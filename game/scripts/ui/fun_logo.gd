class_name FunLogo
extends RefCounted
# Geheimtipps im Logo des Hauptmenüs (Beta 1.4.4, nur lokal):
#  - 7-mal schnell auf die Katze tippen (Abstand höchstens GAP_MS): Sie maunzt, es regnet kurz Konfetti bzw. Sterne.
#  - Sonne (helle Karte) lange drücken: Sie grinst kurz. Mond (dunkle Karte) lange drücken: Er zwinkert kurz.
# Die Treffer-Bereiche beziehen sich auf das Logobild (800 × 450); die reine Logik steht hier, damit sie ohne Bildschirm testbar ist.

const TAPS := 7
const GAP_MS := 900
const HOLD_S := 0.6
const IMG := Vector2(800.0, 450.0)
const CAT_RECT := Rect2(305.0, 35.0, 180.0, 330.0)
const SUN := Vector3(255.0, 190.0, 56.0)       # Mitte x, y und Radius im Bild
const MOON := Vector3(565.0, 205.0, 62.0)

var _taps := 0
var _last_ms := -100000


# Bereich unter einem Punkt (normiert 0 … 1 im Logobild): "cat", "sun", "moon" oder ""
static func region(n: Vector2) -> String:
	var p := n * IMG
	if CAT_RECT.has_point(p):
		return "cat"
	if p.distance_to(Vector2(SUN.x, SUN.y)) <= SUN.z:
		return "sun"
	if p.distance_to(Vector2(MOON.x, MOON.y)) <= MOON.z:
		return "moon"
	return ""


# Ein Tipp auf die Katze zum Zeitpunkt now_ms; true beim TAPS-ten Tipp in Folge (danach beginnt die Zählung neu)
func register_tap(now_ms: int) -> bool:
	if now_ms - _last_ms > GAP_MS:
		_taps = 0
	_last_ms = now_ms
	_taps += 1
	if _taps >= TAPS:
		_taps = 0
		return true
	return false


func count() -> int:
	return _taps


func reset() -> void:
	_taps = 0
	_last_ms = -100000
