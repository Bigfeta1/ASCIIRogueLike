extends Node3D

enum ActionState { MOVEMENT, LOOK, MENU, INTERACTION }
enum CharacterType { SURGEON, ENEMY }
enum CharacterRole { PLAYER, NPC }

@export var character_type: CharacterType = CharacterType.SURGEON
@export var character_role: CharacterRole = CharacterRole.PLAYER

var faction: String = ""
var action_state: ActionState = ActionState.MOVEMENT
var defeated_sprite: String = ""
var corpse_item_id: String = ""

# Component references — the single place to resolve siblings.
# All other nodes access components through these rather than get_node() by name.
@onready var ai: Node = get_node("CharacterAI")
@onready var actions: Node = get_node("CharacterActions")
@onready var combat: Node = get_node("CharacterCombat")
@onready var equipment: Node = get_node("CharacterEquipment")
@onready var interaction: Node = get_node("CharacterInteraction")
@onready var inventory: Node = get_node("CharacterInventory")
@onready var levels: Node = get_node("CharacterLevels")
@onready var lifecycle: Node = get_node("CharacterLifecycle")
@onready var movement: Node = get_node("CharacterMovement")
@onready var sound: Node = get_node("CharacterSound")
@onready var sprite: Node = get_node("CharacterSprite")
@onready var vision: Node = get_node("CharacterVision")
@onready var vitals: Node = get_node("CharacterVitals")
@onready var look_cursor: Node = get_node("LookCursor")
@onready var interact_cursor: Node = get_node("InteractCursor")


func _ready() -> void:
	if character_role == CharacterRole.PLAYER:
		inventory.add_item("combat_knife")
		inventory.add_item("field_bandage")
		inventory.add_item("field_bandage")
		inventory.add_item("field_bandage")
