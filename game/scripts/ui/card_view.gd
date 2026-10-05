class_name CardView
extends Node2D
# Eine Spielkarte auf dem Tisch oder in der Hand (docs/BETA1_PLAN.md Abschnitt 7). Gemeinsamer Baustein für Hand und Tisch.
# Der Ursprung liegt in der Kartenmitte; die Breite in Pixeln setzt man mit width, die Höhe folgt dem Seitenverhältnis 300:466.
# Vorderseite = die Seite, die der Betrachter sehen soll (eigene Hand: aktive Seite; Gegner: deren Rückseite, also die andere Seite).
# Ändern darf diese Datei nur Modul F1a (Hand); andere Module melden Bedarf.
# Aufbau: Die Karte selbst (position, rotation, scale) gehört dem Besitzer (Hand, Tisch, Regie). Wende, Schütteln und Schimmern
# wirken auf den inneren Körper, stören also keine Federn oder Tweens des Besitzers. Schatten und Glühen sind weiche,
# einmal erzeugte Texturen (Glühen additiv, wie Neon auf dem Nachtgrund).

signal flipped

const ASPECT := 466.0 / 300.0
const SOFT_CARD := Vector2(120.0, 186.4)     # Kartenmaß in der weichen Textur …
const SOFT_MARGIN := 22.0                    # … plus Rand für Schatten und Glühen
const SOFT_RADIUS := 8.6                     # Eckradius (40 von 560 Einheiten)
const SOFT_SIGMA := 7.5                     # Schatten
const GLOW_SIGMA := 3.6                     # Glühen (enger, wie drop-shadow 0 0 8–14 px im Entwurf)
const GLOW_PLAYABLE := Color(1.0, 0.96, 0.86, 0.42)
const GLOW_SELECTED := Color(1.0, 0.80, 0.30, 0.95)

enum State { NORMAL, PLAYABLE, SELECTED, DIMMED }

var card_id := -1
var front_key := ""
var back_key := ""
var showing_front := true
var width := 120.0: set = set_width
var state := State.NORMAL: set = set_state
var brightness := 1.0: set = set_brightness     # 1 = volle Helligkeit (Karussellrand 0,75, nicht spielbar ~0,85)
var elevation := 0.0: set = set_elevation       # 0 = liegt, 1 = angehoben/gezogen (Schatten weiter und weicher)

var _body: Node2D
var _shadow: Sprite2D
var _glow: Sprite2D
var _sprite: Sprite2D
var _flip_tween: Tween
var _shake_tween: Tween
var _shimmer_tween: Tween
var _glow_color := Color(0, 0, 0, 0)
var _extra_glow := Color(0, 0, 0, 0)

static var _soft_cache := {}
static var _add_material: CanvasItemMaterial
static var _shimmer_shader: Shader


func _init() -> void:
	_body = Node2D.new()
	add_child(_body)
	_shadow = Sprite2D.new()
	_shadow.texture = soft_texture()
	_shadow.modulate = Color(0, 0, 0, 0.42)
	_body.add_child(_shadow)
	_glow = Sprite2D.new()
	_glow.texture = soft_texture(GLOW_SIGMA)
	_glow.material = _additive()
	_glow.visible = false
	_body.add_child(_glow)
	_sprite = Sprite2D.new()
	_body.add_child(_sprite)
	set_width(width)


func setup(id: int, front: String, back: String = "", show_front := true) -> CardView:
	card_id = id
	front_key = front
	back_key = back
	showing_front = show_front
	_apply_texture()
	return self


func current_key() -> String:
	return front_key if showing_front or back_key == "" else back_key


func set_width(w: float) -> void:
	width = maxf(w, 4.0)
	if _sprite == null:
		return
	var tex := _sprite.texture
	var tw := float(tex.get_width()) if tex else 300.0
	var s := width / tw
	_sprite.scale = Vector2(s, s)
	_update_glow()
	_update_shadow()


func card_size() -> Vector2:
	return Vector2(width, width * ASPECT)


func set_state(s: State) -> void:
	state = s
	if _sprite == null:
		return
	match s:
		State.NORMAL, State.DIMMED:
			_glow_color = Color(0, 0, 0, 0)
		State.PLAYABLE:
			_glow_color = GLOW_PLAYABLE
		State.SELECTED:
			_glow_color = GLOW_SELECTED
	_update_glow()
	_update_modulate()


func set_brightness(b: float) -> void:
	brightness = clampf(b, 0.0, 1.5)
	if _sprite != null:
		_update_modulate()


func set_elevation(e: float) -> void:
	elevation = clampf(e, 0.0, 1.5)
	if _shadow != null:
		_update_shadow()


# Zusätzliches Glühen (z. B. Hilfe-Ziel, Hinweis); Alpha = Stärke, Color(0, 0, 0, 0) = aus.
func set_glow(c: Color) -> void:
	_extra_glow = c
	_update_glow()


func show_side(front: bool) -> void:
	showing_front = front
	_apply_texture()


# Faux-3D-Wende um die senkrechte Achse; der Seitenwechsel passiert in der Mitte. Gibt den Tween zurück (zum Verketten).
func flip(duration := 0.3, delay := 0.0) -> Tween:
	return flip_to(not showing_front, duration, delay)


# Wende zu einer bestimmten Seite (front = Vorderseite zeigen); auch mitten in einer laufenden Wende eindeutig.
func flip_to(front: bool, duration := 0.3, delay := 0.0) -> Tween:
	if _flip_tween and _flip_tween.is_valid():
		_flip_tween.kill()
	_body.scale = Vector2.ONE
	_flip_tween = create_tween()
	if delay > 0.0:
		_flip_tween.tween_interval(delay)
	_flip_tween.tween_property(_body, "scale", Vector2(0.02, 1.05), duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_flip_tween.tween_callback(func() -> void:
		showing_front = front
		_apply_texture())
	_flip_tween.tween_property(_body, "scale", Vector2.ONE, duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_flip_tween.tween_callback(func() -> void: flipped.emit())
	return _flip_tween


func is_flipping() -> bool:
	return _flip_tween != null and _flip_tween.is_valid() and _flip_tween.is_running()


# „Nein“-Schütteln: 3 Schwingungen in 250 ms (nicht spielbar, abgelehnt).
func shake(duration := 0.25, amplitude := 9.0) -> void:
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	_shake_tween.tween_method(func(t: float) -> void:
		_body.position.x = amplitude * (width / 190.0) * sin(t * TAU * 3.0) * (1.0 - t), 0.0, 1.0, duration)
	_shake_tween.tween_callback(func() -> void: _body.position.x = 0.0)


# Neue Karte: Glanzstreifen wandert mehrmals über die Karte, dazu warmes Glühen, das ausklingt (insgesamt duration s).
func shimmer(duration := 3.0) -> void:
	if _shimmer_tween and _shimmer_tween.is_valid():
		_shimmer_tween.kill()
	var mat := ShaderMaterial.new()
	mat.shader = _shimmer()
	_sprite.material = mat
	_shimmer_tween = create_tween()
	_shimmer_tween.tween_method(func(t: float) -> void:
		var sweeps := 3.0
		var phase := fmod(t * sweeps, 1.0)
		mat.set_shader_parameter("shine", lerpf(-0.35, 1.75, phase / 0.75) if phase < 0.75 else -2.0)
		mat.set_shader_parameter("strength", 0.55 * (1.0 - 0.35 * t))
		set_glow(Color(1.0, 0.86, 0.45, 0.55 * (1.0 - t))), 0.0, 1.0, duration)
	_shimmer_tween.tween_callback(func() -> void:
		_sprite.material = null
		set_glow(Color(0, 0, 0, 0)))


func is_shimmering() -> bool:
	return _shimmer_tween != null and _shimmer_tween.is_valid() and _shimmer_tween.is_running()


# Umriss der Karte in globalen Koordinaten (Treffertest, Joker-Strahlen).
func global_polygon() -> PackedVector2Array:
	var h := card_size() * 0.5
	var xf := global_transform
	return PackedVector2Array([xf * Vector2(-h.x, -h.y), xf * Vector2(h.x, -h.y), xf * Vector2(h.x, h.y), xf * Vector2(-h.x, h.y)])


func contains_global_point(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, global_polygon())


func _apply_texture() -> void:
	var tex := CardTextures.get_texture(current_key()) if current_key() != "" else CardTextures.get_texture(CardTextures.BACK)
	_sprite.texture = tex
	set_width(width)


func _update_modulate() -> void:
	var b := brightness * (0.72 if state == State.DIMMED else 1.0)
	_sprite.modulate = Color(b, b, minf(b * 1.03, 1.5))


func _update_glow() -> void:
	var c := _glow_color
	var spread := 1.07 if state == State.SELECTED else 1.035
	if _extra_glow.a > c.a:
		c = _extra_glow
		spread = 1.06
	_glow.visible = c.a > 0.01
	_glow.modulate = Color(c.r * c.a, c.g * c.a, c.b * c.a, 1.0)
	var ss := width / SOFT_CARD.x
	_glow.scale = Vector2(ss, ss) * spread


func _update_shadow() -> void:
	var ss := width / SOFT_CARD.x
	var e := elevation
	_shadow.scale = Vector2(ss, ss) * (1.0 + 0.05 * e)
	_shadow.position = Vector2(width * (0.02 + 0.02 * e), width * (0.045 + 0.07 * e))
	_shadow.modulate = Color(0, 0, 0, 0.42 - 0.08 * e)


# Weiche Kartenform (abgerundetes Rechteck mit Gaußrand der Breite sigma), je sigma einmal erzeugt; alle Karten teilen sie.
static func soft_texture(sigma := SOFT_SIGMA) -> Texture2D:
	if _soft_cache.has(sigma):
		return _soft_cache[sigma]
	var w := int(SOFT_CARD.x + 2.0 * SOFT_MARGIN)
	var h := int(SOFT_CARD.y + 2.0 * SOFT_MARGIN)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var half := SOFT_CARD * 0.5 - Vector2(SOFT_RADIUS, SOFT_RADIUS)
	var c := Vector2(w, h) * 0.5
	for y in h:
		for x in w:
			var q := (Vector2(x + 0.5, y + 0.5) - c).abs() - half
			var sd := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - SOFT_RADIUS
			var a := 0.5 - 0.5 * _erf(sd / (sigma * 1.414))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_soft_cache[sigma] = tex
	return tex


static func _additive() -> CanvasItemMaterial:
	if _add_material == null:
		_add_material = CanvasItemMaterial.new()
		_add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_material


static func _shimmer() -> Shader:
	if _shimmer_shader == null:
		_shimmer_shader = Shader.new()
		_shimmer_shader.code = """
shader_type canvas_item;
// Glanzstreifen für neue Karten: schräges Lichtband an Position shine (UV-Diagonale 0 … 1,4)
uniform float shine = -2.0;
uniform float strength = 0.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float d = UV.x * 0.8 + UV.y * 0.6 - shine;
	float band = exp(-d * d * 70.0) * strength;
	c.rgb += vec3(1.0, 0.95, 0.82) * band * c.a;
	COLOR = c;
}
"""
	return _shimmer_shader


static func _erf(x: float) -> float:
	var a := absf(x)
	var t := 1.0 / (1.0 + 0.3275911 * a)
	var y := 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-a * a)
	return y if x >= 0.0 else -y
