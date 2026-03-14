extends Node

# Cerebral cortex — hypoperfusion damage and syncope tracker.
# Monitors BP and MAP each tick.
#
# Syncope: SBP < 80 → player knocked out immediately (hemodynamic collapse).
# Ischemia: MAP < 60 for 5 continuous minutes (20 ticks) → HP -1/tick until perfusion restored.

const SYNCOPE_SBP_THRESHOLD: float = 80.0  # mmHg — below this = loss of consciousness
const ISCHEMIA_MAP_THRESHOLD: float = 60.0  # mmHg — below this = cerebral hypoperfusion
const ISCHEMIA_TICK_THRESHOLD: int = 20     # ticks — 5 minutes at 15s/tick

var hypoperfusion_ticks: int = 0            # consecutive ticks below ischemia threshold
var ischemia_active: bool = false           # true once threshold crossed

var _organs: Node = null
var _vitals: Node = null
var _character: Node = null


func setup(organ_registry: Node, vitals: Node) -> void:
	_organs = organ_registry
	_vitals = vitals
	_character = get_parent()


func tick() -> void:
	if _organs == null or _organs.cardiovascular == null or _vitals == null:
		return

	var cardio: Node = _organs.cardiovascular
	var sbp: float = cardio.bp_systolic
	var map: float = cardio.mean_arterial_pressure

	# Syncope: SBP below threshold → knock out immediately
	var ai := _character.get_node_or_null("CharacterAI")
	if sbp < SYNCOPE_SBP_THRESHOLD:
		if ai != null and ai.life_state == ai.LifeState.ALIVE:
			_character.get_node("CharacterLifecycle").knock_out(_character)
			return
	else:
		# SBP recovered — restore if knocked out from syncope
		if ai != null and ai.life_state == ai.LifeState.KNOCKED_OUT:
			_character.get_node("CharacterLifecycle").recover_syncope(_character)

	# Ischemia: MAP < 60 for sustained period → HP damage
	if map < ISCHEMIA_MAP_THRESHOLD:
		hypoperfusion_ticks += 1
		if hypoperfusion_ticks >= ISCHEMIA_TICK_THRESHOLD:
			ischemia_active = true
			_vitals.hp = maxi(_vitals.hp - 1, 0)
			_vitals._refresh_ui()
			if _vitals.hp <= 0:
				# PEA: myocardial failure from hypoxia/acidosis.
				# Electrical activity ceases — HR, CO, BP all collapse to zero.
				cardio.heart_rate = 0.0
				cardio.cardiac_output = 0.0
				cardio.SV = 0.0
				cardio.mean_arterial_pressure = 0.0
				cardio.bp_systolic = 0.0
				cardio.bp_diastolic = 0.0
				_vitals.hr = 0
				_vitals.bp_systolic = 0
				_vitals.bp_diastolic = 0
				_vitals._refresh_ui()
				_character.get_node("CharacterLifecycle").die(_character)
	else:
		hypoperfusion_ticks = 0
		ischemia_active = false
