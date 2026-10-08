class_name NetRelayDouble
extends NetServer

# GDScript-Nachbau des Online-Vermittlers (docs/online/ENTWURF.md Abschnitt 1 und 6) auf Basis von NetServer – für Tests und den
# lokalen Gerätetest (game/tests/relay_double_main.gd), nie in der App eingeschaltet. Gleiches Protokoll wie relay/src/core.js:
#  - GET /info (ohne bzw. mit ?room=CODE), GET /ws?role=host|guest&… (Umschlag zum Gastgeber mit Feld k), Herzschlag „ping“ → „pong“.
#  - Statisch: der Browser-Client aus web.zip unter „/“ und unter „/c/<version>/“ (wie die Assets des Workers).
# Die Raumlogik steckt in Core (ohne Netz, Zeit als Parameter): Tests prüfen sie direkt mit relay/test/vectors.json und über echte
# Sockets. Inhalte (d) werden nie geparst und nie geloggt.
#
# Nutzung: var r := NetRelayDouble.new(); add_child(r); r.start(24700, 24700); … r.poll() (bzw. auto_poll)

const DEFAULT_PORT := 24700

var core: Core
var _clock_offset_ms := 0              # Tests: Zeit vorspulen (advance)

func _init() -> void:
	core = Core.new()
	core.versions = [NetProtocol.game_version()]
	threaded = false                     # die Raumlogik läuft in poll() auf dem Hauptthread (keine Sperren nötig)
	check_origin = false                 # Seiten des Vermittlers und App-Gäste ohne Herkunft
	max_client_message = Core.MAX_HOST_MSG
	max_frame_bytes = Core.MAX_HOST_MSG + 1024
	max_rate = Core.HOST_RATE
	max_ws = 64
	ws_ping_ms = 30000
	ws_timeout_ms = NetProtocol.RELAY_TIMEOUT_MS
	auto_reply = Callable(NetProtocol, "relay_auto_reply")
	ws_opened.connect(_on_open)
	ws_message.connect(_on_msg)
	ws_closed.connect(_on_closed)
	ws_dropped.connect(_on_dropped)

func now_ms() -> int:
	return Time.get_ticks_msec() + _clock_offset_ms

func advance(ms: int) -> void:
	# Tests: Uhr vorstellen (Abwesenheit, Lebensdauer) und fällige Alarme ausführen
	_clock_offset_ms += ms
	core.tick(now_ms())
	_flush_core()

func base_url() -> String:
	return "http://127.0.0.1:%d" % port

func poll() -> void:
	super.poll()
	if running:
		core.tick(now_ms())
		_flush_core()

func _on_open(conn: int, info: Dictionary) -> void:
	core.base_url = "http://%s" % str(info.get("host", "127.0.0.1:%d" % port))
	core.connect_socket(conn, Core.parse_query(str(info.get("query", ""))), str(info.get("agent", "")), now_ms())
	_flush_core()

func _on_msg(conn: int, text: String) -> void:
	core.message(conn, text, now_ms())
	_flush_core()

func _on_closed(conn: int, code: int, _reason: String) -> void:
	core.closed(conn, code, now_ms())
	_flush_core()

func _on_dropped(conn: int, why: String, size: int) -> void:
	core.dropped(conn, why, size)
	_flush_core()

func _flush_core() -> void:
	for a in core.take_actions():
		if a[0] == "send":
			send_text(int(a[1]), str(a[2]))
		elif a[0] == "close":
			close_ws(int(a[1]), int(a[2]), str(a[3]))

# /info des Vermittlers statt der Gastgeber-Info; /c/<version>/… liefert den Browser-Client aus web.zip.
# public_dir (optional, z. B. relay/public): statische Dateien wie die Assets des Workers (Lader „/“, 404.html, /c/<version>/ falls
# gebaut); fehlt /c/<version>/ dort, kommt der Browser-Client weiter aus web.zip.
var public_dir := ""

func _handle_request(c: Conn, req: Dictionary) -> void:
	if req.get("ok", false) and str(req.path) == "/info":
		var body := JSON.stringify(core.info(Core.parse_query(str(req.query)), now_ms())).to_utf8_buffer()
		_count("http")
		_respond(c, 200, MIME.json, body, {"Cache-Control": "no-store", "Access-Control-Allow-Origin": "*"}, true, str(req.method) == "HEAD")
		return
	if req.get("ok", false) and public_dir != "" and _serve_public(c, req):
		return
	if req.get("ok", false) and str(req.path).begins_with("/c/"):
		var rest := str(req.path).substr(3)
		var slash := rest.find("/")
		req = req.duplicate()
		req.path = rest.substr(slash) if slash >= 0 else "/"
	super._handle_request(c, req)

func _serve_public(c: Conn, req: Dictionary) -> bool:
	var path := str(req.path).uri_decode()
	var method := str(req.method)
	if path == ws_path or path.begins_with("/apk") or path.contains("..") or path.contains("\\") or not path.begins_with("/"):
		return false
	if method != "GET" and method != "HEAD":
		return false
	var rel := path.substr(1)
	if rel == "" or rel.ends_with("/"):
		rel += "index.html"
	var file := public_dir.path_join(rel)
	if FileAccess.file_exists(file):
		_count("http")
		_respond(c, 200, mime_type(file), FileAccess.get_file_as_bytes(file), {"Cache-Control": "no-cache"}, false, method == "HEAD")
		return true
	if path.begins_with("/c/"):
		return false      # Browser-Client aus web.zip
	var page := public_dir.path_join("404.html")
	_count("http")
	_respond(c, 404, MIME.html, FileAccess.get_file_as_bytes(page) if FileAccess.file_exists(page) else PackedByteArray(), {}, false, method == "HEAD")
	return true


# ---------- Raumlogik (ohne Netz) ----------

class Core:
	extends RefCounted
	# Zustand aller Räume. Sockets sind Zahlen des Aufrufers. Ergebnisse sammeln sich in take_actions():
	#   ["send", sock, text] · ["close", sock, code, reason]
	const MAX_GUESTS := 16
	const MAX_GUEST_MSG := 8192
	const MAX_HOST_MSG := 256 * 1024
	const GUEST_RATE := 20
	const GUEST_BURST := 40
	const HOST_RATE := 200
	const HOST_BURST := 400
	const SEND_MANY := 64
	const FLOOD_MS := 10000
	const AGENT_MAX := 120
	const WORDS := ["KATZE", "MOND", "SONNE", "PFOTE", "WOLKE", "BIRNE", "APFEL", "STERN", "TIGER", "PANDA", "OTTER", "IGEL",
		"FUCHS", "DACHS", "EULE", "FALKE", "MEISE", "KIWI", "MELONE", "BAUM", "BLATT", "WIESE", "BERG", "INSEL", "MEER",
		"WELLE", "NEBEL", "REGEN", "BLITZ", "KOMET", "LAMPE", "KERZE", "KISSEN", "BIENE", "HUMMEL", "ZEBRA", "LAMA", "KOALA"]

	var grace_ms := 10 * 60 * 1000         # Abwesenheit des Gastgebers, dann wird der Raum gelöscht
	var life_ms := 24 * 60 * 60 * 1000     # Lebensdauer eines Raums
	var versions: Array = []
	var base_url := ""                     # für link im room-Rahmen
	var fixed_token := ""                  # Tests/Vektoren: Token beim Anlegen
	var rng := RandomNumberGenerator.new()
	var rooms := {}                        # code -> Room-Dictionary
	var socks := {}                        # sock -> {room, role, c, tokens, tokens_ms, flood_ms}
	var _actions: Array = []

	func _init() -> void:
		rng.randomize()

	func take_actions() -> Array:
		var out := _actions
		_actions = []
		return out

	static func parse_query(q: String) -> Dictionary:
		var out := {}
		for pair in q.split("&", false):
			var eq := pair.find("=")
			if eq > 0:
				out[pair.left(eq)] = pair.substr(eq + 1).uri_decode()
			else:
				out[pair] = ""
		return out

	func new_code() -> String:
		for i in 8:
			var code := "%s-%d" % [WORDS[rng.randi_range(0, WORDS.size() - 1)], rng.randi_range(10, 99)]
			if not rooms.has(code):
				return code
		return ""

	func info(query: Dictionary, now: int) -> Dictionary:
		var out := {"game": NetProtocol.GAME_ID, "relay": 2, "proto": NetProtocol.RELAY_PROTO, "source": "local"}
		if query.has("room"):
			var code := NetProtocol.normalize_room_code(str(query.room))
			var r: Dictionary = rooms.get(code, {})
			out["room"] = {"open": false} if r.is_empty() else {"open": true, "host": int(r.host) >= 0, "version": str(r.version)}
		return out

	func connect_socket(sock: int, q: Dictionary, agent: String, now: int) -> int:
		# Neue Verbindung (wie Worker + RelayRoom.open). Ergebnis: 101 = angenommen (auch wenn gleich wieder geschlossen), sonst der
		# HTTP-Status, mit dem der Worker ablehnen würde (der Nachbau hat dann schon angenommen und schließt mit 4400).
		var role := str(q.get("role", ""))
		var status := 101
		if role == "host" and (not q.has("room") or _truthy(q.get("create"))):
			var code := str(q.get("room", "")) if q.has("room") else new_code()
			status = create(sock, code, q, now) if code != "" else 503
		elif role == "host":
			_host_return(sock, q, now)
		elif role == "guest":
			_guest(sock, q, agent, now)
		else:
			status = 400
		if status != 101 and sock >= 0:
			_close(sock, 4400, str(status))
		return status

	static func _truthy(v) -> bool:
		return v == true or str(v) == "1" or str(v) == "true"

	static func valid_version(v: String) -> bool:
		return RegEx.create_from_string("^[0-9A-Za-z.+-]{1,32}$").search(v) != null

	func create(sock: int, code: String, q: Dictionary, now: int) -> int:
		# Raum mit diesem Code anlegen: 409 belegt, 400 Version/Protokoll ungültig
		if rooms.has(code):
			return 409
		if not valid_version(str(q.get("v", ""))):
			return 400
		if int(str(q.get("proto", "1"))) != NetProtocol.RELAY_PROTO:
			return 400
		var token := fixed_token if fixed_token != "" else Crypto.new().generate_random_bytes(16).hex_encode()
		rooms[code] = {"code": code, "token_hash": token.sha256_text(), "version": str(q.get("v", "")), "created": now,
			"host": sock, "host_gone_at": -1, "guests": {}, "next_c": 1}
		socks[sock] = _sock_entry(code, "host", 0, now)
		_send(sock, _room_frame(rooms[code], token))
		return 101

	func _host_return(sock: int, q: Dictionary, now: int) -> void:
		var code := NetProtocol.normalize_room_code(str(q.get("room", "")))
		var r: Dictionary = rooms.get(code, {})
		if r.is_empty():
			_close(sock, NetProtocol.CLOSE_ROOM_UNKNOWN, "room")
			return
		if str(q.get("token", "")).sha256_text() != str(r.token_hash):
			_close(sock, NetProtocol.CLOSE_BAD_TOKEN, "token")
			return
		var old := int(r.host)
		if old >= 0:
			socks.erase(old)
			_close(old, NetWs.CLOSE_REPLACED, "replaced")
		r.host = sock
		r.host_gone_at = -1
		socks[sock] = _sock_entry(code, "host", 0, now)
		_send(sock, _room_frame(r, ""))

	func _room_frame(r: Dictionary, token: String) -> String:
		var frame := {"k": "room", "room": r.code, "link": "%s/?r=%s" % [base_url, r.code],
			"limits": {"guests": MAX_GUESTS, "msg": MAX_GUEST_MSG, "host_msg": MAX_HOST_MSG, "rate": GUEST_RATE, "grace_s": grace_ms / 1000,
				"life_s": life_ms / 1000, "ping_s": NetProtocol.RELAY_PING_MS / 1000, "idle_s": NetProtocol.RELAY_TIMEOUT_MS / 1000}}
		if token != "":
			frame["token"] = token
		return JSON.stringify(frame)

	func _guest(sock: int, q: Dictionary, agent: String, now: int) -> void:
		var code := NetProtocol.normalize_room_code(str(q.get("room", "")))
		var r: Dictionary = rooms.get(code, {})
		if r.is_empty():
			_close(sock, NetProtocol.CLOSE_ROOM_UNKNOWN, "room")
			return
		if int(r.host) < 0:
			_close(sock, NetProtocol.CLOSE_HOST_AWAY, "host away")
			return
		if (r.guests as Dictionary).size() >= MAX_GUESTS:
			_close(sock, NetProtocol.CLOSE_ROOM_FULL, "full")
			return
		var c := int(r.next_c)
		r.next_c = c + 1
		r.guests[c] = sock
		socks[sock] = _sock_entry(code, "guest", c, now)
		_send(int(r.host), JSON.stringify({"k": "open", "c": c, "info": {"agent": agent.left(AGENT_MAX)}}))

	static func _sock_entry(code: String, role: String, c: int, now: int) -> Dictionary:
		var burst := GUEST_BURST if role == "guest" else HOST_BURST
		return {"room": code, "role": role, "c": c, "tokens": float(burst), "tokens_ms": now, "bad_since": -1, "last_bad": -1}

	func message(sock: int, text: String, now: int) -> void:
		var s: Dictionary = socks.get(sock, {})
		if s.is_empty():
			return
		if text == "ping":
			_send(sock, "pong")    # nur ohne Sofortantwort des Servers (Cloudflare: setWebSocketAutoResponse)
			return
		var r: Dictionary = rooms.get(s.room, {})
		if r.is_empty():
			return
		if s.role == "guest":
			_guest_message(s, r, text, now)
		else:
			_host_message(sock, r, text, now)

	func _guest_message(s: Dictionary, r: Dictionary, text: String, now: int) -> void:
		if int(r.host) < 0:
			return
		var size := text.to_utf8_buffer().size()
		if size > MAX_GUEST_MSG:
			_send(int(r.host), JSON.stringify({"k": "drop", "c": s.c, "why": "size", "size": size}))
			return
		if not _take(s, GUEST_RATE, GUEST_BURST, now):
			if now - int(s.bad_since) >= FLOOD_MS:
				var c := int(s.c)
				_drop_guest(r, c, NetProtocol.CLOSE_RATE, "rate")
				_send(int(r.host), JSON.stringify({"k": "close", "c": c, "code": NetProtocol.CLOSE_RATE}))
				return
			_send(int(r.host), JSON.stringify({"k": "drop", "c": s.c, "why": "rate", "size": size}))
			return
		_send(int(r.host), JSON.stringify({"k": "msg", "c": s.c, "d": text}))

	static func _take(s: Dictionary, rate: int, burst: int, now: int) -> bool:
		# Token-Eimer wie Bucket in core.js; Verstoß-Serie reißt ab, wenn länger als 1 s nichts verworfen wurde
		s.tokens = minf(float(burst), float(s.tokens) + (now - int(s.tokens_ms)) * rate / 1000.0)
		s.tokens_ms = now
		if float(s.tokens) >= 1.0:
			s.tokens = float(s.tokens) - 1.0
			return true
		if int(s.bad_since) < 0 or now - int(s.last_bad) > 1000:
			s.bad_since = now
		s.last_bad = now
		return false

	static func _is_int(v) -> bool:
		return (v is int) or (v is float and is_finite(v) and v == floorf(v))

	func _host_message(sock: int, r: Dictionary, text: String, now: int) -> void:
		var s: Dictionary = socks[sock]
		if text.length() > MAX_HOST_MSG / 4 and text.to_utf8_buffer().size() > MAX_HOST_MSG:
			socks.erase(sock)
			_close(sock, NetWs.CLOSE_TOO_BIG, "too big")
			if int(r.host) == sock:
				_host_left(r, now)
			return
		if not _take(s, HOST_RATE, HOST_BURST, now):
			_send(sock, JSON.stringify({"k": "err", "code": "rate"}))
			return
		var json := JSON.new()
		if json.parse(text) != OK or not json.data is Dictionary:
			_send(sock, JSON.stringify({"k": "err", "code": "bad"}))
			return
		var m: Dictionary = json.data
		match str(m.get("k", "")):
			"send":
				var list: Array = m.c if m.get("c") is Array else [m.get("c")]
				var ok := m.get("d") is String and not list.is_empty() and list.size() <= SEND_MANY
				for c in list:
					ok = ok and _is_int(c)
				if not ok:
					_send(sock, JSON.stringify({"k": "err", "code": "bad"}))
					return
				for c in list:
					var g = r.guests.get(int(c))
					if g == null:
						_send(sock, JSON.stringify({"k": "err", "code": "unknown_c", "c": int(c)}))
					else:
						_send(int(g), str(m.d))
			"kick":
				if not _is_int(m.get("c")):
					_send(sock, JSON.stringify({"k": "err", "code": "bad"}))
					return
				var c := int(m.c)
				if not r.guests.has(c):
					_send(sock, JSON.stringify({"k": "err", "code": "unknown_c", "c": c}))
					return
				var code := int(m.get("code")) if _is_int(m.get("code")) else 1000
				if not (code == 1000 or code == 1001 or code == 1008 or (code >= 3000 and code <= 4999)):
					code = 1000
				_drop_guest(r, c, code, str(m.get("reason", "")).left(100))
				_send(sock, JSON.stringify({"k": "close", "c": c, "code": code}))
			"end":
				_end_room(r, NetProtocol.CLOSE_ROOM_ENDED, "ended")
			_:
				_send(sock, JSON.stringify({"k": "err", "code": "bad"}))

	func closed(sock: int, code: int, now: int) -> void:
		var s: Dictionary = socks.get(sock, {})
		socks.erase(sock)
		if s.is_empty():
			return
		var r: Dictionary = rooms.get(s.room, {})
		if r.is_empty():
			return
		if s.role == "guest":
			r.guests.erase(int(s.c))
			if int(r.host) >= 0:
				_send(int(r.host), JSON.stringify({"k": "close", "c": s.c, "code": code}))
		elif int(r.host) == sock:
			_host_left(r, now)

	func dropped(sock: int, why: String, size: int) -> void:
		# Übergroße Nachricht (NetServer-Grenze): Gast → drop an den Gastgeber; Gastgeber → 1009
		var s: Dictionary = socks.get(sock, {})
		if s.is_empty():
			return
		var r: Dictionary = rooms.get(s.room, {})
		if r.is_empty():
			return
		if s.role == "guest" and int(r.host) >= 0:
			_send(int(r.host), JSON.stringify({"k": "drop", "c": s.c, "why": why, "size": size}))
		elif s.role == "host" and why == "size":
			socks.erase(sock)
			_close(sock, NetWs.CLOSE_TOO_BIG, "too big")
			if int(r.host) == sock:
				_host_left(r, int(s.tokens_ms))

	func tick(now: int) -> void:
		for code in rooms.keys():
			var r: Dictionary = rooms[code]
			if now - int(r.created) >= life_ms:
				_end_room(r, NetProtocol.CLOSE_ROOM_ENDED, "expired")
			elif int(r.host_gone_at) >= 0 and now - int(r.host_gone_at) >= grace_ms:
				_end_room(r, NetProtocol.CLOSE_ROOM_ENDED, "expired")

	func _drop_guest(r: Dictionary, c: int, code: int, reason: String) -> void:
		var sock := int(r.guests.get(c, -1))
		r.guests.erase(c)
		if sock >= 0:
			socks.erase(sock)
			_close(sock, code, reason)

	func _end_room(r: Dictionary, code: int, reason: String) -> void:
		# alle Sockets des Raums in Anmelde-Reihenfolge schließen (wie core.js)
		for sock in socks.keys():
			if str(socks[sock].room) == str(r.code):
				socks.erase(sock)
				_close(int(sock), code, reason)
		r.guests.clear()
		r.host = -1
		rooms.erase(r.code)

	func _host_left(r: Dictionary, now: int) -> void:
		# Gastgeber weg: Gäste mit 4503 schließen, Raum grace_ms aufheben
		r.host = -1
		if int(r.host_gone_at) < 0:
			r.host_gone_at = now
		for c in (r.guests as Dictionary).keys():
			_drop_guest(r, int(c), NetProtocol.CLOSE_HOST_AWAY, "host away")

	func alarm_at(code: String) -> int:
		# Nächster fälliger Zeitpunkt des Raums (wie der Alarm in core.js); -1 = kein Raum
		var r: Dictionary = rooms.get(code, {})
		if r.is_empty():
			return -1
		var life_end := int(r.created) + life_ms
		return mini(int(r.host_gone_at) + grace_ms, life_end) if int(r.host_gone_at) >= 0 else life_end

	func _send(sock: int, text: String) -> void:
		_actions.append(["send", sock, text])

	func _close(sock: int, code: int, reason: String) -> void:
		_actions.append(["close", sock, code, reason])
