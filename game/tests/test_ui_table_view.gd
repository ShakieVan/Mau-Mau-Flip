extends SceneTree
# TableView und Bausteine (Modul F1b), headless: Abgleich mit der Sicht (Plätze gedreht, Rückseiten sichtbar/verdeckt,
# letzte Karte groß, Abzeichen ab 7), Stapel/Ablage/Farbe, Hinweise und Knöpfe, Eingaben (Ziehen, Erwischen, Großansicht),
# komplette Demo-Ereignisfolge mit Endzustand = Sicht, Überspringen bei Rückstand, Sichtschutz ohne Karten mit Halte-
# und Tippsperre, Farbwahl, Joker-Strahlen aus der sichtbaren Kontur, Effektstufe reduziert.

const CleanExit := preload("res://tests/clean_exit.gd")

var ok := 0
var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		ok += 1
	else:
		fails += 1
		print("FAIL: " + what)


func _initialize() -> void:
	call_deferred("run")


func _new_table(sample: TableSamples, seat := 0, with_hand := true) -> TableView:
	var t := TableView.new()
	root.add_child(t)
	if with_hand:
		t.set_hand(DemoHand.new())
	t.apply_view(sample.view_for(seat))
	return t


func _drain(t: TableView, max_frames := 4000) -> void:
	var guard := 0
	while t.director.is_busy() and guard < max_frames:
		await process_frame
		guard += 1


func _click(t: TableView, p: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = p
		t._gui_input(e)


func run() -> void:
	await _view_basics()
	await _rotation_and_backs()
	await _many_players()
	await _inputs()
	await _demo_run()
	await _skip_backlog()
	await _handover()
	await _wish_picker()
	await _rays()
	await _reduced()
	print("RESULT: %d ok" % ok)
	# Töne anhalten und aufräumen, sonst „resources still in use at exit“ (Flip- und Sieg-Ton laufen noch)
	await CleanExit.finish(self, 0 if fails == 0 else 1)


func _view_basics() -> void:
	var s := TableSamples.create(4, 5, [7, 6, 5, 1])
	s.set_top("hell_blau_9")
	var v := s.view_for(0)
	var t := _new_table(s)
	await process_frame
	check(t.seat_node(1) != null and t.seat_node(2) != null and t.seat_node(3) != null and t.seat_node(0) == null, "drei Gegner, kein eigener Platz")
	var lena := t.seat_node(1)
	check(str(lena.keys) == str(v["players"][1]["backs"]), "Fächer = sichtbare Rückseiten (sortiert geliefert)")
	check(lena.backs_visible(), "Rückseiten sichtbar")
	check(t.pile_top().current_key() == str(v["draw_back"]), "Stapel zeigt die Gegenseite der obersten Karte")
	check(t.discard_cards()[-1].current_key() == "hell_blau_9", "Ablage oben = top.face")
	check(t._color == "blau", "aktuelle Farbe")
	check(t.mau_button.mode == MauButton.Mode.IDLE, "Mau-Knopf ruhig")
	check(t.hint_bar.hint == "Du bist dran." and t.hint_bar.highlight, "Hinweis „Du bist dran“ hervorgehoben")
	# letzte Karte groß
	var mia := t.seat_node(3)
	var cards: Array = mia._cards
	check(cards.size() == 1 and (cards[0] as CardView).width > mia.card_w * 1.2, "letzte Karte groß")
	# Mau möglich, Erwischen, Behalten
	s.hands[0] = (s.hands[0] as Array).slice(0, 2)
	s.catch_targets = [3]
	var v2 := s.view_for(0)
	v2["hints"]["can_keep"] = true
	t.apply_view(v2)
	check(t.mau_button.mode == MauButton.Mode.READY, "Mau-Knopf bereit bei zwei Karten am Zug")
	check(mia.catchable and not lena.catchable, "Erwischen nur bei Mia")
	check(t._act_btns["keep"].visible and not t._act_btns["challenge"].visible, "Behalten sichtbar, Anzweifeln nicht")
	t.queue_free()
	await process_frame


func _rotation_and_backs() -> void:
	var s := TableSamples.create(4, 9, [5, 5, 5, 5])
	var t := _new_table(s, 2)
	await process_frame
	var c := t.table_center()
	# Aus Sicht von Platz 2: nächster (3) links, gegenüber (0) oben, voriger (1) rechts – gedreht, nicht gespiegelt
	check(t.seat_node(3).position.x < c.x and t.seat_node(1).position.x > c.x and t.seat_node(0).position.y < 150.0, "Ansicht von Platz 2 gedreht")
	check(t.seat_node(2) == null, "eigener Platz nicht als Gegner")
	# Rückseiten verdeckt → neutrale Rückseite
	s.backs_visible = false
	t.apply_view(s.view_for(2))
	var keys := t.seat_node(0).keys
	check(keys.size() == 5 and keys.count(CardTextures.BACK) == 5, "verdeckt: neutrale Rückseiten")
	check(not t.seat_node(0).backs_visible(), "verdeckt erkannt")
	# Tipp auf eine verdeckte Hand öffnet keine Großansicht
	_click(t, t.seat_node(0).fan_global_center())
	check(not t.backs_viewer.visible, "keine Großansicht bei verdeckten Rückseiten")
	s.backs_visible = true
	t.apply_view(s.view_for(2))
	_click(t, t.seat_node(0).fan_global_center())
	check(t.backs_viewer.visible and t.backs_viewer._cards.size() == 5, "Großansicht der Rückseiten zum Durchblättern")
	t.queue_free()
	await process_frame


func _many_players() -> void:
	for n in [2, 3, 6, 7, 10]:
		var sizes: Array = []
		for i in n:
			sizes.append(3 + i % 4)
		sizes[n - 1] = 1
		var s := TableSamples.create(n, 20 + n, sizes)
		var t := _new_table(s)
		await process_frame
		var compact: bool = n >= 7
		var all_ok := true
		for seat in range(1, n):
			var node := t.seat_node(seat)
			if node == null or node.compact != compact:
				all_ok = false
				continue
			var cards: Array = node._cards
			if compact and seat != n - 1 and not cards.is_empty():
				all_ok = false          # Abzeichen statt Fächer
			if seat == n - 1 and cards.size() != 1:
				all_ok = false          # letzte Karte groß, auch im Abzeichen
		check(all_ok, "%d Spieler: %s, letzte Karte groß" % [n, "Abzeichen" if compact else "Fächer"])
		t.queue_free()
		await process_frame


func _inputs() -> void:
	var s := TableSamples.create(4, 5, [5, 5, 5, 5])
	var t := _new_table(s)
	await process_frame
	var got: Array = []
	t.action.connect(func(a: Dictionary) -> void: got.append(a))
	_click(t, t.draw_pile_position())
	check(got.size() == 1 and got[0]["a"] == "draw", "Tipp auf den Stapel zieht (am Zug)")
	s.turn = 1
	t.apply_view(s.view_for(0))
	got.clear()
	_click(t, t.draw_pile_position())
	check(got.is_empty(), "nicht am Zug: kein Ziehen")
	s.catch_targets = [2]
	t.apply_view(s.view_for(0))
	var tom := t.seat_node(2)
	_click(t, tom.to_global(tom._catch_rect().get_center()))
	check(got.size() == 1 and got[0]["a"] == "catch" and int(got[0]["target"]) == 2, "Erwischen-Knopf: %s" % [got])
	got.clear()
	t.mau_button.mau_pressed.emit()
	check(got.size() == 1 and got[0]["a"] == "mau", "Mau-Knopf meldet mau")
	t.queue_free()
	await process_frame


func _demo_run() -> void:
	var sc := TableDemo.scenario()
	var s: TableSamples = sc["sample"]
	var steps: Array = sc["steps"]
	var t := _new_table(s)
	Engine.time_scale = 8.0
	var errors := 0
	for i in steps.size():
		var ev: Array = (steps[i] as Callable).call()
		var v := s.view_for(0)
		t.handle_state(s.events_for(0, ev), v)
		await _drain(t)
		await process_frame
		# nach jedem Abschnitt: Anzeige = Sicht
		if t.discard_cards().is_empty() or t.discard_cards()[-1].current_key() != str(v["top"]["face"]):
			errors += 1
			print("  Schritt %d: Ablage %s ≠ %s" % [i + 1, t.discard_cards()[-1].current_key() if not t.discard_cards().is_empty() else "-", v["top"]["face"]])
		for p in v["players"]:
			var node := t.seat_node(int(p["seat"]))
			if node != null and node.keys.size() != int(p["count"]):
				errors += 1
				print("  Schritt %d: Platz %d zeigt %d statt %d" % [i + 1, int(p["seat"]), node.keys.size(), int(p["count"])])
		if t.side != str(v["side"]) or not is_equal_approx(t.night, 1.0 if v["side"] == "dunkel" else 0.0):
			errors += 1
			print("  Schritt %d: Seite %s/%.2f" % [i + 1, t.side, t.night])
		var hand: DemoHand = t.hand
		if hand.cards.size() != (v["hand"] as Array).size():
			errors += 1
			print("  Schritt %d: Hand %d statt %d" % [i + 1, hand.cards.size(), (v["hand"] as Array).size()])
	Engine.time_scale = 1.0
	check(errors == 0, "Demo-Folge: nach jedem Schritt Anzeige = Sicht (%d Abweichungen)" % errors)
	check(t.director.played >= 25, "Ereignisse abgespielt: %d" % t.director.played)
	check(t.director.skipped == 0, "ohne Rückstand nichts übersprungen")
	check(t.round_end.visible and t.round_end.rows.size() == 4 and int(t.round_end.rows[0]["seat"]) == 0, "Rundenende mit Platzierungen")
	check(t.mau_button.mode != MauButton.Mode.READY, "Mau-Knopf nach Rundenende nicht bereit")
	check(not t.input_locked and not t.is_flipping(), "Eingaben wieder frei")
	t.queue_free()
	await process_frame


func _skip_backlog() -> void:
	var sc := TableDemo.scenario()
	var s: TableSamples = sc["sample"]
	var steps: Array = sc["steps"]
	var t := _new_table(s)
	# viele Abschnitte auf einmal (z. B. nach Verbindungsabbruch): Rückstand > 8 → überspringen
	for i in 6:
		var ev: Array = (steps[i] as Callable).call()
		t.handle_state(s.events_for(0, ev), s.view_for(0))
	await _drain(t)
	await process_frame
	var v := s.view_for(0)
	check(t.director.skipped > 0, "Rückstand übersprungen: %d" % t.director.skipped)
	check(t.discard_cards()[-1].current_key() == str(v["top"]["face"]) and t.side == "dunkel", "Endzustand nach dem Überspringen")
	check(is_equal_approx(t.night, 1.0), "Nacht gesetzt")
	t.queue_free()
	await process_frame


func _handover() -> void:
	var h := HandoverScreen.new()
	root.add_child(h)
	h.show_for("Lena", 0, 1, 4, 12, 47, "hell")
	await process_frame
	var cards := h.find_children("*", "CardView", true, false)
	check(cards.is_empty(), "Sichtschutz zeigt keine Karten")
	var revealed := [false]
	h.revealed.connect(func() -> void: revealed[0] = true)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = h._button_center()
	h._gui_input(press)
	check(not h._holding, "Tippsperre 350 ms")
	h._process(0.4)
	h._gui_input(press)
	check(h._holding, "danach halten möglich")
	h._process(0.3)
	check(not revealed[0] and h.visible, "300 ms reichen nicht")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	h._gui_input(release)
	h._process(0.3)
	h._gui_input(press)
	h._process(0.25)
	h._process(0.27)
	check(revealed[0] and not h.visible, "500 ms halten deckt auf")
	h.queue_free()
	await process_frame


func _wish_picker() -> void:
	var s := TableSamples.create(4, 5, [5, 5, 5, 5])
	var t := _new_table(s)
	await process_frame
	var chosen: Array = []
	t.wish_picker.color_chosen.connect(func(c: String) -> void: chosen.append(c))
	t.open_color_fields()
	for i in 20:
		await process_frame
	var wp := t.wish_picker
	var cols := wp.colors()
	check(cols == UiPalette.LIGHT_COLORS, "Farben der aktiven Seite")
	check(wp.hover(wp.to_global(wp.field_center(2))) == cols[2], "Feld unter dem Finger")
	check(wp.drop(wp.to_global(wp.field_center(2))) == cols[2] and chosen == [cols[2]], "Loslassen wählt die Farbe")
	check(not wp.is_open(), "danach geschlossen")
	s.flip()
	t.apply_view(s.view_for(0))
	t.open_color_wheel()
	for i in 20:
		await process_frame
	var c := wp.to_global(wp.wheel_center)
	check(wp.colors() == UiPalette.DARK_COLORS, "Nachtfarben nach dem Flip")
	check(wp.color_at(c + Vector2(-120, -100)) == "pink" and wp.color_at(c + Vector2(120, -100)) == "tuerkis" \
		and wp.color_at(c + Vector2(120, 100)) == "orange" and wp.color_at(c + Vector2(-120, 100)) == "lila", "Farbrad-Viertel")
	check(wp.color_at(c) == "" and wp.color_at(c + Vector2(600, 0)) == "", "Mitte und außerhalb: keine Farbe")
	var counts := t._own_counts()
	var total := 0
	for k in counts:
		total += int(counts[k])
	check(total <= 5 and total >= 1, "Anzahl eigener Karten je Farbe")
	t.queue_free()
	await process_frame


func _rays() -> void:
	var samples := JokerRays.outline_samples(Vector2(120, 186), 8.6)
	check(samples.size() >= 50 and samples.size() <= 110, "Konturproben: %d" % samples.size())
	var normals_ok := true
	for smp in samples:
		var p: Vector2 = smp["pos"]
		var n: Vector2 = smp["normal"]
		if not is_equal_approx(n.length(), 1.0) or p.dot(n) <= 0.0:
			normals_ok = false
	check(normals_ok, "Normalen zeigen nach außen und sind normiert")
	var all := JokerRays.visible_samples(Transform2D.IDENTITY, samples, [])
	var cover := PackedVector2Array([Vector2(0, -200), Vector2(200, -200), Vector2(200, 200), Vector2(0, 200)])
	var half := JokerRays.visible_samples(Transform2D.IDENTITY, samples, [cover])
	check((all[0] as PackedVector2Array).size() == samples.size(), "ohne Abdeckung alle sichtbar")
	var visible_right := 0
	for p in half[0]:
		if (p as Vector2).x > 0.5:
			visible_right += 1
	check((half[0] as PackedVector2Array).size() < samples.size() * 0.6 and visible_right == 0, "verdeckte Hälfte strahlt nicht")
	# an echten Karten: rechte Nachbarkarte deckt einen Teil ab
	var holder := Node2D.new()
	root.add_child(holder)
	var joker := CardView.new().setup(1, "hell_wuenscher", "", true)
	joker.width = 120.0
	holder.add_child(joker)
	var other := CardView.new().setup(2, "hell_rot_7", "", true)
	other.width = 120.0
	other.position = Vector2(60, 0)
	holder.add_child(other)
	var r := JokerRays.attach(joker, [other])
	await process_frame
	await process_frame
	check(r.visible_count > 0 and r.visible_count < samples.size(), "Strahlen nur aus dem sichtbaren Teil: %d" % r.visible_count)
	check(joker.get_child(0) == r, "Strahlen unter der Karte (erstes Kind)")
	other.position = Vector2(400, 0)
	await process_frame
	check(r.visible_count > samples.size() * 0.9, "frei liegend: ganze Kontur")
	check(JokerRays.is_joker("dunkel_farbjagd") and not JokerRays.is_joker("dunkel_lila_plus5"), "Joker erkennen")
	holder.queue_free()
	await process_frame


func _reduced() -> void:
	var fx := TableEffects.new()
	root.add_child(fx)
	fx.land_burst(Vector2.ZERO, Color.WHITE, true)
	fx.reduced = true
	fx.land_burst(Vector2.ZERO, Color.WHITE, true)
	var ps := fx.find_children("*", "CPUParticles2D", false, false)
	check(ps.size() == 2 and (ps[1] as CPUParticles2D).amount < (ps[0] as CPUParticles2D).amount, "reduziert: weniger Teilchen")
	var s := TableSamples.create(4, 5, [5, 5, 5, 5])
	var t := _new_table(s)
	t.reduced = true
	t._speed = 1.0
	check(is_equal_approx(t._d(1.0), 0.6), "reduziert: kürzere Abläufe")
	s.give(3, "hell_blau_flip")
	var ev := s.play(3, s.find_any(3, "hell_blau_flip"))
	ev.append_array(s.flip())
	t.director.auto_process = false
	t.handle_state(ev, s.view_for(0))
	var d := t.play_event({"e": "flip", "side": "dunkel"}, 1.0)
	check(d <= 0.71, "Flip reduziert ≈ 0,7 s (%.2f)" % d)
	t.director.flush()
	t.show_notice("Nicht am Zug")
	t.show_notice("Nicht am Zug")
	check(t.hint_bar.active_toasts() == 1, "gleiche Meldung nicht doppelt")
	t.queue_free()
	fx.queue_free()
	await process_frame
