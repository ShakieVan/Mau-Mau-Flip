extends SceneTree

# Online-Spiel Ende-zu-Ende (docs/online/ENTWURF.md 6): HostTable + zwei ClientTables nur über den Vermittler-Nachbau
# (NetRelayDouble, TCP 24951), der Gastgeber zusätzlich im WLAN (24952). Lite-Gast über den echten Lader relay/public (Chrome
# headless: /?r=CODE → /info?room= → /c/<version>/?r=CODE), dann eine ganze Runde (Gäste und Gastgeber per MauBot), Lecktest auf
# allen empfangenen Ständen, ein Gast trennt und kommt mit Token wieder (Spiel wartet), der Gastgeber verliert den Vermittler und
# kehrt mit dem Raum-Token zurück (gleicher Raumcode, Gäste als dieselben Spieler), Ende mit „bye“ und Raum gelöscht.

const RELAY_PORT := 24951
const HOST_PORT := 24952
const CHROME := "C:/Program Files/Google/Chrome/Application/chrome.exe"

var failures := 0
var checks := 0
var relay: NetRelayDouble
var host: HostTable
var tables: Array = []
var received := {}
var leaks := []
var rng := RandomNumberGenerator.new()
var acted := {}
var acted_ms := {}
var host_states := 0
var chrome_pid := -1


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)


func _initialize() -> void:
	rng.seed = 4711
	relay = NetRelayDouble.new()
	relay.auto_poll = false
	relay.web_zip_path = pack_webclient()
	var pub := ProjectSettings.globalize_path("res://").path_join("../relay/public").simplify_path()
	if DirAccess.dir_exists_absolute(pub):
		relay.public_dir = pub
	check(relay.start(RELAY_PORT, RELAY_PORT) == OK, "Vermittler-Nachbau auf %d" % RELAY_PORT)
	run()
	if chrome_pid > 0:
		OS.kill(chrome_pid)
	for c in tables:
		c.leave()
		c.free()
	if host != null:
		host.leave()
		host.free()
	relay.stop()
	relay.free()
	print("RESULT: %d ok" % checks if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)


func run() -> void:
	host = HostTable.new()
	host.auto_process = false
	host.speed = 0.0
	host.use_discovery = false
	host.autosave = false
	host.state_changed.connect(func(_e: Array, _v: Dictionary) -> void: host_states += 1)
	check(host.open("Gastgeberin", HOST_PORT, HOST_PORT) == OK, "Gastgeber im WLAN")
	host.session.open_online("http://127.0.0.1:%d" % RELAY_PORT)
	check(wait_until(func(): return host.session.online_state() == "open"), "Online-Raum offen")
	var code := str(host.session.online_info().get("room", ""))
	var link := str(host.session.online_info().get("link", ""))
	check(code != "" and link.ends_with("/?r=" + code), "Raumcode %s, Link %s" % [code, link])
	# --- Lite über den Lader (wie beim Worker)
	lite(code)
	# --- zwei App-Gäste nur über den Vermittler (Raum-Link als Adresse, wie ClientTable aus QR/App-Link)
	var anna := new_client("Anna", link)
	var ben := new_client("Ben", link)
	check(wait_until(func(): return anna.connection_state() == "open" and ben.connection_state() == "open" and host.session.players.size() == 3),
		"zwei Online-Gäste angenommen (%s/%s, %d Spieler)" % [anna.connection_state(), ben.connection_state(), host.session.players.size()])
	check(anna.client.is_online() and ben.client.is_online(), "Gäste verbunden über den Vermittler")
	check(int(host.session.player(anna.my_id).conn) >= NetProtocol.RELAY_CONN_BASE, "Verbindungsnummer ab 1 000 000")
	check(wait_until(func(): return (anna.lobby.get("players", []) as Array).size() == 3), "Gast sieht drei Spieler")
	host.set_rules(RuleConfig.preset("offiziell"))
	check(host.start(4242), "Start")
	check(wait_until(func(): return received[anna] > 0 and received[ben] > 0), "beide Gäste bekommen state")
	# --- spielen, bis Anna dran ist; dann trennt sie und kommt mit Token wieder
	var t_end := Time.get_ticks_msec() + 30000
	var anna_seat := seat_of(anna)
	while Time.get_ticks_msec() < t_end and not (host.game.current_seat() == anna_seat and host.game.phase() in MauGame.PLAY_PHASES):
		play_step(anna)
		if host.game.phase() == "round_over":
			break
	if host.game.current_seat() == anna_seat and host.game.phase() != "round_over":
		var token := anna.token
		var anna_id := anna.my_id
		anna.leave()
		check(wait_until(func(): return not bool(host.game.connected[anna_seat])), "Gast trennt: Gastgeber merkt es, Platz bleibt")
		var rev_before := host.rev
		for i in 40:
			play_step(anna)
		check(host.game.current_seat() == anna_seat and host.rev == rev_before, "Spiel wartet auf den getrennten Gast")
		var anna2 := new_client("Anna", link, token)
		check(wait_until(func(): return anna2.connection_state() == "open" and received[anna2] > 0), "Gast kommt mit Token wieder")
		check(anna2.my_id == anna_id and anna2.local_seat() == anna_seat, "gleiche id und gleicher Platz")
		anna = anna2
	else:
		check(false, "Anna kam nicht an die Reihe")
	# --- Gastgeber verliert den Vermittler und kehrt mit dem Raum-Token zurück
	for c in tables:
		if c.client != null:
			c.client.host_away_ms = 300
	var r: NetRelayHost = host.session.relay
	r._ws.close()
	r._ws = null
	r._lost("Test")
	check(host.session.online_state() == "away", "Gastgeber kurz weg")
	check(wait_until(func(): return host.session.online_state() == "open", 8000), "Gastgeber wieder online (Raum-Token)")
	check(str(host.session.online_info().get("room", "")) == code, "derselbe Raumcode")
	var back := func() -> bool:
		return anna.connection_state() == "open" and ben.connection_state() == "open" and bool(host.game.connected[seat_of(anna)]) and bool(host.game.connected[seat_of(ben)])
	check(wait_until(back, 15000), "Gäste als dieselben Spieler zurück")
	# --- Rest der Runde
	t_end = Time.get_ticks_msec() + 90000
	var steps := 0
	while Time.get_ticks_msec() < t_end and host.game.phase() != "round_over":
		steps += 1
		play_step()
	check(host.game.phase() == "round_over", "Runde über den Vermittler zu Ende gespielt (%d Schritte)" % steps)
	check(wait_until(func(): return anna.last_rev == host.rev and ben.last_rev == host.rev), "Gäste haben den Endstand")
	check(leaks.is_empty(), "Lecktest: nur die eigene Sicht (%s)" % str(leaks.slice(0, 3)))
	check(received[anna] + received[ben] > 20, "genug Stände geprüft (%d)" % (received[anna] + received[ben]))
	check(int(host.session.relay.stats().get("rate_dropped", 0)) == 0, "keine verworfenen Nachrichten")
	# --- Ende: bye an alle, Raum beim Vermittler gelöscht
	host.session.finish("Der Gastgeber hat das Spiel beendet.")
	check(wait_until(func(): return anna.connection_state() == "closed" and ben.connection_state() == "closed", 5000), "Gäste bekommen bye")
	pump(200)
	check(relay.core.rooms.is_empty(), "Raum beim Vermittler gelöscht")


# Lite im Browser über den Lader relay/public (Chrome headless, Selbsttest tritt bei und meldet Bereit); danach wieder entfernt
func lite(code: String) -> void:
	if not FileAccess.file_exists(CHROME) or relay.public_dir == "" or relay.web_zip_path == "":
		print("HINWEIS: Chrome, relay/public oder webclient fehlt – Lite-Gast übersprungen")
		return
	var profile := ProjectSettings.globalize_path("user://game_online_test/chrome")
	DirAccess.make_dir_recursive_absolute(profile)
	chrome_pid = OS.create_process(CHROME, ["--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
		"--user-data-dir=" + profile, "--window-size=844,390", "http://127.0.0.1:%d/?r=%s&autotest=1" % [RELAY_PORT, code.to_lower()]])
	check(chrome_pid > 0, "Chrome gestartet")
	var ok := wait_until(func():
		for p in host.session.players.values():
			if str(p.kind) == "web" and bool(p.get("online", false)) and bool(p.ready):
				return true
		return false, 30000)
	check(ok, "Lite über Lader und /c/<version>/ beigetreten und bereit")
	OS.kill(chrome_pid)
	chrome_pid = -1
	for p in host.session.players.values():
		if str(p.kind) == "web":
			var id := int(p.id)
			wait_until(func(): return not bool(host.session.player(id).connected), 5000)
			host.session.remove_player(id)
			break
	pump(200)


func pack_webclient() -> String:
	var src := ProjectSettings.globalize_path("res://").path_join("../webclient").simplify_path()
	if not DirAccess.dir_exists_absolute(src):
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://game_online_test"))
	var zip_path := "user://game_online_test/web.zip"
	var z := ZIPPacker.new()
	if z.open(zip_path) != OK:
		return ""
	_pack_dir(z, src, "")
	z.close()
	return zip_path


func _pack_dir(z: ZIPPacker, dir: String, prefix: String) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".mp4"):
			continue
		z.start_file(prefix + f)
		z.write_file(FileAccess.get_file_as_bytes(dir.path_join(f)))
		z.close_file()
	for d in DirAccess.get_directories_at(dir):
		if d != "test":
			_pack_dir(z, dir.path_join(d), prefix + d + "/")


# ---------- Hilfen ----------

func new_client(player_name: String, link: String, token := "") -> ClientTable:
	var c := ClientTable.new()
	c.auto_process = false
	c.reuse_token = false
	c.persist_tokens = false
	c.retry_ms = [150, 300, 600, 800]
	c.ping_ms = 300
	received[c] = 0
	c.state_changed.connect(func(ev: Array, v: Dictionary) -> void:
		received[c] += 1
		check_message(ev, v))
	tables.append(c)
	c.join(link, 0, player_name, token)
	return c


func pump(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while true:
		step()
		if Time.get_ticks_msec() >= end:
			break
		OS.delay_msec(1)


func step() -> void:
	relay.poll()
	if host != null:
		host.pump()
	for c in tables:
		if c.client != null:
			c.pump()


func wait_until(cond: Callable, ms := 4000) -> bool:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		pump(2)
		if cond.call():
			return true
	return cond.call()


func seat_of(c: ClientTable) -> int:
	return host.session.seat_of(c.my_id)


func check_message(events: Array, view: Dictionary) -> void:
	var seat := int(view.get("seat", -1))
	var bad := ""
	for p in view.get("players", []):
		if (p as Dictionary).has("hand"):
			bad = "fremde Hand in players"
	for e in events:
		var d: Dictionary = e
		if str(d.get("e", "")) == "draw" and int(d.get("seat", -1)) != seat and (d.has("faces") or d.has("cards")):
			bad = "fremde gezogene Karten"
	var text := JSON.stringify(view) + JSON.stringify(events)
	if text.contains("rng_state") or text.contains("\"seed\""):
		bad = "Seed/Zufallszustand"
	if bad != "":
		leaks.append("%s (Platz %d)" % [bad, seat])


func play_once(t: TableSource, rev_now: int) -> void:
	var now := Time.get_ticks_msec()
	var last_ms: int = acted_ms.get(t, 0)
	if acted.get(t, -1) == rev_now and now - last_ms < 1000:
		return
	if t is ClientTable and now - last_ms < 70:
		return
	var v := t.current_view()
	if v.is_empty():
		return
	acted[t] = rev_now
	acted_ms[t] = now
	var a := MauBot.choose(v, rng.randi(), 1)
	if not a.is_empty():
		t.act(a)


func play_step(skip: ClientTable = null) -> void:
	step()
	for c in tables:
		if c.client != null and c != skip and c.connection_state() == "open":
			play_once(c, c.view_rev)
	play_once(host, host_states)
