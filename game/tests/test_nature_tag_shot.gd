extends SceneTree
# Kontrollbilder der Tagtiere (Beta 1.6.12, docs/module/natur.md Abschnitt 8.4, Aufgabe T3; „_shot“: vom Testlauf ausgenommen):
#   tools/godot_run.ps1 -Script res://tests/test_nature_tag_shot.gd -Resolution 1600x720 -Extra '--rendering-driver','opengl3_angle'
#   tools/godot_run.ps1 -Script res://tests/test_nature_tag_shot.gd -Resolution 1600x900 -Extra '--rendering-driver','opengl3_angle' -EnvPairs 'SHOT_MODE=900'
# Echte TableScreen (Übung, 4 Spieler, Tagseite), die Uhr steht (Engine.time_scale = 0, die Tiere werden mit seek gestellt):
#   docs/module/optik_1612_natur_<id>.png   oben links der ganze Tisch (Hauptphase), daneben vergrößert die Hauptphase, unten
#                                           vergrößert Anflug bzw. Einblenden und die Reaktion nach dem Tipp bzw. der Abgang
#   docs/module/optik_1612_natur_tag.png    Übersicht: alle Tagtiere vergrößert in der Hauptphase
#   docs/module/optik_1612_natur_ruhig.png  Wolke und Regenbogen bei „Effekte reduziert“
#   docs/module/optik_1612_natur_8spieler.png  Marienkäfer, Spatz, Libelle, Schnecke, Biene bei 8 Spielern (Plätze gemieden)
#   SHOT_MODE=900: docs/module/optik_1612_natur_900.png (1600 × 900: Biene auf der Karte, Spatz, Pusteblume, Wolke)
# NUR=<id,…> beschränkt die Einzelbilder.

const IDS := ["marienkaefer", "biene", "libelle", "pusteblume", "papierflieger", "seifenblasen", "spatz", "wolke", "regenbogen",
	"heissluftballon", "schnecke"]
const SEED := {"marienkaefer": 3, "biene": 21, "libelle": 4, "pusteblume": 6, "papierflieger": 7, "seifenblasen": 8, "spatz": 9,
	"wolke": 12, "regenbogen": 13, "heissluftballon": 10, "schnecke": 11}
const BIG := ["pusteblume", "seifenblasen", "wolke", "regenbogen", "heissluftballon", "papierflieger"]

var nav: ScreenNav
var ts: TableScreen
var nf: NatureFx
var dir := ""


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	dir = ProjectSettings.globalize_path("res://").path_join("../docs/module").simplify_path()
	var mode := OS.get_environment("SHOT_MODE")
	await open_table(4)
	if mode == "900":
		await extra_900()
	else:
		var only := OS.get_environment("NUR")
		var overview: Array[Image] = []
		for id in IDS:
			var img := await shoot(id, only == "" or only.split(",").has(id))
			overview.append(img)
		if only == "":
			_sheet(overview, 4, 400, dir.path_join("optik_1612_natur_tag.png"))
			await calm_sheet()
			await open_table(8)
			await players8()
	Engine.time_scale = 1.0
	print("RESULT: 1 ok")
	quit(0)


func open_table(n: int) -> void:
	Engine.time_scale = 1.0
	if nav != null:
		nav.queue_free()
		await process_frame
	nav = ScreenNav.new()
	root.add_child(nav)
	await process_frame
	var cfg := RuleConfig.preset("familie")
	var names := ["Karlo", "Du", "Mimi", "Socke", "Lena", "Ben", "Kim", "Ute"]
	var players: Array = []
	for i in n:
		players.append({"name": names[i], "kind": "human" if i == 1 else "bot"})
	var src := GameStarter.local("solo", cfg, players, 1)
	ts = TableScreen.create(src, func() -> void: src.start())
	nav.push(ts, false)
	var deadline := Time.get_ticks_msec() + 20000
	await create_timer(1.0).timeout
	while ts.table.director.is_busy() and Time.get_ticks_msec() < deadline:
		await process_frame
	ts.table.set_night(0.0)
	ts.table.fun.cat_chance = 0.0
	ts.table.fun.auto_process = false
	nf = ts.table.nature
	nf.print_log = false
	await create_timer(1.0).timeout
	Engine.time_scale = 0.0               # Uhr anhalten: Computergegner und Animationen stehen, die Tiere stellt seek
	for i in 4:
		await process_frame


func frames() -> void:
	for i in 3:
		await process_frame


# Brennpunkt des Tiers in Bildschirmkoordinaten
func focus(c: Node2D) -> Vector2:
	var p := Vector2.ZERO
	if c.get("cpos") is Vector2:
		p = c.get("cpos")
	elif c.get("pos") is Vector2 and c.get("pos") != Vector2.ZERO:
		p = c.get("pos")
	else:
		var b: Rect2 = c.call("bounds")
		p = b.get_center()
		if c.get("poses") is Array and not (c.get("poses") as Array).is_empty():
			var sum := Vector2.ZERO
			var n := 0
			for ps in c.get("poses"):
				if float(ps[3]) > 0.1 and (ps[0] as Vector2).x > 0.0 and (ps[0] as Vector2).x < 1600.0:
					sum += ps[0]
					n += 1
			if n > 0:
				p = sum / float(n)
	var lay: Node2D = c.get_parent()
	return lay.get_global_transform_with_canvas() * p


func tap(c: Node2D, tt: float, p: Vector2) -> void:
	nf.seek(tt)
	c.set("tap_at", tt)
	c.set("tap_pos", p)
	c.call("on_tap", p)


func shoot(id: String, save: bool) -> Image:
	nf.spawn(id, int(SEED[id]), {"still": true})
	var c := nf.creature()
	var dur := float(c.get("dur"))
	var in_s := float(c.get("in_s"))
	var out_s := float(c.get("out_s"))
	var mid := (in_s + dur - out_s) * 0.5
	var t_in := in_s * 0.6
	var big := BIG.has(id)
	match id:
		"biene":
			mid = (float(c.get("t_d1")) + float(c.get("t_s1"))) * 0.5
			t_in = in_s + float(c.get("per")) * 0.3
		"marienkaefer":
			mid = in_s + (dur - out_s - in_s) * 0.55
		"pusteblume":
			mid = 7.0
			t_in = 3.0
		"seifenblasen":
			mid = 5.0
			t_in = 2.5
		"wolke":
			mid = dur - out_s - 1.0
			t_in = 3.0
		"regenbogen":
			mid = 3.5
			t_in = 0.8
		"schnecke":
			mid = 14.0
			t_in = 0.55
		"papierflieger":
			mid = dur * 0.45
			t_in = dur * 0.2
	if not ["biene", "wolke", "regenbogen", "schnecke"].has(id):
		mid = best_time(in_s, dur - out_s, mid)
	var size := Vector2(800, 450) if big else Vector2(400, 225)
	# Hauptphase: ganzer Tisch und vergrößert
	nf.seek(mid)
	await frames()
	var full := _shot(Rect2i(0, 0, 1600, 720))
	var zoom_main := _crop_at(focus(c), size)
	# Anflug / Einblenden
	nf.seek(t_in)
	await frames()
	var zoom_in := _crop_at(focus(c), size)
	# Reaktion nach dem Tipp bzw. Abgang
	var zoom_r: Image
	var react := str(NT_tipp(id))
	if react != "":
		nf.spawn(id, int(SEED[id]), {"still": true})
		c = nf.creature()
		nf.seek(mid)
		var p: Vector2 = (c.call("bounds") as Rect2).get_center()
		if id == "seifenblasen" or id == "pusteblume":
			p = (c.get("poses") as Array)[0][0] if not (c.get("poses") as Array).is_empty() else p
		tap(c, mid, p)
		var dt := {"marienkaefer": 0.18, "libelle": 0.12, "pusteblume": 0.5, "papierflieger": 0.45, "seifenblasen": 0.08,
			"spatz": 0.3, "heissluftballon": 0.3, "schnecke": 0.25}
		nf.seek(mid + float(dt.get(id, 0.3)))
		await frames()
		zoom_r = _crop_at(focus(c) if id != "seifenblasen" else _screen(c, p), size)
	else:
		nf.seek(dur - out_s * 0.5 if id != "biene" else float(c.get("t_s1")) + 0.25)
		await frames()
		zoom_r = _crop_at(focus(c), size)
	nf.clear()
	await frames()
	if save:
		var sheet := Image.create(1600, 900, false, Image.FORMAT_RGBA8)
		sheet.fill(Color(0.12, 0.12, 0.14))
		full.resize(800, 360, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(full, Rect2i(0, 0, 800, 360), Vector2i(0, 0))
		for pair in [[zoom_main, Vector2i(800, 0)], [zoom_in, Vector2i(0, 450)], [zoom_r, Vector2i(800, 450)]]:
			var im: Image = pair[0]
			im.resize(800, 450, Image.INTERPOLATE_BILINEAR)
			sheet.blit_rect(im, Rect2i(0, 0, 800, 450), pair[1])
		sheet.save_png(dir.path_join("optik_1612_natur_%s.png" % id))
		print("Bild: optik_1612_natur_%s.png" % id)
	var ov := zoom_main.duplicate() as Image
	ov.resize(400, 225, Image.INTERPOLATE_BILINEAR)
	return ov


# Zeitpunkt der Hauptphase, zu dem das Tier gut zu sehen ist (wenig unter Plätzen und Karten), möglichst nah an want
func best_time(a: float, b: float, want: float) -> float:
	var obs := nf.obstacles()
	var best := want
	var best_c := 1.0e9
	for i in 31:
		var tt := lerpf(a, b, float(i) / 30.0)
		nf.seek(tt)
		var r := nf.world_bounds()
		if not r.has_area() or not r.intersects(Rect2(0, 0, 1600, 720)):
			continue
		var cov := 0.0
		for key in obs:
			for q in obs[key]:
				if r.intersects(q):
					cov += r.intersection(q).get_area()
		var sc := cov / r.get_area() + 0.4 * absf(tt - want) / maxf(b - a, 0.1)
		if sc < best_c:
			best_c = sc
			best = tt
	return best


func NT_tipp(id: String) -> String:
	return str(preload("res://scripts/ui/nature_table.gd").entry(id).get("tipp", ""))


func _screen(c: Node2D, p: Vector2) -> Vector2:
	return (c.get_parent() as Node2D).get_global_transform_with_canvas() * p


func calm_sheet() -> void:
	nf.set_reduced(true)
	var imgs: Array[Image] = []
	for id in ["wolke", "regenbogen"]:
		nf.spawn(id, int(SEED[id]), {"still": true})
		var c := nf.creature()
		nf.seek(float(c.get("in_s")) + 2.0)
		await frames()
		imgs.append(_shot(Rect2i(0, 0, 1600, 720)))
		nf.clear()
	nf.set_reduced(false)
	_sheet(imgs, 1, 1600, dir.path_join("optik_1612_natur_ruhig.png"))


func players8() -> void:
	var imgs: Array[Image] = []
	for id in ["marienkaefer", "spatz", "libelle", "schnecke", "biene", "seifenblasen"]:
		nf.spawn(id, int(SEED[id]) + 1, {"still": true, "troedler": 3})
		var c := nf.creature()
		var mid := (float(c.get("in_s")) + float(c.get("dur")) - float(c.get("out_s"))) * 0.5
		if id == "biene":
			mid = float(c.get("in_s")) + float(c.get("per")) * 0.4
		elif id == "schnecke":
			mid = 20.0
		nf.seek(mid)
		await frames()
		imgs.append(_shot(Rect2i(0, 0, 1600, 720)))
		nf.clear()
	_sheet(imgs, 2, 800, dir.path_join("optik_1612_natur_8spieler.png"))


func extra_900() -> void:
	var imgs: Array[Image] = []
	for id in ["biene", "spatz", "pusteblume", "wolke"]:
		nf.spawn(id, int(SEED[id]), {"still": true})
		var c := nf.creature()
		var mid := (float(c.get("in_s")) + float(c.get("dur")) - float(c.get("out_s"))) * 0.5
		if id == "biene":
			mid = (float(c.get("t_d1")) + float(c.get("t_s1"))) * 0.5
		elif id == "pusteblume":
			mid = 7.0
		nf.seek(mid)
		await frames()
		imgs.append(_shot(Rect2i(0, 0, 1600, 900)))
		nf.clear()
	_sheet(imgs, 2, 800, dir.path_join("optik_1612_natur_900.png"))


func _shot(r: Rect2i) -> Image:
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var w := mini(r.size.x, img.get_width() - r.position.x)
	var h := mini(r.size.y, img.get_height() - r.position.y)
	var out := Image.create(r.size.x, r.size.y, false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2i(r.position, Vector2i(w, h)), Vector2i.ZERO)
	return out


func _crop_at(p: Vector2, size: Vector2) -> Image:
	var vp := root.get_texture().get_size()
	var x := clampf(p.x - size.x * 0.5, 0.0, float(vp.x) - size.x)
	var y := clampf(p.y - size.y * 0.5, 0.0, float(vp.y) - size.y)
	return _shot(Rect2i(int(x), int(y), int(size.x), int(size.y)))


func _sheet(shots: Array[Image], cols: int, w: int, path: String) -> void:
	var rows := int(ceil(float(shots.size()) / float(cols)))
	var hs: Array[int] = []
	for im in shots:
		var sc := float(w) / float(im.get_width())
		im.resize(w, int(im.get_height() * sc), Image.INTERPOLATE_BILINEAR)
	var y := 0
	var ys: Array[int] = []
	for r in rows:
		var rh := 0
		for c in cols:
			var i := r * cols + c
			if i < shots.size():
				rh = maxi(rh, shots[i].get_height())
		ys.append(y)
		hs.append(rh)
		y += rh
	var sheet := Image.create(w * cols, y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.12, 0.12, 0.14))
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, w, shots[i].get_height()), Vector2i((i % cols) * w, ys[i / cols]))
	sheet.save_png(path)
	print("Bild: " + path.get_file())
