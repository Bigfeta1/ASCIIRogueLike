extends Node

# Cardiovascular system — vascular component.
# Calculates BP and HR from plasma volume via Frank-Starling and baroreceptor reflex.
# Writes results into CharacterVitals for HUD display.
# Renal node reads MAP to modulate RPF.

# Baseline reference values (at normal plasma volume of 3750 mL)
const BASELINE_PLASMA_ML: float = 3750.0
const BASELINE_SV_ML: float = 99.0        # mL — gives CO=7.425 L/min at HR=75, MAP=93 at SVR=1000
const BASELINE_HR: float = 75.0           # bpm
const BASELINE_SVR: float = 1000.0        # dyn·s·cm⁻⁵ — mid-normal range
const BASELINE_MAP: float = 93.0          # mmHg — (120 + 2×80) / 3

# Live values
var stroke_volume: float = 99.0           # mL
var heart_rate: float = 75.0              # bpm
var cardiac_output: float = 7.425         # L/min
var systemic_vascular_resistance: float = 1000.0
var mean_arterial_pressure: float = 93.0  # mmHg
var bp_systolic: float = 120.0            # mmHg
var bp_diastolic: float = 80.0            # mmHg
var pulse_pressure: float = 40.0          # mmHg

var _organs: Node = null
var _vitals: Node = null


func setup(organ_registry: Node, vitals: Node) -> void:
	_organs = organ_registry
	_vitals = vitals


func tick() -> void:
	if _organs == null or _organs.renal == null:
		return
	var plasma: float = _organs.renal.plasma_fluid

	# Frank-Starling: stroke volume scales with plasma volume.
	# Linear relationship — at 0 plasma, SV = 0; at baseline, SV = 70 mL.
	stroke_volume = BASELINE_SV_ML * (plasma / BASELINE_PLASMA_ML)

	# Baroreceptor reflex: compensatory tachycardia as plasma falls.
	# HR rises inversely with plasma volume, capped at 180 bpm.
	var plasma_ratio := plasma / BASELINE_PLASMA_ML
	heart_rate = clampf(BASELINE_HR / plasma_ratio, BASELINE_HR, 180.0)

	# Cardiac output (L/min)
	cardiac_output = (heart_rate * stroke_volume) / 1000.0

	# SVR rises with dehydration (sympathetic vasoconstriction).
	# Partially compensates for falling CO to maintain MAP.
	systemic_vascular_resistance = BASELINE_SVR / plasma_ratio

	# MAP = CO × SVR / 80 (unit conversion factor)
	mean_arterial_pressure = cardiac_output * systemic_vascular_resistance / 80.0

	# Derive systolic and diastolic from MAP and pulse pressure.
	# Pulse pressure narrows with hypovolemia (less SV).
	pulse_pressure = 40.0 * (stroke_volume / BASELINE_SV_ML)
	# MAP = DBP + 1/3 PP  →  DBP = MAP - PP/3
	bp_diastolic = mean_arterial_pressure - (pulse_pressure / 3.0)
	bp_systolic = bp_diastolic + pulse_pressure

	# Write into vitals for HUD display.
	if _vitals != null:
		_vitals.bp_systolic = roundi(bp_systolic)
		_vitals.bp_diastolic = roundi(bp_diastolic)
		_vitals.hr = roundi(heart_rate)
		_vitals._refresh_ui()
