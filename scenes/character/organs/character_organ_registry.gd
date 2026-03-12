extends Node

# Central reference point for all organ subsystem nodes.
# Populated by character._ready() after dynamic instantiation.
# Other systems read organs through here rather than reaching into character.gd directly.

var renal: Node = null
var hypothalamus: Node = null
var cardiovascular: Node = null
var pulmonary: Node = null
var cortex: Node = null
var coagulation: Node = null
