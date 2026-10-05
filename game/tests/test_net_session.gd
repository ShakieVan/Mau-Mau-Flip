extends SceneTree

# Modul D, Gastgeber-Sitzung und App-Client im selben Prozess über 127.0.0.1 (TCP 24795/24797/24798, UDP 24796): Beitritt mehrerer
# NetClients (WebSocketPeer), eindeutige Namen, Token, Lobby mit Plätzen und Bereit-Status, Sitzordnung, send_to/broadcast,
# Spielaktionen, Browser-Log, Ping/RTT, Wiederverbinden mit Token (Server trennt, Client stürzt ab, Gastgeber hängt → Zeitgrenze)
# als derselbe Spieler, Partie läuft → „running“, falsche Spielversion → „version“ mit APK-Hinweis, falsches Protokoll → „proto“,
# volle Runde → „full“, Übergröße → err, Anmeldefrist, Suche über 127.0.0.1, /info, Entfernen, „bye“ und Neustart des Gastgebers.

const PORT := 24795
const DISC := 24796
const PORT2 := 24797
const PORT3 := 24798

var failures := 0
var checks := 0
var host: NetHostSession
var clients: Array = []
var hosts: Array = []
var joined: Array = []
var left: Array = []
var rejoined: Array = []
var host_msgs: Array = []
var logs: Array = []
var inbox := {}                          # NetClient -> [Nachrichten]

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)

func _init() -> void:
	host = new_host()
	host.discovery_port = DISC
	check(host.start("Lena", PORT, PORT) == OK and host.port() == PORT, "Gastgeber auf %d" % PORT)
	check(host.host_id > 0 and host.players.size() == 1 and host.player(host.host_id).seat == 0, "Gastgeber ist Spieler auf Platz 0")
	test_join()
	test_lobby()
	test_messages()
	test_reconnect()
	test_rejects()
	test_limits()
	test_discovery()
	test_remove_and_bye()
	test_host_restart()
	test_host_stall()
	for c in clients:
		c.close()
		c.free()
	for h in hosts:
		h.stop()
		h.free()
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)

# ---------- Hilfen ----------

func new_host() -> NetHostSession:
	var h := NetHostSession.new()
	h.auto_poll = false
	h.player_joined.connect(func(id): joined.append(id))
	h.player_left.connect(func(id): left.append(id))
	h.player_rejoined.connect(func(id): rejoined.append(id))
	h.message.connect(func(id, msg): host_msgs.append([id, msg]))
	h.log_line.connect(func(t): logs.append(t))
	hosts.append(h)
	return h

func new_client(player_name: String, port := PORT, start := true) -> NetClient:
	var c := NetClient.new()
	c.auto_poll = false
	c.persist_tokens = false
	c.reuse_token = false
	c.ping_ms = 300
	c.retry_ms = [150, 300, 600, 800]
	inbox[c] = []
	c.message.connect(func(m): inbox[c].append(m))
	clients.append(c)
	if start:
		c.connect_to("127.0.0.1", port, player_name)
	return c

func pump(ms: int, skip_hosts := false) -> void:
	var end := Time.get_ticks_msec() + ms
	while true:
		if not skip_hosts:
			for h in hosts:
				h.poll()
		for c in clients:
			c.poll()
		if Time.get_ticks_msec() >= end:
			break
		OS.delay_msec(1)

func wait_until(cond: Callable, ms := 3000, skip_hosts := false) -> bool:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		pump(2, skip_hosts)
		if cond.call():
			return true
	return cond.call()

func last_of(c: NetClient, t: String) -> Dictionary:
	for i in range(inbox[c].size() - 1, -1, -1):
		if inbox[c][i].get("t") == t:
			return inbox[c][i]
	return {}

func lobby_entry(c: NetClient, id: int) -> Dictionary:
	for p in last_of(c, "lobby").get("players", []):
		if p.id == id:
			return p
	return {}

func http_info(port: int) -> Dictionary:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", port)
	var buf := PackedByteArray()
	var sent := false
	var end := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < end:
		peer.poll()
		pump(1)
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			if not sent:
				sent = true
				peer.put_data("GET /info HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n".to_utf8_buffer())
			var n := peer.get_available_bytes()
			if n > 0:
				buf.append_array(peer.get_partial_data(n)[1])
		elif sent:
			break
	var text := buf.get_string_from_utf8()
	var data = JSON.parse_string(text.substr(text.find("\r\n\r\n") + 4))
	return data if data is Dictionary else {}

# ---------- Beitritt und Lobby ----------

var c1: NetClient
var c2: NetClient
var c3: NetClient

func test_join() -> void:
	c1 = new_client("Anna")
	c2 = new_client("Ben")
	c3 = new_client("Anna")
	check(wait_until(func(): return [c1, c2, c3].all(func(c): return c.state == "open")), "drei Clients angenommen")
	var ids := [c1.my_id, c2.my_id, c3.my_id]
	check(ids.all(func(i): return i > 0 and i != host.host_id) and ids[0] != ids[1] and ids[1] != ids[2] and ids[0] != ids[2], "eindeutige Spieler-ids %s" % str(ids))
	var hex := RegEx.create_from_string("^[0-9a-f]{24}$")
	check([c1, c2, c3].all(func(c): return hex.search(c.token) != null), "Token mit 24 Zeichen")
	check(c1.host_name == "Lena" and joined.size() == 3, "host_name im welcome, player_joined dreimal")
	check(wait_until(func(): return last_of(c3, "lobby").get("players", []).size() == 4), "Lobby mit 4 Spielern bei jedem")
	var names: Array = last_of(c1, "lobby").players.map(func(p): return p.name)
	check(names == ["Lena", "Anna", "Ben", "Anna 2"], "Namen in Platzreihenfolge, doppelter bekommt Ziffer (%s)" % str(names))
	var lob := last_of(c2, "lobby")
	check(lob.host_id == host.host_id and lob.rev == host.rev and lobby_entry(c2, host.host_id).kind == "app", "Lobby: host_id, rev, Art")
	check(lobby_entry(c1, c1.my_id).ready == false and lobby_entry(c1, host.host_id).ready == true and lobby_entry(c1, c2.my_id).connected, "Bereit- und Verbindungsstatus")
	check(lobby_entry(c1, c2.my_id).kind == "app" and lobby_entry(c1, c3.my_id).seat == 3, "Art und Platz")

func test_lobby() -> void:
	var rev_before: int = host.rev
	c1.send({"t": "lobby_ready", "ready": true})
	check(wait_until(func(): return lobby_entry(c2, c1.my_id).get("ready") == true), "Bereit-Meldung verteilt")
	check(host.rev > rev_before and host.player(c1.my_id).ready, "Gastgeber kennt Bereit, rev erhöht")
	check(host.set_seat_order([c3.my_id, host.host_id, c1.my_id]) and wait_until(func(): return lobby_entry(c1, c3.my_id).get("seat") == 0), "Sitzordnung gesetzt und verteilt")
	var seats: Array = last_of(c2, "lobby").players.map(func(p): return [p.id, p.seat])
	check(seats == [[c3.my_id, 0], [host.host_id, 1], [c1.my_id, 2], [c2.my_id, 3]], "nicht genannte Spieler folgen (%s)" % str(seats))
	check(not host.set_seat_order([c1.my_id, c1.my_id]) and not host.set_seat_order([999]), "ungültige Sitzordnung abgelehnt")
	host.set_rules({"hand_size": 7})
	check(wait_until(func(): return last_of(c1, "lobby").get("rules", {}).get("hand_size") == 7), "Regeln in der Lobby")
	check(lobby_entry(c1, c1.my_id).ready == false, "Regeländerung setzt Bereit zurück")
	var bot := host.add_local_player("Computer", "bot")
	check(bot > 0 and wait_until(func(): return lobby_entry(c1, bot).get("kind") == "bot"), "Computergegner in der Lobby")
	host.remove_player(bot)
	check(wait_until(func(): return lobby_entry(c1, bot).is_empty()), "Computergegner wieder entfernt")

func test_messages() -> void:
	host.send_to(c2.my_id, {"t": "state", "events": [], "view": {"seat": 3}})
	check(wait_until(func(): return not last_of(c2, "state").is_empty()), "send_to erreicht den Empfänger")
	pump(50)
	check(last_of(c1, "state").is_empty() and last_of(c3, "state").is_empty(), "send_to erreicht nur ihn")
	check(last_of(c2, "state").view.seat == 3 and last_of(c2, "state").view.seat is int, "Zahlen kommen als int an")
	host.broadcast({"t": "err", "text": "Hinweis"})
	check(wait_until(func(): return [c1, c2, c3].all(func(c): return last_of(c, "err").get("text") == "Hinweis")), "broadcast an alle")
	c1.send({"t": "act", "seq": 1, "a": {"a": "play", "card": 17, "color": "rot", "evil": [1]}})
	check(wait_until(func(): return host_msgs.size() > 0), "Aktion kommt an")
	check(host_msgs[-1][0] == c1.my_id and host_msgs[-1][1].a == {"a": "play", "card": 17, "color": "rot"} and host_msgs[-1][1].seq == 1, "Aktion bereinigt mit Absender-id")
	c3.send({"t": "log", "text": "Fehler im Browser"})
	check(wait_until(func(): return logs.any(func(l): return l.contains("Fehler im Browser"))), "Browser-Log im Gastgeber-Log")
	check(wait_until(func(): return c1.rtt_ms >= 0.0, 1500), "Ping/Pong: Laufzeit gemessen (%.1f ms)" % c1.rtt_ms)
	var idle := NetClient.new()
	check(c1.send({"t": "x"}) == OK and idle.send({"t": "x"}) == ERR_UNAVAILABLE, "send nur im Zustand open")
	idle.free()

# ---------- Wiederverbinden ----------

func test_reconnect() -> void:
	# 1. Der Server trennt (Funkloch): Client verbindet selbst neu, mit Token → gleiche id.
	var id2 := c2.my_id
	var conn: int = host.player(id2).conn
	left.clear()
	rejoined.clear()
	host.server.close_ws(conn, NetWs.CLOSE_INTERNAL, "Test")
	check(wait_until(func(): return c2.state == "connecting"), "Client merkt die Trennung (connecting)")
	check(wait_until(func(): return left.has(id2)) and not host.player(id2).connected, "player_left, connected=false, Platz bleibt")
	check(host.player(id2).seat == 3, "Platz reserviert")
	check(wait_until(func(): return c2.state == "open" and rejoined.has(id2)), "automatisch wieder verbunden, player_rejoined")
	check(c2.my_id == id2 and host.player(id2).connected and host.players.size() == 4, "derselbe Spieler, keine Doppelung")
	check(wait_until(func(): return lobby_entry(c2, id2).get("connected") == true), "nach dem Wiederbeitritt sofort Lobby")
	# 2. Der Client stürzt ab (ohne Close) und startet neu: Token aus dem Speicher → gleiche id.
	var id3 := c3.my_id
	c3._ws = null
	check(wait_until(func(): return left.has(id3)), "Absturz: Gastgeber merkt die Trennung")
	check(wait_until(func(): return lobby_entry(c1, id3).get("connected") == false), "Mitspieler sehen „getrennt“")
	NetClient._tokens["127.0.0.1:%d" % PORT] = c3.token
	var c3b := new_client("Anna neu", PORT, false)
	c3b.reuse_token = true
	c3b.connect_to("127.0.0.1", PORT, "Anna neu")
	check(wait_until(func(): return c3b.state == "open"), "Neustart: angenommen")
	check(c3b.my_id == id3 and host.player(id3).name == "Anna 2" and rejoined.has(id3), "mit Token derselbe Spieler (Name bleibt)")
	c3.free()
	clients.erase(c3)
	c3 = c3b
	# 3. Partie läuft: Rückkehr mit Token geht, neu ohne Token nicht.
	host.send_start()
	check(wait_until(func(): return last_of(c1, "start").get("seat") == host.seat_of(c1.my_id)), "start mit eigenem Platz")
	check(last_of(c3, "start").get("seat") == 0, "start beim Spieler auf Platz 0")
	var conn1: int = host.player(c1.my_id).conn
	rejoined.clear()
	host.server.close_ws(conn1, NetWs.CLOSE_INTERNAL, "Test")
	check(wait_until(func(): return rejoined.has(c1.my_id) and c1.state == "open"), "Rückkehr mitten in der Partie")
	var late := new_client("Zu spät")
	check(wait_until(func(): return late.state == "closed") and late.reject_code == "running", "neuer Spieler während der Partie → running")
	pump(400)
	check(late.state == "closed" and late.attempts <= 1, "nach Ablehnung kein Neuverbinden")
	host.set_running(false)

func test_rejects() -> void:
	var old := new_client("Alt", PORT, false)
	old.hello_override = {"game": "0.1.0"}
	old.connect_to("127.0.0.1", PORT, "Alt")
	check(wait_until(func(): return old.state == "closed") and old.reject_code == "version", "andere Spielversion → version")
	check(old.close_text.contains("App vom Gastgeber holen: http://") and old.close_text.contains(":%d/apk" % PORT), "Text mit APK-Adresse (%s)" % old.close_text)
	var proto := new_client("Proto", PORT, false)
	proto.hello_override = {"proto": 99}
	proto.connect_to("127.0.0.1", PORT, "Proto")
	check(wait_until(func(): return proto.state == "closed") and proto.reject_code == "proto", "anderes Protokoll → proto")
	var bots := []
	while host.players.size() < NetProtocol.MAX_PLAYERS:
		bots.append(host.add_local_player("Bot", "bot"))
	check(host.add_local_player("zu viel", "bot") == -1, "elfter Platz nicht möglich")
	var full := new_client("Voll")
	check(wait_until(func(): return full.state == "closed") and full.reject_code == "full", "volle Runde → full")
	var names: Array = host.players.values().map(func(p): return p.name)
	check(names.has("Bot") and names.has("Bot 2"), "Computergegner mit eindeutigen Namen")
	for b in bots:
		host.remove_player(b)
	check(host.players.size() == 4, "Computergegner entfernt")

func test_limits() -> void:
	var before: int = inbox[c1].size()
	c1.send({"t": "log", "text": "x".repeat(9000)})
	check(wait_until(func(): return last_of(c1, "err").get("text", "").contains("zu groß")), "Nachricht über 8 KB → err")
	for i in range(40):
		c1.send({"t": "lobby_ready", "ready": i % 2 == 0})
	pump(300)
	check(c1.state == "open" and int(host.server.stats().rate_dropped) > 0, "40 auf einmal: gedrosselt, Verbindung bleibt")
	check(inbox[c1].size() > before, "weiter Nachrichten")
	# Anmeldefrist: WebSocket ohne hello wird geschlossen
	host.hello_timeout_ms = 300
	var silent := WebSocketPeer.new()
	silent.connect_to_url("ws://127.0.0.1:%d/ws" % PORT)
	var end := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < end and silent.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		silent.poll()
		pump(5)
	check(silent.get_ready_state() == WebSocketPeer.STATE_CLOSED and silent.get_close_code() == NetWs.CLOSE_TIMEOUT, "ohne hello nach der Frist geschlossen (%d)" % silent.get_close_code())
	host.hello_timeout_ms = NetHostSession.HELLO_TIMEOUT_MS

func test_discovery() -> void:
	var d := NetDiscovery.new()
	d.auto_poll = false
	d.use_broadcast = false
	d.probe_local = true
	check(d.start_search(DISC) == OK, "Suche gestartet")
	var end := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < end and d.games_list().is_empty():
		d.poll()
		pump(5)
	var games := d.games_list()
	check(games.size() == 1, "ein Spiel gefunden")
	if games.size() == 1:
		var g: Dictionary = games[0]
		check(g.name == "Lena" and g.port == PORT and g.compatible and g.players == host.players.size(), "Name, Port, passend, Spielerzahl")
		check(g.address == "127.0.0.1" and g.age_ms < 1500 and g.version == NetProtocol.game_version() and not g.running, "Adresse, Alter, Version")
		check(g.sid == host.sid and g.addresses.has("127.0.0.1"), "Sitzungskennung und Adressen")
	d.manual = []
	d.stop()
	d.free()
	var info := http_info(PORT)
	check(info.get("game") == "mau-mau-flip" and int(info.get("players", 0)) == host.players.size() and int(info.get("port", 0)) == PORT, "/info mit Spielerzahl und Port")
	check(info.get("name") == "Lena" and info.get("version") == NetProtocol.game_version() and info.get("addresses") is Array, "/info mit Name, Version, Adressen")

func test_remove_and_bye() -> void:
	var id1 := c1.my_id
	host.remove_player(id1, "Tschüss Anna")
	check(wait_until(func(): return c1.state == "closed") and c1.close_text == "Tschüss Anna", "entfernter Spieler bekommt bye")
	check(not host.players.has(id1) and host.ordered_ids().map(func(i): return host.seat_of(i)) == [0, 1, 2], "Plätze rücken nach")
	var done := [false]
	host.finished.connect(func(): done[0] = true)
	host.finish("Spiel beendet – danke!")
	check(wait_until(func(): return c2.state == "closed" and c3.state == "closed", 3000), "bye an alle beim Beenden")
	check(wait_until(func(): return done[0] and host.server == null), "finish: Clients haben getrennt, Gastgeber geschlossen")
	check(c2.close_text == "Spiel beendet – danke!", "Text des Gastgebers")
	pump(500, true)
	check(c2.state == "closed" and c3.state == "closed", "nach bye kein Neuverbinden")

func test_host_restart() -> void:
	# Gastgeber verschwindet ohne bye (Absturz/Neustart): Client versucht es weiter und kommt nach dem Neustart wieder hinein.
	var h2 := new_host()
	h2.use_discovery = false
	check(h2.start("Neu", PORT2, PORT2) == OK, "zweiter Gastgeber auf %d" % PORT2)
	var c := new_client("Clara", PORT2)
	c.connect_timeout_ms = 1000
	check(wait_until(func(): return c.state == "open"), "Clara angenommen")
	h2.stop()
	check(wait_until(func(): return c.state == "connecting"), "Gastgeber weg → connecting")
	check(wait_until(func(): return c.attempts >= 2, 6000) and c.state == "connecting", "mehrere Versuche (%d)" % c.attempts)
	check(h2.start("Neu", PORT2, PORT2) == OK, "Gastgeber neu gestartet")
	check(wait_until(func(): return c.state == "open"), "Client wieder drin (als neuer Spieler: neue Sitzung)")
	check(h2.players.size() == 2, "Gastgeber plus Clara")
	h2.stop("Ende")

func test_host_stall() -> void:
	# Hauptschleife des Gastgebers steht (Server ohne Thread): Nach timeout_ms ohne Nachricht gilt die Verbindung als verloren; läuft der
	# Gastgeber wieder, kommt der Client mit Token als derselbe Spieler zurück.
	var h3 := new_host()
	h3.use_discovery = false
	check(h3.start("Stau", PORT3, PORT3, false) == OK, "Gastgeber ohne Thread auf %d" % PORT3)
	var c := new_client("Dora", PORT3)
	c.timeout_ms = 600
	check(wait_until(func(): return c.state == "open"), "Dora angenommen")
	var id := c.my_id
	rejoined.clear()
	check(wait_until(func(): return c.state == "connecting", 2500, true), "Gastgeber hängt → nach Zeitgrenze connecting")
	check(wait_until(func(): return c.state == "open" and rejoined.has(id)), "Gastgeber läuft wieder → derselbe Spieler")
	check(c.my_id == id and h3.players.size() == 2, "keine Doppelung")
