extends Node

signal item_clicked(label: Label)

const CATEGORY_ORDER: Array = ["melee", "ranged", "armor", "clothes", "medicine", "misc"]
const CATEGORY_LABELS: Dictionary = {
	"melee": "Melee Weapons",
	"ranged": "Ranged Weapons",
	"armor": "Armor",
	"clothes": "Clothes",
	"medicine": "Medicine",
	"misc": "Misc",
}

var items: Array[String] = []
var collapsed: Dictionary = {}

# Each entry: { "type": "header"/"item", "category": String, "node": Label }
var selectable_entries: Array = []

var _label_current_weight: Label
var _label_max_weight: Label
var item_list: VBoxContainer

func _ready() -> void:
	var character := get_parent()
	if character.character_role != character.CharacterRole.PLAYER:
		return
	var sheet := character.get_parent().get_node("CanvasLayer/CharacterSheet")
	var weight_labels := sheet.get_node("InventoryPanel/WeightLabels")
	_label_current_weight = weight_labels.get_node("CurrentWeightLabel")
	_label_max_weight = weight_labels.get_node("CurrentWeightLabel2")
	item_list = sheet.get_node("InventoryPanel/InventoryList/ScrollContainer/ItemList")
	_refresh_ui()

func carry_capacity() -> float:
	var levels := get_parent().get_node("CharacterLevels")
	return 100.0 + levels.stat_mod(levels.muscle) * 5.0

func current_weight() -> float:
	var total := 0.0
	for id in items:
		total += ItemRegistry.get_item(id).get("weight", 0.0) as float
	return total

func can_add(id: String) -> bool:
	var weight: float = ItemRegistry.get_item(id).get("weight", 0.0)
	return current_weight() + weight <= carry_capacity()

func add_item(id: String) -> bool:
	if not can_add(id):
		return false
	items.append(id)
	_refresh_ui()
	return true

func remove_item(id: String) -> bool:
	var idx := items.find(id)
	if idx == -1:
		return false
	items.remove_at(idx)
	_refresh_ui()
	return true

func toggle_category(category: String) -> void:
	collapsed[category] = not collapsed.get(category, false)
	_refresh_ui()

func _refresh_ui() -> void:
	if _label_current_weight == null:
		return
	_label_current_weight.text = "%.1f" % current_weight()
	_label_max_weight.text = "%.1f" % carry_capacity()

	for child in item_list.get_children():
		child.queue_free()
	selectable_entries.clear()

	# Group counts by category
	var by_category: Dictionary = {}
	var counts: Dictionary = {}
	for id in items:
		counts[id] = counts.get(id, 0) + 1
	for id in counts:
		var cat: String = ItemRegistry.get_item(id).get("category", "misc") as String
		if not CATEGORY_ORDER.has(cat):
			cat = "misc"
		if not by_category.has(cat):
			by_category[cat] = []
		by_category[cat].append(id)

	for cat in CATEGORY_ORDER:
		if not by_category.has(cat):
			continue
		var is_collapsed: bool = collapsed.get(cat, false)
		var arrow := "v " if not is_collapsed else "> "
		var header := Label.new()
		header.text = arrow + CATEGORY_LABELS[cat]
		header.add_theme_color_override("font_color", Color.YELLOW)
		header.mouse_filter = Control.MOUSE_FILTER_STOP
		header.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				toggle_category(cat))
		item_list.add_child(header)
		selectable_entries.append({"type": "header", "category": cat, "node": header})

		if is_collapsed:
			continue
		for id in by_category[cat]:
			var data := ItemRegistry.get_item(id)
			var qty: int = counts[id]
			var unit_weight: float = data.get("weight", 0.0) as float
			var prefix := "%dx  " % qty if qty > 1 else ""
			var label := Label.new()
			label.text = "  %s%s  %.1fkg" % [prefix, data.get("name", id), unit_weight * qty]
			label.mouse_filter = Control.MOUSE_FILTER_STOP
			label.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
					item_clicked.emit(label))
			item_list.add_child(label)
			selectable_entries.append({"type": "item", "category": cat, "node": label, "id": id})
