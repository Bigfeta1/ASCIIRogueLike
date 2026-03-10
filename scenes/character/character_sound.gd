extends Node

const SOUND_TILE = 2
const WAVE_INTERVAL = 0.05
const RADIUS = 5

var _grid_map: GridMap
var _character: Node
var _movement: Node
var _occupancy_map: Node

var _waves: Array = []
var _timer: Timer

func _ready() -> void:
	_character = get_parent()
	_timer = Timer.new()

func setup(grid_map: GridMap) -> void:
	_grid_map = grid_map
	_occupancy_map = grid_map.get_node("OccupancyMap")
	_movement = _character.get_node("CharacterMovement")
	_timer.one_shot = false
	_timer.wait_time = WAVE_INTERVAL
	add_child(_timer)
	_timer.timeout.connect(_on_wave_tick)
	_movement.moved.connect(_on_character_moved)

func _on_character_moved() -> void:
	var origin: Vector2i = _movement.grid_pos
	var result := _build_rings(origin)
	var wave := { "rings": result.rings, "intensities": result.intensities, "step": 0, "origin": origin }
	_apply_ring(wave)
	wave.step += 1
	_waves.append(wave)
	if not _timer.is_stopped():
		return
	_timer.start()

func _build_rings(origin: Vector2i) -> Dictionary:
	var rings: Array = []
	var intensities: Dictionary = {}
	for i in range(RADIUS + 1):
		rings.append([])

	var origin_cell := Vector3i(origin.x, 0, origin.y)
	var remaining: Dictionary = {}
	remaining[origin_cell] = RADIUS

	var queue: Array = [origin_cell]
	var cardinal_dirs := [Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,0,1), Vector3i(0,0,-1)]

	while queue.size() > 0:
		var current: Vector3i = queue.pop_front()
		var cur_remaining: int = remaining[current]

		for dir in cardinal_dirs:
			var neighbour: Vector3i = current + dir

			if _grid_map.get_cell_item(neighbour) == GridMap.INVALID_CELL_ITEM:
				continue

			var true_tile := TileRegistry.get_original_tile(neighbour, _grid_map.get_cell_item(neighbour))
			var extra_dampening := TileRegistry.get_sound_dampening(true_tile)
			var neighbour_pos := Vector2i(neighbour.x, neighbour.z)
			var solid: Node = _occupancy_map.get_solid(neighbour_pos)
			if solid != null:
				extra_dampening += solid.sound_dampening
			var n_remaining := cur_remaining - 1 - extra_dampening

			if remaining.get(neighbour, -INF) >= n_remaining:
				continue
			remaining[neighbour] = n_remaining

			var manhattan := absi(neighbour.x - origin_cell.x) + absi(neighbour.z - origin_cell.z)
			if manhattan > RADIUS:
				continue

			if extra_dampening == 0 and n_remaining >= 0:
				rings[manhattan].append(neighbour)
				intensities[neighbour] = n_remaining

			if n_remaining > 0:
				queue.append(neighbour)

	return { "rings": rings, "intensities": intensities }

func _apply_ring(wave: Dictionary) -> void:
	for cell in wave.rings[wave.step]:
		TileRegistry.sound_claim(cell, _grid_map.get_cell_item(cell))
		_grid_map.set_cell_item(cell, SOUND_TILE)
		_alert_npc_at(cell, wave.intensities.get(cell, 0), wave.origin)

func _alert_npc_at(cell: Vector3i, intensity: int, origin: Vector2i) -> void:
	var cell_pos := Vector2i(cell.x, cell.z)
	var occupant: Node = _occupancy_map.get_solid(cell_pos)
	if occupant == null or occupant == _character:
		return
	var ai: Node = occupant.get_node_or_null("CharacterAI")
	if ai == null:
		return
	if ai.disposition == ai.Disposition.HOSTILE and ai.life_state == ai.LifeState.ALIVE and ai.behavior_state != ai.BehaviorState.COMBAT:
		ai.hear_sound(intensity, origin)

func _restore_ring(wave: Dictionary, r: int) -> void:
	for cell in wave.rings[r]:
		TileRegistry.sound_release(cell, _grid_map)

func _exit_tree() -> void:
	_timer.stop()
	for wave in _waves:
		for r in range(wave.step):
			_restore_ring(wave, r)
	_waves.clear()

func _on_wave_tick() -> void:
	for wave in _waves.duplicate():
		_restore_ring(wave, wave.step - 1)
		if wave.step <= RADIUS:
			_apply_ring(wave)
			wave.step += 1
		else:
			_waves.erase(wave)
	if _waves.is_empty():
		_timer.stop()
