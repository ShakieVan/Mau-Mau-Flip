extends SceneTree
# Erwischt mit Strafe 1 (1.4.1): genau eine Karte fliegt (Strafereignis nur Stempel, „draw“ fliegt mit der echten Zahl). Mit Renderer
# („_shot“: vom Testlauf ausgenommen): godot_run.ps1 -Script res://tests/test_ui_catch_shot.gd -Resolution 1600x720
# Bild: docs/module/optik_141_erwischt.png


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("../docs/module").simplify_path()
	var s := TableSamples.create(3, 4, [3, 3, 3])
	var t := TableView.new()
	root.add_child(t)
	await process_frame
	t.apply_view(s.view_for(0))
	for i in 3:
		await process_frame
	var cards := 0
	var d1 := t.play_event({"e": "catch", "seat": 0, "target": 1}, 1.0)
	var d2 := t.play_event({"e": "penalty", "seat": 1, "count": 1, "reason": "mau"}, 1.0)
	var d3 := t.play_event({"e": "draw", "seat": 1, "count": 1, "reason": "mau", "cards": [1], "faces": [], "backs": []}, 1.0)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join("optik_141_erwischt.png"))
	var n := 0
	for c in t.fx.get_children():
		if c is CardView:
			n += 1
	print("fliegende Karten: %d (Dauern %.2f %.2f %.2f)" % [n, d1, d2, d3])
	print("RESULT: %s" % ("1 ok" if n == 1 else "FAIL"))
	quit()
