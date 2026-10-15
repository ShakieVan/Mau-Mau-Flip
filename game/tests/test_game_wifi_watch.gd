extends SceneTree
# Mau-Mau Flip (Beta 1.6.2, docs/module/uebergabe.md 10.2/10.8/10.16): GameWifiWatch ohne Server, mit eingespritzter Zustandsquelle,
# Uhr, Adressen und Bindung; HostTable als Double (session.rebind, refresh_addrs schreibt wlan.addrs/past fort und verteilt hosts).
#  - Spiel-WLAN geht auf, ohne dass ein Overlay offen ist: rebind und refresh_addrs laufen trotzdem, wlan.addrs/past und hosts aktuell.
#  - Abfrage nur alle POLL_MS; ohne Änderung nichts; Bindung oder Adressen ändern sich → rebind + refresh_addrs.
#  - Schließen per close(): Rückbindung (rebind(true)), kein lost; Android schließt: lost("own") genau einmal.
#  - auto_open: ohne Erlaubnis nichts, normaler Hotspot läuft → aufgeben, incompatible_mode → 3 Wiederholungen im Abstand von 2 s,
#    altes Netz → wiederholen, sonst nicht; fremdes Spiel-WLAN aus dem QR-Code zuerst verlassen.
#  - foreign_ap: QrWifi „lost“ bzw. keine eigene Adresse mehr → lost("foreign") einmal.
#  - mit NetAndroid.wifi_stub als echter Quelle: auto_open öffnet, die Adresse kommt aus dem Stub.
#   tools/godot_run.ps1 -Script res://tests/test_game_wifi_watch.gd -Headless

const CleanExit := preload("res://tests/clean_exit.gd")
const Watch := preload("res://scripts/app/game_wifi_watch.gd")

var ok := 0
var failed := 0


func check(cond: bool, text: String) -> void:
	if cond:
		ok += 1
	else:
		failed += 1
		print("FAIL: ", text)


class SessionDouble:
	extends RefCounted
	var calls: Array = []         # after_close je Aufruf
	var answer := ""
	func rebind(after_close := false) -> String:
		calls.append(after_close)
		return answer


class HostDouble:
	extends RefCounted
	# Nachbau von HostTable.refresh_addrs (T7): eigene Adressen nach wlan.addrs, frühere nach wlan.past, hosts neu verteilen.
	var session := SessionDouble.new()
	var source: Callable
	var port := 24690
	var wlan := {"port": 24690, "addrs": [], "past": []}
	var hosts_sent: Array = []
	var refreshed := 0
	func refresh_addrs() -> void:
		refreshed += 1
		var now: Array = source.call()
		for a in wlan.addrs:
			var key := "%s:%d" % [a, port]
			if not now.has(a) and not (wlan.past as Array).has(key):
				(wlan.past as Array).append(key)
		wlan.addrs = now.duplicate()
		hosts_sent.append(now.map(func(a): return "http://%s:%d/" % [a, port]))


class World:
	extends RefCounted
	var now := 0
	var available := true
	var state := {"status": "off", "granted": true}
	var starts: Array = []        # Ergebnisse von start (Fehlercode oder ""), vorn zuerst
	var after_start: Array = []   # Zustand nach jedem Start, vorn zuerst
	var started := 0
	var stopped := 0
	var address := ""
	var addrs: Array = ["192.168.178.40"]
	var binding := "wifi"
	var qr_on := false
	var qr := {"status": "available"}
	var released := 0
	var old := false
	var order: Array = []
	func start() -> String:
		started += 1
		order.append("start")
		var err: String = starts.pop_front() if not starts.is_empty() else ""
		if not after_start.is_empty():
			state = after_start.pop_front()
		return err
	func stop() -> bool:
		stopped += 1
		state = {"status": "off", "granted": true}
		return true
	func release() -> bool:
		released += 1
		order.append("release")
		var was := qr_on
		qr_on = false
		return was


func _initialize() -> void:
	call_deferred("run")


func make(w: World, h: HostDouble) -> GameWifiWatch:
	var g: GameWifiWatch = Watch.new()
	g.manual = true
	g.setup(h)
	g.now_ms = func() -> int: return w.now
	g.available_source = func() -> bool: return w.available
	g.state_source = func() -> Dictionary: return w.state.duplicate()
	g.start_source = w.start
	g.stop_source = w.stop
	g.address_source = func() -> String: return w.address
	g.addrs_source = func() -> Array: return w.addrs.duplicate()
	g.binding_source = func() -> String: return w.binding
	g.qr_active = func() -> bool: return w.qr_on
	g.qr_state = func() -> Dictionary: return w.qr.duplicate()
	g.qr_release = w.release
	g.old_net = func() -> bool: return w.old
	h.source = func() -> Array: return w.addrs.duplicate()
	root.add_child(g)
	return g


func run() -> void:
	watch_tests()
	auto_tests()
	foreign_tests()
	stub_tests()
	print("RESULT: %d ok" % ok if failed == 0 else "FAIL: test_game_wifi_watch (%d ok, %d fehlgeschlagen)" % [ok, failed])
	await CleanExit.finish(self, 1 if failed > 0 else 0)


func watch_tests() -> void:
	var w := World.new()
	var h := HostDouble.new()
	var g := make(w, h)
	var changes := [0]
	var lost: Array = []
	g.changed.connect(func() -> void: changes[0] += 1)
	g.lost.connect(func(what: String) -> void: lost.append(what))
	check(GameWifiWatch.current() == g, "current() findet den Wächter am Tisch")
	g.tick()
	check(h.session.calls == [false] and h.refreshed == 1 and changes[0] == 1, "erster Blick: rebind + refresh_addrs")
	check(h.wlan.addrs == ["192.168.178.40"], "wlan.addrs nach dem ersten Blick")
	w.now = 1000
	g.tick()
	w.now = 1499
	g.tick()
	check(h.session.calls.size() == 1 and h.refreshed == 1, "ohne Änderung und vor POLL_MS: nichts")
	# Spiel-WLAN geht auf (geöffnet im Overlay, das gleich wieder zu ist – hier gibt es gar keins); Adresse kommt erst später
	w.state = {"status": "on", "granted": true, "ssid": "AndroidShare_1"}
	w.now = 1500
	g.tick()
	check(h.session.calls.size() == 1 and g.state.status == "on" and g.address == "", "on ohne Adresse: noch nicht binden")
	w.address = "192.168.49.1"
	w.addrs = ["192.168.178.40", "192.168.49.1"]
	w.binding = ""
	w.now = 3000
	g.tick()
	check(h.session.calls == [false, false] and h.refreshed == 2 and g.address == "192.168.49.1", "Adresse da: rebind + refresh_addrs")
	check(h.wlan.addrs == ["192.168.178.40", "192.168.49.1"] and (h.hosts_sent.back() as Array).has("http://192.168.49.1:24690/"),
		"wlan.addrs und hosts mit der Spiel-WLAN-Adresse")
	w.now = 4500
	g.tick()
	check(h.session.calls.size() == 2, "Bindung danach gemerkt: kein zweites rebind")
	# Normales WLAN fällt weg (Gerät ohne Gleichzeitigkeit): nur Adressen ändern sich
	w.addrs = ["192.168.49.1"]
	w.now = 6000
	g.tick()
	check(h.session.calls.size() == 3 and h.refreshed == 3 and h.wlan.addrs == ["192.168.49.1"] and (h.wlan.past as Array).has("192.168.178.40:24690"),
		"Adressen ändern sich: rebind + refresh_addrs, alte Adresse in past")
	# Bindung ändert sich allein (z. B. QrJoin.wifi_release setzt sie zurück)
	w.binding = "hotspot"
	w.now = 7500
	g.tick()
	check(h.session.calls.size() == 4 and h.refreshed == 4, "Bindung ändert sich: rebind + refresh_addrs")
	# Schließen per Knopf: Rückbindung, sobald die Adresse weg ist; kein lost
	g.close()
	check(w.stopped == 1, "close() schließt das Spiel-WLAN")
	w.now = 7600
	g.tick()
	check(h.session.calls.size() == 4, "Adresse noch da: mit der Rückbindung warten")
	w.address = ""
	w.addrs = ["192.168.178.40"]
	w.now = 9100
	g.tick()
	check(h.session.calls.back() == true and h.refreshed == 5 and g.address == "" and lost.is_empty(), "geschlossen: rebind(true), kein lost")
	# Android schließt das Spiel-WLAN (ohne close): lost("own") einmal, Rückbindung spätestens nach REBIND_WAIT_MS
	w.state = {"status": "on", "granted": true}
	w.address = "192.168.49.1"
	w.now = 10600
	g.tick()
	var n := h.session.calls.size()
	w.state = {"status": "stopped", "granted": true}
	w.now = 12100
	g.tick()
	check(lost == ["own"], "Android schließt: lost(\"own\")")
	w.now = 13600
	g.tick()
	check(lost == ["own"] and h.session.calls.size() == n, "lost nur einmal; Adresse noch da: warten")
	w.now = 17200
	g.tick()
	check(h.session.calls.size() == n + 1 and h.session.calls.back() == true, "nach REBIND_WAIT_MS trotzdem zurückgebunden")
	g.free()
	check(GameWifiWatch.current() == null, "current() nach dem Entfernen leer")


func auto_tests() -> void:
	# Ohne Erlaubnis: kein Start, Oberfläche zeigt den Knopf mit dem Erlaubnisdialog
	var w := World.new()
	var h := HostDouble.new()
	var g := make(w, h)
	w.state = {"status": "off", "granted": false}
	check(g.auto_open() == "permission" and w.started == 0 and g.auto_state == "permission", "ohne Erlaubnis: nichts öffnen")
	# Normaler Hotspot läuft: aufgeben (die App ändert ihn nie)
	w.state = {"status": "off", "granted": true, "ap_enabled": 1}
	check(g.auto_open() == "ap_running" and w.started == 0 and g.auto_state == "failed", "normaler Hotspot: aufgeben")
	# incompatible_mode dreimal, dann klappt es: 4 Versuche, je 2 s Abstand; fremdes Spiel-WLAN zuerst verlassen
	w.state = {"status": "off", "granted": true}
	w.qr_on = true
	var done: Array = []
	g.auto_done.connect(func(okay: bool, err: String) -> void: done.append([okay, err]))
	var bad := {"status": "failed", "error": "incompatible_mode", "granted": true}
	w.after_start = [bad, bad, bad, {"status": "on", "granted": true}]
	w.now = 50000
	check(g.auto_open() == "" and w.started == 1 and g.auto_state == "waiting", "incompatible_mode: wartet auf den nächsten Versuch")
	check(w.order.slice(0, 2) == ["release", "start"] and w.released == 1, "fremdes Spiel-WLAN vor dem Öffnen verlassen")
	# Gegenprüfung 1.6.2: zweiter Anstoß (Tisch-Aufbau und Anfrage beim HostSwitch) während der Wiederholung – kein neuer Start
	w.now = 50400
	check(g.auto_open() == "" and w.started == 1 and g.auto_tries == 1 and g.auto_state == "waiting", "zweites auto_open beim Warten: nichts neu")
	w.now = 51999
	g.tick()
	check(w.started == 1, "nicht vor 2 s erneut")
	w.now = 52000
	g.tick()
	check(w.started == 2, "zweiter Versuch nach 2 s")
	w.now = 54000
	g.tick()
	w.now = 56000
	g.tick()
	check(w.started == 4 and g.auto_state == "done" and done == [[true, ""]] and g.auto_tries == 4, "vierter Versuch klappt: auto_done(true)")
	# immer incompatible_mode: nach 1 + 3 Versuchen aufgeben
	w.state = {"status": "off", "granted": true}
	w.started = 0
	done.clear()
	w.after_start = [bad, bad, bad, bad, bad]
	w.now = 60000
	g.auto_open()
	for t in [62000, 64000, 66000, 68000, 70000]:
		w.now = t
		g.tick()
	check(w.started == 4 and g.auto_state == "failed" and done == [[false, "incompatible_mode"]], "höchstens 3 Wiederholungen, dann aufgeben")
	# Fehler aus dem Start selbst (ohne Zustand): altes Netz → wiederholen; sonst sofort aufgeben
	w.state = {"status": "off", "granted": true}
	w.started = 0
	done.clear()
	w.old = true
	w.starts = ["generic", ""]
	w.after_start = [{"status": "failed", "error": "generic", "granted": true}, {"status": "on", "granted": true}]
	w.now = 80000
	check(g.auto_open() == "" and g.auto_state == "waiting", "altes Netz: wiederholen")
	w.now = 82000
	g.tick()
	check(w.started == 2 and g.auto_state == "done", "altes Netz: zweiter Versuch klappt")
	w.state = {"status": "off", "granted": true}
	w.started = 0
	w.old = false
	w.starts = ["generic"]
	w.after_start = [{"status": "failed", "error": "generic", "granted": true}]
	check(g.auto_open() == "generic" and w.started == 1 and g.auto_state == "failed", "anderer Fehler ohne altes Netz: kein Wiederholen")
	w.state = {"status": "off", "granted": true}
	w.started = 0
	w.old = true
	w.starts = ["permission"]
	w.after_start = [{"status": "failed", "error": "permission", "granted": true}]
	check(g.auto_open() == "permission" and w.started == 1, "fehlende Erlaubnis beim Start: nie wiederholen")
	# Schon offen bzw. startet gerade
	w.state = {"status": "on", "granted": true}
	w.started = 0
	check(g.auto_open() == "" and w.started == 0 and g.auto_state == "done", "schon offen: nichts zu tun")
	# Ohne Spiel-WLAN-Fähigkeit
	w.available = false
	check(g.auto_open() == "unsupported" and g.auto_state == "failed", "kein Spiel-WLAN möglich")
	# Zu lange keine Antwort von Android
	w.available = true
	w.state = {"status": "off", "granted": true}
	w.started = 0
	w.old = false
	w.after_start = [{"status": "starting", "granted": true}]
	w.now = 100000
	g.auto_open()
	check(g.auto_state == "running" and g.auto_open() == "" and w.started == 1, "zweites auto_open während des Starts: nichts neu")
	w.now = 100000 + Watch.AUTO_WAIT_MS
	g.tick()
	check(g.auto_state == "failed" and g.auto_error == "generic", "keine Antwort: nach AUTO_WAIT_MS aufgeben")
	g.free()


func foreign_tests() -> void:
	# Gastgeber sitzt im Spiel-WLAN eines Mitspielers (Übernahme im fremden Spiel-WLAN): QrWifi meldet „lost“
	var w := World.new()
	var h := HostDouble.new()
	var g := make(w, h)
	var lost: Array = []
	g.lost.connect(func(what: String) -> void: lost.append(what))
	w.addrs = ["192.168.49.23"]
	w.qr_on = true
	g.tick()
	g.foreign_ap = true
	w.now = 1500
	g.tick()
	check(lost.is_empty(), "fremdes Spiel-WLAN da: kein lost")
	w.qr = {"status": "lost"}
	w.now = 3000
	g.tick()
	w.now = 4500
	g.tick()
	check(lost == ["foreign"], "QrWifi lost: lost(\"foreign\") einmal")
	# über die Systemeinstellungen beigetreten (kein QrWifi): keine eigene Adresse mehr
	g.foreign_ap = false
	w.qr_on = false
	w.qr = {"status": "idle"}
	g.foreign_ap = true
	w.now = 6000
	g.tick()
	check(lost.size() == 1, "neu scharf, Netz da: nichts")
	w.addrs = []
	w.now = 7500
	g.tick()
	check(lost == ["foreign", "foreign"] and h.wlan.addrs.is_empty(), "keine eigene Adresse mehr: lost(\"foreign\")")
	g.free()


func stub_tests() -> void:
	# Echte Standardquellen mit NetAndroid.wifi_stub (wie GameWifiPanel in den Bildschirmtests)
	NetAndroid.wifi_stub = {"address": "192.168.49.1", "granted": true}
	NetAndroid.game_wifi_stop()
	var w := World.new()
	var h := HostDouble.new()
	var g: GameWifiWatch = Watch.new()
	g.manual = true
	g.setup(h)
	g.now_ms = func() -> int: return w.now
	g.addrs_source = func() -> Array: return w.addrs.duplicate()
	g.binding_source = func() -> String: return w.binding
	g.qr_active = func() -> bool: return false
	h.source = func() -> Array: return w.addrs.duplicate()
	root.add_child(g)
	g.tick()
	check(g.state.get("status") == "off" and g.address == "", "Stub: Spiel-WLAN zu")
	check(g.auto_open() == "" and g.auto_state == "done", "Stub: auto_open öffnet sofort")
	w.addrs = ["192.168.49.1"]
	w.now = 100
	g.tick()
	check(g.address == "192.168.49.1" and h.session.calls.size() == 2 and h.wlan.addrs == ["192.168.49.1"], "Stub: Adresse, rebind, wlan.addrs")
	NetAndroid.wifi_stub["granted"] = false
	NetAndroid.game_wifi_stop()
	check(g.auto_open() == "permission", "Stub: ohne Erlaubnis kein automatisches Öffnen")
	g.free()
	NetAndroid.game_wifi_stop()
	NetAndroid.wifi_stub = null
