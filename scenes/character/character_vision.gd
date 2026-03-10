extends Node

# CharacterVision owns the LOS overlay tiles on the GridMap.
# CharacterAI calls update() after each turn step; it does not touch GridMap tiles directly.
# Perception logic (can_see) also lives here since it is the authoritative source
# of what this character can observe.

const LOS_TILE = 4

var _movement: Node
var _levels: Node
var _ai: Node
var _grid_map: GridMap
var _occupancy_map: Node
var _vision_cells: Array[Vector3i] = []


func _ready() -> void:
	var character := get_parent()
	if character.character_role == character.CharacterRole.PLAYER:
		return
	_movement = character.get_node("CharacterMovement")
	_levels = character.get_node("CharacterLevels")
	_ai = character.get_node("CharacterAI")

func setup(grid_map: GridMap, occupancy_map: Node) -> void:
	_grid_map = grid_map
	_occupancy_map = occupancy_map


func can_see(target_pos: Vector2i) -> bool:
	var origin: Vector2i = _movement.grid_pos
	if origin == target_pos:
		return true
	var vision_range: int = _levels.sympathetic
	if origin.distance_to(target_pos) > vision_range:
		return false
	var half_angle: float = deg_to_rad(_levels.sympathetic * 7.0 / 2.0)
	var facing_vec: Vector2 = _ai.facing_vector()
	var to_target: Vector2 = Vector2(target_pos - origin).normalized()
	if absf(facing_vec.angle_to(to_target)) > half_angle:
		return false
	for cell in _bresenham(origin, target_pos):
		if cell == origin or cell == target_pos:
			continue
		var cell3 := Vector3i(cell.x, 0, cell.y)
		var tile_id := TileRegistry.get_original_tile(cell3, _grid_map.get_cell_item(cell3))
		if TileRegistry.blocks_vision(tile_id):
			return false
		if _occupancy_map.is_solid(cell):
			return false
	return true


func clear() -> void:
	for cell in _vision_cells:
		TileRegistry.vision_release(cell, _grid_map)
	_vision_cells.clear()


func update(disposition: int) -> void:
	clear()
	# Only hostile characters project a visible LOS overlay.
	if disposition != _ai.Disposition.HOSTILE:
		return
	var origin: Vector2i = _movement.grid_pos
	var vision_range: int = _levels.sympathetic
	for x in range(origin.x - vision_range, origin.x + vision_range + 1):
		for y in range(origin.y - vision_range, origin.y + vision_range + 1):
			var target := Vector2i(x, y)
			if not can_see(target):
				continue
			var cell := Vector3i(x, 0, y)
			var tile_id := _grid_map.get_cell_item(cell)
			if tile_id == GridMap.INVALID_CELL_ITEM:
				continue
			var true_tile := TileRegistry.get_original_tile(cell, tile_id)
			if not TileRegistry.is_walkable(true_tile):
				continue
			TileRegistry.vision_claim(cell, tile_id)
			_grid_map.set_cell_item(cell, LOS_TILE)
			_vision_cells.append(cell)


func _bresenham(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var dx: int = abs(to.x - from.x)
	var dy: int = abs(to.y - from.y)
	var x: int = from.x
	var y: int = from.y
	var sx: int = 1 if to.x > from.x else -1
	var sy: int = 1 if to.y > from.y else -1
	var err: int = dx - dy
	while true:
		cells.append(Vector2i(x, y))
		if x == to.x and y == to.y:
			break
		var e2: int = err * 2
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
	return cells
