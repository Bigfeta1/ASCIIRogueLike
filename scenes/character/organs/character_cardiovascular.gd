extends Node

# Cardiovascular system — full cardiac cycle.

signal beat_initiated                          # SA node threshold reached; triggers EP
signal atrial_region_depolarized(region: int)  # each atrial region completes depolarization
signal mitral_valve_closing                    # LV pressure first exceeds PCWP; c-wave ascent starts
signal mitral_valve_closed                     # valve fully shut; c-wave peak
signal v_wave_peak(pcwp: float)                # PCWP peak at end of ventricular systole — LA maximally filled
signal y_descent_start(pcwp: float)            # mitral opens, LA begins draining into LV

var _organs: Node = null
var _vitals: Node = null
var _levels: Node = null

func _ready() -> void:
	beat_initiated.connect(_on_beat_initiated)
	atrial_region_depolarized.connect(_on_atrial_region_depolarized)
	mitral_valve_closing.connect(_on_mitral_valve_closing)
	mitral_valve_closed.connect(_on_mitral_valve_closed)

func setup(organ_registry: Node, vitals: Node, levels: Node) -> void:
	_organs = organ_registry
	_vitals = vitals
	_levels = levels
	_init_atrial_regions()

func tick(delta: float) -> void:
	_step_sa_node(delta)
	_step_electrical_pathway(delta)
	_step_heart()
	_step_atrial_sweep(delta)
	_tick_atrial_myocytes(delta)
	_step_left_ventricle(delta)
	_step_left_atria(delta)
	_step_aorta(delta)
	_step_right_atria()
	_step_right_ventricle(delta)

	var region_states: String = ""
	for i in atrial_regions:
		var r: Dictionary = atrial_regions_state[i]
		region_states += "R%d:%s " % [i, AtrialMyocyteState.keys()[r["myocyte"]]]
	print("[CARDIO] tick | EP=%s SA=%s | atria=%s [%s] | LA=%.1fmL PCWP=%.1fmmHg mitral=%s | LV=%.1fmL LVp=%.1f aortic=%s" % [
		ElectricalPathwayStates.keys()[ep_state],
		SinoAtrialStates.keys()[sa_state],
		AtrialState.keys()[atrial_state],
		region_states.strip_edges(),
		la_volume, pcwp,
		"O" if mitral_valve_open else "X",
		lv_volume, lv_pressure,
		"O" if lv_aortic_valve_open else "X",
	])

func force_fire_sa_node() -> void:
	sa_node_membrane_potential = 10.0
	sa_state                   = SinoAtrialStates.PHASE_0


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# HEART
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var heart_rate: float           = 60.0
var EDV: float                  = 0.0
var ESV: float                  = 50.0
var SV: float                   = 0.0
var EF: float                   = 0.0
var TPR: float                  = 17.7
var cardiac_output: float       = 0.0
var mean_arterial_pressure: float = 0.0
var pulse_pressure: float       = 40.0
var diastolic_bp: float         = 0.0
var systolic_bp: float          = 0.0
var bp_systolic: float          = 0.0   # alias for cortex/pulmonary compatibility
var bp_diastolic: float         = 0.0   # alias

var venous_return_fraction: float = 1.0

const BASELINE_CO: float = 5.0
const MAX_CO: float      = 20.0
var demanded_co: float           = BASELINE_CO
var demanded_co_pre_decay: float = BASELINE_CO
var spo2: float                  = 99.0

func set_demand(co: float) -> void:
	demanded_co_pre_decay = co
	demanded_co           = co

func _step_heart() -> void:
	_update_cycle_durations()
	if _organs != null and _organs.renal != null:
		solve_for_preload()

	SV = EDV - ESV
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

func solve_for_preload() -> void:
	var plasma_fluid: float              = _organs.renal.plasma_fluid
	var plasma_fluid_to_preload_ratio: float = 100.0 / 3750.0
	var cardiac_preload: float           = plasma_fluid * plasma_fluid_to_preload_ratio * venous_return_fraction
	EDV = ESV + cardiac_preload

func _update_cycle_durations() -> void:
	cardiac_cycle_duration   = 60.0 / heart_rate
	atrial_systole_duration  = 0.10
	atrial_diastole_duration = maxf(0.0, cardiac_cycle_duration - atrial_systole_duration)
	time_to_depolarize_node  = ATRIAL_DEPOLARIZATION_DURATION / float(atrial_regions)


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

# Durations in seconds, indexed by ElectricalPathwayStates enum value.
const EP_STATE_DURATIONS: Array[float] = [0.08, 0.06, 0.03, 0.03, 0.15, 0.03, 0.21]

func _on_beat_initiated() -> void:
	print("[CARDIO] SA node fired | Vm=%.1f" % sa_node_membrane_potential)
	ep_cycle_reset = false
	ep_running     = true
	_ep_transition(ElectricalPathwayStates.ATRIAL_DEPOLARIZATION)
	_run_atrial_depolarization()

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
# LEFT ATRIA
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var pcwp: float             = 8.0
var mitral_valve_open: bool = true
var _pcwp_prev: float       = 8.0
var _v_wave_emitted: bool   = false
var _y_descent_emitted: bool = false

# LA volume — PCWP derived via: pcwp = max(0, (la_volume - LA_UNSTRESSED_VOLUME) / LA_COMPLIANCE)
var la_volume: float              = 35.0
const LA_UNSTRESSED_VOLUME: float = 10.0  # mL — volume at zero transmural pressure
# LA compliance is nonlinear — see _derive_pcwp()
const LA_VENOUS_RETURN_RATE_SYSTOLE: float  = 120.0 # mL/s — reservoir phase (mitral closed, LA filling)
const LA_VENOUS_RETURN_RATE_DIASTOLE: float = 50.0  # mL/s — conduit/booster phase (LA emptying into LV)

func _get_pulmonary_venous_return_rate() -> float:
	return LA_VENOUS_RETURN_RATE_SYSTOLE if ep_cardiac_phase1 else LA_VENOUS_RETURN_RATE_DIASTOLE
const LA_CONTRACTION_RATE: float  = 250.0 # mL/s total; /atrial_regions per region; * 0.08s ≈ 20 mL ejected
const MITRAL_CONDUCTANCE: float   = 25.0  # mL/s/mmHg — passive mitral flow rate

# C-wave: leaflet bulge adds transient pressure during mitral closure — modeled directly on PCWP.
var mitral_valve_diameter: float    = 1.0
var c_wave_pressure: float          = 0.0
const C_WAVE_PEAK_PRESSURE: float   = 3.0   # mmHg — peak c-wave pressure contribution
const MITRAL_CLOSE_RATE: float      = 33.3  # diameter/s — closes fully in ~0.03 s
const C_WAVE_DECAY_RATE: float      = 100.0 # mmHg/s — c-wave pressure decay after full closure

enum AtriaElectricalState { RESTING, DEPOLARIZING, DEPOLARIZED, REPOLARIZING }
enum AtrialMyocyteState {
	PHASE_0,  # fast Na⁺ influx — rapid depolarization          ~0.002 s
	PHASE_1,  # transient K⁺ outward — initial repolarization   ~0.005 s
	PHASE_2,  # Ca²⁺ plateau balanced by K⁺ efflux             ~0.073 s
	PHASE_3,  # delayed rectifier K⁺ — repolarization           ~0.060 s
	PHASE_4   # resting membrane potential
}
enum AtriaMechanicalState { CONTRACTION, RELAXATION }
enum AtrialState { SYSTOLE, DIASTOLE }

const ATRIAL_MYOCYTE_DURATIONS: Dictionary = {
	AtrialMyocyteState.PHASE_0: 0.002,
	AtrialMyocyteState.PHASE_1: 0.005,
	AtrialMyocyteState.PHASE_2: 0.073,
	AtrialMyocyteState.PHASE_3: 0.060,
	AtrialMyocyteState.PHASE_4: 0.0
}

const ATRIAL_MYOCYTE_FORCE: Dictionary = {
	AtrialMyocyteState.PHASE_0: 0.15,  # rapid depolarization — force just beginning to develop
	AtrialMyocyteState.PHASE_1: 0.50,  # early contraction — rising force
	AtrialMyocyteState.PHASE_2: 1.00,  # plateau — peak force
	AtrialMyocyteState.PHASE_3: 0.20,  # repolarization — force tapering off
	AtrialMyocyteState.PHASE_4: 0.00   # resting
}

const ATRIAL_DEPOLARIZATION_DURATION: float = 0.08
const ATRIAL_REPOLARIZATION_DURATION: float = 0.08

var cardiac_cycle_duration: float   = 1.0
var atrial_diastole_duration: float = 0.9
var atrial_systole_duration: float  = 0.1

var atrial_regions: int = 3
var time_to_depolarize_node: float  = ATRIAL_DEPOLARIZATION_DURATION / 3.0

var atrial_regions_state: Dictionary = {}
var atrial_state: AtrialState        = AtrialState.DIASTOLE

# Atrial sweep state
var atrial_sweep_active: bool       = false
var atrial_sweep_region_index: int  = 0
var atrial_sweep_timer: float       = 0.0

func _init_atrial_regions() -> void:
	atrial_regions_state.clear()
	for i in atrial_regions:
		atrial_regions_state[i] = {
			"electrical":    AtriaElectricalState.RESTING,
			"mechanical":    AtriaMechanicalState.RELAXATION,
			"myocyte":       AtrialMyocyteState.PHASE_4,
			"myocyte_timer": 0.0
		}

func _run_atrial_depolarization() -> void:
	atrial_sweep_active       = true
	atrial_sweep_region_index = 0
	atrial_sweep_timer        = 0.0
	for i in atrial_regions:
		atrial_regions_state[i]["electrical"]    = AtriaElectricalState.RESTING
		atrial_regions_state[i]["mechanical"]    = AtriaMechanicalState.RELAXATION
		atrial_regions_state[i]["myocyte"]       = AtrialMyocyteState.PHASE_4
		atrial_regions_state[i]["myocyte_timer"] = 0.0

func _step_atrial_sweep(delta: float) -> void:
	if not atrial_sweep_active:
		return
	atrial_sweep_timer += delta
	while atrial_sweep_timer >= time_to_depolarize_node and atrial_sweep_region_index < atrial_regions:
		atrial_sweep_timer -= time_to_depolarize_node
		atrial_regions_state[atrial_sweep_region_index]["electrical"] = AtriaElectricalState.DEPOLARIZED
		atrial_region_depolarized.emit(atrial_sweep_region_index)
		atrial_sweep_region_index += 1
	if atrial_sweep_region_index >= atrial_regions:
		atrial_sweep_active = false

func _derive_pcwp() -> void:
	var x: float = maxf(0.0, la_volume - LA_UNSTRESSED_VOLUME)
	pcwp = 2.0 * (exp(x / 20.0) - 1.0) + c_wave_pressure

func _on_mitral_valve_closing() -> void:
	print("[CARDIO] Mitral CLOSING — c-wave start | LA=%.1f mL PCWP=%.1f mmHg" % [la_volume, pcwp])
	mitral_valve_diameter = 1.0
	c_wave_pressure       = 0.0

func _on_mitral_valve_closed() -> void:
	print("[CARDIO] Mitral CLOSED — c-wave peak | LA=%.1f mL PCWP=%.1f mmHg" % [la_volume, pcwp])

func _on_atrial_region_depolarized(region: int) -> void:
	print("[CARDIO] Atrial region %d depolarized — myocyte PHASE_0 armed" % region)
	atrial_regions_state[region]["myocyte"]       = AtrialMyocyteState.PHASE_0
	atrial_regions_state[region]["myocyte_timer"]  = 0.0
	atrial_regions_state[region]["mechanical"]    = AtriaMechanicalState.CONTRACTION

func _tick_atrial_myocytes(delta: float) -> void:
	la_volume += _get_pulmonary_venous_return_rate() * delta

	for i in atrial_regions:
		var region: Dictionary = atrial_regions_state[i]
		var phase: AtrialMyocyteState = region["myocyte"]
		if phase == AtrialMyocyteState.PHASE_4:
			continue

		region["myocyte_timer"] += delta

		var force: float = ATRIAL_MYOCYTE_FORCE[phase]
		if mitral_valve_open and force > 0.0:
			var outflow: float = (LA_CONTRACTION_RATE / float(atrial_regions)) * force * delta
			outflow = minf(outflow, maxf(0.0, la_volume - LA_UNSTRESSED_VOLUME))
			la_volume -= outflow
			lv_volume += outflow

		var duration: float = ATRIAL_MYOCYTE_DURATIONS[phase]
		if duration > 0.0 and region["myocyte_timer"] >= duration:
			region["myocyte_timer"] = 0.0
			match phase:
				AtrialMyocyteState.PHASE_0:
					region["myocyte"] = AtrialMyocyteState.PHASE_1
					print("[CARDIO] Region %d myocyte PHASE_0→1 (plateau onset)" % i)
				AtrialMyocyteState.PHASE_1:
					region["myocyte"] = AtrialMyocyteState.PHASE_2
					print("[CARDIO] Region %d myocyte PHASE_1→2 (plateau)" % i)
				AtrialMyocyteState.PHASE_2:
					region["myocyte"] = AtrialMyocyteState.PHASE_3
					print("[CARDIO] Region %d myocyte PHASE_2→3 (relaxation)" % i)
				AtrialMyocyteState.PHASE_3:
					region["myocyte"] = AtrialMyocyteState.PHASE_4
					region["mechanical"] = AtriaMechanicalState.RELAXATION
					region["electrical"] = AtriaElectricalState.REPOLARIZING
					print("[CARDIO] Region %d myocyte PHASE_3→4 (resting)" % i)

	_update_atrial_state()

func _update_atrial_state() -> void:
	var contracting: int = 0
	for i in atrial_regions:
		if atrial_regions_state[i]["mechanical"] == AtriaMechanicalState.CONTRACTION:
			contracting += 1
	atrial_state = AtrialState.SYSTOLE if contracting > 0 else AtrialState.DIASTOLE

func _step_left_atria(delta: float) -> void:
	_derive_pcwp()

	var ventricular_closure_phase: bool = (
		ep_state == ElectricalPathwayStates.VENTRICULAR_DEPOLARIZATION or
		ep_state == ElectricalPathwayStates.EARLY_REPOLARIZATION or
		ep_state == ElectricalPathwayStates.T_WAVE
	)

	var should_close_mitral: bool = ventricular_closure_phase and (lv_pressure > pcwp + 1.0)

	if should_close_mitral:
		if mitral_valve_open:
			mitral_valve_closing.emit()
			mitral_valve_open = false
		_resolve_c_wave(delta)
	else:
		if not ventricular_closure_phase:
			mitral_valve_open     = true
			mitral_valve_diameter = 1.0
			c_wave_pressure       = 0.0

		if mitral_valve_open:
			var flow: float = maxf(0.0, (pcwp - lv_pressure) * MITRAL_CONDUCTANCE * delta)
			flow       = minf(flow, maxf(0.0, la_volume - LA_UNSTRESSED_VOLUME))
			la_volume -= flow
			lv_volume += flow

	la_volume = maxf(LA_UNSTRESSED_VOLUME, la_volume)

	# V-wave peak: PCWP was rising during systole and just turned over
	if not _v_wave_emitted and not ep_cardiac_phase1 and not mitral_valve_open and pcwp < _pcwp_prev:
		_v_wave_emitted = true
		v_wave_peak.emit(pcwp)
		print("[CARDIO] v-wave peak detected | PCWP=%.1f mmHg" % pcwp)

	# Y-descent start: mitral just opened and PCWP is falling
	if not _y_descent_emitted and mitral_valve_open and pcwp < _pcwp_prev:
		_y_descent_emitted = true
		y_descent_start.emit(pcwp)
		print("[CARDIO] y-descent start detected | PCWP=%.1f mmHg" % pcwp)

	_pcwp_prev = pcwp

func _resolve_c_wave(delta: float) -> void:
	if mitral_valve_diameter > 0.0:
		mitral_valve_diameter = maxf(0.0, mitral_valve_diameter - MITRAL_CLOSE_RATE * delta)
		c_wave_pressure = C_WAVE_PEAK_PRESSURE * (1.0 - mitral_valve_diameter)
		if mitral_valve_diameter == 0.0:
			mitral_valve_closed.emit()
	else:
		c_wave_pressure = maxf(0.0, c_wave_pressure - C_WAVE_DECAY_RATE * delta)


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# LEFT VENTRICLE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var lv_pressure: float           = 4.0
var lv_volume: float             = 100.0
var lv_aortic_valve_open: bool   = false

# Time-varying elastance model: lv_pressure = E(t) * (lv_volume - V0)
# E(t) ramps up during systole and decays during diastole.
var lv_elastance: float          = 0.1   # mmHg/mL — current elastance
const LV_E_MIN: float            = 0.1   # mmHg/mL — diastolic (passive) elastance
const LV_E_MAX: float            = 2.5   # mmHg/mL — systolic (active) elastance
const LV_E_RISE_RATE: float      = 30.0  # /s — elastance rise rate during systole
const LV_E_DECAY_RATE: float     = 8.0   # /s — elastance decay rate during diastole
const LV_V0: float               = 10.0  # mL — dead volume (pressure = 0 at this volume)

func _step_left_ventricle(delta: float) -> void:
	# Drive elastance up during systole, decay during diastole
	if ep_cardiac_phase1:
		lv_elastance = minf(LV_E_MAX, lv_elastance + LV_E_RISE_RATE * delta)
	else:
		lv_elastance = maxf(LV_E_MIN, lv_elastance - LV_E_DECAY_RATE * delta)

	# LV pressure fully emergent from elastance and volume
	lv_pressure = lv_elastance * maxf(0.0, lv_volume - LV_V0)

	# Aortic valve: opens when LV pressure exceeds aorta, closes when it falls below
	if not lv_aortic_valve_open and lv_pressure >= aorta_pressure:
		lv_aortic_valve_open = true
	if lv_aortic_valve_open and lv_pressure < aorta_pressure:
		lv_aortic_valve_open = false

	# Ejection — flow proportional to LV-aorta pressure gradient
	if lv_aortic_valve_open:
		var eject_flow: float = maxf(0.0, (lv_pressure - aorta_pressure) * 3.0 * delta)
		eject_flow = minf(eject_flow, maxf(0.0, lv_volume - LV_V0))
		lv_volume     -= eject_flow
		aorta_pressure += eject_flow * 0.5

	lv_pressure = clampf(lv_pressure, 0.0, 200.0)
	lv_volume   = clampf(lv_volume, ESV, EDV)


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AORTA
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var aorta_pressure: float      = 90.0
var aorta_pressure_min: float  = 80.0
var aorta_pressure_max: float  = 120.0
var aorta_blood_flow: bool     = false
var aorta_blood_flow_end: bool = false

func _step_aorta(delta: float) -> void:
	if not lv_aortic_valve_open:
		aorta_pressure -= 25.0 * delta

	aorta_pressure_min = diastolic_bp
	aorta_pressure_max = systolic_bp
	aorta_pressure     = clampf(aorta_pressure, aorta_pressure_min, aorta_pressure_max)

	aorta_blood_flow     = lv_aortic_valve_open
	aorta_blood_flow_end = not lv_aortic_valve_open and ep_cardiac_phase1


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# RIGHT ATRIA
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var ra_pressure: float            = 4.8
var ra_pressure_max: float        = 6.5
var ra_tricuspid_valve_open: bool = true

func _step_right_atria() -> void:
	if ep_state == ElectricalPathwayStates.ATRIAL_DEPOLARIZATION:
		if ra_pressure < ra_pressure_max:
			ra_pressure += (1.7 / 6.0)

	if ep_state == ElectricalPathwayStates.AV_DELAY:
		if ra_pressure > 5.0:
			ra_pressure -= (1.5 / 5.0)
		if pcwp <= 2.0 and ep_state_timer >= EP_STATE_DURATIONS[ElectricalPathwayStates.AV_DELAY]:
			ra_tricuspid_valve_open = false

	if ep_state == ElectricalPathwayStates.ISOVOLUMETRIC_RELAXATION:
		if pcwp <= 2.0:
			ra_tricuspid_valve_open = true

	if ep_cycle_reset:
		ra_pressure = 4.8


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# RIGHT VENTRICLE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var rv_pressure: float           = 5.0
var rv_pressure_systolic: float  = 20.0
var rv_pressure_diastolic: float = 5.0
var rv_pulmonic_valve_open: bool = false
var rv_pulmonic_valve_timer: float = 3.0
var rv_splitting_modifier: float   = 1.0

func _step_right_ventricle(delta: float) -> void:
	if ra_tricuspid_valve_open and not rv_pulmonic_valve_open:
		rv_pressure = ra_pressure

	if rv_pulmonic_valve_open:
		if rv_pressure < rv_pressure_systolic:
			rv_pressure += 10.0 * delta

	if rv_pressure < ra_pressure:
		rv_pressure = ra_pressure

	if lv_aortic_valve_open and not rv_pulmonic_valve_open:
		rv_pulmonic_valve_timer -= 1.0 * rv_splitting_modifier
		if rv_pulmonic_valve_timer <= 0.0:
			rv_pulmonic_valve_open  = true
			rv_pulmonic_valve_timer = 3.0

	if not lv_aortic_valve_open and rv_pulmonic_valve_open:
		rv_pulmonic_valve_timer -= 1.0 * rv_splitting_modifier
		if rv_pulmonic_valve_timer <= 0.0:
			rv_pulmonic_valve_open  = false
			rv_pulmonic_valve_timer = 3.0

	rv_pressure = roundf(rv_pressure)
	rv_pressure = maxf(ra_pressure, rv_pressure)

	if ep_cycle_reset:
		rv_pressure             = 5.0
		ra_tricuspid_valve_open = false
