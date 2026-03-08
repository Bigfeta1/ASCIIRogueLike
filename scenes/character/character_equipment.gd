extends Node

const EquipmentItemScene := preload("res://scenes/items/equipment_item.tscn")

const ARMOR_SLOTS: Array = ["head", "face", "neck", "chest", "shirt", "shoulder", "bracers", "gloves", "belt", "legs", "feet", "outerwear", "back"]

const SLOT_PANEL_PATHS: Dictionary = {
	"head":      "CanvasLayer/CharacterSheet/InventoryPanel/EquipmentSlots/VBoxContainer/HBoxContainer/HeadPanel",
	"face":      "CanvasLayer/CharacterSheet/InventoryPanel/EquipmentSlots/VBoxContainer/HBoxContainer/FacePanel",
	"neck":      "CanvasLayer/CharacterSheet/InventoryPanel/EquipmentSlots/VBoxContainer/NeckPanel",
	"chest":     "CanvasLayer/CharacterSheet/InventoryPanel/EquipmentSlots/VBoxContainer/Chest/ChestPanel",
	"shirt":     "CanvasLayer/CharacterSheet/InventoryPanel/EquipmentSlots/VBoxContainer/Chest/ShirtPanel",
	"shoulder":  "CanvasLayer/CharacterSheet/InventoryPanel/EquipmentSlots/ArmContainer/ShoulderPanel",
	"bracers":   "CanvasLayer/CharacterSheet/InventoryPanel/EquipmentSlots/ArmContainer/BracersPanel",
	"gloves":    "CanvasLayer/CharacterSheet/InventoryPanel/EquipmentSlots/ArmContainer/GlovesPanel",
	"belt":      "CanvasLayer/CharacterSheet/InventoryPanel/EquipmentSlots/VBoxContainer/BeltPanel",
	"legs":      "CanvasLayer/CharacterSheet/InventoryPanel/EquipmentSlots/VBoxContainer/LegsPanel",
	"feet":      "CanvasLayer/CharacterSheet/InventoryPanel/EquipmentSlots/VBoxContainer/Feet Panel",
	"outerwear": "CanvasLayer/CharacterSheet/InventoryPanel/EquipmentSlots/VBoxContainer2/OuterBack/Outerwear",
	"back":      "CanvasLayer/CharacterSheet/InventoryPanel/EquipmentSlots/VBoxContainer2/OuterBack/BackPanel",
	"ring_1":    "CanvasLayer/CharacterSheet/InventoryPanel/EquipmentSlots/VBoxContainer2/Rings/Outerwear",
	"ring_2":    "CanvasLayer/CharacterSheet/InventoryPanel/EquipmentSlots/VBoxContainer2/Rings/BackPanel",
	"trinket_1": "CanvasLayer/CharacterSheet/InventoryPanel/EquipmentSlots/VBoxContainer2/Trinkets/Outerwear",
	"trinket_2": "CanvasLayer/CharacterSheet/InventoryPanel/EquipmentSlots/VBoxContainer2/Trinkets/BackPanel",
	"r_hand":    "CanvasLayer/CharacterSheet/InventoryPanel/EquipmentSlots/Chest/ChestPanel",
	"l_hand":    "CanvasLayer/CharacterSheet/InventoryPanel/EquipmentSlots/Chest/ShirtPanel",
}

signal slot_clicked(slot: String)

var _character: Node


func _ready() -> void:
	_character = get_parent()
	if _character.character_role == _character.CharacterRole.PLAYER:
		_refresh_attack_weight_label()
		_refresh_armor_weight_label()
		for slot in SLOT_PANEL_PATHS:
			var panel := _get_slot_panel(slot)
			if panel == null:
				continue
			panel.mouse_filter = Control.MOUSE_FILTER_STOP
			panel.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
					if equipped.get(slot, "") != "":
						slot_clicked.emit(slot))


# slot_name -> item_id or ""
var equipped: Dictionary = {
	"head": "", "face": "", "neck": "",
	"chest": "", "shirt": "",
	"shoulder": "", "bracers": "", "gloves": "",
	"belt": "", "legs": "", "feet": "",
	"outerwear": "", "back": "",
	"r_hand": "", "l_hand": "",
	"ring_1": "", "ring_2": "",
	"trinket_1": "", "trinket_2": "",
}


func equip(item_id: String) -> bool:
	var data := ItemRegistry.get_item(item_id)
	var slot: String = data.get("slot", "") as String
	if slot == "" or not equipped.has(slot):
		return false
	var inventory := _character.get_node("CharacterInventory")
	if equipped[slot] != "":
		inventory.add_item(equipped[slot])
		_remove_visual(slot)
	equipped[slot] = item_id
	inventory.remove_item(item_id)
	_spawn_visual(slot, data.get("sprite", "") as String)
	_refresh_attack_weight_label()
	_refresh_armor_weight_label()
	return true


func unequip(slot: String) -> bool:
	if not equipped.has(slot) or equipped[slot] == "":
		return false
	var inventory := _character.get_node("CharacterInventory")
	inventory.add_item(equipped[slot])
	equipped[slot] = ""
	_remove_visual(slot)
	_refresh_attack_weight_label()
	_refresh_armor_weight_label()
	return true


func get_equipped(slot: String) -> String:
	return equipped.get(slot, "")


func equipped_in_slot(item_id: String) -> String:
	for slot in equipped:
		if equipped[slot] == item_id:
			return slot
	return ""


# Returns {damage_die, weight_class} — weight_class derived from combined hand weight
func weapon_info() -> Dictionary:
	var weapon_id: String = equipped.get("r_hand", "")
	var damage_die: int = 3
	var hit_bonus: int = 0
	if weapon_id != "":
		var data := ItemRegistry.get_item(weapon_id)
		damage_die = data.get("damage_die", 3) as int
		hit_bonus = data.get("hit_bonus", 0) as int
	var total_weight: float = 0.0
	for slot in ["r_hand", "l_hand"]:
		var item_id: String = equipped.get(slot, "")
		if item_id != "":
			total_weight += ItemRegistry.get_item(item_id).get("weight", 0.0) as float
	return {"damage_die": damage_die, "hit_bonus": hit_bonus, "weight_class": _attack_weight_class(total_weight)}


# Returns the defender's armor weight class derived from total armor weight
func armor_weight_class() -> String:
	var total_weight: float = 0.0
	for slot in ARMOR_SLOTS:
		var item_id: String = equipped.get(slot, "")
		if item_id != "":
			total_weight += ItemRegistry.get_item(item_id).get("weight", 0.0) as float
	return _armor_weight_class(total_weight)


func _attack_weight_class(total_weight: float) -> String:
	if total_weight < 5.0:
		return "light"
	elif total_weight <= 15.0:
		return "medium"
	return "heavy"


func _armor_weight_class(total_weight: float) -> String:
	if total_weight < 25.0:
		return "light"
	elif total_weight <= 60.0:
		return "medium"
	return "heavy"


func _get_slot_panel(slot: String) -> Control:
	var scene_root := _character.get_parent()
	var path: String = SLOT_PANEL_PATHS.get(slot, "")
	if path == "":
		return null
	return scene_root.get_node_or_null(path)


func _spawn_visual(slot: String, sprite_path: String) -> void:
	if sprite_path == "":
		return
	var panel := _get_slot_panel(slot)
	if panel == null:
		return
	var item := EquipmentItemScene.instantiate()
	panel.add_child(item)
	item.setup(sprite_path)


func _remove_visual(slot: String) -> void:
	var panel := _get_slot_panel(slot)
	if panel == null:
		return
	for child in panel.get_children():
		if child is TextureRect:
			child.queue_free()


func _refresh_armor_weight_label() -> void:
	var label := _character.get_parent().get_node_or_null("CanvasLayer/CharacterSheet/InventoryPanel/Labels/ArmorWeightLabel")
	if label == null:
		return
	var total_weight: float = 0.0
	for slot in ARMOR_SLOTS:
		var item_id: String = equipped.get(slot, "")
		if item_id != "":
			total_weight += ItemRegistry.get_item(item_id).get("weight", 0.0) as float
	var wc: String = _armor_weight_class(total_weight)
	label.text = "Armor Weight: %.1f lbs (%s)" % [total_weight, wc.capitalize()]
	label.add_theme_color_override("font_color", _weight_color(wc))


func _refresh_attack_weight_label() -> void:
	var label := _character.get_parent().get_node_or_null("CanvasLayer/CharacterSheet/InventoryPanel/Labels/AttackWeightLabel")
	if label == null:
		return
	var total_weight: float = 0.0
	for slot in ["r_hand", "l_hand"]:
		var item_id: String = equipped.get(slot, "")
		if item_id != "":
			total_weight += ItemRegistry.get_item(item_id).get("weight", 0.0) as float
	var wc: String = _attack_weight_class(total_weight)
	label.text = "Attack Weight: %.1f lbs (%s)" % [total_weight, wc.capitalize()]
	label.add_theme_color_override("font_color", _weight_color(wc))


func _weight_color(weight_class: String) -> Color:
	match weight_class:
		"medium": return Color.YELLOW
		"heavy":  return Color.RED
	return Color.GREEN
