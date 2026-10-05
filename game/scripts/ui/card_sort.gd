class_name CardSort
extends RefCounted
# Sortierung der eigenen Hand (docs/recherche/06_hand_ux_effekte.md Abschnitt 2): Farbe, Wert, Punkte, manuell.
# Sortiert wird immer nach der aktiven Seite, also nach dem Gesichtsschlüssel "face" der Handkarte (docs/BETA1_PLAN.md
# Abschnitt 3: "<seite>_<farbe>_<wert>" bzw. "<seite>_<joker>"). Joker stehen in jeder automatischen Sortierung rechts.
# Reine Funktionen, keine Abhängigkeit vom Regelwerk (Punktwerte nach docs/recherche/07_regeln_hausregeln.md 1.12).

const MODES := ["farbe", "wert", "punkte", "manuell"]
const LABELS := {"farbe": "Farbe", "wert": "Wert", "punkte": "Punkte", "manuell": "Manuell"}
const COLOR_ORDER := {"hell": ["rot", "gelb", "gruen", "blau"], "dunkel": ["pink", "tuerkis", "orange", "lila"]}
const ACTION_ORDER := ["plus1", "plus5", "aussetzen", "alle_aussetzen", "richtungswechsel", "flip"]
const JOKER_ORDER := ["wuenscher", "wuenscher_plus2", "farbjagd"]
const POINTS := {"plus1": 10, "plus5": 20, "aussetzen": 20, "richtungswechsel": 20, "flip": 20, "alle_aussetzen": 30,
	"wuenscher": 40, "wuenscher_plus2": 50, "farbjagd": 60}


# Gesicht zerlegen: {side, color, kind, value, joker}. kind = "zahl" (value 1–9), Aktionsname oder Jokername.
static func parse(face: String) -> Dictionary:
	var parts := face.split("_")
	var side := parts[0] if parts.size() > 0 and (parts[0] == "hell" or parts[0] == "dunkel") else ""
	var out := {"side": side, "color": "", "kind": "", "value": 0, "joker": false}
	if side == "" or parts.size() < 2:
		out.kind = face
		return out
	var all_colors: Array = COLOR_ORDER.hell + COLOR_ORDER.dunkel
	if all_colors.has(parts[1]) and parts.size() >= 3:
		out.color = parts[1]
		var rest := "_".join(parts.slice(2))
		if rest.is_valid_int():
			out.kind = "zahl"
			out.value = int(rest)
		else:
			out.kind = rest
	else:
		out.kind = "_".join(parts.slice(1))
		out.joker = true
	return out


static func points(face: String) -> int:
	var p := parse(face)
	if p.kind == "zahl":
		return int(p.value)
	return int(POINTS.get(p.kind, 0))


static func _color_rank(p: Dictionary) -> int:
	var order: Array = COLOR_ORDER.get(p.side, [])
	var i := order.find(p.color)
	return i if i >= 0 else 9


# Rang innerhalb einer Farbe: Zahlen aufsteigend, dann Aktionen in fester Folge.
static func _kind_rank(p: Dictionary) -> int:
	if p.kind == "zahl":
		return int(p.value)
	var a := ACTION_ORDER.find(p.kind)
	if a >= 0:
		return 10 + a
	var j := JOKER_ORDER.find(p.kind)
	return 20 + (j if j >= 0 else 9)


static func _key(card: Dictionary, mode: String) -> Array:
	var p := parse(str(card.get("face", "")))
	var joker := 1 if p.joker else 0
	match mode:
		"wert":
			return [joker, _kind_rank(p), _color_rank(p), int(card.get("id", 0))]
		"punkte":
			# aufsteigend: billige links, teure (Joker) rechts
			return [joker, points(str(card.get("face", ""))), _color_rank(p), _kind_rank(p), int(card.get("id", 0))]
	return [joker, _color_rank(p), _kind_rank(p), int(card.get("id", 0))]


static func _less(a: Array, b: Array) -> bool:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return a[i] < b[i]
	return a.size() < b.size()


# Karten [{id, face, back}] sortiert (Kopie). "manuell" lässt die Reihenfolge unverändert.
static func sort_cards(cards: Array, mode: String) -> Array:
	var out := cards.duplicate()
	if mode == "manuell":
		return out
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _less(_key(a, mode), _key(b, mode)))
	return out


static func sort_ids(cards: Array, mode: String) -> Array[int]:
	var ids: Array[int] = []
	for c in sort_cards(cards, mode):
		ids.append(int(c.id))
	return ids


# Manuelle Reihenfolge: bekannte Karten bleiben in ihrer Folge, neue kommen rechts dazu (in der übergebenen Folge).
static func merge_manual(previous: Array, cards: Array) -> Array[int]:
	var present := {}
	for c in cards:
		present[int(c.id)] = true
	var ids: Array[int] = []
	for id in previous:
		if present.has(int(id)) and not ids.has(int(id)):
			ids.append(int(id))
	for c in cards:
		if not ids.has(int(c.id)):
			ids.append(int(c.id))
	return ids


# Gruppe einer Karte für die Lücken: Farbe nach Farben (Joker eigene Gruppe), sonst nur Joker getrennt.
static func group_of(face: String, mode: String) -> String:
	var p := parse(face)
	if p.joker:
		return "joker"
	if mode == "farbe":
		return str(p.color)
	return "karte"


# Indizes (in der angezeigten Folge), vor denen eine Gruppenlücke liegt (6 dp, HandLayout.GROUP_GAP).
static func group_starts(faces: Array, mode: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	if mode == "manuell":
		return out
	for i in range(1, faces.size()):
		if group_of(str(faces[i]), mode) != group_of(str(faces[i - 1]), mode):
			out.append(i)
	return out


static func next_mode(mode: String) -> String:
	var i := MODES.find(mode)
	return MODES[(i + 1) % MODES.size()]
