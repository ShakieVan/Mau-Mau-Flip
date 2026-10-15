extends "res://tests/handover_kit.gd"

# Mau-Mau Flip (Beta 1.6.2, docs/module/uebergabe.md 10.6, 10.13, 10.14, 10.16): abgelaufener Online-Raum und Hauptmenü „Partie
# fortsetzen“ mit WLAN-Dateien – Vermittler-Nachbau (TCP 24987), Gastgeberin Hanna, App-Gäste Anna und Ben (HostSwitch), Computer
# Minka; WLAN-Fälle auf 127.0.0.1 (TCP/UDP 24988–24990). Einzelne Fälle: NUR=2 (bzw. 0,1).
#  0  Raum abgelaufen (Gastgeberin weg, Nachbau löscht den Raum nach grace): Gäste landen in gone; Anna setzt „In neuem Raum
#     fortsetzen“ fort (gen + 1, neuer Code, Warteliste offen, Hinweis „Neuer Raum %s …“); Ben tritt per neuem Code bei und landet über
#     bk_token (Sicherung beim Beitritt, Raumalter egal) auf seinem Platz.
#  1  Eigene Datei, deren Raum älter als 24 h ist: saved_offer bietet sie an (resumable(…, true)), resume_saved → expired;
#     resume_new_room setzt im neuen Raum fort (eigener Zweig, gen bleibt).
#  2  Hauptmenü mit WLAN-Datei: zuerst Suche nach der gid. Anna (Gast-Datei) findet Hanna und spielt als Gast weiter (ohne Rückfrage).
#     Ohne Fund: Gast-Datei → Rückfrage (Port belegt: expired mit „Das Spiel ließ sich gerade nicht eröffnen …“), dann führt Anna (gen + 1); Hannas eigene Datei mit Spiel-WLAN → Rückfrage mit ap, „Spiel-WLAN
#     neu öffnen“ setzt den eigenen Zweig fort (gen bleibt) und öffnet ein eigenes Spiel-WLAN.

const RELAY_PORT := 24987
const H_PORT := 24988
const A_PORT := 24989
const B_PORT := 24990
const UDPS := [24988, 24989, 24990]

var opened := {}                      # Gerät -> Anzahl auto_open


func _initialize() -> void:
	rng.seed = 1624
	t_silent = 500
	t_step = 1500
	probe = 500
	within = 3000
	disc_ports = UDPS.duplicate()
	start_relay(RELAY_PORT)
	var t0 := Time.get_ticks_msec()
	var only := OS.get_environment("NUR")
	var cases := [_gone_new_room, _old_room_file, _menu_wlan]
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


func cfg(d: Dev) -> void:
	d.disc_port = d.port
	d.sw.lan_search_ms = 300
	d.sw.menu_search_ms = 600
	d.sw.discovery_setup = func(n: NetDiscovery) -> void: disc(n)
	d.sw.wifi_release = func() -> void: pass
	d.sw.wifi_stop = func() -> void: pass
	d.sw.auto_open = func(_h: HostTable) -> void: opened[d.name] = int(opened.get(d.name, 0)) + 1


func _start(h: Dev, guests: Array) -> void:
	check(wait_until(func(): return guests.all(func(g): return (g as Dev).ct().my_id > 0)), "Gäste angemeldet")
	h.ht().add_bot("Minka")
	h.ht().set_rules(RuleConfig.preset("offiziell"))
	check(h.ht().start(rng.randi_range(1, 9999)), "Start")
	check(wait_until(func(): return guests.all(func(g): return (g as Dev).ct().view_rev > 0)), "Gäste haben den Stand")
	play(6)
	check(wait_until(func(): return guests.all(func(g): return (g as Dev).ct().backup_current())), "Sicherungen aktuell")


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
		if is_instance_valid(d.sw) and d.sw.get_parent() == null and d.src() == null:
			d.sw.cancel()
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
	opened.clear()
	wall_off = 0
	pump(150)


# „App neu gestartet“: Hauptmenü mit eigenem HostSwitch (ohne Quelle), dieselbe Datei.
func menu_dev(old: Dev) -> Dev:
	var d := Dev.new()
	d.name = old.name
	d.path = old.path
	d.port = old.port
	d.ap = old.ap
	d.sw = HostSwitch.new()
	_config(d)
	cfg(d)
	devs.append(d)
	return d


# Gerät aus dem Test nehmen (App beendet, ohne Verlassen): Quelle ohne bye weg, Datei bleibt.
func drop_dev(d: Dev) -> void:
	devs.erase(d)
	var s := d.src()
	if s is ClientTable:
		(s as ClientTable).suspend()
	elif s is HostTable:
		(s as HostTable).autosave = false
		(s as HostTable).handover_shutdown()
	if s != null:
		garbage.append(s)


# ---------- 0 ----------

func _gone_new_room() -> void:
	var h := host_dev("Hanna", H_PORT)
	cfg(h)
	var link := str(h.ht().session.online_info().link)
	var a := guest_dev("Anna", link, A_PORT)
	cfg(a)
	var b := guest_dev("Ben", link, B_PORT)
	cfg(b)
	_start(h, [a, b])
	a.sw.automatic = false
	b.sw.automatic = false
	var code := room_code()
	var gen0 := h.ht().gen
	var seats := {"Anna": a.ct().local_seat(), "Ben": b.ct().local_seat()}
	kill_closed(h)
	check(wait_until(func(): return a.sw.state == "waiting" and b.sw.state == "waiting", 6000), "0: Gäste vermissen Hanna")
	relay.advance(relay.core.grace_ms + 1000)    # Raum läuft ab
	check(not relay.core.rooms.has(code), "0: Raum gelöscht")
	check(a.sw.continue_as_host(), "0: Anna will fortsetzen")
	check(wait_until(func(): return a.sw.state == "gone", 6000), "0: Anna sieht den abgelaufenen Raum (%s)" % a.sw.state)
	check(a.sw.can_new_room() and a.sw.resume_new_room(), "0: In neuem Raum fortsetzen")
	check(wait_until(func(): return a.ht() != null and a.sw.takeovers == 1, 6000), "0: Anna führt (%s)" % a.sw.state)
	var at := a.ht()
	var new_code := str(at.session.online_info().room)
	check(new_code != "" and new_code != code and at.session.online_state() == "open", "0: neuer Raum %s" % new_code)
	check(at.gen == gen0 + 1 and at.host_seat == seats.Anna, "0: gen + 1, Anna auf ihrem Platz")
	check(str(a.swaps[-1][1]) == I18n.t("Neuer Raum %s. Schick den anderen den Link – sie kommen damit auf ihre Plätze.") % new_code,
		"0: Hinweis „Neuer Raum …“ (%s)" % str(a.swaps[-1][1]))
	check(at.session.join_open, "0: Warteliste offen")
	# Ben: „Mit neuem Code beitreten“ – alter Tisch ohne Verlassen weg, neuer Gast-Tisch mit dem Link
	var old_ct := b.ct()
	old_ct.suspend()
	var ct := _dev_client(b)
	ct.backup_path = b.path
	b.sw.attach(ct)                          # der HostSwitch zieht mit (wie der Tisch nach JoinScreen)
	garbage.append(old_ct)
	_listen(b, ct)
	ct.join(str(at.session.online_info().link), 0, "Ben")
	check(not ct.backup.is_empty() and str(ct.backup.gid) == at.gid, "0: Bens Sicherung geladen (Raum egal)")
	check(wait_until(func(): return ct.connection_state() == "open" and ct.local_seat() == seats.Ben, 6000),
		"0: Ben per bk_token auf seinem Platz (%d)" % ct.local_seat())
	check(bool(at.game.connected[seats.Ben]) and at.session.waiting_ids().is_empty(), "0: Ben verbunden, nicht auf der Warteliste")
	_clear()


# ---------- 1 ----------

func _old_room_file() -> void:
	var h := host_dev("Hanna", H_PORT)
	cfg(h)
	var link := str(h.ht().session.online_info().link)
	var a := guest_dev("Anna", link, A_PORT)
	cfg(a)
	_start(h, [a])
	a.sw.automatic = false
	var code := room_code()
	var gen0 := h.ht().gen
	var epoch0 := h.ht().epoch
	kill_closed(h)
	check(wait_until(func(): return a.sw.state == "waiting", 6000), "1: Anna vermisst Hanna (Vermittler hat das Schließen gesehen)")
	relay.advance(relay.core.grace_ms + 1000)
	check(not relay.core.rooms.has(code), "1: Raum gelöscht")
	# Hannas Datei: Raum älter als 24 h, Stand frisch
	var d := MatchSnapshot.read(h.path)
	var now := wall() / 1000
	d.saved_unix = now
	d.online.created_unix = now - 25 * 3600
	MatchSnapshot.write(h.path, d)
	check(not MatchSnapshot.resumable(d, now) and MatchSnapshot.resumable(d, now, true), "1: nur ohne Raumalter fortsetzbar")
	var saved := HostSwitch.saved_offer(h.path, now)
	check(not saved.is_empty(), "1: saved_offer bietet die Datei an")
	drop_dev(h)
	var h2 := menu_dev(h)
	check(h2.sw.resume_saved(saved) == OK, "1: resume_saved")
	check(wait_until(func(): return h2.sw.state == "expired", 6000), "1: Raum abgelaufen (%s)" % h2.sw.state)
	check(h2.sw.can_new_room() and h2.sw.resume_new_room(), "1: In neuem Raum fortsetzen")
	check(wait_until(func(): return h2.ht() != null, 6000), "1: Hanna führt (%s)" % h2.sw.state)
	var nh := h2.ht()
	check(nh.gen == gen0 and nh.epoch == epoch0 and str(nh.session.online_info().room) != code, "1: eigener Zweig im neuen Raum")
	_clear()


# ---------- 2 ----------

func _menu_wlan() -> void:
	# a) Hanna führt noch: Anna findet sie per Suche
	var h := host_dev("Hanna", H_PORT, false, H_PORT)
	cfg(h)
	h.ht().hotspot_check = func() -> bool: return true
	var a := lan_guest("Anna", H_PORT, A_PORT)
	cfg(a)
	_start(h, [a])
	var seat_a := a.ct().local_seat()
	var gen0 := h.ht().gen
	var epoch0 := h.ht().epoch
	drop_dev(a)                               # Annas App startet neu
	var saved := HostSwitch.saved_offer(a.path, wall() / 1000)
	check(not saved.is_empty() and str(saved.role) == "guest" and (saved.online as Dictionary).is_empty(), "2a: WLAN-Gast-Datei wird angeboten")
	var a2 := menu_dev(a)
	var asked: Array = []
	a2.sw.confirm_needed.connect(func(info: Dictionary) -> void: asked.append(info))
	check(a2.sw.resume_saved(saved) == OK and a2.sw.state == "resuming", "2a: resume_saved sucht zuerst")
	check(wait_until(func(): return a2.ct() != null and a2.ct().connection_state() == "open", 6000), "2a: Anna spielt als Gast bei Hanna (%s)" % a2.sw.state)
	check(wait_until(func(): return a2.ct().local_seat() == seat_a, 3000) and asked.is_empty() and a2.sw.takeovers == 0,
		"2a: ohne Rückfrage auf ihrem Platz (%d)" % a2.ct().local_seat())
	# b) Hanna ist weg: Anna (Gast-Datei) findet niemanden → Rückfrage → führt (gen + 1)
	play(2)
	check(wait_until(func(): return a2.ct().backup_current()), "2b: Annas Sicherung aktuell")
	a2.sw.automatic = false
	kill_lan_closed(h)
	pump(200)
	drop_dev(a2)
	var a3 := menu_dev(a)
	asked.clear()
	a3.sw.confirm_needed.connect(func(info: Dictionary) -> void: asked.append(info))
	check(a3.sw.resume_saved(HostSwitch.saved_offer(a.path, wall() / 1000)) == OK, "2b: resume_saved")
	check(wait_until(func(): return not asked.is_empty(), 6000), "2b: Rückfrage (%s)" % a3.sw.state)
	check(str(asked[0].get("role", "")) == "guest" and not bool(asked[0].get("ap", true)), "2b: Rückfrage Gast-Datei (%s)" % str(asked))
	# Gegenprüfung 1.6.2: Port belegt – das Eröffnen scheitert, expired mit eigener Meldung (nicht „Der Online-Raum ist abgelaufen …“)
	var blocker := TCPServer.new()
	check(blocker.listen(A_PORT) == OK, "2b: Port %d belegt (Test)" % A_PORT)
	a3.sw.confirm_resume(true)
	check(wait_until(func(): return a3.sw.state == "expired", 3000), "2b: Eröffnen scheitert → expired (%s)" % a3.sw.state)
	check(a3.sw.last_error == "Das Spiel ließ sich gerade nicht eröffnen. Bitte noch einmal versuchen." and not a3.sw.can_new_room()
		and a3.ht() == null, "2b: eigene Meldung, kein neuer Raum, kein Gastgeber (%s)" % a3.sw.last_error)
	blocker.stop()
	asked.clear()
	check(a3.sw.resume_saved(HostSwitch.saved_offer(a.path, wall() / 1000)) == OK, "2b: erneut fortsetzen")
	check(wait_until(func(): return not asked.is_empty(), 6000), "2b: Rückfrage erneut (%s)" % a3.sw.state)
	check(a3.sw.last_error == "", "2b: Meldung zurückgesetzt")
	a3.sw.confirm_resume(true)
	check(wait_until(func(): return a3.ht() != null, 6000), "2b: Anna führt (%s)" % a3.sw.state)
	check(a3.ht().gen == gen0 + 1 and a3.ht().host_seat == seat_a, "2b: gen + 1 auf Annas Platz")
	check(int(opened.get("Anna", 0)) == 1, "2b: Spiel-WLAN der Partie weg → Anna öffnet ein eigenes")
	# c) Hannas eigene Datei mit Spiel-WLAN, niemand antwortet (Annas Tisch ist schon weg): Rückfrage mit ap → eigener Zweig
	drop_dev(a3)
	var h2 := menu_dev(h)
	devs.erase(h)
	garbage.append(h.src())
	asked.clear()
	h2.sw.confirm_needed.connect(func(info: Dictionary) -> void: asked.append(info))
	var own := HostSwitch.saved_offer(h.path, wall() / 1000)
	check(not own.is_empty() and str(own.role) == "host" and bool(own.wlan.ap), "2c: Hannas Datei mit Spiel-WLAN")
	check(h2.sw.resume_saved(own) == OK, "2c: resume_saved")
	check(wait_until(func(): return not asked.is_empty(), 6000), "2c: Rückfrage trotz frischer Datei (%s)" % h2.sw.state)
	check(bool(asked[0].get("ap", false)) and str(asked[0].get("role", "")) == "host", "2c: Rückfrage mit ap (%s)" % str(asked))
	h2.sw.confirm_resume(true)                # „Spiel-WLAN neu öffnen“
	check(wait_until(func(): return h2.ht() != null, 6000), "2c: Hanna führt (%s)" % h2.sw.state)
	check(h2.ht().gen == gen0 and h2.ht().epoch == epoch0 and int(opened.get("Hanna", 0)) == 1, "2c: eigener Zweig, eigenes Spiel-WLAN")
	_clear()
