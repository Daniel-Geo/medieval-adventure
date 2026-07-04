extends CharacterBody3D

# Speed variables
@export_group("Speed settings")
@export var walking_speed := 5.0
@export var sprint_speed := 8.0
@export var crouch_speed := 3.0

# Movement variables
@export_group("Movement settings")
@export var lerp_speed := 10.0
@export var air_lerp_speed := 3.0
@export var crouching_depth := 0.5
@export var max_step_height := 0.5
@export var jump_velocity := 4.5
@export var free_look_tilt_amount := 5.0
@export var mouse_sensitivity := 0.4

# Slide variables
@export_group("Sliding settings")
@export var slide_speed := 10.0
@export var slide_timer_max := 1.0
var slide_timer := 0.0
var slide_vector := Vector2.ZERO

# Head bobbing variables
@export_group("Head bobbing settings")
@export_subgroup("Head Bobbing speed settings")
@export var head_bobbing_sprinting_speed := 22.0
@export var head_bobbing_walking_speed := 14.0
@export var head_bobbing_crouching_speed := 10.0

@export_subgroup("Head bobbing intensity settings")
@export var head_bobbing_sprinting_intensity := 0.2
@export var head_bobbing_walking_intensity := 0.1
@export var head_bobbing_crouching_intensity := 0.05

var head_bobbing_current_intensity := 0.0
var head_bobbing_vector := Vector2.ZERO
var head_bobbing_index := 0.0

# Input variables
var current_speed: float
var last_velocity := Vector3.ZERO
var input_dir: Vector2
var direction := Vector3.ZERO
var snapped_to_stairs_last_frame := false
var last_frame_was_on_floor := -1

# States
var walking := false
var sprinting := false
var crouching := false
var free_looking := false
var sliding := false

# Player node refrences
@onready var neck: Node3D = $Neck
@onready var head: Node3D = $Neck/Head
@onready var eyes: Node3D = $Neck/Head/Eyes
@onready var camera_smooth: Node3D = $Neck/Head/Eyes/CameraSmooth
@onready var camera_3d: Camera3D = $Neck/Head/Eyes/CameraSmooth/Camera3D
@onready var collision_shape_3d: CollisionShape3D = $CollisionShape3D
@onready var ray_cast_3d: RayCast3D = $RayCast3D
@onready var stairs_below_ray_cast: RayCast3D = $StairsBelowRayCast
@onready var stairs_ahead_ray_cast: RayCast3D = $StairsAheadRayCast
@onready var animation_player: AnimationPlayer = $AnimationPlayer

# Player nodes movement state properties
@onready var collision_shape_3d_height: float = (collision_shape_3d.shape as CapsuleShape3D).height
@onready var collision_shape_3d_position_y: float = collision_shape_3d.position.y

var saved_camera_global_pos = null


func _ready():
	# Lock mouse position and hide the cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _input(event: InputEvent) -> void:
	# Capture mouse motion and rotate the player and its head based on it
	if event is InputEventMouseMotion:
		if free_looking:
			neck.rotate_y(deg_to_rad(-event.relative.x) * mouse_sensitivity)
			neck.rotation.y = clamp(neck.rotation.y, deg_to_rad(-120), deg_to_rad(120))
		else:
			rotate_y(deg_to_rad(-event.relative.x) * mouse_sensitivity)
		head.rotate_x(deg_to_rad(-event.relative.y) * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))


func snap_down_to_stairs_check() -> void:
	var did_snap := false
	var floor_below: bool = stairs_below_ray_cast.is_colliding() and not is_surface_steep(stairs_below_ray_cast.get_collision_normal())
	
	var was_on_floor_last_frame := Engine.get_physics_frames() - last_frame_was_on_floor == 1
	if not is_on_floor() and velocity.y <= 0 and (was_on_floor_last_frame or snapped_to_stairs_last_frame) and floor_below:
		var body_test_result = PhysicsTestMotionResult3D.new()
		if run_body_test_motion(global_transform, Vector3(0, -max_step_height, 0), body_test_result):
			save_camera_pos_for_smoothing()
			var translate_y = body_test_result.get_travel().y
			position.y += translate_y
			apply_floor_snap()
			did_snap = true
	snapped_to_stairs_last_frame = did_snap


func snap_up_stairs_check(delta) -> bool:
	if not is_on_floor() and not snapped_to_stairs_last_frame: return false
	var expected_move_motion = velocity * Vector3(1, 0, 1) * delta
	var step_pos_with_clearance = global_transform.translated(expected_move_motion + Vector3(0, max_step_height * 2, 0))
	var down_check_result = PhysicsTestMotionResult3D.new()
	if (run_body_test_motion(step_pos_with_clearance, Vector3(0, max_step_height * 2, 0), down_check_result)
	and (down_check_result.get_collider().is_class("StaticBody3D") or down_check_result.get_collider().is_class("CSGShape3S"))):
		var step_height =  ((step_pos_with_clearance.origin + down_check_result.get_travel()) - global_position).y
		if step_height > max_step_height or step_height <= 0.01 or (down_check_result.get_collision_point() - global_position).y > max_step_height: return false
		stairs_ahead_ray_cast.global_position = down_check_result.get_collision_point() + Vector3(0, max_step_height, 0) + expected_move_motion.normalized() * 0.1
		stairs_ahead_ray_cast.force_raycast_update()
		if stairs_ahead_ray_cast.is_colliding() and not is_surface_steep(stairs_ahead_ray_cast.get_collision_normal()):
			save_camera_pos_for_smoothing()
			global_position = step_pos_with_clearance.origin + down_check_result.get_travel()
			apply_floor_snap()
			snapped_to_stairs_last_frame = true
			return true
	return false


func save_camera_pos_for_smoothing():
	if saved_camera_global_pos == null:
		saved_camera_global_pos = camera_smooth.global_position


func slide_camera_smooth_back_to_origin(delta):
	if saved_camera_global_pos == null: return
	camera_smooth.global_position.y = saved_camera_global_pos.y
	camera_smooth.position.y = clampf(camera_smooth.position.y, -0.7, 0.7)
	var move_amount =  max(velocity.length() * delta, current_speed/2 * delta)
	camera_smooth.position.y = move_toward(camera_smooth.position.y, 0.0, move_amount)
	saved_camera_global_pos = camera_smooth.global_position
	if camera_smooth.position.y == 0:
		saved_camera_global_pos = null


func _physics_process(delta: float) -> void:
	if is_on_floor(): last_frame_was_on_floor = Engine.get_physics_frames()
	

	# Get the input direction
	input_dir = Input.get_vector("left", "right", "forward", "backward")

	handle_movement_state(delta)

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and (is_on_floor() or snapped_to_stairs_last_frame):
		velocity.y = jump_velocity
		animation_player.play("jump")
		sliding = false

	# Handle the movement direction.
	if is_on_floor():
		direction = lerp(direction, (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), delta * lerp_speed)

		# Handle landing
		if last_velocity.y < -10.0:
			animation_player.play("roll")
		elif last_velocity.y < -4.0:
			animation_player.play("landing")

	else:
		if input_dir != Vector2.ZERO:
			direction = lerp(direction, (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), delta * air_lerp_speed)

	# Handle the movement direction while sliding
	if sliding:
		direction = (transform.basis * Vector3(slide_vector.x, 0, slide_vector.y)).normalized()
		current_speed = (slide_timer + 0.1) * slide_speed

	# Handle the movement
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	last_velocity = velocity

	if not snap_up_stairs_check(delta):
		move_and_slide()
		snap_down_to_stairs_check()

	slide_camera_smooth_back_to_origin(delta)


## Handles crouch/stand/sprint states and other substates along with the capsule dimentions accordingly
func handle_movement_state(delta: float) -> void:
	# Crouching
	if Input.is_action_pressed("crouch") or sliding:
		current_speed = lerp(current_speed, crouch_speed, delta * lerp_speed)
		head.position.y = lerp(head.position.y, -crouching_depth, delta * lerp_speed)
		collision_shape_3d.shape.height = collision_shape_3d_height - crouching_depth
		collision_shape_3d.position.y = collision_shape_3d_position_y - (crouching_depth / 2.0)

		# Sliding
		if sprinting and input_dir != Vector2.ZERO:
			sliding = true
			slide_timer = slide_timer_max
			slide_vector = input_dir
			free_looking = true

		walking = false
		sprinting = false
		crouching = true

	# Standing if not colliding
	elif not ray_cast_3d.is_colliding():
		head.position.y = lerp(head.position.y, 0.0, delta * lerp_speed)
		collision_shape_3d.position.y = collision_shape_3d_position_y
		collision_shape_3d.shape.height = collision_shape_3d_height

		# Sprinting
		if Input.is_action_pressed("sprint"):
			current_speed = lerp(current_speed, sprint_speed, delta * lerp_speed)

			walking = false
			sprinting = true
			crouching = false

		# Walking
		else:
			current_speed = lerp(current_speed, walking_speed, delta * lerp_speed)

			walking = true
			sprinting = false
			crouching = false

	# Handle free locking
	if Input.is_action_pressed("free_look") or sliding:
		free_looking = true

		# Handle sliding camera tilt
		if sliding:
			eyes.rotation.z = lerp(eyes.rotation.z, -deg_to_rad(7.0), delta * lerp_speed)
		else:
			eyes.rotation.z = -deg_to_rad(neck.rotation.y) * free_look_tilt_amount

	else:
		free_looking = false
		neck.rotation.y = lerp(neck.rotation.y, 0.0, delta * lerp_speed)
		eyes.rotation.z = lerp(eyes.rotation.z, 0.0, delta * lerp_speed)

	# Handle sliding
	if sliding:
		slide_timer -= delta
		if slide_timer <= 0.0:
			sliding = false
			free_looking = false

	# Head bobbing
	if sprinting:
		head_bobbing_current_intensity = head_bobbing_sprinting_intensity
		head_bobbing_index += head_bobbing_sprinting_speed * delta
	elif walking:
		head_bobbing_current_intensity = head_bobbing_walking_intensity
		head_bobbing_index += head_bobbing_walking_speed * delta
	elif crouching:
		head_bobbing_current_intensity = head_bobbing_crouching_intensity
		head_bobbing_index += head_bobbing_crouching_speed * delta

	# Handle head bobbing
	if is_on_floor() and not sliding and input_dir != Vector2.ZERO:
		head_bobbing_vector.x = sin(head_bobbing_index)
		head_bobbing_vector.y = sin(head_bobbing_index/2) + 0.5

		eyes.position.x = lerp(eyes.position.x, head_bobbing_vector.x * head_bobbing_current_intensity, delta * lerp_speed)
		eyes.position.y = lerp(eyes.position.y, head_bobbing_vector.y * (head_bobbing_current_intensity / 2.0), delta * lerp_speed)

	else:
		eyes.position.x = lerp(eyes.position.x, 0.0, delta * lerp_speed)
		eyes.position.y = lerp(eyes.position.y, 0.0, delta * lerp_speed)


func is_surface_steep(normal: Vector3) -> bool:
	return normal.angle_to(Vector3.UP) > floor_max_angle

func run_body_test_motion(from: Transform3D, motion: Vector3, result = null) -> bool:
	if not result: result = PhysicsTestMotionResult3D.new()
	var params = PhysicsTestMotionParameters3D.new()
	params.from = from
	params.motion = motion
	return PhysicsServer3D.body_test_motion(get_rid(), params, result)
