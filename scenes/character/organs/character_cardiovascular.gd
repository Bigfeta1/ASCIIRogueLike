extends Node

signal v_wave_peak(pcwp: float)      # PCWP peak at end of ventricular systole — LA maximally filled
signal y_descent_start(pcwp: float)  # mitral opens, LA begins draining into LV

#region REGISTRY
var _vitals: Node = null

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
var heart_rate: float            = 60.0
var TPR: float                   = 17.7
var venous_return_fraction: float = 1.0
var demanded_co: float           = 5.0
var demanded_co_pre_decay: float = 5.0
var spo2: float                  = 99.0

const BASELINE_CO: float = 5.0
const MAX_CO: float      = 20.0

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
	_aortic_valve.waveform_peak.connect(func(v: float) -> void: monitor.bp_systolic = v)
	_aortic_valve.waveform_trough.connect(func(v: float) -> void: monitor.bp_diastolic = v)

#region SETUP
func setup(vitals: Node) -> void:
	_vitals = vitals
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
const SIM_STEP: float      = 0.016

func tick_turn() -> void:
	var beats_per_turn: int = roundi(heart_rate / 60.0 * TURN_DURATION)
	var steps_per_beat: int = ceili(60.0 / heart_rate / SIM_STEP)
	for b in beats_per_turn:
		sa_node.force_fire()
		for _i in steps_per_beat:
			tick(SIM_STEP)
			if pressure_graph != null:
				pressure_graph.record(self)
		print("[BEAT %d] BP=%.0f/%.0f MAP=%.1f" % [b + 1, monitor.bp_systolic, monitor.bp_diastolic, monitor.mean_arterial_pressure])
	print("[TURN END] BP=%.0f/%.0f MAP=%.1f HR=%.0f CO=%.2f beats=%d" % [monitor.bp_systolic, monitor.bp_diastolic, monitor.mean_arterial_pressure, heart_rate, monitor.cardiac_output, beats_per_turn])

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
