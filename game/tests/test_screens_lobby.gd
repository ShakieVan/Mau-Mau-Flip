extends SceneTree
# Gastgeber-Lobby „Spiel eröffnen“ (Beta 1.0.2): Leucht- und Haken-Logik (InviteSteps) samt Rücksetzen, eigene Adressen, Signal
# „Spielseite abgerufen“ (NetServer/NetHostSession.page_visited), Lobby mit Stubs (Zustände von ①, ② mit Adresse), Kopfzeile,
# seitliches Blättern mit Einrasten, „So geht's“ und Platz in allen drei Schriftstufen bei 1600 × 720.
#   tools/godot_run.ps1 -Script res://tests/test_screens_lobby.gd -Resolution 1600x720

const CleanExit := preload("res://tests/clean_exit.gd")
const SETTINGS_PATH := "user://test_screens_lobby_einstellungen.json"
const PORT := 24931

var ok := 0
var failed := false
var nav: ScreenNav
var screen := Rect2(0, 0, 1600, 720)


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


func inside(inner: Rect2, outer: Rect2, tol := 1.0) -> bool:
	return outer.grow(tol).encloses(inner)


func run() -> void:
	GameStarter.test_speed = 0.0
	var app := UiApp.app()
	var real_settings: AppSettings = app.settings if app != null else null
	if app != null:
		_remove_files(SETTINGS_PATH)
		var st := AppSettings.new(SETTINGS_PATH)
		st.set_value("name", "Lena")
		app.settings = st
	root.size = Vector2i(1600, 720)
	steps_logic()
	own_addresses()
	await page_signal()
	nav = ScreenNav.new()
	nav.autostart = false
	root.add_child(nav)
	await frames(3)
	await lobby_states()
	await font_levels()
	NetAndroid.wifi_stub = null
	GameWifiPanel.net_stub = null
	UiFonts.set_level("normal", root)
	if app != null and real_settings != null:
		app.settings = real_settings
		_remove_files(SETTINGS_PATH)
	if failed:
		print("FAIL: test_screens_lobby")
	else:
		print("RESULT: %d ok" % ok)
	await CleanExit.finish(self, 1 if failed else 0)


func _remove_files(p: String) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(p + suffix):
			DirAccess.remove_absolute(p + suffix)


# --------------------------------------------------------------- Logik

func steps_logic() -> void:
	var s := InviteSteps.new()
	check(s.glow() == 1 and not s.step1_done() and not s.step2_done(), "ohne Netz leuchtet ①")
	s.set_net(true, "game_wifi")
	check(s.glow() == 1, "Spiel-WLAN offen: ① leuchtet weiter, bis die Seite aufgerufen wird")
	s.page_visited()
	check(s.step1_done() and s.glow() == 2 and not s.step2_done(), "Seite aufgerufen: Haken an ①, ② leuchtet")
	s.set_net(true, "starting")
	check(s.step1_done(), "Zwischenstand setzt nichts zurück")
	s.set_guests(1)
	check(s.step1_done() and s.step2_done() and s.glow() == 0, "erster Beitritt: beide Haken, nichts leuchtet")
	s.set_guests(2)
	s.set_guests(0)
	check(not s.step1_done() and s.glow() == 1, "kein Gast mehr: von vorn")
	s.page_visited()
	s.set_net(true, "none")
	check(not s.step1_done() and s.glow() == 1, "Spiel-WLAN geschlossen: von vorn")
	s.set_net(true, "wlan")
	s.page_visited()
	s.set_net(false, "wlan")
	check(not s.step1_done(), "Netz weg: von vorn")
	var t := InviteSteps.new()
	t.set_net(true, "wlan")
	t.set_guests(1)
	check(t.step1_done() and t.step2_done() and t.glow() == 0, "App-Gast ohne Seitenaufruf: beide Haken")
	check(HostLobbyScreen.guest_count({"host_id": 1, "players": [{"id": 1, "kind": "app"}, {"id": 2, "kind": "bot"}, {"id": 3, "kind": "web"},
		{"id": 4, "kind": "app"}]}) == 2, "Gäste ohne Gastgeber und Computer")


func own_addresses() -> void:
	check(NetHostSession.is_own_address("127.0.0.1", []) and NetHostSession.is_own_address("::1", []) and NetHostSession.is_own_address("::ffff:127.0.0.1", []),
		"Loopback ist eigen")
	check(NetHostSession.is_own_address("192.168.178.4", ["192.168.178.4", "fe80::1%wlan0"]) and NetHostSession.is_own_address("::ffff:192.168.178.4", ["192.168.178.4"]),
		"eigene Schnittstelle (auch IPv4 in IPv6)")
	check(not NetHostSession.is_own_address("192.168.178.20", ["192.168.178.4"]) and not NetHostSession.is_own_address("10.94.17.5", ["10.94.17.1"]),
		"fremdes Gerät")


func page_signal() -> void:
	var s := NetHostSession.new()
	s.use_discovery = false
	root.add_child(s)
	check(s.start("Lena", PORT, PORT, false) == OK, "Sitzung offen")
	var raw: Array = []
	var seen: Array = []
	s.server.page_visited.connect(func(a: String) -> void: raw.append(a))
	s.page_visited.connect(func(a: String) -> void: seen.append(a))
	await _http_get(PORT, "/info")
	await _http_get(PORT, "/?app=1")
	await frames(3)
	check(raw.size() == 1 and str(raw[0]).ends_with("127.0.0.1"), "Server meldet den Abruf von „/“, nicht /info (%s)" % str(raw))
	check(seen.is_empty(), "eigene Adresse zählt nicht")
	s.server.page_visited.emit("10.94.17.5")
	check(seen == ["10.94.17.5"], "fremdes Gerät wird gemeldet")
	s.stop()
	s.queue_free()
	await frames(2)


func _http_get(port: int, path: String) -> void:
	var c := HTTPClient.new()
	c.connect_to_host("127.0.0.1", port)
	var deadline := Time.get_ticks_msec() + 3000
	while c.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING] and Time.get_ticks_msec() < deadline:
		c.poll()
		await process_frame
	c.request(HTTPClient.METHOD_GET, path, [])
	while c.get_status() == HTTPClient.STATUS_REQUESTING and Time.get_ticks_msec() < deadline:
		c.poll()
		await process_frame
	while c.get_status() == HTTPClient.STATUS_BODY and Time.get_ticks_msec() < deadline:
		c.poll()
		c.read_response_body_chunk()
		await process_frame
	c.close()


# --------------------------------------------------------------- Lobby

func open_lobby() -> HostLobbyScreen:
	var lobby := HostLobbyScreen.new()
	nav.push(lobby, false)
	await frames(4)
	if lobby.host != null:
		lobby.host.autosave = false
	return lobby


func close_lobby(lobby: HostLobbyScreen) -> void:
	if lobby.invite != null and lobby.invite.wifi.mode == "game_wifi":
		lobby.invite.wifi.close_wifi()
	lobby.host.leave()
	nav.go_back()
	await wait(0.3)


func lobby_states() -> void:
	GameWifiPanel.net_stub = {"mode": "none", "urls": []}
	NetAndroid.wifi_stub = {"ssid": "AndroidShare_7k2m", "password": "q9w3e7r2t5y8u4i", "address": "10.94.17.1"}
	NetAndroid.game_wifi_stop()
	var lobby: HostLobbyScreen = await open_lobby()
	check(lobby.host != null and lobby.host.port() > 0, "Lobby offen")
	if lobby.host == null or lobby.host.port() <= 0:
		return
	var inv := lobby.invite
	var port := lobby.host.port()
	# Kopfzeile
	for b in [lobby._help_btn, lobby._rules_btn, lobby._start]:
		check((b as Button).is_visible_in_tree() and inside((b as Button).get_global_rect(), screen), "Kopfzeile: %s sichtbar" % (b as Button).text)
	check(lobby._start.disabled, "Start sichtbar, aber erst ab 2 Spielern aktiv")
	check(not (lobby.find_child("SpielWlan", true, false) is Button), "kein Knopf „Spiel-WLAN“ mehr in der Kopfzeile")
	# Blättern: Einladen offen, Spielerliste ragt ins Bild
	var guests_rect := lobby.pager.pages[1].get_global_rect()
	check(lobby.pager.page == 0 and guests_rect.position.x > 1300 and guests_rect.position.x < 1556, "Spielerliste ragt rechts ins Bild (%s)" % str(guests_rect))
	check(lobby.pager._hint.visible and lobby.pager._hint.side == 1, "Blätter-Hinweis am rechten Rand")
	# ① ohne Netz
	check(inv.wifi.mode == "none" and (inv.wifi.find_child("Oeffnen", true, false) as Button).is_visible_in_tree(), "①: großer Knopf „Spiel-WLAN öffnen“")
	check((inv.find_child("KeinNetz", true, false) as Control).is_visible_in_tree() and inv.game_url() == "", "②: „Noch kein WLAN aktiv“")
	check(inv.glows[0].active and not inv.glows[1].active and not inv.checks[0].visible and not inv.checks[1].visible, "① leuchtet")
	# Spiel-WLAN öffnen
	(inv.wifi.find_child("Oeffnen", true, false) as Button).pressed.emit()
	await frames(3)
	check(inv.wifi.mode == "game_wifi" and inv.wifi.qr_text().begins_with("WIFI:T:WPA;S:AndroidShare_7k2m;"), "①: WLAN-QR")
	check(inv.game_url() == "http://10.94.17.1:%d/" % port and (inv.find_child("Adresse", true, false) as Label).text == "10.94.17.1:%d" % port, "②: Spiel-QR und Adresse im Spiel-WLAN")
	check((inv.find_child("AppHinweis", true, false) as Label).is_visible_in_tree(), "②: Hinweis für App-Gäste")
	check(inv.glows[0].active and not inv.checks[0].visible, "① leuchtet bis zum ersten Aufruf")
	# Spielseite aufgerufen → Haken an ①, ② leuchtet
	lobby.host.session.page_visited.emit("10.94.17.5")
	await frames(1)
	check(inv.checks[0].visible and not inv.checks[1].visible and inv.glows[1].active and not inv.glows[0].active, "Seitenaufruf: Haken ①, ② leuchtet")
	# Gast tritt bei → beide Haken
	var gid := lobby.host.session.add_local_player("Mia", "web")
	await wait(0.2)
	check(inv.checks[0].visible and inv.checks[1].visible and not inv.glows[0].active and not inv.glows[1].active, "Beitritt: beide Haken, nichts leuchtet")
	check(not lobby._start.disabled, "Start mit 2 Spielern aktiv")
	lobby.host.remove_player(gid)
	await wait(0.2)
	check(not inv.checks[0].visible and not inv.checks[1].visible and inv.glows[0].active, "kein Gast mehr: von vorn")
	# Spiel-WLAN schließen setzt zurück
	lobby.host.session.page_visited.emit("10.94.17.5")
	await frames(1)
	(inv.find_child("Schliessen", true, false) as Button).pressed.emit()
	await frames(2)
	check(inv.wifi.mode == "none" and not inv.checks[0].visible and inv.glows[0].active, "Spiel-WLAN geschlossen: von vorn")
	# Effekte reduziert: ruhiger Leuchtrand
	UiApp.app().settings.set_value("effekte", "reduziert")
	inv.apply()
	check(inv.glows[0].reduced and inv.glows[0].active, "reduziert: ruhiger Rand")
	UiApp.app().settings.set_value("effekte", "voll")
	inv.apply()
	# ① im WLAN und mit Hotspot
	GameWifiPanel.net_stub = {"mode": "wlan", "urls": ["http://192.168.178.24:%d/" % port]}
	inv.wifi.refresh_net()
	await frames(1)
	check(inv.wifi.mode == "wlan" and (inv.wifi.find_child("EigenesWlan", true, false) as Button).is_visible_in_tree() and inv.game_url() == "http://192.168.178.24:%d/" % port,
		"im WLAN: dasselbe WLAN und „Lieber eigenes Spiel-WLAN“, ② nutzbar")
	GameWifiPanel.net_stub = {"mode": "hotspot", "urls": ["http://192.168.43.1:%d/" % port]}
	inv.wifi.refresh_net()
	check(inv.wifi.mode == "hotspot" and inv.game_url() == "http://192.168.43.1:%d/" % port, "Hotspot: ② nutzbar")
	# Blättern per Wischen (mit Einrasten) und per Tipp auf den Hinweis
	await _swipe(lobby.pager, Vector2(1100, 420), Vector2(700, 430))
	await wait(0.5)
	check(lobby.pager.page == 1 and inside(lobby.pager.pages[1].get_global_rect(), screen), "Wischen nach links: Spielerliste eingerastet (%s)" % str(lobby.pager.pages[1].get_global_rect()))
	check(lobby.pager._hint.visible and lobby.pager._hint.side == -1, "Blätter-Hinweis jetzt links")
	await _swipe(lobby.pager, Vector2(700, 420), Vector2(660, 420))
	await wait(0.5)
	check(lobby.pager.page == 1, "kurzer Weg: federt zurück")
	lobby.pager._hint.pressed.emit()
	await wait(0.5)
	check(lobby.pager.page == 0 and is_equal_approx(lobby.pager.pages[0].get_global_rect().position.x, 44.0), "Tipp auf den Hinweis blättert zurück")
	# So geht's
	lobby._help_btn.pressed.emit()
	await frames(2)
	check(lobby._help != null and lobby._help.is_visible_in_tree() and lobby.pager._is_blocked(), "„So geht's“ offen, Blättern gesperrt")
	var handled := lobby.on_back()
	var gone: bool = await _gone(lobby, "SoGehts")
	check(handled and gone, "Zurück schließt „So geht's“")
	await close_lobby(lobby)


func _swipe(p: LobbyPager, from: Vector2, to: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	down.global_position = from
	p._input(down)
	for i in range(1, 7):
		var m := InputEventMouseMotion.new()
		m.position = from.lerp(to, i / 6.0)
		m.global_position = m.position
		p._input(m)
		await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = to
	up.global_position = to
	p._input(up)


func _gone(n: Node, child_name: String) -> bool:
	await frames(2)
	return n.find_child(child_name, false, false) == null


# Platz bei 1600 × 720 in allen Schriftstufen: Kopfzeile, beide Schritte ohne Überlauf, 5 Spieler ganz sichtbar
func font_levels() -> void:
	NetAndroid.wifi_stub = {"ssid": "AndroidShare_7k2m", "password": "q9w3e7r2t5y8u4i", "address": "10.94.17.1"}
	for lvl in ["normal", "gross", "sehr_gross"]:
		UiFonts.set_level(lvl, root)
		GameWifiPanel.net_stub = {"mode": "none", "urls": []}
		var lobby: HostLobbyScreen = await open_lobby()
		if lobby.host == null:
			check(false, "Lobby %s" % lvl)
			continue
		lobby.invite.wifi.open_wifi()
		for i in 4:
			lobby.host.add_bot()
		await wait(0.3)
		for b in [lobby._help_btn, lobby._rules_btn, lobby._start]:
			check(inside((b as Button).get_global_rect(), screen), "%s: %s im Bild" % [lvl, (b as Button).text])
		for n in 2:
			var slot := lobby.invite.find_child("Schritt%d" % (n + 1), true, false) as Control
			var need := slot.get_combined_minimum_size().y
			check(inside(slot.get_global_rect(), screen) and need <= slot.size.y + 1.0, "%s: Schritt %d passt (braucht %d, hat %d)" % [lvl, n + 1, need, slot.size.y])
		lobby.show_page(1, false)
		await frames(3)
		var area := lobby._scroll.get_global_rect()
		var rows := lobby._list.get_children()
		var all_in := rows.size() == 5
		for r in rows:
			all_in = all_in and inside((r as Control).get_global_rect(), area)
		check(all_in or lvl != "normal", "%s: 5 Spieler ganz sichtbar" % lvl)
		check(inside(lobby._bot_plus.get_global_rect(), screen) and inside(lobby._count.get_global_rect(), screen) and inside(lobby._rules.get_global_rect(), screen),
			"%s: Spielerzahl, Computer und Regeln im Bild" % lvl)
		await close_lobby(lobby)
