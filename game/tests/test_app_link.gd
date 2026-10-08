extends SceneTree
# App-Link „In der App spielen“ (Beta 1.0.2), am PC mit Stub (NetAndroid.app_link_stub statt AppLink.java):
#  - parse_app_link: gültig (auch Großschreibung, kodiert, Schrägstrich), ungültig (Port fehlt/kaputt, keine private IP, falscher
#    Host) mit freundlichem Text; private_ipv4.
#  - App.check_app_link holt den Link einmal ab; das Hauptmenü öffnet „Beitreten“ direkt mit dieser Adresse (ohne Suche),
#    ein ungültiger Link zeigt nur einen Hinweis.
#  - Direkt beitreten an einen echten HostTable (127.0.0.1); ohne Namen erst die Namensfrage, danach Verbindung.
#  - Schon in diesem Spiel → bleibt; anderes Spiel während Lobby/Partie → Rückfrage („Bleiben“ ändert nichts, „Wechseln“ wechselt).
#   tools/godot_run.ps1 -Script res://tests/test_app_link.gd -Headless

const CleanExit := preload("res://tests/clean_exit.gd")
const PORT := 24941
const SETTINGS_PATH := "user://test_app_link_einstellungen.json"

var ok := 0
var failed := 0
var _real_settings: AppSettings


func check(cond: bool, text: String) -> void:
	if cond:
		ok += 1
	else:
		failed += 1
		print("FAIL: ", text)


func _initialize() -> void:
	call_deferred("run")


func wait(t: float) -> void:
	await create_timer(t).timeout


func until(cond: Callable, limit := 5.0) -> bool:
	var t := 0.0
	while not cond.call() and t < limit:
		await wait(0.05)
		t += 0.05
	return cond.call()


func toasts(nav: ScreenNav) -> String:
	var out := ""
	for t in nav._toast._toasts:
		out += str(t["text"]) + "\n"
	return out


func run() -> void:
	# --- Prüfen der Adresse
	var a := NetAndroid.parse_app_link("maumauflip://join?h=192.168.178.8&p=24690")
	check(a.ok and a.address == "192.168.178.8" and a.port == 24690, "gültiger Link")
	check(NetAndroid.parse_app_link("MauMauFlip://join/?h=10.94.17.1&p=24691#x").ok, "Großschreibung, Schrägstrich, Anker")
	check(NetAndroid.parse_app_link("maumauflip://join?p=24690&h=172.20.3%2E1").address == "172.20.3.1", "kodiert, andere Reihenfolge")
	check(NetAndroid.app_link_url("10.0.0.5", 24690) == "maumauflip://join?h=10.0.0.5&p=24690", "Link bauen")
	for bad in ["maumauflip://join?h=192.168.1.5", "maumauflip://join?h=192.168.1.5&p=", "maumauflip://join?h=192.168.1.5&p=abc",
			"maumauflip://join?h=192.168.1.5&p=70000", "maumauflip://other?h=192.168.1.5&p=24690", "http://192.168.1.5:24690/", ""]:
		var r := NetAndroid.parse_app_link(bad)
		check(not r.ok and str(r.error).contains("unvollständig"), "abgewiesen: " + bad)
	for pub in ["8.8.8.8", "172.32.0.1", "127.0.0.1", "192.169.1.1", "evil.example", "192.168.1"]:
		var r := NetAndroid.parse_app_link("maumauflip://join?h=%s&p=24690" % pub)
		check(not r.ok and str(r.error).length() > 20, "keine private IP: " + pub)
	check(NetAndroid.private_ipv4("10.1.2.3") and NetAndroid.private_ipv4("172.31.255.1") and not NetAndroid.private_ipv4("172.15.0.1")
		and not NetAndroid.private_ipv4("192.168.1.256"), "private Bereiche")
	# --- Abholen über die App (Stub)
	var app := UiApp.app()
	if app == null:
		print("FAIL: App fehlt")
		await CleanExit.finish(self, 1)
		return
	_real_settings = app.settings
	_remove_files()
	app.settings = AppSettings.new(SETTINGS_PATH)
	app.settings.set_value("name", "Tina")
	NetAndroid.app_link_stub = null
	check(not app.check_app_link(), "ohne Link passiert nichts")
	root.size = Vector2i(1600, 720)
	var nav := ScreenNav.new()
	root.add_child(nav)
	await wait(0.3)
	check(nav.top() is MainMenuScreen, "Hauptmenü")
	NetAndroid.app_link_stub = "maumauflip://join?h=8.8.8.8&p=24690"
	check(app.check_app_link(), "ungültiger Link abgeholt")
	await wait(0.1)
	check(nav.top() is MainMenuScreen and toasts(nav).contains("nicht zu einem Spiel in deiner Nähe"), "ungültig: nur Hinweis, kein Wechsel")
	check(NetAndroid.take_app_link() == "", "Link nur einmal")
	NetAndroid.app_link_stub = "maumauflip://join?h=192.168.200.7&p=24699"
	app.check_app_link()
	await wait(0.4)
	var js := nav.top() as JoinScreen
	check(js != null and js.direct.address == "192.168.200.7" and js.discovery == null and js.client != null
		and js._address.text == "192.168.200.7:24699" and nav.stack.size() == 3 and nav.stack[1] is WlanScreen,
		"gültig: Beitreten verbindet direkt, ohne Suche, darunter „Mit anderen spielen“")
	nav.home(false)
	await wait(0.2)
	# --- Echter Gastgeber
	var host := GameStarter.host()
	root.add_child(host)
	host.use_discovery = false
	host.autosave = false
	check(host.open("Lena", PORT, PORT) == OK, "Gastgeber offen")
	JoinScreen.handle_link(nav, {"ok": true, "address": "127.0.0.1", "port": PORT})
	await wait(0.3)
	js = nav.top() as JoinScreen
	check(js != null and await until(func() -> bool: return js.client != null and js.client.connection_state() == "open"), "direkt verbunden")
	check(await until(func() -> bool: return js._lobby_box.visible and js._lobby_list.get_child_count() >= 2), "Lobby des Gastgebers sichtbar")
	# Gleicher Link noch einmal: bleibt
	JoinScreen.handle_link(nav, {"ok": true, "address": "127.0.0.1", "port": PORT})
	await wait(0.1)
	check(nav.top() == js and toasts(nav).contains("schon in diesem Spiel") and js.find_child("AppLinkFrage", true, false) == null, "schon verbunden: bleibt")
	# Anderes Spiel: Rückfrage
	JoinScreen.handle_link(nav, {"ok": true, "address": "127.0.0.1", "port": PORT + 1})
	await wait(0.1)
	var box := js.find_child("AppLinkFrage", true, false) as ConfirmBox
	check(box != null, "anderes Spiel: Rückfrage")
	if box != null:
		box._answer(false)
	await wait(0.2)
	check(nav.top() == js and js.client != null and js.client.connection_state() == "open", "„Bleiben“: Verbindung bleibt")
	JoinScreen.handle_link(nav, {"ok": true, "address": "127.0.0.1", "port": PORT + 1})
	await wait(0.1)
	box = js.find_child("AppLinkFrage", true, false) as ConfirmBox
	if box != null:
		box._answer(true)
	await wait(0.4)
	var js2 := nav.top() as JoinScreen
	check(js2 != null and js2 != js and int(js2.direct.port) == PORT + 1 and nav.stack.size() == 3, "„Wechseln“: neues Beitreten")
	check(await until(func() -> bool: return _guest_count(host) == 0), "altes Spiel verlassen: %s" % str(host.lobby().get("players", [])))
	nav.home(false)
	await wait(0.2)
	# --- Ohne Namen: erst fragen
	app.settings.set_value("name", "")
	JoinScreen.handle_link(nav, {"ok": true, "address": "127.0.0.1", "port": PORT})
	await wait(0.3)
	var js3 := nav.top() as JoinScreen
	var name_edit := js3.find_child("Name", true, false) as LineEdit if js3 != null else null
	check(js3 != null and js3.client == null and name_edit != null and js3._status.text.contains("wie heißt du"), "ohne Namen: Namensfrage, noch keine Verbindung")
	if js3 != null and name_edit != null:
		js3.confirm_name()
		await wait(0.1)
		check(js3.client == null and toasts(nav).contains("Namen"), "leerer Name wird nicht genommen")
		name_edit.text = "  Max  "
		js3.confirm_name()
		check(str(app.settings.get_value("name", "")) == "Max" and js3.client != null, "Name gespeichert, Verbindung startet")
		check(await until(func() -> bool: return js3.client != null and js3.client.connection_state() == "open"), "mit Namen verbunden")
	nav.home(false)
	await wait(0.3)
	host.leave()
	app.settings = _real_settings
	_remove_files()
	NetAndroid.app_link_stub = null
	print("RESULT: %d ok" % ok if failed == 0 else "FAIL: test_app_link (%d ok, %d fehlgeschlagen)" % [ok, failed])
	await CleanExit.finish(self, 1 if failed > 0 else 0)


func _guest_count(host: HostTable) -> int:
	var n := 0
	for p in host.lobby().get("players", []):
		if str((p as Dictionary).get("name", "")) != "Lena" and bool((p as Dictionary).get("connected", true)):
			n += 1
	return n


func _remove_files() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(SETTINGS_PATH + suffix):
			DirAccess.remove_absolute(SETTINGS_PATH + suffix)
