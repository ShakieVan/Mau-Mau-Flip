extends SceneTree
# Kontrollbilder der Gastgeber-Lobby (Beta 1.0.2), Tag, 1600 × 720, mit Stubs für Netz und Spiel-WLAN: je Schriftstufe Einladen
# (Spiel-WLAN offen, Seite aufgerufen → ② leuchtet), Spielerliste mit 2 und mit 8 Gästen; dazu in „Normal“ ① ohne Netz, im WLAN,
# beide Haken und „So geht's“. Wegen „_shot“ startet tools/build.ps1 das Skript nicht als Test.
#   tools/godot_run.ps1 -Script res://tests/test_screens_lobby_shot.gd -Resolution 1600x720 -EnvPairs "SHOT_DIR=…"

const CleanExit := preload("res://tests/clean_exit.gd")
const SETTINGS_PATH := "user://test_screens_lobby_shot_einstellungen.json"
const NAMES := ["Mia", "Ben", "Oma Gerda", "Jonas", "Lea", "Paul", "Sophie", "Tim"]

var out_dir := ""
var nav: ScreenNav


func _initialize() -> void:
	call_deferred("run")


func wait(t: float) -> void:
	await create_timer(t).timeout


func shot(n: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("lobby_102_%s.png" % n))


func run() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://")
	GameStarter.test_speed = 0.0
	var app := UiApp.app()
	var real_settings: AppSettings = app.settings if app != null else null
	if app != null:
		var st := AppSettings.new(SETTINGS_PATH)
		st.set_value("name", "Lena")
		app.settings = st
	NetAndroid.wifi_stub = {"ssid": "AndroidShare_7k2m", "password": "q9w3e7r2t5y8u4i", "address": "10.94.17.1"}
	nav = ScreenNav.new()
	nav.autostart = false
	root.add_child(nav)
	await wait(0.3)
	for lvl in ["normal", "gross", "sehr_gross"]:
		UiFonts.set_level(lvl, root)
		GameWifiPanel.net_stub = {"mode": "none", "urls": []}
		var lobby := await open_lobby()
		if lvl == "normal":
			shot("ohne_netz")
		lobby.invite.wifi.open_wifi()
		await wait(0.3)
		if lvl == "normal":
			shot("spielwlan_offen")
		lobby.host.session.page_visited.emit("10.94.17.5")
		await wait(0.4)
		shot("%s_einladen" % lvl)
		for i in 2:
			lobby.host.session.add_local_player(NAMES[i], "web" if i % 2 == 0 else "app")
		await wait(0.3)
		if lvl == "normal":
			shot("beide_haken")
		lobby.show_page(1, false)
		await wait(0.4)
		shot("%s_2_gaeste" % lvl)
		for i in range(2, 8):
			lobby.host.session.add_local_player(NAMES[i], "web" if i % 2 == 0 else "app")
		await wait(0.4)
		shot("%s_8_gaeste" % lvl)
		if lvl == "normal":
			lobby.show_page(0, false)
			lobby.invite.wifi.close_wifi()
			GameWifiPanel.net_stub = {"mode": "wlan", "urls": ["http://192.168.178.24:%d/" % lobby.host.port()]}
			lobby.invite.wifi.refresh_net()
			await wait(0.3)
			shot("im_wlan")
			lobby.open_help()
			await wait(0.4)
			shot("so_gehts")
			lobby._help.close()
		if lobby.invite.wifi.mode == "game_wifi":
			lobby.invite.wifi.close_wifi()
		lobby.host.leave()
		nav.go_back()
		await wait(0.3)
	UiFonts.set_level("normal", root)
	NetAndroid.wifi_stub = null
	GameWifiPanel.net_stub = null
	if app != null and real_settings != null:
		app.settings = real_settings
	print("Bilder in ", out_dir)
	await CleanExit.finish(self, 0)


func open_lobby() -> HostLobbyScreen:
	var lobby := HostLobbyScreen.new()
	nav.push(lobby, false)
	await wait(0.6)
	lobby.host.autosave = false
	return lobby
