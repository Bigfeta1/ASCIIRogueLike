extends Node

# Zone dimensions
const ZONE_WIDTH: int = 80
const ZONE_HEIGHT: int = 40

# BehaviorState.PATROL = 3 (matches CharacterAI enum order: RELAXED=0, SUSPICIOUS=1, SLEEPING=2, PATROL=3)
# LifeState.ALIVE = 0 (matches CharacterAI enum order: ALIVE=0, KNOCKED_OUT=1, DEAD=2)
const _BEHAVIOR_PATROL: int = 3
const _LIFE_ALIVE: int = 0

# Patrol sequence mirrored from CharacterAI
const _PATROL_SEQ: Array = [
	Vector2i(-1, 0), Vector2i(-1, 0), Vector2i(-1, 0),
	Vector2i(0,  1), Vector2i(0,  1), Vector2i(0,  1),
	Vector2i(1,  0), Vector2i(1,  0), Vector2i(1,  0),
	Vector2i(0, -1), Vector2i(0, -1), Vector2i(0, -1),
]

# zones[Vector2i] = { "tiles": { Vector2i: int }, "items": [ { "id": String, "local_pos": Vector2i } ] }
var zones: Dictionary = {}

# Zones where the full load sequence (tiles + items + enemies) has completed
var visited_zones: Dictionary = {}

# Each record: { world_pos, life_state, behavior_state, patrol_origin_world, patrol_index,
#                faction, character_type, hp, hp_max, disposition,
#                muscle, cardio, adrenal, sympathetic, parasympathetic, affect, name }
var off_screen_enemies: Array = []

var current_zone: Vector2i = Vector2i.ZERO


# --- Coordinate helpers ---

func world_to_zone(world_pos: Vector2i) -> Vector2i:
	return Vector2i(floori(world_pos.x / float(ZONE_WIDTH)), floori(world_pos.y / float(ZONE_HEIGHT)))

func world_to_local(world_pos: Vector2i) -> Vector2i:
	# posmod avoids negative-remainder issue with GDScript's % operator
	return Vector2i(posmod(world_pos.x, ZONE_WIDTH) - ZONE_WIDTH / 2,
					posmod(world_pos.y, ZONE_HEIGHT) - ZONE_HEIGHT / 2)

func local_to_world(zone_id: Vector2i, local_pos: Vector2i) -> Vector2i:
	return Vector2i(zone_id.x * ZONE_WIDTH  + (local_pos.x + ZONE_WIDTH  / 2),
					zone_id.y * ZONE_HEIGHT + (local_pos.y + ZONE_HEIGHT / 2))


# --- Zone tile persistence ---

func has_zone(zone_id: Vector2i) -> bool:
	return zones.has(zone_id)

func mark_visited(zone_id: Vector2i) -> void:
	visited_zones[zone_id] = true

func is_visited(zone_id: Vector2i) -> bool:
	return visited_zones.has(zone_id)

func save_zone_tiles(zone_id: Vector2i, grid_map: GridMap) -> void:
	var tile_dict: Dictionary = {}
	for cell in grid_map.get_used_cells():
		tile_dict[Vector2i(cell.x, cell.z)] = grid_map.get_cell_item(cell)
	if not zones.has(zone_id):
		zones[zone_id] = {"tiles": {}, "items": [], "trees": []}
	zones[zone_id]["tiles"] = tile_dict

func load_zone_tiles(zone_id: Vector2i, grid_map: GridMap) -> void:
	grid_map.clear()
	for local_pos in zones[zone_id]["tiles"]:
		grid_map.set_cell_item(Vector3i(local_pos.x, 0, local_pos.y), zones[zone_id]["tiles"][local_pos])


# --- Zone item persistence ---

func save_zone_items(zone_id: Vector2i, item_nodes: Array, grid_map: GridMap) -> void:
	var records: Array = []
	for item in item_nodes:
		var cell := grid_map.local_to_map(grid_map.to_local(item.global_position))
		records.append({"id": item.item_id, "local_pos": Vector2i(cell.x, cell.z)})
	if not zones.has(zone_id):
		zones[zone_id] = {"tiles": {}, "items": []}
	zones[zone_id]["items"] = records

func load_zone_items(zone_id: Vector2i) -> Array:
	if not zones.has(zone_id):
		return []
	return zones[zone_id].get("items", [])


# --- Zone structure persistence ---

func save_zone_structures(zone_id: Vector2i, structure_nodes: Array) -> void:
	var records: Array = []
	for s in structure_nodes:
		var vitals: Node = s.get_node_or_null("CharacterVitals")
		var inv: Node = s.get_node_or_null("CharacterInventory")
		records.append({
			"id": s.structure_id,
			"grid_pos": s.movement.grid_pos,
			"hp": vitals.hp if vitals != null else 0,
			"inventory": inv.items.duplicate() if inv != null else []
		})
	if not zones.has(zone_id):
		zones[zone_id] = {"tiles": {}, "items": [], "structures": []}
	zones[zone_id]["structures"] = records

func load_zone_structures(zone_id: Vector2i) -> Array:
	if not zones.has(zone_id):
		return []
	return zones[zone_id].get("structures", [])


# --- Enemy persistence ---

func serialize_enemy(enemy_node: Node, zone_id: Vector2i) -> Dictionary:
	var movement := enemy_node.get_node("CharacterMovement")
	var vitals := enemy_node.get_node("CharacterVitals")
	var levels := enemy_node.get_node("CharacterLevels")
	var ai := enemy_node.get_node("CharacterAI")
	var inv := enemy_node.get_node("CharacterInventory")
	var has_blood_splatter := enemy_node.get_node_or_null("BloodSplatter") != null
	# Serialize inventory: items by index with durability and container contents
	var inv_records: Array = []
	for i in inv.items.size():
		var uid: int = inv.item_uids[i]
		var record: Dictionary = {"id": inv.items[i]}
		if inv.item_durability.has(uid):
			record["durability"] = inv.item_durability[uid]
		if inv.container_contents.has(uid):
			record["contents"] = inv.container_contents[uid]
		inv_records.append(record)
	return {
		"world_pos": local_to_world(zone_id, movement.grid_pos),
		"life_state": ai.life_state,
		"behavior_state": ai.behavior_state,
		"patrol_origin_world": local_to_world(zone_id, ai._patrol_origin),
		"patrol_index": ai._patrol_index,
		"faction": enemy_node.faction,
		"character_type": enemy_node.character_type,
		"hp": vitals.hp,
		"hp_max": vitals.hp_max,
		"disposition": ai.disposition,
		"muscle": levels.muscle,
		"cardio": levels.cardio,
		"adrenal": levels.adrenal,
		"sympathetic": levels.sympathetic,
		"parasympathetic": levels.parasympathetic,
		"affect": levels.affect,
		"name": enemy_node.name,
		"display_name": enemy_node.display_name,
		"description": enemy_node.description,
		"sprite_path": enemy_node.sprite_path,
		"defeated_sprite": enemy_node.defeated_sprite,
		"corpse_item_id": enemy_node.corpse_item_id,
		"has_blood_splatter": has_blood_splatter,
		"inventory": inv_records,
		"organs": _serialize_organs(enemy_node),
	}

func _serialize_organs(enemy_node: Node) -> Dictionary:
	var d: Dictionary = {}
	var cardio: Node = enemy_node.cardiovascular
	if cardio != null:
		d["heart_rate"] = cardio.heart_rate
		d["bp_systolic"] = cardio.bp_systolic
		d["bp_diastolic"] = cardio.bp_diastolic
		d["mean_arterial_pressure"] = cardio.mean_arterial_pressure
		d["cardiac_output"] = cardio.cardiac_output
		d["stroke_volume"] = cardio.stroke_volume
		d["systemic_vascular_resistance"] = cardio.systemic_vascular_resistance
		d["demanded_co"] = cardio.demanded_co
		d["venous_return_fraction"] = cardio.venous_return_fraction
		d["spo2"] = cardio.spo2
	var pulm: Node = enemy_node.pulmonary
	if pulm != null:
		d["respiratory_rate"] = pulm.respiratory_rate
		d["tidal_volume"] = pulm.tidal_volume
		d["pao2"] = pulm.pao2
		d["paco2"] = pulm.paco2
		d["pao2_spo2"] = pulm.pao2_spo2
		d["pneumothorax"] = pulm.pneumothorax
		d["pneumothorax_side"] = pulm.pneumothorax_side
		d["pleural_pressure"] = pulm.pleural_pressure
		d["pulmonary_embolism"] = pulm.pulmonary_embolism
		d["pe_severity"] = pulm.pe_severity
		d["pe_rv_strain"] = pulm.pe_rv_strain
	var renal: Node = enemy_node.renal
	if renal != null:
		d["plasma_fluid"] = renal.plasma_fluid
		d["interstitial_fluid"] = renal.interstitial_fluid
		d["intracellular_fluid"] = renal.intracellular_fluid
	var coag: Node = enemy_node.coagulation
	if coag != null:
		d["stasis_score"] = coag.stasis_score
		d["endothelial_injury"] = coag.endothelial_injury
		d["crosslinkage"] = coag.crosslinkage
		d["heparin_active"] = coag.heparin_active
		d["embolism_triggered"] = coag.embolism_triggered
	return d

func add_off_screen_enemy(record: Dictionary) -> void:
	off_screen_enemies.append(record)

func remove_enemies_in_zone(zone_id: Vector2i) -> Array:
	var result: Array = []
	var remaining: Array = []
	for record in off_screen_enemies:
		if world_to_zone(record["world_pos"]) == zone_id:
			result.append(record)
		else:
			remaining.append(record)
	off_screen_enemies = remaining
	return result

func tick_off_screen_enemies() -> void:
	for record in off_screen_enemies:
		if record.get("life_state", _LIFE_ALIVE) != _LIFE_ALIVE:
			continue
		if record["behavior_state"] == _BEHAVIOR_PATROL:
			var idx: int = record["patrol_index"]
			record["world_pos"] = record["world_pos"] + _PATROL_SEQ[idx]
			record["patrol_index"] = (idx + 1) % _PATROL_SEQ.size()
		else:
			record["patrol_index"] = (record["patrol_index"] + 1) % _PATROL_SEQ.size()
