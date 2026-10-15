extends "res://tests/handover_kit.gd"

# Mau-Mau Flip (Beta 1.6.2, Gastgeber-Übergabe im WLAN, docs/module/uebergabe.md 10.2/10.3/10.7/10.9–10.11, Testplan 10.16):
# Gastgeberin Hanna im WLAN (127.0.0.1, Server mit Thread), App-Gäste Ben (hello.ap ohne Spiel-WLAN) und Cleo (ap.ok, ohne Erlaubnis),
# Browser-Gast Wally (kind "web" wie Lite) und Computer Minka; synchron gepumpt, ohne Vermittler.
#  1  Rangfolge und Stand: Erben in Sitzordnung ohne WLAN-Sperre; seats[*].addr/hp/ap; hosts an Wally (gid, gen, Erben-URLs mit hp).
#     Spiel-WLAN (hotspot_check): ap/ap_seat, Rangfolge ap.ok zuerst, how "qr", Ziel ohne ap.ok ausgegraut, „Muss das Spiel-WLAN
#     erlauben.“, Warnzeile, hosts.ap/ap_name; Spiel-WLAN zu → ap aus.
#  2  Geplant „lan“ an Ben: handover trägt how; Ben bestätigt (handover_ok), erst dann geht move an Cleo und Wally (kommt vor dem
#     Schließen an: drain), Hanna tritt ab (step_target lan, Bens Port), wird Gast auf ihrem Platz; Cleo folgt per move, Wally (wie
#     Lite) zieht mit seinem Token um; alle auf ihren Plätzen, kein bye; die Partie läuft bis zum Rundenende.
#  3  Ziel antwortet nie (App ohne HostSwitch): ohne Raum taut Hanna nach handover_timeout_ms auf, gen unverändert, kein move; ein
#     verspätetes handover_ok wird verworfen. Danach im Spiel-WLAN: how "qr", Cleo (ohne ap.ok) ausgegraut; Doras handover_ok{qr}
#     → move qr mit ihrem Namen an Cleo, step_target qr.
#  3c Gegenprüfung 1.6.2: handover how qr, Dora antwortet aber handover_ok{port, qr:false} → move lan mit ihrem Port, step_target lan.
#  4  resume() ohne Raum als Übernahme: Link des alten Gastgebers „wlan“ (addr, hp), wlan.past = alte Adressen × Port, erlaubte
#     Herkunft, Warteliste offen solange ein Platz getrennt ist; seat_assign setzt einen neuen Browser-Gast auf Wallys Platz (assigned,
#     start), Ablehnungen (Gastgeber, Computer, verbundener Platz); alle zurück → join_open wie vorher.
#  5  Gastgeber-Wächter (_on_rival): Regel rival_wins/rival_outcome; Verlierer tritt frühestens beim zweiten gleichen Scan ab und erst,
#     wenn der Gewinner seine gen angehoben hat (höchstens rival_gen_wait weitere Scans; move lan an seine Gäste, Meldung, step_target),
#     schwankendes Ergebnis setzt zurück; Gewinner hebt gen über die des anderen (parent, neue epoch, bk), mit offenem Raum ebenso;
#     Adressen des anderen in past und erlaubter Herkunft. Mit offenem Raum entscheidet bei gleicher gen der Vermittler.

const H_PORT := 24925
const B_PORT := 24926
const C_PORT := 24927
const X_PORT := 24928


func _initialize() -> void:
	rng.seed = 1622
	var t0 := Time.get_ticks_msec()
	_basics_and_planned()
	_clear_all()
	_no_answer()
	_clear_all()
	_qr_answered_lan()
	_clear_all()
	_resume_and_assign()
	_clear_all()
	print("  Dauer %d ms" % (Time.get_ticks_msec() - t0))
	finish()


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


func _table(ben_ap := {}, cleo_ap := {"ok": true, "perm": false}) -> Array:
	var h := host_dev("Hanna", H_PORT, false)
	var b := lan_guest("Ben", H_PORT, B_PORT, true, ben_ap)
	var c := lan_guest("Cleo", H_PORT, C_PORT, true, cleo_ap)
	var w := web_guest_lan("Wally", H_PORT)
	check(wait_until(func(): return b.ct().my_id > 0 and c.ct().my_id > 0 and (w.c as NetClient).my_id > 0), "Gäste im WLAN angemeldet")
	var ht := h.ht()
	ht.add_bot("Minka")
	ht.set_rules(RuleConfig.preset("offiziell"))
	return [h, b, c, w]


func _urls(m: Dictionary) -> Array:
	return (m.get("list", []) as Array).map(func(e): return str(e.url))


# ---------- 1 + 2 ----------

func _basics_and_planned() -> void:
	var t := _table()
	var h: Dev = t[0]
	var b: Dev = t[1]
	var c: Dev = t[2]
	var w: Dictionary = t[3]
	var ht := h.ht()
	check(ht.start(1622), "1: Start")
	check(wait_until(func(): return b.ct().view_rev > 0 and c.ct().view_rev > 0 and not (w.view as Dictionary).is_empty()), "1: alle haben den Stand")
	play(4)
	var seat := {"Hanna": ht.host_seat, "Ben": b.ct().local_seat(), "Cleo": c.ct().local_seat(), "Wally": int((w.view as Dictionary).seat)}
	var tb := str(ht.seats[seat.Ben].token)
	var tc := str(ht.seats[seat.Cleo].token)
	check(ht.wlan_humans() and ht.heirs() == [tb, tc], "1: Erben Ben, Cleo trotz WLAN-Mitspielern (%s)" % str(ht.heirs()))
	var sb: Dictionary = ht.seats[seat.Ben]
	check(str(sb.get("link", "")) == "wlan" and str(sb.get("addr", "")) == "127.0.0.1" and int(sb.get("hp", 0)) == B_PORT,
		"1: Ben link/addr/hp im Stand (%s)" % str(sb))
	check(sb.get("ap") == {"ok": false, "perm": false} and ht.seats[seat.Cleo].get("ap") == {"ok": true, "perm": false}, "1: ap je Platz")
	check(not ht.seats[seat.Wally].has("ap") and not ht.seats[seat.Wally].has("hp"), "1: Browser-Gast ohne ap/hp")
	var hosts := last_of(w.inbox, "hosts")
	check(str(hosts.get("gid", "")) == ht.gid and int(hosts.get("gen", 0)) == 1, "1: hosts an Wally mit gid und gen (%s)" % str(hosts))
	check(_urls(hosts) == ["http://127.0.0.1:%d/" % B_PORT, "http://127.0.0.1:%d/" % C_PORT] and str(hosts.get("online", "x")) == ""
		and hosts.get("ap") == false, "1: hosts: Erben-URLs mit hp, kein Raum, kein Spiel-WLAN")
	check(count(b.inbox, "hosts") == 0 and count(c.inbox, "hosts") == 0, "1: hosts nur an Browser-Gäste")
	check(wait_until(func(): return b.ct().backup_current()), "1: Bens Sicherung aktuell")
	var wl: Dictionary = b.ct().backup.get("wlan", {})
	check(wl.get("ap") == false and int(wl.get("ap_seat", 0)) == -1 and (wl.get("past", ["x"]) as Array).is_empty(), "1: Stand wlan ohne Spiel-WLAN (%s)" % str(wl))
	check(ht.handover_how(seat.Ben) == "lan" and ht.handover_block(seat.Ben).is_empty() and ht.handover_block(seat.Cleo).is_empty(),
		"1: Übergabe im WLAN möglich (how lan)")
	check(ht.handover_block(seat.Wally) == ["Nur Mitspieler mit der App können Gastgeber werden."], "1: Browser-Gast nicht wählbar")
	check(ht.handover_warnings(seat.Ben).is_empty(), "1: keine Warnzeile ohne Spiel-WLAN")
	# Spiel-WLAN geht auf (GameWifiWatch → refresh_addrs)
	var hosts_before := count(w.inbox, "hosts")
	ht.hotspot_check = func() -> bool: return true
	ht.refresh_addrs()
	check(ht.game_wifi() == {"ap": true, "ap_seat": ht.host_seat}, "1: Spiel-WLAN: ap, ap_seat = Gastgeber")
	check(ht.heirs() == [tc, tb], "1: Spiel-WLAN: Cleo (ap.ok) vor Ben")
	check(ht.handover_how(seat.Ben) == "qr" and ht.handover_block(seat.Ben) == ["Kann kein Spiel-WLAN öffnen."], "1: qr – Ben ausgegraut")
	check(ht.handover_block(seat.Cleo).is_empty() and ht.handover_notes(seat.Cleo) == ["Muss das Spiel-WLAN erlauben."], "1: qr – Cleo wählbar, muss erlauben")
	check(ht.handover_warnings(seat.Cleo) == [["Alle müssen danach einen neuen QR-Code scannen."]], "1: Warnzeile QR-Code")
	check(wait_until(func(): return count(w.inbox, "hosts") > hosts_before), "1: neue hosts nach dem Spiel-WLAN")
	hosts = last_of(w.inbox, "hosts")
	check(hosts.get("ap") == true and str(hosts.get("ap_name", "")) == "Cleo" and _urls(hosts)[0] == "http://127.0.0.1:%d/" % C_PORT,
		"1: hosts: ap, ap_name = Rang 0 (Cleo)")
	check(wait_until(func(): return bool((b.ct().backup.get("wlan", {}) as Dictionary).get("ap", false))), "1: Sicherung mit wlan.ap")
	ht.hotspot_check = func() -> bool: return false
	ht.refresh_addrs()
	check(ht.game_wifi() == {"ap": false, "ap_seat": -1} and ht.heirs() == [tb, tc], "1: Spiel-WLAN zu → ap aus, Rangfolge wie vorher")
	check(wait_until(func(): return last_of(w.inbox, "hosts").get("ap") == false), "1: hosts ohne ap")

	# ---------- 2: geplant lan an Ben ----------
	check(wait_until(func(): return b.ct().backup_current()), "2: Bens Sicherung aktuell")
	var gen0 := ht.gen
	var b_before := b.inbox.size()
	var moves_seen := [false]
	var hanna_addrs: Array = ht._addrs.duplicate()
	ht.stepped_down.connect(func(_n: String) -> void:
		moves_seen[0] = not ht.step_target.is_empty())
	check(ht.handover_to(seat.Ben), "2: handover_to(Ben)")
	check(ht.is_frozen() and count(c.inbox, "move") == 0, "2: eingefroren, noch kein move vor handover_ok")
	check(wait_until(func(): return b.ht() != null, 6000), "2: Ben führt (Zustand %s)" % b.sw.state)
	var ho := b.inbox.slice(b_before).filter(func(m): return str(m.get("t", "")) == "handover")
	check(ho.size() == 1 and str((ho[0] as Dictionary).get("how", "")) == "lan", "2: handover mit how lan")
	var bt := b.ht()
	check(bt.gen == gen0 + 1 and bt.host_seat == seat.Ben and bt.port() == B_PORT, "2: Ben auf seinem Platz und Port, gen + 1")
	check(wait_until(func(): return count(c.inbox, "move") > 0 and count(w.inbox, "move") > 0, 4000), "2: move an Cleo und Wally")
	check(wait_until(func(): return moves_seen[0]), "2: stepped_down nach move, step_target gesetzt")
	var mv := last_of(c.inbox, "move")
	check(str(mv.get("how", "")) == "lan" and str(mv.get("addr", "")) == "127.0.0.1" and int(mv.get("port", 0)) == B_PORT
		and str(mv.get("gid", "")) == bt.gid and str(mv.get("name", "")) == "Ben", "2: move lan zu Bens Server (%s)" % str(mv))
	check(str(last_of(w.inbox, "move").get("url", "")) == "http://127.0.0.1:%d/" % B_PORT, "2: move an Wally mit url")
	check(count(b.inbox.slice(b_before), "move") == 0, "2: kein move an das Ziel")
	# Wally zieht um wie Lite (move lan: sofort, mit Token)
	var wc: NetClient = w.c
	var wtok := wc.token
	wc.connect_to(str(mv.get("addr", "127.0.0.1")), int(mv.get("port", B_PORT)), "Wally", "web")
	wc.token = wtok
	check(wait_until(func(): return h.ct() != null and h.ct().connection_state() == "open", 6000), "2: Hanna spielt als Gast weiter (%s)" % h.sw.state)
	check(str(h.swaps[0][1]) == I18n.t("Du spielst jetzt als Gast weiter. Gastgeber ist %s.") % "Ben", "2: Hinweis „Gastgeber ist Ben“")
	var follow := func() -> bool:
		return c.ct().connection_state() == "open" and c.ct().host_name() == "Ben" and wc.state == "open" and wc.host_name == "Ben"
	check(wait_until(follow, 6000), "2: Cleo (move) und Wally (Token) bei Ben")
	var seated := func() -> bool:
		return h.ct().local_seat() == seat.Hanna and c.ct().local_seat() == seat.Cleo and int((w.view as Dictionary).get("seat", -1)) == seat.Wally
	check(wait_until(seated, 4000), "2: alle auf ihren Plätzen")
	check(wait_until(func(): return not bt.is_settling(), 3000), "2: Einschwingzeit vorbei")
	var hb := last_of(w.inbox, "hosts")
	check(wait_until(func(): return int(last_of(w.inbox, "hosts").get("gen", 0)) == bt.gen), "2: Wally bekommt hosts mit der neuen gen")
	hb = last_of(w.inbox, "hosts")
	check(str(hb.get("gid", "")) == bt.gid, "2: hosts nach dem Umzug: gleiche gid")
	var rev := bt.rev
	var played := play(0, true)
	check(bt.rev > rev and played > 0, "2: Partie läuft weiter (%d Züge)" % played)
	check(bt.game.phase() in ["round_over", "game_over"], "2: bis zum Rundenende (%s)" % bt.game.phase())
	check(count(w.inbox, "bye") + count(c.inbox, "bye") + count(h.inbox, "bye") == 0, "2: kein bye")
	check(b.sw.takeovers == 1 and h.sw.takeovers == 0 and c.sw.takeovers == 0, "2: genau eine Übernahme")
	var bo := bt.session.extra_origins()
	check(hanna_addrs.is_empty() or bo.has("http://%s:%d" % [hanna_addrs[0], H_PORT]), "2: Herkunft der alten Seite erlaubt (%s)" % str(bo))


# ---------- 3: Ziel antwortet nie ----------

func _no_answer() -> void:
	var h := host_dev("Hanna", H_PORT, false)
	var c := lan_guest("Cleo", H_PORT, C_PORT)
	# Dora: App mit hello.bk, aber ohne HostSwitch – bestätigt nie (spielt über play() mit wie ein Browser-Gast)
	var dw := _web("Dora")
	var dora: NetClient = dw.c
	var dora_in: Array = dw.inbox
	dora.bk = NetProtocol.BK_NONE.duplicate()
	dora.ap_info = func() -> Dictionary: return {"ok": true, "perm": true}
	dora.connect_to("127.0.0.1", H_PORT, "Dora", "app")
	check(wait_until(func(): return c.ct().my_id > 0 and dora.my_id > 0), "3: Gäste angemeldet")
	var ht := h.ht()
	ht.add_bot("Minka")
	check(ht.start(33), "3: Start")
	play(3)
	var notes: Array = []
	ht.notice.connect(func(n: String) -> void: notes.append(n))
	var down := [0]
	ht.stepped_down.connect(func(_n: String) -> void: down[0] += 1)
	var gen0 := ht.gen
	var ds := ht.session.seat_of(dora.my_id)
	check(ht.handover_block(ds).is_empty() and ht.handover_to(ds), "3: handover_to(Dora)")
	check(wait_until(func(): return count(dora_in, "handover") == 1), "3: Dora bekommt handover")
	pump(1000)
	check(ht.is_frozen(), "3: vor der Frist eingefroren")
	check(wait_until(func(): return not ht.is_frozen(), 4000), "3: nach handover_timeout_ms aufgetaut (ohne Raum, ohne check_now)")
	check(ht.gen == gen0 and down[0] == 0 and ht.step_target.is_empty(), "3: gen unverändert, kein Abtreten")
	check(notes.has(I18n.t("Übergabe an %s hat nicht geklappt. Du bleibst Gastgeber.") % "Dora"), "3: Meldung an Hanna")
	check(count(c.inbox, "move") == 0, "3: kein move ohne handover_ok")
	# verspätetes handover_ok nach dem Auftauen wird verworfen
	dora.send(NetProtocol.make_handover_ok(24999, false))
	pump(300)
	check(not ht.is_frozen() and count(c.inbox, "move") == 0 and down[0] == 0, "3: verspätetes handover_ok verworfen")
	var rev := ht.rev
	play(3)
	check(ht.rev > rev, "3: Partie läuft weiter")
	# qr: Hanna führt ein Spiel-WLAN; Dora (ap.ok) bestätigt mit handover_ok{qr} → move qr mit Doras Namen, step_target qr
	ht.hotspot_check = func() -> bool: return true
	ht.refresh_addrs()
	check(ht.handover_how(ds) == "qr" and ht.handover_block(ds).is_empty(), "3: qr – Dora kann ein Spiel-WLAN öffnen")
	check(ht.handover_block(ht.session.seat_of(c.ct().my_id)) == ["Kann kein Spiel-WLAN öffnen."], "3: qr – Cleo ohne ap.ok ausgegraut")
	var n_ho := count(dora_in, "handover")
	check(ht.handover_to(ds), "3: handover_to(Dora) mit qr")
	check(wait_until(func(): return count(dora_in, "handover") > n_ho), "3: Dora bekommt handover")
	check(str(last_of(dora_in, "handover").get("how", "")) == "qr", "3: handover how qr")
	dora.send(NetProtocol.make_handover_ok(0, true))
	check(wait_until(func(): return count(c.inbox, "move") > 0), "3: move an Cleo")
	var mv := last_of(c.inbox, "move")
	check(str(mv.get("how", "")) == "qr" and str(mv.get("name", "")) == "Dora" and int(mv.get("gen", 0)) == gen0 + 1, "3: move qr mit Doras Namen (%s)" % str(mv))
	check(count(dora_in, "move") == 0, "3: kein move an das Ziel")
	check(wait_until(func(): return down[0] == 1), "3: Hanna tritt ab")
	check(str(ht.step_target.get("how", "")) == "qr" and str(ht.step_target.get("name", "")) == "Dora", "3: step_target qr")


# ---------- 3c: Ziel antwortet anders als gemeint (Gegenprüfung 1.6.2) ----------

# Hanna führt ein Spiel-WLAN und übergibt mit how qr; Dora meldet aber handover_ok{port, qr:false} (sie führt im bisherigen Netz).
# Hanna folgt der Antwort: move lan mit Doras Port an Cleo, step_target lan – ihr Spiel-WLAN bleibt das Netz der Partie.
func _qr_answered_lan() -> void:
	var h := host_dev("Hanna", H_PORT, false)
	var c := lan_guest("Cleo", H_PORT, C_PORT)
	var dw := _web("Dora")
	var dora: NetClient = dw.c
	var dora_in: Array = dw.inbox
	dora.bk = NetProtocol.BK_NONE.duplicate()
	dora.ap_info = func() -> Dictionary: return {"ok": true, "perm": true}
	dora.connect_to("127.0.0.1", H_PORT, "Dora", "app")
	check(wait_until(func(): return c.ct().my_id > 0 and dora.my_id > 0), "3c: Gäste angemeldet")
	var ht := h.ht()
	ht.add_bot("Minka")
	check(ht.start(34), "3c: Start")
	play(2)
	var down := [0]
	ht.stepped_down.connect(func(_n: String) -> void: down[0] += 1)
	ht.hotspot_check = func() -> bool: return true
	ht.refresh_addrs()
	var ds := ht.session.seat_of(dora.my_id)
	check(ht.handover_how(ds) == "qr" and ht.handover_to(ds), "3c: handover_to(Dora) mit qr")
	check(wait_until(func(): return count(dora_in, "handover") == 1), "3c: Dora bekommt handover")
	dora.send(NetProtocol.make_handover_ok(24990, false))
	check(wait_until(func(): return count(c.inbox, "move") > 0), "3c: move an Cleo")
	var mv := last_of(c.inbox, "move")
	check(str(mv.get("how", "")) == "lan" and int(mv.get("port", 0)) == 24990 and str(mv.get("name", "")) == "Dora",
		"3c: move lan mit Doras Port statt qr (%s)" % str(mv))
	check(wait_until(func(): return down[0] == 1), "3c: Hanna tritt ab")
	check(str(ht.step_target.get("how", "")) == "lan" and int(ht.step_target.get("port", 0)) == 24990, "3c: step_target lan (%s)" % str(ht.step_target))


# ---------- 4 + 5: resume als Übernahme, seat_assign, Wächter ----------

func _resume_and_assign() -> void:
	var t := _table()
	var h: Dev = t[0]
	var b: Dev = t[1]
	var c: Dev = t[2]
	var w: Dictionary = t[3]
	var ht := h.ht()
	check(ht.start(4711), "4: Start")
	check(wait_until(func(): return not (w.view as Dictionary).is_empty()), "4: Wally hat den Stand")
	play(3)
	check(wait_until(func(): return b.ct().backup_current()), "4: Bens Sicherung aktuell")
	var data: Dictionary = b.ct().backup.duplicate(true)
	var bseat := b.ct().local_seat()
	var wseat := int((w.view as Dictionary).seat)
	var old_hs := int(data.host_seat)
	var old_addrs: Array = (data.wlan as Dictionary).get("addrs", [])
	# Hanna und alle Gäste weg (Absturz im WLAN), Ben setzt allein fort
	_clear_all()
	var x := make_host()
	x.save_path = BASE_PATH % "x"
	x.autosave = false
	root.add_child(x)
	check(x.resume(data, bseat, X_PORT, X_PORT) == OK, "4: resume als Übernahme ohne Raum")
	check(x.gen == int(data.gen) + 1 and x.host_seat == bseat, "4: gen + 1, Ben führt")
	var so: Dictionary = x.seats[old_hs]
	check(str(so.link) == "wlan" and str(so.net) == "app", "4: alter Gastgeber-Platz: Link wlan (kein Raum)")
	if not old_addrs.is_empty():
		check(str(so.get("addr", "")) == str(old_addrs[0]) and int(so.get("hp", 0)) == H_PORT, "4: alter Gastgeber mit addr/hp")
		check(x.past_hosts().has("%s:%d" % [old_addrs[0], H_PORT]), "4: wlan.past mit der alten Adresse (%s)" % str(x.past_hosts()))
		check(x.session.extra_origins().has("http://%s:%d" % [old_addrs[0], H_PORT]), "4: alte Herkunft erlaubt")
	check(x.session.join_open and not bool(x._save_extra().join_open), "4: Warteliste offen (gespeichert bleibt der vorige Wert)")
	var xs := x._snapshot()
	check((xs.wlan as Dictionary).has("past") and (xs.wlan as Dictionary).has("ap_seat"), "4: Stand mit wlan.past/ap_seat")
	# Ein neuer Browser-Gast kommt (z. B. nach dem Spiel-QR) und landet auf der Warteliste
	var nw := _web("Neo")
	(nw.c as NetClient).connect_to("127.0.0.1", X_PORT, "Neo", "web")
	var pumpx := func() -> void:
		x.pump()
		for wv in webs:
			(wv.c as NetClient).poll()
	var until := func(cond: Callable) -> bool:
		var end := Time.get_ticks_msec() + 4000
		while Time.get_ticks_msec() < end:
			pumpx.call()
			if cond.call():
				return true
			OS.delay_msec(2)
		return cond.call()
	check(until.call(func(): return x.waiting_ids().size() == 1), "4: Neo wartet")
	var nid: int = x.waiting_ids()[0]
	check(not x.seat_assign(nid, x.host_seat), "4: seat_assign: nicht auf den Gastgeber")
	var bot := -1
	for s in x.seats.size():
		if str(x.seats[s].kind) == "bot":
			bot = s
	check(bot >= 0 and not x.seat_assign(nid, bot), "4: seat_assign: nicht auf einen Computer")
	check(x.free_human_seats().has(wseat) and x.free_human_seats().has(old_hs), "4: freie Menschenplätze")
	check(x.seat_assign(nid, wseat), "4: Neo auf Wallys Platz")
	check(until.call(func(): return (nw.c as NetClient).token == str(x.seats[wseat].token) and int((nw.view as Dictionary).get("seat", -1)) == wseat),
		"4: Neo hat Wallys Token und Platz")
	var nwc: NetClient = nw.c
	check(nwc.welcomes == 2 and not nwc.removed and not nwc.readmitted, "4: zweites welcome (assigned), weder removed noch readmitted")
	check(count(nw.inbox, "start") >= 1 and int(last_of(nw.inbox, "start").get("seat", -1)) == wseat, "4: start mit Platz")
	check(not x.seat_assign(nid, wseat), "4: Platz jetzt verbunden – kein zweites Mal")
	check(x.session.join_open, "4: Warteliste bleibt offen (Hanna, Cleo getrennt)")
	# Hanna und Cleo kommen mit ihren Tokens zurück → Warteliste wieder wie vorher
	for s in [old_hs, seat_named(data, "Cleo")]:
		var a := _web("App%d" % s)
		var ac: NetClient = a.c
		ac.bk = NetProtocol.BK_NONE.duplicate()
		ac.connect_to("127.0.0.1", X_PORT, str(x.seats[s].name), "app")
		ac.token = str(x.seats[s].token)
	check(until.call(func(): return x.free_human_seats().is_empty()), "4: alle zurück")
	check(until.call(func(): return not x.session.join_open), "4: Warteliste wieder wie vorher (zu)")

	# ---------- 5: Gastgeber-Wächter ----------
	check(HostTable.rival_wins(2, 1, "aa", 1, 5, "ff") and not HostTable.rival_wins(1, 5, "ff", 2, 1, "aa"), "5: mehr Verbundene gewinnen")
	check(HostTable.rival_wins(1, 3, "00", 1, 2, "ff") and HostTable.rival_wins(1, 2, "bb", 1, 2, "aa") and not HostTable.rival_wins(1, 2, "aa", 1, 2, "bb"),
		"5: dann gen, dann epoch")
	# rival_outcome (Gegenprüfung 1.6.2): Gewinner mit offenem Raum hebt an, auch wenn der Verlierer (ohne Vermittler) die höhere gen hat
	check(HostTable.rival_outcome(true, 3, 1, "aa", 1, 2, "bb") == {"lose": false, "raise": true}, "5: offener Raum, mehr Verbundene: anheben statt abtreten")
	check(HostTable.rival_outcome(false, 1, 2, "bb", 3, 1, "aa") == {"lose": true, "raise": false}, "5: Gegenseite ohne Raum: verliert über conn")
	check(HostTable.rival_outcome(true, 1, 2, "bb", 3, 2, "aa") == {"lose": false, "raise": false}, "5: offener Raum, gleiche gen: der Vermittler entscheidet")
	check(HostTable.rival_outcome(true, 1, 1, "bb", 3, 2, "aa") == {"lose": true, "raise": false}, "5: offener Raum, kleinere gen: abtreten")
	check(HostTable.rival_outcome(false, 2, 5, "aa", 2, 5, "aa") == {"lose": false, "raise": false}, "5: völlig gleich: nichts")
	check(HostTable.rival_outcome(false, 2, 6, "aa", 1, 5, "ff") == {"lose": false, "raise": false}, "5: Gewinner mit schon höherer gen hebt nicht an")
	until.call(func(): return not x.is_settling())
	var my_conn := x.session.connected_humans()
	check(my_conn == 3, "5: drei verbundene Menschen (%d)" % my_conn)
	# Gewinner: Rita hat weniger Verbundene, aber höhere gen → x hebt gen über ihre
	var g0 := x.gen
	var m0 := x.mark()
	var rita := {"gid": x.gid, "gen": g0 + 4, "epoch": "0badf00d", "conn": 1, "port": 24990, "address": "127.0.0.1",
		"addresses": ["10.9.8.7"], "name": "Rita", "sid": "r1"}
	var bk_before := count((webs[webs.size() - 2].inbox as Array), "bk")
	x._on_rival(rita)
	check(x.gen == g0 + 5 and x.parent == m0 and x.epoch != str(m0[1]) and not x.is_frozen(), "5: Gewinner hebt gen über die des anderen")
	check(x.past_hosts().has("10.9.8.7:24990") and x.session.extra_origins().has("http://10.9.8.7:24990"), "5: Adressen des anderen erlaubt")
	var app0_in: Array = webs[webs.size() - 2].inbox
	check(until.call(func(): return count(app0_in, "bk") > bk_before and int(last_of(app0_in, "bk").get("gen", 0)) == x.gen),
		"5: neue Sicherung (neue gen) sofort hinaus")
	x._on_rival(rita)
	check(x.gen == g0 + 5, "5: kein zweites Anheben")
	# Verlierer: Rolf hat mehr Verbundene. Erster Scan: noch nichts; schwankendes Ergebnis setzt zurück; zwei gleiche → Abtreten.
	var downs: Array = []
	x.stepped_down.connect(func(n: String) -> void:
		downs.append(n)
		x.handover_shutdown())
	var rolf := {"gid": x.gid, "gen": 1, "epoch": "01", "conn": my_conn + 2, "port": 24991, "address": "127.0.0.1", "addresses": [],
		"name": "Rolf", "sid": "r2"}
	x._on_rival(rolf)
	pumpx.call()
	check(downs.is_empty() and not x.is_frozen(), "5: erster Scan – noch kein Abtreten")
	var rolf_low := rolf.duplicate()
	rolf_low.conn = 0
	x._on_rival(rolf_low)
	x._on_rival(rolf)
	pumpx.call()
	check(downs.is_empty(), "5: schwankendes Ergebnis – zählt neu")
	x._on_rival({"gid": "ffff", "gen": 99, "conn": 9, "port": 1, "sid": "fremd"})
	check(not x.is_frozen(), "5: fremde gid wird übergangen")
	var nmsgs: Array = nw.inbox
	var before_moves := count(nmsgs, "move")
	# Gegenprüfung 1.6.2: Abtreten erst, wenn der Gewinner seine gen über die eigene gehoben hat (sonst holte die Abstammungsregel den
	# eigenen Zweig zurück) – Rolf meldet noch gen 1: warten, nach rival_gen_wait weiteren Scans trotzdem abtreten
	x.rival_gen_wait = 2
	x._on_rival(rolf)
	pumpx.call()
	check(not x.is_frozen() and downs.is_empty(), "5: zweiter gleicher Scan, Rolfs gen noch kleiner – warten")
	x._on_rival(rolf)
	check(not x.is_frozen(), "5: dritter Scan – weiter warten")
	x._on_rival(rolf)
	check(x.is_frozen() and x.step_target.get("how") == "lan" and int(x.step_target.get("port", 0)) == 24991
		and str(x.step_target.get("name", "")) == "Rolf", "5: nach rival_gen_wait Scans tritt der Verlierer trotzdem ab (%s)" % str(x.step_target))
	check(until.call(func(): return downs.size() == 1), "5: stepped_down nach drain")
	for wv in webs:
		for i in 20:
			(wv.c as NetClient).poll()
			OS.delay_msec(2)
	check(count(nmsgs, "move") == before_moves + 1 and int(last_of(nmsgs, "move").get("port", 0)) == 24991, "5: move lan an die eigenen Gäste")
	var note := false
	for m in nmsgs:
		if str(m.get("t", "")) == "notice" and JSON.stringify(m.get("lt", [])).contains("führt dieses Spiel schon"):
			note = true
	check(note, "5: Meldung „… führt dieses Spiel schon – ihr spielt dort weiter.“")
	check(x.step_target.get("how") == "lan", "5: step_target nach handover_shutdown lesbar")
	if x.get_parent() != null:
		x.get_parent().remove_child(x)
	x.free()


func seat_named(data: Dictionary, n: String) -> int:
	for s in (data.seats as Array).size():
		if str(data.seats[s].name) == n:
			return s
	return -1
