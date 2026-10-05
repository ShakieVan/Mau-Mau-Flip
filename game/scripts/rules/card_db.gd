class_name CardDB
extends RefCounted
# Kartendaten (docs/BETA1_PLAN.md Abschnitt 3, Regelbericht 1.1): 112 doppelseitige Karten, je Seite 112 Gesichter,
# zusammen 108 verschiedene. Ein Gesicht ist {side, color, kind, value}; Joker haben color "" und value 0, Aktionskarten value 0.
# Es gibt keine 0. Welche helle Seite auf welcher dunklen liegt, bestimmt MauGame je Runde aus dem Seed.
#
# Intern rechnet das Regelwerk mit Gesichtscodes (Index in all_keys()), damit die Bot-Dauerläufe schnell bleiben. Die Codes sind
# zugleich die Sortierreihenfolge „Seite, Farbe, Art, Wert“ (Rückseiten der Mitspieler, Kartenhilfe).

const SIDES: Array[String] = ["hell", "dunkel"]
const COLORS := {"hell": ["rot", "gelb", "gruen", "blau"], "dunkel": ["pink", "tuerkis", "orange", "lila"]}
# Farbige Aktionskarten je Seite (je Farbe zweimal), danach die Joker (je viermal).
const ACTIONS := {"hell": ["plus1", "aussetzen", "richtungswechsel", "flip"], "dunkel": ["plus5", "alle_aussetzen", "richtungswechsel", "flip"]}
const WILDS := {"hell": ["wuenscher", "wuenscher_plus2"], "dunkel": ["wuenscher", "farbjagd"]}
const POINTS := {"plus1": 10, "plus5": 20, "aussetzen": 20, "richtungswechsel": 20, "flip": 20, "alle_aussetzen": 30,
	"wuenscher": 40, "wuenscher_plus2": 50, "farbjagd": 60}
# Ziehkarten und ihre Kartenzahl (Farbjagd: bis zur Farbe).
const DRAW_AMOUNT := {"plus1": 1, "plus5": 5, "wuenscher_plus2": 2, "farbjagd": 0}
const CARD_COUNT := 112
const FACE_COUNT := 108
const SUM_LIGHT := 1280
const SUM_DARK := 1480

static var _built := false
static var _keys := PackedStringArray()
static var _side := PackedInt32Array()       # 0 hell, 1 dunkel
static var _color := PackedStringArray()     # "" bei Jokern
static var _kind := PackedStringArray()
static var _value := PackedInt32Array()
static var _points := PackedInt32Array()
static var _wild := PackedByteArray()        # 1 = Joker (passt immer)
static var _code_by_key := {}
static var _deck: Array = []                 # je Seite 112 Gesichtscodes (mit Doppelten)


static func _build() -> void:
	if _built:
		return
	for s in SIDES.size():
		var side: String = SIDES[s]
		var deck := PackedInt32Array()
		for color: String in COLORS[side]:
			for v in range(1, 10):
				var code := _add(s, color, "zahl", v)
				deck.append(code)
				deck.append(code)
			for kind: String in ACTIONS[side]:
				var code := _add(s, color, kind, 0)
				deck.append(code)
				deck.append(code)
		for kind: String in WILDS[side]:
			var code := _add(s, "", kind, 0)
			for i in 4:
				deck.append(code)
		_deck.append(deck)
	_built = true


static func _add(s: int, color: String, kind: String, value: int) -> int:
	var code := _keys.size()
	var face := {"side": SIDES[s], "color": color, "kind": kind, "value": value}
	var key := face_key(face)
	_keys.append(key)
	_side.append(s)
	_color.append(color)
	_kind.append(kind)
	_value.append(value)
	_points.append(value if kind == "zahl" else int(POINTS[kind]))
	_wild.append(1 if color == "" else 0)
	_code_by_key[key] = code
	return code


# --- Gesichter als Dictionary (für Oberfläche und Tests) ---

# Schlüssel eines Gesichts: farbig <seite>_<farbe>_<wert|art>, Joker <seite>_<art>.
static func face_key(face: Dictionary) -> String:
	var side := str(face.get("side", ""))
	var kind := str(face.get("kind", ""))
	var color := str(face.get("color", ""))
	if color == "":
		return "%s_%s" % [side, kind]
	if kind == "zahl":
		return "%s_%s_%d" % [side, color, int(face.get("value", 0))]
	return "%s_%s_%s" % [side, color, kind]


# Die 112 Gesichter der hellen bzw. dunklen Seite (mit Doppelten), in Codereihenfolge.
static func faces_light() -> Array[Dictionary]:
	return _faces_of(0)


static func faces_dark() -> Array[Dictionary]:
	return _faces_of(1)


static func _faces_of(s: int) -> Array[Dictionary]:
	_build()
	var out: Array[Dictionary] = []
	for code in _deck[s]:
		out.append(face(code))
	return out


static func face(code: int) -> Dictionary:
	_build()
	return {"side": SIDES[_side[code]], "color": _color[code], "kind": _kind[code], "value": _value[code]}


static func parse_key(key: String) -> Dictionary:
	var code := code_of(key)
	return face(code) if code >= 0 else {}


static func is_key(key: String) -> bool:
	_build()
	return _code_by_key.has(key)


# Alle 108 verschiedenen Gesichtsschlüssel (sortiert nach Seite, Farbe, Art, Wert).
static func all_keys() -> PackedStringArray:
	_build()
	return _keys


static func points(face_dict: Dictionary) -> int:
	var kind := str(face_dict.get("kind", ""))
	return int(face_dict.get("value", 0)) if kind == "zahl" else int(POINTS.get(kind, 0))


static func points_of_key(key: String) -> int:
	var code := code_of(key)
	return _points[code] if code >= 0 else 0


static func colors(side: String) -> Array:
	return COLORS.get(side, [])


static func other_side(side: String) -> String:
	return "dunkel" if side == "hell" else "hell"


static func is_wild(face_dict: Dictionary) -> bool:
	return str(face_dict.get("color", "")) == ""


static func is_draw_card(face_dict: Dictionary) -> bool:
	return DRAW_AMOUNT.has(str(face_dict.get("kind", "")))


static func is_action(face_dict: Dictionary) -> bool:
	return str(face_dict.get("kind", "")) != "zahl"


# Sortiert Schlüssel nach Seite, Farbe, Art und Wert (unbekannte Schlüssel ans Ende).
static func sort_keys(keys: Array) -> Array:
	_build()
	var codes := PackedInt32Array()
	var unknown: Array = []
	for k in keys:
		var c := code_of(str(k))
		if c >= 0:
			codes.append(c)
		else:
			unknown.append(k)
	codes.sort()
	var out: Array = []
	for c in codes:
		out.append(_keys[c])
	out.append_array(unknown)
	return out


# --- Codes (schneller Zugriff für das Regelwerk) ---

static func code_of(key: String) -> int:
	_build()
	return int(_code_by_key.get(key, -1))


static func deck(s: int) -> PackedInt32Array:
	_build()
	return _deck[s]


static func key_table() -> PackedStringArray:
	_build()
	return _keys


static func side_table() -> PackedInt32Array:
	_build()
	return _side


static func color_table() -> PackedStringArray:
	_build()
	return _color


static func kind_table() -> PackedStringArray:
	_build()
	return _kind


static func value_table() -> PackedInt32Array:
	_build()
	return _value


static func points_table() -> PackedInt32Array:
	_build()
	return _points


static func wild_table() -> PackedByteArray:
	_build()
	return _wild
