extends SceneTree
# Beta 1.2.1: Statistik je Gerät (AppStats) – Zählen aus Ereignissen, Weitergeben nur „Partien auf diesem Gerät“, Speichern und
# Laden, kaputte Datei (Rückgriff auf .bak bzw. leer), Zurücksetzen, Satz fürs Rundenende.

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
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	print("RESULT: %d ok, %d failed" % [ok, failed])
	quit(1 if failed > 0 else 0)
