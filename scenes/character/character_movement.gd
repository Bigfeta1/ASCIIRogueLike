extends Node

signal moved
signal waited
signal zone_exit(direction: Vector2i)

var grid_pos: Vector2i = Vector2i.ZERO
var zone: Vector2i = Vector2i.ZERO
var facing_state: int  # CharacterSprite.FacingState

var _held_keys: Dictionary = {}
var _move_pending: bool = false

var _character: Node
var _sprite: Node
var _grid_map: GridMap
var _look_cursor: Node
var _interact_cursor: Node
var _turn_order: Node



func _ready() -> void:
	_character = get_parent()
	_sprite = _character.get_node("CharacterSprite")
	_grid_map = _character.get_parent().get_node("GridMap")
	_look_cursor = _character.get_node("LookCursor")
	_interact_cursor = _character.get_node("InteractCursor")
	if _character.character_role == _character.CharacterRole.PLAYER:
		_turn_order = _character.get_parent().get_node("GameLogic/TurnOrder")
	facing_state = _sprite.FacingState.RIGHT
	_snap()

func _unhandled_input(event: InputEvent) -> void:
	if _character.character_role != _character.CharacterRole.PLAYER:
		return
	if not event is InputEventKey:
		return
	if event.keycode == KEY_SPACE and event.pressed:
		if _turn_order.current_turn_state == _turn_order.TurnState.PLAYER_TURN:
			if _character.action_state == _character.ActionState.MOVEMENT:
				waited.emit()
		return
	var dir_keys := [KEY_D, KEY_RIGHT, KEY_A, KEY_LEFT, KEY_S, KEY_DOWN, KEY_W, KEY_UP]
	if not event.keycode in dir_keys:
		return
	print("[MOVEMENT INPUT] keycode=%d pressed=%s echo=%s action_state=%d interaction_sub_state=%d" % [
		event.keycode, event.pressed, event.echo,
		_character.action_state, _character.interaction_sub_state
	])
	if not event.pressed:
		_held_keys.erase(event.keycode)
		print("[MOVEMENT INPUT] key released, held_keys=%s" % str(_held_keys))
		return
	if _turn_order.current_turn_state != _turn_order.TurnState.PLAYER_TURN:
		print("[MOVEMENT INPUT] blocked — not player turn")
		return
	_held_keys[event.keycode] = true
	print("[MOVEMENT INPUT] added to held_keys=%s move_pending will be=%s" % [str(_held_keys), not event.echo])
	if not event.echo:
		_move_pending = true
	else:
		_do_move()

func _process(_delta: float) -> void:
	if _move_pending:
		_move_pending = false
		_do_move()

func _do_move() -> void:
	var dx := int(_held_keys.get(KEY_D, false) or _held_keys.get(KEY_RIGHT, false)) - int(_held_keys.get(KEY_A, false) or _held_keys.get(KEY_LEFT, false))
	var dy := int(_held_keys.get(KEY_S, false) or _held_keys.get(KEY_DOWN, false)) - int(_held_keys.get(KEY_W, false) or _held_keys.get(KEY_UP, false))
	var delta := Vector2i(dx, dy)
	print("[DO_MOVE] delta=%s action_state=%d interaction_sub_state=%d held_keys=%s" % [
		str(delta), _character.action_state, _character.interaction_sub_state, str(_held_keys)
	])
	if delta == Vector2i.ZERO:
		print("[DO_MOVE] delta zero, returning")
		return
	if _character.action_state == _character.ActionState.MOVEMENT:
		print("[DO_MOVE] -> _check_move")
		_check_move(delta)
	elif _character.action_state == _character.ActionState.LOOK:
		print("[DO_MOVE] -> look cursor move")
		_look_cursor.move(delta)
	elif _character.action_state == _character.ActionState.INTERACTION:
		if _character.interaction_sub_state == _character.InteractionSubState.MOVE_CURSOR:
			print("[DO_MOVE] -> interact cursor move")
			_interact_cursor.move(delta)
		else:
			print("[DO_MOVE] INTERACTION but sub_state=%d — movement blocked" % _character.interaction_sub_state)
	else:
		print("[DO_MOVE] unhandled action_state=%d — movement blocked" % _character.action_state)

func _check_move(delta: Vector2i) -> void:
	print("[CHECK_MOVE] delta=%s action_state=%d interaction_sub_state=%d" % [str(delta), _character.action_state, _character.interaction_sub_state])
	var target := grid_pos + delta
	var cell := Vector3i(target.x, 0, target.y)
	var tile_id := _grid_map.get_cell_item(cell)
	if tile_id == GridMap.INVALID_CELL_ITEM:
		if _character.character_role == _character.CharacterRole.PLAYER:
			zone_exit.emit(delta)
		return
	var true_tile := TileRegistry.get_original_tile(cell, tile_id)
	if not TileRegistry.is_walkable(true_tile):
		return
	for node in _character.get_parent().get_children():
		if node == _character:
			continue
		var other_movement := node.get_node_or_null("CharacterMovement")
		if other_movement == null or other_movement.grid_pos != target:
			continue
		var other_ai := node.get_node_or_null("CharacterAI")
		if other_ai != null:
			print("[MOVE] %s behavior_state=%d KNOCKED_OUT=%d DEAD=%d" % [node.name, other_ai.behavior_state, other_ai.BehaviorState.KNOCKED_OUT, other_ai.BehaviorState.DEAD])
		if other_ai != null and (other_ai.behavior_state == other_ai.BehaviorState.KNOCKED_OUT or other_ai.behavior_state == other_ai.BehaviorState.DEAD):
			print("[MOVE] skipping %s — incapacitated" % node.name)
			continue
		var different_faction: bool = node.faction != _character.faction
		if other_ai != null and other_ai.disposition == other_ai.Disposition.HOSTILE and different_faction:
			if other_ai.behavior_state != other_ai.BehaviorState.COMBAT:
				other_ai.behavior_state = other_ai.BehaviorState.COMBAT
			_face(delta)
			var combat := _character.get_node_or_null("CharacterCombat")
			if combat != null:
				combat._apply_damage(node)
				combat.bump_attack(target)
			moved.emit()
		return
	grid_pos = target
	moved.emit()
	_face(delta)
	_snap()


func _face(delta: Vector2i) -> void:
	if delta.x > 0:
		facing_state = _sprite.FacingState.RIGHT
		_sprite.face(facing_state, _sprite.FacingState.RIGHT)
	elif delta.x < 0:
		facing_state = _sprite.FacingState.LEFT
		_sprite.face(facing_state, _sprite.FacingState.RIGHT)

func set_look_mode(enabled: bool) -> void:
	if enabled:
		_look_cursor.activate(grid_pos)
	else:
		_look_cursor.deactivate()

func step(delta: Vector2i) -> void:
	_check_move(delta)

func place(pos: Vector2i, new_zone: Vector2i = Vector2i.ZERO) -> void:
	grid_pos = pos
	zone = new_zone
	_snap()

func _snap() -> void:
	var local := _grid_map.map_to_local(Vector3i(grid_pos.x, 0, grid_pos.y))
	var world := _grid_map.to_global(local)
	_character.position.x = world.x
	_character.position.z = world.z

func _world_to_grid(world: Vector3) -> Vector2i:
	var cell := _grid_map.local_to_map(_grid_map.to_local(world))
	return Vector2i(cell.x, cell.z)
