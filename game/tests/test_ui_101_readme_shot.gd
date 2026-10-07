extends SceneTree
# Bild für das README (mit Renderer; „_shot“: vom Testlauf ausgenommen): laufende Partie bei Tag, die Computergegner haben schon
# gelegt, du bist dran. docs/module/optik_101_tag_spiel.png
#   godot_run.ps1 -Script res://tests/test_ui_101_readme_shot.gd

var nav: ScreenNav
var ts: TableScreen


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	nav = ScreenNav.new()
	root.add_child(nav)
	await process_frame
	var cfg := RuleConfig.preset("familie")
	var players := [{"name": "Du", "kind": "human"}, {"name": "Mimi", "kind": "bot"}, {"name": "Socke", "kind": "bot"}, {"name": "Karlo", "kind": "bot"}]
	var src := GameStarter.local("solo", cfg, players, 1)
	ts = TableScreen.create(src, func() -> void: src.start())
	nav.push(ts, false)
	var t0 := Time.get_ticks_msec()
	var deadline := t0 + 60000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var v := ts.view
		var pile := (v.get("discard_log", []) as Array).size()
		if Time.get_ticks_msec() - t0 > 4000 and int(v.get("turn", -1)) == 0 and not ts.table.director.is_busy() \
				and str(v.get("phase", "")) == "turn" and (pile >= 4 or Time.get_ticks_msec() - t0 > 20000):
			break
	await create_timer(1.5).timeout
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://").path_join("../docs/module/optik_101_tag_spiel.png").simplify_path()
	img.save_png(path)
	print("Seite %s, Ablage %d, Bild: %s" % [str(ts.view.get("side", "")), (ts.view.get("discard_log", []) as Array).size(), path])
	print("RESULT: 1 ok")
	quit(0)
