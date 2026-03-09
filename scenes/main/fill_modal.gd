extends Control

signal confirmed(liquid: String, amount_liters: float)
signal action_selected(action: String)
signal container_selected(inventory_index: int)
signal went_back

const _HIGHLIGHT_COLOR := Color(0.2, 0.5, 0.8, 0.4)
const _ITEM_HEIGHT := 24.0
const _TITLE_HEIGHT := 28.0
const _PADDING := 24.0
const _MIN_WIDTH := 160.0
const _CHAR_WIDTH := 8.0

enum Mode { FILL, ACTIONS, CONTAINER_PICK, INSPECT }

var mode: Mode = Mode.FILL
var _options: Array[float] = []
var _action_options: Array[String] = []
var _container_indices: Array[int] = []
var _selected_index: int = 0
var _liquid: String = ""
# Stack of { "title": String, "actions": Array[String], "mode": Mode }
var _back_stack: Array = []

var _title_label: Label
var _action_list: VBoxContainer
var _inspect_icon: TextureRect
var _info_label: Label
var _inspect_items: Control
var _durability_label: Label
var _damage_output_label: Label

func _ready() -> void:
	_title_label = $Panel/VBox/TitleLabel
	_action_list = $Panel/VBox/ActionList
	_inspect_items = $Panel/InspectItems
	_inspect_icon = $Panel/InspectItems/InspectIcon
	_info_label = $Panel/InspectItems/InfoLabel
	_durability_label = $Panel/InspectItems/DurabilityLabel
	_damage_output_label = $Panel/InspectItems/DamageOutputLabel
	_inspect_items.visible = false
	visible = false

func open(liquid: String, capacity_liters: float, current_liters: float) -> void:
	mode = Mode.FILL
	_liquid = liquid
	_options.clear()
	var steps := int(round(capacity_liters / 0.1))
	for i in range(1, steps + 1):
		var amount := snappedf(minf(i * 0.1, capacity_liters), 0.001)
		if amount > current_liters + 0.0001:
			if _options.is_empty() or _options.back() != amount:
				_options.append(amount)
	if _options.is_empty():
		visible = false
		return
	_title_label.text = liquid.capitalize()
	_selected_index = _options.size() - 1
	_inspect_items.visible = false
	_action_list.visible = true
	_rebuild_fill()
	visible = true

func open_actions(title: String, actions: Array, save_back: bool = false) -> void:
	if save_back:
		_back_stack.push_back({ "title": _title_label.text, "actions": _action_options.duplicate(), "mode": mode })
	else:
		_back_stack.clear()
	mode = Mode.ACTIONS
	_action_options.clear()
	for a in actions:
		_action_options.append(a as String)
	_title_label.text = title
	_selected_index = 0
	_inspect_items.visible = false
	_action_list.visible = true
	_rebuild_actions()
	visible = true

func open_container_picker(liquid: String, labels: Array[String], indices: Array[int]) -> void:
	_back_stack.push_back({ "title": _title_label.text, "actions": _action_options.duplicate(), "mode": mode })
	mode = Mode.CONTAINER_PICK
	_liquid = liquid
	_action_options.clear()
	for l in labels:
		_action_options.append(l)
	_container_indices = indices.duplicate()
	_title_label.text = "Choose container"
	_selected_index = 0
	_inspect_items.visible = false
	_action_list.visible = true
	_rebuild_actions()
	visible = true

func open_inspect(title: String, description: String, sprite_path: String, save_back: bool = false, dur_current: int = -1, dur_max: int = -1, hit_bonus: int = -1, damage_die: int = -1) -> void:
	if save_back:
		_back_stack.push_back({ "title": _title_label.text, "actions": _action_options.duplicate(), "mode": mode })
	else:
		_back_stack.clear()
	mode = Mode.INSPECT
	_title_label.text = title
	_action_list.visible = false
	if sprite_path != "":
		_inspect_icon.texture = load(sprite_path)
		_inspect_icon.visible = true
	else:
		_inspect_icon.visible = false
	_info_label.text = description
	if dur_current != -1:
		_durability_label.text = "Durability: %d / %d" % [dur_current, dur_max]
		_durability_label.visible = true
	else:
		_durability_label.visible = false
	if hit_bonus != -1 and damage_die != -1:
		_damage_output_label.text = "Damage: %dd(1-%d)" % [hit_bonus, damage_die]
		_damage_output_label.visible = true
	else:
		_damage_output_label.visible = false
	_inspect_items.visible = true
	_resize_inspect_panel()
	visible = true

func go_back() -> void:
	if not _back_stack.is_empty():
		var prev: Dictionary = _back_stack.pop_back()
		mode = Mode.ACTIONS
		_action_options.assign(prev["actions"])
		_title_label.text = prev["title"]
		_selected_index = 0
		_inspect_items.visible = false
		_action_list.visible = true
		_rebuild_actions()
		went_back.emit()
	else:
		went_back.emit()
		visible = false

func confirm() -> void:
	match mode:
		Mode.FILL:
			visible = false
			confirmed.emit(_liquid, _options[_selected_index])
		Mode.ACTIONS:
			action_selected.emit(_action_options[_selected_index])
		Mode.CONTAINER_PICK:
			visible = false
			container_selected.emit(_container_indices[_selected_index])
		Mode.INSPECT:
			if not _back_stack.is_empty():
				go_back()
			else:
				visible = false

func _rebuild_fill() -> void:
	for child in _action_list.get_children():
		child.free()
	for opt in _options:
		var label := Label.new()
		label.text = "%.0f mL" % (opt * 1000.0)
		label.custom_minimum_size.y = _ITEM_HEIGHT
		_action_list.add_child(label)
	_refresh_selection()
	_resize_panel()

func _rebuild_actions() -> void:
	for child in _action_list.get_children():
		child.free()
	for act in _action_options:
		var label := Label.new()
		label.text = act
		label.custom_minimum_size.y = _ITEM_HEIGHT
		_action_list.add_child(label)
	_refresh_selection()
	_resize_panel()

func _resize_panel() -> void:
	var panel: NinePatchRect = $Panel
	var longest := _title_label.text.length()
	for child in _action_list.get_children():
		var lbl := child as Label
		if lbl != null:
			longest = maxi(longest, lbl.text.length())
	var w := maxf(_MIN_WIDTH, longest * _CHAR_WIDTH + _PADDING * 2.0)
	var h := _TITLE_HEIGHT + _list_size() * _ITEM_HEIGHT + _PADDING * 2.0
	var viewport_size := get_viewport().get_visible_rect().size
	panel.size = Vector2(w, h)
	panel.position = (viewport_size - panel.size) / 2.0


func _resize_inspect_panel() -> void:
	var panel: NinePatchRect = $Panel
	var viewport_size := get_viewport().get_visible_rect().size
	# Derive panel size from the editor-placed InspectItems children
	var content_bottom := 0.0
	for child in _inspect_items.get_children():
		var c := child as Control
		if c != null and c.visible:
			content_bottom = maxf(content_bottom, c.position.y + c.size.y)
	var inspect_top: float = _inspect_items.position.y
	var h := inspect_top + content_bottom + _PADDING
	var w := _inspect_items.position.x + _info_label.size.x + _PADDING
	panel.size = Vector2(w, h)
	panel.position = (viewport_size - panel.size) / 2.0

func _refresh_selection() -> void:
	for i in _action_list.get_child_count():
		var label := _action_list.get_child(i) as Label
		if label == null:
			continue
		if i == _selected_index:
			var box := StyleBoxFlat.new()
			box.bg_color = _HIGHLIGHT_COLOR
			label.add_theme_stylebox_override("normal", box)
		else:
			label.remove_theme_stylebox_override("normal")

func _list_size() -> int:
	return _options.size() if mode == Mode.FILL else _action_options.size()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_W, KEY_UP:
			if mode != Mode.INSPECT:
				_selected_index = posmod(_selected_index - 1, _list_size())
				_refresh_selection()
			accept_event()
		KEY_S, KEY_DOWN:
			if mode != Mode.INSPECT:
				_selected_index = posmod(_selected_index + 1, _list_size())
				_refresh_selection()
			accept_event()
		KEY_E, KEY_ENTER, KEY_KP_ENTER:
			confirm()
			accept_event()
		KEY_Q, KEY_ESCAPE:
			go_back()
			accept_event()
