extends "res://tests/test_rules_views.gd"
# Modul A: Hausregel „Farbe mit ablegen“ (discard_color = "on", 6 zusätzliche Karten: je Seite 4 farbige Ablegen-Karten und
# 2 Ablegen-Joker; Nutzerwunsch 05.10.2026, Festlegung des Koordinators).
# Gebaute Fälle: Kartendaten, Optionen und Texte, Rundenstart, Passen, Wirkung der farbigen Karte und des Jokers (Joker aller Art
# bleiben, Aktionskarten der Farbe wirken nicht, Reihenfolge unter der Ablegen-Karte), öffentliches Ereignis, Mau (1 Karte bleibt:
# Fenster; Ruf vorher erlaubt; Ruf verfällt, wenn mehr bleibt), Fertigwerden bei first/last, offene Stapelstrafe, dunkle Seite,
# Zusammenspiel mit Kartentausch und Glücksspiel, to_dict/from_dict und Bot-Entscheidungen. Danach die Zufallsprüfungen aus
# test_rules_views.gd mit „Farbe ablegen“ (discard_mode() = true) und ein Bot-Dauerlauf: Standard 1000 Partien mit zufälligen
# Regeln, Kartentausch und Glücksspiel abwechselnd dazu (RULES_DISCARD_GAMES, godot_run.ps1 -EnvPairs 'RULES_DISCARD_GAMES=200').

const DC_GAMES := 1000
const DC_STEP_LIMIT := 5000
const DC_ROUND_LIMIT := 40

var dc_stats := {}


func discard_mode() -> bool:
	return true


func _initialize() -> void:
	_dc_cards()
	_dc_config_and_texts()
	_dc_start()
	_dc_matching()
	_dc_colored()
	_dc_wild()
	_dc_mau()
	_dc_finish()
	_dc_pending()
	_dc_dark_side()
	_dc_with_others()
	_dc_round_trip()
	_dc_bot_decisions()
	var t0 := Time.get_ticks_msec()
	_json_views()
	_leak_runs()
	_hint_consistency()
	_round_trip()
	print("Zufallsprüfungen mit „Farbe ablegen“: %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	_dc_bot_run()
	print("Laufzeit seit Godot-Start: %.1f s" % (Time.get_ticks_msec() / 1000.0))
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)


# --- Hilfen ---

func dc_cfg(over := {}) -> RuleConfig:
	var d := {"discard_color": "on"}
	d.merge(over, true)
	return RuleConfig.from_dict(d)


func dc_make(spec: Dictionary, over := {}, n := 3) -> MauGame:
	var g := RulesFixture.build(dc_cfg(over), n, spec)
	var cc := RulesFixture.card_check(g)
	var dc := RulesFixture.deck_check(g)
	check(g.n_cards == g.config.card_count() and cc == "" and dc == "", "Aufbau mit %d Karten: %s %s" % [g.n_cards, cc, dc])
	return g


func dc_act(g: MauGame, seat: int, action: Dictionary, msg: String) -> Array:
	var r := g.apply(seat, action)
	check(bool(r.ok), "%s (abgelehnt: %s)" % [msg, r.reason])
	var inv := RulesFixture.invariants(g)
	check(inv == "", "%s: %s" % [msg, inv])
	return r.events


func dc_play(g: MauGame, seat: int, key: String, msg: String, col := "") -> Array:
	var id := RulesFixture.card(g, seat, key)
	check(id >= 0, "%s: Karte %s bei Platz %d" % [msg, key, seat])
	var a := {"a": "play", "card": id}
	if col != "":
		a["color"] = col
	return dc_act(g, seat, a, msg)


# Ablegen-Karte legen und, falls die Auswahl offen ist, mitablegen: pick = null alle Kandidaten, sonst die Schlüssel in pick;
# next_col = Spielfarbe (nur beim Ablegen-Joker). Liefert die Ereignisse beider Aktionen.
func dc_lay(g: MauGame, seat: int, key: String, msg: String, col := "", pick: Variant = null, next_col := "") -> Array:
	var ev := dc_play(g, seat, key, msg, col)
	if g.phase() != "discard_pick":
		return ev
	var ids: Array = (g.view_for(seat).hints.can_pick as Array).duplicate()
	if pick != null:
		ids = []
		for k in pick:
			ids.append(RulesFixture.card(g, seat, str(k)))
	var a := {"a": "discard_pick", "cards": ids}
	if next_col != "":
		a["color"] = next_col
	ev.append_array(dc_act(g, seat, a, msg + ": Auswahl"))
	return ev


func dc_ev(ev: Array, e_name: String) -> Dictionary:
	for e in ev:
		if str(e.e) == e_name:
			return e
	return {}


func dc_names(ev: Array) -> Array:
	var out: Array = []
	for e in ev:
		out.append(str(e.e))
	return out


func dc_playable(g: MauGame, seat: int) -> Array:
	var out: Array = []
	for id in g.view_for(seat).hints.playable:
		out.append(g._key[g.faces[g.side * g.n_cards + int(id)]])
	return CardDB.sort_keys(out)


func dc_count(key: String, n := 1) -> void:
	dc_stats[key] = int(dc_stats.get(key, 0)) + n


# --- Kartendaten ---

func _dc_cards() -> void:
	var dk := Array(CardDB.discard_keys())
	check(dk == ["hell_rot_ablegen", "hell_gelb_ablegen", "hell_gruen_ablegen", "hell_blau_ablegen", "hell_ablegen_joker",
		"dunkel_pink_ablegen", "dunkel_tuerkis_ablegen", "dunkel_orange_ablegen", "dunkel_lila_ablegen", "dunkel_ablegen_joker"],
		"discard_keys (%s)" % str(dk))
	for k in dk:
		var f := CardDB.parse_key(k)
		var wild := str(k).ends_with("_joker")
		check(CardDB.is_key(k) and CardDB.face_key(f) == k, "Rundreise Schlüssel " + k)
		check(CardDB.points_of_key(k) == (50 if wild else 30), "Punkte %s" % k)
		check(CardDB.is_discard(f) and CardDB.is_wild(f) == wild and not CardDB.is_draw_card(f) and not CardDB.is_gamble(f), "Art %s" % k)
	for s in 2:
		var deck := CardDB.deck(s, false, false, true)
		var colored := {}
		var jokers := 0
		for c in deck:
			if CardDB.kind_table()[c] == CardDB.DISCARD:
				colored[CardDB.color_table()[c]] = int(colored.get(CardDB.color_table()[c], 0)) + 1
			elif CardDB.kind_table()[c] == CardDB.DISCARD_WILD:
				jokers += 1
		check(deck.size() == 118 and colored.size() == 4 and colored.values() == [1, 1, 1, 1] and jokers == 2,
			"Seite %d: 118 Karten, je Farbe eine Ablegen-Karte, 2 Ablegen-Joker" % s)
		check(CardDB.point_sum(s, false, false, true) == (1500 if s == 0 else 1700), "Seite %d: Prüfsumme 1500/1700" % s)
	check(CardDB.sort_keys(["hell_ablegen_joker", "hell_rot_ablegen", "hell_rot_tausch", "hell_rot_flip", "hell_gelb_1", "dunkel_farbjagd",
		"dunkel_ablegen_joker", "dunkel_lila_ablegen", "dunkel_lila_9"]) == ["hell_rot_flip", "hell_rot_tausch", "hell_rot_ablegen", "hell_gelb_1",
		"hell_ablegen_joker", "dunkel_lila_9", "dunkel_lila_ablegen", "dunkel_farbjagd", "dunkel_ablegen_joker"], "Sortierung der Ablegen-Karten")
	check(RulesText.face_title("hell_rot_ablegen") == "Rot ablegen" and RulesText.face_title("dunkel_tuerkis_ablegen") == "Türkis ablegen",
		"Titel „Rot ablegen“")
	check(RulesText.face_title("hell_ablegen_joker") == "Ablegen-Joker" and RulesText.kind_name("ablegen") == "Farbe ablegen", "Namen")
	check(RulesText.match_phrase("hell_gelb_ablegen") == "eine Ablegen-Karte" and RulesText.match_phrase("dunkel_ablegen_joker") == "einen Ablegen-Joker",
		"match_phrase")


func _dc_config_and_texts() -> void:
	var on := dc_cfg()
	check(on.card_count() == 118 and on.preset_name() == "" and on.has_extra_cards(), "discard_color=on: 118 Karten, eigene Regeln")
	check(RuleConfig.from_dict(JSON.parse_string(JSON.stringify(on.to_dict()))).equals(on), "Rundreise über JSON")
	var d_on := "\n".join(on.describe())
	check(d_on.contains("Farbe ablegen") and d_on.contains("(118)") and d_on.contains("Joker bleiben"), "describe (%s)" % d_on)
	check(not "\n".join(RuleConfig.new().describe()).contains("ablegen"), "describe ohne Hausregel")
	var h := "\n".join(RulesText.card_help("hell_rot_ablegen", on))
	for part in ["welche deiner Karten in Rot du mit ablegst","Passt auf Rot und auf jede andere Ablegen-Karte", "Joker auf deiner Hand bleiben",
			"wirken nicht", "„Mau!“", "gewinnst du die Runde", "30 Punkte"]:
		check(h.contains(part), "Hilfe Rot ablegen enthält „%s“ (%s)" % [part, h])
	var hj := "\n".join(RulesText.card_help("dunkel_ablegen_joker", dc_cfg({"round_end": "last", "mau_call": "off"})))
	check(hj.contains("Joker: passt immer") and hj.contains("bist du fertig") and not hj.contains("Mau") and hj.contains("50 Punkte"),
		"Hilfe Ablegen-Joker bis zum Letzten, ohne Mau (%s)" % hj)
	check("\n".join(RulesText.card_help("hell_rot_ablegen", RuleConfig.new())).contains("gerade nicht im Spiel"), "Hilfe ohne Hausregel")
	var titles: Array = []
	var text := ""
	for p in RulesText.overview(on):
		titles.append(p.title)
		text += str(p.text) + "\n"
	check(titles.has("Farbe ablegen") and text.contains("118 Karten") and text.contains("vier Ablegen-Karten (eine je Farbe) und zwei Ablegen-Joker"),
		"Übersicht mit „Farbe ablegen“")
	var off_titles: Array = []
	for p in RulesText.overview(RuleConfig.new()):
		off_titles.append(p.title)
	check(not off_titles.has("Farbe ablegen"), "Übersicht ohne Hausregel unverändert")
	var ov500 := ""
	for p in RulesText.overview(dc_cfg({"scoring": "points500"})):
		ov500 += str(p.text)
	check(ov500.contains("Alle aussetzen und Farbe ablegen 30") and ov500.contains("Wünscher +2 und Ablegen-Joker 50"), "Übersicht 500 Punkte")


func _dc_start() -> void:
	var bad := ""
	for s in 40:
		var cfg := dc_cfg({"hand_size": 5 + s % 6})
		var n := 2 + s % 9
		var g := MauGame.create(cfg, RulesFixture.players(n, "bot"), 4_000_037 * s + 3)
		g.start_round()
		var faces := 0
		for code in g.faces:
			if CardDB.is_discard(CardDB.face(code)):
				faces += 1
		if g.n_cards != 118 or RulesFixture.card_check(g) != "" or RulesFixture.deck_check(g) != "":
			bad = "%d Karten %s %s" % [g.n_cards, RulesFixture.card_check(g), RulesFixture.deck_check(g)]
		elif faces != 12:
			bad = "%d Ablegen-Gesichter statt 12" % faces
		elif CardDB.kind_table()[g.faces[int(g.discard.back())]] != "zahl":
			bad = "Startkarte keine Zahl"
		elif g.view_for(0).has("gamble") or g.to_dict().has("gamble"):
			bad = "Glücksspiel-Felder ohne die Hausregel"
	check(bad == "", "Rundenstart mit „Farbe ablegen“ über 40 Seeds: " + bad)


# --- Passen ---

func _dc_matching() -> void:
	var g := dc_make({"hands": [["hell_rot_ablegen", "hell_gelb_ablegen", "hell_blau_7", "hell_ablegen_joker"], ["hell_blau_1"], ["hell_gruen_1"]],
		"top": "hell_rot_5"})
	check(dc_playable(g, 0) == ["hell_rot_ablegen", "hell_ablegen_joker"], "auf Rot 5: Rot ablegen und Ablegen-Joker (%s)" % str(dc_playable(g, 0)))
	check((g.view_for(0).hints.wild as Array) == [RulesFixture.card(g, 0, "hell_ablegen_joker")], "Ablegen-Joker braucht eine Farbe")
	g = dc_make({"hands": [["hell_rot_ablegen", "hell_gelb_7", "hell_blau_7", "hell_ablegen_joker"], ["hell_blau_1"], ["hell_gruen_1"]],
		"top": "hell_gelb_ablegen"})
	check(dc_playable(g, 0) == ["hell_rot_ablegen", "hell_gelb_7", "hell_ablegen_joker"], "auf Gelb ablegen: jede Ablegen-Karte und Gelb (%s)" % str(dc_playable(g, 0)))
	var r := g.apply(0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_blau_7")})
	check(not bool(r.ok) and str(r.reason) == "Passt nicht – lege Gelb oder eine Ablegen-Karte.", "Begründung (%s)" % r.reason)
	g = dc_make({"hands": [["hell_rot_ablegen", "hell_blau_ablegen", "hell_blau_3"], ["hell_blau_1"], ["hell_gruen_1"]], "top": "hell_ablegen_joker",
		"color": "blau"})
	check(dc_playable(g, 0) == ["hell_blau_3", "hell_blau_ablegen"], "auf dem Ablegen-Joker zählt nur die Wunschfarbe (%s)" % str(dc_playable(g, 0)))
	r = g.apply(0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_rot_ablegen")})
	check(not bool(r.ok) and str(r.reason) == "Passt nicht – lege Blau.", "Begründung auf dem Joker (%s)" % r.reason)
	# Startkarte: bleibt liegen
	g = dc_make({"hands": [["hell_blau_1"], ["hell_blau_2"], ["hell_gruen_1"]], "top": "hell_rot_5", "draw": ["hell_gelb_ablegen", "hell_ablegen_joker", "hell_blau_3"]})
	var old_top: int = g.discard.pop_back()
	g.draw_pile.push_front(old_top)
	var ev: Array = []
	g._reveal_start_card(ev)
	check(bool(ev[0].ignored) and bool(ev[1].ignored) and RulesFixture.top_key(g) == "hell_blau_3", "Ablegen-Karte und -Joker als Startkarte bleiben liegen")


# --- Wirkung ---

func _dc_colored() -> void:
	var g := dc_make({"hands": [["hell_rot_ablegen", "hell_rot_9", "hell_wuenscher", "hell_rot_plus1", "hell_rot_1", "hell_gelb_2", "hell_rot_aussetzen",
		"hell_rot_flip", "hell_wuenscher_plus2", "hell_rot_richtungswechsel"], ["hell_blau_1", "hell_blau_2"], ["hell_gruen_1", "hell_gruen_2"]],
		"top": "hell_rot_5"})
	var aid := RulesFixture.card(g, 0, "hell_rot_ablegen")
	var under: Array = g.discard.duplicate()
	var ev := dc_play(g, 0, "hell_rot_ablegen", "Rot ablegen")
	check(dc_names(ev) == ["play", "discard_pick"] and g.phase() == "discard_pick" and g.current_seat() == 0,
		"Auswahl offen: play, discard_pick (%s)" % str(dc_names(ev)))
	check(JSON.stringify(dc_ev(ev, "discard_pick")) == JSON.stringify({"e": "discard_pick", "seat": 0, "color": "rot"}), "Ereignis discard_pick")
	var reds: Array = []
	for k in ["hell_rot_9", "hell_rot_plus1", "hell_rot_1", "hell_rot_aussetzen", "hell_rot_flip", "hell_rot_richtungswechsel"]:
		reds.append(RulesFixture.card(g, 0, k))
	for s in range(-1, 3):
		var sv := g.view_for(s)
		check(JSON.stringify(sv.discard_pick) == JSON.stringify({"seat": 0, "color": "rot"}), "Sicht discard_pick für Platz %d" % s)
		var cp: Array = sv.hints.can_pick
		check(cp == (reds if s == 0 else []) and (sv.hints.playable as Array).is_empty() and not bool(sv.hints.pick_color),
			"can_pick nur für den Leger (Platz %d: %s)" % [s, str(cp)])
	check(str(g.view_for(0).hints.text).contains("Wähle, welche Karten in Rot") and str(g.view_for(1).hints.text).contains("legt Rot mit ab"),
		"Hinweistexte (%s / %s)" % [g.view_for(0).hints.text, g.view_for(1).hints.text])
	# Falsches wird abgelehnt
	for bad in [[0, {"a": "discard_pick", "cards": [RulesFixture.card(g, 0, "hell_gelb_2")]}], [0, {"a": "discard_pick", "cards": [reds[0], reds[0]]}],
			[0, {"a": "discard_pick", "cards": "alle"}], [0, {"a": "discard_pick", "cards": [RulesFixture.card(g, 0, "hell_wuenscher")]}],
			[1, {"a": "discard_pick", "cards": []}], [0, {"a": "draw"}], [0, {"a": "play", "card": reds[0]}]]:
		var rb := g.apply(int(bad[0]), bad[1])
		check(not bool(rb.ok) and str(rb.reason) != "", "abgelehnt: %s (%s)" % [JSON.stringify(bad[1]), rb.reason])
	# Rundreise mitten in der Auswahl
	var text := JSON.stringify(g.to_dict())
	check(JSON.stringify(MauGame.from_dict(JSON.parse_string(text)).to_dict()) == text, "Rundreise in der Phase discard_pick")
	var ev2 := dc_act(g, 0, {"a": "discard_pick", "cards": reds}, "alle Roten wählen")
	check(dc_names(ev2) == ["discard_color", "turn"], "Ereignisse discard_color, turn (%s)" % str(dc_names(ev2)))
	ev.append_array(ev2)
	var e := dc_ev(ev, "discard_color")
	var want := ["hell_rot_1", "hell_rot_9", "hell_rot_plus1", "hell_rot_aussetzen", "hell_rot_richtungswechsel", "hell_rot_flip"]
	check(int(e.seat) == 0 and str(e.color) == "rot" and int(e.count) == 6 and e.faces == want, "alle Roten mit, nach Rang sortiert (%s)" % str(e))
	check(RulesFixture.hand_keys(g, 0) == ["hell_wuenscher", "hell_gelb_2", "hell_wuenscher_plus2"], "Joker und Gelb bleiben (%s)" % str(RulesFixture.hand_keys(g, 0)))
	var expect: Array = under.duplicate()
	expect.append_array(e.cards)
	expect.append(aid)
	check(g.discard == expect and RulesFixture.top_key(g) == "hell_rot_ablegen", "mitabgelegte Karten liegen unter der Ablegen-Karte")
	check(g.color == "rot" and not g.wished and g.side_name() == "hell" and g.dir == 1 and g.pending.is_empty() and g.current_seat() == 1,
		"Aktionskarten wirken nicht: kein Flip, kein Richtungswechsel, keine Strafe, kein Aussetzen")
	check(g.view_for(1).discard_count == under.size() + 7, "Ablage um 7 Karten größer")
	for s in range(-1, 3):
		check(JSON.stringify(g.events_for(s, ev)) == JSON.stringify(ev), "Ereignis für Platz %d öffentlich" % s)
	# Ohne weitere Karten der Farbe: Ereignis mit 0 Karten
	g = dc_make({"hands": [["hell_gelb_ablegen", "hell_blau_1", "hell_wuenscher"], ["hell_blau_2"], ["hell_gruen_1"]], "top": "hell_gelb_5"})
	ev = dc_play(g, 0, "hell_gelb_ablegen", "Gelb ablegen ohne weitere Gelbe")
	check(int(dc_ev(ev, "discard_color").count) == 0 and (dc_ev(ev, "discard_color").faces as Array).is_empty() and (g.hands[0] as Array).size() == 2,
		"nichts weiter abzulegen: count 0")
	check(not dc_names(ev).has("discard_pick") and g.current_seat() == 1, "ohne Kandidaten keine Auswahl")
	# Nur einige mitablegen (auch Zahlen und Aktionskarten gemischt), Reihenfolge nach Rang; keine mitablegen
	g = dc_make({"hands": [["hell_blau_ablegen", "hell_blau_9", "hell_blau_2", "hell_blau_plus1", "hell_gelb_1"], ["hell_blau_1"], ["hell_gruen_1"]],
		"top": "hell_blau_5"})
	ev = dc_lay(g, 0, "hell_blau_ablegen", "Blau ablegen, Auswahl 9 und +1", "", ["hell_blau_plus1", "hell_blau_9"])
	check(dc_ev(ev, "discard_color").faces == ["hell_blau_9", "hell_blau_plus1"] and int(dc_ev(ev, "discard_color").count) == 2
		and RulesFixture.hand_keys(g, 0) == ["hell_blau_2", "hell_gelb_1"] and g.pending.is_empty() and g.current_seat() == 1,
		"nur die gewählten, +1 wirkt nicht (%s)" % str(dc_ev(ev, "discard_color")))
	g = dc_make({"hands": [["hell_blau_ablegen", "hell_blau_9", "hell_gelb_1"], ["hell_blau_1"], ["hell_gruen_1"]], "top": "hell_blau_5"})
	ev = dc_lay(g, 0, "hell_blau_ablegen", "Blau ablegen, nichts mit", "", [])
	check(int(dc_ev(ev, "discard_color").count) == 0 and RulesFixture.hand_keys(g, 0) == ["hell_blau_9", "hell_gelb_1"], "leere Auswahl erlaubt")


func _dc_wild() -> void:
	var g := dc_make({"hands": [["hell_ablegen_joker", "hell_gelb_1", "hell_gelb_richtungswechsel", "hell_blau_3", "hell_ablegen_joker", "hell_gelb_7",
		"hell_wuenscher"], ["hell_blau_1", "hell_blau_2"], ["hell_gruen_1", "hell_gruen_2"]], "top": "hell_rot_5"})
	var jid := RulesFixture.card(g, 0, "hell_ablegen_joker")
	var r := g.apply(0, {"a": "play", "card": jid})
	check(not bool(r.ok) and str(r.reason).contains("Wähle eine Farbe"), "Ablegen-Joker ohne Farbe abgelehnt")
	r = g.apply(0, {"a": "play", "card": jid, "color": "lila"})
	check(not bool(r.ok), "Farbe der anderen Seite abgelehnt")
	var old_color := g.color
	var ev := dc_act(g, 0, {"a": "play", "card": jid, "color": "gelb"}, "Ablegen-Joker mit Ablegefarbe Gelb")
	check(dc_names(ev) == ["play", "discard_pick"] and g.color == old_color and g.phase() == "discard_pick",
		"Ereignisse play, discard_pick; Spielfarbe noch offen (%s)" % str(dc_names(ev)))
	var v := g.view_for(0)
	check(bool(v.hints.pick_color) and (v.hints.can_pick as Array).size() == 3 and str(v.discard_pick.color) == "gelb", "Joker: Auswahl mit Farbwahl")
	var gelb: Array = (v.hints.can_pick as Array).duplicate()
	for bad in [{"a": "discard_pick", "cards": gelb}, {"a": "discard_pick", "cards": gelb, "color": "lila"}, {"a": "discard_pick", "cards": gelb, "color": 3}]:
		var rb := g.apply(0, bad)
		check(not bool(rb.ok), "Joker-Auswahl ohne gültige Spielfarbe abgelehnt (%s)" % rb.reason)
	ev = dc_act(g, 0, {"a": "discard_pick", "cards": gelb, "color": "blau"}, "alle Gelben, weiter mit Blau")
	check(dc_names(ev) == ["discard_color", "color", "turn"], "Ereignisse discard_color, color, turn (%s)" % str(dc_names(ev)))
	var e := dc_ev(ev, "discard_color")
	check(str(e.color) == "gelb" and e.faces == ["hell_gelb_1", "hell_gelb_7", "hell_gelb_richtungswechsel"], "gewählte Farbe mit ab (%s)" % str(e))
	check(RulesFixture.hand_keys(g, 0) == ["hell_blau_3", "hell_ablegen_joker", "hell_wuenscher"], "andere Joker bleiben (%s)" % str(RulesFixture.hand_keys(g, 0)))
	check(g.color == "blau" and g.wished and RulesFixture.top_key(g) == "hell_ablegen_joker" and g.dir == 1 and g.current_seat() == 1,
		"Spielfarbe Blau getrennt von der Ablegefarbe, Richtungswechsel ohne Wirkung")
	# Joker ohne Karten der Ablegefarbe: Auswahl trotzdem (nur die Spielfarbe fehlt)
	g = dc_make({"hands": [["hell_ablegen_joker", "hell_blau_3", "hell_wuenscher"], ["hell_blau_1"], ["hell_gruen_1"]], "top": "hell_rot_5"})
	dc_play(g, 0, "hell_ablegen_joker", "Joker mit Rot ohne Rote", "rot")
	check(g.phase() == "discard_pick" and (g.view_for(0).hints.can_pick as Array).is_empty() and bool(g.view_for(0).hints.pick_color)
		and g.view_for(0).hints.text == "Wähle die Farbe, mit der es weitergeht.", "Joker ohne Kandidaten: nur Farbwahl")
	ev = dc_act(g, 0, {"a": "discard_pick", "cards": [], "color": "gruen"}, "weiter mit Grün")
	check(dc_names(ev) == ["discard_color", "color", "turn"] and g.color == "gruen" and int(dc_ev(ev, "discard_color").count) == 0, "Grün gilt")


func _dc_mau() -> void:
	# (a) Es kann 1 Karte bleiben: Ruf vorher erlaubt (mit 4 Karten), sonst Fenster nach der Auswahl und Erwischen
	var spec := {"hands": [["hell_rot_ablegen", "hell_rot_3", "hell_rot_4", "hell_blau_1"], ["hell_blau_2", "hell_blau_3"], ["hell_gruen_1"]],
		"top": "hell_rot_5", "draw": ["hell_gelb_1", "hell_gelb_2"]}
	var g := dc_make(spec)
	var v := g.view_for(0)
	check(v.hints.can_mau and str(v.hints.text).contains("Denk an „Mau!“"), "4 Karten, Ablegen lässt 1: Mau möglich, Erinnerung (%s)" % v.hints.text)
	dc_play(g, 0, "hell_rot_ablegen", "ablegen ohne Ruf")
	check(g.phase() == "discard_pick" and g.view_for(0).hints.can_mau and g.mau_open == -1 and (g.view_for(1).hints.catch as Array).is_empty(),
		"in der Auswahl: Ruf möglich, noch nichts zu erwischen")
	dc_act(g, 0, {"a": "discard_pick", "cards": g.view_for(0).hints.can_pick}, "beide Roten mit")
	check((g.hands[0] as Array).size() == 1 and g.mau_open == 0 and g.view_for(1).hints.catch == [0] and g.view_for(0).hints.can_mau,
		"1 Karte: Fenster offen, erwischbar, Ruf nachholbar")
	var ev := dc_act(g, 1, {"a": "catch", "target": 0}, "erwischt")
	check(dc_names(ev) == ["catch", "penalty", "draw"] and (g.hands[0] as Array).size() == 3, "Strafe 2 Karten")
	# (a2) Ruf in der Auswahl, dann nur eine Rote mit (bleiben 2): Ruf verfällt
	g = dc_make(spec)
	dc_play(g, 0, "hell_rot_ablegen", "ablegen")
	dc_act(g, 0, {"a": "mau"}, "Ruf in der Auswahl")
	dc_act(g, 0, {"a": "discard_pick", "cards": [RulesFixture.card(g, 0, "hell_rot_3")]}, "nur Rot 3 mit")
	check(not g.mau_said[0] and (g.hands[0] as Array).size() == 2 and g.mau_open == -1, "2 bleiben: Ruf verfallen")
	# (b) Ruf vorher, dann ablegen: kein Fenster
	g = dc_make(spec)
	dc_act(g, 0, {"a": "mau"}, "Ruf vor dem Ablegen")
	dc_lay(g, 0, "hell_rot_ablegen", "ablegen nach Ruf")
	check(g.mau_open == -1 and g.view_for(1).players[0].mau and (g.view_for(1).hints.catch as Array).is_empty(), "nach dem Ruf nicht erwischbar")
	# (c) Ruf, dann eine andere Karte (bleiben 3): Ruf verfällt
	g = dc_make(spec)
	dc_act(g, 0, {"a": "mau"}, "Ruf")
	dc_play(g, 0, "hell_rot_3", "dann Rot 3")
	check(not g.mau_said[0] and not g.view_for(1).players[0].mau, "Ruf verfällt, wenn mehr als 1 Karte bleibt")
	# (d) Ablegen-Joker: Ruf möglich, wenn eine Farbe 1 Karte übrig lassen kann; mit einer anderen Farbe verfällt er
	g = dc_make({"hands": [["hell_ablegen_joker", "hell_gelb_1", "hell_gelb_2", "hell_blau_1"], ["hell_blau_2"], ["hell_gruen_1"]], "top": "hell_rot_5"})
	check(g.view_for(0).hints.can_mau, "Ablegen-Joker: mit Gelb bliebe 1 Karte → Mau möglich")
	dc_act(g, 0, {"a": "mau"}, "Ruf vor dem Joker")
	dc_lay(g, 0, "hell_ablegen_joker", "Joker mit Blau (bleiben 2)", "blau", null, "gelb")
	check(not g.mau_said[0] and (g.hands[0] as Array).size() == 2, "mit Blau bleiben 2: Ruf verfallen")
	# (e) Keine Karte lässt 1 übrig: kein Ruf, auch nicht in der Auswahl
	g = dc_make({"hands": [["hell_rot_ablegen", "hell_rot_3", "hell_blau_1", "hell_blau_2"], ["hell_blau_3"], ["hell_gruen_1"]], "top": "hell_rot_5"})
	check(not g.view_for(0).hints.can_mau and not str(g.view_for(0).hints.text).contains("Mau"), "nichts lässt 1 Karte: kein Mau")
	var r := g.apply(0, {"a": "mau"})
	check(not bool(r.ok) and str(r.reason) == "„Mau!“ geht erst, wenn du mit 2 Karten dran bist.", "Ruf abgelehnt (%s)" % r.reason)
	dc_play(g, 0, "hell_rot_ablegen", "ablegen (bleiben mindestens 2)")
	r = g.apply(0, {"a": "mau"})
	check(not g.view_for(0).hints.can_mau and not bool(r.ok) and str(r.reason).contains("genau 1 Karte bleiben"), "in der Auswahl abgelehnt (%s)" % r.reason)
	# (f) 2 Karten, nur die Ablegen-Karte passt: Wer Rot 3 behält, hat 1 Karte – Ruf erlaubt; alles mit: fertig ohne Strafe
	g = dc_make({"hands": [["hell_rot_ablegen", "hell_rot_3"], ["hell_blau_3", "hell_blau_4"], ["hell_gruen_1"]], "top": "hell_blau_ablegen"})
	check(dc_playable(g, 0) == ["hell_rot_ablegen"] and g.view_for(0).hints.can_mau, "2 Karten, Rot 3 könnte bleiben: Mau möglich")
	ev = dc_lay(g, 0, "hell_rot_ablegen", "alles auf einmal ablegen")
	check(g.phase() == "round_over" and int(g.result.ranking[0]) == 0 and not dc_names(ev).has("penalty"), "fertig ohne „Mau!“ und ohne Strafe")
	# (g) auto: Fenster nach der Auswahl, Strafe bei der ersten Handlung des Nächsten
	g = dc_make(spec, {"mau_call": "auto"})
	dc_lay(g, 0, "hell_rot_ablegen", "auto: ablegen ohne Ruf")
	ev = dc_act(g, 1, {"a": "draw"}, "auto: Nächster zieht")
	check(dc_names(ev).slice(0, 2) == ["penalty", "draw"] and (g.hands[0] as Array).size() == 3, "auto: Strafe beim Fensterende (%s)" % str(dc_names(ev)))
	# (h) off: kein Fenster
	g = dc_make(spec, {"mau_call": "off"})
	dc_lay(g, 0, "hell_rot_ablegen", "off: ablegen")
	check(g.mau_open == -1 and not g.view_for(0).hints.can_mau, "off: kein Fenster")


func _dc_finish() -> void:
	var g := dc_make({"hands": [["hell_rot_ablegen", "hell_rot_1", "hell_rot_2", "hell_rot_plus1"], ["hell_blau_1", "hell_blau_ablegen"],
		["hell_ablegen_joker"]], "top": "hell_rot_5"}, {"scoring": "points500"})
	var ev := dc_lay(g, 0, "hell_rot_ablegen", "alles ablegen (first)")
	check(dc_names(ev) == ["play", "discard_pick", "discard_color", "finish", "round_over"], "fertig: play, discard_pick, discard_color, finish, round_over (%s)" % str(dc_names(ev)))
	check(g.phase() == "round_over" and int(g.result.ranking[0]) == 0 and g.result.points == [0, 31, 50], "Punkte: Ablegen 30, Joker 50 (%s)" % str(g.result.get("points", [])))
	check(g.pending.is_empty(), "mitabgelegte +1 wirkt auch als letzte Karte nicht")
	g = dc_make({"hands": [["hell_rot_ablegen", "hell_rot_1"], ["hell_blau_1", "hell_blau_2"], ["hell_gruen_1", "hell_gruen_2"], ["hell_gelb_1"]],
		"top": "hell_rot_5"}, {"round_end": "last"}, 4)
	ev = dc_lay(g, 0, "hell_rot_ablegen", "alles ablegen (last)")
	check(dc_names(ev) == ["play", "discard_pick", "discard_color", "finish", "turn"] and int(g.place[0]) == 1 and g.current_seat() == 1, "bis zum Letzten: fertig, Nächster dran")
	g = dc_make({"hands": [["hell_rot_ablegen", "hell_rot_1"], ["hell_blau_1", "hell_blau_2"], []], "top": "hell_rot_5", "finished": [2]},
		{"round_end": "last"})
	dc_lay(g, 0, "hell_rot_ablegen", "alles ablegen, danach nur noch einer")
	check(g.phase() == "round_over" and g.result.get("ranking", []) == [2, 0, 1], "Platzierung 2, 0, 1 (%s)" % str(g.result.get("ranking", [])))
	# Ablegen-Joker als letzte Karte: Auswahl ohne Kandidaten, Spielfarbe gilt für die Übrigen (bis zum Letzten)
	g = dc_make({"hands": [["hell_ablegen_joker"], ["hell_blau_1", "hell_blau_2"], ["hell_gruen_1", "hell_gruen_2"]], "top": "hell_rot_5"},
		{"round_end": "last"})
	ev = dc_lay(g, 0, "hell_ablegen_joker", "Joker als letzte Karte", "rot", null, "gruen")
	check(dc_names(ev) == ["play", "discard_pick", "discard_color", "color", "finish", "turn"] and g.color == "gruen" and int(g.place[0]) == 1,
		"Joker zuletzt: fertig, Grün gilt (%s)" % str(dc_names(ev)))


func _dc_pending() -> void:
	var g := dc_make({"hands": [["hell_rot_plus1", "hell_rot_1"], ["hell_rot_ablegen", "hell_ablegen_joker", "hell_blau_1"], ["hell_gruen_1"]],
		"top": "hell_rot_5"}, {"stacking": "same"})
	dc_play(g, 0, "hell_rot_plus1", "+1 legen")
	check((g.view_for(1).hints.playable as Array).is_empty(), "unter offener Strafe keine Ablegen-Karte")
	g = dc_make({"hands": [["hell_wuenscher_plus2", "hell_ablegen_joker", "hell_blau_1"], ["hell_blau_2"], ["hell_gruen_1"]], "top": "hell_rot_5"},
		{"wild_restriction": "enforce"})
	check(dc_playable(g, 0) == ["hell_ablegen_joker"], "enforce: Ablegen-Joker zählt als anderer Joker (%s)" % str(dc_playable(g, 0)))
	g = dc_make({"hands": [["hell_wuenscher_plus2", "hell_blau_1"], ["hell_blau_ablegen", "hell_ablegen_joker"], ["hell_gruen_1"]], "top": "hell_rot_5"},
		{"wild_restriction": "bluff"})
	dc_play(g, 0, "hell_wuenscher_plus2", "+2", "blau")
	check(g.phase() == "challenge" and (g.view_for(1).hints.playable as Array).is_empty(), "beim Anzweifeln keine Ablegen-Karte")


func _dc_dark_side() -> void:
	var g := dc_make({"side": "dunkel", "hands": [["dunkel_lila_ablegen", "dunkel_lila_1", "dunkel_lila_plus5", "dunkel_farbjagd", "dunkel_pink_2",
		"dunkel_lila_alle_aussetzen"], ["dunkel_pink_3"], ["dunkel_orange_1"]], "top": "dunkel_lila_5"})
	var ev := dc_lay(g, 0, "dunkel_lila_ablegen", "Lila ablegen")
	check(dc_ev(ev, "discard_color").faces == ["dunkel_lila_1", "dunkel_lila_plus5", "dunkel_lila_alle_aussetzen"], "dunkle Seite: Lila mit ab")
	check(RulesFixture.hand_keys(g, 0) == ["dunkel_farbjagd", "dunkel_pink_2"] and g.pending.is_empty() and g.current_seat() == 1,
		"Farbjagd bleibt, +5 und Alle aussetzen wirken nicht")
	# Danach ein Flip: Die mitabgelegten Karten wenden sich mit der Ablage.
	g = dc_make({"hands": [["hell_rot_ablegen", "hell_rot_1/dunkel_pink_9"], ["hell_rot_flip", "hell_blau_1"], ["hell_gruen_1"]], "top": "hell_rot_5/dunkel_lila_6"},
		{"round_end": "last"})
	dc_lay(g, 0, "hell_rot_ablegen", "ablegen, dann fertig")
	dc_play(g, 1, "hell_rot_flip", "Flip danach")
	check(g.side_name() == "dunkel" and RulesFixture.top_key(g) == "dunkel_lila_6", "nach dem Flip oben die unterste Ablagekarte (%s)" % RulesFixture.top_key(g))


func _dc_with_others() -> void:
	var g := dc_make({"hands": [["hell_rot_ablegen", "hell_rot_tausch", "hell_gluecksspiel", "hell_rot_2", "hell_gelb_1"], ["hell_blau_1"], ["hell_gruen_1"]],
		"top": "hell_rot_5"}, {"swap_cards": "on", "gamble_cards": "on"})
	check(g.n_cards == 124, "alle Hausregeln: 124 Karten")
	var others: Array = [g.hands[1].duplicate(), g.hands[2].duplicate()]
	var ev := dc_lay(g, 0, "hell_rot_ablegen", "Rot ablegen mit Kartentausch und Glücksspiel auf der Hand")
	check(dc_ev(ev, "discard_color").faces == ["hell_rot_2", "hell_rot_tausch"] and not dc_names(ev).has("swap_hands") and not dc_names(ev).has("gamble_start"),
		"Kartentausch geht ohne Wirkung mit, kein Glücksspiel")
	check(RulesFixture.hand_keys(g, 0) == ["hell_gluecksspiel", "hell_gelb_1"] and g.hands[1] == others[0] and g.hands[2] == others[1],
		"Glücksspiel-Joker bleibt, andere Hände unverändert")
	# Eine gesetzte Ablegen-Karte (Glücksspiel) wirkt nicht
	g = dc_make({"hands": [["hell_gluecksspiel", "hell_rot_ablegen", "hell_rot_3", "hell_rot_4"], ["hell_blau_1"], ["hell_gruen_1"]], "top": "hell_rot_5"},
		{"gamble_cards": "on"})
	dc_play(g, 0, "hell_gluecksspiel", "Glücksspiel", "blau")
	dc_act(g, 0, {"a": "stake", "card": RulesFixture.card(g, 0, "hell_rot_ablegen")}, "Ablegen-Karte setzen")
	check(RulesFixture.hand_keys(g, 0) == ["hell_rot_3", "hell_rot_4"], "gesetzte Ablegen-Karte nimmt nichts mit")


func _dc_round_trip() -> void:
	var found := 0
	for k in 40:
		var g := MauGame.create(dc_cfg({"swap_cards": "on" if k % 2 == 1 else "off"}), RulesFixture.players(2 + k % 7, "bot"), 810_000 + k)
		g.start_round()
		var rng := RandomNumberGenerator.new()
		rng.seed = 19 + k
		var hit := false
		for step in 800:
			if not g.state in MauGame.PLAY_PHASES:
				break
			var seat := g.current_seat()
			var r := g.apply(seat, MauBot.choose(g.view_for(seat), rng.randi(), 2))
			if not dc_ev(r.events, "discard_color").is_empty() or (k % 2 == 0 and g.phase() == "discard_pick"):  # auch mitten in der Auswahl
				hit = true
				break
		if not hit:
			continue
		found += 1
		var text := JSON.stringify(g.to_dict())
		var h := MauGame.from_dict(JSON.parse_string(text))
		check(JSON.stringify(h.to_dict()) == text and h.n_cards == g.n_cards and RulesFixture.card_check(h) == "", "Rundreise nach dem Ablegen (%d)" % k)
		var r1 := RandomNumberGenerator.new()
		r1.seed = 3 + k
		var r2 := RandomNumberGenerator.new()
		r2.seed = 3 + k
		_advance(g, r1, 250)
		_advance(h, r2, 250)
		check(JSON.stringify(g.to_dict()) == JSON.stringify(h.to_dict()), "nach dem Laden gleich weitergespielt (%d)" % k)
		if found >= 4:
			break
	check(found >= 2, "Rundreise: Partien mit „Farbe ablegen“ gefunden (%d)" % found)


# --- Bot ---

func _dc_bot(g: MauGame, seat: int, level := 2) -> Dictionary:
	return MauBot.choose(g.view_for(seat), 3, level)


func _dc_bot_decisions() -> void:
	var g := dc_make({"hands": [["hell_rot_ablegen", "hell_rot_1", "hell_rot_2", "hell_gelb_3", "hell_gelb_4", "hell_blau_6", "hell_rot_7"],
		["hell_blau_1", "hell_blau_2", "hell_blau_3"], ["hell_gruen_1", "hell_gruen_2", "hell_gruen_3"]], "top": "hell_rot_5"})
	var a := _dc_bot(g, 0)
	check(int(a.get("card", -1)) == RulesFixture.card(g, 0, "hell_rot_ablegen"), "nimmt 3 mit: ablegen (%s)" % str(a))
	g = dc_make({"hands": [["hell_rot_ablegen", "hell_rot_1", "hell_gelb_3", "hell_gelb_4", "hell_blau_6"], ["hell_blau_1", "hell_blau_2", "hell_blau_3"],
		["hell_gruen_1", "hell_gruen_2", "hell_gruen_3"]], "top": "hell_rot_5"})
	a = _dc_bot(g, 0)
	check(int(a.get("card", -1)) == RulesFixture.card(g, 0, "hell_rot_1"), "nimmt nur 1 mit: lieber Rot 1 (%s)" % str(a))
	g = dc_make({"hands": [["hell_rot_ablegen", "hell_rot_1"], ["hell_blau_1", "hell_blau_2", "hell_blau_3"], ["hell_gruen_1", "hell_gruen_2"]],
		"top": "hell_rot_5"})
	a = _dc_bot(g, 0)
	check(int(a.get("card", -1)) == RulesFixture.card(g, 0, "hell_rot_ablegen"), "leert die Hand: ablegen ohne „Mau!“ (%s)" % str(a))
	g = dc_make({"hands": [["hell_ablegen_joker", "hell_gelb_1", "hell_gelb_2", "hell_gelb_3", "hell_blau_1", "hell_gruen_4"], ["hell_blau_2"],
		["hell_gruen_1"]], "top": "hell_rot_5"})
	a = _dc_bot(g, 0)
	check(int(a.get("card", -1)) == RulesFixture.card(g, 0, "hell_ablegen_joker") and str(a.get("color", "")) == "gelb",
		"Ablegen-Joker mit der Farbe mit den meisten Karten (%s)" % str(a))
	g = dc_make({"hands": [["hell_ablegen_joker", "hell_rot_1", "hell_gelb_2", "hell_blau_3"], ["hell_blau_2"], ["hell_gruen_1"]], "top": "hell_rot_5"})
	a = _dc_bot(g, 0)
	check(int(a.get("card", -1)) == RulesFixture.card(g, 0, "hell_rot_1"), "Ablegen-Joker aufsparen, wenn er wenig mitnimmt (%s)" % str(a))
	# Mau vor dem Ablegen, nach dem 1 Karte bleibt; danach bei der Karte bleiben
	g = dc_make({"hands": [["hell_rot_3", "hell_rot_4", "hell_blau_1", "hell_rot_ablegen"], ["hell_blau_2", "hell_blau_3"], ["hell_gruen_1", "hell_gruen_2"]],
		"top": "hell_rot_5"})
	a = _dc_bot(g, 0)
	check(str(a.get("a", "")) == "mau", "Bot ruft vor dem Ablegen auf 1 Karte „Mau!“ (%s)" % str(a))
	dc_act(g, 0, a, "Bot ruft")
	for lvl in [1, 2]:
		for sd in 6:
			var b := MauBot.choose(g.view_for(0), sd, lvl)
			check(str(b.get("a", "")) == "play" and MauBot.left_after(g.view_for(0), b) == 1, "nach dem Ruf: Karte, nach der 1 bleibt (%s)" % str(b))
	# Gezogen: wenig → behalten, viel → legen
	g = dc_make({"hands": [["hell_gelb_1", "hell_gelb_2", "hell_blau_6", "hell_rot_1"], ["hell_blau_2"], ["hell_gruen_1"]], "top": "hell_rot_5",
		"draw": ["hell_rot_ablegen"]})
	g.apply(0, {"a": "draw"})
	check(g.phase() == "drawn" and str(_dc_bot(g, 0).get("a", "")) == "keep", "gezogene Ablegen-Karte, die 1 mitnimmt: behalten")
	g = dc_make({"hands": [["hell_rot_1", "hell_rot_2", "hell_blau_6", "hell_rot_3", "hell_gelb_4"], ["hell_blau_2"], ["hell_gruen_1"]], "top": "hell_rot_5",
		"draw": ["hell_rot_ablegen"]})
	g.apply(0, {"a": "draw"})
	check(g.phase() == "drawn" and str(_dc_bot(g, 0).get("a", "")) == "play", "gezogene Ablegen-Karte, die 3 mitnimmt: legen")
	# JSON-Sicht
	g = dc_make({"hands": [["hell_ablegen_joker", "hell_gelb_1", "hell_gelb_2", "hell_gelb_3", "hell_blau_1", "hell_gruen_4"], ["hell_blau_2"],
		["hell_gruen_1"]], "top": "hell_rot_5"})
	var jv: Dictionary = JSON.parse_string(JSON.stringify(g.view_for(0)))
	a = MauBot.choose(jv, 3, 2)
	check(str(a.get("color", "")) == "gelb" and bool(g.apply(0, a).ok), "Bot auf JSON-Sicht (%s)" % str(a))
	# Auswahl: Zahlen mit, Aktionskarten behalten – außer der Bot wird damit fertig; Joker: Spielfarbe = häufigste Restfarbe
	g = dc_make({"hands": [["hell_rot_ablegen", "hell_rot_1", "hell_rot_plus1", "hell_rot_7", "hell_gelb_3", "hell_gelb_4"], ["hell_blau_1", "hell_blau_2"],
		["hell_gruen_1", "hell_gruen_2"]], "top": "hell_rot_5"})
	dc_play(g, 0, "hell_rot_ablegen", "Auswahl für den Bot")
	a = _dc_bot(g, 0)
	check(str(a.get("a", "")) == "discard_pick" and CardDB.sort_keys(_dc_keys(g, 0, a.cards)) == ["hell_rot_1", "hell_rot_7"] and not a.has("color"),
		"Bot legt Zahlen mit, behält +1 (%s)" % str(a))
	g = dc_make({"hands": [["hell_rot_ablegen", "hell_rot_1", "hell_rot_plus1"], ["hell_blau_1", "hell_blau_2"], ["hell_gruen_1", "hell_gruen_2"]],
		"top": "hell_rot_5"})
	dc_play(g, 0, "hell_rot_ablegen", "Auswahl, die fertig macht")
	a = _dc_bot(g, 0)
	check(str(a.get("a", "")) == "discard_pick" and (a.cards as Array).size() == 2, "Bot wird fertig: alles mit (%s)" % str(a))
	g = dc_make({"hands": [["hell_ablegen_joker", "hell_gelb_1", "hell_gelb_2", "hell_blau_1", "hell_blau_2", "hell_gruen_4"], ["hell_blau_3"],
		["hell_gruen_1"]], "top": "hell_rot_5"})
	dc_play(g, 0, "hell_ablegen_joker", "Joker für den Bot", "gelb")
	a = _dc_bot(g, 0)
	check(str(a.get("a", "")) == "discard_pick" and (a.cards as Array).size() == 2 and str(a.get("color", "")) == "blau" and bool(g.apply(0, a).ok),
		"Bot: Gelbe mit, weiter mit Blau (%s)" % str(a))
	# Mau in der Auswahl, wenn danach 1 Karte bleibt
	g = dc_make({"hands": [["hell_rot_ablegen", "hell_rot_1", "hell_rot_2", "hell_gelb_3"], ["hell_blau_1", "hell_blau_2"], ["hell_gruen_1", "hell_gruen_2"]],
		"top": "hell_rot_5"})
	dc_play(g, 0, "hell_rot_ablegen", "ohne Ruf gelegt")
	check(str(_dc_bot(g, 0).get("a", "")) == "mau", "Bot ruft in der Auswahl „Mau!“")


# --- Bot-Dauerlauf ---

func _dc_bot_run() -> void:
	var games := DC_GAMES
	if OS.get_environment("RULES_DISCARD_GAMES").is_valid_int():
		games = int(OS.get_environment("RULES_DISCARD_GAMES"))
	var t0 := Time.get_ticks_msec()
	var errors := 0
	for i in games:
		var err := _dc_bot_game(i)
		if err != "":
			errors += 1
			if errors <= 10:
				print("FAIL: Partie %d: %s" % [i, err])
	check(errors == 0, "Bot-Dauerlauf mit „Farbe ablegen“: %d von %d Partien fehlerhaft" % [errors, games])
	check(int(dc_stats.get("ablegen", 0)) > games / 2 and int(dc_stats.get("ablegen_fertig", 0)) > 0 and int(dc_stats.get("ablegen_joker", 0)) > 0,
		"Ablegen kommt oft vor, auch als Joker und zum Fertigwerden")
	check(int(dc_stats.get("mau_blind", 0)) == 0, "Bots rufen „Mau!“ nur, wenn danach 1 Karte bleibt (%d blind)" % int(dc_stats.get("mau_blind", 0)))
	print("Bot-Dauerlauf mit „Farbe ablegen“: %d Partien in %.1f s – %s" % [games, (Time.get_ticks_msec() - t0) / 1000.0, str(dc_stats)])


func _dc_bot_game(i: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5_300_029 * i + 23
	var cfg := RulesFixture.random_config(rng, i % 2 == 1, i % 3 == 2, true)
	var n := rng.randi_range(2, 10)
	var levels: Array = []
	for s in n:
		levels.append(rng.randi_range(0, 2))
	var g := MauGame.create(cfg, RulesFixture.players(n, "bot"), rng.randi())
	g.start_round()
	var extra := 1 if rng.randf() < 0.2 else 0
	var forget := rng.randf() * 0.5
	for r in DC_ROUND_LIMIT:
		if g.n_cards != cfg.card_count():
			return "Kartenzahl %d" % g.n_cards
		var dc := RulesFixture.deck_check(g)
		if dc != "":
			return "Runde %d: %s" % [g.round_no, dc]
		var err := _dc_bot_round(g, rng, levels, forget)
		if err != "":
			return "Runde %d (%d Spieler, %s): %s" % [g.round_no, n, JSON.stringify(cfg.to_dict()), err]
		dc_count("runden")
		if g.is_over():
			return ""
		if cfg.effective_scoring() != "points500":
			if extra <= 0:
				return ""
			extra -= 1
		var res := g.apply(0, {"a": "next_round"})
		if not bool(res.ok):
			return "next_round abgelehnt: " + str(res.reason)
	return "" if cfg.effective_scoring() == "points500" else "zu viele Runden"


func _dc_bot_round(g: MauGame, rng: RandomNumberGenerator, levels: Array, forget: float) -> String:
	var n := g.players.size()
	var steps := 0
	var called := -1
	while g.state in MauGame.PLAY_PHASES:
		steps += 1
		if steps > DC_STEP_LIMIT:
			return "Zugobergrenze %d erreicht" % DC_STEP_LIMIT
		if g.mau_open >= 0 and rng.randf() < 0.6:
			var o := rng.randi_range(0, n - 1)
			var ca := MauBot.choose(g.view_for(o), rng.randi(), int(levels[o]))
			if str(ca.get("a", "")) == "catch":
				var cr := g.apply(o, ca)
				if not bool(cr.ok):
					return "catch abgelehnt: " + str(cr.reason)
				dc_count("erwischt")
		var seat := g.current_seat()
		var view := g.view_for(seat)
		if bool(view.hints.can_mau) and rng.randf() < forget:
			view.hints.can_mau = false
		var act := MauBot.choose(view, rng.randi(), int(levels[seat]))
		if act.is_empty():
			return "Bot ohne Aktion in Phase %s (%s)" % [g.state, str(view.hints)]
		var kind := str(act.get("a", ""))
		var before := (g.hands[seat] as Array).size()
		var res := g.apply(seat, act)
		if not bool(res.ok):
			return "Aktion %s abgelehnt: %s" % [JSON.stringify(act), res.reason]
		dc_count("aktionen")
		if kind == "mau":
			if before >= 2:
				called = seat
				if before > 2:
					dc_count("mau_vor_ablegen")
		elif called == seat and kind != "catch" and g.state != "discard_pick":  # Erwischen ändert die Hand nicht; nach der Auswahl zählen
			# Ein Kartentausch nach dem Ruf (Zufallsbot) löscht alle Rufe nach der Regel; das zählt wie im Kartentausch-Test nicht.
			var swapped := false
			for e in res.events:
				if str(e.e) == "swap_hands":
					swapped = true
			if swapped:
				dc_count("mau_dann_tausch")
			elif (g.hands[seat] as Array).size() > 1 and int(g.place[seat]) == 0:
				dc_count("mau_blind")
				if int(dc_stats.get("mau_blind", 0)) <= 6:
					print("blinder Ruf: Platz %d (Stufe %d), danach %s → Hand %d, Ereignisse %s" % [seat, int(levels[seat]), JSON.stringify(act),
						(g.hands[seat] as Array).size(), str(dc_names(res.events))])
			called = -1
		var last_discard := -1
		for e in res.events:
			match str(e.e):
				"discard_color":
					dc_count("ablegen")
					dc_count("mitabgelegt", int(e.count))
					last_discard = int(e.seat)
					if g._kind[g.faces[g.side * g.n_cards + int(g.discard.back())]] == CardDB.DISCARD_WILD or str(act.get("color", "")) != "":
						dc_count("ablegen_joker")
					for k in e.faces:
						if str(CardDB.parse_key(str(k)).get("color", "")) != str(e.color):
							return "discard_color: %s nicht in %s" % [str(k), str(e.color)]
				"finish":
					if int(e.seat) == last_discard:
						dc_count("ablegen_fertig")
		var inv := RulesFixture.invariants(g)
		if inv != "":
			return "nach %s: %s" % [JSON.stringify(act), inv]
	return ""


func _dc_keys(g: MauGame, seat: int, ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		out.append(g._key[g.faces[g.side * g.n_cards + int(id)]])
	return out
