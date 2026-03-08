extends Control

signal closed

enum ModalState { BROWSING, ITEM_ACTION }

const _HIGHLIGHT_COLOR := Color(0.2, 0.5, 0.8, 0.4)
const _MODAL_WIDTH := 220.0
const _ITEM_HEIGHT := 24.0
const _TITLE_HEIGHT := 32.0
const _PADDING := 16.0
const _MAX_VISIBLE_ITEMS := 10
const _ACTION_WIDTH := 120.0

var _target_inventories: Array[Node] = []
var _player_inventory: Node
var _scroll: ScrollContainer
var _item_list: VBoxContainer
var _action_panel: PanelContainer
var _action_list: VBoxContainer

var _state: ModalState = ModalState.BROWSING
var _selected_index: int = 0
var _action_index: int = 0
# Each entry: { "id": String, "inventory": Node }
var _entries: Array = []
var _current_actions: Array[String] = []


func _ready() -> void:
	_scroll = $Panel/VBox/ScrollContainer
	_item_list = $Panel/VBox/ScrollContainer/ItemList
	_action_panel = $ActionPanel
	_action_list = $ActionPanel/ActionList
	_action_panel.visible = false
	visible = false


func open(target_inventories: Array[Node], player_inventory: Node) -> void:
	_target_inventories = target_inventories
	_player_inventory = player_inventory
	_selected_index = 0
	_state = ModalState.BROWSING
	_action_panel.visible = false
	_rebuild()


func _rebuild() -> void:
	for child in _item_list.get_children():
		child.queue_free()
	_entries.clear()

	# Collect counts per (id, inventory) pair, preserving order
	for inv in _target_inventories:
		var counts: Dictionary = {}
		for id in inv.items:
			counts[id] = counts.get(id, 0) + 1
		var seen: Array[String] = []
		for id in inv.items:
			if id in seen:
				continue
			seen.append(id)
			_entries.append({"id": id, "inventory": inv})
			var data := ItemRegistry.get_item(id)
			var qty: int = counts[id]
			var label := Label.new()
			label.text = "%s x%d" % [data.get("name", id), qty]
			label.custom_minimum_size.y = _ITEM_HEIGHT
			_item_list.add_child(label)

	if _entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(empty)"
		empty_label.custom_minimum_size.y = _ITEM_HEIGHT
		_item_list.add_child(empty_label)

	_selected_index = mini(_selected_index, maxi(_entries.size() - 1, 0))
	_resize()
	_refresh_selection()


func _resize() -> void:
	var visible_items := mini(_entries.size() if not _entries.is_empty() else 1, _MAX_VISIBLE_ITEMS)
	var items_height := visible_items * _ITEM_HEIGHT
	var total_height := _TITLE_HEIGHT + items_height + _PADDING
	_scroll.custom_minimum_size.y = visible_items * _ITEM_HEIGHT
	custom_minimum_size = Vector2(_MODAL_WIDTH, total_height)
	size = Vector2(_MODAL_WIDTH, total_height)
	offset_left = -_MODAL_WIDTH / 2.0
	offset_top = -total_height / 2.0
	offset_right = _MODAL_WIDTH / 2.0
	offset_bottom = total_height / 2.0
	_action_panel.position = Vector2(_MODAL_WIDTH + 4.0, 0.0)
	_action_panel.size = Vector2(_ACTION_WIDTH, 0.0)


func _refresh_selection() -> void:
	for i in _item_list.get_child_count():
		var label := _item_list.get_child(i) as Label
		if label == null:
			continue
		if not _entries.is_empty() and i == _selected_index:
			var box := StyleBoxFlat.new()
			box.bg_color = _HIGHLIGHT_COLOR
			label.add_theme_stylebox_override("normal", box)
		else:
			label.remove_theme_stylebox_override("normal")


func _open_action_menu() -> void:
	_state = ModalState.ITEM_ACTION
	_action_index = 0
	var entry: Dictionary = _entries[_selected_index]
	var id: String = entry["id"]
	var inv: Node = entry["inventory"]
	var qty: int = 0
	for item_id in inv.items:
		if item_id == id:
			qty += 1
	_current_actions = ["Take", "Inspect"]
	if qty > 1:
		_current_actions.insert(1, "Take All")
	for child in _action_list.get_children():
		child.queue_free()
	for action in _current_actions:
		var label := Label.new()
		label.text = action
		label.custom_minimum_size.y = _ITEM_HEIGHT
		_action_list.add_child(label)
	_action_panel.visible = true
	_refresh_action_selection()


func _refresh_action_selection() -> void:
	for i in _action_list.get_child_count():
		var label := _action_list.get_child(i) as Label
		if label == null:
			continue
		if i == _action_index:
			var box := StyleBoxFlat.new()
			box.bg_color = _HIGHLIGHT_COLOR
			label.add_theme_stylebox_override("normal", box)
		else:
			label.remove_theme_stylebox_override("normal")


func _confirm_action() -> void:
	var action: String = _current_actions[_action_index]
	var entry: Dictionary = _entries[_selected_index]
	var id: String = entry["id"]
	var inv: Node = entry["inventory"]
	match action:
		"Take":
			if _player_inventory.add_item(id):
				inv.remove_item(id)
			_state = ModalState.BROWSING
			_action_panel.visible = false
			_rebuild()
		"Take All":
			while id in inv.items:
				if not _player_inventory.add_item(id):
					break
				inv.remove_item(id)
			_state = ModalState.BROWSING
			_action_panel.visible = false
			_rebuild()
		"Inspect":
			_state = ModalState.BROWSING
			_action_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match _state:
		ModalState.BROWSING:
			match event.keycode:
				KEY_W, KEY_UP:
					if not _entries.is_empty():
						_selected_index = posmod(_selected_index - 1, _entries.size())
						_refresh_selection()
					accept_event()
				KEY_S, KEY_DOWN:
					if not _entries.is_empty():
						_selected_index = posmod(_selected_index + 1, _entries.size())
						_refresh_selection()
					accept_event()
				KEY_E, KEY_ENTER, KEY_KP_ENTER:
					if not _entries.is_empty():
						_open_action_menu()
					accept_event()
				KEY_ESCAPE, KEY_Q:
					closed.emit()
					accept_event()
		ModalState.ITEM_ACTION:
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
					_state = ModalState.BROWSING
					_action_panel.visible = false
					accept_event()
