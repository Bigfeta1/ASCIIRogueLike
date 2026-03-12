extends Node

# Cardiovascular system — full cardiac cycle.

signal beat_initiated                      # emitted by SA node when threshold reached; triggers electrical pathway
signal atrial_region_depolarized(region: int)  # emitted when each atrial region completes depolarization
signal mitral_valve_closing                # LV pressure first exceeds PCWP — leaflets begin closing; c-wave ascent starts
signal mitral_valve_closed                 # valve fully shut; c-wave peak reached, PCWP snaps back to pre-c baseline

var _organs: Node = null
var _vitals: Node = null
var _levels: Node = null

func _ready() -> void:
	beat_initiated.connect(_on_beat_initiated)
	atrial_region_depolarized.connect(_on_atrial_region_depolarized)
	mitral_valve_closing.connect(_on_mitral_valve_closing)
	mitral_valve_closed.connect(_on_mitral_valve_closed)

func _on_beat_initiated() -> void:
	print("[CARDIO] SA node fired — beat initiated | Vm=%.1f" % sa_node_membrane_potential)
	ep_state_timer    = 0.0
	ep_cycle_reset     = false
	ep_cardiac_phase1 = true
	ep_state          = ElectricalPathwayStates.ATRIAL_DEPOLARIZATION
	_run_electrical_pathway()

func setup(organ_registry: Node, vitals: Node, levels: Node) -> void:
	_organs = organ_registry
	_vitals = vitals
	_levels = levels
	_init_atrial_regions()

func tick(delta: float) -> void:
	_step_sa_node()
	_step_heart()
	_tick_atrial_myocytes(delta)
	_step_left_atria(delta)
	_step_left_ventricle()
	_step_aorta()
	_step_right_atria()
	_step_right_ventricle()
	var region_states: String = ""
	for i in atrial_regions:
		var r: Dictionary = atrial_regions_state[i]
		region_states += "R%d:%s " % [i, AtrialMyocyteState.keys()[r["myocyte"]]]
	print("[CARDIO] tick | SA=%s | atria=%s [%s] | LA=%.1fmL PCWP=%.1fmmHg mitral=%s | LV=%.1fmL LVp=%.1f aortic=%s" % [
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
# HEART (global cardiovascular parameters — _Heart / _Cardiovascular_Controller)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var heart_rate: float        = 60.0    # bpm
var EDV: float               = 0.0     # mL — end-diastolic volume
var ESV: float               = 50.0    # mL — end-systolic volume
var SV: float                = 0.0     # mL — stroke volume = EDV - ESV
var EF: float                = 0.0     # % — ejection fraction
var TPR: float               = 17.7    # mmHg·min/L — total peripheral resistance
var cardiac_output: float    = 0.0     # L/min
var mean_arterial_pressure: float               = 0.0     # mmHg
var pulse_pressure: float    = 40.0    # mmHg
var diastolic_bp: float      = 0.0     # mmHg
var systolic_bp: float       = 0.0     # mmHg
var bp_systolic: float       = 0.0     # alias — kept for cortex/pulmonary compatibility
var bp_diastolic: float      = 0.0     # alias

var venous_return_fraction: float = 1.0

# Metabolic demand — set externally by movement/combat; drives sympathetic tone.
const BASELINE_CO: float = 5.0   # L/min — resting cardiac output
const MAX_CO: float      = 20.0  # L/min — peak exertion cardiac output
var demanded_co: float          = BASELINE_CO
var demanded_co_pre_decay: float = BASELINE_CO
var spo2: float                 = 99.0   # % — set by pulmonary each tick

func set_demand(co: float) -> void:
	demanded_co_pre_decay = co
	demanded_co           = co



func _step_heart() -> void:
	if _organs != null and _organs.renal != null:
		solve_for_preload()
		

	SV = EDV - ESV
	EF = (SV / EDV) * 100.0 if EDV > 0.0 else 0.0

	if not sa_node_cardioplegia:
		cardiac_output = (SV * heart_rate) / 1000.0
	else:
		cardiac_output = 0.0

	mean_arterial_pressure = cardiac_output * TPR
	pulse_pressure = 40.0
	diastolic_bp = mean_arterial_pressure - (pulse_pressure / 3.0)
	systolic_bp  = (3.0 * mean_arterial_pressure) - (2.0 * diastolic_bp)
	bp_systolic  = systolic_bp
	bp_diastolic = diastolic_bp


# Step 1 - Solve For Preload
func solve_for_preload():
	var plasma_fluid = _organs.renal.plasma_fluid
	var plasma_fluid_to_preload_ration = 100.0 / 3750.0 #100 mv SV / 3750 mL plasma fluid
	var cardiac_preload = plasma_fluid * plasma_fluid_to_preload_ration * venous_return_fraction
	EDV = ESV + cardiac_preload



# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SA NODE (_Cardiovascular_SA_Node)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var sa_node_membrane_potential: float = -60.0

var sa_atria_ic_na: float = 0.0
var sa_atria_ic_ca: float = 0.0
var sa_atria_ic_k: float  = 70.0

enum SinoAtrialStates {
	PHASE_4,  # slow diastolic depolarization — Na/Ca influx drives membrane to threshold
	PHASE_0,  # rapid depolarization — threshold reached, signal fires
	PHASE_3   # repolarization — K efflux restores resting potential
}

var sa_state: SinoAtrialStates = SinoAtrialStates.PHASE_4
var sa_node_cardioplegia: bool = false

func _step_sa_node() -> void:
	sa_node_membrane_potential = -130.0 + sa_atria_ic_na + sa_atria_ic_ca + sa_atria_ic_k

	if sa_node_cardioplegia:
		sa_atria_ic_k     = 500.0
		#ep_beat_initiated = false
		return

	match sa_state:
		SinoAtrialStates.PHASE_4:
			# Slow Na influx then Ca influx drives membrane toward threshold
			if sa_node_membrane_potential < -40.0 and sa_atria_ic_na < 20.0:
				sa_atria_ic_na += (20.0 / 49.0) 
			if sa_node_membrane_potential >= -40.0 and sa_node_membrane_potential < 10.0 and sa_atria_ic_ca < 50.0:
				sa_atria_ic_ca += (50.0 / 5.0) 
			
			if sa_node_membrane_potential >= 10.0:
				sa_state = SinoAtrialStates.PHASE_0

		SinoAtrialStates.PHASE_0:
			# Threshold reached — fire beat, transition to repolarization
			beat_initiated.emit()
			sa_state = SinoAtrialStates.PHASE_3

		SinoAtrialStates.PHASE_3:
			# K efflux repolarizes the node back to resting potential
			if sa_atria_ic_k > 0.0:
				sa_atria_ic_k -= (80.0 / 4.0)
			if sa_atria_ic_k <= 0.0:
				sa_atria_ic_na = 0.0
				sa_atria_ic_ca = 0.0
				sa_atria_ic_k  = 70.0
				sa_node_membrane_potential = -60.0
				sa_state = SinoAtrialStates.PHASE_4

#region ELECTRICAL PATHWAY

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 7-phase cycle. Advances when beat_initiated is set by SA node.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var ep_cardiac_phase1: bool  = true   # true during systolic half of cycle
var ep_cycle_reset: bool      = false

enum ElectricalPathwayStates {
	ATRIAL_DEPOLARIZATION,      # signal traveling SA→AV node
	AV_DELAY,                   # atrial repolarization begins here
	VENTRICULAR_DEPOLARIZATION, # QRS complex
	EARLY_REPOLARIZATION,       # ST segment
	T_WAVE,                     # aortic valve closes
	ISOVOLUMETRIC_RELAXATION,   # pressure falls, valves closed
	DIASTOLIC_FILLING           # mitral opens, ventricle fills
}

var ep_state: ElectricalPathwayStates = ElectricalPathwayStates.ATRIAL_DEPOLARIZATION

# Single timer for whichever state is active; duration looked up from table below.
var ep_state_timer: float = 0.0

# Duration (frames) per state. Indexed by ElectricalPathwayStates enum value.
const EP_STATE_DURATIONS: Array[float] = [9.0, 6.0, 3.0, 3.0, 15.0, 3.0, 21.0]

func _run_electrical_pathway() -> void:
	for state in ElectricalPathwayStates.values():
		print("[CARDIO] EP → %s" % ElectricalPathwayStates.keys()[state])
		_ep_transition(state)
		if state == ElectricalPathwayStates.ATRIAL_DEPOLARIZATION:
			_run_atrial_depolarization()
		while not _ep_tick():
			pass

	ep_cycle_reset = true
	_ep_transition(ElectricalPathwayStates.ATRIAL_DEPOLARIZATION)


func _ep_transition(next_state: ElectricalPathwayStates) -> void:
	ep_state_timer = 0.0
	ep_state = next_state

# Advances the timer each call; heart_rate_ratio not applied to early states (SA/AV).
func _ep_tick() -> bool:
	
	var duration: float = EP_STATE_DURATIONS[ep_state]
	
	if ep_state_timer < duration:
		ep_state_timer += 1.0
	
	#return 0 if condition not met. return 1 if met. 
	return ep_state_timer >= duration





#endregion

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# LEFT ATRIA (_Cardiovascular_Left_Atria)
# Tracks PCWP across 7 phases; controls mitral valve.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━



var pcwp: float             = 8.0    # mmHg — derived from la_volume each tick; do not set directly
var mitral_valve_open: bool = true

# LA volume model — PCWP is emergent from volume via compliance equation:
#   pcwp = max(0, (la_volume - la_unstressed_volume) / la_compliance)
var la_volume: float            = 35.0   # mL — current LA volume
const LA_UNSTRESSED_VOLUME: float = 10.0 # mL — volume at zero transmural pressure
const LA_COMPLIANCE: float        = 5.0  # mL/mmHg
const LA_VENOUS_RETURN_RATE: float = 83.0 # mL/s — pulmonary venous return (~5L/min at rest = 83 mL/s)

# Contraction rate: total volume ejected per contraction (~20 mL) spread across myocyte active phases (0.080 s)
const LA_CONTRACTION_RATE: float   = 250.0 # mL/s total; per-region = this / atrial_regions; 250 * 0.08s = 20mL ejected

# C-wave: mitral leaflets bulge into LA during isovolumetric contraction, transiently
# adding effective volume. Diameter 1.0→0.0 as valve closes; la_volume rises proportionally.
# On full closure la_volume snaps back to pre-c baseline.
var mitral_valve_diameter: float  = 1.0   # normalized 1.0 = fully open, 0.0 = fully closed
var la_volume_pre_c_wave: float   = 0.0   # la_volume captured at moment valve starts closing
const C_WAVE_VOLUME: float        = 15.0  # mL — peak effective bulge volume (= 3 mmHg * 5 mL/mmHg)
const MITRAL_CLOSE_RATE: float    = 1.0   # diameter units lost per tick — closes in one tick at this resolution

enum AtriaElectricalState {
	RESTING,
	DEPOLARIZING,
	DEPOLARIZED,
	REPOLARIZING
}

enum AtrialMyocyteState {
	PHASE_0,  # fast Na⁺ influx — rapid depolarization          ~0.002 s
	PHASE_1,  # transient K⁺ outward — initial repolarization   ~0.005 s
	PHASE_2,  # Ca²⁺ plateau balanced by K⁺ efflux             ~0.073 s
	PHASE_3,  # delayed rectifier K⁺ — repolarization           ~0.060 s
	PHASE_4   # resting membrane potential — until next beat
}

const ATRIAL_MYOCYTE_DURATIONS: Dictionary = {
	AtrialMyocyteState.PHASE_0: 0.002,
	AtrialMyocyteState.PHASE_1: 0.005,
	AtrialMyocyteState.PHASE_2: 0.073,
	AtrialMyocyteState.PHASE_3: 0.060,
	AtrialMyocyteState.PHASE_4: 0.0    # dynamic — remainder of cycle
}

enum AtriaMechanicalState {
	CONTRACTION,
	RELAXATION
}

enum AtrialState {
	SYSTOLE,
	DIASTOLE
	
}



const ATRIAL_DEPOLARIZATION_DURATION: float = 0.08
const ATRIAL_REPOLARIZATION_DURATION: float = 0.08



var cardiac_cycle_duration: float = heart_rate / 60.0
var atrial_diastole_duration: float = cardiac_cycle_duration * 0.9
var atrial_systole_duration: float = cardiac_cycle_duration - atrial_diastole_duration

var atrial_regions = 3

const ATRIAL_CONTRACTION_DURATION: float = 0.10
const ATRIAL_ELECTROMECHANICAL_DELAY: float = 0.02


# Time for the signal to depolarize one region chunk (scaleable with atrial_regions)
var time_to_depolarize_node: float = ATRIAL_DEPOLARIZATION_DURATION / atrial_regions

# Per-region state dictionary. Key = region index, value = {electrical, mechanical, myocyte, myocyte_timer}
var atrial_regions_state: Dictionary = {}

func _init_atrial_regions() -> void:
	atrial_regions_state.clear()
	for i in atrial_regions:
		atrial_regions_state[i] = {
			"electrical":   AtriaElectricalState.RESTING,
			"mechanical":   AtriaMechanicalState.RELAXATION,
			"myocyte":      AtrialMyocyteState.PHASE_4,
			"myocyte_timer": 0.0
		}

# Sweep: marks each region as depolarized in sequence, with a delay between each.
# Does NOT wait for action potentials — each region's AP runs independently per tick.
func _run_atrial_depolarization() -> void:
	for i in atrial_regions:
		atrial_regions_state[i]["electrical"] = AtriaElectricalState.DEPOLARIZING
		var timer: float = 0.0
		while timer < time_to_depolarize_node:
			timer += 0.001
		atrial_regions_state[i]["electrical"] = AtriaElectricalState.DEPOLARIZED
		atrial_region_depolarized.emit(i)
		# Note: does NOT call _run_myocyte_action_potential here —
		# the signal triggers it, and it runs tick-driven from then on.


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ATRIAL MYOCYTE CONTROLLER
# Each region runs its action potential independently, advanced per tick.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

const ATRIAL_ELECTROMECHANICAL_DELAY_S: float = 0.015  # 15 ms

var atrial_state: AtrialState = AtrialState.DIASTOLE

# Derives PCWP from LA volume via compliance equation. Call once per tick.
func _derive_pcwp() -> void:
	pcwp = maxf(0.0, (la_volume - LA_UNSTRESSED_VOLUME) / LA_COMPLIANCE)

# Called when mitral valve begins closing — records la_volume baseline for c-wave reference.
func _on_mitral_valve_closing() -> void:
	print("[CARDIO] Mitral CLOSING — c-wave start | LA vol=%.1f mL PCWP=%.1f mmHg" % [la_volume, pcwp])
	la_volume_pre_c_wave  = la_volume
	mitral_valve_diameter = 1.0

# Called when mitral valve fully closes — snap la_volume back to pre-c baseline.
func _on_mitral_valve_closed() -> void:
	print("[CARDIO] Mitral CLOSED — c-wave peak | LA vol=%.1f mL PCWP=%.1f mmHg → snap back" % [la_volume, pcwp])
	la_volume = la_volume_pre_c_wave

# Called when sweep reaches this region — arms it for tick-driven AP progression.
func _on_atrial_region_depolarized(region: int) -> void:
	print("[CARDIO] Atrial region %d depolarized — myocyte PHASE_0 armed" % region)
	atrial_regions_state[region]["myocyte"]      = AtrialMyocyteState.PHASE_0
	atrial_regions_state[region]["myocyte_timer"] = 0.0

# Called every tick — advances each active region's myocyte phase independently.
func _tick_atrial_myocytes(delta: float) -> void:
	# Pulmonary venous return is continuous and independent of myocyte state
	la_volume += LA_VENOUS_RETURN_RATE * delta

	for i in atrial_regions:
		var region: Dictionary = atrial_regions_state[i]
		var phase: AtrialMyocyteState = region["myocyte"]
		if phase == AtrialMyocyteState.PHASE_4:
			continue  # resting — nothing to advance

		region["myocyte_timer"] += delta

		# Phases 0, 1, 2 — active contraction: LA squeezes volume toward LV
		if phase == AtrialMyocyteState.PHASE_0 or phase == AtrialMyocyteState.PHASE_1 or phase == AtrialMyocyteState.PHASE_2:
			var outflow: float = (LA_CONTRACTION_RATE / atrial_regions) * delta
			la_volume -= outflow
			lv_volume += outflow

		var duration: float = ATRIAL_MYOCYTE_DURATIONS[phase]

		if region["myocyte_timer"] >= duration:
			region["myocyte_timer"] = 0.0
			match phase:
				AtrialMyocyteState.PHASE_0:
					region["myocyte"]    = AtrialMyocyteState.PHASE_1
					region["mechanical"] = AtriaMechanicalState.CONTRACTION
					print("[CARDIO] Region %d myocyte PHASE_0→1 (contraction)" % i)
				AtrialMyocyteState.PHASE_1:
					region["myocyte"] = AtrialMyocyteState.PHASE_2
					print("[CARDIO] Region %d myocyte PHASE_1→2 (plateau)" % i)
				AtrialMyocyteState.PHASE_2:
					region["myocyte"] = AtrialMyocyteState.PHASE_3
					print("[CARDIO] Region %d myocyte PHASE_2→3 (relaxation)" % i)
				AtrialMyocyteState.PHASE_3:
					region["myocyte"]    = AtrialMyocyteState.PHASE_4
					region["mechanical"] = AtriaMechanicalState.RELAXATION
					region["electrical"] = AtriaElectricalState.REPOLARIZING
					print("[CARDIO] Region %d myocyte PHASE_3→4 (resting)" % i)
				AtrialMyocyteState.PHASE_4:
					region["electrical"] = AtriaElectricalState.RESTING

	_update_atrial_state()

func _update_atrial_state() -> void:
	var contracting_regions: int = 0
	for i in atrial_regions:
		if atrial_regions_state[i]["mechanical"] == AtriaMechanicalState.CONTRACTION:
			contracting_regions += 1

	if contracting_regions > 0:
		atrial_state = AtrialState.SYSTOLE
	else:
		atrial_state = AtrialState.DIASTOLE

func _step_left_atria(delta: float) -> void:
	_derive_pcwp()

	if lv_pressure > pcwp:
		if mitral_valve_open:
			mitral_valve_closing.emit()
		mitral_valve_open = false
		_resolve_c_wave()
	else:
		mitral_valve_open     = true
		mitral_valve_diameter = 1.0
		_c_wave_snapped       = false
		
		
		# Passive mitral inflow: LA drains into LV down pressure gradient
		var flow: float = ((pcwp - lv_pressure) / LA_COMPLIANCE) * delta
		flow = maxf(0.0, flow)
		la_volume -= flow
		lv_volume += flow
		
		##LATER: Add code to track amount of fluid passed (i.e for stroke volume)

	la_volume = maxf(LA_UNSTRESSED_VOLUME, la_volume)



var _c_wave_snapped: bool = false

func _resolve_c_wave() -> void:
	if mitral_valve_diameter > 0.0:
		mitral_valve_diameter = maxf(0.0, mitral_valve_diameter - MITRAL_CLOSE_RATE)
		la_volume = la_volume_pre_c_wave + C_WAVE_VOLUME * (1.0 - mitral_valve_diameter)
		if mitral_valve_diameter == 0.0:
			_c_wave_snapped = false  # arm the snap for next call

	if mitral_valve_diameter == 0.0 and not _c_wave_snapped:
		_c_wave_snapped = true
		mitral_valve_closed.emit()
	
	
	
	
	
	
	## Atrial depolarization — atrial systole, PCWP rises to max
	## Ventricular depolarization — PCWP rises (isovolumetric contraction)
	#if ep_state == ElectricalPathwayStates.VENTRICULAR_DEPOLARIZATION:
		#if pcwp < 8.0:
			#pcwp += (7.0 / 3.0)

	## Early repolarization — PCWP falls
	#if ep_state == ElectricalPathwayStates.EARLY_REPOLARIZATION:
		#if pcwp > 1.0:
			#pcwp -= (7.0 / 3.0) 

	## T-wave — PCWP rises (v-wave)
	#if ep_state == ElectricalPathwayStates.T_WAVE:
		#if pcwp < 9.0:
			#pcwp += (7.0 / 15.0) 

	## Isovolumetric relaxation — PCWP falls; mitral valve reopens
	#if ep_state == ElectricalPathwayStates.ISOVOLUMETRIC_RELAXATION:
		#if pcwp > 2.0:
			#pcwp -= (7.0 / 3.0) 
		#if pcwp <= 2.0:
			#mitral_valve_open = true

	## Diastolic filling — PCWP resets to baseline
	#if ep_state == ElectricalPathwayStates.DIASTOLIC_FILLING:
		#pcwp = 1.0 

	#if ep_cycle_reset:
		#pcwp = 1.0


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# LEFT VENTRICLE (_Cardiovascular_Left_Ventricle)
# Tracks LV pressure and volume; controls aortic valve.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var lv_pressure: float        = 4.0    # mmHg — starts below resting PCWP so mitral opens on first tick
var lv_pressure_systolic: float = 120.0 # mmHg — peak LV systolic
var lv_pressure_diastolic: float = 10.0 # mmHg — LV end-diastolic
var lv_volume: float          = 100.0   # mL — current LV volume (starts near EDV)
var lv_aortic_valve_open: bool = false

func _step_left_ventricle() -> void:
	# Mitral valve open — LV pressure equalises with PCWP
	if mitral_valve_open and not lv_aortic_valve_open and ep_cardiac_phase1:
		lv_pressure = pcwp

	# Isovolumetric contraction — mitral closed, aortic closed, pressure rising
	if not mitral_valve_open and not lv_aortic_valve_open and ep_cardiac_phase1:
		if lv_pressure < 80.0:
			lv_pressure += pcwp * 4.1
		if lv_pressure >= 80.0 and lv_pressure <= 120.0:
			lv_aortic_valve_open = true

	# Aortic valve open — rapid ejection, pressure continues rising to systolic peak
	if lv_aortic_valve_open:
		if lv_pressure < 120.0 and not aorta_blood_flow:
			lv_pressure += pcwp * 3.5

	# Ejection phase — LV pressure falling as blood enters aorta
	if aorta_blood_flow and not aorta_blood_flow_end:
		if lv_pressure > pcwp:
			lv_pressure -= 1.0 

	# Aortic valve closing — LV pressure drops sharply
	if lv_pressure > pcwp and aorta_blood_flow_end:
		lv_pressure -= 100.0

	# T-wave — aortic valve closes (driven by electrical pathway)
	if ep_state == ElectricalPathwayStates.T_WAVE:
		if ep_state_timer >= EP_STATE_DURATIONS[ElectricalPathwayStates.T_WAVE]:
			lv_aortic_valve_open = false

	# Volume — filling during diastole
	if mitral_valve_open and not lv_aortic_valve_open:
		if lv_volume < EDV:
			lv_volume += (20.0 / 10.0) 

	# Volume — ejection during systole
	if not mitral_valve_open and lv_aortic_valve_open:
		if lv_volume > ESV:
			lv_volume -= (88.0 / 21.0) 

	# Clamp
	lv_pressure = minf(lv_pressure, 120.0)
	lv_pressure = maxf(pcwp, lv_pressure)
	lv_pressure = roundf(lv_pressure)
	lv_volume   = maxf(ESV, lv_volume)

	if ep_cycle_reset:
		lv_volume = EDV - 20.0


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AORTA (_Cardiovascular_Aorta)
# Tracks aortic pressure waveform; drives blood flow flags read by LV.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var aorta_pressure: float      = 90.0   # mmHg
var aorta_pressure_min: float  = 80.0   # mmHg — diastolic floor (= diastolic_bp)
var aorta_pressure_max: float  = 120.0  # mmHg — systolic ceiling (= systolic_bp)
var aorta_blood_flow: bool     = false  # true when LV is actively ejecting
var aorta_blood_flow_end: bool = false  # true after peak ejection, pressure decaying

func _step_aorta() -> void:
	# Before ventricular depolarization — aortic pressure decays toward diastolic
	if ep_state == ElectricalPathwayStates.ATRIAL_DEPOLARIZATION or ep_state == ElectricalPathwayStates.AV_DELAY or ep_state == ElectricalPathwayStates.VENTRICULAR_DEPOLARIZATION:
		if aorta_pressure > diastolic_bp:
			aorta_pressure -= (4.0 / 9.0) 

	# Aortic valve open — aortic pressure matches LV pressure
	if lv_aortic_valve_open:
		aorta_pressure = lv_pressure
		if lv_pressure >= 120.0 and not aorta_blood_flow:
			aorta_blood_flow = true

	# Active ejection — pressure rises toward systolic max after valve closes
	if aorta_blood_flow and not aorta_blood_flow_end:
		if not lv_aortic_valve_open and aorta_pressure < aorta_pressure_max - 5.0:
			aorta_pressure += 5.0
		if not lv_aortic_valve_open and aorta_pressure >= aorta_pressure_max - 15.0:
			aorta_blood_flow_end = true

	# Post-ejection — pressure decays to diastolic
	if aorta_blood_flow and aorta_blood_flow_end:
		if aorta_pressure > aorta_pressure_min:
			aorta_pressure -= 1.0

	# Sync min/max with computed BP each cycle
	aorta_pressure_min = diastolic_bp
	aorta_pressure_max = systolic_bp

	if ep_cycle_reset:
		aorta_blood_flow     = false
		aorta_blood_flow_end = false
		aorta_pressure       = aorta_pressure_min


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# RIGHT ATRIA (_Cardiovascular_Right_Atria)
# Tracks RA pressure; controls tricuspid valve.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var ra_pressure: float         = 4.8   # mmHg
var ra_pressure_max: float     = 6.5   # mmHg
var ra_tricuspid_valve_open: bool = true

func _step_right_atria() -> void:
	# Atrial depolarization — RA fills, pressure rises
	if ep_state == ElectricalPathwayStates.ATRIAL_DEPOLARIZATION:
		if ra_pressure < ra_pressure_max:
			ra_pressure += (1.7 / 6.0)

	# AV delay — RA empties; tricuspid closes in sync with mitral
	if ep_state == ElectricalPathwayStates.AV_DELAY:
		if ra_pressure > 5.0:
			ra_pressure -= (1.5 / 5.0)
		if pcwp <= 2.0 and ep_state_timer >= EP_STATE_DURATIONS[ElectricalPathwayStates.AV_DELAY]:
			ra_tricuspid_valve_open = false

	# Isovolumetric relaxation — tricuspid reopens as pressures fall
	if ep_state == ElectricalPathwayStates.ISOVOLUMETRIC_RELAXATION:
		if pcwp <= 2.0:
			ra_tricuspid_valve_open = true

	if ep_cycle_reset:
		ra_pressure = 4.8


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# RIGHT VENTRICLE (_Cardiovascular_Right_Ventricle)
# Tracks RV pressure; controls pulmonic valve. Slightly delayed vs LV (splitting).
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var rv_pressure: float          = 5.0    # mmHg
var rv_pressure_systolic: float = 20.0   # mmHg — normal RV systolic
var rv_pressure_diastolic: float = 5.0   # mmHg
var rv_pulmonic_valve_open: bool  = false
var rv_pulmonic_valve_timer: float = 3.0
var rv_splitting_modifier: float   = 1.0  # 1 = normal; alter for physiological/pathological splitting

func _step_right_ventricle() -> void:
	# Tricuspid open — RV pressure equalises with RA
	if ra_tricuspid_valve_open and not rv_pulmonic_valve_open:
		rv_pressure = ra_pressure

	# Pulmonic valve open — RV pressure rises toward systolic
	if rv_pulmonic_valve_open:
		if rv_pressure < rv_pressure_systolic:
			rv_pressure += 10.0 

	# Floor at RA pressure
	if rv_pressure < ra_pressure:
		rv_pressure = ra_pressure

	# Pulmonic valve opens slightly after aortic (normal physiological delay)
	if lv_aortic_valve_open and not rv_pulmonic_valve_open:
		rv_pulmonic_valve_timer -= 1.0 * rv_splitting_modifier
		if rv_pulmonic_valve_timer <= 0.0:
			rv_pulmonic_valve_open  = true
			rv_pulmonic_valve_timer = 3.0

	# Pulmonic valve closes slightly after aortic closes
	if not lv_aortic_valve_open and rv_pulmonic_valve_open:
		rv_pulmonic_valve_timer -= 1.0 * rv_splitting_modifier
		if rv_pulmonic_valve_timer <= 0.0:
			rv_pulmonic_valve_open  = false
			rv_pulmonic_valve_timer = 3.0

	rv_pressure = roundf(rv_pressure)
	rv_pressure = maxf(ra_pressure, rv_pressure)

	if ep_cycle_reset:
		rv_pressure = 5.0
		ra_tricuspid_valve_open = false
