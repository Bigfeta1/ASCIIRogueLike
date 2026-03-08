extends Node

var ambient_temp: float = 29.44  # 85°F in Celsius
var time_hour: int = 14
var time_minute: int = 0
var time_second: int = 0

var _label_ambient_temp: Label
var _label_time: Label

func _ready() -> void:
	var main := get_parent().get_parent()
	var hbox2 := main.get_node("CanvasLayer/TopBar/HBoxContainer2")
	_label_ambient_temp = hbox2.get_node("AmbientTempLabel")
	_label_time = hbox2.get_node("TimeLabel")
	_refresh_ui()

func advance_time(seconds: int) -> void:
	time_second += seconds
	time_minute += time_second / 60
	time_second = time_second % 60
	time_hour = (time_hour + time_minute / 60) % 24
	time_minute = time_minute % 60
	_refresh_ui()

func _refresh_ui() -> void:
	_label_ambient_temp.text = "Ambient: %.1f°C" % ambient_temp
	_label_time.text = "Time: %02d:%02d:%02d" % [time_hour, time_minute, time_second]
