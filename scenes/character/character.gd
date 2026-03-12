extends Node3D

const OrganRegistryScript := preload("res://scenes/character/organs/character_organ_registry.gd")
const RenalScript := preload("res://scenes/character/organs/character_renal.gd")
const HypothalamusScript := preload("res://scenes/character/organs/character_hypothalamus.gd")
const CardiovascularScript := preload("res://scenes/character/organs/character_cardiovascular.gd")
const PulmonaryScript := preload("res://scenes/character/organs/character_pulmonary.gd")
const CortexScript := preload("res://scenes/character/organs/character_cortex.gd")
const CoagulationScript := preload("res://scenes/character/organs/character_coagulation.gd")

enum ActionState { MOVEMENT, LOOK, MENU, INTERACTION }
enum CharacterType { SURGEON, ENEMY, STRUCTURE }
enum CharacterRole { PLAYER, NPC }

@export var character_type: CharacterType = CharacterType.SURGEON
@export var character_role: CharacterRole = CharacterRole.PLAYER

var faction: String = ""
var action_state: ActionState = ActionState.MOVEMENT
var defeated_sprite: String = ""
var corpse_item_id: String = ""

# Traversal properties — characters always block vision and have no sound dampening.
# Structures set these from structures.json via StructureConfigurator.
var sound_dampening: int = 0
var blocks_vision: bool = true

# Structure-only fields — set by StructureConfigurator from structures.json
var structure_id: String = ""
var display_name: String = ""
var description: String = ""
var sprite_path: String = ""
var inspect_sprite_path: String = ""
var drops: Array = []
var structure_actions: Array = []

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

var renal: Node = null
var organs: Node = null
var hypothalamus: Node = null
var cardiovascular: Node = null
var pulmonary: Node = null
var cortex: Node = null
var coagulation: Node = null


func _ready() -> void:
	var scene: Node = get_parent()
	var grid_map: GridMap = scene.get_node("GridMap")
	var canvas_layer: CanvasLayer = scene.get_node("CanvasLayer")
	var camera: Camera3D = scene.get_node("Camera3D")


	# Inject scene-level refs into components that need them.
	# Components resolve siblings themselves in their own _ready(); only scene-external
	# refs are injected here so no component hardcodes scene paths.
	var occupancy_map: Node = grid_map.get_node("OccupancyMap")
	movement.setup(grid_map, scene.get_node("GameLogic/TurnOrder") if character_role == CharacterRole.PLAYER else null, occupancy_map)
	lifecycle.setup(occupancy_map)
	combat.setup(grid_map, canvas_layer, camera)
	vision.setup(grid_map, occupancy_map)

	if character_type == CharacterType.STRUCTURE:
		return
	
	
	organs = OrganRegistryScript.new()
	organs.name = "CharacterOrganRegistry"
	add_child(organs)

	renal = RenalScript.new()
	renal.name = "CharacterRenal"
	add_child(renal)
	organs.renal = renal
	renal.setup(organs)

	hypothalamus = HypothalamusScript.new()
	hypothalamus.name = "CharacterHypothalamus"
	add_child(hypothalamus)
	organs.hypothalamus = hypothalamus
	hypothalamus.setup(organs)

	cardiovascular = CardiovascularScript.new()
	cardiovascular.name = "CharacterCardiovascular"
	add_child(cardiovascular)
	organs.cardiovascular = cardiovascular
	cardiovascular.setup(organs, vitals, levels)

	pulmonary = PulmonaryScript.new()
	pulmonary.name = "CharacterPulmonary"
	add_child(pulmonary)
	organs.pulmonary = pulmonary
	pulmonary.setup(organs, levels, vitals)

	cortex = CortexScript.new()
	cortex.name = "CharacterCortex"
	add_child(cortex)
	organs.cortex = cortex
	cortex.setup(organs, vitals)

	coagulation = CoagulationScript.new()
	coagulation.name = "CharacterCoagulation"
	add_child(coagulation)
	organs.coagulation = coagulation
	coagulation.setup(organs)

	sound.setup(grid_map)
	interact_cursor.setup(grid_map)
	look_cursor.setup(grid_map, camera, canvas_layer.get_node("LookModeInfo"))

	if character_role == CharacterRole.PLAYER:
		vitals.setup(canvas_layer, camera, canvas_layer.get_node("TopBar"))
		var character_sheet: Control = canvas_layer.get_node("CharacterSheet")
		levels.setup(character_sheet, canvas_layer.get_node("TopBar"))
		inventory.setup(character_sheet)
		interaction.setup(grid_map, character_sheet, canvas_layer.get_node("LootModal"), canvas_layer.get_node("InteractModal"))
		
		inventory.add_item("combat_knife")
		inventory.add_item("field_bandage")
		inventory.add_item("field_bandage")
		inventory.add_item("field_bandage")
		inventory.add_item("aspiration_needle")
		inventory.add_item("heparin")
		inventory.add_item("tinder_box")
		inventory.add_item("logs")
	else:
		var turn_order: Node = scene.get_node("GameLogic/TurnOrder")
		ai.setup(grid_map, turn_order, canvas_layer, camera)
