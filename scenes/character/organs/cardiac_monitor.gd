class_name CardiacMonitor
extends Node

# Sampled/derived cardiovascular metrics.
# Written by CharacterCardiovascular each tick. Read by cortex, world_state, debug panels, etc.
# Not simulation state — nothing in here drives the simulation.

var EDV: float                    = 120.0   # mL — LV volume at mitral closure
var ESV: float                    = 50.0    # mL — LV volume at aortic closure
var SV: float                     = 0.0     # mL — stroke volum e
var EF: float                     = 0.0     # % — ejection fraction
var cardiac_output: float         = 0.0     # L/min
var mean_arterial_pressure: float = 0.0     # mmHg
var pulse_pressure: float         = 40.0    # mmHg
var bp_systolic: float            = 120.0   # mmHg — sampled at aortic valve closure
var bp_diastolic: float           = 80.0    # mmHg — sampled at aortic valve opening
var pcwp: float                   = 8.0     # mmHg — mirrors la.pressure
var aorta_pressure: float         = 93.0    # mmHg — mirrors _aorta.pressure
var aorta_blood_flow: bool        = false   # true while aortic valve open
var aorta_blood_flow_end: bool    = false   # true the tick aortic valve closes
