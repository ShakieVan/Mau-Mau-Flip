class_name OpponentSeat
extends Node2D
# Ein Mitspieler am Tisch (06 Abschnitt 3.3): Kopfzeile mit Avatar, Name und Kartenzahl, darunter der Mini-Fächer seiner für
# alle sichtbaren Rückseiten (sortiert geliefert, Abschnitt 2.3). Rückseiten verdeckt → neutrale Rückseite „rueckseite“.
# Hat er nur noch 1 Karte, wird deren Rückseite groß gezeigt. Ab 7 Spielern (compact) ein Abzeichen mit Farbbalken statt Fächer.
# Ursprung = Avatarmitte der Kopfzeile. Textfarben folgen night (0 Tag/Papier … 1 Nacht).

const AVATAR_R := 27.0
const AVATAR_R_COMPACT := 21.0
const BAR_W := 150.0
const BAR_H := 24.0
const SPECIAL_KINDS := ["wuenscher_plus2", "wuenscher", "farbjagd", "plus5", "flip"]

var seat := -1
var player: Dictionary = {}
var compact := false
var night := 1.0: set = set_night
var card_w := 60.0
var fan_max_w := 210.0
var show_score := false
var catchable := false: set = set_catchable
var keys: Array[String] = []            # angezeigte Rückseiten (Fächerreihenfolge)

var _fan: Node2D
var _top: Node2D
var _cards: Array[CardView] = []
var _more := 0
var _turn := false
var _next := false
var _sleep := 0.0
var _time := 0.0
var _bump := 0.0
var _header_w := 200.0


func _init() -> void:
	_fan = Node2D.new()
	add_child(_fan)
	# Über dem Fächer: „Erwischt!“-Knopf und „+n“
	_top = Node2D.new()
	add_child(_top)
	_top.draw.connect(_draw_top)


func _process(delta: float) -> void:
	_time += delta
	if _turn or catchable or _sleep > 0.0 or _bump > 0.0:
		queue_redraw()
	if catchable:
		_top.queue_redraw()


func set_night(v: float) -> void:
	night = clampf(v, 0.0, 1.0)
	queue_redraw()


func set_catchable(on: bool) -> void:
	catchable = on
	queue_redraw()
	if _top:
		_top.queue_redraw()


func set_turn(on: bool, next := false) -> void:
	_turn = on
	_next = next and not on
	queue_redraw()


func player_name() -> String:
	return str(player.get("name", "Spieler %d" % (seat + 1)))


func count() -> int:
	return int(player.get("count", 0))


# Daten aus der Sicht (players[i]); backs_visible aus den Regeln
func set_player(p: Dictionary, backs_visible := true) -> void:
	player = p
	seat = int(p.get("seat", seat))
	var backs: Array = p.get("backs", [])
	var n := int(p.get("count", backs.size()))
	var want: Array[String] = []
	if backs_visible and backs.size() == n:
		for b in backs:
			want.append(str(b))
	else:
		for i in n:
			want.append(CardTextures.BACK)
	set_keys(want)
	queue_redraw()


func set_keys(new_keys: Array[String]) -> void:
	keys = new_keys.duplicate()
	_rebuild()


func backs_visible() -> bool:
	return not keys.is_empty() and keys[0] != CardTextures.BACK


# Fächermitte (Ziel für Kartenflüge) in globalen Koordinaten
func fan_global_center() -> Vector2:
	return to_global(_fan.position + Vector2(0, card_w * 0.78))


func avatar_global() -> Vector2:
	return to_global(_avatar_center())


func header_height() -> float:
	return (AVATAR_R_COMPACT if compact else AVATAR_R) * 2.0


# Nimmt eine Karte aus dem Fächer (Ausspielen eines Gegners). Bevorzugt den gewünschten Schlüssel.
# Ergebnis {pos, rot, key, width} in globalen Koordinaten; der Fächer schließt sich sofort.
func take_card(prefer_key := "") -> Dictionary:
	var idx := keys.find(prefer_key) if prefer_key != "" else -1
	if idx < 0 or idx >= _cards.size():
		idx = clampi(_cards.size() / 2, 0, maxi(_cards.size() - 1, 0))
	var out := {"pos": fan_global_center(), "rot": 0.0, "key": prefer_key if prefer_key != "" else CardTextures.BACK, "width": card_w}
	if idx < _cards.size():
		var c := _cards[idx]
		out = {"pos": c.global_position, "rot": c.global_rotation, "key": c.current_key(), "width": c.width * c.global_scale.x}
	if idx < keys.size():
		keys.remove_at(idx)
	elif not keys.is_empty():
		keys.pop_back()
	player["count"] = maxi(count() - 1, 0)
	_rebuild()
	return out


# Gezogene Karte kommt dazu (nach dem Flug)
func add_card(key: String) -> void:
	keys.append(key)
	player["count"] = count() + 1
	_rebuild()
	_bump = 1.0
	var tw := create_tween()
	tw.tween_property(self, "_bump", 0.0, 0.35)


# Flip-Welle über den Fächer: jede Karte wendet zur neuen Seite (new_keys aus der Zielsicht, gleiche Anzahl)
func flip_wave(new_keys: Array[String], delay: float, step := 0.02, dur := 0.2) -> void:
	for i in _cards.size():
		var c := _cards[i]
		var nk := new_keys[i] if i < new_keys.size() else CardTextures.BACK
		c.setup(c.card_id, c.current_key(), nk, true)
		c.flip(dur, delay + i * step)
	var tw := create_tween()
	tw.tween_interval(delay + _cards.size() * step + dur + 0.02)
	tw.tween_callback(func() -> void:
		keys = new_keys.duplicate()
		_rebuild())


# Aussetzen: Avatar für t Sekunden grau
func sleep_for(t: float) -> void:
	_sleep = 1.0
	var tw := create_tween()
	tw.tween_interval(maxf(t - 0.3, 0.0))
	tw.tween_property(self, "_sleep", 0.0, 0.3)


func hit_fan(global_pos: Vector2) -> bool:
	var local := to_local(global_pos)
	var r := Rect2(-maxf(fan_max_w, BAR_W) * 0.5 - 10.0, -header_height() * 0.6, maxf(fan_max_w, BAR_W) + 20.0, header_height() + card_w * 1.9 + 20.0)
	return r.has_point(local)


func hit_catch(global_pos: Vector2) -> bool:
	return catchable and _catch_rect().grow(18.0).has_point(to_local(global_pos))


func _catch_rect() -> Rect2:
	var y := header_height() * 0.5 + 6.0
	return Rect2(-70.0, y, 140.0, 46.0)


# ---------------------------------------------------------------- Aufbau des Fächers

func _rebuild() -> void:
	var n := keys.size()
	var shown_keys: Array[String] = []
	var xfs: Array[Transform2D] = []
	var w := card_w
	_more = 0
	if compact and not (n == 1 and backs_visible()):
		n = 0
	elif n == 1:
		# letzte Karte groß (auch im Abzeichen)
		w = card_w * (1.25 if compact else 1.45)
		shown_keys = [keys[0]]
		xfs = [Transform2D(0.0, Vector2(0, w * 466.0 / 300.0 * 0.5))]
	else:
		var f := TableLayout.fan(n, w, fan_max_w)
		var xf_list: Array = f["xf"]
		for t in xf_list:
			xfs.append(t)
		_more = int(f["more"])
		var shown := int(f["shown"])
		# Bei Überlänge gleichmäßig auswählen (Gruppen bleiben erkennbar)
		for i in shown:
			var src := int(round(float(i) * float(n - 1) / float(maxi(shown - 1, 1)))) if shown < n else i
			shown_keys.append(keys[src])
	while _cards.size() > shown_keys.size():
		var c: CardView = _cards.pop_back()
		c.queue_free()
	while _cards.size() < shown_keys.size():
		var c := CardView.new()
		_fan.add_child(c)
		_cards.append(c)
	_fan.position = Vector2(0, header_height() * 0.5 + 10.0)
	for i in shown_keys.size():
		var c := _cards[i]
		c.width = w
		if c.current_key() != shown_keys[i]:
			c.setup(i, shown_keys[i], "", true)
		c.transform = xfs[i]
		c.set_state(CardView.State.NORMAL)
		c.modulate = Color.WHITE
	queue_redraw()
	_top.queue_redraw()


# ---------------------------------------------------------------- Zeichnen

func _avatar_center() -> Vector2:
	return Vector2(-_header_w * 0.5 + (AVATAR_R_COMPACT if compact else AVATAR_R), 0.0)


func _draw() -> void:
	var ink := UiPalette.ui_text(night)
	var name_font := UiFonts.text(700, 100.0)
	var num_font := UiFonts.text(800, 90.0)
	var name_size := 17 if compact else 21
	var nm := player_name()
	if compact and nm.length() > 9:
		nm = nm.substr(0, 8) + "…"
	var ar := AVATAR_R_COMPACT if compact else AVATAR_R
	var cnt := str(count())
	var name_w := name_font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x
	var cnt_w := maxf(num_font.get_string_size(cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 16.0, 26.0)
	_header_w = ar * 2.0 + 12.0 + name_w + 10.0 + cnt_w
	var ac := _avatar_center()
	var connected := bool(player.get("connected", true))
	# Zugmarke: warmer, pulsierender Ring
	if _turn:
		var pulse := 0.5 + 0.5 * sin(_time * 4.0)
		draw_circle(ac, ar + 10.0 + 3.0 * pulse, Color(UiPalette.TURN, 0.18 + 0.14 * pulse))
		draw_arc(ac, ar + 6.0, 0.0, TAU, 48, Color(UiPalette.TURN, 0.95), 3.0, true)
	# Avatar
	var base := UiPalette.avatar(seat)
	if _sleep > 0.0:
		var g := base.get_luminance()
		base = base.lerp(Color(g, g, g), _sleep * 0.85)
	if not connected:
		base = Color(base, 0.45)
	var bump := 1.0 + 0.08 * _bump
	draw_circle(ac, ar * bump + 3.0, UiPalette.PAPER if night > 0.5 else UiPalette.INK)
	draw_circle(ac, ar * bump, base)
	var initial := player_name().substr(0, 1).to_upper()
	var ini_font := UiFonts.text(800, 100.0)
	var ini_size := int(ar * 0.9)
	var iw := ini_font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, ini_size)
	draw_string(ini_font, ac + Vector2(-iw.x * 0.5, ini_size * 0.36), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, ini_size, UiPalette.INK)
	if str(player.get("kind", "human")) == "bot":
		var bc := ac + Vector2(ar * 0.72, ar * 0.72)
		draw_circle(bc, 10.0, UiPalette.INK)
		var kf := UiFonts.text(800, 80.0)
		var kw := kf.get_string_size("KI", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(kf, bc + Vector2(-kw * 0.5, 3.6), "KI", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiPalette.PAPER)
	if _sleep > 0.0:
		var cat := UiIcons.icon("katze", 40, Color(UiPalette.MOON, _sleep), UiPalette.INK)
		draw_texture_rect(cat, Rect2(ac + Vector2(-20, -ar - 44), Vector2(40, 40)), false)
	# Name
	var nx := ac.x + ar + 12.0
	draw_string(name_font, Vector2(nx, name_size * 0.36), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, Color(ink, 1.0 if connected else 0.55))
	# Kartenzahl als Pille
	var cx := nx + name_w + 10.0
	var pill := Rect2(cx, -12.0, cnt_w, 24.0)
	var pill_bg := UiPalette.PAPER if night > 0.5 else UiPalette.INK
	var pill_fg := UiPalette.INK if night > 0.5 else UiPalette.PAPER
	_draw_round_rect(pill, 12.0, pill_bg)
	var tw := num_font.get_string_size(cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(num_font, Vector2(cx + (cnt_w - tw) * 0.5, 5.5), cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, pill_fg)
	# Nebenzeile: gleich dran / getrennt / Punkte / Mau
	var sub := ""
	if not connected:
		sub = "getrennt"
	elif _next:
		sub = "gleich dran"
	if show_score:
		sub = (sub + " · " if sub != "" else "") + "%d P" % int(player.get("score", 0))
	var sub_font := UiFonts.text(600, 90.0)
	if sub != "" and not compact:
		draw_string(sub_font, Vector2(nx, name_size * 0.36 + 19.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiPalette.ui_muted(night))
	if bool(player.get("mau", false)):
		_draw_mau_tag(ac + Vector2(-ar - 4.0, -ar - 2.0))
	var place := int(player.get("place", 0))
	if place > 0:
		var mc := ac + Vector2(-ar * 0.75, ar * 0.75)
		draw_circle(mc, 13.0, UiPalette.TURN)
		var pt := "%d." % place
		var pw := num_font.get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(num_font, mc + Vector2(-pw * 0.5, 5.0), pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiPalette.INK)
	if compact and _cards.is_empty():
		_draw_bar(Vector2(-BAR_W * 0.5, ar + 10.0))


func _draw_top() -> void:
	var num_font := UiFonts.text(800, 90.0)
	var pill_bg := UiPalette.PAPER if night > 0.5 else UiPalette.INK
	var pill_fg := UiPalette.INK if night > 0.5 else UiPalette.PAPER
	if _more > 0 and not compact:
		var mpos := _fan.position + Vector2(fan_max_w * 0.5 - 6.0, card_w * 1.1)
		var mt := "+%d" % _more
		var mw := num_font.get_string_size(mt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 14.0
		_round_rect(_top, Rect2(mpos - Vector2(mw * 0.5, 12), Vector2(mw, 24)), 12.0, pill_bg)
		_top.draw_string(num_font, mpos + Vector2(-mw * 0.5 + 7.0, 5.5), mt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, pill_fg)
	if catchable:
		var r := _catch_rect()
		var pulse := 0.5 + 0.5 * sin(_time * 6.0)
		_round_rect(_top, r.grow(3.0 + 2.0 * pulse), 26.0, Color(UiPalette.ALERT, 0.35))
		_round_rect(_top, r, 23.0, UiPalette.ALERT)
		var ef := UiFonts.title(800, true, 100.0, 36.0)
		var et := "Erwischt!"
		var ew := ef.get_string_size(et, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		_top.draw_string(ef, Vector2(-ew * 0.5, r.position.y + 31.0), et, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UiPalette.CREAM)


func _draw_mau_tag(p: Vector2) -> void:
	var f := UiFonts.mau()
	var t := "Mau!"
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 14.0
	var r := Rect2(p - Vector2(w * 0.5, 13), Vector2(w, 24))
	_draw_round_rect(r, 12.0, UiPalette.CREAM)
	draw_string(f, r.position + Vector2(7, 17.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiPalette.INK)


# Abzeichen-Farbbalken: Rückseiten je Farbe als Segmente mit Symbol und Anzahl; besondere Rückseiten als Marken dahinter
func _draw_bar(origin: Vector2) -> void:
	var bg := Color(UiPalette.PAPER, 0.14) if night > 0.5 else Color(UiPalette.INK, 0.10)
	var r := Rect2(origin, Vector2(BAR_W, BAR_H))
	_draw_round_rect(r, BAR_H * 0.5, bg)
	if keys.is_empty():
		return
	if not backs_visible():
		var f := UiFonts.text(700, 90.0)
		var t := "verdeckt"
		draw_string(f, origin + Vector2(10, 17), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiPalette.ui_muted(night))
		return
	var counts := {}
	var order: Array[String] = []
	var specials := {}
	for k in keys:
		var col := CardTextures.color_of(k)
		if col == "":
			col = "joker"
		if not counts.has(col):
			counts[col] = 0
			order.append(col)
		counts[col] = int(counts[col]) + 1
		for kind in SPECIAL_KINDS:
			if k.ends_with("_" + kind):
				specials[kind] = int(specials.get(kind, 0)) + 1
				break
	var x := origin.x
	var total := float(keys.size())
	var f2 := UiFonts.text(800, 85.0)
	for col in order:
		var seg_w := BAR_W * float(counts[col]) / total
		var seg := Rect2(x + 1.0, origin.y + 1.0, maxf(seg_w - 2.0, 2.0), BAR_H - 2.0)
		var fill := UiPalette.glow(col) if col != "joker" else UiPalette.MOON
		_draw_round_rect(seg, (BAR_H - 2.0) * 0.5, fill)
		var label := str(counts[col])
		if seg_w >= 34.0 and col != "joker":
			draw_texture_rect(UiIcons.symbol(col, 32, UiPalette.text_on(fill), fill), Rect2(seg.position + Vector2(3, 3), Vector2(16, 16)), false)
			draw_string(f2, seg.position + Vector2(21, 16.5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiPalette.text_on(fill))
		elif seg_w >= 14.0:
			var lw := f2.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(f2, seg.position + Vector2((seg.size.x - lw) * 0.5, 16.5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiPalette.text_on(fill))
		x += seg_w
	# Marken für auffällige Rückseiten
	var mx := origin.x
	var my := origin.y + BAR_H + 6.0
	var mf := UiFonts.text(800, 85.0)
	for kind in SPECIAL_KINDS:
		if not specials.has(kind):
			continue
		var txt := {"wuenscher_plus2": "+2", "wuenscher": "", "farbjagd": "?", "plus5": "+5", "flip": ""}[kind] as String
		var chip := Rect2(mx, my, 40.0, 20.0)
		_draw_round_rect(chip, 10.0, UiPalette.PAPER if night > 0.5 else UiPalette.INK)
		var fg := UiPalette.INK if night > 0.5 else UiPalette.PAPER
		if kind in ["wuenscher", "farbjagd", "wuenscher_plus2"]:
			draw_texture_rect(UiIcons.icon("pfote", 28, fg), Rect2(chip.position + Vector2(4, 3), Vector2(14, 14)), false)
		elif kind == "flip":
			draw_texture_rect(UiIcons.icon("flip", 28, fg, UiPalette.PAPER if night <= 0.5 else UiPalette.INK), Rect2(chip.position + Vector2(4, 3), Vector2(14, 14)), false)
		var label := txt + "×%d" % int(specials[kind]) if txt != "" else "×%d" % int(specials[kind])
		draw_string(mf, chip.position + Vector2(19, 14.5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, fg)
		mx += 44.0


func _draw_round_rect(r: Rect2, radius: float, col: Color) -> void:
	_round_rect(self, r, radius, col)


static func _round_rect(ci: CanvasItem, r: Rect2, radius: float, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	ci.draw_style_box(sb, r)
