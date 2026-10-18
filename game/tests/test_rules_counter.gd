extends "res://tests/test_rules_views.gd"
# Hausregel „Kontern“ (counter_round = "on", Beta 1.6.11, Nutzerwunsch 16.10.2026, docs/module/kontern.md): Wer keine Karten mehr
# hat, wartet in der Konter-Runde; fertig erst, wenn der Zug wieder bei ihm ankäme oder er übersprungen wird; wer ihm vorher Karten
# gibt, kontert. Gebaute Fälle: Grundablauf (erster fertig / bis zum Letzten), Kontern mit +1, +5, Wünscher +2, Farbjagd (auch mit
# Stapeln und penalty_turn = play), Aussetzen, Alle aussetzen (fremd und als eigene letzte Karte), Richtungswechsel (verkürzt und
# verlängert), zwei Wartende gleichzeitig (beide fertig in Reihenfolge, einer gekontert), Kartentausch (Wartender tauscht mit, leere
# Hand wandert; als letzte Karte ohne den Leger; zu zweit; gegen den Uhrzeigersinn), Flip-Überraschung (+5 auf den Wartenden, eigener
# Flip als letzte Karte, Joker oben, flip_last_card = ignore), Glücksspiel (leere Hand nach 0, Glücksspiel als letzte Karte), Farbe
# mit ablegen, Anzweifeln (bluff), Mau und Erwischen, Hinweise und Sicht, Speichern/Laden, Dazuholen/Entfernen, Statistik, Regeln und
# Texte (Familie, Hebung alter Familie-Sätze, Übersicht, Kartenhilfe, Regelauswahl, Browser), Bots (der Vorgänger kontert).
# Danach die Zufallsprüfungen aus test_rules_views.gd mit Kontern (JSON, Lecktest, Hinweise = Regeln, Rundreise; counter_mode() =
# true) und ein Bot-Dauerlauf mit allen Hausregeln (Invarianten nach jeder Aktion, jede Partie endet).

const COUNTER_GAMES := 300
const COUNTER_STEP_LIMIT := 4000
# Zufallsprüfungen aus test_rules_views.gd mit Kontern: etwa halb so viele Partien wie dort (die Sicht ist dieselbe)
const COUNTER_COUNTS := {"RULES_JSON_GAMES": 6, "RULES_LEAK_GAMES": 8, "RULES_HINT_GAMES": 4, "RULES_TRIP_GAMES": 10}

var cstats := {}


func counts() -> Dictionary:
	return COUNTER_COUNTS


func counter_mode() -> bool:
	return true


func _initialize() -> void:
	_c_basic()
	_c_draw_cards()
	_c_skip()
	_c_skip_all()
	_c_reverse()
	_c_two_waiting()
	_c_swap()
	_c_flip_surprise()
	_c_gamble()
	_c_discard()
	_c_bluff()
	_c_mau()
	_c_save_load()
	_c_seats()
	_c_stats()
	_c_rules_and_texts()
	_c_bots()
	_c_off_unchanged()
	var t0 := Time.get_ticks_msec()
	_json_views()
	_leak_runs()
	_hint_consistency()
	_round_trip()
	print("Zufallsprüfungen mit Kontern: %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	_c_bot_run()
	print("Laufzeit seit Godot-Start: %.1f s" % (Time.get_ticks_msec() / 1000.0))
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)


# --- Hilfen ---

func ccfg(over := {}) -> RuleConfig:
	var d := {"counter_round": "on"}
	d.merge(over, true)
	return RuleConfig.from_dict(d)


func make(spec: Dictionary, over := {}, n := 3) -> MauGame:
	var g := RulesFixture.build(ccfg(over), n, spec)
	check(RulesFixture.card_check(g) == "", "Aufbau: " + RulesFixture.card_check(g))
	return g


func act(g: MauGame, seat: int, action: Dictionary, msg: String) -> Array:
	var r := g.apply(seat, action)
	check(bool(r.ok), "%s (abgelehnt: %s)" % [msg, r.reason])
	var inv := RulesFixture.invariants(g)
	check(inv == "", "%s: %s" % [msg, inv])
	return r.events


# Zug abgeben: ziehen und – passt die gezogene Karte – behalten. Gibt alle Ereignisse zurück.
func _pass_turn(g: MauGame, seat: int, msg: String) -> Array:
	var ev := act(g, seat, {"a": "draw"}, msg)
	if g.current == seat and g.phase() == "drawn":
		ev = ev + act(g, seat, {"a": "keep"}, msg + " (behalten)")
	return ev


func play(g: MauGame, seat: int, key: String, msg: String, color := "") -> Array:
	var id := RulesFixture.card(g, seat, key)
	check(id >= 0, "%s: Karte %s auf der Hand von %d" % [msg, key, seat])
	var a := {"a": "play", "card": id}
	if color != "":
		a["color"] = color
	return act(g, seat, a, msg)


func names(ev: Array) -> Array:
	var out: Array = []
	for e in ev:
		out.append(str(e.get("e", "")))
	return out


# Index des ersten Ereignisses e (mit Platz seat, -9 = egal), sonst -1.
func at(ev: Array, e: String, seat := -9) -> int:
	for i in ev.size():
		if str(ev[i].get("e", "")) == e and (seat == -9 or int(ev[i].get("seat", -1)) == seat):
			return i
	return -1


func find(ev: Array, e: String, seat := -9) -> Dictionary:
	var i := at(ev, e, seat)
	return ev[i] if i >= 0 else {}


func hint(g: MauGame, seat: int) -> String:
	return str(g.view_for(seat).hints.text)


# Lage „Anna (0) hat eben ihre letzte Karte gelegt“: 3 Plätze, Hände 1 und 2 frei wählbar; Ablage rot.
func waiting_game(h1: Array, h2: Array, over := {}, extra := {}) -> MauGame:
	var spec := {"hands": [["hell_rot_7"], h1, h2], "top": "hell_rot_5", "draw": ["hell_gruen_9", "hell_gruen_8", "hell_blau_9"]}
	spec.merge(extra, true)
	var g := make(spec, over, 3)
	var ev := play(g, 0, "hell_rot_7", "Anna legt die letzte Karte")
	check(at(ev, "counter_open", 0) >= 0 and at(ev, "finish") < 0, "letzte Karte: Konter-Runde statt fertig (%s)" % str(names(ev)))
	check(g.counter_wait == [0] and int(g.place[0]) == 0 and g.current == 1, "Anna wartet, Ben ist dran")
	return g


# --- Gebaute Fälle ---

func _c_basic() -> void:
	# Erster fertig gewinnt: keiner kontert → Anna ist fertig, wenn der Zug wieder bei ihr ankäme
	var g := waiting_game(["hell_blau_1", "hell_blau_2"], ["hell_gelb_1", "hell_gelb_2"])
	var v0 := g.view_for(0)
	var v1 := g.view_for(1)
	check(v0.counter == {"wait": [0], "done": -1} and bool(v0.players[0].counter) and not bool(v0.players[1].counter),
		"Sicht: counter.wait und players[].counter (%s)" % str(v0.get("counter")))
	check(hint(g, 0).contains("Du hast keine Karten mehr – kontert keiner, bist du fertig."), "Hinweis für Anna: " + hint(g, 0))
	check(v1.hints.text.begins_with("Anna hat keine Karten mehr – wer kontert?"), "Hinweis für Ben: " + str(v1.hints.text))
	check(hint(g, 2).contains("Anna hat keine Karten mehr – wer kontert?") and hint(g, -1).contains("wer kontert?"),
		"Hinweis für Cleo und Zuschauer")
	check(I18n.render(v1.hints.lt, false) == str(v1.hints.text), "Bausteine ergeben den deutschen Hinweis")
	check(not bool(v0.hints.can_mau) and (v0.hints.playable as Array).is_empty() and not bool(v0.hints.can_draw), "Anna hat nichts zu tun")
	check(MauBot.choose(v0, 1, 2).is_empty(), "Bot auf Annas Platz tut nichts")
	check(not bool(g.apply(0, {"a": "draw"}).ok), "Anna darf nicht ziehen")
	act(g, 1, {"a": "draw"}, "Ben zieht (passt nicht)")
	check(g.current == 2 and g.counter_wait == [0], "Cleo dran, Anna wartet weiter")
	var ev := act(g, 2, {"a": "draw"}, "Cleo zieht (passt nicht)")
	var fin := find(ev, "finish", 0)
	check(not fin.is_empty() and bool(fin.get("survived", false)) and int(fin.place) == 1, "Anna ist fertig (survived) %s" % str(names(ev)))
	check(at(ev, "finish", 0) < at(ev, "round_over") and g.phase() == "round_over" and int(g.result.ranking[0]) == 0,
		"Runde vorbei, Anna gewinnt")
	check(g.counter_wait.is_empty() and hint(g, 1).contains("Anna gewinnt die Runde."), "nach der Runde keine Wartenden mehr")
	# Bis zum Letzten: Anna fertig mit Platz 1, die anderen spielen weiter; Hinweis „Anna ist fertig!“ bis zur nächsten Handlung
	g = waiting_game(["hell_blau_1", "hell_blau_2"], ["hell_gelb_1", "hell_gelb_2"], {"round_end": "last"})
	act(g, 1, {"a": "draw"}, "last: Ben zieht")
	ev = act(g, 2, {"a": "draw"}, "last: Cleo zieht")
	check(int(g.place[0]) == 1 and g.phase() == "turn" and g.current == 1 and g.counter_done == 0, "last: Anna Platz 1, Ben dran")
	check(hint(g, 1).begins_with("Anna ist fertig!") and hint(g, 2).begins_with("Anna ist fertig!"), "Hinweis „Anna ist fertig!“: " + hint(g, 1))
	check(hint(g, 0).contains("Du bist fertig (Platz 1).") and not hint(g, 0).contains("Anna ist fertig"), "Anna selbst: " + hint(g, 0))
	check(int(g.view_for(1).counter.done) == 0, "Sicht: counter.done")
	check(not bool(g.apply(1, {"a": "keep"}).ok) and g.counter_done == 0, "abgelehnte Aktion lässt den Hinweis stehen")
	act(g, 1, {"a": "draw"}, "last: Ben zieht noch einmal")
	check(g.counter_done == -1 and not hint(g, 2).contains("ist fertig!"), "Hinweis „fertig!“ nach der nächsten Handlung weg")


func _c_draw_cards() -> void:
	# +1 vom Vorgänger (Cleo): Anna zieht, spielt weiter; offiziell setzt sie danach aus
	var g := waiting_game(["hell_rot_8", "hell_blau_1"], ["hell_rot_plus1", "hell_gelb_1"])
	act(g, 1, {"a": "play", "card": RulesFixture.card(g, 1, "hell_rot_8")}, "Ben legt")
	var ev := play(g, 2, "hell_rot_plus1", "Cleo kontert mit +1")
	check(at(ev, "draw", 0) >= 0 and at(ev, "countered", 0) > at(ev, "draw", 0) and at(ev, "finish") < 0, "+1: gezogen, dann gekontert %s" % str(names(ev)))
	check(g.counter_wait.is_empty() and (g.hands[0] as Array).size() == 1 and int(g.place[0]) == 0, "+1: Anna hat 1 Karte und spielt")
	check(at(ev, "skip", 0) >= 0 and g.current == 1, "+1 offiziell: Anna setzt aus, Ben ist dran")
	check(not g.view_for(0).players[0].counter and not hint(g, 1).contains("wer kontert"), "nach dem Kontern kein Konter-Hinweis")
	# penalty_turn = play: Anna ist gleich dran
	g = waiting_game(["hell_rot_8", "hell_blau_1"], ["hell_rot_plus1", "hell_gelb_1"], {"penalty_turn": "play"})
	act(g, 1, {"a": "play", "card": RulesFixture.card(g, 1, "hell_rot_8")}, "play: Ben legt")
	ev = play(g, 2, "hell_rot_plus1", "play: Cleo kontert")
	check(g.current == 0 and g.phase() == "turn" and (g.hands[0] as Array).size() == 1 and g.counter_wait.is_empty(), "play: Anna ist dran")
	# Stapeln: Ohne Karten gibt es nichts zum Drauflegen – Anna zieht sofort
	g = waiting_game(["hell_rot_8", "hell_blau_1"], ["hell_rot_plus1", "hell_gelb_1"], {"stacking": "same"})
	act(g, 1, {"a": "play", "card": RulesFixture.card(g, 1, "hell_rot_8")}, "same: Ben legt")
	ev = play(g, 2, "hell_rot_plus1", "same: Cleo kontert")
	check(g.pending.is_empty() and g.current == 1 and (g.hands[0] as Array).size() == 1, "same: Anna zieht sofort, kein Stapelzug")
	# Stapelsumme: Ben legt +1 auf Cleo? Hier: Ben +1 auf Cleo, Cleo legt +1 drauf → Summe 2 auf Anna
	g = waiting_game(["hell_rot_plus1", "hell_blau_1"], ["hell_gelb_plus1", "hell_gelb_1"], {"stacking": "same"})
	play(g, 1, "hell_rot_plus1", "same: Ben +1 auf Cleo")
	check(g.current == 2 and int(g.pending.amount) == 1, "same: Cleo darf stapeln")
	play(g, 2, "hell_gelb_plus1", "same: Cleo stapelt auf Anna")
	check((g.hands[0] as Array).size() == 2 and g.counter_wait.is_empty(), "same: Anna zieht die Summe 2")
	# Wünscher +2
	g = waiting_game(["hell_rot_8", "hell_blau_1"], ["hell_wuenscher_plus2", "hell_gelb_1"])
	act(g, 1, {"a": "play", "card": RulesFixture.card(g, 1, "hell_rot_8")}, "+2: Ben legt")
	ev = play(g, 2, "hell_wuenscher_plus2", "+2: Cleo kontert", "gelb")
	check((g.hands[0] as Array).size() == 2 and g.counter_wait.is_empty() and g.color == "gelb", "Wünscher +2: Anna zieht 2")
	# Dunkle Seite: +5 und Farbjagd
	var spec := {"side": "dunkel", "hands": [["dunkel_pink_7"], ["dunkel_pink_8", "dunkel_lila_1"], ["dunkel_pink_plus5", "dunkel_orange_1"]],
		"top": "dunkel_pink_5"}
	g = make(spec)
	play(g, 0, "dunkel_pink_7", "dunkel: Anna legt die letzte Karte")
	play(g, 1, "dunkel_pink_8", "dunkel: Ben legt")
	play(g, 2, "dunkel_pink_plus5", "dunkel: Cleo kontert mit +5")
	check((g.hands[0] as Array).size() == 5 and g.counter_wait.is_empty() and g.current == 1, "+5: Anna zieht 5")
	spec = {"side": "dunkel", "hands": [["dunkel_pink_7"], ["dunkel_pink_8", "dunkel_lila_1"], ["dunkel_farbjagd", "dunkel_orange_1"]],
		"top": "dunkel_pink_5", "draw": ["dunkel_lila_3", "dunkel_pink_2", "dunkel_tuerkis_2"]}
	g = make(spec)
	play(g, 0, "dunkel_pink_7", "Jagd: Anna legt die letzte Karte")
	play(g, 1, "dunkel_pink_8", "Jagd: Ben legt")
	var ev2 := play(g, 2, "dunkel_farbjagd", "Jagd: Cleo kontert", "tuerkis")
	check(RulesFixture.hand_keys(g, 0) == ["dunkel_lila_3", "dunkel_pink_2", "dunkel_tuerkis_2"] and at(ev2, "countered", 0) >= 0,
		"Farbjagd: Anna zieht bis Türkis (%s)" % str(RulesFixture.hand_keys(g, 0)))
	# Ziehkarte als eigene letzte Karte: der Nächste zieht, Anna wartet trotzdem
	g = make({"hands": [["hell_rot_plus1"], ["hell_blau_1", "hell_blau_2"], ["hell_gelb_1"]], "top": "hell_rot_5"})
	ev = play(g, 0, "hell_rot_plus1", "+1 als letzte Karte")
	check((g.hands[1] as Array).size() == 3 and g.counter_wait == [0] and at(ev, "round_over") < 0 and g.current == 2,
		"+1 als letzte Karte: Ben zieht und setzt aus, Anna wartet, Cleo ist dran")


func _c_skip() -> void:
	# Aussetzen vom Vorgänger: übersprungen = Konter-Runde überstanden
	var g := waiting_game(["hell_rot_8", "hell_blau_1"], ["hell_rot_aussetzen", "hell_gelb_1"])
	act(g, 1, {"a": "play", "card": RulesFixture.card(g, 1, "hell_rot_8")}, "Ben legt")
	var ev := play(g, 2, "hell_rot_aussetzen", "Cleo setzt Anna aus")
	check(at(ev, "skip", 0) >= 0 and at(ev, "finish", 0) > at(ev, "skip", 0) and bool(find(ev, "finish", 0).get("survived", false)),
		"Aussetzen: Anna übersprungen und fertig (%s)" % str(names(ev)))
	check(g.phase() == "round_over" and int(g.result.ranking[0]) == 0, "erster fertig: Runde vorbei")
	# Bis zum Letzten, 4 Plätze: danach ist Ben dran
	g = make({"hands": [["hell_rot_7"], ["hell_rot_8", "hell_blau_1"], ["hell_rot_9", "hell_blau_2"], ["hell_rot_aussetzen", "hell_gelb_1"]],
		"top": "hell_rot_5"}, {"round_end": "last"}, 4)
	play(g, 0, "hell_rot_7", "4: Anna letzte Karte")
	play(g, 1, "hell_rot_8", "4: Ben legt")
	play(g, 2, "hell_rot_9", "4: Cleo legt")
	ev = play(g, 3, "hell_rot_aussetzen", "4: Dani setzt Anna aus")
	check(int(g.place[0]) == 1 and g.current == 1 and g.phase() == "turn", "4 Plätze: Anna Platz 1, Ben dran")
	# Aussetzen als eigene letzte Karte (zu zweit). Beta 1.6.14 (Nutzerbefund 18.10.2026: „der andere Spieler hätte noch die Möglichkeit
	# haben müssen, eine Karte zu ziehen“): Ben setzt nicht aus, sonst hätte er keinen Zug mehr zum Kontern (bis 1.6.13: Anna gleich fertig)
	g = make({"hands": [["hell_rot_aussetzen"], ["hell_rot_plus1", "hell_blau_1"]], "top": "hell_rot_5"}, {}, 2)
	ev = play(g, 0, "hell_rot_aussetzen", "zu zweit: Aussetzen als letzte Karte")
	check(at(ev, "counter_open", 0) >= 0 and at(ev, "skip") < 0 and at(ev, "finish") < 0 and g.current == 1 and g.phase() == "turn"
		and g.counter_wait == [0], "zu zweit: Ben setzt nicht aus und darf kontern (%s)" % str(names(ev)))
	ev = play(g, 1, "hell_rot_plus1", "zu zweit: Ben kontert mit +1")
	check(at(ev, "countered", 0) >= 0 and g.counter_wait.is_empty() and (g.hands[0] as Array).size() == 1, "zu zweit: Anna gekontert (%s)" % str(names(ev)))
	# … oder Ben kann nicht kontern: Er zieht, der Zug kommt zu Anna zurück → fertig, Runde vorbei
	g = make({"hands": [["hell_rot_aussetzen"], ["hell_blau_1", "hell_blau_2"]], "top": "hell_rot_5"}, {}, 2)
	play(g, 0, "hell_rot_aussetzen", "zu zweit: Aussetzen als letzte Karte (ohne Konter)")
	ev = _pass_turn(g, 1, "zu zweit: Ben zieht")
	check(at(ev, "finish", 0) >= 0 and g.phase() == "round_over", "zu zweit: Ben kontert nicht, Anna fertig (%s)" % str(names(ev)))
	# Richtungswechsel als eigene letzte Karte zu zweit (wirkt wie Aussetzen): Ben ist ebenso noch dran
	g = make({"hands": [["hell_rot_richtungswechsel"], ["hell_blau_1", "hell_blau_2"]], "top": "hell_rot_5"},
		{"two_player_reverse_skips": true}, 2)
	ev = play(g, 0, "hell_rot_richtungswechsel", "zu zweit: Richtungswechsel als letzte Karte")
	check(at(ev, "skip") < 0 and at(ev, "finish") < 0 and g.current == 1 and g.counter_wait == [0],
		"zu zweit: nach Richtungswechsel als letzter Karte ist Ben dran (%s)" % str(names(ev)))
	# Nutzerbefund nachgestellt: zu dritt, Cleo ist schon fertig, Anna legt Aussetzen als letzte Karte → Ben ist noch dran
	g = make({"hands": [["hell_rot_aussetzen"], ["hell_blau_1", "hell_blau_2"], []], "top": "hell_rot_5", "finished": [2]},
		{"round_end": "last"})
	ev = play(g, 0, "hell_rot_aussetzen", "zu dritt, einer fertig: Aussetzen als letzte Karte")
	check(g.phase() == "turn" and g.current == 1 and g.counter_wait == [0], "zu dritt, einer fertig: Ben darf noch kontern (%s)" % str(names(ev)))
	check(RulesFixture.invariants(g) == "", "zu dritt, einer fertig: " + RulesFixture.invariants(g))
	# zu dritt (alle spielen): Aussetzen als letzte Karte setzt Ben aus, Cleo ist dran – wie bisher
	g = make({"hands": [["hell_rot_aussetzen"], ["hell_blau_1"], ["hell_gelb_1"]], "top": "hell_rot_5"})
	ev = play(g, 0, "hell_rot_aussetzen", "zu dritt: Aussetzen als letzte Karte")
	check(at(ev, "skip", 1) >= 0 and g.current == 2, "zu dritt: Ben setzt aus, Cleo dran (%s)" % str(names(ev)))
	# Spielstand: Der Merker überlebt to_dict/from_dict (Gastgeber-Übergabe), ohne Kontern fehlt er
	g = make({"hands": [[], ["hell_blau_1", "hell_blau_2"], ["hell_gelb_1"]], "top": "hell_rot_5", "counter": [0]})
	g.counter_guard = [0]                    # wie mitten in einer mehrteiligen Aktion (Farbwahl, Ablege-Auswahl)
	var dd := g.to_dict()
	check(((dd.get("counter", {}) as Dictionary).get("guard", []) as Array) == [0], "Spielstand: Merker gespeichert (%s)" % str(dd.get("counter", {})))
	var g2 := MauGame.from_dict(dd)
	check(g2.counter_guard == [0], "Spielstand: Merker geladen")
	dd = g2.to_dict()
	(dd["counter"] as Dictionary)["guard"] = [1]
	check(MauGame.from_dict(dd).counter_guard.is_empty(), "Spielstand: Merker nur für Wartende")


func _c_skip_all() -> void:
	var base := {"side": "dunkel", "top": "dunkel_pink_5"}
	# Alle aussetzen von Ben: Anna wartet, wird übersprungen → fertig, Ben noch einmal dran
	var spec := base.duplicate()
	spec.hands = [["dunkel_pink_7"], ["dunkel_pink_alle_aussetzen", "dunkel_lila_1"], ["dunkel_orange_1"], ["dunkel_orange_2"]]
	var g := make(spec, {"round_end": "last"}, 4)
	play(g, 0, "dunkel_pink_7", "Anna letzte Karte")
	var ev := play(g, 1, "dunkel_pink_alle_aussetzen", "Ben: Alle aussetzen")
	check(at(ev, "finish", 0) > at(ev, "skip_all") and int(g.place[0]) == 1 and g.current == 1, "Alle aussetzen: Anna fertig, Ben wieder dran")
	g = make(spec, {}, 4)
	play(g, 0, "dunkel_pink_7", "first: Anna letzte Karte")
	play(g, 1, "dunkel_pink_alle_aussetzen", "first: Alle aussetzen")
	check(g.phase() == "round_over" and int(g.result.ranking[0]) == 0, "first: Runde vorbei, Anna gewinnt")
	# Als eigene letzte Karte (Beta 1.6.14): Anna wartet, der Nächste ist trotzdem dran und kann kontern (bis 1.6.13: Anna gleich fertig)
	spec = base.duplicate()
	spec.hands = [["dunkel_pink_alle_aussetzen"], ["dunkel_lila_1"], ["dunkel_orange_1"], ["dunkel_orange_2"]]
	g = make(spec, {"round_end": "last"}, 4)
	ev = play(g, 0, "dunkel_pink_alle_aussetzen", "Alle aussetzen als letzte Karte")
	check(at(ev, "counter_open", 0) < at(ev, "skip_all") and at(ev, "finish") < 0 and int(g.place[0]) == 0 and g.counter_wait == [0]
		and g.current == 1, "letzte Karte Alle aussetzen: Anna wartet, Ben dran (%s)" % str(names(ev)))
	# Zwei Wartende, Cleo legt Alle aussetzen: beide fertig in ihrer Reihenfolge
	spec = base.duplicate()
	spec.hands = [["dunkel_pink_7"], ["dunkel_pink_8"], ["dunkel_pink_alle_aussetzen", "dunkel_lila_2"], ["dunkel_orange_2"]]
	g = make(spec, {"round_end": "last"}, 4)
	play(g, 0, "dunkel_pink_7", "zwei: Anna")
	play(g, 1, "dunkel_pink_8", "zwei: Ben")
	check(g.counter_wait == [0, 1], "zwei Wartende")
	ev = play(g, 2, "dunkel_pink_alle_aussetzen", "zwei: Cleo Alle aussetzen")
	check(int(g.place[0]) == 1 and int(g.place[1]) == 2 and at(ev, "finish", 0) < at(ev, "finish", 1) and g.current == 2,
		"zwei: Anna 1., Ben 2., Cleo wieder dran")


func _c_reverse() -> void:
	# Verkürzt: Ben dreht die Richtung, der Zug geht zu Anna zurück → fertig, danach Dani (Richtung −1)
	var g := make({"hands": [["hell_rot_7"], ["hell_rot_richtungswechsel", "hell_blau_1"], ["hell_gelb_1"], ["hell_gelb_2"]], "top": "hell_rot_5"},
		{"round_end": "last"}, 4)
	play(g, 0, "hell_rot_7", "Anna letzte Karte")
	var ev := play(g, 1, "hell_rot_richtungswechsel", "Ben Richtungswechsel")
	check(at(ev, "finish", 0) > at(ev, "reverse") and int(g.place[0]) == 1 and g.current == 3 and g.dir == -1,
		"Richtungswechsel verkürzt: Anna fertig, Dani dran (%s)" % str(names(ev)))
	# Verlängert: Cleo dreht, Ben ist noch einmal dran und kontert mit +1
	g = make({"hands": [["hell_rot_7"], ["hell_rot_8", "hell_rot_plus1", "hell_blau_1"], ["hell_rot_richtungswechsel", "hell_blau_2"],
		["hell_gelb_1"]], "top": "hell_rot_5"}, {"round_end": "last"}, 4)
	play(g, 0, "hell_rot_7", "lang: Anna letzte Karte")
	play(g, 1, "hell_rot_8", "lang: Ben legt")
	play(g, 2, "hell_rot_richtungswechsel", "lang: Cleo dreht")
	check(g.current == 1 and g.counter_wait == [0] and hint(g, 1).begins_with("Anna hat keine Karten mehr – wer kontert?"),
		"lang: Ben noch einmal dran, Anna wartet")
	ev = play(g, 1, "hell_rot_plus1", "lang: Ben kontert")
	check((g.hands[0] as Array).size() == 1 and g.counter_wait.is_empty() and at(ev, "countered", 0) >= 0, "lang: Anna gekontert")
	# Zu zweit wirkt der Richtungswechsel wie Aussetzen: Anna fertig
	g = make({"hands": [["hell_rot_7"], ["hell_rot_richtungswechsel", "hell_blau_1"]], "top": "hell_rot_5"}, {}, 2)
	play(g, 0, "hell_rot_7", "2: Anna letzte Karte")
	play(g, 1, "hell_rot_richtungswechsel", "2: Ben dreht")
	check(g.phase() == "round_over" and int(g.result.ranking[0]) == 0, "zu zweit: Richtungswechsel macht Anna fertig")


func _c_two_waiting() -> void:
	var hands := [["hell_rot_7"], ["hell_rot_8"], ["hell_rot_9", "hell_blau_1"], ["hell_rot_3", "hell_gelb_1"]]
	var g := make({"hands": hands, "top": "hell_rot_5"}, {"round_end": "last"}, 4)
	play(g, 0, "hell_rot_7", "Anna letzte Karte")
	play(g, 1, "hell_rot_8", "Ben letzte Karte")
	check(g.counter_wait == [0, 1] and hint(g, 2).begins_with("2 Spieler haben keine Karten mehr – wer kontert?"), "zwei Wartende: " + hint(g, 2))
	check(hint(g, 0).contains("Du hast keine Karten mehr") and hint(g, 0).contains("Ben hat keine Karten mehr – wer kontert?"),
		"Anna sieht ihre und Bens Konter-Runde: " + hint(g, 0))
	play(g, 2, "hell_rot_9", "Cleo legt")
	var ev := play(g, 3, "hell_rot_3", "Dani legt")
	check(int(g.place[0]) == 1 and int(g.place[1]) == 2 and at(ev, "finish", 0) < at(ev, "finish", 1) and g.current == 2 and g.phase() == "turn",
		"beide fertig in Reihenfolge, Cleo dran (%s)" % str(names(ev)))
	# Erster fertig: Anna gewinnt, Ben (0 Karten) Zweiter
	g = make({"hands": hands, "top": "hell_rot_5"}, {}, 4)
	play(g, 0, "hell_rot_7", "first: Anna")
	play(g, 1, "hell_rot_8", "first: Ben")
	play(g, 2, "hell_rot_9", "first: Cleo")
	play(g, 3, "hell_rot_3", "first: Dani")
	check(g.phase() == "round_over" and g.result.ranking.slice(0, 2) == [0, 1] and g.counter_wait.is_empty(), "first: Anna vor Ben")
	# Einer gekontert: Dani legt +1 auf Anna, Ben bleibt Wartender und ist dann fertig
	hands = [["hell_rot_7"], ["hell_rot_8"], ["hell_rot_9", "hell_blau_1"], ["hell_rot_plus1", "hell_gelb_1"]]
	g = make({"hands": hands, "top": "hell_rot_5", "draw": ["hell_gruen_9"]}, {"round_end": "last"}, 4)
	play(g, 0, "hell_rot_7", "einer: Anna")
	play(g, 1, "hell_rot_8", "einer: Ben")
	play(g, 2, "hell_rot_9", "einer: Cleo")
	ev = play(g, 3, "hell_rot_plus1", "einer: Dani kontert Anna")
	check((g.hands[0] as Array).size() == 1 and int(g.place[1]) == 1 and int(g.place[0]) == 0 and g.current == 2 and g.counter_wait.is_empty(),
		"Anna gekontert, Ben fertig, Cleo dran (%s)" % str(names(ev)))
	# … mit penalty_turn = play: Anna ist dran, Ben wartet weiter
	g = make({"hands": hands, "top": "hell_rot_5", "draw": ["hell_gruen_9"]}, {"round_end": "last", "penalty_turn": "play"}, 4)
	play(g, 0, "hell_rot_7", "play: Anna")
	play(g, 1, "hell_rot_8", "play: Ben")
	play(g, 2, "hell_rot_9", "play: Cleo")
	play(g, 3, "hell_rot_plus1", "play: Dani kontert Anna")
	check(g.current == 0 and g.counter_wait == [1], "play: Anna dran, Ben wartet weiter")
	# Bis zum Letzten mit nur noch zwei Spielern: Ben legt nach Anna seine letzte Karte, Anna wird fertig → Runde vorbei
	g = make({"hands": [["hell_rot_7"], ["hell_rot_8"], []], "top": "hell_rot_5", "finished": [2]}, {"round_end": "last"}, 3)
	play(g, 0, "hell_rot_7", "Rest: Anna")
	var ev3 := play(g, 1, "hell_rot_8", "Rest: Ben")
	check(g.phase() == "round_over" and g.result.ranking == [2, 0, 1], "nur zwei übrig: Anna fertig, Ben Letzter (%s)" % str(g.result.get("ranking")))
	check(at(ev3, "counter_open", 1) >= 0 and at(ev3, "finish", 0) >= 0, "Rest: Ereignisse")


func _c_swap() -> void:
	var sw := {"swap_cards": "on"}
	# Kartentausch von Ben (Uhrzeigersinn): Anna bekommt Cleos Hand (gekontert), Ben bekommt Annas leere Hand und wartet nun selbst
	var g := make({"hands": [["hell_rot_7"], ["hell_rot_tausch", "hell_blau_1", "hell_blau_2"], ["hell_gelb_1", "hell_gelb_2", "hell_gelb_3"]],
		"top": "hell_rot_5", "draw": ["hell_gruen_9", "hell_gruen_8", "hell_blau_9"]}, sw)
	play(g, 0, "hell_rot_7", "Tausch: Anna letzte Karte")
	var ev := play(g, 1, "hell_rot_tausch", "Tausch: Ben tauscht")
	check(RulesFixture.hand_keys(g, 0) == ["hell_gelb_1", "hell_gelb_2", "hell_gelb_3"] and (g.hands[1] as Array).is_empty()
		and RulesFixture.hand_keys(g, 2) == ["hell_blau_1", "hell_blau_2"], "Tausch: leere Hand wandert zu Ben")
	check(at(ev, "swap_hands") < at(ev, "countered", 0) and at(ev, "countered", 0) < at(ev, "counter_open", 1) and g.counter_wait == [1],
		"Tausch: Anna gekontert, Ben wartet (%s)" % str(names(ev)))
	check(g.current == 2, "Tausch: Cleo dran")
	act(g, 2, {"a": "draw"}, "Tausch: Cleo zieht")
	check(g.current == 0 and g.phase() == "turn", "Tausch: Anna ist normal dran")
	ev = act(g, 0, {"a": "draw"}, "Tausch: Anna zieht")
	check(g.phase() == "round_over" and int(g.result.ranking[0]) == 1 and bool(find(ev, "finish", 1).get("survived", false)),
		"Tausch: Ben wird fertig und gewinnt")
	# Gegen den Uhrzeigersinn: Anna gibt ihre leere Hand an Cleo
	var ccw := {"swap_cards": "on", "swap_direction": "counter"}
	var gspec := {"hands": [["hell_rot_7"], ["hell_rot_tausch", "hell_blau_1"], ["hell_gelb_1", "hell_gelb_2"]], "top": "hell_rot_5",
		"draw": ["hell_gruen_9", "hell_gruen_8", "hell_gruen_7", "hell_gruen_6"]}
	g = make(gspec, ccw)
	play(g, 0, "hell_rot_7", "gegen: Anna")
	ev = play(g, 1, "hell_rot_tausch", "gegen: Ben tauscht")
	check(RulesFixture.hand_keys(g, 0) == ["hell_blau_1"] and RulesFixture.hand_keys(g, 1) == ["hell_gelb_1", "hell_gelb_2"]
		and at(ev, "countered", 0) >= 0 and at(ev, "counter_open", 2) >= 0, "gegen den Uhrzeigersinn: Cleo hat jetzt die leere Hand")
	# … Cleo wäre als Nächste dran, ist aber nicht gleich fertig: Der Zug kommt erst jetzt bei ihr an, sie wartet, Anna ist dran
	check(at(ev, "finish") < 0 and g.phase() == "turn" and g.current == 0 and g.counter_wait == [2] and g.counter_fresh.is_empty(),
		"gegen: Cleo wartet, Anna dran (%s)" % str(names(ev)))
	check(hint(g, 0).contains("Cleo hat keine Karten mehr – wer kontert?"), "gegen: Hinweis für Anna: " + hint(g, 0))
	act(g, 0, {"a": "draw"}, "gegen: Anna zieht")
	check(g.current == 1 and g.counter_wait == [2], "gegen: Ben dran, Cleo wartet weiter")
	ev = act(g, 1, {"a": "draw"}, "gegen: Ben zieht")
	check(bool(find(ev, "finish", 2).get("survived", false)) and g.phase() == "round_over" and int(g.result.ranking[0]) == 2,
		"gegen: keiner kontert, Cleo fertig, als der Zug wieder bei ihr ankommt (%s)" % str(names(ev)))
	# … Ben kontert Cleo mit +1 (er hat jetzt Cleos alte Hand)
	gspec.hands = [["hell_rot_7"], ["hell_rot_tausch", "hell_blau_1"], ["hell_rot_plus1", "hell_gelb_2"]]
	g = make(gspec, ccw)
	play(g, 0, "hell_rot_7", "gegen +1: Anna")
	play(g, 1, "hell_rot_tausch", "gegen +1: Ben tauscht")
	act(g, 0, {"a": "draw"}, "gegen +1: Anna zieht")
	ev = play(g, 1, "hell_rot_plus1", "gegen +1: Ben kontert Cleo")
	check(at(ev, "countered", 2) >= 0 and g.counter_wait.is_empty() and g.counter_fresh.is_empty() and (g.hands[2] as Array).size() == 1
		and int(g.place[2]) == 0 and g.phase() == "turn", "gegen +1: Cleo gekontert (%s)" % str(names(ev)))
	# … Cleo frisch wartend und übersprungen: Konter-Runde überstanden → fertig
	gspec.hands = [["hell_rot_7"], ["hell_rot_tausch", "hell_blau_1"], ["hell_rot_aussetzen", "hell_gelb_2"]]
	g = make(gspec, ccw)
	play(g, 0, "hell_rot_7", "gegen Aussetzen: Anna")
	play(g, 1, "hell_rot_tausch", "gegen Aussetzen: Ben tauscht")
	act(g, 0, {"a": "draw"}, "gegen Aussetzen: Anna zieht")
	ev = play(g, 1, "hell_rot_aussetzen", "gegen Aussetzen: Ben setzt Cleo aus")
	check(bool(find(ev, "finish", 2).get("survived", false)) and g.phase() == "round_over", "gegen Aussetzen: Cleo übersprungen und fertig")
	# Zu viert, Cleo tauscht (Uhrzeigersinn): Ben bekommt Annas leere Hand, ohne dran zu sein. Der Zug kommt erst noch bei ihm an
	# (dann geht er weiter), fertig ist er erst beim nächsten Ankommen; „frisch“ steht dazwischen im Spielstand.
	g = make({"hands": [["hell_rot_7"], ["hell_rot_8", "hell_blau_1"], ["hell_rot_tausch", "hell_gelb_1"], ["hell_gelb_2", "hell_gelb_3"]],
		"top": "hell_rot_5", "draw": ["hell_gruen_9", "hell_gruen_8", "hell_gruen_7", "hell_gruen_6", "hell_gruen_5", "hell_gruen_4", "hell_gruen_3"]},
		sw, 4)
	play(g, 0, "hell_rot_7", "vier: Anna letzte Karte")
	play(g, 1, "hell_rot_8", "vier: Ben legt")
	ev = play(g, 2, "hell_rot_tausch", "vier: Cleo tauscht")
	check(at(ev, "countered", 0) >= 0 and at(ev, "counter_open", 1) >= 0 and g.counter_wait == [1] and g.counter_fresh == [1] and g.current == 3,
		"vier: Ben wartet frisch, Dani dran (%s)" % str(names(ev)))
	var text := JSON.stringify(g.to_dict())
	check((g.to_dict().counter as Dictionary).get("fresh", []) == [1], "vier: counter.fresh im Spielstand")
	var h := MauGame.from_dict(JSON.parse_string(text))
	check(h.counter_fresh == [1] and JSON.stringify(h.to_dict()) == text, "vier: counter.fresh übersteht die Rundreise (Gastgeber-Übergabe)")
	var bad := g.to_dict()
	(bad.counter as Dictionary)["fresh"] = [0, 2, 9]
	check(MauGame.from_dict(bad).counter_fresh.is_empty(), "vier: kaputtes fresh (nicht wartend) wird übergangen")
	act(h, 3, {"a": "draw"}, "vier: Dani zieht")
	act(h, 0, {"a": "draw"}, "vier: Anna zieht")
	check(h.current == 2 and h.counter_wait == [1] and h.counter_fresh.is_empty(), "vier: erstes Ankommen bei Ben – er wartet weiter, Cleo dran")
	act(h, 2, {"a": "draw"}, "vier: Cleo zieht")
	act(h, 3, {"a": "draw"}, "vier: Dani zieht wieder")
	ev = act(h, 0, {"a": "draw"}, "vier: Anna zieht wieder")
	check(bool(find(ev, "finish", 1).get("survived", false)) and h.phase() == "round_over" and int(h.result.ranking[0]) == 1,
		"vier: keiner kontert, Ben fertig beim zweiten Ankommen (%s)" % str(names(ev)))
	# Dazuholen vor Ben verschiebt auch „frisch“
	g = MauGame.from_dict(JSON.parse_string(text))
	g.set_host(3)
	var r0 := g.insert_player(0, {"name": "Neu", "kind": "human"})
	check(bool(r0.ok) and g.counter_wait == [2] and g.counter_fresh == [2], "vier: Dazuholen verschiebt counter_fresh (%s)" % str(g.counter_fresh))
	check(RulesFixture.invariants(g) == "", "vier: Dazuholen " + RulesFixture.invariants(g))
	# Als eigene letzte Karte (Beta 1.6.13, Nutzerwunsch 18.10.2026): Anna tauscht mit – sie bekommt Cleos Hand, ihre leere Hand
	# wandert zu Ben, der nun wartet (frisch: Beim ersten Ankommen gleich danach geht der Zug weiter); Cleo bekommt Bens Hand
	g = make({"hands": [["hell_rot_tausch"], ["hell_blau_1", "hell_blau_2"], ["hell_gelb_1"]], "top": "hell_rot_5"}, sw)
	ev = play(g, 0, "hell_rot_tausch", "Tausch als letzte Karte")
	check(at(ev, "counter_open", 0) < at(ev, "swap_hands") and at(ev, "swap_hands") < at(ev, "countered", 0)
		and at(ev, "countered", 0) < at(ev, "counter_open", 1) and RulesFixture.hand_keys(g, 0) == ["hell_gelb_1"]
		and (g.hands[1] as Array).is_empty() and RulesFixture.hand_keys(g, 2) == ["hell_blau_1", "hell_blau_2"]
		and g.counter_wait == [1] and g.counter_fresh.is_empty() and g.current == 2,
		"letzte Karte Tausch: Anna tauscht mit, die Lücke wandert zu Ben (%s, warten %s, frisch %s, dran %d)" % [str(names(ev)),
			str(g.counter_wait), str(g.counter_fresh), g.current])
	var sh := find(ev, "swap_hands")
	check(sh.counts == [1, 0, 2], "letzte Karte Tausch: Zahlen im Ereignis (%s)" % str(sh.counts))
	check(RulesFixture.invariants(g) == "", "letzte Karte Tausch: " + RulesFixture.invariants(g))
	# … Cleo zieht, Anna spielt normal weiter; kommt der Zug zum zweiten Mal bei Ben an (ohne Karten), ist er fertig
	_pass_turn(g, 2, "letzte Karte Tausch: Cleo zieht")
	check(g.current == 0 and g.phase() == "turn" and RulesFixture.hand_keys(g, 0).size() >= 1, "letzte Karte Tausch: Anna ist normal dran")
	ev = _pass_turn(g, 0, "letzte Karte Tausch: Anna zieht")
	check(at(ev, "finish", 1) >= 0 and bool(find(ev, "finish").get("survived", false)), "letzte Karte Tausch: Ben wird fertig (%s)" % str(names(ev)))
	# gegen den Uhrzeigersinn: Annas leere Hand geht an Cleo, Anna bekommt Bens Hand
	g = make({"hands": [["hell_rot_tausch"], ["hell_blau_1", "hell_blau_2"], ["hell_gelb_1"]], "top": "hell_rot_5"}, ccw)
	play(g, 0, "hell_rot_tausch", "gegen: Tausch als letzte Karte")
	check(RulesFixture.hand_keys(g, 0) == ["hell_blau_1", "hell_blau_2"] and (g.hands[2] as Array).is_empty()
		and RulesFixture.hand_keys(g, 1) == ["hell_gelb_1"] and g.counter_wait == [2],
		"gegen: Anna bekommt Bens Hand, die Lücke wandert zu Cleo (warten %s)" % str(g.counter_wait))
	# zu zweit als letzte Karte: Anna bekommt Bens Hand, Ben die leere und wartet
	g = make({"hands": [["hell_rot_tausch"], ["hell_blau_1", "hell_blau_2"]], "top": "hell_rot_5"}, sw, 2)
	ev = play(g, 0, "hell_rot_tausch", "zu zweit: Tausch als letzte Karte")
	check(at(ev, "swap_hands") >= 0 and RulesFixture.hand_keys(g, 0) == ["hell_blau_1", "hell_blau_2"] and (g.hands[1] as Array).is_empty()
		and g.counter_wait == [1], "zu zweit: Tausch als letzte Karte, Ben hat die leere Hand (warten %s, dran %d)" % [str(g.counter_wait), g.current])
	check(RulesFixture.invariants(g) == "", "zu zweit: letzte Karte Tausch " + RulesFixture.invariants(g))
	# ohne Kontern bleibt es dabei: als letzte Karte fertig, die anderen tauschen untereinander
	g = make({"hands": [["hell_rot_tausch"], ["hell_blau_1", "hell_blau_2"], ["hell_gelb_1"], ["hell_gruen_1"]], "top": "hell_rot_5"},
		{"swap_cards": "on", "counter_round": "off", "round_end": "last"}, 4)
	ev = play(g, 0, "hell_rot_tausch", "ohne Kontern: Tausch als letzte Karte")
	check(at(ev, "finish", 0) >= 0 and (g.hands[0] as Array).is_empty() and RulesFixture.hand_keys(g, 2) == ["hell_blau_1", "hell_blau_2"],
		"ohne Kontern: Anna fertig, die anderen tauschen untereinander (%s)" % str(names(ev)))
	# zu zweit, Anna wartet, Ben tauscht: Anna bekommt Bens Rest, Ben wartet
	g = make({"hands": [["hell_rot_7"], ["hell_rot_tausch", "hell_blau_1"]], "top": "hell_rot_5"}, sw, 2)
	play(g, 0, "hell_rot_7", "zu zweit: Anna")
	play(g, 1, "hell_rot_tausch", "zu zweit: Ben tauscht")
	check(RulesFixture.hand_keys(g, 0) == ["hell_blau_1"] and g.counter_wait == [1] and g.current == 0, "zu zweit: Anna dran, Ben wartet")
	# Lecktest der Tausch-Ereignisse mit Wartenden
	g = make({"hands": [["hell_rot_7"], ["hell_rot_tausch", "hell_blau_1", "hell_blau_2"], ["hell_gelb_1"]], "top": "hell_rot_5"}, sw)
	play(g, 0, "hell_rot_7", "Leck: Anna")
	var r := g.apply(1, {"a": "play", "card": RulesFixture.card(g, 1, "hell_rot_tausch")})
	for s in range(-1, 3):
		var e := _leak_events(g, r.events, s, [])
		check(e == "", "Tausch mit Wartenden: Lecktest Platz %d %s" % [s, e])


func _c_flip_surprise() -> void:
	var fs := {"flip_surprise": "on"}
	# Cleo (Vorgängerin) flipt, oben liegt +5: wirkt auf Anna → gekontert
	var g := make({"hands": [["hell_rot_7"], ["hell_rot_8", "hell_blau_1"], ["hell_rot_flip", "hell_gelb_1"]], "top": "hell_rot_5",
		"discard": ["hell_blau_4/dunkel_pink_plus5"]}, fs)
	play(g, 0, "hell_rot_7", "Flip: Anna")
	play(g, 1, "hell_rot_8", "Flip: Ben")
	var ev := play(g, 2, "hell_rot_flip", "Flip: Cleo flipt")
	check(at(ev, "flip_surprise") >= 0 and at(ev, "draw", 0) > at(ev, "flip_surprise") and at(ev, "countered", 0) >= 0
		and (g.hands[0] as Array).size() == 5 and g.counter_wait.is_empty(), "Flip-Überraschung +5 kontert Anna (%s)" % str(names(ev)))
	# … oben liegt Aussetzen: Anna übersprungen → fertig
	g = make({"hands": [["hell_rot_7"], ["hell_rot_8", "hell_blau_1"], ["hell_rot_flip", "hell_gelb_1"]], "top": "hell_rot_5",
		"discard": ["hell_blau_4/dunkel_pink_alle_aussetzen"]}, fs)
	play(g, 0, "hell_rot_7", "Flip AA: Anna")
	play(g, 1, "hell_rot_8", "Flip AA: Ben")
	play(g, 2, "hell_rot_flip", "Flip AA: Cleo flipt")
	check(g.phase() == "round_over" and int(g.result.ranking[0]) == 0, "Flip-Überraschung Alle aussetzen: Anna fertig")
	# Eigener Flip als letzte Karte (wird ausgeführt): oben +5 → Ben zieht, Anna wartet
	g = make({"hands": [["hell_rot_flip"], ["hell_blau_1"], ["hell_gelb_1"]], "top": "hell_rot_5", "discard": ["hell_blau_4/dunkel_pink_plus5"]}, fs)
	ev = play(g, 0, "hell_rot_flip", "Flip als letzte Karte")
	check(g.side == 1 and (g.hands[1] as Array).size() == 6 and g.counter_wait == [0] and g.current == 2, "Flip als letzte Karte: Ben zieht 5, Anna wartet")
	# … Joker oben: Anna (0 Karten) wählt die Farbe, danach geht es weiter
	g = make({"hands": [["hell_rot_flip"], ["hell_blau_1"], ["hell_gelb_1"]], "top": "hell_rot_5", "discard": ["hell_blau_4/dunkel_wuenscher"]}, fs)
	play(g, 0, "hell_rot_flip", "Flip mit Joker oben")
	check(g.phase() == "color" and g.current == 0 and g.counter_wait == [0] and bool(g.view_for(0).hints.need_color), "Joker oben: Anna wählt")
	var bot := MauBot.choose(g.view_for(0), 3, 1)
	check(str(bot.get("a", "")) == "color", "Bot wählt die Farbe mit leerer Hand")
	act(g, 0, {"a": "color", "color": "lila"}, "Farbe Lila")
	check(g.current == 1 and g.color == "lila" and g.counter_wait == [0], "nach der Farbwahl Ben dran")
	# … Ablegen-Joker bzw. Glücksspiel oben: nichts abzulegen oder zu setzen
	g = make({"hands": [["hell_rot_flip"], ["hell_blau_1"], ["hell_gelb_1"]], "top": "hell_rot_5", "discard": ["hell_blau_4/dunkel_gluecksspiel"]},
		{"flip_surprise": "on", "gamble_cards": "on", "discard_color": "on"})
	play(g, 0, "hell_rot_flip", "Flip, Glücksspiel oben")
	check(g.phase() == "color" and not MauBot.discard_wish(g.view_for(0)), "Glücksspiel oben: nur Farbwahl")
	act(g, 0, {"a": "color", "color": "pink"}, "Farbe Pink")
	check(g.phase() == "turn" and g.gamble.is_empty() and g.current == 1, "kein Glücksspiel mit leerer Hand")
	# flip_last_card = ignore: Flip als letzte Karte wird nicht ausgeführt
	g = make({"hands": [["hell_rot_flip"], ["hell_blau_1"], ["hell_gelb_1"]], "top": "hell_rot_5", "discard": ["hell_blau_4/dunkel_pink_plus5"]},
		{"flip_surprise": "on", "flip_last_card": "ignore"})
	play(g, 0, "hell_rot_flip", "Flip ignore")
	check(g.side == 0 and g.counter_wait == [0] and g.current == 1 and (g.hands[1] as Array).size() == 1, "ignore: kein Flip, Anna wartet")


func _c_gamble() -> void:
	var gm := {"gamble_cards": "on"}
	# Letzte Karte gesetzt, 0 gedrückt: Einsatz unter die Ablage, Anna wartet (statt fertig)
	var g := make({"hands": [["hell_rot_7"], ["hell_blau_1"], ["hell_gelb_1"]], "top": "hell_gluecksspiel", "color": "rot", "gamble": {"q": 5}}, gm)
	act(g, 0, {"a": "stake", "card": RulesFixture.card(g, 0, "hell_rot_7")}, "Glücksspiel: setzen")
	g.force_rolls([0])
	var ev := act(g, 0, {"a": "press"}, "Glücksspiel: drücken")
	check(str(find(ev, "stake_discard").get("reason", "")) == "empty" and at(ev, "counter_open", 0) > at(ev, "stake_discard")
		and at(ev, "finish") < 0 and g.counter_wait == [0] and g.current == 1, "leere Hand: Konter-Runde (%s)" % str(names(ev)))
	# Glücksspiel als letzte Karte: kein Glücksspiel, Anna wartet
	g = make({"hands": [["hell_gluecksspiel"], ["hell_blau_1"], ["hell_gelb_1"]], "top": "hell_rot_5"}, gm)
	ev = play(g, 0, "hell_gluecksspiel", "Glücksspiel als letzte Karte", "blau")
	check(at(ev, "gamble_start") < 0 and g.counter_wait == [0] and g.current == 1 and g.phase() == "turn", "Glücksspiel als letzte Karte: wartet")


func _c_discard() -> void:
	var g := make({"hands": [["hell_rot_ablegen", "hell_rot_3", "hell_rot_4"], ["hell_blau_1"], ["hell_gelb_1"]], "top": "hell_rot_5"},
		{"discard_color": "on"})
	play(g, 0, "hell_rot_ablegen", "Ablegen")
	check(g.phase() == "discard_pick" and g.counter_wait.is_empty(), "Auswahl offen, noch keine Konter-Runde")
	var ev := act(g, 0, {"a": "discard_pick", "cards": [RulesFixture.card(g, 0, "hell_rot_3"), RulesFixture.card(g, 0, "hell_rot_4")]}, "alles mit ablegen")
	check(at(ev, "discard_color") < at(ev, "counter_open", 0) and g.counter_wait == [0] and g.current == 1, "Ablegen leert die Hand: Konter-Runde")
	# Ablegen-Joker als letzte Karte (nur Spielfarbe)
	g = make({"hands": [["hell_ablegen_joker"], ["hell_blau_1"], ["hell_gelb_1"]], "top": "hell_rot_5"}, {"discard_color": "on"})
	play(g, 0, "hell_ablegen_joker", "Ablegen-Joker als letzte Karte", "rot")
	act(g, 0, {"a": "discard_pick", "cards": [], "color": "blau"}, "Spielfarbe Blau")
	check(g.counter_wait == [0] and g.color == "blau" and g.current == 1, "Ablegen-Joker: wartet, Blau gilt")


func _c_bluff() -> void:
	# Anzweifeln (nur aus Verträglichkeit): letzte Karte Wünscher +2, Ben nimmt an → Anna wartet
	var g := make({"hands": [["hell_wuenscher_plus2"], ["hell_blau_1"], ["hell_gelb_1"]], "top": "hell_rot_5"}, {"wild_restriction": "bluff"})
	play(g, 0, "hell_wuenscher_plus2", "Bluff: letzte Karte +2", "gelb")
	check(g.phase() == "challenge" and g.current == 1 and g.counter_wait.is_empty(), "Bluff: Ben überlegt")
	var ev := act(g, 1, {"a": "accept"}, "Bluff: Ben nimmt an")
	check(at(ev, "counter_open", 0) >= 0 and at(ev, "finish") < 0 and g.counter_wait == [0] and g.current == 2, "Bluff: Anna wartet, Cleo dran")
	# Ben wartet schon, Anna legt als letzte Karte einen Wünscher +2: Ben zieht sofort (gekontert), Anna wartet jetzt selbst
	g = make({"hands": [["hell_wuenscher_plus2"], [], ["hell_gelb_1"]], "top": "hell_rot_5", "counter": [1],
		"draw": ["hell_gruen_9", "hell_gruen_8", "hell_blau_9"]}, {"wild_restriction": "bluff"})
	ev = play(g, 0, "hell_wuenscher_plus2", "Bluff auf Wartenden: letzte Karte +2", "gelb")
	check(at(ev, "counter_open", 0) >= 0 and at(ev, "countered", 1) >= 0 and at(ev, "finish") < 0 and g.counter_wait == [0]
		and (g.hands[1] as Array).size() == 2 and g.pending.is_empty() and g.current == 2, "Bluff auf Wartenden: Anna wartet (%s)" % str(names(ev)))
	ev = act(g, 2, {"a": "draw"}, "Bluff auf Wartenden: Cleo zieht")
	check(bool(find(ev, "finish", 0).get("survived", false)) and g.phase() == "round_over" and int(g.result.ranking[0]) == 0,
		"Bluff auf Wartenden: Anna fertig, als der Zug wieder bei ihr ankommt")


func _c_mau() -> void:
	# Mau gerufen, dann die letzte Karte: Ruf verfällt, nichts zu erwischen
	var g := make({"hands": [["hell_rot_7"], ["hell_blau_1", "hell_blau_2"], ["hell_gelb_1"]], "top": "hell_rot_5", "mau_said": [0]})
	play(g, 0, "hell_rot_7", "Mau: letzte Karte")
	check(not bool(g.mau_said[0]) and g.mau_open == -1, "Mau-Ruf verfällt")
	check(not bool(g.apply(1, {"a": "catch", "target": 0}).ok), "einen Wartenden kann man nicht erwischen")
	# Wer gekontert wurde und mit 2 Karten wieder dran ist, muss wieder rufen
	g = waiting_game(["hell_rot_8", "hell_blau_1"], ["hell_wuenscher_plus2", "hell_gelb_1"], {"penalty_turn": "play"},
		{"draw": ["hell_gelb_7", "hell_gelb_8"]})
	act(g, 1, {"a": "play", "card": RulesFixture.card(g, 1, "hell_rot_8")}, "Ben legt")
	play(g, 2, "hell_wuenscher_plus2", "Cleo kontert mit +2", "gelb")
	check(g.current == 0 and bool(g.view_for(0).hints.can_mau), "Anna mit 2 Karten: „Mau!“ möglich")
	play(g, 0, "hell_gelb_7", "Anna legt ohne Mau")
	check(g.mau_open == 0 and (g.view_for(1).hints.catch as Array) == [0], "ohne Ruf erwischbar")
	act(g, 1, {"a": "catch", "target": 0}, "Ben erwischt Anna")
	check((g.hands[0] as Array).size() == 3 and g.counter_wait.is_empty(), "Erwischt-Strafe")


func _c_save_load() -> void:
	var g := waiting_game(["hell_rot_8", "hell_blau_1"], ["hell_rot_plus1", "hell_gelb_1"])
	var d := g.to_dict()
	check((d.get("counter", {}) as Dictionary) == {"wait": [0], "done": -1}, "to_dict: counter")
	var text := JSON.stringify(d)
	var h := MauGame.from_dict(JSON.parse_string(text))
	check(JSON.stringify(h.to_dict()) == text and h.counter_wait == [0], "Rundreise mit Wartendem")
	for s in range(-1, 3):
		check(JSON.stringify(h.view_for(s)) == JSON.stringify(g.view_for(s)), "Sicht %d nach dem Laden gleich" % s)
	act(h, 1, {"a": "play", "card": RulesFixture.card(h, 1, "hell_rot_8")}, "geladen: Ben legt")
	play(h, 2, "hell_rot_plus1", "geladen: Cleo kontert")
	check(h.counter_wait.is_empty() and (h.hands[0] as Array).size() == 1, "geladen: Kontern klappt")
	# Ohne Schlüssel (älterer Stand) bzw. kaputt: niemand mit Karten wartet
	var old := d.duplicate(true)
	old.erase("counter")
	check(MauGame.from_dict(old).counter_wait.is_empty(), "Stand ohne counter: niemand wartet")
	var bad := d.duplicate(true)
	bad["counter"] = {"wait": [1, 0, 0, 7, "x"], "done": 99}
	var b := MauGame.from_dict(bad)
	check(b.counter_wait == [0] and b.counter_done == -1, "kaputte Konterliste gesäubert (%s)" % str(b.counter_wait))
	var off := d.duplicate(true)
	(off.config as Dictionary)["counter_round"] = "off"
	check(MauGame.from_dict(off).counter_wait.is_empty(), "ohne Hausregel wird counter übergangen")
	# „fertig!“-Hinweis überlebt das Laden
	g = waiting_game(["hell_blau_1", "hell_blau_2"], ["hell_gelb_1", "hell_gelb_2"], {"round_end": "last"})
	act(g, 1, {"a": "draw"}, "Ben zieht")
	act(g, 2, {"a": "draw"}, "Cleo zieht")
	var g2 := MauGame.from_dict(JSON.parse_string(JSON.stringify(g.to_dict())))
	check(g2.counter_done == 0 and hint(g2, 1).begins_with("Anna ist fertig!"), "counter.done nach dem Laden")


func _c_seats() -> void:
	var g := waiting_game(["hell_rot_8", "hell_blau_1"], ["hell_gelb_1"], {}, {"host": 2})
	var r := g.insert_player(0, {"name": "Neu", "kind": "human"})
	check(bool(r.ok) and g.counter_wait == [1] and (g.hands[1] as Array).is_empty() and g.current == 2, "Dazuholen vor Anna: Anna wartet auf Platz 1")
	check(RulesFixture.invariants(g) == "", "Dazuholen: " + RulesFixture.invariants(g))
	r = g.remove_player(1)
	check(bool(r.ok) and g.counter_wait.is_empty() and g.players.size() == 3, "Entfernen der Wartenden")
	check(RulesFixture.invariants(g) == "", "Entfernen: " + RulesFixture.invariants(g))
	# Entfernen dessen, der dran ist: der Zug geht weiter zur Wartenden → fertig
	g = make({"hands": [["hell_rot_7"], ["hell_blau_1"], ["hell_gelb_1"], ["hell_gelb_2"]], "top": "hell_rot_5",
		"draw": ["hell_gruen_9", "hell_gruen_8"]}, {"round_end": "last"}, 4)
	play(g, 0, "hell_rot_7", "Anna letzte Karte")
	act(g, 1, {"a": "draw"}, "Ben zieht")
	act(g, 2, {"a": "draw"}, "Cleo zieht")
	check(g.current == 3, "Dani dran")
	r = g.remove_player(3)
	check(bool(r.ok) and int(g.place[0]) == 1 and g.current == 1 and g.players.size() == 3, "Dani entfernt: Anna fertig, Ben dran")


func _c_stats() -> void:
	var path := "user://test_rules_counter_stats.json"
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var st := AppStats.new(path)
	var g := make({"hands": [["hell_rot_7"], ["hell_blau_1", "hell_blau_2"], ["hell_gelb_1", "hell_gelb_2"]], "top": "hell_rot_5",
		"draw": ["hell_gruen_9", "hell_gruen_8"]})
	var r := g.apply(0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_rot_7")})
	st.record(g.events_for(0, r.events), g.view_for(0), "solo")
	check(st.value("mau_mau") == 0 and st.value("runden_gewonnen") == 0, "Statistik: nach der letzten Karte noch kein „Mau-Mau!“")
	r = g.apply(1, {"a": "draw"})
	st.record(g.events_for(0, r.events), g.view_for(0), "solo")
	r = g.apply(2, {"a": "draw"})
	st.record(g.events_for(0, r.events), g.view_for(0), "solo")
	check(st.value("mau_mau") == 1 and st.value("runden_gewonnen") == 1 and st.value("runden") == 1, "Statistik: Sieg erst beim endgültigen Fertig")
	# Gekontert: kein „Mau-Mau!“, kein Sieg
	var st2 := AppStats.new(path + "2.json")
	g = waiting_game(["hell_rot_8", "hell_blau_1"], ["hell_rot_plus1", "hell_gelb_1"])
	r = g.apply(1, {"a": "play", "card": RulesFixture.card(g, 1, "hell_rot_8")})
	st2.record(g.events_for(0, r.events), g.view_for(0), "solo")
	r = g.apply(2, {"a": "play", "card": RulesFixture.card(g, 2, "hell_rot_plus1")})
	st2.record(g.events_for(0, r.events), g.view_for(0), "solo")
	check(st2.value("mau_mau") == 0 and st2.value("gezogen") == 1 and st2.value("aussetzen") == 1, "Statistik: gekontert zählt als Ziehen")
	for p in [path, path + ".bak", path + ".tmp", path + "2.json", path + "2.json.bak", path + "2.json.tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _c_rules_and_texts() -> void:
	var fam := RuleConfig.preset("familie")
	check(fam.counter_round == "on" and RuleConfig.new().counter_round == "off" and RuleConfig.preset("mau_mau").counter_round == "off",
		"Familie an, offiziell und Mau-Mau aus")
	check(fam.preset_name() == "familie" and RuleConfig.from_dict({"counter_round": "on"}).preset_name() == "", "Voreinstellungen erkannt")
	check(RuleConfig.CHOICES["counter_round"] == ["off", "on"] and RuleConfig.from_dict({"counter_round": "ja"}).counter_round == "off",
		"Schalter und ungültige Werte")
	var old := fam.to_dict()
	old.erase("counter_round")                      # Familie 1.6.10, so gespeichert
	var up := RuleConfig.from_dict(RuleConfig.migrate_dict(old))
	check(up.counter_round == "on" and up.preset_name() == "familie", "alte Familie wird gehoben")
	var chosen := fam.to_dict()
	chosen["counter_round"] = "off"
	check(RuleConfig.from_dict(RuleConfig.migrate_dict(chosen)).counter_round == "off", "bewusst ausgeschaltet bleibt aus")
	var own := RuleConfig.preset("mau_mau").to_dict()
	own.erase("counter_round")
	check(RuleConfig.from_dict(RuleConfig.migrate_dict(own)).counter_round == "off", "andere alte Sätze bleiben ohne Kontern")
	var older := fam.to_dict()                       # Familie 1.1.2: ohne draw_play und counter_round
	older.erase("counter_round")
	older.erase("draw_play")
	check(RuleConfig.from_dict(RuleConfig.migrate_dict(older)).preset_name() == "familie", "sehr alte Familie wird gehoben")
	var on := ccfg()
	var desc := "\n".join(on.describe())
	check(desc.contains("Kontern: Wer keine Karten mehr hat") and not "\n".join(RuleConfig.new().describe()).contains("Kontern"), "describe")
	var titles: Array = []
	for p in RulesText.overview(on):
		titles.append(str(p.title))
	check(titles.has("Kontern") and not str(RulesText.overview(RuleConfig.new())).contains("Kontern"), "Regelübersicht: Absatz Kontern")
	check("\n".join(RulesText.card_help("hell_rot_plus1", on)).contains("Kontern: Hat der Nächste keine Karten mehr, zieht er")
		and not "\n".join(RulesText.card_help("hell_rot_plus1", RuleConfig.new())).contains("Kontern"), "Kartenhilfe +1")
	check("\n".join(RulesText.card_help("hell_rot_aussetzen", on)).contains("übersprungen"), "Kartenhilfe Aussetzen")
	check("\n".join(RulesText.card_help("dunkel_farbjagd", on)).contains("Kontern"), "Kartenhilfe Farbjagd")
	check("\n".join(RulesText.card_help("hell_rot_tausch", ccfg({"swap_cards": "on"}))).contains("leere Hand"), "Kartenhilfe Kartentausch")
	check("\n".join(RulesText.card_help("hell_gluecksspiel", ccfg({"gamble_cards": "on"}))).contains("keiner kontert"), "Kartenhilfe Glücksspiel")
	check(RulesBar.summary(fam).contains("Kontern") and not RulesBar.summary(RuleConfig.new()).contains("Kontern"), "Kurzbeschreibung")
	var found := false
	for o in RulesScreen.OPTIONS:
		if str(o[0]) == "counter_round":
			found = str(o[1]) == "Kontern" and (o[3] as Array).size() == 2
	check(found, "Regelauswahl: Zeile „Kontern“")
	# Browser: Regelübersicht und Ereignisliste
	var web := ProjectSettings.globalize_path("res://").path_join("../webclient").simplify_path()
	var karten := FileAccess.get_file_as_string(web.path_join("karten.js"))
	var autotest := FileAccess.get_file_as_string(web.path_join("autotest.js"))
	var po := FileAccess.get_file_as_string(web.path_join("i18n_po.js"))
	var line := "Kontern: Wer keine Karten mehr hat, ist erst fertig, wenn die Runde wieder bei ihm ankommt. Bekommt er bis dahin Karten, spielt er weiter."
	check(karten.contains("r.counter_round === 'on'") and karten.contains(line) and desc.contains(line), "Browser: gleicher Regeltext wie die App")
	check(autotest.contains("'counter_open', 'countered'"), "Browser: Ereignisse bekannt")
	check(po.contains(JSON.stringify(line)), "Browser: Übersetzung in i18n_po.js")
	# Mit Kontern keine widersprüchlichen „fertig“-Sätze in der Kartenhilfe (App) …
	var all := ccfg({"swap_cards": "on", "gamble_cards": "on", "discard_color": "on", "flip_surprise": "on"})
	var gl := "\n".join(RulesText.card_help("hell_gluecksspiel", all))
	check(not gl.contains("einfach fertig") and not gl.contains("du bist fertig") and gl.contains("Als letzte Karte gibt es kein Glücksspiel; fertig bist du erst"),
		"Kartenhilfe Glücksspiel ohne „fertig“: " + gl)
	for key in ["hell_rot_ablegen", "dunkel_ablegen_joker"]:
		var dl := "\n".join(RulesText.card_help(key, all))
		check(not dl.contains("bist du fertig") and not dl.contains("gewinnst du die Runde") and dl.contains("wartest du, ob dich jemand kontert"),
			"Kartenhilfe %s ohne „fertig“: %s" % [key, dl])
	var fl := "\n".join(RulesText.card_help("hell_rot_flip", all))
	check(not fl.contains("gewertet wird die neue Seite") and fl.contains("fertig bist du erst, wenn dich keiner kontert"), "Kartenhilfe Flip: " + fl)
	var tw := "\n".join(RulesText.card_help("hell_rot_tausch", all))
	check(not tw.contains("Du bist fertig"), "Kartenhilfe Kartentausch ohne „Du bist fertig“")
	var ov := str(RulesText.overview(all))
	check(not ov.contains("Bleibt keine Karte, bist du fertig.") and ov.contains("Bleibt keine Karte, wartest du, ob dich jemand kontert.")
		and ov.contains("und du wartest, ob dich jemand kontert"), "Regelübersicht: Ablegen und Glücksspiel mit Kontern")
	check("\n".join(RulesText.card_help("hell_gluecksspiel", RuleConfig.from_dict({"gamble_cards": "on"}))).contains("einfach fertig"),
		"ohne Kontern bleibt der alte Text")
	# … und im Browser (karten.js hilfe(): dieselben msgids, Übersetzungen in i18n_po.js)
	for msg in ["Kontern: Hat der Nächste keine Karten mehr, zieht er und spielt weiter.",
			"Kontern: Hat der Nächste keine Karten mehr, ist er damit fertig – er wird ja übersprungen. Als deine letzte Karte zu zweit setzt der andere nicht aus: Er darf noch kontern.",
			"Kontern: Wer keine Karten mehr hat, ist damit fertig. Ist es deine letzte Karte, ist trotzdem der Nächste dran, damit er kontern kann.",
			"Kontern: Kommt der Zug dadurch wieder zu jemandem ohne Karten, ist er fertig. Als deine letzte Karte zu zweit ist der andere trotzdem dran: Er darf noch kontern.",
			"Kontern: Mit leerer Hand bist du erst fertig, wenn dich bis zu deinem nächsten Zug keiner kontert.",
			"Auch als letzte Karte tauschst du mit: Du bekommst eine Hand, deine leere Hand wandert zum Nächsten – der hat dann keine Karten mehr und wartet aufs Kontern.",
			"Kontern: Wer keine Karten mehr hat, tauscht mit und spielt weiter; wer dabei die leere Hand bekommt, hat nun selbst keine Karten mehr.",
			"Als letzte Karte wird der Flip noch ausgeführt und wirkt ganz normal; fertig bist du erst, wenn dich keiner kontert.",
			"Zeigt er 0 und deine Hand ist leer, kommt der Einsatz unter den Ablagestapel; fertig bist du erst, wenn dich keiner kontert.",
			"Als letzte Karte gibt es kein Glücksspiel; fertig bist du erst, wenn dich keiner kontert.",
			"Bleibt dir danach 1 Karte, ruf „Mau!“ (auch schon vorher erlaubt); bleibt keine, wartest du, ob dich jemand kontert.",
			"Bleibt dir danach keine Karte, wartest du, ob dich jemand kontert."]:
		check(karten.contains("tr('%s')" % msg) and po.contains(JSON.stringify(msg)), "Browser-Kartenhilfe mit Übersetzung: " + msg)
	var hilfe := karten.substr(karten.find("function hilfe("), karten.find("function regelnText(") - karten.find("function hilfe("))
	check(hilfe.count("kontern") >= 8, "Browser-Kartenhilfe prüft Kontern bei allen betroffenen Karten")


func _c_bots() -> void:
	# Cleo ist Vorgängerin der wartenden Anna: kontert mit +1 (Stufe 1 und 2, verschiedene Startwerte)
	var spec := {"hands": [[], ["hell_blau_1"], ["hell_rot_plus1", "hell_rot_9", "hell_rot_8"]], "top": "hell_rot_5", "current": 2, "counter": [0]}
	var g := make(spec)
	var all_ok := true
	for seed_i in 20:
		for level in [1, 2]:
			var a := MauBot.choose(g.view_for(2), seed_i, level)
			if str(a.get("a", "")) != "play" or int(a.get("card", -1)) != RulesFixture.card(g, 2, "hell_rot_plus1"):
				all_ok = false
	check(all_ok, "Bot kontert mit +1")
	spec.hands = [[], ["hell_blau_1"], ["hell_wuenscher_plus2", "hell_rot_9", "hell_rot_8"]]
	g = make(spec)
	var a2 := MauBot.choose(g.view_for(2), 4, 2)
	check(int(a2.get("card", -1)) == RulesFixture.card(g, 2, "hell_wuenscher_plus2"), "Bot kontert mit Wünscher +2 (Joker sonst gespart)")
	spec.hands = [[], ["hell_blau_1"], ["hell_rot_aussetzen", "hell_rot_9", "hell_blau_8"]]
	g = make(spec)
	all_ok = true
	for seed_i in 20:
		if int(MauBot.choose(g.view_for(2), seed_i, 2).get("card", -1)) == RulesFixture.card(g, 2, "hell_rot_aussetzen"):
			all_ok = false
	check(all_ok, "Bot setzt die Wartende nicht aus (das machte sie fertig)")
	spec.hands = [[], ["hell_blau_1", "hell_blau_2"], ["hell_rot_tausch", "hell_rot_9", "hell_rot_8"]]
	g = RulesFixture.build(ccfg({"swap_cards": "on"}), 3, spec)
	check(int(MauBot.choose(g.view_for(2), 7, 2).get("card", -1)) == RulesFixture.card(g, 2, "hell_rot_tausch"), "Bot kontert mit Kartentausch")
	# Beta 1.6.13: Nur noch der Kartentausch auf der Hand (niemand wartet): Als letzte Karte bekäme der Bot die Hand seiner Vorgängerin –
	# er zieht lieber; ohne Kontern legt er ihn (dann ist er fertig)
	spec = {"hands": [["hell_gelb_1", "hell_gelb_2", "hell_gelb_3"], ["hell_blau_1", "hell_blau_2"], ["hell_rot_tausch"]], "top": "hell_rot_5",
		"current": 2}
	g = make(spec, {"swap_cards": "on"})
	all_ok = true
	for seed_i in 10:
		if str(MauBot.choose(g.view_for(2), seed_i, 2).get("a", "")) != "draw":
			all_ok = false
	check(all_ok and MauBot.swap_value(g.view_for(2)) < -6.0, "Bot legt den Kartentausch nicht als letzte Karte (Kontern), er zieht")
	g = RulesFixture.build(ccfg({"swap_cards": "on", "counter_round": "off"}), 3, spec)
	check(int(MauBot.choose(g.view_for(2), 3, 2).get("card", -1)) == RulesFixture.card(g, 2, "hell_rot_tausch"), "ohne Kontern: letzte Karte Tausch, Bot legt ihn")
	# Richtungswechsel zur wartenden Vorgängerin (Ben wartet, Cleo dran): lieber nicht
	spec = {"hands": [["hell_gelb_1", "hell_gelb_2"], [], ["hell_rot_richtungswechsel", "hell_rot_9", "hell_blau_8"]], "top": "hell_rot_5",
		"current": 2, "counter": [1]}
	g = make(spec)
	all_ok = true
	for seed_i in 20:
		if int(MauBot.choose(g.view_for(2), seed_i, 2).get("card", -1)) == RulesFixture.card(g, 2, "hell_rot_richtungswechsel"):
			all_ok = false
	check(all_ok, "Bot dreht nicht zur Wartenden zurück")
	check(MauBot.waiting({"counter": true, "place": 0}) and not MauBot.waiting({"count": 0, "place": 0}), "MauBot.waiting")


# Ohne die Hausregel bleibt alles wie bisher: letzte Karte = fertig, keine neuen Felder.
func _c_off_unchanged() -> void:
	var g := RulesFixture.build(RuleConfig.new(), 3, {"hands": [["hell_rot_7"], ["hell_blau_1"], ["hell_gelb_1"]], "top": "hell_rot_5"})
	var r := g.apply(0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_rot_7")})
	check(at(r.events, "finish", 0) >= 0 and at(r.events, "counter_open") < 0 and g.phase() == "round_over", "offiziell: gleich fertig")
	var v := g.view_for(1)
	check(not v.has("counter") and not (v.players[0] as Dictionary).has("counter") and not g.to_dict().has("counter"), "offiziell: keine neuen Felder")


# --- Bot-Dauerlauf mit allen Hausregeln ---

func _c_bot_run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 16102026
	var first := ""
	var ended := 0
	for i in COUNTER_GAMES:
		var cfg := RulesFixture.random_config(rng, rng.randf() < 0.6, rng.randf() < 0.5, rng.randf() < 0.5, true)
		if i % 4 == 0:
			cfg.flip_surprise = "on"
		var n := rng.randi_range(2, 8)
		var g := MauGame.create(cfg, RulesFixture.players(n, "bot"), 4_000_000 + i)
		g.start_round()
		var steps := 0
		while g.state in MauGame.PLAY_PHASES and steps < COUNTER_STEP_LIMIT:
			steps += 1
			var seat := g.current_seat()
			var r := g.apply(seat, MauBot.choose(g.view_for(seat), rng.randi(), rng.randi_range(0, 2)))
			if not bool(r.ok) and first == "":
				first = "Partie %d: abgelehnt %s" % [i, r.reason]
			for e in r.events:
				var k := str(e.get("e", ""))
				if k == "finish" and bool(e.get("survived", false)):
					k = "finish_survived"
				if k in ["counter_open", "countered", "finish_survived", "swap_hands", "flip_surprise"]:
					cstats[k] = int(cstats.get(k, 0)) + 1
			var inv := RulesFixture.invariants(g)
			if inv != "" and first == "":
				first = "Partie %d Schritt %d: %s" % [i, steps, inv]
			if g.counter_wait.size() >= 2:
				cstats["two_waiting"] = int(cstats.get("two_waiting", 0)) + 1
		if g.state in ["round_over", "game_over"]:
			ended += 1
			if g.counter_wait.size() > 0 and first == "":
				first = "Partie %d: Wartende nach dem Rundenende" % i
		elif first == "":
			first = "Partie %d endet nicht (%d Schritte, Phase %s)" % [i, steps, g.state]
	print("Kontern-Dauerlauf: %d Partien, %s" % [COUNTER_GAMES, str(cstats)])
	check(first == "", "Dauerlauf mit Kontern: " + first)
	check(ended == COUNTER_GAMES, "alle Runden enden (%d)" % ended)
	for k in ["counter_open", "countered", "finish_survived", "two_waiting"]:
		check(int(cstats.get(k, 0)) > 0, "Dauerlauf: „%s“ kam vor" % k)
