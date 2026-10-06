class_name DirectionRing
extends Node2D
# Richtungs-Plattform um die Tischmitte (06 Abschnitt 3.4/4.2): ein flacher, dicker Ring wie eine Bühne, die schräg von
# oben gesehen auf dem Tisch liegt – Oberseite als breites Band (vorn breiter, hinten perspektivisch schmaler), sichtbare
# Außenkante vorn und Innenkante hinten im Bühnenloch, weicher Schatten. Nachziehstapel und Ablage liegen im Loch.
# Auf der Oberseite fließen Winkel (Dreiergruppen) in Spielrichtung: speed > 0 = im Uhrzeigersinn (Richtung 1, zum linken
# Nachbarn). Richtungswechsel: Der Fluss bremst, steht kurz und läuft mit Überschwinger rückwärts an; die Winkel strecken sich
# dabei zu Balken und biegen sich in die neue Richtung (Tween über speed durch 0).
# Tag: dicker Karton in Creme mit Druckfarben-Kontur und Prägelinie, Winkel in Druckfarbe. Nacht: dunkles Glas mit Neonkante
# (Lila wie bisher, damit der Farbring an der Ablage die einzige Farbmarke bleibt), leuchtende Winkel; „flash“ glimmt einmal auf.
# Leistung: Das Netz wird nur bei neuer Größe/Variante berechnet (ein draw_mesh), je Bild ändert sich nur die Uniform „phase“.
# Effekte „reduziert“ (App.settings „effekte“): Winkel stehen still (Richtung und Wechsel bleiben sichtbar).
# Ursprung = Tischmitte; radii = Maß aus TableLayout.ring_radii (330 × 160 bei 1600 × 720), die Plattform skaliert damit
# (das Loch bleibt so weit, dass Stapel und Farbring hineinpassen). Kontrollbilder: tests/test_ui_platform_shot.gd.

enum Style { SLIM, WIDE }

const SHADER := "res://assets/shaders/direction_platform.gdshader"
const STYLE_DEFAULT := Style.WIDE            # Standard: B „breit“; A „schlank“ über Style.SLIM
# Maße bei radii = (330, 160): Loch (Innenkante der Oberseite; x Weltpixel, y halbe Höhe auf dem Bildschirm), Bandbreite
# (Weltpixel, an den Seiten so breit, vorn ≈ 0,78 ×, hinten ≈ 0,63 ×), Kantenhöhe, Zelllänge der Winkel
const STYLES := {
	Style.SLIM: {"hole": Vector2(372.0, 136.0), "band": 54.0, "wall": 12.0, "cell": 32.0},
	Style.WIDE: {"hole": Vector2(372.0, 136.0), "band": 66.0, "wall": 16.0, "cell": 38.0},
}
const TILT := 0.70                           # Stauchung der Tiefe (Blick schräg von oben)
const SQUARE := 2.5                          # Superellipse: 2 = Ellipse, größer = Stadion (Platz für den Farbring im Loch)
const PERSP := 0.11                          # Perspektive: vorn größer, hinten kleiner
const HOLE_DY := 6.0                         # Mitte des Lochs unter der Tischmitte (Platz für „Stapel · n“)
const HOLE_MIN_X := 326.0                    # schmale Bildschirme (16:9): Loch nicht enger, die Stapel rücken nicht zusammen
const SEGMENTS := 160
const FLOW_PX := 34.0                        # Fließtempo der Winkel in Weltpixeln je Sekunde
const GROUP := 5                             # Zellen je Gruppe (3 Winkel + 2 frei)
const SHADOW := Vector2(26.0, 20.0)          # Schattenbreite außen / innen (Weltpixel)
const QUIET := Vector2(95.0, 60.0)           # vorn Mitte unter der Hinweisleiste: Winkel gedämpft (halbe Breite, Übergang)

var radii := Vector2(330, 160): set = set_radii
var speed := 1.0: set = set_speed
var color := UiPalette.RING: set = set_color
var animate := true                         # false: Winkel stehen (Tests/Standbilder)
var flash := 0.0: set = set_flash           # kurzes Aufglimmen (Richtungswechsel, Neon zündet)
var style: Style = STYLE_DEFAULT: set = set_style
var reduced := false: set = set_reduced     # Effekte reduziert: kein Fluss
var night := 0.0                            # aus color abgeleitet (UiPalette.ring_color), siehe set_color

var _phase := 0.0
var _tween: Tween
var _mesh: ArrayMesh
var _mat: ShaderMaterial
var _cell := 36.0
var _center_pts := PackedVector2Array()     # Bandmitte auf dem Bildschirm (point_at)
var _verts := PackedVector2Array()          # nur während _rebuild
var _uvs := PackedVector2Array()
var _idx := PackedInt32Array()


func _init() -> void:
	var sh := load(SHADER) as Shader
	if sh != null:
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		material = _mat
	_rebuild()
	_apply_color()
	_param("bend", speed)
	_param("flash", flash)


func _ready() -> void:
	reduced = UiApp.reduced_effects()
	var app := UiApp.app()
	var st: Variant = app.get("settings") if app != null else null
	if st is Object and (st as Object).has_signal("changed"):
		(st as Object).connect("changed", _on_setting_changed)


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "effekte":
		reduced = str(value) == "reduziert"


func set_radii(r: Vector2) -> void:
	if r == radii and _mesh != null:
		return
	radii = r
	_rebuild()


func set_style(s: Style) -> void:
	style = s
	_rebuild()


func set_reduced(on: bool) -> void:
	reduced = on


func set_speed(v: float) -> void:
	speed = v
	_param("bend", v)


func set_color(c: Color) -> void:
	color = c
	_apply_color()


func set_flash(v: float) -> void:
	flash = v
	_param("flash", v)


func set_direction(dir: int) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	speed = 1.0 if dir >= 0 else -1.0


# Richtungswechsel animiert; liefert die Dauer
func reverse_to(dir: int, duration := 1.0) -> float:
	var target := 1.0 if dir >= 0 else -1.0
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "speed", 0.0, duration * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(self, "flash", 1.0, duration * 0.35)
	_tween.tween_interval(duration * 0.15)
	_tween.tween_property(self, "speed", target, duration * 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(self, "flash", 0.0, duration * 0.5)
	return duration


func _process(delta: float) -> void:
	if animate and not reduced and speed != 0.0:
		_phase = fposmod(_phase + delta * speed * FLOW_PX / _cell, float(GROUP))
		_param("phase", _phase)


# Punkt auf der Mitte des Bands (Bildschirmwinkel in Grad, 0 = rechts, im Uhrzeigersinn)
func point_at(deg: float) -> Vector2:
	if _center_pts.is_empty():
		var a := deg_to_rad(deg)
		return Vector2(cos(a) * radii.x, sin(a) * radii.y)
	var i := int(round(fposmod(deg, 360.0) / 360.0 * SEGMENTS)) % SEGMENTS
	return _center_pts[i]


# ----------------------------------------------------------------- Farbe und Tageszeit

func _apply_color() -> void:
	# night aus der Ringfarbe von TableView (UiPalette.ring_color: Tagbraun → Lavendel); eigene Farben gelten als Neonfarbe
	var day := UiPalette.ring_color(0.0)
	var axis := Vector3(UiPalette.RING.r - day.r, UiPalette.RING.g - day.g, UiPalette.RING.b - day.b)
	var rel := Vector3(color.r - day.r, color.g - day.g, color.b - day.b)
	night = clampf(rel.dot(axis) / maxf(axis.length_squared(), 1e-6), 0.0, 1.0)
	var on_curve := UiPalette.ring_color(night)
	var neon := UiPalette.RING
	if Vector3(color.r - on_curve.r, color.g - on_curve.g, color.b - on_curve.b).length() > 0.06:
		neon = color
	_param("night", night)
	_param("neon", Color(neon, 1.0))


func _param(name: String, value: Variant) -> void:
	if _mat != null:
		_mat.set_shader_parameter(name, value)


# ----------------------------------------------------------------- Netz (einmal je Größe/Variante)

# Weltpunkt (x, z; z > 0 = vorn) auf den Bildschirm; drop = Abstand unter der Oberseite (0 = oben, Kantenhöhe = Tisch)
func _proj(p: Vector2, drop: float, zref: float, yoff: float) -> Vector2:
	var s := 1.0 / (1.0 - PERSP * p.y / zref)
	return Vector2(p.x * s, (TILT * p.y + drop) * s + yoff)


func _rebuild() -> void:
	var st: Dictionary = STYLES[style]
	var fx := radii.x / 330.0
	var fy := radii.y / 160.0
	var hole: Vector2 = st["hole"]
	var ai := maxf(hole.x * fx, HOLE_MIN_X)
	var bi := hole.y * fy / TILT
	var band: float = float(st["band"]) * minf(fx, fy)
	var wall: float = float(st["wall"]) * fy
	var zref := bi + band
	# Mitte des Lochs auf HOLE_DY legen (die Perspektive verschiebt sie sonst nach unten)
	var yf := _proj(Vector2(0, bi), 0.0, zref, 0.0).y
	var yb := _proj(Vector2(0, -bi), 0.0, zref, 0.0).y
	var yoff := HOLE_DY * fy - (yf + yb) * 0.5

	var n := SEGMENTS
	var inner := PackedVector2Array()
	var nrm := PackedVector2Array()
	for i in n + 1:
		var t := TAU * float(i) / n
		var c := cos(t)
		var s := sin(t)
		var q := Vector2(ai * signf(c) * pow(absf(c), 2.0 / SQUARE), bi * signf(s) * pow(absf(s), 2.0 / SQUARE))
		inner.append(q)
		nrm.append(Vector2(signf(q.x) * pow(absf(q.x) / ai, SQUARE - 1.0) / ai, signf(q.y) * pow(absf(q.y) / bi, SQUARE - 1.0) / bi).normalized())
	# Lauflänge längs der Bandmitte (Welt) → Zellen; ganze Zahl von Gruppen, damit die Naht nicht springt
	var cum := PackedFloat32Array([0.0])
	var total := 0.0
	for i in range(1, n + 1):
		total += (inner[i] + nrm[i] * band * 0.5).distance_to(inner[i - 1] + nrm[i - 1] * band * 0.5)
		cum.append(total)
	var cell_target: float = float(st["cell"]) * minf(fx, fy)
	var cells := maxi(GROUP, int(round(total / (cell_target * GROUP))) * GROUP)
	_cell = total / cells

	_verts = PackedVector2Array()
	_uvs = PackedVector2Array()
	_idx = PackedInt32Array()
	var u := PackedFloat32Array()
	for i in n + 1:
		u.append(cum[i] / total * cells)
	var top_in := PackedVector2Array()
	var top_out := PackedVector2Array()
	var foot_in := PackedVector2Array()
	var foot_out := PackedVector2Array()
	var sh_out_a := PackedVector2Array()
	var sh_out_b := PackedVector2Array()
	var sh_in_a := PackedVector2Array()
	var sh_in_b := PackedVector2Array()
	_center_pts = PackedVector2Array()
	var light_off := Vector2(9.0, 7.0) * fy
	for i in n + 1:
		var pi_ := inner[i]
		var po := inner[i] + nrm[i] * band
		top_in.append(_proj(pi_, 0.0, zref, yoff))
		top_out.append(_proj(po, 0.0, zref, yoff))
		foot_in.append(_proj(pi_, wall, zref, yoff))
		foot_out.append(_proj(po, wall, zref, yoff))
		sh_out_a.append(_proj(po - nrm[i] * 6.0, wall, zref, yoff))
		sh_out_b.append(_proj(po + nrm[i] * SHADOW.x * fy, wall, zref, yoff) + light_off)
		sh_in_a.append(_proj(pi_ + nrm[i] * 3.0, wall, zref, yoff))
		sh_in_b.append(_proj(pi_ - nrm[i] * SHADOW.y * fy, wall, zref, yoff) + light_off * 0.5)
		if i < n:
			_center_pts.append(_proj(inner[i] + nrm[i] * band * 0.5, 0.0, zref, yoff))
	# Zeichenreihenfolge: Schatten, Kanten, Oberseite
	_add_strip(sh_out_a, sh_out_b, 3, u)
	_add_strip(sh_in_a, sh_in_b, 4, u)
	_add_strip(top_out, foot_out, 1, u)
	_add_strip(top_in, foot_in, 2, u)
	_add_strip(top_in, top_out, 0, u)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _idx
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_verts = PackedVector2Array()
	_uvs = PackedVector2Array()
	_idx = PackedInt32Array()

	# Halbachsen der Bandmitte (Lichtrichtung im Shader) und Maße für die Winkel
	var ex := 0.0
	var ey_min := 0.0
	var ey_max := 0.0
	for p in _center_pts:
		ex = maxf(ex, absf(p.x))
		ey_min = minf(ey_min, p.y)
		ey_max = maxf(ey_max, p.y)
	_param("ell", Vector2(ex, (ey_max - ey_min) * 0.5))
	_param("ell_center", Vector2(0.0, (ey_max + ey_min) * 0.5))
	_param("square", SQUARE)
	_param("quiet", Vector2(QUIET.x * fx, QUIET.y * fx))
	_param("cell_px", _cell)
	_param("band_px", band)
	_param("wall_px", wall * 1.08)
	_param("group", float(GROUP))
	_param("phase", _phase)
	queue_redraw()


# Streifen zwischen zwei Kurven (je SEGMENTS + 1 Punkte); UV = (Lauf in Zellen, Teil * 2 + v)
func _add_strip(a: PackedVector2Array, b: PackedVector2Array, part: int, u: PackedFloat32Array) -> void:
	var base := _verts.size()
	for i in a.size():
		_verts.append(a[i])
		_uvs.append(Vector2(u[i], part * 2.0))
		_verts.append(b[i])
		_uvs.append(Vector2(u[i], part * 2.0 + 1.0))
	for i in a.size() - 1:
		var k := base + i * 2
		_idx.append(k)
		_idx.append(k + 1)
		_idx.append(k + 3)
		_idx.append(k)
		_idx.append(k + 3)
		_idx.append(k + 2)


func _draw() -> void:
	if _mesh != null:
		draw_mesh(_mesh, null)
