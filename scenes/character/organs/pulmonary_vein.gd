class_name PulmonaryVein
extends Node

@export var debug_name: String = ""

# Pulmonary venous reservoir. RV ejects here; LA draws from here.

var volume: float = 380.0

const UNSTRESSED_VOLUME: float = 300.0  # mL
const COMPLIANCE: float        = 10.0   # mL/mmHg
const TO_LA_CONDUCTANCE: float = 23.0   # mL/(s·mmHg)

var pressure: float = 0.0   # derived from volume each tick

# Drains into LA. Returns volume transferred.
func tick(delta: float, la_pressure: float) -> float:
	pressure = maxf(0.0, (volume - UNSTRESSED_VOLUME) / COMPLIANCE)
	var flow: float = maxf(0.0, (pressure - la_pressure) * TO_LA_CONDUCTANCE * delta)
	flow    = minf(flow, maxf(0.0, volume - UNSTRESSED_VOLUME))
	volume -= flow
	return flow
