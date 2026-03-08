extends MeshInstance3D

enum FacingState { LEFT, RIGHT }

@export var texture_surgeon: Texture2D
@export var texture_enemy_soldier: Texture2D

func _ready() -> void:
	var character := get_parent()
	var mat := (material_override as StandardMaterial3D).duplicate()
	material_override = mat
	match character.character_type:
		character.CharacterType.SURGEON:
			if texture_surgeon:
				mat.albedo_texture = texture_surgeon
		character.CharacterType.ENEMY:
			if texture_enemy_soldier:
				mat.albedo_texture = texture_enemy_soldier

func face(facing_state: int, facing_right_value: int) -> void:
	if facing_state == facing_right_value:
		scale.x = abs(scale.x)
	else:
		scale.x = -abs(scale.x)
