class_name Aorta
extends Node

@export var debug_name: String = ""

# Two-element Windkessel model.
# Pressure derived from volume each tick.
# Systemic outflow drains into the systemic venous reservoir (owned by cardiovascular coordinator).

var volume: float   = 620.0   # mL — arterial blood volume
var pressure: float = 80.0    # derived from volume each tick

var blood_flow:     bool = false   # true while aortic valve open
var blood_flow_end: bool = false   # true the tick the aortic valve closes

var pressure_min: float = 8.0
var pressure_max: float = 200.0

const COMPLIANCE: float        = 1.575   # mL/mmHg
const UNSTRESSED_VOLUME: float = 550.0 # mL
const BASELINE_SYSTEMIC_RESISTANCE: float = 1.2725 # mmHg·s/mL — resting value
var   systemic_resistance: float          = 1.2725 # mmHg·s/mL — modulated by sympathetic tone

# Returns the volume drained into the systemic venous reservoir this tick.
func tick(delta: float, valve_open: bool, notch_fired: bool, notch_dip: float) -> float:
	blood_flow     = valve_open
	blood_flow_end = notch_fired

	pressure = maxf(0.0, (volume - UNSTRESSED_VOLUME) / COMPLIANCE)

	var outflow: float = maxf(0.0, pressure / systemic_resistance * delta)
	outflow             = minf(outflow, maxf(0.0, volume - UNSTRESSED_VOLUME))
	volume             -= outflow

	pressure = maxf(0.0, (volume - UNSTRESSED_VOLUME) / COMPLIANCE)

	if notch_fired:
		pressure = maxf(0.0, pressure - notch_dip)

	pressure = clampf(pressure, pressure_min, pressure_max)

	return outflow
