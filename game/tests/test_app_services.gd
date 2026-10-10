extends SceneTree
# Modul C: App-Dienste – Autoload-Schnittstelle, Ton (Lautstärke nach Einstellung, fehlende Dateien still), ApkShare am PC
# (Ersatzdatei: path/size/sha256 für den Netz-Server), NetAndroid-Rückfall am PC.

var ok := 0
var failed := 0

func check(cond: bool, text: String) -> void:
	if cond:
		ok += 1
	else:
		failed += 1
		print("FAIL: ", text)

func _init() -> void:
	# Erst nach dem ersten Bild prüfen: Dann hängen die Autoloads im Baum, und Töne lassen sich abspielen.
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	# Ton: Lautstärke und stummes Verhalten ohne Dateien.
	var path := "user://test_app_services_%d.json" % Time.get_ticks_usec()
	var settings := AppSettings.new(path)
	var sound := AppSound.new()
	sound.settings = settings
	root.add_child(sound)
	# Standard (AGENTS.md 20): Mau-Töne normal, übrige Spieltöne ebenfalls normal. Die genauen dB-Werte prüft test_app_sound.
	var mau_normal := float(AppSound.MAU_DB["normal"])
	check(is_equal_approx(sound.volume_db("mau"), mau_normal) and is_equal_approx(sound.volume_db("karte"), float(AppSound.TON_DB["normal"])), "Ton: Mau normal, Spieltöne ab Werk normal")
	settings.set_value("toene", "aus")
	check(sound.volume_db("karte") <= -80.0, "Ton: Spieltöne ausdrücklich aus bleiben aus")
	settings.set_value("mau_ton", "leise")
	check(is_equal_approx(sound.volume_db("mau"), float(AppSound.MAU_DB["leise"])) and sound.volume_db("mau") < mau_normal, "Ton: Mau leise ist leiser")
	settings.set_value("mau_ton", "aus")
	check(not sound.play("mau") and not sound.play("mau_mau") and sound.last_played == "", "Ton: Mau aus spielt nichts")
	check(not sound.play("gibt_es_nicht") and AppSound.path_for("gibt_es_nicht") == "", "Ton: fehlende Datei bleibt still")
	settings.set_value("toene", "normal")
	for sound_name in AppSound.NAMES:
		var has_file := AppSound.path_for(sound_name) != ""
		if AppSound.is_mau(sound_name):
			continue
		check(sound.play(sound_name) == has_file, "Ton %s: %s" % [sound_name, "spielt" if has_file else "fehlt noch, still"])
		if not has_file:
			print("Hinweis: res://assets/sfx/%s.ogg/.wav fehlt noch" % sound_name)
	settings.set_value("mau_ton", "normal")
	for sound_name in AppSound.MAU_NAMES:
		var mau_file := AppSound.path_for(sound_name) != ""
		check(sound.play(sound_name) == mau_file and (not mau_file or is_equal_approx(sound.last_db, mau_normal)), "Ton: %s normal" % sound_name)
	sound.stop_all()
	sound.free()

	# ApkShare am PC: ohne Ersatzdatei nichts anzubieten; mit Ersatzdatei path/size/sha256/name für /apk.
	var none := ApkShare.new()
	check(not none.available() and none.server_info().is_empty() and none.offer().is_empty(), "ApkShare am PC ohne Datei: nichts anzubieten")
	none.free()
	var fake := "user://test_app_fake_%d.apk" % Time.get_ticks_usec()
	var content := PackedByteArray()
	for i in range(300000):
		content.append(i % 251)
	var f := FileAccess.open(fake, FileAccess.WRITE)
	f.store_buffer(content)
	f.close()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(content)
	var expected := ctx.finish().hex_encode()
	var share := ApkShare.new()
	share.source_override = {"path": fake, "version": "9.9.9"}
	check(share.available() and share.size_bytes() == content.size() and share.version() == "9.9.9", "ApkShare: Ersatzdatei erkannt")
	check(share.server_info().is_empty() and share.job == "hash", "ApkShare: erster Abruf stößt die Prüfsumme an")
	var waited := 0
	while share.job != "" and waited < 5000:
		OS.delay_msec(10)
		waited += 10
		share.poll()
	var server := share.server_info()
	check(server.get("path") == fake and int(server.get("size", 0)) == content.size() and server.get("sha256") == expected
		and server.get("name") == "MauMauFlip-9.9.9.apk" and ApkShare.is_sha(str(server.get("sha256", ""))), "ApkShare: path/size/sha256/name für /apk")
	check(share.offer() == {"size": content.size(), "sha256": expected}, "ApkShare: Angebot (Größe, Prüfsumme)")
	check(ApkShare.file_name_for("0.1.1") == "MauMauFlip-0.1.1.apk" and not ApkShare.is_sha("abc") and not ApkShare.is_sha("zz".repeat(32)), "ApkShare: Dateiname, Prüfsummenformat")
	share.release_file()
	check(share.file_path() == "" and FileAccess.file_exists(fake), "ApkShare: release_file vergisst die Ersatzdatei, löscht sie nicht")
	share.free()
	DirAccess.remove_absolute(fake)

	# NetAndroid am PC: Rückfall ohne Java.
	var state := NetAndroid.state()
	check(not NetAndroid.available() and state.get("android") == false and state.get("interfaces") is Array and NetAndroid.bind_wifi() == "Nur auf Android möglich."
		and not NetAndroid.multicast(true) and NetAndroid.wifi_gateway(state) == "", "NetAndroid am PC: Ersatzwerte")

	# Autoload App (fehlt er, z. B. in einem anderen Testaufbau, wird das gemeldet, aber nicht als Fehler gezählt).
	var app: Node = root.get_node_or_null("/root/App")
	if app == null:
		print("Hinweis: Autoload App fehlt in diesem Lauf")
	else:
		check(app.version() == ProjectSettings.get_setting("application/config/version") and not app.is_android(), "App: version(), is_android()")
		check(app.settings is AppSettings and app.sound is AppSound and app.updater is Updater and app.apk_share is ApkShare, "App: Dienste vorhanden")
		app.vibrate(30, 0.5)
		app.set_keep_screen_on(false)
		var off: bool = app.keep_screen_on()
		app.set_keep_screen_on(true)
		check(not off and app.keep_screen_on(), "App: Bildschirm-an umschaltbar")
		check(app.updater.status == "Noch nicht geprüft." and not app.updater.busy, "App: keine automatische Update-Prüfung am PC")
	# Der Audioserver gibt beendete Wiedergaben erst im nächsten Mischschritt frei – sonst meldet Godot beim Beenden belegte Ressourcen.
	for i in range(10):
		await process_frame
		OS.delay_msec(10)
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(path + suffix)
	print("RESULT: %d ok" % ok)
	quit(1 if failed > 0 else 0)
