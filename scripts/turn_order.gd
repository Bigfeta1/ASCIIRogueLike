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

func _tick_enemy_organs(enemy: Node, is_moving: bool) -> void:
	if enemy.cardiovascular != null:
		enemy.cardiovascular.tick(0.016)
	if enemy.pulmonary != null:
		enemy.pulmonary.tick()
	if enemy.renal != null:
		enemy.renal.consume_action_cost()
		enemy.renal.tick()
	if enemy.hypothalamus != null:
		enemy.hypothalamus.tick()
	if enemy.cortex != null:
		enemy.cortex.tick()
	if enemy.coagulation != null:
		if is_moving:
			enemy.coagulation.on_moved()
		else:
			enemy.coagulation.on_waited()
		enemy.coagulation.tick()

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
	if not is_instance_valid(_player):
		return
	current_turn_state = TurnState.MAP_TURN
	turn_changed.emit(TurnState.PLAYER_TURN, TurnState.MAP_TURN)
	if _player.cardiovascular != null:
		_player.cardiovascular.tick(0.016)
	if _player.pulmonary != null:
		_player.pulmonary.tick()
	if _player.renal != null:
		_player.renal.consume_action_cost()
		_player.renal.tick()
	if _player.hypothalamus != null:
		_player.hypothalamus.tick()
	if _player.cortex != null:
		_player.cortex.tick()
	if _player.coagulation != null:
		_player.coagulation.on_waited()
		_player.coagulation.tick()
	await get_tree().create_timer(0.1).timeout
	if not is_instance_valid(_player):
		return
	for enemy in _enemies:
		var ai: Node = enemy.get_node("CharacterAI")
		var alive: bool = ai.life_state == ai.LifeState.ALIVE
		if alive:
			ai.take_turn_step()
		_tick_enemy_organs(enemy, alive)
		enemy.get_node("CharacterVitals").tick_regen()
	WorldState.tick_off_screen_enemies()
	_map_params.advance_time(15)
	_player.get_node("CharacterVitals").tick_regen()
	current_turn_state = TurnState.PLAYER_TURN
	turn_changed.emit(TurnState.MAP_TURN, TurnState.PLAYER_TURN)

func _on_player_moved() -> void:
	if not is_instance_valid(_player):
		return
	current_turn_state = TurnState.MAP_TURN
	turn_changed.emit(TurnState.PLAYER_TURN, TurnState.MAP_TURN)
	if _player.cardiovascular != null:
		_player.cardiovascular.tick(0.016)
	if _player.pulmonary != null:
		_player.pulmonary.tick()
	if _player.renal != null:
		_player.renal.consume_action_cost()
		_player.renal.tick()
	if _player.hypothalamus != null:
		_player.hypothalamus.tick()
	if _player.cortex != null:
		_player.cortex.tick()
	if _player.coagulation != null:
		_player.coagulation.on_moved()
		_player.coagulation.tick()
	_player_actions.spend_action()
	if _player_actions.has_bonus_turn():
		_player_actions.consume_bonus_turn()
		current_turn_state = TurnState.PLAYER_TURN
		turn_changed.emit(TurnState.MAP_TURN, TurnState.PLAYER_TURN)
		return
	await get_tree().create_timer(0.1).timeout
	if not is_instance_valid(_player):
		return
	for enemy in _enemies:
		var ai: Node = enemy.get_node("CharacterAI")
		var alive: bool = ai.life_state == ai.LifeState.ALIVE
		if alive:
			ai.take_turn_step()
		_tick_enemy_organs(enemy, alive)
		enemy.get_node("CharacterVitals").tick_regen()
	WorldState.tick_off_screen_enemies()
	_map_params.advance_time(15)
	_player.get_node("CharacterVitals").tick_regen()
	current_turn_state = TurnState.PLAYER_TURN
	turn_changed.emit(TurnState.MAP_TURN, TurnState.PLAYER_TURN)
