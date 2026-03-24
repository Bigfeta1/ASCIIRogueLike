extends Node

signal moved
signal waited
signal zone_exit(direction: Vector2i)

var grid_pos: Vector2i = Vector2i.ZERO
var zone: Vector2i = Vector2i.ZERO
var facing_state: int  # CharacterSprite.FacingState

var _character: Node
var _sprite: Node
var _grid_map: GridMap
var _look_cursor: Node
var _interact_cursor: Node
var _turn_order: Node
var _occupancy_map: Node



func _ready() -> void:
	_character = get_parent()
	_sprite = _character.get_node("CharacterSprite")
	_look_cursor = _character.get_node("LookCursor")
	_interact_cursor = _character.get_node("InteractCursor")
	facing_state = _sprite.FacingState.RIGHT

func setup(grid_map: GridMap, turn_order: Node, occupancy_map: Node) -> void:
	_grid_map = grid_map
	_turn_order = turn_order
	_occupancy_map = occupancy_map
	_snap()


func move_look_cursor(delta: Vector2i) -> void:
	_look_cursor.move(delta)


func move_interaction_cursor(delta: Vector2i) -> void:
	if _character.interaction.interaction_sub_state == _character.interaction.InteractionSubState.MOVE_CURSOR:
		if _character.interaction.pending_action != "":
			_check_move(delta)
		else:
			_interact_cursor.move(delta)
	elif _character.interaction.interaction_sub_state == _character.interaction.InteractionSubState.DROPPING_ITEM:
		_interact_cursor.move(delta)
	elif _character.interaction.interaction_sub_state == _character.interaction.InteractionSubState.PLACE_CAMPFIRE:
		_interact_cursor.move(delta)


func _check_move(delta: Vector2i) -> void:
	var target := grid_pos + delta
	var cell := Vector3i(target.x, 0, target.y)
	var tile_id := _grid_map.get_cell_item(cell)
	
	if tile_id == GridMap.INVALID_CELL_ITEM:
		if _character.character_role == _character.CharacterRole.PLAYER:
			zone_exit.emit(delta)
		return
	
	var true_tile := TileRegistry.get_original_tile(cell, tile_id)
	if not TileRegistry.is_walkable(true_tile):
		return
	
	var occupant: Node = _occupancy_map.get_solid(target)
	if occupant != null:
		if occupant.character_type == occupant.CharacterType.STRUCTURE:
			# Structure — requires pending_target lock to attack
			if _character.interaction.pending_target == occupant and _character.action_state == _character.ActionState.MOVEMENT:
				_face(delta)
				var combat := _character.get_node_or_null("CharacterCombat")
				if combat != null:
					combat.bump_attack(target)
					combat._apply_damage(occupant)
				if _character.organs.autonomic != null:
					_character.organs.autonomic.notify_activity(0.672)
				moved.emit()
			return
		
		# Alive character — check for combat or block
		var other_ai := occupant.get_node_or_null("CharacterAI")
		var different_faction: bool = occupant.faction != _character.faction
		
		if other_ai != null and other_ai.disposition == other_ai.Disposition.HOSTILE and different_faction:
			occupant.get_node("CharacterLifecycle").enter_combat(occupant)
			_face(delta)
			var combat := _character.get_node_or_null("CharacterCombat")
			if combat != null:
				combat._apply_damage(occupant)
				combat.bump_attack(target)
			if _character.organs.autonomic != null:
				_character.organs.autonomic.notify_activity(0.803)
			moved.emit()
		return
	
	_occupancy_map.move_solid(grid_pos, target, _character)
	grid_pos = target
	
	
	if _character.organs.autonomic != null:
		_character.organs.autonomic.notify_activity(0.115)

	moved.emit()
	
	_face(delta)
	_snap()


func _face(delta: Vector2i) -> void:
	if delta.x > 0:
		facing_state = _sprite.FacingState.RIGHT
		_sprite.face(facing_state, _sprite.FacingState.RIGHT)
	elif delta.x < 0:
		facing_state = _sprite.FacingState.LEFT
		_sprite.face(facing_state, _sprite.FacingState.RIGHT)

func set_look_mode(enabled: bool) -> void:
	if enabled:
		_look_cursor.activate(grid_pos)
	else:
		_look_cursor.deactivate()

func step(delta: Vector2i) -> void:
	_check_move(delta)

func place(pos: Vector2i, new_zone: Vector2i = Vector2i.ZERO) -> void:
	_occupancy_map.register_solid(pos, _character)
	grid_pos = pos
	zone = new_zone
	_snap()

func _snap() -> void:
	var local := _grid_map.map_to_local(Vector3i(grid_pos.x, 0, grid_pos.y))
	var world := _grid_map.to_global(local)
	_character.position.x = world.x
	_character.position.y = 0.01
	_character.position.z = world.z

func _world_to_grid(world: Vector3) -> Vector2i:
	var cell := _grid_map.local_to_map(_grid_map.to_local(world))
	return Vector2i(cell.x, cell.z)
