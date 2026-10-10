extends SceneTree
# Kontrollbilder Partie-Ende als Regen (1.4.2), Nacht (Funkelsterne) und Tag (Konfetti), mit Renderer („_shot“: vom Testlauf ausgenommen):
#   godot_run.ps1 -Script res://tests/test_ui_celebrate_shot.gd -Resolution 1600x720
# docs/module/optik_142_regen_nacht_05.png, _25, _45, _65, _85 und optik_142_regen_tag_05 ... (0,5 / 2,5 / 4,5 / 6,5 / 8,5 s nach dem Start)

const SERIES := [0.5, 2.5, 4.5, 6.5, 8.5]   # 5 s voller Regen, danach Ausrieseln bis 10 s


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("../docs/module").simplify_path()
	var shots := 0
	for night in [true, false]:
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
		for at in SERIES:
			while Time.get_ticks_msec() - start < int(float(at) * 1000.0):
				await process_frame
			await RenderingServer.frame_post_draw
			var sp := dir.path_join("optik_142_regen_%s_%02d.png" % ["nacht" if night else "tag", int(round(float(at) * 10.0))])
			root.get_texture().get_image().save_png(sp)
			print("Bild: %s (%.2f s)" % [sp, (Time.get_ticks_msec() - start) / 1000.0])
			shots += 1
		t.queue_free()
		await process_frame
	print("RESULT: %d ok" % shots)
	quit(0)
