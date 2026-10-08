class_name NetServer
extends Node

# Ein TCP-Port für alles (docs/BETA1_PLAN.md Abschnitt 5, docs/recherche/17_https_empfehlung.md 2.2): HTTP/1.1 für die Seiten des
# Browser-Clients (aus res://assets/web.zip), /info, /apk (gestückelt gestreamt) und /ws mit eigenem WebSocket nach RFC 6455.
# Kein HSTS, keine Umleitung auf https, kein upgrade-insecure-requests. TLS-Versuche (erstes Byte 0x16) werden sofort geschlossen,
# damit Safari ohne 3-s-Wartezeit auf http zurückfällt.
#
# Thread oder Hauptthread (bewusst entschieden, docs/recherche/13_gegenpruefung.md Punkt 6): Die gesamte Netzarbeit – Annehmen,
# HTTP, Dateien, APK-Ströme, WebSocket-Rahmen, Ping/Pong, Grenzen – läuft in EINEM eigenen Netz-Thread (threaded = true). Steht die
# Hauptschleife (Android onStop: App-Wechsel, Bildschirm aus, Vollbild-Einstellungen), liefert der Server weiter Seiten und die APK aus,
# beantwortet WebSocket-Pings und das Lebenszeichen „ping“ der Clients (auto_reply) und puffert deren Nachrichten; die Spiellogik
# arbeitet sie ab, sobald die Hauptschleife wieder läuft. Mit dem Hauptthread spricht der Thread nur über zwei Warteschlangen
# (Befehle hin, Ereignisse zurück) und zwei kleine Dictionaries (/info, APK-Quelle), alle unter _mutex. Signale entstehen nur in
# poll() auf dem Hauptthread. threaded = false erledigt dieselbe Arbeit in poll() (Tests, Plattformen ohne Threads).
#
# Nutzung: var s := NetServer.new(); add_child(s); s.start(); s.ws_message.connect(…); s.send_text(conn, text)

signal ws_opened(conn: int, info: Dictionary)          # info: address, port, host (Host-Kopf), origin, agent, path, query
signal ws_message(conn: int, text: String)
signal ws_closed(conn: int, code: int, reason: String)
signal ws_dropped(conn: int, why: String, size: int)   # Nachricht verworfen: "size" (> max_client_message) oder "rate"
signal log_line(text: String)
signal page_visited(address: String)                   # GET „/“ bzw. „/index.html“ (Spielseite) von dieser Adresse (Lobby, Beta 1.0.2)

const CHUNK := 65536
const MAX_APK_STREAMS := 6
const MAX_OUT_QUEUE := 4 * 1024 * 1024   # Byte, die ein WebSocket-Client nicht abholt → trennen
const APK_WAIT_MS := 8000                # so lange auf die APK-Quelle warten (Hauptthread), dann 503
const LINGER_MS := 2000                  # nach "Connection: close" auf das Schließen des Clients warten (kein RST vor dem Ende)
const LINGER_APK_MS := 10000
const LINGER_QUIET_MS := 150            # so lange nach der letzten Antwort nichts mehr kommt, wird geschlossen
const MAX_KEEPALIVE_REQUESTS := 200
const COMPRESSIBLE := ["html", "css", "js", "mjs", "json", "svg", "txt", "webmanifest", "map"]
const MIME := {
	"html": "text/html; charset=utf-8", "htm": "text/html; charset=utf-8", "css": "text/css; charset=utf-8",
	"js": "text/javascript; charset=utf-8", "mjs": "text/javascript; charset=utf-8", "json": "application/json; charset=utf-8",
	"webmanifest": "application/manifest+json", "txt": "text/plain; charset=utf-8", "map": "application/json; charset=utf-8",
	"svg": "image/svg+xml", "webp": "image/webp", "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
	"gif": "image/gif", "ico": "image/x-icon", "ttf": "font/ttf", "otf": "font/otf", "woff": "font/woff", "woff2": "font/woff2",
	"ogg": "audio/ogg", "m4a": "audio/mp4", "mp3": "audio/mpeg", "wav": "audio/wav", "mp4": "video/mp4", "webm": "video/webm",
	"wasm": "application/wasm", "pck": "application/octet-stream", "apk": "application/vnd.android.package-archive",
}
const STATUS_TEXT := {200: "OK", 101: "Switching Protocols", 204: "No Content", 206: "Partial Content", 304: "Not Modified",
	400: "Bad Request", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 408: "Request Timeout",
	413: "Content Too Large", 416: "Range Not Satisfiable", 426: "Upgrade Required", 431: "Request Header Fields Too Large",
	500: "Internal Server Error", 503: "Service Unavailable", 505: "HTTP Version Not Supported"}
const WEEKDAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

# --- Einstellungen (vor start setzen) ---
var threaded := true
var auto_poll := true                    # _process ruft poll(); false: der Besitzer ruft poll() selbst
var web_zip_path := "res://assets/web.zip"
var ws_path := NetProtocol.WS_PATH
var apk_provider := Callable()           # () -> {path, size, name}; {} = wird vorbereitet (503 nach 8 s), sonst ohne gültigen path = keine APK (404). Nur Hauptthread
var auto_reply := Callable(NetProtocol, "auto_reply")   # (text) -> String; läuft im Netz-Thread, muss zustandslos sein
var max_header_bytes := 8192
var max_client_message := NetProtocol.MAX_CLIENT_MESSAGE
var max_frame_bytes := 65536             # harte Grenze je Nachricht (auch fragmentiert): darüber 1009 und Trennung
var max_rate := NetProtocol.MAX_RATE     # Nachrichten je Sekunde und Client (Ping zählt mit)
var max_connections := 128             # Browser öffnen je Gast bis zu 6 Verbindungen für die Seite
var max_ws := 32
var header_timeout_ms := 10000
var idle_timeout_ms := 15000             # HTTP keep-alive ohne Anfrage
var ws_ping_ms := 10000                  # so lange Stille → WebSocket-Ping
var ws_timeout_ms := 30000               # so lange Stille → trennen
var gzip := true
var check_origin := true

var port := 0
var running := false

var _mutex := Mutex.new()
var _thread: Thread
var _quit := false
var _cmds: Array = []                    # Hauptthread → Netz: ["send", ids, text] | ["close", id, code, reason]
var _events: Array = []                  # Netz → Hauptthread: ["open", id, info] | ["msg", id, text] | ["closed", id, code, reason] | ["drop", id, why, size] | ["log", text]
var _info := {}
var _apk := {}                           # {state: "" | "ready" | "wait" | "none", path, size, name}
var _apk_wanted := false
var _stats := {}

# nur im Netz-Thread (bzw. in poll(), wenn nicht threaded)
var _tcp: TCPServer
var _conns := {}
var _next_id := 1
var _zip: ZIPReader
var _zip_index := {}                     # Pfad ohne Präfix → Eintrag im Archiv
var _files := {}                         # Pfad → {data, etag, gz}
var _date_cache := ""
var _date_sec := -1
var _logged := {}

class Conn:
	extends RefCounted
	var id := 0
	var peer: StreamPeerTCP
	var address := ""
	var remote_port := 0
	var kind := "new"                    # new | http | ws | apk_wait | stream | linger
	var inbuf := PackedByteArray()
	var out: Array = []
	var out_off := 0
	var out_bytes := 0
	var created_ms := 0
	var last_rx_ms := 0
	var requests := 0
	var close_after := false
	var linger_ms := LINGER_MS
	var linger_until := 0
	var linger_cap := 0
	var failed := false                  # Protokollfehler: Close gesendet, Eingang wird nur noch verworfen
	var skip_body := 0
	var file: FileAccess
	var file_left := 0
	var apk_req := {}
	var apk_deadline := 0
	var apk_next_ask := 0
	var frag_op := 0
	var frag := PackedByteArray()
	var frag_size := 0
	var frag_over := false
	var tokens := 0.0
	var tokens_ms := 0
	var drops := 0
	var drops_ms := 0
	var ping_sent := false
	var close_sent := false
	var close_received := false
	var last_tx_ms := 0
	var close_code := 1006
	var close_reason := ""
	var close_at := 0                    # verzögertes Schließen (close_ws mit grace_ms): dann Close senden
	var close_pending := []
	var muted := false                   # nur Tests (Vermittler-Nachbau): stilles Abreißen – nichts mehr lesen oder senden, nicht trennen
	var info := {}

# ---------- Öffentliche Schnittstelle (Hauptthread) ----------

func start(first_port := NetProtocol.PORT, last_port := NetProtocol.PORT_LAST, bind_address := "*") -> Error:
	# Lauschen auf dem ersten freien Port im Bereich. Ergebnis in port.
	stop()
	_tcp = TCPServer.new()
	var err := ERR_CANT_CREATE
	for p in range(first_port, maxi(first_port, last_port) + 1):
		err = _tcp.listen(p, bind_address)
		if err == OK:
			port = p
			break
	if err != OK:
		_tcp = null
		port = 0
		log_line.emit("Server: kein freier Port %d–%d (%s)" % [first_port, last_port, error_string(err)])
		return err
	_open_zip()
	_mutex.lock()
	_quit = false
	_cmds.clear()
	_events.clear()
	_stats = {"connections": 0, "refused": 0, "http": 0, "http_404": 0, "tls_rejected": 0, "header_too_big": 0, "ws_opened": 0,
		"ws_active": 0, "ws_rejected": 0, "origin_rejected": 0, "msgs_in": 0, "msgs_out": 0, "auto_replies": 0, "rate_dropped": 0,
		"oversize": 0, "apk_started": 0, "apk_done": 0, "apk_aborted": 0, "apk_active": 0, "bytes_out": 0, "protocol_errors": 0, "gzip": 0}
	_mutex.unlock()
	running = true
	if threaded:
		_thread = Thread.new()
		_thread.start(_run)
	log_line.emit("Server lauscht auf Port %d (%s, Browser-Client %s)" % [port, "Netz-Thread" if threaded else "Hauptthread",
		"%d Dateien" % _zip_index.size() if _zip != null else "fehlt – eingebaute Hinweisseite"])
	return OK

func stop() -> void:
	if not running and _thread == null:
		return
	_mutex.lock()
	_quit = true
	_mutex.unlock()
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	else:
		_shutdown()
	running = false
	_mutex.lock()
	_cmds.clear()
	_events.clear()
	_mutex.unlock()

func poll() -> void:
	# Hauptthread: Netzarbeit (nur ohne Thread), APK-Quelle fragen, Ereignisse als Signale ausgeben.
	if not running:
		return
	if not threaded:
		_step()
	_service_apk()
	_mutex.lock()
	var events := _events
	_events = []
	_mutex.unlock()
	for e in events:
		match e[0]:
			"open":
				ws_opened.emit(e[1], e[2])
			"msg":
				ws_message.emit(e[1], e[2])
			"closed":
				ws_closed.emit(e[1], e[2], e[3])
			"drop":
				ws_dropped.emit(e[1], e[2], e[3])
			"log":
				log_line.emit(e[1])
			"page":
				page_visited.emit(e[1])

func send_text(conn: int, text: String) -> void:
	_command(["send", [conn], text])

func send_text_many(conns: Array, text: String) -> void:
	# Gleicher Text an mehrere Verbindungen, der Rahmen wird nur einmal gebaut.
	if not conns.is_empty():
		_command(["send", conns.duplicate(), text])

func close_ws(conn: int, code := NetWs.CLOSE_NORMAL, reason := "", grace_ms := 0) -> void:
	# Close-Rahmen senden, auf die Antwort warten (höchstens 2 s), dann trennen. ws_closed folgt.
	# grace_ms > 0: erst so lange warten, ob der Client selbst schließt (nach „reject“/„bye“). Godots WebSocketPeer verwirft Nachrichten,
	# die im selben poll() wie ein vollständiger Close-Handshake ankommen – ein sofortiger Close-Rahmen kostete sonst das „reject“.
	_command(["close", conn, code, reason, grace_ms])

# Nur Tests: Verbindung „hängt“ (kein Lesen, kein Senden, kein Trennen) – wie ein still abgerissener Mobilfunk-Socket.
func mute_ws(conn: int, on := true) -> void:
	_command(["mute", conn, on])

func set_info(info: Dictionary) -> void:
	# Inhalt von /info (port wird ergänzt).
	_mutex.lock()
	_info = info.duplicate(true)
	_mutex.unlock()

func set_apk(info: Dictionary) -> void:
	# APK-Quelle direkt setzen ({path, size, name}); {} = vergessen, beim nächsten Abruf apk_provider fragen.
	_mutex.lock()
	_apk = _clean_apk(info) if not info.is_empty() else {}
	_mutex.unlock()

func stats() -> Dictionary:
	_mutex.lock()
	var out := _stats.duplicate()
	_mutex.unlock()
	return out

func has_web_client() -> bool:
	return _zip != null

func _process(_delta: float) -> void:
	if auto_poll:
		poll()

func _exit_tree() -> void:
	# Umhängen mit dem Elternknoten (Lobby → Tisch) ist kein Ende: erst am Ende des Frames prüfen (Gerätetest 0.1.1, H1).
	_stop_if_detached.call_deferred()

func _stop_if_detached() -> void:
	if not is_inside_tree():
		stop()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		stop()

func _command(cmd: Array) -> void:
	_mutex.lock()
	_cmds.append(cmd)
	_mutex.unlock()

func _service_apk() -> void:
	_mutex.lock()
	var wanted := _apk_wanted
	_apk_wanted = false
	_mutex.unlock()
	if not wanted:
		return
	var result := {"state": "none"}
	if apk_provider.is_valid():
		var info = apk_provider.call()
		result = _clean_apk(info) if info is Dictionary and not info.is_empty() else {"state": "wait"}
	_mutex.lock()
	_apk = result
	_mutex.unlock()

static func _clean_apk(info: Dictionary) -> Dictionary:
	var path := str(info.get("path", ""))
	if path == "" or not FileAccess.file_exists(path):
		return {"state": "none"}
	var size := int(info.get("size", 0))
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"state": "none"}
	var length := f.get_length()
	f.close()
	if size <= 0:
		size = length
	if size != length:
		return {"state": "none"}
	var file_name := str(info.get("name", "MauMauFlip-%s.apk" % NetProtocol.game_version())).get_file()
	file_name = file_name.replace("\"", "").replace("\r", "").replace("\n", "")
	return {"state": "ready", "path": path, "size": size, "name": file_name if file_name != "" else "MauMauFlip.apk"}

func _count(key: String, delta := 1) -> void:
	_mutex.lock()
	_stats[key] = int(_stats.get(key, 0)) + delta
	_mutex.unlock()

func _event(e: Array) -> void:
	_mutex.lock()
	_events.append(e)
	_mutex.unlock()

func _log(text: String, once_key := "") -> void:
	# Netz-Thread: Protokollzeile über poll() ausgeben; once_key: nur einmal je Schlüssel.
	if once_key != "":
		if _logged.has(once_key):
			return
		_logged[once_key] = true
	_event(["log", text])

# ---------- Netz-Thread ----------

func _run() -> void:
	while true:
		_mutex.lock()
		var q := _quit
		_mutex.unlock()
		if q:
			break
		if not _step():
			OS.delay_msec(4 if not _conns.is_empty() else 10)   # Akku: kurz schlafen, wenn nichts zu tun ist (Übertragungen schlafen nicht)
	_shutdown()

func _shutdown() -> void:
	for c in _conns.values():
		if c.kind == "ws" and not c.close_sent:
			c.peer.put_partial_data(NetWs.close_frame(NetWs.CLOSE_GOING_AWAY, "Gastgeber beendet"))
		if c.file != null:
			c.file.close()
		c.peer.disconnect_from_host()
	_conns.clear()
	if _tcp != null:
		_tcp.stop()
		_tcp = null
	if _zip != null:
		_zip.close()
		_zip = null
	_files.clear()

func _step() -> bool:
	# Eine Runde Netzarbeit. true = es wurde etwas bewegt (dann gleich weiter, sonst kurz schlafen).
	if _tcp == null:
		return false
	var busy := false
	var now := Time.get_ticks_msec()
	while _tcp.is_connection_available():
		var peer := _tcp.take_connection()
		if peer == null:
			break
		busy = true
		if _conns.size() >= max_connections:
			_count("refused")
			peer.disconnect_from_host()
			continue
		peer.set_no_delay(true)
		var c := Conn.new()
		c.id = _next_id
		_next_id += 1
		c.peer = peer
		c.address = peer.get_connected_host()
		c.remote_port = peer.get_connected_port()
		c.created_ms = now
		c.last_rx_ms = now
		_conns[c.id] = c
		_count("connections")
	busy = _commands() or busy
	for c in _conns.values():
		busy = _service(c, now) or busy
	for id in _conns.keys():
		var c: Conn = _conns[id]
		if c.peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_remove(c)
	return busy

func _commands() -> bool:
	_mutex.lock()
	var cmds := _cmds
	_cmds = []
	_mutex.unlock()
	for cmd in cmds:
		if cmd[0] == "send":
			var frame := NetWs.text_frame(cmd[2])
			for id in cmd[1]:
				var c: Conn = _conns.get(id)
				if c != null and c.kind == "ws" and not c.close_sent:
					_queue(c, frame)
					_count("msgs_out")
		elif cmd[0] == "mute":
			var m: Conn = _conns.get(cmd[1])
			if m != null:
				m.muted = bool(cmd[2])
				m.out.clear()
				m.out_off = 0
				m.out_bytes = 0
		elif cmd[0] == "close":
			var c: Conn = _conns.get(cmd[1])
			if c != null and c.kind == "ws":
				if int(cmd[4]) > 0:
					c.close_at = Time.get_ticks_msec() + int(cmd[4])
					c.close_pending = [cmd[2], cmd[3]]
				else:
					_ws_close(c, cmd[2], cmd[3])
	return not cmds.is_empty()

func _remove(c: Conn) -> void:
	if c.file != null:
		c.file.close()
		c.file = null
		if c.file_left > 0:
			_count("apk_aborted")
		_count("apk_active", -1)
	if c.kind == "ws" or c.info.has("ws"):
		_count("ws_active", -1)
		_event(["closed", c.id, c.close_code, c.close_reason])
	c.peer.disconnect_from_host()
	_conns.erase(c.id)

func _service(c: Conn, now: int) -> bool:
	c.peer.poll()
	if c.peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false
	var busy := false
	var n := c.peer.get_available_bytes()
	if c.muted:
		if n > 0:
			c.peer.get_partial_data(mini(n, CHUNK))   # Eingang verwerfen (wie ein Funkloch: nichts kommt an)
		c.last_rx_ms = now                           # und nicht selbst trennen: die Gegenstelle muss es bemerken
		return n > 0
	if n > 0:
		var r := c.peer.get_partial_data(mini(n, CHUNK))
		if r[0] == OK and (r[1] as PackedByteArray).size() > 0:
			c.last_rx_ms = now
			busy = true
			if c.kind in ["linger", "stream", "apk_wait"] or c.close_after or c.close_received or c.failed:
				# nach der (letzten) Anfrage: weitere Bytes verwerfen; im Nachlauf so lange warten, bis nichts mehr kommt
				if c.kind == "linger":
					c.linger_until = mini(now + LINGER_QUIET_MS, c.linger_cap)
			else:
				c.inbuf.append_array(r[1])
				if c.kind != "ws" and c.inbuf.size() > max_header_bytes + max_client_message + 4096:
					c.peer.disconnect_from_host()    # liest keine Antworten, schickt aber immer mehr
					return busy
	match c.kind:
		"new", "http":
			busy = _http_input(c, now) or busy
		"ws":
			busy = _ws_input(c, now) or busy
		"apk_wait":
			_apk_wait(c, now)
	if c.kind == "stream" and c.out_bytes < CHUNK and c.file != null and c.file_left > 0:
		var piece := c.file.get_buffer(mini(CHUNK, c.file_left))
		if piece.is_empty():
			_log("APK-Datei nicht weiter lesbar – Sendung an %s abgebrochen" % c.address)
			c.peer.disconnect_from_host()
			return busy
		c.file_left -= piece.size()
		_queue(c, piece)
		if c.file_left <= 0:
			c.file.close()
			c.file = null
			_count("apk_done")
			_count("apk_active", -1)
			_log("APK an %s vollständig gesendet" % c.address)
			c.close_after = true
			c.linger_ms = LINGER_APK_MS
	busy = _flush(c) or busy
	if c.out_bytes == 0 and c.close_after and c.kind != "linger":
		c.kind = "linger"
		c.linger_cap = now + c.linger_ms
		c.linger_until = now + LINGER_QUIET_MS
		c.close_after = false
	if c.kind == "ws" and c.close_sent and c.close_received and c.out_bytes == 0:
		c.peer.disconnect_from_host()    # Schließen in beiden Richtungen bestätigt: der Server trennt TCP (RFC 6455 7.1.1)
		return true
	_timeouts(c, now)
	return busy

func _timeouts(c: Conn, now: int) -> void:
	if c.out_bytes > 0 and now - maxi(c.last_tx_ms, c.created_ms) > 30000:
		c.peer.disconnect_from_host()        # Gegenseite nimmt seit 30 s nichts mehr an
		return
	match c.kind:
		"new", "http":
			var limit := header_timeout_ms if c.inbuf.size() > 0 or c.requests == 0 else idle_timeout_ms
			if now - c.last_rx_ms > limit and c.out_bytes == 0:
				c.peer.disconnect_from_host()
		"linger":
			if now > c.linger_until:
				c.peer.disconnect_from_host()
		"ws":
			if c.close_at > 0 and now >= c.close_at and not c.close_sent:
				_ws_close(c, int(c.close_pending[0]), str(c.close_pending[1]))
			var quiet := now - c.last_rx_ms
			if c.close_sent:
				if now > c.linger_until:
					c.peer.disconnect_from_host()
			elif quiet > ws_timeout_ms:
				c.close_code = NetWs.CLOSE_TIMEOUT
				c.close_reason = "keine Antwort"
				_log("WebSocket %d (%s) seit %d s stumm – getrennt" % [c.id, c.address, quiet / 1000])
				c.peer.disconnect_from_host()
			elif quiet > ws_ping_ms and not c.ping_sent:
				c.ping_sent = true
				_queue(c, NetWs.encode_frame(NetWs.OP_PING, "mmf".to_ascii_buffer()))

func _queue(c: Conn, bytes: PackedByteArray) -> void:
	if bytes.is_empty() or c.muted:
		return
	c.out.append(bytes)
	c.out_bytes += bytes.size()
	if c.kind == "ws" and c.out_bytes > MAX_OUT_QUEUE:
		_log("WebSocket %d (%s) holt keine Daten ab – getrennt" % [c.id, c.address])
		c.close_code = NetWs.CLOSE_POLICY
		c.close_reason = "Rückstau"
		c.out.clear()
		c.out_bytes = 0
		c.peer.disconnect_from_host()

func _flush(c: Conn) -> bool:
	var moved := false
	while not c.out.is_empty():
		var head: PackedByteArray = c.out[0]
		var piece := head if c.out_off == 0 else head.slice(c.out_off)
		var r := c.peer.put_partial_data(piece)
		if r[0] != OK:
			c.out.clear()
			c.out_bytes = 0
			c.peer.disconnect_from_host()
			return moved
		var sent := int(r[1])
		if sent <= 0:
			break
		moved = true
		c.last_tx_ms = Time.get_ticks_msec()
		_count("bytes_out", sent)
		c.out_bytes -= sent
		if sent >= piece.size():
			c.out.pop_front()
			c.out_off = 0
		else:
			c.out_off += sent
			break
	return moved

# ---------- HTTP ----------

func _http_input(c: Conn, now: int) -> bool:
	if c.inbuf.is_empty() or c.close_after or c.kind == "linger":
		return false
	if c.kind == "new":
		if c.inbuf[0] == 0x16:
			# TLS-ClientHello auf dem http-Port: sofort schließen, Safari & Co. fallen dann gleich auf http zurück.
			_count("tls_rejected")
			_log("TLS-Versuch von %s abgewiesen (Browser versucht https) – weiter mit http" % c.address, "tls " + c.address)
			c.inbuf.clear()
			c.peer.disconnect_from_host()
			return true
		c.kind = "http"
	if c.skip_body > 0:
		var k := mini(c.skip_body, c.inbuf.size())
		c.inbuf = c.inbuf.slice(k)
		c.skip_body -= k
		if c.skip_body > 0:
			return true
	if c.out_bytes > 0:
		return false    # erst die vorige Antwort hinausschicken (Pipelining der Reihe nach)
	var cut := _blank_line(c.inbuf, max_header_bytes)
	if cut < 0:
		if c.inbuf.size() > max_header_bytes:
			_count("header_too_big")
			_respond(c, 431, "text/plain; charset=utf-8", "Anfrage-Kopf zu groß.".to_utf8_buffer(), {}, false)
			return true
		return false
	var head := c.inbuf.slice(0, cut).get_string_from_ascii()
	c.inbuf = c.inbuf.slice(cut + 4)
	c.requests += 1
	c.created_ms = now
	_handle_request(c, parse_head(head))
	return true

static func _blank_line(buf: PackedByteArray, limit: int) -> int:
	var n := mini(buf.size(), limit + 4)
	for i in range(n - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	return -1

static func parse_head(head: String) -> Dictionary:
	# Anfragezeile und Kopfzeilen → {ok, method, target, path, query, version, headers (klein geschrieben)}; ok=false bei Unsinn.
	var lines := head.split("\r\n")
	var first := lines[0].split(" ")
	if first.size() != 3 or not first[2].begins_with("HTTP/1."):
		return {"ok": false}
	var headers := {}
	for i in range(1, lines.size()):
		var line := lines[i]
		var colon := line.find(":")
		if colon <= 0:
			if line.strip_edges() == "":
				continue
			return {"ok": false}
		var key := line.left(colon).strip_edges().to_lower()
		var value := line.substr(colon + 1).strip_edges()
		headers[key] = (str(headers[key]) + ", " + value) if headers.has(key) else value
	var target := first[1]
	var q := target.find("?")
	var raw_path := target.left(q) if q >= 0 else target
	var query := target.substr(q + 1) if q >= 0 else ""
	if raw_path.begins_with("http://"):
		var rest := raw_path.substr(7)
		var slash := rest.find("/")
		raw_path = rest.substr(slash) if slash >= 0 else "/"
	return {"ok": true, "method": first[0], "target": target, "path": raw_path.uri_decode(), "query": query,
		"version": first[2], "headers": headers}

func _handle_request(c: Conn, req: Dictionary) -> void:
	_count("http")
	if not req.ok:
		_respond(c, 400, "text/plain; charset=utf-8", "Anfrage nicht verstanden.".to_utf8_buffer(), {}, false)
		return
	var headers: Dictionary = req.headers
	var keep := str(req.version) == "HTTP/1.1" and not str(headers.get("connection", "")).to_lower().contains("close")
	if str(req.version) == "HTTP/1.0" and str(headers.get("connection", "")).to_lower().contains("keep-alive"):
		keep = true
	if c.requests >= MAX_KEEPALIVE_REQUESTS:
		keep = false
	var length := str(headers.get("content-length", "0")).strip_edges()
	var body := int(length) if length.is_valid_int() else -1
	if body < 0 or body > max_client_message:
		_respond(c, 413, "text/plain; charset=utf-8", "Anfrage zu groß.".to_utf8_buffer(), {}, false)
		return
	if headers.has("transfer-encoding"):
		_respond(c, 400, "text/plain; charset=utf-8", "Kein Inhalt erwartet.".to_utf8_buffer(), {}, false)
		return
	var method := str(req.method)
	if method != "GET" and method != "HEAD":
		_respond(c, 405, "text/plain; charset=utf-8", "Nur GET und HEAD.".to_utf8_buffer(), {"Allow": "GET, HEAD"}, false)
		return
	c.skip_body = body
	if c.skip_body > 0:
		var k := mini(c.skip_body, c.inbuf.size())
		c.inbuf = c.inbuf.slice(k)
		c.skip_body -= k
	var path := str(req.path)
	if path.contains("\\") or not path.begins_with("/"):
		_respond(c, 400, "text/plain; charset=utf-8", "Pfad ungültig.".to_utf8_buffer(), {}, keep, method == "HEAD")
		return
	if path == ws_path:
		_ws_handshake(c, req)
		return
	if path == "/info":
		_mutex.lock()
		var info := _info.duplicate(true)
		_mutex.unlock()
		info["port"] = port
		_respond(c, 200, MIME.json, JSON.stringify(info).to_utf8_buffer(), {"Cache-Control": "no-store",
			"Access-Control-Allow-Origin": "*"}, keep, method == "HEAD")
		return
	if path == "/apk" or path == "/apk/":
		c.apk_req = req
		c.kind = "apk_wait"
		c.apk_deadline = Time.get_ticks_msec() + APK_WAIT_MS
		c.apk_next_ask = 0
		_apk_wait(c, Time.get_ticks_msec())
		return
	if method == "GET" and (path == "/" or path == "/index.html"):
		_event(["page", c.address])
	_serve_file(c, req, keep)

func _respond(c: Conn, status: int, type: String, body: PackedByteArray, extra: Dictionary, keep: bool, head_only := false) -> void:
	if status == 404:
		_count("http_404")
	var text := "HTTP/1.1 %d %s\r\n" % [status, STATUS_TEXT.get(status, "Status")]
	text += "Date: %s\r\nServer: MauMauFlip/%s\r\n" % [_date(), NetProtocol.game_version()]
	if type != "":
		text += "Content-Type: %s\r\nX-Content-Type-Options: nosniff\r\n" % type
	if status != 304 and status != 101:
		text += "Content-Length: %d\r\n" % (int(extra.get("_length", body.size())))
	for key in extra:
		if not str(key).begins_with("_"):
			text += "%s: %s\r\n" % [key, extra[key]]
	text += "Connection: %s\r\n\r\n" % ("keep-alive" if keep else "close")
	_queue(c, text.to_utf8_buffer())
	if not head_only and status != 304 and not body.is_empty():
		_queue(c, body)
	if not keep:
		c.close_after = true
	else:
		c.kind = "http"

func _date() -> String:
	# Date-Kopf (RFC 9110, IMF-fixdate), je Sekunde einmal gebaut.
	var sec := int(Time.get_unix_time_from_system())
	if sec != _date_sec:
		_date_sec = sec
		var d := Time.get_datetime_dict_from_unix_time(sec)
		_date_cache = "%s, %02d %s %d %02d:%02d:%02d GMT" % [WEEKDAYS[int(d.weekday)], d.day, MONTHS[int(d.month) - 1], d.year, d.hour, d.minute, d.second]
	return _date_cache

# ---------- Dateien aus web.zip ----------

func _open_zip() -> void:
	_zip_index.clear()
	_files.clear()
	if _zip != null:
		_zip.close()
	_zip = null
	if web_zip_path == "" or not FileAccess.file_exists(web_zip_path):
		return
	var z := ZIPReader.new()
	if z.open(web_zip_path) != OK:
		log_line.emit("Server: %s nicht lesbar" % web_zip_path)
		return
	var names := z.get_files()
	# Liegen alle Dateien unter einem gemeinsamen Ordner mit index.html (z. B. webclient/), wird er abgeschnitten.
	var prefix := ""
	if not names.has("index.html"):
		for n in names:
			if n.ends_with("/index.html") and n.count("/") == 1:
				prefix = n.left(n.length() - "index.html".length())
				break
	for n in names:
		if n.ends_with("/") or not n.begins_with(prefix):
			continue
		_zip_index[n.substr(prefix.length())] = n
	_zip = z

static func mime_type(path: String) -> String:
	return MIME.get(path.get_extension().to_lower(), "application/octet-stream")

static func versioned(path: String, query: String) -> bool:
	# Versionierte Dateien dürfen ein Jahr im Cache bleiben: Abfrage mit v=… oder Name mit Prüfsumme/Version (app.3f9a1c2e.js, app.0.1.1.js).
	if query.begins_with("v=") or query.contains("&v="):
		return true
	var file := path.get_file()
	var re := RegEx.create_from_string("[.-]([0-9a-f]{8,}|\\d+\\.\\d+\\.\\d+)\\.[a-z0-9]+$")
	return re.search(file) != null

func _serve_file(c: Conn, req: Dictionary, keep: bool) -> void:
	var path := str(req.path)
	var head_only := str(req.method) == "HEAD"
	if path.ends_with("/"):
		path += "index.html"
	var key := path.substr(1)
	if key.split("/").has("..") or key.split("/").has("."):
		_respond(c, 404, MIME.html, _page("Nicht gefunden", "Diese Datei gibt es hier nicht."), {}, keep, head_only)
		return
	if _zip == null:
		if key == "index.html":
			_respond(c, 200, MIME.html, _fallback_page(), {"Cache-Control": "no-cache"}, keep, head_only)
		else:
			_respond(c, 404, MIME.html, _page("Nicht gefunden", "Diese Datei gibt es hier nicht."), {}, keep, head_only)
		return
	if not _zip_index.has(key):
		_respond(c, 404, MIME.html, _page("Nicht gefunden", "Diese Datei gibt es hier nicht."), {}, keep, head_only)
		return
	var entry: Dictionary = _files.get(key, {})
	if entry.is_empty():
		var data := _zip.read_file(_zip_index[key])
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_MD5)
		ctx.update(data)
		entry = {"data": data, "etag": ctx.finish().hex_encode().left(16), "gz": PackedByteArray()}
		var ext := key.get_extension().to_lower()
		if gzip and COMPRESSIBLE.has(ext) and data.size() > 512:
			var gz := data.compress(FileAccess.COMPRESSION_GZIP)
			if gz.size() < data.size() * 0.9:
				entry.gz = gz
		_files[key] = entry
	var headers: Dictionary = req.headers
	var use_gz: bool = not (entry.gz as PackedByteArray).is_empty() and str(headers.get("accept-encoding", "")).to_lower().contains("gzip")
	var etag := "\"%s%s\"" % [entry.etag, "-gz" if use_gz else ""]
	var extra := {"ETag": etag, "Cache-Control": "public, max-age=31536000, immutable" if versioned(path, str(req.query)) else "no-cache"}
	if not (entry.gz as PackedByteArray).is_empty():
		extra["Vary"] = "Accept-Encoding"
	var inm := str(headers.get("if-none-match", ""))
	if inm != "" and (inm.contains("\"%s\"" % entry.etag) or inm.contains("\"%s-gz\"" % entry.etag) or inm.strip_edges() == "*"):
		_respond(c, 304, "", PackedByteArray(), extra, keep, true)
		return
	if use_gz:
		extra["Content-Encoding"] = "gzip"
		_count("gzip")
	_respond(c, 200, mime_type(key), entry.gz if use_gz else entry.data, extra, keep, head_only)

static func _page(title: String, text: String) -> PackedByteArray:
	var html := "<!doctype html><html lang=\"de\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
	html += "<title>%s</title></head><body style=\"font-family:sans-serif;background:#0a0d20;color:#f4eada;padding:24px\">" % title
	html += "<h1>%s</h1><p>%s</p></body></html>" % [title, text]
	return html.to_utf8_buffer()

func _fallback_page() -> PackedByteArray:
	# Eingebaute Hinweisseite, solange web.zip fehlt (z. B. Bau ohne Browser-Client).
	return ("<!doctype html><html lang=\"de\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">" +
		"<title>Mau-Mau Flip</title></head><body style=\"font-family:sans-serif;background:#0a0d20;color:#f4eada;padding:24px;line-height:1.5\">" +
		"<h1>Mau-Mau Flip</h1><p>Der Gastgeber ist erreichbar, aber in dieser Version fehlt das Mitspielen im Browser.</p>" +
		"<p><a style=\"color:#ffdd33\" href=\"/apk\">App installieren (APK für Android)</a></p>" +
		"<p style=\"opacity:.7\">Version %s</p></body></html>" % NetProtocol.game_version()).to_utf8_buffer()

# ---------- APK ----------

func _apk_wait(c: Conn, now: int) -> void:
	_mutex.lock()
	var apk := _apk.duplicate()
	var active := int(_stats.get("apk_active", 0))
	if apk.get("state", "") != "ready" and now >= c.apk_next_ask:
		_apk_wanted = true
		c.apk_next_ask = now + 1000
	elif apk.get("state", "") == "ready":
		_apk_wanted = true      # Quelle beim nächsten poll() auffrischen (die zwischengespeicherte gilt schon jetzt)
	_mutex.unlock()
	var req := c.apk_req
	var head_only := str(req.method) == "HEAD"
	var state := str(apk.get("state", ""))
	if state == "none":
		c.kind = "http"
		_respond(c, 404, MIME.html, _page("Keine App", "Dieses Gerät bietet keine App zum Herunterladen an."), {}, false, head_only)
		return
	if state != "ready":
		if now > c.apk_deadline:
			c.kind = "http"
			_respond(c, 503, MIME.html, _page("Gleich", "Die App wird noch vorbereitet. Bitte gleich noch einmal versuchen."),
				{"Retry-After": "5"}, false, head_only)
		return
	if active >= MAX_APK_STREAMS and not head_only:
		c.kind = "http"
		_respond(c, 503, MIME.html, _page("Gleich", "Gerade laden schon %d Geräte die App. Bitte gleich noch einmal versuchen." % active),
			{"Retry-After": "10"}, false)
		return
	var size := int(apk.size)
	var first := 0
	var last := size - 1
	var status := 200
	var extra := {"Content-Disposition": "attachment; filename=\"%s\"" % apk.name, "Accept-Ranges": "bytes", "Cache-Control": "no-store"}
	var range := str((req.headers as Dictionary).get("range", "")).strip_edges().to_lower()
	if range.begins_with("bytes=") and not range.contains(","):
		var spec := range.substr(6)
		var dash := spec.find("-")
		var a := spec.left(dash).strip_edges() if dash >= 0 else ""
		var b := spec.substr(dash + 1).strip_edges() if dash >= 0 else ""
		var ok := dash >= 0
		if ok and a == "" and b.is_valid_int():
			first = maxi(0, size - int(b))
		elif ok and a.is_valid_int() and (b == "" or b.is_valid_int()):
			first = int(a)
			if b != "":
				last = mini(int(b), size - 1)
		else:
			ok = false
		if ok:
			if first >= size or first > last:
				c.kind = "http"
				_respond(c, 416, "", PackedByteArray(), {"Content-Range": "bytes */%d" % size}, false, true)
				return
			status = 206
			extra["Content-Range"] = "bytes %d-%d/%d" % [first, last, size]
	var length := last - first + 1
	extra["_length"] = length
	c.kind = "http"
	if head_only:
		_respond(c, status, MIME.apk, PackedByteArray(), extra, false, true)
		return
	var f := FileAccess.open(str(apk.path), FileAccess.READ)
	if f == null:
		_respond(c, 500, MIME.html, _page("Fehler", "Die App-Datei ist nicht lesbar."), {}, false)
		return
	f.seek(first)
	_respond(c, status, MIME.apk, PackedByteArray(), extra, false, true)
	c.close_after = false
	c.kind = "stream"
	c.file = f
	c.file_left = length
	_count("apk_started")
	_count("apk_active")
	_log("APK an %s: %s, %d Byte%s" % [c.address, apk.name, length, " ab Byte %d" % first if first > 0 else ""])

# ---------- WebSocket ----------

func _ws_handshake(c: Conn, req: Dictionary) -> void:
	var h: Dictionary = req.headers
	var head_only := str(req.method) == "HEAD"
	var upgrade := str(h.get("upgrade", "")).to_lower()
	var connection := str(h.get("connection", "")).to_lower()
	if str(req.method) != "GET" or not upgrade.contains("websocket") or not connection.contains("upgrade"):
		_count("ws_rejected")
		_respond(c, 426, "text/plain; charset=utf-8", "Hier nur WebSocket.".to_utf8_buffer(), {"Upgrade": "websocket"}, false, head_only)
		return
	if str(h.get("sec-websocket-version", "")).strip_edges() != "13":
		_count("ws_rejected")
		_respond(c, 426, "text/plain; charset=utf-8", "WebSocket-Version 13 nötig.".to_utf8_buffer(), {"Sec-WebSocket-Version": "13"}, false)
		return
	var key := str(h.get("sec-websocket-key", ""))
	if not NetWs.valid_key(key) or not h.has("host"):
		_count("ws_rejected")
		_respond(c, 400, "text/plain; charset=utf-8", "WebSocket-Anfrage unvollständig.".to_utf8_buffer(), {}, false)
		return
	var origin := str(h.get("origin", ""))
	if check_origin and not origin_allowed(origin, str(h.host)):
		_count("origin_rejected")
		_count("ws_rejected")
		_log("WebSocket von %s abgelehnt: fremde Herkunft %s" % [c.address, origin.left(80)], "origin " + origin.left(80))
		_respond(c, 403, "text/plain; charset=utf-8", "Fremde Herkunft.".to_utf8_buffer(), {}, false)
		return
	var ws_count := 0
	for other in _conns.values():
		if other.kind == "ws":
			ws_count += 1
	if ws_count >= max_ws:
		_count("ws_rejected")
		_respond(c, 503, "text/plain; charset=utf-8", "Zu viele Verbindungen.".to_utf8_buffer(), {"Retry-After": "5"}, false)
		return
	var text := "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n" % NetWs.accept_key(key)
	_queue(c, text.to_ascii_buffer())
	c.kind = "ws"
	c.tokens = float(max_rate)
	c.tokens_ms = Time.get_ticks_msec()
	c.last_rx_ms = c.tokens_ms
	c.info = {"ws": true, "address": c.address, "port": c.remote_port, "host": str(h.host).left(80), "origin": origin.left(120),
		"agent": str(h.get("user-agent", "")).left(160), "path": str(req.path), "query": str(req.query).left(200)}
	_count("ws_opened")
	_count("ws_active")
	_event(["open", c.id, c.info.duplicate()])

static func origin_allowed(origin: String, host: String) -> bool:
	# Erlaubt: keine Herkunft (App-Client) oder dieselbe Adresse samt Port wie im Host-Kopf (Seite vom Gastgeber selbst).
	if origin == "":
		return true
	var o := origin.strip_edges().to_lower()
	var default_port := "80"
	if o.begins_with("http://"):
		o = o.substr(7)
	elif o.begins_with("https://"):
		o = o.substr(8)
		default_port = "443"
	else:
		return false
	if o.ends_with("/"):
		o = o.left(o.length() - 1)
	var hh := host.strip_edges().to_lower()
	if not o.contains(":"):
		o += ":" + default_port
	if not hh.contains(":"):
		hh += ":80"
	return o == hh

func _ws_input(c: Conn, now: int) -> bool:
	var busy := false
	var offset := 0
	while not c.close_received and not c.failed:
		if c.peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var f := NetWs.parse_frame(c.inbuf, offset, max_frame_bytes)
		if f.status == "need":
			break
		busy = true
		if f.status == "error":
			_ws_fail(c, int(f.code), str(f.reason))
			offset = c.inbuf.size()
			break
		offset += int(f.size)
		if not f.masked:
			_ws_fail(c, NetWs.CLOSE_PROTOCOL, "unmaskierter Rahmen")
			break
		c.ping_sent = false
		var op := int(f.opcode)
		var payload: PackedByteArray = f.payload
		if op == NetWs.OP_PING:
			if not c.close_sent:
				_queue(c, NetWs.encode_frame(NetWs.OP_PONG, payload))
			continue
		if op == NetWs.OP_PONG:
			continue
		if op == NetWs.OP_CLOSE:
			_ws_close_received(c, payload)
			break
		if c.close_sent:
			continue    # nach dem eigenen Close nur noch auf die Antwort warten
		if op == NetWs.OP_BINARY or (op == NetWs.OP_CONT and c.frag_op == NetWs.OP_BINARY):
			_ws_fail(c, NetWs.CLOSE_UNSUPPORTED, "nur Text")
			break
		if op == NetWs.OP_TEXT:
			if c.frag_op != 0:
				_ws_fail(c, NetWs.CLOSE_PROTOCOL, "neue Nachricht mitten in einer fragmentierten")
				break
			c.frag_op = op
			c.frag = PackedByteArray()
			c.frag_size = 0
			c.frag_over = false
		elif op == NetWs.OP_CONT and c.frag_op == 0:
			_ws_fail(c, NetWs.CLOSE_PROTOCOL, "Fortsetzung ohne Anfang")
			break
		c.frag_size += payload.size()
		if c.frag_size > max_frame_bytes:
			_ws_fail(c, NetWs.CLOSE_TOO_BIG, "Nachricht zu groß")
			break
		if c.frag_size > max_client_message:
			c.frag_over = true
			c.frag = PackedByteArray()
		elif not c.frag_over:
			c.frag.append_array(payload)
		if not f.fin:
			continue
		var data := c.frag
		var size := c.frag_size
		var over := c.frag_over
		c.frag_op = 0
		c.frag = PackedByteArray()
		c.frag_size = 0
		c.frag_over = false
		if over:
			_count("oversize")
			_event(["drop", c.id, "size", size])
			continue
		if not NetWs.valid_utf8(data):
			_ws_fail(c, NetWs.CLOSE_INVALID_DATA, "kein gültiges UTF-8")
			break
		if not _rate_ok(c, now):
			continue
		var text := data.get_string_from_utf8()
		_count("msgs_in")
		if auto_reply.is_valid():
			var reply = auto_reply.call(text)
			if reply is String and reply != "":
				_queue(c, NetWs.text_frame(reply))
				_count("auto_replies")
				continue
		_event(["msg", c.id, text])
	if offset > 0:
		c.inbuf = c.inbuf.slice(offset) if offset < c.inbuf.size() else PackedByteArray()
	return busy

func _rate_ok(c: Conn, now: int) -> bool:
	# Eimer mit max_rate Marken, füllt sich mit max_rate je Sekunde. Wer dauerhaft flutet (dreifache Rate verworfen), fliegt.
	c.tokens = minf(float(max_rate), c.tokens + (now - c.tokens_ms) * max_rate / 1000.0)
	c.tokens_ms = now
	if c.tokens >= 1.0:
		c.tokens -= 1.0
		return true
	if now - c.drops_ms > 1000:
		c.drops_ms = now
		c.drops = 0
	c.drops += 1
	_count("rate_dropped")
	_event(["drop", c.id, "rate", 0])
	if c.drops > max_rate * 3:
		_log("WebSocket %d (%s) flutet – getrennt" % [c.id, c.address])
		_ws_close(c, NetWs.CLOSE_POLICY, "zu viele Nachrichten")
	return false

func _ws_fail(c: Conn, code: int, reason: String) -> void:
	# Protokollfehler: Close senden, Eingang nur noch verwerfen, nach kurzem Nachlauf trennen (RFC 6455 7.1.7).
	_count("protocol_errors")
	_log("WebSocket %d (%s): %s – Verbindung geschlossen (%d)" % [c.id, c.address, reason, code])
	c.inbuf.clear()
	_ws_close(c, code, reason)
	c.failed = true
	c.linger_until = Time.get_ticks_msec() + 500

func _ws_close(c: Conn, code: int, reason: String) -> void:
	if c.close_sent:
		return
	c.close_sent = true
	c.close_code = code
	c.close_reason = reason
	c.frag_op = 0
	c.frag = PackedByteArray()
	_queue(c, NetWs.close_frame(code, reason))
	c.linger_until = Time.get_ticks_msec() + LINGER_MS

func _ws_close_received(c: Conn, payload: PackedByteArray) -> void:
	var parsed := NetWs.parse_close(payload)
	var code := int(parsed[0])
	if payload.size() == 1 or (payload.size() >= 2 and not NetWs.valid_close_code(code)):
		_ws_fail(c, NetWs.CLOSE_PROTOCOL, "ungültiger Close-Code")
		c.close_received = true
		return
	c.close_received = true
	if not c.close_sent:
		# Antwort mit demselben Code (RFC 6455 5.5.1), danach trennt der Client.
		c.close_sent = true
		c.close_code = code
		c.close_reason = str(parsed[1])
		_queue(c, NetWs.encode_frame(NetWs.OP_CLOSE, payload.slice(0, 2) if payload.size() >= 2 else PackedByteArray()))
	c.linger_until = Time.get_ticks_msec() + LINGER_MS
	c.inbuf.clear()
