extends Node

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AUTONOMIC NERVOUS SYSTEM
#
# Two independent outflows from the medullary cardioregulatory center:
#   sym_tone   [0, 1] — sympathetic outflow
#   vagal_tone [0, 1] — parasympathetic outflow (1.0 = resting vagal tone)
#
# Baroreceptor reflex (feedback):
#   High MAP → baroreceptors fire → NTS → ↑vagal_tone, ↓sym_tone
#   Low MAP  → baroreceptors silent  → ↑sym_tone, ↓vagal_tone
#
# Central command (feedforward):
#   Activity → immediate sym rise and vagal withdrawal from motor cortex
#   Derived each turn from _metabolic_svr_factor; no extra state needed
#
# Metabolic vasodilation (NOT ANS-mediated):
#   Activity sets _metabolic_svr_factor — local vasodilation (CO₂/NO/lactate)
#   Applied directly to SVR, decays over 2-3 turns after activity stops
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var _cardiovascular: Node = null
var _levels: Node         = null
var _is_player: bool      = false

# Baroreceptor integrator state — two independent tones
var sym_tone: float   = 0.0  # [0, 1] sympathetic outflow
var vagal_tone: float = 1.0  # [0, 1] parasympathetic outflow (1.0 = resting)

# Local metabolic vasodilation factor [0, 1].
# Set by notify_activity(), decays each turn.
var _metabolic_svr_factor: float = 0.0

# ── Baroreceptor constants ──
const MAP_SETPOINT:   float = 93.0   # mmHg — normal resting MAP
const MAP_RANGE:      float = 40.0   # mmHg — normalisation denominator
const MAP_DEADBAND:   float = 1.0    # mmHg — no integration within this band
const BARO_GAIN_SYM:  float = 0.10   # sym integrator step per turn at full baro signal
const BARO_GAIN_VAGAL: float = 0.14  # vagal integrator step (vagus responds faster)

# ── Central command constants (exercise feedforward) ──
const CENTRAL_SYM_GAIN:   float = 0.6  # sym_tone contribution from activity
const CENTRAL_VAGAL_GAIN: float = 0.5  # vagal withdrawal from activity

# ── Metabolic constants ──
const METABOLIC_DECAY:     float = 0.45  # fraction lost per turn (~2-3 turn decay)
const METABOLIC_SVR_DEPTH: float = 0.50  # max SVR reduction at metabolic=1.0

# ── Effector parameter ranges ──
const BASELINE_NA_SLOPE:       float = 23.0
const MAX_NA_SLOPE:            float = 80.6
const MIN_NA_SLOPE:            float = 11.11

const BASELINE_LV_EMAX:        float = 2.5
const MAX_LV_EMAX:             float = 4.5
const BASELINE_LV_ERISE:       float = 20.0
const MAX_LV_ERISE:            float = 130.0
const BASELINE_LV_EDECAY:      float = 60.0
const MAX_LV_EDECAY:           float = 120.0

const BASELINE_RV_EMAX:        float = 1.2
const MAX_RV_EMAX:             float = 2.0

const BASELINE_LA_CONDUCTANCE: float = 25.0
const MAX_LA_CONDUCTANCE:      float = 55.0


func setup(cardiovascular: Node, levels: Node, is_player: bool) -> void:
	_cardiovascular = cardiovascular
	_levels         = levels
	_is_player      = is_player


func notify_activity(level: float) -> void:
	_metabolic_svr_factor = clampf(level, 0.0, 1.0)
	# Central command (feedforward) is derived each turn from _metabolic_svr_factor
	# in tick_turn via central_sym_drive and central_vagal_drive — no extra state needed.


func tick_turn() -> void:
	if _cardiovascular == null:
		return

	var map: float = _cardiovascular.monitor.mean_arterial_pressure
	var map_deviation: float = map - MAP_SETPOINT
	
	# baro_signal > 0 → high MAP → baroreceptors firing → suppress sym, raise vagal
	# baro_signal < 0 → low MAP → baroreceptors silent → raise sym, withdraw vagal
	var baro_signal: float = clampf(map_deviation / MAP_RANGE, -1.0, 1.0)

	var sym_mod: float     = 1.0
	var parasym_mod: float = 1.0
	
	# Modifier from levels
	if _levels != null:
		sym_mod    = 1.0 + _levels.stat_mod(_levels.sympathetic)    * 0.05
		parasym_mod = 1.0 + _levels.stat_mod(_levels.parasympathetic) * 0.10

	# Actual Sympathetic or Vagal Tone
	if absf(map_deviation) > MAP_DEADBAND:
		# High baro_signal → suppress sym, raise vagal
		# Low baro_signal  → raise sym, suppress vagal
		sym_tone   = clampf(sym_tone   - (baro_signal * BARO_GAIN_SYM ) * sym_mod,   0.0, 1.0)
		vagal_tone = clampf(vagal_tone + (baro_signal * BARO_GAIN_VAGAL) * parasym_mod, 0.0, 1.0)

	# Local Vasodilation decay
	_metabolic_svr_factor = maxf(0.0, _metabolic_svr_factor - METABOLIC_DECAY)

	# Central command: immediate feedforward from activity (motor cortex + mechanoreflex)
	var central_sym_drive:   float = _metabolic_svr_factor * CENTRAL_SYM_GAIN
	var central_vagal_drive: float = _metabolic_svr_factor * CENTRAL_VAGAL_GAIN

	# Effective drives combine baroreflex integrator state with central command
	var effective_sym:   float = clampf(sym_tone   + central_sym_drive,   0.0, 1.0)
	var effective_vagal: float = clampf(vagal_tone - central_vagal_drive, 0.0, 1.0)

	if _is_player:
		_apply_effectors_player(effective_sym, effective_vagal)
	else:
		_apply_effectors_enemy(effective_sym, effective_vagal)


func _apply_effectors_player(effective_sym: float, effective_vagal: float) -> void:
	var cv := _cardiovascular

	# SA node: sym raises na_slope, vagal lowers it.
	# At rest (sym=0, vagal=1): lerpf(23, 80.6, 0)=23, lerpf(23, 11.11, 0)=23. Correct.
	# Max sym (sym=1, vagal=1): lerpf(23, 80.6, 1)=80.6, lerpf(80.6, 11.11, 0)=80.6. Correct.
	# Max vagal (sym=0, vagal=0): lerpf(23, 80.6, 0)=23, lerpf(23, 11.11, 1)=11.11. Correct.
	cv.sa_node.na_slope = lerpf(BASELINE_NA_SLOPE, MAX_NA_SLOPE, effective_sym)
	cv.sa_node.na_slope = lerpf(cv.sa_node.na_slope, MIN_NA_SLOPE, 1.0 - effective_vagal)

	# Ventricular inotropy/lusitropy — sym only (vagal has negligible ventricular effect)
	cv.lv.e_max        = lerpf(BASELINE_LV_EMAX,  MAX_LV_EMAX,  effective_sym)
	cv.rv.e_max        = lerpf(BASELINE_RV_EMAX,  MAX_RV_EMAX,  effective_sym)
	cv.lv.e_rise_rate  = lerpf(BASELINE_LV_ERISE, MAX_LV_ERISE, effective_sym)
	cv.lv.e_decay_rate = lerpf(BASELINE_LV_EDECAY, MAX_LV_EDECAY, effective_sym)

	# LA valve conductance — sym only
	cv.la.valve_conductance = lerpf(BASELINE_LA_CONDUCTANCE, MAX_LA_CONDUCTANCE, effective_sym)

	# SVR: sym raises resistance (vasoconstriction); metabolic vasodilation opposes.
	# At rest (sym=0, metabolic=0): baseline. At sym=1: 2x baseline (vasoconstriction).
	var baseline_svr: float = cv._aorta.BASELINE_SYSTEMIC_RESISTANCE
	var max_svr:      float = baseline_svr * 2.0
	var min_svr:      float = baseline_svr * 0.50
	cv._aorta.systemic_resistance = clampf(
		lerpf(baseline_svr, max_svr, effective_sym) - (baseline_svr * _metabolic_svr_factor * METABOLIC_SVR_DEPTH),
		min_svr, max_svr)

	# Venous tone: sym causes venoconstriction (lower unstressed volume → more preload)
	cv._vena_cava.unstressed_volume = lerpf(
		cv._vena_cava.BASELINE_UNSTRESSED_VOLUME,
		cv._vena_cava.BASELINE_UNSTRESSED_VOLUME * 0.85,
		effective_sym)
	cv._vena_cava.to_ra_conductance = lerpf(
		cv._vena_cava.BASELINE_TO_RA_CONDUCTANCE,
		cv._vena_cava.BASELINE_TO_RA_CONDUCTANCE * 2.0,
		effective_sym)


func _apply_effectors_enemy(effective_sym: float, effective_vagal: float) -> void:
	var cardiac_sim: Node = _cardiovascular.get_node_or_null("CardiacSim")
	if cardiac_sim == null:
		return
	cardiac_sim.apply_tone(effective_sym, effective_vagal, _metabolic_svr_factor)
