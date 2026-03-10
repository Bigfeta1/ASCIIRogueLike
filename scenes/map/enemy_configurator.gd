extends Node

const CHARACTER_SCENE = preload("res://scenes/character/character.tscn")
const ENEMY_DATA_PATH = "res://data/enemies.json"

const MAP_WIDTH: int = 80
const MAP_HEIGHT: int = 40

func spawn(zone_id: Vector2i = Vector2i.ZERO) -> void:
	var main := get_parent().get_parent()
	var grid_map: GridMap = get_parent()

	# Restore enemies that were in this zone when the player last left
	var returning: Array = WorldState.remove_enemies_in_zone(zone_id)
	for record in returning:
		var enemy: Node = CHARACTER_SCENE.instantiate()
		enemy.name = record["name"]
		enemy.character_type = record["character_type"]
		enemy.character_role = enemy.CharacterRole.NPC
		enemy.faction = record["faction"]
		enemy.defeated_sprite = record.get("defeated_sprite", "")
		enemy.corpse_item_id = record.get("corpse_item_id", "")
		enemy.display_name = record.get("display_name", "")
		enemy.description = record.get("description", "")
		enemy.sprite_path = record.get("sprite_path", "")

		var vitals := enemy.get_node("CharacterVitals")
		vitals.hp = record["hp"]
		vitals.hp_max = record["hp_max"]

		var levels := enemy.get_node("CharacterLevels")
		levels.muscle = record["muscle"]
		levels.cardio = record["cardio"]
		levels.adrenal = record["adrenal"]
		levels.sympathetic = record["sympathetic"]
		levels.parasympathetic = record["parasympathetic"]
		levels.affect = record["affect"]

		# add_child triggers CharacterAI._ready, so AI state is set after
		main.add_child(enemy)
		var local_pos := WorldState.world_to_local(record["world_pos"])
		enemy.get_node("CharacterMovement").place(local_pos, zone_id)
		var ai := enemy.get_node("CharacterAI")
		ai.disposition = record["disposition"]
		ai._patrol_index = record["patrol_index"]
		ai._patrol_origin = WorldState.world_to_local(record["patrol_origin_world"])

		ai.behavior_state = record["behavior_state"]
		var saved_life_state: int = record.get("life_state", ai.LifeState.ALIVE)
		var lifecycle := enemy.get_node("CharacterLifecycle")
		lifecycle.restore_incapacitated(enemy, saved_life_state)
		if saved_life_state != ai.LifeState.ALIVE:
			enemy.get_node("CharacterSprite").set_defeated(enemy.defeated_sprite)
			if not record.get("has_blood_splatter", false):
				# set_defeated always spawns a splatter; remove it if the original didn't have one
				var splatter := enemy.get_node_or_null("BloodSplatter")
				if splatter != null:
					splatter.queue_free()

		# Restore inventory directly, bypassing weight checks
		var inv := enemy.get_node("CharacterInventory")
		for inv_record in record.get("inventory", []):
			var id: String = inv_record["id"]
			var uid: int = inv._next_uid
			inv.items.append(id)
			inv.item_uids.append(uid)
			inv._next_uid += 1
			if inv_record.has("durability"):
				inv.item_durability[uid] = inv_record["durability"]
			if inv_record.has("contents"):
				inv.container_contents[uid] = inv_record["contents"]

	# Only spawn fresh enemies if this zone has not been fully loaded before
	if WorldState.is_visited(zone_id):
		return

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

			enemy.defeated_sprite = def.get("defeated_sprite", "") as String
			enemy.corpse_item_id = def.get("corpse_item_id", "") as String
			enemy.display_name = def.get("name", def["id"]) as String
			enemy.description = def.get("description", "") as String
			enemy.sprite_path = def.get("sprite", "") as String
			enemy.get_node("CharacterAI").disposition = enemy.get_node("CharacterAI").Disposition.HOSTILE
			main.add_child(enemy)
			enemy.get_node("CharacterMovement").place(_random_walkable_cell(grid_map), zone_id)
			enemy.get_node("CharacterAI").start_patrol()
			var inventory_items := enemy.get_node("CharacterInventory")
			for item_id in def.get("inventory_items", []):
				inventory_items.add_item(item_id)
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
