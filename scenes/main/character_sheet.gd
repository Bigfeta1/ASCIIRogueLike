extends Control

signal close_requested

enum Tab { STATS, SKILLS, INVENTORY }
enum InventoryState { BROWSING, ITEM_ACTION }

const _HIGHLIGHT_COLOR := Color(0.2, 0.5, 0.8, 0.4)
const _ACTION_LABELS := ["Inspect", "Drop"]

var _tab: Tab = Tab.STATS
var _inventory_state: InventoryState = InventoryState.BROWSING
var _selected_index: int = 0
var _action_index: int = 0
var _inventory: Node
var _action_panel: PanelContainer
var _action_list: VBoxContainer

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

func _set_tab(tab: Tab) -> void:
	_tab = tab
	$StatsPanel.visible = _tab == Tab.STATS
	$SkillsPanel.visible = _tab == Tab.SKILLS
	$InventoryPanel.visible = _tab == Tab.INVENTORY
	_selected_index = 0
	_set_inventory_state(InventoryState.BROWSING)
	_refresh_selection()
	get_viewport().gui_release_focus()

func _set_inventory_state(state: InventoryState) -> void:
	_inventory_state = state
	_action_panel.visible = _inventory_state == InventoryState.ITEM_ACTION
	if _inventory_state == InventoryState.ITEM_ACTION:
		_action_index = 0
		_refresh_action_selection()

func _open_item_action(item_label: Label) -> void:
	var label_global := item_label.get_global_rect()
	_action_panel.position = label_global.position - _action_panel.get_parent().get_global_position() + Vector2(320.0, 0.0)
	_set_inventory_state(InventoryState.ITEM_ACTION)

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
			_action_index = posmod(_action_index - 1, _ACTION_LABELS.size())
			_refresh_action_selection()
			accept_event()
		KEY_S, KEY_DOWN:
			_action_index = posmod(_action_index + 1, _ACTION_LABELS.size())
			_refresh_action_selection()
			accept_event()
		KEY_E, KEY_ENTER, KEY_KP_ENTER:
			_confirm_action()
			accept_event()
		KEY_ESCAPE:
			_set_inventory_state(InventoryState.BROWSING)
			accept_event()

func _confirm_action() -> void:
	# Placeholder — actions will be implemented later
	_set_inventory_state(InventoryState.BROWSING)

func _refresh_selection() -> void:
	if _inventory == null:
		return
	var entries: Array = _inventory.selectable_entries
	for i in entries.size():
		var label: Label = entries[i]["node"]
		if i == _selected_index:
			label.add_theme_stylebox_override("normal", _make_highlight_box())
		else:
			label.remove_theme_stylebox_override("normal")

func _refresh_action_selection() -> void:
	for i in _action_list.get_child_count():
		var label := _action_list.get_child(i) as Label
		if i == _action_index:
			label.add_theme_stylebox_override("normal", _make_highlight_box())
		else:
			label.remove_theme_stylebox_override("normal")

func _make_highlight_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = _HIGHLIGHT_COLOR
	return box
