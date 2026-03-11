extends Node

# Cardiovascular system — vascular component.
# Calculates BP and HR from plasma volume via Frank-Starling and baroreceptor reflex.
# Writes results into CharacterVitals for HUD display.
# Renal node reads MAP to modulate RPF.

# Baseline reference values (at normal plasma volume of 3750 mL)
const BASELINE_PLASMA_ML: float = 3750.0
const BASELINE_SV_ML: float = 99.0        # mL — gives CO=7.425 L/min at HR=75, MAP=93 at SVR=1000
const BASELINE_HR: float = 60.0           # bpm — resting
const BASELINE_SVR: float = 1000.0        # dyn·s·cm⁻⁵ — mid-normal range
const BASELINE_MAP: float = 93.0          # mmHg — (120 + 2×80) / 3
const BASELINE_CO: float = 5.94           # L/min — resting cardiac output (HR=60 × SV=99)
const MAX_CO: float = 20.0               # L/min — physiological ceiling

# Live values
var stroke_volume: float = 99.0           # mL
var heart_rate: float = 60.0              # bpm
var cardiac_output: float = 5.94          # L/min
var systemic_vascular_resistance: float = 1000.0
var mean_arterial_pressure: float = 93.0  # mmHg
var bp_systolic: float = 120.0            # mmHg
var bp_diastolic: float = 80.0            # mmHg
var pulse_pressure: float = 40.0          # mmHg

# Metabolic demand — set by actions, decays toward resting each tick.
# Snaps up instantly if new demand is higher; decays down otherwise.
var demanded_co: float = 5.94             # L/min — matches BASELINE_CO

var _organs: Node = null
var _vitals: Node = null
var _levels: Node = null


func setup(organ_registry: Node, vitals: Node, levels: Node) -> void:
	_organs = organ_registry
	_vitals = vitals
	_levels = levels


func set_demand(co: float) -> void:
	if co > demanded_co:
		demanded_co = co


func tick() -> void:
	if _organs == null or _organs.renal == null:
		return
	var plasma: float = _organs.renal.plasma_fluid

	# Floor plasma_ratio to prevent SVR/HR from going to infinity at near-zero plasma.
	var plasma_ratio := maxf(plasma / BASELINE_PLASMA_ML, 0.1)

	# Frank-Starling: stroke volume scales with plasma volume.
	# Cardio stat raises baseline SV — fitter heart pumps more per beat at any given filling.
	var cardio_sv_bonus: float = 0.0
	if _levels != null:
		cardio_sv_bonus = _levels.stat_mod(_levels.cardio) * 12.0
	stroke_volume = (BASELINE_SV_ML + cardio_sv_bonus) * plasma_ratio

	# Baroreceptor reflex: compensatory tachycardia as plasma falls.
	var baroreflex_hr: float = clampf(BASELINE_HR / plasma_ratio, BASELINE_HR, 180.0)

	# Metabolic demand: HR needed to meet demanded_co given current SV.
	var demand_hr: float = 0.0
	if stroke_volume > 0.0:
		demand_hr = demanded_co * 1000.0 / stroke_volume

	# Dominant driver wins — whichever requires the higher HR.
	heart_rate = clampf(maxf(baroreflex_hr, demand_hr), BASELINE_HR, 180.0)

	# Decay demanded_co toward resting after HR is solved for this turn.
	# Modulated by parasympathetic stat — vagal reactivation drives post-exercise recovery.
	var para_mod: int = 0
	if _levels != null:
		para_mod = _levels.stat_mod(_levels.parasympathetic)
	var decay_rate: float = 0.5 + para_mod * 0.1
	demanded_co = maxf(BASELINE_CO, demanded_co - decay_rate)

	# Cardiac output (L/min)
	cardiac_output = (heart_rate * stroke_volume) / 1000.0

	# SVR rises with dehydration (sympathetic vasoconstriction).
	systemic_vascular_resistance = BASELINE_SVR / plasma_ratio

	# MAP = CO × SVR / 80 (unit conversion factor)
	mean_arterial_pressure = cardiac_output * systemic_vascular_resistance / 80.0

	# Derive systolic and diastolic from MAP and pulse pressure.
	pulse_pressure = 40.0 * (stroke_volume / BASELINE_SV_ML)
	bp_diastolic = mean_arterial_pressure - (pulse_pressure / 3.0)
	bp_systolic = bp_diastolic + pulse_pressure

	# CO-scaled fluid cost: exertion above resting adds up to 3× base insensible loss.
	# Zero at resting CO, full 3× at MAX_CO. Added on top of renal base cost.
	var co_excess: float = maxf(0.0, demanded_co - BASELINE_CO)
	var co_fraction: float = co_excess / (MAX_CO - BASELINE_CO)
	var co_fluid_cost: float = _organs.renal.DEFAULT_ACTION_COST_ML * 3.0 * co_fraction
	_organs.renal.pending_plasma_cost += co_fluid_cost

	# Write into vitals for HUD display.
	if _vitals != null:
		_vitals.bp_systolic = roundi(bp_systolic)
		_vitals.bp_diastolic = roundi(bp_diastolic)
		_vitals.hr = roundi(heart_rate)
		_vitals._refresh_ui()
