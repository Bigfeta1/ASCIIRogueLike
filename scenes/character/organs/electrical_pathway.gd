class_name ElectricalPathway
extends Node

signal ventricular_depolarization_started

@onready var _av:      ConductionComponent = get_node("AVnode")
@onready var _his:     ConductionComponent = get_node("BundleOfHis")
@onready var _purkinje: ConductionComponent = get_node("PurkinjeFibers")

@export var debug_name: String = ""

func _ready() -> void:
	var atrial: Node = get_parent().get_node("AtrialComponents")
	atrial.depolarized.connect(func() -> void: _av.activate())
	_av.conducted.connect(func() -> void: _his.activate())
	_his.conducted.connect(func() -> void: _purkinje.activate())
	_purkinje.conducted.connect(func() -> void: ventricular_depolarization_started.emit())

func tick(delta: float) -> void:
	_av.tick(delta)
	_his.tick(delta)
	_purkinje.tick(delta)
