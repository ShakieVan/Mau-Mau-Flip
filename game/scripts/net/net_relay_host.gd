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
# Mau-Mau Flip (Beta 1.6.1, Gastgeber-Übergabe, docs/module/uebergabe.md Abschnitt 3):
#  - close(end_room := false): {k:"end"} nur noch auf ausdrücklichen Wunsch; beim Freigeben (PREDELETE) nie. Der Raum bleibt dann
#    beim Vermittler offen, die Gäste sehen 4503, und ein Mitspieler kann übernehmen.
#  - open_existing(): bestehenden Raum mit dem Raum-Token übernehmen. Die bekannten c (aus dem Spielstand) bekommen 4012, dazu ein
#    4012-Rundumschlag an alle übrigen c bis max_c + SWEEP_EXTRA (höchstens SWEEP_PER_FRAME je Frame, Zeitbudget unter host_burst).
#    Eine Nachricht von einer unbekannten c bekommt ebenfalls 4012 (statt still verworfen zu werden).
#  - Code 4000 (ein anderes Gerät führt den Raum): zuerst Signal replaced, dann Zustand stepped_down. Die Gäste bleiben unberührt (kein
#    ws_closed), es geht nichts mehr hinaus.
#  - Vorsichtiges Neuverbinden: Jede Neuverbindung mit bestehendem Raum fragt zuerst GET /info?room=CODE. host:false → als Gastgeber
#    anmelden; host:true → Zustand check und Signal needs_check (die Spielsteuerung prüft per Probe als Gast und ruft dann claim()
#    bzw. step_down()); ohne Empfänger des Signals sofort claim() (Verhalten wie bis 1.6.0). /info nicht erreichbar → weiter warten.
#  - max_c (höchste gesehene c) und created_unix (Wanduhr beim Anlegen des Raums) für den Spielstand; Uhren einspritzbar (clock,
#    ms_clock) für Tests.

signal ws_opened(conn: int, info: Dictionary)
signal ws_message(conn: int, text: String)
signal ws_closed(conn: int, code: int, reason: String)
signal ws_dropped(conn: int, why: String, size: int)
signal log_line(text: String)
signal state_changed(state: String)
signal replaced                          # Beta 1.6.1: Code 4000, ein anderes Gerät führt den Raum (kommt vor stepped_down)
signal needs_check(info: Dictionary)     # Beta 1.6.1: /info meldet einen Gastgeber im Raum; Probe nötig, dann claim() oder step_down()

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
var state := "off"                       # off | connecting | open | away | check | stepped_down | failed
var room := ""
var token := ""
var link := ""
var limits := {}
var error := ""                          # letzter Fehlertext (deutsche msgid, für I18n.t)
var close_code := 0                      # Close-Code der letzten Vermittler-Verbindung (z. B. 4404/4403 beim Übernehmen)
# Mau-Mau Flip (Beta 1.6.1, Gastgeber-Übergabe):
var clock := Callable()                  # Tests: () -> Wanduhr in s (sonst Time.get_unix_time_from_system)
var ms_clock := Callable()               # Tests: () -> Monotonuhr in ms (sonst Time.get_ticks_msec)
var max_c := 0                           # höchste c, die dieser Gastgeber je gesehen hat (für den 4012-Rundumschlag)
var created_unix := 0                    # Wanduhr beim Anlegen des Raums (der Vermittler hält ihn höchstens 24 h)
var info_timeout_ms := NetProtocol.RELAY_INFO_TIMEOUT_MS
var sweep_extra := NetProtocol.SWEEP_EXTRA
var sweep_per_frame := NetProtocol.SWEEP_PER_FRAME
var sweep_budget := NetProtocol.SWEEP_BUDGET          # Rahmen auf einmal (unter host_burst 400 des Vermittlers)
var sweep_refill_per_s := NetProtocol.SWEEP_REFILL_PER_S
var _claim_next := false                 # nächstes _connect() meldet sich ohne /info an (open_existing, claim)
var _takeover := false                   # beim nächsten room-Rahmen den 4012-Rundumschlag starten
var _sweep_c := 0                        # nächste c des Rundumschlags
var _sweep_end := -1                     # letzte c (einschließlich); -1 = kein Rundumschlag
var _sweep_skip := {}                    # c, die schon bekannt sind (eigene 4012 über _resync_held)
var _sweep_tokens := 0.0
var _sweep_ms := 0
var _http: HTTPClient                    # GET /info?room= (vorsichtiges Neuverbinden)
var _http_sent := false
var _http_body := PackedByteArray()
var _http_deadline := -1
var _stale_ws: WebSocketPeer             # hängendes altes Socket bis zur neuen Anmeldung (nicht abgefragt, siehe _lost)
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
var _stats := {"ws_active": 0, "ws_opened": 0, "msgs_in": 0, "msgs_out": 0, "rate_dropped": 0, "oversize": 0, "reconnects": 0,
	"sweep_kicks": 0, "sweep_max_frame": 0, "unknown_kicks": 0, "info_checks": 0}

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
	close_code = 0
	max_c = 0
	created_unix = 0
	_attempts = 0
	_set_state("connecting")
	return _connect()

# Mau-Mau Flip (Beta 1.6.1, Gastgeber-Übergabe): bestehenden Raum mit dem Raum-Token als Gastgeber übernehmen (Abschnitt 3.2).
# conns: c der Online-Gäste aus dem Spielstand (ohne RELAY_CONN_BASE); sie bekommen nach dem room-Rahmen 4012 und melden sich mit
# ihrem Token neu an, dazu der Rundumschlag an alle übrigen c bis max(known_max_c, conns) + sweep_extra. Kein /info vorab (das hat
# der Aufrufer geprüft); erst ein späteres Neuverbinden geht den vorsichtigen Weg. 4404/4403 → failed (close_code sagt, welcher).
func open_existing(url: String, room_code: String, room_token: String, conns: Array, known_max_c := 0, created := 0) -> Error:
	close()
	relay_url = NetProtocol.normalize_relay_url(url)
	room = NetProtocol.normalize_room_code(room_code)
	token = room_token.left(128)
	close_code = 0
	if relay_url == "" or room == "" or token == "":
		room = ""
		token = ""
		error = "Keine gültige Vermittler-Adresse." if relay_url == "" else "Der Online-Raum ist abgelaufen. Bitte neu öffnen."
		_set_state("failed")
		return ERR_INVALID_PARAMETER
	link = NetProtocol.room_link(relay_url, room)
	error = ""
	max_c = maxi(known_max_c, 0)
	created_unix = maxi(created, 0)
	for c in conns:
		if (c is int or c is float) and int(c) > 0:
			_held[NetProtocol.RELAY_CONN_BASE + int(c)] = -1
			max_c = maxi(max_c, int(c))
	_attempts = 0
	_takeover = true
	_claim_next = true
	_set_state("connecting")
	return _connect()

# Beta 1.6.1: Nach needs_check hat die Spielsteuerung geprüft – niemand anderes führt den Raum: jetzt als Gastgeber anmelden.
func claim() -> void:
	if room == "" or token == "" or not state in ["check", "away"]:
		return
	_abort_http()
	_retry_at = -1
	_claim_next = true
	_set_state("away")
	_connect()

# Beta 1.6.1: Die Probe hat einen anderen Gastgeber gefunden: abtreten, ohne etwas zu senden (kein end, kein kick, kein bye).
func step_down() -> void:
	if state == "off" or state == "stepped_down":
		return
	_abort_http()
	_drop_stale()
	_retry_at = -1
	if _ws != null:
		_ws.close()
		_ws = null
	_unhold()
	_stop_sweep()
	_set_state("stepped_down")

# Beta 1.6.1: Online aufgeben wie bis 1.6.0 bei 4000 (alle Online-Gäste getrennt, Zustand failed) – Rückfall in NetHostSession,
# solange niemand auf replaced hört.
func give_up(reason: String) -> void:
	_fail(reason)

func close(end_room := false) -> void:
	# Online trennen. end_room (Beta 1.6.1: nur noch ausdrücklich – Tisch verlassen, Online schließen): vorher {k:"end"}, die Gäste
	# bekommen 1001 und der Raum ist weg. Sonst bleibt der Raum beim Vermittler offen (Gäste sehen 4503, Übernahme möglich).
	if _ws != null:
		if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			if end_room:
				_ws.send_text(JSON.stringify({"k": "end"}))
				_ws.poll()
			_ws.close(NetWs.CLOSE_NORMAL, "Gastgeber beendet" if end_room else "Gastgeber weg")
			_ws.poll()
		_ws = null
	_abort_http()
	_drop_stale()
	_unhold()
	_retry_at = -1
	_claim_next = false
	_takeover = false
	_stop_sweep()
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
	if _sweep_end >= 0:
		_sweep_tokens -= 1.0     # Beta 1.6.1: Spielverkehr hat Vorrang, der Rundumschlag nimmt nur, was im Budget übrig bleibt
	if _probe_since < 0:
		_probe_since = _ms()     # Prüfung nach eigenem Senden (Beta 1.3.3)

func close_ws(conn: int, code := NetWs.CLOSE_NORMAL, reason := "", grace_ms := 0) -> void:
	# Gast schließen; grace_ms > 0: erst so lange warten, ob er selbst geht (nach „reject“/„bye“, wie NetServer.close_ws).
	if _held.has(conn):
		_held.erase(conn)     # alte Verbindung eines Gastes aus der Abwesenheit (z. B. durch seine neue ersetzt)
		ws_closed.emit(conn, code, reason)
		return
	if not _guests.has(conn):
		return
	if grace_ms > 0:
		_kicks[conn] = [_ms() + grace_ms, code, reason]
		return
	_kick(conn, code, reason)

func stats() -> Dictionary:
	var out := _stats.duplicate()
	out.ws_active = _guests.size() + _held.size()
	return out

func check_now() -> void:
	# App wieder vorn (Beta 1.3.3): Verbindung zum Vermittler sofort prüfen bzw. den wartenden Neuversuch vorziehen (Beta 1.6.1: der
	# fragt zuerst /info, siehe _connect).
	var now := _ms()
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

# Beta 1.6.1: Wartet die Prüfung aus check_now() noch auf eine Antwort? (HostTable: geplante Übergabe ohne 4000 – lebt das Socket?)
func check_pending() -> bool:
	return _resume_deadline >= 0

func is_guest(conn: int) -> bool:
	return conn >= NetProtocol.RELAY_CONN_BASE

func info() -> Dictionary:
	return {"room": room, "link": link, "error": error, "relay": relay_url}

# Beta 1.6.1: Uhren (für Tests einspritzbar)
func _ms() -> int:
	return int(ms_clock.call()) if ms_clock.is_valid() else Time.get_ticks_msec()

func _unix() -> int:
	return int(clock.call()) if clock.is_valid() else int(Time.get_unix_time_from_system())

func _process(_delta: float) -> void:
	if auto_poll:
		poll()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Beta 1.6.1: kein {k:"end"} mehr – App beendet ohne „Tisch verlassen“: Raum bleibt offen, ein Mitspieler kann übernehmen.
		if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_ws.close(NetWs.CLOSE_NORMAL, "Gastgeber weg")
		_ws = null
		_http = null
		_drop_stale()
		_unhold()

func poll() -> void:
	var now := _ms()
	if _retry_at >= 0 and now >= _retry_at:
		_retry_at = -1
		_connect()
	if _http != null:
		_poll_http(now)
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
		if _sweep_end >= 0 and state == "open":
			_sweep_step(now)
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
		close_code = code
		if code == NetProtocol.CLOSE_ROOM_UNKNOWN or code == NetProtocol.CLOSE_BAD_TOKEN or code == NetProtocol.CLOSE_ROOM_ENDED:
			_fail("Der Online-Raum ist abgelaufen. Bitte neu öffnen.")
		elif code == NetWs.CLOSE_REPLACED:
			_replaced()     # Beta 1.6.1: abtreten statt _fail (das trennte alle Gäste)
		else:
			_lost("Verbindung zum Vermittler getrennt.")

# ---------- intern ----------

func _connect() -> Error:
	var query := "role=host&proto=%d&v=%s" % [NetProtocol.RELAY_PROTO, game_version.uri_encode()]
	if room != "" and token != "":
		if not _claim_next:
			return _start_check()     # Beta 1.6.1: bestehender Raum – erst /info, nie blind als Gastgeber anmelden
		query = "role=host&room=%s&token=%s" % [room, token]
	_claim_next = false
	var url := NetProtocol.relay_ws_url(relay_url, query)
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = NetProtocol.MAX_CLIENT_MESSAGE * 4 + 65536
	_ws.outbound_buffer_size = NetProtocol.RELAY_MAX_HOST_MESSAGE * 4
	_ws.max_queued_packets = 4096
	_was_open = false
	_opened_ms = _ms()
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
	var k := str(m.get("k", ""))
	if c > NetProtocol.RELAY_CONN_BASE and k in ["open", "msg", "close", "drop"]:
		max_c = maxi(max_c, c - NetProtocol.RELAY_CONN_BASE)     # Beta 1.6.1; nicht aus err (der Rundumschlag fragt unbenutzte c)
	match k:
		"room":
			room = NetProtocol.normalize_room_code(str(m.get("room", "")))
			if m.get("token") is String and str(m.token) != "":
				token = str(m.token).left(128)
				if created_unix <= 0:
					created_unix = _unix()     # neuer Raum (Beta 1.6.1)
			limits = m.get("limits", {}) if m.get("limits") is Dictionary else {}
			link = NetProtocol.room_link(relay_url, room)
			error = ""
			_attempts = 0
			_drop_stale()     # der Vermittler hat das alte Socket durch dieses ersetzt (Beta 1.6.1)
			_resync_held()
			if _takeover:
				_takeover = false
				_start_sweep()
			_log("Online-Raum %s offen" % room)
			_set_state("open")
		"open":
			if c < NetProtocol.RELAY_CONN_BASE:
				return
			if _sweep_end >= 0 and c - NetProtocol.RELAY_CONN_BASE <= _sweep_end:
				# Der Vermittler zählt c stetig hoch: ab dieser c ist alles neu, der Rundumschlag endet davor (Beta 1.6.1).
				_sweep_end = c - NetProtocol.RELAY_CONN_BASE - 1
			_guests[c] = true
			_stats.ws_opened += 1
			var agent := str((m.get("info", {}) as Dictionary).get("agent", "")) if m.get("info") is Dictionary else ""
			ws_opened.emit(c, {"address": "online", "port": 0, "host": "", "origin": "", "agent": agent.left(120), "path": NetProtocol.WS_PATH,
				"query": "", "online": true})
		"msg":
			if _guests.has(c) and m.get("d") is String:
				_stats.msgs_in += 1
				ws_message.emit(c, str(m.d))
			elif c > NetProtocol.RELAY_CONN_BASE and not _guests.has(c) and not _held.has(c) and _is_open():
				# Beta 1.6.1: unbekannte c (z. B. bei einem still toten Vorgänger angemeldet) → neu anmelden lassen statt verwerfen
				_ws.send_text(JSON.stringify({"k": "kick", "c": c - NetProtocol.RELAY_CONN_BASE, "code": NetProtocol.CLOSE_RESYNC,
					"reason": "neu anmelden"}))
				_stats.unknown_kicks += 1
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
			pass    # z. B. unknown_c: der Gast war schon weg (Rennen zwischen Senden und Trennen) bzw. Rundumschlag – still verwerfen

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
	var until := _ms() + resync_grace_ms
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
	_drop_stale()
	if _ws != null:
		if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN and room != "" and token != "" and state == "open":
			# Beta 1.6.1: Ein still hängendes Socket nicht selbst schließen, sondern bis zur neuen Anmeldung liegen lassen. Sonst
			# bemerkt der Vermittler das Schließen, während /info läuft, und schickt allen Gästen 4503 (sie warten dann 10 s);
			# so ersetzt die neue Anmeldung das alte Socket, und die Gäste bekommen gleich 4012.
			_stale_ws = _ws
		else:
			_ws.close()
		_ws = null
	_probe_since = -1
	_probe_deadline = -1
	_resume_deadline = -1
	if state == "off" or state == "stepped_down":
		_drop_stale()
		return
	if room == "" or token == "":
		if state == "connecting" and _attempts < 2:
			_retry_at = _ms() + int(retry_ms[0])     # erster Versuch: einmal wiederholen
			return
		_fail(reason)
		return
	_hold_guests()
	error = reason
	if delay < 0:
		delay = retry_ms[mini(maxi(_attempts - 1, 0), retry_ms.size() - 1)]
	_retry_at = _ms() + delay
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
	_abort_http()
	_drop_stale()
	_stop_sweep()
	_takeover = false
	_claim_next = false
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

# ---------- Mau-Mau Flip (Beta 1.6.1, Gastgeber-Übergabe): docs/module/uebergabe.md Abschnitt 3 ----------

func _replaced() -> void:
	# Code 4000: Ein anderes Gerät hat sich mit dem Raum-Token als Gastgeber angemeldet. Kein _fail (das trennte alle Gäste, bevor
	# jemand vom Abtreten weiß): zuerst replaced, dann stepped_down; die Gäste-Liste bleibt, es geht nichts mehr hinaus.
	_unhold()
	_abort_http()
	_drop_stale()
	_stop_sweep()
	_retry_at = -1
	_probe_since = -1
	_probe_deadline = -1
	_resume_deadline = -1
	error = "Der Online-Raum wird jetzt von einem anderen Gerät geführt."
	_log("Online: " + error)
	var before := state
	replaced.emit()
	if state == before:     # ein Empfänger kann schon anders entschieden haben (give_up → failed, close → off)
		_set_state("stepped_down")

func _start_check() -> Error:
	# Vorsichtiges Neuverbinden (3.4): GET <vermittler>/info?room=CODE; Ergebnis in _poll_http → _check_result.
	_abort_http()
	var tls := relay_url.begins_with("https://")
	var hostport := relay_url.substr(8 if tls else 7)
	var host := hostport
	var port := 443 if tls else 80
	var colon := hostport.rfind(":")
	if colon > 0:
		host = hostport.left(colon)
		port = int(hostport.substr(colon + 1))
	_http = HTTPClient.new()
	_http_sent = false
	_http_body = PackedByteArray()
	_http_deadline = _ms() + info_timeout_ms
	_stats.info_checks += 1
	NetAddresses.hold_unbound(hold_id())     # Android: wie beim Socket (Bindung an ein Netz ohne Internet aussetzen)
	var err := _http.connect_to_host(("https://" if tls else "http://") + host, port, TLSOptions.client() if tls else null)
	if err != OK:
		_http = null
		_check_retry("Vermittler nicht erreichbar.")
	return err

func _poll_http(now: int) -> void:
	_http.poll()
	var st := _http.get_status()
	if st == HTTPClient.STATUS_CONNECTED and not _http_sent:
		if _http.request(HTTPClient.METHOD_GET, "/info?room=" + room.uri_encode(), ["Accept: application/json"]) != OK:
			_http = null
			_check_retry("Vermittler nicht erreichbar.")
			return
		_http_sent = true
	elif st == HTTPClient.STATUS_BODY:
		_http_body.append_array(_http.read_response_body_chunk())
		if _http_body.size() > 16384:
			_abort_http()
			_check_retry("Vermittler antwortet nicht.")
			return
	elif _http_sent and _http.has_response() and (st == HTTPClient.STATUS_CONNECTED or st == HTTPClient.STATUS_DISCONNECTED):
		var code := _http.get_response_code()
		var body := _http_body.get_string_from_utf8()
		_abort_http()
		_check_result(code, body)
		return
	elif st in [HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CONNECTION_ERROR,
			HTTPClient.STATUS_TLS_HANDSHAKE_ERROR] or (st == HTTPClient.STATUS_DISCONNECTED and _http_sent):
		_abort_http()
		_check_retry("Vermittler nicht erreichbar.")
		return
	else:
		NetAddresses.expire_holds()
	if now > _http_deadline:
		_abort_http()
		_check_retry("Vermittler antwortet nicht.")

func _check_result(code: int, body: String) -> void:
	var data = JSON.parse_string(body) if code == 200 else null
	if not data is Dictionary:
		_check_retry("Vermittler antwortet nicht.")
		return
	var r = (data as Dictionary).get("room")
	if r is Dictionary and r.get("open") == false:
		close_code = NetProtocol.CLOSE_ROOM_UNKNOWN
		_fail("Der Online-Raum ist abgelaufen. Bitte neu öffnen.")
		return
	if r is Dictionary and r.get("host") == true and not needs_check.get_connections().is_empty():
		# Jemand ist als Gastgeber angemeldet: das eigene halboffene Socket – oder ein Ersatz-Gastgeber. Die Spielsteuerung prüft.
		_unhold()
		_log("Online: Raum %s hat einen Gastgeber – prüfe, wer führt" % room)
		_set_state("check")
		needs_check.emit({"room": room, "relay": relay_url})
		return
	# host:false (oder ein Vermittler ohne Raum-Auskunft, oder niemand prüft): als Gastgeber anmelden
	_claim_next = true
	_connect()

func _check_retry(reason: String) -> void:
	# /info nicht erreichbar (eigenes Netz weg): weiter warten und erneut fragen – nie blind als Gastgeber anmelden.
	_unhold()
	_attempts += 1
	error = reason
	var delay: int = retry_ms[mini(maxi(_attempts - 1, 0), retry_ms.size() - 1)]
	_retry_at = _ms() + delay
	_stats.reconnects += 1
	_log("%s Neuer Versuch in %.0f s." % [reason, delay / 1000.0])
	_set_state("away")

func _abort_http() -> void:
	if _http != null:
		_http.close()
		_http = null

func _start_sweep() -> void:
	# 4012-Rundumschlag (3.2) nach einer Übernahme: alle c von 1 bis max(max_c, bekannte c) + sweep_extra, ohne die bekannten.
	_sweep_skip.clear()
	var top := max_c
	for conn in _held.keys() + _guests.keys():
		var c := int(conn) - NetProtocol.RELAY_CONN_BASE
		_sweep_skip[c] = true
		top = maxi(top, c)
	_sweep_c = 1
	_sweep_end = top + sweep_extra
	_sweep_tokens = float(sweep_budget)
	_sweep_ms = _ms()

func _sweep_step(now: int) -> void:
	# Höchstens sweep_per_frame Rahmen je Aufruf und nicht mehr als das Zeitbudget (sweep_budget, dann sweep_refill_per_s).
	_sweep_tokens = minf(float(sweep_budget), _sweep_tokens + (now - _sweep_ms) * sweep_refill_per_s / 1000.0)
	_sweep_ms = now
	var limit := mini(sweep_per_frame, int(_sweep_tokens))
	var n := 0
	while n < limit and _sweep_c <= _sweep_end:
		var c := _sweep_c
		_sweep_c += 1
		var conn := NetProtocol.RELAY_CONN_BASE + c
		if _sweep_skip.has(c) or _guests.has(conn) or _held.has(conn):
			continue
		_ws.send_text(JSON.stringify({"k": "kick", "c": c, "code": NetProtocol.CLOSE_RESYNC, "reason": "neu anmelden"}))
		n += 1
	_sweep_tokens -= n
	_stats.sweep_kicks += n
	_stats.sweep_max_frame = maxi(int(_stats.sweep_max_frame), n)
	if _sweep_c > _sweep_end:
		_log("Online: 4012-Rundumschlag fertig (%d Rahmen)" % int(_stats.sweep_kicks))
		_stop_sweep()

func _stop_sweep() -> void:
	_sweep_end = -1
	_sweep_skip.clear()

func _drop_stale() -> void:
	# altes, hängendes Gastgeber-Socket (siehe _lost) jetzt schließen
	if _stale_ws != null:
		_stale_ws.close()
		_stale_ws = null

func sweeping() -> bool:
	return _sweep_end >= 0
