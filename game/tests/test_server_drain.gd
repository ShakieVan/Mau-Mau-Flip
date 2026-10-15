extends SceneTree

# Mau-Mau Flip (Beta 1.6.2, Gastgeber-Übergabe im WLAN, docs/module/uebergabe.md 10.7 Schritt 3 und Abschnitt 11): NetServer.drain
# über 127.0.0.1 (TCP 24995–24997) mit rohen WebSocket-Gästen, die in eigenen Threads lesen (der Hauptthread steht während drain()).
#  A  Netz-Thread: send_text + send_text_many (klein, großes „bk“ über 1,5 MB, klein) + drain(500) + stop(): alles kommt in der
#     Reihenfolge und vollständig an, danach der Close-Rahmen 1001; send + close_ws + drain: Nachricht, dann Close 1000.
#  B  Ein Gast, der nichts abholt: drain() kehrt nach der Frist zurück (blockiert nicht länger).
#  C  Gegenprobe ohne drain: Die große Nachricht darf verloren gehen (nur protokolliert), aber der Strom bleibt gültig – kein
#     Close-Rahmen mitten in einer halb gesendeten Nachricht.
#  D  Ohne Thread (threaded = false): drain() pumpt selbst, alles kommt an.

const PORT_A := 24995
const PORT_B := 24996
const PORT_D := 24997
const KEY := "dGhlIHNhbXBsZSBub25jZQ=="

var failures := 0
var checks := 0
var servers: Array = []
var opened: Array = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)

func _init() -> void:
	var idle := NetServer.new()
	check(idle.drain(100), "drain ohne laufenden Server: sofort true")
	idle.free()
	test_threaded()
	test_stuck_and_without()
	test_unthreaded()
	for s in servers:
		s.stop()
		s.free()
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)

# ---------- Hilfen ----------

func new_server(threaded: bool, port: int) -> NetServer:
	var s := NetServer.new()
	s.threaded = threaded
	s.auto_poll = false
	s.web_zip_path = ""
	s.ws_opened.connect(func(c, _info): opened.append([s.get_instance_id(), c]))
	servers.append(s)
	check(s.start(port, port) == OK and s.port == port, "Server lauscht auf %d (%s)" % [port, "Thread" if threaded else "ohne Thread"])
	return s

func pump(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while true:
		for s in servers:
			s.poll()
		if Time.get_ticks_msec() >= end:
			break
		OS.delay_msec(1)

func ws_open(s: NetServer) -> Dictionary:
	# Roher WebSocket-Gast: Handshake im Hauptthread, danach {peer, buf (schon gelesene Bytes nach dem Kopf), conn}.
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", s.port)
	var end := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < end and peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		peer.poll()
		pump(2)
	var before := opened.size()
	peer.put_data(("GET /ws HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n" % [s.port, KEY]).to_ascii_buffer())
	var buf := PackedByteArray()
	var cut := -1
	end = Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < end and (cut < 0 or opened.size() <= before):
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			buf.append_array(peer.get_partial_data(n)[1])
		if cut < 0:
			cut = _head_end(buf)
		pump(2)
	var ok := cut >= 0 and buf.slice(0, cut).get_string_from_ascii().begins_with("HTTP/1.1 101")
	check(ok and opened.size() > before, "WebSocket-Handshake auf %d" % s.port)
	return {"peer": peer, "buf": buf.slice(cut + 4) if cut >= 0 else PackedByteArray(), "conn": int(opened[-1][1]) if opened.size() > before else -1}

static func _head_end(buf: PackedByteArray) -> int:
	for i in range(buf.size() - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	return -1

func start_reader(w: Dictionary, max_ms := 6000) -> Thread:
	var t := Thread.new()
	t.start(_reader.bind(w.peer, w.buf, max_ms))
	return t

static func _reader(peer: StreamPeerTCP, start: PackedByteArray, max_ms: int) -> PackedByteArray:
	# Eigener Thread: lesen, bis der Server trennt (oder die Frist abläuft).
	var buf := start.duplicate()
	var end := Time.get_ticks_msec() + max_ms
	while Time.get_ticks_msec() < end:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var n := peer.get_available_bytes()
		if n > 0:
			var r: Array = peer.get_partial_data(n)
			buf.append_array(r[1])
		else:
			OS.delay_msec(1)
	peer.disconnect_from_host()
	return buf

static func frames(buf: PackedByteArray) -> Dictionary:
	# Alle vollständigen Rahmen: {list: [{op, text, code}], rest: "need"|"" , error: bool}
	var list: Array = []
	var off := 0
	while off < buf.size():
		var f := NetWs.parse_frame(buf, off, 1 << 23)
		if f.status == "need":
			return {"list": list, "rest": "need", "error": false}
		if f.status != "ok":
			return {"list": list, "rest": "", "error": true}
		off += int(f.size)
		var item := {"op": int(f.opcode), "text": "", "code": 0}
		if int(f.opcode) == NetWs.OP_TEXT:
			item.text = (f.payload as PackedByteArray).get_string_from_utf8()
		elif int(f.opcode) == NetWs.OP_CLOSE:
			item.code = int(NetWs.parse_close(f.payload)[0])
		list.append(item)
	return {"list": list, "rest": "", "error": false}

static func big_bk(size: int, tag: String) -> String:
	# Wie ein Sicherungs-„bk“: ein JSON-Text über size Zeichen.
	var chunk := "Karte-%s-0123456789abcdef;" % tag
	return JSON.stringify({"t": "bk", "tag": tag, "data": chunk.repeat(size / chunk.length() + 1)})

# ---------- A: Netz-Thread ----------

func test_threaded() -> void:
	var s := new_server(true, PORT_A)
	var w1 := ws_open(s)
	var w2 := ws_open(s)
	var big := big_bk(1_600_000, "A")
	var r1 := start_reader(w1)
	var r2 := start_reader(w2)
	s.send_text(w1.conn, "{\"t\":\"handover_ok\"}")
	s.send_text_many([w1.conn, w2.conn], "{\"t\":\"note\",\"n\":1}")
	s.send_text(w1.conn, big)
	s.send_text_many([w1.conn, w2.conn], "{\"t\":\"move\",\"how\":\"lan\"}")
	s.close_ws(w2.conn, NetWs.CLOSE_NORMAL, "umgezogen")
	var t0 := Time.get_ticks_msec()
	var ok := s.drain(500)
	var took := Time.get_ticks_msec() - t0
	check(ok, "drain(500) mit lesenden Gästen: true (%d ms)" % took)
	check(took < 500, "drain kehrt zurück, sobald alles hinaus ist (%d ms)" % took)
	s.stop()
	var f1 := frames(r1.wait_to_finish())
	var f2 := frames(r2.wait_to_finish())
	var l1: Array = f1.list
	check(not f1.error and l1.size() == 5, "Gast 1: vier Nachrichten und Close, Strom gültig (%d Rahmen, Fehler %s, Rest %s, letzter op %s)" % [l1.size(), f1.error, f1.rest, l1[-1].op if l1.size() > 0 else -1])
	if l1.size() >= 5:
		check(l1[0].text == "{\"t\":\"handover_ok\"}" and l1[1].text.contains("note") and l1[2].text == big and l1[3].text.contains("move"),
			"Gast 1: Reihenfolge und großes bk vollständig (%d Zeichen)" % big.length())
		check(l1[4].op == NetWs.OP_CLOSE and l1[4].code == NetWs.CLOSE_GOING_AWAY, "Gast 1: danach Close 1001 von stop()")
	var l2: Array = f2.list
	check(not f2.error and l2.size() == 3, "Gast 2: zwei Nachrichten und Close (%d Rahmen)" % l2.size())
	if l2.size() >= 3:
		check(l2[0].text.contains("note") and l2[1].text.contains("move"), "Gast 2: note, dann move")
		check(l2[2].op == NetWs.OP_CLOSE and l2[2].code == NetWs.CLOSE_NORMAL, "Gast 2: close_ws-Rahmen 1000 kommt vor stop() an (nicht 1001)")
	check(s.drain(50), "drain nach stop(): true")

# ---------- B und C: Gast holt nichts ab, Gegenprobe ohne drain ----------

func test_stuck_and_without() -> void:
	var s := new_server(true, PORT_B)
	var stuck := ws_open(s)
	var w := ws_open(s)
	s.send_text(stuck.conn, big_bk(3_500_000, "B"))
	var t0 := Time.get_ticks_msec()
	var ok := s.drain(300)
	var took := Time.get_ticks_msec() - t0
	check(took >= 0 and took < 300 + 250, "drain(300) mit nicht lesendem Gast blockiert nicht länger als die Frist (%d ms)" % took)
	print("Info: drain mit nicht lesendem Gast → %s nach %d ms (true nur, wenn das Betriebssystem alles puffert)" % [ok, took])
	# Gegenprobe: großes bk und sofort stop() – ohne drain.
	var big := big_bk(1_600_000, "C")
	var r := start_reader(w)
	s.send_text(w.conn, "{\"t\":\"vorher\"}")
	s.send_text(w.conn, big)
	s.stop()
	var f := frames(r.wait_to_finish())
	stuck.peer.disconnect_from_host()
	var l: Array = f.list
	check(not f.error, "ohne drain: Strom bleibt gültig (kein Close-Rahmen mitten in einer Nachricht)")
	var got := l.any(func(x): return x.text == big)
	var close_at := -1
	for i in l.size():
		if l[i].op == NetWs.OP_CLOSE:
			close_at = i
	check(close_at < 0 or (close_at == l.size() - 1 and f.rest == ""), "ohne drain: Close höchstens als letzter Rahmen, hinter vollständigen Nachrichten")
	print("Info: ohne drain kam das große bk %s an (%d Rahmen, Close %s)" % ["vollständig" if got else "NICHT", l.size(), "ja" if close_at >= 0 else "nein"])

# ---------- D: ohne Thread ----------

func test_unthreaded() -> void:
	var s := new_server(false, PORT_D)
	var w := ws_open(s)
	var big := big_bk(1_600_000, "D")
	var r := start_reader(w)
	s.send_text(w.conn, big)
	s.send_text(w.conn, "{\"t\":\"move\"}")
	check(s.drain(500), "ohne Thread: drain(500) true")
	s.stop()
	var l: Array = frames(r.wait_to_finish()).list
	check(l.size() == 3 and l[0].text == big and l[1].text == "{\"t\":\"move\"}" and l[2].op == NetWs.OP_CLOSE,
		"ohne Thread: bk, move, dann Close (%d Rahmen)" % l.size())
