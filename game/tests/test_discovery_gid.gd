extends SceneTree

# Mau-Mau Flip (Beta 1.6.2, WLAN-Übergabe, docs/module/uebergabe.md 10.1/10.11/10.16): Suchantwort mit gid/gen/epoch/conn,
# Begrüßung mit hp/bk_gid/ap, handover_ok, move/hosts bauen und prüfen, same_net; NetDiscovery mit eingespritzter Uhr:
# Gastgeber-Scan meldet rival nur bei gleicher gid und nie für die eigene sid, ports fragt mehrere UDP-Ports ab, Abfrageabstand
# und Verfall laufen über now_ms. UDP-Ports 24901–24905 (freier Bereich laut Testplan).

const PORTS := [24901, 24902, 24903, 24904]
const SEARCH_EXTRA := 24905   # unbenutzt: Anfragen an einen toten Port schaden nicht
const G := "0123456789abcdef"
const H := "fedcba9876543210"

var failures := 0
var checks := 0
var clock := [1000000]
var hosts := {}               # sid -> NetDiscovery
var rivals := {}              # sid -> Array der gemeldeten rival-Einträge

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)

func _init() -> void:
	test_constants()
	test_reply_fields()
	test_hello_fields()
	test_handover_ok()
	test_move()
	test_hosts()
	test_same_net()
	test_host_scan()
	test_search_ports_clock()
	for d in hosts.values():
		d.stop()
		d.free()
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)

func test_constants() -> void:
	check(NetProtocol.HOST_SCAN_MS == 5000 and NetProtocol.LAN_SEARCH_MS == 2000 and NetProtocol.PAST_MAX == 16, "Konstanten 10.1")
	var d := NetDiscovery.new()
	check(d.scan_ms == NetProtocol.HOST_SCAN_MS and d.ports.is_empty() and d.now_ms.is_valid() and int(d.now_ms.call()) >= 0, "Standardwerte der Suche")
	d.free()

func test_reply_fields() -> void:
	var info := NetProtocol.make_info("Lena", 4, 24690, {"running": true, "sid": "abc", "addresses": ["192.168.1.5"],
		"gid": G, "gen": 3, "epoch": "a1b2c3d4", "conn": 2})
	var back := NetProtocol.parse_reply(NetProtocol.make_reply(info))
	check(back.gid == G and back.gen == 3 and back.epoch == "a1b2c3d4" and back.conn == 2, "Suchantwort trägt gid, gen, epoch, conn (%s)" % str(back))
	check(back.gen is int and back.conn is int and back.name == "Lena" and back.sid == "abc", "Typen und alte Felder")
	var plain := NetProtocol.parse_reply(NetProtocol.make_reply(NetProtocol.make_info("Lena", 1, 24690, {"sid": "abc"})))
	check(plain.gid == "" and plain.gen == 0 and plain.epoch == "" and plain.conn == 0, "ohne Partie: Standardwerte")
	var bad_cases := [
		[{"gid": "xyz!", "gen": 3, "epoch": "ab"}, "gid kein Hex"],
		[{"gid": "a".repeat(33), "gen": 3, "epoch": "ab"}, "gid zu lang"],
		[{"gid": 17, "gen": 3, "epoch": "ab"}, "gid keine Zeichenkette"],
		[{"gid": "-ab", "gen": 3, "epoch": "ab"}, "gid mit Vorzeichen"]]
	for c in bad_cases:
		var e := info.duplicate()
		e.merge(c[0], true)
		var r := NetProtocol.parse_reply(NetProtocol.make_reply(e))
		check(not r.is_empty() and r.gid == "" and r.gen == 0 and r.epoch == "", "kaputtes Feld verworfen: %s" % c[1])
	for c in [[{"gen": -1}, "gen negativ"], [{"gen": "3"}, "gen Text"], [{"gen": 2.5}, "gen Bruch"]]:
		var e := info.duplicate()
		e.merge(c[0], true)
		var r := NetProtocol.parse_reply(NetProtocol.make_reply(e))
		check(r.gid == G and r.gen == 0, "kaputtes Feld verworfen: %s" % c[1])
	for c in [[{"epoch": "zz"}, "epoch kein Hex"], [{"epoch": "a".repeat(17)}, "epoch zu lang"], [{"epoch": 5}, "epoch Zahl"]]:
		var e := info.duplicate()
		e.merge(c[0], true)
		check(NetProtocol.parse_reply(NetProtocol.make_reply(e)).epoch == "", "kaputtes Feld verworfen: %s" % c[1])
	for c in [[{"conn": 17}, "conn zu groß"], [{"conn": -1}, "conn negativ"], [{"conn": "2"}, "conn Text"]]:
		var e := info.duplicate()
		e.merge(c[0], true)
		check(NetProtocol.parse_reply(NetProtocol.make_reply(e)).conn == 0, "kaputtes Feld verworfen: %s" % c[1])
	var e16 := info.duplicate()
	e16.conn = 16
	check(NetProtocol.parse_reply(NetProtocol.make_reply(e16)).conn == 16, "conn 16 gilt noch")

func test_hello_fields() -> void:
	var h := NetProtocol.make_hello("Kim", "app", "tok", "", [3, "a1b2", 17], "platz", {"hp": 24690, "bk_gid": G, "ap": {"ok": true, "perm": false}})
	var c := NetProtocol.clean_client_message(NetProtocol.decode(NetProtocol.encode(h)))
	check(c.hp == 24690 and c.bk_gid == G and c.ap == {"ok": true, "perm": false}, "hello: hp, bk_gid, ap über JSON (%s)" % str(c))
	check(c.bk == [3, "a1b2", 17] and c.bk_token == "platz" and c.token == "tok", "hello: alte Felder bleiben")
	var old := NetProtocol.make_hello("Kim", "app", "tok")
	check(not old.has("hp") and not old.has("bk_gid") and not old.has("ap"), "make_hello ohne extra: keine neuen Felder")
	var bad := NetProtocol.clean_client_message({"t": "hello", "proto": 1, "hp": 80, "bk_gid": "xyz", "ap": {"ok": 1, "perm": "ja"}})
	check(not bad.has("hp") and not bad.has("bk_gid") and bad.ap == {"ok": false, "perm": false}, "hello: ungültige hp/bk_gid, ap nur mit bool (%s)" % str(bad))
	for v in [1023, 65536, "24690", 24690.5]:
		check(not NetProtocol.clean_client_message({"t": "hello", "hp": v}).has("hp"), "hp ungültig: %s" % str(v))
	check(not NetProtocol.clean_client_message({"t": "hello", "ap": [true]}).has("ap"), "ap kein Objekt: weggelassen")
	check(not NetProtocol.clean_client_message({"t": "hello", "bk_gid": "a".repeat(33)}).has("bk_gid"), "bk_gid zu lang")
	var lite := NetProtocol.clean_client_message({"t": "hello", "proto": 1, "kind": "web", "name": "Bea"})
	check(not lite.has("hp") and not lite.has("ap") and not lite.has("bk_gid"), "Lite ohne neue Felder")

func test_handover_ok() -> void:
	var m := NetProtocol.clean_client_message(NetProtocol.decode(NetProtocol.encode(NetProtocol.make_handover_ok(24917))))
	check(m == {"t": "handover_ok", "port": 24917, "qr": false}, "handover_ok lan (%s)" % str(m))
	check(NetProtocol.clean_client_message({"t": "handover_ok", "qr": true, "x": 1}) == {"t": "handover_ok", "port": 0, "qr": true}, "handover_ok qr ohne Port")
	check(NetProtocol.clean_client_message({"t": "handover_ok", "port": 24690, "qr": true}) == {"t": "handover_ok", "port": 24690, "qr": true}, "handover_ok qr mit Port")
	check(NetProtocol.clean_client_message({"t": "handover_ok"}).is_empty(), "handover_ok ohne Port und ohne qr verworfen")
	check(NetProtocol.clean_client_message({"t": "handover_ok", "port": 70000, "qr": "ja"}).is_empty(), "handover_ok mit kaputten Feldern verworfen")

func test_move() -> void:
	var lan := NetProtocol.make_move(G, 4, "beef", "lan", "Bea", "192.168.1.7", 24690)
	check(lan.url == "http://192.168.1.7:24690/" and lan.room == "" and lan.relay == "" and lan.name == "Bea" and lan.t == "move", "move lan (%s)" % str(lan))
	var wire := NetProtocol.decode(NetProtocol.encode(lan), NetProtocol.MAX_HOST_MESSAGE)
	check(NetProtocol.clean_move(wire, G) == lan, "move lan übersteht JSON und Prüfung")
	check(NetProtocol.clean_move(wire) == lan, "ohne erwartete gid angenommen")
	check(NetProtocol.clean_move(wire, H).is_empty(), "fremde gid verworfen")
	var on := NetProtocol.make_move(G, 5, "", "online", "Kim", "", 0, "katze-42", "https://relay.example/x")
	check(on.room == "KATZE-42" and on.relay == "https://relay.example" and on.url == "https://relay.example/?r=KATZE-42" and on.addr == "" and on.port == 0, "move online (%s)" % str(on))
	check(NetProtocol.clean_move(NetProtocol.decode(NetProtocol.encode(on), NetProtocol.MAX_HOST_MESSAGE), G) == on, "move online übersteht JSON und Prüfung")
	var qr := NetProtocol.make_move(G, 6, "01", "qr", "Ute", "192.168.1.9", 24690, "KATZE-42", "https://relay.example")
	check(qr.addr == "" and qr.port == 0 and qr.room == "" and qr.url == "" and qr.name == "Ute", "move qr nur mit Namen (%s)" % str(qr))
	check(NetProtocol.clean_move(qr, G) == qr, "move qr geprüft")
	# Felder werden aus den geprüften Werten neu gebaut: eingeschmuggelte url gilt nicht
	var sneaky := lan.duplicate()
	sneaky.url = "javascript:alert(1)"
	sneaky["x"] = 1
	check(NetProtocol.clean_move(sneaky, G) == lan, "url und fremde Felder neu gebaut")
	var broken := [
		[{"gid": "zz"}, "gid kein Hex"], [{"gen": 0}, "gen 0"], [{"gen": "4"}, "gen Text"], [{"epoch": "zz"}, "epoch kein Hex"],
		[{"how": "bus"}, "how unbekannt"], [{"addr": "192.168.1"}, "addr keine IPv4"], [{"addr": "0.0.0.0"}, "addr 0.0.0.0"],
		[{"port": 0}, "Port 0"], [{"port": 99999}, "Port zu groß"], [{"t": "bk"}, "anderer Typ"]]
	for b in broken:
		var m := lan.duplicate()
		m.merge(b[0], true)
		check(NetProtocol.clean_move(m, G).is_empty(), "move verworfen: %s" % b[1])
	var on_bad := on.duplicate()
	on_bad.room = "x"
	check(NetProtocol.clean_move(on_bad, G).is_empty(), "move online ohne gültigen Raum verworfen")
	on_bad = on.duplicate()
	on_bad.relay = "ftp://x y"
	check(NetProtocol.clean_move(on_bad, G).is_empty(), "move online ohne gültigen Vermittler verworfen")
	var nameless := qr.duplicate()
	nameless.name = 5
	check(NetProtocol.clean_move(nameless, G).name == "Gastgeber", "Name fehlt: Gastgeber")

func test_hosts() -> void:
	var list := [{"name": "Bea", "url": "http://192.168.1.7:24690/"}, {"name": "Kim\u0007", "url": "http://192.168.1.8:24690/"},
		{"name": "Böse", "url": "javascript:alert(1)"}, {"name": "x", "url": 5}, "kaputt", {"name": "Lang", "url": "http://" + "a".repeat(400)}]
	var h := NetProtocol.make_hosts(G, 3, list, "https://relay.example/?r=KATZE-42", true, "Bea")
	check(h.t == "hosts" and h.gid == G and h.gen == 3 and h.ap == true and h.ap_name == "Bea", "hosts: Kopf (%s)" % str(h))
	check(h.list == [{"name": "Bea", "url": "http://192.168.1.7:24690/"}, {"name": "Kim", "url": "http://192.168.1.8:24690/"}], "hosts: nur gültige Einträge (%s)" % str(h.list))
	check(h.online == "https://relay.example/?r=KATZE-42", "hosts: Raum-Link")
	var empty := NetProtocol.make_hosts(G, 1, [])
	check(empty.list == [] and empty.online == "" and empty.ap == false and empty.ap_name == "", "hosts: leere Liste geht auch hinaus")
	check(NetProtocol.make_hosts(G, 1, [], "javascript:x").online == "", "hosts: ungültiger Raum-Link leer")
	var many := []
	for i in 20:
		many.append({"name": "P%d" % i, "url": "http://10.0.0.%d:24690/" % (i + 1)})
	check(NetProtocol.make_hosts(G, 1, many).list.size() == NetProtocol.MAX_PLAYERS, "hosts: höchstens MAX_PLAYERS")

func test_same_net() -> void:
	check(NetProtocol.same_net("192.168.1.5", "192.168.1.200", 24), "/24 gleich")
	check(not NetProtocol.same_net("192.168.1.5", "192.168.2.5", 24), "/24 verschieden")
	check(NetProtocol.same_net("192.168.1.5", "192.168.2.5", 16), "/16 gleich")
	check(NetProtocol.same_net("10.1.2.3", "10.200.0.1", 8) and not NetProtocol.same_net("10.1.2.3", "11.1.2.3", 8), "/8")
	check(NetProtocol.same_net("172.17.251.253", "172.17.251.40", 24), "Spiel-WLAN-Netz")
	check(NetProtocol.same_net("192.168.1.5", "192.168.1.5", 32) and not NetProtocol.same_net("192.168.1.5", "192.168.1.6", 32), "/32")
	check(NetProtocol.same_net("192.168.1.130", "192.168.1.200", 25) and not NetProtocol.same_net("192.168.1.5", "192.168.1.200", 25), "/25")
	check(NetProtocol.same_net("200.1.1.1", "250.9.9.9", 1) and not NetProtocol.same_net("1.1.1.1", "200.1.1.1", 1), "/1")
	for c in [["192.168.1.5", "x", 24], ["", "192.168.1.5", 24], ["192.168.1.5", "192.168.1.5", 0], ["192.168.1.5", "192.168.1.5", 33]]:
		check(not NetProtocol.same_net(c[0], c[1], c[2]), "ungültig: %s" % str(c))

# --- NetDiscovery mit eingespritzter Uhr ---

func now() -> int:
	return clock[0]

func make_host(sid: String, listen: int, gid: String, gen: int, conn: int) -> NetDiscovery:
	var d := NetDiscovery.new()
	d.auto_poll = false
	d.use_broadcast = false
	d.probe_local = true
	d.ports = PORTS
	d.now_ms = now
	var extra := {"running": gid != "", "sid": sid, "addresses": []}
	if gid != "":
		extra.merge({"gid": gid, "gen": gen, "epoch": "a1", "conn": conn})
	check(d.start_host(NetProtocol.make_info("Host-" + sid, 3, 24690 + listen % 100, extra), listen) == OK, "Gastgeber %s lauscht auf %d" % [sid, listen])
	rivals[sid] = []
	d.rival.connect(func(info): rivals[sid].append(info))
	hosts[sid] = d
	return d

func pump(ms: int, extra: Array = []) -> void:
	# echte Zeit für die UDP-Zustellung; die Uhr der Suche steht dabei
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		for d in hosts.values():
			d.poll()
		for d in extra:
			d.poll()
		OS.delay_msec(3)

func test_host_scan() -> void:
	var a := make_host("aaaa", PORTS[0], G, 2, 1)
	var b := make_host("bbbb", PORTS[1], G, 3, 2)
	var c := make_host("cccc", PORTS[2], H, 7, 0)
	var d := make_host("dddd", PORTS[3], "", 0, 0)   # Lobby ohne Partie: antwortet, fragt aber nicht
	pump(400)
	check(int(a.counters.get("scans", 0)) == 1 and int(b.counters.get("scans", 0)) == 1, "erster Scan sofort")
	check(int(d.counters.get("scans", 0)) == 0 and int(d.counters.get("sent", 0)) == 0, "ohne gid kein Scan")
	check(int(a.counters.get("sent", 0)) == PORTS.size(), "Scan fragt alle ports (%d)" % int(a.counters.get("sent", 0)))
	check(rivals.aaaa.size() == 1 and rivals.aaaa[0].sid == "bbbb", "A meldet B als rival (%s)" % str(rivals.aaaa))
	if rivals.aaaa.size() == 1:
		var r: Dictionary = rivals.aaaa[0]
		check(r.gid == G and r.gen == 3 and r.epoch == "a1" and r.conn == 2 and r.address == "127.0.0.1" and r.port == 24690 + PORTS[1] % 100, "rival-Eintrag mit gid, gen, epoch, conn, Adresse, Port (%s)" % str(r))
	check(rivals.bbbb.size() == 1 and rivals.bbbb[0].sid == "aaaa", "B meldet A (symmetrisch)")
	check(rivals.cccc.is_empty(), "andere gid: kein rival")
	check(rivals.dddd.is_empty(), "ohne eigene gid: kein rival")
	check(not a.games.has("aaaa") and a.games.has("bbbb") and a.games.has("cccc") and a.games.has("dddd"), "eigene sid übergangen, andere eingetragen (%s)" % str(a.games.keys()))
	check(a.games.cccc.gid == H and a.games.dddd.gid == "" and a.games.dddd.gen == 0, "Einträge mit gid")
	check(a.find_gid(G).size() == 1 and a.find_gid(G)[0].sid == "bbbb" and a.find_gid("").is_empty(), "find_gid")
	check(int(a.counters.get("queries", 0)) >= 3, "A beantwortet die Scans der anderen (und den eigenen)")
	for sid in rivals:
		check((rivals[sid] as Array).all(func(r): return r.sid != sid), "nie die eigene sid (%s)" % sid)
	# Abfrageabstand über die eingespritzte Uhr
	pump(250)
	check(int(a.counters.get("scans", 0)) == 1 and rivals.aaaa.size() == 1, "ohne Uhrzeit kein neuer Scan")
	clock[0] += NetProtocol.HOST_SCAN_MS - 1
	pump(150)
	check(int(a.counters.get("scans", 0)) == 1, "kurz vor scan_ms kein Scan")
	clock[0] += 1
	pump(300)
	check(int(a.counters.get("scans", 0)) == 2 and rivals.aaaa.size() == 2 and rivals.bbbb.size() == 2, "nach scan_ms neuer Scan, rival einmal je Scan (%d)" % rivals.aaaa.size())
	# Verfall: B verschwindet; Einträge leben im Gastgeber-Modus mindestens zwei Scans
	var t_b: int = clock[0]
	b.stop()
	hosts.erase("bbbb")
	b.free()
	clock[0] = t_b + NetProtocol.HOST_SCAN_MS
	pump(250)
	check(a.games.has("bbbb") and rivals.aaaa.size() == 2, "B nach einem verpassten Scan noch da, kein rival")
	clock[0] = t_b + NetProtocol.HOST_SCAN_MS * 2 + 1001
	pump(250)
	check(not a.games.has("bbbb") and a.games.has("cccc"), "B verfallen, C aufgefrischt (%s)" % str(a.games.keys()))
	check(a.games_list().all(func(g): return int(g.age_ms) < 1000), "Alter nach der eingespritzten Uhr")
	# andere gid über set_info: alte Einträge weg, sofort neu fragen; C ist jetzt rival
	var scans := int(a.counters.get("scans", 0))
	var info := NetProtocol.make_info("Host-aaaa", 3, 24601, {"running": true, "sid": "aaaa", "gid": H, "gen": 1, "epoch": "b2", "conn": 0, "addresses": []})
	a.set_info(info)
	check(a.games.is_empty(), "neue gid: Einträge geleert")
	pump(300)
	check(int(a.counters.get("scans", 0)) == scans + 1 and rivals.aaaa.size() == 3 and rivals.aaaa[2].sid == "cccc", "neue gid: sofort gefragt, C ist rival")
	check(rivals.cccc.size() == 0, "C sieht A erst bei seinem nächsten Scan")
	# scan_ms ≤ 0 schaltet den Wächter ab
	a.scan_ms = 0
	clock[0] += 60000
	pump(200)
	check(int(a.counters.get("scans", 0)) == scans + 1, "scan_ms 0: kein Scan")
	a.scan_ms = NetProtocol.HOST_SCAN_MS
	check(c.mode == "host" and d.mode == "host", "C und D antworten weiter")

func test_search_ports_clock() -> void:
	var s := NetDiscovery.new()
	s.auto_poll = false
	s.use_broadcast = false
	s.probe_local = true
	s.ports = PORTS + [SEARCH_EXTRA]
	s.now_ms = now
	check(s.start_search(PORTS[0]) == OK, "Suche gestartet")
	var start: int = clock[0]
	pump(400, [s])
	var sent := int(s.counters.get("sent", 0))
	check(sent == PORTS.size() + 1, "eine Anfrage je Port (%d)" % sent)
	check(s.games.has("aaaa") and s.games.has("cccc") and s.games.has("dddd") and not s.games.has("bbbb"), "alle lebenden Gastgeber über ports gefunden (%s)" % str(s.games.keys()))
	if s.games.has("cccc"):
		var e: Dictionary = s.games.cccc
		check(e.gid == H and e.gen == 7 and e.epoch == "a1" and e.conn == 0 and e.compatible, "Sucheintrag mit gid, gen, epoch, conn")
	check(s.find_gid(H).size() == 2 and s.find_gid(H)[0].sid == "cccc", "find_gid: höchste gen zuerst (%s)" % str(s.find_gid(H).map(func(g): return g.sid)))
	pump(200, [s])
	check(int(s.counters.sent) == sent, "Abfrageabstand: ohne Uhrzeit keine neue Anfrage")
	clock[0] = start + 999
	pump(150, [s])
	check(int(s.counters.sent) == sent, "kurz vor query_interval_ms keine Anfrage")
	clock[0] = start + 1000
	pump(250, [s])
	check(int(s.counters.sent) == sent * 2, "nach query_interval_ms neue Anfrage (%d)" % int(s.counters.sent))
	# Verfall: C hört auf zu antworten
	var c: NetDiscovery = hosts.cccc
	c.stop()
	hosts.erase("cccc")
	c.free()
	clock[0] = start + 1000 + s.expire_ms + 1
	pump(300, [s])
	check(not s.games.has("cccc") and s.games.has("aaaa") and s.games.has("dddd"), "C verfallen, A und D bleiben (%s)" % str(s.games.keys()))
	check(s.games_list().all(func(g): return int(g.age_ms) == 0), "Alter nach der eingespritzten Uhr")
	s.stop()
	s.free()
