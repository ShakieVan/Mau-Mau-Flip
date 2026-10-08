class_name NetRelayHost
extends Node

# Gastgeber-Seite des Online-Spiels (docs/online/ENTWURF.md Abschnitt 1 und 3): eine WebSocket-Verbindung zum Vermittler
# (wss://<vermittler>/ws?role=host…), über die alle Online-Gäste laufen. Schnittstelle wie NetServer (Signale ws_opened, ws_message,
# ws_closed, ws_dropped, log_line; send_text, send_text_many, close_ws, stats, poll), damit NetHostSession beide Transporte gleich
# behandelt. Verbindungsnummern = NetProtocol.RELAY_CONN_BASE + c (c vom Vermittler), so laufen WLAN- und Online-Gäste nebeneinander.
# Umschlag: Vermittler → hier {k: room|open|msg|close|drop|err}, hier → Vermittler {k: send|kick|end}. Spieltexte d werden nur
# durchgereicht.
# Zustände (state_changed): off → connecting → open; Verbindung zum Vermittler weg → away (neu verbinden mit dem Raum-Token:
# 1, 2, 4 … 30 s); Raum unbekannt/abgelaufen oder Vermittler nicht erreichbar beim ersten Mal → failed.
# Beta 1.3.3 (Nutzerbefund 1.3.2: still abgerissene Verbindung, der Gast sah lange einen alten Stand):
#  - Herzschlag 10 s, 25 s Stille = weg; nach eigenem Senden ohne jede Antwort binnen 6 s sofort „ping“, 4 s später weg.
#  - check_now() (App wieder vorn, NetHostSession): „ping“, Antwort binnen 3 s, sonst sofort neu verbinden; wartender Neuversuch → jetzt.
#  - Während „away“ gelten die Online-Gäste NICHT als gegangen (kein ws_closed, also keine Vertretung durch den Computer). Nach der
#    Rückkehr bekommen ihre alten Verbindungen 4012 (CLOSE_RESYNC): Sie melden sich sofort mit Token neu an und erhalten den vollen
#    Stand. Nötig, weil der Vermittler beim Ersetzen eines still toten Gastgeber-Sockets die Gäste behält, der neue Gastgeber-Socket
#    sie aber nicht kennt. Wer binnen RELAY_RESYNC_GRACE_MS nicht wiederkommt, gilt erst dann als getrennt.

signal ws_opened(conn: int, info: Dictionary)
signal ws_message(conn: int, text: String)
signal ws_closed(conn: int, code: int, reason: String)
signal ws_dropped(conn: int, why: String, size: int)
signal log_line(text: String)
signal state_changed(state: String)

const RETRY_MS := [1000, 2000, 4000, 8000, 16000, 30000]
const CONNECT_TIMEOUT_MS := 10000

var auto_poll := true
var relay_url := ""
var game_version := NetProtocol.game_version()
var ping_ms := NetProtocol.RELAY_PING_MS
var timeout_ms := NetProtocol.RELAY_TIMEOUT_MS
var probe_after_ms := NetProtocol.RELAY_PROBE_AFTER_MS
var probe_wait_ms := NetProtocol.RELAY_PROBE_WAIT_MS
var resync_grace_ms := NetProtocol.RELAY_RESYNC_GRACE_MS
var retry_ms: Array = RETRY_MS.duplicate()
var connect_timeout_ms := CONNECT_TIMEOUT_MS
var state := "off"                       # off | connecting | open | away | failed
var room := ""
var token := ""
var link := ""
var limits := {}
var error := ""                          # letzter Fehlertext (deutsche msgid, für I18n.t)
var _ws: WebSocketPeer
var _was_open := false
var _opened_ms := 0
var _last_rx_ms := 0
var _next_ping_ms := 0
var _retry_at := -1
var _attempts := 0
var _guests := {}                        # conn -> true (verbunden)
var _held := {}                          # conn -> Frist (ms, -1 = Gastgeber noch weg): Online-Gäste während/nach „away“
var _probe_since := -1                   # erstes Senden ohne Antwort seither (ms), -1 = nichts offen
var _probe_deadline := -1                # Prüf-„ping“ gesendet: bis dahin muss etwas kommen
var resume_probe_ms := NetProtocol.RESUME_PROBE_MS
var _resume_deadline := -1               # nach check_now(): bis dahin muss etwas kommen, sonst sofort neu verbinden
var _kicks := {}                         # conn -> [Zeitpunkt, code, reason] (close_ws mit grace_ms)
var _stats := {"ws_active": 0, "ws_opened": 0, "msgs_in": 0, "msgs_out": 0, "rate_dropped": 0, "oversize": 0, "reconnects": 0}

# ---------- Öffentliche Schnittstelle ----------

func open(url: String) -> Error:
	# Neuen Raum beim Vermittler öffnen.
	close()
	relay_url = NetProtocol.normalize_relay_url(url)
	if relay_url == "":
		error = "Keine gültige Vermittler-Adresse."
		_set_state("failed")
		return ERR_INVALID_PARAMETER
	room = ""
	token = ""
	link = ""
	error = ""
	_attempts = 0
	_set_state("connecting")
	return _connect()

func close(end_room := true) -> void:
	# Online beenden: {k:"end"} (Gäste bekommen 1001, der Raum ist weg) und trennen.
	if _ws != null:
		if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			if end_room:
				_ws.send_text(JSON.stringify({"k": "end"}))
				_ws.poll()
			_ws.close(NetWs.CLOSE_NORMAL, "Gastgeber beendet")
			_ws.poll()
		_ws = null
	_unhold()
	_retry_at = -1
	_drop_all_guests(NetProtocol.CLOSE_ROOM_ENDED, "Raum beendet")
	_kicks.clear()
	if state != "off":
		_set_state("off")

func send_text(conn: int, text: String) -> void:
	send_text_many([conn], text)

func send_text_many(conns: Array, text: String) -> void:
	var cs := []
	for conn in conns:
		if _guests.has(conn):
			cs.append(int(conn) - NetProtocol.RELAY_CONN_BASE)
	if cs.is_empty() or not _is_open():
		return
	_ws.send_text(JSON.stringify({"k": "send", "c": cs, "d": text}))
	_stats.msgs_out += cs.size()
	if _probe_since < 0:
		_probe_since = Time.get_ticks_msec()     # Prüfung nach eigenem Senden (Beta 1.3.3)

func close_ws(conn: int, code := NetWs.CLOSE_NORMAL, reason := "", grace_ms := 0) -> void:
	# Gast schließen; grace_ms > 0: erst so lange warten, ob er selbst geht (nach „reject“/„bye“, wie NetServer.close_ws).
	if _held.has(conn):
		_held.erase(conn)     # alte Verbindung eines Gastes aus der Abwesenheit (z. B. durch seine neue ersetzt)
		ws_closed.emit(conn, code, reason)
		return
	if not _guests.has(conn):
		return
	if grace_ms > 0:
		_kicks[conn] = [Time.get_ticks_msec() + grace_ms, code, reason]
		return
	_kick(conn, code, reason)

func stats() -> Dictionary:
	var out := _stats.duplicate()
	out.ws_active = _guests.size() + _held.size()
	return out

func check_now() -> void:
	# App wieder vorn (Beta 1.3.3): Verbindung zum Vermittler sofort prüfen bzw. den wartenden Neuversuch vorziehen.
	var now := Time.get_ticks_msec()
	if _retry_at >= 0:
		_retry_at = now
		return
	if state != "open" or not _is_open():
		return
	if now - _last_rx_ms > timeout_ms:
		_lost("Vermittler antwortet nicht.", 0)
		return
	_ws.send_text("ping")
	_next_ping_ms = now + ping_ms
	_resume_deadline = now + resume_probe_ms
	_ws.poll()

func flush() -> void:
	# Gesendetes sofort hinausschieben (vor dem Anhalten der App).
	if _ws != null:
		_ws.poll()

func is_guest(conn: int) -> bool:
	return conn >= NetProtocol.RELAY_CONN_BASE

func info() -> Dictionary:
	return {"room": room, "link": link, "error": error, "relay": relay_url}

func _process(_delta: float) -> void:
	if auto_poll:
		poll()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_ws.send_text(JSON.stringify({"k": "end"}))
			_ws.close(NetWs.CLOSE_NORMAL, "Gastgeber beendet")
		_ws = null
		_unhold()

func poll() -> void:
	var now := Time.get_ticks_msec()
	if _retry_at >= 0 and now >= _retry_at:
		_retry_at = -1
		_connect()
	for conn in _held.keys():
		if int(_held[conn]) >= 0 and now >= int(_held[conn]):
			_held.erase(conn)
			ws_closed.emit(conn, NetProtocol.CLOSE_HOST_AWAY, "nicht zurückgekehrt")
	for conn in _kicks.keys():
		if now >= int(_kicks[conn][0]):
			var k: Array = _kicks[conn]
			_kicks.erase(conn)
			if _guests.has(conn):
				_kick(conn, int(k[1]), str(k[2]))
	if _ws == null:
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st != WebSocketPeer.STATE_CONNECTING:
		_unhold()
	else:
		NetAddresses.expire_holds()
	if st == WebSocketPeer.STATE_OPEN and not _was_open:
		_was_open = true
		_last_rx_ms = now
		_next_ping_ms = now + ping_ms
	while _ws != null and _ws.get_available_packet_count() > 0:
		var text := _ws.get_packet().get_string_from_utf8()
		_last_rx_ms = now
		_probe_since = -1
		_probe_deadline = -1
		_resume_deadline = -1
		if text == "pong":
			continue
		_handle(text)
	if _ws == null:
		return
	if st == WebSocketPeer.STATE_OPEN:
		if now >= _next_ping_ms:
			_next_ping_ms = now + ping_ms
			_ws.send_text("ping")
		if state == "open" and _probe_deadline < 0 and _probe_since >= 0 and now - _probe_since > probe_after_ms:
			_probe_deadline = now + probe_wait_ms     # eigenes Senden blieb ohne Antwort: sofort nachfragen
			_next_ping_ms = now + ping_ms
			_ws.send_text("ping")
		if now - _last_rx_ms > timeout_ms:
			_lost("Vermittler antwortet nicht.")
		elif _resume_deadline >= 0 and now > _resume_deadline:
			_lost("Vermittler antwortet nicht.", 0)
		elif _probe_deadline >= 0 and now > _probe_deadline:
			_lost("Vermittler antwortet nicht.")
		elif state == "connecting" and now - _opened_ms > connect_timeout_ms:
			_lost("Vermittler antwortet nicht.")
	elif st == WebSocketPeer.STATE_CONNECTING:
		if now - _opened_ms > connect_timeout_ms:
			_lost("Vermittler nicht erreichbar.")
	elif st == WebSocketPeer.STATE_CLOSED:
		var code := _ws.get_close_code()
		_ws = null
		if code == NetProtocol.CLOSE_ROOM_UNKNOWN or code == NetProtocol.CLOSE_BAD_TOKEN or code == NetProtocol.CLOSE_ROOM_ENDED:
			_fail("Der Online-Raum ist abgelaufen. Bitte neu öffnen.")
		elif code == NetWs.CLOSE_REPLACED:
			_fail("Der Online-Raum wird jetzt von einem anderen Gerät geführt.")
		else:
			_lost("Verbindung zum Vermittler getrennt.")

# ---------- intern ----------

func _connect() -> Error:
	var query := "role=host&proto=%d&v=%s" % [NetProtocol.RELAY_PROTO, game_version.uri_encode()]
	if room != "" and token != "":
		query = "role=host&room=%s&token=%s" % [room, token]
	var url := NetProtocol.relay_ws_url(relay_url, query)
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = NetProtocol.MAX_CLIENT_MESSAGE * 4 + 65536
	_ws.outbound_buffer_size = NetProtocol.RELAY_MAX_HOST_MESSAGE * 4
	_ws.max_queued_packets = 4096
	_was_open = false
	_opened_ms = Time.get_ticks_msec()
	_attempts += 1
	# Android: Bindung ans Spiel-WLAN/WLAN ohne Internet aussetzen, bis der Socket steht (offen, Fehler oder Frist).
	NetAddresses.hold_unbound(hold_id())
	var err := _ws.connect_to_url(url, TLSOptions.client() if url.begins_with("wss://") else null)
	if err != OK:
		_ws = null
		_lost("Vermittler nicht erreichbar.")
	return err

func _handle(text: String) -> void:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return
	var m: Dictionary = json.data
	var c := (NetProtocol.RELAY_CONN_BASE + int(m.c)) if (m.get("c") is float or m.get("c") is int) else -1
	match str(m.get("k", "")):
		"room":
			room = NetProtocol.normalize_room_code(str(m.get("room", "")))
			if m.get("token") is String and str(m.token) != "":
				token = str(m.token).left(128)
			limits = m.get("limits", {}) if m.get("limits") is Dictionary else {}
			link = NetProtocol.room_link(relay_url, room)
			error = ""
			_attempts = 0
			_resync_held()
			_log("Online-Raum %s offen" % room)
			_set_state("open")
		"open":
			if c < NetProtocol.RELAY_CONN_BASE:
				return
			_guests[c] = true
			_stats.ws_opened += 1
			var agent := str((m.get("info", {}) as Dictionary).get("agent", "")) if m.get("info") is Dictionary else ""
			ws_opened.emit(c, {"address": "online", "port": 0, "host": "", "origin": "", "agent": agent.left(120), "path": NetProtocol.WS_PATH,
				"query": "", "online": true})
		"msg":
			if _guests.has(c) and m.get("d") is String:
				_stats.msgs_in += 1
				ws_message.emit(c, str(m.d))
		"close":
			if _guests.has(c):
				_guests.erase(c)
				_kicks.erase(c)
				ws_closed.emit(c, int(m.get("code", 1005)) if (m.get("code") is float or m.get("code") is int) else 1005, "")
		"drop":
			if _guests.has(c):
				var why := str(m.get("why", "size"))
				_stats["rate_dropped" if why == "rate" else "oversize"] += 1
				ws_dropped.emit(c, why, int(m.get("size", 0)) if (m.get("size") is float or m.get("size") is int) else 0)
		"err":
			pass    # z. B. unknown_c: der Gast war schon weg (Rennen zwischen Senden und Trennen)

func _kick(conn: int, code: int, reason: String) -> void:
	_kicks.erase(conn)
	if _is_open():
		_ws.send_text(JSON.stringify({"k": "kick", "c": conn - NetProtocol.RELAY_CONN_BASE, "code": code, "reason": reason.left(100)}))
	# Der Vermittler bestätigt mit {k:"close"} nicht; der Gast ist ab jetzt weg.
	if _guests.has(conn):
		_guests.erase(conn)
		ws_closed.emit(conn, code, reason)

func hold_id() -> String:
	return "relay_host:%d" % get_instance_id()

func _unhold() -> void:
	NetAddresses.release_hold(hold_id())

func _is_open() -> bool:
	return _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN

func _resync_held() -> void:
	# Zurück beim Vermittler: alte Verbindungen der Gäste auffordern, sich sofort neu anzumelden (4012). Der Vermittler bestätigt mit
	# {k:"close"} bzw. kennt sie nicht mehr ({k:"err"}); beides ändert hier nichts. Ab jetzt läuft die Frist für ihre Rückkehr.
	var until := Time.get_ticks_msec() + resync_grace_ms
	for conn in _held.keys():
		_held[conn] = until
		if _is_open():
			_ws.send_text(JSON.stringify({"k": "kick", "c": int(conn) - NetProtocol.RELAY_CONN_BASE, "code": NetProtocol.CLOSE_RESYNC,
				"reason": "neu anmelden"}))
	if not _held.is_empty():
		_log("Online wieder da: %d Gäste melden sich neu an" % _held.size())

func _drop_all_guests(code: int, reason: String) -> void:
	for conn in _held.keys():
		_held.erase(conn)
		ws_closed.emit(conn, code, reason)
	for conn in _guests.keys():
		_guests.erase(conn)
		ws_closed.emit(conn, code, reason)

func _lost(reason: String, delay := -1) -> void:
	# delay ≥ 0: so bald neu verbinden (0 = sofort, nach der Rückkehr in die App), sonst nach der Staffel retry_ms.
	_unhold()
	if _ws != null:
		_ws.close()
		_ws = null
	_probe_since = -1
	_probe_deadline = -1
	_resume_deadline = -1
	if state == "off":
		return
	if room == "" or token == "":
		if state == "connecting" and _attempts < 2:
			_retry_at = Time.get_ticks_msec() + int(retry_ms[0])     # erster Versuch: einmal wiederholen
			return
		_fail(reason)
		return
	_hold_guests()
	error = reason
	if delay < 0:
		delay = retry_ms[mini(maxi(_attempts - 1, 0), retry_ms.size() - 1)]
	_retry_at = Time.get_ticks_msec() + delay
	_stats.reconnects += 1
	_log("%s Neuer Versuch in %.0f s." % [reason, delay / 1000.0])
	_set_state("away")

func _hold_guests() -> void:
	# Vermittler weg, Neuverbinden geplant: Gäste bleiben für die Sitzung verbunden (kein ws_closed), bis der Gastgeber zurück ist.
	# Wer ohnehin gerade gehen sollte (close_ws mit Frist), ist jetzt weg.
	for conn in _kicks.keys():
		if _guests.has(conn):
			_guests.erase(conn)
			ws_closed.emit(conn, int(_kicks[conn][1]), str(_kicks[conn][2]))
	_kicks.clear()
	for conn in _guests.keys():
		_held[conn] = -1
	_guests.clear()
	for conn in _held.keys():
		_held[conn] = -1

func _fail(reason: String) -> void:
	_unhold()
	_retry_at = -1
	if _ws != null:
		_ws.close()
		_ws = null
	_drop_all_guests(NetProtocol.CLOSE_ROOM_ENDED, "Raum beendet")
	error = reason
	room = ""
	token = ""
	link = ""
	_log("Online: " + reason)
	_set_state("failed")

func _set_state(s: String) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(s)

func _log(text: String) -> void:
	log_line.emit(text)
