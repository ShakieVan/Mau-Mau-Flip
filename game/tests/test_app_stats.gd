extends SceneTree
# Beta 1.2.1: Statistik je Gerät (AppStats) – Zählen aus Ereignissen, Weitergeben nur „Partien auf diesem Gerät“, Speichern und
# Laden, kaputte Datei (Rückgriff auf .bak bzw. leer), Zurücksetzen, Satz fürs Rundenende. Dazu die Glücksspiel-Zähler je Trefferstufe,
# auch an den Ereignissen echter Bot-Partien.

var ok := 0
var failed := 0

func check(cond: bool, text: String) -> void:
	if cond:
		ok += 1
	else:
		failed += 1
		print("FAIL: ", text)

func _init() -> void:
	var path := "user://test_app_stats_%d.json" % Time.get_ticks_usec()
	var s := AppStats.new(path)
	check(s.is_empty() and s.value("partien") == 0 and not FileAccess.file_exists(path), "neu: alles 0, keine Datei")
	var changes := [0]
	s.changed.connect(func() -> void: changes[0] += 1)
	# Partie als Spieler auf Platz 1 (Übung)
	var hand7 := [1, 2, 3, 4, 5, 6, 7]
	var note := s.record([{"e": "round_start", "round": 1, "dealer": 0}, {"e": "deal"}], {"seat": 1, "hand": hand7}, "solo")
	check(note == "" and s.value("partien") == 1 and s.value("groesste_hand") == 7 and FileAccess.file_exists(path), "Partie gezählt, größte Hand, sofort gespeichert")
	s.record([{"e": "play", "seat": 1, "card": 5, "face": "hell_rot_flip"}, {"e": "flip", "side": "dunkel"},
		{"e": "play", "seat": 0, "card": 6, "face": "hell_gelb_flip"}, {"e": "swap_hands", "seat": 1, "dir": 1},
		{"e": "catch", "seat": 1, "target": 2}, {"e": "catch", "seat": 0, "target": 1}, {"e": "catch", "seat": 2, "target": 0},
		{"e": "gamble_roll", "seat": 1, "value": 0}, {"e": "gamble_roll", "seat": 1, "value": 7}, {"e": "gamble_roll", "seat": 1, "value": 3},
		{"e": "gamble_roll", "seat": 0, "value": 10}], {"seat": 1, "hand": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]}, "solo")
	check(s.value("flip") == 1 and s.value("kartentausch") == 1, "nur eigene Flips und Kartentausche")
	check(s.value("erwischt_selbst") == 1 and s.value("erwischt_worden") == 1, "Erwischt: selbst erwischt / erwischt worden")
	check(s.value("gluecksspiel_max") == 7 and s.value("groesste_hand") == 12, "Höchstwerte: Glücksspiel-Treffer (nur eigener), größte Hand")
	note = s.record([{"e": "finish", "seat": 1, "place": 1}, {"e": "round_over", "ranking": [1, 0, 2], "scores": [0, 1, 0]}], {"seat": 1, "hand": []}, "solo")
	check(s.value("mau_mau") == 1 and s.value("runden") == 1 and s.value("runden_gewonnen") == 1 and note == "Dein erster Rundensieg!", "Rundensieg mit Satz")
	check(s.value("groesste_hand") == 12, "leere Hand ändert den Höchstwert nicht")
	note = s.record([{"e": "round_over", "ranking": [{"seat": 0, "points": 5}, {"seat": 1}], "scores": [1, 1]}], {"seat": 1}, "client")
	check(note == "" and s.value("runden") == 2 and s.value("runden_gewonnen") == 1, "verlorene Runde (Ranking als Dictionary): kein Satz")
	s.record([{"e": "round_start", "round": 2}], {"seat": 1}, "client")
	check(s.value("partien") == 1, "Runde 2 ist keine neue Partie")
	note = s.record([{"e": "round_over", "ranking": [1, 0]}, {"e": "game_over", "winner": 1}], {"seat": 1}, "host")
	check(s.value("runden_gewonnen") == 2 and s.value("partien_gewonnen") == 1 and note == "Dein erster Partiesieg!", "Partiesieg geht vor Rundensieg")
	check(AppStats.round_note("runde", 12) == "Dein 12. Rundensieg!", "Satz mit Ordnungszahl")
	# Weitergeben: nur Partien auf diesem Gerät, nichts pro Mensch
	var before := s.data.duplicate()
	note = s.record([{"e": "round_start", "round": 1}, {"e": "finish", "seat": 0}, {"e": "catch", "seat": 0, "target": 1},
		{"e": "round_over", "ranking": [0, 1]}], {"seat": 0, "hand": hand7 + hand7 + hand7}, "pass")
	check(note == "" and s.value("partien_weitergeben") == 1, "Weitergeben: Partie auf diesem Gerät gezählt, kein Satz")
	before["partien_weitergeben"] = 1
	check(s.data == before, "Weitergeben: sonst nichts gezählt")
	# nichts Zählbares: kein Speichern, kein Signal
	var c0: int = changes[0]
	s.record([{"e": "turn", "seat": 0}], {"seat": 1, "hand": [1]}, "solo")
	check(changes[0] == c0, "ohne Änderung kein Speichern/Signal")
	# Laden
	var t := AppStats.new(path)
	check(t.data == s.data, "nach dem Laden gleich")
	# kaputte Hauptdatei → .bak (Vorversion), beides kaputt → leer
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{kaputt")
	f.close()
	var u := AppStats.new(path)
	check(not u.is_empty() and u.value("partien") == 1, "kaputte Datei: Vorversion aus .bak")
	f = FileAccess.open(path + ".bak", FileAccess.WRITE)
	f.store_string("[1, 2]")
	f.close()
	check(AppStats.new(path).is_empty(), "Datei und .bak kaputt: leer, kein Absturz")
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"partien": 3.0, "runden": -4, "flip": "viele", "unbekannt": 9}))
	f.close()
	var w := AppStats.new(path)
	check(w.value("partien") == 3 and w.value("runden") == 0 and w.value("flip") == 0 and not w.data.has("unbekannt"), "ungültige Werte werden 0")
	# Zurücksetzen
	check(s.reset() and s.is_empty() and AppStats.new(path).is_empty(), "Zurücksetzen speichert Nullen")
	check(s.rows().size() == AppStats.KEYS.size() and str(s.rows()[AppStats.KEYS.find("groesste_hand")][1]) == "–", "Zeilen: Höchstwert 0 als –")
	for k in AppStats.KEYS:
		check(AppStats.LABELS.has(k), "Beschriftung für " + k)
	_gamble_counters(path)
	_gamble_real_games(path)
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	print("RESULT: %d ok, %d failed" % [ok, failed])
	quit(1 if failed > 0 else 0)


func _gamble_counters(path: String) -> void:
	var s := AppStats.new(path)
	s.reset()
	var medium := {"seat": 1, "rules": {"gamble_max": 5}}
	var key := AppStats.gamble_key
	# Erster Druck 0, dann weiter bis zum Treffer; auch der Zug eines Mitspielers zählt, in getrennten Lieferungen
	s.record([{"e": "gamble_start", "seat": 0}], medium, "host")
	check(s.value(key.call(5, "spiele")) == 0, "Glücksspiel: Zählt erst beim Druck")
	s.record([{"e": "gamble_roll", "seat": 0, "value": 0}], medium, "host")
	s.record([{"e": "gamble_roll", "seat": 0, "value": 4}], medium, "host")
	s.record([{"e": "gamble_start", "seat": 1}, {"e": "gamble_roll", "seat": 1, "value": 7}], medium, "solo")
	check(s.value(key.call(5, "spiele")) == 2 and s.value(key.call(5, "spiele0")) == 1, "Glücksspiel: nur der erste Druck je Spiel")
	check(s.value(key.call(5, "drucke")) == 3 and s.value(key.call(5, "drucke0")) == 1, "Glücksspiel: alle Drucke")
	check(s.value("gluecksspiel_max") == 7, "Höchster Treffer zählt weiter nur den eigenen")
	# Gast und Weitergeben würfeln nicht auf diesem Gerät bzw. zählen nur Partien; ohne Start zählt kein erster Druck
	var before := s.data.duplicate()
	s.record([{"e": "gamble_start", "seat": 0}, {"e": "gamble_roll", "seat": 0, "value": 0}], medium, "client")
	s.record([{"e": "gamble_start", "seat": 0}, {"e": "gamble_roll", "seat": 0, "value": 0}], medium, "pass")
	check(s.data == before, "Glücksspiel: Gast und Weitergeben zählen nicht")
	s.record([{"e": "gamble_roll", "seat": 0, "value": 0}], medium, "host")
	check(s.value(key.call(5, "spiele")) == 2 and s.value(key.call(5, "drucke")) == 4, "Fortgesetztes Glücksspiel: nur bei den Drucken")
	# Obergrenzen getrennt; Stufe eines älteren Stands = deren Obergrenze, ohne Angabe oder ungültig bis 1:10
	s.record([{"e": "gamble_start"}, {"e": "gamble_roll", "value": 2}], {"seat": 1, "rules": {"gamble_max": 3}}, "host")
	s.record([{"e": "gamble_start"}, {"e": "gamble_roll", "value": 0}], {"seat": 1, "rules": {}}, "host")
	s.record([{"e": "gamble_start"}, {"e": "gamble_roll", "value": 0}], {"seat": 1, "rules": {"gamble_odds": "kaputt"}}, "host")
	s.record([{"e": "gamble_start"}, {"e": "gamble_roll", "value": 3}], {"seat": 1, "rules": {"gamble_max": 7}}, "host")
	s.record([{"e": "gamble_start"}, {"e": "gamble_roll", "value": 0}], {"seat": 1, "rules": {"gamble_odds": "often"}}, "host")
	check(s.value(key.call(3, "spiele")) == 2 and s.value(key.call(3, "spiele0")) == 1 and s.value(key.call(10, "spiele0")) == 2
		and s.value(key.call(7, "spiele")) == 1 and s.value(key.call(7, "spiele0")) == 0, "Obergrenzen getrennt")
	# Zeilen (aufsteigend wie der Regler), Erwartung, Laden, Zurücksetzen
	var rows := s.gamble_rows()
	check(rows.size() == 8 and s.rows().size() == AppStats.KEYS.size() + 8, "je Obergrenze zwei Zeilen (%d)" % rows.size())
	check(str(rows[0][0]) == "Glücksspiel bis 1:3: 0 beim ersten Druck (erwartet 39 %)" and str(rows[0][1]) == "1 von 2 · 50 %", "Zeile: %s" % str(rows[0]))
	check(str(rows[2][0]) == "Glücksspiel bis 1:5: 0 beim ersten Druck (erwartet 54 %)" and str(rows[2][1]) == "1 von 2 · 50 %", "Zeile: %s" % str(rows[2]))
	check(str(rows[3][0]) == "Glücksspiel bis 1:5: 0 bei allen Drucken" and str(rows[3][1]) == "2 von 4 · 50 %", "Zeile: %s" % str(rows[3]))
	check(str(rows[4][0]) == "Glücksspiel bis 1:7: 0 beim ersten Druck (erwartet 63 %)" and str(rows[6][0]).begins_with("Glücksspiel bis 1:10:"), "Zeilen 1:7 und 1:10")
	check(AppStats.new(path).data == s.data, "Glücksspiel-Zähler nach dem Laden gleich")
	check(s.reset() and s.gamble_rows().is_empty() and s.is_empty(), "Zurücksetzen löscht die Glücksspiel-Zähler")
	# Stand 1.6.18 (Zähler je Stufe gs_rare_… / gs_medium_… / gs_often_…): Laden übernimmt sie zu 1:10 / 1:5 / 1:3, Speichern ohne sie
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "partien": 4, "gs_rare_spiele": 12, "gs_rare_spiele0": 9, "gs_medium_spiele": 5,
		"gs_medium_drucke": 8, "gs_medium_drucke0": 3, "gs_often_spiele0": 2, "gs_often_spiele": 6, "gs_kaputt_spiele": 99}))
	f.close()
	var legacy := AppStats.new(path)
	check(legacy.value("partien") == 4 and legacy.value(key.call(10, "spiele")) == 12 and legacy.value(key.call(10, "spiele0")) == 9
		and legacy.value(key.call(5, "spiele")) == 5 and legacy.value(key.call(5, "drucke0")) == 3 and legacy.value(key.call(3, "spiele")) == 6
		and not legacy.data.has("gs_rare_spiele"), "Zähler von 1.6.18 übernommen")
	check(legacy.gamble_rows().size() == 4, "Zeilen aus übernommenen Zählern (%d)" % legacy.gamble_rows().size())


# Echte Partien mit Bots: Die Zähler stimmen mit den Ereignissen überein, und der Anteil der 0 beim ersten Druck liegt beim erwarteten Wert
func _gamble_real_games(path: String) -> void:
	var cfg := RuleConfig.preset("familie")
	check(cfg.gamble_max == 6, "Familie spielt bis 1:6")
	var s := AppStats.new(path)
	s.reset()
	var starts := 0
	var rolls := 0
	var zeros := 0
	for i in 250:
		var g := MauGame.create(cfg, RulesFixture.players(3 + i % 4, "bot"), 7_700_017 * i + 3)
		g.start_round()
		var rng := RandomNumberGenerator.new()
		rng.seed = 104_729 * i + 5
		for step in 5000:
			if not g.state in MauGame.PLAY_PHASES:
				break
			var seat := g.current_seat()
			var res := g.apply(seat, MauBot.choose(g.view_for(seat), rng.randi(), 2))
			check(bool(res.ok), "Bot-Aktion angenommen")
			if not bool(res.ok):
				return
			for e in res.events:
				if str(e.e) == "gamble_start":
					starts += 1
				elif str(e.e) == "gamble_roll":
					rolls += 1
					zeros += 1 if int(e.value) == 0 else 0
			s.record(res.events, g.view_for(seat), "host")
	var games := s.value(AppStats.gamble_key(6, "spiele"))
	var first_zero := s.value(AppStats.gamble_key(6, "spiele0"))
	check(starts > 200 and games > 200 and games <= starts, "Glücksspiele gezählt (%d von %d Starts)" % [games, starts])
	check(s.value(AppStats.gamble_key(6, "drucke")) == rolls and s.value(AppStats.gamble_key(6, "drucke0")) == zeros, "alle Drucke wie in den Ereignissen")
	check(s.value(AppStats.gamble_key(10, "drucke")) == 0 and s.value(AppStats.gamble_key(3, "drucke")) == 0, "andere Obergrenzen bleiben leer")
	var share := 100.0 * first_zero / maxf(games, 1)
	check(absf(share - RuleConfig.gamble_zero_percent(6)) < 8.0, "0 beim ersten Druck: %.1f %% (erwartet %d %%)" % [share, RuleConfig.gamble_zero_percent(6)])
	print("Echte Partien: %d Glücksspiele, 0 beim ersten Druck %.1f %%, %d Drucke" % [games, share, rolls])
