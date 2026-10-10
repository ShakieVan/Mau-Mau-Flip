extends SceneTree
# Flip-Überraschung mit allen Karten (Beta 1.4.8, Nutzerwunsch: „Wäre schön, wenn da alle Karten funktionieren würden“): Liegt nach
# einem Flip eine Zusatzkarte oben, wirkt sie, als hätte der Flip-Spieler sie gelegt.
#   - Kartentausch: alle geben ihre Hand weiter (Tauschrichtung, zu zweit, Fertige tauschen nicht mit), Mau-Fenster verfällt.
#   - Glücksspiel: erst Farbwahl, dann Phase gamble für den Flip-Spieler (Aufhören, Treffer, leere Hand = fertig).
#   - Ablegen-Karte: Phase discard_pick ohne Zurücknehmen (auch nach Speichern), ohne Karten der Farbe gleich weiter, alles abgelegt =
#     fertig, Mau-Fenster.
#   - Ablegen-Joker: Farbwahl = Ablegefarbe (ohne Ereignis color), dann Auswahl mit Spielfarbe; Bot wählt die häufigste Farbe.
#   - Flip oben: keine Kette; Wünscher: nur Farbwahl; fertiger Flip-Spieler: Glücksspiel/Ablegen wirken nicht.
# Jede Prüfung mit flip_mode pile und card und mit/ohne Stapeln + penalty_turn = play. Dazu Bot-Dauerlauf mit allen Hausregeln
# und Flip-Überraschung (keine Hänger, keine abgelehnte Aktion, Kartenerhaltung, jede neue Überraschung kommt vor).

const Teil := preload("res://tests/teil.gd")
const OTHERS := [["hell_gelb_1/dunkel_pink_6", "hell_gelb_3", "hell_gelb_5"], ["hell_gelb_2", "hell_gelb_4", "hell_gelb_6", "hell_gelb_7"]]
const VARIANTS := [{}, {"stacking": "same", "penalty_turn": "play"}]
const BOT_GAMES := 240
const STEP_LIMIT := 5000

var ok := 0
var fails := 0
var surprises := {}


func check(cond: bool, what: String) -> void:
	if cond:
		ok += 1
	else:
		fails += 1
		print("FAIL: " + what)


func cfg(over: Dictionary) -> RuleConfig:
	var c := RuleConfig.new()
	c.apply_dict(over)
	return c


func act(g: MauGame, seat: int, action: Dictionary, what: String) -> Array:
	var r := g.apply(seat, action)
	check(bool(r.ok), "%s: %s" % [what, str(r.get("reason", ""))])
	var bad := RulesFixture.invariants(g)
	check(bad == "", "%s: Invariante %s" % [what, bad])
	return r.get("events", [])


func refuse(g: MauGame, seat: int, action: Dictionary, what: String) -> void:
	var before := JSON.stringify(g.to_dict())
	var r := g.apply(seat, action)
	check(not bool(r.ok) and JSON.stringify(g.to_dict()) == before, "%s: abgelehnt, Zustand unverändert (%s)" % [what, str(r.get("reason", ""))])


func names(ev: Array) -> Array:
	var out: Array = []
	for e in ev:
		out.append(str(e.get("e", "")))
	return out


func find_ev(ev: Array, n: String) -> Dictionary:
	for e in ev:
		if str(e.get("e", "")) == n:
			return e
	return {}


func in_order(ev: Array, list: Array) -> bool:
	var order := names(ev)
	var last := -1
	for n in list:
		var i := order.find(n, last + 1)
		if i < 0:
			return false
		last = i
	return true


func ids(g: MauGame, seat: int, keys: Array) -> Array:
	var out: Array = []
	for k in keys:
		out.append(RulesFixture.card(g, seat, str(k)))
	return out


func sorted(a: Array) -> Array:
	var b := a.duplicate()
	b.sort()
	return b


# Platz 0 legt den Flip (hell → dunkel). back = Gesicht, das danach oben liegt: bei pile die Gegenseite der untersten Ablagekarte,
# bei card die Gegenseite der Flip-Karte. rest0 = übrige Karten von Platz 0 (Hand nach dem Flip), others = Hände der anderen.
func game(mode: String, back: String, rest0: Array, over := {}, others: Array = OTHERS, extra := {}) -> MauGame:
	var c := {"flip_surprise": "on", "swap_cards": "on", "gamble_cards": "on", "discard_color": "on", "flip_mode": mode}
	c.merge(over, true)
	var h0: Array = ["hell_rot_flip/" + back if mode == "card" else "hell_rot_flip"]
	h0.append_array(rest0)
	var hands: Array = [h0]
	hands.append_array(others)
	var spec := {"hands": hands, "top": "hell_rot_5/dunkel_orange_3",
		"discard": ["hell_blau_4/" + (back if mode == "pile" else "dunkel_tuerkis_9")]}
	spec.merge(extra, true)
	return RulesFixture.build(cfg(c), hands.size(), spec)


func play_flip(g: MauGame, what: String) -> Array:
	return act(g, 0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_rot_flip")}, what)


func label(mode: String, over: Dictionary) -> String:
	return "[%s%s]" % [mode, " " + JSON.stringify(over) if not over.is_empty() else ""]


func _initialize() -> void:
	if Teil.first():
		for mode in ["pile", "card"]:
			for over in VARIANTS:
				_swap(mode, over)
				_gamble(mode, over)
				_discard(mode, over)
				_discard_wild(mode, over)
				_no_chain(mode, over)
		_finished_flip_player()
		_remove_during_pick()
		_texts()
	_bots()
	print("RESULT: %d ok" % ok if fails == 0 else "RESULT: %d ok, %d FAIL" % [ok, fails])
	quit(0 if fails == 0 else 1)


# --- Kartentausch ---

func _swap(mode: String, over: Dictionary) -> void:
	var L := label(mode, over)
	var g := game(mode, "dunkel_lila_tausch", ["hell_rot_1", "hell_rot_2"], over)
	var h0: Array = (g.hands[0] as Array).duplicate()
	h0.erase(RulesFixture.card(g, 0, "hell_rot_flip"))
	var h1: Array = (g.hands[1] as Array).duplicate()
	var h2: Array = (g.hands[2] as Array).duplicate()
	var ev := play_flip(g, "Tausch %s" % L)
	check(in_order(ev, ["flip", "flip_surprise", "swap_hands", "turn"]), "Tausch %s: Reihenfolge (%s)" % [L, str(names(ev))])
	check(str(find_ev(ev, "flip_surprise").get("face", "")) == "dunkel_lila_tausch", "Tausch %s: Gesicht im Ereignis" % L)
	check(g.hands[1] == h0 and g.hands[2] == h1 and g.hands[0] == h2, "Tausch %s: Hände im Uhrzeigersinn weitergegeben" % L)
	check(g.current_seat() == 1 and g.phase() == "turn", "Tausch %s: der Nächste ist dran" % L)
	var sw2: Dictionary = find_ev(g.events_for(2, ev), "swap_hands")
	check(not sw2.has("hands") and (sw2.get("hand", []) as Array).size() == h1.size(), "Tausch %s: nur die eigene neue Hand im Ereignis" % L)
	# Tauschrichtung „in Spielrichtung“ bei Richtung gegen den Uhrzeigersinn
	var o2 := over.duplicate()
	o2["swap_direction"] = "play"
	g = game(mode, "dunkel_lila_tausch", ["hell_rot_1", "hell_rot_2"], o2, OTHERS, {"dir": -1})
	h0 = (g.hands[0] as Array).duplicate()
	h0.erase(RulesFixture.card(g, 0, "hell_rot_flip"))
	h1 = (g.hands[1] as Array).duplicate()
	h2 = (g.hands[2] as Array).duplicate()
	play_flip(g, "Tausch in Spielrichtung %s" % L)
	check(g.hands[2] == h0 and g.hands[1] == h2 and g.hands[0] == h1 and g.current_seat() == 2,
		"Tausch %s: in Spielrichtung (gegen den Uhrzeigersinn)" % L)
	# zu zweit: Hände tauschen
	g = game(mode, "dunkel_lila_tausch", ["hell_rot_1", "hell_rot_2"], over, [OTHERS[0]])
	h0 = (g.hands[0] as Array).duplicate()
	h0.erase(RulesFixture.card(g, 0, "hell_rot_flip"))
	h1 = (g.hands[1] as Array).duplicate()
	play_flip(g, "Tausch zu zweit %s" % L)
	check(g.hands[0] == h1 and g.hands[1] == h0 and g.current_seat() == 1, "Tausch %s: zu zweit Hände getauscht" % L)
	# Mau-Fenster: Flip-Spieler hat danach 1 Karte, ohne Ruf – der Tausch löscht das Fenster, der Empfänger muss nicht rufen
	g = game(mode, "dunkel_lila_tausch", ["hell_rot_1"], over)
	play_flip(g, "Tausch mit 1 Karte %s" % L)
	check(g.mau_open == -1 and (g.hands[1] as Array).size() == 1 and not bool(g.mau_said[1]) and (g.view_for(2).hints.catch as Array).is_empty(),
		"Tausch %s: Mau-Fenster verfällt, niemand zu erwischen" % L)


# --- Glücksspiel ---

func _gamble(mode: String, over: Dictionary) -> void:
	var L := label(mode, over)
	var rest := ["hell_rot_1/dunkel_pink_1", "hell_rot_2/dunkel_pink_2"]
	var g := game(mode, "dunkel_gluecksspiel", rest, over)
	var ev := play_flip(g, "Glücksspiel %s" % L)
	check(g.phase() == "color" and g.current_seat() == 0 and not names(ev).has("flip_surprise") and names(ev).has("choose_color"),
		"Glücksspiel %s: zuerst Farbwahl" % L)
	ev = act(g, 0, {"a": "color", "color": "tuerkis"}, "Glücksspiel Farbe %s" % L)
	check(in_order(ev, ["color", "flip_surprise", "gamble_start"]) and g.phase() == "gamble" and g.current_seat() == 0
		and g.color == "tuerkis" and int(g.gamble.seat) == 0, "Glücksspiel %s: Farbe, Überraschung, Glücksspiel (%s)" % [L, str(names(ev))])
	var h: Dictionary = g.view_for(0).hints
	check((h.can_stake as Array).size() == 2 and not bool(h.can_stop) and bool(h.can_mau), "Glücksspiel %s: setzen, Mau vor dem Setzen möglich" % L)
	check(g.view_for(1).gamble.seat == 0, "Glücksspiel %s: öffentlich sichtbar" % L)
	g.force_rolls([0])
	act(g, 0, {"a": "stake", "card": RulesFixture.card(g, 0, "dunkel_pink_1")}, "setzen %s" % L)
	act(g, 0, {"a": "press"}, "drücken %s" % L)
	check(bool(g.view_for(0).hints.can_stop), "Glücksspiel %s: Aufhören nach 0" % L)
	ev = act(g, 0, {"a": "stop"}, "aufhören %s" % L)
	check(str(find_ev(ev, "stake_discard").get("reason", "")) == "stop" and g.current_seat() == 1 and g.phase() == "turn"
		and (g.hands[0] as Array).size() == 1 and g.color == "tuerkis", "Glücksspiel %s: Aufhören, Einsatz unter die Ablage, Farbe bleibt" % L)
	check(g.mau_open == 0 and (g.view_for(1).hints.catch as Array).has(0), "Glücksspiel %s: ohne Ruf erwischbar" % L)
	# Treffer: ziehen, Einsatz zurück
	g = game(mode, "dunkel_gluecksspiel", rest, over)
	play_flip(g, "Glücksspiel Treffer %s" % L)
	act(g, 0, {"a": "color", "color": "pink"}, "Farbe %s" % L)
	g.force_rolls([4])
	act(g, 0, {"a": "stake", "card": RulesFixture.card(g, 0, "dunkel_pink_1")}, "setzen %s" % L)
	ev = act(g, 0, {"a": "press"}, "Treffer %s" % L)
	check(names(ev).has("stake_back") and (g.hands[0] as Array).size() == 6 and g.current_seat() == 1, "Glücksspiel %s: Treffer 4, Einsatz zurück" % L)
	# Flip-Spieler mit 1 Karte: setzen, 0 → fertig
	g = game(mode, "dunkel_gluecksspiel", ["hell_rot_1/dunkel_pink_1"], over)
	play_flip(g, "Glücksspiel 1 Karte %s" % L)
	act(g, 0, {"a": "color", "color": "pink"}, "Farbe %s" % L)
	g.force_rolls([0])
	act(g, 0, {"a": "stake", "card": RulesFixture.card(g, 0, "dunkel_pink_1")}, "letzte Karte setzen %s" % L)
	ev = act(g, 0, {"a": "press"}, "drücken %s" % L)
	check(names(ev).has("finish") and str(find_ev(ev, "stake_discard").get("reason", "")) == "empty" and g.phase() == "round_over"
		and int((g.result.ranking as Array)[0]) == 0, "Glücksspiel %s: leere Hand, fertig (%s)" % [L, g.phase()])


# --- Farbe mit ablegen ---

func _discard(mode: String, over: Dictionary) -> void:
	var L := label(mode, over)
	var rest := ["hell_rot_1/dunkel_lila_1", "hell_rot_2/dunkel_lila_2", "hell_rot_3/dunkel_pink_3"]
	var g := game(mode, "dunkel_lila_ablegen", rest, over)
	var ev := play_flip(g, "Ablegen %s" % L)
	check(in_order(ev, ["flip", "flip_surprise", "discard_pick"]) and g.phase() == "discard_pick" and g.current_seat() == 0,
		"Ablegen %s: Auswahl für den Flip-Spieler (%s)" % [L, str(names(ev))])
	var lila := ids(g, 0, ["dunkel_lila_1", "dunkel_lila_2"])
	var v := g.view_for(0)
	check(sorted(v.hints.can_pick) == sorted(lila) and not bool(v.hints.pick_color) and not bool(v.hints.can_undo)
		and str(v.discard_pick.color) == "lila", "Ablegen %s: Kandidaten, kein Zurücknehmen (%s)" % [L, str(v.hints)])
	check(bool(v.hints.can_mau), "Ablegen %s: Mau vor der Auswahl möglich (3 Karten, 2 lila)" % L)
	refuse(g, 0, {"a": "undo"}, "Ablegen %s: Zurücknehmen" % L)
	g = MauGame.from_dict(JSON.parse_string(JSON.stringify(g.to_dict())))
	check(not bool(g.view_for(0).hints.can_undo), "Ablegen %s: nach Speichern kein Zurücknehmen" % L)
	refuse(g, 0, {"a": "undo"}, "Ablegen %s: Zurücknehmen nach Speichern" % L)
	ev = act(g, 0, {"a": "discard_pick", "cards": lila}, "Ablegen Auswahl %s" % L)
	var dc := find_ev(ev, "discard_color")
	check(int(dc.get("count", -1)) == 2 and RulesFixture.hand_keys(g, 0) == ["dunkel_pink_3"] and g.current_seat() == 1
		and RulesFixture.top_key(g) == "dunkel_lila_ablegen" and g.color == "lila", "Ablegen %s: 2 lila mitabgelegt" % L)
	check(g.mau_open == 0, "Ablegen %s: 1 Karte ohne Ruf → Mau-Fenster" % L)
	if mode == "card":
		check(int(g.dside.get(lila[0], -1)) == 1, "Ablegen [card]: Seite der mitabgelegten Karte gemerkt")
	# ohne Karten der Farbe: gleich weiter
	g = game(mode, "dunkel_lila_ablegen", ["hell_rot_1/dunkel_pink_1", "hell_rot_2/dunkel_pink_2"], over)
	ev = play_flip(g, "Ablegen ohne lila %s" % L)
	check(in_order(ev, ["flip_surprise", "discard_color"]) and int(find_ev(ev, "discard_color").get("count", -1)) == 0
		and g.phase() == "turn" and g.current_seat() == 1, "Ablegen %s: ohne Karten der Farbe weiter (%s)" % [L, str(names(ev))])
	# letzte Karte mit abgelegt → fertig
	g = game(mode, "dunkel_lila_ablegen", ["hell_rot_1/dunkel_lila_1"], over)
	play_flip(g, "Ablegen letzte %s" % L)
	ev = act(g, 0, {"a": "discard_pick", "cards": ids(g, 0, ["dunkel_lila_1"])}, "letzte Karte mit ablegen %s" % L)
	check(names(ev).has("finish") and g.phase() == "round_over", "Ablegen %s: alles abgelegt, fertig" % L)
	# mit Ruf: kein Fenster
	g = game(mode, "dunkel_lila_ablegen", rest, over)
	play_flip(g, "Ablegen mit Ruf %s" % L)
	act(g, 0, {"a": "mau"}, "Mau in der Auswahl %s" % L)
	act(g, 0, {"a": "discard_pick", "cards": ids(g, 0, ["dunkel_lila_1", "dunkel_lila_2"])}, "Auswahl nach Ruf %s" % L)
	check(g.mau_open == -1 and bool(g.mau_said[0]), "Ablegen %s: mit Ruf kein Fenster" % L)


func _discard_wild(mode: String, over: Dictionary) -> void:
	var L := label(mode, over)
	var rest := ["hell_rot_1/dunkel_lila_1", "hell_rot_2/dunkel_lila_2", "hell_rot_3/dunkel_pink_3"]
	var g := game(mode, "dunkel_ablegen_joker", rest, over)
	var ev := play_flip(g, "Ablegen-Joker %s" % L)
	check(g.phase() == "color" and g.current_seat() == 0 and not names(ev).has("flip_surprise"), "Ablegen-Joker %s: zuerst Farbwahl" % L)
	var v := g.view_for(0)
	check(str(v.hints.text).contains("Ablegen-Joker") and MauBot.discard_wish(v), "Ablegen-Joker %s: Hinweis Ablegefarbe (%s)" % [L, str(v.hints.text)])
	check(not MauBot.discard_wish(g.view_for(1)), "Ablegen-Joker %s: discard_wish nur für den Flip-Spieler" % L)
	var bot := MauBot.choose(v, 7, 1)
	check(str(bot.get("a", "")) == "color" and str(bot.get("color", "")) == "lila", "Ablegen-Joker %s: Bot wählt die häufigste Farbe (%s)" % [L, str(bot)])
	ev = act(g, 0, {"a": "color", "color": "lila"}, "Ablegefarbe %s" % L)
	check(names(ev) == ["flip_surprise", "discard_pick"] and g.phase() == "discard_pick" and g.color == "lila" and not g.wished,
		"Ablegen-Joker %s: Ablegefarbe ohne Farbereignis (%s)" % [L, str(names(ev))])
	v = g.view_for(0)
	check(bool(v.hints.pick_color) and not bool(v.hints.can_undo) and str(v.discard_pick.color) == "lila", "Ablegen-Joker %s: Spielfarbe fehlt noch" % L)
	refuse(g, 0, {"a": "undo"}, "Ablegen-Joker %s: Zurücknehmen" % L)
	refuse(g, 0, {"a": "discard_pick", "cards": ids(g, 0, ["dunkel_lila_1"])}, "Ablegen-Joker %s: ohne Spielfarbe" % L)
	ev = act(g, 0, {"a": "discard_pick", "cards": ids(g, 0, ["dunkel_lila_1", "dunkel_lila_2"]), "color": "pink"}, "Auswahl mit Spielfarbe %s" % L)
	check(in_order(ev, ["discard_color", "color"]) and g.color == "pink" and g.wished and g.current_seat() == 1
		and RulesFixture.hand_keys(g, 0) == ["dunkel_pink_3"], "Ablegen-Joker %s: abgelegt, weiter mit Pink" % L)
	# ohne Karten der Farbe: nur die Spielfarbe
	g = game(mode, "dunkel_ablegen_joker", ["hell_rot_1/dunkel_pink_1", "hell_rot_2/dunkel_pink_2"], over)
	play_flip(g, "Ablegen-Joker ohne Farbe %s" % L)
	act(g, 0, {"a": "color", "color": "orange"}, "Ablegefarbe orange %s" % L)
	check(g.phase() == "discard_pick" and (g.view_for(0).hints.can_pick as Array).is_empty(), "Ablegen-Joker %s: leere Auswahl" % L)
	act(g, 0, {"a": "discard_pick", "cards": [], "color": "pink"}, "nur Spielfarbe %s" % L)
	check(g.color == "pink" and g.current_seat() == 1 and (g.hands[0] as Array).size() == 2, "Ablegen-Joker %s: nur Spielfarbe gewählt" % L)
	# Speichern zwischen Ablegefarbe und Auswahl
	g = game(mode, "dunkel_ablegen_joker", rest, over)
	play_flip(g, "Ablegen-Joker speichern %s" % L)
	act(g, 0, {"a": "color", "color": "lila"}, "Ablegefarbe %s" % L)
	g = MauGame.from_dict(JSON.parse_string(JSON.stringify(g.to_dict())))
	check(g.phase() == "discard_pick" and not bool(g.view_for(0).hints.can_undo) and bool(g.view_for(0).hints.pick_color),
		"Ablegen-Joker %s: nach Speichern unverändert" % L)
	act(g, 0, {"a": "discard_pick", "cards": [], "color": "lila"}, "Auswahl nach Laden %s" % L)


# --- keine Kette, Wünscher ---

func _no_chain(mode: String, over: Dictionary) -> void:
	var L := label(mode, over)
	var g := game(mode, "dunkel_lila_flip", ["hell_rot_1", "hell_rot_2"], over)
	var ev := play_flip(g, "Flip oben %s" % L)
	check(names(ev).count("flip") == 1 and not names(ev).has("flip_surprise") and g.side == 1 and g.current_seat() == 1
		and g.phase() == "turn" and RulesFixture.top_key(g) == "dunkel_lila_flip", "Flip oben %s: keine Kette (%s)" % [L, str(names(ev))])
	g = game(mode, "dunkel_wuenscher", ["hell_rot_1", "hell_rot_2"], over)
	play_flip(g, "Wünscher oben %s" % L)
	check(g.phase() == "color", "Wünscher oben %s: Farbwahl" % L)
	ev = act(g, 0, {"a": "color", "color": "orange"}, "Farbe nach Wünscher %s" % L)
	check(not names(ev).has("flip_surprise") and g.current_seat() == 1 and g.phase() == "turn" and g.color == "orange",
		"Wünscher oben %s: nur Farbwahl" % L)
	# Aus: Zusatzkarten wirken nicht
	var off := over.duplicate()
	off["flip_surprise"] = "off"
	for back in ["dunkel_lila_tausch", "dunkel_lila_ablegen"]:
		g = game(mode, back, ["hell_rot_1/dunkel_lila_1", "hell_rot_2"], off)
		ev = play_flip(g, "%s ohne Hausregel %s" % [back, L])
		check(not names(ev).has("flip_surprise") and not names(ev).has("swap_hands") and g.phase() == "turn" and g.current_seat() == 1,
			"%s %s: ohne Hausregel keine Wirkung" % [back, L])


# Fertig mit dem Flip (round_end = last, Flip wird ausgeführt): Glücksspiel und Ablegen wirken nicht; Tausch unter den Übrigen.
func _finished_flip_player() -> void:
	var over := {"round_end": "last", "flip_last_card": "execute"}
	for mode in ["pile", "card"]:
		var g := game(mode, "dunkel_lila_tausch", [], over)
		var h1: Array = (g.hands[1] as Array).duplicate()
		var h2: Array = (g.hands[2] as Array).duplicate()
		var ev := play_flip(g, "fertig + Tausch [%s]" % mode)
		check(in_order(ev, ["finish", "flip", "flip_surprise", "swap_hands"]) and g.hands[1] == h2 and g.hands[2] == h1
			and g.current_seat() == 1, "fertig [%s]: Tausch nur unter den Übrigen (%s)" % [mode, str(names(ev))])
		for back in ["dunkel_lila_ablegen"]:
			g = game(mode, back, [], over)
			ev = play_flip(g, "fertig + %s [%s]" % [back, mode])
			check(not names(ev).has("flip_surprise") and g.phase() == "turn" and g.current_seat() == 1, "fertig [%s]: %s wirkt nicht" % [mode, back])
		for back in ["dunkel_gluecksspiel", "dunkel_ablegen_joker"]:
			g = game(mode, back, [], over)
			play_flip(g, "fertig + %s [%s]" % [back, mode])
			check(g.phase() == "color" and g.current_seat() == 0 and not MauBot.discard_wish(g.view_for(0))
				and not str(g.view_for(0).hints.text).contains("Ablegen-Joker"), "fertig [%s]: %s – nur Farbwahl" % [mode, back])
			var bot := MauBot.choose(g.view_for(0), 3, 1)
			ev = act(g, 0, bot, "Farbe fertiger Spieler %s" % back)
			check(names(ev).has("color") and not names(ev).has("flip_surprise") and g.phase() == "turn" and g.current_seat() == 1
				and g.gamble.is_empty(), "fertig [%s]: %s wirkt nicht" % [mode, back])


# Der Flip-Spieler (Gast, nicht Gastgeber) wird mitten in der Auswahl herausgenommen: Die Farbe bleibt gültig.
func _remove_during_pick() -> void:
	var c := cfg({"flip_surprise": "on", "discard_color": "on"})
	var g := RulesFixture.build(c, 3, {"hands": [["hell_gelb_1"], ["hell_rot_flip", "hell_rot_1/dunkel_lila_1"], ["hell_gelb_2"]],
		"top": "hell_rot_5", "discard": ["hell_blau_4/dunkel_ablegen_joker"], "current": 1})
	act(g, 1, {"a": "play", "card": RulesFixture.card(g, 1, "hell_rot_flip")}, "Flip von Platz 1")
	act(g, 1, {"a": "color", "color": "lila"}, "Ablegefarbe")
	check(g.phase() == "discard_pick", "Auswahl offen")
	var r := g.remove_player(1)
	check(bool(r.ok) and g.dpick.is_empty() and g.color == "lila" and g.phase() == "turn" and RulesFixture.invariants(g) == "",
		"Herausnehmen in der Auswahl: Farbe gültig (%s, %s)" % [g.color, RulesFixture.invariants(g)])


func _texts() -> void:
	var fam := RuleConfig.preset("familie")
	var help := " ".join(RulesText.card_help("hell_rot_flip", fam))
	check(help.contains("Kartentausch oben") and help.contains("Glücksspiel oben") and help.contains("Ablegen-Karte oben")
		and help.contains("keine Kette"), "Kartenhilfe Flip nennt die Zusatzkarten")
	var plain := cfg({"flip_surprise": "on"})
	var help2 := " ".join(RulesText.card_help("hell_rot_flip", plain))
	check(not help2.contains("Kartentausch oben") and help2.contains("Flip-Überraschung"), "ohne Zusatzkarten keine Zusatzzeilen")
	var ov := ""
	for p in RulesText.overview(fam):
		ov += str(p.text)
	check(ov.contains("keine Kette") and ov.contains("Kartentausch, Glücksspiel und Farbe mit ablegen"), "Regelübersicht")
	check(" ".join(fam.describe()).contains("als hätte der Flip-Spieler sie gelegt"), "Kurzfassung")


# --- Bot-Dauerlauf ---

func _bots() -> void:
	var t0 := Time.get_ticks_msec()
	var errors := 0
	var played := 0
	for i in BOT_GAMES:
		if not Teil.mine(i):
			continue
		played += 1
		var err := _bot_game(i)
		if err != "":
			errors += 1
			if errors <= 10:
				print("FAIL: Partie %d: %s" % [i, err])
	check(errors == 0, "Bot-Dauerlauf mit Flip-Überraschung: %d von %d Partien fehlerhaft" % [errors, played])
	if Teil.count() <= 1:
		for k in [MauGame.SWAP, MauGame.GAMBLE, MauGame.DISCARD, MauGame.DISCARD_WILD]:
			check(int(surprises.get(k, 0)) > 0, "Überraschung %s kommt im Dauerlauf vor (%s)" % [k, str(surprises)])
	print("Bot-Dauerlauf Flip-Überraschung%s: %d Partien in %.1f s – %s" % [Teil.label(), played, (Time.get_ticks_msec() - t0) / 1000.0, str(surprises)])


func _bot_game(i: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7_310_011 * i + 5
	var c := RulesFixture.random_config(rng, true, true, true)
	c.flip_surprise = "on"
	var n := rng.randi_range(2, 8)
	var g := MauGame.create(c, RulesFixture.players(n, "bot"), rng.randi())
	g.start_round()
	for r in 3:
		var steps := 0
		while g.state in MauGame.PLAY_PHASES:
			steps += 1
			if steps > STEP_LIMIT:
				return "Runde %d: Zugobergrenze (Phase %s)" % [r, g.state]
			if g.mau_open >= 0 and rng.randf() < 0.5:
				var o := rng.randi_range(0, n - 1)
				var ca := MauBot.choose(g.view_for(o), rng.randi(), 1)
				if str(ca.get("a", "")) == "catch" and not bool(g.apply(o, ca).ok):
					return "catch abgelehnt"
			var seat := g.current_seat()
			var act := MauBot.choose(g.view_for(seat), rng.randi(), rng.randi_range(0, 2))
			if act.is_empty():
				return "Bot ohne Aktion in Phase %s (%s)" % [g.state, str(g.view_for(seat).hints)]
			var res := g.apply(seat, act)
			if not bool(res.ok):
				return "Aktion %s abgelehnt: %s (%s)" % [JSON.stringify(act), res.reason, JSON.stringify(c.to_dict())]
			for e in res.events:
				if str(e.get("e", "")) == "flip_surprise":
					var k := str(CardDB.parse_key(str(e.get("face", ""))).get("kind", ""))
					surprises[k] = int(surprises.get(k, 0)) + 1
			var bad := RulesFixture.invariants(g)
			if bad != "":
				return "Runde %d: %s nach %s" % [r, bad, JSON.stringify(act)]
		if g.is_over():
			return ""
		var nr := g.apply(0, {"a": "next_round"})
		if not bool(nr.ok):
			return "next_round abgelehnt: " + str(nr.reason)
	return ""
