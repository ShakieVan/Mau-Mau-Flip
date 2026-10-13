extends SceneTree

# Mau-Mau Flip (Beta 1.6.1, Gastgeber-Übergabe): Vermittler-Bausteine aus docs/module/uebergabe.md Abschnitt 3 und 3.5 über den
# Vermittler-Nachbau (NetRelayDouble, TCP 24961) im selben Prozess, synchron gepumpt. Gäste sind rohe WebSockets („Lite-artig“: sie
# melden sich an und senden sonst nichts), damit Close-Codes und Rahmen genau sichtbar sind.
#  1  Raum nicht versehentlich beenden: NetRelayHost.close() und Freigeben (PREDELETE) ohne {k:"end"}, close(true) mit;
#     NetHostSession.stop() ohne, stop(text, true) mit; HostTable.leave() beendet den Raum.
#  2  open_existing: 4012 an die bekannten c, 4012-Rundumschlag an eine Lite-Verbindung, die sich beim still toten Vorgänger
#     angemeldet hat (höchstens 150 Rahmen je Frame, genau max + 256 ohne die bekannten), created_unix bleibt.
#  3  Rundumschlag endet vor der ersten neuen c (neuer Gast wird nicht gekickt); msg von unbekannter c → 4012.
#  4  Code 4000: zuerst replaced, dann stepped_down, kein ws_closed, kein Neuverbinden, Abtreten beendet den Raum nicht.
#  5  Vorsichtiges Neuverbinden: /info host:false → anmelden; host:true → check + needs_check (nie blind), claim(); ohne Empfänger
#     sofort anmelden; /info nicht erreichbar → weiter warten; Raum weg → failed 4404; falsches Token → 4403.
#  6  Sitzung: hello.bk/bk_token (nur App), welcome mit gid/gen/epoch, restore_player (auch Warteliste), send_many, online_room,
#     open_online_existing (verdrängt die alte Sitzung: replaced an die Spielsteuerung, niemand getrennt; ohne Empfänger wie bis 1.6.0),
#     „wieder da“ erst nach dem Neuverbinden.

const RELAY_PORT := 24961
const HOST_PORT := 24962
const TABLE_PORT := 24963
const HOST2_PORT := 24964
const HOST3_PORT := 24965
const FAKE_UNIX := 1800000000
const BASE := NetProtocol.RELAY_CONN_BASE

var failures := 0
var checks := 0
var relay: NetRelayDouble
var base := ""
var nodes: Array = []          # wird von pump() abgefragt (NetRelayHost, NetHostSession, HostTable)
var all_nodes: Array = []      # zum Freigeben am Ende
var guests: Array = []
var keep: Array = []           # halboffene Gastgeber-Sockets (bleiben beim Vermittler angemeldet)


class RawGuest:
	extends RefCounted
	var ws := WebSocketPeer.new()
	var inbox: Array = []
	var code := -1
	var hello := {}
	var _sent := false

	func _init(url: String, hello_msg: Dictionary) -> void:
		hello = hello_msg
		ws.connect_to_url(url)

	func poll() -> void:
		if code >= 0:
			return
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN and not _sent:
			_sent = true
			if not hello.is_empty():
				ws.send_text(JSON.stringify(hello))
		while ws.get_available_packet_count() > 0:
			var t := ws.get_packet().get_string_from_utf8()
			var d = JSON.parse_string(t)
			inbox.append(d if d is Dictionary else {"raw": t})
		if st == WebSocketPeer.STATE_CLOSED:
			code = ws.get_close_code()

	func is_open() -> bool:
		return code < 0 and ws.get_ready_state() == WebSocketPeer.STATE_OPEN

	func send(text: String) -> void:
		ws.send_text(text)

	func last(t: String) -> Dictionary:
		for i in range(inbox.size() - 1, -1, -1):
			if inbox[i].get("t") == t:
				return inbox[i]
		return {}


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)


func _initialize() -> void:
	relay = NetRelayDouble.new()
	relay.auto_poll = false
	relay.web_zip_path = ""
	check(relay.start(RELAY_PORT, RELAY_PORT) == OK, "Vermittler-Nachbau auf %d" % RELAY_PORT)
	base = relay.base_url()
	var t0 := Time.get_ticks_msec()
	_constants()
	_end_room()
	_takeover_sweep()
	_sweep_stops_and_unknown()
	_careful()
	_session()
	print("  Dauer %d ms" % (Time.get_ticks_msec() - t0))
	for g in guests:
		g.ws.close()
	for k in keep:
		k.close()
	keep.clear()
	for n in all_nodes:
		if is_instance_valid(n):
			if n is HostTable:
				n.leave()
			n.free()
	relay.stop()
	relay.free()
	print("RESULT: %d ok" % checks if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)


func _constants() -> void:
	check(NetProtocol.BACKUP_ALIVE_MS == 15000 and NetProtocol.T_SILENT_MS == 40000 and NetProtocol.T_AWAY_MS == 180000,
		"Wartezeiten wie im Entwurf: alive 15 s, T_SILENT 40 s, T_AWAY 180 s")
	check(NetProtocol.SWEEP_EXTRA == 256 and NetProtocol.SWEEP_PER_FRAME == 150 and NetProtocol.SWEEP_BUDGET <= 200,
		"Rundumschlag: max + 256, höchstens 150 je Frame, Budget unter dem Eimer des Nachbaus")


# ---------- 1. Raum nicht versehentlich beenden ----------

func _end_room() -> void:
	var h1 := new_host()
	h1.open(base)
	check(wait(func(): return h1.state == "open"), "1: Raum offen (%s %s)" % [h1.state, h1.error])
	var c1 := h1.room
	h1.close()
	pump(150)
	check(relay.core.rooms.has(c1) and int(relay.core.rooms[c1].host) < 0, "1: close() ohne end – Raum bleibt (Gastgeber weg)")
	var h2 := new_host()
	h2.open(base)
	check(wait(func(): return h2.state == "open"), "1: zweiter Raum offen")
	var c2 := h2.room
	drop(h2)
	h2.free()
	pump(150)
	check(relay.core.rooms.has(c2), "1: Freigeben (PREDELETE) schickt kein end – Raum bleibt")
	var h3 := new_host()
	h3.open(base)
	check(wait(func(): return h3.state == "open"), "1: dritter Raum offen")
	var c3 := h3.room
	h3.close(true)
	check(wait(func(): return not relay.core.rooms.has(c3)), "1: close(true) beendet den Raum")
	# Sitzung
	var s := new_session(HOST_PORT)
	s.open_online(base)
	check(wait(func(): return s.online_state() == "open"), "1: Sitzung online")
	var c4 := str(s.online_info().get("room", ""))
	s.stop()
	pump(150)
	check(relay.core.rooms.has(c4), "1: NetHostSession.stop() ohne end – Raum bleibt")
	check(s.start("Lena", HOST_PORT, HOST_PORT, false) == OK, "1: Sitzung neu")
	s.open_online(base)
	check(wait(func(): return s.online_state() == "open"), "1: Sitzung wieder online")
	var c5 := str(s.online_info().get("room", ""))
	s.stop("Tschüss", true)
	check(wait(func(): return not relay.core.rooms.has(c5)), "1: stop(text, true) beendet den Raum")
	drop(s)
	s.free()
	# HostTable.leave(): ausdrückliches Ende
	var ht := HostTable.new()
	ht.auto_process = false
	ht.autosave = false
	ht.speed = 0.0
	ht.use_discovery = false
	ht.threaded = false
	nodes.append(ht)
	all_nodes.append(ht)
	check(ht.open("Gastgeberin", TABLE_PORT, TABLE_PORT) == OK, "1: HostTable offen")
	ht.session.open_online(base)
	check(wait(func(): return ht.session.online_state() == "open"), "1: HostTable online")
	var c6 := str(ht.session.online_info().get("room", ""))
	drop(ht)
	ht.leave()
	check(wait(func(): return not relay.core.rooms.has(c6)), "1: HostTable.leave() beendet den Raum")


# ---------- 2. Bestehenden Raum übernehmen, 4012-Rundumschlag ----------

func _takeover_sweep() -> void:
	var a := new_host()
	a.clock = func() -> int: return FAKE_UNIX
	a.open(base)
	check(wait(func(): return a.state == "open"), "2: Raum von A offen")
	check(a.created_unix == FAKE_UNIX, "2: created_unix beim Anlegen (eingespritzte Wanduhr: %d)" % a.created_unix)
	var code := a.room
	var tok := a.token
	var g1 := raw(code)
	var g2 := raw(code)
	check(wait(func(): return a.stats().ws_active == 2), "2: zwei Gäste bei A")
	g1.send("hallo")
	pump(100)
	check(a.max_c == 2, "2: max_c = 2 (%d)" % a.max_c)
	# A stirbt still: Socket hängt beim Vermittler, A wird nicht mehr abgefragt
	check(relay.hang_host(code) >= 0, "2: Socket von A hängt")
	drop(a)
	var g3 := raw(code)                  # Lite meldet sich beim still toten A an (c = 3) und sendet danach nichts
	check(wait(func(): return (relay.core.rooms[code].guests as Dictionary).size() == 3), "2: Lite-Gast mit neuer c beim Vermittler")
	pump(100)
	check(g3.is_open(), "2: Lite-Gast hängt ohne Antwort")
	var b := new_host()
	b.clock = func() -> int: return FAKE_UNIX + 3600
	b.resync_grace_ms = 400
	var states := []
	b.state_changed.connect(func(st: String) -> void: states.append(st))
	var closed := []
	b.ws_closed.connect(func(conn: int, _c: int, _r: String) -> void: closed.append(conn))
	check(b.open_existing(base, code.to_lower().replace("-", " "), tok, [1, 2], a.max_c, a.created_unix) == OK, "2: open_existing")
	check(wait(func(): return b.state == "open"), "2: B führt den Raum (%s %s)" % [b.state, b.error])
	check(states == ["connecting", "open"], "2: ohne /info direkt angemeldet (%s)" % str(states))
	check(b.room == code and b.link.ends_with("?r=" + code), "2: derselbe Raumcode")
	check(wait(func(): return g1.code == NetProtocol.CLOSE_RESYNC and g2.code == NetProtocol.CLOSE_RESYNC), "2: bekannte c bekommen 4012 (%d/%d)" % [g1.code, g2.code])
	check(wait(func(): return g3.code == NetProtocol.CLOSE_RESYNC, 3000), "2: Rundumschlag holt den Lite-Gast (4012, %d)" % g3.code)
	check(wait(func(): return not b.sweeping(), 3000), "2: Rundumschlag fertig")
	var st := b.stats()
	check(int(st.sweep_kicks) == 256, "2: Rundumschlag c 1 … 258 ohne die bekannten = 256 Rahmen (%d)" % int(st.sweep_kicks))
	check(int(st.sweep_max_frame) > 0 and int(st.sweep_max_frame) <= 150, "2: höchstens 150 je Frame (%d)" % int(st.sweep_max_frame))
	check(b.created_unix == FAKE_UNIX and b.max_c >= 3, "2: created_unix bleibt, max_c %d" % b.max_c)
	check(wait(func(): return closed.has(BASE + 1) and closed.has(BASE + 2)), "2: nicht zurückgekehrte Gäste gelten nach der Frist als getrennt")
	check(b.state == "open" and relay.core.rooms.has(code), "2: Raum besteht weiter")
	drop(b)
	b.close()


# ---------- 3. Rundumschlag endet vor neuen c; unbekannte c ----------

func _sweep_stops_and_unknown() -> void:
	var a := new_host()
	a.open(base)
	check(wait(func(): return a.state == "open"), "3: Raum offen")
	var code := a.room
	var g1 := raw(code)
	check(wait(func(): return a.stats().ws_active == 1), "3: Gast bei A")
	relay.hang_host(code)
	drop(a)
	var b := new_host()
	b.sweep_per_frame = 0                # Rundumschlag angehalten, bis ein neuer Gast da ist
	b.open_existing(base, code, a.token, [1], 1, 0)
	check(wait(func(): return b.state == "open" and g1.code == NetProtocol.CLOSE_RESYNC), "3: B führt, alte c 4012")
	check(b.sweeping(), "3: Rundumschlag läuft")
	var g5 := raw(code)                  # neu: c = 2
	check(wait(func(): return b.stats().ws_active >= 1 and b._guests.has(BASE + 2)), "3: neuer Gast bei B (c 2)")
	check(b._sweep_end == 1, "3: Rundumschlag endet vor der neuen c (%d)" % b._sweep_end)
	b.sweep_per_frame = 150
	check(wait(func(): return not b.sweeping()), "3: Rundumschlag fertig")
	pump(150)
	check(g5.is_open() and int(b.stats().sweep_kicks) == 0, "3: neuer Gast nicht gekickt (%d Rahmen)" % int(b.stats().sweep_kicks))
	# msg von einer unbekannten c → 4012 statt still verwerfen
	b._guests.erase(BASE + 2)
	g5.send("{\"t\":\"ping\",\"ts\":1}")
	check(wait(func(): return g5.code == NetProtocol.CLOSE_RESYNC), "3: Nachricht von unbekannter c → 4012 (%d)" % g5.code)
	check(int(b.stats().unknown_kicks) == 1, "3: ein Kick für die unbekannte c")
	# ---------- 4. Code 4000: abtreten
	var g6 := raw(code)
	check(wait(func(): return b._guests.size() == 1), "4: Gast bei B")
	var order := []
	b.replaced.connect(func() -> void: order.append("replaced"))
	b.ws_closed.connect(func(_c: int, _code: int, _r: String) -> void: order.append("closed"))
	b.state_changed.connect(func(s: String) -> void: order.append("state:" + s))
	var guests_before := b._guests.duplicate()
	b.retry_ms = [50]
	var d := new_host()
	d.open_existing(base, code, b.token, [], b.max_c, b.created_unix)
	check(wait(func(): return b.state == "stepped_down" and d.state == "open"), "4: D führt, B tritt ab (%s/%s)" % [b.state, d.state])
	check(order.size() >= 2 and order[0] == "replaced" and order[1] == "state:stepped_down", "4: zuerst replaced, dann stepped_down (%s)" % str(order))
	check(not order.has("closed") and b._guests == guests_before, "4: kein ws_closed, Gäste-Liste unberührt")
	check(b.close_code == NetWs.CLOSE_REPLACED and b.error.contains("anderen Gerät"), "4: Code 4000, Text (%s)" % b.error)
	pump(300)
	check(b.state == "stepped_down" and b._ws == null and b._retry_at < 0, "4: kein Neuverbinden nach 4000")
	check(wait(func(): return g6.code == NetProtocol.CLOSE_RESYNC), "4: D holt den Gast per Rundumschlag (%d)" % g6.code)
	drop(b)
	b.close()
	pump(150)
	check(relay.core.rooms.has(code) and int(relay.core.rooms[code].host) >= 0, "4: Abtreten beendet den Raum nicht, D bleibt Gastgeber")
	drop(d)
	d.close()


# ---------- 5. Vorsichtiges Neuverbinden ----------

func _careful() -> void:
	# a) host:false → sofort anmelden
	var f := new_host()
	f.retry_ms = [100000]
	var asked := []
	f.needs_check.connect(func(i: Dictionary) -> void: asked.append(i))
	f.open(base)
	check(wait(func(): return f.state == "open"), "5a: Raum offen")
	var code := f.room
	check(f.stats().info_checks == 0, "5a: neuer Raum ohne /info")
	f._ws.close()
	f._ws = null
	f._lost("Test")
	check(f.state == "away", "5a: Vermittler weg")
	check(wait(func(): return int(relay.core.rooms[code].host) < 0), "5a: Vermittler hat den Gastgeber verloren")
	f.check_now()                        # Rückkehr in die App: Neuversuch sofort (über /info)
	check(wait(func(): return f.state == "open"), "5a: wieder offen (%s)" % f.state)
	check(int(f.stats().info_checks) == 1 and asked.is_empty(), "5a: /info host:false → angemeldet, keine Probe")
	# b) host:true → check, nie blind; erst claim() meldet an. Wanduhr „10 min später“, Monotonuhr nur Sekunden.
	relay.hang_host(code)
	keep.append(f._ws)                   # das eigene halboffene Socket bleibt beim Vermittler angemeldet
	f._ws = null
	f._lost("Test")
	f.clock = func() -> int: return int(Time.get_unix_time_from_system()) + 600
	f.check_now()
	check(wait(func(): return f.state == "check"), "5b: /info host:true → check (%s)" % f.state)
	check(asked.size() == 1 and str(asked[0].get("room", "")) == code, "5b: needs_check mit Raum (%s)" % str(asked))
	check(int(f.stats().info_checks) == 2, "5b: jede Neuverbindung fragt /info (auch nach „Tiefschlaf“)")
	pump(300)
	check(f.state == "check" and f._ws == null, "5b: ohne Entscheidung nie blind als Gastgeber")
	f.check_now()
	pump(50)
	check(f.state == "check", "5b: check_now ändert nichts")
	f.claim()
	check(wait(func(): return f.state == "open"), "5b: claim() → wieder Gastgeber (%s)" % f.state)
	check(f.room == code, "5b: derselbe Raum")
	# c) ohne Empfänger von needs_check: sofort anmelden (Verhalten bis 1.6.0)
	var g := new_host()
	g.retry_ms = [100000]
	g.open(base)
	check(wait(func(): return g.state == "open"), "5c: Raum offen")
	var gcode := g.room
	relay.hang_host(gcode)
	keep.append(g._ws)
	g._ws = null
	g._lost("Test")
	var gstates := []
	g.state_changed.connect(func(s: String) -> void: gstates.append(s))
	g.check_now()
	check(wait(func(): return g.state == "open"), "5c: wieder offen")
	check(not gstates.has("check") and int(g.stats().info_checks) == 1, "5c: ohne Empfänger kein check (%s)" % str(gstates))
	# c2) hängendes Socket nach der Stille-Frist: bleibt liegen, bis die neue Anmeldung es ersetzt → Gäste 4012 statt 4503
	var k := new_host()
	k.retry_ms = [100000]
	k.open(base)
	check(wait(func(): return k.state == "open"), "5c2: Raum offen")
	var kcode := k.room
	var gx := raw(kcode)
	check(wait(func(): return k.stats().ws_active == 1), "5c2: Gast da")
	relay.hang_host(kcode)
	k._lost("Vermittler antwortet nicht.")
	check(k._stale_ws != null and k._ws == null and k.state == "away", "5c2: hängendes Socket bleibt bis zur neuen Anmeldung liegen")
	k.check_now()
	check(wait(func(): return k.state == "open" and gx.code >= 0), "5c2: wieder offen")
	check(gx.code == NetProtocol.CLOSE_RESYNC and k._stale_ws == null, "5c2: Gast bekommt 4012 statt 4503 (%d), altes Socket zu" % gx.code)
	drop(k)
	k.close()
	# d) /info nicht erreichbar → weiter warten, nie als Gastgeber anmelden
	var h := new_host()
	h.retry_ms = [30]
	h.info_timeout_ms = 200
	h.relay_url = "http://127.0.0.1:1"
	h.room = gcode
	h.token = "abc"
	h._set_state("away")
	h._retry_at = 0
	var ws_seen := [false]
	pump_until(func():
		if h._ws != null:
			ws_seen[0] = true
		return int(h.stats().info_checks) >= 2, 4000)
	check(int(h.stats().info_checks) >= 2 and h.state == "away" and not ws_seen[0], "5d: /info nicht erreichbar → weiter warten (%d Versuche, %s)" % [int(h.stats().info_checks), h.state])
	drop(h)
	h.close()
	# e) Raum unbekannt → failed (4404)
	var gone := "MOND-11"
	for n in range(11, 99):
		gone = "MOND-%d" % n
		if not relay.core.rooms.has(gone):
			break
	var e := new_host()
	e.relay_url = base
	e.room = gone
	e.token = "abc"
	e._set_state("away")
	e._retry_at = 0
	check(wait(func(): return e.state == "failed"), "5e: Raum weg → failed (%s)" % e.state)
	check(e.close_code == NetProtocol.CLOSE_ROOM_UNKNOWN and e.room == "", "5e: Code 4404, Raum vergessen")
	# f) open_existing mit falschem Token → 4403
	var w := new_host()
	w.open_existing(base, gcode, "falsch", [], 0, 0)
	check(wait(func(): return w.state == "failed"), "5f: falsches Token → failed")
	check(w.close_code == NetProtocol.CLOSE_BAD_TOKEN, "5f: Code 4403 (%d)" % w.close_code)
	check(int(relay.core.rooms[gcode].host) >= 0, "5f: der echte Gastgeber bleibt")
	for n in [f, g, e, w]:
		drop(n)
		n.close()


# ---------- 6. Sitzung ----------

func _session() -> void:
	var s := new_session(HOST_PORT)
	var replaced_n := [0]
	s.replaced.connect(func() -> void: replaced_n[0] += 1)
	var left := []
	s.player_left.connect(func(id: int) -> void: left.append(id))
	s.open_online(base)
	s.relay.clock = func() -> int: return FAKE_UNIX
	check(wait(func(): return s.online_state() == "open"), "6: Sitzung online")
	var code := str(s.online_info().get("room", ""))
	s.welcome_extra = {"gid": "0011223344556677", "gen": 2, "epoch": "a1b2c3d4", "fremd": 1}
	var mark := [1, "a1b2c3d4", 7]
	var gk := raw(code, NetProtocol.make_hello("Kim", "app", "", "", mark))
	check(wait(func(): return not gk.last("welcome").is_empty()), "6: App-Gast mit bk angenommen")
	var gw := raw(code, NetProtocol.make_hello("Web", "web", "", "", mark))
	check(wait(func(): return not gw.last("welcome").is_empty()), "6: Browser angenommen")
	var ga := raw(code, NetProtocol.make_hello("Alt", "app"))
	check(wait(func(): return not ga.last("welcome").is_empty()), "6: App ohne bk angenommen")
	var wk := gk.last("welcome")
	check(str(wk.get("gid")) == "0011223344556677" and int(wk.get("gen", 0)) == 2 and str(wk.get("epoch")) == "a1b2c3d4" and not wk.has("fremd"),
		"6: welcome mit gid/gen/epoch (%s)" % str(wk))
	var idk := int(wk.id)
	var idw := int(gw.last("welcome").id)
	var ida := int(ga.last("welcome").id)
	check(s.backup_mark(idk) == mark and s.backup_mark(idw).is_empty() and s.backup_mark(ida).is_empty(), "6: hello.bk nur bei der App mit bk")
	check(s.backup_ids() == [idk], "6: backup_ids nur Kim (%s)" % str(s.backup_ids()))
	# restore_player und Wiedererkennen über bk_token
	var rid := s.restore_player("Ben", "app", "tok-ben-123")
	var rw := s.restore_player("Wart", "web", "tok-wart", true)
	check(rid > 0 and not bool(s.player(rid).connected) and bool(s.player(rid).ready) and s.seat_of(rid) == 4, "6: restore_player getrennt, bereit, Platz 4")
	check(s.is_waiting(rw) and s.seat_of(rw) == -1 and s.waiting_ids() == [rw] and str(s.player(rw).kind) == "web", "6: restore_player auf die Warteliste")
	var gb := raw(code, NetProtocol.make_hello("Ben", "app", "unbekannt", "", [2, "a1b2c3d4", 9], "tok-ben-123"))
	check(wait(func(): return not gb.last("welcome").is_empty()), "6: Ben angenommen")
	var wb := gb.last("welcome")
	check(int(wb.id) == rid and str(wb.token) == "tok-ben-123" and bool(s.player(rid).connected), "6: bk_token erkennt den Platz (%s)" % str(wb))
	check(s.backup_ids() == [idk, rid] and s.backup_mark(rid) == [2, "a1b2c3d4", 9], "6: Ben im bk-Verteiler (%s)" % str(s.backup_ids()))
	# send_many
	s.send_many([idk, rid, idw, s.host_id, 999], NetProtocol.encode({"t": "notice", "text": "alle drei"}))
	var got_all := func() -> bool:
		for g in [gk, gb, gw]:
			if g.last("notice").get("text") != "alle drei":
				return false
		return true
	check(wait(got_all), "6: send_many an drei Gäste")
	check(ga.last("notice").is_empty(), "6: send_many nur an die genannten")
	# online_room
	var room := s.online_room()
	check(str(room.get("room")) == code and str(room.get("token")) == s.relay.token and str(room.get("relay")) == base, "6: online_room Raum/Token/Vermittler")
	check(room.get("conns") == [1, 2, 3, 4] and int(room.get("max_c", 0)) >= 4 and int(room.get("created_unix", 0)) == FAKE_UNIX,
		"6: online_room conns/max_c/created_unix (%s)" % str(room))
	# Übernahme durch eine zweite Sitzung: die erste tritt ab (replaced an die Spielsteuerung, niemand getrennt)
	var s2 := new_session(HOST2_PORT)
	var left2 := []
	s2.player_left.connect(func(id: int) -> void: left2.append(id))
	check(s2.open_online_existing(str(room.relay), str(room.room), str(room.token), room.conns, int(room.max_c), int(room.created_unix)) == OK,
		"6: open_online_existing")
	check(wait(func(): return s.online_state() == "stepped_down" and s2.online_state() == "open"), "6: S2 führt, S tritt ab (%s/%s)" % [s.online_state(), s2.online_state()])
	check(replaced_n[0] == 1 and left.is_empty() and bool(s.player(idk).connected), "6: replaced an die Spielsteuerung, niemand getrennt")
	check(wait(func(): return gk.code == NetProtocol.CLOSE_RESYNC and gb.code == NetProtocol.CLOSE_RESYNC and gw.code == NetProtocol.CLOSE_RESYNC),
		"6: alle Gäste bekommen 4012 (%d/%d/%d)" % [gk.code, gb.code, gw.code])
	check(s2.relay.created_unix == FAKE_UNIX, "6: created_unix übernommen")
	drop(s)
	s.stop()
	pump(100)
	check(relay.core.rooms.has(code), "6: Stopp der abgetretenen Sitzung beendet den Raum nicht")
	# Ohne Empfänger von replaced: wie bis 1.6.0 (Online aufgeben, Online-Gäste getrennt)
	var gn := raw(code, NetProtocol.make_hello("Neu", "app"))
	check(wait(func(): return not gn.last("welcome").is_empty()), "6: Gast bei S2")
	var room2 := s2.online_room()
	var s3 := new_session(HOST3_PORT)
	s3.open_online_existing(str(room2.relay), str(room2.room), str(room2.token), room2.conns, int(room2.max_c), int(room2.created_unix))
	check(wait(func(): return s2.online_state() == "failed" and s3.online_state() == "open"), "6: S3 führt, S2 ohne Empfänger → failed (%s)" % s2.online_state())
	check(left2.size() == 1, "6: Online-Gast bei S2 getrennt wie bis 1.6.0 (%s)" % str(left2))
	# „wieder da“ erst, wenn der Vermittler wieder offen ist
	s3.app_paused()
	check(s3.is_away(s3.host_id), "6: Gastgeber away")
	var r3 := s3.relay
	r3.retry_ms = [100000]
	r3._ws.close()
	r3._ws = null
	r3._lost("Test")
	check(wait(func(): return int(relay.core.rooms[code].host) < 0), "6: Vermittler hat S3 verloren")
	s3.app_resumed()
	check(s3.is_away(s3.host_id) and s3.online_state() in ["away", "check", "connecting"], "6: noch away, solange neu verbunden wird (%s)" % s3.online_state())
	check(wait(func(): return s3.online_state() == "open" and not s3.is_away(s3.host_id)), "6: nach dem Neuverbinden wieder da")
	# Ohne Internet (/info scheitert, der Vermittler bleibt away ohne Signal): „wieder da“ spätestens nach unaway_max_ms (WLAN-Gäste)
	s3.app_paused()
	s3.unaway_max_ms = 300
	var url3 := r3.relay_url
	r3.relay_url = "http://127.0.0.1:1"
	r3.info_timeout_ms = 300
	r3._ws.close()
	r3._ws = null
	r3._lost("Test")
	s3.app_resumed()
	check(s3.is_away(s3.host_id) and s3.online_state() in ["away", "connecting"], "6: ohne Internet zunächst noch away (%s)" % s3.online_state())
	check(wait(func(): return not s3.is_away(s3.host_id), 4000) and s3.online_state() != "open", "6: … nach unaway_max_ms wieder da, Vermittler weiter weg (%s)" % s3.online_state())
	check(wait(func(): return r3._retry_at >= 0, 8000), "6: /info gescheitert, nächster Versuch geplant")
	r3.relay_url = url3
	r3.check_now()
	check(wait(func(): return s3.online_state() == "open"), "6: Internet wieder da: Vermittler offen")
	drop(s3)
	s3.stop("Ende", true)
	check(wait(func(): return not relay.core.rooms.has(code)), "6: stop(text, true) beendet den Raum")


# ---------- Hilfen ----------

func new_host() -> NetRelayHost:
	var h := NetRelayHost.new()
	h.auto_poll = false
	h.retry_ms = [50, 100, 200]
	nodes.append(h)
	all_nodes.append(h)
	return h


func new_session(port: int) -> NetHostSession:
	var s := NetHostSession.new()
	s.auto_poll = false
	s.use_discovery = false
	s.web_zip_path = ""
	check(s.start("Gastgeber %d" % port, port, port, false) == OK, "Sitzung auf %d" % port)
	nodes.append(s)
	all_nodes.append(s)
	return s


func drop(n: Object) -> void:
	nodes.erase(n)


func raw(code: String, hello := {}) -> RawGuest:
	var g := RawGuest.new(NetProtocol.relay_ws_url(base, "role=guest&room=" + code), hello)
	guests.append(g)
	return g


func pump(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while true:
		step()
		if Time.get_ticks_msec() >= end:
			break
		OS.delay_msec(1)


func step() -> void:
	relay.poll()
	for n in nodes:
		if not is_instance_valid(n):
			continue
		if n is HostTable:
			n.pump()
		else:
			n.poll()
	for g in guests:
		g.poll()


func wait(cond: Callable, ms := 4000) -> bool:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		pump(2)
		if cond.call():
			return true
	return cond.call()


func pump_until(cond: Callable, ms: int) -> bool:
	return wait(cond, ms)
