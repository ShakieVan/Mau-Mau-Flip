class_name TableBackground
extends ColorRect
# Vollbild-Hintergrund mit dem Shader res://assets/shaders/table_background.gdshader. tageszeit 0 = Tag (Papier, Sonne),
# 1 = Nacht (Mond, Sterne). Die Karten werden dabei nicht abgedunkelt (06 Abschnitt 4.4: sonst wirkt das Neon matt).
# Tag: weiche goldene Sonnenstrahlen („Licht durch Dunst“, unterschiedliche Breiten und Längen, weich auslaufend), die sehr
# langsam atmen; motion = false (Effekte reduziert) hält sie und das Funkeln der Sterne an.
# Kontrollbilder: res://tests/test_ui_rays_shot.gd → docs/module/optik_strahlen_*.png.
#
# Zwischenbild (Gerätetest 0.1.1, M3): Der Shader rechnet nicht in jedem Bild für jedes Gerätepixel (am S21 2400 × 1080 bei
# 120 Hz waren das rund zwei Drittel der GPU-Last am Tisch), sondern in ein SubViewport in Basisauflösung (RENDER_SCALE je
# Einheit der Fläche, also 1600 × 720). Es wird REFRESH_HZ-mal pro Sekunde neu berechnet – die Strahlen wandern über Minuten,
# das Atmen dauert 15 s –, bei jeder Änderung (Tageszeit beim Flip, Größe, Tischmitte) sofort und ohne Daueranimation nur dann.
# Gezeichnet wird in jedem Bild nur noch das fertige Zwischenbild.

const SHADER := "res://assets/shaders/table_background.gdshader"
const REFRESH_HZ := 20.0
const RENDER_SCALE := 1.0

var tageszeit := 0.0: set = set_tageszeit
var table_center := Vector2(800, 320): set = set_table_center
var motion := true: set = set_motion
var calm := false: set = set_calm           # ruhige Variante (großer Modus): keine Strahlen, kaum Sterne, mehr Kontrast
var shader_material: ShaderMaterial      # Material des Shaders (liegt auf der Fläche im Zwischenbild)
var renders := 0                         # Anzahl Neuberechnungen (Tests)

var _vp: SubViewport
var _rect: ColorRect
var _dirty := true
var _since := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = UiPalette.PAPER
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_vp = SubViewport.new()
	_vp.name = "Zwischenbild"
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.size = Vector2i(16, 16)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp, false, Node.INTERNAL_MODE_FRONT)
	_rect = ColorRect.new()
	_rect.color = Color.WHITE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp.add_child(_rect)
	var sh := load(SHADER) as Shader
	if sh != null:
		shader_material = ShaderMaterial.new()
		shader_material.shader = sh
		_rect.material = shader_material
	resized.connect(_update_size)
	visibility_changed.connect(refresh)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_update_size()
	set_tageszeit(tageszeit)
	_render()


func set_tageszeit(v: float) -> void:
	tageszeit = clampf(v, 0.0, 1.0)
	color = UiPalette.PAPER.lerp(UiPalette.NIGHT_HI, tageszeit)
	_param("tageszeit", tageszeit)


func set_table_center(p: Vector2) -> void:
	table_center = p
	_param("center", p)


func set_calm(on: bool) -> void:
	calm = on
	_param("calm", 1.0 if on else 0.0)


func set_motion(on: bool) -> void:
	motion = on
	_param("motion", 1.0 if on else 0.0)


# Im nächsten Bild neu berechnen (z. B. nachdem Kontrollbilder das Material von außen geändert haben)
func refresh() -> void:
	_dirty = true


func _update_size() -> void:
	var px := Vector2i(maxi(1, ceili(size.x * RENDER_SCALE)), maxi(1, ceili(size.y * RENDER_SCALE)))
	if _vp.size != px:
		_vp.size = px
	_rect.position = Vector2.ZERO
	_rect.size = Vector2(px)
	_param("size", size)
	queue_redraw()


func _param(name: String, value: Variant) -> void:
	if shader_material != null:
		shader_material.set_shader_parameter(name, value)
	_dirty = true


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_since += delta
	if _dirty or (motion and _since >= 1.0 / REFRESH_HZ):
		_render()


func _render() -> void:
	_dirty = false
	_since = 0.0
	renders += 1
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _draw() -> void:
	draw_texture_rect(_vp.get_texture(), Rect2(Vector2.ZERO, size), false)
