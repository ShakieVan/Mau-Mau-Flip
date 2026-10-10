extends SceneTree
# Neue Karten am Tisch (headless, echter TableScreen mit LocalTable und Regelwerk; Lagen aus RulesFixture):
#   Kartentausch    eigener Tausch im Uhrzeigersinn und gegen ihn (Hände wandern, eigene Hand geht weg und kommt neu an), mit
#                   sichtbaren und verdeckten Rückseiten; danach Hand, Kartenzahlen und Fächer = Sicht
#   Glücksspiel     Legen mit Farbwahl → Automat und Einsatzstapel; Setzen über die Hand (play_requested → stake), Druck über den
#                   Knopf mit vorgegebenem Wurf 0 („Nichts!“) und Treffer 4 (Ziehen, Einsatz zurück); Glücksspiel bis zur leeren
#                   Hand (Einsatz unter die Ablage, fertig); Gegner spielt (Stapel an seinem Platz, Erwischen geht); Mau-Knopf
#   Farbe ablegen   eigene Ablegen-Karte (Aktionskarten der Farbe wirken nicht, liegen unter der Ablegen-Karte) und ein Gegner
#   Hervorheben     Einstellung „hervorheben“ aus: kein Markieren, unpassende Karte springt zurück mit „Die Karte passt nicht.“
#   ohne Hausregeln keine Glücksspiel-Teile; nach jedem Ablauf ruhen Automat und Einsatzstapel (kein Dauerzeichnen)
#   godot_run.ps1 -Script res://tests/test_ui_new_cards.gd -Headless -Timeout 180

const CleanExit := preload("res://tests/clean_exit.gd")

var ok := 0
var fails := 0
var errors_before := 0


func _initialize() -> void:
	call_deferred("run")


func check(cond: bool, what: String) -> void:
	if cond:
		ok += 1
	else:
		fails += 1
		print("FAIL: " + what)


func frames(n := 2) -> void:
	for i in n:
		await process_frame


func wait(t: float) -> void:
	await create_timer(t).timeout


func run() -> void:
	root.size = Vector2i(1600, 720)
	Engine.time_scale = 3.0
	var app := UiApp.app()
	var had_hl: bool = app != null and app.settings.has_value("hervorheben")
	var hl_backup: Variant = UiApp.setting("hervorheben", true)
	if app != null:
		app.settings.set_value("hervorheben", true)
	await swap_test("clockwise", 1, true)
	await swap_test("play", -1, true)
	await swap_test("clockwise", 1, false)
	await gamble_test()
	await gamble_empty_test()
	await gamble_opponent_test()
	await gamble_stop_test()
	await gamble_stop_opponent_test()
	await discard_test()
	await discard_opponent_test()
	await discard_joker_test()
	await discard_undo_test()
	await color_phase_test()
	await highlight_test()
	await plain_rules_test()
	if app != null:
		if had_hl:
			app.settings.set_value("hervorheben", hl_backup)
		else:
			app.settings.reset("hervorheben")
	Engine.time_scale = 1.0
	if fails > 0:
		print("FAIL: test_ui_new_cards (%d)" % fails)
	print("RESULT: %d ok" % ok)
	await CleanExit.finish(self, 1 if fails > 0 else 0)


# ----------------------------------------------------------------- Vorrichtung

# Tisch mit LocalTable aus einer gebauten Lage (Platz 0 = Mensch, übrige Computergegner, die nur auf pump() hin handeln)
func make_table(cfg: RuleConfig, n: int, spec: Dictionary) -> TableScreen:
	var g := RulesFixture.build(cfg, n, spec, 4711)
	var seats: Array = []
	for i in n:
		if i > 0:
			(g.players[i] as Dictionary)["kind"] = "bot"
		seats.append({"name": str(g.players[i].name), "kind": "human" if i == 0 else "bot", "host": i == 0})
	var t := LocalTable.new()
	t.auto_process = false
	t.autosave = false
	t.speed = 0.0
	var data := {"mode": "solo", "game": g.to_dict(), "seats": seats, "host_seat": 0}
	var ts := TableScreen.create(t, func() -> void: t.resume(data))
	root.add_child(ts)
	await frames(3)
	await settle(ts)
	return ts


func game_of(ts: TableScreen) -> MauGame:
	return (ts.source as LocalTable).game


func close_table(ts: TableScreen) -> void:
	ts.leaving = true
	ts.queue_free()
	await frames(3)


# Wartet, bis die Regie fertig ist und Nachläufe (Austeilen in die Hand, Ausblenden) vorbei sind
func settle(ts: TableScreen, extra := 0.5) -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while ts.table.director.is_busy() and Time.get_ticks_msec() < deadline:
		await frames(1)
	await wait(extra)


# Protokoll der Ereignisse, die die Regie beginnt (Namen in Reihenfolge)
func watch(ts: TableScreen) -> Array:
	var log: Array = []
	ts.table.director.event_started.connect(func(ev: Dictionary) -> void: log.append(str(ev.get("e", ""))))
	return log


# Wartet, bis die Regie das Ereignis begonnen hat (true) bzw. bis zur Zeitgrenze (false)
func wait_event(log: Array, name: String, timeout := 6.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not log.has(name) and Time.get_ticks_msec() < deadline:
		await frames(1)
	return log.has(name)


func sorted_ids(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		out.append(int(c.get("id", -1)))
	out.sort()
	return out


func sorted_ints(a: Array) -> Array:
	var out: Array = []
	for x in a:
		out.append(int(x))
	out.sort()
	return out


# Anzeige = Sicht: eigene Hand, Kartenzahlen und Fächer der Gegner (Rückseiten bzw. neutrale Rückseiten)
func check_matches_view(ts: TableScreen, label: String) -> void:
	var v := ts.view
	check(sorted_ints(ts.hand.get_order()) == sorted_ids(v.get("hand", [])), label + ": eigene Hand = Sicht (%s / %s)" % [sorted_ints(ts.hand.get_order()), sorted_ids(v.get("hand", []))])
	var backs_visible := bool((v.get("rules", {}) as Dictionary).get("backs_visible", true))
	var good := true
	for p in v.get("players", []):
		var s := int(p.get("seat", -1))
		if s == int(v.get("seat", -1)):
			continue
		var node := ts.table.seat_node(s)
		if node == null:
			good = false
			print("  Platz %d fehlt" % s)
			continue
		var want: Array[String] = []
		var backs: Array = p.get("backs", [])
		if backs_visible and backs.size() == int(p.get("count", 0)):
			for b in backs:
				want.append(str(b))
		else:
			for i in int(p.get("count", 0)):
				want.append(CardTextures.BACK)
		if node.count() != int(p.get("count", -1)) or node.keys != want:
			good = false
			print("  Platz %d: angezeigt %d %s, Sicht %d %s" % [s, node.count(), node.keys, int(p.get("count", -1)), want])
	check(good, label + ": Gegner (Zahl und Fächer) = Sicht")


func all_back(keys: Array) -> bool:
	for k in keys:
		if str(k) != CardTextures.BACK:
			return false
	return true


func toast_has(ts: TableScreen, part: String) -> bool:
	for t in ts.table.hint_bar.get("_toasts"):
		if str(t["text"]).contains(part):
			return true
	return false


# ----------------------------------------------------------------- Kartentausch

func swap_test(direction: String, dir: int, backs: bool) -> void:
	var cfg := RuleConfig.new()
	cfg.swap_cards = "on"
	cfg.swap_direction = direction
	cfg.backs_visible = backs
	var label := "Tausch %s (dir %d, Rückseiten %s)" % [direction, dir, "sichtbar" if backs else "verdeckt"]
	var ts := await make_table(cfg, 4, {"hands": [["hell_rot_tausch", "hell_rot_2", "hell_blau_3", "hell_gelb_4"],
		["hell_gruen_1", "hell_gruen_2"], ["hell_blau_7", "hell_blau_8", "hell_blau_9", "hell_gelb_1", "hell_gelb_2"],
		["hell_rot_9", "hell_gelb_9", "hell_gruen_9"]], "top": "hell_rot_5", "current": 0, "dir": dir})
	var g := game_of(ts)
	var before: Array = []
	for s in 4:
		before.append(sorted_ints(g.hands[s]))
	var id := RulesFixture.card(g, 0, "hell_rot_tausch")
	var log := watch(ts)
	ts.hand.play_requested.emit(id, ts.hand.play_target)
	check(await wait_event(log, "swap_hands") and ts.table._house.swaps == 1, label + ": Tausch wird abgespielt")
	# mitten im Flug: eigene Hand ist weg, Gegnerfächer sind leer, Karten fliegen
	check(ts.hand.get_order().is_empty(), label + ": eigene Hand ist abgeflogen")
	check(ts.table.seat_node(1).count() == 0, label + ": Gegnerfächer leer, bis die neue Hand ankommt")
	await wait(0.1)
	var flying := 0
	for c in ts.table.fx.get_children():
		if c is CardView:
			flying += 1
	check(flying >= 6, label + ": Karten fliegen über den Tisch (%d)" % flying)
	check(toast_has(ts, "Kartentausch!") and toast_has(ts, "im Uhrzeigersinn" if dir > 0 else "gegen den Uhrzeigersinn"), label + ": Hinweis mit Richtung")
	await settle(ts, 0.9)
	var to := posmod(0 + dir, 4)
	check(sorted_ints(g.hands[to]) == sorted_ints(before[0].filter(func(x: int) -> bool: return x != id)), label + ": Regelwerk hat getauscht")
	check_matches_view(ts, label)
	if not backs:
		var hidden_ok := true
		for s in [1, 2, 3]:
			if not all_back(ts.table.seat_node(s).keys):
				hidden_ok = false
		check(hidden_ok, label + ": verdeckt bleiben nur neutrale Rückseiten")
	check(ts.hand.is_enabled(), label + ": Hand wieder bedienbar")
	await close_table(ts)


# ----------------------------------------------------------------- Glücksspiel

func gamble_cfg() -> RuleConfig:
	var cfg := RuleConfig.new()
	cfg.gamble_cards = "on"
	return cfg


func gamble_test() -> void:
	var ts := await make_table(gamble_cfg(), 3, {"hands": [["hell_gluecksspiel", "hell_rot_2", "hell_blau_3"],
		["hell_gruen_1", "hell_gruen_2", "hell_gelb_6"], ["hell_blau_7", "hell_blau_8"]], "top": "hell_rot_5", "current": 0})
	var g := game_of(ts)
	var tv := ts.table
	check(not tv.gamble_machine.active and not tv.stake_pile.shown, "Glücksspiel: vorher kein Automat")
	var gid := RulesFixture.card(g, 0, "hell_gluecksspiel")
	ts.hand.play_requested.emit(gid, ts.hand.play_target)
	await frames(2)
	check(tv.wish_picker.is_open(), "Glücksspiel: Farbwahl beim Legen")
	tv.wish_picker.color_chosen.emit("blau")
	tv.wish_picker.close()
	await settle(ts)
	check(g.phase() == "gamble", "Glücksspiel: Phase gamble")
	check(tv.gamble_machine.active and tv.gamble_machine.visible, "Glücksspiel: Automat sichtbar")
	check(tv.stake_pile.shown and tv.stake_pile.count == 0 and tv.stake_pile.target, "Glücksspiel: leerer Einsatzstapel als Ziel")
	check(tv.stake_pile.position.distance_to(TableLayout.own_stake_pos(tv.size)) < 1.0, "Glücksspiel: eigener Einsatz vor der Hand")
	check(not tv.get("_color_mark").visible, "Glücksspiel: Farbanzeige weicht dem Automaten")
	check(tv.staking and not ts.hand.show_playable, "Glücksspiel: Setzen über die Hand, ohne Markierung")
	check(ts.hand.play_target.distance_to(tv.get_global_transform() * tv.stake_pile.position) < 1.0, "Glücksspiel: Karten fliegen zum Einsatz")
	check(tv.mau_button.mode == MauButton.Mode.READY, "Glücksspiel: „Mau!“ vor dem Setzen der vorletzten Karte möglich")
	check(not tv.gamble_machine.can_press, "Glücksspiel: Knopf erst nach dem Setzen")
	check(not tv.press_gamble(), "Glücksspiel: Knopf ohne Einsatz gesperrt")
	# Mau rufen geht weiter
	tv.mau_button.mau_pressed.emit()
	await settle(ts, 0.2)
	check(bool(g.mau_said[0]), "Glücksspiel: Mau-Knopf wirkt")
	# Setzen über die Hand
	var sid := int(ts.view.hints.can_stake[0])
	ts.hand.play_requested.emit(sid, ts.hand.play_target)
	await settle(ts)
	check(g.gamble.need == "press" and (g.gamble.stake as Array).size() == 1, "Glücksspiel: gesetzt")
	check(tv.stake_pile.count == 1 and not tv.stake_pile.target, "Glücksspiel: Einsatzstapel zeigt 1")
	check(not ts.hand.get_order().has(sid), "Glücksspiel: Einsatzkarte hat die Hand verlassen")
	check(tv.gamble_machine.can_press, "Glücksspiel: Knopf pulsiert")
	check(tv.gamble_machine.is_animating(), "Glücksspiel: Puls läuft, solange der Druck fällig ist")
	# Druck: kein Treffer
	g.force_rolls([0])
	var center := tv.get_global_transform() * (tv.gamble_machine.position + tv.gamble_machine.button_center())
	check(tv.gamble_machine.hit(center), "Glücksspiel: Knopf trifft")
	tv._tap(tv.get_global_transform().affine_inverse() * center)
	await frames(2)
	check(tv.gamble_machine.is_spinning(), "Glücksspiel: Walze dreht")
	await settle(ts)
	check(tv.gamble_machine.shown_value() == 0, "Glücksspiel: Walze zeigt 0")
	check(g.gamble.need == "stake" and tv.stake_pile.target, "Glücksspiel: nach 0 wieder setzen")
	# zweiter Einsatz (letzte Karte), Treffer 4
	var sid2 := int(ts.view.hints.can_stake[0])
	ts.hand.play_requested.emit(sid2, ts.hand.play_target)
	await settle(ts)
	check(tv.stake_pile.count == 2, "Glücksspiel: Einsatz 2")
	g.force_rolls([4])
	check(tv.press_gamble(), "Glücksspiel: Knopf gedrückt")
	check(not tv.press_gamble(), "Glücksspiel: kein zweiter Druck")
	await settle(ts, 1.2)
	check(g.phase() == "turn" and g.gamble.is_empty(), "Glücksspiel: Treffer beendet den Zug")
	check(tv.gamble_machine.shown_value() == 4 or not tv.gamble_machine.active, "Glücksspiel: Walze zeigte 4")
	check(not tv.gamble_machine.active and not tv.stake_pile.shown, "Glücksspiel: Automat und Einsatz weg")
	check(tv.get("_color_mark").visible, "Glücksspiel: Farbanzeige wieder da")
	check(not tv.staking and ts.hand.show_playable, "Glücksspiel: Hand wieder normal")
	check(ts.hand.play_target.distance_to(tv.get_global_transform() * tv.discard_position()) < 1.0, "Glücksspiel: Ziel wieder die Ablage")
	check((ts.view.hand as Array).size() == 6, "Glücksspiel: 4 gezogen + 2 zurück (%d)" % (ts.view.hand as Array).size())
	check_matches_view(ts, "Glücksspiel Treffer")
	await wait(0.6)
	check(not tv.gamble_machine.is_processing() and not tv.stake_pile.is_processing(), "Glücksspiel: Automat und Stapel ruhen")
	await close_table(ts)


# Glücksspiel bis zur leeren Hand: Einsatz unter die Ablage, fertig
func gamble_empty_test() -> void:
	var ts := await make_table(gamble_cfg(), 3, {"hands": [["hell_gluecksspiel", "hell_rot_2"],
		["hell_gruen_1", "hell_gruen_2", "hell_gelb_6"], ["hell_blau_7", "hell_blau_8"]], "top": "hell_rot_5", "current": 0,
		"mau_said": [0]})
	var g := game_of(ts)
	var tv := ts.table
	ts._act({"a": "play", "card": RulesFixture.card(g, 0, "hell_gluecksspiel"), "color": "rot"})
	await settle(ts)
	ts.hand.play_requested.emit(RulesFixture.card(g, 0, "hell_rot_2"), ts.hand.play_target)
	await settle(ts)
	check(ts.hand.get_order().is_empty() and tv.stake_pile.count == 1, "Leer: letzte Karte gesetzt")
	g.force_rolls([0])
	tv.press_gamble()
	await settle(ts, 1.0)
	check(g.phase() in ["round_over", "game_over"], "Leer: Runde vorbei (%s)" % g.phase())
	check(not tv.gamble_machine.active and not tv.stake_pile.shown, "Leer: Automat und Einsatz weg")
	check(tv.round_end.visible, "Leer: Rundenende")
	await close_table(ts)


# Ein Gegner spielt Glücksspiel: Stapel an seinem Platz, Knopf nicht drückbar, Erwischen geht
func gamble_opponent_test() -> void:
	var ts := await make_table(gamble_cfg(), 3, {"hands": [["hell_rot_2", "hell_blau_3", "hell_gelb_1"],
		["hell_gruen_1", "hell_gruen_2"], ["hell_blau_7", "hell_blau_8"]], "top": "hell_gluecksspiel", "color": "gruen",
		"current": 1, "gamble": {"q": 3, "stake": [], "need": "stake"}})
	var g := game_of(ts)
	var tv := ts.table
	var lt := ts.source as LocalTable
	check(tv.gamble_machine.active and not tv.gamble_machine.can_press, "Gegner: Automat sichtbar, Knopf nicht für mich")
	var own := TableLayout.own_stake_pos(tv.size)
	check(tv.stake_pile.position.distance_to(own) > 100.0, "Gegner: Einsatzstapel am Platz des Gegners")
	check(not tv.staking, "Gegner: meine Hand setzt nicht")
	var node := tv.seat_node(1)
	var before := node.count()
	lt._apply(1, {"a": "stake", "card": RulesFixture.card(g, 1, "hell_gruen_1")})
	await settle(ts)
	check(tv.stake_pile.count == 1 and node.count() == before - 1, "Gegner: Karte wandert auf seinen Einsatz")
	check(node.catchable, "Gegner: ohne „Mau!“ bei 1 Karte erwischbar")
	g.force_rolls([2])
	lt._apply(1, {"a": "press"})
	await settle(ts, 1.0)
	check(not tv.gamble_machine.active and node.count() == 4, "Gegner: Treffer 2, Einsatz zurück (%d Karten)" % node.count())
	check_matches_view(ts, "Gegner-Glücksspiel")
	await close_table(ts)


# Aufhören: Knopf erst nach einer 0, Tipp darauf legt den Einsatz unter die Ablage, Zug vorbei
func gamble_stop_test() -> void:
	var ts := await make_table(gamble_cfg(), 3, {"hands": [["hell_gluecksspiel", "hell_rot_2", "hell_blau_3", "hell_gelb_4"],
		["hell_gruen_1", "hell_gruen_2", "hell_gelb_6"], ["hell_blau_7", "hell_blau_8"]], "top": "hell_rot_5", "current": 0})
	var g := game_of(ts)
	var tv := ts.table
	var m := tv.gamble_machine
	ts._act({"a": "play", "card": RulesFixture.card(g, 0, "hell_gluecksspiel"), "color": "rot"})
	await settle(ts)
	var stop_g := tv.get_global_transform() * (m.position + m.stop_rect().get_center())
	check(not m.can_stop and not m.hit_stop(stop_g) and not tv.stop_gamble(), "Aufhören: vor dem ersten Druck kein Knopf")
	ts.hand.play_requested.emit(RulesFixture.card(g, 0, "hell_rot_2"), ts.hand.play_target)
	await settle(ts)
	check(not m.can_stop, "Aufhören: vor dem Drücken kein Knopf")
	g.force_rolls([0])
	tv.press_gamble()
	await settle(ts)
	check(m.can_stop and m.hit_stop(stop_g), "Aufhören: nach der 0 sichtbar und treffbar")
	check(str(ts.view.hints.text).begins_with("Noch eine Karte setzen – oder aufhören?"), "Aufhören: Hinweistext (%s)" % str(ts.view.hints.text))
	check(not m.hit(stop_g), "Aufhören: Knopf liegt nicht auf „Los!“")
	var under := g.discard.size()
	var log := watch(ts)
	tv._tap(tv.get_global_transform().affine_inverse() * stop_g)
	check(m.press_sent and not m.hit_stop(stop_g), "Aufhören: einmal gesendet")
	check(await wait_event(log, "stake_discard"), "Aufhören: Einsatz geht unter die Ablage")
	await settle(ts, 0.8)
	check(g.phase() == "turn" and g.current_seat() == 1 and g.gamble.is_empty() and g.discard.size() == under + 1, "Aufhören: Zug vorbei")
	check(not m.active and not m.can_stop and not tv.stake_pile.shown, "Aufhören: Automat und Einsatz weg")
	check(toast_has(ts, "Du hörst auf – 1 Karte unter die Ablage."), "Aufhören: Meldung")
	check((ts.view.hand as Array).size() == 2 and not tv.staking, "Aufhören: Resthand 2, Hand wieder normal")
	check_matches_view(ts, "Aufhören")
	await close_table(ts)


# Ein Gegner hört auf: alle sehen es (Meldung), Einsatz wandert verdeckt unter die Ablage
func gamble_stop_opponent_test() -> void:
	var ts := await make_table(gamble_cfg(), 3, {"hands": [["hell_rot_2", "hell_blau_3", "hell_gelb_1"],
		["hell_gruen_1", "hell_gruen_2", "hell_gruen_3"], ["hell_blau_7", "hell_blau_8"]], "top": "hell_gluecksspiel", "color": "gruen",
		"current": 1, "gamble": {"q": 3, "stake": ["hell_gelb_2", "hell_gelb_3"], "need": "stake", "last": 0}})
	var g := game_of(ts)
	var tv := ts.table
	var lt := ts.source as LocalTable
	check(tv.gamble_machine.active and not tv.gamble_machine.can_stop, "Gegner-Aufhören: kein Knopf für mich")
	var name1 := str(g.players[1].name)
	lt._apply(1, {"a": "stop"})
	await settle(ts, 0.8)
	check(toast_has(ts, "%s hört auf – 2 Karten unter die Ablage." % name1), "Gegner-Aufhören: Meldung für alle")
	check(not tv.gamble_machine.active and not tv.stake_pile.shown and tv.seat_node(1).count() == 3, "Gegner-Aufhören: Automat weg, Hand bleibt")
	check_matches_view(ts, "Gegner-Aufhören")
	await close_table(ts)


# ----------------------------------------------------------------- Farbe mit ablegen

func discard_cfg() -> RuleConfig:
	var cfg := RuleConfig.new()
	cfg.discard_color = "on"
	return cfg


func discard_test() -> void:
	var ts := await make_table(discard_cfg(), 3, {"hands": [["hell_rot_ablegen", "hell_rot_3", "hell_rot_aussetzen", "hell_rot_plus1",
		"hell_rot_richtungswechsel", "hell_blau_2", "hell_wuenscher"], ["hell_gruen_1", "hell_gruen_2"], ["hell_blau_7", "hell_blau_8"]],
		"top": "hell_rot_5", "current": 0})
	var g := game_of(ts)
	var tv := ts.table
	var seen: Array = []
	ts.source.state_changed.connect(func(evs: Array, _v: Dictionary) -> void:
		for e in evs:
			seen.append(str(e.get("e", ""))))
	var log := watch(ts)
	ts.hand.play_requested.emit(RulesFixture.card(g, 0, "hell_rot_ablegen"), ts.hand.play_target)
	# 0.1.3: Auswahl (Phase discard_pick): alle 4 roten vorausgewählt, eine abwählen, „Ablegen (3)“
	await settle(ts, 0.3)
	var pick: PillButton = tv.get("_act_btns")["pick"]
	check(g.state == "discard_pick" and ts.hand.is_picking() and ts.hand.get_pick().size() == 4 and pick.visible and pick.text == "Ablegen (4)",
		"Ablegen: Auswahl mit 4 vorausgewählten Karten (%s, %s)" % [g.state, pick.text])
	var plus1 := RulesFixture.card(g, 0, "hell_rot_plus1")
	ts.hand.toggle_pick(plus1)
	check(pick.text == "Ablegen (3)" and not ts.hand.get_pick().has(plus1), "Ablegen: Abwählen zählt mit (%s)" % pick.text)
	ts.hand.call("_on_tap", RulesFixture.card(g, 0, "hell_blau_2"))
	check(ts.hand.get_pick().size() == 3 and g.state == "discard_pick", "Ablegen: andere Farbe nicht wählbar, nichts gespielt")
	pick.pressed.emit()
	await wait_event(log, "discard_color")
	check(toast_has(ts, "Du legst 3 rote Karten mit ab."), "Ablegen: Hinweis")
	check(sorted_ids(ts.view.get("hand", [])).has(plus1), "Ablegen: abgewählte Karte bleibt auf der Hand")
	await settle(ts, 0.8)
	check(seen.has("discard_color") and not seen.has("skip") and not seen.has("reverse") and not seen.has("pending"), "Ablegen: Aktionskarten wirken nicht (%s)" % [seen])
	check(g.current_seat() == 1 and g.dir == 1, "Ablegen: der Nächste ist dran, Richtung bleibt")
	var keys: Array = []
	for c in tv.discard_cards():
		keys.append(c.current_key())
	check(keys.back() == "hell_rot_ablegen", "Ablegen: Ablegen-Karte oben")
	var under_ok := true
	for k in ["hell_rot_3", "hell_rot_aussetzen", "hell_rot_richtungswechsel"]:
		if not keys.has(k):
			under_ok = false
	check(under_ok, "Ablegen: mitabgelegte Karten liegen unter der Ablegen-Karte (%s)" % [keys])
	var top: CardView = tv.discard_cards().back()
	var below_ok := true
	for c in tv.discard_cards():
		if c != top and c.get_index() > top.get_index():
			below_ok = false
	check(below_ok, "Ablegen: Zeichenreihenfolge unter der obersten Karte")
	check(not tv.get("_color_ring").pending, "Ablegen: keine Strafe angezeigt")
	check_matches_view(ts, "Ablegen")
	await close_table(ts)


func discard_opponent_test() -> void:
	var ts := await make_table(discard_cfg(), 3, {"hands": [["hell_rot_2", "hell_blau_3"],
		["hell_gelb_ablegen", "hell_gelb_1", "hell_gelb_flip", "hell_gruen_2"], ["hell_blau_7", "hell_blau_8"]],
		"top": "hell_gelb_5", "current": 1})
	var g := game_of(ts)
	var tv := ts.table
	var lt := ts.source as LocalTable
	var log := watch(ts)
	lt._apply(1, {"a": "play", "card": RulesFixture.card(g, 1, "hell_gelb_ablegen")})
	await settle(ts, 0.2)
	check(g.state == "discard_pick" and tv.hint_bar.hint.ends_with("wählt aus …") and not tv.get("_act_btns")["pick"].visible,
		"Ablegen Gegner: „… wählt aus …“ (%s)" % tv.hint_bar.hint)
	var deadline := Time.get_ticks_msec() + 8000
	while not log.has("discard_color") and Time.get_ticks_msec() < deadline:
		lt.pump()
		await frames(1)
	check(toast_has(ts, "Ben legt"), "Ablegen Gegner: Hinweis")
	await settle(ts, 0.8)
	check(g.side == 0 and tv.side == "hell", "Ablegen Gegner: mitabgelegter Flip wendet nicht")
	check(tv.discard_cards().back().current_key() == "hell_gelb_ablegen", "Ablegen Gegner: Ablegen-Karte oben")
	check_matches_view(ts, "Ablegen Gegner")
	await close_table(ts)


# ----------------------------------------------------------------- Spielbare Karten hervorheben

func highlight_test() -> void:
	var app := UiApp.app()
	var ts := await make_table(RuleConfig.new(), 2, {"hands": [["hell_rot_2", "hell_blau_3", "hell_rot_7"], ["hell_gruen_1", "hell_gruen_2"]],
		"top": "hell_rot_5", "current": 0})
	var g := game_of(ts)
	var tv := ts.table
	var red := RulesFixture.card(g, 0, "hell_rot_2")
	var blue := RulesFixture.card(g, 0, "hell_blau_3")
	await frames(3)
	check(ts.hand.highlight and ts.hand.card_view(red).state == CardView.State.PLAYABLE, "Hervorheben an: spielbare Karte markiert")
	if app != null:
		app.settings.set_value("hervorheben", false)
	await wait(0.4)
	check(not ts.hand.highlight and not tv.highlight, "Hervorheben aus: live übernommen")
	var marked := false
	var dimmed := false
	for id in ts.hand.get_order():
		var cv := ts.hand.card_view(id)
		if cv.state == CardView.State.PLAYABLE:
			marked = true
		if cv.brightness < 0.99 and ts.hand.get_mode() == HandLayout.Mode.FAN:
			dimmed = true
	check(not marked and not dimmed, "Hervorheben aus: kein Rand, kein Leuchten, kein Abdunkeln")
	var y_red := ts.hand.card_view(red).position.y
	var y_blue := ts.hand.card_view(blue).position.y
	check(absf(y_red - y_blue) < 3.0, "Hervorheben aus: spielbare Karte nicht angehoben (%.1f / %.1f)" % [y_red, y_blue])
	# unpassende Karte: springt zurück, Hinweis, keine Strafe
	var count_before := (g.hands[0] as Array).size()
	var played := ts.hand._try_play(blue, ts.hand.play_target)
	await frames(2)
	check(not played and ts.hand.get_order().has(blue), "Hervorheben aus: unpassende Karte bleibt in der Hand")
	check(toast_has(ts, "Die Karte passt nicht."), "Hervorheben aus: Hinweis „Die Karte passt nicht.“")
	check((g.hands[0] as Array).size() == count_before and g.current_seat() == 0, "Hervorheben aus: keine Strafe, weiter am Zug")
	# Scharfmachen beim Hochziehen verrät nichts (auch die unpassende Karte zeigt das Geisterbild)
	check(ts.hand.get("highlight") == false, "Hervorheben aus: Hand kennt die Einstellung")
	# Hinweis „nichts passt“ wird neutral
	check(tv.hint_text("Du bist dran – nichts passt, zieh eine Karte.") == "Du bist dran.", "Hervorheben aus: Hinweis verrät nichts")
	if app != null:
		app.settings.set_value("hervorheben", true)
	await frames(3)
	check(ts.hand.highlight and ts.hand.card_view(red).state == CardView.State.PLAYABLE, "Hervorheben wieder an")
	check(tv.hint_text("Du bist dran – nichts passt, zieh eine Karte.") != "Du bist dran.", "Hervorheben an: Hinweis unverändert")
	await close_table(ts)


# Ohne die Hausregeln: keine Glücksspiel-Felder, kein Automat, Farbanzeige bleibt
func plain_rules_test() -> void:
	var ts := await make_table(RuleConfig.preset("offiziell"), 3, {"hands": [["hell_rot_2", "hell_blau_3"], ["hell_gruen_1", "hell_gruen_2"],
		["hell_blau_7", "hell_blau_8"]], "top": "hell_rot_5", "current": 0})
	var tv := ts.table
	check(not ts.view.has("gamble") and not (ts.view.hints as Dictionary).has("can_stake"), "Ohne Hausregel: keine Glücksspiel-Felder")
	check(not tv.gamble_machine.active and not tv.gamble_machine.visible and not tv.stake_pile.visible, "Ohne Hausregel: kein Automat")
	check(tv.get("_color_mark").visible and not tv.staking, "Ohne Hausregel: Farbanzeige, normales Ausspielen")
	check(not tv.gamble_machine.is_processing(), "Ohne Hausregel: Automat schläft")
	ts.hand.play_requested.emit(RulesFixture.card(game_of(ts), 0, "hell_rot_2"), ts.hand.play_target)
	await settle(ts)
	check((ts.view.hand as Array).size() == 1, "Ohne Hausregel: normal gelegt")
	await close_table(ts)


# Ablegen-Joker (0.1.3): Farbrad „Welche Farbe legst du mit ab?“ → Auswahl → Farbrad „Mit welcher Farbe geht es weiter?“
func discard_joker_test() -> void:
	var ts := await make_table(discard_cfg(), 2, {"hands": [["hell_ablegen_joker", "hell_blau_3", "hell_blau_4", "hell_rot_7", "hell_gelb_2"],
		["hell_gruen_1", "hell_gruen_2"]], "top": "hell_rot_5", "current": 0})
	var g := game_of(ts)
	var tv := ts.table
	var log := watch(ts)
	ts.hand.play_requested.emit(RulesFixture.card(g, 0, "hell_ablegen_joker"), ts.hand.play_target)
	await frames(2)
	check(tv.wish_picker.mode == "wheel" and tv.wish_picker.title == "Welche Farbe legst du mit ab?" and int(tv.wish_picker.counts.get("blau", 0)) == 2,
		"Ablegen-Joker: erst die Ablegefarbe (mit Anzahl)")
	tv.wish_picker.close()
	tv.wish_picker.color_chosen.emit("blau")
	await settle(ts, 0.3)
	var pick: PillButton = tv.get("_act_btns")["pick"]
	check(g.state == "discard_pick" and ts.hand.get_pick().size() == 2 and pick.visible and pick.text == "Ablegen (2)", "Ablegen-Joker: Auswahl Blau (%s)" % pick.text)
	pick.pressed.emit()
	await frames(2)
	check(tv.wish_picker.mode == "wheel" and tv.wish_picker.title == "Mit welcher Farbe geht es weiter?" and not pick.visible
		and int(tv.wish_picker.counts.get("blau", 0)) == 0, "Ablegen-Joker: danach die Spielfarbe (ohne die mitabgelegten)")
	tv.wish_picker.close()
	tv.wish_picker.color_chosen.emit("gelb")
	await wait_event(log, "discard_color")
	await settle(ts, 0.5)
	check(g.color == "gelb" and g.state != "discard_pick" and (ts.view.get("hand", []) as Array).size() == 2 and not ts.hand.is_picking(),
		"Ablegen-Joker: Blau abgelegt, weiter mit Gelb (%s)" % g.color)
	await close_table(ts)


# Beta 1.4.1 (Nutzerbefund 10.10.2026): Jeder Abbruchweg beim Ablegen-Joker nimmt den ganzen Zug zurück (kein Hängen):
# Ablegefarbe weggeklickt (nichts gelegt), Spielfarbe weggeklickt, Zurück-Taste in beiden Schritten, Knopf „Zurücknehmen“.
func discard_undo_test() -> void:
	var ts := await make_table(discard_cfg(), 2, {"hands": [["hell_ablegen_joker", "hell_blau_3", "hell_blau_4", "hell_rot_7", "hell_gelb_2"],
		["hell_gruen_1", "hell_gruen_2"]], "top": "hell_rot_5", "current": 0})
	var g := game_of(ts)
	var tv := ts.table
	var joker := RulesFixture.card(g, 0, "hell_ablegen_joker")
	var pick: PillButton = tv.get("_act_btns")["pick"]
	var undo: PillButton = tv.get("_act_btns")["undo"]
	# 1. Ablegefarbe weggeklickt: nichts gelegt, Karte bleibt in der Hand
	ts.hand.play_requested.emit(joker, ts.hand.play_target)
	await frames(2)
	tv.wish_picker.cancel()
	await settle(ts, 0.3)
	check(g.state == "turn" and (g.hands[0] as Array).has(joker) and ts.hand.get_order().has(joker), "Abbruch Ablegefarbe: Joker bleibt in der Hand")
	# 2.–5. Abbruch nach dem Legen
	for way in ["rad", "rad_zurueck", "knopf", "zurueck"]:
		ts.hand.play_requested.emit(joker, ts.hand.play_target)
		await frames(2)
		tv.wish_picker.close()
		tv.wish_picker.color_chosen.emit("blau")
		await settle(ts, 0.3)
		check(g.state == "discard_pick" and pick.visible and undo.visible, "%s: Auswahl mit „Zurücknehmen“" % way)
		ts.hand.toggle_pick(RulesFixture.card(g, 0, "hell_blau_4"))
		match way:
			"rad", "rad_zurueck":
				pick.pressed.emit()
				await frames(2)
				check(tv.wish_picker.mode == "wheel" and not undo.visible, "%s: Farbrad der Spielfarbe offen" % way)
				if way == "rad":
					tv.wish_picker.drop(Vector2(-5000, -5000))      # Tipp daneben
				else:
					check(ts.on_back(), "%s: Zurück-Taste verbraucht" % way)
			"knopf":
				undo.pressed.emit()
			"zurueck":
				check(ts.on_back() and ts.get("_confirm") == null, "%s: Zurück-Taste nimmt zurück, kein „Partie verlassen?“" % way)
		await settle(ts, 0.5)
		check(g.state == "turn" and g.current_seat() == 0 and (g.hands[0] as Array).size() == 5 and (g.hands[0] as Array).has(joker),
			"%s: Joker zurück in der Hand (%s)" % [way, g.state])
		check(not tv.wish_picker.is_open() and not pick.visible and not undo.visible and not ts.hand.is_picking(), "%s: nichts hängt offen" % way)
		check(tv.discard_cards().back().current_key() == "hell_rot_5" and g.color == "rot", "%s: alte Karte wieder oben" % way)
		check_matches_view(ts, way)
	# Danach wieder ganz normal: alle Blauen mit ab (Auswahl frisch, nicht die abgewählte von vorher), weiter mit Gelb
	ts.hand.play_requested.emit(joker, ts.hand.play_target)
	await frames(2)
	tv.wish_picker.close()
	tv.wish_picker.color_chosen.emit("blau")
	await settle(ts, 0.3)
	check(ts.hand.get_pick().size() == 2, "nach dem Zurücknehmen: Auswahl wieder vollständig (%d)" % ts.hand.get_pick().size())
	pick.pressed.emit()
	await frames(2)
	tv.wish_picker.close()
	tv.wish_picker.color_chosen.emit("gelb")
	await settle(ts, 0.8)
	check(g.color == "gelb" and (g.hands[0] as Array).size() == 2 and g.current_seat() == 1, "nach dem Zurücknehmen normal abgelegt")
	await close_table(ts)


# Farbwahl nach einem Flip mit Joker oben (Phase color) ist endgültig: Wegklicken und Zurück-Taste öffnen das Rad sofort wieder.
func color_phase_test() -> void:
	var ts := await make_table(RuleConfig.new(), 3, {"hands": [["hell_rot_flip", "hell_rot_1"], ["hell_gelb_1"], ["hell_gelb_2"]],
		"top": "hell_rot_5", "discard": ["hell_blau_4/dunkel_wuenscher"], "current": 0})
	var g := game_of(ts)
	var tv := ts.table
	ts.hand.play_requested.emit(RulesFixture.card(g, 0, "hell_rot_flip"), ts.hand.play_target)
	await settle(ts, 0.5)
	check(g.state == "color" and tv.wish_picker.mode == "wheel", "Flip mit Joker oben: Farbrad offen (%s)" % g.state)
	tv.wish_picker.drop(Vector2(-5000, -5000))
	await frames(2)
	check(tv.wish_picker.mode == "wheel" and g.state == "color", "Phase color: Tipp daneben öffnet das Rad wieder")
	check(ts.on_back() and ts.get("_confirm") == null, "Phase color: Zurück-Taste verbraucht")
	await frames(2)
	check(tv.wish_picker.mode == "wheel" and g.state == "color", "Phase color: Rad nach der Zurück-Taste wieder offen")
	tv.wish_picker.close()
	tv.wish_picker.color_chosen.emit("pink")
	await settle(ts, 0.5)
	check(g.state == "turn" and g.color == "pink", "Phase color: Farbe gewählt, es geht weiter")
	await close_table(ts)
