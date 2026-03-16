class_name VenaCava
extends Node

@export var debug_name: String = ""

# Systemic venous reservoir. Aortic runoff drains here; RA draws from here.

var volume: float = 3500.0

const UNSTRESSED_VOLUME: float = 3000.0  # mL — pressure = 0 below this
const COMPLIANCE: float        = 50.0    # mL/mmHg — very compliant veins
const TO_RA_CONDUCTANCE: float = 14.3    # mL/(s·mmHg)

var pressure: float = 0.0   # derived from volume each tick

# Drains into RA. Returns volume transferred.
func tick(delta: float, ra_pressure: float) -> float:
	pressure = maxf(0.0, (volume - UNSTRESSED_VOLUME) / COMPLIANCE)
	var flow: float = maxf(0.0, (pressure - ra_pressure) * TO_RA_CONDUCTANCE * delta)
	flow    = minf(flow, maxf(0.0, volume - UNSTRESSED_VOLUME))
	volume -= flow
	return flow
