extends Node

signal attack_finished

enum BumpState { IDLE, LUNGE, RETURN }

const DamageLabelScript := preload("res://scenes/character/damage_label.gd")

const LUNGE_DURATION := 0.12
const RETURN_DURATION := 0.10
const LUNGE_FRACTION := 0.45

var bump_state: BumpState = BumpState.IDLE

var _character: Node
var _grid_map: GridMap
var _origin_world: Vector3
var _target_world: Vector3
var _elapsed: float = 0.0


func _ready() -> void:
	_character = get_parent()
	_grid_map = _character.get_parent().get_node("GridMap")
	set_process(false)


func bump_attack(target_grid_pos: Vector2i) -> void:
	if bump_state != BumpState.IDLE:
		return
	var movement := _character.get_node("CharacterMovement")
	var origin_local := _grid_map.map_to_local(Vector3i(movement.grid_pos.x, 0, movement.grid_pos.y))
	var target_local := _grid_map.map_to_local(Vector3i(target_grid_pos.x, 0, target_grid_pos.y))
	_origin_world = _grid_map.to_global(origin_local)
	_target_world = _grid_map.to_global(target_local)
	_elapsed = 0.0
	bump_state = BumpState.LUNGE
	set_process(true)


func _process(delta: float) -> void:
	match bump_state:
		BumpState.LUNGE:
			_elapsed += delta
			var t := minf(_elapsed / LUNGE_DURATION, 1.0)
			var lunge_pos := _origin_world.lerp(_target_world, t * LUNGE_FRACTION)
			_character.position.x = lunge_pos.x
			_character.position.z = lunge_pos.z
			if t >= 1.0:
				bump_state = BumpState.RETURN
				_elapsed = 0.0

		BumpState.RETURN:
			_elapsed += delta
			var t := minf(_elapsed / RETURN_DURATION, 1.0)
			var lunge_end := _origin_world.lerp(_target_world, LUNGE_FRACTION)
			var ret_pos := lunge_end.lerp(_origin_world, t)
			_character.position.x = ret_pos.x
			_character.position.z = ret_pos.z
			if t >= 1.0:
				_character.position.x = _origin_world.x
				_character.position.z = _origin_world.z
				bump_state = BumpState.IDLE
				set_process(false)
				attack_finished.emit()


func _apply_damage(target: Node) -> void:
	var vitals := target.get_node_or_null("CharacterVitals")
	if vitals == null:
		return
	var attacker_levels := _character.get_node("CharacterLevels")
	var defender_levels := target.get_node("CharacterLevels")

	# Hit roll
	var hit_roll: int = randi_range(1, 20) + attacker_levels.hit_mod()
	var evasion: int = 10 + defender_levels.hit_mod()
	if hit_roll < evasion:
		_spawn_miss_label(target)
		return

	# Parry — defender needs 18+ (d20 + parry_mod vs fixed 18 + attacker parry_mod)
	var parry_roll: int = randi_range(1, 20) + defender_levels.parry_mod()
	if parry_roll >= 19 + attacker_levels.parry_mod():
		_spawn_label(target, "Parry!", Color.CYAN)
		var attacker_vitals := _character.get_node_or_null("CharacterVitals")
		if attacker_vitals != null:
			attacker_vitals.hp = maxi(0, attacker_vitals.hp - 1)
			if _character.character_role == _character.CharacterRole.PLAYER:
				attacker_vitals._refresh_ui()
		return

	# Dodge — needs 18+ (d20 + dodge_mod vs fixed 18)
	var dodge_roll: int = randi_range(1, 20) + defender_levels.dodge_mod()
	if dodge_roll >= 19:
		var adrenal_contribution: int = defender_levels.stat_mod(defender_levels.adrenal)
		if adrenal_contribution > 0:
			vitals.stat_debt["adrenal"] = vitals.stat_debt.get("adrenal", 0) + adrenal_contribution
		_spawn_label(target, "Dodge!", Color.GREEN)
		return

	# Crit check
	var muscle_mod: int = attacker_levels.stat_mod(attacker_levels.muscle)
	var affect_mod: int = attacker_levels.stat_mod(attacker_levels.affect)
	var crit_chance: float = 0.05 + affect_mod * 0.025
	var is_crit: bool = randf() < crit_chance
	var damage: int
	if is_crit:
		var crit_mod: int = floori((attacker_levels.stat_mod(attacker_levels.adrenal) + muscle_mod + attacker_levels.stat_mod(attacker_levels.sympathetic)) / 3.0)
		damage = 3 + crit_mod
	else:
		damage = maxi(1, randi_range(1, 3) + muscle_mod)

	# Block — needs 18+ (d20 + block_mod vs fixed 18), then rolls d6 reduction
	var block_check: int = randi_range(1, 20) + defender_levels.block_mod()
	if block_check >= 19:
		var block_roll: int = randi_range(1, 6) + defender_levels.block_mod()
		damage = maxi(1, damage - block_roll)

	vitals.hp = maxi(0, vitals.hp - damage)
	if is_crit:
		_spawn_crit_label(target, damage)
	else:
		_spawn_damage_label(target, damage)
	if target.character_role == target.CharacterRole.PLAYER:
		vitals._refresh_ui()
	if vitals.hp <= 0:
		if _character.character_role == _character.CharacterRole.PLAYER:
			_character.get_node("CharacterLevels").add_xp(10)
		target.queue_free()


func _spawn_label(target: Node, text: String, color: Color) -> void:
	var label: Label = DamageLabelScript.new()
	_character.get_parent().get_node("CanvasLayer").add_child(label)
	label.setup(text, color, target.position, _character.get_parent().get_node("Camera3D"))


func _spawn_damage_label(target: Node, amount: int) -> void:
	_spawn_label(target, "-%dHP" % amount, Color.RED)


func _spawn_crit_label(target: Node, amount: int) -> void:
	_spawn_label(target, "CRIT -%dHP" % amount, Color(1.0, 0.84, 0.0))


func _spawn_miss_label(target: Node) -> void:
	_spawn_label(target, "Miss!", Color.GRAY)
