extends Node

const MAP_WIDTH: int = 80
const MAP_HEIGHT: int = 40

var TILE_FLOOR: int
var TILE_WATER: int
var TILE_WALL: int

var grid_map: GridMap
var _lake_origins: Array[Vector2] = []
var _lake_sizes: Array[Vector2] = []
var home_interiors: Array[Array] = []

func generate() -> void:
	grid_map = get_parent()
	initialize_tiles()
	grid_map.clear()
	_lake_origins.clear()
	_lake_sizes.clear()
	home_interiors.clear()
	create_floor()
	for i in range(4):
		create_lake()
	for i in range(7):
		create_home()
	_apply_lake_shader()


func initialize_tiles() -> void:
	TILE_FLOOR = TileRegistry.get_tile_id("Floor")
	TILE_WATER = TileRegistry.get_tile_id("Water")
	TILE_WALL = TileRegistry.get_tile_id("Wall")

func create_floor():
	var x_left = 0 - (MAP_WIDTH / 2)
	var x_right = MAP_WIDTH / 2

	var z_top = 0 - (MAP_HEIGHT/2)
	var z_bottom = MAP_HEIGHT/2

	var tile = TILE_FLOOR

	for x in range(x_left, x_right):
		for z in range (z_top, z_bottom):
			grid_map.set_cell_item(Vector3i(x, 0, z), tile)

func create_lake():
	var lake_width := randi_range(3, 7)
	var lake_height := randi_range(4, 8)
	create_structure(generate_lake_pattern(lake_width, lake_height), lake_width, lake_height)

func create_home():
	var home_width := randi_range(5, 9)
	var home_height := randi_range(5, 9)
	var result := generate_home_pattern(home_width, home_height)
	var origin := create_structure(result.pattern, home_width, home_height)
	var door: Vector2i = result.door
	var corners := [
		Vector2i(1, 1),
		Vector2i(1, home_height - 2),
		Vector2i(home_width - 2, 1),
		Vector2i(home_width - 2, home_height - 2),
	]
	corners.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_squared_to(door) > b.distance_squared_to(door)
	)
	var interior: Array = [origin + corners[0], origin + corners[1]]
	home_interiors.append(interior)


#region PATTERNS

func generate_lake_pattern(width: int, height: int) -> Array:
	var pattern := []
	for x in range(width):
		var row := []
		for z in range(height):
			row.append(TILE_WATER)
		pattern.append(row)
	return pattern

func generate_home_pattern(width: int, height: int) -> Dictionary:
	var pattern := []
	for x in range(width):
		var row := []
		for z in range(height):
			if x == 0 or x == width - 1 or z == 0 or z == height - 1:
				row.append(TILE_WALL)
			else:
				row.append(TILE_FLOOR)
		pattern.append(row)

	var door_candidates := []
	for x in range(1, width - 1):
		door_candidates.append(Vector2i(x, 0))
		door_candidates.append(Vector2i(x, height - 1))
	for z in range(1, height - 1):
		door_candidates.append(Vector2i(0, z))
		door_candidates.append(Vector2i(width - 1, z))

	var door: Vector2i = door_candidates.pick_random()
	pattern[door.x][door.y] = TILE_FLOOR

	return {"pattern": pattern, "door": door}

#endregion

#region CREATE STRUCTURE

func create_structure(pattern: Array, width: int, height: int) -> Vector2i:
	var origin := create_random_origin_for_structure(width, height)
	place_structure(origin.x, origin.y, pattern)

	if pattern[0][0] == TILE_WATER:
		var grid_cell_size := grid_map.cell_size.x
		var grid_origin := grid_map.global_position
		_lake_origins.append(Vector2(origin.x * grid_cell_size + grid_origin.x, origin.y * grid_cell_size + grid_origin.z))
		_lake_sizes.append(Vector2(width * grid_cell_size, height * grid_cell_size))

	return origin

func _apply_lake_shader() -> void:
	var mat: ShaderMaterial = grid_map.mesh_library.get_item_mesh(TILE_WATER).surface_get_material(0)
	mat.set_shader_parameter("lake_count", _lake_origins.size())
	mat.set_shader_parameter("lake_origins", _lake_origins)
	mat.set_shader_parameter("lake_sizes", _lake_sizes)

func create_random_origin_for_structure(width: int, height: int) -> Vector2i:
	var usable_x_left := 0 - (MAP_WIDTH / 2)
	var usable_x_right := (MAP_WIDTH / 2) - width
	var usable_z_top := 0 - (MAP_HEIGHT / 2)
	var usable_z_bottom := (MAP_HEIGHT / 2) - height

	var origin := Vector2i(randi_range(usable_x_left, usable_x_right), randi_range(usable_z_top, usable_z_bottom))
	while not is_area_clear(origin, width, height):
		origin = Vector2i(randi_range(usable_x_left, usable_x_right), randi_range(usable_z_top, usable_z_bottom))
	return origin

func is_area_clear(origin: Vector2i, width: int, height: int) -> bool:
	for x in range(origin.x, origin.x + width):
		for z in range(origin.y, origin.y + height):
			if grid_map.get_cell_item(Vector3i(x, 0, z)) != TILE_FLOOR:
				return false
	return true

func place_structure(structure_x_origin: int, structure_z_origin: int, pattern: Array):
	for x in range(pattern.size()):
		for z in range(pattern[x].size()):
			grid_map.set_cell_item(Vector3i(structure_x_origin + x, 0, structure_z_origin + z), pattern[x][z])

#endregion
