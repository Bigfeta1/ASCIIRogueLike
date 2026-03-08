extends Node

const _PATH := "res://data/items.json"

var _items: Dictionary = {}

func _ready() -> void:
	var file := FileAccess.open(_PATH, FileAccess.READ)
	var records: Array = JSON.parse_string(file.get_as_text())
	file.close()
	for record in records:
		_items[record["id"]] = record

func get_item(id: String) -> Dictionary:
	return _items.get(id, {})

func has_item(id: String) -> bool:
	return _items.has(id)
