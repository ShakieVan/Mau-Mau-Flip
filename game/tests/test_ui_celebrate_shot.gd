extends SceneTree
# Kontrollbilder Partie-Ende Tag (Konfetti) und Nacht (Funkelsterne), mit Renderer („_shot“: vom Testlauf ausgenommen):
#   godot_run.ps1 -Script res://tests/test_ui_celebrate_shot.gd -Resolution 1600x720
# docs/module/optik_134_partieende_tag.png und _nacht.png, dazu nachts eine kurze Bildfolge der Funkelsterne (1.3.6):
# docs/module/optik_136_funkeln_03.png, _08, _14, _20 (0,3 / 0,8 / 1,4 / 2,0 s nach dem Start)

const SERIES := [1.0, 4.0]


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("../docs/module").simplify_path()
	var shots := 0
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
		var start := Time.get_ticks_msec()
		t.play_event({"e": "game_over", "ranking": [0]}, 1.0)
		if night:
			for at in SERIES:
				while Time.get_ticks_msec() - start < int(float(at) * 1000.0):
					await process_frame
				await RenderingServer.frame_post_draw
				var sp := dir.path_join("optik_136_funkeln_%02d.png" % int(round(float(at) * 10.0)))
				root.get_texture().get_image().save_png(sp)
				print("Bild: %s (%.2f s)" % [sp, (Time.get_ticks_msec() - start) / 1000.0])
				shots += 1
		else:
			for i in 55:
				await process_frame
			await process_frame
			var path := dir.path_join("optik_134_partieende_tag.png")
			root.get_texture().get_image().save_png(path)
			print("Bild: " + path)
			shots += 1
		t.queue_free()
		await process_frame
	print("RESULT: %d ok" % shots)
	quit(0)
