extends SceneTree
# Hausregel „Nach dem Ziehen: beliebige Karte legen“ (draw_play, Beta 1.1.3): drawn (offiziell, nur die gezogene Karte) und any
# (jede passende Karte oder behalten). Gezogene passt/passt nicht, andere passt, nichts passt, drawn_card must/may_not,
# until_playable, Strafziehen, Mau-Fenster, Sicht/Lecks, Bots, Familie, Hebung, Texte.
# Plätze: 0 Anna, 1 Ben, 2 Cleo (3 Spieler, Platz 0 am Zug, Richtung +1), oben hell_rot_5.

var failures := 0
var checks := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)


func _initialize() -> void:
	_official()
	_any_basic()
	_any_options()
	_penalty()
	_mau_window()
	_views_and_bots()
	_config()
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)


# --- Hilfen ---

func make(hand: Array, draw: Array, opts := {}) -> MauGame:
	var spec := {"hands": [hand, ["hell_gruen_1", "hell_gruen_2"], ["hell_gruen_3", "hell_gruen_4"]], "top": "hell_rot_5",
		"draw": draw}
	var g := RulesFixture.build(RuleConfig.from_dict(opts), 3, spec)
	check(RulesFixture.card_check(g) == "", "Aufbau: " + RulesFixture.card_check(g))
	return g


func id_of(g: MauGame, seat: int, key: String) -> int:
	var id := RulesFixture.card(g, seat, key)
	check(id >= 0, "Karte %s bei Platz %d vorhanden" % [key, seat])
	return id


func act(g: MauGame, seat: int, action: Dictionary, msg: String) -> Array:
	var r := g.apply(seat, action)
	check(bool(r.ok), "%s (abgelehnt: %s)" % [msg, r.reason])
	check(RulesFixture.card_check(g) == "", "%s: Kartenzahl %s" % [msg, RulesFixture.card_check(g)])
	return r.events


func deny(g: MauGame, seat: int, action: Dictionary, msg: String) -> String:
	var before := JSON.stringify(g.to_dict())
	var r := g.apply(seat, action)
	check(not bool(r.ok), msg + " (wurde angenommen)")
	check(JSON.stringify(g.to_dict()) == before, msg + ": Zustand unverändert")
	return str(r.reason)


func playable(g: MauGame, seat := 0) -> Array:
	var out: Array = []
	for id in g.view_for(seat).hints.playable:
		out.append(int(id))
	out.sort()
	return out


func ids(g: MauGame, seat: int, keys: Array) -> Array:
	var out: Array = []
	for k in keys:
		out.append(id_of(g, seat, str(k)))
	out.sort()
	return out


func names(ev: Array) -> Array:
	var out: Array = []
	for e in ev:
		out.append(str(e.e))
	return out


# --- Fälle ---

func _official() -> void:
	# drawn (Standard): gezogene passt nicht → Zug vorbei, obwohl rot_3 gepasst hätte
	var g := make(["hell_blau_1", "hell_rot_3"], ["hell_gelb_9"])
	check(g.config.draw_play == "drawn", "Standard drawn")
	act(g, 0, {"a": "draw"}, "offiziell: freiwillig ziehen")
	check(g.state == "turn" and g.current == 1, "offiziell: gezogene passt nicht → Zug vorbei")
	# drawn: gezogene passt → nur sie legbar
	g = make(["hell_blau_1", "hell_rot_3"], ["hell_rot_9"])
	act(g, 0, {"a": "draw"}, "offiziell: ziehen (passt)")
	check(g.state == "drawn" and playable(g) == ids(g, 0, ["hell_rot_9"]), "offiziell: nur die gezogene legbar (%s)" % str(playable(g)))
	var why := deny(g, 0, {"a": "play", "card": id_of(g, 0, "hell_rot_3")}, "offiziell: andere Karte abgelehnt")
	check(why.contains("gezogene"), "offiziell: Begründung (%s)" % why)


func _any_basic() -> void:
	var opts := {"draw_play": "any"}
	# gezogene passt nicht, andere passt → Phase drawn bleibt
	var g := make(["hell_blau_1", "hell_rot_3"], ["hell_gelb_9"], opts)
	act(g, 0, {"a": "draw"}, "any: ziehen (passt nicht)")
	var v := g.view_for(0)
	check(g.state == "drawn" and g.current == 0, "any: drawn bleibt, obwohl die gezogene nicht passt")
	check(playable(g) == ids(g, 0, ["hell_rot_3"]), "any: andere passende Karte legbar (%s)" % str(playable(g)))
	check(bool(v.hints.can_keep) and not bool(v.hints.can_draw), "any: behalten ja, ziehen nein")
	check(int(v.drawn) == id_of(g, 0, "hell_gelb_9"), "any: gezogene Karte in der Sicht")
	check(str(v.hints.text).contains("behalten"), "any: Hinweistext (%s)" % v.hints.text)
	var why := deny(g, 0, {"a": "play", "card": id_of(g, 0, "hell_gelb_9")}, "any: gezogene passt nicht → abgelehnt")
	check(why.begins_with("Passt nicht"), "any: Begründung (%s)" % why)
	deny(g, 0, {"a": "draw"}, "any: nicht noch einmal ziehen")
	act(g, 0, {"a": "play", "card": id_of(g, 0, "hell_rot_3")}, "any: andere Karte gelegt")
	check(g.current == 1 and g.state == "turn" and g.drawn_id == -1 and RulesFixture.top_key(g) == "hell_rot_3", "any: Zug weiter")
	# gezogene passt → alle passenden legbar
	g = make(["hell_blau_1", "hell_rot_3"], ["hell_rot_9"], opts)
	act(g, 0, {"a": "draw"}, "any: ziehen (passt)")
	check(playable(g) == ids(g, 0, ["hell_rot_3", "hell_rot_9"]), "any: gezogene und andere legbar (%s)" % str(playable(g)))
	act(g, 0, {"a": "play", "card": id_of(g, 0, "hell_rot_9")}, "any: gezogene gelegt")
	check(g.current == 1 and RulesFixture.top_key(g) == "hell_rot_9", "any: gezogene liegt oben")
	# behalten
	g = make(["hell_blau_1", "hell_rot_3"], ["hell_gelb_9"], opts)
	act(g, 0, {"a": "draw"}, "any: ziehen")
	var ev := act(g, 0, {"a": "keep"}, "any: behalten")
	check(names(ev).has("keep") and g.current == 1 and (g.hands[0] as Array).size() == 3, "any: behalten beendet den Zug")
	# nichts passt → Zug vorbei wie bisher
	g = make(["hell_blau_1", "hell_gelb_2"], ["hell_gruen_9"], opts)
	act(g, 0, {"a": "draw"}, "any: ziehen (nichts passt)")
	check(g.state == "turn" and g.current == 1 and g.drawn_id == -1, "any: nichts passt → Zug vorbei")


func _any_options() -> void:
	# must + any: gezogene passt → muss gelegt werden; passt sie nicht → frei wählen oder behalten
	var g := make(["hell_blau_1", "hell_rot_3"], ["hell_rot_9"], {"draw_play": "any", "drawn_card": "must"})
	act(g, 0, {"a": "draw"}, "must+any: ziehen (passt)")
	check(playable(g) == ids(g, 0, ["hell_rot_9"]) and not bool(g.view_for(0).hints.can_keep), "must+any: nur gezogene, kein Behalten")
	deny(g, 0, {"a": "keep"}, "must+any: behalten abgelehnt")
	g = make(["hell_blau_1", "hell_rot_3"], ["hell_gelb_9"], {"draw_play": "any", "drawn_card": "must"})
	act(g, 0, {"a": "draw"}, "must+any: ziehen (passt nicht)")
	check(g.state == "drawn" and playable(g) == ids(g, 0, ["hell_rot_3"]) and bool(g.view_for(0).hints.can_keep), "must+any: andere oder behalten")
	act(g, 0, {"a": "keep"}, "must+any: behalten")
	# may_not + any: gezogene nie, andere schon
	g = make(["hell_blau_1", "hell_rot_3"], ["hell_rot_9"], {"draw_play": "any", "drawn_card": "may_not"})
	act(g, 0, {"a": "draw"}, "may_not+any: ziehen")
	check(g.state == "drawn" and playable(g) == ids(g, 0, ["hell_rot_3"]), "may_not+any: nur andere (%s)" % str(playable(g)))
	var why := deny(g, 0, {"a": "play", "card": id_of(g, 0, "hell_rot_9")}, "may_not+any: gezogene abgelehnt")
	check(why.contains("nächsten Zug"), "may_not+any: Begründung (%s)" % why)
	# until_playable: wie bisher nur die gezogene
	g = make(["hell_blau_1", "hell_rot_3"], ["hell_gelb_9", "hell_rot_8"], {"draw_play": "any", "draw_rule": "until_playable"})
	act(g, 0, {"a": "draw"}, "until_playable+any: ziehen")
	check(g.state == "drawn" and playable(g) == ids(g, 0, ["hell_rot_8"]), "until_playable+any: nur die gezogene (%s)" % str(playable(g)))
	# enforce: Wünscher +2 bleibt nach dem Ziehen gesperrt, wenn eine Karte der Farbe da ist
	g = make(["hell_wuenscher_plus2", "hell_rot_3"], ["hell_gelb_9"], {"draw_play": "any", "wild_restriction": "enforce"})
	act(g, 0, {"a": "draw"}, "enforce+any: ziehen")
	check(playable(g) == ids(g, 0, ["hell_rot_3"]), "enforce+any: Wünscher +2 gesperrt (%s)" % str(playable(g)))


func _penalty() -> void:
	# Strafziehen bleibt, wie penalty_turn es regelt (play: danach Phase turn, kein drawn)
	var spec := {"hands": [["hell_blau_1", "hell_rot_3"], ["hell_gruen_1", "hell_gruen_2"], ["hell_rot_plus1", "hell_gruen_4"]],
		"top": "hell_rot_5", "draw": ["hell_gelb_9", "hell_gelb_8"], "current": 2}
	var g := RulesFixture.build(RuleConfig.from_dict({"draw_play": "any", "penalty_turn": "play", "stacking": "same"}), 3, spec)
	act(g, 2, {"a": "play", "card": id_of(g, 2, "hell_rot_plus1")}, "Strafe: +1 gelegt")
	check(g.current == 0 and not g.pending.is_empty(), "Strafe offen für Anna")
	act(g, 0, {"a": "draw"}, "Strafe ziehen")
	check(g.state == "turn" and g.current == 0 and g.pending.is_empty(), "nach dem Strafziehen: Phase turn (wie bisher)")
	act(g, 0, {"a": "draw"}, "danach freiwillig ziehen")
	check(g.state == "drawn" and playable(g) == ids(g, 0, ["hell_rot_3"]), "danach gilt any (%s)" % str(playable(g)))
	g = RulesFixture.build(RuleConfig.from_dict({"draw_play": "any", "stacking": "same"}), 3, spec)
	act(g, 2, {"a": "play", "card": id_of(g, 2, "hell_rot_plus1")}, "Strafe skip: +1 gelegt")
	act(g, 0, {"a": "draw"}, "Strafe skip: ziehen")
	check(g.current == 1 and g.state == "turn", "skip: Strafe ziehen und aussetzen (wie bisher)")


func _mau_window() -> void:
	# Mit 1 Karte ziehen (2 auf der Hand), dann eine andere passende legen: „Mau!“ möglich, kein Strafgrund
	var g := make(["hell_rot_3"], ["hell_gelb_9"], {"draw_play": "any"})
	act(g, 0, {"a": "draw"}, "Mau: ziehen")
	check(g.state == "drawn" and bool(g.view_for(0).hints.can_mau), "Mau: Ruf nach dem Ziehen möglich")
	act(g, 0, {"a": "mau"}, "Mau: gerufen")
	act(g, 0, {"a": "play", "card": id_of(g, 0, "hell_rot_3")}, "Mau: rot_3 gelegt")
	check((g.hands[0] as Array).size() == 1 and g.mau_said[0], "Mau: 1 Karte, gerufen")
	# ohne Ruf: erwischbar
	g = make(["hell_rot_3"], ["hell_gelb_9"], {"draw_play": "any"})
	act(g, 0, {"a": "draw"}, "Mau vergessen: ziehen")
	act(g, 0, {"a": "play", "card": id_of(g, 0, "hell_rot_3")}, "Mau vergessen: gelegt")
	check(g.mau_open == 0 and (g.view_for(1).hints.catch as Array) == [0], "Mau vergessen: Fenster offen")
	# offiziell: gezogene passt nicht → kein Ruf, Zug vorbei
	g = make(["hell_rot_3"], ["hell_gelb_9"])
	act(g, 0, {"a": "draw"}, "Mau offiziell: ziehen")
	check(g.current == 1 and g.mau_open != 0, "Mau offiziell: Zug vorbei, kein Fenster")


func _views_and_bots() -> void:
	var g := make(["hell_blau_1", "hell_rot_3"], ["hell_gelb_9"], {"draw_play": "any"})
	act(g, 0, {"a": "draw"}, "Sicht: ziehen")
	for s in [1, 2]:
		var v := g.view_for(s)
		check(int(v.drawn) == -1 and (v.hints.playable as Array).is_empty() and not bool(v.hints.can_keep), "Sicht Platz %d ohne Leck" % s)
		check(not str(v.hints.text).contains("behalten"), "Sicht Platz %d: kein Hinweis aufs Behalten" % s)
	check(int(g.view_for(-1).drawn) == -1, "Zuschauer ohne gezogene Karte")
	# Bots: legen die passende Karte oder behalten; Entscheidung gültig und deterministisch
	for level in [0, 1, 2]:
		var a := MauBot.choose(g.view_for(0), 99, level)
		check(a == MauBot.choose(g.view_for(0), 99, level), "Bot %d deterministisch" % level)
		check(str(a.get("a", "")) in ["play", "keep"], "Bot %d: legen oder behalten (%s)" % [level, str(a)])
		var g2 := MauGame.from_dict(g.to_dict())
		check(bool(g2.apply(0, a).ok), "Bot %d: Aktion gültig (%s)" % [level, str(a)])
	# mehrere passende Karten nach dem Ziehen (gezogene und eine andere): Wahl nach der Zug-Taktik
	var gm := make(["hell_blau_1", "hell_rot_3", "hell_wuenscher"], ["hell_rot_9"], {"draw_play": "any"})
	act(gm, 0, {"a": "draw"}, "Bot mehrere: ziehen")
	for level in [0, 1, 2]:
		for sd in [1, 2, 3]:
			var a := MauBot.choose(gm.view_for(0), sd, level)
			var g3 := MauGame.from_dict(gm.to_dict())
			check(str(a.get("a", "")) in ["play", "keep"] and bool(g3.apply(0, a).ok), "Bot %d/%d mehrere: gültig (%s)" % [level, sd, str(a)])
	var b := MauBot.choose(g.view_for(0), 7, 2)
	check(str(b.get("a", "")) == "play" and int(b.get("card", -1)) == id_of(g, 0, "hell_rot_3"), "Bot 2 legt rot_3 (%s)" % str(b))
	# ganze Partien mit Bots: Kartenerhaltung, Ende
	for sd in [11, 12, 13]:
		var cfg := RuleConfig.preset("familie")
		var gg := MauGame.create(cfg, RulesFixture.players(4, "bot"), sd)
		gg.start_round()
		var steps := 0
		var drawn_any := 0
		while gg.state in MauGame.PLAY_PHASES and steps < 4000:
			var moved := false
			for s in 4:
				var a := MauBot.choose(gg.view_for(s), sd * 1000 + steps, 2)
				if a.is_empty():
					continue
				if gg.state == "drawn" and str(a.get("a", "")) == "play" and int(a.get("card", -1)) != gg.drawn_id:
					drawn_any += 1
				var r := gg.apply(s, a)
				check(bool(r.ok), "Partie %d: Bot-Aktion gültig (%s: %s)" % [sd, str(a), r.reason])
				moved = true
				break
			if not moved:
				break
			steps += 1
		check(not gg.state in MauGame.PLAY_PHASES, "Partie %d endet (%d Schritte, %s)" % [sd, steps, gg.state])
		check(RulesFixture.card_check(gg) == "", "Partie %d: Kartenerhaltung" % sd)
		if sd == 11:
			print("Partie 11: %d Schritte, %d-mal andere Karte nach dem Ziehen" % [steps, drawn_any])


func _config() -> void:
	var fam := RuleConfig.preset("familie")
	check(fam.draw_play == "any" and RuleConfig.new().draw_play == "drawn", "Familie any, Standard drawn")
	check(fam.preset_name() == "familie" and RuleConfig.preset("mau_mau").draw_play == "drawn", "Voreinstellungen")
	var old := fam.to_dict()
	old.erase("draw_play")                              # Familie 1.1.2, so gespeichert
	check(RuleConfig.from_dict(RuleConfig.migrate_dict(old)).equals(fam), "Hebung: Familie 1.1.2 → any")
	var older := old.duplicate()
	older.erase("flip_mode")                            # Familie 1.0.1
	check(RuleConfig.from_dict(RuleConfig.migrate_dict(older)).equals(fam), "Hebung: Familie 1.0.1 → heutige")
	var chosen := fam.to_dict()
	chosen["draw_play"] = "drawn"
	check(RuleConfig.migrate_dict(chosen) == chosen, "keine Hebung bei gewähltem drawn")
	var custom := old.duplicate()
	custom["hand_size"] = 8
	check(RuleConfig.migrate_dict(custom) == custom, "keine Hebung bei eigenen Regeln")
	check(RuleConfig.migrate_dict({}) == {}, "offiziell bleibt")
	var bad := RuleConfig.from_dict({"draw_play": "alles"})
	check(bad.draw_play == "drawn", "ungültiger Wert ignoriert")
	var back := RuleConfig.from_dict(JSON.parse_string(JSON.stringify(fam.to_dict())))
	check(back.draw_play == "any", "Rundreise über JSON")
	# Texte
	check("\n".join(fam.describe()).contains("jede passende Karte"), "describe Familie")
	check(not "\n".join(RuleConfig.new().describe()).contains("jede passende"), "describe offiziell ohne Hausregel")
	check(not "\n".join(RuleConfig.from_dict({"draw_play": "any", "draw_rule": "until_playable"}).describe()).contains("passende Karte legen oder"), "describe until_playable ohne Hausregel")
	var ov := ""
	for p in RulesText.overview(fam):
		ov += str(p.text) + " "
	check(ov.contains("Hausregel: Danach darfst du jede passende Karte"), "Übersicht Familie")
	ov = ""
	for p in RulesText.overview(RuleConfig.new()):
		ov += str(p.text) + " "
	check(ov.contains("nur die gezogene Karte legen"), "Übersicht offiziell")
