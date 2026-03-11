extends Node

# Cardiovascular system — vascular component.
# Calculates BP and HR from plasma volume via Frank-Starling and baroreceptor reflex.
# Writes results into CharacterVitals for HUD display.
# Renal node reads MAP to modulate RPF.

# Baseline reference values (at normal plasma volume of 3750 mL)
const BASELINE_PLASMA_ML: float = 3750.0
const BASELINE_SV_ML: float = 100.0       # mL
const BASELINE_HR: float = 75.0           # bpm — resting
const BASELINE_SVR: float = 1000.0        # dyn·s·cm⁻⁵ — calibrated to MAP=93 at HR=75, SV=100
const BASELINE_MAP: float = 93.0          # mmHg — CO=7.5 × SVR=1000 / 80
const BASELINE_CO: float = 7.5            # L/min — resting cardiac output (HR=75 × SV=100)
const MAX_CO: float = 20.0               # L/min — physiological ceiling

# Live values
var stroke_volume: float = 100.0          # mL
var heart_rate: float = 75.0              # bpm
var cardiac_output: float = 7.5           # L/min
var systemic_vascular_resistance: float = 1000.0
var mean_arterial_pressure: float = 93.0  # mmHg
var bp_systolic: float = 120.0            # mmHg
var bp_diastolic: float = 80.0            # mmHg
var pulse_pressure: float = 40.0          # mmHg

# Smoothed targets — actual HR and SVR lerp toward these each tick.
# Deterioration (target > current) is faster than recovery (target < current)
# to ensure the mechanical insult dominates and prevents clean oscillation.
var _hr_target: float = 75.0
var _svr_target: float = 1000.0

# Metabolic demand — set by actions, decays toward resting each tick.
# Snaps up instantly if new demand is higher; decays down otherwise.
var demanded_co: float = 7.5              # L/min — matches BASELINE_CO
var spo2: float = 99.0                    # % — written by pulmonary each tick

# Pre-decay snapshot — readable by pulmonary after cardio.tick() to get the demand
# value that drove this turn's HR, before vagal reactivation reduces it.
var demanded_co_pre_decay: float = 7.5

# Venous return fraction — written by pulmonary when tension pneumothorax compresses vena cava.
# 1.0 = normal; falls toward 0.1 as mediastinal shift worsens. Reduces effective preload.
var venous_return_fraction: float = 1.0

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

	# Frank-Starling: stroke volume scales with plasma volume and venous return.
	# venous_return_fraction collapses preload during tension pneumothorax mediastinal shift.
	# Cardio stat raises baseline SV — fitter heart pumps more per beat at any given filling.
	var cardio_sv_bonus: float = 0.0
	if _levels != null:
		cardio_sv_bonus = _levels.stat_mod(_levels.cardio) * 12.0
	var effective_preload: float = plasma_ratio * venous_return_fraction
	effective_preload = maxf(effective_preload, 0.1)
	stroke_volume = (BASELINE_SV_ML + cardio_sv_bonus) * effective_preload

	# Baroreceptor reflex: compensatory tachycardia as preload falls.
	var baroreflex_hr: float = clampf(BASELINE_HR / effective_preload, BASELINE_HR, 180.0)

	# Metabolic demand: HR needed to meet demanded_co given current SV.
	var demand_hr: float = 0.0
	if stroke_volume > 0.0:
		demand_hr = demanded_co * 1000.0 / stroke_volume

	# Hypoxic drive: SpO2 < 90% → peripheral chemoreceptors → sympathetic → tachycardia.
	# Adds up to +60 bpm at SpO2=50% (full hypoxia).
	var hypoxic_hr: float = 0.0
	if spo2 < 90.0:
		hypoxic_hr = BASELINE_HR + (90.0 - spo2) / 40.0 * 60.0

	# Dominant driver wins — sets the HR target this tick.
	_hr_target = clampf(maxf(maxf(baroreflex_hr, demand_hr), hypoxic_hr), BASELINE_HR, 180.0)

	# Lerp heart_rate toward target — faster when rising (deterioration) than falling (recovery).
	# This prevents clean oscillation: the body overshoots upward quickly but recovers slowly.
	var hr_alpha: float = 0.6 if _hr_target > heart_rate else 0.25
	heart_rate = lerpf(heart_rate, _hr_target, hr_alpha)
	heart_rate = clampf(heart_rate, BASELINE_HR, 180.0)

	# Cardiac output (L/min) — reduced by hypoxia (SpO2 < 90% impairs delivery).
	# Below 90% SpO2, effective CO scales down linearly to 50% at SpO2=50%.
	var spo2_modifier: float = 1.0
	if spo2 < 90.0:
		spo2_modifier = 0.5 + (spo2 - 50.0) / 40.0 * 0.5
		spo2_modifier = clampf(spo2_modifier, 0.5, 1.0)
	cardiac_output = (heart_rate * stroke_volume) / 1000.0 * spo2_modifier

	# SVR target: rises with sympathetic tone (dehydration + hypoxia + low preload).
	_svr_target = BASELINE_SVR / plasma_ratio
	# Hypoxia/low preload adds additional sympathetic vasoconstriction
	if spo2 < 90.0 or venous_return_fraction < 1.0:
		var stress: float = maxf(1.0 - venous_return_fraction, (90.0 - spo2) / 40.0)
		_svr_target *= (1.0 + stress * 0.5)

	# SVR also lerps — rises faster than it falls (sympathetic activation is fast, washout is slow).
	var svr_alpha: float = 0.5 if _svr_target > systemic_vascular_resistance else 0.2
	systemic_vascular_resistance = lerpf(systemic_vascular_resistance, _svr_target, svr_alpha)

	# MAP = CO × SVR / 80 (unit conversion factor)
	mean_arterial_pressure = cardiac_output * systemic_vascular_resistance / 80.0

	# Derive systolic and diastolic from MAP and pulse pressure.
	pulse_pressure = 40.0 * (stroke_volume / BASELINE_SV_ML)
	bp_diastolic = mean_arterial_pressure - (pulse_pressure / 3.0)
	bp_systolic = maxf(bp_diastolic + pulse_pressure, 50.0)

	# PEA threshold: BP floored means no effective mechanical output — display HR as 0.
	if bp_systolic <= 50.0:
		heart_rate = 0.0

	# CO-scaled fluid cost: exertion above resting adds up to 3× base insensible loss.
	# Zero at resting CO, full 3× at MAX_CO. Added on top of renal base cost.
	var co_excess: float = maxf(0.0, demanded_co - BASELINE_CO)
	var co_fraction: float = co_excess / (MAX_CO - BASELINE_CO)
	var co_fluid_cost: float = _organs.renal.DEFAULT_ACTION_COST_ML * 3.0 * co_fraction
	_organs.renal.pending_plasma_cost += co_fluid_cost

	# Snapshot pre-decay demand (readable by pulmonary this same turn).
	demanded_co_pre_decay = demanded_co

	# Decay demanded_co toward resting — after all this-turn calculations are done.
	# Modulated by parasympathetic stat — vagal reactivation drives post-exercise recovery.
	var para_mod: int = 0
	if _levels != null:
		para_mod = _levels.stat_mod(_levels.parasympathetic)
	var decay_rate: float = 0.5 + para_mod * 0.1
	demanded_co = maxf(BASELINE_CO, demanded_co - decay_rate)

	# Write into vitals for HUD display.
	if _vitals != null:
		_vitals.bp_systolic = roundi(bp_systolic)
		_vitals.bp_diastolic = roundi(bp_diastolic)
		_vitals.hr = roundi(heart_rate)
		_vitals._refresh_ui()
