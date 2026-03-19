extends Node

# Central reference point for all organ subsystem nodes.
# Populated by character._ready() after dynamic instantiation.
# Other systems read organs through here rather than reaching into character.gd directly.

var renal: Node = null
var hypothalamus: Node = null
var cardiovascular: Node = null
var pulmonary: Node = null
var cortex: Node = null
var coagulation: Node = null

func _ready() -> void:
	renal = get_node("CharacterRenal")
	hypothalamus = get_node("CharacterHypothalamus")
	cardiovascular = get_node("CharacterCardiovascular")
	pulmonary = get_node("CharacterPulmonary")
	cortex = get_node("CharacterCortex")
	coagulation = get_node("CharacterCoagulation")
	

func setup(vitals: Node, levels: Node, is_player: bool = false) -> void:
	# Called by Character.gd

	renal.setup(self)
	hypothalamus.setup(self)
	cardiovascular.setup(vitals, levels, is_player)
	pulmonary.setup(self, levels, vitals, is_player)
	cortex.setup(self, vitals)
	coagulation.setup(self)

func tick(is_moving: bool = false) -> void:
	# Called by TurnOrder (player only now — enemies use tick_non_cardiac)
	if cardiovascular != null:
		await cardiovascular.tick_turn()
	tick_non_cardiac(is_moving)

func tick_non_cardiac(is_moving: bool = false) -> void:
	if pulmonary != null:
		pulmonary.tick()
	if renal != null:
		renal.consume_action_cost()
		renal.tick()
	if hypothalamus != null:
		hypothalamus.tick()
	if cortex != null:
		cortex.tick()
	if coagulation != null:
		if is_moving:
			coagulation.on_moved()
		else:
			coagulation.on_waited()
		coagulation.tick()
