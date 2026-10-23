extends RefCounted
# Mau-Mau Flip (Beta 1.6.12): Tagtiere der „Natur-Überraschungen“ (docs/module/natur.md Abschnitt 3.2, Aufgabe T3).
# NatureFx findet sie über static func make(id) -> NatureCreature (null = keine Tag-id). Je Tier eine innere Klasse; alle erben von
# Day (Hilfen für Bahnen, Band-Wege und Schutzflächen), Day erbt von nature_creature.gd (Vertrag siehe dort).
#   marienkaefer  Band vorn seitlich: Anflug, krabbelt mit Pausen Richtung Bandmitte, Abflug; Tipp: Deckflügel auf, steil davon
#   biene         über der Hand (nur im fremden Zug): Einflug, eine Acht an einer freien Stelle, landet oben rechts auf der mittleren
#                 Handkarte (Eckindex bleibt frei), Abflug; scheu (Zickzack nach oben)
#   libelle       Streifen über dem hinteren Bandrand: Sprint/Schweben quer über den Tisch, schwebt an freien Stellen; Tipp: Zickzack davon
#   pusteblume    Himmel: Schirmchen treiben quer, pendeln; Tipp: Windstoß
#   papierflieger Himmel: flache Welle, sinkt; Tipp: ein Looping
#   seifenblasen  Streifen über dem hinteren Bandrand → Himmel: schillernde Blasen, platzen; Tipp: die nächste platzt
#   spatz         hinteres Band: Anflug, hüpft, pickt, dreht sich, Abflug; Tipp: flattert weg, zwei Federchen fallen
#   wolke         vor der Sonne, ein Hauch Schatten über dem Hintergrund; ruhig: steht und blendet
#   regenbogen    nach Flip zu Tag: Bogen über dem Tisch, wächst von links; ruhig: nur Deckkraft
#   heissluftballon  ferner Himmel: schwebt quer, Brenner flackert; Tipp: Brenner flammt auf, steigt davon
#   schnecke      bei Trödlern: kriecht am Band Richtung Platz, Schleimspur; Tipp: zieht sich ein und kommt wieder
#   hoppelhase    (1.6.15) hüpft vorn am Plattformrand von einer Seite zur anderen, Pausen mit Ohrenzucken und Männchen; Tipp:
#                 Schreck-Sprung, dann schnell davon
#   strand        (1.6.15) Ecke unten rechts (hinter Hand und Mau-Knopf): Welle bringt einen Sandstrand, eine Palme wächst und wiegt
#                 sich, eine große Welle spült alles weg; Tipp auf die Palme: schüttelt sich, eine Kokosnuss fällt
# Alles selbst gezeichnet (Polygone, Bögen, Linien; Stil „Papier & Neon“: Tusche-Kontur INK, kräftige Farben), kein Ton, kein Text.
# Pose nur aus Samen und Zeit (pose_at), Reaktionen ab tap_at, schneller Abgang ab leave_at.

const IDS := ["marienkaefer", "biene", "libelle", "pusteblume", "papierflieger", "seifenblasen", "spatz", "wolke", "regenbogen",
	"heissluftballon", "schnecke", "hoppelhase", "strand"]


static func make(id: String) -> NatureCreature:
	match id:
		"marienkaefer":
			return Marienkaefer.new()
		"biene":
			return Biene.new()
		"libelle":
			return Libelle.new()
		"pusteblume":
			return Pusteblume.new()
		"papierflieger":
			return Papierflieger.new()
		"seifenblasen":
			return Seifenblasen.new()
		"spatz":
			return Spatz.new()
		"wolke":
			return Wolke.new()
		"regenbogen":
			return Regenbogen.new()
		"heissluftballon":
			return Heissluftballon.new()
		"schnecke":
			return Schnecke.new()
		"hoppelhase":
			return Hoppelhase.new()
		"strand":
			return Strand.new()
	return null


# ================================================================================ Gemeinsame Hilfen

class Day extends "res://scripts/ui/nature_creature.gd":
	var s := 1.0               # Zeichenmaßstab (Weltpixel je Zeichen-Einheit)

	static func catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, u: float) -> Vector2:
		var u2 := u * u
		var u3 := u2 * u
		return 0.5 * ((2.0 * p1) + (p2 - p0) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * u3)

	static func bez2(a: Vector2, c: Vector2, b: Vector2, u: float) -> Vector2:
		var v := 1.0 - u
		return a * (v * v) + c * (2.0 * u * v) + b * (u * u)

	# Bahn durch Schlüssel [[Zeit, Punkt], …] (aufsteigend); smooth = Catmull-Rom, sonst gerade Stücke
	static func track(keys: Array, tt: float, smooth := true) -> Vector2:
		var n := keys.size()
		if n == 0:
			return Vector2.ZERO
		if tt <= float(keys[0][0]):
			return keys[0][1]
		if tt >= float(keys[n - 1][0]):
			return keys[n - 1][1]
		var i := 0
		while i < n - 2 and tt > float(keys[i + 1][0]):
			i += 1
		var t0 := float(keys[i][0])
		var t1 := float(keys[i + 1][0])
		var u := clampf((tt - t0) / maxf(t1 - t0, 1e-4), 0.0, 1.0)
		var p1: Vector2 = keys[i][1]
		var p2: Vector2 = keys[i + 1][1]
		if not smooth:
			return p1.lerp(p2, u)
		var p0: Vector2 = keys[maxi(i - 1, 0)][1]
		var p3: Vector2 = keys[mini(i + 2, n - 1)][1]
		return catmull(p0, p1, p2, p3, u)

	# Punkte nach Weglänge auf [t0, t0 + d] verteilen → Schlüssel für track
	static func timed(pts: Array, t0: float, d: float) -> Array:
		var total := 0.0
		for i in range(1, pts.size()):
			total += (pts[i] as Vector2).distance_to(pts[i - 1])
		var keys: Array = []
		var acc := 0.0
		for i in pts.size():
			if i > 0:
				acc += (pts[i] as Vector2).distance_to(pts[i - 1])
			keys.append([t0 + (d * acc / total if total > 0.0 else d * float(i) / maxf(pts.size() - 1, 1)), pts[i]])
		return keys

	static func path_len(pts: Array) -> float:
		var total := 0.0
		for i in range(1, pts.size()):
			total += (pts[i] as Vector2).distance_to(pts[i - 1])
		return total

	# Schutzflächen (ctx.obstacles) als Liste, ohne die erlaubten Namen
	func obs_rects(allow: Array = []) -> Array:
		var out: Array = []
		var obs: Dictionary = ctx.get("obstacles", {})
		for key in obs:
			if allow.has(key):
				continue
			for r in obs[key]:
				out.append(r)
		return out

	# Anteil von r unter Schutzflächen (0 … 1, wie nature_check)
	func covered(r: Rect2) -> float:
		var a := r.get_area()
		if a <= 0.0:
			return 0.0
		var sum := 0.0
		var obs: Dictionary = ctx.get("obstacles", {})
		for key in obs:
			for q in obs[key]:
				if r.intersects(q):
					sum += r.intersection(q).get_area()
		return minf(sum / a, 1.0)

	func shadow(p: Vector2, rx: float, ry: float, a: float) -> void:
		if a > 0.003:
			poly_ellipse(p, rx, ry, ca(INK, a), 0.0, 18)

	# Seitenansicht: lokal +x = vorn; f = +1 schaut nach rechts, −1 nach links (gespiegelt, bleibt aufrecht)
	func side_xf(p: Vector2, dirv: Vector2, sc: float, f: float, max_tilt := 0.6) -> void:
		var d := dirv * f
		var ang := clampf(d.angle(), -max_tilt, max_tilt) if d.length() > 1e-4 else 0.0
		draw_set_transform(p, ang, Vector2(sc * f, sc))

	func reset_xf() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Weg auf dem Band von Grad d0 nach d1 (Punkte alle 0,5°) mit Weglänge
	func band_track(d0: float, d1: float, quer := 0.5) -> Dictionary:
		var pts := PackedVector2Array()
		var cum := PackedFloat32Array()
		var n := maxi(2, int(absf(d1 - d0) / 0.5) + 1)
		var total := 0.0
		for i in n:
			var p := band(lerpf(d0, d1, float(i) / float(n - 1)), quer)
			if i > 0:
				total += p.distance_to(pts[i - 1])
			pts.append(p)
			cum.append(total)
		return {"pts": pts, "cum": cum, "len": total}

	static func _seg(bt: Dictionary, dist: float) -> Array:
		var cum: PackedFloat32Array = bt["cum"]
		var d := clampf(dist, 0.0, float(bt["len"]))
		var i := clampi(cum.bsearch(d), 1, cum.size() - 1)
		var a := cum[i - 1]
		var b := cum[i]
		return [i, 0.0 if b <= a else (d - a) / (b - a)]

	static func along(bt: Dictionary, dist: float) -> Vector2:
		var pts: PackedVector2Array = bt["pts"]
		var sg := _seg(bt, dist)
		var i: int = sg[0]
		return pts[i - 1].lerp(pts[i], float(sg[1]))

	static func along_dir(bt: Dictionary, dist: float) -> Vector2:
		var pts: PackedVector2Array = bt["pts"]
		var sg := _seg(bt, dist)
		var i: int = sg[0]
		return (pts[i] - pts[i - 1]).normalized()

	# Liegt eine Hülle (Halbmaße he um p) in der Hauptphase gut sichtbar (höchstens zu einem Drittel unter Schutzflächen)?
	func free_spot(p: Vector2, he: Vector2) -> bool:
		return covered(box(p, he)) <= 0.34

	# Sichtbare Hülle eines Schwarms bzw. großen Gebildes aus Teilkästen (Ebene hinten/mitte: was unter Spielelementen liegt, ist nicht
	# zu sehen): Vereinigung der Teile, die höchstens zur Hälfte bedeckt und im Bild sind; ist die Vereinigung selbst überwiegend
	# bedeckt (Teile links und rechts eines Platzes), der am wenigsten bedeckte Teil.
	func visible_hull(boxes: Array) -> Rect2:
		var screen := Rect2(Vector2.ZERO, table_size())
		var vis: Array = []
		var best := Rect2()
		var best_c := 2.0
		for b in boxes:
			var r: Rect2 = b
			if not r.has_area() or not r.intersects(screen):
				continue
			var cv := covered(r)
			if cv < 0.5:
				vis.append(r)
				if cv < best_c:
					best_c = cv
					best = r
		if vis.is_empty():
			return Rect2()
		var u: Rect2 = vis[0]
		for r in vis:
			u = u.merge(r)
		return u if covered(u) <= 0.5 else best


# ================================================================================ 1 Marienkäfer

class Marienkaefer extends Day:
	const RED := Color("#E8352E")
	const RED_HI := Color("#FF6B5C")
	var bt: Dictionary = {}
	var segs: Array = []        # [t0, t1, d0, d1, Drehung] Laufen bzw. Halt
	var land := Vector2.ZERO
	var from := Vector2.ZERO
	var ctrl := Vector2.ZERO
	var side := 1.0
	var t_land := 1.2
	var t_walk := 1.4
	var t_off := 8.0
	var dist_end := 0.0
	var head0 := 0.0
	# Pose
	var pos := Vector2.ZERO
	var rot := 0.0
	var open := 0.0             # Deckflügel 0 zu … 1 offen
	var fly := 0.0              # Hautflügel sichtbar
	var lift := 0.0             # Höhe über dem Band (Schatten)
	var gait := 0.0
	var walking := false
	var flap := 1.0

	func setup(c: Dictionary) -> void:
		s = 1.45 * k()
		own_leave = true
		in_s = t_walk
		out_s = 1.0
		t_off = dur - out_s
		var o: Variant = c.get("ort")
		var deg := float((o as Dictionary).get("deg", 25.0)) if o is Dictionary else 25.0
		var dir := 1.0 if deg < 90.0 or deg > 270.0 else -1.0
		side = 1.0 if deg < 90.0 or deg > 270.0 else -1.0
		var v := 12.0 * k()
		var tt := t_walk
		var d := 0.0
		while tt < t_off - 0.05:
			var w := minf(rng.randf_range(1.5, 2.5), t_off - tt)
			segs.append([tt, tt + w, d, d + v * w, 0.0])
			d += v * w
			tt += w
			if tt >= t_off - 0.05:
				break
			var pz := minf(rng.randf_range(0.4, 0.8), t_off - tt)
			segs.append([tt, tt + pz, d, d, deg_to_rad(rng.randf_range(-15.0, 15.0))])
			tt += pz
		dist_end = d
		# zur vorderen Bandmitte, aber nie unter die Hinweisleiste (66–114°)
		var lim := 63.0 if dir > 0.0 else 117.0
		if deg > 270.0:
			lim = 360.0 + 63.0
		if (lim - deg) * dir < 4.0:
			lim = deg + dir * 4.0
		bt = band_track(deg, lim, 0.55)
		land = along(bt, 0.0)
		head0 = along_dir(bt, 0.0).angle() + PI * 0.5
		from = Vector2(land.x + side * 190.0 * k(), -40.0)
		ctrl = Vector2(land.x + side * 30.0 * k(), land.y - 170.0 * k())

	func _base(tb: float) -> void:
		walking = false
		gait = 0.0
		lift = 0.0
		if tb < t_land:
			var u := clampf(tb / t_land, 0.0, 1.0)
			var e := 1.0 - (1.0 - u) * (1.0 - u)
			pos = bez2(from, ctrl, land, e)
			var ahead := bez2(from, ctrl, land, minf(e + 0.04, 1.0)) - pos
			var fly_rot := ahead.angle() + PI * 0.5 if ahead.length() > 0.01 else head0
			rot = lerp_angle(fly_rot, head0, ramp(u, 0.6, 1.0))
			open = 1.0
			fly = 1.0
			lift = 46.0 * (1.0 - e)
		elif tb < t_walk:
			var u := (tb - t_land) / (t_walk - t_land)
			pos = land
			rot = head0
			open = 1.0 - smoothstep(0.0, 1.0, u)
			fly = 1.0 - u
		elif tb < t_off:
			var d := 0.0
			var turn := 0.0
			for sg in segs:
				if tb >= float(sg[0]) and tb < float(sg[1]):
					var u := (tb - float(sg[0])) / maxf(float(sg[1]) - float(sg[0]), 1e-4)
					d = lerpf(float(sg[2]), float(sg[3]), u)
					if float(sg[3]) > float(sg[2]):
						walking = true
						gait = (tb - float(sg[0])) * 2.6
					else:
						turn = float(sg[4]) * sin(PI * u)
					break
				elif tb >= float(sg[1]):
					d = float(sg[3])
			pos = along(bt, d)
			rot = along_dir(bt, d).angle() + PI * 0.5 + turn
			open = 0.0
			fly = 0.0
		else:
			var u := clampf((tb - t_off) / out_s, 0.0, 1.0)
			var p_end := along(bt, dist_end)
			pos = p_end + Vector2(side * 150.0 * u, -(320.0 * u * u + 50.0 * u)) * k()
			rot = along_dir(bt, dist_end).angle() + PI * 0.5
			rot = lerp_angle(rot, side * 0.5, ramp(u, 0.0, 0.5))
			open = minf(1.0, (tb - t_off) / 0.15)
			fly = open
			lift = 70.0 * u
			alpha = 1.0 - ramp(u, 0.6, 1.0)

	func pose_at(tt: float) -> void:
		var tb := tt
		var lv := since_leave(tt)
		var tp := since_tap(tt)
		if lv >= 0.0:
			tb = leave_at
		if tp >= 0.0:
			tb = minf(tb, tap_at)
		_base(tb)
		if tp >= 0.0:
			var u := clampf(tp / 0.8, 0.0, 1.0)
			pos += Vector2(side * 70.0 * u, -360.0 * u * (0.45 + 0.55 * u)) * k()
			open = minf(1.0, tp / 0.07)
			fly = open
			lift += 70.0 * u
			rot = lerp_angle(rot, side * 0.35, ramp(u, 0.0, 0.4))
			alpha *= 1.0 - ramp(u, 0.55, 1.0)
		if lv >= 0.0:
			var u := clampf(lv / maxf(leave_s, 0.01), 0.0, 1.0)
			pos += Vector2(side * 60.0 * u, -(200.0 * u * u + 40.0 * u)) * k()
			open = minf(1.0, lv / 0.07)
			fly = open
			lift += 50.0 * u
			alpha *= 1.0 - ramp(u, 0.4, 1.0)
		flap = 0.55 + 0.45 * absf(sin(tt * TAU * 18.0))

	func on_tap(_p: Vector2) -> void:
		dur = minf(dur, tap_at + 0.8)

	func bounds() -> Rect2:
		if alpha <= 0.01:
			return Rect2()
		var r := (14.0 + 10.0 * open) * s * (1.0 + 0.15 * fly)
		return box(pos, Vector2(r, r))

	func _elytron_xf(sd: float) -> Transform2D:
		var h := Vector2(sd * 0.8, -6.0)
		return Transform2D(-sd * open * deg_to_rad(44.0), Vector2(1.0 - 0.15 * open, 1.0), 0.0, h) * Transform2D(0.0, -h)

	func _draw() -> void:
		if alpha <= 0.003:
			return
		var sc := s * (1.0 + 0.15 * fly)
		shadow(pos + Vector2(2.0, 4.0 + lift) * s, 10.5 * s, 8.0 * s, 0.16 * (1.0 - clampf(lift / 90.0, 0.0, 0.85)))
		draw_set_transform(pos, rot, Vector2(sc, sc))
		# Beinchen (trippeln beim Laufen)
		if fly < 0.6:
			for i in 3:
				for sdv in [-1.0, 1.0]:
					var sd: float = sdv
					var ph := sin(gait * TAU + PI * float((i + (1 if sd > 0.0 else 0)) % 2)) if walking else 0.0
					var a := Vector2(sd * 6.0, -3.0 + i * 4.0)
					var b := Vector2(sd * 11.5, -5.5 + i * 6.0 + ph * 1.8)
					var m := (a + b) * 0.5 + Vector2(sd * 0.5, -1.4)
					draw_polyline(PackedVector2Array([a, m, b]), INK, 1.0, true)
		# Hautflügel (im Flug, unter den Deckflügeln)
		if open > 0.05 and fly > 0.05:
			for sdv in [-1.0, 1.0]:
				var sd: float = sdv
				wing(Vector2(sd * 2.0, -4.0), 24.0 * flap * fly, 10.0, PI * 0.5 - sd * PI * 0.27, Color(1, 1, 1, 0.72), ca(INK, 0.3), 0.6)
		# Hinterleib (sichtbar, wenn die Deckflügel offen sind)
		poly_ellipse(Vector2(0, 3.5), 6.2, 8.2, INK)
		# Deckflügel mit Punkten
		for sdv in [-1.0, 1.0]:
			var sd: float = sdv
			var xf := _elytron_xf(sd)
			var pts := PackedVector2Array()
			for i in 13:
				var a := PI * 0.5 + PI * float(i) / 12.0
				pts.append(Vector2(-sd * cos(a) * 9.6, 3.0 + sin(a) * 10.0))
			var poly := xf * pts
			draw_colored_polygon(poly, RED)
			# hellere Kante innen (Wölbung)
			var hi := PackedVector2Array([xf * Vector2(sd * 1.6, -4.0), xf * Vector2(sd * 6.5, -3.0), xf * Vector2(sd * 7.8, 2.0),
				xf * Vector2(sd * 5.5, 0.0), xf * Vector2(sd * 2.0, -2.0)])
			draw_colored_polygon(hi, RED_HI)
			for sp in [[Vector2(4.3, -0.6), 1.7], [Vector2(5.9, 5.6), 1.5], [Vector2(2.8, 9.2), 1.35]]:
				var c: Vector2 = sp[0]
				draw_circle(xf * Vector2(sd * c.x, c.y), float(sp[1]), INK, true, -1.0, true)
			outline_poly(poly, INK, 0.8)
			# Glanzpunkt
			poly_ellipse(xf * Vector2(sd * 4.6, -3.6), 2.2, 1.0, Color(1, 1, 1, 0.6), -sd * 0.5, 12)
		# Halsschild und Kopf
		poly_ellipse(Vector2(0, -7.4), 7.6, 3.2, INK)
		for sdv in [-1.0, 1.0]:
			var sd: float = sdv
			poly_ellipse(Vector2(sd * 4.6, -7.5), 1.9, 1.4, CREAM, 0.0, 12)
		poly_ellipse(Vector2(0, -10.8), 4.8, 3.4, INK)
		for sdv in [-1.0, 1.0]:
			var sd: float = sdv
			draw_circle(Vector2(sd * 2.4, -11.9), 1.1, Color.WHITE, true, -1.0, true)
			draw_polyline(PackedVector2Array([Vector2(sd * 1.6, -13.4), Vector2(sd * 2.8, -16.2), Vector2(sd * 5.0, -17.4)]), INK, 0.8, true)
		reset_xf()


# ================================================================================ 2 Biene

class Biene extends Day:
	const BODY := Color("#FFC934")
	const BODY_D := Color("#E9A21C")
	var c8 := Vector2.ZERO        # Acht: Mitte, Halbachsen, Periode
	var a8 := 100.0
	var b8 := 26.0
	var per := 2.2
	var n8 := 1
	var es := 1.0                 # Seite der Spitze (+1 rechts)
	var tip := Vector2.ZERO
	var keys_in: Array = []
	var keys_down: Array = []
	var keys_out: Array = []
	var t_e0 := 1.2
	var t_e1 := 3.4
	var t_d1 := 4.3
	var t_s1 := 5.8
	var land := Vector2.ZERO
	var land_rot := 0.0
	var has_card := false
	var forbid: Array = []
	var hand_r: Array = []
	var quad := Rect2()           # linkes oberes Viertel der mittleren Handkarte (Eckindex)
	var quad_xf := Transform2D.IDENTITY
	var quad_size := Vector2.ZERO
	var land_xf := Transform2D.IDENTITY
	var land_size := Vector2.ZERO
	# Pose
	var pos := Vector2.ZERO
	var tilt := 0.0
	var face := 1.0
	var sitting := false
	var wing_a := 0.0
	var bob := 0.0
	var trail := PackedVector2Array()

	func setup(c: Dictionary) -> void:
		s = 1.0
		own_leave = true
		var sz := table_size()
		forbid = obs_rects(["hand"])
		var obs: Dictionary = c.get("obstacles", {})
		hand_r = obs.get("hand", [])
		var card: Dictionary = {}
		var hc: Variant = c.get("hand")
		if hc is Callable and (hc as Callable).is_valid():
			card = (hc as Callable).call()
		elif c.get("ort") is Dictionary:
			card = c["ort"]
		has_card = not card.is_empty() and card.get("xf") is Transform2D
		if has_card:
			# Eckindex der mittleren Karte bleibt frei (Prüfung wie nature_check)
			quad_xf = card["xf"]
			quad_size = card["size"]
			# Landeplatz: oben rechts auf der obersten Karte des Fächers (deren rechte obere Ecke deckt keine Nachbarkarte; bei der
			# mittleren Karte läge dort schon die nächste Karte samt Eckindex), Kartenoberkante + 22, rechter Rand − 26
			var top := _top_card(card)
			var xf: Transform2D = top["xf"]
			var cs: Vector2 = top["size"]
			land = xf * Vector2(cs.x * 0.5 - 26.0, -cs.y * 0.5 + 22.0)
			land_rot = xf.get_rotation()
			land_xf = xf
			land_size = cs
		var want := clampf(dur, 7.0, 9.0)
		n8 = 2 if want >= 8.2 and not has_card else 1
		per = clampf((want - 4.6) / float(n8), 2.0, 2.6) if has_card else clampf((want - 2.4) / float(n8), 2.0, 2.6)
		t_e0 = 1.2
		t_e1 = t_e0 + per * float(n8)
		var route := _plan(sz)
		keys_in = timed(route[0], 0.0, t_e0)
		var t_now := t_e1
		var out_pts: Array
		if has_card:
			var down: Array = route[1]
			var dd := clampf(path_len(down) / 520.0, 0.6, 1.2)
			keys_down = timed(down, t_now, dd)
			t_d1 = t_now + dd
			t_s1 = t_d1 + 1.5
			t_now = t_s1
			out_pts = _best(_exits(sz, land, down))[0]
		else:
			t_d1 = t_now
			t_s1 = t_now
			out_pts = _best(_exits(sz, tip, []))[0]
		var xd := clampf(path_len(out_pts) / 480.0, 0.8, 2.2)
		keys_out = timed(out_pts, t_now, xd)
		dur = t_now + xd
		in_s = t_e0
		out_s = xd

	# ---- Wegwahl: Hülle frei von Schutzflächen (außer Hand), Eckindex-Viertel frei. Die Biene fliegt gerade Stücke (die Wege
	# sind so geprüft, wie sie geflogen werden); geschwungen ist nur die Acht.

	func _hull_at(p: Vector2) -> Rect2:
		return Rect2(p + Vector2(-17.0, -15.0) * s, Vector2(34.0, 25.0) * s)

	func _blocked(p: Vector2) -> bool:
		var h := _hull_at(p)
		for r in forbid:
			if h.intersects(r):
				return true
		if has_card:
			for q in [[quad_xf, quad_size], [land_xf, land_size]]:
				var qs: Vector2 = q[1]
				if qs == Vector2.ZERO:
					continue
				var lp := (q[0] as Transform2D).affine_inverse() * p
				if lp.x < 2.0 and lp.y < 2.0 and lp.x > -qs.x * 0.5 - 2.0 and lp.y > -qs.y * 0.5 - 2.0:
					return true
		return false

	# Oberste Karte des Fächers (zuletzt gelegt, rechts) mit freiem Landeplatz; sonst die mittlere Karte
	func _top_card(mid: Dictionary) -> Dictionary:
		var tbl: Variant = fx.get("table") if fx != null else null
		if not (tbl is Object) or not (fx as Object).has_method("_wx"):
			return mid
		var h: Variant = (tbl as Object).get("hand")
		if not (h is Node2D) or not (h as Node2D).has_method("get_order"):
			return mid
		var slots: Variant = (h as Object).get("_slots")
		if not (slots is Dictionary):
			return mid
		var wx: Transform2D = fx.call("_wx")
		var sz := table_size()
		var order: Array = (h as Object).call("get_order")
		for i in range(order.size() - 1, -1, -1):
			var sl: Variant = (slots as Dictionary).get(order[i])
			if not (sl is Object) or not ((sl as Object).get("view") is Node2D):
				continue
			var cv: Node2D = (sl as Object).get("view")
			var xf: Transform2D = wx * cv.get_global_transform()
			var w := float(cv.get("width"))
			var cs := Vector2(w, w * 466.0 / 300.0)
			var p := xf * Vector2(cs.x * 0.5 - 26.0, -cs.y * 0.5 + 22.0)
			if p.x > 30.0 and p.x < sz.x - 30.0 and p.y < sz.y - 20.0 and not _blocked(p):
				return {"xf": xf, "size": cs}
		return mid

	func _on_hand(p: Vector2) -> bool:
		var h := _hull_at(p)
		for r in hand_r:
			if h.intersects(r):
				return true
		return false

	# Kosten einer Polylinie: [verbotene Proben, Hand-Proben, Länge]; bricht ab, sobald mehr als limit verbotene Proben
	func _cost(pts: Array, limit := 1 << 30) -> Array:
		var bad := 0
		var on_hand := 0
		for i in range(1, pts.size()):
			var a: Vector2 = pts[i - 1]
			var b: Vector2 = pts[i]
			var n := maxi(1, int(a.distance_to(b) / 6.0))
			for j in n + 1:
				var p := a.lerp(b, float(j) / float(n))
				if _blocked(p):
					bad += 1
					if bad > limit:
						return [bad, on_hand, path_len(pts)]
				elif _on_hand(p):
					on_hand += 1
		return [bad, on_hand, path_len(pts)]

	static func _less(a: Array, b: Array) -> bool:
		if int(a[0]) != int(b[0]):
			return int(a[0]) < int(b[0])
		if int(a[1]) != int(b[1]):
			return int(a[1]) < int(b[1])
		return float(a[2]) < float(b[2]) - 1.0

	# Beste Polylinie aus Kandidaten (erst frei, dann wenig Hand, dann kurz; bei Gleichstand die erste): [Punkte, Kosten]
	func _best(cands: Array) -> Array:
		var best: Array = cands[0]
		var bc := [1 << 30, 1 << 30, 1.0e9]
		for cand in cands:
			var cc := _cost(cand, int(bc[0]))
			if _less(cc, bc):
				best = cand
				bc = cc
		return [best, bc]

	func _eight_at(u: float) -> Vector2:
		var th := es * PI * 0.5 + TAU * u
		return c8 + Vector2(a8 * sin(th), b8 * sin(2.0 * th))

	# Acht-Kandidaten in Vorzugsreihenfolge: groß vor klein, nah an der Stelle aus dem Entwurf (0,5 W; H − 300) zuerst
	func _eight_cands(sz: Vector2) -> Array:
		var spec := Vector2(0.5 * sz.x, sz.y - 300.0)
		var cands: Array = []
		var sizes := [[0.18, 35.0], [0.13, 30.0], [0.09, 26.0], [0.06, 22.0], [0.045, 18.0]]
		var jitter := rng.randf_range(-0.015, 0.015) * sz.x
		for si in sizes.size():
			var pts: Array = []
			for i in 21:
				var xf := 0.1 + 0.04 * float(i)
				var y := 0.12 * sz.y
				while y <= sz.y - 220.0:
					pts.append(Vector2(xf * sz.x + (jitter if i != 10 else 0.0), y))
					y += 24.0
			pts.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.distance_to(spec) < q.distance_to(spec))
			for p in pts:
				cands.append([p, float(sizes[si][0]) * sz.x, float(sizes[si][1])])
		return cands

	func _eight_bad(cand: Array, sz: Vector2) -> int:
		var cc: Vector2 = cand[0]
		var a := float(cand[1])
		var b := float(cand[2])
		var bad := 0
		for i in 24:
			var th := TAU * float(i) / 24.0
			var p := cc + Vector2(a * sin(th), b * sin(2.0 * th))
			var h := _hull_at(p)
			if _blocked(p) or _on_hand(p) or h.position.x < 4.0 or h.end.x > sz.x - 4.0 or h.position.y < 4.0:
				bad += 1
				if bad > 0:
					return bad
		return bad

	# Acht, Seite der Spitze, Einflug und Abstieg gemeinsam wählen: [Einflug, Abstieg]
	func _plan(sz: Vector2) -> Array:
		var frees: Array = []
		for cand in _eight_cands(sz):
			if _eight_bad(cand, sz) == 0:
				frees.append(cand)
				if frees.size() >= 40:
					break
		if frees.is_empty():
			frees.append([Vector2(0.5 * sz.x, 0.25 * sz.y), 0.06 * sz.x, 22.0])
		var first := 1.0 if rng.randf() < 0.5 else -1.0
		var best: Array = []
		var bc := [1 << 30, 1 << 30, 1.0e9]
		for cand in frees:
			for ev in [first, -first]:
				var e: float = ev
				var tp: Vector2 = (cand[0] as Vector2) + Vector2(e * float(cand[1]), 0.0)
				var ent := _best(_entries(sz, tp, e))
				var dn: Array = _best(_descents(sz, tp)) if has_card else [[tp], [0, 0, 0.0]]
				var cc := [int(ent[1][0]) + int(dn[1][0]), int(ent[1][1]) + int(dn[1][1]), 0.0]
				if _less(cc, bc):
					bc = cc
					best = [cand, e, tp, ent[0], dn[0]]
			if int(bc[0]) == 0:
				break
		c8 = best[0][0]
		a8 = best[0][1]
		b8 = best[0][2]
		es = best[1]
		tip = best[2]
		return [best[3], best[4]]

	func _side_x(sz: Vector2, sd: float) -> float:
		return sz.x + 60.0 if sd > 0.0 else -60.0

	func _entries(sz: Vector2, tp: Vector2, e: float) -> Array:
		var out: Array = []
		var x0 := _side_x(sz, e)
		for dy in [0.0, 30.0, -30.0, 60.0, -60.0, 95.0, -95.0, 130.0, -130.0, 180.0, -180.0]:
			var y := clampf(tp.y + float(dy), 30.0, sz.y - 40.0)
			out.append([Vector2(x0, y), Vector2(lerpf(x0, tp.x, 0.55), lerpf(y, tp.y, 0.7)), tp])
			out.append([Vector2(x0, y), Vector2(tp.x + e * 60.0, y), tp])
		out.append([Vector2(tp.x + e * 120.0, -50.0), tp + Vector2(e * 70.0, -80.0), tp])
		for dx in [0.0, 90.0, -90.0, 180.0, -180.0]:
			out.append([Vector2(tp.x + float(dx), -50.0), tp])
		return out

	# Gang unter der Hinweisleiste: Mitte zwischen Leiste und Hand
	func _lane(sz: Vector2) -> Dictionary:
		var obs: Dictionary = ctx.get("obstacles", {})
		var top := sz.y - 179.5
		var x0 := sz.x * 0.5 - 330.0
		var x1 := sz.x * 0.5 + 330.0
		for r in obs.get("leiste", []):
			top = (r as Rect2).end.y
			x0 = (r as Rect2).position.x
			x1 = (r as Rect2).end.x
		var bot := top + 32.5
		for r in hand_r:
			bot = (r as Rect2).position.y
		var y := top + 15.0 * s + maxf(0.0, (bot - top - 25.0 * s) * 0.5)
		return {"y": y, "x0": x0 - 18.0 * s - 6.0, "x1": x1 + 18.0 * s + 6.0}

	func _descents(sz: Vector2, tp: Vector2) -> Array:
		var ln := _lane(sz)
		var y := float(ln["y"])
		var out: Array = []
		out.append([tp, land])
		out.append([tp, Vector2(land.x + 40.0, land.y - 60.0), land])
		for sdv in [1.0, -1.0]:
			var sd: float = sdv
			var xe := float(ln["x1"]) if sd > 0.0 else float(ln["x0"])
			var c2 := Vector2(land.x + sd * 34.0, y)
			out.append([tp, Vector2(xe, y), c2, land])
			out.append([tp, Vector2(xe, tp.y), Vector2(xe, y), c2, land])
			out.append([tp, Vector2(tp.x, y), Vector2(xe, y), c2, land])
		return out

	func _exits(sz: Vector2, from_p: Vector2, down: Array) -> Array:
		var out: Array = []
		for dx in [220.0, -220.0, 420.0, -420.0, 80.0, -80.0]:
			out.append([from_p, from_p + Vector2(float(dx) * 0.4, -120.0), Vector2(from_p.x + float(dx), -60.0)])
		for sdv in [1.0, -1.0]:
			out.append([from_p, Vector2(_side_x(sz, sdv), from_p.y - 30.0)])
		# über den Gang unter der Leiste zur Seite, dann senkrecht hoch und waagrecht hinaus (bzw. oben hinaus)
		var ln := _lane(sz)
		var y := float(ln["y"])
		for sdv in [1.0, -1.0]:
			var sd: float = sdv
			var xe := float(ln["x1"]) if sd > 0.0 else float(ln["x0"])
			var c2 := Vector2(from_p.x + sd * 34.0, y)
			out.append([from_p, c2, Vector2(xe, y), Vector2(xe, -60.0)])
			var hy := y - 30.0
			while hy > 20.0:
				out.append([from_p, c2, Vector2(xe, y), Vector2(xe, hy), Vector2(_side_x(sz, sd), hy)])
				hy -= 40.0
		# senkrecht hoch und waagrecht hinaus (ohne Karte: von der Acht-Spitze)
		for sdv in [1.0, -1.0]:
			var hy := from_p.y - 30.0
			while hy > 20.0:
				out.append([from_p, Vector2(from_p.x, hy), Vector2(_side_x(sz, sdv), hy)])
				hy -= 40.0
		# denselben Weg zurück (Abstieg rückwärts, dann Acht-Spitze und Einflug rückwärts)
		var back: Array = []
		if not down.is_empty():
			for i in range(down.size() - 1, -1, -1):
				back.append(down[i])
		else:
			back.append(from_p)
		for i in range(keys_in.size() - 2, -1, -1):
			back.append(keys_in[i][1])
		out.append(back)
		return out

	func _pos(tb: float) -> Vector2:
		if tb < t_e0:
			return track(keys_in, tb, false)
		if tb < t_e1:
			return _eight_at((tb - t_e0) / per)
		if tb < t_d1:
			return track(keys_down, tb, false)
		if tb < t_s1:
			return land
		return track(keys_out, tb, false)

	func pose_at(tt: float) -> void:
		var tb := tt
		var lv := since_leave(tt)
		if lv >= 0.0:
			tb = leave_at
		pos = _pos(tb)
		sitting = has_card and tb >= t_d1 and tb < t_s1
		var vel := _pos(tb + 0.03) - _pos(tb - 0.03)
		if sitting:
			face = 1.0 if _pos(t_d1 - 0.02).x >= _pos(t_d1 - 0.12).x else -1.0
			tilt = land_rot + sin(tt * TAU * 2.2) * 0.06
			bob = sin(tt * TAU * 3.0)
			wing_a = PI + 0.3 + sin(tt * TAU * 31.0) * 0.06
		else:
			if absf(vel.x) > 0.6:
				face = 1.0 if vel.x > 0.0 else -1.0
			else:
				face = 1.0 if _pos(tb + 0.15).x >= pos.x else -1.0
			tilt = clampf(vel.y * face / maxf(vel.length(), 1.0) * 0.5, -0.45, 0.45)
			bob = 0.0
			wing_a = -PI * 0.5 - 0.35 + sin(tt * TAU * 22.0) * 0.55
		trail = PackedVector2Array()
		if not sitting and lv < 0.0:
			for i in 7:
				trail.append(_pos(tb - 0.05 + 0.05 * float(i) / 6.0) + Vector2(-face * 13.0, 3.0) * s)
		if lv >= 0.0:
			var u := clampf(lv / maxf(leave_s, 0.01), 0.0, 1.0)
			pos += Vector2(sin(lv * 34.0) * 14.0, -lv * 620.0)
			tilt = -0.4 * face
			sitting = false
			wing_a = -PI * 0.5 - 0.35 + sin(tt * TAU * 22.0) * 0.55
			alpha *= 1.0 - ramp(u, 0.45, 1.0)
		if tt < 0.12:
			alpha *= tt / 0.12

	func leave_time(_fast: bool) -> float:
		return 0.4

	func bounds() -> Rect2:
		if alpha <= 0.01:
			return Rect2()
		return _hull_at(pos)

	func _band_poly(x0: float, x1: float, cx: float, cy: float, rx: float, ry: float) -> PackedVector2Array:
		var top := PackedVector2Array()
		var bot := PackedVector2Array()
		for i in 6:
			var x := lerpf(x0, x1, float(i) / 5.0)
			var q := clampf(1.0 - pow((x - cx) / rx, 2.0), 0.0, 1.0)
			var h := ry * sqrt(q)
			top.append(Vector2(x, cy - h))
			bot.append(Vector2(x, cy + h))
		bot.reverse()
		return top + bot

	func _draw() -> void:
		if alpha <= 0.003:
			return
		if trail.size() >= 2:
			var cols := PackedColorArray()
			for i in trail.size():
				cols.append(ca(INK, 0.32 * float(i) / float(trail.size() - 1)))
			draw_polyline_colors(trail, cols, 1.0, true)
		if sitting:
			shadow(pos + Vector2(2.0, 9.0), 10.0, 3.0, 0.14)
		draw_set_transform(pos + Vector2(0.0, bob * 0.6), tilt, Vector2(face * s, s))
		# hinterer Flügel
		wing(Vector2(1.0, -5.0), 12.0, 6.5, wing_a - 0.32, Color(1, 1, 1, 0.42), ca(INK, 0.4), 0.9)
		# Beinchen
		for i in 3:
			var bx := -2.5 + float(i) * 3.2
			var dy := 0.0 if sitting else 1.5
			draw_polyline(PackedVector2Array([Vector2(bx, 5.0), Vector2(bx - 1.2, 8.0 + dy), Vector2(bx - 0.4, 10.0 + dy)]), ca(INK, 0.85), 1.1, true)
		# Stachel
		tri(Vector2(-10.8, -1.4), Vector2(-10.8, 1.8), Vector2(-15.0, 0.5), INK)
		# Körper mit Streifen
		var cx := -1.5
		var cy := 0.5
		var pts := ellipse_points(Vector2(cx, cy), 10.2, 7.0, -bob * 0.04, 24)
		draw_colored_polygon(pts, BODY)
		draw_colored_polygon(_band_poly(4.0, 8.6, cx, cy, 10.2, 7.0), BODY_D)
		for bnd in [[-8.6, -6.2], [-4.4, -2.0], [-0.2, 2.2]]:
			draw_colored_polygon(_band_poly(float(bnd[0]), float(bnd[1]), cx, cy, 10.2, 7.0), INK)
		outline_poly(pts, INK, 1.4)
		poly_ellipse(Vector2(-2.5, -3.6), 3.2, 1.3, Color(1, 1, 1, 0.5), -0.1, 12)
		# Kopf
		draw_circle(Vector2(10.6, -0.3), 4.6, INK, true, -1.0, true)
		draw_circle(Vector2(12.3, -1.7), 1.15, Color.WHITE, true, -1.0, true)
		draw_polyline(PackedVector2Array([Vector2(11.5, -4.0), Vector2(13.6, -8.4), Vector2(16.8, -9.6)]), INK, 1.0, true)
		draw_polyline(PackedVector2Array([Vector2(10.0, -4.2), Vector2(11.0, -8.8), Vector2(13.6, -10.8)]), INK, 1.0, true)
		# vorderer Flügel
		wing(Vector2(2.0, -5.0), 14.0, 7.6, wing_a, Color(1, 1, 1, 0.58), ca(INK, 0.55), 1.0)
		reset_xf()


# ================================================================================ 3 Libelle

class Libelle extends Day:
	const BODY := Color("#19C6D4")
	const BODY_D := Color("#0E7F8C")
	const EYE := Color("#2E7BFF")
	var keys: Array = []          # [t, p] Haltepunkte der Abschnitte
	var sprints: Array = []       # [t0, t1, a, b]
	var hovers: Array = []        # [t0, t1, p]
	var dir := 1.0
	var t_end := 7.0
	# Pose
	var pos := Vector2.ZERO
	var head := 0.0
	var shimmer := 0.0
	var wing_j := 0.0

	func setup(c: Dictionary) -> void:
		s = 1.25 * k()
		own_leave = true
		var sz := table_size()
		var lane: Rect2 = c.get("ort", Rect2(0, 100, sz.x, 80)) if c.get("ort") is Rect2 else Rect2(0, 100, sz.x, 80)
		dir = 1.0 if rng.randf() < 0.5 else -1.0
		var n := rng.randi_range(5, 7)
		var x0 := -70.0 if dir > 0.0 else sz.x + 70.0
		var x1 := sz.x + 90.0 if dir > 0.0 else -90.0
		var he := Vector2(26.0, 22.0) * s
		var ys: Array = []
		for i in 5:
			ys.append(lane.position.y + lane.size.y * (0.15 + 0.7 * float(i) / 4.0))
		var p := Vector2(x0, float(ys[rng.randi() % ys.size()]))
		var pts: Array = [p]
		for i in n:
			var base_x := lerpf(x0, x1, float(i + 1) / float(n + 1))
			var best := Vector2(base_x, p.y)
			var best_c := 1.0e9
			for dx in [0.0, 60.0, -60.0, 120.0, -120.0, 180.0, -180.0]:
				for yv in ys:
					var q := Vector2(base_x + float(dx), float(yv) + rng.randf_range(-6.0, 6.0))
					var cc := covered(box(q, he)) * 10.0 + absf(float(dx)) * 0.002 + absf(q.y - p.y) * 0.002
					if (q.x - p.x) * dir < 40.0:
						cc += 3.0
					if q.x < 30.0 or q.x > sz.x - 30.0:
						cc += 5.0
					if cc < best_c:
						best_c = cc
						best = q
			pts.append(best)
			p = best
		pts.append(Vector2(x1, p.y + rng.randf_range(-20.0, 20.0)))
		var sprint := 0.26
		var hs: Array = []
		var hsum := 0.0
		for i in n:
			var h := rng.randf_range(0.5, 1.0)
			hs.append(h)
			hsum += h
		var avail := dur - sprint * float(n + 1) - 0.05
		var f := avail / hsum if hsum > 0.0 else 1.0
		var tt := 0.0
		for i in n + 1:
			sprints.append([tt, tt + sprint, pts[i], pts[i + 1]])
			tt += sprint
			if i < n:
				var h := float(hs[i]) * f
				hovers.append([tt, tt + h, pts[i + 1]])
				tt += h
		t_end = tt
		dur = tt
		in_s = sprint
		out_s = sprint
		shimmer = rng.randf_range(0.0, TAU)

	func _base(tb: float) -> void:
		for sp in sprints:
			if tb <= float(sp[1]):
				if tb >= float(sp[0]):
					var u := (tb - float(sp[0])) / (float(sp[1]) - float(sp[0]))
					var e := 1.0 - pow(1.0 - u, 3.0)
					var a: Vector2 = sp[2]
					var b: Vector2 = sp[3]
					pos = a.lerp(b, e)
					head = (b - a).angle()
					wing_j = 1.0
					return
		for hv in hovers:
			if tb >= float(hv[0]) and tb <= float(hv[1]):
				var hp: Vector2 = hv[2]
				pos = hp + Vector2(sin(tb * 7.3 + shimmer) * 1.5, sin(tb * 5.1 + shimmer * 2.0) * 1.5)
				head = _sprint_dir(tb) + sin(tb * 1.7 + shimmer) * 0.08
				wing_j = 0.4
				return
		var last: Array = sprints[sprints.size() - 1]
		pos = last[3]
		head = ((last[3] as Vector2) - (last[2] as Vector2)).angle()

	func _sprint_dir(tb: float) -> float:
		var d := 0.0
		for sp in sprints:
			if float(sp[0]) <= tb:
				d = ((sp[3] as Vector2) - (sp[2] as Vector2)).angle()
		return d

	func pose_at(tt: float) -> void:
		var tb := tt
		var lv := since_leave(tt)
		var tp := since_tap(tt)
		if lv >= 0.0:
			tb = leave_at
		if tp >= 0.0:
			tb = minf(tb, tap_at)
		_base(tb)
		if tp >= 0.0:
			var away := (pos - tap_pos).normalized() if pos.distance_to(tap_pos) > 1.0 else Vector2.from_angle(head)
			var legs := [away.rotated(0.6) * 80.0, away.rotated(-0.6) * 100.0, away.rotated(0.25) * 320.0]
			var p := pos
			var hd := head
			for i in 3:
				var u := clampf((tp - 0.12 * float(i)) / 0.12, 0.0, 1.0)
				var v: Vector2 = legs[i] * k()
				p += v * (1.0 - pow(1.0 - u, 2.0))
				if u > 0.0:
					hd = v.angle()
			pos = p
			head = hd
			wing_j = 1.0
			alpha *= 1.0 - ramp(tp, 0.24, 0.42)
		if lv >= 0.0:
			var u := clampf(lv / maxf(leave_s, 0.01), 0.0, 1.0)
			var away := Vector2.from_angle(head)
			pos += away * 360.0 * k() * (1.0 - pow(1.0 - u, 2.0))
			alpha *= 1.0 - ramp(u, 0.3, 1.0)
		alpha *= clampf(tt / 0.1, 0.0, 1.0)

	func on_tap(_p: Vector2) -> void:
		dur = minf(dur, tap_at + 0.42)

	func bounds() -> Rect2:
		if alpha <= 0.01:
			return Rect2()
		return box(pos, Vector2(26.0, 22.0) * s)

	func _draw() -> void:
		if alpha <= 0.003:
			return
		shadow(pos + Vector2(8.0, 22.0) * s, 16.0 * s, 4.0 * s, 0.07)
		draw_set_transform(pos, head, Vector2(s, s))
		# Hinterleib: 8 Glieder, 4 → 2 px, dunkle Ringe
		var abd := PackedVector2Array()
		for i in 9:
			var x := 1.0 - float(i) * 4.4
			var sway := sin(t * 2.3 + shimmer) * 1.4 * pow(float(i) / 8.0, 2.0)
			abd.append(Vector2(x, sway))
		# schlanker, spitz zulaufender Leib als Fläche mit feinen Ringen, dunkle Spitze
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		for i in 9:
			var w := lerpf(2.5, 1.1, float(i) / 8.0) + (0.4 if i == 8 else 0.0)
			var dv := (abd[mini(i + 1, 8)] - abd[maxi(i - 1, 0)]).normalized()
			var nrm := dv.orthogonal() * w
			left.append(abd[i] + nrm)
			right.append(abd[i] - nrm)
		right.reverse()
		var leib := left + right
		draw_colored_polygon(leib, BODY)
		draw_colored_polygon(PackedVector2Array([left[7], left[8], right[0], right[1]]), BODY_D)
		for i in range(1, 8):
			var nrm := (abd[i + 1] - abd[i]).orthogonal().normalized() * lerpf(2.5, 1.1, float(i) / 8.0)
			draw_line(abd[i] + nrm, abd[i] - nrm, ca(INK, 0.5), 0.7, true)
		outline_poly(leib, ca(INK, 0.9), 0.8)
		draw_line(abd[1], abd[6], Color(1, 1, 1, 0.35), 0.6, true)
		# Brust und Kopf mit großen Augen
		ellipse_outlined(Vector2(5.5, 0.0), 6.0, 4.3, BODY_D, INK, 1.2)
		poly_ellipse(Vector2(4.6, -1.4), 2.2, 0.9, Color(1, 1, 1, 0.35), 0.2, 10)
		for sdv in [-1.0, 1.0]:
			var sd: float = sdv
			ellipse_outlined(Vector2(12.5, sd * 3.0), 3.5, 3.3, EYE, INK, 1.1)
			draw_circle(Vector2(13.4, sd * 3.0 - 1.1), 0.9, Color.WHITE, true, -1.0, true)
		# vier Flügel, schimmern zwischen Türkis und Violett
		for i in 4:
			var sd := -1.0 if i % 2 == 0 else 1.0
			var front := i < 2
			var base := Vector2(7.5 if front else 3.5, sd * 1.6)
			var ang := sd * (PI * 0.5 - (0.18 if front else -0.16)) + sin(t * 60.0 + float(i)) * 0.07 * wing_j
			var tint := Color("#19C6D4").lerp(Color("#A06BFF"), 0.5 + 0.5 * sin(t * 2.6 + shimmer + float(i) * 1.3))
			var fill := Color(1, 1, 1).lerp(tint, 0.4)
			fill.a = 0.36 + 0.1 * sin(t * 43.0 + float(i) * 2.0) * wing_j
			var ln := 20.0 if front else 19.0
			var wd := 6.4 if front else 7.6
			wing(base, ln, wd, ang, fill, ca(INK, 0.38), 0.8)
			var tip := base + Vector2.from_angle(ang) * (ln * 0.82)
			draw_line(base + Vector2.from_angle(ang) * 2.0, tip, ca(INK, 0.22), 0.7, true)
			draw_circle(tip + Vector2.from_angle(ang + sd * 0.2) * 0.6, 1.0, ca(INK, 0.55), true, -1.0, true)
		reset_xf()


# ================================================================================ 4 Pusteblumen-Samen

class Pusteblume extends Day:
	const SEED := Color("#8A5A2E")
	var seeds: Array = []         # je Samen: {d, v, x0, y0, amp, per, ph, r, spin}
	var dir := 1.0
	var hit_i := -1
	# Pose: je Samen [pos, rot, sx, a]
	var poses: Array = []

	func setup(c: Dictionary) -> void:
		s = 1.2 * k()
		var sz := table_size()
		var sky: Rect2 = c.get("ort") if c.get("ort") is Rect2 else Rect2(0, 0.04 * sz.y, sz.x, 0.26 * sz.y)
		dir = 1.0 if rng.randf() < 0.5 else -1.0
		var n := rng.randi_range(7, 10)
		in_s = 1.0
		out_s = 2.0
		# Höhe der Wolke aus Samen: die Bahn, die am wenigsten hinter Plätzen und Knöpfen liegt
		var lane := sky.get_center().y
		var best := 1.0e9
		var x_start := -20.0 if dir > 0.0 else sz.x + 20.0
		for i in 7:
			var y := lerpf(sky.position.y + 30.0, sky.end.y - 24.0, float(i) / 6.0)
			var cc := 0.0
			for j in 12:
				cc += covered(box(Vector2(x_start + dir * 1150.0 * k() * float(j) / 11.0, y), Vector2(150.0, 50.0)))
			cc += rng.randf() * 0.2
			if cc < best:
				best = cc
				lane = y
		for i in n:
			var d := rng.randf_range(0.0, 3.0)
			var r := rng.randf_range(8.0, 11.0)
			seeds.append({
				"d": d, "v": rng.randf_range(80.0, 100.0) * k(),
				"x0": (-15.0 - rng.randf_range(0.0, 40.0)) if dir > 0.0 else (sz.x + 15.0 + rng.randf_range(0.0, 40.0)),
				"y0": clampf(lane + rng.randf_range(-45.0, 45.0), sky.position.y + 18.0, sky.end.y - 14.0),
				"amp": rng.randf_range(12.0, 25.0), "per": rng.randf_range(3.0, 5.0), "ph": rng.randf_range(0.0, TAU),
				"r": r, "spin": rng.randf_range(0.6, 1.2) * (1.0 if rng.randf() < 0.5 else -1.0), "drift": rng.randf_range(-12.0, 12.0),
			})

	func _seed_base(sd: Dictionary, tb: float) -> Vector2:
		var tau := tb - float(sd["d"])
		var x := float(sd["x0"]) + dir * float(sd["v"]) * maxf(tau, 0.0)
		var y := float(sd["y0"]) + float(sd["amp"]) * sin(TAU * tb / float(sd["per"]) + float(sd["ph"])) + float(sd["drift"]) * tb / maxf(dur, 1.0)
		return Vector2(x, y)

	func pose_at(tt: float) -> void:
		poses.clear()
		var tp := since_tap(tt)
		var tap_base: Array = []
		if tp >= 0.0:
			for sd in seeds:
				tap_base.append(_seed_base(sd, tap_at))
		var fade := edge_fade(tt) if tt > in_s else 1.0
		for i in seeds.size():
			var sd: Dictionary = seeds[i]
			var p := _seed_base(sd, tt)
			var w := TAU * tt / float(sd["per"]) + float(sd["ph"])
			var rot := deg_to_rad(12.0) * cos(w)
			var sx := 0.86 + 0.14 * cos(tt * float(sd["spin"]) + float(sd["ph"]))
			if tp >= 0.0:
				var q: Vector2 = tap_base[i]
				var dist := q.distance_to(tap_pos)
				var f := clampf(1.0 - dist / 160.0, 0.0, 1.0)
				if i == hit_i:
					f = maxf(f, 0.6)
				if f > 0.0:
					var away := (q - tap_pos).normalized() if dist > 1.0 else Vector2.UP
					away = (away + Vector2(dir * 0.4, -0.3)).normalized()
					var e := 1.0 - exp(-tp / 0.45)
					p += away * 280.0 * k() * f * e
					rot += f * TAU * (1.0 - exp(-tp / 0.5)) * float(sd["spin"])
			var a := clampf((tt - float(sd["d"])) / 0.4, 0.0, 1.0) * fade
			poses.append([p, rot, sx, a, float(sd["r"]) * s])

	func on_tap(p: Vector2) -> void:
		var best := 1.0e9
		hit_i = -1
		for i in poses.size():
			var d := (poses[i][0] as Vector2).distance_to(p)
			if d < best:
				best = d
				hit_i = i

	func bounds() -> Rect2:
		var boxes: Array = []
		for ps in poses:
			if float(ps[3]) <= 0.02:
				continue
			var rr := float(ps[4])
			boxes.append(Rect2((ps[0] as Vector2) - Vector2(rr + 2.0, rr + 2.0), Vector2(rr * 2.0 + 4.0, rr + 16.0 * s)))
		return visible_hull(boxes)

	func hit(p: Vector2) -> bool:
		var b := bounds()
		return b.has_area() and b.grow(16.0).has_point(p)

	func _draw() -> void:
		for ps in poses:
			var a := float(ps[3])
			if a <= 0.01:
				continue
			var rr := float(ps[4])
			var sc := rr / 10.0
			draw_set_transform(ps[0], float(ps[1]), Vector2(sc * float(ps[2]), sc))
			# weicher Flaum hinter dem Schirmchen
			glow(Vector2(0, -4.5), 12.5, Color(1, 1, 1, 0.75 * a))
			# Stiel und Korn
			draw_line(Vector2(0, 0), Vector2(0, 12.0), ca(INK, 0.55 * a), 0.9, true)
			poly_ellipse(Vector2(0, 14.2), 1.4, 3.0, ca(SEED, a), 0.0, 10)
			draw_line(Vector2(0, 11.8), Vector2(0, 17.0), ca(INK, 0.4 * a), 0.7, true)
			# Schirmchen: 12 feine Strahlen, an den Spitzen weiße Flaumbüschel
			for j in 12:
				var ang := PI * 0.94 + PI * 1.12 * (float(j) + 0.5) / 12.0
				var tip := Vector2.from_angle(ang) * 10.0 * Vector2(1.0, 0.86)
				draw_line(Vector2(0, 0), tip, ca(Color("#7A6B58"), 0.6 * a), 0.7, true)
				for f in [-0.55, -0.2, 0.2, 0.55]:
					draw_line(tip, tip + Vector2.from_angle(ang + float(f)) * 3.4, ca(Color.WHITE, 0.95 * a), 1.0, true)
				draw_circle(tip, 1.25, ca(Color.WHITE, a), true, -1.0, true)
				draw_arc(tip, 1.4, 0.0, TAU, 8, ca(Color("#9C8B74"), 0.45 * a), 0.5, true)
			draw_circle(Vector2(0, 0), 1.2, ca(SEED, a), true, -1.0, true)
		reset_xf()


# ================================================================================ 5 Papierflieger

class Papierflieger extends Day:
	const STRIPES := [Color("#FF2FA8"), Color("#19C6D4"), Color("#FFB627")]
	var dir := 1.0
	var x0 := 0.0
	var x1 := 0.0
	var y0 := 0.0
	var ph := 0.0
	var ph2 := 0.0
	var span := 6.5               # Zeit für die Strecke (ohne Looping)
	var stripe := Color.WHITE
	# Pose
	var pos := Vector2.ZERO
	var vel := Vector2.RIGHT
	var roll := 1.0
	var looping := false

	func setup(c: Dictionary) -> void:
		s = 1.5 * k()
		var sz := table_size()
		var sky: Rect2 = c.get("ort") if c.get("ort") is Rect2 else Rect2(0, 0.04 * sz.y, sz.x, 0.26 * sz.y)
		dir = 1.0 if rng.randf() < 0.5 else -1.0
		x0 = -70.0 if dir > 0.0 else sz.x + 70.0
		x1 = sz.x + 70.0 if dir > 0.0 else -70.0
		ph = rng.randf_range(0.0, TAU)
		ph2 = rng.randf_range(0.0, TAU)
		stripe = STRIPES[rng.randi() % STRIPES.size()]
		span = dur
		# Höhe: die Bahn mit der kleinsten Überdeckung (Welle ±15, sinkt 40)
		var best := 1.0e9
		y0 = sky.position.y + 30.0
		for i in 8:
			var y := lerpf(sky.position.y + 4.0, sky.end.y - 60.0, float(i) / 7.0) + rng.randf_range(-4.0, 4.0)
			var cc := 0.0
			for j in 16:
				var u := float(j) / 15.0
				cc += covered(box(Vector2(lerpf(x0, x1, u), y + 40.0 * u + 15.0 * sin(TAU * u + ph)), Vector2(28.0, 16.0) * s))
			cc += absf(y - sky.get_center().y) * 0.002
			if cc < best:
				best = cc
				y0 = y
		in_s = 0.3
		out_s = 0.3

	func _path(u: float) -> Vector2:
		return Vector2(lerpf(x0, x1, u), y0 + 40.0 * u + 15.0 * sin(TAU * u + ph))

	func pose_at(tt: float) -> void:
		var tp := since_tap(tt)
		var tb := tt
		looping = false
		if tp >= 0.0:
			tb = tap_at if tp < 1.0 else tt - 1.0
		var u := clampf(tb / span, 0.0, 1.0)
		pos = _path(u)
		vel = _path(minf(u + 0.004, 1.0)) - _path(maxf(u - 0.004, 0.0))
		roll = 0.82 + 0.18 * sin(TAU * u * 2.0 + ph2)
		if tp >= 0.0 and tp < 1.0:
			looping = true
			var r := 45.0 * k()
			var phi := TAU * smoothstep(0.0, 1.0, tp)
			var cpos := pos + Vector2(0.0, -r)
			pos = cpos + Vector2(dir * r * sin(phi), r * cos(phi))
			vel = Vector2(dir * cos(phi), -sin(phi))
			roll = 0.8 + 0.2 * cos(phi)

	func on_tap(_p: Vector2) -> void:
		dur += 1.0

	func bounds() -> Rect2:
		if alpha <= 0.01:
			return Rect2()
		return box(pos, Vector2(28.0, 16.0) * s)

	func _draw() -> void:
		if alpha <= 0.003:
			return
		var f := dir
		var ang := (vel * f).angle() if vel.length() > 1e-4 else 0.0
		if looping:
			ang = vel.angle() if f > 0.0 else (vel * -1.0).angle()
		draw_set_transform(pos, ang, Vector2(s * f, s))
		var nose := Vector2(27.0, 0.0)
		var tm := Vector2(-23.0, 0.5)
		var tt_ := Vector2(-27.0, -10.0 * roll)
		var tn := Vector2(-25.0, 4.0 + 4.0 * (1.0 - roll))
		var kl := Vector2(-20.0, 9.0)
		var line := ca(INK, 0.9)
		# Kiel unten, nahe Fläche, ferne (obere) Fläche
		var keel := PackedVector2Array([nose, tm, kl])
		draw_colored_polygon(keel, Color("#D4C29E"))
		outline_poly(keel, line, 1.5)
		var near := PackedVector2Array([nose, tm, tn])
		draw_colored_polygon(near, PAPER_D)
		outline_poly(near, line, 1.5)
		var far := PackedVector2Array([nose, tt_, tm])
		draw_colored_polygon(far, Color("#FFFCF4"))
		# Zierstreifen auf der oberen Fläche
		draw_line(Vector2(-8.0, -3.4 * roll), Vector2(-20.5, -8.2 * roll), stripe, 2.2, true)
		outline_poly(far, line, 1.5)
		draw_line(nose, tm, ca(INK, 0.55), 1.0, true)
		reset_xf()


# ================================================================================ 6 Seifenblasen

class Seifenblasen extends Day:
	const TEAL := Color("#19C6D4")
	const PINK := Color("#FF4FB0")
	const GOLD := Color("#FFD24A")
	var bubbles: Array = []       # {d, life, r, src, vx, vy, wa, wf, ph}
	var popped := -1              # durch Tipp geplatzte Blase
	var src := Vector2.ZERO
	var dir := 1.0
	var poses: Array = []         # [pos, r, state (0 fliegt, >0 platzt: Anteil), a, ph]

	func setup(c: Dictionary) -> void:
		s = 1.15 * k()
		var sz := table_size()
		var lane: Rect2 = c.get("ort") if c.get("ort") is Rect2 else Rect2(0, 100, sz.x, 80)
		dir = 1.0 if rng.randf() < 0.5 else -1.0
		# Quelle: freie Stelle auf der Startseite des Streifens
		var best := 1.0e9
		for fx in [0.1, 0.17, 0.24, 0.31]:
			for fy in [0.3, 0.6, 0.9]:
				var x := float(fx) * sz.x if dir > 0.0 else sz.x - float(fx) * sz.x
				var q := Vector2(x, lane.position.y + lane.size.y * float(fy))
				var cc := covered(box(q + Vector2(dir * 90.0, -50.0), Vector2(110.0, 60.0))) + rng.randf() * 0.05
				if cc < best:
					best = cc
					src = q
		in_s = 0.6
		out_s = 0.6
		var n := rng.randi_range(5, 8)
		for i in n:
			var d := rng.randf_range(0.0, 4.0)
			var r := rng.randf_range(11.0, 24.0) * s
			var vy := -rng.randf_range(10.0, 20.0)
			var life := rng.randf_range(3.0, 7.0)
			var y_start := src.y + rng.randf_range(-24.0, 24.0)
			var top := (y_start - r - 4.0) / -vy
			life = minf(life, top)
			life = minf(life, dur - 0.35 - d)
			if life < 1.2:
				d = maxf(0.0, d - (1.2 - life))
				life = minf(maxf(life, 1.2), dur - 0.35 - d)
			bubbles.append({"d": d, "life": life, "r": r, "y": y_start, "ox": rng.randf_range(-30.0, 30.0), "vx": dir * rng.randf_range(30.0, 50.0), "vy": vy,
				"wa": rng.randf_range(5.0, 11.0), "wf": rng.randf_range(0.5, 0.9), "ph": rng.randf_range(0.0, TAU)})

	func _bpos(b: Dictionary, tau: float) -> Vector2:
		return Vector2(src.x + float(b["ox"]) + float(b["vx"]) * tau + float(b["wa"]) * sin(TAU * float(b["wf"]) * tau + float(b["ph"])),
			float(b["y"]) + float(b["vy"]) * tau)

	func _end_of(i: int) -> float:
		var b: Dictionary = bubbles[i]
		var e := float(b["d"]) + float(b["life"])
		if i == popped and tap_at >= 0.0:
			e = minf(e, tap_at)
		return e

	func pose_at(tt: float) -> void:
		poses.clear()
		for i in bubbles.size():
			var b: Dictionary = bubbles[i]
			var d := float(b["d"])
			if tt < d:
				continue
			var e := _end_of(i)
			var tau := minf(tt, e) - d
			var p := _bpos(b, tau)
			var a := clampf((tt - d) / 0.35, 0.0, 1.0)
			if tt < e:
				poses.append([p, float(b["r"]), 0.0, a, float(b["ph"]) + tt * 0.8, tt])
			elif tt < e + 0.28:
				poses.append([p, float(b["r"]), (tt - e) / 0.28, a, float(b["ph"]), tt])

	func on_tap(p: Vector2) -> void:
		var best := 1.0e9
		for i in bubbles.size():
			var b: Dictionary = bubbles[i]
			if tap_at < float(b["d"]) or tap_at >= _end_of(i):
				continue
			var d := _bpos(b, tap_at - float(b["d"])).distance_to(p)
			if d < best:
				best = d
				popped = i

	func alive_count() -> int:
		var n := 0
		for ps in poses:
			if float(ps[2]) <= 0.0:
				n += 1
		return n

	func bounds() -> Rect2:
		var r := Rect2()
		var first := true
		for ps in poses:
			var rr := float(ps[1]) * (1.0 + 0.5 * float(ps[2]))
			var b := box(ps[0], Vector2(rr, rr))
			r = b if first else r.merge(b)
			first = false
		return r

	func hit(p: Vector2) -> bool:
		var b := bounds()
		return b.has_area() and b.grow(12.0).has_point(p)

	func _draw() -> void:
		for ps in poses:
			var p: Vector2 = ps[0]
			var r := float(ps[1])
			var a := float(ps[3])
			var burst := float(ps[2])
			var tt_ := float(ps[5])
			if burst > 0.0:
				var rr := r * (1.0 + 0.45 * burst)
				draw_arc(p, rr, 0.0, TAU, 32, ca(TEAL, 0.6 * (1.0 - burst) * a), 1.6, true)
				for j in 6:
					var dv := Vector2.from_angle(TAU * float(j) / 6.0 + float(ps[4]))
					draw_circle(p + dv * r * (1.0 + 0.9 * burst), 1.7 * s, ca(TEAL.lerp(PINK, float(j % 2)), 0.8 * (1.0 - burst) * a), true, -1.0, true)
				continue
			var wob := 0.04 * sin(tt_ * 5.3 + float(ps[4]))
			var rx := r * (1.0 + wob)
			var ry := r * (1.0 - wob)
			poly_ellipse(p, rx, ry, ca(Color.WHITE, 0.14 * a), 0.0, 28)
			var rim := ellipse_points(p, rx, ry, 0.0, 32)
			outline_poly(rim, ca(Color("#7CCFDD"), 0.45 * a), 1.2)
			var a0 := float(ps[4])
			draw_arc(p, r - 1.2, a0, a0 + 2.3, 20, ca(TEAL, 0.6 * a), 2.2, true)
			draw_arc(p, r - 2.8, a0 + 0.3, a0 + 1.9, 16, ca(TEAL, 0.3 * a), 1.4, true)
			draw_arc(p, r - 1.2, a0 + PI, a0 + PI + 2.0, 20, ca(PINK, 0.55 * a), 2.0, true)
			draw_arc(p, r - 2.8, a0 + PI + 0.3, a0 + PI + 1.6, 16, ca(PINK, 0.28 * a), 1.3, true)
			draw_arc(p, r - 1.6, a0 + 2.45, a0 + 2.95, 8, ca(GOLD, 0.45 * a), 1.6, true)
			poly_ellipse(p + Vector2(-0.36 * r, -0.42 * r), 0.24 * r, 0.13 * r, ca(Color.WHITE, 0.9 * a), -0.7, 14)
			draw_circle(p + Vector2(0.32 * r, 0.44 * r), maxf(0.08 * r, 1.0), ca(Color.WHITE, 0.6 * a), true, -1.0, true)


# ================================================================================ 7 Spatz

class Spatz extends Day:
	const BROWN := Color("#A0703C")
	const BROWN_D := Color("#6E4A26")
	const BREAST := Color("#E8D2B0")
	const CAP := Color("#8C8478")
	var bt: Dictionary = {}
	var acts: Array = []          # [t0, t1, art, d0, d1, f]  art: hop | peck | look | turn | idle
	var land_d := 0.0
	var from := Vector2.ZERO
	var ctrl := Vector2.ZERO
	var t_land := 1.0
	var t_off := 8.0
	var f_in := 1.0
	var feathers: Array = []
	# Pose
	var pos := Vector2.ZERO
	var dirv := Vector2.RIGHT
	var face := 1.0
	var flying := false
	var flap := 0.0
	var nod := 0.0
	var tail := 0.0
	var ground := Vector2.ZERO
	var hop_h := 0.0

	func setup(c: Dictionary) -> void:
		s = 1.35 * k()
		own_leave = true
		var o: Variant = c.get("ort")
		var deg := float((o as Dictionary).get("deg", 270.0)) if o is Dictionary else 270.0
		bt = band_track(deg - 22.0, deg + 22.0, 0.5)
		land_d = float(bt["len"]) * 0.5
		f_in = 1.0 if rng.randf() < 0.5 else -1.0
		in_s = t_land
		out_s = 0.8
		t_off = dur - out_s
		var lp := along(bt, land_d)
		from = Vector2(lp.x - f_in * 230.0 * k(), -50.0)
		ctrl = Vector2(lp.x - f_in * 60.0 * k(), lp.y - 140.0 * k())
		# Ablauf am Boden: mindestens zwei Hüpfer, Picken, Umdrehen
		var tt := t_land + 0.15
		var d := land_d
		var f := f_in
		var plan := ["hop", "peck", "hop", "look", "turn", "hop", "peck", "idle", "hop", "turn", "peck", "look", "hop"]
		var start := rng.randi() % 2
		var lim := minf(float(bt["len"]) * 0.5 - 6.0, 46.0 * k())
		var i := start
		while tt < t_off - 0.2:
			var art: String = plan[i % plan.size()]
			i += 1
			if rng.randf() < 0.25 and art != "turn":
				art = ["idle", "look", "peck"][rng.randi() % 3]
			var dd := 0.0
			var len_t := 0.3
			match art:
				"hop":
					dd = f * rng.randf_range(12.0, 18.0) * k()
					if absf(d + dd - land_d) > lim:
						art = "turn"
						dd = 0.0
						len_t = 0.18
					else:
						len_t = 0.25
				"peck":
					len_t = 0.78
				"look":
					len_t = rng.randf_range(0.5, 0.8)
				"turn":
					len_t = 0.18
				_:
					len_t = rng.randf_range(0.3, 0.5)
			len_t = minf(len_t, t_off - tt)
			acts.append([tt, tt + len_t, art, d, d + dd, f])
			d += dd
			if art == "turn":
				f = -f
			tt += len_t
			if art == "hop":
				var rest := minf(0.14, t_off - tt)
				acts.append([tt, tt + rest, "idle", d, d, f])
				tt += rest
		for j in 2:
			feathers.append({"dx": rng.randf_range(-10.0, 10.0), "sw": rng.randf_range(0.7, 1.1), "ph": rng.randf_range(0.0, TAU),
				"rot": rng.randf_range(-1.0, 1.0)})

	func _act(tb: float) -> Array:
		for a in acts:
			if tb >= float(a[0]) and tb < float(a[1]):
				return a
		return acts[acts.size() - 1] if not acts.is_empty() else [t_land, t_off, "idle", land_d, land_d, f_in]

	func _ground_end() -> Array:
		if acts.is_empty():
			return [land_d, f_in]
		var a: Array = acts[acts.size() - 1]
		var f := float(a[5])
		if str(a[2]) == "turn":
			f = -f
		return [float(a[4]), f]

	func _base(tb: float) -> void:
		flying = false
		nod = 0.0
		tail = 0.0
		hop_h = 0.0
		if tb < t_land:
			var u := clampf(tb / t_land, 0.0, 1.0)
			var e := 1.0 - (1.0 - u) * (1.0 - u)
			pos = bez2(from, ctrl, along(bt, land_d), e)
			ground = along(bt, land_d)
			face = f_in
			dirv = bez2(from, ctrl, along(bt, land_d), minf(e + 0.03, 1.0)) - pos
			flying = u < 0.88
			flap = sin(tb * TAU * 12.0)
			if not flying:
				flap = -0.6
			return
		if tb < t_off:
			var a := _act(tb)
			var u := clampf((tb - float(a[0])) / maxf(float(a[1]) - float(a[0]), 1e-4), 0.0, 1.0)
			var d := float(a[3])
			face = float(a[5])
			match str(a[2]):
				"hop":
					d = lerpf(float(a[3]), float(a[4]), u)
					hop_h = 8.0 * k() * sin(PI * u)
					tail = -0.25 * sin(PI * u)
				"peck":
					nod = 0.55 * absf(sin(u * PI * 3.0))
				"look":
					nod = -0.22 * sin(PI * u)
				"turn":
					face = float(a[5]) if u < 0.5 else -float(a[5])
					hop_h = 3.0 * k() * sin(PI * u)
				_:
					tail = 0.2 * sin(u * TAU)
			ground = along(bt, d)
			pos = ground - Vector2(0.0, hop_h)
			dirv = Vector2(face, 0.0)
			return
		var ge := _ground_end()
		var u := clampf((tb - t_off) / out_s, 0.0, 1.0)
		face = float(ge[1])
		ground = along(bt, float(ge[0]))
		pos = ground + Vector2(face * 170.0 * u, -(330.0 * u * u + 70.0 * u)) * k()
		dirv = Vector2(face, -1.2)
		flying = true
		flap = sin(tb * TAU * 12.0)
		alpha = 1.0 - ramp(u, 0.6, 1.0)

	func pose_at(tt: float) -> void:
		var tb := tt
		var lv := since_leave(tt)
		var tp := since_tap(tt)
		if lv >= 0.0:
			tb = leave_at
		if tp >= 0.0:
			tb = minf(tb, tap_at)
		_base(tb)
		if tp >= 0.0:
			var u := clampf(tp / 0.6, 0.0, 1.0)
			var away := 1.0 if pos.x >= tap_pos.x else -1.0
			face = away
			pos += Vector2(away * 160.0 * u, -(300.0 * u * u + 90.0 * u)) * k()
			dirv = Vector2(away, -1.3)
			flying = true
			flap = sin(tt * TAU * 15.0)
			alpha *= 1.0 - ramp(u, 0.55, 1.0)
		if lv >= 0.0:
			var u := clampf(lv / maxf(leave_s, 0.01), 0.0, 1.0)
			pos += Vector2(face * 90.0 * u, -(220.0 * u * u + 40.0 * u)) * k()
			dirv = Vector2(face, -1.2)
			flying = true
			flap = sin(tt * TAU * 14.0)
			alpha *= 1.0 - ramp(u, 0.35, 1.0)

	func on_tap(_p: Vector2) -> void:
		dur = minf(dur, tap_at + 0.95)

	func bounds() -> Rect2:
		if alpha <= 0.01:
			return Rect2()
		return box(pos + Vector2(0.0, -3.0) * s, Vector2(22.0, 16.0) * s)

	func _draw_feathers() -> void:
		var tp := since_tap(t)
		if tp < 0.0:
			return
		var origin := _tap_origin()
		for fe in feathers:
			var u := tp / 0.95
			var p := origin + Vector2(float(fe["dx"]) + sin(tp * 6.0 * float(fe["sw"]) + float(fe["ph"])) * 9.0, -6.0 + 34.0 * tp) * s
			var a := 1.0 - ramp(u, 0.55, 1.0)
			draw_set_transform(p, float(fe["rot"]) + sin(tp * 6.0 * float(fe["sw"]) + float(fe["ph"])) * 0.6, Vector2(s, s))
			var pts := ellipse_points(Vector2.ZERO, 7.0, 2.6, 0.0, 16)
			draw_colored_polygon(pts, ca(BREAST, a))
			draw_colored_polygon(ellipse_points(Vector2(2.5, 0.0), 4.0, 2.0, 0.0, 12), ca(BROWN, a))
			outline_poly(pts, ca(INK, 0.55 * a), 0.8)
			draw_line(Vector2(-9.0, 0.0), Vector2(6.0, 0.0), ca(INK, 0.6 * a), 0.8, true)
			reset_xf()

	func _tap_origin() -> Vector2:
		var keep_t := t
		var save := [pos, dirv, face, flying, flap, nod, tail, ground, hop_h, alpha]
		alpha = 1.0
		_base(tap_at)
		var o := pos
		pos = save[0]
		dirv = save[1]
		face = save[2]
		flying = save[3]
		flap = save[4]
		nod = save[5]
		tail = save[6]
		ground = save[7]
		hop_h = save[8]
		alpha = save[9]
		t = keep_t
		return o

	func _draw() -> void:
		_draw_feathers()
		if alpha <= 0.003:
			return
		if not flying:
			shadow(ground + Vector2(0.0, 13.0) * s, 11.0 * s, 3.2 * s, 0.16 * (1.0 - clampf(hop_h / (12.0 * s), 0.0, 0.5)))
		var tilt_v := dirv if flying else Vector2(face, 0.0)
		side_xf(pos, tilt_v, s, face, 0.5)
		# ferner Flügel (nur im Flug)
		if flying:
			_wing(Vector2(1.5, -3.0), -0.35 + flap * 0.7 + 0.25, Color("#5A3B1E"), 0.85)
		# Schwanz
		var txf := Transform2D(tail, Vector2(-9.0, 1.0)) * Transform2D(0.0, Vector2(9.0, -1.0))
		var tl := txf * PackedVector2Array([Vector2(-8.5, -1.5), Vector2(-21.0, -7.5), Vector2(-22.5, -3.5), Vector2(-9.5, 3.0)])
		draw_colored_polygon(tl, BROWN_D)
		outline_poly(tl, INK, 1.2)
		# Beine
		if not flying:
			for lx in [-0.5, 3.0]:
				var x := float(lx)
				draw_line(Vector2(x, 7.0), Vector2(x - 0.8, 13.0), Color("#5B4030"), 1.3, true)
				draw_line(Vector2(x - 0.8, 13.0), Vector2(x + 2.4, 13.4), Color("#5B4030"), 1.1, true)
		# Körper mit heller Brust
		var body := ellipse_points(Vector2(-1.0, 1.0), 11.5, 8.5, -0.12, 26)
		draw_colored_polygon(body, BROWN)
		poly_ellipse(Vector2(2.5, 3.2), 6.8, 4.9, BREAST, -0.1, 18)
		outline_poly(body, INK, 1.4)
		# Kopf (nickt beim Picken)
		var hxf := Transform2D(nod, Vector2(7.0, -2.0)) * Transform2D(0.0, Vector2(-7.0, 2.0))
		var head := hxf * ellipse_points(Vector2(9.5, -6.0), 6.2, 6.0, 0.0, 22)
		draw_colored_polygon(head, BROWN)
		var cap := PackedVector2Array()
		for j in 10:
			var a := deg_to_rad(195.0 + 150.0 * float(j) / 9.0)
			cap.append(hxf * (Vector2(9.5, -6.0) + Vector2(cos(a) * 6.2, sin(a) * 6.0)))
		cap.append(hxf * Vector2(12.0, -6.4))
		cap.append(hxf * Vector2(6.5, -6.0))
		draw_colored_polygon(cap, CAP)
		draw_colored_polygon(hxf * ellipse_points(Vector2(10.6, -3.6), 3.3, 2.2, -0.2, 14), Color("#EFE2CC"))
		draw_colored_polygon(hxf * ellipse_points(Vector2(13.4, -1.3), 2.1, 1.7, 0.0, 12), INK)
		outline_poly(head, INK, 1.3)
		var beak := hxf * PackedVector2Array([Vector2(15.0, -7.6), Vector2(20.2, -6.0), Vector2(15.0, -4.4)])
		draw_colored_polygon(beak, INK)
		draw_circle(hxf * Vector2(12.0, -7.4), 1.5, INK, true, -1.0, true)
		draw_circle(hxf * Vector2(12.5, -7.9), 0.55, Color.WHITE, true, -1.0, true)
		# naher Flügel mit zwei hellen Binden
		if flying:
			_wing(Vector2(2.0, -3.0), -0.35 + flap * 0.75, BROWN_D, 1.0)
		else:
			var wg := PackedVector2Array([Vector2(4.0, -3.0), Vector2(-2.0, -5.0), Vector2(-10.0, -3.2), Vector2(-14.5, 0.2),
				Vector2(-8.0, 2.4), Vector2(0.5, 1.6)])
			draw_colored_polygon(wg, BROWN_D)
			draw_line(Vector2(-3.0, -4.2), Vector2(-5.0, 1.6), Color("#F2E3C4"), 1.3, true)
			draw_line(Vector2(-7.2, -3.4), Vector2(-9.2, 1.6), Color("#F2E3C4"), 1.3, true)
			draw_line(Vector2(-10.5, -2.4), Vector2(-13.5, 0.6), ca(Color("#C99A62"), 0.9), 1.0, true)
			outline_poly(wg, INK, 1.1)
		reset_xf()

	# Flügel im Flug: um die Schulter gedreht (Schlag ±40°)
	func _wing(sh: Vector2, ang: float, col: Color, a: float) -> void:
		var xf := Transform2D(ang, sh)
		var pts := xf * PackedVector2Array([Vector2(0, 0), Vector2(-4.0, -6.0), Vector2(-12.0, -11.0), Vector2(-19.0, -10.0),
			Vector2(-14.0, -4.0), Vector2(-6.0, 1.5)])
		draw_colored_polygon(pts, ca(col, a))
		draw_line(xf * Vector2(-6.0, -5.0), xf * Vector2(-10.0, -2.0), ca(Color("#F2E3C4"), a), 1.2, true)
		outline_poly(pts, ca(INK, a), 1.1)


# ================================================================================ 8 Wolke vor der Sonne

class Wolke extends Day:
	const EDGE := Color("#D8C6A2")
	const PUFFS := [[Vector2(-74, 14), 28.0], [Vector2(-40, -6), 36.0], [Vector2(2, -20), 44.0], [Vector2(46, -4), 36.0],
		[Vector2(80, 14), 26.0], [Vector2(-14, 16), 32.0], [Vector2(30, 18), 30.0]]
	var sun := Vector2.ZERO
	var sun_r := 64.0
	var x0 := 0.0
	var x1 := 0.0
	var y := 0.0
	var puffs: Array = []
	# Pose
	var cpos := Vector2.ZERO
	var shade := 0.0

	func setup(c: Dictionary) -> void:
		s = k()
		var o: Variant = c.get("ort")
		sun = (o as Dictionary).get("pos", Vector2(112, 22)) if o is Dictionary else Vector2(112, 22)
		sun_r = float((o as Dictionary).get("r", 64.0)) if o is Dictionary else 64.0
		for p in PUFFS:
			puffs.append([(p[0] as Vector2) + Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(-3.0, 3.0)), float(p[1]) * rng.randf_range(0.92, 1.08)])
		if calm:
			dur = 10.0
			in_s = 2.0
			out_s = 2.0
			cpos = sun + Vector2(190.0, 40.0) * s
			return
		# zieht von rechts heran und schiebt sich vor die Sonne (die Sonne liegt halb hinter den Knöpfen oben links; so ist die
		# Wolke vorher gut zu sehen), dort blendet sie aus
		y = sun.y + rng.randf_range(10.0, 25.0) * s + 14.0 * s
		x0 = sun.x + rng.randf_range(600.0, 680.0) * s
		x1 = sun.x + 20.0 * s
		in_s = 1.5
		out_s = 1.5

	func pose_at(tt: float) -> void:
		if calm:
			alpha = edge_fade(tt)
		else:
			cpos = Vector2(lerpf(x0, x1, clampf(tt / dur, 0.0, 1.0)), y + sin(tt * 0.6) * 2.0 * s)
			alpha = edge_fade(tt)
		var dx := absf(cpos.x - sun.x)
		shade = (1.0 - smoothstep(60.0 * s, 170.0 * s, dx)) * alpha * (0.6 if calm else 1.0)

	func bounds() -> Rect2:
		if alpha <= 0.01:
			return Rect2()
		var boxes: Array = []
		for p in puffs:
			var r := (float(p[1]) + 2.5) * s
			boxes.append(box(cpos + (p[0] as Vector2) * s, Vector2(r, r)))
		return visible_hull(boxes)

	func _draw() -> void:
		if alpha <= 0.003:
			return
		var sz := table_size()
		if shade > 0.002:
			draw_rect(Rect2(Vector2(-20, -20), sz + Vector2(40, 40)), ca(INK, 0.05 * shade))
		for p in puffs:
			glow(cpos + (p[0] as Vector2) * s, float(p[1]) * s * 1.7, Color(1, 1, 1, 0.25))
		for p in puffs:
			draw_circle(cpos + ((p[0] as Vector2) + Vector2(0, 1.5)) * s, (float(p[1]) + 2.5) * s, EDGE, true, -1.0, true)
		for p in puffs:
			draw_circle(cpos + ((p[0] as Vector2) + Vector2(0, 3.0)) * s, float(p[1]) * s, PAPER_D, true, -1.0, true)
		for p in puffs:
			draw_circle(cpos + ((p[0] as Vector2) + Vector2(0, -1.5)) * s, (float(p[1]) - 1.5) * s, Color("#FFFEFA"), true, -1.0, true)
		# zarte Lichtkante oben
		for p in puffs:
			var pc: Vector2 = p[0]
			if pc.y < 0.0:
				draw_arc(cpos + (pc + Vector2(0, -1.5)) * s, (float(p[1]) - 6.0) * s, PI * 1.15, PI * 1.6, 10, Color(1, 1, 1, 0.9), 2.0 * s, true)


# ================================================================================ 9 Regenbogen nach Flip

class Regenbogen extends Day:
	const BANDS := [Color("#FF4D57"), Color("#FF8A1F"), Color("#FFDD33"), Color("#4FD36E"), Color("#4C7DFF"), Color("#8B6BFF")]
	const SEGS := 56
	var ctr := Vector2.ZERO
	var rad := 1000.0
	var a0 := PI
	var a1 := TAU
	var apex := 50.0
	var y_base := 360.0
	var bw := 9.0
	# Pose
	var grow := 1.0

	func setup(c: Dictionary) -> void:
		s = k()
		var sz := table_size()
		var o: Variant = c.get("ort")
		var cc: Vector2 = (o as Dictionary).get("center", Vector2(sz.x * 0.5, sz.y * 0.5)) if o is Dictionary else Vector2(sz.x * 0.5, sz.y * 0.5)
		var half := float((o as Dictionary).get("r", 0.46 * sz.x)) if o is Dictionary else 0.46 * sz.x
		# Bogen mit dem Scheitel oben im freien Himmel, Füße bei ±0,46 W auf Höhe der Tischmitte (+40)
		bw = 9.0 * s
		apex = 0.02 * sz.y + 2.0
		y_base = cc.y
		var d := y_base - apex
		rad = (half * half + d * d) / (2.0 * d)
		ctr = Vector2(cc.x, apex + rad)
		var ang := atan2(y_base - ctr.y, half)
		a0 = PI - ang
		a1 = TAU + ang
		dur = 7.0
		in_s = 1.5
		out_s = 2.0

	func pose_at(tt: float) -> void:
		if calm:
			grow = 1.0
			alpha = clampf(tt / 1.5, 0.0, 1.0) * clampf((dur - tt) / 2.0, 0.0, 1.0)
			return
		grow = smoothstep(0.0, 1.0, clampf(tt / 1.5, 0.0, 1.0))
		alpha = clampf(tt / 0.3, 0.0, 1.0) * clampf((dur - tt) / 2.0, 0.0, 1.0)

	func _fade_y(y: float) -> float:
		var y_f := y_base - 0.5 * (y_base - apex)
		return 1.0 - smoothstep(y_f, y_base - 10.0, y)

	func _pt(a: float, r: float) -> Vector2:
		return ctr + Vector2(cos(a), sin(a)) * r

	func bounds() -> Rect2:
		if alpha <= 0.01 or grow <= 0.01:
			return Rect2()
		# sichtbarer Teil: Stücke des Bogens, die nicht hinter Plätzen und Knöpfen liegen (er liegt hinter allem)
		var ae := lerpf(a0, a1, grow)
		var outer := rad
		var inner := rad - bw * 6.0
		var boxes: Array = []
		var n := 28
		for i in n:
			var b0 := lerpf(a0, ae, float(i) / float(n))
			var b1 := lerpf(a0, ae, float(i + 1) / float(n))
			var p := _pt((b0 + b1) * 0.5, outer)
			if _fade_y(p.y) < 0.5:
				continue
			boxes.append(Rect2(_pt(b0, outer), Vector2.ZERO).expand(_pt(b1, outer)).expand(_pt(b0, inner)).expand(_pt(b1, inner)))
		return visible_hull(boxes)

	func _draw() -> void:
		if alpha <= 0.003 or grow <= 0.003:
			return
		var ae := lerpf(a0, a1, grow)
		var n := maxi(2, int(SEGS * grow) + 1)
		var bands: Array = [[Color(BANDS[0], 0.08), rad + 5.0 * s, rad]]
		for i in BANDS.size():
			bands.append([Color(BANDS[i], 0.36), rad - bw * float(i), rad - bw * float(i + 1)])
		bands.append([Color(BANDS[BANDS.size() - 1], 0.08), rad - bw * 6.0, rad - bw * 6.0 - 5.0 * s])
		for bd in bands:
			var col: Color = bd[0]
			var ro := float(bd[1])
			var ri := float(bd[2])
			for i in n:
				var u0 := float(i) / float(n)
				var u1 := float(i + 1) / float(n)
				var b0 := lerpf(a0, ae, u0)
				var b1 := lerpf(a0, ae, u1)
				var po0 := _pt(b0, ro)
				var po1 := _pt(b1, ro)
				var pi0 := _pt(b0, ri)
				var pi1 := _pt(b1, ri)
				# weiche Wachstumskante und ausblendende Füße
				var e0 := clampf((1.0 - u0) * float(n) / 3.0, 0.0, 1.0) if grow < 0.999 else 1.0
				var e1 := clampf((1.0 - u1) * float(n) / 3.0, 0.0, 1.0) if grow < 0.999 else 1.0
				var c0 := ca(col, alpha * e0 * _fade_y(po0.y))
				var c1 := ca(col, alpha * e1 * _fade_y(po1.y))
				var ci0 := ca(col, alpha * e0 * _fade_y(pi0.y))
				var ci1 := ca(col, alpha * e1 * _fade_y(pi1.y))
				if c0.a + c1.a + ci0.a + ci1.a < 0.004:
					continue
				draw_primitive(PackedVector2Array([po0, po1, pi1, pi0]), PackedColorArray([c0, c1, ci1, ci0]), PackedVector2Array())


# ================================================================================ 10 Heißluftballon

class Heissluftballon extends Day:
	const GORES := [Color("#FF4D57"), Color("#FFDD33"), Color("#4FD36E"), Color("#4C7DFF"), Color("#FFF7E8")]
	const BASKET := Color("#A0703C")
	var dir := 1.0
	var x0 := 0.0
	var speed := 80.0
	var y0 := 80.0
	var ph := 0.0
	var bursts: Array = []        # [t0, t1] Brennerstöße
	var rise_from := Vector2.ZERO
	# Pose
	var pos := Vector2.ZERO
	var rot := 0.0
	var flame := 0.0

	func setup(c: Dictionary) -> void:
		s = 1.4 * k()
		var sz := table_size()
		var lane: Rect2 = c.get("ort") if c.get("ort") is Rect2 else Rect2(0, 0.06 * sz.y, sz.x, 0.12 * sz.y)
		dir = 1.0 if rng.randf() < 0.5 else -1.0
		x0 = -40.0 * s if dir > 0.0 else sz.x + 40.0 * s
		speed = (sz.x + 80.0 * s) / dur
		ph = rng.randf_range(0.0, TAU)
		var best := 1.0e9
		for i in 5:
			var y := lerpf(lane.position.y + 10.0, lane.end.y - 10.0, float(i) / 4.0)
			var cc := 0.0
			for j in 20:
				var x := x0 + dir * speed * dur * float(j) / 19.0
				cc += covered(Rect2(Vector2(x, y) + Vector2(-25.0, -37.0) * s, Vector2(50.0, 76.0) * s))
			cc += rng.randf() * 0.05
			if cc < best:
				best = cc
				y0 = y
		var tt := rng.randf_range(1.0, 3.0)
		while tt < dur - 1.0:
			bursts.append([tt, tt + rng.randf_range(0.4, 0.7)])
			tt += rng.randf_range(2.5, 4.5)
		in_s = 0.6
		out_s = 0.6

	func _drift(tb: float) -> Vector2:
		return Vector2(x0 + dir * speed * tb, y0 + 4.0 * sin(TAU * tb / 4.0 + ph))

	func pose_at(tt: float) -> void:
		var tp := since_tap(tt)
		var tb := tt if tp < 0.0 else tap_at
		pos = _drift(tb)
		rot = 0.05 * sin(TAU * tb / 4.0 + ph + 1.0)
		flame = 0.0
		for b in bursts:
			if tt >= float(b[0]) and tt < float(b[1]):
				var u := (tt - float(b[0])) / (float(b[1]) - float(b[0]))
				flame = sin(PI * u)
		if tp >= 0.0:
			flame = maxf(flame, 1.6 * (1.0 - ramp(tp, 0.3, 0.6)) if tp < 0.6 else 0.6)
			var u := maxf(tp - 0.25, 0.0)
			pos += Vector2(dir * 55.0 * u, -(70.0 * u * u + 90.0 * u)) * k()
			rot += -dir * 0.05 * ramp(tp, 0.0, 0.6)
			alpha *= 1.0 - ramp(tp, 1.3, 1.8)

	func on_tap(_p: Vector2) -> void:
		dur = minf(dur, tap_at + 1.8)

	func bounds() -> Rect2:
		if alpha <= 0.01:
			return Rect2()
		return Rect2(pos + Vector2(-25.0, -37.0) * s, Vector2(50.0, 76.0) * s)

	static func _r(y: float) -> float:
		if y < -14.0:
			var v := (y + 14.0) / 22.0
			return 24.0 * sqrt(maxf(0.0, 1.0 - v * v))
		var u := clampf((y + 14.0) / 32.0, 0.0, 1.0)
		return 6.0 + 18.0 * cos(u * PI * 0.5)

	func _draw() -> void:
		if alpha <= 0.003:
			return
		draw_set_transform(pos, rot, Vector2(s, s))
		# Seile und Korb
		for rx in [-6.0, -2.0, 2.0, 6.0]:
			draw_line(Vector2(float(rx), 19.0), Vector2(float(rx) * 0.8, 30.0), ca(INK, 0.75), 1.0, true)
		var bk := PackedVector2Array([Vector2(-6.5, 30.0), Vector2(6.5, 30.0), Vector2(5.2, 38.0), Vector2(-5.2, 38.0)])
		draw_colored_polygon(bk, BASKET)
		draw_line(Vector2(-6.0, 33.0), Vector2(6.0, 33.0), ca(INK, 0.35), 0.9, true)
		draw_line(Vector2(-5.6, 35.6), Vector2(5.6, 35.6), ca(INK, 0.35), 0.9, true)
		for vx in [-3.0, 0.0, 3.0]:
			draw_line(Vector2(float(vx), 30.5), Vector2(float(vx) * 0.85, 37.5), ca(INK, 0.25), 0.8, true)
		outline_poly(bk, INK, 1.3)
		# Flamme
		if flame > 0.02:
			var fh := 4.0 + 8.0 * flame
			glow(Vector2(0, 24.0), 9.0 + 9.0 * flame, Color(1.0, 0.72, 0.2, 0.45 * minf(flame, 1.0)))
			draw_colored_polygon(PackedVector2Array([Vector2(-3.0, 27.0), Vector2(0.0, 27.0 - fh), Vector2(3.0, 27.0)]), Color("#FF8A24"))
			draw_colored_polygon(PackedVector2Array([Vector2(-1.5, 27.0), Vector2(0.0, 27.0 - fh * 0.6), Vector2(1.5, 27.0)]), Color("#FFDD33"))
		# Hülle: fünf Bahnen
		var ys := PackedFloat32Array()
		for i in 25:
			ys.append(lerpf(-36.0, 18.0, float(i) / 24.0))
		for g in 5:
			var p0 := -PI * 0.5 + PI * float(g) / 5.0
			var p1 := -PI * 0.5 + PI * float(g + 1) / 5.0
			var pts := PackedVector2Array()
			for y in ys:
				pts.append(Vector2(_r(y) * sin(p0), y))
			for i in range(ys.size() - 1, -1, -1):
				pts.append(Vector2(_r(ys[i]) * sin(p1), ys[i]))
			draw_colored_polygon(pts, GORES[g])
			if g > 0:
				var seam := PackedVector2Array()
				for y in ys:
					seam.append(Vector2(_r(y) * sin(p0), y))
				draw_polyline(seam, ca(INK, 0.45), 1.0, true)
		var sil := PackedVector2Array()
		for y in ys:
			sil.append(Vector2(_r(y), y))
		for i in range(ys.size() - 1, -1, -1):
			sil.append(Vector2(-_r(ys[i]), ys[i]))
		outline_poly(sil, INK, 1.5)
		poly_ellipse(Vector2(-10.0, -22.0), 4.5, 9.0, Color(1, 1, 1, 0.32), 0.35, 16)
		# Schürze
		var sk := PackedVector2Array([Vector2(-6.5, 17.0), Vector2(6.5, 17.0), Vector2(5.8, 21.0), Vector2(-5.8, 21.0)])
		draw_colored_polygon(sk, CREAM)
		outline_poly(sk, INK, 1.2)
		reset_xf()


# ================================================================================ 11 Schnecke bei Trödlern

class Schnecke extends Day:
	const BODY := Color("#B9C7A0")
	const BODY_D := Color("#8FA078")
	const SHELL := Color("#C9803E")
	const SHELL_D := Color("#8E4F1E")
	var bt: Dictionary = {}       # Weg vom Start zum Ziel
	var speed := 6.0
	var t_emerge := 1.0
	# Pose
	var dist := 0.0
	var pos := Vector2.ZERO
	var dirv := Vector2.RIGHT
	var face := 1.0
	var ext := 1.0                # 0 im Haus … 1 ausgestreckt
	var quer_o := 0.0             # Hervorkriechen: Versatz nach außen
	var crawl_ph := 0.0
	var trail_from := 0.0

	func setup(c: Dictionary) -> void:
		s = 1.5 * k()
		own_leave = true
		speed = 6.0 * k()
		in_s = t_emerge
		out_s = 0.9
		var o: Variant = c.get("ort")
		var target := float((o as Dictionary).get("deg", 115.0)) if o is Dictionary else 115.0
		var need := speed * (dur - in_s - out_s) + 8.0
		# Richtung und Endpunkt: möglichst frei sichtbar, nie unter der Hinweisleiste (66–114°)
		var best: Dictionary = {}
		var best_c := 1.0e9
		for off in [0.0, 4.0, 8.0, 12.0, 18.0, 24.0, 32.0, 40.0]:
			for sdv in [1.0, -1.0]:
				var sd: float = sdv
				var endd := target + sd * float(off)
				var span := _span_for(endd, sd, need)
				var startd := endd + sd * span
				var cc := _score(startd, endd) + float(off) * 0.01
				if cc < best_c:
					best_c = cc
					best = {"a": startd, "b": endd}
			if best_c < 0.1:
				break
		bt = band_track(float(best["a"]), float(best["b"]), 0.55)

	# Grad-Spanne für need px Weg ab endd in Richtung sd (Start liegt bei endd + sd·span)
	func _span_for(endd: float, sd: float, need: float) -> float:
		var acc := 0.0
		var span := 0.0
		var prev := band(endd, 0.55)
		while acc < need and span < 120.0:
			span += 1.0
			var p := band(endd + sd * span, 0.55)
			acc += p.distance_to(prev)
			prev = p
		return span

	func _score(a: float, b: float) -> float:
		var cc := 0.0
		var n := 14
		for i in n + 1:
			var d := lerpf(a, b, float(i) / float(n))
			var dm := fposmod(d, 360.0)
			if dm > 64.0 and dm < 116.0:
				cc += 3.0
			var hb := box(band(d, 0.55) + Vector2(0.0, -5.0) * s, Vector2(20.0, 14.0) * s)
			cc += covered(hb) * 2.0
			for r in (ctx.get("obstacles", {}) as Dictionary).get("leiste", []):
				if hb.intersects(r):
					cc += 3.0
		return cc / float(n + 1)

	func _crawl_time(tt: float) -> float:
		var x := maxf(tt - in_s, 0.0)
		if tap_at >= 0.0 and tt > tap_at:
			x -= minf(tt - tap_at, 2.8)
		return maxf(x, 0.0)

	func pose_at(tt: float) -> void:
		var tb := tt
		var lv := since_leave(tt)
		if lv >= 0.0:
			tb = leave_at
		dist = minf(speed * _crawl_time(tb), float(bt["len"]))
		pos = along(bt, dist)
		dirv = along_dir(bt, dist)
		face = 1.0 if dirv.x >= 0.0 else -1.0
		crawl_ph = dist / (6.0 * s)
		trail_from = maxf(0.0, dist - speed * 4.0)
		ext = 1.0
		quer_o = 0.0
		if tb < in_s:
			var u := clampf(tb / in_s, 0.0, 1.0)
			quer_o = (1.0 - smoothstep(0.0, 1.0, u)) * 16.0 * s
			alpha = smoothstep(0.0, 0.7, u)
			ext = 0.3 + 0.7 * smoothstep(0.3, 1.0, u)
		var tp := since_tap(tt)
		if tp >= 0.0 and tp < 2.8:
			if tp < 0.4:
				ext = 1.0 - smoothstep(0.0, 0.4, tp)
			elif tp < 2.4:
				ext = 0.0
			else:
				ext = smoothstep(2.4, 2.8, tp)
		if tb >= dur - out_s and lv < 0.0:
			var u := clampf((tb - (dur - out_s)) / out_s, 0.0, 1.0)
			ext = minf(ext, 1.0 - smoothstep(0.0, 0.45, u))
			alpha *= 1.0 - smoothstep(0.45, 1.0, u)
		if lv >= 0.0:
			var u := clampf(lv / maxf(leave_s, 0.01), 0.0, 1.0)
			ext = minf(ext, 1.0 - smoothstep(0.0, 0.5, u))
			alpha *= 1.0 - smoothstep(0.45, 1.0, u)
		# nach außen versetzt (unter dem Bandrand hervor)
		pos += dirv.orthogonal() * (-quer_o if _outward_sign() < 0.0 else quer_o)

	func _outward_sign() -> float:
		var cpt: Vector2 = ctx.get("center", Vector2.ZERO)
		var n := dirv.orthogonal()
		return 1.0 if n.dot(pos - cpt) > 0.0 else -1.0

	func leave_time(_fast: bool) -> float:
		return 0.5

	func bounds() -> Rect2:
		if alpha <= 0.01:
			return Rect2()
		return box(pos + Vector2(0.0, -5.0) * s, Vector2(20.0, 14.0) * s)

	func _draw() -> void:
		if alpha <= 0.003:
			return
		# Schleimspur (verblasst nach 4 s)
		if dist - trail_from > 2.0:
			var pts := PackedVector2Array()
			var cols := PackedColorArray()
			var n := 16
			for i in n + 1:
				var d := lerpf(trail_from, dist, float(i) / float(n))
				pts.append(along(bt, d) + Vector2(0.0, 7.0 * s))
				cols.append(Color(1, 1, 1, 0.3 * float(i) / float(n)))
			draw_polyline_colors(pts, cols, 4.5 * s, true)
			for i in cols.size():
				cols[i] = Color(1, 1, 1, 0.55 * float(i) / float(n))
			draw_polyline_colors(pts, cols, 1.2 * s, true)
		shadow(pos + Vector2(0.0, 8.0) * s, 15.0 * s, 2.6 * s, 0.13)
		side_xf(pos, dirv, s, face, 0.5)
		# Körper (Fuß mit Wellen), Kopf mit Fühlern
		if ext > 0.03:
			var e := ext
			var body := PackedVector2Array()
			body.append(Vector2(-6.0 - 12.0 * e, 7.5))
			for i in 9:
				var x := lerpf(-4.0 - 12.0 * e, -2.0 + 15.0 * e, float(i) / 8.0)
				body.append(Vector2(x, 8.0 + 0.7 * sin(x * 0.7 - crawl_ph * 3.0)))
			var hx := -2.0 + 18.0 * e
			body.append(Vector2(hx - 1.0, 7.0))
			body.append(Vector2(hx + 1.6, 3.5))
			body.append(Vector2(hx + 0.6, -1.2))
			body.append(Vector2(hx - 2.6, -3.4))
			body.append(Vector2(hx - 6.0, -2.4))
			body.append(Vector2(hx - 9.0, 1.0))
			body.append(Vector2(-8.0, 3.6))
			body.append(Vector2(-5.0 - 12.0 * e, 5.6))
			draw_colored_polygon(body, BODY)
			draw_line(Vector2(-4.0 - 10.0 * e, 6.2), Vector2(hx - 2.0, 6.0), ca(BODY_D, 0.7), 1.2, true)
			outline_poly(body, INK, 1.3)
			# Fühler (wippen)
			var wob := sin(t * 3.1) * 1.2
			var stalk := e * e
			for st in [[Vector2(hx - 2.4, -2.6), Vector2(hx + 1.0 + wob, -11.0)], [Vector2(hx - 4.4, -2.2), Vector2(hx - 3.6 - wob * 0.6, -10.0)]]:
				var a: Vector2 = st[0]
				var b: Vector2 = a.lerp(st[1], stalk)
				draw_line(a, b, INK, 1.3, true)
				if stalk > 0.25:
					draw_circle(b, 1.7, INK, true, -1.0, true)
					draw_circle(b + Vector2(0.5, -0.5), 0.55, Color.WHITE, true, -1.0, true)
			draw_line(Vector2(hx, 2.4), Vector2(hx + 3.0 * e, 3.6), INK, 1.1, true)
			draw_circle(Vector2(hx - 1.8, 0.4), 0.7, ca(INK, 0.55), true, -1.0, true)
		# Haus mit Spirale
		var hc := Vector2(-3.0, -5.0)
		draw_circle(hc, 10.5, SHELL, true, -1.0, true)
		var spiral := PackedVector2Array()
		for i in 49:
			var th := 3.0 * TAU * float(i) / 48.0
			var r := 9.0 * float(i) / 48.0
			spiral.append(hc + Vector2(cos(th + 0.6), sin(th + 0.6)) * r)
		draw_polyline(spiral, SHELL_D, 1.8, true)
		draw_arc(hc, 10.5, 0.0, TAU, 32, INK, 1.4, true)
		draw_arc(hc + Vector2(-1.5, -1.5), 7.2, PI * 1.05, PI * 1.45, 8, Color(1, 1, 1, 0.55), 1.6, true)
		reset_xf()


# ================================================================================ 12 Hoppelhase (1.6.15)

# Nutzerwunsch 23.10.2026: „Ein Hoppelhase hüpft durch das Bild“. Kommt von der Seite auf den Plattformrand gehüpft, hoppelt vorn am
# Rand entlang zur anderen Seite (Hüpfer mit Ducken, Strecken und Landen), hält zweimal an (Ohren zucken, Näschen, einmal Männchen) und
# hüpft dort hinaus. Antippen: großer Schreck-Sprung, danach schnell davon. Seitenansicht wie der Spatz, Ursprung an den Füßen.
class Hoppelhase extends Day:
	const FUR := Color("#D3AE87")
	const FUR_D := Color("#B38B64")
	const BELLY := Color("#F8EDDC")
	const EAR_IN := Color("#F5A9BC")
	const NOSE := Color("#EE7499")
	const BLUSH := Color(1.0, 0.55, 0.68, 0.38)
	const QUER := 0.62
	const HOP_S := 0.42              # ein Hüpfer: Ducken, Flug, Landen
	const SCARE_S := 0.55            # Schreck-Sprung
	const FLEE_S := 0.3              # schnelle Hüpfer danach
	var bt: Dictionary = {}          # Weg auf dem Band von der Startseite über vorn zur anderen Seite (band_track)
	var acts: Array = []             # [t0, t1, art, p0, p1, extra]  art: hop | rest | pause (extra: "ohren" | "maennchen")
	var hop_len := 46.0
	var enter_v := Vector2.LEFT      # nach außen am Start (Einhüpfen)
	var exit_v := Vector2.RIGHT      # nach außen am Ende (Hinaushüpfen)
	var t_fade := 8.0                # ab hier blendet er beim Hinaushüpfen aus
	var tap_p := Vector2.ZERO
	var tap_dir := Vector2.RIGHT
	# Pose
	var pos := Vector2.ZERO
	var ground := Vector2.ZERO
	var face := 1.0
	var tilt := 0.0
	var sx := 1.0
	var sy := 1.0
	var hop_h := 0.0
	var ear := 0.0                   # Ohren: + nach hinten (Flug), − steil hoch (Schreck)
	var twitch := 0.0
	var sit := 0.0                   # Männchen 0 … 1
	var sniff := 0.0
	var scared := 0.0

	static func _eo(u: float) -> float:
		var v := clampf(u, 0.0, 1.0)
		return 1.0 - (1.0 - v) * (1.0 - v)

	static func _bmp(u: float) -> float:
		return sin(PI * clampf(u, 0.0, 1.0))

	func setup(c: Dictionary) -> void:
		s = 1.25 * k()
		own_leave = false
		var o: Variant = c.get("ort")
		var deg := float((o as Dictionary).get("deg", 140.0)) if o is Dictionary else 140.0
		var he := Vector2(20, 20) * s
		# Weg wählen: von einer Seite vorn herum zur anderen; die Seite des Ankers zuerst, sonst die freiere
		var best := INF
		var a0 := 168.0
		var a1 := 12.0
		for st in [170.0, 164.0, 158.0, 10.0, 16.0, 22.0]:
			for en in [10.0, 16.0, 22.0, 28.0]:
				var s0 := float(st)
				var e0 := float(en) if s0 > 90.0 else 180.0 - float(en)
				var cost := 0.0
				for m in 16:
					var p := band(lerpf(s0, e0, (float(m) + 0.5) / 16.0), QUER)
					cost += covered(box(p + Vector2(0, -18) * s, he))
				cost /= 16.0
				cost += (0.0 if (s0 > 90.0) == (deg > 90.0) else 0.04) + absf(absf(e0 - s0) - 160.0) * 0.0004 + rng.randf() * 0.01
				if cost < best:
					best = cost
					a0 = s0
					a1 = e0
		bt = band_track(a0, a1, QUER)
		var L := float(bt["len"])
		var C: Vector2 = c.get("center", table_size() * Vector2(0.5, 0.445))
		var p_start := along(bt, 0.0)
		var p_end := along(bt, L)
		enter_v = (p_start - C).normalized()
		exit_v = (p_end - C).normalized()
		# Hüpfer und Pausen in die Dauer der Tabelle einpassen
		var pause_t := [rng.randf_range(1.1, 1.5), rng.randf_range(1.0, 1.4)]
		var rest_t := 0.1
		var avail := dur - 3.0 * HOP_S - float(pause_t[0]) - float(pause_t[1])
		var n := maxi(6, int(avail / (HOP_S + rest_t)))
		hop_len = clampf(L / float(n), 34.0 * k(), 72.0 * k())
		n = maxi(3, int(ceil(L / hop_len)))
		hop_len = L / float(n)
		# Pausen nach etwa einem Drittel und zwei Dritteln, an einer gut sichtbaren Stelle
		var pause_at: Array = []
		for f in [0.33, 0.68]:
			var bi := clampi(int(round(float(n) * float(f))), 1, n - 1)
			for dj in [0, 1, -1, 2, -2]:
				var j := clampi(bi + int(dj), 1, n - 1)
				if covered(box(along(bt, hop_len * j) + Vector2(0, -18) * s, he)) < 0.2:
					bi = j
					break
			pause_at.append(bi)
		var tt := 0.0
		var p_in := p_start + enter_v * 52.0 * k()
		acts.append([tt, tt + HOP_S, "hop", p_in, p_start, ""])
		tt += HOP_S
		var d := 0.0
		for i in n:
			acts.append([tt, tt + rest_t, "rest", along(bt, d), along(bt, d), ""])
			tt += rest_t
			acts.append([tt, tt + HOP_S, "hop", along(bt, d), along(bt, d + hop_len), ""])
			tt += HOP_S
			d += hop_len
			var pz := pause_at.find(i + 1)
			if pz >= 0:
				acts.append([tt, tt + float(pause_t[pz]), "pause", along(bt, d), along(bt, d), "maennchen" if pz == 0 else "ohren"])
				tt += float(pause_t[pz])
		var p_out := p_end + exit_v * 54.0 * k()
		acts.append([tt, tt + rest_t, "rest", p_end, p_end, ""])
		tt += rest_t
		acts.append([tt, tt + HOP_S, "hop", p_end, p_out, ""])
		tt += HOP_S
		acts.append([tt, tt + HOP_S, "hop", p_out, p_out + exit_v * 54.0 * k(), ""])
		t_fade = tt
		tt += HOP_S
		dur = tt
		in_s = HOP_S
		out_s = HOP_S * 2.0 + rest_t

	func _act(tb: float) -> Array:
		for a in acts:
			if tb < float(a[1]):
				return a
		return acts[acts.size() - 1]

	# Hüpfer von p0 nach p1, u = 0 … 1: Ducken (bis 0,18), Flug, Landen (ab 0,82)
	func _hop(p0: Vector2, p1: Vector2, u: float, h: float) -> void:
		var dv := p1 - p0
		face = 1.0 if dv.x >= 0.0 else -1.0
		var slope := clampf(atan2(dv.y * face, absf(dv.x) + 0.001), -0.45, 0.45)
		if u < 0.18:
			var w := u / 0.18
			ground = p0
			hop_h = 0.0
			sy = 1.0 - 0.2 * sin(PI * 0.5 * w)
			sx = 1.0 + 0.12 * sin(PI * 0.5 * w)
			tilt = slope + 0.06 * w
			ear = 0.15 * w
		elif u < 0.82:
			var v := (u - 0.18) / 0.64
			var e := smoothstep(0.0, 1.0, v)
			ground = p0.lerp(p1, e)
			hop_h = h * sin(PI * v)
			sy = 1.0 + 0.16 * pow(1.0 - v, 2.0) + 0.06 * pow(v, 3.0)
			sx = 1.0 / sqrt(sy)
			tilt = slope - 0.3 * cos(PI * v)
			ear = 0.15 + 0.45 * sin(PI * v)
		else:
			var w := (u - 0.82) / 0.18
			ground = p1
			hop_h = 0.0
			sy = 1.0 - 0.16 * sin(PI * w)
			sx = 1.0 + 0.1 * sin(PI * w)
			tilt = slope * (1.0 - 0.3 * w)
			ear = 0.3 * (1.0 - w)

	func _base(tb: float) -> void:
		sx = 1.0
		sy = 1.0
		hop_h = 0.0
		ear = 0.0
		twitch = 0.0
		sit = 0.0
		sniff = 0.0
		var a := _act(tb)
		var u := clampf((tb - float(a[0])) / maxf(float(a[1]) - float(a[0]), 1e-4), 0.0, 1.0)
		var p0: Vector2 = a[3]
		var p1: Vector2 = a[4]
		match str(a[2]):
			"hop":
				_hop(p0, p1, u, 0.42 * hop_len + 6.0 * k())
			_:
				ground = p0
				var nxt := acts.find(a) + 1
				var q: Vector2 = (acts[nxt][4] as Vector2) if nxt < acts.size() else p0 + exit_v
				var dv := q - p0
				face = 1.0 if dv.x >= 0.0 else -1.0
				tilt = clampf(atan2(dv.y * face, absf(dv.x) + 0.001), -0.45, 0.45)
				if str(a[2]) == "pause":
					var lt := tb - float(a[0])
					var len_t := float(a[1]) - float(a[0])
					sniff = 1.0
					if str(a[5]) == "maennchen":
						sit = smoothstep(0.0, 0.25, lt) * (1.0 - smoothstep(len_t - 0.25, len_t, lt))
						twitch = 0.35 * sin(lt * 22.0) * _bmp((lt - 0.4) / 0.35)
					else:
						twitch = 0.4 * sin(lt * 24.0) * (_bmp((lt - 0.15) / 0.3) + _bmp((lt - 0.7) / 0.3))
		pos = ground - Vector2(0.0, hop_h)

	func pose_at(tt: float) -> void:
		scared = 0.0
		var tp := since_tap(tt)
		var tb := tt if tp < 0.0 else tap_at
		_base(tb)
		alpha = minf(clampf(tt / (HOP_S * 0.7), 0.0, 1.0), 1.0 - ramp(tt, t_fade, t_fade + HOP_S))
		if tp >= 0.0:
			# Schreck: steil hoch, Ohren aufgestellt; danach schnelle, weite Hüpfer davon
			face = 1.0 if tap_dir.x >= 0.0 else -1.0
			if tp < SCARE_S:
				var u := tp / SCARE_S
				ground = tap_p
				hop_h = 66.0 * k() * sin(PI * u)
				sy = 1.18 - 0.18 * u if u < 0.5 else 1.0 + 0.1 * sin(PI * (u - 0.5) * 2.0)
				sx = 1.0 / sqrt(sy)
				tilt = -0.35 * sin(PI * u) + 0.12 * sin(u * 40.0) * (1.0 - u)
				ear = -0.55 * _bmp(u * 1.4)
				scared = _bmp(u * 1.2)
			else:
				var k2 := tp - SCARE_S
				var i := int(k2 / FLEE_S)
				var u := fmod(k2, FLEE_S) / FLEE_S
				var step := tap_dir * hop_len * 1.5
				var p0 := tap_p + step * float(i)
				_hop(p0, p0 + step, u, 0.5 * hop_len + 8.0 * k())
				face = 1.0 if tap_dir.x >= 0.0 else -1.0
				ear = 0.6
			pos = ground - Vector2(0.0, hop_h)
			alpha = 1.0 - ramp(tp, SCARE_S + FLEE_S * 1.2, SCARE_S + FLEE_S * 3.0)
			if tt < HOP_S:
				alpha *= clampf(tt / (HOP_S * 0.7), 0.0, 1.0)

	func on_tap(_p: Vector2) -> void:
		_base(tap_at)
		tap_p = ground
		var a := _act(tap_at)
		var p0: Vector2 = a[3]
		var p1: Vector2 = a[4]
		var dv := p1 - p0
		if dv.length() < 1.0:
			dv = Vector2(face, 0.0)
		tap_dir = dv.normalized()
		dur = tap_at + SCARE_S + FLEE_S * 3.0 + 0.05
		pose_at(t)

	func bounds() -> Rect2:
		if alpha <= 0.01:
			return Rect2()
		return box(pos + Vector2(0.0, -19.0) * s, Vector2(21.0, 21.0) * s)

	func _draw() -> void:
		if alpha <= 0.003:
			return
		shadow(ground + Vector2(0.0, 1.5) * s, 15.0 * s * (1.0 - clampf(hop_h / (90.0 * s), 0.0, 0.45)), 3.6 * s,
			0.15 * (1.0 - clampf(hop_h / (60.0 * s), 0.0, 0.6)))
		draw_set_transform(pos, tilt - 0.5 * sit, Vector2(s * face * sx, s * sy))
		# Schwänzchen (Wattebausch)
		draw_circle(Vector2(-15.0, -12.0), 5.4, BELLY)
		draw_circle(Vector2(-17.0, -14.0), 2.6, Color.WHITE)
		draw_arc(Vector2(-15.0, -12.0), 5.4, 0.0, TAU, 18, INK, 1.2, true)
		# fernes Ohr
		var ear_a := -1.83 + ear - 0.25 * sit
		wing(Vector2(6.5, -28.0), 16.0, 7.0, ear_a - 0.12, FUR_D, INK, 1.2)
		# Hinterlauf und Fuß
		ellipse_outlined(Vector2(-7.0, -8.0), 8.6, 7.4, FUR_D, INK, 1.3, -0.2, 20)
		ellipse_outlined(Vector2(-4.0 + 2.0 * sit, -1.8), 9.2, 3.0, FUR, INK, 1.2, 0.0, 18)
		# Körper mit Bauch
		ellipse_outlined(Vector2(-1.0, -12.5), 13.5, 10.5, FUR, INK, 1.4, -0.2, 28)
		poly_ellipse(Vector2(5.0, -9.0), 6.4, 5.2, BELLY, -0.3, 18)
		ellipse_outlined(Vector2(-6.5, -10.0), 7.6, 6.4, FUR_D, Color(0, 0, 0, 0), 1.0, -0.2, 18)
		draw_arc(Vector2(-6.5, -10.0), 7.6, PI * 1.1, PI * 1.85, 10, ca(INK, 0.55), 1.1, true)
		# Vorderpfote (beim Männchen angezogen)
		var paw := Vector2(8.0, -1.8).lerp(Vector2(10.5, -9.0), sit)
		ellipse_outlined(paw, 3.3, 2.3, FUR, INK, 1.1, 0.0, 14)
		# Kopf (groß und rund), Schnäuzchen, Bäckchen
		ellipse_outlined(Vector2(10.5, -21.0), 9.8, 9.2, FUR, INK, 1.4, 0.0, 28)
		poly_ellipse(Vector2(16.4, -17.8), 4.8, 3.6, BELLY, 0.0, 16)
		draw_circle(Vector2(13.6, -16.8), 2.7, BLUSH)
		# Auge (beim Schreck groß und rund)
		var er := 2.4 + 0.8 * scared
		poly_ellipse(Vector2(13.4, -22.8), er * 0.92, er * 1.18, INK, 0.0, 16)
		draw_circle(Vector2(14.2, -23.9), 0.95 + 0.2 * scared, Color.WHITE)
		draw_circle(Vector2(12.9, -21.7), 0.45, ca(Color.WHITE, 0.8))
		# Näschen (schnuppert) und Schnurrhaare
		var nz := Vector2(20.6, -19.2) + Vector2(0.0, 0.5 * sin(t * 30.0)) * sniff
		draw_circle(nz, 1.6, NOSE)
		for wy in [-0.8, 1.4]:
			draw_line(Vector2(18.0, -18.0 + float(wy) * 0.5), Vector2(24.5, -19.0 + float(wy)), ca(INK, 0.45), 0.7, true)
		# nahes Ohr mit rosa Innenseite (zuckt)
		var ea := -1.62 + ear + twitch - 0.2 * sit
		wing(Vector2(9.0, -28.6), 17.0, 7.6, ea, FUR, INK, 1.3)
		wing(Vector2(9.3, -30.2), 12.5, 3.6, ea, EAR_IN)
		reset_xf()


# ================================================================================ 13 Strand mit Palme (1.6.15)

# Nutzerwunsch 23.10.2026: „In der unteren rechten Ecke kommt mit einer Welle für ein paar Sekunden ein Strand ins Bild und eine Palme
# wächst“. Eine Welle rollt aus der Ecke herein und lässt beim Zurückweichen einen kleinen Sandstrand zurück (Meer bleibt in der Ecke,
# kleine Wellen lecken am Ufer); eine Palme wächst Stück für Stück, die Wedel entfalten sich, sie wiegt sich; am Ende spült eine große
# Welle alles weg. Ebene hinten: Hand und Mau-Knopf (rechts 46, unten 40, 150 × 150) liegen darüber. Die Palme steht zwischen der Hand
# (höchstens bis W − 270) und dem Mau-Knopf (ab W − 196), ihre Krone über dem Knopf. Antippen der Palme: sie schüttelt sich kräftig,
# eine Kokosnuss fällt.
class Strand extends Day:
	const SEA := Color("#2FBFD2")
	const SEA_HI := Color("#86E6EF")
	const FOAM := Color("#FFFFFF")
	const SAND := Color("#F3CC86")
	const SAND_D := Color("#D9A85E")
	const WET := Color("#D2A061")
	const TRUNK := Color("#B47D46")
	const TRUNK_D := Color("#7E5329")
	const LEAF := Color("#3DBB6A")
	const LEAF_HI := Color("#5FD486")
	const LEAF_D := Color("#227F44")
	const NUT := Color("#7A4A22")
	const STAR := Color("#FF8A5B")
	const SHELL := Color("#FFC9D6")
	const SEGS := 8
	const T_IN := 1.0                 # Welle rollt herein
	const T_BACK := 1.8               # Wasser ist zurück an der Meereslinie
	const SEA_R := 0.5                # Meereslinie (Anteil am Strand)
	# Wedel: [Winkel (Grad, 0 = rechts, −90 = oben), Länge, Durchhang]
	const FRONDS := [[-178.0, 86.0, 42.0], [-152.0, 82.0, 24.0], [-124.0, 66.0, 10.0], [-95.0, 56.0, 2.0], [-64.0, 64.0, 8.0],
		[-36.0, 80.0, 22.0], [-10.0, 86.0, 38.0], [16.0, 72.0, 44.0]]
	var P := Vector2.ZERO             # Ecke unten rechts
	var R := Vector2(410, 245)        # Strand (Ellipse um die Ecke)
	var kk := 1.0
	var base := Vector2.ZERO          # Fuß der Palme
	var top := Vector2.ZERO           # Krone
	var ctrl := Vector2.ZERO
	var TH := 250.0
	var star_p := Vector2.ZERO
	var shell_p := Vector2.ZERO
	var dots: Array = []              # Sandkörnchen [Winkel, Radius-Anteil]
	var ph := 0.0
	var t_wash := 6.0
	# Pose
	var sea := 0.0                    # Wasserlinie (Anteil von R)
	var sand := 0.0                   # Sand (Anteil von R; 0 = keiner)
	var wet := 0.0                    # nasser Rand (Deckkraft)
	var grow := 0.0                   # Stamm 0 … 1
	var leaves := 0.0                 # Wedel 0 … 1
	var sway := 0.0                   # Neigung der Krone (rad)
	var palm_a := 0.0
	var palm_tip := 0.0               # Kippen beim Wegspülen
	var water_a := 1.0
	var nut_t := -1.0                 # Zeit seit dem Kokosnuss-Fall (−1 = keiner)
	var tc := 0.0

	func setup(c: Dictionary) -> void:
		kk = clampf(k(), 0.9, 1.15)
		var sz := table_size()
		var o: Variant = c.get("ort")
		P = (o as Dictionary).get("pos", sz) if o is Dictionary else sz
		R = Vector2(410.0, 245.0) * kk
		# Fuß zwischen Hand und Mau-Knopf (feste Pixel wie TableView.hand_rect / Mau-Knopf)
		var mau: Rect2 = (o as Dictionary).get("mau", Rect2()) if o is Dictionary else Rect2()
		var bx := P.x - 233.0
		if mau.has_area():
			bx = minf(bx, mau.position.x - 34.0)
		base = Vector2(bx, P.y - 52.0)
		TH = 250.0 * minf(kk, 1.05)
		top = base + Vector2(16.0, -TH)
		ctrl = base + Vector2(-38.0, -0.55 * TH)
		# Seestern links vom Palmenfuß (zwischen Hand und Mau-Knopf), Muschel über dem Mau-Knopf
		star_p = Vector2(base.x - 52.0, P.y - 26.0)
		shell_p = Vector2(P.x - 128.0, P.y - 212.0 * kk)
		ph = rng.randf() * TAU
		for i in 16:
			dots.append([rng.randf_range(PI * 1.03, PI * 1.47), rng.randf_range(SEA_R + 0.08, 0.95)])
		in_s = T_IN
		out_s = 1.7
		t_wash = dur - out_s

	static func _eo(u: float) -> float:
		var v := clampf(u, 0.0, 1.0)
		return 1.0 - (1.0 - v) * (1.0 - v)

	static func _eio(u: float) -> float:
		return smoothstep(0.0, 1.0, u)

	func pose_at(tt: float) -> void:
		tc = tt
		alpha = 1.0
		water_a = 1.0
		# Wasserlinie: Welle herein, zurück zur Meereslinie, kleine Wellen, große Welle, ganz zurück
		if tt < T_IN:
			sea = 1.08 * _eo(tt / T_IN)
		elif tt < T_BACK:
			sea = lerpf(1.08, SEA_R, _eio((tt - T_IN) / (T_BACK - T_IN)))
		elif tt < t_wash:
			sea = SEA_R + 0.035 * sin(TAU * (tt - T_BACK) / 1.7) * ramp(tt, T_BACK, T_BACK + 0.4)
		elif tt < t_wash + 0.7:
			var s0 := SEA_R + 0.035 * sin(TAU * (t_wash - T_BACK) / 1.7)
			sea = lerpf(s0, 1.18, _eo((tt - t_wash) / 0.7))
		else:
			sea = lerpf(1.18, 0.0, _eio((tt - t_wash - 0.7) / maxf(dur - t_wash - 0.75, 0.1)))
			water_a = 1.0 - ramp(tt, dur - 0.45, dur)
		# Sand: wächst unter der ersten Welle, verschwindet unter der großen
		sand = minf(1.0, sea * 0.96) if tt < T_IN else 1.0
		if tt > t_wash + 0.55:
			sand = 0.0
		wet = (1.0 - ramp(tt, T_BACK, T_BACK + 1.6)) if tt >= T_IN else 0.0
		# Palme wächst (Stamm Stück für Stück, dann die Wedel), wiegt sich
		grow = ramp(tt, 1.7, 2.7)
		leaves = ramp(tt, 2.5, 3.3)
		palm_a = 1.0 if grow > 0.0 else 0.0
		sway = 0.05 * sin(TAU * tt / 2.6 + ph) * leaves
		var st := since_tap(tt)
		nut_t = -1.0
		if st >= 0.0:
			sway += 0.24 * exp(-1.7 * st) * sin(TAU * 1.5 * st)
			nut_t = st
		# Wegspülen: die Welle erreicht den Fuß, die Palme kippt und verschwindet
		var hit_t := t_wash + 0.32
		if tt > hit_t:
			var u := clampf((tt - hit_t) / 0.45, 0.0, 1.0)
			palm_tip = _eio(u)
			palm_a = 1.0 - u
		else:
			palm_tip = 0.0

	# Punkt am Rand der Strand-Ellipse (Winkel th ∈ [π, 1,5π], Anteil r) mit leichtem Wellenrand
	func _rim(th: float, r: float, wob := 0.025, tt := 0.0) -> Vector2:
		var w := 1.0 + wob * sin(5.0 * th + ph + tt * 1.3)
		return P + Vector2(cos(th) * R.x, sin(th) * R.y) * r * w

	func _shape(r: float, wob := 0.025, tt := 0.0) -> PackedVector2Array:
		var pts := PackedVector2Array()
		pts.append(P + Vector2(-R.x * r * 1.2 - 20.0, 4.0))
		for i in 25:
			pts.append(_rim(PI + PI * 0.5 * float(i) / 24.0, r, wob, tt))
		pts.append(P + Vector2(4.0, -R.y * r * 1.2 - 20.0))
		pts.append(P + Vector2(4.0, 4.0))
		return pts

	func _edge(r: float, wob := 0.025, tt := 0.0) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 25:
			pts.append(_rim(PI + PI * 0.5 * float(i) / 24.0, r, wob, tt))
		return pts

	# Stamm: Punkt bei Anteil f (0 Fuß … 1 Krone), mit Neigung der Krone und Kippen beim Wegspülen
	func _trunk(f: float) -> Vector2:
		var tp := top + Vector2(TH * 0.06 * sin(sway), 0.0)
		var p := bez2(base, ctrl, tp, f)
		return base + (p - base).rotated(-0.75 * palm_tip)

	func _crown() -> Vector2:
		return _trunk(1.0)

	# Wedel i: Punkte der Mittelrippe (entfaltet sich mit leaves, neigt sich mit sway)
	func _frond(i: int) -> PackedVector2Array:
		var fd: Array = FRONDS[i]
		var e := clampf((leaves - float(i) * 0.04) / 0.72, 0.0, 1.0)
		e = 1.0 - (1.0 - e) * (1.0 - e)
		var ang := deg_to_rad(lerpf(-90.0, float(fd[0]), e)) + sway * 1.4 - 0.75 * palm_tip
		var ln := float(fd[1]) * lerpf(0.25, 1.0, e) * minf(kk, 1.05)
		var droop := float(fd[2]) * e * minf(kk, 1.05)
		var c0 := _crown()
		var dv := Vector2.from_angle(ang)
		var tip := c0 + dv * ln + Vector2(0.0, droop)
		var cp := c0 + dv * ln * 0.55 + Vector2(0.0, -ln * 0.22 * e)
		var pts := PackedVector2Array()
		for j in 9:
			pts.append(bez2(c0, cp, tip, float(j) / 8.0))
		return pts

	func _palm_hull() -> Rect2:
		var u := Rect2(base - Vector2(8, 8), Vector2(16, 12))
		u = u.expand(_crown())
		if leaves > 0.0:
			for i in FRONDS.size():
				var f := _frond(i)
				u = u.expand(f[f.size() - 1])
		return u.grow(6.0)

	func bounds() -> Rect2:
		if alpha <= 0.0:
			return Rect2()
		if grow > 0.25 and palm_a > 0.1:
			return _palm_hull()
		var r := maxf(sea, sand)
		if r <= 0.02 or water_a <= 0.02:
			return Rect2()
		var b := Rect2(P - R * r, R * r)
		return b.intersection(Rect2(Vector2.ZERO, table_size()))

	# Getroffen wird die Palme (sonst nichts)
	func hit(p: Vector2) -> bool:
		if modulate.a < 0.05 or grow <= 0.25 or palm_a <= 0.1:
			return false
		return _palm_hull().grow(14.0).has_point(p)

	func _draw() -> void:
		if alpha <= 0.0:
			return
		# Sand mit Papierkante, nasser Rand, Körnchen, Seestern und Muschel
		if sand > 0.02:
			var sh := _shape(sand)
			var shadow_pts := PackedVector2Array()
			for q in sh:
				shadow_pts.append(q + Vector2(-3.0, -3.0))
			draw_colored_polygon(shadow_pts, ca(INK, 0.07))
			draw_colored_polygon(sh, SAND)
			if wet > 0.0:
				draw_colored_polygon(_shape(minf(sand, 1.0)), ca(WET, 0.5 * wet))
			draw_polyline(_edge(sand), ca(INK, 0.5), 1.6, true)
			for d in dots:
				var q := _rim(float(d[0]), float(d[1]) * sand, 0.0)
				draw_circle(q, 1.4, ca(SAND_D, 0.75))
			if sand >= 0.99:
				_starfish(star_p, 9.5 * kk)
				_shell(shell_p, 7.0 * kk)
		# Meer: helle Uferzone, tieferes Wasser, Schaumkante mit Bläschen
		if sea > 0.02 and water_a > 0.0:
			var wob := 0.03
			draw_colored_polygon(_shape(sea, wob, tc), ca(SEA_HI, 0.95 * water_a))
			if sea > 0.12:
				draw_colored_polygon(_shape(sea - 0.07, wob, tc + 0.6), ca(SEA, 0.95 * water_a))
				draw_polyline(_edge(maxf(sea - 0.18, 0.05), 0.04, tc + 1.7), ca(FOAM, 0.35 * water_a), 2.0, true)
			draw_polyline(_edge(sea, wob, tc), ca(FOAM, 0.95 * water_a), 4.0 * kk, true)
			for i in 9:
				var th := PI + PI * 0.5 * (float(i) + 0.5) / 9.0
				var q := _rim(th, sea, wob, tc) + Vector2(cos(th), sin(th)) * 3.0
				draw_circle(q, (2.2 + 1.2 * sin(tc * 3.0 + float(i))) * kk, ca(FOAM, 0.9 * water_a))
		# Palme
		if palm_a > 0.0 and grow > 0.0:
			_palm()
			_nut_drop()

	func _palm() -> void:
		var a := palm_a
		var n_vis := grow * float(SEGS)
		for j in SEGS:
			if float(j) >= n_vis:
				break
			var pop := clampf(n_vis - float(j), 0.0, 1.0)
			var f0 := float(j) / float(SEGS)
			var f1 := (float(j) + pop) / float(SEGS)
			var p0 := _trunk(f0)
			var p1 := _trunk(f1)
			var w0 := lerpf(9.0, 6.0, f0) * kk
			var w1 := lerpf(9.0, 6.0, f1) * kk * (0.75 + 0.25 * pop)
			var nv := (p1 - p0).normalized().orthogonal()
			var seg := PackedVector2Array([p0 + nv * w0, p1 + nv * w1 * 1.12, p1 - nv * w1 * 1.12, p0 - nv * w0])
			draw_colored_polygon(seg, ca(TRUNK, a))
			draw_line(p1 + nv * w1 * 1.12, p1 - nv * w1 * 1.12, ca(TRUNK_D, a), 2.0, true)
			outline_poly(seg, ca(INK, 0.85 * a), 1.3)
		if leaves <= 0.0:
			return
		var c0 := _crown()
		# Kokosnüsse (eine fällt beim Antippen)
		var nuts := [Vector2(-6, 8), Vector2(5, 9), Vector2(-1, 14)]
		for i in nuts.size():
			if i == 1 and nut_t >= 0.0:
				continue
			var q: Vector2 = c0 + (nuts[i] as Vector2).rotated(-0.75 * palm_tip) * kk
			var na := a * ramp(leaves, 0.5, 0.9)
			draw_circle(q, 5.6 * kk, ca(NUT, na))
			draw_arc(q, 5.6 * kk, 0.0, TAU, 14, ca(INK, 0.8 * na), 1.1, true)
			draw_circle(q + Vector2(-1.8, -1.8) * kk, 1.4 * kk, ca(Color.WHITE, 0.35 * na))
		# Wedel: Blatt mit gezackter Unterkante (als Vierecke je Abschnitt, damit nichts an der Triangulierung scheitert), Mittelrippe
		for i in FRONDS.size():
			var mid := _frond(i)
			var up := PackedVector2Array()
			var dn := PackedVector2Array()
			for j in mid.size():
				var f := float(j) / float(mid.size() - 1)
				var tg := (mid[mini(j + 1, mid.size() - 1)] - mid[maxi(j - 1, 0)]).normalized()
				var nv := tg.orthogonal()
				var w := 13.0 * kk * sin(PI * minf(f * 1.12, 1.0)) * (0.55 + 0.45 * (1.0 - f))
				up.append(mid[j] + nv * w * 0.6)
				var zig := 1.0 if j % 2 == 0 else 0.5
				dn.append(mid[j] - nv * w * zig)
			var col := LEAF_HI if i % 2 == 0 else LEAF
			for j in mid.size() - 1:
				draw_colored_polygon(PackedVector2Array([mid[j], up[j], up[j + 1], mid[j + 1]]), ca(col, a))
				draw_colored_polygon(PackedVector2Array([mid[j], mid[j + 1], dn[j + 1], dn[j]]), ca(col.darkened(0.08), a))
			var leaf := PackedVector2Array()
			leaf.append_array(up)
			for j in range(dn.size() - 1, -1, -1):
				leaf.append(dn[j])
			draw_polyline(mid, ca(LEAF_D, a), 1.6, true)
			outline_poly(leaf, ca(INK, 0.85 * a), 1.2)

	func _nut_drop() -> void:
		if nut_t < 0.0:
			return
		var c0 := _crown()
		var start := c0 + Vector2(5, 9) * kk
		var ground_y := base.y - 4.0
		var fall_h := maxf(ground_y - start.y, 1.0)
		var t_fall := sqrt(2.0 * fall_h / 900.0)
		var q := start
		var rot := 0.0
		if nut_t < t_fall:
			q.y = start.y + 0.5 * 900.0 * nut_t * nut_t
		else:
			var b := nut_t - t_fall
			var bh := fall_h * 0.12
			var tb := 0.3
			q.y = ground_y - (4.0 * bh * (b / tb) * (1.0 - b / tb) if b < tb else 0.0)
			var roll := clampf((b - 0.05) / 0.7, 0.0, 1.0)
			q.x += 34.0 * kk * (1.0 - (1.0 - roll) * (1.0 - roll))
			rot = 34.0 * (1.0 - (1.0 - roll) * (1.0 - roll)) / 5.6
		var a := palm_a
		draw_circle(q, 5.6 * kk, ca(NUT, a))
		draw_arc(q, 5.6 * kk, 0.0, TAU, 14, ca(INK, 0.8 * a), 1.1, true)
		draw_circle(q + Vector2(-1.8, -1.8).rotated(rot) * kk, 1.4 * kk, ca(Color.WHITE, 0.35 * a))

	func _starfish(c: Vector2, r: float) -> void:
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI * 0.5 + TAU * float(i) / 10.0 + 0.2
			pts.append(c + Vector2.from_angle(a) * (r if i % 2 == 0 else r * 0.45))
		draw_colored_polygon(pts, STAR)
		outline_poly(pts, ca(INK, 0.8), 1.1)
		for i in 5:
			var a := -PI * 0.5 + TAU * float(i) / 5.0 + 0.2
			draw_circle(c + Vector2.from_angle(a) * r * 0.5, 0.9, Color("#FFE0C8"))

	func _shell(c: Vector2, r: float) -> void:
		var pts := PackedVector2Array()
		pts.append(c + Vector2(0, r * 0.55))
		for i in 9:
			var a := PI + PI * float(i) / 8.0
			pts.append(c + Vector2(cos(a) * r, sin(a) * r * 0.8))
		draw_colored_polygon(pts, SHELL)
		outline_poly(pts, ca(INK, 0.75), 1.0)
		for i in 4:
			var a := PI + PI * (float(i) + 0.5) / 4.0
			draw_line(c + Vector2(0, r * 0.45), c + Vector2(cos(a) * r * 0.85, sin(a) * r * 0.7), ca(INK, 0.35), 0.8, true)
