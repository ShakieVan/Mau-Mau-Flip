class_name LobbyPager
extends Control
# Seitlich blätterbarer Bereich der Gastgeber-Lobby (Beta 1.0.2): Seiten nebeneinander, die gerade verdeckte ragt um PEEK ins Bild.
# Waagrechtes Wischen (Maus bzw. Touch, auch über Knöpfen und der Spielerliste) verschiebt die Seiten; beim Loslassen rastet die
# nächste ein (Weg oder Schwung genügt), am Ende federt es zurück. Am offenen Rand liegt ein schmaler, pulsierender Blätter-Hinweis
# über die ganze Höhe; ein Tipp darauf oder auf den ragenden Teil blättert. Effekte reduziert: kein Pulsieren, kürzeres Einrasten.
# Die Wischgeste wird in _input erkannt (vor den Knöpfen und inneren Bildläufen), angefangene Knopfdrücke bricht
# NOTIFICATION_SCROLL_BEGIN ab. blocked (Callable → bool) sperrt das Wischen, z. B. solange ein Dialog offen ist.

signal page_changed(index: int)

const PEEK := 112.0
const GAP := 18.0
const DECIDE := 16.0            # so weit (px) bewegen, bevor entschieden wird: waagrecht blättern oder nicht
const SWITCH_SHARE := 0.18      # Anteil der Seitenbreite, ab dem beim Loslassen weitergeblättert wird
const SWITCH_SPEED := 700.0     # px/s Schwung, ab dem weitergeblättert wird

var pages: Array[Control] = []
var page := 0
var blocked := Callable()
var _strip: Control
var _hint: EdgeHint
var _offset := 0.0
var _tween: Tween
var _press := false
var _press_pos := Vector2.ZERO
var _press_offset := 0.0
var _drag := 0                  # 0 offen, 1 waagrecht (Blättern), -1 etwas anderes
var _vel := 0.0
var _last_x := 0.0
var _last_t := 0


func _init() -> void:
	name = "Blaettern"
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_strip = Control.new()
	_strip.name = "Streifen"
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)
	_hint = EdgeHint.new()
	_hint.name = "BlaetterHinweis"
	_hint.pressed.connect(func() -> void: show_page(1 - page if pages.size() == 2 else (page + 1) % maxi(pages.size(), 1)))
	add_child(_hint)


func add_page(c: Control) -> void:
	pages.append(c)
	_strip.add_child(c)
	# Umbrechende Texte melden bei schmaler erster Breite eine riesige Mindesthöhe; dann klemmt Godot die Größe darauf. Sobald
	# die Mindestgröße wieder passt, die Seite erneut auf die Fläche setzen.
	c.minimum_size_changed.connect(_fit_pages_later)
	c.resized.connect(_fit_pages_later)
	_layout()


func _fit_pages_later() -> void:
	if not is_queued_for_deletion():
		_fit_pages.call_deferred()


func _fit_pages() -> void:
	var want := Vector2(page_width(), size.y)
	for p in pages:
		if is_instance_valid(p) and not p.size.is_equal_approx(want):
			p.size = want


func page_width() -> float:
	return maxf(size.x - PEEK - GAP, 200.0)


func page_x(i: int) -> float:
	return i * (page_width() + GAP)


# Verschiebung, bei der Seite i ganz zu sehen ist (erste links-, letzte rechtsbündig)
func target_offset(i: int) -> float:
	if i <= 0:
		return 0.0
	if i >= pages.size() - 1:
		return size.x - page_x(i) - page_width()
	return PEEK + GAP - page_x(i)


func show_page(i: int, animate := true) -> void:
	i = clampi(i, 0, maxi(pages.size() - 1, 0))
	var changed := i != page
	page = i
	_kill_tween()
	var to := target_offset(i)
	if animate and is_inside_tree() and absf(to - _offset) > 1.0:
		_hint.visible = false
		_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_method(_set_offset, _offset, to, 0.14 if UiApp.reduced_effects() else 0.3)
		_tween.tween_callback(_place_hint)
	else:
		_set_offset(to)
		_place_hint()
	if changed:
		page_changed.emit(i)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _set_offset(x: float) -> void:
	_offset = x
	_strip.position = Vector2(roundf(x), 0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _layout() -> void:
	if _strip == null:
		return
	var w := page_width()
	for i in pages.size():
		pages[i].position = Vector2(page_x(i), 0)
		pages[i].size = Vector2(w, size.y)
	_kill_tween()
	_set_offset(target_offset(page))
	_place_hint()


func _place_hint() -> void:
	if pages.size() < 2:
		_hint.visible = false
		return
	_hint.visible = true
	_hint.side = 1 if page == 0 else -1
	_hint.reduced = UiApp.reduced_effects()
	var w := PEEK + GAP
	_hint.position = Vector2(size.x - w, 0) if page == 0 else Vector2.ZERO
	_hint.size = Vector2(w, size.y)
	_hint.queue_redraw()


func _is_blocked() -> bool:
	return not is_visible_in_tree() or (blocked.is_valid() and bool(blocked.call()))


func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_press = not _is_blocked() and get_global_rect().has_point(mb.global_position)
			if _press:
				_press_pos = mb.global_position
				_press_offset = _offset
				_drag = 0
				_vel = 0.0
				_last_x = mb.global_position.x
				_last_t = Time.get_ticks_msec()
		elif _press:
			_press = false
			if _drag == 1:
				_drag = 0
				get_viewport().set_input_as_handled()
				_release()
			_drag = 0
		return
	var mm := event as InputEventMouseMotion
	if mm == null or not _press:
		return
	var d := mm.global_position - _press_pos
	if _drag == 0 and d.length() > DECIDE:
		_drag = 1 if absf(d.x) > absf(d.y) * 1.2 and pages.size() > 1 else -1
		if _drag == 1:
			_kill_tween()
			_hint.visible = false
			_strip.propagate_notification(NOTIFICATION_SCROLL_BEGIN)   # angefangene Knopfdrücke abbrechen
			_hint.cancel()
	if _drag != 1:
		return
	var now := Time.get_ticks_msec()
	var dt := maxf(float(now - _last_t), 1.0) / 1000.0
	_vel = lerpf(_vel, (mm.global_position.x - _last_x) / dt, 0.5)
	_last_x = mm.global_position.x
	_last_t = now
	var x := _press_offset + d.x
	var lo := target_offset(pages.size() - 1)
	if x > 0.0:
		x = x * 0.35                                     # Gummiband am Anfang
	elif x < lo:
		x = lo + (x - lo) * 0.35                         # … und am Ende
	_set_offset(x)
	get_viewport().set_input_as_handled()


func _release() -> void:
	var delta := _offset - target_offset(page)
	var next := page
	if absf(delta) > page_width() * SWITCH_SHARE or absf(_vel) > SWITCH_SPEED:
		var dir := -signf(delta) if absf(delta) > page_width() * SWITCH_SHARE else -signf(_vel)
		next = page + int(dir)
	show_page(next)


# Schmaler, pulsierender Streifen mit Pfeil am offenen Rand; Trefferfläche ist der ganze ragende Teil
class EdgeHint:
	extends Control
	signal pressed
	const STRIP := 34.0
	var side := 1                # 1 = rechts (weiter nach rechts blättern), -1 = links
	var reduced := false
	var _t := 0.0
	var _down := false
	var _arrow: Texture2D

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_arrow = UiIcons.icon("pfeil", 30, UiPalette.INK)

	func cancel() -> void:
		_down = false

	func _process(delta: float) -> void:
		if visible and not reduced:
			_t += delta
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_down = true
		elif _down:
			_down = false
			if Rect2(Vector2.ZERO, size).has_point(mb.position):
				pressed.emit()
		accept_event()

	func _draw() -> void:
		var pulse := 0.5 if reduced else 0.5 + 0.5 * sin(_t * 3.0)
		var x := size.x - STRIP if side > 0 else 0.0
		var r := Rect2(x, 0, STRIP, size.y)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UiPalette.PAPER, 0.55 + 0.3 * pulse)
		sb.border_color = Color(UiPalette.INK, 0.12 + 0.22 * pulse)
		sb.set_border_width_all(0)
		if side > 0:
			sb.border_width_left = 3
			sb.corner_radius_top_left = 16
			sb.corner_radius_bottom_left = 16
		else:
			sb.border_width_right = 3
			sb.corner_radius_top_right = 16
			sb.corner_radius_bottom_right = 16
		draw_style_box(sb, r)
		if _arrow != null:
			var s := _arrow.get_size()
			var nudge := (0.0 if reduced else 4.0 * pulse) * side
			var c := r.get_center() + Vector2(nudge, 0)
			if side > 0:
				draw_texture(_arrow, c - s / 2.0, Color(1, 1, 1, 0.55 + 0.45 * pulse))
			else:
				draw_texture_rect(_arrow, Rect2(c.x + s.x / 2.0, c.y - s.y / 2.0, -s.x, s.y), false, Color(1, 1, 1, 0.55 + 0.45 * pulse))
