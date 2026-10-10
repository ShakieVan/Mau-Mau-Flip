extends SceneTree

# Flip-Überraschung mit Zusatzkarten im Online-Spiel (Beta 1.4.8): Gastgeber (HostTable) und ein App-Gast (ClientTable) nur über den
# Vermittler-Nachbau (NetRelayDouble, TCP 24981). Der Gast ist der Flip-Spieler; unter dem Flip liegt jeweils eine Zusatzkarte
# (gezielte Lage aus RulesFixture, beim Gastgeber eingesetzt). Geprüft wird, was beim Gast ankommt: Ereignis flip_surprise, danach die
# Phasen wie beim normalen Legen (Kartentausch mit eigener neuer Hand, Farbwahl + Glücksspiel mit Setzen/Drücken/Aufhören,
# Ablege-Auswahl ohne Zurücknehmen, Ablegen-Joker mit Ablegefarbe und Spielfarbe) und dass „undo“ abgelehnt wird, ohne zu hängen.

const RELAY_PORT := 24981
const HOST_PORT := 24982

var failures := 0
var checks := 0
var relay: NetRelayDouble
var host: HostTable
var anna: ClientTable
var anna_events: Array = []
var anna_notices: Array = []
var anna_seat := -1
var leaks: Array = []


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
	check(host.open("Gastgeberin", HOST_PORT, HOST_PORT) == OK, "Gastgeber offen")
	host.session.open_online("http://127.0.0.1:%d" % RELAY_PORT)
	check(wait_until(func(): return host.session.online_state() == "open"), "Online-Raum offen")
	var link := str(host.session.online_info().get("link", ""))
	anna = ClientTable.new()
	anna.auto_process = false
	anna.reuse_token = false
	anna.persist_tokens = false
	anna.retry_ms = [150, 300, 600]
	anna.state_changed.connect(func(ev: Array, v: Dictionary) -> void:
		anna_events.append_array(ev)
		_leak_check(ev, v))
	anna.notice.connect(func(t: String) -> void: anna_notices.append(t))
	anna.join(link, 0, "Anna")
	check(wait_until(func(): return anna.connection_state() == "open" and host.session.players.size() == 2), "Gast über den Vermittler")
	var c := RuleConfig.new()
	c.apply_dict({"flip_surprise": "on", "swap_cards": "on", "gamble_cards": "on", "discard_color": "on"})
	host.set_rules(c)
	check(host.start(4711), "Start")
	check(wait_until(func(): return anna.view_rev > 0), "Gast bekommt den Stand")
	anna_seat = host.session.seat_of(anna.my_id)
	check(anna_seat >= 0 and anna_seat != host.host_seat, "Gast hat einen eigenen Platz (%d)" % anna_seat)
	_swap()
	_gamble()
	_discard()
	_discard_wild()
	_discard_wild_tap()
	_discard_wild_play_tap()
	check(leaks.is_empty(), "Gast sieht nur die eigene Hand (%s)" % str(leaks.slice(0, 3)))


# Lage einsetzen: Anna (Flip-Spieler) ist dran mit [Flip, rest…], unter der Ablage liegt hell_blau_4/<back>.
func inject(back: String, rest: Array, first := "hell_rot_flip") -> void:
	var hands: Array = [[], []]
	var mine: Array = [first]
	mine.append_array(rest)
	hands[anna_seat] = mine
	hands[host.host_seat] = ["hell_gelb_1/dunkel_pink_6", "hell_gelb_3", "hell_gelb_5"]
	var g := RulesFixture.build(host.rules, 2, {"hands": hands, "top": "hell_rot_5/dunkel_orange_3", "discard": ["hell_blau_4/" + back],
		"current": anna_seat, "host": host.host_seat})
	g.players = host.game.players.duplicate(true)
	g.connected = host.game.connected.duplicate()
	host.game = g
	var r0 := anna.last_rev
	host._changed([])
	check(wait_until(func(): return anna.last_rev > r0 and anna.last_rev == host.rev), "Lage %s beim Gast" % back)
	anna_events.clear()
	anna_notices.clear()


# Aktion des Gasts senden und warten, bis ein neuer Stand oder eine Meldung ankommt.
func anna_act(a: Dictionary, what: String) -> void:
	var r0 := anna.view_rev
	var n0 := anna_notices.size()
	anna.act(a)
	check(wait_until(func(): return anna.view_rev > r0 or anna_notices.size() > n0), "%s: Antwort des Gastgebers" % what)


func view() -> Dictionary:
	return anna.current_view()


func ev_names() -> Array:
	var out: Array = []
	for e in anna_events:
		out.append(str(e.get("e", "")))
	return out


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


func flip_now(what: String) -> void:
	anna_act({"a": "play", "card": card_id("hell_rot_flip")}, what)
	var fs := ev_of("flip_surprise")
	check(ev_names().has("flip") and (fs.is_empty() or int(fs.get("seat", -1)) == anna_seat), "%s: Flip beim Gast (%s)" % [what, str(ev_names())])


func _swap() -> void:
	inject("dunkel_lila_tausch", ["hell_rot_1", "hell_rot_2"])
	var host_old: Array = (host.game.hands[host.host_seat] as Array).duplicate()
	flip_now("Tausch")
	var sw := ev_of("swap_hands")
	var own: Array = []
	for item in sw.get("hand", []):
		own.append(int(item.get("id", -1)))
	check(ev_names().find("flip_surprise") >= 0 and ev_names().find("flip_surprise") < ev_names().find("swap_hands"),
		"Tausch: flip_surprise vor swap_hands beim Gast (%s)" % str(ev_names()))
	check(not sw.has("hands") and own == host_old and (view().hand as Array).size() == 3, "Tausch: Gast bekommt nur die eigene neue Hand")
	check(int(view().turn) == host.host_seat and str(view().phase) == "turn", "Tausch: danach ist der Gastgeber dran")


func _gamble() -> void:
	inject("dunkel_gluecksspiel", ["hell_rot_1/dunkel_pink_1", "hell_rot_2/dunkel_pink_2"])
	flip_now("Glücksspiel")
	check(str(view().phase) == "color" and bool(view().hints.need_color) and int(view().turn) == anna_seat, "Glücksspiel: Farbwahl beim Gast")
	anna_act({"a": "color", "color": "tuerkis"}, "Farbe")
	check(ev_names().has("flip_surprise") and ev_names().has("gamble_start") and str(view().phase) == "gamble"
		and (view().hints.can_stake as Array).size() == 2, "Glücksspiel: Phase gamble beim Gast (%s)" % str(ev_names()))
	host.game.force_rolls([0])
	anna_act({"a": "stake", "card": card_id("dunkel_pink_1")}, "setzen")
	anna_act({"a": "press"}, "drücken")
	check(bool(view().hints.can_stop), "Glücksspiel: Aufhören angeboten")
	anna_act({"a": "stop"}, "aufhören")
	check(str(view().phase) == "turn" and int(view().turn) == host.host_seat and str(view().color) == "tuerkis"
		and str(ev_of("stake_discard").get("reason", "")) == "stop", "Glücksspiel: Zug vorbei, Farbe Türkis")


func _discard() -> void:
	inject("dunkel_lila_ablegen", ["hell_rot_1/dunkel_lila_1", "hell_rot_2/dunkel_lila_2", "hell_rot_3/dunkel_pink_3"])
	flip_now("Ablegen")
	var h: Dictionary = view().hints
	check(str(view().phase) == "discard_pick" and (h.can_pick as Array).size() == 2 and not bool(h.can_undo)
		and int(view().discard_pick.seat) == anna_seat, "Ablegen: Auswahl beim Gast ohne Zurücknehmen")
	var n0 := anna_notices.size()
	anna_act({"a": "undo"}, "zurücknehmen")
	check(anna_notices.size() > n0 and host.game.phase() == "discard_pick", "Ablegen: undo abgelehnt, Auswahl bleibt offen")
	anna_act({"a": "discard_pick", "cards": h.can_pick}, "mit ablegen")
	check(int(ev_of("discard_color").get("count", -1)) == 2 and (view().hand as Array).size() == 1 and int(view().turn) == host.host_seat,
		"Ablegen: 2 Karten mit abgelegt, Gastgeber dran")


func _discard_wild() -> void:
	inject("dunkel_ablegen_joker", ["hell_rot_1/dunkel_lila_1", "hell_rot_2/dunkel_lila_2", "hell_rot_3/dunkel_pink_3"])
	flip_now("Ablegen-Joker")
	check(str(view().phase) == "color" and MauBot.discard_wish(view()) and str(view().hints.text).contains("Ablegen-Joker"),
		"Ablegen-Joker: Ablegefarbe wählen (%s)" % str(view().hints.text))
	var bot := MauBot.choose(view(), 5, 1)
	check(str(bot.get("color", "")) == "lila", "Ablegen-Joker: Bot-Vorschlag Lila")
	anna_act(bot, "Ablegefarbe")
	var h: Dictionary = view().hints
	check(str(view().phase) == "discard_pick" and bool(h.pick_color) and not bool(h.can_undo) and str(view().discard_pick.color) == "lila",
		"Ablegen-Joker: Auswahl mit Spielfarbe beim Gast")
	var pick := MauBot.choose(view(), 6, 1)
	if str(pick.get("a", "")) == "mau":            # 1 Karte bleibt: der Bot ruft zuerst
		anna_act(pick, "Mau vor der Auswahl")
		check(bool(ev_of("mau").get("seat", -1) == anna_seat), "Ablegen-Joker: Mau in der Auswahl beim Gast")
		pick = MauBot.choose(view(), 6, 1)
	check(str(pick.get("a", "")) == "discard_pick" and pick.has("color"), "Ablegen-Joker: Bot wählt Karten und Spielfarbe (%s)" % str(pick))
	anna_act(pick, "Auswahl")
	check(str(view().phase) == "turn" and int(view().turn) == host.host_seat and bool(view().wish) and ev_names().has("discard_color"),
		"Ablegen-Joker: abgelegt, Spielfarbe gewünscht")


# 1.4.9: Ablegefarbe per Antippen (hints.pick_tap): Flip-Überraschung mit {a:"color", color:""} → offene Auswahl über alle farbigen
# Karten, gemischte Farben abgelehnt, dann Lila mit ab und Orange als Spielfarbe.
func _discard_wild_tap() -> void:
	inject("dunkel_ablegen_joker", ["hell_rot_1/dunkel_lila_1", "hell_rot_2/dunkel_lila_2", "hell_rot_3/dunkel_pink_3"])
	flip_now("Ablegen-Joker offen")
	check(bool(view().hints.get("pick_tap", false)) and str(view().phase) == "color", "Ablegen-Joker offen: Gastgeber meldet pick_tap")
	anna_act({"a": "color", "color": ""}, "offene Ablegefarbe")
	var h: Dictionary = view().hints
	check(str(view().phase) == "discard_pick" and bool(h.get("pick_open", false)) and (h.can_pick as Array).size() == 3
		and str(view().discard_pick.color) == "" and str(view().color) == "" and not bool(h.can_undo),
		"Ablegen-Joker offen: alle farbigen Karten wählbar, keine Farbe sichtbar (%s)" % str(h.can_pick))
	var n0 := anna_notices.size()
	anna_act({"a": "discard_pick", "cards": [card_id("dunkel_lila_1"), card_id("dunkel_pink_3")], "color": "orange"}, "gemischt")
	check(anna_notices.size() > n0 and host.game.phase() == "discard_pick", "Ablegen-Joker offen: gemischte Farben abgelehnt")
	anna_act({"a": "discard_pick", "cards": [card_id("dunkel_lila_1"), card_id("dunkel_lila_2")], "color": "orange"}, "Lila mit ab")
	var dc := ev_of("discard_color")
	check(str(dc.get("color", "")) == "lila" and int(dc.get("count", -1)) == 2 and str(view().color) == "orange"
		and int(view().turn) == host.host_seat, "Ablegen-Joker offen: Lila abgelegt, weiter mit Orange (%s)" % str(dc))


# 1.4.9: Ablegen-Joker aus der Hand mit color "" legen (Gast), Ablegefarbe aus der Auswahl; Zurücknehmen geht.
func _discard_wild_play_tap() -> void:
	inject("dunkel_lila_1", ["hell_blau_1", "hell_blau_2", "hell_gelb_3"], "hell_ablegen_joker")
	anna_act({"a": "play", "card": card_id("hell_ablegen_joker"), "color": ""}, "Joker offen legen")
	var h: Dictionary = view().hints
	check(str(view().phase) == "discard_pick" and bool(h.get("pick_open", false)) and (h.can_pick as Array).size() == 3 and bool(h.can_undo),
		"Joker offen: Auswahl mit Zurücknehmen")
	anna_act({"a": "undo"}, "zurücknehmen")
	check(str(view().phase) == "turn" and card_id("hell_ablegen_joker") >= 0, "Joker offen: zurückgenommen")
	anna_act({"a": "play", "card": card_id("hell_ablegen_joker"), "color": ""}, "Joker offen legen (2)")
	anna_act({"a": "discard_pick", "cards": [card_id("hell_blau_1")], "color": "gelb"}, "eine Blaue")
	var dc := ev_of("discard_color")
	check(str(dc.get("color", "")) == "blau" and int(dc.get("count", -1)) == 1 and str(view().color) == "gelb"
		and (view().hand as Array).size() == 2, "Joker offen: eine Blaue abgelegt, weiter mit Gelb (%s)" % str(dc))


func _leak_check(events: Array, v: Dictionary) -> void:
	for e in events:
		var d: Dictionary = e
		if str(d.get("e", "")) == "swap_hands" and d.has("hands"):
			leaks.append("swap_hands mit allen Händen")
		if str(d.get("e", "")) == "draw" and int(d.get("seat", -1)) != int(v.get("seat", -1)) and d.has("faces"):
			leaks.append("fremde gezogene Karten")


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
