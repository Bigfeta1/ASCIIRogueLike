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
var spo2: float                   = 99.0

const BASELINE_HR: float = 60.0
const MAX_HR: float      = 180.0

var pressure_graph: CardiacPressureGraph = null

@onready var _cardiac_sim: CardiacSim = get_node("CardiacSim")

#endregion

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
var _is_player: bool = false

func setup(vitals: Node, levels: Node = null, is_player: bool = false) -> void:
	_vitals = vitals
	_levels = levels
	_is_player = is_player
	if not _is_player and _cardiac_sim != null:
		_cardiac_sim.initialize()
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

func tick_turn() -> void:
	_turn_index += 1

	if not _is_player and _cardiac_sim != null:
		# async path: launched externally, results collected via _collect_async_results()
		return

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

	if _vitals != null and _is_player:
		_vitals._refresh_ui()

	var total_vol: float = la.volume + lv.volume + ra.volume + rv.volume + _aorta.volume + _vena_cava.volume + _pulmonary_vein.volume
	print("[TURN %d] BP=%.0f/%.0f HR=%.0f SV=%.1f EDV=%.1f ESV=%.1f CO=%.3f VC=%.1f PV=%.1f Ao=%.1f LA=%.1f LV=%.1f RA=%.1f RV=%.1f TOTAL=%.1f" % [
		_turn_index, monitor.bp_systolic, monitor.bp_diastolic, heart_rate,
		monitor.SV, monitor.EDV, monitor.ESV, monitor.cardiac_output,
		_vena_cava.volume, _pulmonary_vein.volume, _aorta.volume,
		la.volume, lv.volume, ra.volume, rv.volume, total_vol
	])

func _collect_async_results() -> void:
	heart_rate = _cardiac_sim.get_heart_rate()
	monitor.bp_systolic  = _cardiac_sim.get_bp_systolic()
	monitor.bp_diastolic = _cardiac_sim.get_bp_diastolic()
	monitor.cardiac_output = _cardiac_sim.get_cardiac_output()
	monitor.SV  = _cardiac_sim.get_sv()
	monitor.EDV = _cardiac_sim.get_edv()
	monitor.ESV = _cardiac_sim.get_esv()
	monitor.mean_arterial_pressure = _cardiac_sim.get_mean_arterial_pressure()
	if _vitals != null:
		_vitals.hr           = roundi(heart_rate)
		_vitals.bp_systolic  = roundi(monitor.bp_systolic)
		_vitals.bp_diastolic = roundi(monitor.bp_diastolic)

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

	_step_heart_monitor()


func _step_heart_monitor() -> void:
	monitor.SV             = maxf(0.0, monitor.EDV - monitor.ESV)
	monitor.EF             = (monitor.SV / monitor.EDV) * 100.0 if monitor.EDV > 0.0 else 0.0
	monitor.cardiac_output = (monitor.SV * heart_rate) / 1000.0 if not _atrial._sa_node.cardioplegia else 0.0

	monitor.mean_arterial_pressure = monitor.bp_diastolic + (monitor.bp_systolic - monitor.bp_diastolic) / 3.0
	monitor.pulse_pressure         = monitor.bp_systolic - monitor.bp_diastolic

	if _vitals != null and _is_player:
		_vitals.hr           = roundi(heart_rate)
		_vitals.bp_systolic  = roundi(monitor.bp_systolic)
		_vitals.bp_diastolic = roundi(monitor.bp_diastolic)


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
