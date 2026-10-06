extends SceneTree
# Modul A: jede Karte, Regel und Option einzeln in gezielt aufgebauten Situationen (RulesFixture).
# Plätze: 0 Anna, 1 Ben, 2 Cleo (Standard 3 Spieler, Platz 0 am Zug, Richtung +1).

var failures := 0
var checks := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)


func _initialize() -> void:
	_matching()
	_wish()
	_draw_cards()
	_skip_reverse()
	_skip_all()
	_flip()
	_start_card()
	_bluff_plus2()
	_restriction_modes()
	_farbjagd()
	_stacking()
	_last_card()
	_piles()
	_mau()
	_round_end_last()
	_scoring()
	_draw_rules()
	_two_players()
	_hint_texts()
	_broken_actions()
	_host_seat()
	_fixes()
	print("Laufzeit seit Godot-Start: %.1f s" % (Time.get_ticks_msec() / 1000.0))
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)


# --- Hilfen ---

func make(spec: Dictionary, opts := {}, n := 3) -> MauGame:
	# Diese Fälle stammen aus der Zeit mit Anzweifeln als Standard: ohne Angabe gilt hier weiter wild_restriction = bluff.
	var d := {"wild_restriction": "bluff"}
	d.merge(opts, true)
	var g := RulesFixture.build(RuleConfig.from_dict(d), n, spec)
	check(RulesFixture.card_check(g) == "", "Aufbau mit 112 Karten: " + RulesFixture.card_check(g))
	return g


func id_of(g: MauGame, seat: int, key: String) -> int:
	var id := RulesFixture.card(g, seat, key)
	check(id >= 0, "Karte %s bei Platz %d vorhanden" % [key, seat])
	return id


func act(g: MauGame, seat: int, action: Dictionary, msg: String) -> Array:
	var r := g.apply(seat, action)
	check(bool(r.ok), "%s (abgelehnt: %s)" % [msg, r.reason])
	var cc := RulesFixture.card_check(g)
	check(cc == "", "%s: Kartenzahl %s" % [msg, cc])
	return r.events


func play(g: MauGame, seat: int, key: String, msg: String, col := "") -> Array:
	var a := {"a": "play", "card": id_of(g, seat, key)}
	if col != "":
		a["color"] = col
	return act(g, seat, a, msg)


# Erwartet eine Ablehnung, der Zustand bleibt unverändert.
func deny(g: MauGame, seat: int, action: Dictionary, msg: String) -> String:
	var before := JSON.stringify(g.to_dict())
	var r := g.apply(seat, action)
	check(not bool(r.ok), msg + " (wurde angenommen)")
	check(str(r.reason) != "", msg + ": Begründung vorhanden")
	check(JSON.stringify(g.to_dict()) == before, msg + ": Zustand unverändert")
	return str(r.reason)


func n_hand(g: MauGame, seat: int) -> int:
	return (g.hands[seat] as Array).size()


func ev_names(ev: Array) -> Array:
	var out: Array = []
	for e in ev:
		out.append(str(e.e))
	return out


func find_ev(ev: Array, e_name: String) -> Dictionary:
	for e in ev:
		if str(e.e) == e_name:
			return e
	return {}


func playable_keys(g: MauGame, seat: int) -> Array:
	var out: Array = []
	for id in g.view_for(seat).hints.playable:
		out.append(g._key[g.faces[g.side * g.n_cards + int(id)]])
	out.sort()
	return out


func sorted(a: Array) -> Array:
	var b := a.duplicate()
	b.sort()
	return b


# --- Fälle ---

func _matching() -> void:
	var g := make({"hands": [["hell_rot_3", "hell_blau_5", "hell_gelb_aussetzen", "hell_wuenscher", "hell_gruen_2"], ["hell_rot_1"], ["hell_rot_2"]],
		"top": "hell_rot_5"})
	check(playable_keys(g, 0) == sorted(["hell_rot_3", "hell_blau_5", "hell_wuenscher"]), "passend: Farbe, Zahl, Joker (%s)" % str(playable_keys(g, 0)))
	deny(g, 0, {"a": "play", "card": id_of(g, 0, "hell_gruen_2")}, "unpassende Karte")
	deny(g, 0, {"a": "play", "card": id_of(g, 0, "hell_gelb_aussetzen")}, "Aktion auf Zahl anderer Farbe")
	deny(g, 1, {"a": "play", "card": id_of(g, 1, "hell_rot_1")}, "nicht dran")
	deny(g, 0, {"a": "play", "card": id_of(g, 1, "hell_rot_1")}, "fremde Karte")
	deny(g, 0, {"a": "fliegen"}, "unbekannte Aktion")
	deny(g, 7, {"a": "draw"}, "unbekannter Platz")
	check(g.view_for(1).hints.playable.is_empty(), "wer nicht dran ist, hat keine spielbaren Karten")
	var ev := play(g, 0, "hell_blau_5", "Zahl auf gleiche Zahl")
	check(g.current_seat() == 1 and g.color == "blau" and RulesFixture.top_key(g) == "hell_blau_5", "nach Zahl: Nächster dran, Farbe blau")
	check(ev_names(ev) == ["play", "turn"], "Ereignisse play, turn (%s)" % str(ev_names(ev)))
	# Symbol passt auf Symbol
	g = make({"hands": [["hell_blau_aussetzen", "hell_blau_5", "hell_gelb_plus1"]], "top": "hell_gelb_aussetzen"})
	check(playable_keys(g, 0) == sorted(["hell_blau_aussetzen", "hell_gelb_plus1"]), "Aussetzen auf Aussetzen, Farbe gelb (%s)" % str(playable_keys(g, 0)))
	# Auf einem Joker zählt nur die Wunschfarbe
	g = make({"hands": [["hell_blau_1", "hell_rot_1", "hell_wuenscher_plus2", "hell_wuenscher"]], "top": "hell_wuenscher", "color": "blau"},
		{"wild_restriction": "free"})
	check(playable_keys(g, 0) == sorted(["hell_blau_1", "hell_wuenscher_plus2", "hell_wuenscher"]), "auf Joker: Wunschfarbe und Joker (%s)" % str(playable_keys(g, 0)))
	check(g.view_for(0).wish == true, "Wunschfarbe in der Sicht markiert")
	# dunkle Seite
	g = make({"side": "dunkel", "hands": [["dunkel_pink_3", "dunkel_lila_5", "dunkel_tuerkis_flip"]], "top": "dunkel_orange_5"})
	check(playable_keys(g, 0) == ["dunkel_lila_5"], "dunkel: Zahl passt (%s)" % str(playable_keys(g, 0)))


func _wish() -> void:
	var g := make({"hands": [["hell_wuenscher", "hell_rot_1"], ["hell_gruen_4", "hell_blau_4", "hell_wuenscher"], ["hell_rot_2"]], "top": "hell_rot_5"})
	var w := id_of(g, 0, "hell_wuenscher")
	check(g.view_for(0).hints.wild == [w], "hints.wild nennt den Joker")
	deny(g, 0, {"a": "play", "card": w}, "Wünscher ohne Farbe")
	deny(g, 0, {"a": "play", "card": w, "color": "pink"}, "Wünscher mit Farbe der anderen Seite")
	var ev := play(g, 0, "hell_wuenscher", "Wünscher mit Grün", "gruen")
	check(g.color == "gruen" and g.wished, "Wunschfarbe grün gesetzt")
	check(find_ev(ev, "color").get("color", "") == "gruen", "Ereignis color")
	check(playable_keys(g, 1) == sorted(["hell_gruen_4", "hell_wuenscher"]), "Nächster muss grün oder Joker legen (%s)" % str(playable_keys(g, 1)))
	# Wunsch der bisherigen Farbe ist erlaubt
	g = make({"hands": [["hell_wuenscher", "hell_rot_1"]], "top": "hell_rot_5"})
	play(g, 0, "hell_wuenscher", "Wünscher mit bisheriger Farbe", "rot")
	check(g.color == "rot", "bisherige Farbe wünschbar")


func _draw_cards() -> void:
	var g := make({"hands": [["hell_rot_plus1", "hell_rot_1"], ["hell_gelb_1"], ["hell_gelb_2"]], "top": "hell_rot_5"})
	var ev := play(g, 0, "hell_rot_plus1", "+1 legen")
	check(n_hand(g, 1) == 2 and g.current_seat() == 2, "+1: Nächster zieht 1 und setzt aus")
	check(ev_names(ev) == ["play", "pending", "draw", "skip", "turn"], "+1 Ereignisse (%s)" % str(ev_names(ev)))
	check(find_ev(ev, "draw").reason == "strafe" and int(find_ev(ev, "skip").seat) == 1, "+1 Strafe und Aussetzen")
	# +1 auf +1 ohne Stapeln: wirkt erst nach dem Ziehen, dann normal legbar
	check(g.pending.is_empty(), "ohne Stapeln keine offene Strafe")
	g = make({"side": "dunkel", "hands": [["dunkel_pink_plus5", "dunkel_pink_1"], ["dunkel_lila_1"], ["dunkel_lila_2"]], "top": "dunkel_pink_5"})
	play(g, 0, "dunkel_pink_plus5", "+5 legen")
	check(n_hand(g, 1) == 6 and g.current_seat() == 2, "+5: Nächster zieht 5 und setzt aus")
	g = make({"hands": [["hell_wuenscher_plus2", "hell_gelb_1"], ["hell_gelb_2"], ["hell_gelb_3"]], "top": "hell_rot_5"}, {"wild_restriction": "free"})
	play(g, 0, "hell_wuenscher_plus2", "Wünscher +2 (frei)", "blau")
	check(n_hand(g, 1) == 3 and g.current_seat() == 2 and g.color == "blau", "Wünscher +2: zieht 2, setzt aus, Farbe bleibt")


func _skip_reverse() -> void:
	var g := make({"hands": [["hell_rot_aussetzen", "hell_rot_1"], ["hell_rot_2"], ["hell_rot_3"]], "top": "hell_rot_5"})
	var ev := play(g, 0, "hell_rot_aussetzen", "Aussetzen")
	check(g.current_seat() == 2 and int(find_ev(ev, "skip").seat) == 1, "Aussetzen überspringt den Nächsten")
	g = make({"hands": [["hell_rot_richtungswechsel", "hell_rot_1"], ["hell_rot_2"], ["hell_rot_3", "hell_rot_4"]], "top": "hell_rot_5"})
	ev = play(g, 0, "hell_rot_richtungswechsel", "Richtungswechsel zu dritt")
	check(g.dir == -1 and g.current_seat() == 2, "Richtungswechsel: Richtung -1, Platz 2 dran")
	check(int(find_ev(ev, "reverse").dir) == -1, "Ereignis reverse")
	play(g, 2, "hell_rot_3", "nach Richtungswechsel")
	check(g.current_seat() == 1, "Richtung bleibt rückwärts")
	# zu zweit: wie Aussetzen (Option) bzw. ohne Wirkung
	g = make({"hands": [["hell_rot_richtungswechsel", "hell_rot_1"], ["hell_rot_2"]], "top": "hell_rot_5"}, {}, 2)
	ev = play(g, 0, "hell_rot_richtungswechsel", "Richtungswechsel zu zweit")
	check(g.current_seat() == 0 and find_ev(ev, "skip").get("seat", -1) == 1, "zu zweit wie Aussetzen")
	g = make({"hands": [["hell_rot_richtungswechsel", "hell_rot_1"], ["hell_rot_2"]], "top": "hell_rot_5"}, {"two_player_reverse_skips": false}, 2)
	play(g, 0, "hell_rot_richtungswechsel", "Richtungswechsel zu zweit ohne Option")
	check(g.current_seat() == 1, "zu zweit ohne Option: der andere ist dran")


func _skip_all() -> void:
	var g := make({"side": "dunkel", "hands": [["dunkel_pink_alle_aussetzen", "dunkel_pink_1", "dunkel_lila_1"], ["dunkel_pink_2"], ["dunkel_pink_3"]],
		"top": "dunkel_pink_5"})
	var ev := play(g, 0, "dunkel_pink_alle_aussetzen", "Alle aussetzen")
	check(g.current_seat() == 0 and g.state == "turn", "Alle aussetzen: Zusatzzug")
	check(ev_names(ev) == ["play", "skip_all", "turn"], "Ereignisse skip_all (%s)" % str(ev_names(ev)))
	play(g, 0, "dunkel_pink_1", "Zusatzzug normal legen")
	check(g.current_seat() == 1, "nach dem Zusatzzug geht es normal weiter")
	# Zusatzzug darf auch Ziehen sein
	g = make({"side": "dunkel", "hands": [["dunkel_pink_alle_aussetzen", "dunkel_lila_1", "dunkel_lila_2"]], "top": "dunkel_pink_5", "draw": ["dunkel_orange_9"]})
	play(g, 0, "dunkel_pink_alle_aussetzen", "Alle aussetzen 2")
	act(g, 0, {"a": "draw"}, "Zusatzzug: ziehen")
	check(g.current_seat() == 1 and n_hand(g, 0) == 3, "Zusatzzug gezogen, dann Nächster")


func _flip() -> void:
	# Grundfall: Ablage und Nachziehstapel umgekehrt, Seite gewechselt, Wunsch verfällt, Hände gewendet.
	var g := make({"hands": [["hell_rot_flip", "hell_gruen_1/dunkel_pink_9"], ["hell_gelb_1/dunkel_lila_4"], ["hell_gelb_2"]],
		"top": "hell_wuenscher", "color": "rot", "discard": ["hell_blau_4/dunkel_lila_6", "hell_gelb_7"],
		"draw": ["hell_gelb_8/dunkel_orange_1"], "draw_bottom": ["hell_gelb_9/dunkel_tuerkis_3"]})
	check(g.wished and g.color == "rot", "Ausgang: Wunschfarbe rot")
	var flip_id := id_of(g, 0, "hell_rot_flip")
	var ev := play(g, 0, "hell_rot_flip", "Flip legen")
	check(g.side == 1, "Flip: dunkle Seite aktiv")
	check(RulesFixture.top_key(g) == "dunkel_lila_6", "neue oberste Ablage = bisher unterste, andere Seite (%s)" % RulesFixture.top_key(g))
	check(int(g.discard[0]) == flip_id, "Flip-Karte liegt jetzt unten")
	check(g.color == "lila" and not g.wished, "Wunschfarbe verfallen, Farbe der neuen Oberkarte")
	check(RulesFixture.draw_key(g) == "dunkel_tuerkis_3", "oberste Nachziehkarte = bisher unterste (%s)" % RulesFixture.draw_key(g))
	check(g.view_for(1).draw_back == "hell_gelb_9", "Nachziehstapel zeigt die helle Gegenseite")
	check(RulesFixture.hand_keys(g, 0) == ["dunkel_pink_9"], "eigene Hand gewendet")
	check(g.view_for(1).hand[0].face == "dunkel_lila_4", "Hände der anderen gewendet")
	check(g.current_seat() == 1 and g.dir == 1, "danach normal der Nächste, Richtung bleibt")
	var fe := find_ev(ev, "flip")
	check(fe.get("side", "") == "dunkel" and fe.get("face", "") == "dunkel_lila_6", "Ereignis flip")
	# Flip auf Flip (Symbol) und zurück zur hellen Seite
	g = make({"side": "dunkel", "hands": [["dunkel_lila_flip", "dunkel_lila_1"]], "top": "dunkel_pink_flip", "discard": ["hell_rot_7/dunkel_pink_2"]})
	play(g, 0, "dunkel_lila_flip", "Flip auf Flip")
	check(g.side == 0 and RulesFixture.top_key(g) == "hell_rot_7" and g.color == "rot", "zurück auf hell, oben hell_rot_7")
	# Aktionskarte nach dem Flip wirkt nicht
	for back in ["dunkel_lila_plus5", "dunkel_lila_alle_aussetzen", "dunkel_lila_richtungswechsel", "dunkel_lila_flip"]:
		g = make({"hands": [["hell_rot_flip", "hell_rot_1"], ["hell_gelb_1"], ["hell_gelb_2"]], "top": "hell_rot_5", "discard": ["hell_blau_4/" + back]})
		ev = play(g, 0, "hell_rot_flip", "Flip mit %s unten" % back)
		check(g.current_seat() == 1 and n_hand(g, 1) == 1 and g.dir == 1 and g.pending.is_empty() and g.state == "turn",
			"%s nach Flip ohne Wirkung" % back)
		check(not ev_names(ev).has("skip") and not ev_names(ev).has("draw") and not ev_names(ev).has("skip_all"), "%s: keine Wirkungsereignisse" % back)
	# Joker nach dem Flip: Flip-Spieler wählt die Farbe, kein Ziehen
	for back in ["dunkel_farbjagd", "dunkel_wuenscher"]:
		g = make({"hands": [["hell_rot_flip", "hell_rot_1"], ["hell_gelb_1"], ["hell_gelb_2"]], "top": "hell_rot_5", "discard": ["hell_blau_4/" + back]})
		ev = play(g, 0, "hell_rot_flip", "Flip mit %s unten" % back)
		check(g.state == "color" and g.current_seat() == 0, "%s oben: Phase color, Flip-Spieler wählt" % back)
		check(g.view_for(0).hints.need_color and not g.view_for(1).hints.need_color, "need_color nur für den Flip-Spieler")
		check(find_ev(ev, "choose_color").get("seat", -1) == 0, "Ereignis choose_color")
		deny(g, 1, {"a": "color", "color": "pink"}, "Farbwahl von anderem Platz")
		deny(g, 0, {"a": "color", "color": "rot"}, "Farbwahl mit heller Farbe")
		deny(g, 0, {"a": "play", "card": int(g.hands[0][0])}, "Legen vor der Farbwahl")
		deny(g, 0, {"a": "draw"}, "Ziehen vor der Farbwahl")
		act(g, 0, {"a": "color", "color": "orange"}, "Farbe nach Flip wählen")
		check(g.color == "orange" and g.wished and g.current_seat() == 1 and n_hand(g, 1) == 1 and g.state == "turn",
			"%s: Farbe orange, Nächster ohne Strafe dran" % back)


func _start_card() -> void:
	var g := make({"hands": [[], [], []], "draw": ["hell_rot_plus1", "hell_wuenscher", "hell_blau_flip", "hell_gelb_3"]})
	# Ablage leeren: Oberkarte unter den Nachziehstapel.
	var old_top: int = g.discard.pop_back()
	g.draw_pile.push_front(old_top)
	var ev: Array = []
	g._reveal_start_card(ev)
	check(g.discard.size() == 4 and RulesFixture.top_key(g) == "hell_gelb_3", "Aktion, Joker, Flip ignoriert, Zahl oben (%d)" % g.discard.size())
	check(g.color == "gelb" and not g.wished, "Startfarbe gelb")
	var ignored := 0
	for e in ev:
		if e.e == "start" and e.ignored:
			ignored += 1
	check(ignored == 3, "drei Startkarten ignoriert (%d)" % ignored)
	check(RulesFixture.card_check(g) == "", "Startkarte: 112 Karten")
	# Eigenschaften über viele Seeds
	var bad := ""
	for s in 200:
		var cfg := RuleConfig.from_dict({"hand_size": 5 + s % 6})
		var n := 2 + s % 9
		var gg := MauGame.create(cfg, RulesFixture.players(n, "bot"), 1000003 * s + 17)
		var e2 := gg.start_round()
		var top_code := gg.faces[int(gg.discard.back())]
		if gg.side != 0 or CardDB.kind_table()[top_code] != "zahl":
			bad = "Startkarte keine helle Zahl"
		for i in range(gg.discard.size() - 1):
			if CardDB.kind_table()[gg.faces[int(gg.discard[i])]] == "zahl":
				bad = "Zahl unter der Startkarte"
		for p in n:
			if (gg.hands[p] as Array).size() != cfg.hand_size:
				bad = "Handgröße falsch"
		if gg.current_seat() != 1 % n or gg.dealer != 0:
			bad = "Geber/Startspieler falsch"
		if RulesFixture.card_check(gg) != "":
			bad = RulesFixture.card_check(gg)
		if gg.color != CardDB.color_table()[top_code]:
			bad = "Startfarbe falsch"
		if str(e2[0].e) != "round_start" or str(e2.back().e) != "turn":
			bad = "Startereignisse"
	check(bad == "", "Rundenstart über 200 Seeds: " + bad)


func _bluff_plus2() -> void:
	var base := {"hands": [["hell_wuenscher_plus2", "hell_gruen_1", "hell_gelb_2"], ["hell_gelb_3", "hell_blau_3"], ["hell_gelb_4"]], "top": "hell_rot_5"}
	var g := make(base)
	var ev := play(g, 0, "hell_wuenscher_plus2", "Wünscher +2 ehrlich", "blau")
	check(g.state == "challenge" and g.current_seat() == 1, "Phase challenge für das Opfer")
	var h: Dictionary = g.view_for(1).hints
	check(h.can_challenge and h.can_accept and h.can_draw and h.playable.is_empty(), "Opfer: anzweifeln/annehmen")
	check(not g.view_for(2).hints.can_challenge, "nur das Opfer zweifelt an")
	deny(g, 2, {"a": "challenge"}, "Anzweifeln durch Unbeteiligten")
	check(g.view_for(1).pending.get("kind", "") == "wuenscher_plus2" and not g.view_for(1).pending.has("legal"), "Sicht: pending ohne Prüfergebnis")
	act(g, 1, {"a": "accept"}, "annehmen")
	check(n_hand(g, 1) == 4 and g.current_seat() == 2 and g.color == "blau", "angenommen: +2, aussetzen, Farbe bleibt")
	# Ziehen in der Phase challenge = annehmen
	g = make(base)
	play(g, 0, "hell_wuenscher_plus2", "Wünscher +2", "blau")
	act(g, 1, {"a": "draw"}, "ziehen statt annehmen")
	check(n_hand(g, 1) == 4 and g.current_seat() == 2, "Ziehen nimmt die Strafe an")
	# ehrlich, angezweifelt: Herausforderer zieht 4 und setzt aus
	g = make(base)
	play(g, 0, "hell_wuenscher_plus2", "Wünscher +2", "blau")
	ev = act(g, 1, {"a": "challenge"}, "anzweifeln (ehrlich)")
	var ch := find_ev(ev, "challenge")
	check(ch.get("success", true) == false and n_hand(g, 1) == 6 and g.current_seat() == 2, "ehrlich: Herausforderer +4 und aussetzen")
	check(sorted(ch.get("hand", [])) == sorted(["hell_gruen_1", "hell_gelb_2"]), "Hand des Legers im Ereignis")
	check(g.events_for(1, ev)[0].has("hand") and not g.events_for(2, ev)[0].has("hand") and not g.events_for(0, ev)[0].has("hand"),
		"Hand nur für den Herausforderer")
	check(g.color == "blau", "Farbe bleibt nach dem Anzweifeln")
	# Bluff erwischt: Leger zieht 2, Herausforderer normal dran
	g = make({"hands": [["hell_wuenscher_plus2", "hell_rot_1", "hell_gelb_2"], ["hell_blau_3", "hell_gelb_3"], ["hell_gelb_4"]], "top": "hell_rot_5"})
	play(g, 0, "hell_wuenscher_plus2", "Wünscher +2 Bluff", "blau")
	ev = act(g, 1, {"a": "challenge"}, "anzweifeln (Bluff)")
	check(find_ev(ev, "challenge").get("success", false) == true, "Bluff erkannt")
	check(n_hand(g, 0) == 4 and n_hand(g, 1) == 2 and g.current_seat() == 1 and g.state == "turn", "Bluff: Leger +2, Herausforderer dran")
	check(g.color == "blau", "Wunschfarbe bleibt nach Bluff")
	check(playable_keys(g, 1) == ["hell_blau_3"], "Herausforderer legt normal")
	deny(g, 1, {"a": "challenge"}, "zweites Anzweifeln")
	# Joker auf der Hand zählen bei der Bluff-Prüfung (Option)
	for counts in [true, false]:
		g = make({"hands": [["hell_wuenscher_plus2", "hell_wuenscher", "hell_gelb_2"], ["hell_blau_3"], ["hell_gelb_4"]], "top": "hell_rot_5"},
			{"wild_counts_for_bluff": counts})
		play(g, 0, "hell_wuenscher_plus2", "Wünscher +2 mit zweitem Joker", "blau")
		ev = act(g, 1, {"a": "challenge"}, "anzweifeln")
		check(find_ev(ev, "challenge").get("success", null) == counts, "wild_counts_for_bluff=%s: Bluff=%s" % [counts, counts])


func _restriction_modes() -> void:
	# enforce: mit Karte der Farbe nicht legbar
	var g := make({"hands": [["hell_wuenscher_plus2", "hell_rot_1"], ["hell_gelb_3"], ["hell_gelb_4"]], "top": "hell_rot_5"}, {"wild_restriction": "enforce"})
	check(not playable_keys(g, 0).has("hell_wuenscher_plus2"), "enforce: +2 mit roter Karte nicht spielbar")
	var why := deny(g, 0, {"a": "play", "card": id_of(g, 0, "hell_wuenscher_plus2"), "color": "blau"}, "enforce: +2 abgelehnt")
	check(why.contains("nur, wenn"), "Begründung nennt die Bedingung (%s)" % why)
	g = make({"hands": [["hell_wuenscher_plus2", "hell_gelb_1"], ["hell_gelb_3"], ["hell_gelb_4"]], "top": "hell_rot_5"}, {"wild_restriction": "enforce"})
	play(g, 0, "hell_wuenscher_plus2", "enforce: +2 ohne rote Karte", "blau")
	check(g.state == "turn" and n_hand(g, 1) == 3 and g.current_seat() == 2, "enforce: kein Anzweifeln, Opfer zieht sofort")
	# enforce mit Joker-Zählung
	g = make({"hands": [["hell_wuenscher_plus2", "hell_wuenscher"], ["hell_gelb_3"]], "top": "hell_rot_5"}, {"wild_restriction": "enforce"})
	check(not playable_keys(g, 0).has("hell_wuenscher_plus2"), "enforce + Joker zählt: +2 gesperrt")
	g = make({"hands": [["hell_wuenscher_plus2", "hell_wuenscher"], ["hell_gelb_3"]], "top": "hell_rot_5"},
		{"wild_restriction": "enforce", "wild_counts_for_bluff": false})
	check(playable_keys(g, 0).has("hell_wuenscher_plus2"), "enforce ohne Joker-Zählung: +2 erlaubt")
	# free: immer, kein Anzweifeln
	g = make({"hands": [["hell_wuenscher_plus2", "hell_rot_1"], ["hell_gelb_3"], ["hell_gelb_4"]], "top": "hell_rot_5"}, {"wild_restriction": "free"})
	play(g, 0, "hell_wuenscher_plus2", "free: +2 trotz roter Karte", "blau")
	check(g.state == "turn" and n_hand(g, 1) == 3 and g.current_seat() == 2, "free: Opfer zieht sofort")


func _farbjagd() -> void:
	var jagd_draw := ["dunkel_pink_3", "dunkel_wuenscher", "dunkel_tuerkis_4", "dunkel_lila_7", "dunkel_orange_9"]
	var hands := [["dunkel_farbjagd", "dunkel_pink_1", "dunkel_tuerkis_2"], ["dunkel_pink_2"], ["dunkel_pink_4"]]
	var g := make({"side": "dunkel", "hands": hands, "top": "dunkel_orange_5", "draw": jagd_draw})
	play(g, 0, "dunkel_farbjagd", "Farbjagd", "lila")
	check(g.state == "challenge" and g.current_seat() == 1, "Farbjagd: Anzweifeln möglich")
	var ev := act(g, 1, {"a": "accept"}, "Farbjagd annehmen")
	check(n_hand(g, 1) == 5 and g.current_seat() == 2, "zieht bis Lila (4 Karten, Joker beendet nicht), behält alle, setzt aus (%d)" % n_hand(g, 1))
	check(RulesFixture.hand_keys(g, 1).has("dunkel_lila_7") and RulesFixture.hand_keys(g, 1).has("dunkel_wuenscher"), "gefundene Karte bleibt auf der Hand")
	check(int(find_ev(ev, "draw").count) == 4, "ein Zieh-Ereignis mit 4 Karten")
	# gezogener Joker beendet (Option)
	g = make({"side": "dunkel", "hands": hands, "top": "dunkel_orange_5", "draw": jagd_draw}, {"jagd_wild_stops": true})
	play(g, 0, "dunkel_farbjagd", "Farbjagd", "lila")
	act(g, 1, {"a": "accept"}, "Farbjagd annehmen")
	check(n_hand(g, 1) == 3, "jagd_wild_stops: Joker beendet die Jagd (%d)" % n_hand(g, 1))
	# ehrlich angezweifelt: bis zur Farbe, dann 2 weitere
	g = make({"side": "dunkel", "hands": hands, "top": "dunkel_orange_5", "draw": jagd_draw + ["dunkel_pink_6", "dunkel_pink_7"]})
	play(g, 0, "dunkel_farbjagd", "Farbjagd", "lila")
	ev = act(g, 1, {"a": "challenge"}, "Farbjagd anzweifeln (ehrlich)")
	check(find_ev(ev, "challenge").success == false and n_hand(g, 1) == 7 and g.current_seat() == 2, "ehrlich: bis Farbe + 2, aussetzen (%d)" % n_hand(g, 1))
	# Bluff erwischt: Leger zieht bis zur eigenen Wunschfarbe
	g = make({"side": "dunkel", "hands": [["dunkel_farbjagd", "dunkel_orange_1", "dunkel_tuerkis_2"], ["dunkel_pink_2"], ["dunkel_pink_4"]],
		"top": "dunkel_orange_5", "draw": jagd_draw})
	play(g, 0, "dunkel_farbjagd", "Farbjagd Bluff", "lila")
	ev = act(g, 1, {"a": "challenge"}, "Farbjagd anzweifeln (Bluff)")
	check(find_ev(ev, "challenge").success == true and n_hand(g, 0) == 6 and g.current_seat() == 1 and g.state == "turn",
		"Bluff: Leger zieht bis Lila (%d), Herausforderer dran" % n_hand(g, 0))
	check(g.color == "lila", "Farbjagd: Wunschfarbe bleibt")
	# Farbe in keinem Stapel mehr: Ziehen endet, Opfer setzt trotzdem aus
	g = make({"side": "dunkel", "hands": [["dunkel_farbjagd", "dunkel_pink_1"], ["dunkel_pink_2"], ["dunkel_pink_4"]], "top": "dunkel_orange_5",
		"draw": ["dunkel_pink_3", "dunkel_pink_5"], "rest": "discard"}, {"wild_restriction": "free"})
	# alle lila Karten aus Ablage und Stapel in die Hand von Platz 2
	var lila: Array = []
	for pile in [g.discard, g.draw_pile]:
		for id in pile.duplicate():
			if g._color[g.faces[g.n_cards + int(id)]] == "lila" and id != g.discard.back():
				pile.erase(id)
				lila.append(id)
	g.hands[2].append_array(lila)
	check(RulesFixture.card_check(g) == "", "Umbau ohne Lila: 112 Karten")
	var before := n_hand(g, 1)
	var total_free: int = g.draw_pile.size() + g.discard.size() - 1
	play(g, 0, "dunkel_farbjagd", "Farbjagd ohne erreichbare Farbe", "lila")
	check(n_hand(g, 1) == before + total_free + 1 and g.current_seat() == 2, "ohne Lila: alles gezogen, Opfer setzt aus (%d)" % n_hand(g, 1))


func _stacking() -> void:
	var opts := {"stacking": "same"}
	var g := make({"hands": [["hell_rot_plus1", "hell_rot_1"], ["hell_blau_plus1", "hell_blau_3", "hell_rot_aussetzen"], ["hell_gelb_4"]], "top": "hell_rot_5"}, opts)
	play(g, 0, "hell_rot_plus1", "+1 (Stapeln)")
	check(g.current_seat() == 1 and g.state == "turn" and int(g.pending.amount) == 1 and n_hand(g, 1) == 3, "offene Strafe 1 für Platz 1")
	check(playable_keys(g, 1) == ["hell_blau_plus1"], "nur gleiche Ziehkarte legbar (%s)" % str(playable_keys(g, 1)))
	deny(g, 1, {"a": "play", "card": id_of(g, 1, "hell_rot_aussetzen")}, "Aussetzen auf offene +1")
	play(g, 1, "hell_blau_plus1", "+1 auf +1")
	check(g.current_seat() == 2 and int(g.pending.amount) == 2 and int(g.pending.victim) == 2, "Summe wandert weiter: 2")
	check(g.view_for(2).hints.playable.is_empty() and g.view_for(2).hints.can_draw, "Platz 2 kann nur ziehen")
	act(g, 2, {"a": "draw"}, "Strafe nehmen")
	check(n_hand(g, 2) == 3 and g.current_seat() == 0 and g.pending.is_empty(), "Platz 2 zieht 2 und setzt aus")
	# Wünscher +2 im Bluff-Modus gestapelt, Bluff im Stapel erwischt: Leger zieht die ganze Summe
	g = make({"hands": [["hell_wuenscher_plus2", "hell_gelb_1"], ["hell_wuenscher_plus2", "hell_blau_3"], ["hell_gelb_4"]], "top": "hell_rot_5"}, opts)
	play(g, 0, "hell_wuenscher_plus2", "+2 (Stapeln)", "blau")
	check(g.state == "challenge" and playable_keys(g, 1) == ["hell_wuenscher_plus2"], "Opfer darf +2 drauflegen")
	play(g, 1, "hell_wuenscher_plus2", "+2 auf +2 (Bluff: hat Blau)", "gruen")
	check(g.state == "challenge" and g.current_seat() == 2 and int(g.pending.amount) == 4, "Summe 4 bei Platz 2")
	var ev := act(g, 2, {"a": "challenge"}, "Stapel anzweifeln")
	check(find_ev(ev, "challenge").success == true and n_hand(g, 1) == 5 and g.current_seat() == 2, "Bluff im Stapel: Leger zieht 4 (%d)" % n_hand(g, 1))
	# ehrlich im Stapel: Herausforderer zieht Summe + 2
	g = make({"hands": [["hell_wuenscher_plus2", "hell_gelb_1"], ["hell_wuenscher_plus2", "hell_gelb_3"], ["hell_gelb_4"]], "top": "hell_rot_5"}, opts)
	play(g, 0, "hell_wuenscher_plus2", "+2", "blau")
	play(g, 1, "hell_wuenscher_plus2", "+2 auf +2 (ehrlich)", "gruen")
	act(g, 2, {"a": "challenge"}, "Stapel anzweifeln (ehrlich)")
	check(n_hand(g, 2) == 7 and g.current_seat() == 0, "ehrlich im Stapel: Herausforderer zieht 6 (%d)" % n_hand(g, 2))
	# Farbjagd weitergeben: das letzte Opfer zieht bis zur zuletzt gewünschten Farbe
	g = make({"side": "dunkel", "hands": [["dunkel_farbjagd", "dunkel_pink_1"], ["dunkel_farbjagd", "dunkel_pink_2"], ["dunkel_pink_4"]],
		"top": "dunkel_orange_5", "draw": ["dunkel_lila_1", "dunkel_pink_3", "dunkel_tuerkis_9"]}, {"stacking": "same", "wild_restriction": "free"})
	play(g, 0, "dunkel_farbjagd", "Farbjagd (Stapeln)", "lila")
	check(g.current_seat() == 1 and playable_keys(g, 1) == ["dunkel_farbjagd"], "Farbjagd weitergeben möglich")
	play(g, 1, "dunkel_farbjagd", "Farbjagd weitergeben", "tuerkis")
	act(g, 2, {"a": "draw"}, "letztes Opfer zieht")
	check(n_hand(g, 2) == 4 and g.current_seat() == 0, "letztes Opfer zieht bis Türkis (3 Karten)")
	# +5 gestapelt auf der dunklen Seite
	g = make({"side": "dunkel", "hands": [["dunkel_pink_plus5", "dunkel_pink_1"], ["dunkel_lila_plus5", "dunkel_pink_2"], ["dunkel_pink_4"]],
		"top": "dunkel_pink_5"}, opts)
	play(g, 0, "dunkel_pink_plus5", "+5")
	play(g, 1, "dunkel_lila_plus5", "+5 auf +5")
	act(g, 2, {"a": "draw"}, "10 ziehen")
	check(n_hand(g, 2) == 11, "+5 gestapelt: 10 Karten")


func _last_card() -> void:
	# Ziehkarte als letzte Karte: Der Nächste zieht trotzdem, Wertung zählt sie mit.
	var g := make({"hands": [["hell_rot_plus1"], ["hell_gelb_1"], ["hell_gelb_2"]], "top": "hell_rot_5", "draw": ["hell_blau_9"]}, {"scoring": "points500"})
	var ev := play(g, 0, "hell_rot_plus1", "letzte Karte +1")
	check(g.state == "round_over" and n_hand(g, 1) == 2, "Runde vorbei, Platz 1 hat trotzdem gezogen")
	check(int(g.scores[0]) == 1 + 9 + 2, "Sieger bekommt auch die gezogene Karte (%d)" % int(g.scores[0]))
	check(ev_names(ev).has("finish") and ev_names(ev).has("round_over"), "Ereignisse finish, round_over")
	check(g.current_seat() == -1 and g.view_for(0).hints.can_next_round and not g.view_for(1).hints.can_next_round, "nach der Runde: nur Platz 0 startet neu")
	# Gestapelte Strafe als letzte Karte addiert sich
	g = make({"hands": [["hell_gelb_plus1"], ["hell_gelb_1"], ["hell_gelb_2"]], "top": "hell_rot_plus1", "draw": ["hell_blau_9", "hell_blau_8"]}, {"stacking": "same"})
	g.pending = {"kind": "plus1", "amount": 1, "by": 2, "victim": 0, "color": "rot", "legal": true, "snap": [], "finisher": false}
	play(g, 0, "hell_gelb_plus1", "letzte Karte auf offene +1")
	check(g.state == "round_over" and n_hand(g, 1) == 3, "gestapelt als letzte Karte: Nächster zieht 2")
	# Wünscher +2 als letzte Karte im Bluff-Modus: erst anzweifeln, dann fertig
	g = make({"hands": [["hell_wuenscher_plus2"], ["hell_gelb_1"], ["hell_gelb_2"]], "top": "hell_rot_5"}, {"stacking": "same"})
	play(g, 0, "hell_wuenscher_plus2", "letzte Karte Wünscher +2", "blau")
	check(g.state == "challenge" and g.place[0] == 0, "noch nicht fertig, Anzweifeln offen")
	check(g.view_for(1).hints.playable.is_empty(), "kein Stapeln auf die letzte Karte")
	act(g, 1, {"a": "challenge"}, "letzte Karte anzweifeln")
	check(g.state == "round_over" and n_hand(g, 1) == 5 and int(g.result.ranking[0]) == 0, "ehrlich (leere Hand): Herausforderer +4, Platz 0 gewinnt")
	# Flip als letzte Karte: ausführen, Wertung auf der neuen Seite (bzw. nicht ausführen)
	for mode in ["execute", "ignore"]:
		g = make({"hands": [["hell_rot_flip"], ["hell_blau_1/dunkel_farbjagd"], ["hell_gelb_2/dunkel_pink_2"]], "top": "hell_rot_5",
			"discard": ["hell_blau_4/dunkel_lila_6"]}, {"flip_last_card": mode, "scoring": "points500"})
		ev = play(g, 0, "hell_rot_flip", "letzte Karte Flip (%s)" % mode)
		check(g.state == "round_over", "Flip als letzte Karte beendet die Runde")
		if mode == "execute":
			check(g.side == 1 and int(g.scores[0]) == 62 and g.result.side == "dunkel", "Flip ausgeführt, Wertung dunkel (%d)" % int(g.scores[0]))
			check(ev_names(ev).has("flip"), "Ereignis flip")
		else:
			check(g.side == 0 and int(g.scores[0]) == 3 and not ev_names(ev).has("flip"), "Flip nicht ausgeführt, Wertung hell (%d)" % int(g.scores[0]))
	# Aussetzen als letzte Karte: Runde endet, keine Wirkung
	g = make({"hands": [["hell_rot_aussetzen"], ["hell_gelb_1"], ["hell_gelb_2"]], "top": "hell_rot_5"})
	ev = play(g, 0, "hell_rot_aussetzen", "letzte Karte Aussetzen")
	check(g.state == "round_over" and not ev_names(ev).has("skip"), "Aussetzen als letzte Karte ohne Bedeutung")
	# Joker als letzte Karte erlaubt
	g = make({"hands": [["hell_wuenscher"], ["hell_gelb_1"]], "top": "hell_rot_5"}, {}, 2)
	play(g, 0, "hell_wuenscher", "letzte Karte Wünscher", "gelb")
	check(g.state == "round_over", "mit Joker fertig")


func _piles() -> void:
	# Nachziehstapel leer: Ablage außer der obersten mischen, Wunschfarbe bleibt.
	var g := make({"hands": [["hell_blau_1"], ["hell_rot_1"], ["hell_rot_2"]], "top": "hell_wuenscher", "color": "gruen",
		"discard": ["hell_gelb_1", "hell_gelb_2", "hell_gelb_3"], "rest": "discard"})
	check(g.draw_pile.is_empty(), "Nachziehstapel leer")
	var top_id: int = g.discard.back()
	var under: int = g.discard.size() - 1
	var ev := act(g, 0, {"a": "draw"}, "Ziehen mit leerem Stapel")
	check(ev_names(ev).has("shuffle"), "Ereignis shuffle")
	check(g.discard.size() == 1 and int(g.discard[0]) == top_id, "oberste Karte bleibt liegen")
	check(g.draw_pile.size() == under - 1 and n_hand(g, 0) == 2, "Rest gemischt und eine gezogen")
	check(g.color == "gruen" and g.wished, "Wunschfarbe bleibt nach dem Mischen")
	check(int(find_ev(ev, "shuffle").count) == under, "shuffle nennt die Kartenzahl")
	# Beide leer: Ziehen entfällt (aussetzen); mit passender Karte nicht erlaubt
	g = make({"hands": [["hell_blau_1"], ["hell_rot_1"], []], "top": "hell_rot_5"})
	g.hands[2].append_array(g.draw_pile)
	g.draw_pile.clear()
	check(RulesFixture.card_check(g) == "", "Umbau: 112 Karten")
	check(g.view_for(0).hints.can_draw, "nichts passt: Ziehen (= aussetzen) möglich")
	ev = act(g, 0, {"a": "draw"}, "Ziehen ohne Karten")
	check(ev_names(ev) == ["pass", "turn"] and g.current_seat() == 1 and n_hand(g, 0) == 1, "Ziehen entfällt, Nächster dran (%s)" % str(ev_names(ev)))
	check(not g.view_for(1).hints.can_draw, "mit passender Karte und leeren Stapeln kein Ziehen")
	deny(g, 1, {"a": "draw"}, "Ziehen trotz passender Karte bei leeren Stapeln")
	# Offene Strafe bei leeren Stapeln: nur die alte Oberkarte ist zu mischen, der Rest verfällt, Opfer setzt trotzdem aus
	g = make({"side": "dunkel", "hands": [["dunkel_pink_plus5", "dunkel_pink_2"], ["dunkel_lila_1"], []], "top": "dunkel_pink_5"})
	g.hands[2].append_array(g.draw_pile)
	g.draw_pile.clear()
	play(g, 0, "dunkel_pink_plus5", "+5 bei leeren Stapeln")
	check(n_hand(g, 1) == 2 and g.current_seat() == 2 and g.discard.size() == 1, "Strafe verfällt bis auf 1 Karte, Opfer setzt aus (%d)" % n_hand(g, 1))
	# Stillstand: Zwei Nachbarn reichen sich zwei Richtungswechsel hin und her (Mischen gibt immer die eben gelegte Karte zurück,
	# die gezogene Karte muss gelegt werden). Beim dritten Mal derselben Lage endet die Runde.
	g = make({"hands": [["hell_gelb_1"], ["hell_gelb_2"], []], "top": "hell_rot_richtungswechsel", "discard": ["hell_blau_richtungswechsel"],
		"current": 1}, {"drawn_card": "must", "mau_call": "off"})
	g.hands[2].append_array(g.draw_pile)
	g.draw_pile.clear()
	var loops := 0
	while g.state in MauGame.PLAY_PHASES and loops < 60:
		loops += 1
		var s := g.current_seat()
		if g.state == "drawn":
			act(g, s, {"a": "play", "card": g.drawn_id}, "gezogenen Richtungswechsel legen")
		else:
			act(g, s, {"a": "draw"}, "ziehen im Stillstand")
		check(g.state == "round_over" or g.current_seat() != 2, "Platz 2 kommt im Stillstand nie dran")
	check(g.state == "round_over" and g.result.reason == "blockiert" and loops < 20, "Stillstand beendet die Runde (%d Aktionen)" % loops)
	check(g.result.ranking == [0, 1, 2], "Stillstand: wenigste Karten vorn (%s)" % str(g.result.ranking))
	# Rundreise mit Stillstandszähler
	g = make({"hands": [["hell_gelb_1"], ["hell_gelb_2"], []], "top": "hell_rot_richtungswechsel", "discard": ["hell_blau_richtungswechsel"],
		"current": 1}, {"drawn_card": "must", "mau_call": "off"})
	g.hands[2].append_array(g.draw_pile)
	g.draw_pile.clear()
	for k in 5:
		g.apply(g.current_seat(), {"a": "play", "card": g.drawn_id} if g.state == "drawn" else {"a": "draw"})
	check(not g.seen.is_empty(), "Stillstandszähler läuft")
	var copy := MauGame.from_dict(JSON.parse_string(JSON.stringify(g.to_dict())))
	check(JSON.stringify(copy.to_dict()) == JSON.stringify(g.to_dict()), "Stillstandszähler übersteht Speichern")
	# Sicherung: Kann reihum niemand legen, endet die Runde (blockiert)
	g = make({"hands": [["hell_blau_1"], ["hell_blau_2"], []], "top": "hell_rot_5"})
	g.hands[2].append_array(g.draw_pile)
	g.draw_pile.clear()
	g.pass_streak = 2
	ev = act(g, 0, {"a": "draw"}, "dritter Pass in Folge")
	check(g.state == "round_over" and g.result.reason == "blockiert" and int(g.result.ranking[0]) == 0, "blockiert: wenigste Karten gewinnt")


func _mau() -> void:
	var spec := {"hands": [["hell_rot_1", "hell_rot_2"], ["hell_rot_3", "hell_rot_4"], ["hell_rot_6", "hell_rot_7", "hell_rot_8"]], "top": "hell_rot_5"}
	# vergessen und erwischt
	var g := make(spec)
	check(g.view_for(0).hints.can_mau and not g.view_for(1).hints.can_mau and not g.view_for(2).hints.can_mau, "Mau nur mit 2 Karten am Zug")
	check(g.view_for(0).hints.text.contains("Mau"), "Hinweis erinnert an Mau")
	play(g, 0, "hell_rot_1", "vorletzte Karte ohne Mau")
	check(g.mau_open == 0 and g.view_for(1).hints.catch == [0] and g.view_for(2).hints.catch == [0] and g.view_for(0).hints.catch.is_empty(),
		"erwischbar für die anderen")
	check(g.view_for(-1).hints.catch.is_empty(), "Zuschauer erwischt nicht")
	deny(g, 0, {"a": "catch", "target": 0}, "sich selbst erwischen")
	var ev := act(g, 2, {"a": "catch", "target": 0}, "erwischen")
	check(n_hand(g, 0) == 3 and ev_names(ev) == ["catch", "penalty", "draw"], "erwischt: 2 Strafkarten (%s)" % str(ev_names(ev)))
	deny(g, 1, {"a": "catch", "target": 0}, "zweimal erwischen")
	# selbst gerufen vor dem Legen
	g = make(spec)
	ev = act(g, 0, {"a": "mau"}, "Mau rufen")
	check(ev_names(ev) == ["mau"] and g.view_for(1).players[0].mau, "Mau in Ereignis und Sicht")
	deny(g, 0, {"a": "mau"}, "zweimal rufen")
	play(g, 0, "hell_rot_1", "nach Mau legen")
	check(g.mau_open == -1 and g.view_for(1).hints.catch.is_empty(), "gerufen: nicht erwischbar")
	deny(g, 1, {"a": "catch", "target": 0}, "Erwischen nach Ruf")
	# nach dem Legen rufen, bevor der nächste Zug beginnt
	g = make(spec)
	play(g, 0, "hell_rot_1", "legen ohne Mau")
	check(g.view_for(0).hints.can_mau, "nach dem Legen noch rufbar")
	act(g, 0, {"a": "mau"}, "nachträglich rufen")
	check(g.mau_open == -1, "nachträglich gerufen: sicher")
	# Fenster schließt mit der ersten Handlung des Nächsten
	g = make(spec)
	play(g, 0, "hell_rot_1", "legen ohne Mau")
	play(g, 1, "hell_rot_3", "Nächster beginnt seinen Zug")
	deny(g, 2, {"a": "catch", "target": 0}, "zu spät erwischt")
	deny(g, 0, {"a": "mau"}, "zu spät gerufen")
	# automatisch: Strafe beim Fensterende
	g = make(spec, {"mau_call": "auto", "mau_penalty": 1})
	play(g, 0, "hell_rot_1", "legen ohne Mau (auto)")
	check(n_hand(g, 0) == 1, "noch keine Strafe")
	deny(g, 1, {"a": "catch", "target": 0}, "Erwischen im Modus auto")
	ev = play(g, 1, "hell_rot_3", "Nächster beginnt (auto)")
	check(n_hand(g, 0) == 2 and ev_names(ev)[0] == "penalty", "auto: 1 Strafkarte beim Zugbeginn des Nächsten")
	# Erinnerung: keine Strafe, kein Erwischen
	g = make(spec, {"mau_call": "reminder"})
	play(g, 0, "hell_rot_1", "legen ohne Mau (reminder)")
	check(g.view_for(1).hints.catch.is_empty(), "reminder: nicht erwischbar")
	deny(g, 1, {"a": "catch", "target": 0}, "Erwischen im Modus reminder")
	play(g, 1, "hell_rot_3", "weiter (reminder)")
	check(n_hand(g, 0) == 1, "reminder: keine Strafe")
	# aus
	g = make(spec, {"mau_call": "off"})
	check(not g.view_for(0).hints.can_mau, "off: kein Mau-Knopf")
	deny(g, 0, {"a": "mau"}, "Mau bei off")
	# Mau mit 3 Karten oder außerhalb des Zugs nicht möglich
	g = make(spec)
	deny(g, 2, {"a": "mau"}, "Mau mit 3 Karten")
	deny(g, 1, {"a": "mau"}, "Mau mit 2 Karten, nicht dran")
	# Alle aussetzen: Fenster endet mit dem eigenen Zusatzzug
	g = make({"side": "dunkel", "hands": [["dunkel_pink_alle_aussetzen", "dunkel_pink_1"], ["dunkel_pink_3"], ["dunkel_pink_4"]], "top": "dunkel_pink_5"})
	play(g, 0, "dunkel_pink_alle_aussetzen", "Alle aussetzen auf 1 Karte")
	check(g.view_for(1).hints.catch == [0], "erwischbar vor dem Zusatzzug")
	act(g, 0, {"a": "draw"}, "Zusatzzug beginnt")
	deny(g, 1, {"a": "catch", "target": 0}, "nach Beginn des Zusatzzugs zu spät")
	# Mau gilt nur bis zum nächsten Kartenzuwachs (hier: freiwillig ziehen trotz passender Karte)
	g = make({"hands": [["hell_gelb_1", "hell_blau_2"], ["hell_rot_3"], ["hell_rot_6"]], "top": "hell_gelb_5", "draw": ["hell_gelb_9"]})
	act(g, 0, {"a": "mau"}, "Mau rufen, dann ziehen")
	act(g, 0, {"a": "draw"}, "ziehen nach Mau")
	check(not g.mau_said[0] and not g.view_for(1).players[0].mau, "nach dem Ziehen ist der Ruf verfallen")


func _round_end_last() -> void:
	var opts := {"round_end": "last"}
	var g := make({"hands": [["hell_rot_1"], ["hell_rot_2", "hell_gelb_2"], ["hell_rot_3", "hell_rot_4"]], "top": "hell_rot_5"}, opts)
	var ev := play(g, 0, "hell_rot_1", "erster fertig (bis zum Letzten)")
	check(g.state == "turn" and g.place[0] == 1 and g.current_seat() == 1, "Runde läuft weiter, Platz 1 vergeben")
	check(find_ev(ev, "finish").get("place", 0) == 1, "Ereignis finish")
	check(g.view_for(2).players[0].place == 1 and g.view_for(1).ranking == [0], "Platzierung in der Sicht")
	play(g, 1, "hell_rot_2", "Platz 1 legt")
	play(g, 2, "hell_rot_3", "Platz 2 legt")
	check(g.current_seat() == 1, "fertige Spieler werden übersprungen")
	check(not g.view_for(1).hints.text.is_empty() and g.view_for(0).hints.text.contains("Du bist fertig (Platz 1)"),
		"Hinweis für Fertige: " + str(g.view_for(0).hints.text))
	# Zusatzzug-Sonderfall: fertig mit Alle aussetzen → der Nächste macht weiter
	g = make({"side": "dunkel", "hands": [["dunkel_pink_alle_aussetzen"], ["dunkel_pink_2"], ["dunkel_pink_3"]], "top": "dunkel_pink_5"}, opts)
	play(g, 0, "dunkel_pink_alle_aussetzen", "fertig mit Alle aussetzen")
	check(g.state == "turn" and g.current_seat() == 1, "Zusatzzug entfällt, Platz 1 dran")
	# Ziehkarte als letzte Karte, Runde läuft weiter
	g = make({"hands": [["hell_rot_plus1"], ["hell_rot_2"], ["hell_rot_3"]], "top": "hell_rot_5"}, opts)
	play(g, 0, "hell_rot_plus1", "fertig mit +1")
	check(n_hand(g, 1) == 2 and g.current_seat() == 2, "Nächster zieht und setzt aus")
	# Runde endet, wenn nur noch einer Karten hat; Platzierungen
	g = make({"hands": [["hell_rot_1"], ["hell_rot_2"], ["hell_rot_3", "hell_gelb_7"]], "top": "hell_rot_5", "finished": []}, opts)
	play(g, 0, "hell_rot_1", "Platz 0 fertig")
	play(g, 1, "hell_rot_2", "Platz 1 fertig")
	check(g.state == "round_over" and g.result.ranking == [0, 1, 2] and int(g.scores[0]) == 1, "Platzierungen 0, 1, 2; Sieg gezählt")
	# Zweierregel bei 2 Verbleibenden
	g = make({"hands": [["hell_rot_1"], ["hell_rot_richtungswechsel", "hell_rot_2"], ["hell_rot_3"]], "top": "hell_rot_5"}, opts)
	play(g, 0, "hell_rot_1", "Platz 0 fertig")
	play(g, 1, "hell_rot_richtungswechsel", "Richtungswechsel bei 2 Verbleibenden")
	check(g.current_seat() == 1, "Zweierregel: Richtungswechsel wirkt wie Aussetzen")


func _scoring() -> void:
	var g := make({"hands": [["hell_rot_1"], ["hell_blau_9", "hell_wuenscher"], ["hell_gelb_plus1"]], "top": "hell_rot_5"}, {"scoring": "points500"})
	var ev := play(g, 0, "hell_rot_1", "Runde gewinnen (Punkte)")
	check(int(g.scores[0]) == 59 and g.state == "round_over", "Sieger bekommt 49 + 10 = 59 (%d)" % int(g.scores[0]))
	var ro := find_ev(ev, "round_over")
	check(ro.get("points", []) == [0, 49, 10] and ro.get("gains", []) == [59, 0, 0], "round_over nennt Punkte und Gewinne")
	check(g.view_for(1).result.hands[1] == ["hell_blau_9", "hell_wuenscher"], "Resthände nach der Runde sichtbar")
	deny(g, 1, {"a": "next_round"}, "nächste Runde nicht von Platz 1")
	deny(g, 1, {"a": "draw"}, "Ziehen nach Rundenende")
	ev = act(g, 0, {"a": "next_round"}, "nächste Runde")
	check(g.round_no == 2 and g.dealer == 1 and g.current_seat() == 2 and g.state == "turn", "Runde 2: Geber 1, Platz 2 beginnt")
	check(n_hand(g, 0) == 7 and n_hand(g, 1) == 7 and n_hand(g, 2) == 7 and int(g.scores[0]) == 59, "neu ausgeteilt, Punkte bleiben")
	check(g.place == [0, 0, 0] and g.result.is_empty(), "Platzierungen zurückgesetzt")
	# Partieende
	g = make({"hands": [["hell_rot_1"], ["hell_blau_9", "hell_wuenscher"], ["hell_gelb_plus1"]], "top": "hell_rot_5", "scores": [480, 100, 0]},
		{"scoring": "points500"})
	ev = play(g, 0, "hell_rot_1", "Partie gewinnen")
	check(g.state == "game_over" and g.is_over() and find_ev(ev, "game_over").get("winner", -1) == 0, "game_over bei 500")
	deny(g, 0, {"a": "next_round"}, "keine Runde nach Partieende")
	# eigenes Ziel
	g = make({"hands": [["hell_rot_1"], ["hell_blau_9"], ["hell_gelb_plus1"]], "top": "hell_rot_5"}, {"scoring": "points500", "target": 100})
	g.scores = [90, 0, 0]
	play(g, 0, "hell_rot_1", "Ziel 100")
	check(g.state == "game_over", "target 100 erreicht")
	# ohne Wertung: Siege zählen, keine Partieende
	g = make({"hands": [["hell_rot_1"], ["hell_blau_9"], ["hell_gelb_plus1"]], "top": "hell_rot_5"})
	play(g, 0, "hell_rot_1", "Runde ohne Wertung")
	check(g.state == "round_over" and g.scores == [1, 0, 0] and not g.is_over(), "ohne Wertung: Sieg gezählt")


func _draw_rules() -> void:
	# bis spielbar ziehen
	var g := make({"hands": [["hell_blau_1"], ["hell_gelb_1"]], "top": "hell_rot_5", "draw": ["hell_gelb_2", "hell_gruen_3", "hell_rot_9", "hell_blau_7"]},
		{"draw_rule": "until_playable"})
	var ev := act(g, 0, {"a": "draw"}, "bis spielbar ziehen")
	check(n_hand(g, 0) == 4 and g.state == "drawn", "3 Karten gezogen, Phase drawn")
	check(playable_keys(g, 0) == ["hell_rot_9"] and g.view_for(0).drawn == RulesFixture.card(g, 0, "hell_rot_9"), "nur die gezogene Karte legbar")
	check(g.view_for(1).drawn == -1, "andere sehen die gezogene id nicht")
	check(int(find_ev(ev, "draw").count) == 3, "ein Ereignis mit 3 Karten")
	act(g, 0, {"a": "keep"}, "behalten")
	check(g.current_seat() == 1 and g.state == "turn", "nach Behalten ist der Nächste dran")
	# eine Karte: passt sie nicht, endet der Zug
	g = make({"hands": [["hell_blau_1"], ["hell_gelb_1"]], "top": "hell_rot_5", "draw": ["hell_gelb_2"]})
	act(g, 0, {"a": "draw"}, "eine Karte ziehen (passt nicht)")
	check(g.current_seat() == 1 and n_hand(g, 0) == 2, "unpassend gezogen: Zug endet")
	# darf: legen
	g = make({"hands": [["hell_blau_1"], ["hell_gelb_1"]], "top": "hell_rot_5", "draw": ["hell_rot_9"]})
	act(g, 0, {"a": "draw"}, "passende Karte ziehen")
	check(g.state == "drawn" and g.view_for(0).hints.can_keep and not g.view_for(0).hints.can_draw, "drawn: legen oder behalten")
	deny(g, 0, {"a": "draw"}, "zweimal ziehen")
	deny(g, 0, {"a": "play", "card": id_of(g, 0, "hell_blau_1")}, "andere Karte nach dem Ziehen")
	play(g, 0, "hell_rot_9", "gezogene Karte legen")
	check(g.current_seat() == 1 and RulesFixture.top_key(g) == "hell_rot_9", "gezogene Karte gelegt")
	# freiwillig ziehen trotz passender Karte, dann nur die gezogene
	g = make({"hands": [["hell_rot_1"], ["hell_gelb_1"]], "top": "hell_rot_5", "draw": ["hell_rot_7"]})
	act(g, 0, {"a": "draw"}, "freiwillig ziehen")
	check(playable_keys(g, 0) == ["hell_rot_7"], "nach freiwilligem Ziehen nur die gezogene Karte")
	# muss
	g = make({"hands": [["hell_blau_1"], ["hell_gelb_1"]], "top": "hell_rot_5", "draw": ["hell_rot_9"]}, {"drawn_card": "must"})
	act(g, 0, {"a": "draw"}, "ziehen (muss)")
	check(not g.view_for(0).hints.can_keep, "muss: kein Behalten")
	deny(g, 0, {"a": "keep"}, "Behalten bei muss")
	play(g, 0, "hell_rot_9", "gezogene Karte legen (muss)")
	# darf nicht
	g = make({"hands": [["hell_blau_1"], ["hell_gelb_1"]], "top": "hell_rot_5", "draw": ["hell_rot_9"]}, {"drawn_card": "may_not"})
	act(g, 0, {"a": "draw"}, "ziehen (darf nicht)")
	check(g.current_seat() == 1 and n_hand(g, 0) == 2, "darf nicht: Zug endet sofort")
	deny(g, 0, {"a": "keep"}, "Behalten außerhalb von drawn")
	# bis spielbar + enforce: gesperrter Wünscher +2 zählt nicht als passend
	g = make({"hands": [["hell_rot_1"], ["hell_gelb_1"]], "top": "hell_rot_5", "draw": ["hell_wuenscher_plus2", "hell_gelb_2", "hell_rot_3"]},
		{"draw_rule": "until_playable", "wild_restriction": "enforce"})
	act(g, 0, {"a": "draw"}, "bis spielbar (enforce)")
	check(n_hand(g, 0) == 4 and playable_keys(g, 0) == ["hell_rot_3"], "enforce: gesperrter Joker zählt nicht als passend (%d)" % n_hand(g, 0))


func _two_players() -> void:
	var g := make({"hands": [["hell_rot_plus1", "hell_rot_1"], ["hell_gelb_1"]], "top": "hell_rot_5"}, {}, 2)
	play(g, 0, "hell_rot_plus1", "+1 zu zweit")
	check(n_hand(g, 1) == 2 and g.current_seat() == 0, "zu zweit: Leger wieder dran")
	g = make({"hands": [["hell_rot_aussetzen", "hell_rot_1"], ["hell_gelb_1"]], "top": "hell_rot_5"}, {}, 2)
	play(g, 0, "hell_rot_aussetzen", "Aussetzen zu zweit")
	check(g.current_seat() == 0, "zu zweit: Aussetzen = nochmal")
	g = make({"side": "dunkel", "hands": [["dunkel_pink_alle_aussetzen", "dunkel_pink_1"], ["dunkel_lila_1"]], "top": "dunkel_pink_5"}, {}, 2)
	play(g, 0, "dunkel_pink_alle_aussetzen", "Alle aussetzen zu zweit")
	check(g.current_seat() == 0, "zu zweit: Alle aussetzen = nochmal")


func _hint_texts() -> void:
	var g := make({"hands": [["hell_blau_3", "hell_gelb_1", "hell_rot_2"], ["hell_rot_1"], ["hell_rot_2"]], "top": "hell_blau_7"})
	var t := str(g.view_for(0).hints.text)
	check(t.begins_with("Du bist dran – lege Blau oder eine 7"), "Hinweis: " + t)
	check(str(g.view_for(1).hints.text) == "Anna ist dran.", "Hinweis für andere: " + str(g.view_for(1).hints.text))
	check(str(g.view_for(-1).hints.text) == "Anna ist dran.", "Hinweis Zuschauer")
	g = make({"hands": [["hell_gruen_1"], ["hell_rot_1"]], "top": "hell_blau_7"})
	check(str(g.view_for(0).hints.text).contains("nichts passt"), "Hinweis: nichts passt")
	g = make({"hands": [["hell_gruen_1", "hell_gelb_1"], ["hell_rot_1"]], "top": "hell_gelb_aussetzen"})
	check(str(g.view_for(0).hints.text).contains("lege Gelb oder ein Aussetzen"), "Hinweis Symbol: " + str(g.view_for(0).hints.text))
	g = make({"hands": [["hell_gruen_1", "hell_blau_1"], ["hell_rot_1"]], "top": "hell_wuenscher", "color": "blau"})
	check(str(g.view_for(0).hints.text).contains("lege Blau (Wunschfarbe)"), "Hinweis Wunschfarbe: " + str(g.view_for(0).hints.text))
	g = make({"hands": [["hell_wuenscher_plus2", "hell_gelb_1"], ["hell_rot_1"]], "top": "hell_rot_5"})
	play(g, 0, "hell_wuenscher_plus2", "+2 für Hinweis", "blau")
	check(str(g.view_for(1).hints.text).contains("anzweifeln"), "Hinweis challenge: " + str(g.view_for(1).hints.text))
	check(str(g.view_for(0).hints.text).contains("überlegt"), "Hinweis für den Leger: " + str(g.view_for(0).hints.text))
	# Begründungen auf Deutsch
	g = make({"hands": [["hell_gruen_1", "hell_rot_1"], ["hell_rot_1"]], "top": "hell_blau_7"})
	var why := deny(g, 0, {"a": "play", "card": id_of(g, 0, "hell_gruen_1")}, "Begründung")
	check(why.contains("lege Blau oder eine 7"), "Begründung nennt die Möglichkeiten: " + why)


# --- Nachbesserung nach der Prüfung (docs/module/A_pruefung.json) ---

# Kaputte Aktionen (freies JSON aus dem Netz): sauber abgelehnt mit Begründung, Zustand unverändert, keine Skriptfehler.
func _broken_actions() -> void:
	var spec := {"hands": [["hell_rot_1", "hell_wuenscher", "hell_gelb_3"], ["hell_rot_3", "hell_rot_4"], ["hell_rot_6"]], "top": "hell_rot_5"}
	var g := make(spec)
	check(int(g.hands[0][0]) == 0, "Platz 0 hält die Karte mit id 0 (früher spielte card:\"abc\" sie)")
	for bad: Variant in [null, [1], {}, "abc", "0", 1.5, true, INF, NAN]:
		var why := deny(g, 0, {"a": "play", "card": bad}, "play mit card=%s" % str(bad))
		check(why == "Ungültige Aktion.", "card=%s: „Ungültige Aktion.“ (%s)" % [str(bad), why])
	deny(g, 0, {"a": "play"}, "play ohne card")
	deny(g, 0, {"a": "play", "card": 999}, "play mit unbekannter id")
	for bad: Variant in [null, 5, ["rot"], {}, "lila"]:
		var why := deny(g, 0, {"a": "play", "card": id_of(g, 0, "hell_wuenscher"), "color": bad}, "Joker mit color=%s" % str(bad))
		check(why.begins_with("Wähle eine Farbe"), "Joker mit color=%s: Farbe verlangt (%s)" % [str(bad), why])
	for bad: Variant in [null, 5, ["play"], {}, "spielen"]:
		var why := deny(g, 0, {"a": bad, "card": 0}, "a=%s" % str(bad))
		check(why == "Unbekannte Aktion.", "a=%s: „Unbekannte Aktion.“ (%s)" % [str(bad), why])
	deny(g, 0, {}, "leere Aktion")
	deny(g, 0, {"a": "next_round", "seat": "x"}, "next_round mitten in der Runde")
	# JSON-Zahlen kommen als float und werden angenommen
	var jp: Dictionary = JSON.parse_string(JSON.stringify({"a": "play", "card": id_of(g, 0, "hell_rot_1")}))
	check(jp.card is float, "JSON liefert die id als float")
	act(g, 0, jp, "play mit JSON-Zahl")
	# Erwischen mit kaputtem Ziel
	g = make({"hands": [["hell_rot_1", "hell_rot_2"], ["hell_rot_3", "hell_rot_4"], ["hell_rot_6", "hell_rot_7", "hell_rot_8"]], "top": "hell_rot_5"})
	play(g, 0, "hell_rot_1", "legen ohne Mau")
	for bad: Variant in [null, "x", "0", [0], {}, 0.5, false]:
		var why := deny(g, 1, {"a": "catch", "target": bad}, "catch mit target=%s" % str(bad))
		check(why == "Ungültige Aktion.", "target=%s: „Ungültige Aktion.“ (%s)" % [str(bad), why])
	deny(g, 1, {"a": "catch"}, "catch ohne target")
	deny(g, 1, {"a": "catch", "target": 99}, "catch mit Platz 99")
	deny(g, 1, {"a": "catch", "target": -5}, "catch mit Platz -5")
	var jc: Dictionary = JSON.parse_string("{\"a\":\"catch\",\"target\":0}")
	act(g, 1, jc, "catch mit JSON-Zahl")
	check(n_hand(g, 0) == 3, "erwischt über JSON-Aktion")
	# Farbwahl mit kaputter Farbe
	g = make({"hands": [["hell_rot_flip", "hell_rot_1/dunkel_lila_1", "hell_rot_2/dunkel_lila_2"], ["hell_gelb_1"], ["hell_gelb_2"]],
		"top": "hell_rot_5", "discard": ["hell_blau_4/dunkel_wuenscher"]})
	play(g, 0, "hell_rot_flip", "Flip mit Joker unten")
	check(g.state == "color", "Phase color")
	for bad: Variant in [null, 3, ["lila"], "rot"]:
		deny(g, 0, {"a": "color", "color": bad}, "Farbwahl mit color=%s" % str(bad))
	act(g, 0, {"a": "color", "color": "lila"}, "Farbwahl Lila")


# Gastgeber-Platz: players[i].host; nur er startet die nächste Runde und bekommt can_next_round.
func _host_seat() -> void:
	var pl: Array = [{"name": "Anna"}, {"name": "Ben", "host": true}, {"name": "Cleo", "host": true}]
	var g := MauGame.create(RuleConfig.new(), pl, 5)
	check(g.host_seat() == 1, "Gastgeber = erster Platz mit host (%d)" % g.host_seat())
	check(MauGame.create(RuleConfig.new(), RulesFixture.players(3), 5).host_seat() == 0, "ohne Markierung: Platz 0")
	var jp: Array = JSON.parse_string("[{\"name\":\"A\"},{\"name\":\"B\"},{\"name\":\"C\",\"host\":1}]")
	check(MauGame.create(RuleConfig.new(), jp, 5).host_seat() == 2, "host als JSON-Zahl")
	check(MauGame.create(RuleConfig.new(), [{"name": "A"}, {"name": "B", "host": "ja"}], 5).host_seat() == 0, "host nur als bool oder Zahl")
	g.start_round()
	var back := MauGame.from_dict(JSON.parse_string(JSON.stringify(g.to_dict())))
	check(back.host_seat() == 1 and JSON.stringify(back.to_dict()) == JSON.stringify(g.to_dict()), "Gastgeber übersteht Speichern")
	check(MauGame.from_dict({"players": [{"name": "A"}, {"name": "B"}]}).host_seat() == 0, "alter Spielstand ohne host: Platz 0")
	# Runde zu Ende: nur der Gastgeber startet die nächste
	g = make({"hands": [["hell_rot_1"], ["hell_blau_9"], ["hell_gelb_1"]], "top": "hell_rot_5", "host": 2})
	play(g, 0, "hell_rot_1", "Runde gewinnen (Gastgeber Platz 2)")
	check(g.state == "round_over", "Runde vorbei")
	check(not g.view_for(0).hints.can_next_round and not g.view_for(1).hints.can_next_round and g.view_for(2).hints.can_next_round
		and not g.view_for(-1).hints.can_next_round, "can_next_round nur für den Gastgeber")
	check(not str(g.view_for(0).hints.text).contains("Weiter mit") and str(g.view_for(2).hints.text).contains("Weiter mit der nächsten Runde"),
		"Hinweis nur für den Gastgeber: %s | %s" % [g.view_for(0).hints.text, g.view_for(2).hints.text])
	var why := deny(g, 0, {"a": "next_round"}, "nächste Runde von Platz 0 (nicht Gastgeber)")
	check(why.contains("Gastgeber"), "Begründung nennt den Gastgeber: " + why)
	act(g, 2, {"a": "next_round"}, "Gastgeber startet die nächste Runde")
	check(g.round_no == 2 and g.state == "turn" and g.host_seat() == 2, "Runde 2, Gastgeber bleibt")
	g.set_host(7)
	check(g.host_seat() == 2, "set_host ignoriert ungültige Plätze")
	g.set_host(1)
	check(g.host_seat() == 1, "set_host")
	# Spielerzahl 2–10 wird erzwungen (zwei absichtliche Warnungen „WARNING: MauGame: 2 bis 10 Spieler nötig“, keine ERROR-Zeile)
	for n in [1, 11]:
		var bad := MauGame.create(RuleConfig.new(), RulesFixture.players(n), 3)
		check(not bad.is_valid() and bad.start_round().is_empty() and bad.state == "idle", "%d Spieler: ungültig, startet nicht" % n)
		var r := bad.apply(0, {"a": "draw"})
		check(not bool(r.ok) and str(r.reason) != "", "%d Spieler: apply lehnt ab (%s)" % [n, r.reason])
	for n in [2, 10]:
		var ok_game := MauGame.create(RuleConfig.new(), RulesFixture.players(n), 3)
		check(ok_game.is_valid() and not ok_game.start_round().is_empty() and ok_game.state == "turn", "%d Spieler: gültig" % n)
		check(RulesFixture.card_check(ok_game) == "", "%d Spieler: 112 Karten" % n)
	var big := MauGame.create(RuleConfig.from_dict({"hand_size": 10}), RulesFixture.players(10), 4)
	big.start_round()
	check(RulesFixture.invariants(big) == "", "10 Spieler mit 10 Karten: " + RulesFixture.invariants(big))


func _fixes() -> void:
	# Kein blinder Mau-Ruf: 2 Karten, nichts passt → weder can_mau noch Erinnerung, Ruf wird abgelehnt
	var g := make({"hands": [["hell_blau_1", "hell_blau_2"], ["hell_rot_3"], ["hell_rot_6"]], "top": "hell_gelb_5", "draw": ["hell_gelb_9"]})
	var v := g.view_for(0)
	check(not v.hints.can_mau and not str(v.hints.text).contains("Mau"), "nichts passt: kein Mau-Hinweis (%s)" % v.hints.text)
	var why := deny(g, 0, {"a": "mau"}, "blinder Mau-Ruf")
	check(why.contains("vorletzte Karte"), "Begründung blinder Ruf: " + why)
	# Opfer einer +2 ohne Stapeln mit 2 Karten: kein Mau
	g = make({"hands": [["hell_wuenscher_plus2", "hell_gelb_1", "hell_gelb_2"], ["hell_rot_3", "hell_rot_4"], ["hell_rot_6"]], "top": "hell_rot_5"})
	play(g, 0, "hell_wuenscher_plus2", "+2 auf Opfer mit 2 Karten", "blau")
	v = g.view_for(1)
	check(g.state == "challenge" and not v.hints.can_mau and not str(v.hints.text).contains("Mau"), "Opfer ohne Stapeln: kein Mau (%s)" % v.hints.text)
	deny(g, 1, {"a": "mau"}, "Mau als Opfer ohne Stapeln")
	# Opfer kann stapeln: Mau möglich und Erinnerung
	g = make({"hands": [["hell_wuenscher_plus2", "hell_gelb_1", "hell_gelb_2"], ["hell_wuenscher_plus2", "hell_rot_4"], ["hell_rot_6"]], "top": "hell_rot_5"},
		{"stacking": "same"})
	play(g, 0, "hell_wuenscher_plus2", "+2 auf Opfer, das stapeln kann", "blau")
	v = g.view_for(1)
	check(v.hints.can_mau and str(v.hints.text).contains("Denk an „Mau!“"), "Opfer kann stapeln: Mau möglich (%s)" % v.hints.text)
	act(g, 1, {"a": "mau"}, "Mau vor dem Stapeln")
	# Flip als letzte Karte bei ignore: auch nicht ausgeführt, wenn die Runde weiterläuft (round_end=last)
	for mode in ["execute", "ignore"]:
		g = make({"hands": [["hell_rot_flip"], ["hell_blau_1/dunkel_lila_3", "hell_rot_2"], ["hell_gelb_2/dunkel_pink_2", "hell_rot_3"]],
			"top": "hell_rot_5", "discard": ["hell_blau_4/dunkel_lila_6"]}, {"flip_last_card": mode, "round_end": "last"})
		var ev := play(g, 0, "hell_rot_flip", "letzte Karte Flip, Runde läuft weiter (%s)" % mode)
		check(g.state == "turn" and g.place[0] == 1 and g.current_seat() == 1, "Runde läuft weiter, Platz 1 dran (%s)" % mode)
		if mode == "execute":
			check(g.side == 1 and ev_names(ev).has("flip"), "execute: Flip ausgeführt")
		else:
			check(g.side == 0 and not ev_names(ev).has("flip") and g.color == "rot", "ignore: kein Flip, Farbe Rot (%s)" % str(ev_names(ev)))
	check("\n".join(RulesText.card_help("hell_rot_flip", RuleConfig.from_dict({"flip_last_card": "ignore"}))).contains("nicht mehr ausgeführt"),
		"Kartenhilfe bei ignore")
	# auto-Strafe vor dem Legen ändert die Regelgerechtheit nicht (entschieden wird mit der Hand vor der Strafe)
	for mode in ["bluff", "enforce"]:
		g = make({"hands": [["hell_rot_aussetzen", "hell_wuenscher_plus2"], ["hell_gelb_1", "hell_gelb_2", "hell_gelb_3"]], "top": "hell_rot_5",
			"draw": ["hell_rot_1", "hell_rot_2"]}, {"mau_call": "auto", "wild_restriction": mode}, 2)
		play(g, 0, "hell_rot_aussetzen", "Aussetzen zu zweit ohne Mau (%s)" % mode)
		check(g.current_seat() == 0 and g.mau_open == 0 and playable_keys(g, 0) == ["hell_wuenscher_plus2"], "Zusatzzug, +2 laut Hinweis erlaubt (%s)" % mode)
		var ev := play(g, 0, "hell_wuenscher_plus2", "+2 nach auto-Strafe (%s)" % mode, "gelb")
		check(ev_names(ev).slice(0, 3) == ["penalty", "draw", "play"], "Strafe vor dem Legen (%s)" % str(ev_names(ev)))
		if mode == "bluff":
			check(g.state == "challenge" and bool(g.pending.legal), "regelgerecht trotz Strafkarten")
			ev = act(g, 1, {"a": "challenge"}, "anzweifeln nach auto-Strafe")
			var ch := find_ev(ev, "challenge")
			check(not bool(ch.success) and (ch.hand as Array).is_empty() and n_hand(g, 1) == 7,
				"ehrlich: Herausforderer zieht 4 und sieht die Hand vor der Strafe (%s)" % str(ch))
		else:
			check(n_hand(g, 1) == 5 and n_hand(g, 0) == 2, "enforce: angenommen, Nächster zieht 2")
	# reminder: Ruf auch nach dem Legen möglich, kein Erwischen, keine Strafe
	var spec := {"hands": [["hell_rot_1", "hell_rot_2"], ["hell_rot_3", "hell_rot_4"], ["hell_rot_6", "hell_rot_7", "hell_rot_8"]], "top": "hell_rot_5"}
	g = make(spec, {"mau_call": "reminder"})
	play(g, 0, "hell_rot_1", "legen ohne Mau (reminder)")
	check(g.view_for(0).hints.can_mau and g.view_for(1).hints.catch.is_empty(), "reminder: nachträglich rufbar, nicht erwischbar")
	act(g, 0, {"a": "mau"}, "nachträglich rufen (reminder)")
	check(g.view_for(1).players[0].mau, "Ruf sichtbar")
	g = make(spec, {"mau_call": "reminder"})
	play(g, 0, "hell_rot_1", "legen ohne Mau (reminder)")
	play(g, 1, "hell_rot_3", "Nächster beginnt (reminder)")
	deny(g, 0, {"a": "mau"}, "reminder: nach Beginn des nächsten Zugs zu spät")
	check(n_hand(g, 0) == 1, "reminder: keine Strafe")
	# Mau-Fenster nach automatischem Ziehen (Absicht): Das Opfer einer +1 handelt nicht selbst; erwischen geht bis zur ersten
	# Handlung des Übernächsten.
	g = make({"hands": [["hell_rot_plus1", "hell_rot_1"], ["hell_rot_3", "hell_rot_4"], ["hell_rot_6", "hell_rot_7"], ["hell_rot_8"]],
		"top": "hell_rot_5"}, {}, 4)
	play(g, 0, "hell_rot_plus1", "+1 auf 1 Karte ohne Mau")
	check(g.current_seat() == 2 and g.view_for(3).hints.catch == [0], "nach automatischem Ziehen noch erwischbar")
	play(g, 2, "hell_rot_6", "Übernächster handelt")
	deny(g, 3, {"a": "catch", "target": 0}, "danach zu spät")
	# Übersicht bei drawn_card=may_not ohne Widerspruch
	var spielzug := ""
	for p in RulesText.overview(RuleConfig.from_dict({"drawn_card": "may_not"})):
		if p.title == "Spielzug":
			spielzug = str(p.text)
	check(spielzug.contains("danach ist dein Zug vorbei") and not spielzug.contains("nur die gezogene Karte legen"), "may_not: " + spielzug)
	for p in RulesText.overview(RuleConfig.new()):
		if p.title == "Spielzug":
			spielzug = str(p.text)
	check(spielzug.contains("nur die gezogene Karte legen"), "may: " + spielzug)
