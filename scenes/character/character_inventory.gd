extends Node

signal item_clicked(row: Control)

const CATEGORY_ORDER: Array = ["melee", "ranged", "armor", "clothes", "medicine", "container", "camping", "misc"]
const CATEGORY_LABELS: Dictionary = {
	"melee": "Melee Weapons",
	"ranged": "Ranged Weapons",
	"armor": "Armor",
	"clothes": "Clothes",
	"medicine": "Medicine",
	"container": "Containers",
	"camping": "Camping",
	"misc": "Misc",
}

var items: Array[String] = []
var item_uids: Array[int] = []
# Maps uid -> { "liquid": String, "amount_liters": float } for container items
var container_contents: Dictionary = {}
# Maps uid -> current durability for items with durability_max
var item_durability: Dictionary = {}
var _next_uid: int = 0
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
	var uid: int = _next_uid
	items.append(id)
	item_uids.append(uid)
	_next_uid += 1
	var data := ItemRegistry.get_item(id)
	if data.has("durability_max"):
		item_durability[uid] = data["durability_max"] as int
	_refresh_ui()
	return true

func remove_item(id: String) -> bool:
	var idx := items.find(id)
	if idx == -1:
		return false
	var uid: int = item_uids[idx]
	items.remove_at(idx)
	item_uids.remove_at(idx)
	container_contents.erase(uid)
	item_durability.erase(uid)
	_refresh_ui()
	return true

func get_durability(item_index: int) -> int:
	var uid: int = item_uids[item_index]
	return item_durability.get(uid, -1)

func set_durability(item_index: int, value: int) -> void:
	var uid: int = item_uids[item_index]
	var data := ItemRegistry.get_item(items[item_index])
	var max_dur: int = data.get("durability_max", 0) as int
	item_durability[uid] = clampi(value, 0, max_dur)
	_refresh_ui()

func get_liquid(item_index: int) -> Dictionary:
	var uid: int = item_uids[item_index]
	return container_contents.get(uid, {})

func set_liquid(item_index: int, liquid: String, amount_liters: float) -> void:
	var uid: int = item_uids[item_index]
	var data := ItemRegistry.get_item(items[item_index])
	var capacity: float = data.get("capacity_liters", 0.0)
	var allowed: Array = data.get("allowed_liquids", [])
	if amount_liters <= 0.0:
		container_contents.erase(uid)
	elif allowed.has(liquid) and amount_liters <= capacity:
		container_contents[uid] = {"liquid": liquid, "amount_liters": amount_liters}
	_refresh_ui()

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
			var fill_suffix := ""
			if data.get("category", "") == "container":
				var capacity: float = data.get("capacity_liters", 0.0)
				var idx := items.find(id)
				if idx != -1:
					var contents := get_liquid(idx)
					if contents.is_empty():
						fill_suffix = "  (%.2fL empty)" % capacity
					else:
						fill_suffix = "  (%.2f/%.2fL %s)" % [contents["amount_liters"], capacity, contents["liquid"]]
			if data.has("durability_max"):
				var idx := items.find(id)
				if idx != -1:
					var dur: int = get_durability(idx)
					var dur_max: int = data["durability_max"] as int
					fill_suffix = "  (%d/%d)" % [dur, dur_max]

			var row := PanelContainer.new()
			row.mouse_filter = Control.MOUSE_FILTER_STOP
			var hbox := HBoxContainer.new()
			hbox.mouse_filter = Control.MOUSE_FILTER_PASS
			row.add_child(hbox)

			var sprite_path: String = data.get("sprite", "") as String
			if sprite_path != "":
				var icon := TextureRect.new()
				icon.texture = load(sprite_path)
				icon.custom_minimum_size = Vector2(28, 28)
				icon.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon.mouse_filter = Control.MOUSE_FILTER_PASS
				hbox.add_child(icon)

			var label := Label.new()
			label.text = "  %s%s  %.1fkg%s" % [prefix, data.get("name", id), unit_weight * qty, fill_suffix]
			label.mouse_filter = Control.MOUSE_FILTER_PASS
			hbox.add_child(label)

			row.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
					item_clicked.emit(row))
			item_list.add_child(row)
			selectable_entries.append({"type": "item", "category": cat, "node": row, "id": id})
