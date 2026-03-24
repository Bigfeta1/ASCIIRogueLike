extends Node

# Central reference point for all organ subsystem nodes.
# Populated by character._ready() after dynamic instantiation.
# Other systems read organs through here rather than reaching into character.gd directly.

var renal: Node = null
var cardiovascular: Node = null
var pulmonary: Node = null
var coagulation: Node = null
var nervous_system: Node = null

# Convenience passthroughs into nervous_system — kept so external callers don't break
var autonomic: Node = null
var hypothalamus: Node = null
var cortex: Node = null
var precentral_gyrus: Node = null


func _ready() -> void:
	renal = get_node("CharacterRenal")
	cardiovascular = get_node("CharacterCardiovascular")
	pulmonary = get_node("CharacterPulmonary")
	coagulation = get_node("CharacterCoagulation")
	nervous_system = get_node("CharacterNervousSystem")
	# Populate convenience refs once sub-registries are ready
	autonomic = nervous_system.pns.autonomic
	hypothalamus = nervous_system.cns.hypothalamus
	cortex = nervous_system.cns.cortex
	precentral_gyrus = nervous_system.cns.precentral_gyrus


func setup(vitals: Node, levels: Node, is_player: bool = false) -> void:
	# Called by Character.gd
	renal.setup(self)
	cardiovascular.setup(vitals, levels, is_player)
	nervous_system.setup(self, cardiovascular, vitals, levels, is_player)
	pulmonary.setup(self, levels, vitals, is_player)
	coagulation.setup(self)


func tick(is_moving: bool = false) -> void:
	# Called by TurnOrder (player only now — enemies use tick_non_cardiac)
	if cardiovascular != null:
		await cardiovascular.tick_turn()
	if nervous_system != null:
		nervous_system.tick_turn()
	tick_non_cardiac(is_moving)


func tick_non_cardiac(is_moving: bool = false) -> void:
	if pulmonary != null:
		pulmonary.tick()
	if renal != null:
		renal.consume_action_cost()
		renal.tick()
	if nervous_system != null:
		nervous_system.tick()
	if coagulation != null:
		if is_moving:
			coagulation.on_moved()
		else:
			coagulation.on_waited()
		coagulation.tick()
