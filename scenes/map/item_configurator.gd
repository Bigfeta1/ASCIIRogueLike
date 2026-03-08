extends Node

const WORLD_ITEM_SCENE = preload("res://scenes/items/world_item.tscn")
const ITEM_DATA_PATH = "res://data/world_items.json"

func place(zone_id: Vector2i = Vector2i.ZERO) -> void:
	var grid_map: GridMap = get_parent()

	if WorldState.is_visited(zone_id):
		var records: Array = WorldState.load_zone_items(zone_id)
		for record in records:
			var local_pos: Vector2i = record["local_pos"]
			var item: Node = WORLD_ITEM_SCENE.instantiate()
			item.name = record["id"]
			grid_map.add_child(item)
			item.global_position = grid_map.to_global(grid_map.map_to_local(Vector3i(local_pos.x, 0, local_pos.y)))
		return

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

	var item_nodes: Array = []
	for child in grid_map.get_children():
		if child is MeshInstance3D:
			item_nodes.append(child)
	WorldState.save_zone_items(zone_id, item_nodes, grid_map)
