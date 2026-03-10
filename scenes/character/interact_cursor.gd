extends MeshInstance3D

var _grid_map: GridMap
var _movement: Node
var _cursor_grid_pos: Vector2i = Vector2i.ZERO

func _ready() -> void:
	_movement = get_parent().get_node("CharacterMovement")
	visible = false

func setup(grid_map: GridMap) -> void:
	_grid_map = grid_map

func activate() -> void:
	_cursor_grid_pos = _movement.grid_pos
	_snap()
	visible = true

func activate_at(pos: Vector2i) -> void:
	_cursor_grid_pos = pos
	_snap()
	visible = true

func deactivate() -> void:
	visible = false

func move(delta: Vector2i) -> void:
	var target := _cursor_grid_pos + delta
	var origin: Vector2i = _movement.grid_pos
	var dist := maxi(absi(target.x - origin.x), absi(target.y - origin.y))
	if dist > 1:
		return
	if _grid_map.get_cell_item(Vector3i(target.x, 0, target.y)) == GridMap.INVALID_CELL_ITEM:
		return
	_cursor_grid_pos = target
	_snap()

func get_grid_pos() -> Vector2i:
	return _cursor_grid_pos

func _snap() -> void:
	var local := _grid_map.map_to_local(Vector3i(_cursor_grid_pos.x, 0, _cursor_grid_pos.y))
	var world := _grid_map.to_global(local)
	global_position.x = world.x
	global_position.z = world.z
