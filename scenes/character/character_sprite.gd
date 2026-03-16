extends MeshInstance3D

enum FacingState { LEFT, RIGHT }

@export var texture_surgeon: Texture2D
@export var texture_enemy_soldier: Texture2D

func _process(_delta: float) -> void:
	sorting_offset = get_parent().position.z


func _ready() -> void:
	var character := get_parent()
	var mat := (material_override as StandardMaterial3D).duplicate()
	material_override = mat
	var tex: Texture2D = null
	match character.character_type:
		character.CharacterType.SURGEON:
			tex = texture_surgeon
		character.CharacterType.ENEMY:
			tex = texture_enemy_soldier
		character.CharacterType.STRUCTURE:
			pass  # texture set later via set_texture() from StructureConfigurator
	if tex != null:
		mat.albedo_texture = tex
		if tex.get_width() > 0:
			var aspect: float = float(tex.get_height()) / float(tex.get_width())
			(mesh as PlaneMesh).size = Vector2(2.0, 2.0 * aspect)


func set_texture(path: String) -> void:
	var mat := material_override as StandardMaterial3D
	if mat == null or path == "":
		return
	var tex := load(path) as Texture2D
	mat.albedo_texture = tex
	if tex != null and tex.get_width() > 0:
		var aspect: float = float(tex.get_height()) / float(tex.get_width())
		(mesh as PlaneMesh).size = Vector2(2.0, 2.0 * aspect)

func set_defeated(sprite_path: String) -> void:
	if sprite_path == "":
		return
	var mat := material_override as StandardMaterial3D
	if mat == null:
		return
	var tex := load(sprite_path)
	mat.albedo_texture = tex
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
	splatter.position = Vector3(0.0, -0.01, 0.0)
	splatter.sorting_offset = -1.0
	get_parent().add_child(splatter)


func face(facing_state: int, facing_right_value: int) -> void:
	if facing_state == facing_right_value:
		scale.x = abs(scale.x)
	else:
		scale.x = -abs(scale.x)
