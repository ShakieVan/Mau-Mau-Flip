class_name NetDiscovery
extends Node

# Spielsuche im lokalen Netz (UDP, Port 24692), Anfrage/Antwort nach dem Muster von Draw2Race:
#  - Suchender schickt jede Sekunde „MMF?“ an den gerichteten Rundruf jeder eigenen Schnittstelle und an 255.255.255.255
#    (255.255.255.255 allein landet bei eingeschalteten mobilen Daten oft im Mobilnetz), dazu an das WLAN-Gateway (im Handy-Hotspot
#    ist das der Gastgeber), an eingetippte Adressen und – für Tests – an 127.0.0.1.
#  - Gastgeber antwortet direkt an den Absender mit JSON wie /info plus eigene Adressen (NetProtocol.make_reply).
# Einträge sind nach der Sitzungskennung sid geschlüsselt (ein Gastgeber mit mehreren Adressen = ein Eintrag) und verfallen nach
# expire_ms. Die Multicast-Sperre hält NetAndroid (Modul C) während Suche und Gastgeberbetrieb. Läuft im Hauptthread: gesucht wird
# nur, solange der Bildschirm „Beitreten“ offen ist; der Gastgeber antwortet, solange seine Hauptschleife läuft.
#
# Mau-Mau Flip (Beta 1.6.2, Gastgeber-Wächter, docs/module/uebergabe.md 10.1/10.11):
#  - Einträge tragen zusätzlich gid, gen, epoch und conn der Suchantwort (Partie-Kennung, Stand, verbundene entfernte Menschen).
#  - Uhr now_ms (Callable, Standard Time.get_ticks_msec) für Abfrageabstand, Verfall und Gastgeber-Scan; Tests spritzen sie ein.
#  - Gastgeber mit laufender Partie (gid in der eigenen Info) fragen alle scan_ms selbst „MMF?“ (Rundruf, manual, probe_local) und
#    werten die Antworten auf demselben Socket aus; die eigene sid wird übergangen. Gleiche gid → Signal rival(info), je Gastgeber
#    höchstens einmal je Scan (der Wächter zählt Scans).
#  - ports: Anfragen an mehrere UDP-Ports (Tests: mehrere Gastgeber auf 127.0.0.1 können nicht denselben Port binden); leer = port.

signal games_changed
signal log_line(text: String)
signal rival(info: Dictionary)          # Gastgeber-Modus: anderer Gastgeber derselben Partie (Eintrag wie in games)

var auto_poll := true
var query_interval_ms := 1000
var expire_ms := 5000
var refresh_targets_ms := 5000
var scan_ms := NetProtocol.HOST_SCAN_MS # Gastgeber-Modus: so oft nach Gastgebern derselben gid fragen (≤ 0: nie)
var use_broadcast := true               # false: nur Unicast-Ziele (Gateway, Adressen, lokal) – für Tests
var probe_local := false                # zusätzlich 127.0.0.1 fragen (PC-Tests)
var mode := ""                          # "" | "host" | "search"
var port := NetProtocol.DISCOVERY_PORT
var ports: Array = []                   # Zielports der Anfragen (leer: port)
var manual: Array = []                  # eingetippte Adressen (Gastgeber-Modus: Erben-Adressen und frühere Gastgeber)
var now_ms: Callable = Callable(Time, "get_ticks_msec")
var games := {}                         # Schlüssel (sid, sonst "ip:port") -> {address, addresses, port, name, version, proto, players, max,
                                        #   running, compatible, sid, gid, gen, epoch, conn, first_ms, last_ms}
var counters := {}                      # "sent", "send_err", "replies", "queries", "scans", "rivals" -> Anzahl
var _socket: PacketPeerUDP
var _info := {}
var _targets: Array = []
var _next_query_ms := 0
var _next_targets_ms := 0
var _next_scan_ms := 0
var _rival_seen := {}                   # sid -> true: in diesem Scan schon gemeldet
var _logged := {}
var _multicast := false

func start_host(info: Dictionary, listen_port := NetProtocol.DISCOVERY_PORT) -> Error:
	# Auf Anfragen antworten.
	stop()
	_socket = PacketPeerUDP.new()
	_socket.set_broadcast_enabled(true)
	var err := _socket.bind(listen_port, "0.0.0.0")   # nur IPv4: Rundruf gibt es nur dort
	if err != OK:
		_socket = null
		_log("Suche: Port %d nicht frei (%s)" % [listen_port, error_string(err)])
		return err
	mode = "host"
	port = listen_port
	_info = info.duplicate(true)
	games.clear()
	_rival_seen.clear()
	_next_scan_ms = 0
	_next_targets_ms = 0
	_multicast = NetAddresses.multicast(true)
	_log("Suche: Gastgeber antwortet auf Port %d" % listen_port)
	return OK

func set_info(info: Dictionary) -> void:
	var before := _own_gid()
	_info = info.duplicate(true)
	if mode == "host" and _own_gid() != before:
		# andere bzw. neue Partie: Einträge der alten gelten nicht mehr, gleich neu fragen
		games.clear()
		_rival_seen.clear()
		_next_scan_ms = 0

# Gastgeber-Modus (Gerätetest 1.6.2, B1): beim nächsten poll() gleich fragen (Rückkehr aus dem Hintergrund), Ziele frisch.
func scan_soon() -> void:
	_next_scan_ms = 0
	_next_targets_ms = 0
	_rival_seen.clear()

func start_search(target_port := NetProtocol.DISCOVERY_PORT) -> Error:
	stop()
	NetAddresses.bind_for("search")     # Android: vor dem Socket ans WLAN binden (mobile Daten)
	_socket = PacketPeerUDP.new()
	_socket.set_broadcast_enabled(true)
	var err := _socket.bind(0, "0.0.0.0")
	if err != OK:
		_socket = null
		_log("Suche: kein Socket (%s)" % error_string(err))
		return err
	mode = "search"
	port = target_port
	games.clear()
	counters.clear()
	_next_query_ms = 0
	_next_targets_ms = 0
	_multicast = NetAddresses.multicast(true)
	_log("Suche gestartet (Antwort-Port %d)" % _socket.get_local_port())
	return OK

func stop() -> void:
	if mode == "search":
		NetAddresses.release("search")
	if _socket != null:
		_socket.close()
		_socket = null
	if _multicast:
		NetAddresses.multicast(false)
		_multicast = false
	mode = ""

func add_manual(address: String) -> void:
	var a := NetProtocol.parse_address(address)
	if not a.is_empty() and not manual.has(a.address):
		manual.append(a.address)
		_next_targets_ms = 0
		_next_query_ms = 0

func games_list() -> Array:
	# Gefundene Spiele mit Alter (age_ms): passende zuerst, dann nach erster Sichtung.
	var now := _now()
	var list := []
	for g in games.values():
		var e: Dictionary = g.duplicate(true)
		e["age_ms"] = now - int(g.last_ms)
		list.append(e)
	list.sort_custom(func(a, b): return (a.compatible and not b.compatible) or (a.compatible == b.compatible and int(a.first_ms) < int(b.first_ms)))
	return list

func find_gid(gid: String) -> Array:
	# Einträge einer Partie (gid), höchste gen zuerst
	var list := games_list().filter(func(g): return gid != "" and str(g.gid) == gid)
	list.sort_custom(func(a, b): return int(a.gen) > int(b.gen))
	return list

func _process(_delta: float) -> void:
	if auto_poll:
		poll()

func _exit_tree() -> void:
	# Umhängen mit dem Elternknoten ist kein Ende: erst am Ende des Frames prüfen (Gerätetest 0.1.1, H1).
	_stop_if_detached.call_deferred()

func _stop_if_detached() -> void:
	if not is_inside_tree():
		stop()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		stop()

func poll() -> void:
	if _socket == null:
		return
	var now := _now()
	if mode == "host":
		_poll_host(now)
	elif mode == "search":
		_poll_search(now)

func _now() -> int:
	return int(now_ms.call())

func _own_gid() -> String:
	return NetProtocol.clean_gid(_info.get("gid"))

func _poll_host(now: int) -> void:
	# Gastgeber-Wächter (Beta 1.6.2): nur mit laufender Partie (gid) selbst fragen
	if scan_ms > 0 and _own_gid() != "" and now >= _next_scan_ms:
		_next_scan_ms = now + scan_ms
		_refresh_targets(now)
		_rival_seen.clear()
		counters["scans"] = int(counters.get("scans", 0)) + 1
		_send_queries()
	var changed := false
	while _socket.get_available_packet_count() > 0:
		var bytes := _socket.get_packet()
		var ip := _socket.get_packet_ip()
		var from := _socket.get_packet_port()
		if NetProtocol.is_query(bytes):
			if from <= 0:
				continue
			counters["queries"] = int(counters.get("queries", 0)) + 1
			if not _logged.has(ip):
				_logged[ip] = true
				_log("Suche: Anfrage von %s – antworte" % ip)
			_socket.set_dest_address(ip, from)
			_socket.put_packet(NetProtocol.make_reply(_info))
			continue
		# Antwort auf den eigenen Scan (Beta 1.6.2); die eigene (Rundruf kommt zurück) übergehen
		var info := NetProtocol.parse_reply(bytes)
		if info.is_empty() or NetProtocol.ipv4_to_int(ip) < 0:
			continue
		var own_sid := str(_info.get("sid", ""))
		if own_sid != "" and str(info.sid) == own_sid:
			continue
		var entry := _take_reply(info, ip, now)
		changed = true
		var gid := _own_gid()
		var key := str(info.sid) if str(info.sid) != "" else "%s:%d" % [ip, info.port]
		if gid != "" and str(entry.gid) == gid and not _rival_seen.has(key):
			_rival_seen[key] = true
			counters["rivals"] = int(counters.get("rivals", 0)) + 1
			if not _logged.has("rival:" + key):
				_logged["rival:" + key] = true
				_log("Wächter: „%s“ %s:%d führt dieselbe Partie (gen %d, %d verbunden)" % [entry.name, ip, entry.port, entry.gen, entry.conn])
			rival.emit(entry.duplicate(true))
	# Gastgeber-Modus: Einträge leben mindestens zwei Scans lang
	if _expire(now, maxi(expire_ms, scan_ms * 2 + 1000)):
		changed = true
	if changed:
		games_changed.emit()

func _poll_search(now: int) -> void:
	_refresh_targets(now)
	if now >= _next_query_ms:
		_next_query_ms = now + query_interval_ms
		_send_queries()
	var changed := false
	while _socket.get_available_packet_count() > 0:
		var bytes := _socket.get_packet()
		var ip := _socket.get_packet_ip()
		var info := NetProtocol.parse_reply(bytes)
		if info.is_empty() or NetProtocol.ipv4_to_int(ip) < 0:
			continue
		_take_reply(info, ip, now)
		changed = true
	if _expire(now, expire_ms):
		changed = true
	if changed:
		games_changed.emit()

func _refresh_targets(now: int) -> void:
	if now < _next_targets_ms:
		return
	_next_targets_ms = now + refresh_targets_ms
	_targets = []
	if use_broadcast:
		_targets.append_array(NetAddresses.broadcast_targets())
		var gw := NetAddresses.gateway()
		if gw != "":
			_targets.append(gw)
	for a in manual:
		if not _targets.has(a):
			_targets.append(a)
	if probe_local and not _targets.has("127.0.0.1"):
		_targets.append("127.0.0.1")

func _send_queries() -> void:
	var q := NetProtocol.DISCOVERY_QUERY.to_ascii_buffer()
	var to_ports: Array = ports if not ports.is_empty() else [port]
	for t in _targets:
		for p in to_ports:
			_socket.set_dest_address(t, int(p))
			if _socket.put_packet(q) == OK:
				counters["sent"] = int(counters.get("sent", 0)) + 1
			else:
				counters["send_err"] = int(counters.get("send_err", 0)) + 1

func _take_reply(info: Dictionary, ip: String, now: int) -> Dictionary:
	# Antwort in games eintragen bzw. auffrischen; liefert den Eintrag.
	counters["replies"] = int(counters.get("replies", 0)) + 1
	var key := str(info.sid) if str(info.sid) != "" else "%s:%d" % [ip, info.port]
	var known := games.has(key)
	var entry: Dictionary = games[key] if known else {"address": ip, "addresses": [], "first_ms": now}
	# Bevorzugt die Adresse, über die die Antwort kam – außer Loopback, wenn es eine echte gibt.
	if entry.address.begins_with("127.") and not ip.begins_with("127."):
		entry.address = ip
	for a in [ip] + info.addresses:
		if not entry.addresses.has(a):
			entry.addresses.append(a)
	for field in ["name", "version", "proto", "players", "max", "port", "running", "compatible", "sid", "gid", "gen", "epoch", "conn"]:
		entry[field] = info[field]
	entry["last_ms"] = now
	games[key] = entry
	if not known:
		_log("Gefunden: „%s“ %s:%d (Version %s, %d Spieler)" % [entry.name, ip, entry.port, entry.version, entry.players])
	return entry

func _expire(now: int, after_ms: int) -> bool:
	var changed := false
	for key in games.keys():
		if now - int(games[key].last_ms) > after_ms:
			games.erase(key)
			changed = true
	return changed

func _log(text: String) -> void:
	log_line.emit(text)
