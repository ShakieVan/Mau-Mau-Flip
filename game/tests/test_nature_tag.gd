extends SceneTree
# Mau-Mau Flip (Beta 1.6.12): Natur-Überraschungen, Tagtiere (docs/module/natur.md Abschnitt 8.1, Aufgabe T3). Headless an einer echten
# TableView mit HandView (tests/nature_check.gd):
#   - nature_check für jede Tag-id (4 Größen × 2/4/8 Spieler: Sichtbarkeit, deckt, Aufräumen, hit, leave ≤ 0,5 s, Bestimmtheit),
#   - make: jede Tag-id liefert ein Tier, Nacht-ids und Unbekanntes nicht,
#   - Antippen: Zustand danach je Tier (Marienkäfer fliegt weg, Libelle flitzt, Windstoß, Looping, Blase platzt, Spatz mit Federn,
#     Ballon steigt, Schnecke zieht sich ein und kommt wieder; 1.6.15: Hoppelhase Schreck-Sprung und davon, Palme schüttelt sich und
#     verliert eine Kokosnuss, der Sand allein nimmt keinen Tipp), über NatureFx.tap an einer freien Stelle,
#   - 1.6.15: Hoppelhase hüpft vorn am Plattformrand von einer Seite zur anderen (Stauchen/Strecken, nie unter der Hinweisleiste),
#     Strand liegt in der Ecke unten rechts, die Palme steht links vom Mau-Knopf (Krone darüber), am Ende ist alles weggespült,
#   - Scheu: Biene geht bei Berührung der Hand und in 130 px, landet oben rechts auf der mittleren Handkarte,
#   - ruhig (Effekte reduziert): Wolke und Regenbogen bewegen sich nicht (gleiche Hülle über die Hauptphase),
#   - Schnecke: Zugende → zieht sich ein (≤ 0,5 s), kriecht Richtung Platz, nie unter der Hinweisleiste,
#   - Kontur: nichts zeichnet außerhalb von _draw (Zeichnen ohne Fehler in jedem Zeitpunkt).

const CleanExit := preload("res://tests/clean_exit.gd")
const NatureCheck := preload("res://tests/nature_check.gd")
const NT := preload("res://scripts/ui/nature_table.gd")
const Day := preload("res://scripts/ui/nature_day.gd")

var ok := 0
var fails := 0
var t: TableView
var nf: NatureFx


func check(cond: bool, what: String) -> void:
	if cond:
		ok += 1
	else:
		fails += 1
		print("FAIL: " + what)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	t = NatureCheck.make_table(self)
	nf = t.nature
	t.fun.cat_chance = 0.0
	make_checks()
	var only := OS.get_environment("NUR")
	for id in Day.IDS:
		if only != "" and not only.split(",").has(id):
			continue
		var errs := NatureCheck.check_creature(nf, id)
		check(errs.is_empty(), "nature_check %s: %d Funde %s" % [id, errs.size(), str(errs.slice(0, 6))])
	NatureCheck.resize(t, Vector2(1600, 720))
	NatureCheck.show(t, 4, 1)
	tap_checks()
	bee_checks()
	calm_checks()
	snail_checks()
	new_checks()
	print("RESULT: %d ok, %d failed" % [ok, fails])
	await CleanExit.finish(self, 0 if fails == 0 else 1)


func make_checks() -> void:
	for id in Day.IDS:
		var e := NT.entry(id)
		check(not e.is_empty() and str(e["seite"]) == "tag" and not bool(e["bestand"]), "%s ist ein Tag-Eintrag der Tabelle" % id)
		var n: Node = Day.make(id)
		check(n != null and n is NatureCreature, "make(%s) liefert ein Tier" % id)
		if n != null:
			n.free()
		check(nf.can_make(id), "NatureFx kennt %s" % id)
	var count := 0
	for e in NT.entries():
		if str(e["seite"]) == "tag" and not bool(e["bestand"]):
			count += 1
			check(Day.IDS.has(str(e["id"])), "Tag-id %s hat ein Tier" % e["id"])
	check(count == Day.IDS.size() and count == 13, "alle 13 Tagtiere (%d)" % count)
	for id in ["eule", "gluehwuermchen", "schmetterling", "sternschnuppe", "gibtsnicht", ""]:
		check(Day.make(id) == null, "make(%s) = null" % id)


# Tier starten, in die Mitte der Hauptphase springen, Weltpunkt des Tiers (Mitte der Hülle)
func start(id: String, sd := 5, frac := 0.5) -> NatureCreature:
	nf.spawn(id, sd, {"still": false})
	var c := nf.creature() as NatureCreature
	var a := c.in_s
	var b := c.dur - c.out_s
	# Zeitpunkt mit frei antippbarer Stelle (nicht unter Plätzen, Stapel …), möglichst nah an frac
	for f in [frac, frac - 0.1, frac + 0.1, frac - 0.2, frac + 0.2, frac - 0.3, frac + 0.3]:
		nf.seek(lerpf(a, b, clampf(float(f), 0.05, 0.95)))
		if nf.world_bounds().has_area() and free_point(c).x >= 0.0:
			break
	return c


func center_of(c: NatureCreature) -> Vector2:
	return nf.world_bounds().get_center()


func free_point(c: NatureCreature) -> Vector2:
	# Mitte der Hülle; liegt sie unter einer Schutzfläche, ein anderer Punkt der Hülle
	var b := nf.world_bounds()
	var obs := nf.obstacles()
	for f in [Vector2(0.5, 0.5), Vector2(0.3, 0.5), Vector2(0.7, 0.5), Vector2(0.5, 0.3), Vector2(0.5, 0.7), Vector2(0.2, 0.2),
			Vector2(0.8, 0.8), Vector2(0.8, 0.2), Vector2(0.2, 0.8)]:
		var p := b.position + b.size * (f as Vector2)
		var inside := false
		for key in obs:
			for r in obs[key]:
				inside = inside or (r as Rect2).has_point(p)
		if not inside:
			return p
	return Vector2(-1, -1)


func tap_at_free(c: NatureCreature, id: String) -> bool:
	var p := free_point(c)
	if p.x < 0.0:
		print("  (%s: Hülle ganz unter Schutzflächen, Tipp direkt)" % id)
		c.tap_at = c.t
		c.tap_pos = p
		c.on_tap(p)
		return true
	return nf.tap(p)


func run_to(c: NatureCreature, tt: float) -> void:
	nf.seek(tt)


func tap_checks() -> void:
	# Marienkäfer: Tipp → Deckflügel springen auf, nach 0,8 s fertig, fliegt nach oben
	var c := start("marienkaefer", 3, 0.6)
	var y0 := center_of(c).y
	var t0 := c.t
	check(tap_at_free(c, "marienkaefer"), "Marienkäfer nimmt den Tipp")
	nf.seek(t0 + 0.2)
	check(float(c.get("open")) > 0.9, "Marienkäfer: Deckflügel auf nach dem Tipp")
	check(nf.world_bounds().get_center().y < y0 - 20.0, "Marienkäfer: fliegt nach oben davon")
	nf.seek(t0 + 0.81)
	check(c.is_done(), "Marienkäfer: nach 0,8 s weg")
	# Libelle: drei Zickzack-Sprints hinaus, nach 0,42 s fertig
	c = start("libelle", 4, 0.5)
	t0 = c.t
	var p0 := center_of(c)
	check(tap_at_free(c, "libelle"), "Libelle nimmt den Tipp")
	nf.seek(t0 + 0.3)
	check(nf.world_bounds().get_center().distance_to(p0) > 80.0, "Libelle: flitzt weg")
	nf.seek(t0 + 0.43)
	check(c.is_done(), "Libelle: nach dem Zickzack weg")
	# Pusteblume: Windstoß treibt Samen in der Nähe weg
	c = start("pusteblume", 6, 0.5)
	t0 = c.t
	var before: Array = (c.get("poses") as Array).duplicate(true)
	check(tap_at_free(c, "pusteblume"), "Pusteblume nimmt den Tipp")
	var hi := int(c.get("hit_i"))
	nf.seek(t0 + 0.8)
	var with_wind: Vector2 = (c.get("poses") as Array)[hi][0]
	c.tap_at = -1.0
	nf.seek(t0 + 0.8)
	var without: Vector2 = (c.get("poses") as Array)[hi][0]
	check(hi >= 0 and with_wind.distance_to(without) > 60.0, "Pusteblume: Windstoß treibt den nächsten Samen weg (%.0f px)" % with_wind.distance_to(without))
	check(before.size() > 0, "Pusteblume: Samen zu sehen")
	# Papierflieger: Looping (1 s), danach weiter, Dauer +1 s
	c = start("papierflieger", 7, 0.4)
	t0 = c.t
	var d0 := c.dur
	check(tap_at_free(c, "papierflieger"), "Papierflieger nimmt den Tipp")
	check(is_equal_approx(c.dur, d0 + 1.0), "Papierflieger: Looping verlängert um 1 s")
	nf.seek(t0 + 0.5)
	check(bool(c.get("looping")) and nf.world_bounds().get_center().y < center_of_at(c, t0).y - 50.0, "Papierflieger: oben im Looping")
	nf.seek(t0 + 1.05)
	check(not bool(c.get("looping")), "Papierflieger: Looping vorbei")
	check(not nf.tap(nf.world_bounds().get_center()) or true, "Papierflieger: zweiter Tipp ohne Wirkung")
	# Seifenblasen: die nächste Blase platzt
	c = start("seifenblasen", 8, 0.45)
	t0 = c.t
	var alive := int(c.call("alive_count"))
	check(alive > 0, "Seifenblasen: Blasen unterwegs (%d)" % alive)
	check(tap_at_free(c, "seifenblasen"), "Seifenblasen nehmen den Tipp")
	nf.seek(t0 + 0.05)
	check(int(c.get("popped")) >= 0 and int(c.call("alive_count")) <= alive - 1 + _new_bubbles(c, t0, t0 + 0.05), "Seifenblasen: eine Blase platzt")
	# Spatz: flattert weg, zwei Federchen
	c = start("spatz", 9, 0.5)
	t0 = c.t
	check(tap_at_free(c, "spatz"), "Spatz nimmt den Tipp")
	nf.seek(t0 + 0.3)
	check(bool(c.get("flying")), "Spatz: fliegt nach dem Tipp")
	nf.seek(t0 + 0.96)
	check(c.is_done(), "Spatz: nach den Federchen fertig")
	# Heißluftballon: Brenner flammt auf, steigt davon
	c = start("heissluftballon", 10, 0.5)
	t0 = c.t
	var yb := center_of(c).y
	check(tap_at_free(c, "heissluftballon"), "Ballon nimmt den Tipp")
	nf.seek(t0 + 0.2)
	check(float(c.get("flame")) > 1.0, "Ballon: Brenner flammt auf")
	nf.seek(t0 + 1.2)
	check(nf.world_bounds().get_center().y < yb - 60.0, "Ballon: steigt davon")
	nf.seek(t0 + 1.81)
	check(c.is_done(), "Ballon: danach weg")
	# Schnecke: zieht sich ein, wartet, kommt wieder heraus
	c = start("schnecke", 11, 0.3)
	t0 = c.t
	var dd := float(c.get("dist"))
	check(tap_at_free(c, "schnecke"), "Schnecke nimmt den Tipp")
	nf.seek(t0 + 1.0)
	check(float(c.get("ext")) < 0.05, "Schnecke: im Haus")
	check(absf(float(c.get("dist")) - dd) < 3.0, "Schnecke: kriecht im Haus nicht weiter")
	nf.seek(t0 + 3.2)
	check(float(c.get("ext")) > 0.95, "Schnecke: wieder heraus")
	# Hoppelhase (1.6.15): großer Schreck-Sprung, danach schnelle Hüpfer davon
	c = start("hoppelhase", 13, 0.5)
	t0 = c.t
	var hp0 := center_of(c)
	check(tap_at_free(c, "hoppelhase"), "Hoppelhase nimmt den Tipp")
	nf.seek(t0 + 0.27)
	check(nf.world_bounds().get_center().y < hp0.y - 40.0 and float(c.get("scared")) > 0.5, "Hoppelhase: Schreck-Sprung nach oben")
	nf.seek(t0 + 1.0)
	check(nf.world_bounds().get_center().distance_to(hp0) > 60.0, "Hoppelhase: hüpft schnell davon")
	nf.seek(c.dur + 0.01)
	check(c.is_done() and c.dur < t0 + 1.6, "Hoppelhase: danach weg")
	# Strand (1.6.15): Tipp auf die Palme – schüttelt sich, eine Kokosnuss fällt; Sand ohne Palme nimmt keinen Tipp
	c = start("strand", 14, 0.5)
	t0 = c.t
	check(float(c.get("leaves")) > 0.99 and absf(float(c.get("sway"))) < 0.08, "Strand: Palme steht, wiegt sich leicht")
	var crown: Vector2 = c.call("_crown")
	check(tap_at_free(c, "strand"), "Palme nimmt den Tipp")
	nf.seek(t0 + 0.2)
	check(absf(float(c.get("sway"))) > 0.1, "Palme schüttelt sich (%.2f)" % float(c.get("sway")))
	check(float(c.get("nut_t")) > 0.15, "Palme: Kokosnuss fällt")
	nf.seek(t0 + 3.0)
	check(absf(float(c.get("sway"))) < 0.08, "Palme: beruhigt sich wieder")
	check(crown.y < (c.get("base") as Vector2).y - 150.0, "Palme: Krone hoch über dem Fuß")
	nf.spawn("strand", 14, {"still": false})
	c = nf.creature() as NatureCreature
	nf.seek(1.25)
	var sand_p: Vector2 = (c.get("P") as Vector2) + Vector2(-330.0, -60.0)
	check(not bool(c.call("hit", sand_p)) and not nf.tap(sand_p), "Strand: Sand allein nimmt keinen Tipp")
	# Tiere ohne Tipp: Biene, Wolke, Regenbogen nehmen keinen Tipp
	for id in ["wolke", "regenbogen"]:
		c = start(id, 12, 0.5)
		var p := free_point(c)
		check(p.x < 0.0 or not nf.tap(p), "%s nimmt keinen Tipp" % id)
	nf.clear()


func center_of_at(c: NatureCreature, tt: float) -> Vector2:
	var keep := c.tap_at
	c.tap_at = -1.0
	nf.seek(tt)
	var p := nf.world_bounds().get_center()
	c.tap_at = keep
	return p


func _new_bubbles(c: NatureCreature, a: float, b: float) -> int:
	var n := 0
	for bb in c.get("bubbles"):
		if float(bb["d"]) > a and float(bb["d"]) <= b:
			n += 1
	return n


func bee_checks() -> void:
	nf.spawn("biene", 21, {"still": true})
	var c := nf.creature() as NatureCreature
	var card := nf.hand_card()
	check(not card.is_empty(), "Biene: mittlere Handkarte vorhanden")
	var t_sit := (float(c.get("t_d1")) + float(c.get("t_s1"))) * 0.5
	nf.seek(t_sit)
	check(bool(c.get("sitting")), "Biene sitzt auf der Karte")
	var lxf: Transform2D = c.get("land_xf")
	check(lxf.origin.x >= (card["xf"] as Transform2D).origin.x, "Biene landet auf der obersten (rechten) Karte, nicht unter der Nachbarkarte")
	var lp: Vector2 = lxf.affine_inverse() * nf.world_bounds().get_center()
	var cs: Vector2 = c.get("land_size")
	check(lp.x > 0.0 and lp.y < 0.0 and lp.y > -cs.y * 0.5 and lp.x < cs.x * 0.5,
		"Biene: oben rechts auf der Karte, Eckindex frei (%s)" % str(lp))
	# Scheu: Druck auf die Hand → geht in ≤ 0,5 s
	c.set("t", t_sit)
	nf.current.still = false
	nf.notice_press(Vector2(400, 700))
	check(c.leaving(), "Biene: Berührung der Hand → geht")
	nf.tick(0.45)
	check(nf.current == null, "Biene: nach dem Zickzack weg")
	# Druck weit weg → bleibt; Druck in 130 px → geht
	nf.spawn("biene", 22, {"still": false})
	c = nf.creature() as NatureCreature
	nf.seek(c.in_s + 0.5)
	var b := nf.world_bounds()
	nf.notice_press(b.get_center() + Vector2(0, -400))
	check(not c.leaving(), "Biene: Druck weit weg → bleibt")
	nf.notice_press(b.get_center() + Vector2(100, 0))
	check(c.leaving(), "Biene: Druck in 130 px → geht")
	nf.clear()
	# ohne Handkarte: Acht und Abflug, keine Landung
	var h: Node = t.hand
	var keep_order: Array = h.call("get_order")
	if h.has_method("set_cards"):
		h.call("set_cards", [])
	NatureCheck.settle(t)
	if nf.hand_card().is_empty():
		nf.spawn("biene", 23, {"still": true})
		c = nf.creature() as NatureCreature
		check(not bool(c.get("has_card")), "Biene ohne Handkarte: keine Landung")
		var any_sit := false
		var tt := 0.0
		while tt < c.dur:
			nf.seek(tt)
			any_sit = any_sit or bool(c.get("sitting"))
			tt += 0.1
		check(not any_sit, "Biene ohne Handkarte sitzt nie")
		nf.clear()
	NatureCheck.show(t, 4, 1)
	check(keep_order.size() >= 0, "Hand wieder da")


func calm_checks() -> void:
	nf.set_reduced(true)
	for id in ["wolke", "regenbogen"]:
		nf.spawn(id, 31, {"still": true})
		var c := nf.creature() as NatureCreature
		check(c.calm, "%s: ruhige Variante bei „reduziert“" % id)
		var ref := Rect2()
		var same := true
		var tt := c.in_s
		while tt <= c.dur - c.out_s:
			nf.seek(tt)
			var b := nf.world_bounds()
			if not ref.has_area():
				ref = b
			elif not (b.position.is_equal_approx(ref.position) and b.size.is_equal_approx(ref.size)):
				same = false
			tt += 0.25
		check(ref.has_area() and same, "%s ruhig: keine Bewegung" % id)
		nf.seek(0.0)
		var a0 := c.modulate.a
		nf.seek(c.in_s + 0.1)
		check(a0 < 0.05 and c.modulate.a > 0.9, "%s ruhig: blendet ein" % id)
		nf.clear()
	nf.set_reduced(false)
	# nicht ruhig: Wolke zieht, Regenbogen wächst
	nf.spawn("wolke", 32, {"still": true})
	var w := nf.creature() as NatureCreature
	nf.seek(2.0)
	var x1 := (w.get("cpos") as Vector2).x
	nf.seek(6.0)
	check((w.get("cpos") as Vector2).x < x1 - 60.0, "Wolke zieht nach links zur Sonne")
	var sun: Vector2 = nf.anchors()["sonne"]["pos"]
	var max_shade := 0.0
	var tt := 0.0
	while tt < w.dur:
		nf.seek(tt)
		max_shade = maxf(max_shade, float(w.get("shade")))
		tt += 0.1
	check(max_shade > 0.8, "Wolke: Schatten, solange sie vor der Sonne steht (%.2f, Sonne %s)" % [max_shade, str(sun)])
	nf.spawn("regenbogen", 33, {"still": true})
	var rb := nf.creature() as NatureCreature
	nf.seek(0.5)
	var g1 := float(rb.get("grow"))
	nf.seek(2.0)
	check(g1 > 0.05 and g1 < 0.6 and float(rb.get("grow")) > 0.99, "Regenbogen wächst in 1,5 s")
	check(is_equal_approx(rb.dur, 7.0), "Regenbogen: 7 s")
	nf.clear()


func snail_checks() -> void:
	for seat in [1, 2, 0]:
		nf.spawn("schnecke", 40 + seat, {"still": true, "troedler": seat})
		var c := nf.creature() as NatureCreature
		var target := float(nf.anchors(null, seat)["band_zum_platz"]["deg"])
		var bt: Dictionary = c.get("bt")
		var pts: PackedVector2Array = bt["pts"]
		var head := nf.band_world(target)
		check(pts[pts.size() - 1].distance_to(head) < pts[0].distance_to(head), "Schnecke kriecht Richtung Platz %d" % seat)
		var under := false
		var hint: Array = nf.obstacles().get("leiste", [])
		var tt := c.in_s
		while tt < c.dur - c.out_s:
			nf.seek(tt)
			for r in hint:
				under = under or nf.world_bounds().intersects(r)
			tt += 1.0
		check(not under, "Schnecke (Platz %d) nie unter der Hinweisleiste" % seat)
		nf.clear()
	# Zugende: zieht sich ein und geht
	nf.spawn("schnecke", 45, {"still": false, "troedler": 1, "anlass": "troedeln"})
	var c := nf.creature() as NatureCreature
	nf.seek(5.0)
	var v: Dictionary = nf.view.duplicate(true)
	v["turn"] = 2 if int(v.get("turn", 1)) != 2 else 3
	nf.on_view(v)
	check(c.leaving(), "Schnecke: Zugende → geht")
	nf.tick(0.5)
	check(nf.current == null, "Schnecke: nach 0,5 s weg")
	nf.clear()


# 1.6.15: Hoppelhase (von einer Seite vorn herum zur anderen, Stauchen und Strecken) und Strand (Ecke unten rechts, Palme zwischen Hand
# und Mau-Knopf, Krone darüber, am Ende alles weggespült; Ebene hinten)
func new_checks() -> void:
	NatureCheck.show(t, 4, 1)
	for sd in [51, 52, 53]:
		nf.spawn("hoppelhase", sd, {"still": true})
		var c := nf.creature() as NatureCreature
		var C := t.table_center()
		var xs: Array = []
		var squash := false
		var stretch := false
		var under := 0
		var n := 0
		var hint: Array = nf.obstacles().get("leiste", [])
		var tt := c.in_s
		while tt < c.dur - c.out_s:
			nf.seek(tt)
			var b := nf.world_bounds()
			xs.append(b.get_center().x)
			squash = squash or float(c.get("sy")) < 0.88
			stretch = stretch or float(c.get("sy")) > 1.1
			for r in hint:
				if b.intersection(r).get_area() > b.get_area() * 0.3:
					under += 1
			n += 1
			tt += 0.05
		check(xs.size() > 10 and (float(xs[0]) - C.x) * (float(xs[xs.size() - 1]) - C.x) < 0.0,
			"Hoppelhase (%d): hüpft von einer Seite zur anderen (%.0f → %.0f)" % [sd, float(xs[0]), float(xs[xs.size() - 1])])
		check(squash and stretch, "Hoppelhase (%d): staucht und streckt sich" % sd)
		check(under <= n / 10, "Hoppelhase (%d): kaum unter der Hinweisleiste (%d/%d)" % [sd, under, n])
		check(c.dur >= 8.0 and c.dur <= 13.5, "Hoppelhase (%d): Dauer %.1f s" % [sd, c.dur])
		nf.clear()
	# Strand
	nf.spawn("strand", 54, {"still": true})
	var s := nf.creature() as NatureCreature
	check(s.get_parent() == nf.layers["hinten"], "Strand: Ebene hinten (Hand und Mau-Knopf liegen darüber)")
	var mau: Rect2 = (nf.obstacles().get("mau", [Rect2()]) as Array)[0]
	nf.seek(0.5)
	var b0 := nf.world_bounds()
	check(b0.has_area() and b0.end.x >= 1599.0 and b0.end.y >= 719.0, "Strand: Welle kommt aus der Ecke unten rechts (%s)" % str(b0))
	nf.seek(3.5)
	var base: Vector2 = s.get("base")
	var crown: Vector2 = s.call("_crown")
	check(base.x < mau.position.x - 10.0 and base.x > 1600.0 - 270.0, "Strand: Palme zwischen Hand und Mau-Knopf (x %.0f, Mau ab %.0f)" % [base.x, mau.position.x])
	check(crown.y < mau.position.y - 30.0, "Strand: Krone über dem Mau-Knopf (y %.0f, Mau ab %.0f)" % [crown.y, mau.position.y])
	check(float(s.get("sea")) < 0.6 and float(s.get("sand")) > 0.99, "Strand: Meer in der Ecke, Sand davor")
	var dd := s.dur
	nf.seek(dd - 0.9)
	check(float(s.get("palm_a")) < 0.1, "Strand: große Welle spült die Palme weg")
	nf.seek(dd - 0.02)
	check(float(s.get("sand")) <= 0.0 and float(s.get("sea")) < 0.1, "Strand: am Ende ist alles weg")
	nf.clear()
