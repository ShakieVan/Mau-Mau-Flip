extends SceneTree
# Gespeicherte Regelsätze und Regeln des letzten Gastgebers (RuleSets, AppSettings "regelsaetze" / "regeln_gastgeber"), ohne
# Oberfläche und mit eigener Einstellungsdatei: Speichern, Laden, Überschreiben (Groß-/Kleinschreibung egal), Löschen, Grenze 12,
# Namen (Zeichen wie Spielernamen, höchstens 20), Rundreise über die Datei (JSON-Zahlen), kaputte Daten (keine Liste, fehlende
# Namen, unbekannte Optionen, ungültige Werte, Doppelte, zu viele), Erkennung des passenden Satzes (ohne Kartentausch zählt die
# Tauschrichtung nicht), Gastgeber-Platz (ein Platz, schreibt nur bei Änderung, zählt nicht zu den 12; leere Regeln weder beim
# Merken noch beim Laden), Namensvorschläge, zuletzt gewählter Satz („regelsatz_gewaehlt“: Doppelte zeigen überall denselben
# Namen), Schreibfehler (Datei nicht schreibbar: Meldung, Stand im Speicher unverändert). Die Rundreise nutzt Kartentausch in
# Spielrichtung (swap_direction = "play"), damit auch der Nicht-Standardwert der Tauschrichtung die Datei übersteht.
#   godot_run.ps1 -Script res://tests/test_rule_sets.gd -Headless

var ok := 0
var failed := 0


func check(cond: bool, text: String) -> void:
	if cond:
		ok += 1
	else:
		failed += 1
		print("FAIL: ", text)


func _init() -> void:
	var path := "user://test_rule_sets_%d.json" % Time.get_ticks_usec()
	var st := AppSettings.new(path)
	check(st.get_value("regelsaetze") == [] and st.get_value("regeln_gastgeber") == {} and RuleSets.list(st).is_empty()
		and RuleSets.host_slot(st).is_empty() and RuleSets.host_config(st) == null, "Standard: keine Sätze, kein Gastgeber")
	names_and_suggestions()
	save_load(st, path)
	limit(st)
	broken(path)
	recognition(st)
	host_slot(st, path)
	chosen(path)
	write_errors()
	migration_013(path)
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(path + suffix)
		DirAccess.remove_absolute(path + ".kaputt" + suffix)
	print("RESULT: %d ok" % ok if failed == 0 else "RESULT: %d ok, %d FAIL" % [ok, failed])
	quit(1 if failed > 0 else 0)


func house() -> RuleConfig:
	var cfg := RuleConfig.preset("familie")
	cfg.gamble_cards = "on"
	cfg.discard_color = "on"
	cfg.hand_size = 9
	cfg.target = 1200
	cfg.swap_direction = "play"          # Familie hat Kartentausch: die Richtung zählt und muss die Rundreise überstehen
	return cfg


func names_and_suggestions() -> void:
	check(RuleSets.clean_name("  Oma  &  Opa (Urlaub)  ") == "Oma & Opa (Urlaub)", "Name: Leerzeichen, & und Klammern (%s)" % RuleSets.clean_name("  Oma  &  Opa (Urlaub)  "))
	check(RuleSets.clean_name("[b]Fett[/b] 100%") == "bFettb 100", "Name: keine Klammern für BBCode, kein %")
	check(RuleSets.clean_name("Abcdefghij Klmnopqrstuvwxyz") == "Abcdefghij Klmnopqrs" and RuleSets.clean_name("Abcdefghij Klmnopqrstuvwxyz").length() == RuleSets.NAME_MAX,
		"Name: höchstens 20 Zeichen")
	check(RuleSets.clean_name("😀") == "" and RuleSets.clean_name("   ") == "", "Name: nur unerlaubte Zeichen = leer")
	check(RuleSets.filter_name("Jörg Müller-Äß ") == "Jörg Müller-Äß " and RuleSets.filter_name("x".repeat(30)).length() == 20, "Filter beim Tippen")
	check(RuleSets.suggestion_for_host("Lena") == "Regeln von Lena", "Vorschlag: Regeln von Lena")
	check(RuleSets.suggestion_for_host("Gastgeberin") == "Von Gastgeberin", "Vorschlag bei langem Namen: Von … (%s)" % RuleSets.suggestion_for_host("Gastgeberin"))
	check(RuleSets.suggestion_for_host("Abcdefghijklmnopqr").length() <= 20 and RuleSets.suggestion_for_host("") == "Regeln vom Gastgeber", "Vorschlag: gekürzt bzw. ohne Namen")
	check(RuleSets.host_title("Lena") == "Zuletzt gespielt bei Lena", "Bezeichnung des Gastgeber-Platzes")


func save_load(st: AppSettings, path: String) -> void:
	var a := house()
	check(RuleSets.save("  Oma-Regeln ", a, st) == RuleSets.OK_SAVED and RuleSets.names(st) == ["Oma-Regeln"], "Speichern mit bereinigtem Namen")
	check(RuleSets.save("  ", a, st) == RuleSets.ERR_NAME and RuleSets.save("😀", a, st) == RuleSets.ERR_NAME and RuleSets.count(st) == 1, "leerer Name abgelehnt")
	var b := RuleConfig.preset("klassisch500")
	b.target = 300
	RuleSets.save("Kneipe", b, st)
	check(RuleSets.names(st) == ["Oma-Regeln", "Kneipe"], "neue Sätze hinten")
	check(RuleSets.config("oma-regeln", st) != null and RuleSets.config("OMA-REGELN", st).equals(a), "Laden: Name ohne Rücksicht auf Groß-/Kleinschreibung, gleiche Regeln")
	check(RuleSets.config("Gibt es nicht", st) == null and RuleSets.index_of("", st) == -1, "unbekannter Satz = null")
	# Rundreise über die Datei: JSON-Zahlen kommen als float, die Sätze wieder mit int
	var again := AppSettings.new(path)
	var loaded := RuleSets.config("Oma-Regeln", again)
	check(loaded != null and loaded.equals(a) and loaded.hand_size == 9 and loaded.target == 1200 and loaded.gamble_cards == "on", "Rundreise: Regeln gleich")
	check(loaded != null and loaded.swap_cards == "on" and loaded.swap_direction == "play" and RuleSets.matches("Oma-Regeln", a, again),
		"Rundreise: Kartentausch in Spielrichtung bleibt erhalten")
	var raw: Dictionary = (again.get_value("regelsaetze")[0] as Dictionary).regeln
	check(typeof(raw.hand_size) == TYPE_INT and raw.size() == RuleConfig.keys().size(), "Rundreise: Zahlen als int, alle Optionen")
	# Überschreiben: gleicher Platz, neue Schreibweise
	check(not RuleSets.would_overwrite("oma-regeln", a, st) and RuleSets.would_overwrite("oma-regeln", b, st), "would_overwrite nur bei anderen Regeln")
	check(RuleSets.save("OMA-regeln", b, st) == RuleSets.OK_SAVED and RuleSets.names(st) == ["OMA-regeln", "Kneipe"] and RuleSets.config("Oma-Regeln", st).equals(b),
		"Überschreiben: gleicher Platz, neue Schreibweise, neue Regeln")
	check(RuleSets.stored_name("oma-REGELN", st) == "OMA-regeln", "gespeicherte Schreibweise")
	RuleSets.save("Oma-Regeln", a, st)
	# Löschen
	check(RuleSets.remove("kneipe", st) and RuleSets.names(st) == ["Oma-Regeln"] and not RuleSets.remove("kneipe", st), "Löschen")
	check(AppSettings.new(path).get_value("regelsaetze").size() == 1, "Löschen gespeichert")
	# Gelesene Liste ist eine Kopie
	var l := RuleSets.list(st)
	(l[0] as Dictionary).name = "Verändert"
	check(RuleSets.names(st) == ["Oma-Regeln"], "list() liefert eine Kopie")


func limit(st: AppSettings) -> void:
	for i in range(RuleSets.count(st), RuleSets.MAX):
		var c := RuleConfig.new()
		c.hand_size = 5 + (i % 6)
		check(RuleSets.save("Satz %d" % i, c, st) == RuleSets.OK_SAVED, "Satz %d gespeichert" % i)
	check(RuleSets.count(st) == RuleSets.MAX, "12 Sätze")
	check(RuleSets.save("Dreizehn", RuleConfig.new(), st) == RuleSets.ERR_FULL and not RuleSets.has_set("Dreizehn", st), "13. Satz abgelehnt")
	var c := RuleConfig.new()
	c.mau_penalty = 4
	check(RuleSets.save("satz 3", c, st) == RuleSets.OK_SAVED and RuleSets.config("Satz 3", st).mau_penalty == 4 and RuleSets.count(st) == RuleSets.MAX,
		"bei 12 Sätzen: Überschreiben geht")
	check(RuleSets.remove("Satz 3", st) and RuleSets.save("Dreizehn", RuleConfig.new(), st) == RuleSets.OK_SAVED, "nach dem Löschen wieder Platz")
	# zurück auf einen Satz für die folgenden Prüfungen
	for n in RuleSets.names(st):
		if n != "Oma-Regeln":
			RuleSets.remove(n, st)
	check(RuleSets.names(st) == ["Oma-Regeln"], "aufgeräumt")


func broken(path: String) -> void:
	var p := path + ".kaputt"
	var many := []
	for i in 15:
		many.append({"name": "S%d" % i, "regeln": {}})
	var entries := [
		{"name": "Gut", "regeln": {"round_end": "last", "hand_size": 8.0, "unbekannt": 5, "stacking": "quatsch", "target": 99999, "backs_visible": 0}},
		{"name": "gut", "regeln": {}},                  # doppelt (Groß-/Kleinschreibung)
		{"name": "", "regeln": {}},                     # ohne Namen
		{"name": 7, "regeln": {}},                      # Name keine Zeichenkette
		{"name": "Ohne Regeln"},
		{"name": "Regeln falsch", "regeln": [1, 2]},
		"kein Eintrag",
		{"name": "Zweiter", "regeln": {"swap_cards": "on"}},
	]
	entries.append_array(many)
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "regelsaetze": entries, "regeln_gastgeber": {"host": "<Lena>\n", "regeln": {"mau_call": "off", "x": 1}}}))
	f.close()
	var st := AppSettings.new(p)
	var names := RuleSets.names(st)
	check(st.get_value("regelsatz_gewaehlt") == "", "zuletzt gewählter Satz: Standard leer")
	check(names.size() == RuleSets.MAX and names[0] == "Gut" and names[1] == "Zweiter" and names[2] == "S0" and not names.has("gut"),
		"kaputte Einträge fallen weg, Doppelte auch, höchstens 12 (%s)" % str(names))
	var g := RuleSets.config("Gut", st)
	check(g.round_end == "last" and g.hand_size == 8 and g.stacking == "off" and g.target == 5000 and not g.backs_visible
		and not (st.get_value("regelsaetze")[0] as Dictionary).regeln.has("unbekannt"), "unbekannte Optionen weg, ungültige Werte auf Standard bzw. begrenzt")
	check(RuleSets.config("S3", st).equals(RuleConfig.new()), "leere Regeln = Standard (offiziell)")
	check(RuleSets.host_name(st) == "<Lena>" and RuleSets.host_config(st).mau_call == "off", "Gastgeber-Platz bereinigt (%s)" % RuleSets.host_name(st))
	# Ganz falsche Typen: Standard
	f = FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "regelsaetze": {"name": "x"}, "regeln_gastgeber": {"host": "Lena"}}))
	f.close()
	st = AppSettings.new(p)
	check(not st.has_value("regelsaetze") and RuleSets.list(st).is_empty() and not st.has_value("regeln_gastgeber") and RuleSets.host_slot(st).is_empty(),
		"keine Liste bzw. Gastgeber ohne Regeln → Standard")
	check(not st.set_value("regelsaetze", "Oma") and not st.set_value("regeln_gastgeber", [1]), "set_value lehnt falsche Typen ab")
	# Gastgeber mit leeren Regeln: beim Laden wie beim Merken (remember_host) ein leerer Platz
	f = FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "regeln_gastgeber": {"host": "Lena", "regeln": {}}, "regelsatz_gewaehlt": 5}))
	f.close()
	st = AppSettings.new(p)
	check(RuleSets.host_slot(st).is_empty() and RuleSets.host_name(st) == "" and not st.has_value("regeln_gastgeber"), "Gastgeber mit leeren Regeln → leer")
	check(not st.has_value("regelsatz_gewaehlt") and RuleSets.chosen_name(st) == "", "gewählter Satz keine Zeichenkette → Standard")
	check(AppSettings.sanitize("regelsatz_gewaehlt", "  [Oma]  ") == "Oma", "gewählter Satz: Name bereinigt")


func recognition(st: AppSettings) -> void:
	var a := house()
	check(RuleSets.match_name(a, st) == "Oma-Regeln" and RuleSets.matches("oma-regeln", a, st), "aktuelle Regeln = gespeicherter Satz")
	var changed := a.duplicate_config()
	changed.hand_size = 6
	check(RuleSets.match_name(changed, st) == "", "geändert: kein Satz")
	# Ohne Kartentausch zählt die Tauschrichtung nicht (wie bei den Voreinstellungen)
	var off := RuleConfig.new()
	off.mau_call = "auto"
	RuleSets.save("Ohne Tausch", off, st)
	var other_dir := off.duplicate_config()
	other_dir.swap_direction = "play"
	check(RuleSets.match_name(other_dir, st) == "Ohne Tausch", "ohne Kartentausch: Richtung egal")
	var with_swap := a.duplicate_config()
	with_swap.swap_direction = "clockwise"
	check(RuleSets.match_name(with_swap, st) == "", "mit Kartentausch: Richtung zählt")
	# Doppelte Regeln unter zwei Namen: der zuletzt gewählte (gespeicherte bzw. geladene) passt, ohne Wahl der erste
	RuleSets.save("Oma 2", a, st)
	check(RuleSets.match_name(a, st) == "Oma 2", "doppelte Regeln: der zuletzt gespeicherte")
	RuleSets.choose("oma-regeln", st)
	check(RuleSets.match_name(a, st) == "Oma-Regeln" and RuleSets.chosen_name(st) == "Oma-Regeln", "doppelte Regeln: der zuletzt gewählte")
	RuleSets.choose("", st)
	check(RuleSets.match_name(a, st) == "Oma-Regeln", "doppelte Regeln ohne Wahl: erster Satz")
	RuleSets.choose("Oma 2", st)
	check(RuleSets.match_name(changed, st) == "", "gewählter Satz passt nicht: kein Name")
	RuleSets.remove("Oma 2", st)
	check(RuleSets.chosen_name(st) == "" and RuleSets.match_name(a, st) == "Oma-Regeln", "gewählten Satz gelöscht: Wahl verfällt")
	RuleSets.remove("Ohne Tausch", st)


func host_slot(st: AppSettings, path: String) -> void:
	var writes := []
	var on_changed := func(key: String, _v: Variant) -> void:
		if key == RuleSets.HOST_KEY:
			writes.append(key)
	st.changed.connect(on_changed)
	var lobby_rules := house().to_dict()
	lobby_rules["hand_size"] = 10.0                  # wie aus JSON
	check(RuleSets.remember_host(lobby_rules, "Lena", st) and writes.size() == 1, "Gastgeber-Regeln gemerkt")
	check(RuleSets.host_name(st) == "Lena" and RuleSets.host_config(st).hand_size == 10 and RuleSets.host_config(st).gamble_cards == "on", "Gastgeber-Platz: Name und Regeln")
	check(RuleSets.remember_host(lobby_rules, "Lena", st) and writes.size() == 1, "gleiche Regeln: kein erneutes Schreiben")
	check(not RuleSets.remember_host({}, "Lena", st) and not RuleSets.remember_host(null, "Lena", st) and writes.size() == 1, "leere Regeln ändern nichts")
	var other := RuleConfig.preset("mau_mau").to_dict()
	check(RuleSets.remember_host(other, "Ben", st) and writes.size() == 2 and RuleSets.host_name(st) == "Ben" and RuleSets.host_config(st).equals(RuleConfig.preset("mau_mau")),
		"anderer Gastgeber: Platz überschrieben")
	check(RuleSets.host_matches(RuleConfig.preset("mau_mau"), st) and not RuleSets.host_matches(house(), st), "host_matches")
	check(RuleSets.count(st) == 1 and RuleSets.names(st) == ["Oma-Regeln"], "Gastgeber-Platz zählt nicht zu den eigenen Sätzen")
	var again := AppSettings.new(path)
	check(RuleSets.host_name(again) == "Ben" and RuleSets.host_config(again).equals(RuleConfig.preset("mau_mau")), "Gastgeber-Platz übersteht Neustart")
	# Bei 12 eigenen Sätzen wird der Gastgeber trotzdem gemerkt
	for i in range(RuleSets.count(st), RuleSets.MAX):
		RuleSets.save("Voll %d" % i, RuleConfig.new(), st)
	check(RuleSets.remember_host(lobby_rules, "Lena", st) and RuleSets.host_name(st) == "Lena" and RuleSets.count(st) == RuleSets.MAX, "Gastgeber auch bei 12 Sätzen")
	st.changed.disconnect(on_changed)
	# Name aus der Lobby-Nachricht
	var lobby := {"host_id": 3, "players": [{"id": 1, "name": "Ben"}, {"id": 3, "name": "Lena"}]}
	check(RuleSets.host_name_in_lobby(lobby, "?") == "Lena" and RuleSets.host_name_in_lobby({"players": []}, "Gastgeber") == "Gastgeber", "Name des Gastgebers aus der Lobby")


# Zuletzt gewählter Satz: speichern und laden setzen ihn, er übersteht den Neustart, Löschen und Voreinstellung heben ihn auf
func chosen(path: String) -> void:
	var p := path + ".wahl"
	var st := AppSettings.new(p)
	var a := house()
	var b := RuleConfig.preset("mau_mau")
	RuleSets.save("Erster", a, st)
	check(RuleSets.chosen_name(st) == "Erster", "Speichern wählt den Satz")
	RuleSets.save("Zweiter", a, st)
	RuleSets.save("Dritter", b, st)
	check(RuleSets.chosen_name(st) == "Dritter" and RuleSets.match_name(a, st) == "Erster", "anderer Satz gewählt: bei Doppelten der erste")
	RuleSets.choose("zweiter", st)
	var again := AppSettings.new(p)
	check(RuleSets.chosen_name(again) == "Zweiter" and RuleSets.match_name(a, again) == "Zweiter", "Wahl übersteht den Neustart, Doppelte zeigen sie")
	RuleSets.choose("Gibt es nicht", st)
	check(RuleSets.chosen_name(st) == "", "unbekannter Name: keine Wahl")
	var writes := [0]
	var count_writes := func(key: String, _v: Variant) -> void:
		if key == RuleSets.CHOSEN_KEY:
			writes[0] += 1
	st.changed.connect(count_writes)
	RuleSets.choose("", st)
	check(writes[0] == 0, "gleiche Wahl: kein Schreiben")
	st.changed.disconnect(count_writes)
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(p + suffix)


# Datei nicht schreibbar (Ordner fehlt): Speichern und Löschen melden es, im Speicher bleibt der alte Stand
func write_errors() -> void:
	var st := AppSettings.new("user://gibt_es_nicht_%d/einstellungen.json" % Time.get_ticks_usec())
	check(RuleSets.save("Oma", house(), st) == RuleSets.ERR_WRITE and RuleSets.count(st) == 0 and not st.has_value(RuleSets.KEY),
		"Speichern ohne schreibbare Datei: ERR_WRITE, nichts im Speicher")
	st.data[RuleSets.KEY] = [{"name": "Alt", "regeln": RuleConfig.new().to_dict()}]
	check(RuleSets.save("Alt", house(), st) == RuleSets.ERR_WRITE and RuleSets.config("Alt", st).equals(RuleConfig.new()), "Überschreiben scheitert: alter Satz bleibt")
	check(not RuleSets.remove("Alt", st) and RuleSets.has_set("Alt", st), "Löschen scheitert: Satz bleibt")
	check(not RuleSets.remember_host(house().to_dict(), "Lena", st), "Gastgeber merken scheitert: false")


# 0.1.3 (Protokoll Nr. 2): Gespeicherte Regeln mit „bluff“ (App-Einstellungen, Regelsätze, Gastgeber-Regeln) laden als „free“.
# Dazu der Regler „Tempo der Computergegner“ (bot_tempo 0…1, Standard 0,5 = Bedenkzeit wie bisher).
func migration_013(path: String) -> void:
	var p := path + ".mig"
	var old := {"regeln": {"wild_restriction": "bluff", "hand_size": 6},
		"regelsaetze": [{"name": "Alt", "regeln": {"wild_restriction": "bluff"}}],
		"regeln_gastgeber": {"host": "Lena", "regeln": {"wild_restriction": "bluff", "stacking": "same"}}}
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	var st := AppSettings.new(p)
	var r: Dictionary = st.get_value("regeln")
	check(str(r.get("wild_restriction", "")) == "free" and int(r.get("hand_size", 0)) == 6, "Einstellungen: bluff → free (%s)" % str(r))
	var alt := RuleSets.config("Alt", st)
	check(alt != null and alt.wild_restriction == "free", "Regelsatz: bluff → free")
	var h := RuleSets.host_config(st)
	check(h != null and h.wild_restriction == "free" and h.stacking == "same", "Gastgeber-Regeln: bluff → free")
	RuleSets.remember_host({"wild_restriction": "bluff", "mau_penalty": 2}, "Kim", st)
	check(RuleSets.host_config(st).wild_restriction == "free" and RuleSets.host_name(st) == "Kim", "neu gemerkte Gastgeber-Regeln: bluff → free")
	check(RuleSets.load_config({"wild_restriction": "enforce"}).wild_restriction == "enforce", "App prüft bleibt")
	# Tempo der Computergegner
	check(is_equal_approx(float(st.get_value("bot_tempo")), 0.5) and is_equal_approx(AppSettings.think_factor(0.5), 1.0), "Tempo: Standard 0,5 = Faktor 1")
	check(AppSettings.think_factor(0.0) > 2.0 and AppSettings.think_factor(1.0) < 0.5, "Tempo: gemütlich langsamer, flott schneller")
	check(is_equal_approx(AppSettings.think_factor(0.0), 5.0) and is_equal_approx(AppSettings.think_factor(0.25), 3.0)
			and is_equal_approx(AppSettings.think_factor(1.0), 0.4) and is_equal_approx(AppSettings.think_factor(0.75), 0.7),
			"Tempo: gemütlich 5-fache Bedenkzeit, je Hälfte linear, flott 0,4")
	check(st.set_value("bot_tempo", 3) and is_equal_approx(float(st.get_value("bot_tempo")), 1.0) and not st.set_value("bot_tempo", "schnell"), "Tempo: begrenzt, Text ungültig")
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(p + suffix)
