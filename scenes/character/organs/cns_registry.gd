extends Node

var cortex: Node = null
var hypothalamus: Node = null
var brainstem: Node = null
var precentral_gyrus: Node = null


func _ready() -> void:
	cortex = get_node("CharacterCortex")
	hypothalamus = get_node("CharacterHypothalamus")
	brainstem = get_node("Brainstem")
	precentral_gyrus = get_node("CharacterCortex/FrontalLobe/PrecentralGyrus")


func setup(organ_registry: Node, vitals: Node) -> void:
	hypothalamus.setup(organ_registry)
	cortex.setup(organ_registry, vitals)


func tick() -> void:
	if hypothalamus != null:
		hypothalamus.tick()
	if cortex != null:
		cortex.tick()
