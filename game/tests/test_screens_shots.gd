extends SceneTree
# Kontrollbilder der Menübildschirme mit echtem Renderer (nicht headless, wird von tools/build.ps1 wegen „_shot“ nicht als Test
# gestartet): Regeln (Übersicht, Anpassen oben und bei den Hausregeln mit Zusatzkarten), Einstellungen, Gastgeber-Lobby mit
# 5 Spielern (davon ein App-Gast), Gast-Lobby, Übungs-Einrichtung. Die Regeln in App.settings werden danach wiederhergestellt.
#   tools/godot_run.ps1 -Script res://tests/test_screens_shots.gd -Resolution 1600x720 -EnvPairs "SHOT_DIR=…"
# Optional SHOT_SIZE=2400x1080 (wie das S21) oder 1600x720 (Standard).

const CleanExit := preload("res://tests/clean_exit.gd")

var out_dir := ""
var nav: ScreenNav
var nav2: ScreenNav
var shots := 0


func _initialize() -> void:
	call_deferred("run")


func wait(t: float) -> void:
	await create_timer(t).timeout


func run() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://")
	var size_text := OS.get_environment("SHOT_SIZE")
	if size_text != "" and size_text.contains("x"):
		var p := size_text.split("x")
		root.size = Vector2i(int(p[0]), int(p[1]))
	GameStarter.test_speed = 0.0
	var backup: Variant = UiApp.setting("regeln", {})
	var app := UiApp.app()
	var hl_set: bool = app != null and app.settings.has_value("hervorheben")
	var hl_backup: Variant = UiApp.setting("hervorheben", true)
	var host_rules_backup: Variant = UiApp.setting("regeln_gastgeber", {})   # der App-Gast merkt sich die Regeln (RuleSets)
	var cfg := RuleConfig.preset("familie")
	cfg.gamble_cards = "on"
	cfg.discard_color = "on"
	if app != null:
		app.settings.set_value("regeln", cfg.to_dict())
	nav = ScreenNav.new()
	nav.autostart = false
	root.add_child(nav)
	await wait(0.3)
	# Regeln
	var rs := RulesScreen.new()
	nav.push(rs, false)
	await wait(0.8)
	shot("regeln_uebersicht")
	rs._overview.scroll_vertical = 900
	await wait(0.4)
	shot("regeln_uebersicht_hausregeln")
	rs._show_tab("anpassen")
	await wait(0.5)
	shot("regeln_anpassen")
	rs._editor.scroll_vertical = 100000
	await wait(0.5)
	shot("regeln_anpassen_hausregeln")
	rs.apply_preset("offiziell")
	await wait(0.4)
	shot("regeln_anpassen_offiziell")
	if app != null:
		app.settings.set_value("regeln", cfg.to_dict())
	nav.go_back()
	await wait(0.4)
	# Einstellungen
	nav.push(SettingsScreen.new(), false)
	await wait(0.8)
	shot("einstellungen")
	var st := nav.top()
	for s in st.find_children("*", "ScrollContainer", true, false):
		(s as ScrollContainer).scroll_vertical = 100000
	await wait(0.4)
	shot("einstellungen_unten")
	nav.go_back()
	await wait(0.4)
	# Übungs-Einrichtung (Regelzeile mit Hausregeln)
	nav.push(SoloSetupScreen.new(), false)
	await wait(0.6)
	shot("uebung_einrichtung")
	nav.go_back()
	await wait(0.4)
	# Gastgeber-Lobby mit App-Gast und Computergegnern (5 Spieler)
	var lobby := HostLobbyScreen.new()
	nav.push(lobby, false)
	await wait(0.6)
	var host := lobby.host
	nav2 = ScreenNav.new()
	nav2.autostart = false
	nav2.visible = false
	root.add_child(nav2)
	await wait(0.2)
	var join := JoinScreen.new()
	nav2.push(join, false)
	await wait(0.3)
	join.join("127.0.0.1", host.port())
	var deadline := Time.get_ticks_msec() + 6000
	while (host.lobby().get("players", []) as Array).size() < 2 and Time.get_ticks_msec() < deadline:
		await process_frame
	for i in 3:
		host.add_bot()
	await wait(0.8)
	shot("lobby_5_spieler")
	for i in 5:
		lobby._bot_plus.pressed.emit()       # wie ein Tipp auf „+“: die Liste rollt zum neuen Spieler
		await wait(0.15)
	await wait(0.8)
	shot("lobby_10_spieler")
	# Gast-Lobby (gleiche Größe)
	nav.visible = false
	nav2.visible = true
	await wait(0.6)
	shot("gast_lobby")
	join._ready_btn.button_pressed = true
	await wait(0.4)
	shot("gast_lobby_bereit")
	if app != null:
		app.settings.set_value("regeln", backup if backup is Dictionary else {})
		if hl_set:
			app.settings.set_value("hervorheben", hl_backup)
		else:
			app.settings.reset("hervorheben")
		if host_rules_backup is Dictionary and not (host_rules_backup as Dictionary).is_empty():
			app.settings.set_value("regeln_gastgeber", host_rules_backup)
		else:
			app.settings.reset("regeln_gastgeber")
	print("RESULT: %d ok" % shots)
	await CleanExit.finish(self, 0)


func shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join("screens_%s.png" % name))
	shots += 1
