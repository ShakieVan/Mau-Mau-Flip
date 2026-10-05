extends SceneTree
# Modul F1a: Sortierung der Hand (CardSort): Zerlegen der Gesichtsschlüssel, Farbe/Wert/Punkte nach aktiver Seite, Joker rechts,
# Gruppenlücken, manuelle Reihenfolge (neue Karten rechts), Punktsummen beider Seiten (1280 / 1480).
# Aufruf: tools/godot_run.ps1 -Script res://tests/test_ui_hand_sort.gd -Headless
var ok := 0
var failed := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		ok += 1
	else:
		failed += 1
		print("FAIL: ", msg)


func cards_of(faces: Array) -> Array:
	var out: Array = []
	for i in faces.size():
		out.append({"id": i, "face": faces[i], "back": ""})
	return out


func faces_of(sorted: Array) -> Array:
	var out: Array = []
	for c in sorted:
		out.append(c.face)
	return out


# Alle 112 Gesichter einer Seite (docs/BETA1_PLAN.md Abschnitt 3).
func deck(side: String) -> Array:
	var out: Array = []
	var colors: Array = CardSort.COLOR_ORDER[side]
	var acts := ["plus1", "aussetzen", "richtungswechsel", "flip"] if side == "hell" else ["plus5", "alle_aussetzen", "richtungswechsel", "flip"]
	for c in colors:
		for v in range(1, 10):
			out.append("%s_%s_%d" % [side, c, v])
			out.append("%s_%s_%d" % [side, c, v])
		for a in acts:
			out.append("%s_%s_%s" % [side, c, a])
			out.append("%s_%s_%s" % [side, c, a])
	var jokers := ["wuenscher", "wuenscher_plus2"] if side == "hell" else ["wuenscher", "farbjagd"]
	for j in jokers:
		for k in 4:
			out.append("%s_%s" % [side, j])
	return out


func _init() -> void:
	# Zerlegen
	var p := CardSort.parse("hell_rot_7")
	check(p.side == "hell" and p.color == "rot" and p.kind == "zahl" and p.value == 7 and not p.joker, "hell_rot_7")
	p = CardSort.parse("dunkel_lila_alle_aussetzen")
	check(p.side == "dunkel" and p.color == "lila" and p.kind == "alle_aussetzen" and not p.joker, "dunkel_lila_alle_aussetzen")
	p = CardSort.parse("hell_wuenscher_plus2")
	check(p.side == "hell" and p.color == "" and p.kind == "wuenscher_plus2" and p.joker, "hell_wuenscher_plus2")
	p = CardSort.parse("dunkel_farbjagd")
	check(p.joker and p.kind == "farbjagd", "dunkel_farbjagd")
	p = CardSort.parse("rueckseite")
	check(p.side == "" and not p.joker, "rueckseite")
	# Punkte und Kontrollsummen
	check(CardSort.points("hell_gelb_9") == 9 and CardSort.points("hell_gelb_plus1") == 10 and CardSort.points("dunkel_pink_plus5") == 20, "Punkte Zahl/Zieh")
	check(CardSort.points("dunkel_orange_alle_aussetzen") == 30 and CardSort.points("hell_wuenscher") == 40 and CardSort.points("hell_wuenscher_plus2") == 50 and CardSort.points("dunkel_farbjagd") == 60, "Punkte Aktionen/Joker")
	var sum_h := 0
	for f in deck("hell"):
		sum_h += CardSort.points(f)
	var sum_d := 0
	for f in deck("dunkel"):
		sum_d += CardSort.points(f)
	check(deck("hell").size() == 112 and sum_h == 1280, "Punktsumme hell 1280 (%d)" % sum_h)
	check(deck("dunkel").size() == 112 and sum_d == 1480, "Punktsumme dunkel 1480 (%d)" % sum_d)
	# Farbe (hell)
	var hand := ["hell_wuenscher", "hell_blau_9", "hell_rot_flip", "hell_gelb_3", "hell_rot_7", "hell_gruen_aussetzen",
		"hell_wuenscher_plus2", "hell_gelb_plus1", "hell_blau_richtungswechsel", "hell_rot_2"]
	var by_color := faces_of(CardSort.sort_cards(cards_of(hand), "farbe"))
	check(by_color == ["hell_rot_2", "hell_rot_7", "hell_rot_flip", "hell_gelb_3", "hell_gelb_plus1", "hell_gruen_aussetzen",
		"hell_blau_9", "hell_blau_richtungswechsel", "hell_wuenscher", "hell_wuenscher_plus2"], "Farbe hell: %s" % [by_color])
	check(CardSort.group_starts(by_color, "farbe") == PackedInt32Array([3, 5, 6, 8]), "Lücken zwischen Farbgruppen: %s" % [CardSort.group_starts(by_color, "farbe")])
	# Farbe (dunkel)
	var dark := ["dunkel_farbjagd", "dunkel_lila_6", "dunkel_pink_plus5", "dunkel_tuerkis_7", "dunkel_wuenscher", "dunkel_orange_9", "dunkel_pink_1"]
	var dsort := faces_of(CardSort.sort_cards(cards_of(dark), "farbe"))
	check(dsort == ["dunkel_pink_1", "dunkel_pink_plus5", "dunkel_tuerkis_7", "dunkel_orange_9", "dunkel_lila_6", "dunkel_wuenscher", "dunkel_farbjagd"], "Farbe dunkel: %s" % [dsort])
	# Wert
	var hand2 := ["hell_blau_7", "hell_rot_7", "hell_gelb_2", "hell_wuenscher", "hell_gruen_plus1", "hell_rot_flip", "hell_gruen_2"]
	var by_value := faces_of(CardSort.sort_cards(cards_of(hand2), "wert"))
	check(by_value == ["hell_gelb_2", "hell_gruen_2", "hell_rot_7", "hell_blau_7", "hell_gruen_plus1", "hell_rot_flip", "hell_wuenscher"], "Wert: %s" % [by_value])
	check(CardSort.group_starts(by_value, "wert") == PackedInt32Array([6]), "Wert: nur Joker abgesetzt")
	# Punkte (aufsteigend, teure Karten und Joker rechts)
	var hand3 := ["dunkel_farbjagd", "dunkel_lila_alle_aussetzen", "dunkel_pink_3", "dunkel_wuenscher", "dunkel_orange_plus5", "dunkel_tuerkis_9"]
	var by_points := faces_of(CardSort.sort_cards(cards_of(hand3), "punkte"))
	check(by_points == ["dunkel_pink_3", "dunkel_tuerkis_9", "dunkel_orange_plus5", "dunkel_lila_alle_aussetzen", "dunkel_wuenscher", "dunkel_farbjagd"], "Punkte: %s" % [by_points])
	# Joker stehen in jeder automatischen Sortierung rechts
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var all := deck("hell")
	var right_ok := true
	for mode in ["farbe", "wert", "punkte"]:
		for trial in 20:
			var pick: Array = []
			for k in 12:
				pick.append(all[rng.randi_range(0, all.size() - 1)])
			var s := faces_of(CardSort.sort_cards(cards_of(pick), mode))
			var seen_joker := false
			for f in s:
				var j: bool = CardSort.parse(f).joker
				if seen_joker and not j:
					right_ok = false
				seen_joker = seen_joker or j
	check(right_ok, "Joker immer rechts")
	# Gleiche Karten: stabil nach Kennung
	var dup := [{"id": 9, "face": "hell_rot_5", "back": ""}, {"id": 2, "face": "hell_rot_5", "back": ""}, {"id": 4, "face": "hell_rot_1", "back": ""}]
	check(CardSort.sort_ids(dup, "farbe") == [4, 2, 9], "gleiche Gesichter nach Kennung")
	# Manuell: Reihenfolge bleibt, neue rechts, entfernte fallen weg
	var cards := [{"id": 1, "face": "hell_rot_1"}, {"id": 5, "face": "hell_rot_2"}, {"id": 3, "face": "hell_rot_3"}, {"id": 8, "face": "hell_gelb_1"}]
	check(CardSort.merge_manual([3, 1, 7, 5], cards) == [3, 1, 5, 8], "manuell: gemerkte Folge, neue Karte rechts")
	check(CardSort.sort_cards(cards, "manuell") == cards, "manuell sortiert nicht")
	check(CardSort.group_starts(["hell_rot_1", "hell_gelb_1"], "manuell").is_empty(), "manuell ohne Lücken")
	check(CardSort.next_mode("farbe") == "wert" and CardSort.next_mode("manuell") == "farbe", "Moduswechsel reihum")
	print("RESULT: %d ok" % ok)
	quit(0 if failed == 0 else 1)
