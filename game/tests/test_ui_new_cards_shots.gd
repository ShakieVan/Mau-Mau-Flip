extends SceneTree
# Kontrollbilder der neuen Karten am Tisch (mit Renderer, nicht headless; „_shot“ im Namen: vom Testlauf ausgenommen):
#   godot_run.ps1 -Script res://tests/test_ui_new_cards_shots.gd -Resolution 1600x720 [-EnvPairs 'SHOT=tausch_tag']
# Bilder in docs/module/:
#   optik_tausch_tag / _nacht                 Kartentausch mitten im Flug (Hände wandern, Bogenpfeile, Hinweis)
#   optik_gluecksspiel_setzen_tag             eigener Einsatz fällig (Automat, leerer Einsatzstapel als Ziel)
#   optik_gluecksspiel_tag / _nacht           Druck fällig (Knopf pulsiert, Einsatz 2)
#   optik_gluecksspiel_walze_tag              Walze dreht
#   optik_gluecksspiel_treffer_tag / _nacht   Treffer mit großer Zahl und Strahlen
#   optik_gluecksspiel_nichts_nacht           „Nichts!“
#   optik_gluecksspiel_gegner_tag / _nacht    ein Gegner spielt (Stapel an seinem Platz)
#   optik_ablegen_tag / _nacht                Farbe mit ablegen: Karten fliegen unter die Ablegen-Karte bzw. liegen darunter
# Echter TableScreen mit LocalTable; Lagen aus RulesFixture (Platz 0 = Mensch, Computergegner handeln nicht von selbst).

var out_dir := ""
var made := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	out_dir = ProjectSettings.globalize_path("res://").path_join("../docs/module").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var only := OS.get_environment("SHOT")
	var shots := ["tausch_tag", "tausch_nacht", "gluecksspiel_setzen_tag", "gluecksspiel_tag", "gluecksspiel_nacht",
		"gluecksspiel_walze_tag", "gluecksspiel_treffer_tag", "gluecksspiel_treffer_nacht", "gluecksspiel_nichts_nacht",
		"gluecksspiel_gegner_tag", "gluecksspiel_gegner_nacht", "ablegen_tag", "ablegen_nacht"]
	if only != "":
		shots = Array(only.split(","))
	for s in shots:
		await call("shot_" + str(s))
		made += 1
	print("RESULT: %d ok" % made)
	quit(0)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := out_dir.path_join("optik_%s.png" % name)
	img.save_png(path)
	print("Bild: " + path)


func _clear() -> void:
	for c in root.get_children():
		if c.name != "App":
			c.queue_free()
	await process_frame
	await process_frame


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _settle(ts: TableScreen, extra := 0.6) -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while ts.table.director.is_busy() and Time.get_ticks_msec() < deadline:
		await process_frame
	await _wait(extra)


func _table(cfg: RuleConfig, n: int, spec: Dictionary) -> TableScreen:
	await _clear()
	var g := RulesFixture.build(cfg, n, spec, 4711)
	var seats: Array = []
	var names := ["Du", "Lena", "Tom", "Mia", "Ben", "Ida"]
	for i in n:
		(g.players[i] as Dictionary)["name"] = names[i]
		if i > 0:
			(g.players[i] as Dictionary)["kind"] = "bot"
		seats.append({"name": names[i], "kind": "human" if i == 0 else "bot", "host": i == 0})
	var t := LocalTable.new()
	t.auto_process = false
	t.autosave = false
	t.speed = 0.0
	var data := {"mode": "solo", "game": g.to_dict(), "seats": seats, "host_seat": 0}
	var ts := TableScreen.create(t, func() -> void: t.resume(data))
	root.add_child(ts)
	await _settle(ts, 0.8)
	return ts


func _game(ts: TableScreen) -> MauGame:
	return (ts.source as LocalTable).game


# ----------------------------------------------------------------- Kartentausch

func _swap(night: bool) -> void:
	var cfg := RuleConfig.new()
	cfg.swap_cards = "on"
	var spec := {"hands": [["hell_blau_tausch", "hell_rot_2", "hell_rot_flip", "hell_gelb_4", "hell_gruen_7", "hell_blau_1", "hell_wuenscher"],
		["hell_gruen_1", "hell_gruen_2", "hell_gelb_8"], ["hell_blau_7", "hell_blau_8", "hell_rot_9", "hell_gelb_1", "hell_gelb_2"],
		["hell_rot_9", "hell_gelb_9"]], "top": "hell_blau_5", "current": 0}
	if night:
		spec = {"side": "dunkel", "hands": [["dunkel_lila_tausch", "dunkel_pink_2", "dunkel_orange_flip", "dunkel_tuerkis_4", "dunkel_lila_7",
			"dunkel_pink_1", "dunkel_farbjagd"], ["dunkel_tuerkis_1", "dunkel_tuerkis_2", "dunkel_orange_8"],
			["dunkel_lila_3", "dunkel_lila_8", "dunkel_pink_9", "dunkel_orange_1", "dunkel_orange_2"], ["dunkel_pink_9", "dunkel_orange_9"]],
			"top": "dunkel_lila_5", "current": 0}
	var ts := await _table(cfg, 4, spec)
	var key := "dunkel_lila_tausch" if night else "hell_blau_tausch"
	ts.hand.play_requested.emit(RulesFixture.card(_game(ts), 0, key), ts.hand.play_target)
	await _wait(0.52 + 0.42)
	await _save("tausch_nacht" if night else "tausch_tag")


func shot_tausch_tag() -> void:
	await _swap(false)


func shot_tausch_nacht() -> void:
	await _swap(true)


# ----------------------------------------------------------------- Glücksspiel

func _gamble_cfg() -> RuleConfig:
	var cfg := RuleConfig.new()
	cfg.gamble_cards = "on"
	return cfg


func _gamble_spec(night: bool, need: String, stake: int, seat := 0) -> Dictionary:
	var light := {"hands": [["hell_rot_2", "hell_rot_7", "hell_gelb_4", "hell_gruen_7", "hell_blau_1"], ["hell_gruen_1", "hell_gruen_2", "hell_gelb_8"],
		["hell_blau_7", "hell_blau_8", "hell_rot_9", "hell_gelb_1"], ["hell_rot_9", "hell_gelb_9", "hell_blau_4"]],
		"top": "hell_gluecksspiel", "color": "gruen"}
	var dark := {"side": "dunkel", "hands": [["dunkel_pink_2", "dunkel_pink_7", "dunkel_orange_4", "dunkel_lila_7", "dunkel_tuerkis_1"],
		["dunkel_tuerkis_1", "dunkel_tuerkis_2", "dunkel_orange_8"], ["dunkel_lila_3", "dunkel_lila_8", "dunkel_pink_9", "dunkel_orange_1"],
		["dunkel_pink_9", "dunkel_orange_9", "dunkel_lila_4"]], "top": "dunkel_gluecksspiel", "color": "lila"}
	var spec: Dictionary = dark if night else light
	var keys: Array = []
	for i in stake:
		keys.append(("dunkel_tuerkis_%d" if night else "hell_blau_%d") % (5 + i))
	spec["current"] = seat
	spec["gamble"] = {"q": 3, "stake": keys, "need": need}
	return spec


func shot_gluecksspiel_setzen_tag() -> void:
	var ts := await _table(_gamble_cfg(), 4, _gamble_spec(false, "stake", 0))
	await _wait(0.3)
	await _save("gluecksspiel_setzen_tag")


func _gamble_press(night: bool) -> TableScreen:
	var ts := await _table(_gamble_cfg(), 4, _gamble_spec(night, "press", 2))
	return ts


func shot_gluecksspiel_tag() -> void:
	await _gamble_press(false)
	await _wait(0.35)
	await _save("gluecksspiel_tag")


func shot_gluecksspiel_nacht() -> void:
	await _gamble_press(true)
	await _wait(0.35)
	await _save("gluecksspiel_nacht")


func shot_gluecksspiel_walze_tag() -> void:
	var ts := await _gamble_press(false)
	_game(ts).force_rolls([7])
	ts.table.press_gamble()
	await _wait(0.45)
	await _save("gluecksspiel_walze_tag")


func _hit(night: bool) -> void:
	var ts := await _gamble_press(night)
	_game(ts).force_rolls([7])
	ts.table.press_gamble()
	await _wait(1.05 + 0.32)
	await _save("gluecksspiel_treffer_nacht" if night else "gluecksspiel_treffer_tag")


func shot_gluecksspiel_treffer_tag() -> void:
	await _hit(false)


func shot_gluecksspiel_treffer_nacht() -> void:
	await _hit(true)


func shot_gluecksspiel_nichts_nacht() -> void:
	var ts := await _gamble_press(true)
	_game(ts).force_rolls([0])
	ts.table.press_gamble()
	await _wait(1.05 + 0.3)
	await _save("gluecksspiel_nichts_nacht")


func _opponent(night: bool) -> void:
	var ts := await _table(_gamble_cfg(), 4, _gamble_spec(night, "press", 3, 1))
	await _wait(0.3)
	await _save("gluecksspiel_gegner_nacht" if night else "gluecksspiel_gegner_tag")


func shot_gluecksspiel_gegner_tag() -> void:
	await _opponent(false)


func shot_gluecksspiel_gegner_nacht() -> void:
	await _opponent(true)


# ----------------------------------------------------------------- Farbe mit ablegen

func _discard(night: bool) -> void:
	var cfg := RuleConfig.new()
	cfg.discard_color = "on"
	var spec := {"hands": [["hell_rot_ablegen", "hell_rot_3", "hell_rot_aussetzen", "hell_rot_plus1", "hell_rot_8", "hell_blau_2",
		"hell_wuenscher", "hell_gelb_6"], ["hell_gruen_1", "hell_gruen_2", "hell_gelb_8"], ["hell_blau_7", "hell_blau_8", "hell_rot_9"],
		["hell_rot_9", "hell_gelb_9"]], "top": "hell_rot_5", "current": 0}
	if night:
		spec = {"side": "dunkel", "hands": [["dunkel_tuerkis_1", "dunkel_lila_2"], ["dunkel_orange_ablegen", "dunkel_orange_3",
			"dunkel_orange_plus5", "dunkel_orange_flip", "dunkel_orange_7", "dunkel_pink_2"], ["dunkel_lila_7", "dunkel_lila_8", "dunkel_pink_9"],
			["dunkel_pink_9", "dunkel_lila_9"]], "top": "dunkel_orange_5", "current": 1, "mau_said": [1]}
	var ts := await _table(cfg, 4, spec)
	var g := _game(ts)
	if night:
		# Lena (Gegner) legt ab; Bild, wenn alles unter der Ablegen-Karte liegt
		(ts.source as LocalTable)._apply(1, {"a": "play", "card": RulesFixture.card(g, 1, "dunkel_orange_ablegen")})
		await _wait(0.52 + 0.85 + 0.4)
		await _save("ablegen_nacht")
	else:
		ts.hand.play_requested.emit(RulesFixture.card(g, 0, "hell_rot_ablegen"), ts.hand.play_target)
		await _wait(0.52 + 0.3)
		await _save("ablegen_tag")


func shot_ablegen_tag() -> void:
	await _discard(false)


func shot_ablegen_nacht() -> void:
	await _discard(true)
