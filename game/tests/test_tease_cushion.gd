extends SceneTree
# Mau-Mau Flip (Beta 1.6.6, Furzkissen, docs/module/eastereggs2.md Abschnitt 12): Regeln (TeaseRules) und Protokoll (NetProtocol), rein
# und mit eingespritzter Uhr und eingespritztem Zufall.
#  A  Wer darf auf wen: andere Menschen und Bots, nie sich selbst, nicht auf Abwesende, nicht bei Necken aus (Ziel oder Leger), nur in
#     den Zugphasen; Übung nur auf Bots, Weitergeben nichts; Bots und Wartende legen nie.
#  B  Nur eins je Ziel (busy), Zufallssperre des Legers 1–3 min (rate; erst die Sperre, dann das Ziel); cushion_block_ms aus dem Zufall.
#  C  Spiegel des Legers: Bestätigung sperrt nur die Mindestzeit, kissen_pop räumt ab; Kissen gehen in keinen Eimer.
#  D  Verfall: Rundenende (note_turn außerhalb der Zugphasen) und seats/reset; die Sperre überdauert das Rundenende.
#  E  Auslöser: play, draw, accept, stake – nicht mau, catch, color, keep, next_round, undo …
#  F  Protokoll: Wunsch {k:"kissen", to, reveal}, Bestätigung, kissen_pop (from nur bei reveal bzw. in der Kopie an den Leger), fx_no mit
#     k:"kissen", Bereinigung kaputter Nachrichten; ein Gast kann kein kissen_pop schicken.
#  G  Ältere Geräte (bis 1.6.5): ihre Prüfung kennt nur snore/alarm/ball/react – beide neuen Arten fallen dort heraus.
#  H  Beta 1.6.8 (Nutzerbefund S10): Restdauer left nur für den Leger – Bestätigung und fx_no rate mit left, Spiegel sperrt genau so lange
#     (Sperre 150 s: bei 61 s und 149 s gesperrt, ab 150 s frei), fx_no rate mit left setzt die Sperre, ohne left wie bis 1.6.7 (60 s),
#     Bereinigung (geklemmt, kaputt → weg), left nur bei kissen/rate.

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


func kissen(to, reveal := false) -> Dictionary:
	return {"k": "kissen", "to": to, "reveal": reveal}


func run() -> void:
	var t := tbl()
	var now := 100000

	# ---------- A: Ziele, Absender, Phasen, Spielarten
	var r := fresh()
	check(r.check(0, kissen(2), t, now) == "", "A: auf einen Menschen, der nicht am Zug ist")
	check(r.check(0, kissen(1), t, now) == "", "A: auf den Spieler am Zug (löst bei seinem nächsten Legen/Ziehen aus)")
	check(r.check(0, kissen(3), t, now) == "", "A: auf einen Computergegner")
	check(r.check(1, kissen(1), t, now) == "self", "A: nie auf sich selbst")
	check(r.check(0, kissen(7), t, now) == "target" and r.check(0, {"k": "kissen"}, t, now) == "target", "A: Platz außerhalb / ohne Ziel")
	check(r.check(0, kissen(2), tbl("turn", 1, "host", {2: {"gone": true}}), now) == "target", "A: nicht auf Abwesende/Vertretene")
	check(r.check(0, kissen(2), tbl("turn", 1, "host", {2: {"off": true}}), now) == "off", "A: Ziel hat Necken aus")
	check(r.check(0, kissen(2), tbl("turn", 1, "host", {0: {"off": true}}), now) == "off", "A: Leger hat Necken aus")
	check(r.check(3, kissen(1), t, now) == "sender" and r.check(-1, kissen(1), t, now) == "sender", "A: Bots und Wartende legen nie")
	for ph in TeaseRules.TURN_PHASES:
		check(fresh().check(0, kissen(2), tbl(ph, 1), now) == "", "A: in Phase %s" % ph)
	for ph in ["round_over", "game_over", "idle", ""]:
		check(fresh().check(0, kissen(2), tbl(ph, -1), now) == "phase", "A: nicht in Phase „%s“" % ph)
	check(fresh(0).check(0, kissen(3), tbl("turn", 0, "solo"), now) == "", "A: Übung: auf Bots")
	check(fresh(0).check(0, kissen(1), tbl("turn", 0, "solo"), now) == "target", "A: Übung: nie auf Menschen")
	check(fresh(0).check(0, kissen(3), tbl("turn", 0, "pass"), now) == "mode", "A: Weitergeben: nichts")
	check(TeaseRules.caps("solo").kinds == ["ball", "kissen"] and (TeaseRules.caps("host").kinds as Array).has("kissen")
		and (TeaseRules.caps("client").kinds as Array).has("kissen") and not (TeaseRules.caps("pass").kinds as Array).has("kissen"),
		"A: caps")
	check(not TeaseRules.FX_KINDS.has(TeaseRules.CUSHION_POP), "A: kissen_pop ist kein Wunsch")

	# ---------- B: eins je Ziel, Zufallssperre
	check(TeaseRules.cushion_block_ms(0.0) == 60000 and TeaseRules.cushion_block_ms(1.0) == 180000
		and TeaseRules.cushion_block_ms(0.5) == 120000 and TeaseRules.cushion_block_ms(-3.0) == 60000
		and TeaseRules.cushion_block_ms(7.0) == 180000, "B: Sperre aus dem Zufall: 1–3 min, geklemmt")
	var lo := 999999
	var hi := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 166
	for i in 2000:
		var ms := TeaseRules.cushion_block_ms(rng.randf())
		lo = mini(lo, ms)
		hi = maxi(hi, ms)
	check(lo >= 60000 and hi <= 180000 and lo < 63000 and hi > 177000, "B: über den ganzen Bereich verteilt (%d … %d)" % [lo, hi])
	r = fresh()
	var block := TeaseRules.cushion_block_ms(0.25)     # 90 s
	check(r.check(0, kissen(2, true), t, now) == "", "B: erstes Kissen")
	r.place_cushion(0, 2, true, now, block)
	check(r.cushion_at(2) == {"from": 0, "reveal": true, "at": now}, "B: Kissen liegt bei Ole (%s)" % str(r.cushion_at(2)))
	check(r.check(1, kissen(2), t, now) == "busy", "B: zweites Kissen beim selben Ziel: busy")
	check(r.check(1, kissen(3), t, now) == "", "B: anderes Ziel, anderer Leger: geht")
	check(r.check(0, kissen(3), t, now) == "rate", "B: der Leger ist gesperrt")
	check(r.check(0, kissen(2), t, now) == "rate", "B: erst die Sperre, dann das Ziel (rate vor busy)")
	check(r.check(0, kissen(3), t, now + block - 1) == "rate", "B: Sperre läuft bis kurz vor 90 s")
	check(r.check(0, kissen(3), t, now + block) == "", "B: danach frei")
	check(r.check(0, kissen(2), t, now + block) == "busy", "B: Ole hat noch sein Kissen")
	check(r.check(0, {"k": "ball", "to": 2}, t, now) == "" and r.check(0, {"k": "react", "r": "lachen"}, t, now) == "",
		"B: Kugel und Reaktion bleiben frei (eigene Sperren)")
	var taken := r.take_cushion(2)
	check(taken.from == 0 and bool(taken.reveal) and r.cushion_at(2).is_empty() and r.take_cushion(2).is_empty(), "B: take_cushion")
	check(r.check(1, kissen(2), t, now + 1) == "", "B: nach dem Pups wieder frei")

	# ---------- C: Spiegel des Legers, keine Eimer
	var m := fresh()
	m.commit(NetProtocol.make_cushion(1, 2, false), now)
	check(m.cushion_at(2).from == 1 and not bool(m.cushion_at(2).reveal), "C: Bestätigung merkt das eigene Kissen")
	check(int(m.cushion_until[1]) == now + TeaseRules.CUSHION_BLOCK_MIN_MS, "C: Spiegel sperrt nur die Mindestzeit")
	check(m.check(1, kissen(3), t, now + 59999) == "rate" and m.check(1, kissen(3), t, now + 60000) == "", "C: grau 1 min, dann aktiv")
	check(m.check(1, kissen(2), t, now + 60000) == "busy", "C: eigenes Kissen: busy")
	check(m.buckets.is_empty(), "C: Kissen gehen in keinen Eimer (auch nicht der Tisch-Eimer)")
	m.commit(NetProtocol.make_cushion_pop(2, false, 1), now + 1000)
	check(m.cushions.is_empty() and m.buckets.is_empty(), "C: kissen_pop räumt ab, ohne Eimer")
	m.commit(NetProtocol.make_cushion_pop(3, true, 0), now + 1000)
	check(m.cushions.is_empty(), "C: kissen_pop ohne liegendes Kissen schadet nicht")
	var b := fresh()
	for i in 9:
		b.place_cushion(0, 1 + i % 3, false, now, 0)
	check(b.check(1, {"k": "react", "r": "daumen"}, t, now) == "", "C: viele Kissen leeren den Tisch-Eimer nicht")

	# ---------- D: Verfall
	r = fresh()
	r.place_cushion(0, 2, false, now, 60000)
	r.place_cushion(1, 3, true, now, 60000)
	r.note_turn(2, "drawn", now + 10)
	check(r.cushions.size() == 2, "D: Zugwechsel lässt Kissen liegen")
	r.note_turn(-1, "round_over", now + 20)
	check(r.cushions.is_empty(), "D: Rundenende: Kissen verfallen still")
	check(r.cushion_until.has(0) and r.cushion_until.has(1), "D: die Sperre überdauert das Rundenende")
	r.note_turn(1, "turn", now + 30)
	check(r.check(0, kissen(2), t, now + 30) == "rate", "D: neue Runde: Leger noch gesperrt")
	r.place_cushion(2, 1, false, now + 40, 60000)
	r.note_events([{"e": "seats", "map": [0, 1, 2, 3], "join": 1}], now + 50)
	check(r.cushions.is_empty() and r.cushion_until.is_empty(), "D: seats leert Kissen und Sperren (Platznummern gelten nicht mehr)")
	r.place_cushion(2, 1, false, now, 60000)
	r.reset()
	check(r.cushions.is_empty() and r.cushion_until.is_empty(), "D: reset (neue Partie, Übernahme, welcome)")

	# ---------- E: Auslöser
	for a in ["play", "draw", "accept", "stake"]:
		check(TeaseRules.cushion_trigger({"a": a, "card": 3}), "E: %s löst aus" % a)
	for a in ["mau", "catch", "color", "keep", "next_round", "undo", "challenge", "press", "stop", "discard_pick", "", "fx"]:
		check(not TeaseRules.cushion_trigger({"a": a}), "E: %s löst nicht aus" % a)
	check(not TeaseRules.cushion_trigger({}) and not TeaseRules.cushion_trigger({"a": 3}), "E: kaputte Aktion löst nicht aus")

	# ---------- F: Protokoll
	check(NetProtocol.make_fx_request(kissen(2, true)) == {"t": "fx", "k": "kissen", "to": 2, "reveal": true}, "F: Wunsch mit Namen")
	check(NetProtocol.make_fx_request(kissen(2, false)) == {"t": "fx", "k": "kissen", "to": 2, "reveal": false}, "F: Wunsch geheim")
	check(NetProtocol.make_fx_request({"k": "kissen", "to": 2})["reveal"] == false
		and NetProtocol.make_fx_request({"k": "kissen", "to": 2, "reveal": "ja"})["reveal"] == false, "F: nur true verrät den Namen")
	for bad in [{"k": "kissen"}, {"k": "kissen", "to": -1}, {"k": "kissen", "to": 10}, {"k": "kissen", "to": "1"},
			{"k": "kissen_pop", "to": 1}, {"k": "kissen_pop", "to": 1, "reveal": true, "from": 0}]:
		check(NetProtocol.make_fx_request(bad).is_empty(), "F: ungültiger Wunsch %s" % str(bad))
	var raw := NetProtocol.decode('{"t":"fx","k":"kissen","to":1,"reveal":true,"from":3,"x":1}')
	check(NetProtocol.clean_client_message(raw) == {"t": "fx", "k": "kissen", "to": 1, "reveal": true},
		"F: clean_client_message kissen (ohne fremde Felder, from setzt der Gastgeber)")
	check(NetProtocol.clean_client_message(NetProtocol.decode('{"t":"fx","k":"kissen_pop","to":1,"reveal":true,"from":0}')).is_empty(),
		"F: ein Gast kann kein kissen_pop schicken")
	check(NetProtocol.make_cushion(1, 2, false) == {"t": "fx", "k": "kissen", "from": 1, "to": 2, "reveal": false}, "F: Bestätigung")
	check(NetProtocol.make_cushion_pop(2, false) == {"t": "fx", "k": "kissen_pop", "to": 2, "reveal": false}, "F: Pups geheim ohne from")
	check(NetProtocol.make_cushion_pop(2, false, 1) == {"t": "fx", "k": "kissen_pop", "to": 2, "reveal": false, "from": 1},
		"F: Kopie an den Leger mit from")
	check(NetProtocol.make_cushion_pop(2, true, 1) == {"t": "fx", "k": "kissen_pop", "to": 2, "reveal": true, "from": 1}, "F: mit Namen")
	# Gast-Seite
	var c_ok := NetProtocol.decode('{"t":"fx","k":"kissen","from":1,"to":2,"reveal":false}')
	check(NetProtocol.clean_fx(c_ok) == NetProtocol.make_cushion(1, 2, false), "F: clean_fx Bestätigung")
	for bad in [{"t": "fx", "k": "kissen", "from": 1, "to": 2}, {"t": "fx", "k": "kissen", "from": 2, "to": 2, "reveal": true},
			{"t": "fx", "k": "kissen", "to": 2, "reveal": true}, {"t": "fx", "k": "kissen", "from": 1, "to": 2, "reveal": 1}]:
		check(NetProtocol.clean_fx(bad).is_empty(), "F: clean_fx verwirft %s" % str(bad))
	check(NetProtocol.clean_fx(NetProtocol.decode('{"t":"fx","k":"kissen_pop","to":2,"reveal":false}')) == NetProtocol.make_cushion_pop(2, false),
		"F: clean_fx Pups geheim")
	check(NetProtocol.clean_fx(NetProtocol.decode('{"t":"fx","k":"kissen_pop","to":2,"reveal":true,"from":0,"x":5}')) == NetProtocol.make_cushion_pop(2, true, 0),
		"F: clean_fx Pups mit Namen (ohne fremde Felder)")
	for bad in [{"t": "fx", "k": "kissen_pop", "to": 2, "reveal": true}, {"t": "fx", "k": "kissen_pop", "to": 2},
			{"t": "fx", "k": "kissen_pop", "to": 2, "reveal": false, "from": 2}, {"t": "fx", "k": "kissen_pop", "to": 2, "reveal": false, "from": "0"},
			{"t": "fx", "k": "kissen_pop", "to": -1, "reveal": false}, {"t": "fx", "k": "kissen_pop", "reveal": false}]:
		check(NetProtocol.clean_fx(bad).is_empty(), "F: clean_fx verwirft %s" % str(bad))
	check(NetProtocol.make_fx_no("busy", "kissen") == {"t": "fx_no", "why": "busy", "k": "kissen"}
		and NetProtocol.make_fx_no("rate", "kissen") == {"t": "fx_no", "why": "rate", "k": "kissen"}, "F: fx_no mit k:kissen (ohne Restzeit)")
	check(NetProtocol.make_fx_no("busy", "snore") == {"t": "fx_no", "why": "busy"} and NetProtocol.make_fx_no("rate") == {"t": "fx_no", "why": "rate"},
		"F: übrige fx_no wie in 1.6.3")
	check(NetProtocol.clean_fx_no_kind({"why": "busy", "k": "kissen"}) == "kissen" and NetProtocol.clean_fx_no_kind({"why": "busy"}) == ""
		and NetProtocol.clean_fx_no_kind({"why": "busy", "k": "ball"}) == "" and NetProtocol.clean_fx_no_kind({"k": 3}) == "", "F: clean_fx_no_kind")

	# ---------- G: ältere Geräte (1.6.3–1.6.5): ClientTable/Lite prüfen fx mit make_fx_request bzw. FX_KINDS.indexOf –
	# diese Liste kannte nur die vier alten Arten. Beide neuen Arten fallen dort heraus (kein Signal, kein Effekt, Lite: null).
	var old_kinds := ["snore", "alarm", "ball", "react"]
	for k in [TeaseRules.CUSHION, TeaseRules.CUSHION_POP]:
		check(not old_kinds.has(k), "G: „%s“ ist für Geräte bis 1.6.5 unbekannt" % k)
	check(TeaseRules.FX_KINDS.slice(0, 4) == old_kinds, "G: alte Arten unverändert und in derselben Reihenfolge")

	# ---------- H: Beta 1.6.8 – Restdauer der Sperre für den Leger
	var host := fresh()
	var blk := TeaseRules.cushion_block_ms(0.75)        # 150 s
	check(blk == 150000, "H: Zufall 0,75 → 150 s")
	host.place_cushion(1, 2, false, now, blk)
	check(host.cushion_left_ms(1, now) == 150000 and host.cushion_left_ms(1, now + 61000) == 89000
		and host.cushion_left_ms(1, now + 200000) == 0 and host.cushion_left_ms(0, now) == 0, "H: cushion_left_ms (Gastgeber)")
	var conf := NetProtocol.make_cushion(1, 2, false, blk)
	check(conf == {"t": "fx", "k": "kissen", "from": 1, "to": 2, "reveal": false, "left": 150000}, "H: Bestätigung mit left (%s)" % str(conf))
	check(NetProtocol.make_cushion(1, 2, false) == {"t": "fx", "k": "kissen", "from": 1, "to": 2, "reveal": false}, "H: ohne left wie bis 1.6.7")
	var wire := NetProtocol.decode(NetProtocol.encode(conf))
	check(NetProtocol.clean_fx(wire) == conf, "H: clean_fx behält left (%s)" % str(NetProtocol.clean_fx(wire)))
	var g := fresh()
	g.commit(NetProtocol.clean_fx(wire), now)
	check(g.check(1, kissen(3), t, now + 61000) == "rate", "H: Spiegel bei 61 s noch gesperrt")
	check(g.check(1, kissen(3), t, now + 149000) == "rate", "H: Spiegel bei 149 s noch gesperrt")
	check(g.check(1, kissen(3), t, now + 149999) == "rate" and g.check(1, kissen(3), t, now + 150000) == "", "H: Spiegel frei ab 150 s (wie der Gastgeber)")
	check(g.check(1, kissen(3), t, now + 151000) == "", "H: Spiegel bei 151 s frei")
	for c in [[{"left": 999999}, 180000], [{"left": 1234.6}, 1235], [{"left": 0}, 0], [{"left": -1}, -1], [{"left": "90000"}, -1],
			[{"left": null}, -1], [{"left": NAN}, -1], [{}, -1]]:
		check(NetProtocol.clean_cushion_left(c[0]) == c[1], "H: clean_cushion_left %s → %d (%d)" % [str(c[0]), c[1], NetProtocol.clean_cushion_left(c[0])])
	var bad_left := NetProtocol.clean_fx({"t": "fx", "k": "kissen", "from": 1, "to": 2, "reveal": true, "left": "viel"})
	check(bad_left == NetProtocol.make_cushion(1, 2, true), "H: kaputtes left fällt weg, die Bestätigung bleibt (%s)" % str(bad_left))
	var huge := NetProtocol.clean_fx({"t": "fx", "k": "kissen", "from": 1, "to": 2, "reveal": true, "left": 10000000})
	check(int(huge.get("left", -1)) == TeaseRules.CUSHION_BLOCK_MAX_MS, "H: left geklemmt auf höchstens 3 min")
	var old := fresh()
	old.commit(NetProtocol.clean_fx(NetProtocol.make_cushion(1, 2, false)), now)
	check(old.check(1, kissen(3), t, now + 59999) == "rate" and old.check(1, kissen(3), t, now + 60000) == "",
		"H: Gastgeber bis 1.6.7 (ohne left): Spiegel wie bisher 60 s")
	# fx_no rate mit left
	check(NetProtocol.make_fx_no("rate", "kissen", 89000) == {"t": "fx_no", "why": "rate", "k": "kissen", "left": 89000}, "H: fx_no rate mit left")
	check(NetProtocol.make_fx_no("busy", "kissen", 89000) == {"t": "fx_no", "why": "busy", "k": "kissen"}
		and NetProtocol.make_fx_no("rate", "ball", 89000) == {"t": "fx_no", "why": "rate"} and NetProtocol.make_fx_no("rate", "kissen") == {"t": "fx_no", "why": "rate", "k": "kissen"},
		"H: left nur bei kissen/rate")
	check(NetProtocol.clean_fx_no_left({"t": "fx_no", "why": "rate", "k": "kissen", "left": 89000}) == 89000
		and NetProtocol.clean_fx_no_left({"t": "fx_no", "why": "rate", "k": "kissen"}) == -1
		and NetProtocol.clean_fx_no_left({"t": "fx_no", "why": "busy", "k": "kissen", "left": 5}) == -1
		and NetProtocol.clean_fx_no_left({"t": "fx_no", "why": "rate", "left": 5}) == -1
		and NetProtocol.clean_fx_no_left({"t": "fx_no", "why": "rate", "k": "kissen", "left": -5}) == -1, "H: clean_fx_no_left")
	var n := fresh()
	n.note_cushion_wait(1, 89000, now)
	check(n.check(1, kissen(3), t, now + 88999) == "rate" and n.check(1, kissen(3), t, now + 89000) == "", "H: note_cushion_wait sperrt genau so lange")
	n.note_cushion_wait(1, -1, now + 100000)
	n.note_cushion_wait(-1, 5000, now + 100000)
	check(n.check(1, kissen(3), t, now + 100000) == "" and not n.cushion_until.has(-1), "H: note_cushion_wait ohne Restdauer/Platz ändert nichts")
	n.note_cushion_wait(1, 20000, now + 100000)
	check(n.check(1, kissen(3), t, now + 119999) == "rate" and n.cushions.is_empty(), "H: Sperre aus fx_no ohne Kissen am Ziel (kein busy erfunden)")
