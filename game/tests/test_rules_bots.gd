extends SceneTree
# Modul A: Bot-Partien mit zufälligen Regeln und 2–10 Spielern ohne Fehler (abgelehnte Aktion, Kartenzahl ≠ 112, Endlosschleife).
# Standardlauf 300 Partien und Stärketest mit 600 Partien (kurz, weil alle Agenten die Godot-Sperre teilen); die lange Fassung
# (10 000 Partien, Stärketest 3 000) ist test_rules_bots_long.gd. Anzahl auch per Umgebungsvariable RULES_GAMES bzw.
# RULES_STRENGTH (godot_run.ps1 -EnvPairs "RULES_GAMES=200").
# Dazu Einzelprüfungen der Bot-Entscheidungen in gezielten Situationen und die Zählung „blinder“ Mau-Rufe (muss 0 sein).

const Teil := preload("res://tests/teil.gd")
const STEP_LIMIT := 5000         # Aktionen je Runde; mehr = Endlosschleife
const ROUND_LIMIT := 40           # Runden je Partie (Punktewertung)

var failures := 0
var checks := 0
var stats := {}


func game_count() -> int:
	return 300


func strength_count() -> int:
	return 600


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)


func _initialize() -> void:
	var games := game_count()
	if OS.get_environment("RULES_GAMES").is_valid_int():
		games = int(OS.get_environment("RULES_GAMES"))
	# Aufteilung (tests/teil.gd, TEIL=k/n): Einzelprüfungen samt Stärketest in Teil 1, Partie i im Teil i % n + 1.
	if Teil.first():
		_bot_decisions()
	var t0 := Time.get_ticks_msec()
	var errors := 0
	var played := 0
	for i in games:
		if not Teil.mine(i):
			continue
		played += 1
		var err := _run_game(i)
		if err != "":
			errors += 1
			if errors <= 10:
				print("FAIL: Partie %d: %s" % [i, err])
	games = played
	checks += 1
	if errors > 0:
		failures += 1
		print("FAIL: %d von %d Partien fehlerhaft" % [errors, games])
	check(int(stats.get("mau_rufe", 0)) > 0 and int(stats.get("mau_blind", 0)) == 0,
		"Bots rufen „Mau!“ nur, wenn sie danach legen (%d Rufe, %d blind)" % [int(stats.get("mau_rufe", 0)), int(stats.get("mau_blind", 0))])
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("Bot-Partien%s: %d in %.1f s – %s" % [Teil.label(), games, secs, str(stats)])
	print("Laufzeit seit Godot-Start: %.1f s" % (Time.get_ticks_msec() / 1000.0))
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)


func _count(key: String, n := 1) -> void:
	stats[key] = int(stats.get(key, 0)) + n


func _run_game(i: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9_000_017 * i + 3
	var cfg := RulesFixture.random_config(rng)
	var n := rng.randi_range(2, 10)
	var levels: Array = []
	for s in n:
		levels.append(rng.randi_range(0, 2))
	var g := MauGame.create(cfg, RulesFixture.players(n, "bot"), rng.randi())
	g.start_round()
	var extra_rounds := 1 if rng.randf() < 0.2 else 0
	var forget := rng.randf() * 0.5
	for r in ROUND_LIMIT:
		var err := _play_round(g, rng, levels, forget)
		if err != "":
			return "Runde %d (%d Spieler, %s): %s" % [g.round_no, n, JSON.stringify(cfg.to_dict()), err]
		_count("runden")
		if g.result.get("reason", "") == "blockiert":
			_count("blockiert")
		if g.is_over():
			_count("partien_500")
			return ""
		if cfg.effective_scoring() != "points500":
			if extra_rounds <= 0:
				return ""
			extra_rounds -= 1
		var res := g.apply(0, {"a": "next_round"})
		if not bool(res.ok):
			return "next_round abgelehnt: " + str(res.reason)
	return "" if cfg.effective_scoring() == "points500" else "zu viele Runden"


func _play_round(g: MauGame, rng: RandomNumberGenerator, levels: Array, forget: float) -> String:
	var n := g.players.size()
	var steps := 0
	var mau_seat := -1                  # Platz, der gerade mit 2 Karten „Mau!“ gerufen hat: Seine nächste Aktion muss play sein.
	while g.state in MauGame.PLAY_PHASES:
		steps += 1
		if steps > STEP_LIMIT:
			return "Zugobergrenze %d erreicht" % STEP_LIMIT
		# Erwischen: ein zufälliger Platz schaut, ob er jemanden erwischen kann.
		if g.mau_open >= 0 and rng.randf() < 0.6:
			var o := rng.randi_range(0, n - 1)
			var ca := MauBot.choose(g.view_for(o), rng.randi(), int(levels[o]))
			if str(ca.get("a", "")) == "catch":
				var cr := g.apply(o, ca)
				if not bool(cr.ok):
					return "catch abgelehnt: " + str(cr.reason)
				_count("erwischt")
		var seat := g.current_seat()
		var view := g.view_for(seat)
		if bool(view.hints.can_mau) and rng.randf() < forget:
			view.hints.can_mau = false          # „vergisst“ Mau
		var act := MauBot.choose(view, rng.randi(), int(levels[seat]))
		if act.is_empty():
			return "Bot ohne Aktion in Phase %s (%s)" % [g.state, str(view.hints)]
		var kind := str(act.get("a", ""))
		# Erwischen zwischendurch zählt nicht (Stufe 0 erwischt zufällig je Anfrage); danach muss trotzdem play kommen.
		if mau_seat == seat and kind == "catch":
			_count("mau_dann_erwischen")
		elif kind != "catch":
			if mau_seat == seat and kind != "play":
				_count("mau_blind")
				if int(stats.get("mau_blind", 0)) <= 3:
					print("blinder Ruf: Platz %d, danach %s in Phase %s, Hinweise %s" % [seat, JSON.stringify(act), g.state, str(view.hints)])
			mau_seat = -1
		if kind == "mau" and (g.hands[seat] as Array).size() == 2:
			mau_seat = seat
			_count("mau_rufe")
		var res := g.apply(seat, act)
		if not bool(res.ok):
			return "Aktion %s abgelehnt: %s" % [JSON.stringify(act), res.reason]
		for e in res.events:
			match str(e.e):
				"flip", "shuffle", "challenge", "pass", "penalty", "skip_all":
					_count(str(e.e))
		_count("aktionen")
		var inv := RulesFixture.invariants(g)
		if inv != "":
			return "nach %s: %s" % [JSON.stringify(act), inv]
	return ""


# Taktik schlägt Zufall: Stufe 2 gegen zwei Bots der Stufe 0, Platz reihum (feste Seeds, also nicht zufällig rot).
# Zufall läge bei 33 %; das Spiel ist glückslastig, gemessen sind etwa 42 % (3 000 Partien).
func _strength() -> void:
	var t0 := Time.get_ticks_msec()
	var wins := 0
	var games := strength_count()
	if OS.get_environment("RULES_STRENGTH").is_valid_int():
		games = int(OS.get_environment("RULES_STRENGTH"))
	for i in games:
		var strong := i % 3
		var levels := [0, 0, 0]
		levels[strong] = 2
		var g := MauGame.create(RuleConfig.new(), RulesFixture.players(3, "bot"), 777 + i)
		g.start_round()
		var rng := RandomNumberGenerator.new()
		rng.seed = 31 + i
		var err := _play_round(g, rng, levels, 0.0)
		if err != "":
			check(false, "Stärketest: " + err)
			return
		if int(g.result.ranking[0]) == strong:
			wins += 1
	stats["staerke_siege"] = wins
	print("Stärketest: %d von %d Partien in %.1f s" % [wins, games, (Time.get_ticks_msec() - t0) / 1000.0])
	check(wins > games * 0.37, "Taktik-Bot (Stufe 2) gewinnt deutlich öfter als ein Drittel (%d von %d; gemessen über 3 000: etwa 42 %%)" % [wins, games])


# --- Bot-Entscheidungen in gezielten Situationen ---

# „Mau!“ nur, wenn der Bot im selben Zug auf 1 Karte kommt (Befund der Prüfung: vorher 44 % blinde Rufe auf Stufe 2).
func _mau_decisions() -> void:
	for level in 3:
		# 2 Karten, nichts passt: ziehen, kein Ruf
		var g := RulesFixture.build(RuleConfig.new(), 3, {"hands": [["hell_blau_1", "hell_blau_2"], ["hell_rot_3"], ["hell_rot_6"]], "top": "hell_gelb_5"})
		var a := _decide(g, 0, level)
		check(a.get("a", "") == "draw", "Stufe %d: nichts passt → ziehen, kein Mau (%s)" % [level, str(a)])
		# Opfer einer +2 mit 2 Karten ohne Stapeln: anzweifeln oder annehmen, kein Ruf
		g = RulesFixture.build(RuleConfig.from_dict({"wild_restriction": "bluff"}), 3, {"hands": [["hell_wuenscher_plus2", "hell_gelb_1", "hell_gelb_2"], ["hell_rot_3", "hell_rot_4"], ["hell_rot_6"]],
			"top": "hell_rot_5"})
		g.apply(0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_wuenscher_plus2"), "color": "blau"})
		a = _decide(g, 1, level)
		check(a.get("a", "") in ["accept", "challenge"], "Stufe %d: Opfer einer +2 ohne Stapeln ruft nicht (%s)" % [level, str(a)])
		# Opfer kann regelgerecht stapeln: erst „Mau!“, dann stapeln
		g = RulesFixture.build(RuleConfig.from_dict({"stacking": "same"}), 3, {"hands": [["hell_wuenscher_plus2", "hell_gelb_1", "hell_gelb_2"],
			["hell_wuenscher_plus2", "hell_gelb_4"], ["hell_rot_6"]], "top": "hell_rot_5"})
		g.apply(0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_wuenscher_plus2"), "color": "blau"})
		a = _decide(g, 1, level)
		check(a.get("a", "") == "mau", "Stufe %d: Opfer stapelt mit 2 Karten → erst Mau (%s)" % [level, str(a)])
		g.apply(1, a)
		a = _decide(g, 1, level)
		check(a.get("a", "") == "play" and bool(g.apply(1, a).ok), "Stufe %d: nach Mau wird gestapelt (%s)" % [level, str(a)])
		# Stapeln nur „unehrlich“ möglich (free): Der Bot legt selten; ruft er „Mau!“, bleibt er danach beim Legen
		g = RulesFixture.build(RuleConfig.from_dict({"stacking": "same", "wild_restriction": "free"}), 3, {"hands": [["hell_wuenscher_plus2", "hell_gelb_1", "hell_gelb_2"],
			["hell_wuenscher_plus2", "hell_blau_4"], ["hell_rot_6"]], "top": "hell_rot_5"})
		g.apply(0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_wuenscher_plus2"), "color": "blau"})
		var calls := 0
		for k in 20:
			var c := MauGame.from_dict(g.to_dict())
			var b := _decide(c, 1, level, 100 + k)
			if b.get("a", "") == "mau":
				calls += 1
				c.apply(1, b)
				for j in 5:
					var p := _decide(c, 1, level, 500 + j)
					check(p.get("a", "") == "play", "Stufe %d: nach Mau wird gelegt, nicht gezogen (%s)" % [level, str(p)])
			else:
				check(b.get("a", "") == "draw", "Stufe %d: ohne Ruf wird gezogen (%s)" % [level, str(b)])
		check(calls > 0 and calls < 20, "Stufe %d: unehrliches Stapeln nur manchmal (%d von 20)" % [level, calls])
		# Zu zweit nach Aussetzen ohne Ruf auf 1 Karte: Im eigenen Zusatzzug wird nachträglich gerufen
		g = RulesFixture.build(RuleConfig.new(), 2, {"hands": [["hell_rot_aussetzen", "hell_gelb_1"], ["hell_blau_1", "hell_blau_2"]], "top": "hell_rot_5"})
		g.apply(0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_rot_aussetzen")})
		check(g.current_seat() == 0 and _decide(g, 0, level).get("a", "") == "mau", "Stufe %d: nachträglicher Ruf im Zusatzzug" % level)

func _decide(g: MauGame, seat: int, level := 1, rng_seed := 1) -> Dictionary:
	return MauBot.choose(g.view_for(seat), rng_seed, level)


func _bot_decisions() -> void:
	# Passende Karte, Wunschfarbe nach Handmehrheit
	var g := RulesFixture.build(RuleConfig.new(), 3, {"hands": [["hell_wuenscher", "hell_gelb_1", "hell_gelb_2", "hell_gelb_3", "hell_blau_9"], ["hell_rot_1"], ["hell_rot_2"]],
		"top": "hell_rot_5"})
	var a := _decide(g, 0, 2)
	check(a.get("a", "") == "play" and int(a.card) == RulesFixture.card(g, 0, "hell_wuenscher") and a.get("color", "") == "gelb",
		"einziger Zug Joker, Wunsch Gelb nach Handmehrheit (%s)" % str(a))
	# Zahl statt Joker, wenn möglich
	g = RulesFixture.build(RuleConfig.new(), 3, {"hands": [["hell_wuenscher", "hell_rot_1", "hell_gelb_2", "hell_gelb_3"], ["hell_rot_1", "hell_rot_2", "hell_rot_3"], ["hell_rot_2"]],
		"top": "hell_rot_5"})
	a = _decide(g, 0, 2)
	check(int(a.get("card", -1)) == RulesFixture.card(g, 0, "hell_rot_1"), "Joker aufsparen, Zahl legen (%s)" % str(a))
	# Angriff auf Spieler mit wenigen Karten
	g = RulesFixture.build(RuleConfig.new(), 3, {"hands": [["hell_rot_plus1", "hell_rot_1", "hell_gelb_2"], ["hell_blau_1"], ["hell_rot_2", "hell_rot_3"]],
		"top": "hell_rot_5"})
	a = _decide(g, 0, 2)
	check(int(a.get("card", -1)) == RulesFixture.card(g, 0, "hell_rot_plus1"), "+1 gegen Spieler mit 1 Karte (%s)" % str(a))
	# Mau immer rufen
	g = RulesFixture.build(RuleConfig.new(), 3, {"hands": [["hell_rot_1", "hell_rot_2"], ["hell_blau_1"], ["hell_rot_2"]], "top": "hell_rot_5"})
	check(_decide(g, 0).get("a", "") == "mau", "Bot ruft Mau")
	# Erwischen, auch außerhalb des eigenen Zugs
	g.apply(0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_rot_1")})
	a = _decide(g, 2)
	check(a.get("a", "") == "catch" and int(a.get("target", -1)) == 0, "Bot erwischt (%s)" % str(a))
	check(_decide(g, 0).is_empty(), "nichts zu tun außerhalb des Zugs")
	# Nichts passt: ziehen; gezogene passende Karte legen
	g = RulesFixture.build(RuleConfig.new(), 2, {"hands": [["hell_blau_1", "hell_blau_2", "hell_blau_3"], ["hell_gelb_1"]], "top": "hell_rot_5", "draw": ["hell_rot_7"]})
	check(_decide(g, 0).get("a", "") == "draw", "nichts passt: ziehen")
	g.apply(0, {"a": "draw"})
	a = _decide(g, 0)
	check(a.get("a", "") == "play" and int(a.card) == RulesFixture.card(g, 0, "hell_rot_7"), "gezogene Karte legen (%s)" % str(a))
	# Annehmen, wenn der Leger kaum Karten hat (wohl ehrlich), anzweifeln bei Verdacht (viele Karten)
	for k in [0, 8]:
		var hand: Array = ["hell_wuenscher_plus2", "hell_gruen_9"]
		for j in k:
			hand.append("hell_gelb_%d" % (j + 1))
		g = RulesFixture.build(RuleConfig.from_dict({"wild_restriction": "bluff"}), 3, {"hands": [hand, ["hell_blau_1", "hell_blau_2", "hell_blau_3"], ["hell_rot_2"]], "top": "hell_rot_5"})
		if hand.size() == 2:
			g.apply(0, {"a": "mau"})
		g.apply(0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_wuenscher_plus2"), "color": "blau"})
		a = _decide(g, 1, 2)
		check(a.get("a", "") == ("accept" if k == 0 else "challenge"), "Leger mit %d Karten: %s (%s)" % [k + 1, "annehmen" if k == 0 else "anzweifeln", str(a)])
	# Stapeln statt ziehen
	g = RulesFixture.build(RuleConfig.from_dict({"stacking": "same"}), 3, {"hands": [["hell_rot_plus1", "hell_rot_1", "hell_rot_3"], ["hell_blau_plus1", "hell_blau_1", "hell_blau_4"], ["hell_rot_2"]],
		"top": "hell_rot_5"})
	g.apply(0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_rot_plus1")})
	a = _decide(g, 1)
	check(int(a.get("card", -1)) == RulesFixture.card(g, 1, "hell_blau_plus1"), "Bot stapelt (%s)" % str(a))
	# Farbwahl nach Flip mit Joker oben
	g = RulesFixture.build(RuleConfig.new(), 3, {"hands": [["hell_rot_flip", "hell_rot_1/dunkel_lila_1", "hell_rot_2/dunkel_lila_2"], ["hell_gelb_1"], ["hell_gelb_2"]],
		"top": "hell_rot_5", "discard": ["hell_blau_4/dunkel_wuenscher"]})
	g.apply(0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_rot_flip")})
	a = _decide(g, 0)
	check(a.get("a", "") == "color" and a.get("color", "") == "lila", "Farbwahl nach Flip nach Handmehrheit (%s)" % str(a))
	_mau_decisions()
	_strength()
	# Bot arbeitet auch auf einer Sicht, die über JSON kam (Zahlen als float, wie im Netz)
	var g1 := RulesFixture.build(RuleConfig.new(), 3, {"hands": [["hell_rot_1", "hell_gelb_5", "hell_blau_5"], ["hell_blau_1"], ["hell_gelb_2"]], "top": "hell_rot_5"})
	var jv: Dictionary = JSON.parse_string(JSON.stringify(g1.view_for(0)))
	var ja := MauBot.choose(jv, 5, 1)
	check(ja.get("a", "") == "play" and bool(g1.apply(0, ja).ok), "Bot auf JSON-Sicht liefert gültige Aktion (%s)" % str(ja))
