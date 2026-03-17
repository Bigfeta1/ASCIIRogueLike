extends Node

signal v_wave_peak(pcwp: float)      # PCWP peak at end of ventricular systole — LA maximally filled
signal y_descent_start(pcwp: float)  # mitral opens, LA begins draining into LV

#region REGISTRY
var _vitals: Node  = null
var _levels: Node  = null

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ELECTROPHYSIOLOGY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
@onready var sa_node: SANode = get_node("HeartElectricalSystem/AtrialComponents/SAnode")
@onready var _atrial: Node = get_node("HeartElectricalSystem/AtrialComponents")
@onready var _ventricular: Node = get_node("HeartElectricalSystem/Ventricularcomponents")

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CHAMBERS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
@onready var la: CardiacChamber = get_node("LeftHeart/Atria")
@onready var lv: CardiacChamber = get_node("LeftHeart/Ventricle")
@onready var ra: CardiacChamber = get_node("RightHeart/Atria")
@onready var rv: CardiacChamber = get_node("RightHeart/Ventricle")

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# VALVES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
@onready var _mitral_valve:      CardiacValve    = get_node("LeftHeart/Atria/MitralValve")
@onready var _aortic_valve:      CardiacValve    = get_node("LeftHeart/Ventricle/AorticlValve")
@onready var _tricuspid_valve:   CardiacValve    = get_node("RightHeart/Atria/TricuspidValve")
@onready var _pulmonic_valve:    CardiacValve    = get_node("RightHeart/Ventricle/PulmoniclValve")

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# I/O
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
@onready var _pulmonary_artery:  PulmonaryArtery = get_node("RightHeart/PulmonaryArtery")
@onready var _vena_cava:         VenaCava        = get_node("RightHeart/VenaCava")
@onready var _aorta:             Aorta           = get_node("LeftHeart/Aorta")
@onready var _pulmonary_vein:    PulmonaryVein   = get_node("LeftHeart/PulmonaryVein")

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# MONITOR
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
@onready var monitor: CardiacMonitor = get_node("CardiacMonitor")

#endregion

#region SIMULATION STATE PARAMETERS
var heart_rate: float             = 60.0
var TPR: float                    = 17.7
var venous_return_fraction: float = 1.0
var demanded_co: float            = 5.0
var demanded_co_pre_decay: float  = 5.0
var spo2: float                   = 99.0

const BASELINE_CO: float = 4.75
const MAX_CO: float      = 20.0

# Sympathetic tone — two channels with different time constants
# fast: HR + inotropy (neural, ~1-2 turns); slow: SVR + venous tone (humoral, ~2-3 turns)
var _sym_tone_fast: float = 0.0
var _sym_tone_slow: float = 0.0

# Baseline cardiac parameters
const BASELINE_HR: float             = 60.0
const MAX_HR: float                  = 180.0
const CO_TOLERANCE: float            = 0.03

const BASELINE_NA_SLOPE: float = 23.0
const MAX_NA_SLOPE: float      = 80.6
const MIN_NA_SLOPE: float      = 11.11

const BASELINE_LV_EMAX: float        = 2.5
const MAX_LV_EMAX: float             = 4.5
const MIN_LV_EMAX: float             = 1.8
const BASELINE_LV_EDECAY: float      = 60.0
const MAX_LV_EDECAY: float           = 120.0
const BASELINE_RV_EMAX: float        = 1.2
const MAX_RV_EMAX: float             = 2.0
const MIN_RV_EMAX: float             = 0.9
const BASELINE_LA_CONDUCTANCE: float = 25.0
const MAX_LA_CONDUCTANCE: float      = 55.0
const BASELINE_LV_ERISE: float       = 20.0
const MAX_LV_ERISE: float            = 130.0

const MAX_SYSTEMIC_RESISTANCE: float = 1.26 * 1.5
const MAX_UNSTRESSED_VOLUME: float   = 3023.0 * 1.10
const MIN_TO_RA_CONDUCTANCE: float   = 14.3 * 0.7

var pressure_graph: CardiacPressureGraph = null


#endregion

func set_demand(co: float) -> void:
	demanded_co_pre_decay = co
	demanded_co           = co

func _ready() -> void:
	_mitral_valve.setup(la, lv)
	_aortic_valve.setup(lv, null)
	_tricuspid_valve.setup(ra, rv)
	_pulmonic_valve.setup(rv, null)

	_mitral_valve.upstream_closed.connect(func(v: float) -> void: monitor.EDV = v)
	_mitral_valve.waveform_peak.connect(func(p: float) -> void: v_wave_peak.emit(p))
	_mitral_valve.waveform_trough.connect(func(p: float) -> void: y_descent_start.emit(p))

	_aortic_valve.upstream_closed.connect(func(v: float) -> void: monitor.ESV = v)
	_aortic_valve.waveform_peak.connect(func(v: float) -> void:
		monitor.bp_systolic = v
	)
	_aortic_valve.waveform_trough.connect(func(v: float) -> void: monitor.bp_diastolic = v)

#region SETUP
func setup(vitals: Node, levels: Node = null) -> void:
	_vitals = vitals
	_levels = levels
	_refresh_initial_valve_states()

func _refresh_initial_valve_states() -> void:
	lv.pressure = lv.elastance * maxf(0.0, lv.volume - lv.v0)
	rv.pressure = rv.elastance * maxf(0.0, rv.volume - rv.v0)
	la.pressure = la.elastance * maxf(0.0, la.volume - la.v0)
	ra.pressure = ra.elastance * maxf(0.0, ra.volume - ra.v0)

	la.valve_open = lv.pressure <= la.pressure + 1.0
	ra.valve_open = rv.pressure <= ra.pressure + 1.0
	lv.valve_open = false
	rv.valve_open = false

#endregion

#region TICK

const TURN_DURATION: float = 15.0
const SIM_STEP: float      = 0.020

static var _turn_index: int = 0

func _apply_sympathetic_tone() -> void:
	var actual_co: float = monitor.cardiac_output
	var co_error: float = demanded_co - actual_co
	var error_fraction: float = clampf(co_error / (MAX_CO - BASELINE_CO), -1.0, 1.0)

	var sym_mod: float = 1.0
	var parasym_recovery: float = 1.0
	if _levels != null:
		sym_mod = 1.0 + _levels.stat_mod(_levels.sympathetic) * 0.05
		parasym_recovery = 1.0 + _levels.stat_mod(_levels.parasympathetic) * 0.1

	# Integral state update — symmetric [-1, 1] range
	if co_error > 0.0:
		_sym_tone_fast = clampf(_sym_tone_fast + error_fraction * sym_mod * 0.12, -1.0, 1.0)
		_sym_tone_slow = clampf(_sym_tone_slow + error_fraction * sym_mod * 0.10, -1.0, 1.0)
	elif co_error < -CO_TOLERANCE:
		_sym_tone_fast = clampf(_sym_tone_fast + error_fraction * parasym_recovery * 0.12, -1.0, 1.0)
		_sym_tone_slow = clampf(_sym_tone_slow + error_fraction * parasym_recovery * 0.10, -1.0, 1.0)
	# else: CO within tolerance — hold tone as-is

	# Proportional command on top of integral state
	var fast_cmd: float = clampf(_sym_tone_fast + error_fraction * 0.25, -1.0, 1.0)
	var slow_cmd: float = clampf(_sym_tone_slow + error_fraction * 0.18, -1.0, 1.0)

	# na_slope: tone=-1 → MIN, tone=0 → BASELINE, tone=+1 → MAX
	if fast_cmd >= 0.0:
		sa_node.na_slope = lerpf(BASELINE_NA_SLOPE, MAX_NA_SLOPE, fast_cmd)
	else:
		sa_node.na_slope = lerpf(BASELINE_NA_SLOPE, MIN_NA_SLOPE, -fast_cmd)

	# lv.e_max
	if fast_cmd >= 0.0:
		lv.e_max = lerpf(BASELINE_LV_EMAX, MAX_LV_EMAX, fast_cmd)
	else:
		lv.e_max = lerpf(BASELINE_LV_EMAX, MIN_LV_EMAX, -fast_cmd)

	# rv.e_max
	if fast_cmd >= 0.0:
		rv.e_max = lerpf(BASELINE_RV_EMAX, MAX_RV_EMAX, fast_cmd)
	else:
		rv.e_max = lerpf(BASELINE_RV_EMAX, MIN_RV_EMAX, -fast_cmd)

	# e_rise_rate and e_decay_rate — only modulated upward (no parasympathetic effect)
	lv.e_rise_rate  = lerpf(BASELINE_LV_ERISE,  MAX_LV_ERISE,  maxf(0.0, fast_cmd))
	lv.e_decay_rate = lerpf(BASELINE_LV_EDECAY, MAX_LV_EDECAY, maxf(0.0, fast_cmd))

	# valve_conductance — only upward
	la.valve_conductance = lerpf(BASELINE_LA_CONDUCTANCE, MAX_LA_CONDUCTANCE, maxf(0.0, fast_cmd))

	# systemic_resistance: tone=0 → BASELINE, tone=+1 → vasodilation, tone=-1 → MAX (vasoconstriction)
	if slow_cmd >= 0.0:
		_aorta.systemic_resistance = lerpf(_aorta.BASELINE_SYSTEMIC_RESISTANCE, _aorta.BASELINE_SYSTEMIC_RESISTANCE * 0.37, slow_cmd)
	else:
		_aorta.systemic_resistance = lerpf(_aorta.BASELINE_SYSTEMIC_RESISTANCE, MAX_SYSTEMIC_RESISTANCE, -slow_cmd)

	# unstressed_volume: tone=0 → BASELINE, tone=+1 → venoconstriction, tone=-1 → MAX (venodilation)
	if slow_cmd >= 0.0:
		_vena_cava.unstressed_volume = lerpf(_vena_cava.BASELINE_UNSTRESSED_VOLUME, _vena_cava.BASELINE_UNSTRESSED_VOLUME * 0.85, slow_cmd)
	else:
		_vena_cava.unstressed_volume = lerpf(_vena_cava.BASELINE_UNSTRESSED_VOLUME, MAX_UNSTRESSED_VOLUME, -slow_cmd)

	# to_ra_conductance: tone=0 → BASELINE, tone=+1 → ×2.0, tone=-1 → MIN
	if slow_cmd >= 0.0:
		_vena_cava.to_ra_conductance = lerpf(_vena_cava.BASELINE_TO_RA_CONDUCTANCE, _vena_cava.BASELINE_TO_RA_CONDUCTANCE * 2.0, slow_cmd)
	else:
		_vena_cava.to_ra_conductance = lerpf(_vena_cava.BASELINE_TO_RA_CONDUCTANCE, MIN_TO_RA_CONDUCTANCE, -slow_cmd)


func tick_turn() -> void:
	_turn_index += 1

	var turn_steps: int = roundi(TURN_DURATION / SIM_STEP)
	for i in turn_steps:
		tick(SIM_STEP)

		if pressure_graph != null:
			pressure_graph.record(self)

	if sa_node.beat_period > 0.0:
		heart_rate             = 60.0 / sa_node.beat_period
		monitor.cardiac_output = (monitor.SV * heart_rate) / 1000.0
	else:
		monitor.cardiac_output = 0.0

	_apply_sympathetic_tone()

	var total_vol: float = la.volume + lv.volume + ra.volume + rv.volume + _aorta.volume + _vena_cava.volume + _pulmonary_vein.volume
	print("[TURN %d] BP=%.0f/%.0f HR=%.0f SV=%.1f EDV=%.1f ESV=%.1f CO=%.3f tone_f=%.3f tone_s=%.3f demanded=%.2f VC=%.1f PV=%.1f Ao=%.1f LA=%.1f LV=%.1f RA=%.1f RV=%.1f TOTAL=%.1f" % [
		_turn_index, monitor.bp_systolic, monitor.bp_diastolic, heart_rate,
		monitor.SV, monitor.EDV, monitor.ESV, monitor.cardiac_output,
		_sym_tone_fast, _sym_tone_slow, demanded_co,
		_vena_cava.volume, _pulmonary_vein.volume, _aorta.volume,
		la.volume, lv.volume, ra.volume, rv.volume, total_vol
	])

func tick(delta: float) -> void:
	_atrial.tick(delta)
	_ventricular.tick(delta)

	lv.tick(delta)
	rv.tick(delta)
	la.tick(delta)
	ra.tick(delta)

	_step_valves(delta)

	# Recompute all chamber pressures after flow — stale pressures cause wrong valve decisions
	lv.pressure = lv.elastance * maxf(0.0, lv.volume - lv.v0)
	rv.pressure = rv.elastance * maxf(0.0, rv.volume - rv.v0)
	la.pressure = la.elastance * maxf(0.0, la.volume - la.v0)
	ra.pressure = ra.elastance * maxf(0.0, ra.volume - ra.v0)

	_vena_cava.volume         += _aorta.tick(delta, lv.valve_open, _aortic_valve.notch_fired, _aortic_valve.notch_dip)
	_aortic_valve.update_peak(_aorta.pressure)
	monitor.aorta_pressure     = _aorta.pressure
	monitor.aorta_blood_flow   = _aorta.blood_flow
	monitor.aorta_blood_flow_end = _aorta.blood_flow_end
	_pulmonary_artery.tick(delta, rv.valve_open)

	_step_heart()


func _step_heart() -> void:
	monitor.SV             = maxf(0.0, monitor.EDV - monitor.ESV)
	monitor.EF             = (monitor.SV / monitor.EDV) * 100.0 if monitor.EDV > 0.0 else 0.0
	monitor.cardiac_output = (monitor.SV * heart_rate) / 1000.0 if not _atrial._sa_node.cardioplegia else 0.0

	monitor.mean_arterial_pressure = monitor.bp_diastolic + (monitor.bp_systolic - monitor.bp_diastolic) / 3.0
	monitor.pulse_pressure         = monitor.bp_systolic - monitor.bp_diastolic

	if _vitals != null:
		_vitals.hr           = roundi(heart_rate)
		_vitals.bp_systolic  = roundi(monitor.bp_systolic)
		_vitals.bp_diastolic = roundi(monitor.bp_diastolic)
		_vitals._refresh_ui()


func _step_valves(delta: float) -> void:
	monitor.pcwp = la.pressure

	la.volume += _pulmonary_vein.tick(delta, la.pressure)
	ra.volume += _vena_cava.tick(delta, ra.pressure)

	var lv_systole: bool = lv.pressure > la.pressure
	var rv_systole: bool = rv.pressure > ra.pressure

	_mitral_valve.tick(delta, 0.0, lv_systole, lv.valve_open)
	la.volume = maxf(la.v0, la.volume)

	_aortic_valve.tick(delta, _aorta.pressure, false, false)
	_aorta.volume += _aortic_valve.flow

	_tricuspid_valve.tick(delta, 0.0, rv_systole, false)
	ra.volume = maxf(ra.v0, ra.volume)

	_pulmonic_valve.tick(delta, _pulmonary_artery.pressure, false, false)
	_pulmonary_vein.volume += _pulmonic_valve.flow
#endregion
