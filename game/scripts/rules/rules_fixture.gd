class_name RulesFixture
extends RefCounted
# Baut gezielte Spielsituationen für Tests und Kontrollbilder (z. B. Hand mit 25 Karten, Joker nach Flip). Setzt Hände, Stapel
# und Zustand direkt; alle Karten bleiben im Spiel (112, mit den Hausregeln dazu deren Zusatzkarten: swap_cards = "on"
# "hell_<farbe>_tausch" / "dunkel_<farbe>_tausch", gamble_cards = "on" "hell_gluecksspiel" / "dunkel_gluecksspiel",
# discard_color = "on" "hell_<farbe>_ablegen", "hell_ablegen_joker" usw.; g.n_cards ist die Kartenzahl der Variante).
#
# Karten werden als Gesichtsschlüssel angegeben: "hell_rot_7" (die andere Seite füllt die Vorrichtung mit einer freien Zahlenkarte)
# oder "hell_rot_7/dunkel_lila_2" (beide Seiten, Reihenfolge egal). Fehlt ein Gesicht im Vorrat, gibt es push_error.
#
# spec (alles optional):
#   side: "hell"|"dunkel"         aktive Seite
#   hands: [[Schlüssel, …], …]    je Platz, in Besitzerreihenfolge
#   top: Schlüssel                oberste Ablagekarte; discard: [Schlüssel, …] darunter (unterste zuerst)
#   draw: [Schlüssel, …]          Nachziehstapel von oben; draw_bottom: [Schlüssel, …] ganz unten (unterste zuerst)
#   rest: "draw"|"discard"        wohin die übrigen Karten kommen (Standard: Nachziehstapel zwischen draw und draw_bottom;
#                                 "discard": unter die Ablage, dann ist der Nachziehstapel nur draw + draw_bottom)
#   current, dir, color, wished, phase ("turn" …), dealer, round, scores, mau_said: [Plätze], finished: [Plätze], host (Platz)
#   gamble: {q, stake: [Schlüssel, …], need: "stake"|"press", last}   laufendes Glücksspiel des Platzes current (dazu
#                                 phase "gamble"); stake = Einsatz, zuerst gelegte Karte zuerst

const NAMES := ["Anna", "Ben", "Cleo", "Dani", "Emil", "Fritzi", "Gus", "Hanna", "Ida", "Jo"]

var _pool: Array = [[], []]     # freie Gesichtscodes je Seite (mit Doppelten)
var _next_id := 0
var _game: MauGame


static func players(n: int, kind := "human") -> Array:
	var out: Array = []
	for i in n:
		out.append({"name": NAMES[i % NAMES.size()], "kind": kind})
	return out


static func build(config: RuleConfig, player_count: int, spec: Dictionary, rng_seed := 4711) -> MauGame:
	var fx := RulesFixture.new()
	return fx._build(config, player_count, spec, rng_seed)


# id der ersten Karte mit diesem (aktiven) Gesicht in der Hand eines Platzes, sonst -1.
static func card(g: MauGame, seat: int, key: String) -> int:
	for id in g.hands[seat]:
		if g._key[g.faces[g.side * g.n_cards + int(id)]] == key:
			return int(id)
	return -1


# Aktive Gesichter einer Hand.
static func hand_keys(g: MauGame, seat: int) -> Array:
	var out: Array = []
	for id in g.hands[seat]:
		out.append(g._key[g.faces[g.side * g.n_cards + int(id)]])
	return out


static func top_key(g: MauGame) -> String:
	return g._key[g.faces[g.side * g.n_cards + int(g.discard.back())]]


# Gesicht (aktive Seite) der Karte, die als n-te von oben im Nachziehstapel liegt.
static func draw_key(g: MauGame, n := 0) -> String:
	return g._key[g.faces[g.side * g.n_cards + int(g.draw_pile[g.draw_pile.size() - 1 - n])]]


# Zufällige Regeln für Dauerläufe (alle Optionen, Ziel klein genug für kurze Partien). Hausregeln mit Zusatzkarten: ohne die
# Schalter immer aus (dieselben Zufallszahlen wie vor den Hausregeln, bestehende Läufe bleiben gleich); with_swap: Kartentausch
# an, Richtung zufällig (die Zufallszahl dafür wird zuletzt gezogen); with_gamble / with_discard: Glücksspiel bzw. Farbe mit
# ablegen an (ohne weitere Zufallszahlen).
static func random_config(rng: RandomNumberGenerator, with_swap := false, with_gamble := false, with_discard := false) -> RuleConfig:
	var d := {}
	for k in RuleConfig.CHOICES:
		if k in ["swap_cards", "swap_direction", "gamble_cards", "discard_color"]:
			continue
		var vals: Array = RuleConfig.CHOICES[k]
		d[k] = vals[rng.randi_range(0, vals.size() - 1)]
	for k in RuleConfig.FLAGS:
		d[k] = rng.randf() < 0.5
	d["hand_size"] = rng.randi_range(5, 10)
	d["mau_penalty"] = rng.randi_range(1, 4)
	d["target"] = [150, 300, 500][rng.randi_range(0, 2)]
	if with_swap:
		d["swap_cards"] = "on"
		d["swap_direction"] = RuleConfig.CHOICES["swap_direction"][rng.randi_range(0, 3)]
	if with_gamble:
		d["gamble_cards"] = "on"
	if with_discard:
		d["discard_color"] = "on"
	return RuleConfig.from_dict(d)


# Prüft die Grundannahmen des Zustands; "" = in Ordnung.
static func invariants(g: MauGame) -> String:
	var cc := card_check(g)
	if cc != "":
		return cc
	var n := g.players.size()
	for s in n:
		if int(g.place[s]) != 0 and not (g.hands[s] as Array).is_empty() and g.state in MauGame.PLAY_PHASES:
			return "fertiger Platz %d hat Karten" % s
	if g.state == "gamble":
		var gb := g.gamble
		if gb.is_empty() or int(gb.get("seat", -1)) != g.current:
			return "Glücksspiel ohne Zustand oder für den falschen Platz"
		if not str(gb.get("need", "")) in ["stake", "press"]:
			return "Glücksspiel: unbekannter Schritt " + str(gb.get("need", ""))
		if str(gb.need) == "press" and (gb.stake as Array).is_empty():
			return "Glücksspiel: Drücken ohne Einsatz"
		if int(gb.get("q", 0)) < 1 or int(gb.get("q", 0)) > 10:
			return "Glücksspiel: Quote %d" % int(gb.get("q", 0))
	elif not g.gamble.is_empty():
		return "Glücksspielzustand außerhalb der Phase gamble"
	if g.state == "discard_pick":
		if g.dpick.is_empty() or int(g.dpick.get("seat", -1)) != g.current or g.discard.is_empty() \
				or int(g.discard.back()) != int(g.dpick.get("card", -1)):
			return "Ablege-Auswahl ohne Zustand, für den falschen Platz oder ohne Ablegen-Karte oben"
	elif not g.dpick.is_empty():
		return "Ablege-Auswahl außerhalb der Phase discard_pick"
	if not g.state in MauGame.PLAY_PHASES:
		return "" if g.state in ["round_over", "game_over"] else "unbekannte Phase " + g.state
	var c := g.current_seat()
	if c < 0 or c >= n:
		return "kein gültiger Platz am Zug"
	if int(g.place[c]) != 0 and g.state != "color":
		return "fertiger Platz %d am Zug" % c
	if g._active_count() < 2:
		return "weniger als 2 aktive Spieler, Runde läuft"
	if g.state != "color" and not (CardDB.COLORS[g.side_name()] as Array).has(g.color):
		return "Farbe „%s“ passt nicht zur Seite" % g.color
	if g.state == "challenge" and g.pending.is_empty():
		return "challenge ohne offene Strafe"
	if g.state == "drawn" and not (g.hands[c] as Array).has(g.drawn_id):
		return "gezogene Karte fehlt"
	if g.discard.is_empty():
		return "Ablage leer"
	return ""


# Zahl aller Karten (muss immer g.n_cards sein: 112, mit Zusatzkarten bis 124) und ob jede id genau einmal vorkommt
# (Nachziehstapel, Ablage, Hände und der Einsatz eines laufenden Glücksspiels).
static func card_check(g: MauGame) -> String:
	var n_cards := g.n_cards
	if n_cards != g.config.card_count():
		return "Kartenzahl %d passt nicht zu den Regeln (%d)" % [n_cards, g.config.card_count()]
	if g.faces.size() != n_cards * 2:
		return "%d Gesichter statt %d" % [g.faces.size(), n_cards * 2]
	var seen := PackedByteArray()
	seen.resize(n_cards)
	var total := 0
	var piles: Array = [g.draw_pile, g.discard]
	piles.append_array(g.hands)
	piles.append(g.gamble.get("stake", []))
	for pile in piles:
		for id in pile:
			var i := int(id)
			if i < 0 or i >= n_cards:
				return "ungültige id %d" % i
			if seen[i] == 1:
				return "id %d doppelt" % i
			seen[i] = 1
			total += 1
	if total != n_cards:
		return "%d statt %d Karten" % [total, n_cards]
	return ""


# Gesichter der Partie als Multimenge je Seite gleich dem Deck der Regelvariante (112 bis 124); "" = in Ordnung. Teurer als
# card_check, daher nur zu Rundenbeginn bzw. gezielt aufrufen (Gesichter ändern sich nur beim Mischen der Runde).
static func deck_check(g: MauGame) -> String:
	for s in 2:
		var mine := g.faces.slice(s * g.n_cards, (s + 1) * g.n_cards)
		mine.sort()
		var want := PackedInt32Array(g.config.deck(s))
		want.sort()
		if mine != want:
			return "Gesichter der %s weichen vom Deck ab" % MauGame.SIDES[s]
	return ""


func _build(config: RuleConfig, player_count: int, spec: Dictionary, rng_seed: int) -> MauGame:
	_game = MauGame.create(config, players(player_count), rng_seed)
	var g := _game
	for s in 2:
		_pool[s] = Array(g.config.deck(s))
	g.side = 0 if str(spec.get("side", "hell")) == "hell" else 1
	g.round_no = int(spec.get("round", 1))
	g.dealer = int(spec.get("dealer", 0))
	g.faces.resize(g.n_cards * 2)
	var hs: Array = spec.get("hands", [])
	var top_key := str(spec.get("top", "hell_rot_5" if g.side == 0 else "dunkel_pink_5"))
	# Erst alle ausdrücklich genannten Gesichter reservieren, dann die fehlenden Seiten auffüllen.
	var all: Array = []
	for s in mini(player_count, hs.size()):
		all.append_array(hs[s])
	all.append_array(spec.get("discard", []))
	all.append(top_key)
	all.append_array(spec.get("draw", []))
	all.append_array(spec.get("draw_bottom", []))
	var gspec: Dictionary = spec.get("gamble", {})
	all.append_array(gspec.get("stake", []))
	for k in all:
		_reserve(str(k))
	for s in player_count:
		var hand: Array = []
		if s < hs.size():
			for k in hs[s]:
				hand.append(_take(str(k)))
		g.hands[s] = hand
	var stake: Array = []
	for k in gspec.get("stake", []):
		stake.append(_take(str(k)))
	var under: Array = []
	for k in spec.get("discard", []):
		under.append(_take(str(k)))
	var top := _take(top_key)
	var draw_top: Array = []
	for k in spec.get("draw", []):
		draw_top.append(_take(str(k)))
	var draw_bottom: Array = []
	for k in spec.get("draw_bottom", []):
		draw_bottom.append(_take(str(k)))
	var rest: Array = []
	while _next_id < g.n_cards:
		rest.append(_assign(int((_pool[0] as Array).pop_front()), int((_pool[1] as Array).pop_front())))
	# Nachziehstapel als Array: unten zuerst, oben zuletzt.
	g.draw_pile = draw_bottom.duplicate()
	if str(spec.get("rest", "draw")) == "draw":
		g.draw_pile.append_array(rest)
		g.discard = []
	else:
		g.discard = rest.duplicate()
	draw_top.reverse()
	g.draw_pile.append_array(draw_top)
	g.discard.append_array(under)
	g.discard.append(top)
	g.current = int(spec.get("current", 0))
	g.dir = int(spec.get("dir", 1))
	var top_code := g.faces[g.side * g.n_cards + top]
	g.color = str(spec.get("color", g._color[top_code]))
	g.wished = bool(spec.get("wished", spec.has("color") and g._wild[top_code] == 1))
	g.state = str(spec.get("phase", "turn"))
	g.turn_started = false
	for s in spec.get("mau_said", []):
		g.mau_said[int(s)] = true
	for s in spec.get("finished", []):
		g.finished.append(int(s))
		g.place[int(s)] = g.finished.size()
	var sc: Array = spec.get("scores", [])
	for s in sc.size():
		g.scores[s] = int(sc[s])
	if spec.has("host"):
		g.set_host(int(spec.host))
	if spec.has("gamble"):
		g.state = str(spec.get("phase", "gamble"))
		g.turn_started = true
		g.gamble = {"seat": g.current, "q": clampi(int(gspec.get("q", 5)), 1, 10), "stake": stake,
			"need": str(gspec.get("need", "press" if not stake.is_empty() else "stake")), "last": int(gspec.get("last", -1))}
	return g


# "a" oder "a/b" → [Code hell, Code dunkel], -1 = nicht angegeben.
func _parse(entry: String) -> Array:
	var codes := [-1, -1]
	for p in entry.split("/"):
		var c := CardDB.code_of(p.strip_edges())
		if c < 0:
			push_error("RulesFixture: unbekanntes Gesicht „%s“" % p)
			continue
		codes[CardDB.side_table()[c]] = c
	return codes


func _reserve(entry: String) -> void:
	var codes := _parse(entry)
	for s in 2:
		if codes[s] >= 0 and not _pull(_pool[s], codes[s]):
			push_error("RulesFixture: Gesicht %s gibt es nicht so oft" % CardDB.key_table()[codes[s]])


# Vergibt die nächste id für einen (reservierten) Eintrag; die fehlende Seite kommt aus dem Vorrat.
func _take(entry: String) -> int:
	var codes := _parse(entry)
	for s in 2:
		if codes[s] < 0:
			codes[s] = _free_number(s)
			_pull(_pool[s], codes[s])
	return _assign(codes[0], codes[1])


func _pull(a: Array, c: int) -> bool:
	var i := a.find(c)
	if i < 0:
		return false
	a.remove_at(i)
	return true


func _assign(light: int, dark: int) -> int:
	var id := _next_id
	_next_id += 1
	_game.faces[id] = light
	_game.faces[_game.n_cards + id] = dark
	return id


# Freie Zahlenkarte der Seite s für die nicht angegebene Seite (vermeidet unbeabsichtigte Aktionen nach einem Flip).
func _free_number(s: int) -> int:
	var ktab := CardDB.kind_table()
	for c in _pool[s]:
		if ktab[int(c)] == "zahl":
			return int(c)
	return int(_pool[s][0])
