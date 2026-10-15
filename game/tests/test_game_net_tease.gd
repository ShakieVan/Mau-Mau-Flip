extends "res://tests/handover_kit.gd"

# Mau-Mau Flip (Beta 1.6.3, Easter Eggs Teil 2 „Necken“, docs/module/eastereggs2.md Abschnitte 1, 4, 9): Netzseite.
# Gastgeberin „Hanna“ (WLAN 24833 + Raum beim Vermittler-Nachbau 24832), App-Gast „Kim“ im WLAN, App-Gast „Anna“ online, Browser-Gast
# „Wally“ online (nackter NetClient wie Lite), Computergegner „Minka“. Die Uhr fürs Necken ist eingespritzt (fx_clock, steht still, läuft nur
# über clock_off).
#  0  Übung: nur die Papierkugel auf Computergegner (lokal, ohne Netz); Weitergeben: nichts.
#  1  Schnarchen: vor 10 s still verworfen; danach Gast → Gastgeber → alle (auch Absender, Gastgeber per fx_event, Browser); Spielstand
#     unberührt (rev, seq, Speicherdatei, Zahl der bk). Zweite Weckaktion während der ersten: busy als fx_no nur an den Absender
#     (Gastgeber: fx_refused), kein err. Abgelehnte Aktion des Ziels setzt die Uhr nicht zurück, angenommene schon; Ziel hat gespielt: late.
#  2  Papierkugel auf den Computergegner, Abstand am Ziel (rate); Reaktions-Eimer (rate), lokaler Spiegel graut genauso aus.
#  3  fx_pref → fx_offs an alle Sitzenden nur bei Änderung, ohne Spielstand (rev, seq, Datei, bk); gleicher Wert erneut → nichts;
#     Ziel mit Necken aus wird nicht angenommen; Gastgeber steht selbst in der Liste; kaputte Nachrichten ändern nichts.
#  4  Warteliste: bekommt kein fx, kann nicht necken; Dazuholen leert den Zustand, verschiebt fx_offs (neue Platznummern), der Neue
#     bekommt die Liste.
#  5  Eingefroren und Einschwingzeit: nichts angenommen (ohne fx_no).
#  6  Ältere Geräte: unbekannte Typen und kaputte fx gehen an ClientTable._on_message vorbei, ohne Signal und ohne die Sicht zu ändern;
#     der Browser-Gast bleibt verbunden.
#  7  Übernahme (online, 1.6.1): Anna führt, Ben meldet fx_pref neu (fx_offs bei Anna), Necken läuft beim neuen Gastgeber.

const RELAY_PORT := 24832
const H_PORT := 24833
const K_PORT := 24834
const A_PORT := 24835
const O_PORT := 24836
const H2_PORT := 24837
const A2_PORT := 24838
const B2_PORT := 24839

var clock_base := Time.get_ticks_msec()
var clock_off := 0
var recs := {}                     # Instanz-id der Quelle -> {fx: [], no: [], offs: []}


func _initialize() -> void:
	rng.seed = 1630
	_practice()
	start_relay(RELAY_PORT)
	# 1–6 prüfen das Necken, nicht die Übergabe: Wächter mit Fristen nahe der App (sonst verbindet ein App-Gast unter Last nach 0,5 s
	# Stille neu – HostSwitch._start_probe → reconnect_now – und ein fx in diesem Moment geht verloren). 7 braucht die kurzen Fristen.
	t_silent = 30000
	t_away = 30000
	_main_table()
	_clear()
	t_silent = 500
	t_away = 4000
	_takeover()
	finish()


# Necken-Uhr steht still und läuft nur über clock_off: Sperrzeiten (Kugel-Abstand 1,5 s, Eimer, Weckaktion 4,5 s, „early“ 10 s) hängen
# so nicht davon ab, wie viel echte Zeit unter Last zwischen Ereignis und Prüfung vergeht (voller Bau: parallele Testprozesse).
func fx_now() -> int:
	return clock_base + clock_off


func make_host() -> HostTable:
	var h := super.make_host()
	h.fx_clock = fx_now
	return h


func make_client() -> ClientTable:
	var c := super.make_client()
	c.fx_clock = fx_now
	return c


# Signale einer Quelle mitschreiben (fx_event, fx_refused, fx_offs_changed)
func rec(t: TableSource) -> Dictionary:
	var key := t.get_instance_id()
	if not recs.has(key):
		var r := {"fx": [], "no": [], "offs": []}
		recs[key] = r
		t.fx_event.connect(func(m: Dictionary) -> void: (r.fx as Array).append(m))
		t.fx_refused.connect(func(w: String) -> void: (r.no as Array).append(w))
		t.fx_offs_changed.connect(func(s: Array) -> void: (r.offs as Array).append(s))
	return recs[key]


var diag_host: HostTable           # Haupttisch (1–6), für die Ausgabe bei FAIL


# Bei FAIL zusätzlich: Verbindungen (eine neue conn-Nummer = neu angemeldet), Wächter, letzte Nachrichten je Gerät.
func check(ok: bool, message: String) -> void:
	super.check(ok, message)
	if ok or diag_host == null or not is_instance_valid(diag_host):
		return
	var h := diag_host
	print("  DIAG Gastgeber: frozen %s, settling %s, Spieler %s" % [h._frozen, h._settling,
		str(h.session.players.values().map(func(pl): return [pl.get("name", ""), pl.get("conn", -1), pl.get("connected", "?"), pl.get("away", false)]))])
	for d in devs:
		var s: TableSource = d.src()
		var tail: Array = (d.inbox as Array).slice(-8).map(func(m): return str(m.get("t", "")) + ("/" + str(m.get("k", "")) if m.has("k") else ""))
		print("  DIAG %s: %s, Wächter %s, Posteingang …%s" % [d.name, s.connection_state() if s is ClientTable else ("host" if s != null else "-"),
			d.sw.state if d.sw != null else "-", str(tail)])
	for wv in webs:
		print("  DIAG %s: %s, zu %s, …%s" % [wv.name, (wv.c as NetClient).state, str(wv.closed), str((wv.inbox as Array).slice(-6).map(func(m): return str(m.get("t", ""))))])

func file_of(h: HostTable) -> String:
	return FileAccess.get_file_as_string(h.save_path) if FileAccess.file_exists(h.save_path) else ""


# Den Platz seat ans Ziehen setzen (gebaute Lage wie test_game_net_seats) und an alle verteilen.
func give_turn(h: HostTable, seat: int) -> void:
	h.game.current = seat
	h.game.state = "turn"
	h._changed([])
	pump(150)


# ---------- 0: Übung und Weitergeben ----------

func _practice() -> void:
	var solo := LocalTable.new()
	solo.auto_process = false
	solo.autosave = false
	solo.speed = 0.0
	solo.fx_clock = fx_now
	check(solo.setup("solo", [{"name": "Lena"}, {"name": "Minka", "kind": "bot"}, {"name": "Mogli", "kind": "bot"}], RuleConfig.new(), 99),
		"0: Übung aufgesetzt")
	root.add_child(solo)
	var r := rec(solo)
	solo.start()
	check(solo.fx_caps() == {"kinds": ["ball", "kissen"], "bots_only": true}, "0: caps Übung (Kugel, ab 1.6.6 Furzkissen)")
	check(solo.fx_check({"k": "ball", "to": 1}) == "", "0: Kugel auf Minka erlaubt (lokal)")
	solo.send_fx({"k": "ball", "to": 1})
	check(r.fx.size() == 1 and r.fx[0] == {"t": "fx", "k": "ball", "from": 0, "to": 1}, "0: Kugel kommt direkt als Ereignis (%s)" % str(r.fx))
	solo.send_fx({"k": "ball", "to": 1})
	check(r.fx.size() == 1 and r.no == ["rate"], "0: gleiches Ziel sofort: rate (%s)" % str(r.no))
	solo.send_fx({"k": "snore", "to": 1})
	solo.send_fx({"k": "react", "r": "lachen"})
	solo.send_fx({"k": "ball", "to": 0})
	check(r.fx.size() == 1 and r.no == ["rate"], "0: kein Schnarchen, keine Reaktion, nicht auf sich selbst")
	solo.set_fx_off(true)
	clock_off += 5000
	solo.send_fx({"k": "ball", "to": 2})
	check(r.fx.size() == 1, "0: Necken aus: nichts")
	solo.leave()
	solo.free()
	var ps := LocalTable.new()
	ps.auto_process = false
	ps.autosave = false
	ps.speed = 0.0
	check(ps.setup("pass", [{"name": "Lena"}, {"name": "Ben"}, {"name": "Minka", "kind": "bot"}], RuleConfig.new(), 7), "0: Weitergeben")
	root.add_child(ps)
	var rp := rec(ps)
	ps.start()
	if ps.pending_handover() >= 0:
		ps.reveal()
	check((ps.fx_caps().kinds as Array).is_empty() and ps.fx_check({"k": "ball", "to": 2}) == "mode", "0: Weitergeben: caps leer")
	ps.send_fx({"k": "ball", "to": 2})
	check(rp.fx.is_empty() and rp.no.is_empty(), "0: Weitergeben: kein Necken")
	ps.leave()
	ps.free()


# ---------- 1–6: Haupttisch ----------

func _main_table() -> void:
	var hd := host_dev("Hanna", H_PORT)
	var h := hd.ht()
	diag_host = h
	var link := str(h.session.online_info().link)
	var code := str(h.session.online_info().room)
	var kd := lan_guest("Kim", H_PORT, K_PORT)
	var ad := guest_dev("Anna", link, A_PORT)
	var w := web_guest("Wally", relay.base_url(), code)
	check(wait_until(func(): return kd.ct().my_id > 0 and ad.ct().my_id > 0 and (w.c as NetClient).my_id > 0), "Gäste angemeldet")
	h.add_bot("Minka")
	h.set_rules(RuleConfig.preset("offiziell"))
	check(h.start(1630), "Start")
	var kim := kd.ct()
	var anna := ad.ct()
	check(wait_until(func(): return kim.view_rev > 0 and anna.view_rev > 0 and not (w.view as Dictionary).is_empty()), "alle haben den Stand")
	var ks := kim.local_seat()
	var as_ := anna.local_seat()
	var ws := int((w.view as Dictionary).get("seat", -1))
	var bot := -1
	for s in h.seats.size():
		if str(h.seats[s].kind) == "bot":
			bot = s
	check(h.host_seat == 0 and ks >= 0 and as_ >= 0 and ws >= 0 and bot >= 0, "Plätze (Kim %d, Anna %d, Wally %d, Minka %d)" % [ks, as_, ws, bot])
	var rh := rec(h)
	var rk := rec(kim)
	var ra := rec(anna)

	# ---------- 1: Schnarchen
	give_turn(h, ks)
	check(wait_until(func(): return int(anna.current_view().get("turn", -1)) == ks and int(kim.current_view().get("turn", -1)) == ks),
		"1: Kim ist dran (alle Sichten)")
	check(anna.fx_check({"k": "snore", "to": ks}) == "early" and anna.fx_slow_left_ms(ks) > 9000, "1: Anna lokal: noch zu früh")
	anna.send_fx({"k": "snore", "to": ks})
	pump(300)
	check(rh.fx.is_empty() and ra.fx.is_empty() and ra.no.is_empty() and count(kd.inbox, "fx") == 0, "1: vor 10 s still verworfen")
	clock_off += 10500
	check(anna.fx_check({"k": "snore", "to": ks}) == "" and anna.fx_slow_left_ms(ks) == 0, "1: Anna lokal: jetzt erlaubt")
	var rev0 := h.rev
	var seq0 := h.seq
	var file0 := file_of(h)
	var bk_k := count(kd.inbox, "bk")
	var bk_a := count(ad.inbox, "bk")
	anna.send_fx({"k": "snore", "to": ks})
	var want := {"t": "fx", "k": "snore", "from": as_, "to": ks}
	var all_got := func() -> bool:
		return rk.fx.size() == 1 and ra.fx.size() == 1 and rh.fx.size() == 1 and count(w.inbox, "fx") == 1
	check(wait_until(all_got), "1: Schnarchen kommt bei allen an (fx H/K/A %d/%d/%d, Wally %d)" % [rh.fx.size(), rk.fx.size(), ra.fx.size(), count(w.inbox, "fx")])
	check(all_got.call() and rk.fx[0] == want and ra.fx[0] == want and rh.fx[0] == want and last_of(w.inbox, "fx") == want, "1: gleiches Ereignis (%s)" % str(rk.fx))
	pump(200)
	check(h.rev == rev0 and h.seq == seq0 and file_of(h) == file0 and count(kd.inbox, "bk") == bk_k and count(ad.inbox, "bk") == bk_a,
		"1: Spielstand unberührt (rev, seq, Datei, bk)")
	check(anna.fx_check({"k": "snore", "to": ks}) == "once", "1: Anna lokal: einmal je Zug")
	# Gastgeberin selbst während der Weckaktion: busy nur lokal
	h.send_fx({"k": "alarm", "to": ks})
	check(rh.no == ["busy"] and rh.fx.size() == 1, "1: Gastgeberin: busy als fx_refused")
	# Browser-Gast während der Weckaktion: fx_no busy nur an ihn
	(w.c as NetClient).send({"t": "fx", "k": "alarm", "to": ks})
	check(wait_until(func(): return last_of(w.inbox, "fx_no") == {"t": "fx_no", "why": "busy"}), "1: Wally bekommt fx_no busy")
	pump(150)
	check(count(w.inbox, "err") == 0 and count(kd.inbox, "fx_no") == 0 and count(ad.inbox, "fx_no") == 0 and rk.no.is_empty(),
		"1: kein err, die anderen merken nichts")
	clock_off += 5000
	(w.c as NetClient).send({"t": "fx", "k": "alarm", "to": ks})
	check(wait_until(func(): return rk.fx.size() == 2 and str(rk.fx[1].k) == "alarm" and int(rk.fx[1].from) == ws), "1: Wecker von Wally danach")
	# abgelehnte Aktion des Ziels setzt die Uhr nicht zurück, angenommene schon
	var since0 := h.tease.since
	clock_off += 1000
	kim.act({"a": "play", "card": 99999})
	check(wait_until(func(): return count(kd.inbox, "err") > 0), "1: Kim: ungültiger Zug abgelehnt")
	check(h.tease.since == since0, "1: abgelehnte Aktion: Uhr unverändert")
	kim.act({"a": "draw"})
	check(wait_until(func(): return h.tease.since != since0 or h.game.current_seat() != ks), "1: Kim zieht")
	check(h.tease.since > since0, "1: angenommene Aktion: Uhr neu")
	if h.game.phase() == "drawn" and h.game.current_seat() == ks:
		kim.act({"a": "keep"})
	check(wait_until(func(): return h.game.current_seat() != ks and int(anna.current_view().get("turn", -1)) != ks), "1: Kim ist fertig")
	clock_off += 11000
	(ad.ct().client as NetClient).send({"t": "fx", "k": "alarm", "to": ks})   # an der lokalen Vorprüfung vorbei
	check(wait_until(func(): return ra.no == ["late"]), "1: Ziel hat schon gespielt: late (%s)" % str(ra.no))
	check(count(ad.inbox, "err") == 0, "1: late ist kein err")

	# ---------- 2: Papierkugel und Reaktionen
	give_turn(h, as_)
	var nfx: int = rk.fx.size()
	var nfa: int = ra.fx.size()
	anna.send_fx({"k": "ball", "to": bot})
	# Auch auf Annas eigenes Echo warten: Ihr Spiegel verbucht die Kugel erst beim Empfang, und online (über den Vermittler) kann sie
	# ein paar Schritte nach Kim (WLAN) ankommen – bis dahin sagt die lokale Vorprüfung noch „geht“ (der Gastgeber lehnt dann mit rate ab).
	check(wait_until(func(): return (rk.fx.size() == nfx + 1 and str(rk.fx[-1].k) == "ball" and int(rk.fx[-1].to) == bot
		and ra.fx.size() == nfa + 1 and str(ra.fx[-1].k) == "ball")), "2: Kugel auf Minka (Kim und Anna)")
	var why2 := anna.fx_check({"k": "ball", "to": bot})
	check(why2 == "rate", "2: Anna lokal: gleiches Ziel zu früh (%s, last_ball %s)" % [why2, str(anna.tease.last_ball)])
	anna.send_fx({"k": "ball", "to": bot})
	check(wait_until(func(): return ra.no.size() == 2 and ra.no[1] == "rate"), "2: zweite Kugel sofort: rate")
	for i in 3:
		kim.send_fx({"k": "react", "r": "klatschen"})
	check(wait_until(func(): return rk.fx.filter(func(m): return str(m.k) == "react").size() == 3), "2: drei Reaktionen")
	check(kim.fx_check({"k": "react", "r": "lachen"}) == "rate", "2: Kim lokal: Eimer leer")
	kim.send_fx({"k": "react", "r": "lachen"})
	check(wait_until(func(): return rk.no == ["rate"]), "2: vierte Reaktion: rate")
	check(wait_until(func(): return (ra.fx.filter(func(m): return str(m.k) == "react").size() == 3 and int(ra.fx[-1].from) == ks
		and str(ra.fx[-1].r) == "klatschen")), "2: Anna sieht genau die drei")

	# ---------- 3: fx_pref / fx_offs
	rev0 = h.rev
	seq0 = h.seq
	file0 = file_of(h)
	bk_a = count(ad.inbox, "bk")
	kim.set_fx_off(true)
	var offs_got := func() -> bool:
		return h.fx_off_seats() == [ks] and anna.fx_off_seats() == [ks] and kim.fx_off_seats() == [ks] and last_of(w.inbox, "fx_offs") == {"t": "fx_offs", "seats": [ks]}
	check(wait_until(offs_got), "3: Kim aus → fx_offs an alle")
	check(rh.offs == [[ks]] and ra.offs == [[ks]] and rk.offs == [[ks]], "3: fx_offs_changed je einmal (%s %s %s, Kim %d fx_offs, %s)" % [str(rh.offs), str(ra.offs), str(rk.offs), count(kd.inbox, "fx_offs"), str(kim.fx_off_seats())])
	pump(150)
	check(h.rev == rev0 and h.seq == seq0 and file_of(h) == file0 and count(ad.inbox, "bk") == bk_a, "3: Spielstand unberührt")
	var n_offs := count(ad.inbox, "fx_offs")
	kim.client.send({"t": "fx_pref", "off": true})
	pump(250)
	check(count(ad.inbox, "fx_offs") == n_offs, "3: gleicher Wert erneut: nichts")
	check(anna.fx_check({"k": "ball", "to": ks}) == "off", "3: Anna lokal: Kim will nicht")
	anna.send_fx({"k": "ball", "to": ks})
	pump(250)
	check(rk.fx.filter(func(m): return str(m.k) == "ball" and int(m.to) == ks).is_empty() and ra.no.size() == 2, "3: Kugel auf Kim still verworfen")
	h.set_fx_off(true)
	check(wait_until(func(): return anna.fx_off_seats() == [0, ks]), "3: Gastgeberin steht selbst in der Liste")
	kim.set_fx_off(false)
	check(wait_until(func(): return anna.fx_off_seats() == [0] and h.fx_off_seats() == [0]), "3: Kim wieder an")
	h.set_fx_off(false)
	check(wait_until(func(): return anna.fx_off_seats().is_empty()), "3: alle an")
	var n3: int = rk.fx.size()
	for bad in [{"t": "fx", "k": "boom", "to": 1}, {"t": "fx_pref", "off": "ja"}, {"t": "fx", "k": "react", "r": 7}, {"t": "fx", "k": "ball"}]:
		kim.client.send(bad)
	pump(250)
	check(kim.connection_state() == "open" and rk.fx.size() == n3 and anna.fx_off_seats().is_empty() and count(kd.inbox, "err") == 1,
		"3: kaputte Nachrichten ändern nichts")
	kim.set_fx_off(true)
	check(wait_until(func(): return anna.fx_off_seats() == [ks]), "3: Kim wieder aus (für 4)")

	# ---------- 4: Warteliste und Dazuholen
	h.set_join_open(true)
	var od := guest_dev("Ole", link, O_PORT)
	check(wait_until(func(): return od.ct().waiting and h.waiting_ids().size() == 1), "4: Ole wartet")
	var ole := od.ct()
	var ro := rec(ole)
	clock_off += 4000
	anna.send_fx({"k": "react", "r": "daumen"})
	check(wait_until(func(): return ra.fx.size() > 0 and str(ra.fx[-1].r) == "daumen"), "4: Reaktion von Anna")
	pump(150)
	check(count(od.inbox, "fx") == 0 and ro.fx.is_empty(), "4: die Warteliste bekommt kein fx")
	var n_all: int = ra.fx.size()
	ole.client.send({"t": "fx", "k": "react", "r": "lachen"})
	pump(300)
	check(ra.fx.size() == n_all and count(od.inbox, "fx_no") == 0, "4: Wartende necken nicht (still)")
	check(not h.tease.sent.is_empty(), "4: vorher: Schnarch-Buch voll")
	var oid: int = h.waiting_ids()[0]
	check(h.seat_in(oid, 1), "4: Ole an Platz 1")
	check(wait_until(func(): return ole.local_seat() == 1 and kim.local_seat() == ks + 1 and anna.fx_off_seats() == [ks + 1]),
		"4: Kim rückt weiter, fx_offs mit neuer Nummer (%s)" % str(anna.fx_off_seats()))
	check(h.tease.sent.is_empty() and h.tease.buckets.is_empty() and anna.tease.sent.is_empty(), "4: Dazuholen leert den Zustand (Gastgeber, Spiegel)")
	check(wait_until(func(): return ole.fx_off_seats() == [ks + 1]), "4: der Neue bekommt die Liste")
	ks += 1
	if as_ >= 1:
		as_ += 1
	if bot >= 1:
		bot += 1
	check(ole.fx_check({"k": "react", "r": "lachen"}) == "", "4: Ole kann jetzt necken")
	ole.send_fx({"k": "react", "r": "lachen"})
	check(wait_until(func(): return ra.fx.size() == n_all + 1 and int(ra.fx[-1].from) == 1), "4: Reaktion von Ole kommt an")

	# ---------- 5: eingefroren, Einschwingzeit
	var n5: int = ra.fx.size()
	var no5 := count(ad.inbox, "fx_no")
	clock_off += 4000
	h._frozen = true
	anna.send_fx({"k": "react", "r": "schreck"})
	pump(300)
	h._frozen = false
	# Einschwingzeit direkt (ohne Erben-Tokens endet sie beim nächsten pump von selbst)
	var rh5: int = rh.fx.size()
	h._settling = true
	h._on_fx(anna.my_id, {"t": "fx", "k": "react", "r": "schreck"})
	h.send_fx({"k": "react", "r": "schreck"})
	h._settling = false
	check(rh.fx.size() == rh5, "5: Einschwingzeit: nichts angenommen")
	pump(300)
	check(ra.fx.size() == n5 and count(ad.inbox, "fx_no") == no5, "5: eingefroren/Einschwingzeit: nichts angenommen, kein fx_no (%d %d, %d %d)" % [ra.fx.size(), n5, count(ad.inbox, "fx_no"), no5])
	h._on_fx(anna.my_id, {"t": "fx", "k": "react", "r": "schreck"})
	check(rh.fx.size() == rh5 + 1, "5: danach wieder angenommen")

	# ---------- 6: ältere Geräte und kaputte Nachrichten an den Gast
	var v0: Dictionary = kim.current_view().duplicate(true)
	var n6 := [rk.fx.size(), rk.no.size(), rk.offs.size()]
	kim._on_message({"t": "fx_neu", "k": "snore", "from": 0, "to": ks})
	kim._on_message({"t": "fx", "k": "gaehnen", "from": 0, "to": ks})
	kim._on_message({"t": "fx", "k": "ball", "from": ks, "to": ks})
	kim._on_message({"t": "fx_no", "why": "early"})
	kim._on_message({"t": "fx_offs", "seats": [ks]})        # dieselbe Liste: kein Signal
	check([rk.fx.size(), rk.no.size(), rk.offs.size()] == n6 and kim.current_view() == v0, "6: unbekannt/kaputt: ohne Signal, Sicht gleich")
	check((w.c as NetClient).state == "open" and (w.view as Dictionary).has("hand"), "6: Browser-Gast bleibt verbunden")
	_spawn_ok(w)

	# ---------- 3b: fx_offs über „zurück in die Lobby“ und eine neue Partie (Gegenprüfung 1.6.3)
	# Kim bleibt aus: Die neue Partie bringt die Liste neu (mit Kims neuer Nummer).
	h.back_to_lobby()
	check(wait_until(func(): return anna.fx_off_seats().is_empty() and kim.fx_off_seats().is_empty()), "3b: Lobby: Gäste vergessen fx_offs")
	check(h.start(1631), "3b: neue Partie")
	check(wait_until(func(): return kim.local_seat() >= 0 and anna.fx_off_seats() == [kim.local_seat()] and kim.fx_off_seats() == [kim.local_seat()]),
		"3b: Kim weiter aus → Liste der neuen Partie (%s, Kim %d)" % [str(anna.fx_off_seats()), kim.local_seat()])
	# Kim schaltet in der Lobby wieder an: In der neuen Partie gilt niemand mehr als „aus“ (der Gastgeber schickt die leere Liste nicht).
	h.back_to_lobby()
	pump(150)
	kim.set_fx_off(false)
	pump(150)
	check(h.start(1632), "3b: dritte Partie")
	check(wait_until(func(): return kim.local_seat() >= 0 and anna.local_seat() >= 0 and int(anna.current_view().get("turn", -1)) >= 0), "3b: Sicht der dritten Partie")
	pump(200)
	check(anna.fx_off_seats().is_empty() and kim.fx_off_seats().is_empty() and h.fx_off_seats().is_empty(),
		"3b: niemand mehr aus (%s %s %s)" % [str(anna.fx_off_seats()), str(kim.fx_off_seats()), str(h.fx_off_seats())])
	check(anna.fx_check({"k": "ball", "to": kim.local_seat()}) != "off", "3b: Anna darf Kim wieder necken")


func _spawn_ok(w: Dictionary) -> void:
	# Der Browser-Gast hat alle Typen bekommen (Lite ignoriert sie in 1.6.2 per default: break)
	var types := {}
	for m in w.inbox:
		types[str(m.get("t", ""))] = true
	check(types.has("fx") and types.has("fx_no") and types.has("fx_offs"), "6: Browser bekam fx, fx_no, fx_offs (%s)" % str(types.keys()))


func _clear() -> void:
	diag_host = null
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
	recs.clear()
	pump(150)


# ---------- 7: Übernahme ----------

func _takeover() -> void:
	var hd := host_dev("Hanna2", H2_PORT)
	var h := hd.ht()
	var link := str(h.session.online_info().link)
	var ad := guest_dev("Anna2", link, A2_PORT)
	var bd := guest_dev("Ben2", link, B2_PORT)
	check(wait_until(func(): return ad.ct().my_id > 0 and bd.ct().my_id > 0), "7: Gäste angemeldet")
	h.add_bot("Minka")
	h.set_rules(RuleConfig.preset("offiziell"))
	check(h.start(1631), "7: Start")
	check(wait_until(func(): return ad.ct().view_rev > 0 and bd.ct().view_rev > 0), "7: Gäste haben den Stand")
	play(4)
	bd.ct().set_fx_off(true)
	var bs := bd.ct().local_seat()
	check(wait_until(func(): return ad.ct().fx_off_seats() == [bs]), "7: Ben aus (vor dem Ausfall)")
	check(wait_until(func(): return ad.ct().backup_current() and bd.ct().backup_current() and ad.sw.state == "watch"), "7: Sicherungen aktuell")
	kill_still(hd)
	check(wait_until(func(): return ad.sw.takeovers == 1, 8000), "7: Anna übernimmt (Zustand %s)" % ad.sw.state)
	var at := ad.ht()
	check(at != null and wait_until(func(): return bd.ct() != null and bd.ct().connection_state() == "open" and bd.ct().host_name() == "Anna2", 6000),
		"7: Ben ist jetzt bei Anna")
	check(wait_until(func(): return at.fx_off_seats() == [bs] and bd.ct().fx_off_seats() == [bs], 3000),
		"7: Ben meldet fx_pref nach seinem welcome neu (%s)" % str(at.fx_off_seats()))
	check(wait_until(func(): return not at.is_settling(), 3000), "7: Einschwingzeit vorbei")
	bd.sw.t_silent_ms = 30000          # Übernahme geprüft; ab hier geht es ums Necken (wie oben: kein Neuverbinden nach 0,5 s Stille)
	bd.sw.t_away_ms = 30000
	var ra := rec(at)
	var rb := rec(bd.ct())
	clock_off += 4000
	bd.ct().set_fx_off(false)
	check(wait_until(func(): return at.fx_off_seats().is_empty()), "7: Ben wieder an")
	bd.ct().send_fx({"k": "react", "r": "daumen"})
	var want := {"t": "fx", "k": "react", "from": bs, "r": "daumen"}
	check(wait_until(func(): return ra.fx.size() == 1 and rb.fx.size() == 1), "7: Reaktion nach der Übernahme kommt an")
	check(ra.fx[0] == want and rb.fx[0] == want, "7: bei Anna (Gastgeberin) und Ben (%s)" % str(rb.fx))
	at.send_fx({"k": "ball", "to": bs})
	check(wait_until(func(): return rb.fx.size() == 2 and str(rb.fx[1].k) == "ball" and int(rb.fx[1].from) == at.host_seat),
		"7: Kugel der neuen Gastgeberin bei Ben")
