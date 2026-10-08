extends "res://tests/test_rules_views.gd"
# Modul A: Hausregel Glücksspiel (gamble_cards = "on", 2 zusätzliche Joker; Nutzerwunsch 05.10.2026, Festlegung des Koordinators).
# Gebaute Fälle: Kartendaten aller 8 Deckvarianten (Kartenzahl, Gesichter, Prüfsummen, Codes, Sortierung), Optionen und Texte,
# Rundenstart, Legen und Phase "gamble" samt Ablehnungen, Setzen/Drücken mit vorgegebenen Würfen (MauGame.force_rolls), Treffer,
# Fertigwerden bei round_end first/last, letzte Karte, Mau-Fenster und Erwischen im Glücksspiel, offene Stapelstrafe, Flip,
# leere Stapel, zu zweit, mit Kartentausch, Zufall (Quote gleichverteilt, Treffer 1/q, Werte 1–10), Lecktest (Quote und
# Einsatzgesichter nie bei anderen), to_dict/from_dict mitten im Glücksspiel und Bot-Entscheidungen. Danach die Zufallsprüfungen
# aus test_rules_views.gd mit Glücksspiel (gamble_mode() = true), ein Stärketest und der Bot-Dauerlauf mit ALLEN Hausregeln an
# (Kartentausch, Glücksspiel, Farbe mit ablegen): Standard 2000 Partien (RULES_GAMBLE_GAMES, godot_run.ps1 -EnvPairs
# 'RULES_GAMBLE_GAMES=200').

const GB_GAMES := 2000
const GB_STEP_LIMIT := 5000      # Aktionen je Runde; mehr = Endlosschleife
const GB_ROUND_LIMIT := 40       # Runden je Partie (Punktewertung)

var gb_stats := {}


func gamble_mode() -> bool:
	return true


func _initialize() -> void:
	# Aufteilung (tests/teil.gd, TEIL=k/n): Einzel- und Zufallsprüfungen nur in Teil 1, die Partien des Bot-Dauerlaufs reihum.
	if not Teil.first():
		_gb_bot_run()
		print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
		quit(0 if failures == 0 else 1)
		return
	_gb_cards()
	_gb_config_and_texts()
	_gb_start()
	_gb_play_and_phase()
	_gb_hit()
	_gb_finish_first()
	_gb_finish_last()
	_gb_last_card()
	_gb_mau()
	_gb_stop()
	_gb_stop_mau()
	_gb_pending()
	_gb_flip()
	_gb_empty_piles()
	_gb_two_players()
	_gb_with_swap()
	_gb_random()
	_gb_leak()
	_gb_round_trip()
	_gb_bot_decisions()
	_gb_bot_stop()
	var t0 := Time.get_ticks_msec()
	_json_views()
	_leak_runs()
	_hint_consistency()
	_round_trip()
	print("Zufallsprüfungen mit Glücksspiel: %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	_gb_strength()
	_gb_bot_run()
	print("Laufzeit seit Godot-Start: %.1f s" % (Time.get_ticks_msec() / 1000.0))
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)


# --- Hilfen ---

func gb_cfg(over := {}) -> RuleConfig:
	var d := {"gamble_cards": "on"}
	d.merge(over, true)
	return RuleConfig.from_dict(d)


func gb_make(spec: Dictionary, over := {}, n := 3) -> MauGame:
	var g := RulesFixture.build(gb_cfg(over), n, spec)
	var cc := RulesFixture.card_check(g)
	var dc := RulesFixture.deck_check(g)
	check(g.n_cards == g.config.card_count() and cc == "" and dc == "", "Aufbau mit %d Karten: %s %s" % [g.n_cards, cc, dc])
	return g


func gb_act(g: MauGame, seat: int, action: Dictionary, msg: String) -> Array:
	var r := g.apply(seat, action)
	check(bool(r.ok), "%s (abgelehnt: %s)" % [msg, r.reason])
	var inv := RulesFixture.invariants(g)
	check(inv == "", "%s: %s" % [msg, inv])
	return r.events


func gb_play(g: MauGame, seat: int, key: String, msg: String, col := "") -> Array:
	var id := RulesFixture.card(g, seat, key)
	check(id >= 0, "%s: Karte %s bei Platz %d" % [msg, key, seat])
	var a := {"a": "play", "card": id}
	if col != "":
		a["color"] = col
	return gb_act(g, seat, a, msg)


func gb_stake(g: MauGame, seat: int, key: String, msg: String) -> Array:
	var id := RulesFixture.card(g, seat, key)
	check(id >= 0, "%s: Karte %s bei Platz %d" % [msg, key, seat])
	return gb_act(g, seat, {"a": "stake", "card": id}, msg)


func gb_press(g: MauGame, seat: int, roll: int, msg: String) -> Array:
	g.force_rolls([roll])
	return gb_act(g, seat, {"a": "press"}, msg)


# Abgelehnte Aktion: Grund wie erwartet (want "" = egal) und Zustand unverändert.
func gb_reject(g: MauGame, seat: int, action: Dictionary, want: String, msg: String) -> void:
	var before := JSON.stringify(g.to_dict())
	var r := g.apply(seat, action)
	check(not bool(r.ok) and (want == "" or str(r.reason) == want), "%s: abgelehnt mit „%s“ (%s, %s)" % [msg, want, str(r.ok), r.reason])
	check(JSON.stringify(g.to_dict()) == before, "%s: Zustand unverändert" % msg)


func gb_ev(ev: Array, e_name: String) -> Dictionary:
	for e in ev:
		if str(e.e) == e_name:
			return e
	return {}


func gb_names(ev: Array) -> Array:
	var out: Array = []
	for e in ev:
		out.append(str(e.e))
	return out


func gb_count(key: String, n := 1) -> void:
	gb_stats[key] = int(gb_stats.get(key, 0)) + n


func gb_keys(g: MauGame, ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		out.append(g._key[g.faces[g.side * g.n_cards + int(id)]])
	return out


# --- Kartendaten aller Deckvarianten ---

func _gb_cards() -> void:
	var ptab := CardDB.points_table()
	for mask in 8:
		var sw := mask & 1 != 0
		var ga := mask & 2 != 0
		var di := mask & 4 != 0
		var want_cards := 112 + (4 if sw else 0) + (2 if ga else 0) + (6 if di else 0)
		var want_faces := 108 + (8 if sw else 0) + (2 if ga else 0) + (10 if di else 0)
		var cfg := RuleConfig.from_dict({"swap_cards": "on" if sw else "off", "gamble_cards": "on" if ga else "off",
			"discard_color": "on" if di else "off"})
		var label := "Variante %s%s%s" % ["T" if sw else "-", "G" if ga else "-", "A" if di else "-"]
		check(CardDB.card_count(sw, ga, di) == want_cards and cfg.card_count() == want_cards, "%s: %d Karten" % [label, want_cards])
		check(CardDB.face_count(sw, ga, di) == want_faces, "%s: %d Gesichter" % [label, want_faces])
		var distinct := {}
		for s in 2:
			var deck := CardDB.deck(s, sw, ga, di)
			check(deck == cfg.deck(s), "%s: RuleConfig.deck = CardDB.deck" % label)
			check(deck.size() == want_cards, "%s Seite %d: %d Karten (%d)" % [label, s, want_cards, deck.size()])
			var sum := 0
			var wrong_side := 0
			for c in deck:
				sum += ptab[c]
				distinct[c] = true
				if CardDB.side_table()[c] != s:
					wrong_side += 1
			check(wrong_side == 0, "%s Seite %d: alle Gesichter von dieser Seite" % [label, s])
			var want_sum := (1280 if s == 0 else 1480) + (80 if sw else 0) + (100 if ga else 0) + (220 if di else 0)
			check(sum == want_sum and CardDB.point_sum(s, sw, ga, di) == want_sum, "%s Seite %d: Prüfsumme %d (%d)" % [label, s, want_sum, sum])
			# Das Grunddeck steht unverändert vorn (Paarung aus dem Seed bleibt für alte Varianten gleich).
			check(deck.slice(0, 112) == CardDB.deck(s), "%s Seite %d: Grunddeck vorn" % [label, s])
			if sw:
				check(deck.slice(112, 116) == CardDB.deck(s, true).slice(112, 116), "%s: Kartentausch direkt hinter dem Grunddeck" % label)
		check(distinct.size() == want_faces, "%s: %d verschiedene Gesichter (%d)" % [label, want_faces, distinct.size()])
		var fl := CardDB.faces_light(sw, ga, di)
		var fd := CardDB.faces_dark(sw, ga, di)
		check(fl.size() == want_cards and fd.size() == want_cards, "%s: faces_light/dark" % label)
	check(CardDB.CARD_COUNT_ALL == 124 and CardDB.FACE_COUNT_ALL == 128 and CardDB.SUM_LIGHT_ALL == 1680 and CardDB.SUM_DARK_ALL == 1880,
		"Konstanten aller Hausregeln 124/128/1680/1880")
	check(CardDB.point_sum(0, true, true, true) == CardDB.SUM_LIGHT_ALL and CardDB.point_sum(1, true, true, true) == CardDB.SUM_DARK_ALL,
		"point_sum aller Hausregeln")
	# Feste Codes: Grunddeck 0–107, Kartentausch 108–115, Glücksspiel 116/117, Farbe mit ablegen 118–127.
	var kt := CardDB.key_table()
	check(kt.size() == 128, "128 Codes (%d)" % kt.size())
	var stable := true
	for i in 108:
		if kt[i] != CardDB.all_keys()[i]:
			stable = false
	check(stable, "Codes 0–107 unverändert")
	check(Array(kt.slice(108, 116)) == ["hell_rot_tausch", "hell_gelb_tausch", "hell_gruen_tausch", "hell_blau_tausch",
		"dunkel_pink_tausch", "dunkel_tuerkis_tausch", "dunkel_orange_tausch", "dunkel_lila_tausch"], "Codes 108–115 Kartentausch")
	check(Array(kt.slice(116, 128)) == ["hell_gluecksspiel", "dunkel_gluecksspiel", "hell_rot_ablegen", "hell_gelb_ablegen",
		"hell_gruen_ablegen", "hell_blau_ablegen", "hell_ablegen_joker", "dunkel_pink_ablegen", "dunkel_tuerkis_ablegen",
		"dunkel_orange_ablegen", "dunkel_lila_ablegen", "dunkel_ablegen_joker"], "Codes 116–127 (%s)" % str(kt.slice(116, 128)))
	check(Array(CardDB.gamble_keys()) == ["hell_gluecksspiel", "dunkel_gluecksspiel"], "gamble_keys")
	for k in CardDB.gamble_keys():
		var f := CardDB.parse_key(k)
		check(CardDB.is_key(k) and CardDB.face_key(f) == k, "Rundreise Schlüssel " + k)
		check(CardDB.points_of_key(k) == 50 and CardDB.points(f) == 50, "50 Punkte: " + k)
		check(CardDB.is_wild(f) and CardDB.is_gamble(f) and CardDB.is_action(f) and not CardDB.is_draw_card(f) and not CardDB.is_discard(f),
			"Art gluecksspiel ist ein Joker: " + k)
		check(Array(CardDB.all_keys(true)).has(k) and not Array(CardDB.all_keys()).has(k), "all_keys(true) enthält " + k)
	var all_sorted := Array(CardDB.all_keys(true))
	check(all_sorted.size() == 128 and CardDB.sort_keys(all_sorted) == all_sorted, "all_keys(true): 128, sortiert")
	check(CardDB.all_keys().size() == 108, "all_keys() bleibt beim Grunddeck (Vertrag mit den Kartenbildern)")
	var sorted := CardDB.sort_keys(["dunkel_gluecksspiel", "hell_gluecksspiel", "hell_wuenscher_plus2", "hell_ablegen_joker", "hell_wuenscher",
		"hell_blau_ablegen", "hell_blau_tausch", "hell_blau_flip", "dunkel_farbjagd", "dunkel_ablegen_joker"])
	check(sorted == ["hell_blau_flip", "hell_blau_tausch", "hell_blau_ablegen", "hell_wuenscher", "hell_wuenscher_plus2", "hell_gluecksspiel",
		"hell_ablegen_joker", "dunkel_farbjagd", "dunkel_gluecksspiel", "dunkel_ablegen_joker"], "Sortierung der neuen Karten (%s)" % str(sorted))
	check(RulesText.face_title("hell_gluecksspiel") == "Glücksspiel" and RulesText.kind_name("gluecksspiel") == "Glücksspiel"
		and RulesText.match_phrase("dunkel_gluecksspiel") == "ein Glücksspiel", "Namen Glücksspiel")


# --- Optionen und Texte ---

func _gb_config_and_texts() -> void:
	var c := RuleConfig.new()
	check(c.gamble_cards == "off" and c.discard_color == "off" and c.card_count() == 112, "Standard: kein Glücksspiel, keine Ablegen-Karten")
	for p in RuleConfig.preset_names():
		check((RuleConfig.preset(p).gamble_cards == "on" and RuleConfig.preset(p).discard_color == "on") == (p == "familie"),
			"Voreinstellung %s: Glücksspiel und Farbe ablegen nur bei Familie" % p)
	var on := gb_cfg()
	check(on.card_count() == 114 and on.preset_name() == "", "gamble_cards=on: 114 Karten, eigene Regeln")
	check(RuleConfig.from_dict(JSON.parse_string(JSON.stringify(on.to_dict()))).equals(on), "Rundreise über JSON")
	check(RuleConfig.from_dict({"gamble_cards": "ja", "discard_color": true}).gamble_cards == "off", "ungültige Werte bleiben beim Standard")
	var all_on := gb_cfg({"swap_cards": "on", "discard_color": "on"})
	check(all_on.card_count() == 124 and all_on.has_extra_cards() and not c.has_extra_cards(), "alle Hausregeln: 124 Karten")
	check(not "\n".join(c.describe()).contains("Glücksspiel"), "describe ohne Glücksspiel")
	var d_on := "\n".join(on.describe())
	check(d_on.contains("Glücksspiel") and d_on.contains("(114)") and d_on.contains("1 bis 10"), "describe mit Glücksspiel (%s)" % d_on)
	check("\n".join(all_on.describe()).contains("124 Karten"), "describe mit allen Hausregeln: 124 Karten")
	# Kartenhilfe
	var h := "\n".join(RulesText.card_help("hell_gluecksspiel", on))
	for part in ["passt immer", "Einsatz", "1:1 und 1:10", "1 bis 10", "gewinnst die Runde", "auch aufhören", "„Mau!“",
			"wirken nicht", "letzte Karte", "50 Punkte"]:
		check(h.contains(part), "Hilfe Glücksspiel enthält „%s“ (%s)" % [part, h])
	var h2 := "\n".join(RulesText.card_help("dunkel_gluecksspiel", gb_cfg({"round_end": "last", "mau_call": "off", "stacking": "same"})))
	check(not h2.contains("gewinnst") and h2.contains("du bist fertig") and not h2.contains("Mau") and h2.contains("Ziehstrafe"),
		"Hilfe Glücksspiel bis zum Letzten, ohne Mau, mit Stapeln (%s)" % h2)
	check("\n".join(RulesText.card_help("hell_gluecksspiel", RuleConfig.new())).contains("gerade nicht im Spiel"), "Hilfe ohne Hausregel")
	# Übersicht
	var text_on := ""
	var titles_on: Array = []
	for p in RulesText.overview(on):
		titles_on.append(p.title)
		text_on += str(p.text) + "\n"
	var text_off := ""
	var titles_off: Array = []
	for p in RulesText.overview(RuleConfig.new()):
		titles_off.append(p.title)
		text_off += str(p.text) + "\n"
	check(titles_on.has("Glücksspiel") and text_on.contains("114 Karten") and text_on.contains("zwei Glücksspiel-Joker"), "Übersicht mit Glücksspiel")
	check(text_on.contains("auch aufhören"), "Übersicht nennt das Aufhören")
	check(not titles_off.has("Glücksspiel") and text_off.contains("112 Karten") and not text_off.contains("zwei Glücksspiel-Joker"),
		"Übersicht ohne Glücksspiel: kein eigener Absatz, 112 Karten")
	# Besondere Karten der ausgeschalteten Hausregeln stehen kurz in einem eigenen Absatz (Nutzerwunsch: Anleitung „Regeln“).
	var more_off := ""
	for p in RulesText.overview(RuleConfig.new()):
		if str(p.title) == "Weitere besondere Karten":
			more_off = str(p.text)
	check(more_off.contains("Kartentausch") and more_off.contains("Glücksspiel-Joker") and more_off.contains("hörst auf")
		and more_off.contains("Farbe ablegen"), "Übersicht ohne Hausregeln: weitere besondere Karten (%s)" % more_off)
	var more_on := ""
	for p in RulesText.overview(on):
		if str(p.title) == "Weitere besondere Karten":
			more_on = str(p.text)
	check(not more_on.contains("Glücksspiel") and more_on.contains("Kartentausch"), "eingeschaltete Hausregel nicht doppelt (%s)" % more_on)
	var all_titles: Array = []
	for p in RulesText.overview(gb_cfg({"swap_cards": "on", "discard_color": "on"})):
		all_titles.append(p.title)
	check(not all_titles.has("Weitere besondere Karten"), "alle Hausregeln an: kein Zusatzabsatz")
	var ov_all := ""
	for p in RulesText.overview(gb_cfg({"swap_cards": "on", "discard_color": "on", "scoring": "points500"})):
		ov_all += str(p.text) + "\n"
	check(ov_all.contains("124 Karten") and ov_all.contains("Kartentausch-Karten") and ov_all.contains("Ablegen-Joker")
		and ov_all.contains("Wünscher +2, Glücksspiel und Ablegen-Joker 50") and ov_all.contains("Alle aussetzen und Farbe ablegen 30"),
		"Übersicht mit allen Hausregeln und Punkten (%s)" % ov_all)


# --- Rundenstart ---

func _gb_start() -> void:
	var bad := ""
	for s in 60:
		var all := s % 3 == 0
		var cfg := gb_cfg({"hand_size": 5 + s % 6, "swap_cards": "on" if all else "off", "discard_color": "on" if all else "off"})
		var n := 2 + s % 9
		var g := MauGame.create(cfg, RulesFixture.players(n, "bot"), 9_000_011 * s + 7)
		g.start_round()
		var want := 124 if all else 114
		var gfaces := 0
		for code in g.faces:
			if CardDB.kind_table()[code] == CardDB.GAMBLE:
				gfaces += 1
		if g.n_cards != want or g.faces.size() != want * 2:
			bad = "n_cards %d" % g.n_cards
		elif RulesFixture.card_check(g) != "" or RulesFixture.deck_check(g) != "":
			bad = RulesFixture.card_check(g) + RulesFixture.deck_check(g)
		elif gfaces != 4:
			bad = "%d Glücksspiel-Gesichter statt 4" % gfaces
		elif CardDB.kind_table()[g.faces[int(g.discard.back())]] != "zahl":
			bad = "Startkarte keine Zahl"
		elif g.view_for(0).gamble != {} or not g.view_for(0).hints.has("can_stake"):
			bad = "Sicht ohne leeres gamble bzw. can_stake"
		g.state = "round_over"
		g.apply(0, {"a": "next_round"})
		if RulesFixture.card_check(g) != "" or RulesFixture.deck_check(g) != "":
			bad = "Runde 2: " + RulesFixture.card_check(g) + RulesFixture.deck_check(g)
	check(bad == "", "Rundenstart mit Glücksspiel über 60 Seeds: " + bad)
	var off := MauGame.create(RuleConfig.new(), RulesFixture.players(3), 3)
	off.start_round()
	var v := off.view_for(0)
	check(not v.has("gamble") and not v.hints.has("can_stake") and not v.hints.has("can_press") and not off.to_dict().has("gamble"),
		"ohne Hausregel: keine Glücksspiel-Felder in Sicht, Hinweisen und Spielstand")
	var r := off.apply(1, {"a": "press"})
	check(not bool(r.ok) and str(r.reason) == "Glücksspiel gibt es in diesen Regeln nicht.", "ohne Hausregel: press abgelehnt (%s)" % r.reason)


# --- Legen und Phase ---

func _gb_play_and_phase() -> void:
	var g := gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1", "hell_gelb_2", "hell_blau_3"], ["hell_blau_1", "hell_blau_2"],
		["hell_gruen_1", "hell_gruen_2"]], "top": "hell_rot_5"})
	var gid := RulesFixture.card(g, 0, "hell_gluecksspiel")
	check((g.view_for(0).hints.playable as Array).has(gid) and (g.view_for(0).hints.wild as Array).has(gid), "Glücksspiel passt immer und braucht eine Farbe")
	gb_reject(g, 0, {"a": "play", "card": gid}, "", "Glücksspiel ohne Farbe")
	gb_reject(g, 0, {"a": "stake", "card": RulesFixture.card(g, 0, "hell_gelb_1")}, "Gerade läuft kein Glücksspiel.", "stake vor dem Glücksspiel")
	gb_reject(g, 0, {"a": "press"}, "Gerade läuft kein Glücksspiel.", "press vor dem Glücksspiel")
	var ev := gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel legen", "gelb")
	check(gb_names(ev) == ["play", "color", "gamble_start"], "Ereignisse play, color, gamble_start (%s)" % str(gb_names(ev)))
	check(int(gb_ev(ev, "gamble_start").seat) == 0 and gb_ev(ev, "gamble_start").size() == 2, "gamble_start {e, seat}")
	check(g.phase() == "gamble" and g.current_seat() == 0 and g.color == "gelb" and g.wished, "Phase gamble, Platz 0, Wunschfarbe Gelb")
	check(int(g.gamble.q) >= 1 and int(g.gamble.q) <= 10 and str(g.gamble.need) == "stake" and (g.gamble.stake as Array).is_empty(), "Quote 1–10 gelost")
	for s in range(-1, 3):
		var v := g.view_for(s)
		check(v.gamble == {"seat": 0, "stake": 0, "need": "stake", "last": -1}, "Sicht %d: gamble öffentlich (%s)" % [s, str(v.gamble)])
		check(v.turn == 0 and v.phase == "gamble", "Sicht %d: Platz 0 am Zug in Phase gamble" % s)
	var v0 := g.view_for(0)
	check(v0.hints.can_stake == g.hands[0] and not v0.hints.can_press and (v0.hints.playable as Array).is_empty() and not v0.hints.can_draw,
		"Hinweise: alle Handkarten setzbar, nichts anderes")
	check(v0.hints.text == "Leg eine Karte verdeckt auf deinen Einsatz.", "Hinweistext Setzen (%s)" % v0.hints.text)
	var v1 := g.view_for(1)
	check((v1.hints.can_stake as Array).is_empty() and not v1.hints.can_press and str(v1.hints.text).contains("Anna spielt Glücksspiel"),
		"andere: keine Glücksspiel-Hinweise, Text „spielt Glücksspiel“ (%s)" % v1.hints.text)
	gb_reject(g, 0, {"a": "press"}, "Leg erst eine Karte verdeckt auf deinen Einsatz.", "press vor dem Setzen")
	gb_reject(g, 0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_gelb_1")}, "Erst eine Karte verdeckt auf den Einsatz legen.", "play im Glücksspiel")
	gb_reject(g, 0, {"a": "draw"}, "Erst eine Karte verdeckt auf den Einsatz legen.", "draw im Glücksspiel")
	gb_reject(g, 0, {"a": "keep"}, "Erst eine Karte verdeckt auf den Einsatz legen.", "keep im Glücksspiel")
	gb_reject(g, 1, {"a": "stake", "card": RulesFixture.card(g, 1, "hell_blau_1")}, "Du bist nicht dran.", "stake eines anderen")
	gb_reject(g, 1, {"a": "press"}, "Du bist nicht dran.", "press eines anderen")
	gb_reject(g, 0, {"a": "stake", "card": RulesFixture.card(g, 1, "hell_blau_1")}, "Diese Karte hast du nicht.", "fremde Karte setzen")
	gb_reject(g, 0, {"a": "stake"}, "Diese Karte hast du nicht.", "stake ohne Karte")
	for bad in ["x", 1.5, null, [], {}]:
		gb_reject(g, 0, {"a": "stake", "card": bad}, "Ungültige Aktion.", "stake mit card=%s" % str(bad))
	var sid := RulesFixture.card(g, 0, "hell_blau_3")
	ev = gb_act(g, 0, {"a": "stake", "card": float(sid)}, "Blau 3 setzen (id als JSON-Zahl)")
	var se := gb_ev(ev, "stake")
	check(gb_names(ev) == ["stake"] and int(se.count) == 1 and int(se.card) == sid and se.face == "hell_blau_3", "Ereignis stake (%s)" % str(se))
	check(str(g.gamble.need) == "press" and g.gamble.stake == [sid] and (g.hands[0] as Array).size() == 2, "Einsatz 1, jetzt drücken")
	v0 = g.view_for(0)
	check(v0.gamble == {"seat": 0, "stake": 1, "need": "press", "last": -1} and v0.hints.can_press and (v0.hints.can_stake as Array).is_empty(),
		"Sicht nach dem Setzen")
	check(v0.hints.text == "Drück den Glücksspielknopf!", "Hinweistext Drücken (%s)" % v0.hints.text)
	gb_reject(g, 0, {"a": "stake", "card": RulesFixture.card(g, 0, "hell_gelb_1")}, "Erst den Glücksspielknopf drücken.", "zweimal setzen")
	gb_reject(g, 0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_gelb_1")}, "Erst den Glücksspielknopf drücken.", "play vor dem Drücken")
	ev = gb_press(g, 0, 0, "drücken: kein Treffer")
	check(gb_names(ev) == ["gamble_roll"] and int(gb_ev(ev, "gamble_roll").value) == 0, "Ereignis gamble_roll 0 (%s)" % str(ev))
	check(g.phase() == "gamble" and str(g.gamble.need) == "stake" and int(g.gamble.last) == 0 and g.current_seat() == 0, "kein Treffer: weiter setzen")
	check(g.view_for(2).gamble.last == 0 and g.view_for(2).gamble.stake == 1, "Sicht zeigt den letzten Wert 0")
	check(g.view_for(0).hints.can_mau and str(g.view_for(0).hints.text).contains("Denk an „Mau!“"), "mit 2 Karten vor dem Setzen: Mau möglich")


func _gb_hit() -> void:
	for dir in [1, -1]:
		var g := gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1", "hell_gelb_2", "hell_gelb_3"], ["hell_blau_1", "hell_blau_2"],
			["hell_gruen_1", "hell_gruen_2"]], "top": "hell_rot_5", "draw": ["hell_rot_1", "hell_rot_2", "hell_rot_3", "hell_rot_4"], "dir": dir})
		gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel (Richtung %d)" % dir, "blau")
		var keep := RulesFixture.card(g, 0, "hell_gelb_3")
		var s1 := RulesFixture.card(g, 0, "hell_gelb_1")
		var s2 := RulesFixture.card(g, 0, "hell_gelb_2")
		gb_stake(g, 0, "hell_gelb_1", "setzen 1")
		gb_press(g, 0, 0, "drücken 1: 0")
		gb_stake(g, 0, "hell_gelb_2", "setzen 2")
		var ev := gb_press(g, 0, 3, "drücken 2: Treffer 3")
		var want_next := 1 if dir == 1 else 2
		check(gb_names(ev) == ["gamble_roll", "draw", "stake_back", "turn"], "Treffer: gamble_roll, draw, stake_back, turn (%s)" % str(gb_names(ev)))
		var de := gb_ev(ev, "draw")
		check(int(de.seat) == 0 and int(de.count) == 3 and str(de.reason) == "gluecksspiel" and de.faces == ["hell_rot_1", "hell_rot_2", "hell_rot_3"],
			"Treffer: 3 Karten gezogen, Grund gluecksspiel (%s)" % str(de))
		var sb := gb_ev(ev, "stake_back")
		check(int(sb.count) == 2 and sb.cards == [s1, s2] and sb.faces == ["hell_gelb_1", "hell_gelb_2"], "stake_back: ganzer Einsatz zurück (%s)" % str(sb))
		check(gb_keys(g, g.hands[0]) == ["hell_gelb_3", "hell_rot_1", "hell_rot_2", "hell_rot_3", "hell_gelb_1", "hell_gelb_2"] and g.hands[0][0] == keep,
			"Hand: Rest, gezogene Karten, Einsatz (%s)" % str(gb_keys(g, g.hands[0])))
		check(g.phase() == "turn" and g.current_seat() == want_next and g.gamble.is_empty(), "Zug vorbei: Nächster in Spielrichtung (%d)" % g.current_seat())
		check(g.color == "blau" and g.wished and RulesFixture.top_key(g) == "hell_gluecksspiel", "gewünschte Farbe gilt nach dem Glücksspiel")
		check(g.view_for(1).gamble == {} and int(g.view_for(1).players[0].count) == 6, "Sicht danach: gamble leer, 6 Karten")


func _gb_finish_first() -> void:
	var g := gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1", "hell_gelb_2"], ["hell_blau_1", "hell_blau_7"], ["hell_gruen_1"]],
		"top": "hell_rot_5"}, {"scoring": "points500"})
	var under: Array = g.discard.duplicate()
	gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel mit 2 Restkarten", "rot")
	check(g.view_for(0).hints.can_mau, "vor dem Setzen der vorletzten Karte: Mau möglich")
	gb_act(g, 0, {"a": "mau"}, "Mau vor dem Setzen")
	var s1 := RulesFixture.card(g, 0, "hell_gelb_1")
	var s2 := RulesFixture.card(g, 0, "hell_gelb_2")
	gb_stake(g, 0, "hell_gelb_1", "setzen")
	check(g.mau_open == -1 and g.mau_said[0], "nach dem Ruf kein offenes Fenster")
	gb_press(g, 0, 0, "0")
	gb_stake(g, 0, "hell_gelb_2", "letzte Karte setzen")
	check((g.hands[0] as Array).is_empty() and g.phase() == "gamble", "Hand leer, Glücksspiel läuft noch")
	var ev := gb_press(g, 0, 0, "0 mit leerer Hand")
	check(gb_names(ev) == ["gamble_roll", "stake_discard", "finish", "round_over"], "Fertig: gamble_roll, stake_discard, finish, round_over (%s)" % str(gb_names(ev)))
	var sd := gb_ev(ev, "stake_discard")
	check(int(sd.count) == 2 and sd.cards == [s1, s2] and sd.faces == ["hell_gelb_1", "hell_gelb_2"], "stake_discard (%s)" % str(sd))
	check(g.phase() == "round_over" and int(g.result.ranking[0]) == 0 and g.result.points[0] == 0, "Runde vorbei, Platz 0 gewinnt")
	check(int(g.result.gains[0]) == 1 + 7 + 1, "Punkte der anderen (9) (%s)" % str(g.result.gains))
	check(g.discard.slice(0, 2) == [s1, s2] and g.discard.slice(2, 2 + under.size()) == under and RulesFixture.top_key(g) == "hell_gluecksspiel",
		"Einsatz liegt unter der Ablage, oben das Glücksspiel")
	check(RulesFixture.card_check(g) == "" and g.gamble.is_empty(), "Kartenzahl nach dem Fertigwerden")


func _gb_finish_last() -> void:
	# bis zum Letzten mit 4 Spielern: fertig auf Platz 1, der Nächste macht weiter
	var g := gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1"], ["hell_blau_1", "hell_blau_7"], ["hell_gruen_1", "hell_gruen_2"],
		["hell_gelb_4", "hell_gelb_5"]], "top": "hell_rot_5", "mau_said": [0]}, {"round_end": "last"}, 4)
	gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel als vorletzte Karte", "gruen")
	gb_stake(g, 0, "hell_gelb_1", "letzte Karte setzen")
	var ev := gb_press(g, 0, 0, "0: fertig")
	check(gb_names(ev) == ["gamble_roll", "stake_discard", "finish", "turn"], "bis zum Letzten: fertig, Nächster (%s)" % str(gb_names(ev)))
	check(int(g.place[0]) == 1 and g.phase() == "turn" and g.current_seat() == 1 and g.color == "gruen", "Platz 1 vergeben, Platz 1 dran, Farbe Grün")
	# bis zum Letzten, nur noch einer übrig: Runde vorbei
	g = gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1"], ["hell_blau_1", "hell_blau_7"], []], "top": "hell_rot_5", "mau_said": [0],
		"finished": [2]}, {"round_end": "last"})
	gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel, danach nur noch einer", "blau")
	gb_stake(g, 0, "hell_gelb_1", "setzen")
	ev = gb_press(g, 0, 0, "0: fertig")
	check(g.phase() == "round_over" and g.result.ranking == [2, 0, 1], "Platzierung 2, 0, 1 (%s)" % str(g.result.get("ranking", [])))
	# Treffer bei last: weiter wie sonst
	g = gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1"], ["hell_blau_1", "hell_blau_7"], ["hell_gruen_1"]], "top": "hell_rot_5",
		"mau_said": [0]}, {"round_end": "last"})
	gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel bei last", "blau")
	gb_stake(g, 0, "hell_gelb_1", "setzen")
	ev = gb_press(g, 0, 10, "Treffer 10")
	check(int(gb_ev(ev, "draw").count) == 10 and (g.hands[0] as Array).size() == 11 and int(g.place[0]) == 0, "Treffer 10: 11 Karten, nicht fertig")


func _gb_last_card() -> void:
	var g := gb_make({"hands": [["hell_gluecksspiel"], ["hell_blau_1", "hell_blau_7"], ["hell_gruen_1"]], "top": "hell_rot_5", "mau_said": [0]})
	var ev := gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel als letzte Karte (first)", "rot")
	check(g.phase() == "round_over" and int(g.result.ranking[0]) == 0 and gb_ev(ev, "gamble_start").is_empty(), "letzte Karte: fertig, kein Glücksspiel")
	g = gb_make({"hands": [["hell_gluecksspiel"], ["hell_blau_1", "hell_blau_7"], ["hell_gruen_1", "hell_gruen_3"], ["hell_rot_1"]],
		"top": "hell_rot_5", "mau_said": [0]}, {"round_end": "last"}, 4)
	ev = gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel als letzte Karte (last)", "gruen")
	check(gb_names(ev) == ["play", "color", "finish", "turn"] and g.phase() == "turn" and g.current_seat() == 1 and g.gamble.is_empty(),
		"letzte Karte bei last: fertig, Nächster dran (%s)" % str(gb_names(ev)))


func _gb_mau() -> void:
	# (a) Glücksspiel als vorletzte Karte ohne Ruf: Fenster offen, Erwischen im Glücksspiel, danach geht es weiter.
	var g := gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1"], ["hell_blau_1", "hell_blau_2"], ["hell_gruen_1", "hell_gruen_2"]],
		"top": "hell_rot_5", "draw": ["hell_rot_1", "hell_rot_2"]})
	gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel ohne Ruf", "rot")
	check(g.mau_open == 0 and g.view_for(1).hints.catch == [0] and g.view_for(0).hints.can_mau, "Fenster offen: erwischbar, Ruf nachholbar")
	var ev := gb_act(g, 1, {"a": "catch", "target": 0}, "erwischt im Glücksspiel")
	check(gb_names(ev) == ["catch", "penalty", "draw"] and (g.hands[0] as Array).size() == 3 and g.phase() == "gamble"
		and str(g.gamble.need) == "stake" and g.current_seat() == 0, "Strafe 2 Karten, Glücksspiel geht weiter (%s)" % str(gb_names(ev)))
	check((g.view_for(0).hints.can_stake as Array).size() == 3, "jetzt 3 Karten setzbar")
	# (b) Setzen bis auf 1 Karte ohne Ruf: Fenster, anderer erwischt; Ruf mit 3 Karten nicht möglich.
	g = gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1", "hell_gelb_2", "hell_gelb_3"], ["hell_blau_1", "hell_blau_2"],
		["hell_gruen_1", "hell_gruen_2"]], "top": "hell_rot_5"})
	gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel mit 3 Restkarten", "rot")
	gb_reject(g, 0, {"a": "mau"}, "„Mau!“ geht erst, wenn du mit 2 Karten dran bist.", "Ruf mit 3 Karten")
	gb_stake(g, 0, "hell_gelb_1", "setzen (3 → 2)")
	gb_reject(g, 0, {"a": "mau"}, "„Mau!“ rufst du, bevor du deine vorletzte Karte auf den Einsatz legst.", "Ruf mit 2 Karten vor dem Drücken")
	gb_press(g, 0, 0, "0")
	check(g.view_for(0).hints.can_mau and str(g.view_for(0).hints.text).contains("Denk an „Mau!“"), "2 Karten vor dem Setzen: Ruf möglich, Erinnerung")
	gb_stake(g, 0, "hell_gelb_2", "setzen ohne Ruf (2 → 1)")
	check(g.mau_open == 0 and g.view_for(2).hints.catch == [0], "Fenster nach dem Setzen offen")
	gb_act(g, 2, {"a": "catch", "target": 0}, "Platz 2 erwischt")
	check((g.hands[0] as Array).size() == 3 and g.mau_open == -1 and str(g.gamble.need) == "press", "Strafe, weiter mit Drücken")
	# (c) Ruf vor dem Setzen: kein Fenster
	g = gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1", "hell_gelb_2"], ["hell_blau_1", "hell_blau_2"], ["hell_gruen_1"]], "top": "hell_rot_5"})
	gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel", "rot")
	gb_act(g, 0, {"a": "mau"}, "Ruf vor dem Setzen")
	gb_stake(g, 0, "hell_gelb_1", "setzen nach Ruf")
	check(g.mau_open == -1 and (g.view_for(1).hints.catch as Array).is_empty() and g.view_for(1).players[0].mau, "nach dem Ruf nicht erwischbar")
	# Treffer: Ruf verfällt, Fenster zu, niemand erwischbar
	gb_press(g, 0, 2, "Treffer 2")
	check(not g.mau_said[0] and g.mau_open == -1 and (g.view_for(1).hints.catch as Array).is_empty(), "nach dem Treffer: Ruf verfallen, nichts offen")
	# (d) auto: Fenster offen, Treffer → keine Strafe beim Nächsten
	g = gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1", "hell_gelb_2"], ["hell_blau_1", "hell_blau_2"], ["hell_gruen_1"]],
		"top": "hell_rot_5", "draw": ["hell_rot_1", "hell_rot_2", "hell_rot_3"]}, {"mau_call": "auto"})
	gb_play(g, 0, "hell_gluecksspiel", "auto: Glücksspiel", "blau")
	gb_stake(g, 0, "hell_gelb_1", "auto: setzen ohne Ruf")
	check(g.mau_open == 0 and (g.view_for(1).hints.catch as Array).is_empty(), "auto: Fenster offen, aber kein Erwischen")
	gb_press(g, 0, 1, "auto: Treffer 1")
	var ev2 := gb_act(g, 1, {"a": "play", "card": RulesFixture.card(g, 1, "hell_blau_1")}, "auto: Nächster legt")
	check(not gb_names(ev2).has("penalty"), "auto: keine Mau-Strafe nach dem Treffer (%s)" % str(gb_names(ev2)))
	# (e) Mit 0 Karten erwischt (Ruf bei 1 Karte vergessen): Strafkarten, kein Fertigwerden bei 0
	g = gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1"], ["hell_blau_1", "hell_blau_2"], ["hell_gruen_1"]], "top": "hell_rot_5",
		"draw": ["hell_rot_1", "hell_rot_2"]})
	gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel ohne Ruf", "blau")
	gb_stake(g, 0, "hell_gelb_1", "letzte Karte setzen")
	check((g.hands[0] as Array).is_empty() and g.view_for(1).hints.catch == [0], "mit 0 Karten noch erwischbar (Ruf bei 1 Karte vergessen)")
	gb_act(g, 1, {"a": "catch", "target": 0}, "erwischt mit leerer Hand")
	var ev3 := gb_press(g, 0, 0, "0 mit Strafkarten")
	check(not gb_names(ev3).has("finish") and str(g.gamble.need) == "stake" and (g.hands[0] as Array).size() == 2, "nicht fertig, weiter setzen")
	# (f) mau_call off: kein Fenster
	g = gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1"], ["hell_blau_1"], ["hell_gruen_1"]], "top": "hell_rot_5"}, {"mau_call": "off"})
	gb_play(g, 0, "hell_gluecksspiel", "off: Glücksspiel", "blau")
	check(g.mau_open == -1 and not g.view_for(0).hints.can_mau, "off: kein Mau-Fenster")


# Aufhören (AGENTS.md Nr. 26, 06.10.2026): nach mindestens einem Druck ohne Treffer, Einsatz unter die Ablage, Zug vorbei.
func _gb_stop() -> void:
	var g := gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1", "hell_gelb_2", "hell_gelb_3", "hell_blau_4"], ["hell_blau_1", "hell_blau_2"],
		["hell_gruen_1", "hell_gruen_2"]], "top": "hell_rot_5"})
	gb_reject(g, 0, {"a": "stop"}, "Gerade läuft kein Glücksspiel.", "stop vor dem Glücksspiel")
	check(not bool(g.view_for(0).hints.can_stop), "can_stop vor dem Glücksspiel aus")
	gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel", "gelb")
	check(not bool(g.view_for(0).hints.can_stop), "vor dem ersten Druck kein Aufhören")
	gb_reject(g, 0, {"a": "stop"}, "Aufhören geht erst nach dem ersten Druck.", "stop vor dem Setzen")
	var s1 := RulesFixture.card(g, 0, "hell_gelb_1")
	var s2 := RulesFixture.card(g, 0, "hell_gelb_2")
	gb_stake(g, 0, "hell_gelb_1", "setzen 1")
	check(not bool(g.view_for(0).hints.can_stop), "vor dem Drücken kein Aufhören")
	gb_reject(g, 0, {"a": "stop"}, "Erst den Glücksspielknopf drücken.", "stop vor dem Drücken")
	gb_press(g, 0, 0, "drücken 1: 0")
	var v0 := g.view_for(0)
	check(bool(v0.hints.can_stop) and (v0.hints.can_stake as Array).size() == 3, "nach der 0: aufhören oder setzen")
	check(v0.hints.text == "Noch eine Karte setzen – oder aufhören?", "Hinweistext Aufhören (%s)" % v0.hints.text)
	check(not bool(g.view_for(1).hints.can_stop) and not bool(g.view_for(-1).hints.get("can_stop", false)),
		"andere: kein Aufhören")
	gb_reject(g, 1, {"a": "stop"}, "Du bist nicht dran.", "stop eines anderen")
	gb_stake(g, 0, "hell_gelb_2", "setzen 2")
	gb_press(g, 0, 0, "drücken 2: 0")
	var under: Array = g.discard.duplicate()
	var ev := gb_act(g, 0, {"a": "stop"}, "aufhören")
	check(gb_names(ev) == ["stake_discard", "turn"], "Aufhören: stake_discard, turn (%s)" % str(gb_names(ev)))
	var sd := gb_ev(ev, "stake_discard")
	check(int(sd.seat) == 0 and int(sd.count) == 2 and sd.cards == [s1, s2] and sd.faces == ["hell_gelb_1", "hell_gelb_2"] and str(sd.reason) == "stop",
		"stake_discard mit reason stop (%s)" % str(sd))
	check(g.discard.slice(0, 2) == [s1, s2] and g.discard.slice(2) == under and RulesFixture.top_key(g) == "hell_gluecksspiel",
		"Einsatz unter der Ablage, oben das Glücksspiel")
	check(gb_keys(g, g.hands[0]) == ["hell_gelb_3", "hell_blau_4"] and int(g.place[0]) == 0, "Resthand bleibt, nicht fertig")
	check(g.phase() == "turn" and g.current_seat() == 1 and g.gamble.is_empty() and g.color == "gelb" and g.wished, "Zug vorbei, Wunschfarbe gilt")
	check(g.view_for(1).gamble == {} and not bool(g.view_for(1).hints.can_stop), "Sicht danach: kein Glücksspiel")
	for s in [1, 2, -1]:
		var f: Dictionary = g.events_for(s, ev)[0]
		check(not f.has("cards") and not f.has("faces") and int(f.count) == 2 and str(f.reason) == "stop", "Platz %d sieht nur Anzahl und Grund (%s)" % [s, str(f)])
	check(g.events_for(0, ev)[0].faces == ["hell_gelb_1", "hell_gelb_2"], "Besitzer sieht seine Einsatzgesichter")
	gb_reject(g, 1, {"a": "stop"}, "Gerade läuft kein Glücksspiel.", "stop nach dem Glücksspiel")
	check(RulesFixture.card_check(g) == "", "Kartenzahl nach dem Aufhören")
	# leere Hand: reason empty
	g = gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1"], ["hell_blau_1"], ["hell_gruen_1"]], "top": "hell_rot_5", "mau_said": [0]})
	gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel", "gelb")
	gb_stake(g, 0, "hell_gelb_1", "letzte Karte setzen")
	ev = gb_press(g, 0, 0, "0 mit leerer Hand")
	check(str(gb_ev(ev, "stake_discard").get("reason", "")) == "empty", "stake_discard bei leerer Hand: reason empty")
	# ohne Hausregel: kein stop, kein can_stop
	var off := RulesFixture.build(RuleConfig.new(), 3, {"hands": [["hell_gelb_1", "hell_gelb_2"], ["hell_blau_1"], ["hell_gruen_1"]], "top": "hell_rot_5"})
	var r := off.apply(0, {"a": "stop"})
	check(not bool(r.ok) and str(r.reason) == "Glücksspiel gibt es in diesen Regeln nicht.", "ohne Hausregel: stop abgelehnt (%s)" % r.reason)
	check(not off.view_for(0).hints.has("can_stop") and not off.view_for(0).hints.has("can_press"), "ohne Hausregel: kein can_stop")


# Aufhören mit 1 Restkarte: normale Mau-Regel (Fenster vom Setzen bleibt offen, Ruf davor schützt).
func _gb_stop_mau() -> void:
	var g := gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1", "hell_gelb_2", "hell_gelb_3"], ["hell_blau_1", "hell_blau_2"],
		["hell_gruen_1", "hell_gruen_2"]], "top": "hell_rot_5", "draw": ["hell_rot_1", "hell_rot_2", "hell_rot_3"]})
	gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel", "gelb")
	gb_stake(g, 0, "hell_gelb_1", "setzen (3 → 2)")
	gb_press(g, 0, 0, "0")
	gb_stake(g, 0, "hell_gelb_2", "setzen ohne Ruf (2 → 1)")
	gb_press(g, 0, 0, "0")
	gb_act(g, 0, {"a": "stop"}, "aufhören mit 1 Karte")
	check((g.hands[0] as Array).size() == 1 and g.current_seat() == 1 and g.view_for(2).hints.catch == [0], "nach dem Aufhören mit 1 Karte erwischbar")
	gb_act(g, 2, {"a": "catch", "target": 0}, "erwischt nach dem Aufhören")
	check((g.hands[0] as Array).size() == 3 and g.mau_open == -1, "Strafe nach dem Aufhören")
	# mit Ruf vor dem Setzen: nicht erwischbar, Ruf bleibt
	g = gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1", "hell_gelb_2", "hell_gelb_3"], ["hell_blau_1", "hell_blau_2"],
		["hell_gruen_1", "hell_gruen_2"]], "top": "hell_rot_5"})
	gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel", "gelb")
	gb_stake(g, 0, "hell_gelb_1", "setzen")
	gb_press(g, 0, 0, "0")
	gb_act(g, 0, {"a": "mau"}, "Ruf vor dem Setzen")
	gb_stake(g, 0, "hell_gelb_2", "setzen nach Ruf")
	gb_press(g, 0, 0, "0")
	gb_act(g, 0, {"a": "stop"}, "aufhören nach Ruf")
	check(g.mau_said[0] and g.mau_open == -1 and (g.view_for(1).hints.catch as Array).is_empty(), "nach dem Ruf nicht erwischbar, Ruf gilt weiter")


func _gb_pending() -> void:
	# Stapelstrafe offen: Glücksspiel passt nicht (wie jeder Joker)
	var g := gb_make({"hands": [["hell_rot_plus1", "hell_rot_1"], ["hell_gluecksspiel", "hell_blau_1"], ["hell_gruen_1"]], "top": "hell_rot_5"},
		{"stacking": "same"})
	gb_play(g, 0, "hell_rot_plus1", "+1 legen")
	check((g.view_for(1).hints.playable as Array).is_empty(), "unter offener Stapelstrafe kein Glücksspiel")
	var r := g.apply(1, {"a": "play", "card": RulesFixture.card(g, 1, "hell_gluecksspiel"), "color": "rot"})
	check(not bool(r.ok), "Glücksspiel auf offene Strafe abgelehnt (%s)" % r.reason)
	# Anzweifeln offen: auch kein Glücksspiel
	g = gb_make({"hands": [["hell_wuenscher_plus2", "hell_blau_1"], ["hell_gluecksspiel", "hell_blau_2"], ["hell_gruen_1"]], "top": "hell_rot_5"},
		{"wild_restriction": "bluff"})
	gb_play(g, 0, "hell_wuenscher_plus2", "+2 legen", "blau")
	check(g.phase() == "challenge" and (g.view_for(1).hints.playable as Array).is_empty(), "challenge: kein Glücksspiel")
	# Ein Glücksspiel-Joker auf der Hand zählt beim Wünscher +2 als „anderer Joker“ (wild_counts_for_bluff)
	g = gb_make({"hands": [["hell_wuenscher_plus2", "hell_gluecksspiel", "hell_blau_1"], ["hell_blau_2"], ["hell_gruen_1"]], "top": "hell_rot_5"},
		{"wild_restriction": "enforce"})
	var pk := gb_keys(g, g.view_for(0).hints.playable)
	check(pk == ["hell_gluecksspiel"], "enforce: Wünscher +2 nicht legbar, wenn ein Glücksspiel auf der Hand ist (%s)" % str(pk))
	# Als Startkarte bleibt es liegen (Joker)
	g = gb_make({"hands": [["hell_blau_1"], ["hell_blau_2"], ["hell_gruen_1"]], "top": "hell_rot_5", "draw": ["hell_gluecksspiel", "hell_blau_3"]})
	var old_top: int = g.discard.pop_back()
	g.draw_pile.push_front(old_top)
	var ev: Array = []
	g._reveal_start_card(ev)
	check(bool(ev[0].ignored) and str(ev[0].face) == "hell_gluecksspiel" and RulesFixture.top_key(g) == "hell_blau_3", "Glücksspiel als Startkarte bleibt liegen")


func _gb_flip() -> void:
	# Ein gesetzter Flip wirkt nicht; nach dem Fertigwerden liegt der Einsatz unter der Ablage und kommt mit dem nächsten Flip nach oben.
	var g := gb_make({"hands": [["hell_gluecksspiel", "hell_rot_flip/dunkel_pink_7"], ["hell_blau_flip", "hell_blau_1"], ["hell_gruen_1", "hell_gruen_2"],
		["hell_gelb_1", "hell_gelb_2"]], "top": "hell_rot_5", "mau_said": [0]}, {"round_end": "last"}, 4)
	gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel", "blau")
	var fid := RulesFixture.card(g, 0, "hell_rot_flip")
	gb_stake(g, 0, "hell_rot_flip", "Flip setzen")
	check(g.side_name() == "hell", "gesetzter Flip wirkt nicht")
	gb_press(g, 0, 0, "0: fertig")
	check(int(g.place[0]) == 1 and int(g.discard[0]) == fid, "Flip liegt ganz unten in der Ablage")
	gb_play(g, 1, "hell_blau_flip", "Platz 1 flippt")
	check(g.side_name() == "dunkel" and RulesFixture.top_key(g) == "dunkel_pink_7" and g.color == "pink", "nach dem Flip oben: die gesetzte Karte, dunkle Seite (%s)" % RulesFixture.top_key(g))
	# Glücksspiel oben nach einem Flip: Joker oben, der Flip-Spieler wählt die Farbe, es gibt kein Glücksspiel.
	g = gb_make({"hands": [["hell_rot_flip", "hell_rot_1"], ["hell_blau_1"], ["hell_gruen_1"]], "top": "hell_rot_5",
		"discard": ["hell_rot_3/dunkel_gluecksspiel"]})
	var ev := gb_play(g, 0, "hell_rot_flip", "Flip mit Glücksspiel unten")
	check(g.phase() == "color" and g.current_seat() == 0 and gb_ev(ev, "gamble_start").is_empty() and RulesFixture.top_key(g) == "dunkel_gluecksspiel",
		"Glücksspiel oben nach dem Flip: nur Farbwahl")
	gb_act(g, 0, {"a": "color", "color": "lila"}, "Farbe wählen")
	check(g.phase() == "turn" and g.current_seat() == 1, "danach der Nächste")
	# Glücksspiel auf der dunklen Seite
	g = gb_make({"side": "dunkel", "hands": [["dunkel_gluecksspiel", "dunkel_pink_1", "dunkel_pink_2"], ["dunkel_lila_1"], ["dunkel_orange_1"]],
		"top": "dunkel_lila_5"})
	gb_play(g, 0, "dunkel_gluecksspiel", "dunkles Glücksspiel", "tuerkis")
	check(g.phase() == "gamble" and g.color == "tuerkis", "dunkle Seite: Glücksspiel, Farbe Türkis")


func _gb_empty_piles() -> void:
	# Nachziehstapel leer, Ablage voll: Mischen ohne den Einsatz
	var g := gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1", "hell_gelb_2"], ["hell_blau_1"], ["hell_gruen_1"]], "top": "hell_rot_5",
		"rest": "discard"})
	check(g.draw_pile.is_empty(), "Nachziehstapel leer")
	gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel", "gelb")
	var sid := RulesFixture.card(g, 0, "hell_gelb_1")
	gb_stake(g, 0, "hell_gelb_1", "setzen")
	var ev := gb_press(g, 0, 4, "Treffer 4 mit leerem Stapel")
	check(gb_names(ev).has("shuffle") and int(gb_ev(ev, "draw").count) == 4 and not g.draw_pile.has(sid) and (g.hands[0] as Array).has(sid),
		"Mischen ohne Einsatzkarten, Einsatz zurück (%s)" % str(gb_names(ev)))
	check(RulesFixture.card_check(g) == "", "Kartenzahl nach dem Mischen")
	# Beide Stapel leer: nichts zu ziehen, Einsatz trotzdem zurück
	g = gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1", "hell_gelb_2"], ["hell_blau_1"], ["hell_gruen_1"]], "top": "hell_rot_5"})
	gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel", "gelb")
	var top: int = g.discard.pop_back()
	g.hands[2].append_array(g.draw_pile)
	g.hands[2].append_array(g.discard)
	g.draw_pile = []
	g.discard = [top]
	gb_stake(g, 0, "hell_gelb_1", "setzen")
	ev = gb_press(g, 0, 7, "Treffer 7 mit leeren Stapeln")
	check(gb_names(ev) == ["gamble_roll", "stake_back", "turn"] and (g.hands[0] as Array).size() == 2, "nichts zu ziehen, Einsatz zurück (%s)" % str(gb_names(ev)))
	check(RulesFixture.card_check(g) == "", "Kartenzahl bei leeren Stapeln")


func _gb_two_players() -> void:
	var g := gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1"], ["hell_blau_1", "hell_blau_2"]], "top": "hell_rot_5", "mau_said": [0]}, {}, 2)
	gb_play(g, 0, "hell_gluecksspiel", "zu zweit", "blau")
	gb_stake(g, 0, "hell_gelb_1", "setzen")
	gb_press(g, 0, 2, "Treffer")
	check(g.current_seat() == 1 and g.phase() == "turn", "zu zweit: danach der andere")
	g = gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1"], ["hell_blau_1", "hell_blau_2"]], "top": "hell_rot_5", "mau_said": [0]},
		{"round_end": "last"}, 2)
	gb_play(g, 0, "hell_gluecksspiel", "zu zweit bis zum Letzten", "blau")
	gb_stake(g, 0, "hell_gelb_1", "setzen")
	gb_press(g, 0, 0, "0: fertig")
	check(g.phase() == "round_over" and g.result.ranking == [0, 1], "zu zweit bei last: Runde vorbei")


func _gb_with_swap() -> void:
	# Mit Kartentausch: ein gesetzter Kartentausch wirkt nicht; 118 Karten.
	var g := gb_make({"hands": [["hell_gluecksspiel", "hell_rot_tausch", "hell_gelb_1"], ["hell_blau_1", "hell_blau_2"], ["hell_gruen_1"]],
		"top": "hell_rot_5", "mau_said": [0]}, {"swap_cards": "on"})
	check(g.n_cards == 118, "Kartentausch + Glücksspiel: 118 Karten")
	var others: Array = [g.hands[1].duplicate(), g.hands[2].duplicate()]
	gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel", "rot")
	gb_stake(g, 0, "hell_rot_tausch", "Kartentausch setzen")
	gb_press(g, 0, 0, "0")
	gb_stake(g, 0, "hell_gelb_1", "letzte Karte setzen")
	var ev := gb_press(g, 0, 0, "0: fertig")
	check(not gb_names(ev).has("swap_hands") and g.hands[1] == others[0] and g.hands[2] == others[1], "gesetzter Kartentausch wirkt nicht")
	check(g.phase() == "round_over", "fertig, Runde vorbei")
	# Kartentausch nach einem Glücksspiel: die zurückgenommene Hand wandert weiter
	g = gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1", "hell_gelb_2"], ["hell_gelb_tausch", "hell_blau_2"], ["hell_gruen_1"]],
		"top": "hell_rot_5", "mau_said": [0]}, {"swap_cards": "on"})
	gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel", "gelb")
	gb_stake(g, 0, "hell_gelb_1", "setzen")
	gb_press(g, 0, 1, "Treffer 1")
	var mine: Array = g.hands[0].duplicate()
	gb_play(g, 1, "hell_gelb_tausch", "Kartentausch danach")
	check(g.hands[1] == mine, "Hand nach dem Glücksspiel wandert beim Kartentausch weiter")


# --- Zufall ---

func _gb_random() -> void:
	var g := gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1"], ["hell_blau_1"], ["hell_gruen_1"]], "top": "hell_rot_5"})
	# Quote gleichverteilt 1–10
	var qs := {}
	for i in 5000:
		g._start_gamble(0, [])
		qs[int(g.gamble.q)] = int(qs.get(int(g.gamble.q), 0)) + 1
	var ok := qs.size() == 10
	for q in range(1, 11):
		if int(qs.get(q, 0)) < 400 or int(qs.get(q, 0)) > 600:
			ok = false
	check(ok, "Quote 1–10 gleichverteilt (5000 Lose: %s)" % str(qs))
	# Treffer mit Wahrscheinlichkeit 1/q, Werte 1–10 gleichverteilt
	var values := {}
	for q in [1, 2, 5, 10]:
		g.gamble = {"seat": 0, "q": q, "stake": [], "need": "press", "last": -1}
		var hits := 0
		var n := 4000
		for i in n:
			var v := g._roll()
			if v > 0:
				hits += 1
				values[v] = int(values.get(v, 0)) + 1
			elif v < 0 or v > 10:
				ok = false
		var rate := float(hits) / n
		check(absf(rate - 1.0 / q) < 0.03, "Quote 1:%d: Trefferrate %.3f" % [q, rate])
	var total := 0
	for v in values:
		total += int(values[v])
	ok = values.size() == 10
	for v in range(1, 11):
		if absf(float(values.get(v, 0)) / total - 0.1) > 0.02:
			ok = false
	check(ok, "Werte 1–10 gleichverteilt (%d Treffer: %s)" % [total, str(values)])
	g.gamble = {}
	# Gleicher Seed, gleiche Würfe (aus dem Spielzufall, nicht aus der globalen Quelle)
	var seqs: Array = []
	for k in 2:
		seed(17 + k)
		var h := gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1", "hell_gelb_2", "hell_gelb_3", "hell_gelb_4", "hell_gelb_5"], ["hell_blau_1"],
			["hell_gruen_1"]], "top": "hell_rot_5", "mau_said": [0]})
		h._rng.seed = 99
		h.apply(0, {"a": "play", "card": RulesFixture.card(h, 0, "hell_gluecksspiel"), "color": "rot"})
		var seq: Array = [int(h.gamble.q)]
		while h.phase() == "gamble":
			if str(h.gamble.need) == "stake":
				h.apply(0, {"a": "stake", "card": int(h.hands[0][0])})
			else:
				var r := h.apply(0, {"a": "press"})
				seq.append(int(gb_ev(r.events, "gamble_roll").value))
		seqs.append(seq)
	check(seqs[0] == seqs[1] and (seqs[0] as Array).size() >= 2, "gleicher Seed: gleiche Quote und Würfe (%s)" % str(seqs[0]))


# --- Lecktest an gebauten Lagen ---

func _gb_leak() -> void:
	for combo in [[true, true], [false, false], [true, false], [false, true]]:
		var opts := {"backs_visible": combo[0], "peek_own_backs": combo[1]}
		var g := gb_make({"hands": [["hell_gluecksspiel/dunkel_pink_1", "hell_gelb_1/dunkel_lila_9", "hell_gelb_2/dunkel_farbjagd", "hell_blau_4/dunkel_pink_2"],
			["hell_blau_1/dunkel_orange_3"], ["hell_blau_2/dunkel_tuerkis_4", "hell_blau_3"]], "top": "hell_rot_5"}, opts)
		var secrets := [str(g._seed)]
		var all_ev: Array = []
		all_ev.append_array(g.apply(0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_gluecksspiel"), "color": "rot"}).events)
		for k in ["hell_gelb_1", "hell_gelb_2"]:
			all_ev.append_array(g.apply(0, {"a": "stake", "card": RulesFixture.card(g, 0, k)}).events)
			for s in range(-1, 3):
				var e1 := _leak_view(g, s, secrets + [str(g._rng.state)])
				check(e1 == "", "Lecktest Sicht %s Platz %d: %s" % [str(combo), s, e1])
			check(_quota_check(g) == "", "Quote ändert keine Sicht")
			g.force_rolls([0])
			all_ev.append_array(g.apply(0, {"a": "press"}).events)
		g.force_rolls([6])
		all_ev.append_array(g.apply(0, {"a": "stake", "card": RulesFixture.card(g, 0, "hell_blau_4")}).events)
		all_ev.append_array(g.apply(0, {"a": "press"}).events)
		check(gb_names(all_ev).has("stake_back"), "Lecktest: Einsatz zurück")
		for s in range(-1, 3):
			var err := _leak_events(g, all_ev, s, secrets)
			check(err == "", "Lecktest Ereignisse %s Platz %d: %s" % [str(combo), s, err])
			var f := g.events_for(s, all_ev)
			var got := {}
			for e in f:
				if str(e.e) in ["stake", "stake_back"]:
					_collect_keys(e, got, false)
			var allowed := {}
			if s == 0:
				for k in ["hell_gelb_1", "hell_gelb_2", "hell_blau_4", "hell_gelb_1", "hell_gelb_2", "hell_blau_4"]:
					_add(allowed, k)
				if combo[1]:
					for k in ["dunkel_lila_9", "dunkel_farbjagd", "dunkel_pink_2", "dunkel_lila_9", "dunkel_farbjagd", "dunkel_pink_2"]:
						_add(allowed, k)
			elif combo[0]:
				for k in ["dunkel_lila_9", "dunkel_farbjagd", "dunkel_pink_2"]:
					_add(allowed, k)       # nur beim Zurücknehmen (wie beim Ziehen), nie beim Setzen
			check(got == allowed, "Lecktest %s Platz %d: Einsatzgesichter nur beim Besitzer (zu viel: %s)" % [str(combo), s, str(_diff(got, allowed))])
			check(not JSON.stringify(f).contains("\"q\"") and not JSON.stringify(g.view_for(s)).contains("\"q\""), "keine Quote in Sicht und Ereignissen")
		check(JSON.stringify(g.to_dict()).contains("\"gamble\""), "Spielstand enthält das Glücksspiel")
	# Mitten im Glücksspiel: Quote im Spielstand, nicht in der Sicht
	var h := gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1", "hell_gelb_2"], ["hell_blau_1"], ["hell_gruen_1"]], "top": "hell_rot_5"})
	h.apply(0, {"a": "play", "card": RulesFixture.card(h, 0, "hell_gluecksspiel"), "color": "rot"})
	check(h.to_dict().gamble.has("q") and not JSON.stringify(h.view_for(0)).contains("\"q\""), "Quote nur im Spielstand")


# --- Speichern ---

func _gb_round_trip() -> void:
	var g := gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1", "hell_gelb_2", "hell_gelb_3"], ["hell_blau_1", "hell_blau_2"],
		["hell_gruen_1", "hell_gruen_2"]], "top": "hell_rot_5"})
	gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel", "rot")
	gb_stake(g, 0, "hell_gelb_1", "setzen")
	var text := JSON.stringify(g.to_dict())
	var h := MauGame.from_dict(JSON.parse_string(text))
	check(JSON.stringify(h.to_dict()) == text and h.phase() == "gamble" and h.gamble == g.gamble, "to_dict/from_dict mitten im Glücksspiel")
	check(RulesFixture.card_check(h) == "" and RulesFixture.invariants(h) == "", "geladen: Karten und Zustand gültig")
	for s in range(-1, 3):
		check(JSON.stringify(h.view_for(s)) == JSON.stringify(g.view_for(s)), "Sicht %d nach dem Laden gleich" % s)
	var r1 := RandomNumberGenerator.new()
	r1.seed = 5
	var r2 := RandomNumberGenerator.new()
	r2.seed = 5
	_advance(g, r1, 300)
	_advance(h, r2, 300)
	check(JSON.stringify(g.to_dict()) == JSON.stringify(h.to_dict()), "nach dem Laden gleich weitergespielt (gleiche Würfe)")
	# Bot-Partien bis mitten in ein Glücksspiel, dann speichern und laden
	var found := 0
	for k in 60:
		var bg := MauGame.create(gb_cfg({"swap_cards": "on" if k % 2 == 0 else "off", "discard_color": "on" if k % 3 == 0 else "off"}),
			RulesFixture.players(2 + k % 6, "bot"), 700_000 + k)
		bg.start_round()
		var rng := RandomNumberGenerator.new()
		rng.seed = 33 + k
		for step in 1500:
			if not bg.state in MauGame.PLAY_PHASES or bg.state == "gamble":
				break
			var seat := bg.current_seat()
			bg.apply(seat, MauBot.choose(bg.view_for(seat), rng.randi(), 2))
		if bg.state != "gamble":
			continue
		found += 1
		var t := JSON.stringify(bg.to_dict())
		var bh := MauGame.from_dict(JSON.parse_string(t))
		check(JSON.stringify(bh.to_dict()) == t, "Bot-Partie %d: Rundreise im Glücksspiel" % k)
		var a1 := RandomNumberGenerator.new()
		a1.seed = 8 + k
		var a2 := RandomNumberGenerator.new()
		a2.seed = 8 + k
		_advance(bg, a1, 200)
		_advance(bh, a2, 200)
		check(JSON.stringify(bg.to_dict()) == JSON.stringify(bh.to_dict()), "Bot-Partie %d: gleich weitergespielt" % k)
		if found >= 5:
			break
	check(found >= 3, "Rundreise: Bot-Partien mitten im Glücksspiel gefunden (%d)" % found)
	# Alter Spielstand ohne die neuen Optionen lädt ohne Glücksspiel
	var old := MauGame.create(RuleConfig.new(), RulesFixture.players(3), 9)
	old.start_round()
	var d := old.to_dict()
	for k in ["gamble_cards", "discard_color", "swap_cards", "swap_direction"]:
		(d.config as Dictionary).erase(k)
	var back := MauGame.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(back.n_cards == 112 and back.config.gamble_cards == "off" and back.gamble.is_empty() and RulesFixture.card_check(back) == "",
		"alter Stand ohne die Optionen: 112 Karten, kein Glücksspiel")


# --- Bot ---

func _gb_bot(g: MauGame, seat: int, level := 2) -> Dictionary:
	return MauBot.choose(g.view_for(seat), 3, level)


func _gb_bot_decisions() -> void:
	# Kleine Hand: Glücksspiel, auch wenn anderes passt
	var g := gb_make({"hands": [["hell_gluecksspiel", "hell_rot_7", "hell_gelb_1"], ["hell_blau_1", "hell_blau_2"], ["hell_gruen_1", "hell_gruen_2"]],
		"top": "hell_rot_5"})
	var a := _gb_bot(g, 0)
	check(int(a.get("card", -1)) == RulesFixture.card(g, 0, "hell_gluecksspiel") and str(a.get("color", "")) != "", "kleine Hand: Glücksspiel (%s)" % str(a))
	# Große Hand und etwas anderes passt: nicht spielen
	g = gb_make({"hands": [["hell_gluecksspiel", "hell_rot_7", "hell_gelb_1", "hell_gelb_2", "hell_gelb_3", "hell_gelb_4", "hell_gelb_6", "hell_blau_1"],
		["hell_blau_2", "hell_blau_3"], ["hell_gruen_1", "hell_gruen_2"]], "top": "hell_rot_5"})
	a = _gb_bot(g, 0)
	check(int(a.get("card", -1)) == RulesFixture.card(g, 0, "hell_rot_7"), "große Hand: lieber Rot 7 (%s)" % str(a))
	# Sonst passt nichts: Glücksspiel statt Ziehen
	g = gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1", "hell_gelb_2", "hell_gelb_3", "hell_gelb_4", "hell_gelb_6", "hell_blau_1", "hell_blau_9"],
		["hell_blau_2", "hell_blau_3"], ["hell_gruen_1", "hell_gruen_2"]], "top": "hell_rot_5"})
	a = _gb_bot(g, 0)
	check(str(a.get("a", "")) == "play" and int(a.get("card", -1)) == RulesFixture.card(g, 0, "hell_gluecksspiel"), "nichts anderes passt: Glücksspiel (%s)" % str(a))
	# Gezogen: große Hand behalten, kleine spielen
	g = gb_make({"hands": [["hell_gelb_1", "hell_gelb_2", "hell_gelb_3", "hell_gelb_4", "hell_gelb_6", "hell_blau_1", "hell_blau_9"], ["hell_blau_2"],
		["hell_gruen_1"]], "top": "hell_rot_5", "draw": ["hell_gluecksspiel"]})
	g.apply(0, {"a": "draw"})
	check(g.phase() == "drawn" and str(_gb_bot(g, 0).get("a", "")) == "keep", "gezogenes Glücksspiel bei großer Hand behalten")
	g = gb_make({"hands": [["hell_gelb_1", "hell_gelb_2"], ["hell_blau_2"], ["hell_gruen_1"]], "top": "hell_rot_5", "draw": ["hell_gluecksspiel"]})
	g.apply(0, {"a": "draw"})
	check(str(_gb_bot(g, 0).get("a", "")) == "play", "gezogenes Glücksspiel bei kleiner Hand spielen")
	# Setzen: hohe Punkte zuerst, Joker zuletzt; drücken
	g = gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1", "hell_gelb_9", "hell_gelb_aussetzen", "hell_wuenscher"], ["hell_blau_2"], ["hell_gruen_1"]],
		"top": "hell_rot_5"})
	gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel", "gelb")
	a = _gb_bot(g, 0)
	check(str(a.get("a", "")) == "stake" and int(a.card) == RulesFixture.card(g, 0, "hell_gelb_aussetzen"), "Bot setzt zuerst die Karte mit den meisten Punkten (%s)" % str(a))
	gb_act(g, 0, a, "Bot setzt")
	check(str(_gb_bot(g, 0).get("a", "")) == "press", "Bot drückt")
	g.force_rolls([0])
	gb_act(g, 0, _gb_bot(g, 0), "Bot drückt: 0")
	a = _gb_bot(g, 0)
	check(int(a.get("card", -1)) == RulesFixture.card(g, 0, "hell_gelb_9"), "danach Gelb 9 (%s)" % str(a))
	gb_act(g, 0, a, "Gelb 9")
	g.force_rolls([0])
	gb_act(g, 0, {"a": "press"}, "0")
	# Mit 2 Karten (Gelb 1, Wünscher): erst „Mau!“, dann Gelb 1 (Joker zuletzt)
	a = _gb_bot(g, 0)
	check(str(a.get("a", "")) == "mau", "Bot ruft vor dem Setzen der vorletzten Karte „Mau!“ (%s)" % str(a))
	gb_act(g, 0, a, "Bot ruft")
	a = _gb_bot(g, 0)
	check(int(a.get("card", -1)) == RulesFixture.card(g, 0, "hell_gelb_1"), "Joker zuletzt: Gelb 1 (%s)" % str(a))
	# Schwer spielbar: einzelne Farbe vor häufiger Farbe bei gleichen Punkten
	g = gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_5", "hell_gelb_6", "hell_blau_5"], ["hell_blau_2"], ["hell_gruen_1"]], "top": "hell_rot_5"})
	gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel", "gelb")
	a = _gb_bot(g, 0)
	check(int(a.get("card", -1)) == RulesFixture.card(g, 0, "hell_blau_5"), "einzelne Farbe zuerst setzen (%s)" % str(a))
	# JSON-Sicht
	var jv: Dictionary = JSON.parse_string(JSON.stringify(g.view_for(0)))
	a = MauBot.choose(jv, 3, 2)
	check(str(a.get("a", "")) == "stake" and bool(g.apply(0, a).ok), "Bot auf JSON-Sicht (%s)" % str(a))


# Bot und Aufhören: nie mit 1 Karte, eher bei großem Einsatz, deterministisch; mit vielen Nullen hört er irgendwann auf.
func _gb_bot_stop() -> void:
	var hand := []
	for i in 3:
		hand.append({"id": i, "face": "hell_gelb_%d" % (i + 1)})
	var v := {"hand": hand, "gamble": {"seat": 0, "stake": 1, "need": "stake", "last": 0}}
	var p1 := MauBot.stop_chance(v, 2)
	v.gamble.stake = 5
	var p5 := MauBot.stop_chance(v, 2)
	check(p5 > p1 and p5 <= 0.9, "größerer Einsatz: eher aufhören (%.2f → %.2f)" % [p1, p5])
	v.hand = [hand[0]]
	check(MauBot.stop_chance(v, 2) == 0.0 and MauBot.stop_chance(v, 0) == 0.0, "mit 1 Karte nie aufhören")
	v.hand = [hand[0], hand[1]]
	v.gamble.stake = 2
	var p2 := MauBot.stop_chance(v, 2)
	v.hand = hand
	check(p2 < MauBot.stop_chance(v, 2), "mit 2 Karten eher weiter als mit 3")
	var stops := 0
	for k in 20:
		var g := gb_make({"hands": [["hell_gluecksspiel", "hell_gelb_1", "hell_gelb_2", "hell_gelb_3", "hell_gelb_4", "hell_gelb_6", "hell_blau_1",
			"hell_blau_9"], ["hell_blau_2"], ["hell_gruen_1"]], "top": "hell_rot_5", "mau_said": [0]})
		gb_play(g, 0, "hell_gluecksspiel", "Glücksspiel", "gelb")
		var seq: Array = []
		for step in 30:
			if g.phase() != "gamble":
				break
			var vw := g.view_for(0)
			var a := MauBot.choose(vw, 100 * k + step, 2)
			check(MauBot.choose(vw, 100 * k + step, 2) == a, "Bot-Entscheidung deterministisch")
			if str(a.get("a", "")) == "press":
				g.force_rolls([0])
			seq.append(str(a.get("a", "")))
			var r := g.apply(0, a)
			check(bool(r.ok), "Bot-Aktion %s angenommen (%s)" % [str(a), r.reason])
			if str(a.get("a", "")) == "stop":
				stops += 1
				check((g.hands[0] as Array).size() >= 2, "Bot hört nicht mit 1 Karte auf")
	check(stops >= 10, "Bot hört bei vielen Nullen meistens irgendwann auf (%d von 20)" % stops)


# Taktik mit Glücksspiel: Stufe 2 gegen zwei Bots der Stufe 0, zu dritt, Platz reihum.
func _gb_strength() -> void:
	var t0 := Time.get_ticks_msec()
	var games := 600
	var wins := 0
	var saved := gb_stats.duplicate()
	for i in games:
		var strong := i % 3
		var levels := [0, 0, 0]
		levels[strong] = 2
		var g := MauGame.create(gb_cfg(), RulesFixture.players(3, "bot"), 8_800 + i)
		g.start_round()
		var rng := RandomNumberGenerator.new()
		rng.seed = 71 + i
		var err := _gb_bot_round(g, rng, levels, 0.0)
		if err != "":
			check(false, "Stärketest mit Glücksspiel: " + err)
			return
		if int(g.result.ranking[0]) == strong:
			wins += 1
	gb_stats = saved
	print("Stärketest mit Glücksspiel: %d von %d Partien in %.1f s" % [wins, games, (Time.get_ticks_msec() - t0) / 1000.0])
	check(wins > games * 0.36, "Taktik-Bot (Stufe 2) gewinnt mit Glücksspiel deutlich öfter als ein Drittel (%d von %d)" % [wins, games])


# --- Bot-Dauerlauf mit allen Hausregeln ---

func _gb_bot_run() -> void:
	var games := GB_GAMES
	if OS.get_environment("RULES_GAMBLE_GAMES").is_valid_int():
		games = int(OS.get_environment("RULES_GAMBLE_GAMES"))
	var t0 := Time.get_ticks_msec()
	var errors := 0
	var all_games := games
	games = 0
	for i in all_games:
		if not Teil.mine(i):
			continue
		games += 1
		var err := _gb_bot_game(i)
		if err != "":
			errors += 1
			if errors <= 10:
				print("FAIL: Partie %d: %s" % [i, err])
	check(errors == 0, "Bot-Dauerlauf mit allen Hausregeln: %d von %d Partien fehlerhaft" % [errors, games])
	var st := gb_stats
	check(int(st.get("gluecksspiel", 0)) > games / 4 and int(st.get("treffer", 0)) > 0 and int(st.get("gluecksspiel_fertig", 0)) > 0,
		"Glücksspiel kommt vor, mit Treffern und Fertigwerden")
	check(int(st.get("aufgehoert", 0)) > 0, "Bots hören beim Glücksspiel auch auf (%d)" % int(st.get("aufgehoert", 0)))
	check(int(st.get("ablegen", 0)) > games / 4 and int(st.get("tausch", 0)) > games / 4, "Farbe ablegen und Kartentausch kommen vor")
	check(int(st.get("gluecksspiel_offen", 0)) == 0, "jedes Glücksspiel endet (%d offen)" % int(st.get("gluecksspiel_offen", 0)))
	check(int(st.get("mau_blind", 0)) == 0, "Bots rufen „Mau!“ nur, wenn danach 1 Karte bleibt (%d blind)" % int(st.get("mau_blind", 0)))
	print("Bot-Dauerlauf mit allen Hausregeln%s: %d Partien in %.1f s – %s" % [Teil.label(), games, (Time.get_ticks_msec() - t0) / 1000.0, str(st)])


func _gb_bot_game(i: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6_100_043 * i + 17
	var cfg := RulesFixture.random_config(rng, true, true, true)
	var n := rng.randi_range(2, 10)
	var levels: Array = []
	for s in n:
		levels.append(rng.randi_range(0, 2))
	var g := MauGame.create(cfg, RulesFixture.players(n, "bot"), rng.randi())
	g.start_round()
	var extra := 1 if rng.randf() < 0.2 else 0
	var forget := rng.randf() * 0.5
	for r in GB_ROUND_LIMIT:
		if g.n_cards != 124:
			return "Kartenzahl %d" % g.n_cards
		var dc := RulesFixture.deck_check(g)
		if dc != "":
			return "Runde %d: %s" % [g.round_no, dc]
		var err := _gb_bot_round(g, rng, levels, forget)
		if err != "":
			return "Runde %d (%d Spieler, %s): %s" % [g.round_no, n, JSON.stringify(cfg.to_dict()), err]
		gb_count("runden")
		if g.is_over():
			gb_count("partien_500")
			return ""
		if cfg.effective_scoring() != "points500":
			if extra <= 0:
				return ""
			extra -= 1
		var res := g.apply(0, {"a": "next_round"})
		if not bool(res.ok):
			return "next_round abgelehnt: " + str(res.reason)
	return "" if cfg.effective_scoring() == "points500" else "zu viele Runden"


func _gb_bot_round(g: MauGame, rng: RandomNumberGenerator, levels: Array, forget: float) -> String:
	var n := g.players.size()
	var steps := 0
	var called := -1               # Platz, der vor dem Legen bzw. Setzen „Mau!“ gerufen hat
	var gamble_len := 0
	while g.state in MauGame.PLAY_PHASES:
		steps += 1
		if steps > GB_STEP_LIMIT:
			return "Zugobergrenze %d erreicht" % GB_STEP_LIMIT
		if g.mau_open >= 0 and rng.randf() < 0.6:
			var o := rng.randi_range(0, n - 1)
			var ca := MauBot.choose(g.view_for(o), rng.randi(), int(levels[o]))
			if str(ca.get("a", "")) == "catch":
				var cr := g.apply(o, ca)
				if not bool(cr.ok):
					return "catch abgelehnt: " + str(cr.reason)
				gb_count("erwischt")
				if g.state == "gamble":
					gb_count("erwischt_im_gluecksspiel")
		var seat := g.current_seat()
		var view := g.view_for(seat)
		if bool(view.hints.can_mau) and rng.randf() < forget:
			view.hints.can_mau = false
		var act := MauBot.choose(view, rng.randi(), int(levels[seat]))
		if act.is_empty():
			return "Bot ohne Aktion in Phase %s (%s)" % [g.state, str(view.hints)]
		var kind := str(act.get("a", ""))
		var phase_before := g.state
		var hand_before := RulesFixture.hand_keys(g, seat)
		var res := g.apply(seat, act)
		if not bool(res.ok):
			return "Aktion %s abgelehnt: %s" % [JSON.stringify(act), res.reason]
		gb_count("aktionen")
		if kind == "mau":
			if (g.hands[seat] as Array).size() >= 2:
				called = seat
		elif called == seat and kind != "catch" and g.state != "discard_pick":  # Erwischen ändert die Hand nicht; nach der Auswahl zählen
			# Ein Kartentausch nach dem Ruf (Zufallsbot) löscht alle Rufe nach der Regel; das zählt wie im Kartentausch-Test nicht.
			var swapped := false
			for e in res.events:
				if str(e.e) == "swap_hands":
					swapped = true
			if swapped:
				gb_count("mau_dann_tausch")
			elif (g.hands[seat] as Array).size() > 1 and int(g.place[seat]) == 0:
				gb_count("mau_blind")
				if int(gb_stats.get("mau_blind", 0)) <= 6:
					print("blinder Ruf: Platz %d (Stufe %d), Phase %s, Hand vorher %s, danach %s → Hand %d, Ereignisse %s" % [seat, int(levels[seat]),
						phase_before, str(hand_before), JSON.stringify(act), (g.hands[seat] as Array).size(), str(gb_names(res.events))])
			called = -1
		if g.state == "gamble":
			gamble_len += 1
		for e in res.events:
			match str(e.e):
				"gamble_start":
					gb_count("gluecksspiel")
					gamble_len = 0
				"gamble_roll":
					gb_count("druecke")
					if int(e.value) > 0:
						gb_count("treffer")
				"stake_discard":
					gb_count("aufgehoert" if str(e.get("reason", "")) == "stop" else "gluecksspiel_fertig")
					gb_stats["laengstes_gluecksspiel"] = maxi(int(gb_stats.get("laengstes_gluecksspiel", 0)), gamble_len)
				"discard_color":
					gb_count("ablegen")
					gb_count("mitabgelegt", int(e.count))
					if int(e.count) != (e.faces as Array).size():
						return "discard_color: count passt nicht"
				"swap_hands":
					gb_count("tausch")
				"flip":
					gb_count("flip")
		var inv := RulesFixture.invariants(g)
		if inv != "":
			return "nach %s: %s" % [JSON.stringify(act), inv]
	if g.state == "gamble" or not g.gamble.is_empty():
		gb_count("gluecksspiel_offen")
	return ""
