class_name GambleMachine
extends Node2D
# Glücksspiel-Automat in der Tischmitte (Hausregel „Glücksspiel“, AGENTS.md Nr. 26, BETA1_PLAN Abschnitt 4 Phase „gamble“):
# oben das Zahlenwerk – eine Walze 0–10 wie eine Trommel, die Nachbarzahlen laufen oben und unten aus –, darunter der große runde
# Glücksspielknopf. Alle sehen den Automaten und den Ablauf; drücken kann nur der Glücksspieler, wenn der Druck fällig ist
# (can_press: der Knopf pulsiert). Ein Ring in der Avatarfarbe zeigt, wer spielt. Darunter erscheint der kleine Knopf
# „Aufhören“, solange hints.can_stop gilt (can_stop, hit_stop).
# Gestaltung Papier & Neon: Tag = Papier mit Druckfarbenrand und Goldkranz, Nacht = dunkle Scheibe mit rosa Neonröhre und
# goldenen Leuchtziffern.
# Leistung: gezeichnet wird nur bei Änderungen; _process läuft nur, solange etwas läuft (Erscheinen, Walze, Druck, Puls, Wackeln,
# Aufleuchten), danach schläft der Knoten (set_process(false)).
# Ursprung = Tischmitte: Walze bei REEL_Y, Knopf bei BUTTON_Y (bei 1600 × 720 also y 262 bzw. 372, zwischen den Stapeln).

const REEL_SIZE := Vector2(120.0, 84.0)
const REEL_Y := -58.0
const BUTTON_R := 56.0
const BUTTON_Y := 52.0
const VALUES := 11                 # Walze 0–10
const STEP_ANGLE := 0.62           # Trommel: Winkel je Zahl
const DRUM_R := 40.0
const OVERSHOOT := 0.22            # Walze rastet mit kleinem Überschwinger ein (in Zahlen)
const NEON := Color("#FF7FCF")
const NEON_CORE := Color("#FFE3F4")
const GOLD := Color("#FFD65A")
const LABEL := "Los!"
const STOP_LABEL := "Aufhören"
const STOP_SIZE := Vector2(138.0, 40.0)
const STOP_Y := BUTTON_Y + BUTTON_R + 36.0   # Mitte des Aufhören-Knopfs unter „Los!“

var night := 0.0: set = set_night
var accent := Color("#FFD65A"): set = set_accent
var can_press := false: set = set_can_press
var can_stop := false: set = set_can_stop   # hints.can_stop: kleiner Knopf „Aufhören“ unter „Los!“
var reduced := false
var active := false
var press_sent := false            # eigener Druck ist unterwegs (kein zweites Senden bis zur nächsten Sicht)

var _appear := 0.0
var _appear_to := 0.0
var _reel := 0.0                   # Walzenstellung in Zahlen (fortlaufend; Anzeige = Rest modulo 11)
var _blank := true                 # vor dem ersten Druck: „?“
var _spin_from := 0.0
var _spin_to := 0.0
var _spin_t := -1.0
var _spin_dur := 1.0
var _press := 0.0
var _down := false
var _kick := 0.0
var _pulse := 0.0
var _shake := 0.0
var _flash := 0.0


func _init() -> void:
	visible = false
	set_process(false)


func set_night(v: float) -> void:
	night = clampf(v, 0.0, 1.0)
	queue_redraw()


func set_accent(c: Color) -> void:
	accent = c
	queue_redraw()


func set_can_press(on: bool) -> void:
	if on == can_press:
		return
	can_press = on
	_wake()


func set_can_stop(on: bool) -> void:
	if on == can_stop:
		return
	can_stop = on
	_wake()


# Erscheinen (aufploppen) bzw. Verschwinden (ausblenden)
func show_machine(animate := true) -> void:
	active = true
	_appear_to = 1.0
	visible = true
	if not animate:
		_appear = 1.0
	_wake()


func hide_machine(animate := true) -> void:
	active = false
	can_press = false
	can_stop = false
	press_sent = false
	_down = false
	_appear_to = 0.0
	if not animate or _appear <= 0.0:
		_appear = 0.0
		visible = false
	_wake()


# Wert ohne Walzenlauf zeigen (Abgleich mit view.gamble.last); −1 = noch kein Druck („?“)
func set_value(v: int) -> void:
	if is_spinning():
		return
	_blank = v < 0
	if v >= 0 and posmod(roundi(_reel), VALUES) != v:
		_reel = float(v)
	queue_redraw()


func shown_value() -> int:
	return -1 if _blank else posmod(roundi(_reel), VALUES)


# Walze dreht dur Sekunden (mindestens eine volle Umdrehung, sonst zwei) und rastet auf v ein.
func spin_to(v: int, dur: float) -> void:
	_blank = false
	var cur := fposmod(_reel, float(VALUES))
	_reel = cur
	_spin_from = cur
	var turns := 2 if dur >= 0.6 else 1
	_spin_to = floorf(cur) + float(VALUES * turns + posmod(v - int(floorf(cur)), VALUES))
	_spin_dur = maxf(dur, 0.05)
	_spin_t = 0.0
	_wake()


# Walze sofort auf ihr Ziel (Überspringen)
func finish_spin() -> void:
	if _spin_t >= 0.0:
		_spin_t = -1.0
		_reel = _spin_to
		queue_redraw()


func is_spinning() -> bool:
	return _spin_t >= 0.0


# Knopf wird gedrückt (eigener Tipp oder der Druck eines anderen, gezeigt mit dem Ereignis)
func press_anim() -> void:
	_kick = 1.0
	_wake()


func set_down(on: bool) -> void:
	if on == _down:
		return
	_down = on
	_wake()


# „Nichts!“: Walze wackelt kurz
func shake() -> void:
	_shake = 1.0
	_wake()


# Treffer: Walze leuchtet auf
func flash() -> void:
	_flash = 1.0
	_wake()


func reel_center() -> Vector2:
	return Vector2(0.0, REEL_Y)


func button_center() -> Vector2:
	return Vector2(0.0, BUTTON_Y)


# Treffer auf den Knopf (global)
func hit(global_pos: Vector2) -> bool:
	if not active or _appear < 0.5 or not is_visible_in_tree():
		return false
	return to_local(global_pos).distance_to(button_center()) <= BUTTON_R + 12.0


func stop_rect() -> Rect2:
	return Rect2(Vector2(-STOP_SIZE.x * 0.5, STOP_Y - STOP_SIZE.y * 0.5), STOP_SIZE)


# Treffer auf „Aufhören“ (global); nur, solange der Knopf sichtbar ist
func hit_stop(global_pos: Vector2) -> bool:
	if not active or not can_stop or press_sent or _appear < 0.5 or not is_visible_in_tree():
		return false
	return stop_rect().grow(8.0).has_point(to_local(global_pos))


# Läuft gerade etwas (Tests, Leistung)?
func is_animating() -> bool:
	return is_processing()


func _wake() -> void:
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	var busy := false
	if _appear != _appear_to:
		_appear = move_toward(_appear, _appear_to, delta / (0.18 if reduced else 0.26))
		if _appear <= 0.0 and _appear_to <= 0.0:
			visible = false
		busy = true
	modulate.a = clampf(_appear * 1.6, 0.0, 1.0)
	if _spin_t >= 0.0:
		_spin_t += delta
		var u := clampf(_spin_t / _spin_dur, 0.0, 1.0)
		var dist := _spin_to - _spin_from
		if u < 0.86:
			var v := u / 0.86
			_reel = _spin_from + (dist + OVERSHOOT) * (1.0 - pow(1.0 - v, 3.0))
		else:
			var w := (u - 0.86) / 0.14
			_reel = _spin_to + OVERSHOOT * (1.0 - smoothstep(0.0, 1.0, w))
		if u >= 1.0:
			_spin_t = -1.0
			_reel = _spin_to
		busy = true
	var want := 1.0 if _down else 0.0
	if _press != want:
		_press = move_toward(_press, want, delta * 14.0)
		busy = true
	if _kick > 0.0:
		_kick = maxf(_kick - delta / 0.3, 0.0)
		busy = true
	if _shake > 0.0:
		_shake = maxf(_shake - delta / 0.45, 0.0)
		busy = true
	if _flash > 0.0:
		_flash = maxf(_flash - delta / 0.9, 0.0)
		busy = true
	if can_press and active and not press_sent:
		_pulse += delta
		busy = true
	queue_redraw()
	if not busy:
		set_process(false)


# ---------------------------------------------------------------- Zeichnen

func _draw() -> void:
	if _appear <= 0.0:
		return
	var u := clampf(_appear, 0.0, 1.0) - 1.0
	var s := (1.0 + 2.70158 * u * u * u + 1.70158 * u * u) if _appear_to > 0.0 else _appear
	if reduced:
		s = 1.0
	var off := Vector2(sin(_shake * 34.0) * 7.0 * _shake, 0.0)
	var base := Transform2D(0.0, Vector2(s, s), 0.0, off)
	_draw_button(base)
	if can_stop and not press_sent:
		_draw_stop(base)
	_draw_reel(base)
	draw_set_transform_matrix(Transform2D.IDENTITY)


# „Aufhören“: kleine Pille im Stil von „Los!“ (Tag: Papier mit Tintenrand, Nacht: Neonrand)
func _draw_stop(base: Transform2D) -> void:
	draw_set_transform_matrix(base)
	var neon := night > 0.5
	var rect := stop_rect()
	var sh := StyleBoxFlat.new()
	sh.set_corner_radius_all(int(STOP_SIZE.y * 0.5))
	sh.bg_color = Color(0, 0, 0, 0.3)
	draw_style_box(sh, rect.grow(1.0))
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(int(STOP_SIZE.y * 0.5))
	box.set_border_width_all(3)
	if neon:
		box.bg_color = UiPalette.NIGHT
		box.border_color = NEON
	else:
		box.bg_color = UiPalette.PAPER
		box.border_color = UiPalette.INK
	draw_style_box(box, Rect2(rect.position - Vector2(0.0, 3.0), rect.size))
	var f := UiFonts.mau()
	var fs := 22
	var tw := f.get_string_size(I18n.t(STOP_LABEL), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := Vector2(-tw * 0.5, STOP_Y - 3.0 + fs * 0.34)
	if neon:
		draw_string_outline(f, tp, I18n.t(STOP_LABEL), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(NEON, 0.3))
		draw_string(f, tp, I18n.t(STOP_LABEL), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, NEON_CORE)
	else:
		draw_string(f, tp, I18n.t(STOP_LABEL), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiPalette.INK)


func _draw_button(base: Transform2D) -> void:
	draw_set_transform_matrix(base)
	var neon := night > 0.5
	var r := BUTTON_R
	var pr := maxf(_press, sin(_kick * PI) * 0.95)
	var k := 1.0 - 0.06 * pr
	var bc := Vector2(0.0, BUTTON_Y)
	var c := bc + Vector2(0.0, 4.0 * pr)
	var live := can_press and not press_sent
	# Kranz: pulsierend, wenn der eigene Druck fällig ist; sonst ruhig in der Avatarfarbe des Glücksspielers
	if live:
		var p := 0.5 + 0.5 * sin(_pulse * 4.2)
		var halo := NEON if neon else GOLD
		draw_circle(bc, (r + 15.0 + 6.0 * p) * k, Color(halo, 0.20 + 0.18 * p))
		draw_circle(bc, (r + 9.0) * k, Color(halo, 0.62))
	else:
		draw_circle(bc, (r + 8.0) * k, Color(accent, 0.55))
	draw_circle(bc + Vector2(0.0, 7.0 * (1.0 - pr)), r * k, Color(0, 0, 0, 0.33))
	var f := UiFonts.mau()
	var fs := int(36.0 * k)
	var tw := f.get_string_size(I18n.t(LABEL), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := c + Vector2(-tw * 0.5, fs * 0.34)
	if neon:
		draw_circle(c, r * k, UiPalette.NIGHT_HI)
		draw_circle(c, (r - 6.0) * k, UiPalette.NIGHT)
		draw_arc(c, (r - 3.0) * k, 0.0, TAU, 72, Color(NEON, 0.30 if live else 0.18), 12.0, true)
		draw_arc(c, (r - 3.0) * k, 0.0, TAU, 72, Color(NEON, 1.0 if live else 0.7), 3.5, true)
		draw_arc(c, (r - 3.0) * k, 0.0, TAU, 72, Color(NEON_CORE, 0.9 if live else 0.5), 1.2, true)
		draw_string_outline(f, tp, I18n.t(LABEL), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 9, Color(NEON, 0.35 if live else 0.18))
		draw_string(f, tp, I18n.t(LABEL), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(NEON_CORE, 1.0 if live else 0.6))
	else:
		draw_circle(c, r * k, UiPalette.INK)
		draw_circle(c, (r - 5.0) * k, UiPalette.CREAM if live else UiPalette.PAPER)
		draw_arc(c, (r - 13.0) * k, PI * 1.12, PI * 1.88, 24, Color(1, 1, 1, 0.7), 4.0 * k, true)
		draw_string(f, tp, I18n.t(LABEL), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiPalette.INK, 1.0 if live else 0.62))


func _draw_reel(base: Transform2D) -> void:
	draw_set_transform_matrix(base)
	var neon := night > 0.5
	var rc := Vector2(0.0, REEL_Y)
	var rect := Rect2(rc - REEL_SIZE * 0.5, REEL_SIZE)
	var inner := rect.grow(-5.0)
	var inner_bg := UiPalette.NIGHT if neon else UiPalette.CREAM
	# Gehäuse mit Schatten bzw. Neonschein
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(18)
	box.anti_aliasing = true
	if neon:
		box.bg_color = UiPalette.NIGHT_PANEL
		box.shadow_color = Color(NEON, 0.30 + 0.45 * _flash)
		box.shadow_size = int(12.0 + 10.0 * _flash)
	else:
		box.bg_color = UiPalette.INK
		box.shadow_color = Color(0, 0, 0, 0.30)
		box.shadow_size = 10
		box.shadow_offset = Vector2(0, 4)
	draw_style_box(box, rect)
	var ib := StyleBoxFlat.new()
	ib.bg_color = inner_bg
	ib.set_corner_radius_all(13)
	ib.anti_aliasing = true
	draw_style_box(ib, inner)
	# Ziffern auf der Trommel
	var font := UiFonts.text(800, 100.0)
	var fs := 52
	var half := REEL_SIZE.y * 0.5 - 1.0
	var digit_col := GOLD if neon else UiPalette.INK
	if _blank:
		var q := "?"
		var qw := font.get_string_size(q, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, rc + Vector2(-qw * 0.5, fs * 0.36), q, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(digit_col, 0.55))
	else:
		var b := floorf(_reel)
		var frac := _reel - b
		for j in range(-2, 3):
			var o := float(j) - frac
			var ang := o * STEP_ANGLE
			if absf(ang) > 1.35:
				continue
			var y := -sin(ang) * DRUM_R
			var sy := cos(ang)
			var h2 := fs * 0.36 * sy
			var alpha := clampf((half - 2.0 - (absf(y) + h2)) / 9.0, 0.0, 1.0) * clampf(sy * 1.3 - 0.1, 0.0, 1.0)
			if alpha <= 0.01:
				continue
			var txt := str(posmod(int(b) + j, VALUES))
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_set_transform_matrix(base * Transform2D(0.0, Vector2(1.0, sy), 0.0, rc + Vector2(0.0, y)))
			var p := Vector2(-w * 0.5, fs * 0.36)
			if neon:
				draw_string_outline(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(GOLD, 0.22 * alpha))
			draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(digit_col, alpha))
		draw_set_transform_matrix(base)
	# Trommelschatten oben und unten (Ziffern laufen weich aus)
	var band := inner.size.y * 0.30
	var solid := Color(inner_bg, 0.95)
	var clear := Color(inner_bg, 0.0)
	draw_polygon(PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y), Vector2(inner.end.x, inner.position.y + band), Vector2(inner.position.x, inner.position.y + band)]),
		PackedColorArray([solid, solid, clear, clear]))
	draw_polygon(PackedVector2Array([Vector2(inner.position.x, inner.end.y - band), Vector2(inner.end.x, inner.end.y - band), inner.end, Vector2(inner.position.x, inner.end.y)]),
		PackedColorArray([clear, clear, solid, solid]))
	# Rahmen (deckt Ecken und Rand) und Neonlinie
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.set_corner_radius_all(18)
	frame.set_border_width_all(5)
	frame.border_color = UiPalette.NIGHT_PANEL if neon else UiPalette.INK
	frame.anti_aliasing = true
	draw_style_box(frame, rect)
	if neon:
		var line := StyleBoxFlat.new()
		line.draw_center = false
		line.set_corner_radius_all(16)
		line.set_border_width_all(3)
		line.border_color = NEON
		line.anti_aliasing = true
		draw_style_box(line, rect.grow(-2.0))
	# Markierungen links und rechts der Mitte (Ablesestelle)
	var mk := NEON if neon else GOLD
	for sgn: float in [-1.0, 1.0]:
		var x: float = rc.x + sgn * (REEL_SIZE.x * 0.5 - 4.0)
		var tri := PackedVector2Array([Vector2(x, rc.y - 9.0), Vector2(x, rc.y + 9.0), Vector2(x - sgn * 11.0, rc.y)])
		draw_colored_polygon(tri, mk)
		if not neon:
			draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), UiPalette.INK, 1.5, true)
	# Treffer: Walze leuchtet
	if _flash > 0.01:
		var fl := StyleBoxFlat.new()
		fl.draw_center = false
		fl.set_corner_radius_all(22)
		fl.set_border_width_all(4)
		fl.border_color = Color(NEON if neon else GOLD, _flash)
		fl.anti_aliasing = true
		draw_style_box(fl, rect.grow(4.0 + 6.0 * (1.0 - _flash)))
