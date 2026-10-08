class_name DiscardBrowser
extends Node2D
# „Ablage durchsehen“ (Beta 1.0.1, BETA1_PLAN Abschnitt Sichten: view.discard_log). Liegt in der Tischwelt an der Ablage
# (Ursprung = Mitte der Ablage). Tipp auf die Ablage schiebt die oberste noch nicht verschobene Karte weich auf einen
# Seitenstapel daneben, Tipp auf den Seitenstapel schiebt eine zurück, Tipp irgendwo sonst schiebt alle zurück. Die oberste
# Karte des Seitenstapels zeigt „von <Name>“ (bei Leger -1 „Startkarte“), bei Jokern die Wunschfarbe, darüber den Zähler
# „3 von 27“. Ändert sich das Protokoll (jemand legt, Flip, Mischen), springt alles sofort zurück (set_log, close_now).
# Solange etwas verschoben ist (is_open), blendet der Tisch seine eigene Ablage aus; dieser Knoten zeigt dann an der Ablage die
# nächste noch liegende Karte. Verdeckte Glücksspiel-Einsätze (h) erscheinen nur als neutrale Rückseite.

signal opened_changed(open: bool)

const CARD_W := 116.0
const SIDE := Vector2(CARD_W * 1.32, -6.0)    # Seitenstapel relativ zur Ablage
const LAYER := Vector2(2.2, -2.6)             # Versatz je Karte im Seitenstapel
const MAX_LAYERS := 4                         # sichtbare Lagen im Seitenstapel
const SLIDE := 0.30                           # Schiebedauer in s (reduziert kürzer)

var night := 0.0: set = set_night
var reduced := false
var names: Array = []          # Spielernamen je Platz
var entries: Array = []        # view.discard_log (unten → oben)
var moved := 0                 # so viele Karten liegen auf dem Seitenstapel

var _sig := ""
var _side: Array[CardView] = []    # Seitenstapel, unterste zuerst (= zuletzt verschobene zuoberst)
var _rest: CardView                # nächste noch liegende Karte an der Ablage
var _labels: Node2D
var _anim := 0                     # laufende Rückschiebungen
var _tweens: Array[Tween] = []
var card_w := CARD_W                # Kartenbreite (großer Modus: wie die riesige Ablage)
var side_x := SIDE.x                 # Seitenstapel relativ zur Ablage (großer Modus: links über dem Nachziehstapel)
var labels_inside := false          # großer Modus: Beschriftung auf der oberen Kartenhälfte (unten liegt die Hand)


func _init() -> void:
	_labels = Node2D.new()
	_labels.z_index = 2
	_labels.draw.connect(_draw_labels)
	add_child(_labels)


func set_night(v: float) -> void:
	night = clampf(v, 0.0, 1.0)
	var day := night < 0.5
	for c in _side:
		c.day = day
	if _rest != null:
		_rest.day = day
	_labels.queue_redraw()


func is_open() -> bool:
	return moved > 0 or _anim > 0


func total() -> int:
	return entries.size()


# Neues Protokoll aus der Sicht. Andere Ablage → alles sofort zurück. true = zurückgesetzt.
func set_log(log_entries: Array, player_names: Array) -> bool:
	names = player_names.duplicate()
	var sig := JSON.stringify(log_entries)
	if sig == _sig:
		_labels.queue_redraw()
		return false
	_sig = sig
	entries = log_entries.duplicate(true)
	var was := is_open()
	close_now()
	return was


# Alles sofort zurück (ohne Animation), z. B. wenn jemand legt.
func close_now() -> void:
	var was := is_open()
	for t in _tweens:
		if t.is_valid():
			t.kill()
	_tweens.clear()
	for c in get_children():
		if c is CardView and c != _rest:
			c.queue_free()
	for c in _side:
		c.queue_free()
	_side.clear()
	moved = 0
	_anim = 0
	_set_rest(-1)
	_labels.queue_redraw()
	if was:
		opened_changed.emit(false)


# Tipp in Weltkoordinaten der Ablage-Elternebene (lokal: Ursprung = Ablage). true = verbraucht.
func handle_tap(local_pos: Vector2) -> bool:
	if moved > 0 and _card_rect(_side_pos(moved - 1)).grow(8.0).has_point(local_pos):
		step_back()
		return true
	if _card_rect(Vector2.ZERO).grow(6.0).has_point(local_pos):
		if moved < entries.size():
			step_forward()
		return true
	if moved > 0:
		close_all()
	return false


# Oberste noch liegende Karte auf den Seitenstapel schieben.
func step_forward() -> void:
	if moved >= entries.size():
		return
	var idx := entries.size() - 1 - moved
	var c := _make_card(idx)
	add_child(c)
	move_child(c, _labels.get_index())
	c.position = Vector2.ZERO
	_side.append(c)
	moved += 1
	if moved == 1:
		opened_changed.emit(true)
	_set_rest(entries.size() - 1 - moved)
	var k := float(posmod(idx * 37, 9) - 4)
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_track(tw)
	tw.tween_property(c, "position", _side_pos(moved - 1), _dur())
	tw.tween_property(c, "rotation", deg_to_rad(k), _dur())
	c.elevation = 1.0
	tw.chain().tween_property(c, "elevation", 0.0, 0.12)
	_restack()
	_labels.queue_redraw()


# Eine Karte vom Seitenstapel zurück auf die Ablage.
func step_back() -> void:
	if moved <= 0:
		return
	var c: CardView = _side.pop_back()
	moved -= 1
	_slide_home(c, true)
	_restack()
	_labels.queue_redraw()


# Alle zurück (weich).
func close_all() -> void:
	if moved <= 0:
		return
	var cards := _side.duplicate()
	_side.clear()
	moved = 0
	cards.reverse()
	var i := 0
	for c in cards:
		_slide_home(c, i == cards.size() - 1, 0.03 * float(mini(i, 6)))
		i += 1
	_labels.queue_redraw()


func _slide_home(c: CardView, becomes_rest: bool, delay := 0.0) -> void:
	_anim += 1
	c.visible = true
	move_child(c, _labels.get_index())
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_track(tw)
	tw.tween_property(c, "position", Vector2.ZERO, _dur() * 0.85).set_delay(delay)
	tw.tween_property(c, "rotation", 0.0, _dur() * 0.85).set_delay(delay)
	tw.chain().tween_callback(func() -> void:
		c.queue_free()
		_anim = maxi(_anim - 1, 0)
		if becomes_rest or moved == 0:
			_set_rest(entries.size() - 1 - moved)
		if not is_open():
			opened_changed.emit(false))


func _track(tw: Tween) -> void:
	_tweens = _tweens.filter(func(t: Tween) -> bool: return t.is_valid())
	_tweens.append(tw)


func _dur() -> float:
	return SLIDE * (0.4 if reduced else 1.0)


func _side_pos(i: int) -> Vector2:
	return Vector2(side_x, SIDE.y) + LAYER * float(mini(i, MAX_LAYERS - 1))


func _card_rect(center: Vector2) -> Rect2:
	var sz := Vector2(card_w, card_w * CardView.ASPECT)
	return Rect2(center - sz * 0.5, sz)


# nur die obersten Lagen zeigen
func _restack() -> void:
	for i in _side.size():
		_side[i].visible = i >= _side.size() - MAX_LAYERS


func _make_card(idx: int) -> CardView:
	var e: Dictionary = entries[idx]
	var c := CardView.new()
	c.width = card_w
	var f := str(e.get("f", ""))
	c.setup(-1, f if f != "" else CardTextures.BACK, "", true)
	c.day = night < 0.5
	return c


# Nächste noch liegende Karte an der Ablage (idx < 0: keine bzw. Browser zu → Tisch zeigt seine Ablage).
func _set_rest(idx: int) -> void:
	if _rest != null:
		_rest.queue_free()
		_rest = null
	if idx < 0 or not is_open():
		return
	_rest = _make_card(idx)
	add_child(_rest)
	move_child(_rest, 0)


# ------------------------------------------------------------------ Beschriftung

func entry_label(e: Dictionary) -> String:
	var s := int(e.get("s", -1))
	var who := I18n.t("Startkarte")
	if s >= 0:
		who = I18n.t("von %s") % (str(names[s]) if s < names.size() else I18n.t("Platz %d") % (s + 1))
	if bool(e.get("h", false)):
		who += " · " + I18n.t("verdeckt")
	return who


func counter_text() -> String:
	return I18n.t("%d von %d") % [moved, entries.size()]


func _draw_labels() -> void:
	if moved <= 0:
		return
	var e: Dictionary = entries[entries.size() - moved]
	var top := _side_pos(moved - 1)
	var sz := Vector2(card_w, card_w * CardView.ASPECT)
	var f := UiFonts.text(800, 90.0)
	var bg := UiPalette.PAPER if night > 0.5 else UiPalette.INK
	var fg := UiPalette.INK if night > 0.5 else UiPalette.PAPER
	# unter dem Stapel: Leger, Wunschfarbe, Zähler (darüber sitzen oft Gegner)
	# Größen folgen der Einstellung „Schriftgröße“ (UiFonts.px)
	var lk := 1.5 if labels_inside else 1.0
	var step := float(UiFonts.px(19 * lk)) + 15.0 * lk
	var y := top.y + sz.y * 0.5 + 20.0
	if labels_inside:
		y = top.y - sz.y * 0.5 + sz.y * 0.30
	_pill(f, entry_label(e), Vector2(top.x, y), UiFonts.px(19 * lk), bg, fg, Color(0, 0, 0, 0))
	var c := str(e.get("c", ""))
	if c != "":
		_pill(f, I18n.t("Wunsch: %s") % I18n.t(UiPalette.color_name(c)), Vector2(top.x, y + step), UiFonts.px(18 * lk), bg, fg, UiPalette.fill(c))
		if not labels_inside:
			# mit Wunschfarbe sitzt der Zähler auf der Oberkante der Karte (sonst berührt er bei „Sehr groß“ die Hinweisleiste)
			_pill(f, counter_text(), Vector2(top.x, top.y - sz.y * 0.5 + 4.0), UiFonts.px(17), Color(bg, 0.9), fg, Color(0, 0, 0, 0))
			return
		y += step
	_pill(f, counter_text(), Vector2(top.x, y + step), UiFonts.px(17 * lk), Color(bg, 0.75), fg, Color(0, 0, 0, 0))


# Pille mit Mittelpunkt at; dot.a > 0 zeichnet links einen Farbpunkt
func _pill(f: Font, txt: String, at: Vector2, fs: int, bg: Color, fg: Color, dot: Color) -> void:
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var extra := 18.0 if dot.a > 0.0 else 0.0
	var h := float(fs) + 12.0
	var r := Rect2(at.x - (tw + extra) * 0.5 - 10.0, at.y - h * 0.5, tw + extra + 20.0, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(h * 0.5))
	sb.anti_aliasing = true
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 3
	_labels.draw_style_box(sb, r)
	var x := r.position.x + 10.0
	if dot.a > 0.0:
		_labels.draw_circle(Vector2(x + 6.0, at.y), 6.5, dot)
		_labels.draw_arc(Vector2(x + 6.0, at.y), 6.5, 0.0, TAU, 20, Color(fg, 0.6), 1.2, true)
		x += extra
	_labels.draw_string(f, Vector2(x, at.y + float(fs) * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fg)


# Großer Modus (Beta 1.1.1): Karten so groß wie die Ablage, Seitenstapel links über dem Nachziehstapel, Beschriftung auf der Karte.
# Nur bei geschlossenem Browser (sonst erst alles zurück).
func set_big(on: bool, w: float) -> void:
	if is_equal_approx(w, card_w) and labels_inside == on:
		return
	close_now()
	card_w = w
	side_x = -(w + 22.0) if on else SIDE.x
	labels_inside = on
	_labels.queue_redraw()
