class_name SANode
extends Node

# Sinoatrial node — pacemaker automaticity.
# Drives membrane potential through Phase 4 → 0 → 3, then emits fired.
# The electrical pathway listens to fired to start conduction.

signal fired

enum Phase {
	PHASE_4,  # slow diastolic depolarization — Na/Ca influx drives membrane to threshold
	PHASE_0,  # rapid depolarization — threshold reached, signal fires
	PHASE_3   # repolarization — K efflux restores resting potential
}

@export var debug_name: String = "SA Node"

var membrane_potential: float = -60.0
var ic_na: float              = 0.0
var ic_ca: float              = 0.0
var ic_k: float               = 70.0

var state: Phase = Phase.PHASE_4
var cardioplegia: bool = false

func _ready():
	membrane_potential = -130.0 + ic_na + ic_ca + ic_k

func tick(delta: float) -> void:
	
	if cardioplegia:
		ic_k = 500.0
		return

	match state:
		Phase.PHASE_4:
			if membrane_potential < -40.0 and ic_na < 20.0:
				ic_na += (20.0 / 0.49) * delta
			
			elif membrane_potential >= -40.0 and membrane_potential < 10.0 and ic_ca < 50.0:
				ic_ca += (50.0 / 0.05) * delta
			if membrane_potential >= 10.0:
				state = Phase.PHASE_0

		Phase.PHASE_0:
			fired.emit()
			state = Phase.PHASE_3

		Phase.PHASE_3:
			if ic_k > 0.0:
				ic_k -= (80.0 / 0.04) * delta
			if ic_k <= 0.0:
				ic_na             = 0.0
				ic_ca             = 0.0
				ic_k              = 70.0
				membrane_potential = -60.0
				state             = Phase.PHASE_4


func force_fire() -> void:
	membrane_potential = 10.0
	state              = Phase.PHASE_0
