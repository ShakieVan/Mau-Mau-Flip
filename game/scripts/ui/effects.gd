class_name TableEffects
extends Node2D
# Einmalige Effekte über dem Tisch (06 Abschnitt 4.2): Kartenflüge im Bogen, Papierstaub und Neonfunken, Stempel („+5“,
# „Strafe“), aufsteigende Texte (Zzz, „Nochmal du!“), Farb- und Schockwellen, Komet, Mau-Sprechblase, Konfetti, Sonnenstrahlen.
# Alle Knoten räumen sich selbst ab. reduced = Effektstufe „reduziert“: weniger Teilchen, keine Schockwellen.
# Glühen über additive Verlaufstexturen (Compatibility-Renderer, kein 2D-HDR). Koordinaten = Koordinaten des Elternknotens.

var reduced := false
var night := 0.0

static var _glow_tex: Texture2D
static var _dot_tex: Texture2D
static var _rect_tex: Texture2D


func factor() -> float:
	return 0.35 if reduced else 1.0


static func glow_texture() -> Texture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_glow_tex = t
	return _glow_tex


static func dot_texture() -> Texture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 16
		t.height = 16
		_dot_tex = t
	return _dot_tex


static func rect_texture() -> Texture2D:
	if _rect_tex == null:
		var img := Image.create(6, 10, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_rect_tex = ImageTexture.create_from_image(img)
	return _rect_tex


static func additive() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


# ---------------------------------------------------------------- Kartenflug

# Karte fliegt im Bogen von a nach b. opts: flip_to (Schlüssel nach der Wende in der Flugmitte), arc (Bogenhöhe, Standard
# 18 % der Strecke), delay, on_land (Callable), spin (zusätzliche Drehung), keep (nicht freigeben, Aufrufer übernimmt)
func fly_card(key: String, from_pos: Vector2, from_rot: float, from_w: float, to_pos: Vector2, to_rot: float, to_w: float, dur: float, opts := {}) -> CardView:
	var c := CardView.new()
	add_child(c)
	var flip_to := str(opts.get("flip_to", ""))
	c.setup(-1, key, flip_to, true)
	c.width = from_w
	c.position = from_pos
	c.rotation = from_rot
	var delay := float(opts.get("delay", 0.0))
	c.visible = delay <= 0.0
	var dist := from_pos.distance_to(to_pos)
	var arc := float(opts.get("arc", clampf(dist * 0.18, 20.0, 140.0)))
	var mid := (from_pos + to_pos) * 0.5
	var perp := (to_pos - from_pos).orthogonal().normalized()
	if perp.y > 0.0:
		perp = -perp                       # Bogen immer nach oben
	var ctrl := mid + perp * arc
	var spin := float(opts.get("spin", 0.0))
	var tw := c.create_tween()     # am Kartenknoten: wird die Karte entfernt (Überspringen), endet auch der Flug
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(func() -> void: c.visible = true)
	tw.tween_method(func(t: float) -> void:
		var u := 1.0 - t
		c.position = u * u * from_pos + 2.0 * u * t * ctrl + t * t * to_pos
		c.rotation = lerp_angle(from_rot, to_rot, t) + spin * t
		c.width = lerpf(from_w, to_w, t), 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if flip_to != "":
		c.flip(dur * 0.42, delay + dur * 0.22)
	var on_land: Callable = opts.get("on_land", Callable())
	var keep := bool(opts.get("keep", false))
	tw.tween_callback(func() -> void:
		if on_land.is_valid():
			on_land.call()
		if not keep:
			c.queue_free())
	return c


# ---------------------------------------------------------------- Teilchen

func _one_shot(p: CPUParticles2D, life: float) -> void:
	add_child(p)
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(life + 0.3)
	tw.tween_callback(p.queue_free)


# Papierstaub (hell) bzw. Neonfunken (dunkel) beim Landen einer Karte
func land_burst(pos: Vector2, color: Color, neon: bool, radius := 60.0) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = maxi(4, int((18 if neon else 14) * factor()))
	p.lifetime = 0.55 if neon else 0.7
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
	p.emission_sphere_radius = radius
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 60.0 if neon else 30.0
	p.initial_velocity_max = 170.0 if neon else 90.0
	p.gravity = Vector2(0, 0) if neon else Vector2(0, 260)
	p.damping_min = 80.0
	p.damping_max = 140.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color, 1.0))
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	if neon:
		p.texture = dot_texture()
		p.material = additive()
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.2
	else:
		p.texture = rect_texture()
		p.scale_amount_min = 0.5
		p.scale_amount_max = 1.0
		p.angular_velocity_min = -360.0
		p.angular_velocity_max = 360.0
		p.angle_min = 0.0
		p.angle_max = 360.0
	_one_shot(p, p.lifetime)


# Konfetti in den Tagfarben (oder Nachtfarben) über die Breite von area
func confetti(area: Rect2, colors: Array, amount := 220) -> void:
	var p := CPUParticles2D.new()
	p.position = Vector2(area.get_center().x, area.position.y - 10.0)
	p.one_shot = true
	p.explosiveness = 0.75
	p.amount = maxi(12, int(amount * factor()))
	p.lifetime = 2.6
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(area.size.x * 0.5, 8.0)
	p.direction = Vector2(0, 1)
	p.spread = 30.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 240.0
	p.gravity = Vector2(0, 320)
	p.damping_min = 20.0
	p.damping_max = 60.0
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.0
	p.texture = rect_texture()
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offs.append(float(i) / colors.size())
		cols.append(colors[i])
	g.offsets = offs
	g.colors = cols
	p.color_initial_ramp = g
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.8, 1.0])
	fade.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	p.color_ramp = fade
	_one_shot(p, p.lifetime)


# Kurzes additives Aufleuchten (Neon zündet, Treffer)
func glow_flash(pos: Vector2, radius: float, color: Color, dur := 0.5, peak := 0.9) -> void:
	var s := Sprite2D.new()
	s.texture = glow_texture()
	s.material = additive()
	s.position = pos
	s.scale = Vector2.ONE * radius / 64.0
	s.modulate = Color(color, 0.0)
	add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", peak, dur * 0.3)
	tw.tween_property(s, "modulate:a", 0.0, dur * 0.7)
	tw.tween_callback(s.queue_free)


# ---------------------------------------------------------------- Texte, Stempel, Blasen

class TextFx:
	extends Node2D
	var text := ""
	var font: Font
	var font_size := 40
	var color := Color.WHITE
	var outline := Color(0, 0, 0, 0)
	var outline_w := 0
	var box := Color(0, 0, 0, 0)     # Stempelrahmen
	var box_w := 0.0

	func _draw() -> void:
		var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var pos := Vector2(-sz.x * 0.5, font_size * 0.34)
		if box.a > 0.0:
			var r := Rect2(-sz.x * 0.5 - 20.0, -font_size * 0.74, sz.x + 40.0, font_size * 1.42)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0, 0, 0, 0)
			sb.draw_center = false
			sb.border_color = box
			sb.set_border_width_all(int(box_w))
			sb.set_corner_radius_all(int(font_size * 0.28))
			sb.anti_aliasing = true
			draw_style_box(sb, r)
		if outline_w > 0:
			draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_w, outline)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _text(pos: Vector2, text: String, font: Font, size: int, color: Color, outline: Color, outline_w: int) -> TextFx:
	var t := TextFx.new()
	t.text = text
	t.font = font
	t.font_size = size
	t.color = color
	t.outline = outline
	t.outline_w = outline_w
	t.position = pos
	add_child(t)
	return t


# Aufsteigender Text mit Plopp (TRANS_BACK), dann ausblenden
func float_text(pos: Vector2, text: String, size := 44, color := UiPalette.CREAM, dur := 1.1, rise := 50.0, font: Font = null) -> TextFx:
	var f := font if font != null else UiFonts.title(900, true, 100.0)
	var t := _text(pos, text, f, size, color, Color(UiPalette.INK, 0.9), maxi(4, size / 7))
	t.scale = Vector2.ONE * 0.4
	var tw := t.create_tween()
	tw.tween_property(t, "scale", Vector2.ONE, minf(0.25, dur * 0.3)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(t, "position:y", pos.y - rise, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(t, "modulate:a", 0.0, dur * 0.35).set_delay(dur * 0.65)
	tw.tween_callback(t.queue_free)
	return t


# Stempel: groß aufgesetzt, leicht schräg, mit Rahmen; bleibt kurz stehen
func stamp(pos: Vector2, text: String, color: Color, size := 52, hold := 0.7, rot := -0.14) -> TextFx:
	var t := _text(pos, text, UiFonts.title(900, false, 0.0, 72.0), size, color, Color(UiPalette.CREAM, 0.95), maxi(5, size / 6))
	t.box = color
	t.box_w = maxf(4.0, size / 11.0)
	t.rotation = rot
	t.scale = Vector2.ONE * 2.2
	t.modulate.a = 0.0
	var tw := t.create_tween()
	tw.tween_property(t, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(t, "modulate:a", 1.0, 0.1)
	tw.tween_interval(hold)
	tw.tween_property(t, "modulate:a", 0.0, 0.3)
	tw.tween_callback(t.queue_free)
	return t


# Zzz: drei Buchstaben steigen versetzt auf
func zzz(pos: Vector2, dur := 1.0) -> void:
	var f := UiFonts.title(800, true, 100.0)
	for i in 3:
		var t := _text(pos + Vector2(i * 14.0 - 10.0, -i * 6.0), "z" if i < 2 else "Z", f, 26 + i * 8, UiPalette.MOON, Color(UiPalette.INK, 0.85), 5)
		t.modulate.a = 0.0
		var tw := t.create_tween()
		tw.tween_interval(i * dur * 0.15)
		tw.tween_property(t, "modulate:a", 1.0, 0.12)
		tw.parallel().tween_property(t, "position", t.position + Vector2(18.0 + i * 6.0, -46.0 - i * 10.0), dur * 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(t, "modulate:a", 0.0, dur * 0.2)
		tw.tween_callback(t.queue_free)


class BubbleFx:
	extends Node2D
	# Sprechblase mit Katzenohren
	var text := "Mau!"
	var fill := UiPalette.CREAM
	var ink := UiPalette.INK
	var tail_dir := Vector2(0, 1)

	func _draw() -> void:
		var f := UiFonts.mau()
		var fs := 40
		var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var w := sz.x + 44.0
		var h := 64.0
		var r := Rect2(-w * 0.5, -h * 0.5, w, h)
		# Ohren
		for side in [-1.0, 1.0]:
			var ex: float = side * w * 0.28
			var ear := PackedVector2Array([Vector2(ex - 16.0, -h * 0.5 + 6.0), Vector2(ex + side * 4.0, -h * 0.5 - 24.0), Vector2(ex + 16.0, -h * 0.5 + 6.0)])
			draw_colored_polygon(ear, ink)
			var inner := PackedVector2Array([ear[0] + Vector2(6, 2), ear[1] + Vector2(0, 9), ear[2] + Vector2(-6, 2)])
			draw_colored_polygon(inner, fill)
		# Schwanz der Blase
		var base := tail_dir.normalized()
		var tip := base * (h * 0.5 + 22.0)
		var side_v := Vector2(-base.y, base.x) * 13.0
		var tail := PackedVector2Array([base * (h * 0.5 - 6.0) + side_v, tip, base * (h * 0.5 - 6.0) - side_v])
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill
		sb.border_color = ink
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(30)
		sb.anti_aliasing = true
		draw_colored_polygon(tail, ink)
		draw_style_box(sb, r)
		draw_colored_polygon(PackedVector2Array([tail[0] * 0.92, tail[1] * 0.84, tail[2] * 0.92]), fill)
		draw_string(f, Vector2(-sz.x * 0.5, fs * 0.34), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)


func bubble(pos: Vector2, text := "Mau!", hold := 1.0, tail_dir := Vector2(0, 1)) -> BubbleFx:
	var b := BubbleFx.new()
	b.text = text
	b.tail_dir = tail_dir
	b.position = pos
	b.scale = Vector2.ONE * 0.2
	add_child(b)
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(hold)
	tw.tween_property(b, "modulate:a", 0.0, 0.25)
	tw.tween_callback(b.queue_free)
	return b


# ---------------------------------------------------------------- Wellen, Komet, Strahlen

class RingFx:
	extends Node2D
	var radius := 10.0
	var width := 8.0
	var color := Color.WHITE
	var squash := 1.0         # Ellipse (Tischperspektive)

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, squash))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, Color(color, color.a * 0.35), width * 2.4, true)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, color, width, true)


# Farbwelle (Wünscher) bzw. Schockwelle (+5): Ring läuft nach außen und verblasst
func ring_wave(pos: Vector2, color: Color, from_r: float, to_r: float, dur: float, width := 10.0, squash := 1.0) -> void:
	var r := RingFx.new()
	r.position = pos
	r.color = color
	r.width = width
	r.radius = from_r
	r.squash = squash
	r.material = additive() if night > 0.5 else null
	add_child(r)
	var tw := r.create_tween()
	tw.tween_method(func(v: float) -> void:
		r.radius = v
		r.queue_redraw(), from_r, to_r, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(r, "modulate:a", 0.0, dur * 0.6).set_delay(dur * 0.4)
	tw.tween_callback(r.queue_free)


# Komet über eine Punktfolge (Alle aussetzen). on_point(i) kommt beim Passieren von Punkt i bzw. Marke i.
func comet(points: PackedVector2Array, dur: float, color: Color, on_point: Callable = Callable(), marks := PackedInt32Array()) -> void:
	if points.size() < 2:
		return
	var head := Sprite2D.new()
	head.texture = glow_texture()
	head.material = additive()
	head.modulate = color
	head.scale = Vector2.ONE * 0.75
	head.position = points[0]
	var core := Sprite2D.new()
	core.texture = glow_texture()
	core.material = additive()
	core.scale = Vector2.ONE * 0.28
	core.modulate = Color(1, 1, 1, 0.95)
	head.add_child(core)
	core.scale = Vector2.ONE * 0.37
	var tail := Line2D.new()
	tail.width = 16.0
	tail.default_color = color
	tail.material = additive()
	tail.joint_mode = Line2D.LINE_JOINT_ROUND
	tail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	var wc := Curve.new()
	wc.add_point(Vector2(0, 0))
	wc.add_point(Vector2(1, 1))
	tail.width_curve = wc
	var g := Gradient.new()
	g.set_color(0, Color(color, 0.0))
	g.set_color(1, Color(color, 0.85))
	tail.gradient = g
	add_child(tail)
	add_child(head)
	var lengths := PackedFloat32Array([0.0])
	for i in range(1, points.size()):
		lengths.append(lengths[i - 1] + points[i].distance_to(points[i - 1]))
	var total := lengths[lengths.size() - 1]
	var passed := [0]
	var trail: Array[Vector2] = []
	var tw := head.create_tween()
	tw.tween_method(func(t: float) -> void:
		var d := t * total
		var j := 1
		while j < lengths.size() - 1 and lengths[j] < d:
			j += 1
		var u := (d - lengths[j - 1]) / maxf(lengths[j] - lengths[j - 1], 0.001)
		head.position = points[j - 1].lerp(points[j], clampf(u, 0.0, 1.0))
		trail.append(head.position)
		if trail.size() > 26:
			trail.pop_front()
		tail.points = PackedVector2Array(trail)
		# Marken: Indizes in points, bei deren Passieren on_point(Markennummer) kommt (ohne Marken: jeder Punkt)
		var count := marks.size() if not marks.is_empty() else points.size()
		while passed[0] < count:
			var pi_idx: int = marks[passed[0]] if not marks.is_empty() else passed[0]
			if lengths[pi_idx] > d + 0.5:
				break
			if on_point.is_valid():
				on_point.call(passed[0])
			passed[0] += 1, 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(head, "modulate:a", 0.0, 0.2)
	tw.parallel().tween_property(tail, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func() -> void:
		head.queue_free()
		tail.queue_free())


class RaysFx:
	extends Node2D
	var color := Color(1, 0.85, 0.3, 0.35)
	var radius := 220.0
	var count := 14

	func _process(delta: float) -> void:
		rotation += delta * 0.35

	func _draw() -> void:
		for i in count:
			var a := TAU * i / count
			var w := TAU / count * 0.28
			draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2.from_angle(a - w) * radius, Vector2.from_angle(a + w) * radius]),
				color)


# Sonnenstrahlen hinter dem Gewinner (bleiben, bis free_rays oder clear)
func sun_rays(pos: Vector2, radius: float, color: Color) -> RaysFx:
	var r := RaysFx.new()
	r.position = pos
	r.radius = radius
	r.color = color
	r.modulate.a = 0.0
	r.material = additive()
	add_child(r)
	move_child(r, 0)
	create_tween().tween_property(r, "modulate:a", 1.0, 0.4)
	return r


# Laufende Effekte entfernen (Abgleich auf die Sicht, Überspringen)
func clear() -> void:
	for c in get_children():
		c.queue_free()
