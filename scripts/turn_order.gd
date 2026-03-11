extends Node

signal turn_changed(old_turn, new_turn)

enum TurnState {
	PLAYER_TURN,
	MAP_TURN,
	IDLE
}

var current_turn_state = TurnState.PLAYER_TURN
var previous_turn

var _enemies: Array = []
var _player_actions: Node
var _map_params: Node
var _player: Node

func register_enemy(enemy: Node) -> void:
	_enemies.append(enemy)
	enemy.get_node("CharacterAI").set_player(_player)

func unregister_enemy(enemy: Node) -> void:
	_enemies.erase(enemy)

func get_enemies() -> Array:
	return _enemies

func _ready() -> void:
	var main := get_parent().get_parent()
	_player = main.get_node("Character")
	_player_actions = _player.get_node("CharacterActions")
	_map_params = main.get_node("GridMap/MapParameters")
	_player.get_node("CharacterMovement").moved.connect(_on_player_moved)
	_player.get_node("CharacterMovement").waited.connect(_on_player_waited)

func _on_player_waited() -> void:
	current_turn_state = TurnState.MAP_TURN
	turn_changed.emit(TurnState.PLAYER_TURN, TurnState.MAP_TURN)
	if _player.renal != null:
		_player.renal.consume_action_cost()
		_player.renal.tick()
	if _player.cardiovascular != null:
		_player.cardiovascular.tick()
	if _player.hypothalamus != null:
		_player.hypothalamus.tick()
	await get_tree().create_timer(0.1).timeout
	for enemy in _enemies:
		var ai: Node = enemy.get_node("CharacterAI")
		if ai.life_state != ai.LifeState.ALIVE:
			continue
		ai.take_turn_step()
		enemy.get_node("CharacterVitals").tick_regen()
	WorldState.tick_off_screen_enemies()
	_map_params.advance_time(15)
	_player.get_node("CharacterVitals").tick_regen()
	current_turn_state = TurnState.PLAYER_TURN
	turn_changed.emit(TurnState.MAP_TURN, TurnState.PLAYER_TURN)

func _on_player_moved() -> void:
	current_turn_state = TurnState.MAP_TURN
	turn_changed.emit(TurnState.PLAYER_TURN, TurnState.MAP_TURN)
	if _player.renal != null:
		_player.renal.consume_action_cost()
		_player.renal.tick()
	if _player.cardiovascular != null:
		_player.cardiovascular.tick()
	if _player.hypothalamus != null:
		_player.hypothalamus.tick()
	_player_actions.spend_action()
	if _player_actions.has_bonus_turn():
		_player_actions.consume_bonus_turn()
		current_turn_state = TurnState.PLAYER_TURN
		turn_changed.emit(TurnState.MAP_TURN, TurnState.PLAYER_TURN)
		return
	await get_tree().create_timer(0.1).timeout
	for enemy in _enemies:
		var ai: Node = enemy.get_node("CharacterAI")
		if ai.life_state != ai.LifeState.ALIVE:
			continue
		ai.take_turn_step()
		enemy.get_node("CharacterVitals").tick_regen()
	WorldState.tick_off_screen_enemies()
	_map_params.advance_time(15)
	_player.get_node("CharacterVitals").tick_regen()
	current_turn_state = TurnState.PLAYER_TURN
	turn_changed.emit(TurnState.MAP_TURN, TurnState.PLAYER_TURN)
