extends SceneTree
# Nachbesserung nach dem Gerätetest 0.1.1 (docs/geraetetest/0.1.1/BERICHT.md), headless mit echten Bildschirmen:
#  H1  Lobby → Start → Tisch: Der Server des Gastgebers läuft weiter (/info antwortet, „running“), die Spieler bleiben, die Partie
#      läuft und der Gastgeber hat eine Hand. Der App-Gast (Beitreten → Tisch, ClientTable wird umgehängt) bleibt verbunden und
#      bekommt seine Hand. Verlässt der Gastgeber, sieht der Gast „Verbindung beendet“.
#  M1  Android meldet einen Druck auf Zurück doppelt (NOTIFICATION_WM_GO_BACK_REQUEST und KEY_BACK): genau ein Schritt. Lobby: eine
#      Rückfrage, Zurück schließt sie wieder. Tisch: „Partie verlassen?“ bleibt offen. Regeln: zurück ins Hauptmenü, nicht weiter.
#  M2  Bildlauf per Wischen über Karten und Knöpfe (Einstellungen, Regeln); ein Knopf löst beim Wischen nicht aus, ein Tipp schon.
#  N1  „Bereit“ des App-Gasts liegt im sichtbaren Bereich, auch mit langem Regeltext.
#  N2  Spielerliste der Gastgeber-Lobby blättert per Wischen (gleicher Bildlauf wie M2).
#   godot_run.ps1 -Script res://tests/test_screens_device_fixes.gd -Headless -Timeout 120

const CleanExit := preload("res://tests/clean_exit.gd")

var ok := 0
var failed := false
var nav: ScreenNav
var nav2: ScreenNav


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


func run() -> void:
	GameStarter.test_speed = 0.0
	var settings_backup: Variant = UiApp.setting("regeln", {})
	var host_rules_backup: Variant = UiApp.setting("regeln_gastgeber", {})   # der App-Gast merkt sich die Regeln (RuleSets)
	root.size = Vector2i(2400, 1080)       # wie das S21 (headless wäre das Fenster 64 × 64, sichtbar dann 1600 × 1600)
	await frames(2)
	nav = ScreenNav.new()
	root.add_child(nav)
	await frames(3)
	check(nav.top() is MainMenuScreen, "Start im Hauptmenü")
	await back_key_pages()
	await swipe_settings()
	await swipe_rules()
	await background_cache()
	await net_flow()
	var app := UiApp.app()
	if app != null:
		app.settings.set_value("regeln", settings_backup if settings_backup is Dictionary else {})
		if host_rules_backup is Dictionary and not (host_rules_backup as Dictionary).is_empty():
			app.settings.set_value("regeln_gastgeber", host_rules_backup)
		else:
			app.settings.reset("regeln_gastgeber")
	if failed:
		print("FAIL: test_screens_device_fixes")
	else:
		print("RESULT: %d ok" % ok)
	await CleanExit.finish(self, 1 if failed else 0)


# ----------------------------------------------------------------- Hilfen

func press(n: ScreenNav, name: String) -> bool:
	var b := n.top().find_child(name, true, false) as BaseButton
	if b == null:
		print("Knopf fehlt: " + name)
		return false
	b.pressed.emit()
	return true


# Ein Druck auf die Android-Zurück-Taste, wie Godot ihn meldet: Benachrichtigung und Taste im selben Augenblick
func android_back(n: ScreenNav) -> void:
	n.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	var k := InputEventKey.new()
	k.keycode = KEY_BACK
	k.pressed = true
	n._unhandled_input(k)


func mouse_button(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	e.position = pos
	e.global_position = pos
	root.push_input(e, true)


func mouse_move(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.velocity = rel * 60.0
	root.push_input(e, true)


# Finger aufsetzen, in Schritten um delta ziehen, loslassen
func swipe(from: Vector2, delta: Vector2, steps := 12) -> void:
	mouse_button(from, true)
	await frames(1)
	for i in steps:
		mouse_move(from + delta * float(i + 1) / float(steps), delta / float(steps))
		await frames(1)
	mouse_button(from + delta, false)
	await frames(2)


func tap(pos: Vector2) -> void:
	mouse_button(pos, true)
	await frames(1)
	mouse_button(pos, false)
	await frames(2)


func first_scroll(n: Node) -> ScrollContainer:
	for c in n.find_children("*", "ScrollContainer", true, false):
		if (c as ScrollContainer).is_visible_in_tree():
			return c
	return null


# Steuerelemente im Bildlauf, die die Wischgeste abfangen würden (STOP), außer Eingabefeldern und Reglern
func blockers(scroll: ScrollContainer) -> Array:
	var out := []
	for c in scroll.find_children("*", "Control", true, false):
		var ctl := c as Control
		if ctl.mouse_filter == Control.MOUSE_FILTER_STOP and not (ctl is LineEdit or ctl is Range or ctl is ScrollBar):
			out.append("%s (%s)" % [ctl.name, ctl.get_class()])
	return out


# Ein sichtbarer Knopf im Bildlauf (Mitte im sichtbaren Bereich)
func visible_button(scroll: ScrollContainer, wanted := "") -> BaseButton:
	var area := scroll.get_global_rect().grow(-20.0)
	for c in scroll.find_children(wanted if wanted != "" else "*", "BaseButton", true, false):
		var b := c as BaseButton
		if b.is_visible_in_tree() and not b.disabled and area.has_point(b.get_global_rect().get_center()):
			return b
	return null


# ----------------------------------------------------------------- M1: Zurück auf einfachen Seiten

func back_key_pages() -> void:
	for key in ["Regeln", "Einstellungen"]:
		press(nav, key)
		await wait(0.3)
		check(nav.depth() == 2, "%s geöffnet" % key)
		android_back(nav)
		await wait(0.3)
		check(nav.top() is MainMenuScreen and nav.depth() == 1, "Zurück-Taste aus %s → Hauptmenü (ein Schritt)" % key)
		await wait(0.8)
	# Gehaltene Taste: Android wiederholt die Benachrichtigung nach gut 0,5 s und dann alle 50 ms – trotzdem nur ein Schritt
	nav.push(RulesScreen.new(), false)
	nav.push(SettingsScreen.new(), false)
	await frames(2)
	check(nav.depth() == 3, "zwei Seiten übereinander")
	android_back(nav)
	await wait(0.52)
	for i in 4:
		nav.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		await wait(0.05)
	await wait(0.3)
	check(nav.depth() == 2, "Gehaltene Zurück-Taste: ein Schritt (Tiefe %d)" % nav.depth())
	await wait(0.8)
	android_back(nav)
	await wait(0.3)
	check(nav.depth() == 1 and nav.top() is MainMenuScreen, "nächster Druck: nächster Schritt")
	await wait(0.8)


# ----------------------------------------------------------------- M2: Wischen in den Einstellungen

func swipe_settings() -> void:
	press(nav, "Einstellungen")
	await wait(0.35)
	var st := nav.top() as SettingsScreen
	check(st != null, "Einstellungen offen")
	if st == null:
		return
	var scroll := first_scroll(st)
	check(scroll is ScreenKit.TouchScroll, "Einstellungen: Bildlauf mit Wischen")
	if scroll == null:
		return
	await frames(2)
	check(blockers(scroll).is_empty(), "Einstellungen: nichts fängt die Wischgeste ab %s" % str(blockers(scroll)))
	check(DisplayServer.is_touchscreen_available(), "Touchscreen-Nachbildung aktiv (input_devices/pointing/emulate_touch_from_mouse)")
	var bar := scroll.get_v_scroll_bar()
	check(bar.max_value > scroll.size.y + 40.0, "Einstellungen länger als der Bildschirm (%d > %d)" % [int(bar.max_value), int(scroll.size.y)])
	# Wischen über eine Kartenüberschrift (Label → Karte → Bildlauf)
	var heading: Control = null
	for l in st.find_children("*", "Label", true, false):
		if (l as Label).text == "Ton" and scroll.is_ancestor_of(l):
			heading = l
	check(heading != null, "Überschrift „Ton“")
	if heading != null:
		scroll.scroll_vertical = 0
		await frames(2)
		await swipe(heading.get_global_rect().get_center(), Vector2(0, -260))
		await wait(0.3)
		check(scroll.scroll_vertical > 120, "Wischen über eine Karte blättert (%d)" % scroll.scroll_vertical)
	# Wischen, das auf einem Knopf beginnt: blättert, Knopf löst nicht aus
	scroll.scroll_vertical = 0
	await wait(0.3)
	var b := visible_button(scroll, "Probehoeren")
	check(b != null, "Knopf „Mau!“ sichtbar")
	if b != null:
		var hits := [0]
		var count := func() -> void: hits[0] += 1
		b.pressed.connect(count)
		await swipe(b.get_global_rect().get_center(), Vector2(0, -220))
		await wait(0.3)
		check(scroll.scroll_vertical > 100, "Wischen ab einem Knopf blättert (%d)" % scroll.scroll_vertical)
		check(int(hits[0]) == 0, "Knopf löst beim Wischen nicht aus")
		# kurzer Tipp löst aus
		scroll.scroll_vertical = 0
		await wait(0.3)
		await tap(b.get_global_rect().get_center())
		check(int(hits[0]) == 1, "Tipp auf den Knopf löst aus (%d)" % int(hits[0]))
		b.pressed.disconnect(count)
	nav.go_back()
	await wait(0.3)


# ----------------------------------------------------------------- M2: Wischen in den Regeln

func swipe_rules() -> void:
	press(nav, "Regeln")
	await wait(0.35)
	var rs := nav.top() as RulesScreen
	check(rs != null, "Regeln offen")
	if rs == null:
		return
	for tab in ["uebersicht", "anpassen"]:
		rs._show_tab(tab)
		await frames(3)
		var scroll: ScrollContainer = rs._overview if tab == "uebersicht" else rs._editor
		check(blockers(scroll).is_empty(), "Regeln %s: nichts fängt die Wischgeste ab %s" % [tab, str(blockers(scroll))])
		scroll.scroll_vertical = 0
		await frames(2)
		var r := scroll.get_global_rect()
		await swipe(Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.7), Vector2(0, -280))
		await wait(0.3)
		check(scroll.scroll_vertical > 120, "Regeln %s: Wischen blättert (%d)" % [tab, scroll.scroll_vertical])
	rs._show_tab("uebersicht")
	nav.go_back()
	await wait(0.3)


# ----------------------------------------------------------------- M3: Hintergrund als Zwischenbild

func background_cache() -> void:
	var bg := TableBackground.new()
	root.add_child(bg)
	await frames(3)
	check(bg.material == null and bg.shader_material != null, "Hintergrund: Shader nicht direkt auf der Vollbildfläche")
	var r0 := bg.renders
	await wait(1.0)
	var per_s := bg.renders - r0
	check(per_s >= 12 and per_s <= 26, "Hintergrund: etwa %d Neuberechnungen je Sekunde (%d)" % [int(TableBackground.REFRESH_HZ), per_s])
	bg.motion = false
	await frames(3)
	r0 = bg.renders
	await wait(0.5)
	check(bg.renders == r0, "Hintergrund ohne Daueranimation: keine Neuberechnung (%d)" % (bg.renders - r0))
	bg.tageszeit = 0.5
	await frames(2)
	check(bg.renders == r0 + 1, "Tageszeit geändert: sofort einmal neu (%d)" % (bg.renders - r0))
	bg.visible = false
	bg.motion = true
	await frames(2)
	r0 = bg.renders
	await wait(0.4)
	check(bg.renders == r0, "unsichtbarer Hintergrund rechnet nicht")
	bg.visible = true
	await frames(2)
	check(bg.renders > r0, "wieder sichtbar: neu berechnet")
	bg.queue_free()
	await frames(2)


# ----------------------------------------------------------------- H1, M1, N1, N2: WLAN-Spiel über die Bildschirme

func net_flow() -> void:
	var app := UiApp.app()
	if app != null:
		app.settings.set_value("regeln", RuleConfig.new().to_dict())     # Voreinstellung „offiziell“: langer Regeltext (N1)
	nav.push(HostLobbyScreen.new(), false)
	await frames(3)
	var lobby := nav.top() as HostLobbyScreen
	check(lobby != null and lobby.host != null, "Lobby offen")
	if lobby == null or lobby.host == null:
		return
	var host := lobby.host
	var port := host.port()
	check(port > 0, "Gastgeber-Server läuft (Port %d)" % port)
	# App-Gast über „Beitreten“ in einer zweiten Bildschirmverwaltung
	nav2 = ScreenNav.new()
	nav2.autostart = false
	root.add_child(nav2)
	await frames(2)
	nav2.push(JoinScreen.new(), false)
	await frames(2)
	var join := nav2.top() as JoinScreen
	join.join("127.0.0.1", port)
	var deadline := Time.get_ticks_msec() + 6000
	while (host.lobby().get("players", []) as Array).size() < 2 and Time.get_ticks_msec() < deadline:
		await frames(1)
	check((host.lobby().get("players", []) as Array).size() == 2, "App-Gast in der Lobby")
	await wait(0.3)
	# N1: „Bereit“ sichtbar und innerhalb des Bildschirms
	var ready := join._ready_btn
	var screen := Rect2(Vector2.ZERO, nav2.size)
	check(ready.is_visible_in_tree() and screen.encloses(ready.get_global_rect()), "„Bereit“ des App-Gasts sichtbar (%s in %s)" % [str(ready.get_global_rect()), str(screen)])
	ready.button_pressed = true
	deadline = Time.get_ticks_msec() + 3000
	var guest_ready := false
	while not guest_ready and Time.get_ticks_msec() < deadline:
		await frames(1)
		for p in host.lobby().get("players", []):
			if str(p.get("kind", "")) == "app" and int(p.get("id", -1)) != int(host.lobby().get("host_id", -1)) and bool(p.get("ready", false)):
				guest_ready = true
	check(guest_ready, "Gastgeber sieht den App-Gast als bereit")
	for i in 3:
		host.add_bot()
	await frames(3)
	# N2: Spielerliste blättert per Wischen
	var list_scroll := first_scroll(lobby)
	check(list_scroll is ScreenKit.TouchScroll and blockers(list_scroll).is_empty(), "Lobby: Spielerliste wischbar %s" % (str(blockers(list_scroll)) if list_scroll != null else "-"))
	# M1 in der Lobby mit Gast: genau eine Rückfrage, Zurück schließt sie
	android_back(nav)
	await frames(2)
	check(_boxes(lobby) == 1, "Lobby: eine Rückfrage nach einem Druck (%d)" % _boxes(lobby))
	await wait(0.8)
	android_back(nav)
	await frames(2)
	check(_boxes(lobby) == 0 and nav.top() == lobby, "Lobby: Zurück schließt die Rückfrage, Lobby bleibt")
	await wait(0.8)
	# H1: Start
	lobby.start_game()
	await wait(0.6)
	var ts := nav.top() as TableScreen
	check(ts != null and ts.source == host, "Tisch des Gastgebers")
	check(host.session != null and host.session.server != null and host.session.server.running, "Server läuft nach dem Start weiter")
	check(host.is_running(), "Partie läuft")
	check(host.session != null and host.session.players.size() == 5, "Spieler bleiben (%d)" % (host.session.players.size() if host.session != null else -1))
	var info := await http_get(port, "/info")
	check(info.contains("\"running\":true") and info.contains("mau-mau-flip"), "/info antwortet nach dem Start mit running")
	deadline = Time.get_ticks_msec() + 4000
	while ts != null and (ts.view.get("hand", []) as Array).is_empty() and Time.get_ticks_msec() < deadline:
		await frames(1)
	check(ts != null and (ts.view.get("hand", []) as Array).size() > 0, "Gastgeber hat eine Hand")
	check(ts != null and (ts.view.get("players", []) as Array).size() == 5, "5 Plätze am Tisch")
	# H1: App-Gast kommt an den Tisch und bleibt verbunden
	deadline = Time.get_ticks_msec() + 4000
	while not (nav2.top() is TableScreen) and Time.get_ticks_msec() < deadline:
		await frames(1)
	var gts := nav2.top() as TableScreen
	check(gts != null and gts.source is ClientTable, "Tisch des App-Gasts")
	if gts != null:
		var ct := gts.source as ClientTable
		await wait(0.4)
		check(ct.client != null and ct.client.state == "open", "App-Gast nach dem Wechsel zum Tisch verbunden (%s)" % (ct.client.state if ct.client != null else "kein Client"))
		deadline = Time.get_ticks_msec() + 4000
		while (gts.view.get("hand", []) as Array).is_empty() and Time.get_ticks_msec() < deadline:
			await frames(1)
		check((gts.view.get("hand", []) as Array).size() > 0, "App-Gast hat eine Hand")
		check(int(gts.view.get("seat", -1)) >= 0 and int(gts.view.get("seat", -1)) != int(ts.view.get("seat", -1)), "App-Gast auf eigenem Platz")
	# M1 am Tisch: ein Druck öffnet „Partie verlassen?“ und lässt sie offen
	android_back(nav)
	await frames(2)
	check(ts._confirm != null and is_instance_valid(ts._confirm) and not ts._confirm.is_queued_for_deletion(), "Tisch: Zurück öffnet die Rückfrage und sie bleibt offen")
	await wait(0.8)
	android_back(nav)
	await frames(2)
	check(ts._confirm == null and nav.top() == ts, "Tisch: Zurück schließt die Rückfrage")
	# Gastgeber verlässt: Der Gast zeigt die Verbindungsmeldung. (Im selben Prozess kann der Gast während des blockierenden
	# Abschieds des Gastgebers nicht abfragen; dann kommt das „bye“ zusammen mit dem Schließen an und er versucht es neu.)
	ts._leave_now()
	await wait(1.5)
	check(nav.top() is MainMenuScreen, "Gastgeber im Hauptmenü")
	if gts != null and is_instance_valid(gts):
		var st := (gts.source as ClientTable).connection_state()
		check(st in ["closed", "connecting"] and gts._conn.visible, "Gast: Verbindungsmeldung nach dem Ende (%s)" % st)


func _boxes(n: Node) -> int:
	var k := 0
	for c in n.find_children("Rueckfrage*", "", true, false):
		if not c.is_queued_for_deletion():
			k += 1
	return k


func http_get(port: int, path: String) -> String:
	var tcp := StreamPeerTCP.new()
	if tcp.connect_to_host("127.0.0.1", port) != OK:
		return ""
	var deadline := Time.get_ticks_msec() + 3000
	tcp.poll()
	while tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < deadline:
		await process_frame
		tcp.poll()
	if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return ""
	tcp.put_data(("GET %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nConnection: close\r\n\r\n" % [path, port]).to_utf8_buffer())
	var out := PackedByteArray()
	while Time.get_ticks_msec() < deadline:
		await process_frame
		tcp.poll()
		var n := tcp.get_available_bytes()
		if n > 0:
			var got: Array = tcp.get_data(n)
			out.append_array(got[1])
			if out.get_string_from_utf8().strip_edges().ends_with("}"):
				break
		elif tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
	tcp.disconnect_from_host()
	return out.get_string_from_utf8()
