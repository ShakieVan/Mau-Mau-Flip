extends SceneTree
# Modul F1a, Nachbesserung nach der Prüfung (docs/module/F1a_pruefung.json), headless mit Testuhr:
# Schichtung (keine z_index-Werte über 100, Tisch-Overlays wie der Sichtschutz liegen über der Hand), abgebrochene Berührungen
# (canceled, hängende Berührung), Hilfegeste am unteren Rand, Rundenwechsel mit wiederverwendeten Kennungen (kein Flip),
# Schwung am Kartenende ohne Überschwingen, Handbereich am unteren Rand des sichtbaren Bereichs bzw. vom Tisch gesetzt,
# Tag-Hervorhebung, Haptik nur beim Nutzerscrollen, Tipp in laufenden Schwung hält nur an, take_card räumt auf,
# reset_for_player beim Weitergeben, Geisterbild auf der Ablage beim scharfen Hochziehen, schnelle weiche Texturen, „reduziert“.
# Aufruf: tools/godot_run.ps1 -Script res://tests/test_ui_hand_fixes.gd -Headless
const DT := 1.0 / 60.0
var ok := 0
var failed := 0
var hand: HandView
var clock := 1000.0
var log: Array = []
var vr := Rect2()


class CountingHand:
	extends HandView
	var pulses := 0

	func _vibrate(_ms: int, _strength: float) -> void:
		pulses += 1


func check(cond: bool, msg: String) -> void:
	if cond:
		ok += 1
	else:
		failed += 1
		print("FAIL: ", msg)


func _initialize() -> void:
	call_deferred("run")


func step(n := 1) -> void:
	for k in n:
		clock += DT * 1000.0
		hand.clock_ms = clock
		hand.step(DT)


func settle(seconds := 1.2) -> void:
	step(int(seconds / DT))


func cards(faces: Array, first_id := 0, with_backs := true) -> Array:
	var out: Array = []
	for i in faces.size():
		out.append({"id": first_id + i, "face": faces[i], "back": ("dunkel_lila_%d" % (1 + i % 9)) if with_backs else ""})
	return out


func many(n: int, first_id := 0, shift := 0) -> Array:
	var colors := ["rot", "gelb", "gruen", "blau"]
	var faces: Array = []
	for i in n:
		faces.append("hell_%s_%d" % [colors[(i + shift) % 4], 1 + ((i + shift) / 4) % 9])
	return cards(faces, first_id)


func tap_point(id: int) -> Vector2:
	var v := hand.card_view(id)
	var h := v.card_size() * v.scale.x * 0.5
	return v.position + Vector2(-h.x + 22.0, -h.y + 50.0).rotated(v.rotation)


func events(name: String) -> Array:
	return log.filter(func(e: Array) -> bool: return e[0] == name)


func new_hand(h: HandView = null) -> void:
	if hand != null:
		hand.free()      # sofort: ein noch hängender Knoten bekäme sonst die Eingaben
	hand = h if h != null else HandView.new()
	hand.haptics = false
	root.add_child(hand)
	hand.set_process(false)
	hand.clock_ms = clock
	vr = hand._view_rect()
	hand.layout_rect = Rect2(270, vr.end.y - 220.0, 1060, 220)
	log.clear()
	hand.play_requested.connect(func(id: int, g: Vector2) -> void: log.append(["play", id]))
	hand.help_requested.connect(func(id: int, face: String) -> void: log.append(["help", id]))
	hand.drag_ended.connect(func(id: int, g: Vector2, played: bool) -> void: log.append(["drag_ended", id, played]))
	hand.selection_changed.connect(func(id: int) -> void: log.append(["select", id]))
	hand.big_view_changed.connect(func(id: int) -> void: log.append(["big", id]))
	hand.sort_mode_changed.connect(func(m: String) -> void: log.append(["sort_mode", m]))
	hand.drag_armed.connect(func(id: int, on: bool) -> void: log.append(["armed", id, on]))


# Wirksamer z_index eines CanvasItems (relativ zu den Eltern addiert).
func eff_z(ci: CanvasItem) -> int:
	var z := 0
	var n: Node = ci
	while n is CanvasItem:
		var c := n as CanvasItem
		z += c.z_index
		if not c.z_as_relative:
			break
		n = n.get_parent()
	return z


func items_of(n: Node, out: Array) -> Array:
	for c in n.get_children():
		if c is CanvasItem and (c as CanvasItem).is_visible_in_tree():
			out.append(c)
		items_of(c, out)
	return out


func max_z(n: Node) -> int:
	var m := -100000
	for ci in items_of(n, []):
		m = maxi(m, absi((ci as CanvasItem).z_index))
	return m


# a wird über allen sichtbaren Teilen der Hand gezeichnet (gleiche Zeichenebene: erst z, dann Baumreihenfolge)
func above_hand(a: CanvasItem, h: Node) -> bool:
	var za := eff_z(a)
	for ci in items_of(h, []):
		var zc := eff_z(ci as CanvasItem)
		if zc > za or (zc == za and (ci as Node).is_greater_than(a)):
			return false
	return true


func touch(pressed: bool, p: Vector2, index := 0, canceled := false) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = root.get_final_transform() * (hand.get_global_transform_with_canvas() * p)   # Fensterkoordinaten
	ev.pressed = pressed
	ev.canceled = canceled
	root.push_input(ev)


func touch_drag(p: Vector2, index := 0) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = root.get_final_transform() * (hand.get_global_transform_with_canvas() * p)   # Fensterkoordinaten
	root.push_input(ev)


func run() -> void:
	# ---------------------------------------------------------------- Schichtung
	new_hand()
	var five := cards(["hell_wuenscher", "hell_blau_9", "hell_rot_7", "hell_gelb_3", "hell_rot_2"])
	hand.set_cards(five)
	hand.set_playable([0, 1, 2, 3, 4])
	settle(1.0)
	check(max_z(hand) == 0, "ruhende Hand: alle z_index 0 (%d)" % max_z(hand))
	hand.select(2)
	settle(0.3)
	var p3 := tap_point(3)
	hand.touch_down(p3, clock)
	step(25)
	check(hand.is_big_view_open(), "Großansicht offen")
	check(max_z(hand) <= 100, "Großansicht: z_index höchstens 100 (%d)" % max_z(hand))
	var big := hand.card_view(3)
	check(big.get_index() > hand._overlay.get_index(), "große Karte über der Abdunklung (Kindreihenfolge)")
	hand.touch_up(p3, clock)
	hand.close_big_view()
	settle(0.3)
	var p1 := tap_point(1)
	hand.play_target = Vector2(980, 320)
	hand.touch_down(p1, clock)
	for k in range(1, 15):
		step()
		hand.touch_move(p1 + Vector2(0, -17.0 * k), clock)
	step(3)
	check(max_z(hand) <= 100, "Ziehen mit Geisterbild: z_index höchstens 100 (%d)" % max_z(hand))
	var z_ok := true
	for ci in items_of(hand, []):
		if not (ci as CanvasItem).z_as_relative:
			z_ok = false
	check(z_ok, "alle z_index relativ zur Hand")
	hand.touch_up(p1 + Vector2(0, -238), clock)
	settle(0.5)
	check(max_z(hand) <= 100, "ausgespielt: z_index höchstens 100")
	hand.cancel_play(1)
	settle(1.0)

	# mit dem echten Tisch: Sichtschutz und Kartenhilfe liegen über der Hand
	var table := TableView.new()
	root.add_child(table)
	var th := HandView.new()
	th.haptics = false
	table.set_hand(th)
	th.set_process(false)
	th.set_cards(many(9))
	for k in 60:
		th.step(DT)
	table.handover.show_for("Lena", 0, 1, 7)
	check(above_hand(table.handover, th), "Sichtschutz liegt über allen Handkarten")
	table.help_popup.visible = true
	check(above_hand(table.help_popup, th), "Kartenhilfe liegt über allen Handkarten")
	check(max_z(th) <= 100, "Hand im Tisch: z_index höchstens 100")
	table.free()

	# ---------------------------------------------------------------- abgebrochene Berührungen
	new_hand()
	hand.set_cards(five)
	hand.set_playable([0, 1, 2, 3, 4])
	settle(1.0)
	var p0 := tap_point(0)
	touch(true, p0)
	for k in range(1, 15):
		step()
		touch_drag(p0 + Vector2(0, -17.0 * k))
	step()
	check(hand.is_play_armed(), "hochgezogen und scharf")
	touch(false, p0 + Vector2(0, -238), 0, true)
	step()
	check(events("play").is_empty() and events("drag_ended") == [["drag_ended", 0, false]], "abgebrochene Berührung spielt nicht aus (%s)" % [log])
	check(not hand.is_play_armed(), "nicht mehr scharf")
	settle(0.5)
	log.clear()
	touch(true, p0)
	step(25)
	check(hand.is_big_view_open(), "Halten öffnet die Großansicht")
	touch(false, p0, 0, true)
	step()
	check(not hand.is_big_view_open(), "Abbruch schließt die Großansicht")
	settle(0.3)
	# hängende Berührung (Loslassen verloren): neuer Druck mit demselben Index beginnt neu
	log.clear()
	touch(true, tap_point(4))
	step(3)
	touch(true, tap_point(2))
	step(3)
	touch(false, tap_point(2))
	step()
	check(events("select") == [["select", 2]], "hängende Berührung: neuer Druck zählt (%s)" % [log])
	# Fokusverlust bricht ab
	log.clear()
	var pf := tap_point(3)
	hand.touch_down(pf, clock)
	for k in range(1, 15):
		step()
		hand.touch_move(pf + Vector2(0, -17.0 * k), clock)
	hand.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	hand.touch_up(pf + Vector2(0, -238), clock)
	check(events("play").is_empty(), "Fokusverlust bricht das Ziehen ab")
	settle(0.5)

	# ---------------------------------------------------------------- Hilfegeste am unteren Rand
	for y_off in [70.0, 25.0, 12.0]:
		log.clear()
		var id := hand.get_order()[2]
		var v := hand.card_view(id)
		var p := Vector2(v.position.x - 30.0, vr.end.y - y_off)
		check(v.contains_global_point(hand.to_global(p)), "Druckpunkt %d px über dem Rand trifft die Karte" % int(y_off))
		hand.touch_down(p, clock)
		step(25)
		check(hand.is_big_view_open(), "Großansicht bei %d px über dem Rand" % int(y_off))
		var badge: Vector2 = hand._badge_pos
		check(badge.y <= vr.end.y - HandView.BADGE_R * 0.6, "„?“ sichtbar (%d px)" % int(y_off))
		if y_off >= 25.0:
			check(badge.y > p.y, "„?“ unter dem Finger (%d px: Finger %.0f, „?“ %.0f)" % [int(y_off), p.y, badge.y])
		var down := minf(p.y + 60.0, vr.end.y - 1.0)
		for k in range(1, 7):
			step()
			hand.touch_move(p.lerp(Vector2(p.x + 2.0, down), float(k) / 6.0), clock)
		step()
		hand.touch_up(Vector2(p.x + 2.0, down), clock)
		check(events("help") == [["help", id]], "Hilfe auch %d px über dem Rand (%s)" % [int(y_off), log])
		settle(0.4)

	# ---------------------------------------------------------------- Rundenwechsel: Kennungen neu gemischt
	new_hand()
	hand.apply_view({"seat": 0, "round": 1, "hand": many(7), "hints": {"playable": []}})
	settle(1.5)
	var r2 := many(7, 3, 2)
	hand.apply_view({"seat": 0, "round": 2, "hand": r2, "hints": {"playable": []}})
	var flipping := 0
	var shimmering := 0
	var wrong := 0
	for c in r2:
		var cv := hand.card_view(int(c.id))
		if cv.is_flipping():
			flipping += 1
		if cv.is_shimmering():
			shimmering += 1
		if cv.current_key() != str(c.face):
			wrong += 1
	check(flipping == 0 and wrong == 0, "neue Runde: kein Flip, sofort die neuen Gesichter (wendet %d, falsch %d)" % [flipping, wrong])
	check(shimmering == 0, "neue Runde: wird ausgeteilt, kein Schimmern (%d)" % shimmering)
	check(hand.card_view(3).position.distance_to(hand.card_view(9).position) < 1.0 and hand.card_view(3).position.y < vr.end.y - 300.0, "neue Runde: Karten fliegen erst ein")
	settle(1.5)
	# ohne Rundennummer: gleiche Kennung, andere Karte derselben Seite = ersetzen statt wenden
	hand.set_cards(many(7, 3, 5))
	check(not hand.card_view(4).is_flipping() and hand.card_view(4).current_key() == str(many(7, 3, 5)[1].face), "andere Karte unter alter Kennung wird ersetzt")
	settle(1.5)
	# echter Flip auch ohne Rückseiten-Angabe (peek_own_backs aus)
	var dark: Array = []
	for c in hand.get_order():
		dark.append({"id": c, "face": "dunkel_pink_%d" % (1 + c % 9), "back": ""})
	var before_key := hand.card_view(5).current_key()
	hand.set_cards(dark)
	check(hand.card_view(5).current_key() == before_key, "Flip ohne Rückseiten-Angabe wendet (zeigt zuerst die alte Seite)")
	settle(1.0)

	# ---------------------------------------------------------------- Schwung am Kartenende
	new_hand()
	hand.set_cards(many(20))
	settle(1.0)
	hand._scroll = 16.0
	hand._scroll_target = 16.0
	settle(1.0)
	var start := Vector2(1100, vr.end.y - 80.0)
	hand.touch_down(start, clock)
	for k in range(1, 4):
		step()
		hand.touch_move(start - Vector2(80.0 * k, 0), clock)
	step()
	hand.touch_up(start - Vector2(240, 0), clock)
	check(hand.get_scroll() < 19.0, "losgelassen vor dem Ende (%.2f)" % hand.get_scroll())
	var peak := hand.get_scroll()
	for k in 150:
		step()
		peak = maxf(peak, hand.get_scroll())
	check(absf(hand.get_scroll() - 19.0) < 0.02, "Schwung rastet auf der letzten Karte ein (%.2f)" % hand.get_scroll())
	check(peak <= 19.3, "Schwung am Ende überschwingt höchstens 0,3 Karten (Spitze %.3f)" % peak)

	# ---------------------------------------------------------------- Haptik nur beim Nutzerscrollen, Tipp in den Schwung
	var ch := CountingHand.new()
	new_hand(ch)
	ch.haptics = true
	hand.set_cards(many(20))
	settle(1.0)
	ch.pulses = 0
	for k in 5:
		hand.receive_card({"id": 40 + k, "face": "hell_rot_%d" % (1 + k), "back": ""}, hand.landing_point())
		settle(0.3)
	check(ch.pulses == 0, "neue Karten im Karussell: keine Vibration (%d)" % ch.pulses)
	var sw := Vector2(1000, vr.end.y - 80.0)
	hand.touch_down(sw, clock)
	for k in range(1, 6):
		step()
		hand.touch_move(sw - Vector2(70.0 * k, 0), clock)
	step()
	hand.touch_up(sw - Vector2(350, 0), clock)
	step(4)
	check(ch.pulses > 0, "Nutzerschwung: Haptik-Raster (%d)" % ch.pulses)
	check(absf(hand._scroll_v) > HandView.FLING_STOP, "Schwung läuft (%.1f Karten/s)" % hand._scroll_v)
	log.clear()
	var mid := Vector2(800, vr.end.y - 60.0)
	hand.touch_down(mid, clock)
	step(3)
	hand.touch_up(mid, clock)
	check(events("select").is_empty() and hand.get_selected() == -1, "Tipp in den laufenden Schwung wählt nichts")
	var stop_at := hand.get_scroll()
	settle(1.5)
	check(absf(hand.get_scroll() - roundf(stop_at)) < 0.02, "Tipp hält den Schwung an (%.2f → %.2f)" % [stop_at, hand.get_scroll()])
	tap_select(hand.get_order()[int(roundf(hand.get_scroll()))])
	check(hand.get_selected() != -1, "Tipp danach wählt wieder")

	# ---------------------------------------------------------------- take_card räumt auf
	new_hand()
	hand.set_cards(five)
	hand.set_playable([0, 1, 2, 3, 4])
	settle(1.0)
	hand.select(2)
	log.clear()
	var tv := hand.take_card(2)
	check(hand.get_selected() == -1 and events("select") == [["select", -1]], "take_card der gewählten Karte hebt die Auswahl auf")
	tv.free()
	var pb := tap_point(3)
	hand.touch_down(pb, clock)
	step(25)
	tv = hand.take_card(3)
	settle(0.3)
	check(not hand.is_big_view_open() and hand._overlay.dim < 0.01, "take_card in der Großansicht schließt sie samt Abdunklung")
	tv.free()

	# ---------------------------------------------------------------- Spielerwechsel (Weitergeben)
	new_hand()
	hand.apply_view({"seat": 0, "round": 1, "hand": cards(["hell_rot_1", "hell_gelb_2", "hell_blau_3", "hell_gruen_4"]), "hints": {}})
	settle(1.0)
	hand.set_sort_mode("manuell")
	var manual_order := hand.get_order()
	manual_order.reverse()
	hand._order = manual_order.duplicate()
	hand.set_peek_backs(true)
	settle(0.5)
	log.clear()
	hand.apply_view({"seat": -1, "round": 1, "hand": [], "hints": {}})
	check(hand.get_order().is_empty() and items_of(hand, []).filter(func(c: Object) -> bool: return c is CardView).is_empty(), "Sichtschutz-Sicht: Hand sofort leer, keine Karte sichtbar")
	hand.apply_view({"seat": 1, "round": 1, "hand": cards(["hell_rot_5", "hell_gelb_6", "hell_blau_7"], 10), "hints": {}})
	check(not hand.is_peeking(), "neuer Spieler: Rückseiten-Ansicht aus")
	check(hand.sort_mode == "farbe" and events("sort_mode") == [["sort_mode", "farbe"]], "neuer Spieler: automatische Sortierung (%s)" % hand.sort_mode)
	check(hand.card_view(10).current_key() == "hell_rot_5", "neuer Spieler sieht Vorderseiten")
	settle(1.0)
	hand.apply_view({"seat": 0, "round": 1, "hand": cards(["hell_rot_1", "hell_gelb_2", "hell_blau_3", "hell_gruen_4"]), "hints": {}})
	check(hand.sort_mode == "manuell" and hand.get_order() == manual_order, "zurück zu Platz 0: manuelle Reihenfolge wieder da (%s)" % [hand.get_order()])
	hand.reset_for_player()
	check(hand.get_order().is_empty() and hand.sort_mode == "farbe", "reset_for_player() ohne Platz: leer, manuell → farbe")

	# ---------------------------------------------------------------- Geisterbild auf der Ablage
	new_hand()
	hand.set_cards(five)
	hand.set_playable([1])
	hand.play_target = Vector2(980, 320)
	settle(1.0)
	log.clear()
	var pg := tap_point(1)
	hand.touch_down(pg, clock)
	for k in range(1, 15):
		step()
		hand.touch_move(pg + Vector2(0, -17.0 * k), clock)
	step(10)
	var ghost: CardView = hand._ghost
	check(events("armed") == [["armed", 1, true]] and hand.is_play_armed(), "drag_armed beim Überschreiten der Schwelle")
	check(ghost != null and ghost.visible and ghost.global_position.distance_to(Vector2(980, 320)) < 1.0, "Geisterbild auf der Ablage")
	check(ghost != null and ghost.current_key() == "hell_blau_9" and ghost.modulate.a < 0.6, "Geisterbild zeigt die Karte, halb durchsichtig")
	hand.touch_move(pg + Vector2(0, -40), clock)
	step(10)
	check(events("armed").size() == 2 and events("armed")[1] == ["armed", 1, false] and not ghost.visible, "zurückgezogen: Geisterbild weg")
	hand.touch_up(pg + Vector2(0, -40), clock)
	settle(0.5)
	log.clear()
	var pn := tap_point(3)
	hand.touch_down(pn, clock)
	for k in range(1, 15):
		step()
		hand.touch_move(pn + Vector2(0, -17.0 * k), clock)
	step(5)
	check(events("armed").is_empty(), "nicht spielbare Karte: kein Geisterbild")
	hand.touch_up(pn + Vector2(0, -238), clock)
	settle(1.0)

	# ---------------------------------------------------------------- Handbereich
	new_hand()
	var auto := HandView.new()
	root.add_child(auto)
	var avr: Rect2 = auto._view_rect()
	check(absf(auto.layout_rect.end.y - avr.end.y) < 0.5 and absf(auto.layout_rect.size.y - 220.0) < 0.5, "ohne Tisch: Handbereich am unteren Rand (%s)" % auto.layout_rect)
	auto.layout_rect = Rect2(300, 400, 1000, 200)
	auto._fit_to_view()
	check(auto.layout_rect == Rect2(300, 400, 1000, 200), "vom Tisch gesetzt: bleibt")
	auto.set_play_target(Vector2(5, 6))
	auto.set_spawn_from(Vector2(7, 8))
	check(auto.play_target == Vector2(5, 6) and auto.spawn_from == Vector2(7, 8), "Setter für Ablage und Stapel")
	check(HandView.default_rect(Rect2(0, 0, 1600, 757)) == Rect2(270, 537, 1060, 220), "19:9: Hand am unteren Rand")
	auto.free()

	# ---------------------------------------------------------------- Tag/Nacht, reduziert, weiche Texturen
	hand.set_cards(five)
	hand.set_playable([0])
	hand.select(1)
	settle(0.5)
	check(hand.card_view(1).day and hand.card_view(1)._glow.material == null, "helle Seite: Glühen normal gemischt (Tag)")
	check(hand.card_view(1)._glow.modulate.a > 0.9, "Tag: gewählte Karte deckend umrandet")
	hand.night = 1.0
	step()
	check(not hand.card_view(1).day and hand.card_view(1)._glow.material != null, "Nacht: additiv")
	hand.night = -1.0
	hand.apply_view({"hand": five, "hints": {"playable": [0]}, "color": "blau"})
	step()
	check(hand.card_view(0).playable_tint.a > 0.5 and hand.card_view(0).state == CardView.State.PLAYABLE, "spielbare Karte: Rand in der aktuellen Farbe")
	hand.reduced = true
	hand.receive_card({"id": 60, "face": "hell_rot_8", "back": ""}, hand.landing_point())
	check(not hand.card_view(60).is_shimmering(), "reduziert: kein Glanzstreifen")
	hand.reduced = false
	var t0 := Time.get_ticks_usec()
	var tex := CardView.soft_texture(5.25)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("weiche Textur erzeugt in %.1f ms" % ms)
	var img := tex.get_image()
	var cx := img.get_width() / 2
	var cy := img.get_height() / 2
	check(img.get_pixel(cx, cy).a > 0.99 and img.get_pixel(0, 0).a < 0.01, "weiche Textur: innen deckend, Ecke leer")
	var edge := img.get_pixel(int(CardView.SOFT_MARGIN), cy).a
	check(absf(edge - 0.5) < 0.12, "weiche Textur: Kante halb (%.2f)" % edge)
	check(absf(img.get_pixel(10, 30).a - img.get_pixel(img.get_width() - 11, img.get_height() - 31).a) < 0.01, "weiche Textur: symmetrisch")

	print("RESULT: %d ok" % ok)
	quit(0 if failed == 0 else 1)


func tap_select(id: int) -> void:
	var p := tap_point(id)
	hand.touch_down(p, clock)
	step(3)
	hand.touch_up(p, clock)
	step(2)
