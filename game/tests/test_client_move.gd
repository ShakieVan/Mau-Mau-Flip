extends SceneTree

# Mau-Mau Flip (Beta 1.6.2, WLAN und Spiel-WLAN, docs/module/uebergabe.md Abschnitte 10.1, 10.4–10.7, 10.10, Testplan 10.16):
# NetClient und ClientTable des App-Gastes, synchron gepumpt, echte Sockets auf 127.0.0.1.
#  1  Umzug (echter Gastgeber, WLAN, TCP 24997/24998): Anna sitzt mit aktueller Sicherung am Tisch; der Gastgeber fällt aus →
#     host_lost_wall ab dem ersten gescheiterten Neuversuch (nicht beim Schließen der alten Verbindung, bleibt beim zweiten). Ein
#     zweiter Gastgeber setzt die Partie auf einem anderen Port fort; move_to behält Sicherung, head/head_gid und Token
#     (backup_current() bleibt wahr), sendet moved, der neue NetClient zählt von vorn; Anna landet per Token auf ihrem Platz.
#     follow_room zieht auf den Raum-Link (Port 0).
#  2  Begrüßung (Nachbau-Gastgeber, TCP 24999): Sicherung aus der Datei bei jeder Adresse (auch mit Raum älter als 24 h) – hello mit hp,
#     bk, bk_token, bk_gid und ap; ohne Sicherung bk = BK_NONE, ohne bk_token/bk_gid, ap ohne Quelle {false, false}; Lite (kind web)
#     ohne hp/ap/bk.
#  3  welcome assigned:true (seat_assign): App-Gast mit altem Token aus der Token-Datei – erst als Neuer angenommen, dann auf einen
#     Platz gesetzt: weder removed noch readmitted, das neue Token geht beim Neuverbinden hinaus. Gegenprobe ohne assigned: readmitted.
#  4  NetClient.drain (echter NetServer, TCP 24996): handover_ok nach 20 Füllnachrichten kommt an, obwohl direkt danach suspend() den
#     NetClient freigibt. Gegenprobe ohne drain wird nur protokolliert.

const PORT_A := 24997
const PORT_B := 24998
const PORT_F := 24999
const PORT_D := 24996
const PATH_H := "user://test_client_move_host.json"
const PATH_H2 := "user://test_client_move_host2.json"
const PATH_ANNA := "user://test_client_move_anna.json"
const PATH_C := "user://test_client_move_c.json"

var failures := 0
var checks := 0
var rng := RandomNumberGenerator.new()
var hosts: Array = []
var clients: Array = []
var nets: Array = []
var fake: FakeHost
var wall := 0


# Nachbau eines Gastgebers: nimmt WebSockets an, merkt sich jede Nachricht (JSON) je Verbindung, schickt auf Zuruf.
class FakeHost:
	extends RefCounted
	var tcp := TCPServer.new()
	var peers: Array = []          # WebSocketPeer
	var got: Array = []            # [{peer, msg}]

	func start(port: int) -> Error:
		return tcp.listen(port, "127.0.0.1")

	func stop() -> void:
		for p in peers:
			(p as WebSocketPeer).close()
		peers.clear()
		tcp.stop()

	func poll() -> void:
		while tcp.is_connection_available():
			var ws := WebSocketPeer.new()
			ws.accept_stream(tcp.take_connection())
			peers.append(ws)
		for i in peers.size():
			var ws: WebSocketPeer = peers[i]
			ws.poll()
			while ws.get_available_packet_count() > 0:
				var m = JSON.parse_string(ws.get_packet().get_string_from_utf8())
				if m is Dictionary:
					got.append({"peer": i, "msg": m})

	func send(i: int, msg: Dictionary) -> void:
		(peers[i] as WebSocketPeer).send_text(JSON.stringify(msg))

	func last(t: String) -> Dictionary:
		for i in range(got.size() - 1, -1, -1):
			if str(got[i].msg.get("t", "")) == t:
				return got[i]
		return {}

	func count(t: String) -> int:
		return got.filter(func(g): return str(g.msg.get("t", "")) == t).size()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)


func _initialize() -> void:
	rng.seed = 1662
	NetClient.ap_info_default = Callable()
	for p in [PATH_H, PATH_H2, PATH_ANNA, PATH_C]:
		TableSource.clear_saved(p)
	wall = int(Time.get_unix_time_from_system() * 1000.0)
	fake = FakeHost.new()
	check(fake.start(PORT_F) == OK, "Nachbau-Gastgeber auf %d" % PORT_F)
	var t0 := Time.get_ticks_msec()
	_move()
	_hello()
	_assigned()
	_drain()
	print("  Dauer %d ms" % (Time.get_ticks_msec() - t0))
	for c in clients:
		if is_instance_valid(c):
			c.suspend()
			c.free()
	for n in nets:
		if is_instance_valid(n):
			n.close()
			n.free()
	for h in hosts:
		if is_instance_valid(h):
			h.autosave = false
			h.leave()
			h.free()
	fake.stop()
	for p in [PATH_H, PATH_H2, PATH_ANNA, PATH_C]:
		TableSource.clear_saved(p)
	print("RESULT: %d ok" % checks if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)


# ---------- 1: Umzug ----------

func _move() -> void:
	var h := new_host(PATH_H)
	check(h.open("Hanna", PORT_A, PORT_A) == OK, "1: Gastgeberin auf %d" % PORT_A)
	var anna := new_client("Anna", PATH_ANNA)
	anna.clock = func() -> int: return wall
	anna.join("127.0.0.1", PORT_A, "Anna")
	check(wait_until(func(): return anna.my_id > 0), "1: Anna angenommen")
	h.add_bot("Minka")
	h.set_rules(RuleConfig.preset("offiziell"))
	check(h.start(99), "1: Start")
	check(wait_until(func(): return anna.view_rev > 0 and anna.backup_current()), "1: Anna hat Stand und aktuelle Sicherung")
	_play(h, [anna], 4)
	check(wait_until(func(): return anna.backup_current() and int(anna.head[2]) == h.seq), "1: Sicherung aktuell nach Zügen")
	var tok := anna.token
	var gid := str(anna.backup.gid)
	var head := anna.head.duplicate()
	var mark := MatchSnapshot.mark(anna.backup)
	var seat := _seat_of_token(h, tok)
	check(seat >= 0 and anna.backup_seat() == seat, "1: Annas Platz %d (Sicherung %d)" % [seat, anna.backup_seat()])
	check(anna.client.host_lost_wall == 0, "1: host_lost_wall 0, solange der Gastgeber antwortet")
	# Gastgeberin fällt aus (Freigeben ohne „Tisch verlassen“): Schließen der Verbindung zählt nicht, erst der Neuversuch
	anna.client.connect_timeout_ms = 1500
	var lost_at := wall + 100000
	wall = lost_at
	drop(h)
	check(wait_until(func(): return anna.client.host_lost_wall != 0, 6000), "1: host_lost_wall nach dem ersten gescheiterten Neuversuch")
	check(anna.client.host_lost_wall == lost_at, "1: host_lost_wall = Wanduhr des ersten Fehlschlags (%d)" % anna.client.host_lost_wall)
	var tries := anna.client.attempts
	wall = lost_at + 50000
	check(wait_until(func(): return anna.client.attempts > tries + 1, 8000), "1: weitere Neuversuche")
	check(anna.client.host_lost_wall == lost_at, "1: host_lost_wall bleibt beim ersten Fehlschlag")
	check(anna.backup_current(), "1: Sicherung bleibt aktuell (kein neues bk)")
	# Zweiter Gastgeber setzt die Partie auf einem anderen Port fort
	var h2 := new_host(PATH_H2)
	check(h2.resume(MatchSnapshot.read(PATH_H), -1, PORT_B, PORT_B) == OK, "1: Fortsetzen auf %d" % PORT_B)
	var moves: Array = []
	anna.moved.connect(func(a: String, p: int) -> void: moves.append([a, p]))
	var old_client := anna.client
	check(anna.move_to("127.0.0.1", PORT_B) == OK, "1: move_to")
	check(moves == [["127.0.0.1", PORT_B]], "1: Signal moved (%s)" % str(moves))
	check(anna.client != old_client and anna.client.welcomes == 0 and anna.client.last_host_wall == 0 \
		and anna.client.host_lost_wall == 0, "1: neuer NetClient zählt von vorn")
	check(not anna.backup.is_empty() and str(anna.backup.gid) == gid and MatchSnapshot.mark(anna.backup) == mark, "1: Sicherung bleibt")
	check(anna.head == head and anna.head_gid == gid, "1: head/head_gid bleiben")
	check(anna.backup_current(), "1: backup_current() bleibt wahr")
	check(anna.token == tok and anna.client.token == tok, "1: Platz-Token bleibt (auch im neuen NetClient)")
	check(anna.client.address == "127.0.0.1" and anna.client.port == PORT_B, "1: neue Adresse")
	check(anna.client.bk_token == tok and anna.client.bk_gid == gid, "1: hello trägt bk_token und bk_gid")
	var back := func() -> bool:
		var s := _seat_of_token(h2, tok)
		return anna.connection_state() == "open" and s >= 0 and bool(h2.game.connected[s])
	check(wait_until(back, 6000), "1: Anna beim neuen Gastgeber verbunden")
	check(_seat_of_token(h2, tok) == seat and anna.token == tok, "1: auf ihrem Platz, gleiches Token")
	check(not anna.was_removed() and not anna.client.readmitted, "1: weder herausgenommen noch neu aufgenommen")
	check(anna.client.welcomes == 1 and anna.client.host_lost_wall == 0, "1: eine Annahme beim neuen Gastgeber")
	check(wait_until(func(): return anna.backup_current() and int(anna.head[2]) == h2.seq, 4000), "1: neue Sicherung vom neuen Gastgeber")
	var rev := h2.rev
	_play(h2, [anna], 4)
	check(h2.rev > rev and wait_until(func(): return anna.last_rev == h2.rev), "1: Partie läuft weiter, Anna hat den Stand")
	# follow_room: dasselbe über den Raum-Link
	var bea := new_client("Bea", "user://test_client_move_bea.json")
	moves.clear()
	bea.moved.connect(func(a: String, p: int) -> void: moves.append([a, p]))
	bea.follow_room("http://127.0.0.1:1", "KATZE-42")
	var link := NetProtocol.room_link("http://127.0.0.1:1", "KATZE-42")
	check(moves == [[link, 0]] and bea.client.is_online() and bea.client.room == "KATZE-42", "1: follow_room zieht auf den Raum-Link (%s)" % str(moves))
	bea.suspend()
	TableSource.clear_saved("user://test_client_move_bea.json")


# ---------- 2: Begrüßung ----------

func _hello() -> void:
	var d := MatchSnapshot.read(PATH_ANNA)
	check(not d.is_empty() and str(d.role) == "guest", "2: Annas Datei (role guest)")
	if d.is_empty():
		return
	# Raum älter als 24 h: beim Beitritt zählt das Raumalter nicht (resumable(…, true))
	var now := int(Time.get_unix_time_from_system())
	d["online"] = {"relay": "https://vermittler.example", "room": "ALT-11", "token": "ab", "conns": [], "max_c": 0,
		"created_unix": now - 2 * 86400}
	check(MatchSnapshot.write(PATH_C, d), "2: Datei mit altem Raum")
	var file := MatchSnapshot.read(PATH_C)
	check(not MatchSnapshot.resumable(file, now) and MatchSnapshot.resumable(file, now, true), "2: Raum abgelaufen, Partie fortsetzbar")
	var c := new_client("Anna", PATH_C)
	c.listen_port = 24991
	c.ap_info = func() -> Dictionary: return {"ok": true, "perm": true}
	var n0 := fake.got.size()
	c.join("127.0.0.1", PORT_F, "Anna")
	check(wait_fake(func(): return fake.got.size() > n0 and str(fake.got[-1].msg.t) == "hello"), "2: hello beim Nachbau")
	var hello: Dictionary = fake.last("hello").get("msg", {})
	check(int(hello.get("hp", 0)) == 24991, "2: hp = listen_port (%s)" % str(hello.get("hp")))
	check(NetProtocol.clean_bk_mark(hello.get("bk")) == MatchSnapshot.mark(file), "2: bk = Marke der Sicherung (%s)" % str(hello.get("bk")))
	check(str(hello.get("bk_token", "")) == MatchSnapshot.own_token(file) and str(hello.get("bk_token", "")) != "", "2: bk_token = eigener Platz")
	check(str(hello.get("bk_gid", "")) == str(file.gid), "2: bk_gid = gid der Sicherung")
	check(hello.get("ap") is Dictionary and hello.ap.get("ok") == true and hello.ap.get("perm") == true, "2: ap aus ap_info (%s)" % str(hello.get("ap")))
	var clean := NetProtocol.clean_client_message(NetProtocol.decode(JSON.stringify(hello)))
	check(int(clean.get("hp", 0)) == 24991 and str(clean.get("bk_gid", "")) == str(file.gid) and clean.get("ap") is Dictionary, "2: Gastgeber übernimmt hp, bk_gid, ap")
	c.suspend()
	# Ohne Sicherung
	var e := new_client("Ben", "user://test_client_move_leer.json")
	TableSource.clear_saved("user://test_client_move_leer.json")
	n0 = fake.got.size()
	e.join("127.0.0.1", PORT_F, "Ben")
	check(wait_fake(func(): return fake.got.size() > n0 and str(fake.got[-1].msg.t) == "hello"), "2: hello ohne Sicherung")
	hello = fake.last("hello").get("msg", {})
	check(NetProtocol.clean_bk_mark(hello.get("bk")) == NetProtocol.BK_NONE and not hello.has("bk_token") and not hello.has("bk_gid"), "2: ohne Sicherung: BK_NONE, kein bk_token/bk_gid")
	check(int(hello.get("hp", 0)) == NetProtocol.PORT, "2: hp Standard %d" % NetProtocol.PORT)
	check(hello.get("ap") is Dictionary and hello.ap.get("ok") == false and hello.ap.get("perm") == false, "2: ap ohne Quelle {false, false}")
	e.suspend()
	# Standardquelle aus app/ (NetClient.ap_info_default)
	NetClient.ap_info_default = func() -> Dictionary: return {"ok": true, "perm": false}
	var nd := NetClient.new()
	nd.kind = "app"
	check(nd.ap_state() == {"ok": true, "perm": false}, "2: ap_info_default gilt ohne eigene Quelle")
	nd.ap_info = func(): return "kaputt"
	check(nd.ap_state() == {"ok": false, "perm": false}, "2: kaputte Quelle → {false, false}")
	nd.free()
	# Gegenprüfung 1.6.2: App setzt die Standardquelle (NetAndroid.install_net_hooks) – hello.ap ohne eigene Quelle aus NetAndroid
	NetAndroid.install_net_hooks()
	check(NetClient.ap_info_default.is_valid(), "2: install_net_hooks setzt ap_info_default")
	var saved_stub = NetAndroid.wifi_stub
	for st in [[{"sdk": 34, "granted": true}, {"ok": true, "perm": true}], [{"sdk": 31, "granted": false}, {"ok": true, "perm": false}],
			[{"sdk": 25, "granted": true}, {"ok": false, "perm": false}]]:
		NetAndroid.wifi_stub = st[0]
		var na := new_client("Nora", "user://test_client_move_leer.json")
		TableSource.clear_saved("user://test_client_move_leer.json")
		n0 = fake.got.size()
		na.join("127.0.0.1", PORT_F, "Nora")
		check(wait_fake(func(): return fake.got.size() > n0 and str(fake.got[-1].msg.t) == "hello"), "2: hello ohne eigene Quelle (%s)" % str(st[0]))
		hello = fake.last("hello").get("msg", {})
		check(hello.get("ap") is Dictionary and hello.ap.get("ok") == st[1].ok and hello.ap.get("perm") == st[1].perm,
			"2: hello.ap aus NetAndroid (%s → %s)" % [str(st[0]), str(hello.get("ap"))])
		na.suspend()
	NetAndroid.wifi_stub = saved_stub
	NetClient.ap_info_default = Callable()
	# Lite (kind web): nichts davon
	var w := new_net()
	n0 = fake.got.size()
	w.connect_to("127.0.0.1", PORT_F, "Lisa", "web")
	check(wait_fake(func(): return fake.got.size() > n0 and str(fake.got[-1].msg.t) == "hello"), "2: hello von Lite")
	hello = fake.last("hello").get("msg", {})
	check(not hello.has("hp") and not hello.has("ap") and not hello.has("bk") and not hello.has("bk_gid"), "2: Lite ohne hp/ap/bk (%s)" % str(hello.keys()))
	w.close()
	pump(50)


# ---------- 3: welcome assigned ----------

func _assigned() -> void:
	var n := new_net()
	var n0 := fake.got.size()
	var p0 := fake.peers.size()
	n.connect_to("127.0.0.1", PORT_F, "Wanda", "app")
	n.token = "0a1d"                  # altes Token aus der Token-Datei für dieselbe ip:port
	check(wait_fake(func(): return fake.got.size() > n0 and str(fake.got[-1].msg.t) == "hello"), "3: hello")
	var g: Dictionary = fake.got[-1]
	check(str(g.msg.get("token", "")) == "0a1d", "3: altes Token geht mit")
	var i := int(g.peer)
	check(i >= p0, "3: neue Verbindung")
	fake.send(i, {"t": "welcome", "id": 7, "token": "aa11", "host_name": "Hanna"})      # unbekannt: als Neue (Warteliste)
	check(wait_fake(func(): return n.my_id == 7), "3: als Neue angenommen")
	check(not n.removed and not n.readmitted, "3: erste Annahme ist kein Herausnehmen")
	fake.send(i, {"t": "welcome", "id": 2, "token": "bb22", "host_name": "Hanna", "assigned": true, "gid": "abcd", "gen": 2, "epoch": "e1"})
	check(wait_fake(func(): return n.my_id == 2), "3: zweites welcome (assigned)")
	check(not n.removed and not n.readmitted, "3: assigned: weder removed noch readmitted")
	check(n.token == "bb22" and n.welcomes == 2 and str(n.welcome_info.get("gid", "")) == "abcd", "3: neues Token und gid")
	# Neuverbinden: das zugewiesene Token geht hinaus und gilt als bekannt
	n0 = fake.got.size()
	n.reconnect_now()
	check(wait_fake(func(): return fake.got.size() > n0 and str(fake.got[-1].msg.t) == "hello"), "3: neues hello nach reconnect_now")
	g = fake.got[-1]
	check(str(g.msg.get("token", "")) == "bb22", "3: hello mit dem zugewiesenen Token")
	fake.send(int(g.peer), {"t": "welcome", "id": 2, "token": "bb22", "host_name": "Hanna"})
	check(wait_fake(func(): return n.welcomes == 3), "3: wieder angenommen")
	check(not n.removed and not n.readmitted, "3: gleiches Token: alles gut")
	# Gegenprobe: neues Token ohne assigned = herausgenommen und neu aufgenommen
	n0 = fake.got.size()
	n.reconnect_now()
	check(wait_fake(func(): return fake.got.size() > n0 and str(fake.got[-1].msg.t) == "hello"), "3: hello (Gegenprobe)")
	fake.send(int(fake.got[-1].peer), {"t": "welcome", "id": 9, "token": "cc33", "host_name": "Hanna"})
	check(wait_fake(func(): return n.welcomes == 4), "3: Annahme (Gegenprobe)")
	check(n.readmitted and n.removed, "3: ohne assigned: readmitted wie bisher")
	n.close()
	pump(50)


# ---------- 4: drain ----------

# Empfänger ist ein echter NetServer (eigenes WebSocket, Netz-Thread) – wie beim alten Gastgeber, der auf handover_ok wartet.
func _drain() -> void:
	var srv := NetServer.new()
	srv.threaded = true
	srv.auto_poll = false
	srv.web_zip_path = ""
	srv.max_rate = 1000
	var got: Array = []          # [conn, msg]
	srv.ws_message.connect(func(conn: int, text: String) -> void:
		var m := NetProtocol.decode(text)
		got.append([conn, m])
		if str(m.get("t", "")) == "hello":
			srv.send_text(conn, NetProtocol.encode({"t": "welcome", "id": 3, "token": "dd44", "host_name": "Hanna"})))
	check(srv.start(PORT_D, PORT_D, "127.0.0.1") == OK, "4: NetServer auf %d" % PORT_D)
	var results := {}
	for with_drain in [true, false]:
		var c := new_client("Dora", "user://test_client_move_dora.json")
		c.backups = false
		c.join("127.0.0.1", PORT_D, "Dora")
		var opened := func() -> bool:
			srv.poll()
			return c.connection_state() == "open"
		check(wait_until(opened), "4: Dora angenommen (drain %s)" % str(with_drain))
		var conn := -1
		for g in got:
			if str(g[1].get("t", "")) == "hello":
				conn = int(g[0])
		var pad := "x".repeat(2000)
		for k in 20:
			c.client.send({"t": "fill", "k": k, "pad": pad})
		if with_drain:
			check(c.send_and_drain({"t": "handover_ok", "port": 24995, "qr": false}), "4: send_and_drain meldet: alles hinaus")
		else:
			c.client.send({"t": "handover_ok", "port": 24995, "qr": false})
		c.suspend()
		check(c.client == null, "4: suspend gibt den NetClient frei")
		var end := Time.get_ticks_msec() + 800
		while Time.get_ticks_msec() < end:
			srv.poll()
			OS.delay_msec(2)
		var mine := got.filter(func(g): return int(g[0]) == conn)
		var ho := mine.filter(func(g): return str(g[1].get("t", "")) == "handover_ok")
		results[with_drain] = not ho.is_empty()
		if with_drain:
			check(ho.size() == 1 and int(ho[0][1].get("port", 0)) == 24995 and ho[0][1].get("qr") == false, "4: handover_ok kommt trotz suspend() an")
			var fills := mine.filter(func(g): return str(g[1].get("t", "")) == "fill").size()
			check(fills == 20 and str(mine[-1][1].get("t", "")) == "handover_ok", "4: Füllnachrichten (%d) davor, handover_ok zuletzt" % fills)
		TableSource.clear_saved("user://test_client_move_dora.json")
	print("  Gegenprobe ohne drain: handover_ok %s" % ("angekommen" if results.get(false, false) else "verloren"))
	srv.stop()
	srv.free()


# ---------- Hilfen ----------

func new_host(path: String) -> HostTable:
	var h := HostTable.new()
	h.auto_process = false
	h.speed = 0.0
	h.use_discovery = false
	h.save_path = path
	hosts.append(h)
	return h


func drop(h: HostTable) -> void:
	hosts.erase(h)
	h.free()


func new_client(_player_name: String, path: String) -> ClientTable:
	var c := ClientTable.new()
	c.auto_process = false
	c.reuse_token = false
	c.persist_tokens = false
	c.retry_ms = [100, 200, 300]
	c.ping_ms = 300
	c.backups = true
	c.persist_backup = true
	c.backup_path = path
	clients.append(c)
	return c


func new_net() -> NetClient:
	var n := NetClient.new()
	n.auto_poll = false
	n.auto_reconnect = true
	n.reuse_token = false
	n.persist_tokens = false
	n.retry_ms = [100, 200]
	nets.append(n)
	return n


func _seat_of_token(h: HostTable, t: String) -> int:
	for s in h.seats.size():
		if str(h.seats[s].get("token", "")) == t:
			return s
	return -1


func _play(h: HostTable, cts: Array, moves: int) -> void:
	var done := 0
	var end := Time.get_ticks_msec() + 6000
	while done < moves and Time.get_ticks_msec() < end:
		pump(5)
		if h.game == null or h.game.phase() in ["round_over", "game_over"]:
			break
		for t in [h] + cts:
			if t is ClientTable and (t.client == null or t.connection_state() != "open"):
				continue
			var v: Dictionary = t.current_view()
			if v.is_empty():
				continue
			var a := MauBot.choose(v, rng.randi(), 1)
			if not a.is_empty() and str(a.get("a", "")) != "next_round":
				var before := h.rev
				t.act(a)
				pump(5)
				if h.rev != before:
					done += 1


func step() -> void:
	fake.poll()
	for h in hosts:
		if is_instance_valid(h):
			h.pump()
	for c in clients:
		if is_instance_valid(c) and c.client != null:
			c.pump()
	for n in nets:
		if is_instance_valid(n):
			n.poll()


func pump(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while true:
		step()
		if Time.get_ticks_msec() >= end:
			break
		OS.delay_msec(1)


func wait_until(cond: Callable, ms := 4000) -> bool:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		pump(2)
		if cond.call():
			return true
	return cond.call()


func wait_fake(cond: Callable, ms := 3000) -> bool:
	return wait_until(cond, ms)
