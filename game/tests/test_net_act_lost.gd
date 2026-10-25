extends SceneTree
# Beta 1.6.16 (Nutzerbefund 25.10.2026, Online-Spiel: Joker mit Türkis lag oben, der Mitspieler meinte, er habe eine 4 gelegt; am selben
# Tag häufige Verbindungsabbrüche): verlorene Aktionen eines App-Gasts. Echter Gast-Tisch (TableScreen mit HandView) an einem
# ClientTable, Gastgeber HostTable ohne Oberfläche, echte Fristen (HandView 4 s, ClientTable.ACT_CHECK_MS, NetClient 3 s).
#  A  Online (Vermittler-Nachbau), Gast-Socket hängt nach dem Legen still: Karte verlässt die Hand, nach 4 s ist sie zurück und die
#     Verbindungsprüfung ist angestoßen; nach der neuen Anmeldung die Meldung „Deine Karte kam nicht beim Gastgeber an …“ (als Fehler),
#     beim Gastgeber kam nichts an. Noch einmal legen geht durch, ohne weitere Meldung.
#  B  Online, Antwort kommt nur spät (Gastgeber 5,5 s angehalten, danach zuerst ein älterer Stand ohne Quittung): keine Meldung, die
#     Karte liegt danach regulär auf der Ablage.
#  C  WLAN, Gast-Socket hängt nach dem Tipp auf den Ziehstapel: Meldung „Dein Ziehen kam nicht beim Gastgeber an …“, Stapel wieder
#     antippbar, beim Gastgeber nichts gezogen; erneut tippen zieht.
#  Außerdem: Der Gastgeber-Tisch sendet act_lost nie; englische Texte vorhanden.
#   godot_run.ps1 -Script res://tests/test_net_act_lost.gd -Headless -Timeout 150

const CleanExit := preload("res://tests/clean_exit.gd")
const RELAY_PORT := 24985
const HOST_PORT := 24986
const WLAN_PORT := 24987
const LOST_CARD := "Deine Karte kam nicht beim Gastgeber an – sie ist wieder in deiner Hand. Leg sie noch einmal."
const LOST_DRAW := "Dein Ziehen kam nicht beim Gastgeber an – tipp noch einmal auf den Stapel."
const LOST_OTHER := "Deine Aktion kam nicht beim Gastgeber an – bitte noch einmal."

var ok := 0
var failed := false
var relay: NetRelayDouble
var host: HostTable
var guest: ClientTable
var nav: ScreenNav
var ts: TableScreen
var host_lost := 0
var g := 1
var h := 0


func _initialize() -> void:
	call_deferred("run")


func check(cond: bool, what: String) -> void:
	if cond:
		ok += 1
	else:
		failed = true
		print("FAIL: " + what)


func frames(n := 2) -> void:
	for i in n:
		await process_frame


func wait(t: float) -> void:
	await create_timer(t).timeout


func _wait_for(cond: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not bool(cond.call()) and Time.get_ticks_msec() < deadline:
		await frames(1)
	return bool(cond.call())


func run() -> void:
	GameStarter.test_speed = 0.0
	root.size = Vector2i(1600, 720)
	nav = ScreenNav.new()
	nav.autostart = false
	root.add_child(nav)
	await frames(2)
	texts()
	relay = NetRelayDouble.new()
	root.add_child(relay)
	check(relay.start(RELAY_PORT, RELAY_PORT) == OK, "Vermittler-Nachbau auf %d" % RELAY_PORT)
	if await setup(true):
		await lost_play()
		await late_answer()
	await teardown()
	if await setup(false):
		await lost_draw()
	await teardown()
	check(host_lost == 0, "Gastgeber-Tisch sendet act_lost nie")
	relay.stop()
	print("RESULT: %d ok" % ok if not failed else "FAIL: test_net_act_lost (%d ok)" % ok)
	await CleanExit.finish(self, 1 if failed else 0)


func texts() -> void:
	I18n.set_language("en")
	check(I18n.t(LOST_CARD) == "Your card didn't reach the host – it's back in your hand. Play it again.", "Englisch: Karte")
	check(I18n.t(LOST_DRAW) == "Your draw didn't reach the host – tap the draw pile again.", "Englisch: Ziehen")
	check(I18n.t(LOST_OTHER) == "Your move didn't reach the host – please try again.", "Englisch: sonstige Aktion")
	I18n.set_language("de")


# Gastgeber (online über den Vermittler-Nachbau bzw. nur WLAN), Gast am echten Tisch, Ausgangslage: Gast ist dran.
func setup(online: bool) -> bool:
	host = HostTable.new()
	host.speed = 0.0
	host.use_discovery = false
	host.autosave = false
	host.act_lost.connect(func(_a: Array) -> void: host_lost += 1)
	root.add_child(host)
	var port := HOST_PORT if online else WLAN_PORT
	check(host.open("Shakie", port, port) == OK, "Gastgeber offen (%s)" % ("online" if online else "WLAN"))
	var link := ""
	if online:
		host.session.open_online(relay.base_url())
		check(await _wait_for(func() -> bool: return host.session.online_state() == "open", 5.0), "Online-Raum offen")
		link = str(host.session.online_info().get("link", ""))
	guest = ClientTable.new()
	guest.reuse_token = false
	guest.persist_tokens = false
	guest.persist_backup = false
	guest.retry_ms = [150, 300, 600, 800]
	root.add_child(guest)
	if online:
		guest.join(link, 0, "Püppi")
	else:
		guest.join("127.0.0.1", port, "Püppi")
	if not await _wait_for(func() -> bool: return guest.connection_state() == "open" and host.session.players.size() == 2, 6.0):
		check(false, "Püppi angenommen")
		return false
	check(host.start(4711), "Start")
	if not await _wait_for(func() -> bool: return not guest.current_view().is_empty(), 5.0):
		check(false, "Püppi hat einen Stand")
		return false
	g = 1 - host.host_seat
	h = host.host_seat
	ts = TableScreen.create(guest)
	nav.push(ts, false)
	await frames(3)
	return await fixture()


# Gast ist dran, Ablage rot 5; der Gast hat rot 1, rot 7, gelb 5, der Gastgeber nichts Passendes.
func fixture() -> bool:
	var rules := RuleConfig.new()
	var hands := [[], []]
	hands[g] = ["hell_rot_1", "hell_rot_7", "hell_gelb_5"]
	hands[h] = ["hell_blau_3", "hell_gelb_4", "hell_gruen_6"]
	var game := RulesFixture.build(rules, 2, {"hands": hands, "top": "hell_rot_5", "current": g,
		"draw": ["hell_blau_4", "hell_gruen_8", "hell_blau_9", "hell_gelb_2"]})
	for s in 2:
		game.set_connected(s, true)
	host.game = game
	host._changed([])
	var good := await _wait_for(func() -> bool: return int(guest.current_view().get("turn", -1)) == g \
		and (guest.current_view().get("hand", []) as Array).size() == 3 and ts.hand._order.size() == 3 \
		and ts.table._pile.highlight and not ts.table.director.is_busy(), 6.0)
	check(good, "Ausgangslage beim Gast: dran, 3 Karten, Stapel antippbar")
	return good


func teardown() -> void:
	if ts != null and is_instance_valid(ts):
		ts._leave_now()
	await frames(2)
	if guest != null and is_instance_valid(guest):
		guest.leave()
	if host != null and is_instance_valid(host):
		host.leave()
		host.queue_free()
	await wait(0.4)
	ts = null
	guest = null
	host = null


func lost_texts() -> Array:
	var out: Array = []
	for t in ts.table.hint_bar._toasts:
		if str(t["text"]) in [LOST_CARD, LOST_DRAW, LOST_OTHER]:
			out.append(t)
	return out


func card_id(seat: int, key: String) -> int:
	return RulesFixture.card(host.game, seat, key)


# A: Online, Gast-Socket hängt nach dem Legen
func lost_play() -> void:
	var pid := host.session.id_at_seat(g)
	var c := int(host.session.player(pid).conn) - NetProtocol.RELAY_CONN_BASE
	var code := str(host.session.online_info().get("room", ""))
	check(relay.hang_guest(code, c) >= 0, "A: Gast-Socket hängt")
	var id := card_id(g, "hell_rot_1")
	var checks0 := guest.act_checks
	var t0 := Time.get_ticks_msec()
	check(ts.hand._try_play(id, Vector2(800, 300)), "A: Karte ausgespielt")
	await frames(2)
	check(not ts.hand._order.has(id), "A: Karte hat die Hand verlassen (optimistisch)")
	await wait(3.4)
	check(not ts.hand._order.has(id) and lost_texts().is_empty(), "A: vor 4 s weder zurück noch Meldung")
	check(await _wait_for(func() -> bool: return ts.hand._order.has(id), 1.5), "A: nach 4 s ist die Karte zurück in der Hand")
	var back := Time.get_ticks_msec() - t0
	check(back >= 3900 and back <= 4800, "A: zurück nach %d ms" % back)
	check(await _wait_for(func() -> bool: return guest.act_checks == checks0 + 1, 0.5), "A: Verbindungsprüfung angestoßen (check_now)")
	check(lost_texts().is_empty(), "A: noch keine Meldung, solange der Gastgeber nicht geantwortet hat")
	var shown := await _wait_for(func() -> bool: return not lost_texts().is_empty(), 9.0)
	var took := Time.get_ticks_msec() - t0
	check(shown and took <= 10500, "A: Meldung nach %d ms (neu verbunden statt erst nach 10–15 s)" % took)
	var msg: Array = lost_texts()
	check(msg.size() == 1 and str(msg[0]["text"]) == LOST_CARD and str(msg[0]["kind"]) == "error", "A: Meldung zur Karte, als Fehler (%s)" % str(msg))
	check(ts.hand._order.has(id) and not bool(ts.hand._slots[id].played), "A: Karte liegt in der Hand")
	check(guest.connection_state() == "open", "A: Gast wieder verbunden")
	check(host.game.current_seat() == g and host.game.hands[g].size() == 3, "A: beim Gastgeber kam nichts an, Püppi bleibt dran")
	check(guest.unacked_acts() == 0, "A: keine offene Aktion mehr")
	# noch einmal legen
	check(await _wait_for(func() -> bool: return not ts.table.director.is_busy(), 3.0), "A: Tisch ruhig")
	check(ts.hand._try_play(id, Vector2(800, 300)), "A: noch einmal ausgespielt")
	check(await _wait_for(func() -> bool: return host.game.current_seat() == h and int(guest.current_view().get("turn", -1)) == h, 4.0),
		"A: zweiter Versuch kommt an")
	check(await _wait_for(func() -> bool: return guest.unacked_acts() == 0, 2.0), "A: quittiert")
	check(lost_texts().size() == 1, "A: keine zweite Meldung")
	await wait(0.5)


# B: Online, Antwort kommt erst nach der Prüfung (Gastgeber angehalten), davor noch ein älterer Stand ohne Quittung
func late_answer() -> void:
	ts.table.hint_bar._toasts.clear()
	check(await fixture(), "B: Ausgangslage")
	var id := card_id(g, "hell_rot_7")
	var checks0 := guest.act_checks
	host.auto_process = false
	check(ts.hand._try_play(id, Vector2(800, 300)), "B: Karte ausgespielt")
	await wait(5.5)
	check(guest.act_checks == checks0 + 1, "B: nach 4 s Verbindung geprüft")
	check(guest.connection_state() == "open", "B: Verbindung zum Vermittler steht (pong)")
	check(host.game.hands[g].size() == 3, "B: Gastgeber hat noch nichts verarbeitet")
	var acks: Array = []
	var rec := func(m: Dictionary) -> void:
		if str(m.get("t", "")) == "state":
			acks.append(int(m.get("seq_ack", -1)))
	guest.host_message.connect(rec)
	var sent := guest._seq
	host._changed([])                     # älterer Stand ohne Quittung geht zuerst hinaus
	host.auto_process = true
	check(await _wait_for(func() -> bool: return host.game.current_seat() == h and guest.unacked_acts() == 0, 4.0),
		"B: späte Antwort quittiert das Legen")
	guest.host_message.disconnect(rec)
	check(acks.size() >= 2 and int(acks[0]) < sent and acks.has(sent), "B: erst ein Stand ohne Quittung, dann die Quittung (%s, seq %d)" % [str(acks), sent])
	check(await _wait_for(func() -> bool: return not ts.hand._slots.has(id), 4.0), "B: Karte ist regulär aus der Hand")
	await wait(1.2)                       # länger als ACT_SETTLE_MS
	check(lost_texts().is_empty(), "B: keine Meldung bei später Antwort (%s)" % str(lost_texts()))
	check(host.game.hands[g].size() == 2 and not ts.hand._slots.has(id), "B: gelegt, nicht zurück in der Hand")


# C: WLAN, Gast-Socket hängt nach dem Tipp auf den Ziehstapel
func lost_draw() -> void:
	var pid := host.session.id_at_seat(g)
	var conn := int(host.session.player(pid).conn)
	host.session.server.mute_ws(conn)
	await wait(0.2)
	var t0 := Time.get_ticks_msec()
	check(ts.table._tap(ts.table.draw_pile_position()), "C: Tipp auf den Ziehstapel")
	check(not ts.table._pile.highlight and ts.table.draw_pending(), "C: Stapel aus, Ziehen unterwegs")
	var shown := await _wait_for(func() -> bool: return not lost_texts().is_empty(), 12.0)
	var took := Time.get_ticks_msec() - t0
	check(shown and took <= 10500, "C: Meldung nach %d ms" % took)
	var msg: Array = lost_texts()
	check(msg.size() == 1 and str(msg[0]["text"]) == LOST_DRAW, "C: Meldung zum Ziehen (%s)" % str(msg))
	check(host.game.hands[g].size() == 3, "C: beim Gastgeber nichts gezogen")
	check(await _wait_for(func() -> bool: return ts.table._pile.highlight, 2.0), "C: Stapel wieder antippbar")
	check(ts.table._tap(ts.table.draw_pile_position()), "C: noch einmal getippt")
	check(await _wait_for(func() -> bool: return host.game.hands[g].size() == 4, 4.0), "C: jetzt gezogen")
	check(await _wait_for(func() -> bool: return guest.unacked_acts() == 0, 2.0), "C: quittiert")
	check(lost_texts().size() == 1, "C: keine zweite Meldung")
	others()


# D: übrige Aktionen am Tisch (Oberfläche allein): Glücksspielknopf, Einsatz, Ablege-Auswahl, sonstige
func others() -> void:
	ts.table.hint_bar._toasts.clear()
	ts.table.gamble_machine.press_sent = true
	ts._on_act_lost([{"a": "press"}])
	check(not ts.table.gamble_machine.press_sent, "D: Glücksspielknopf wieder drückbar")
	check(lost_texts().size() == 1 and str(lost_texts()[0]["text"]) == LOST_OTHER, "D: allgemeine Meldung (%s)" % str(lost_texts()))
	ts.table.hint_bar._toasts.clear()
	var id := int(ts.hand._order[0])
	ts.hand.play_requested.disconnect(ts._on_play_requested)     # nur die Hand: nichts geht an den Gastgeber
	var enforce := ts.hand.enforce_playable
	ts.hand.enforce_playable = false
	check(ts.hand._try_play(id, Vector2(800, 300)) and not ts.hand._order.has(id), "D: Einsatzkarte unterwegs")
	ts.hand.enforce_playable = enforce
	ts.hand.play_requested.connect(ts._on_play_requested)
	ts._on_act_lost([{"a": "mau"}, {"a": "stake", "card": id}])
	check(ts.hand._order.has(id) and not bool(ts.hand._slots[id].played), "D: Einsatzkarte sofort zurück in der Hand")
	check(lost_texts().size() == 1 and str(lost_texts()[0]["text"]) == LOST_CARD, "D: Meldung zur Karte hat Vorrang")
	ts.leaving = true
	ts._on_act_lost([{"a": "draw"}])
	check(lost_texts().size() == 1, "D: beim Verlassen keine Meldung mehr")
	ts.leaving = false
