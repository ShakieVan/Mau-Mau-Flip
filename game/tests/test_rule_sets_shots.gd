extends SceneTree
# Kontrollbilder der gespeicherten Regelsätze mit echtem Renderer (nicht headless; wegen „_shot“ startet tools/build.ps1 das Skript
# nicht als Test): Regel-Editor mit Sätzen und „Zuletzt gespielt bei Lena“ (vorn), Speichern-Dialog, Rückfrage zum Überschreiben
# (eigene Zeile), 12 lange Namen, Löschen per Gedrückthalten, voller Speicher, Übung mit Knopf „Gespeichert“ und Auswahl, Gast-Lobby
# mit „Regeln speichern“ (vorher und nachher), Spielmenü des Gastes (Dialog über der Rückfrage), Leiste „Verbindung zum Gastgeber
# beendet.“ mit „Selbst eröffnen“, die so eröffnete Lobby, Gastgeber-Lobby mit dem Angebot „Regeln von Lena“ (übernehmen).
# Läuft mit eigener Einstellungsdatei (App.settings wird ersetzt), die echten Einstellungen bleiben unberührt.
#   tools/godot_run.ps1 -Script res://tests/test_rule_sets_shots.gd -Resolution 1600x720 -EnvPairs "SHOT_DIR=…"

const CleanExit := preload("res://tests/clean_exit.gd")
const PORT := 24896
const SETTINGS_PATH := "user://test_rule_sets_shots_einstellungen.json"
const LONG_NAMES := ["Ferienhaus Ostsee 26", "Weihnachten bei Oma", "WWWWWWWWWWWWWWWWWWWW", "Kneipenabend Freitag", "Schnelle Runde (3+4)",
	"Kinder & Großeltern", "Turnier Vereinsheim", "Zu zweit im Zug", "Lange Nacht 500 Pkt", "Mau-Mau klassisch", "Probe Glücksspiel", "Sonntag Nachmittag"]

var out_dir := ""
var nav: ScreenNav
var nav2: ScreenNav
var shots := 0
var _real: AppSettings


func _initialize() -> void:
	call_deferred("run")


func wait(t: float) -> void:
	await create_timer(t).timeout


func run() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://")
	GameStarter.test_speed = 0.0
	var app := UiApp.app()
	_real = app.settings
	_remove_files(SETTINGS_PATH)
	var st := AppSettings.new(SETTINGS_PATH)
	st.set_value("name", "Ben")
	app.settings = st
	var lena := RuleConfig.preset("familie")
	lena.gamble_cards = "on"
	lena.discard_color = "on"
	lena.hand_size = 6
	var oma := RuleConfig.preset("familie")
	oma.hand_size = 9
	oma.mau_call = "reminder"
	var kneipe := RuleConfig.preset("klassisch500")
	kneipe.target = 300
	RuleSets.save("Oma-Regeln", oma)
	RuleSets.save("Kneipe", kneipe)
	RuleSets.save("Urlaub 2026", lena)
	RuleSets.remember_host(lena.to_dict(), "Lena")
	RulesBar.store(oma)
	nav = ScreenNav.new()
	nav.autostart = false
	root.add_child(nav)
	await wait(0.3)
	RuleSets.choose("Oma-Regeln")
	# Regel-Editor
	var rs := RulesScreen.new()
	rs.start_tab = "anpassen"
	nav.push(rs, false)
	await wait(0.8)
	shot("regeln")
	rs.apply_host_rules()
	await wait(0.3)
	shot("regeln_gastgeber")
	rs.set_option("hand_size", 8)
	RuleSets.choose("Urlaub 2026")
	rs.save_as()
	await wait(0.5)
	shot("speichern")
	rs._save_box.confirm()
	await wait(0.3)
	shot("ueberschreiben")
	rs._save_box.cancel()
	await wait(0.3)
	rs.save_as()
	await wait(0.3)
	rs._save_box.field.text = ""
	rs._save_box.confirm()
	await wait(0.2)
	shot("speichern_leer")
	rs._save_box.cancel()
	await wait(0.2)
	nav.go_back()
	await wait(0.4)
	# 12 lange Namen und ein Gastgeber mit langem Namen
	var keep := RuleSets.list()
	st.reset(RuleSets.KEY)
	for i in LONG_NAMES.size():
		var c := RuleConfig.new()
		c.hand_size = 5 + (i % 6)
		c.mau_penalty = 1 + (i % 4)
		if i == 2:
			c.gamble_cards = "on"
		RuleSets.save(LONG_NAMES[i], c)
	RuleSets.remember_host(lena.to_dict(), "Maximilian12")
	RulesBar.store(RuleSets.config("Kinder & Großeltern"))
	RuleSets.choose("Kinder & Großeltern")
	rs = RulesScreen.new()
	rs.start_tab = "anpassen"
	nav.push(rs, false)
	await wait(0.8)
	shot("zwoelf")
	rs.ask_delete("Ferienhaus Ostsee 26")
	await wait(0.4)
	shot("loeschen")
	rs._confirm.cancel()
	await wait(0.2)
	rs.save_as()
	await wait(0.3)
	rs._save_box.field.text = "Dreizehn"
	rs._save_box.confirm()
	await wait(0.3)
	shot("voll")
	rs._save_box.cancel()
	await wait(0.2)
	nav.go_back()
	await wait(0.4)
	# Übung: Knopf „Gespeichert“ und Auswahl
	RulesBar.store(RuleSets.config("Weihnachten bei Oma"))
	RuleSets.choose("Weihnachten bei Oma")
	var solo := SoloSetupScreen.new()
	nav.push(solo, false)
	await wait(0.6)
	shot("uebung")
	solo._rules.open_picker()
	await wait(0.5)
	shot("uebung_auswahl")
	solo._rules.close_picker()
	nav.go_back()
	await wait(0.4)
	st.set_value(RuleSets.KEY, keep)
	RuleSets.remember_host(lena.to_dict(), "Lena")
	RuleSets.remove("Urlaub 2026")
	# Gast-Lobby bei Lena
	var host := HostTable.new()
	host.use_discovery = false
	host.autosave = false
	host.speed = 0.0
	host.set_rules(lena)
	root.add_child(host)
	host.open("Lena", PORT, PORT)
	host.add_bot()
	host.add_bot()
	nav.visible = false
	nav2 = ScreenNav.new()
	nav2.autostart = false
	root.add_child(nav2)
	await wait(0.2)
	var join := JoinScreen.new()
	nav2.push(join, false)
	await wait(0.3)
	join.join("127.0.0.1", PORT)
	var deadline := Time.get_ticks_msec() + 6000
	while join.host_rules == null and Time.get_ticks_msec() < deadline:
		await process_frame
	await wait(0.6)
	shot("gast_lobby")
	join.save_rules()
	await wait(0.5)
	shot("gast_speichern")
	join._save_box.field.text = "Lenas Runde"
	join._save_box.confirm()
	await wait(0.4)
	shot("gast_gespeichert")
	# Spielmenü des Gastes
	host.start()
	deadline = Time.get_ticks_msec() + 6000
	while not (nav2.top() is TableScreen and not (nav2.top() as TableScreen).view.is_empty()) and Time.get_ticks_msec() < deadline:
		await process_frame
	await wait(2.0)
	var gts := nav2.top() as TableScreen
	if gts != null:
		gts.on_back()
		await wait(0.5)
		shot("spielmenue")
		var opt := gts._confirm.find_child("RegelnSpeichern", true, false) as Button
		opt.pressed.emit()
		await wait(0.5)
		shot("spielmenue_speichern")
		gts._save_box.cancel()
		await wait(0.2)
		gts.on_back()
		await wait(0.2)
		host.leave()
		await wait(1.0)
		gts._on_connection("closed")
		await wait(0.4)
		shot("verbindung_beendet")
		RulesBar.store(RuleConfig.preset("offiziell"))
		gts._conn_host.pressed.emit()
		await wait(0.8)
		var own := nav2.top() as HostLobbyScreen
		if own != null and own.host != null:
			own.host.autosave = false
			own.host.add_bot()
			await wait(0.4)
			shot("selbst_eroeffnet")
			own.host.leave()
	await wait(0.4)
	nav2.queue_free()
	host.queue_free()
	await wait(0.3)
	# Dieses Gerät eröffnet später über das Menü: Lobby bietet die Regeln des letzten Gastgebers an, danach steht der Name da
	nav.visible = true
	RulesBar.store(RuleConfig.preset("offiziell"))
	var lobby := HostLobbyScreen.new()
	nav.push(lobby, false)
	await wait(0.8)
	lobby.host.autosave = false
	lobby.host.add_bot()
	lobby.host.add_bot()
	await wait(0.5)
	shot("lobby_angebot")
	lobby._rules._offer_btn.pressed.emit()
	await wait(0.4)
	shot("lobby")
	lobby.host.leave()
	nav.go_back()
	await wait(0.3)
	app.settings = _real
	_remove_files(SETTINGS_PATH)
	print("RESULT: %d ok" % shots)
	await CleanExit.finish(self, 0)


func _remove_files(p: String) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(p + suffix):
			DirAccess.remove_absolute(p + suffix)


func shot(shot_name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join("optik_regelsaetze_%s.png" % shot_name))
	shots += 1
