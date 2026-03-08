extends Node

const CHARACTER_SCENE = preload("res://scenes/character/character.tscn")
const ENEMY_DATA_PATH = "res://data/enemies.json"

const MAP_WIDTH: int = 80
const MAP_HEIGHT: int = 40

func spawn() -> void:
	var main := get_parent().get_parent()
	var grid_map: GridMap = get_parent()

	var file := FileAccess.open(ENEMY_DATA_PATH, FileAccess.READ)
	var enemy_defs: Array = JSON.parse_string(file.get_as_text())
	file.close()

	var spawn_index := 0
	for def in enemy_defs:
		var count: int = def.get("count", 1)
		for i in range(count):
			var enemy: Node = CHARACTER_SCENE.instantiate()
			enemy.name = "%s%d" % [def["id"], spawn_index]
			enemy.character_type = enemy.CharacterType.ENEMY
			enemy.character_role = enemy.CharacterRole.NPC
			enemy.faction = def.get("faction", "")

			var vitals := enemy.get_node("CharacterVitals")
			var hp: int = def.get("hp", 10)
			vitals.hp = hp
			vitals.hp_max = hp

			var levels := enemy.get_node("CharacterLevels")
			var stats: Dictionary = def.get("stats", {})
			if stats.has("muscle"): levels.muscle = stats["muscle"]
			if stats.has("cardio"): levels.cardio = stats["cardio"]
			if stats.has("adrenal"): levels.adrenal = stats["adrenal"]
			if stats.has("sympathetic"): levels.sympathetic = stats["sympathetic"]
			if stats.has("parasympathetic"): levels.parasympathetic = stats["parasympathetic"]
			if stats.has("affect"): levels.affect = stats["affect"]

			enemy.get_node("CharacterAI").disposition = enemy.get_node("CharacterAI").Disposition.HOSTILE
			main.add_child(enemy)
			enemy.get_node("CharacterMovement").place(_random_walkable_cell(grid_map))
			enemy.get_node("CharacterAI").start_patrol()
			spawn_index += 1

func _random_walkable_cell(grid_map: GridMap) -> Vector2i:
	var x_min := -(MAP_WIDTH / 2)
	var x_max := MAP_WIDTH / 2 - 1
	var z_min := -(MAP_HEIGHT / 2)
	var z_max := MAP_HEIGHT / 2 - 1
	while true:
		var x := randi_range(x_min, x_max)
		var z := randi_range(z_min, z_max)
		var cell := Vector3i(x, 0, z)
		var tile := TileRegistry.get_original_tile(cell, grid_map.get_cell_item(cell))
		if TileRegistry.is_walkable(tile):
			return Vector2i(x, z)
	return Vector2i.ZERO
