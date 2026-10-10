extends SceneTree
# Kontrollbild Beta 1.4.4, freche Sprüche (mit Renderer; „_shot“: vom Testlauf ausgenommen):
#   tools/godot_run.ps1 -Script res://tests/test_fun_texts_shot.gd -Resolution 1600x720
# docs/module/optik_144_sprueche.png: Hinweisleiste mit dem längsten Spruch – Tag, Nacht, großer Modus Tag/Nacht, Englisch, Schrift sehr groß.

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
	var long := "Im Ziehstapel liegt vielleicht genau die Karte, die du brauchst. Schau mal nach."
	var shots: Array[Image] = []
	for cfg_shot in [[false, false, "de", long, "normal"], [true, false, "de", long, "sehr_gross"], [false, true, "de", long, "normal"],
			[true, true, "de", long, "sehr_gross"], [false, false, "en", long, "normal"], [true, true, "en", long, "sehr_gross"]]:
		I18n.set_language(str(cfg_shot[2]))
		UiFonts.set_level(str(cfg_shot[4]), root)
		ts.table.set_big(bool(cfg_shot[1]))
		ts.table.set_night(1.0 if cfg_shot[0] else 0.0)
		await process_frame
		shots.append(await _force(str(cfg_shot[3])))
	I18n.set_language("de")
	UiFonts.set_level("normal", root)
	var dir := ProjectSettings.globalize_path("res://").path_join("../docs/module").simplify_path()
	_sheet(shots, dir.path_join("optik_144_sprueche.png"))
	print("RESULT: 1 ok")
	quit(0)


# Spruch erzwingen (wie ein Anlass im laufenden Zug) und die ganze Bühne aufnehmen
func _force(de: String) -> Image:
	var t := ts.table
	var f := t.sprueche
	var h: Dictionary = t.view.get("hints", {})
	f._picked = de
	f._show(FunTexts.format_line(de, "Mimi"), "zug", int(t.view.get("turn", -1)))
	f._replaceable = true
	t.hint_bar.show_hint(f.text, int(t.view.get("turn", -1)) == t.my_seat)
	for i in 3:
		await process_frame
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	f._end()
	t._apply_hints(h, int(t.view.get("turn", -1)))
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
	print("Bild: " + path)
