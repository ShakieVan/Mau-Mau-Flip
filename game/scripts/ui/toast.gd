class_name Toast
extends Control
# Hinweisleiste und kurze Meldungen. Die Leiste über der Hand zeigt hints.text der Sicht („Du bist dran.“): am Zug
# hervorgehoben (wie im Entwurf: Papierpille), sonst zurückhaltend. Meldungen (Ablehnung, Verbindung …) erscheinen darüber,
# stapeln sich und verschwinden nach einigen Sekunden. Nimmt keine Eingaben an.

const HINT_H := 40.0
const TOAST_H := 46.0

var night := 1.0: set = set_night
var hint_y := 513.0                   # Mitte der Hinweisleiste (Basis 720 px Höhe)
var hint := ""
var highlight := false
var opaque := false                   # großer Modus: Leiste liegt über der Ablage, darum deckender Grund
var _toasts: Array[Dictionary] = []   # {text, kind, t, life}
var _hint_pop := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_night(v: float) -> void:
	night = v
	queue_redraw()


func show_hint(text: String, my_turn := false) -> void:
	if text != hint or my_turn != highlight:
		_hint_pop = 1.0 if my_turn and (text != hint or not highlight) else 0.0
	hint = text
	highlight = my_turn
	queue_redraw()


# kind: info | warn | error
func toast(raw_text: String, kind := "info", life := 2.8) -> void:
	var text := I18n.t(raw_text)   # deutsche msgid ohne Platzhalter → aktuelle Sprache (Formatstrings übersetzt der Aufrufer)
	for t in _toasts:
		if t["text"] == text:
			t["t"] = 0.0          # gleiche Meldung nicht doppelt, nur verlängern
			return
	_toasts.append({"text": text, "kind": kind, "t": 0.0, "life": life})
	if _toasts.size() > 3:
		_toasts.pop_front()
	queue_redraw()


func active_toasts() -> int:
	return _toasts.size()


func _process(delta: float) -> void:
	var changed := _hint_pop > 0.0
	_hint_pop = maxf(_hint_pop - delta * 3.0, 0.0)
	for t in _toasts:
		t["t"] = float(t["t"]) + delta
		changed = true
	_toasts.assign(_toasts.filter(func(t: Dictionary) -> bool: return float(t["t"]) < float(t["life"])))
	if changed:
		queue_redraw()


func _pill(center: Vector2, text: String, font: Font, fs: int, bg: Color, fg: Color, h: float, border := Color(0, 0, 0, 0)) -> void:
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	# Zu lange Texte (Sprüche, große Schrift, großer Modus mit Skalierung) schrumpfen, statt über den Rand zu laufen
	var avail := size.x / maxf(scale.x, 0.01) - 40.0 - 24.0
	if size.x > 0.0 and tw > avail and avail > 80.0:
		fs = maxi(int(float(fs) * avail / tw), 12)
		tw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var r := Rect2(center.x - tw * 0.5 - 20.0, center.y - h * 0.5, tw + 40.0, h)
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0.0)
	shadow.shadow_color = Color(0, 0, 0, 0.3)
	shadow.shadow_size = 10
	shadow.shadow_offset = Vector2(0, 4)
	shadow.set_corner_radius_all(int(h * 0.5))
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(h * 0.5))
	sb.anti_aliasing = true
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(2)
	if bg.a > 0.6:
		draw_style_box(shadow, r)
	draw_style_box(sb, r)
	draw_string(font, Vector2(center.x - tw * 0.5, center.y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fg)


# Höhen wachsen mit der Schriftgröße (UiFonts)
func hint_h() -> float:
	return maxf(HINT_H, UiFonts.size("hinweisleiste") + 18.0)


func toast_h() -> float:
	return maxf(TOAST_H, UiFonts.size("text") + 22.0)


func _draw() -> void:
	var cx := size.x * 0.5
	var f := UiFonts.text(700, 100.0)
	if hint != "":
		var s := 1.0 + 0.12 * sin(_hint_pop * PI)
		draw_set_transform(Vector2(cx, hint_y) * (1.0 - s), 0.0, Vector2(s, s))
		if highlight:
			_pill(Vector2(cx, hint_y), hint, f, UiFonts.size("hinweisleiste"), UiPalette.CREAM if night > 0.5 else UiPalette.INK, UiPalette.INK if night > 0.5 else UiPalette.CREAM, hint_h())
		else:
			var fill := UiPalette.ui_fill(night)
			if opaque:
				fill = UiPalette.INK if night > 0.5 else UiPalette.CREAM
			_pill(Vector2(cx, hint_y), hint, f, UiFonts.size("hinweisleiste") - 1, fill, UiPalette.ui_text(night), hint_h() - 4.0, UiPalette.ui_line(night))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var y := hint_y - hint_h() * 0.5 - 14.0 - toast_h() * 0.5
	for i in range(_toasts.size() - 1, -1, -1):
		var t: Dictionary = _toasts[i]
		var age := float(t["t"])
		var life := float(t["life"])
		var a := clampf(minf(age / 0.18, (life - age) / 0.35), 0.0, 1.0)
		var bg := UiPalette.INK if night > 0.5 else UiPalette.CREAM
		bg = Color(bg, 0.94 * a)
		var fg := Color(UiPalette.PAPER if night > 0.5 else UiPalette.INK, a)
		var border := Color(0, 0, 0, 0)
		match str(t["kind"]):
			"warn":
				border = Color(UiPalette.TURN, a)
			"error":
				border = Color(UiPalette.ALERT, a)
		_pill(Vector2(cx, y + (1.0 - a) * 10.0), str(t["text"]), f, UiFonts.size("text"), bg, fg, toast_h(), border)
		y -= toast_h() + 8.0
