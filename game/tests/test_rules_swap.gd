extends "res://tests/test_rules_views.gd"
# Modul A: Hausregel Kartentausch (swap_cards = "on", 116 Karten; Nutzerwunsch 05.10.2026).
# Gebaute Fälle: Kartendaten und Prüfsummen, Regeloptionen und Texte, Rundenstart mit 116 Karten, Tausch im Uhrzeigersinn und in
# Spielrichtung nach einem Richtungswechsel, zu zweit, mit Fertigen, als letzte Karte bei round_end first/last, Mau-Fenster
# danach, Flip danach, Lecktest (jeder sieht nur seine neue Hand), to_dict/from_dict mit 116 Karten, Passen, Punkte und
# Bot-Entscheidungen. Danach die Zufallsprüfungen aus test_rules_views.gd mit Kartentausch (JSON, Lecktest, Hinweise = Regeln,
# Rundreise; swap_mode() = true) und ein Bot-Dauerlauf: Standard 2000 Partien mit zufälligen Regeln, 2–10 Spielern und
# Stufen 0–2 (Anzahl per Umgebungsvariable RULES_SWAP_GAMES, godot_run.ps1 -EnvPairs 'RULES_SWAP_GAMES=200').

const SWAP_GAMES := 2000
const SWAP_STEP_LIMIT := 5000      # Aktionen je Runde; mehr = Endlosschleife
const SWAP_ROUND_LIMIT := 40       # Runden je Partie (Punktewertung)

var swap_stats := {}


func swap_mode() -> bool:
	return true


func _initialize() -> void:
	# Aufteilung (tests/teil.gd, TEIL=k/n): Einzel- und Zufallsprüfungen nur in Teil 1, die Partien des Bot-Dauerlaufs reihum.
	if not Teil.first():
		_sw_bot_run()
		print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
		quit(0 if failures == 0 else 1)
		return
	_sw_cards()
	_sw_config_and_texts()
	_sw_start()
	_sw_clockwise()
	_sw_after_reverse()
	_sw_two_players()
	_sw_finished_players()
	_sw_last_card()
	_sw_mau()
	_sw_flip_after()
	_sw_dark_side()
	_sw_leak()
	_sw_round_trip()
	_sw_matching()
	_sw_points()
	_sw_bot_decisions()
	var t0 := Time.get_ticks_msec()
	_json_views()
	_leak_runs()
	_hint_consistency()
	_round_trip()
	print("Zufallsprüfungen mit Kartentausch: %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	_sw_strength()
	_sw_bot_run()
	print("Laufzeit seit Godot-Start: %.1f s" % (Time.get_ticks_msec() / 1000.0))
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)


# --- Hilfen ---

func sw_cfg(over := {}) -> RuleConfig:
	var d := {"swap_cards": "on"}
	d.merge(over, true)
	return RuleConfig.from_dict(d)


func sw_make(spec: Dictionary, over := {}, n := 3) -> MauGame:
	var g := RulesFixture.build(sw_cfg(over), n, spec)
	var cc := RulesFixture.card_check(g)
	var dc := RulesFixture.deck_check(g)
	check(g.n_cards == 116 and cc == "" and dc == "", "Aufbau mit 116 Karten: %s %s" % [cc, dc])
	return g


func sw_act(g: MauGame, seat: int, action: Dictionary, msg: String) -> Array:
	var r := g.apply(seat, action)
	check(bool(r.ok), "%s (abgelehnt: %s)" % [msg, r.reason])
	var inv := RulesFixture.invariants(g)
	check(inv == "", "%s: %s" % [msg, inv])
	return r.events


func sw_play(g: MauGame, seat: int, key: String, msg: String, col := "") -> Array:
	var id := RulesFixture.card(g, seat, key)
	check(id >= 0, "%s: Karte %s bei Platz %d" % [msg, key, seat])
	var a := {"a": "play", "card": id}
	if col != "":
		a["color"] = col
	return sw_act(g, seat, a, msg)


func sw_ev(ev: Array, e_name: String) -> Dictionary:
	for e in ev:
		if str(e.e) == e_name:
			return e
	return {}


func sw_names(ev: Array) -> Array:
	var out: Array = []
	for e in ev:
		out.append(str(e.e))
	return out


func sw_without(a: Array, id: int) -> Array:
	var b := a.duplicate()
	b.erase(id)
	return b


func sw_count(key: String, n := 1) -> void:
	swap_stats[key] = int(swap_stats.get(key, 0)) + n


func sw_swap_faces(g: MauGame) -> int:
	var c := 0
	for code in g.faces:
		if CardDB.kind_table()[code] == CardDB.SWAP:
			c += 1
	return c


# Prüft ein swap_hands-Ereignis gegen den Zustand direkt nach dem Tausch.
func sw_check_event(g: MauGame, e: Dictionary, seat: int, step: int, msg: String) -> void:
	check(not e.is_empty(), msg + ": Ereignis swap_hands")
	if e.is_empty():
		return
	check(int(e.seat) == seat and int(e.dir) == step, "%s: seat %d, dir %d (%s, %s)" % [msg, seat, step, str(e.seat), str(e.dir)])
	var counts: Array = []
	for s in g.players.size():
		counts.append((g.hands[s] as Array).size())
		var ids: Array = []
		for item in e.hands[s]:
			ids.append(int(item.id))
		check(ids == g.hands[s], "%s: Hand von Platz %d im Ereignis" % [msg, s])
	check(e.counts == counts, "%s: counts %s (%s)" % [msg, str(counts), str(e.counts)])


# --- Kartendaten ---

func _sw_cards() -> void:
	var ptab := CardDB.points_table()
	var want_sums := [[CardDB.SUM_LIGHT, CardDB.SUM_LIGHT_SWAP], [CardDB.SUM_DARK, CardDB.SUM_DARK_SWAP]]
	for s in 2:
		var base := CardDB.deck(s)
		var full := CardDB.deck(s, true)
		check(base.size() == 112 and full.size() == 116, "Seite %d: 112 bzw. 116 Karten (%d/%d)" % [s, base.size(), full.size()])
		var sum_base := 0
		var sum_full := 0
		var swaps := {}
		for c in base:
			sum_base += ptab[c]
			check(CardDB.kind_table()[c] != CardDB.SWAP, "Grunddeck ohne Kartentausch")
		for c in full:
			sum_full += ptab[c]
			if CardDB.kind_table()[c] == CardDB.SWAP:
				swaps[CardDB.color_table()[c]] = int(swaps.get(CardDB.color_table()[c], 0)) + 1
		check(sum_base == int(want_sums[s][0]) and sum_full == int(want_sums[s][1]),
			"Seite %d: Prüfsummen %d/%d (%d/%d)" % [s, int(want_sums[s][0]), int(want_sums[s][1]), sum_base, sum_full])
		check(swaps.size() == 4 and swaps.values() == [1, 1, 1, 1], "Seite %d: ein Kartentausch je Farbe (%s)" % [s, str(swaps)])
		for color in CardDB.colors(CardDB.SIDES[s]):
			check(swaps.has(color), "Kartentausch in %s" % color)
	check(CardDB.SUM_LIGHT_SWAP == 1360 and CardDB.SUM_DARK_SWAP == 1560 and CardDB.CARD_COUNT_SWAP == 116, "Konstanten 1360/1560/116")
	var fl := CardDB.faces_light(true)
	var fd := CardDB.faces_dark(true)
	var sl := 0
	var sd := 0
	for f in fl:
		sl += CardDB.points(f)
	for f in fd:
		sd += CardDB.points(f)
	check(fl.size() == 116 and fd.size() == 116 and sl == 1360 and sd == 1560, "faces_light/dark(true): 116, 1360/1560 (%d/%d)" % [sl, sd])
	check(CardDB.faces_light().size() == 112 and CardDB.faces_dark().size() == 112, "faces_light/dark(): weiter 112")
	check(CardDB.all_keys().size() == 108 and CardDB.all_keys(true).size() == 128, "all_keys 108 / 128 (alle Hausregeln) (%d/%d)" % [CardDB.all_keys().size(), CardDB.all_keys(true).size()])
	check(CardDB.key_table().size() == 128 and CardDB.key_table()[108] == "hell_rot_tausch" and CardDB.key_table()[115] == "dunkel_lila_tausch", "Codetabelle: Kartentausch 108–115 (insgesamt 128 Gesichter)")
	# Codes des Grunddecks unverändert (Spielstände speichern sie): Code i = i-ter Schlüssel des Grunddecks.
	var stable := true
	for i in 108:
		if CardDB.key_table()[i] != CardDB.all_keys()[i]:
			stable = false
	check(stable, "Codes 0–107 wie vor dem Kartentausch")
	var sk := Array(CardDB.swap_keys())
	check(sk == ["hell_rot_tausch", "hell_gelb_tausch", "hell_gruen_tausch", "hell_blau_tausch",
		"dunkel_pink_tausch", "dunkel_tuerkis_tausch", "dunkel_orange_tausch", "dunkel_lila_tausch"], "Kartentausch-Schlüssel (%s)" % str(sk))
	for k in sk:
		var f := CardDB.parse_key(k)
		check(CardDB.is_key(k) and CardDB.face_key(f) == k, "Rundreise Schlüssel " + k)
		check(CardDB.points_of_key(k) == 20 and CardDB.points(f) == 20, "20 Punkte: " + k)
		check(CardDB.is_swap(f) and CardDB.is_action(f) and not CardDB.is_wild(f) and not CardDB.is_draw_card(f), "Art tausch: " + k)
		check(Array(CardDB.all_keys(true)).has(k) and not Array(CardDB.all_keys()).has(k), "all_keys(true) enthält " + k)
	var sorted := CardDB.sort_keys(["hell_gelb_1", "dunkel_pink_tausch", "hell_rot_tausch", "hell_wuenscher", "hell_rot_flip", "hell_rot_9",
		"dunkel_pink_flip", "dunkel_tuerkis_1"])
	check(sorted == ["hell_rot_9", "hell_rot_flip", "hell_rot_tausch", "hell_gelb_1", "hell_wuenscher", "dunkel_pink_flip",
		"dunkel_pink_tausch", "dunkel_tuerkis_1"], "Sortierung: Kartentausch hinter dem Flip seiner Farbe (%s)" % str(sorted))
	var all_sorted := Array(CardDB.all_keys(true))
	check(CardDB.sort_keys(all_sorted) == all_sorted, "all_keys(true) ist sortiert")
	check(RulesText.face_title("hell_rot_tausch") == "Rot Kartentausch" and RulesText.face_title("dunkel_lila_tausch") == "Lila Kartentausch",
		"Titel Rot/Lila Kartentausch")
	check(RulesText.match_phrase("dunkel_pink_tausch") == "einen Kartentausch" and RulesText.kind_name("tausch") == "Kartentausch", "Namen Kartentausch")


func _sw_config_and_texts() -> void:
	var c := RuleConfig.new()
	check(c.swap_cards == "off" and c.swap_direction == "clockwise" and c.card_count() == 112, "Standard: kein Kartentausch, 112 Karten")
	# Nutzerentscheidung 05.10.2026: „Familie“ spielt mit Kartentausch, alle anderen Voreinstellungen ohne.
	for p in RuleConfig.preset_names():
		check(RuleConfig.preset(p).swap_cards == ("on" if p == "familie" else "off"), "Voreinstellung %s: Kartentausch nur bei Familie" % p)
	check(RuleConfig.preset("familie").card_count() == 124 and RuleConfig.preset("familie").swap_direction == "play",
		"Familie: 124 Karten, Tausch in Spielrichtung")
	check(RuleConfig.from_dict(RuleConfig.preset("familie").to_dict().merged({"swap_direction": "clockwise"}, true)).preset_name() == "",
		"Familie mit Tausch im Uhrzeigersinn: eigene Regeln")
	var on := RuleConfig.from_dict({"swap_cards": "on", "swap_direction": "play"})
	check(on.card_count() == 116 and on.swap_direction == "play", "swap_cards=on: 116 Karten")
	check(RuleConfig.from_dict(JSON.parse_string(JSON.stringify(on.to_dict()))).equals(on), "Rundreise über JSON")
	var bad := RuleConfig.from_dict({"swap_cards": "ja", "swap_direction": 1})
	check(bad.swap_cards == "off" and bad.swap_direction == "clockwise", "ungültige Werte bleiben beim Standard")
	check(RuleConfig.from_dict({"swap_direction": "play"}).preset_name() == "offiziell", "ohne Kartentausch zählt die Richtung nicht für die Voreinstellung")
	check(on.preset_name() == "" and RuleConfig.from_dict({"swap_cards": "on"}).preset_name() == "", "mit Kartentausch: eigene Regeln")
	check(c.swap_step(-1) == 1 and on.swap_step(-1) == -1 and on.swap_step(1) == 1, "swap_step")
	check(not "\n".join(c.describe()).contains("Kartentausch"), "describe ohne Kartentausch")
	var d_on := "\n".join(on.describe())
	check(d_on.contains("Kartentausch") and d_on.contains("Spielrichtung") and d_on.contains("116"), "describe mit Kartentausch in Spielrichtung (%s)" % d_on)
	check("\n".join(sw_cfg().describe()).contains("Uhrzeigersinn"), "describe mit Kartentausch im Uhrzeigersinn")
	# Kartenhilfe für alle 116 Gesichter, Kartentausch je nach Option
	for k in CardDB.all_keys(true):
		var h := RulesText.card_help(k, on)
		check(h.size() >= 2, "Kartenhilfe für " + k)
		check(RulesText.face_title(k) != k, "Titel für " + k)
	var cw := "\n".join(RulesText.card_help("hell_rot_tausch", sw_cfg()))
	check(cw.contains("Uhrzeigersinn") and cw.contains("Passt auf Rot") and cw.contains("Auch als letzte Karte") and cw.contains("gewinnst")
		and cw.contains("„Mau!“") and cw.contains("Zu zweit") and cw.contains("20 Punkte"), "Hilfe Kartentausch Uhrzeigersinn (%s)" % cw)
	var pl := "\n".join(RulesText.card_help("dunkel_lila_tausch", sw_cfg({"swap_direction": "play", "round_end": "last", "mau_call": "off"})))
	check(pl.contains("Spielrichtung") and pl.contains("andersherum") and pl.contains("tauschen trotzdem") and not pl.contains("Mau"),
		"Hilfe Kartentausch Spielrichtung, bis zum Letzten, ohne Mau (%s)" % pl)
	check("\n".join(RulesText.card_help("hell_rot_tausch", RuleConfig.new())).contains("gerade nicht im Spiel"), "Hilfe ohne Hausregel")
	var titles_on: Array = []
	var text_on := ""
	for p in RulesText.overview(sw_cfg()):
		titles_on.append(p.title)
		text_on += str(p.text) + "\n"
	var titles_off: Array = []
	var text_off := ""
	for p in RulesText.overview(RuleConfig.new()):
		titles_off.append(p.title)
		text_off += str(p.text) + "\n"
	check(titles_on.has("Kartentausch") and text_on.contains("116 Karten") and text_on.contains("Uhrzeigersinn"), "Übersicht mit Kartentausch")
	check(not titles_off.has("Kartentausch") and text_off.contains("112 Karten") and not text_off.contains("Kartentausch-Karten"), "Übersicht ohne Kartentausch: kein eigener Absatz (kurz unter „Weitere besondere Karten“)")
	var ov500 := ""
	for p in RulesText.overview(sw_cfg({"scoring": "points500"})):
		ov500 += str(p.text)
	check(ov500.contains("Kartentausch und Flip 20") or ov500.contains("Kartentausch"), "Übersicht 500 Punkte nennt den Kartentausch")


# --- Rundenstart ---

func _sw_start() -> void:
	var bad := ""
	for s in 60:
		var cfg := sw_cfg({"hand_size": 5 + s % 6})
		var n := 2 + s % 9
		var g := MauGame.create(cfg, RulesFixture.players(n, "bot"), 7_000_003 * s + 5)
		g.start_round()
		if g.n_cards != 116 or g.faces.size() != 232:
			bad = "n_cards %d, faces %d" % [g.n_cards, g.faces.size()]
		elif RulesFixture.card_check(g) != "" or RulesFixture.deck_check(g) != "":
			bad = RulesFixture.card_check(g) + RulesFixture.deck_check(g)
		elif sw_swap_faces(g) != 8:
			bad = "%d Kartentausch-Gesichter statt 8" % sw_swap_faces(g)
		elif CardDB.kind_table()[g.faces[int(g.discard.back())]] != "zahl":
			bad = "Startkarte keine Zahl"
		for p in n:
			if (g.hands[p] as Array).size() != cfg.hand_size:
				bad = "Handgröße"
		g.state = "round_over"
		g.apply(0, {"a": "next_round"})
		if RulesFixture.card_check(g) != "" or RulesFixture.deck_check(g) != "" or sw_swap_faces(g) != 8:
			bad = "Runde 2: " + RulesFixture.card_check(g) + RulesFixture.deck_check(g)
	check(bad == "", "Rundenstart mit 116 Karten über 60 Seeds: " + bad)
	var off := MauGame.create(RuleConfig.new(), RulesFixture.players(4), 3)
	off.start_round()
	check(off.n_cards == 112 and off.faces.size() == 224 and sw_swap_faces(off) == 0 and RulesFixture.deck_check(off) == "",
		"ohne Hausregel: 112 Karten, kein Kartentausch")
	check(off.view_for(0).rules.swap_cards == "off", "Regeln in der Sicht nennen swap_cards")


# --- Tausch ---

func _sw_spec4() -> Dictionary:
	return {"hands": [["hell_rot_tausch", "hell_gelb_1", "hell_gelb_2"], ["hell_blau_1"], ["hell_blau_2", "hell_blau_3", "hell_blau_4"],
		["hell_gruen_1", "hell_gruen_2", "hell_gruen_3", "hell_gruen_4"]], "top": "hell_rot_5"}


func _sw_clockwise() -> void:
	var g := sw_make(_sw_spec4(), {}, 4)
	var old: Array = g.hands.duplicate(true)
	var tid := RulesFixture.card(g, 0, "hell_rot_tausch")
	var ev := sw_play(g, 0, "hell_rot_tausch", "Kartentausch im Uhrzeigersinn")
	check(sw_names(ev) == ["play", "swap_hands", "turn"], "Ereignisse play, swap_hands, turn (%s)" % str(sw_names(ev)))
	check(g.hands[1] == sw_without(old[0], tid) and g.hands[2] == old[1] and g.hands[3] == old[2] and g.hands[0] == old[3],
		"jede Hand wandert an Platz + 1")
	check(g.current_seat() == 1 and g.dir == 1, "danach ist der Nächste in Spielrichtung dran (%d)" % g.current_seat())
	sw_check_event(g, sw_ev(ev, "swap_hands"), 0, 1, "Uhrzeigersinn")
	check(sw_ev(ev, "swap_hands").counts == [4, 2, 1, 3], "counts [4, 2, 1, 3]")
	check(RulesFixture.top_key(g) == "hell_rot_tausch" and g.color == "rot", "Kartentausch liegt oben, Farbe Rot")
	var v := g.view_for(1)
	var ids: Array = []
	for item in v.hand:
		ids.append(int(item.id))
	check(ids == g.hands[1] and v.players[0].count == 4, "Sicht zeigt die neue Hand")


func _sw_after_reverse() -> void:
	# Nach dem Richtungswechsel (dir = −1): Platz + 1 bei clockwise und against, Platz − 1 bei counter und play
	for mode in ["play", "clockwise", "counter", "against"]:
		var spec := {"hands": [["hell_rot_richtungswechsel", "hell_gelb_1", "hell_gelb_2"], ["hell_blau_1", "hell_blau_2"],
			["hell_blau_3", "hell_blau_4", "hell_blau_5"], ["hell_rot_tausch", "hell_gruen_1", "hell_gruen_2", "hell_gruen_3", "hell_gruen_4"]],
			"top": "hell_rot_5"}
		var g := sw_make(spec, {"swap_direction": mode}, 4)
		sw_play(g, 0, "hell_rot_richtungswechsel", "Richtungswechsel (%s)" % mode)
		check(g.dir == -1 and g.current_seat() == 3, "%s: Richtung -1, Platz 3 dran" % mode)
		var old: Array = g.hands.duplicate(true)
		var tid := RulesFixture.card(g, 3, "hell_rot_tausch")
		var ev := sw_play(g, 3, "hell_rot_tausch", "Kartentausch nach Richtungswechsel (%s)" % mode)
		var rest := sw_without(old[3], tid)
		if mode == "play" or mode == "counter":
			check(g.hands[2] == rest and g.hands[1] == old[2] and g.hands[0] == old[1] and g.hands[3] == old[0],
				"%s: Hände wandern an Platz − 1" % mode)
			sw_check_event(g, sw_ev(ev, "swap_hands"), 3, -1, mode)
		else:
			check(g.hands[0] == rest and g.hands[1] == old[0] and g.hands[2] == old[1] and g.hands[3] == old[2],
				"%s nach Richtungswechsel: Hände wandern an Platz + 1" % mode)
			sw_check_event(g, sw_ev(ev, "swap_hands"), 3, 1, mode)
		check(g.current_seat() == 2 and g.dir == -1, "%s: danach Platz 2 (Spielrichtung bleibt −1) (%d)" % [mode, g.current_seat()])
	# Ohne Richtungswechsel: counter und against wandern an Platz − 1
	for mode in ["counter", "against"]:
		var g := sw_make({"hands": [["hell_rot_tausch", "hell_gelb_1"], ["hell_blau_1", "hell_blau_2"], ["hell_blau_3", "hell_blau_4", "hell_blau_5"]],
			"top": "hell_rot_5"}, {"swap_direction": mode}, 3)
		var old: Array = g.hands.duplicate(true)
		var tid := RulesFixture.card(g, 0, "hell_rot_tausch")
		var ev := sw_play(g, 0, "hell_rot_tausch", "Kartentausch (%s)" % mode)
		check(g.hands[2] == sw_without(old[0], tid) and g.hands[0] == old[1] and g.hands[1] == old[2], "%s: Hände an Platz − 1" % mode)
		sw_check_event(g, sw_ev(ev, "swap_hands"), 0, -1, mode)
		check(g.current_seat() == 1, "%s: danach der Nächste in Spielrichtung" % mode)
	var texts := []
	for mode in ["clockwise", "counter", "play", "against"]:
		texts.append("\n".join(RulesText.card_help("hell_rot_tausch", sw_cfg({"swap_direction": mode}))))
	check(texts[0].contains("immer im Uhrzeigersinn") and texts[1].contains("immer gegen den Uhrzeigersinn")
		and texts[2].contains("in der aktuellen Spielrichtung") and texts[3].contains("gegen die aktuelle Spielrichtung")
		and texts[3].contains("andersherum") and not texts[1].contains("andersherum"), "Kartenhilfe je Tauschrichtung")


func _sw_two_players() -> void:
	for mode in ["clockwise", "play"]:
		var g := sw_make({"hands": [["hell_rot_tausch", "hell_gelb_1"], ["hell_blau_1", "hell_blau_2", "hell_blau_3"]], "top": "hell_rot_5",
			"dir": -1 if mode == "play" else 1}, {"swap_direction": mode}, 2)
		var old: Array = g.hands.duplicate(true)
		var tid := RulesFixture.card(g, 0, "hell_rot_tausch")
		var ev := sw_play(g, 0, "hell_rot_tausch", "Kartentausch zu zweit (%s)" % mode)
		check(g.hands[0] == old[1] and g.hands[1] == sw_without(old[0], tid), "%s: zu zweit tauschen beide ihre Hände" % mode)
		check(g.current_seat() == 1, "%s: danach ist der andere dran" % mode)
		sw_check_event(g, sw_ev(ev, "swap_hands"), 0, -1 if mode == "play" else 1, "zu zweit " + mode)


func _sw_finished_players() -> void:
	var spec := {"hands": [["hell_rot_tausch", "hell_gelb_1", "hell_gelb_2"], ["hell_blau_1"], [], ["hell_gruen_1", "hell_gruen_2", "hell_gruen_3", "hell_gruen_4"]],
		"top": "hell_rot_5", "finished": [2]}
	var g := sw_make(spec, {"round_end": "last"}, 4)
	var old: Array = g.hands.duplicate(true)
	var tid := RulesFixture.card(g, 0, "hell_rot_tausch")
	var ev := sw_play(g, 0, "hell_rot_tausch", "Kartentausch mit einem Fertigen")
	check(g.hands[1] == sw_without(old[0], tid) and g.hands[3] == old[1] and g.hands[0] == old[3] and (g.hands[2] as Array).is_empty(),
		"Fertige werden übersprungen: 0 → 1 → 3 → 0")
	sw_check_event(g, sw_ev(ev, "swap_hands"), 0, 1, "mit Fertigem")
	check(sw_ev(ev, "swap_hands").counts == [4, 2, 0, 1], "counts mit Fertigem [4, 2, 0, 1]")
	check(g.current_seat() == 1, "danach Platz 1")
	# Spielrichtung −1 mit Fertigem: 0 → 3 → 1 → 0
	g = sw_make(spec.merged({"dir": -1}), {"round_end": "last", "swap_direction": "play"}, 4)
	old = g.hands.duplicate(true)
	tid = RulesFixture.card(g, 0, "hell_rot_tausch")
	ev = sw_play(g, 0, "hell_rot_tausch", "Kartentausch gegen den Uhrzeigersinn mit einem Fertigen")
	check(g.hands[3] == sw_without(old[0], tid) and g.hands[1] == old[3] and g.hands[0] == old[1], "Fertige übersprungen: 0 → 3 → 1 → 0")
	check(g.current_seat() == 3, "danach Platz 3 (Richtung −1)")


func _sw_last_card() -> void:
	# round_end first: Der Leger ist fertig und gewinnt, getauscht wird nicht mehr.
	var g := sw_make({"hands": [["hell_rot_tausch"], ["hell_blau_1", "hell_blau_2"], ["hell_gruen_1"]], "top": "hell_rot_5", "mau_said": [0]})
	var old: Array = g.hands.duplicate(true)
	var ev := sw_play(g, 0, "hell_rot_tausch", "Kartentausch als letzte Karte (first)")
	check(g.phase() == "round_over" and int(g.result.ranking[0]) == 0, "letzte Karte: Runde vorbei, Leger gewinnt")
	check(sw_ev(ev, "swap_hands").is_empty() and g.hands[1] == old[1] and g.hands[2] == old[2], "letzte Karte bei first: kein Tausch")
	# round_end last: Leger fertig, die übrigen drei tauschen untereinander (1 → 2 → 3 → 1).
	g = sw_make({"hands": [["hell_rot_tausch"], ["hell_blau_1"], ["hell_blau_2", "hell_blau_3"], ["hell_gruen_1", "hell_gruen_2", "hell_gruen_3"]],
		"top": "hell_rot_5", "mau_said": [0]}, {"round_end": "last"}, 4)
	old = g.hands.duplicate(true)
	ev = sw_play(g, 0, "hell_rot_tausch", "Kartentausch als letzte Karte (last)")
	check(int(g.place[0]) == 1 and g.phase() == "turn", "letzte Karte bei last: Platz 1, Runde läuft weiter")
	check(g.hands[2] == old[1] and g.hands[3] == old[2] and g.hands[1] == old[3] and (g.hands[0] as Array).is_empty(),
		"die Übrigen tauschen: 1 → 2 → 3 → 1")
	check(sw_names(ev) == ["play", "finish", "swap_hands", "turn"], "Ereignisse play, finish, swap_hands, turn (%s)" % str(sw_names(ev)))
	sw_check_event(g, sw_ev(ev, "swap_hands"), 0, 1, "letzte Karte bei last")
	check(g.current_seat() == 1, "danach der Nächste nach dem Leger")
	# round_end last, nur noch einer übrig: Runde endet, kein Tausch.
	g = sw_make({"hands": [["hell_rot_tausch"], ["hell_blau_1", "hell_blau_2"], []], "top": "hell_rot_5", "finished": [2], "mau_said": [0]},
		{"round_end": "last"}, 3)
	ev = sw_play(g, 0, "hell_rot_tausch", "Kartentausch als letzte Karte, danach nur noch einer")
	check(g.phase() == "round_over" and sw_ev(ev, "swap_hands").is_empty(), "nur noch einer aktiv: Runde vorbei, kein Tausch")
	check(g.result.ranking == [2, 0, 1], "Platzierung 2, 0, 1 (%s)" % str(g.result.ranking))


func _sw_mau() -> void:
	for mode in ["catch", "auto"]:
		# Platz 0 legt den Kartentausch als vorletzte Karte, ohne „Mau!“ zu rufen; Platz 1 bekommt die eine Restkarte.
		var g := sw_make({"hands": [["hell_rot_tausch", "hell_rot_7"], ["hell_blau_1", "hell_blau_2", "hell_blau_3"], ["hell_gruen_1"]],
			"top": "hell_rot_5", "mau_said": [2]}, {"mau_call": mode})
		check(g.view_for(0).hints.can_mau, "%s: vorher könnte Platz 0 „Mau!“ rufen" % mode)
		sw_play(g, 0, "hell_rot_tausch", "Kartentausch als vorletzte Karte ohne Ruf (%s)" % mode)
		check(g.mau_open == -1, "%s: Mau-Fenster geschlossen" % mode)
		check(g.mau_said == [false, false, false], "%s: alle Rufe verfallen (%s)" % [mode, str(g.mau_said)])
		check((g.hands[1] as Array).size() == 1 and (g.hands[2] as Array).size() == 3, "%s: Platz 1 hat 1 Karte" % mode)
		for s in 3:
			var v := g.view_for(s)
			check((v.hints.catch as Array).is_empty(), "%s: niemand kann erwischt werden (Sicht %d)" % [mode, s])
			check(not bool(v.players[2].mau), "%s: Ruf von Platz 2 verfallen (Sicht %d)" % [mode, s])
		if mode == "catch":
			for t in 3:
				var r := g.apply(2 if t != 2 else 0, {"a": "catch", "target": t})
				check(not bool(r.ok), "catch: Platz %d nicht erwischbar" % t)
		check(not g.view_for(1).hints.can_mau, "%s: Platz 1 muss mit 1 Karte nicht rufen" % mode)
		var ev := sw_play(g, 1, "hell_rot_7", "Platz 1 legt die bekommene letzte Karte (%s)" % mode)
		check(not sw_names(ev).has("penalty") and g.phase() == "round_over" and int(g.result.ranking[0]) == 1,
			"%s: fertig ohne „Mau!“ und ohne Strafe (%s)" % [mode, str(sw_names(ev))])
	# auto: Die erste Handlung des Nächsten bringt keine Strafe für den Leger.
	var g2 := sw_make({"hands": [["hell_rot_tausch", "hell_gelb_7"], ["hell_blau_1", "hell_blau_2", "hell_blau_3"], ["hell_gruen_1", "hell_gruen_2"]],
		"top": "hell_rot_5", "draw": ["hell_blau_9"]}, {"mau_call": "auto"})
	sw_play(g2, 0, "hell_rot_tausch", "auto: Kartentausch mit 2 Karten")
	var ev2 := sw_act(g2, 1, {"a": "draw"}, "auto: Platz 1 zieht (nichts passt)")
	check(not sw_names(ev2).has("penalty"), "auto: keine Mau-Strafe nach dem Tausch (%s)" % str(sw_names(ev2)))
	# Bot ruft vor einem Kartentausch kein „Mau!“
	var g3 := sw_make({"hands": [["hell_rot_tausch", "hell_gelb_1"], ["hell_blau_1"], ["hell_gruen_1"]], "top": "hell_rot_5"})
	check(g3.view_for(0).hints.can_mau, "Bot-Fall: „Mau!“ wäre möglich")
	var a := MauBot.choose(g3.view_for(0), 1, 0)
	check(a.get("a", "") == "play" and int(a.get("card", -1)) == RulesFixture.card(g3, 0, "hell_rot_tausch"), "Bot: kein Ruf vor dem Kartentausch (%s)" % str(a))


func _sw_flip_after() -> void:
	var g := sw_make({"hands": [["hell_rot_tausch", "hell_rot_flip/dunkel_pink_9", "hell_gelb_1/dunkel_pink_2"], ["hell_blau_1/dunkel_lila_3"],
		["hell_gruen_1/dunkel_orange_4", "hell_gruen_2/dunkel_orange_5"]], "top": "hell_rot_5"})
	var ev := sw_play(g, 0, "hell_rot_tausch", "Kartentausch vor dem Flip")
	var e := sw_ev(ev, "swap_hands")
	check(RulesFixture.hand_keys(g, 1) == ["hell_rot_flip", "hell_gelb_1"], "Platz 1 hat Flip und Gelb 1")
	var backs: Array = []
	for s in 3:
		var b: Array = []
		for item in e.hands[s]:
			if int(item.id) != RulesFixture.card(g, 1, "hell_rot_flip"):
				b.append(str(item.back))
		backs.append(b)
	sw_play(g, 1, "hell_rot_flip", "Flip nach dem Tausch")
	check(g.side_name() == "dunkel", "Flip: dunkle Seite")
	for s in 3:
		check(RulesFixture.hand_keys(g, s) == backs[s], "Platz %d: getauschte Karten zeigen nach dem Flip ihre Rückseiten (%s / %s)"
			% [s, str(RulesFixture.hand_keys(g, s)), str(backs[s])])
	check(RulesFixture.hand_keys(g, 1) == ["dunkel_pink_2"], "Platz 1: Gelb 1 ist jetzt Pink 2")


func _sw_dark_side() -> void:
	var g := sw_make({"side": "dunkel", "hands": [["dunkel_lila_tausch", "dunkel_pink_1"], ["dunkel_pink_2", "dunkel_pink_3"], ["dunkel_orange_1"]],
		"top": "dunkel_lila_5"}, {"swap_direction": "play"})
	var old: Array = g.hands.duplicate(true)
	var tid := RulesFixture.card(g, 0, "dunkel_lila_tausch")
	sw_play(g, 0, "dunkel_lila_tausch", "Kartentausch auf der dunklen Seite")
	check(g.hands[1] == sw_without(old[0], tid) and g.hands[2] == old[1] and g.hands[0] == old[2], "dunkle Seite: Tausch in Spielrichtung +1")
	check(g.color == "lila" and g.current_seat() == 1, "dunkle Seite: Farbe Lila, Platz 1 dran")


# --- Lecktest an gebauten Lagen ---

func _sw_leak() -> void:
	for combo in [[true, true], [false, false], [true, false], [false, true]]:
		var opts := {"backs_visible": combo[0], "peek_own_backs": combo[1], "swap_direction": "play"}
		var g := sw_make({"hands": [["hell_rot_tausch/dunkel_pink_1", "hell_gelb_1/dunkel_lila_9", "hell_gelb_2/dunkel_farbjagd"],
			["hell_blau_1/dunkel_orange_3"], ["hell_blau_2/dunkel_pink_tausch", "hell_blau_3/dunkel_tuerkis_4"],
			["hell_gruen_1/dunkel_lila_tausch", "hell_gruen_2", "hell_gruen_3", "hell_gruen_4"]], "top": "hell_rot_5", "dir": -1}, opts, 4)
		var r := g.apply(0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_rot_tausch")})
		check(bool(r.ok), "Lecktest: Kartentausch gelegt")
		var raw := sw_ev(r.events, "swap_hands")
		for s in range(-1, 4):
			var err := _leak_events(g, r.events, s, [str(g._seed)])
			check(err == "", "Lecktest %s Platz %d: %s" % [str(combo), s, err])
			var err2 := _leak_view(g, s, [str(g._seed)])
			check(err2 == "", "Lecktest Sicht %s Platz %d: %s" % [str(combo), s, err2])
			var f := sw_ev(g.events_for(s, r.events), "swap_hands")
			# Erlaubte Gesichter im gefilterten Ereignis: eigene Hand (mit Rückseiten nur bei peek), fremde nur als Rückseiten.
			var allowed := {}
			for i in 4:
				for item in raw.hands[i]:
					if i == s:
						_add(allowed, str(item.face))
						if combo[1]:
							_add(allowed, str(item.back))
					elif combo[0]:
						_add(allowed, str(item.back))
			var got := {}
			_collect_keys(f, got, false)
			check(got == allowed, "Lecktest %s Platz %d: nur eigene Gesichter und fremde Rückseiten (zu viel: %s)" % [str(combo), s, str(_diff(got, allowed))])
			check(not f.has("hands") and (f.hand as Array).size() == (0 if s < 0 else (g.hands[s] as Array).size()), "Lecktest: nur die eigene Hand")
		check(raw.has("hands"), "ungefiltertes Ereignis enthält alle Hände (nur über events_for weitergeben)")


# --- Speichern ---

func _sw_round_trip() -> void:
	# Bot-Partie mit Kartentausch bis kurz nach einem Tausch, dann speichern, laden und beide gleich weiterspielen.
	var found := false
	for k in 40:
		var g := MauGame.create(sw_cfg({"swap_direction": "play" if k % 2 == 1 else "clockwise"}), RulesFixture.players(3 + k % 5, "bot"), 600_000 + k)
		g.start_round()
		var rng := RandomNumberGenerator.new()
		rng.seed = 77 + k
		var swapped := false
		for step in 600:
			if not g.state in MauGame.PLAY_PHASES:
				break
			var seat := g.current_seat()
			var r := g.apply(seat, MauBot.choose(g.view_for(seat), rng.randi(), 2))
			if not sw_ev(r.events, "swap_hands").is_empty():
				swapped = true
				break
		if not swapped:
			continue
		found = true
		var text := JSON.stringify(g.to_dict())
		var h := MauGame.from_dict(JSON.parse_string(text))
		check(h.n_cards == 116 and h.faces.size() == 232 and RulesFixture.card_check(h) == "" and RulesFixture.deck_check(h) == "",
			"geladen: 116 Karten (%s)" % RulesFixture.card_check(h))
		check(JSON.stringify(h.to_dict()) == text, "to_dict nach from_dict gleich")
		var same_views := true
		for s in range(-1, g.players.size()):
			if JSON.stringify(h.view_for(s)) != JSON.stringify(g.view_for(s)):
				same_views = false
		check(same_views, "Sichten nach dem Laden gleich")
		var r1 := RandomNumberGenerator.new()
		r1.seed = 5 + k
		var r2 := RandomNumberGenerator.new()
		r2.seed = 5 + k
		_advance(g, r1, 300)
		_advance(h, r2, 300)
		check(JSON.stringify(g.to_dict()) == JSON.stringify(h.to_dict()), "nach dem Laden gleich weitergespielt")
		break
	check(found, "Rundreise: Partie mit Kartentausch gefunden")
	# Alter Spielstand ohne die neuen Optionen lädt mit 112 Karten.
	var old := MauGame.create(RuleConfig.new(), RulesFixture.players(3), 9)
	old.start_round()
	var d := old.to_dict()
	(d.config as Dictionary).erase("swap_cards")
	(d.config as Dictionary).erase("swap_direction")
	var back := MauGame.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(back.n_cards == 112 and RulesFixture.card_check(back) == "" and back.config.swap_cards == "off", "alter Stand ohne swap_cards: 112 Karten")


# --- Passen, Punkte ---

func _sw_matching() -> void:
	var g := sw_make({"hands": [["hell_rot_tausch", "hell_gelb_tausch", "hell_blau_7"], ["hell_blau_1"], ["hell_gruen_1"]], "top": "hell_rot_5"})
	var pk: Array = []
	for id in g.view_for(0).hints.playable:
		pk.append(g._key[g.faces[g.side * g.n_cards + int(id)]])
	pk.sort()
	check(pk == ["hell_rot_tausch"], "Kartentausch passt auf seine Farbe (%s)" % str(pk))
	g = sw_make({"hands": [["hell_rot_tausch", "hell_gelb_7", "hell_blau_7"], ["hell_blau_1"], ["hell_gruen_1"]], "top": "hell_gelb_tausch"})
	pk = []
	for id in g.view_for(0).hints.playable:
		pk.append(g._key[g.faces[g.side * g.n_cards + int(id)]])
	pk.sort()
	check(pk == ["hell_gelb_7", "hell_rot_tausch"], "auf einem Kartentausch: gleiche Farbe oder jeder Kartentausch (%s)" % str(pk))
	var r := g.apply(0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_blau_7")})
	check(not bool(r.ok) and str(r.reason).contains("einen Kartentausch"), "Begründung nennt den Kartentausch (%s)" % r.reason)
	# Unter offener Stapelstrafe kein Kartentausch
	g = sw_make({"hands": [["hell_rot_plus1", "hell_rot_1"], ["hell_rot_tausch", "hell_blau_1"], ["hell_gruen_1"]], "top": "hell_rot_5"}, {"stacking": "same"})
	sw_play(g, 0, "hell_rot_plus1", "+1 legen")
	check((g.view_for(1).hints.playable as Array).is_empty(), "unter offener Strafe kein Kartentausch")
	# Startkarte Kartentausch bleibt liegen wie eine Aktionskarte, die nächste Karte wird aufgedeckt.
	g = sw_make({"hands": [["hell_blau_1"], ["hell_blau_2"], ["hell_gruen_1"]], "top": "hell_rot_5", "draw": ["hell_gelb_tausch", "hell_blau_3"]})
	var old_top: int = g.discard.pop_back()
	g.draw_pile.push_front(old_top)
	var ev: Array = []
	g._reveal_start_card(ev)
	check(ev.size() >= 2 and bool(ev[0].ignored) and str(ev[0].face) == "hell_gelb_tausch", "Kartentausch als Startkarte bleibt liegen")
	check(RulesFixture.top_key(g) == "hell_blau_3" and g.color == "blau", "darüber die nächste Zahl")
	check(RulesFixture.card_check(g) == "", "Startkarte: 116 Karten")


func _sw_points() -> void:
	var g := sw_make({"hands": [["hell_rot_7"], ["hell_blau_tausch", "hell_blau_1"], ["hell_gruen_tausch"]], "top": "hell_rot_5", "mau_said": [0]},
		{"scoring": "points500"})
	sw_play(g, 0, "hell_rot_7", "letzte Karte")
	check(g.result.points == [0, 21, 20], "Kartentausch zählt 20 Punkte (%s)" % str(g.result.points))
	check(int(g.result.gains[0]) == 41, "Sieger bekommt 41 Punkte")


# --- Bot ---

func _sw_bot_decide(g: MauGame, seat: int, level := 2) -> Dictionary:
	return MauBot.choose(g.view_for(seat), 3, level)


func _sw_bot_decisions() -> void:
	# Eigene Hand deutlich größer als die, die man bekommt (Vorgänger in Tauschrichtung = Platz 2): Kartentausch.
	var g := sw_make({"hands": [["hell_rot_tausch", "hell_rot_7", "hell_gelb_1", "hell_gelb_2", "hell_gelb_3", "hell_gelb_4", "hell_gelb_6"],
		["hell_blau_1", "hell_blau_2", "hell_blau_3", "hell_blau_4", "hell_blau_5"], ["hell_gruen_1", "hell_gruen_2"]], "top": "hell_rot_5"})
	var a := _sw_bot_decide(g, 0)
	check(int(a.get("card", -1)) == RulesFixture.card(g, 0, "hell_rot_tausch"), "Bot tauscht 6 gegen 2 Karten (%s)" % str(a))
	# Tauschrichtung Spielrichtung, Richtung −1: Vorgänger in Tauschrichtung ist Platz 1 (5 Karten) → nicht tauschen.
	g = sw_make({"hands": [["hell_rot_tausch", "hell_rot_7", "hell_gelb_1", "hell_gelb_2", "hell_gelb_3"],
		["hell_blau_1", "hell_blau_2", "hell_blau_3", "hell_blau_4", "hell_blau_5", "hell_blau_6", "hell_blau_7"], ["hell_gruen_1", "hell_gruen_2", "hell_gruen_3"]],
		"top": "hell_rot_5", "dir": -1}, {"swap_direction": "play"})
	a = _sw_bot_decide(g, 0)
	check(int(a.get("card", -1)) == RulesFixture.card(g, 0, "hell_rot_7"), "Bot tauscht nicht 4 gegen 7 Karten (Spielrichtung −1) (%s)" % str(a))
	# Selbst kurz vor dem Ende: nicht tauschen, sondern die Zahl legen (vorher „Mau!“).
	g = sw_make({"hands": [["hell_rot_tausch", "hell_rot_7"], ["hell_blau_1", "hell_blau_2", "hell_blau_3"],
		["hell_gruen_1", "hell_gruen_2", "hell_gruen_3", "hell_gruen_4", "hell_gruen_5", "hell_gruen_6"]], "top": "hell_rot_5"})
	a = _sw_bot_decide(g, 0)
	check(a.get("a", "") == "mau", "Bot mit 2 Karten ruft vor der Zahl „Mau!“ (%s)" % str(a))
	g.apply(0, a)
	a = _sw_bot_decide(g, 0)
	check(int(a.get("card", -1)) == RulesFixture.card(g, 0, "hell_rot_7"), "Bot kurz vor dem Ende tauscht nicht (%s)" % str(a))
	# Empfänger (Platz 1) kurz vor dem Ende: tauschen, auch wenn man gleich viele bekommt.
	g = sw_make({"hands": [["hell_rot_tausch", "hell_rot_7", "hell_gelb_1", "hell_gelb_2", "hell_gelb_3"], ["hell_blau_1"],
		["hell_gruen_1", "hell_gruen_2", "hell_gruen_3", "hell_gruen_4"]], "top": "hell_rot_5"})
	a = _sw_bot_decide(g, 0)
	check(int(a.get("card", -1)) == RulesFixture.card(g, 0, "hell_rot_tausch"), "Bot tauscht gegen einen Empfänger mit 1 Karte (%s)" % str(a))
	# Nur ein schlechter Kartentausch passt: lieber ziehen.
	g = sw_make({"hands": [["hell_rot_tausch", "hell_gelb_1", "hell_gelb_2"], ["hell_blau_1", "hell_blau_2"],
		["hell_gruen_1", "hell_gruen_2", "hell_gruen_3", "hell_gruen_4", "hell_gruen_5", "hell_gruen_6", "hell_gruen_7", "hell_gruen_8"]], "top": "hell_rot_5"})
	a = _sw_bot_decide(g, 0)
	check(a.get("a", "") == "draw", "Bot zieht statt eines schlechten Kartentauschs (%s)" % str(a))
	# Gezogener Kartentausch, der nicht lohnt: behalten.
	g = sw_make({"hands": [["hell_gelb_1", "hell_gelb_2"], ["hell_blau_1", "hell_blau_2"],
		["hell_gruen_1", "hell_gruen_2", "hell_gruen_3", "hell_gruen_4", "hell_gruen_5", "hell_gruen_6", "hell_gruen_7", "hell_gruen_8"]],
		"top": "hell_rot_5", "draw": ["hell_rot_tausch"]})
	g.apply(0, {"a": "draw"})
	check(g.phase() == "drawn", "gezogener Kartentausch passt")
	a = _sw_bot_decide(g, 0)
	check(a.get("a", "") == "keep", "Bot behält einen gezogenen Kartentausch, der nicht lohnt (%s)" % str(a))
	# Als letzte Karte immer legen.
	g = sw_make({"hands": [["hell_rot_tausch"], ["hell_blau_1", "hell_blau_2"], ["hell_gruen_1", "hell_gruen_2", "hell_gruen_3"]], "top": "hell_rot_5", "mau_said": [0]})
	a = _sw_bot_decide(g, 0)
	check(int(a.get("card", -1)) == RulesFixture.card(g, 0, "hell_rot_tausch"), "Bot legt den Kartentausch als letzte Karte (%s)" % str(a))
	# Bot nutzt nur die eigene Sicht: über JSON (Zahlen als float) gleiche Entscheidung.
	g = sw_make({"hands": [["hell_rot_tausch", "hell_rot_7", "hell_gelb_1", "hell_gelb_2", "hell_gelb_3", "hell_gelb_4", "hell_gelb_6"],
		["hell_blau_1", "hell_blau_2", "hell_blau_3", "hell_blau_4", "hell_blau_5"], ["hell_gruen_1", "hell_gruen_2"]], "top": "hell_rot_5"})
	var jv: Dictionary = JSON.parse_string(JSON.stringify(g.view_for(0)))
	a = MauBot.choose(jv, 3, 2)
	check(a.get("a", "") == "play" and int(a.card) == RulesFixture.card(g, 0, "hell_rot_tausch") and bool(g.apply(0, a).ok), "Bot auf JSON-Sicht (%s)" % str(a))


# Taktik mit Kartentausch: Stufe 2 gegen zwei Bots der Stufe 0, zu dritt, Platz reihum, beide Tauschrichtungen.
func _sw_strength() -> void:
	var t0 := Time.get_ticks_msec()
	var games := 600
	var wins := 0
	var swaps := 0
	var saved := swap_stats.duplicate()      # Zähler des Dauerlaufs bleiben unberührt
	for i in games:
		var strong := i % 3
		var levels := [0, 0, 0]
		levels[strong] = 2
		var g := MauGame.create(sw_cfg({"swap_direction": "play" if i % 2 == 1 else "clockwise"}), RulesFixture.players(3, "bot"), 9_900 + i)
		g.start_round()
		var rng := RandomNumberGenerator.new()
		rng.seed = 61 + i
		var before := int(swap_stats.get("tausch", 0))
		var err := _sw_bot_round(g, rng, levels, 0.0)
		swaps += int(swap_stats.get("tausch", 0)) - before
		if err != "":
			check(false, "Stärketest mit Kartentausch: " + err)
			return
		if int(g.result.ranking[0]) == strong:
			wins += 1
	swap_stats = saved
	print("Stärketest mit Kartentausch: %d von %d Partien (%d Tausche) in %.1f s" % [wins, games, swaps, (Time.get_ticks_msec() - t0) / 1000.0])
	check(wins > games * 0.37, "Taktik-Bot (Stufe 2) gewinnt mit Kartentausch deutlich öfter als ein Drittel (%d von %d)" % [wins, games])


# --- Bot-Dauerlauf ---

func _sw_bot_run() -> void:
	var games := SWAP_GAMES
	if OS.get_environment("RULES_SWAP_GAMES").is_valid_int():
		games = int(OS.get_environment("RULES_SWAP_GAMES"))
	var t0 := Time.get_ticks_msec()
	var errors := 0
	var all_games := games
	games = 0
	for i in all_games:
		if not Teil.mine(i):
			continue
		games += 1
		var err := _sw_bot_game(i)
		if err != "":
			errors += 1
			if errors <= 10:
				print("FAIL: Partie %d: %s" % [i, err])
	check(errors == 0, "Bot-Dauerlauf mit Kartentausch: %d von %d Partien fehlerhaft" % [errors, games])
	check(int(swap_stats.get("tausch", 0)) > games / 2, "Kartentausch kommt im Dauerlauf oft vor (%d)" % int(swap_stats.get("tausch", 0)))
	check(int(swap_stats.get("tausch_spielrichtung", 0)) > 0 and int(swap_stats.get("tausch_letzte_karte", 0)) > 0,
		"Dauerlauf: Tausch gegen den Uhrzeigersinn und als letzte Karte kommen vor")
	check(int(swap_stats.get("mau_blind", 0)) == 0, "Bots rufen „Mau!“ nur vor dem Legen (%d blind)" % int(swap_stats.get("mau_blind", 0)))
	print("Bot-Dauerlauf mit Kartentausch%s: %d Partien in %.1f s – %s" % [Teil.label(), games, (Time.get_ticks_msec() - t0) / 1000.0, str(swap_stats)])


func _sw_bot_game(i: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7_100_019 * i + 11
	var cfg := RulesFixture.random_config(rng, true)
	var n := rng.randi_range(2, 10)
	var levels: Array = []
	for s in n:
		levels.append(rng.randi_range(0, 2))
	var g := MauGame.create(cfg, RulesFixture.players(n, "bot"), rng.randi())
	g.start_round()
	var extra := 1 if rng.randf() < 0.2 else 0
	var forget := rng.randf() * 0.5
	for r in SWAP_ROUND_LIMIT:
		if g.n_cards != 116 or g.config.swap_cards != "on":
			return "Kartenzahl %d" % g.n_cards
		var dc := RulesFixture.deck_check(g)
		if dc != "":
			return "Runde %d: %s" % [g.round_no, dc]
		var err := _sw_bot_round(g, rng, levels, forget)
		if err != "":
			return "Runde %d (%d Spieler, %s): %s" % [g.round_no, n, JSON.stringify(cfg.to_dict()), err]
		sw_count("runden")
		if g.result.get("reason", "") == "blockiert":
			sw_count("blockiert")
		if g.is_over():
			sw_count("partien_500")
			return ""
		if cfg.effective_scoring() != "points500":
			if extra <= 0:
				return ""
			extra -= 1
		var res := g.apply(0, {"a": "next_round"})
		if not bool(res.ok):
			return "next_round abgelehnt: " + str(res.reason)
	return "" if cfg.effective_scoring() == "points500" else "zu viele Runden"


func _sw_bot_round(g: MauGame, rng: RandomNumberGenerator, levels: Array, forget: float) -> String:
	var n := g.players.size()
	var steps := 0
	var mau_seat := -1
	while g.state in MauGame.PLAY_PHASES:
		steps += 1
		if steps > SWAP_STEP_LIMIT:
			return "Zugobergrenze %d erreicht" % SWAP_STEP_LIMIT
		if g.mau_open >= 0 and rng.randf() < 0.6:
			var o := rng.randi_range(0, n - 1)
			var ca := MauBot.choose(g.view_for(o), rng.randi(), int(levels[o]))
			if str(ca.get("a", "")) == "catch":
				var cr := g.apply(o, ca)
				if not bool(cr.ok):
					return "catch abgelehnt: " + str(cr.reason)
				sw_count("erwischt")
		var seat := g.current_seat()
		var view := g.view_for(seat)
		if bool(view.hints.can_mau) and rng.randf() < forget:
			view.hints.can_mau = false
		var act := MauBot.choose(view, rng.randi(), int(levels[seat]))
		if act.is_empty():
			return "Bot ohne Aktion in Phase %s (%s)" % [g.state, str(view.hints)]
		var kind := str(act.get("a", ""))
		if kind != "catch":
			if mau_seat == seat and kind != "play":
				sw_count("mau_blind")
			mau_seat = -1
		if kind == "mau" and (g.hands[seat] as Array).size() == 2:
			mau_seat = seat
		var res := g.apply(seat, act)
		if not bool(res.ok):
			return "Aktion %s abgelehnt: %s" % [JSON.stringify(act), res.reason]
		sw_count("aktionen")
		for e in res.events:
			match str(e.e):
				"swap_hands":
					sw_count("tausch")
					if int(e.dir) != g.config.swap_step(g.dir):
						return "swap_hands: Richtung %d" % int(e.dir)
					if int(e.dir) == -1:
						sw_count("tausch_spielrichtung")
					if int(g.place[int(e.seat)]) != 0:
						sw_count("tausch_letzte_karte")
					for s in n:
						if int(e.counts[s]) != (g.hands[s] as Array).size():
							return "swap_hands: counts %s passen nicht zu den Händen" % str(e.counts)
					if g.mau_open != -1 or g.mau_said.has(true):
						return "nach dem Tausch noch Mau-Fenster oder Ruf offen"
				"flip":
					sw_count("flip")
		var inv := RulesFixture.invariants(g)
		if inv != "":
			return "nach %s: %s" % [JSON.stringify(act), inv]
	return ""
