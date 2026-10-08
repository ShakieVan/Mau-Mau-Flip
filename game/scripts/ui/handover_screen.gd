class_name HandoverScreen
extends Control
# Sichtschutz „Weitergeben“ (AGENTS.md Nr. 15, 06 Abschnitt 3.5): deckt den Tisch vollständig ab und zeigt KEINE Karten,
# auch keine Rückseiten – nur Ablage- und Stapelzahl. Text „Gib das Handy nach links an Lena“ mit Pfeil aus der Sitzordnung.
# Aufdecken: 500 ms halten (Fortschrittsring); die ersten 350 ms nach dem Erscheinen sind gesperrt (versehentliches Weitertippen).

signal revealed

const HOLD_TIME := 0.5
const TAP_LOCK := 0.35

var to_name := ""
var info := {}                      # Ergebnis von direction_info
var discard_count := 0
var draw_count := 0
var side := "hell"
var night := 0.0

var _bg: TableBackground
var _shown_at := 0.0
var _clock := 0.0
var _holding := false
var _hold := 0.0
var _time := 0.0


# Richtung vom aktuellen Halter zum nächsten Menschen. Plätze im Uhrzeigersinn: der nächste Platz sitzt links.
# Ergebnis {side: "links"|"rechts"|"gegenüber", steps: Plätze dazwischen + 1, arrow: Bildschirmrichtung}
static func direction_info(from_seat: int, to_seat: int, n: int) -> Dictionary:
	var r := posmod(to_seat - from_seat, maxi(n, 1))
	if r == 0:
		return {"side": "selbst", "steps": 0, "arrow": Vector2.ZERO}
	if n % 2 == 0 and r == n / 2 and n > 2:
		return {"side": "gegenüber", "steps": r, "arrow": Vector2.UP}
	if r <= n / 2:
		return {"side": "links", "steps": r, "arrow": Vector2.LEFT}
	return {"side": "rechts", "steps": n - r, "arrow": Vector2.RIGHT}


static func headline(name: String, d: Dictionary) -> String:
	match str(d.get("side", "")):
		"selbst":
			return "%s ist wieder dran" % name
		"gegenüber":
			return "Gib das Handy an %s gegenüber" % name
		"links", "rechts":
			if int(d["steps"]) == 1:
				return "Gib das Handy nach %s an %s" % [d["side"], name]
			return "Gib das Handy an %s – %d Plätze nach %s" % [name, int(d["steps"]), d["side"]]
	return "Gib das Handy an %s" % name


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_bg = TableBackground.new()
	_bg.show_behind_parent = true     # eigene Zeichnung liegt über dem Hintergrund
	add_child(_bg)


func show_for(name: String, from_seat: int, to_seat: int, n: int, discard := 0, pile := 0, active_side := "hell") -> void:
	to_name = name
	info = direction_info(from_seat, to_seat, n) if from_seat >= 0 else {}   # Partiebeginn: kein Vorgänger, nur „Gib das Handy an …“
	discard_count = discard
	draw_count = pile
	side = active_side
	night = 1.0 if side == "dunkel" else 0.0
	_bg.tageszeit = night
	_shown_at = _clock
	_hold = 0.0
	_holding = false
	visible = true
	queue_redraw()


func hide_screen() -> void:
	visible = false
	_holding = false


func can_press() -> bool:
	return _clock - _shown_at >= TAP_LOCK


func hold_progress() -> float:
	return clampf(_hold / HOLD_TIME, 0.0, 1.0)


func _process(delta: float) -> void:
	_clock += delta
	if not visible:
		return
	_time += delta
	if _holding:
		_hold += delta
		if _hold >= HOLD_TIME:
			_holding = false
			visible = false
			UiApp.vibrate(20, 0.4)
			revealed.emit()
	elif _hold > 0.0:
		_hold = maxf(_hold - delta * 3.0, 0.0)
	queue_redraw()


func _button_center() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.70)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		accept_event()
		return
	if mb.pressed:
		if can_press() and mb.position.distance_to(_button_center()) < 130.0:
			_holding = true
	else:
		_holding = false
	accept_event()


func _draw() -> void:
	var ink := UiPalette.ui_text(night)
	var muted := UiPalette.ui_muted(night)
	var c := Vector2(size.x * 0.5, 0.0)
	# Pfeil aus der Sitzordnung (wippt in Laufrichtung)
	var arrow: Vector2 = info.get("arrow", Vector2.ZERO)
	var title_f := UiFonts.title(800, false, 50.0, 72.0)
	var head := headline(to_name, info)
	var fs := UiFonts.px(46)   # Schriftgrößen folgen der Einstellung „Schriftgröße“
	var tw := title_f.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if tw > size.x - 120.0:
		fs = int(fs * (size.x - 120.0) / tw)
		tw = title_f.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(title_f, Vector2(c.x - tw * 0.5, size.y * 0.24), head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	if arrow != Vector2.ZERO:
		var wob := sin(_time * 5.0) * 10.0
		var ac := Vector2(c.x, size.y * 0.40) + arrow * wob
		var tex := UiIcons.icon("pfeil", 128, ink)
		draw_set_transform(ac, arrow.angle(), Vector2.ONE)
		draw_texture_rect(tex, Rect2(-56, -56, 112, 112), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# nur Zahlen, keine Karten
	var f := UiFonts.text(700, 100.0)
	if discard_count + draw_count > 0:      # vor dem Austeilen (Partiebeginn) noch keine Zahlen
		var line := "Ablage: %d Karten  ·  Stapel: %d Karten" % [discard_count, draw_count]
		var ls := UiFonts.px(20)
		var lw := f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, ls).x
		draw_string(f, Vector2(c.x - lw * 0.5, size.y * 0.52), line, HORIZONTAL_ALIGNMENT_LEFT, -1, ls, muted)
	# Halteknopf mit Fortschrittsring
	var bc := _button_center()
	var r := 74.0
	var locked := not can_press()
	draw_circle(bc, r + 10.0, Color(ink, 0.10))
	draw_circle(bc, r, UiPalette.CREAM if night > 0.5 else UiPalette.INK)
	if hold_progress() > 0.0:
		draw_arc(bc, r + 6.0, -PI * 0.5, -PI * 0.5 + TAU * hold_progress(), 64, UiPalette.TURN, 8.0, true)
	var eye := UiIcons.icon("katze_wach", 96, UiPalette.INK if night > 0.5 else UiPalette.CREAM, UiPalette.CREAM if night > 0.5 else UiPalette.INK)
	draw_texture_rect(eye, Rect2(bc - Vector2(40, 44), Vector2(80, 80)), false, Color(1, 1, 1, 0.5 if locked else 1.0))
	var hint := "%s: zum Aufdecken halten" % to_name
	var hs := UiFonts.px(22)
	var hw := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x
	draw_string(f, Vector2(c.x - hw * 0.5, bc.y + r + 24.0 + hs), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, ink)
