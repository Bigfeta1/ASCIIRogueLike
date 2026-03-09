extends Node3D

enum ActionState { MOVEMENT, LOOK, MENU, INTERACTION }
enum InteractionSubState { NONE, MOVE_CURSOR, INTERACTION_MENU, LOOT, COLLECT_LIQUID, INSPECTION, USE_ITEM }
enum CharacterType { SURGEON, ENEMY }
enum CharacterRole { PLAYER, NPC }
enum ModalContext { NONE, TILE_ACTIONS, TILE_FILL, INSPECT_TILE }

@export var character_type: CharacterType = CharacterType.SURGEON
@export var character_role: CharacterRole = CharacterRole.PLAYER

var faction: String = ""
var action_state: ActionState = ActionState.MOVEMENT
var interaction_sub_state: InteractionSubState = InteractionSubState.NONE
var defeated_sprite: String = ""
var corpse_item_id: String = ""

var _look_cursor: Node
var _interact_cursor: Node
var _character_sheet: Control
var _loot_modal: Control
var _fill_modal: Control
var _loot_interrupted: bool = false

var _modal_context: ModalContext = ModalContext.NONE
var _collect_item_id: String = ""
var _use_item_id: String = ""
var _collect_liquid: String = ""
var _tile_action_name: String = ""
var _tile_actions: Array = []

func _ready() -> void:
	_look_cursor = get_node("LookCursor")
	_interact_cursor = get_node("InteractCursor")
	if character_role == CharacterRole.PLAYER:
		_character_sheet = get_parent().get_node("CanvasLayer/CharacterSheet")
		_loot_modal = get_parent().get_node("CanvasLayer/LootModal")
		_fill_modal = get_parent().get_node("CanvasLayer/InteractModal")
		_fill_modal.confirmed.connect(_on_fill_confirmed)
		_fill_modal.action_selected.connect(_on_tile_action_selected)
		_fill_modal.container_selected.connect(_on_container_selected)
		_fill_modal.visibility_changed.connect(_on_modal_visibility_changed)
		_fill_modal.went_back.connect(_on_fill_modal_went_back)
		_loot_modal.closed.connect(func() -> void:
			action_state = ActionState.MOVEMENT
			interaction_sub_state = InteractionSubState.NONE
			_loot_modal.visible = false
			_interact_cursor.deactivate())
		_character_sheet.visible = false
		_character_sheet.init(get_node("CharacterInventory"))
		_character_sheet.close_requested.connect(func() -> void:
			_character_sheet.visible = false
			if _loot_interrupted:
				_loot_interrupted = false
				_loot_modal.visible = true
				action_state = ActionState.INTERACTION
				interaction_sub_state = InteractionSubState.LOOT
			else:
				action_state = ActionState.MOVEMENT
				interaction_sub_state = InteractionSubState.NONE)

		get_node("CharacterInventory").add_item("combat_knife")
		get_node("CharacterInventory").add_item("field_bandage")
		get_node("CharacterInventory").add_item("field_bandage")
		get_node("CharacterInventory").add_item("field_bandage")

func _unhandled_input(event: InputEvent) -> void:
	if character_role != CharacterRole.PLAYER:
		return
	if not event is InputEventKey:
		return
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_TAB:
			if action_state == ActionState.INTERACTION:
				if interaction_sub_state != InteractionSubState.LOOT:
					return
				_loot_interrupted = true
				_loot_modal.visible = false
			if action_state != ActionState.MENU:
				action_state = ActionState.MENU
				interaction_sub_state = InteractionSubState.NONE
				_character_sheet.visible = true
			elif _character_sheet._inventory_state == _character_sheet.InventoryState.ITEM_ACTION:
				pass
			elif _character_sheet._tab == _character_sheet.Tab.STATS:
				_character_sheet.close()
				_character_sheet.visible = false
			else:
				_character_sheet._set_tab(_character_sheet.Tab.STATS)
		KEY_I:
			if action_state == ActionState.INTERACTION:
				if interaction_sub_state != InteractionSubState.LOOT:
					return
				_loot_interrupted = true
				_loot_modal.visible = false
			if action_state != ActionState.MENU:
				action_state = ActionState.MENU
				interaction_sub_state = InteractionSubState.NONE
				_character_sheet.visible = true
				_character_sheet._set_tab(_character_sheet.Tab.INVENTORY)
			elif _character_sheet._inventory_state == _character_sheet.InventoryState.ITEM_ACTION:
				pass
			elif _character_sheet._tab == _character_sheet.Tab.INVENTORY:
				_character_sheet.close()
				_character_sheet.visible = false
			else:
				_character_sheet._set_tab(_character_sheet.Tab.INVENTORY)
		KEY_E:
			if action_state == ActionState.INTERACTION and interaction_sub_state == InteractionSubState.MOVE_CURSOR:
				_open_interaction_menu()
				get_viewport().set_input_as_handled()
				return
			if action_state != ActionState.MOVEMENT:
				return
			action_state = ActionState.INTERACTION
			interaction_sub_state = InteractionSubState.MOVE_CURSOR
			_interact_cursor.activate()
		KEY_C:
			if action_state == ActionState.MENU or action_state == ActionState.INTERACTION:
				return
			action_state = ActionState.LOOK if action_state == ActionState.MOVEMENT else ActionState.MOVEMENT
			if action_state == ActionState.LOOK:
				_look_cursor.activate()
			else:
				_look_cursor.deactivate()
		KEY_Q, KEY_ESCAPE:
			if action_state == ActionState.INTERACTION and interaction_sub_state == InteractionSubState.MOVE_CURSOR:
				action_state = ActionState.MOVEMENT
				interaction_sub_state = InteractionSubState.NONE
				_collect_item_id = ""
				_interact_cursor.deactivate()

func _on_modal_visibility_changed() -> void:
	print("[DBG] visibility_changed: fill_modal.visible=", _fill_modal.visible, " action_state=", action_state, " sub=", interaction_sub_state)
	if _fill_modal.visible or action_state != ActionState.INTERACTION:
		return
	match interaction_sub_state:
		InteractionSubState.INTERACTION_MENU:
			action_state = ActionState.MOVEMENT
			interaction_sub_state = InteractionSubState.NONE
			_interact_cursor.deactivate()
		InteractionSubState.COLLECT_LIQUID, InteractionSubState.INSPECTION, InteractionSubState.USE_ITEM:
			_on_modal_closed()

func _on_modal_closed() -> void:
	var ctx := _modal_context
	print("[DBG] _on_modal_closed: ctx=", ctx, " sub=", interaction_sub_state)
	_modal_context = ModalContext.NONE
	match ctx:
		ModalContext.NONE:
			if interaction_sub_state == InteractionSubState.INSPECTION:
				print("[DBG] restoring sheet from INSPECTION")
				interaction_sub_state = InteractionSubState.NONE
				action_state = ActionState.MENU
				_character_sheet._set_tab(_character_sheet.Tab.INVENTORY)
				_character_sheet.visible = true
			elif interaction_sub_state == InteractionSubState.USE_ITEM:
				interaction_sub_state = InteractionSubState.NONE
				action_state = ActionState.MENU
				_character_sheet._set_tab(_character_sheet.Tab.INVENTORY)
				_character_sheet.visible = true
		ModalContext.TILE_ACTIONS, ModalContext.TILE_FILL:
			interaction_sub_state = InteractionSubState.MOVE_CURSOR

func _on_fill_modal_went_back() -> void:
	print("[DBG] went_back fired: sub was=", interaction_sub_state)
	_modal_context = ModalContext.NONE
	interaction_sub_state = InteractionSubState.INTERACTION_MENU

func _open_interaction_menu() -> void:
	var cursor_pos: Vector2i = _interact_cursor.get_grid_pos()
	var grid_map: GridMap = get_parent().get_node("GridMap")
	var tile_id: int = grid_map.get_cell_item(Vector3i(cursor_pos.x, 0, cursor_pos.y))
	var true_tile: int = TileRegistry.get_original_tile(Vector3i(cursor_pos.x, 0, cursor_pos.y), tile_id)
	var tile_data := TileRegistry.get_tile(true_tile)
	_collect_liquid = tile_data.get("liquid", "")
	if _collect_item_id != "":
		var item_data := ItemRegistry.get_item(_collect_item_id)
		if item_data.get("category", "") == "container":
			var allowed: Array = item_data.get("allowed_liquids", [])
			if _collect_liquid != "" and allowed.has(_collect_liquid):
				var inventory: Node = get_node("CharacterInventory")
				var idx: int = inventory.items.find(_collect_item_id)
				var current: float = inventory.get_liquid(idx).get("amount_liters", 0.0)
				var capacity: float = item_data.get("capacity_liters", 0.0)
				_modal_context = ModalContext.TILE_FILL
				interaction_sub_state = InteractionSubState.COLLECT_LIQUID
				_fill_modal.open(_collect_liquid, capacity, current)
				return
	var actions: Array[String] = []
	for node in get_parent().get_children():
		if node == self:
			continue
		var other_movement := node.get_node_or_null("CharacterMovement")
		if other_movement == null or other_movement.grid_pos != cursor_pos:
			continue
		var other_ai := node.get_node_or_null("CharacterAI")
		if other_ai != null and (other_ai.behavior_state == other_ai.BehaviorState.KNOCKED_OUT or other_ai.behavior_state == other_ai.BehaviorState.DEAD):
			actions.append("Loot")
			break
	for action in tile_data.get("actions", []):
		actions.append(action as String)
	if not actions.has("Inspect"):
		actions.append("Inspect")
	_tile_action_name = tile_data.get("name", "")
	_tile_actions = actions
	interaction_sub_state = InteractionSubState.INTERACTION_MENU
	_fill_modal.open_actions(_tile_action_name, actions)

func _try_map_interact() -> void:
	var cursor_pos: Vector2i = _interact_cursor.get_grid_pos()
	var grid_map: GridMap = get_parent().get_node("GridMap")
	var tile_id: int = grid_map.get_cell_item(Vector3i(cursor_pos.x, 0, cursor_pos.y))
	var true_tile: int = TileRegistry.get_original_tile(Vector3i(cursor_pos.x, 0, cursor_pos.y), tile_id)
	var tile_name: String = TileRegistry.get_tile(true_tile).get("name", "")
	if _collect_item_id != "":
		var item_data := ItemRegistry.get_item(_collect_item_id)
		if item_data.get("category", "") == "container":
			var allowed: Array = item_data.get("allowed_liquids", [])
			if tile_name == "Water" and allowed.has("water"):
				var inventory: Node = get_node("CharacterInventory")
				var idx: int = inventory.items.find(_collect_item_id)
				var current: float = inventory.get_liquid(idx).get("amount_liters", 0.0)
				var capacity: float = item_data.get("capacity_liters", 0.0)
				_modal_context = ModalContext.TILE_FILL
				_fill_modal.open("water", capacity, current)
	else:
		var tile_data := TileRegistry.get_tile(true_tile)
		var actions: Array = tile_data.get("actions", [])
		if not actions.is_empty():
			_collect_liquid = tile_data.get("liquid", "")
			_tile_action_name = tile_name
			_tile_actions = actions
			_modal_context = ModalContext.TILE_ACTIONS
			_fill_modal.open_actions(tile_name, actions)

func _on_fill_confirmed(liquid: String, amount_liters: float) -> void:
	var item_id: String
	if interaction_sub_state == InteractionSubState.USE_ITEM:
		item_id = _use_item_id
		var inventory: Node = get_node("CharacterInventory")
		var idx: int = inventory.items.find(_use_item_id)
		var contents: Dictionary = inventory.get_liquid(idx)
		var remaining: float = snappedf(contents.get("amount_liters", 0.0) - amount_liters, 0.001)
		inventory.set_liquid(idx, liquid, remaining)
		_use_item_id = ""
	else:
		item_id = _collect_item_id
		var inventory: Node = get_node("CharacterInventory")
		var idx: int = inventory.items.find(_collect_item_id)
		inventory.set_liquid(idx, liquid, amount_liters)
		_collect_item_id = ""
		_interact_cursor.deactivate()
	_modal_context = ModalContext.NONE
	interaction_sub_state = InteractionSubState.NONE
	action_state = ActionState.MENU
	_character_sheet._set_tab(_character_sheet.Tab.INVENTORY)
	_character_sheet.select_item(item_id)
	_character_sheet.visible = true

func _on_tile_action_selected(action: String) -> void:
	if action == "Loot":
		var cursor_pos: Vector2i = _interact_cursor.get_grid_pos()
		var target_inventories: Array[Node] = []
		for node in get_parent().get_children():
			if node == self:
				continue
			var other_movement := node.get_node_or_null("CharacterMovement")
			if other_movement == null or other_movement.grid_pos != cursor_pos:
				continue
			var other_ai := node.get_node_or_null("CharacterAI")
			if other_ai != null and (other_ai.behavior_state == other_ai.BehaviorState.KNOCKED_OUT or other_ai.behavior_state == other_ai.BehaviorState.DEAD):
				target_inventories.append(node.get_node("CharacterInventory"))
		interaction_sub_state = InteractionSubState.LOOT
		_fill_modal.visible = false
		_loot_modal.open(target_inventories, get_node("CharacterInventory"))
		_loot_modal.visible = true
	elif action == "Collect":
		var inventory: Node = get_node("CharacterInventory")
		var labels: Array[String] = []
		var indices: Array[int] = []
		for i in inventory.items.size():
			var item_data := ItemRegistry.get_item(inventory.items[i])
			if item_data.get("category", "") != "container":
				continue
			var allowed: Array = item_data.get("allowed_liquids", [])
			if not allowed.has(_collect_liquid):
				continue
			var capacity: float = item_data.get("capacity_liters", 0.0)
			var current: float = inventory.get_liquid(i).get("amount_liters", 0.0)
			if current >= capacity:
				continue
			var fill_suffix := "  (%.0f/%.0f mL)" % [current * 1000.0, capacity * 1000.0]
			labels.append(item_data.get("name", inventory.items[i]) + fill_suffix)
			indices.append(i)
		interaction_sub_state = InteractionSubState.COLLECT_LIQUID
		_fill_modal.visible = false
		if labels.is_empty():
			_modal_context = ModalContext.TILE_ACTIONS
			_fill_modal.open_actions(_tile_action_name, _tile_actions)
			return
		_fill_modal.open_container_picker(_collect_liquid, labels, indices)
	elif action == "Inspect":
		var cursor_pos: Vector2i = _interact_cursor.get_grid_pos()
		var grid_map: GridMap = get_parent().get_node("GridMap")
		var tile_id: int = grid_map.get_cell_item(Vector3i(cursor_pos.x, 0, cursor_pos.y))
		var true_tile: int = TileRegistry.get_original_tile(Vector3i(cursor_pos.x, 0, cursor_pos.y), tile_id)
		var tile_data := TileRegistry.get_tile(true_tile)
		_modal_context = ModalContext.INSPECT_TILE
		interaction_sub_state = InteractionSubState.INSPECTION
		_fill_modal.open_inspect(
			tile_data.get("name", ""),
			tile_data.get("description", ""),
			tile_data.get("sprite", ""),
			true
		)
	else:
		interaction_sub_state = InteractionSubState.COLLECT_LIQUID
		_fill_modal.visible = false

func _on_container_selected(inventory_index: int) -> void:
	var inventory: Node = get_node("CharacterInventory")
	var item_data := ItemRegistry.get_item(inventory.items[inventory_index])
	var capacity: float = item_data.get("capacity_liters", 0.0)
	var current: float = inventory.get_liquid(inventory_index).get("amount_liters", 0.0)
	_collect_item_id = inventory.items[inventory_index]
	_fill_modal.open(_collect_liquid, capacity, current)

func open_inspect_modal(title: String, description: String, sprite_path: String, dur_current: int = -1, dur_max: int = -1, hit_bonus: int = -1, damage_die: int = -1) -> void:
	_character_sheet.visible = false
	action_state = ActionState.INTERACTION
	interaction_sub_state = InteractionSubState.INSPECTION
	_fill_modal.open_inspect(title, description, sprite_path, false, dur_current, dur_max, hit_bonus, damage_die)

func open_drink_modal(item_id: String, liquid: String, current_liters: float) -> void:
	_use_item_id = item_id
	_character_sheet._set_tab(_character_sheet.Tab.STATS)
	_character_sheet.visible = false
	action_state = ActionState.INTERACTION
	interaction_sub_state = InteractionSubState.USE_ITEM
	_fill_modal.open(liquid, current_liters, 0.0)

func activate_map_interaction(item_id: String) -> void:
	_collect_item_id = item_id
	_character_sheet._set_tab(_character_sheet.Tab.STATS)
	_character_sheet.visible = false
	action_state = ActionState.INTERACTION
	interaction_sub_state = InteractionSubState.MOVE_CURSOR
	_interact_cursor.activate()

func deactivate_map_interaction() -> void:
	_collect_item_id = ""
	action_state = ActionState.MOVEMENT
	interaction_sub_state = InteractionSubState.NONE
	_interact_cursor.deactivate()
