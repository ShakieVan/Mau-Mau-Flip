extends Node2D
# Sternschnuppe am Tischhimmel (Beta 1.6.11, Nutzerwunsch „nachts leuchtender“; vorher ein weißer Strich mit Punkt in fun_fx.gd).
# Im Stil der Funkelsterne am Partie-Ende (SparkleShowerFx): heller Kopf mit Lichthof und feinen Strahlen, die leicht funkeln,
# ein langer Schweif mit Farbverlauf (weiß → gold → eisblau → violett), der hinter dem Kopf weich ausglüht (jede Stelle verlischt
# mit ihrem Alter, auch nachdem der Kopf verglüht ist), und kleine Funken, die vom Kopf abfallen, flackern und verglimmen.
# Am Ende verglüht der Kopf mit einem kurzen Aufblitzen und einem Funkenkranz.
#   glow ≥ 0.5 (Nacht): additiv gemischt, volle Helligkeit (glow 0.5 … 1 regelt sie von 75 % auf 100 %).
#   glow < 0.5 (Tag; regulär fliegt tagsüber der Schmetterling): normal gemischt in Gold/Orange, schmaler, weniger Funken.
#   calm: ohne Funken und Funkeln (Effekte reduziert; derzeit startet FunFx im reduzierten Modus gar keinen Himmel).
# Kein Dauerlauf: Die Zeit schaltet SkyNode.step weiter; nach MOVE + AFTER Sekunden ist alles leer. Je Bild höchstens etwa
# 140 Kern- und 45 Glühstempel des Schweifs und MAX_SPARKS Funken, alle mit denselben zwei, drei Texturen (gebündelt).

const MOVE := 1.2            # Flugzeit des Kopfes (wie bis 1.6.10)
const AFTER := 0.75          # Ausglühen von Schweif und Funken danach
const TAIL := 0.6            # Schweiflänge als Anteil der Flugstrecke (bis 1.6.10: 0.3)
const TAIL_DECAY := 0.6      # Sekunden, bis eine Schweifstelle auf 1/e verglüht ist
const HEAD_OUT := 0.2        # Verglühen des Kopfes nach dem Ende der Flugbahn
const MAX_SPARKS := 90

const NIGHT_COLS := [Color(1.0, 1.0, 1.0), Color("#FFF1C2"), Color("#FFCF5A"), Color("#7FD4FF"), Color("#A77BFF")]
const DAY_COLS := [Color("#FFC23A"), Color("#FFA51E"), Color("#FF8A3D"), Color("#F86F6F"), Color("#E26AA8")]
const NIGHT_SPARK := [Color.WHITE, Color("#FFE9A0"), Color("#FFD66B"), Color("#FFC400"), Color("#BFE8FF"), Color("#FFB3E6")]
const DAY_SPARK := [Color("#FFB21E"), Color("#FF9A2E"), Color("#FFC94A"), Color("#FF7A59")]

var p0 := Vector2.ZERO
var p1 := Vector2.ZERO
var glow := 1.0
var calm := false
var k := 1.0                 # Größe (Tischhöhe / 720)
var t := 0.0
var running := false
var sparks: Array = []       # je Funke: [Ort, Tempo, Alter, Lebensdauer, Größe, Farbe, Flackertempo, Phase, Strahlen]
var sparks_made := 0         # Tests/Zähler
var _rng := RandomNumberGenerator.new()
var _emit := 0.0
var _burst := false
var _add: CanvasItemMaterial


func start(from: Vector2, to: Vector2, glow_v: float, rng: RandomNumberGenerator, table_h := 720.0) -> void:
	p0 = from
	p1 = to
	glow = clampf(glow_v, 0.0, 1.0)
	k = clampf(table_h / 720.0, 0.8, 1.6)
	t = 0.0
	sparks.clear()
	sparks_made = 0
	_emit = 0.0
	_burst = false
	_rng.seed = rng.randi()
	running = true
	visible = true
	if is_night():
		if _add == null:
			_add = CanvasItemMaterial.new()
			_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = _add
	else:
		material = null
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	queue_redraw()


func clear() -> void:
	running = false
	sparks.clear()
	visible = false


func is_night() -> bool:
	return glow >= 0.5


func total() -> float:
	return MOVE + AFTER


# Wegstück (0 … 1) des Kopfes zur Zeit tt: bremst zum Ende hin ab wie bis 1.6.10
static func ease_at(tt: float) -> float:
	var u := clampf(tt / MOVE, 0.0, 1.0)
	return u * (2.0 - u)


# Zeitpunkt, zu dem der Kopf das Wegstück s erreicht hat (Umkehrung von ease_at)
static func time_of(s: float) -> float:
	return (1.0 - sqrt(maxf(0.0, 1.0 - clampf(s, 0.0, 1.0)))) * MOVE


func head_pos() -> Vector2:
	return p0.lerp(p1, ease_at(t))


# Helligkeit des Kopfes: rasch an, kurz vor dem Ende ein Aufflackern, dann verglüht er in HEAD_OUT
func head_bright() -> float:
	if t >= MOVE:
		return clampf(1.0 - (t - MOVE) / HEAD_OUT, 0.0, 1.0) * 1.35
	var u := t / MOVE
	return clampf(t / 0.1, 0.0, 1.0) * (1.0 + 0.35 * smoothstep(0.75, 1.0, u))


func step(delta: float) -> void:
	if not running:
		return
	t += delta
	if t >= total():
		clear()
		return
	var dir := (p1 - p0).normalized()
	var perp := Vector2(-dir.y, dir.x)
	# neue Funken am Kopf (abhängig vom Tempo des Kopfes: zum Ende hin weniger), am Ende ein kleiner Kranz
	if not calm and t < MOVE:
		var speed := 1.0 - t / MOVE
		_emit += delta * (48.0 if is_night() else 16.0) * (0.45 + 0.55 * speed)
		while _emit >= 1.0:
			_emit -= 1.0
			_spark(head_pos() + perp * _rng.randf_range(-3.0, 3.0) * k,
				-dir * _rng.randf_range(20.0, 90.0) * k + perp * _rng.randf_range(-38.0, 38.0) * k + Vector2(0, _rng.randf_range(0.0, 30.0) * k))
	if not calm and not _burst and t >= MOVE:
		_burst = true
		var n := 14 if is_night() else 6
		for i in n:
			var a := TAU * (float(i) + _rng.randf()) / float(n)
			_spark(head_pos(), Vector2.from_angle(a) * _rng.randf_range(35.0, 85.0) * k + dir * 25.0 * k)
	var i := 0
	while i < sparks.size():
		var sp: Array = sparks[i]
		sp[2] = float(sp[2]) + delta
		if float(sp[2]) >= float(sp[3]):
			sparks.remove_at(i)
			continue
		var v: Vector2 = sp[1]
		v = v * pow(0.25, delta) + Vector2(0, 70.0 * k) * delta     # Luftwiderstand, sanft nach unten
		sp[1] = v
		sp[0] = (sp[0] as Vector2) + v * delta
		i += 1
	queue_redraw()


func _spark(pos: Vector2, vel: Vector2) -> void:
	if sparks.size() >= MAX_SPARKS:
		return
	var pal: Array = NIGHT_SPARK if is_night() else DAY_SPARK
	sparks_made += 1
	sparks.append([pos, vel, 0.0, _rng.randf_range(0.35, 0.95), _rng.randf_range(6.0, 13.0) * k, pal[_rng.randi() % pal.size()],
		_rng.randf_range(22.0, 40.0), _rng.randf() * TAU, _rng.randf() < 0.35])


# Farbe des Schweifs an der Stelle x (0 = Kopf, 1 = Ende)
func _tail_col(x: float) -> Color:
	var cols: Array = NIGHT_COLS if is_night() else DAY_COLS
	var f := clampf(x, 0.0, 1.0) * float(cols.size() - 1)
	var j := mini(int(f), cols.size() - 2)
	return (cols[j] as Color).lerp(cols[j + 1], f - float(j))


func _draw() -> void:
	if not running:
		return
	var night := is_night()
	var gain := lerpf(0.75, 1.0, clampf((glow - 0.5) * 2.0, 0.0, 1.0)) if night else 1.0
	var day_k := 1.0 if night else 0.85          # tagsüber schmaler
	var glow_tex := TableEffects.glow_texture()
	var core_tex := TableEffects.sparkle_core_texture()
	var ray_tex := TableEffects.sparkle_ray_texture()
	var e_head := ease_at(t)
	var path := p1 - p0
	var plen := path.length()
	var tail := minf(TAIL, e_head)
	# ---- Schweif: Stempel entlang der Bahn; jede Stelle glüht nach ihrem Alter aus und läuft zum Ende spitz zu
	if tail > 0.0005 and plen > 1.0:
		var span := tail * plen
		var n_glow := clampi(int(span / 9.0), 4, 45)
		var n_core := clampi(int(span / 3.0), 8, 140)
		for pass_i in 2:
			var n := n_glow if pass_i == 0 else n_core
			for j in n:
				var x := (float(j) + 0.5) / float(n)                 # 0 Kopf … 1 Ende (bezogen auf die volle Länge TAIL)
				var s := e_head - x * tail
				var age := t - time_of(s)
				var xf := x * tail / TAIL
				var inten := exp(-age / TAIL_DECAY) * pow(1.0 - xf, 1.15)
				if inten < 0.01:
					continue
				var c := _tail_col(xf) if pass_i == 1 else _tail_col(minf(1.0, 0.18 + xf * 1.7))   # Lichthof schon farbig
				var pos := p0 + path * s
				var sz: float
				if pass_i == 0:
					sz = lerpf(46.0, 14.0, xf) * k * day_k
					c.a = clampf(inten * (0.42 if night else 0.35) * gain, 0.0, 1.0)
					draw_texture_rect(glow_tex, Rect2(pos - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, c)
				else:
					sz = lerpf(16.0, 4.0, xf) * k * day_k
					c.a = clampf(inten * (0.62 if night else 0.9) * gain, 0.0, 1.0)
					draw_texture_rect(core_tex, Rect2(pos - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, c)
	# ---- Funken
	for sp in sparks:
		var age: float = sp[2]
		var life: float = sp[3]
		var u := age / life
		var fl := 1.0 if calm else 0.6 + 0.4 * sin(age * float(sp[6]) + float(sp[7]))
		var a := pow(1.0 - u, 1.3) * fl * gain
		var c: Color = sp[5]
		var sz: float = float(sp[4]) * (1.0 - 0.45 * u)
		c.a = clampf(a * (1.0 if night else 0.85), 0.0, 1.0)
		var pos: Vector2 = sp[0]
		draw_texture_rect(core_tex, Rect2(pos - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, c)
		if bool(sp[8]):
			var rs := sz * 2.6
			draw_texture_rect(ray_tex, Rect2(pos - Vector2(rs, rs) * 0.5, Vector2(rs, rs)), false, c)
	# ---- Kopf: Lichthof, Strahlen (lang/kurz, funkelnd), Kern
	var hb := head_bright()
	if hb > 0.01:
		var h := head_pos()
		var tw := 1.0 if calm else 0.82 + 0.18 * sin(t * 31.0) * sin(t * 13.0 + 1.0)
		var warm := Color("#FFE7A8") if night else Color("#FFC53D")
		var halo := 78.0 * k * day_k * (0.85 + 0.15 * hb)
		var hc := warm
		hc.a = clampf(0.42 * hb * gain, 0.0, 1.0) if night else clampf(0.35 * hb, 0.0, 1.0)
		draw_texture_rect(glow_tex, Rect2(h - Vector2(halo, halo) * 0.5, Vector2(halo, halo)), false, hc)
		var inner := 30.0 * k * day_k
		var ic := Color.WHITE if night else Color("#FFB21E")
		ic.a = clampf(0.7 * hb * gain, 0.0, 1.0)
		draw_texture_rect(glow_tex, Rect2(h - Vector2(inner, inner) * 0.5, Vector2(inner, inner)), false, ic)
		var rot := 0.12                              # Strahlen fast achsparallel wie bei den Funkelsternen
		var rc := Color("#FFF6DC") if night else Color("#FF9A2E")
		rc.a = clampf(0.95 * hb * gain, 0.0, 1.0)
		var lng := 74.0 * k * day_k * tw * (0.8 + 0.2 * hb)
		draw_set_transform(h, rot, Vector2.ONE)
		draw_texture_rect(ray_tex, Rect2(-Vector2(lng, lng) * 0.5, Vector2(lng, lng)), false, rc)
		var sht := lng * 0.5 * (2.0 - tw)
		draw_set_transform(h, rot + PI * 0.25, Vector2.ONE)
		draw_texture_rect(ray_tex, Rect2(-Vector2(sht, sht) * 0.5, Vector2(sht, sht)), false, rc)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var cs := 26.0 * k * day_k
		var cc := Color.WHITE
		cc.a = clampf(hb * gain, 0.0, 1.0)
		draw_texture_rect(core_tex, Rect2(h - Vector2(cs, cs) * 0.5, Vector2(cs, cs)), false, cc)
