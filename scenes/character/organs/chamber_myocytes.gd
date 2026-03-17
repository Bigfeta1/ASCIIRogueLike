class_name ChamberMyocytes
extends Node

signal region_depolarized(region: int)
signal systole_started
signal diastole_started

## Name shown in the debugger to identify which chamber these myocytes belong to.
@export var debug_name: String = ""

## Which part of the electrical system triggers this myocyte sweep. Atrial = AtrialComponents.depolarized. Ventricular = ventricular_depolarization_started.
@export_enum("atrial", "ventricular") var electrical_source: int = 0
## If false, this myocyte group will not connect to the electrical system — useful for isolated testing.
@export var connected: bool = true

## Number of fascicles (muscle bundles) in this chamber. Each fascicle activates sequentially during the sweep.
@export var fascicle_count: int       = 1
## Number of myocyte regions per fascicle. Total region count = fascicle_count × regions_per_fascicle.
@export var regions_per_fascicle: int = 3
## Total time (seconds) for the depolarization wave to sweep across all fascicles.
@export var sweep_duration: float     = 0.08
## Duration (seconds) of each action potential phase per myocyte: [Phase0, Phase1, Phase2, Phase3, Phase4(idle)]. Phase4 duration is ignored — myocytes stay idle until the next sweep.
@export var myocyte_durations: Array[float] = [0.002, 0.005, 0.073, 0.060, 0.0]
## Contractile force contribution of each action potential phase: [Phase0, Phase1, Phase2, Phase3, Phase4]. Summed across all active regions to compute total active force.
@export var myocyte_force: Array[float]     = [0.15,  0.50,  1.00,  0.20,  0.0]

var region_count: int  = 3
var in_systole:   bool = false
var active_force: float = 0.0   # read by CardiacChamber each tick for elastance

var sweep_active:        bool  = false
var sweep_fascicle_index: int  = 0
var sweep_region_index:  int  = 0
var sweep_timer:         float = 0.0

var _regions: Array        = []
var _prev_in_systole: bool = false

func _ready() -> void:
	region_count = fascicle_count * regions_per_fascicle
	_regions.clear()
	
	for i in region_count:
		_regions.append({ "myocyte": 4, "myocyte_timer": 0.0, "mechanical": 0 })

	if connected:
		var es: Node = get_node("../../../HeartElectricalSystem")
		if electrical_source == 0:
			var atrial: Node = es.get_node("AtrialComponents")
			atrial.depolarized.connect(trigger_sweep)
		else:
			var ventricular: Node = es.get_node("Ventricularcomponents")
			ventricular.ventricular_depolarization_started.connect(trigger_sweep)

#Triggered by atrial.depolarized or ventricular_depolarization_started triggeres
func trigger_sweep() -> void:
	sweep_active          = true
	sweep_fascicle_index  = 0
	sweep_region_index    = 0
	sweep_timer           = 0.0
	for i in region_count:
		_regions[i]["myocyte"]       = 4
		_regions[i]["myocyte_timer"] = 0.0
		_regions[i]["mechanical"]    = 0

#region STEP FUNCTIONS
func step_chamber(delta: float):
	step_myocytes(delta)
	
	if sweep_active:
		step_sweep(delta)

func step_sweep(delta: float) -> void:
	var time_per_fascicle: float = sweep_duration / float(fascicle_count)
	var time_per_region: float   = time_per_fascicle / float(regions_per_fascicle)

	sweep_timer += delta

	while sweep_active:
		if sweep_timer < time_per_region:
			break
		
		sweep_timer -= time_per_region
		var idx: int = sweep_fascicle_index * regions_per_fascicle + sweep_region_index
		
		_regions[idx]["myocyte"]       = 0
		_regions[idx]["myocyte_timer"] = 0.0
		_regions[idx]["mechanical"]    = 1
		
		region_depolarized.emit(idx)
		sweep_region_index += 1
		
		if sweep_region_index >= regions_per_fascicle:
			sweep_region_index = 0
			sweep_fascicle_index += 1
			if sweep_fascicle_index >= fascicle_count:
				sweep_active = false


func step_myocytes(delta: float) -> void:
	active_force = 0.0

	for i in region_count:
		var r: Dictionary = _regions[i]
		var phase: int = r["myocyte"]

		if phase == 4:
			continue

		r["myocyte_timer"] += delta
		active_force       += myocyte_force[phase]

		var dur: float = myocyte_durations[phase]

		if dur > 0.0 and r["myocyte_timer"] >= dur:
			var overflow: float = r["myocyte_timer"] - dur
			if phase < 3:
				r["myocyte"]       = phase + 1
				r["myocyte_timer"] = overflow
			else:
				r["myocyte"]       = 4
				r["myocyte_timer"] = 0.0
				r["mechanical"]    = 0
	
	_update_systole_state()

func _update_systole_state() -> void:
	var any_contracting: bool = false
	for i in region_count:
		if _regions[i]["mechanical"] == 1:
			any_contracting = true
			break
	in_systole = any_contracting
	if in_systole and not _prev_in_systole:
		systole_started.emit()
	elif not in_systole and _prev_in_systole:
		diastole_started.emit()
	_prev_in_systole = in_systole
#endregion
