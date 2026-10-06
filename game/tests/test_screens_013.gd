extends SceneTree
# Oberfläche 0.1.3, headless mit echten Bildschirmen und echtem Netz über 127.0.0.1:
#  T   Regler „Tempo der Computergegner“ (Einstellungen, persönlich je Gerät): speichert bot_tempo, GameStarter gibt den Faktor
#      an LocalTable/HostTable weiter (nur Bedenkzeit).
#  M4  Getrennter Gast: Der Gastgeber sieht am Tisch „Computer spielt für …“, Rückfrage, substitute_bot(); kommt der Gast zurück,
#      spielt er selbst weiter (Vertretung endet).
#  N6  Gast verliert nach dem Spielende die Verbindung und der Gastgeber ist weg: nach einem gescheiterten Versuch
#      „Spiel beendet.“ mit „Zum Menü“ statt endlos „Verbinde neu …“.
#   godot_run.ps1 -Script res://tests/test_screens_013.gd -Headless -Timeout 150

const CleanExit := preload("res://tests/clean_exit.gd")

var ok := 0
var failed := false
var nav: ScreenNav
var nav2: ScreenNav
var nav3: ScreenNav


func _initialize() -> void:
	call_deferred("run")


func check(cond: bool, what: String) -> void:
	if cond:
		ok += 1
	else:
		failed = true
		print("FAIL: " + what)


func frames(n := 2) -> void:
	for i in n:
		await process_frame


func wait(t: float) -> void:
	await create_timer(t).timeout


func _wait_for(cond: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not bool(cond.call()) and Time.get_ticks_msec() < deadline:
		await frames(1)
	return bool(cond.call())


func run() -> void:
	GameStarter.test_speed = 0.0
	var app := UiApp.app()
	var rules_backup: Variant = UiApp.setting("regeln", {})
	var had_tempo: bool = app != null and app.settings.has_value("bot_tempo")
	var tempo_backup: Variant = UiApp.setting("bot_tempo", 0.5)
	root.size = Vector2i(1600, 720)
	nav = ScreenNav.new()
	nav.autostart = true
	root.add_child(nav)
	await frames(3)
	await tempo()
	await net_flow()
	if app != null:
		app.settings.set_value("regeln", rules_backup if rules_backup is Dictionary else {})
		if had_tempo:
			app.settings.set_value("bot_tempo", tempo_backup)
		else:
			app.settings.reset("bot_tempo")
	if failed:
		print("FAIL: test_screens_013")
	else:
		print("RESULT: %d ok" % ok)
	await CleanExit.finish(self, 1 if failed else 0)


# ----------------------------------------------------------------- Tempo der Computergegner

func tempo() -> void:
	var app := UiApp.app()
	if app == null:
		check(false, "App fehlt")
		return
	app.settings.reset("bot_tempo")
	check(is_equal_approx(GameStarter.bot_think_factor(), 1.0), "Tempo: Standard wie bisher (Faktor 1)")
	var ss := SettingsScreen.new()
	nav.push(ss, false)
	await frames(3)
	var slider := ss.find_child("TempoRegler", true, false) as HSlider
	check(slider != null and is_equal_approx(slider.value, 0.5), "Tempo: Regler in den Einstellungen, Mitte")
	if slider == null:
		return
	var texts := ""
	for l in ss.find_child("Tempo", true, false).find_children("*", "Label", true, false):
		texts += (l as Label).text + " "
	check(texts.contains("gemütlich") and texts.contains("flott") and texts.contains("Gastgeber"), "Tempo: Beschriftung mit Hinweis auf den Gastgeber")
	slider.value = 1.0
	await frames(1)
	check(is_equal_approx(float(UiApp.setting("bot_tempo", 0.0)), 1.0) and GameStarter.bot_think_factor() < 0.5, "Tempo: flott gespeichert, kürzere Bedenkzeit")
	var t := GameStarter.local("solo", RuleConfig.new(), [{"name": "Ich", "kind": "human"}, {"name": "Bot", "kind": "bot"}], 7)
	check(t != null and t.think_factor < 0.5 and is_equal_approx(t.speed, 0.0), "Tempo: LocalTable bekommt den Faktor, Animationstempo unberührt")
	if t != null:
		t.free()
	slider.value = 0.0
	await frames(1)
	check(GameStarter.bot_think_factor() > 2.0, "Tempo: gemütlich")
	nav.pop()
	await frames(2)


# ----------------------------------------------------------------- M4 und N6 im Netz

func _guest_nav() -> ScreenNav:
	var n := ScreenNav.new()
	n.autostart = false
	root.add_child(n)
	return n


func _guest_entry(host: HostTable) -> Dictionary:
	var l := host.lobby()
	for p in l.get("players", []):
		if str(p.get("kind", "")) == "app" and int(p.get("id", -1)) != int(l.get("host_id", -1)):
			return p
	return {}


func net_flow() -> void:
	UiApp.app().settings.set_value("regeln", RuleConfig.new().to_dict())
	nav.push(HostLobbyScreen.new(), false)
	await frames(3)
	var lobby := nav.top() as HostLobbyScreen
	check(lobby != null and lobby.host != null and lobby.host.port() > 0, "Lobby des Gastgebers offen")
	if lobby == null or lobby.host == null or lobby.host.port() <= 0:
		return
	var host := lobby.host
	host.autosave = false
	var port := host.port()
	nav2 = _guest_nav()
	await frames(2)
	nav2.push(JoinScreen.new(), false)
	await frames(2)
	(nav2.top() as JoinScreen).join("127.0.0.1", port)
	check(await _wait_for(func() -> bool: return not _guest_entry(host).is_empty(), 6.0), "App-Gast in der Lobby")
	await wait(0.3)
	host.add_bot()
	await wait(0.3)
	lobby.start_game()
	await wait(0.6)
	var hts := nav.top() as TableScreen
	check(await _wait_for(func() -> bool: return nav2.top() is TableScreen and not ((nav2.top() as TableScreen).view.get("hand", []) as Array).is_empty(), 5.0), "App-Gast am Tisch")
	var gts := nav2.top() as TableScreen
	if hts == null or gts == null:
		return
	var seat := int(gts.view.get("seat", -1))
	var gname := host.seat_name(seat)
	check(not hts._sub_btn.visible, "M4: ohne getrennten Gast kein Knopf")
	# Gast weg (App abgewürgt)
	nav2.queue_free()
	nav2 = null
	check(await _wait_for(func() -> bool: return host.game != null and not bool(host.game.connected[seat]), 4.0), "M4: Gastgeber sieht den Gast getrennt")
	check(await _wait_for(func() -> bool: return hts._sub_btn.visible, 2.0) and hts._sub_btn.text == "Computer spielt für %s" % gname,
		"M4: Knopf „Computer spielt für %s“ (%s)" % [gname, hts._sub_btn.text])
	var r := hts._sub_btn.get_global_rect()
	check(Rect2(0, 0, 1600, 720).encloses(r), "M4: Knopf im Bild")
	hts.ask_substitute()
	check(hts._confirm != null and is_instance_valid(hts._confirm), "M4: Rückfrage")
	hts._confirm._answer(true)
	await frames(2)
	check(host.is_substituted(seat) and not hts._sub_btn.visible, "M4: Computer spielt für den Gast, Knopf weg")
	await wait(0.5)
	# Gast kommt zurück: spielt selbst weiter
	nav3 = _guest_nav()
	await frames(2)
	nav3.push(JoinScreen.new(), false)
	await frames(2)
	(nav3.top() as JoinScreen).join("127.0.0.1", port)
	check(await _wait_for(func() -> bool: return nav3.top() is TableScreen, 5.0), "M4: Gast kommt zurück an den Tisch")
	check(await _wait_for(func() -> bool: return host.game != null and bool(host.game.connected[seat]), 3.0) and not host.is_substituted(seat),
		"M4: Platz wieder beim Gast, Vertretung beendet")
	var rts := nav3.top() as TableScreen
	if rts == null or not rts.source is ClientTable:
		return
	# N6: Spielende, Gast verliert die Verbindung, Gastgeber geht ins Menü
	var ct := rts.source as ClientTable
	await wait(0.3)
	ct.current_view()["phase"] = "game_over"
	ct.client.retry_ms = [200]
	ct.client.connect_timeout_ms = 1500
	ct.client._lost("Hintergrund (Test)")
	hts._leave_now()
	check(await _wait_for(func() -> bool: return rts._conn.visible and rts._conn_label.text == "Spiel beendet.", 15.0),
		"N6: „Spiel beendet.“ statt „Verbinde neu …“ (%s; %s, Versuche %d, Phase %s)" % [rts._conn_label.text, ct.connection_state(), ct.client.attempts if ct.client != null else -1, str(ct.current_view().get("phase", ""))])
	check(rts._conn_menu.visible and ct.connection_state() == "ended", "N6: Weg ins Menü, Verbindung aufgegeben")
	rts._leave_now()
	await wait(0.5)
