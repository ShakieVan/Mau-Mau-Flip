extends "res://tests/handover_kit.gd"

# Mau-Mau Flip (Beta 1.6.1, Gastgeber-Übergabe): geplante Übergabe online (docs/module/uebergabe.md 4.1, 4.5, 5, 7) – Gastgeberin
# Hanna, App-Gast Ben (mit Sicherung), App-Gast Cleo ohne hello.bk, Browser-Gast Wally (kind "web", wie Lite) und Computer Minka über
# den Vermittler-Nachbau (TCP 24953), synchron gepumpt.
#  1  Einige Züge, dann „Gastgeber übergeben“ an Ben: Hanna friert ein (keine Sicht mehr), Ben führt (gen + 1), Hanna wird Gast auf
#     ihrem Platz, Cleo und Wally folgen per 4012 mit Token auf ihre Plätze, Meldungen „Gastgeber wechselt zu …“ und „… ist jetzt
#     Gastgeber.“, kein bye. Lecktest: bk/alive/handover nie an Wally (web) und nie an Cleo (App ohne hello.bk); Reihenfolge je Gast:
#     bk vor der zugehörigen Sicht (Ben vorher, Hanna nachher). Die Partie läuft bis zum Rundenende weiter.
#  2  Frist within_ms: Ben bekommt keinen room-Rahmen → bricht ab, ist wieder Gast (Datei wie vorher, gen der Übernahme gilt nicht);
#     Hanna taut nach check_now auf, gen unverändert, die Partie läuft weiter.

const RELAY_PORT := 24953
const H_PORT := 24954
const B_PORT := 24955
const C_PORT := 24956


func _initialize() -> void:
	rng.seed = 1612
	start_relay(RELAY_PORT)
	var t0 := Time.get_ticks_msec()
	_planned()
	_clear_all()
	_within_abort()
	print("  Dauer %d ms" % (Time.get_ticks_msec() - t0))
	finish()


func _has_notice(list: Array, template: String) -> bool:
	for m in list:
		if str(m.get("t", "")) == "notice" and JSON.stringify(m.get("lt", [])).contains(template.replace("%s", "").strip_edges().left(14)):
			return true
	return false


func _leaks(list: Array) -> int:
	return count(list, "bk") + count(list, "alive") + count(list, "handover")


# ---------- 1 ----------

func _planned() -> void:
	var h := host_dev("Hanna", H_PORT)
	var link := str(h.ht().session.online_info().link)
	var code := str(h.ht().session.online_info().room)
	var b := guest_dev("Ben", link, B_PORT)
	var c := guest_dev("Cleo", link, C_PORT, false)
	var w := web_guest("Wally", relay.base_url(), code)
	check(wait_until(func(): return b.ct().my_id > 0 and c.ct().my_id > 0 and (w.c as NetClient).my_id > 0), "1: Gäste angemeldet")
	var ht := h.ht()
	ht.add_bot("Minka")
	ht.set_rules(RuleConfig.preset("offiziell"))
	check(ht.start(4242), "1: Start")
	check(wait_until(func(): return b.ct().view_rev > 0 and c.ct().view_rev > 0 and not (w.view as Dictionary).is_empty()), "1: alle haben den Stand")
	play(8)
	check(ht.session.backup_ids() == [b.ct().my_id], "1: nur Ben bekommt Sicherungen")
	check(count(b.inbox, "bk") > 0 and count(c.inbox, "bk") == 0, "1: bk an Ben, nicht an Cleo")
	var seats := {"Hanna": ht.host_seat, "Ben": b.ct().local_seat(), "Cleo": c.ct().local_seat(), "Wally": int((w.view as Dictionary).seat)}
	check(ht.handover_block(seats.Ben).is_empty(), "1: Übergabe an Ben möglich (%s)" % str(ht.handover_block(seats.Ben)))
	check(ht.handover_block(seats.Cleo) == ["Nur Mitspieler mit der App können Gastgeber werden."], "1: Cleo (ohne Sicherung) nicht wählbar")
	check(ht.handover_block(seats.Wally) == ["Nur Mitspieler mit der App können Gastgeber werden."], "1: Browser-Gast nicht wählbar")
	check(wait_until(func(): return b.ct().backup_current()), "1: Bens Sicherung aktuell")
	var gen0 := ht.gen
	var views_after := [0]
	ht.state_changed.connect(func(_e, _v) -> void: views_after[0] += 1)
	var b_before := b.inbox.size()
	if OS.get_environment("DEBUG_UEBERGABE") != "":
		relay.ws_dropped.connect(func(conn: int, why: String, _s: int) -> void:
			var se: Dictionary = relay.core.socks.get(conn, {})
			print("  drop %d %s %s c=%s t=%d" % [conn, why, str(se.get("role", "?")), str(se.get("c", "?")), Time.get_ticks_msec()]))
	check(ht.handover_to(seats.Ben), "1: handover_to(Ben)")
	check(ht.is_frozen(), "1: Hanna eingefroren")
	check(wait_until(func(): return b.ht() != null, 6000), "1: Ben führt (Zustand %s)" % b.sw.state)
	var bt := b.ht()
	check(views_after[0] == 0, "1: eingefroren – kein Stand mehr bei Hanna (auch nicht beim Schließen von Bens Gast-Socket)")
	check(bt.gen == gen0 + 1 and bt.host_seat == seats.Ben, "1: Ben auf seinem Platz, gen + 1")
	check(str(b.swaps[0][1]) == I18n.t("Du bist jetzt Gastgeber. Bitte lass die App offen."), "1: Hinweis an Ben")
	var ho := b.inbox.slice(b_before).filter(func(m): return str(m.get("t", "")) == "handover")
	check(ho.size() == 1 and (ho[0] as Dictionary).has("z"), "1: Ben bekam genau ein handover mit Stand")
	check(wait_until(func(): return h.ct() != null and h.ct().connection_state() == "open", 6000), "1: Hanna spielt als Gast weiter (%s)" % h.sw.state)
	check(str(h.swaps[0][1]) == I18n.t("Du spielst jetzt als Gast weiter. Gastgeber ist %s.") % "Ben", "1: Hinweis „Gastgeber ist Ben“")
	var follow := func() -> bool:
		return c.ct().connection_state() == "open" and c.ct().host_name() == "Ben" and (w.c as NetClient).state == "open" \
			and (w.c as NetClient).host_name == "Ben"
	check(wait_until(follow, 6000), "1: Cleo und Wally folgen (4012 + Token)")
	check(wait_until(func(): return h.ct().local_seat() == seats.Hanna and c.ct().local_seat() == seats.Cleo \
		and int((w.view as Dictionary).get("seat", -1)) == seats.Wally, 4000), "1: alle auf ihren Plätzen")
	check(wait_until(func(): return not bt.is_settling(), 3000), "1: Einschwingzeit vorbei")
	check(_has_notice(c.inbox, "Gastgeber wechselt zu %s …") and _has_notice(w.inbox, "Gastgeber wechselt zu %s …"), "1: Meldung „Gastgeber wechselt zu Ben …“")
	check(wait_until(func(): return _has_notice(c.inbox, "%s ist jetzt Gastgeber.") and _has_notice(w.inbox, "%s ist jetzt Gastgeber.")),
		"1: Meldung „Ben ist jetzt Gastgeber.“")
	var rev := bt.rev
	var played := play(0, true)
	check(int(relay.stats().get("rate_dropped", 0)) == 0, "1: Vermittler verwarf keine Rahmen (Rundumschlag im Budget)")
	if int(relay.stats().get("rate_dropped", 0)) > 0:
		print("  Vermittler: ", relay.stats(), "\n  Ben: ", bt.session.relay.stats())
	check(bt.rev > rev and played > 0, "1: Partie läuft weiter (%d Züge)" % played)
	check(bt.game.phase() in ["round_over", "game_over"], "1: bis zum Rundenende (%s, am Zug %s, %s)" % [bt.game.phase(),
		bt.seat_name(bt.game.current_seat()), str(bt.view_of(bt.host_seat).hints.get("text", ""))])
	if not bt.game.phase() in ["round_over", "game_over"]:
		var errs: Array = (w.inbox as Array).filter(func(m): return str(m.get("t", "")) == "err")
		print("  Wally: %s, err %s, Sicht seat %s, rev-Stände %d" % [(w.c as NetClient).state, str(errs.slice(-2)), str((w.view as Dictionary).get("seat")),
			count(w.inbox, "state")])
		print("  Wally hints: ", (w.view as Dictionary).get("hints", {}))
		var wid := bt._id_of_token((w.c as NetClient).token)
		var p: Dictionary = bt.session.player(wid)
		print("  Ben-Sitzung: Wally id %d conn %d connected %s; relay guests %s held %s; Wally my_id %d welcomes %d attempts %d" % [wid,
			int(p.get("conn", -9)), str(p.get("connected")), str(bt.session.relay._guests.keys()), str(bt.session.relay._held.keys()),
			(w.c as NetClient).my_id, (w.c as NetClient).welcomes, (w.c as NetClient).attempts])
	check(wait_until(func(): return count(h.inbox, "bk") > 0 and int(h.ct().backup.get("gen", 0)) == bt.gen), "1: Hanna (jetzt Gast) bekommt Bens Sicherungen")
	# Lecktest und Reihenfolge
	check(_leaks(w.inbox) == 0, "1: Browser-Gast bekam nie bk/alive/handover")
	check(_leaks(c.inbox) == 0, "1: App ohne hello.bk bekam nie bk/alive/handover")
	check(bk_before_each_state(b.inbox.slice(0, b_before)), "1: Ben (Gast): bk vor jeder Sicht")
	check(bk_before_each_state(h.inbox), "1: Hanna (Gast): bk vor jeder Sicht")
	check(count(w.inbox, "bye") + count(c.inbox, "bye") + count(h.inbox, "bye") == 0 and (w.closed as Array).is_empty(), "1: kein bye")
	check(b.sw.takeovers == 1 and h.sw.takeovers == 0 and c.sw.takeovers == 0, "1: genau eine Übernahme")


func _clear_all() -> void:
	for wv in webs:
		(wv.c as NetClient).close()
		(wv.c as NetClient).free()
	webs.clear()
	for d in devs:
		var s: TableSource = d.src()
		if s is HostTable:
			(s as HostTable).autosave = false
			(s as HostTable).leave()
		elif s is ClientTable:
			(s as ClientTable).leave()
		if s != null:
			garbage.append(s)
		TableSource.clear_saved(d.path)
	for g in garbage:
		if is_instance_valid(g):
			if g is HostTable:
				(g as HostTable).autosave = false
			if g.get_parent() != null:
				g.get_parent().remove_child(g)
			g.free()
	garbage.clear()
	devs.clear()
	pump(150)


# ---------- 2 ----------

func _within_abort() -> void:
	var h := host_dev("Hanna", H_PORT)
	var link := str(h.ht().session.online_info().link)
	var b := guest_dev("Ben", link, B_PORT)
	check(wait_until(func(): return b.ct().my_id > 0), "2: Ben angemeldet")
	var ht := h.ht()
	ht.handover_within_ms = 1000
	ht.add_bot("Minka")
	check(ht.start(99), "2: Start")
	play(4)
	check(wait_until(func(): return b.ct().backup_current()), "2: Bens Sicherung aktuell")
	var before := MatchSnapshot.read(b.path)
	check(not before.is_empty() and int(before.gen) == 1, "2: Bens Datei gen 1")
	var ct_before := b.ct()
	# Bens Gastgeber-Verbindung kommt nie zustande (kein room-Rahmen): Socket gleich nach dem Anlegen kappen
	b.sw.state_changed.connect(func(st: String) -> void:
		if st == "taking":
			var r: NetRelayHost = (b.sw._new as HostTable).session.relay
			if r._ws != null:
				r._ws.close()
				r._ws = null)
	var notes: Array = []
	ht.notice.connect(func(n: String) -> void: notes.append(n))
	var gen0 := ht.gen
	check(ht.handover_to(b.ct().local_seat()), "2: handover_to(Ben)")
	check(wait_until(func(): return b.sw.state == "taking"), "2: Ben versucht zu übernehmen")
	check(wait_until(func(): return b.sw.state == "watch" or b.sw.state == "off", 4000), "2: nach within_ms abgebrochen (%s)" % b.sw.state)
	check(b.sw.takeovers == 0 and b.ct() == ct_before, "2: Ben bleibt Gast am selben Tisch")
	check(wait_until(func(): return b.ct().connection_state() == "open", 4000), "2: Ben wieder als Gast angemeldet")
	var after := MatchSnapshot.read(b.path)
	check(int(after.get("gen", 0)) == 1 and str(after.get("role", "")) == "guest", "2: Datei wie vorher (gen 1, role guest)")
	check(wait_until(func(): return not ht.is_frozen(), 5000), "2: Hanna taut auf (check_now)")
	check(ht.gen == gen0 and notes.has(I18n.t("Übergabe an %s hat nicht geklappt. Du bleibst Gastgeber.") % "Ben"), "2: gen unverändert, Meldung an Hanna")
	check(h.ht() == ht and h.sw.state == "host", "2: Hanna bleibt Gastgeberin")
	var rev := ht.rev
	play(4)
	check(ht.rev > rev, "2: Partie läuft weiter")
	check(wait_until(func(): return b.ct().backup_current() and int(b.ct().backup.gen) == 1), "2: Bens Sicherung folgt wieder Hanna")
