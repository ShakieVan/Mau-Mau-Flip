class_name MauButton
extends Control
# Großer runder „Mau!“-Knopf (Entwurf: rechts unten, 150 px, Fraunces kursiv 900 mit SOFT 100, Papier mit Druckfarbenrand
# und rosa Lichtkranz). Zustände: IDLE (sichtbar, ruhig), READY (Mau ist jetzt möglich: Kranz pulsiert, Knopf hebt sich),
# CALLED (gerufen: gedämpft mit Haken), HIDDEN. Drücken staucht den Knopf; das Signal kommt beim Loslassen im Knopf.
# Den Mau-Ton spielt nur das Gerät, das gedrückt hat (BETA1_PLAN Abschnitt 5) – das übernimmt der Tisch.

signal mau_pressed

enum Mode { IDLE, READY, CALLED, HIDDEN }

const SIZE := 150.0

var mode := Mode.IDLE: set = set_mode
var _down := false
var _time := 0.0
var _press := 0.0
var _pop := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	focus_mode = Control.FOCUS_NONE


func set_mode(m: Mode) -> void:
	if m == Mode.READY and mode != Mode.READY:
		_pop = 1.0
	mode = m
	visible = m != Mode.HIDDEN
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_press = move_toward(_press, 1.0 if _down else 0.0, delta * 12.0)
	_pop = maxf(_pop - delta * 2.5, 0.0)
	if mode == Mode.READY or _press > 0.0 or _pop > 0.0:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var inside := (mb.position - size * 0.5).length() <= size.x * 0.5 + 12.0
	if mb.pressed and inside:
		_down = true
	elif not mb.pressed and _down:
		_down = false
		if inside:
			mau_pressed.emit()
	accept_event()


func _has_point(point: Vector2) -> bool:
	return (point - size * 0.5).length() <= size.x * 0.5 + 12.0


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 12.0
	var s := 1.0 - 0.07 * _press + 0.06 * sin(_pop * PI)
	var pulse := 0.5 + 0.5 * sin(_time * 3.2)
	var halo := Color("#FF7FCF")
	match mode:
		Mode.READY:
			draw_circle(c, (r + 14.0 + 5.0 * pulse) * s, Color(halo, 0.22 + 0.18 * pulse))
			draw_circle(c, (r + 9.0) * s, Color(halo, 0.55))
		Mode.CALLED:
			draw_circle(c, (r + 8.0) * s, Color(halo, 0.18))
		_:
			draw_circle(c, (r + 8.0) * s, Color(halo, 0.30))
	draw_circle(c + Vector2(0, 8.0 * (1.0 - _press)), r * s, Color(0, 0, 0, 0.35))
	var fill := UiPalette.CREAM if mode != Mode.CALLED else UiPalette.PAPER_D
	draw_circle(c, r * s, UiPalette.INK)
	draw_circle(c, (r - 5.0) * s, fill)
	var f := UiFonts.mau()
	var fs := int(46.0 * s)
	var t := "Mau!"
	var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var room := (r - 5.0) * s * 2.0 * 0.80
	if tw > room:
		fs = int(fs * room / tw)
		tw = f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var ink := UiPalette.INK if mode != Mode.CALLED else Color(UiPalette.INK, 0.55)
	draw_string(f, c + Vector2(-tw * 0.5, fs * 0.34), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	if mode == Mode.CALLED:
		var hk := c + Vector2(r * 0.52, r * 0.52)
		draw_circle(hk, 17.0, UiPalette.INK)
		draw_texture_rect(UiIcons.icon("haken", 40, UiPalette.CREAM), Rect2(hk - Vector2(11, 11), Vector2(22, 22)), false)
