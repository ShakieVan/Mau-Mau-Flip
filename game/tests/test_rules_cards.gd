extends SceneTree
# Modul A: Kartendaten (CardDB), Regeloptionen (RuleConfig) und Texte (RulesText).

var failures := 0
var checks := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)


func _initialize() -> void:
	_cards()
	_config()
	_texts()
	print("Laufzeit seit Godot-Start: %.1f s" % (Time.get_ticks_msec() / 1000.0))
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)


func _cards() -> void:
	var light := CardDB.faces_light()
	var dark := CardDB.faces_dark()
	check(light.size() == 112 and dark.size() == 112, "je Seite 112 Gesichter (%d/%d)" % [light.size(), dark.size()])
	var sum_l := 0
	var sum_d := 0
	for f in light:
		sum_l += CardDB.points(f)
		check(f.side == "hell", "helle Liste nur hell")
	for f in dark:
		sum_d += CardDB.points(f)
		check(f.side == "dunkel", "dunkle Liste nur dunkel")
	check(sum_l == 1280, "Kontrollsumme hell 1280 (%d)" % sum_l)
	check(sum_d == 1480, "Kontrollsumme dunkel 1480 (%d)" % sum_d)
	var keys := CardDB.all_keys()
	check(keys.size() == 108, "108 verschiedene Gesichter (%d)" % keys.size())
	var uniq := {}
	for f in light + dark:
		uniq[CardDB.face_key(f)] = true
	check(uniq.size() == 108, "108 Schlüssel aus beiden Listen (%d)" % uniq.size())
	# Anzahlen je Art
	var count := {}
	for f in light + dark:
		var k := "%s_%s" % [f.side, f.kind]
		count[k] = int(count.get(k, 0)) + 1
	var want := {"hell_zahl": 72, "hell_plus1": 8, "hell_aussetzen": 8, "hell_richtungswechsel": 8, "hell_flip": 8,
		"hell_wuenscher": 4, "hell_wuenscher_plus2": 4, "dunkel_zahl": 72, "dunkel_plus5": 8, "dunkel_alle_aussetzen": 8,
		"dunkel_richtungswechsel": 8, "dunkel_flip": 8, "dunkel_wuenscher": 4, "dunkel_farbjagd": 4}
	for k in want:
		check(int(count.get(k, 0)) == want[k], "Anzahl %s = %d (%d)" % [k, want[k], int(count.get(k, 0))])
	check(count.size() == want.size(), "keine weiteren Arten")
	# keine 0, Zahlen 1–9
	var zero := false
	for f in light + dark:
		if f.kind == "zahl" and (int(f.value) < 1 or int(f.value) > 9):
			zero = true
	check(not zero, "keine 0, Zahlen 1–9")
	# Schlüsselformat
	check(CardDB.face_key({"side": "hell", "color": "rot", "kind": "zahl", "value": 7}) == "hell_rot_7", "Schlüssel hell_rot_7")
	check(CardDB.face_key({"side": "hell", "color": "gelb", "kind": "plus1", "value": 0}) == "hell_gelb_plus1", "Schlüssel hell_gelb_plus1")
	check(CardDB.face_key({"side": "dunkel", "color": "lila", "kind": "alle_aussetzen", "value": 0}) == "dunkel_lila_alle_aussetzen", "Schlüssel dunkel_lila_alle_aussetzen")
	check(CardDB.face_key({"side": "dunkel", "color": "", "kind": "farbjagd", "value": 0}) == "dunkel_farbjagd", "Schlüssel dunkel_farbjagd")
	for k in ["hell_wuenscher", "hell_wuenscher_plus2", "dunkel_wuenscher", "dunkel_farbjagd", "dunkel_pink_flip", "hell_blau_9"]:
		check(CardDB.is_key(k), "Schlüssel vorhanden: " + k)
	for k in keys:
		check(CardDB.face_key(CardDB.parse_key(k)) == k, "Rundreise Schlüssel " + k)
	# Punkte
	check(CardDB.points_of_key("hell_rot_7") == 7, "Punkte Zahl")
	check(CardDB.points_of_key("hell_rot_plus1") == 10, "Punkte +1")
	check(CardDB.points_of_key("dunkel_pink_plus5") == 20, "Punkte +5")
	check(CardDB.points_of_key("dunkel_pink_alle_aussetzen") == 30, "Punkte Alle aussetzen")
	check(CardDB.points_of_key("hell_wuenscher") == 40, "Punkte Wünscher")
	check(CardDB.points_of_key("hell_wuenscher_plus2") == 50, "Punkte Wünscher +2")
	check(CardDB.points_of_key("dunkel_farbjagd") == 60, "Punkte Farbjagd")
	# Sortierung: Seite, Farbe, Art, Wert
	var sorted := CardDB.sort_keys(["dunkel_pink_1", "hell_wuenscher", "hell_blau_2", "hell_rot_flip", "hell_rot_9", "hell_rot_1"])
	check(sorted == ["hell_rot_1", "hell_rot_9", "hell_rot_flip", "hell_blau_2", "hell_wuenscher", "dunkel_pink_1"],
		"Sortierung nach Seite, Farbe, Art, Wert (%s)" % str(sorted))
	check(CardDB.colors("dunkel") == ["pink", "tuerkis", "orange", "lila"], "Farben dunkel")
	check(CardDB.is_wild(CardDB.parse_key("dunkel_farbjagd")) and not CardDB.is_wild(CardDB.parse_key("dunkel_pink_flip")), "is_wild")
	check(CardDB.is_draw_card(CardDB.parse_key("hell_wuenscher_plus2")) and not CardDB.is_draw_card(CardDB.parse_key("hell_wuenscher")), "is_draw_card")


func _config() -> void:
	var c := RuleConfig.new()
	var d := c.to_dict()
	var want := {"round_end": "first", "scoring": "none", "target": 500, "hand_size": 7, "draw_rule": "one", "drawn_card": "may",
		"stacking": "off", "penalty_turn": "skip", "wild_restriction": "free", "wild_counts_for_bluff": true, "jagd_wild_stops": false,
		"mau_call": "catch", "mau_penalty": 2, "backs_visible": true, "peek_own_backs": true, "two_player_reverse_skips": true,
		"flip_last_card": "execute", "swap_cards": "off", "swap_direction": "clockwise", "gamble_cards": "off",
		"discard_color": "off"}
	for k in want:
		check(d.has(k) and d[k] == want[k], "Standard %s = %s (%s)" % [k, str(want[k]), str(d.get(k))])
	check(d.size() == want.size(), "to_dict hat genau die Optionen (%d)" % d.size())
	check(c.preset_name() == "offiziell", "Standard = offiziell")
	var fam := RuleConfig.preset("familie")
	check(fam.round_end == "last" and fam.stacking == "same" and fam.wild_restriction == "enforce" and fam.mau_penalty == 1
		and fam.swap_cards == "on" and fam.gamble_cards == "off" and fam.discard_color == "off", "Voreinstellung familie (mit Kartentausch)")
	var mm := RuleConfig.preset("mau_mau")
	check(mm.stacking == "same" and mm.wild_restriction == "enforce" and mm.mau_penalty == 1 and mm.round_end == "first", "Voreinstellung mau_mau")
	var k5 := RuleConfig.preset("klassisch500")
	check(k5.scoring == "points500" and k5.wild_restriction == "free" and k5.target == 500, "Voreinstellung klassisch500")
	# 0.1.3: Anzweifeln entfällt in der Oberfläche; gespeichertes "bluff" wird beim Laden zu "free", Tauschrichtungen
	check(RuleConfig.migrate_dict({"wild_restriction": "bluff", "stacking": "same"}) == {"wild_restriction": "free", "stacking": "same"}
		and RuleConfig.migrate_dict({"wild_restriction": "enforce"}).wild_restriction == "enforce" and RuleConfig.migrate_dict({}) == {}, "migrate_dict: bluff → free")
	var k5b := RuleConfig.from_dict({"scoring": "points500", "wild_counts_for_bluff": false})
	check(k5b.preset_name() == "klassisch500", "ohne Anzweifeln zählt wild_counts_for_bluff nicht für die Voreinstellung")
	var steps := []
	for sd in ["clockwise", "counter", "play", "against"]:
		var sc := RuleConfig.from_dict({"swap_direction": sd})
		check(sc.swap_direction == sd and RuleConfig.swap_direction_title(sd) != "", "Tauschrichtung %s" % sd)
		steps.append([sc.swap_step(1), sc.swap_step(-1)])
	check(steps == [[1, 1], [-1, -1], [1, -1], [-1, 1]], "swap_step je Richtung (%s)" % str(steps))
	for p in RuleConfig.preset_names():
		check(RuleConfig.preset(p).preset_name() == p, "preset_name erkennt " + p)
	# Rundreise auch über JSON (Zahlen als float)
	var custom := RuleConfig.from_dict({"round_end": "last", "hand_size": 9, "mau_call": "auto", "backs_visible": false, "target": 250})
	var back := RuleConfig.from_dict(JSON.parse_string(JSON.stringify(custom.to_dict())))
	check(back.to_dict() == custom.to_dict(), "to_dict/from_dict über JSON")
	check(back.hand_size == 9 and typeof(back.hand_size) == TYPE_INT, "hand_size bleibt int")
	check(custom.preset_name() == "", "eigene Regeln ohne Voreinstellung")
	# Ungültiges bleibt beim Standard, Zahlen werden begrenzt
	var bad := RuleConfig.from_dict({"round_end": "nie", "hand_size": 99, "mau_penalty": 0.0, "stacking": 3, "unbekannt": 1, "backs_visible": 0})
	check(bad.round_end == "first", "ungültiger Wert ignoriert")
	check(bad.hand_size == 10 and bad.mau_penalty == 1, "Zahlen begrenzt (%d, %d)" % [bad.hand_size, bad.mau_penalty])
	check(bad.stacking == "off" and not bad.backs_visible, "Typen geprüft")
	# effektive Wertung
	var e := RuleConfig.from_dict({"scoring": "points500", "round_end": "last"})
	check(e.effective_scoring() == "none", "points500 bei round_end=last → Platzierungen")
	check(RuleConfig.preset("klassisch500").effective_scoring() == "points500", "points500 bei round_end=first")
	# describe
	var lines := RuleConfig.new().describe()
	check(lines.size() >= 8, "describe liefert Zeilen (%d)" % lines.size())
	check("\n".join(lines).contains("dürfen immer gelegt werden") and not "\n".join(lines).contains("anzweifeln"), "describe: Wünscher +2 immer erlaubt")
	check("\n".join(RuleConfig.from_dict({"wild_restriction": "bluff"}).describe()).contains("anzweifeln"), "describe erwähnt Anzweifeln bei bluff")
	check("\n".join(RuleConfig.preset("familie").describe()).contains("Bis zum Letzten"), "describe familie: bis zum Letzten")
	check("\n".join(RuleConfig.preset("familie").describe()).contains("Stapeln"), "describe familie: Stapeln")
	check(c.duplicate_config().equals(c), "duplicate_config")


func _texts() -> void:
	var off := RuleConfig.new()
	var stack := RuleConfig.from_dict({"stacking": "same"})
	for k in CardDB.all_keys():
		var h := RulesText.card_help(k, off)
		check(h.size() >= 2, "Kartenhilfe für " + k)
		check(RulesText.face_title(k) != k, "Titel für " + k)
	var plus5 := "\n".join(RulesText.card_help("dunkel_lila_plus5", stack))
	check(plus5.contains("+5 darf gestapelt werden"), "„+5 darf gestapelt werden“ bei stacking=same")
	check(not "\n".join(RulesText.card_help("dunkel_lila_plus5", off)).contains("darf gestapelt"), "kein Stapeln bei stacking=off")
	check("\n".join(RulesText.card_help("hell_wuenscher_plus2", RuleConfig.from_dict({"wild_restriction": "bluff"}))).contains("anzweifeln"), "Wünscher +2: anzweifeln bei bluff")
	check("\n".join(RulesText.card_help("hell_wuenscher_plus2", RuleConfig.from_dict({"wild_restriction": "enforce"}))).contains("App achtet"),
		"Wünscher +2: App achtet bei enforce")
	check("\n".join(RulesText.card_help("hell_wuenscher_plus2", RuleConfig.from_dict({"wild_restriction": "free"}))).contains("jederzeit"),
		"Wünscher +2: jederzeit bei free")
	check("\n".join(RulesText.card_help("dunkel_farbjagd", off)).contains("beendet die Jagd nicht"), "Farbjagd: Joker beendet nicht")
	check("\n".join(RulesText.card_help("dunkel_farbjagd", RuleConfig.from_dict({"jagd_wild_stops": true}))).contains("beendet die Jagd."),
		"Farbjagd: Joker beendet")
	check("\n".join(RulesText.card_help("hell_rot_flip", off)).contains("dunkle Seite"), "Flip hell → dunkle Seite")
	check("\n".join(RulesText.card_help("dunkel_pink_flip", off)).contains("helle Seite"), "Flip dunkel → helle Seite")
	check("\n".join(RulesText.card_help("hell_blau_richtungswechsel", off)).contains("wie Aussetzen"), "Richtungswechsel zu zweit")
	check(RulesText.face_title("hell_gruen_7") == "Grün 7", "Titel Grün 7")
	check(RulesText.face_title("dunkel_tuerkis_plus5") == "Türkis +5", "Titel Türkis +5")
	check(RulesText.face_title("hell_wuenscher_plus2") == "Wünscher +2", "Titel Wünscher +2")
	check(RulesText.match_phrase("hell_rot_7") == "eine 7", "match_phrase Zahl")
	var ov := RulesText.overview(off)
	check(ov.size() >= 8, "Regelübersicht in Absätzen (%d)" % ov.size())
	for p in ov:
		check(str(p.get("title", "")) != "" and str(p.get("text", "")).length() > 20, "Absatz " + str(p.get("title", "")))
	var ov500 := ""
	for p in RulesText.overview(RuleConfig.preset("klassisch500")):
		ov500 += str(p.text)
	check(ov500.contains("500 Punkte"), "Übersicht klassisch500 nennt 500 Punkte")
