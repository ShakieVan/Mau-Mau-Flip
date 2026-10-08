class_name NetClient
extends Node

# App-Mitspieler (docs/BETA1_PLAN.md Abschnitt 5): Godot-WebSocketPeer auf ws://<host>:<port>/ws. Meldet sich mit „hello“ an, merkt
# sich das Token je Gastgeber-Adresse (auch über einen Neustart, user://netz_token.json) und verbindet bei Verlust selbst neu –
# Abstand 1, 2, 4, dann 5 s, mit Token, also als derselbe Spieler. Lebenszeichen „ping“ alle 5 s; kommt 15 s lang nichts, gilt die
# Verbindung als verloren. Endgültig ist nur: close(), Ablehnung („reject“), „bye“ des Gastgebers oder Ersetzung durch eine neuere
# Verbindung desselben Spielers (Code 4000).
# Zustände: idle → connecting → open (angenommen) → connecting (neu verbinden) … → closed.
# Online (docs/online/ENTWURF.md): connect_relay(vermittler, raumcode) bzw. connect_to mit einem Raum-Link als Adresse
# („https://<vermittler>/?r=KATZE-42“): wss://<vermittler>/ws?role=guest&room=CODE, Token je Raum (relay:<vermittler>/<CODE>),
# Herzschlag „ping“ alle 25 s (Antwort „pong“ vom Vermittler), 70 s Stille = getrennt. Code 4503 (Gastgeber kurz weg) → 10 s
# warten; 4404 (Raum unbekannt), 4409 (voll) und 1001 (Raum beendet) sind endgültig.

signal state_changed(state: String)
signal welcomed(id: int, host_name: String)
signal message(msg: Dictionary)
signal rejected(code: String, text: String)
signal closed(text: String)
signal log_line(text: String)

const RETRY_MS := [1000, 2000, 4000, 5000]
const PING_MS := 5000
const TIMEOUT_MS := 15000
const CONNECT_TIMEOUT_MS := 8000
const TOKEN_FILE := "user://netz_token.json"
const MAX_TOKENS := 12

var auto_poll := true
var auto_reconnect := true
var persist_tokens := true
var reuse_token := true                 # false: als neuer Spieler anmelden (Tests mit mehreren Clients je Adresse)
var connect_timeout_ms := CONNECT_TIMEOUT_MS
var ping_ms := PING_MS
var timeout_ms := TIMEOUT_MS
var retry_ms: Array = RETRY_MS.duplicate()
var host_away_ms := NetProtocol.RELAY_HOST_AWAY_MS   # Online, Code 4503: so lange warten
var hello_override := {}                 # nur Tests: Felder der Begrüßung ersetzen (z. B. falsche Version)
var state := "idle"                      # idle | connecting | open | closed
var address := ""
var port := 0
var kind := "app"
var player_name := "Gast"
var my_id := 0
var token := ""
var host_name := ""
var close_text := ""
var reject_code := ""
var attempts := 0                        # Verbindungsversuche seit der letzten Annahme
var rtt_ms := -1.0
var relay_url := ""                      # Online: Vermittler (normalisiert), sonst ""
var room := ""                           # Online: Raumcode
var _ws: WebSocketPeer
var _was_open := false
var _welcomed := false
var _opened_ms := 0
var _last_rx_ms := 0
var _next_ping_ms := 0
var _retry_at := -1
var _closing: WebSocketPeer
var _closing_until := 0
static var _tokens := {}

func connect_to(host_address: String, host_port := NetProtocol.PORT, name_of_player := "Gast", client_kind := "app") -> Error:
	var link := NetProtocol.parse_room_link(host_address)
	if not link.is_empty():
		return connect_relay(str(link.relay), str(link.room), name_of_player, client_kind)
	close()
	relay_url = ""
	room = ""
	address = host_address
	port = host_port
	player_name = NetProtocol.clean_name(name_of_player)
	kind = client_kind
	token = _load_token(_key()) if reuse_token else ""
	my_id = 0
	attempts = 0
	close_text = ""
	reject_code = ""
	_set_state("connecting")
	NetAddresses.bind_for("join", address)   # Android: Sockets ins richtige Netz (WLAN bzw. eigener Hotspot)
	return _open()

func connect_relay(relay: String, code: String, name_of_player := "Gast", client_kind := "app") -> Error:
	# Online-Gast über den Vermittler. address = Raum-Link, port = 0 (ClientTable.same_game vergleicht beides).
	close()
	relay_url = NetProtocol.normalize_relay_url(relay)
	room = NetProtocol.normalize_room_code(code)
	address = NetProtocol.room_link(relay_url, room)
	port = 0
	player_name = NetProtocol.clean_name(name_of_player)
	kind = client_kind
	my_id = 0
	attempts = 0
	close_text = ""
	reject_code = ""
	if relay_url == "" or room == "":
		_set_state("connecting")
		_final(I18n.t("Raumcode oder Vermittler-Adresse ungültig."))
		return ERR_INVALID_PARAMETER
	token = _load_token(_key()) if reuse_token else ""
	_set_state("connecting")
	return _open()

func is_online() -> bool:
	return relay_url != ""

func send(msg: Dictionary) -> Error:
	# Nur angenommen (state == "open"); sonst ERR_UNAVAILABLE (die Spielsteuerung zeigt „Verbindung …“).
	if state != "open" or _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE
	return _ws.send_text(NetProtocol.encode(msg))

func close(text := "") -> void:
	# Endgültig trennen (kein Neuverbinden).
	if _ws != null:
		if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_ws.close(NetWs.CLOSE_NORMAL, "Verlassen")
			_closing = _ws
			_closing_until = Time.get_ticks_msec() + 1000
		_ws = null
	_retry_at = -1
	if state != "idle" and state != "closed":
		_final(text if text != "" else I18n.t("Verbindung beendet."))

func forget_token() -> void:
	token = ""
	_store_token(_key(), "")

func _process(_delta: float) -> void:
	if auto_poll:
		poll()

func _exit_tree() -> void:
	# Umhängen (Beitreten → Tisch hängt ClientTable samt NetClient um) ist kein Ende: erst am Ende des Frames prüfen, ob der Knoten
	# wirklich draußen ist (Gerätetest 0.1.1, H1).
	_close_if_detached.call_deferred()

func _close_if_detached() -> void:
	if not is_inside_tree():
		close()

func _notification(what: int) -> void:
	# Freigeben: Verbindung still schließen – keine Signale mehr an Knoten, die gerade mit abgebaut werden.
	if what == NOTIFICATION_PREDELETE:
		if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_ws.close(NetWs.CLOSE_NORMAL, "Verlassen")
		_ws = null
		_closing = null
		_retry_at = -1
		if state != "idle" and state != "closed":
			NetAddresses.release("join")
			state = "closed"

func poll() -> void:
	var now := Time.get_ticks_msec()
	if _closing != null:
		_closing.poll()
		if _closing.get_ready_state() == WebSocketPeer.STATE_CLOSED or now > _closing_until:
			_closing = null
	if _retry_at >= 0 and now >= _retry_at:
		_retry_at = -1
		_open()
	if _ws == null:
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not _was_open:
		_was_open = true
		_last_rx_ms = now
		var hello := NetProtocol.make_hello(player_name, kind, token)
		hello.merge(hello_override, true)
		_ws.send_text(NetProtocol.encode(hello))
	# Auch nach dem Schließen abholen: „reject“ bzw. „bye“ kommen direkt vor dem Close-Rahmen.
	while _ws != null and _ws.get_available_packet_count() > 0:
		var bytes := _ws.get_packet()
		_last_rx_ms = now
		if bytes.size() > NetProtocol.MAX_HOST_MESSAGE:
			continue
		if is_online() and bytes.size() == 4 and bytes.get_string_from_utf8() == "pong":
			continue    # Herzschlag des Vermittlers
		_handle(NetProtocol.decode(bytes.get_string_from_utf8(), NetProtocol.MAX_HOST_MESSAGE))
	if _ws == null:
		return
	var limit := NetProtocol.RELAY_TIMEOUT_MS if is_online() and timeout_ms == TIMEOUT_MS else timeout_ms
	if st == WebSocketPeer.STATE_OPEN:
		if _welcomed and now >= _next_ping_ms:
			_next_ping_ms = now + _ping_every()
			# Online: Text „ping“ (der Vermittler antwortet selbst, ohne aufzuwachen); im WLAN das Spiel-Ping mit Laufzeit
			_ws.send_text("ping" if is_online() else NetProtocol.encode({"t": "ping", "ts": now}))
		if now - _last_rx_ms > limit:
			_lost(I18n.t("Gastgeber antwortet nicht (%d s).") % (limit / 1000))
		elif not _welcomed and now - _opened_ms > connect_timeout_ms:
			_lost(I18n.t("Anmeldung nicht beantwortet."))
	elif st == WebSocketPeer.STATE_CONNECTING:
		if now - _opened_ms > connect_timeout_ms:
			if is_online():
				_lost(I18n.t("Vermittler nicht erreichbar."))
			else:
				_lost(I18n.t("Gastgeber %s:%d nicht erreichbar.") % [address, port])
	elif st == WebSocketPeer.STATE_CLOSED:
		var code := _ws.get_close_code()
		if code == NetWs.CLOSE_REPLACED:
			_ws = null
			_final(I18n.t("Diese Verbindung wurde durch eine neuere ersetzt."))
			return
		if is_online() and _relay_close(code):
			return
		_lost(I18n.t("Verbindung getrennt (%d).") % code if code > 0 else I18n.t("Verbindung getrennt."))

func _ping_every() -> int:
	return NetProtocol.RELAY_PING_MS if is_online() and ping_ms == PING_MS else ping_ms

func _relay_close(code: int) -> bool:
	# Schließcodes des Vermittlers. true = erledigt (endgültig oder Warten geplant).
	match code:
		NetProtocol.CLOSE_ROOM_UNKNOWN:
			_ws = null
			_final(I18n.t("Raum %s nicht gefunden. Stimmt der Code?") % room)
			return true
		NetProtocol.CLOSE_ROOM_FULL:
			_ws = null
			_final(I18n.t("Der Online-Raum ist voll."))
			return true
		NetProtocol.CLOSE_ROOM_ENDED:
			_ws = null
			_final(I18n.t("Der Gastgeber hat das Spiel beendet."))
			return true
		NetProtocol.CLOSE_HOST_AWAY:
			_ws = null
			var wait := host_away_ms
			_retry_at = Time.get_ticks_msec() + wait
			close_text = I18n.t("Gastgeber kurz weg – warte …")
			_log("Gastgeber kurz weg (4503), neuer Versuch in %.0f s." % (wait / 1000.0))
			_set_state("connecting")
			return true
	return false

func _open() -> Error:
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = NetProtocol.MAX_HOST_MESSAGE + 4096
	_ws.outbound_buffer_size = 65536
	_ws.max_queued_packets = 4096
	_was_open = false
	_welcomed = false
	_opened_ms = Time.get_ticks_msec()
	attempts += 1
	var err := OK
	if is_online():
		var url := NetProtocol.relay_ws_url(relay_url, "role=guest&room=" + room)
		err = _ws.connect_to_url(url, TLSOptions.client() if url.begins_with("wss://") else null)
		if err != OK:
			_lost(I18n.t("Vermittler nicht erreichbar."))
		return err
	err = _ws.connect_to_url("ws://%s:%d%s" % [address, port, NetProtocol.WS_PATH])
	if err != OK:
		_lost(I18n.t("Verbindung zu %s:%d nicht möglich (%s).") % [address, port, error_string(err)])
	return err

func _handle(msg: Dictionary) -> void:
	if msg.is_empty():
		return
	match str(msg.t):
		"welcome":
			my_id = int(msg.get("id", 0)) if msg.get("id") is int else 0
			token = str(msg.get("token", "")).left(64)
			host_name = NetProtocol.clean_name(str(msg.get("host_name", "")), "Gastgeber")
			_store_token(_key(), token)
			_welcomed = true
			attempts = 0
			_next_ping_ms = Time.get_ticks_msec() + _ping_every()
			_log("Angenommen von „%s“ als Spieler %d" % [host_name, my_id])
			_set_state("open")
			welcomed.emit(my_id, host_name)
		"reject":
			reject_code = str(msg.get("code", "")).left(16)
			var text := I18n.msg_text(msg, "Abgelehnt.").left(400)   # Bausteine (lt) bzw. deutsche msgid → eigene Sprache
			_log("Abgelehnt (%s): %s" % [reject_code, text])
			if _ws != null:
				_ws.close()
				_closing = _ws
				_closing_until = Time.get_ticks_msec() + 1000
				_ws = null
			rejected.emit(reject_code, text)
			_final(text)
		"bye":
			var text := I18n.msg_text(msg, "Der Gastgeber hat das Spiel beendet.").left(400)
			if _ws != null:
				_ws.close()
				_closing = _ws
				_closing_until = Time.get_ticks_msec() + 1000
				_ws = null
			_final(text)
		"pong":
			if msg.get("ts") is int:
				rtt_ms = float(Time.get_ticks_msec() - int(msg.ts))
		_:
			if _welcomed:
				message.emit(msg)

func _lost(reason: String) -> void:
	if _ws != null:
		_ws.close()
		_ws = null
	if state == "closed" or state == "idle":
		return
	if not auto_reconnect:
		_final(reason)
		return
	var delay: int = retry_ms[mini(maxi(attempts - 1, 0), retry_ms.size() - 1)]
	_retry_at = Time.get_ticks_msec() + delay
	_log("%s Neuer Versuch in %.0f s." % [reason, delay / 1000.0])
	close_text = reason
	_set_state("connecting")

func _final(text: String) -> void:
	_retry_at = -1
	NetAddresses.release("join")
	close_text = text
	_set_state("closed")
	closed.emit(text)

func _set_state(s: String) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(s)

func _key() -> String:
	if is_online():
		return "relay:%s/%s" % [NetProtocol.relay_host(relay_url), room]
	return "%s:%d" % [address, port]

func _load_token(key: String) -> String:
	if _tokens.has(key):
		return str(_tokens[key])
	if persist_tokens and FileAccess.file_exists(TOKEN_FILE):
		var data = JSON.parse_string(FileAccess.get_file_as_string(TOKEN_FILE))
		if data is Dictionary and data.get(key) is Dictionary and data[key].get("token") is String:
			return str(data[key].token).left(64)
	return ""

func _store_token(key: String, value: String) -> void:
	_tokens[key] = value
	if not persist_tokens:
		return
	var data := {}
	if FileAccess.file_exists(TOKEN_FILE):
		var old = JSON.parse_string(FileAccess.get_file_as_string(TOKEN_FILE))
		if old is Dictionary:
			data = old
	if value == "":
		data.erase(key)
	else:
		data[key] = {"token": value, "t": int(Time.get_unix_time_from_system())}
	if data.size() > MAX_TOKENS:
		var keys := data.keys()
		keys.sort_custom(func(a, b): return int(data[a].get("t", 0)) < int(data[b].get("t", 0)) if data[a] is Dictionary and data[b] is Dictionary else false)
		for k in keys.slice(0, data.size() - MAX_TOKENS):
			data.erase(k)
	var f := FileAccess.open(TOKEN_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()

func _log(text: String) -> void:
	log_line.emit(text)
