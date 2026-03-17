class_name VenaCava
extends Node

@export var debug_name: String = ""

# Systemic venous reservoir. Aortic runoff drains here; RA draws from here.

var volume: float = 3633.4  # mL — steady-state value

const BASELINE_UNSTRESSED_VOLUME: float = 3023.0  # mL — resting value
var   unstressed_volume: float          = 3023.0  # mL — modulated by sympathetic tone
const COMPLIANCE: float                      = 50.0    # mL/mmHg — very compliant veins
const BASELINE_TO_RA_CONDUCTANCE: float      = 14.3    # mL/(s·mmHg) — resting value
var   to_ra_conductance: float               = 14.3    # mL/(s·mmHg) — modulated by sympathetic tone

var pressure: float = 0.0   # derived from volume each tick

# Drains into RA. Returns volume transferred.
func tick(delta: float, ra_pressure: float) -> float:
	pressure = maxf(0.0, (volume - unstressed_volume) / COMPLIANCE)
	var flow: float = maxf(0.0, (pressure - ra_pressure) * to_ra_conductance * delta)
	flow    = minf(flow, maxf(0.0, volume - unstressed_volume))
	volume -= flow
	return flow
