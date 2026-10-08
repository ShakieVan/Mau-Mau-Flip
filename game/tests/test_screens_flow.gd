extends SceneTree
# Modul F2, headless: Bildschirmwechsel (Hauptmenü ↔ alle Unterseiten, Zurück), Übungspartie mit echter LocalTable startet und
# läuft ein paar Züge, Verlassen mit Rückfrage, Weitergeben zeigt vor jedem Menschenwechsel den Sichtschutz (nie eine fremde Hand),
# Regel-Editor speichert, Einstellungen schreiben, Mau-Töne (Aufnahmen) mit Entprellung je Platz.
# Weitergeben mit Hausregeln (AGENTS.md 15): Nach einem Kartentausch und nach einem Glücksspiel erscheint der Sichtschutz ohne
# jede Karte (Hand leer, keine Kartenansicht im Sichtschutz, keine neue Sicht bis zum Aufdecken); während des Glücksspiels kommt
# kein Sichtschutz.
#   godot_run.ps1 -Script res://tests/test_screens_flow.gd -Headless -Timeout 300

const CleanExit := preload("res://tests/clean_exit.gd")

var ok := 0
var failed := false
var nav: ScreenNav
var mau_ton_backup := "normal"


func _initialize() -> void:
	call_deferred("run")


func check(cond: bool, what: String) -> void:
	if cond:
		ok += 1
	else:
		failed = true
		print("FAIL: " + what)


func frames(n := 2) -> void:
	for i in n:
		await process_frame


func wait(t: float) -> void:
	await create_timer(t).timeout


func press(name: String) -> bool:
	var top := nav.top()
	var b := top.find_child(name, true, false) as BaseButton
	if b == null:
		print("Knopf fehlt: " + name + " in " + top.get_class() + " " + str(top.get_script().resource_path))
		return false
	b.pressed.emit()
	return true


func run() -> void:
	GameStarter.test_speed = 0.0
	var settings_backup: Variant = UiApp.setting("regeln", {})
	mau_ton_backup = str(UiApp.setting("mau_ton", "normal"))
	nav = ScreenNav.new()
	root.add_child(nav)
	await frames(3)
	check(nav.top() is MainMenuScreen, "Start im Hauptmenü")
	# Jede Unterseite öffnen und mit Zurück verlassen
	var pages := {"Uebungsspiel": SoloSetupScreen, "Weitergeben": PassSetupScreen, "Wlan": WlanScreen, "Regeln": RulesScreen, "Einstellungen": SettingsScreen}
	for key in pages:
		check(press(key), "Knopf " + key)
		await wait(0.25)
		check(is_instance_of(nav.top(), pages[key]), "Seite " + key)
		nav.go_back()
		await wait(0.25)
		check(nav.top() is MainMenuScreen and nav.depth() == 1, "zurück von " + key)
	# WLAN → Spiel eröffnen / Beitreten erreichbar (ohne Netzaufbau zu prüfen)
	press("Wlan")
	await wait(0.25)
	check(nav.top().find_child("Eröffnen", true, false) != null and nav.top().find_child("Suchen", true, false) != null, "WLAN-Auswahl")
	nav.go_back()
	await wait(0.25)
	await solo_game()
	await pass_game()
	await pass_house_rules()
	await rules_editor()
	await mau_lock()
	var app := UiApp.app()
	if app != null:
		app.settings.set_value("regeln", settings_backup if settings_backup is Dictionary else {})
		app.settings.set_value("mau_ton", mau_ton_backup)
	MauSound.reset()
	if failed:
		print("FAIL: test_screens_flow")
	else:
		print("RESULT: %d ok" % ok)
	# Töne anhalten, Bildschirme freigeben, statische Zwischenspeicher leeren (sonst „resources still in use at exit“)
	await CleanExit.finish(self, 1 if failed else 0)


# Übungspartie: startet, eigene Züge über die Hand-Signale, Computergegner ziehen, Verlassen mit Rückfrage
func solo_game() -> void:
	press("Uebungsspiel")
	await wait(0.25)
	var setup := nav.top() as SoloSetupScreen
	setup.bots = 2
	press("Start")
	await wait(0.4)
	var ts := nav.top() as TableScreen
	check(ts != null, "Tisch nach Start")
	if ts == null:
		return
	check(ts.source is LocalTable and ts.source.mode() == "solo", "LocalTable solo")
	check(ts.overlay.layer > 1 and ts.table.round_end.get_parent().get_parent() == ts.overlay, "Overlays im höheren CanvasLayer")
	var deadline := Time.get_ticks_msec() + 3000
	while ts.view.is_empty() and Time.get_ticks_msec() < deadline:
		await frames(1)
	check(not ts.view.is_empty(), "erste Sicht")
	check((ts.view.get("players", []) as Array).size() == 3, "3 Plätze")
	check(int(ts.view.get("seat", -1)) == 0, "eigener Platz 0")
	# ein paar Züge: wenn dran, spielbare Karte über die Hand (Wünscher mit Farbrad), sonst ziehen/behalten
	var my_moves := 0
	var bot_events := [0]
	ts.source.state_changed.connect(func(evs: Array, _v: Dictionary) -> void:
		for e in evs:
			if str(e.get("e", "")) in ["play", "draw"] and int(e.get("seat", 0)) > 0:
				bot_events[0] += 1)
	deadline = Time.get_ticks_msec() + 40000
	while my_moves < 4 and Time.get_ticks_msec() < deadline:
		await wait(0.1)
		if ts.table.director.is_busy():
			continue
		var v := ts.view
		var phase := str(v.get("phase", ""))
		if phase == "round_over" or phase == "game_over":
			break
		var turn := int(v.get("turn", -1))
		if turn != 0:
			continue
		var hints: Dictionary = v.get("hints", {})
		var playable: Array = hints.get("playable", [])
		if phase == "color":
			ts.table.wish_picker.color_chosen.emit(str((v.get("colors", ["rot"]) as Array)[0]))
		elif not playable.is_empty():
			var id := int(playable[0])
			ts.hand.play_requested.emit(id, ts.hand.play_target)
			if ts.table.wish_picker.mode == "wheel":
				ts.table.wish_picker.color_chosen.emit(str((v.get("colors", ["rot"]) as Array)[0]))
				ts.table.wish_picker.close()
			my_moves += 1
		elif bool(hints.get("can_keep", false)):
			ts._act({"a": "keep"})
		elif bool(hints.get("can_challenge", false)) or bool(hints.get("can_accept", false)):
			ts._act({"a": "accept"})
		elif bool(hints.get("can_draw", false)):
			ts._act({"a": "draw"})
			my_moves += 1
		elif phase in ["gamble", "discard_pick"]:
			# gespeicherte Hausregeln mit Glücksspiel/Farbe ablegen: wie ein Computergegner weitermachen (sonst bleibt die Schleife hängen)
			ts._act(MauBot.choose(v, my_moves + 1))
		await wait(0.3)
	check(my_moves >= 3, "eigene Züge gespielt (%d)" % my_moves)
	check(int(bot_events[0]) >= 2, "Computergegner ziehen (%d)" % int(bot_events[0]))
	check(ts.hand.get_order().size() == (ts.view.get("hand", []) as Array).size() or ts.table.director.is_busy(), "Hand = Sicht")
	# Hilfe zu einer Handkarte
	var cards: Array = ts.view.get("hand", [])
	if not cards.is_empty():
		ts._on_help(int(cards[0].id), str(cards[0].face))
		check(ts.table.help_popup.visible, "Kartenhilfe offen")
		nav.go_back()
		check(not ts.table.help_popup.visible and nav.top() == ts, "Zurück schließt die Hilfe")
	# Sortieren
	var before := ts.hand.sort_mode
	ts._cycle_sort()
	check(ts.hand.sort_mode != before and str(UiApp.setting("sortierung", "")) == ts.hand.sort_mode, "Sortierknopf")
	ts._apply_sort("farbe")
	# Zurück = Rückfrage, „Weiterspielen“ bleibt, „Verlassen“ führt ins Menü
	nav.go_back()
	await frames(2)
	var box := ts._top.find_child("Rueckfrage", true, false) as ConfirmBox
	check(box != null, "Rückfrage „Partie verlassen?“")
	if box != null:
		(box.find_child("Nein", true, false) as Button).pressed.emit()
		await frames(2)
		check(nav.top() == ts, "Weiterspielen")
	nav.go_back()
	await frames(2)
	box = ts._top.find_child("Rueckfrage", true, false) as ConfirmBox
	if box != null:
		(box.find_child("Ja", true, false) as Button).pressed.emit()
	await wait(0.4)
	check(nav.top() is MainMenuScreen and nav.depth() == 1, "Verlassen → Hauptmenü")
	check(not is_instance_valid(ts) or ts.is_queued_for_deletion() or ts.get_parent() == null, "Tisch freigegeben")


# Weitergeben: zwei Menschen und ein Computergegner; vor jedem Menschenwechsel Sichtschutz, nie eine fremde Hand
func pass_game() -> void:
	press("Weitergeben")
	await wait(0.25)
	var setup := nav.top() as PassSetupScreen
	setup.entries = [{"name": "Lena", "kind": "human"}, {"name": "Tom", "kind": "human"}, {"name": "Mimi", "kind": "bot"}]
	setup._rebuild()
	press("Start")
	await wait(0.4)
	var ts := nav.top() as TableScreen
	check(ts != null and ts.source.mode() == "pass", "Weitergeben-Tisch")
	if ts == null:
		return
	var log: Array = []                      # Reihenfolge: ["view", seat] / ["handover", seat]
	ts.source.handover.connect(func(s: int, _n: String) -> void: log.append(["handover", s]))
	ts.source.state_changed.connect(func(_e: Array, v: Dictionary) -> void: log.append(["view", int(v.get("seat", -1))]))
	var reveals := 0
	var covered_ok := true
	var deadline := Time.get_ticks_msec() + 45000
	while reveals < 3 and Time.get_ticks_msec() < deadline:
		await wait(0.1)
		if ts.table.handover.visible:
			# Sichtschutz: keine Karten sichtbar (die Hand ist leer bzw. blendet aus) – aufdecken
			await wait(0.5)
			if ts.hand.get_order().size() != 0:
				covered_ok = false
			ts.table.handover.visible = false
			ts.table.handover.revealed.emit()
			reveals += 1
			continue
		if ts.table.director.is_busy():
			continue
		var v := ts.view
		var seat := int(v.get("seat", -1))
		if seat < 0 or int(v.get("turn", -1)) != seat:
			continue
		var hints: Dictionary = v.get("hints", {})
		var playable: Array = hints.get("playable", [])
		if str(v.get("phase", "")) == "color":
			ts.table.wish_picker.color_chosen.emit(str((v.get("colors", ["rot"]) as Array)[0]))
		elif not playable.is_empty():
			ts.hand.play_requested.emit(int(playable[0]), ts.hand.play_target)
			if ts.table.wish_picker.mode == "wheel":
				ts.table.wish_picker.color_chosen.emit(str((v.get("colors", ["rot"]) as Array)[0]))
				ts.table.wish_picker.close()
		elif bool(hints.get("can_keep", false)):
			ts._act({"a": "keep"})
		elif bool(hints.get("can_challenge", false)):
			ts._act({"a": "accept"})
		elif bool(hints.get("can_draw", false)):
			ts._act({"a": "draw"})
		elif str(v.get("phase", "")) in ["gamble", "discard_pick"]:
			ts._act(MauBot.choose(v, 7))
		await wait(0.3)
	check(reveals >= 2, "Sichtschutz erschienen und aufgedeckt (%d)" % reveals)
	check(covered_ok, "unter dem Sichtschutz keine Karten")
	# Zwischen zwei Sichten verschiedener Menschen liegt immer ein Sichtschutz
	var last_seat := -1
	var since_handover := true
	var leak := false
	for entry in log:
		if entry[0] == "handover":
			since_handover = true
		elif int(entry[1]) >= 0:
			if last_seat >= 0 and int(entry[1]) != last_seat and not since_handover:
				leak = true
			last_seat = int(entry[1])
			since_handover = false
	check(not leak, "nie fremde Hand ohne Sichtschutz")
	check(log.size() > 3, "Ablauf protokolliert (%d)" % log.size())
	ts._leave_now()
	await wait(0.4)
	check(nav.top() is MainMenuScreen, "Weitergeben verlassen")


# Weitergeben mit Hausregeln: zwei Menschen; erst ein Kartentausch, dann ein Glücksspiel (feste Drucke 0, 3). Die Karten werden
# hinter dem Sichtschutz in die Hand gelegt (Kartenzahl bleibt gleich).
func pass_house_rules() -> void:
	var cfg := RuleConfig.preset("familie")
	cfg.gamble_cards = "on"
	cfg.discard_color = "on"
	RulesBar.store(cfg)
	press("Weitergeben")
	await wait(0.25)
	var setup := nav.top() as PassSetupScreen
	setup.entries = [{"name": "Anna", "kind": "human"}, {"name": "Ben", "kind": "human"}]
	setup._rebuild()
	press("Start")
	await wait(0.4)
	var ts := nav.top() as TableScreen
	check(ts != null and ts.source is LocalTable and ts.source.mode() == "pass", "Hausregeln Weitergeben: Tisch")
	if ts == null or not ts.source is LocalTable:
		return
	var src := ts.source as LocalTable
	var g := src.game
	check(g != null and g.n_cards == 124, "Hausregeln Weitergeben: 124 Karten")
	var views := []
	src.state_changed.connect(func(_e: Array, v: Dictionary) -> void: views.append(int(v.get("seat", -1))))
	# erster Sichtschutz
	var first := await _await_handover(ts)
	check(first >= 0, "Hausregeln Weitergeben: Sichtschutz vor dem ersten Zug")
	if first < 0:
		ts._leave_now()
		await wait(0.4)
		return
	_check_cover(ts, "erster Sichtschutz")
	var other := 1 - first
	var sid := _give(g, first, MauGame.SWAP)
	if sid >= 0:
		g.color = str(g._color[g.faces[g.side * g.n_cards + sid]])
		g.wished = false
	_reveal(ts)
	await _settle(ts)
	check(int(ts.view.get("seat", -1)) == first and (ts.view.hints.playable as Array).has(sid), "Hausregeln Weitergeben: Kartentausch spielbar")
	var n_views := views.size()
	ts._act({"a": "play", "card": sid})
	var second := await _await_handover(ts)
	check(second == other, "Hausregeln Weitergeben: nach dem Kartentausch Sichtschutz für den anderen (%d)" % second)
	_check_cover(ts, "nach dem Kartentausch")
	check(views.slice(n_views).filter(func(s): return s == other).is_empty(), "nach dem Kartentausch keine fremde Sicht vor dem Aufdecken")
	# Glücksspiel des anderen
	var gid := _give(g, other, MauGame.GAMBLE)
	g.force_rolls([0, 3])
	_reveal(ts)
	await _settle(ts)
	check(int(ts.view.get("seat", -1)) == other and (ts.view.hints.playable as Array).has(gid), "Hausregeln Weitergeben: Glücksspiel spielbar")
	ts._act({"a": "play", "card": gid, "color": str((ts.view.get("colors", ["rot"]) as Array)[0])})
	var covered_during := false
	var deadline := Time.get_ticks_msec() + 15000
	while g.phase() == "gamble" and Time.get_ticks_msec() < deadline:
		await wait(0.1)
		if ts.table.handover.visible:
			covered_during = true
		if ts.table.director.is_busy():
			continue
		var h: Dictionary = ts.view.get("hints", {})
		if not (h.get("can_stake", []) as Array).is_empty():
			ts._act({"a": "stake", "card": int(h.can_stake[0])})
		elif bool(h.get("can_press", false)):
			ts._act({"a": "press"})
	check(g.phase() != "gamble" and not covered_during, "Hausregeln Weitergeben: Glücksspiel ohne Sichtschutz zu Ende gespielt (%s)" % g.phase())
	n_views = views.size()
	var third := await _await_handover(ts)
	check(third == first, "Hausregeln Weitergeben: nach dem Glücksspiel Sichtschutz (%d)" % third)
	_check_cover(ts, "nach dem Glücksspiel")
	check(views.slice(n_views).filter(func(s): return s == first).is_empty(), "nach dem Glücksspiel keine fremde Sicht vor dem Aufdecken")
	check(RulesFixture.card_check(g) == "", "Hausregeln Weitergeben: Karten vollständig (%s)" % RulesFixture.card_check(g))
	ts._leave_now()
	await wait(0.4)
	check(nav.top() is MainMenuScreen, "Hausregeln Weitergeben verlassen")


# Wartet, bis der Sichtschutz erscheint; Platz, auf den er wartet (-1: keiner)
func _await_handover(ts: TableScreen) -> int:
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		await wait(0.05)
		var src := ts.source as LocalTable
		if ts.table.handover.visible and src.pending_handover() >= 0:
			await wait(0.3)
			return src.pending_handover()
	return -1


# Sichtschutz (AGENTS.md 15): deckt alles ab, zeigt keine Karte, auch keine Rückseite; die Hand darunter ist leer
func _check_cover(ts: TableScreen, what: String) -> void:
	var cover := ts.table.handover
	var screen := Rect2(Vector2.ZERO, ts.get_viewport_rect().size)
	check(cover.visible and cover.get_global_rect().encloses(screen.grow(-1.0)), "Sichtschutz %s deckt den Bildschirm ab" % what)
	check(cover.find_children("*", "CardView", true, false).is_empty() and cover.find_children("*", "TextureRect", true, false).is_empty(),
		"Sichtschutz %s zeigt keine Karten" % what)
	check(ts.hand.get_order().size() == 0, "Sichtschutz %s: Hand leer" % what)


func _reveal(ts: TableScreen) -> void:
	ts.table.handover.visible = false
	ts.table.handover.revealed.emit()


func _settle(ts: TableScreen) -> void:
	await wait(0.2)
	var deadline := Time.get_ticks_msec() + 5000
	while ts.table.director.is_busy() and Time.get_ticks_msec() < deadline:
		await wait(0.05)


# Legt eine Karte der Art kind (aktive Seite) auf die Hand von seat; Kartenzahl bleibt gleich. -1: keine gefunden
func _give(g: MauGame, seat: int, kind: String) -> int:
	for id in g.hands[seat]:
		if str(g._kind[g.faces[g.side * g.n_cards + int(id)]]) == kind:
			return int(id)
	for i in g.draw_pile.size():
		var id := int(g.draw_pile[i])
		if str(g._kind[g.faces[g.side * g.n_cards + id]]) == kind:
			g.draw_pile.remove_at(i)
			(g.hands[seat] as Array).append(id)
			return id
	return -1


# Regel-Editor: Voreinstellung und Einzeloption landen in App.settings "regeln"
func rules_editor() -> void:
	press("Regeln")
	await wait(0.25)
	var rs := nav.top() as RulesScreen
	check(rs != null, "Regelseite")
	if rs == null:
		return
	if rs.has_method("set_option"):
		rs.call("set_option", "hand_size", 9)
		check(RulesBar.current().hand_size == 9, "Option gespeichert")
		rs.call("apply_preset", "familie")
		check(RulesBar.current().preset_name() == "familie", "Voreinstellung gespeichert")
	nav.go_back()
	await wait(0.25)


# Mau-Töne am Tisch (AGENTS.md 21): jeder Ruf klingt auf jedem Gerät, entprellt wird nur derselbe Ton für denselben Platz (1 s);
# Mau-Ton „aus“ = still.
func mau_lock() -> void:
	MauSound.reset()
	var app := UiApp.app()
	if app != null:
		app.settings.set_value("mau_ton", "normal")
	var first := MauSound.play(100000, 1, "mau")
	var repeat := MauSound.play(100500, 1, "mau")
	var other := MauSound.play(100600, 2, "mau")
	var later := MauSound.play(101000, 1, "mau")
	check(first and not repeat and other and later, "Mau-Ton je Platz entprellt, andere Plätze klingen (%s %s %s %s)" % [first, repeat, other, later])
	check(MauSound.last_path == "res://assets/sfx/mau.ogg", "Mau-Tondatei ist die Aufnahme (%s)" % MauSound.last_path)
	check(MauSound.play(102000, 1, "mau_mau") and MauSound.last_path == "res://assets/sfx/mau_mau.ogg", "Mau-Mau-Tondatei (%s)" % MauSound.last_path)
	if app != null:
		app.settings.set_value("mau_ton", "aus")
		check(not MauSound.play(110000, 3, "mau"), "Mau-Ton aus: still")
		app.settings.set_value("mau_ton", "normal")
