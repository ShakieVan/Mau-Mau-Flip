class_name TableLayout
extends RefCounted
# Geometrie des Tisches als reine Funktionen (docs/recherche/06_hand_ux_effekte.md Abschnitt 3.2/3.3, Zielbild
# art/entwurf/a-papier-neon/hand.png, Querformat 1600×720). Headless testbar (tests/test_ui_table_layout.gd).
# Sitzordnung: Plätze im Uhrzeigersinn von oben gesehen; Spielrichtung 1 = zum linken Nachbarn. Jedes Gerät DREHT die Ansicht
# so, dass der eigene Platz unten liegt – es spiegelt nie: Der nächste Spieler erscheint links, der vorige rechts.

const PHI0 := 0.9599310885968813         # 55° Stauchung: unten bleibt frei für die eigene Hand
const BADGE_FROM := 7                    # ab 7 Spielern Abzeichen statt Fächer
const BASE := Vector2(1600, 720)


# Relativer Platz r (0 = man selbst, 1 = nächster in Spielrichtung 1, …)
static func relative_seat(seat: int, my_seat: int, n: int) -> int:
	return posmod(seat - my_seat, n)


# Gestauchter Bildschirmwinkel φ (Bogenmaß, im Uhrzeigersinn ab „unten“)
static func seat_angle(r: int, n: int, phi0 := PHI0) -> float:
	var theta := TAU * float(r) / float(maxi(n, 1))
	return phi0 + theta * (TAU - 2.0 * phi0) / TAU


static func seat_pos(r: int, n: int, center: Vector2, radii: Vector2, phi0 := PHI0) -> Vector2:
	var phi := seat_angle(r, n, phi0)
	return center + Vector2(-sin(phi) * radii.x, cos(phi) * radii.y)


static func compact(n: int) -> bool:
	return n >= BADGE_FROM


static func table_center(size: Vector2) -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.445)


static func ring_radii(size: Vector2) -> Vector2:
	return Vector2(minf(330.0, size.x * 0.21), clampf(size.y * 0.222, 140.0, 190.0))


static func draw_pile_pos(size: Vector2) -> Vector2:
	return table_center(size) + Vector2(-177.0, 0.0)


static func discard_pos(size: Vector2) -> Vector2:
	return table_center(size) + Vector2(177.0, 0.0)


static func hand_pos(size: Vector2) -> Vector2:
	return Vector2(size.x * 0.5, size.y - 90.0)


static func seat_radii(size: Vector2, n: int) -> Vector2:
	var margin := 150.0 if not compact(n) else 115.0
	return Vector2(size.x * 0.5 - margin, size.y * 0.445 - (62.0 if not compact(n) else 66.0))


# Bildschirmposition (Kopfzeile: Avatarmitte) je Platz; Index = Platznummer. Der eigene Platz liegt unten (Hand).
# Ab 7 Spielern liegen die Abzeichen auf zwei leicht versetzten Ebenen, damit sie sich an den Seiten nicht berühren.
static func seat_positions(n: int, my_seat: int, size: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var c := table_center(size)
	var radii := seat_radii(size, n)
	var half_w := 112.0 if not compact(n) else 78.0
	for s in n:
		var r := relative_seat(s, my_seat, n)
		if r == 0:
			out.append(hand_pos(size))
			continue
		var rr := radii
		if compact(n) and r % 2 == 0:
			rr = Vector2(radii.x * 0.80, radii.y * 0.80)
		var p := seat_pos(r, n, c, rr)
		p.x = clampf(p.x, half_w + 12.0, size.x - half_w - 12.0)
		p.y = maxf(p.y, 40.0)
		out.append(p)
	return out


# Fächer der sichtbaren Rückseiten (Mini-Karten) für k Karten der Breite w in höchstens max_w Breite.
# Ergebnis: {"xf": Array[Transform2D] (Kartenmitte relativ zur Fächermitte oben), "shown": angezeigte Karten, "more": Rest („+n“)}
static func fan(k: int, w: float, max_w: float, min_step := 7.0) -> Dictionary:
	var h := w * 466.0 / 300.0
	var shown := k
	var cap := int(floor((max_w - w) / min_step)) + 1
	if shown > cap:
		shown = maxi(cap, 1)
	var xf: Array[Transform2D] = []
	if shown <= 0:
		return {"xf": xf, "shown": 0, "more": k}
	var da := clampf(deg_to_rad(36.0) / float(shown), deg_to_rad(1.5), deg_to_rad(6.0))
	var radius := h * 1.1
	var spread := radius * sin(da * (shown - 1) * 0.5) * 2.0
	var step := 0.0
	if shown > 1:
		step = clampf((max_w - w - spread) / float(shown - 1), min_step * 0.5, w * 0.42)
	var mid := (shown - 1) * 0.5
	for i in shown:
		var a := (i - mid) * da
		var p := Vector2((i - mid) * step + radius * sin(a), radius * (1.0 - cos(a)) + h * 0.5)
		xf.append(Transform2D(a, p))
	return {"xf": xf, "shown": shown, "more": k - shown}


# Breite der Mini-Karten und des Fächers je Spielerzahl (Gegner = n − 1)
static func fan_metrics(n: int) -> Vector2:
	if n <= 2:
		return Vector2(72.0, 260.0)
	if n <= 4:
		return Vector2(60.0, 210.0)
	return Vector2(52.0, 176.0)


# Catmull-Rom-Kurve durch Punkte (z. B. Komet um den Tisch); per Punkte je Abschnitt. Ist der letzte Punkt gleich dem ersten,
# wird die Kurve geschlossen geglättet. Punkt i der Eingabe liegt im Ergebnis bei Index i * per.
static func smooth_path(pts: PackedVector2Array, per := 10) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	if n < 3:
		return pts
	var closed := pts[0].distance_to(pts[n - 1]) < 0.5
	for i in n - 1:
		var p0 := pts[i - 1] if i > 0 else (pts[n - 2] if closed else pts[0])
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[i + 2] if i + 2 < n else (pts[1] if closed else pts[n - 1])
		for k in per:
			var t := float(k) / per
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[n - 1])
	return out
