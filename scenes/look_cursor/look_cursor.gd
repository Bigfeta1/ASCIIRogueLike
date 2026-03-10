extends MeshInstance3D
class_name LookCursor

var _grid_map: GridMap
var _camera: Camera3D
var _tile_label: Label
var _tile_label2: Label
var _disposition_label: Label
var _status_label: Label
var _cursor_grid_pos: Vector2i = Vector2i.ZERO

var _movement: Node
var _tracked_character: Node = null

func _ready() -> void:
	_movement = get_parent().get_node("CharacterMovement")
	visible = false

func setup(grid_map: GridMap, camera: Camera3D, look_mode_info: Control) -> void:
	_grid_map = grid_map
	_camera = camera
	_tile_label = look_mode_info.get_node("Label")
	_tile_label2 = look_mode_info.get_node("Label2")
	_disposition_label = look_mode_info.get_node("DispositionLabel")
	_status_label = look_mode_info.get_node("StatusLabel")
	_tile_label.visible = false
	_tile_label2.visible = false
	_disposition_label.visible = false
	_status_label.visible = false

func _process(_delta: float) -> void:
	if not visible:
		return
	var screen_pos := _camera.unproject_position(global_position)
	var offset: Vector2
	match _camera.size:
		230.0: offset = Vector2(40.0, -25.0)
		145.0: offset = Vector2(60.0, -35.0)
		_:     offset = Vector2(100.0, -75.0)
	_tile_label.global_position = screen_pos + offset
	_tile_label2.global_position = screen_pos + offset + Vector2(0.0, 26.0)
	_disposition_label.global_position = screen_pos + offset + Vector2(0.0, 47.0)
	_status_label.global_position = screen_pos + offset + Vector2(0.0, 59.0)
	_refresh_character_status()

func activate() -> void:
	_cursor_grid_pos = _movement.grid_pos
	visible = true
	_tile_label.visible = true
	_update_tile_label()

func activate_at(pos: Vector2i) -> void:
	_cursor_grid_pos = pos
	var local := _grid_map.map_to_local(Vector3i(pos.x, 0, pos.y))
	var world := _grid_map.to_global(local)
	global_position.x = world.x
	global_position.z = world.z
	visible = true
	_tile_label.visible = true
	_update_tile_label()
	for node in get_parent().get_parent().get_children():
		var ai := node.get_node_or_null("CharacterAI")
		if ai != null and node.character_role == node.CharacterRole.NPC:
			ai._check_vision()

func deactivate() -> void:
	visible = false
	_tile_label.visible = false
	_tile_label2.visible = false
	_disposition_label.visible = false
	_status_label.visible = false
	position = Vector3(0.043, 0.0, 0.013)

func move(delta: Vector2i) -> void:
	var target := _cursor_grid_pos + delta
	if _grid_map.get_cell_item(Vector3i(target.x, 0, target.y)) == GridMap.INVALID_CELL_ITEM:
		return
	_cursor_grid_pos = target
	var local := _grid_map.map_to_local(Vector3i(_cursor_grid_pos.x, 0, _cursor_grid_pos.y))
	var world := _grid_map.to_global(local)
	global_position.x = world.x
	global_position.z = world.z
	_update_tile_label()

func _update_tile_label() -> void:
	var tile_id := _grid_map.get_cell_item(Vector3i(_cursor_grid_pos.x, 0, _cursor_grid_pos.y))
	var tile := TileRegistry.get_tile(tile_id)
	_tile_label.text = tile.get("name", "")

	_tracked_character = null
	for node in get_parent().get_parent().get_children():
		var movement := node.get_node_or_null("CharacterMovement")
		if movement != null and movement.grid_pos == _cursor_grid_pos:
			_tracked_character = node
			break

	if _tracked_character != null:
		_tile_label2.text = _tracked_character.name
		_tile_label2.visible = true
	else:
		_tile_label2.visible = false
		_disposition_label.visible = false
		_status_label.visible = false

func _refresh_character_status() -> void:
	if _tracked_character == null:
		return
	var movement := _tracked_character.get_node_or_null("CharacterMovement")
	if movement == null or movement.grid_pos != _cursor_grid_pos:
		_update_tile_label()
		return
	var ai := _tracked_character.get_node_or_null("CharacterAI")
	if ai == null or _tracked_character.character_role != _tracked_character.CharacterRole.NPC:
		_disposition_label.visible = false
		_status_label.visible = false
		return
	match ai.disposition:
		ai.Disposition.FRIENDLY:
			_disposition_label.text = "Friendly"
			_disposition_label.modulate = Color.GREEN
		ai.Disposition.NEUTRAL:
			_disposition_label.text = "Neutral"
			_disposition_label.modulate = Color.WHITE
		ai.Disposition.HOSTILE:
			_disposition_label.text = "Hostile"
			_disposition_label.modulate = Color.RED
	_disposition_label.visible = true
	const LIFE_LABELS := {
		1: "Knocked Out",
		2: "Dead",
	}
	const BEHAVIOR_LABELS := {
		0: "Relaxed",
		1: "Suspicious",
		2: "Sleeping",
		3: "Patrolling",
		4: "Combat",
		5: "Investigating",
		6: "Alert",
		7: "Returning",
	}
	if ai.life_state != ai.LifeState.ALIVE:
		_status_label.text = LIFE_LABELS.get(ai.life_state, "")
	else:
		_status_label.text = BEHAVIOR_LABELS.get(ai.behavior_state, "")
	_status_label.visible = true
