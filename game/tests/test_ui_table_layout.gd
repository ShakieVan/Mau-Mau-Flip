extends SceneTree
# TableLayout (Modul F1b): Sitzordnung relativ zum eigenen Platz (06 Abschnitt 3.2) – nur drehen, nie spiegeln –, Layout
# für 2–10 Spieler innerhalb des Bildes ohne Überlappung, Abzeichen ab 7, Fächer der Mini-Karten, Sichtschutz-Richtung.

var ok := 0
var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		ok += 1
	else:
		fails += 1
		print("FAIL: " + what)


func _init() -> void:
	var size := TableLayout.BASE
	var c := TableLayout.table_center(size)
	# Relativer Platz und Winkel
	check(TableLayout.relative_seat(3, 1, 4) == 2 and TableLayout.relative_seat(0, 1, 4) == 3, "relativer Platz")
	check(is_equal_approx(TableLayout.seat_angle(0, 4), TableLayout.PHI0), "r = 0 liegt bei φ0")
	check(is_equal_approx(TableLayout.seat_angle(2, 4), PI), "gegenüber liegt oben (180°)")
	# 4 Spieler aus Sicht von Platz 0: nächster (1) links, gegenüber (2) oben, voriger (3) rechts – wie im Entwurf
	var p := TableLayout.seat_positions(4, 0, size)
	check(p[1].x < c.x - 400.0 and p[3].x > c.x + 400.0, "4 Spieler: nächster links, voriger rechts")
	check(absf(p[2].x - c.x) < 1.0 and p[2].y < 120.0, "4 Spieler: gegenüber oben Mitte")
	check(p[0].y > 600.0, "eigener Platz unten (Hand)")
	# Drehen statt spiegeln: Für jeden Betrachter liegt der nächste Platz links, der vorige rechts, die Reihenfolge bleibt
	for n in range(2, 11):
		for me in n:
			var q := TableLayout.seat_positions(n, me, size)
			if n >= 3:
				check(q[posmod(me + 1, n)].x < c.x and q[posmod(me - 1, n)].x > c.x, "n=%d me=%d: links/rechts" % [n, me])
			# im Uhrzeigersinn (auf dem Bildschirm) wachsender Winkel um die Mitte: links unten → oben → rechts unten
			var last := -INF
			var mono := true
			for r in range(1, n):
				var s := posmod(me + r, n)
				var a := TableLayout.seat_angle(r, n)
				if a <= last:
					mono = false
				last = a
				var pos: Vector2 = q[s]
				if pos.x < 0.0 or pos.x > size.x or pos.y < 0.0 or pos.y > 470.0:
					mono = false
			check(mono, "n=%d me=%d: Reihenfolge erhalten und im Bild" % [n, me])
	# Mindestabstand der Kopfzeilen: normal 150 px, Abzeichen 100 px (zwei Ebenen)
	for n in range(2, 11):
		var q := TableLayout.seat_positions(n, 0, size)
		var min_d := INF
		for a in range(1, n):
			for b in range(a + 1, n):
				min_d = minf(min_d, q[a].distance_to(q[b]))
		var need := 150.0 if not TableLayout.compact(n) else 100.0
		check(n == 2 or min_d >= need, "n=%d: Abstand der Plätze %.0f ≥ %.0f" % [n, min_d, need])
	check(not TableLayout.compact(6) and TableLayout.compact(7), "Abzeichen ab 7 Spielern")
	# Beta 1.6.17: Der „…“-Knopf neben ☰ (TableScreen._place_bar) liegt bei keiner Spielerzahl auf einem Kopf. Größen: virtuelle Maße bei
	# Streckung „expand“ für 21:9, 20:9, 19,5:9, 19:9, 16:9
	var dots := Rect2(14.0 + 84.0 + 12.0 + 84.0 + 12.0, 10.0, 84.0, 84.0).grow(-2.0)
	for sz: Vector2 in [Vector2(1680, 720), Vector2(1600, 720), Vector2(1600, 738), Vector2(1600, 758), Vector2(1600, 900)]:
		for n in range(2, 11):
			var q := TableLayout.seat_positions(n, 0, sz)
			var free := true
			for a in range(1, n):
				var half := 112.0 if not TableLayout.compact(n) else 78.0
				free = free and not dots.intersects(Rect2(q[a] - Vector2(half, 34.0), Vector2(half * 2.0, 68.0)))
			check(free, "„…“ frei: %s, n=%d" % [sz, n])
	# Fächer: bleibt in der Breite, Überlänge wird als „+n“ gezählt, symmetrisch
	for k in [1, 2, 5, 9, 14, 25]:
		var f := TableLayout.fan(k, 60.0, 210.0)
		var xf: Array = f["xf"]
		var minx := INF
		var maxx := -INF
		for t in xf:
			minx = minf(minx, (t as Transform2D).origin.x - 30.0)
			maxx = maxf(maxx, (t as Transform2D).origin.x + 30.0)
		check(int(f["shown"]) + int(f["more"]) == k, "Fächer %d: gezeigt + Rest" % k)
		check(maxx - minx <= 210.0 + 24.0, "Fächer %d: Breite %.0f" % [k, maxx - minx])
		check(absf(minx + maxx) < 1.0, "Fächer %d: mittig" % k)
	# Sichtschutz: Richtung aus der Sitzordnung
	check(HandoverScreen.direction_info(0, 1, 4)["side"] == "links", "Weitergeben an den nächsten: links")
	check(HandoverScreen.direction_info(0, 3, 4)["side"] == "rechts", "an den vorigen: rechts")
	check(HandoverScreen.direction_info(0, 2, 4)["side"] == "gegenüber", "gegenüber")
	var d := HandoverScreen.direction_info(1, 3, 5)
	check(d["side"] == "links" and int(d["steps"]) == 2, "zwei Plätze nach links")
	check(HandoverScreen.headline("Lena", HandoverScreen.direction_info(0, 1, 4)) == "Gib das Handy nach links an Lena", "Überschrift")
	print("RESULT: %d ok" % ok)
	quit(0 if fails == 0 else 1)
