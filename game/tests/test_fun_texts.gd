extends SceneTree
# Beta 1.4.4: Freche Sprüche (FunTexts) – Auswahl je Stufe, Häufigkeit und Abklingzeit, nie bei wichtigen Hinweisen, nie hinter dem
# Sichtschutz, Trödeln, Ereignisse (Richtungswechsel, Autsch, Pechsträhne, Farbjagd), falscher Tipp mit Pointe, Platzhalter,
# beide Sprachen (game/i18n/en_fun.po).

var ok := 0
var failed := 0

const ME := 0
const STD := "Du bist dran – lege Rot oder 7."
const NF := "Du bist dran – nichts passt, zieh eine Karte."


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
	check_freq_levels()
	check_immer()
	check_important()
	check_blocked_and_time()
	check_slow()
	check_events()
	check_fake_tip()
	check_luck()
	check_nothing_fits()
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
	check(FunTexts.clean_freq("quatsch") == "oft" and FunTexts.clean_freq("immer") == "immer" and FunTexts.FREQ_DEFAULT == "oft", "Häufigkeit bereinigt, ab Werk oft")
	check(AppSettings.defaults().get(FunTexts.FREQ_SETTING) == "oft" and AppSettings.sanitize(FunTexts.FREQ_SETTING, "dauernd") == null
		and AppSettings.sanitize(FunTexts.FREQ_SETTING, 3) == null, "Einstellung sprueche_oft: Standard oft, ungültige Werte abgelehnt")
	for fq in FunTexts.FREQS:
		check(AppSettings.sanitize(FunTexts.FREQ_SETTING, fq) == fq, "Einstellung sprueche_oft: gültig " + fq)
		check(FunTexts.FREQ_TURN.has(fq) and FunTexts.FREQ_COOLDOWN.has(fq) and FunTexts.FREQ_RARE.has(fq), "Häufigkeit mit allen Größen: " + fq)
	check(AppSettings.SPRUECHE_OFT == FunTexts.FREQS and FunTexts.FREQ_NAMES.size() == FunTexts.FREQS.size(), "Häufigkeitsstufen in Einstellungen und FunTexts gleich")
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
	for k in ["Sprüche", "Nett", "Frech", "Häufigkeit", "Selten", "Oft", "Immer", "Immer: jeder Zug bekommt einen Spruch, der bleibt stehen."]:
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
	# frech/nett: bei „normal“ ~35 % der Züge mit 7 Karten; nett nie eine freche Zeile
	for lvl in ["frech", "nett"]:
		var f := FunTexts.new()
		f.rng.seed = 4711
		f.set_level(lvl)
		f.set_freq("normal")
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
		check(hits > 110 and hits < 175, "%s: bei normal etwa jeder dritte Zug ein Spruch (%d/400)" % [lvl, hits])
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
	f3.set_freq("selten")
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


# Beta 1.4.5: Häufigkeit je Stufe (statistisch) – selten < normal < oft < immer, jede Stufe im erwarteten Bereich
func check_freq_levels() -> void:
	var bounds := {"selten": [35, 90], "normal": [110, 175], "oft": [225, 295], "immer": [400, 400]}
	var prev := -1
	for fq in FunTexts.FREQS:
		var f := FunTexts.new()
		f.rng.seed = 808
		f.set_level("nett")
		f.set_freq(fq)
		var hits := 0
		for i in 400:
			f.tick(45.0)
			show(f, view(2))
			if show(f, view(ME)) != STD:
				hits += 1
			show(f, view(2))
		check(hits >= int(bounds[fq][0]) and hits <= int(bounds[fq][1]), "Häufigkeit %s: Sprüche in %d von 400 eigenen Zügen" % [fq, hits])
		check(hits > prev, "Häufigkeit %s häufiger als die Stufe davor" % fq)
		prev = hits
	# seltene Anlässe: Richtungswechsel (Grundwert 0,6) je Stufe
	var rev := {}
	for fq in FunTexts.FREQS:
		var hits := 0
		for i in 300:
			var r := FunTexts.new()
			r.rng.seed = 5000 + i
			r.set_level("nett")
			r.set_freq(fq)
			r.tick(100.0)
			r.observe([{"e": "reverse", "dir": -1, "seat": 1}], view(1), ME)
			if show(r, view(2)) != view(2).hints.text:
				hits += 1
		rev[fq] = hits
	check(rev.selten > 75 and rev.selten < 145 and rev.normal > 150 and rev.normal < 210 and rev.oft > 260 and rev.oft < 300 and rev.immer == 300,
		"Richtungswechsel je Stufe: ×0,6 / 0,6 / ≈0,95 / immer (%s)" % str(rev))
	check(is_equal_approx(FunTexts.new().rare(0.6), 0.95) and is_equal_approx(FunTexts.new().rare(0.4), 0.72), "oft: seltene Anlässe ×1,8, höchstens 0,95")
	# viele/wenige Karten kommen bei „immer“ jedes Mal
	var g := FunTexts.new()
	g.set_freq("immer")
	for i in 20:
		g.tick(1.0)
		show(g, view(2))
		show(g, view(ME, 14))
		check(g.occasion == "viele", "immer: ab 12 Karten jedes Mal ein Spruch über viele Karten")
		show(g, view(2))
		show(g, view(ME, 3))
		check(g.occasion == "wenige", "immer: bei 2–3 Karten jedes Mal ein Spruch über wenige Karten")
		show(g, view(2))
	# Abklingzeit je Stufe: direkt nach einem Spruch erst nach der Pause wieder einer
	for fq in ["selten", "normal", "oft"]:
		var h := FunTexts.new()
		h.set_freq(fq)
		h.set_level("nett")
		h.rng.seed = 12
		var n := 0
		while own_turn(h) == STD and n < 500:
			n += 1
			show(h, view(2))
		show(h, view(2))                                  # Spruch endet mit dem Zugwechsel
		var cd: float = FunTexts.FREQ_COOLDOWN[fq]
		h.tick(cd - 1.0)
		var early := show(h, view(ME)) != STD
		check(not early, "Häufigkeit %s: innerhalb der Abklingzeit (%.0f s) kein Spruch" % [fq, cd])


# Beta 1.4.5: „immer“ ersetzt den Standardtext und lässt den Spruch stehen
func check_immer() -> void:
	var f := FunTexts.new()
	f.set_freq("immer")
	f.set_level("nett")
	f.rng.seed = 77
	# jeder eigene Zug bekommt einen Spruch, nie der Standardtext
	for i in 40:
		f.tick(0.2)
		show(f, view(1))
		var t := show(f, view(ME))
		check(t != STD and f.showing() and f.occasion == "zug", "immer: eigener Zug bekommt einen Spruch (%s)" % t)
	# bleibt stehen: weit über SHOW_TIME hinaus bis zum Trödel-Anlass, danach wieder ein Spruch statt Standardtext
	f.tick(5.0)
	show(f, view(1))
	var first := show(f, view(ME))
	var stays := true
	for i in 12:
		f.tick(1.0)
		if show(f, view(ME)) != first:
			stays = false
	check(stays and f.showing() and f.occasion == "zug", "immer: der Spruch bleibt über SHOW_TIME (%.0f s) hinaus stehen" % FunTexts.SHOW_TIME)
	var kept := true
	for i in 200:
		f.tick(1.0)
		if show(f, view(ME)) == STD:
			kept = false
	check(kept, "immer: auch nach Minuten kein Zurückfallen auf „Du bist dran“")
	check(f.occasion == "langsam", "immer: Trödel-Spruch löste den Zugspruch ab")
	# Kommentare für den Mitmenschen: nach 25 s
	var o := FunTexts.new()
	o.set_freq("immer")
	o.tick(100.0)
	show(o, view(ME))
	show(o, view(1))
	o.tick(FunTexts.SLOW_OTHER + 0.5)
	var ot := show(o, view(1))
	check(o.occasion == "langsam_andere" and ot.contains("Kim"), "immer: Kommentar über trödelnden Mitspieler nach 25 s: " + ot)
	# Ereignis löst den stehenden Spruch ab (frühestens nach IMMER_MIN_SHOW), vorher nicht
	var e := FunTexts.new()
	e.set_freq("immer")
	e.set_level("nett")
	e.rng.seed = 3
	e.tick(10.0)
	show(e, view(1))
	var zug := show(e, view(ME))
	check(e.occasion == "zug", "immer: Zugspruch steht")
	var mine := view(ME)
	mine.players[0]["count"] = 1
	e.observe([{"e": "pending", "kind": "plus5", "amount": 5, "seat": 0, "by": 1}], mine, ME)
	check(show(e, view(ME)) == zug, "immer: neuer Anlass löst den Spruch nicht sofort ab")
	check(e.tick(FunTexts.IMMER_MIN_SHOW + 0.1), "immer: Hinweisleiste wird für den neuen Anlass neu aufgebaut")
	var ev := show(e, view(ME))
	check(e.occasion == "autsch_du" and ev != zug and ev != STD, "immer: Ereignis (Autsch) löst den Zugspruch ab: " + ev)
	# wichtige Hinweise werden nie ersetzt
	var imp := view(ME, 2, "Du bist dran – lege Rot oder 7. Denk an „Mau!“")
	check(show(e, imp) == imp.hints.text and not e.showing(), "immer: Mau-Pflicht verdrängt den Spruch")
	for t in ["Wünscher +2 auf dich – Zieh 2.", "Drück den Glücksspielknopf!"]:
		var w := view(ME, 7, t)
		check(show(e, w) == t and not e.showing(), "immer: wichtiger Hinweis bleibt: " + t)
	var col := view(ME, 7, "Nach dem Flip liegt ein Joker oben – wähle die neue Farbe.", "color")
	col.hints["need_color"] = true
	check(show(e, col) == col.hints.text, "immer: Farbwahl bleibt")
	var pen := view(ME)
	pen.pending = {"kind": "plus5", "amount": 5}
	check(show(e, pen) == pen.hints.text, "immer: offene Strafe bleibt")
	check(e.hint_for(view(ME), view(ME).hints, ME, STD, true) == STD, "immer: Weitergeben-Sichtschutz zeigt nie einen Spruch")
	# Aus bleibt aus, auch bei „immer“
	var off := FunTexts.new()
	off.set_freq("immer")
	off.set_level("aus")
	var all_std := true
	for i in 30:
		off.tick(50.0)
		show(off, view(1))
		if show(off, view(ME)) != STD:
			all_std = false
	check(all_std, "Sprüche aus: auch bei Häufigkeit immer nur Standardtexte")
	# Wiederholungssperre: 20 Sprüche je Anlass, 20 Züge hintereinander lauter verschiedene, nie zwei gleiche direkt nacheinander
	var r := FunTexts.new()
	r.set_freq("immer")
	r.set_level("nett")
	r.rng.seed = 99
	var seen := {}
	var last := ""
	var same_in_row := 0
	for i in 200:
		r.tick(1.0)
		show(r, view(1))
		show(r, view(ME))
		if i < 20:
			seen[r.line] = true
		if r.line == last:
			same_in_row += 1
		last = r.line
	check(seen.size() == 20, "immer: 20 Züge, 20 verschiedene Zugsprüche (%d)" % seen.size())
	check(same_in_row == 0, "immer: nie zweimal derselbe Spruch direkt hintereinander (%d)" % same_in_row)
	# Alias teilt die Tüte: Pech auf dich und Farbjagd auf dich wiederholen sich nicht
	var p := FunTexts.new()
	p.set_freq("immer")
	p.rng.seed = 4
	var pick_seen := {}
	for i in 20:
		p.tick(3.0)
		p.observe([{"e": "pending", "kind": "plus5", "amount": 5, "seat": 0, "by": 1}], mine, ME)
		show(p, view(1))
		pick_seen[p.line] = true
	check(pick_seen.size() == 20, "immer: Pech-Sprüche (Alias) 20 verschiedene (%d)" % pick_seen.size())
	# Wechsel der Häufigkeit beendet einen stehenden Spruch
	var wf := FunTexts.new()
	wf.set_freq("immer")
	wf.tick(10.0)
	show(wf, view(1))
	show(wf, view(ME))
	check(wf.showing(), "Spruch steht vor dem Wechsel")
	wf.set_freq("selten")
	check(not wf.showing() and show(wf, view(ME)) == STD, "Häufigkeit gewechselt: Spruch endet, Standardtext")


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
		r.set_freq("normal")
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
		k.set_freq("normal")
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


# Beta 1.4.6: Anlass „nichts passt“ – ersetzt nur den reinen Hinweis „nichts passt, zieh eine Karte“ (Häufigkeit wie der Zug-Anlass)
func check_nothing_fits() -> void:
	var lines := FunTexts.lines_for("nichts_passt", "frech")
	check(lines.size() == 40 and FunTexts.lines_for("nichts_passt", "nett").size() == 35 and FunTexts.lines_for("nichts_passt", "aus").is_empty(),
		"nichts_passt: 40 Sprüche (35 davon nett, 5 frech)")
	for l in lines:
		check(l.contains("ieh") or l.contains("Stapel") or l.contains("Nachschub"), "Spruch nennt das Ziehen: " + l)
	var vw := view(ME, 7, NF)
	check(FunTexts.nothing_fits(vw, vw.hints, ME) and not FunTexts.nothing_fits(vw, vw.hints, -1) and not FunTexts.nothing_fits(view(1), view(1).hints, ME),
		"nothing_fits: nur im eigenen Zug mit dem reinen Hinweis")
	# Immer: jeder Nichts-passt-Zug bekommt einen Spruch aus dem Anlass, alle 40 der Reihe nach verschieden, nie der Zug-/Tipp-Anlass
	var f := FunTexts.new()
	f.set_freq("immer")
	f.rng.seed = 5
	var seen := {}
	var bad := 0
	for i in 40:
		f.tick(0.2)
		show(f, view(1))
		var t := show(f, view(ME, 7, NF))
		if t == NF or not f.showing() or f.occasion != "nichts_passt" or not lines.has(f.line) or t != I18n.t(f.line):
			bad += 1
		seen[f.line] = true
	check(bad == 0, "immer: jeder Nichts-passt-Zug bekommt einen nichts_passt-Spruch (%d Ausnahmen)" % bad)
	check(seen.size() == 40, "immer: 40 Züge, 40 verschiedene Sprüche (%d)" % seen.size())
	# kein falscher Tipp, keine Pointe nach dem Ziehen
	f.observe([{"e": "draw", "seat": 0, "reason": "zug", "count": 1}], view(ME), ME)
	check(f.take_notice() == "", "nichts_passt löst keine „verarscht“-Pointe aus")
	# der Spruch endet, sobald der Hinweis nicht mehr der reine Nichts-passt-Fall ist; bleibt sonst stehen
	f.tick(30.0)
	show(f, view(1))
	var s1 := show(f, view(ME, 7, NF))
	check(f.occasion == "nichts_passt" and show(f, view(ME, 7, NF)) == s1, "Spruch steht über wiederholte Ansichten")
	check(show(f, view(ME)) == STD and not f.showing(), "anderer Hinweis im selben Zug: Spruch endet")
	# Strafen, Ziehpflicht, Mau-Zusatz, leere Stapel, Farbwahl, Auswahl, Erwischen: Hinweis bleibt unersetzt
	var imp := FunTexts.new()
	imp.set_freq("immer")
	for t in ["Wünscher +2 auf dich – Zieh 2.", "+5 auf dich – Zieh 5.", "Farbjagd auf dich – Zieh, bis Rot kommt.",
			"Du bist dran – nichts passt und beide Stapel sind leer: aussetzen.", "Du bist dran – nichts passt, zieh eine Karte. Denk an „Mau!“"]:
		imp.tick(40.0)
		show(imp, view(1))
		var w := view(ME, 7, t)
		check(show(imp, w) == t and not imp.showing(), "immer: bleibt unersetzt: " + t)
	var pen := view(ME, 7, NF)
	pen.pending = {"kind": "plus5", "amount": 5}
	imp.tick(40.0)
	show(imp, view(1))
	check(show(imp, pen) == NF and not imp.showing(), "offene Strafe: Hinweis bleibt")
	var col := view(ME, 7, NF)
	col.hints["need_color"] = true
	check(show(imp, col) == NF and not imp.showing(), "Farbwahl: Hinweis bleibt")
	var cat := view(ME, 7, NF)
	cat.hints["catch"] = [1]
	check(show(imp, cat) == NF and not imp.showing(), "Erwischen offen: Hinweis bleibt")
	var dpv := view(ME, 7, NF)
	dpv["discard_pick"] = {"seat": 0, "color": "rot"}
	check(show(imp, dpv) == NF and not imp.showing(), "Ablege-Auswahl: Hinweis bleibt")
	check(imp.hint_for(view(ME, 7, NF), view(ME, 7, NF).hints, ME, NF, true) == NF, "Weitergeben-Sichtschutz: nie ein Spruch")
	# Aus und ohne „Spielbare Karten hervorheben“: nie (der Spruch würde „nichts passt“ verraten)
	var off := FunTexts.new()
	off.set_freq("immer")
	off.set_level("aus")
	off.tick(40.0)
	show(off, view(1))
	check(show(off, view(ME, 7, NF)) == NF and not off.showing(), "Sprüche aus: Hinweis bleibt")
	var nohl := FunTexts.new()
	nohl.set_freq("immer")
	nohl.nothing_ok = false
	nohl.tick(40.0)
	show(nohl, view(1))
	check(show(nohl, view(ME, 7, NF)) == NF and not nohl.showing(), "Hervorheben aus: Hinweis bleibt")
	# Stufe nett: keine frechen Zeilen (alle 35 kommen, kein (F))
	var nt := FunTexts.new()
	nt.set_freq("immer")
	nt.set_level("nett")
	nt.rng.seed = 8
	var nett_seen := {}
	for i in 35:
		nt.tick(0.2)
		show(nt, view(1))
		show(nt, view(ME, 7, NF))
		nett_seen[nt.line] = true
	var nett_lines := FunTexts.lines_for("nichts_passt", "nett")
	check(nett_seen.size() == 35 and nett_seen.keys().all(func(l: Variant) -> bool: return nett_lines.has(l)), "nett: 35 Sprüche ohne die frechen")
	# Häufigkeit wie der Zug-Anlass (oft: 65 %), selten < normal < oft
	var rate := {}
	for fq in ["selten", "normal", "oft"]:
		var g := FunTexts.new()
		g.set_freq(fq)
		g.rng.seed = 21
		var hits := 0
		for i in 600:
			g.tick(10.0)
			g.tick(50.0)             # erst endet der letzte Spruch, dann vergeht die Abklingzeit
			show(g, view(1))
			show(g, view(ME, 7, NF))
			if g.showing():
				hits += 1
		rate[fq] = float(hits) / 600.0
	check(rate.selten < rate.normal and rate.normal < rate.oft, "Häufigkeit steigt: %s" % str(rate))
	check(absf(rate.oft - FunTexts.FREQ_TURN["oft"]) < 0.08 and absf(rate.normal - FunTexts.FREQ_TURN["normal"]) < 0.08, "Wahrscheinlichkeit wie beim Zug-Anlass (%s)" % str(rate))
	# Englisch
	I18n.set_language("en")
	var en := FunTexts.new()
	en.set_freq("immer")
	en.tick(40.0)
	show(en, view(1))
	var et := show(en, view(ME, 7, NF))
	check(en.occasion == "nichts_passt" and et != en.line and et.length() > 5, "Englisch: übersetzter Spruch (%s)" % et)
	I18n.set_language("de")
