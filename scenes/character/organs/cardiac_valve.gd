class_name CardiacValve
extends Node

signal upstream_closed(downstream_volume: float)  # EDV (mitral) or ESV (aortic) at closure
signal waveform_peak(pressure: float)              # v-wave (mitral) or SBP (aortic)
signal waveform_trough(pressure: float)            # y-descent (mitral) or DBP (aortic)

# ── Configuration ─────────────────────────────────────────────────────────────
## Name shown in the debugger to identify this valve instance.
@export var debug_name: String = ""

## mL/s of active upstream ejection force. Set >0 for AV valves (mitral, tricuspid). Leave 0 for semilunar valves (aortic, pulmonic).
@export var contraction_rate: float      = 0.0
## Extra mmHg the upstream chamber must exceed downstream pressure before the valve opens. Adds resistance to opening.
@export var open_threshold: float        = 0.0
## mmHg ceiling clamped on the upstream chamber pressure each tick. Prevents runaway pressure values.
@export var pressure_clamp_max: float    = 200.0
## If true, valve open/close is gated on ventricular systole state. Enable for AV valves (mitral, tricuspid).
@export var use_systole_guard: bool      = false
## If true, valve cannot reopen after closing within the same beat. Enable for the aortic valve to prevent backflow.
@export var use_latch: bool              = false
## If true, applies an elastance boost to the upstream chamber on closure — models the C-wave seen in LA pressure. Enable for mitral only.
@export var use_c_wave: bool             = false
## If true, detects the V-wave peak and Y-descent in upstream pressure — used to estimate PCWP. Enable for mitral only.
@export var use_pcwp_detection: bool     = false
## If true, tracks systolic and diastolic pressure peaks from the downstream waveform. Enable for the aortic valve to read SBP/DBP.
@export var use_waveform_tracking: bool  = false
## mmHg pressure drop applied on valve closure to simulate the dicrotic notch. Enable for the aortic valve.
@export var notch_dip: float             = 0.0

# C-wave parameters (mitral only)
## Rate at which the mitral valve diameter closes after AV closure, driving the C-wave elastance boost.
@export var c_wave_close_rate:     float = 33.3
## Peak elastance added to the LA at full mitral closure — stiffens the atrium to model the C-wave pressure bump.
@export var c_wave_elastance_boost: float = 0.30
## Rate at which the C-wave elastance boost decays after the valve is fully closed.
@export var c_wave_decay_rate:     float = 10.0
## Baseline e_max restored to the LA when the mitral valve reopens after systole.
@export var upstream_e_max_base:   float = 0.60

# ── Runtime state ─────────────────────────────────────────────────────────────
var _upstream:   CardiacChamber = null
var _downstream: CardiacChamber = null

var _latched:          bool  = false
var _was_open:         bool  = false

var _valve_diameter:   float = 1.0   # c-wave animation
var _c_boost:          float = 0.0

var _waveform_emitted: bool  = false   # v-wave / SBP emitted this cycle
var _trough_emitted:   bool  = false   # y-descent / DBP emitted this cycle
var _prev_pressure:    float = 8.0
var _cycle_peak:       float = 0.0
var _cycle_min:        float = 999.0

# Read by cardiovascular after tick()
var notch_fired: bool  = false
var flow:        float = 0.0   # eject_flow this tick (semilunar); 0 for AV valves (flow applied inline)

func _ready() -> void:
	var ep: Node = get_node("../../../HeartElectricalSystem/Ventricularcomponents")
	if use_latch:
		ep.ventricular_depolarization_started.connect(func() -> void: _latched = false)
	if use_pcwp_detection:
		ep.ventricular_depolarization_started.connect(func() -> void:
			_waveform_emitted = false
			_trough_emitted   = false
		)

func setup(upstream: CardiacChamber, downstream: CardiacChamber) -> void:
	_upstream   = upstream
	_downstream = downstream

# downstream_pressure: aorta_pressure / pulmonary_pressure for semilunar; ignored for AV valves
# ventricular_systole: used only when use_systole_guard=true
# downstream_valve_open: used only when use_pcwp_detection=true (mitral needs aortic valve state)
func tick(delta: float, downstream_pressure: float, ventricular_systole: bool, downstream_valve_open: bool) -> void:
	notch_fired = false
	flow        = 0.0

	var prev_was_open: bool = _was_open

	# ── Open / close ──────────────────────────────────────────────────────────
	if use_systole_guard:
		# AV valve: closes when downstream exceeds upstream during systole; opens in diastole
		if ventricular_systole and (_downstream.pressure > _upstream.pressure + 1.0):
			if _upstream.valve_open:
				_upstream.valve_open = false
				upstream_closed.emit(_downstream.volume)
				if use_c_wave:
					_valve_diameter = 1.0
					_c_boost        = 0.0
		elif not ventricular_systole:
			if not _upstream.valve_open and _downstream.pressure <= _upstream.pressure + 1.0:
				_upstream.valve_open = true
				if use_c_wave:
					_valve_diameter      = 1.0
					_c_boost             = 0.0
					_upstream.e_max      = upstream_e_max_base
	else:
		# Semilunar valve: pure pressure differential
		if not _upstream.valve_open and not _latched:
			if _upstream.pressure >= downstream_pressure + open_threshold:
				_upstream.valve_open = true
		if _upstream.valve_open:
			if _upstream.pressure < downstream_pressure:
				_upstream.valve_open = false
				if use_latch:
					_latched = true
				upstream_closed.emit(_upstream.volume)

	# ── C-wave (mitral only) ──────────────────────────────────────────────────
	if use_c_wave and not _upstream.valve_open:
		if _valve_diameter > 0.0:
			_valve_diameter    = maxf(0.0, _valve_diameter - c_wave_close_rate * delta)
			_c_boost           = c_wave_elastance_boost * (1.0 - _valve_diameter)
			_upstream.e_max    = upstream_e_max_base + _c_boost
		else:
			_c_boost        = maxf(0.0, _c_boost - c_wave_decay_rate * delta)
			_upstream.e_max = upstream_e_max_base + _c_boost

	# ── Flow ──────────────────────────────────────────────────────────────────
	if _upstream.valve_open:
		if contraction_rate > 0.0:
			var atrial_force: float = _upstream.get_active_force()
			if atrial_force > 0.0:
				var active_flow: float = (contraction_rate / float(_upstream.get_region_count())) * atrial_force * delta
				active_flow        = minf(active_flow, maxf(0.0, _upstream.volume - _upstream.v0))
				_upstream.volume  -= active_flow
				_downstream.volume += active_flow
			var passive_flow: float = maxf(0.0, (_upstream.pressure - _downstream.pressure) * _upstream.valve_conductance * delta)
			passive_flow        = minf(passive_flow, maxf(0.0, _upstream.volume - _upstream.v0))
			_upstream.volume   -= passive_flow
			_downstream.volume += passive_flow
		else:
			flow = maxf(0.0, (_upstream.pressure - downstream_pressure) * _upstream.valve_conductance * delta)
			flow = minf(flow, maxf(0.0, _upstream.volume - _upstream.v0))
			_upstream.volume -= flow

	_upstream.pressure = clampf(_upstream.pressure, 0.0, pressure_clamp_max)

	# ── Notch / flags ─────────────────────────────────────────────────────────
	_was_open   = _upstream.valve_open
	notch_fired = prev_was_open and not _upstream.valve_open

	# ── Waveform tracking (aortic only) ───────────────────────────────────────
	if use_waveform_tracking:
		if _upstream.valve_open:
			if not prev_was_open and _cycle_min < 999.0:
				waveform_trough.emit(_cycle_min)
				_cycle_min = 999.0
			_cycle_peak = maxf(_cycle_peak, downstream_pressure)
		else:
			_cycle_min = minf(_cycle_min, downstream_pressure)
			if notch_fired:
				waveform_peak.emit(_cycle_peak)
				_cycle_peak = 0.0

	# ── PCWP detection (mitral only) ──────────────────────────────────────────
	if use_pcwp_detection:
		var pcwp: float = _upstream.pressure
		if not _waveform_emitted and not downstream_valve_open and not _upstream.valve_open and pcwp < _prev_pressure:
			_waveform_emitted = true
			waveform_peak.emit(pcwp)
		if not _trough_emitted and _upstream.valve_open and pcwp < _prev_pressure:
			_trough_emitted = true
			waveform_trough.emit(pcwp)
		_prev_pressure = pcwp
