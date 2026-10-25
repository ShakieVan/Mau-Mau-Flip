class_name WishPicker
extends Node2D
# Farbwahl für Wünscher (06 Abschnitt 1.5). Name WishPicker statt ColorPicker: Godot hat bereits eine Klasse ColorPicker.
# Farbrad nach dem Legen: vier Viertel um die Bildschirmmitte, jedes mit Formsymbol und der Anzahl eigener Karten dieser Farbe;
# Tipp wählt, Tipp daneben bricht ab. Eingaben gibt der Tisch über handle_input() weiter.
# Die Farbfelder um die Ablage beim Ziehen eines Jokers sind entfallen (Nutzerwunsch 25.10.2026: man landete zu oft versehentlich
# darauf; die Farbwahl über das Farbrad nach dem Legen reicht).

signal color_chosen(color: String)
signal cancelled

const WHEEL_R := 210.0
const WHEEL_INNER := 92.0

var side := "hell"
var counts: Dictionary = {}
var mode := ""                       # "" | "wheel"
var hovered := ""
var wheel_center := Vector2.ZERO     # lokal (Bildschirmmitte), vom Tisch gesetzt
var night := 0.0
var title := ""                      # Farbrad: Frage über dem Rad (z. B. beim Ablegen-Joker), "" = keine

var _open := 0.0
var _tween: Tween
var _press_seen := false             # Farbrad: Druck seit dem Öffnen (siehe handle_input)


func is_open() -> bool:
	return mode != ""


func colors() -> Array[String]:
	return UiPalette.colors_of(side)


func open_wheel(active_side: String, own_counts: Dictionary = {}, question := "") -> void:
	_start("wheel", active_side, own_counts)
	title = question


func close() -> void:
	mode = ""
	title = ""
	hovered = ""
	_open = 0.0
	queue_redraw()


func _start(m: String, active_side: String, own_counts: Dictionary) -> void:
	mode = m
	side = active_side
	counts = own_counts
	hovered = ""
	_open = 0.0
	_press_seen = false
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(func(v: float) -> void:
		_open = v
		queue_redraw(), 0.0, 1.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()


# Farbe unter einer globalen Position (Viertel des Farbrads), sonst ""
func color_at(global_pos: Vector2) -> String:
	var p := to_local(global_pos)
	if mode == "wheel":
		var v := p - wheel_center
		var l := v.length()
		if l < WHEEL_INNER * 0.6 or l > WHEEL_R + 30.0:
			return ""
		var a := fposmod(v.angle() + PI, TAU)      # 0 = links, im Uhrzeigersinn
		var q := int(a / (PI * 0.5)) % 4
		# Viertel: oben links, oben rechts, unten rechts, unten links
		return colors()[q]
	return ""


func hover(global_pos: Vector2) -> String:
	var c := color_at(global_pos)
	if c != hovered:
		hovered = c
		if c != "":
			UiApp.vibrate(10, 0.25)
		queue_redraw()
	return c


# Loslassen: gewählte Farbe oder "" (dann abgebrochen); schließt in beiden Fällen
func drop(global_pos: Vector2) -> String:
	var c := color_at(global_pos)
	close()
	if c != "":
		color_chosen.emit(c)
	else:
		cancelled.emit()
	return c


# Abbrechen von außen (Zurück-Taste): wie ein Tipp daneben
func cancel() -> void:
	if mode == "":
		return
	close()
	cancelled.emit()


# Farbrad: Tipp wählt, Tipp außerhalb bricht ab. Gibt true zurück, wenn das Ereignis verbraucht wurde.
# Ein Loslassen zählt nur nach einem Druck seit dem Öffnen (Nutzerbefund 25.10.2026, Doppeltipp mit dem Stift auf einen Joker): Beim
# Stift kommt die nachgebildete Berührung vor dem Mausereignis (App.enable_pen_touch), die Hand öffnet das Rad also schon beim
# Loslassen der Berührung – das Maus-Loslassen desselben Tipps landete dann hier und brach als „Tipp daneben“ sofort ab. Beim Finger
# ist die Reihenfolge umgekehrt (nachgebildete Maus zuerst).
func handle_input(event: InputEvent, global_pos: Vector2) -> bool:
	if mode != "wheel":
		return false
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_press_seen = true
			hover(global_pos)
		elif _press_seen:
			drop(global_pos)
		return true
	if event is InputEventMouseMotion:
		hover(global_pos)
		return true
	return false


func _draw() -> void:
	if mode == "wheel":
		_draw_wheel()


func _draw_wheel() -> void:
	var cols := colors()
	var c := wheel_center
	var o := clampf(_open, 0.0, 1.2)
	# Dialog: ganzer Bildschirm abgedunkelt
	draw_rect(Rect2(-position - Vector2(200, 200), Vector2(5000, 3000)), Color(0.02, 0.03, 0.08, 0.45 * clampf(_open, 0.0, 1.0)))
	draw_circle(c, (WHEEL_R + 26.0) * o, Color(UiPalette.CREAM, 0.9))
	if o < 0.35:
		return
	var nf := UiFonts.text(800, 95.0)
	for q in 4:
		var col := cols[q]
		var hot := col == hovered
		var a0 := PI + q * PI * 0.5 + 0.03
		var a1 := a0 + PI * 0.5 - 0.06
		var ro := (WHEEL_R + (14.0 if hot else 0.0)) * o
		var ri := WHEEL_INNER * o
		var pts := PackedVector2Array()
		for k in 25:
			pts.append(c + Vector2.from_angle(lerpf(a0, a1, k / 24.0)) * ro)
		for k in 25:
			pts.append(c + Vector2.from_angle(lerpf(a1, a0, k / 24.0)) * ri)
		draw_colored_polygon(pts, UiPalette.fill(col))
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, UiPalette.CREAM if side == "hell" else UiPalette.glow(col), 4.0 if hot else 2.5, true)
		var mid := c + Vector2.from_angle((a0 + a1) * 0.5) * (ri + ro) * 0.5
		var sym_col := UiPalette.CREAM if UiPalette.fill(col).get_luminance() < 0.6 else UiPalette.INK
		draw_texture_rect(UiIcons.symbol(col, 96, sym_col, UiPalette.fill(col)), Rect2(mid - Vector2(26, 38) * o, Vector2(52, 52) * o), false)
		var label := "%s ×%d" % [I18n.t(UiPalette.color_name(col)), int(counts.get(col, 0))]
		var fs := maxi(int(UiFonts.px(17) * o), 1)
		var lw := nf.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(nf, mid + Vector2(-lw * 0.5, 34.0 * o), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, sym_col)
	if title != "":
		var qf := UiFonts.title(800, true, 100.0, 36.0)
		var qs := UiFonts.px(34)
		var qt := I18n.t(title)
		var qw := qf.get_string_size(qt, HORIZONTAL_ALIGNMENT_LEFT, -1, qs).x
		var qy := c.y - (WHEEL_R + 60.0) * o
		var qr := Rect2(Vector2(c.x - qw * 0.5 - 24.0, qy - qs - 6.0), Vector2(qw + 48.0, qs + 22.0))
		var qb := StyleBoxFlat.new()
		qb.bg_color = Color(UiPalette.CREAM, 0.95)
		qb.set_corner_radius_all(28)
		draw_style_box(qb, qr)
		draw_string(qf, Vector2(c.x - qw * 0.5, qy), qt, HORIZONTAL_ALIGNMENT_LEFT, -1, qs, UiPalette.INK)
	draw_circle(c, (WHEEL_INNER - 10.0) * o, UiPalette.CREAM)
	var tf := UiFonts.title(800, true, 100.0, 36.0)
	var ts := maxi(int(UiFonts.px(22) * o), 1)
	var k := UiFonts.px(22) / 22.0
	var wp := I18n.t("Farbe wählen").split(" ", false, 1)
	for line in [[wp[0], -6.0], [wp[1] if wp.size() > 1 else "", 20.0]]:
		var t: String = line[0]
		var tw := tf.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x
		draw_string(tf, c + Vector2(-tw * 0.5, float(line[1]) * k * o), t, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, UiPalette.INK)
