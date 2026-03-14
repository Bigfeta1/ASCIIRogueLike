class_name CardiacChamber
extends RefCounted

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SIGNALS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

signal region_depolarized(region: int)
signal systole_started
signal diastole_started

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CONFIGURATION — set before calling init_regions()
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Sweep structure
var fascicle_count: int       = 1   # 1 for atria, 3 for ventricles
var regions_per_fascicle: int = 3   # always 3
var sweep_duration: float     = 0.08  # total seconds to traverse all fascicles

# Myocyte action potential — 5 values, index = phase 0..4
# Phase 4 duration = 0.0 (resting, no timer)
var myocyte_durations: Array[float] = [0.002, 0.005, 0.073, 0.060, 0.0]
var myocyte_force: Array[float]     = [0.15,  0.50,  1.00,  0.20,  0.0]

# Time-varying elastance
var e_min: float        = 0.20   # mmHg/mL — passive diastolic
var e_max: float        = 0.60   # mmHg/mL — peak systolic
var e_rise_rate: float  = 5.0    # /s — elastance rise driven by active force
var e_decay_rate: float = 3.0    # /s — elastance decay during relaxation

# Volume
var v0: float          = 4.0    # mL — dead volume (pressure = 0 at this volume)
var initial_volume: float = 35.0

# Outflow valve — coordinator sets valve_open; chamber exposes it for reads
var valve_open: bool         = false
var valve_conductance: float = 0.0

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# RUNTIME STATE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

var region_count: int = 3        # derived in init_regions(): fascicle_count * regions_per_fascicle

var volume: float    = 0.0
var elastance: float = 0.0
var pressure: float  = 0.0

var in_systole: bool       = false
var _prev_in_systole: bool = false

# Sweep
var sweep_active: bool         = false
var sweep_fascicle_index: int  = 0
var sweep_timer: float         = 0.0

# Regions — Array of Dicts:
#   "myocyte":       int  0..4  (myocyte phase)
#   "myocyte_timer": float
#   "mechanical":    int  0=RELAXATION  1=CONTRACTION
var _regions: Array = []

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# INIT
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func init_regions() -> void:
	region_count = fascicle_count * regions_per_fascicle
	
	_regions.clear()
	
	for i in region_count:
		_regions.append({ "myocyte": 4, "myocyte_timer": 0.0, "mechanical": 0 })
	
	volume    = initial_volume
	elastance = e_min
	pressure  = elastance * maxf(0.0, volume - v0)


#region ELECTRICAL SWEEP

func trigger_sweep() -> void:
	sweep_active         = true
	sweep_fascicle_index = 0
	sweep_timer          = 0.0
	for i in region_count:
		_regions[i]["myocyte"]       = 4
		_regions[i]["myocyte_timer"] = 0.0
		_regions[i]["mechanical"]    = 0

func step_sweep(delta: float) -> void:
	if not sweep_active:
		return
		
	var time_per_fascicle: float = sweep_duration / float(fascicle_count)
	
	sweep_timer += delta
	
	while sweep_timer >= time_per_fascicle and sweep_fascicle_index < fascicle_count:
			
		#decrement sweep timer -> updateregion as contrating
		sweep_timer -= time_per_fascicle
		
		var base: int = sweep_fascicle_index * regions_per_fascicle
		
		for r in regions_per_fascicle:
			
			var idx: int = base + r
			_regions[idx]["myocyte"]       = 0   # PHASE_0
			_regions[idx]["myocyte_timer"] = 0.0
			_regions[idx]["mechanical"]    = 1   # CONTRACTION
			region_depolarized.emit(idx)
			
		sweep_fascicle_index += 1
	
	# Deactivate Sweep
	if sweep_fascicle_index >= fascicle_count:
		sweep_active = false

#endregion

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# MYOCYTE STEPPING
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Advances each region's action potential. Returns summed active force across
# all regions this tick — coordinator uses this for volume transfer calculations.
func step_myocytes(delta: float) -> float:
	var total_force: float = 0.0
	for i in region_count:
		var r: Dictionary = _regions[i]
		var phase: int = r["myocyte"]
		if phase == 4:
			continue
		r["myocyte_timer"] += delta
		total_force += myocyte_force[phase]
		var dur: float = myocyte_durations[phase]
		if dur > 0.0 and r["myocyte_timer"] >= dur:
			r["myocyte_timer"] = 0.0
			if phase < 3:
				r["myocyte"] = phase + 1
			else:
				r["myocyte"]    = 4
				r["mechanical"] = 0  # RELAXATION
	_update_systole_state()
	return total_force

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

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ELASTANCE + PRESSURE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Drives elastance from regional myocyte state, then derives pressure.
# Call after step_myocytes() so mechanical states are current.
func step_elastance(delta: float) -> void:
	var active_force: float = 0.0
	for i in region_count:
		var r: Dictionary = _regions[i]
		if r["mechanical"] == 1:
			active_force += myocyte_force[r["myocyte"]]

	var normalized_force: float = active_force / float(region_count)

	if normalized_force > 0.0:
		elastance = minf(e_max, elastance + normalized_force * e_rise_rate * delta)
	else:
		elastance = maxf(e_min, elastance - e_decay_rate * delta)

	pressure = elastance * maxf(0.0, volume - v0)
