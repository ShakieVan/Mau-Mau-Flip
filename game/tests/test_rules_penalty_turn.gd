extends SceneTree
# Hausregel penalty_turn (Nutzerwunsch 05.10.2026: „wenn man +1, +5 usw. gezogen hat, ist man in der Regel noch am Zug und
# kann etwas legen“): offiziell zieht das Opfer und setzt aus (skip); mit „play“ ist es danach ganz normal am Zug.
# Geprüft: einfache Ziehkarte, gestapelte Strafe, angenommener Wünscher +2 (Bluff-Modus), gescheitertes Anzweifeln,
# Voreinstellungen und Texte.

var ok := 0
var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		ok += 1
	else:
		fails += 1
		print("FAIL: " + what)


func cfg(over: Dictionary) -> RuleConfig:
	var c := RuleConfig.new()
	c.apply_dict(over)
	return c


func act(g: MauGame, seat: int, action: Dictionary, what: String) -> Array:
	var r := g.apply(seat, action)
	check(bool(r.ok), "%s: %s" % [what, str(r.get("reason", ""))])
	return r.get("events", [])


func has_ev(ev: Array, name: String, seat := -1) -> bool:
	for e in ev:
		if str(e.get("e", "")) == name and (seat < 0 or int(e.get("seat", -1)) == seat):
			return true
	return false


func _init() -> void:
	_simple()
	_stacked()
	_wild_accept_and_challenge()
	_presets_and_texts()
	print("RESULT: %d ok" % ok if fails == 0 else "RESULT: %d ok, %d FAIL" % [ok, fails])
	quit(0 if fails == 0 else 1)


func _spec() -> Dictionary:
	return {"hands": [["hell_rot_plus1", "hell_rot_1"], ["hell_rot_3", "hell_gelb_4"], ["hell_gelb_2", "hell_blau_7"]],
		"top": "hell_rot_5", "draw": ["hell_blau_4", "hell_gruen_6", "hell_blau_8"]}


func _simple() -> void:
	# offiziell: Opfer zieht 1 und setzt aus
	var g := RulesFixture.build(cfg({}), 3, _spec())
	var ev := act(g, 0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_rot_plus1")}, "+1 legen (offiziell)")
	check(g.hands[1].size() == 3, "offiziell: Opfer hat 1 gezogen")
	check(has_ev(ev, "skip", 1), "offiziell: Ereignis skip für das Opfer")
	check(g.current_seat() == 2, "offiziell: danach ist Platz 2 dran (%d)" % g.current_seat())
	# Hausregel: Opfer zieht 1 und ist dann dran
	g = RulesFixture.build(cfg({"penalty_turn": "play"}), 3, _spec())
	ev = act(g, 0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_rot_plus1")}, "+1 legen (Hausregel)")
	check(g.hands[1].size() == 3, "Hausregel: Opfer hat 1 gezogen")
	check(not has_ev(ev, "skip", 1), "Hausregel: kein skip für das Opfer")
	check(g.current_seat() == 1 and g.phase() == "turn", "Hausregel: Opfer ist danach am Zug (%d, %s)" % [g.current_seat(), g.phase()])
	var v := g.view_for(1)
	check((v.hints.playable as Array).has(RulesFixture.card(g, 1, "hell_rot_3")), "Hausregel: passende Karte ist spielbar")
	act(g, 1, {"a": "play", "card": RulesFixture.card(g, 1, "hell_rot_3")}, "Opfer legt nach dem Strafziehen")
	check(g.current_seat() == 2, "danach geht es normal weiter (%d)" % g.current_seat())


func _stacked() -> void:
	var spec := {"hands": [["hell_rot_plus1", "hell_rot_1"], ["hell_gelb_plus1", "hell_gelb_4"], ["hell_rot_2", "hell_blau_7"]],
		"top": "hell_rot_5", "draw": ["hell_blau_4", "hell_gruen_6", "hell_blau_8", "hell_gruen_1"]}
	var g := RulesFixture.build(cfg({"stacking": "same", "penalty_turn": "play"}), 3, spec)
	act(g, 0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_rot_plus1")}, "+1 legen")
	check(g.current_seat() == 1, "gestapelt: Platz 1 entscheidet")
	act(g, 1, {"a": "play", "card": RulesFixture.card(g, 1, "hell_gelb_plus1")}, "+1 drauflegen")
	check(g.current_seat() == 2, "gestapelt: Platz 2 entscheidet")
	act(g, 2, {"a": "draw"}, "Platz 2 nimmt die Strafe")
	check(g.hands[2].size() == 4, "gestapelt: Platz 2 hat 2 gezogen (%d)" % g.hands[2].size())
	check(g.current_seat() == 2 and g.phase() == "turn", "gestapelt + Hausregel: Platz 2 ist danach am Zug")
	act(g, 2, {"a": "draw"}, "Platz 2 zieht normal weiter (nichts Gelbes auf der Hand)")
	# offiziell mit Stapeln: Platz 2 setzt nach dem Ziehen aus
	g = RulesFixture.build(cfg({"stacking": "same"}), 3, spec)
	act(g, 0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_rot_plus1")}, "+1 legen (offiziell)")
	act(g, 1, {"a": "play", "card": RulesFixture.card(g, 1, "hell_gelb_plus1")}, "+1 drauflegen (offiziell)")
	act(g, 2, {"a": "draw"}, "Platz 2 nimmt die Strafe (offiziell)")
	check(g.current_seat() == 0, "gestapelt offiziell: danach Platz 0 (%d)" % g.current_seat())


func _wild_accept_and_challenge() -> void:
	# Wünscher +2 regelgerecht (keine rote Karte), Opfer nimmt an
	var spec := {"hands": [["hell_wuenscher_plus2", "hell_gelb_1"], ["hell_blau_3", "hell_gelb_4"], ["hell_gelb_2", "hell_blau_7"]],
		"top": "hell_rot_5", "draw": ["hell_blau_4", "hell_gruen_6", "hell_blau_8", "hell_gruen_1", "hell_gelb_9", "hell_gelb_8"]}
	var g := RulesFixture.build(cfg({"wild_restriction": "bluff", "wild_counts_for_bluff": false, "penalty_turn": "play"}), 3, spec)
	act(g, 0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_wuenscher_plus2"), "color": "blau"}, "Wünscher +2 legen")
	check(g.phase() == "challenge" and g.current_seat() == 1, "Opfer darf anzweifeln")
	act(g, 1, {"a": "accept"}, "Opfer nimmt an")
	check(g.hands[1].size() == 4, "angenommen: 2 gezogen")
	check(g.current_seat() == 1 and g.phase() == "turn", "angenommen + Hausregel: Opfer ist danach am Zug")
	act(g, 1, {"a": "play", "card": RulesFixture.card(g, 1, "hell_blau_3")}, "Opfer legt Blau")
	# Anzweifeln scheitert (Leger war ehrlich): Herausforderer zieht 4 und ist mit der Hausregel danach am Zug
	g = RulesFixture.build(cfg({"wild_restriction": "bluff", "wild_counts_for_bluff": false, "penalty_turn": "play"}), 3, spec)
	act(g, 0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_wuenscher_plus2"), "color": "blau"}, "Wünscher +2 legen (2)")
	act(g, 1, {"a": "challenge"}, "Opfer zweifelt an")
	check(g.hands[1].size() == 6, "gescheitert: 4 gezogen (%d)" % g.hands[1].size())
	check(g.current_seat() == 1 and g.phase() == "turn", "gescheitert + Hausregel: Herausforderer ist danach am Zug")
	# dasselbe offiziell: Herausforderer setzt aus
	g = RulesFixture.build(cfg({"wild_restriction": "bluff", "wild_counts_for_bluff": false}), 3, spec)
	act(g, 0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_wuenscher_plus2"), "color": "blau"}, "Wünscher +2 legen (3)")
	act(g, 1, {"a": "challenge"}, "Opfer zweifelt an (offiziell)")
	check(g.current_seat() == 2, "gescheitert offiziell: Platz 2 ist dran (%d)" % g.current_seat())


func _presets_and_texts() -> void:
	check(RuleConfig.preset("offiziell").penalty_turn == "skip", "Offiziell: aussetzen")
	check(RuleConfig.preset("familie").penalty_turn == "play", "Familie: weiterspielen")
	var c := RuleConfig.from_dict({"penalty_turn": "play"})
	check(c.penalty_turn == "play" and c.to_dict().penalty_turn == "play", "Rundreise to_dict/from_dict")
	check(RuleConfig.from_dict({"penalty_turn": "quatsch"}).penalty_turn == "skip", "ungültiger Wert bleibt beim Standard")
	var help := "\n".join(RulesText.card_help("dunkel_pink_plus5", c))
	check(help.contains("trotzdem dran") and not help.contains("setzt aus"), "Kartenhilfe +5 mit Hausregel (%s)" % help)
	help = "\n".join(RulesText.card_help("dunkel_pink_plus5", RuleConfig.new()))
	check(help.contains("setzt aus"), "Kartenhilfe +5 offiziell")
	check("\n".join(c.describe()).contains("trotzdem dran"), "Regelübersicht nennt die Hausregel")
