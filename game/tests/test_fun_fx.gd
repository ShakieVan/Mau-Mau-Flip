extends SceneTree
# Beta 1.4.4, Ostereier Teil 1 (lokal): Mau-Katze (Auslöser, Abklingzeit, höchstens einmal je Spieler, weggeschoben, „reduziert“),
# Himmel (Abstände, nur bei Ruhe), „Autsch!“/Applaus, Spaßtitel, Zähler der Statistik, Geheimtipp im Logo.

const CleanExit := preload("res://tests/clean_exit.gd")
var ok := 0
var failed := 0


func check(cond: bool, text: String) -> void:
	if cond:
		ok += 1
	else:
		failed += 1
		print("FAIL: ", text)


func _initialize() -> void:
	call_deferred("run")


func make() -> FunFx:
	var t := Control.new()
	t.size = Vector2(1600, 720)
	root.add_child(t)
	var bg := ColorRect.new()
	t.add_child(bg)
	var world := Node2D.new()
	t.add_child(world)
	var f := FunFx.new()
	f.mount(t, bg, world)
	f.auto_process = false
	f.cat_chance = 1.0
	f.rng.seed = 7
	f.set_pile(Vector2(623, 320), 116.0)
	return f


static func view(turn: int, top := 5, draw := 40, phase := "turn") -> Dictionary:
	return {"turn": turn, "top": {"id": top}, "draw_count": draw, "phase": phase}


func run() -> void:
	# --- Katze
	var f := make()
	f.on_view(view(1))
	f.tick(24.0)
	check(not f.cat.active() and f.cats_started == 0, "Katze: vor 25 s nichts")
	f.tick(1.5)
	check(f.cat.active() and f.cats_started == 1 and f.cat_used.has(1), "Katze: nach 25 s Wartezeit tapst sie herein")
	f.tick(0.5)
	check(f.cats_started == 1, "Katze: höchstens einmal je Zug")
	for i in 100:
		f.tick(0.1)
	check(f.cat.st == "sleep" and absf(f.cat.position.x - 623.0) < 1.0, "Katze: liegt nach dem Gehen auf dem Ziehstapel (%s)" % f.cat.st)
	var hit_pos: Vector2 = f.cat.position + Vector2(0, -16)
	check(f.cat.hit(hit_pos) and not f.cat.hit(hit_pos + Vector2(200, 0)), "Katze: Treffer nur auf der Katze (Ziehen sonst frei)")
	# Zugwechsel: sie geht
	f.on_view(view(2, 6, 39))
	for i in 60:
		f.tick(0.1)
	check(not f.cat.active(), "Katze: beim nächsten Zug verschwunden")
	# Spieler 1 ein zweites Mal: nicht noch einmal
	f.on_view(view(1, 7, 38))
	f.tick(30.0)
	check(f.cats_started == 1, "Katze: bei demselben Spieler höchstens einmal je Partie")
	# anderer Spieler darf
	f.on_view(view(2, 8, 38))
	f.tick(26.0)
	check(f.cats_started == 2 and f.cat.active(), "Katze: anderer Spieler bekommt sie")
	# Tipp schiebt weg
	for i in 100:
		f.tick(0.1)
	check(f.tap(f.cat.position + Vector2(0, -16)), "Katze: Tipp wird verbraucht")
	check(f.cat.st == "hopdown" and f.cat.angry, "Katze: springt beleidigt davon")
	for i in 60:
		f.tick(0.1)
	check(not f.cat.active(), "Katze: nach dem Wegschieben verschwunden")
	check(not f.tap(Vector2(10, 10)), "Katze: Tipp ohne Katze wird nicht verbraucht")
	# neue Partie: Zählung zurück
	f.on_event({"e": "round_start", "round": 1})
	check(f.cat_used.is_empty(), "Katze: neue Partie löscht die Einmal-Liste")
	# Runde vorbei: keine Katze
	f.on_view(view(3, 1, 30, "round_over"))
	f.tick(40.0)
	check(f.cats_started == 2, "Katze: nicht am Rundenende")
	# Animation läuft: abwarten
	var g := make()
	g.busy_override = 1
	g.on_view(view(0))
	g.tick(40.0)
	check(not g.cat.active(), "Katze: nicht während einer Animation")
	g.busy_override = 0
	g.tick(0.1)
	check(g.cat.active(), "Katze: kommt, sobald Ruhe ist")
	# Chance 0
	var z := make()
	z.cat_chance = 0.0
	z.on_view(view(0))
	z.tick(40.0)
	check(not z.cat.active() and z.cats_started == 0, "Katze: Zufall entscheidet (Chance 0)")
	# reduziert
	var r := make()
	r.on_view(view(0))
	r.set_reduced(true)
	r.tick(60.0)
	check(not r.cat.active() and r.cats_started == 0, "reduziert: keine Katze")
	# Wartezeit beginnt neu, wenn der Spieler etwas tut (Stapel ändert sich)
	var w := make()
	w.on_view(view(0, 5, 40))
	w.tick(20.0)
	w.on_view(view(0, 5, 39))
	w.tick(10.0)
	check(not w.cat.active(), "Katze: Wartezeit beginnt nach einer Aktion neu")

	# --- Himmel
	var s := make()
	s.on_view(view(0))
	var guard := 0
	while s.sky_started == 0 and guard < 2000:
		s.tick(0.5)
		guard += 1
	check(s.sky_started == 1 and s.sky.kind == "butterfly", "Himmel: tagsüber ein Schmetterling (%s)" % s.sky.kind)
	check(s.now >= FunFx.SKY_MIN_S and s.now <= FunFx.SKY_MAX_S + 1.0, "Himmel: erstes Mal nach 60 bis 180 s (%.1f)" % s.now)
	for i in 21:
		s.tick(0.5)
	check(not s.sky.active(), "Himmel: Schmetterling fliegt nach wenigen Sekunden hinaus")
	var t0 := s.now
	s.tick(FunFx.SKY_MIN_S - 14.0)
	check(s.sky_started == 1, "Himmel: Abklingzeit mindestens 60 s")
	guard = 0
	while s.sky_started == 1 and guard < 2000:
		s.tick(0.5)
		guard += 1
	check(s.sky_started == 2 and s.now - t0 <= FunFx.SKY_MAX_S + 1.0, "Himmel: nächstes Mal innerhalb von 180 s")
	var n := make()
	n.set_night(1.0)
	n.on_view(view(0))
	guard = 0
	while n.sky_started == 0 and guard < 2000:
		n.tick(0.5)
		guard += 1
	check(n.sky.kind == "star", "Himmel: nachts eine Sternschnuppe (%s)" % n.sky.kind)
	var b := make()
	b.busy_override = 1
	b.on_view(view(0))
	b.tick(400.0)
	check(b.sky_started == 0, "Himmel: nicht während einer Animation")
	var rd := make()
	rd.on_view(view(0))
	rd.set_reduced(true)
	rd.tick(400.0)
	check(rd.sky_started == 0 and not rd.sky.active(), "reduziert: kein Himmel")
	var bg := make()
	bg.big = true
	bg.on_view(view(0))
	bg.tick(400.0)
	check(bg.sky_started == 0, "großer Modus: ruhiger Himmel")

	# --- Stempel und Applaus
	var strafe := {"e": "draw", "seat": 1, "count": 5, "reason": "strafe"}
	check(FunFx.is_autsch(strafe, 1), "Autsch: +5 bei 1 Karte")
	check(not FunFx.is_autsch(strafe, 2), "Autsch: nicht bei 2 Karten")
	check(not FunFx.is_autsch({"e": "draw", "seat": 1, "count": 1, "reason": "strafe"}, 1), "Autsch: nicht bei +1")
	check(not FunFx.is_autsch({"e": "draw", "seat": 1, "count": 5, "reason": "zug"}, 1), "Autsch: nicht beim freiwilligen Ziehen")
	check(FunFx.is_autsch({"e": "draw", "seat": 1, "count": 3, "reason": "strafe"}, 1), "Autsch: Wünscher +2 / Farbjagd (ab 2)")
	var e := make()
	e.on_event(strafe, 1)
	e.on_event(strafe, 4)
	e.on_event({"e": "finish", "seat": 0})
	check(e.stamps == 1 and e.applauses == 1, "Stempel nur bei Autsch, Applaus bei Mau-Mau")

	# --- Titel und Zähler
	check(FunTitles.earned({}).is_empty(), "Titel: ohne Zähler keiner")
	var d := {"gezogen": 120, "erwischt_selbst": 6, "gluecksspiel_max": 10, "aussetzen": 12, "flip": 11, "kartentausch": 9}
	var ts := FunTitles.earned(d)
	check(ts.size() == 3 and ts[0]["key"] == "gezogen", "Titel: höchstens drei, stärkster zuerst")
	var one := FunTitles.earned({"flip": 10})
	check(one.size() == 1 and one[0]["title"] == "Flipper", "Titel: Schwelle erreicht ergibt Flipper")
	check(FunTitles.earned({"flip": 9}).is_empty(), "Titel: knapp darunter keiner")
	var st := AppStats.new("user://test_fun_stats_%d.json" % Time.get_ticks_usec())
	st.record([{"e": "draw", "seat": 1, "count": 5, "reason": "strafe"}, {"e": "draw", "seat": 0, "count": 1, "reason": "zug"},
		{"e": "draw", "seat": 1, "count": 6, "reason": "join"}, {"e": "skip", "seat": 1}, {"e": "skip", "seat": 0}], {"seat": 1, "hand": [1]}, "solo")
	check(st.value("gezogen") == 5 and st.value("aussetzen") == 1, "Statistik: gezogene Karten (ohne Dazuholen) und Aussetzen des eigenen Platzes")
	st.data["gezogen"] = 70
	check(st.titles().size() == 1 and st.titles()[0]["key"] == "gezogen", "Statistik: titles() liefert Ziehkönig")
	st.reset()
	check(st.titles().is_empty(), "Statistik: nach dem Zurücksetzen keine Titel")

	# --- Logo-Geheimtipp
	check(FunLogo.region(Vector2(0.5, 0.45)) == "cat", "Logo: Mitte ist die Katze")
	check(FunLogo.region(Vector2(255.0 / 800.0, 190.0 / 450.0)) == "sun", "Logo: Sonne")
	check(FunLogo.region(Vector2(565.0 / 800.0, 205.0 / 450.0)) == "moon", "Logo: Mond")
	check(FunLogo.region(Vector2(0.05, 0.05)) == "", "Logo: Rand ist nichts")
	var fl := FunLogo.new()
	var fired := false
	for i in 6:
		fired = fired or fl.register_tap(1000 + i * 300)
	check(not fired and fl.count() == 6, "Logo: 6 Tipps lösen nichts aus")
	check(fl.register_tap(1000 + 6 * 300), "Logo: der 7. schnelle Tipp löst aus")
	check(fl.count() == 0, "Logo: Zählung beginnt neu")
	var slow := FunLogo.new()
	var any := false
	for i in 10:
		any = any or slow.register_tap(i * 1500)
	check(not any, "Logo: langsame Tipps zählen nicht")

	print("RESULT: %d ok, %d failed" % [ok, failed])
	await CleanExit.finish(self, 1 if failed else 0)
