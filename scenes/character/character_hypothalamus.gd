extends Node

# Hypothalamus — senses plasma osmolality and substrate levels.
# Emits signals that downstream systems (UI, behavior, vitals) connect to.

signal thirst_triggered
signal thirst_resolved
signal dehydrated_triggered
signal dehydrated_resolved
signal severely_dehydrated_triggered
signal severely_dehydrated_resolved
signal hunger_triggered
signal hunger_resolved

# Osmolality thresholds (mOsm/kg)
const THIRST_THRESHOLD: float = 290.0
const THIRST_RESOLVE: float = 287.0
const DEHYDRATED_THRESHOLD: float = 295.0
const DEHYDRATED_RESOLVE: float = 292.0
const SEVERELY_DEHYDRATED_THRESHOLD: float = 310.0
const SEVERELY_DEHYDRATED_RESOLVE: float = 306.0

# Glucose thresholds (mg/dL) — hunger
const HUNGER_THRESHOLD: float = 70.0
const HUNGER_RESOLVE: float = 90.0

var plasma_osmolality: float = 285.0
var is_thirsty: bool = false
var is_dehydrated: bool = false
var is_severely_dehydrated: bool = false
var is_hungry: bool = false

var _organs: Node = null


func setup(organ_registry: Node) -> void:
	_organs = organ_registry


func tick() -> void:
	_sense_osmolality()
	_sense_glucose()


func _sense_osmolality() -> void:
	if _organs == null or _organs.renal == null:
		return
	var renal: Node = _organs.renal
	plasma_osmolality = renal.plasma_osmolality

	if not is_thirsty and plasma_osmolality > THIRST_THRESHOLD:
		is_thirsty = true
		thirst_triggered.emit()
	elif is_thirsty and plasma_osmolality < THIRST_RESOLVE:
		is_thirsty = false
		thirst_resolved.emit()

	if not is_dehydrated and plasma_osmolality > DEHYDRATED_THRESHOLD:
		is_dehydrated = true
		dehydrated_triggered.emit()
	elif is_dehydrated and plasma_osmolality < DEHYDRATED_RESOLVE:
		is_dehydrated = false
		dehydrated_resolved.emit()

	if not is_severely_dehydrated and plasma_osmolality > SEVERELY_DEHYDRATED_THRESHOLD:
		is_severely_dehydrated = true
		severely_dehydrated_triggered.emit()
	elif is_severely_dehydrated and plasma_osmolality < SEVERELY_DEHYDRATED_RESOLVE:
		is_severely_dehydrated = false
		severely_dehydrated_resolved.emit()


func _sense_glucose() -> void:
	# Placeholder — will wire to metabolic organ when implemented.
	pass
