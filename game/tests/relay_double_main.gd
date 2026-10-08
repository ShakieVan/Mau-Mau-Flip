extends SceneTree
# Online-Spiel (docs/online/ENTWURF.md 6): Vermittler-Nachbau (NetRelayDouble) auf dem PC – kein test_*.gd, läuft nur von Hand.
#
# Lokaler Gerätetest (nach Absprache):
#   tools/godot_run.ps1 -Script res://tests/relay_double_main.gd -Headless -Timeout 7200 -EnvPairs "RELAY_SEKUNDEN=7000"
#   Handys: adb reverse tcp:24700 tcp:24700, in der App unter Einstellungen → Online die Adresse http://localhost:24700 eintragen.
#   Browser-Gäste: http://localhost:24700/?r=CODE (Lader aus relay/public wie beim Worker, dann /c/<version>/ aus relay/public/c
#   bzw. webclient/ / assets/web.zip; RELAY_OHNE_LADER=1 liefert den Browser-Client direkt unter „/“).
#   Umgebung: RELAY_PORT (Standard 24700), RELAY_SEKUNDEN (Laufzeit, Standard 3600), RELAY_GNADE_S (Abwesenheit, Standard 600).
#
# Kontrollbilder der Online-Bildschirme (Tag, dazu einmal Englisch), mit echtem Renderer:
#   tools/godot_run.ps1 -Script res://tests/relay_double_main.gd -Resolution 1600x720 -EnvPairs "SHOT_DIR=…"
#   online_lobby_offen (Weg „Online (Internet)“ mit Raumcode, Link, QR, Leuchten), online_lobby_gast (Haken, Spielerliste mit
#   Weltkugel), online_lobby_ohne_vermittler, online_beitreten (Raumcode-Feld), online_einstellungen (Abschnitt „Online“ nach
#   „Verbindung testen“), online_lobby_offen_en. Die Einstellung „vermittler“ wird danach wiederhergestellt.

const CleanExit := preload("res://tests/clean_exit.gd")

var relay: NetRelayDouble
var out_dir := ""
var failed := 0
var shots := 0


func _initialize() -> void:
	call_deferred("run")


func check(cond: bool, text: String) -> void:
	if not cond:
		failed += 1
		print("FAIL: ", text)


func run() -> void:
	var port := int(OS.get_environment("RELAY_PORT")) if OS.get_environment("RELAY_PORT").is_valid_int() else NetRelayDouble.DEFAULT_PORT
	relay = NetRelayDouble.new()
	relay.web_zip_path = _web_zip()
	# Lader und Startseite wie beim Worker (relay/public), außer bei den Kontrollbildern
	var pub := ProjectSettings.globalize_path("res://").path_join("../relay/public").simplify_path()
	if OS.get_environment("SHOT_DIR") == "" and OS.get_environment("RELAY_OHNE_LADER") == "" and DirAccess.dir_exists_absolute(pub):
		relay.public_dir = pub
	if OS.get_environment("RELAY_GNADE_S").is_valid_int():
		relay.core.grace_ms = int(OS.get_environment("RELAY_GNADE_S")) * 1000
	relay.log_line.connect(func(t: String) -> void: print("Vermittler: ", t))
	root.add_child(relay)
	if relay.start(port, port) != OK:
		print("FAIL: Port %d belegt" % port)
		await CleanExit.finish(self, 1)
		return
	print("Vermittler-Nachbau: http://127.0.0.1:%d (Browser-Client: %s)" % [port, relay.web_zip_path if relay.web_zip_path != "" else "keiner"])
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir != "":
		await shots_run(port)
		print("Bilder: %d nach %s" % [shots, out_dir])
		print("RESULT: %d Bilder" % shots if failed == 0 else "FAIL: %d" % failed)
		relay.stop()
		await CleanExit.finish(self, 1 if failed else 0)
		return
	var seconds := int(OS.get_environment("RELAY_SEKUNDEN")) if OS.get_environment("RELAY_SEKUNDEN").is_valid_int() else 3600
	var end := Time.get_ticks_msec() + seconds * 1000
	var last := ""
	while Time.get_ticks_msec() < end:
		await create_timer(1.0).timeout
		var rooms := ", ".join(PackedStringArray(relay.core.rooms.keys()))
		var line := "Räume: %s · Verbindungen: %d" % [rooms if rooms != "" else "–", relay.core.socks.size()]
		if line != last:
			print(line)
			last = line
	relay.stop()
	await CleanExit.finish(self, 0)


# Browser-Client: aktueller Stand aus webclient/ (gepackt), sonst assets/web.zip
func _web_zip() -> String:
	var src := ProjectSettings.globalize_path("res://").path_join("../webclient").simplify_path()
	if DirAccess.dir_exists_absolute(src):
		var zip_path := "user://relay_double/web.zip"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://relay_double"))
		var z := ZIPPacker.new()
		if z.open(zip_path) == OK:
			_pack(z, src, "")
			z.close()
			return zip_path
	return "res://assets/web.zip" if FileAccess.file_exists("res://assets/web.zip") else ""


func _pack(z: ZIPPacker, dir: String, prefix: String) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".mp4"):
			continue
		z.start_file(prefix + f)
		z.write_file(FileAccess.get_file_as_bytes(dir.path_join(f)))
		z.close_file()
	for d in DirAccess.get_directories_at(dir):
		if d != "test":
			_pack(z, dir.path_join(d), prefix + d + "/")


# ---------- Kontrollbilder ----------

func shots_run(port: int) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1600, 720)
	GameStarter.test_speed = 0.0
	var app := UiApp.app()
	var had: bool = app.settings.has_value("vermittler")
	var backup: Variant = app.settings.get_value("vermittler")
	var url := "http://127.0.0.1:%d" % port
	# ohne Vermittler-Adresse
	app.settings.set_value("vermittler", "")
	var nav := ScreenNav.new()
	nav.autostart = false
	root.add_child(nav)
	await _frames(10)
	var lobby := HostLobbyScreen.new()
	nav.push(lobby, false)
	await _frames(30)
	lobby.invite.show_way("online")
	await _frames(20)
	check(lobby.invite.find_child("OhneVermittler", true, false).visible, "ohne Vermittler: Hinweis sichtbar")
	await _save("online_lobby_ohne_vermittler")
	# mit Vermittler: öffnen
	app.settings.set_value("vermittler", url)
	lobby.on_enter()
	lobby.invite.open_online()
	check(await _until(func() -> bool: return lobby.invite.online_state() == "open", 5000), "Online-Raum offen")
	await _frames(30)
	var code := str(lobby.invite.online_info().get("room", ""))
	check(code != "" and (lobby.invite.find_child("Raumcode", true, false) as Label).text == code, "Raumcode angezeigt")
	await _save("online_lobby_offen")
	# englisch
	I18n.set_language("en")
	await _frames(20)
	await _save("online_lobby_offen_en")
	I18n.set_language("de")
	await _frames(10)
	# ein Online-Gast
	var guest := NetClient.new()
	guest.persist_tokens = false
	guest.reuse_token = false
	root.add_child(guest)
	guest.connect_relay(url, code, "Mia")
	check(await _until(func() -> bool: return guest.state == "open", 5000), "Online-Gast angenommen")
	await _frames(30)
	check(lobby.invite._on_check.visible, "Haken nach dem ersten Online-Gast")
	await _save("online_lobby_gast")
	lobby.show_page(1, false)
	await _frames(30)
	check(lobby.find_child("Online", true, false) != null, "Weltkugel in der Spielerliste")
	await _save("online_lobby_spielerliste")
	guest.close()
	guest.queue_free()
	nav.pop(false)
	await _frames(10)
	# Beitreten mit Raumcode
	var join := JoinScreen.new()
	nav.push(join, false)
	await _frames(30)
	(join.find_child("Raumcode", true, false) as LineEdit).text = "KATZE-42"
	await _frames(5)
	await _save("online_beitreten")
	nav.pop(false)
	await _frames(10)
	# Einstellungen, Abschnitt Online nach „Verbindung testen“
	var st := SettingsScreen.new()
	nav.push(st, false)
	await _frames(30)
	st.test_relay()
	var status := st.find_child("VermittlerStatus", true, false) as Label
	check(await _until(func() -> bool: return status.text.contains("ms"), 5000), "Verbindung testen: " + status.text)
	st.show_relay_qr(true)
	await _frames(10)
	for s in st.find_children("*", "ScrollContainer", true, false):
		(s as ScrollContainer).ensure_control_visible(st.find_child("VermittlerQRBild", true, false) as Control)
	await _frames(20)
	await _save("online_einstellungen")
	nav.queue_free()
	await _frames(5)
	if had:
		app.settings.set_value("vermittler", backup)
	else:
		app.settings.reset("vermittler")


func _until(cond: Callable, ms: int) -> bool:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _save(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	shots += 1
