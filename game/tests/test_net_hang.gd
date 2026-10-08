extends SceneTree

# Beta 1.3.3: still abreißende Online-Verbindungen (Nutzerbefund 1.3.2, zwei Menschen über den echten Vermittler: Shakie bekam +1,
# zog, zog freiwillig, behielt – bei ihm war danach Püppi dran, bei Püppi noch Shakie; erst nach über einer Minute renkte es sich ein).
# Vermittler-Nachbau NetRelayDouble (TCP 24971), Gastgeber HostTable (WLAN 24972) und App-Gast „Püppi“ nur über den Vermittler.
# hang_host/hang_guest lassen einen Socket hängen (offen, aber nichts kommt mehr an oder zurück, auch kein „pong“, kein Close).
# Die Fristen sind die echten (NetProtocol: Herzschlag 10 s, Stille 25 s, Prüfung 6 + 4 s nach eigenem Senden).
#  A  Gastgeber hängt genau in der Abfolge des Befunds (+1 von Püppi, Strafziehen und weiterspielen, freiwillig ziehen, behalten):
#     erkannt binnen ~10 s, Zustand „away“ (Hinweis am Tisch), Püppi gilt beim Gastgeber nicht als gegangen (keine Vertretung, keine
#     Rückfrage), Rückkehr mit Raum-Token, 4012 an Püppis alte Verbindung, Püppi meldet sich neu an → beide Seiten gleich.
#  B  Gast hängt und legt eine Karte: erkannt binnen ~10 s, Hinweis „Verbindung zum Gastgeber unterbrochen – warte …“, neu verbunden
#     mit Token, beide Seiten gleich, danach geht die Partie normal weiter.
#  C  4503 (Gastgeber kurz weg) → Hinweis „Gastgeber kurz weg – warte …“; Konstanten und Vertrag.

const RELAY_PORT := 24971
const HOST_PORT := 24972

var failures := 0
var checks := 0
var relay: NetRelayDouble
var host: HostTable
var guest: ClientTable


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)


func _initialize() -> void:
	relay = NetRelayDouble.new()
	relay.auto_poll = false
	check(relay.start(RELAY_PORT, RELAY_PORT) == OK, "Vermittler-Nachbau auf %d" % RELAY_PORT)
	_constants()
	run()
	if guest != null:
		guest.leave()
		guest.free()
	if host != null:
		host.leave()
		host.free()
	relay.stop()
	relay.free()
	print("RESULT: %d ok" % checks if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)


func _constants() -> void:
	check(NetProtocol.RELAY_PING_MS == 10000 and NetProtocol.RELAY_TIMEOUT_MS == 25000, "Online-Herzschlag 10 s, Stille 25 s")
	check(NetProtocol.RELAY_PROBE_AFTER_MS == 6000 and NetProtocol.RELAY_PROBE_WAIT_MS == 4000, "Prüfung nach eigenem Senden 6 + 4 s")
	check(NetProtocol.CLOSE_RESYNC == 4012 and NetProtocol.CLOSE_RESYNC != NetWs.CLOSE_TIMEOUT, "4012 = neu anmelden")
	var netz := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../webclient/netz.js").simplify_path())
	check(netz.contains("ONLINE_PING = 10000") and netz.contains("ONLINE_STILL = 25000") and netz.contains("ev.code === 4012"),
		"Lite: gleiche Fristen, 4012 sofort neu")


func run() -> void:
	host = HostTable.new()
	host.auto_process = false
	host.speed = 0.0
	host.use_discovery = false
	host.autosave = false
	check(host.open("Shakie", HOST_PORT, HOST_PORT) == OK, "Gastgeber offen")
	host.session.open_online("http://127.0.0.1:%d" % RELAY_PORT)
	check(wait_until(func(): return host.session.online_state() == "open"), "Online-Raum offen")
	var code := str(host.session.online_info().get("room", ""))
	var link := str(host.session.online_info().get("link", ""))
	guest = ClientTable.new()
	guest.auto_process = false
	guest.reuse_token = false
	guest.persist_tokens = false
	guest.retry_ms = [150, 300, 600, 800]
	guest.join(link, 0, "Püppi")
	check(wait_until(func(): return guest.connection_state() == "open" and host.session.players.size() == 2), "Püppi online angenommen")
	guest.client.host_away_ms = 300
	var rules := RuleConfig.new()
	rules.apply_dict({"stacking": "same", "penalty_turn": "play", "draw_play": "any"})
	host.set_rules(rules)
	check(host.start(4711), "Start")
	check(wait_until(func(): return not guest.current_view().is_empty()), "Püppi hat einen Stand")
	var g := 1 - host.host_seat
	var h := host.host_seat
	# Gezielte Lage: Püppi ist dran und hat +1; Shakie hat nichts Passendes
	var hands := [[], []]
	hands[g] = ["hell_rot_plus1", "hell_rot_1", "hell_gelb_5"]
	hands[h] = ["hell_blau_3", "hell_gelb_4", "hell_gruen_6"]
	var game := RulesFixture.build(rules, 2, {"hands": hands, "top": "hell_rot_5", "current": g,
		"draw": ["hell_blau_4", "hell_gruen_8", "hell_blau_9", "hell_gelb_2"]})
	for s in 2:
		game.set_connected(s, true)
	host.game = game
	host._changed([])
	check(wait_until(func(): return same(g)), "Ausgangslage auf beiden Seiten gleich")

	# ---------- A: Gastgeber hängt (Abfolge des Befunds)
	guest.act({"a": "play", "card": RulesFixture.card(host.game, g, "hell_rot_plus1")})
	check(wait_until(func(): return host.game.current_seat() == h and same(g)), "Püppi legt +1, Shakie ist dran")
	var host_sock := relay.hang_host(code)
	check(host_sock >= 0, "Gastgeber-Socket hängt")
	var t0 := Time.get_ticks_msec()
	host.act({"a": "draw"})                  # Strafe nehmen (gestapelt möglich, also selbst ziehen)
	pump(50)
	check(host.game.current_seat() == h, "Strafziehen und weiterspielen: Shakie bleibt dran")
	host.act({"a": "draw"})                  # freiwillig ziehen
	pump(50)
	host.act({"a": "keep"})                  # behalten
	pump(50)
	check(host.game.current_seat() == g and host.game.hands[h].size() == 5, "beim Gastgeber ist Püppi dran (Shakie 5 Karten)")
	check(guest.current_view().get("turn", -1) == h, "bei Püppi noch Shakie dran (der Abriss)")
	var away := wait_until(func(): return host.session.online_state() == "away", 13000)
	var took := Time.get_ticks_msec() - t0
	check(away and took <= 11500, "Gastgeber erkennt den Abriss nach %d ms (Frist 6 + 4 s nach eigenem Senden)" % took)
	check(host.session.relay.state == "away", "Zustand away → Hinweis „Online-Verbindung unterbrochen – verbinde neu …“")
	var pid := id_at(g)
	check(bool(host.session.player(pid).connected) and bool(host.game.connected[g]), "Püppi gilt beim Gastgeber nicht als gegangen")
	check(host.substitutable_seats().is_empty() and host.waiting_seat() == -1, "keine Vertretung, keine Rückfrage")
	check(wait_until(func(): return host.session.online_state() == "open", 8000), "Gastgeber wieder online (Raum-Token)")
	check(bool(host.session.player(pid).connected), "auch nach der Rückkehr kein „gegangen“ während Püppi neu anmeldet")
	check(wait_until(func(): return same(g), 8000), "beide Seiten wieder gleich (%s / %s)" % [str(sig_guest()), str(sig_host(g))])
	check(guest.current_view().get("turn", -1) == g and int(players(guest.current_view())[h].count) == 5, "Püppi ist dran, Shakie 5 Karten")
	check(host.session.player(pid).connected and guest.my_id == pid, "Püppi als dieselbe Spielerin zurück")
	check(int(host.session.relay.stats().get("ws_active", 0)) == 1, "nur noch eine Online-Verbindung")

	# ---------- B: Gast hängt und legt eine Karte
	var c := int(host.session.player(pid).conn) - NetProtocol.RELAY_CONN_BASE
	check(relay.hang_guest(code, c) >= 0, "Gast-Socket hängt")
	var hint_seen := false
	t0 = Time.get_ticks_msec()
	guest.act({"a": "play", "card": RulesFixture.card(host.game, g, "hell_rot_1")})
	var lost := false
	var end := Time.get_ticks_msec() + 13000
	while Time.get_ticks_msec() < end:
		pump(5)
		if guest.connection_state() == "connecting":
			lost = true
			hint_seen = guest.connection_hint() == "Verbindung zum Gastgeber unterbrochen – warte …"
			break
	took = Time.get_ticks_msec() - t0
	check(lost and took <= 11500, "Gast erkennt den Abriss nach %d ms" % took)
	check(hint_seen, "Hinweis „Verbindung zum Gastgeber unterbrochen – warte …“")
	check(host.game.current_seat() == g, "die verlorene Aktion kam nicht an: Püppi bleibt dran")
	check(wait_until(func(): return guest.connection_state() == "open" and same(g), 8000), "neu verbunden, beide Seiten gleich")
	guest.act({"a": "play", "card": RulesFixture.card(host.game, g, "hell_rot_1")})
	check(wait_until(func(): return host.game.current_seat() == h and same(g)), "danach geht es normal weiter")

	# ---------- C: 4503 → eigener Hinweis
	guest.client.host_away = true
	check(guest.connection_hint() == "Gastgeber kurz weg – warte …", "Hinweis bei 4503")
	guest.client.host_away = false


# ---------- Hilfen ----------

func id_at(seat: int) -> int:
	return host.session.id_at_seat(seat)


func players(v: Dictionary) -> Array:
	return v.get("players", []) as Array


func sig(v: Dictionary) -> Array:
	var counts := []
	for p in players(v):
		counts.append(int((p as Dictionary).get("count", -1)))
	return [int(v.get("turn", -1)), counts, int(v.get("draw_count", -1)), int(v.get("discard_count", -1)), str(v.get("phase", ""))]


func sig_guest() -> Array:
	return sig(guest.current_view())


func sig_host(seat: int) -> Array:
	return sig(host.game.view_for(seat))


func same(seat: int) -> bool:
	return guest != null and guest.connection_state() == "open" and sig_guest() == sig_host(seat)


func pump(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while true:
		relay.poll()
		host.pump()
		if guest != null and guest.client != null:
			guest.pump()
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
