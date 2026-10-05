class_name HandLayout
extends RefCounted
# Reine Rechnungen der eigenen Hand (docs/recherche/06_hand_ux_effekte.md Abschnitt 1): Stufenwahl mit Hysterese, Fächer (A),
# Lupe (B), Bogen-Karussell mit Fischauge (C), Schwung-Projektion, Einrasten, Gummiband, Federn, Geschwindigkeit aus Touchproben
# und die Gestenerkennung als Zustandsmaschine (Zeit und Weg als Eingabe). Keine Nodes, alles headless testbar.
# Einheit: Pixel der Basisauflösung 1600×720 (Handy quer ≈ 800×360 dp, also DP = 2 px). Karte i = 0 liegt links.
# Koordinaten des Handbereichs: (0, 0) oben links, (width, height) unten rechts. Die Kartenmitte ruht auf der Unterkante,
# sichtbar ist also nur die obere Hälfte (Nutzerentscheidung 8: Querformat, Eckindex oben links trägt die Karte).

enum Mode { FAN, LENS, CAROUSEL }

const DP := 2.0
const CARD_ASPECT := 466.0 / 300.0
const CARD_W_PER_H := 0.86            # Kartenbreite relativ zur Höhe des Handbereichs (220 px → 189 px wie im Entwurf)
const FAN_MAX := 7                    # Stufe A bis 7 Karten
const CAROUSEL_FROM := 16             # Stufe C ab 16 Karten …
const CAROUSEL_BACK := 13             # … zurück zu B erst bei ≤ 13 (Hysterese)
const FAN_STEP_MIN := 48.0 * DP       # Stufe A: jede Karte direkt antippbar
const FAN_STEP_MAX := 56.0 * DP
const LENS_STEP_MAX := 40.0 * DP
const LENS_EXTRA := 45.0 * DP         # zusätzliche Öffnung der Lupe, auf die Lücken um den Finger verteilt
const LENS_SIGMA := 1.0               # Breite der Lupe in Karten (Lücken)
const LENS_LIFT := 24.0 * DP          # Karte unter dem Finger: +24 dp …
const LENS_SCALE := 0.15              # … und ×1,15
const LENS_CARD_SIGMA := 0.55
const ARC_RADIUS := 1600.0            # Bogen der Stufen A und B; Drehung höchstens ±12°
const MAX_TILT := deg_to_rad(12.0)
const FISH_S_MAX := 52.0 * DP         # Fischauge: Abstand in der Mitte …
const FISH_S_MIN := 10.0 * DP         # … und am Rand (wird bei vielen Karten kleiner, damit alle als Streifen sichtbar bleiben)
const FISH_S_FLOOR := 1.5 * DP
const FISH_SIGMA := 2.5
const WHEEL_RADIUS := 1250.0          # Bogen des Karussells
const WHEEL_EDGE_SCALE := 0.85
const WHEEL_EDGE_SHADE := 0.75
const WHEEL_EDGE_DROP := 12.0 * DP
const GROUP_GAP := 6.0 * DP           # Lücke zwischen Farbgruppen
const PROJECT_RATE := 0.998           # Abklingrate je ms (Apple „normal“, τ ≈ 0,5 s)
const RUBBER_C := 0.55                # Gummiband wie UIScrollView


static func card_width(height: float) -> float:
	return height * CARD_W_PER_H


# Stufe für n Karten; current ist die bisherige Stufe (Hysterese nur zwischen B und C).
static func choose_mode(n: int, current: Mode = Mode.FAN) -> Mode:
	if n >= CAROUSEL_FROM:
		return Mode.CAROUSEL
	if current == Mode.CAROUSEL and n > CAROUSEL_BACK:
		return Mode.CAROUSEL
	return Mode.FAN if n <= FAN_MAX else Mode.LENS


# Fischauge: Kartenabstand im Abstand d (in Karten) zur Mitte, s(d) = s_min + (s_max − s_min)·exp(−(d/σ)²).
static func fisheye(d: float, s_min := FISH_S_MIN, s_max := FISH_S_MAX, sigma := FISH_SIGMA) -> float:
	return s_min + (s_max - s_min) * exp(-(d / sigma) * (d / sigma))


# Stammfunktion des Fischauges: Versatz der Karte im Abstand d zur Mitte (stetig in d, also ruckfrei beim Scrollen).
static func fisheye_offset(d: float, s_min := FISH_S_MIN, s_max := FISH_S_MAX, sigma := FISH_SIGMA) -> float:
	return s_min * d + (s_max - s_min) * sigma * sqrt(PI) * 0.5 * erf(d / sigma)


# Fehlerfunktion (Abramowitz/Stegun 7.1.26, Fehler < 1,5e-7).
static func erf(x: float) -> float:
	var a := absf(x)
	var t := 1.0 / (1.0 + 0.3275911 * a)
	var y := 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-a * a)
	return y if x >= 0.0 else -y


# Kleinster Karussell-Abstand, bei dem alle n Karten von der Mitte aus in die halbe Breite passen.
static func wheel_s_min(n: int, width: float, height: float) -> float:
	var half := (width - card_width(height) * WHEEL_EDGE_SCALE) * 0.5 - 2.0 * DP
	var k := FISH_SIGMA * sqrt(PI) * 0.5 * erf(float(n - 1) / FISH_SIGMA)
	var rest := float(n - 1) - k
	if rest <= 0.0:
		return FISH_S_MIN
	return clampf((half - FISH_S_MAX * k) / rest, FISH_S_FLOOR, FISH_S_MIN)


# Layout der Hand: je Karte ein Transform (Drehung, Skalierung, Mittelpunkt) im Handbereich.
# scroll: Karussell-Mitte in Karten (0 … n−1, darüber hinaus Gummiband); focus: Lupe in Karten (−1 = aus);
# gaps: Indizes, vor denen eine Gruppenlücke liegt (CardSort.group_starts).
static func layout(n: int, scroll: float, focus: float, mode: Mode, width: float, height: float,
		gaps: PackedInt32Array = PackedInt32Array()) -> Array[Transform2D]:
	var out: Array[Transform2D] = []
	if n <= 0:
		return out
	if mode == Mode.CAROUSEL:
		return _wheel(n, scroll, width, height, gaps)
	var cw := card_width(height)
	var avail := maxf(width - cw, 0.0)
	var gap_total := GROUP_GAP * gaps.size()
	var step := 0.0
	if n > 1:
		var top := FAN_STEP_MAX if mode == Mode.FAN else LENS_STEP_MAX
		step = minf(top, (avail - gap_total) / float(n - 1))
		if mode == Mode.FAN:
			step = maxf(step, minf(FAN_STEP_MIN, (avail - gap_total) / float(n - 1)))
		step = maxf(step, 1.0)
	# Lücken: Grundabstand, bei aktiver Lupe Öffnung um den Finger (Summe bleibt in der verfügbaren Breite)
	var spacing := PackedFloat32Array()
	spacing.resize(maxi(n - 1, 0))
	var base_total := step * float(n - 1) + gap_total
	var total := base_total
	if mode == Mode.LENS and focus >= 0.0 and n > 1:
		var wsum := 0.0
		var w := PackedFloat32Array()
		w.resize(n - 1)
		for k in n - 1:
			var dk := (float(k) + 0.5 - focus) / LENS_SIGMA
			w[k] = exp(-dk * dk)
			wsum += w[k]
		total = minf(avail, base_total + LENS_EXTRA * wsum)
		total = maxf(total, base_total)
		var a := (total - gap_total - LENS_EXTRA * wsum) / float(n - 1)
		var extra := LENS_EXTRA
		if a < step * 0.45:
			# zu eng: Öffnung begrenzen, damit kein Streifen verschwindet
			a = step * 0.45
			extra = maxf((total - gap_total - a * float(n - 1)) / maxf(wsum, 0.001), 0.0)
		for k in n - 1:
			spacing[k] = a + extra * w[k]
	else:
		for k in n - 1:
			spacing[k] = step
	var radius := maxf(ARC_RADIUS, (base_total * 0.5) / MAX_TILT)
	var cx := width * 0.5
	var x := -total * 0.5
	var gi := 0
	for i in n:
		if i > 0:
			x += spacing[i - 1]
			while gi < gaps.size() and gaps[gi] <= i:
				if gaps[gi] == i:
					x += GROUP_GAP
				gi += 1
		var theta := clampf(x / radius, -MAX_TILT, MAX_TILT)
		var pos := Vector2(cx + radius * sin(x / radius), height + radius * (1.0 - cos(x / radius)))
		var s := 1.0
		if mode == Mode.LENS and focus >= 0.0:
			var dc := (float(i) - focus) / LENS_CARD_SIGMA
			var c := exp(-dc * dc)
			s += LENS_SCALE * c
			pos += Vector2(0.0, -LENS_LIFT * c).rotated(theta)
		out.append(Transform2D(theta, Vector2(s, s), 0.0, pos))
	return out


# Bogen-Karussell: Fischauge um scroll, Karten auf einem Kreisbogen, zum Rand kleiner und abgesenkt.
static func _wheel(n: int, scroll: float, width: float, height: float, gaps: PackedInt32Array) -> Array[Transform2D]:
	var out: Array[Transform2D] = []
	var s_min := wheel_s_min(n, width, height)
	var cx := width * 0.5
	for i in n:
		var d := float(i) - scroll
		var x := fisheye_offset(d, s_min)
		# Gruppenlücken: stetig beim Durchlaufen, in der Mitte voll, am Rand mit dem Fischauge gestaucht
		for g in gaps:
			var passed := clampf(scroll - float(g - 1), 0.0, 1.0)
			var gw := GROUP_GAP * fisheye(float(g) - 0.5 - scroll, s_min) / FISH_S_MAX
			x += gw * ((1.0 if i >= g else 0.0) - passed)
		var w := exp(-(d / FISH_SIGMA) * (d / FISH_SIGMA))
		var theta := x / WHEEL_RADIUS
		var pos := Vector2(cx + WHEEL_RADIUS * sin(theta), height + WHEEL_RADIUS * (1.0 - cos(theta)) + WHEEL_EDGE_DROP * (1.0 - w))
		var s := WHEEL_EDGE_SCALE + (1.0 - WHEEL_EDGE_SCALE) * w
		out.append(Transform2D(theta, Vector2(s, s), 0.0, pos))
	return out


# Helligkeit je Karte (Karussell: zum Rand auf 75 %).
static func shade(n: int, scroll: float, mode: Mode, i: int) -> float:
	if mode != Mode.CAROUSEL or n <= 0:
		return 1.0
	var d := (float(i) - scroll) / FISH_SIGMA
	return WHEEL_EDGE_SHADE + (1.0 - WHEEL_EDGE_SHADE) * exp(-d * d)


# Stetiger Kartenindex unter x (Handbereich) nach den sichtbaren Streifen ohne Lupe: Mitte des Streifens von Karte i = i.
# Ergebnis in [−0,5, n − 0,5]; für Lupe/Einfügen auf [0, n − 1] begrenzen.
static func index_at(n: int, x: float, scroll: float, mode: Mode, width: float, height: float,
		gaps: PackedInt32Array = PackedInt32Array()) -> float:
	if n <= 0:
		return -1.0
	var xf := layout(n, scroll, -1.0, mode, width, height, gaps)
	var cw := card_width(height)
	var lefts := PackedFloat32Array()
	lefts.resize(n + 1)
	for i in n:
		lefts[i] = xf[i].origin.x - cw * xf[i].get_scale().x * 0.5
	lefts[n] = xf[n - 1].origin.x + cw * xf[n - 1].get_scale().x * 0.5
	if x <= lefts[0]:
		return -0.5
	if x >= lefts[n]:
		return float(n) - 0.5
	for i in n:
		if x < lefts[i + 1] or i == n - 1:
			var wdt := maxf(lefts[i + 1] - lefts[i], 0.001)
			return float(i) - 0.5 + clampf((x - lefts[i]) / wdt, 0.0, 1.0)
	return float(n) - 0.5


# Schwung-Projektion (WWDC18 „Designing Fluid Interfaces“): Endposition bei Abklingrate rate je ms; v in Einheiten pro Sekunde.
static func project(pos: float, velocity: float, rate := PROJECT_RATE) -> float:
	return pos + velocity / 1000.0 * rate / (1.0 - rate)


# Einrasten: nächste Kartenmitte zur projizierten Endposition.
static func snap(projected: float, n: int) -> int:
	return clampi(roundi(projected), 0, maxi(n - 1, 0))


# Gummiband: Überscroll x wird als (1 − 1/(x·c/d + 1))·d gezeigt (d = Abmessung, z. B. Handbreite).
static func rubber_band(x: float, dim: float, c := RUBBER_C) -> float:
	if dim <= 0.0:
		return 0.0
	var a := absf(x)
	var r := (1.0 - 1.0 / (a * c / dim + 1.0)) * dim
	return r if x >= 0.0 else -r


# Scrollwert mit Gummiband außerhalb von [0, n − 1]; px_per_card rechnet in Pixel um (das Gummiband wirkt in Pixeln).
static func rubber_scroll(raw: float, n: int, px_per_card: float, dim: float) -> float:
	var hi := float(maxi(n - 1, 0))
	if raw < 0.0:
		return rubber_band(raw * px_per_card, dim) / px_per_card
	if raw > hi:
		return hi + rubber_band((raw - hi) * px_per_card, dim) / px_per_card
	return raw


# Gedämpfte Feder, exakt gelöst (stabil bei jedem dt): Ergebnis (Position, Geschwindigkeit).
# zeta = 1: kritisch gedämpft (Einrasten ohne Überschwingen); zeta < 1: leicht federnd (Karten folgen ihrem Ziel).
static func spring(x: float, v: float, target: float, omega: float, zeta: float, dt: float) -> Vector2:
	var y := x - target
	if zeta >= 0.999:
		var e := exp(-omega * dt)
		var tmp := (v + omega * y) * dt
		return Vector2(target + (y + tmp) * e, (v - omega * tmp) * e)
	var wd := omega * sqrt(1.0 - zeta * zeta)
	var a := y
	var b := (v + zeta * omega * y) / wd
	var e2 := exp(-zeta * omega * dt)
	var c := cos(wd * dt)
	var s := sin(wd * dt)
	var ny := e2 * (a * c + b * s)
	var nv := e2 * (-zeta * omega * (a * c + b * s) + (-a * wd * s + b * wd * c))
	return Vector2(target + ny, nv)


# Geschwindigkeit aus den Touchproben der letzten ~100 ms (gewichtetes Mittel, neuere Abschnitte zählen mehr).
class Velocity:
	extends RefCounted
	const WINDOW_MS := 100.0
	var _t := PackedFloat64Array()
	var _p := PackedVector2Array()

	func reset() -> void:
		_t.clear()
		_p.clear()

	func add(t_ms: float, p: Vector2) -> void:
		_t.append(t_ms)
		_p.append(p)
		# alte Proben verwerfen (eine vor dem Fenster bleibt als Anfang des ersten Abschnitts)
		while _t.size() > 2 and _t[1] < t_ms - WINDOW_MS:
			_t.remove_at(0)
			_p.remove_at(0)

	# Pixel pro Sekunde; now_ms = Zeitpunkt des Loslassens.
	func get_velocity(now_ms: float) -> Vector2:
		var sum := Vector2.ZERO
		var wsum := 0.0
		for k in range(1, _t.size()):
			var t0 := _t[k - 1]
			var t1 := _t[k]
			if t1 < now_ms - WINDOW_MS:
				continue
			var dt := t1 - t0
			if dt <= 0.0:
				continue
			var recency := 1.0 - clampf((now_ms - t1) / WINDOW_MS, 0.0, 1.0)
			var w := dt * (0.5 + recency)
			sum += (_p[k] - _p[k - 1]) / (dt / 1000.0) * w
			wsum += w
		return sum / wsum if wsum > 0.0 else Vector2.ZERO


# Gestenerkennung als Zustandsmaschine. Eingabe: Zeit (ms) und Weg (Pixel); Ausgabe: Ereignisnamen für die Hand.
#   press → PENDING. Nach 8 dp entscheidet der Winkel: |dy| > 1,2·|dx| nach oben = Ausspielen ziehen ("play_drag"),
#   nach unten = "down" (ignoriert), sonst seitlich ("horizontal": Lupe gleiten bzw. Karussell drehen).
#   350 ms ohne Bewegung = Halten ("hold", Großansicht). Danach: oben = "play_drag", seitlich = "reorder" (umsortieren),
#   unten = "help_drag" (zum „?“). Aus dem seitlichen Gleiten führt ein deutlicher Zug nach oben ebenfalls zu "play_drag".
#   release → "tap" / "double_tap" / "play" / "cancel" / "help" / "hold_release" / "reorder_end" / "horizontal_end".
class Gesture:
	extends RefCounted
	enum S { IDLE, PENDING, HORIZONTAL, PLAY_DRAG, HOLD, REORDER, HELP, DOWN }
	const TOL_DP := 8.0
	const HOLD_MS := 350.0
	const DOUBLE_TAP_MS := 350.0
	const ANGLE_RATIO := 1.2
	const FLICK_DP := 1200.0           # Schnippen nach oben: > 1200 dp/s …
	const FLICK_DEG := 35.0            # … innerhalb ±35° der Senkrechten
	const HELP_DP := 40.0              # kurzer Zug nach unten bis zum „?“
	var dp := DP
	var play_dist := 180.0             # Weg nach oben, ab dem das Loslassen ausspielt (≈ 25 % Bildschirmhöhe)
	var help_dist := HELP_DP * DP      # Weg nach unten bis zum „?“ (die Hand kürzt ihn, wenn unten kein Platz ist)
	var hold_tol := -1.0               # Toleranz der Richtungsentscheidung nach dem Halten (≤ 0 = tol()); am unteren Rand kleiner
	var up_from_horizontal := true
	var state := S.IDLE
	var start := Vector2.ZERO
	var start_ms := 0.0
	var pos := Vector2.ZERO
	var anchor := Vector2.ZERO
	var help_armed := false
	var play_armed := false
	var velocity := Vector2.ZERO        # beim Loslassen gemessen
	var vel := Velocity.new()
	var _last_tap_ms := -100000.0
	var _last_tap_pos := Vector2(INF, INF)

	func tol() -> float:
		return TOL_DP * dp

	func is_active() -> bool:
		return state != S.IDLE

	func press(t_ms: float, p: Vector2) -> String:
		hold_tol = -1.0
		state = S.PENDING
		start = p
		pos = p
		anchor = p
		start_ms = t_ms
		help_armed = false
		play_armed = false
		velocity = Vector2.ZERO
		vel.reset()
		vel.add(t_ms, p)
		return "press"

	func tick(t_ms: float) -> String:
		if state == S.PENDING and t_ms - start_ms >= HOLD_MS:
			state = S.HOLD
			return "hold"
		return ""

	func move(t_ms: float, p: Vector2) -> String:
		if state == S.IDLE:
			return ""
		var held := tick(t_ms)
		pos = p
		vel.add(t_ms, p)
		var d := p - start
		match state:
			S.PENDING, S.HOLD:
				var lim := tol() if state == S.PENDING or hold_tol <= 0.0 else minf(hold_tol, tol())
				if d.length() < lim:
					return held
				var vertical := absf(d.y) > ANGLE_RATIO * absf(d.x)
				if state == S.PENDING:
					if vertical and d.y < 0.0:
						state = S.PLAY_DRAG
						return "play_drag"
					if vertical:
						state = S.DOWN
						return "down"
					state = S.HORIZONTAL
					anchor = p
					return "horizontal"
				if vertical and d.y < 0.0:
					state = S.PLAY_DRAG
					return "play_drag"
				if vertical:
					state = S.HELP
					help_armed = d.y >= help_dist
					return "help_drag"
				state = S.REORDER
				return "reorder"
			S.HORIZONTAL:
				var u := anchor - p
				if up_from_horizontal and u.y >= 2.0 * tol() and u.y > ANGLE_RATIO * absf(u.x):
					state = S.PLAY_DRAG
					start = anchor
					return "play_drag"
				if absf(u.x) > tol() and absf(u.x) > absf(u.y):
					anchor = p
				elif p.y > anchor.y:
					anchor.y = p.y
				return "move"
			S.PLAY_DRAG:
				play_armed = start.y - p.y >= play_dist
				return "move"
			S.HELP:
				help_armed = d.y >= help_dist
				return "move"
			S.REORDER:
				return "move"
		return ""

	func release(t_ms: float, p: Vector2) -> String:
		if state == S.IDLE:
			return ""
		move(t_ms, p)
		velocity = vel.get_velocity(t_ms)
		var was := state
		state = S.IDLE
		match was:
			S.PENDING:
				var dbl := t_ms - _last_tap_ms <= DOUBLE_TAP_MS and p.distance_to(_last_tap_pos) <= 2.0 * tol()
				_last_tap_ms = -100000.0 if dbl else t_ms
				_last_tap_pos = p
				return "double_tap" if dbl else "tap"
			S.HOLD:
				return "hold_release"
			S.PLAY_DRAG:
				return "play" if play_armed or is_flick(velocity) else "cancel"
			S.HELP:
				return "help" if help_armed else "cancel"
			S.REORDER:
				return "reorder_end"
			S.HORIZONTAL:
				return "horizontal_end"
		return "cancel"

	func cancel() -> void:
		state = S.IDLE

	# Schnippen nach oben: schnell genug und steil genug.
	func is_flick(v: Vector2) -> bool:
		var up := -v.y
		return up > FLICK_DP * dp and absf(v.x) <= up * tan(deg_to_rad(FLICK_DEG))
