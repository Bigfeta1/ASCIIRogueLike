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

	# Weapon and armor weight class matchup → hit penalty
	var attacker_equip := _character.get_node_or_null("CharacterEquipment")
	var defender_equip := target.get_node_or_null("CharacterEquipment")
	var weapon: Dictionary = attacker_equip.weapon_info() if attacker_equip else {"damage_die": 3, "weight_class": "light"}
	var defender_armor_class: String = defender_equip.armor_weight_class() if defender_equip else "light"
	const WEIGHT_ORDER: Array = ["light", "medium", "heavy"]
	var w_idx: int = WEIGHT_ORDER.find(weapon.weight_class)
	var a_idx: int = WEIGHT_ORDER.find(defender_armor_class)
	var mismatch: int = w_idx - a_idx  # positive = weapon heavier than armor, negative = lighter
	var hit_penalty: int = 0
	if mismatch == 1 or mismatch == -1:
		hit_penalty = 4
	elif mismatch >= 2 or mismatch <= -2:
		hit_penalty = 8

	# Hit roll
	var hit_roll: int = randi_range(1, 20) + attacker_levels.hit_mod() + weapon.hit_bonus - hit_penalty
	var evasion: int = 10 + defender_levels.hit_mod()
	if hit_roll < evasion:
		_spawn_miss_label(target)
		return

	# Damage roll (simultaneous crit check)
	var muscle_mod: int = attacker_levels.stat_mod(attacker_levels.muscle)
	var affect_mod: int = attacker_levels.stat_mod(attacker_levels.affect)
	var damage_die: int = weapon.damage_die
	var crit_chance: float = 0.05 + affect_mod * 0.025
	var is_crit: bool = randf() < crit_chance
	var damage: int
	if is_crit:
		var crit_mod: int = floori((attacker_levels.stat_mod(attacker_levels.adrenal) + muscle_mod + attacker_levels.stat_mod(attacker_levels.sympathetic)) / 3.0)
		damage = damage_die + crit_mod
	else:
		damage = maxi(1, randi_range(1, damage_die) + muscle_mod)

	# Determine available defenses based on attacker weapon class vs defender armor class
	# w_idx: 0=light, 1=medium, 2=heavy — a_idx same
	const DEFENSE_TABLE: Array = [
		# defender: light,              medium,            heavy
		[["parry","dodge","block"], ["parry","block"],  ["block"]        ], # attacker: light
		[["parry","dodge"],         ["parry","dodge","block"], ["parry","block"]], # attacker: medium
		[["dodge"],                 ["parry","dodge"],  ["parry","dodge","block"]], # attacker: heavy
	]
	var available_defenses: Array = DEFENSE_TABLE[w_idx][a_idx]

	print("[COMBAT] %s -> %s | atk:%s die:d%d armor:%s | penalty:-%d | defenses:%s" % [
		_character.name, target.name,
		weapon.weight_class, weapon.damage_die,
		defender_armor_class, hit_penalty,
		str(available_defenses)
	])

	# Parry
	if "parry" in available_defenses:
		var parry_roll: int = randi_range(1, 20) + defender_levels.parry_mod()
		if parry_roll >= 19 + attacker_levels.parry_mod():
			_spawn_label(target, "Parry!", Color.CYAN)
			var attacker_vitals := _character.get_node_or_null("CharacterVitals")
			if attacker_vitals != null:
				attacker_vitals.hp = maxi(0, attacker_vitals.hp - 1)
				if _character.character_role == _character.CharacterRole.PLAYER:
					attacker_vitals._refresh_ui()
			return

	# Dodge
	if "dodge" in available_defenses:
		var dodge_roll: int = randi_range(1, 20) + defender_levels.dodge_mod()
		if dodge_roll >= 19:
			var adrenal_contribution: int = defender_levels.stat_mod(defender_levels.adrenal)
			if adrenal_contribution > 0:
				vitals.stat_debt["adrenal"] = vitals.stat_debt.get("adrenal", 0) + adrenal_contribution
			_spawn_label(target, "Dodge!", Color.GREEN)
			return

	# Block
	if "block" in available_defenses:
		var block_check: int = randi_range(1, 20) + defender_levels.block_mod()
		if block_check >= 19:
			var block_roll: int = randi_range(1, 6) + defender_levels.block_mod()
			damage = maxi(1, damage - block_roll)

	var attacker_equip_node := _character.get_node_or_null("CharacterEquipment")
	if attacker_equip_node != null:
		var weapon_slot := "r_hand"
		var cur_dur: int = attacker_equip_node.get_equipped_durability(weapon_slot)
		if cur_dur != -1:
			attacker_equip_node.set_equipped_durability(weapon_slot, cur_dur - 2)
	vitals.hp = maxi(0, vitals.hp - damage)
	if is_crit:
		_spawn_crit_label(target, damage)
	else:
		_spawn_damage_label(target, damage)
	if target.character_role == target.CharacterRole.PLAYER:
		vitals._refresh_ui()
	print("[DEATH] %s hp=%d" % [target.name, vitals.hp])
	if vitals.hp <= 0:
		print("[DEATH] incapacitating %s" % target.name)
		if _character.character_role == _character.CharacterRole.PLAYER:
			_character.get_node("CharacterLevels").add_xp(10)
		_incapacitate(target, target.get_node("CharacterAI").BehaviorState.DEAD)


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


func _incapacitate(target: Node, state: int) -> void:
	var ai := target.get_node_or_null("CharacterAI")
	print("[INCAP] ai=%s state=%d" % [str(ai), state])
	if ai == null:
		return
	ai.behavior_state = state
	print("[INCAP] behavior_state set to %d on %s" % [ai.behavior_state, target.name])
	ai._clear_vision_tiles()
	ai.set_process(false)
	target.get_node("CharacterMovement").set_process(false)
	target.get_node("CharacterCombat").set_process(false)
	if target.corpse_item_id != "":
		target.get_node("CharacterInventory").add_item(target.corpse_item_id)
	print("[INCAP] calling set_defeated on %s with sprite='%s'" % [target.name, target.defeated_sprite])
	target.get_node("CharacterSprite").set_defeated(target.defeated_sprite)
