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
		character.CharacterType.STRUCTURE:
			pass  # texture set later via set_texture() from StructureConfigurator


func set_texture(path: String) -> void:
	var mat := material_override as StandardMaterial3D
	if mat == null or path == "":
		return
	mat.albedo_texture = load(path)

func set_defeated(sprite_path: String) -> void:
	print("[SPRITE] set_defeated path='%s'" % sprite_path)
	if sprite_path == "":
		print("[SPRITE] empty path, returning")
		return
	var mat := material_override as StandardMaterial3D
	print("[SPRITE] material_override=%s mat=%s" % [str(material_override), str(mat)])
	if mat == null:
		print("[SPRITE] mat is null!")
		return
	var tex := load(sprite_path)
	print("[SPRITE] loaded tex=%s" % str(tex))
	mat.albedo_texture = tex
	print("[SPRITE] texture set. current albedo_texture=%s" % str(mat.albedo_texture))
	position = Vector3.ZERO
	rotation = Vector3.ZERO
	var splatter := MeshInstance3D.new()
	splatter.name = "BloodSplatter"
	var plane := PlaneMesh.new()
	splatter.mesh = plane
	var splatter_mat := StandardMaterial3D.new()
	splatter_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	splatter_mat.albedo_texture = load("res://assets/images/world_items/enemy_defeated/spr_blood_splatter.png")
	splatter.material_override = splatter_mat
	splatter.position = Vector3(0.0, 0.0, 0.0)
	get_parent().add_child(splatter)


func face(facing_state: int, facing_right_value: int) -> void:
	if facing_state == facing_right_value:
		scale.x = abs(scale.x)
	else:
		scale.x = -abs(scale.x)
