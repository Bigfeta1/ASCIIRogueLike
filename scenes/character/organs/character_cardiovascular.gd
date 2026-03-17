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

const BASELINE_CO: float = 5.0
const MAX_CO: float      = 20.0

# Sympathetic tone — two channels with different time constants
# fast: HR + inotropy (neural, ~1-2 turns); slow: SVR + venous tone (humoral, ~2-3 turns)
var _sym_tone_fast: float = 0.0
var _sym_tone_slow: float = 0.0

# Baseline cardiac parameters
const BASELINE_HR: float             = 60.0
const MAX_HR: float                  = 180.0
const BASELINE_LV_EMAX: float        = 2.5
const MAX_LV_EMAX: float             = 4.5
const BASELINE_LV_EDECAY: float      = 60.0
const MAX_LV_EDECAY: float           = 120.0
const BASELINE_RV_EMAX: float        = 1.2
const MAX_RV_EMAX: float             = 2.0
const BASELINE_LA_CONDUCTANCE: float = 25.0
const MAX_LA_CONDUCTANCE: float      = 55.0
const BASELINE_LV_ERISE: float       = 20.0
const MAX_LV_ERISE: float            = 130.0

var pressure_graph: CardiacPressureGraph = null
var _beat_phase: float = 1.0   # fires when >= 1.0; starts at 1.0 so step 0 fires immediately


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
	var actual_co: float      = monitor.cardiac_output
	var co_error: float       = demanded_co - actual_co
	var error_fraction: float = co_error / (MAX_CO - BASELINE_CO)

	var sym_mod: float          = 1.0
	var parasym_recovery: float = 1.0
	if _levels != null:
		sym_mod            = 1.0 + _levels.stat_mod(_levels.sympathetic) * 0.05
		parasym_recovery   = 1.0 + _levels.stat_mod(_levels.parasympathetic) * 0.1

	var tone_step: float   = error_fraction * sym_mod * 0.4
	var target_tone: float = clampf(_sym_tone_fast + tone_step, 0.0, 1.0)

	var fast_alpha: float = 0.6 if target_tone > _sym_tone_fast else 0.25 * parasym_recovery
	_sym_tone_fast = lerpf(_sym_tone_fast, target_tone, fast_alpha)
	if _sym_tone_fast < 0.001:
		_sym_tone_fast = 0.0

	var slow_alpha: float = 0.5 if target_tone > _sym_tone_slow else 0.15 * parasym_recovery
	_sym_tone_slow = lerpf(_sym_tone_slow, target_tone, slow_alpha)
	if _sym_tone_slow < 0.001:
		_sym_tone_slow = 0.0

	heart_rate           = lerpf(BASELINE_HR, MAX_HR, _sym_tone_fast)
	var inotropy_curve: float = pow(_sym_tone_fast, 0.4)
	lv.e_max             = lerpf(BASELINE_LV_EMAX, MAX_LV_EMAX, inotropy_curve)
	lv.e_rise_rate       = lerpf(BASELINE_LV_ERISE, MAX_LV_ERISE, _sym_tone_fast)
	lv.e_decay_rate      = lerpf(BASELINE_LV_EDECAY, MAX_LV_EDECAY, _sym_tone_fast)
	rv.e_max             = lerpf(BASELINE_RV_EMAX, MAX_RV_EMAX, _sym_tone_fast)
	la.valve_conductance = lerpf(BASELINE_LA_CONDUCTANCE, MAX_LA_CONDUCTANCE, _sym_tone_fast)

	var svr_curve: float = pow(_sym_tone_slow, 0.4)
	_aorta.systemic_resistance   = lerpf(
		_aorta.BASELINE_SYSTEMIC_RESISTANCE,
		_aorta.BASELINE_SYSTEMIC_RESISTANCE * 0.37,
		svr_curve)
	_vena_cava.unstressed_volume = lerpf(
		_vena_cava.BASELINE_UNSTRESSED_VOLUME,
		_vena_cava.BASELINE_UNSTRESSED_VOLUME * 0.85,
		svr_curve)
	_vena_cava.to_ra_conductance = lerpf(
		_vena_cava.BASELINE_TO_RA_CONDUCTANCE,
		_vena_cava.BASELINE_TO_RA_CONDUCTANCE * 2.0,
		svr_curve)


func tick_turn() -> void:
	_turn_index += 1
	var phase_per_step: float = SIM_STEP / (60.0 / heart_rate)
	var turn_steps: int = roundi(TURN_DURATION / SIM_STEP)
	var beat: int = 0
	var _beat_step: int = 0
	var _prev_edv: float = monitor.EDV
	var _prev_esv: float = monitor.ESV
	for i in turn_steps:
		if _beat_phase >= 1.0:
			_beat_phase -= 1.0
			sa_node.force_fire()
			if _turn_index <= 2:
				print("[T%d B%d] EDV=%.1f ESV=%.1f SV=%.1f LA=%.1f LV=%.1f RV=%.1f PV=%.1f VC=%.1f Ao=%.1f" % [_turn_index, beat, _prev_edv, _prev_esv, _prev_edv-_prev_esv, la.volume, lv.volume, rv.volume, _pulmonary_vein.volume, _vena_cava.volume, _aorta.volume])
			beat += 1
			_beat_step = 0
			_prev_edv = monitor.EDV
			_prev_esv = monitor.ESV
		tick(SIM_STEP)
		if pressure_graph != null:
			pressure_graph.record(self)
		_beat_step += 1
		_beat_phase += phase_per_step
	_apply_sympathetic_tone()
	var total_vol: float = la.volume + lv.volume + ra.volume + rv.volume + _aorta.volume + _vena_cava.volume + _pulmonary_vein.volume
	print("[TURN %d] BP=%.0f/%.0f HR=%.0f SV=%.1f EDV=%.1f ESV=%.1f CO=%.3f tone_f=%.3f tone_s=%.3f demanded=%.2f VC=%.1f PV=%.1f Ao=%.1f LA=%.1f LV=%.1f RA=%.1f RV=%.1f TOTAL=%.1f" % [_turn_index, monitor.bp_systolic, monitor.bp_diastolic, heart_rate, monitor.SV, monitor.EDV, monitor.ESV, monitor.cardiac_output, _sym_tone_fast, _sym_tone_slow, demanded_co, _vena_cava.volume, _pulmonary_vein.volume, _aorta.volume, la.volume, lv.volume, ra.volume, rv.volume, total_vol])

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

	var ventricular_systole: bool = lv.pressure > la.pressure

	_mitral_valve.tick(delta, 0.0, ventricular_systole, lv.valve_open)
	la.volume = maxf(la.v0, la.volume)

	_aortic_valve.tick(delta, _aorta.pressure, false, false)
	_aorta.volume += _aortic_valve.flow

	_tricuspid_valve.tick(delta, 0.0, ventricular_systole, false)
	ra.volume = maxf(ra.v0, ra.volume)

	_pulmonic_valve.tick(delta, _pulmonary_artery.pressure, false, false)
	_pulmonary_vein.volume += _pulmonic_valve.flow
#endregion
