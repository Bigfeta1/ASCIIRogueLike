extends Control

signal close_requested

enum Tab { STATS, SKILLS, INVENTORY }
enum InventoryState { BROWSING, ITEM_ACTION }

const _HIGHLIGHT_COLOR := Color(0.2, 0.5, 0.8, 0.4)

var _tab: Tab = Tab.STATS
var _inventory_state: InventoryState = InventoryState.BROWSING
var _selected_index: int = 0
var _action_index: int = 0
var _current_actions: Array[String] = []
var _active_item_id: String = ""
var _active_slot: String = ""
var _inventory: Node
var _action_panel: PanelContainer
var _action_list: VBoxContainer
var _info_row: String = ""

func _ready() -> void:
	$TabBar/StatsButton.pressed.connect(_set_tab.bind(Tab.STATS))
	$TabBar/SkillsButton.pressed.connect(_set_tab.bind(Tab.SKILLS))
	$TabBar/InventoryButton.pressed.connect(_set_tab.bind(Tab.INVENTORY))
	_action_panel = $InventoryPanel/ItemActionPanel
	_action_list = $InventoryPanel/ItemActionPanel/ActionList
	_set_tab(Tab.STATS)

func init(inventory: Node) -> void:
	_inventory = inventory
	_inventory.item_clicked.connect(_open_item_action)
	var equipment := inventory.get_parent().get_node("CharacterEquipment")
	equipment.slot_clicked.connect(_open_slot_action)

func select_item(item_id: String) -> void:
	for i in _inventory.selectable_entries.size():
		var entry: Dictionary = _inventory.selectable_entries[i]
		if entry.get("type") == "item" and entry.get("id") == item_id:
			_selected_index = i
			_refresh_selection()
			return

func _set_tab(tab: Tab) -> void:
	_tab = tab
	$StatsPanel.visible = _tab == Tab.STATS
	$SkillsPanel.visible = _tab == Tab.SKILLS
	$InventoryPanel.visible = _tab == Tab.INVENTORY
	if _tab == Tab.INVENTORY:
		_inventory._refresh_ui()
	_selected_index = 0
	_set_inventory_state(InventoryState.BROWSING)
	_refresh_selection()
	get_viewport().gui_release_focus()

func _set_inventory_state(state: InventoryState) -> void:
	_inventory_state = state
	_action_panel.visible = _inventory_state == InventoryState.ITEM_ACTION
	if _inventory_state != InventoryState.ITEM_ACTION:
		_info_row = ""
	if _inventory_state == InventoryState.ITEM_ACTION:
		_action_index = 0
		_rebuild_action_list()
		_refresh_action_selection()

func _open_item_action(row: Control) -> void:
	var entry := _entry_for_node(row)
	if entry.is_empty():
		return
	_active_item_id = entry["id"]
	var row_global := row.get_global_rect()
	_action_panel.position = row_global.position - _action_panel.get_parent().get_global_position() + Vector2(320.0, 0.0)
	_set_inventory_state(InventoryState.ITEM_ACTION)

func _open_slot_action(slot: String) -> void:
	var equipment := _get_equipment()
	var item_id: String = equipment.get_equipped(slot)
	if item_id == "":
		return
	_active_slot = slot
	_active_item_id = item_id
	var panel: Control = equipment._get_slot_panel(slot)
	var panel_global: Rect2 = panel.get_global_rect()
	_action_panel.position = panel_global.position - _action_panel.get_parent().get_global_position() + Vector2(panel_global.size.x + 4.0, 0.0)
	_current_actions = ["Unequip", "Inspect"]
	_action_index = 0
	_info_row = ""
	var dur: int = equipment.get_equipped_durability(slot)
	if dur != -1:
		var dur_max: int = ItemRegistry.get_item(item_id).get("durability_max", 0) as int
		_info_row = "%d/%d dur" % [dur, dur_max]
	_rebuild_action_list_from(_current_actions)
	_action_panel.visible = true
	_inventory_state = InventoryState.ITEM_ACTION

func _entry_for_node(node: Control) -> Dictionary:
	for entry in _inventory.selectable_entries:
		if entry["node"] == node:
			return entry
	return {}

func _build_actions_for(item_id: String) -> Array[String]:
	var data := ItemRegistry.get_item(item_id)
	var actions: Array[String] = []
	var interaction: String = str(data.get("interaction", "") if data.get("interaction", null) != null else "")
	if interaction == "equip":
		actions.append("Equip")
	elif interaction == "use":
		actions.append("Use")
		if data.get("category", "") == "container":
			var idx: int = _inventory.items.find(item_id)
			if idx != -1 and not _inventory.get_liquid(idx).is_empty():
				actions.append("Drink")
	var idx: int = _inventory.items.find(item_id)
	if idx != -1:
		var uid: int = _inventory.item_uids[idx]
		if _inventory.chest_contents.has(uid):
			actions.append("View Contents")
	actions.append("Inspect")
	actions.append("Drop")
	return actions


func _get_equipment() -> Node:
	return _inventory.get_parent().get_node("CharacterEquipment")

func _rebuild_action_list() -> void:
	_current_actions = _build_actions_for(_active_item_id)
	_rebuild_action_list_from(_current_actions)

func _rebuild_action_list_from(actions: Array[String]) -> void:
	for child in _action_list.get_children():
		child.queue_free()
	if _info_row != "":
		var info_label := Label.new()
		info_label.text = _info_row
		info_label.add_theme_color_override("font_color", Color.GRAY)
		info_label.add_theme_font_size_override("font_size", 10)
		_action_list.add_child(info_label)
	for action in actions:
		var label := Label.new()
		label.text = action
		_action_list.add_child(label)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not event is InputEventKey:
		return
	if not event.pressed:
		return
	if event.keycode == KEY_ESCAPE and _inventory_state == InventoryState.BROWSING:
		close()
		accept_event()
		return
	if _tab != Tab.INVENTORY:
		return
	match _inventory_state:
		InventoryState.BROWSING:
			_handle_browsing_input(event)
		InventoryState.ITEM_ACTION:
			_handle_action_input(event)

func close() -> void:
	_set_tab(Tab.STATS)
	close_requested.emit()

func _handle_browsing_input(event: InputEvent) -> void:
	var entries: Array = _inventory.selectable_entries
	var count: int = entries.size()
	if count == 0:
		return
	match event.keycode:
		KEY_W, KEY_UP:
			_selected_index = posmod(_selected_index - 1, count)
			_refresh_selection()
			accept_event()
		KEY_S, KEY_DOWN:
			_selected_index = posmod(_selected_index + 1, count)
			_refresh_selection()
			accept_event()
		KEY_E, KEY_ENTER, KEY_KP_ENTER:
			var entry: Dictionary = entries[_selected_index]
			if entry["type"] == "header":
				_inventory.toggle_category(entry["category"])
				_selected_index = mini(_selected_index, _inventory.selectable_entries.size() - 1)
				_refresh_selection()
			elif entry["type"] == "item":
				_open_item_action(entry["node"])
			accept_event()

func _handle_action_input(event: InputEvent) -> void:
	match event.keycode:
		KEY_W, KEY_UP:
			_action_index = posmod(_action_index - 1, _current_actions.size())
			_refresh_action_selection()
			accept_event()
		KEY_S, KEY_DOWN:
			_action_index = posmod(_action_index + 1, _current_actions.size())
			_refresh_action_selection()
			accept_event()
		KEY_E, KEY_ENTER, KEY_KP_ENTER:
			_confirm_action()
			accept_event()
		KEY_ESCAPE, KEY_Q:
			_active_slot = ""
			_set_inventory_state(InventoryState.BROWSING)
			accept_event()

func _confirm_action() -> void:
	var action := _current_actions[_action_index]
	match action:
		"Use":
			var data := ItemRegistry.get_item(_active_item_id)
			if data.get("category", "") == "container":
				_inventory.get_parent().interaction.activate_map_interaction(_active_item_id)
				return
			if _active_item_id == "tinder_box":
				_inventory.get_parent().interaction.activate_place_campfire(_active_item_id)
				return
			if _active_item_id == "aspiration_needle":
				var character := _inventory.get_parent()
				if character.pulmonary != null and character.pulmonary.pneumothorax:
					character.pulmonary.resolve_pneumothorax()
					_inventory.remove_item(_active_item_id)
				return
			var vitals := _inventory.get_parent().get_node("CharacterVitals")
			if vitals.hp < vitals.hp_max:
				vitals.heal(5)
				_inventory.remove_item(_active_item_id)
		"Drink":
			var idx: int = _inventory.items.find(_active_item_id)
			var contents: Dictionary = _inventory.get_liquid(idx)
			var current: float = contents.get("amount_liters", 0.0)
			var liquid: String = contents.get("liquid", "")
			_inventory.get_parent().interaction.open_drink_modal(_active_item_id, liquid, current)
			return
		"Inspect":
			var data := ItemRegistry.get_item(_active_item_id)
			var dur_current: int = -1
			var dur_max: int = -1
			if data.has("durability_max"):
				dur_max = data["durability_max"] as int
				var idx: int = _inventory.items.find(_active_item_id)
				if idx != -1:
					dur_current = _inventory.get_durability(idx)
				elif _active_slot != "":
					dur_current = _get_equipment().get_equipped_durability(_active_slot)
			var hit_bonus: int = data.get("hit_bonus", -1) as int
			var damage_die: int = data.get("damage_die", -1) as int
			_inventory.get_parent().interaction.open_inspect_modal(
				data.get("name", _active_item_id),
				data.get("description", ""),
				data.get("sprite", ""),
				dur_current,
				dur_max,
				hit_bonus,
				damage_die
			)
			return
		"View Contents":
			var idx: int = _inventory.items.find(_active_item_id)
			var uid: int = _inventory.item_uids[idx]
			_inventory.get_parent().interaction.open_chest_contents(_active_item_id, uid)
			return
		"Drop":
			_inventory.get_parent().interaction.activate_drop_item(_active_item_id)
			return
		"Equip":
			_get_equipment().equip(_active_item_id)
		"Unequip":
			_get_equipment().unequip(_active_slot)
	_active_slot = ""
	_set_inventory_state(InventoryState.BROWSING)

func _refresh_selection() -> void:
	if _inventory == null:
		return
	var entries: Array = _inventory.selectable_entries
	for i in entries.size():
		var node: Control = entries[i]["node"]
		var stylebox_slot := "panel" if entries[i]["type"] == "item" else "normal"
		if i == _selected_index:
			node.add_theme_stylebox_override(stylebox_slot, _make_highlight_box())
		else:
			node.remove_theme_stylebox_override(stylebox_slot)

func _refresh_action_selection() -> void:
	var offset: int = 1 if _info_row != "" else 0
	for i in _action_list.get_child_count():
		var label := _action_list.get_child(i) as Label
		if label == null:
			continue
		if i == _action_index + offset:
			label.add_theme_stylebox_override("normal", _make_highlight_box())
		else:
			label.remove_theme_stylebox_override("normal")

func _make_highlight_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = _HIGHLIGHT_COLOR
	return box
