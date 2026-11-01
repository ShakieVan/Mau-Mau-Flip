class_name PulseDotsButton
extends Control
# Runder „…“-Knopf, der pulsiert (Beta 1.6.17, Nutzerwunsch 31.10.2026): Steht am Tisch des Gastgebers statt der Sofort-Leiste, solange
# ein Gast weg ist; ein Tipp öffnet die Leiste (TableScreen.toggle_bar). Gelb mit dunklen Punkten, ein Ring läuft nach außen.
# Effekte „reduziert“: steht still, ohne Ring. Der Ring darf über den Knopf hinausragen, die Trefferfläche ist size.

signal pressed

const PERIOD_S := 1.4            # ein Pulsschlag
const RING_GROW := 20.0          # so weit läuft der Ring hinaus

var night := 0.0: set = set_night
var reduced := false: set = set_reduced

var _t := 0.0
var _down := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func set_night(v: float) -> void:
	if not is_equal_approx(v, night):
		night = v
		queue_redraw()


func set_reduced(on: bool) -> void:
	if on != reduced:
		reduced = on
		queue_redraw()


func _process(delta: float) -> void:
	if reduced or not is_visible_in_tree():
		return
	_t += delta
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_down = true
			queue_redraw()
		elif _down:
			_down = false
			queue_redraw()
			if Rect2(Vector2.ZERO, size).has_point(mb.position):
				pressed.emit()
		accept_event()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 3.0
	if not reduced:
		var phase := fposmod(_t / PERIOD_S, 1.0)
		var ring := UiPalette.TURN if night > 0.5 else UiPalette.INK
		draw_arc(c, r + RING_GROW * phase, 0.0, TAU, 56, Color(ring, 0.75 * (1.0 - phase)), 4.0, true)
		r *= 1.0 + 0.05 * sin(phase * TAU)
	if _down:
		r -= 3.0
	draw_circle(c, r, UiPalette.TURN, true, -1.0, true)
	draw_arc(c, r, 0.0, TAU, 56, UiPalette.INK, 3.0, true)
	for i in [-1, 0, 1]:
		draw_circle(c + Vector2(i * r * 0.44, 0.0), r * 0.13, UiPalette.INK, true, -1.0, true)
