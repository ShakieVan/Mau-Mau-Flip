class_name FunFx
extends Node
# Ostereier am Tisch (Beta 1.4.4, nur lokal je Gerät, nichts davon geht über das Netz):
#  1. Mau-Katze: Braucht ein Spieler (auch man selbst) länger als CAT_WAIT_S für seinen Zug, tapst manchmal (CAT_CHANCE, höchstens
#     einmal je Spieler und Partie) eine kleine Katze über den Tisch und legt sich auf den Ziehstapel. Ein Tipp auf die Katze
#     schiebt sie weg (sie springt beleidigt davon). Beim nächsten Zug (oder Rundenende) steht sie auf und geht. Sie blockiert nichts:
#     Das Ziehen funktioniert überall außer genau auf der Katze.
#  2. Himmel: nachts gelegentlich eine Sternschnuppe, tagsüber ein Schmetterling, alle SKY_MIN_S … SKY_MAX_S Sekunden, nur wenn
#     keine Animation läuft; die Knoten liegen hinter den Karten.
#  3. Kommentar-Stempel: „Autsch!“, wenn jemand mit 1 Karte eine Strafe von 2 oder mehr Karten bekommt (+5, Wünscher +2, Farbjagd);
#     kurzer Applaus (gezeichnete Hände) bei „Mau-Mau!“.
# „Effekte reduziert“: Katze, Schmetterling und Sternschnuppe aus, der Stempel erscheint ohne Aufsetzen, der Applaus steht still.
# Der Tisch (TableView) ruft nur: mount, set_pile, on_view, on_event, tap. Die Uhr läuft über _process; Tests schalten
# auto_process aus und rufen tick(delta).

const CAT_WAIT_S := 25.0
const CAT_CHANCE := 0.4
const SKY_MIN_S := 60.0
const SKY_MAX_S := 180.0
const SKY_RETRY_S := 5.0
const CAT_SPEED := 150.0
const CAT_FLEE_SPEED := 430.0

const FUR := Color("#C98A4B")
const FUR_DARK := Color("#8A5528")
const FUR_LIGHT := Color("#F3DDBB")
const OUTLINE := Color("#211B2C")
const PINK := Color("#F2A3B5")

var table: Control
var rng := RandomNumberGenerator.new()
var auto_process := true
var reduced := false
var night := 0.0
var big := false
var enabled := true
var cat_chance := CAT_CHANCE
var busy_override := -1              # Tests: 0/1 statt der Frage an die Tischregie
var now := 0.0                       # Uhr des Ostereis (Sekunden, nur über tick)
var cat: CatNode
var sky: SkyNode
var cat_used := {}                   # Platz → true: Die Katze war in dieser Partie bei ihm
var cats_started := 0                # Tests/Zähler
var sky_started := 0
var stamps := 0
var applauses := 0

var _turn_since := 0.0
var _sig := ""
var _turn_seat := -1
var _playing := false
var _rolled := false                 # für den laufenden Zug schon gewürfelt
var _sky_due := 0.0
var _pile_pos := Vector2(623, 320)
var _pile_w := 116.0


func _init() -> void:
	rng.randomize()
	_sky_due = rng.randf_range(SKY_MIN_S, SKY_MAX_S)


# Knoten einhängen: Himmel direkt hinter dem Hintergrund, die Katze in die Welt (über Ablage, unter der Hand).
func mount(t: Control, bg: Node, world: Node2D) -> void:
	table = t
	t.add_child(self)
	sky = SkyNode.new()
	sky.name = "FunHimmel"
	t.add_child(sky)
	t.move_child(sky, bg.get_index() + 1)
	cat = CatNode.new()
	cat.name = "FunKatze"
	cat.visible = false
	cat.zzz_cb = _zzz
	world.add_child(cat)


func set_pile(pos: Vector2, w: float) -> void:
	_pile_pos = pos
	_pile_w = w


func set_reduced(on: bool) -> void:
	reduced = on
	if on and cat != null:
		cat.hide_now()
	if on and sky != null:
		sky.stop()


func set_night(v: float) -> void:
	night = v
	if cat != null:
		cat.night = v


func _process(delta: float) -> void:
	if auto_process:
		tick(delta)


func is_busy() -> bool:
	if busy_override >= 0:
		return busy_override == 1
	var d: Variant = table.get("director") if table != null else null
	return d is Object and bool((d as Object).call("is_busy"))


# Zeit voranschalten (eine Bildzeit)
func tick(delta: float) -> void:
	now += delta
	if cat != null:
		cat.step(delta, _table_w())
	if sky != null:
		sky.step(delta)
	if not enabled or reduced:
		return
	_check_cat()
	_check_sky()


func _table_w() -> float:
	if table != null and table.size.x > 10.0:
		return table.size.x
	return 1600.0


func _table_h() -> float:
	if table != null and table.size.y > 10.0:
		return table.size.y
	return 720.0


# --------------------------------------------------------------------------------- Sicht

# Neue Sicht: Zug, Phase. Die Wartezeit beginnt neu, sobald sich Zug, Ablage oder Stapel ändern; die Katze geht beim nächsten Zug.
func on_view(v: Dictionary) -> void:
	var phase := str(v.get("phase", "turn"))
	_playing = phase != "round_over" and phase != "game_over"
	var turn := int(v.get("turn", -1))
	var top_id := int((v.get("top", {}) as Dictionary).get("id", -1)) if v.get("top", {}) is Dictionary else -1
	var sig := "%d|%d|%d" % [turn, top_id, int(v.get("draw_count", 0))]
	if sig != _sig:
		_sig = sig
		_turn_since = now
		_rolled = false
	if turn != _turn_seat or not _playing:
		_turn_seat = turn
		_rolled = false
		_turn_since = now
		if cat != null and cat.active():
			cat.leave(false, _table_w())


func waiting_for() -> float:
	return now - _turn_since


func _check_cat() -> void:
	if cat == null or cat.active() or _rolled or not _playing or _turn_seat < 0:
		return
	if now - _turn_since < CAT_WAIT_S or is_busy():
		return
	_rolled = true
	if cat_used.has(_turn_seat) or rng.randf() >= cat_chance:
		return
	cat_used[_turn_seat] = true
	cats_started += 1
	cat.night = night
	cat.arrive(_pile_pos, _pile_w, _table_w(), rng.randf() < 0.5)


func _check_sky() -> void:
	if sky == null or now < _sky_due or sky.active():
		return
	if not _playing or big or is_busy():
		_sky_due = now + SKY_RETRY_S
		return
	_sky_due = now + rng.randf_range(SKY_MIN_S, SKY_MAX_S)
	sky_started += 1
	sky.launch(night > 0.5, rng, Vector2(_table_w(), _table_h()))


# Tipp (Koordinaten der Welt); true = die Katze wurde angetippt und geht
func tap(world_pos: Vector2) -> bool:
	if cat == null or not cat.hit(world_pos):
		return false
	cat.leave(true, _table_w())
	if table != null and table.get("fx") != null:
		(table.get("fx") as TableEffects).float_text(cat.position + Vector2(0, -60 * cat.k), "Mpf!", 30, UiPalette.CREAM, 0.9, 24.0)
	return true


# --------------------------------------------------------------------------------- Ereignisse

# Ereignis der Tischregie. count_before = Kartenzahl des betroffenen Spielers vor dem Ereignis (Sicht vor der Lieferung).
func on_event(ev: Dictionary, count_before := -1) -> void:
	var e := str(ev.get("e", ""))
	if e == "round_start" and int(ev.get("round", 0)) == 1:
		cat_used.clear()
	elif e == "draw" and is_autsch(ev, count_before):
		_stamp_autsch(int(ev.get("seat", -1)))
	elif e == "finish":
		_applause(int(ev.get("seat", -1)))


# „Autsch!“: eine Strafe (reason „strafe“) von mindestens 2 Karten, und der Betroffene hatte nur 1 Karte
static func is_autsch(ev: Dictionary, count_before: int) -> bool:
	return str(ev.get("e", "")) == "draw" and str(ev.get("reason", "")) == "strafe" and int(ev.get("count", 0)) >= 2 and count_before == 1


func _victim_pos(seat: int) -> Vector2:
	if table == null:
		return Vector2.ZERO
	var node: Node2D = table.call("seat_node", seat)
	if node != null:
		return node.position
	var p: Vector2 = table.call("_seat_point", seat)
	return p + Vector2(0, -150) if seat == int(table.get("my_seat")) else p


func _stamp_autsch(seat: int) -> void:
	stamps += 1
	if table == null or table.get("fx") == null:
		return
	var fx: TableEffects = table.get("fx")
	var pos := _victim_pos(seat) + Vector2(0, -72)
	if reduced:
		fx.float_text(pos, "Autsch!", 34, UiPalette.ALERT, 1.0, 0.0)
	else:
		fx.stamp(pos, "Autsch!", UiPalette.ALERT, 42, 0.9, -0.12)


func _applause(seat: int) -> void:
	applauses += 1
	if table == null or table.get("fx_top") == null:
		return
	var layer: Node2D = table.get("fx_top")
	var sp: Dictionary = table.call("mau_speaker", seat)
	var from: Vector2 = sp["pos"]
	var away: Vector2 = from - Vector2(table.call("table_center"))
	away = away.normalized() if away.length() > 1.0 else Vector2(0, -1)
	var a := ApplauseFx.new()
	a.calm = reduced
	a.k = 1.3 if big else 1.0
	layer.add_child(a)
	a.position = table.call("_table_to", layer, from + away * (float(sp["r"]) + 70.0))


func _zzz(pos: Vector2) -> void:
	if table != null and table.get("fx") != null and not reduced:
		(table.get("fx") as TableEffects).zzz(pos, 1.0)


# ================================================================================ Katze

class CatNode:
	extends Node2D
	var night := 0.0
	var k := 1.0
	var st := "off"        # off | in | hop | sleep | hopdown | out
	var angry := false
	var zzz_cb: Callable
	var _t := 0.0
	var _phase := 0.0
	var _dir := 1.0                # Blickrichtung beim Gehen
	var _target := Vector2.ZERO    # Schlafplatz (Mitte der Katze)
	var _edge_y := 0.0             # Gehlinie (Füße)
	var _hop_from := Vector2.ZERO
	var _hop_to := Vector2.ZERO
	var _zzz_t := 0.0
	var _out_dir := 1.0

	func active() -> bool:
		return st != "off"

	func hide_now() -> void:
		st = "off"
		visible = false

	# Katze betritt den Tisch von links oder rechts und läuft zum Ziehstapel
	func arrive(pile: Vector2, pile_w: float, table_w: float, from_left: bool) -> void:
		k = pile_w / 116.0
		_edge_y = pile.y - pile_w * 0.8 - 6.0 * k
		_target = Vector2(pile.x, pile.y - pile_w * 0.8 + 18.0 * k)
		position = Vector2(-60.0 * k if from_left else table_w + 60.0 * k, _edge_y)
		_dir = 1.0 if from_left else -1.0
		angry = false
		st = "in"
		_t = 0.0
		visible = true
		_apply_scale()

	# Treffer auf die sichtbare Katze (Welt-Koordinaten)
	func hit(p: Vector2) -> bool:
		if not (st == "in" or st == "hop" or st == "sleep"):
			return false
		return p.distance_to(position + Vector2(0, -16.0 * k)) <= 46.0 * k

	# Aufstehen und gehen (angry = weggeschoben: schnell und mit hoch erhobenem Schwanz)
	func leave(is_angry: bool, table_w: float) -> void:
		if st == "off" or st == "out" or st == "hopdown":
			angry = angry or is_angry
			return
		angry = is_angry
		_out_dir = -1.0 if position.x < table_w * 0.5 else 1.0
		if st == "sleep" or st == "hop":
			_hop_from = position
			_hop_to = Vector2(position.x + _out_dir * 30.0 * k, _edge_y)
			st = "hopdown"
			_t = 0.0
		else:
			st = "out"
			_dir = _out_dir
		_apply_scale()

	func _apply_scale() -> void:
		scale = Vector2(_dir * k, k)

	func step(delta: float, table_w: float) -> void:
		if st == "off":
			return
		_t += delta
		modulate = Color(0.82, 0.86, 1.0) if night > 0.5 else Color.WHITE
		var speed := (CAT_FLEE_SPEED if angry else CAT_SPEED) * k
		match st:
			"in":
				_phase += delta * 9.0
				position.x += _dir * speed * delta
				if (_dir > 0.0 and position.x >= _target.x) or (_dir < 0.0 and position.x <= _target.x):
					position.x = _target.x
					st = "hop"
					_t = 0.0
					_hop_from = position
					_hop_to = _target
			"hop":
				var u := clampf(_t / 0.45, 0.0, 1.0)
				position = _hop_from.lerp(_hop_to, u) + Vector2(0, -sin(u * PI) * 34.0 * k)
				if u >= 1.0:
					st = "sleep"
					_t = 0.0
					_zzz_t = 1.0
					position = _target
					_dir = 1.0
					_apply_scale()
			"sleep":
				_zzz_t -= delta
				if _zzz_t <= 0.0:
					_zzz_t = 3.5
					if zzz_cb.is_valid():
						zzz_cb.call(global_to_local_world(Vector2(24.0 * k, -34.0 * k)))
			"hopdown":
				var d := 0.3 if angry else 0.45
				var u := clampf(_t / d, 0.0, 1.0)
				position = _hop_from.lerp(_hop_to, u) + Vector2(0, -sin(u * PI) * 40.0 * k)
				if u >= 1.0:
					st = "out"
					_dir = _out_dir
					_apply_scale()
			"out":
				_phase += delta * (15.0 if angry else 9.0)
				position.x += _dir * speed * delta
				if position.x < -80.0 * k or position.x > table_w + 80.0 * k:
					hide_now()
		queue_redraw()

	# Punkt über der Katze in Koordinaten des Elternknotens (für Zzz)
	func global_to_local_world(off: Vector2) -> Vector2:
		return position + Vector2(off.x * _dir, off.y)

	func _draw() -> void:
		if st == "off":
			return
		if st == "sleep":
			_draw_sleep()
		elif st == "hop" or st == "hopdown":
			_draw_walk(0.0, true)
		else:
			_draw_walk(_phase, false)

	func _poly_ellipse(c: Vector2, rx: float, ry: float, col: Color, grow := 0.0) -> void:
		var pts := PackedVector2Array()
		for i in 28:
			var a := TAU * i / 28.0
			pts.append(c + Vector2(cos(a) * (rx + grow), sin(a) * (ry + grow)))
		draw_colored_polygon(pts, col)

	func _tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
		draw_colored_polygon(PackedVector2Array([a, b, c]), col)

	func _draw_walk(ph: float, jumping: bool) -> void:
		# Schwanz hinten (beim Weggeschobenen steil nach oben)
		var up := 44.0 if angry else 34.0
		var tail := PackedVector2Array()
		for i in 9:
			var u := i / 8.0
			tail.append(Vector2(-25.0 - 9.0 * u - 6.0 * sin(u * 3.0 + ph * 0.5) * u, -26.0 - up * u))
		draw_polyline(tail, OUTLINE, 9.0, true)
		draw_polyline(tail, FUR, 5.5, true)
		draw_circle(tail[8], 4.6, OUTLINE)
		draw_circle(tail[8], 2.8, FUR_DARK)
		# Beine
		var xs := [-16.0, -7.0, 10.0, 19.0]
		var offs := [0.0, PI, PI, 0.0]
		for i in 4:
			var sw := 0.0 if jumping else sin(ph + float(offs[i])) * 6.0
			var foot := Vector2(float(xs[i]) + sw, 0.0 if not jumping else -2.0 + (4.0 if i % 2 == 0 else -2.0))
			draw_line(Vector2(float(xs[i]), -14.0), foot, OUTLINE, 8.0, true)
			draw_line(Vector2(float(xs[i]), -14.0), foot, FUR if i < 2 else FUR_LIGHT, 4.5, true)
		# Körper
		_poly_ellipse(Vector2(0, -23), 26.0, 13.0, OUTLINE, 2.4)
		_poly_ellipse(Vector2(0, -23), 26.0, 13.0, FUR)
		_poly_ellipse(Vector2(3, -15), 17.0, 5.0, FUR_LIGHT)
		for x in [-12.0, -2.0, 8.0]:
			draw_line(Vector2(x, -35.0), Vector2(x + 1.0, -27.0), FUR_DARK, 3.0, true)
		# Kopf
		var hc := Vector2(30, -31)
		_tri(hc + Vector2(-9, -6), hc + Vector2(-6, -22), hc + Vector2(3, -9), OUTLINE)
		_tri(hc + Vector2(2, -9), hc + Vector2(9, -22), hc + Vector2(12, -5), OUTLINE)
		_tri(hc + Vector2(-8, -7), hc + Vector2(-6, -19), hc + Vector2(1, -9), FUR)
		_tri(hc + Vector2(3, -9), hc + Vector2(8, -19), hc + Vector2(10, -6), FUR)
		_tri(hc + Vector2(-6, -9), hc + Vector2(-5, -16), hc + Vector2(-1, -10), PINK)
		_tri(hc + Vector2(4, -10), hc + Vector2(7, -16), hc + Vector2(8, -8), PINK)
		_poly_ellipse(hc, 12.5, 11.0, OUTLINE, 2.2)
		_poly_ellipse(hc, 12.5, 11.0, FUR)
		draw_line(hc + Vector2(-2, -10), hc + Vector2(-1, -5), FUR_DARK, 2.4, true)
		draw_line(hc + Vector2(3, -10), hc + Vector2(3, -5), FUR_DARK, 2.4, true)
		_poly_ellipse(hc + Vector2(8, 4), 6.0, 4.5, FUR_LIGHT)
		draw_circle(hc + Vector2(6, -2), 2.6, OUTLINE)
		draw_circle(hc + Vector2(6.8, -2.8), 0.9, Color.WHITE)
		draw_circle(hc + Vector2(12, 2), 1.8, PINK)
		draw_line(hc + Vector2(11, 5), hc + Vector2(14, 3), OUTLINE, 1.2, true)
		draw_line(hc + Vector2(11, 4), hc + Vector2(22, 0), Color(OUTLINE, 0.7), 1.0, true)
		draw_line(hc + Vector2(11, 5), hc + Vector2(22, 7), Color(OUTLINE, 0.7), 1.0, true)

	func _draw_sleep() -> void:
		var br := 1.0 + 0.04 * sin(_t * 2.4)
		# Schwanz um die Vorderseite gerollt
		var tail := PackedVector2Array()
		for i in 11:
			var a := lerpf(0.25, 2.7, i / 10.0)
			tail.append(Vector2(5.0 + cos(a) * 31.0, -13.0 + sin(a) * 15.0))
		draw_polyline(tail, OUTLINE, 9.5, true)
		draw_polyline(tail, FUR_DARK, 6.0, true)
		_poly_ellipse(Vector2(0, -17), 33.0, 17.0 * br, OUTLINE, 2.4)
		_poly_ellipse(Vector2(0, -17), 33.0, 17.0 * br, FUR)
		for x in [-4.0, 6.0, 16.0]:
			draw_line(Vector2(x, -32.0 * br), Vector2(x + 2.0, -23.0), FUR_DARK, 3.2, true)
		# Kopf links, auf die Pfoten gelegt
		var hc := Vector2(-25, -10)
		_tri(hc + Vector2(-11, -3), hc + Vector2(-11, -21), hc + Vector2(-1, -8), OUTLINE)
		_tri(hc + Vector2(1, -8), hc + Vector2(10, -20), hc + Vector2(11, -3), OUTLINE)
		_tri(hc + Vector2(-9, -5), hc + Vector2(-9, -17), hc + Vector2(-2, -8), FUR)
		_tri(hc + Vector2(2, -8), hc + Vector2(8, -16), hc + Vector2(9, -4), FUR)
		_poly_ellipse(hc, 14.0, 11.5, OUTLINE, 2.2)
		_poly_ellipse(hc, 14.0, 11.5, FUR)
		_poly_ellipse(hc + Vector2(0, 5), 8.0, 5.0, FUR_LIGHT)
		draw_arc(hc + Vector2(-5, -1), 3.2, 0.2, PI - 0.2, 8, OUTLINE, 1.8, true)
		draw_arc(hc + Vector2(5, -1), 3.2, 0.2, PI - 0.2, 8, OUTLINE, 1.8, true)
		draw_circle(hc + Vector2(0, 3), 1.8, PINK)


# ================================================================================ Himmel

class SkyNode:
	extends Node2D
	var kind := ""           # "star" (Sternschnuppe) | "butterfly" | ""
	var t := 0.0
	var dur := 1.0
	var p0 := Vector2.ZERO
	var p1 := Vector2.ZERO
	var wing := Color("#FF9A3C")
	var wing2 := Color("#FFD76A")
	var _bob := 0.0

	func active() -> bool:
		return kind != ""

	func stop() -> void:
		kind = ""
		visible = false

	func launch(is_night: bool, rng: RandomNumberGenerator, sz: Vector2) -> void:
		t = 0.0
		visible = true
		if is_night:
			kind = "star"
			dur = 1.2
			p0 = Vector2(rng.randf_range(0.5, 0.95) * sz.x, rng.randf_range(0.04, 0.2) * sz.y)
			p1 = p0 + Vector2(-0.34 * sz.x, 0.15 * sz.y)
		else:
			kind = "butterfly"
			dur = 9.0
			var y := rng.randf_range(0.1, 0.24) * sz.y
			var from_left := rng.randf() < 0.5
			p0 = Vector2(-30.0 if from_left else sz.x + 30.0, y)
			p1 = Vector2(sz.x + 30.0 if from_left else -30.0, y + rng.randf_range(-0.05, 0.08) * sz.y)
			_bob = rng.randf_range(0.0, TAU)
			var palettes := [[Color("#FF9A3C"), Color("#FFD76A")], [Color("#5FA8FF"), Color("#BFE0FF")], [Color("#F08AD0"), Color("#FFD0EE")]]
			var pal: Array = palettes[rng.randi() % palettes.size()]
			wing = pal[0]
			wing2 = pal[1]
		queue_redraw()

	func step(delta: float) -> void:
		if kind == "":
			return
		t += delta
		if t >= dur:
			stop()
			return
		queue_redraw()

	func pos_at(u: float) -> Vector2:
		if kind == "butterfly":
			var base := p0.lerp(p1, u)
			return base + Vector2(0, sin(u * TAU * 3.0 + _bob) * 22.0 + sin(u * TAU * 7.0) * 5.0)
		return p0.lerp(p1, u)

	func _draw() -> void:
		if kind == "":
			return
		var u := clampf(t / dur, 0.0, 1.0)
		if kind == "star":
			var e := u * (2.0 - u)
			var head := pos_at(e)
			var dir := (p1 - p0).normalized()
			var fade := sin(clampf(u, 0.0, 1.0) * PI)
			var tail_len := (p1 - p0).length() * 0.3
			var n := 16
			for i in n:
				var a := float(i) / n
				var b := float(i + 1) / n
				draw_line(head - dir * tail_len * a, head - dir * tail_len * b, Color(1, 1, 1, (1.0 - a) * 0.85 * fade), lerpf(3.4, 0.6, a), true)
			draw_circle(head, 5.5, Color(1, 0.96, 0.8, 0.25 * fade))
			draw_circle(head, 2.8, Color(1, 1, 1, fade))
		else:
			var c0 := pos_at(u)
			var ahead := pos_at(minf(u + 0.01, 1.0)) - c0
			draw_set_transform(c0, 0.0, Vector2(1.8, 1.8))
			var c := Vector2.ZERO
			var flap := absf(cos(t * 14.0))
			var face := 1.0 if ahead.x >= 0.0 else -1.0
			var fade := minf(1.0, minf(u * 12.0, (1.0 - u) * 12.0))
			var w := wing
			w.a = fade
			var w2 := wing2
			w2.a = fade
			var ink := Color(OUTLINE.r, OUTLINE.g, OUTLINE.b, fade)
			for s in [-1.0, 1.0]:
				var up := PackedVector2Array()
				var lo := PackedVector2Array()
				for i in 16:
					var a := TAU * i / 16.0
					up.append(c + Vector2(s * (7.0 + cos(a) * 9.0 * flap), -5.0 + sin(a) * 8.0))
					lo.append(c + Vector2(s * (5.0 + cos(a) * 6.0 * flap), 6.0 + sin(a) * 5.5))
				draw_colored_polygon(up, w)
				draw_colored_polygon(lo, w2)
				draw_polyline(up + PackedVector2Array([up[0]]), ink, 1.2, true)
			draw_line(c + Vector2(0, -8), c + Vector2(0, 9), ink, 2.6, true)
			draw_line(c + Vector2(0, -8), c + Vector2(face * 5.0, -15.0), ink, 1.0, true)
			draw_line(c + Vector2(0, -8), c + Vector2(face * -1.0, -15.0), ink, 1.0, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ================================================================================ Applaus

class ApplauseFx:
	extends Node2D
	var calm := false
	var k := 1.0
	var t := 0.0
	const DUR := 1.4

	func _ready() -> void:
		scale = Vector2.ONE * k

	func _process(delta: float) -> void:
		t += delta
		if t >= DUR:
			queue_free()
			return
		modulate.a = clampf(minf(t / 0.12, (DUR - t) / 0.3), 0.0, 1.0)
		queue_redraw()

	func _hand(side: float, d: float) -> void:
		var skin := Color("#F2C48D")
		var ink := Color("#211B2C")
		var c := Vector2(side * d, 0)
		var rot := -side * 0.32
		var xf := Transform2D(rot, c)
		draw_set_transform_matrix(xf)
		var pts := PackedVector2Array()
		for i in 20:
			var a := TAU * i / 20.0
			pts.append(Vector2(cos(a) * 13.0, 7.0 + sin(a) * 15.0))
		draw_colored_polygon(pts, ink.lerp(skin, 0.0))
		pts = PackedVector2Array()
		for i in 20:
			var a := TAU * i / 20.0
			pts.append(Vector2(cos(a) * 11.0, 7.0 + sin(a) * 13.0))
		draw_colored_polygon(pts, skin)
		for i in 4:
			var x := -8.0 + i * 5.3
			var top := Vector2(x * 1.1, -24.0 + absf(x) * 0.5)
			draw_line(Vector2(x, -4.0), top, ink, 7.0, true)
			draw_line(Vector2(x, -4.0), top, skin, 4.4, true)
		draw_line(Vector2(-side * 10.0, 8.0), Vector2(-side * 20.0, -4.0), ink, 7.0, true)
		draw_line(Vector2(-side * 10.0, 8.0), Vector2(-side * 20.0, -4.0), skin, 4.4, true)
		draw_set_transform_matrix(Transform2D.IDENTITY)

	func _draw() -> void:
		var cyc := 0.5 + 0.5 * cos(t / DUR * 3.0 * TAU)      # 1 = weit auseinander, 0 = zusammen
		var d := 20.0 if calm else 9.0 + 16.0 * cyc
		_hand(-1.0, d)
		_hand(1.0, d)
		if not calm and cyc < 0.25:
			var s := 1.0 - cyc / 0.25
			for i in 7:
				var a := -PI * 0.5 + (i - 3) * 0.42
				var dir := Vector2(cos(a), sin(a))
				draw_line(dir * (30.0 + 4.0 * s), dir * (30.0 + 16.0 * s), UiPalette.TURN, 3.0, true)
