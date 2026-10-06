extends SceneTree
# Modul C: Einstellungen – Standardwerte, sofortiges Speichern und Laden, Prüfung der Werte, Sicherung (.bak), Namensfilter.

var ok := 0
var failed := 0

func check(cond: bool, text: String) -> void:
	if cond:
		ok += 1
	else:
		failed += 1
		print("FAIL: ", text)

func _init() -> void:
	var path := "user://test_app_settings_%d.json" % Time.get_ticks_usec()
	var s := AppSettings.new(path)
	var beta_default := not AppSettings.app_version().ends_with(".0")
	check(s.get_value("mau_ton") == "normal" and s.get_value("vibration") == true and s.get_value("effekte") == "voll"
		and s.get_value("sortierung") == "farbe" and s.get_value("beta") == beta_default and s.get_value("regeln") == {}
		and s.get_value("letzte_namen") == [] and s.get_value("name") == "", "Standardwerte")
	check(s.get_value("gibt_es_nicht", 7) == 7 and s.get_value("mau_ton", "aus") == "normal", "Vorgabe des Aufrufers nur für unbekannte Schlüssel")
	check(s.get_value("regelsaetze") == [] and s.get_value("regeln_gastgeber") == {} and AppSettings.sanitize("regelsaetze", "x") == null
		and AppSettings.sanitize("regeln_gastgeber", {"host": "Lena"}) == null, "Regelsätze und Gastgeber-Regeln: Standard leer, Prüfung (Einzelheiten: test_rule_sets)")
	check(s.get_value("regelsatz_gewaehlt") == "" and AppSettings.sanitize("regelsatz_gewaehlt", 3) == null
		and AppSettings.sanitize("regeln_gastgeber", {"host": "Lena", "regeln": {}}) == null, "zuletzt gewählter Satz: Standard leer; Gastgeber ohne Regeln ungültig")
	check(not FileAccess.file_exists(path), "ohne Änderung keine Datei")
	# Sofort gespeichert und beim nächsten Start wieder geladen; JSON-Zahlen kommen als float zurück.
	check(s.set_value("mau_ton", "leise") and FileAccess.file_exists(path), "set_value speichert sofort")
	s.set_value("vibration", false)
	s.set_value("effekte", "reduziert")
	s.set_value("sortierung", "punkte")
	s.set_value("name", "  Lena  ")
	s.set_value("regeln", {"hand_size": 7, "round_end": "last", "stacking": "same"})
	s.set_value("eigener_schluessel", {"a": [1, 2]})
	var t := AppSettings.new(path)
	var rules: Dictionary = t.get_value("regeln")
	check(t.get_value("mau_ton") == "leise" and t.get_value("vibration") == false and t.get_value("effekte") == "reduziert"
		and t.get_value("sortierung") == "punkte" and t.get_value("name") == "Lena", "Werte nach dem Laden")
	check(int(rules.get("hand_size", 0)) == 7 and rules.get("round_end") == "last" and t.get_value("eigener_schluessel").a.size() == 2,
		"Regeln und unbekannte Schlüssel bleiben erhalten (Zahlen per int())")
	# Kopien: Änderungen am gelesenen Wert ändern die Einstellung nicht.
	rules["hand_size"] = 9
	check(int(t.get_value("regeln").hand_size) == 7, "get_value liefert Kopien von Dictionary/Array")
	# Ungültige Werte ändern nichts.
	check(not t.set_value("mau_ton", "laut") and not t.set_value("vibration", "ja") and not t.set_value("effekte", 3)
		and not t.set_value("sortierung", "zufall") and not t.set_value("regeln", [1]) and not t.set_value("beta", 1), "ungültige Werte abgelehnt")
	check(t.get_value("mau_ton") == "leise" and t.get_value("vibration") == false, "nach Ablehnung unverändert")
	# Beta-Kanal: erst gespeichert, wenn jemand ihn umschaltet; reset kehrt zum Standard zurück.
	check(not t.has_value("beta"), "Beta-Kanal ohne Umschalten nicht gespeichert")
	t.set_value("beta", not beta_default)
	check(AppSettings.new(path).get_value("beta") == (not beta_default), "Beta-Kanal umgeschaltet und gespeichert")
	t.reset("beta")
	check(AppSettings.new(path).get_value("beta") == beta_default and not AppSettings.new(path).has_value("beta"), "reset: wieder Standardwert")
	# „Spielbare Karten hervorheben“: persönliche Einstellung (bool, Standard an), Signal changed für den Tisch (HandView).
	check(t.get_value("hervorheben") == true and AppSettings.defaults().get("hervorheben") == true and t.get_value("hervorheben", false) == true,
		"hervorheben: Standard an (auch mit anderer Vorgabe des Aufrufers)")
	var hl := []
	var on_hl := func(key: String, value: Variant) -> void:
		if key == "hervorheben":
			hl.append(value)
	t.changed.connect(on_hl)
	check(t.set_value("hervorheben", false) and AppSettings.new(path).get_value("hervorheben") == false and hl == [false],
		"hervorheben aus: gespeichert, Signal changed")
	check(not t.set_value("hervorheben", "nein") and not t.set_value("hervorheben", 0) and t.get_value("hervorheben") == false and hl == [false],
		"hervorheben: nur bool, Ablehnung ändert nichts")
	t.set_value("hervorheben", true)
	check(AppSettings.new(path).get_value("hervorheben") == true and hl == [false, true], "hervorheben wieder an")
	t.changed.disconnect(on_hl)
	var hf := FileAccess.open(path + ".hl", FileAccess.WRITE)
	hf.store_string(JSON.stringify({"version": 1, "hervorheben": "ja"}))
	hf.close()
	check(AppSettings.new(path + ".hl").get_value("hervorheben") == true and not AppSettings.new(path + ".hl").has_value("hervorheben"),
		"hervorheben: ungültiger Eintrag in der Datei → Standard an")
	DirAccess.remove_absolute(path + ".hl")
	# Mehrere Werte, ein Speichervorgang; Signal je Schlüssel.
	var seen := []
	t.changed.connect(func(key: String, _value: Variant) -> void: seen.append(key))
	t.set_values({"mau_ton": "aus", "vibration": true, "effekte": "falsch"})
	check(AppSettings.new(path).get_value("mau_ton") == "aus" and AppSettings.new(path).get_value("vibration") == true
		and AppSettings.new(path).get_value("effekte") == "reduziert" and seen.has("mau_ton") and seen.has("vibration"), "set_values")
	# Beschädigte Datei: Rückfall auf die Sicherung (.bak = Stand vor dem letzten Speichern).
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{kaputt")
	f.close()
	var from_bak := AppSettings.new(path)
	check(from_bak.get_value("effekte") == "reduziert" and from_bak.get_value("sortierung") == "punkte", "beschädigte Datei → Sicherung")
	# Ungültige Einträge in der Datei gelten als nicht gesetzt.
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "mau_ton": 5, "vibration": "ja", "sortierung": "wert", "letzte_namen": ["Anna", "anna", "Anna", "<b>"]}))
	f.close()
	var odd := AppSettings.new(path)
	check(odd.get_value("mau_ton") == "normal" and odd.get_value("vibration") == true and odd.get_value("sortierung") == "wert"
		and odd.get_value("letzte_namen") == ["Anna", "anna", "b"], "ungültige Einträge → Standardwert, Namen bereinigt")
	# Zuletzt benutzte Namen: neue vorn, ohne Doppelte, höchstens 12.
	odd.remember_names(["Ben", "Anna"])
	check(odd.get_value("letzte_namen") == ["Ben", "Anna", "anna", "b"], "letzte Namen: neue vorn, ohne Doppelte")
	var many := []
	for i in range(20):
		many.append("Spieler %d" % i)
	odd.remember_names(many)
	check(odd.get_value("letzte_namen").size() == AppSettings.RECENT_NAMES and odd.get_value("letzte_namen")[0] == "Spieler 0", "letzte Namen: höchstens 12")
	# Namensfilter wie Draw2Race.
	check(AppSettings.clean_name("  A<script>  ") == "Ascript" and AppSettings.clean_name("Jörg  Müller-Äß") == "Jörg Müller-"
		and AppSettings.clean_name("") == "" and AppSettings.clean_name("😀😀") == "", "Name bereinigt (Zeichen, Leerzeichen, Länge)")
	check(AppSettings.filter_name("Lena ") == "Lena " and AppSettings.filter_name("abcdefghijklmnop") == "abcdefghijkl"
		and AppSettings.clean_name("Zoë!?") == "Zoë!?", "Filter beim Tippen")
	var hint := odd.player_name()
	check(hint.begins_with("Spieler ") and odd.player_name() == hint and AppSettings.new(path).player_name() == hint, "Namensvorschlag bleibt gleich")
	odd.set_value("name", "Mia")
	check(odd.player_name() == "Mia", "eigener Name")
	# Fehlender Ordner: Speichern meldet false statt abzustürzen.
	var nowhere := AppSettings.new("user://gibt/es/nicht/einstellungen.json")
	check(not nowhere.set_value("mau_ton", "aus") and nowhere.get_value("mau_ton") == "aus", "Speicherfehler gemeldet, Wert gilt in der Sitzung")
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(path + suffix)
	print("RESULT: %d ok" % ok)
	quit(1 if failed > 0 else 0)
