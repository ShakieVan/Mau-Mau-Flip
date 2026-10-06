class_name TableEffects
extends Node2D
# Einmalige Effekte über dem Tisch (06 Abschnitt 4.2): Kartenflüge im Bogen, Papierstaub und Neonfunken, Stempel („+5“,
# „Strafe“), aufsteigende Texte (Zzz, „Nochmal du!“), Farb- und Schockwellen, Komet, animierte Mau-Sprechblasen (mehrere Varianten,
# MauBubbleFx), Konfetti, Sonnenstrahlen.
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
# 18 % der Strecke), delay, on_land (Callable), spin (zusätzliche Drehung), keep (nicht freigeben, Aufrufer übernimmt),
# bow_to (Punkt: der Bogen wölbt sich zu ihm hin, z. B. zur Tischmitte; sonst immer nach oben), parent (anderer Elternknoten,
# Koordinaten dann in dessen System) und below (Geschwisterknoten in parent, unter dem die Karte fliegt, z. B. die oberste Ablagekarte)
func fly_card(key: String, from_pos: Vector2, from_rot: float, from_w: float, to_pos: Vector2, to_rot: float, to_w: float, dur: float, opts := {}) -> CardView:
	var c := CardView.new()
	var parent: Node = opts.get("parent", self)
	if parent == null or not is_instance_valid(parent):
		parent = self
	parent.add_child(c)
	var below: Variant = opts.get("below", null)
	if below is Node and is_instance_valid(below) and (below as Node).get_parent() == parent:
		parent.move_child(c, (below as Node).get_index())
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
	var bow: Variant = opts.get("bow_to", null)
	if bow is Vector2:
		if perp.dot((bow as Vector2) - mid) < 0.0:
			perp = -perp                   # Bogen zum Punkt hin (über den Tisch)
	elif perp.y > 0.0:
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


# ---------------------------------------------------------------- Mau-Sprechblasen (AGENTS.md Nr. 21)
# Beim Rufenden erscheint eine witzig animierte Blase „Mau!“, je Ruf in einer zufälligen Variante (Zufall nur für die Darstellung):
#   plopp    ploppt mit Überschwinger auf, wackelt nach, Plopp-Striche
#   ohren    Katzenohren springen hoch und zucken, Schnurrhaare, kleine Funkelsterne
#   huepfen  die Buchstaben M-a-u-! hüpfen einzeln hinein, dann läuft eine kleine Welle durch
#   pfote    die Blase fliegt aus dem Avatar heraus und dreht sich ein, Pfotenabdrücke auf dem Weg, ein Herzchen
#   wellen   Schallwellen vom Rufenden, die Blase schwingt wie ein Ballon nach
#   neon     (nur nachts) dunkle Blase mit Neonröhre, die einmal aufglimmt
#   schlicht Effektstufe „reduziert“: kurz einblenden, stehen, ausblenden
# „Mau-Mau!“ (fertig): maumau = zwei Blasen „Mau-“ „Mau!“ im Takt der Aufnahme plus Konfetti bzw. Neonfunken; maumau_schlicht reduziert.
# Tag: Papier und Druckfarbe; Nacht: Papierblase mit rosa Neonkranz (wie der Mau-Knopf) bzw. die Neon-Variante. Kein Blinken.

const MAU_VARIANTS: Array[String] = ["plopp", "ohren", "huepfen", "pfote", "wellen", "neon"]
const MAU_NIGHT_ONLY: Array[String] = ["neon"]
const MAU_ALL: Array[String] = ["plopp", "ohren", "huepfen", "pfote", "wellen", "neon", "schlicht", "maumau", "maumau_schlicht"]
const NEON_PINK := Color("#FF7FCF")


# Varianten, aus denen gelost wird (nachts zusätzlich „neon“)
static func mau_variants(at_night: bool) -> Array[String]:
	var out: Array[String] = []
	for v in MAU_VARIANTS:
		if at_night or not MAU_NIGHT_ONLY.has(v):
			out.append(v)
	return out


# Blase „Mau!“ bzw. „Mau-Mau!“ (variant aus MAU_ALL). pos = Mitte der (ersten) Blase in Koordinaten dieses Knotens.
# opts: speaker (Punkt des Rufenden relativ zu pos), tail (Richtung, falls kein speaker), k (Größe), accent (Avatarfarbe),
# night, seed, duration, text
func mau_bubble(pos: Vector2, variant: String, opts := {}) -> MauBubbleFx:
	var b := MauBubbleFx.new()
	b.variant = variant if MAU_ALL.has(variant) else "plopp"
	b.night = float(opts.get("night", night))
	b.k = float(opts.get("k", 1.0))
	b.seed_v = int(opts.get("seed", 1))
	if opts.has("accent"):
		b.accent = opts["accent"]
	if opts.has("speaker"):
		b.speaker = opts["speaker"]
	if opts.has("tail"):
		b.tail = (opts["tail"] as Vector2).normalized()
	if opts.has("duration"):
		b.duration = float(opts["duration"])
	if opts.has("text"):
		b.text = str(opts["text"])
	b.position = pos
	add_child(b)
	return b


# Ältere Schnittstelle (Kontrollbilder F1b): schlichte Blase, die hold Sekunden steht
func bubble(pos: Vector2, text := "Mau!", hold := 1.0, tail_dir := Vector2(0, 1)) -> MauBubbleFx:
	return mau_bubble(pos, "schlicht", {"tail": tail_dir, "duration": hold + 0.45, "text": text})


class MauBubbleFx:
	extends Node2D
	# Animierte Sprechblase. Der Ablauf hängt nur von age (Sekunden) ab: auto = selbst fortschreiben und am Ende freigeben;
	# auto = false: age von außen setzen (set_age), z. B. für Kontrollbilder. Ursprung = Mitte der ersten Blase.
	# speaker = Punkt des Rufenden (lokal); die Schwänze zeigen dorthin. Ohne speaker gilt tail als Richtung.

	var variant := "plopp"
	var text := "Mau!"
	var tail := Vector2(0, 1)
	var speaker := Vector2.INF
	var speaker_r := 27.0                  # Radius des Avatars bzw. Knopfs am Rufenden (Schallwellen, Pfoten)
	var night := 0.0
	var k := 1.0
	var accent := Color("#FF99CC")
	var seed_v := 1
	var age := 0.0
	var duration := -1.0                   # -1 = Standard der Variante (total())
	var auto := true

	var _bodies: Array[Dictionary] = []    # {text, fs, tw, size, at, t0, tip, dir, shape, closed}
	var _built := false
	var _font: Font
	var _bits: Array[Dictionary] = []      # Konfetti/Funken (fest ausgelost)

	const INK := Color("#211B2C")
	const CREAM := Color("#FFF7E8")
	const NEON := Color("#FF7FCF")
	const NEON_CORE := Color("#FFE3F4")
	const EAR_PINK := Color("#FF9ECF")
	const STAR := Color("#FFD65A")
	const HEART := Color("#FF5FA8")
	const SE_N := 3.0                      # Superellipse: weich gerundetes Rechteck

	func _ready() -> void:
		if not _built:
			build()
		set_age(age)

	func _process(delta: float) -> void:
		if not auto:
			return
		set_age(age + delta)
		if age >= total():
			queue_free()

	func total() -> float:
		if duration > 0.0:
			return duration
		match variant:
			"maumau":
				return 1.9
			"maumau_schlicht":
				return 1.5
			"schlicht":
				return 1.3
		return 1.6

	func is_big() -> bool:
		return variant.begins_with("maumau")

	func set_age(v: float) -> void:
		age = maxf(v, 0.0)
		var fade_out := clampf((total() - age) / 0.25, 0.0, 1.0)
		var fade_in := 1.0
		if variant == "schlicht" or variant == "maumau_schlicht":
			fade_in = clampf(age / 0.12, 0.0, 1.0)
		modulate.a = minf(fade_in, fade_out)
		queue_redraw()

	# --- Aufbau

	func _layout() -> void:
		if _font == null:
			_font = UiFonts.mau()
		_bodies.clear()
		var fs := 42.0 * k
		if is_big():
			var a := _make_body("Mau-", fs * 0.92, 0.0)
			var b := _make_body("Mau!", fs * 1.16, 0.30)
			var sa: Vector2 = a["size"]
			var sb: Vector2 = b["size"]
			a["at"] = Vector2.ZERO
			b["at"] = Vector2(sa.x * 0.40 + sb.x * 0.42, -sa.y * 0.42)
			_bodies.append(a)
			_bodies.append(b)
		else:
			_bodies.append(_make_body(text, fs, 0.0))

	func _make_body(t: String, fs: float, t0: float) -> Dictionary:
		var ts := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs))
		return {"text": t, "fs": int(fs), "tw": ts.x, "size": Vector2(ts.x + fs * 1.2, fs * 1.55), "at": Vector2.ZERO, "t0": t0}

	# Rechteck aller Blasen (lokal) mit Rand für Ohren, hüpfende Buchstaben und Wackeln; ohne Schwanz
	func extent() -> Rect2:
		if _bodies.is_empty():
			_layout()
		var r := Rect2()
		for i in _bodies.size():
			var b: Dictionary = _bodies[i]
			var sz: Vector2 = b["size"]
			var br := Rect2(Vector2(b["at"]) - sz * 0.5, sz)
			r = br if i == 0 else r.merge(br)
		return r.grow_individual(8.0 * k, 26.0 * k, 8.0 * k, 4.0 * k)

	func build() -> void:
		_layout()
		var sp := speaker
		if not sp.is_finite():
			var b0: Dictionary = _bodies[0]
			sp = Vector2(b0["at"]) + tail * (_edge(b0["size"], tail) + 46.0 * k)
		for b in _bodies:
			_shape_for(b, sp)
		_bits.clear()
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_v
		var day_cols := [UiPalette.FILL["rot"], UiPalette.FILL["gelb"], UiPalette.FILL["gruen"], UiPalette.FILL["blau"], STAR]
		var night_cols := [UiPalette.GLOW["pink"], UiPalette.GLOW["tuerkis"], UiPalette.GLOW["orange"], UiPalette.GLOW["lila"], NEON_CORE]
		for i in 30:
			var ang := rng.randf_range(-PI * 0.95, -PI * 0.05) if i % 5 != 0 else rng.randf_range(-PI, PI)
			_bits.append({"v": Vector2.from_angle(ang) * rng.randf_range(200.0, 470.0) * k, "rot": rng.randf_range(0.0, TAU),
				"spin": rng.randf_range(-9.0, 9.0), "w": rng.randf_range(6.0, 9.0) * k, "h": rng.randf_range(10.0, 15.0) * k,
				"col": (night_cols if night > 0.5 else day_cols)[i % 5], "drag": rng.randf_range(1.2, 2.2)})
		_built = true

	# Abstand Mitte → Rand der Superellipse in Richtung d
	func _edge(sz: Vector2, d: Vector2) -> float:
		var a := sz.x * 0.5
		var b := sz.y * 0.5
		var c := absf(d.x)
		var s := absf(d.y)
		return 1.0 / pow(pow(c / a, SE_N) + pow(s / b, SE_N), 1.0 / SE_N)

	func _shape_for(b: Dictionary, sp: Vector2) -> void:
		var sz: Vector2 = b["size"]
		var at: Vector2 = b["at"]
		var body := PackedVector2Array()
		var n := 72
		for i in n:
			var th := TAU * float(i) / float(n)
			var c := cos(th)
			var s := sin(th)
			body.append(Vector2(sz.x * 0.5 * signf(c) * pow(absf(c), 2.0 / SE_N), sz.y * 0.5 * signf(s) * pow(absf(s), 2.0 / SE_N)))
		var to := sp - at
		var d := to.normalized() if to.length() > 1.0 else tail
		var edge := _edge(sz, d)
		var tl := clampf(to.length() - edge - 8.0 * k, 12.0 * k, 26.0 * k)
		var base := d * (edge - 7.0 * k)
		var p := Vector2(-d.y, d.x)
		var bw := 13.0 * k
		var tip := d * (edge + tl) + p * tl * 0.18      # leicht schräg, wie gezeichnet
		var tail_poly := PackedVector2Array()
		var steps := 7
		for i in steps + 1:           # linke Flanke: Basis → Spitze, leicht nach außen gewölbt
			var u := float(i) / steps
			var q := (base + p * bw).lerp(tip, u) + p * sin(u * PI) * 3.0 * k
			tail_poly.append(q)
		for i in range(1, steps):     # rechte Flanke: Spitze → Basis, nach innen gewölbt
			var u := float(i) / steps
			var q := tip.lerp(base - p * bw, u) + p * sin(u * PI) * 2.0 * k
			tail_poly.append(q)
		tail_poly.append(base - p * bw)
		var merged := Geometry2D.merge_polygons(body, tail_poly)
		var shape := body
		var best := -1.0
		for poly in merged:
			var area := absf(_area(poly))
			if area > best:
				best = area
				shape = poly
		b["shape"] = shape
		var closed := shape.duplicate()
		closed.append(shape[0])
		b["closed"] = closed
		b["tip"] = tip
		b["dir"] = d

	static func _area(poly: PackedVector2Array) -> float:
		var a := 0.0
		for i in poly.size():
			var p := poly[i]
			var q := poly[(i + 1) % poly.size()]
			a += p.x * q.y - q.x * p.y
		return a * 0.5

	# --- Kurven

	static func _spring(t: float, freq := 16.0, damp := 6.5) -> float:
		if t <= 0.0:
			return 0.0
		return 1.0 - exp(-damp * t) * cos(freq * t)

	static func _back(t: float) -> float:
		var u := clampf(t, 0.0, 1.0) - 1.0
		return 1.0 + 2.70158 * u * u * u + 1.70158 * u * u

	static func _out(t: float) -> float:
		var u := 1.0 - clampf(t, 0.0, 1.0)
		return 1.0 - u * u * u

	# Drehen/Skalieren um pivot (Körperkoordinaten), dann an die Stelle at
	static func _about(at: Vector2, pivot: Vector2, rot: float, sc: Vector2, off := Vector2.ZERO) -> Transform2D:
		return Transform2D(0.0, at + pivot + off) * Transform2D(rot, sc, 0.0, Vector2.ZERO) * Transform2D(0.0, -pivot)

	# --- Zeichnen

	func _draw() -> void:
		if not _built:
			build()
		match variant:
			"plopp":
				_draw_plopp()
			"ohren":
				_draw_ohren()
			"huepfen":
				_draw_huepfen()
			"pfote":
				_draw_pfote()
			"wellen":
				_draw_wellen()
			"neon":
				_draw_neon()
			"maumau":
				_draw_maumau(false)
			"maumau_schlicht":
				_draw_maumau(true)
			_:
				_draw_schlicht()
		draw_set_transform_matrix(Transform2D.IDENTITY)

	func _line_col(a := 1.0) -> Color:
		return Color(NEON, a) if night > 0.5 else Color(INK, a)

	# Papierblase: Schatten, nachts rosa Neonkranz, Papier, Druckfarbenrand, Glanzlicht
	func _paper(b: Dictionary, m: Transform2D, fill := CREAM) -> void:
		var shape: PackedVector2Array = b["shape"]
		var closed: PackedVector2Array = b["closed"]
		var sz: Vector2 = b["size"]
		draw_set_transform_matrix(Transform2D(0.0, Vector2(3.0, 7.0) * k) * m)
		draw_colored_polygon(shape, Color(0, 0, 0, 0.34 if night > 0.5 else 0.2))
		draw_set_transform_matrix(m)
		if night > 0.5:
			# Neonkranz hinter dem Papier: weicher Schein, darauf ein klarer rosa Rand
			draw_polyline(closed, Color(NEON, 0.08), 26.0 * k, true)
			draw_polyline(closed, Color(NEON, 0.16), 16.0 * k, true)
			draw_polyline(closed, Color(NEON, 0.95), 9.5 * k, true)
			draw_circle(b["tip"], 4.6 * k, NEON)
		draw_colored_polygon(shape, fill)
		draw_polyline(closed, INK, maxf(3.0, 4.2 * k), true)
		draw_circle(b["tip"], maxf(1.5, 2.1 * k), INK)
		draw_arc(Vector2(-sz.x * 0.27, -sz.y * 0.06), sz.y * 0.27, PI * 1.08, PI * 1.42, 10, Color(1, 1, 1, 0.85), 3.0 * k, true)

	# „Mau!“ in Fraunces kursiv; am Tag mit leicht versetztem rosa Druck darunter (Papier-Druck-Anmutung)
	func _label(b: Dictionary, m: Transform2D, col := INK) -> void:
		draw_set_transform_matrix(m)
		var fs: int = b["fs"]
		var p := Vector2(-float(b["tw"]) * 0.5 - fs * 0.03, fs * 0.35)
		if night <= 0.5:
			draw_string(_font, p + Vector2(2.2, 2.0) * k, str(b["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(NEON, 0.75))
		draw_string(_font, p, str(b["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	func _star(pos: Vector2, r: float, rot: float, fill: Color, outline: Color) -> void:
		if r <= 0.5:
			return
		var pts := PackedVector2Array()
		for i in 8:
			var a := rot + TAU * i / 8.0 - PI * 0.5
			pts.append(pos + Vector2.from_angle(a) * (r if i % 2 == 0 else r * 0.36))
		draw_colored_polygon(pts, fill)
		pts.append(pts[0])
		draw_polyline(pts, outline, maxf(1.5, 2.2 * k), true)

	# Funkelsterne um eine Blase (je einer erscheint, dreht sich und vergeht – einmal, kein Blinken)
	func _sparkles(b: Dictionary, m: Transform2D, t: float, starts: Array, life := 0.55) -> void:
		var sz: Vector2 = b["size"]
		var spots: Array[Vector2] = [Vector2(0.60, -0.62), Vector2(-0.66, -0.30), Vector2(0.62, 0.50), Vector2(-0.40, -0.86), Vector2(0.20, -0.95)]
		draw_set_transform_matrix(Transform2D.IDENTITY)
		for i in mini(starts.size(), spots.size()):
			var u := (t - float(starts[i])) / life
			if u <= 0.0 or u >= 1.0:
				continue
			var p := m * (Vector2(spots[i].x * sz.x, spots[i].y * sz.y))
			var r := (11.0 + 3.0 * (i % 2)) * k * sin(PI * u)
			if night > 0.5:
				draw_circle(p, r * 1.5, Color(NEON, 0.18))
				_star(p, r, u * 1.4, NEON_CORE, NEON)
			else:
				_star(p, r, u * 1.4, STAR, INK)

	# (a) Plopp mit Überschwinger, Quetschen und Nachwackeln; Plopp-Striche
	func _draw_plopp() -> void:
		var b: Dictionary = _bodies[0]
		var t := age
		var s := _spring(t, 16.0, 6.5)
		var sq := 0.14 * sin(16.0 * t) * exp(-6.0 * t)
		var rot := 0.11 * exp(-3.0 * t) * sin(11.0 * t)
		var m := _about(b["at"], b["tip"], rot, Vector2(s * (1.0 + sq), s * (1.0 - sq)))
		_pop_lines(b, t, 0.05, 0.36)
		_paper(b, m)
		_label(b, m)

	func _pop_lines(b: Dictionary, t: float, t0: float, t1: float) -> void:
		var u := (t - t0) / (t1 - t0)
		if u <= 0.0 or u >= 1.0:
			return
		draw_set_transform_matrix(Transform2D.IDENTITY)
		var sz: Vector2 = b["size"]
		var d: Vector2 = b["dir"]
		var e := _out(u)
		for j in 9:
			var dir := Vector2.from_angle(TAU * j / 9.0 + 0.25)
			if dir.dot(d) > 0.55:
				continue
			var r0 := _edge(sz, dir) + 10.0 * k
			var a := Vector2(b["at"]) + dir * (r0 + 28.0 * k * e)
			var z := Vector2(b["at"]) + dir * (r0 + 28.0 * k * e + 15.0 * k * (1.0 - u))
			draw_line(a, z, _line_col(1.0 - u * 0.5), maxf(2.5, 4.0 * k), true)

	# (b) Katzenohren springen hoch und zucken, Schnurrhaare, Funkelsterne
	func _draw_ohren() -> void:
		var b: Dictionary = _bodies[0]
		var t := age
		var s := lerpf(0.25, 1.0, _back(t / 0.3))
		var m := _about(b["at"], b["tip"], 0.0, Vector2(s, s))
		var ear_up := _back((t - 0.14) / 0.2)
		var tw_l := -0.5 * exp(-11.0 * (t - 0.55)) * sin(30.0 * (t - 0.55)) if t > 0.55 else 0.0
		var tw_r := 0.5 * exp(-11.0 * (t - 0.86)) * sin(30.0 * (t - 0.86)) if t > 0.86 else 0.0
		if t > 0.14:
			_ear(b, m, -1.0, ear_up, tw_l)
			_ear(b, m, 1.0, ear_up, tw_r)
		_paper(b, m)
		if t > 0.18:
			_whiskers(b, m, t)
		_label(b, m)
		_sparkles(b, m, t, [0.24, 0.40, 0.54, 0.70])

	func _ear(b: Dictionary, m: Transform2D, side: float, up: float, twitch: float) -> void:
		var sz: Vector2 = b["size"]
		var base := Vector2(side * sz.x * 0.25, -sz.y * 0.5 + 9.0 * k)
		var h := 33.0 * k * up
		var w := 18.0 * k
		var pts := PackedVector2Array([Vector2(-w, 0), Vector2(-w * 0.35, -h * 0.62), Vector2(side * 2.0 * k - 3.0 * k, -h),
			Vector2(side * 2.0 * k + 3.0 * k, -h + 1.0 * k), Vector2(w * 0.4, -h * 0.58), Vector2(w, 0)])
		var em := m * Transform2D(twitch + side * 0.12, base)
		draw_set_transform_matrix(em)
		var closed := pts.duplicate()
		closed.append(pts[0])
		if night > 0.5:
			draw_polyline(closed, Color(NEON, 0.16), 16.0 * k, true)
			draw_polyline(closed, Color(NEON, 0.95), 9.5 * k, true)
		draw_colored_polygon(pts, CREAM)
		draw_polyline(closed, INK, maxf(3.0, 4.2 * k), true)
		var inner := PackedVector2Array([Vector2(-w * 0.48, -2.0 * k), Vector2(side * 2.0 * k, -h * 0.72), Vector2(w * 0.48, -2.0 * k)])
		if h > 6.0 * k:
			draw_colored_polygon(inner, EAR_PINK)

	func _whiskers(b: Dictionary, m: Transform2D, t: float) -> void:
		var sz: Vector2 = b["size"]
		var d: Vector2 = b["dir"]
		var grow := _out((t - 0.18) / 0.2)
		draw_set_transform_matrix(m)
		for side: float in [-1.0, 1.0]:
			if d.x * side > 0.6:
				continue                     # dort kommt der Schwanz heraus
			for j in 3:
				var tilt := (float(j) - 1.0) * 0.3 * side + sin(t * 9.0 + j + side) * 0.06
				var a := Vector2(side * (sz.x * 0.5 - 5.0 * k), (float(j) - 1.0) * 6.0 * k + 5.0 * k)
				var dirw := Vector2(side, 0).rotated(tilt)
				draw_line(a, a + dirw * 22.0 * k * grow, _line_col(0.9), maxf(1.5, 2.2 * k), true)

	# (c) Buchstaben hüpfen einzeln hinein, danach läuft eine Welle hindurch
	func _draw_huepfen() -> void:
		var b: Dictionary = _bodies[0]
		var t := age
		var s := lerpf(0.3, 1.0, _back(t / 0.22))
		var m := _about(b["at"], b["tip"], 0.0, Vector2(s, s))
		_paper(b, m)
		var txt := str(b["text"])
		var fs: int = b["fs"]
		var x := -float(b["tw"]) * 0.5 - fs * 0.03
		for i in txt.length():
			var ch := txt[i]
			var cw := _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var ti := 0.12 + i * 0.11
			var u := (t - ti) / 0.3
			if u > 0.0:
				var dy := 0.0
				var sx := 1.0
				var sy := 1.0
				var rot := 0.0
				var sc := 1.0
				if u < 1.0:
					dy = -24.0 * k * 4.0 * u * (1.0 - u)
					sc = lerpf(0.35, 1.0, clampf(u * 3.0, 0.0, 1.0))
					sy = 1.0 + 0.16 * (1.0 - absf(2.0 * u - 1.0))
					sx = 1.0 / sy
				else:
					var tau := t - ti - 0.3
					var q := 0.24 * exp(-12.0 * tau) * cos(26.0 * tau)
					sx = 1.0 + q
					sy = 1.0 - q
					if ch == "!":
						rot = 0.28 * exp(-5.0 * tau) * sin(16.0 * tau)
				var wv := clampf((t - 0.95 - i * 0.07) / 0.24, 0.0, 1.0)
				dy -= 9.0 * k * sin(PI * wv)
				var lp := Vector2(x + cw * 0.5, fs * 0.35)
				var lm := m * Transform2D(0.0, lp + Vector2(0, dy)) * Transform2D(rot, Vector2(sx, sy) * sc, 0.0, Vector2.ZERO) * Transform2D(0.0, -lp)
				draw_set_transform_matrix(lm)
				if night <= 0.5:
					draw_string(_font, Vector2(x, fs * 0.35) + Vector2(2.2, 2.0) * k, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(NEON, 0.75))
				draw_string(_font, Vector2(x, fs * 0.35), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
			x += _font.get_string_size(txt.substr(0, i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x - _font.get_string_size(txt.substr(0, i), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

	# (d) Fliegt aus dem Avatar heraus, dreht sich ein; Pfotenabdrücke auf dem Weg, Herzchen
	# Mitte des Rufenden (lokal); ohne speaker kurz hinter der Schwanzspitze
	func _speaker_point() -> Vector2:
		if speaker.is_finite():
			return speaker
		var b0: Dictionary = _bodies[0]
		return Vector2(b0["at"]) + Vector2(b0["tip"]) + Vector2(b0["dir"]) * (speaker_r + 4.0) * k

	func _speaker_radius() -> float:
		return speaker_r if speaker.is_finite() else speaker_r * k

	func _draw_pfote() -> void:
		var b: Dictionary = _bodies[0]
		var t := age
		var fly := 0.36
		var from := _speaker_point()
		var to: Vector2 = b["at"]
		var mid := (from + to) * 0.5
		var dirv := (to - from).normalized()
		var perp := dirv.orthogonal()
		if perp.y > 0.0:
			perp = -perp
		var ctrl := mid + perp * from.distance_to(to) * 0.45
		var u := clampf(t / fly, 0.0, 1.0)
		var e := _out(u)
		var side := -1.0 if (to - from).x >= 0.0 else 1.0
		# Pfotenspur: eine Katze tapst vom Rufenden seitlich zur Blase hinauf (Avatarfarbe mit Druckfarbenrand, nachts Neonrand)
		var sz: Vector2 = b["size"]
		var walk := dirv.orthogonal()
		if walk.x < 0.0:
			walk = -walk
		var rr := _speaker_radius()
		var p0 := from + walk * (rr + 12.0 * k) - dirv * rr * 0.75
		var p1 := to + walk * _edge(sz, walk) * 0.95 - dirv * _edge(sz, dirv) * 0.8
		var paw_w := UiIcons.icon("pfote", 64, Color.WHITE)
		var paw_ink := UiIcons.icon("pfote", 64, INK if night <= 0.5 else NEON)
		var step_dir := (p1 - p0).normalized()
		for j in 3:
			var v := t - (0.05 + 0.1 * j)
			if v <= 0.0:
				continue
			var a := clampf(minf(v / 0.06, (1.32 - t) / 0.3), 0.0, 1.0)
			if a <= 0.0:
				continue
			var q := p0.lerp(p1, 0.08 + 0.42 * j) + step_dir.orthogonal() * (7.0 * k if j % 2 == 0 else -7.0 * k)
			var sc := lerpf(1.45, 1.0, _out(v / 0.12))
			var ps := 27.0 * k * sc
			draw_set_transform(q, step_dir.angle() + PI * 0.5, Vector2.ONE)
			draw_texture_rect(paw_ink, Rect2(-ps * 0.56, -ps * 0.56, ps * 1.12, ps * 1.12), false, Color(1, 1, 1, a))
			draw_texture_rect(paw_w, Rect2(-ps * 0.45, -ps * 0.45, ps * 0.9, ps * 0.9), false, Color(accent, a))
		var pos := _bez(from, ctrl, to, e)
		var s := lerpf(0.25, 1.0, e)
		var rot := lerpf(0.5 * side, 0.0, e)
		if t > fly:
			var tau := t - fly
			s *= 1.0 + 0.08 * exp(-8.0 * tau) * sin(20.0 * tau)
			rot += -0.16 * side * exp(-6.0 * tau) * sin(15.0 * tau)
		var m := Transform2D(0.0, pos) * Transform2D(rot, Vector2(s, s), 0.0, Vector2.ZERO)
		_paper(b, m)
		_label(b, m)
		# Herzchen oben rechts
		var th := t - fly - 0.05
		if th > 0.0:
			var hs := _back(th / 0.22) * k
			var hp := m * Vector2(sz.x * 0.5 - 4.0 * k, -sz.y * 0.5 - 2.0 * k) + Vector2(0, -16.0 * k * _out(th / 0.9))
			var heart_ink := UiIcons.icon("herz", 64, INK if night <= 0.5 else NEON)
			var heart := UiIcons.icon("herz", 64, HEART if night <= 0.5 else NEON_CORE)
			draw_set_transform(hp, 0.22 * sin(th * 5.0), Vector2(hs, hs))
			if night > 0.5:
				draw_texture_rect(TableEffects.glow_texture(), Rect2(-30, -30, 60, 60), false, Color(NEON, 0.35))
			draw_texture_rect(heart_ink, Rect2(-17, -16, 34, 34), false)
			draw_texture_rect(heart, Rect2(-13, -12, 26, 26), false)

	static func _bez(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
		var u := 1.0 - t
		return u * u * a + 2.0 * u * t * c + t * t * b

	# (e) Schallwellen vom Rufenden, Blase schwingt wie ein Ballon nach
	func _draw_wellen() -> void:
		var b: Dictionary = _bodies[0]
		var t := age
		var sp := _speaker_point()
		var r0 := _speaker_radius()
		var up := (Vector2(b["at"]) - sp).angle()
		draw_set_transform_matrix(Transform2D.IDENTITY)
		# Schallwellen links und rechts vom Rufenden: „((( M )))“, drei Bögen je Seite, nacheinander
		for j in 3:
			var u := (t - j * 0.1) / 0.6
			if u <= 0.0 or u >= 1.0:
				continue
			var r := r0 + (6.0 + 46.0 * _out(u)) * k
			var a := (1.0 - u) * (1.0 - u)
			for ang: float in [up + PI * 0.5, up - PI * 0.5]:
				if night > 0.5:
					draw_arc(sp, r, ang - 0.55, ang + 0.55, 20, Color(NEON, a * 0.25), 12.0 * k, true)
				draw_arc(sp, r, ang - 0.55, ang + 0.55, 20, _line_col(a), maxf(2.5, 4.5 * k), true)
		var s := lerpf(0.1, 1.0, _back(t / 0.32))
		var rot := 0.26 * exp(-1.8 * t) * sin(6.2 * t)
		var stretch := 0.06 * sin(5.0 * t) * exp(-2.0 * t)
		var bob := -Vector2(b["dir"]) * 5.0 * k * sin(5.0 * t) * exp(-1.4 * t)
		var m := _about(b["at"], b["tip"], rot, Vector2(s * (1.0 - stretch), s * (1.0 + stretch)), bob)
		_paper(b, m)
		_label(b, m)

	# (f) Neonröhre glimmt einmal auf (erst Rand, dann Schrift), dunkle Blase
	func _draw_neon() -> void:
		var b: Dictionary = _bodies[0]
		var t := age
		var g := smoothstep(0.04, 0.30, t) * (1.0 + 0.35 * exp(-pow((t - 0.33) / 0.09, 2.0)))
		var gt := smoothstep(0.16, 0.42, t) * (1.0 + 0.3 * exp(-pow((t - 0.45) / 0.09, 2.0)))
		var s := lerpf(0.9, 1.0, _out(t / 0.3))
		var m := _about(b["at"], b["tip"], 0.0, Vector2(s, s))
		var shape: PackedVector2Array = b["shape"]
		var closed: PackedVector2Array = b["closed"]
		var sz: Vector2 = b["size"]
		draw_set_transform_matrix(m)
		draw_texture_rect(TableEffects.glow_texture(), Rect2(-sz * 0.95, sz * 1.9), false, Color(NEON, 0.2 * g))
		draw_colored_polygon(shape, Color(0.07, 0.05, 0.18, 0.92 * smoothstep(0.0, 0.12, t)))
		draw_polyline(closed, Color(NEON, 0.10 * g), 18.0 * k, true)
		draw_polyline(closed, Color(NEON, 0.22 * g), 10.0 * k, true)
		draw_polyline(closed, Color(NEON, minf(0.55 * g, 1.0)), 6.0 * k, true)
		draw_polyline(closed, Color(NEON_CORE, minf(g, 1.0)), maxf(1.5, 2.6 * k), true)
		var fs: int = b["fs"]
		var tp := Vector2(-float(b["tw"]) * 0.5 - fs * 0.03, fs * 0.35)
		if gt > 0.0:
			draw_string_outline(_font, tp, str(b["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(16.0 * k), Color(NEON, 0.12 * gt))
			draw_string_outline(_font, tp, str(b["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(8.0 * k), Color(NEON, 0.3 * gt))
			draw_string(_font, tp, str(b["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Color("#FFF2FA"), minf(gt, 1.0)))

	# Effektstufe „reduziert“: kurz einblenden, stehen, ausblenden
	func _draw_schlicht() -> void:
		var b: Dictionary = _bodies[0]
		var s := lerpf(0.9, 1.0, _out(age / 0.16))
		var m := _about(b["at"], b["tip"], 0.0, Vector2(s, s))
		_paper(b, m)
		_label(b, m)

	# „Mau-Mau!“: zwei Blasen im Takt der Aufnahme, dann Konfetti (Tag) bzw. Neonfunken (Nacht)
	func _draw_maumau(simple: bool) -> void:
		var t := age
		if not simple and _bodies.size() >= 2:
			_confetti(t - 0.34)                # bricht hinter der zweiten Blase hervor
		for i in _bodies.size():
			var b: Dictionary = _bodies[i]
			var tau := t - float(b["t0"])
			if tau <= 0.0:
				continue
			var m: Transform2D
			if simple:
				var s := lerpf(0.9, 1.0, _out(tau / 0.16))
				m = _about(b["at"], b["tip"], 0.0, Vector2(s, s))
			else:
				var s := _spring(tau, 14.0, 7.5)
				var sq := 0.12 * sin(14.0 * tau) * exp(-7.0 * tau)
				var lean := -0.07 if i == 0 else 0.06
				var rot := lean + 0.1 * exp(-3.2 * tau) * sin(11.0 * tau) * (1.0 if i == 1 else -1.0)
				m = _about(b["at"], b["tip"], rot, Vector2(s * (1.0 + sq), s * (1.0 - sq)))
			_paper(b, m)
			_label(b, m)
			if not simple and i == 1:
				_sparkles(b, m, tau, [0.18, 0.30, 0.42, 0.55, 0.66], 0.6)

	# Konfetti (Tag: Papierstreifen in den Kartenfarben) bzw. Neonfunken (Nacht: leuchtende Striche in Flugrichtung)
	func _confetti(tc: float) -> void:
		if tc <= 0.0:
			return
		var b1: Dictionary = _bodies[1]
		var origin := Vector2(b1["at"])
		var fade := clampf((total() - 0.34 - tc) / 0.45, 0.0, 1.0)
		var grav := 520.0 * k
		for bit in _bits:
			var drag := float(bit["drag"])
			var v: Vector2 = bit["v"]
			var p := origin + v * (1.0 - exp(-drag * tc)) / drag + Vector2(0, 0.5 * grav * tc * tc)
			var col: Color = bit["col"]
			if night > 0.5:
				var vel := v * exp(-drag * tc) + Vector2(0, grav * tc)
				var tail_v := vel.normalized() * clampf(vel.length() * 0.045, 4.0 * k, 18.0 * k)
				draw_set_transform_matrix(Transform2D.IDENTITY)
				draw_line(p - tail_v, p, Color(col, 0.3 * fade), 7.0 * k, true)
				draw_line(p - tail_v, p, Color(col.lightened(0.45), fade), 2.6 * k, true)
			else:
				var rot := float(bit["rot"]) + float(bit["spin"]) * tc
				var w := float(bit["w"]) * (0.55 + 0.45 * absf(cos(rot * 1.7)))   # Papierstreifen dreht sich
				draw_set_transform(p, rot, Vector2.ONE)
				draw_rect(Rect2(-w * 0.5, -float(bit["h"]) * 0.5, w, float(bit["h"])), Color(col, fade))

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


# Sanfte Lichtstrahlen wie am Tisch (Rundenende, 0.1.4): Shader soft_rays statt Keilen, nichts dreht sich
class SoftRaysFx:
	extends Node2D
	var radius := 700.0
	var tint := Color(1.0, 0.86, 0.5, 0.5)
	var motion := true

	func _ready() -> void:
		var sh := load("res://assets/shaders/soft_rays.gdshader") as Shader
		if sh != null:
			var m := ShaderMaterial.new()
			m.shader = sh
			m.set_shader_parameter("tint", tint)
			m.set_shader_parameter("radius", radius)
			m.set_shader_parameter("inner", radius * 0.09)
			m.set_shader_parameter("motion", 1.0 if motion else 0.0)
			material = m

	func _draw() -> void:
		draw_rect(Rect2(-Vector2(radius, radius), Vector2(radius, radius) * 2.0), Color.WHITE)


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


# ---------------------------------------------------------------- Hausregeln mit Zusatzkarten (Kartentausch, Glücksspiel)

# Verzögerter Aufruf, der mit clear() verfällt (Überspringen bei Rückstand): ein kleiner Hilfsknoten trägt den Zeitgeber.
func after(delay: float, cb: Callable) -> void:
	var n := Node.new()
	add_child(n)
	var tw := n.create_tween()
	tw.tween_interval(maxf(delay, 0.001))
	tw.tween_callback(func() -> void:
		if cb.is_valid():
			cb.call())
	tw.tween_callback(n.queue_free)


class SwapArrowsFx:
	extends Node2D
	# Kartentausch: zwei Bogenpfeile um die Tischmitte drehen sich in Tauschrichtung (dir +1 = im Uhrzeigersinn auf diesem
	# Bildschirm). Zeichnet nur während seiner Lebenszeit neu und gibt sich danach frei.
	var radii := Vector2(104, 74)
	var dir := 1.0
	var color := Color.WHITE
	var dur := 1.3
	var width := 7.0
	var age := 0.0

	func _process(delta: float) -> void:
		age += delta
		if age >= dur:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t := clampf(age / dur, 0.0, 1.0)
		var a := clampf(minf(t / 0.14, (1.0 - t) / 0.3), 0.0, 1.0)
		var u := clampf(t / 0.3, 0.0, 1.0) - 1.0
		var k := 0.82 + 0.18 * (1.0 + 2.70158 * u * u * u + 1.70158 * u * u)
		var spin := dir * PI * 1.25 * (1.0 - pow(1.0 - t, 2.0))
		var span := PI * 0.66
		for arm in 2:
			var start := spin + float(arm) * PI - dir * span * 0.5
			var pts := PackedVector2Array()
			var steps := 26
			for i in steps + 1:
				var ang := start + dir * span * float(i) / steps
				pts.append(Vector2(cos(ang) * radii.x, sin(ang) * radii.y) * k)
			var col := Color(color, color.a * a)
			draw_polyline(pts, Color(col, col.a * 0.28), width * 2.6, true)
			draw_polyline(pts, col, width, true)
			# Pfeilspitze an der Spitze in Drehrichtung
			var head := pts[pts.size() - 1]
			var tang := (head - pts[pts.size() - 3]).normalized()
			var nrm := Vector2(-tang.y, tang.x)
			var hs := width * 2.6
			draw_colored_polygon(PackedVector2Array([head + tang * hs * 0.9, head - tang * hs * 0.5 + nrm * hs, head - tang * hs * 0.5 - nrm * hs]), col)


# Bogenpfeile des Kartentauschs um pos (dir +1 = im Uhrzeigersinn)
func swap_arrows(pos: Vector2, dir: int, color: Color, dur := 1.3, radii := Vector2(104, 74)) -> SwapArrowsFx:
	var s := SwapArrowsFx.new()
	s.position = pos
	s.dir = 1.0 if dir >= 0 else -1.0
	s.color = color
	s.dur = dur
	s.radii = radii
	s.material = additive() if night > 0.5 else null
	add_child(s)
	return s


# Treffer im Glücksspiel: große Zahl mit Strahlenkranz (Neon nachts), Lichtblitz und Ring; darüber klein „Treffer!“.
func hit_burst(pos: Vector2, number: String, dur := 1.1) -> void:
	var neon := night > 0.5
	var glow_col := NEON_PINK if neon else UiPalette.TURN
	if not reduced:
		var rays := RaysFx.new()
		rays.position = pos
		rays.radius = 240.0
		rays.count = 16
		rays.color = Color(glow_col, 0.34 if neon else 0.42)
		rays.material = additive() if neon else null
		rays.modulate.a = 0.0
		add_child(rays)
		move_child(rays, 0)
		var rt := rays.create_tween()
		rt.tween_property(rays, "modulate:a", 1.0, dur * 0.15)
		rt.tween_interval(dur * 0.45)
		rt.tween_property(rays, "modulate:a", 0.0, dur * 0.4)
		rt.tween_callback(rays.queue_free)
		ring_wave(pos, glow_col, 50.0, 300.0, dur * 0.65, 10.0)
	glow_flash(pos, 190.0, glow_col, dur * 0.55, 0.85 if neon else 0.6)
	var f := UiFonts.title(900, true, 100.0)
	var num := _text(pos + Vector2(0, 12), number, f, 128, NEON_PINK.lerp(Color.WHITE, 0.55) if neon else UiPalette.TURN,
		Color(NEON_PINK, 0.9) if neon else UiPalette.INK, 14)
	var cap := _text(pos + Vector2(0, -86), "Treffer!", f, 40, UiPalette.CREAM, Color(UiPalette.INK, 0.9), 7)
	for t in [num, cap]:
		var tx := t as TextFx
		tx.scale = Vector2.ONE * 0.3
		var tw := tx.create_tween()
		tw.tween_property(tx, "scale", Vector2.ONE, minf(0.28, dur * 0.3)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(dur * 0.45)
		tw.tween_property(tx, "modulate:a", 0.0, dur * 0.25)
		tw.parallel().tween_property(tx, "scale", Vector2.ONE * 1.12, dur * 0.25)
		tw.tween_callback(tx.queue_free)


# Laufende Effekte entfernen (Abgleich auf die Sicht, Überspringen)
func clear() -> void:
	for c in get_children():
		c.queue_free()
