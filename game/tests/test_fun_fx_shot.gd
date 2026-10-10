extends SceneTree
# Kontrollbilder Beta 1.4.4 (mit Renderer; „_shot“: vom Testlauf ausgenommen):
#   tools/godot_run.ps1 -Script res://tests/test_fun_fx_shot.gd -Resolution 1600x720
# docs/module/optik_144_fun_tag.png / _nacht.png: Katze läuft, Katze schläft, Himmel (Schmetterling bzw. Sternschnuppe), „Autsch!“,
# Applaus; optik_144_logo.png: Sonne grinst, Mond zwinkert.

var nav: ScreenNav
var ts: TableScreen


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
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
	for night in [false, true]:
		ts.table.set_night(1.0 if night else 0.0)
		var f: FunFx = ts.table.fun
		f.auto_process = true
		var shots: Array[Image] = []
		# Katze läuft herein (von links), dann schläft sie
		f.cat.night = 1.0 if night else 0.0
		f.cat.arrive(f._pile_pos, f._pile_w, 1600.0, true)
		await create_timer(1.3).timeout
		shots.append(_crop(Rect2i(0, 100, 400, 300)))
		await create_timer(3.0).timeout
		await create_timer(1.5).timeout
		shots.append(_crop(Rect2i(450, 150, 400, 300)))
		f.cat.leave(false, 1600.0)
		f.cat.hide_now()
		# Himmel
		f.sky.launch(night, f.rng, Vector2(1600, 720))
		await create_timer(0.35 if night else 3.0).timeout
		shots.append(_crop(Rect2i(0, 0, 1600, 360)))
		# Autsch
		f.on_event({"e": "draw", "seat": 0, "count": 5, "reason": "strafe"}, 1)
		await create_timer(0.45).timeout
		shots.append(_crop(Rect2i(1000, 0, 600, 400)))
		# Applaus
		f.on_event({"e": "finish", "seat": 2})
		await create_timer(0.5).timeout
		shots.append(_crop(Rect2i(0, 0, 600, 400)))
		_sheet(shots, dir.path_join("optik_144_fun_%s.png" % ("nacht" if night else "tag")))
		await create_timer(1.5).timeout
	# Logo
	var menu := MainMenuScreen.new()
	nav.push(menu, false)
	await create_timer(0.6).timeout
	var imgs: Array[Image] = []
	for kind in ["sun", "moon"]:
		menu._logo._face.start(kind)
		await create_timer(0.55).timeout
		imgs.append(_crop(Rect2i(0, 0, 1000, 560)))
	_sheet(imgs, dir.path_join("optik_144_logo.png"))
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
	var h := 0
	for i in shots.size():
		var im := shots[i]
		var sc := float(w) / im.get_width()
		im.resize(w, int(im.get_height() * sc), Image.INTERPOLATE_BILINEAR)
	var rows := (shots.size() + 1) / 2
	var sheet := Image.create(w * 2, 1, false, Image.FORMAT_RGBA8)
	var ys: Array[int] = []
	var y := 0
	for r in rows:
		var rh := shots[r * 2].get_height()
		if r * 2 + 1 < shots.size():
			rh = maxi(rh, shots[r * 2 + 1].get_height())
		ys.append(y)
		y += rh
	sheet = Image.create(w * 2, y, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, w, shots[i].get_height()), Vector2i((i % 2) * w, ys[i / 2]))
	sheet.save_png(path)
	print("Bild: " + path)
