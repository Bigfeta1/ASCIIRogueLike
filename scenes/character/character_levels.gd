extends Node

const XP_BASE := 25

var muscle: int = 10
var cardio: int = 10
var adrenal: int = 10
var sympathetic: int = 10
var parasympathetic: int = 10
var affect: int = 10

var level: int = 1
var xp: int = 0

var _label_muscle: Label
var _label_cardio: Label
var _label_adrenal: Label
var _label_sympathetic: Label
var _label_parasympathetic: Label
var _label_affect: Label
var _label_level_amount: Label
var _label_current_xp: Label
var _label_max_xp: Label
var _xp_fill: ColorRect

func stat_mod(stat: int) -> int:
	return floori((stat - 10) / 2.0)

func hit_mod() -> int:
	return floori((stat_mod(cardio) + stat_mod(adrenal) + stat_mod(sympathetic) + stat_mod(parasympathetic)) / 4.0)

func dodge_mod() -> int:
	return floori((stat_mod(cardio) + stat_mod(adrenal) + stat_mod(affect)) / 3.0)

func block_mod() -> int:
	return floori((stat_mod(muscle) + stat_mod(sympathetic)) / 2.0)

func parry_mod() -> int:
	return floori((stat_mod(muscle) + stat_mod(parasympathetic)) / 2.0)

func regen_mod() -> int:
	return floori((stat_mod(adrenal) + stat_mod(cardio) + stat_mod(parasympathetic)) / 3.0)

func xp_to_next() -> int:
	return XP_BASE * level * level


func add_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
	_refresh_ui()


func _ready() -> void:
	pass

func setup(character_sheet: Control, top_bar: Control) -> void:
	var stats_hbox := character_sheet.get_node("StatsPanel/StatsHBox")
	_label_muscle = stats_hbox.get_node("MusclePanel/MuscleStat")
	_label_cardio = stats_hbox.get_node("CardioPanel/CardioStat")
	_label_adrenal = stats_hbox.get_node("AdrenalPanel/AdrenalStat")
	_label_sympathetic = stats_hbox.get_node("SympatheticPanel/SympatheticStat")
	_label_parasympathetic = stats_hbox.get_node("ParasympatheticPanel/ParasympatheticStat")
	_label_affect = stats_hbox.get_node("AffectPanel/AffectStat")
	var xp_bar := top_bar.get_node("XPBar")
	_label_level_amount = xp_bar.get_node("LevelLabel/LevelAmount")
	_label_current_xp = xp_bar.get_node("CurrentXPLabel")
	_label_max_xp = xp_bar.get_node("CurrentXPLabel/MaxXPLabel")
	_xp_fill = xp_bar.get_node("XPFill")
	_refresh_ui()


func _refresh_ui() -> void:
	_label_muscle.text = str(muscle)
	_label_cardio.text = str(cardio)
	_label_adrenal.text = str(adrenal)
	_label_sympathetic.text = str(sympathetic)
	_label_parasympathetic.text = str(parasympathetic)
	_label_affect.text = str(affect)
	_label_level_amount.text = str(level)
	_label_current_xp.text = str(xp)
	_label_max_xp.text = str(xp_to_next())
	_xp_fill.size.x = _xp_fill.get_parent().size.x * (float(xp) / float(xp_to_next()))
