extends SceneTree
# Kontrollbilder Partie-Ende Tag (Konfetti) und Nacht (Sternenschauer), mit Renderer („_shot“: vom Testlauf ausgenommen):
#   godot_run.ps1 -Script res://tests/test_ui_celebrate_shot.gd -Resolution 1600x720
# docs/module/optik_134_partieende_tag.png und _nacht.png

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("../docs/module").simplify_path()
	for night in [false, true]:
		var s := TableSamples.create(3, 4, [0, 3, 2])
		if night:
			s.side = "dunkel"
		var v := s.view_for(0)
		v["phase"] = "game_over"
		v["ranking"] = [0]
		var t := TableView.new()
		root.add_child(t)
		await process_frame
		t.apply_view(v)
		t.fx_top.night = 1.0 if night else 0.0
		t.play_event({"e": "game_over", "ranking": [0]}, 1.0)
		for i in 55:
			await process_frame
		await process_frame
		var path := dir.path_join("optik_134_partieende_%s.png" % ("nacht" if night else "tag"))
		root.get_texture().get_image().save_png(path)
		print("Bild: " + path)
		t.queue_free()
		await process_frame
	print("RESULT: 2 ok")
	quit(0)
