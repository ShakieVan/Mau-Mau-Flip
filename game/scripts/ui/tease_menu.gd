class_name TeaseMenu
extends Control
# Mau-Mau Flip (Beta 1.6.3, Easter Eggs Teil 2 „Necken“, docs/module/eastereggs2.md Abschnitt 2): kleines Necken-Menü am Gegner – eine
# Sprechblase mit Zipfel zum Avatar, Titel „Kim · 5 Karten“, darunter runde Knöpfe mit gezeichneten Bildern (Papierkugel, Schnarchen,
# Wecker, Karten ansehen) und ggf. ein Hinweis („Erst, wenn Kim eine Weile überlegt.“). Was gerade nicht geht, ist ausgegraut;
# Schnarchen/Wecker füllen bis 10 s einen Ring. Ein Tipp daneben schließt das Menü und wirkt normal weiter (die Fläche außerhalb der
# Blase gehört nicht zum Menü, _has_point). Die Lage setzt TeaseFx.place_menu; TeaseFx schließt es nach 5 s ohne Tipp, bei Zugwechsel,
# erwischbaren Plätzen und Platzwechseln. Tag: Papier und Druckfarbe, Nacht: dunkle Blase mit hellem Rand und leichtem Neon-Schein.
# Darunter (innere Klasse) ReactionPicker: runder Knopf mit Lachgesicht am eigenen Platz, ein Tipp fächert 4 Reaktionen auf.

signal chosen(key: String)
signal closed

const BTN_R := 30.0
const CELL_W := 100.0
const PAD := 16.0

var seat := -1
var title := ""
var note := ""
var items: Array = []                 # [{key, label, on, progress}]
var night := 0.0
var k := 1.0
var idle := 0.0                       # Sekunden ohne Tipp (TeaseFx schließt nach 5 s)
var tail_to := Vector2.ZERO           # Avatar relativ zur Blase
var tail_r := 30.0
var size_changed := false
var _press := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func set_items(new_items: Array, new_note: String) -> void:
	var old := size
	items = new_items
	note = new_note
	relayout()
	size_changed = not size.is_equal_approx(old)
	queue_redraw()


func _font_t() -> int:
	return int(UiFonts.size("zeile") * k)


func _font_l() -> int:
	return int(UiFonts.size("mini") * k)


func _font_n() -> int:
	return int(UiFonts.size("klein") * k)


func relayout() -> void:
	var tf := UiFonts.text(800, 100.0)
	var lf := UiFonts.text(700, 90.0)
	var w := tf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_t()).x
	var cell := CELL_W * k
	for it in items:
		cell = maxf(cell, lf.get_string_size(str(it.label), HORIZONTAL_ALIGNMENT_LEFT, -1, _font_l()).x + 12.0 * k)
	w = maxf(w, cell * items.size())
	if note != "":
		w = maxf(w, lf.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_n()).x)
	var h := PAD * k + _font_t() * 1.25
	if not items.is_empty():
		h += BTN_R * k * 2.0 + 10.0 * k + _font_l() * 1.3
	if note != "":
		h += _font_n() * 1.5
	size = Vector2(w + PAD * 2.0 * k, h + PAD * k)


# Mitte des Knopfs i (lokale Koordinaten)
func button_center(i: int) -> Vector2:
	var n := items.size()
	var cell := (size.x - PAD * 2.0 * k) / maxf(n, 1)
	var y := PAD * k + _font_t() * 1.25 + BTN_R * k + 4.0 * k
	return Vector2(PAD * k + cell * (i + 0.5), y)


func button_at(p: Vector2) -> int:
	for i in items.size():
		if p.distance_to(button_center(i)) <= BTN_R * k + 10.0 * k:
			return i
	return -1


func _has_point(p: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(p)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	idle = 0.0
	var i := button_at(mb.position)
	if mb.pressed:
		_press = str(items[i].key) if i >= 0 else ""
		queue_redraw()
		return
	var key := _press
	_press = ""
	queue_redraw()
	if i >= 0 and str(items[i].key) == key and bool(items[i].get("on", false)):
		chosen.emit(key)


# Tipp daneben: Menü zu, der Tipp wirkt normal weiter (nicht verbraucht)
func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or not is_visible_in_tree():
		return
	var local := get_global_transform_with_canvas().affine_inverse() * mb.position
	if not _has_point(local):
		closed.emit()


func _draw() -> void:
	var dark := night > 0.5
	var fill := UiPalette.NIGHT_PANEL if dark else UiPalette.PAPER
	var edge := UiPalette.MOON if dark else UiPalette.INK
	var ink := UiPalette.MOON if dark else UiPalette.INK
	var muted := UiPalette.ui_muted(night)
	var rect := Rect2(Vector2.ZERO, size)
	# Zipfel zum Avatar (vom nächsten Punkt des Randes aus)
	var tip := tail_to
	var dir := (tip - rect.get_center())
	var tail_pts := PackedVector2Array()
	if dir.length() > tail_r + 6.0:
		var tip_p := tip - dir.normalized() * tail_r
		var base := Vector2(clampf(tip_p.x, 20.0 * k, size.x - 20.0 * k), clampf(tip_p.y, 20.0 * k, size.y - 20.0 * k))
		var n := (tip_p - base).normalized().orthogonal() * 11.0 * k
		if not rect.has_point(tip_p):
			tail_pts = PackedVector2Array([base + n, tip_p, base - n])
	if dark:
		for i in 3:
			var g := StyleBoxFlat.new()
			g.bg_color = Color(0, 0, 0, 0)
			g.draw_center = false
			g.border_color = Color(UiPalette.RING, 0.12 - i * 0.03)
			g.set_border_width_all(int(4 + i * 3))
			g.set_corner_radius_all(int(20 * k + i * 3))
			g.anti_aliasing = true
			draw_style_box(g, rect.grow(3.0 + i * 3.0))
	if tail_pts.size() == 3:
		draw_colored_polygon(tail_pts, edge)
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	sb.set_border_width_all(int(maxf(2.0, 3.0 * k)))
	sb.set_corner_radius_all(int(18 * k))
	sb.anti_aliasing = true
	draw_style_box(sb, rect)
	if tail_pts.size() == 3:
		var inner := PackedVector2Array([tail_pts[0].lerp(tail_pts[1], 0.12), tail_pts[1].lerp(tail_pts[0].lerp(tail_pts[2], 0.5), 0.3), tail_pts[2].lerp(tail_pts[1], 0.12)])
		draw_colored_polygon(inner, fill)
	var tf := UiFonts.text(800, 100.0)
	var lf := UiFonts.text(700, 90.0)
	var tw := tf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_t()).x
	draw_string(tf, Vector2((size.x - tw) * 0.5, PAD * k + _font_t() * 0.9), title, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_t(), ink)
	for i in items.size():
		var it: Dictionary = items[i]
		var c := button_center(i)
		var on := bool(it.get("on", false))
		var a := 1.0 if on else 0.38
		var r := BTN_R * k * (0.92 if _press == str(it.key) and on else 1.0)
		draw_circle(c, r + 3.0, Color(edge, a))
		draw_circle(c, r, Color(UiPalette.CREAM if not dark else UiPalette.NIGHT_HI, 1.0))
		var prog := float(it.get("progress", 1.0))
		if prog < 0.999:
			draw_arc(c, r + 6.0 * k, -PI * 0.5, -PI * 0.5 + TAU * clampf(prog, 0.0, 1.0), 40, Color(UiPalette.TURN, 0.95), 4.0 * k, true)
		var icon: String = {"ball": "ball", "snore": "snore", "alarm": "alarm", "backs": "backs"}.get(str(it.key), "ball")
		var mod := Color(1, 1, 1, a)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		modulate_icon(icon, c, r * 0.62, mod)
		var label := str(it.label)
		var lw := lf.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_l()).x
		draw_string(lf, Vector2(c.x - lw * 0.5, c.y + r + 8.0 * k + _font_l() * 0.85), label, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_l(), Color(ink, maxf(a, 0.55)))
	if note != "":
		var nw := lf.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_n()).x
		draw_string(lf, Vector2((size.x - nw) * 0.5, size.y - PAD * k * 0.9), note, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_n(), muted)


# Bild mit Deckkraft (ausgegraut): über ein Zwischenbild wäre teuer – die Bilder zeichnen deckend, darüber ein Schleier in der Knopffarbe
func modulate_icon(icon: String, c: Vector2, s: float, mod: Color) -> void:
	TeaseFx.draw_icon(self, icon, c, s, 0.0)
	if mod.a < 0.99:
		draw_circle(c, BTN_R * k, Color(UiPalette.NIGHT_HI if night > 0.5 else UiPalette.CREAM, 1.0 - mod.a))


# ================================================================= Reaktionsknopf mit Fächer

class ReactionPicker:
	extends Control
	signal chosen(r: String)
	signal dismissed                   # Beta 1.6.3: Tipp daneben hat den Fächer geschlossen (TeaseFx: derselbe Tipp öffnet nicht gleich wieder)

	const BTN_R := 26.0
	const ITEM_R := 27.0
	const FAN_R := 84.0

	var center := Vector2.ZERO        # Mitte des Knopfs (lokale Koordinaten; Steuerelement deckt den ganzen Tisch)
	var open := false
	var gray := false
	var night := 0.0
	var k := 1.0
	var big := false
	var reduced := false
	var dim := false                  # Beta 1.6.3: Tisch bzw. eigener Eimer gerade voll (fx_no "rate"): auch der Knopf selbst blass
	var _shake := 0.0                 # Beta 1.6.3: Wackeln nach fx_no "rate" (Sekunden, läuft rückwärts)
	var _open_t := 0.0
	var _press := ""

	func _init() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		tooltip_text = "Reaktion"

	# Namen für Hilfetexte (Barrierefreiheit; die Bilder selbst haben keinen Text)
	static func label_of(r: String) -> String:
		match r:
			"lachen":
				return I18n.t("Lachen")
			"schreck":
				return I18n.t("Schreck")
			"klatschen":
				return I18n.t("Klatschen")
			"daumen":
				return I18n.t("Daumen hoch")
		return I18n.t("Reaktion")

	func _get_tooltip(at_position: Vector2) -> String:
		var i := item_at(at_position)
		return label_of(TeaseRules.FX_REACTS[i]) if i >= 0 else I18n.t("Reaktion")

	func toggle() -> void:
		open = not open
		_open_t = 0.0
		queue_redraw()

	# Lage der Reaktion i: nach oben aufgefächert, im großen Modus nach links (die Zeile „Du“ steht rechts in der Liste)
	func item_center(i: int) -> Vector2:
		var angles := [228.0, 264.0, 300.0, 336.0] if not big else [125.0, 158.0, 202.0, 235.0]
		var a := deg_to_rad(float(angles[i]))
		var u := 1.0 if reduced else clampf(_open_t / 0.18, 0.0, 1.0)
		return center + Vector2(cos(a), sin(a)) * FAN_R * k * (0.4 + 0.6 * u)

	func item_at(p: Vector2) -> int:
		if not open:
			return -1
		for i in TeaseRules.FX_REACTS.size():
			if p.distance_to(item_center(i)) <= ITEM_R * k + 6.0:
				return i
		return -1

	func bounds() -> Rect2:
		var r := Rect2(center - Vector2.ONE * (BTN_R * k + 4.0), Vector2.ONE * (BTN_R * k + 4.0) * 2.0)
		if open:
			for i in TeaseRules.FX_REACTS.size():
				r = r.merge(Rect2(item_center(i) - Vector2.ONE * ITEM_R * k, Vector2.ONE * ITEM_R * k * 2.0))
		return r

	func _has_point(p: Vector2) -> bool:
		if not visible:
			return false
		return p.distance_to(center) <= BTN_R * k + 8.0 or item_at(p) >= 0

	# Beta 1.6.3: kurzes Wackeln (fx_no "rate"), damit eine Ablehnung auch bei schon geschlossenem Fächer bzw. Menü sichtbar wird
	func nudge() -> void:
		_shake = 0.0 if reduced else 0.32
		queue_redraw()

	func _process(delta: float) -> void:
		if open and _open_t < 0.3:
			_open_t += delta
			queue_redraw()
		if _shake > 0.0:
			_shake = maxf(0.0, _shake - delta)
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		accept_event()
		var i := item_at(mb.position)
		var on_btn := mb.position.distance_to(center) <= BTN_R * k + 8.0
		if mb.pressed:
			_press = TeaseRules.FX_REACTS[i] if i >= 0 else ("btn" if on_btn else "")
			queue_redraw()
			return
		var key := _press
		_press = ""
		if key == "btn" and on_btn:
			toggle()
		elif i >= 0 and key == TeaseRules.FX_REACTS[i]:
			if not gray:
				chosen.emit(key)
				open = false
		queue_redraw()

	# Tipp daneben: Fächer zu (nicht verbraucht)
	func _input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb == null or not mb.pressed or not open or not is_visible_in_tree():
			return
		var local := get_global_transform_with_canvas().affine_inverse() * mb.position
		if not _has_point(local):
			open = false
			queue_redraw()
			dismissed.emit()

	func _draw() -> void:
		var dark := night > 0.5
		var edge := UiPalette.MOON if dark else UiPalette.INK
		var fill := UiPalette.NIGHT_HI if dark else UiPalette.CREAM
		var r := BTN_R * k * (0.92 if _press == "btn" else 1.0)
		var bc := center + Vector2(sin(_shake * 60.0) * 5.0 * k * (_shake / 0.32), 0.0)
		if dark:
			draw_circle(bc, r + 9.0, Color(UiPalette.RING, 0.16))
		draw_circle(bc, r + 3.0, edge)
		draw_circle(bc, r, fill)
		TeaseFx.draw_icon(self, "smile", bc, r * 0.66, 0.0)
		if dim:
			draw_circle(bc, r, Color(fill, 0.62))
		if not open:
			return
		for i in TeaseRules.FX_REACTS.size():
			var name_r: String = TeaseRules.FX_REACTS[i]
			var c := item_center(i)
			var ir := ITEM_R * k * (0.9 if _press == name_r else 1.0)
			draw_circle(c, ir + 3.0, edge)
			draw_circle(c, ir, fill)
			TeaseFx.draw_icon(self, name_r, c, ir * 0.66, 0.0)
			if gray:
				draw_circle(c, ir, Color(fill, 0.62))
