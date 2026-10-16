extends SceneTree

# Hausregel „Kontern“ im Netz (Beta 1.6.11, docs/module/kontern.md): Gastgeber (HostTable, Voreinstellung „Familie“ mit Kontern) und
# ein App-Gast (ClientTable) über den Vermittler-Nachbau (NetRelayDouble, TCP 25011). Gezielte Lagen aus RulesFixture, beim
# Gastgeber eingesetzt. Geprüft wird, was beim Gast ankommt (Ereignisse counter_open/countered/finish mit survived, Sicht counter und
# players[].counter, Hinweis in Bausteinen), dass der Schnappschuss der Gastgeber-Übergabe die Konter-Runde mitnimmt (pack/unpack und
# ein echtes HostTable.resume() auf 25013) und dass die Sicht, die ein Browser-Gast (Lite) bekäme, JSON-fest ist und den Hinweis trägt.

const RELAY_PORT := 25011
const HOST_PORT := 25012
const RESUME_PORT := 25013

var failures := 0
var checks := 0
var relay: NetRelayDouble
var host: HostTable
var anna: ClientTable
var anna_events: Array = []
var anna_notices: Array = []
var anna_seat := -1


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
	if anna != null:
		anna.leave()
		anna.free()
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
	host.save_path = "user://test_net_counter.json"
	check(host.open("Gastgeberin", HOST_PORT, HOST_PORT) == OK, "Gastgeber offen")
	host.session.open_online("http://127.0.0.1:%d" % RELAY_PORT)
	check(wait_until(func(): return host.session.online_state() == "open"), "Online-Raum offen")
	var link := str(host.session.online_info().get("link", ""))
	anna = ClientTable.new()
	anna.auto_process = false
	anna.reuse_token = false
	anna.persist_tokens = false
	anna.retry_ms = [150, 300, 600]
	anna.state_changed.connect(func(ev: Array, _v: Dictionary) -> void: anna_events.append_array(ev))
	anna.notice.connect(func(t: String) -> void: anna_notices.append(t))
	anna.join(link, 0, "Anna")
	check(wait_until(func(): return anna.connection_state() == "open" and host.session.players.size() == 2), "Gast über den Vermittler")
	var fam := RuleConfig.preset("familie")
	check(fam.counter_round == "on", "Familie mit Kontern")
	host.set_rules(fam)
	check(host.start(4711), "Start")
	check(wait_until(func(): return anna.view_rev > 0), "Gast bekommt den Stand")
	anna_seat = host.session.seat_of(anna.my_id)
	check(anna_seat >= 0 and anna_seat != host.host_seat, "Gast hat einen eigenen Platz (%d)" % anna_seat)
	check(str((view().get("rules", {}) as Dictionary).get("counter_round", "")) == "on", "Gast kennt die Regel")
	_countered()
	_survived()


# Lage einsetzen: Anna ist dran mit mine, die Gastgeberin hält theirs; oben rot 5.
func inject(mine: Array, theirs: Array, draw := []) -> void:
	var hands: Array = [[], []]
	hands[anna_seat] = mine
	hands[host.host_seat] = theirs
	var g := RulesFixture.build(host.rules, 2, {"hands": hands, "top": "hell_rot_5", "draw": draw, "current": anna_seat,
		"host": host.host_seat})
	g.players = host.game.players.duplicate(true)
	g.connected = host.game.connected.duplicate()
	host.game = g
	var r0 := anna.last_rev
	host._changed([])
	check(wait_until(func(): return anna.last_rev > r0 and anna.last_rev == host.rev), "Lage beim Gast")
	anna_events.clear()
	anna_notices.clear()


func anna_act(a: Dictionary, what: String) -> void:
	var r0 := anna.view_rev
	var n0 := anna_notices.size()
	anna.act(a)
	check(wait_until(func(): return anna.view_rev > r0 or anna_notices.size() > n0), "%s: Antwort des Gastgebers" % what)
	check(anna_notices.size() == n0, "%s: angenommen (%s)" % [what, str(anna_notices.slice(n0))])


func host_act(a: Dictionary, what: String) -> void:
	var r0 := anna.view_rev
	host.act(a)
	check(wait_until(func(): return anna.view_rev > r0 and anna.last_rev == host.rev), "%s: beim Gast angekommen" % what)


func view() -> Dictionary:
	return anna.current_view()


func ev_of(n: String) -> Dictionary:
	for e in anna_events:
		if str(e.get("e", "")) == n:
			return e
	return {}


func card_id(key: String) -> int:
	for c in view().get("hand", []):
		if str(c.get("face", "")) == key:
			return int(c.get("id", -1))
	return -1


func host_card(key: String) -> int:
	return RulesFixture.card(host.game, host.host_seat, key)


func _countered() -> void:
	inject(["hell_rot_7"], ["hell_rot_plus1", "hell_blau_1", "hell_blau_2"])
	anna_act({"a": "play", "card": card_id("hell_rot_7")}, "Anna legt die letzte Karte")
	var v := view()
	check(int(ev_of("counter_open").get("seat", -1)) == anna_seat and ev_of("finish").is_empty(), "Gast: counter_open, nicht fertig")
	check((v.get("counter", {}) as Dictionary).get("wait", []) == [anna_seat] and bool(v.players[anna_seat].get("counter", false))
		and int(v.players[anna_seat].place) == 0 and (v.hand as Array).is_empty(), "Gast: Sicht zeigt die Konter-Runde")
	check(str(v.hints.text).contains("Du hast keine Karten mehr – kontert keiner, bist du fertig.") and int(v.turn) == host.host_seat,
		"Gast: Hinweis (%s)" % str(v.hints.text))
	check(I18n.render(v.hints.lt, false) == str(v.hints.text), "Gast: Bausteine ergeben den Hinweis")
	var hv := host.view_of(host.host_seat)
	check(str(hv.hints.text).begins_with("Anna hat keine Karten mehr – wer kontert?"), "Gastgeberin: wer kontert? (%s)" % str(hv.hints.text))
	# Sicht für einen Browser-Gast (Lite): dieselbe Sicht über JSON
	var lite: Variant = JSON.parse_string(NetProtocol.encode({"t": "state", "events": [], "view": host.view_of(anna_seat)}))
	check(lite is Dictionary and ((lite as Dictionary).view.counter as Dictionary).get("wait", []) == [float(anna_seat)]
		and str((lite as Dictionary).view.hints.text).contains("kontert keiner"), "Lite-Sicht trägt counter und Hinweis")
	# Schnappschuss der Gastgeber-Übergabe nimmt die Konter-Runde mit
	var snap := host._snapshot()
	var back := MatchSnapshot.unpack(MatchSnapshot.pack(snap))
	var g2 := MauGame.from_dict(back.game)
	check(g2.counter_wait == [anna_seat] and JSON.stringify(g2.to_dict()) == JSON.stringify(host.game.to_dict()), "Schnappschuss: counter kommt mit")
	_resume(back)
	# Die Gastgeberin kontert mit +1 (Familie: Anna zieht sofort, ist danach dran)
	host_act({"a": "play", "card": host_card("hell_rot_plus1")}, "Gastgeberin kontert")
	v = view()
	var dr := ev_of("draw")
	check(int(dr.get("seat", -1)) == anna_seat and (dr.get("faces", []) as Array).size() == 1 and int(ev_of("countered").get("seat", -1)) == anna_seat,
		"Gast: gezogen und gekontert")
	check((v.hand as Array).size() == 1 and int(v.turn) == anna_seat and (v.counter.wait as Array).is_empty()
		and not bool(v.players[anna_seat].counter), "Gast: wieder im Spiel und dran")


# Echtes HostTable.resume() des Schnappschusses (nur im WLAN, ohne den Online-Raum: sonst übernähme es den Raum der Gastgeberin).
func _resume(back: Dictionary) -> void:
	var snap := back.duplicate(true)
	snap["online"] = {}
	var t := HostTable.new()
	t.auto_process = false
	t.speed = 0.0
	t.use_discovery = false
	t.autosave = false
	t.backup_enabled = false
	t.save_path = "user://test_net_counter_resume.json"
	check(t.resume(snap, -1, RESUME_PORT, RESUME_PORT) == OK, "Übergabe: resume")
	var ref := MauGame.from_dict(snap.game)
	ref.connected = t.game.connected.duplicate()
	check(t.game.counter_wait == [anna_seat] and JSON.stringify(t.game.to_dict()) == JSON.stringify(ref.to_dict())
		and JSON.stringify(t.game.view_for(anna_seat)) == JSON.stringify(ref.view_for(anna_seat)), "Übergabe: neuer Gastgeber kennt die Konter-Runde")
	check(str(t.view_of(t.host_seat).hints.text).contains("Anna hat keine Karten mehr – wer kontert?"), "Übergabe: Hinweis beim neuen Gastgeber")
	t.leave()
	t.free()
	check(wait_until(func(): return anna.connection_state() == "open"), "Gast bleibt bei der Gastgeberin")


func _survived() -> void:
	inject(["hell_rot_7"], ["hell_blau_1", "hell_blau_2"], ["hell_gruen_9"])
	anna_act({"a": "play", "card": card_id("hell_rot_7")}, "Anna legt die letzte Karte (2)")
	check(not ev_of("counter_open").is_empty() and str(view().phase) == "turn", "zweite Lage: Konter-Runde")
	host_act({"a": "draw"}, "Gastgeberin zieht")
	var fin := ev_of("finish")
	var ro := ev_of("round_over")
	check(int(fin.get("seat", -1)) == anna_seat and bool(fin.get("survived", false)), "Gast: finish mit survived (%s)" % str(fin))
	check(not ro.is_empty() and int((ro.ranking as Array)[0]) == anna_seat and str(view().phase) == "round_over", "Gast: Runde vorbei, Anna gewinnt")


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
	if anna != null and anna.client != null:
		anna.pump()


func wait_until(cond: Callable, ms := 5000) -> bool:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		pump(2)
		if cond.call():
			return true
	return cond.call()
