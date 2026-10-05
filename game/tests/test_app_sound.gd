extends SceneTree
# Modul S / T2: Töne – Mau-Töne sind die Aufnahmen des Nutzers ("mau" = „Mao“, "mau_mau" = „Mao-Mao“, AGENTS.md Nr. 20), Lautstärke
# nach mau_ton, übrige Töne nach toene (Standard aus), keine Gerätesperre mehr (Entprellung je Platz macht MauSound), Probehören,
# fehlende Dateien bleiben still, Vorladen, mehrere Töne gleichzeitig, Dateien für Godot und Browser-Client, synthetische
# Mau-Varianten entfernt.
# Aufruf headless mit Dummy-Audio:  tools/godot_run.ps1 -Script res://tests/test_app_sound.gd -Headless -Extra '--audio-driver','Dummy'

var ok := 0
var failed := 0

func check(cond: bool, text: String) -> void:
	if cond:
		ok += 1
	else:
		failed += 1
		print("FAIL: ", text)

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var path := "user://test_app_sound_%d.json" % Time.get_ticks_usec()
	var settings := AppSettings.new(path)
	var sound := AppSound.new()
	sound.settings = settings
	sound.now_override = 100000
	root.add_child(sound)

	# Dateien: alle Töne vorhanden und vorgeladen, Längen wie entworfen bzw. aufgenommen.
	var lengths := {"mau": [0.35, 0.7], "mau_mau": [0.45, 0.8], "karte": [0.08, 0.20], "ziehen": [0.20, 0.36], "mischen": [0.35, 0.46],
		"flip": [0.55, 0.66], "sieg": [1.10, 1.28], "fehler": [0.12, 0.22], "dran": [0.22, 0.32]}
	for sound_name in lengths:
		var s: AudioStream = sound.stream(sound_name)
		var span: Array = lengths[sound_name]
		check(s != null and sound.is_loaded(sound_name), "Datei %s vorhanden und vorgeladen" % sound_name)
		if s != null:
			check(s.get_length() >= float(span[0]) and s.get_length() <= float(span[1]), "Länge %s: %.3f s" % [sound_name, s.get_length()])
	check(AppSound.NAMES.size() == 9 and sound.preload_all() == 9, "preload_all zählt alle 9 Dateien")
	for k in ["stimme", "gesungen", "blubb", "spieluhr", "kalimba"]:
		check(AppSound.path_for("mau_" + k) == "", "synthetische Mau-Variante mau_%s entfernt" % k)
	var web := ProjectSettings.globalize_path("res://").path_join("../webclient/sfx/")
	for sound_name in lengths:
		check(FileAccess.file_exists(web + sound_name + ".ogg") and FileAccess.file_exists(web + sound_name + ".m4a"), "Browser-Client: %s.ogg/.m4a" % sound_name)
	# sfx/index.json (Browser-Client, Modul E): nennt mindestens die Aufnahmen; jede genannte Datei liegt daneben.
	var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(web + "index.json"))
	check(index is Dictionary and str(index.get("mau", "")) == "mau.m4a" and str(index.get("mau_mau", "")) == "mau_mau.m4a", "Browser-Client: sfx/index.json nennt die Aufnahmen")
	if index is Dictionary:
		for key in index:
			check(FileAccess.file_exists(web + str(index[key])), "Browser-Client: sfx/%s vorhanden" % str(index[key]))

	# Standardwerte: Mau-Ton normal (-2 dB), Spieltöne aus.
	check(sound.level("mau_ton") == "normal" and sound.level("toene") == "aus", "Standard: mau_ton normal, toene aus")
	check(is_equal_approx(sound.volume_db("mau"), -2.0) and is_equal_approx(sound.volume_db("mau_mau"), -2.0), "Mau-Töne normal -2 dB")
	check(sound.volume_db("karte") <= -80.0 and not sound.play("karte") and sound.last_played == "", "Spieltöne ab Werk aus: Karte still")
	var bare := AppSound.new()
	check(bare.level("toene") == "aus" and bare.level("mau_ton") == "normal", "ohne Einstellungen: dieselben Standardwerte")
	bare.free()

	# Lautstärke: Mau nach mau_ton, übrige Töne nach toene (unabhängig voneinander).
	settings.set_value("toene", "normal")
	check(is_equal_approx(sound.volume_db("karte"), -8.0) and is_equal_approx(sound.volume_db("mau"), -2.0), "toene normal: Karte -8 dB, Mau unverändert")
	settings.set_value("mau_ton", "leise")
	check(is_equal_approx(sound.volume_db("mau"), -12.0) and is_equal_approx(sound.volume_db("mau_mau"), -12.0) and is_equal_approx(sound.volume_db("karte"), -8.0), "mau_ton leise wirkt nur auf die Mau-Töne")
	settings.set_value("toene", "leise")
	check(is_equal_approx(sound.volume_db("karte"), -16.0) and is_equal_approx(sound.volume_db("mau"), -12.0), "toene leise wirkt nur auf die übrigen Töne")
	check(not settings.set_value("toene", "laut") and is_equal_approx(sound.volume_db("karte"), -16.0), "toene: ungültiger Wert abgelehnt")
	settings.data["toene"] = "laut"
	check(sound.level("toene") == "aus", "toene: ungültiger gespeicherter Wert → aus")
	settings.set_value("toene", "aus")
	check(not sound.play("karte") and sound.last_played == "", "toene aus: Karte still")
	settings.set_value("toene", "normal")

	# Mau aus: still (beide Aufnahmen).
	settings.set_value("mau_ton", "aus")
	check(not sound.play("mau") and not sound.play("mau_mau") and sound.last_played == "", "mau_ton aus: Mau und Mau-Mau still")

	# Keine Gerätesperre mehr: zwei Rufe kurz hintereinander klingen beide (Entprellung je Platz: MauSound).
	settings.set_value("mau_ton", "normal")
	check(sound.play("mau") and sound.last_played == "mau" and sound.last_file == "mau" and is_equal_approx(sound.last_db, -2.0), "Mau spielt mau.ogg mit -2 dB")
	sound.now_override = 100300
	check(sound.play("mau"), "zweiter Mau-Ruf 0,3 s später klingt auch")
	check(sound.play("mau_mau") and sound.last_file == "mau_mau", "Mau-Mau spielt mau_mau.ogg")
	settings.set_value("mau_ton", "leise")
	check(sound.play("mau") and is_equal_approx(sound.last_db, -12.0), "Mau leise -12 dB")

	# Probehören: Aufnahme in der eingestellten Lautstärke, bei „aus“ leise; nur Mau-Töne.
	check(sound.play_preview("mau") and sound.last_file == "mau" and is_equal_approx(sound.last_db, -12.0), "Probehören mau leise")
	settings.set_value("mau_ton", "aus")
	check(sound.play_preview("mau_mau") and sound.last_file == "mau_mau" and is_equal_approx(sound.last_db, -12.0), "Probehören bei mau_ton aus: leise")
	check(not sound.play_preview("karte") and not sound.play_preview("stimme"), "Probehören nur für Mau-Töne")
	settings.set_value("mau_ton", "normal")
	check(sound.play_preview() and is_equal_approx(sound.last_db, -2.0), "Probehören normal -2 dB")

	# Gleicher Spielton im selben Augenblick nur einmal, nach 40 ms wieder.
	sound.now_override = 130000
	check(sound.play("ziehen"), "ziehen spielt")
	check(not sound.play("ziehen"), "ziehen im selben Augenblick nur einmal")
	sound.now_override = 130040
	check(sound.play("ziehen"), "ziehen nach 40 ms wieder")

	# Mehrere Töne gleichzeitig (Vorrat an Abspielern).
	sound.stop_all()
	sound.now_override = 140000
	var started := 0
	for sound_name in ["karte", "ziehen", "mischen", "flip", "sieg", "fehler", "dran"]:
		if sound.play(sound_name):
			started += 1
	check(started == 7 and sound.playing_count() == AppSound.VOICES, "7 Töne gestartet, alle %d Abspieler belegt" % AppSound.VOICES)
	sound.stop_all()

	# Fehlende Dateien: alles still, keine Fehler.
	var empty := AppSound.new()
	empty.dir = "res://gibt_es_nicht/"
	empty.settings = settings
	empty.now_override = 1000
	root.add_child(empty)
	check(empty.preload_all() == 0 and empty.stream("mau") == null and empty.stream("karte") == null, "fehlende Dateien: nichts geladen")
	check(not empty.play("mau") and not empty.play("mau_mau") and not empty.play_preview("mau"), "fehlende Mau-Töne: still")
	check(not empty.play("karte") and not empty.play("gibt_es_nicht") and empty.last_played == "", "fehlende Töne: still")
	empty.free()

	sound.free()
	for i in range(10):
		await process_frame
		OS.delay_msec(10)
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(path + suffix)
	print("RESULT: %d ok" % ok)
	quit(1 if failed > 0 else 0)
