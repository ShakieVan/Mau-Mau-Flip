extends SceneTree

# Modul G, LocalTable: Übungsspiel (1 Mensch + 3 Bots, der „Mensch“ entscheidet per MauBot) bis Rundenende und weiter in Runde 2,
# Denkpausen der Bots, Weitergeben mit 3 Menschen (+ Bot): Sichtschutz vor jedem Menschenwechsel, nie eine fremde Hand in
# state_changed, keine fremden gezogenen Gesichter in den Ereignissen; Speichern und Fortsetzen.
# Hausregeln mit Zusatzkarten (Familie mit Kartentausch, dazu Glücksspiel und Farbe ablegen = 124 Karten): ganze Partien im
# Übungsspiel und im Weitergeben-Modus mit Kartenerhaltung (Hände + Stapel + Ablage + Einsätze = Kartenzahl) nach jedem Schritt;
# Kartentausch, Glücksspiel und Farbe ablegen kommen wirklich vor. Weitergeben (AGENTS.md 15): Nach einem Kartentausch und im
# Glücksspiel kommt vor jeder fremden Hand der Sichtschutz, das Signal handover trägt nur Platz und Name, zwischen handover und
# reveal() gibt es keine Sicht; Einsätze, getauschte Hände und Einsatzrückgaben anderer bleiben verdeckt. Dazu ein erzwungener
# Ablauf (Kartentausch, dann Glücksspiel mit festen Drucken) mit zwei Menschen.

const SAVE := "user://test_game_partie.json"

var failures := 0
var checks := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)


func _initialize() -> void:
	test_solo()
	test_solo_pauses()
	test_pass(3, 0, "auto", 11)
	test_pass(3, 1, "catch", 12)
	test_pass(2, 2, "auto", 13)
	test_save_resume()
	test_house_solo()
	test_house_pass(3, 1, 21)
	test_house_pass(2, 1, 22)
	test_house_pass_forced()
	TableSource.clear_saved(SAVE)
	print("RESULT: %d ok" % checks if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)


# ---------- Hilfen ----------

func new_table() -> LocalTable:
	var t := LocalTable.new()
	t.auto_process = false
	t.speed = 0.0
	t.autosave = false
	t.save_path = SAVE
	root.add_child(t)
	return t


func ids_of(hand: Array) -> Array:
	var out: Array = []
	for item in hand:
		out.append(int(item.id))
	out.sort()
	return out


func sorted_ints(a: Array) -> Array:
	var out: Array = []
	for x in a:
		out.append(int(x))
	out.sort()
	return out


# Hände + Nachziehstapel + Ablage + Einsatz des Glücksspiels
func total_cards(g: MauGame) -> int:
	var n := g.draw_pile.size() + g.discard.size() + (g.gamble.get("stake", []) as Array).size()
	for h in g.hands:
		n += (h as Array).size()
	return n


# Kartenerhaltung: jede id genau einmal, Summe = Kartenzahl der Regeln (112 … 124); "" = in Ordnung
func cards_ok(g: MauGame) -> String:
	var err := RulesFixture.card_check(g)
	if err == "" and total_cards(g) != g.config.card_count():
		err = "%d statt %d Karten" % [total_cards(g), g.config.card_count()]
	return err


# Prüft eine ausgegebene Sicht samt Ereignissen gegen den echten Zustand: nur die eigene Hand, keine fremden Gesichter.
# Hausregeln: beim Kartentausch nur die eigene neue Hand, Einsätze und Einsatzrückgaben anderer verdeckt, nie die Trefferquote.
func check_private(t: GameTable, events: Array, view: Dictionary, label: String) -> bool:
	var seat := int(view.get("seat", -1))
	var ok := seat >= 0 and ids_of(view.hand) == sorted_ints(t.game.hands[seat])
	var why := "" if ok else "Hand"
	for p in view.players:
		if (p as Dictionary).has("hand") or (int(p.seat) == seat and not (p.backs as Array).is_empty()):
			ok = false
			why = "players"
	for e in events:
		var d: Dictionary = e
		var foreign := int(d.get("seat", -1)) != seat
		match str(d.get("e", "")):
			"draw":
				if foreign and (d.has("faces") or d.has("cards")):
					ok = false
					why = "draw"
			"challenge":
				if foreign and d.has("hand"):
					ok = false
					why = "challenge"
			"swap_hands":
				var b: Array = d.get("backs", [])
				if d.has("hands") or (seat < b.size() and not (b[seat] as Array).is_empty()):
					ok = false
					why = "swap_hands"
			"stake":
				if foreign and (d.has("card") or d.has("face") or d.has("back")):
					ok = false
					why = "stake"
			"stake_back", "stake_discard":
				if foreign and (d.has("cards") or d.has("faces")):
					ok = false
					why = str(d.e)
	var gv: Variant = view.get("gamble", {})
	if gv is Dictionary and ((gv as Dictionary).has("q") or not ((gv as Dictionary).get("stake", 0) is int)):
		ok = false
		why = "gamble"
	var text := JSON.stringify(view) + JSON.stringify(events)
	if text.contains("rng_state") or text.contains("\"snap\"") or text.contains("\"seed\"") or text.contains("\"q\""):
		ok = false
		why = "Zufall/Quote"
	if not ok:
		print("  Sicht/Ereignisse (%s) für Platz %d nicht privat: %s" % [label, seat, why])
	return ok


# ---------- Übungsspiel ----------

func test_solo() -> void:
	var t := new_table()
	var players := [{"name": "Bot A", "kind": "bot"}, {"name": "Lena", "kind": "human"}, {"name": "Bot B", "kind": "bot"},
		{"name": "Bot C", "kind": "bot"}]
	check(t.setup("solo", players, RuleConfig.preset("offiziell"), 4711), "Solo: setup")
	check(not t.setup("solo", [{"name": "A", "kind": "human"}, {"name": "B", "kind": "human"}]), "Solo mit 2 Menschen abgelehnt")
	check(t.setup("solo", players, RuleConfig.preset("offiziell"), 4711), "Solo: setup erneut")
	var log := {"states": 0, "private": true, "seat_ok": true, "handover": 0, "started": -1}
	t.state_changed.connect(func(ev: Array, v: Dictionary) -> void:
		log.states += 1
		if int(v.seat) != 1:
			log.seat_ok = false
		if not check_private(t, ev, v, "solo"):
			log.private = false)
	t.handover.connect(func(_s: int, _n: String) -> void: log.handover += 1)
	t.game_started.connect(func(s: int) -> void: log.started = s)
	t.start()
	check(log.started == 1 and t.local_seat() == 1 and t.mode() == "solo", "Solo: Mensch auf Platz 1, game_started")
	check(log.states >= 1 and int(t.current_view().get("round", 0)) == 1, "Solo: Stand nach dem Austeilen")
	check(t.host_seat == 1 and bool(t.seats[1].host), "Solo: der Mensch ist Gastgeber-Platz")
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var rounds := 0
	var last := -1
	var acts := 0
	var guard := 0
	var cards_ok := true
	while rounds < 2 and guard < 20000:
		guard += 1
		t.pump()
		if total_cards(t.game) != 112:
			cards_ok = false
		var v := t.current_view()
		if t.game.phase() == "round_over":
			rounds += 1
			check(bool(v.hints.can_next_round), "Solo: Mensch darf die nächste Runde starten (Runde %d)" % rounds)
			check(not (v.result as Dictionary).is_empty(), "Solo: Ergebnis in der Sicht")
			if rounds < 2:
				t.act({"a": "next_round"})
				check(t.game.round_no == 2 and t.game.phase() in MauGame.PLAY_PHASES, "Solo: Runde 2 läuft")
			last = -1
			continue
		if log.states == last:
			continue
		last = log.states
		var a := MauBot.choose(v, rng.randi(), 1)
		if not a.is_empty():
			acts += 1
			t.act(a)
	check(rounds == 2, "Solo: zwei Runden bis zum Ende gespielt (%d Schleifen, %d Aktionen des Menschen)" % [guard, acts])
	check(acts > 3, "Solo: der Mensch hat gehandelt")
	check(cards_ok, "Solo: immer 112 Karten")
	check(log.seat_ok, "Solo: jede Sicht ist die des Menschen")
	check(log.private, "Solo: nie eine fremde Hand oder fremde gezogene Karten")
	check(log.handover == 0, "Solo: kein Sichtschutz")
	# Fehlaktion → Hinweis
	var notes: Array = []
	t.notice.connect(func(text: String) -> void: notes.append(text))
	t.act({"a": "play", "card": 999})
	check(not notes.is_empty(), "Solo: abgelehnte Aktion meldet notice")
	t.leave()
	check(t.game == null, "Solo: leave")
	t.free()


func test_solo_pauses() -> void:
	var t := new_table()
	t.speed = 1.0
	# Bot gibt (Platz 0), Platz 1 beginnt: hier ein Bot, damit nach dem Austeilen sofort ein Bot dran ist.
	var players := [{"name": "Lena", "kind": "human"}, {"name": "Bot A", "kind": "bot"}, {"name": "Bot B", "kind": "bot"}]
	t.setup("solo", players, RuleConfig.preset("offiziell"), 77)
	var stamps: Array = []
	t.state_changed.connect(func(_e: Array, _v: Dictionary) -> void: stamps.append(Time.get_ticks_msec()))
	var t0 := Time.get_ticks_msec()
	t.start()
	var cur := t.game.current_seat()
	var bot_turn := t.is_bot(cur)
	t.pump()
	check(stamps.size() == 1, "Pause: Bot handelt nicht sofort nach dem Austeilen")
	if bot_turn:
		while stamps.size() < 2 and Time.get_ticks_msec() - t0 < 4000:
			t.pump()
			OS.delay_msec(5)
		var dt := int(stamps[1]) - t0 if stamps.size() > 1 else -1
		check(dt >= int((GameTable.THINK_MIN + GameTable.ROUND_PAUSE) * 1000) - 20 and dt <= int((GameTable.THINK_MAX + GameTable.ROUND_PAUSE) * 1000) + 300,
			"Pause: erster Bot-Zug nach Denkpause + Austeilen (%d ms)" % dt)
	else:
		check(true, "Pause: Mensch beginnt")
	# Oberfläche beschäftigt → Bots warten
	var busy := [true]
	t.busy_check = func() -> bool: return busy[0]
	var before := stamps.size()
	var end := Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < end:
		t.pump()
		if t.game.current_seat() == 0:
			break
		OS.delay_msec(5)
	if t.game.current_seat() != 0:
		check(stamps.size() == before, "Pause: busy_check hält die Bots an")
	busy[0] = false
	t.leave()
	t.free()


# ---------- Weitergeben ----------

func test_pass(humans: int, bots: int, mau_call: String, rng_seed: int) -> void:
	var t := new_table()
	var players: Array = []
	for i in humans + bots:
		# Menschen und Bots abwechselnd verteilt
		var bot := i % 2 == 1 and bots > 0 and players.filter(func(p): return p.kind == "bot").size() < bots
		if players.filter(func(p): return p.kind == "human").size() >= humans:
			bot = true
		players.append({"name": ("Bot %d" % i) if bot else ("Mensch %d" % i), "kind": "bot" if bot else "human"})
	var cfg := RuleConfig.preset("offiziell")
	cfg.mau_call = mau_call
	var label := "Weitergeben %d+%d (%s)" % [humans, bots, mau_call]
	check(t.setup("pass", players, cfg, rng_seed), label + ": setup")
	check(not t.setup("pass", [{"name": "A", "kind": "human"}, {"name": "B", "kind": "bot"}]), label + ": nur 1 Mensch abgelehnt")
	t.setup("pass", players, cfg, rng_seed)
	var log := {"states": 0, "private": true, "handovers": 0, "awaiting": -1, "shown": -1, "leak_between": 0, "switch_ok": true,
		"switches": 0, "own_seat": true}
	t.handover.connect(func(s: int, n: String) -> void:
		log.handovers += 1
		log.awaiting = s
		if n != str(t.seats[s].name) or t.is_bot(s):
			log.switch_ok = false)
	t.state_changed.connect(func(ev: Array, v: Dictionary) -> void:
		log.states += 1
		var s := int(v.seat)
		if t.pending_handover() >= 0:
			log.leak_between += 1              # Sicht, während der Sichtschutz noch wartet
		if s != log.shown and log.awaiting != s:
			log.switch_ok = false              # Menschenwechsel ohne Sichtschutz
		if s != log.shown:
			log.switches += 1
		log.shown = s
		log.awaiting = -1
		if s != t.local_seat() or t.is_bot(s):
			log.own_seat = false
		if not check_private(t, ev, v, label):
			log.private = false)
	t.start()
	check(log.states == 0 and log.handovers == 0 or log.handovers == 1, label + ": Start – erst Sichtschutz, keine Hand")
	t.pump()
	check(log.handovers == 1 and t.pending_handover() >= 0 and t.local_seat() == -1 and log.states == 0,
		label + ": Sichtschutz vor der ersten Hand")
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var rounds := 0
	var last := -1
	var guard := 0
	var acts := 0
	while rounds < 2 and guard < 30000:
		guard += 1
		t.pump()
		if t.pending_handover() >= 0:
			# während der Sichtschutz wartet: Aktionen werden abgelehnt
			if guard % 7 == 0:
				var n_before: int = log.states
				t.act({"a": "draw"})
				check(log.states == n_before, label + ": keine Aktion hinter dem Sichtschutz")
			t.reveal()
			continue
		if t.game.phase() == "round_over":
			rounds += 1
			check(bool(t.current_view().hints.can_next_round), label + ": gezeigter Mensch darf weiterschalten")
			if rounds < 2:
				t.act({"a": "next_round"})
			last = -1
			continue
		if log.states == last:
			continue
		last = log.states
		var a := MauBot.choose(t.current_view(), rng.randi(), 1)
		if not a.is_empty():
			acts += 1
			t.act(a)
	check(rounds == 2, label + ": zwei Runden gespielt (%d Schleifen, %d Aktionen)" % [guard, acts])
	check(log.private, label + ": nie eine fremde Hand in state_changed")
	check(log.leak_between == 0, label + ": keine Sicht zwischen Sichtschutz und reveal()")
	check(log.switch_ok, label + ": Sichtschutz vor jedem Menschenwechsel")
	check(log.own_seat, label + ": Sicht immer = local_seat, nie ein Bot")
	check(log.switches >= 2 and log.handovers >= log.switches, label + ": %d Wechsel, %d Sichtschutz-Meldungen" % [log.switches, log.handovers])
	t.leave()
	t.free()


# ---------- Speichern und Fortsetzen ----------

func test_save_resume() -> void:
	TableSource.clear_saved(SAVE)
	check(not TableSource.has_saved(SAVE), "Speichern: anfangs nichts gespeichert")
	var t := new_table()
	t.autosave = true
	var players := [{"name": "Lena", "kind": "human"}, {"name": "Bot A", "kind": "bot"}, {"name": "Bot B", "kind": "bot"}]
	t.setup("solo", players, RuleConfig.preset("familie"), 4242)
	t.start()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 6:
		t.pump()
		var a := MauBot.choose(t.current_view(), rng.randi(), 1)
		if not a.is_empty():
			t.act(a)
	t.pump()
	check(TableSource.has_saved(SAVE), "Speichern: Stand liegt vor")
	var data := TableSource.load_saved(SAVE)
	check(str(data.get("mode", "")) == "solo" and (data.seats as Array).size() == 3, "Speichern: Spielart und Plätze")
	var hand_before := ids_of(t.current_view().hand)
	var rev_game := JSON.stringify(t.game.to_dict())
	var t2 := new_table()
	t2.autosave = true
	var got := []
	t2.state_changed.connect(func(_e: Array, v: Dictionary) -> void: got.append(v))
	check(t2.resume(data), "Fortsetzen: resume")
	check(got.size() == 1 and ids_of(got[0].hand) == hand_before and t2.local_seat() == 0, "Fortsetzen: gleiche Hand sofort gezeigt")
	check(JSON.stringify(t2.game.to_dict()) == rev_game, "Fortsetzen: Zustand identisch")
	check(t2.game.config.round_end == "last" and t2.game.config.stacking == "same", "Fortsetzen: Regeln übernommen")
	var guard := 0
	var last := -1
	while t2.game.phase() != "round_over" and guard < 20000:
		guard += 1
		t2.pump()
		if got.size() == last:
			continue
		last = got.size()
		var a := MauBot.choose(t2.current_view(), rng.randi(), 1)
		if not a.is_empty():
			t2.act(a)
	check(t2.game.phase() == "round_over", "Fortsetzen: Runde zu Ende gespielt")
	t2.leave()
	check(not TableSource.has_saved(SAVE), "Speichern: leave löscht den Stand")
	t.autosave = false
	t.leave()
	t.free()
	t2.free()
	# Weitergeben fortsetzen: erst Sichtschutz
	var t3 := new_table()
	t3.autosave = true
	t3.setup("pass", [{"name": "A", "kind": "human"}, {"name": "B", "kind": "human"}], RuleConfig.new(), 31)
	t3.start()
	t3.pump()
	t3.reveal()
	var data3 := TableSource.load_saved(SAVE)
	var t4 := new_table()
	var ho := []
	var st := []
	t4.handover.connect(func(s: int, _n: String) -> void: ho.append(s))
	t4.state_changed.connect(func(_e: Array, v: Dictionary) -> void: st.append(v))
	check(t4.resume(data3), "Fortsetzen Weitergeben: resume")
	t4.pump()
	check(ho.size() == 1 and st.is_empty(), "Fortsetzen Weitergeben: erst Sichtschutz, keine Hand")
	t4.reveal()
	check(st.size() == 1 and int(st[0].seat) == ho[0], "Fortsetzen Weitergeben: nach reveal die richtige Hand")
	t4.autosave = false
	t3.leave()
	t3.free()
	t4.free()



# ---------- Hausregeln mit Zusatzkarten ----------

const HOUSE_EVENTS := ["swap_hands", "gamble_start", "stake", "gamble_roll", "discard_color"]


# Familie (mit Kartentausch), dazu Glücksspiel und Farbe ablegen: 124 Karten
func house_config() -> RuleConfig:
	var cfg := RuleConfig.preset("familie")
	cfg.gamble_cards = "on"
	cfg.discard_color = "on"
	return cfg


func count_events(seen: Dictionary, events: Array) -> void:
	for e in events:
		var k := str((e as Dictionary).get("e", ""))
		seen[k] = int(seen.get(k, 0)) + 1


func seen_all(seen: Dictionary) -> bool:
	for k in HOUSE_EVENTS:
		if int(seen.get(k, 0)) == 0:
			return false
	return true


func house_counts(seen: Dictionary) -> String:
	var parts: Array[String] = []
	for k in HOUSE_EVENTS:
		parts.append("%s %d" % [k, int(seen.get(k, 0))])
	return ", ".join(parts)


# Art des aktiven Gesichts einer Karte ("tausch", "gluecksspiel", "zahl" …)
func face_kind(g: MauGame, id: int) -> String:
	return str(g._kind[g.faces[g.side * g.n_cards + id]])


# Holt eine Karte der Art kind auf die Hand von seat (vom Nachziehstapel, sonst aus einer anderen Hand, die dafür die oberste
# Stapelkarte bekommt). Die Kartenzahl bleibt gleich. Liefert die id oder -1.
func give_card(g: MauGame, seat: int, kind: String) -> int:
	for id in g.hands[seat]:
		if face_kind(g, int(id)) == kind:
			return int(id)
	for i in g.draw_pile.size():
		var id := int(g.draw_pile[i])
		if face_kind(g, id) == kind:
			g.draw_pile.remove_at(i)
			(g.hands[seat] as Array).append(id)
			return id
	for s in g.hands.size():
		if s == seat:
			continue
		for x in g.hands[s]:
			var id := int(x)
			if face_kind(g, id) == kind:
				(g.hands[s] as Array).erase(id)
				(g.hands[s] as Array).append(g.draw_pile.pop_back())
				(g.hands[seat] as Array).append(id)
				return id
	return -1


# Spielt (MauBot für den gezeigten Menschen, Sichtschutz wird sofort aufgedeckt), bis min_rounds Runden fertig sind und alle
# Hausregel-Ereignisse vorkamen, höchstens max_rounds. Prüft die Kartenerhaltung nach jedem Schritt.
func play_rounds(t: LocalTable, min_rounds: int, max_rounds: int, log: Dictionary, rng_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var out := {"rounds": 0, "acts": 0, "cards": "", "guard": 0}
	var last := -1
	while int(out.guard) < 400000:
		out.guard += 1
		t.pump()
		if out.cards == "":
			out.cards = cards_ok(t.game)
		if t.pending_handover() >= 0:
			t.reveal()
			continue
		var phase := t.game.phase()
		if phase == "round_over" or phase == "game_over":
			out.rounds += 1
			if (int(out.rounds) >= min_rounds and seen_all(log.seen)) or int(out.rounds) >= max_rounds or phase == "game_over":
				break
			t.act({"a": "next_round"})
			if out.cards == "":
				out.cards = cards_ok(t.game)
			last = -1
			continue
		if int(log.states) == last:
			continue
		last = int(log.states)
		var a := MauBot.choose(t.current_view(), rng.randi(), 1)
		if not a.is_empty():
			out.acts += 1
			t.act(a)
	return out


# Übungsspiel mit allen Hausregeln: ganze Runden, bis Kartentausch, Glücksspiel und Farbe ablegen vorkamen
func test_house_solo() -> void:
	var cfg := house_config()
	check(cfg.card_count() == 124 and cfg.swap_cards == "on" and cfg.round_end == "last" and cfg.preset_name() == "",
		"Hausregeln: Familie + Glücksspiel + Farbe ablegen = 124 Karten, eigene Regeln")
	var t := new_table()
	var players := [{"name": "Lena", "kind": "human"}, {"name": "Bot A", "kind": "bot"}, {"name": "Bot B", "kind": "bot"},
		{"name": "Bot C", "kind": "bot"}]
	check(t.setup("solo", players, cfg, 9101), "Hausregeln solo: setup")
	var log := {"states": 0, "private": true, "seen": {}}
	t.state_changed.connect(func(ev: Array, v: Dictionary) -> void:
		log.states += 1
		count_events(log.seen, ev)
		if not check_private(t, ev, v, "Hausregeln solo"):
			log.private = false)
	t.start()
	check(t.game.n_cards == 124 and cards_ok(t.game) == "", "Hausregeln solo: 124 Karten ausgeteilt (%s)" % cards_ok(t.game))
	var res := play_rounds(t, 2, 16, log, 41)
	check(int(res.rounds) >= 2, "Hausregeln solo: ganze Runden gespielt (%d Runden, %d Aktionen des Menschen)" % [res.rounds, res.acts])
	check(res.cards == "", "Hausregeln solo: Kartenerhaltung nach jedem Schritt (%s)" % res.cards)
	check(seen_all(log.seen), "Hausregeln solo: Kartentausch, Glücksspiel und Farbe ablegen kamen vor (%s)" % house_counts(log.seen))
	check(log.private, "Hausregeln solo: nie fremde Hände, Einsätze oder die Trefferquote")
	t.leave()
	t.free()


# Weitergeben mit allen Hausregeln: Sichtschutz vor jedem Menschenwechsel, auch nach Kartentausch und Glücksspiel
func test_house_pass(humans: int, bots: int, rng_seed: int) -> void:
	var cfg := house_config()
	var t := new_table()
	var players: Array = []
	for i in humans + bots:
		var bot := i % 2 == 1 and players.filter(func(p): return p.kind == "bot").size() < bots
		if players.filter(func(p): return p.kind == "human").size() >= humans:
			bot = true
		players.append({"name": ("Bot %d" % i) if bot else ("Mensch %d" % i), "kind": "bot" if bot else "human"})
	var label := "Hausregeln Weitergeben %d+%d" % [humans, bots]
	check(t.setup("pass", players, cfg, rng_seed), label + ": setup")
	var log := {"states": 0, "private": true, "seen": {}, "handovers": 0, "awaiting": -1, "shown": -1, "switch_ok": true,
		"leak_between": 0, "own_seat": true, "gamble_handover": 0, "after_swap": false, "after_gamble": false,
		"swap_handover": 0, "gamble_then_handover": 0}
	t.handover.connect(func(s: int, n: String) -> void:
		log.handovers += 1
		log.awaiting = s
		if n != str(t.seats[s].name) or t.is_bot(s):
			log.switch_ok = false
		# Mitten im Glücksspiel eines anderen Menschen darf kein Sichtschutz kommen (der Spieler setzt und drückt selbst weiter)
		if t.game.phase() == "gamble" and int(t.game.gamble.get("seat", -1)) != s:
			log.gamble_handover += 1
		if log.after_swap:
			log.swap_handover += 1
		if log.after_gamble:
			log.gamble_then_handover += 1
		log.after_swap = false
		log.after_gamble = false)
	t.state_changed.connect(func(ev: Array, v: Dictionary) -> void:
		log.states += 1
		count_events(log.seen, ev)
		for e in ev:
			var k := str(e.get("e", ""))
			if k == "swap_hands":
				log.after_swap = true
			elif k == "stake_back" or k == "stake_discard":
				log.after_gamble = true
		var s := int(v.seat)
		if t.pending_handover() >= 0:
			log.leak_between += 1
		if s != log.shown and log.awaiting != s:
			log.switch_ok = false
		log.shown = s
		log.awaiting = -1
		if s != t.local_seat() or t.is_bot(s):
			log.own_seat = false
		if not check_private(t, ev, v, label):
			log.private = false)
	t.start()
	t.pump()
	check(t.pending_handover() >= 0 and log.states == 0, label + ": Sichtschutz vor der ersten Hand")
	var res := play_rounds(t, 1, 12, log, rng_seed)
	check(int(res.rounds) >= 1, label + ": ganze Runden gespielt (%d Runden, %d Aktionen)" % [res.rounds, res.acts])
	check(res.cards == "", label + ": Kartenerhaltung nach jedem Schritt (%s)" % res.cards)
	check(seen_all(log.seen), label + ": Kartentausch, Glücksspiel und Farbe ablegen kamen vor (%s)" % house_counts(log.seen))
	check(log.private, label + ": nie fremde Hände, Einsätze oder die Trefferquote")
	check(log.leak_between == 0, label + ": keine Sicht zwischen Sichtschutz und reveal()")
	check(log.switch_ok, label + ": Sichtschutz vor jedem Menschenwechsel")
	check(log.own_seat, label + ": Sicht immer = local_seat, nie ein Bot")
	check(log.gamble_handover == 0, label + ": kein Sichtschutz mitten im Glücksspiel")
	check(int(log.swap_handover) > 0 and int(log.gamble_then_handover) > 0,
		label + ": Sichtschutz nach Kartentausch (%d) und nach Glücksspiel (%d) geprüft" % [log.swap_handover, log.gamble_then_handover])
	t.leave()
	t.free()


# Erzwungener Ablauf mit zwei Menschen: Kartentausch, dann ein Glücksspiel mit festen Drucken (0, 0, 3)
func test_house_pass_forced() -> void:
	var label := "Weitergeben erzwungen"
	var t := new_table()
	check(t.setup("pass", [{"name": "Anna", "kind": "human"}, {"name": "Ben", "kind": "human"}], house_config(), 77), label + ": setup")
	var log := {"views": 0, "handovers": [], "between": 0, "private": true}
	t.handover.connect(func(s: int, n: String) -> void: log.handovers.append([s, n]))
	t.state_changed.connect(func(ev: Array, v: Dictionary) -> void:
		log.views += 1
		if t.pending_handover() >= 0:
			log.between += 1
		if not check_private(t, ev, v, label):
			log.private = false)
	# Das Signal des Sichtschutzes trägt nur Platz und Name, nie Karten
	var args_ok := false
	for sig in t.get_signal_list():
		if str(sig.name) == "handover":
			args_ok = true
			for a in sig.args:
				if not int(a.type) in [TYPE_INT, TYPE_STRING]:
					args_ok = false
	check(args_ok, label + ": handover(Platz, Name) ohne Karten")
	t.start()
	t.pump()
	var g := t.game
	var first := t.pending_handover()
	check(first >= 0 and first == g.current_seat() and log.views == 0, label + ": Sichtschutz vor dem ersten Zug")
	if first < 0:
		t.leave()
		t.free()
		return
	var other := 1 - first
	# Kartentausch auf die Hand, Farbe passend (noch hinter dem Sichtschutz)
	var swap_id := give_card(g, first, MauGame.SWAP)
	if swap_id >= 0:
		g.color = str(g._color[g.faces[g.side * g.n_cards + swap_id]])
		g.wished = false
	check(swap_id >= 0 and cards_ok(g) == "", label + ": Kartentausch auf der Hand (%s)" % cards_ok(g))
	t.reveal()
	var v := t.current_view()
	check(int(v.seat) == first and (v.hints.playable as Array).has(swap_id), label + ": Kartentausch spielbar")
	var other_old := sorted_ints(g.hands[other])
	var mine_after := sorted_ints(g.hands[first])
	mine_after.erase(swap_id)
	var ho := (log.handovers as Array).size()
	t.act({"a": "play", "card": swap_id})
	check(ids_of(t.current_view().hand) == other_old and sorted_ints(g.hands[other]) == mine_after,
		label + ": Hände getauscht, eigene Sicht zeigt die neue eigene Hand")
	for i in 3:
		t.pump()
	check((log.handovers as Array).size() == ho + 1 and int(log.handovers[-1][0]) == other and t.local_seat() == -1,
		label + ": nach dem Kartentausch erst der Sichtschutz für %d (%s)" % [other, str(log.handovers)])
	check(log.between == 0 and cards_ok(g) == "", label + ": keine Sicht hinter dem Sichtschutz, Karten vollständig")
	# Glücksspiel für den anderen Menschen: zweimal 0, dann Treffer 3
	var gid := give_card(g, other, MauGame.GAMBLE)
	g.force_rolls([0, 0, 3])
	check(gid >= 0 and cards_ok(g) == "", label + ": Glücksspiel auf der Hand")
	t.reveal()
	v = t.current_view()
	check(int(v.seat) == other and (v.hints.playable as Array).has(gid) and (v.gamble as Dictionary).is_empty(),
		label + ": Glücksspiel spielbar, noch kein Einsatz")
	ho = (log.handovers as Array).size()
	var hand_before := (g.hands[other] as Array).size()
	t.act({"a": "play", "card": gid, "color": str((v.colors as Array)[0])})
	check(g.phase() == "gamble" and int(g.gamble.seat) == other, label + ": Glücksspiel läuft")
	var presses := 0
	var stakes := 0
	var steady := true
	var cards := ""
	for step in 30:
		if g.phase() != "gamble":
			break
		t.pump()
		if t.pending_handover() >= 0 or t.local_seat() != other:
			steady = false
		v = t.current_view()
		var gv: Dictionary = v.get("gamble", {})
		if int(gv.get("stake", -1)) != stakes:
			steady = false
		var h: Dictionary = v.hints
		if not (h.get("can_stake", []) as Array).is_empty():
			t.act({"a": "stake", "card": int(h.can_stake[0])})
			stakes += 1
		elif bool(h.get("can_press", false)):
			t.act({"a": "press"})
			presses += 1
		if cards == "":
			cards = cards_ok(g)
	check(presses == 3 and stakes == 3 and g.phase() != "gamble" and g.gamble.is_empty(),
		label + ": drei Einsätze, drei Drucke, Treffer beendet das Glücksspiel (%d/%d, %s)" % [stakes, presses, g.phase()])
	check(steady, label + ": während des Glücksspiels kein Sichtschutz, nur die eigene Sicht")
	check(cards == "" and cards_ok(g) == "", label + ": Kartenerhaltung mit Einsatz (%s)" % cards)
	check((g.hands[other] as Array).size() == hand_before - 1 + 3,
		label + ": 3 gezogen, Einsatz zurück (%d Karten)" % (g.hands[other] as Array).size())
	for i in 3:
		t.pump()
	check((log.handovers as Array).size() == ho + 1 and int(log.handovers[-1][0]) == first and log.between == 0,
		label + ": nach dem Glücksspiel Sichtschutz für %d, keine Sicht dahinter" % first)
	t.reveal()
	check(int(t.current_view().seat) == first and log.private, label + ": danach die richtige Hand, alles privat")
	t.leave()
	t.free()
