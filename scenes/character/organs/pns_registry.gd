extends Node

var autonomic: Node = null


func _ready() -> void:
	autonomic = get_node("AutonomicNervousSystem")


func setup(cardiovascular: Node, levels: Node, is_player: bool) -> void:
	autonomic.setup(cardiovascular, levels, is_player)


func tick_turn() -> void:
	if autonomic != null:
		autonomic.tick_turn()
