extends Label

const DURATION := 0.8

var _camera: Camera3D
var _world_pos: Vector3
var _elapsed: float = 0.0


func setup(world_pos: Vector3, camera: Camera3D, label_text: String = "?", label_color: Color = Color(1.0, 0.85, 0.2)) -> void:
	text = label_text
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	custom_minimum_size.x = 120.0
	add_theme_color_override("font_color", label_color)
	_world_pos = world_pos
	_camera = camera


func _process(delta: float) -> void:
	_elapsed += delta
	var t := _elapsed / DURATION
	var zoom := _camera.size
	var font_size := int(remap(zoom, 60.0, 230.0, 96, 48))
	add_theme_font_size_override("font_size", font_size)
	var base_offset := remap(zoom, 60.0, 230.0, 120.0, 60.0)
	var float_range := remap(zoom, 60.0, 230.0, 80.0, 40.0)
	var screen_pos := _camera.unproject_position(_world_pos)
	position = screen_pos + Vector2(-custom_minimum_size.x / 2.0, -base_offset - t * float_range)
	modulate.a = 1.0 - t
	if _elapsed >= DURATION:
		queue_free()
