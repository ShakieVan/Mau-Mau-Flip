extends SceneTree
# Kontrollbilder der Sonnenstrahlen im Tischhintergrund (mit Renderer, nicht headless; „_shot“ im Namen: vom Testlauf ausgenommen):
#   godot_run.ps1 -Script res://tests/test_ui_rays_shot.gd -Resolution 1600x720
# Bilder in docs/module/optik_strahlen_<name>.png: tag (Tisch mit Karten), daemmerung (tageszeit 0,5), nacht, hintergrund
# (ohne Tisch), menue (Hauptmenü), zeit (Streifen: oberer linker Ausschnitt nach 0/20/60/180 s, zeigt das langsame Atmen),
# uebergang (Flip Tag → Nacht in sechs Schritten).
# Vorher-Bilder: ALT_SHADER=<Pfad zu einer alten table_background.gdshader> setzen; die Bilder heißen dann
# optik_strahlen_vorher_<name>.png. Einzelnes Bild: SHOT=<name>.

var out_dir := ""
var prefix := "optik_strahlen_"
var alt_shader: Shader = null
var made := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	out_dir = ProjectSettings.globalize_path("res://").path_join("../docs/module").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var alt := OS.get_environment("ALT_SHADER")
	if alt != "":
		var code := FileAccess.get_file_as_string(alt)
		if code == "":
			push_error("ALT_SHADER nicht lesbar: " + alt)
			quit(1)
			return
		alt_shader = Shader.new()
		alt_shader.code = code
		prefix = "optik_strahlen_vorher_"
	var only := OS.get_environment("SHOT")
	var shots := ["tag", "daemmerung", "nacht", "hintergrund", "menue", "zeit", "uebergang"]
	for s in shots:
		if only != "" and only != s:
			continue
		await call("shot_" + s)
		made += 1
	print("RESULT: %d ok" % made)
	quit(0)


func _save(name: String, img: Image = null) -> void:
	if img == null:
		await process_frame
		await process_frame
		img = root.get_texture().get_image()
	var path := out_dir.path_join(prefix + name + ".png")
	img.save_png(path)
	print("Bild: " + path)


func _clear() -> void:
	for c in root.get_children():
		if c.name != "App":
			c.queue_free()
	await process_frame


func _wait(t: float) -> void:
	await create_timer(t).timeout


# Für Vorher-Bilder den alten Shader in alle Hintergründe unter node einsetzen
func _use_alt(node: Node) -> void:
	if alt_shader == null:
		return
	if node is TableBackground:
		var mat := (node as TableBackground).shader_material
		if mat != null:
			mat.shader = alt_shader
			var bg := node as TableBackground
			mat.set_shader_parameter("size", bg.size)
			mat.set_shader_parameter("center", bg.table_center)
			mat.set_shader_parameter("tageszeit", bg.tageszeit)
			mat.set_shader_parameter("motion", 1.0 if bg.motion else 0.0)
			bg.refresh()
	for c in node.get_children():
		_use_alt(c)


# Ausgangslage wie test_ui_table_shots.gd (Entwurf hand.png): 4 Spieler, Blau 9 auf der Ablage, neun Karten auf der Hand
func _sample_light() -> TableSamples:
	var s := TableSamples.create(4, 5, [0, 6, 5, 2])
	for k in ["hell_rot_7", "hell_rot_flip", "hell_gelb_3", "hell_gelb_plus1", "hell_gruen_aussetzen", "hell_blau_9", "hell_blau_richtungswechsel", "hell_wuenscher", "hell_wuenscher_plus2"]:
		s.give(0, k)
	s.set_top("hell_gelb_9")
	s.set_top("hell_blau_9")
	s.set_draw_top("hell_rot_4")
	s.turn = 0
	return s


func _table(s: TableSamples, night := -1.0) -> TableView:
	var table := TableView.new()
	root.add_child(table)
	var hand := DemoHand.new()
	table.set_hand(hand)
	table.apply_view(s.view_for(0))
	if night >= 0.0:
		table.set_night(night)
	_use_alt(table)
	return table


func shot_tag() -> void:
	await _clear()
	_table(_sample_light())
	await _wait(0.6)
	await _save("tag")


func shot_daemmerung() -> void:
	await _clear()
	_table(_sample_light(), 0.5)
	await _wait(0.6)
	await _save("daemmerung")


func shot_nacht() -> void:
	await _clear()
	var s := _sample_light()
	s.flip()
	_table(s)
	await _wait(0.6)
	await _save("nacht")


func shot_hintergrund() -> void:
	await _clear()
	var bg := TableBackground.new()
	root.add_child(bg)
	bg.table_center = Vector2(800, 320)
	_use_alt(bg)
	await _wait(0.3)
	await _save("hintergrund")


func shot_menue() -> void:
	await _clear()
	var nav := ScreenNav.new()
	root.add_child(nav)
	_use_alt(nav)
	await _wait(0.8)
	await _save("menue")


# Flip-Übergang: Hintergrund allein bei tageszeit 0; 0,2; 0,4; 0,6; 0,8; 1 (je auf ein Drittel verkleinert, 3×2)
func shot_uebergang() -> void:
	await _clear()
	var bg := TableBackground.new()
	root.add_child(bg)
	bg.table_center = Vector2(800, 320)
	_use_alt(bg)
	var strip := Image.create(1599, 480, false, Image.FORMAT_RGBA8)
	for i in 6:
		bg.tageszeit = i * 0.2
		_use_alt(bg)
		await process_frame
		await process_frame
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(533, 240, Image.INTERPOLATE_LANCZOS)
		strip.blit_rect(img, Rect2i(0, 0, 533, 240), Vector2i((i % 3) * 533, (i / 3) * 240))
	await _save("uebergang", strip)


# Zeitstreifen: derselbe Ausschnitt (Sonne und Strahlen, 800×360 oben links) nach 0, 20, 60 und 180 s Laufzeit des Shaders.
# TIME lässt sich nicht setzen; der Streifen entsteht daher aus vier Hintergründen, deren Zeit über eine Kopie des Shaders mit
# fester Zeit vorgegeben wird (TIME → Uniform).
func shot_zeit() -> void:
	await _clear()
	var src := alt_shader.code if alt_shader != null else (load(TableBackground.SHADER) as Shader).code
	var code := src.replace("uniform float motion", "uniform float fake_time = 0.0;\nuniform float motion").replace("TIME", "fake_time")
	var sh := Shader.new()
	sh.code = code
	var bg := TableBackground.new()
	root.add_child(bg)
	bg.table_center = Vector2(800, 320)
	var mat := bg.shader_material
	mat.shader = sh
	mat.set_shader_parameter("size", Vector2(1600, 720))
	mat.set_shader_parameter("center", Vector2(800, 320))
	mat.set_shader_parameter("tageszeit", 0.0)
	mat.set_shader_parameter("motion", 1.0)
	var strip := Image.create(1600, 720, false, Image.FORMAT_RGBA8)
	var times := [0.0, 20.0, 60.0, 180.0]
	for i in times.size():
		mat.set_shader_parameter("fake_time", times[i])
		bg.refresh()
		await process_frame
		await process_frame
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		var part := img.get_region(Rect2i(0, 0, 800, 360))
		strip.blit_rect(part, Rect2i(0, 0, 800, 360), Vector2i((i % 2) * 800, (i / 2) * 360))
	await _save("zeit", strip)
