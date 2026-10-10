extends SceneTree
# Kontrollbild Beta 1.4.5, Häufigkeit der Sprüche (mit Renderer; „_shot“: vom Testlauf ausgenommen):
#   tools/godot_run.ps1 -Script res://tests/test_fun_freq_shot.gd -Resolution 1600x720 -EnvPairs "SHOT_DIR=…"
# Einstellungsseite, Zeilen „Sprüche“ und „Häufigkeit“ in Schrift normal und sehr groß; dazu mit Sprüchen „Aus“ (Häufigkeit verschwindet).
# Schrift und Einstellungen werden danach wiederhergestellt. Prüft: Zeile nur sichtbar, solange Sprüche nicht „Aus“ sind; Knöpfe nicht gestreckt.

const CleanExit := preload("res://tests/clean_exit.gd")

var out_dir := ""
var shots := 0
var failed := 0


func _initialize() -> void:
	call_deferred("run")


func check(cond: bool, text: String) -> void:
	if not cond:
		failed += 1
		print("FAIL: ", text)


func run() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://")
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1600, 720)
	var app := UiApp.app()
	var keep: Dictionary = {}
	for k in [FunTexts.SETTING, FunTexts.FREQ_SETTING]:
		keep[k] = [app.settings.has_value(k), app.settings.get_value(k)]
	app.settings.set_value(FunTexts.SETTING, "frech")
	app.settings.set_value(FunTexts.FREQ_SETTING, "oft")
	for level in ["normal", "sehr_gross"]:
		UiFonts.set_level(level, root)
		var nav := ScreenNav.new()
		nav.autostart = false
		root.add_child(nav)
		await _frames(10)
		UiFonts.set_level(level, root)
		var screen := SettingsScreen.new()
		nav.push(screen, false)
		await _frames(40)
		var row := screen.find_child("SpruecheOftZeile", true, false) as Control
		var spr := screen.find_child("Sprueche", true, false) as Control
		var oft := screen.find_child("SpruecheOft", true, false) as Control
		check(row != null and spr != null and oft != null, "Zeilen vorhanden (%s)" % level)
		if row != null:
			check(row.visible, "Häufigkeit sichtbar bei Sprüchen an (%s)" % level)
			check(oft.size.y < 120.0 and spr.size.y < 120.0, "Auswahlknöpfe nicht gestreckt (%s: %s / %s)" % [level, str(spr.size.y), str(oft.size.y)])
			for s in screen.find_children("*", "ScrollContainer", true, false):
				(s as ScrollContainer).ensure_control_visible(row)
			await _frames(20)
			await _save("haeufigkeit_%s" % level)
			# Sprüche aus: Zeile verschwindet
			var aus := spr.get_child(0) as Button
			aus.pressed.emit()
			await _frames(5)
			check(not row.visible, "Häufigkeit weg bei Sprüchen aus (%s)" % level)
			await _save("haeufigkeit_%s_aus" % level)
			(spr.get_child(2) as Button).pressed.emit()
			await _frames(3)
			check(row.visible, "Häufigkeit wieder da (%s)" % level)
			(oft.get_child(3) as Button).pressed.emit()
			await _frames(3)
			check(str(app.settings.get_value(FunTexts.FREQ_SETTING)) == "immer", "Immer gespeichert")
		nav.queue_free()
		await _frames(3)
	UiFonts.set_level("normal", root)
	for k in keep:
		if keep[k][0]:
			app.settings.set_value(k, keep[k][1])
		else:
			app.settings.reset(k)
	print("RESULT: %d Bilder, %d failed" % [shots, failed])
	await CleanExit.finish(self, 1 if failed > 0 else 0)


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _save(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	shots += 1
