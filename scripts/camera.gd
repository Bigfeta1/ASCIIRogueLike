extends Camera3D

const ZOOM_LEVELS = [230.0, 110.0, 60.0]
const FOV_LEVELS = [168.0, 160.0, 120.0, 100.0]
const PERSPECTIVE_Z = 22.19
var zoom_index := 0

var _character: Node3D
var _origin_transform: Transform3D


func _ready() -> void:
	_character = get_parent().get_node("Character")
	position.z = PERSPECTIVE_Z if projection == PROJECTION_PERSPECTIVE else 0.0
	_origin_transform = transform
	_apply_zoom()


func _process(_delta: float) -> void:
	if zoom_index > 0 and is_instance_valid(_character):
		position.x = _character.position.x
		position.z = _character.position.z


func _input(event: InputEvent) -> void:
	if _character.action_state == _character.ActionState.MENU:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_index = min(zoom_index + 1, FOV_LEVELS.size() - 1)
			_apply_zoom()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_index = max(zoom_index - 1, 0)
			_apply_zoom()
			if zoom_index == 0:
				transform = _origin_transform
				position.z = PERSPECTIVE_Z


func _apply_zoom() -> void:
	if zoom_index <= 1:
		projection = PROJECTION_PERSPECTIVE
		fov = FOV_LEVELS[zoom_index]
		position.z = PERSPECTIVE_Z
	else:
		projection = PROJECTION_ORTHOGONAL
		size = ZOOM_LEVELS[zoom_index - 1]
		position.z = 0.0
