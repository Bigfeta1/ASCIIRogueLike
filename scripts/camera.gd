extends Camera3D

const ZOOM_LEVELS = [230.0, 145.0, 60.0]
var zoom_index := 0

var _character: Node3D
var _origin_transform: Transform3D

func _ready() -> void:
	size = ZOOM_LEVELS[zoom_index]
	_origin_transform = transform
	_character = get_parent().get_node("Character")

func _process(_delta: float) -> void:
	if zoom_index > 0 and is_instance_valid(_character):
		position.x = _character.position.x
		position.z = _character.position.z

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_index = min(zoom_index + 1, ZOOM_LEVELS.size() - 1)
			size = ZOOM_LEVELS[zoom_index]
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_index = max(zoom_index - 1, 0)
			size = ZOOM_LEVELS[zoom_index]
			if zoom_index == 0:
				transform = _origin_transform
