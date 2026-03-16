class_name PulmonaryArtery
extends Node

@export var debug_name: String = ""

var pressure: float = 15.0

const DECAY_RATE: float  = 4.0
const PRESSURE_MIN: float = 8.0
const PRESSURE_MAX: float = 30.0

func tick(delta: float, valve_open: bool) -> void:
	if not valve_open:
		pressure -= DECAY_RATE * delta
	pressure = clampf(pressure, PRESSURE_MIN, PRESSURE_MAX)
