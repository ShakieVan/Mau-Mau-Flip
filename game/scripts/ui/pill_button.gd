class_name PillButton
extends Control
# Pillenknopf am Tisch („Sortieren“, „Rückseiten“, „Behalten“ …): Symbol und Text in einer abgerundeten Pille. Die Pille ist
# sichtbar flacher (visual_h) als die Trefferfläche, die mindestens 84 px hoch ist (≈ 48 dp auf einem Handy quer).
# Farben folgen night (Tag: Druckfarbe auf Papier, Nacht: Papier auf Nachtgrund); style "primary" = gefüllt, "alert" = rot.

signal pressed

const TOUCH_MIN := 84.0

var text := "": set = set_text
var icon_name := "": set = set_icon_name
var night := 1.0: set = set_night
var visual_h := 56.0
var style := "ghost": set = set_style        # ghost | primary | alert
var font_size := 20
var disabled := false: set = set_disabled
var big := 1.0: set = set_big            # großer Modus (Beta 1.1.1): Pille, Symbol und Trefferfläche größer

var _down := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(TOUCH_MIN, TOUCH_MIN)
	focus_mode = Control.FOCUS_NONE


func set_text(t: String) -> void:
	text = t
	_fit()


func set_icon_name(n: String) -> void:
	icon_name = n
	_fit()


func set_big(k: float) -> void:
	big = maxf(k, 1.0)
	visual_h = 56.0 * big
	_fit()


func touch_h() -> float:
	return TOUCH_MIN * big


func set_night(v: float) -> void:
	night = clampf(v, 0.0, 1.0)
	queue_redraw()


func set_style(s: String) -> void:
	style = s
	queue_redraw()


func set_disabled(d: bool) -> void:
	disabled = d
	queue_redraw()


func preferred_width() -> float:
	var f := UiFonts.text(700, 100.0)
	var w := f.get_string_size(I18n.t(text), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 44.0 * big
	if icon_name != "":
		w += 34.0 * big
	return maxf(w, touch_h())


func _fit() -> void:
	custom_minimum_size = Vector2(preferred_width(), touch_h())
	size = Vector2(maxf(size.x, custom_minimum_size.x), maxf(size.y, touch_h()))
	queue_redraw()


func visual_rect() -> Rect2:
	var w := minf(preferred_width(), size.x)
	return Rect2((size.x - w) * 0.5, (size.y - visual_h) * 0.5, w, visual_h)


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
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
	var r := visual_rect()
	if _down:
		r = r.grow(-2.0)
	var fg := UiPalette.ui_text(night)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(int(r.size.y * 0.5))
	sb.anti_aliasing = true
	match style:
		"primary":
			sb.bg_color = UiPalette.CREAM if night > 0.5 else UiPalette.INK
			fg = UiPalette.INK if night > 0.5 else UiPalette.CREAM
		"alert":
			sb.bg_color = UiPalette.ALERT
			fg = UiPalette.CREAM
		_:
			sb.bg_color = UiPalette.ui_fill(night)
			sb.border_color = UiPalette.ui_line(night)
			sb.set_border_width_all(2 if big <= 1.0 else 4)
			if big > 1.0:                # großer Modus: deckend, liegt über dem riesigen Stapel
				sb.bg_color = (UiPalette.NIGHT if night > 0.5 else UiPalette.PAPER).lerp(Color(sb.bg_color, 1.0), sb.bg_color.a)
				sb.border_color = UiPalette.ui_text(night)
	if _down:
		sb.bg_color = sb.bg_color.lerp(fg, 0.15)
	if disabled:
		fg = Color(fg, 0.45)
		sb.bg_color = Color(sb.bg_color, sb.bg_color.a * 0.5)
	draw_style_box(sb, r)
	var f := UiFonts.text(700, 100.0)
	var shown := I18n.t(text)
	var tw := f.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var content_w := tw + (34.0 * big if icon_name != "" else 0.0)
	var x := r.position.x + (r.size.x - content_w) * 0.5
	var cy := r.position.y + r.size.y * 0.5
	if icon_name != "":
		var cut := sb.bg_color if sb.bg_color.a > 0.5 else (UiPalette.NIGHT if night > 0.5 else UiPalette.PAPER)
		draw_texture_rect(UiIcons.icon(icon_name, 64 if big > 1.0 else 48, fg, cut), Rect2(x, cy - 13.0 * big, 26.0 * big, 26.0 * big), false)
		x += 34.0 * big
	draw_string(f, Vector2(x, cy + font_size * 0.36), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, fg)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_fit()
