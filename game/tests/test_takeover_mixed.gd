extends "res://tests/handover_kit.gd"

# Mau-Mau Flip (Beta 1.6.2, Gastgeber-Übergabe in gemischten Partien, docs/module/uebergabe.md 10.4, 10.7, 10.12, 10.16): Gastgeberin
# Hanna online (Vermittler-Nachbau, TCP 24924) und im WLAN (127.0.0.1), App-Gäste Willi und Wanda im WLAN, Olga online, Computer Minka;
# synchron gepumpt, kurze Fristen, Wanduhr einspritzbar. Einzelne Fälle: NUR=1 (bzw. 0,2).
#  0  WLAN-Erbe übernimmt Raum und LAN: Willi (Rang 0) prüft LAN und Raum (Probe mit eigenem Token: niemand da), übernimmt; Olga folgt
#     über den Raum (4012), Wanda per Suche.
#  1  WLAN-Erbe ohne Vermittler (Nachbau antwortet nicht): Willis Übernahme gilt fürs LAN, Wanda folgt; der Raum wird im Hintergrund
#     wiederholt – sobald der Nachbau wieder antwortet, ist er übernommen und Olga folgt per 4012.
#  2  Willi nicht aktuell, Wanda weg: Olga ist keine Erbin (WLAN-Mitspieler am Tisch, Gegenprüfung 1.6.2) und übernimmt nur von Hand;
#     Willi findet im LAN niemanden, probt in waiting den Raum und folgt über den Raum (follow_room).
#  3  Geplante Übergabe an Olga (online), während Hanna zusätzlich ein Spiel-WLAN führt: how bleibt online (WLAN-Ziel wäre qr, nur dort
#     die QR-Warnzeile); move how online an die WLAN-Gäste, beide folgen über den Raum; Hanna spielt als Gast weiter. Bei geschlossenem
#     Raum ist Olga ausgegraut.
#  4  Wettlauf aus Fall 0 (wackelig bis 15.10.2026): Hannas letzter Stand ging vor dem Ausfall nur noch über den Vermittler hinaus
#     (Olga seq + 1, Willi und Wanda nicht – der Server verwarf ihn beim Schließen). Willi übernimmt mit dem älteren Stand; die
#     Abstammungsregel gibt das Spiel trotzdem nicht an Olga (online, WLAN-Mitspieler am Tisch, 10.12) – Olga folgt Willi, ihr Zug
#     entfällt. Hier deterministisch: WLAN-Verbindungen stumm, dann eine Änderung, dann Ausfall.

const RELAY_PORT := 24924
const H_PORT := 24925
const W_PORT := 24926
const V_PORT := 24927
const O_PORT := 24928
const UDPS := [24925, 24926, 24927, 24928]

var states := {}                      # Gerät -> Zustände des HostSwitch


func _initialize() -> void:
	rng.seed = 1623
	t_silent = 500
	t_step = 1500
	probe = 500
	within = 3000
	disc_ports = UDPS.duplicate()
	start_relay(RELAY_PORT)
	var t0 := Time.get_ticks_msec()
	var only := OS.get_environment("NUR")
	var cases := [_wlan_heir, _wlan_heir_no_relay, _online_heir, _planned_online, _wlan_heir_newer_online]
	for i in cases.size():
		if only == "" or str(i) in only.split(","):
			var t1 := Time.get_ticks_msec()
			(cases[i] as Callable).call()
			print("  Fall %d: %d ms" % [i, Time.get_ticks_msec() - t1])
	print("  Dauer %d ms" % (Time.get_ticks_msec() - t0))
	finish()


# ---------- Aufbau ----------

func disc(n: NetDiscovery) -> void:
	n.use_broadcast = false
	n.probe_local = true
	n.ports = UDPS.duplicate()
	n.query_interval_ms = 100
	n.refresh_targets_ms = 200
	n.expire_ms = 1500


func mix_cfg(d: Dev) -> void:
	var sw := d.sw
	sw.lan_search_ms = 300
	sw.room_retry_ms = 500
	sw.room_probe_every_ms = 500
	sw.discovery_setup = func(n: NetDiscovery) -> void: disc(n)
	sw.wifi_release = func() -> void: pass
	sw.wifi_stop = func() -> void: pass
	sw.auto_open = func(_h: HostTable) -> void: pass
	sw.state_changed.connect(func(st: String) -> void: (states[d.name] as Array).append(st))
	states[d.name] = []
	d.disc_port = d.port


func _table() -> Array:
	var h := host_dev("Hanna", H_PORT, true, H_PORT)
	mix_cfg(h)
	var link := str(h.ht().session.online_info().link)
	var w := lan_guest("Willi", H_PORT, W_PORT)
	mix_cfg(w)
	var v := lan_guest("Wanda", H_PORT, V_PORT)
	mix_cfg(v)
	var o := guest_dev("Olga", link, O_PORT)
	mix_cfg(o)
	check(wait_until(func(): return w.ct().my_id > 0 and v.ct().my_id > 0 and o.ct().my_id > 0), "Gäste angemeldet")
	h.ht().add_bot("Minka")
	h.ht().set_rules(RuleConfig.preset("offiziell"))
	check(h.ht().start(rng.randi_range(1, 9999)), "Start")
	check(wait_until(func(): return w.ct().view_rev > 0 and v.ct().view_rev > 0 and o.ct().view_rev > 0), "Gäste haben den Stand")
	play(6)
	check(wait_until(func(): return w.ct().backup_current() and v.ct().backup_current() and o.ct().backup_current() \
		and w.sw.state == "watch" and v.sw.state == "watch" and o.sw.state == "watch"),
		"Sicherungen aktuell, Wächter scharf (%s, %s, %s)" % [w.sw.state, v.sw.state, o.sw.state])
	var heirs: Array = w.ct().backup.heirs
	# Gegenprüfung 1.6.2: mit WLAN-Mitspielern am Tisch keine Online-Erben (Olga übernimmt nur von Hand)
	check(heirs == [w.ct().client.token, v.ct().client.token], "Erben: nur WLAN (Willi, Wanda), Olga (online) nicht (%s)" % str(heirs))
	return [h, w, v, o]


func _clear() -> void:
	for d in devs:
		var s: TableSource = d.src()
		if s is HostTable:
			(s as HostTable).autosave = false
			if (s as HostTable).session != null:
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
	states.clear()
	relay_paused = false
	wall_off = 0
	pump(150)


func at_host(d: Dev, host_name: String) -> bool:
	return d.ct() != null and d.ct().connection_state() == "open" and d.ct().host_name() == host_name


# Platz als Gast (−9 = gerade kein Gast-Tisch, z. B. selbst Gastgeber geworden; ohne SCRIPT ERROR weiterprüfen)
func guest_seat(d: Dev) -> int:
	return d.ct().local_seat() if d.ct() != null else -9


func guest_online(d: Dev) -> bool:
	return d.ct() != null and d.ct().client != null and d.ct().client.is_online()


# ---------- 0 ----------

func _wlan_heir() -> void:
	var t := _table()
	var h: Dev = t[0]
	var w: Dev = t[1]
	var v: Dev = t[2]
	var o: Dev = t[3]
	var code := room_code()
	var gen0 := h.ht().gen
	var seat_o := o.ct().local_seat()
	kill_lan_closed(h)                      # App weg: Raum-Socket zu (4503) und Server zu
	check(wait_until(func(): return w.sw.takeovers == 1, 8000), "0: Willi (WLAN-Erbe) übernimmt (%s)" % w.sw.state)
	var wt := w.ht()
	check(wt != null and wt.gen == gen0 + 1 and wt.port() == W_PORT, "0: Willi führt, gen + 1, eigener Port")
	check(wait_until(func(): return wt.session.online_state() == "open", 4000) and str(wt.session.online_info().room) == code,
		"0: Willi führt den alten Raum")
	check(wait_until(func(): return at_host(o, "Willi"), 8000), "0: Olga folgt über den Raum (%s)" % o.sw.state)
	check(guest_seat(o) == seat_o and guest_online(o) and o.sw.takeovers == 0, "0: Olga online auf ihrem Platz (takeovers %d)" % o.sw.takeovers)
	check(wait_until(func(): return at_host(v, "Willi"), 6000), "0: Wanda folgt per Suche (%s)" % v.sw.state)
	check(v.sw.follows >= 1 and v.sw.takeovers == 0 and v.ct() != null and not guest_online(v), "0: Wanda im WLAN bei Willi")
	if w.ht() == wt:
		var rev := wt.rev
		wt.substitute_bot(h.ht().host_seat)
		play(6)
		check(wt.rev > rev, "0: Partie läuft weiter")
	else:
		check(false, "0: Willi führt weiter (%s)" % w.sw.state)
	_clear()


# ---------- 1 ----------

func _wlan_heir_no_relay() -> void:
	var t := _table()
	var h: Dev = t[0]
	var w: Dev = t[1]
	var v: Dev = t[2]
	var o: Dev = t[3]
	var code := room_code()
	relay_paused = true                     # Vermittler antwortet nicht (Netzfehler)
	kill_lan_closed(h)
	check(wait_until(func(): return w.sw.takeovers == 1, 10000), "1: Willi übernimmt fürs LAN ohne Vermittler (%s)" % w.sw.state)
	var wt := w.ht()
	check(wt != null and wt.session.online_state() != "open", "1: Raum noch nicht übernommen (%s)" % (wt.session.online_state() if wt != null else "?"))
	check(wait_until(func(): return at_host(v, "Willi"), 6000), "1: Wanda folgt per Suche (%s)" % v.sw.state)
	check(o.sw.takeovers == 0 and not at_host(o, "Willi"), "1: Olga wartet (Vermittler weg)")
	relay_paused = false
	check(wait_until(func(): return wt.session.online_state() == "open", 8000) and str(wt.session.online_info().room) == code,
		"1: Raum im Hintergrund übernommen (%s)" % wt.session.online_state())
	check(wait_until(func(): return at_host(o, "Willi"), 8000), "1: Olga folgt per 4012 (%s)" % o.sw.state)
	check(o.sw.takeovers == 0 and v.sw.takeovers == 0 and w.sw.takeovers == 1, "1: nur Willi hat übernommen")
	_clear()


# ---------- 2 ----------

func _online_heir() -> void:
	var t := _table()
	var h: Dev = t[0]
	var w: Dev = t[1]
	var v: Dev = t[2]
	var o: Dev = t[3]
	v.dead = true                            # Wanda ist weg (übernimmt nicht)
	w.sw.discovery_setup = func(n: NetDiscovery) -> void:
		disc(n)
		n.ports = [24929]                    # Olgas Server liegt in einem anderen Netz: Willis Suche findet ihn nicht
	kill_lan_closed(h)
	pump(30)
	w.ct().head = [int(w.ct().head[0]), str(w.ct().head[1]), int(w.ct().head[2]) + 1]   # Willi hat eine Sicherung verpasst
	check(not w.sw.is_current() and o.sw.is_current(), "2: Willi nicht aktuell, Olga schon")
	# Gegenprüfung 1.6.2: Olga ist keine Erbin (WLAN-Mitspieler am Tisch) – keine Automatik, von Hand mit Warnzeile
	check(wait_until(func(): return o.sw.state == "waiting", 6000), "2: Olga merkt das Fehlen (%s)" % o.sw.state)
	check(o.sw.rank() < 0 and o.sw.countdown_ms() < 0 and o.sw.can_continue(), "2: Olga ohne Automatik, Knopf möglich")
	pump(t_step + 300)
	check(o.sw.takeovers == 0, "2: Olga übernimmt nicht automatisch")
	check(o.sw.continue_as_host(), "2: Olga setzt von Hand fort")
	check(wait_until(func(): return o.sw.takeovers == 1, 10000), "2: Olga (online) übernimmt von Hand (%s)" % o.sw.state)
	check(w.sw.takeovers == 0, "2: Willi übernimmt nicht")
	check(wait_until(func(): return at_host(w, "Olga"), 10000), "2: Willi folgt über den Raum (%s)" % w.sw.state)
	check(guest_online(w) and w.sw.follows >= 1, "2: Willi jetzt online")
	_clear()


# ---------- 3 ----------

func _planned_online() -> void:
	var t := _table()
	var h: Dev = t[0]
	var w: Dev = t[1]
	var v: Dev = t[2]
	var o: Dev = t[3]
	var ht := h.ht()
	var seat_o := o.ct().local_seat()
	# Gegenprüfung 1.6.2: Hanna führt zusätzlich ein Spiel-WLAN – ein Online-Ziel bleibt trotzdem „online“ (kein Spiel-WLAN in einer
	# anderen Stadt), ein WLAN-Ziel wäre „qr“; die QR-Warnzeile gilt nur für qr-Ziele
	ht.hotspot_check = func() -> bool: return true
	ht.refresh_addrs()
	check(ht.game_wifi().get("ap") == true, "3: Hanna führt ein Spiel-WLAN")
	check(ht.handover_how(seat_o) == "online" and ht.handover_block(seat_o).is_empty(), "3: Übergabe an Olga online möglich")
	check(ht.handover_how(w.ct().local_seat()) == "qr", "3: WLAN-Ziel Willi wäre qr")
	var warns: Array = ht.handover_warnings(seat_o)
	var warn := I18n.render(warns[0] if not warns.is_empty() else [])
	check(warn.contains(I18n.t("WLAN-Mitspieler brauchen dann Internet.")), "3: Warnzeile WLAN-Mitspieler (%s)" % warn)
	check(warns.size() == 1 and ht.handover_warnings(w.ct().local_seat()).size() == 1
		and I18n.render(ht.handover_warnings(w.ct().local_seat())[0]) == I18n.t("Alle müssen danach einen neuen QR-Code scannen."),
		"3: QR-Warnzeile nur beim qr-Ziel (%s)" % str(warns))
	check(ht.handover_to(seat_o), "3: handover_to(Olga)")
	check(wait_until(func(): return o.sw.takeovers == 1 and o.ht() != null, 8000), "3: Olga führt (%s)" % o.sw.state)
	check(wait_until(func(): return at_host(w, "Olga") and at_host(v, "Olga"), 8000), "3: WLAN-Gäste folgen über den Raum (%s/%s)" % [w.sw.state, v.sw.state])
	check(str(last_of(w.inbox, "move").get("how", "")) == "online" and guest_online(w), "3: move online an Willi")
	check(wait_until(func(): return at_host(h, "Olga"), 8000), "3: Hanna spielt als Gast bei Olga (%s)" % h.sw.state)
	check(w.sw.takeovers == 0 and v.sw.takeovers == 0 and h.sw.takeovers == 0, "3: niemand sonst übernimmt")
	_clear()
	# Raum geschlossen: Online-Ziel ausgegraut
	t = _table()
	h = t[0]
	o = t[3]
	seat_o = o.ct().local_seat()
	h.ht().session.close_online()
	check(wait_until(func(): return not h.ht().handover_block(seat_o).is_empty(), 2000), "3b: Olga bei geschlossenem Raum ausgegraut")
	_clear()


# ---------- 4 ----------

func _wlan_heir_newer_online() -> void:
	var t := _table()
	var h: Dev = t[0]
	var w: Dev = t[1]
	var v: Dev = t[2]
	var o: Dev = t[3]
	var ht := h.ht()
	var code := room_code()
	var gen0 := ht.gen
	var seat_o := o.ct().local_seat()
	var lan_seats := [w.ct().local_seat(), v.ct().local_seat()]
	# Zug eines Nicht-WLAN-Platzes abwarten (Hanna, Olga oder Minka): Die Änderung entsteht dann ohne Willi und Wanda.
	for i in 20:
		if not ht.game.current_seat() in lan_seats:
			break
		play(1)
	check(not ht.game.current_seat() in lan_seats, "4: ein Nicht-WLAN-Platz ist dran")
	for p in ht.session.players.values():
		var conn := int(p.get("conn", -1))
		if conn >= 0 and conn < NetProtocol.RELAY_CONN_BASE:
			ht.session.server.mute_ws(conn)  # WLAN still: Hannas letzter Stand erreicht nur noch Olga
	ht.session.server.poll()
	var rev := ht.rev
	check(play(1) >= 1 and ht.rev > rev, "4: Hanna ändert noch etwas")
	var seq_w := int(MatchSnapshot.mark(w.ct().backup)[2])
	check(wait_until(func(): return int(MatchSnapshot.mark(o.ct().backup)[2]) > seq_w, 2000)
		and int(MatchSnapshot.mark(v.ct().backup)[2]) == seq_w and int(MatchSnapshot.mark(w.ct().backup)[2]) == seq_w,
		"4: nur Olga hat den neuesten Stand (O %s, W %s)" % [str(MatchSnapshot.mark(o.ct().backup)), str(MatchSnapshot.mark(w.ct().backup))])
	var mark_o := MatchSnapshot.mark(o.ct().backup)
	kill_lan_closed(h)
	check(wait_until(func(): return w.sw.takeovers == 1, 8000), "4: Willi (WLAN-Erbe) übernimmt (%s)" % w.sw.state)
	var wt := w.ht()
	check(wt != null and wt.gen == gen0 + 1 and int(wt.parent[2]) < int(mark_o[2]), "4: Willi führt mit dem älteren Stand")
	check(wait_until(func(): return wt.session.online_state() == "open", 4000) and str(wt.session.online_info().room) == code,
		"4: Willi führt den alten Raum")
	check(wait_until(func(): return at_host(o, "Willi"), 8000), "4: Olga folgt über den Raum, keine Abstammungs-Übergabe (%s)" % o.sw.state)
	check(wait_until(func(): return at_host(v, "Willi"), 6000), "4: Wanda folgt per Suche (%s)" % v.sw.state)
	pump(t_step)                             # eine Übergabe own:true käme in dieser Zeit
	check(w.ht() == wt and w.sw.state == "host" and o.sw.takeovers == 0 and at_host(o, "Willi"),
		"4: Willi bleibt Gastgeber, Olga Gast (%s, %s)" % [w.sw.state, o.sw.state])
	check(guest_seat(o) == seat_o and guest_online(o) and int(MatchSnapshot.mark(o.ct().backup)[0]) == wt.gen,
		"4: Olga auf ihrem Platz, Sicherung von Willi (%s)" % str(MatchSnapshot.mark(o.ct().backup) if o.ct() != null else []))
	_clear()
