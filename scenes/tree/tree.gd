extends Node3D

var grid_pos: Vector2i = Vector2i.ZERO
var hp: int = 100
var block_mod: int = 5

var _grid_map: GridMap

func _ready() -> void:
	add_to_group("trees")
	_grid_map = get_parent().get_node("GridMap")

func place(pos: Vector2i) -> void:
	grid_pos = pos
	var local := _grid_map.map_to_local(Vector3i(pos.x, 0, pos.y))
	var world := _grid_map.to_global(local)
	position.x = world.x
	position.z = world.z

func take_damage(amount: int, _attacker: Node) -> void:
	hp = maxi(0, hp - amount)
	if hp <= 0:
		_grid_map.set_cell_item(Vector3i(grid_pos.x, 0, grid_pos.y), TileRegistry.get_tile_id("Floor"))
		queue_free()
