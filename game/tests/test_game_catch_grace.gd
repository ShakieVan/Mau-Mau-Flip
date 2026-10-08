extends SceneTree

# Erwischen-Frist (Nutzerbefund 08.10.2026, GameTable.CATCH_*): Vergisst jemand „Mau!“ und sitzt ein Mensch am Tisch, der
# erwischen könnte, warten die Bots mindestens catch_grace() (≥ CATCH_MIN + CATCH_ANIM, mal Tempo-Faktor); nur Bots am Tisch:
# Denkpause wie bisher. Solange die Tischregie spielt (busy_check), beginnt die Frist neu. Ohne Erwischen (mau_call auto): keine Frist.

var failures := 0
var checks := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)


func _initialize() -> void:
	test_formula()
	test_plan()
	test_busy_restart()
	print("RESULT: %d ok" % checks if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)


func test_formula() -> void:
	check(is_equal_approx(GameTable.catch_grace(0.0, 1.0), GameTable.CATCH_GRACE + GameTable.CATCH_ANIM), "Formel: Mitte")
	check(GameTable.catch_grace(0.0, 0.4) >= GameTable.CATCH_MIN + GameTable.CATCH_ANIM - 0.001, "Formel: flott nicht unter CATCH_MIN")
	check(GameTable.catch_grace(0.0, 5.0) > GameTable.catch_grace(0.0, 1.0) and is_equal_approx(GameTable.catch_grace(GameTable.CATCH_JITTER, 5.0), GameTable.CATCH_MAX + GameTable.CATCH_ANIM), "Formel: gemütlich länger, aber gedeckelt")
	check(GameTable.CATCH_MIN >= 2.0 and GameTable.CATCH_GRACE >= 3.0, "Frist deutlich länger als die Denkpause")


# Tisch mit offenem Mau-Fenster für Platz 1 (Bot, vergessen); liefert die Wartezeit des geplanten Bot-Zugs in ms.
func plan_wait(kinds: Array, factor: float, mau_call := "catch", seed := 5, all_bots := false) -> Dictionary:
	var t := LocalTable.new()
	t.auto_process = false
	t.speed = 1.0
	t.autosave = false
	t.save_path = "user://test_game_catch_grace.json"
	root.add_child(t)
	var players: Array = []
	for i in kinds.size():
		players.append({"name": "P%d" % i, "kind": kinds[i]})
	var cfg := RuleConfig.preset("offiziell")
	cfg.mau_call = mau_call
	t.setup("solo" if kinds.count("human") <= 1 else "pass", players, cfg, seed)
	t.think_factor = factor
	if all_bots:
		t._substitute[0] = true      # „Computer spielt für …“: kein Mensch mehr am Tisch
	t.start()
	t.game.mau_open = 1
	t.game.mau_said[1] = false
	t._extra_pause = 0.0
	var now := Time.get_ticks_msec()
	var p: Dictionary = t._next_bot_plan()
	var out := {"wait": int(p.get("at", now)) - now if not p.is_empty() else -1, "plan": p, "table": t}
	return out


func free_table(r: Dictionary) -> void:
	var t: LocalTable = r.table
	t.leave()
	t.free()


func test_plan() -> void:
	for factor in [0.4, 1.0, 2.0]:
		var r := plan_wait(["human", "bot", "bot"], factor)
		var need := int(GameTable.catch_grace(0.0, factor) * 1000.0) - 5
		check(int(r.wait) >= need, "Mensch dabei, Faktor %.1f: Bot wartet ≥ %d ms (%d)" % [factor, need, int(r.wait)])
		check(int(r.wait) <= int(GameTable.catch_grace(GameTable.CATCH_JITTER, factor) * 1000.0) + 5, "Faktor %.1f: nicht länger als nötig" % factor)
		check((r.plan as Dictionary).has("grace"), "Faktor %.1f: Plan merkt sich die Frist" % factor)
		free_table(r)
	# Erwischt ein Bot? (Platz 2 sieht das Fenster)
	var r2 := plan_wait(["human", "bot", "bot"], 1.0)
	var t2: LocalTable = r2.table
	var a2 := MauBot.choose(t2.game.view_for(2), 1, 1)
	check(str(a2.get("a", "")) == "catch", "Bot würde erwischen")
	free_table(r2)
	# Nur Bots: wie bisher (Denkpause)
	var r3 := plan_wait(["human", "bot", "bot"], 1.0, "catch", 5, true)
	check(int(r3.wait) >= 0 and int(r3.wait) <= int(GameTable.THINK_MAX * 1000.0) + 5, "nur Bots: Denkpause wie bisher (%d ms)" % int(r3.wait))
	check(not (r3.plan as Dictionary).has("grace"), "nur Bots: keine Frist")
	free_table(r3)
	# Weitergeben mit zwei Menschen: Frist gilt
	var r4 := plan_wait(["human", "bot", "human", "bot"], 1.0)
	check(int(r4.wait) >= int(GameTable.catch_grace(0.0, 1.0) * 1000.0) - 5, "Weitergeben: Frist (%d ms)" % int(r4.wait))
	free_table(r4)
	# Ohne Erwischen (auto): keine Erwischen-Frist
	var r5 := plan_wait(["human", "bot", "bot"], 1.0, "auto")
	check(int(r5.wait) <= int(GameTable.THINK_MAX * 1000.0) + 5, "auto: keine Erwischen-Frist (%d ms)" % int(r5.wait))
	free_table(r5)


func test_busy_restart() -> void:
	var r := plan_wait(["human", "bot", "bot"], 0.4)
	var t: LocalTable = r.table
	t._plan = r.plan
	t._plan_dirty = false
	var busy := [true]
	t.busy_check = func() -> bool: return busy[0]
	t._plan.at = Time.get_ticks_msec() - 1     # Frist wäre schon um, aber die Regie spielt noch
	var rev := t.rev
	t.pump()
	check(t.rev == rev, "Regie beschäftigt: kein Bot-Zug")
	var left := int(t._plan.get("at", 0)) - Time.get_ticks_msec()
	check(left >= int(float(r.plan.grace) * 1000.0) - 20, "Frist beginnt nach der Animation neu (%d ms)" % left)
	busy[0] = false
	free_table(r)
