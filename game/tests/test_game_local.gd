extends SceneTree

# Modul G, LocalTable: Übungsspiel (1 Mensch + 3 Bots, der „Mensch“ entscheidet per MauBot) bis Rundenende und weiter in Runde 2,
# Denkpausen der Bots, Weitergeben mit 3 Menschen (+ Bot): Sichtschutz vor jedem Menschenwechsel, nie eine fremde Hand in
# state_changed, keine fremden gezogenen Gesichter in den Ereignissen; Speichern und Fortsetzen.

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


func total_cards(g: MauGame) -> int:
	var n := g.draw_pile.size() + g.discard.size()
	for h in g.hands:
		n += (h as Array).size()
	return n


# Prüft eine ausgegebene Sicht samt Ereignissen gegen den echten Zustand: nur die eigene Hand, keine fremden Gesichter.
func check_private(t: GameTable, events: Array, view: Dictionary, label: String) -> bool:
	var seat := int(view.get("seat", -1))
	var ok := seat >= 0 and ids_of(view.hand) == sorted_ints(t.game.hands[seat])
	for p in view.players:
		if (p as Dictionary).has("hand") or (int(p.seat) == seat and not (p.backs as Array).is_empty()):
			ok = false
	for e in events:
		var d: Dictionary = e
		if str(d.get("e", "")) == "draw" and int(d.seat) != seat and (d.has("faces") or d.has("cards")):
			ok = false
		if str(d.get("e", "")) == "challenge" and int(d.seat) != seat and d.has("hand"):
			ok = false
	var text := JSON.stringify(view) + JSON.stringify(events)
	if text.contains("rng_state") or text.contains("\"snap\"") or text.contains("\"seed\""):
		ok = false
	if not ok:
		print("  Sicht/Ereignisse (%s) für Platz %d nicht privat" % [label, seat])
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
