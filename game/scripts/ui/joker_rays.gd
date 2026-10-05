class_name JokerRays
extends Node2D
# Joker-Strahlen aus der sichtbaren Kontur (06 Abschnitt 4.3, Verfahren A), wiederverwendbar für Hand und Ablage:
#   JokerRays.attach(card, above)   card = CardView des Jokers, above = Karten, die darüber liegen (verdecken die Kontur)
# 1. Einmal je Kartenbreite: Umriss als abgerundetes Rechteck abtasten, Normalen analytisch (Kanten senkrecht, Ecken radial).
# 2. Je Bild: Proben in globale Koordinaten, gegen die Umrisse der höheren Karten prüfen (Geometry2D.is_point_in_polygon);
#    verdeckte Proben fallen weg.
# 3. Übrige Proben speisen CPUParticles2D (EMISSION_SHAPE_DIRECTED_POINTS) mit Farbe je Quadrant in den vier Farben der Seite;
#    die Zuordnung dreht sich langsam. Nacht: längere Strahlen, sanftes Flackern ≤ 3 Hz.
# 4. target_dir ≠ 0 (Tisch): Strahlen neigen sich zum Zielspieler.
# 5. Der Knoten ist erstes Kind der Karte: Er liegt unter der Karte, aber über tieferen Karten.

const SAMPLE_STEP := 9.0          # px zwischen zwei Konturproben (120 px breite Karte ≈ 70 Proben)
const CORNER := 40.0 / 560.0      # Eckradius relativ zur Breite (Kartenentwurf viewBox 560×870, r 40)
const JOKERS := ["hell_wuenscher", "hell_wuenscher_plus2", "dunkel_wuenscher", "dunkel_farbjagd"]

var card: CardView
var above: Array = []
var side := "hell"
var target_dir := Vector2.ZERO
var reduced := false
var visible_count := 0            # sichtbare Proben (Tests)

var _particles: CPUParticles2D
var _samples: Array = []          # [{pos, normal}] in Kartenkoordinaten
var _sample_w := -1.0
var _time := 0.0
var _color_clock := 0.0
var _visible_idx := PackedInt32Array()

static var _streak: Texture2D


static func is_joker(key: String) -> bool:
	return JOKERS.has(key)


static func attach(target: CardView, cards_above: Array = [], active_side := "") -> JokerRays:
	var r := JokerRays.new()
	r.card = target
	r.above = cards_above
	r.side = active_side if active_side != "" else ("dunkel" if target.current_key().begins_with("dunkel") else "hell")
	r.reduced = UiApp.reduced_effects()
	target.add_child(r)
	target.move_child(r, 0)
	return r


# Löst vorhandene Strahlen von einer Karte
static func detach(target: CardView) -> void:
	for c in target.get_children():
		if c is JokerRays:
			c.queue_free()


# Umriss des abgerundeten Rechtecks (Ursprung Mitte) mit analytischen Normalen
static func outline_samples(size: Vector2, radius: float, step := SAMPLE_STEP) -> Array:
	var out: Array = []
	var h := size * 0.5
	var r := minf(radius, minf(h.x, h.y))
	var straight_x := size.x - 2.0 * r
	var straight_y := size.y - 2.0 * r
	var arc_len := PI * 0.5 * r
	# Kanten: oben, rechts, unten, links; Ecken dazwischen
	var corners := [Vector2(h.x - r, -h.y + r), Vector2(h.x - r, h.y - r), Vector2(-h.x + r, h.y - r), Vector2(-h.x + r, -h.y + r)]
	var edges := [
		[Vector2(-h.x + r, -h.y), Vector2(1, 0), straight_x, Vector2(0, -1)],
		[Vector2(h.x, -h.y + r), Vector2(0, 1), straight_y, Vector2(1, 0)],
		[Vector2(h.x - r, h.y), Vector2(-1, 0), straight_x, Vector2(0, 1)],
		[Vector2(-h.x, h.y - r), Vector2(0, -1), straight_y, Vector2(-1, 0)],
	]
	var start_angles := [-PI * 0.5, 0.0, PI * 0.5, PI]
	for e in 4:
		var edge: Array = edges[e]
		var n := maxi(1, int(round(float(edge[2]) / step)))
		for i in n:
			var p: Vector2 = edge[0] + edge[1] * (float(edge[2]) * (float(i) + 0.5) / n)
			out.append({"pos": p, "normal": edge[3]})
		var m := maxi(1, int(round(arc_len / step)))
		for i in m:
			var a: float = start_angles[e] + PI * 0.5 * (float(i) + 0.5) / m
			var nrm := Vector2(cos(a), sin(a))
			out.append({"pos": corners[e] + nrm * r, "normal": nrm})
	return out


# Sichtbare Proben: [Punkte, Normalen (PackedVector2Array, Kartenkoordinaten), Indizes (PackedInt32Array)]
static func visible_samples(card_xf: Transform2D, samples: Array, covers: Array) -> Array:
	var pts := PackedVector2Array()
	var nrm := PackedVector2Array()
	var idx := PackedInt32Array()
	for si in samples.size():
		var s: Dictionary = samples[si]
		var p: Vector2 = card_xf * (s["pos"] as Vector2)
		var covered := false
		for poly in covers:
			if Geometry2D.is_point_in_polygon(p, poly):
				covered = true
				break
		if not covered:
			pts.append(s["pos"])
			nrm.append(s["normal"])
			idx.append(si)
	return [pts, nrm, idx]


static func streak_texture() -> Texture2D:
	if _streak == null:
		var w := 16
		var h := 64
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			var v := float(y) / (h - 1)
			var along := pow(sin(PI * v), 0.8) * (1.0 - 0.5 * v)
			for x in w:
				var u := absf((float(x) + 0.5) / w * 2.0 - 1.0)
				var across := clampf(1.0 - u * u, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, along * across * across))
		_streak = ImageTexture.create_from_image(img)
	return _streak


func _ready() -> void:
	var night := side == "dunkel"
	# Nacht: additiv (Leuchten), Tag: normal gemischt, sonst verschwinden helle Strahlen auf Papier
	material = TableEffects.additive() if night else null
	_particles = CPUParticles2D.new()
	_particles.texture = streak_texture()
	_particles.material = TableEffects.additive() if night else null
	_particles.local_coords = true
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_DIRECTED_POINTS
	_particles.particle_flag_align_y = true
	_particles.direction = Vector2(1, 0)
	_particles.spread = 6.0
	_particles.gravity = Vector2.ZERO
	var scale_w := (card.width if card else 120.0) / 120.0
	_particles.amount = 18 if reduced else (56 if night else 44)
	_particles.lifetime = (0.9 if night else 0.65)
	_particles.preprocess = _particles.lifetime
	_particles.initial_velocity_min = (60.0 if night else 45.0) * scale_w
	_particles.initial_velocity_max = (130.0 if night else 95.0) * scale_w
	_particles.damping_min = 30.0
	_particles.damping_max = 60.0
	_particles.scale_amount_min = 0.6 * scale_w
	_particles.scale_amount_max = (1.25 if night else 1.0) * scale_w
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.5))
	sc.add_point(Vector2(1.0, 1.4))
	_particles.scale_amount_curve = sc
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.18, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.0)])
	_particles.color_ramp = ramp
	add_child(_particles)
	_update(true)


func _process(delta: float) -> void:
	_time += delta
	_color_clock += delta
	_update(_color_clock > 0.1)
	if side == "dunkel" and not reduced:
		modulate.a = 0.85 + 0.15 * sin(TAU * 2.5 * _time)   # sanftes Flackern 2,5 Hz (≤ 3 Hz)


# Farbe an einer Stelle der Kontur: vier Farben der Seite je Viertel, weich ineinander, langsam drehend
func color_at(p: Vector2) -> Color:
	var palette: Array[String] = UiPalette.colors_of(side)
	var a := fposmod(p.angle() + PI * 0.75 + _time * 0.5, TAU) / (TAU / 4.0)
	var q := int(a) % 4
	var f := smoothstep(0.7, 1.0, a - floor(a))
	return UiPalette.glow(palette[q]).lerp(UiPalette.glow(palette[(q + 1) % 4]), f)


func _update(colors_too: bool) -> void:
	if card == null or _particles == null:
		return
	if not is_equal_approx(_sample_w, card.width):
		_sample_w = card.width
		var sz := card.card_size()
		_samples = outline_samples(sz, sz.x * CORNER, SAMPLE_STEP * clampf(sz.x / 120.0, 0.6, 1.6))
	var covers: Array = []
	var my_rect := _rect_of(card.global_polygon())
	for c in above:
		if c == null or not is_instance_valid(c) or not (c is CardView) or not (c as CardView).is_visible_in_tree():
			continue
		var poly: PackedVector2Array = (c as CardView).global_polygon()
		if _rect_of(poly).intersects(my_rect):
			covers.append(poly)
	var vis := visible_samples(card.global_transform, _samples, covers)
	var pts: PackedVector2Array = vis[0]
	var nrm: PackedVector2Array = vis[1]
	var idx: PackedInt32Array = vis[2]
	var changed := pts.size() != visible_count or idx != _visible_idx
	visible_count = pts.size()
	_visible_idx = idx
	_particles.emitting = visible_count > 0
	if visible_count == 0:
		if changed:
			queue_redraw()
		return
	if target_dir != Vector2.ZERO:
		var local_target := target_dir.rotated(-card.global_rotation).normalized()
		for i in nrm.size():
			nrm[i] = nrm[i].lerp(local_target, 0.45).normalized()
	_particles.emission_points = pts
	_particles.emission_normals = nrm
	if colors_too or changed or _particles.emission_colors.size() != pts.size():
		_color_clock = 0.0
		var cols := PackedColorArray()
		for p in pts:
			cols.append(color_at(p))
		_particles.emission_colors = cols
		queue_redraw()


# Leuchtsaum entlang der sichtbaren Konturstücke (zusammenhängende Läufe der Proben, ringförmig)
func _draw() -> void:
	if _visible_idx.is_empty() or _samples.is_empty():
		return
	var n := _samples.size()
	var vis := {}
	for i in _visible_idx:
		vis[i] = true
	var start := 0
	if vis.size() < n:
		while vis.has(start):
			start = (start + 1) % n       # Lauf beginnt nach einer Lücke
	var run_pts := PackedVector2Array()
	var run_cols := PackedColorArray()
	var strength := 0.55 if side == "dunkel" else 0.45
	for k in n + 1:
		var i := (start + k) % n
		if vis.has(i) and k < n:
			var s: Dictionary = _samples[i]
			var p: Vector2 = s["pos"]
			run_pts.append(p + (s["normal"] as Vector2) * 3.0)
			run_cols.append(color_at(p))
		if (not vis.has(i) or k == n) and run_pts.size() >= 2:
			if vis.size() == n:
				run_pts.append(run_pts[0])
				run_cols.append(run_cols[0])
			var soft := PackedColorArray()
			var core := PackedColorArray()
			for c in run_cols:
				soft.append(Color(c, strength * 0.35))
				core.append(Color(c, strength))
			draw_polyline_colors(run_pts, soft, 12.0 * clampf(card.width / 120.0, 0.6, 1.5), true)
			draw_polyline_colors(run_pts, core, 4.0 * clampf(card.width / 120.0, 0.6, 1.5), true)
		if not vis.has(i):
			run_pts = PackedVector2Array()
			run_cols = PackedColorArray()


static func _rect_of(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r
