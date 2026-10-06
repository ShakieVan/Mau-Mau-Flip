extends SceneTree
# Hausregel „Flip-Überraschung“ (flip_surprise, Protokoll 0.1.4 Nr. 1): Die klassische Aktionskarte, die nach einem Flip oben
# liegt, wirkt, als hätte der Flip-Spieler sie gelegt. Geprüft: jede Kartenart, Joker oben mit Farbwahl (auch nach Speichern),
# Stapeln, penalty_turn, keine Überraschung bei Flip/Wünscher/Zusatzkarten oben, am Rundenende und offiziell; Ereignis und
# Reihenfolge; dazu die neue „Familie“ und ihre Hebung in RuleConfig.migrate_dict (Protokoll 0.1.4 Nr. 2).

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
	var bad := RulesFixture.invariants(g)
	check(bad == "", "%s: Invariante %s" % [what, bad])
	return r.get("events", [])


func names(ev: Array) -> Array:
	var out: Array = []
	for e in ev:
		out.append(str(e.get("e", "")))
	return out


func find_ev(ev: Array, n: String) -> Dictionary:
	for e in ev:
		if str(e.get("e", "")) == n:
			return e
	return {}


# Flip von Platz 0; unten auf der Ablage liegt eine Karte mit dem Gesicht bottom auf der anderen Seite.
func flip_game(over: Dictionary, bottom: String, players := 3, extra := {}) -> MauGame:
	var dark := bottom.begins_with("dunkel")
	var spec := {"hands": [["hell_rot_flip", "hell_rot_1"], ["hell_gelb_1"], ["hell_gelb_2"]], "top": "hell_rot_5",
		"discard": ["hell_blau_4/" + bottom]}
	if not dark:
		spec = {"side": "dunkel", "hands": [["dunkel_lila_flip", "dunkel_lila_1"], ["dunkel_pink_1"], ["dunkel_pink_2"]],
			"top": "dunkel_lila_5", "discard": ["dunkel_orange_4/" + bottom]}
	if players == 2:
		(spec.hands as Array).pop_back()
	spec.merge(extra, true)
	var c := {"flip_surprise": "on"}
	c.merge(over, true)
	return RulesFixture.build(cfg(c), players, spec)


func play_flip(g: MauGame, what: String) -> Array:
	var key := "hell_rot_flip" if g.side == 0 else "dunkel_lila_flip"
	return act(g, 0, {"a": "play", "card": RulesFixture.card(g, 0, key)}, what)


func _init() -> void:
	_each_kind()
	_wild_top()
	_stacking_and_penalty_turn()
	_no_surprise()
	_familie()
	print("RESULT: %d ok" % ok if fails == 0 else "RESULT: %d ok, %d FAIL" % [ok, fails])
	quit(0 if fails == 0 else 1)


func _each_kind() -> void:
	# +1 (dunkel → hell): Nächster zieht 1 und setzt aus
	var g := flip_game({}, "hell_rot_plus1")
	var ev := play_flip(g, "Flip mit +1 unten")
	var order := names(ev)
	check(order.find("flip") < order.find("flip_surprise") and order.find("flip_surprise") < order.find("pending"),
		"+1: Reihenfolge flip, flip_surprise, pending (%s)" % str(order))
	var fs := find_ev(ev, "flip_surprise")
	check(int(fs.get("seat", -1)) == 0 and str(fs.get("face", "")) == "hell_rot_plus1", "+1: Ereignis flip_surprise (%s)" % str(fs))
	check(g.hands[1].size() == 2 and g.current_seat() == 2, "+1: Platz 1 zieht 1 und setzt aus (%d, %d)" % [g.hands[1].size(), g.current_seat()])
	check(names(g.events_for(2, ev)).has("flip_surprise"), "+1: Ereignis öffentlich")
	# Aussetzen
	g = flip_game({}, "hell_rot_aussetzen")
	ev = play_flip(g, "Flip mit Aussetzen unten")
	check(names(ev).has("flip_surprise") and g.hands[1].size() == 1 and g.current_seat() == 2, "Aussetzen: Platz 1 übersprungen (%d)" % g.current_seat())
	# Richtungswechsel: drei Spieler, danach Platz 2
	g = flip_game({}, "hell_rot_richtungswechsel")
	ev = play_flip(g, "Flip mit Richtungswechsel unten")
	check(g.dir == -1 and g.current_seat() == 2 and names(ev).has("reverse"), "Richtungswechsel: Richtung gedreht, Platz 2 dran")
	# Richtungswechsel zu zweit: wie Aussetzen
	g = flip_game({}, "hell_rot_richtungswechsel", 2)
	play_flip(g, "Flip mit Richtungswechsel zu zweit")
	check(g.current_seat() == 0, "Richtungswechsel zu zweit: Flip-Spieler noch einmal dran (%d)" % g.current_seat())
	# +5 (hell → dunkel)
	g = flip_game({}, "dunkel_lila_plus5")
	play_flip(g, "Flip mit +5 unten")
	check(g.hands[1].size() == 6 and g.current_seat() == 2, "+5: Platz 1 zieht 5 und setzt aus")
	# Alle aussetzen: Flip-Spieler ist gleich wieder dran
	g = flip_game({}, "dunkel_lila_alle_aussetzen")
	ev = play_flip(g, "Flip mit Alle aussetzen unten")
	check(names(ev).has("skip_all") and g.current_seat() == 0 and g.phase() == "turn", "Alle aussetzen: Flip-Spieler wieder dran")


func _wild_top() -> void:
	# Wünscher +2 oben: erst Farbe, dann Strafe
	var g := flip_game({}, "hell_wuenscher_plus2")
	var ev := play_flip(g, "Flip mit Wünscher +2 unten")
	check(g.phase() == "color" and g.current_seat() == 0 and not names(ev).has("flip_surprise"), "Wünscher +2: zuerst Farbwahl")
	# Speichern und laden mitten in der Farbwahl
	g = MauGame.from_dict(JSON.parse_string(JSON.stringify(g.to_dict())))
	ev = act(g, 0, {"a": "color", "color": "gelb"}, "Farbe gelb")
	var order := names(ev)
	check(order.find("color") < order.find("flip_surprise") and order.find("flip_surprise") < order.find("pending"),
		"Wünscher +2: Reihenfolge color, flip_surprise, pending (%s)" % str(order))
	check(g.color == "gelb" and g.hands[1].size() == 3 and g.current_seat() == 2, "Wünscher +2: Platz 1 zieht 2, Farbe gelb")
	# Farbjagd oben
	g = flip_game({}, "dunkel_farbjagd")
	play_flip(g, "Flip mit Farbjagd unten")
	check(g.phase() == "color", "Farbjagd: zuerst Farbwahl")
	ev = act(g, 0, {"a": "color", "color": "pink"}, "Farbe pink")
	var got: Array = RulesFixture.hand_keys(g, 1)
	check(names(ev).has("flip_surprise") and names(ev).has("draw") and got.size() >= 2, "Farbjagd: Platz 1 zieht bis Pink (%s)" % str(got))
	check(g.current_seat() == 2, "Farbjagd: Platz 1 setzt aus")
	# Bluff-Modus: kein Anzweifeln, die Strafe wirkt sofort
	g = flip_game({"wild_restriction": "bluff"}, "hell_wuenscher_plus2")
	play_flip(g, "Flip (Bluff-Modus)")
	act(g, 0, {"a": "color", "color": "rot"}, "Farbe rot (Bluff-Modus)")
	check(g.phase() == "turn" and g.current_seat() == 2 and g.hands[1].size() == 3, "Bluff-Modus: kein Anzweifeln (%s)" % g.phase())


func _stacking_and_penalty_turn() -> void:
	# Stapeln: Platz 1 legt +5 drauf, Platz 2 zieht 10
	var g := flip_game({"stacking": "same"}, "dunkel_lila_plus5", 3,
		{"hands": [["hell_rot_flip", "hell_rot_1"], ["hell_gelb_1/dunkel_tuerkis_plus5", "hell_gelb_3"], ["hell_gelb_2"]]})
	play_flip(g, "Flip mit +5 (Stapeln)")
	check(g.current_seat() == 1 and int(g.pending.get("amount", 0)) == 5, "Stapeln: Platz 1 entscheidet über 5")
	act(g, 1, {"a": "play", "card": RulesFixture.card(g, 1, "dunkel_tuerkis_plus5")}, "+5 drauflegen")
	check(g.current_seat() == 2 and int(g.pending.get("amount", 0)) == 10, "Stapeln: Summe 10 bei Platz 2")
	act(g, 2, {"a": "draw"}, "Platz 2 nimmt die Strafe")
	check(g.hands[2].size() == 11 and g.current_seat() == 0, "Stapeln: Platz 2 zieht 10 und setzt aus")
	# penalty_turn = play: Opfer zieht und ist dran
	g = flip_game({"penalty_turn": "play"}, "dunkel_lila_plus5")
	play_flip(g, "Flip mit +5 (penalty_turn play)")
	check(g.hands[1].size() == 6 and g.current_seat() == 1 and g.phase() == "turn", "penalty_turn play: Platz 1 zieht und ist dran")


func _no_surprise() -> void:
	var extras := {"swap_cards": "on", "gamble_cards": "on", "discard_color": "on"}
	for bottom in ["dunkel_lila_flip", "dunkel_lila_tausch", "dunkel_lila_ablegen", "dunkel_lila_7"]:
		var g := flip_game(extras, bottom)
		var ev := play_flip(g, "Flip mit %s unten" % bottom)
		check(not names(ev).has("flip_surprise") and g.current_seat() == 1 and g.phase() == "turn" and not names(ev).has("swap_hands"),
			"%s oben: keine Überraschung (%s)" % [bottom, str(names(ev))])
	for bottom in ["dunkel_wuenscher", "dunkel_gluecksspiel", "dunkel_ablegen_joker"]:
		var g := flip_game(extras, bottom)
		play_flip(g, "Flip mit %s unten" % bottom)
		check(g.phase() == "color", "%s oben: Farbwahl" % bottom)
		var ev := act(g, 0, {"a": "color", "color": "pink"}, "Farbe nach %s" % bottom)
		check(not names(ev).has("flip_surprise") and g.current_seat() == 1 and g.phase() == "turn",
			"%s oben: keine Überraschung (%s, %s)" % [bottom, g.phase(), str(names(ev))])
	# offiziell (aus)
	var g := flip_game({"flip_surprise": "off"}, "dunkel_lila_plus5")
	var ev := play_flip(g, "Flip offiziell")
	check(not names(ev).has("flip_surprise") and g.hands[1].size() == 1 and g.current_seat() == 1, "offiziell: Aktionskarte wirkt nicht")
	# Flip als letzte Karte, Runde endet: keine Überraschung
	g = flip_game({}, "dunkel_lila_plus5", 3, {"hands": [["hell_rot_flip"], ["hell_gelb_1"], ["hell_gelb_2"]]})
	ev = play_flip(g, "Flip als letzte Karte")
	check(names(ev).has("flip") and not names(ev).has("flip_surprise") and g.hands[1].size() == 1, "Rundenende: keine Überraschung")


func _familie() -> void:
	var fam := RuleConfig.preset("familie")
	check(fam.flip_surprise == "on" and fam.wild_restriction == "free" and fam.swap_direction == "play" and fam.gamble_cards == "on"
		and fam.discard_color == "on" and fam.card_count() == 124, "Familie 0.1.4: Werte und 124 Karten")
	check(RuleConfig.new().flip_surprise == "off" and RuleConfig.preset("offiziell").preset_name() == "offiziell", "Standard aus")
	var old := {"round_end": "last", "stacking": "same", "penalty_turn": "play", "wild_restriction": "enforce", "mau_penalty": 1,
		"swap_cards": "on"}
	check(RuleConfig.from_dict(RuleConfig.migrate_dict(old)).preset_name() == "familie", "Hebung: alte Familie (enforce, Teilschlüssel)")
	var full := RuleConfig.from_dict(old).to_dict()
	check(RuleConfig.from_dict(RuleConfig.migrate_dict(full)).equals(fam), "Hebung: alte Familie (vollständig gespeichert)")
	var bluff := full.duplicate()
	bluff["wild_restriction"] = "bluff"
	bluff["wild_counts_for_bluff"] = false
	check(RuleConfig.from_dict(RuleConfig.migrate_dict(bluff)).equals(fam), "Hebung: alte Familie mit bluff → free")
	var custom := full.duplicate()
	custom["hand_size"] = 8
	check(RuleConfig.migrate_dict(custom) == custom, "keine Hebung bei eigenen Regeln")
	var newer := fam.to_dict()
	check(RuleConfig.migrate_dict(newer) == newer, "neue Familie bleibt")
	check(RuleConfig.migrate_dict({}) == {}, "offiziell bleibt")
	check(RulesText.card_help("hell_rot_flip", fam).size() > 0 and " ".join(RulesText.card_help("hell_rot_flip", fam)).contains("Flip-Überraschung")
		and not " ".join(RulesText.card_help("hell_rot_flip", RuleConfig.new())).contains("Überraschung"), "Kartenhilfe Flip")
	check(" ".join(fam.describe()).contains("Flip-Überraschung") and not " ".join(RuleConfig.new().describe()).contains("Überraschung"), "Kurzfassung")
	var ov := ""
	for p in RulesText.overview(fam):
		ov += str(p.text)
	check(ov.contains("Flip-Überraschung"), "Regelübersicht")
