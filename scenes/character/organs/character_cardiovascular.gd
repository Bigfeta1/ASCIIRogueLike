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
	lv.e_rise_rate          = 25.0
	lv.e_decay_rate         = 60.0
	lv.v0                   = 10.0
	lv.initial_volume       = 120.0
	lv.valve_conductance    = 50.0
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

	la.step_sweep(delta)
	ra.step_sweep(delta)
	lv.step_sweep(delta)
	rv.step_sweep(delta)

	lv.step_myocytes(delta)
	rv.step_myocytes(delta)
	la.step_myocytes(delta)
	ra.step_myocytes(delta)

	lv.step_elastance(delta)
	rv.step_elastance(delta)
	la.step_elastance(delta)
	ra.step_elastance(delta)

	_step_valves(delta)

	# Recompute all chamber pressures after flow — stale pressures cause wrong valve decisions
	lv.pressure = lv.elastance * maxf(0.0, lv.volume - lv.v0)
	rv.pressure = rv.elastance * maxf(0.0, rv.volume - rv.v0)
	la.pressure = la.elastance * maxf(0.0, la.volume - la.v0)
	ra.pressure = ra.elastance * maxf(0.0, ra.volume - ra.v0)

	_step_aorta(delta)
	_step_pulmonary_artery(delta)

	print("[CARDIO] EP=%s SA=%s | LA=%.1fmL p=%.1f mitral=%s | LV=%.1fmL p=%.1f aortic=%s aorta=%.1f | RA=%.1fmL p=%.1f | RV=%.1fmL p=%.1f | SBP=%d DBP=%d" % [
		ElectricalPathwayStates.keys()[ep_state],
		SinoAtrialStates.keys()[sa_state],
		la.volume, la.pressure, "O" if la.valve_open else "X",
		lv.volume, lv.pressure, "O" if lv.valve_open else "X",
		aorta_pressure,
		ra.volume, ra.pressure,
		rv.volume, rv.pressure,
		roundi(systolic_bp), roundi(diastolic_bp),
	])

func force_fire_sa_node() -> void:
	sa_node_membrane_potential = 10.0
	sa_state                   = SinoAtrialStates.PHASE_0


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# HEART — derived metrics unified from actual chamber volumes
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var heart_rate: float             = 60.0
var EDV: float                    = 120.0   # updated from lv.volume at mitral closure
var ESV: float                    = 50.0    # updated from lv.volume at aortic closure
var SV: float                     = 0.0
var EF: float                     = 0.0
var TPR: float                    = 17.7
var cardiac_output: float         = 0.0
var mean_arterial_pressure: float = 0.0
var pulse_pressure: float         = 40.0
var diastolic_bp: float           = 80.0
var systolic_bp: float            = 120.0
var bp_systolic: float            = 120.0   # alias for cortex/pulmonary compatibility
var bp_diastolic: float           = 80.0    # alias

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

	# SV/EF derived from actual chamber volumes captured at valve events
	SV             = maxf(0.0, EDV - ESV)
	EF             = (SV / EDV) * 100.0 if EDV > 0.0 else 0.0
	cardiac_output = (SV * heart_rate) / 1000.0 if not sa_node_cardioplegia else 0.0

	mean_arterial_pressure = diastolic_bp + (systolic_bp - diastolic_bp) / 3.0
	pulse_pressure         = systolic_bp - diastolic_bp

	if _vitals != null:
		_vitals.hr           = roundi(heart_rate)
		_vitals.bp_systolic  = roundi(systolic_bp)
		_vitals.bp_diastolic = roundi(diastolic_bp)
		_vitals._refresh_ui()

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
			ep_cardiac_phase1    = true
			_aortic_latched_shut = false   # new beat — aortic valve may open again
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

# Pulmonary venous return into LA (from pulmonary veins — closed-loop approximation)
const LA_VENOUS_RETURN_RATE_SYSTOLE: float  = 150.0  # mL/s during systole (reservoir phase)
const LA_VENOUS_RETURN_RATE_DIASTOLE: float = 62.0   # mL/s during diastole (conduit phase)
const LA_CONTRACTION_RATE: float            = 250.0  # mL/s active atrial ejection

# Systemic venous compartment — true closed-loop for LV side
# Blood ejected into aorta drains through systemic resistance into SVC reservoir → RA
var systemic_venous_volume: float = 3500.0   # mL — large venous capacitance reservoir
const SYSTEMIC_VENOUS_COMPLIANCE: float = 50.0     # mL/mmHg — very compliant veins
const SYSTEMIC_VENOUS_UNSTRESSED: float = 3000.0   # mL — unstressed volume (P=0 below this)
const SYSTEMIC_VENOUS_TO_RA_CONDUCTANCE: float = 8.0  # mL/(s·mmHg) — venous return to RA

const RA_CONTRACTION_RATE: float = 180.0  # mL/s

# C-wave: transient elastance spike on LA at mitral closure
var _mitral_valve_diameter: float   = 1.0
const MITRAL_CLOSE_RATE: float      = 33.3   # diameter/s — fully closed in ~0.03s
const C_WAVE_ELASTANCE_BOOST: float = 0.30   # mmHg/mL added to la.e_max transiently
const C_WAVE_DECAY_RATE: float      = 10.0   # /s — elastance boost decay after full closure
var _c_wave_boost: float            = 0.0    # current extra elastance on LA

# Aortic valve latch — once closed in a beat, cannot reopen until next VD
var _aortic_latched_shut: bool = false

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
	# Pressure-driven from venous reservoir into RA
	var venous_pressure: float = maxf(0.0, (systemic_venous_volume - SYSTEMIC_VENOUS_UNSTRESSED) / SYSTEMIC_VENOUS_COMPLIANCE)
	var venous_to_ra: float    = maxf(0.0, (venous_pressure - ra.pressure) * SYSTEMIC_VENOUS_TO_RA_CONDUCTANCE * delta)
	venous_to_ra               = minf(venous_to_ra, maxf(0.0, systemic_venous_volume - SYSTEMIC_VENOUS_UNSTRESSED))
	systemic_venous_volume    -= venous_to_ra
	ra.volume                 += venous_to_ra

	# ── Mitral valve (LA → LV) ────────────────────────────────────────────────
	# Systole (VD/ER/T_WAVE/ISOREL): stays closed once LV pressure exceeds LA
	# Diastole: opens only when LV pressure falls below LA pressure
	var ventricular_systole: bool = (
		ep_state == ElectricalPathwayStates.VENTRICULAR_DEPOLARIZATION or
		ep_state == ElectricalPathwayStates.EARLY_REPOLARIZATION or
		ep_state == ElectricalPathwayStates.T_WAVE or
		ep_state == ElectricalPathwayStates.ISOVOLUMETRIC_RELAXATION
	)
	var should_close_mitral: bool = ventricular_systole and (lv.pressure > la.pressure + 1.0)

	if should_close_mitral:
		if la.valve_open:
			la.valve_open          = false
			_mitral_valve_diameter = 1.0
			_c_wave_boost          = 0.0
			EDV                    = lv.volume  # capture EDV at mitral closure
			print("[CARDIO] Mitral CLOSING | LA=%.1fmL p=%.1f | EDV=%.1f" % [la.volume, la.pressure, EDV])
		_resolve_mitral_c_wave(delta)
	elif not ventricular_systole:
		if not la.valve_open and lv.pressure <= la.pressure + 1.0:
			la.valve_open          = true
			_mitral_valve_diameter = 1.0
			_c_wave_boost          = 0.0
			la.e_max               = 0.60

	if la.valve_open:
		var la_force: float = 0.0
		for i in la.region_count:
			if la._regions[i]["mechanical"] == 1:
				la_force += la.myocyte_force[la._regions[i]["myocyte"]]
		if la_force > 0.0:
			var active_flow: float = (LA_CONTRACTION_RATE / float(la.region_count)) * la_force * delta
			active_flow  = minf(active_flow, maxf(0.0, la.volume - la.v0))
			la.volume   -= active_flow
			lv.volume   += active_flow
		var passive_flow: float = maxf(0.0, (la.pressure - lv.pressure) * la.valve_conductance * delta)
		passive_flow  = minf(passive_flow, maxf(0.0, la.volume - la.v0))
		la.volume    -= passive_flow
		lv.volume    += passive_flow

	la.volume = maxf(la.v0, la.volume)

	# ── Aortic valve (LV → aortic volume) ─────────────────────────────────────
	# Latched shut once closed — cannot reopen in same beat. Resets at VD (new beat).
	if not lv.valve_open and not _aortic_latched_shut:
		if ep_cardiac_phase1 and lv.pressure >= aorta_pressure + 2.0:
			lv.valve_open = true
	elif lv.valve_open:
		if lv.pressure < aorta_pressure:
			lv.valve_open        = false
			_aortic_latched_shut = true
			ESV                  = lv.volume  # capture ESV at aortic closure
			print("[CARDIO] Aortic CLOSING | LV=%.1fmL p=%.1f | ESV=%.1f" % [lv.volume, lv.pressure, ESV])

	if lv.valve_open:
		var eject_flow: float = maxf(0.0, (lv.pressure - aorta_pressure) * lv.valve_conductance * delta)
		eject_flow       = minf(eject_flow, maxf(0.0, lv.volume - lv.v0))
		lv.volume       -= eject_flow
		aorta_volume    += eject_flow  # blood enters arterial compartment

	lv.pressure = clampf(lv.pressure, 0.0, 200.0)

	# ── Tricuspid valve (RA → RV) ─────────────────────────────────────────────
	var should_close_tricuspid: bool = ventricular_systole and (rv.pressure > ra.pressure + 1.0)

	if should_close_tricuspid:
		ra.valve_open = false
	elif not ventricular_systole:
		if not ra.valve_open and rv.pressure <= ra.pressure + 1.0:
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

	if not _y_descent_emitted and la.valve_open and pcwp < _pcwp_prev and ep_state == ElectricalPathwayStates.DIASTOLIC_FILLING:
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
# AORTA — Windkessel volume/compliance model
# Aorta is a blood compartment. Pressure derived from volume. No direct pressure hacks.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Two-element Windkessel: compliance C, resistance R (TPR)
# Pressure = (aorta_volume - unstressed_volume) / compliance
# Systemic outflow = aorta_pressure / TPR_effective → drains into systemic venous compartment
var aorta_volume: float             = 700.0   # mL — arterial blood volume
const AORTA_COMPLIANCE: float       = 2.0     # mL/mmHg — C in Windkessel
const AORTA_UNSTRESSED_VOLUME: float = 560.0  # mL — volume at which P = 0  (gives 80 mmHg at 700 mL: (700-560)/2=70, tune)
const SYSTEMIC_RESISTANCE: float    = 1.0     # mmHg·s/mL — outflow resistance (TPR effective)

var aorta_pressure: float      = 93.0   # derived each tick from aorta_volume
var aorta_pressure_min: float  = 8.0
var aorta_pressure_max: float  = 200.0
var aorta_blood_flow: bool     = false
var aorta_blood_flow_end: bool = false
var _aorta_cycle_peak: float   = 0.0
var _aorta_cycle_min: float    = 999.0

# Dicrotic notch — brief pressure perturbation at valve closure
var _aortic_valve_was_open: bool    = false
var _dicrotic_notch_pending: bool   = false
var _dicrotic_notch_boost: float    = 0.0
const DICROTIC_NOTCH_DIP: float    = 5.0    # mmHg drop at closure (incisura)
const DICROTIC_NOTCH_HEIGHT: float = 3.0    # mmHg rebound above dip
const DICROTIC_NOTCH_DECAY: float  = 80.0   # /s — how fast the rebound decays

func _step_aorta(delta: float) -> void:
	# Systemic outflow — Windkessel runoff through peripheral resistance into venous reservoir
	var outflow: float      = maxf(0.0, aorta_pressure / SYSTEMIC_RESISTANCE * delta)
	outflow                 = minf(outflow, maxf(0.0, aorta_volume - AORTA_UNSTRESSED_VOLUME))
	aorta_volume           -= outflow
	systemic_venous_volume += outflow

	# Derive pressure from volume
	aorta_pressure = maxf(0.0, (aorta_volume - AORTA_UNSTRESSED_VOLUME) / AORTA_COMPLIANCE)

	# Dicrotic notch — applies after valve closure, not during systole
	var prev_valve_was_open: bool = _aortic_valve_was_open
	var valve_just_closed: bool   = _aortic_valve_was_open and not lv.valve_open and not ep_cardiac_phase1
	_aortic_valve_was_open        = lv.valve_open

	if valve_just_closed:
		_dicrotic_notch_pending = true
		aorta_pressure         -= DICROTIC_NOTCH_DIP
		_dicrotic_notch_boost   = 0.0
	elif _dicrotic_notch_pending:
		aorta_pressure         += DICROTIC_NOTCH_DIP + DICROTIC_NOTCH_HEIGHT
		_dicrotic_notch_boost   = DICROTIC_NOTCH_HEIGHT
		_dicrotic_notch_pending = false
	elif _dicrotic_notch_boost > 0.0:
		_dicrotic_notch_boost = maxf(0.0, _dicrotic_notch_boost - DICROTIC_NOTCH_DECAY * delta)

	aorta_pressure = clampf(aorta_pressure, aorta_pressure_min, aorta_pressure_max)

	aorta_blood_flow     = lv.valve_open
	aorta_blood_flow_end = not lv.valve_open and ep_cardiac_phase1

	# Track SBP/DBP from actual waveform
	if lv.valve_open:
		# Valve just opened this tick — capture DBP as lowest pressure during prior diastole
		if not prev_valve_was_open and _aorta_cycle_min < 999.0:
			diastolic_bp     = _aorta_cycle_min
			bp_diastolic     = diastolic_bp
			_aorta_cycle_min = 999.0
		_aorta_cycle_peak = maxf(_aorta_cycle_peak, aorta_pressure)
	else:
		_aorta_cycle_min = minf(_aorta_cycle_min, aorta_pressure)
		if valve_just_closed:
			systolic_bp       = _aorta_cycle_peak
			bp_systolic       = systolic_bp
			_aorta_cycle_peak = 0.0


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# PULMONARY ARTERY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var pulmonary_pressure: float = 15.0

func _step_pulmonary_artery(delta: float) -> void:
	if not rv.valve_open:
		pulmonary_pressure -= 4.0 * delta
	pulmonary_pressure = clampf(pulmonary_pressure, 8.0, 30.0)
