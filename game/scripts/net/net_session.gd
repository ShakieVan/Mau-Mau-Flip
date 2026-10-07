class_name NetHostSession
extends Node

# Gastgeber-Sitzung (docs/BETA1_PLAN.md Abschnitt 5), spielunabhängig: kennt nur Spieler, Token, Plätze und Bereit-Status, keine
# Karten. Besitzt den NetServer (ein Port für Seiten, APK und WebSocket) und auf Wunsch die Suche (NetDiscovery als Gastgeber).
#  - Begrüßung prüft Protokoll und Spielversion (exakt gleich), sonst Ablehnung mit Klartext; volle Runde und laufende Partie
#    werden abgelehnt. Wer ein bekanntes Token mitbringt, ist derselbe Spieler (gleiche id, gleicher Platz) – auch mitten in der Partie.
#  - Verbindungsverlust: connected=false, der Platz bleibt reserviert. Der Gastgeber und Computergegner sind lokale Spieler.
#  - Plätze ordnet der Gastgeber (set_seat_order). Lobby-Nachricht: lobby_message(); nach jeder Änderung verteilt (auto_lobby).
# Die Spielsteuerung (Modul G) verbindet sich mit player_joined/left/rejoined und message(id, msg) und sendet mit send_to/broadcast.
#
# Nutzung: var s := NetHostSession.new(); add_child(s); s.start("Lena"); var me := s.host_id; s.message.connect(…)

signal player_joined(id: int)
signal player_left(id: int)
signal player_rejoined(id: int)
signal message(id: int, msg: Dictionary)
signal lobby_changed
signal finished                          # finish() ist fertig: alles geschlossen
signal log_line(text: String)
signal page_visited(address: String)     # ein fremdes Gerät (nicht dieses) hat die Spielseite „/“ abgerufen (Lobby, Beta 1.0.2)

const HELLO_TIMEOUT_MS := 10000
const CLOSE_GRACE_MS := 3000             # nach „reject“/„bye“: so lange darf der Client selbst schließen (NetServer.close_ws)
const FINISH_MS := 2000                  # finish(): höchstens so lange auf die Clients warten

var auto_poll := true
var hello_timeout_ms := HELLO_TIMEOUT_MS   # so lange darf eine neue Verbindung ohne „hello“ bleiben
var auto_lobby := true                   # nach jeder Änderung die Lobby an alle schicken (solange keine Partie läuft)
var use_discovery := true
var discovery_port := NetProtocol.DISCOVERY_PORT
var game_version := NetProtocol.game_version()   # Tests: andere Version vortäuschen
var web_zip_path := "res://assets/web.zip"     # Browser-Client (an den Server weitergereicht)
var apk_provider := Callable()           # () -> {path, size, name} für /apk (App.apk_share.server_info), an den Server weitergereicht
var max_players := NetProtocol.MAX_PLAYERS
var server: NetServer
var discovery: NetDiscovery
var host_name := "Gastgeber"
var host_id := 0
var rules := {}
var running := false                     # Partie läuft: Neue ohne Token werden abgelehnt („running“)
var rev := 0
var sid := ""
var players := {}                        # id -> {id, name, kind, token, connected, ready, seat, conn, local, address}
var _conn_player := {}                   # Verbindung -> id
var _pending := {}                       # Verbindung -> {since_ms, info}
var _next_id := 1
var _dirty := false
var _stopping := false
var _finish_at := 0

# ---------- Lebenszyklus ----------

func start(name_of_host: String, port_first := NetProtocol.PORT, port_last := NetProtocol.PORT_LAST, threaded := true) -> Error:
	# Server starten und den Gastgeber als ersten Spieler (Platz 0) eintragen.
	stop()
	NetAddresses.bind_for("host")    # Android: Bindung vor den Sockets (WLAN, eigener Hotspot oder ungebunden – Draw2Race-Regeln)
	server = NetServer.new()
	server.name = "NetServer"
	server.auto_poll = false
	server.threaded = threaded
	server.web_zip_path = web_zip_path
	server.apk_provider = apk_provider
	add_child(server)
	server.ws_opened.connect(_on_open)
	server.ws_message.connect(_on_message)
	server.ws_closed.connect(_on_closed)
	server.ws_dropped.connect(_on_dropped)
	server.log_line.connect(_log)
	server.page_visited.connect(_on_page)
	var err := server.start(port_first, port_last)
	if err != OK:
		_drop_node(server)
		server = null
		NetAddresses.release("host")
		return err
	if apk_provider.is_valid():
		# Vorbereitung anstoßen (ApkShare kopiert die APK im Hintergrund); ist sie schon bereit, gilt sie sofort.
		var apk = apk_provider.call()
		if apk is Dictionary and not apk.is_empty():
			server.set_apk(apk)
	sid = Crypto.new().generate_random_bytes(6).hex_encode()
	host_name = NetProtocol.clean_name(name_of_host, "Gastgeber")
	host_id = add_local_player(host_name, "app")
	if use_discovery:
		discovery = NetDiscovery.new()
		discovery.name = "NetDiscovery"
		discovery.auto_poll = false
		add_child(discovery)
		discovery.log_line.connect(_log)
		if discovery.start_host(info(), discovery_port) != OK:
			_log("Suche: Port %d belegt – Mitspieler finden das Spiel nur über die Adresse" % discovery_port)
	_changed()
	_log("Gastgeber „%s“ bereit auf Port %d (Protokoll %d, Version %s)" % [host_name, server.port, NetProtocol.PROTO, game_version])
	return OK

func finish(text := "Der Gastgeber hat das Spiel beendet.") -> void:
	# Nicht blockierend beenden: allen „bye“ schicken, poll() schließt alles, sobald die Clients getrennt haben (höchstens FINISH_MS),
	# dann Signal finished. Bevorzugt vor stop(text), weil die Clients dabei weiter abgefragt werden.
	if server == null or _finish_at > 0:
		return
	_bye_all(text, FINISH_MS - 500)
	_finish_at = Time.get_ticks_msec() + FINISH_MS

func stop(text := "") -> void:
	# Sofort beenden; mit text vorher „bye“ an alle und bis zu 1 s warten. Signale gehen dabei keine mehr hinaus.
	_stopping = true
	_finish_at = 0
	if server != null:
		if text != "":
			_bye_all(text, 800)
			var end := Time.get_ticks_msec() + 1000
			while Time.get_ticks_msec() < end and int(server.stats().get("ws_active", 0)) > 0:
				server.poll()
				OS.delay_msec(5)
		server.stop()
		_drop_node(server)
		server = null
		NetAddresses.release("host")
	if discovery != null:
		discovery.stop()
		_drop_node(discovery)
		discovery = null
	_stopping = false
	players.clear()
	_conn_player.clear()
	_pending.clear()
	host_id = 0
	running = false

func port() -> int:
	return server.port if server != null else 0

func rebind() -> String:
	# Nach dem Öffnen des Spiel-WLANs (LocalOnlyHotspot): Bindung neu bewerten (NetAddresses.bind_for, Draw2Race-Regeln). Waren Server
	# und Suche ans WLAN gebunden, erreichen sie die Spiel-WLAN-Gäste nicht; dann entstehen beide neu auf demselben Port, solange noch
	# kein Mitspieler verbunden ist. "" = passt, sonst deutscher Hinweis.
	if server == null:
		return ""
	var before := NetAddresses.bound_to
	var now := NetAddresses.bind_for("host")
	if now == before:
		return ""
	var guests := players.values().filter(func(p): return not bool(p.get("local", false)) and int(p.get("conn", -1)) >= 0)
	if not guests.is_empty():
		return "Mitspieler sind schon verbunden. Damit das Spiel-WLAN klappt, eröffne das Spiel neu."
	var p := server.port
	server.stop()
	var err := server.start(p, p)
	if err != OK:
		err = server.start(NetProtocol.PORT, NetProtocol.PORT_LAST)
	if err != OK:
		return "Das Spiel ließ sich nicht neu öffnen. Bitte zurück und neu eröffnen."
	if discovery != null:
		discovery.start_host(info(), discovery_port)
	_log("Neu gebunden (%s → %s) auf Port %d" % [before if before != "" else "ungebunden", now if now != "" else "ungebunden", server.port])
	return ""

func _process(_delta: float) -> void:
	if auto_poll:
		poll()

func _exit_tree() -> void:
	# Umhängen (reparent, z. B. Lobby → Tisch) verlässt den Baum nur kurz. Erst am Ende des Frames prüfen, ob die Sitzung wirklich
	# draußen ist; sonst ginge der Server mitten im Spielstart aus (Gerätetest 0.1.1, H1). Beim Freigeben stoppt NOTIFICATION_PREDELETE.
	_stop_if_detached.call_deferred()

func _stop_if_detached() -> void:
	if not is_inside_tree():
		stop()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		stop()

func poll() -> void:
	if server == null:
		return
	server.poll()
	if discovery != null:
		discovery.poll()
	var now := Time.get_ticks_msec()
	for conn in _pending.keys():
		if now - int(_pending[conn].since_ms) > hello_timeout_ms:
			_pending.erase(conn)
			server.close_ws(conn, NetWs.CLOSE_TIMEOUT, "Anmeldung fehlt")
	if _finish_at > 0 and (int(server.stats().get("ws_active", 0)) == 0 or now > _finish_at):
		stop()
		finished.emit()
		return
	if _dirty:
		_dirty = false
		_publish()

func _bye_all(text: String, grace_ms: int) -> void:
	var conns := _connected_conns()
	server.send_text_many(conns, NetProtocol.encode({"t": "bye", "text": text}))
	for conn in conns:
		server.close_ws(conn, NetWs.CLOSE_GOING_AWAY, "Gastgeber beendet", grace_ms)
	for conn in _pending.keys():
		server.close_ws(conn, NetWs.CLOSE_GOING_AWAY, "Gastgeber beendet")
	_pending.clear()

# ---------- Spieler ----------

func add_local_player(player_name: String, kind := "bot") -> int:
	# Gastgeber ("app") oder Computergegner ("bot"): immer verbunden und bereit. -1 = voll.
	if players.size() >= max_players:
		return -1
	var id := _next_id
	_next_id += 1
	players[id] = {"id": id, "name": NetProtocol.unique_name(NetProtocol.clean_name(player_name, "Computer"), _names()), "kind": kind,
		"token": "", "connected": true, "ready": true, "seat": _next_seat(), "conn": -1, "local": true, "address": ""}
	_changed()
	return id

func remove_player(id: int, text := "Der Gastgeber hat dich aus der Runde genommen.") -> void:
	# Spieler entfernen (Gastgeber-Knopf); ein verbundener bekommt „bye“. Plätze rücken nach.
	if not players.has(id) or id == host_id:
		return
	var p: Dictionary = players[id]
	if int(p.conn) >= 0:
		server.send_text(p.conn, NetProtocol.encode({"t": "bye", "text": text}))
		server.close_ws(p.conn, NetWs.CLOSE_NORMAL, "entfernt", CLOSE_GRACE_MS)
		_conn_player.erase(p.conn)
	players.erase(id)
	_compact_seats()
	_changed()

func set_seat_order(ids: Array) -> bool:
	# Sitzordnung im Uhrzeigersinn ab Platz 0. Nicht genannte Spieler folgen in ihrer bisherigen Reihenfolge. false = ungültig.
	var seen := {}
	for id in ids:
		if not (id is int) or not players.has(id) or seen.has(id):
			return false
		seen[id] = true
	var order: Array = ids.duplicate()
	for id in ordered_ids():
		if not seen.has(id):
			order.append(id)
	for i in range(order.size()):
		players[order[i]].seat = i
	_changed()
	return true

func ordered_ids() -> Array:
	# Spieler-ids nach Platz.
	var ids := players.keys()
	ids.sort_custom(func(a, b): return int(players[a].seat) < int(players[b].seat))
	return ids

func player(id: int) -> Dictionary:
	return players.get(id, {})

func seat_of(id: int) -> int:
	return int(players[id].seat) if players.has(id) else -1

func id_at_seat(seat: int) -> int:
	for id in players:
		if int(players[id].seat) == seat:
			return id
	return -1

func set_ready(id: int, ready: bool) -> void:
	if players.has(id) and players[id].ready != ready:
		players[id].ready = ready
		_changed()

func all_ready() -> bool:
	for p in players.values():
		if not p.ready or not p.connected:
			return false
	return true

func set_rules(new_rules: Dictionary) -> void:
	# Regeln ändern: Bereit-Meldungen der Mitspieler verfallen (sie sollen die neuen Regeln sehen).
	rules = new_rules.duplicate(true)
	for p in players.values():
		if not p.local:
			p.ready = false
	_changed()

func set_running(on: bool) -> void:
	running = on
	_changed()

func send_start() -> void:
	# Partie beginnt: running setzen und jedem verbundenen Mitspieler {t:"start", seat} schicken.
	running = true
	for id in players:
		send_to(id, {"t": "start", "seat": int(players[id].seat)})
	_changed()

func send_to(id: int, msg: Dictionary) -> bool:
	# An einen verbundenen Mitspieler; false = nicht verbunden oder lokal.
	if server == null or not players.has(id) or int(players[id].conn) < 0:
		return false
	server.send_text(players[id].conn, NetProtocol.encode(msg))
	return true

func broadcast(msg: Dictionary, except_id := -1) -> void:
	var conns := []
	for id in players:
		if id != except_id and int(players[id].conn) >= 0:
			conns.append(players[id].conn)
	if server != null:
		server.send_text_many(conns, NetProtocol.encode(msg))

func lobby_message() -> Dictionary:
	var list := []
	for id in ordered_ids():
		var p: Dictionary = players[id]
		list.append({"id": id, "name": p.name, "kind": p.kind, "connected": p.connected,
			"ready": p.ready, "seat": int(p.seat)})
	return {"t": "lobby", "rev": rev, "players": list, "rules": rules, "host_id": host_id}

func info() -> Dictionary:
	# Inhalt von /info und der Suchantwort.
	return NetProtocol.make_info(host_name, players.size(), port(), {"running": running, "sid": sid, "addresses": NetAddresses.own_addresses().map(func(a): return a.address)})

func apk_url(host_header := "") -> String:
	# Adresse der APK, wie der Mitspieler den Gastgeber erreicht (Host-Kopf seiner Verbindung), sonst die erste eigene Adresse.
	var host := host_header
	if host == "" or host.begins_with("127.") or host.begins_with("localhost"):
		var own := NetAddresses.own_addresses()
		if not own.is_empty():
			host = "%s:%d" % [own[0].address, port()]
		elif host == "":
			host = "127.0.0.1:%d" % port()
	return "http://%s/apk" % host

# ---------- Ereignisse des Servers ----------

func _on_page(address: String) -> void:
	if not is_own_address(address):
		page_visited.emit(address)

static func is_own_address(address: String, own: Variant = null) -> bool:
	# Eigene Adresse (Loopback oder eine Schnittstelle dieses Geräts)? own: Liste statt IP.get_local_addresses() (Tests).
	var a := address.trim_prefix("::ffff:").get_slice("%", 0)
	if a == "" or a.begins_with("127.") or a == "::1":
		return true
	for o in (own if own is Array else Array(IP.get_local_addresses())):
		if str(o).trim_prefix("::ffff:").get_slice("%", 0) == a:
			return true
	return false

func _on_open(conn: int, conn_info: Dictionary) -> void:
	_pending[conn] = {"since_ms": Time.get_ticks_msec(), "info": conn_info}

func _on_closed(conn: int, code: int, reason: String) -> void:
	_pending.erase(conn)
	if _stopping or _finish_at > 0 or not _conn_player.has(conn):
		return
	var id: int = _conn_player[conn]
	_conn_player.erase(conn)
	if not players.has(id) or int(players[id].conn) != conn:
		return
	players[id].conn = -1
	players[id].connected = false
	_log("Spieler %d „%s“ getrennt (%d%s)" % [id, players[id].name, code, " " + reason if reason != "" else ""])
	player_left.emit(id)
	_changed()

func _on_dropped(conn: int, why: String, size: int) -> void:
	if why == "size":
		server.send_text(conn, NetProtocol.encode({"t": "err", "text": "Nachricht zu groß (%d Byte) – verworfen." % size}))

func _on_message(conn: int, text: String) -> void:
	if _finish_at > 0:
		return
	var raw := NetProtocol.decode(text)
	if raw.is_empty():
		_log("Unverständliche Nachricht auf Verbindung %d verworfen (%d Zeichen)" % [conn, text.length()])
		return
	var msg := NetProtocol.clean_client_message(raw)
	if msg.is_empty():
		return
	if _pending.has(conn):
		if msg.t == "hello":
			_hello(conn, msg, _pending[conn].info)
		return
	if not _conn_player.has(conn):
		return
	var id: int = _conn_player[conn]
	match str(msg.t):
		"hello":
			return
		"ping":
			send_to(id, {"t": "pong", "ts": msg.ts})    # nur ohne Sofortantwort des Server-Threads
		"lobby_ready":
			if not running:
				set_ready(id, bool(msg.ready))
		"log":
			_log("Gast %d „%s“: %s" % [id, players[id].name, str(msg.text).left(300)])
		_:
			message.emit(id, msg)

func _hello(conn: int, msg: Dictionary, conn_info: Dictionary) -> void:
	_pending.erase(conn)
	var url := apk_url(str(conn_info.get("host", "")))
	var problem := NetProtocol.check_hello(msg, game_version, url)
	var token := str(msg.get("token", ""))
	var known := -1
	if problem.is_empty() and token != "":
		for id in players:
			if not players[id].local and players[id].token == token:
				known = id
				break
	if problem.is_empty() and known < 0:
		if running:
			problem = {"code": "running", "text": "Die Partie läuft schon. Warte, bis der Gastgeber eine neue Runde eröffnet."}
		elif players.size() >= max_players:
			problem = {"code": "full", "text": "Die Runde ist voll (höchstens %d Spieler)." % max_players}
	if not problem.is_empty():
		_log("Anmeldung von %s abgelehnt (%s): %s" % [conn_info.get("address", "?"), problem.code, problem.text])
		server.send_text(conn, NetProtocol.encode({"t": "reject", "code": problem.code, "text": problem.text}))
		server.close_ws(conn, NetWs.CLOSE_NORMAL, problem.code, CLOSE_GRACE_MS)
		return
	if known >= 0:
		var p: Dictionary = players[known]
		var old := int(p.conn)
		if old >= 0 and old != conn:
			_conn_player.erase(old)
			server.close_ws(old, NetWs.CLOSE_REPLACED, "neue Verbindung")
		p.conn = conn
		p.connected = true
		p.kind = msg.kind
		p.address = str(conn_info.get("address", ""))
		_conn_player[conn] = known
		server.send_text(conn, NetProtocol.encode({"t": "welcome", "id": known, "token": p.token, "host_name": host_name,
			"proto": NetProtocol.PROTO, "game": game_version}))
		_log("Spieler %d „%s“ wieder da (%s)" % [known, p.name, conn_info.get("address", "?")])
		player_rejoined.emit(known)
		_changed(true)
		return
	var id := _next_id
	_next_id += 1
	var new_token := Crypto.new().generate_random_bytes(NetProtocol.TOKEN_LENGTH / 2).hex_encode()
	players[id] = {"id": id, "name": NetProtocol.unique_name(str(msg.name), _names()), "kind": msg.kind, "token": new_token,
		"connected": true, "ready": false, "seat": _next_seat(), "conn": conn, "local": false,
		"address": str(conn_info.get("address", ""))}
	_conn_player[conn] = id
	server.send_text(conn, NetProtocol.encode({"t": "welcome", "id": id, "token": new_token, "host_name": host_name,
		"proto": NetProtocol.PROTO, "game": game_version}))
	_log("Spieler %d „%s“ beigetreten (%s, %s)" % [id, players[id].name, msg.kind, conn_info.get("address", "?")])
	player_joined.emit(id)
	_changed(true)

# ---------- intern ----------

func _changed(now := false) -> void:
	rev += 1
	_dirty = true
	if now:
		_dirty = false
		_publish()

func _publish() -> void:
	# Lobby verteilen (nur ohne laufende Partie; dann sendet die Spielsteuerung „state“) und /info sowie die Suche auffrischen.
	if server == null:
		return
	var i := info()
	server.set_info(i)
	if discovery != null:
		discovery.set_info(i)
	if auto_lobby and not running:
		broadcast(lobby_message())
	lobby_changed.emit()

static func _drop_node(n: Node) -> void:
	if n.is_inside_tree():
		n.queue_free()
	else:
		n.free()

func _connected_conns() -> Array:
	var out := []
	for p in players.values():
		if int(p.conn) >= 0:
			out.append(p.conn)
	return out

func _names() -> Array:
	return players.values().map(func(p): return p.name)

func _next_seat() -> int:
	var seat := 0
	for p in players.values():
		seat = maxi(seat, int(p.seat) + 1)
	return seat

func _compact_seats() -> void:
	var ids := ordered_ids()
	for i in range(ids.size()):
		players[ids[i]].seat = i

func _log(text: String) -> void:
	log_line.emit(text)
