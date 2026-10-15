extends "res://tests/handover_kit.gd"

# Mau-Mau Flip (Beta 1.6.2, Gastgeber-Übergabe im WLAN, docs/module/uebergabe.md 10.4, 10.5, 10.7, 10.8, 10.11, 10.16): Gast-Wächter
# HostSwitch ohne Vermittler – Gastgeberin Hanna, App-Gäste Anna und Ben (HostSwitch, Sicherung), Computer Minka; alles auf 127.0.0.1
# im selben Prozess (TCP 24907–24910, Suche UDP 24907–24911 über ports/probe_local), synchron gepumpt, kurze Fristen, Wanduhr
# einspritzbar (wall_off). Einzelne Fälle: NUR=3 (bzw. 1,4).
#  0  Ausfall mit geschlossenem Server (Verbindung verweigert): Rang 0 (Anna) übernimmt nach T_SILENT (gen + 1, gleiche Plätze);
#     Rang 1 (Ben) findet sie per Suche (gid, gen ≥) und folgt (move_to → watch), übernimmt nicht; Partie läuft weiter.
#  1  Ausfall still (alle Verbindungen stumm, Hauptschleife steht): ebenso.
#  2  Annas Sicherung nicht aktuell: keine Automatik für sie, Ben (Rang 1) übernimmt, Anna folgt per Suche.
#  3  Gastgeberin in einer anderen App: vor T_AWAY nichts, danach übernimmt Anna.
#  4  lan_ok falsch (eingespritzt: eigenes Netz weg): niemand übernimmt, „Spiel als Gastgeber fortsetzen“ bleibt möglich.
#  5  Spiel-WLAN der Gastgeberin (wlan.ap) und ihr Netz ist weg: Rangfolge Geräte mit ap.ok zuerst (Ben vor Anna); nur Ben (Rang 0)
#     übernimmt nach t_step mit Countdown (Funkloch-Schutz) – wifi_release vor dem Server, danach eigenes Spiel-WLAN (auto_open,
#     Hinweis „… Öffne das Spiel-WLAN …“); Anna geht nach scan (Namen: Hanna, Ben), übernimmt nicht und folgt Ben, sobald die Suche
#     ihn findet.
#  6  Übernahme im fremden Spiel-WLAN: Hanna (führt das Netz) nur in einer anderen App → Anna übernimmt nach T_AWAY als Teilnehmerin;
#     der neue Stand behält ap_seat = Hannas Platz. Fällt dann Annas Netz für Ben weg, geht Ben nach scan mit Annas Namen und
#     übernimmt nicht.
#  7  Geplante Übergabe lan (Ziel Anna): resume, handover_ok, Abtreten Hannas als Gast bei Anna (step_target lan), Ben folgt dem move.
#  8  Geplante Übergabe qr (Hannas Spiel-WLAN): Anna gibt handover_ok{qr} vor wifi_release und Server, öffnet ein eigenes Spiel-WLAN;
#     Hanna schließt ihres (wifi_stop) und geht nach scan, Ben ebenso (move qr) – beide finden Anna per Suche und folgen.
#  9  Mehrheit gewinnt (Gastgeber-Wächter): Anna hat einen Aussetzer und übernimmt allein, Hanna spielt mit Ben weiter. Beim
#     Wiedersehen tritt Anna ab (weniger verbundene Menschen) und spielt als Gast bei Hanna; Hanna hebt ihre gen über Annas, die Züge
#     der Mehrheit bleiben erhalten, kein Zurückholen per Abstammung.
# 10  Zwei übernehmen gleichzeitig (gleiches conn, gleiche gen, andere epoch): genau einer tritt ab, kein Hin und Her.
# 11  Nachtest 1.6.2: nach der geplanten Übergabe qr wartet die abgetretene Gastgeberin (handed_off, kein „Spiel als Gastgeber
#     fortsetzen“), Ben in scan nach move qr unverändert; nach handoff_wait_ms gilt scan wie nach einem Ausfall.

const H_PORT := 24907
const A_PORT := 24908
const B_PORT := 24909
const DEAD_UDP := 24911               # niemand lauscht (Fall 9: Annas Suche ins Leere)
const UDPS := [24907, 24908, 24909, 24910]

var released := {}                    # Gerät -> Anzahl wifi_release
var stopped := {}                     # Gerät -> Anzahl wifi_stop
var opened := {}                      # Gerät -> Anzahl auto_open
var order := {}                       # Gerät -> Reihenfolge ["release", "server"]
var states := {}                      # Gerät -> Zustände des HostSwitch


func _initialize() -> void:
	rng.seed = 1622
	t_silent = 500
	t_step = 1500
	probe = 500
	within = 3000
	disc_ports = UDPS.duplicate()      # ohne Vermittler (finish() kommt ohne aus)
	var t0 := Time.get_ticks_msec()
	var only := OS.get_environment("NUR")
	var cases := [_closed, _still, _not_current, _away, _no_lan, _ap_lost, _foreign_ap, _planned_lan, _planned_qr, _majority, _two_at_once, _planned_qr_wait]
	for i in cases.size():
		if only == "" or str(i) in only.split(","):
			var t1 := Time.get_ticks_msec()
			(cases[i] as Callable).call()
			print("  Fall %d: %d ms" % [i, Time.get_ticks_msec() - t1])
	print("  Dauer %d ms" % (Time.get_ticks_msec() - t0))
	finish()


# ---------- Aufbau (Kit: host_dev ohne Raum, lan_guest, kill_lan_closed/still) ----------

func disc(n: NetDiscovery, ports := UDPS) -> void:
	n.use_broadcast = false
	n.probe_local = true
	n.ports = ports.duplicate()
	n.query_interval_ms = 100
	n.refresh_targets_ms = 200
	n.expire_ms = 1500


# Zusätzlich zum Kit: eigene Suche des HostSwitch (Unicast an 127.0.0.1, alle UDP-Ports), schneller Wächter-Scan neuer
# Gastgeber-Tische, Spiel-WLAN-Doubles und Mitschrift (Reihenfolge, Zustände).
func lan_cfg(d: Dev) -> void:
	var sw := d.sw
	sw.lan_search_ms = 300
	sw.menu_search_ms = 600
	sw.discovery_setup = func(n: NetDiscovery) -> void: disc(n)
	sw.host_factory = func() -> HostTable:
		(order[d.name] as Array).append("server")
		var h := _dev_host(d)
		h.scan_ms = 300
		return h
	sw.wifi_release = func() -> void:
		released[d.name] = int(released.get(d.name, 0)) + 1
		(order[d.name] as Array).append("release")
	sw.wifi_stop = func() -> void: stopped[d.name] = int(stopped.get(d.name, 0)) + 1
	sw.auto_open = func(_h: HostTable) -> void: opened[d.name] = int(opened.get(d.name, 0)) + 1
	sw.state_changed.connect(func(st: String) -> void: (states[d.name] as Array).append(st))
	order[d.name] = []
	states[d.name] = []


func lan_host(dev_name: String, port: int, ap := false) -> Dev:
	var d := host_dev(dev_name, port, false, port)
	var h := d.ht()
	if h.session.discovery != null:
		h.session.discovery.scan_ms = 300
	if ap:
		h.hotspot_check = func() -> bool: return true
	lan_cfg(d)
	return d


func lan_dev(dev_name: String, host_port: int, port: int, caps := {}) -> Dev:
	var d := lan_guest(dev_name, host_port, port, true, caps)
	d.disc_port = port
	lan_cfg(d)
	return d


func _table(ap := false, a_caps := {}, b_caps := {}) -> Array:
	var h := lan_host("Hanna", H_PORT, ap)
	var a := lan_dev("Anna", H_PORT, A_PORT, a_caps)
	var b := lan_dev("Ben", H_PORT, B_PORT, b_caps)
	check(wait_until(func(): return a.ct().my_id > 0 and b.ct().my_id > 0), "Gäste angemeldet")
	h.ht().add_bot("Minka")
	h.ht().set_rules(RuleConfig.preset("offiziell"))
	check(h.ht().start(rng.randi_range(1, 9999)), "Start")
	check(wait_until(func(): return a.ct().view_rev > 0 and b.ct().view_rev > 0), "Gäste haben den Stand")
	play(6)
	check(wait_until(func(): return a.ct().backup_current() and b.ct().backup_current() and a.sw.state == "watch" and b.sw.state == "watch"),
		"Sicherungen aktuell, Wächter scharf im WLAN (%s, %s)" % [a.sw.state, b.sw.state])
	return [h, a, b]


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
	released.clear()
	stopped.clear()
	opened.clear()
	order.clear()
	states.clear()
	wall_off = 0
	pump(150)


func seats_of(list: Array) -> Dictionary:
	var out := {}
	for d in list:
		out[d.name] = d.ct().local_seat()
	return out


# ---------- 0 / 1 ----------

func _closed() -> void:
	_rank_follow(false)


func _still() -> void:
	_rank_follow(true)


func _rank_follow(still: bool) -> void:
	var tag := "1" if still else "0"
	var t := _table()
	var h: Dev = t[0]
	var a: Dev = t[1]
	var b: Dev = t[2]
	check(a.sw.rank() == 0 and b.sw.rank() == 1, "%s: Rang Anna 0, Ben 1 (%d, %d)" % [tag, a.sw.rank(), b.sw.rank()])
	var gen0 := h.ht().gen
	var hanna_seat := h.ht().host_seat
	var seats := seats_of([a, b])
	if still:
		kill_lan_still(h)
	else:
		kill_lan_closed(h)
	check(wait_until(func(): return a.sw.takeovers == 1, 8000), "%s: Anna (Rang 0) übernimmt (Zustand %s)" % [tag, a.sw.state])
	var at := a.ht()
	check(at != null and at.gen == gen0 + 1 and at.host_seat == seats.Anna, "%s: Anna führt auf ihrem Platz, gen + 1" % tag)
	check(at != null and at.port() == A_PORT, "%s: Annas Server auf ihrem Port" % tag)
	check(wait_until(func(): return b.ct() != null and b.ct().connection_state() == "open" and b.ct().host_name() == "Anna", 6000),
		"%s: Ben folgt Anna (Zustand %s)" % [tag, b.sw.state])
	check(b.sw.follows >= 1 and b.sw.takeovers == 0, "%s: Ben per Suche gefolgt (%d), keine Übernahme" % [tag, b.sw.follows])
	check(b.ct().port == A_PORT and b.ct().local_seat() == seats.Ben, "%s: Ben auf seinem Platz bei Anna" % tag)
	check(wait_until(func(): return b.sw.state == "watch", 3000), "%s: Bens Wächter wieder scharf (%s)" % [tag, b.sw.state])
	check(not (states.Ben as Array).has("taking"), "%s: Ben hat nie übernommen" % tag)
	if at == null:
		_clear()
		return
	at.substitute_bot(hanna_seat)
	var rev := at.rev
	play(6)
	check(at.rev > rev, "%s: Partie läuft weiter" % tag)
	check(wait_until(func(): return int(b.ct().backup.get("gen", 0)) == at.gen and b.ct().backup_current()), "%s: Bens Sicherung folgt Anna" % tag)
	pump(400)
	check(a.sw.takeovers == 1 and b.sw.takeovers == 0, "%s: keine weitere Übernahme" % tag)
	_clear()


# ---------- 2 ----------

func _not_current() -> void:
	var t := _table()
	var h: Dev = t[0]
	var a: Dev = t[1]
	var b: Dev = t[2]
	kill_lan_closed(h)
	pump(30)
	a.ct().head = [int(a.ct().head[0]), str(a.ct().head[1]), int(a.ct().head[2]) + 1]   # Anna hat eine Sicherung verpasst
	check(not a.sw.is_current() and b.sw.is_current(), "2: Anna nicht aktuell, Ben schon")
	check(wait_until(func(): return b.sw.takeovers == 1, 9000), "2: Ben (Rang 1) übernimmt (%s)" % b.sw.state)
	check(a.sw.takeovers == 0, "2: Anna übernimmt nicht")
	check(wait_until(func(): return a.ct() != null and a.ct().connection_state() == "open" and a.ct().host_name() == "Ben", 6000),
		"2: Anna folgt Ben per Suche (%s)" % a.sw.state)
	_clear()


# ---------- 3 ----------

func _away() -> void:
	var t := _table()
	var h: Dev = t[0]
	var a: Dev = t[1]
	var b: Dev = t[2]
	h.ht().session.app_paused()
	check(wait_until(func(): return a.ct().host_away() and b.ct().host_away()), "3: Gäste sehen away")
	kill_lan_closed(h)
	pump(t_silent * 4)
	check(a.sw.state == "watch" and a.sw.takeovers == 0 and b.sw.takeovers == 0, "3: keine Übernahme vor T_AWAY (%s)" % a.sw.state)
	wall_off += t_away
	check(wait_until(func(): return a.sw.takeovers == 1, 8000), "3: nach T_AWAY übernimmt Anna")
	check(wait_until(func(): return b.ct() != null and b.ct().host_name() == "Anna" and b.ct().connection_state() == "open", 6000), "3: Ben folgt")
	_clear()


# ---------- 4 ----------

func _no_lan() -> void:
	var t := _table()
	var h: Dev = t[0]
	var a: Dev = t[1]
	var b: Dev = t[2]
	for d in [a, b]:
		(d as Dev).sw.net_check = func(_targets: Array) -> bool: return false
	kill_lan_closed(h)
	check(wait_until(func(): return a.sw.state == "missing" and b.sw.state == "missing", 4000), "4: beide vermissen die Gastgeberin")
	check(not a.sw.lan_ok() and not b.sw.lan_ok(), "4: lan_ok falsch")
	pump(t_step + probe)
	check(a.sw.takeovers == 0 and b.sw.takeovers == 0, "4: niemand übernimmt")
	check(a.sw.state == "missing" and a.sw.countdown_ms() < 0, "4: Anna wartet ohne Automatik (%s)" % a.sw.state)
	check(a.sw.can_continue(), "4: von Hand fortsetzen möglich")
	_clear()


# ---------- 5 ----------

func _ap_lost() -> void:
	var t := _table(true, {"ok": false, "perm": false}, {"ok": true, "perm": true})
	var h: Dev = t[0]
	var a: Dev = t[1]
	var b: Dev = t[2]
	var bk: Dictionary = b.ct().backup
	check(bool(bk.wlan.ap) and int(bk.wlan.ap_seat) == h.ht().host_seat, "5: Partie im Spiel-WLAN der Gastgeberin (ap_seat %d)" % int(bk.wlan.ap_seat))
	check(b.sw.rank() == 0 and a.sw.rank() == 1, "5: Ben (kann ein Spiel-WLAN öffnen) vor Anna (%d, %d)" % [b.sw.rank(), a.sw.rank()])
	check(HostSwitch.scan_names_of(bk) == ["Hanna", "Ben"], "5: Namen für scan (%s)" % str(HostSwitch.scan_names_of(bk)))
	for d in [a, b]:
		(d as Dev).sw.net_check = func(_targets: Array) -> bool: return false     # Hannas Spiel-WLAN ist weg
	(order.Ben as Array).clear()
	kill_lan_closed(h)
	# Gegenprüfung 1.6.2: Rang 0 übernimmt nicht sofort (Netz weg kann ein Funkloch sein) – erst nach t_step_ms mit Countdown
	check(wait_until(func(): return b.sw.state == "waiting", 6000), "5: Ben wartet (%s)" % b.sw.state)
	check(b.sw.countdown_ms() > t_step / 2 and b.sw.takeovers == 0, "5: Countdown statt sofortiger Übernahme (%d ms)" % b.sw.countdown_ms())
	check(wait_until(func(): return b.sw.takeovers == 1, 8000), "5: Ben (Rang 0) übernimmt (%s)" % b.sw.state)
	check(int(released.get("Ben", 0)) == 1 and order.Ben == ["release", "server"], "5: wifi_release vor dem Server (%s)" % str(order.Ben))
	check(int(opened.get("Ben", 0)) == 1, "5: Ben öffnet ein eigenes Spiel-WLAN (auto_open)")
	check(str(b.swaps[-1][1]) == I18n.t("Du bist jetzt Gastgeber. Öffne das Spiel-WLAN und lass die anderen den QR-Code scannen."), "5: Hinweis an Ben")
	check((states.Anna as Array).has("scan"), "5: Anna geht nach scan (%s)" % str(states.Anna))
	check(not (states.Anna as Array).has("taking") and a.sw.takeovers == 0, "5: Anna übernimmt nicht")
	check(wait_until(func(): return a.ct() != null and a.ct().connection_state() == "open" and a.ct().host_name() == "Ben", 6000),
		"5: Anna findet Ben (gleiches Ersatz-WLAN) und folgt (%s)" % a.sw.state)
	_clear()
	# scan ohne Fund: Anna bleibt im Zustand scan, Knopf von Hand mit Warnzeile
	t = _table(true, {"ok": false, "perm": false}, {"ok": true, "perm": true})
	h = t[0]
	a = t[1]
	b = t[2]
	a.sw.net_check = func(_targets: Array) -> bool: return false
	b.dead = true                            # Ben ist außer Reichweite (übernimmt hier nicht)
	kill_lan_closed(h)
	check(wait_until(func(): return a.sw.state == "scan", 6000), "5b: Anna im Zustand scan (%s)" % a.sw.state)
	check(a.sw.scan_names() == ["Hanna", "Ben"], "5b: Spiel-WLAN von Hanna weg, neues bei Ben")
	check(a.sw.can_continue() and I18n.render(a.sw.continue_warnings()).contains(I18n.t("Nur wenn %s nicht übernimmt – sonst gibt es zwei Spiele.") % "Ben"),
		"5b: von Hand möglich, mit Warnzeile")
	pump(t_step)
	check(a.sw.state == "scan" and a.sw.takeovers == 0, "5b: keine Übernahme aus scan heraus")
	_clear()


# ---------- 6 ----------

func _foreign_ap() -> void:
	var t := _table(true)
	var h: Dev = t[0]
	var a: Dev = t[1]
	var b: Dev = t[2]
	var hanna_seat := h.ht().host_seat
	h.ht().session.app_paused()
	check(wait_until(func(): return a.ct().host_away() and b.ct().host_away()), "6: Gäste sehen away")
	kill_lan_still(h)                        # Hanna angehalten, ihr Spiel-WLAN besteht (lan_ok wahr)
	pump(t_silent * 3)
	check(a.sw.takeovers == 0, "6: vor T_AWAY nichts")
	wall_off += t_away
	check(wait_until(func(): return a.sw.takeovers == 1, 8000), "6: Anna übernimmt im fremden Spiel-WLAN (%s)" % a.sw.state)
	check(int(released.get("Anna", 0)) == 0 and int(opened.get("Anna", 0)) == 0, "6: kein eigenes Spiel-WLAN (Hannas besteht)")
	check(wait_until(func(): return b.ct() != null and b.ct().connection_state() == "open" and b.ct().host_name() == "Anna", 6000), "6: Ben folgt Anna")
	check(wait_until(func(): return int(b.ct().backup.get("gen", 0)) == a.ht().gen and b.ct().backup_current(), 4000), "6: Bens Sicherung von Anna")
	var w: Dictionary = b.ct().backup.wlan
	check(bool(w.ap) and int(w.ap_seat) == hanna_seat, "6: neuer Stand behält ap_seat = Hannas Platz (%s)" % str(w))
	check(HostSwitch.scan_names_of(b.ct().backup) == ["Hanna", "Anna"], "6: bei Verlust öffnet Anna ein neues")
	# Hannas Netz fällt weg: Ben verliert Anna (eingespritzt), Anna führt weiter und öffnet ein eigenes – Ben scannt
	b.sw.net_check = func(_targets: Array) -> bool: return false
	kill_lan_still(a)
	check(wait_until(func(): return b.sw.state == "scan", 6000), "6: Ben im Zustand scan (%s)" % b.sw.state)
	check(b.sw.scan_names() == ["Hanna", "Anna"], "6: Ben scannt bei Anna (%s)" % str(b.sw.scan_names()))
	pump(t_step)
	check(b.sw.takeovers == 0 and not (states.Ben as Array).has("taking"), "6: Ben übernimmt nicht")
	_clear()


# ---------- 7 ----------

func _planned_lan() -> void:
	var t := _table()
	var h: Dev = t[0]
	var a: Dev = t[1]
	var b: Dev = t[2]
	var ht := h.ht()
	var seats := seats_of([a, b])
	var hanna_seat := ht.host_seat
	var gen0 := ht.gen
	check(ht.handover_block(seats.Anna).is_empty(), "7: Übergabe an Anna im WLAN möglich (%s)" % I18n.render(ht.handover_block(seats.Anna)))
	check(ht.handover_to(seats.Anna), "7: handover_to(Anna)")
	check(wait_until(func(): return a.ht() != null and a.sw.takeovers == 1, 6000), "7: Anna führt (%s)" % a.sw.state)
	check(a.ht().gen == gen0 + 1 and a.ht().port() == A_PORT, "7: Anna gen + 1 auf ihrem Port")
	# Hannas Gast-Tisch ist neu: Den Platz kennt er erst aus der ersten Sicht (state), die nach dem welcome kommt – unter Last oft erst
	# im nächsten poll. Deshalb auf die erste Sicht warten (vorher lag local_seat() noch bei −1, Bau 1.6.3 einmal rot).
	check(wait_until(func(): return h.ct() != null and h.ct().connection_state() == "open" and h.ct().host_name() == "Anna" \
		and h.ct().view_rev > 0, 6000), "7: Hanna tritt ab und spielt als Gast bei Anna (%s)" % h.sw.state)
	check(h.ct().local_seat() == hanna_seat and h.ct().port == A_PORT, "7: Hanna auf ihrem Platz (Platz %d statt %d, Port %d, Sichten %d)"
		% [h.ct().local_seat(), hanna_seat, h.ct().port, h.ct().view_rev])
	check(str(h.swaps[-1][1]) == I18n.t("Du spielst jetzt als Gast weiter. Gastgeber ist %s.") % "Anna", "7: Hinweis an Hanna")
	check(wait_until(func(): return b.ct() != null and b.ct().connection_state() == "open" and b.ct().host_name() == "Anna", 6000),
		"7: Ben folgt dem move (%s)" % b.sw.state)
	check(b.sw.follows >= 1 and b.sw.takeovers == 0 and b.ct().local_seat() == seats.Ben, "7: Ben umgezogen, gleicher Platz")
	check(str(last_of(b.inbox, "move").get("how", "")) == "lan" and not (states.Ben as Array).has("missing"),
		"7: Ben folgt dem move lan, nicht erst der Suche (%s)" % str(states.Ben))
	check(count(b.inbox, "bye") == 0, "7: kein bye")
	var at := a.ht()
	var rev := at.rev
	play(6)
	check(at.rev > rev, "7: Partie läuft weiter")
	check(h.sw.takeovers == 0 and a.sw.takeovers == 1, "7: kein Hin und Her")
	_clear()


# ---------- 8 ----------

func _planned_qr() -> void:
	var t := _table(true, {"ok": true, "perm": true}, {"ok": false, "perm": false})
	var h: Dev = t[0]
	var a: Dev = t[1]
	var b: Dev = t[2]
	var ht := h.ht()
	var seats := seats_of([a, b])
	check(ht.handover_how(seats.Anna) == "qr", "8: Übergabe im Spiel-WLAN der Gastgeberin ist qr")
	check(not ht.handover_block(seats.Ben).is_empty(), "8: Ben (kein Spiel-WLAN möglich) ist ausgegraut")
	(order.Anna as Array).clear()
	check(ht.handover_to(seats.Anna), "8: handover_to(Anna)")
	check(wait_until(func(): return a.ht() != null and a.sw.takeovers == 1, 6000), "8: Anna führt (%s)" % a.sw.state)
	check(order.Anna == ["release", "server"] and int(released.get("Anna", 0)) == 1, "8: wifi_release vor dem Server (%s)" % str(order.Anna))
	check(int(opened.get("Anna", 0)) == 1, "8: Anna öffnet ein eigenes Spiel-WLAN")
	check(wait_until(func(): return h.ct() != null, 6000), "8: Hanna tritt ab (%s)" % h.sw.state)
	check(int(stopped.get("Hanna", 0)) == 1, "8: Hanna schließt ihr Spiel-WLAN")
	check(wait_until(func(): return (states.Ben as Array).has("scan"), 3000), "8: Ben bekommt move qr (%s)" % str(last_of(b.inbox, "move")))
	check((states.Hanna as Array).has("scan") and (states.Ben as Array).has("scan"), "8: Hanna und Ben im Zustand scan (%s / %s)" % [str(states.Hanna), str(states.Ben)])
	# Hanna: neuer Gast-Tisch, Platz erst mit der ersten Sicht (wie Fall 7)
	check(wait_until(func(): return h.ct() != null and h.ct().connection_state() == "open" and h.ct().host_name() == "Anna" \
		and h.ct().view_rev > 0 and b.ct() != null and b.ct().connection_state() == "open" and b.ct().host_name() == "Anna", 8000),
		"8: beide finden Anna per Suche (%s / %s)" % [h.sw.state, b.sw.state])
	check(h.ct().local_seat() == ht.host_seat and b.ct().local_seat() == seats.Ben, "8: gleiche Plätze (Hanna %d statt %d, Sichten %d)"
		% [h.ct().local_seat(), ht.host_seat, h.ct().view_rev])
	check(h.sw.takeovers == 0 and b.sw.takeovers == 0, "8: niemand sonst übernimmt")
	_clear()


# ---------- 9 ----------

func _majority() -> void:
	var t := _table()
	var h: Dev = t[0]
	var a: Dev = t[1]
	var b: Dev = t[2]
	var ht := h.ht()
	var seats := seats_of([a, b])
	var gen0 := ht.gen
	# Annas Aussetzer: ihre Verbindung hängt, Neuversuche laufen ins Leere, ihre Suche findet niemanden
	a.sw.discovery_setup = func(n: NetDiscovery) -> void: disc(n, [DEAD_UDP])
	for conn in ht.session._conn_player.keys():
		if int(ht.session._conn_player[conn]) == ht.session.id_at_seat(seats.Anna):
			ht.session.server.mute_ws(int(conn))
	a.ct().client.port = 1
	ht.substitute_bot(seats.Anna)            # bei Hanna spielt der Computer für Anna weiter
	check(wait_until(func(): return a.sw.takeovers == 1 and a.ht() != null, 8000), "9: Anna übernimmt allein (%s)" % a.sw.state)
	var gen_a := a.ht().gen
	check(gen_a == gen0 + 1, "9: Annas Zweig gen + 1")
	var rev := ht.rev
	play(4)
	check(ht.rev > rev, "9: Hanna spielt mit Ben weiter")
	var seq_h := ht.seq
	check(wait_until(func(): return a.ct() != null and a.ct().connection_state() == "open" and a.ct().host_name() == "Hanna", 10000),
		"9: Anna tritt ab (weniger verbunden) und spielt als Gast bei Hanna (%s)" % a.sw.state)
	check(h.ht() == ht and ht.gen > gen_a, "9: Hanna hebt ihre gen über Annas (%d > %d)" % [ht.gen, gen_a])
	check(ht.seq >= seq_h and b.ct().host_name() == "Hanna", "9: Züge der Mehrheit bleiben, Ben bleibt bei Hanna")
	check(wait_until(func(): return int(a.ct().backup.get("gen", 0)) == ht.gen, 4000), "9: Annas Sicherung folgt Hanna (gen %d)" % ht.gen)
	pump(1200)
	check(h.ht() == ht and a.ct() != null and not ht.is_frozen() and a.sw.takeovers == 1, "9: kein Zurückholen per Abstammung")
	_clear()


# ---------- 10 ----------

func _two_at_once() -> void:
	var t := _table()
	var h: Dev = t[0]
	var a: Dev = t[1]
	var b: Dev = t[2]
	var gen0 := h.ht().gen
	a.sw.automatic = false
	b.sw.automatic = false
	kill_lan_closed(h)
	check(wait_until(func(): return a.sw.state == "waiting" and b.sw.state == "waiting", 6000), "10: beide merken das Fehlen (%s/%s)" % [a.sw.state, b.sw.state])
	a.sw._take_over_backup(a.ct())          # beide gleichzeitig (wie „Spiel als Gastgeber fortsetzen“ auf zwei Geräten)
	b.sw._take_over_backup(b.ct())
	check(a.ht() != null and b.ht() != null and a.ht().gen == gen0 + 1 and b.ht().gen == gen0 + 1 and a.ht().epoch != b.ht().epoch,
		"10: zwei Gastgeber, gleiche gen, andere epoch")
	check(wait_until(func(): return (a.ht() != null) != (b.ht() != null) and (a.ct() == null or a.ct().connection_state() == "open") \
		and (b.ct() == null or b.ct().connection_state() == "open"), 10000), "10: genau einer tritt ab (%s/%s)" % [a.sw.state, b.sw.state])
	var host: Dev = a if a.ht() != null else b
	var guest: Dev = b if host == a else a
	var swaps := [host.swaps.size(), guest.swaps.size()]
	pump(1500)
	check(host.ht() != null and guest.ct() != null and host.swaps.size() == swaps[0] and guest.swaps.size() == swaps[1], "10: kein Hin und Her")
	check(guest.ct().host_name() == host.name, "10: der andere spielt als Gast")
	_clear()


# ---------- 11 ----------

# Nachtest 1.6.2: Nach der geplanten Übergabe qr stand die abgetretene Gastgeberin (ihr Spiel-WLAN gerade selbst geschlossen) in scan
# mit „Spiel-WLAN von Hanna ist weg.“ und „Spiel als Gastgeber fortsetzen“ – ein Tipp eröffnete einen zweiten Zweig. Jetzt wartet sie
# handoff_wait_ms (handed_off, keine Übernahme von Hand); Ben (scan nach move qr, fremdes Spiel-WLAN weg) bleibt unverändert, danach
# gilt auch für Hanna scan wie nach einem Ausfall. Beide Suchen laufen hier ins Leere (Anna wird nie gefunden).
func _planned_qr_wait() -> void:
	var t := _table(true, {"ok": true, "perm": true}, {"ok": false, "perm": false})
	var h: Dev = t[0]
	var a: Dev = t[1]
	var b: Dev = t[2]
	var ht := h.ht()
	var seats := seats_of([a, b])
	for d in [h, b]:
		(d as Dev).sw.discovery_setup = func(n: NetDiscovery) -> void: disc(n, [DEAD_UDP])
	h.sw.handoff_wait_ms = 3000
	check(ht.handover_how(seats.Anna) == "qr" and ht.handover_to(seats.Anna), "11: handover_to(Anna) mit qr")
	check(wait_until(func(): return h.ct() != null and h.sw.state == "scan", 6000), "11: Hanna tritt ab, Zustand scan (%s)" % h.sw.state)
	check(int(stopped.get("Hanna", 0)) == 1 and h.ct().client == null, "11: eigenes Spiel-WLAN zu, ohne Verbindung")
	check(h.sw.handed_off() and not h.sw.can_continue(), "11: Hanna wartet – kein „Spiel als Gastgeber fortsetzen“")
	check(h.sw.scan_names()[1] == "Anna", "11: QR-Knopf nennt Anna (%s)" % str(h.sw.scan_names()))
	check(not h.sw.continue_as_host() and h.sw.state == "scan" and h.ht() == null, "11: continue_as_host() bleibt wirkungslos")
	check(wait_until(func(): return b.sw.state == "scan", 3000), "11: Ben bekommt move qr (%s)" % b.sw.state)
	check(not b.sw.handed_off() and b.sw.can_continue(), "11: Ben (scan nach move) unverändert mit „Spiel als Gastgeber fortsetzen“")
	pump(600)
	check(h.sw.state == "scan" and h.sw.handed_off() and not h.sw.can_continue(), "11: Hanna wartet weiter (%s)" % h.sw.state)
	check(wait_until(func(): return not h.sw.handed_off(), 5000), "11: Wartezeit vorbei")
	check(h.sw.state == "scan" and h.sw.can_continue(), "11: danach scan wie nach einem Ausfall (%s)" % h.sw.state)
	check(h.sw.takeovers == 0 and b.sw.takeovers == 0 and a.sw.takeovers == 1, "11: nur Anna führt")
	_clear()
