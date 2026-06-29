extends CharacterBody3D

# Player node refrences
@onready var head: Node3D = $Head
@onready var collision_shape_3d: CollisionShape3D = $CollisionShape3D
@onready var ray_cast_3d: RayCast3D = $RayCast3D

# Player nodes movement state properties
@onready var head_position_y: float = head.position.y
@onready var collision_shape_3d_height: float = (collision_shape_3d.shape as CapsuleShape3D).height
@onready var collision_shape_3d_position_y: float = collision_shape_3d.position.y

# Speed variables
@export var walking_speed := 5.0
@export var sprint_speed := 8.0
@export var crouch_speed := 3.0

# Movement variables
@export var lerp_speed := 10.0
@export var crouching_depth := 0.5
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.4

# Input variables
var current_speed: float
var direction: Vector3 = Vector3.ZERO


func _ready():
	# Lock mouse position and hide the cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _input(event: InputEvent) -> void:
	# Capture mouse motion and rotate the player and its head based on it
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x) * mouse_sensitivity)
		head.rotate_x(deg_to_rad(-event.relative.y) * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))


func _physics_process(delta: float) -> void:
	handle_movement_state(delta)

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity

	# Get the input direction and handle the movement/deceleration.
	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	direction = lerp(direction, (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), delta * lerp_speed)
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()


## Handles crouch/stand/sprint states along with the capsule dimentions accordingly
func handle_movement_state(delta: float) -> void:
	# Crouching
	if Input.is_action_pressed("crouch"):
		current_speed = crouch_speed
		head.position.y = lerp(head.position.y, head_position_y - crouching_depth, delta * lerp_speed)
		collision_shape_3d.shape.height = collision_shape_3d_height - crouching_depth

	# Standing if not colliding
	elif !ray_cast_3d.is_colliding():
		head.position.y = lerp(head.position.y, head_position_y, delta * lerp_speed)
		collision_shape_3d.position.y = collision_shape_3d_position_y
		collision_shape_3d.shape.height = collision_shape_3d_height

		# Sprinting
		current_speed = sprint_speed if Input.is_action_pressed("sprint") else walking_speed
