class_name AtrialComponents
extends Node

signal depolarized   # atria fully activated — VentricularComponents listens to this

@onready var _sa_node:      Node = get_node("SAnode")
@onready var _atrial_tract: Node = get_node("AtrialTract")

@export var debug_name: String = ""

func _ready() -> void:
	_sa_node.fired.connect(func() -> void:
		_atrial_tract.activate()
	)
	_atrial_tract.conducted.connect(func() -> void: depolarized.emit())

func tick(delta: float) -> void:
	_sa_node.tick(delta)
	_atrial_tract.tick(delta)
