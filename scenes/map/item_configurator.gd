extends Node

const WORLD_ITEM_SCENE = preload("res://scenes/items/world_item.tscn")
const ITEM_DATA_PATH = "res://data/world_items.json"

func place() -> void:
	var grid_map: GridMap = get_parent()
	var map_generator: Node = grid_map.get_node("MapGenerator")

	var file := FileAccess.open(ITEM_DATA_PATH, FileAccess.READ)
	var item_defs: Array = JSON.parse_string(file.get_as_text())
	file.close()

	var chest_def: Dictionary = {}
	for def in item_defs:
		if def["id"] == "military_chest":
			chest_def = def
			break

	for interior in map_generator.home_interiors:
		if randf() < 0.5:
			var cell: Vector2i = interior.pick_random()
			var world_pos := grid_map.to_global(grid_map.map_to_local(Vector3i(cell.x, 0, cell.y)))
			var item: Node = WORLD_ITEM_SCENE.instantiate()
			item.name = chest_def["id"]
			grid_map.add_child(item)
			item.global_position = world_pos
