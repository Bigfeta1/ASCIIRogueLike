class_name ConductionComponent
extends Node

signal conducted   # fires when conduction duration elapses

## Name shown in the debugger to identify this conduction component (e.g. "AV Node", "Bundle of His").
@export var debug_name: String = ""
## Time (seconds) from activation until the conducted signal fires and passes to the next component.
@export var conduction_duration: float = 0.05

var conducting: bool = false
var _timer: float    = 0.0

func activate() -> void:
	conducting = true
	_timer     = 0.0

func tick(delta: float) -> void:
	if not conducting:
		return
	_timer += delta
	if _timer >= conduction_duration:
		conducting = false
		_timer     = 0.0
		conducted.emit()
