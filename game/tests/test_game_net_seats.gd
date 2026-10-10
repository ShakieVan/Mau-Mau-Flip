extends SceneTree
# Beta 1.4.2: Mitspieler mitten im Netzspiel dazuholen und entfernen (HostTable.seat_in/add_bot_at/remove_seat, NetHostSession-
# Warteliste, docs/module/dazuholen.md). Vermittler-Nachbau NetRelayDouble (TCP 24985), Gastgeber „Shakie“ (WLAN 24986), App-Gast
# „Kim“ im WLAN von Anfang an, App-Gast „Püppi“ online über den Vermittler mitten in der Partie.
#  A  Einladen zu: Püppi wird mit „running“ abgelehnt.
#  B  Einladen offen: Püppi landet auf der Warteliste ({t:"lobby", late, waiting}), sieht keinen Tisch.
#  C  seat_in während einer offenen Farbwahl wartet („nach diesem Zug“), danach: Püppi bekommt start und einen Stand mit dem richtigen
#     view.seat und so vielen Karten wie die größte Hand; Kim rückt einen Platz weiter, Ereignisse seats und draw (reason join).
#     Platznummern passen: Ereignisse in alter Nummerierung stehen nie mit seats in einer Nachricht.
#  D  Püppi in einer anderen App: Vertretung und Herausnehmen sofort (substitutable_seats ohne Wartezeit).
#  E  remove_seat: Püppi bekommt „bye“, Kim rückt zurück, die Karten liegen unter dem Ziehstapel.
#  F  Püppi kommt mit dem alten Token wieder: nur über die Warteliste (neue id), niedrigster Punktestand.
#  G  Ablehnen von der Warteliste („bye“), Einladen wieder zu → „running“.
#  H  Computergegner dazu und wieder heraus; zuletzt Kim heraus → nur noch der Gastgeber: Partie vorbei (Grund left).

const RELAY_PORT := 24985
const HOST_PORT := 24986

var failures := 0
var checks := 0
var relay: NetRelayDouble
var host: HostTable
var kim: ClientTable
var guests: Array = []
var kim_msgs: Array = []         # je Stand die Ereignisse bei Kim


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
	for c in guests:
		if c != null and is_instance_valid(c):
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
	guests.append(g)
	return g


func names(v: Dictionary) -> Array:
	var out: Array = []
	for p in v.get("players", []):
		out.append(str(p.get("name", "")))
	return out


func ev_names(ev: Array) -> Array:
	var out: Array = []
	for e in ev:
		out.append(str((e as Dictionary).get("e", "")))
	return out


func run() -> void:
	host = HostTable.new()
	host.auto_process = false
	host.speed = 0.0
	host.use_discovery = false
	host.autosave = false
	check(host.open("Shakie", HOST_PORT, HOST_PORT) == OK, "Gastgeber offen")
	host.session.open_online("http://127.0.0.1:%d" % RELAY_PORT)
	check(wait_until(func(): return host.session.online_state() == "open"), "Online-Raum offen")
	var link := str(host.session.online_info().get("link", ""))
	kim = make_guest()
	kim.join("127.0.0.1", HOST_PORT, "Kim")
	check(wait_until(func(): return kim.connection_state() == "open" and host.session.players.size() == 2), "Kim angenommen")
	kim.state_changed.connect(func(ev: Array, _v: Dictionary) -> void: kim_msgs.append(ev))
	var cfg := RuleConfig.new()
	cfg.scoring = "points500"
	host.set_rules(cfg)
	check(host.start(4711), "Start zu zweit")
	check(wait_until(func(): return not kim.current_view().is_empty()), "Kim hat einen Stand")
	check(host.host_seat == 0 and kim.local_seat() == 1, "Shakie Platz 0, Kim Platz 1")

	# ---------- A: Einladen zu
	var p1 := make_guest()
	p1.join(link, 0, "Püppi")
	check(wait_until(func(): return p1.connection_state() == "rejected"), "A: ohne offenes Einladen „running“")
	check(host.session.players.size() == 2 and host.waiting_ids().is_empty(), "A: niemand wartet")

	# ---------- B: Warteliste
	host.set_join_open(true)
	var puppi := make_guest()
	puppi.join(link, 0, "Püppi")
	check(wait_until(func(): return puppi.waiting and host.waiting_ids().size() == 1), "B: Püppi auf der Warteliste")
	check(bool(puppi.lobby.get("late", false)) and str(puppi.lobby.get("host_name", "")) == "Shakie" and puppi.local_seat() == -1
		and puppi.current_view().is_empty(), "B: Warte-Lobby (late, host_name), kein Tisch")
	var pid: int = host.waiting_ids()[0]
	check(host.session.seat_of(pid) == -1 and not host.session.ordered_ids().has(pid), "B: ohne Platz in der Sitzung")
	var wl: Array = host.session.lobby_message().players.filter(func(p): return bool(p.get("waiting", false)))
	check(wl.size() == 1 and int(wl[0].id) == pid, "B: Lobby-Liste markiert den Wartenden")
	pump(100)
	check(kim.current_view().get("players", []).size() == 2, "B: am Tisch noch zu zweit")

	# ---------- C: aufgeschoben während einer Farbwahl, dann an Platz 1 (zwischen Shakie und Kim)
	var hand_most := 0
	for s in 2:
		hand_most = maxi(hand_most, (host.game.hands[s] as Array).size())
	host.game.state = "color"           # gebaute Lage: Farbwahl offen (kein Bot am Tisch, niemand handelt)
	kim_msgs.clear()
	check(host.seat_in(pid, 1), "C: Auftrag angenommen")
	check(host.pending_seat_ops().size() == 1 and host.seat_op_of(pid) == "in" and host.game.players.size() == 2,
		"C: wartet bis nach diesem Zug")
	check(not host.seat_in(pid, 1), "C: kein zweiter Auftrag für denselben Gast")
	host.game.state = "turn"
	host._changed([])                   # nächste Änderung: jetzt geht es
	check(host.pending_seat_ops().is_empty() and host.game.players.size() == 3, "C: ausgeführt")
	check(wait_until(func(): return not puppi.waiting and puppi.local_seat() == 1 and int(puppi.current_view().get("seat", -1)) == 1),
		"C: Püppi bekommt start und view.seat 1")
	check((puppi.current_view().get("hand", []) as Array).size() == clampi(hand_most, 1, 7), "C: Karten = größte Hand (%d)" % hand_most)
	check(wait_until(func(): return kim.local_seat() == 2 and names(kim.current_view()) == ["Shakie", "Püppi", "Kim"]),
		"C: Kim rückt auf Platz 2 (%s)" % str(names(kim.current_view())))
	var seen_seats := false
	var seen_join := false
	for ev in kim_msgs:
		var en := ev_names(ev)
		var at := en.find("seats")
		if at >= 0:
			seen_seats = true
			for i in at:
				check(en[i] in ["leave_cards", "color", "finish"], "C: vor seats nur Ereignisse des Auftrags (%s)" % str(en))
		for e in ev:
			if str(e.get("e", "")) == "draw" and str(e.get("reason", "")) == "join":
				seen_join = int(e.seat) == 1 and not (e as Dictionary).has("faces")
	check(seen_seats and seen_join, "C: Kim sieht seats und draw (join, ohne Gesichter)")
	check(host.session.seat_of(pid) == 1 and host.session.seat_of(kim.my_id) == 2, "C: Sitzung kennt die neuen Plätze")
	check(int(host.game.scores[1]) == 0, "C: Punkte wie der niedrigste Stand")

	# ---------- D: Vertretung und Herausnehmen sofort
	puppi.client.app_paused()
	check(wait_until(func(): return host.is_away(1)), "D: Püppi in einer anderen App")
	check(host.absent_seats() == [1] and host.substitutable_seats() == [1], "D: sofort beide Möglichkeiten")
	puppi.client.app_resumed()
	check(wait_until(func(): return not host.is_away(1)), "D: wieder da")

	# ---------- E: herausnehmen
	var old_token := puppi.token
	var cards := (host.game.hands[1] as Array).duplicate()
	cards.sort()
	kim_msgs.clear()
	check(host.remove_seat(1), "E: Auftrag")
	check(host.game.players.size() == 2 and host.pending_seat_ops().is_empty(), "E: sofort (zwischen zwei Zügen)")
	var bottom: Array = host.game.draw_pile.slice(0, cards.size())
	bottom.sort()
	check(bottom == cards, "E: Karten unter dem Ziehstapel")
	check(wait_until(func(): return puppi.connection_state() == "closed"), "E: Püppi bekommt bye (%s)" % puppi.connection_state())
	check(wait_until(func(): return kim.local_seat() == 1 and names(kim.current_view()) == ["Shakie", "Kim"]), "E: Kim wieder Platz 1")
	check(not host.session.players.has(pid), "E: Püppi aus der Sitzung")
	var left_ok := false
	for ev in kim_msgs:
		if ev_names(ev).has("leave_cards") and ev_names(ev).has("seats"):
			left_ok = true
	check(left_ok, "E: Kim sieht leave_cards und seats")
	pump(1500)
	check(puppi.connection_state() == "closed" and host.session.players.size() == 2, "E: Püppi verbindet nicht neu")

	# ---------- F: Wiederkommen mit altem Token nur über die Warteliste
	host.game.scores[0] = 30
	host.game.scores[1] = 12
	var back := make_guest()
	back.join(link, 0, "Püppi", old_token)
	check(wait_until(func(): return back.waiting and host.waiting_ids().size() == 1), "F: alter Token → Warteliste")
	var pid2: int = host.waiting_ids()[0]
	check(pid2 != pid, "F: neue Spieler-id")
	check(host.seat_in(pid2, 2), "F: an Platz 2 (hinter Kim)")
	check(wait_until(func(): return back.local_seat() == 2 and not back.current_view().is_empty()), "F: am Tisch")
	check(int(host.game.scores[2]) == 12, "F: niedrigster Stand (12)")
	# Platz 2 sitzt hinter Kim: ist Kim dran, kommt Püppi als Nächste
	if host.game.current_seat() == 0:
		host.act({"a": "draw"})
		if host.game.phase() == "drawn":
			host.act({"a": "keep"})
	check(wait_until(func(): return host.game.current_seat() == 1 and int(kim.current_view().get("turn", -1)) == 1), "F: Kim ist dran")
	kim.act({"a": "draw"})
	check(wait_until(func(): return host.game.current_seat() != 1 or host.game.phase() == "drawn"), "F: Kim zieht")
	if host.game.phase() == "drawn":
		kim.act({"a": "keep"})
	check(wait_until(func(): return host.game.current_seat() == 2 and int(back.current_view().get("turn", -1)) == 2),
		"F: Püppi direkt hinter Kim ist als Nächste dran")

	# ---------- G: Ablehnen und Einladen zu
	var other := make_guest()
	other.join("127.0.0.1", HOST_PORT, "Ole")
	check(wait_until(func(): return other.waiting), "G: Ole wartet")
	host.reject_waiting(host.waiting_ids()[0])
	check(wait_until(func(): return other.connection_state() == "closed") and host.waiting_ids().is_empty(), "G: abgelehnt (bye)")
	host.set_join_open(false)
	var late := make_guest()
	late.join("127.0.0.1", HOST_PORT, "Zoe")
	check(wait_until(func(): return late.connection_state() == "rejected"), "G: Einladen zu → running")

	# ---------- H: Computergegner dazu und heraus; zuletzt Kim heraus
	check(host.add_bot_at(1), "H: Computergegner an Platz 1")
	check(wait_until(func(): return host.game.players.size() == 4 and str(host.seats[1].kind) == "bot"), "H: Computer sitzt")
	check(host.is_bot(1) and host._seat_ids.size() == 4 and host.session.ordered_ids() == host._seat_ids, "H: Plätze stimmen überein")
	pump(300)                             # Computergegner spielt, falls er dran ist
	var bot_seat := -1
	for s in host.seats.size():
		if str(host.seats[s].kind) == "bot":
			bot_seat = s
	check(bot_seat >= 0 and host.remove_seat(bot_seat), "H: Computergegner heraus (Auftrag)")
	check(wait_until(func(): return host.game.players.size() == 3), "H: Computergegner weg")
	check(host.remove_seat(host._seat_ids.find(back.my_id)), "H: Püppi heraus")
	check(wait_until(func(): return host.game.players.size() == 2), "H: zu zweit")
	check(host.remove_seat(host._seat_ids.find(kim.my_id)), "H: Kim heraus")
	check(wait_until(func(): return host.game != null and host.game.is_over()), "H: Partie vorbei")
	var v := host.current_view()
	check(str((v.get("result", {}) as Dictionary).get("reason", "")) == "left" and str(v.hints.text).begins_with("Zu wenige Spieler"),
		"H: Grund left (%s)" % str(v.hints.text))
	check(not host.remove_seat(0), "H: Gastgeber nie")
	host.back_to_lobby()
	check(host.session.players.size() == 1, "H: Lobby nur mit dem Gastgeber")


func pump(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while true:
		relay.poll()
		host.pump()
		for c in guests:
			if c != null and is_instance_valid(c) and c.client != null:
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
