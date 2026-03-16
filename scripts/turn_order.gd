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

func _ready() -> void:
	var main := get_parent().get_parent()
	
	_player = main.get_node("Character")
	_player_actions = _player.get_node("CharacterActions")
	_map_params = main.get_node("GridMap/MapParameters")
	
	_player.get_node("CharacterMovement").moved.connect(_on_player_acted.bind(true))
	_player.get_node("CharacterMovement").waited.connect(_on_player_acted.bind(false))
	turn_changed.connect(_on_turn_changed)

#region REGISTRATION
func register_enemy(enemy: Node) -> void:
	_enemies.append(enemy)
	enemy.get_node("CharacterAI").set_player(_player)

func unregister_enemy(enemy: Node) -> void:
	_enemies.erase(enemy)

func get_enemies() -> Array:
	return _enemies
#endregion

func _on_player_acted(is_moving: bool) -> void:
	
	if not is_instance_valid(_player):
		return
	
	current_turn_state = TurnState.MAP_TURN
	turn_changed.emit(TurnState.PLAYER_TURN, TurnState.MAP_TURN)
	
	# Health regen
	_player.get_node("CharacterVitals").tick_regen()
	
	# Organs Ticked
	if _player.organs != null:
		_player.organs.tick(is_moving)
	
	# Action Points
	_player_actions.spend_action()
	
	# Bonus Actions
	if _player_actions.has_bonus_turn():
		_player_actions.consume_bonus_turn()
		current_turn_state = TurnState.PLAYER_TURN
		turn_changed.emit(TurnState.MAP_TURN, TurnState.PLAYER_TURN)
		return
	
func _on_turn_changed(_old_turn: TurnState, new_turn: TurnState) -> void:
	
	# Return on PlayerTurn
	if new_turn != TurnState.MAP_TURN:
		return
	
	# MapTurn
	await get_tree().create_timer(0.1).timeout
	
	if not is_instance_valid(_player):
		return
	
	# Handle Enemy turn
	handle_enemy_turn()
	
	# Emit Signal
	current_turn_state = TurnState.PLAYER_TURN
	turn_changed.emit(TurnState.MAP_TURN, TurnState.PLAYER_TURN)
	

func handle_enemy_turn():
	for enemy in _enemies:
		var ai: Node = enemy.get_node("CharacterAI")
		var alive: bool = ai.life_state == ai.LifeState.ALIVE
		
		if alive:
			ai.take_turn_step()
		
		if enemy.organs != null:
			enemy.organs.tick(alive)

		# Enemy Regen
		enemy.get_node("CharacterVitals").tick_regen()
	
	WorldState.tick_off_screen_enemies()
	_map_params.advance_time(15)
