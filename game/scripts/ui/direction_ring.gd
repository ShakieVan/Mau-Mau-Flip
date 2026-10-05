class_name DirectionRing
extends Node2D
# Richtungsring um die Tischmitte (06 Abschnitt 3.4/4.2): zwei leuchtende Ellipsenbögen mit Pfeilspitzen wie im Entwurf, dazu
# wandernde Winkel, die die Spielrichtung zeigen. speed > 0 = im Uhrzeigersinn (Richtung 1, zum linken Nachbarn).
# Richtungswechsel: Der Ring bremst, steht kurz und läuft mit Überschwinger rückwärts an (Tween über speed durch 0).
# Ursprung = Tischmitte.

const ARC_TOP := Vector2(198.0, 342.0)       # Grad (0 = rechts, Bildschirmwinkel, y nach unten)
const ARC_BOTTOM := Vector2(18.0, 162.0)
const CHEVRON_GAP := 46.0                    # px zwischen den wandernden Winkeln

var radii := Vector2(330, 160): set = set_radii
var speed := 1.0: set = set_speed
var color := UiPalette.RING: set = set_color
var animate := true                         # false: stehend (Effekte reduziert bleibt animiert; nur Tests/Standbilder)
var flash := 0.0: set = set_flash           # kurzes Aufleuchten (Richtungswechsel, Neon zündet)

var _phase := 0.0
var _tween: Tween


func set_radii(r: Vector2) -> void:
	radii = r
	queue_redraw()


func set_speed(v: float) -> void:
	speed = v
	queue_redraw()


func set_color(c: Color) -> void:
	color = c
	queue_redraw()


func set_flash(v: float) -> void:
	flash = v
	queue_redraw()


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
	if animate:
		_phase = fposmod(_phase + delta * speed * 38.0, CHEVRON_GAP)
		queue_redraw()


func point_at(deg: float) -> Vector2:
	var a := deg_to_rad(deg)
	return Vector2(cos(a) * radii.x, sin(a) * radii.y)


func _arc_points(a0: float, a1: float, steps := 48) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		pts.append(point_at(lerpf(a0, a1, float(i) / steps)))
	return pts


func _draw() -> void:
	var glow := Color(color, 0.16 + 0.22 * flash)
	var line := Color(color, 0.55 + 0.4 * flash)
	for arc in [ARC_TOP, ARC_BOTTOM]:
		var pts := _arc_points(arc.x, arc.y)
		draw_polyline(pts, glow, 12.0, true)
		draw_polyline(pts, line, 4.0, true)
		_draw_chevrons(pts)
		# Pfeilspitze am Ende in Laufrichtung, Größe folgt |speed| (bei Stillstand verschwindet sie)
		var s := clampf(absf(speed), 0.0, 1.3)
		if s > 0.04:
			var forward := speed > 0.0
			var tip_deg: float = arc.y if forward else arc.x
			var back_deg: float = tip_deg - (4.0 if forward else -4.0)
			var tip := point_at(tip_deg)
			var dirv := (tip - point_at(back_deg)).normalized()
			var nrm := Vector2(-dirv.y, dirv.x)
			var size := 22.0 * s
			var a := tip - dirv * size + nrm * size * 0.62
			var b := tip - dirv * size - nrm * size * 0.62
			draw_polyline(PackedVector2Array([a, tip, b]), glow, 12.0, true)
			draw_polyline(PackedVector2Array([a, tip, b]), line, 4.0, true)


# Kleine Winkel entlang des Bogens, die mit der Spielrichtung wandern
func _draw_chevrons(pts: PackedVector2Array) -> void:
	var total := 0.0
	var lengths := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
		lengths.append(total)
	var col := Color(color, (0.22 + 0.3 * flash) * clampf(absf(speed) * 1.5, 0.0, 1.0))
	if col.a < 0.02:
		return
	var d := _phase + 14.0
	var j := 1
	while d < total - 14.0:
		while j < lengths.size() - 1 and lengths[j] < d:
			j += 1
		var t := (d - lengths[j - 1]) / maxf(lengths[j] - lengths[j - 1], 0.001)
		var p := pts[j - 1].lerp(pts[j], t)
		var dirv := (pts[j] - pts[j - 1]).normalized() * (1.0 if speed >= 0.0 else -1.0)
		var nrm := Vector2(-dirv.y, dirv.x)
		var inner := p - p.normalized() * 14.0     # etwas nach innen versetzt
		draw_polyline(PackedVector2Array([inner - dirv * 5.0 + nrm * 5.0, inner + dirv * 1.0, inner - dirv * 5.0 - nrm * 5.0]), col, 2.5, true)
		d += CHEVRON_GAP
