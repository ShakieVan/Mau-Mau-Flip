extends SceneTree
# Modul F1a: HandView headless mit Testuhr und festen Schritten: Austeilen und Sortieren, Stufenwechsel mit Hysterese, Tipp hebt an,
# zweiter Tipp spielt aus (nicht spielbar → play_denied), Wischen nach oben (Schwelle, Abbruch), Halten → Großansicht → „?“ (Zug nach
# unten und Knopf), Ausspielen aus der offenen Großansicht, Umsortieren per Halten + seitlich (→ „manuell“), neue Karten (rechts bzw.
# einsortiert, Schimmern), Entfernen, Karussell mit Schwung, Einrasten und Gummiband, Lupe beim Gleiten, Flip mit Welle und
# Neusortierung, Rückseiten ansehen, Eingabe aus, Auswahl aufheben, take_card/cancel_play, Zeitgrenze für ausgespielte Karten.
# Aufruf: tools/godot_run.ps1 -Script res://tests/test_ui_hand_view.gd -Headless
const DT := 1.0 / 60.0
var ok := 0
var failed := 0
var hand: HandView
var clock := 1000.0
var log: Array = []


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


# echte Zeit für Tweens (Wenden, Schütteln)
func wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
		step()


func cards(faces: Array, first_id := 0) -> Array:
	var out: Array = []
	for i in faces.size():
		out.append({"id": first_id + i, "face": faces[i], "back": "dunkel_lila_%d" % (1 + i % 9)})
	return out


func many(n: int) -> Array:
	var colors := ["rot", "gelb", "gruen", "blau"]
	var faces: Array = []
	for i in n:
		faces.append("hell_%s_%d" % [colors[i % 4], 1 + (i / 4) % 9])
	return cards(faces)


# Punkt im sichtbaren Streifen oben links einer Karte (lokal = global, die Hand liegt im Ursprung)
func tap_point(id: int) -> Vector2:
	var v := hand.card_view(id)
	var h := v.card_size() * v.scale.x * 0.5
	return v.position + Vector2(-h.x + 22.0, -h.y + 50.0).rotated(v.rotation)


func tap(id: int) -> void:
	var p := tap_point(id)
	hand.touch_down(p, clock)
	step(4)
	hand.touch_up(p, clock)
	step(2)


# Zug in Schritten zu je einem Bild
func drag(from: Vector2, to: Vector2, frames: int, release := true) -> void:
	hand.touch_down(from, clock)
	for k in range(1, frames + 1):
		step()
		hand.touch_move(from.lerp(to, float(k) / frames), clock)
	if release:
		step()
		hand.touch_up(to, clock)
		step()


func events(name: String) -> Array:
	return log.filter(func(e: Array) -> bool: return e[0] == name)


func run() -> void:
	hand = HandView.new()
	hand.haptics = false
	root.add_child(hand)
	hand.layout_rect = HandView.DEFAULT_RECT    # wie der Tisch: fester Handbereich (headless ist das Fenster höher als 720)
	hand.set_process(false)
	hand.clock_ms = clock
	hand.play_requested.connect(func(id: int, g: Vector2) -> void: log.append(["play", id, g]))
	hand.help_requested.connect(func(id: int, face: String) -> void: log.append(["help", id, face]))
	hand.drag_started.connect(func(id: int, face: String) -> void: log.append(["drag_started", id, face]))
	hand.drag_moved.connect(func(g: Vector2) -> void: log.append(["drag_moved", g]))
	hand.drag_ended.connect(func(id: int, g: Vector2, played: bool) -> void: log.append(["drag_ended", id, played]))
	hand.order_changed.connect(func(ids: Array) -> void: log.append(["order", ids]))
	hand.selection_changed.connect(func(id: int) -> void: log.append(["select", id]))
	hand.play_denied.connect(func(id: int) -> void: log.append(["denied", id]))
	hand.sort_mode_changed.connect(func(m: String) -> void: log.append(["sort_mode", m]))
	hand.big_view_changed.connect(func(id: int) -> void: log.append(["big", id]))

	# Austeilen und Sortieren (Farbe)
	var five := cards(["hell_wuenscher", "hell_blau_9", "hell_rot_7", "hell_gelb_3", "hell_rot_2"])
	hand.set_cards(five)
	check(hand.get_order() == [4, 2, 3, 1, 0], "Farbe: rot 2, rot 7, gelb 3, blau 9, Joker (%s)" % [hand.get_order()])
	check(hand.get_mode() == HandLayout.Mode.FAN, "5 Karten: Fächer")
	check(not hand.card_view(2).is_shimmering(), "Austeilen ohne Schimmern")
	settle(1.5)
	var xs_ok := true
	var z_ok := true
	var order := hand.get_order()
	for i in range(1, order.size()):
		if hand.card_view(order[i]).position.x <= hand.card_view(order[i - 1]).position.x:
			xs_ok = false
		if hand.card_view(order[i]).get_index() <= hand.card_view(order[i - 1]).get_index():
			z_ok = false
	check(xs_ok and z_ok, "Karten von links nach rechts, rechte über linker (Kindreihenfolge)")
	var base_y := hand.card_view(2).position.y
	check(absf(base_y - 720.0) < 25.0, "Hand unten, obere Hälfte sichtbar (y %.0f)" % base_y)

	# Tipp hebt an, zweiter Tipp bei nicht spielbarer Karte: Nein
	log.clear()
	tap(2)
	check(hand.get_selected() == 2 and events("select") == [["select", 2]], "Tipp hebt an (Auswahl)")
	settle(0.6)
	check(hand.card_view(2).position.y < base_y - 30.0, "angehobene Karte liegt höher")
	tap(2)
	check(events("denied") == [["denied", 2]] and events("play").is_empty(), "zweiter Tipp auf nicht spielbare Karte: Nein")
	check(hand.get_selected() == 2, "Auswahl bleibt nach Nein")

	# spielbar: zweiter Tipp spielt aus
	hand.set_playable([2, 1, 0])
	log.clear()
	tap(2)
	check(events("play").size() == 1 and events("play")[0][1] == 2, "zweiter Tipp spielt aus")
	check(not hand.get_order().has(2) and hand.get_selected() == -1, "ausgespielte Karte verlässt die Hand sofort")
	settle(0.5)
	hand.cancel_play(2)
	check(hand.get_order() == [4, 2, 3, 1, 0], "abgelehnt: Karte kehrt an ihren Platz zurück")
	settle(1.0)

	# Doppeltipp auf eine nicht gewählte Karte
	log.clear()
	var p1 := tap_point(1)
	hand.touch_down(p1, clock)
	step(3)
	hand.touch_up(p1, clock)
	step(6)
	hand.touch_down(p1, clock)
	step(3)
	hand.touch_up(p1, clock)
	check(events("play").size() == 1 and events("play")[0][1] == 1, "Doppeltipp spielt aus")
	hand.cancel_play(1)
	settle(1.0)

	# Wischen nach oben
	log.clear()
	var p0 := tap_point(0)
	drag(p0, p0 + Vector2(6, -230), 14)
	check(events("drag_started") == [["drag_started", 0, "hell_wuenscher"]], "drag_started mit Gesicht")
	check(events("drag_moved").size() >= 10, "drag_moved laufend")
	check(events("play").size() == 1 and events("drag_ended") == [["drag_ended", 0, true]], "Wischen über die Schwelle spielt aus")
	check(events("play").size() == 1 and events("play")[0][2].distance_to(p0 + Vector2(6, -230)) < 1.0, "Ablageposition = Finger")
	hand.cancel_play(0)
	settle(1.0)
	log.clear()
	p0 = tap_point(0)
	hand.touch_down(p0, clock)
	for k in range(1, 30):
		step()
		hand.touch_move(p0 + Vector2(0, -3.0 * k), clock)
	step(20)
	hand.touch_up(p0 + Vector2(0, -87), clock)
	check(events("play").is_empty() and events("drag_ended") == [["drag_ended", 0, false]], "langsam und zu kurz: kein Ausspielen")
	settle(1.0)
	check(absf(hand.card_view(0).position.y - hand.card_view(1).position.y) < 40.0, "Karte federt zurück in die Hand")
	log.clear()
	var p3 := tap_point(3)
	drag(p3, p3 + Vector2(0, -240), 12)
	check(events("denied") == [["denied", 3]] and events("drag_ended") == [["drag_ended", 3, false]], "nicht spielbar hochgewischt: Nein")
	settle(1.0)

	# Halten → Großansicht → nach unten auf das „?“
	log.clear()
	var ph := tap_point(3)
	hand.touch_down(ph, clock)
	step(25)
	check(hand.is_big_view_open() and events("big") == [["big", 3]], "Halten 350 ms öffnet die Großansicht")
	settle(0.4)
	hand.touch_move(ph + Vector2(0, 30), clock)
	hand.touch_move(ph + Vector2(2, 82), clock)
	step()
	hand.touch_up(ph + Vector2(2, 82), clock)
	check(events("help") == [["help", 3, "hell_gelb_3"]], "Zug nach unten auf das „?“ öffnet die Kartenhilfe")
	check(not hand.is_big_view_open(), "Großansicht danach zu")
	settle(0.5)

	# Halten und loslassen: Großansicht bleibt, „?“-Knopf
	log.clear()
	ph = tap_point(4)
	hand.touch_down(ph, clock)
	step(25)
	hand.touch_up(ph, clock)
	settle(0.4)
	check(hand.is_big_view_open(), "Loslassen ohne Zug: Großansicht bleibt offen")
	var btn: Vector2 = hand._button_pos
	var big := hand.card_view(4)
	check(big.scale.x > 1.3, "Großansicht vergrößert (%.2f)" % big.scale.x)
	check(btn.y < 720.0 and btn.x < 1600.0 and not big.contains_global_point(btn), "„?“-Knopf neben der Karte")
	hand.touch_down(btn, clock)
	hand.touch_up(btn, clock)
	check(events("help") == [["help", 4, "hell_rot_2"]] and not hand.is_big_view_open(), "„?“-Knopf öffnet die Hilfe")
	settle(0.5)
	# offene Großansicht: Tipp daneben schließt
	ph = tap_point(4)
	hand.touch_down(ph, clock)
	step(25)
	hand.touch_up(ph, clock)
	settle(0.3)
	hand.touch_down(Vector2(100, 100), clock)
	hand.touch_up(Vector2(100, 100), clock)
	check(not hand.is_big_view_open(), "Tipp daneben schließt die Großansicht")
	settle(0.5)
	# offene Großansicht: auf der Karte nach oben wischen spielt aus
	log.clear()
	ph = tap_point(0)
	hand.touch_down(ph, clock)
	step(25)
	hand.touch_up(ph, clock)
	settle(0.4)
	var c0 := hand.card_view(0).position
	drag(c0, c0 + Vector2(0, -240), 10)
	check(events("play").size() == 1 and events("play")[0][1] == 0, "aus der offenen Großansicht hochwischen spielt aus")
	hand.cancel_play(0)
	settle(1.0)

	# Halten + seitlich = umsortieren
	log.clear()
	var before := hand.get_order()
	var pr := tap_point(4)
	hand.touch_down(pr, clock)
	step(25)
	for k in range(1, 25):
		step()
		hand.touch_move(pr + Vector2(14.0 * k, 0), clock)
	step()
	hand.touch_up(pr + Vector2(336, 0), clock)
	var after := hand.get_order()
	check(after != before and after.find(4) > before.find(4), "Halten + seitlich schiebt die Karte nach rechts (%s → %s)" % [before, after])
	check(hand.sort_mode == "manuell" and events("sort_mode") == [["sort_mode", "manuell"]], "Umsortieren schaltet auf manuell")
	check(events("order").size() == 1 and events("order")[0][1] == after, "order_changed mit neuer Folge")
	settle(1.2)

	# neue Karte: manuell rechts, schimmert
	var six := five.duplicate()
	six.append({"id": 9, "face": "hell_rot_1", "back": "dunkel_pink_3"})
	hand.set_cards(six)
	check(hand.get_order()[-1] == 9, "manuell: neue Karte rechts")
	check(hand.card_view(9).is_shimmering(), "neue Karte schimmert")
	settle(1.0)
	# Sortierung wieder an: einsortiert
	log.clear()
	hand.set_sort_mode("farbe")
	check(hand.get_order()[0] == 9 and events("order").size() == 1, "Farbe: rot 1 ganz links, order_changed")
	hand.set_sort_mode("wert")
	check(hand.get_order() == [9, 4, 3, 2, 1, 0], "Wert: 1, 2, 3, 7, 9, Joker (%s)" % [hand.get_order()])
	hand.set_sort_mode("farbe")
	settle(1.0)
	# Entfernen blendet aus
	var gone := hand.card_view(9)
	hand.set_cards(five)
	check(not hand.get_order().has(9), "fehlende Karte verlässt die Hand")
	settle(0.5)
	check(not is_instance_valid(gone) or gone.is_queued_for_deletion(), "ausgeblendet und freigegeben")

	# Stufenwechsel mit Hysterese
	hand.set_cards(many(12))
	check(hand.get_mode() == HandLayout.Mode.LENS, "12 Karten: Lupe")
	settle(1.0)
	# Lupe: gleiten hebt und vergrößert die Karte unter dem Finger
	var lp := tap_point(5)
	hand.touch_down(lp, clock)
	hand.touch_move(lp + Vector2(20, 0), clock)
	hand.touch_move(lp + Vector2(24, 0), clock)
	settle(0.5)
	var biggest := -1
	var big_s := 0.0
	for id in hand.get_order():
		if hand.card_view(id).scale.x > big_s:
			big_s = hand.card_view(id).scale.x
			biggest = id
	check(big_s > 1.1 and absi(hand.get_order().find(biggest) - 5) <= 1, "Lupe vergrößert die Karte unter dem Finger (%.2f)" % big_s)
	hand.touch_up(lp + Vector2(24, 0), clock)
	settle(0.6)
	check(hand.card_view(biggest).scale.x < 1.03, "Lupe schließt beim Loslassen")
	hand.set_cards(many(16))
	check(hand.get_mode() == HandLayout.Mode.CAROUSEL, "16 Karten: Karussell")
	hand.set_cards(many(14))
	check(hand.get_mode() == HandLayout.Mode.CAROUSEL, "14 Karten: bleibt Karussell")
	hand.set_cards(many(13))
	check(hand.get_mode() == HandLayout.Mode.LENS, "13 Karten: zurück zur Lupe")

	# Karussell: Schwung und Einrasten
	hand.set_cards(many(25))
	settle(1.5)
	var s0 := hand.get_scroll()
	check(absf(s0 - 12.0) < 0.01, "Karussell beginnt in der Mitte (%.2f)" % s0)
	var cx := Vector2(800, 640)
	drag(cx, cx + Vector2(-300, 0), 8)
	var tgt: float = hand._scroll_target
	check(tgt > s0 + 3.0 and tgt == roundf(tgt), "Schwung nach links dreht weiter und rastet auf einer Karte ein (%.2f)" % tgt)
	settle(2.5)
	check(absf(hand.get_scroll() - tgt) < 0.01, "eingerastet (%.3f)" % hand.get_scroll())
	# Gummiband am Anfang
	var pull := HandLayout.FISH_S_MAX * tgt + 300.0
	drag(Vector2(300, 640), Vector2(300 + pull, 640), 60, false)
	var sc := hand.get_scroll()
	var raw := tgt - pull / HandLayout.FISH_S_MAX
	check(sc < 0.0 and sc > raw, "Gummiband: über den Anfang hinaus gedämpft (%.2f, roh %.2f)" % [sc, raw])
	step(20)
	hand.touch_up(Vector2(300 + pull, 640), clock)
	settle(2.0)
	check(absf(hand.get_scroll()) < 0.01, "federt zurück auf die erste Karte")
	# Tipp auf eine Karte am Rand dreht sie in die Mitte
	var right_id := hand.get_order()[3]
	tap(right_id)
	settle(2.0)
	check(absf(hand.get_scroll() - 3.0) < 0.02 and hand.get_selected() == right_id, "Tipp auf Karte im Karussell: in die Mitte und angehoben")

	# Flip: Welle, dann Neusortierung nach der neuen Seite
	hand.set_cards(five)
	settle(1.5)
	var flipped: Array = []
	var new_faces := ["dunkel_lila_4", "dunkel_pink_9", "dunkel_orange_1", "dunkel_wuenscher", "dunkel_pink_2"]
	for i in five.size():
		flipped.append({"id": five[i].id, "face": new_faces[i], "back": five[i].face})
	hand.set_cards(flipped)
	check(hand.card_view(0).current_key() == "hell_wuenscher", "Flip: zunächst noch die alte Seite sichtbar")
	await wait(0.9)
	var turned := true
	for c in flipped:
		if hand.card_view(c.id).current_key() != c.face:
			turned = false
	check(turned, "Flip: alle Karten zeigen die neue Seite")
	check(hand.get_order() == [4, 1, 2, 0, 3], "Flip: neu sortiert nach dunkler Seite (%s)" % [hand.get_order()])

	# Eigene Rückseiten ansehen
	hand.set_peek_backs(true)
	await wait(0.7)
	var backs := true
	for c in flipped:
		if hand.card_view(c.id).current_key() != c.back:
			backs = false
	check(backs, "Rückseiten: alle Karten gewendet")
	log.clear()
	tap(1)
	check(events("select").is_empty() and hand.get_selected() == -1, "Rückseiten: kein Anheben/Ausspielen")
	hand.set_peek_backs(false)
	await wait(0.7)
	check(hand.card_view(1).current_key() == "dunkel_pink_9", "Rückseiten aus: Vorderseiten wieder da")

	# Eingabe aus
	hand.set_enabled(false)
	check(not hand.touch_down(tap_point(1), clock), "Eingabe aus: Hand nimmt keine Berührung an")
	hand.set_enabled(true)

	# Auswahl aufheben per Tipp daneben; play_selected kurz danach spielt trotzdem die gewählte Karte
	hand.set_playable([1])
	tap(1)
	check(hand.get_selected() == 1, "gewählt")
	log.clear()
	check(not hand.touch_down(Vector2(800, 200), clock), "Tipp außerhalb gehört nicht der Hand")
	check(hand.get_selected() == -1, "Tipp außerhalb hebt die Auswahl auf")
	check(hand.play_selected() and events("play").size() == 1 and events("play")[0][1] == 1, "play_selected direkt danach (Ablage angetippt)")

	# take_card übergibt den Knoten
	var view := hand.take_card(1)
	check(view != null and view.get_parent() == null and not hand.get_order().has(1), "take_card: Knoten ohne Eltern")
	view.free()

	# ausgespielt, aber keine Antwort: nach 4 s zurück
	hand.set_playable([0])
	tap(0)
	tap(0)
	check(not hand.get_order().has(0), "ausgespielt")
	settle(4.2)
	check(hand.get_order().has(0), "nach 4 s ohne Antwort zurück in der Hand")

	# Adapter für den Tisch (TableView, Modul F1b)
	hand.set_cards([])
	settle(0.5)
	hand.set_sort_mode("farbe")
	var tview := {"hand": cards(["hell_gelb_4", "hell_rot_9", "hell_gelb_1"]), "hints": {"playable": [1]}}
	hand.apply_view(tview)
	check(hand.get_order() == [1, 2, 0], "apply_view: Karten sortiert (%s)" % [hand.get_order()])
	check(hand.own_color_counts() == {"gelb": 2, "rot": 1}, "own_color_counts")
	settle(1.0)
	log.clear()
	tap(1)
	tap(1)
	check(events("play").size() == 1, "apply_view: spielbare Karten aus hints")
	hand.cancel_play(1)
	var lp2 := hand.landing_point()
	check(lp2.y > 600.0 and absf(lp2.x - hand.layout_rect.get_center().x) < 1.0, "landing_point in der Handmitte")
	hand.receive_card({"id": 7, "face": "hell_rot_2", "back": "dunkel_pink_1"}, lp2)
	check(hand.get_order() == [7, 1, 2, 0] and hand.card_view(7).is_shimmering(), "receive_card: einsortiert und schimmert")
	check(hand.card_view(7).position.distance_to(lp2) < 1.0, "receive_card: startet am Landepunkt")
	hand.receive_card({"id": -1, "face": "hell_rot_3", "back": ""}, lp2)
	check(hand.get_order().size() == 4, "receive_card ohne Kennung: abwarten bis apply_view")
	settle(1.0)
	hand.flip_wave(0.05, 0.02, 0.2, {7: "dunkel_lila_2", 1: "dunkel_pink_5", 2: "dunkel_orange_3", 0: "dunkel_wuenscher"})
	check(hand.get_order() == [1, 2, 7, 0], "flip_wave: neue Folge nach dunkler Seite (%s)" % [hand.get_order()])
	await wait(0.6)
	check(hand.card_view(7).current_key() == "dunkel_lila_2" and hand.card_view(7).back_key == "hell_rot_2", "flip_wave: gewendet, alte Seite ist Rückseite")
	hand.set_input_locked(true)
	check(not hand.is_enabled(), "set_input_locked sperrt")
	hand.set_input_locked(false)

	print("RESULT: %d ok" % ok)
	quit(0 if failed == 0 else 1)
