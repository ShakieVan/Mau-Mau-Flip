extends SceneTree
# Beta 1.4.4: Freche Sprüche (FunTexts) – Auswahl je Stufe, Häufigkeit und Abklingzeit, nie bei wichtigen Hinweisen, nie hinter dem
# Sichtschutz, Trödeln, Ereignisse (Richtungswechsel, Autsch, Pechsträhne, Farbjagd), falscher Tipp mit Pointe, Platzhalter,
# beide Sprachen (game/i18n/en_fun.po).

var ok := 0
var failed := 0

const ME := 0
const STD := "Du bist dran – lege Rot oder 7."


func check(cond: bool, text: String) -> void:
	if cond:
		ok += 1
	else:
		failed += 1
		print("FAIL: ", text)


static func players() -> Array:
	return [{"seat": 0, "name": "Ich", "kind": "human", "count": 7}, {"seat": 1, "name": "Kim", "kind": "human", "count": 1},
		{"seat": 2, "name": "Robo", "kind": "bot", "count": 5}]


static func view(turn: int, hand_n := 7, text := STD, phase := "turn") -> Dictionary:
	var hand: Array = []
	for i in hand_n:
		hand.append({"id": i, "face": "hell_rot_1"})
	if turn != ME and text == STD:
		text = "%s ist dran." % ["Ich", "Kim", "Robo"][turn]
	return {"phase": phase, "turn": turn, "seat": ME, "dir": 1, "hand": hand, "players": players(), "pending": {},
		"hints": {"text": text}}


func show(f: FunTexts, v: Dictionary) -> String:
	return f.hint_for(v, v.hints, ME, str(v.hints.text))


# Ein eigener Zug: anderer Zug, dann eigener (Zugbeginn); gibt den angezeigten Text zurück
func own_turn(f: FunTexts, hand_n := 7, gap := 40.0) -> String:
	f.tick(gap)
	show(f, view(2))
	return show(f, view(ME, hand_n))


func _init() -> void:
	I18n.set_language("de")
	check_levels()
	check_translations()
	check_replaceable()
	check_frequency()
	check_important()
	check_blocked_and_time()
	check_slow()
	check_events()
	check_fake_tip()
	check_luck()
	check_english()
	I18n.set_language("de")
	print("RESULT: %d ok, %d failed" % [ok, failed])
	quit(1 if failed > 0 else 0)


func check_levels() -> void:
	for occ in FunTexts.LINES:
		var nett := FunTexts.lines_for(occ, "nett")
		var frech := FunTexts.lines_for(occ, "frech")
		check(FunTexts.lines_for(occ, "aus").is_empty(), "aus: keine Zeilen (%s)" % occ)
		check(frech.size() >= 3 and frech.size() >= nett.size(), "frech hat alle Zeilen (%s)" % occ)
		for l in nett:
			check(frech.has(l), "nett ⊂ frech (%s)" % l)
		for e in FunTexts.LINES[occ]:
			check(str(e[1]) in ["nett", "frech"], "Stufe gültig: " + str(e[0]))
			if str(e[1]) == "frech":
				check(not nett.has(str(e[0])), "freche Zeile nicht in nett: " + str(e[0]))
	for occ in ["zug", "langsam", "viele", "wenige", "richtung"]:
		check(FunTexts.lines_for(occ, "frech").size() >= 6, "Hauptanlass mit mindestens 6 Sprüchen: " + occ)
	check(FunTexts.lines_for("tipp", "frech").size() == 20 and FunTexts.lines_for("tipp", "nett").is_empty(), "falsche Tipps: 20, nur in frech")
	check(FunTexts.lines_for("verarscht", "frech").size() == 20, "Pointen nach dem Tipp: 20")
	for occ in ["zug", "zug_name", "langsam", "langsam_andere", "richtung", "viele", "wenige", "pech_du", "glueck"]:
		check(FunTexts.lines_for(occ, "frech").size() == 20, "20 Sprüche in frech: " + occ)
	check(FunTexts.lines_for("zug", "nett").size() == 20 and FunTexts.lines_for("glueck", "nett").size() == 20, "Zug- und Glückssprüche alle nett")
	check(FunTexts.lines_for("zug_name", "frech").size() == 20 and FunTexts.lines_for("zug_name", "nett").is_empty(), "Namenssprüche alle frech")
	check(FunTexts.lines_for("farbjagd_du", "frech") == FunTexts.lines_for("pech_du", "frech") and FunTexts.lines_for("autsch_du", "nett") == FunTexts.lines_for("pech_du", "nett"),
		"Pech auf dich: Farbjagd und +5 auf die eigene letzte Karte benutzen die Pech-Liste")
	var texts := FunTexts.all_lines()
	var uniq := {}
	for l in texts:
		uniq[l] = true
	check(uniq.size() == texts.size(), "all_lines ohne Doppelte")
	check(FunTexts.lines_for("zug_name", "nett").is_empty(), "Namenssprüche (doof, in die Karten geguckt) nur in frech")
	check(FunTexts.clean_level("quatsch") == "frech" and FunTexts.clean_level("nett") == "nett", "Stufe bereinigt, ab Werk frech")
	check(AppSettings.defaults().get(FunTexts.SETTING) == "frech" and AppSettings.sanitize(FunTexts.SETTING, "laut") == null
		and AppSettings.sanitize(FunTexts.SETTING, "aus") == "aus", "Einstellung sprueche: Standard frech, nur aus/nett/frech")
	# Platzhalter: nur %s, und genau dort, wo ein Name gemeint ist
	for occ in FunTexts.LINES:
		var named: bool = occ in ["zug_name", "langsam_andere", "pech", "farbjagd"]
		for l in FunTexts.lines_for(occ, "frech"):
			var ph := I18n.placeholders(l)
			check((not ph.is_empty() and ph.all(func(p: Variant) -> bool: return p == "%s")) if named else ph.is_empty(), "Platzhalter passend (%s): %s" % [occ, l])
			if named:
				check(FunTexts.format_line(l, "Kim").count("Kim") == ph.size(), "Name an jeder Stelle eingesetzt: " + l)
			check(not FunTexts.format_line(l, "Kim").contains("%"), "eingesetzt ohne Rest-%: " + l)


func check_translations() -> void:
	var po := FileAccess.get_file_as_string("res://i18n/en_fun.po")
	check(po != "", "en_fun.po lesbar")
	var ids := {}
	var re := RegEx.create_from_string("msgid \"((?:[^\"\\\\]|\\\\.)*)\"\\s*\\nmsgstr \"((?:[^\"\\\\]|\\\\.)*)\"")
	for m in re.search_all(po):
		ids[m.get_string(1).replace("\\\"", "\"")] = m.get_string(2)
	for l in FunTexts.all_lines():
		check(ids.has(l) and str(ids[l]) != "", "Übersetzung vorhanden: " + l)
		if ids.has(l):
			check(I18n.placeholders(l) == I18n.placeholders(str(ids[l])), "Platzhalter gleich: " + l)
			# passt in die Hinweisleiste, auch im großen Modus (wie die längsten Regelhinweise)
			check(l.length() <= 80 and str(ids[l]).length() <= 80, "höchstens 80 Zeichen: " + l)
	for k in ["Sprüche", "Nett", "Frech"]:
		check(ids.has(k), "Einstellungstext übersetzt: " + k)
	check(ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray()).has("res://i18n/en_fun.po")
		and I18n.FILES.has("res://i18n/en_fun.po"), "en_fun.po in project.godot und I18n.FILES")


func check_replaceable() -> void:
	var v := view(ME)
	check(FunTexts.replaceable(v, v.hints, ME), "„Du bist dran – …“ ist ersetzbar")
	check(FunTexts.replaceable(view(1), view(1).hints, ME), "„Kim ist dran.“ ist ersetzbar")
	for t in ["Du bist dran – lege Rot oder 7. Denk an „Mau!“", "Du bist dran – nichts passt, zieh eine Karte.",
			"Wünscher +2 auf dich – Zieh 2.", "Drück den Glücksspielknopf!"]:
		var w := view(ME, 7, t)
		check(not FunTexts.replaceable(w, w.hints, ME), "nicht ersetzbar: " + t)
	var w2 := view(ME)
	w2.pending = {"kind": "plus5", "amount": 5}
	check(not FunTexts.replaceable(w2, w2.hints, ME), "offene Strafe: nicht ersetzbar")
	for ph in ["color", "drawn", "gamble", "challenge", "discard_pick", "round_over", "game_over"]:
		var w3 := view(ME, 7, STD, ph)
		check(not FunTexts.replaceable(w3, w3.hints, ME), "Phase %s: nicht ersetzbar" % ph)
	var w4 := view(ME)
	w4.hints["need_color"] = true
	check(not FunTexts.replaceable(w4, w4.hints, ME), "Farbe wählen: nicht ersetzbar")
	var w5 := view(1, 7, "Kim hat nicht „Mau!“ gerufen – erwischen! Kim ist dran.")
	w5.hints["catch"] = [1]
	check(not FunTexts.replaceable(w5, w5.hints, ME), "Erwischen: nicht ersetzbar")
	var w6 := view(1)
	w6["discard_pick"] = {"seat": 1, "color": "rot"}
	check(not FunTexts.replaceable(w6, w6.hints, ME), "Ablege-Auswahl: nicht ersetzbar")


func check_frequency() -> void:
	# aus: immer der Standardtext
	var off := FunTexts.new()
	off.set_level("aus")
	var all_std := true
	for i in 200:
		if own_turn(off, [1, 2, 7, 14][i % 4]) != STD:
			all_std = false
	check(all_std, "aus: nur Standardtexte")
	# frech/nett: ~25 % der Züge mit 7 Karten; nett nie eine freche Zeile
	for lvl in ["frech", "nett"]:
		var f := FunTexts.new()
		f.rng.seed = 4711
		f.set_level(lvl)
		var hits := 0
		var bad := 0
		var seen := {}
		for i in 400:
			var t := own_turn(f)
			if t != STD:
				hits += 1
				seen[f.line] = true
				if not FunTexts.lines_for(f.occasion, "nett").has(f.line) and lvl == "nett":
					bad += 1
				check(not t.contains("%s"), "kein offener Platzhalter: " + t)
			show(f, view(2))
		check(hits > 60 and hits < 150, "%s: etwa jeder vierte Zug ein Spruch (%d/400)" % [lvl, hits])
		check(bad == 0, "%s: keine frechen Zeilen" % lvl if lvl == "nett" else "frech: geprüft")
		check(seen.size() >= 6, "%s: abwechslungsreich (%d verschiedene)" % [lvl, seen.size()])
	# viele / wenige Karten
	var f2 := FunTexts.new()
	f2.rng.seed = 7
	var occ := {}
	for i in 200:
		own_turn(f2, 14)
		occ[f2.occasion] = true
		show(f2, view(2))
	check(occ.has("viele"), "ab 12 Karten: Sprüche über viele Karten")
	occ = {}
	for i in 200:
		own_turn(f2, 3)
		occ[f2.occasion] = true
		show(f2, view(2))
	check(occ.has("wenige") and not occ.has("viele"), "2–3 Karten: Sprüche über wenige Karten")
	# Abklingzeit: direkt nach einem Spruch kommt im nächsten Zug (innerhalb COOLDOWN) keiner
	var f3 := FunTexts.new()
	f3.rng.seed = 99
	var n := 0
	while own_turn(f3) == STD and n < 500:
		n += 1
	check(f3.showing(), "irgendwann ein Spruch")
	f3.tick(FunTexts.SHOW_TIME + 0.1)
	var quiet := true
	for i in 30:
		if own_turn(f3, 7, 0.5) != STD:
			quiet = false
	check(quiet, "Abklingzeit: kein neuer Zufallsspruch kurz danach")


func check_important() -> void:
	var f := FunTexts.new()
	f.rng.seed = 5
	var n := 0
	while own_turn(f) == STD and n < 500:
		n += 1
	check(f.showing(), "Spruch steht")
	var mau := view(ME, 2, "Du bist dran – lege Rot oder 7. Denk an „Mau!“")
	check(show(f, mau) == mau.hints.text and not f.showing(), "Mau-Pflicht verdrängt den Spruch sofort")
	var col := view(ME, 7, "Nach dem Flip liegt ein Joker oben – wähle die neue Farbe.", "color")
	col.hints["need_color"] = true
	for i in 100:
		check(own_turn(f, 7) != "" , "läuft")
		check(show(f, col) == col.hints.text, "Farbe wählen bleibt stehen")


func check_blocked_and_time() -> void:
	var f := FunTexts.new()
	f.rng.seed = 11
	var shown_blocked := false
	for i in 200:
		f.tick(40.0)
		f.hint_for(view(1), view(1).hints, ME, "x", true)
		var v := view(ME)
		if f.hint_for(v, v.hints, ME, STD, true) != STD:
			shown_blocked = true
		f.tick(40.0)                       # Sichtschutz liegt: keine Trödel-Uhr
		if f.hint_for(v, v.hints, ME, STD, true) != STD:
			shown_blocked = true
	check(not shown_blocked, "Weitergeben-Sichtschutz: nie ein Spruch")
	# Anzeigedauer
	var g := FunTexts.new()
	g.rng.seed = 3
	var n := 0
	while own_turn(g) == STD and n < 500:
		n += 1
	check(not g.tick(FunTexts.SHOW_TIME - 1.0) and g.showing(), "Spruch steht noch")
	check(g.tick(1.5) and not g.showing() and show(g, view(ME)) == STD, "nach SHOW_TIME zurück zum Standardtext")


func check_slow() -> void:
	var f := FunTexts.new()
	f.set_level("nett")
	f.tick(100.0)
	show(f, view(1))
	var v := view(ME)
	show(f, v)
	f._end()
	check(not f.tick(14.0), "vor 15 s nichts")
	check(f.tick(1.5), "nach 15 s: Hinweisleiste neu")
	var t := show(f, v)
	check(t != STD and f.occasion == "langsam", "Trödel-Spruch nach 15 s: " + t)
	f.tick(FunTexts.SHOW_TIME + 0.5)
	show(f, v)
	f.tick(30.0 - f.now + f._turn_start + 0.5)
	t = show(f, v)
	check(t != STD and f.occasion == "langsam", "zweiter Trödel-Spruch nach 30 s")
	# andere: Mensch Kim trödelt → Kommentar mit Namen; Computer Robo nicht
	var g := FunTexts.new()
	g.tick(100.0)
	show(g, view(ME))
	show(g, view(1))
	g.tick(FunTexts.SLOW_OTHER + 0.5)
	t = show(g, view(1))
	check(g.occasion == "langsam_andere" and t.contains("Kim"), "Kommentar über trödelnde Mitspielerin: " + t)
	var h := FunTexts.new()
	h.tick(100.0)
	show(h, view(2))
	h.tick(60.0)
	check(show(h, view(2)) == view(2).hints.text, "Computergegner bekommen keinen Trödel-Spruch")


func check_events() -> void:
	# +5 auf Kim mit 1 Karte → „Autsch“ (Kommentar am eigenen Gerät)
	var f := FunTexts.new()
	f.tick(100.0)
	var before := view(1)
	f.observe([{"e": "pending", "kind": "plus5", "amount": 5, "seat": 1, "by": 0}, {"e": "draw", "seat": 1, "count": 5, "reason": "strafe"}], before, ME)
	var t := show(f, view(2))
	check(f.occasion == "autsch", "Autsch bei +5 auf jemanden mit 1 Karte: " + t)
	# nie zwei Sprüche direkt hintereinander: ein neuer Anlass wartet mindestens GAP s
	f.tick(FunTexts.SHOW_TIME + 0.1)
	f.observe([{"e": "gamble_roll", "seat": 1, "value": 3}, {"e": "gamble_roll", "seat": 1, "value": 2}, {"e": "gamble_roll", "seat": 1, "value": 9}], before, ME)
	check(show(f, view(2)) == view(2).hints.text, "Pechsträhne wartet nach dem Autsch-Ende")
	f.tick(FunTexts.GAP)
	t = show(f, view(2))
	check(f.occasion == "pech" and t.contains("Kim"), "drei Glücksspiel-Treffer in Folge: " + t)
	# eigene Pechsträhne mit Unterbrechung zählt nicht
	var g := FunTexts.new()
	g.tick(100.0)
	g.observe([{"e": "gamble_roll", "seat": 0, "value": 3}, {"e": "gamble_roll", "seat": 0, "value": 0}, {"e": "gamble_roll", "seat": 0, "value": 2},
		{"e": "gamble_roll", "seat": 0, "value": 4}], before, ME)
	check(show(g, view(1)) == view(1).hints.text, "Unterbrochene Treffer: kein Spruch")
	g.observe([{"e": "gamble_roll", "seat": 0, "value": 1}], before, ME)
	show(g, view(1))
	check(g.occasion == "pech_du", "eigene drei Treffer in Folge")
	# Farbjagd ≥ 8 Karten auf mich
	var h := FunTexts.new()
	h.tick(100.0)
	h.observe([{"e": "pending", "kind": "farbjagd", "amount": 0, "seat": 0, "by": 1}, {"e": "draw", "seat": 0, "count": 9, "reason": "strafe"}], before, ME)
	show(h, view(1))
	check(h.occasion == "farbjagd_du", "Farbjagd mit 9 Karten: farbenblind?")
	var h2 := FunTexts.new()
	h2.tick(100.0)
	h2.observe([{"e": "pending", "kind": "farbjagd", "amount": 0, "seat": 0, "by": 1}, {"e": "draw", "seat": 0, "count": 3, "reason": "strafe"}], before, ME)
	check(show(h2, view(1)) == view(1).hints.text, "Farbjagd mit 3 Karten: kein Spruch")
	# Richtungswechsel: meistens ein Spruch, mit Nett nie der freche
	var hits := 0
	for i in 50:
		var r := FunTexts.new()
		r.set_level("nett")
		r.tick(100.0)
		r.observe([{"e": "reverse", "dir": -1, "seat": 1}], before, ME)
		if show(r, view(2)) != view(2).hints.text:
			hits += 1
			check(FunTexts.lines_for("richtung", "nett").has(r.line), "nett: kein frecher Richtungsspruch")
	check(hits > 15 and hits < 45, "Richtungswechsel: oft, nicht immer (%d/50)" % hits)
	# zu alter Anlass verfällt; wichtiger Hinweis zeigt ihn nicht
	var q := FunTexts.new()
	q.tick(100.0)
	q.observe([{"e": "pending", "kind": "plus5", "amount": 5, "seat": 1, "by": 0}], before, ME)
	var imp := view(ME, 7, "Du bist dran – lege Rot oder 7. Denk an „Mau!“")
	check(show(q, imp) == imp.hints.text, "Anlass wartet hinter wichtigem Hinweis")
	q.tick(FunTexts.QUEUE_LIFE + 1.0)
	check(show(q, view(2)) == view(2).hints.text, "veralteter Anlass verfällt")


func check_fake_tip() -> void:
	# Falsche Tipps kommen vor (nur frech); nach jedem, welche Zeile auch immer, wird die Pointe scharf
	var f := FunTexts.new()
	f.rng.seed = 2024
	var seen := {}
	var tips := 0
	var n := 0
	while n < 4000 and seen.size() < 20:
		own_turn(f)
		if f.occasion == "tipp":
			tips += 1
			seen[f.line] = true
			check(FunTexts.lines_for("tipp", "frech").has(f.line), "Tipp aus der Tipp-Liste: " + f.line)
			f.observe([{"e": "draw", "seat": 0, "count": 1, "reason": "zug"}], view(ME), ME)
			var note := f.take_notice()
			check(FunTexts.lines_for("verarscht", "frech").has(note), "nach dem Ziehen: " + note)
			check(f.take_notice() == "", "Pointe nur einmal")
			f.observe([{"e": "draw", "seat": 0, "count": 1, "reason": "zug"}], view(ME), ME)
			check(f.take_notice() == "", "ohne Tipp keine Pointe")
		show(f, view(2))
		n += 1
	check(tips >= 20 and seen.size() >= 12, "falsche Tipps kommen vor und wechseln (%d Tipps, %d Zeilen in %d Zügen)" % [tips, seen.size(), n])
	# Anteil unter den Zugsprüchen etwa 10 %; in nett nie ein Tipp
	var g := FunTexts.new()
	g.rng.seed = 31
	g.set_level("nett")
	for i in 300:
		own_turn(g)
		check(g.occasion != "tipp", "nett: kein falscher Tipp")
		show(g, view(2))
	# Wird der Zug ohne Ziehen beendet, verfällt der Tipp
	var h := FunTexts.new()
	h.rng.seed = 2024
	n = 0
	while n < 4000:
		own_turn(h)
		if h.occasion == "tipp":
			break
		show(h, view(2))
		n += 1
	check(h.occasion == "tipp", "Tipp für den Verfallstest gefunden")
	show(h, view(2))                                  # Zug vorbei, nicht gezogen
	h.observe([{"e": "draw", "seat": 0, "count": 1, "reason": "zug"}], view(ME), ME)
	check(h.take_notice() == "", "Tipp verfällt, wenn der Zug ohne Ziehen endet")


func check_luck() -> void:
	var before := view(1)
	# Glücksspiel: 3 Drücke ohne Treffer, dann aufgehört oder Hand leer
	for reason in ["stop", "empty"]:
		var f := FunTexts.new()
		f.tick(100.0)
		f.observe([{"e": "stake_discard", "seat": 0, "count": 3, "reason": reason}], before, ME)
		var t := show(f, view(1))
		check(f.occasion == "glueck" and FunTexts.lines_for("glueck", "frech").has(f.line), "Glücksspiel 3 Drücke ohne Treffer (%s): %s" % [reason, t])
	var g := FunTexts.new()
	g.tick(100.0)
	g.observe([{"e": "stake_discard", "seat": 0, "count": 2, "reason": "stop"}, {"e": "stake_discard", "seat": 1, "count": 6, "reason": "stop"}], before, ME)
	check(show(g, view(1)) == view(1).hints.text, "nur 2 Drücke oder fremdes Glück: kein Glück-Spruch")
	# Farbe mit ablegen: ab 4 mitabgelegten Karten
	var h := FunTexts.new()
	h.tick(100.0)
	h.observe([{"e": "discard_color", "seat": 0, "color": "rot", "count": 3}], before, ME)
	check(show(h, view(1)) == view(1).hints.text, "3 mitabgelegte Karten: kein Glück-Spruch")
	h.observe([{"e": "discard_color", "seat": 0, "color": "rot", "count": 4}], before, ME)
	show(h, view(1))
	check(h.occasion == "glueck", "4 mitabgelegte Karten: Glück-Spruch")
	# eigene Hand leer (Platz belegt): nur manchmal, nie bei fremden; nett bekommt nur nette Zeilen
	var hits := 0
	for i in 60:
		var k := FunTexts.new()
		k.rng.seed = 100 + i
		k.set_level("nett")
		k.tick(100.0)
		k.observe([{"e": "finish", "seat": 1, "place": 1}], before, ME)
		check(show(k, view(1)) == view(1).hints.text, "fremdes Fertigwerden: kein Glück-Spruch")
		k.observe([{"e": "finish", "seat": 0, "place": 2}], before, ME)
		if show(k, view(1)) != view(1).hints.text:
			hits += 1
			check(k.occasion == "glueck", "Fertig: Glück-Spruch")
	check(hits > 10 and hits < 50, "eigenes Fertigwerden: manchmal ein Glück-Spruch (%d/60)" % hits)
	# Pech auf mich: +5 auf meine letzte Karte und Farbjagd benutzen die Pech-Liste
	var m := FunTexts.new()
	m.tick(100.0)
	var mine := view(1)
	mine.players[0]["count"] = 1
	m.observe([{"e": "pending", "kind": "plus5", "amount": 5, "seat": 0, "by": 1}], mine, ME)
	show(m, view(1))
	check(m.occasion == "autsch_du" and FunTexts.lines_for("pech_du", "frech").has(m.line), "+5 auf meine letzte Karte: Pech-Liste (%s)" % m.line)
	var p := FunTexts.new()
	p.tick(100.0)
	p.observe([{"e": "pending", "kind": "farbjagd", "amount": 0, "seat": 0, "by": 1}, {"e": "draw", "seat": 0, "count": 9, "reason": "strafe"}], before, ME)
	show(p, view(1))
	check(p.occasion == "farbjagd_du" and FunTexts.lines_for("pech_du", "frech").has(p.line), "Farbjagd auf mich: Pech-Liste")


func check_english() -> void:
	I18n.set_language("en")
	check(FunTexts.format_line("Autsch!", "") == "Ouch!", "Englisch: Autsch → Ouch")
	var t := FunTexts.format_line("%s hat dir gerade in die Karten geguckt. Ich hab's genau gesehen.", "Kim")
	check(t.begins_with("Kim ") and not t.contains("Karten"), "Englisch mit Namen: " + t)
	var t2 := FunTexts.format_line("%s hat gerade gegähnt. Weck %s mal auf!", "Kim")
	check(t2 == "Kim just yawned. Wake Kim up!", "Englisch, Name zweimal: " + t2)
	var f := FunTexts.new()
	f.tick(100.0)
	f.observe([{"e": "pending", "kind": "plus5", "amount": 5, "seat": 1, "by": 0}], view(1), ME)
	var s := show(f, view(2))
	check(["Ouch!", "That hurt.", "So close to the finish. Ouch!", "So close to the end – that stings.", "Almost done and then this. Mean!",
		"Hehe. I mean: oh no!"].has(s), "Spruch auf Englisch: " + s)
	I18n.set_language("de")
