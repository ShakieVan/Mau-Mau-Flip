extends SceneTree

# Mau-Mau Flip (Beta 1.6.2, Gastgeber-Übergabe im WLAN, docs/module/uebergabe.md 10.9 und Abschnitt 11): Herkunftsliste früherer
# Gastgeber. Die Lite-Seite des alten Gastgebers verbindet sich mit „Origin: http://<alt>:<Port>“ zum neuen.
#  1  NetServer.origin_allowed(origin, host, extra) und extra_origin: nur exakte „http://IPv4:Port“; https, Muster, fremde Ports,
#     Namen, führende Nullen und Unsinn abgelehnt; ohne extra wie bisher.
#  2  set_extra_origins wirkt im Netz-Thread (TCP 24998) für den nächsten Handshake, auch nach einer Änderung im Betrieb; ohne Thread
#     ebenso (TCP 24999).

const PORT_T := 24998
const PORT_U := 24999
const KEY := "dGhlIHNhbXBsZSBub25jZQ=="
const HOST := "192.168.1.9:24690"

var failures := 0
var checks := 0
var servers: Array = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)

func _init() -> void:
	test_static()
	test_server(true, PORT_T)
	test_server(false, PORT_U)
	for s in servers:
		s.stop()
		s.free()
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)

func test_static() -> void:
	var extra := ["192.168.1.7:24690", "http://10.0.0.5:24691"]
	check(NetServer.origin_allowed("", HOST, extra), "ohne Herkunft (App) erlaubt")
	check(NetServer.origin_allowed("http://192.168.1.9:24690", HOST, extra), "eigene Herkunft weiter erlaubt")
	check(NetServer.origin_allowed("http://192.168.1.7:24690", HOST, extra), "früherer Gastgeber (ip:port aus past) erlaubt")
	check(NetServer.origin_allowed("http://10.0.0.5:24691", HOST, extra), "früherer Gastgeber (http://ip:port) erlaubt")
	check(NetServer.origin_allowed("HTTP://192.168.1.7:24690", HOST, extra), "Groß-/Kleinschreibung des Schemas egal")
	check(not NetServer.origin_allowed("http://192.168.1.7:24690", HOST), "ohne extra: früherer Gastgeber abgelehnt")
	check(not NetServer.origin_allowed("http://192.168.1.7:24690", HOST, []), "leere Liste: abgelehnt")
	for bad in ["https://192.168.1.7:24690", "http://192.168.1.7:24691", "http://192.168.1.7", "http://192.168.1.70:24690",
			"http://192.168.1.7:2469", "http://192.168.1.7:24690/", "http://192.168.1.7:24690/x", "ws://192.168.1.7:24690",
			"http://192.168.1.7:24690.evil.example", "http://evil.192.168.1.7:24690", "null", "192.168.1.7:24690",
			"http://192.168.001.7:24690", "http://user@192.168.1.7:24690", " http://10.0.0.6:24691"]:
		check(not NetServer.origin_allowed(bad, HOST, extra), "abgelehnt: %s" % bad)
	# Muster und Namen in der Liste wirken nicht.
	var patterns := ["192.168.1.*:24690", "http://*:24690", "*", "host.local:24690", "http://192.168.1.0/24:24690", "https://10.0.0.8:24690"]
	for o in ["http://192.168.1.7:24690", "http://host.local:24690", "http://10.0.0.8:24690", "http://192.168.1.0:24690"]:
		check(not NetServer.origin_allowed(o, HOST, patterns), "Muster/Name/https in der Liste wirkt nicht: %s" % o)
	# Normierung
	check(NetServer.extra_origin("192.168.1.7:24690") == "http://192.168.1.7:24690", "extra_origin: ip:port → http://ip:port")
	check(NetServer.extra_origin(" HTTP://10.0.0.5:1 ") == "http://10.0.0.5:1", "extra_origin: Leerraum, Großschreibung")
	check(NetServer.extra_origin("192.168.1.7:24690", false) == "", "extra_origin ohne bare_ok verlangt http://")
	for bad in ["", "192.168.1.7", "192.168.1.256:24690", "192.168.1:24690", "1.2.3.4.5:24690", "1.2.3.4:0", "1.2.3.4:65536",
			"1.2.3.4:024690", "01.2.3.4:24690", "1.2.3.-4:24690", "1.2.3.4:24690:1", "[::1]:24690", "a.b.c.d:24690", "1.2.3.4:+80"]:
		check(NetServer.extra_origin(bad) == "", "extra_origin verwirft: '%s'" % bad)

func test_server(threaded: bool, port: int) -> void:
	var label := "Netz-Thread" if threaded else "ohne Thread"
	var s := NetServer.new()
	s.threaded = threaded
	s.auto_poll = false
	s.web_zip_path = ""
	servers.append(s)
	check(s.start(port, port) == OK, "%s: Server lauscht auf %d" % [label, port])
	check(ws_status(s, "http://10.0.0.5:24690") == 403, "%s: vor der Liste fremde Herkunft 403" % label)
	s.set_extra_origins(["10.0.0.5:24690", "http://192.168.1.7:24691", "192.168.1.*:24690", "bogus", "10.0.0.5:24690"])
	check(s.extra_origins() == ["http://10.0.0.5:24690", "http://192.168.1.7:24691"], "%s: Liste normiert, Unsinn und Doppelte verworfen" % label)
	check(ws_status(s, "http://10.0.0.5:24690") == 101, "%s: früherer Gastgeber 10.0.0.5:24690 → 101" % label)
	check(ws_status(s, "http://192.168.1.7:24691") == 101, "%s: früherer Gastgeber 192.168.1.7:24691 → 101" % label)
	check(ws_status(s, "http://127.0.0.1:%d" % port) == 101, "%s: eigene Herkunft weiter 101" % label)
	check(ws_status(s, "") == 101, "%s: App ohne Herkunft 101" % label)
	check(ws_status(s, "https://10.0.0.5:24690") == 403, "%s: https → 403" % label)
	check(ws_status(s, "http://10.0.0.5:24691") == 403, "%s: fremder Port → 403" % label)
	check(ws_status(s, "http://192.168.1.8:24690") == 403, "%s: Muster in der Liste wirkt nicht → 403" % label)
	s.set_extra_origins(["192.168.1.7:24691"])
	check(ws_status(s, "http://10.0.0.5:24690") == 403, "%s: nach Änderung im Betrieb entfernt → 403" % label)
	check(ws_status(s, "http://192.168.1.7:24691") == 101, "%s: nach Änderung verbleibender Eintrag → 101" % label)
	s.set_extra_origins([])
	check(ws_status(s, "http://192.168.1.7:24691") == 403, "%s: leere Liste → 403" % label)
	check(int(s.stats().get("origin_rejected", 0)) >= 5, "%s: abgelehnte Herkunft gezählt" % label)

# ---------- Hilfen ----------

func pump(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while true:
		for s in servers:
			s.poll()
		if Time.get_ticks_msec() >= end:
			break
		OS.delay_msec(1)

func ws_status(s: NetServer, origin: String) -> int:
	# Handshake mit dieser Herkunft; Statuscode der Antwort (0 = keine).
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", s.port)
	var end := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < end and peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		peer.poll()
		pump(2)
	var head := "GET /ws HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n" % [s.port, KEY]
	if origin != "":
		head += "Origin: %s\r\n" % origin
	peer.put_data((head + "\r\n").to_ascii_buffer())
	var buf := PackedByteArray()
	end = Time.get_ticks_msec() + 2000
	var status := 0
	while Time.get_ticks_msec() < end:
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			buf.append_array(peer.get_partial_data(n)[1])
		var text := buf.get_string_from_ascii()
		if text.contains("\r\n\r\n"):
			status = int(text.get_slice(" ", 1))
			break
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		pump(2)
	peer.disconnect_from_host()
	pump(5)
	return status
