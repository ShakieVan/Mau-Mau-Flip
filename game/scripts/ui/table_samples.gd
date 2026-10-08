class_name TableSamples
extends RefCounted
# Beispieldaten für Demo, Tests und Kontrollbilder (Modul F1b, Phase 1 ohne Regelwerk): ein kleiner Kartenstand mit 112
# doppelseitigen Karten, aus dem Sichten (BETA1_PLAN Abschnitt 4, view_for) und passende Ereignisse entstehen.
# Kein Regelwerk: Züge werden von außen vorgegeben (play/draw/flip …); nur „spielbar“ ist grob nachgebildet.

const NAMES := ["Du", "Lena", "Tom", "Mia", "Ben", "Ida", "Ole", "Pia", "Max", "Zoe"]
const ACTIONS_LIGHT := ["plus1", "aussetzen", "richtungswechsel", "flip"]
const ACTIONS_DARK := ["plus5", "alle_aussetzen", "richtungswechsel", "flip"]
const KIND_ORDER := ["plus1", "plus5", "aussetzen", "alle_aussetzen", "richtungswechsel", "flip"]

var n := 4
var pairs: Array = []                 # Kennung → [helle Seite, dunkle Seite]
var hands: Array = []                 # Platz → Array[int]
var deck: Array[int] = []             # oberste Karte = letzte
var discard: Array[int] = []
var side := "hell"
var turn := 0
var dir := 1
var color := ""
var mau := {}
var places := {}
var scores: Array = []
var kinds: Array = []
var phase := "turn"
var pending := 0
var round_no := 1
var ranking: Array = []
var backs_visible := true
var scoring := "none"
var catch_targets: Array = []


static func faces_light() -> Array[String]:
	var out: Array[String] = []
	for c in UiPalette.LIGHT_COLORS:
		for v in range(1, 10):
			out.append("hell_%s_%d" % [c, v])
			out.append("hell_%s_%d" % [c, v])
		for a in ACTIONS_LIGHT:
			out.append("hell_%s_%s" % [c, a])
			out.append("hell_%s_%s" % [c, a])
	for i in 4:
		out.append("hell_wuenscher")
		out.append("hell_wuenscher_plus2")
	return out


static func faces_dark() -> Array[String]:
	var out: Array[String] = []
	for c in UiPalette.DARK_COLORS:
		for v in range(1, 10):
			out.append("dunkel_%s_%d" % [c, v])
			out.append("dunkel_%s_%d" % [c, v])
		for a in ACTIONS_DARK:
			out.append("dunkel_%s_%s" % [c, a])
			out.append("dunkel_%s_%s" % [c, a])
	for i in 4:
		out.append("dunkel_wuenscher")
		out.append("dunkel_farbjagd")
	return out


static func create(players := 4, seed := 7, hand_sizes: Array = []) -> TableSamples:
	var s := TableSamples.new()
	s.n = players
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var light := faces_light()
	var dark := faces_dark()
	_shuffle(dark, rng)
	var order: Array[int] = []
	for i in 112:
		s.pairs.append([light[i], dark[i]])
		order.append(i)
	_shuffle(order, rng)
	s.deck = order
	for p in players:
		s.hands.append([])
		s.scores.append(0)
		s.kinds.append("human" if p == 0 else ("bot" if p % 3 == 2 else "human"))
	for p in players:
		var k := int(hand_sizes[p]) if p < hand_sizes.size() else 7
		for j in k:
			s.hands[p].append(s.deck.pop_back())
	# Startkarte: eine Zahlenkarte
	for i in range(s.deck.size() - 1, -1, -1):
		var f := str(s.pairs[s.deck[i]][0])
		if f.right(1).is_valid_int():
			s.discard.append(s.deck[i])
			s.deck.remove_at(i)
			break
	s.color = CardTextures.color_of(s.top_face())
	return s


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t


func face(id: int) -> String:
	return str(pairs[id][0 if side == "hell" else 1])


func back(id: int) -> String:
	return str(pairs[id][1 if side == "hell" else 0])


func top_face() -> String:
	return face(discard[-1]) if not discard.is_empty() else ""


# Karte mit der gewünschten aktiven Seite aus dem Stapel (oder einer fremden Hand) in die Hand von seat legen
func give(seat: int, face_key: String) -> int:
	var id := _take_face(face_key, seat)
	if id >= 0:
		hands[seat].append(id)
	return id


# Oberste Ablagekarte setzen
func set_top(face_key: String) -> void:
	var id := _take_face(face_key, -1)
	if id >= 0:
		discard.append(id)
		var c := CardTextures.color_of(face_key)
		if c != "":
			color = c


# Sucht nach der Seite, die im Schlüssel steht (hell_… oder dunkel_…), unabhängig von der aktiven Seite
func _has(id: int, face_key: String) -> bool:
	return str(pairs[id][0 if face_key.begins_with("hell") else 1]) == face_key


func _take_face(face_key: String, exclude_seat: int) -> int:
	for i in range(deck.size() - 1, -1, -1):
		if _has(deck[i], face_key):
			var id := deck[i]
			deck.remove_at(i)
			return id
	for p in n:
		if p == exclude_seat:
			continue
		var h: Array = hands[p]
		for j in h.size():
			if _has(int(h[j]), face_key):
				var id := int(h[j])
				h.remove_at(j)
				h.append(deck.pop_back())
				return id
	return -1


# Oberste Stapelkarte festlegen (deren Gegenseite der Stapel zeigt)
func set_draw_top(face_key: String) -> void:
	for i in deck.size():
		if _has(deck[i], face_key):
			var id := deck[i]
			deck.remove_at(i)
			deck.append(id)
			return


func find_in_hand(seat: int, face_key: String) -> int:
	for id in hands[seat]:
		if face(int(id)) == face_key:
			return int(id)
	return -1


static func sort_key(face_key: String) -> String:
	# Seite, Farbe, Art, Wert (Gegnerhände neutral sortiert, 06 Abschnitt 2.3)
	var parts := face_key.split("_")
	var s := "0" if parts[0] == "hell" else "1"
	var cols := UiPalette.LIGHT_COLORS + UiPalette.DARK_COLORS
	var c := CardTextures.color_of(face_key)
	if c == "":
		return s + "9" + face_key
	var rest := face_key.substr(parts[0].length() + c.length() + 2)
	var kind := "0" + rest if rest.is_valid_int() else "1%d" % KIND_ORDER.find(rest)
	return s + str(cols.find(c)) + kind


func playable(id: int) -> bool:
	var f := face(id)
	var tf := top_face()
	if CardTextures.color_of(f) == "":
		return true
	if CardTextures.color_of(f) == color:
		return true
	var a := f.substr(f.find("_", f.find("_") + 1) + 1)
	var b := tf.substr(tf.find("_", tf.find("_") + 1) + 1)
	return a == b and CardTextures.color_of(tf) != ""


func view_for(seat: int) -> Dictionary:
	var players: Array = []
	for p in n:
		var backs: Array = []
		if backs_visible and p != seat:
			for id in hands[p]:
				backs.append(back(int(id)))
			backs.sort_custom(func(x: String, y: String) -> bool: return sort_key(x) < sort_key(y))
		players.append({"seat": p, "name": NAMES[p % NAMES.size()] if p != seat or seat != 0 else "Du", "kind": kinds[p], "count": hands[p].size(),
			"backs": backs, "place": int(places.get(p, 0)), "mau": bool(mau.get(p, false)), "connected": true, "score": int(scores[p])})
	var hand: Array = []
	var playable_ids: Array = []
	if seat >= 0:
		for id in hands[seat]:
			hand.append({"id": int(id), "face": face(int(id)), "back": back(int(id))})
			if turn == seat and playable(int(id)):
				playable_ids.append(int(id))
	var my_turn := turn == seat
	var text := "Du bist dran." if my_turn else "%s ist dran." % NAMES[turn % NAMES.size()]
	var lt: Array = [] if my_turn else [I18n.part("%s ist dran.", [NAMES[turn % NAMES.size()]])]
	if phase == "round_over":
		text = "Runde vorbei."
		lt = []
	var v := {
		"v": 1, "seat": seat, "side": side, "phase": phase, "turn": turn, "dir": dir, "color": color,
		"players": players, "hand": hand,
		"top": {"id": discard[-1] if not discard.is_empty() else -1, "face": top_face()},
		"draw_back": back(deck[-1]) if not deck.is_empty() else "", "draw_count": deck.size(),
		"pending": {"kind": "stack", "amount": pending} if pending > 0 else {},
		"hints": {"playable": playable_ids, "can_draw": my_turn and phase == "turn", "can_keep": false, "can_challenge": false,
			"can_mau": my_turn and seat >= 0 and hands[seat].size() == 2, "catch": catch_targets.duplicate(), "need_color": false, "text": text, "lt": lt},
		"round": round_no, "ranking": ranking.duplicate(),
		"rules": {"backs_visible": backs_visible, "scoring": scoring, "hand_size": 7, "peek_own_backs": true},
	}
	return v


# Ereignisse für einen Empfänger filtern (gezogene Gesichter nur für den Ziehenden)
func events_for(seat: int, events: Array) -> Array:
	var out: Array = []
	for ev in events:
		var e: Dictionary = (ev as Dictionary).duplicate(true)
		if str(e.get("e", "")) == "draw" and int(e.get("seat", -1)) != seat:
			e.erase("faces")
		out.append(e)
	return out


func advance(steps := 1) -> void:
	turn = posmod(turn + dir * steps, n)


# ---------------------------------------------------------------- Züge (ohne Regelprüfung)

func play(seat: int, id: int, wish := "") -> Array:
	var events: Array = []
	hands[seat].erase(id)
	discard.append(id)
	var f := face(id)
	events.append({"e": "play", "seat": seat, "card": id, "face": f})
	var c := CardTextures.color_of(f)
	if c != "":
		color = c
	if wish != "":
		color = wish
		events.append({"e": "color", "color": wish})
	mau.erase(seat)
	return events


func draw(seat: int, count: int) -> Array:
	var faces: Array = []
	for i in count:
		if deck.is_empty():
			break
		var id: int = deck.pop_back()
		hands[seat].append(id)
		faces.append(face(id))
	return [{"e": "draw", "seat": seat, "count": faces.size(), "faces": faces}]


func flip() -> Array:
	side = "dunkel" if side == "hell" else "hell"
	var c := CardTextures.color_of(top_face())
	if c != "":
		color = c
	return [{"e": "flip", "side": side}]


func call_mau(seat: int) -> Array:
	mau[seat] = true
	return [{"e": "mau", "seat": seat}]


func finish_round(winner: int) -> Array:
	phase = "round_over"
	ranking = [winner]
	var others: Array = []
	for p in n:
		if p != winner:
			others.append(p)
	others.sort_custom(func(a: int, b: int) -> bool: return hands[a].size() < hands[b].size())
	ranking.append_array(others)
	places[winner] = 1
	return [{"e": "round_over", "ranking": ranking.duplicate(), "scores": scores.duplicate()}]


# Stapel so ordnen, dass die Karten in dieser Reihenfolge gezogen werden (erste zuerst)
func stack_deck(keys: Array) -> void:
	for i in range(keys.size() - 1, -1, -1):
		var id := _take_face(str(keys[i]), -1)
		if id >= 0:
			deck.append(id)


func find_any(seat: int, face_key: String) -> int:
	for id in hands[seat]:
		if _has(int(id), face_key):
			return int(id)
	return -1
