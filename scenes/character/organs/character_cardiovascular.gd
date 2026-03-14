extends Node

# Cardiovascular system — full cardiac cycle.

signal beat_initiated                # SA node threshold reached; triggers EP
signal v_wave_peak(pcwp: float)      # PCWP peak at end of ventricular systole — LA maximally filled
signal y_descent_start(pcwp: float)  # mitral opens, LA begins draining into LV

var _organs: Node = null
var _vitals: Node = null
var _levels: Node = null

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CARDIAC CHAMBERS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var la: CardiacChamber = null
var lv: CardiacChamber = null
var ra: CardiacChamber = null
var rv: CardiacChamber = null

func _init_chambers() -> void:
	la = CardiacChamber.new()
	la.fascicle_count       = 1
	la.regions_per_fascicle = 3
	la.sweep_duration       = 0.08
	la.myocyte_durations    = [0.002, 0.005, 0.073, 0.060, 0.0]
	la.myocyte_force        = [0.15,  0.50,  1.00,  0.20,  0.0]
	la.e_min                = 0.20
	la.e_max                = 0.60
	la.e_rise_rate          = 5.0
	la.e_decay_rate         = 3.0
	la.v0                   = 10.0
	la.initial_volume       = 55.0
	la.valve_conductance    = 25.0
	la.init_regions()
	la.region_depolarized.connect(_on_la_region_depolarized)

	lv = CardiacChamber.new()
	lv.fascicle_count       = 3
	lv.regions_per_fascicle = 3
	lv.sweep_duration       = 0.03
	lv.myocyte_durations    = [0.002, 0.005, 0.100, 0.080, 0.0]
	lv.myocyte_force        = [0.10,  0.40,  1.00,  0.25,  0.0]
	lv.e_min                = 0.1
	lv.e_max                = 2.5
	lv.e_rise_rate          = 8.0
	lv.e_decay_rate         = 8.0
	lv.v0                   = 10.0
	lv.initial_volume       = 100.0
	lv.valve_conductance    = 15.0
	lv.init_regions()

	ra = CardiacChamber.new()
	ra.fascicle_count       = 1
	ra.regions_per_fascicle = 3
	ra.sweep_duration       = 0.08
	ra.myocyte_durations    = [0.002, 0.005, 0.073, 0.060, 0.0]
	ra.myocyte_force        = [0.15,  0.50,  1.00,  0.20,  0.0]
	ra.e_min                = 0.25
	ra.e_max                = 0.67
	ra.e_rise_rate          = 5.0
	ra.e_decay_rate         = 3.0
	ra.v0                   = 8.0
	ra.initial_volume       = 22.0
	ra.valve_conductance    = 20.0
	ra.init_regions()

	rv = CardiacChamber.new()
	rv.fascicle_count       = 3
	rv.regions_per_fascicle = 3
	rv.sweep_duration       = 0.03
	rv.myocyte_durations    = [0.002, 0.005, 0.100, 0.080, 0.0]
	rv.myocyte_force        = [0.10,  0.40,  1.00,  0.25,  0.0]
	rv.e_min                = 0.05
	rv.e_max                = 0.60
	rv.e_rise_rate          = 6.0
	rv.e_decay_rate         = 6.0
	rv.v0                   = 10.0
	rv.initial_volume       = 100.0
	rv.valve_conductance    = 3.0
	rv.init_regions()

func _on_la_region_depolarized(region: int) -> void:
	print("[CARDIO] LA region %d depolarized" % region)

func _ready() -> void:
	beat_initiated.connect(_on_beat_initiated)

func setup(organ_registry: Node, vitals: Node, levels: Node) -> void:
	_organs = organ_registry
	_vitals = vitals
	_levels = levels
	_init_chambers()

func tick(delta: float) -> void:
	_step_sa_node(delta)
	_step_electrical_pathway(delta)
	_step_heart()
	# Sweeps triggered from _on_beat_initiated and _ep_transition
	la.step_sweep(delta)
	ra.step_sweep(delta)
	lv.step_sweep(delta)
	rv.step_sweep(delta)
	# Myocytes — ventricles before atria so valve logic sees current LV pressure
	lv.step_myocytes(delta)
	rv.step_myocytes(delta)
	la.step_myocytes(delta)
	ra.step_myocytes(delta)
	# Elastance + pressure
	lv.step_elastance(delta)
	rv.step_elastance(delta)
	la.step_elastance(delta)
	ra.step_elastance(delta)
	# Valve logic and volume transfers
	_step_valves(delta)
	# Recompute ventricular pressures after ejection — volume changed, elastance did not
	lv.pressure = lv.elastance * maxf(0.0, lv.volume - lv.v0)
	rv.pressure = rv.elastance * maxf(0.0, rv.volume - rv.v0)
	# Open aortic valve = pressure equilibrium: eject excess volume to match aorta
	if lv.valve_open and lv.elastance > 0.0:
		var lv_eq_volume: float = aorta_pressure / lv.elastance + lv.v0
		var lv_transfer: float = lv.volume - lv_eq_volume
		if lv_transfer > 0.0:
			lv_transfer    = minf(lv_transfer, maxf(0.0, lv.volume - lv.v0))
			lv.volume     -= lv_transfer
			aorta_pressure += lv_transfer / 1.5
		lv.pressure = lv.elastance * maxf(0.0, lv.volume - lv.v0)
	_step_aorta(delta)
	_step_pulmonary_artery(delta)

	print("[CARDIO] EP=%s SA=%s | LA=%.1fmL p=%.1f mitral=%s | LV=%.1fmL p=%.1f aortic=%s aorta=%.1f(notch=%.1f) | RA=%.1fmL p=%.1f | RV=%.1fmL p=%.1f" % [
		ElectricalPathwayStates.keys()[ep_state],
		SinoAtrialStates.keys()[sa_state],
		la.volume, la.pressure, "O" if la.valve_open else "X",
		lv.volume, lv.pressure, "O" if lv.valve_open else "X",
		aorta_pressure, _dicrotic_notch_boost,
		ra.volume, ra.pressure,
		rv.volume, rv.pressure,
	])

func force_fire_sa_node() -> void:
	sa_node_membrane_potential = 10.0
	sa_state                   = SinoAtrialStates.PHASE_0


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# HEART
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var heart_rate: float             = 60.0
var EDV: float                    = 142.0
var ESV: float                    = 62.0
var SV: float                     = 0.0
var EF: float                     = 0.0
var TPR: float                    = 17.7
var cardiac_output: float         = 0.0
var mean_arterial_pressure: float = 0.0
var pulse_pressure: float         = 40.0
var diastolic_bp: float           = 0.0
var systolic_bp: float            = 0.0
var bp_systolic: float            = 0.0   # alias for cortex/pulmonary compatibility
var bp_diastolic: float           = 0.0   # alias

var venous_return_fraction: float = 1.0

const BASELINE_CO: float = 5.0
const MAX_CO: float      = 20.0
var demanded_co: float           = BASELINE_CO
var demanded_co_pre_decay: float = BASELINE_CO
var spo2: float                  = 99.0

# pcwp alias — always la.pressure; kept for signal payloads and external readers
var pcwp: float = 8.0

func set_demand(co: float) -> void:
	demanded_co_pre_decay = co
	demanded_co           = co

func _step_heart() -> void:
	_update_cycle_durations()
	if _organs != null and _organs.renal != null:
		solve_for_preload()

	SV = maxf(0.0, EDV - ESV)
	EF = (SV / EDV) * 100.0 if EDV > 0.0 else 0.0

	if not sa_node_cardioplegia:
		cardiac_output = (SV * heart_rate) / 1000.0
	else:
		cardiac_output = 0.0

	mean_arterial_pressure = cardiac_output * TPR
	pulse_pressure         = 40.0
	diastolic_bp           = mean_arterial_pressure - (pulse_pressure / 3.0)
	systolic_bp            = (3.0 * mean_arterial_pressure) - (2.0 * diastolic_bp)
	bp_systolic            = systolic_bp
	bp_diastolic           = diastolic_bp

	if _vitals != null:
		_vitals.hr         = roundi(heart_rate)
		_vitals.bp_systolic  = roundi(systolic_bp)
		_vitals.bp_diastolic = roundi(diastolic_bp)
		_vitals._refresh_ui()

func solve_for_preload() -> void:
	var plasma_fluid: float                  = _organs.renal.plasma_fluid
	var plasma_fluid_to_preload_ratio: float = 100.0 / 3750.0
	var cardiac_preload: float               = plasma_fluid * plasma_fluid_to_preload_ratio * venous_return_fraction
	EDV = ESV + cardiac_preload

var cardiac_cycle_duration: float   = 1.0
var atrial_systole_duration: float  = 0.1
var atrial_diastole_duration: float = 0.9

func _update_cycle_durations() -> void:
	cardiac_cycle_duration   = 60.0 / heart_rate
	atrial_systole_duration  = 0.10
	atrial_diastole_duration = maxf(0.0, cardiac_cycle_duration - atrial_systole_duration)


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SA NODE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var sa_node_membrane_potential: float = -60.0
var sa_atria_ic_na: float             = 0.0
var sa_atria_ic_ca: float             = 0.0
var sa_atria_ic_k: float              = 70.0

enum SinoAtrialStates {
	PHASE_4,  # slow diastolic depolarization — Na/Ca influx drives membrane to threshold
	PHASE_0,  # rapid depolarization — threshold reached, signal fires
	PHASE_3   # repolarization — K efflux restores resting potential
}

var sa_state: SinoAtrialStates = SinoAtrialStates.PHASE_4
var sa_node_cardioplegia: bool = false

func _step_sa_node(delta: float) -> void:
	sa_node_membrane_potential = -130.0 + sa_atria_ic_na + sa_atria_ic_ca + sa_atria_ic_k

	if sa_node_cardioplegia:
		sa_atria_ic_k = 500.0
		return

	match sa_state:
		SinoAtrialStates.PHASE_4:
			if sa_node_membrane_potential < -40.0 and sa_atria_ic_na < 20.0:
				sa_atria_ic_na += (20.0 / 0.49) * delta
			elif sa_node_membrane_potential >= -40.0 and sa_node_membrane_potential < 10.0 and sa_atria_ic_ca < 50.0:
				sa_atria_ic_ca += (50.0 / 0.05) * delta
			if sa_node_membrane_potential >= 10.0:
				sa_state = SinoAtrialStates.PHASE_0

		SinoAtrialStates.PHASE_0:
			beat_initiated.emit()
			sa_state = SinoAtrialStates.PHASE_3

		SinoAtrialStates.PHASE_3:
			if sa_atria_ic_k > 0.0:
				sa_atria_ic_k -= (80.0 / 0.04) * delta
			if sa_atria_ic_k <= 0.0:
				sa_atria_ic_na             = 0.0
				sa_atria_ic_ca             = 0.0
				sa_atria_ic_k              = 70.0
				sa_node_membrane_potential = -60.0
				sa_state                   = SinoAtrialStates.PHASE_4


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ELECTRICAL PATHWAY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var ep_cardiac_phase1: bool = false
var ep_cycle_reset: bool    = false
var ep_running: bool        = false

enum ElectricalPathwayStates {
	ATRIAL_DEPOLARIZATION,      # signal traveling SA→AV node
	AV_DELAY,                   # AV node delay
	VENTRICULAR_DEPOLARIZATION, # QRS complex
	EARLY_REPOLARIZATION,       # ST segment
	T_WAVE,                     # aortic valve closes
	ISOVOLUMETRIC_RELAXATION,   # pressure falls, valves closed
	DIASTOLIC_FILLING           # mitral opens, ventricle fills
}

var ep_state: ElectricalPathwayStates = ElectricalPathwayStates.DIASTOLIC_FILLING
var ep_state_timer: float             = 0.0

const EP_STATE_DURATIONS: Array[float] = [0.08, 0.06, 0.03, 0.03, 0.15, 0.03, 0.21]

func _on_beat_initiated() -> void:
	print("[CARDIO] SA node fired | Vm=%.1f" % sa_node_membrane_potential)
	ep_cycle_reset = false
	ep_running     = true
	_ep_transition(ElectricalPathwayStates.ATRIAL_DEPOLARIZATION)
	la.trigger_sweep()
	ra.trigger_sweep()

func _ep_transition(next_state: ElectricalPathwayStates) -> void:
	ep_state       = next_state
	ep_state_timer = 0.0
	match ep_state:
		ElectricalPathwayStates.ATRIAL_DEPOLARIZATION:
			ep_cardiac_phase1 = false
			print("[CARDIO] EP → ATRIAL_DEPOLARIZATION")
		ElectricalPathwayStates.AV_DELAY:
			ep_cardiac_phase1 = false
			print("[CARDIO] EP → AV_DELAY")
		ElectricalPathwayStates.VENTRICULAR_DEPOLARIZATION:
			ep_cardiac_phase1 = true
			lv.trigger_sweep()
			rv.trigger_sweep()
			print("[CARDIO] EP → VENTRICULAR_DEPOLARIZATION")
		ElectricalPathwayStates.EARLY_REPOLARIZATION:
			ep_cardiac_phase1 = true
			print("[CARDIO] EP → EARLY_REPOLARIZATION")
		ElectricalPathwayStates.T_WAVE:
			ep_cardiac_phase1 = true
			print("[CARDIO] EP → T_WAVE")
		ElectricalPathwayStates.ISOVOLUMETRIC_RELAXATION:
			ep_cardiac_phase1 = false
			_v_wave_emitted   = false
			print("[CARDIO] EP → ISOVOLUMETRIC_RELAXATION")
		ElectricalPathwayStates.DIASTOLIC_FILLING:
			ep_cardiac_phase1  = false
			_y_descent_emitted = false
			print("[CARDIO] EP → DIASTOLIC_FILLING")

func _step_electrical_pathway(delta: float) -> void:
	if not ep_running:
		return

	ep_cycle_reset  = false
	ep_state_timer += delta

	if ep_state_timer < EP_STATE_DURATIONS[ep_state]:
		return

	match ep_state:
		ElectricalPathwayStates.ATRIAL_DEPOLARIZATION:
			_ep_transition(ElectricalPathwayStates.AV_DELAY)
		ElectricalPathwayStates.AV_DELAY:
			_ep_transition(ElectricalPathwayStates.VENTRICULAR_DEPOLARIZATION)
		ElectricalPathwayStates.VENTRICULAR_DEPOLARIZATION:
			_ep_transition(ElectricalPathwayStates.EARLY_REPOLARIZATION)
		ElectricalPathwayStates.EARLY_REPOLARIZATION:
			_ep_transition(ElectricalPathwayStates.T_WAVE)
		ElectricalPathwayStates.T_WAVE:
			_ep_transition(ElectricalPathwayStates.ISOVOLUMETRIC_RELAXATION)
		ElectricalPathwayStates.ISOVOLUMETRIC_RELAXATION:
			_ep_transition(ElectricalPathwayStates.DIASTOLIC_FILLING)
		ElectricalPathwayStates.DIASTOLIC_FILLING:
			ep_cycle_reset = true
			ep_running     = false


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# VALVES + VOLUME TRANSFER
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Venous return constants — pulmonary veins into LA
const LA_VENOUS_RETURN_RATE_SYSTOLE: float  = 100.0  # mL/s — reservoir phase (mitral closed)
const LA_VENOUS_RETURN_RATE_DIASTOLE: float = 42.0   # mL/s — conduit/booster phase
const LA_CONTRACTION_RATE: float            = 250.0  # mL/s total active ejection rate

# Venous return constants — systemic veins into RA
const RA_VENOUS_RETURN_RATE_SYSTOLE: float  = 34.0   # mL/s
const RA_VENOUS_RETURN_RATE_DIASTOLE: float = 25.0   # mL/s
const RA_CONTRACTION_RATE: float            = 180.0  # mL/s

# C-wave: transient elastance spike on LA at mitral closure
var _mitral_valve_diameter: float   = 1.0
const MITRAL_CLOSE_RATE: float      = 33.3   # diameter/s — fully closed in ~0.03s
const C_WAVE_ELASTANCE_BOOST: float = 0.30   # mmHg/mL added to la.e_max transiently
const C_WAVE_DECAY_RATE: float      = 10.0   # /s — elastance boost decay after full closure
var _c_wave_boost: float            = 0.0    # current extra elastance on LA

# PCWP waveform detection
var _pcwp_prev: float        = 8.0
var _v_wave_emitted: bool    = false
var _y_descent_emitted: bool = false

func _step_valves(delta: float) -> void:
	pcwp = la.pressure

	# ── Pulmonary venous return into LA ───────────────────────────────────────
	var la_vr_rate: float = LA_VENOUS_RETURN_RATE_SYSTOLE if ep_cardiac_phase1 else LA_VENOUS_RETURN_RATE_DIASTOLE
	la.volume += la_vr_rate * delta

	# ── Systemic venous return into RA ────────────────────────────────────────
	var ra_vr_rate: float = RA_VENOUS_RETURN_RATE_SYSTOLE if ep_cardiac_phase1 else RA_VENOUS_RETURN_RATE_DIASTOLE
	ra.volume += ra_vr_rate * delta

	# ── Mitral valve (LA → LV) ────────────────────────────────────────────────
	var ventricular_closure: bool = (
		ep_state == ElectricalPathwayStates.VENTRICULAR_DEPOLARIZATION or
		ep_state == ElectricalPathwayStates.EARLY_REPOLARIZATION or
		ep_state == ElectricalPathwayStates.T_WAVE
	)
	var should_close_mitral: bool = ventricular_closure and (lv.pressure > la.pressure + 1.0)

	if should_close_mitral:
		if la.valve_open:
			la.valve_open         = false
			_mitral_valve_diameter = 1.0
			_c_wave_boost          = 0.0
			print("[CARDIO] Mitral CLOSING | LA=%.1fmL p=%.1f" % [la.volume, la.pressure])
		_resolve_mitral_c_wave(delta)
	else:
		if not ventricular_closure:
			la.valve_open         = true
			_mitral_valve_diameter = 1.0
			_c_wave_boost          = 0.0
			la.e_max               = 0.60  # restore baseline e_max

	if la.valve_open:
		# Active contraction flow (booster phase)
		var la_force: float = 0.0
		for i in la.region_count:
			if la._regions[i]["mechanical"] == 1:
				la_force += la.myocyte_force[la._regions[i]["myocyte"]]
		if la_force > 0.0:
			var active_flow: float = (LA_CONTRACTION_RATE / float(la.region_count)) * la_force * delta
			active_flow  = minf(active_flow, maxf(0.0, la.volume - la.v0))
			la.volume   -= active_flow
			lv.volume   += active_flow
		# Passive filling flow (pressure gradient)
		var passive_flow: float = maxf(0.0, (la.pressure - lv.pressure) * la.valve_conductance * delta)
		passive_flow  = minf(passive_flow, maxf(0.0, la.volume - la.v0))
		la.volume    -= passive_flow
		lv.volume    += passive_flow

	la.volume = maxf(la.v0, la.volume)

	# ── Aortic valve (LV → aorta) ─────────────────────────────────────────────
	if not lv.valve_open and lv.pressure >= aorta_pressure:
		lv.valve_open = true
	if lv.valve_open and lv.pressure < aorta_pressure:
		lv.valve_open = false

	if lv.valve_open:
		var eject_flow: float = maxf(0.0, (lv.pressure - aorta_pressure) * lv.valve_conductance * delta)
		eject_flow     = minf(eject_flow, maxf(0.0, lv.volume - lv.v0))
		lv.volume     -= eject_flow
		aorta_pressure += eject_flow / 1.5

	lv.pressure = clampf(lv.pressure, 0.0, 200.0)

	# ── Tricuspid valve (RA → RV) ─────────────────────────────────────────────
	var should_close_tricuspid: bool = ventricular_closure and (rv.pressure > ra.pressure + 1.0)

	if should_close_tricuspid:
		ra.valve_open = false
	elif not ventricular_closure:
		ra.valve_open = true

	if ra.valve_open:
		var ra_force: float = 0.0
		for i in ra.region_count:
			if ra._regions[i]["mechanical"] == 1:
				ra_force += ra.myocyte_force[ra._regions[i]["myocyte"]]
		if ra_force > 0.0:
			var active_flow: float = (RA_CONTRACTION_RATE / float(ra.region_count)) * ra_force * delta
			active_flow  = minf(active_flow, maxf(0.0, ra.volume - ra.v0))
			ra.volume   -= active_flow
			rv.volume   += active_flow
		var passive_flow: float = maxf(0.0, (ra.pressure - rv.pressure) * ra.valve_conductance * delta)
		passive_flow  = minf(passive_flow, maxf(0.0, ra.volume - ra.v0))
		ra.volume    -= passive_flow
		rv.volume    += passive_flow

	ra.volume = maxf(ra.v0, ra.volume)

	# ── Pulmonic valve (RV → pulmonary artery) ────────────────────────────────
	if not rv.valve_open and rv.pressure >= pulmonary_pressure:
		rv.valve_open = true
	if rv.valve_open and rv.pressure < pulmonary_pressure:
		rv.valve_open = false

	if rv.valve_open:
		var eject_flow: float = maxf(0.0, (rv.pressure - pulmonary_pressure) * rv.valve_conductance * delta)
		eject_flow          = minf(eject_flow, maxf(0.0, rv.volume - rv.v0))
		rv.volume          -= eject_flow
		pulmonary_pressure += eject_flow * 0.1

	rv.pressure = clampf(rv.pressure, 0.0, 60.0)

	# ── PCWP waveform detection ───────────────────────────────────────────────
	if not _v_wave_emitted and not ep_cardiac_phase1 and not la.valve_open and pcwp < _pcwp_prev:
		_v_wave_emitted = true
		v_wave_peak.emit(pcwp)
		print("[CARDIO] v-wave peak | PCWP=%.1f mmHg" % pcwp)

	if not _y_descent_emitted and la.valve_open and pcwp < _pcwp_prev:
		_y_descent_emitted = true
		y_descent_start.emit(pcwp)
		print("[CARDIO] y-descent start | PCWP=%.1f mmHg" % pcwp)

	_pcwp_prev = pcwp

func _resolve_mitral_c_wave(delta: float) -> void:
	if _mitral_valve_diameter > 0.0:
		_mitral_valve_diameter = maxf(0.0, _mitral_valve_diameter - MITRAL_CLOSE_RATE * delta)
		_c_wave_boost          = C_WAVE_ELASTANCE_BOOST * (1.0 - _mitral_valve_diameter)
		la.e_max               = 0.60 + _c_wave_boost
		if _mitral_valve_diameter == 0.0:
			print("[CARDIO] Mitral CLOSED | LA=%.1fmL p=%.1f" % [la.volume, la.pressure])
	else:
		_c_wave_boost = maxf(0.0, _c_wave_boost - C_WAVE_DECAY_RATE * delta)
		la.e_max      = 0.60 + _c_wave_boost


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AORTA
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var aorta_pressure: float      = 90.0
var aorta_pressure_min: float  = 80.0
var aorta_pressure_max: float  = 120.0
var aorta_blood_flow: bool     = false
var aorta_blood_flow_end: bool = false

var _aortic_valve_was_open: bool   = false
var _dicrotic_notch_boost: float   = 0.0
var _incisura_pending: bool        = false
var _incisura_close_pressure: float = 0.0  # aorta pressure at valve closure
const DICROTIC_NOTCH_DIP: float    = 5.0
const DICROTIC_NOTCH_HEIGHT: float = 0.5
const DICROTIC_NOTCH_DECAY: float  = 80.0

func _step_aorta(delta: float) -> void:
	var notch_fired: bool = _aortic_valve_was_open and not lv.valve_open
	_aortic_valve_was_open = lv.valve_open

	if notch_fired:
		_incisura_close_pressure = aorta_pressure
		aorta_pressure          -= DICROTIC_NOTCH_DIP
		_incisura_pending        = true
	elif _incisura_pending:
		aorta_pressure        += DICROTIC_NOTCH_DIP + DICROTIC_NOTCH_HEIGHT
		_dicrotic_notch_boost  = DICROTIC_NOTCH_HEIGHT
		_incisura_pending      = false
	elif _dicrotic_notch_boost > 0.0:
		_dicrotic_notch_boost = maxf(0.0, _dicrotic_notch_boost - DICROTIC_NOTCH_DECAY * delta)

	if not lv.valve_open and not notch_fired and not _incisura_pending:
		aorta_pressure -= 55.0 * delta

	aorta_pressure_min = 8.0
	aorta_pressure_max = 160.0
	aorta_pressure     = clampf(aorta_pressure, aorta_pressure_min, aorta_pressure_max)

	aorta_blood_flow     = lv.valve_open
	aorta_blood_flow_end = not lv.valve_open and ep_cardiac_phase1


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# PULMONARY ARTERY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var pulmonary_pressure: float = 15.0

func _step_pulmonary_artery(delta: float) -> void:
	if not rv.valve_open:
		pulmonary_pressure -= 4.0 * delta
	pulmonary_pressure = clampf(pulmonary_pressure, 8.0, 30.0)
