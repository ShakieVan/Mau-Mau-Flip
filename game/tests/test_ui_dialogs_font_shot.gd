extends SceneTree
# Beta 1.1.1, Einstellung „Schriftgröße“ in Rundenende, Farbrad, Weitergeben, Kartenhilfe und Rückseiten: Kontrollbilder in
# allen drei Stufen plus eine Übersicht (schrift_dialoge_uebersicht.png). Prüft grob, dass die Rundenende-Karte und die
# Kartenhilfe im Bild bleiben. Mit echtem Renderer (wegen „_shot“ nicht in tools/build.ps1):
#   tools/godot_run.ps1 -Script res://tests/test_ui_dialogs_font_shot.gd -Resolution 1600x720 -EnvPairs "SHOT_DIR=…"

const CleanExit := preload("res://tests/clean_exit.gd")

var out_dir := ""
var problems: Array[String] = []
var tiles: Array[Image] = []


func _initialize() -> void:
	call_deferred("run")


func wait(t: float) -> void:
	await create_timer(t).timeout


func run() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://")
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1600, 720)
	for lvl in ["normal", "gross", "sehr_gross"]:
		UiFonts.set_level(lvl)
		await views(lvl)
	UiFonts.set_level("normal")
	var tw := 480
	var th := 216
	var sheet := Image.create(tw * 5, th * 3, false, Image.FORMAT_RGBA8)
	for i in tiles.size():
		var t := tiles[i]
		t.resize(tw, th)
		sheet.blit_rect(t, Rect2i(0, 0, tw, th), Vector2i((i % 5) * tw, (i / 5) * th))
	sheet.save_png(out_dir.path_join("schrift_dialoge_uebersicht.png"))
	for p in problems:
		print("UEBERLAUF: " + p)
	print("RESULT: %d Bilder, %d Überläufe" % [tiles.size(), problems.size()])
	await CleanExit.finish(self, 0)


func views(lvl: String) -> void:
	# Rundenende mit 8 Spielern und Punkten
	var players: Array = []
	var names := ["Maximiliane", "Ben", "Lena", "Konstantin", "Ida", "Robo Rudi", "Sophie-Marie", "Tom"]
	for i in 8:
		players.append({"seat": i, "name": names[i], "count": i})
	var re := RoundEndView.new()
	root.add_child(re)
	re.show_result(players, [{"seat": 2, "points": 112}, {"seat": 0, "points": 0}], [10, 0, 212, 5, 0, 18, 7, 99], 2, 3, true, true)
	await wait(0.6)
	if re._panel_rect.end.y > 720.0 or re._panel_rect.position.y < 0.0:
		problems.append("%s Rundenende: Karte ragt aus dem Bild" % lvl)
	await snap(lvl, "rundenende")
	re.queue_free()
	# Farbrad mit Frage
	var holder := Node2D.new()
	root.add_child(holder)
	var wp := WishPicker.new()
	holder.add_child(wp)
	wp.wheel_center = Vector2(800, 400)
	wp.open_wheel("dunkel", {"pink": 3, "tuerkis": 12, "orange": 0, "lila": 1}, "Welche Farbe ablegen?")
	await wait(0.5)
	await snap(lvl, "farbrad")
	holder.queue_free()
	# Weitergeben
	var ho := HandoverScreen.new()
	root.add_child(ho)
	ho.show_for("Sophie-Marie", 0, 3, 6, 23, 81)
	await wait(0.6)
	await snap(lvl, "weitergeben")
	ho.queue_free()
	# Kartenhilfe
	var hp := HelpPopup.new()
	root.add_child(hp)
	hp.show_help("hell_wuenscher_plus2", "Wünscher +2", "Passt auf jede Karte. Du wünschst dir eine Farbe, und der Nächste zieht [b]2 Karten[/b] und setzt aus. "
		+ "Mit der Hausregel „Ziehkarten stapeln“ kann er eine gleiche Karte drauflegen; dann wandert die Summe weiter. "
		+ "Als letzte Karte zählt sie wie jede andere – vergiss das „Mau!“ nicht.")
	await wait(0.6)
	var pr := Rect2(hp._panel.position, hp._panel.size)
	if pr.end.y > 722.0 or pr.end.x > 1602.0 or pr.position.y < -2.0:
		problems.append("%s Kartenhilfe: Fenster ragt aus dem Bild %s" % [lvl, str(pr)])
	await snap(lvl, "kartenhilfe")
	hp.queue_free()
	# Rückseiten
	var bv := BacksViewer.new()
	root.add_child(bv)
	bv.show_backs("Sophie-Marie", ["hell_rot_7", "hell_blau_9", "hell_gelb_3", "hell_wuenscher", "hell_gruen_flip"])
	await wait(0.6)
	await snap(lvl, "rueckseiten")
	bv.queue_free()
	await wait(0.2)


func snap(lvl: String, name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join("schrift_%s_%s.png" % [lvl, name]))
	tiles.append(img)
