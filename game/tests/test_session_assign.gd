extends SceneTree

# Mau-Mau Flip (Beta 1.6.2, docs/module/uebergabe.md 10.1, 10.9, 10.10): NetHostSession im WLAN über 127.0.0.1 (TCP 24921, UDP 24923)
#  - info() bzw. /info und Suche tragen bei laufender Partie gid, gen, epoch und conn; set_game_mark frischt beides sofort auf.
#  - hello: hp, ap und bk_gid je Spieler; bk_token gilt nur mit bk_gid == gid der Partie (fremde gid, ohne bk_gid: Warteliste).
#  - assign_seat: zweites welcome mit Platz-Token und assigned:true, dann start{seat}; ein App-Gast mit altem Token aus der
#    Token-Datei für dieselbe ip:port wird danach weder removed noch readmitted; Ablehnungen (verbundener Platz, Gastgeber, Computer,
#    Wartender, kein Wartender); Nachrichten des Gesetzten kommen unter der Platz-id an.
#  - send_hosts nur an Browser-Gäste im WLAN, nach jedem welcome während der Partie erneut; drain und set_extra_origins.

const PORT := 24921
const DISC := 24923
const GID := "a1b2c3d4e5f60718"
const EPOCH := "0badf00d"

var failures := 0
var checks := 0
var host: NetHostSession
var clients: Array = []
var rejoined: Array = []
var host_msgs: Array = []
var inbox := {}                          # NetClient -> [Nachrichten]

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)

func _init() -> void:
	host = NetHostSession.new()
	host.auto_poll = false
	host.discovery_port = DISC
	host.player_rejoined.connect(func(id): rejoined.append(id))
	host.message.connect(func(id, msg): host_msgs.append([id, msg]))
	check(host.start("Hanna", PORT, PORT) == OK, "Gastgeber auf %d" % PORT)
	test_info_and_hello()
	test_bk_token_gid()
	test_assign_app_old_token()
	test_assign_web_and_hosts()
	test_drain_and_origins()
	for c in clients:
		c.close()
		c.free()
	host.stop()
	host.free()
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)

# ---------- Hilfen ----------

func new_client(player_name: String, kind := "app", start := true) -> NetClient:
	var c := NetClient.new()
	c.auto_poll = false
	c.persist_tokens = false
	c.reuse_token = false
	c.ping_ms = 300
	c.retry_ms = [150, 300, 600, 800]
	inbox[c] = []
	c.message.connect(func(m): inbox[c].append(m))
	# welcome behandelt NetClient selbst (kein message): als Eintrag mitschreiben, damit die Reihenfolge prüfbar ist
	c.welcomed.connect(func(id, _h): inbox[c].append({"t": "welcome", "id": id, "token": c.token}))
	clients.append(c)
	if start:
		c.connect_to("127.0.0.1", PORT, player_name, kind)
	return c

# Roher WebSocket-Gast wie Lite: sieht jede Nachricht so, wie sie auf der Leitung ankommt (auch welcome mit assigned).
class Raw:
	var ws := WebSocketPeer.new()
	var hello := {}
	var sent := false
	var msgs: Array = []
	func poll() -> void:
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not sent:
			sent = true
			ws.send_text(NetProtocol.encode(hello))
		while ws.get_available_packet_count() > 0:
			var d := NetProtocol.decode(ws.get_packet().get_string_from_utf8(), NetProtocol.MAX_HOST_MESSAGE)
			if not d.is_empty():
				msgs.append(d)
	func id() -> int:
		for m in msgs:
			if m.get("t") == "welcome":
				return int(m.id)
		return 0

var raws: Array = []

func new_raw(player_name: String) -> Raw:
	var r := Raw.new()
	r.hello = NetProtocol.make_hello(player_name, "web")
	r.ws.connect_to_url("ws://127.0.0.1:%d%s" % [PORT, NetProtocol.WS_PATH])
	inbox[r] = r.msgs
	raws.append(r)
	return r

func pump(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while true:
		host.poll()
		for c in clients:
			c.poll()
		for r in raws:
			r.poll()
		if Time.get_ticks_msec() >= end:
			break
		OS.delay_msec(1)

func wait_until(cond: Callable, ms := 3000) -> bool:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		pump(2)
		if cond.call():
			return true
	return cond.call()

func of_type(c: Object, t: String) -> Array:
	return inbox[c].filter(func(m): return m.get("t") == t)

func first_of(c: Object, t: String) -> Dictionary:
	var list := of_type(c, t)
	return list[0] if not list.is_empty() else {}

func index_of(c: Object, cond: Callable) -> int:
	for i in range(inbox[c].size()):
		if cond.call(inbox[c][i]):
			return i
	return -1

func http_info() -> Dictionary:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", PORT)
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
	return NetProtocol.ints(data) if data is Dictionary else {}

func id_of(player_name: String) -> int:
	for id in host.players:
		if str(host.players[id].name) == player_name:
			return id
	return -1

# ---------- Kennung der Partie, hello-Felder ----------

var anna: NetClient
var ben: NetClient
var lisa: NetClient
var bot_id := 0

func test_info_and_hello() -> void:
	bot_id = host.add_local_player("Robo", "bot")
	anna = new_client("Anna", "app", false)
	anna.listen_port = 24777
	anna.ap_info = func() -> Dictionary: return {"ok": true, "perm": false}
	anna.bk = [0, "", 0]
	anna.connect_to("127.0.0.1", PORT, "Anna", "app")
	ben = new_client("Ben")
	lisa = new_client("Lisa", "web")
	check(wait_until(func(): return [anna, ben, lisa].all(func(c): return c.state == "open")), "drei Gäste angenommen")
	var a := anna.my_id
	check(host.hello_port(a) == 24777, "hp gemerkt (%d)" % host.hello_port(a))
	check(host.ap_caps(a) == {"ok": true, "perm": false}, "ap gemerkt %s" % str(host.ap_caps(a)))
	check(host.ap_caps(lisa.my_id) == {"ok": false, "perm": false} and host.hello_port(lisa.my_id) == 0, "Browser: kein hp/ap")
	check(host.backup_gid(a) == "", "ohne Sicherung keine bk_gid")
	# Lobby: noch keine Kennung
	var i := host.info()
	check(not i.has("gid") and not i.has("conn"), "Lobby: info ohne gid/conn %s" % str(i))
	host.set_game_mark(GID, 3, EPOCH)
	check(not host.info().has("gid"), "gid erst bei laufender Partie")
	host.send_start()
	i = host.info()
	check(i.get("gid") == GID and i.get("gen") == 3 and i.get("epoch") == EPOCH and i.get("conn") == 3, "info mit gid/gen/epoch/conn %s" % str(i))
	var w: Dictionary = first_of(anna, "welcome")
	check(w.get("id") == anna.my_id and anna.welcome_info.get("gid", "") == "", "Lobby-welcome ohne gid")
	host.set_game_mark(GID, 4, EPOCH)
	var h := http_info()
	check(h.get("gid") == GID and h.get("gen") == 4 and h.get("conn") == 3, "/info sofort aufgefrischt %s" % str(h))
	check(host.discovery != null and host.discovery._info.get("gen") == 4, "Suche aufgefrischt")
	var reply := NetProtocol.parse_reply(NetProtocol.make_reply(host.info()))
	check(reply.get("gid") == GID and reply.get("gen") == 4 and reply.get("conn") == 3, "Suchantwort trägt gid/gen/conn %s" % str(reply))
	# Ben und Lisa gehen: conn sinkt
	ben.close()
	lisa.close()
	check(wait_until(func(): return not bool(host.player(id_of("Ben")).connected) and not bool(host.player(id_of("Lisa")).connected)), "Ben und Lisa getrennt")
	check(host.info().get("conn") == 1, "conn zählt nur Verbundene (%s)" % str(host.info().get("conn")))
	h = http_info()
	check(h.get("conn") == 1, "/info conn 1 (%s)" % str(h.get("conn")))

# ---------- bk_token nur mit passender gid ----------

func test_bk_token_gid() -> void:
	var ben_id := id_of("Ben")
	var ben_token := str(host.player(ben_id).token)
	host.join_open = true
	# fremde gid: Warteliste statt Bens Platz
	var x := new_client("Bert", "app", false)
	x.bk_token = ben_token
	x.bk_gid = "ffff0000"
	x.connect_to("127.0.0.1", PORT, "Bert", "app")
	check(wait_until(func(): return x.state == "open"), "fremde gid angenommen")
	check(x.my_id != ben_id and host.is_waiting(x.my_id) and not bool(host.player(ben_id).connected), "fremde gid: bk_token gilt nicht (Warteliste)")
	check(host.backup_gid(x.my_id) == "ffff0000", "bk_gid gemerkt")
	# ohne bk_gid (ältere Gäste innerhalb derselben Version gibt es nicht): ebenso nicht
	var y := new_client("Bodo", "app", false)
	y.bk_token = ben_token
	y.connect_to("127.0.0.1", PORT, "Bodo", "app")
	check(wait_until(func(): return y.state == "open"), "ohne bk_gid angenommen")
	check(y.my_id != ben_id and host.is_waiting(y.my_id), "ohne bk_gid: bk_token gilt nicht")
	# passende gid: Bens Platz
	var z := new_client("Benny", "app", false)
	z.bk_token = ben_token
	z.bk_gid = GID
	z.connect_to("127.0.0.1", PORT, "Benny", "app")
	check(wait_until(func(): return z.state == "open"), "passende gid angenommen")
	check(z.my_id == ben_id and bool(host.player(ben_id).connected) and rejoined.has(ben_id), "passende gid: Bens Platz")
	check(host.backup_gid(ben_id) == GID, "bk_gid am Platz gemerkt")
	for c in [x, y, z]:
		c.close()
	check(wait_until(func(): return not bool(host.player(ben_id).connected) and not bool(host.player(x.my_id).connected)), "wieder getrennt")
	host.remove_player(x.my_id)
	host.remove_player(y.my_id)
	check(host.waiting_ids().is_empty(), "Warteliste leer")

# ---------- assign_seat: App-Gast mit altem Token ----------

func test_assign_app_old_token() -> void:
	var ben_id := id_of("Ben")
	var ben_seat := host.seat_of(ben_id)
	var ben_token := str(host.player(ben_id).token)
	var c := new_client("Bruno", "app", false)
	c.listen_port = 24800
	c.ap_info = func() -> Dictionary: return {"ok": true, "perm": true}
	c.connect_to("127.0.0.1", PORT, "Bruno", "app")
	c.token = "00112233445566778899aabb"    # altes Token aus der Token-Datei für dieselbe ip:port (dem Gastgeber unbekannt)
	check(wait_until(func(): return c.state == "open"), "Bruno angenommen")
	var wid := c.my_id
	check(host.is_waiting(wid) and wid != ben_id, "Bruno wartet")
	check(not c.removed and not c.readmitted, "erstes welcome: nicht herausgenommen")
	# Ablehnungen
	var anna_id := anna.my_id
	check(not host.assign_seat(wid, host.host_id), "nicht auf den Gastgeber")
	check(not host.assign_seat(wid, bot_id), "nicht auf einen Computer")
	check(not host.assign_seat(wid, anna_id), "nicht auf einen verbundenen Platz")
	check(not host.assign_seat(anna_id, ben_id), "nur Wartende")
	check(not host.assign_seat(wid, 9999), "unbekannter Platz")
	check(not host.assign_seat(wid, wid), "nicht auf sich selbst")
	var other := new_client("Olga")
	check(wait_until(func(): return other.state == "open"), "Olga wartet")
	check(not host.assign_seat(wid, other.my_id), "nicht auf einen Wartenden")
	check(host.is_waiting(wid) and not bool(host.player(ben_id).connected), "Ablehnungen ändern nichts")
	# Hinsetzen
	inbox[c].clear()
	var n_rejoined := rejoined.size()
	check(host.assign_seat(wid, ben_id), "Bruno auf Bens Platz")
	check(not host.players.has(wid) and not host.is_waiting(ben_id), "Eintrag des Wartenden fällt weg")
	var p := host.player(ben_id)
	check(bool(p.connected) and int(p.conn) >= 0 and int(p.seat) == ben_seat and str(p.token) == ben_token, "Platz verbunden, Token bleibt")
	check(host.hello_port(ben_id) == 24800 and host.ap_caps(ben_id) == {"ok": true, "perm": true}, "hp/ap gehen über")
	check(rejoined.size() == n_rejoined + 1 and rejoined[-1] == ben_id, "player_rejoined für den Platz")
	check(wait_until(func(): return of_type(c, "start").size() > 0), "start kommt an")
	var iw := index_of(c, func(m): return m.get("t") == "welcome")
	var is_ := index_of(c, func(m): return m.get("t") == "start")
	check(iw >= 0 and is_ > iw, "Reihenfolge welcome → start (%d, %d)" % [iw, is_])
	var w: Dictionary = inbox[c][iw] if iw >= 0 else {}
	check(w.get("id") == ben_id and w.get("token") == ben_token and c.welcome_info.get("gid") == GID, "zweites welcome mit Platz-Token und gid %s" % str(w))
	check(first_of(c, "start").get("seat") == ben_seat, "start mit Bens Platz")
	check(c.my_id == ben_id and c.token == ben_token, "Client übernimmt id und Token")
	check(not c.removed and not c.readmitted, "kein removed/readmitted trotz altem Token")
	check(of_type(c, "hosts").is_empty(), "App-Gast bekommt kein hosts")
	# Nachrichten kommen unter der Platz-id an
	host_msgs.clear()
	c.send({"t": "act", "a": {"a": "draw"}})
	check(wait_until(func(): return not host_msgs.is_empty()), "Aktion kommt an")
	check(not host_msgs.is_empty() and host_msgs[0][0] == ben_id, "Aktion unter Bens id")
	check(host.info().get("conn") == 2, "conn zählt den Gesetzten (%s)" % str(host.info().get("conn")))
	# Trennen: der Platz wird wieder getrennt, nicht der alte Wartende
	c.close()
	check(wait_until(func(): return not bool(host.player(ben_id).connected)), "Bruno getrennt → Bens Platz getrennt")
	other.close()
	check(wait_until(func(): return not bool(host.player(other.my_id).connected)), "Olga getrennt")
	host.remove_player(other.my_id)

# ---------- assign_seat: Browser-Gast, hosts ----------

func test_assign_web_and_hosts() -> void:
	var lisa_id := id_of("Lisa")
	var lisa_seat := host.seat_of(lisa_id)
	inbox[anna].clear()
	host.send_hosts({"gid": GID, "gen": 4, "list": [{"name": "Anna", "url": "http://127.0.0.1:24777/"}], "online": "", "ap": false, "ap_name": ""})
	check(host.hosts_message().get("t") == "hosts", "hosts gemerkt")
	var lea := new_raw("Lea")
	check(wait_until(func(): return lea.id() > 0 and of_type(lea, "hosts").size() > 0), "Lea wartet und bekommt hosts nach welcome")
	check(host.is_waiting(lea.id()), "Lea wartet")
	pump(50)
	check(of_type(anna, "hosts").is_empty(), "App-Gast bekommt kein hosts")
	var wid := lea.id()
	inbox[lea].clear()
	check(host.assign_seat(wid, lisa_id), "Lea auf Lisas Platz")
	check(wait_until(func(): return of_type(lea, "hosts").size() > 0 and of_type(lea, "start").size() > 0), "start und hosts kommen an")
	var iw := index_of(lea, func(m): return m.get("t") == "welcome")
	var is_ := index_of(lea, func(m): return m.get("t") == "start")
	var ih := index_of(lea, func(m): return m.get("t") == "hosts")
	check(iw >= 0 and iw < is_ and is_ < ih, "Reihenfolge welcome → start → hosts (%d, %d, %d)" % [iw, is_, ih])
	var w: Dictionary = inbox[lea][iw] if iw >= 0 else {}
	check(w.get("assigned") == true and w.get("id") == lisa_id, "Browser: zweites welcome mit assigned")
	check(first_of(lea, "start").get("seat") == lisa_seat, "start mit Lisas Platz")
	check(lea.id() == lisa_id and lea.ws.get_ready_state() == WebSocketPeer.STATE_OPEN, "Browser-Gast sitzt auf Lisas Platz")
	check(str(host.player(lisa_id).kind) == "web" and host.hello_port(lisa_id) == 0, "Art web, kein hp")
	# Neue Liste geht an alle Browser-Gäste im WLAN
	inbox[lea].clear()
	host.send_hosts({"gid": GID, "gen": 5, "list": [], "online": "", "ap": true, "ap_name": "Anna"})
	check(wait_until(func(): return of_type(lea, "hosts").size() > 0), "neue hosts-Liste kommt an")
	var hm: Dictionary = first_of(lea, "hosts")
	check(hm.get("gen") == 5 and hm.get("ap") == true and hm.get("ap_name") == "Anna", "hosts-Inhalt %s" % str(hm))
	pump(50)
	check(of_type(anna, "hosts").is_empty(), "App-Gast bekommt weiterhin kein hosts")
	lea.ws.close()
	check(wait_until(func(): return not bool(host.player(lisa_id).connected)), "Lea getrennt")

# ---------- drain, zusätzliche Ursprünge ----------

func test_drain_and_origins() -> void:
	host.send_to(anna.my_id, {"t": "note", "text": "x".repeat(20000)})
	check(host.drain(500), "drain: alles hinaus")
	check(wait_until(func(): return of_type(anna, "note").size() > 0), "Nachricht nach drain angekommen")
	host.set_extra_origins(["http://192.168.1.5:24690", "http://192.168.1.5:24690", "", 7, "http://10.0.0.2:24691"])
	check(host.extra_origins() == ["http://192.168.1.5:24690", "http://10.0.0.2:24691"], "Ursprünge bereinigt %s" % str(host.extra_origins()))
	host.set_game_mark("", 0, "")
	check(host.welcome_extra.is_empty() and not host.info().has("gid"), "set_game_mark(\"\") leert die Kennung")
