extends SceneTree
# Beta 1.4.2: Mitspieler mitten im Spiel dazuholen und entfernen (MauGame.insert_player/remove_player, docs/module/dazuholen.md).
# Gebaute Fälle: Einfügen an jedem Platz vor/hinter dem Spieler am Zug in beiden Richtungen (wer ist als Nächster dran), Kartenzahl
# (höchste Hand, höchstens Startzahl, mindestens 1, knapper und leerer Stapel), Punkte (niedrigster Stand), am Rundenende, Entfernen in
# jeder Phase (turn mit Stapelstrafe, drawn, challenge mit Leger/Opfer, color, gamble mit Einsatz, discard_pick), Mau-Fenster, Fertige,
# Geber, Karten unten im Ziehstapel, 2 → 1 Spieler, Speichern/Laden. Danach ein Dauerlauf: Bot-Partien mit zufälligen Regeln, in
# denen zufällig dazugeholt und entfernt wird (Invarianten, Kartenerhaltung, keine Hänger; RULES_SEATS_GAMES, teilbar per TEIL=k/n).

const Teil := preload("res://tests/teil.gd")
const GAMES := 250
const STEP_LIMIT := 6000
const ROUND_LIMIT := 30

var failures := 0
var checks := 0
var stats := {}


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)


func _initialize() -> void:
	if Teil.first():
		_insert_positions()
		_card_count()
		_card_count_empty_pile()
		_scores()
		_insert_round_over()
		_insert_refused()
		_remove_simple()
		_remove_stacking()
		_remove_drawn()
		_remove_challenge()
		_remove_color()
		_remove_gamble()
		_remove_discard_pick()
		_remove_mau_window()
		_remove_finished()
		_remove_last()
		_remove_round_over()
		_save_load()
	_bot_run()
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)


# --- Hilfen ---

func cfg(over := {}) -> RuleConfig:
	return RuleConfig.from_dict(over)


func fresh(n: int, over := {}, rng_seed := 4242) -> MauGame:
	var g := MauGame.create(cfg(over), RulesFixture.players(n), rng_seed)
	g.start_round()
	return g


func names(g: MauGame) -> Array:
	var out: Array = []
	for p in g.players:
		out.append(str(p.name))
	return out


func ev_names(ev: Array) -> Array:
	var out: Array = []
	for e in ev:
		out.append(str(e.e))
	return out


func ev_of(ev: Array, e_name: String) -> Dictionary:
	for e in ev:
		if str(e.e) == e_name:
			return e
	return {}


func inv(g: MauGame, msg: String) -> void:
	var i := RulesFixture.invariants(g)
	check(i == "", "%s: %s" % [msg, i])


# Zug weitergeben: ziehen und, falls die gezogene Karte passt, behalten.
func pass_turn(g: MauGame) -> void:
	var s := g.current_seat()
	var r := g.apply(s, {"a": "draw"})
	check(bool(r.ok), "ziehen (%s)" % r.reason)
	if g.state == "drawn" and g.current == s:
		r = g.apply(s, {"a": "keep"})
		check(bool(r.ok), "behalten (%s)" % r.reason)


func act(g: MauGame, seat: int, action: Dictionary, msg: String) -> Array:
	var r := g.apply(seat, action)
	check(bool(r.ok), "%s (abgelehnt: %s)" % [msg, r.reason])
	inv(g, msg)
	return r.events


func play(g: MauGame, seat: int, key: String, msg: String, col := "") -> Array:
	var id := RulesFixture.card(g, seat, key)
	check(id >= 0, "%s: Karte %s bei Platz %d" % [msg, key, seat])
	var a := {"a": "play", "card": id}
	if col != "":
		a["color"] = col
	return act(g, seat, a, msg)


func remove(g: MauGame, seat: int, msg: String) -> Array:
	var before := RulesFixture.card_check(g)
	var r := g.remove_player(seat)
	check(bool(r.ok), "%s: entfernen (%s)" % [msg, r.reason])
	check(before == "" and RulesFixture.card_check(g) == "", "%s: Kartenerhaltung (%s)" % [msg, RulesFixture.card_check(g)])
	if g.state in MauGame.PLAY_PHASES:
		inv(g, msg)
	return r.events


# --- Dazuholen ---

func _insert_positions() -> void:
	for n in [3, 4]:
		for d in [1, -1]:
			var base := fresh(n, {}, 900 + n)
			base.dir = d
			for at in n + 1:
				var g := MauGame.from_dict(base.to_dict())
				var cur_name := str(g.players[g.current].name)
				var old_c := g.current
				var r := g.insert_player(at, {"name": "Neu", "kind": "human"})
				var tag := "n=%d dir=%d at=%d" % [n, d, at]
				check(bool(r.ok) and int(r.seat) == at and str(g.players[at].name) == "Neu", "%s: eingefügt" % tag)
				check(str(g.players[g.current].name) == cur_name and g.state == "turn", "%s: am Zug bleibt %s" % [tag, cur_name])
				var e := ev_of(r.events, "seats")
				check(int(e.get("join", -2)) == at and int(e.get("leave", -2)) == -1 and (e.get("map", []) as Array).size() == n
					and int(e.map[old_c]) == g.current, "%s: Ereignis seats (%s)" % [tag, str(e)])
				var dr := ev_of(r.events, "draw")
				check(str(dr.get("reason", "")) == "join" and int(dr.get("seat", -1)) == at and int(dr.get("count", 0)) == 7,
					"%s: zieht 7 mit reason join (%s)" % [tag, str(dr)])
				check(ev_names(r.events) == ["seats", "draw"], "%s: nur seats und draw (%s)" % [tag, str(ev_names(r.events))])
				inv(g, tag)
				var order := names(g)
				var want := str(order[posmod(g.current + d, n + 1)])
				var neu_next: bool = posmod(g.current + d, n + 1) == at
				pass_turn(g)
				check(str(g.players[g.current].name) == want, "%s: als Nächstes %s (ist %s)" % [tag, want, str(g.players[g.current].name)])
				if neu_next:
					check(want == "Neu", "%s: sitzt direkt dahinter → als Nächster dran" % tag)
					stats["neu_direkt_dran"] = int(stats.get("neu_direkt_dran", 0)) + 1
	check(int(stats.get("neu_direkt_dran", 0)) == 4, "der Neue direkt hinter dem Spieler am Zug kam in allen vier Fällen dran")


func _card_count() -> void:
	var g := RulesFixture.build(cfg({"hand_size": 7}), 3, {"hands": [["hell_rot_1", "hell_rot_2", "hell_rot_3"],
		["hell_gelb_1", "hell_gelb_2", "hell_gelb_3", "hell_gelb_4", "hell_gelb_5", "hell_gelb_6", "hell_gelb_7", "hell_gelb_8", "hell_gelb_9"],
		["hell_blau_1", "hell_blau_2"]], "top": "hell_rot_5"})
	check(g.join_card_count() == 7, "höchste Hand 9 → höchstens die Startzahl 7 (%d)" % g.join_card_count())
	g = RulesFixture.build(cfg({"hand_size": 7}), 3, {"hands": [["hell_rot_1", "hell_rot_2", "hell_rot_3"],
		["hell_gelb_1", "hell_gelb_2", "hell_gelb_3", "hell_gelb_4"], ["hell_blau_1", "hell_blau_2"]], "top": "hell_rot_5"})
	check(g.join_card_count() == 4, "höchste Hand 4 → 4 (%d)" % g.join_card_count())
	var r := g.insert_player(3, {"name": "Neu"})
	check(bool(r.ok) and (g.hands[3] as Array).size() == 4, "Neuer bekommt 4 Karten")
	# Fertige zählen nicht (round_end last): aktiv 1 und 1 Karte → 1
	g = RulesFixture.build(cfg({"round_end": "last"}), 4, {"hands": [["hell_rot_1"], [], ["hell_gelb_1"], ["hell_blau_1"]],
		"top": "hell_rot_5", "finished": [1]})
	check(g.join_card_count() == 1, "nur Einzelkarten, Fertige ohne Karten → 1 (%d)" % g.join_card_count())
	r = g.insert_player(2, {"name": "Neu"})
	check(bool(r.ok) and (g.hands[2] as Array).size() == 1 and int(g.place[2]) == 0 and int(g.place[1]) == 1 and g.finished == [1],
		"mit 1 Karte dabei, Fertiger bleibt Platz 1 (%s)" % str(g.place))
	check(not g.mau_said[2] and g.mau_open == -1, "mit 1 Karte kein Mau-Fenster für den Neuen")
	inv(g, "Fertige")
	# höchstens die Startzahl auch bei hand_size 5
	g = fresh(3, {"hand_size": 5}, 77)
	r = g.insert_player(1, {"name": "Neu"})
	check((g.hands[1] as Array).size() == 5, "Startzahl 5 → 5 Karten")


func _card_count_empty_pile() -> void:
	# Fast alle Karten in den Händen: freie Karten = Ziehstapel + Ablage ohne oberste
	var g := fresh(3, {}, 31)
	while g.draw_pile.size() > 2:
		(g.hands[1] as Array).append(g.draw_pile.pop_back())
	while g.discard.size() > 1:
		(g.hands[2] as Array).append(g.discard.pop_front())
	check(g.join_card_count() == 2 and RulesFixture.card_check(g) == "", "knapp: nur 2 freie Karten (%d)" % g.join_card_count())
	var r := g.insert_player(1, {"name": "Neu"})
	check(bool(r.ok) and (g.hands[1] as Array).size() == 2 and g.draw_pile.is_empty(), "bekommt die 2, die da sind")
	inv(g, "knapp")
	# Gar keine freie Karte: sitzt aus, solange beide Stapel leer sind, und wird übersprungen
	g = fresh(3, {}, 32)
	while not g.draw_pile.is_empty():
		(g.hands[1] as Array).append(g.draw_pile.pop_back())
	while g.discard.size() > 1:
		(g.hands[2] as Array).append(g.discard.pop_front())
	var c := g.current
	r = g.insert_player(c + 1, {"name": "Neu"})
	check(bool(r.ok) and (g.hands[c + 1] as Array).is_empty() and ev_of(r.events, "draw").is_empty(), "leerer Stapel: keine Karten")
	check(g._out_of_cards(c + 1) and g._active_count() == 3, "sitzt aus, 3 aktiv")
	inv(g, "leer")
	# Beide Stapel leer: der Platz direkt dahinter wird übersprungen
	var j := c + 1
	check(g._next_in(c, 1) == posmod(c + 2, 4), "beide Stapel leer: der Aussitzende wird übersprungen")
	# Wird eine Karte frei, ist er normal dran und zieht
	var donor := posmod(c + 2, 4)
	g.discard.insert(0, (g.hands[donor] as Array).pop_back())
	check(not g._out_of_cards(j) and g._next_in(c, 1) == j and RulesFixture.card_check(g) == "", "Karte frei: er ist wieder dabei")
	g._new_turn(j, [])
	var hv := g.view_for(j)
	check(bool(hv.hints.can_draw) and (hv.hints.playable as Array).is_empty(), "am Zug ohne Karten: ziehen")
	act(g, j, MauBot.choose(hv, 3, 1), "Aussitzender zieht")
	check((g.hands[j] as Array).size() >= 1 or g.current != j, "hat jetzt eine Karte")
	# Runde zu Ende spielen
	var steps := 0
	while g.state in MauGame.PLAY_PHASES and steps < 3000:
		steps += 1
		var s := g.current_seat()
		var rr := g.apply(s, MauBot.choose(g.view_for(s), steps, 1))
		if not bool(rr.ok):
			check(false, "Bot abgelehnt: %s" % rr.reason)
			break
		inv(g, "Runde mit Aussitzendem")
	check(g.state in ["round_over", "game_over"], "Runde endet (%s, %d Schritte)" % [g.state, steps])
	if g.state == "round_over":
		act(g, g.host, {"a": "next_round"}, "nächste Runde")
		check((g.hands[j] as Array).size() == 7, "beim nächsten Austeilen bekommt er 7 Karten")


func _scores() -> void:
	var g := fresh(3, {"scoring": "points500"}, 12)
	g.scores = [40, 12, 90]
	g.insert_player(1, {"name": "Neu"})
	check(g.scores == [40, 12, 12, 90], "Punkte: Neuer startet mit dem niedrigsten Stand (%s)" % str(g.scores))
	g.remove_player(1)
	g.insert_player(3, {"name": "Wieder"})
	check(g.scores == [40, 12, 90, 12], "Wiederkommen: wieder der niedrigste Stand, kein Merken (%s)" % str(g.scores))


func _insert_round_over() -> void:
	var g := RulesFixture.build(cfg(), 3, {"hands": [["hell_rot_7"], ["hell_gelb_1", "hell_gelb_2"], ["hell_blau_1"]],
		"top": "hell_rot_5", "current": 0})
	play(g, 0, "hell_rot_7", "letzte Karte")
	check(g.state == "round_over", "Runde vorbei")
	var r := g.insert_player(1, {"name": "Neu", "kind": "bot"})
	check(bool(r.ok) and ev_names(r.events) == ["seats"] and (g.hands[1] as Array).is_empty(), "am Rundenende: nur seats, keine Karten")
	check(str(g.players[1].kind) == "bot" and (g.result.points as Array).size() == 4 and int(g.result.points[1]) == 0
		and int(g.result.gains[1]) == 0 and (g.result.hands[1] as Array).is_empty() and not (g.result.ranking as Array).has(1),
		"Ergebnis: Einträge 0/0/[], nicht in der Rangliste (%s)" % str(g.result))
	check(int(g.result.ranking[0]) == 0 and int(g.place[1]) == 0 and int(g.place[0]) == 1, "Sieger bleibt Platz 0, Neuer ohne Platz")
	var v := g.view_for(1)
	check(str(v.hints.text) != "" and not str(v.hints.text).contains("Platz 0"), "Hinweis des Neuen ohne „Platz 0“ (%s)" % v.hints.text)
	act(g, 0, {"a": "next_round"}, "nächste Runde mit 4")
	for s in 4:
		check((g.hands[s] as Array).size() == 7, "nach dem Austeilen hat Platz %d 7 Karten" % s)


func _insert_refused() -> void:
	var g := fresh(3, {"gamble_cards": "on"}, 5)
	g.state = "color"
	var r := g.insert_player(1, {"name": "X"})
	check(not bool(r.ok) and g.players.size() == 3, "Farbwahl offen: Dazuholen erst nach dem Zug")
	g.state = "turn"
	var full := fresh(10, {}, 6)
	r = full.insert_player(3, {"name": "X"})
	check(not bool(r.ok) and full.players.size() == 10, "voll mit 10")
	check(not g.remove_player(g.host).ok, "Gastgeber nicht entfernbar")
	check(not g.can_remove_now(g.host), "can_remove_now: Gastgeber nie")
	var other := posmod(g.current + 1, 3)
	if other == g.host:
		other = posmod(g.current + 2, 3)
	g.state = "drawn"
	check(g.can_remove_now(g.current) and (g.current == g.host or not g.can_remove_now(other) or other == g.current),
		"in drawn nur der Platz am Zug sofort")
	g.state = "turn"


# --- Entfernen ---

func _remove_simple() -> void:
	for d in [1, -1]:
		for rel in [-1, 1]:
			var g := fresh(4, {}, 300)
			g.host = 0
			g.dir = d
			if g.current == 0:
				pass_turn(g)
			var cur_name := str(g.players[g.current].name)
			var r := posmod(g.current + rel, 4)
			if r == 0:
				r = posmod(g.current - rel, 4)
			var gone := str(g.players[r].name)
			var cnt := (g.hands[r] as Array).size()
			var gone_ids: Array = (g.hands[r] as Array).duplicate()
			var ev := remove(g, r, "vor/nach dem Spieler am Zug (dir %d, rel %d)" % [d, rel])
			check(g.players.size() == 3 and not names(g).has(gone) and str(g.players[g.current].name) == cur_name and g.state == "turn",
				"%s raus, %s bleibt am Zug" % [gone, cur_name])
			check(ev_names(ev) == ["leave_cards", "seats"] and int(ev[0].count) == cnt and int(ev[0].seat) == r, "Ereignisse leave_cards, seats")
			var bottom: Array = g.draw_pile.slice(0, cnt)
			bottom.sort()
			gone_ids.sort()
			check(bottom == gone_ids, "Karten liegen unten im Ziehstapel")
			var e := ev[1] as Dictionary
			check(int(e.leave) == r and int(e.join) == -1 and int(e.map[r]) == -1, "seats: leave %d" % r)


func _remove_stacking() -> void:
	# Opfer am Zug mit offener Stapelstrafe → die Strafe verfällt, der Nächste ist dran
	var g := RulesFixture.build(cfg({"stacking": "same"}), 4, {"hands": [["hell_rot_plus1", "hell_rot_1"], ["hell_gelb_1", "hell_gelb_2"],
		["hell_blau_1", "hell_blau_2"], ["hell_gruen_1", "hell_gruen_2"]], "top": "hell_rot_5", "current": 0})
	play(g, 0, "hell_rot_plus1", "+1 legen")
	check(g.current == 1 and not g.pending.is_empty() and int(g.pending.victim) == 1, "Stapelstrafe gegen Platz 1")
	var ev := remove(g, 1, "Opfer raus")
	check(g.pending.is_empty() and str(g.players[g.current].name) == "Cleo" and g.state == "turn", "Strafe verfällt, Cleo ist dran")
	check(ev_names(ev).back() == "turn" and int(ev.back().seat) == g.current, "turn-Ereignis mit neuer Nummer")
	# Leger einer nicht anzweifelbaren Strafe raus: die Strafe bleibt, der Leger ist −1
	g = RulesFixture.build(cfg({"stacking": "same"}), 4, {"hands": [["hell_rot_plus1", "hell_rot_1"], ["hell_gelb_1", "hell_gelb_2"],
		["hell_blau_1", "hell_blau_2"], ["hell_gruen_1", "hell_gruen_2"]], "top": "hell_rot_5", "current": 0, "host": 2})
	play(g, 0, "hell_rot_plus1", "+1 legen")
	remove(g, 0, "Leger raus")
	check(not g.pending.is_empty() and int(g.pending.by) == -1 and int(g.pending.victim) == 0 and g.current == 0, "Strafe bleibt beim Opfer")
	act(g, 0, {"a": "draw"}, "Opfer nimmt die Strafe")


func _remove_drawn() -> void:
	var g := fresh(3, {}, 41)
	var c := g.current
	act(g, c, {"a": "draw"}, "ziehen")
	if g.state != "drawn":
		return
	if c == g.host:
		g.host = posmod(c + 1, 3)
	var nxt := str(g.players[posmod(c + g.dir, 3)].name)
	remove(g, c, "in drawn")
	check(g.state == "turn" and g.drawn_id == -1 and str(g.players[g.current].name) == nxt, "drawn: Nächster ist dran")


func _remove_challenge() -> void:
	var spec := {"hands": [["hell_wuenscher_plus2", "hell_gelb_4"], ["hell_gelb_1", "hell_gelb_2"], ["hell_blau_1", "hell_blau_2"]],
		"top": "hell_rot_5", "current": 0, "host": 2}
	# Leger raus: Opfer spielt normal weiter
	var g := RulesFixture.build(cfg({"wild_restriction": "bluff"}), 3, spec)
	play(g, 0, "hell_wuenscher_plus2", "Wünscher +2 legen", "blau")
	check(g.state == "challenge" and g.current == 1, "Anzweifeln offen")
	var ev := remove(g, 0, "Leger raus")
	check(g.state == "turn" and g.pending.is_empty() and str(g.players[g.current].name) == "Ben" and g.color == "blau",
		"Strafe verfällt, Ben spielt normal, Wunschfarbe bleibt")
	check(ev_names(ev).back() == "turn", "neuer Zug für Ben")
	# Opfer raus: der Nächste ist dran
	g = RulesFixture.build(cfg({"wild_restriction": "bluff"}), 3, spec)
	play(g, 0, "hell_wuenscher_plus2", "Wünscher +2 legen", "blau")
	remove(g, 1, "Opfer raus")
	check(g.state == "turn" and g.pending.is_empty() and str(g.players[g.current].name) == "Cleo", "Cleo ist dran")
	# Letzte Karte anzweifelbar, Opfer raus: der Leger ist trotzdem fertig
	var spec2 := spec.duplicate(true)
	spec2.hands[0] = ["hell_wuenscher_plus2"]
	g = RulesFixture.build(cfg({"wild_restriction": "bluff", "round_end": "last"}), 4, {"hands": [["hell_wuenscher_plus2"],
		["hell_gelb_1"], ["hell_blau_1", "hell_blau_2"], ["hell_rot_1", "hell_rot_2"]], "top": "hell_rot_5", "current": 0, "host": 2})
	play(g, 0, "hell_wuenscher_plus2", "letzte Karte Wünscher +2", "blau")
	ev = remove(g, 1, "Opfer der letzten Karte raus")
	check(int(g.place[0]) == 1 and g.finished == [0] and str(g.players[g.current].name) == "Cleo", "Anna fertig, Cleo dran (%s)" % str(g.place))
	check(ev_names(ev).has("finish"), "finish-Ereignis")
	g = RulesFixture.build(cfg({"wild_restriction": "bluff"}), 3, {"hands": [["hell_wuenscher_plus2"],
		["hell_gelb_1"], ["hell_blau_1", "hell_blau_2"]], "top": "hell_rot_5", "current": 0, "host": 2})
	play(g, 0, "hell_wuenscher_plus2", "letzte Karte Wünscher +2", "blau")
	ev = remove(g, 1, "Opfer raus, round_end first")
	check(g.state == "round_over" and int(g.result.ranking[0]) == 0 and str(g.result.reason) == "fertig", "Runde endet, Anna gewinnt")


func _remove_color() -> void:
	var g := fresh(3, {}, 51)
	g.host = posmod(g.current + 1, 3)
	g.state = "color"
	g.color = ""
	var c := g.current
	var want := str(g.players[posmod(c + g.dir, 3)].name)
	var ev := remove(g, c, "Farbwahl offen")
	check(g.state == "turn" and (CardDB.COLORS[g.side_name()] as Array).has(g.color) and g.wished, "Zufallsfarbe (%s)" % g.color)
	var ce := ev_of(ev, "color")
	check(int(ce.get("seat", 0)) == -1 and str(ce.get("color", "")) == g.color, "color-Ereignis mit seat −1")
	check(str(g.players[g.current].name) == want, "Nächster dran")


func _remove_gamble() -> void:
	var c := cfg({"gamble_cards": "on"})
	var g := RulesFixture.build(c, 3, {"hands": [["hell_rot_1", "hell_rot_2", "hell_rot_3"], ["hell_gelb_1", "hell_gelb_2"],
		["hell_blau_1", "hell_blau_2"]], "top": "hell_gluecksspiel", "color": "rot", "current": 1, "host": 0, "phase": "gamble",
		"gamble": {"q": 3, "stake": ["hell_gruen_1", "hell_gruen_2"], "need": "stake"}})
	inv(g, "Glücksspiel gebaut")
	var stake: Array = (g.gamble.stake as Array).duplicate()
	stake.append_array(g.hands[1])
	stake.sort()
	var ev := remove(g, 1, "im Glücksspiel")
	check(g.gamble.is_empty() and g.state == "turn" and str(g.players[g.current].name) == "Cleo", "Glücksspiel weg, Cleo dran")
	check(int(ev_of(ev, "leave_cards").get("count", 0)) == 4, "Hand und Einsatz: 4 Karten")
	var bottom: Array = g.draw_pile.slice(0, 4)
	bottom.sort()
	check(bottom == stake, "Einsatz und Hand unten im Ziehstapel")
	# Ein anderer (nicht am Zug) wird erst nach dem Glücksspiel entfernt
	g = RulesFixture.build(c, 3, {"hands": [["hell_rot_1", "hell_rot_2", "hell_rot_3"], ["hell_gelb_1", "hell_gelb_2"],
		["hell_blau_1", "hell_blau_2"]], "top": "hell_gluecksspiel", "color": "rot", "current": 1, "host": 0, "phase": "gamble",
		"gamble": {"q": 3, "stake": [], "need": "stake"}})
	check(not g.can_remove_now(2) and g.can_remove_now(1) and not g.can_change_seats(), "can_remove_now im Glücksspiel")


func _remove_discard_pick() -> void:
	var g := RulesFixture.build(cfg({"discard_color": "on"}), 3, {"hands": [["hell_rot_ablegen", "hell_rot_1", "hell_gelb_2"],
		["hell_gelb_1", "hell_gelb_3"], ["hell_blau_1", "hell_blau_2"]], "top": "hell_rot_5", "current": 0, "host": 1})
	play(g, 0, "hell_rot_ablegen", "Ablegen-Karte")
	check(g.state == "discard_pick", "Ablege-Auswahl offen")
	remove(g, 0, "in der Ablege-Auswahl")
	check(g.dpick.is_empty() and g.state == "turn" and str(g.players[g.current].name) == "Ben" and RulesFixture.top_key(g) == "hell_rot_ablegen",
		"Auswahl entfällt, Ablegen-Karte oben, Ben dran")
	# Ablegen-Joker: bisherige Farbe gilt als Wunsch
	g = RulesFixture.build(cfg({"discard_color": "on"}), 3, {"hands": [["hell_ablegen_joker", "hell_rot_1"],
		["hell_gelb_1", "hell_gelb_3"], ["hell_blau_1", "hell_blau_2"]], "top": "hell_rot_5", "current": 0, "host": 1})
	play(g, 0, "hell_ablegen_joker", "Ablegen-Joker", "rot")
	remove(g, 0, "Joker-Auswahl")
	check(g.color == "rot" and g.wished, "Farbe bleibt rot als Wunsch")


func _remove_mau_window() -> void:
	var g := RulesFixture.build(cfg(), 4, {"hands": [["hell_rot_1", "hell_rot_2"], ["hell_gelb_1", "hell_gelb_2"], ["hell_blau_1", "hell_blau_2"],
		["hell_gruen_1", "hell_gruen_2"]], "top": "hell_rot_5", "current": 0, "host": 3})
	play(g, 0, "hell_rot_1", "vorletzte Karte ohne Ruf")
	check(g.mau_open == 0, "Mau-Fenster bei Anna")
	remove(g, 1, "Ben raus")
	check(g.mau_open == 0 and str(g.players[g.current].name) == "Cleo", "Fenster bleibt bei Anna, Cleo dran")
	check(g.view_for(2).hints.catch == [0], "Erwischen weiter möglich")
	remove(g, 0, "Anna raus")
	check(g.mau_open == -1 and g.view_for(1).hints.catch == [], "Fenster zu")


func _remove_finished() -> void:
	var g := RulesFixture.build(cfg({"round_end": "last"}), 5, {"hands": [["hell_rot_1", "hell_rot_2"], [], [],
		["hell_blau_1", "hell_blau_2"], ["hell_gruen_1", "hell_gruen_2"]], "top": "hell_rot_5", "current": 0, "host": 4,
		"finished": [2, 1], "dealer": 1})
	check(int(g.place[2]) == 1 and int(g.place[1]) == 2, "aufgebaut: Cleo 1., Ben 2.")
	remove(g, 2, "Erster Fertiger raus")
	check(g.finished == [1] and int(g.place[1]) == 1 and g.players.size() == 4, "Ben rückt auf Platz 1 (%s)" % str(g.place))
	remove(g, 1, "Geber raus")
	check(g.dealer == 0, "Geber: der Platz davor (%d)" % g.dealer)
	check(g.finished.is_empty() and g.state == "turn", "keiner mehr fertig")
	remove(g, 0, "am Zug raus")
	check(g.state == "round_over" and str(g.result.reason) == "left" and g.players.size() == 2 or g.state == "turn",
		"Spiel geht weiter oder endet (%s)" % g.state)


func _remove_last() -> void:
	var g := fresh(2, {}, 61)
	g.host = 0
	var ev := remove(g, 1, "2 → 1")
	check(g.state == "game_over" and g.players.size() == 1 and ev_names(ev).has("round_over") and ev_names(ev).back() == "game_over",
		"Partie endet (%s)" % str(ev_names(ev)))
	check(str(ev_of(ev, "round_over").reason) == "left" and int(ev_of(ev, "game_over").winner) == 0, "Grund left, Sieger Platz 0")
	var v := g.view_for(0)
	check(str(v.hints.text).begins_with("Zu wenige Spieler"), "Hinweis „Zu wenige Spieler – …“ (%s)" % v.hints.text)
	check(I18n.render(v.hints.lt, false) == str(v.hints.text), "Bausteine = Text")
	# 3 Spieler, round_end last, einer fertig, ein Aktiver geht → Runde endet mit left
	g = RulesFixture.build(cfg({"round_end": "last"}), 3, {"hands": [["hell_rot_1", "hell_rot_2"], [], ["hell_blau_1", "hell_blau_2"]],
		"top": "hell_rot_5", "current": 0, "host": 0, "finished": [1]})
	ev = remove(g, 2, "letzter Gegner raus")
	check(g.state == "round_over" and str(g.result.reason) == "left" and g.result.ranking == [1, 0], "Runde endet, Rangliste [1, 0] (%s)" % str(g.result))


func _remove_round_over() -> void:
	var g := RulesFixture.build(cfg(), 3, {"hands": [["hell_rot_7"], ["hell_gelb_1", "hell_gelb_2"], ["hell_blau_1"]],
		"top": "hell_rot_5", "current": 0, "host": 2})
	play(g, 0, "hell_rot_7", "letzte Karte")
	var rk: Array = g.result.ranking
	var ev := remove(g, 1, "am Rundenende")
	check(ev_names(ev) == ["leave_cards", "seats"] and (g.result.points as Array).size() == 2 and (g.result.ranking as Array).size() == rk.size() - 1,
		"Ergebnis umnummeriert (%s)" % str(g.result))
	check(g.host == 1 and g.view_for(1).hints.can_next_round, "Gastgeber jetzt Platz 1, darf weiter")
	act(g, 1, {"a": "next_round"}, "nächste Runde zu zweit")
	check(g.players.size() == 2 and (g.hands[0] as Array).size() == 7, "zu zweit weiter")


func _save_load() -> void:
	var g := fresh(4, {"gamble_cards": "on", "discard_color": "on", "flip_mode": "card"}, 71)
	g.host = 0
	if g.current == 0:
		pass_turn(g)
	g.insert_player(2, {"name": "Neu"})
	g.remove_player(posmod(g.current + 1, 5) if posmod(g.current + 1, 5) != 0 else 3)
	var j := JSON.stringify(g.to_dict())
	var h := MauGame.from_dict(JSON.parse_string(j))
	check(JSON.stringify(h.to_dict()) == j, "Rundreise nach dem Umbau gleich")
	for i in 40:
		if not g.state in MauGame.PLAY_PHASES:
			break
		var s := g.current_seat()
		var a := MauBot.choose(g.view_for(s), i, 1)
		var ra := g.apply(s, a)
		var rb := h.apply(s, a)
		check(bool(ra.ok) == bool(rb.ok) and JSON.stringify(ra.events) == JSON.stringify(rb.events), "gleich weiter nach dem Laden (%d)" % i)


# --- Dauerlauf ---

func _bot_run() -> void:
	var games := GAMES
	if OS.get_environment("RULES_SEATS_GAMES").is_valid_int():
		games = int(OS.get_environment("RULES_SEATS_GAMES"))
	var t0 := Time.get_ticks_msec()
	var errors := 0
	var mine := 0
	for i in games:
		if not Teil.mine(i):
			continue
		mine += 1
		var err := _bot_game(i)
		if err != "":
			errors += 1
			if errors <= 10:
				print("FAIL: Partie %d: %s" % [i, err])
	check(errors == 0, "Dauerlauf mit Dazuholen/Entfernen: %d von %d Partien fehlerhaft" % [errors, mine])
	if mine >= 50:
		check(int(stats.get("dazu", 0)) > mine and int(stats.get("raus", 0)) > mine and int(stats.get("raus_am_zug", 0)) > 0
			and int(stats.get("raus_sonder", 0)) > 0 and int(stats.get("partie_left", 0)) > 0, "alle Fälle kommen vor (%s)" % str(stats))
	print("Dauerlauf Plätze%s: %d Partien in %.1f s – %s" % [Teil.label(), mine, (Time.get_ticks_msec() - t0) / 1000.0, str(stats)])


func _count(k: String) -> void:
	stats[k] = int(stats.get(k, 0)) + 1


func _bot_game(i: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7_300_019 * i + 3
	var c := RulesFixture.random_config(rng, rng.randf() < 0.5, rng.randf() < 0.5, rng.randf() < 0.5)
	var n := rng.randi_range(2, 8)
	var g := MauGame.create(c, RulesFixture.players(n, "bot"), rng.randi())
	g.start_round()
	var next_name := 0
	for r in ROUND_LIMIT:
		var steps := 0
		while g.state in MauGame.PLAY_PHASES:
			steps += 1
			if steps > STEP_LIMIT:
				return "Zugobergrenze (Runde %d, %d Spieler, %s)" % [g.round_no, g.players.size(), JSON.stringify(c.to_dict())]
			var roll := rng.randf()
			if roll < 0.02 and g.can_change_seats() and g.players.size() < MauGame.MAX_PLAYERS:
				next_name += 1
				var k := g.join_card_count()
				var cur_name := str(g.players[g.current].name)
				var res := g.insert_player(rng.randi_range(0, g.players.size()), {"name": "N%d" % next_name, "kind": "bot"})
				if not bool(res.ok):
					return "insert abgelehnt: " + str(res.reason)
				if str(g.players[g.current].name) != cur_name:
					return "insert ändert den Spieler am Zug"
				if (g.hands[int(res.seat)] as Array).size() != k:
					return "insert: %d statt %d Karten" % [(g.hands[int(res.seat)] as Array).size(), k]
				_count("dazu")
			elif roll < 0.04:
				var s := rng.randi_range(0, g.players.size() - 1)
				if rng.randf() < 0.3:
					s = g.current
				if g.can_remove_now(s):
					if g.state != "turn":
						_count("raus_sonder")
					if s == g.current:
						_count("raus_am_zug")
					var res := g.remove_player(s)
					if not bool(res.ok):
						return "remove abgelehnt: " + str(res.reason)
					_count("raus")
					if g.state == "game_over" and g.players.size() == 1:
						_count("partie_left")
						return RulesFixture.card_check(g)
			if g.state in MauGame.PLAY_PHASES:
				var inv_err := RulesFixture.invariants(g)
				if inv_err != "":
					return "Invariante (Runde %d, Phase %s): %s" % [g.round_no, g.state, inv_err]
			else:
				var cc := RulesFixture.card_check(g)
				if cc != "":
					return cc
				break
			# Erwischen durch andere manchmal
			if g.mau_open >= 0 and rng.randf() < 0.5:
				var o := rng.randi_range(0, g.players.size() - 1)
				var ca := MauBot.choose(g.view_for(o), rng.randi(), 1)
				if str(ca.get("a", "")) == "catch":
					var cr := g.apply(o, ca)
					if not bool(cr.ok):
						return "catch abgelehnt: " + str(cr.reason)
			var seat := g.current_seat()
			var a := MauBot.choose(g.view_for(seat), rng.randi(), rng.randi_range(0, 2))
			if a.is_empty():
				return "Bot ohne Aktion in Phase %s" % g.state
			var rr := g.apply(seat, a)
			if not bool(rr.ok):
				return "Aktion %s abgelehnt: %s (Phase %s)" % [JSON.stringify(a), rr.reason, g.state]
		if g.state == "game_over":
			return ""
		if g.state != "round_over":
			return "unerwartete Phase " + g.state
		if str(g.result.get("reason", "")) == "left":
			_count("runde_left")
		# am Rundenende auch mal dazuholen/entfernen
		if rng.randf() < 0.3 and g.players.size() < MauGame.MAX_PLAYERS:
			next_name += 1
			if not bool(g.insert_player(rng.randi_range(0, g.players.size()), {"name": "R%d" % next_name, "kind": "bot"}).ok):
				return "insert am Rundenende abgelehnt"
		if rng.randf() < 0.2 and g.players.size() > 2:
			var s := rng.randi_range(0, g.players.size() - 1)
			if s != g.host and not bool(g.remove_player(s).ok):
				return "remove am Rundenende abgelehnt"
		if c.effective_scoring() != "points500" and r >= 3:
			return ""
		var nr := g.apply(g.host, {"a": "next_round"})
		if not bool(nr.ok):
			return "next_round abgelehnt: " + str(nr.reason)
	return ""
