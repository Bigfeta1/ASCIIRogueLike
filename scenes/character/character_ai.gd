extends Node

enum Disposition { HOSTILE, NEUTRAL, FRIENDLY }
enum LifeState { ALIVE, KNOCKED_OUT, DEAD }
enum BehaviorState { RELAXED, SUSPICIOUS, SLEEPING, PATROL, COMBAT, INVESTIGATE, ALERT, RETURN }
enum FacingDirection { LEFT, RIGHT, UP, DOWN }

var disposition: Disposition = Disposition.NEUTRAL
var life_state: LifeState = LifeState.ALIVE
var behavior_state: BehaviorState = BehaviorState.RELAXED
var facing: FacingDirection = FacingDirection.LEFT

var _movement: Node
var _levels: Node
var _sprite: Node
var _vision: Node
var _combat: Node
var _turn_order: Node
var _player_node: Node  # injected by TurnOrder at registration

const SuspicionLabelScript := preload("res://scenes/character/suspicion_label.gd")

var _astar: AStarGrid2D
var _grid_map: GridMap
var _canvas_layer: CanvasLayer
var _camera: Camera3D

var _patrol_sequence: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(-1, 0), Vector2i(-1, 0),
	Vector2i(0, 1),  Vector2i(0, 1),  Vector2i(0, 1),
	Vector2i(1, 0),  Vector2i(1, 0),  Vector2i(1, 0),
	Vector2i(0, -1), Vector2i(0, -1), Vector2i(0, -1),
]
var _patrol_index: int = 0
var _patrol_origin: Vector2i = Vector2i.ZERO
var _has_patrol_origin: bool = false

var _investigate_target: Vector2i = Vector2i.ZERO
var _spotted_distance: float = 0.0
var _suspicious_turns_remaining: int = 0


func _ready() -> void:
	var character := get_parent()
	if character.character_role == character.CharacterRole.PLAYER:
		return
	_movement = character.get_node("CharacterMovement")
	_levels = character.get_node("CharacterLevels")
	_sprite = character.get_node("CharacterSprite")
	_vision = character.get_node("CharacterVision")
	_combat = character.get_node("CharacterCombat")

func setup(grid_map: GridMap, turn_order: Node, canvas_layer: CanvasLayer, camera: Camera3D) -> void:
	_grid_map = grid_map
	_turn_order = turn_order
	_canvas_layer = canvas_layer
	_camera = camera
	_turn_order.register_enemy(get_parent())
	_build_astar()


func _exit_tree() -> void:
	if _vision != null:
		_vision.clear()
	if _turn_order != null:
		_turn_order.unregister_enemy(get_parent())


# Called by TurnOrder immediately after register_enemy so AI can find the player
# without crawling the scene tree itself.
func set_player(player_node: Node) -> void:
	_player_node = player_node


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
	print("[AI] start_patrol | enemy=%s | from_state=%s" % [get_parent().name, BehaviorState.keys()[behavior_state]])
	print(get_stack())
	if not _has_patrol_origin:
		_patrol_origin = _movement.grid_pos
		_has_patrol_origin = true
	behavior_state = BehaviorState.PATROL
	_patrol_index = 0
	_suspicious_turns_remaining = 0


# Called when a sound wave reaches this enemy's cell.
# intensity ranges from 0 (edge of range) to RADIUS (adjacent to source).
# High-intensity sounds escalate directly to INVESTIGATE; low-intensity sounds
# go to SUSPICIOUS first to allow the enemy to stand down if it was a fluke.
func hear_sound(intensity: int, source_pos: Vector2i) -> void:
	if behavior_state == BehaviorState.COMBAT or behavior_state == BehaviorState.SUSPICIOUS or behavior_state == BehaviorState.INVESTIGATE:
		return
	_investigate_target = source_pos
	if intensity >= 3:
		behavior_state = BehaviorState.INVESTIGATE
	else:
		behavior_state = BehaviorState.SUSPICIOUS
		_suspicious_turns_remaining = 1


func see_player(player_pos: Vector2i, distance: float) -> void:
	if behavior_state == BehaviorState.COMBAT or behavior_state == BehaviorState.ALERT or behavior_state == BehaviorState.SUSPICIOUS:
		print("[AI] see_player blocked | enemy=%s | current_state=%s" % [get_parent().name, BehaviorState.keys()[behavior_state]])
		return
	var vision_range: float = _levels.sympathetic
	if behavior_state == BehaviorState.INVESTIGATE:
		var roll := randi_range(1, int(vision_range))
		var threshold: int = max(1, int(vision_range - distance))
		print("[AI] see_player during INVESTIGATE | enemy=%s | dist=%.1f | roll=%d | threshold=%d | result=%s" % [
			get_parent().name, distance, roll, threshold,
			"ALERT" if roll > threshold else "CONTINUE"
		])
		if roll > threshold:
			behavior_state = BehaviorState.ALERT
			var label: Label = SuspicionLabelScript.new()
			_canvas_layer.add_child(label)
			label.setup(get_parent().position, _camera, "!", Color.RED)
		else:
			_investigate_target = player_pos
		return
	if distance <= vision_range * 0.5:
		print("[AI] see_player | enemy=%s | dist=%.1f | -> ALERT" % [get_parent().name, distance])
		behavior_state = BehaviorState.ALERT
		var label: Label = SuspicionLabelScript.new()
		_canvas_layer.add_child(label)
		label.setup(get_parent().position, _camera, "!", Color.RED)
	else:
		print("[AI] see_player | enemy=%s | from_state=%s | dist=%.1f | -> SUSPICIOUS | target=%s" % [get_parent().name, BehaviorState.keys()[behavior_state], distance, player_pos])
		_investigate_target = player_pos
		_spotted_distance = distance
		behavior_state = BehaviorState.SUSPICIOUS
		_suspicious_turns_remaining = 1
		var label: Label = SuspicionLabelScript.new()
		_canvas_layer.add_child(label)
		label.setup(get_parent().position, _camera)


# After sitting in SUSPICIOUS for the required turn, roll to escalate or stand down.
# Close to target → more likely to investigate. Far → more likely to resume patrol.
func _resolve_suspicion() -> void:
	var vision_range: float = _levels.sympathetic
	var roll := randi_range(1, int(vision_range))
	var threshold: int = max(1, int(vision_range - _spotted_distance))
	print("[AI] _resolve_suspicion | enemy=%s | spotted_dist=%.1f | vision_range=%.1f | roll=%d | threshold=%d | result=%s" % [
		get_parent().name, _spotted_distance, vision_range, roll, threshold,
		"INVESTIGATE" if roll <= threshold else "PATROL"
	])
	if roll <= threshold:
		behavior_state = BehaviorState.INVESTIGATE
	else:
		start_patrol()


func _check_vision() -> void:
	if behavior_state == BehaviorState.COMBAT or behavior_state == BehaviorState.ALERT:
		return
	if _player_node == null:
		return
	var player_pos: Vector2i = _player_node.get_node("CharacterMovement").grid_pos
	if _vision.can_see(player_pos):
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
	_sprite.face(
		_sprite.FacingState.RIGHT if facing == FacingDirection.RIGHT else _sprite.FacingState.LEFT,
		_sprite.FacingState.RIGHT
	)


# Returns the unit vector for the current facing direction.
# Used by CharacterVision for cone calculations.
func facing_vector() -> Vector2:
	match facing:
		FacingDirection.LEFT:  return Vector2(-1, 0)
		FacingDirection.RIGHT: return Vector2(1, 0)
		FacingDirection.UP:    return Vector2(0, -1)
		FacingDirection.DOWN:  return Vector2(0, 1)
	return Vector2(-1, 0)


func take_turn_step() -> void:
	if life_state != LifeState.ALIVE:
		return
	match behavior_state:
		BehaviorState.PATROL:
			var delta: Vector2i = _patrol_sequence[_patrol_index]
			_update_facing(delta)
			_check_vision()
			_movement.step(delta)
			_patrol_index = (_patrol_index + 1) % _patrol_sequence.size()
		BehaviorState.SUSPICIOUS:
			_suspicious_turns_remaining -= 1
			if _suspicious_turns_remaining <= 0:
				_resolve_suspicion()
		BehaviorState.ALERT:
			if _player_node == null:
				return
			var player_pos: Vector2i = _player_node.get_node("CharacterMovement").grid_pos
			var to_player: Vector2i = player_pos - _movement.grid_pos
			if abs(to_player.x) <= 1 and abs(to_player.y) <= 1 and to_player != Vector2i.ZERO:
				_update_facing(to_player)
				_combat._apply_damage(_player_node)
				_combat.bump_attack(player_pos)
			else:
				var path := _astar.get_id_path(_movement.grid_pos, player_pos)
				if path.size() >= 2:
					var step_delta: Vector2i = path[1] - _movement.grid_pos
					_update_facing(step_delta)
					_movement.step(step_delta)
		BehaviorState.COMBAT:
			if _player_node == null:
				return
			var player_pos: Vector2i = _player_node.get_node("CharacterMovement").grid_pos
			var to_player: Vector2i = player_pos - _movement.grid_pos
			if abs(to_player.x) <= 1 and abs(to_player.y) <= 1 and to_player != Vector2i.ZERO:
				_update_facing(to_player)
				_combat._apply_damage(_player_node)
				_combat.bump_attack(player_pos)
		BehaviorState.INVESTIGATE:
			if _movement.grid_pos == _investigate_target:
				behavior_state = BehaviorState.RETURN
			else:
				var path := _astar.get_id_path(_movement.grid_pos, _investigate_target)
				if path.size() >= 2:
					var step_delta: Vector2i = path[1] - _movement.grid_pos
					_update_facing(step_delta)
					_check_vision()
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
					_check_vision()
					_movement.step(step_delta)
				else:
					start_patrol()
	_vision.update(disposition)
