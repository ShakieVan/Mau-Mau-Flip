extends SceneTree

# Modul D, NetServer über 127.0.0.1 (Testports 24790–24794) mit rohen TCP-Clients: HTTP-Routen aus einer Test-Zip (ZIPPacker),
# Gzip, ETag/304, Cache-Regeln, HEAD, 404/405/413/431/400, keep-alive und Pipelining, /info, /apk (gestückelt, Range, HEAD,
# mehrere gleichzeitig, Quelle erst später bereit), TLS-Byte, Rückfallport, eingebaute Hinweisseite ohne web.zip. WebSocket:
# Handshake (RFC-Beispiel), maskierte, fragmentierte, tröpfchenweise und große Rahmen (16/64-Bit-Länge), Ping/Pong, Close in beide
# Richtungen, Fehlerfälle (1002/1003/1007/1009), Herkunft, Sofortantwort auf „ping“, Rate-Limit, Leerlauf-Ping und -Trennung.
# Dazu: Der Netz-Thread liefert Seiten, APK und Pongs, während der Hauptthread steht; derselbe Server ohne Thread.

const PORT_A := 24790
const PORT_C := 24793
const PORT_D := 24794
const KEY := "dGhlIHNhbXBsZSBub25jZQ=="
const DIR := "user://nettest"

var failures := 0
var checks := 0
var servers: Array = []
var files := {}
var apk_bytes := PackedByteArray()
var apk_ready_at := 0
var opened: Array = []
var messages: Array = []
var closed_events: Array = []
var dropped: Array = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)

func _init() -> void:
	prepare_files()
	var a := new_server(true)
	a.web_zip_path = DIR + "/web_test.zip"
	a.apk_provider = apk_source
	check(a.start(PORT_A, PORT_A) == OK and a.port == PORT_A, "Server A lauscht auf %d" % PORT_A)
	a.set_info({"game": "mau-mau-flip", "version": "0.1.1", "name": "Testtisch", "players": 2})
	check(a.has_web_client(), "Test-Zip geladen")
	test_http(a)
	test_tls(a)
	test_apk(a)
	test_fallback()
	test_ws(a)
	test_ws_errors(a)
	test_rate(a)
	test_stalled_main(a)
	test_big_and_idle()
	test_unthreaded()
	for s in servers:
		s.stop()
		s.free()
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)

# ---------- Hilfen ----------

func new_server(threaded: bool) -> NetServer:
	var s := NetServer.new()
	s.threaded = threaded
	s.auto_poll = false
	var sid := s.get_instance_id()
	s.ws_opened.connect(func(c, info): opened.append([sid, c, info]))
	s.ws_message.connect(func(c, t): messages.append([sid, c, t]))
	s.ws_closed.connect(func(c, code, reason): closed_events.append([sid, c, code, reason]))
	s.ws_dropped.connect(func(c, why, size): dropped.append([sid, c, why, size]))
	servers.append(s)
	return s

func apk_source() -> Dictionary:
	if Time.get_ticks_msec() < apk_ready_at:
		return {}
	return {"path": DIR + "/test.apk", "size": apk_bytes.size(), "name": "MauMauFlip-0.1.1.apk"}

func prepare_files() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var js := ""
	for i in range(200):
		js += "console.log('Zeile %d: Mau-Mau Flip');\n" % i
	var webp := PackedByteArray()
	for i in range(3000):
		webp.append((i * 131 + 7) & 255)
	files = {"index.html": "<!doctype html><title>Test</title><p>Hallo Tisch</p>".to_utf8_buffer(), "app.js": js.to_utf8_buffer(),
		"style.css": "body{color:#f4eada}".to_utf8_buffer(), "cards/hell_rot_7.webp": webp, "app.1a2b3c4d.js": "var v=1;".to_utf8_buffer(),
		"fonts/x.woff2": PackedByteArray([0x77, 0x4F, 0x46, 0x32, 1, 2, 3])}
	var z := ZIPPacker.new()
	z.open(DIR + "/web_test.zip")
	for name in files:
		z.start_file(name)
		z.write_file(files[name])
		z.close_file()
	z.close()
	apk_bytes.resize(300000)
	for i in range(0, apk_bytes.size()):
		apk_bytes[i] = (i * 7 + (i >> 9)) & 255
	var f := FileAccess.open(DIR + "/test.apk", FileAccess.WRITE)
	f.store_buffer(apk_bytes)
	f.close()

func pump(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while true:
		for s in servers:
			s.poll()
		if Time.get_ticks_msec() >= end:
			break
		OS.delay_msec(1)

func wait_until(cond: Callable, ms := 2000) -> bool:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		pump(2)
		if cond.call():
			return true
	return cond.call()

func tcp(port: int) -> Dictionary:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", port)
	var end := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < end:
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break
		pump(2)
	return {"peer": peer, "buf": PackedByteArray()}

func send(c: Dictionary, data) -> void:
	c.peer.put_data(data.to_utf8_buffer() if data is String else data)

func fill(c: Dictionary) -> bool:
	# Verfügbare Bytes in den Puffer; false = Verbindung zu.
	c.peer.poll()
	if c.peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false
	var n: int = c.peer.get_available_bytes()
	if n > 0:
		var r: Array = c.peer.get_partial_data(n)
		c.buf.append_array(r[1])
	return c.peer.get_status() == StreamPeerTCP.STATUS_CONNECTED

static func head_end(buf: PackedByteArray) -> int:
	for i in range(buf.size() - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	return -1

func response(c: Dictionary, head_only := false, timeout := 3000) -> Dictionary:
	# Eine HTTP-Antwort lesen: {status, headers, body, open}; status 0 = keine Antwort.
	var end := Time.get_ticks_msec() + timeout
	var open := true
	var cut := -1
	while Time.get_ticks_msec() < end:
		open = fill(c)
		cut = head_end(c.buf)
		if cut >= 0 or not open:
			break
		pump(1)
	if cut < 0:
		return {"status": 0, "headers": {}, "body": PackedByteArray(), "open": open}
	var lines: PackedStringArray = c.buf.slice(0, cut).get_string_from_utf8().split("\r\n")
	var headers := {}
	for i in range(1, lines.size()):
		var colon := lines[i].find(":")
		headers[lines[i].left(colon).to_lower()] = lines[i].substr(colon + 1).strip_edges()
	var status := int(lines[0].get_slice(" ", 1))
	c.buf = c.buf.slice(cut + 4)
	var body := PackedByteArray()
	if not head_only and not status in [101, 204, 304]:
		if headers.has("content-length"):
			var length := int(headers["content-length"])
			while c.buf.size() < length and Time.get_ticks_msec() < end:
				open = fill(c)
				if not open and c.buf.size() < length:
					fill(c)
					break
				pump(1)
			body = c.buf.slice(0, length)
			c.buf = c.buf.slice(mini(length, c.buf.size()))
		else:
			while open and Time.get_ticks_msec() < end:
				open = fill(c)
				pump(1)
			body = c.buf
			c.buf = PackedByteArray()
	pump(5)
	open = fill(c)
	return {"status": status, "headers": headers, "body": body, "open": open}

func get_req(port: int, path: String, extra := "", method := "GET") -> Dictionary:
	var c := tcp(port)
	send(c, "%s %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n%s\r\n" % [method, path, port, extra])
	var r := response(c, method == "HEAD")
	c.peer.disconnect_from_host()
	return r

func closed_soon(c: Dictionary, ms := 1000) -> bool:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		if not fill(c):
			return true
		pump(2)
	return not fill(c)

# --- WebSocket roh ---

func ws_open(s: NetServer, extra := "") -> Dictionary:
	var port := s.port
	var c := tcp(port)
	var before := opened.size()
	send(c, "GET /ws HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nUpgrade: websocket\r\nConnection: keep-alive, Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\nUser-Agent: Testclient\r\n%s\r\n" % [port, KEY, extra])
	c["response"] = response(c, true)
	if c.response.status == 101:
		wait_until(func(): return opened.size() > before)
		c["conn"] = int(opened[-1][1]) if opened.size() > before else -1
		c["sid"] = s.get_instance_id()
		c["info"] = opened[-1][2] if opened.size() > before else {}
	return c

func ws_send(c: Dictionary, opcode: int, payload, fin := true, masked := true) -> void:
	var bytes: PackedByteArray = payload.to_utf8_buffer() if payload is String else payload
	send(c, NetWs.encode_frame(opcode, bytes, fin, masked))

func ws_frame(c: Dictionary, timeout := 2000) -> Dictionary:
	# Nächster Rahmen vom Server: {opcode, payload, text, masked}; {closed: true} wenn TCP zu, {} bei Zeitgrenze.
	var end := Time.get_ticks_msec() + timeout
	while true:
		var f := NetWs.parse_frame(c.buf, 0, 1 << 22)
		if f.status == "ok":
			c.buf = c.buf.slice(f.size)
			return {"opcode": f.opcode, "payload": f.payload, "text": f.payload.get_string_from_utf8() if f.opcode == 1 else "", "masked": f.masked, "fin": f.fin}
		var open := fill(c)
		if not open and NetWs.parse_frame(c.buf, 0, 1 << 22).status != "ok":
			return {"closed": true}
		if Time.get_ticks_msec() >= end:
			return {}
		pump(1)
	return {}

func msgs(w: Dictionary) -> Array:
	return messages.filter(func(m): return m[0] == w.sid and m[1] == w.conn).map(func(m): return m[2])

func closed_code(w: Dictionary) -> int:
	for e in closed_events:
		if e[0] == w.sid and e[1] == w.conn:
			return e[2]
	return -1

func drops(w: Dictionary, why: String) -> int:
	return dropped.filter(func(d): return d[0] == w.sid and d[1] == w.conn and d[2] == why).size()

# ---------- HTTP ----------

func test_http(a: NetServer) -> void:
	var r := get_req(PORT_A, "/")
	check(r.status == 200 and r.body == files["index.html"], "GET / liefert index.html")
	check(str(r.headers.get("content-type", "")).begins_with("text/html") and r.headers.get("cache-control") == "no-cache", "HTML: Typ und no-cache")
	check(r.headers.has("etag") and r.headers.has("date") and r.headers.get("connection") == "keep-alive", "ETag, Date, keep-alive")
	check(not r.headers.has("strict-transport-security") and not str(r.headers).contains("upgrade-insecure"), "kein HSTS, kein upgrade-insecure-requests")
	var gz := get_req(PORT_A, "/app.js", "Accept-Encoding: gzip, deflate\r\n")
	check(gz.status == 200 and gz.headers.get("content-encoding") == "gzip" and gz.headers.get("vary") == "Accept-Encoding", "app.js gzip-komprimiert")
	check(gz.body.size() < files["app.js"].size() and gz.body.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP) == files["app.js"], "gzip entpackt = Original")
	var plain := get_req(PORT_A, "/app.js")
	check(plain.status == 200 and plain.body == files["app.js"] and not plain.headers.has("content-encoding"), "ohne Accept-Encoding unkomprimiert")
	check(str(plain.headers.get("content-type", "")).begins_with("text/javascript"), "JS-Typ")
	var etag := str(plain.headers.get("etag", ""))
	var nm := get_req(PORT_A, "/app.js", "If-None-Match: %s\r\n" % etag)
	check(nm.status == 304 and nm.body.is_empty() and nm.headers.get("etag") == etag, "If-None-Match → 304")
	check(get_req(PORT_A, "/app.1a2b3c4d.js").headers.get("cache-control", "").contains("immutable"), "Datei mit Prüfsumme: ein Jahr Cache")
	check(get_req(PORT_A, "/style.css?v=0.1.1").headers.get("cache-control", "").contains("max-age=31536000"), "?v= versioniert")
	var webp := get_req(PORT_A, "/cards/hell_rot_7.webp")
	check(webp.status == 200 and webp.body == files["cards/hell_rot_7.webp"] and webp.headers.get("content-type") == "image/webp", "Kartenbild binär und image/webp")
	check(get_req(PORT_A, "/fonts/x.woff2").headers.get("content-type") == "font/woff2", "woff2-Typ")
	var head := get_req(PORT_A, "/cards/hell_rot_7.webp", "", "HEAD")
	check(head.status == 200 and int(head.headers.get("content-length", "0")) == 3000 and head.body.is_empty(), "HEAD: Länge ohne Inhalt")
	check(get_req(PORT_A, "/nichtda.png").status == 404, "unbekannte Datei → 404")
	check(get_req(PORT_A, "/../index.html").status == 404, "Pfad mit .. → 404")
	var post := get_req(PORT_A, "/", "Content-Length: 3\r\n", "POST")
	check(post.status == 405 and post.headers.get("allow") == "GET, HEAD" and post.headers.get("connection") == "close", "POST → 405 mit Allow")
	check(get_req(PORT_A, "/", "Content-Length: 100000\r\n").status == 413, "zu großer Inhalt → 413")
	var c := tcp(PORT_A)
	send(c, "GET / HTTP/1.1\r\nHost: x\r\nX-Pad: %s\r\n\r\n" % "p".repeat(9000))
	check(response(c).status == 431, "Kopf über 8 KB → 431")
	c.peer.disconnect_from_host()
	var g := tcp(PORT_A)
	send(g, "HALLO WELT\r\n\r\n")
	check(response(g).status == 400 and closed_soon(g), "Unsinn → 400 und Verbindung zu")
	# keep-alive und Pipelining
	var k := tcp(PORT_A)
	send(k, "GET /style.css HTTP/1.1\r\nHost: x\r\n\r\n")
	var k1 := response(k)
	send(k, "GET /index.html HTTP/1.1\r\nHost: x\r\n\r\nGET /app.1a2b3c4d.js HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
	var k2 := response(k)
	var k3 := response(k)
	check(k1.status == 200 and k1.open and k2.body == files["index.html"] and k3.body == files["app.1a2b3c4d.js"], "keep-alive und zwei Anfragen in einem Paket")
	check(k3.headers.get("connection") == "close" and closed_soon(k), "Connection: close beendet die Verbindung")
	var info := get_req(PORT_A, "/info")
	var data = JSON.parse_string(info.body.get_string_from_utf8())
	check(info.status == 200 and data is Dictionary and int(data.port) == PORT_A and data.name == "Testtisch" and info.headers.get("cache-control") == "no-store", "/info als JSON mit Port")
	check(get_req(PORT_A, "/ws").status == 426, "/ws ohne Upgrade → 426")
	check(int(a.stats().http_404) >= 2 and int(a.stats().header_too_big) == 1, "Zähler 404 und Kopfgröße")

func test_tls(a: NetServer) -> void:
	var c := tcp(PORT_A)
	var t0 := Time.get_ticks_msec()
	send(c, PackedByteArray([0x16, 0x03, 0x01, 0x00, 0xA5, 0x01, 0x00, 0x00, 0xA1, 0x03, 0x03]))
	var gone := closed_soon(c, 1500)
	check(gone and c.buf.is_empty(), "TLS-ClientHello: sofort geschlossen, keine Antwort")
	check(Time.get_ticks_msec() - t0 < 500, "TLS-Abweisung schnell (%d ms)" % (Time.get_ticks_msec() - t0))
	check(int(a.stats().tls_rejected) == 1, "TLS-Versuch gezählt")
	check(get_req(PORT_A, "/").status == 200, "danach geht http weiter")

# ---------- APK ----------

func test_apk(a: NetServer) -> void:
	var r := get_req(PORT_A, "/apk")
	check(r.status == 200 and r.body == apk_bytes, "APK vollständig (%d Byte)" % r.body.size())
	check(r.headers.get("content-type") == "application/vnd.android.package-archive", "APK-Typ")
	check(str(r.headers.get("content-disposition", "")).contains("MauMauFlip-0.1.1.apk") and r.headers.get("accept-ranges") == "bytes", "Dateiname und Range-Hinweis")
	var part := get_req(PORT_A, "/apk", "Range: bytes=1000-1999\r\n")
	check(part.status == 206 and part.body == apk_bytes.slice(1000, 2000) and part.headers.get("content-range") == "bytes 1000-1999/300000", "Range 1000–1999 → 206")
	var tail := get_req(PORT_A, "/apk", "Range: bytes=-500\r\n")
	check(tail.status == 206 and tail.body == apk_bytes.slice(299500), "Range die letzten 500 Byte")
	var rest := get_req(PORT_A, "/apk", "Range: bytes=299000-\r\n")
	check(rest.status == 206 and rest.body == apk_bytes.slice(299000), "Range ab Byte 299000")
	check(get_req(PORT_A, "/apk", "Range: bytes=400000-\r\n").status == 416, "Range hinter dem Ende → 416")
	var head := get_req(PORT_A, "/apk", "", "HEAD")
	check(head.status == 200 and int(head.headers.get("content-length", "0")) == 300000 and head.body.is_empty(), "HEAD /apk")
	# drei gleichzeitig, verzahnt gelesen
	var conns := []
	for i in range(3):
		var c := tcp(PORT_A)
		send(c, "GET /apk HTTP/1.1\r\nHost: x\r\n\r\n")
		conns.append(c)
	var end := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < end:
		var all_done := true
		for c in conns:
			fill(c)
			if c.buf.size() < 300000 + 200:
				all_done = false
		if all_done:
			break
		pump(1)
	var ok := true
	for c in conns:
		var cut := head_end(c.buf)
		if cut < 0 or c.buf.slice(cut + 4) != apk_bytes:
			ok = false
		c.peer.disconnect_from_host()
	check(ok, "drei Downloads gleichzeitig vollständig")
	# Quelle erst nach 600 ms bereit: Anfrage wartet
	apk_ready_at = Time.get_ticks_msec() + 600
	a.set_apk({})
	var late := get_req(PORT_A, "/apk")
	check(late.status == 200 and late.body.size() == 300000, "APK-Quelle später bereit: Anfrage wartet und bekommt die Datei")
	check(int(a.stats().apk_done) >= 7 and int(a.stats().apk_active) == 0, "Zähler: fertig %d, aktiv %d" % [a.stats().apk_done, a.stats().apk_active])

func test_fallback() -> void:
	var b := new_server(true)
	b.web_zip_path = ""
	check(b.start(PORT_A, PORT_A + 2) == OK and b.port == PORT_A + 1, "Rückfall auf den nächsten Port (%d)" % b.port)
	var r := get_req(b.port, "/")
	var text: String = r.body.get_string_from_utf8()
	check(r.status == 200 and text.contains("Mau-Mau Flip") and text.contains("href=\"/apk\""), "ohne web.zip: eingebaute Hinweisseite mit APK-Link")
	check(get_req(b.port, "/app.js").status == 404, "ohne web.zip: andere Dateien 404")
	check(get_req(b.port, "/apk").status == 404, "ohne APK-Quelle: /apk → 404")
	b.stop()

# ---------- WebSocket ----------

func test_ws(a: NetServer) -> void:
	var w := ws_open(a)
	check(w.response.status == 101 and w.response.headers.get("sec-websocket-accept") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", "Handshake: 101 und Accept-Schlüssel")
	check(str(w.response.headers.get("upgrade", "")).to_lower() == "websocket", "Upgrade-Kopf")
	var conn: int = w.conn
	check(conn > 0 and w.info.host == "127.0.0.1:%d" % PORT_A and w.info.agent == "Testclient" and w.info.address == "127.0.0.1", "ws_opened mit Host, Agent, Adresse")
	ws_send(w, NetWs.OP_TEXT, "Hallo Welt")
	check(wait_until(func(): return msgs(w).has("Hallo Welt")), "maskierte Textnachricht angekommen")
	a.send_text(conn, "Grüße 🃏")
	var f := ws_frame(w)
	check(f.get("opcode") == 1 and f.text == "Grüße 🃏" and not f.masked and f.fin, "Server schreibt unmaskierten Textrahmen")
	var w2 := ws_open(a)
	a.send_text_many([conn, w2.conn], "an alle")
	check(ws_frame(w).get("text") == "an alle" and ws_frame(w2).get("text") == "an alle", "send_text_many an zwei Verbindungen")
	# fragmentiert, mit Ping dazwischen
	ws_send(w, NetWs.OP_TEXT, "Teil1-", false)
	ws_send(w, NetWs.OP_PING, "p")
	ws_send(w, NetWs.OP_CONT, "Teil2-", false)
	ws_send(w, NetWs.OP_CONT, "Ende", true)
	var pong := ws_frame(w)
	check(pong.get("opcode") == NetWs.OP_PONG and pong.payload.get_string_from_utf8() == "p", "Ping mitten in Fragmenten → Pong mit gleicher Nutzlast")
	check(wait_until(func(): return msgs(w).has("Teil1-Teil2-Ende")), "fragmentierte Nachricht zusammengesetzt")
	# Byte für Byte
	var frame := NetWs.encode_frame(NetWs.OP_TEXT, "tröpfchenweise".to_utf8_buffer(), true, true)
	for i in range(frame.size()):
		send(w, frame.slice(i, i + 1))
		pump(1)
	check(wait_until(func(): return msgs(w).has("tröpfchenweise")), "Rahmen Byte für Byte")
	# Sofortantwort auf das Lebenszeichen, ohne die Spielsteuerung
	var before := messages.size()
	ws_send(w, NetWs.OP_TEXT, "{\"t\":\"ping\",\"ts\":77}")
	var p := ws_frame(w)
	check(p.get("text") == "{\"t\":\"pong\",\"ts\":77}", "„ping“ → „pong“ direkt aus dem Netz-Thread")
	pump(20)
	check(messages.size() == before, "Ping erreicht die Spielsteuerung nicht")
	# 9 KB: verworfen, Verbindung bleibt
	ws_send(w, NetWs.OP_TEXT, "{\"t\":\"log\",\"text\":\"%s\"}" % "x".repeat(9000))
	check(wait_until(func(): return drops(w, "size") > 0), "Nachricht über 8 KB verworfen (ws_dropped size)")
	ws_send(w, NetWs.OP_TEXT, "danach")
	check(wait_until(func(): return msgs(w).has("danach")), "nach Übergröße geht es weiter")
	# Client schließt
	ws_send(w, NetWs.OP_CLOSE, NetWs.close_payload(1000, "tschüss"))
	var echo := ws_frame(w)
	check(echo.get("opcode") == NetWs.OP_CLOSE and NetWs.parse_close(echo.payload)[0] == 1000, "Close 1000 wird beantwortet")
	check(closed_soon(w) and wait_until(func(): return closed_code(w) == 1000), "danach TCP zu, ws_closed 1000")
	# Server schließt
	a.close_ws(w2.conn, 4000, "ersetzt")
	var sc := ws_frame(w2)
	check(sc.get("opcode") == NetWs.OP_CLOSE and NetWs.parse_close(sc.payload) == [4000, "ersetzt"], "Server-Close mit Code und Grund")
	ws_send(w2, NetWs.OP_CLOSE, NetWs.close_payload(4000))
	check(closed_soon(w2) and wait_until(func(): return closed_code(w2) == 4000), "Server-Close bestätigt, ws_closed 4000")
	# Herkunft und Kopfprüfungen
	check(ws_open(a, "Origin: http://evil.example\r\n").response.status == 403, "fremde Herkunft → 403")
	var same := ws_open(a, "Origin: http://127.0.0.1:%d\r\n" % PORT_A)
	check(same.response.status == 101, "gleiche Herkunft → 101")
	same.peer.disconnect_from_host()
	var c := tcp(PORT_A)
	send(c, "GET /ws HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\n\r\n" % KEY)
	check(response(c).status == 426, "ohne Sec-WebSocket-Version → 426")
	var c2 := tcp(PORT_A)
	send(c2, "GET /ws HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: kurz\r\nSec-WebSocket-Version: 13\r\n\r\n")
	check(response(c2).status == 400, "ungültiger Schlüssel → 400")

func test_ws_errors(a: NetServer) -> void:
	var cases := [["unmaskiert", 1002], ["binär", 1003], ["kein UTF-8", 1007], ["zu groß", 1009], ["Fortsetzung ohne Anfang", 1002]]
	for case in cases:
		var w := ws_open(a)
		match case[0]:
			"unmaskiert":
				ws_send(w, NetWs.OP_TEXT, "offen", true, false)
			"binär":
				ws_send(w, NetWs.OP_BINARY, PackedByteArray([1, 2, 3]))
			"kein UTF-8":
				ws_send(w, NetWs.OP_TEXT, PackedByteArray([0x61, 0xC0, 0xAF]))
			"zu groß":
				var big := PackedByteArray()
				big.resize(70000)
				big.fill(0x61)
				ws_send(w, NetWs.OP_TEXT, big)
			"Fortsetzung ohne Anfang":
				ws_send(w, NetWs.OP_CONT, "x")
		var f := ws_frame(w)
		var code: int = NetWs.parse_close(f.payload)[0] if f.get("opcode") == NetWs.OP_CLOSE else -1
		check(code == case[1], "%s → Close %d (bekommen %d)" % [case[0], case[1], code])
		ws_send(w, NetWs.OP_CLOSE, NetWs.close_payload(code))
		check(closed_soon(w) and wait_until(func(): return closed_code(w) == case[1]), "%s: Verbindung zu" % case[0])

func test_rate(a: NetServer) -> void:
	var w := ws_open(a)
	var conn: int = w.conn
	var burst := PackedByteArray()
	for i in range(30):
		burst.append_array(NetWs.encode_frame(NetWs.OP_TEXT, ("{\"t\":\"x\",\"n\":%d}" % i).to_utf8_buffer(), true, true))
	send(w, burst)
	pump(150)
	var got := msgs(w).size()
	var dropped_n := drops(w, "rate")
	check(got >= 20 and got <= 23 and got + dropped_n == 30, "30 auf einmal: %d angenommen, %d verworfen (Grenze 20/s)" % [got, dropped_n])
	check(fill(w), "Verbindung bleibt nach leichter Überschreitung")
	pump(1100)
	ws_send(w, NetWs.OP_TEXT, "nach einer Sekunde")
	check(wait_until(func(): return msgs(w).has("nach einer Sekunde")), "nach einer Sekunde wieder frei")
	var flood := PackedByteArray()
	for i in range(150):
		flood.append_array(NetWs.encode_frame(NetWs.OP_TEXT, "f".to_utf8_buffer(), true, true))
	send(w, flood)
	var f := ws_frame(w)
	check(f.get("opcode") == NetWs.OP_CLOSE and NetWs.parse_close(f.payload)[0] == 1008, "Dauerflut → Close 1008")
	check(int(a.stats().rate_dropped) >= dropped_n, "Zähler rate_dropped")

# ---------- Hauptthread steht ----------

var _side := {}

func _side_job(port: int) -> void:
	# Läuft in einem eigenen Thread, während der Hauptthread schläft (kein poll()).
	var out := {"page": 0, "apk": 0, "pong": ""}
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", port)
	var buf := PackedByteArray()
	var end := Time.get_ticks_msec() + 3000
	while peer.get_status() != StreamPeerTCP.STATUS_CONNECTED and Time.get_ticks_msec() < end:
		peer.poll()
		OS.delay_msec(2)
	peer.put_data("GET /index.html HTTP/1.1\r\nHost: x\r\n\r\nGET /apk HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n".to_utf8_buffer())
	while Time.get_ticks_msec() < end:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var n := peer.get_available_bytes()
		if n > 0:
			buf.append_array(peer.get_partial_data(n)[1])
		else:
			OS.delay_msec(2)
	var text := buf.slice(0, 400).get_string_from_utf8()
	out.page = 200 if text.begins_with("HTTP/1.1 200") else 0
	out.apk = buf.size()
	var ws := StreamPeerTCP.new()
	ws.connect_to_host("127.0.0.1", port)
	end = Time.get_ticks_msec() + 3000
	while ws.get_status() != StreamPeerTCP.STATUS_CONNECTED and Time.get_ticks_msec() < end:
		ws.poll()
		OS.delay_msec(2)
	ws.put_data(("GET /ws HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n" % KEY).to_utf8_buffer())
	var wbuf := PackedByteArray()
	var sent := false
	while Time.get_ticks_msec() < end:
		ws.poll()
		var n := ws.get_available_bytes()
		if n > 0:
			wbuf.append_array(ws.get_partial_data(n)[1])
		var cut := head_end(wbuf)
		if cut >= 0 and not sent:
			sent = true
			wbuf = wbuf.slice(cut + 4)
			ws.put_data(NetWs.encode_frame(NetWs.OP_TEXT, "{\"t\":\"ping\",\"ts\":4242}".to_utf8_buffer(), true, true))
		if sent:
			var f := NetWs.parse_frame(wbuf, 0, 4096)
			if f.status == "ok":
				out.pong = f.payload.get_string_from_utf8()
				break
		OS.delay_msec(2)
	ws.disconnect_from_host()
	peer.disconnect_from_host()
	_side = out

func test_stalled_main(_a: NetServer) -> void:
	# docs/recherche/13_gegenpruefung.md Punkt 6: Steht die Hauptschleife, liefert der Netz-Thread weiter aus.
	pump(50)
	var t := Thread.new()
	t.start(_side_job.bind(PORT_A))
	OS.delay_msec(1500)            # Hauptthread „hängt“ – kein poll()
	t.wait_to_finish()
	check(_side.get("page") == 200, "Seite ausgeliefert, während der Hauptthread steht")
	check(int(_side.get("apk", 0)) > 300000, "APK ausgeliefert, während der Hauptthread steht (%d Byte)" % int(_side.get("apk", 0)))
	check(_side.get("pong") == "{\"t\":\"pong\",\"ts\":4242}", "Lebenszeichen beantwortet, während der Hauptthread steht")
	pump(50)

# ---------- große Rahmen, Leerlauf ----------

func test_big_and_idle() -> void:
	var c := new_server(true)
	c.max_client_message = 200000
	c.max_frame_bytes = 200000
	c.ws_ping_ms = 300
	c.ws_timeout_ms = 900
	check(c.start(PORT_C, PORT_C) == OK, "Server C (große Rahmen) auf %d" % PORT_C)
	var w := ws_open(c)
	var conn: int = w.conn
	var t60 := "{\"t\":\"x\",\"d\":\"%s\"}" % "a".repeat(60000)
	var t100 := "{\"t\":\"y\",\"d\":\"%s\"}" % "b".repeat(100000)
	ws_send(w, NetWs.OP_TEXT, t60)
	ws_send(w, NetWs.OP_TEXT, t100)
	var pieces := "{\"t\":\"z\",\"d\":\"%s\"}" % "c".repeat(100000)
	var bytes := pieces.to_utf8_buffer()
	var step := bytes.size() / 7 + 1
	for i in range(0, bytes.size(), step):
		var last := i + step >= bytes.size()
		ws_send(w, NetWs.OP_TEXT if i == 0 else NetWs.OP_CONT, bytes.slice(i, i + step), last)
	check(wait_until(func(): return msgs(w).size() == 3, 4000), "drei große Nachrichten angekommen")
	var got := msgs(w)
	check(got.size() == 3 and got[0] == t60 and got[1] == t100 and got[2] == pieces, "60 KB (16-Bit-Länge), 100 KB (64-Bit-Länge), 100 KB in 7 Fragmenten unverändert")
	c.send_text(conn, t100)
	var back := ws_frame(w)
	check(back.get("text") == t100, "Server schreibt 100 KB (64-Bit-Länge)")
	# Leerlauf: Server pingt nach 300 ms, trennt nach 900 ms ohne Antwort
	var ping := ws_frame(w, 1000)
	check(ping.get("opcode") == NetWs.OP_PING, "Leerlauf → Ping vom Server")
	check(closed_soon(w, 2000) and wait_until(func(): return closed_code(w) == NetWs.CLOSE_TIMEOUT), "ohne Antwort getrennt (4001)")
	c.stop()

func test_unthreaded() -> void:
	var d := new_server(false)
	d.web_zip_path = DIR + "/web_test.zip"
	check(d.start(PORT_D, PORT_D) == OK, "Server D ohne Thread auf %d" % PORT_D)
	check(get_req(PORT_D, "/style.css").body == files["style.css"], "ohne Thread: Datei ausgeliefert")
	var w := ws_open(d)
	ws_send(w, NetWs.OP_TEXT, "ohne Thread")
	check(wait_until(func(): return msgs(w).has("ohne Thread")), "ohne Thread: WebSocket-Nachricht")
	ws_send(w, NetWs.OP_TEXT, "{\"t\":\"ping\",\"ts\":1}")
	check(ws_frame(w).get("text") == "{\"t\":\"pong\",\"ts\":1}", "ohne Thread: Pong")
	d.stop()
