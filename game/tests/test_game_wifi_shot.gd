extends SceneTree
# Kontrollbilder Spiel-WLAN (Beta 1.0.1) mit echtem Renderer und PC-Stub: Lobby „Spiel eröffnen“ → „Spiel-WLAN öffnen“, Schritt 1
# (WLAN-QR), Schritt 2 (Spiel-QR), Fehler „normaler Hotspot läuft“. Wegen „_shot“ startet tools/build.ps1 das Skript nicht als Test.
#   tools/godot_run.ps1 -Script res://tests/test_game_wifi_shot.gd -Resolution 1600x720 -EnvPairs "SHOT_DIR=…"

const CleanExit := preload("res://tests/clean_exit.gd")

var out_dir := ""


func _initialize() -> void:
	call_deferred("run")


func wait(t: float) -> void:
	await create_timer(t).timeout


func shot(n: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("optik_spielwlan_%s.png" % n))


func run() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://")
	NetAndroid.wifi_stub = {"ssid": "AndroidShare_7k2m", "password": "q9w3e7r2t5y8u4i", "address": "10.94.17.1"}
	var nav := ScreenNav.new()
	nav.autostart = false
	root.add_child(nav)
	await wait(0.3)
	var lobby := HostLobbyScreen.new()
	nav.push(lobby, false)
	await wait(0.8)
	lobby.host.autosave = false
	shot("lobby")
	(lobby.find_child("SpielWlan", true, false) as Button).pressed.emit()
	await wait(0.5)
	shot("schritt1")
	var p := lobby.find_child("SpielWlan", true, false)
	for c in lobby.get_children():
		if c is GameWifiPanel:
			p = c
	(p as GameWifiPanel).set_step(1)
	await wait(0.3)
	shot("schritt2")
	(p as GameWifiPanel).close()
	NetAndroid.game_wifi_stop()
	NetAndroid.wifi_stub = {"ap_enabled": 1}
	GameWifiPanel.open(lobby, lobby.host)
	await wait(0.4)
	shot("hotspot_laeuft")
	lobby.host.leave()
	print("Bilder in ", out_dir)
	await CleanExit.finish(self, 0)
