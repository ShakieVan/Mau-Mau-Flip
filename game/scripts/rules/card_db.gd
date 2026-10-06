class_name CardDB
extends RefCounted
# Kartendaten (docs/BETA1_PLAN.md Abschnitt 3, Regelbericht 1.1): 112 doppelseitige Karten, je Seite 112 Gesichter,
# zusammen 108 verschiedene. Ein Gesicht ist {side, color, kind, value}; Joker haben color "" und value 0, Aktionskarten value 0.
# Es gibt keine 0. Welche helle Seite auf welcher dunklen liegt, bestimmt MauGame je Runde aus dem Seed.
#
# Hausregeln mit Zusatzkarten (docs/module/A.md, Abschnitte „Kartentausch“, „Glücksspiel“, „Farbe mit ablegen“), jede einzeln
# zuschaltbar; das Deck einer Partie ist das Grunddeck plus die Zusatzkarten der eingeschalteten Hausregeln, in dieser Reihenfolge:
# - Kartentausch (RuleConfig.swap_cards = "on"): 4 Karten, je Seite eine Kartentausch-Karte (Art "tausch", 20 Punkte) je Farbe.
# - Glücksspiel (gamble_cards = "on"): 2 Karten, je Seite zweimal der Joker "gluecksspiel" (50 Punkte).
# - Farbe mit ablegen (discard_color = "on"): 6 Karten, je Seite eine Ablegen-Karte (Art "ablegen", 30 Punkte) je Farbe und
#   zweimal den Ablegen-Joker "ablegen_joker" (50 Punkte).
# Kartenzahl also 112 + 4 + 2 + 6 je nach Optionen (höchstens 124), verschiedene Gesichter 108 + 8 + 2 + 10 (höchstens 128).
#
# Intern rechnet das Regelwerk mit Gesichtscodes (Index in key_table()), damit die Bot-Dauerläufe schnell bleiben. Die Codes des
# Grunddecks (0–107) sind seit Beta 0.1.1 fest, weil Spielstände (MauGame.to_dict) sie speichern; dahinter hängen die Zusatzkarten
# (108–115 Kartentausch, 116–117 Glücksspiel, 118–127 Farbe mit ablegen) und bleiben ebenso fest. Sortiert wird daher nicht nach
# Code, sondern nach Rang (rank_table/order_table): „Seite, Farbe, Art, Wert“; in ihrer Farbe stehen Kartentausch und Ablegen-Karte
# hinter dem Flip, unter den Jokern der Seite Glücksspiel und Ablegen-Joker hinter den bisherigen.

const SIDES: Array[String] = ["hell", "dunkel"]
const COLORS := {"hell": ["rot", "gelb", "gruen", "blau"], "dunkel": ["pink", "tuerkis", "orange", "lila"]}
# Farbige Aktionskarten je Seite (je Farbe zweimal), danach die Joker (je viermal).
const ACTIONS := {"hell": ["plus1", "aussetzen", "richtungswechsel", "flip"], "dunkel": ["plus5", "alle_aussetzen", "richtungswechsel", "flip"]}
const WILDS := {"hell": ["wuenscher", "wuenscher_plus2"], "dunkel": ["wuenscher", "farbjagd"]}
const SWAP := "tausch"                       # Kartentausch-Karte (je Seite und Farbe einmal, nur mit swap_cards = "on")
const GAMBLE := "gluecksspiel"               # Glücksspiel-Joker (je Seite zweimal, nur mit gamble_cards = "on")
const DISCARD := "ablegen"                   # Farbe ablegen (je Seite und Farbe einmal, nur mit discard_color = "on")
const DISCARD_WILD := "ablegen_joker"        # Ablegen-Joker (je Seite zweimal, nur mit discard_color = "on")
const POINTS := {"plus1": 10, "plus5": 20, "aussetzen": 20, "richtungswechsel": 20, "flip": 20, "alle_aussetzen": 30,
	"wuenscher": 40, "wuenscher_plus2": 50, "farbjagd": 60, "tausch": 20, "gluecksspiel": 50, "ablegen": 30, "ablegen_joker": 50}
# Ziehkarten und ihre Kartenzahl (Farbjagd: bis zur Farbe).
const DRAW_AMOUNT := {"plus1": 1, "plus5": 5, "wuenscher_plus2": 2, "farbjagd": 0}
const CARD_COUNT := 112
const FACE_COUNT := 108
const SUM_LIGHT := 1280
const SUM_DARK := 1480
# Mit Kartentausch: je Seite 4 Karten zu 20 Punkten mehr.
const CARD_COUNT_SWAP := 116
const FACE_COUNT_SWAP := 116
const SUM_LIGHT_SWAP := 1360
const SUM_DARK_SWAP := 1560
# Zusatzkarten je Hausregel: doppelseitige Karten, verschiedene Gesichter (beide Seiten) und Punkte je Seite.
const EXTRA_CARDS := {"swap": 4, "gamble": 2, "discard": 6}
const EXTRA_FACES := {"swap": 8, "gamble": 2, "discard": 10}
const EXTRA_POINTS := {"swap": 80, "gamble": 100, "discard": 220}
const CARD_COUNT_ALL := 124                  # alle Hausregeln an
const FACE_COUNT_ALL := 128                  # alle verschiedenen Gesichter
const SUM_LIGHT_ALL := 1680
const SUM_DARK_ALL := 1880

static var _built := false
static var _keys := PackedStringArray()
static var _side := PackedInt32Array()       # 0 hell, 1 dunkel
static var _color := PackedStringArray()     # "" bei Jokern
static var _kind := PackedStringArray()
static var _value := PackedInt32Array()
static var _points := PackedInt32Array()
static var _wild := PackedByteArray()        # 1 = Joker (passt immer)
static var _code_by_key := {}
static var _base: Array = []                 # je Seite die 112 Gesichtscodes des Grunddecks (mit Doppelten)
static var _extra := {}                      # "swap"/"gamble"/"discard" → je Seite die Zusatzcodes (mit Doppelten)
static var _decks := {}                      # Variante (Bitmaske 1 Tausch, 2 Glücksspiel, 4 Ablegen) → [hell, dunkel]
static var _order := PackedInt32Array()      # alle Codes in Sortierreihenfolge
static var _rank := PackedInt32Array()       # Code → Platz in _order
static var _sorted_base := PackedStringArray()   # 108 Schlüssel sortiert
static var _sorted_all := PackedStringArray()    # alle 128 Schlüssel sortiert


static func _build() -> void:
	if _built:
		return
	# Grunddeck: Codes 0–107 in genau dieser Reihenfolge (gespeicherte Spielstände hängen daran).
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
		_base.append(deck)
	# Kartentausch: Codes 108–115, je Seite eine Karte je Farbe.
	_extra["swap"] = []
	for s in SIDES.size():
		var part := PackedInt32Array()
		for color: String in COLORS[SIDES[s]]:
			part.append(_add(s, color, SWAP, 0))
		_extra["swap"].append(part)
	# Glücksspiel: Codes 116 (hell) und 117 (dunkel), je Seite zweimal.
	_extra["gamble"] = []
	for s in SIDES.size():
		var code := _add(s, "", GAMBLE, 0)
		_extra["gamble"].append(PackedInt32Array([code, code]))
	# Farbe mit ablegen: Codes 118–122 (hell: rot, gelb, gruen, blau, Joker) und 123–127 (dunkel), Joker je Seite zweimal.
	_extra["discard"] = []
	for s in SIDES.size():
		var part := PackedInt32Array()
		for color: String in COLORS[SIDES[s]]:
			part.append(_add(s, color, DISCARD, 0))
		var wild := _add(s, "", DISCARD_WILD, 0)
		part.append(wild)
		part.append(wild)
		_extra["discard"].append(part)
	# Decks aller 8 Varianten: Grunddeck, dann Kartentausch, Glücksspiel, Ablegen (soweit eingeschaltet).
	for mask in 8:
		var pair: Array = []
		for s in SIDES.size():
			var deck := PackedInt32Array(_base[s])
			if mask & 1:
				deck.append_array(_extra["swap"][s])
			if mask & 2:
				deck.append_array(_extra["gamble"][s])
			if mask & 4:
				deck.append_array(_extra["discard"][s])
			pair.append(deck)
		_decks[mask] = pair
	# Sortierreihenfolge: Seite, Farbe (Zahlen, Aktionen, Kartentausch, Ablegen), danach die Joker der Seite.
	for s in SIDES.size():
		var side: String = SIDES[s]
		for color: String in COLORS[side]:
			for v in range(1, 10):
				_order.append(_code_by_key["%s_%s_%d" % [side, color, v]])
			for kind: String in ACTIONS[side] + [SWAP, DISCARD]:
				_order.append(_code_by_key["%s_%s_%s" % [side, color, kind]])
		for kind: String in WILDS[side] + [GAMBLE, DISCARD_WILD]:
			_order.append(_code_by_key["%s_%s" % [side, kind]])
	_rank.resize(_keys.size())
	for i in _order.size():
		_rank[_order[i]] = i
		_sorted_all.append(_keys[_order[i]])
		if _order[i] < FACE_COUNT:
			_sorted_base.append(_keys[_order[i]])
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


# Variante als Bitmaske: 1 Kartentausch, 2 Glücksspiel, 4 Farbe mit ablegen.
static func variant(with_swap := false, with_gamble := false, with_discard := false) -> int:
	return (1 if with_swap else 0) | (2 if with_gamble else 0) | (4 if with_discard else 0)


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


# Die 112 Gesichter der hellen bzw. dunklen Seite (mit Doppelten), in Codereihenfolge des Decks; mit Hausregeln dazu deren
# Zusatzkarten (Kartentausch +4, Glücksspiel +2, Farbe mit ablegen +6).
static func faces_light(with_swap := false, with_gamble := false, with_discard := false) -> Array[Dictionary]:
	return _faces_of(0, variant(with_swap, with_gamble, with_discard))


static func faces_dark(with_swap := false, with_gamble := false, with_discard := false) -> Array[Dictionary]:
	return _faces_of(1, variant(with_swap, with_gamble, with_discard))


static func _faces_of(s: int, mask: int) -> Array[Dictionary]:
	_build()
	var out: Array[Dictionary] = []
	for code in _decks[mask][s]:
		out.append(face(code))
	return out


# Kartenzahl der Deckvariante: 112, mit Kartentausch +4, Glücksspiel +2, Farbe mit ablegen +6.
static func card_count(with_swap := false, with_gamble := false, with_discard := false) -> int:
	return CARD_COUNT + (EXTRA_CARDS.swap if with_swap else 0) + (EXTRA_CARDS.gamble if with_gamble else 0) \
		+ (EXTRA_CARDS.discard if with_discard else 0)


# Zahl der verschiedenen Gesichter (beide Seiten) der Deckvariante: 108 + 8 / 2 / 10.
static func face_count(with_swap := false, with_gamble := false, with_discard := false) -> int:
	return FACE_COUNT + (EXTRA_FACES.swap if with_swap else 0) + (EXTRA_FACES.gamble if with_gamble else 0) \
		+ (EXTRA_FACES.discard if with_discard else 0)


# Prüfsumme der Punkte einer Seite (s: 0 hell, 1 dunkel) in der Deckvariante: hell 1280, dunkel 1480, dazu je Seite
# Kartentausch +80, Glücksspiel +100, Farbe mit ablegen +220.
static func point_sum(s: int, with_swap := false, with_gamble := false, with_discard := false) -> int:
	return (SUM_LIGHT if s == 0 else SUM_DARK) + (EXTRA_POINTS.swap if with_swap else 0) \
		+ (EXTRA_POINTS.gamble if with_gamble else 0) + (EXTRA_POINTS.discard if with_discard else 0)


static func face(code: int) -> Dictionary:
	_build()
	return {"side": SIDES[_side[code]], "color": _color[code], "kind": _kind[code], "value": _value[code]}


static func parse_key(key: String) -> Dictionary:
	var code := code_of(key)
	return face(code) if code >= 0 else {}


static func is_key(key: String) -> bool:
	_build()
	return _code_by_key.has(key)


# Alle 108 verschiedenen Gesichtsschlüssel des Grunddecks (sortiert nach Seite, Farbe, Art, Wert); with_extras: alle 128
# einschließlich der Zusatzkarten aller Hausregeln (Kartentausch, Glücksspiel, Farbe mit ablegen).
static func all_keys(with_extras := false) -> PackedStringArray:
	_build()
	return _sorted_all if with_extras else _sorted_base


# Die 8 Kartentausch-Gesichter (sortiert).
static func swap_keys() -> PackedStringArray:
	return _keys_of_kinds([SWAP])


# Die 2 Glücksspiel-Gesichter (hell_gluecksspiel, dunkel_gluecksspiel).
static func gamble_keys() -> PackedStringArray:
	return _keys_of_kinds([GAMBLE])


# Die 10 Gesichter von „Farbe mit ablegen“ (je Seite 4 farbige und der Ablegen-Joker, sortiert).
static func discard_keys() -> PackedStringArray:
	return _keys_of_kinds([DISCARD, DISCARD_WILD])


static func _keys_of_kinds(kinds: Array) -> PackedStringArray:
	_build()
	var out := PackedStringArray()
	for k in _sorted_all:
		if kinds.has(_kind[int(_code_by_key[k])]):
			out.append(k)
	return out


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


static func is_swap(face_dict: Dictionary) -> bool:
	return str(face_dict.get("kind", "")) == SWAP


static func is_gamble(face_dict: Dictionary) -> bool:
	return str(face_dict.get("kind", "")) == GAMBLE


# Farbige Ablegen-Karte oder Ablegen-Joker.
static func is_discard(face_dict: Dictionary) -> bool:
	var kind := str(face_dict.get("kind", ""))
	return kind == DISCARD or kind == DISCARD_WILD


# Sortiert Schlüssel nach Seite, Farbe, Art und Wert (unbekannte Schlüssel ans Ende).
static func sort_keys(keys: Array) -> Array:
	_build()
	var ranks := PackedInt32Array()
	var unknown: Array = []
	for k in keys:
		var c := code_of(str(k))
		if c >= 0:
			ranks.append(_rank[c])
		else:
			unknown.append(k)
	ranks.sort()
	var out: Array = []
	for r in ranks:
		out.append(_keys[_order[r]])
	out.append_array(unknown)
	return out


# --- Codes (schneller Zugriff für das Regelwerk) ---

static func code_of(key: String) -> int:
	_build()
	return int(_code_by_key.get(key, -1))


# Gesichtscodes einer Seite mit Doppelten: Grunddeck (112) plus die Zusatzkarten der eingeschalteten Hausregeln, in der
# Reihenfolge Kartentausch, Glücksspiel, Farbe mit ablegen. Nicht verändern (geteilte Daten).
static func deck(s: int, with_swap := false, with_gamble := false, with_discard := false) -> PackedInt32Array:
	_build()
	return _decks[variant(with_swap, with_gamble, with_discard)][s]


# Sortierrang je Code (rank_table()[code]) und die Codes in Sortierreihenfolge (order_table()[rang]).
static func rank_table() -> PackedInt32Array:
	_build()
	return _rank


static func order_table() -> PackedInt32Array:
	_build()
	return _order


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
