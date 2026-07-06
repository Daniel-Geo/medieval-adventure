extends GridMap

var area_scene: PackedScene = preload("res://scenes/spike_area_3d.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for cell in get_used_cells():
		var tile_id = get_cell_item(cell)
		if tile_id == 2:
			var spawn_position = map_to_local(cell)
			var area_instance = area_scene.instantiate()
			area_instance.position = spawn_position
			add_child(area_instance)
