extends SceneTree

# Beta 1.3.3: App-Wechsel im Mehrspieler (Nutzerbefund: Spieler wechseln kurz in andere Apps, z. B. Threema für Screenshots; Android
# hält das Spiel an, die Verbindung schläft ein, zurück im Spiel zeigte die App bis zu 70 s den alten Stand; beim Gastgeber stand
# „Computer spielt für Püppi“ – ein Knopf, der wie ein Zustand wirkte).
# Vermittler-Nachbau NetRelayDouble (TCP 24981), Gastgeber HostTable „Shakie“ (WLAN 24982), App-Gast „Püppi“ online über den Vermittler,
# App-Gast „Kim“ im WLAN. app_paused()/app_resumed() stehen für NOTIFICATION_APPLICATION_PAUSED/RESUMED (bzw. FOCUS_OUT/FOCUS_IN).
#  A  Püppi geht in eine andere App: „away“ kommt an, alle sehen away:true am Platz; nur Hinweis, Knopf erst nach sub_offer_ms;
#     nie automatische Vertretung; zurück → away weg, Püppi bekommt den vollen Stand.
#  B  Online still abgerissen, während Püppi weg war: zurück → binnen 5 s neu verbunden (Token) und voller Stand.
#  C  WLAN still abgerissen, während Kim weg war: dasselbe im WLAN.
#  D  Gastgeber geht in eine andere App: Gäste sehen host:true + away:true; zurück mit still toter Vermittler-Verbindung → binnen
#     5 s wieder online, Püppi meldet sich neu an (4012), away ist überall weg.
#  E  Lobby: away in der Lobby-Nachricht; ältere Gastgeber: away/back sind für sie unbekannte Typen (gehen an die Spielsteuerung,
#     die nur „act“ kennt).

const RELAY_PORT := 24981
const HOST_PORT := 24982
const BACK_LIMIT_MS := 5000

var failures := 0
var checks := 0
var relay: NetRelayDouble
var host: HostTable
var puppi: ClientTable
var kim: ClientTable


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)


func _initialize() -> void:
	relay = NetRelayDouble.new()
	relay.auto_poll = false
	check(relay.start(RELAY_PORT, RELAY_PORT) == OK, "Vermittler-Nachbau auf %d" % RELAY_PORT)
	run()
	for c in [puppi, kim]:
		if c != null:
			c.leave()
			c.free()
	if host != null:
		host.leave()
		host.free()
	relay.stop()
	relay.free()
	print("RESULT: %d ok" % checks if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)


func make_guest() -> ClientTable:
	var g := ClientTable.new()
	g.auto_process = false
	g.reuse_token = false
	g.persist_tokens = false
	g.retry_ms = [150, 300, 600, 800]
	return g


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
	puppi = make_guest()
	puppi.join(link, 0, "Püppi")
	kim = make_guest()
	kim.join("127.0.0.1", HOST_PORT, "Kim")
	check(wait_until(func(): return puppi.connection_state() == "open" and kim.connection_state() == "open" and host.session.players.size() == 3),
		"Püppi (online) und Kim (WLAN) angenommen")

	# ---------- E (Lobby): away in der Lobby-Nachricht
	puppi.client.app_paused()
	check(wait_until(func(): return lobby_away(kim.lobby, puppi.my_id)), "Lobby: Kim sieht Püppi „kurz in einer anderen App“")
	puppi.client.app_resumed()
	check(wait_until(func(): return not lobby_away(kim.lobby, puppi.my_id) and not host.session.is_away(puppi.my_id)), "Lobby: Püppi wieder da")
	check(not host.session.lobby_message().players.any(func(p): return p.has("away")), "Lobby: away nur, wenn jemand weg ist")

	check(host.start(4711), "Start")
	check(wait_until(func(): return not puppi.current_view().is_empty() and not kim.current_view().is_empty()), "beide Gäste haben einen Stand")
	var g := host.session.seat_of(puppi.my_id)
	var k := host.session.seat_of(kim.my_id)
	var h := host.host_seat

	# ---------- A: Püppi geht kurz in eine andere App
	var t0 := Time.get_ticks_msec()
	puppi.client.app_paused()
	check(puppi.client.app_away, "Püppi: away gemerkt")
	check(wait_until(func(): return host.session.is_away(puppi.my_id)), "Gastgeber bekommt „away“ (%d ms)" % (Time.get_ticks_msec() - t0))
	check(wait_until(func(): return seat_flag(kim.current_view(), g, "away")), "Kim sieht Püppi „kurz in einer anderen App“")
	check(seat_flag(host.current_view(), g, "away"), "Gastgeber-Tisch: Püppi away")
	check(seat_flag(kim.current_view(), h, "host") and not seat_flag(kim.current_view(), h, "away"), "Gastgeber-Eintrag host:true, nicht away")
	check(host.absent_seats() == [g] and host.substitutable_seats().is_empty(), "nur Hinweis „kurz in einer anderen App“, noch kein Knopf")
	host.sub_offer_ms = 300
	check(wait_until(func(): return host.substitutable_seats() == [g], 2000), "Knopf erst nach sub_offer_ms")
	host.sub_offer_ms = NetProtocol.SUB_OFFER_MS
	check(host.substitutable_seats().is_empty(), "mit 30 s wieder kein Knopf")
	# Nie automatisch vertreten, auch wenn auto_substitute_s an wäre und das Spiel auf Püppi wartete
	host.auto_substitute_s = 0.05
	host._waiting_seat = g
	host._wait_since = 0
	pump(100)
	check(not host.is_substituted(g), "Gast in einer anderen App wird nie automatisch vertreten")
	host.auto_substitute_s = 0.0
	host._waiting_seat = -1
	var before := puppi.view_rev
	t0 = Time.get_ticks_msec()
	puppi.client.app_resumed()
	check(wait_until(func(): return not host.session.is_away(puppi.my_id) and puppi.view_rev > before and not seat_flag(kim.current_view(), g, "away")),
		"Püppi zurück: away weg, voller Stand (%d ms)" % (Time.get_ticks_msec() - t0))
	check(host.absent_seats().is_empty(), "kein Hinweis mehr")
	# „back“ ohne vorheriges „away“ (z. B. verlorene Nachricht): trotzdem voller Stand nur für diesen Gast
	before = puppi.view_rev
	var kim_before := kim.view_rev
	puppi.client.send({"t": "back"})
	check(wait_until(func(): return puppi.view_rev > before), "„back“ ohne Änderung → Püppi bekommt den Stand")
	pump(100)
	check(kim.view_rev == kim_before, "… nur Püppi, nicht alle")

	# ---------- B: online still abgerissen, während Püppi weg war
	puppi.client.app_paused()
	check(wait_until(func(): return host.session.is_away(puppi.my_id)), "B: Püppi weg")
	var c := int(host.session.player(puppi.my_id).conn) - NetProtocol.RELAY_CONN_BASE
	check(relay.hang_guest(code, c) >= 0, "B: Püppis Socket hängt still")
	pump(300)
	var old_conn := int(host.session.player(puppi.my_id).conn)
	t0 = Time.get_ticks_msec()
	puppi.client.app_resumed()
	var back := wait_until(func(): return puppi.connection_state() == "open" and int(host.session.player(puppi.my_id).conn) != old_conn and same(puppi, g) and not host.session.is_away(puppi.my_id), 8000)
	var took := Time.get_ticks_msec() - t0
	print("  zurueck nach %d ms" % took)
	check(back and took < BACK_LIMIT_MS, "B: online nach stillem Abriss in %d ms neu verbunden und auf vollem Stand (< %d)" % [took, BACK_LIMIT_MS])
	check(int(host.session.relay.stats().get("ws_active", 0)) == 1, "B: nur noch eine Online-Verbindung")

	# ---------- C: WLAN still abgerissen, während Kim weg war
	kim.client.app_paused()
	check(wait_until(func(): return host.session.is_away(kim.my_id)), "C: Kim weg")
	host.session.server.mute_ws(int(host.session.player(kim.my_id).conn))
	pump(300)
	t0 = Time.get_ticks_msec()
	kim.client.app_resumed()
	var lost := false
	var end := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < end:
		pump(5)
		if kim.connection_state() == "connecting":
			lost = true
		if lost and kim.connection_state() == "open" and same(kim, k) and not host.session.is_away(kim.my_id):
			break
	took = Time.get_ticks_msec() - t0
	print("  zurueck nach %d ms" % took)
	check(lost and same(kim, k) and took < BACK_LIMIT_MS, "C: WLAN nach stillem Abriss in %d ms wieder auf vollem Stand (< %d)" % [took, BACK_LIMIT_MS])

	# ---------- D: Gastgeber geht in eine andere App
	host.session.app_paused()
	check(host.session.is_away(host.session.host_id), "D: Gastgeber away")
	check(wait_until(func(): return seat_flag(puppi.current_view(), h, "away") and seat_flag(kim.current_view(), h, "away")),
		"D: beide Gäste sehen „Shakie (Gastgeber) ist kurz in einer anderen App“")
	check(seat_flag(puppi.current_view(), h, "host"), "D: Gastgeber-Eintrag erkennbar (host:true)")
	check(relay.hang_host(code) >= 0, "D: Vermittler-Verbindung des Gastgebers hängt still")
	pump(300)
	t0 = Time.get_ticks_msec()
	host.session.app_resumed()
	check(not host.session.is_away(host.session.host_id), "D: Gastgeber wieder da")
	var host_back := wait_until(func(): return host.session.online_state() == "open" and Time.get_ticks_msec() - t0 > 50 and host.session.relay._resume_deadline < 0 and same(puppi, g), 9000)
	took = Time.get_ticks_msec() - t0
	print("  zurueck nach %d ms" % took)
	check(host_back and took < BACK_LIMIT_MS, "D: Gastgeber in %d ms wieder online, Püppi auf vollem Stand (< %d)" % [took, BACK_LIMIT_MS])
	check(wait_until(func(): return not seat_flag(puppi.current_view(), h, "away") and not seat_flag(kim.current_view(), h, "away")),
		"D: away beim Gastgeber überall weg")
	check(bool(host.session.player(puppi.my_id).connected) and host.substitutable_seats().is_empty(), "D: Püppi verbunden, keine Vertretung")

	# ---------- Vertrag
	check(NetProtocol.clean_client_message({"t": "away", "x": 1}) == {"t": "away"}, "away ohne Felder")
	var plan := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../docs/BETA1_PLAN.md").simplify_path())
	check(plan.contains("`{t:\"away\"}`") and plan.contains("`{t:\"back\"}`"), "Vertrag nennt away/back")


# ---------- Hilfen ----------

func lobby_away(l: Dictionary, id: int) -> bool:
	for p in l.get("players", []):
		if int(p.get("id", -1)) == id:
			return bool(p.get("away", false))
	return false


func seat_flag(v: Dictionary, seat: int, key: String) -> bool:
	for p in v.get("players", []):
		if int(p.get("seat", -1)) == seat:
			return bool(p.get(key, false))
	return false


func sig(v: Dictionary) -> Array:
	var counts := []
	for p in v.get("players", []):
		counts.append(int((p as Dictionary).get("count", -1)))
	return [int(v.get("turn", -1)), counts, int(v.get("draw_count", -1)), int(v.get("discard_count", -1)), str(v.get("phase", ""))]


func same(guest: ClientTable, seat: int) -> bool:
	return guest != null and guest.connection_state() == "open" and sig(guest.current_view()) == sig(host.game.view_for(seat))


func pump(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while true:
		relay.poll()
		host.pump()
		for c in [puppi, kim]:
			if c != null and c.client != null:
				c.pump()
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
