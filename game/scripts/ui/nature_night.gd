extends RefCounted
# Mau-Mau Flip (Beta 1.6.12): Nachttiere der „Natur-Überraschungen“ (docs/module/natur.md Abschnitt 3.3, Aufgabe T4).
# Je Ereignis eine innere Klasse auf der Grundklasse nature_creature.gd; NatureFx findet sie über static func make(id).
# Alles mit Godot-Zeichenbefehlen (Polygone, Linien, Glühtextur aus TableEffects), Stil „Papier & Neon“ bei Nacht: dunkle Körper
# mit Lavendel-Kontur, Leuchtendes additiv. Kein Ton, keine Vibration, kein Netz; einziger Text ist das gezeichnete „z“ am Mond.
# Bahn und Aussehen hängen nur vom Samen (rng in setup) und von t ab (pose_at), damit seek(t) für Tests und Kontrollbilder gilt.
#   gluehwuermchen  6–9 Leuchtpunkte in einer freien Stelle rund um die Plattform; Tipp: stieben auseinander, Ende
#   eule            gleitet auf die Plattform-Schulter, blinzelt, dreht den Kopf zum Spieler am Zug; Tipp: Kopf fast ganz herum
#   fledermaus      ruckartiges Zickzack mit einer Kehre über den oberen Himmel
#   mond_muetze     Zipfelmütze fällt auf die Mondsichel, der Mond schläft („z“); Tipp: wacht kurz auf; ruhig: nur Blende
#   polarlicht      drei wogende Vorhänge (additiv, höchstens 0,35); ruhig: ohne Wogen
#   sternbild       Katze aus 11 Sternen (Form aus der Tabelle), Linien wachsen; Tipp: Funkeln, Schwanz wackelt; ruhig: Blende
#   ufo             schwebt über den Ziehstapel, Lichtkegel ≤ 0,22, Funken; scheu; Tipp: saust davon
#   satellit        heller Punkt mit Solarflächen und rotem Blinklicht, blitzt einmal auf
#   motte           taumelt heran und umkreist den Ablage-Ring (verweilt, wo sie zu sehen ist); scheu
#   igel            tippelt am Plattformrand, schnüffelt, kehrt um; Tipp: rollt sich ein
#   komet           blass und langsam, Staub- und Ionenschweif
#   lampion         steigt hinter dem Tisch auf, flackert; Tipp: glüht auf und schaukelt

const BASE_PATH := "res://scripts/ui/nature_creature.gd"


# Tier zu einer id (null = kein Nachttier dieser Datei)
static func make(id: String) -> Node2D:
	match id:
		"gluehwuermchen":
			return Fireflies.new()
		"eule":
			return Owl.new()
		"fledermaus":
			return Bat.new()
		"mond_muetze":
			return MoonCap.new()
		"polarlicht":
			return Aurora.new()
		"sternbild":
			return Constellation.new()
		"ufo":
			return Ufo.new()
		"satellit":
			return Satellite.new()
		"motte":
			return Moth.new()
		"igel":
			return Hedgehog.new()
		"komet":
			return Comet.new()
		"lampion":
			return Lantern.new()
	return null


static func ids() -> Array[String]:
	return ["gluehwuermchen", "eule", "fledermaus", "mond_muetze", "polarlicht", "sternbild", "ufo", "satellit", "motte", "igel",
		"komet", "lampion"]


# ===================================================================================================== gemeinsame Hilfen

class NightBase extends "res://scripts/ui/nature_creature.gd":
	# Anteil von r unter Schutzflächen (0 … 1; ctx.free summiert alle Flächen)
	func cover_frac(r: Rect2) -> float:
		var a := r.get_area()
		if a <= 0.0:
			return 0.0
		var cb: Variant = ctx.get("free")
		if cb is Callable and (cb as Callable).is_valid():
			return clampf(float((cb as Callable).call(r)) / a, 0.0, 1.0)
		return 0.0

	# Anteil von r außerhalb des Bilds
	func outside_frac(r: Rect2) -> float:
		var a := r.get_area()
		if a <= 0.0:
			return 1.0
		var scr := Rect2(Vector2.ZERO, table_size())
		if not r.intersects(scr):
			return 1.0
		return 1.0 - r.intersection(scr).get_area() / a

	func spot_cost(c: Vector2, he: Vector2) -> float:
		var r := box(c, he)
		return cover_frac(r) + outside_frac(r)

	# Zählt wie die Sichtprüfung (nature_check): im Bild und höchstens zur Hälfte unter Schutzflächen
	func seen(r: Rect2) -> bool:
		return r.has_area() and r.intersects(Rect2(Vector2.ZERO, table_size())) and cover_frac(r) <= 0.45

	# Berührt r eine Schutzfläche (außer den genannten)?
	func touches(r: Rect2, skip: Array = []) -> bool:
		var obs: Variant = ctx.get("obstacles")
		if not (obs is Dictionary):
			return false
		for key in obs:
			if skip.has(key):
				continue
			for q in obs[key]:
				if r.intersects(q as Rect2):
					return true
		return false

	func anchor(key: String) -> Variant:
		var an: Variant = ctx.get("anchors")
		return (an as Dictionary).get(key) if an is Dictionary else null

	func center() -> Vector2:
		return ctx.get("center", table_size() * Vector2(0.5, 0.445))

	static func bez2(a: Vector2, b: Vector2, c: Vector2, u: float) -> Vector2:
		return a.lerp(b, u).lerp(b.lerp(c, u), u)

	static func bez3(a: Vector2, b: Vector2, c: Vector2, d: Vector2, u: float) -> Vector2:
		return bez2(a.lerp(b, u), b.lerp(c, u), c.lerp(d, u), u)

	static func e_out(u: float) -> float:
		var v := clampf(u, 0.0, 1.0)
		return 1.0 - (1.0 - v) * (1.0 - v)

	static func e_in(u: float) -> float:
		var v := clampf(u, 0.0, 1.0)
		return v * v

	static func e_io(u: float) -> float:
		return smoothstep(0.0, 1.0, u)

	# schießt über das Ziel hinaus und kehrt zurück (0 → 1)
	static func back_out(u: float) -> float:
		var v := clampf(u, 0.0, 1.0) - 1.0
		return 1.0 + 2.70158 * v * v * v + 1.70158 * v * v

	static func bump(u: float) -> float:
		return sin(PI * clampf(u, 0.0, 1.0))

	# weiches Rauschen −1 … 1 aus drei Sinus
	static func wobble(x: float, sd: float) -> float:
		return 0.5 * sin(x + sd) + 0.3 * sin(x * 2.31 + sd * 1.7) + 0.2 * sin(x * 4.07 + sd * 2.9)

	# Dreiecksnetz aus gleich langen Zeilen (rows: Array[PackedVector2Array], cols: Array[PackedColorArray]) mit Eckfarben
	func mesh(ci: CanvasItem, rows: Array, cols: Array) -> void:
		var nr := rows.size()
		if nr < 2:
			return
		var nc := (rows[0] as PackedVector2Array).size()
		if nc < 2:
			return
		var pts := PackedVector2Array()
		var cs := PackedColorArray()
		for r in nr:
			pts.append_array(rows[r])
			cs.append_array(cols[r])
		var idx := PackedInt32Array()
		for r in nr - 1:
			for j in nc - 1:
				var a := r * nc + j
				idx.append_array([a, a + 1, a + nc + 1, a, a + nc + 1, a + nc])
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cs)

	# geschlossene Ellipsenlinie
	func ellipse_line(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color, w := 1.5, rot := 0.0, n := 28) -> void:
		var pts := ellipse_points(c, rx, ry, rot, n)
		pts.append(pts[0])
		ci.draw_polyline(pts, col, w, true)

	# Kreissegment einer Ellipse von oben bis zum Anteil f (Lid, Kappe); f 0 = nichts, 1 = ganz
	static func top_segment(c: Vector2, rx: float, ry: float, f: float, n := 14) -> PackedVector2Array:
		var pts := PackedVector2Array()
		if f <= 0.02:
			return pts
		var m := clampf(-1.0 + 2.0 * f, -1.0, 1.0)
		var a0 := PI - asin(m)
		var a1 := TAU + asin(m)
		for i in n + 1:
			var a := lerpf(a0, a1, float(i) / float(n))
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		return pts


# ===================================================================================================== 12 Glühwürmchen

class Fireflies extends NightBase:
	const COL := Color("#D8FF6A")
	const CORE := Color("#FDFFDC")
	const BODY := Color("#2E2846")
	const WING := Color("#DCE6FF")
	var flies: Array = []
	var pts: Array = []
	var lum: Array = []
	var dirs: Array = []
	var spot := Vector2.ZERO
	var dur0 := 12.0
	var s := 1.0

	func setup(c: Dictionary) -> void:
		use_glow()
		s = k()
		in_s = 2.0
		out_s = 2.0
		own_leave = true
		dur0 = dur
		var o: Dictionary = c.get("ort", {}) if c.get("ort") is Dictionary else {}
		var ctr: Vector2 = o.get("center", center())
		var radii: Vector2 = o.get("radii", c.get("ring_radii", Vector2(330, 160)))
		var f0 := float(o.get("f0", 1.05))
		var f1 := float(o.get("f1", 1.45))
		var ymax := float(o.get("ymax", table_size().y - 250.0))
		var spread := Vector2(96, 54) * s
		var best := ctr + Vector2(0, -radii.y * 1.25)
		var best_c := INF
		for i in 36:
			var a := TAU * float(i) / 36.0
			for f in [f0 + 0.04, (f0 + f1) * 0.5, f1 - 0.04]:
				var p := ctr + Vector2(cos(a) * radii.x, sin(a) * radii.y) * float(f)
				if p.y + spread.y * 0.6 > ymax:
					continue
				var cost := spot_cost(p, spread + Vector2(30, 30) * s) + rng.randf() * 0.05
				if cost < best_c:
					best_c = cost
					best = p
		spot = best
		var n := rng.randi_range(6, 9)
		for i in n:
			var ang := rng.randf() * TAU
			var rr := sqrt(rng.randf()) * 0.85
			flies.append({
				"base": spot + Vector2(cos(ang) * spread.x, sin(ang) * spread.y) * rr,
				"ax": rng.randf_range(12.0, 22.0) * s, "fx": rng.randf_range(0.10, 0.19), "px": rng.randf() * TAU,
				"bx": rng.randf_range(4.0, 9.0) * s, "gx": rng.randf_range(0.27, 0.45), "qx": rng.randf() * TAU,
				"ay": rng.randf_range(8.0, 15.0) * s, "fy": rng.randf_range(0.12, 0.22), "py": rng.randf() * TAU,
				"by": rng.randf_range(3.0, 7.0) * s, "gy": rng.randf_range(0.30, 0.50), "qy": rng.randf() * TAU,
				"delay": 0.0 if i == 0 else rng.randf_range(0.0, 2.0), "per": rng.randf_range(1.4, 3.0), "ph": rng.randf(),
				"sz": rng.randf_range(0.85, 1.15), "wing": rng.randf() * TAU,
			})

	func _fly_pos(f: Dictionary, u: float) -> Vector2:
		return Vector2(f["base"]) + Vector2(
			float(f["ax"]) * sin(TAU * float(f["fx"]) * u + float(f["px"])) + float(f["bx"]) * sin(TAU * float(f["gx"]) * u + float(f["qx"])),
			float(f["ay"]) * sin(TAU * float(f["fy"]) * u + float(f["py"])) + float(f["by"]) * sin(TAU * float(f["gy"]) * u + float(f["qy"])))

	func _bright(f: Dictionary, tt: float) -> float:
		var a_in := ramp(tt - float(f["delay"]), 0.0, 0.9)
		var a_out := clampf((dur0 - tt) / out_s, 0.0, 1.0)
		var blink := 0.35 + 0.65 * pow(0.5 + 0.5 * sin(TAU * (tt / float(f["per"]) + float(f["ph"]))), 1.6)
		return a_in * a_out * blink

	func pose_at(tt: float) -> void:
		pts.clear()
		lum.clear()
		dirs.clear()
		var burst := -1.0
		var burst_at := 0.0
		var burst_from := spot
		var burst_len := 0.8
		var st := since_tap(tt)
		var sl := since_leave(tt)
		if st >= 0.0:
			burst = st
			burst_at = tap_at
			burst_from = tap_pos
		elif sl >= 0.0:
			burst = sl
			burst_at = leave_at
			burst_len = maxf(leave_s, 0.05)
		var any := false
		for f in flies:
			var u := tt if burst < 0.0 else burst_at
			var p := _fly_pos(f, u)
			var d := _fly_pos(f, u + 0.05) - p
			d = d.normalized() if d.length() > 0.01 else Vector2.RIGHT
			var b := _bright(f, tt if burst < 0.0 else burst_at)
			if burst >= 0.0:
				var away := p - burst_from
				var dir := away.normalized() if away.length() > 1.0 else Vector2.from_angle(float(f["ph"]) * TAU)
				var w := clampf(burst / burst_len, 0.0, 1.0)
				p += dir * 180.0 * s * burst * (1.0 - 0.35 * w)
				d = dir
				b = maxf(b, 0.5) * (1.0 + 0.6 * bump(w * 4.0)) * pow(1.0 - w, 1.3)
			pts.append(p)
			lum.append(b)
			dirs.append(d)
			any = any or b > 0.01
		alpha = 1.0 if any else 0.0

	func on_tap(_p: Vector2) -> void:
		dur = minf(dur, tap_at + 0.85)

	func hit(p: Vector2) -> bool:
		for i in pts.size():
			if float(lum[i]) > 0.08 and (pts[i] as Vector2).distance_to(p) <= 60.0:
				return true
		return false

	func bounds() -> Rect2:
		var r := Rect2()
		var he := Vector2(13, 13) * s
		for i in pts.size():
			if float(lum[i]) > 0.05:
				var b := box(pts[i], he)
				r = b if not r.has_area() else r.merge(b)
		return r

	func _draw() -> void:
		for i in pts.size():
			var b := float(lum[i])
			if b <= 0.02:
				continue
			var p: Vector2 = pts[i]
			var d: Vector2 = dirs[i]
			var f: Dictionary = flies[i]
			var fl := 0.5 + 0.5 * sin(t * 150.0 + float(f["wing"]))
			var vis := clampf(0.35 + b, 0.0, 1.0)
			# Flügelchen (flirrend) und dunkler Körper vor dem leuchtenden Hinterleib
			for sg in [-1.0, 1.0]:
				wing(p + d * 4.0 * s, (4.5 + 1.5 * fl) * s, 2.6 * s, d.angle() + float(sg) * (2.2 - 0.5 * fl), ca(WING, 0.32 * vis))
			poly_ellipse(p + d * 4.2 * s, 3.4 * s, 1.8 * s, ca(BODY, 0.9 * vis), d.angle(), 12)
			draw_circle(p + d * 7.4 * s, 1.3 * s, ca(BODY, 0.9 * vis))

	func _draw_glow() -> void:
		for i in pts.size():
			var b := float(lum[i])
			if b <= 0.02:
				continue
			var p: Vector2 = pts[i]
			var sz := float((flies[i] as Dictionary)["sz"])
			glow(p, 32.0 * s * sz, ca(COL, 0.42 * b))
			glow(p, 12.0 * s * sz, ca(COL, b))
			glow(p, 4.6 * s, ca(CORE, minf(1.0, 1.4 * b)))


# ===================================================================================================== 13 Eule

class Owl extends NightBase:
	const BODY := Color("#4A3B63")
	const WING := Color("#3A2D52")
	const WING_HI := Color("#5F4D82")
	const CHEST := Color("#7A6A92")
	const CHEST_V := Color("#5A4B74")
	const FACE := Color("#8C7BA6")
	const FACE_RIM := Color("#6B5B86")
	const IRIS := Color("#FFB627")
	const BEAK := Color("#E8C46A")
	const BEAK_D := Color("#9E7A34")
	const GLIDE := 1.6
	const FOLD := 0.3
	var land := Vector2.ZERO
	var side := 1.0
	var from := Vector2.ZERO
	var exit_to := Vector2.ZERO
	var blinks: Array = []
	var t_turn := 0.0
	var t_back := 0.0
	var t_turn2 := 0.0
	var yaw_target := 0.0
	var look_target := Vector2(0, 1)
	var t_puff := 0.0
	var s := 1.0
	# Pose
	var pos := Vector2.ZERO
	var spread := 0.0
	var flap := 0.0
	var tilt := 0.0
	var yaw := 0.0
	var look := Vector2.ZERO
	var lid := 0.2
	var puff := 1.0

	func setup(c: Dictionary) -> void:
		use_glow()
		s = k()
		in_s = GLIDE + FOLD
		out_s = 1.2
		own_leave = true
		var o: Dictionary = c.get("ort", {}) if c.get("ort") is Dictionary else {}
		var deg := float(o.get("deg", 205.0))
		var he := Vector2(25, 30) * s
		var best_d := deg
		var best_q := 0.5
		var best_c := INF
		# Schulter (200–215° / 325–340°) bevorzugt; ist sie bei vielen Spielern zugestellt, eine freie Stelle weiter hinten
		var cands: Array = [deg]
		var d0 := 190.0
		while d0 <= 350.0:
			cands.append(d0)
			d0 += 5.0
		for d in cands:
			var dd := float(d)
			var off := 0.0 if (dd >= 198.0 and dd <= 217.0) or (dd >= 323.0 and dd <= 342.0) else 0.25 + 0.002 * minf(absf(dd - 207.0), absf(dd - 332.0))
			for q in [0.3, 0.55, 0.8]:
				var p := band(dd, float(q))
				var cost := spot_cost(p + Vector2(0, -29) * s, he) + off + absf(dd - deg) * 0.0015 + rng.randf() * 0.01
				if cost < best_c:
					best_c = cost
					best_d = dd
					best_q = float(q)
		land = band(best_d, best_q)
		side = 1.0 if land.x >= center().x else -1.0
		from = land + Vector2(side * 270.0, -230.0) * s
		exit_to = land + Vector2(side * 330.0, -260.0) * s
		t_turn = in_s + rng.randf_range(1.0, 1.8)
		t_back = t_turn + 0.6 + rng.randf_range(2.4, 3.4)
		t_turn2 = t_back + 0.6 + rng.randf_range(1.6, 2.4)
		var tr := int(c.get("troedler", -1))
		var head := land + Vector2(0, -40) * s
		for q in c.get("seats", []):
			var qd: Dictionary = q
			if int(qd.get("seat", -9)) == tr:
				var dp: Vector2 = Vector2(qd["pos"]) - head
				if bool(qd.get("me", false)):
					yaw_target = clampf(dp.x / 600.0, -0.3, 0.3)
				else:
					yaw_target = clampf(dp.x / 380.0, -0.75, 0.75)
				look_target = dp.normalized() if dp.length() > 1.0 else Vector2(0, 1)
		var tb := in_s + rng.randf_range(0.4, 1.2)
		while tb < dur:
			blinks.append(tb)
			tb += rng.randf_range(3.0, 4.0)
		t_puff = rng.randf_range(in_s + 2.0, maxf(in_s + 2.1, dur - out_s - 1.4))

	# Kopfdrehung und Blick der ruhigen Zeitlinie
	func _gaze(tl: float) -> void:
		var w := 0.0
		if tl >= t_turn2:
			w = e_io((tl - t_turn2) / 0.6)
		elif tl >= t_back:
			w = 1.0 - e_io((tl - t_back) / 0.6)
		elif tl >= t_turn:
			w = e_io((tl - t_turn) / 0.6)
		yaw = yaw_target * w
		look = Vector2(0, 0.5).lerp(look_target, w)

	func pose_at(tt: float) -> void:
		var sl := since_leave(tt)
		var tl := leave_at if sl >= 0.0 else tt
		var t_dep := dur - out_s
		alpha = ramp(tt, 0.0, 0.35)
		yaw = 0.0
		look = Vector2(0, 0.5)
		flap = 0.0
		tilt = 0.0
		if tl < GLIDE:
			var u := tl / GLIDE
			pos = bez2(from, land + Vector2(side * 120.0, -24.0) * s, land, e_out(u))
			spread = 1.0
			flap = 0.22 * sin(u * TAU * 1.5) * (1.0 - u)
			tilt = side * 0.16 * (1.0 - u)
		elif tl < GLIDE + FOLD:
			pos = land
			spread = 1.0 - e_io((tl - GLIDE) / FOLD)
		elif tl >= t_dep:
			var u := (tl - t_dep) / out_s
			spread = minf(1.0, u / 0.2)
			pos = land.lerp(exit_to, e_in(maxf(0.0, (u - 0.12) / 0.88)))
			flap = 0.35 * sin(u * TAU * 2.2)
			tilt = -side * 0.12 * u
			alpha = 1.0 - smoothstep(0.7, 1.0, u)
		else:
			pos = land
			spread = 0.0
			_gaze(tl)
		# Blinzeln
		lid = 0.1
		for b in blinks:
			var x := tl - float(b)
			if x >= 0.0 and x < 0.3:
				lid = maxf(lid, 0.1 + 0.9 * bump(x / 0.3))
		puff = 1.0 + 0.06 * bump((tl - t_puff) / 0.9)
		# Tipp: Kopf fast ganz herum, mit Überschwinger zurück; zweimal blinzeln
		var st := since_tap(tt)
		if st >= 0.0 and st < 0.9 and spread < 0.5:
			var off := 0.0
			if st < 0.35:
				off = 2.7 * e_out(st / 0.35)
			elif st < 0.45:
				off = 2.7
			else:
				off = 2.7 * (1.0 - back_out((st - 0.45) / 0.45))
			yaw += off * (1.0 if yaw_target >= 0.0 else -1.0)
			for x in [st - 0.05, st - 0.62]:
				if x >= 0.0 and x < 0.24:
					lid = maxf(lid, 0.2 + 0.8 * bump(x / 0.24))
		# schneller Abgang: Flügel auf und davon
		if sl >= 0.0:
			var u := sl / maxf(leave_s, 0.05)
			spread = maxf(spread, minf(1.0, u * 3.0))
			pos += (exit_to - land) * 0.7 * e_in(u)
			flap = 0.4 * sin(u * TAU * 1.5)
			lid = 0.1
			alpha *= 1.0 - u * u

	func bounds() -> Rect2:
		if alpha <= 0.0:
			return Rect2()
		var sc := s * puff
		var he := Vector2(lerpf(24.0, 62.0, spread), 31.0) * sc
		return box(pos + Vector2(0, -29) * sc, he)

	# Merkmal auf dem Kopf (Zylinder): Winkel phi bei Kopfdrehung yaw → x-Lage und Stauchung (≤ 0: nicht zu sehen)
	func _feat(phi: float, r: float) -> Vector2:
		var a := phi + yaw
		return Vector2(sin(a) * r, cos(a))

	func _wing_pts(sgn: float) -> PackedVector2Array:
		var prof := [Vector2(0, -0.4), Vector2(0.25, -0.6), Vector2(0.55, -0.64), Vector2(0.8, -0.52), Vector2(0.95, -0.3), Vector2(1.0, -0.06),
			Vector2(0.96, 0.1), Vector2(0.88, 0.06), Vector2(0.89, 0.24), Vector2(0.79, 0.2), Vector2(0.78, 0.38), Vector2(0.67, 0.33),
			Vector2(0.64, 0.5), Vector2(0.53, 0.44), Vector2(0.48, 0.58), Vector2(0.36, 0.52), Vector2(0.28, 0.62), Vector2(0.13, 0.52), Vector2(0.0, 0.4)]
		var ln := lerpf(29.0, 52.0, spread)
		var wd := lerpf(12.0, 27.0, spread)
		var ang := lerpf(PI * 0.5 - 0.1, -0.2 + flap, spread)
		var base := Vector2(12.0, -32.0)
		var xf := Transform2D(ang, base)
		var out := PackedVector2Array()
		for q in prof:
			var v: Vector2 = q
			var p := xf * Vector2(v.x * ln, v.y * wd)
			out.append(Vector2(p.x * sgn, p.y))
		return out

	func _wings() -> void:
		for sgn in [-1.0, 1.0]:
			var w := _wing_pts(float(sgn))
			draw_colored_polygon(w, WING)
			# helle Deckfedern an der Vorderkante, Federlinien zu den Kerben
			var lead := PackedVector2Array([w[0], w[1], w[2], w[3]])
			draw_polyline(lead, WING_HI, 2.4, true)
			# Deckfedern als hellerer Streifen, Schwungfedern als Linien von den Kerben
			var cov := PackedVector2Array([w[0], w[1], w[2], w[3], w[3].lerp(w[13], 0.3), w[1].lerp(w[17], 0.35), w[0].lerp(w[18], 0.4)])
			draw_colored_polygon(cov, ca(WING_HI, 0.55))
			for j in [7, 9, 11, 13, 15]:
				draw_line(w[j], w[j].lerp(w[2], 0.42), ca(RING, 0.4), 1.0, true)
			outline_poly(w, RING, 1.3)

	func _ears(col: Color, w: float) -> void:
		for sgn in [-1.0, 1.0]:
			var f := _feat(float(sgn) * 0.78, 14.0)
			var ex := f.x
			var o := float(sgn) * (0.5 + 0.5 * absf(f.y))
			var tri_pts := PackedVector2Array([Vector2(ex - 4.5 * o, -48.0), Vector2(ex + 7.0 * o, -60.5), Vector2(ex + 5.0 * o, -46.0)])
			if w > 0.0:
				var cl := tri_pts.duplicate()
				cl.append(tri_pts[0])
				draw_polyline(cl, col, w, true)
			else:
				draw_colored_polygon(tri_pts, col)

	func _draw() -> void:
		if alpha <= 0.0:
			return
		draw_set_transform(pos, tilt, Vector2(s, s) * puff)
		var body_c := Vector2(0, -21)
		var head_c := Vector2(0, -39)
		if spread > 0.5:
			_wings()
		# Kontur (Lavendel), dann Flächen: so entsteht eine Umrisslinie um Körper, Kopf und Ohren
		ellipse_line(self, body_c, 19.0, 21.0, RING, 3.2)
		ellipse_line(self, head_c, 18.5, 15.5, RING, 3.2)
		_ears(RING, 3.2)
		poly_ellipse(body_c, 19.0, 21.0, BODY, 0.0, 28)
		poly_ellipse(head_c, 18.5, 15.5, BODY, 0.0, 28)
		_ears(BODY, 0.0)
		if spread <= 0.5:
			_wings()
		# Brust mit V-Federn
		poly_ellipse(Vector2(0, -17), 11.5, 13.5, CHEST, 0.0, 22)
		for q in [Vector2(-5.5, -25), Vector2(0.5, -27), Vector2(6, -24.5), Vector2(-6.5, -18.5), Vector2(0, -20), Vector2(6.5, -18),
				Vector2(-4, -11.5), Vector2(2.5, -12.5), Vector2(7, -10)]:
			var v: Vector2 = q
			draw_polyline(PackedVector2Array([v + Vector2(-2.2, -1.3), v + Vector2(0, 0.9), v + Vector2(2.2, -1.3)]), CHEST_V, 1.2, true)
		_face()
		# Krallen
		if spread < 0.5:
			for sgn in [-1.0, 1.0]:
				for dx in [-2.3, 0.0, 2.3]:
					poly_ellipse(Vector2(float(sgn) * 6.5 + float(dx), -0.6), 1.3, 2.1, BEAK, 0.0, 10)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _face() -> void:
		var front := cos(yaw)
		if front < -0.2:
			# Hinterkopf: ein paar Federbögen
			for q in [Vector2(-5, -44), Vector2(4, -45), Vector2(0, -37), Vector2(-7, -35), Vector2(7, -35)]:
				var v: Vector2 = q
				var x := v.x * absf(front) * 0.8 + sin(yaw + PI) * 4.0
				draw_arc(Vector2(x, v.y), 3.0, 0.2, PI - 0.2, 6, CHEST_V, 1.2, true)
		# Gesichtsscheiben
		for sgn in [-1.0, 1.0]:
			var f := _feat(float(sgn) * 0.42, 18.0)
			if f.y > 0.06:
				poly_ellipse(Vector2(f.x, -40.0), 8.9 * f.y, 9.3, FACE, 0.0, 20)
				ellipse_line(self, Vector2(f.x, -40.0), 8.9 * f.y, 9.3, FACE_RIM, 1.1, 0.0, 20)
		# Stirn-V zwischen den Augen
		if front > 0.25:
			var a := _feat(-0.62, 18.0)
			var b := _feat(0.0, 18.0)
			var c := _feat(0.62, 18.0)
			draw_polyline(PackedVector2Array([Vector2(a.x, -48.5), Vector2(b.x, -46.6), Vector2(c.x, -48.5)]), FACE_RIM, 1.4, true)
		# Augen mit Lid
		for sgn in [-1.0, 1.0]:
			var f := _feat(float(sgn) * 0.42, 18.0)
			if f.y <= 0.1:
				continue
			var e := Vector2(f.x, -40.0)
			poly_ellipse(e, 5.4 * f.y, 5.4, IRIS, 0.0, 18)
			var lp := Vector2(look.x * 1.7 * f.y, look.y * 1.5)
			poly_ellipse(e + lp, 3.0 * f.y, 3.1, INK, 0.0, 14)
			draw_circle(e + lp + Vector2(-1.1 * f.y, -1.3), 1.05, Color(1, 1, 1, 0.95))
			var lp_pts := top_segment(e, 5.9 * f.y, 5.9, lid)
			if lp_pts.size() >= 3:
				draw_colored_polygon(lp_pts, FACE)
				draw_line(lp_pts[0], lp_pts[lp_pts.size() - 1], FACE_RIM, 1.2, true)
		# Schnabel
		var bf := _feat(0.0, 18.0)
		if bf.y > 0.15:
			var bx := bf.x
			var bw := 2.8 * bf.y
			var bk := PackedVector2Array([Vector2(bx - bw, -38.5), Vector2(bx + bw, -38.5), Vector2(bx, -32.5)])
			draw_colored_polygon(bk, BEAK)
			outline_poly(bk, BEAK_D, 0.9)

	func _draw_glow() -> void:
		if alpha <= 0.0 or lid > 0.85:
			return
		var xf := Transform2D(tilt, pos)
		for sgn in [-1.0, 1.0]:
			var f := _feat(float(sgn) * 0.42, 18.0)
			if f.y > 0.2:
				glow(xf * (Vector2(f.x, -40.0) * s * puff), 9.0 * s, ca(IRIS, 0.32 * f.y * (1.0 - lid)))


# ===================================================================================================== 14 Fledermaus

class Bat extends NightBase:
	const LINE := Color("#8B6BFF")
	const EYE := Color("#FF5FB8")
	var nodes: Array = []
	var times: Array = []
	var pos := Vector2.ZERO
	var dir := Vector2.RIGHT
	var flap := 0.0
	var s := 1.0

	func setup(c: Dictionary) -> void:
		s = k()
		var W := table_size().x
		var H := table_size().y
		var sky: Rect2 = c.get("ort") if c.get("ort") is Rect2 else Rect2(0, 0.04 * H, W, 0.26 * H)
		var dirx := 1.0 if rng.randf() < 0.5 else -1.0
		var ylo := sky.position.y + 14.0 * s
		var yhi := sky.position.y + sky.size.y * 0.62
		# mehrere zufällige Zickzack-Bahnen, genommen wird die am wenigsten verdeckte
		var best: Array = []
		var best_t: Array = []
		var best_c := INF
		for attempt in 10:
			var n := rng.randi_range(8, 10)
			var turn_i := rng.randi_range(3, n - 3)
			var segs: Array = []
			for i in n:
				var a := rng.randf_range(-deg_to_rad(35.0), deg_to_rad(35.0))
				var d := rng.randf_range(0.38, 0.6)
				if i == turn_i:
					a = PI + rng.randf_range(-0.45, 0.45)
					d = rng.randf_range(0.22, 0.3)
				segs.append([a, d])
			var sumx := 0.0
			for sg in segs:
				sumx += cos(float(sg[0])) * float(sg[1])
			var v := (W + 110.0 * s) / maxf(sumx, 0.8)
			var y0 := lerpf(ylo + 6.0 * s, yhi - 6.0 * s, rng.randf())
			var p := Vector2(-55.0 * s if dirx > 0.0 else W + 55.0 * s, y0)
			var path: Array = [p]
			var tms: Array = [0.0]
			var T := 0.0
			var hidden := 0
			var count := 0
			for sg in segs:
				var dv := Vector2(cos(float(sg[0])) * dirx, sin(float(sg[0]))) * v * float(sg[1])
				var q := p + dv
				if q.y < ylo or q.y > yhi:
					dv.y = -dv.y
					q = p + dv
				q.y = clampf(q.y, ylo, yhi)
				for j in 5:
					var m := p.lerp(q, (float(j) + 0.5) / 5.0)
					if _inside(m):
						count += 1
						if not seen(box(m, Vector2(25, 14) * s)):
							hidden += 1
				path.append(q)
				T += float(sg[1])
				tms.append(T)
				p = q
			var cost := float(hidden) / maxf(float(count), 1.0)
			if cost < best_c:
				best_c = cost
				best = path
				best_t = tms
		nodes = best
		times = best_t
		dur = float(times[times.size() - 1])
		# An- und Abflug außerhalb des Bilds zählen nicht zur Hauptphase
		in_s = 0.0
		out_s = 0.0
		var tt := 0.0
		while tt < dur:
			if _inside(_at(tt)):
				break
			tt += 0.02
		in_s = minf(tt, dur * 0.3)
		tt = dur
		while tt > 0.0:
			if _inside(_at(tt)):
				break
			tt -= 0.02
		out_s = minf(dur - tt, dur * 0.3)

	func _inside(p: Vector2) -> bool:
		return p.x > 24.0 * s and p.x < table_size().x - 24.0 * s

	func _at(tt: float) -> Vector2:
		for i in range(1, times.size()):
			if tt <= float(times[i]) or i == times.size() - 1:
				var t0 := float(times[i - 1])
				var u := clampf((tt - t0) / maxf(float(times[i]) - t0, 0.001), 0.0, 1.0)
				return (nodes[i - 1] as Vector2).lerp(nodes[i], u)
		return nodes[0]

	func pose_at(tt: float) -> void:
		pos = _at(tt)
		var d := _at(minf(tt + 0.03, dur)) - _at(maxf(tt - 0.03, 0.0))
		if d.length() > 0.1:
			dir = d.normalized()
		flap = sin(TAU * 8.0 * tt)
		alpha = minf(ramp(tt, 0.0, 0.12), 1.0 - ramp(tt, dur - 0.12, dur))

	func bounds() -> Rect2:
		return box(pos, Vector2(25, 14) * s) if alpha > 0.0 else Rect2()

	func _wing(sgn: float) -> PackedVector2Array:
		var f := flap
		var pts := [Vector2(3, -1), Vector2(11, -7.5 - 6.0 * f), Vector2(24, -2.5 - 9.0 * f), Vector2(20, 3.0 - 5.5 * f),
			Vector2(16.5, 0.8 - 3.8 * f), Vector2(13, 6.0 - 2.6 * f), Vector2(9.5, 3.0 - 1.6 * f), Vector2(6, 6.2 - 0.8 * f), Vector2(2.5, 4)]
		var out := PackedVector2Array()
		for q in pts:
			var v: Vector2 = q
			out.append(Vector2(v.x * sgn, v.y))
		return out

	func _draw() -> void:
		if alpha <= 0.0:
			return
		glow(pos, 30.0 * s, ca(LINE, 0.2))
		var tilt := clampf(atan2(dir.y, absf(dir.x)), -0.6, 0.6) * 0.45 * signf(dir.x if absf(dir.x) > 0.05 else 1.0)
		draw_set_transform(pos, tilt, Vector2(s, s))
		var wl := _wing(-1.0)
		var wr := _wing(1.0)
		var body := ellipse_points(Vector2(0, 1.5), 4.4, 6.6, 0.0, 16)
		var head := ellipse_points(Vector2(0, -5), 4.2, 4.0, 0.0, 14)
		var ears: Array = []
		for sgn in [-1.0, 1.0]:
			var g := float(sgn)
			ears.append(PackedVector2Array([Vector2(3.9 * g, -6.6), Vector2(4.8 * g, -12.6), Vector2(1.2 * g, -8.4)]))
		var parts: Array = [wl, wr, body, head, ears[0], ears[1]]
		for p in parts:
			var cl: PackedVector2Array = (p as PackedVector2Array).duplicate()
			cl.append(cl[0])
			draw_polyline(cl, LINE, 3.0, true)
		for p in parts:
			draw_colored_polygon(p, NIGHT)
		# Fingerknochen
		for sgn in [-1.0, 1.0]:
			var w := wr if float(sgn) > 0.0 else wl
			for j in [3, 5, 7]:
				draw_line(w[1], w[j], ca(LINE, 0.35), 0.8, true)
		for sgn in [-1.0, 1.0]:
			draw_circle(Vector2(1.7 * float(sgn), -5.4), 0.95, EYE)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ===================================================================================================== 15 Mond mit Schlafmütze

class MoonCap extends NightBase:
	const CAP := Color("#FF2FA8")
	const CAP_D := Color("#B0157A")
	const POM := Color("#FFF7E8")
	const POM_D := Color("#E2D3BE")
	const CHEEK := Color(1.0, 0.45, 0.72, 0.5)
	var M := Vector2.ZERO
	var tip := Vector2.ZERO
	var eye := Vector2.ZERO
	var cheek := Vector2.ZERO
	var brim := Vector2.ZERO
	var brim_rot := 0.0
	var z_times: Array = []
	var font: Font
	# Pose
	var hat_off := Vector2.ZERO
	var hat_rot := 0.0
	var swing := 0.0
	var eye_open := 0.0
	var zs: Array = []

	func setup(c: Dictionary) -> void:
		var o: Dictionary = c.get("ort", {}) if c.get("ort") is Dictionary else {}
		var W := table_size().x
		var H := table_size().y
		M = o.get("pos", Vector2(W * 0.94, H * 0.08))
		var r_moon := float(o.get("r", 40.0))
		var cut: Vector2 = o.get("cut", Vector2(17, -12))
		var r1 := r_moon - 1.25                      # table_background.gdshader: smoothstep(40.0, 37.5, md)
		var r2 := r_moon * 0.8125                    # smoothstep(31.0, 34.0, md2)
		var d := cut.length()
		var u := cut / maxf(d, 0.001)
		var a := (r1 * r1 - r2 * r2 + d * d) / (2.0 * d)
		var h := sqrt(maxf(r1 * r1 - a * a, 0.0))
		var perp := Vector2(-u.y, u.x)
		var t1 := u * a + perp * h
		var t2 := u * a - perp * h
		tip = M + (t1 if t1.y < t2.y else t2)
		eye = M + _mid(198.0, r1, r2, cut)
		cheek = M + _mid(152.0, r1, r2, cut)
		# Mütze sitzt schräg oben auf dem Mond (der Mond steht dicht am oberen Rand), der Zipfel fällt nach rechts in die Sichel
		brim = M + Vector2.from_angle(deg_to_rad(258.0)) * (r1 - 4.0)
		brim_rot = 0.62
		if calm:
			in_s = 1.0
			out_s = 1.0
		else:
			in_s = 0.8
			out_s = 0.9
			var zt := 1.3
			while zt < dur - out_s - 1.4:
				z_times.append(zt)
				zt += 2.0
		font = UiFonts.title(800) if UiFonts.has_fonts() else ThemeDB.fallback_font

	# Mitte der Sichel entlang des Strahls im Winkel deg (vom Mondmittelpunkt aus)
	static func _mid(deg: float, r1: float, r2: float, cut: Vector2) -> Vector2:
		var dv := Vector2.from_angle(deg_to_rad(deg))
		var dc := dv.dot(cut)
		var disc := dc * dc - cut.length_squared() + r2 * r2
		var s_in := dc + sqrt(maxf(disc, 0.0))
		return dv * (clampf(s_in, 0.0, r1) + r1) * 0.5

	func pose_at(tt: float) -> void:
		zs.clear()
		hat_off = Vector2.ZERO
		hat_rot = brim_rot
		swing = 0.0
		eye_open = 0.0
		if calm:
			alpha = edge_fade(tt)
			return
		alpha = 1.0 - ramp(tt, dur - 0.3, dur)
		# Mütze fällt mit kleinem Abpraller, das Auge schließt sich nach der Landung
		if tt < 0.6:
			var u := tt / 0.6
			var f := e_in(u / 0.7) if u < 0.7 else 1.0 - 0.14 * sin(PI * (u - 0.7) / 0.3)
			hat_off.y = -85.0 * (1.0 - f)
			hat_rot += 0.35 * (1.0 - u) * sin(u * 9.0)
			alpha *= ramp(tt, 0.0, 0.12)
		eye_open = 1.0 - ramp(tt, 0.42, 0.68)
		swing = deg_to_rad(12.0) * sin(TAU * (tt - 0.6) / 2.4) * ramp(tt, 0.5, 1.2)
		hat_off.y += 0.8 * sin(TAU * tt / 2.4)
		# Wind pustet die Mütze weg, der Mond schaut kurz
		var te := dur - 0.8
		if tt > te:
			var u := (tt - te) / 0.8
			hat_off += Vector2(75.0, -55.0) * e_in(u)
			hat_rot += 1.5 * e_in(u)
			eye_open = maxf(eye_open, ramp(u, 0.05, 0.25))
		# Tipp: wacht kurz auf, der Bommel hüpft
		var st := since_tap(tt)
		if st >= 0.0 and st < 1.2:
			eye_open = maxf(eye_open, ramp(st, 0.0, 0.12) * (1.0 - ramp(st, 0.55, 0.75)))
			swing += 0.45 * sin(TAU * 2.5 * st) * exp(-3.0 * st)
			hat_off.y += -4.0 * bump(st / 0.3)
		for zt in z_times:
			var u := (tt - float(zt)) / 1.6
			if u > 0.0 and u < 1.0:
				zs.append(u)

	func bounds() -> Rect2:
		return Rect2(M + Vector2(-52, -64), Vector2(104, 112)) if alpha > 0.0 else Rect2()

	# Mittellinie der Zipfelmütze (Pendeln um den Knick)
	func _cap_line() -> Array:
		var p0 := Vector2(0, 0)
		var p1 := Vector2(5, -15)
		var p2 := Vector2(23, -21)
		var p3 := Vector2(31, -1)
		p2 = p1 + (p2 - p1).rotated(swing * 0.5)
		p3 = p1 + (p3 - p1).rotated(swing)
		return [p0, p1, p2, p3]

	func _draw() -> void:
		if alpha <= 0.0:
			return
		# Bäckchen und Auge auf der Sichel
		glow(cheek, 9.0, CHEEK)
		if eye_open < 0.2:
			draw_arc(eye + Vector2(0, -2.2), 4.8, 0.35, PI - 0.35, 14, ca(INK, 0.7), 2.2, true)
		else:
			poly_ellipse(eye, 2.6, 3.4 * eye_open, ca(INK, 0.85), 0.0, 14)
			draw_circle(eye + Vector2(-0.8, -1.2 * eye_open), 0.9, Color(1, 1, 1, 0.95))
			draw_arc(eye + Vector2(0, -0.5), 4.4, PI + 0.5, TAU - 0.5, 10, ca(INK, 0.5), 1.2, true)
		# z steigt nach links oben
		for u in zs:
			var uu := float(u)
			var p := M + Vector2(-40, -10) + Vector2(-46, -26) * uu + Vector2(sin(uu * 6.0) * 3.0, 0)
			var fs := int(round(lerpf(16.0, 28.0, uu)))
			draw_string(font, p, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ca(CREAM, 0.9 * sin(PI * uu)))
		# Zipfelmütze
		draw_set_transform(brim + hat_off, hat_rot, Vector2.ONE)
		var cl := _cap_line()
		var n := 18
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		var mids: Array = []
		for i in n + 1:
			var f := float(i) / float(n)
			var c := bez3(cl[0], cl[1], cl[2], cl[3], f)
			var tg := bez3(cl[0], cl[1], cl[2], cl[3], minf(f + 0.02, 1.0)) - bez3(cl[0], cl[1], cl[2], cl[3], maxf(f - 0.02, 0.0))
			var nn := Vector2(-tg.y, tg.x).normalized()
			var w := lerpf(15.0, 2.6, pow(f, 0.85))
			left.append(c + nn * w)
			right.append(c - nn * w)
			mids.append(c)
		var rows := [left, right]
		var col_rows := [_cols(n + 1, CAP), _cols(n + 1, CAP)]
		mesh(self, rows, col_rows)
		# Schatten auf der Unterseite
		var shade := PackedVector2Array()
		for i in n + 1:
			shade.append(right[i].lerp(left[i], 0.35))
		mesh(self, [shade, right], [_cols(n + 1, ca(CAP_D, 0.0)), _cols(n + 1, ca(CAP_D, 0.45))])
		# drei cremefarbene Streifen
		for rg in [[5, 6], [9, 10], [13, 14]]:
			var i0 := int(rg[0])
			var i1 := int(rg[1])
			mesh(self, [PackedVector2Array([left[i0], left[i1]]), PackedVector2Array([right[i0], right[i1]])],
				[_cols(2, ca(POM, 0.95)), _cols(2, ca(POM, 0.95))])
		var outline := PackedVector2Array()
		outline.append_array(left)
		for i in range(n, -1, -1):
			outline.append(right[i])
		outline.append(left[0])
		draw_polyline(outline, CAP_D, 1.3, true)
		# Krempe
		var b0 := PackedVector2Array()
		var b1 := PackedVector2Array()
		for i in 4:
			var f := float(i) / 3.0
			var c := bez3(cl[0], cl[1], cl[2], cl[3], f * 0.12)
			var tg: Vector2 = ((cl[1] as Vector2) - (cl[0] as Vector2)).normalized()
			var nn := Vector2(-tg.y, tg.x)
			b0.append(c + nn * 17.0)
			b1.append(c - nn * 17.0)
		var brim_rows := [PackedVector2Array([b0[0], b0[3]]), PackedVector2Array([b1[0], b1[3]])]
		mesh(self, brim_rows, [_cols(2, POM), _cols(2, POM)])
		draw_polyline(PackedVector2Array([b0[0], b0[3], b1[3], b1[0], b0[0]]), POM_D, 1.1, true)
		# Bommel
		var tg_end: Vector2 = ((cl[3] as Vector2) - (cl[2] as Vector2)).normalized()
		var pc: Vector2 = cl[3] + tg_end * 3.0
		for j in 10:
			var a := TAU * float(j) / 10.0
			draw_circle(pc + Vector2.from_angle(a) * 6.4, 2.6, POM_D)
		draw_circle(pc, 7.2, POM)
		for j in 10:
			var a := TAU * float(j) / 10.0 + 0.3
			draw_circle(pc + Vector2.from_angle(a) * 5.6, 2.3, POM)
		draw_arc(pc, 5.0, 0.4, 2.2, 8, POM_D, 1.2, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	static func _cols(n: int, c: Color) -> PackedColorArray:
		var out := PackedColorArray()
		out.resize(n)
		out.fill(c)
		return out


# ===================================================================================================== 16 Polarlicht

class Aurora extends NightBase:
	const COLS := [Color("#4FFFB0"), Color("#19E0D4"), Color("#A855FF")]
	const A_MAX := 0.35
	const N := 40
	var curtains: Array = []
	var u := 0.0
	var ext := Rect2()
	var s := 1.0

	func setup(c: Dictionary) -> void:
		material = TableEffects.additive()
		s = k()
		in_s = 3.0
		out_s = 3.0
		var W := table_size().x
		var H := table_size().y
		var top: Rect2 = c.get("ort") if c.get("ort") is Rect2 else Rect2(0, 0.02 * H, W, 0.18 * H)
		var centers := [0.3, 0.55, 0.78]
		if rng.randf() < 0.5:
			centers = [0.72, 0.47, 0.22]
		var order := [2, 0, 1]                      # Lila weiter hinten (zuerst), dann Grün, Türkis
		for i in order:
			var cx := (float(centers[i]) + rng.randf_range(-0.04, 0.04)) * W
			var half := rng.randf_range(0.2, 0.26) * W
			var cu := {
				"col": COLS[i], "x0": cx - half, "x1": cx + half,
				"y": top.end.y - rng.randf_range(0.0, 18.0) * s - (28.0 * s if i == 2 else 0.0),
				"h": rng.randf_range(125.0, 175.0) * s,
				"l1": rng.randf_range(280.0, 420.0) * s, "l2": rng.randf_range(150.0, 230.0) * s, "l3": rng.randf_range(90.0, 150.0) * s,
				"p1": rng.randf() * TAU, "p2": rng.randf() * TAU, "p3": rng.randf() * TAU,
				"dir": 1.0 if rng.randf() < 0.5 else -1.0, "a": 0.75 if i == 2 else 1.0,
			}
			curtains.append(cu)
			var r := Rect2(float(cu["x0"]) - 30.0 * s, float(cu["y"]) - float(cu["h"]) - 10.0 * s,
				float(cu["x1"]) - float(cu["x0"]) + 60.0 * s, float(cu["h"]) + 34.0 * s)
			ext = r if not ext.has_area() else ext.merge(r)

	func pose_at(tt: float) -> void:
		alpha = edge_fade(tt)
		u = 0.0 if calm else tt

	func bounds() -> Rect2:
		return ext if alpha > 0.0 else Rect2()

	func _draw() -> void:
		if alpha <= 0.0:
			return
		for cu in curtains:
			_curtain(cu)

	func _curtain(cu: Dictionary) -> void:
		var col: Color = cu["col"]
		var hem := col.lerp(Color.WHITE, 0.35)
		var x0 := float(cu["x0"])
		var x1 := float(cu["x1"])
		var y := float(cu["y"])
		var h := float(cu["h"])
		var l1 := float(cu["l1"])
		var l2 := float(cu["l2"])
		var l3 := float(cu["l3"])
		var p1 := float(cu["p1"])
		var p2 := float(cu["p2"])
		var p3 := float(cu["p3"])
		var dr := float(cu["dir"])
		var aa := float(cu["a"])
		var r_lo := PackedVector2Array()
		var r_b := PackedVector2Array()
		var r_m := PackedVector2Array()
		var r_t := PackedVector2Array()
		var c_lo := PackedColorArray()
		var c_b := PackedColorArray()
		var c_m := PackedColorArray()
		var c_t := PackedColorArray()
		var rays: Array = []
		for j in N + 1:
			var f := float(j) / float(N)
			var x := lerpf(x0, x1, f)
			var taper := smoothstep(0.0, 0.2, f) * smoothstep(1.0, 0.8, f)
			var yb := y + 14.0 * s * sin(TAU * x / l1 + TAU * 0.12 * u * dr + p1) + 6.0 * s * sin(TAU * x / l2 - 0.8 * u + p2)
			var lean := 20.0 * s * sin(TAU * x / l1 * 0.7 + 0.5 * u + p3)
			var hh := h * (0.72 + 0.28 * sin(TAU * x / l3 + p3 + 0.3 * u))
			var br := (0.5 + 0.5 * pow(sin(TAU * x / l3 + 1.1 * u + p2), 2.0)) * (0.88 + 0.12 * sin(0.9 * u + p1))
			var ab := A_MAX * aa * taper * br
			r_lo.append(Vector2(x, yb + 5.0 * s))
			r_b.append(Vector2(x, yb))
			r_m.append(Vector2(x + lean * 0.35, yb - hh * 0.32))
			r_t.append(Vector2(x + lean, yb - hh))
			c_lo.append(ca(col, 0.0))
			c_b.append(ca(hem, ab))
			c_m.append(ca(col, ab * 0.75))
			c_t.append(ca(col, 0.0))
			if j % 3 == 1:
				rays.append([Vector2(x, yb), Vector2(x + lean * 0.85, yb - hh * 0.9), taper * br])
		mesh(self, [r_lo, r_b, r_m, r_t], [c_lo, c_b, c_m, c_t])
		for ry in rays:
			var a: Vector2 = ry[0]
			var b: Vector2 = ry[1]
			var w := float(ry[2])
			var dx := Vector2(1.2 * s, 0)
			mesh(self, [PackedVector2Array([a - dx, a + dx]), PackedVector2Array([b - dx, b + dx])],
				[PackedColorArray([ca(col, 0.1 * aa * w), ca(col, 0.1 * aa * w)]), PackedColorArray([ca(col, 0.0), ca(col, 0.0)])])


# ===================================================================================================== 17 Katzen-Sternbild

class Constellation extends NightBase:
	const STAR := Color("#DDE6FF")
	const T0 := 0.2
	const STEP := 0.22
	const LINES_S := 1.4
	var P: Array = []
	var L: Array = []
	var sizes: Array = []
	var tw: Array = []
	var rect := Rect2()
	var t_lines0 := 0.0
	var star_b: Array = []
	var line_f: Array = []
	var Q: Array = []

	func setup(c: Dictionary) -> void:
		material = TableEffects.additive()
		var W := table_size().x
		var H := table_size().y
		rect = c.get("ort") if c.get("ort") is Rect2 else Rect2(0.32 * W - 120.0, 0.02 * H + 4.0, 240, 160)
		# Kasten verfeinern: der freieste 240 × 160-Platz im oberen Himmel (nicht am Mond, nicht über den Knöpfen oben links)
		var moon: Variant = anchor("mond")
		var mp: Vector2 = (moon as Dictionary).get("pos", Vector2(W * 0.94, H * 0.08)) if moon is Dictionary else Vector2(W * 0.94, H * 0.08)
		var best_c := cover_frac(rect) + 0.0
		var x := 0.14
		while x <= 0.87:
			var r := Rect2(x * W - rect.size.x * 0.5, rect.position.y, rect.size.x, rect.size.y)
			var cost := cover_frac(r) + outside_frac(r) + absf(r.get_center().x - rect.get_center().x) / W * 0.15
			if r.get_center().distance_to(mp) < 200.0 or r.intersects(Rect2(0, 0, 280, 110)):
				cost += 1.0
			if cost < best_c - 0.02:
				best_c = cost
				rect = r
			x += 0.02
		var form: Dictionary = c.get("form", {}) if c.get("form") is Dictionary else {}
		var punkte: Array = form.get("punkte", [])
		L = form.get("linien", [])
		var inner := rect.grow(-16.0)
		for p in punkte:
			P.append(inner.position + Vector2(float(p[0]) * inner.size.x, float(p[1]) * inner.size.y))
			sizes.append(1.0)
			tw.append([rng.randf_range(0.6, 1.1), rng.randf() * TAU])
		for i in [0, 2]:
			if i < sizes.size():
				sizes[i] = 1.3
		if sizes.size() > 10:
			sizes[10] = 1.25
		t_lines0 = T0 + float(P.size()) * STEP + 0.15
		if calm:
			in_s = 1.5
			out_s = 1.5
		else:
			in_s = t_lines0 + LINES_S
			out_s = 1.8
			dur = maxf(dur, in_s + out_s + 3.0)

	func pose_at(tt: float) -> void:
		star_b.clear()
		line_f.clear()
		Q = P.duplicate()
		if calm:
			alpha = edge_fade(tt)
			for i in P.size():
				star_b.append(1.0)
			for j in L.size():
				line_f.append(1.0)
			return
		alpha = 1.0 - ramp(tt, dur - out_s, dur)
		var st := since_tap(tt)
		for i in P.size():
			var ti := T0 + float(i) * STEP
			var b := ramp(tt, ti, ti + 0.12) * (1.0 + 0.8 * bump((tt - ti) / 0.35))
			if tt > in_s:
				b *= 0.8 + 0.2 * sin(TAU * float(tw[i][0]) * tt + float(tw[i][1]))
			if st >= 0.0:
				b *= 1.0 + 1.3 * bump(st / 0.4)
			star_b.append(b)
		var dt := LINES_S / maxf(float(L.size()), 1.0)
		for j in L.size():
			var a := t_lines0 + float(j) * dt
			line_f.append(clampf((tt - a) / dt, 0.0, 1.0))
		# Schwanz wackelt nach dem Tipp
		if st >= 0.0 and st < 1.6 and Q.size() > 10:
			var axis := (Q[10] as Vector2) - (Q[8] as Vector2)
			var nn := Vector2(-axis.y, axis.x).normalized()
			var w := 7.0 * exp(-2.5 * st) * sin(TAU * 2.2 * st)
			Q[9] = (Q[9] as Vector2) + nn * w * 0.6
			Q[10] = (Q[10] as Vector2) + nn * w

	func bounds() -> Rect2:
		return rect if alpha > 0.0 else Rect2()

	func _draw() -> void:
		if alpha <= 0.0:
			return
		for j in L.size():
			var f := float(line_f[j])
			if f <= 0.0:
				continue
			var a: Vector2 = Q[int(L[j][0])]
			var b: Vector2 = Q[int(L[j][1])]
			var e := a.lerp(b, f)
			draw_line(a, e, ca(STAR, 0.1), 4.5, true)
			draw_line(a, e, ca(STAR, 0.45), 1.5, true)
		var ray := TableEffects.sparkle_ray_texture()
		var core := TableEffects.sparkle_core_texture()
		for i in Q.size():
			var b := float(star_b[i])
			if b <= 0.01:
				continue
			var p: Vector2 = Q[i]
			var sz := 20.0 * float(sizes[i]) * (0.75 + 0.25 * minf(b, 1.6))
			glow(p, 9.0 * float(sizes[i]), ca(STAR, 0.22 * minf(b, 1.5)))
			draw_texture_rect(ray, Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, ca(STAR, minf(b, 1.0)))
			draw_set_transform(p, PI * 0.25, Vector2.ONE)
			var s2 := sz * 0.55
			draw_texture_rect(ray, Rect2(-Vector2(s2, s2) * 0.5, Vector2(s2, s2)), false, ca(STAR, 0.7 * minf(b, 1.0)))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var cs := 9.0 * float(sizes[i])
			draw_texture_rect(core, Rect2(p - Vector2(cs, cs) * 0.5, Vector2(cs, cs)), false, Color(1, 1, 1, minf(b, 1.0)))


# ===================================================================================================== 18 UFO

class Ufo extends NightBase:
	const HULL_LO := Color("#6B7394")
	const HULL_HI := Color("#B8C0D8")
	const RIM := Color("#19C6D4")
	const DOME := Color("#7FF6FF")
	const ALIEN := Color("#7CFFB2")
	const LIGHTS := [Color("#FF4FD8"), Color("#FFE14D"), Color("#3FF2E6"), Color("#FF4FD8"), Color("#FFE14D")]
	const BEAM := Color("#B5FFF6")
	var hover := Vector2.ZERO
	var pile := Rect2()
	var start := Vector2.ZERO
	var ctrl := Vector2.ZERO
	var exit_dir := Vector2(0.6, -1.0).normalized()
	var t_beam0 := 1.9
	var t_beam1 := 4.4
	var sparks: Array = []
	var s := 1.0
	var he := Vector2(38, 19)
	# Pose
	var pos := Vector2.ZERO
	var rot := 0.0
	var beam := 0.0
	var tl := 0.0

	func setup(c: Dictionary) -> void:
		use_glow()
		own_leave = true
		s = k()
		he = Vector2(38, 19) * s
		var o: Dictionary = c.get("ort", {}) if c.get("ort") is Dictionary else {}
		var sz := table_size()
		hover = o.get("pos", Vector2(sz.x * 0.39, sz.y * 0.23))
		pile = o.get("pile", Rect2(hover + Vector2(-58, 62), Vector2(116, 180)))
		in_s = 1.5
		out_s = 0.8
		# Schwebepunkt: über dem Stapel, aber frei von Plätzen und Knöpfen (ein wenig tiefer oder seitlich, wenn nötig)
		var best_c := INF
		var h0 := hover
		for dy in [0.0, 8.0, 16.0, 22.0]:
			for dx in [0.0, -15.0, 15.0, -30.0, 30.0, -45.0, 45.0]:
				var hp := h0 + Vector2(float(dx), float(dy)) * s
				var cost := (10.0 if touches(box(hp, he), ["stapel"]) else 0.0) + absf(float(dx)) * 0.01 + float(dy) * 0.012
				if cost < best_c:
					best_c = cost
					hover = hp
		best_c = INF
		for dx in [-320.0, -220.0, -150.0, -80.0, 0.0, 80.0, 150.0, 220.0, 320.0]:
			var st := Vector2(hover.x + dx * s, -50.0 * s)
			var cp := Vector2(hover.x + dx * 0.85 * s, hover.y - 30.0 * s)
			var cost := 0.0
			for i in 16:
				if touches(box(bez2(st, cp, hover, e_out((float(i) + 0.5) / 16.0)), he), ["stapel"]):
					cost += 1.0
			cost += 0.6 * absf(absf(dx) - 150.0) / 320.0 + rng.randf() * 0.05
			if cost < best_c:
				best_c = cost
				start = st
				ctrl = cp
		best_c = INF
		for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(-0.5, -1), Vector2(0.5, -1), Vector2(-1.4, -0.8), Vector2(1.4, -0.8), Vector2(0, -1)]:
			var dn := (d as Vector2).normalized()
			var cost := 0.0
			for i in 12:
				var u := (float(i) + 0.5) / 12.0
				if touches(box(hover + dn * 520.0 * s * e_in(u), he), ["stapel"]):
					cost += 1.0
			cost += rng.randf() * 0.3 + (0.4 if absf(dn.x) < 0.1 else 0.0)
			if cost < best_c:
				best_c = cost
				exit_dir = dn
		t_beam1 = minf(t_beam1, dur - out_s - 0.3)
		var n := rng.randi_range(4, 6)
		for i in n:
			sparks.append({"t0": t_beam0 + 0.2 + (float(i) + rng.randf() * 0.8) / float(n) * maxf(t_beam1 - t_beam0 - 1.3, 0.3),
				"life": rng.randf_range(0.9, 1.3), "x": rng.randf_range(-0.55, 0.55), "sz": rng.randf_range(0.8, 1.3), "wob": rng.randf() * TAU})

	func on_tap(_p: Vector2) -> void:
		leave(true)

	func pose_at(tt: float) -> void:
		var sl := since_leave(tt)
		tl = leave_at if sl >= 0.0 else tt
		var t_dep := dur - out_s
		alpha = 1.0
		if tl < in_s:
			var u := tl / in_s
			pos = bez2(start, ctrl, hover, e_out(u))
			rot = deg_to_rad(8.0) * sin(u * TAU * 1.25) * (1.0 - u)
		elif tl < t_dep:
			pos = hover + Vector2(0, 3.0 * s * sin(TAU * (tl - in_s) / 1.6))
			rot = deg_to_rad(2.0) * sin(TAU * tl / 2.3)
		else:
			var u := (tl - t_dep) / out_s
			pos = hover + exit_dir * 560.0 * s * e_in(u)
			rot = exit_dir.x * 0.25 * u
			alpha = 1.0 - smoothstep(0.75, 1.0, u)
		beam = ramp(tl, t_beam0, t_beam0 + 0.15) * (1.0 - ramp(tl, t_beam1 - 0.15, t_beam1))
		if sl >= 0.0:
			var u := sl / maxf(leave_s, 0.05)
			pos += exit_dir * 420.0 * s * e_in(u)
			rot = exit_dir.x * 0.3 * u
			beam = 0.0
			alpha = 1.0 - ramp(u, 0.55, 1.0)

	func _beam_geo() -> Array:
		var top := pos + Vector2(0, 13.0 * s)
		var by := pile.position.y + pile.size.y * 0.36
		var hw_top := 14.0 * s
		var hw_bot := (pile.size.x + 20.0) * 0.5
		var cx := pile.get_center().x
		return [top, hw_top, Vector2(cx, by), hw_bot]

	# Hülle = Untertasse. Der Lichtkegel (Deckkraft ≤ 0,22, additiv) zählt nicht dazu: er ist der einzige Teil, der den Stapel
	# berührt (natur.md 2.3); sein umschließendes Rechteck schnitte neben dem Stapel liegende Fächer, die er höchstens streift.
	func bounds() -> Rect2:
		return box(pos, he) if alpha > 0.0 else Rect2()

	func _light(i: int) -> Vector2:
		var x := -24.0 + 12.0 * float(i)
		return Vector2(x, 5.0 + 9.5 * sqrt(maxf(0.0, 1.0 - pow(x / 36.0, 2.0))) * 0.62)

	func _light_b(i: int) -> float:
		return 0.3 + 0.7 * pow(maxf(0.0, cos(TAU * (tl * 1.4 - float(i) / 5.0))), 2.0)

	func _draw() -> void:
		if alpha <= 0.0:
			return
		draw_set_transform(pos, rot, Vector2(s, s))
		# Untertasse
		poly_ellipse(Vector2(0, 5), 36.0, 9.5, HULL_LO, 0.0, 32)
		poly_ellipse(Vector2(0, 1), 31.0, 8.0, HULL_HI, 0.0, 32)
		var seam := PackedVector2Array()
		for i in 13:
			var a := lerpf(0.25, PI - 0.25, float(i) / 12.0)
			seam.append(Vector2(cos(a) * 24.0, 1.0 + sin(a) * 4.6))
		draw_polyline(seam, ca(HULL_LO, 0.6), 1.2, true)
		# kleiner Gast unter der Kuppel
		draw_line(Vector2(0, -12), Vector2(1.5, -16.5), ALIEN, 1.2, true)
		draw_circle(Vector2(1.5, -17), 1.5, ALIEN)
		poly_ellipse(Vector2(0, -6.5), 6.6, 6.0, ALIEN, 0.0, 16)
		for sgn in [-1.0, 1.0]:
			poly_ellipse(Vector2(2.4 * float(sgn), -7.0), 1.5, 2.1, INK, 0.0, 10)
		draw_arc(Vector2(0, -4.6), 1.8, 0.4, PI - 0.4, 6, INK, 0.9, true)
		# Glaskuppel
		var dome := top_segment(Vector2(0, 0), 15.0, 15.0, 0.5, 18)
		draw_colored_polygon(dome, ca(DOME, 0.42))
		draw_polyline(dome, ca(RIM, 0.85), 1.2, true)
		draw_arc(Vector2(0, 0), 11.0, PI + 0.55, PI + 1.25, 8, Color(1, 1, 1, 0.75), 1.6, true)
		# Rand und Lichterkette
		ellipse_line(self, Vector2(0, 5), 36.0, 9.5, RIM, 2.0, 0.0, 36)
		for i in 5:
			var c: Color = LIGHTS[i]
			draw_circle(_light(i), 2.5, c.lerp(Color.WHITE, 0.35 * _light_b(i)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_glow() -> void:
		if alpha <= 0.0:
			return
		var xf := Transform2D(rot, pos)
		if beam > 0.0:
			var g := _beam_geo()
			var top: Vector2 = g[0]
			var bot: Vector2 = g[2]
			var ht := float(g[1])
			var hb := float(g[3])
			var rows := [PackedVector2Array([top - Vector2(ht, 0), top, top + Vector2(ht, 0)]),
				PackedVector2Array([bot - Vector2(hb, 0), bot, bot + Vector2(hb, 0)])]
			var a_top := 0.15 * beam
			var a_bot := 0.05 * beam
			mesh(glow_layer, rows, [PackedColorArray([ca(BEAM, a_top * 0.7), ca(BEAM, a_top), ca(BEAM, a_top * 0.7)]),
				PackedColorArray([ca(BEAM, a_bot * 0.5), ca(BEAM, a_bot), ca(BEAM, a_bot * 0.5)])])
			var core_rows := [PackedVector2Array([top - Vector2(ht * 0.45, 0), top + Vector2(ht * 0.45, 0)]),
				PackedVector2Array([bot - Vector2(hb * 0.35, 0), bot + Vector2(hb * 0.35, 0)])]
			mesh(glow_layer, core_rows, [PackedColorArray([ca(BEAM, 0.07 * beam), ca(BEAM, 0.07 * beam)]),
				PackedColorArray([ca(BEAM, 0.01 * beam), ca(BEAM, 0.01 * beam)])])
			# Funken steigen im Kegel auf
			for sp in sparks:
				var age := tl - float(sp["t0"])
				var life := float(sp["life"])
				if age < 0.0 or age > life:
					continue
				var u := age / life
				var y := lerpf(bot.y - 4.0 * s, top.y + 6.0 * s, e_out(u))
				var f := (y - top.y) / maxf(bot.y - top.y, 1.0)
				var hw := lerpf(ht, hb, f)
				var p := Vector2(lerpf(top.x, bot.x, f) + float(sp["x"]) * hw + 4.0 * s * sin(age * 6.0 + float(sp["wob"])), y)
				glow(p, 5.0 * s * float(sp["sz"]), Color(0.85, 1.0, 0.97, 0.9 * bump(u) * beam))
		for i in 5:
			var c: Color = LIGHTS[i]
			glow(xf * (_light(i) * s), 8.0 * s, ca(c, 0.75 * _light_b(i)))
		glow(xf * (Vector2(0, 5) * s), 46.0 * s, ca(RIM, 0.12))


# ===================================================================================================== 19 Satellit

class Satellite extends NightBase:
	const PANEL := Color("#8FB8FF")
	const RED := Color("#FF4D57")
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var red_ph := 0.0
	var t_flash := 0.0
	var s := 1.0
	var pos := Vector2.ZERO
	var red := 0.0
	var flash := 0.0
	var dirx := 1.0

	func setup(c: Dictionary) -> void:
		material = TableEffects.additive()
		s = k()
		var W := table_size().x
		var H := table_size().y
		var top: Rect2 = c.get("ort") if c.get("ort") is Rect2 else Rect2(0, 0.02 * H, W, 0.18 * H)
		dirx = 1.0 if rng.randf() < 0.5 else -1.0
		var x0 := -20.0 * s if dirx > 0.0 else W + 20.0 * s
		var x1 := W + 20.0 * s if dirx > 0.0 else -20.0 * s
		var best_c := INF
		for i in 5:
			var y0 := top.position.y + top.size.y * (0.12 + 0.19 * float(i)) + rng.randf_range(-4.0, 4.0) * s
			for dy in [-40.0, -15.0, 15.0, 40.0]:
				var y1 := clampf(y0 + float(dy) * s, top.position.y + 6.0, top.end.y)
				var cost := 0.0
				for j in 16:
					cost += spot_cost(Vector2(x0, y0).lerp(Vector2(x1, y1), (float(j) + 0.5) / 16.0), Vector2(9, 9) * s)
				cost += rng.randf() * 0.2
				if cost < best_c:
					best_c = cost
					a = Vector2(x0, y0)
					b = Vector2(x1, y1)
		in_s = 0.4
		out_s = 0.4
		red_ph = rng.randf()
		# Aufblitzen an einer Stelle, an der er frei am Himmel steht
		t_flash = rng.randf_range(0.35, 0.65) * dur
		for i in 12:
			var tf := rng.randf_range(0.2, 0.8) * dur
			if seen(box(a.lerp(b, tf / dur), Vector2(14, 14) * s)):
				t_flash = tf
				break

	func pose_at(tt: float) -> void:
		pos = a.lerp(b, clampf(tt / dur, 0.0, 1.0))
		red = 1.0 if fposmod(tt + red_ph, 1.0) < 0.1 else 0.0
		flash = bump((tt - t_flash) / 0.4)
		alpha = edge_fade(tt)

	func bounds() -> Rect2:
		return box(pos, Vector2(9, 9) * s) if alpha > 0.0 else Rect2()

	func _draw() -> void:
		if alpha <= 0.0:
			return
		# feine Spur hinter dem Satelliten (zeigt die Bewegung), Schein, Solarflächen, heller Kern, rotes Blinklicht
		var back := (a - b).normalized()
		mesh(self, [PackedVector2Array([pos, pos + back * 46.0 * s]), PackedVector2Array([pos + Vector2(0, 0.8) * s, pos + back * 46.0 * s + Vector2(0, 0.8) * s])],
			[PackedColorArray([Color(0.8, 0.88, 1, 0.22), Color(0.8, 0.88, 1, 0.0)]), PackedColorArray([Color(0.8, 0.88, 1, 0.22), Color(0.8, 0.88, 1, 0.0)])])
		glow(pos, 11.0 * s, Color(0.85, 0.9, 1, 0.45 + 0.4 * flash))
		if flash > 0.01:
			glow(pos, 8.0 * s * (1.0 + flash), Color(1, 1, 1, 0.85 * flash))
			var sz := 30.0 * s * flash
			draw_texture_rect(TableEffects.sparkle_ray_texture(), Rect2(pos - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false,
				Color(1, 1, 1, flash))
		for sgn in [-1.0, 1.0]:
			var pr := Rect2(pos + Vector2(float(sgn) * 6.5 - 2.75, -1.5) * s, Vector2(5.5, 3.0) * s)
			draw_rect(pr, ca(PANEL, 0.8))
			draw_line(pr.get_center() - Vector2(0, 1.5) * s, pr.get_center() + Vector2(0, 1.5) * s, Color(0.1, 0.15, 0.4, 0.6), 0.6)
		draw_line(pos - Vector2(4, 0) * s, pos + Vector2(4, 0) * s, Color(0.9, 0.92, 1, 0.8), 0.8)
		draw_circle(pos, 1.9 * s, Color(1, 1, 1, 1))
		if red > 0.0:
			var rp := pos + Vector2(0, 2.6) * s
			glow(rp, 6.0 * s, ca(RED, 0.8))
			draw_circle(rp, 1.2 * s, RED)


# ===================================================================================================== 20 Motte am Ablage-Ring

class Moth extends NightBase:
	const WING := Color("#8C7E6A")
	const HIND := Color("#74685A")
	const SAUM := Color("#CFC0A4")
	const BODY := Color("#6E6252")
	const HEAD := Color("#A89A84")
	const SPOT := Color("#5A4F42")
	const NSTEP := 72
	const ROUND := 2.2
	var ctr := Vector2.ZERO
	var rx := 156.0
	var ry := 134.0
	var steps := PackedFloat32Array()
	var j0 := 0
	var ang_dir := 1.0
	var p_in := Vector2.ZERO
	var exit_to := Vector2.ZERO
	var th_end := 0.0
	var tint := Color(1, 0.9, 0.7)
	var ph := [0.0, 0.0, 0.0, 0.0]
	var s := 1.0
	var pos := Vector2.ZERO
	var heading := 0.0
	var flap := 1.0

	func setup(c: Dictionary) -> void:
		use_glow()
		own_leave = true
		s = k() * 1.35                       # etwas größer als im Entwurf (22 × 16), sonst nachts kaum zu sehen
		in_s = 1.2
		out_s = 1.0
		var o: Dictionary = c.get("ort", {}) if c.get("ort") is Dictionary else {}
		ctr = o.get("pos", table_size() * Vector2(0.61, 0.445))
		var R := float(o.get("r", 116.0))
		rx = R + 40.0 * k()
		ry = R + 18.0 * k()
		for i in 4:
			ph[i] = rng.randf() * TAU
		ang_dir = 1.0 if rng.randf() < 0.5 else -1.0
		# Verweilen, wo sie zu sehen ist: Zeit je 5°-Schritt ∝ Sichtbarkeit
		var half := Vector2(11, 8) * s
		var vis := PackedFloat32Array()
		var best := -1.0
		for j in NSTEP:
			var p := _orbit(TAU * float(j) / float(NSTEP))
			var v := 1.0 - minf(1.0, cover_frac(box(p, half)) + outside_frac(box(p, half)))
			vis.append(v)
			var sc := v + rng.randf() * 0.04
			if sc > best:
				best = sc
				j0 = j
		var sum := 0.0
		for j in NSTEP:
			var w := 0.08 + 0.92 * smoothstep(0.3, 0.8, vis[j])
			steps.append(w)
			sum += w
		for j in NSTEP:
			steps[j] = ROUND * steps[j] / sum
		var th0 := TAU * float(j0) / float(NSTEP)
		var out0 := Vector2(cos(th0), sin(th0))
		p_in = _orbit(th0) + out0 * 200.0 * s + Vector2(0, -70) * s
		th_end = _angle(dur - in_s - out_s)
		var oe := Vector2(cos(th_end), sin(th_end))
		exit_to = _orbit(th_end) + oe * 250.0 * s + Vector2(0, -90) * s
		var tb: Variant = fx.get("table") if fx != null else null
		if tb is Object:
			var ring: Variant = (tb as Object).get("_color_ring")
			if ring is Object:
				var col: Variant = (ring as Object).get("color")
				if col is Color and (col as Color).a > 0.05:
					tint = col

	func _orbit(th: float) -> Vector2:
		return ctr + Vector2(cos(th) * rx, sin(th) * ry)

	# Winkel nach m Sekunden Kreisen (gewichtete Schritte, ab j0 in Drehrichtung)
	func _angle(m: float) -> float:
		var rounds := floorf(m / ROUND)
		var rest := m - rounds * ROUND
		var acc := 0.0
		var k0 := 0
		var frac := 0.0
		while k0 < NSTEP:
			var j := posmod(j0 + int(ang_dir) * k0, NSTEP)
			var d := steps[j]
			if acc + d >= rest:
				frac = (rest - acc) / maxf(d, 0.0001)
				break
			acc += d
			k0 += 1
		return TAU * float(j0) / float(NSTEP) + ang_dir * (TAU * rounds + (float(k0) + frac) * TAU / float(NSTEP))

	func _jit(tt: float) -> Vector2:
		return Vector2(sin(TAU * 5.3 * tt + ph[0]), cos(TAU * 4.1 * tt + ph[1])) * 3.5 * s

	func _path(tl: float) -> Vector2:
		if tl < in_s:
			var u := tl / in_s
			return p_in.lerp(_orbit(TAU * float(j0) / float(NSTEP)), e_out(u)) + _jit(tl) * (1.0 + 2.0 * (1.0 - u))
		if tl < dur - out_s:
			var m := tl - in_s
			var th := _angle(m)
			var jr := 6.0 * s * sin(TAU * 1.1 * m + ph[2])
			var poke := -10.0 * s * pow(maxf(0.0, sin(TAU * 1.6 * m + ph[3])), 8.0)
			return ctr + Vector2(cos(th) * (rx + jr + poke), sin(th) * (ry + jr + poke * 0.9)) + _jit(tl)
		var u := (tl - (dur - out_s)) / out_s
		return _orbit(th_end).lerp(exit_to, e_in(u)) + _jit(tl) * 2.0

	func pose_at(tt: float) -> void:
		var sl := since_leave(tt)
		var tl := leave_at if sl >= 0.0 else tt
		pos = _path(tl)
		var d := _path(tl + 0.04) - pos
		if d.length() > 0.05:
			heading = d.angle()
		flap = absf(sin(TAU * 14.0 * tt))
		alpha = ramp(tt, 0.0, 0.25) * (1.0 - ramp(tl, dur - 0.4, dur))
		if sl >= 0.0:
			var u := sl / maxf(leave_s, 0.05)
			var away := (pos - ctr).normalized()
			pos += (away + Vector2(0, -0.6)).normalized() * 300.0 * s * e_in(u) + _jit(tt) * 2.0
			heading = (away + Vector2(0, -0.6)).angle()
			alpha *= 1.0 - u * u

	func bounds() -> Rect2:
		return box(pos, Vector2(11, 8) * s) if alpha > 0.0 else Rect2()

	func _draw() -> void:
		if alpha <= 0.0:
			return
		# Lichtschein vom Ring auf der Motte (hinter ihr, normal gemischt: sie bleibt graubraun)
		glow(pos, 22.0 * s, ca(tint.lerp(Color(1, 0.92, 0.75), 0.4), 0.3))
		draw_set_transform(pos, heading, Vector2(s, s))
		var sp := 0.45 + 0.55 * flap
		var wc := WING.lerp(tint, 0.18)
		var hc := HIND.lerp(tint, 0.18)
		for sgn in [-1.0, 1.0]:
			var g := float(sgn) * sp
			var hind := PackedVector2Array([Vector2(-2, 1 * g), Vector2(-4, 6 * g), Vector2(-8, 7.5 * g), Vector2(-10.5, 5 * g), Vector2(-9, 2 * g)])
			draw_colored_polygon(hind, hc)
			outline_poly(hind, SAUM, 0.9)
		for sgn in [-1.0, 1.0]:
			var g := float(sgn) * sp
			var fore := PackedVector2Array([Vector2(4, 1 * g), Vector2(3, 6 * g), Vector2(0.5, 10.5 * g), Vector2(-3.5, 11 * g),
				Vector2(-6, 8 * g), Vector2(-4.5, 3 * g), Vector2(-2, 1 * g)])
			draw_colored_polygon(fore, wc)
			outline_poly(fore, SAUM, 1.0)
			draw_circle(Vector2(-1.2, 6.5 * g), 1.3, SPOT)
		poly_ellipse(Vector2(-2, 0), 6.0, 2.4, BODY, 0.0, 14)
		draw_circle(Vector2(4.2, 0), 2.2, HEAD)
		for sgn in [-1.0, 1.0]:
			var g := float(sgn)
			var a0 := Vector2(5.5, 0.8 * g)
			var a1 := Vector2(10.0, 4.6 * g)
			draw_line(a0, a1, ca(HEAD, 0.95), 0.8, true)
			for q in 3:
				var m := a0.lerp(a1, 0.35 + 0.22 * float(q))
				draw_line(m, m + Vector2(0.9, 1.4 * g), ca(HEAD, 0.8), 0.6, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_glow() -> void:
		if alpha <= 0.0:
			return
		pass


# ===================================================================================================== 21 Igel am Plattformrand

class Hedgehog extends NightBase:
	const COAT := Color("#6B5139")
	const TIP := Color("#AE8A62")
	const FACE := Color("#D9BE98")
	const FACE_D := Color("#B39673")
	const BELLY := Color("#B59772")
	const EAR := Color("#C4A47E")
	const LEG := Color("#3E2E20")
	const SPEED := 20.0
	const SZ := 1.3                      # Zeichnung etwas größer als im Entwurf (44 × 26), sonst nachts kaum zu sehen
	var path := PackedVector2Array()
	var cum := PackedFloat32Array()
	var walk_len := 80.0
	var segs: Array = []                 # [t0, t1, art, d0, d1]
	var dur0 := 12.0
	var s := 1.0
	var tap_d := 0.0
	var tap_face := 1.0
	var tap_tilt := 0.0
	# Pose
	var pos := Vector2.ZERO
	var face := 1.0
	var tilt := 0.0
	var step_ph := 0.0
	var sniff := 0.0
	var ball := 0.0
	var squash := 1.0

	func setup(c: Dictionary) -> void:
		s = k()
		in_s = 0.5
		out_s = 0.5
		var o: Dictionary = c.get("ort", {}) if c.get("ort") is Dictionary else {}
		var deg := float(o.get("deg", 140.0))
		walk_len = maxf((dur - 2.1) * SPEED * s * 0.5, 40.0 * s)
		var best_c := INF
		var best_path := PackedVector2Array()
		for st in [165.0, 160.0, 155.0, 150.0, 145.0, 140.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0]:
			var dirn := -1.0 if float(st) > 90.0 else 1.0
			var p := _band_path(float(st), dirn)
			var cost := 0.0
			var n := 0
			for i in range(0, p.size(), maxi(1, p.size() / 10)):
				cost += spot_cost(p[i] + Vector2(0, -13) * s * SZ, Vector2(24, 14) * s * SZ)
				n += 1
			cost /= maxf(float(n), 1.0)
			var same := (float(st) > 90.0) == (deg > 90.0)
			cost += (0.0 if same else 0.05) + absf(float(st) - deg) * 0.0005 + rng.randf() * 0.01
			if cost < best_c:
				best_c = cost
				best_path = p
		path = best_path
		cum = PackedFloat32Array([0.0])
		for i in range(1, path.size()):
			cum.append(cum[i - 1] + path[i].distance_to(path[i - 1]))
		walk_len = minf(walk_len, cum[cum.size() - 1])
		var v := SPEED * s
		var f1 := rng.randf_range(0.3, 0.5)
		var f2 := rng.randf_range(0.35, 0.6)
		var t := 0.0
		var d1 := walk_len * f1
		segs.append([t, t + d1 / v, "walk", 0.0, d1])
		t += d1 / v
		segs.append([t, t + 0.8, "sniff", d1, d1])
		t += 0.8
		segs.append([t, t + (walk_len - d1) / v, "walk", d1, walk_len])
		t += (walk_len - d1) / v
		segs.append([t, t + 0.5, "turn", walk_len, walk_len])
		t += 0.5
		var d2 := walk_len * (1.0 - f2)
		segs.append([t, t + (walk_len - d2) / v, "walk", walk_len, d2])
		t += (walk_len - d2) / v
		segs.append([t, t + 0.8, "sniff", d2, d2])
		t += 0.8
		segs.append([t, t + d2 / v, "walk", d2, 0.0])
		t += d2 / v
		dur = t
		dur0 = t

	# Punkte am Außenrand der Plattform ab Winkel st in Richtung dirn (Schritte 0,5°), bis zur Lauflänge
	func _band_path(st: float, dirn: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		var acc := 0.0
		var d := st
		var prev := band(d, 0.97)
		out.append(prev)
		var guard := 0
		while acc < walk_len + 2.0 and guard < 200:
			d += dirn * 0.5
			var p := band(d, 0.97)
			acc += p.distance_to(prev)
			out.append(p)
			prev = p
			guard += 1
		return out

	func _at(dist: float) -> Vector2:
		if path.size() < 2:
			return path[0] if path.size() > 0 else center()
		var dd := clampf(dist, 0.0, cum[cum.size() - 1])
		var lo := 0
		var hi := cum.size() - 1
		while hi - lo > 1:
			var mid := (lo + hi) / 2
			if cum[mid] <= dd:
				lo = mid
			else:
				hi = mid
		var u := (dd - cum[lo]) / maxf(cum[hi] - cum[lo], 0.001)
		return path[lo].lerp(path[hi], u)

	func _base(tt: float) -> Dictionary:
		# Abschnitte 0–2 hinaus (Weg wächst), 3 Umdrehen, 4–6 zurück
		var n := segs.size()
		for i in n:
			var sg: Array = segs[i]
			if tt <= float(sg[1]) or i == n - 1:
				var u := clampf((tt - float(sg[0])) / maxf(float(sg[1]) - float(sg[0]), 0.001), 0.0, 1.0)
				return {"dist": lerpf(float(sg[3]), float(sg[4]), u), "art": str(sg[2]), "fwd": 1.0 if i <= 3 else -1.0,
					"turn_u": u if str(sg[2]) == "turn" else 0.0, "local": tt - float(sg[0])}
		return {"dist": 0.0, "art": "walk", "fwd": 1.0, "turn_u": 0.0, "local": 0.0}

	# Blickrichtung auf dem Bildschirm aus der Laufrichtung entlang des Pfads
	func _screen_face(dist: float, fwd: float) -> Array:
		var a := _at(dist - 2.0)
		var b := _at(dist + 2.0)
		var tg := (b - a) * fwd
		if tg.length() < 0.01:
			tg = Vector2(fwd, 0)
		var f := 1.0 if tg.x >= 0.0 else -1.0
		var tl := clampf(atan2(tg.y * f, absf(tg.x)), -0.45, 0.45)
		return [f, tl]

	func pose_at(tt: float) -> void:
		ball = 0.0
		sniff = 0.0
		squash = 1.0
		var st := since_tap(tt)
		if st >= 0.0:
			var dist := tap_d
			face = tap_face
			tilt = tap_tilt
			ball = ramp(st, 0.0, 0.3) * (1.0 - ramp(st, 2.1, 2.4))
			if st > 2.4:
				dist = maxf(0.0, tap_d - 3.0 * SPEED * s * (st - 2.4))
				var sf := _screen_face(dist, -1.0)
				face = float(sf[0])
				tilt = float(sf[1])
				step_ph = dist / (5.0 * s) * TAU
			pos = _at(dist)
			alpha = 1.0 - ramp(tt, dur - 0.4, dur)
			return
		var bs := _base(tt)
		var dist := float(bs["dist"])
		pos = _at(dist)
		var sf := _screen_face(dist, float(bs["fwd"]))
		face = float(sf[0])
		tilt = float(sf[1])
		step_ph = dist / (5.0 * s) * TAU
		if str(bs["art"]) == "sniff":
			sniff = bump(float(bs["local"]) / 0.8)
		elif str(bs["art"]) == "turn":
			var u := float(bs["turn_u"])
			var sb := _screen_face(dist, -1.0)
			face = float(sf[0]) if u < 0.5 else float(sb[0])
			tilt = lerpf(float(sf[1]), float(sb[1]), u)
			squash = absf(cos(PI * u)) * 0.85 + 0.15
		alpha = minf(ramp(tt, 0.0, in_s), 1.0 - ramp(tt, dur0 - out_s, dur0))

	func on_tap(_p: Vector2) -> void:
		if t > dur0 - out_s - 0.1:
			return
		var bs := _base(tap_at)
		tap_d = float(bs["dist"])
		var sf := _screen_face(tap_d, float(bs["fwd"]))
		tap_face = float(sf[0])
		tap_tilt = float(sf[1])
		dur = tap_at + 2.4 + tap_d / (3.0 * SPEED * s) + 0.4

	func bounds() -> Rect2:
		return box(pos + Vector2(0, -13) * s * SZ, Vector2(24, 14) * s * SZ) if alpha > 0.0 else Rect2()

	func _draw() -> void:
		if alpha <= 0.0:
			return
		draw_set_transform(pos, tilt, Vector2(s * face * squash, s) * SZ)
		poly_ellipse(Vector2(1, 0.5), 20.0, 3.0, Color(0, 0, 0, 0.3), 0.0, 18)
		if ball < 0.999:
			_walker(1.0 - ball)
		if ball > 0.001:
			_ball(ball)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _walker(fa: float) -> void:
		# Beinchen trippeln
		var xs := [-11.0, -5.0, 5.0, 11.0]
		for i in 4:
			var lift := maxf(0.0, sin(step_ph + (PI if i % 2 == 1 else 0.0))) * 1.6
			poly_ellipse(Vector2(float(xs[i]), -2.0 - lift), 2.2, 2.6, ca(LEG, fa), 0.0, 10)
		poly_ellipse(Vector2(-2, -6), 15.0, 5.0, ca(BELLY, fa), 0.0, 18)
		# Stachelkleid: 14 Zacken über den Rücken
		var c := Vector2(-3, -9.5)
		var coat := PackedVector2Array()
		var tips: Array = []
		var n := 28
		for i in n + 1:
			var a := lerpf(PI, TAU - 0.35, float(i) / float(n))
			var r := 1.0 if i % 2 == 0 else 1.3
			var tilt_back := 0.0 if i % 2 == 0 else 0.12
			var p := c + Vector2(cos(a - tilt_back) * 17.5 * r, sin(a - tilt_back) * 12.5 * r)
			coat.append(p)
			if i % 2 == 1:
				tips.append(p)
		coat.append(Vector2(13, -8))
		coat.append(Vector2(6, -4))
		coat.append(Vector2(-15, -4))
		coat.append(Vector2(-20.5, -7))
		draw_colored_polygon(coat, ca(COAT, fa))
		for p in tips:
			var q: Vector2 = p
			var dirv := (q - c).normalized()
			tri(q, q - dirv * 6.0 + dirv.orthogonal() * 2.0, q - dirv * 6.0 - dirv.orthogonal() * 2.0, ca(TIP, fa))
		# Mondlicht-Kante auf den Stacheln
		var rim := PackedVector2Array()
		for i in range(2, tips.size() - 2):
			rim.append(tips[i])
		draw_polyline(rim, ca(CREAM, 0.7 * fa), 1.3, true)
		outline_poly(coat, ca(RING, 0.55 * fa), 1.0)
		# Gesicht mit spitzer Schnauze
		var snout := PackedVector2Array([Vector2(5.5, -14.5), Vector2(14, -15), Vector2(23.5, -9), Vector2(24, -6.5), Vector2(14, -4.2), Vector2(5.5, -5)])
		draw_colored_polygon(snout, ca(FACE, fa))
		draw_circle(Vector2(11, -9.8), 5.6, ca(FACE, fa))
		draw_polyline(PackedVector2Array([Vector2(14, -4.2), Vector2(24, -6.5)]), ca(FACE_D, fa), 1.0, true)
		draw_circle(Vector2(9.5, -15.6), 2.5, ca(EAR, fa))
		draw_circle(Vector2(9.6, -15.3), 1.2, ca(FACE_D, fa))
		draw_circle(Vector2(15.4, -11.4), 1.75, ca(INK, fa))
		draw_circle(Vector2(15.9, -12.0), 0.6, Color(1, 1, 1, 0.95 * fa))
		var nz := Vector2(24.3, -7.6) + Vector2(sin(t * 44.0) * 0.6, sin(t * 37.0) * 0.9) * sniff
		draw_circle(nz, 2.1, ca(INK, fa))
		draw_circle(nz + Vector2(-0.5, -0.7), 0.7, Color(1, 1, 1, 0.9 * fa))
		for q in [Vector2(20, -8.5), Vector2(20, -6.5)]:
			var v: Vector2 = q
			draw_line(v, v + Vector2(5.5, (v.y + 7.5) * 1.6 - 1.0), ca(FACE_D, 0.7 * fa), 0.6, true)

	func _ball(fa: float) -> void:
		var sc := 0.8 + 0.2 * fa
		var c := Vector2(0, -12.5 * sc)
		var r := 12.0 * sc
		var wob := 0.15 * sin(t * 5.0) * fa
		var pts := PackedVector2Array()
		var tips: Array = []
		var n := 36
		for i in n:
			var a := TAU * float(i) / float(n) + wob
			var rr := r * (1.0 if i % 2 == 0 else 1.35)
			var p := c + Vector2.from_angle(a) * rr
			pts.append(p)
			if i % 2 == 1:
				tips.append(p)
		draw_colored_polygon(pts, ca(COAT, fa))
		for p in tips:
			var q: Vector2 = p
			var dv := (q - c).normalized()
			tri(q, q - dv * 5.0 + dv.orthogonal() * 2.0, q - dv * 5.0 - dv.orthogonal() * 2.0, ca(TIP, fa))
		outline_poly(pts, ca(RING, 0.55 * fa), 1.0)
		draw_arc(c, r * 1.25, PI + 0.4, TAU - 0.4, 14, ca(CREAM, 0.7 * fa), 1.4, true)
		draw_circle(c + Vector2(6.5, 7.0) * sc, 1.8, ca(INK, fa))


# ===================================================================================================== 22 Komet

class Comet extends NightBase:
	const DUST := Color("#FFF3C8")
	const ION := Color("#8FB8FF")
	const CURVE := 18.0
	const WMAX := 22.0
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var sag := 30.0
	var tail_l := 160.0
	var s := 1.0
	var head := Vector2.ZERO
	var vdir := Vector2.RIGHT
	var shim := 0.0

	func setup(c: Dictionary) -> void:
		material = TableEffects.additive()
		s = k()
		in_s = 2.0
		out_s = 3.0
		var W := table_size().x
		var H := table_size().y
		var top: Rect2 = c.get("ort") if c.get("ort") is Rect2 else Rect2(0, 0.02 * H, W, 0.18 * H)
		tail_l = rng.randf_range(140.0, 180.0) * s
		sag = 30.0 * s
		var chord := 0.55 * W
		var dirx := 1.0 if rng.randf() < 0.5 else -1.0
		var moon: Variant = anchor("mond")
		var mp: Vector2 = (moon as Dictionary).get("pos", Vector2(W * 0.94, H * 0.08)) if moon is Dictionary else Vector2(W * 0.94, H * 0.08)
		var best_c := INF
		for xf in [0.04, 0.1, 0.16, 0.22, 0.28, 0.34, 0.41]:
			for yf in [0.12, 0.25, 0.4, 0.55, 0.7]:
				var x0 := float(xf) * W
				var y0 := top.position.y + float(yf) * top.size.y
				var dy := rng.randf_range(-14.0, 14.0) * s
				var aa := Vector2(x0, y0) if dirx > 0.0 else Vector2(x0 + chord, y0)
				var bb := Vector2(x0 + chord, y0 + dy) if dirx > 0.0 else Vector2(x0, y0 + dy)
				# wie die Sichtprüfung: Anteil der Hauptphase, in dem die Hülle zu mehr als der Hälfte verdeckt ist
				var hidden := 0.0
				for j in 12:
					var u := lerpf(in_s / dur, 1.0 - out_s / dur, (float(j) + 0.5) / 12.0)
					var g := _geo(u, aa, bb)
					if not seen(_rect(g[0], g[1])):
						hidden += 1.0
					if (g[0] as Vector2).distance_to(mp) < 90.0 * s:
						hidden += 0.5
				var cost := hidden / 12.0 + rng.randf() * 0.02
				if cost < best_c:
					best_c = cost
					a = aa
					b = bb

	func _geo(u: float, aa: Vector2, bb: Vector2) -> Array:
		var hp := aa.lerp(bb, u) + Vector2(0, sag * 4.0 * u * (1.0 - u))
		var vd := ((bb - aa) + Vector2(0, sag * 4.0 * (1.0 - 2.0 * u))).normalized()
		return [hp, vd]

	func pose_at(tt: float) -> void:
		var g := _geo(clampf(tt / dur, 0.0, 1.0), a, b)
		head = g[0]
		vdir = g[1]
		alpha = edge_fade(tt)
		shim = tt

	func _tail_dirs(vd: Vector2) -> Array:
		var back := -vd
		var perp := Vector2(-back.y, back.x)
		if perp.y < 0.0:
			perp = -perp
		return [back, perp]

	func _rect(hp: Vector2, vd: Vector2) -> Rect2:
		var tp := _tail_dirs(vd)
		var back: Vector2 = tp[0]
		var perp: Vector2 = tp[1]
		var r := box(hp, Vector2(12, 12) * s)
		r = r.expand(hp + back * tail_l * 1.1).expand(hp + back * tail_l + perp * (CURVE + WMAX * 0.6) * s)
		return r

	func bounds() -> Rect2:
		return _rect(head, vdir) if alpha > 0.0 else Rect2()

	func _draw() -> void:
		if alpha <= 0.0:
			return
		var tp := _tail_dirs(vdir)
		var back: Vector2 = tp[0]
		var perp: Vector2 = tp[1]
		var n := 18
		var r_l := PackedVector2Array()
		var r_c := PackedVector2Array()
		var r_r := PackedVector2Array()
		var c_l := PackedColorArray()
		var c_c := PackedColorArray()
		var c_r := PackedColorArray()
		for i in n:
			var f := float(i) / float(n - 1)
			var cpt := head + back * tail_l * f + perp * CURVE * s * f * f
			var w := lerpf(3.0, WMAX, f) * s
			var al := 0.7 * pow(1.0 - f, 1.3) * (0.9 + 0.1 * sin(shim * 1.3 - f * 7.0))
			r_l.append(cpt + perp * w)
			r_c.append(cpt)
			r_r.append(cpt - perp * w)
			c_l.append(ca(DUST, al * 0.15))
			c_c.append(ca(DUST, al))
			c_r.append(ca(DUST, al * 0.15))
		mesh(self, [r_l, r_c, r_r], [c_l, c_c, c_r])
		# gerader, schmaler Ionenschweif (leicht zur anderen Seite)
		var ib := back.rotated(-0.1 if perp.cross(back) > 0.0 else 0.1)
		var ip := Vector2(-ib.y, ib.x)
		var i_l := PackedVector2Array()
		var i_c := PackedVector2Array()
		var i_r := PackedVector2Array()
		var ic_l := PackedColorArray()
		var ic_c := PackedColorArray()
		var ic_r := PackedColorArray()
		for i in n:
			var f := float(i) / float(n - 1)
			var cpt := head + ib * tail_l * 1.15 * f
			var w := lerpf(1.5, 5.0, f) * s
			var al := 0.5 * (1.0 - f)
			i_l.append(cpt + ip * w)
			i_c.append(cpt)
			i_r.append(cpt - ip * w)
			ic_l.append(ca(ION, 0.0))
			ic_c.append(ca(ION, al))
			ic_r.append(ca(ION, 0.0))
		mesh(self, [i_l, i_c, i_r], [ic_l, ic_c, ic_r])
		glow(head, 26.0 * s, ca(DUST, 0.5))
		glow(head, 7.0 * s, Color(1, 1, 1, 0.85))
		draw_circle(head, 1.8 * s, Color(1, 1, 1, 0.95))


# ===================================================================================================== 23 Lampion

class Lantern extends NightBase:
	const SKIN := Color("#FF8A24")
	const SKIN_HI := Color("#FFB45E")
	const RIB := Color("#C45A10")
	const LIGHT := Color("#FFD27A")
	const HALO := Color("#FF9A3C")
	const FLAME := Color("#FFE27A")
	var x0 := 0.0
	const SZ := 1.3                      # etwas größer als im Entwurf (34 × 44)
	var drift := 0.0
	var y0 := 0.0
	var y1 := -80.0
	var speed := 45.0
	var ph := 0.0
	var fl_sd := 0.0
	var s := 1.0
	var pos := Vector2.ZERO
	var rot := 0.0
	var flick := 1.0
	var boost := 1.0

	func setup(c: Dictionary) -> void:
		use_glow()
		s = k()
		in_s = 1.2
		out_s = 1.0
		var W := table_size().x
		var o: Dictionary = c.get("ort", {}) if c.get("ort") is Dictionary else {}
		var start: Vector2 = o.get("pos", center())
		y1 = float(o.get("target_y", -80.0)) * s
		speed = rng.randf_range(40.0, 50.0) * s
		y0 = minf(y1 + speed * dur, center().y + 120.0 * s)
		speed = (y0 - y1) / dur
		# Hauptphase endet, wenn er oben aus dem Bild steigt (danach nur noch Ausblenden außerhalb)
		out_s = clampf((-34.0 * s - y1) / speed + 0.25, 0.8, dur * 0.3)
		ph = rng.randf() * TAU
		fl_sd = rng.randf() * 10.0
		# Start im freieren der beiden Spalten; der Wind treibt ihn ein wenig schräg (Weg nach oben möglichst frei)
		var best_c := INF
		x0 = start.x
		for gap in [[0.25, 0.40], [0.60, 0.75]]:
			var x := float(gap[0]) * W
			while x <= float(gap[1]) * W + 0.1:
				for dr in [0.0, -12.0, 12.0, -24.0, 24.0]:
					var hidden := 0.0
					for j in 16:
						var tt := lerpf(in_s, dur - out_s, (float(j) + 0.5) / 16.0)
						if not seen(box(Vector2(x + float(dr) * s * tt, y0 - speed * tt), Vector2(19, 26) * s * SZ)) or _on_band(Vector2(x + float(dr) * s * tt, y0 - speed * tt)):
							hidden += 1.0
					var cost := hidden / 16.0 + absf(x - start.x) * 0.0003 + absf(float(dr)) * 0.002 + rng.randf() * 0.01
					if cost < best_c:
						best_c = cost
						x0 = x
						drift = float(dr) * s
				x += 12.0 * s

	func pose_at(tt: float) -> void:
		var amp := 1.0
		boost = 1.0
		var st := since_tap(tt)
		if st >= 0.0:
			amp = 1.0 + 1.4 * exp(-1.2 * st)
			boost = 1.0 + 1.5 * ramp(st, 0.0, 0.12) * (1.0 - ramp(st, 0.25, 0.85))
		pos = Vector2(x0 + drift * tt + 10.0 * s * amp * sin(TAU * tt / 3.0 + ph), y0 - speed * tt)
		rot = deg_to_rad(4.0) * amp * sin(TAU * tt / 3.0 + ph + 0.7)
		flick = 0.9 + 0.1 * wobble(tt * 7.0, fl_sd)
		alpha = ramp(tt, 0.0, in_s) * (1.0 - ramp(tt, dur - 0.6, dur))

	func bounds() -> Rect2:
		return box(pos, Vector2(19, 26) * s * SZ) if alpha > 0.0 else Rect2()

	func _rx(y: float) -> float:
		return 16.5 - 3.5 * (y / 22.0)

	func _draw() -> void:
		if alpha <= 0.0:
			return
		draw_set_transform(pos, rot, Vector2(s, s) * SZ)
		var body := PackedVector2Array()
		for i in 32:
			var a := TAU * float(i) / 32.0
			var y := 22.0 * sin(a)
			var yy := y
			if y < -19.0:
				yy = -19.0 - (-y - 19.0) * 0.4
			body.append(Vector2(_rx(y) * cos(a), yy))
		draw_colored_polygon(body, SKIN)
		poly_ellipse(Vector2(0, 5), 10.5 * flick, 13.0, ca(SKIN_HI, 0.65 * minf(boost, 1.6) / 1.6 + 0.2), 0.0, 18)
		for xf in [-0.62, -0.2, 0.2, 0.62]:
			var rib := PackedVector2Array()
			for j in 9:
				var y := lerpf(-19.0, 19.5, float(j) / 8.0)
				var sq := sqrt(maxf(0.0, 1.0 - pow(y / 22.5, 2.0)))
				rib.append(Vector2(float(xf) * _rx(y) * sq, y))
			draw_polyline(rib, ca(RIB, 0.75), 1.3, true)
		ellipse_line(self, Vector2(0, -19.5), 11.5, 2.6, INK, 1.8, 0.0, 20)
		poly_ellipse(Vector2(0, 20.5), 8.0, 2.2, Color("#7A2E05"), 0.0, 16)
		ellipse_line(self, Vector2(0, 20.5), 8.5, 2.3, INK, 1.8, 0.0, 18)
		var fy := 23.5 + 0.6 * sin(t * 13.0)
		draw_colored_polygon(PackedVector2Array([Vector2(-2.2, 21.5), Vector2(0, fy + 2.5), Vector2(2.2, 21.5), Vector2(0, 19.8)]), FLAME)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_glow() -> void:
		if alpha <= 0.0:
			return
		var xf := Transform2D(rot, pos)
		var g := s * SZ
		glow(pos, 70.0 * g, ca(HALO, 0.26 * flick * boost))
		glow(xf * (Vector2(0, 6) * g), 22.0 * g, ca(LIGHT, minf(0.75 * flick * boost, 1.0)))
		glow(xf * (Vector2(0, 22) * g), 8.0 * g, ca(FLAME, 0.9 * flick))

	# Liegt p auf dem Band der Richtungs-Plattform (dort verdeckt sie den Lampion, der dahinter aufsteigt)?
	func _on_band(p: Vector2) -> bool:
		var C := center()
		var radii: Vector2 = ctx.get("ring_radii", Vector2(330, 160))
		var deg := rad_to_deg(atan2((p.y - C.y) / maxf(radii.y, 1.0), (p.x - C.x) / maxf(radii.x, 1.0)))
		var din := band(deg, 0.0).distance_to(C)
		var dout := band(deg, 1.0).distance_to(C)
		var d := p.distance_to(C)
		return d > din - 14.0 * s and d < dout + 14.0 * s
