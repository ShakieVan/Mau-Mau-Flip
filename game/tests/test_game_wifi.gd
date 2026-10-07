extends SceneTree
# Spiel-WLAN (Beta 1.0.1): WLAN-QR-Text mit Escaping, Spiel-Adresse aus den Schnittstellen (nie 192.168 angenommen), deutsche Texte
# zu allen Zuständen und Fehlern, Panel-Ablauf mit dem PC-Stub (NetAndroid.wifi_stub) samt Gastgeber-Sitzung und rebind().
#   tools/godot_run.ps1 -Script res://tests/test_game_wifi.gd -Headless

const CleanExit := preload("res://tests/clean_exit.gd")
const PORT := 24912

var ok := 0
var failed := 0


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


func run() -> void:
	# --- QR-Text
	check(NetAndroid.wifi_qr_text("AndroidShare_4821", "k7m3x9q2w5r8t4z") == "WIFI:T:WPA;S:AndroidShare_4821;P:k7m3x9q2w5r8t4z;;", "WLAN-QR einfach")
	check(NetAndroid.wifi_qr_escape("a\\b;c,d:e\"f") == "a\\\\b\\;c\\,d\\:e\\\"f", "Escaping von \\ ; , : \"")
	check(NetAndroid.wifi_qr_text("Mau;Mau", "p:w,\"x\\") == "WIFI:T:WPA;S:Mau\\;Mau;P:p\\:w\\,\\\"x\\\\;;", "WLAN-QR mit Sonderzeichen")
	check(NetAndroid.wifi_qr_text("Ä Öse", "geheim123", "wpa3_transition").begins_with("WIFI:T:WPA;S:Ä Öse;"), "WPA3 bleibt T:WPA, Umlaute unverändert")
	check(NetAndroid.wifi_qr_text("Offen", "", "open") == "WIFI:T:nopass;S:Offen;;", "offenes Netz ohne Passwort")
	check(NetAndroid.game_url("10.21.7.1") == "http://10.21.7.1:24690/" and NetAndroid.game_url("10.0.0.1", 24691) == "http://10.0.0.1:24691/"
		and NetAndroid.game_url("") == "", "Spiel-Adresse mit http und Port")
	var qr := QrCode.encode(NetAndroid.wifi_qr_text("AndroidShare_4821", "k7m3x9q2w5r8t4z"))
	check(qr != null, "WLAN-QR lässt sich kodieren")
	# --- Adresse des Spiel-WLANs aus den Schnittstellen
	var home := {"transport": "wifi", "iface": "wlan0", "addresses": ["192.168.178.4/24"], "gateway": "192.168.178.1", "internet": true, "default": true}
	var s := {"android": true, "networks": [home], "interfaces": [{"name": "wlan0", "address": "192.168.178.4", "prefix": 24},
		{"name": "swlan0", "address": "10.94.17.1", "prefix": 24}, {"name": "rmnet_data0", "address": "10.3.4.5", "prefix": 30}]}
	check(NetAndroid.game_wifi_address(s) == "10.94.17.1", "Adresse aus der Hotspot-Schnittstelle (10.x, nicht 192.168, ohne Mobilfunk)")
	var two: Dictionary = s.duplicate(true)
	(two.interfaces as Array).append({"name": "rndis0", "address": "172.20.3.1", "prefix": 24})
	check(NetAndroid.game_wifi_address(two, ["10.94.17.1"]) == "172.20.3.1", "neue Schnittstelle nach dem Start bevorzugt")
	check(NetAndroid.game_wifi_address({"android": true, "networks": [home], "interfaces": [{"name": "wlan0", "address": "192.168.178.4"}]}) == "",
		"ohne Spiel-WLAN keine Adresse")
	check(NetAndroid.game_wifi_address({"android": false, "interfaces": []}) == "", "PC ohne Stub: keine Adresse")
	# --- Texte
	var codes := ["permission", "location_off", "incompatible_mode", "ap_running", "no_channel", "tethering_disallowed", "unsupported", "generic", "busy"]
	var titles := {}
	for c in codes:
		var m := NetAndroid.game_wifi_message({"status": "failed", "error": c, "sdk": 34})
		check(str(m.title) != "" and str(m.text).length() > 20, "Text für " + c)
		titles[str(m.title)] = true
	check(titles.size() >= 7, "Fehler haben eigene Überschriften")
	var hot := NetAndroid.game_wifi_message({"status": "failed", "error": "incompatible_mode"})
	check(str(hot.title) == "Dein Hotspot läuft" and str(hot.text).contains("Schnelleinstellungen aus") and str(hot.text).contains("ändert ihn nie"), "normaler Hotspot: Bitte, ohne Eingriff")
	check(str(NetAndroid.game_wifi_message({"status": "failed", "error": "permission", "sdk": 34}).text).contains("Geräte in der Nähe")
		and str(NetAndroid.game_wifi_message({"status": "failed", "error": "permission", "sdk": 31}).text).contains("Standort"), "Erlaubnis je Android-Version")
	check(bool(NetAndroid.game_wifi_message({"status": "failed", "error": "permission"}).settings), "Erlaubnis: Hinweis auf App-Einstellungen")
	check(not bool(NetAndroid.game_wifi_message({"status": "failed", "error": "tethering_disallowed"}).retry), "gesperrt: kein „Neu öffnen“")
	check(str(NetAndroid.game_wifi_message({"status": "on"}).text).contains("Kein Internet"), "offen: kein Internet ist normal")
	check(str(NetAndroid.game_wifi_message({"status": "stopped"}).title) == "Spiel-WLAN beendet", "von Android beendet")
	# --- Stub und Erlaubnis
	NetAndroid.wifi_stub = {"sdk": 31}
	check(NetAndroid.game_wifi_permission() == "android.permission.ACCESS_FINE_LOCATION", "bis Android 12: Standort-Erlaubnis")
	NetAndroid.wifi_stub = {"sdk": 34}
	check(NetAndroid.game_wifi_permission() == "android.permission.NEARBY_WIFI_DEVICES", "ab Android 13: Geräte in der Nähe")
	check(NetAndroid.game_wifi_available() and NetAndroid.game_wifi_state().status == "off", "Stub verfügbar, zunächst aus")
	check(NetAndroid.game_wifi_start() == "" and NetAndroid.game_wifi_state().status == "on" and NetAndroid.game_wifi_state().ssid != "", "Stub startet")
	check(NetAndroid.game_wifi_stop() and NetAndroid.game_wifi_state().status == "off" and NetAndroid.game_wifi_state().ssid == "", "Stub schließt")
	# --- Panel mit Gastgeber-Sitzung
	var host := GameStarter.host()
	root.add_child(host)
	host.use_discovery = false
	check(host.open("Ben", PORT, PORT) == OK, "Gastgeber offen")
	host.autosave = false
	var holder := Control.new()
	holder.size = Vector2(1600, 720)
	root.add_child(holder)
	NetAndroid.wifi_stub = {"ssid": "AndroidShare_7k2m", "password": "q9w3e7r2t5y8u4i", "address": "10.94.17.1"}
	var p := GameWifiPanel.open(holder, host)
	await wait(0.2)
	check(p.wifi.status == "on" and p.problem == "" and p.address == "10.94.17.1", "Panel: Spiel-WLAN offen, Adresse gefunden")
	check(p.qr_text() == "WIFI:T:WPA;S:AndroidShare_7k2m;P:q9w3e7r2t5y8u4i;;", "Panel zeigt zuerst den WLAN-QR")
	check(p.hint == "", "rebind am PC: nichts zu tun")
	p.set_step(1)
	check(p.qr_text() == "http://10.94.17.1:%d/" % PORT, "Schritt 2: Spiel-QR mit Port des Gastgebers")
	check(p.find_child("Adresse", true, false) is Label and (p.find_child("Adresse", true, false) as Label).text == "10.94.17.1:%d" % PORT, "Adresse als Text")
	(p.find_child("Schliessen", true, false) as Button).pressed.emit()
	check(NetAndroid.game_wifi_state().status == "off" and p.qr_text() == "", "Schließen beendet das Spiel-WLAN")
	p.close()
	await wait(0.1)
	# Fehlerfälle
	var cases := {"incompatible_mode": {"start_error": "incompatible_mode"}, "ap_running": {"ap_enabled": 1}, "permission": {"granted": false},
		"no_channel": {"start_error": "no_channel"}}
	for want in cases:
		NetAndroid.wifi_stub = cases[want]
		var q := GameWifiPanel.open(holder, host)
		await wait(0.1)
		check(q.problem == want and q.qr_text() == "" and (q.find_child("Erneut", true, false) as Button).visible, "Panel-Fehler " + want)
		q.close()
	NetAndroid.wifi_stub = {"start_error": "tethering_disallowed"}
	var t := GameWifiPanel.open(holder, host)
	await wait(0.1)
	check(t.problem == "tethering_disallowed" and not (t.find_child("Erneut", true, false) as Button).visible, "gesperrt: kein Neu-Öffnen-Knopf")
	t.close()
	# Ohne Android und ohne Stub: nicht verfügbar
	NetAndroid.wifi_stub = null
	check(not NetAndroid.game_wifi_available() and NetAndroid.game_wifi_start() == "unsupported", "PC ohne Stub: nicht verfügbar")
	var u := GameWifiPanel.open(holder, host)
	await wait(0.1)
	check(u.problem == "unsupported", "Panel: nicht verfügbar")
	u.close()
	host.leave()
	print("RESULT: %d ok" % ok)
	await CleanExit.finish(self, 1 if failed > 0 else 0)
