extends Node

enum Disposition { HOSTILE, NEUTRAL, FRIENDLY }
enum BehaviorState { RELAXED, SUSPICIOUS, SLEEPING, PATROL, COMBAT, INVESTIGATE, ALERT, RETURN }
enum FacingDirection { LEFT, RIGHT, UP, DOWN }

const LOS_TILE = 4

var disposition: Disposition = Disposition.NEUTRAL
var behavior_state: BehaviorState = BehaviorState.RELAXED
var facing: FacingDirection = FacingDirection.LEFT

var _movement: Node
var _turn_order: Node
var _grid_map: GridMap
var _levels: Node
var _vision_cells: Array[Vector3i] = []
var _astar: AStarGrid2D
var _patrol_sequence: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(-1, 0), Vector2i(-1, 0),
	Vector2i(0, 1),  Vector2i(0, 1),  Vector2i(0, 1),
	Vector2i(1, 0),  Vector2i(1, 0),  Vector2i(1, 0),
	Vector2i(0, -1), Vector2i(0, -1), Vector2i(0, -1),
]
var _patrol_index: int = 0
var _investigate_target: Vector2i = Vector2i.ZERO
var _patrol_origin: Vector2i = Vector2i.ZERO
var _suspicious_turns_remaining: int = 0

func _ready() -> void:
	var character := get_parent()
	if character.character_role == character.CharacterRole.PLAYER:
		return
	_movement = character.get_node("CharacterMovement")
	_levels = character.get_node("CharacterLevels")
	_grid_map = character.get_parent().get_node("GridMap")
	_turn_order = character.get_parent().get_node("GameLogic/TurnOrder")
	_turn_order.register_enemy(character)
	_build_astar()

func _exit_tree() -> void:
	_clear_vision_tiles()
	if _turn_order != null:
		_turn_order.unregister_enemy(get_parent())

func _build_astar() -> void:
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(-40, -20, 80, 40)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for x in range(-40, 40):
		for y in range(-20, 20):
			var cell := Vector3i(x, 0, y)
			var tile_id := TileRegistry.get_original_tile(cell, _grid_map.get_cell_item(cell))
			if not TileRegistry.is_walkable(tile_id):
				_astar.set_point_solid(Vector2i(x, y), true)

func start_patrol() -> void:
	if _patrol_origin == Vector2i.ZERO:
		_patrol_origin = _movement.grid_pos
	behavior_state = BehaviorState.PATROL
	_patrol_index = 0
	_suspicious_turns_remaining = 0

# Called when a sound wave reaches this enemy's cell.
# intensity: 0 (edge of range) to RADIUS (adjacent to source).
# Close sounds always escalate. Far sounds may resolve back to patrol after suspicion.
func hear_sound(intensity: int, source_pos: Vector2i) -> void:
	if behavior_state == BehaviorState.COMBAT or behavior_state == BehaviorState.SUSPICIOUS:
		return
	_investigate_target = source_pos
	behavior_state = BehaviorState.SUSPICIOUS
	_suspicious_turns_remaining = 1

func see_player(player_pos: Vector2i, distance: float) -> void:
	if behavior_state == BehaviorState.COMBAT or behavior_state == BehaviorState.ALERT or behavior_state == BehaviorState.SUSPICIOUS:
		return
	var vision_range: float = _levels.sympathetic
	if distance <= vision_range * 0.5:
		behavior_state = BehaviorState.ALERT
	else:
		_investigate_target = player_pos
		behavior_state = BehaviorState.SUSPICIOUS
		_suspicious_turns_remaining = 1

# After sitting in SUSPICIOUS for the required turn, roll to escalate or stand down.
# Close to target → more likely to investigate. Far → more likely to resume patrol.
func _resolve_suspicion() -> void:
	var dist: float = _movement.grid_pos.distance_to(_investigate_target)
	var vision_range: float = _levels.sympathetic
	# Roll 1d(range+1): succeed (investigate) if roll <= (range - dist + 1)
	var roll := randi_range(1, int(vision_range) + 1)
	if roll <= int(vision_range - dist) + 1:
		behavior_state = BehaviorState.INVESTIGATE
	else:
		start_patrol()

func can_see(target_pos: Vector2i) -> bool:
	var origin: Vector2i = _movement.grid_pos
	if origin == target_pos:
		return true
	var vision_range: int = _levels.sympathetic
	if origin.distance_to(target_pos) > vision_range:
		return false
	var half_angle: float = deg_to_rad(_levels.sympathetic * 7.0 / 2.0)
	var facing_vec: Vector2 = _facing_vector()
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
	return true

func _facing_vector() -> Vector2:
	match facing:
		FacingDirection.LEFT:  return Vector2(-1, 0)
		FacingDirection.RIGHT: return Vector2(1, 0)
		FacingDirection.UP:    return Vector2(0, -1)
		FacingDirection.DOWN:  return Vector2(0, 1)
	return Vector2(-1, 0)

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

func _clear_vision_tiles() -> void:
	for cell in _vision_cells:
		TileRegistry.vision_release(cell, _grid_map)
	_vision_cells.clear()

func _update_vision_tiles() -> void:
	_clear_vision_tiles()
	if disposition != Disposition.HOSTILE:
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

func _check_vision() -> void:
	if behavior_state == BehaviorState.COMBAT or behavior_state == BehaviorState.ALERT:
		return
	var player := get_parent().get_parent().get_node_or_null("Character")
	if player == null:
		return
	var player_pos: Vector2i = player.get_node("CharacterMovement").grid_pos
	if can_see(player_pos):
		var dist: float = _movement.grid_pos.distance_to(player_pos)
		see_player(player_pos, dist)

func _update_facing(delta: Vector2i) -> void:
	if delta.x < 0:
		facing = FacingDirection.LEFT
	elif delta.x > 0:
		facing = FacingDirection.RIGHT
	elif delta.y < 0:
		facing = FacingDirection.UP
	elif delta.y > 0:
		facing = FacingDirection.DOWN
	var sprite := get_parent().get_node("CharacterSprite")
	sprite.face(sprite.FacingState.RIGHT if facing == FacingDirection.RIGHT else sprite.FacingState.LEFT, sprite.FacingState.RIGHT)

func take_turn_step() -> void:
	_check_vision()
	match behavior_state:
		BehaviorState.PATROL:
			var delta: Vector2i = _patrol_sequence[_patrol_index]
			_update_facing(delta)
			_movement.step(delta)
			_patrol_index = (_patrol_index + 1) % _patrol_sequence.size()
		BehaviorState.SUSPICIOUS:
			_suspicious_turns_remaining -= 1
			if _suspicious_turns_remaining <= 0:
				_resolve_suspicion()
		BehaviorState.COMBAT:
			var player := get_parent().get_parent().get_node("Character")
			var player_pos: Vector2i = player.get_node("CharacterMovement").grid_pos
			var to_player: Vector2i = player_pos - _movement.grid_pos
			if abs(to_player.x) <= 1 and abs(to_player.y) <= 1 and to_player != Vector2i.ZERO:
				_update_facing(to_player)
				var combat := get_parent().get_node("CharacterCombat")
				combat._apply_damage(player)
				combat.bump_attack(player_pos)
		BehaviorState.INVESTIGATE:
			if _movement.grid_pos == _investigate_target:
				behavior_state = BehaviorState.RETURN
			else:
				var path := _astar.get_id_path(_movement.grid_pos, _investigate_target)
				if path.size() >= 2:
					var step_delta: Vector2i = path[1] - _movement.grid_pos
					_update_facing(step_delta)
					_movement.step(step_delta)
				else:
					behavior_state = BehaviorState.RETURN
		BehaviorState.RETURN:
			if _movement.grid_pos == _patrol_origin:
				start_patrol()
			else:
				var path := _astar.get_id_path(_movement.grid_pos, _patrol_origin)
				if path.size() >= 2:
					var step_delta: Vector2i = path[1] - _movement.grid_pos
					_update_facing(step_delta)
					_movement.step(step_delta)
				else:
					start_patrol()
	_update_vision_tiles()
