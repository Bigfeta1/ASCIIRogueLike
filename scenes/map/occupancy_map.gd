extends Node

# OccupancyMap tracks what occupies each grid cell.
#
# Solid occupants (alive characters, trees) block movement and vision.
# Only one solid occupant is allowed per cell — the game already prevents two alive
# entities from sharing a tile.
#
# Passable occupants (KO/dead enemies, world items) do not block movement or vision.
# Multiple passable occupants may share a cell (e.g. player looting on a corpse tile).
#
# Registration is the responsibility of each entity:
#   - CharacterMovement: registers/moves solid on place() and successful move
#   - CharacterLifecycle: moves character from solid to passable on KO/death
#   - tree.gd: registers solid on place(), unregisters before queue_free()

var _solid: Dictionary = {}     # Vector2i -> Node
var _passable: Dictionary = {}  # Vector2i -> Array[Node]


func register_solid(pos: Vector2i, node: Node) -> void:
	_solid[pos] = node


func unregister_solid(pos: Vector2i, node: Node) -> void:
	if _solid.get(pos) == node:
		_solid.erase(pos)


func move_solid(from: Vector2i, to: Vector2i, node: Node) -> void:
	if _solid.get(from) == node:
		_solid.erase(from)
	_solid[to] = node


func register_passable(pos: Vector2i, node: Node) -> void:
	if not _passable.has(pos):
		_passable[pos] = []
	_passable[pos].append(node)


func unregister_passable(pos: Vector2i, node: Node) -> void:
	if not _passable.has(pos):
		return
	_passable[pos].erase(node)
	if _passable[pos].is_empty():
		_passable.erase(pos)


func is_solid(pos: Vector2i) -> bool:
	return _solid.has(pos)


func get_solid(pos: Vector2i) -> Node:
	return _solid.get(pos, null)


func get_passable(pos: Vector2i) -> Array:
	return _passable.get(pos, [])


func clear() -> void:
	_solid.clear()
	_passable.clear()
