extends SceneTree
# Modul A: Sichten und Ereignisse. Rückseiten sortiert, keine fremden Vorderseiten, kein Seed (Lecktest über alle view_for und
# events_for in Bot-Partien), JSON-Tauglichkeit, Determinismus, to_dict/from_dict-Rundreise.

const VIEW_KEYS := ["v", "seat", "side", "phase", "turn", "dir", "color", "wish", "colors", "players", "hand", "top", "draw_back",
	"draw_count", "discard_count", "pending", "drawn", "hints", "round", "dealer", "ranking", "result", "rules", "discard_log"]
const PLAYER_KEYS := ["seat", "name", "kind", "count", "backs", "place", "mau", "connected", "score"]
const HINT_KEYS := ["playable", "wild", "can_draw", "can_keep", "can_challenge", "can_accept", "can_mau", "catch", "need_color",
	"can_next_round", "text"]
# Partienzahlen: Standardlauf kurz (gemeinsame Godot-Sperre), volle Zahlen in test_rules_views_long.gd. Einzeln überschreibbar
# per Umgebungsvariable (godot_run.ps1 -EnvPairs 'RULES_LEAK_GAMES=60').
const COUNTS := {"RULES_JSON_GAMES": 10, "RULES_LEAK_GAMES": 16, "RULES_HINT_GAMES": 5, "RULES_TRIP_GAMES": 15}

var failures := 0
var checks := 0
var leak_errors := 0
var leak_views := 0
var leak_events := 0
var leak_swaps := 0              # geprüfte Kartentausch-Ereignisse (nur mit swap_mode)
var leak_stakes := 0             # geprüfte Einsatz-Ereignisse des Glücksspiels (stake, stake_back, stake_discard)
var leak_discards := 0           # geprüfte Ereignisse „Farbe ablegen“
var leak_quota := 0              # Sichten im Glücksspiel, bei denen eine andere Quote nichts ändern darf


# Anzahl für einen Teil des Tests (test_rules_views_long.gd überschreibt counts()).
func counts() -> Dictionary:
	return COUNTS


# Zufallsregeln mit Kartentausch-Karten (116)? Hier nie (Läufe wie vor der Hausregel); test_rules_swap.gd überschreibt das.
func swap_mode() -> bool:
	return false


# Zufallsregeln mit Glücksspiel bzw. „Farbe mit ablegen“? Hier nie; test_rules_gamble.gd bzw. test_rules_discard.gd überschreiben das.
func gamble_mode() -> bool:
	return false


func discard_mode() -> bool:
	return false


func rand_cfg(rng: RandomNumberGenerator) -> RuleConfig:
	return RulesFixture.random_config(rng, swap_mode(), gamble_mode(), discard_mode())


func count(key: String) -> int:
	var env := OS.get_environment(key)
	return int(env) if env.is_valid_int() else int(counts()[key])


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
	print("Laufzeit seit Godot-Start: %.1f s" % (Time.get_ticks_msec() / 1000.0))
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
	for i in count("RULES_JSON_GAMES"):
		var g := MauGame.create(rand_cfg(rng), RulesFixture.players(rng.randi_range(2, 10), "bot"), rng.randi())
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
	var act := g.side * g.n_cards
	var oth := (1 - g.side) * g.n_cards
	if s >= 0:
		for id in g.hands[s]:
			_add(want, g._key[g.faces[act + int(id)]])
			if g.config.peek_own_backs:
				_add(want, g._key[g.faces[oth + int(id)]])
	if not g.discard.is_empty():
		_add(want, g._key[g.faces[act + int(g.discard.back())]])
	# Ablage-Protokoll: alle Ablagekarten (aktive Seite, bei flip_mode = card die Seite, mit der sie liegen), außer verdeckten Glücksspiel-Einsätzen unter der obersten Karte.
	for i in g.discard.size():
		var did := int(g.discard[i])
		if i == g.discard.size() - 1 or not bool((g.dlog.get(did, {}) as Dictionary).get("h", false)):
			_add(want, g._key[g.faces[_shown(g, i) * g.n_cards + did]])
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


# view.discard_log: genau die Ablage von unten nach oben, Felder {f, s, c, h}; verdeckt nur Einsätze unter der obersten Karte.
func _check_discard_log(g: MauGame, dl: Array) -> String:
	if dl.size() != g.discard.size():
		return "discard_log hat %d statt %d Einträge" % [dl.size(), g.discard.size()]
	for i in dl.size():
		var e: Dictionary = dl[i]
		var ks: Array = e.keys()
		ks.sort()
		if ks != ["c", "f", "h", "s"]:
			return "discard_log mit Feldern %s" % str(e.keys())
		var did := int(g.discard[i])
		var hid := bool(e.h)
		if hid != (i < dl.size() - 1 and bool((g.dlog.get(did, {}) as Dictionary).get("h", false))):
			return "discard_log[%d]: verdeckt falsch" % i
		if (str(e.f) == "") != hid or (not hid and str(e.f) != g._key[g.faces[_shown(g, i) * g.n_cards + did]]):
			return "discard_log[%d]: Gesicht falsch" % i
		if int(e.s) < -1 or int(e.s) >= g.players.size():
			return "discard_log[%d]: Leger %d" % [i, int(e.s)]
	return ""


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
	# Glücksspiel-Felder nur mit der Hausregel (ohne sie bleibt die Sicht wie vorher).
	var gamble_on := g.config.gamble_cards == "on"
	var discard_on := g.config.discard_color == "on"
	if v.size() != VIEW_KEYS.size() + (1 if gamble_on else 0) + (1 if discard_on else 0) or v.has("gamble") != gamble_on \
			or v.has("discard_pick") != discard_on:
		return "Platz %d: zusätzliche Felder" % s
	if v.hints.has("can_pick") != discard_on:
		return "Platz %d: Ablege-Hinweise ohne die Hausregel bzw. fehlend" % s
	if discard_on:
		# Öffentlich nur Platz und Ablegefarbe (keine Kandidatenzahl), die wählbaren ids nur für den Leger selbst.
		var dp: Dictionary = v.discard_pick
		if (g.state == "discard_pick") == dp.is_empty():
			return "Platz %d: view.discard_pick passt nicht zum Zustand" % s
		if not dp.is_empty():
			var dk: Array = dp.keys()
			dk.sort()
			if dk != ["color", "seat"] or int(dp.seat) != g.current:
				return "Platz %d: view.discard_pick mit Feldern %s" % [s, str(dp.keys())]
		for id in v.hints.can_pick:
			if s < 0 or s != g.current or g.state != "discard_pick" or not (g.hands[s] as Array).has(int(id)):
				return "can_pick für Platz %d mit fremder id oder außerhalb der Auswahl" % s
	if v.hints.has("can_stake") != gamble_on or v.hints.has("can_press") != gamble_on:
		return "Platz %d: Glücksspiel-Hinweise ohne die Hausregel bzw. fehlend" % s
	if gamble_on:
		var gv: Dictionary = v.gamble
		if g.gamble.is_empty() != gv.is_empty():
			return "Platz %d: view.gamble passt nicht zum Zustand" % s
		if not gv.is_empty():
			var gk: Array = gv.keys()
			gk.sort()
			if gk != ["last", "need", "seat", "stake"]:
				return "Platz %d: view.gamble mit Feldern %s" % [s, str(gv.keys())]
			if int(gv.stake) != (g.gamble.stake as Array).size() or int(gv.seat) != int(g.gamble.seat):
				return "Platz %d: view.gamble falsch" % s
		for id in v.hints.can_stake:
			if s < 0 or not (g.hands[s] as Array).has(int(id)):
				return "can_stake mit fremder id"
		if (not (v.hints.can_stake as Array).is_empty() or bool(v.hints.can_press)) and (s != g.current or g.state != "gamble"):
			return "Glücksspiel-Hinweise für Platz %d außerhalb des eigenen Glücksspiels" % s
	for p in v.players:
		if p.size() != PLAYER_KEYS.size():
			return "Platz %d: Spielerfelder %s" % [s, str(p.keys())]
	if s < 0 and not (v.hand as Array).is_empty():
		return "Zuschauer mit Hand"
	var why := _check_discard_log(g, v.discard_log)
	if why != "":
		return "Platz %d: %s" % [s, why]
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
			"swap_hands":
				var e := _leak_swap(g, src, out, s)
				if e != "":
					return e
			"stake", "stake_back", "stake_discard":
				var e := _leak_stake(g, src, out, s)
				if e != "":
					return e
			"gamble_start", "gamble_roll":
				var allowed := ["e", "seat", "value"]
				for k in src:
					if not allowed.has(str(k)):
						return "Glücksspiel-Ereignis mit Feld %s" % str(k)
			"discard_pick":
				var pk: Array = out.keys()
				pk.sort()
				if pk != ["color", "e", "seat"]:
					return "Ablege-Auswahl-Ereignis mit Feldern %s" % str(out.keys())
			"discard_color":
				leak_discards += 1
				if JSON.stringify(out) != JSON.stringify(src):
					return "„Farbe ablegen“ ist öffentlich und darf nicht gefiltert werden"
				if (out.faces as Array).size() != int(out.count) or (out.cards as Array).size() != int(out.count):
					return "„Farbe ablegen“: count passt nicht"
				for k in out.faces:
					if str(CardDB.parse_key(str(k)).get("color", "")) != str(out.color):
						return "„Farbe ablegen“: Karte %s hat nicht die Farbe %s" % [str(k), str(out.color)]
	var js := JSON.stringify(f)
	for sec in secrets:
		if js.contains(sec):
			return "Geheimnis im Ereignis"
	if js.contains("\"q\""):
		return "Trefferquote im Ereignis"
	return ""


# Glücksspiel-Einsatz: Gesichter, ids und Rückseiten nur für den Spieler selbst (Rückseiten nur bei peek_own_backs); andere sehen
# Platz und Anzahl, beim Zurücknehmen dazu die sortierten Rückseiten (bei backs_visible, wie beim Ziehen).
func _leak_stake(g: MauGame, src: Dictionary, out: Dictionary, s: int) -> String:
	leak_stakes += 1
	var ev := str(src.e)
	var own := int(src.seat) == s
	var private_keys := ["card", "face", "cards", "faces"]
	for k in private_keys:
		if out.has(k) != (own and src.has(k)):
			return "%s: Feld %s für Platz %d falsch verteilt" % [ev, k, s]
	if own:
		if out.get("face", "") != src.get("face", "") or out.get("faces", []) != src.get("faces", []):
			return "%s: eigene Gesichter fehlen" % ev
		var back_key := "back" if ev == "stake" else "backs"
		if src.has(back_key) and out.has(back_key) != g.config.peek_own_backs:
			return "%s: eigene Rückseite trotz peek_own_backs=%s" % [ev, str(g.config.peek_own_backs)]
	else:
		if out.has("back"):
			return "stake: Rückseite der gesetzten Karte für andere"
		if ev == "stake_back":
			if g.config.backs_visible:
				if out.get("backs", []) != CardDB.sort_keys(src.backs):
					return "stake_back: Rückseiten für andere unsortiert"
			elif out.has("backs"):
				return "stake_back: Rückseiten trotz backs_visible=false"
		elif out.has("backs"):
			return "%s: Rückseiten für andere" % ev
	if int(out.get("count", -1)) != int(src.count) or int(out.get("seat", -9)) != int(src.seat):
		return "%s: seat/count fehlen" % ev
	return ""


# Die geheime Trefferquote darf keine Sicht ändern: alle Sichten mit einer anderen Quote müssen gleich bleiben.
func _quota_check(g: MauGame) -> String:
	if g.gamble.is_empty():
		return ""
	leak_quota += 1
	var q := int(g.gamble.q)
	var before: Array = []
	for s in range(-1, g.players.size()):
		before.append(JSON.stringify(g.view_for(s)))
	g.gamble.q = 1 + (q % 10)
	var after: Array = []
	for s in range(-1, g.players.size()):
		after.append(JSON.stringify(g.view_for(s)))
	g.gamble.q = q
	return "" if before == after else "Sicht hängt von der Trefferquote ab"


# Kartentausch: Jeder bekommt nur seine eigene neue Hand (genau wie im ungefilterten Ereignis, ohne Rückseiten bei
# peek_own_backs=false), die anderen nur als Anzahl und – bei backs_visible – als sortierte Rückseiten.
func _leak_swap(g: MauGame, src: Dictionary, out: Dictionary, s: int) -> String:
	leak_swaps += 1
	if out.has("hands"):
		return "Kartentausch: alle Hände für Platz %d sichtbar" % s
	var want: Array = []
	if s >= 0:
		want = (src.hands[s] as Array).duplicate(true)
		if not g.config.peek_own_backs:
			for item in want:
				item.erase("back")
	if out.get("hand", null) != want:
		return "Kartentausch: eigene neue Hand für Platz %d falsch" % s
	for item in want:
		if str(item.face).get_slice("_", 0) != g.side_name():
			return "Kartentausch: Handkarte nicht von der aktiven Seite"
	if out.get("counts", []) != src.counts or int(out.get("seat", -9)) != int(src.seat) or int(out.get("dir", 0)) != int(src.dir):
		return "Kartentausch: seat/dir/counts fehlen"
	if g.config.backs_visible:
		var b: Array = out.get("backs", [])
		if b.size() != g.players.size():
			return "Kartentausch: Rückseiten fehlen"
		for i in b.size():
			if i == s:
				if not (b[i] as Array).is_empty():
					return "Kartentausch: eigene Rückseiten unter backs"
			elif b[i] != CardDB.sort_keys(src.backs[i]) or (b[i] as Array).size() != int(src.counts[i]):
				return "Kartentausch: Rückseiten von Platz %d unsortiert oder unvollständig" % i
			for k in b[i]:
				if str(k).get_slice("_", 0) == g.side_name():
					return "Kartentausch: Rückseite von der aktiven Seite"
	elif out.has("backs"):
		return "Kartentausch: Rückseiten trotz backs_visible=false"
	return ""


func _leak_runs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var first := ""
	for i in count("RULES_LEAK_GAMES"):
		var cfg := rand_cfg(rng)
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
			var qe := _quota_check(g)
			if qe != "" and first == "":
				first = "Partie %d Schritt %d: %s" % [i, steps, qe]
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
	if swap_mode():
		print("Lecktest: davon %d gefilterte Kartentausch-Ereignisse" % leak_swaps)
		check(leak_swaps > 0, "Lecktest prüft Kartentausch-Ereignisse (%d)" % leak_swaps)
	if gamble_mode():
		print("Lecktest: davon %d gefilterte Einsatz-Ereignisse, %d Quotenprüfungen" % [leak_stakes, leak_quota])
		check(leak_stakes > 0 and leak_quota > 0, "Lecktest prüft Glücksspiel-Ereignisse und die Quote (%d/%d)" % [leak_stakes, leak_quota])
	if discard_mode():
		print("Lecktest: davon %d „Farbe ablegen“-Ereignisse" % leak_discards)
		check(leak_discards > 0, "Lecktest prüft „Farbe ablegen“-Ereignisse (%d)" % leak_discards)


# Hinweise sagen genau voraus, was apply() annimmt (der Client braucht keine eigene Regelkenntnis): jede Handkarte, Ziehen,
# Behalten, Anzweifeln, Annehmen, Farbwahl, Mau und Erwischen werden an einer Kopie des Zustands ausprobiert.
func _hint_consistency() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8080
	var first := ""
	var trials := 0
	for i in count("RULES_HINT_GAMES"):
		var cfg := rand_cfg(rng)
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
			# Glücksspiel: jede Handkarte setzen, drücken (Hinweise fehlen ohne die Hausregel = nicht erlaubt)
			for item in v.hand:
				tries.append([seat, {"a": "stake", "card": int(item.id)}, (h.get("can_stake", []) as Array).has(int(item.id)),
					"stake " + str(item.face)])
			tries.append([seat, {"a": "press"}, bool(h.get("can_press", false)), "press"])
			# Farbe mit ablegen: jede Handkarte einzeln wählen, alle Kandidaten bzw. keine (Farbe nur beim Joker, dann Pflicht)
			var in_pick := g.state == "discard_pick"
			var pick_col: Dictionary = {"color": v.colors[0]} if bool(h.get("pick_color", false)) else {}
			for item in v.hand:
				var pa := {"a": "discard_pick", "cards": [int(item.id)]}
				pa.merge(pick_col)
				tries.append([seat, pa, in_pick and (h.get("can_pick", []) as Array).has(int(item.id)), "discard_pick " + str(item.face)])
			var all_pick := {"a": "discard_pick", "cards": (h.get("can_pick", []) as Array).duplicate()}
			all_pick.merge(pick_col)
			tries.append([seat, all_pick, in_pick, "discard_pick alle"])
			if not pick_col.is_empty():
				tries.append([seat, {"a": "discard_pick", "cards": []}, false, "discard_pick ohne Farbe"])
			for o in n:
				var ho: Dictionary = g.view_for(o).hints
				tries.append([o, {"a": "mau"}, bool(ho.can_mau), "mau von %d" % o])
				if o != seat:
					tries.append([o, {"a": "press"}, false, "press von %d" % o])
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
	for id in g1.n_cards:
		if g1.faces[g1.n_cards + id] == pair1[g1.n_cards + id] and g1.faces[id] == pair1[id]:
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
	var trips := count("RULES_TRIP_GAMES")
	for i in trips:
		var cfg := rand_cfg(rng)
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
	check(bad == "", "to_dict/from_dict-Rundreise über JSON (%d Partien): %s" % [trips, bad])
	# Leerer bzw. neuer Zustand
	var fresh := MauGame.create(RuleConfig.preset("familie"), RulesFixture.players(4), 1)
	var back := MauGame.from_dict(JSON.parse_string(JSON.stringify(fresh.to_dict())))
	check(back.phase() == "idle" and back.config.preset_name() == "familie" and back.players.size() == 4, "Rundreise vor dem Start")
	check(back.start_round().size() > 0 and back.phase() == "turn", "geladene Partie startet")


# Seite, mit der Ablagekarte i im Protokoll erscheint: oben die aktive, darunter bei flip_mode = card die gemerkte (dside).
func _shown(g: MauGame, i: int) -> int:
	if i == g.discard.size() - 1 or g.config.flip_mode != "card":
		return g.side
	return int(g.dside.get(int(g.discard[i]), g.side))
