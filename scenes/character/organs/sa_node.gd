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

# Modulated by cardiovascular sympathetic tone.
# Baseline = 21.86/s (60 bpm). Max = 80.6/s (180 bpm).
var na_slope: float = 22.222  # 20.0/(45*0.02) — 60 bpm at SIM_STEP=0.02

var fired_count: int   = 0
var beat_period: float = 1.0   # seconds between last two beats; updated each firing
var _time_since_last_beat: float = 0.0

func _ready():
	membrane_potential = -130.0 + ic_na + ic_ca + ic_k

func tick(delta: float) -> void:
	
	_time_since_last_beat += delta

	if cardioplegia:
		ic_k = 500.0
		return

	match state:
		Phase.PHASE_4:
			if membrane_potential < -40.0 and ic_na < 20.0:
				ic_na += na_slope * delta

			elif membrane_potential >= -40.0 and membrane_potential < 10.0 and ic_ca < 50.0:
				ic_ca += (50.0 / 0.05) * delta

			membrane_potential = -130.0 + ic_na + ic_ca + ic_k

			if membrane_potential >= 10.0:
				state = Phase.PHASE_0

		Phase.PHASE_0:
			fired.emit()
			fired_count       += 1
			beat_period        = _time_since_last_beat
			_time_since_last_beat = 0.0
			state              = Phase.PHASE_3

		Phase.PHASE_3:
			if ic_k > 0.0:
				ic_k -= (80.0 / 0.04) * delta
			if ic_k <= 0.0:
				ic_na             = 0.0
				ic_ca             = 0.0
				ic_k              = 70.0
				membrane_potential = -60.0
				state             = Phase.PHASE_4

