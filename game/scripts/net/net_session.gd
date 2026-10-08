class_name NetHostSession
extends Node

# Gastgeber-Sitzung (docs/BETA1_PLAN.md Abschnitt 5), spielunabhängig: kennt nur Spieler, Token, Plätze und Bereit-Status, keine
# Karten. Besitzt den NetServer (ein Port für Seiten, APK und WebSocket) und auf Wunsch die Suche (NetDiscovery als Gastgeber).
#  - Begrüßung prüft Protokoll und Spielversion (exakt gleich), sonst Ablehnung mit Klartext; volle Runde und laufende Partie
#    werden abgelehnt. Wer ein bekanntes Token mitbringt, ist derselbe Spieler (gleiche id, gleicher Platz) – auch mitten in der Partie.
#  - Verbindungsverlust: connected=false, der Platz bleibt reserviert. Der Gastgeber und Computergegner sind lokale Spieler.
#  - Plätze ordnet der Gastgeber (set_seat_order). Lobby-Nachricht: lobby_message(); nach jeder Änderung verteilt (auto_lobby).
# Die Spielsteuerung (Modul G) verbindet sich mit player_joined/left/rejoined und message(id, msg) und sendet mit send_to/broadcast.
# Online-Spiel (docs/online/ENTWURF.md): open_online(vermittler) öffnet zusätzlich einen Raum beim Vermittler (NetRelayHost, gleiche
# Schnittstelle wie NetServer). Verbindungsnummern ab NetProtocol.RELAY_CONN_BASE gehören zum Vermittler (_link wählt den Transport),
# so spielen WLAN- und Online-Gäste in derselben Lobby und Partie. finish/stop beenden auch den Raum ({k:"end"}).
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
signal online_changed(state: String, info: Dictionary)   # Online-Spiel: off | connecting | open | away | failed; info {room, link, error, relay}

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
var relay: NetRelayHost                  # Online-Spiel über den Vermittler (open_online); Verbindungen ab NetProtocol.RELAY_CONN_BASE
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
	if (server == null and relay == null) or _finish_at > 0:
		return
	_bye_all(text, FINISH_MS - 500)
	_finish_at = Time.get_ticks_msec() + FINISH_MS

func stop(text := "") -> void:
	# Sofort beenden; mit text vorher „bye“ an alle und bis zu 1 s warten. Signale gehen dabei keine mehr hinaus.
	_stopping = true
	_finish_at = 0
	if text != "" and (server != null or relay != null):
		_bye_all(text, 800)
		var end := Time.get_ticks_msec() + 1000
		while Time.get_ticks_msec() < end and _active() > 0:
			if server != null:
				server.poll()
			if relay != null:
				relay.poll()
			OS.delay_msec(5)
	_close_relay()
	if server != null:
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

func rebind(after_close := false) -> String:
	# Nach dem Öffnen des Spiel-WLANs (LocalOnlyHotspot): Bindung neu bewerten (NetAddresses.bind_for, Draw2Race-Regeln). Waren Server
	# und Suche ans WLAN gebunden, erreichen sie die Spiel-WLAN-Gäste nicht; dann entstehen beide neu auf demselben Port, solange noch
	# kein Mitspieler verbunden ist. "" = passt, sonst deutscher Hinweis.
	# after_close (Beta 1.1.1): Spiel-WLAN wieder zu – zurück zur Bindung wie beim Eröffnen (meist ans WLAN). War die Sitzung ans
	# Spiel-WLAN gebunden, ist dessen Netz weg; dann entsteht der Server auch mit (nun getrennten) Mitspielern neu.
	if server == null:
		return ""
	var before := NetAddresses.bound_to
	var now := NetAddresses.bind_for("host")
	if now == before:
		return ""
	var guests := players.values().filter(func(p): return not bool(p.get("local", false)) and int(p.get("conn", -1)) >= 0 and int(p.get("conn", -1)) < NetProtocol.RELAY_CONN_BASE)
	if not guests.is_empty() and not (after_close and before == "hotspot"):
		if after_close:
			return I18n.t("Spiel-WLAN ist zu. Kommt jemand aus dem WLAN nicht rein, eröffne das Spiel neu.")
		return I18n.t("Mitspieler sind schon verbunden. Damit das Spiel-WLAN klappt, eröffne das Spiel neu.")
	var p := server.port
	server.stop()
	var err := server.start(p, p)
	for attempt in 4:
		# Unter Last gibt Windows den eben geschlossenen Port manchmal erst einen Augenblick später frei.
		if err == OK:
			break
		OS.delay_msec(25 * (attempt + 1))
		err = server.start(p, p)
	if err != OK:
		err = server.start(NetProtocol.PORT, NetProtocol.PORT_LAST)
	if err != OK:
		return I18n.t("Das Spiel ließ sich nicht neu öffnen. Bitte zurück und neu eröffnen.")
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
	if server == null and relay == null:
		return
	if server != null:
		server.poll()
	if relay != null:
		relay.poll()
	if discovery != null:
		discovery.poll()
	var now := Time.get_ticks_msec()
	for conn in _pending.keys():
		if now - int(_pending[conn].since_ms) > hello_timeout_ms:
			_pending.erase(conn)
			_close(conn, NetWs.CLOSE_TIMEOUT, "Anmeldung fehlt")
	if _finish_at > 0 and (_active() == 0 or now > _finish_at):
		stop()
		finished.emit()
		return
	if _dirty:
		_dirty = false
		_publish()

func _bye_all(text: String, grace_ms: int) -> void:
	var conns := _connected_conns()
	_send_many(conns, NetProtocol.encode({"t": "bye", "text": text}))
	for conn in conns:
		_close(conn, NetWs.CLOSE_GOING_AWAY, "Gastgeber beendet", grace_ms)
	for conn in _pending.keys():
		_close(conn, NetWs.CLOSE_GOING_AWAY, "Gastgeber beendet")
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
		_send(p.conn, NetProtocol.encode({"t": "bye", "text": text}))
		_close(p.conn, NetWs.CLOSE_NORMAL, "entfernt", CLOSE_GRACE_MS)
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
	if not players.has(id) or int(players[id].conn) < 0 or _link(int(players[id].conn)) == null:
		return false
	_send(players[id].conn, NetProtocol.encode(msg))
	return true

func broadcast(msg: Dictionary, except_id := -1) -> void:
	var conns := []
	for id in players:
		if id != except_id and int(players[id].conn) >= 0:
			conns.append(players[id].conn)
	_send_many(conns, NetProtocol.encode(msg))

func lobby_message() -> Dictionary:
	var list := []
	for id in ordered_ids():
		var p: Dictionary = players[id]
		var entry := {"id": id, "name": p.name, "kind": p.kind, "connected": p.connected, "ready": p.ready, "seat": int(p.seat)}
		if bool(p.get("online", false)):
			entry["online"] = true          # über den Vermittler verbunden (Weltkugel in der Lobby)
		list.append(entry)
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
		_send(conn, NetProtocol.encode(I18n.with_lt({"t": "err"}, [I18n.part("Nachricht zu groß (%d Byte) – verworfen.", [size])])))

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
	var url := NetProtocol.apk_page_url(game_version) if bool(conn_info.get("online", false)) else apk_url(str(conn_info.get("host", "")))
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
			problem = I18n.with_lt({"code": "full"}, [I18n.part("Die Runde ist voll (höchstens %d Spieler).", [max_players])])
	if not problem.is_empty():
		_log("Anmeldung von %s abgelehnt (%s): %s" % [conn_info.get("address", "?"), problem.code, problem.text])
		var rej := {"t": "reject", "code": problem.code, "text": problem.text}
		if problem.get("lt") is Array:
			rej["lt"] = problem.lt   # Bausteine (I18n): Anzeige in der Sprache des Gastes
		_send(conn, NetProtocol.encode(rej))
		_close(conn, NetWs.CLOSE_NORMAL, problem.code, CLOSE_GRACE_MS)
		return
	if known >= 0:
		var p: Dictionary = players[known]
		var old := int(p.conn)
		if old >= 0 and old != conn:
			_conn_player.erase(old)
			_close(old, NetWs.CLOSE_REPLACED, "neue Verbindung")
		p.conn = conn
		p.connected = true
		p.kind = msg.kind
		p.address = str(conn_info.get("address", ""))
		p.online = bool(conn_info.get("online", false))
		_conn_player[conn] = known
		_send(conn, NetProtocol.encode({"t": "welcome", "id": known, "token": p.token, "host_name": host_name,
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
		"address": str(conn_info.get("address", "")), "online": bool(conn_info.get("online", false))}
	_conn_player[conn] = id
	_send(conn, NetProtocol.encode({"t": "welcome", "id": id, "token": new_token, "host_name": host_name,
		"proto": NetProtocol.PROTO, "game": game_version}))
	_log("Spieler %d „%s“ beigetreten (%s, %s)" % [id, players[id].name, msg.kind, conn_info.get("address", "?")])
	player_joined.emit(id)
	_changed(true)

# ---------- Online-Spiel ----------

func open_online(relay_url: String) -> Error:
	# Raum beim Vermittler öffnen (zusätzlich zum WLAN). Fortschritt über online_changed.
	_close_relay()
	var r := NetRelayHost.new()
	r.name = "NetRelayHost"
	r.auto_poll = false
	r.game_version = game_version
	relay = r
	add_child(r)
	r.ws_opened.connect(_on_open)
	r.ws_message.connect(_on_message)
	r.ws_closed.connect(_on_closed)
	r.ws_dropped.connect(_on_dropped)
	r.log_line.connect(_log)
	r.state_changed.connect(func(st: String) -> void:
		if relay == r:
			online_changed.emit(st, r.info()))
	return r.open(relay_url)

func close_online() -> void:
	# Online-Raum schließen: Online-Gäste bekommen „bye“, der Raum wird beendet. WLAN-Gäste bleiben.
	if relay == null:
		return
	var conns := _connected_conns().filter(func(c): return int(c) >= NetProtocol.RELAY_CONN_BASE)
	relay.send_text_many(conns, NetProtocol.encode({"t": "bye", "text": "Der Gastgeber hat das Online-Spiel geschlossen."}))
	_close_relay()
	online_changed.emit("off", {})
	_changed()

func online_state() -> String:
	return relay.state if relay != null else "off"

func online_info() -> Dictionary:
	return relay.info() if relay != null else {}

func _close_relay() -> void:
	# Vermittler trennen; Online-Spieler gelten als getrennt (Platz bleibt wie bei WLAN-Gästen).
	if relay == null:
		return
	var r := relay
	relay = null
	for c in [[r.ws_opened, _on_open], [r.ws_message, _on_message], [r.ws_closed, _on_closed], [r.ws_dropped, _on_dropped]]:
		if (c[0] as Signal).is_connected(c[1]):
			(c[0] as Signal).disconnect(c[1])
	r.close()
	for conn in _pending.keys():
		if int(conn) >= NetProtocol.RELAY_CONN_BASE:
			_pending.erase(conn)
	if not _stopping:
		for conn in _conn_player.keys():
			if int(conn) >= NetProtocol.RELAY_CONN_BASE:
				_on_closed(conn, NetProtocol.CLOSE_ROOM_ENDED, "Online geschlossen")
	_drop_node(r)

# Transport einer Verbindung: Vermittler (ab RELAY_CONN_BASE) oder WLAN-Server
func _link(conn: int) -> Object:
	return relay if conn >= NetProtocol.RELAY_CONN_BASE else server

func _send(conn: int, text: String) -> void:
	var t: Object = _link(conn)
	if t != null:
		t.send_text(conn, text)

func _send_many(conns: Array, text: String) -> void:
	var lan := []
	var online := []
	for c in conns:
		if int(c) >= NetProtocol.RELAY_CONN_BASE:
			online.append(c)
		else:
			lan.append(c)
	if server != null and not lan.is_empty():
		server.send_text_many(lan, text)
	if relay != null and not online.is_empty():
		relay.send_text_many(online, text)

func _close(conn: int, code: int, reason: String, grace_ms := 0) -> void:
	var t: Object = _link(conn)
	if t != null:
		t.close_ws(conn, code, reason, grace_ms)

func _active() -> int:
	var n := 0
	if server != null:
		n += int(server.stats().get("ws_active", 0))
	if relay != null:
		n += int(relay.stats().get("ws_active", 0))
	return n

# ---------- intern ----------

func _changed(now := false) -> void:
	rev += 1
	_dirty = true
	if now:
		_dirty = false
		_publish()

func _publish() -> void:
	# Lobby verteilen (nur ohne laufende Partie; dann sendet die Spielsteuerung „state“) und /info sowie die Suche auffrischen.
	if server == null and relay == null:
		return
	var i := info()
	if server != null:
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
