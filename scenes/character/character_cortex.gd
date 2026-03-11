extends Node

# Cerebral cortex — hypoperfusion damage tracker.
# Monitors MAP each tick. If MAP stays below ISCHEMIA_MAP_THRESHOLD for
# ISCHEMIA_TICK_THRESHOLD consecutive ticks (5 minutes at 15s/tick),
# neuronal death begins: HP decrements by 1 per tick until perfusion is restored.

const ISCHEMIA_MAP_THRESHOLD: float = 60.0  # mmHg — below this = cerebral hypoperfusion
const ISCHEMIA_TICK_THRESHOLD: int = 20     # ticks — 5 minutes at 15s/tick

var hypoperfusion_ticks: int = 0            # consecutive ticks below threshold
var ischemia_active: bool = false           # true once threshold crossed

var _organs: Node = null
var _vitals: Node = null


func setup(organ_registry: Node, vitals: Node) -> void:
	_organs = organ_registry
	_vitals = vitals


func tick() -> void:
	if _organs == null or _organs.cardiovascular == null or _vitals == null:
		return

	var map: float = _organs.cardiovascular.mean_arterial_pressure

	if map < ISCHEMIA_MAP_THRESHOLD:
		hypoperfusion_ticks += 1
		if hypoperfusion_ticks >= ISCHEMIA_TICK_THRESHOLD:
			ischemia_active = true
			_vitals.hp = maxi(_vitals.hp - 1, 0)
			_vitals._refresh_ui()
	else:
		# Perfusion restored — reset counter and clear ischemia
		hypoperfusion_ticks = 0
		ischemia_active = false
