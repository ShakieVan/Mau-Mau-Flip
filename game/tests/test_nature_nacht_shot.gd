extends SceneTree
# Kontrollbilder Nachttiere der Natur-Überraschungen (Beta 1.6.12, Aufgabe T4; mit Renderer, „_shot“: vom Testlauf ausgenommen):
#   tools/godot_run.ps1 -Script res://tests/test_nature_nacht_shot.gd -Resolution 1600x720 -Extra '--rendering-driver','opengl3_angle'
# Echte TableView mit Hand (4 Spieler, Nachtseite), Tiere über nature.spawn(id, seed, {t, still}) zu festen Zeitpunkten:
#   docs/module/optik_<Stand>_natur_<id>.png      je Ereignis drei Augenblicke: Anflug/Beginn, Hauptphase, Reaktion auf Tipp bzw. Abgang
#                                                 (UFO ab 1.6.15: Ausweichen nach dem 1. Tipp)
#   docs/module/optik_<Stand>_natur_nacht.png     Übersicht: Hauptphase aller vierzehn Nachtereignisse
#   docs/module/optik_<Stand>_natur_nacht_ruhig.png  „Effekte reduziert“: Mond mit Mütze, Polarlicht, Sternbild (ruhige Fassung)
#   docs/module/optik_<Stand>_natur_nacht_8sp.png    8 Spieler: Eule, Igel, Glühwürmchen, Motte, Lampion, UFO, Feuerwerk, Astronaut
#   docs/module/optik_<Stand>_natur_nacht_tisch.png  ganzer Tisch mit UFO-Lichtkegel (Stapel bleibt lesbar)
# Umgebung: NUR=<id,…> nur diese ids, SHOT_SUFFIX=<text> hängt an die Dateinamen an (z. B. „_1600x900“ bei anderer Auflösung),
# SHOT_DIR=<Ordner> statt docs/module, STAND=<Zahl> (Standard 1615; die Bilder bis 1.6.12 heißen optik_1612_…).

const Night := preload("res://scripts/ui/nature_night.gd")
const SD := 1612
var CROP_H := 300
var near := false

var t: TableView
var nf: NatureFx
var out_dir := ""
var suffix := ""
var stand := "1615"


func _initialize() -> void:
	call_deferred("run")


func ids() -> Array:
	var e := OS.get_environment("NUR")
	var out: Array = []
	for id in Night.ids():
		if e == "" or e.split(",").has(id):
			out.append(id)
	return out


func run() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://").path_join("../docs/module").simplify_path()
	suffix = OS.get_environment("SHOT_SUFFIX")
	if OS.get_environment("STAND") != "":
		stand = OS.get_environment("STAND")
	near = OS.get_environment("SHOT_NAH") != ""
	if near:
		CROP_H = 420
	await make_table(4)
	var overview: Array[Image] = []
	for id in ids():
		var shots := await triple(id)
		_row(shots, out_dir.path_join("optik_%s_natur_%s%s.png" % [stand, id, suffix]))
		overview.append(shots[1])
	if ids().size() == Night.ids().size():
		_grid(overview, 3, out_dir.path_join("optik_%s_natur_nacht%s.png" % [stand, suffix]))
		# ruhige Fassung
		nf.set_reduced(true)
		var calm: Array[Image] = []
		for id in ["mond_muetze", "polarlicht", "sternbild"]:
			calm.append(await single(id, -1.0, Rect2()))
		nf.set_reduced(false)
		_row(calm, out_dir.path_join("optik_%s_natur_nacht_ruhig%s.png" % [stand, suffix]))
		# ganzer Tisch mit dem UFO-Kegel
		nf.spawn("ufo", SD, {"t": 3.0, "still": true})
		await frames(3)
		var full := root.get_texture().get_image()
		full.convert(Image.FORMAT_RGBA8)
		full.save_png(out_dir.path_join("optik_%s_natur_nacht_tisch%s.png" % [stand, suffix]))
		print("Bild: optik_%s_natur_nacht_tisch%s.png" % [stand, suffix])
		# 8 Spieler
		await make_table(8)
		var many: Array[Image] = []
		for id in ["eule", "igel", "gluehwuermchen", "motte", "lampion", "ufo", "feuerwerk", "astronaut"]:
			many.append(await single(id, -1.0, Rect2()))
		_grid(many, 3, out_dir.path_join("optik_%s_natur_nacht_8sp%s.png" % [stand, suffix]))
	nf.clear()
	print("RESULT: 1 ok")
	quit(0)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func make_table(players: int) -> void:
	if t != null:
		t.queue_free()
		await frames(2)
	var sz := Vector2(root.get_visible_rect().size)
	t = TableView.new()
	root.add_child(t)
	t.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	t.size = sz
	t.sprueche.set_level("aus")
	t.fun.auto_process = false
	t.tease.auto_process = false
	t.nature.auto_process = false
	t.nature.print_log = false
	var hand := HandView.new()
	hand.name = "Hand"
	t.set_hand(hand)
	hand.layout_rect = t.hand_rect(sz)
	t.set_night(1.0)
	var s := TableSamples.create(players, 7)
	s.turn = 1
	s.side = "dunkel"
	t.apply_view(s.view_for(0))
	t.director.flush()
	for i in 80:
		hand.step(0.05)
	nf = t.nature
	await frames(20)


# Zeitpunkte je Ereignis: [Anflug, Hauptphase, Reaktion] – Reaktion: ["tap", t, dt] | ["leave", t, dt] | ["time", t]
func plan(id: String, c: Node) -> Array:
	var dur := float(c.get("dur"))
	var in_s := float(c.get("in_s"))
	match id:
		"gluehwuermchen":
			return [1.0, 6.0, ["tap", 6.0, 0.3]]
		"eule":
			return [0.8, float(c.get("t_turn")) + 1.0, ["tap", float(c.get("t_turn")) + 1.0, 0.32]]
		"fledermaus":
			return [dur * 0.25, dur * 0.5, ["time", dur * 0.72]]
		"mond_muetze":
			return [0.32, 3.4, ["tap", 4.2, 0.3]]
		"polarlicht":
			return [1.6, 6.5, ["time", dur - 1.6]]
		"sternbild":
			return [1.6, in_s - 0.6, ["tap", in_s + 1.2, 0.18]]
		"ufo":
			return [0.85, 3.0, ["tap", 3.0, 0.3]]
		"feuerwerk":
			var bs: Array = c.get("bursts")
			var t1 := float((bs[0] as Dictionary)["t"])
			return [t1 - 0.45, t1 + 0.55, ["tap", t1 + 0.9, 0.45]]
		"astronaut":
			return [1.3, float(c.get("t_wave")) + 0.8, ["tap", float(c.get("t_wave")) + 2.4, 0.8]]
		"satellit":
			return [dur * 0.25, float(c.get("t_flash")) + 0.2, ["time", dur * 0.8]]
		"motte":
			return [0.6, 3.2, ["leave", 4.0, 0.18]]
		"igel":
			var sniff := float((c.get("segs") as Array)[1][0]) + 0.4
			return [0.8, sniff, ["tap", sniff + 1.0, 0.7]]
		"komet":
			return [2.0, dur * 0.5, ["time", dur - 2.4]]
		"lampion":
			var tm := (float(c.get("y0")) - 0.16 * t.size.y) / float(c.get("speed"))
			return [1.6, tm, ["tap", tm + 0.8, 0.16]]
	return [1.0, dur * 0.5, ["time", dur - 0.5]]


func pose(id: String, step: Variant) -> void:
	if step is float:
		nf.spawn(id, SD, {"t": float(step), "still": true})
		return
	var st: Array = step
	nf.spawn(id, SD, {"t": float(st[1]), "still": true})
	var c := nf.creature() as NatureCreature
	match str(st[0]):
		"tap":
			var p := tap_point(id, c)
			c.tap_at = float(st[1])
			c.tap_pos = p
			c.on_tap(p)
			nf.seek(float(st[1]) + float(st[2]))
		"leave":
			c.leave(true)
			nf.seek(float(st[1]) + float(st[2]))


func tap_point(id: String, c: NatureCreature) -> Vector2:
	if id == "gluehwuermchen":
		var pts: Array = c.get("pts")
		return pts[0] if not pts.is_empty() else Vector2.ZERO
	var b := c.bounds()
	return b.get_center()


func triple(id: String) -> Array[Image]:
	nf.spawn(id, SD, {"t": 0.0, "still": true})
	var steps := plan(id, nf.creature())
	var rects: Array[Rect2] = []
	for st in steps:
		pose(id, st)
		rects.append(nf.world_bounds())
	var crop := crop_rect(rects)
	var out: Array[Image] = []
	for i in steps.size():
		pose(id, steps[i])
		await frames(3)
		out.append(_crop(crop_rect([rects[i]]) if near else crop))
	return out


func single(id: String, tt: float, crop: Rect2) -> Image:
	nf.spawn(id, SD, {"t": 0.0, "still": true})
	var steps := plan(id, nf.creature())
	var at: Variant = steps[1] if tt < 0.0 else tt
	pose(id, at)
	var r := crop if crop.has_area() else crop_rect([nf.world_bounds()])
	await frames(3)
	return _crop(r)


func crop_rect(rects: Array) -> Rect2:
	var u := Rect2()
	for r in rects:
		var rr: Rect2 = r
		if rr.has_area():
			u = rr if not u.has_area() else u.merge(rr)
	var scr := Rect2(Vector2.ZERO, t.size)
	if not u.has_area():
		return scr
	u = u.grow(26.0 if near else 110.0)
	var min_sz := Vector2(150, 110) if near else Vector2(560, 320)
	if u.size.x < min_sz.x:
		u = u.grow_individual((min_sz.x - u.size.x) * 0.5, 0, (min_sz.x - u.size.x) * 0.5, 0)
	if u.size.y < min_sz.y:
		u = u.grow_individual(0, (min_sz.y - u.size.y) * 0.5, 0, (min_sz.y - u.size.y) * 0.5)
	# im Bild halten (verschieben statt abschneiden, wo es geht)
	var p := u.position
	p.x = clampf(p.x, 0.0, maxf(0.0, scr.size.x - u.size.x))
	p.y = clampf(p.y, 0.0, maxf(0.0, scr.size.y - u.size.y))
	return Rect2(p, u.size).intersection(scr)


func _crop(r: Rect2) -> Image:
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var ri := Rect2i(r)
	var out := Image.create(ri.size.x, ri.size.y, false, Image.FORMAT_RGBA8)
	out.blit_rect(img, ri, Vector2i.ZERO)
	return out


func _fit(im: Image, h: int) -> Image:
	var c := im.duplicate() as Image
	var w := int(round(float(c.get_width()) * float(h) / float(c.get_height())))
	c.resize(maxi(w, 1), h, Image.INTERPOLATE_LANCZOS)
	return c


func _row(shots: Array[Image], path: String) -> void:
	var fitted: Array[Image] = []
	var w := 0
	for im in shots:
		var f := _fit(im, CROP_H)
		fitted.append(f)
		w += f.get_width() + 6
	var sheet := Image.create(maxi(w - 6, 1), CROP_H, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.06, 0.07, 0.14))
	var x := 0
	for f in fitted:
		sheet.blit_rect(f, Rect2i(Vector2i.ZERO, f.get_size()), Vector2i(x, 0))
		x += f.get_width() + 6
	sheet.save_png(path)
	print("Bild: " + path)


func _grid(shots: Array[Image], cols: int, path: String) -> void:
	var cw := 520
	var ch := 300
	var rows := (shots.size() + cols - 1) / cols
	var sheet := Image.create(cols * cw + (cols - 1) * 6, rows * ch + (rows - 1) * 6, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.06, 0.07, 0.14))
	for i in shots.size():
		var im := shots[i].duplicate() as Image
		var sc := minf(float(cw) / im.get_width(), float(ch) / im.get_height())
		im.resize(maxi(1, int(im.get_width() * sc)), maxi(1, int(im.get_height() * sc)), Image.INTERPOLATE_LANCZOS)
		var ox := (i % cols) * (cw + 6) + (cw - im.get_width()) / 2
		var oy := (i / cols) * (ch + 6) + (ch - im.get_height()) / 2
		sheet.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(ox, oy))
	sheet.save_png(path)
	print("Bild: " + path)
