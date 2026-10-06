extends SceneTree
# Director (Modul F1b, Tischregie): Reihenfolge, Abgleich nach den Ereignissen, doppeltes Tempo bei Rückstand > 3,
# Überspringen bei Rückstand > 8 (mit Abgleich auf die letzte Sicht), flush.

var ok := 0
var fails := 0


class Mock:
	extends RefCounted
	var log: Array = []
	var speeds: Array = []
	var dur := 0.5

	func play_event(ev: Dictionary, speed: float) -> float:
		log.append("play:" + str(ev["e"]))
		speeds.append(speed)
		return dur

	func skip_event(ev: Dictionary) -> void:
		log.append("skip:" + str(ev["e"]))

	func apply_view(view: Dictionary) -> void:
		log.append("view:" + str(view["n"]))


func check(cond: bool, what: String) -> void:
	if cond:
		ok += 1
	else:
		fails += 1
		print("FAIL: " + what)


func _evs(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({"e": "e%d" % i})
	return out


func _init() -> void:
	# Grundablauf: Ereignisse nacheinander, danach die Sicht
	var d := Director.new()
	var m := Mock.new()
	d.handler = m
	d.auto_process = false
	d.enqueue(_evs(2), {"n": 1})
	check(m.log == ["play:e0"], "erstes Ereignis sofort: %s" % [m.log])
	check(d.is_busy() and d.backlog() == 1, "wartet, ein Ereignis offen")
	check(d.upcoming_view().get("n") == 1, "Zielsicht sichtbar")
	d.step(0.3)
	check(m.log.size() == 1, "vor Ablauf der Dauer kein nächstes Ereignis")
	d.step(0.3)
	check(m.log == ["play:e0", "play:e1"], "zweites Ereignis nach der Dauer")
	d.step(0.6)
	check(m.log == ["play:e0", "play:e1", "view:1"], "danach Abgleich: %s" % [m.log])
	check(not d.is_busy(), "fertig")
	check(m.speeds == [1.0, 1.0], "normales Tempo")
	# Rückstand > 3 → doppelt so schnell, bis er wieder klein ist
	m.log.clear()
	m.speeds.clear()
	d.enqueue(_evs(5), {"n": 2})
	for i in 20:
		d.step(0.5)
	check(m.speeds[0] == Director.FAST_SPEED, "Rückstand 5: doppelt so schnell")
	check(m.speeds[-1] == 1.0, "am Ende wieder normal: %s" % [m.speeds])
	check(m.log[-1] == "view:2", "Sicht zuletzt")
	# Rückstand > 8 → überspringen und Endzustand setzen
	m.log.clear()
	d.enqueue(_evs(10), {"n": 3})
	check(m.log.count("play:e0") == 0 and m.log.count("skip:e0") == 1, "großer Rückstand: übersprungen")
	check(m.log[-1] == "view:3" and not d.is_busy(), "Endzustand der letzten Sicht gesetzt: %s" % [m.log])
	check(d.skipped == 10, "10 übersprungen")
	# Laufende Animation wird abgekürzt, wenn während des Wartens > 8 nachkommen
	m.log.clear()
	d.enqueue(_evs(1), {"n": 4})
	check(m.log == ["play:e0"], "spielt")
	for k in 3:
		d.enqueue(_evs(3), {"n": 5 + k})
	d.step(0.01)
	check(m.log.has("view:7") and not m.log.has("play:e1"), "Warten abgekürzt, übersprungen bis zur letzten Sicht: %s" % [m.log])
	# Mehrere Abschnitte ohne Rückstand: jede Sicht nach ihren Ereignissen
	m.log.clear()
	d.enqueue(_evs(1), {"n": 8})
	d.enqueue(_evs(1), {"n": 9})
	for i in 6:
		d.step(0.5)
	check(m.log == ["play:e0", "view:8", "play:e0", "view:9"], "Abschnitte in Reihenfolge: %s" % [m.log])
	# flush
	m.log.clear()
	d.enqueue(_evs(2), {"n": 10})
	d.flush()
	check(m.log[-1] == "view:10" and not d.is_busy(), "flush setzt den Endzustand")
	# Ereignis ohne Dauer blockiert nicht
	m.dur = 0.0
	m.log.clear()
	d.enqueue(_evs(3), {"n": 11})
	check(m.log == ["play:e0", "play:e1", "play:e2", "view:11"], "Ereignisse ohne Animation laufen durch")
	# Buchungen ohne Animation (quiet_events) zählen nicht zum Rückstand: 3 echte + „turn“ bleibt normales Tempo
	m.dur = 0.5
	m.log.clear()
	m.speeds.clear()
	d.quiet_events = {"turn": true}
	d.enqueue([{"e": "gamble_roll"}, {"e": "draw"}, {"e": "stake_back"}, {"e": "turn"}], {"n": 12})
	check(m.speeds[0] == 1.0, "„turn“ zählt nicht zum Rückstand: %s" % [m.speeds])
	for i in 6:
		d.step(0.5)
	check(m.log[-1] == "view:12", "Abgleich danach")
	d.quiet_events = {}
	m.speeds.clear()
	d.enqueue([{"e": "gamble_roll"}, {"e": "draw"}, {"e": "stake_back"}, {"e": "turn"}], {"n": 13})
	check(m.speeds[0] == Director.FAST_SPEED, "ohne quiet_events doppelt so schnell")
	d.flush()
	d.free()
	print("RESULT: %d ok" % ok)
	quit(0 if fails == 0 else 1)
