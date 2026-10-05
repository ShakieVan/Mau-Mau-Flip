extends SceneTree
# Modul A: Sichten und Ereignisse. Rückseiten sortiert, keine fremden Vorderseiten, kein Seed (Lecktest über alle view_for und
# events_for in Bot-Partien), JSON-Tauglichkeit, Determinismus, to_dict/from_dict-Rundreise.

const VIEW_KEYS := ["v", "seat", "side", "phase", "turn", "dir", "color", "wish", "colors", "players", "hand", "top", "draw_back",
	"draw_count", "discard_count", "pending", "drawn", "hints", "round", "dealer", "ranking", "result", "rules"]
const PLAYER_KEYS := ["seat", "name", "kind", "count", "backs", "place", "mau", "connected", "score"]
const HINT_KEYS := ["playable", "wild", "can_draw", "can_keep", "can_challenge", "can_accept", "can_mau", "catch", "need_color",
	"can_next_round", "text"]
const LEAK_GAMES := 60

var failures := 0
var checks := 0
var leak_errors := 0
var leak_views := 0
var leak_events := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)


func _initialize() -> void:
	_backs_and_hand()
	_json_views()
	_events_filter()
	_leak_runs()
	_hint_consistency()
	_determinism()
	_round_trip()
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)


func _backs_and_hand() -> void:
	var spec := {"hands": [["hell_rot_1/dunkel_lila_9", "hell_rot_2/dunkel_pink_1", "hell_rot_3/dunkel_farbjagd", "hell_rot_4/dunkel_pink_flip"],
		["hell_blau_1/dunkel_orange_3", "hell_blau_2/dunkel_pink_7"], ["hell_gelb_1"]], "top": "hell_rot_5"}
	var g := RulesFixture.build(RuleConfig.new(), 3, spec)
	var v := g.view_for(1)
	check(v.players[0].backs == ["dunkel_pink_1", "dunkel_pink_flip", "dunkel_lila_9", "dunkel_farbjagd"],
		"Rückseiten sortiert nach Farbe, Art, Wert, nicht in Besitzerreihenfolge (%s)" % str(v.players[0].backs))
	check(v.players[1].backs.is_empty(), "eigene Rückseiten nicht in players")
	check(v.hand.size() == 2 and v.hand[0].face == "hell_blau_1" and v.hand[0].back == "dunkel_orange_3", "eigene Hand mit Rückseite (peek_own_backs)")
	check(v.players[0].count == 4 and v.players[0].name == "Anna" and v.players[0].kind == "human", "Spielerdaten")
	g = RulesFixture.build(RuleConfig.from_dict({"backs_visible": false, "peek_own_backs": false}), 3, spec)
	v = g.view_for(1)
	check(v.players[0].backs.is_empty() and v.players[2].backs.is_empty(), "backs_visible=false: keine Rückseiten")
	check(not v.hand[0].has("back"), "peek_own_backs=false: keine eigene Rückseite")
	var w := g.view_for(-1)
	check(w.hand.is_empty() and w.seat == -1 and w.hints.playable.is_empty() and not w.hints.can_draw, "Zuschauer: keine Hand, keine Handlungen")
	check(RuleConfig.new().backs_visible and RulesFixture.build(RuleConfig.new(), 3, spec).view_for(-1).players[0].backs.size() == 4,
		"Zuschauer sieht Rückseiten aller (Rückseiten sind öffentlich)")
	for k in VIEW_KEYS:
		check(v.has(k), "Sicht hat Feld " + k)
	check(v.size() == VIEW_KEYS.size(), "Sicht hat keine weiteren Felder (%s)" % str(v.keys()))
	for k in HINT_KEYS:
		check(v.hints.has(k), "hints hat Feld " + k)
	check(v.top.face == "hell_rot_5" and v.draw_back != "" and v.draw_back.begins_with("dunkel_"), "Oberkarte und Nachziehrückseite")
	check(v.rules == RuleConfig.from_dict({"backs_visible": false, "peek_own_backs": false}).to_dict(), "Regeln in der Sicht")
	g.set_connected(2, false)
	check(g.view_for(0).players[2].connected == false, "set_connected")


# Nur JSON-Typen, Zahlen als int; stringify → parse liefert dasselbe.
func _json_ok(x: Variant, path: String) -> String:
	match typeof(x):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return ""
		TYPE_FLOAT:
			return path + ": float"
		TYPE_ARRAY:
			var a: Array = x
			for i in a.size():
				var e := _json_ok(a[i], "%s[%d]" % [path, i])
				if e != "":
					return e
			return ""
		TYPE_DICTIONARY:
			for k in x:
				if typeof(k) != TYPE_STRING:
					return path + ": Schlüssel kein String"
				var e := _json_ok(x[k], path + "." + str(k))
				if e != "":
					return e
			return ""
	return "%s: Typ %s" % [path, type_string(typeof(x))]


func _same(a: Variant, b: Variant) -> bool:
	if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT):
		return float(a) == float(b)
	if typeof(a) != typeof(b):
		return false
	if a is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _same(a[i], b[i]):
				return false
		return true
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _same(a[k], b[k]):
				return false
		return true
	return a == b


func _json_views() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var bad := ""
	for i in 30:
		var g := MauGame.create(RulesFixture.random_config(rng), RulesFixture.players(rng.randi_range(2, 10), "bot"), rng.randi())
		g.start_round()
		for step in 400:
			if not g.state in MauGame.PLAY_PHASES:
				break
			for s in range(-1, g.players.size()):
				var v := g.view_for(s)
				var e := _json_ok(v, "view")
				if e != "":
					bad = e
				elif not _same(JSON.parse_string(JSON.stringify(v)), v):
					bad = "JSON-Rundreise der Sicht weicht ab"
			var seat := g.current_seat()
			var r := g.apply(seat, MauBot.choose(g.view_for(seat), rng.randi(), 1))
			var e2 := _json_ok(r, "apply")
			if e2 != "":
				bad = e2
			for s in range(-1, g.players.size()):
				var fe := _json_ok(g.events_for(s, r.events), "events_for")
				if fe != "":
					bad = fe
		var e3 := _json_ok(g.view_for(0), "Endsicht")
		if e3 != "":
			bad = e3
		var td := _json_ok(g.to_dict(), "to_dict")
		if td != "":
			bad = td
		if bad != "":
			break
	check(bad == "", "Sichten, Ereignisse und to_dict JSON-tauglich mit int-Zahlen: " + bad)


func _events_filter() -> void:
	var g := RulesFixture.build(RuleConfig.new(), 3, {"hands": [["hell_blau_1", "hell_blau_2", "hell_blau_3"], ["hell_rot_1"], ["hell_rot_2"]],
		"top": "hell_rot_5", "draw": ["hell_gelb_1/dunkel_pink_4"]})
	var r := g.apply(0, {"a": "draw"})
	var own: Dictionary = g.events_for(0, r.events)[0]
	var other: Dictionary = g.events_for(1, r.events)[0]
	var watch: Dictionary = g.events_for(-1, r.events)[0]
	check(own.e == "draw" and own.faces == ["hell_gelb_1"] and own.cards.size() == 1 and own.backs == ["dunkel_pink_4"], "Ziehender sieht Gesicht, id und Rückseite")
	check(not other.has("faces") and not other.has("cards") and other.count == 1 and other.backs == ["dunkel_pink_4"], "andere sehen Anzahl und Rückseite")
	check(not watch.has("faces") and not watch.has("cards"), "Zuschauer sieht kein Gesicht")
	g = RulesFixture.build(RuleConfig.from_dict({"backs_visible": false, "peek_own_backs": false}), 3,
		{"hands": [["hell_blau_1", "hell_blau_2", "hell_blau_3"], ["hell_rot_1"], ["hell_rot_2"]], "top": "hell_rot_5", "draw": ["hell_gelb_1/dunkel_pink_4"]})
	r = g.apply(0, {"a": "draw"})
	check(not g.events_for(1, r.events)[0].has("backs"), "backs_visible=false: keine Rückseiten im Ereignis")
	check(not g.events_for(0, r.events)[0].has("backs") and g.events_for(0, r.events)[0].has("faces"), "peek_own_backs=false: eigene ohne Rückseite")
	# Rückseiten mehrerer gezogener Karten für andere sortiert
	g = RulesFixture.build(RuleConfig.from_dict({"draw_rule": "until_playable"}), 3, {"hands": [["hell_blau_1", "hell_blau_2"], ["hell_rot_1"], ["hell_rot_2"]],
		"top": "hell_rot_5", "draw": ["hell_gelb_1/dunkel_pink_9", "hell_gelb_2/dunkel_pink_1", "hell_rot_7/dunkel_lila_1"]})
	r = g.apply(0, {"a": "draw"})
	var de: Dictionary = {}
	for e in g.events_for(2, r.events):
		if e.e == "draw":
			de = e
	check(de.get("backs", []) == ["dunkel_pink_1", "dunkel_pink_9", "dunkel_lila_1"], "Rückseiten im Ereignis sortiert (%s)" % str(de.get("backs", [])))
	# Ereignisliste wird nicht verändert
	var before := JSON.stringify(r.events)
	g.events_for(1, r.events)
	check(JSON.stringify(r.events) == before, "events_for verändert die Eingabe nicht")


# Lecktest: Jede Sicht enthält genau die erlaubten Gesichter (als Multimenge) und nie den Seed oder den Zufallszustand.
func _expected_keys(g: MauGame, s: int) -> Dictionary:
	var want := {}
	var act := g.side * MauGame.N_CARDS
	var oth := (1 - g.side) * MauGame.N_CARDS
	if s >= 0:
		for id in g.hands[s]:
			_add(want, g._key[g.faces[act + int(id)]])
			if g.config.peek_own_backs:
				_add(want, g._key[g.faces[oth + int(id)]])
	if not g.discard.is_empty():
		_add(want, g._key[g.faces[act + int(g.discard.back())]])
	if not g.draw_pile.is_empty():
		_add(want, g._key[g.faces[oth + int(g.draw_pile.back())]])
	if g.config.backs_visible:
		for i in g.players.size():
			if i != s:
				for id in g.hands[i]:
					_add(want, g._key[g.faces[oth + int(id)]])
	if g.state == "round_over" or g.state == "game_over":
		for h in g.result.get("hands", []):
			for k in h:
				_add(want, str(k))
	return want


func _add(d: Dictionary, k: String) -> void:
	d[k] = int(d.get(k, 0)) + 1


func _collect_keys(x: Variant, into: Dictionary, skip_rules := true) -> void:
	if x is String:
		if CardDB.is_key(x):
			_add(into, x)
	elif x is Array:
		for e in x:
			_collect_keys(e, into, skip_rules)
	elif x is Dictionary:
		for k in x:
			if skip_rules and str(k) == "rules":
				continue
			_collect_keys(x[k], into, skip_rules)


func _leak_view(g: MauGame, s: int, secrets: Array) -> String:
	var v := g.view_for(s)
	leak_views += 1
	var got := {}
	_collect_keys(v, got)
	var want := _expected_keys(g, s)
	if got != want:
		return "Platz %d: Gesichter in der Sicht weichen ab (zu viel: %s)" % [s, str(_diff(got, want))]
	if v.size() != VIEW_KEYS.size():
		return "Platz %d: zusätzliche Felder" % s
	for p in v.players:
		if p.size() != PLAYER_KEYS.size():
			return "Platz %d: Spielerfelder %s" % [s, str(p.keys())]
	if s < 0 and not (v.hand as Array).is_empty():
		return "Zuschauer mit Hand"
	if int(v.drawn) >= 0 and (s != g.current or g.state != "drawn"):
		return "gezogene id für Platz %d sichtbar" % s
	for id in v.hints.playable:
		if not (g.hands[s] as Array).has(int(id)):
			return "playable mit fremder id"
	if v.pending.has("legal") or v.pending.has("snap"):
		return "Prüfergebnis des Bluffs sichtbar"
	var js := JSON.stringify(v)
	for sec in secrets:
		if js.contains(sec):
			return "Platz %d: Geheimnis %s in der Sicht" % [s, sec]
	return ""


func _diff(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	for k in a:
		if int(a[k]) != int(b.get(k, 0)):
			out[k] = int(a[k]) - int(b.get(k, 0))
	for k in b:
		if not a.has(k):
			out[k] = -int(b[k])
	return out


func _leak_events(g: MauGame, events: Array, s: int, secrets: Array) -> String:
	var f := g.events_for(s, events)
	leak_events += 1
	if f.size() != events.size():
		return "Ereigniszahl"
	for i in f.size():
		var src: Dictionary = events[i]
		var out: Dictionary = f[i]
		match str(src.e):
			"draw":
				if int(src.seat) != s:
					if out.has("faces") or out.has("cards"):
						return "fremde gezogene Karte für Platz %d sichtbar" % s
					if g.config.backs_visible:
						if out.get("backs", []) != CardDB.sort_keys(src.backs):
							return "Rückseiten im Ziehereignis unsortiert"
						for k in out.backs:
							if str(k).get_slice("_", 0) == str(src.faces[0]).get_slice("_", 0):
								return "Rückseite von der aktiven Seite"
					elif out.has("backs"):
						return "Rückseiten trotz backs_visible=false"
				elif out.get("faces", []) != src.faces:
					return "eigene gezogene Karten fehlen"
			"challenge":
				if out.has("hand") != (int(src.seat) == s):
					return "Hand beim Anzweifeln falsch verteilt (Platz %d)" % s
	var js := JSON.stringify(f)
	for sec in secrets:
		if js.contains(sec):
			return "Geheimnis im Ereignis"
	return ""


func _leak_runs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var first := ""
	for i in LEAK_GAMES:
		var cfg := RulesFixture.random_config(rng)
		if i % 3 == 0:
			cfg.backs_visible = true
			cfg.mau_call = "catch"
		var n := rng.randi_range(2, 10)
		var game_seed := 1_000_000_007 + rng.randi() * 977
		var g := MauGame.create(cfg, RulesFixture.players(n, "bot"), game_seed)
		var secrets := [str(game_seed)]
		var start := g.start_round()
		for s in range(-1, n):
			var e := _leak_events(g, start, s, secrets)
			if e != "" and first == "":
				first = "Start: " + e
		var rounds := 0
		var steps := 0
		while steps < 3000 and rounds < 2:
			steps += 1
			if not g.state in MauGame.PLAY_PHASES:
				rounds += 1
				if g.state == "game_over":
					break
				var nr := g.apply(0, {"a": "next_round"})
				for s in range(-1, n):
					var e := _leak_events(g, nr.events, s, secrets)
					if e != "" and first == "":
						first = "next_round: " + e
				continue
			secrets = [str(game_seed), str(g._rng.state)]
			for s in range(-1, n):
				var e := _leak_view(g, s, secrets)
				if e != "" and first == "":
					first = "Partie %d Schritt %d: %s" % [i, steps, e]
			# Erwischen gelegentlich durch einen anderen Platz
			if g.mau_open >= 0 and rng.randf() < 0.5:
				var o := rng.randi_range(0, n - 1)
				var ca := MauBot.choose(g.view_for(o), rng.randi(), 1)
				if ca.get("a", "") == "catch":
					var cr := g.apply(o, ca)
					for s in range(-1, n):
						var e := _leak_events(g, cr.events, s, secrets)
						if e != "" and first == "":
							first = "catch: " + e
			var seat := g.current_seat()
			if seat < 0:
				continue
			var v := g.view_for(seat)
			if bool(v.hints.can_mau) and rng.randf() < 0.3:
				v.hints.can_mau = false
			var r := g.apply(seat, MauBot.choose(v, rng.randi(), rng.randi_range(0, 2)))
			if not bool(r.ok) and first == "":
				first = "Aktion abgelehnt: " + str(r.reason)
			for s in range(-1, n):
				var e := _leak_events(g, r.events, s, secrets)
				if e != "" and first == "":
					first = "Partie %d Schritt %d Ereignis: %s" % [i, steps, e]
		# Endsicht (mit aufgedeckten Resthänden)
		for s in range(-1, n):
			var e := _leak_view(g, s, [str(game_seed)])
			if e != "" and first == "":
				first = "Endsicht: " + e
	check(first == "", "Lecktest über %d Sichten und %d Ereignislisten: %s" % [leak_views, leak_events, first])
	print("Lecktest: %d Sichten und %d gefilterte Ereignislisten geprüft" % [leak_views, leak_events])


# Hinweise sagen genau voraus, was apply() annimmt (der Client braucht keine eigene Regelkenntnis): jede Handkarte, Ziehen,
# Behalten, Anzweifeln, Annehmen, Farbwahl, Mau und Erwischen werden an einer Kopie des Zustands ausprobiert.
func _hint_consistency() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8080
	var first := ""
	var trials := 0
	for i in 16:
		var cfg := RulesFixture.random_config(rng)
		if i % 2 == 0:
			cfg.mau_call = "catch"
		var n := rng.randi_range(2, 6)
		var g := MauGame.create(cfg, RulesFixture.players(n, "bot"), 777_000_000 + i)
		g.start_round()
		for step in 250:
			if not g.state in MauGame.PLAY_PHASES or first != "":
				break
			var snap := g.to_dict()
			var seat := g.current_seat()
			var v := g.view_for(seat)
			var h: Dictionary = v.hints
			var tries: Array = []
			for item in v.hand:
				var a := {"a": "play", "card": int(item.id)}
				if CardDB.is_wild(CardDB.parse_key(str(item.face))):
					a["color"] = v.colors[0]
				tries.append([seat, a, (h.playable as Array).has(int(item.id)), "play " + str(item.face)])
			tries.append([seat, {"a": "draw"}, bool(h.can_draw), "draw"])
			tries.append([seat, {"a": "keep"}, bool(h.can_keep), "keep"])
			tries.append([seat, {"a": "challenge"}, bool(h.can_challenge), "challenge"])
			tries.append([seat, {"a": "accept"}, bool(h.can_accept), "accept"])
			tries.append([seat, {"a": "color", "color": v.colors[0]}, bool(h.need_color), "color"])
			for o in n:
				var ho: Dictionary = g.view_for(o).hints
				tries.append([o, {"a": "mau"}, bool(ho.can_mau), "mau von %d" % o])
				for t in n:
					if t != o:
						tries.append([o, {"a": "catch", "target": t}, (ho.catch as Array).has(t), "catch %d→%d" % [o, t]])
			for t in tries:
				var c := MauGame.from_dict(snap)
				var ok := bool(c.apply(int(t[0]), t[1]).ok)
				trials += 1
				if ok != bool(t[2]) and first == "":
					first = "Partie %d Schritt %d Phase %s: %s – Hinweis %s, apply %s" % [i, step, g.state, t[3], t[2], ok]
			if g.mau_open >= 0 and rng.randf() < 0.3:
				var o := rng.randi_range(0, n - 1)
				var ca := MauBot.choose(g.view_for(o), rng.randi(), 1)
				if ca.get("a", "") == "catch":
					g.apply(o, ca)
					continue
			var bv := g.view_for(seat)
			if bool(bv.hints.can_mau) and rng.randf() < 0.4:
				bv.hints.can_mau = false
			g.apply(seat, MauBot.choose(bv, rng.randi(), rng.randi_range(0, 2)))
	check(first == "", "Hinweise stimmen mit apply() überein (%d Versuche): %s" % [trials, first])
	print("Hinweisprüfung: %d Aktionen an Zustandskopien ausprobiert" % trials)


# Partie mit festen Bot-Entscheidungen nach max_steps Aktionen.
func _scripted(game_seed: int, bot_seed: int, cfg: RuleConfig, n: int, max_steps: int) -> MauGame:
	var g := MauGame.create(cfg, RulesFixture.players(n, "bot"), game_seed)
	g.start_round()
	var rng := RandomNumberGenerator.new()
	rng.seed = bot_seed
	_advance(g, rng, max_steps)
	return g


func _advance(g: MauGame, rng: RandomNumberGenerator, max_steps: int) -> void:
	for step in max_steps:
		if not g.state in MauGame.PLAY_PHASES:
			if g.state == "round_over":
				g.apply(0, {"a": "next_round"})
				continue
			return
		var seat := g.current_seat()
		g.apply(seat, MauBot.choose(g.view_for(seat), rng.randi(), 1))


func _determinism() -> void:
	var cfg := RuleConfig.from_dict({"stacking": "same", "scoring": "points500", "draw_rule": "until_playable"})
	var a := _scripted(123456789, 5, cfg, 4, 300)
	var b := _scripted(123456789, 5, cfg, 4, 300)
	check(JSON.stringify(a.to_dict()) == JSON.stringify(b.to_dict()), "gleicher Seed + gleiche Aktionen = gleicher Zustand")
	check(a.round_no >= 1 and a.to_dict().hash() == b.to_dict().hash(), "Zustand nach 300 Aktionen gleich (Runde %d)" % a.round_no)
	var c := _scripted(123456790, 5, cfg, 4, 0)
	var d := _scripted(123456789, 5, cfg, 4, 0)
	check(JSON.stringify(c.to_dict()["hands"]) != JSON.stringify(d.to_dict()["hands"]), "anderer Seed, andere Verteilung")
	# Paarung hell↔dunkel je Runde neu, aus dem Seed reproduzierbar
	var g1 := MauGame.create(RuleConfig.new(), RulesFixture.players(3), 99)
	var g2 := MauGame.create(RuleConfig.new(), RulesFixture.players(3), 99)
	g1.start_round()
	g2.start_round()
	var pair1 := g1.faces.duplicate()
	check(g1.faces == g2.faces, "Paarung aus dem Seed reproduzierbar")
	g1.state = "round_over"
	g1.apply(0, {"a": "next_round"})
	check(g1.faces != pair1, "Paarung und ids in Runde 2 neu gemischt")
	# Paarung ist zufällig: nicht immer gleiche Zuordnung von Gesicht zu Gesicht
	var same_pairs := 0
	for id in 112:
		if g1.faces[112 + id] == pair1[112 + id] and g1.faces[id] == pair1[id]:
			same_pairs += 1
	check(same_pairs < 20, "ids je Runde neu verteilt (%d gleich)" % same_pairs)
	# Keine globale Zufallsquelle: globaler Seed ändert nichts
	seed(1)
	var e := _scripted(2024, 7, cfg, 5, 150)
	seed(999)
	randi()
	var f := _scripted(2024, 7, cfg, 5, 150)
	check(JSON.stringify(e.to_dict()) == JSON.stringify(f.to_dict()), "unabhängig von der globalen Zufallsquelle")


func _round_trip() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var bad := ""
	for i in 40:
		var cfg := RulesFixture.random_config(rng)
		var n := rng.randi_range(2, 10)
		var g := MauGame.create(cfg, RulesFixture.players(n, "bot"), 5_000_000_000 + i)
		g.start_round()
		var brng := RandomNumberGenerator.new()
		brng.seed = 11 + i
		_advance(g, brng, rng.randi_range(0, 120))
		var d := g.to_dict()
		var text := JSON.stringify(d)
		var h := MauGame.from_dict(JSON.parse_string(text))
		if JSON.stringify(h.to_dict()) != text:
			bad = "Partie %d: to_dict nach from_dict weicht ab" % i
			break
		for s in range(-1, n):
			if JSON.stringify(h.view_for(s)) != JSON.stringify(g.view_for(s)):
				bad = "Partie %d: Sicht nach Laden weicht ab" % i
		# Beide Fassungen gleich weiterspielen (auch der Zufallszustand muss stimmen)
		var r1 := RandomNumberGenerator.new()
		r1.seed = 900 + i
		var r2 := RandomNumberGenerator.new()
		r2.seed = 900 + i
		_advance(g, r1, 200)
		_advance(h, r2, 200)
		if JSON.stringify(g.to_dict()) != JSON.stringify(h.to_dict()):
			bad = "Partie %d: nach dem Laden anders weitergespielt" % i
			break
	check(bad == "", "to_dict/from_dict-Rundreise über JSON (40 Partien): " + bad)
	# Leerer bzw. neuer Zustand
	var fresh := MauGame.create(RuleConfig.preset("familie"), RulesFixture.players(4), 1)
	var back := MauGame.from_dict(JSON.parse_string(JSON.stringify(fresh.to_dict())))
	check(back.phase() == "idle" and back.config.preset_name() == "familie" and back.players.size() == 4, "Rundreise vor dem Start")
	check(back.start_round().size() > 0 and back.phase() == "turn", "geladene Partie startet")
