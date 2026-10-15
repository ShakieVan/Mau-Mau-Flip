extends SceneTree

# Mau-Mau Flip (Beta 1.6.1, Gastgeber-Übergabe): gemeinsame Hilfen für test_takeover_online.gd und test_handover_online.gd.
# Jedes „Gerät“ ist ein Dev mit HostSwitch (zieht bei jedem Wechsel mit der Quelle um), eigener Datei und eigenem WLAN-Port; alles im
# selben Prozess, synchron gepumpt, Vermittler-Nachbau NetRelayDouble. Wanduhr der HostSwitches und NetClients ist einspritzbar
# (wall_off verschiebt sie), kurze Fristen als Eigenschaften. Browser-Gäste (kind "web") sind nackte NetClients wie Lite: Sie melden
# sich mit Token neu an (4012/4503) und kennen weder bk noch handover.
# Beta 1.6.2 (WLAN und Spiel-WLAN, docs/module/uebergabe.md 10.16): host_dev(…, online = false) eröffnet nur im WLAN (127.0.0.1),
# lan_guest() tritt dort bei (hello.hp = eigener Port, hello.ap aus Dev.ap), web_guest_lan() ist ein Browser-Gast im WLAN (bekommt
# hosts und move). kill_lan_closed()/kill_lan_still(): WLAN-Gastgeber fällt aus (Verbindung verweigert bzw. still, mute_ws). Der
# Vermittler-Nachbau ist optional (start_relay nur, wenn ein Test online braucht).

const BASE_PATH := "user://test_uebergabe_%s.json"

var failures := 0
var checks := 0
var relay: NetRelayDouble
var relay_port := 0
var relay_paused := false
var wall_off := 0
var devs: Array = []
var webs: Array = []           # [{c: NetClient, inbox: [], view: {}, seq, closed: []}]
var garbage: Array = []        # alte Quellen (nach einem Wechsel), am Ende freigeben
var rng := RandomNumberGenerator.new()
var _acted := {}               # Quelle bzw. NetClient -> [Sicht, ms], zu der zuletzt gehandelt wurde

# Fristen der Tests
var t_silent := 500
var t_away := 4000
var t_step := 1500
var probe := 500
var within := 3000
var disc_ports: Array = []      # Beta 1.6.2: UDP-Ports aller Gastgeber-Suchen (Wächter-Scan fragt alle, 127.0.0.1)


class Dev:
	extends RefCounted
	var name := ""
	var sw: HostSwitch
	var path := ""
	var port := 0
	var inbox: Array = []      # Nachrichten des Gastgebers (als Gast), roh
	var swaps: Array = []      # ["host"|"client", note]
	var dead := false
	var last_src: TableSource
	var bk := true
	var ap := {"ok": false, "perm": false}   # Beta 1.6.2: hello.ap dieses Geräts (kann ein Spiel-WLAN öffnen / erlaubt)
	var disc_port := 0         # Beta 1.6.2: eigener UDP-Port der Suche als Gastgeber (0 = keine Suche, Tests ohne UDP)

	func src() -> TableSource:
		return sw.source if sw != null and is_instance_valid(sw) and sw.source != null and is_instance_valid(sw.source) else null

	func ct() -> ClientTable:
		return src() as ClientTable

	func ht() -> HostTable:
		return src() as HostTable


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)
	mark(message)


func start_relay(port: int) -> void:
	relay_port = port
	relay = NetRelayDouble.new()
	relay.auto_poll = false
	relay.web_zip_path = ""
	check(relay.start(port, port) == OK, "Vermittler-Nachbau auf %d" % port)


func finish() -> void:
	for w in webs:
		(w.c as NetClient).close()
		(w.c as NetClient).free()
	webs.clear()
	for d in devs:
		var s: TableSource = d.src()
		if s is HostTable:
			(s as HostTable).autosave = false
			(s as HostTable).leave()
		elif s is ClientTable:
			(s as ClientTable).leave()
		if s != null:
			garbage.append(s)
		TableSource.clear_saved(d.path)
	for g in garbage:
		if is_instance_valid(g):
			if g is HostTable:
				(g as HostTable).autosave = false
			if g.get_parent() != null:
				g.get_parent().remove_child(g)
			g.free()
	garbage.clear()
	devs.clear()
	if relay != null:
		relay.stop()
		relay.free()
	print("RESULT: %d ok" % checks if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)


func wall() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0) + wall_off


# --- Geräte ---

func make_host() -> HostTable:
	var h := HostTable.new()
	h.auto_process = false
	h.speed = 0.0
	h.use_discovery = false
	h.settle_max_ms = 1500
	h.handover_timeout_ms = 2500
	h.alive_ms = 400
	return h


func make_client() -> ClientTable:
	var c := ClientTable.new()
	c.auto_process = false
	c.reuse_token = false
	c.persist_tokens = false
	c.retry_ms = [100, 200, 400]
	c.ping_ms = 300
	c.host_away_ms = 300
	return c


func _config(d: Dev) -> void:
	var sw := d.sw
	sw.auto_process = false
	sw.t_silent_ms = t_silent
	sw.t_away_ms = t_away
	sw.t_step_ms = t_step
	sw.probe_ms = probe
	sw.takeover_within_ms = within
	sw.join_wait_ms = 3000
	sw.wall_ms = wall
	sw.save_path = d.path
	sw.port_first = d.port
	sw.port_last = d.port
	sw.host_factory = func() -> HostTable: return _dev_host(d)
	sw.client_factory = func() -> ClientTable: return _dev_client(d)
	sw.swapped.connect(func(src: TableSource, note: String) -> void: _on_swap(d, src, note))


# Gastgeber-Tisch dieses Geräts (Beta 1.6.2): mit disc_port antwortet er auf die Suche und fragt im Wächter-Scan alle disc_ports
# (nur 127.0.0.1, kein Rundruf).
func _dev_host(d: Dev) -> HostTable:
	var h := make_host()
	if d.disc_port > 0:
		h.use_discovery = true
		h.discovery_port = d.disc_port
		h.scan_broadcast = false
		h.scan_probe_local = true
		h.scan_ports = disc_ports.filter(func(p): return int(p) != d.disc_port)
	return h


# Gast-Tisch dieses Geräts (auch nach einem Wechsel): hello.hp = eigener Port, hello.ap = Dev.ap (Beta 1.6.2)
func _dev_client(d: Dev) -> ClientTable:
	var c := make_client()
	c.listen_port = d.port
	c.ap_info = func() -> Dictionary: return d.ap
	return c


func _on_swap(d: Dev, src: TableSource, note: String) -> void:
	d.swaps.append(["host" if src is HostTable else "client", note])
	if d.last_src != null and d.last_src != src:
		garbage.append(d.last_src)
	d.last_src = src
	if src is ClientTable:
		_listen(d, src as ClientTable)


func _listen(d: Dev, ct: ClientTable) -> void:
	ct.host_message.connect(func(m: Dictionary) -> void: d.inbox.append(m))


# online = false (Beta 1.6.2): nur im WLAN (127.0.0.1:port), ohne Raum; disc_port > 0: Suche als Gastgeber auf diesem UDP-Port
func host_dev(dev_name: String, port: int, online := true, disc_port := 0) -> Dev:
	var d := Dev.new()
	d.name = dev_name
	d.path = BASE_PATH % dev_name
	d.port = port
	d.disc_port = disc_port
	TableSource.clear_saved(d.path)
	var h := _dev_host(d)
	h.save_path = d.path
	check(h.open(dev_name, port, port) == OK, "%s eröffnet (Port %d)" % [dev_name, port])
	if online:
		h.session.open_online(relay.base_url())
	d.sw = HostSwitch.ensure(h)
	d.last_src = h
	_config(d)
	devs.append(d)
	if online:
		check(wait_until(func(): return h.session.online_state() == "open"), "%s: Online-Raum offen" % dev_name)
	return d


# Beta 1.6.2: App-Gast im WLAN beim Gastgeber auf host_port (127.0.0.1); port = eigener Gastgeber-Port (hello.hp), ap = hello.ap.
func lan_guest(dev_name: String, host_port: int, port: int, with_bk := true, ap := {}) -> Dev:
	return guest_dev(dev_name, "127.0.0.1", port, with_bk, host_port, ap)


func guest_dev(dev_name: String, link: String, port: int, with_bk := true, join_port := 0, ap := {}) -> Dev:
	var d := Dev.new()
	d.name = dev_name
	d.path = BASE_PATH % dev_name
	d.port = port
	d.bk = with_bk
	if not ap.is_empty():
		d.ap = {"ok": ap.get("ok") == true, "perm": ap.get("perm") == true}
	TableSource.clear_saved(d.path)
	var ct := _dev_client(d)
	ct.backups = with_bk
	ct.backup_path = d.path
	d.sw = HostSwitch.ensure(ct)
	d.last_src = ct
	_config(d)
	ct.listen_port = d.port          # HostSwitch.ensure setzte noch den Standard-port_first
	_listen(d, ct)
	devs.append(d)
	ct.join(link, join_port, dev_name)
	return d


func web_guest(web_name: String, relay_url: String, code: String) -> Dictionary:
	var w := _web(web_name)
	(w.c as NetClient).connect_relay(relay_url, code, web_name, "web")
	return w


# Beta 1.6.2: Browser-Gast im WLAN (wie Lite: kind "web", ohne bk; bekommt hosts und move).
func web_guest_lan(web_name: String, host_port: int) -> Dictionary:
	var w := _web(web_name)
	(w.c as NetClient).connect_to("127.0.0.1", host_port, web_name, "web")
	return w


func _web(web_name: String) -> Dictionary:
	var c := NetClient.new()
	c.auto_poll = false
	c.reuse_token = false
	c.persist_tokens = false
	c.retry_ms = [100, 200, 400]
	c.ping_ms = 300
	c.host_away_ms = 300
	var w := {"c": c, "name": web_name, "inbox": [], "view": {}, "seq": 0, "closed": []}
	c.message.connect(func(m: Dictionary) -> void:
		(w.inbox as Array).append(m)
		if str(m.get("t", "")) == "state" and m.get("view") is Dictionary:
			w.view = m.view)
	c.closed.connect(func(t: String) -> void: (w.closed as Array).append(t))
	webs.append(w)
	return w


# Beta 1.6.2: letzte Nachricht vom Typ t ({} = keine).
func last_of(list: Array, t: String) -> Dictionary:
	for i in range(list.size() - 1, -1, -1):
		if str((list[i] as Dictionary).get("t", "")) == t:
			return list[i]
	return {}


func host_now() -> HostTable:
	for d in devs:
		if not d.dead and d.ht() != null and d.ht().session != null and d.ht().game != null:
			return d.ht()
	return null


# --- Pumpen ---

func step() -> void:
	if relay != null and not relay_paused:
		relay.poll()
	for d in devs.duplicate():
		if d.dead:
			continue
		var s: TableSource = d.src()
		if s is HostTable:
			(s as HostTable).pump()
		elif s is ClientTable:
			(s as ClientTable).pump()
		if is_instance_valid(d.sw):
			d.sw.pump()
	for w in webs:
		(w.c as NetClient).poll()


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


# Züge mit MauBot für alle Menschen (Gastgeber, App-Gäste, Browser-Gäste), bis moves Änderungen beim Gastgeber angekommen sind.
func play(moves: int, until_round_end := false) -> int:
	var done := 0
	var end := Time.get_ticks_msec() + (30000 if until_round_end else 8000)
	while (done < moves or until_round_end) and Time.get_ticks_msec() < end:
		pump(5)
		var h := host_now()
		if h == null or h.game == null or h.game.phase() == "game_over":
			break
		if h.game.phase() == "round_over":
			if until_round_end:
				return done
			break
		for d in devs:
			if d.dead:
				continue
			var t: TableSource = d.src()
			if t == null or (t is ClientTable and ((t as ClientTable).client == null or t.connection_state() != "open")):
				continue
			_act(t, t.current_view(), h)
		for w in webs:
			if (w.c as NetClient).state == "open" and not (w.view as Dictionary).is_empty():
				var a := MauBot.choose(w.view, rng.randi(), 1) if _may_act(w.c, w.view) else {}
				if not a.is_empty() and str(a.get("a", "")) != "next_round":
					w.seq = int(w.seq) + 1
					(w.c as NetClient).send({"t": "act", "seq": w.seq, "a": a})
		var before := h.rev
		pump(5)
		if h.rev != before:
			done += 1
	return done


# Je Stand höchstens eine Aktion (wie ein Mensch; sonst fluten abgelehnte Wiederholungen den Gastgeber-Socket über die Rate des
# Vermittlers, und er verwirft Stände).
func _act(t: TableSource, v: Dictionary, _h: HostTable) -> void:
	if v.is_empty() or not _may_act(t, v):
		return
	var a := MauBot.choose(v, rng.randi(), 1)
	if not a.is_empty() and str(a.get("a", "")) != "next_round":
		t.act(a)


# --- Prüfhilfen ---

func count(list: Array, t: String) -> int:
	return list.filter(func(m): return str(m.get("t", "")) == t).size()


# Jede Sicht nach der ersten Sicherung kommt erst nach einer Sicherung (bk seit der letzten Sicht) – Reihenfolge je Gast.
func bk_before_each_state(list: Array) -> bool:
	var seen_bk := false
	var fresh := false
	for m in list:
		match str(m.get("t", "")):
			"bk":
				seen_bk = true
				fresh = true
			"state":
				if seen_bk and not fresh:
					return false
				fresh = false
	return seen_bk


func seat_of_token(h: HostTable, token: String) -> int:
	for s in h.seats.size():
		if str(h.seats[s].get("token", "")) == token:
			return s
	return -1


func room_code() -> String:
	var h := host_now()
	return str(h.session.online_info().room) if h != null else ""


# Gastgeber „stirbt“: still (Socket hängt beim Vermittler, nichts kommt mehr) bzw. mit Schließen (Vermittler meldet 4503).
func kill_still(d: Dev) -> void:
	var code := room_code()
	check(relay.hang_host(code) >= 0, "%s: Socket hängt still" % d.name)
	d.dead = true


func kill_closed(d: Dev) -> void:
	var h := d.ht()
	d.dead = true
	h.autosave = false             # Datei bleibt, wie sie ist (Absturz)
	h.session.relay.close(false)   # wie beim Beenden der App: Socket zu, Raum bleibt (Gäste bekommen 4503)
	h.session.relay.poll()


# Beta 1.6.2: WLAN-Gastgeber stirbt mit Schließen – Server zu, Neuversuche der Gäste werden verweigert. Ohne Raum.
func kill_lan_closed(d: Dev) -> void:
	var h := d.ht()
	d.dead = true
	h.autosave = false
	if h.session.relay != null:
		h.session.relay.close(false)
		h.session.relay.poll()
	h.session.server.stop()


# Beta 1.6.2: WLAN-Gastgeber still tot – alle WLAN-Verbindungen stumm (der Server-Thread beantwortet auch kein ping mehr), nichts wird
# geschlossen; die Hauptschleife läuft nicht mehr (dead).
func kill_lan_still(d: Dev) -> void:
	var h := d.ht()
	d.dead = true
	h.autosave = false
	for p in h.session.players.values():
		var conn := int(p.get("conn", -1))
		if conn >= 0 and conn < NetProtocol.RELAY_CONN_BASE:
			h.session.server.mute_ws(conn)
	h.session.server.poll()


# Zu dieser Sicht noch nicht gehandelt – oder es ist 400 ms her (abgelehnt, z. B. in der Einschwingzeit, ohne neuen Stand).
func _may_act(key: Object, v: Dictionary) -> bool:
	var last: Array = _acted.get(key, [null, 0])
	var now := Time.get_ticks_msec()
	if is_same(last[0], v) and now - int(last[1]) < 400:
		return false
	_acted[key] = [v, now]
	return true


# Zeitmarken (nur mit DEBUG_UEBERGABE): wo die Zeit eines Falls bleibt
var _mark_ms := 0
func mark(label: String) -> void:
	if OS.get_environment("DEBUG_UEBERGABE") == "":
		return
	var now := Time.get_ticks_msec()
	print("  [%5d ms] %s" % [now - _mark_ms if _mark_ms > 0 else 0, label])
	_mark_ms = now
