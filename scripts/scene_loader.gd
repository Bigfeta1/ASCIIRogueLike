extends Node

signal map_generated
signal items_placed
signal characters_spawned
signal load_complete

var _main: Node
var _grid_map: GridMap
var _map_generator: Node
var _item_configurator: Node
var _enemy_configurator: Node

func _ready() -> void:
	await get_tree().process_frame
	var main := get_tree().root.get_node_or_null("MainScene")
	if main:
		load_game(main)

func load_game(main: Node) -> void:
	_main = main
	_grid_map = main.get_node("GridMap")
	_map_generator = _grid_map.get_node("MapGenerator")
	_item_configurator = _grid_map.get_node("ItemConfigurator")
	_enemy_configurator = _grid_map.get_node("EnemyConfigurator")

	_map_generator.generate()
	map_generated.emit()

	await _item_configurator.place()
	items_placed.emit()

	await _spawn_characters()
	characters_spawned.emit()

	load_complete.emit()

func _spawn_characters() -> void:
	var player := _main.get_node("Character")
	player.get_node("CharacterMovement").place(Vector2i(0, 0))
	await _enemy_configurator.spawn()
