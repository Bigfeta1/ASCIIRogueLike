extends Node3D

enum ActionState { MOVEMENT, LOOK, MENU, INTERACTION }
enum CharacterType { SURGEON, ENEMY }
enum CharacterRole { PLAYER, NPC }

@export var character_type: CharacterType = CharacterType.SURGEON
@export var character_role: CharacterRole = CharacterRole.PLAYER

var faction: String = ""
var action_state: ActionState = ActionState.MOVEMENT
var defeated_sprite: String = ""

var _look_cursor: Node
var _character_sheet: Control
var _loot_modal: Control
var _loot_interrupted: bool = false

func _ready() -> void:
	_look_cursor = get_node("LookCursor")
	if character_role == CharacterRole.PLAYER:
		_character_sheet = get_parent().get_node("CanvasLayer/CharacterSheet")
		_loot_modal = get_parent().get_node("CanvasLayer/LootModal")
		_loot_modal.closed.connect(func() -> void:
			action_state = ActionState.MOVEMENT
			_loot_modal.visible = false)
		_character_sheet.visible = false
		_character_sheet.init(get_node("CharacterInventory"))
		_character_sheet.close_requested.connect(func() -> void:
			_character_sheet.visible = false
			if _loot_interrupted:
				_loot_interrupted = false
				_loot_modal.visible = true
				action_state = ActionState.INTERACTION
			else:
				action_state = ActionState.MOVEMENT)

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
			if action_state != ActionState.MENU:
				if action_state == ActionState.INTERACTION:
					_loot_interrupted = true
					_loot_modal.visible = false
				action_state = ActionState.MENU
				_character_sheet.visible = true
			elif _character_sheet._inventory_state == _character_sheet.InventoryState.ITEM_ACTION:
				pass
			elif _character_sheet._tab == _character_sheet.Tab.STATS:
				_character_sheet.close()
				_character_sheet.visible = false
			else:
				_character_sheet._set_tab(_character_sheet.Tab.STATS)
		KEY_I:
			if action_state != ActionState.MENU:
				if action_state == ActionState.INTERACTION:
					_loot_interrupted = true
					_loot_modal.visible = false
				action_state = ActionState.MENU
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
			if action_state != ActionState.MOVEMENT:
				return
			var my_pos: Vector2i = get_node("CharacterMovement").grid_pos
			var target_inventories: Array[Node] = []
			for node in get_parent().get_children():
				if node == self:
					continue
				var other_movement := node.get_node_or_null("CharacterMovement")
				if other_movement == null or other_movement.grid_pos != my_pos:
					continue
				var other_ai := node.get_node_or_null("CharacterAI")
				if other_ai == null:
					continue
				if other_ai.behavior_state == other_ai.BehaviorState.KNOCKED_OUT or other_ai.behavior_state == other_ai.BehaviorState.DEAD:
					target_inventories.append(node.get_node("CharacterInventory"))
			if not target_inventories.is_empty():
				action_state = ActionState.INTERACTION
				_loot_modal.open(target_inventories, get_node("CharacterInventory"))
				_loot_modal.visible = true
		KEY_C:
			if action_state == ActionState.MENU:
				return
			action_state = ActionState.LOOK if action_state == ActionState.MOVEMENT else ActionState.MOVEMENT
			if action_state == ActionState.LOOK:
				_look_cursor.activate()
			else:
				_look_cursor.deactivate()
