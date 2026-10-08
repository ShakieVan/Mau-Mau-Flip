class_name ListHeader
extends Node2D
# Kopf der Spielerliste im großen Modus (Nutzerwunsch 08.10.2026, wie im Browser): großer Kreispfeil für die Spielrichtung und
# das Wort „Reihenfolge“. dir 1 = im Uhrzeigersinn (wie der Richtungsring am Tisch), −1 = gegen den Uhrzeigersinn.
# Richtungswechsel: Der Pfeil klappt (Spiegelung über 0) in die neue Richtung und dreht sich dabei einmal ganz in ihr herum,
# mit kurzem Aufploppen. Effekte „reduziert“: sofort, ohne Drehung. Ursprung = linke obere Ecke von BigLayout.list_head_rect,
# head_size = deren Größe. Farben folgen night (0 Tag/Papier … 1 Nacht), Schrift über UiFonts (on_font_scale).

const TEXT := "Reihenfolge"
const TURN_S := 0.75             # Dauer der Wende

var head_size := Vector2(440, 64): set = set_head_size
var night := 0.0: set = set_night
var reduced := false
var dir := 1                     # Zielrichtung (Tests: arrow_sign)
var _from := 1.0                 # Spiegelung vor der Wende
var _t := -1.0                   # Fortschritt der Wende 0..1, −1 = keine


func set_head_size(v: Vector2) -> void:
	head_size = v
	queue_redraw()


func set_night(v: float) -> void:
	night = clampf(v, 0.0, 1.0)
	queue_redraw()


func on_font_scale() -> void:
	queue_redraw()


# Richtung setzen; animate = sichtbare Wende (nicht beim ersten Bild, nicht bei reduzierten Effekten)
func set_dir(d: int, animate: bool) -> void:
	d = -1 if d < 0 else 1
	if d == dir:
		return
	_from = _mirror()
	dir = d
	_t = 0.0 if animate and not reduced else -1.0
	set_process(_t >= 0.0)
	queue_redraw()


# Lage des Pfeils: 1 = im Uhrzeigersinn, −1 = gegen den Uhrzeigersinn (Tests)
func arrow_sign() -> int:
	return dir


func turning() -> bool:
	return _t >= 0.0


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	if _t < 0.0:
		set_process(false)
		return
	_t += delta / TURN_S
	if _t >= 1.0:
		_t = -1.0
		set_process(false)
	queue_redraw()


func _mirror() -> float:
	if _t < 0.0:
		return float(dir)
	return lerpf(_from, float(dir), smoothstep(0.0, 0.45, _t))


# Pfeilgröße (Radius) und Textgröße, aus der Kopfhöhe bzw. der Schriftstufe
func arrow_radius() -> float:
	return head_size.y * 0.40


func _font_size() -> int:
	return UiFonts.px(32)


# Breite des Inhalts (Pfeil + Abstand + Wort), zentriert in head_size
func content_width() -> float:
	var r := arrow_radius()
	var tw := UiFonts.text(800, 100.0).get_string_size(I18n.t(TEXT), HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size()).x
	return r * 2.0 + 20.0 + 18.0 + tw


func _draw() -> void:
	var r := arrow_radius()
	var cw := minf(content_width(), head_size.x)
	var x0 := (head_size.x - cw) * 0.5
	var c := Vector2(x0 + r + 10.0, head_size.y * 0.5)
	var m := _mirror()
	var spin := 0.0
	var pop := 1.0
	if _t >= 0.0:
		var e := 1.0 - pow(1.0 - _t, 3.0)
		spin = float(dir) * TAU * e
		pop = 1.0 + 0.22 * sin(PI * minf(_t / 0.6, 1.0))
	var col := UiPalette.ring_color(night)
	var halo := UiPalette.INK if night > 0.5 else UiPalette.PAPER
	var w := maxf(r * 0.30, 5.0)
	# im Uhrzeigersinn gezeichnet (Bildschirm: y nach unten, wachsender Winkel = Uhrzeigersinn), Spiegelung m kehrt ihn um
	draw_set_transform(c, spin, Vector2(m, 1.0) * pop)
	var a0 := deg_to_rad(-60.0)
	var a1 := a0 + deg_to_rad(285.0)
	var head_len := r * 0.85
	var a_cut := a1 - head_len / r * 0.55          # Bogen endet unter der Spitze
	var tip_dir := Vector2(-sin(a1), cos(a1))
	var base := Vector2(cos(a1), sin(a1)) * r
	var tip := base + tip_dir * head_len * 0.75
	var side := Vector2(cos(a1), sin(a1)) * head_len * 0.62
	var tri := PackedVector2Array([tip, base - tip_dir * head_len * 0.35 + side, base - tip_dir * head_len * 0.35 - side])
	draw_arc(Vector2.ZERO, r, a0, a_cut, 40, Color(halo, 0.75), w + 6.0, true)
	draw_colored_polygon(_grow(tri, 3.5), Color(halo, 0.75))
	draw_arc(Vector2.ZERO, r, a0, a_cut, 40, col, w, true)
	draw_colored_polygon(tri, col)
	draw_set_transform(Vector2.ZERO)
	var font := UiFonts.text(800, 100.0)
	var fs := _font_size()
	var tx := c.x + r + 18.0 + 10.0
	var ty := head_size.y * 0.5 + fs * 0.36
	var maxw := maxf(head_size.x - tx, 10.0)
	draw_string_outline(font, Vector2(tx, ty), I18n.t(TEXT), HORIZONTAL_ALIGNMENT_LEFT, maxw, fs, 6, Color(halo, 0.85))
	draw_string(font, Vector2(tx, ty), I18n.t(TEXT), HORIZONTAL_ALIGNMENT_LEFT, maxw, fs, UiPalette.ui_muted(night))


# Dreieck um d nach außen vergrößern (Umrandung der Spitze)
static func _grow(p: PackedVector2Array, d: float) -> PackedVector2Array:
	var cen := (p[0] + p[1] + p[2]) / 3.0
	var out := PackedVector2Array()
	for q in p:
		out.append(q + (q - cen).normalized() * d * 1.6)
	return out
