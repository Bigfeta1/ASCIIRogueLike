extends Node

var _character: Node
var _turn_order: Node
var _held_keys: Dictionary = {}
var _move_pending: bool = false


func setup(character: Node, turn_order: Node) -> void:
	_character = character
	_turn_order = turn_order


func _unhandled_input(event: InputEvent) -> void:
	if _character == null or _turn_order == null:
		return
	if _character.character_role != _character.CharacterRole.PLAYER:
		return
	if not event is InputEventKey:
		return
	if event.keycode == KEY_SPACE and event.pressed:
		if _turn_order.current_turn_state == _turn_order.TurnState.PLAYER_TURN:
			if _character.action_state == _character.ActionState.MOVEMENT:
				if _character.organs.autonomic != null:
					_character.organs.autonomic.notify_activity(0.0)
				_character.movement.waited.emit()
		return
	var dir_keys := [KEY_D, KEY_RIGHT, KEY_A, KEY_LEFT, KEY_S, KEY_DOWN, KEY_W, KEY_UP]
	if not event.keycode in dir_keys:
		return
	var ai := _character.get_node_or_null("CharacterAI")
	if ai != null and ai.life_state != ai.LifeState.ALIVE:
		return
	if not event.pressed:
		_held_keys.erase(event.keycode)
		return
	if _turn_order.current_turn_state != _turn_order.TurnState.PLAYER_TURN:
		return
	_held_keys[event.keycode] = true
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
	if delta == Vector2i.ZERO:
		return
	var mv: Node = _character.movement
	if _character.action_state == _character.ActionState.MOVEMENT:
		mv.step(delta)
	elif _character.action_state == _character.ActionState.LOOK:
		mv.move_look_cursor(delta)
	elif _character.action_state == _character.ActionState.INTERACTION:
		mv.move_interaction_cursor(delta)
