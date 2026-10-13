extends SceneTree

# Mau-Mau Flip (Beta 1.6.1, Gastgeber-Übergabe): Spielstand-Schnappschuss (docs/module/uebergabe.md Abschnitte 1 und 7), synchron
# gepumpt im selben Prozess (WLAN 24966–24969, kein Vermittler).
#  A  Partie mit 10 Plätzen (Gastgeber + 9 Computergegner, „Familie“ mit allen Zusatzkarten): nach JEDER Änderung Schnappschuss →
#     gzip/base64 → zurück; MauGame.to_dict und view_for aller Plätze gleich. Zwischenzustände (Farbwahl, offene Strafe,
#     Glücksspiel samt geheimer Quote, Ablege-Auswahl samt Undo, Kartentausch, Rundenende) müssen vorkommen; ein offenes
#     Mau-Fenster (Computergegner vergessen selten) wird in B notfalls aus einem anderen Stand gebaut.
#     Größe der Sicherung bei 10 Plätzen < 16 KB.
#  B  Je Zwischenzustand ein echtes HostTable.resume() (eigener Zweig): gleicher Regelstand, gen/epoch bleiben, seq zählt weiter,
#     Vertretung und herausgenommene Namen kommen mit, keine Einschwingzeit ohne Sicherungsempfänger.
#  C  Tokens A→B→C: Gastgeber A mit App-Gästen B, C und einem Bot; Übernahme durch B (resume mit my_seat), dann durch C. Alle Tokens
#     bleiben an ihren Plätzen (keins doppelt, auch der Gastgeber-Platz hat eins), gen steigt genau bei Platzwechsel, parent stimmt,
#     die Sichten sind bis auf host/connected gleich. A und B kommen mit ihren Tokens zurück und landen auf ihren eigenen Plätzen.

const P1 := 24966
const P2 := 24967
const P3 := 24968
const P4 := 24969

var failures := 0
var checks := 0
var rng := RandomNumberGenerator.new()
var nodes: Array = []
var clients: Array = []

# Teil A
var changes := 0
var mismatches: Array = []
var max_z := 0
var covered := {}
var firsts := {}


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)


func _initialize() -> void:
	rng.seed = 1611
	var t0 := Time.get_ticks_msec()
	_roundtrips()
	_resume_states()
	_tokens_abc()
	print("  Dauer %d ms" % (Time.get_ticks_msec() - t0))
	for c in clients:
		if is_instance_valid(c):
			c.leave()
			c.free()
	for n in nodes:
		if is_instance_valid(n):
			n.autosave = false
			n.leave()
			n.free()
	print("RESULT: %d ok" % checks if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)


func new_host(port: int) -> HostTable:
	var h := HostTable.new()
	h.auto_process = false
	h.speed = 0.0
	h.use_discovery = false
	h.autosave = false
	h.save_path = "user://test_handover_snapshot.json"
	nodes.append(h)
	return h


func drop_host(h: HostTable) -> void:
	nodes.erase(h)
	h.free()


# ---------- A: Schnappschuss nach jeder Änderung ----------

func _roundtrips() -> void:
	var h := new_host(P1)
	h.backup_enabled = false
	check(h.open("Gastgeber", P1, P1) == OK, "A: Gastgeber im WLAN")
	for i in 9:
		h.add_bot()
	var cfg := RuleConfig.preset("familie")
	check(cfg.swap_cards == "on" and cfg.gamble_cards == "on" and cfg.discard_color == "on", "A: Familie mit allen Zusatzkarten")
	h.set_rules(cfg)
	h.state_changed.connect(func(ev: Array, _v: Dictionary) -> void: _after_change(h, ev))
	check(h.start(4711), "A: Start mit 10 Plätzen")
	check(h.host_token().length() == NetProtocol.TOKEN_LENGTH, "A: Gastgeber-Platz hat ein Token")
	check(h.gen == 1 and h.epoch.length() == 8 and h.gid.length() == 16 and h.parent == NetProtocol.BK_NONE, "A: gid, gen 1, epoch, parent leer")
	var rounds := 0
	var t_end := Time.get_ticks_msec() + 40000
	while Time.get_ticks_msec() < t_end and changes < 3000 and not _all_covered():
		h.pump()
		var g := h.game
		if g.phase() == "game_over":
			h.back_to_lobby()
			h.start(rng.randi())
			continue
		if g.phase() == "round_over":
			rounds += 1
			h.act({"a": "next_round"})
			continue
		var v := h.current_view()
		var a := MauBot.choose(v, rng.randi(), 1)
		if not a.is_empty():
			h.act(a)
	print("  A: %d Änderungen, %d Runden, größte Sicherung %d Byte, abgedeckt %s" % [changes, rounds, max_z, str(covered.keys())])
	check(changes > 50, "A: genug Änderungen geprüft (%d)" % changes)
	check(mismatches.is_empty(), "A: Regelstand und Sichten nach Schnappschuss gleich (%s)" % str(mismatches.slice(0, 3)))
	check(max_z > 0 and max_z < 16 * 1024, "A: Sicherung bei 10 Plätzen kleiner als 16 KB (%d Byte)" % max_z)
	for k in ["color", "pending", "gamble", "discard_pick", "undo", "swap", "round_over"]:
		check(covered.has(k), "A: Zwischenzustand „%s“ kam vor" % k)
	h.leave()
	drop_host(h)


func _all_covered() -> bool:
	for k in ["color", "pending", "gamble", "discard_pick", "undo", "swap", "round_over"]:
		if not covered.has(k):
			return false
	return true


func _after_change(h: HostTable, events: Array) -> void:
	changes += 1
	var g := h.game
	var snap := h._snapshot()
	var z := MatchSnapshot.pack(snap)
	max_z = maxi(max_z, z.length())
	var back := MatchSnapshot.unpack(z)
	if back.is_empty():
		mismatches.append("unpack leer (%d)" % changes)
		return
	if MatchSnapshot.mark(back) != h.mark() or int(back.seq) != h.seq:
		mismatches.append("Marke %s statt %s" % [str(MatchSnapshot.mark(back)), str(h.mark())])
	var g2 := MauGame.from_dict(back.game)
	if JSON.stringify(g.to_dict()) != JSON.stringify(g2.to_dict()):
		mismatches.append("to_dict in Phase %s" % g.phase())
	for s in g.seat_count():
		if JSON.stringify(g.view_for(s)) != JSON.stringify(g2.view_for(s)):
			mismatches.append("view_for(%d) in Phase %s" % [s, g.phase()])
			break
	var keys: Array = []
	if g.phase() in ["color", "challenge", "gamble", "discard_pick", "round_over"]:
		keys.append(g.phase())
	if not g.pending.is_empty():
		keys.append("pending")
	if g.phase() == "gamble" and int(g.gamble.get("q", 0)) > 0:
		keys.append("gamble")
	if g.phase() == "discard_pick" and g.dpick.get("undo") is Dictionary and not (g.dpick.undo as Dictionary).is_empty():
		keys.append("undo")
	if g.mau_open >= 0 and not bool(g.mau_said[g.mau_open]):
		keys.append("mau_open")
	for e in events:
		if str((e as Dictionary).get("e", "")) == "swap_hands":
			keys.append("swap")
	for k in keys:
		covered[k] = true
		if not firsts.has(k):
			firsts[k] = snap.duplicate(true)


# ---------- B: echtes resume() je Zwischenzustand ----------

func _resume_states() -> void:
	if firsts.is_empty():
		check(false, "B: keine Zwischenzustände aus A")
		return
	# Mau-Fenster: kam es mit Computergegnern nicht vor, aus einem anderen Stand bauen (offenes Fenster für Platz 3)
	if not firsts.has("mau_open"):
		var d: Dictionary = (firsts.get("pending", firsts.values()[0]) as Dictionary).duplicate(true)
		var gd: Dictionary = d.game
		gd["mau_open"] = 3
		var ms: Array = gd.mau_said
		ms[3] = false
		firsts["mau_open"] = d
	# Vertretung und herausgenommene Namen (sonst leer, weil nur Computergegner am Tisch sitzen)
	var extra: Dictionary = (firsts.get("color", firsts.values()[0]) as Dictionary).duplicate(true)
	extra.gone_names = ["Mogli"]
	firsts["extra"] = extra
	for k in firsts:
		var snap: Dictionary = firsts[k]
		var t := new_host(P2)
		var err := t.resume(snap, -1, P2, P2)
		check(err == OK, "B %s: resume" % k)
		if err != OK:
			drop_host(t)
			continue
		var ref := MauGame.from_dict(snap.game)
		ref.connected = t.game.connected.duplicate()
		check(JSON.stringify(t.game.to_dict()) == JSON.stringify(ref.to_dict()), "B %s: Regelstand gleich (Phase %s)" % [k, ref.phase()])
		var same := true
		for s in ref.seat_count():
			if JSON.stringify(t.game.view_for(s)) != JSON.stringify(ref.view_for(s)):
				same = false
		check(same, "B %s: view_for aller Plätze gleich" % k)
		check(t.gid == str(snap.gid) and t.gen == int(snap.gen) and t.epoch == str(snap.epoch) and t.seq == int(snap.seq) + 1,
			"B %s: eigener Zweig – gid/gen/epoch bleiben, seq zählt weiter (%d → %d)" % [k, int(snap.seq), t.seq])
		check(t.parent == (snap.parent as Array), "B %s: parent bleibt" % k)
		check(not t.is_settling() and not t.is_frozen(), "B %s: ohne Sicherungsempfänger keine Einschwingzeit" % k)
		check(t.host_token() == MatchSnapshot.seat_token(snap, int(snap.host_seat)), "B %s: Token des Gastgeber-Platzes bleibt" % k)
		if k == "extra":
			check(t._gone_names.has("Mogli"), "B: herausgenommene Namen kommen mit")
		if k == "mau_open":
			check(t.game.mau_open >= 0 and not bool(t.game.mau_said[t.game.mau_open]), "B: offenes Mau-Fenster kommt mit")
		if k == "round_over":
			check(t.game.phase() == "round_over" and bool(t.view_of(t.host_seat).hints.get("can_next_round", false)),
				"B: Rundenende – der Gastgeber darf die nächste Runde starten")
		if k == "gamble":
			check(int(t.game.gamble.get("q", 0)) == int((snap.game as Dictionary).gamble.q), "B: geheime Glücksspiel-Quote kommt mit")
		t.leave()
		drop_host(t)


# ---------- C: Tokens A→B→C ----------

func _tokens_abc() -> void:
	var a := new_host(P2)
	check(a.open("Anna", P2, P2) == OK, "C: Gastgeberin Anna")
	var ben := new_client("Ben", P2)
	var cleo := new_client("Cleo", P2)
	check(wait_until([a], func(): return a.session.players.size() == 3 and ben.my_id > 0 and cleo.my_id > 0), "C: zwei App-Gäste")
	a.add_bot("Minka")
	a.set_rules(RuleConfig.preset("offiziell"))
	check(a.start(77), "C: Start")
	check(wait_until([a], func(): return ben.view_rev > 0 and cleo.view_rev > 0), "C: Gäste bekommen den Stand")
	_play([a], a, 12)
	var seat_a := a.host_seat
	var seat_b := a.session.seat_of(ben.my_id)
	var seat_c := a.session.seat_of(cleo.my_id)
	var toks := _tokens(a.seats)
	check(toks.size() == 4 and str(toks[seat_a]) != "" and str(toks[seat_b]) == ben.token and str(toks[seat_c]) == cleo.token,
		"C: Tokens an den Plätzen (Gastgeber %s…)" % str(toks[seat_a]).left(6))
	check(_unique(toks), "C: kein Token doppelt")
	# Übernahme durch Ben: A fällt aus (ohne „Tisch verlassen“)
	var snap_a := a._snapshot()
	var views_a := _views(a.game)
	drop_host(a)
	var b := new_host(P3)
	check(b.resume(snap_a, seat_b, P3, P3) == OK, "C: Ben übernimmt (resume mit eigenem Platz)")
	check(b.host_seat == seat_b and b.local_seat() == seat_b and bool(b.seats[seat_b].host) and not bool(b.seats[seat_a].host),
		"C: Gastgeber-Platz gewechselt, Anna ist Gast")
	check(b.game.host_seat() == seat_b, "C: Regelwerk kennt den neuen Gastgeber-Platz")
	check(b.gen == 2 and b.epoch != str(snap_a.epoch) and b.gid == str(snap_a.gid), "C: gen 2, neue epoch, gleiche gid")
	check(b.parent == [int(snap_a.gen), str(snap_a.epoch), int(snap_a.seq)], "C: parent = Stand von Anna %s" % str(b.parent))
	check(_tokens(b.seats) == toks, "C: alle Tokens unverändert an ihren Plätzen")
	check(_views_equal(views_a, b.game), "C: Sichten aller Plätze gleich (bis auf host/connected)")
	check(str(b.seats[seat_a].net) == "app" and not bool(b.game.connected[seat_a]), "C: Annas Platz ist ein getrennter App-Gast")
	# Anna (mit dem Token ihres Platzes) und Cleo kommen zurück
	var anna := new_client("Anna", P3, str(toks[seat_a]))
	cleo.leave()
	var cleo2 := new_client("Cleo", P3, str(toks[seat_c]))
	ben.leave()
	check(wait_until([b], func(): return anna.view_rev > 0 and cleo2.view_rev > 0), "C: Anna und Cleo zurück (bei Ben)")
	check(anna.local_seat() == seat_a and cleo2.local_seat() == seat_c, "C: auf ihren eigenen Plätzen (%d/%d)" % [anna.local_seat(), cleo2.local_seat()])
	check(bool(b.game.connected[seat_a]) and bool(b.game.connected[seat_c]), "C: Ben sieht beide verbunden")
	_play([b], b, 8)
	# Vertretung im Stand: Anna geht, der Computer spielt für sie
	anna.leave()
	check(wait_until([b], func(): return not bool(b.game.connected[seat_a])), "C: Anna trennt bei Ben")
	b.substitute_bot(seat_a)
	check(b.is_substituted(seat_a), "C: Computer spielt für Anna")
	# Übernahme durch Cleo
	var snap_b := b._snapshot()
	var views_b := _views(b.game)
	drop_host(b)
	var c := new_host(P4)
	check(c.resume(snap_b, seat_c, P4, P4) == OK, "C: Cleo übernimmt")
	check(c.gen == 3 and c.parent == [2, str(snap_b.epoch), int(snap_b.seq)] and c.gid == str(snap_a.gid), "C: gen 3, parent = Bens Stand")
	check(_tokens(c.seats) == toks and _unique(_tokens(c.seats)), "C: Tokens unverändert, keins doppelt")
	check(_views_equal(views_b, c.game), "C: Sichten gleich nach der zweiten Übernahme")
	check(c.is_substituted(seat_a) and not c.is_substituted(seat_c), "C: Vertretung für Anna kommt mit")
	var anna2 := new_client("Anna", P4, str(toks[seat_a]))
	var ben2 := new_client("Ben", P4, str(toks[seat_b]))
	check(wait_until([c], func(): return anna2.view_rev > 0 and ben2.view_rev > 0), "C: Anna und Ben zurück (bei Cleo)")
	check(anna2.local_seat() == seat_a and ben2.local_seat() == seat_b, "C: Anna und Ben auf ihren eigenen Plätzen")
	check(c.session.players.size() == 4, "C: niemand doppelt in der Sitzung")
	# Eigener Zweig nach der Übernahme: gen bleibt
	var snap_c := c._snapshot()
	drop_host(c)
	var c2 := new_host(P4)
	check(c2.resume(snap_c, seat_c, P4, P4) == OK and c2.gen == 3 and c2.epoch == str(snap_c.epoch), "C: Cleo setzt ihren Zweig fort – gen bleibt 3")
	drop_host(c2)


func _tokens(seats: Array) -> Array:
	return seats.map(func(p): return str(p.get("token", "")) if str(p.get("kind", "")) != "bot" else "")


func _unique(toks: Array) -> bool:
	var seen := {}
	for t in toks:
		if str(t) == "":
			continue
		if seen.has(t):
			return false
		seen[t] = true
	return true


func _views(g: MauGame) -> Array:
	var out: Array = []
	for s in g.seat_count():
		out.append(_norm(g.view_for(s)))
	return out


func _views_equal(before: Array, g: MauGame) -> bool:
	for s in g.seat_count():
		if JSON.stringify(before[s]) != JSON.stringify(_norm(g.view_for(s))):
			print("  Sicht %d: %s\n  statt %s" % [s, JSON.stringify(_norm(g.view_for(s))).left(300), JSON.stringify(before[s]).left(300)])
			return false
	return true


# host/connected und davon abhängige Hinweise ausblenden
func _norm(v: Dictionary) -> Dictionary:
	var d := v.duplicate(true)
	for p in d.get("players", []):
		(p as Dictionary).erase("connected")
	(d.hints as Dictionary).erase("can_next_round")
	return d


func _play(hosts: Array, h: HostTable, moves: int) -> void:
	var done := 0
	var end := Time.get_ticks_msec() + 5000
	while done < moves and Time.get_ticks_msec() < end:
		pump(hosts)
		if h.game.phase() == "round_over" or h.game.phase() == "game_over":
			break
		for t in [h] + clients:
			if not is_instance_valid(t) or (t is ClientTable and (t.client == null or t.connection_state() != "open")):
				continue
			var v: Dictionary = t.current_view()
			if v.is_empty():
				continue
			var a := MauBot.choose(v, rng.randi(), 1)
			if not a.is_empty() and str(a.get("a", "")) != "next_round":
				var before := h.rev
				t.act(a)
				pump(hosts)
				if h.rev != before:
					done += 1


func new_client(player_name: String, port: int, token := "") -> ClientTable:
	var c := ClientTable.new()
	c.auto_process = false
	c.reuse_token = false
	c.persist_tokens = false
	c.retry_ms = [100, 200, 400]
	clients.append(c)
	c.join("127.0.0.1", port, player_name, token)
	return c


func pump(hosts: Array) -> void:
	for h in hosts:
		if is_instance_valid(h):
			h.pump()
	for c in clients:
		if is_instance_valid(c) and c.client != null:
			c.pump()


func wait_until(hosts: Array, cond: Callable, ms := 4000) -> bool:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		pump(hosts)
		if cond.call():
			return true
		OS.delay_msec(2)
	return cond.call()
