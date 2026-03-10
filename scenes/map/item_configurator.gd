extends Node

const WORLD_ITEM_SCENE = preload("res://scenes/items/world_item.tscn")

func place(zone_id: Vector2i = Vector2i.ZERO) -> void:
	var grid_map: GridMap = get_parent()

	if WorldState.is_visited(zone_id):
		var records: Array = WorldState.load_zone_items(zone_id)
		for record in records:
			var local_pos: Vector2i = record["local_pos"]
			var item: MeshInstance3D = WORLD_ITEM_SCENE.instantiate()
			item.item_id = record["id"]
			_apply_sprite(item, record["id"])
			grid_map.add_child(item)
			item.global_position = grid_map.to_global(grid_map.map_to_local(Vector3i(local_pos.x, 0, local_pos.y)))
		return

	var map_generator: Node = grid_map.get_node("MapGenerator")

	for interior in map_generator.home_interiors:
		if randf() < 0.5:
			var cell: Vector2i = interior.pick_random()
			var world_pos := grid_map.to_global(grid_map.map_to_local(Vector3i(cell.x, 0, cell.y)))
			var item: MeshInstance3D = WORLD_ITEM_SCENE.instantiate()
			item.item_id = "military_chest"
			_apply_sprite(item, "military_chest")
			grid_map.add_child(item)
			item.global_position = world_pos

	var item_nodes: Array = []
	for child in grid_map.get_children():
		if child is MeshInstance3D and child.get_script() != null:
			item_nodes.append(child)
	WorldState.save_zone_items(zone_id, item_nodes, grid_map)


func _apply_sprite(item: MeshInstance3D, item_id: String) -> void:
	var data := ItemRegistry.get_item(item_id)
	if not data.has("sprite"):
		return
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = load(data["sprite"])
	item.material_override = mat
