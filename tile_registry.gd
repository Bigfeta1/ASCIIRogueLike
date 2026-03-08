extends Node

const SOUND_TILE: int = 2
const LOS_TILE: int = 4

var _tiles: Dictionary = {}

# Key: Vector3i cell, Value: [original_tile_id, ref_count]
var _sound_originals: Dictionary = {}

# Key: Vector3i cell, Value: original_tile_id
var _vision_originals: Dictionary = {}

func _ready() -> void:
	var file := FileAccess.open("res://data/tiles.json", FileAccess.READ)
	_tiles = JSON.parse_string(file.get_as_text())
	file.close()

func get_tile(id: int) -> Dictionary:
	return _tiles.get(str(id), {})

func is_walkable(id: int) -> bool:
	return _tiles.get(str(id), {}).get("walkable", false)

func blocks_vision(id: int) -> bool:
	return _tiles.get(str(id), {}).get("blocks_vision", false)

func get_sound_dampening(id: int) -> int:
	return _tiles.get(str(id), {}).get("sound_dampening", 0)

func get_tile_id(name: String) -> int:
	for key in _tiles:
		if _tiles[key].get("name") == name:
			return int(key)
	return -1

func get_original_tile(cell: Vector3i, current_tile: int) -> int:
	if _sound_originals.has(cell):
		return _sound_originals[cell][0]
	if _vision_originals.has(cell):
		return _vision_originals[cell]
	return current_tile

func sound_claim(cell: Vector3i, current_tile: int) -> void:
	if _sound_originals.has(cell):
		_sound_originals[cell][1] += 1
	else:
		_sound_originals[cell] = [get_original_tile(cell, current_tile), 1]

func sound_release(cell: Vector3i, grid_map: GridMap) -> void:
	if not _sound_originals.has(cell):
		return
	_sound_originals[cell][1] -= 1
	if _sound_originals[cell][1] <= 0:
		var restore: int = _sound_originals[cell][0]
		_sound_originals.erase(cell)
		# if vision still owns this cell, restore to LOS tile not the underlying tile
		grid_map.set_cell_item(cell, LOS_TILE if _vision_originals.has(cell) else restore)

func vision_claim(cell: Vector3i, current_tile: int) -> void:
	if not _vision_originals.has(cell):
		_vision_originals[cell] = get_original_tile(cell, current_tile)

func vision_release(cell: Vector3i, grid_map: GridMap) -> void:
	if not _vision_originals.has(cell):
		return
	var restore: int = _vision_originals[cell]
	_vision_originals.erase(cell)
	# if sound still owns this cell, restore to sound tile not the underlying tile
	grid_map.set_cell_item(cell, SOUND_TILE if _sound_originals.has(cell) else restore)

func clear_state() -> void:
	_sound_originals.clear()
	_vision_originals.clear()
