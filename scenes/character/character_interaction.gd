extends Node

# CharacterInteraction owns all player-side UI coordination:
# input handling for menus/look/interact, modal wiring, target lock,
# interaction menu construction, and pending action execution.
#
# action_state lives on character.gd as shared readable state (camera, movement, AI gate on it).
# interaction_sub_state and its enum live here — only this node and CharacterMovement read it.

enum InteractionSubState { NONE, MOVE_CURSOR, INTERACTION_MENU, LOOT, COLLECT_LIQUID, INSPECTION, USE_ITEM, DROPPING_ITEM, PLACE_CAMPFIRE }
enum ModalContext { NONE, TILE_ACTIONS, TILE_FILL, INSPECT_TILE }

var interaction_sub_state: InteractionSubState = InteractionSubState.NONE

var _character: Node
var _look_cursor: Node
var _interact_cursor: Node
var _target_cursor: MeshInstance3D
var _character_sheet: Control
var _loot_modal: Control
var _fill_modal: Control
var _grid_map: GridMap

var _loot_interrupted: bool = false
var _loot_inspect: bool = false
var _look_interrupted: bool = false
var _look_interrupted_pos: Vector2i = Vector2i.ZERO

var _modal_context: ModalContext = ModalContext.NONE
var _collect_item_id: String = ""
var _use_item_id: String = ""
var _drop_item_id: String = ""
var _tinderbox_item_id: String = ""
var _collect_liquid: String = ""
var _tile_action_name: String = ""
var _tile_actions: Array = []
var _cursor_entities: Array = []
var _selected_entity: Dictionary = {}

var pending_action: String = ""
var pending_target: Node = null

var _renal_debug_panel: Control = null
var _hypothalamus_debug_panel: Control = null
var _cardiovascular_debug_panel: Control = null
var _cardiac_pressure_graph: CardiacPressureGraph = null
var _pulmonary_debug_panel: Control = null
var _coagulation_debug_panel: Control = null


func _ready() -> void:
	_character = get_parent()
	if _character.character_role != _character.CharacterRole.PLAYER:
		return
	_look_cursor = _character.get_node("LookCursor")
	_interact_cursor = _character.get_node("InteractCursor")

func setup(grid_map: GridMap, character_sheet: Control, loot_modal: Control, fill_modal: Control) -> void:
	_grid_map = grid_map
	_character_sheet = character_sheet
	_loot_modal = loot_modal
	_fill_modal = fill_modal

	_fill_modal.confirmed.connect(_on_fill_confirmed)
	_fill_modal.action_selected.connect(_on_tile_action_selected)
	_fill_modal.container_selected.connect(_on_container_selected)
	_fill_modal.visibility_changed.connect(_on_modal_visibility_changed)
	_fill_modal.went_back.connect(_on_fill_modal_went_back)

	_loot_modal.closed.connect(func() -> void:
		_character.action_state = _character.ActionState.MOVEMENT
		interaction_sub_state = InteractionSubState.NONE
		_loot_modal.visible = false
		_interact_cursor.deactivate()
		for child in get_children():
			if child.get_script() != null and child.get_script().resource_path.ends_with("chest_inventory_proxy.gd"):
				child.queue_free())

	_loot_modal.inspect_requested.connect(func(item_id: String) -> void:
		_loot_inspect = true
		_loot_modal.visible = false
		var data := ItemRegistry.get_item(item_id)
		var dur_current: int = -1
		var dur_max: int = -1
		if data.has("durability_max"):
			dur_max = data["durability_max"] as int
			dur_current = dur_max
		open_inspect_modal(
			data.get("name", item_id),
			data.get("description", ""),
			data.get("sprite", ""),
			dur_current,
			dur_max,
			data.get("hit_bonus", -1) as int,
			data.get("damage_die", -1) as int))

	_character_sheet.visible = false
	_character_sheet.init(_character.get_node("CharacterInventory"))
	_character_sheet.close_requested.connect(func() -> void:
		_character_sheet.visible = false
		if _loot_interrupted:
			_loot_interrupted = false
			_loot_modal.visible = true
			_character.action_state = _character.ActionState.INTERACTION
			interaction_sub_state = InteractionSubState.LOOT
		else:
			_character.action_state = _character.ActionState.MOVEMENT
			interaction_sub_state = InteractionSubState.NONE)

	_character.get_node("CharacterMovement").moved.connect(_on_player_moved)


func _unhandled_input(event: InputEvent) -> void:
	if _character.character_role != _character.CharacterRole.PLAYER:
		return
	if not event is InputEventKey:
		return
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_TAB:
			if _character.action_state == _character.ActionState.INTERACTION:
				return
			if _character.action_state != _character.ActionState.MENU:
				_character.action_state = _character.ActionState.MENU
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
			if _character.action_state == _character.ActionState.INTERACTION:
				return
			if _character.action_state != _character.ActionState.MENU:
				_character.action_state = _character.ActionState.MENU
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
			if _character.action_state == _character.ActionState.LOOK:
				var look_pos: Vector2i = _look_cursor._cursor_grid_pos
				_look_interrupted = true
				_look_interrupted_pos = look_pos
				_look_cursor.deactivate()
				_character.action_state = _character.ActionState.INTERACTION
				_open_interaction_menu(look_pos, true)
				get_viewport().set_input_as_handled()
				return
			if _character.action_state == _character.ActionState.INTERACTION and interaction_sub_state == InteractionSubState.DROPPING_ITEM:
				_execute_drop()
				get_viewport().set_input_as_handled()
				return
			if _character.action_state == _character.ActionState.INTERACTION and interaction_sub_state == InteractionSubState.PLACE_CAMPFIRE:
				_execute_place_campfire()
				get_viewport().set_input_as_handled()
				return
			if _character.action_state == _character.ActionState.INTERACTION and interaction_sub_state == InteractionSubState.MOVE_CURSOR:
				if pending_action != "":
					_execute_pending_action()
				else:
					_open_interaction_menu()
				get_viewport().set_input_as_handled()
				return
			if _character.action_state != _character.ActionState.MOVEMENT:
				return
			pending_action = ""
			_character.action_state = _character.ActionState.INTERACTION
			interaction_sub_state = InteractionSubState.MOVE_CURSOR
			_interact_cursor.activate()
		KEY_C:
			if _character.action_state == _character.ActionState.MENU or _character.action_state == _character.ActionState.INTERACTION:
				return
			_character.action_state = _character.ActionState.LOOK if _character.action_state == _character.ActionState.MOVEMENT else _character.ActionState.MOVEMENT
			if _character.action_state == _character.ActionState.LOOK:
				_look_cursor.activate()
			else:
				_look_cursor.deactivate()
		KEY_KP_1:
			if _renal_debug_panel != null and _character.organs.pulmonary != null:
				if _character.organs.pulmonary.pneumothorax:
					_character.organs.pulmonary.resolve_pneumothorax()
				else:
					_character.organs.pulmonary.trigger_pneumothorax("right")
				_refresh_renal_debug()
		KEY_KP_2:
			if _renal_debug_panel != null and _character.organs.coagulation != null:
				_character.organs.coagulation.add_endothelial_injury(40.0)
				_refresh_renal_debug()
		KEY_KP_3:
			if _renal_debug_panel != null and _character.organs.coagulation != null:
				_character.organs.coagulation.trigger_trauma()
				_refresh_renal_debug()
		KEY_KP_4:
			if _character.organs.cardiovascular != null:
				var cardio: Node = _character.organs.cardiovascular
				cardio.sa_node.force_fire()
				var ticks: int = ceili(60.0 / cardio.heart_rate / cardio.SIM_STEP)
				var waveform: PackedStringArray = []
				for _i in ticks:
					cardio.tick(cardio.SIM_STEP)
					if _cardiac_pressure_graph != null:
						_cardiac_pressure_graph.record(cardio)
					waveform.append("LV=%.1f Ao=%.1f" % [cardio.lv.pressure, cardio.monitor.aorta_pressure])
				print("[WAVEFORM]")
				for w in waveform:
					print("  ", w)
				print("[BEAT] LA=%.1f LV=%.1f RA=%.1f RV=%.1f Aorta=%.1f(P=%.1f) VenaCava=%.1f PulmVein=%.1f EDV=%.1f ESV=%.1f SV=%.1f CO=%.2f HR=%.0f BP=%.0f/%.0f" % [
					cardio.la.volume, cardio.lv.volume,
					cardio.ra.volume, cardio.rv.volume,
					cardio.get_node("LeftHeart/Aorta").volume, cardio.monitor.aorta_pressure,
					cardio.get_node("RightHeart/VenaCava").volume,
					cardio.get_node("LeftHeart/PulmonaryVein").volume,
					cardio.monitor.EDV, cardio.monitor.ESV, cardio.monitor.SV,
					cardio.monitor.cardiac_output, cardio.heart_rate,
					cardio.monitor.bp_systolic, cardio.monitor.bp_diastolic
				])
				_refresh_renal_debug()
		KEY_F12:
			if _renal_debug_panel != null:
				_character.movement.moved.disconnect(_refresh_renal_debug)
				_character.movement.waited.disconnect(_refresh_renal_debug)
				_renal_debug_panel.queue_free()
				_renal_debug_panel = null
				_hypothalamus_debug_panel.queue_free()
				_hypothalamus_debug_panel = null
				_cardiovascular_debug_panel.queue_free()
				_cardiovascular_debug_panel = null
				_cardiac_pressure_graph.queue_free()
				_cardiac_pressure_graph = null
				_character.organs.cardiovascular.pressure_graph = null
				_pulmonary_debug_panel.queue_free()
				_pulmonary_debug_panel = null
				_coagulation_debug_panel.queue_free()
				_coagulation_debug_panel = null
			else:
				_show_renal_debug()
		KEY_Q, KEY_ESCAPE:
			if pending_target != null:
				pending_action = ""
				pending_target = null
				_unlock()
			if _character.action_state == _character.ActionState.LOOK:
				_character.action_state = _character.ActionState.MOVEMENT
				_look_cursor.deactivate()
			elif _character.action_state == _character.ActionState.INTERACTION and interaction_sub_state == InteractionSubState.DROPPING_ITEM:
				_drop_item_id = ""
				_character.action_state = _character.ActionState.MOVEMENT
				interaction_sub_state = InteractionSubState.NONE
				_interact_cursor.deactivate()
			elif _character.action_state == _character.ActionState.INTERACTION and interaction_sub_state == InteractionSubState.PLACE_CAMPFIRE:
				_tinderbox_item_id = ""
				_character.action_state = _character.ActionState.MOVEMENT
				interaction_sub_state = InteractionSubState.NONE
				_interact_cursor.deactivate()
			elif _character.action_state == _character.ActionState.INTERACTION and interaction_sub_state == InteractionSubState.MOVE_CURSOR:
				_character.action_state = _character.ActionState.MOVEMENT
				interaction_sub_state = InteractionSubState.NONE
				_collect_item_id = ""
				_interact_cursor.deactivate()


func _on_modal_visibility_changed() -> void:
	if _fill_modal.visible or _character.action_state != _character.ActionState.INTERACTION:
		return
	match interaction_sub_state:
		InteractionSubState.INTERACTION_MENU:
			if _look_interrupted:
				_look_interrupted = false
				_character.action_state = _character.ActionState.LOOK
				_look_cursor.activate_at(_look_interrupted_pos)
			else:
				_character.action_state = _character.ActionState.MOVEMENT
				interaction_sub_state = InteractionSubState.NONE
				_interact_cursor.deactivate()
		InteractionSubState.COLLECT_LIQUID, InteractionSubState.INSPECTION, InteractionSubState.USE_ITEM:
			_on_modal_closed()


func _on_modal_closed() -> void:
	var ctx := _modal_context
	_modal_context = ModalContext.NONE
	match ctx:
		ModalContext.NONE:
			if interaction_sub_state == InteractionSubState.INSPECTION:
				interaction_sub_state = InteractionSubState.NONE
				if _loot_inspect:
					_loot_inspect = false
					_loot_modal.visible = true
					_character.action_state = _character.ActionState.INTERACTION
					interaction_sub_state = InteractionSubState.LOOT
				else:
					_character.action_state = _character.ActionState.MENU
					_character_sheet._set_tab(_character_sheet.Tab.INVENTORY)
					_character_sheet.visible = true
			elif interaction_sub_state == InteractionSubState.USE_ITEM:
				interaction_sub_state = InteractionSubState.NONE
				_character.action_state = _character.ActionState.MENU
				_character_sheet._set_tab(_character_sheet.Tab.INVENTORY)
				_character_sheet.visible = true
		ModalContext.TILE_ACTIONS, ModalContext.TILE_FILL:
			interaction_sub_state = InteractionSubState.MOVE_CURSOR


func _on_fill_modal_went_back() -> void:
	_modal_context = ModalContext.NONE
	if not _fill_modal.visible:
		_selected_entity = {}
		if _look_interrupted:
			_look_interrupted = false
			_character.action_state = _character.ActionState.LOOK
			interaction_sub_state = InteractionSubState.NONE
			_look_cursor.activate_at(_look_interrupted_pos)
		else:
			interaction_sub_state = InteractionSubState.MOVE_CURSOR
	else:
		interaction_sub_state = InteractionSubState.INTERACTION_MENU
		var restored_title: String = _fill_modal._title_label.text
		var restored_to_entity := false
		for entity in _cursor_entities:
			if entity["name"] == restored_title:
				_selected_entity = entity
				restored_to_entity = true
				break
		if not restored_to_entity:
			_selected_entity = {}


func _lock_on(target: Node) -> void:
	pending_target = target
	if _target_cursor != null:
		_target_cursor.queue_free()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scenes/look_cursor/look_cursor.gdshader")
	mat.set_shader_parameter("border_color", Color(1, 0, 0, 1))
	mat.set_shader_parameter("border_thickness", 0.05)
	mat.set_shader_parameter("corner_length", 0.2)
	_target_cursor = MeshInstance3D.new()
	_target_cursor.mesh = PlaneMesh.new()
	_target_cursor.scale = Vector3(3.876, 3.876, 3.876)
	_target_cursor.material_override = mat
	_character.get_parent().add_child(_target_cursor)
	_update_target_cursor()


func _unlock() -> void:
	if _target_cursor != null:
		_target_cursor.queue_free()
		_target_cursor = null


func _on_player_moved() -> void:
	if _target_cursor != null:
		_update_target_cursor()


func _update_target_cursor() -> void:
	if pending_target == null or not is_instance_valid(pending_target):
		_unlock()
		return
	var target_pos: Vector2i = pending_target.get_node("CharacterMovement").grid_pos
	var world := _grid_map.to_global(_grid_map.map_to_local(Vector3i(target_pos.x, 0, target_pos.y)))
	_target_cursor.global_position = Vector3(world.x, 0.0, world.z)


func _execute_pending_action() -> void:
	match pending_action:
		"chop":
			if pending_target == null or not is_instance_valid(pending_target):
				pending_action = ""
				pending_target = null
				return
			var combat: Node = _character.combat
			if combat != null:
				combat.bump_attack(pending_target.get_node("CharacterMovement").grid_pos)
				combat._apply_damage(pending_target)
			_unlock()
			pending_action = ""
			pending_target = null
			_character.action_state = _character.ActionState.MOVEMENT
			interaction_sub_state = InteractionSubState.NONE
			_character.movement.moved.emit()


func _open_interaction_menu(cursor_pos: Vector2i = Vector2i(-9999, -9999), look_only: bool = false) -> void:
	if cursor_pos == Vector2i(-9999, -9999):
		cursor_pos = _interact_cursor.get_grid_pos()
	var tile_id: int = _grid_map.get_cell_item(Vector3i(cursor_pos.x, 0, cursor_pos.y))
	var true_tile: int = TileRegistry.get_original_tile(Vector3i(cursor_pos.x, 0, cursor_pos.y), tile_id)
	var tile_data := TileRegistry.get_tile(true_tile)
	_collect_liquid = tile_data.get("liquid", "")
	if _collect_item_id != "":
		var item_data := ItemRegistry.get_item(_collect_item_id)
		if item_data.get("category", "") == "container":
			var allowed: Array = item_data.get("allowed_liquids", [])
			if _collect_liquid != "" and allowed.has(_collect_liquid):
				var idx: int = _character.inventory.items.find(_collect_item_id)
				var current: float = _character.inventory.get_liquid(idx).get("amount_liters", 0.0)
				var capacity: float = item_data.get("capacity_liters", 0.0)
				_modal_context = ModalContext.TILE_FILL
				interaction_sub_state = InteractionSubState.COLLECT_LIQUID
				_fill_modal.open(_collect_liquid, capacity, current)
				return

	_cursor_entities.clear()
	_selected_entity = {}

	var occupancy_map: Node = _grid_map.get_node("OccupancyMap")
	var solid: Node = occupancy_map.get_solid(cursor_pos)
	if solid != null and solid != _character:
		if solid.character_type == solid.CharacterType.STRUCTURE:
			var structure_actions: Array[String] = []
			if not look_only:
				for a in solid.structure_actions:
					structure_actions.append(a as String)
			structure_actions.append("Inspect")
			if pending_target == solid:
				structure_actions.append("Unlock Target")
			else:
				structure_actions.append("Lock On")
			var struct_data := { "name": solid.display_name, "description": solid.description, "sprite": solid.inspect_sprite_path }
			_cursor_entities.append({ "name": solid.display_name, "type": "structure", "node": solid, "actions": structure_actions, "data": struct_data })
		else:
			if look_only:
				var char_actions: Array[String] = ["Inspect"]
				if pending_target == solid:
					char_actions.append("Unlock Target")
				else:
					char_actions.append("Lock On")
				var char_data := { "name": solid.display_name, "description": solid.description, "sprite": solid.sprite_path }
				_cursor_entities.append({ "name": solid.display_name, "type": "character", "node": solid, "actions": char_actions, "data": char_data })

	for node in occupancy_map.get_passable(cursor_pos):
		var other_ai: Node = node.get_node_or_null("CharacterAI")
		if other_ai == null or other_ai.life_state == other_ai.LifeState.ALIVE:
			continue
		var char_sprite: String = node.defeated_sprite if node.defeated_sprite != "" else node.sprite_path
		var char_name: String
		var char_desc: String
		if other_ai.life_state == other_ai.LifeState.DEAD:
			var corpse_data := ItemRegistry.get_item(node.corpse_item_id)
			char_name = corpse_data.get("name", node.display_name)
			char_desc = corpse_data.get("description", node.description)
		else:
			char_name = "%s (Incapacitated)" % node.display_name
			char_desc = node.description
		var char_data := { "name": char_name, "description": char_desc, "sprite": char_sprite }
		if look_only:
			var char_actions: Array[String] = ["Inspect"]
			if pending_target == node:
				char_actions.append("Unlock Target")
			else:
				char_actions.append("Lock On")
			_cursor_entities.append({ "name": char_name, "type": "character", "node": node, "actions": char_actions, "data": char_data })
		else:
			_cursor_entities.append({ "name": char_name, "type": "character", "node": node, "actions": ["Loot", "Inspect"], "data": char_data })

	var cell_world: Vector3 = _grid_map.to_global(_grid_map.map_to_local(Vector3i(cursor_pos.x, 0, cursor_pos.y)))
	for child in _grid_map.get_children():
		if child.get("item_id") == null:
			continue
		var dx: float = absf(child.global_position.x - cell_world.x)
		var dz: float = absf(child.global_position.z - cell_world.z)
		if dx > 0.1 or dz > 0.1:
			continue
		var wi_data := ItemRegistry.get_item(child.item_id)
		var wi_name: String = wi_data.get("name", child.item_id)
		var wi_actions: Array[String] = []
		if not look_only:
			wi_actions.append("Pick Up")
		wi_actions.append("Inspect")
		_cursor_entities.append({ "name": wi_name, "type": "world_item", "node": child, "actions": wi_actions, "data": wi_data })

	var tile_actions: Array[String] = ["Inspect"]
	if not look_only:
		for action in tile_data.get("actions", []):
			tile_actions.insert(tile_actions.size() - 1, action as String)
	_cursor_entities.append({ "name": tile_data.get("name", "Tile"), "type": "tile", "node": null, "actions": tile_actions, "data": tile_data })

	interaction_sub_state = InteractionSubState.INTERACTION_MENU
	if _cursor_entities.size() == 1:
		_open_entity_actions(_cursor_entities[0])
	else:
		var names: Array[String] = []
		for e in _cursor_entities:
			names.append(e["name"] as String)
		_fill_modal.open_actions("What?", names)


func _open_entity_actions(entity: Dictionary) -> void:
	_selected_entity = entity
	_tile_action_name = entity["name"]
	_tile_actions = entity["actions"]
	_fill_modal.open_actions(entity["name"], entity["actions"], _cursor_entities.size() > 1)


func _on_fill_confirmed(liquid: String, amount_liters: float) -> void:
	var item_id: String
	if _use_item_id != "":
		item_id = _use_item_id
		var idx: int = _character.inventory.items.find(_use_item_id)
		var contents: Dictionary = _character.inventory.get_liquid(idx)
		var remaining: float = snappedf(contents.get("amount_liters", 0.0) - amount_liters, 0.001)
		_character.inventory.set_liquid(idx, liquid, remaining)
		if _character.organs.renal != null:
			_character.organs.renal.drink(amount_liters)
		_use_item_id = ""
	else:
		item_id = _collect_item_id
		var idx: int = _character.inventory.items.find(_collect_item_id)
		_character.inventory.set_liquid(idx, liquid, amount_liters)
		_collect_item_id = ""
		_interact_cursor.deactivate()
	_modal_context = ModalContext.NONE
	interaction_sub_state = InteractionSubState.NONE
	_character.action_state = _character.ActionState.MENU
	_character_sheet._set_tab(_character_sheet.Tab.INVENTORY)
	_character_sheet.select_item(item_id)
	_character_sheet.visible = true


func _on_tile_action_selected(action: String) -> void:
	if _selected_entity.is_empty():
		for entity in _cursor_entities:
			if entity["name"] == action:
				_open_entity_actions(entity)
				return
		return
	if action == "Lock On":
		var target_node: Node = _selected_entity.get("node", null)
		_look_interrupted = false
		_fill_modal.visible = false
		_character.action_state = _character.ActionState.MOVEMENT
		interaction_sub_state = InteractionSubState.NONE
		_interact_cursor.deactivate()
		_lock_on(target_node)
	elif action == "Unlock Target":
		pending_action = ""
		pending_target = null
		_unlock()
		_look_interrupted = false
		_fill_modal.visible = false
		_character.action_state = _character.ActionState.MOVEMENT
		interaction_sub_state = InteractionSubState.NONE
		_interact_cursor.deactivate()
	elif action == "Chop":
		var structure_node: Node = _selected_entity.get("node", null)
		pending_action = "chop"
		_fill_modal.visible = false
		_character.action_state = _character.ActionState.MOVEMENT
		interaction_sub_state = InteractionSubState.NONE
		_interact_cursor.deactivate()
		_lock_on(structure_node)
		if structure_node != null:
			var combat: Node = _character.combat
			if combat != null:
				combat.bump_attack(structure_node.get_node("CharacterMovement").grid_pos)
				combat._apply_damage(structure_node)
		_character.movement.moved.emit()
	elif action == "Take Chest":
		var structure_node: Node = _selected_entity.get("node", null)
		if structure_node != null:
			var chest_inv: Node = structure_node.get_node("CharacterInventory")
			var contents_weight: float = 0.0
			for content_id in chest_inv.items:
				contents_weight += ItemRegistry.get_item(content_id).get("weight", 0.0) as float
			if _character.inventory.can_add(structure_node.structure_id, contents_weight) and _character.inventory.add_item(structure_node.structure_id):
				var inv: Node = _character.inventory
				var uid: int = inv.item_uids[inv.items.rfind(structure_node.structure_id)]
				inv.chest_contents[uid] = chest_inv.items.duplicate()
				var occupancy_map: Node = _grid_map.get_node("OccupancyMap")
				occupancy_map.unregister_solid(structure_node.movement.grid_pos, structure_node)
				structure_node.remove_from_group("structures")
				structure_node.queue_free()
		_fill_modal.visible = false
		_character.action_state = _character.ActionState.MOVEMENT
		interaction_sub_state = InteractionSubState.NONE
		_interact_cursor.deactivate()
		_character.movement.moved.emit()
	elif action == "Open":
		var structure_node: Node = _selected_entity.get("node", null)
		if structure_node != null:
			var target_inventories: Array[Node] = [structure_node.get_node("CharacterInventory")]
			interaction_sub_state = InteractionSubState.LOOT
			_fill_modal.visible = false
			_loot_modal.open(target_inventories, _character.inventory)
			_loot_modal.visible = true
	elif action == "Loot":
		var cursor_pos: Vector2i = _interact_cursor.get_grid_pos()
		var target_inventories: Array[Node] = []
		var occupancy_map: Node = _grid_map.get_node("OccupancyMap")
		for node in occupancy_map.get_passable(cursor_pos):
			var other_ai: Node = node.get_node_or_null("CharacterAI")
			if other_ai != null and other_ai.life_state != other_ai.LifeState.ALIVE:
				target_inventories.append(node.get_node("CharacterInventory"))
		interaction_sub_state = InteractionSubState.LOOT
		_fill_modal.visible = false
		_loot_modal.open(target_inventories, _character.inventory)
		_loot_modal.visible = true
	elif action == "Collect":
		var labels: Array[String] = []
		var indices: Array[int] = []
		for i in _character.inventory.items.size():
			var item_data := ItemRegistry.get_item(_character.inventory.items[i])
			if item_data.get("category", "") != "container":
				continue
			var allowed: Array = item_data.get("allowed_liquids", [])
			if not allowed.has(_collect_liquid):
				continue
			var capacity: float = item_data.get("capacity_liters", 0.0)
			var current: float = _character.inventory.get_liquid(i).get("amount_liters", 0.0)
			if current >= capacity:
				continue
			var fill_suffix := "  (%.0f/%.0f mL)" % [current * 1000.0, capacity * 1000.0]
			labels.append(item_data.get("name", _character.inventory.items[i]) + fill_suffix)
			indices.append(i)
		interaction_sub_state = InteractionSubState.COLLECT_LIQUID
		_fill_modal.visible = false
		if labels.is_empty():
			_modal_context = ModalContext.TILE_ACTIONS
			_fill_modal.open_actions(_tile_action_name, _tile_actions)
			return
		_fill_modal.open_container_picker(_collect_liquid, labels, indices)
	elif action == "Pick Up":
		var world_item_node: Node = _selected_entity.get("node", null)
		if world_item_node != null:
			_character.inventory.add_item(world_item_node.item_id)
			world_item_node.queue_free()
		_fill_modal.visible = false
		_character.action_state = _character.ActionState.MOVEMENT
		interaction_sub_state = InteractionSubState.NONE
		_interact_cursor.deactivate()
		_character.movement.moved.emit()
	elif action == "Inspect":
		var entity_data: Dictionary = _selected_entity.get("data", {})
		_modal_context = ModalContext.INSPECT_TILE
		interaction_sub_state = InteractionSubState.INSPECTION
		_fill_modal.open_inspect(
			entity_data.get("name", _selected_entity.get("name", "")),
			entity_data.get("description", ""),
			entity_data.get("sprite", ""),
			true)
	else:
		interaction_sub_state = InteractionSubState.COLLECT_LIQUID
		_fill_modal.visible = false


func _on_container_selected(inventory_index: int) -> void:
	var item_data := ItemRegistry.get_item(_character.inventory.items[inventory_index])
	var capacity: float = item_data.get("capacity_liters", 0.0)
	var current: float = _character.inventory.get_liquid(inventory_index).get("amount_liters", 0.0)
	_collect_item_id = _character.inventory.items[inventory_index]
	_fill_modal.open(_collect_liquid, capacity, current)


# --- Public API called via character.gd delegates ---

func open_inspect_modal(title: String, description: String, sprite_path: String, dur_current: int = -1, dur_max: int = -1, hit_bonus: int = -1, damage_die: int = -1) -> void:
	_character_sheet.visible = false
	_character.action_state = _character.ActionState.INTERACTION
	interaction_sub_state = InteractionSubState.INSPECTION
	_fill_modal.open_inspect(title, description, sprite_path, false, dur_current, dur_max, hit_bonus, damage_die)


func open_drink_modal(item_id: String, liquid: String, current_liters: float) -> void:
	_use_item_id = item_id
	_character_sheet._set_tab(_character_sheet.Tab.STATS)
	_character_sheet.visible = false
	_character.action_state = _character.ActionState.INTERACTION
	interaction_sub_state = InteractionSubState.USE_ITEM
	_fill_modal.open(liquid, current_liters, 0.0)


func activate_map_interaction(item_id: String) -> void:
	_collect_item_id = item_id
	_character_sheet._set_tab(_character_sheet.Tab.STATS)
	_character_sheet.visible = false
	_character.action_state = _character.ActionState.INTERACTION
	interaction_sub_state = InteractionSubState.MOVE_CURSOR
	_interact_cursor.activate()


func deactivate_map_interaction() -> void:
	_collect_item_id = ""
	_character.action_state = _character.ActionState.MOVEMENT
	interaction_sub_state = InteractionSubState.NONE
	_interact_cursor.deactivate()


func open_chest_contents(item_id: String, uid: int) -> void:
	var contents: Array = _character.inventory.chest_contents.get(uid, [])
	var proxy_script := load("res://scenes/items/chest_inventory_proxy.gd")
	var proxy: Node = Node.new()
	proxy.set_script(proxy_script)
	proxy.init(_character.inventory, uid, contents)
	add_child(proxy)
	var target_inventories: Array[Node] = [proxy]
	_loot_interrupted = true
	_character_sheet.visible = false
	_character.action_state = _character.ActionState.INTERACTION
	interaction_sub_state = InteractionSubState.LOOT
	_loot_modal.open(target_inventories, _character.inventory)
	_loot_modal.visible = true


func activate_place_campfire(item_id: String) -> void:
	_tinderbox_item_id = item_id
	_character_sheet.visible = false
	_character.action_state = _character.ActionState.INTERACTION
	interaction_sub_state = InteractionSubState.PLACE_CAMPFIRE
	_interact_cursor.activate()


func _execute_place_campfire() -> void:
	if _tinderbox_item_id == "":
		return
	var cursor_pos: Vector2i = _interact_cursor.get_grid_pos()
	var cell_world: Vector3 = _grid_map.to_global(_grid_map.map_to_local(Vector3i(cursor_pos.x, 0, cursor_pos.y)))
	var logs_node: Node = null
	for child in _grid_map.get_children():
		if child.get("item_id") != "logs":
			continue
		if absf(child.global_position.x - cell_world.x) > 0.1 or absf(child.global_position.z - cell_world.z) > 0.1:
			continue
		logs_node = child
		break
	if logs_node == null:
		return
	logs_node.queue_free()
	var structure_configurator: Node = _grid_map.get_node_or_null("StructureConfigurator")
	if structure_configurator != null:
		structure_configurator.spawn_one("campfire", cursor_pos, -1, [])
	_tinderbox_item_id = ""
	_character.action_state = _character.ActionState.MOVEMENT
	interaction_sub_state = InteractionSubState.NONE
	_interact_cursor.deactivate()
	_character.movement.moved.emit()


func activate_drop_item(item_id: String) -> void:
	_drop_item_id = item_id
	_character_sheet.visible = false
	_character.action_state = _character.ActionState.INTERACTION
	interaction_sub_state = InteractionSubState.DROPPING_ITEM
	_interact_cursor.activate()


func _show_renal_debug() -> void:
	if _character.organs.renal == null:
		return
	var canvas_layer: CanvasLayer = _character.get_parent().get_node("CanvasLayer")

	var renal_panel := PanelContainer.new()
	renal_panel.position = Vector2(10, 60)
	var renal_label := Label.new()
	renal_label.add_theme_font_size_override("font_size", 14)
	renal_panel.add_child(renal_label)
	canvas_layer.add_child(renal_panel)
	_renal_debug_panel = renal_panel

	var hypo_panel := PanelContainer.new()
	hypo_panel.position = Vector2(310, 60)
	var hypo_label := Label.new()
	hypo_label.add_theme_font_size_override("font_size", 14)
	hypo_panel.add_child(hypo_label)
	canvas_layer.add_child(hypo_panel)
	_hypothalamus_debug_panel = hypo_panel

	var cardio_panel := PanelContainer.new()
	cardio_panel.position = Vector2(610, 60)
	var cardio_label := Label.new()
	cardio_label.add_theme_font_size_override("font_size", 14)
	cardio_panel.add_child(cardio_label)
	canvas_layer.add_child(cardio_panel)
	_cardiovascular_debug_panel = cardio_panel

	var graph := CardiacPressureGraph.new()
	graph.position = Vector2(900, 700)
	canvas_layer.add_child(graph)
	_cardiac_pressure_graph = graph
	_character.organs.cardiovascular.pressure_graph = graph

	var pulm_panel := PanelContainer.new()
	pulm_panel.position = Vector2(910, 60)
	var pulm_label := Label.new()
	pulm_label.add_theme_font_size_override("font_size", 14)
	pulm_panel.add_child(pulm_label)
	canvas_layer.add_child(pulm_panel)
	_pulmonary_debug_panel = pulm_panel

	var coag_panel := PanelContainer.new()
	coag_panel.position = Vector2(1210, 60)
	var coag_label := Label.new()
	coag_label.add_theme_font_size_override("font_size", 14)
	coag_panel.add_child(coag_label)
	canvas_layer.add_child(coag_panel)
	_coagulation_debug_panel = coag_panel

	_refresh_renal_debug()
	_character.movement.moved.connect(_refresh_renal_debug)
	_character.movement.waited.connect(_refresh_renal_debug)


func _refresh_renal_debug() -> void:
	if _renal_debug_panel == null:
		return
	var renal: Node = _character.organs.renal
	renal.tick()
	var renal_label: Label = _renal_debug_panel.get_child(0)
	renal_label.text = (
		"[RENAL DEBUG]\n"
		+ "Body Mass:        %.1f kg\n" % renal.body_mass
		+ "Total Body Water: %.0f mL\n" % renal.total_body_water
		+ "Intracellular:    %.0f mL\n" % renal.intracellular_fluid
		+ "Extracellular:    %.0f mL\n" % renal.extracellular_fluid
		+ "  Interstitial:   %.0f mL\n" % renal.interstitial_fluid
		+ "  Plasma:         %.0f mL\n" % renal.plasma_fluid
		+ "Renal Blood Flow: %.0f mL/min\n" % renal.renal_blood_flow
		+ "Renal Plasma Flow:%.0f mL/min\n" % renal.renal_plasma_flow
		+ "Net Filtration:   %.1f mmHg\n" % renal.net_filtration
		+ "GFR:              %.1f mL/min\n" % renal.gfr
		+ "FF:               %.3f\n" % renal.ff
		+ "Plasma Creatinine:%.4f mg/mL\n" % renal.plasma_creatinine
		+ "Urine Creatinine: %.1f mg/day\n" % renal.urine_creatinine
	)

	if _hypothalamus_debug_panel == null:
		return
	var hypo: Node = _character.organs.hypothalamus
	var hypo_label: Label = _hypothalamus_debug_panel.get_child(0)
	hypo_label.text = (
		"[HYPOTHALAMUS DEBUG]\n"
		+ "Plasma Osmolality:    %.1f mOsm/kg\n" % renal.plasma_osmolality
		+ "Plasma Na:            %.1f mEq/L\n" % renal.plasma_sodium
		+ "Plasma Glucose:       %.1f mg/dL\n" % renal.plasma_glucose
		+ "Plasma BUN:           %.1f mg/dL\n" % renal.plasma_bun
		+ "Thirsty:              %s\n" % str(hypo.is_thirsty)
		+ "Dehydrated:           %s\n" % str(hypo.is_dehydrated)
		+ "Severely Dehydrated:  %s\n" % str(hypo.is_severely_dehydrated)
		+ "Hungry:               %s\n" % str(hypo.is_hungry)
	)

	if _cardiovascular_debug_panel == null:
		return
	var cardio: Node = _character.organs.cardiovascular
	var cardio_label: Label = _cardiovascular_debug_panel.get_child(0)
	cardio_label.text = (
		"[CARDIOVASCULAR]\n"
		+ "HR:         %.0f bpm\n" % cardio.heart_rate
		+ "SV:         %.1f mL\n" % cardio.monitor.SV
		+ "EDV:        %.1f mL\n" % cardio.monitor.EDV
		+ "ESV:        %.1f mL\n" % cardio.monitor.ESV
		+ "EF:         %.1f %%\n" % cardio.monitor.EF
		+ "CO:         %.2f L/min\n" % cardio.monitor.cardiac_output
		+ "MAP:        %.1f mmHg\n" % cardio.monitor.mean_arterial_pressure
		+ "BP:         %.0f/%.0f mmHg\n" % [cardio.monitor.bp_systolic, cardio.monitor.bp_diastolic]
		+ "TPR:        %.1f\n" % cardio.TPR
		+ "\n[LEFT ATRIA]\n"
		+ "LA Vol:     %.1f mL\n" % cardio.la.volume
		+ "PCWP:       %.1f mmHg\n" % cardio.monitor.pcwp
		+ "Mitral:     %s\n" % ("OPEN" if cardio.la.valve_open else "CLOSED")
		+ "Atrial:     %s\n" % ("SYSTOLE" if cardio.la.in_systole else "DIASTOLE")
		+ "\n[LEFT VENTRICLE]\n"
		+ "LV Vol:     %.1f mL\n" % cardio.lv.volume
		+ "LV Press:   %.1f mmHg\n" % cardio.lv.pressure
		+ "Aortic:     %s\n" % ("OPEN" if cardio.lv.valve_open else "CLOSED")
		+ "\n[RIGHT ATRIA]\n"
		+ "RA Vol:     %.1f mL\n" % cardio.ra.volume
		+ "RA Press:   %.1f mmHg\n" % cardio.ra.pressure
		+ "Tricuspid:  %s\n" % ("OPEN" if cardio.ra.valve_open else "CLOSED")
		+ "\n[RIGHT VENTRICLE]\n"
		+ "RV Vol:     %.1f mL\n" % cardio.rv.volume
		+ "RV Press:   %.1f mmHg\n" % cardio.rv.pressure
		+ "Pulmonic:   %s\n" % ("OPEN" if cardio.rv.valve_open else "CLOSED")
		+ "\n[VASCULATURE]\n"
		+ "Aorta Vol:  %.1f mL\n" % cardio.get_node("LeftHeart/Aorta").volume
		+ "Aorta P:    %.1f mmHg\n" % cardio.monitor.aorta_pressure
		+ "VenaCava:   %.1f mL\n" % cardio.get_node("RightHeart/VenaCava").volume
		+ "PulmVein:   %.1f mL\n" % cardio.get_node("LeftHeart/PulmonaryVein").volume
		+ "\n[SA NODE]\n"
		+ "Vm:         %.1f mV\n" % cardio.get_node("HeartElectricalSystem/AtrialComponents/SAnode").membrane_potential
		+ "SA State:   %s\n" % ["PHASE_4", "PHASE_0", "PHASE_3"][cardio.get_node("HeartElectricalSystem/AtrialComponents/SAnode").state]
		+ "\n[CONDUCTION]\n"
		+ "AtrialTract:%s\n" % ("C" if cardio.get_node("HeartElectricalSystem/AtrialComponents/AtrialTract").conducting else ".")
		+ "AV Node:    %s\n" % ("C" if cardio.get_node("HeartElectricalSystem/Ventricularcomponents/AVnode").conducting else ".")
		+ "His:        %s\n" % ("C" if cardio.get_node("HeartElectricalSystem/Ventricularcomponents/BundleOfHis").conducting else ".")
		+ "Purkinje:   %s\n" % ("C" if cardio.get_node("HeartElectricalSystem/Ventricularcomponents/PurkinjeFibers").conducting else ".")
	)

	if _cardiac_pressure_graph != null:
		_cardiac_pressure_graph.record(cardio)

	if _pulmonary_debug_panel == null:
		return
	var pulm: Node = _character.organs.pulmonary
	var pulm_label: Label = _pulmonary_debug_panel.get_child(0)
	pulm_label.text = (
		"[PULMONARY DEBUG]\n"
		+ "Resp Rate:      %.0f bpm\n" % pulm.respiratory_rate
		+ "Tidal Volume:   %.0f mL\n" % pulm.tidal_volume
		+ "Minute Vent:    %.0f mL/min\n" % pulm.minute_ventilation
		+ "Alveolar Vent:  %.0f mL/min\n" % pulm.alveolar_ventilation
		+ "PaO2:           %.1f mmHg\n" % pulm.pao2
		+ "PaCO2:          %.1f mmHg\n" % pulm.paco2
		+ "Pulm Vein O2:   %.1f mmHg\n" % pulm.pulm_vein_o2
		+ "SpO2:           %.1f %%\n" % pulm.pao2_spo2
		+ "Pneumothorax:   %s\n" % ("YES (%s)" % pulm.pneumothorax_side if pulm.pneumothorax else "No")
		+ "Pleural Pres:   %.1f cmH2O\n" % pulm.pleural_pressure
		+ "Venous Return:  %.0f %%\n" % (pulm.venous_return_fraction * 100.0)
		+ "PE:             %s\n" % ("YES (%.0f%%)" % (pulm.pe_severity * 100.0) if pulm.pulmonary_embolism else "No")
		+ "RV Strain:      %.0f %%\n" % (pulm.pe_rv_strain * 100.0)
	)

	if _coagulation_debug_panel == null:
		return
	var coag: Node = _character.organs.coagulation
	var coag_label: Label = _coagulation_debug_panel.get_child(0)
	coag_label.text = (
		"[COAGULATION DEBUG]\n"
		+ "Stasis:         %.0f %%\n" % coag.stasis_score
		+ "Injury:         %.0f %%\n" % coag.endothelial_injury
		+ "Heparin:        %s\n" % ("ACTIVE" if coag.heparin_active else "No")
		+ "── Extrinsic ──\n"
		+ "VII:            %.1f\n" % coag.factor_7
		+ "VIIa:           %.1f\n" % coag.factor_7a
		+ "Tissue Factor:  %.1f\n" % coag.tissue_factor
		+ "TF-VIIa:        %.1f\n" % coag.tf_viia
		+ "── Common ──\n"
		+ "Xa:             %.1f\n" % coag.factor_10a
		+ "Prothrombin:    %.1f\n" % coag.prothrombin
		+ "Thrombin:       %.1f\n" % coag.thrombin
		+ "Fibrinogen:     %.1f\n" % coag.fibrinogen
		+ "Fibrin:         %.1f\n" % coag.fibrin
		+ "Clot:           %.1f %%\n" % coag.crosslinkage
		+ "── Intrinsic ──\n"
		+ "XIa:            %.1f\n" % coag.factor_11a
		+ "IXa:            %.1f\n" % coag.factor_9a
		+ "Embolized:      %s\n" % ("YES" if coag.embolism_triggered else "No")
		+ "── Fibrinolytic ──\n"
		+ "Plasmin:        %.1f\n" % coag.plasmin
	)


func _execute_drop() -> void:
	if _drop_item_id == "":
		return
	var cursor_pos: Vector2i = _interact_cursor.get_grid_pos()
	var inv: Node = _character.inventory
	var item_idx: int = inv.items.rfind(_drop_item_id)
	var uid: int = inv.item_uids[item_idx]
	var saved_contents: Array = inv.chest_contents.get(uid, [])
	var structure_configurator: Node = _grid_map.get_node_or_null("StructureConfigurator")
	var is_structure: bool = inv.chest_contents.has(uid)
	if is_structure and structure_configurator != null:
		inv.remove_item(_drop_item_id)
		structure_configurator.spawn_one(_drop_item_id, cursor_pos, -1, saved_contents)
	else:
		var item_data := ItemRegistry.get_item(_drop_item_id)
		var world_item_scene := load("res://scenes/items/world_item.tscn")
		var world_item: MeshInstance3D = world_item_scene.instantiate()
		world_item.item_id = _drop_item_id
		if item_data.has("sprite"):
			var mat := StandardMaterial3D.new()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_texture = load(item_data["sprite"])
			world_item.material_override = mat
		_grid_map.add_child(world_item)
		world_item.global_position = _grid_map.to_global(_grid_map.map_to_local(Vector3i(cursor_pos.x, 0, cursor_pos.y)))
		inv.remove_item(_drop_item_id)
	_drop_item_id = ""
	_character.action_state = _character.ActionState.MOVEMENT
	interaction_sub_state = InteractionSubState.NONE
	_interact_cursor.deactivate()
