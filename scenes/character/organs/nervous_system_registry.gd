extends Node

var cns: Node = null
var pns: Node = null


func _ready() -> void:
	cns = get_node("CNS")
	pns = get_node("PNS")


func setup(organ_registry: Node, cardiovascular: Node, vitals: Node, levels: Node, is_player: bool) -> void:
	cns.setup(organ_registry, vitals)
	pns.setup(cardiovascular, levels, is_player)


func tick_turn() -> void:
	pns.tick_turn()


func tick() -> void:
	cns.tick()
