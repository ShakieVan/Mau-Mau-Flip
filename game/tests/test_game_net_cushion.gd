extends "res://tests/handover_kit.gd"

# Mau-Mau Flip (Beta 1.6.6, Furzkissen, docs/module/eastereggs2.md Abschnitt 12): Netzseite und Übung.
# Gastgeberin „Hanna“ im WLAN (24842), App-Gäste „Kim“ und „Anna“ im WLAN, Browser-Gast „Wally“ (nackter NetClient wie Lite),
# Computergegner „Minka“. Necken-Uhr (fx_clock) steht still und läuft nur über clock_off, der Zufall der Sperre (fx_rand) ist fest.
#  0  Übung: Kissen nur auf Computergegner, Bestätigung, Sperre (rate) und eins je Ziel (busy) mit fx_refused_kind, Pups beim nächsten
#     Zug des Bots (mit from, das Gerät ist der Leger); Weitergeben: nichts.
#  1  Geheim legen: Bestätigung nur an den Leger; Gastgeberin, Ziel und Browser bekommen nichts, die Vorprüfung der Gastgeberin verrät
#     nichts; Spielstand unberührt (rev, seq, Datei).
#  2  Zweites Kissen beim selben Ziel: fx_no busy mit k:"kissen" nur an den Absender (Gastgeberin: fx_refused + fx_refused_kind).
#  3  Zufallssperre: 0,5 → 120 s beim Gastgeber, ohne Restzeit in fx_no; der Spiegel des Legers sperrt nur 60 s.
#  4  Auslösen: Zugwechsel allein löst nichts aus, der nächste Zug (Ziehen) des Ziels schon – erst der Stand, dann kissen_pop; geheim ohne
#     from an alle außer dem Leger (Kopie mit from); kein Leck des Legers an andere, weder vorher noch nachher; zweite Aktion: nichts.
#  5  Mit Namen auf den Computergegner: Pups beim Zug des Bots, alle bekommen from.
#  6  Necken aus: Kissen auf ein Ziel mit Necken aus still verworfen; Ziel schaltet nach dem Legen aus → verfällt still.
#  7  Lobby/neue Partie: offene Kissen verfallen, nichts pupst später.
#  8  Ältere/fremde Nachrichten am Gast: Bestätigung für einen anderen Platz und unbekannte Arten ohne Signal; Browser bleibt verbunden.

const H_PORT := 24842
const K_PORT := 24843
const A_PORT := 24844

var clock_base := Time.get_ticks_msec()
var clock_off := 0
var rand_u := 0.5
var recs := {}


func _initialize() -> void:
	rng.seed = 1660
	_practice()
	t_silent = 30000
	t_away = 30000
	_main_table()
	finish()


func fx_now() -> int:
	return clock_base + clock_off


func fx_rand() -> float:
	return rand_u


func make_host() -> HostTable:
	var h := super.make_host()
	h.fx_clock = fx_now
	h.fx_rand = fx_rand
	return h


func make_client() -> ClientTable:
	var c := super.make_client()
	c.fx_clock = fx_now
	return c


func rec(t: TableSource) -> Dictionary:
	var key := t.get_instance_id()
	if not recs.has(key):
		var r := {"fx": [], "no": [], "kind": []}
		recs[key] = r
		t.fx_event.connect(func(m: Dictionary) -> void: (r.fx as Array).append(m))
		t.fx_refused.connect(func(w: String) -> void:
			(r.no as Array).append(w)
			(r.kind as Array).append(t.fx_refused_kind))
	return recs[key]


func kissen(to: int, reveal := false) -> Dictionary:
	return {"k": "kissen", "to": to, "reveal": reveal}


func give_turn(h: HostTable, seat: int) -> void:
	h.game.current = seat
	h.game.state = "turn"
	h._changed([])
	pump(150)


func file_of(h: HostTable) -> String:
	return FileAccess.get_file_as_string(h.save_path) if FileAccess.file_exists(h.save_path) else ""


# fx-Nachrichten mit Kissen-Art in einer Liste
func cushion_msgs(list: Array) -> Array:
	return list.filter(func(m): return str(m.get("t", "")) == "fx" and str(m.get("k", "")).begins_with("kissen"))


# ---------- 0: Übung und Weitergeben ----------

func _practice() -> void:
	var solo := LocalTable.new()
	solo.auto_process = false
	solo.autosave = false
	solo.speed = 0.0
	solo.fx_clock = fx_now
	solo.fx_rand = fx_rand
	check(solo.setup("solo", [{"name": "Lena"}, {"name": "Minka", "kind": "bot"}, {"name": "Mogli", "kind": "bot"}], RuleConfig.new(), 166),
		"0: Übung aufgesetzt")
	root.add_child(solo)
	var r := rec(solo)
	solo.start()
	solo.game.current = 0
	solo.game.state = "turn"
	solo._changed([])
	check(solo.fx_check(kissen(1)) == "" and solo.fx_check(kissen(0)) == "self", "0: Kissen auf Minka erlaubt, nie auf sich selbst")
	rand_u = 0.0
	solo.send_fx(kissen(1))
	check(r.fx == [NetProtocol.make_cushion(0, 1, false)], "0: Bestätigung (%s)" % str(r.fx))
	check(int(solo.tease.cushion_until[0]) == fx_now() + 60000, "0: Sperre ausgelost (Zufall 0 → 60 s)")
	solo.send_fx(kissen(2))
	check(r.no == ["rate"] and r.kind == ["kissen"], "0: gesperrt: rate, fx_refused_kind kissen (%s %s)" % [str(r.no), str(r.kind)])
	clock_off += 60000
	solo.send_fx(kissen(1))
	check(r.no == ["rate", "busy"] and r.kind == ["kissen", "kissen"], "0: bei Minka liegt schon eins: busy")
	solo.send_fx({"k": "ball", "to": 2})
	check(r.fx.size() == 2 and solo.fx_refused_kind == "kissen", "0: Kugel geht weiter (fx_refused_kind bleibt bis zur nächsten Ablehnung)")
	solo.send_fx({"k": "ball", "to": 2})
	check(r.no.size() == 3 and solo.fx_refused_kind == "", "0: Ablehnung einer Kugel: fx_refused_kind leer")
	# Minka ist dran: Der Bot legt oder zieht → Pups (mit from: das Gerät ist der Leger)
	solo.game.current = 1
	solo.game.state = "turn"
	solo._changed([])
	check(r.fx.size() == 2, "0: Zugwechsel allein löst nichts aus")
	var guard := 0
	while guard < 50 and cushion_msgs(r.fx).size() < 2:
		guard += 1
		solo.pump()
	check(cushion_msgs(r.fx).size() == 2 and r.fx[-1] == NetProtocol.make_cushion_pop(1, false, 0),
		"0: Minka zieht/legt → kissen_pop (%s)" % str(r.fx.slice(-1)))
	check(solo.tease.cushions.is_empty(), "0: Kissen weg")
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
	check(ps.fx_check(kissen(2)) == "mode", "0: Weitergeben: kein Kissen")
	ps.send_fx(kissen(2))
	check(rp.fx.is_empty() and rp.no.is_empty() and ps.tease.cushions.is_empty(), "0: Weitergeben: nichts")
	ps.leave()
	ps.free()


# ---------- 1–8: Netz ----------

func _main_table() -> void:
	var hd := host_dev("Hanna", H_PORT, false)
	var h := hd.ht()
	var kd := lan_guest("Kim", H_PORT, K_PORT)
	var ad := lan_guest("Anna", H_PORT, A_PORT)
	var w := web_guest_lan("Wally", H_PORT)
	check(wait_until(func(): return kd.ct().my_id > 0 and ad.ct().my_id > 0 and (w.c as NetClient).my_id > 0), "Gäste angemeldet")
	h.add_bot("Minka")
	h.set_rules(RuleConfig.preset("offiziell"))
	check(h.start(1660), "Start")
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
	check(h.host_seat == 0 and ks > 0 and as_ > 0 and ws > 0 and bot > 0, "Plätze (Kim %d, Anna %d, Wally %d, Minka %d)" % [ks, as_, ws, bot])
	var rh := rec(h)
	var rk := rec(kim)
	var ra := rec(anna)
	give_turn(h, 0)                       # Hanna ist dran: niemand sonst handelt von selbst

	# ---------- 1: geheim legen
	rand_u = 0.5
	var rev0 := h.rev
	var seq0 := h.seq
	var file0 := file_of(h)
	var t1 := fx_now()
	check(kim.fx_check(kissen(as_)) == "", "1: Kim lokal: Kissen auf Anna geht")
	kim.send_fx(kissen(as_))
	check(wait_until(func(): return rk.fx.size() == 1), "1: Kim bekommt die Bestätigung")
	check(rk.fx[0] == NetProtocol.make_cushion(ks, as_, false), "1: Bestätigung {kissen, from, to, reveal:false} (%s)" % str(rk.fx))
	pump(250)
	check(rh.fx.is_empty() and ra.fx.is_empty() and count(ad.inbox, "fx") == 0 and count(w.inbox, "fx") == 0,
		"1: Gastgeberin, Anna und Wally sehen nichts")
	check(h.tease.cushion_at(as_) == {"from": ks, "reveal": false, "at": t1}, "1: Gastgeber-Logik weiß es (%s)" % str(h.tease.cushion_at(as_)))
	check(h.rev == rev0 and h.seq == seq0 and file_of(h) == file0, "1: Spielstand unberührt (rev, seq, Datei)")
	check(h.tease.check(0, kissen(as_), h._fx_table(), fx_now()) == "busy" and h.fx_check(kissen(as_)) == "",
		"1: Vorprüfung der Gastgeberin verrät das fremde Kissen nicht")
	check(anna.fx_check(kissen(ks)) == "" and anna.tease.cushions.is_empty(), "1: Annas Spiegel weiß nichts")
	check(kim.tease.cushion_at(as_).from == ks and kim.fx_check(kissen(bot)) == "rate", "1: Kims Spiegel: eigenes Kissen, gesperrt")

	# ---------- 2: zweites Kissen beim selben Ziel
	h.send_fx(kissen(as_))
	check(rh.no == ["busy"] and rh.kind == ["kissen"] and rh.fx.is_empty(), "2: Gastgeberin: busy (Kissen)")
	(w.c as NetClient).send({"t": "fx", "k": "kissen", "to": as_, "reveal": true})
	check(wait_until(func(): return last_of(w.inbox, "fx_no") == {"t": "fx_no", "why": "busy", "k": "kissen"}), "2: Wally bekommt fx_no busy mit k")
	pump(150)
	check(count(kd.inbox, "fx_no") == 0 and count(ad.inbox, "fx_no") == 0 and count(w.inbox, "err") == 0, "2: die anderen merken nichts, kein err")
	check(int(h.tease.cushion_at(as_).from) == ks, "2: es bleibt Kims Kissen")

	# ---------- 3: Zufallssperre (0,5 → 120 s), ohne Restzeit
	check(int(h.tease.cushion_until[ks]) == t1 + 120000, "3: Sperre beim Gastgeber 120 s")
	kim.client.send({"t": "fx", "k": "kissen", "to": bot, "reveal": false})   # an der lokalen Vorprüfung vorbei
	check(wait_until(func(): return rk.no == ["rate"]), "3: Kim gesperrt: rate")
	check(kim.fx_refused_kind == "kissen" and last_of(kd.inbox, "fx_no") == {"t": "fx_no", "why": "rate", "k": "kissen"},
		"3: fx_no ohne Restzeit (%s)" % str(last_of(kd.inbox, "fx_no")))
	clock_off += 60000
	check(kim.fx_check(kissen(bot)) == "", "3: Kims Spiegel gibt nach 60 s frei")
	kim.send_fx(kissen(bot))
	check(wait_until(func(): return rk.no.size() == 2), "3: Gastgeber sperrt weiter (rate)")
	clock_off += 59999
	check(h.tease.check(ks, kissen(bot), h._fx_table(), fx_now()) == "rate", "3: bis kurz vor 120 s gesperrt")
	clock_off += 1
	check(h.tease.check(ks, kissen(bot), h._fx_table(), fx_now()) == "", "3: ab 120 s frei")

	# ---------- 4: nächster Zug des Ziels löst aus
	var nfx := [rh.fx.size(), rk.fx.size(), ra.fx.size(), count(w.inbox, "fx")]
	give_turn(h, as_)
	check(wait_until(func(): return int(anna.current_view().get("turn", -1)) == as_), "4: Anna ist dran")
	check([rh.fx.size(), rk.fx.size(), ra.fx.size(), count(w.inbox, "fx")] == nfx, "4: Zugwechsel allein löst nichts aus")
	anna.act({"a": "mau"})               # kein Legen/Ziehen (abgelehnt oder angenommen – egal): nichts
	pump(150)
	check([rh.fx.size(), rk.fx.size(), ra.fx.size(), count(w.inbox, "fx")] == nfx and not h.tease.cushion_at(as_).is_empty(),
		"4: Mau löst nicht aus")
	anna.act({"a": "draw"})
	var popped := func() -> bool:
		return rh.fx.size() == nfx[0] + 1 and rk.fx.size() == nfx[1] + 1 and ra.fx.size() == nfx[2] + 1 and count(w.inbox, "fx") == nfx[3] + 1
	check(wait_until(popped), "4: Pups bei allen (H/K/A/W %d/%d/%d/%d)" % [rh.fx.size(), rk.fx.size(), ra.fx.size(), count(w.inbox, "fx")])
	var secret := NetProtocol.make_cushion_pop(as_, false)
	check(rh.fx[-1] == secret and ra.fx[-1] == secret and last_of(w.inbox, "fx") == secret, "4: geheim: ohne from (%s)" % str(ra.fx.slice(-1)))
	check(rk.fx[-1] == NetProtocol.make_cushion_pop(as_, false, ks), "4: nur der Leger bekommt from (%s)" % str(rk.fx.slice(-1)))
	check(h.tease.cushions.is_empty() and kim.tease.cushions.is_empty(), "4: Kissen weg (Gastgeber und Kims Spiegel)")
	# erst der Stand mit Annas Zug, dann der Pups
	var i_pop := -1
	var i_draw := -1
	for i in ad.inbox.size():
		var m: Dictionary = ad.inbox[i]
		if str(m.get("t", "")) == "fx" and str(m.get("k", "")) == "kissen_pop":
			i_pop = i
		if str(m.get("t", "")) == "state" and i_pop < 0:
			for e in m.get("events", []):
				if str(e.get("e", "")) == "draw" and int(e.get("seat", -1)) == as_:
					i_draw = i
	check(i_draw >= 0 and i_pop > i_draw, "4: erst der Stand mit dem Ziehen, dann kissen_pop (%d < %d)" % [i_draw, i_pop])
	# kein Leck: Anna, Wally und der Gastgeber-Bildschirm sahen nie eine Kissen-Nachricht mit from bzw. eine Bestätigung
	var leak := func(list: Array) -> bool:
		return cushion_msgs(list).any(func(m): return m.has("from") or str(m.k) == "kissen")
	check(not leak.call(ad.inbox) and not leak.call(w.inbox) and not leak.call(rh.fx) and not leak.call(ra.fx), "4: geheim bleibt geheim (Protokoll)")
	if h.game.phase() == "drawn" and h.game.current_seat() == as_:
		anna.act({"a": "keep"})
	pump(200)
	check(cushion_msgs(ra.fx).size() == 1 and cushion_msgs(rh.fx).size() == 1, "4: nächste Aktion: kein zweiter Pups")

	# ---------- 5: mit Namen auf den Computergegner
	give_turn(h, 0)
	anna.send_fx(kissen(bot, true))
	check(wait_until(func(): return ra.fx.size() > 0 and ra.fx[-1] == NetProtocol.make_cushion(as_, bot, true)), "5: Anna legt mit Namen auf Minka")
	pump(150)
	check(cushion_msgs(rk.fx).size() == 2 and count(w.inbox, "fx") == nfx[3] + 1, "5: auch mit Namen sieht vorher niemand etwas")
	var named := NetProtocol.make_cushion_pop(bot, true, as_)
	give_turn(h, bot)                   # Minka spielt beim nächsten pump
	check(wait_until(func(): return (rh.fx.size() > 0 and rh.fx[-1] == named and rk.fx[-1] == named and ra.fx[-1] == named
		and last_of(w.inbox, "fx") == named)), "5: Minka legt/zieht → alle bekommen from (%s)" % str(rk.fx.slice(-1)))

	# ---------- 6: Necken aus
	give_turn(h, 0)
	clock_off += 200000
	anna.set_fx_off(true)
	check(wait_until(func(): return h.fx_off_seats() == [as_] and kim.fx_off_seats() == [as_]), "6: Anna aus")
	var nk6: int = rk.fx.size()
	kim.client.send({"t": "fx", "k": "kissen", "to": as_, "reveal": true})
	pump(250)
	check(rk.fx.size() == nk6 and rk.no.size() == 2 and h.tease.cushions.is_empty(), "6: Kissen auf Anna (aus) still verworfen")
	anna.set_fx_off(false)
	check(wait_until(func(): return h.fx_off_seats().is_empty()), "6: Anna wieder an")
	kim.send_fx(kissen(0))
	check(wait_until(func(): return rk.fx.size() == nk6 + 1 and str(rk.fx[-1].k) == "kissen"), "6: Kim legt eins bei Hanna")
	h.set_fx_off(true)
	var n6 := [rh.fx.size(), rk.fx.size(), ra.fx.size(), count(w.inbox, "fx")]
	h.act({"a": "draw"})
	pump(250)
	check([rh.fx.size(), rk.fx.size(), ra.fx.size(), count(w.inbox, "fx")] == n6 and h.tease.cushions.is_empty(),
		"6: Hanna schaltete nach dem Legen aus → verfällt still beim Ziehen")
	h.set_fx_off(false)
	if h.game.phase() == "drawn" and h.game.current_seat() == 0:
		h.act({"a": "keep"})
	pump(150)

	# ---------- 7: Lobby/neue Partie
	give_turn(h, 0)
	clock_off += 200000
	kim.send_fx(kissen(bot))
	check(wait_until(func(): return not h.tease.cushion_at(bot).is_empty()), "7: Kissen bei Minka")
	h.back_to_lobby()
	check(h.tease.cushions.is_empty() and wait_until(func(): return kim.tease.cushions.is_empty()), "7: Lobby: verfallen (Gastgeber, Spiegel)")
	var n7 := [cushion_msgs(rk.fx).size(), cushion_msgs(ra.fx).size(), cushion_msgs(rh.fx).size()]
	check(h.start(1661), "7: neue Partie")
	check(wait_until(func(): return kim.view_rev > 0 and int(kim.current_view().get("round", 0)) >= 1), "7: Stand der neuen Partie")
	play(6)
	check([cushion_msgs(rk.fx).size(), cushion_msgs(ra.fx).size(), cushion_msgs(rh.fx).size()] == n7, "7: nichts pupst später")

	# ---------- 8: fremde/ältere Nachrichten am Gast
	var n8 := [rk.fx.size(), rk.no.size()]
	var other := (ks + 1) % h.seats.size()
	kim._on_message({"t": "fx", "k": "kissen", "from": other, "to": (other + 1) % h.seats.size(), "reveal": true})
	kim._on_message({"t": "fx", "k": "kissen_furz", "from": 0, "to": ks, "reveal": true})
	kim._on_message({"t": "fx", "k": "kissen_pop", "to": ks})
	kim._on_message({"t": "fx_no", "why": "boom", "k": "kissen"})
	check([rk.fx.size(), rk.no.size()] == n8 and kim.tease.cushions.is_empty(), "8: fremde Bestätigung/unbekannt/kaputt: ohne Signal")
	check((w.c as NetClient).state == "open", "8: Browser-Gast bleibt verbunden")
