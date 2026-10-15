extends SceneTree
# Mau-Mau Flip (Beta 1.6.3, Easter Eggs Teil 2 „Necken“): Regeln und Sperrzeiten (TeaseRules) und Protokollprüfung (NetProtocol fx,
# fx_pref, fx_no, fx_offs), rein und mit eingespritzter Uhr (docs/module/eastereggs2.md Abschnitte 1, 4, 9).
#  A  Schnarchen/Wecker: vor 10 s „early“, ab 10 s erlaubt; je Sender und Zug einmal („once“); zweiter Sender erst nach WAKE_BUSY_MS
#     („busy“); Wecker als eigene Art; Zugwechsel: „late“ für das alte Ziel, Uhr neu; eigene Aktion des Ziels setzt die Uhr zurück,
#     eine abgelehnte (keine Ereignisse) nicht.
#  B  Ausgeschlossene Ziele und Absender: nie man selbst, nie Bots (Schnarchen/Wecker), nicht getrennt/away/vertreten, Necken aus;
#     Wartende (−1), Bots und Abwesende als Absender, Absender mit Necken aus.
#  C  Phasen: alle Zugphasen erlaubt, Rundenende nur react.
#  D  Eimer: Papierkugel 2 (+1 je 5 s) und 1,5 s am selben Ziel, Reaktion 3 (+1 je 3 s), Tisch 8 (+4 je s); Gründe rate.
#  E  reset() und Ereignis „seats“; slow_left_ms; caps je Spielart (solo nur Kugel auf Bots, pass nichts).
#  F  table_from_view; NetProtocol: make_fx_request, clean_client_message (fx, fx_pref), make_fx/clean_fx, clean_fx_no, clean_fx_offs.

var failures := 0
var checks := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)


func _initialize() -> void:
	run()
	print("RESULT: %d ok" % checks if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)


# Tisch: Platz 0 Gastgeber, 1 Kim, 2 Ole (Menschen), 3 Minka (Bot)
func tbl(phase := "turn", turn := 1, mode := "host", over := {}) -> Dictionary:
	var seats: Array = []
	for s in 4:
		var d := {"bot": s == 3, "gone": false, "off": false}
		if over.has(s):
			d.merge(over[s], true)
		seats.append(d)
	return {"mode": mode, "phase": phase, "turn": turn, "seats": seats}


func fresh(turn := 1, now := 0) -> TeaseRules:
	var r := TeaseRules.new()
	r.note_turn(turn, "turn", now)
	return r


func fx(k: String, from: int, to := -1, rr := "") -> Dictionary:
	return NetProtocol.make_fx(k, from, to, rr)


func run() -> void:
	# ---------- A: Schnarchen / Wecker
	var r := fresh(1, 1000)
	var t := tbl()
	check(r.check(0, {"k": "snore", "to": 1}, t, 1000 + 9999) == "early", "A: vor 10 s early")
	check(r.slow_left_ms(1, 1000 + 4000) == 6000 and r.slow_left_ms(2, 5000) == -1, "A: slow_left_ms")
	check(r.check(0, {"k": "snore", "to": 1}, t, 11000) == "", "A: ab 10 s erlaubt")
	r.commit(fx("snore", 0, 1), 11000)
	check(r.check(0, {"k": "snore", "to": 1}, t, 30000) == "once", "A: je Sender und Zug einmal")
	check(r.check(2, {"k": "snore", "to": 1}, t, 11000 + 4499) == "busy", "A: zweiter Sender während der Weckaktion busy")
	check(r.check(2, {"k": "snore", "to": 1}, t, 11000 + 4500) == "", "A: zweiter Sender nach 4,5 s")
	check(r.check(0, {"k": "alarm", "to": 1}, t, 11000 + 4500) == "", "A: Wecker ist eine eigene Art")
	r.commit(fx("alarm", 0, 1), 16000)
	check(r.check(2, {"k": "snore", "to": 1}, t, 16000 + 4999) == "busy", "A: Wecker hält das Ziel 5 s")
	check(r.check(2, {"k": "snore", "to": 1}, t, 21000) == "", "A: danach frei")
	check(r.check(0, {"k": "alarm", "to": 1}, t, 60000) == "once", "A: Wecker auch nur einmal je Zug")
	# eine abgelehnte Aktion des Ziels (keine Ereignisse) setzt die Uhr nicht zurück, eine angenommene schon
	r.note_events([], 22000)
	check(r.check(2, {"k": "snore", "to": 1}, t, 22000) == "", "A: abgelehnte Aktion: Uhr läuft weiter")
	r.note_events([{"e": "draw", "seat": 1, "n": 1}], 22000)
	check(r.check(2, {"k": "snore", "to": 1}, t, 22000 + 9999) == "early", "A: eigene Aktion des Ziels: Uhr neu")
	check(r.check(0, {"k": "snore", "to": 1}, t, 40000) == "once", "A: gleicher Zug bleibt gleicher Zug")
	r.note_events([{"e": "play", "seat": 2}], 23000)
	check(r.check(2, {"k": "snore", "to": 1}, t, 22000 + 10000) == "", "A: Ereignis eines anderen Platzes ändert die Uhr nicht")
	# Zugwechsel
	r.note_turn(2, "turn", 40000)
	var t2 := tbl("turn", 2)
	check(r.check(0, {"k": "snore", "to": 1}, t2, 60000) == "late", "A: altes Ziel nicht mehr am Zug: late")
	check(r.check(0, {"k": "snore", "to": 2}, t2, 49999) == "early", "A: neues Ziel: Uhr neu")
	check(r.check(0, {"k": "snore", "to": 2}, t2, 50000) == "", "A: neuer Zug: wieder erlaubt (sent vom alten Zug zählt nicht)")
	r.note_turn(1, "turn", 50000)
	r.note_turn(1, "turn", 70000)
	check(r.check(0, {"k": "snore", "to": 1}, t, 60000) == "", "A: Kim wieder dran = neuer Zug (Uhr ab Wechsel, nicht ab note_turn ohne Wechsel)")

	# ---------- B: Ziele und Absender
	r = fresh(1, 0)
	var now := 20000
	check(r.check(1, {"k": "ball", "to": 1}, t, now) == "self" and r.check(1, {"k": "react", "r": "lachen"}, t, now) == "",
		"B: nie sich selbst (react hat kein Ziel)")
	r.note_turn(3, "turn", 0)
	check(r.check(0, {"k": "snore", "to": 3}, tbl("turn", 3), now) == "target", "B: Bots nie schnarchen/wecken")
	check(r.check(0, {"k": "ball", "to": 3}, tbl("turn", 3), now) == "", "B: Papierkugel auf Bots geht")
	r = fresh(1, 0)
	check(r.check(0, {"k": "snore", "to": 1}, tbl("turn", 1, "host", {1: {"gone": true}}), now) == "target", "B: Ziel abwesend")
	check(r.check(0, {"k": "ball", "to": 1}, tbl("turn", 1, "host", {1: {"gone": true}}), now) == "target", "B: Kugel nicht auf Abwesende")
	check(r.check(0, {"k": "snore", "to": 1}, tbl("turn", 1, "host", {1: {"off": true}}), now) == "off", "B: Ziel hat Necken aus")
	check(r.check(0, {"k": "ball", "to": 2}, tbl("turn", 1, "host", {2: {"off": true}}), now) == "off", "B: Kugel: Ziel hat Necken aus")
	check(r.check(-1, {"k": "react", "r": "daumen"}, t, now) == "sender", "B: Wartende (kein Platz) senden nicht")
	check(r.check(3, {"k": "ball", "to": 1}, t, now) == "sender", "B: Bots necken nie")
	check(r.check(2, {"k": "ball", "to": 1}, tbl("turn", 1, "host", {2: {"gone": true}}), now) == "sender", "B: vertreten/away sendet nicht")
	check(r.check(2, {"k": "react", "r": "daumen"}, tbl("turn", 1, "host", {2: {"off": true}}), now) == "off",
		"B: wer Necken aus hat, neckt nicht")
	check(r.check(0, {"k": "ball", "to": 7}, t, now) == "target" and r.check(0, {"k": "ball"}, t, now) == "target"
		and r.check(9, {"k": "ball", "to": 1}, t, now) == "sender", "B: Plätze außerhalb")
	check(r.check(0, {"k": "gaehnen", "to": 1}, t, now) == "kind" and r.check(0, {"k": "react", "r": "gaehnen"}, t, now) == "kind",
		"B: Gähnen gibt es nicht")

	# ---------- C: Phasen
	for ph in ["turn", "drawn", "color", "challenge", "gamble", "discard_pick"]:
		r = fresh(1, 0)
		r.note_turn(1, ph, 0)
		check(r.check(0, {"k": "snore", "to": 1}, tbl(ph, 1), 10000) == "", "C: Schnarchen in Phase %s" % ph)
		check(r.check(0, {"k": "ball", "to": 2}, tbl(ph, 1), 10000) == "", "C: Kugel in Phase %s" % ph)
	r = fresh(1, 0)
	r.note_turn(-1, "round_over", 0)
	var ro := tbl("round_over", -1)
	check(r.check(0, {"k": "snore", "to": 1}, ro, 20000) == "late" and r.check(0, {"k": "alarm", "to": 1}, ro, 20000) == "late",
		"C: Rundenende: Schnarchen/Wecker late")
	check(r.check(0, {"k": "ball", "to": 1}, ro, 20000) == "phase", "C: Rundenende: keine Kugel")
	check(r.check(0, {"k": "react", "r": "klatschen"}, ro, 20000) == "" and r.check(0, {"k": "react", "r": "klatschen"},
		tbl("game_over", -1), 20000) == "", "C: Rundenende/Partieende: Reaktion geht")
	check(r.check(0, {"k": "react", "r": "klatschen"}, tbl("idle", -1), 20000) == "phase", "C: ohne Partie keine Reaktion")

	# ---------- D: Eimer
	r = fresh(1, 0)
	now = 100000
	check(r.check(0, {"k": "ball", "to": 1}, t, now) == "", "D: Kugel 1")
	r.commit(fx("ball", 0, 1), now)
	check(r.check(0, {"k": "ball", "to": 1}, t, now + 1499) == "rate", "D: gleiches Ziel vor 1,5 s")
	check(r.check(0, {"k": "ball", "to": 2}, t, now + 100) == "", "D: anderes Ziel sofort")
	r.commit(fx("ball", 0, 2), now + 100)
	check(r.check(0, {"k": "ball", "to": 3}, t, now + 200) == "rate", "D: Eimer 2 leer")
	check(r.check(2, {"k": "ball", "to": 3}, t, now + 200) == "", "D: Eimer je Sender")
	check(r.check(0, {"k": "ball", "to": 3}, t, now + 4999) == "rate", "D: noch nicht nachgefüllt")
	check(r.check(0, {"k": "ball", "to": 3}, t, now + 5100) == "", "D: +1 je 5 s")
	check(r.check(0, {"k": "ball", "to": 1}, t, now + 1500) == "rate", "D: bei leerem Eimer auch am alten Ziel rate")
	r = fresh(1, 0)
	for i in 3:
		check(r.check(1, {"k": "react", "r": "lachen"}, t, now) == "", "D: Reaktion %d" % (i + 1))
		r.commit(fx("react", 1, -1, "lachen"), now)
	check(r.check(1, {"k": "react", "r": "daumen"}, t, now + 2999) == "rate", "D: Reaktions-Eimer 3 leer")
	check(r.check(1, {"k": "react", "r": "daumen"}, t, now + 3000) == "", "D: +1 je 3 s")
	# Tisch: 8, +4 je s – viele Absender gleichzeitig (Reaktionen von 0, 1, 2 je 3 = 9 Wünsche)
	r = fresh(1, 0)
	var ok := 0
	for s in [0, 1, 2]:
		for i in 3:
			if r.check(s, {"k": "react", "r": "schreck"}, t, now) == "":
				r.commit(fx("react", s, -1, "schreck"), now)
				ok += 1
	check(ok == 8, "D: Tisch-Eimer lässt 8 durch (%d)" % ok)
	check(r.check(2, {"k": "react", "r": "schreck"}, t, now + 249) == "rate", "D: Tisch-Eimer leer")
	check(r.check(2, {"k": "react", "r": "schreck"}, t, now + 250) == "", "D: Tisch +1 je 250 ms")

	# ---------- E: reset, seats, caps
	r = fresh(1, 0)
	r.commit(fx("snore", 0, 1), 10000)
	r.commit(fx("ball", 2, 1), 10000)
	r.note_events([{"e": "seats", "map": [0, 1, 2], "join": 2}], 11000)
	check(r.sent.is_empty() and r.last_ball.is_empty() and r.buckets.is_empty() and r.busy_until.is_empty() and r.turn == -1,
		"E: seats leert den Zustand")
	r.note_turn(1, "turn", 11000)
	check(r.check(0, {"k": "snore", "to": 1}, t, 20999) == "early" and r.check(0, {"k": "snore", "to": 1}, t, 21000) == "",
		"E: nach seats beginnt die Uhr neu, einmal je Zug wieder frei")
	check(TeaseRules.caps("host").kinds == TeaseRules.FX_KINDS and TeaseRules.caps("client").kinds == TeaseRules.FX_KINDS,
		"E: caps host/client: alles")
	check(TeaseRules.caps("solo") == {"kinds": ["ball"], "bots_only": true}, "E: caps solo: nur Kugel auf Bots")
	check((TeaseRules.caps("pass").kinds as Array).is_empty() and (TeaseRules.caps("").kinds as Array).is_empty(), "E: caps pass: nichts")
	r = fresh(0, 0)
	var solo := tbl("turn", 0, "solo")
	check(r.check(0, {"k": "ball", "to": 3}, solo, 1000) == "", "E: Übung: Kugel auf Bot")
	check(r.check(0, {"k": "ball", "to": 1}, solo, 1000) == "target", "E: Übung: nie auf Menschen")
	check(r.check(0, {"k": "snore", "to": 3}, solo, 20000) == "mode" and r.check(0, {"k": "react", "r": "lachen"}, solo, 1000) == "mode",
		"E: Übung: kein Schnarchen, keine Reaktion")
	check(r.check(0, {"k": "ball", "to": 3}, tbl("turn", 0, "pass"), 1000) == "mode", "E: Weitergeben: nichts")
	check(TeaseRules.REFUSALS == ["late", "busy", "rate"], "E: Gründe für fx_no")

	# ---------- F: table_from_view und Protokoll
	var v := {"phase": "drawn", "turn": 2, "players": [
		{"seat": 0, "kind": "human", "connected": true},
		{"seat": 1, "kind": "human", "connected": false},
		{"seat": 2, "kind": "human", "connected": true, "away": true},
		{"seat": 3, "kind": "human", "connected": true, "substituted": true},
		{"seat": 4, "kind": "bot", "connected": true}]}
	var tv := TeaseRules.table_from_view(v, [0], "client")
	var gone: Array = (tv.seats as Array).map(func(d): return bool(d.gone))
	check(tv.mode == "client" and tv.phase == "drawn" and int(tv.turn) == 2 and gone == [false, true, true, true, false]
		and bool(tv.seats[0].off) and not bool(tv.seats[1].off) and bool(tv.seats[4].bot) and not bool(tv.seats[3].bot),
		"F: table_from_view (%s)" % str(tv))
	check(NetProtocol.make_fx_request({"k": "ball", "to": 2}) == {"t": "fx", "k": "ball", "to": 2}, "F: Wunsch Kugel")
	check(NetProtocol.make_fx_request({"k": "react", "r": "daumen", "to": 1}) == {"t": "fx", "k": "react", "r": "daumen"},
		"F: Wunsch Reaktion ohne Ziel")
	for bad in [{"k": "ball"}, {"k": "ball", "to": -1}, {"k": "ball", "to": 10}, {"k": "ball", "to": "1"}, {"k": "ball", "to": 1.5},
			{"k": "react"}, {"k": "react", "r": "gaehnen"}, {"k": "gaehnen", "to": 1}, {"k": 3, "to": 1}, {}]:
		check(NetProtocol.make_fx_request(bad).is_empty(), "F: ungültiger Wunsch %s" % str(bad))
	var raw := NetProtocol.decode('{"t":"fx","k":"snore","to":1,"from":5,"extra":"x"}')
	check(NetProtocol.clean_client_message(raw) == {"t": "fx", "k": "snore", "to": 1}, "F: clean_client_message fx (ohne fremde Felder)")
	check(NetProtocol.clean_client_message(NetProtocol.decode('{"t":"fx","k":"boom"}')).is_empty(), "F: kaputtes fx verworfen")
	check(NetProtocol.clean_client_message(NetProtocol.decode('{"t":"fx_pref","off":true,"x":1}')) == {"t": "fx_pref", "off": true},
		"F: fx_pref")
	check(NetProtocol.clean_client_message(NetProtocol.decode('{"t":"fx_pref","off":"ja"}')).is_empty(), "F: fx_pref ohne bool verworfen")
	check(NetProtocol.make_fx("react", 2, 4, "lachen") == {"t": "fx", "k": "react", "from": 2, "r": "lachen"}
		and NetProtocol.make_fx("alarm", 2, 4) == {"t": "fx", "k": "alarm", "from": 2, "to": 4}, "F: make_fx")
	check(NetProtocol.clean_fx(NetProtocol.decode('{"t":"fx","k":"ball","from":0,"to":2}')) == {"t": "fx", "k": "ball", "from": 0, "to": 2},
		"F: clean_fx")
	check(NetProtocol.clean_fx({"t": "fx", "k": "ball", "from": 2, "to": 2}).is_empty() and NetProtocol.clean_fx({"t": "fx", "k": "ball",
		"to": 2}).is_empty() and NetProtocol.clean_fx({"t": "fx", "k": "react", "from": 1, "r": "x"}).is_empty(), "F: clean_fx verwirft")
	check(NetProtocol.clean_fx_no({"why": "busy"}) == "busy" and NetProtocol.clean_fx_no({"why": "early"}) == ""
		and NetProtocol.clean_fx_no({}) == "", "F: clean_fx_no")
	check(NetProtocol.clean_fx_offs({"seats": [3, 1, 3, -1, 12, "2", 0]}) == [0, 1, 3] and NetProtocol.clean_fx_offs({"seats": "1"}) == []
		and NetProtocol.make_fx_offs([2, 0]) == {"t": "fx_offs", "seats": [0, 2]}, "F: fx_offs")
	# unbekannte künftige Typen gehen weiter unverändert an die Spielsteuerung (sie prüft selbst)
	check(NetProtocol.clean_client_message({"t": "fx_future", "a": 1}) == {"t": "fx_future", "a": 1}, "F: unbekannte Typen")
