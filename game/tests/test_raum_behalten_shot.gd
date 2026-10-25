extends "res://tests/main_menu_kit.gd"
# Kontrollbilder Beta 1.6.16 (Raum behalten, docs/module/raum_behalten.md): Hauptmenü mit „Zurück ins Spiel“ (S24-Format, normal,
# sehr groß, Englisch), Gastgeber-Lobby mit dem gemerkten Raum („Gleicher Raumcode wie vorhin …“) und die Rückfrage „Lobby schließen?“
# mit dem Hinweis auf den Raumcode. Vermittler: NetRelayDouble auf 127.0.0.1. Wegen „_shot“ startet tools/build.ps1 das Skript nicht.
#   tools/godot_run.ps1 -Script res://tests/test_raum_behalten_shot.gd -Resolution 1600x720 -EnvPairs "SHOT_DIR=…"

const CleanExit := preload("res://tests/clean_exit.gd")
const RELAY_PORT := 24935
const SETTINGS_PATH := "user://test_raum_behalten_shot_einstellungen.json"
const KEEP_FILE := "user://eigener_raum_shot.json"

var out := ""
var shots := 0
var relay: NetRelayDouble
var lnav: ScreenNav


func _initialize() -> void:
	call_deferred("run")


func wait(t: float) -> void:
	await create_timer(t).timeout


func menu_shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out.path_join("raum_1616_%s.png" % file))
	shots += 1
	var probs := fit_problems(menu, Vector2(vp.size))
	if not probs.is_empty():
		print("BEFUND %s: %s" % [file, "; ".join(probs)])


func root_shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out.path_join("raum_1616_%s.png" % file))
	shots += 1


func run() -> void:
	out = OS.get_environment("SHOT_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://")
	DirAccess.make_dir_recursive_absolute(out)
	# Hauptmenü
	for v in [["menue_zurueck_normal", "normal", "de", false], ["menue_zurueck_update_sehr_gross", "sehr_gross", "de", true],
			["menue_zurueck_en_normal", "normal", "en", false]]:
		await open_menu(1560, 720, str(v[1]), str(v[2]), bool(v[3]), false, true)
		await wait(0.3)
		await menu_shot(str(v[0]))
	restore()
	# Lobby mit Vermittler-Nachbau
	relay = NetRelayDouble.new()
	root.add_child(relay)
	relay.start(RELAY_PORT, RELAY_PORT)
	var app := UiApp.app()
	var real_settings: AppSettings = app.settings if app != null else null
	if app != null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
		var st := AppSettings.new(SETTINGS_PATH)
		st.set_value("name", "Lena")
		st.set_value("vermittler", "http://127.0.0.1:%d" % RELAY_PORT)
		app.settings = st
	RoomKeeper.enabled = true
	RoomKeeper.save_path = KEEP_FILE
	GameStarter.test_speed = 0.0
	GameWifiPanel.net_stub = {"mode": "wlan", "urls": ["http://192.168.178.24:24690/"]}
	lnav = ScreenNav.new()
	lnav.autostart = false
	root.add_child(lnav)
	await wait(0.3)
	var lobby := HostLobbyScreen.new()
	lnav.push(lobby, false)
	await wait(0.6)
	lobby.host.autosave = false
	lobby.invite.show_way("online")
	lobby.invite.open_online()
	await wait(1.0)
	await root_shot("lobby_neuer_raum")
	var code := str(lobby.host.session.online_info().get("room", ""))
	lobby.host.session.add_local_player("Mia", "web")
	await wait(0.3)
	lobby.on_back()
	await wait(0.4)
	await root_shot("lobby_schliessen")
	if lobby._confirm != null:
		lobby._confirm.queue_free()
		lobby._confirm = null
	lobby.host.leave()
	lnav.go_back()
	await wait(0.5)
	var lobby2 := HostLobbyScreen.new()
	lnav.push(lobby2, false)
	await wait(1.0)
	lobby2.host.autosave = false
	print("Raum vorher %s, jetzt %s, gemerkt %s" % [code, str(lobby2.host.session.online_info().get("room", "")), lobby2.host.session.online_kept])
	await root_shot("lobby_gleicher_code")
	UiFonts.set_level("sehr_gross", root)
	await wait(0.5)
	await root_shot("lobby_gleicher_code_sehr_gross")
	UiFonts.set_level("normal", root)
	lobby2.host.session.close_online()
	lobby2.host.leave()
	RoomKeeper.discard()
	RoomKeeper.enabled = false
	GameWifiPanel.net_stub = null
	if app != null and real_settings != null:
		app.settings = real_settings
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	print("RESULT: %d Bilder nach %s" % [shots, out])
	await CleanExit.finish(self, 0)
