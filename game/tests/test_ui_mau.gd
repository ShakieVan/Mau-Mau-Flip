extends SceneTree
# T2 „Mau für alle“ (AGENTS.md Nr. 21), headless: Ereignis „mau“ eines Gegners → Ton angefordert und gespielt, Sprechblase beim
# Rufenden; eigener Knopf ohne Ton (Ton erst mit dem Ereignis, einmal), Entprellung je Platz, Mau-Ton aus = still mit Blase,
# „finish“ → „mau_mau“ und Doppelblase, Zufallswahl der Varianten (mind. 5 am Tag, Neon nur nachts, keine Wiederholung),
# reduziert = schlicht, Lage der Blasen im Bildschirm (4, 8, 10 Spieler), alle Varianten laufen durch und räumen sich ab.

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


func _table(sample: TableSamples, seat := 0) -> TableView:
	var t := TableView.new()
	root.add_child(t)
	t.set_hand(DemoHand.new())
	t.apply_view(sample.view_for(seat))
	t.director.auto_process = false
	return t


# Ereignisse sofort abspielen (Regie ohne Wartezeit)
func _events(t: TableView, events: Array, view: Dictionary) -> void:
	t.director.step(30.0)
	t.handle_state(events, view)
	t.director.step(30.0)


func _bubbles(t: TableView) -> Array[TableEffects.MauBubbleFx]:
	var out: Array[TableEffects.MauBubbleFx] = []
	for c in t.fx_top.get_children():
		if c is TableEffects.MauBubbleFx and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _last_request() -> Dictionary:
	return MauSound.requests.back() if not MauSound.requests.is_empty() else {}


func run() -> void:
	var app := UiApp.app()
	var st: AppSettings = app.get("settings") if app != null else null
	check(st != null, "App mit Einstellungen vorhanden")
	if st == null:
		await CleanExit.finish(self, 1)
		return
	var had_mau := st.has_value("mau_ton")
	var old_mau: Variant = st.get_value("mau_ton")
	var had_fx := st.has_value("effekte")
	var old_fx: Variant = st.get_value("effekte")
	st.set_value("mau_ton", "normal")
	st.set_value("effekte", "voll")
	MauSound.reset()
	var has_file := AppSound.path_for("mau") != "" and AppSound.path_for("mau_mau") != ""
	check(has_file, "Aufnahmen mau.ogg und mau_mau.ogg vorhanden")

	await _opponent_and_own(app)
	await _muted(st)
	await _finish()
	await _random_and_reduced()
	await _placement()
	await _all_variants()

	if had_mau:
		st.set_value("mau_ton", old_mau)
	else:
		st.reset("mau_ton")
	if had_fx:
		st.set_value("effekte", old_fx)
	else:
		st.reset("effekte")
	MauSound.reset()
	print("RESULT: %d ok" % ok)
	await CleanExit.finish(self, 0 if fails == 0 else 1)


func _opponent_and_own(app: Node) -> void:
	var s := TableSamples.create(4, 5, [5, 1, 5, 5])
	s.mau[1] = true
	var t := _table(s)
	await process_frame
	var v := s.view_for(0)
	# Gegner (Platz 1) ruft Mau: Ton auf diesem Gerät, Blase an seinem Avatar
	_events(t, [{"e": "mau", "seat": 1}], v)
	var r := _last_request()
	check(MauSound.requests.size() == 1 and str(r.get("sound", "")) == "mau" and int(r.get("seat", -1)) == 1, "Gegner-Mau fordert den Ton an (%s)" % [MauSound.requests])
	check(bool(r.get("played", false)), "Gegner-Mau: Ton gespielt")
	var snd: Variant = app.get("sound")
	check(snd is AppSound and (snd as AppSound).last_played == "mau" and (snd as AppSound).last_file == "mau", "App.sound spielte die Aufnahme „Mao“")
	var bs := _bubbles(t)
	check(bs.size() == 1 and TableEffects.mau_variants(t.night > 0.5).has(bs[0].variant), "eine Blase mit gültiger Variante (%s)" % [bs[0].variant if bs.size() > 0 else "-"])
	if bs.size() > 0:
		var node := t.seat_node(1)
		var d := bs[0].get_global_transform_with_canvas().origin.distance_to(node.get_global_transform_with_canvas() * node.to_local(node.avatar_global()))
		check(d < 200.0, "Blase sitzt am Rufenden (Abstand %.0f px)" % d)
		check(bool(node.player.get("mau", false)), "Mau-Marke am Gegner")
	# Eigener Knopf: Aktion ohne Ton; Ton kommt einmal mit dem Ereignis
	var got: Array = []
	t.action.connect(func(a: Dictionary) -> void: got.append(a))
	var before := MauSound.requests.size()
	t.mau_button.mau_pressed.emit()
	check(got.size() == 1 and str(got[0].get("a", "")) == "mau", "Mau-Knopf meldet mau")
	check(MauSound.requests.size() == before, "Mau-Knopf allein spielt keinen Ton")
	_events(t, [{"e": "mau", "seat": 0}], v)
	r = _last_request()
	check(MauSound.requests.size() == before + 1 and int(r.get("seat", -1)) == 0 and bool(r.get("played", false)), "eigenes Mau-Ereignis: Ton einmal")
	bs = _bubbles(t)
	if bs.size() > 0:
		var own: TableEffects.MauBubbleFx = bs.back()
		var btn := t.mau_button.get_global_rect()
		var p := own.get_global_transform_with_canvas().origin
		check(p.y < btn.position.y and absf(p.x - btn.get_center().x) < 160.0, "eigene Blase über dem Mau-Knopf (%s, Knopf %s)" % [p, btn])
	# Wiederholung desselben Platzes binnen 1 s: entprellt; anderer Platz sofort: klingt
	_events(t, [{"e": "mau", "seat": 0}], v)
	check(not bool(_last_request().get("played", true)), "derselbe Platz binnen 1 s: entprellt")
	_events(t, [{"e": "mau", "seat": 2}], v)
	check(bool(_last_request().get("played", false)) and int(_last_request().get("seat", -1)) == 2, "anderer Platz sofort: klingt")
	check(_bubbles(t).size() == 4, "jede Ansage zeigt eine Blase (%d)" % _bubbles(t).size())
	# Blasen räumen sich selbst ab (höchstens 1,9 s)
	await create_timer(2.1).timeout
	check(_bubbles(t).is_empty(), "Blasen nach Ablauf entfernt (%d übrig)" % _bubbles(t).size())
	t.queue_free()
	await process_frame


func _muted(st: AppSettings) -> void:
	var s := TableSamples.create(4, 6, [5, 5, 5, 1])
	var t := _table(s)
	await process_frame
	st.set_value("mau_ton", "aus")
	MauSound.reset()
	_events(t, [{"e": "mau", "seat": 3}], s.view_for(0))
	check(MauSound.requests.size() == 1 and not bool(_last_request().get("played", true)), "Mau-Ton aus: kein Ton")
	check(_bubbles(t).size() == 1, "Mau-Ton aus: Blase trotzdem sichtbar")
	st.set_value("mau_ton", "normal")
	t.queue_free()
	await process_frame


func _finish() -> void:
	var s := TableSamples.create(4, 7, [5, 5, 0, 5])
	var t := _table(s)
	await process_frame
	MauSound.reset()
	_events(t, [{"e": "finish", "seat": 2, "place": 1}], s.view_for(0))
	var r := _last_request()
	check(str(r.get("sound", "")) == "mau_mau" and int(r.get("seat", -1)) == 2 and bool(r.get("played", false)), "Fertig: „Mao-Mao“ gespielt (%s)" % [r])
	var bs := _bubbles(t)
	check(bs.size() == 1 and bs[0].variant == "maumau" and bs[0].is_big(), "Fertig: große Doppelblase „Mau-Mau!“")
	if bs.size() > 0:
		check(bs[0].total() >= 1.6 and bs[0].total() <= 2.0, "Mau-Mau dauert 1,6–2,0 s (%.2f)" % bs[0].total())
	# eigener Platz fertig
	_events(t, [{"e": "finish", "seat": 0, "place": 2}], s.view_for(0))
	check(str(_last_request().get("sound", "")) == "mau_mau" and int(_last_request().get("seat", -1)) == 0, "eigenes Fertig: Ton angefordert")
	t.queue_free()
	await process_frame


func _random_and_reduced() -> void:
	var s := TableSamples.create(4, 8, [5, 5, 5, 5])
	var t := _table(s)
	await process_frame
	t.set_night(0.0)
	var seen := {}
	var prev := ""
	var repeats := 0
	for i in 80:
		var v := t.pick_mau_variant()
		seen[v] = true
		if v == prev:
			repeats += 1
		prev = v
	check(seen.size() >= 5 and not seen.has("neon"), "Tag: mindestens 5 Varianten gelost, kein Neon (%s)" % [seen.keys()])
	check(repeats == 0, "nie zweimal dieselbe Variante hintereinander")
	t.set_night(1.0)
	seen.clear()
	for i in 80:
		seen[t.pick_mau_variant()] = true
	check(seen.size() == 6 and seen.has("neon"), "Nacht: alle 6 Varianten inkl. Neon (%s)" % [seen.keys()])
	for v in TableEffects.MAU_VARIANTS:
		check(TableEffects.MAU_ALL.has(v), "Variante %s bekannt" % v)
	t.reduced = true
	check(t.pick_mau_variant() == "schlicht", "reduziert: schlichte Blase")
	var b := t.show_mau(1, true)
	check(b.variant == "maumau_schlicht", "reduziert: schlichte Mau-Mau-Blase")
	t.reduced = false
	t.queue_free()
	await process_frame


# Jede Blase liegt ganz im Bildschirm, verdeckt den Avatar des Rufenden nicht und zeigt mit dem Schwanz zu ihm
func _placement() -> void:
	for n in [4, 8, 10]:
		var sizes: Array = []
		for i in n:
			sizes.append(1 if i % 3 == 1 else 4)
		var s := TableSamples.create(n, 11 + n, sizes)
		var t := _table(s)
		await process_frame
		var screen := Rect2(Vector2.ZERO, t.size if t.size.x > 10.0 else TableLayout.BASE)
		var bad: Array = []
		for seat in n:
			for big in [false, true]:
				var b := t.show_mau(seat, big, "maumau" if big else "ohren")
				var sp := t.mau_speaker(seat)
				var center := t.get_global_transform_with_canvas().affine_inverse() * b.get_global_transform_with_canvas().origin
				var ext := b.extent()
				var rect := Rect2(center + ext.position, ext.size)
				var avatar_hit := rect.grow(-4.0).has_point(sp["pos"])
				if not screen.grow(1.0).encloses(rect) or avatar_hit:
					bad.append("%d%s %s" % [seat, "/MM" if big else "", rect])
				b.queue_free()
		check(bad.is_empty(), "%d Spieler: alle Blasen im Bild, Avatar frei (%s)" % [n, bad])
		t.queue_free()
		await process_frame


# Alle Varianten bei Tag und Nacht einmal ganz durchlaufen lassen (Zeichnen ohne Fehler, Ablauf über age)
func _all_variants() -> void:
	var s := TableSamples.create(4, 9, [5, 5, 5, 5])
	var t := _table(s)
	await process_frame
	var made := 0
	for night in [0.0, 1.0]:
		for v in TableEffects.MAU_ALL:
			var b := t.fx_top.mau_bubble(Vector2(800, 300), v, {"speaker": Vector2(0, 110), "night": night, "seed": 3})
			b.auto = false
			var steps := 0
			var a := 0.0
			while a <= b.total():
				b.set_age(a)
				a += 0.1
				steps += 1
			b.set_age(b.total())
			await process_frame
			check(steps >= 12 and b.modulate.a <= 0.01, "%s (%s): läuft bis zum Ende und blendet aus" % [v, "Nacht" if night > 0.5 else "Tag"])
			var ext := b.extent()
			check(ext.size.x > 100.0 and ext.size.y > 60.0, "%s: sinnvolle Größe %s" % [v, ext.size])
			b.queue_free()
			made += 1
	check(made == TableEffects.MAU_ALL.size() * 2, "alle Varianten gebaut")
	t.queue_free()
	await process_frame
