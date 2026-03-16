class_name CardiacPressureGraph
extends Control

# Draws a rolling pressure-over-time graph for all 4 cardiac chambers.
# Attach to a CanvasLayer. Call record(cardio) each tick from the debug refresh.

const HISTORY_SIZE: int   = 300
const GRAPH_W: float      = 600.0
const GRAPH_H: float      = 300.0
const Y_MIN: float        = 0.0
const Y_MAX: float        = 160.0
const LABEL_W: float      = 60.0
const BOTTOM_PAD: float   = 20.0

# Series: LA, LV, RA, RV, Aorta
const COLORS: Array = [
	Color(0.2, 0.8, 1.0),   # LA  — cyan
	Color(1.0, 0.3, 0.3),   # LV  — red
	Color(0.3, 1.0, 0.5),   # RA  — green
	Color(1.0, 0.8, 0.2),   # RV  — yellow
	Color(1.0, 0.5, 0.0),   # Aorta — orange
]
const NAMES: Array = ["LA", "LV", "RA", "RV", "Ao"]

var _history: Array = []   # Array of Array[float] — one inner array per series, length HISTORY_SIZE

func _init() -> void:
	custom_minimum_size = Vector2(LABEL_W + GRAPH_W, GRAPH_H + BOTTOM_PAD)
	for _i in NAMES.size():
		var buf: Array[float] = []
		buf.resize(HISTORY_SIZE)
		buf.fill(0.0)
		_history.append(buf)

func record(cardio: Node) -> void:
	var samples: Array = [
		cardio.la.pressure,
		cardio.lv.pressure,
		cardio.ra.pressure,
		cardio.rv.pressure,
		cardio.monitor.aorta_pressure,
	]
	for s in NAMES.size():
		_history[s].pop_front()
		_history[s].append(samples[s])
	queue_redraw()

func _draw() -> void:
	var bg_rect := Rect2(Vector2.ZERO, Vector2(LABEL_W + GRAPH_W, GRAPH_H + BOTTOM_PAD))
	draw_rect(bg_rect, Color(0.05, 0.05, 0.05, 0.9))

	var plot_x: float = LABEL_W
	var plot_w: float = GRAPH_W
	var plot_h: float = GRAPH_H

	# Y axis grid lines at 0, 40, 80, 120, 160
	for mmhg in [0, 40, 80, 120, 160]:
		var y: float = _mmhg_to_y(float(mmhg), plot_h)
		draw_line(Vector2(plot_x, y), Vector2(plot_x + plot_w, y), Color(0.2, 0.2, 0.2), 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(2.0, y + 4.0), str(mmhg), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.5, 0.5))

	# Series lines
	for s in NAMES.size():
		var buf: Array = _history[s]
		var col: Color = COLORS[s]
		var prev_pt := Vector2(plot_x, _mmhg_to_y(buf[0], plot_h))
		for i in range(1, HISTORY_SIZE):
			var x: float = plot_x + (float(i) / float(HISTORY_SIZE - 1)) * plot_w
			var pt := Vector2(x, _mmhg_to_y(buf[i], plot_h))
			draw_line(prev_pt, pt, col, 1.5)
			prev_pt = pt

	# Legend at bottom
	var lx: float = plot_x
	for s in NAMES.size():
		draw_rect(Rect2(lx, GRAPH_H + 4.0, 10.0, 10.0), COLORS[s])
		draw_string(ThemeDB.fallback_font, Vector2(lx + 13.0, GRAPH_H + 14.0), NAMES[s], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLORS[s])
		lx += 60.0

func _mmhg_to_y(mmhg: float, plot_h: float) -> float:
	var t: float = clampf((mmhg - Y_MIN) / (Y_MAX - Y_MIN), 0.0, 1.0)
	return plot_h * (1.0 - t)
