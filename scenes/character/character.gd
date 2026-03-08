extends Node3D

enum ActionState { MOVEMENT, LOOK, MENU }
enum CharacterType { SURGEON, ENEMY }
enum CharacterRole { PLAYER, NPC }

@export var character_type: CharacterType = CharacterType.SURGEON
@export var character_role: CharacterRole = CharacterRole.PLAYER

var faction: String = ""
var action_state: ActionState = ActionState.MOVEMENT

var _look_cursor: Node
var _character_sheet: Control

func _ready() -> void:
	_look_cursor = get_node("LookCursor")
	if character_role == CharacterRole.PLAYER:
		_character_sheet = get_parent().get_node("CanvasLayer/CharacterSheet")
		_character_sheet.visible = false
		_character_sheet.init(get_node("CharacterInventory"))
		_character_sheet.close_requested.connect(func() -> void:
			action_state = ActionState.MOVEMENT
			_character_sheet.visible = false)

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
				action_state = ActionState.MENU
				_character_sheet.visible = true
			elif _character_sheet._inventory_state == _character_sheet.InventoryState.ITEM_ACTION:
				pass
			elif _character_sheet._tab == _character_sheet.Tab.STATS:
				action_state = ActionState.MOVEMENT
				_character_sheet.close()
				_character_sheet.visible = false
			else:
				_character_sheet._set_tab(_character_sheet.Tab.STATS)
		KEY_I:
			if action_state != ActionState.MENU:
				action_state = ActionState.MENU
				_character_sheet.visible = true
				_character_sheet._set_tab(_character_sheet.Tab.INVENTORY)
			elif _character_sheet._inventory_state == _character_sheet.InventoryState.ITEM_ACTION:
				pass
			elif _character_sheet._tab == _character_sheet.Tab.INVENTORY:
				action_state = ActionState.MOVEMENT
				_character_sheet.close()
				_character_sheet.visible = false
			else:
				_character_sheet._set_tab(_character_sheet.Tab.INVENTORY)
		KEY_C:
			if action_state == ActionState.MENU:
				return
			action_state = ActionState.LOOK if action_state == ActionState.MOVEMENT else ActionState.MOVEMENT
			if action_state == ActionState.LOOK:
				_look_cursor.activate()
			else:
				_look_cursor.deactivate()
