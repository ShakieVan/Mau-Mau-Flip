extends SceneTree
# Hausregel „Flip dreht nur die gelegte Karte“ (flip_mode, Beta 1.0.2): offiziell ("pile") wendet der Flip die ganze Ablage,
# bei "card" liegt oben die andere Seite der Flip-Karte, die übrige Ablage bleibt in ihrer Reihenfolge darunter und zeigt im
# Ablage-Protokoll die Seite, mit der sie lag. Geprüft: Oberkarte, Reihenfolge, discard_log, Flip-Überraschung, Speichern und
# Laden, Mischen, Familie, Hebung der Familie 1.0.1 in RuleConfig.migrate_dict, Texte.

var ok := 0
var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		ok += 1
	else:
		fails += 1
		print("FAIL: " + what)


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


func log_faces(g: MauGame) -> Array:
	var out: Array = []
	for e in g.view_for(1).discard_log:
		out.append(str(e.f))
	return out


# Platz 0 legt den Flip (andere Seite: dunkel_pink_plus5 bzw. dunkel_pink_7); unten liegt hell_blau_4/dunkel_lila_plus5.
func flip_game(mode: String, back := "dunkel_pink_7", surprise := "off") -> MauGame:
	var c := RuleConfig.new()
	c.apply_dict({"flip_mode": mode, "flip_surprise": surprise})
	return RulesFixture.build(c, 3, {"hands": [["hell_rot_flip/" + back, "hell_rot_1"], ["hell_gelb_1"], ["hell_gelb_2"]],
		"top": "hell_rot_5/dunkel_orange_3", "discard": ["hell_blau_4/dunkel_lila_plus5"]})


func play_flip(g: MauGame, what: String) -> Array:
	return act(g, 0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_rot_flip")}, what)


func _init() -> void:
	_pile()
	_card()
	_surprise()
	_save_and_shuffle()
	_familie()
	print("RESULT: %d ok" % ok if fails == 0 else "RESULT: %d ok, %d FAIL" % [ok, fails])
	quit(0 if fails == 0 else 1)


func _pile() -> void:
	var g := flip_game("pile")
	var flip_id := RulesFixture.card(g, 0, "hell_rot_flip")
	var bottom := int(g.discard[0])                # hell_blau_4 (unter der Startkarte)
	play_flip(g, "Flip offiziell")
	check(RulesFixture.top_key(g) == "dunkel_lila_plus5" and int(g.discard.back()) == bottom, "offiziell: unterste Karte oben (%s)" % RulesFixture.top_key(g))
	check(int(g.discard[0]) == flip_id, "offiziell: Flip-Karte ganz unten")
	var lf := log_faces(g)
	check(lf.slice(lf.size() - 3) == ["dunkel_pink_7", "dunkel_orange_3", "dunkel_lila_plus5"], "offiziell: Protokoll ganz gewendet (%s)" % str(lf.slice(lf.size() - 3)))
	check(g.side == 1 and g.current_seat() == 1, "offiziell: dunkle Seite, Platz 1 dran")


func _card() -> void:
	var g := flip_game("card")
	var flip_id := RulesFixture.card(g, 0, "hell_rot_flip")
	var before := g.discard.duplicate()
	var hand1 := RulesFixture.hand_keys(g, 1)
	play_flip(g, "Flip nur die Karte")
	before.append(flip_id)
	check(g.discard == before, "card: Reihenfolge der Ablage bleibt, Flip oben")
	check(RulesFixture.top_key(g) == "dunkel_pink_7" and g.color == "pink" and g.side == 1, "card: andere Seite der Flip-Karte oben (%s)" % RulesFixture.top_key(g))
	check(RulesFixture.hand_keys(g, 1) != hand1 and str(RulesFixture.hand_keys(g, 1)[0]).begins_with("dunkel"), "card: Hände gewendet")
	var lf := log_faces(g)
	check(lf.slice(lf.size() - 3) == ["hell_blau_4", "hell_rot_5", "dunkel_pink_7"], "card: Protokoll zeigt die gelegten Seiten (%s)" % str(lf.slice(lf.size() - 3)))
	check(lf == log_faces(g) and g.view_for(0).discard_log == g.view_for(2).discard_log, "card: Protokoll für alle gleich")
	# Weiterlegen auf der dunklen Seite, dann zurückflippen: die dunkle Karte bleibt dunkel, die hellen hell
	var g2 := RulesFixture.build(RuleConfig.from_dict({"flip_mode": "card"}), 2, {"side": "dunkel",
		"hands": [["dunkel_pink_1", "dunkel_pink_flip/hell_gruen_8", "dunkel_pink_2"], ["dunkel_pink_3", "dunkel_lila_6"]],
		"top": "dunkel_pink_5/hell_blau_9"})
	act(g2, 0, {"a": "play", "card": RulesFixture.card(g2, 0, "dunkel_pink_1")}, "dunkel 1")
	act(g2, 1, {"a": "play", "card": RulesFixture.card(g2, 1, "dunkel_pink_3")}, "dunkel 3")
	act(g2, 0, {"a": "play", "card": RulesFixture.card(g2, 0, "dunkel_pink_flip")}, "Flip zurück")
	var lf2 := log_faces(g2)
	check(lf2.slice(lf2.size() - 4) == ["dunkel_pink_5", "dunkel_pink_1", "dunkel_pink_3", "hell_gruen_8"] and g2.color == "gruen",
		"card: zweiter Flip (%s)" % str(lf2.slice(lf2.size() - 4)))


func _surprise() -> void:
	# Überraschung wirkt auf die andere Seite der Flip-Karte, nicht auf die unterste Ablagekarte
	var g := flip_game("card", "dunkel_pink_plus5", "on")
	var ev := play_flip(g, "card: Flip mit +5 auf der Rückseite")
	check(names(ev).has("flip_surprise") and g.hands[1].size() == 6 and g.current_seat() == 2, "card: Überraschung +5 der Flip-Rückseite")
	g = flip_game("card", "dunkel_pink_7", "on")
	ev = play_flip(g, "card: Zahl auf der Rückseite, +5 ganz unten")
	check(not names(ev).has("flip_surprise") and g.hands[1].size() == 1 and g.current_seat() == 1, "card: unterste +5 wirkt nicht")
	g = flip_game("pile", "dunkel_pink_7", "on")
	ev = play_flip(g, "offiziell: +5 ganz unten")
	check(names(ev).has("flip_surprise") and g.hands[1].size() == 6, "offiziell: unterste +5 wirkt")


func _save_and_shuffle() -> void:
	var g := flip_game("card")
	play_flip(g, "Flip vor dem Speichern")
	var d := g.to_dict()
	check(d.has("dside"), "card: Spielstand mit dside")
	var g2 := MauGame.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(g2.view_for(1).discard_log == g.view_for(1).discard_log and g2.dside == g.dside,
		"card: Protokoll nach Laden gleich")
	check(not flip_game("pile").to_dict().has("dside"), "offiziell: Spielstand ohne dside")
	# Mischen: nur die oberste bleibt, danach Kartenerhaltung
	var c := RuleConfig.from_dict({"flip_mode": "card"})
	var g3 := RulesFixture.build(c, 2, {"hands": [["hell_rot_flip/dunkel_pink_7", "hell_rot_1"], ["hell_gelb_1", "hell_gelb_2"]],
		"top": "hell_rot_5", "rest": "discard"})
	play_flip(g3, "Flip bei leerem Nachziehstapel")
	var ev := act(g3, 1, {"a": "draw"}, "Ziehen löst Mischen aus")
	check(names(ev).has("shuffle") and g3.discard.size() == 1 and RulesFixture.top_key(g3) == "dunkel_pink_7", "card: Mischen, Flip bleibt oben")
	check(RulesFixture.card_check(g3) == "", "card: Kartenerhaltung nach Mischen (%s)" % RulesFixture.card_check(g3))
	check(log_faces(g3) == ["dunkel_pink_7"], "card: Protokoll nach Mischen")


func _familie() -> void:
	var fam := RuleConfig.preset("familie")
	check(fam.flip_mode == "card" and RuleConfig.new().flip_mode == "pile" and fam.preset_name() == "familie", "Familie: card, Standard pile")
	var old := fam.to_dict()
	old.erase("flip_mode")                            # Familie 1.0.1, so gespeichert
	check(RuleConfig.from_dict(RuleConfig.migrate_dict(old)).equals(fam), "Hebung: Familie 1.0.1 → card")
	var chosen := fam.to_dict()
	chosen["flip_mode"] = "pile"                      # bewusst gewählt: bleibt
	check(RuleConfig.migrate_dict(chosen) == chosen, "keine Hebung bei gewähltem pile")
	var custom := old.duplicate()
	custom["hand_size"] = 8
	check(RuleConfig.migrate_dict(custom) == custom, "keine Hebung bei eigenen Regeln")
	check(RuleConfig.migrate_dict({}) == {}, "offiziell bleibt")
	var help_card := " ".join(RulesText.card_help("hell_rot_flip", fam))
	var help_pile := " ".join(RulesText.card_help("hell_rot_flip", RuleConfig.new()))
	check(help_card.contains("andere Seite dieses Flips") and help_pile.contains("bisher unterste"), "Kartenhilfe je Modus")
	check(" ".join(fam.describe()).contains("nur die gelegte Karte") and not " ".join(RuleConfig.new().describe()).contains("nur die gelegte"), "Kurzfassung")
	var ov := ""
	for p in RulesText.overview(fam):
		ov += str(p.text)
	check(ov.contains("nur sich selbst") and not ov.contains("bisher unterste"), "Regelübersicht card")
