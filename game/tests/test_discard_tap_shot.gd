extends SceneTree
# Kontrollbild Beta 1.4.9, Ablegen-Joker mit Ablegefarbe per Antippen (mit Renderer; „_shot“: vom Testlauf ausgenommen):
#   tools/godot_run.ps1 -Script res://tests/test_discard_tap_shot.gd -Resolution 1600x720
# docs/module/optik_149_ablegen_tippen.png: Joker gelegt (Hinweis „Tippe auf …“), Blau angetippt (Tag, Nacht, großer Modus Tag/Nacht),
# danach das Farbrad der Spielfarbe.

var ts: TableScreen


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(1600, 720)
	var cfg := RuleConfig.new()
	cfg.discard_color = "on"
	var g := RulesFixture.build(cfg, 3, {"hands": [["hell_ablegen_joker", "hell_blau_3", "hell_blau_4", "hell_blau_aussetzen", "hell_rot_7",
		"hell_gelb_2", "hell_wuenscher"], ["hell_gruen_1", "hell_gruen_2"], ["hell_rot_1", "hell_rot_2"]], "top": "hell_rot_5", "current": 0}, 4711)
	var seats: Array = []
	for i in 3:
		if i > 0:
			(g.players[i] as Dictionary)["kind"] = "bot"
		seats.append({"name": str(g.players[i].name), "kind": "human" if i == 0 else "bot", "host": i == 0})
	var t := LocalTable.new()
	t.auto_process = false
	t.autosave = false
	t.speed = 0.0
	var data := {"mode": "solo", "game": g.to_dict(), "seats": seats, "host_seat": 0}
	ts = TableScreen.create(t, func() -> void: t.resume(data))
	root.add_child(ts)
	await _settle()
	ts.hand.play_requested.emit(RulesFixture.card(g, 0, "hell_ablegen_joker"), ts.hand.play_target)
	await _settle()
	var shots: Array[Image] = []
	shots.append(await _shot(false, false))
	ts.hand.call("_on_tap", RulesFixture.card(g, 0, "hell_blau_3"))
	await create_timer(0.6).timeout
	for c in [[false, false], [true, false], [false, true], [true, true]]:
		shots.append(await _shot(c[0], c[1]))
	ts.table.set_big(false)
	ts.table.set_night(0.0)
	(ts.table.get("_act_btns")["pick"] as PillButton).pressed.emit()
	await create_timer(0.6).timeout
	shots.append(await _shot(false, false))
	var dir := ProjectSettings.globalize_path("res://").path_join("../docs/module").simplify_path()
	_sheet(shots, dir.path_join("optik_149_ablegen_tippen.png"))
	print("RESULT: 1 ok")
	quit(0)


func _settle() -> void:
	var deadline := Time.get_ticks_msec() + 15000
	await create_timer(0.5).timeout
	while ts.table.director.is_busy() and Time.get_ticks_msec() < deadline:
		await process_frame
	await create_timer(0.8).timeout


func _shot(night: bool, big: bool) -> Image:
	ts.table.set_big(big)
	ts.table.set_night(1.0 if night else 0.0)
	await create_timer(0.5).timeout
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _sheet(shots: Array[Image], path: String) -> void:
	var w := 800
	for im in shots:
		im.resize(w, int(im.get_height() * float(w) / im.get_width()), Image.INTERPOLATE_BILINEAR)
	var rows := (shots.size() + 1) / 2
	var rh := shots[0].get_height()
	var sheet := Image.create(w * 2, rh * rows, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, w, rh), Vector2i((i % 2) * w, (i / 2) * rh))
	sheet.save_png(path)
