extends "res://tests/handover_kit.gd"

# Mau-Mau Flip (Beta 1.6.1, Gastgeber-Übergabe): unerwarteter Ausfall des Gastgebers online (docs/module/uebergabe.md 4.2–4.5, 7) –
# Gastgeber, App-Gäste mit HostSwitch (Wächter) und ein Browser-Gast über den Vermittler-Nachbau (TCP 24943), synchron gepumpt,
# kurze Fristen, Wanduhr einspritzbar (wall_off).
#  0  Fristregel (deadline_for): away vor 4503 bzw. bis AWAY_LINK_MS danach → T_AWAY ab dem away; sonst T_SILENT.
#  1  Still toter Gastgeber: Rang 0 (Anna) übernimmt (gen + 1, gleiche Plätze), Rang 1 (Ben) bleibt Gast; Browser-Gast folgt per
#     4012/Token; Partie läuft weiter. Der alte Gastgeber kommt zurück: vorsichtiges Neuverbinden, Probe als Gast → Abtreten, sitzt als
#     Gast auf seinem Platz. Abstammung: Ben übernimmt nicht noch einmal.
#  2  Gastgeber mit Schließen weg (4503): Rang 0 übernimmt; der alte Gastgeber setzt aus seiner Datei fort (Hauptmenü,
#     resume_saved) und spielt als Gast weiter („… führt das Spiel inzwischen“).
#  3  Frische Probe: Ben (Rang 1), dessen Anmeldung beim toten Gastgeber hängt (der Ersatz kennt die c nicht, ohne Rundumschlag),
#     übernimmt kein zweites Mal – /info host:true, frische Probe bekommt welcome.
#  4  Zwei gleichzeitig: beide übernehmen, einer tritt ab (gleiche gen, andere epoch) – kein Hin und Her.
#  5  Nicht aktueller Gast übernimmt nicht automatisch (Rang 0), Rang 1 schon.
#  6  Gastgeber in einer anderen App: keine Übernahme vor T_AWAY (still und mit 4503 danach).
#  7  Abstammung: Der alte Gastgeber setzt seine eigene Datei fort (gen 1) und verdrängt Anna (gen 2); Anna meldet sich mit hello.bk
#     und bekommt das Spiel per handover own:true zurück (gen 2, gleiche epoch). handover own:true mit fremder Marke → handover_no.
#  8  WLAN-Mitspieler am Tisch: keine Online-Erben (Beta 1.6.2: WLAN-Erben schon), keine Automatik für den Online-Gast; „Spiel als
#     Gastgeber fortsetzen“ mit Warnzeile möglich.
#  9  Hauptmenü „Partie fortsetzen“, niemand antwortet: eigene Datei älter als 5 min → Rückfrage (confirm_needed), danach Fortsetzen
#     als Gastgeber (gen bleibt); jünger → sofort. Gäste ohne Automatik warten und finden zurück.
# 10  Einschwing-Regel: Der still tote Gastgeber hat nach dem letzten bk noch Stände gemacht (seq > parent.seq) und kehrt zurück, während
#     Annas Einschwingzeit läuft. Seine Sicherung wird beim Wiederkommen nicht überschrieben (Abstammung vor dem ersten bk), er bekommt
#     das Spiel per handover own:true zurück und führt mit höherer gen (host_gen + 1) – kein Hin und Her.

const RELAY_PORT := 24943
const H_PORT := 24944
const A_PORT := 24945
const B_PORT := 24946
const C_PORT := 24947
const W_PORT := 24948


func _initialize() -> void:
	rng.seed = 1611
	start_relay(RELAY_PORT)
	var t0 := Time.get_ticks_msec()
	var only := OS.get_environment("NUR")       # einzelne Fälle: NUR=7 (bzw. 1,3)
	var cases := [_deadline_rule, _still_rank_and_return, _closed_and_resume_saved, _fresh_probe, _two_at_once, _not_current, _away,
		_lineage, _wlan_humans, _resume_menu, _settle_newer]
	for i in cases.size():
		if only == "" or str(i) in only.split(","):
			var t1 := Time.get_ticks_msec()
			(cases[i] as Callable).call()
			print("  Fall %d: %d ms" % [i, Time.get_ticks_msec() - t1])
	print("  Dauer %d ms" % (Time.get_ticks_msec() - t0))
	finish()


# ---------- 0 ----------

func _deadline_rule() -> void:
	check(HostSwitch.deadline_for(1000, 0, 0, 700, 4000, 2000) == 1700, "0: still → T_SILENT ab der letzten Nachricht")
	check(HostSwitch.deadline_for(1000, 5000, 0, 700, 4000, 2000) == 5700, "0: 4503 → T_SILENT ab dem 4503")
	check(HostSwitch.deadline_for(1000, 5000, 3000, 700, 4000, 2000) == 7000, "0: away vor 4503 → T_AWAY ab dem away")
	check(HostSwitch.deadline_for(1000, 5000, 6500, 700, 4000, 2000) == 10500, "0: away bis 2 s nach 4503 → T_AWAY ab dem away")
	check(HostSwitch.deadline_for(1000, 5000, 8000, 700, 4000, 2000) == 5700, "0: away später als 2 s nach 4503 → T_SILENT")
	check(HostSwitch.deadline_for(1000, 0, 900, 700, 4000, 2000) == 4900, "0: away ohne 4503 → T_AWAY")


# ---------- Aufbau: Hanna (Gastgeberin), Anna, Ben (App), Wally (Browser), Minka (Computer) ----------

func _table(with_web := true) -> Array:
	var h := host_dev("Hanna", H_PORT)
	var link := str(h.ht().session.online_info().link)
	var code := str(h.ht().session.online_info().room)
	var a := guest_dev("Anna", link, A_PORT)
	var b := guest_dev("Ben", link, B_PORT)
	var w := web_guest("Wally", relay.base_url(), code) if with_web else {}
	check(wait_until(func(): return a.ct().my_id > 0 and b.ct().my_id > 0 and (not with_web or (w.c as NetClient).my_id > 0)), "Gäste angemeldet")
	h.ht().add_bot("Minka")
	h.ht().set_rules(RuleConfig.preset("offiziell"))
	check(h.ht().start(rng.randi_range(1, 9999)), "Start")
	check(wait_until(func(): return a.ct().view_rev > 0 and b.ct().view_rev > 0), "Gäste haben den Stand")
	play(6)
	var ht := h.ht()
	check(wait_until(func(): return a.ct().backup_current() and b.ct().backup_current() and not a.ct().backup.is_empty()), "Sicherungen aktuell")
	check(a.sw.state == "watch" and b.sw.state == "watch", "Wächter scharf (%s, %s)" % [a.sw.state, b.sw.state])
	check(a.sw.rank() == 0 and b.sw.rank() == 1, "Rang Anna 0, Ben 1 (%d, %d)" % [a.sw.rank(), b.sw.rank()])
	check(not ht.is_frozen(), "Tisch läuft")
	return [h, a, b, w]


func _clear() -> void:
	# Alles abbauen für den nächsten Fall (Raum beenden, Dateien weg)
	for wv in webs:
		(wv.c as NetClient).close()
		(wv.c as NetClient).free()
	webs.clear()
	for d in devs:
		var s: TableSource = d.src()
		if s is HostTable and not d.dead:
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
	wall_off = 0
	pump(150)


# ---------- 1 ----------

func _still_rank_and_return() -> void:
	var t := _table()
	var h: Dev = t[0]
	var a: Dev = t[1]
	var b: Dev = t[2]
	var w: Dictionary = t[3]
	var ht := h.ht()
	var code := room_code()
	var seats := {"Anna": a.ct().local_seat(), "Ben": b.ct().local_seat(), "Wally": int((w.view as Dictionary).get("seat", -1))}
	var gen0 := ht.gen
	var hanna_seat := ht.host_seat
	var hanna_token := ht.host_token()
	kill_still(h)
	check(wait_until(func(): return a.sw.takeovers == 1, 8000), "1: Anna (Rang 0) übernimmt (Zustand %s)" % a.sw.state)
	var at := a.ht()
	check(at != null and at.gen == gen0 + 1 and at.host_seat == seats.Anna, "1: Anna führt auf ihrem Platz, gen + 1")
	check(a.swaps.size() == 1 and str(a.swaps[0][1]) == I18n.t("Du bist jetzt Gastgeber. Bitte lass die App offen."), "1: Hinweis „Du bist jetzt Gastgeber …“")
	check(wait_until(func(): return b.ct() != null and b.ct().connection_state() == "open" and b.ct().host_name() == "Anna", 6000), "1: Ben bleibt Gast, jetzt bei Anna")
	check(b.sw.takeovers == 0, "1: Ben übernimmt nicht")
	check(wait_until(func(): return (w.c as NetClient).state == "open" and (w.c as NetClient).host_name == "Anna", 6000), "1: Browser-Gast folgt per 4012 mit Token")
	check(b.ct().local_seat() == seats.Ben and int((w.view as Dictionary).get("seat", -1)) == seats.Wally, "1: gleiche Plätze")
	check(wait_until(func(): return not at.is_settling(), 3000), "1: Einschwingzeit vorbei")
	check(b.inbox.filter(func(m): return str(m.get("t", "")) == "notice" and JSON.stringify(m.get("lt", [])).contains("führt das Spiel weiter")).size() == 1,
		"1: Meldung „%s führt das Spiel weiter“ an alle")
	check(count(w.inbox, "bk") == 0 and count(w.inbox, "alive") == 0 and count(w.inbox, "handover") == 0, "1: Browser bekommt nie bk/alive/handover")
	check(count(w.inbox, "bye") == 0 and (w.closed as Array).is_empty(), "1: kein bye")
	at.substitute_bot(hanna_seat)            # Hanna ist weg: Computer übernimmt (sonst wartet die Partie an ihrem Zug)
	var rev := at.rev
	play(6)
	check(at.rev > rev, "1: Partie läuft weiter")
	check(wait_until(func(): return int(b.ct().backup.get("gen", 0)) == at.gen and b.ct().backup_current()), "1: Bens Sicherung folgt Anna (gen %d)" % at.gen)
	# --- Hanna kommt zurück: vorsichtiges Neuverbinden, Probe als Gast → abtreten
	h.dead = false
	ht.session.relay._lost("Test: zurück", 0)
	check(wait_until(func(): return h.ct() != null and h.ct().connection_state() == "open", 8000), "1: Hanna wird Gast (Zustand %s)" % h.sw.state)
	check(h.swaps.size() == 1 and str(h.swaps[0][0]) == "client" and str(h.swaps[0][1]).contains("Anna"), "1: Hinweis „Gastgeber ist Anna“")
	check(wait_until(func(): return h.ct().local_seat() == hanna_seat and bool(at.game.connected[hanna_seat]), 4000), "1: Hanna auf ihrem Platz")
	check(seat_of_token(at, hanna_token) == hanna_seat, "1: Hannas Token bleibt an ihrem Platz")
	check(relay.core.rooms.has(code), "1: Raum besteht")
	check(wait_until(func(): return int(h.ct().backup.get("gen", 0)) == at.gen, 4000), "1: Hannas Datei folgt Anna (gen ≥)")
	check(str(MatchSnapshot.read(h.path).get("role", "")) == "guest", "1: Hannas Datei role guest")
	pump(600)
	check(a.sw.takeovers == 1 and b.sw.takeovers == 0 and h.ct() != null and a.ht() == at, "1: keine weitere Übernahme")
	check(int(relay.stats().get("rate_dropped", 0)) == 0, "1: Vermittler verwarf keine Rahmen (Rundumschlag im Budget)")
	_clear()


# ---------- 2 ----------

func _closed_and_resume_saved() -> void:
	var t := _table()
	var h: Dev = t[0]
	var a: Dev = t[1]
	var b: Dev = t[2]
	var w: Dictionary = t[3]
	var hanna_seat := h.ht().host_seat
	kill_closed(h)
	check(wait_until(func(): return a.sw.takeovers == 1, 8000), "2: nach 4503 übernimmt Anna (Zustand %s)" % a.sw.state)
	check(wait_until(func(): return b.ct() != null and b.ct().connection_state() == "open" and b.ct().host_name() == "Anna", 6000), "2: Ben folgt")
	check(wait_until(func(): return (w.c as NetClient).state == "open" and (w.c as NetClient).host_name == "Anna", 6000), "2: Browser-Gast folgt")
	check(b.sw.takeovers == 0, "2: Ben übernimmt nicht")
	# Hanna setzt aus ihrer Datei fort (Hauptmenü): antwortet ein Gastgeber, spielt sie als Gast weiter
	var saved := HostSwitch.saved_offer(h.path, wall() / 1000)
	check(not saved.is_empty() and str(saved.role) == "host", "2: Hannas Datei wird angeboten")
	var old: HostTable = h.ht()
	devs.erase(h)
	garbage.append(old)
	var h2 := Dev.new()
	h2.name = "Hanna"
	h2.path = h.path
	h2.port = H_PORT
	h2.sw = HostSwitch.new()
	_config(h2)
	devs.append(h2)
	check(h2.sw.resume_saved(saved) == OK, "2: resume_saved")
	check(wait_until(func(): return h2.ct() != null, 6000), "2: Hanna spielt als Gast weiter (Zustand %s)" % h2.sw.state)
	check(str(h2.swaps[0][1]) == I18n.t("%s führt das Spiel inzwischen. Du spielst als Gast weiter.") % "Anna", "2: Hinweis „Anna führt das Spiel inzwischen“")
	check(wait_until(func(): return h2.ct().local_seat() == hanna_seat, 4000), "2: auf ihrem Platz")
	check(a.ht() != null and a.sw.takeovers == 1, "2: Anna bleibt Gastgeberin")
	_clear()


# ---------- 3 ----------

func _fresh_probe() -> void:
	var t := _table(false)
	var h: Dev = t[0]
	var a: Dev = t[1]
	var b: Dev = t[2]
	b.sw.t_step_ms = 2000
	# Annas Übernahme ohne Rundumschlag: Bens neue Anmeldung beim toten Gastgeber bleibt beim Ersatz unbekannt
	a.sw.state_changed.connect(func(st: String) -> void:
		if st == "taking":
			var r: NetRelayHost = (a.sw._new as HostTable).session.relay
			r.sweep_extra = 0)
	var saw_check := [false]
	b.sw.state_changed.connect(func(st: String) -> void:
		if st == "checking":
			saw_check[0] = true)
	var welcomes := b.ct().client.welcomes
	kill_still(h)
	check(wait_until(func(): return b.sw.state == "waiting" and b.sw.countdown_ms() > 0, 6000), "3: Ben wartet mit Rang 1 (%s)" % b.sw.state)
	check(wait_until(func(): return a.sw.takeovers == 1, 6000), "3: Anna übernimmt")
	check(b.ct().client.welcomes == welcomes and b.sw.state == "waiting" and not saw_check[0], "3: Bens Anmeldung beim toten Gastgeber bleibt unbeantwortet")
	check(wait_until(func(): return b.sw.state == "watch" and b.ct().connection_state() == "open", 6000), "3: Ben findet Anna (Zustand %s)" % b.sw.state)
	check(saw_check[0] and bool(b.ct().client.info_result.get("host", false)), "3: /info meldet einen Gastgeber, frische Probe")
	check(b.sw.takeovers == 0, "3: keine zweite Übernahme")
	check(b.ct().host_name() == "Anna", "3: Gastgeberin Anna")
	_clear()


# ---------- 4 ----------

func _two_at_once() -> void:
	var t := _table(false)
	var h: Dev = t[0]
	var a: Dev = t[1]
	var b: Dev = t[2]
	var gen0 := h.ht().gen
	kill_closed(h)
	check(wait_until(func(): return a.ct().client.host_away_wall > 0 and b.ct().client.host_away_wall > 0), "4: beide sehen 4503")
	pump(50)
	a.sw._take_over_backup(a.ct())       # beide gleichzeitig (wie „Spiel als Gastgeber fortsetzen“ auf zwei Geräten)
	b.sw._take_over_backup(b.ct())
	check(wait_until(func(): return (a.ht() != null) != (b.ht() != null) and (a.ct() == null or a.ct().connection_state() == "open") \
		and (b.ct() == null or b.ct().connection_state() == "open"), 8000), "4: genau einer führt (%s/%s)" % [a.sw.state, b.sw.state])
	var host: Dev = a if a.ht() != null else b
	var guest: Dev = b if host == a else a
	check(host.ht().gen == gen0 + 1, "4: Gastgeber gen + 1")
	var swaps := [host.swaps.size(), guest.swaps.size()]
	pump(1500)
	check(host.ht() != null and guest.ct() != null and host.swaps.size() == swaps[0] and guest.swaps.size() == swaps[1], "4: kein Hin und Her")
	check(not host.ht().is_frozen() and host.ht().handover_seat() < 0, "4: keine Rückgabe per handover")
	check(guest.ct().host_name() == host.name, "4: der andere spielt als Gast")
	_clear()


# ---------- 5 ----------

func _not_current() -> void:
	var t := _table(false)
	var h: Dev = t[0]
	var a: Dev = t[1]
	var b: Dev = t[2]
	kill_still(h)
	pump(30)
	a.ct().head = [int(a.ct().head[0]), str(a.ct().head[1]), int(a.ct().head[2]) + 1]   # Anna hat eine Sicherung verpasst
	check(not a.sw.is_current() and b.sw.is_current(), "5: Anna nicht aktuell, Ben schon")
	check(wait_until(func(): return b.sw.takeovers == 1, 9000), "5: Ben (Rang 1) übernimmt")
	check(a.sw.takeovers == 0, "5: Anna übernimmt nicht")
	check(wait_until(func(): return a.ct() != null and a.ct().connection_state() == "open" and a.ct().host_name() == "Ben", 6000), "5: Anna spielt bei Ben weiter")
	_clear()


# ---------- 6 ----------

func _away() -> void:
	# a) Gastgeber in einer anderen App, Socket hängt still
	var t := _table(false)
	var h: Dev = t[0]
	var a: Dev = t[1]
	var b: Dev = t[2]
	h.ht().session.app_paused()
	check(wait_until(func(): return a.ct().host_away() and b.ct().host_away()), "6a: Gäste sehen away")
	kill_still(h)
	pump(t_silent * 3)
	check(a.sw.state == "watch" and a.sw.takeovers == 0, "6a: keine Übernahme nach T_SILENT (%s)" % a.sw.state)
	wall_off += t_away
	check(wait_until(func(): return a.sw.takeovers == 1, 8000), "6a: nach T_AWAY übernimmt Anna")
	_clear()
	# b) away, dann Socket zu (4503)
	t = _table(false)
	h = t[0]
	a = t[1]
	b = t[2]
	h.ht().session.app_paused()
	check(wait_until(func(): return a.ct().host_away() and b.ct().host_away()), "6b: Gäste sehen away")
	kill_closed(h)
	check(wait_until(func(): return a.ct().client.host_away_wall > 0), "6b: 4503")
	pump(t_silent * 3)
	check(a.sw.state == "watch" and a.sw.takeovers == 0 and b.sw.takeovers == 0, "6b: keine Übernahme vor T_AWAY ab dem away (%s)" % a.sw.state)
	wall_off += t_away
	check(wait_until(func(): return a.sw.takeovers == 1, 8000), "6b: nach T_AWAY übernimmt Anna")
	_clear()


# ---------- 7 ----------

func _lineage() -> void:
	var t := _table(false)
	var h: Dev = t[0]
	var a: Dev = t[1]
	var b: Dev = t[2]
	var own := MatchSnapshot.read(h.path)
	check(not own.is_empty() and int(own.gen) == 1, "7: Hannas Datei gen 1")
	kill_closed(h)
	check(wait_until(func(): return a.sw.takeovers == 1, 8000), "7: Anna übernimmt")
	var at := a.ht()
	var gen_a := at.gen
	var epoch_a := at.epoch
	check(wait_until(func(): return b.ct() != null and b.ct().connection_state() == "open" and not at.is_settling(), 6000), "7: Ben bei Anna")
	at.substitute_bot(h.ht().host_seat)     # Hanna ist weg: Computer übernimmt (sonst wartet die Partie an ihrem Zug)
	play(3)
	# Hanna setzt ihre eigene Datei fort (eigener Zweig, gen 1) und verdrängt Anna
	var old: HostTable = h.ht()
	devs.erase(h)
	garbage.append(old)
	var h2 := Dev.new()
	h2.name = "Hanna"
	h2.path = h.path
	h2.port = H_PORT
	var nh := make_host()
	nh.save_path = h2.path
	check(nh.resume(MatchSnapshot.read(h.path), -1, W_PORT, W_PORT) == OK and nh.gen == 1, "7: Hanna setzt fort (gen 1)")
	h2.sw = HostSwitch.ensure(nh)
	h2.last_src = nh
	_config(h2)
	devs.append(h2)
	if OS.get_environment("DEBUG_UEBERGABE") != "":
		a.sw.state_changed.connect(func(st): print("  A: ", st, " ", a.sw.last_error))
		h2.sw.state_changed.connect(func(st): print("  H2: ", st))
		nh.notice.connect(func(n): print("  nh: ", n))
	check(wait_until(func(): return a.ct() != null, 8000), "7: Anna verdrängt (4000) und meldet sich als Gast (Zustand %s)" % a.sw.state)
	check(wait_until(func(): return a.sw.takeovers == 2 and a.ht() != null, 8000), "7: Anna bekommt das Spiel per handover own:true zurück (%s)" % a.sw.state)
	check(a.ht().gen == gen_a and a.ht().epoch == epoch_a, "7: eigener Zweig – gen %d und epoch bleiben" % a.ht().gen)
	check(wait_until(func(): return h2.ct() != null and h2.ct().connection_state() == "open", 8000), "7: Hanna tritt ab und spielt als Gast (%s)" % h2.sw.state)
	check(wait_until(func(): return b.ct() != null and b.ct().host_name() == "Anna" and b.ct().connection_state() == "open", 6000), "7: Ben wieder bei Anna")
	pump(800)
	check(a.ht() != null and h2.ct() != null and a.sw.takeovers == 2, "7: kein Hin und Her")
	# handover own:true mit einer Marke, die Ben nicht hat → handover_no, Anna taut sofort auf
	var ah := a.ht()
	var bseat := b.ct().local_seat()
	var frozen_at := Time.get_ticks_msec()
	check(ah._begin_handover(bseat, NetProtocol.make_handover(ah.gid, [9, "abcd", 1], "", 3000), true) and ah.is_frozen(), "7: own:true an Ben, eingefroren")
	check(wait_until(func(): return not ah.is_frozen(), 2000) and Time.get_ticks_msec() - frozen_at < ah.handover_timeout_ms, "7: handover_no taut sofort auf")
	check(b.ct() != null and b.sw.takeovers == 0, "7: Ben übernimmt nicht")
	_clear()


# ---------- 8 ----------

func _wlan_humans() -> void:
	var h := host_dev("Hanna", H_PORT)
	var link := str(h.ht().session.online_info().link)
	var a := guest_dev("Anna", link, A_PORT)
	var k := guest_dev("Kim", "127.0.0.1", C_PORT, true, H_PORT)
	check(wait_until(func(): return a.ct().my_id > 0 and k.ct().my_id > 0), "8: Anna online, Kim im WLAN")
	h.ht().add_bot("Minka")
	check(h.ht().start(77), "8: Start")
	play(4)
	check(wait_until(func(): return a.ct().backup_current()), "8: Anna hat eine aktuelle Sicherung")
	# Beta 1.6.2 (10.3, Gegenprüfung): WLAN-Erben ja (Kim), Online-Erben nicht, solange WLAN-Mitspieler am Tisch sitzen – fällt bei
	# Hanna nur das Internet aus, merkt Kim nichts (der Server-Thread antwortet); Anna eröffnete sonst ein zweites Spiel
	var heirs: Array = a.ct().backup.heirs
	check(heirs == [k.ct().client.token] and bool(a.ct().backup.wlan_humans), "8: Erben nur Kim (WLAN), Anna (online) nicht (%s)" % str(heirs))
	kill_still(h)                            # nur das Vermittler-Socket hängt: Kim im WLAN merkt nichts (der Server-Thread antwortet)
	check(wait_until(func(): return a.sw.state == "waiting", 6000), "8: Anna merkt das Fehlen")
	check(a.sw.rank() < 0 and a.sw.countdown_ms() < 0 and a.sw.can_continue(), "8: Anna ohne Automatik, Knopf möglich")
	var warn := I18n.render(a.sw.continue_warnings())
	check(warn.contains(I18n.t("WLAN-Mitspieler brauchen dann Internet.")), "8: Warnzeile WLAN (1.6.2)")
	pump(t_step + 500)
	check(a.sw.takeovers == 0, "8: keine automatische Übernahme")
	check(a.sw.continue_as_host(), "8: von Hand fortsetzen")
	check(wait_until(func(): return a.sw.takeovers == 1, 6000), "8: Anna führt (von Hand)")
	_clear()


# ---------- 9 ----------

func _menu_dev(old: Dev) -> Dev:
	var d := Dev.new()
	d.name = old.name
	d.path = old.path
	d.port = old.port
	d.sw = HostSwitch.new()
	_config(d)
	devs.append(d)
	return d


func _resume_menu() -> void:
	var t := _table(false)
	var h: Dev = t[0]
	var a: Dev = t[1]
	var b: Dev = t[2]
	a.sw.automatic = false
	b.sw.automatic = false
	var gen0 := h.ht().gen
	var epoch0 := h.ht().epoch
	kill_closed(h)
	check(wait_until(func(): return a.sw.state == "waiting" and b.sw.state == "waiting", 6000), "9: Gäste merken das Fehlen, keine Automatik")
	# Hannas App startet neu (alter Tisch weg, Port frei); Datei ist „6 min“ alt
	devs.erase(h)
	h.ht().free()
	var saved := HostSwitch.saved_offer(h.path, wall() / 1000)
	check(not saved.is_empty(), "9: Datei wird angeboten")
	var h2 := _menu_dev(h)
	var asked: Array = []
	h2.sw.confirm_needed.connect(func(info: Dictionary) -> void: asked.append(info))
	wall_off += 6 * 60 * 1000
	check(h2.sw.resume_saved(saved) == OK, "9: resume_saved")
	check(wait_until(func(): return not asked.is_empty(), 6000), "9: Rückfrage (Zustand %s)" % h2.sw.state)
	check(int(asked[0].get("age_min", 0)) >= 5 and str(asked[0].get("role", "")) == "host", "9: Rückfrage mit Alter (%s)" % str(asked))
	h2.sw.confirm_resume(true)
	check(wait_until(func(): return h2.ht() != null, 6000), "9: Hanna führt wieder (%s)" % h2.sw.state)
	check(h2.ht().gen == gen0 and h2.ht().epoch == epoch0, "9: eigener Zweig – gen und epoch bleiben")
	check(wait_until(func(): return a.ct().host_name() == "Hanna" and a.ct().connection_state() == "open" and a.sw.state == "watch" \
		and b.ct().connection_state() == "open", 6000), "9: Gäste finden zurück (%s/%s)" % [a.sw.state, b.sw.state])
	# … noch einmal, Datei frisch: ohne Rückfrage
	wall_off = 0
	check(wait_until(func(): return not h2.ht().is_settling(), 3000), "9: Einschwingzeit vorbei")
	play(2)
	kill_closed(h2)
	check(wait_until(func(): return a.sw.state == "waiting", 6000), "9: Gäste merken das Fehlen")
	devs.erase(h2)
	h2.ht().free()
	var h3 := _menu_dev(h)
	asked.clear()
	h3.sw.confirm_needed.connect(func(info: Dictionary) -> void: asked.append(info))
	check(h3.sw.resume_saved(HostSwitch.saved_offer(h.path, wall() / 1000)) == OK, "9: resume_saved (frisch)")
	check(wait_until(func(): return h3.ht() != null, 6000) and asked.is_empty(), "9: frische eigene Datei ohne Rückfrage (%s)" % h3.sw.state)
	check(wait_until(func(): return a.ct().connection_state() == "open" and a.ct().host_name() == "Hanna", 6000), "9: Anna wieder dabei")
	_clear()


# ---------- 10 ----------

func _settle_newer() -> void:
	var t := _table(false)
	var h: Dev = t[0]
	var a: Dev = t[1]
	var b: Dev = t[2]
	var ht := h.ht()
	var gen0 := ht.gen
	var epoch0 := ht.epoch
	b.dead = true                            # Ben kommt erst später zurück: Annas Einschwingzeit läuft so lange
	a.sw.host_setup = func(x: HostTable) -> void: x.settle_max_ms = 10000
	kill_still(h)
	# Hannas Tisch läuft am halboffenen Socket noch ein Stück weiter: Stände, die niemand mehr bekommt (eigene Datei schon)
	ht._changed([])
	ht._changed([])
	var seq_h := ht.seq
	check(seq_h > int(a.ct().backup.seq), "10: Hanna ist weiter als Annas Sicherung (%d > %d)" % [seq_h, int(a.ct().backup.seq)])
	check(wait_until(func(): return a.sw.takeovers == 1, 8000), "10: Anna übernimmt (%s)" % a.sw.state)
	var at := a.ht()
	check(at != null and at.gen == gen0 + 1 and at.is_settling() and int(at.parent[0]) == gen0 and str(at.parent[1]) == epoch0 \
		and int(at.parent[2]) < seq_h, "10: Anna gen + 1, Einschwingzeit läuft (parent %s)" % (str(at.parent) if at != null else "?"))
	# Hanna kommt zurück (vorsichtiges Neuverbinden → abtreten → Gast mit hello.bk ihres neueren Stands)
	h.dead = false
	ht.session.relay._lost("Test: zurück", 0)
	check(wait_until(func(): return h.ht() != null and h.sw.takeovers == 1, 10000), "10: Hanna bekommt das Spiel per own:true zurück (%s)" % h.sw.state)
	var nh := h.ht()
	if nh == null:
		_clear()
		return
	check(nh.gen == gen0 + 2 and nh.parent == [gen0, epoch0, seq_h] and nh.epoch != epoch0 and nh.seq >= seq_h,
		"10: Hannas Stand, gen über Annas (gen %d, parent %s)" % [nh.gen, str(nh.parent)])
	check(wait_until(func(): return a.ct() != null and a.ct().connection_state() == "open" and a.ct().host_name() == "Hanna", 8000),
		"10: Anna tritt ab und spielt bei Hanna (%s)" % a.sw.state)
	b.dead = false
	check(wait_until(func(): return b.ct() != null and b.ct().connection_state() == "open" and b.ct().host_name() == "Hanna", 8000), "10: Ben bei Hanna")
	check(wait_until(func(): return a.ct() != null and int(a.ct().backup.get("gen", 0)) == nh.gen, 4000), "10: Annas Sicherung folgt Hanna (gen %d)" % nh.gen)
	pump(1000)
	check(h.ht() == nh and a.ct() != null and h.sw.takeovers == 1 and a.sw.takeovers == 1 and b.sw.takeovers == 0 and not nh.is_frozen(),
		"10: kein Hin und Her")
	_clear()
