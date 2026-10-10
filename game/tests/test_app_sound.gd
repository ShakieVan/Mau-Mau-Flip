extends SceneTree
# Modul S / T2: Töne – Mau-Töne sind die Aufnahmen des Nutzers ("mau" = „Mao“, "mau_mau" = „Mao-Mao“, AGENTS.md Nr. 20), Lautstärke
# nach mau_ton, übrige Töne nach toene (Standard aus), keine Gerätesperre mehr (Entprellung je Platz macht MauSound), Probehören,
# fehlende Dateien bleiben still, Vorladen, mehrere Töne gleichzeitig, Dateien für Godot und Browser-Client, synthetische
# Mau-Varianten entfernt. Spieltöne: KI-Fassungen (MOSS-SoundEffect v2.0, tools/make_sfx_moss.py --spiel) mit Katzen-Leitplanke
# laut audio/sfx_ki/spiel/messwerte.json (über 6/10/12 kHz höchstens −30/−50/−60 dB in WAV, OGG und M4A).
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

	# Dateien: alle Töne vorhanden und vorgeladen, Längen wie geschnitten bzw. aufgenommen (Spieltöne mit 20 ms Endstille).
	var lengths := {"mau": [0.35, 0.7], "mau_mau": [0.45, 0.8], "karte": [0.20, 0.32], "ziehen": [0.50, 0.70], "mischen": [1.05, 1.30],
		"flip": [1.25, 1.50], "jubel_1": [7.0, 7.5], "jubel_2": [7.1, 7.6], "fehler": [0.20, 0.32], "dran": [0.50, 0.70], "schnurren": [1.55, 1.75]}
	for sound_name in lengths:
		var s: AudioStream = sound.stream(sound_name)
		var span: Array = lengths[sound_name]
		check(s != null and sound.is_loaded(sound_name), "Datei %s vorhanden und vorgeladen" % sound_name)
		if s != null:
			check(s.get_length() >= float(span[0]) and s.get_length() <= float(span[1]), "Länge %s: %.3f s" % [sound_name, s.get_length()])
	check(AppSound.NAMES.size() == 11 and sound.preload_all() == 11, "preload_all zählt alle 11 Dateien")
	for k in ["stimme", "gesungen", "blubb", "spieluhr", "kalimba"]:
		check(AppSound.path_for("mau_" + k) == "", "synthetische Mau-Variante mau_%s entfernt" % k)
	var web := ProjectSettings.globalize_path("res://").path_join("../webclient/sfx/")
	for sound_name in lengths:
		check(FileAccess.file_exists(web + sound_name + ".ogg") and FileAccess.file_exists(web + sound_name + ".m4a"), "Browser-Client: %s.ogg/.m4a" % sound_name)
	# Spieltöne: App und Browser spielen dieselbe Fassung (OGG gleich, M4A ist AAC im MP4-Behälter), Messwerte halten die Leitplanke.
	var game_sfx := ProjectSettings.globalize_path("res://assets/sfx/")
	var fav := {"karte": "karte_02", "ziehen": "ziehen_07", "mischen": "mischen_06", "flip": "flip_02", "dran": "dran_04",
		"fehler": "fehler_09"}
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		ProjectSettings.globalize_path("res://").path_join("../audio/sfx_ki/spiel/messwerte.json")))
	check(report is Dictionary and report.get("toene") is Dictionary, "audio/sfx_ki/spiel/messwerte.json vorhanden")
	var tones: Dictionary = report.get("toene", {}) if report is Dictionary else {}
	for sound_name in fav:
		var ogg_game := FileAccess.get_file_as_bytes(game_sfx + sound_name + ".ogg")
		check(ogg_game.size() > 1000 and ogg_game == FileAccess.get_file_as_bytes(web + sound_name + ".ogg"), "%s.ogg: App und Browser gleich" % sound_name)
		var m4a := FileAccess.get_file_as_bytes(web + sound_name + ".m4a")
		check(m4a.size() > 1000 and m4a.slice(4, 8).get_string_from_ascii() == "ftyp", "%s.m4a ist MP4/AAC" % sound_name)
		var m: Dictionary = tones.get(sound_name, {})
		check(str(m.get("kandidat", "")) == fav[sound_name], "%s: Favorit %s im Spiel" % [sound_name, fav[sound_name]])
		var fc := float(m.get("tiefpass_hz", 0.0))
		check(fc >= 4000.0 and fc <= 6000.0, "%s: Tiefpass zwischen 4 und 6 kHz (%.0f Hz)" % [sound_name, fc])
		for part in [m, m.get("ogg", {}), m.get("m4a", {})]:
			var d: Dictionary = part
			check(d.has("ueber_6k_db") and float(d["ueber_6k_db"]) <= -30.0 and float(d.get("ueber_10k_db", 0.0)) <= -50.0
				and float(d.get("ueber_12k_db", 0.0)) <= -60.0, "%s: Katzen-Leitplanke (%s / %s / %s dB)" % [sound_name,
				d.get("ueber_6k_db"), d.get("ueber_10k_db"), d.get("ueber_12k_db")])
			check(float(d.get("spitze_dbtp", 0.0)) <= -0.7, "%s: Spitze %s dBTP" % [sound_name, d.get("spitze_dbtp")])
	# Abgleich: Karte legen bleibt dezent (leiser als dran, flip), alle unter dem Mau-Ton. (Sieg = Jubel, eigene Prüfung unten.)
	if tones.size() >= fav.size():
		var lufs := func(n: String) -> float: return float(tones[n].get("lufs_momentan_max", 0.0))
		check(lufs.call("karte") < lufs.call("flip") and lufs.call("karte") < lufs.call("dran"), "Karte legen leiser als flip, dran")
		check(lufs.call("dran") >= lufs.call("mischen"), "dran lauter als mischen")
		var mau_lufs := float(report.get("bezug", {}).get("mau", {}).get("lufs_momentan_max", 0.0))
		for sound_name in fav:
			check(float(tones[sound_name].get("gegen_mau_db", 0.0)) <= -6.0, "%s im Spiel mindestens 6 dB unter dem Mau-Ton (%s dB)" % [sound_name, tones[sound_name].get("gegen_mau_db")])
			check(lufs.call(sound_name) + float(AppSound.TON_DB["normal"]) < mau_lufs + float(AppSound.MAU_DB["normal"]), "%s leiser als Mau" % sound_name)
	# sfx/index.json (Browser-Client, Modul E): nennt mindestens die Aufnahmen; jede genannte Datei liegt daneben.
	var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(web + "index.json"))
	check(index is Dictionary and str(index.get("mau", "")) == "mau.m4a" and str(index.get("mau_mau", "")) == "mau_mau.m4a", "Browser-Client: sfx/index.json nennt die Aufnahmen")
	if index is Dictionary:
		for key in index:
			check(FileAccess.file_exists(web + str(index[key])), "Browser-Client: sfx/%s vorhanden" % str(index[key]))

	# Jubel statt Sieg-Ton (10.10.2026): Ereignis "sieg" spielt jubel_1 oder jubel_2 (Zufall), unverändert aus audio/entwurf/jubel3 (01 und 06).
	var entwurf := ProjectSettings.globalize_path("res://").path_join("../audio/entwurf/jubel3/")
	for pair in [["jubel_1", "jubel3_01"], ["jubel_2", "jubel3_06"]]:
		var jb := FileAccess.get_file_as_bytes(game_sfx + str(pair[0]) + ".ogg")
		check(jb.size() > 1000 and jb == FileAccess.get_file_as_bytes(web + str(pair[0]) + ".ogg"), "%s.ogg: App und Browser gleich" % pair[0])
		check(jb == FileAccess.get_file_as_bytes(entwurf + str(pair[1]) + ".ogg"), "%s ist %s unverändert" % [pair[0], pair[1]])
	check(AppSound.path_for("sieg") == "" and not FileAccess.file_exists(web + "sieg.ogg") and not FileAccess.file_exists(web + "sieg.m4a"), "alter Sieg-Ton entfernt")
	check(index is Dictionary and not index.has("sieg") and str(index.get("jubel_1", "")) == "jubel_1.m4a" and str(index.get("jubel_2", "")) == "jubel_2.m4a", "sfx/index.json nennt jubel_1/jubel_2, nicht sieg")
	# Standardwerte: Mau-Ton normal (-2 dB), Spieltöne aus.
	check(sound.level("mau_ton") == "normal" and sound.level("toene") == "aus", "Standard: mau_ton normal, toene aus")
	check(is_equal_approx(sound.volume_db("mau"), -2.0) and is_equal_approx(sound.volume_db("mau_mau"), -2.0), "Mau-Töne normal -2 dB")
	check(sound.volume_db("karte") <= -80.0 and not sound.play("karte") and sound.last_played == "", "Spieltöne ab Werk aus: Karte still")
	var bare := AppSound.new()
	check(bare.level("toene") == "aus" and bare.level("mau_ton") == "normal", "ohne Einstellungen: dieselben Standardwerte")
	bare.free()

	# Lautstärke: Mau nach mau_ton, übrige Töne nach toene (unabhängig voneinander).
	settings.set_value("toene", "normal")
	check(is_equal_approx(sound.volume_db("karte"), -4.5) and is_equal_approx(sound.volume_db("mau"), -2.0), "toene normal: Karte -4,5 dB, Mau unverändert")
	settings.set_value("mau_ton", "leise")
	check(is_equal_approx(sound.volume_db("mau"), -12.0) and is_equal_approx(sound.volume_db("mau_mau"), -12.0) and is_equal_approx(sound.volume_db("karte"), -4.5), "mau_ton leise wirkt nur auf die Mau-Töne")
	settings.set_value("toene", "leise")
	check(is_equal_approx(sound.volume_db("karte"), -12.5) and is_equal_approx(sound.volume_db("mau"), -12.0), "toene leise wirkt nur auf die übrigen Töne")
	check(not settings.set_value("toene", "laut") and is_equal_approx(sound.volume_db("karte"), -12.5), "toene: ungültiger Wert abgelehnt")
	check(AppSound.TRIM_DB.is_empty(), "kein Feinabgleich je Ton: der Abgleich steckt in den Dateien (der Browser hat keinen)")
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

	# Jubel: bei Spieltöne normal spielt "sieg" eine der beiden Dateien, beide kommen vor, läuft er schon, startet kein zweiter; Ausblenden stoppt ihn.
	sound.stop_all()
	var seen := {}
	for i in range(40):
		sound.stop_all()
		sound.now_override = 200000 + i * 1000
		if sound.play("sieg"):
			check(sound.last_played == "sieg" and AppSound.JUBEL.has(sound.last_file), "sieg spielt Jubel (%s)" % sound.last_file)
			seen[sound.last_file] = true
	check(seen.size() == 2, "beide Jubel-Dateien kommen vor (Zufall)")
	sound.stop_all()
	sound.jubel_pick = 1
	check(sound.play("sieg") and sound.last_file == "jubel_2" and is_equal_approx(sound.last_db, -4.5), "jubel_pick erzwingt jubel_2, -4,5 dB")
	sound.now_override += 5000
	check(not sound.play("sieg") and sound.playing_count() == 1, "Jubel startet nicht doppelt")
	sound.fade_out_jubel()
	await create_timer(AppSound.JUBEL_FADE_S + 0.3).timeout
	check(sound.playing_count() == 0, "fade_out_jubel blendet aus und stoppt")
	sound.jubel_pick = -1

	# Mehrere Töne gleichzeitig (Vorrat an Abspielern).
	sound.stop_all()
	sound.now_override = 140000
	var started := 0
	for sound_name in ["karte", "ziehen", "mischen", "flip", "sieg", "fehler", "dran", "schnurren"]:
		if sound.play(sound_name):
			started += 1
	check(started == 8 and sound.playing_count() == AppSound.VOICES, "8 Töne gestartet, alle %d Abspieler belegt" % AppSound.VOICES)
	sound.stop_all()

	# Android-Weg (Beta 1.4.8, Ton nach Telefonat): Töne gehen an SoundPool (Attrappe), Lautstärke linear, Jubel-Sperre und
	# playing_count nach Länge, Ausblenden/Stopp/Pause an Java; liefert SoundPool 0 (noch nicht geladen), spielt Godot.
	var fake := FakePool.new()
	sound.stop_all()
	sound.native = fake
	sound.now_override = 300000
	check(sound.play("karte") and sound.last_native and fake.calls[-1] == "play karte", "Android: Karte über SoundPool")
	check(is_equal_approx(float(fake.vols[-1]), db_to_linear(-4.5)), "Android: Lautstärke -4,5 dB linear (%.3f)" % float(fake.vols[-1]))
	check(sound.playing_count() == 1, "Android: laufender Ton zählt")
	sound.now_override = 300000 + 400
	check(sound.playing_count() == 0, "Android: nach seiner Länge zählt er nicht mehr")
	sound.now_override = 301000
	check(sound.play("mau") and is_equal_approx(float(fake.vols[-1]), db_to_linear(-2.0)), "Android: Mau -2 dB")
	sound.jubel_pick = 0
	check(sound.play("sieg") and sound.last_native and fake.calls[-1] == "play jubel_1", "Android: Jubel über SoundPool")
	sound.now_override = 304000
	check(not sound.play("sieg"), "Android: Jubel startet nicht doppelt")
	sound.fade_out_jubel()
	check(fake.calls[-1].begins_with("fade ") and fake.calls[-1].ends_with(" 600"), "Android: Jubel ausblenden in 600 ms")
	check(sound.play("sieg"), "Android: nach dem Ausblenden darf Jubel wieder starten")
	sound.jubel_pick = -1
	fake.next_id = 0
	sound.now_override = 305000
	check(sound.play("ziehen") and not sound.last_native and sound.playing_count() >= 1, "Android: SoundPool liefert 0 → Godot spielt")
	fake.next_id = 50
	sound.stop_all()
	check(fake.calls[-1] == "stopAll" and sound.playing_count() == 0, "Android: stop_all stoppt auch SoundPool")
	sound.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	sound.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(fake.calls.slice(-2) == ["pause", "resume"], "Android: Fokus weg/zurück → pause/resume")
	sound.now_override = 306000
	for i in range(8):
		sound.play(["karte", "ziehen", "mischen", "flip", "fehler", "dran", "schnurren", "mau"][i])
	check(sound.playing_count() <= AppSound.VOICES, "Android: höchstens %d Stimmen gezählt" % AppSound.VOICES)
	sound.stop_all()
	sound.native = null

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


class FakePool:
	extends RefCounted
	var calls: Array[String] = []
	var vols: Array[float] = []
	var next_id := 50

	func play(n: String, vol: float) -> int:
		calls.append("play " + n)
		vols.append(vol)
		if next_id <= 0:
			return 0
		next_id += 1
		return next_id

	func stopAll() -> void:
		calls.append("stopAll")

	func fade(id: int, vol: float, ms: int) -> void:
		calls.append("fade %d %d" % [id, ms])

	func pause() -> void:
		calls.append("pause")

	func resume() -> void:
		calls.append("resume")
