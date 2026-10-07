extends SceneTree
# Modul A: öffentliches Ablage-Protokoll view.discard_log (Beta 1.0.1, „Ablage durchsehen“). Gebaute Fälle: Startkarten und
# Legen (Reihenfolge, Leger), Joker mit Wunschfarbe, „Farbe mit ablegen“ (Mitabgelegte mit Leger), Glücksspiel-Einsatz verdeckt
# (ohne Gesicht), Flip (andere Seite, umgekehrt), Mischen (nur die oberste bleibt), gleiche Liste für alle Plätze und Zuschauer,
# to_dict/from_dict. Der Lecktest über Zufallspartien steht in test_rules_views.gd (_check_discard_log, _expected_keys).

var failures := 0
var checks := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + message)


func _initialize() -> void:
	_play_and_joker()
	_discard_color()
	_gamble_stake()
	_flip()
	_reshuffle()
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)


func _act(g: MauGame, seat: int, action: Dictionary, msg: String) -> void:
	var r := g.apply(seat, action)
	check(bool(r.ok), "%s (abgelehnt: %s)" % [msg, r.get("reason", "")])


func _log(g: MauGame, seat := 0) -> Array:
	return g.view_for(seat).discard_log


func _same_for_all(g: MauGame, msg: String) -> void:
	var a := JSON.stringify(_log(g, 0))
	var ok := JSON.stringify(_log(g, -1)) == a
	for s in g.players.size():
		ok = ok and JSON.stringify(_log(g, s)) == a
	check(ok, "%s: für alle gleich" % msg)


func _play_and_joker() -> void:
	var g := RulesFixture.build(RuleConfig.new(), 3, {"hands": [["hell_rot_7", "hell_wuenscher", "hell_blau_1"], ["hell_rot_2", "hell_gelb_1"],
		["hell_gruen_1", "hell_gruen_2"]], "top": "hell_rot_5", "discard": ["hell_gelb_3"]})
	var dl := _log(g)
	check(dl.size() == 2 and dl[0].f == "hell_gelb_3" and dl[1].f == "hell_rot_5" and int(dl[0].s) == -1 and int(dl[1].s) == -1,
		"Start: unten zuerst, Leger unbekannt (%s)" % str(dl))
	_act(g, 0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_rot_7")}, "Rot 7")
	_act(g, 1, {"a": "play", "card": RulesFixture.card(g, 1, "hell_rot_2")}, "Rot 2")
	dl = _log(g)
	check(dl.size() == 4 and dl[2].f == "hell_rot_7" and int(dl[2].s) == 0 and dl[3].f == "hell_rot_2" and int(dl[3].s) == 1
		and dl[3].c == "" and not bool(dl[3].h), "Legen: oberste zuletzt, mit Leger (%s)" % str(dl))
	check(int(g.view_for(0).discard_count) == dl.size(), "Zahl passt zu discard_count")
	g.current = 0
	g.state = "turn"
	g.turn_started = false
	_act(g, 0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_wuenscher"), "color": "blau"}, "Wünscher Blau")
	dl = _log(g)
	check(dl.back().f == "hell_wuenscher" and dl.back().c == "blau" and int(dl.back().s) == 0, "Joker mit Wunschfarbe (%s)" % str(dl.back()))
	_same_for_all(g, "Legen")
	var g2 := MauGame.from_dict(JSON.parse_string(JSON.stringify(g.to_dict())))
	check(JSON.stringify(_log(g2)) == JSON.stringify(_log(g)), "to_dict/from_dict behält das Protokoll")


func _discard_color() -> void:
	var cfg := RuleConfig.from_dict({"discard_color": "on"})
	var g := RulesFixture.build(cfg, 3, {"hands": [["hell_rot_ablegen", "hell_rot_9", "hell_rot_1", "hell_gelb_2"], ["hell_blau_1", "hell_blau_2"],
		["hell_gruen_1", "hell_gruen_2"]], "top": "hell_rot_5"})
	_act(g, 0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_rot_ablegen")}, "Rot ablegen")
	_act(g, 0, {"a": "discard_pick", "cards": [RulesFixture.card(g, 0, "hell_rot_9"), RulesFixture.card(g, 0, "hell_rot_1")]}, "Auswahl")
	var dl := _log(g)
	var n := dl.size()
	check(dl.back().f == "hell_rot_ablegen" and int(dl.back().s) == 0 and int(dl[n - 2].s) == 0 and int(dl[n - 3].s) == 0
		and int(dl[n - 4].s) == -1, "Mitabgelegte zählen mit Leger, Ablegen-Karte oben (%s)" % str(dl))
	var mid := [str(dl[n - 3].f), str(dl[n - 2].f)]
	mid.sort()
	check(mid == ["hell_rot_1", "hell_rot_9"], "Mitabgelegte offen (%s)" % str(mid))


func _gamble_stake() -> void:
	var cfg := RuleConfig.from_dict({"gamble_cards": "on"})
	var g := RulesFixture.build(cfg, 3, {"hands": [["hell_blau_4", "hell_gelb_4", "hell_gruen_4"], ["hell_blau_1"], ["hell_gruen_1"]],
		"top": "hell_gluecksspiel", "color": "rot", "discard": ["hell_rot_3"], "gamble": {"q": 5, "stake": ["hell_rot_8", "hell_gelb_8"], "need": "press"}})
	g.force_rolls([0])
	_act(g, 0, {"a": "press"}, "Druck ohne Treffer")
	_act(g, 0, {"a": "stop"}, "Aufhören")
	var dl := _log(g)
	check(dl.size() == 4 and bool(dl[0].h) and bool(dl[1].h) and dl[0].f == "" and dl[1].f == "" and int(dl[0].s) == 0 and int(dl[1].s) == 0,
		"Einsatz verdeckt unter der Ablage, ohne Gesicht (%s)" % str(dl))
	check(not bool(dl[2].h) and dl[2].f == "hell_rot_3" and dl[3].f == "hell_gluecksspiel", "darüber offen (%s)" % str(dl))
	var js := JSON.stringify(_log(g, 1))
	check(not js.contains("hell_rot_8") and not js.contains("hell_gelb_8"), "kein Einsatzgesicht im Protokoll")
	_same_for_all(g, "Einsatz")


func _flip() -> void:
	var g := RulesFixture.build(RuleConfig.new(), 3, {"hands": [["hell_rot_flip", "hell_blau_1"], ["hell_blau_2", "hell_gelb_1"], ["hell_gruen_1"]],
		"top": "hell_rot_5", "discard": ["hell_gelb_5"]})
	var ids: Array = g.discard.duplicate()
	var fid := RulesFixture.card(g, 0, "hell_rot_flip")
	_act(g, 0, {"a": "play", "card": fid}, "Flip")
	check(g.side == 1, "Flip ausgeführt")
	ids.append(fid)
	ids.reverse()
	var dl := _log(g)
	var ok := dl.size() == ids.size()
	for i in mini(dl.size(), ids.size()):
		ok = ok and dl[i].f == g._key[g.faces[g.n_cards + int(ids[i])]]
	check(ok, "Flip: dunkle Seite, umgekehrte Reihenfolge (%s)" % str(dl))
	check(int(dl[0].s) == 0 and int(dl.back().s) == -1, "Leger wandern mit (%s)" % str(dl))
	check(dl.back().f == g.view_for(0).top.face, "oberster Eintrag = Oberkarte")


func _reshuffle() -> void:
	var g := RulesFixture.build(RuleConfig.new(), 3, {"hands": [["hell_rot_7", "hell_blau_1"], ["hell_blau_2", "hell_gelb_1"], ["hell_gruen_1"]],
		"top": "hell_rot_5", "rest": "discard"})
	check(g.draw_pile.is_empty() and g.discard.size() > 10, "Aufbau: Nachziehstapel leer")
	_act(g, 0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_rot_7")}, "Rot 7")
	_act(g, 1, {"a": "draw"}, "Ziehen mit Mischen")
	var dl := _log(g)
	check(dl.size() == 1 and dl[0].f == "hell_rot_7" and int(dl[0].s) == 0, "Mischen: nur die oberste bleibt, mit Leger (%s)" % str(dl))
