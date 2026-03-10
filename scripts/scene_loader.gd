extends Node

signal map_generated
signal items_placed
signal characters_spawned
signal load_complete

var _main: Node
var _grid_map: GridMap
var _map_generator: Node
var _item_configurator: Node
var _enemy_configurator: Node
var _loaded: bool = false

func _ready() -> void:
	await get_tree().process_frame
	var main := get_tree().root.get_node_or_null("MainScene")
	if main and not _loaded:
		load_game(main)

func load_game(main: Node) -> void:
	_loaded = true
	_main = main
	_grid_map = main.get_node("GridMap")
	_map_generator = _grid_map.get_node("MapGenerator")
	_item_configurator = _grid_map.get_node("ItemConfigurator")
	_enemy_configurator = _grid_map.get_node("EnemyConfigurator")

	_map_generator.generate()
	map_generated.emit()

	await _item_configurator.place()
	items_placed.emit()

	await _spawn_characters()
	characters_spawned.emit()

	WorldState.mark_visited(Vector2i.ZERO)
	_main.get_node("Character/CharacterMovement").zone_exit.connect(_on_zone_exit)

	load_complete.emit()

func _spawn_characters() -> void:
	var player := _main.get_node("Character")
	player.get_node("CharacterMovement").place(Vector2i(0, 0))
	player.get_node("CharacterInventory").add_item("flask")
	await _enemy_configurator.spawn()

func _on_zone_exit(direction: Vector2i) -> void:
	var player_movement := _main.get_node("Character/CharacterMovement")
	var current_zone: Vector2i = player_movement.zone
	var player_local: Vector2i = player_movement.grid_pos

	# Advance time and run enemy turns before tearing down the zone
	var map_params := _grid_map.get_node("MapParameters")
	var turn_order := _main.get_node("GameLogic/TurnOrder")
	for enemy in turn_order.get_enemies():
		enemy.get_node("CharacterAI").take_turn_step()
		enemy.get_node("CharacterVitals").tick_regen()
	WorldState.tick_off_screen_enemies()
	map_params.advance_time(15)
	_main.get_node("Character/CharacterVitals").tick_regen()

	# Serialize all live enemies and remove them
	var player := _main.get_node("Character")
	var enemies_to_free: Array = []
	for child in _main.get_children():
		if child != player and child.get_node_or_null("CharacterAI") != null and child.character_type != child.CharacterType.STRUCTURE:
			enemies_to_free.append(child)
	for enemy in enemies_to_free:
		WorldState.add_off_screen_enemy(WorldState.serialize_enemy(enemy, current_zone))
		enemy.queue_free()

	# Serialize items and remove them
	var items_to_free: Array = []
	for child in _grid_map.get_children():
		if child is MeshInstance3D:
			items_to_free.append(child)
	WorldState.save_zone_items(current_zone, items_to_free, _grid_map)
	for item in items_to_free:
		item.queue_free()

	# Save and clear structures
	var structures_to_free: Array = get_tree().get_nodes_in_group("structures")
	WorldState.save_zone_structures(current_zone, structures_to_free)
	for s in structures_to_free:
		s.queue_free()

	# Clear TileRegistry overlay state and occupancy before wiping the grid
	# (queue_free is deferred so _exit_tree hasn't run yet — clear manually)
	TileRegistry.clear_state()
	_grid_map.get_node("OccupancyMap").clear()
	_grid_map.clear()

	# Compute new zone and player entry position on the opposite edge
	var new_zone: Vector2i = current_zone + direction
	var entry_local: Vector2i
	if direction.x == 1:
		entry_local = Vector2i(-40, player_local.y)
	elif direction.x == -1:
		entry_local = Vector2i(39, player_local.y)
	elif direction.y == 1:
		entry_local = Vector2i(player_local.x, -20)
	else:
		entry_local = Vector2i(player_local.x, 19)

	_map_generator.generate(new_zone)
	await _item_configurator.place(new_zone)
	await _enemy_configurator.spawn(new_zone)

	player_movement.place(_find_walkable_near(entry_local), new_zone)
	WorldState.mark_visited(new_zone)
	WorldState.current_zone = new_zone

func _find_walkable_near(pos: Vector2i) -> Vector2i:
	for radius in range(0, 20):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dy) != radius:
					continue
				var candidate := pos + Vector2i(dx, dy)
				var cell := Vector3i(candidate.x, 0, candidate.y)
				var tile_id := _grid_map.get_cell_item(cell)
				if tile_id == GridMap.INVALID_CELL_ITEM:
					continue
				var true_tile := TileRegistry.get_original_tile(cell, tile_id)
				if TileRegistry.is_walkable(true_tile):
					return candidate
	return Vector2i(0, 0)
