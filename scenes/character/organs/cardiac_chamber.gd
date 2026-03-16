class_name CardiacChamber
extends Node

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CONFIGURATION
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## Name shown in the debugger to identify this chamber instance.
@export var debug_name: String = ""

## Minimum elastance (mmHg/mL) at rest — stiffness of the relaxed chamber wall.
@export var e_min: float        = 0.20
## Maximum elastance (mmHg/mL) at peak contraction — stiffness of the fully contracted chamber wall.
@export var e_max: float        = 0.60
## How fast elastance rises toward e_max when myocytes are active (per second).
@export var e_rise_rate: float  = 5.0
## How fast elastance decays back to e_min when myocytes are inactive (per second).
@export var e_decay_rate: float = 3.0

## Unstressed volume (mL) — volume at which chamber pressure is zero. Blood below this threshold generates no pressure.
@export var v0: float             = 4.0
## Starting blood volume (mL) in this chamber at scene load.
@export var initial_volume: float = 35.0

## Whether the outflow valve is open at startup.
@export var valve_open: bool         = false
## Flow conductance of the outflow valve (mL per mmHg per second). Higher = less resistance.
@export var valve_conductance: float = 0.0

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# RUNTIME STATE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var volume:    float = 0.0
var elastance: float = 0.0
var pressure:  float = 0.0

var _myocytes: ChamberMyocytes = null

func _ready() -> void:
	_myocytes = get_node("Myocytes")
	volume    = initial_volume
	elastance = e_min
	pressure  = elastance * maxf(0.0, volume - v0)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# DELEGATES — cardiovascular calls these; myocytes node does the work
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func tick(delta: float) -> void:
	_myocytes.step_chamber(delta)
	step_elastance(delta)

func trigger_sweep() -> void:
	_myocytes.trigger_sweep()

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ELASTANCE + PRESSURE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func step_elastance(delta: float) -> void:
	var normalized_force: float = _myocytes.active_force / float(_myocytes.region_count)
	
	if normalized_force > 0.0:
		elastance = minf(e_max, elastance + normalized_force * e_rise_rate * delta)
	else:
		elastance = maxf(e_min, elastance - e_decay_rate * delta)
	
	pressure = elastance * maxf(0.0, volume - v0)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ACTIVE FORCE — read by cardiac_valve for AV contraction flow
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func get_active_force() -> float:
	return _myocytes.active_force

func get_region_count() -> int:
	return _myocytes.region_count

var in_systole: bool:
	get: return _myocytes.in_systole
