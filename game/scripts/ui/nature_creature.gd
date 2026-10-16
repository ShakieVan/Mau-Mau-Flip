class_name NatureCreature
extends Node2D
# Mau-Mau Flip (Beta 1.6.12): Grundklasse aller Tiere der „Natur-Überraschungen“ (docs/module/natur.md Abschnitt 7.1, Aufgabe T1).
# Die Tiere stehen in nature_day.gd / nature_night.gd (je Tier eine innere Klasse, extends preload("res://scripts/ui/nature_creature.gd"))
# und werden von NatureFx über deren static func make(id) -> NatureCreature gefunden.
#
# Vertrag für ein Tier:
#   setup(ctx)   einmal beim Start: würfelt nur aus rng (eigener Samen), setzt dur (vorbelegt aus der Tabelle), in_s/out_s, Bahnen …
#   pose_at(t)   reiner Zustand zur Zeit t (Sekunden ab Start): gleicher Samen + gleiches t = gleiches Bild (seek für Tests und
#                Kontrollbilder). Setzt nur Felder, die _draw liest, und alpha (Deckkraft 0 … 1). Reaktionen auf einen Tipp laufen als
#                eigene Zeitlinie ab tap_at, der schnelle Abgang ab leave_at (beide −1 = keiner); so bleibt seek eindeutig.
#   _draw()      zeichnet die Pose; Koordinaten = die des Elternknotens (Ebene; bei Ruhe gleich den Tisch-/Weltkoordinaten), der
#                Knoten selbst bleibt bei (0, 0). Additives Glühen: use_glow() in setup, dann _draw_glow() überschreiben und dort
#                glow(pos, r, col) rufen.
#   bounds()     sichtbare Hülle (Koordinaten der Ebene) zur aktuellen Pose; Rect2() = nichts zu sehen (Tests: Sichtbarkeit, deckt,
#                Scheu, Treffer).
#   optional: hit(p) (Standard: Abstand zur Mitte der Hülle ≤ max(treffer_min_r, halbe Hüllengröße)), on_tap(p) (Reaktion, nur bei
#                „tipp“ in der Tabelle, höchstens einmal; tap_at/tap_pos sind dann schon gesetzt), on_press(p) (Scheu: gleich danach
#                geht das Tier schnell), on_event(ev) -> bool (Spielereignis; true = schnell abgehen), on_leave() (Beginn des schnellen
#                Abgangs), leave_time(fast) (Dauer des schnellen Abgangs, Standard abgang_s; höchstens 0,5 s), own_leave = true, wenn
#                pose_at den Abgang selbst zeichnet (sonst blendet die Basis in leave_s aus).
# Keine CPUParticles2D: Teilchen sind eigene Listen (aus rng in setup), damit alles mit dem Samen festliegt. Kein Ton, keine Vibration,
# kein Text (Ausnahme: das gezeichnete „z“ am schlafenden Mond über UiFonts).
#
# ctx (beim Start von NatureFx berechnet, Weltkoordinaten = Tischkoordinaten bei Ruhe; Dictionary):
#   id, entry (Tabelleneintrag), size (Vector2 Tisch), center (Tischmitte), side ("tag"|"nacht"), night (0 … 1), reduced, calm (ruhige
#   Variante bei „Effekte reduziert“), timing (Tabelle „zeiten“), form (Sternbild oder {}), layer ("hinten"|"mitte"|"vorn"),
#   ort (Anker dieses Eintrags), anchors (alle Anker, Abschnitt 2.2), band (Callable(deg, quer := 0.5) -> Vector2: Punkt auf der
#   Richtungs-Plattform; 0° rechts, 90° vorn, im Uhrzeigersinn; quer 0 Innenkante … 1 Außenkante), ring_radii (TableLayout.ring_radii),
#   seats ([{seat, pos, rect, me}] Köpfe), obstacles ({Name: [Rect2]} Schutzflächen, Abschnitt 2.3), free (Callable(Rect2) -> float:
#   Überdeckung mit Schutzflächen in px²), hand (Callable() -> Dictionary: mittlere sichtbare Handkarte {id, pos, rot, size, xf
#   (Kartenmitte-System → Welt), rect} oder {}), troedler (Platz der Schnecke), my_seat, demo (Vorführung).
# Anker (anchors): himmel/himmel_oben/himmel_fern/tisch_quer Rect2; himmel_frei Rect2 (240 × 160); himmel_bogen {center, r};
#   sonne {pos, r}; mond {pos, r, cut} (Sichel: Kreis r um pos minus Kreis um pos + cut); band_hinten/band_schulter/band_vorn_seite
#   {deg}; band_zum_platz {deg, seat}; tisch_rund {center, radii, f0, f1, ymax}; handkarte (wie hand()); stapel_oben {pos, pile
#   (Rect2)}; ablage_ring {pos, r}; aufsteigend {pos, target_y}.

const NT := preload("res://scripts/ui/nature_table.gd")
const INK := UiPalette.INK
const PAPER := UiPalette.PAPER
const PAPER_D := UiPalette.PAPER_D
const CREAM := UiPalette.CREAM
const NIGHT := UiPalette.NIGHT
const RING := UiPalette.RING
const MOON := UiPalette.MOON
const TURN := UiPalette.TURN

var id := ""
var fx: Object = null                 # NatureFx (untypisiert: kein Ring der Skriptabhängigkeiten)
var entry: Dictionary = {}
var rng := RandomNumberGenerator.new()
var seed_value := 0
var t := 0.0
var dur := 8.0
var night := 0.0
var reduced := false
var calm := false
var ctx: Dictionary = {}
var layer := "mitte"
var in_s := 1.0                       # Anflug bzw. Einblenden (danach beginnt die Hauptphase)
var out_s := 1.0                      # Abflug bzw. Ausblenden am Ende (Hauptphase endet bei dur − out_s)
var alpha := 1.0                      # Deckkraft aus pose_at (die Basis multipliziert die Blende des schnellen Abgangs)
var tap_at := -1.0                    # Zeit des Tipps (Reaktion), −1 = keiner
var tap_pos := Vector2.ZERO
var leave_at := -1.0                  # Beginn des schnellen Abgangs, −1 = keiner
var leave_s := 0.4
var leave_fast := true
var own_leave := false                # true: pose_at zeichnet den Abgang selbst (sonst blendet die Basis in leave_s aus)
var glow_layer: Node2D                # additive Kindebene (use_glow)
var _gl: CanvasItem = null            # Ziel von glow() während _draw_glow


# Von NatureFx gerufen (nicht überschreiben): Samen, Zustand, dann setup und die erste Pose
func init_creature(p_id: String, p_seed: int, p_ctx: Dictionary, p_fx: Object = null) -> void:
	id = p_id
	seed_value = p_seed
	rng.seed = p_seed
	ctx = p_ctx
	fx = p_fx
	entry = p_ctx.get("entry", NT.entry(p_id))
	night = float(p_ctx.get("night", 0.0))
	reduced = bool(p_ctx.get("reduced", false))
	calm = bool(p_ctx.get("calm", false))
	layer = str(p_ctx.get("layer", entry.get("ebene", "mitte")))
	leave_s = float(NT.timing("abgang_s"))
	var d: Array = entry.get("dauer", [8.0, 8.0])
	dur = rng.randf_range(float(d[0]), float(d[1]))
	name = "Natur_" + p_id
	setup(p_ctx)
	seek(0.0)


# ---------------------------------------------------------------- Vertrag (überschreiben)

func setup(_c: Dictionary) -> void:
	pass


func pose_at(_tt: float) -> void:
	pass


func bounds() -> Rect2:
	return Rect2()


func on_tap(_p: Vector2) -> void:
	pass


func on_press(_p: Vector2) -> void:
	pass


func on_event(_ev: Dictionary) -> bool:
	return false


func on_leave() -> void:
	pass


func leave_time(_fast: bool) -> float:
	return float(NT.timing("abgang_s"))


func _draw_glow() -> void:
	pass


# ---------------------------------------------------------------- Ablauf (von NatureFx)

func step(dt: float) -> void:
	if is_done():
		return
	t += dt
	_apply()


func seek(tt: float) -> void:
	t = maxf(tt, 0.0)
	_apply()


func _apply() -> void:
	alpha = 1.0
	pose_at(t)
	modulate.a = clampf(alpha * leave_fade(), 0.0, 1.0)
	queue_redraw()
	if glow_layer != null:
		glow_layer.modulate.a = modulate.a
		glow_layer.queue_redraw()


# Blende des schnellen Abgangs (1 = keiner; own_leave: immer 1)
func leave_fade() -> float:
	if leave_at < 0.0 or own_leave:
		return 1.0
	return clampf(1.0 - (t - leave_at) / maxf(leave_s, 0.01), 0.0, 1.0)


func leaving() -> bool:
	return leave_at >= 0.0


func tapped() -> bool:
	return tap_at >= 0.0


# Schnell abgehen (wegfliegen bzw. ausblenden); ein zweiter Aufruf ändert nichts
func leave(fast := true) -> void:
	if leave_at >= 0.0 or is_done():
		return
	leave_fast = fast
	leave_at = t
	leave_s = clampf(leave_time(fast), 0.05, 1.5)
	on_leave()
	_apply()


func end_time() -> float:
	return leave_at + leave_s if leave_at >= 0.0 else dur


func is_done() -> bool:
	return t >= end_time()


# "in" | "main" | "leave" | "done"
func phase() -> String:
	if is_done():
		return "done"
	if leave_at >= 0.0 or t >= dur - out_s:
		return "leave"
	if t < in_s:
		return "in"
	return "main"


# Zeit seit dem Tipp (−1 = kein Tipp oder vor dem Tipp) bzw. seit dem Abgang
func since_tap(tt := -1.0) -> float:
	var x := t if tt < 0.0 else tt
	return x - tap_at if tap_at >= 0.0 and x >= tap_at else -1.0


func since_leave(tt := -1.0) -> float:
	var x := t if tt < 0.0 else tt
	return x - leave_at if leave_at >= 0.0 and x >= leave_at else -1.0


# Tipp p (Koordinaten der Ebene) trifft das Tier
func hit(p: Vector2) -> bool:
	var b := bounds()
	if not b.has_area() or modulate.a < 0.05:
		return false
	var r := maxf(float(NT.timing("treffer_min_r")), maxf(b.size.x, b.size.y) * 0.5)
	return p.distance_to(b.get_center()) <= r


# Punkt auf der Richtungs-Plattform (siehe ctx.band)
func band(deg: float, quer := 0.5) -> Vector2:
	var cb: Variant = ctx.get("band")
	if cb is Callable and (cb as Callable).is_valid():
		return (cb as Callable).call(deg, quer)
	return Vector2(ctx.get("center", Vector2(800, 320))) + Vector2(cos(deg_to_rad(deg)) * 345.0, sin(deg_to_rad(deg)) * 160.0)


func table_size() -> Vector2:
	return ctx.get("size", Vector2(1600, 720))


# Höhe / 720 (Größenmaß wie bei den übrigen Effekten)
func k() -> float:
	return clampf(table_size().y / 720.0, 0.8, 1.6)


# ---------------------------------------------------------------- Glühen (additive Kindebene)

func use_glow() -> void:
	if glow_layer != null:
		return
	glow_layer = Node2D.new()
	glow_layer.name = "Gluehen"
	glow_layer.material = TableEffects.additive()
	glow_layer.show_behind_parent = false
	glow_layer.draw.connect(_on_glow_draw)
	add_child(glow_layer)


func _on_glow_draw() -> void:
	_gl = glow_layer
	_draw_glow()
	_gl = null


# Weicher Lichtpunkt mit Radius r (in _draw_glow additiv, sonst normal gemischt auf dem Tier)
func glow(pos: Vector2, r: float, col: Color) -> void:
	var ci: CanvasItem = _gl if _gl != null else self
	ci.draw_texture_rect(TableEffects.glow_texture(), Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0), false, col)


# ---------------------------------------------------------------- Zeichenhilfen

static func ellipse_points(c: Vector2, rx: float, ry: float, rot := 0.0, n := 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var xf := Transform2D(rot, c)
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(xf * Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func poly_ellipse(c: Vector2, rx: float, ry: float, col: Color, rot := 0.0, n := 24) -> void:
	if rx <= 0.05 or ry <= 0.05:
		return
	draw_colored_polygon(ellipse_points(c, rx, ry, rot, n), col)


# Ellipse mit Kontur (Fläche + geschlossene Linie)
func ellipse_outlined(c: Vector2, rx: float, ry: float, fill: Color, line: Color, w := 1.5, rot := 0.0, n := 24) -> void:
	if rx <= 0.05 or ry <= 0.05:
		return
	var pts := ellipse_points(c, rx, ry, rot, n)
	draw_colored_polygon(pts, fill)
	outline_poly(pts, line, w)


func tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([a, b, c]), col)


# Geschlossene Linie um ein Polygon
func outline_poly(pts: PackedVector2Array, col: Color, w := 1.5) -> void:
	if pts.size() < 2:
		return
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, col, w, true)


# Flügel als Ellipse, die an base ansetzt und in Richtung angle zeigt (Länge len, Breite width); Kontur optional
func wing(base: Vector2, length: float, width: float, angle: float, col: Color, line := Color(0, 0, 0, 0), w := 1.0) -> void:
	if length <= 0.1 or width <= 0.05:
		return
	var c := base + Vector2.from_angle(angle) * length * 0.5
	var pts := ellipse_points(c, length * 0.5, width * 0.5, angle, 20)
	draw_colored_polygon(pts, col)
	if line.a > 0.0:
		outline_poly(pts, line, w)


# Polygon mit Kontur; Punkte im System xf (z. B. Transform2D(rot, pos).scaled …)
func poly_xf(pts: PackedVector2Array, xf: Transform2D, fill: Color, line := Color(0, 0, 0, 0), w := 1.5) -> void:
	var p := xf * pts
	if p.size() >= 3:
		draw_colored_polygon(p, fill)
	if line.a > 0.0:
		outline_poly(p, line, w)


# Farbe mit Deckkraft a (Abkürzung)
static func ca(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * clampf(a, 0.0, 1.0))


# Glatter Übergang 0 … 1 über [a, b]
static func ramp(x: float, a: float, b: float) -> float:
	if b <= a:
		return 1.0 if x >= b else 0.0
	return smoothstep(a, b, x)


# Ein- und Ausblenden über in_s/out_s an den Rändern von [0, dur]
func edge_fade(tt: float) -> float:
	var a := 1.0 if in_s <= 0.0 else clampf(tt / in_s, 0.0, 1.0)
	var b := 1.0 if out_s <= 0.0 else clampf((dur - tt) / out_s, 0.0, 1.0)
	return minf(a, b)


# Hülle eines Punkts mit halber Größe he (Koordinaten der Ebene)
static func box(c: Vector2, he: Vector2) -> Rect2:
	return Rect2(c - he, he * 2.0)
