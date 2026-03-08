extends Node

const DamageLabelScript := preload("res://scenes/character/damage_label.gd")

var _turns_since_regen: int = 0

var hp: int = 10
var hp_max: int = 10
var bp_systolic: int = 120
var bp_diastolic: int = 80
var hr: int = 75
var rr: int = 12
var temperature: float = 37.0

# Accumulated stat debt — consequences to be wired later
# Keys match stat names: "adrenal", "cardio", "muscle", etc.
var stat_debt: Dictionary = {}

var _label_hp: Label
var _label_bp: Label
var _label_hr: Label
var _label_rr: Label
var _label_temp: Label

func _ready() -> void:
	var character := get_parent()
	if character.character_role != character.CharacterRole.PLAYER:
		return
	var hbox := character.get_parent().get_node("CanvasLayer/TopBar/HBoxContainer")
	_label_hp = hbox.get_node("HPLabel")
	_label_bp = hbox.get_node("BPLabel")
	_label_hr = hbox.get_node("HRLabel")
	_label_rr = hbox.get_node("RRLabel")
	_label_temp = hbox.get_node("TemperatureLabel")
	_refresh_ui()

func heal(amount: int) -> void:
	hp = mini(hp + amount, hp_max)
	_refresh_ui()
	var character := get_parent()
	if character.character_role == character.CharacterRole.PLAYER:
		var label: Label = DamageLabelScript.new()
		character.get_parent().get_node("CanvasLayer").add_child(label)
		label.setup("+%dHP" % amount, Color.GREEN, character.position, character.get_parent().get_node("Camera3D"))

func tick_regen() -> void:
	if hp >= hp_max:
		_turns_since_regen = 0
		return
	var character := get_parent()
	var mod: int = character.get_node("CharacterLevels").regen_mod()
	var turns_needed: int = 7 - mod
	_turns_since_regen += 1
	if _turns_since_regen < turns_needed:
		return
	_turns_since_regen = 0
	var heal: int = randi_range(1, 3) + mod
	hp = mini(hp + heal, hp_max)
	_refresh_ui()
	if character.character_role == character.CharacterRole.PLAYER:
		var label: Label = DamageLabelScript.new()
		character.get_parent().get_node("CanvasLayer").add_child(label)
		label.setup("+%dHP" % heal, Color.GREEN, character.position, character.get_parent().get_node("Camera3D"))

func _refresh_ui() -> void:
	if _label_hp == null:
		return
	_label_hp.text = "HP: %d/%d" % [hp, hp_max]
	var ratio := float(hp) / float(hp_max)
	if ratio > 0.6:
		_label_hp.modulate = Color.WHITE
	elif ratio > 0.3:
		_label_hp.modulate = Color.YELLOW
	else:
		_label_hp.modulate = Color.RED
	_label_bp.text = "BP: %d/%d" % [bp_systolic, bp_diastolic]
	_label_hr.text = "HR: %d bpm" % hr
	_label_rr.text = "RR: %d bpm" % rr
	_label_temp.text = "Temp: %.1f°C" % temperature
