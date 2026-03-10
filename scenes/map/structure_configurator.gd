extends Node

const CHARACTER_SCENE = preload("res://scenes/character/character.tscn")
const STRUCTURES_DATA_PATH = "res://data/structures.json"

const MAP_WIDTH: int = 80
const MAP_HEIGHT: int = 40

var _defs: Dictionary = {}  # id -> definition dict
var _grid_map: GridMap


func _ready() -> void:
	_grid_map = get_parent()
	var file := FileAccess.open(STRUCTURES_DATA_PATH, FileAccess.READ)
	var records: Array = JSON.parse_string(file.get_as_text())
	file.close()
	for record in records:
		_defs[record["id"]] = record


func spawn_one(id: String, pos: Vector2i, hp_override: int = -1, inventory_override: Array = []) -> Node:
	var def: Dictionary = _defs.get(id, {})
	if def.is_empty():
		return null
	var main := _grid_map.get_parent()
	var entity: Node = CHARACTER_SCENE.instantiate()
	entity.character_type = entity.CharacterType.STRUCTURE
	entity.character_role = entity.CharacterRole.NPC
	entity.structure_id = id
	entity.display_name = def.get("name", id)
	entity.description = def.get("description", "")
	entity.sprite_path = def.get("sprite", "")
	entity.inspect_sprite_path = def.get("inspect_sprite", entity.sprite_path)
	entity.sound_dampening = def.get("sound_dampening", 0)
	entity.blocks_vision = def.get("blocks_vision", false)
	entity.drops = def.get("drops", [])
	entity.structure_actions = def.get("actions", [])
	main.add_child(entity)
	entity.name = def.get("name", id)
	entity.add_to_group("structures")
	entity.get_node("CharacterSprite").set_texture(def.get("sprite", ""))
	var vitals := entity.get_node("CharacterVitals")
	var hp: int = hp_override if hp_override >= 0 else def.get("hp", 10)
	vitals.hp = hp
	vitals.hp_max = def.get("hp", 10)
	var levels := entity.get_node("CharacterLevels")
	levels.muscle = def.get("muscle", 10)
	entity.get_node("CharacterMovement").place(pos)
	var inventory := entity.get_node("CharacterInventory")
	var contents: Array = inventory_override if not inventory_override.is_empty() else def.get("contents", [])
	for item_id in contents:
		inventory.add_item(item_id)
	if id == "campfire":
		_attach_fire_particles(entity)
	return entity


func _attach_fire_particles(entity: Node) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "FireParticles"
	particles.amount = 48
	particles.lifetime = 1.2
	particles.explosiveness = 0.0
	particles.randomness = 0.5
	particles.fixed_fps = 12
	particles.position = Vector3(0.0, 0.05, 0.0)

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.3
	mat.direction = Vector3(0, 0, -1)
	mat.spread = 18.0
	mat.initial_velocity_min = 1.2
	mat.initial_velocity_max = 2.2
	mat.gravity = Vector3(0, 0, 0)
	mat.damping_min = 1.0
	mat.damping_max = 2.0
	mat.scale_min = 0.45
	mat.scale_max = 0.75
	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(1.0, 0.6, 0.05, 1.0))
	color_ramp.set_color(1, Color(0.8, 0.1, 0.0, 0.0))
	var color_tex := GradientTexture1D.new()
	color_tex.gradient = color_ramp
	mat.color_ramp = color_tex
	particles.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.55)
	particles.draw_pass_1 = quad

	var draw_mat := StandardMaterial3D.new()
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.albedo_color = Color.WHITE
	quad.surface_set_material(0, draw_mat)

	entity.add_child(particles)


func scatter_chests(home_interiors: Array) -> void:
	for interior in home_interiors:
		if randf() < 0.5:
			var cell: Vector2i = interior.pick_random()
			spawn_one("military_chest", cell)


func scatter_trees(home_rects: Array) -> void:
	var x_left := -(MAP_WIDTH / 2)
	var x_right := MAP_WIDTH / 2
	var z_top := -(MAP_HEIGHT / 2)
	var z_bottom := MAP_HEIGHT / 2
	var floor_cells: Array[Vector3i] = []
	var tile_floor: int = TileRegistry.get_tile_id("Floor")
	for x in range(x_left, x_right):
		for z in range(z_top, z_bottom):
			var cell := Vector3i(x, 0, z)
			if _grid_map.get_cell_item(cell) != tile_floor:
				continue
			var in_house := false
			for rect in home_rects:
				if rect.has_point(Vector2i(x, z)):
					in_house = true
					break
			if not in_house:
				floor_cells.append(cell)
	floor_cells.shuffle()
	var tree_count := randi_range(15, 60)
	for i in range(mini(tree_count, floor_cells.size())):
		var cell := floor_cells[i]
		spawn_one("tree", Vector2i(cell.x, cell.z))
