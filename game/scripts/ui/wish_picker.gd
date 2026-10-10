class_name WishPicker
extends Node2D
# Farbwahl für Wünscher (06 Abschnitt 1.5, „Joker in einer Geste“). Name WishPicker statt ColorPicker: Godot hat bereits eine
# Klasse ColorPicker.
# - Felder: Beim Ziehen eines Jokers fächern vier Farbfelder um die Ablage auf (Farben der aktiven Seite), jedes mit Formsymbol
#   und der Anzahl eigener Karten dieser Farbe. Die Hand meldet die Fingerposition mit hover(), loslassen mit drop().
# - Farbrad (Rückfall per Tipp): vier Viertel um die Bildschirmmitte; Tipp wählt, Tipp daneben bricht ab.
# Ursprung = Mitte der Ablage. Eingaben im Farbrad gibt der Tisch über handle_input() weiter.

signal color_chosen(color: String)
signal cancelled

const FIELD := 104.0
const OFFSET := Vector2(150.0, 128.0)
const WHEEL_R := 210.0
const WHEEL_INNER := 92.0

var side := "hell"
var counts: Dictionary = {}
var mode := ""                       # "" | "fields" | "wheel"
var hovered := ""
var wheel_center := Vector2.ZERO     # lokal (Bildschirmmitte), vom Tisch gesetzt
var night := 0.0
var title := ""                      # Farbrad: Frage über dem Rad (z. B. beim Ablegen-Joker), "" = keine

var _open := 0.0
var _tween: Tween


func is_open() -> bool:
	return mode != ""


func colors() -> Array[String]:
	return UiPalette.colors_of(side)


func open_fields(active_side: String, own_counts: Dictionary = {}) -> void:
	_start("fields", active_side, own_counts)


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
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(func(v: float) -> void:
		_open = v
		queue_redraw(), 0.0, 1.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()


# Lage der Felder (lokal): oben links, oben rechts, unten rechts, unten links – in Farbreihenfolge der Seite
func field_center(i: int) -> Vector2:
	var dirs := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var d: Vector2 = dirs[i % 4]
	return d * OFFSET * _open


func field_rect(i: int) -> Rect2:
	var c := field_center(i)
	return Rect2(c - Vector2.ONE * FIELD * 0.5, Vector2.ONE * FIELD)


# Farbe unter einer globalen Position (Felder: großzügige Trefferfläche, Farbrad: Viertel)
func color_at(global_pos: Vector2) -> String:
	var p := to_local(global_pos)
	if mode == "fields":
		var best := ""
		var best_d := FIELD * 0.95
		var cols := colors()
		for i in 4:
			var d := p.distance_to(field_center(i))
			if d < best_d:
				best_d = d
				best = cols[i]
		return best
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
func handle_input(event: InputEvent, global_pos: Vector2) -> bool:
	if mode != "wheel":
		return false
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			hover(global_pos)
		else:
			drop(global_pos)
		return true
	if event is InputEventMouseMotion:
		hover(global_pos)
		return true
	return false


func _draw() -> void:
	if mode == "fields":
		_draw_fields()
	elif mode == "wheel":
		_draw_wheel()


func _draw_fields() -> void:
	var cols := colors()
	var nf := UiFonts.text(800, 90.0)
	for i in 4:
		var col := cols[i]
		var hot := col == hovered
		var dim := hovered != "" and not hot
		var s := (1.18 if hot else 1.0) * clampf(_open, 0.0, 1.2)
		var c := field_center(i)
		var r := Rect2(c - Vector2.ONE * FIELD * 0.5 * s, Vector2.ONE * FIELD * s)
		var fill := UiPalette.fill(col)
		var glow := UiPalette.glow(col)
		if hot:
			draw_circle(c, FIELD * 0.85 * s, Color(glow, 0.28))
		var shadow := StyleBoxFlat.new()
		shadow.bg_color = Color(0, 0, 0, 0)
		shadow.shadow_color = Color(0, 0, 0, 0.35)
		shadow.shadow_size = 12
		shadow.shadow_offset = Vector2(0, 6)
		shadow.set_corner_radius_all(int(26 * s))
		draw_style_box(shadow, r)
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill if not dim else fill.lerp(Color(0.5, 0.5, 0.55), 0.45)
		sb.set_corner_radius_all(int(26 * s))
		sb.border_color = UiPalette.CREAM if side == "hell" else glow
		sb.set_border_width_all(int((6 if hot else 4) * s))
		sb.anti_aliasing = true
		draw_style_box(sb, r)
		var sym_col := UiPalette.CREAM if fill.get_luminance() < 0.6 else UiPalette.INK
		var isz := 52.0 * s
		draw_texture_rect(UiIcons.symbol(col, 104, sym_col, fill), Rect2(c - Vector2(isz * 0.5, isz * 0.62), Vector2(isz, isz)), false)
		var n := int(counts.get(col, 0))
		var label := "×%d" % n
		if s < 0.35:
			continue
		var fs := maxi(int(UiFonts.px(18) * s), 1)
		var lw := nf.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(nf, c + Vector2(-lw * 0.5, FIELD * 0.36 * s), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, sym_col)


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
