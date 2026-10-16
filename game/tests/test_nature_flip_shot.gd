extends SceneTree
# Kontrollbild Flip der Natur-Überraschungen (Beta 1.6.12, docs/module/natur.md 8.4, Aufgabe T7; „_shot“: vom Testlauf ausgenommen):
#   tools/godot_run.ps1 -Script res://tests/test_nature_flip_shot.gd -Resolution 1600x720 -Extra '--rendering-driver','opengl3_angle'
# Echte TableScreen (Übung, 4 Spieler), die Uhr steht (Engine.time_scale = 0); der Tag/Nacht-Wechsel wird mit TableView.set_night
# gestellt, das Natur-Ereignis bekommt das Spielereignis „flip“ über nature.on_event wie von der Tischregie.
#   docs/module/optik_1612_natur_flip.png   oben:   Tag mit Marienkäfer | Flip beginnt (Nacht 0,4), der Marienkäfer geht schnell ab
#                                           Mitte:  Nacht, Glühwürmchen kommen (Anlass Flip) | Glühwürmchen in der Hauptphase
#                                           unten:  Flip zum Tag, Regenbogen blendet ein | Regenbogen in der Hauptphase
# Prüft nebenbei: Abgang des Tagtiers ≤ 0,4 s nach dem Flip (sonst RESULT mit FAIL).

var nav: ScreenNav
var ts: TableScreen
var nf: NatureFx
var dir := ""
var fails := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	dir = ProjectSettings.globalize_path("res://").path_join("../docs/module").simplify_path()
	await open_table()
	var shots: Array[Image] = []
	# 1. Tag: Marienkäfer läuft (wie ein Zufallsereignis, nicht eingefroren)
	ts.table.set_night(0.0)
	nf.spawn("marienkaefer", 3, {"anlass": "zufall"})
	var c := nf.creature()
	var mid := float(c.get("in_s")) + (float(c.get("dur")) - float(c.get("out_s")) - float(c.get("in_s"))) * 0.55
	nf.seek(mid)
	await frames()
	shots.append(_shot())
	# 2. Flip beginnt: Spielereignis flip → schneller Abgang, Hintergrund halb gewechselt
	nf.on_event({"e": "flip", "side": "dunkel"})
	ts.table.set_night(0.4)
	var p := _screen_center(c)
	nf.tick(0.15)
	await frames()
	shots.append(_crop_at(p, Vector2(800, 360)))
	var gone := false
	for i in 6:
		nf.tick(0.05)
		if nf.current == null or nf.current.id != "marienkaefer":
			gone = true
			break
	_check(gone, "Marienkäfer geht nach dem Flip in ≤ 0,45 s ab")
	nf.clear()
	# 3. Nacht: Glühwürmchen als Flip-Anlass (Einflug und Hauptphase)
	ts.table.set_night(1.0)
	nf.spawn("gluehwuermchen", 1612, {"anlass": "flip", "still": true})
	c = nf.creature()
	_check(c != null, "Glühwürmchen gezeichnet")
	if c != null:
		nf.seek(float(c.get("in_s")) * 0.7)
		await frames()
		shots.append(_shot())
		nf.seek((float(c.get("in_s")) + float(c.get("dur")) - float(c.get("out_s"))) * 0.5)
		await frames()
		shots.append(_shot())
	nf.clear()
	# 4. Flip zum Tag: Regenbogen (nur nach einem Flip zum Tag)
	ts.table.set_night(0.0)
	nf.spawn("regenbogen", 13, {"anlass": "flip", "still": true})
	c = nf.creature()
	_check(c != null, "Regenbogen gezeichnet")
	if c != null:
		nf.seek(0.8)
		await frames()
		shots.append(_shot())
		nf.seek(3.5)
		await frames()
		shots.append(_shot())
	nf.clear()
	await frames()
	_sheet(shots, 2, 800, dir.path_join("optik_1612_natur_flip.png"))
	Engine.time_scale = 1.0
	print("RESULT: 1 ok" if fails == 0 else "RESULT: %d FAIL" % fails)
	quit(0 if fails == 0 else 1)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: " + msg)


func open_table() -> void:
	nav = ScreenNav.new()
	root.add_child(nav)
	await process_frame
	var cfg := RuleConfig.preset("familie")
	var players: Array = []
	for n in ["Karlo", "Du", "Mimi", "Socke"]:
		players.append({"name": n, "kind": "human" if n == "Du" else "bot"})
	var src := GameStarter.local("solo", cfg, players, 1)
	ts = TableScreen.create(src, func() -> void: src.start())
	nav.push(ts, false)
	var deadline := Time.get_ticks_msec() + 20000
	await create_timer(1.0).timeout
	while ts.table.director.is_busy() and Time.get_ticks_msec() < deadline:
		await process_frame
	ts.table.fun.cat_chance = 0.0
	ts.table.fun.auto_process = false
	nf = ts.table.nature
	nf.print_log = false
	nf.auto_process = false
	await create_timer(1.0).timeout
	Engine.time_scale = 0.0               # Uhr anhalten: Computergegner und Animationen stehen
	for i in 4:
		await process_frame


func frames() -> void:
	for i in 3:
		await process_frame


func _screen_center(c: Node2D) -> Vector2:
	var b: Rect2 = c.call("bounds")
	return (c.get_parent() as Node2D).get_global_transform_with_canvas() * b.get_center()


func _shot(r := Rect2i(0, 0, 1600, 720)) -> Image:
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
	var im := _shot(Rect2i(int(x), int(y), int(size.x), int(size.y)))
	im.resize(1600, 720, Image.INTERPOLATE_BILINEAR)   # vergrößert auf Tischformat (gleiche Kachelgröße im Bogen)
	return im


func _sheet(shots: Array[Image], cols: int, w: int, path: String) -> void:
	var rows := int(ceil(float(shots.size()) / float(cols)))
	var h := 0
	for im in shots:
		im.resize(w, int(im.get_height() * float(w) / float(im.get_width())), Image.INTERPOLATE_BILINEAR)
		h = maxi(h, im.get_height())
	var sheet := Image.create(w * cols + (cols - 1) * 4, rows * h + (rows - 1) * 4, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.12, 0.12, 0.14))
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, w, shots[i].get_height()), Vector2i((i % cols) * (w + 4), (i / cols) * (h + 4)))
	sheet.save_png(path)
	print("Bild: " + path.get_file())
