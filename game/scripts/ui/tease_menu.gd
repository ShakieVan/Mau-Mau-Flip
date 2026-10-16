class_name TeaseMenu
extends Control
# Mau-Mau Flip (Beta 1.6.3, Easter Eggs Teil 2 „Necken“, docs/module/eastereggs2.md Abschnitt 2): kleines Necken-Menü am Gegner – eine
# Sprechblase mit Zipfel zum Avatar, Titel „Kim · 5 Karten“, darunter runde Knöpfe mit gezeichneten Bildern (Papierkugel, Schnarchen,
# Wecker, Karten ansehen) und ggf. ein Hinweis („Erst, wenn Kim eine Weile überlegt.“). Was gerade nicht geht, ist ausgegraut;
# Schnarchen/Wecker füllen bis 10 s einen Ring. Ein Tipp daneben schließt das Menü und wirkt normal weiter (die Fläche außerhalb der
# Blase gehört nicht zum Menü, _has_point). Die Lage setzt TeaseFx.place_menu; TeaseFx schließt es nach 15 s ohne Tipp (bis 1.6.6: 5 s)
# und bei Platzwechseln, ab Beta 1.6.7 nicht mehr bei Zugwechsel oder erwischbaren Plätzen (dann frischt es auf bzw. zeigt den
# „Erwischt!“-Buzzer über sich, buzzers). Tag: Papier und Druckfarbe, Nacht: dunkle Blase mit hellem Rand und leichtem Neon-Schein.
# Darunter (innere Klasse) ReactionBar: die 4 Reaktionen als runde Knöpfe am eigenen Platz (Beta 1.6.5; vorher ein Lachgesicht-Knopf mit Fächer).
# Beta 1.6.6 (Furzkissen, eastereggs2.md 12.4): unter den runden Knöpfen eine eigene Zeile „Furzkissen“ (gezeichnetes Kissen) mit zwei
# Knöpfen „Mit Namen“ (chosen "kissen_name") und „Geheim“ ("kissen_geheim"); beide grau, wenn es gerade nicht geht. Der Hinweis darf
# mehrere Zeilen haben (durch "\n" getrennt, z. B. „Erst, wenn …“ und „Das Kissen muss sich erst wieder aufpusten.“).

signal chosen(key: String)
signal closed

const BTN_R := 30.0
const CELL_W := 100.0
const PAD := 16.0
const PILL_H := 48.0                  # Beta 1.6.6: Höhe der Kissen-Knöpfe (Trefferfläche ≥ 48 px), × k
const PILL_GAP := 10.0

var seat := -1
var title := ""
var note := ""
var items: Array = []                 # [{key, label, on, progress}]
var cushion: Dictionary = {}          # Beta 1.6.6: {} = keine Kissen-Zeile, sonst {label, on, why, opts: [{key, label}]}
var night := 0.0
var k := 1.0
var idle := 0.0                       # Sekunden ohne Tipp (TeaseFx schließt nach MENU_IDLE_S = 15 s)
var tail_to := Vector2.ZERO           # Avatar relativ zur Blase
var tail_r := 30.0
var size_changed := false
var old_size := Vector2.ZERO          # Beta 1.6.7: Größe vor dem letzten set_items (TeaseFx.place_menu(keep))
var buzzers: Array = []               # Beta 1.6.7: [{rect, hit, t, fs}] „Erwischt!“-Buzzer unter der Blase (lokal), von TeaseFx gesetzt
var _press := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func set_items(new_items: Array, new_note: String, new_cushion: Dictionary = {}) -> void:
	var old := size
	old_size = old
	items = new_items
	note = new_note
	cushion = new_cushion
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
	if not cushion.is_empty():
		w = maxf(w, cushion_row_width())
	for line in note_lines():
		w = maxf(w, lf.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_n()).x)
	var h := PAD * k + _font_t() * 1.25
	if not items.is_empty():
		h += BTN_R * k * 2.0 + 10.0 * k + _font_l() * 1.3
	if not cushion.is_empty():
		h += cushion_row_height() + 8.0 * k
	h += _font_n() * 1.5 * note_lines().size()
	size = Vector2(w + PAD * 2.0 * k, h + PAD * k)


func note_lines() -> PackedStringArray:
	return PackedStringArray() if note == "" else note.split("\n", false)


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


# --- Beta 1.6.6: Kissen-Zeile [Kissenbild + „Furzkissen“] [Mit Namen] [Geheim]

func _pill_w(j: int) -> float:
	var opts: Array = cushion.get("opts", [])
	var lbl := str((opts[j] as Dictionary).get("label", "")) if j < opts.size() else ""
	return maxf(UiFonts.text(800, 100.0).get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_n()).x + 34.0 * k, 96.0 * k)


func _cushion_icon_w() -> float:
	var lw := UiFonts.text(700, 90.0).get_string_size(str(cushion.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, _font_l()).x
	return maxf(BTN_R * k * 2.0, lw + 6.0 * k)


func cushion_row_height() -> float:
	return maxf(PILL_H * k, BTN_R * k * 1.5 + 6.0 * k + _font_l() * 1.1)


func cushion_row_width() -> float:
	var w := _cushion_icon_w() + 14.0 * k
	var opts: Array = cushion.get("opts", [])
	for j in opts.size():
		w += _pill_w(j) + (PILL_GAP * k if j > 0 else 0.0)
	return w


func _cushion_top() -> float:
	var y := PAD * k + _font_t() * 1.25
	if not items.is_empty():
		y += BTN_R * k * 2.0 + 10.0 * k + _font_l() * 1.3
	return y + 4.0 * k


# Mitte des Kissenbilds (lokal)
func cushion_icon_center() -> Vector2:
	var x0 := (size.x - cushion_row_width()) * 0.5
	return Vector2(x0 + _cushion_icon_w() * 0.5, _cushion_top() + BTN_R * k * 0.75)


# Knopf j der Kissen-Zeile (lokal)
func pill_rect(j: int) -> Rect2:
	var x := (size.x - cushion_row_width()) * 0.5 + _cushion_icon_w() + 14.0 * k
	for i in j:
		x += _pill_w(i) + PILL_GAP * k
	var h := PILL_H * k
	return Rect2(Vector2(x, _cushion_top() + (cushion_row_height() - h) * 0.5), Vector2(_pill_w(j), h))


func pill_at(p: Vector2) -> int:
	if cushion.is_empty():
		return -1
	var opts: Array = cushion.get("opts", [])
	for j in opts.size():
		if pill_rect(j).grow(4.0).has_point(p):
			return j
	return -1


# Schlüssel unter p ("" = keiner) und ob er gerade geht
func key_at(p: Vector2) -> String:
	var i := button_at(p)
	if i >= 0:
		return str(items[i].key)
	var j := pill_at(p)
	if j >= 0:
		return str(((cushion.get("opts", []) as Array)[j] as Dictionary).get("key", ""))
	return ""


func key_on(key: String) -> bool:
	for it in items:
		if str(it.key) == key:
			return bool(it.get("on", false))
	for o in cushion.get("opts", []):
		if str((o as Dictionary).get("key", "")) == key:
			return bool(cushion.get("on", false))
	return false


# Beta 1.6.7: über einem „Erwischt!“-Buzzer gehört der Tipp dem Tisch (er erwischt; _input schließt das Menü wie bei jedem Tipp daneben)
func _has_point(p: Vector2) -> bool:
	for b in buzzers:
		if ((b as Dictionary).hit as Rect2).has_point(p):
			return false
	return Rect2(Vector2.ZERO, size).has_point(p)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	idle = 0.0
	var at := key_at(mb.position)
	if mb.pressed:
		_press = at
		queue_redraw()
		return
	var key := _press
	_press = ""
	queue_redraw()
	if key != "" and at == key and key_on(key):
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
	if not cushion.is_empty():
		_draw_cushion_row(dark, edge, ink)
	var lines := note_lines()
	for li in lines.size():
		var line := lines[li]
		var nw := lf.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_n()).x
		var ny := size.y - PAD * k * 0.9 - _font_n() * 1.5 * (lines.size() - 1 - li)
		draw_string(lf, Vector2((size.x - nw) * 0.5, ny), line, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_n(), muted)
	# Beta 1.6.7: wer erwischbar wurde, während das Menü offen ist, dessen Buzzer liegt sichtbar über der Blase
	for b in buzzers:
		var bd := b as Dictionary
		OpponentSeat.draw_buzzer(self, bd.rect, float(bd.t), night, bool(bd.get("red", false)), int(bd.fs))


# Beta 1.6.6: Kissen-Zeile – links das gezeichnete Kissen mit „Furzkissen“ darunter, rechts die Knöpfe „Mit Namen“ und „Geheim“
func _draw_cushion_row(dark: bool, edge: Color, ink: Color) -> void:
	var on := bool(cushion.get("on", false))
	var a := 1.0 if on else 0.38
	var lf := UiFonts.text(700, 90.0)
	var bf := UiFonts.text(800, 100.0)
	var ic := cushion_icon_center()
	TeaseFx.draw_cushion(self, ic + Vector2(-BTN_R * k * 0.14, BTN_R * k * 0.05), BTN_R * k * 0.9, 0.0, 1.0, night)
	if not on:
		draw_circle(ic, BTN_R * k * 1.05, Color(UiPalette.NIGHT_PANEL if dark else UiPalette.PAPER, 0.6))
	var label := str(cushion.get("label", ""))
	var lw := lf.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_l()).x
	draw_string(lf, Vector2(ic.x - lw * 0.5, ic.y + BTN_R * k * 0.75 + 6.0 * k + _font_l() * 0.85), label, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_l(), Color(ink, maxf(a, 0.55)))
	var opts: Array = cushion.get("opts", [])
	for j in opts.size():
		var o: Dictionary = opts[j]
		var rect := pill_rect(j)
		if _press == str(o.get("key", "")) and on:
			rect = rect.grow(-2.0 * k)
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiPalette.NIGHT_HI if dark else UiPalette.CREAM
		sb.border_color = Color(edge, a)
		sb.set_border_width_all(int(maxf(2.0, 3.0 * k)))
		sb.set_corner_radius_all(int(rect.size.y * 0.5))
		sb.anti_aliasing = true
		draw_style_box(sb, rect)
		var t := str(o.get("label", ""))
		var tw := bf.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_n()).x
		draw_string(bf, Vector2(rect.get_center().x - tw * 0.5, rect.get_center().y + _font_n() * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_n(), Color(ink, maxf(a, 0.45)))


# Bild mit Deckkraft (ausgegraut): über ein Zwischenbild wäre teuer – die Bilder zeichnen deckend, darüber ein Schleier in der Knopffarbe
func modulate_icon(icon: String, c: Vector2, s: float, mod: Color) -> void:
	TeaseFx.draw_icon(self, icon, c, s, 0.0)
	if mod.a < 0.99:
		draw_circle(c, BTN_R * k, Color(UiPalette.NIGHT_HI if night > 0.5 else UiPalette.CREAM, 1.0 - mod.a))


# ================================================================= Reaktionsknöpfe am eigenen Platz

# Beta 1.6.5 (Nutzerwunsch nach der Familienrunde): Reihenfolge der Knöpfe (TeaseRules.FX_REACTS bleibt die Liste des Protokolls)
const REACT_ORDER := ["lachen", "klatschen", "daumen", "schreck"]
const REACT_BTN_R := 24.0             # Knopfradius (Trefferfläche ≥ 48 px), großer Modus × k
const REACT_ICON := 0.76              # Bildgröße relativ zum Knopfradius (Fluent-Emoji-Bild, TeaseFx.draw_reaction)


# Beta 1.6.5: die 4 Reaktionen als eigene runde Knöpfe (ein Tipp = senden), statt hinter einem Lachgesicht-Knopf im Fächer. Lage
# setzt TeaseFx._sync_reactions (centers, r): neben dem eigenen Namen, im großen Modus in der Zeile „Du“ vor der Kartenzahl.
# Während der Sperrzeit (eigener Eimer leer, fx_no "rate") sind alle ausgegraut, nach fx_no "rate" wackeln sie kurz.
class ReactionBar:
	extends Control
	signal chosen(r: String)

	var centers: Array[Vector2] = []  # Mitte je Knopf (lokale Koordinaten; das Steuerelement deckt den ganzen Tisch)
	var r := REACT_BTN_R
	var squash := 1.0                 # großer Modus: Zeile klappt beim Richtungswechsel kurz zusammen (OpponentSeat.flip_y)
	var gray := false
	var night := 0.0
	var reduced := false
	var dim := false                  # fx_no "rate": kurz blasser
	var _shake := 0.0                 # Wackeln nach fx_no "rate" (Sekunden, läuft rückwärts)
	var _press := -1

	func _init() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		tooltip_text = "Reaktion"

	# Namen für Hilfetexte (Barrierefreiheit; die Bilder selbst haben keinen Text)
	static func label_of(name_r: String) -> String:
		match name_r:
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
		return label_of(REACT_ORDER[i]) if i >= 0 else I18n.t("Reaktion")

	# Trefferfläche: der Kreis plus etwas Rand (höchstens bis zur halben Lücke zum Nachbarn)
	func hit_r() -> float:
		var pad := 6.0
		if centers.size() >= 2:
			var gap := centers[0].distance_to(centers[1]) - 2.0 * r
			pad = clampf(gap * 0.5, 0.0, 6.0)
		return r + pad

	func item_at(p: Vector2) -> int:
		if not visible:
			return -1
		for i in centers.size():
			if p.distance_to(centers[i]) <= hit_r():
				return i
		return -1

	func bounds() -> Rect2:
		if centers.is_empty():
			return Rect2()
		var out := Rect2(centers[0] - Vector2.ONE * (r + 4.0), Vector2.ONE * (r + 4.0) * 2.0)
		for c in centers:
			out = out.merge(Rect2(c - Vector2.ONE * (r + 4.0), Vector2.ONE * (r + 4.0) * 2.0))
		return out

	func _has_point(p: Vector2) -> bool:
		return item_at(p) >= 0

	func nudge() -> void:
		_shake = 0.0 if reduced else 0.32
		queue_redraw()

	func _process(delta: float) -> void:
		if _shake > 0.0:
			_shake = maxf(0.0, _shake - delta)
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		accept_event()
		var i := item_at(mb.position)
		if mb.pressed:
			_press = i
			queue_redraw()
			return
		var was := _press
		_press = -1
		queue_redraw()
		if i >= 0 and i == was and not gray:
			chosen.emit(REACT_ORDER[i])

	func _draw() -> void:
		var dark := night > 0.5
		var edge := UiPalette.MOON if dark else UiPalette.INK
		var fill := UiPalette.NIGHT_HI if dark else UiPalette.CREAM
		var dx := sin(_shake * 60.0) * 5.0 * (_shake / 0.32)
		for i in centers.size():
			var c := centers[i] + Vector2(dx, 0.0)
			var rr := r * (0.9 if _press == i and not gray else 1.0)
			draw_set_transform(c, 0.0, Vector2(1.0, maxf(squash, 0.02)))
			if dark:
				draw_circle(Vector2.ZERO, rr + 8.0, Color(UiPalette.RING, 0.16))
			draw_circle(Vector2.ZERO, rr + 3.0, edge)
			draw_circle(Vector2.ZERO, rr, fill)
			TeaseFx.draw_icon(self, REACT_ORDER[i], Vector2.ZERO, rr * REACT_ICON, 0.0)
			if gray:
				draw_circle(Vector2.ZERO, rr + 0.5, Color(fill, 0.66 if dim else 0.62))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
