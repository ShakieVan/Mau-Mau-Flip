extends SceneTree
# Kontrollbild 0.1.4 (mit Renderer; „_shot“: vom Testlauf ausgenommen): Partiestart mit Austeilen, wenn du anfängst – der
# Schein hinter der eigenen Hand darf erst nach dem Austeilen erscheinen und nicht mit den hereinfliegenden Karten wandern.
#   godot_run.ps1 -Script res://tests/test_ui_014_deal_shot.gd -Resolution 1600x720
# docs/module/optik_014_austeilen.png: sechs Momente (0,4 s … nach dem Austeilen) als Bogen, NACHT=1 für die dunkle Seite.

const MOMENTS := [0.4, 0.9, 1.5, 2.2, 3.2]

var nav: ScreenNav
var ts: TableScreen


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	nav = ScreenNav.new()
	root.add_child(nav)
	await process_frame
	var cfg := RuleConfig.preset("familie")
	# Bei Startwert 1 beginnt Platz 1: dort sitzt du, damit der eigene Schein nach dem Austeilen erscheinen muss
	var players := [{"name": "Karlo", "kind": "bot"}, {"name": "Du", "kind": "human"}, {"name": "Mimi", "kind": "bot"}, {"name": "Socke", "kind": "bot"}]
	var src := GameStarter.local("solo", cfg, players, 1)
	ts = TableScreen.create(src, func() -> void: src.start())
	nav.push(ts, false)
	var shots: Array[Image] = []
	var t0 := Time.get_ticks_msec()
	for m in MOMENTS:
		while (Time.get_ticks_msec() - t0) / 1000.0 < float(m):
			await process_frame
		shots.append(root.get_texture().get_image())
	var deadline := Time.get_ticks_msec() + 15000
	while ts.table.director.is_busy() and Time.get_ticks_msec() < deadline:
		await process_frame
	await create_timer(0.8).timeout
	shots.append(root.get_texture().get_image())
	_save_sheet(shots)
	# Zurück-Knopf auf der Nachtseite (1.0.1): Ausschnitt oben links
	ts.table.night = 1.0
	for i in 20:
		await process_frame
	var night_img := root.get_texture().get_image()
	night_img.crop(480, 240)
	var np := ProjectSettings.globalize_path("res://").path_join("../docs/module/optik_101_zurueck_nacht.png").simplify_path()
	night_img.save_png(np)
	print("Bild: " + np)
	print("RESULT: 1 ok")
	quit(0)


func _save_sheet(shots: Array[Image]) -> void:
	var w := shots[0].get_width() / 2
	var h := shots[0].get_height() / 2
	var sheet := Image.create(w * 2, h * 3, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var img := shots[i]
		img.convert(Image.FORMAT_RGBA8)
		img.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % 2) * w, (i / 2) * h))
	var path := ProjectSettings.globalize_path("res://").path_join("../docs/module/optik_014_austeilen.png").simplify_path()
	sheet.save_png(path)
	print("Bild: " + path)
