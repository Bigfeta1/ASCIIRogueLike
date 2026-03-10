extends Node

const BEAT_DURATION: int = 15
const BASE_ACTION_COST: int = 15

var time_credits: int = 0
var _levels: Node

func _ready() -> void:
	_levels = get_parent().get_node("CharacterLevels")

func get_speed() -> int:
	return _levels.sympathetic - 10

func get_action_cost(base_cost: int = BASE_ACTION_COST) -> int:
	return base_cost - get_speed()

func spend_action(base_cost: int = BASE_ACTION_COST) -> void:
	var cost := get_action_cost(base_cost)
	var unspent := BEAT_DURATION - cost
	time_credits += unspent

func has_bonus_turn() -> bool:
	return time_credits >= BEAT_DURATION

func consume_bonus_turn() -> void:
	time_credits -= BEAT_DURATION
