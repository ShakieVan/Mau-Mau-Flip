extends SceneTree
# Kontrollbilder Sternschnuppe (Beta 1.6.11, mit Renderer; „_shot“: vom Testlauf ausgenommen):
#   tools/godot_run.ps1 -Script res://tests/test_sternschnuppe_shot.gd -Resolution 1600x720 -Extra '--rendering-driver','opengl3_angle' -EnvPairs 'SHOT_TAG=nachher'
# docs/module/optik_1611_stern_<SHOT_TAG>_nacht.png / _tag.png: dieselbe Sternschnuppe (fester Zufall) zu mehreren Zeitpunkten,
# nachts in vollem Glanz, tagsüber (glow 0) die dezente Fassung. Die Zeit läuft von Hand (auto_process aus), damit die Bilder
# immer dieselben Augenblicke zeigen.

const TIMES := [0.2, 0.5, 0.85, 1.12, 1.3, 1.6]

var nav: ScreenNav
var ts: TableScreen


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var tag := OS.get_environment("SHOT_TAG")
	if tag == "":
		tag = "nachher"
	nav = ScreenNav.new()
	root.add_child(nav)
	await process_frame
	var cfg := RuleConfig.preset("familie")
	var players := [{"name": "Karlo", "kind": "bot"}, {"name": "Du", "kind": "human"}, {"name": "Mimi", "kind": "bot"}, {"name": "Socke", "kind": "bot"}]
	var src := GameStarter.local("solo", cfg, players, 1)
	ts = TableScreen.create(src, func() -> void: src.start())
	nav.push(ts, false)
	var deadline := Time.get_ticks_msec() + 20000
	await create_timer(1.0).timeout
	while ts.table.director.is_busy() and Time.get_ticks_msec() < deadline:
		await process_frame
	var dir := ProjectSettings.globalize_path("res://").path_join("../docs/module").simplify_path()
	for night in [true, false]:
		ts.table.set_night(1.0 if night else 0.0)
		await create_timer(1.2).timeout
		var f: FunFx = ts.table.fun
		f.auto_process = false
		f.sky.stop()
		var shots: Array[Image] = []
		var rng := RandomNumberGenerator.new()
		rng.seed = 1611
		var probe := RandomNumberGenerator.new()
		for s in 200:                         # eine Bahn, die rechts beginnt und nicht hinter den Karten oben endet
			probe.seed = 1611 + s
			if probe.randf() > 0.88 and probe.randf() < 0.45:
				rng.seed = 1611 + s
				break
		f.sky.set("glow", 1.0 if night else 0.0)
		f.sky.launch(true, rng, Vector2(1600, 720))
		var t := 0.0
		for target in TIMES:
			while t < float(target) - 0.0001:
				f.sky.step(1.0 / 60.0)
				t += 1.0 / 60.0
			await process_frame
			await process_frame
			shots.append(_crop(Rect2i(200, 0, 1400, 330)))
			if OS.get_environment("SHOT_RAW") != "":
				shots[-1].save_png(OS.get_environment("SHOT_RAW").path_join("%s_%d.png" % ["nacht" if night else "tag", shots.size()]))
		f.sky.stop()
		_sheet(shots, dir.path_join("optik_1611_stern_%s_%s.png" % [tag, "nacht" if night else "tag"]))
	print("RESULT: 1 ok")
	quit(0)


func _crop(r: Rect2i) -> Image:
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var out := Image.create(r.size.x, r.size.y, false, Image.FORMAT_RGBA8)
	out.blit_rect(img, r, Vector2i.ZERO)
	return out


func _sheet(shots: Array[Image], path: String) -> void:
	var w := 800
	for im in shots:
		im.resize(w, int(im.get_height() * float(w) / im.get_width()), Image.INTERPOLATE_BILINEAR)
	var rh := shots[0].get_height()
	var rows := (shots.size() + 1) / 2
	var sheet := Image.create(w * 2 + 4, rows * (rh + 4), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.5, 0.5, 0.5))
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, w, rh), Vector2i((i % 2) * (w + 4), (i / 2) * (rh + 4)))
	sheet.save_png(path)
	print("Bild: " + path)
