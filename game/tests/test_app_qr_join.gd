extends SceneTree
# QR-Code scannen unter „Beitreten“ (Beta 1.4.3), am PC mit Stubs (QrJoin.scan_stub/wifi_stub statt QrScan.java/QrWifi.java):
#  - QrJoin.parse: WLAN-Spiel-Link (Groß/Klein, Port, Pfad), Online-Link (eigener Vermittler), App-Link (WLAN und online),
#    Spiel-WLAN-QR (Escapes \; \: \\ \, \", Reihenfolge, Schlüssel klein, T fehlt/SAE/nopass/WEP, H:true, Anführungszeichen),
#    fehlerhafte und fremde Codes, eingespeiste Texte älter als 2 min.
#  - NetAddresses.pinned: „join“/„search“ binden ans Spiel-WLAN, „host“ nicht; Bindungsfehler → übliche Regeln; Freigeben.
#  - Freigeben: attach/client_left (nur die eigene Verbindung), Seite ohne Partie verlassen.
#  - Beitreten-Seite: Knopf ganz oben, ohne Google-Dienste Meldung, Unbekanntes, altes Android (Hinweis mit Passwort), WLAN-QR →
#    Verbindung (Stub) → Beitritt am Gateway (echter Gastgeber auf 127.0.0.1) → Lobby → zurück = Spiel verlassen → freigegeben;
#    Spiel-WLAN nicht erreichbar → Meldung und freigegeben; WLAN-Link → direkt beitreten.
#   tools/godot_run.ps1 -Script res://tests/test_app_qr_join.gd -Headless

const CleanExit := preload("res://tests/clean_exit.gd")
const SETTINGS_PATH := "user://test_app_qr_join_einstellungen.json"

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


func run() -> void:
	parse_tests()
	binding_tests()
	var app := UiApp.app()
	if app == null:
		print("FAIL: App fehlt")
		await CleanExit.finish(self, 1)
		return
	_real_settings = app.settings
	_remove_files()
	app.settings = AppSettings.new(SETTINGS_PATH)
	app.settings.set_value("name", "Tina")
	await screen_tests()
	app.settings = _real_settings
	_remove_files()
	QrJoin.scan_stub = null
	QrJoin.wifi_stub = null
	print("RESULT: %d ok" % ok if failed == 0 else "FAIL: test_app_qr_join (%d ok, %d fehlgeschlagen)" % [ok, failed])
	await CleanExit.finish(self, 1 if failed > 0 else 0)


func parse_tests() -> void:
	# (a) WLAN-Spiel-Link
	var r := QrJoin.parse("http://192.168.43.1:24690/")
	check(r.kind == "wlan" and r.address == "192.168.43.1" and r.port == 24690, "WLAN-Link")
	r = QrJoin.parse("  HTTP://10.94.17.1:24693/APK?X=1#Y \n")
	check(r.kind == "wlan" and r.address == "10.94.17.1" and r.port == 24693, "WLAN-Link groß, Pfad, Abfrage, Anker")
	r = QrJoin.parse("http://172.20.3.4")
	check(r.kind == "wlan" and r.port == NetProtocol.PORT, "WLAN-Link ohne Port → Standardport")
	for bad in ["http://192.168.1.5:abc/", "http://192.168.1.5:0/", "http://192.168.1.5:70000/"]:
		r = QrJoin.parse(bad)
		check(r.kind == "invalid" and str(r.error).contains("unvollständig"), "kaputter Port: " + bad)
	for far in ["http://8.8.8.8:24690/", "https://example.com/", "http://192.168.1/"]:
		r = QrJoin.parse(far)
		check(r.kind == "unknown" and str(r.error).contains("nicht zu einem Spiel"), "kein Spiel in der Nähe: " + far)
	# (b) Online-Link, auch eigener Vermittler
	r = QrJoin.parse("https://mau-mau-flip-relay.shakie.workers.dev/?r=KATZE-42")
	check(r.kind == "online" and r.room == "KATZE-42" and r.relay == "https://mau-mau-flip-relay.shakie.workers.dev", "Online-Link")
	r = QrJoin.parse("HTTPS://Mein-Vermittler.Example.org/?lang=en&r=katze42")
	check(r.kind == "online" and r.room == "KATZE-42" and r.relay == "https://mein-vermittler.example.org", "eigener Vermittler, Groß/Klein")
	# (c) App-Link
	r = QrJoin.parse("maumauflip://join?h=192.168.200.7&p=24699")
	check(r.kind == "wlan" and r.address == "192.168.200.7" and r.port == 24699, "App-Link WLAN")
	r = QrJoin.parse("MAUMAUFLIP://join?r=MOND-17&v=x.example.org")
	check(r.kind == "online" and r.room == "MOND-17" and r.relay == "https://x.example.org", "App-Link online")
	r = QrJoin.parse("maumauflip://join?h=8.8.8.8&p=24690")
	check(r.kind == "invalid" and str(r.error).length() > 20, "App-Link ohne private IP")
	r = QrJoin.parse("maumauflip://join?h=192.168.1.5")
	check(r.kind == "invalid", "App-Link ohne Port")
	# (d) Spiel-WLAN-QR, wie game_wifi_panel ihn baut
	var made := NetAndroid.wifi_qr_text("Mau;Mau:Flip\\\"1,", "pa;ss:wo\\rd,\"x")
	r = QrJoin.parse(made)
	check(r.kind == "wifi" and r.ssid == "Mau;Mau:Flip\\\"1," and r.password == "pa;ss:wo\\rd,\"x" and r.security == "wpa2" and not r.hidden,
		"WLAN-QR mit Escapes zurückgelesen: %s" % str(r))
	r = QrJoin.parse("WIFI:T:WPA;S:AndroidShare_4821;P:k7m3x9q2w5r8t4z;;")
	check(r.kind == "wifi" and r.ssid == "AndroidShare_4821" and r.password == "k7m3x9q2w5r8t4z", "WLAN-QR einfach")
	r = QrJoin.parse("wifi:p:geheim123;s:Spiel;h:true;t:sae;;")
	check(r.kind == "wifi" and r.ssid == "Spiel" and r.security == "wpa3" and r.hidden, "Schlüssel klein, andere Reihenfolge, SAE, versteckt")
	r = QrJoin.parse("WIFI:S:Spiel;P:geheim123;;")
	check(r.kind == "wifi" and r.security == "wpa2", "T fehlt, Passwort da → WPA")
	r = QrJoin.parse("WIFI:S:Offen;T:nopass;P:;;")
	check(r.kind == "wifi" and r.security == "open" and r.password == "", "offenes WLAN")
	r = QrJoin.parse("WIFI:S:\"123456\";T:WPA;P:\"geheim123\";;")
	check(r.kind == "wifi" and r.ssid == "123456" and r.password == "geheim123", "Werte in Anführungszeichen")
	r = QrJoin.parse("WIFI:S:Spiel;T:WPA;P:ab:cd:ef:12;;")
	check(r.kind == "wifi" and r.password == "ab:cd:ef:12", "ungeschützter Doppelpunkt im Wert")
	r = QrJoin.parse("WIFI:S:Alt;T:WEP;P:12345;;")
	check(r.kind == "invalid" and str(r.error).contains("WEP"), "WEP abgewiesen")
	for bad in ["WIFI:T:WPA;P:geheim123;;", "WIFI:S:Spiel;T:WPA;P:kurz;;", "WIFI:S:Spiel;T:XYZ;P:geheim123;;", "WIFI:S:Spiel;T:WPA;P:geheim123\\",
			"WIFI:", "WIFI:S:%s;T:WPA;P:geheim123;;" % "x".repeat(33), "WIFI:S:Spiel;T:WPA;P:%s;;" % "y".repeat(65)]:
		r = QrJoin.parse(bad)
		check(r.kind == "invalid" and str(r.error).contains("unvollständig"), "fehlerhafter WLAN-QR: " + bad.left(40))
	# (e) Unbekanntes
	for other in ["", "   ", "Hallo Welt", "tel:+49123", "MATMSG:TO:a@b.de;;", "x".repeat(2000)]:
		r = QrJoin.parse(other)
		check(r.kind == "unknown" and str(r.error).contains("kein QR-Code"), "unbekannt: " + other.left(20))
	# Eingespeiste Texte (adb) verfallen nach 2 min
	QrJoin.scan_stub = {"available": true, "results": [{"status": "done", "text": "x", "source": "intent", "at": 1000, "now": 200000},
		{"status": "done", "text": "y", "source": "intent", "at": 1000, "now": 30000}, {"status": "done", "text": "z", "source": "camera", "at": 0, "now": 999999}]}
	check(QrJoin.scan_take().status == "idle", "eingespeist, älter als 2 min: verworfen")
	check(QrJoin.scan_take().text == "y", "eingespeist, frisch: zählt")
	check(QrJoin.scan_take().text == "z", "Kamera: immer")
	check(QrJoin.scan_take().status == "idle", "danach leer")
	check(QrJoin.scan_error_text("cancelled") == "" and QrJoin.scan_error_text("no_gms").contains("Google-Play-Dienste")
		and QrJoin.scan_error_text("module").contains("geladen") and QrJoin.scan_error_text("exception").contains("Raumcode"), "Fehlertexte")
	QrJoin.scan_stub = null


func binding_tests() -> void:
	QrJoin.wifi_stub = {"sdk": 34, "state": {"status": "connecting"}}
	check(QrJoin.wifi_supported(), "Android 14: Spiel-WLAN per QR möglich")
	check(QrJoin.wifi_connect("Spiel", "geheim123", "wpa2") == "" and QrJoin.wifi_active(), "Anfrage läuft")
	QrJoin.wifi_pin()
	check(NetAddresses.bind_for("join", "192.168.49.1") == "qr_wifi" and NetAddresses.bound_to == "qr_wifi", "join → Spiel-WLAN")
	check(NetAddresses.bind_for("search") == "qr_wifi", "search → Spiel-WLAN")
	check(NetAddresses.bind_for("host") != "qr_wifi", "host nie ans Spiel-WLAN aus dem QR-Code")
	NetAddresses.release("host")
	QrJoin.wifi_stub["bind_error"] = "Das Spiel-WLAN ist nicht verbunden."
	check(NetAddresses.bind_for("join", "192.168.49.1") != "qr_wifi" and NetAddresses.bind_problem.contains("nicht verbunden"),
		"Bindung scheitert → übliche Regeln, Grund gemerkt")
	QrJoin.wifi_stub["bind_error"] = ""
	# attach/client_left: nur die eigene Verbindung gibt frei
	var mine := Node.new()
	var other := Node.new()
	QrJoin.attach(mine)
	QrJoin.client_left(other)
	check(QrJoin.wifi_active() and int(QrJoin.wifi_stub.get("released", 0)) == 0, "fremde Verbindung verlassen: bleibt")
	QrJoin.client_left(mine)
	check(not QrJoin.wifi_active() and int(QrJoin.wifi_stub.get("released", 0)) == 1 and not NetAddresses.pinned.is_valid(),
		"eigene Verbindung verlassen: freigegeben")
	check(NetAddresses.bind_for("join", "192.168.49.1") != "qr_wifi", "nach dem Freigeben keine Bindung ans Spiel-WLAN mehr")
	check(not QrJoin.wifi_release() and int(QrJoin.wifi_stub.get("released", 0)) == 1, "zweites Freigeben: nichts mehr zu tun")
	# check_lost (Gerätetest 1.4.3): Spiel-WLAN weg → freigeben; nur für die eigene Verbindung, höchstens alle 2 s nachsehen
	QrJoin.wifi_stub["state"] = {"status": "connecting"}
	check(QrJoin.wifi_connect("Spiel", "geheim123", "wpa2") == "", "neue Anfrage")
	QrJoin.wifi_stub["state"] = {"status": "available"}
	QrJoin.attach(mine)
	check(not QrJoin.check_lost(other, 100000) and not QrJoin.check_lost(mine, 100000) and QrJoin.wifi_active(), "verbunden: bleibt")
	QrJoin.wifi_stub["state"] = {"status": "lost"}
	check(not QrJoin.check_lost(mine, 100500) and QrJoin.wifi_active(), "binnen 2 s nicht erneut nachgesehen")
	check(QrJoin.check_lost(mine, 102500) and not QrJoin.wifi_active() and int(QrJoin.wifi_stub.get("released", 0)) == 2,
		"Spiel-WLAN weg: freigegeben")
	check(not QrJoin.check_lost(mine, 105000), "danach nichts mehr zu tun")
	NetAddresses.release("join")
	NetAddresses.release("search")
	mine.free()
	other.free()
	QrJoin.wifi_stub = {"sdk": 28}
	check(not QrJoin.wifi_supported() and QrJoin.wifi_connect("A", "geheim123", "wpa2") == "old_android" and not QrJoin.wifi_active(),
		"Android 9: nicht möglich")
	QrJoin.wifi_stub = null


func screen_tests() -> void:
	root.size = Vector2i(1600, 720)
	var nav := ScreenNav.new()
	nav.autostart = false
	root.add_child(nav)
	await wait(0.3)
	nav.push(WlanScreen.new(), false)
	var js := JoinScreen.new()
	nav.push(js, false)
	await wait(0.4)
	var btn := js.find_child("QrScannen", true, false) as Button
	check(btn != null and btn.visible and btn.get_parent() is HBoxContainer and btn.get_index() == btn.get_parent().get_child_count() - 1 and btn.size.x == (js.find_child("Zurueck", true, false) as Control).size.x and btn.tooltip_text != "", "„QR-Code scannen“ klein oben rechts in der Kopfzeile")
	# Ohne Google-Dienste
	QrJoin.scan_stub = {"available": false}
	js.scan_qr()
	check(js._status.text.contains("Google-Play-Dienste"), "ohne Google-Dienste: klare Meldung")
	# Unbekannter Code
	QrJoin.scan_stub = {"available": true, "results": [{"status": "done", "text": "Hallo", "source": "camera"}]}
	js.scan_qr()
	check(await until(func() -> bool: return js._status.text.contains("kein QR-Code")), "unbekannter Code: freundliche Meldung")
	check(js.client == null, "unbekannter Code: keine Verbindung")
	# Altes Android: Hinweis mit Passwort
	QrJoin.wifi_stub = {"sdk": 28}
	js.handle_scan("WIFI:T:WPA;S:Spiel\\;1;P:geheim123;;")
	check(js._status.text.contains("„Spiel;1“") and js._status.text.contains("geheim123") and js._wifi_wait.is_empty(), "Android 9: in den WLAN-Einstellungen verbinden")
	# Spiel-WLAN nicht erreichbar
	QrJoin.wifi_stub = {"sdk": 34, "state": {"status": "connecting", "ssid": "Spiel"}}
	js.handle_scan("WIFI:T:WPA;S:Spiel;P:geheim123;;")
	check(js._status.text.contains("Bestätige") and not js._wifi_wait.is_empty(), "WLAN-QR: Anfrage läuft")
	QrJoin.wifi_stub["state"] = {"status": "unavailable"}
	check(await until(func() -> bool: return js._wifi_wait.is_empty()), "nicht erreichbar: Warten beendet")
	check(js._status.text.contains("Keine Verbindung") and not QrJoin.wifi_active() and int(QrJoin.wifi_stub.get("released", 0)) == 1,
		"nicht erreichbar: Meldung, freigegeben")
	# Echter Gastgeber am „Gateway“ (127.0.0.1)
	var host := GameStarter.host()
	root.add_child(host)
	host.use_discovery = false
	host.autosave = false
	check(host.open("Lena", NetProtocol.PORT, NetProtocol.PORT) == OK, "Gastgeber offen")
	QrJoin.wifi_stub = {"sdk": 34, "state": {"status": "connecting"}}
	QrJoin.scan_stub = {"available": true, "results": [{"status": "done", "text": "WIFI:T:WPA;S:AndroidShare_4821;P:k7m3x9q2w5r8t4z;;", "source": "camera"}]}
	js.scan_qr()
	check(await until(func() -> bool: return not js._wifi_wait.is_empty()), "WLAN-QR gescannt: verbindet")
	QrJoin.wifi_stub["state"] = {"status": "available", "ssid": "AndroidShare_4821", "handle": "7", "gateway": "127.0.0.1"}
	check(await until(func() -> bool: return js.client != null and js.client.connection_state() == "open"), "am Gateway beigetreten")
	check(NetAddresses.bound_to == "qr_wifi" or NetAddresses.binding() == "qr_wifi", "Verbindung ans Spiel-WLAN gebunden")
	check(QrJoin._owner_client == js.client.get_instance_id() if js.client != null else false, "Spiel-WLAN gehört zur Verbindung")
	check(not js._scan_btn.visible, "in der Lobby kein Scan-Knopf")
	js.on_back()
	await wait(0.2)
	check(not QrJoin.wifi_active() and int(QrJoin.wifi_stub.get("released", 0)) == 1 and js._scan_btn.visible, "Spiel verlassen: freigegeben")
	# Seite ohne Partie verlassen, während die Anfrage läuft
	QrJoin.wifi_stub = {"sdk": 34, "state": {"status": "connecting"}}
	js.handle_scan("WIFI:T:WPA;S:Spiel;P:geheim123;;")
	nav.go_back()
	await wait(0.3)
	check(not QrJoin.wifi_active() and int(QrJoin.wifi_stub.get("released", 0)) == 1, "Seite verlassen: freigegeben")
	# WLAN-Link → direkt beitreten
	var js2 := JoinScreen.new()
	nav.push(js2, false)
	await wait(0.3)
	js2.handle_scan("http://127.0.0.1:%d/" % NetProtocol.PORT)
	check(js2.client == null and js2._status.text.contains("nicht zu einem Spiel"), "Loopback ist kein Spiel in der Nähe")
	js2.handle_scan("HTTP://192.168.200.7:24699/")
	check(js2.client != null and str(js2.direct.address) == "192.168.200.7" and int(js2.direct.port) == 24699, "WLAN-Link: direkt beitreten")
	nav.home(false)
	await wait(0.3)
	host.leave()
	nav.queue_free()
	await wait(0.2)


func _remove_files() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(SETTINGS_PATH + suffix):
			DirAccess.remove_absolute(SETTINGS_PATH + suffix)
