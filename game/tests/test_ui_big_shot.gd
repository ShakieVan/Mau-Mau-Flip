extends SceneTree
# Kontrollbilder großer Modus (Beta 1.1.1) mit echtem Renderer (wegen „_shot“ nicht in tools/build.ps1):
#   tools/godot_run.ps1 -Script res://tests/test_ui_big_shot.gd -Resolution 1600x720 -EnvPairs "SHOT_DIR=…"
# Tag/Nacht × 3/8 Spieler × Schrift normal/gross/sehr_gross → gross_<tag|nacht>_<n>_<stufe>.png. Optional STUFE=…, SPIELER=…,
# ZEIT=tag|nacht. Dazu gross_mau (Mau-Blase an einer Listenzeile) und gross_normal (zurückgeschaltet) bei normaler Schrift.

const CleanExit := preload("res://tests/clean_exit.gd")

var out_dir := ""
var shots := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://")
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1600, 720)
	var levels: Array = ["normal", "gross", "sehr_gross"]
	if OS.get_environment("STUFE") != "":
		levels = [OS.get_environment("STUFE")]
	var counts: Array = [3, 8]
	if OS.get_environment("SPIELER") != "":
		counts = [int(OS.get_environment("SPIELER"))]
	var times: Array = ["tag", "nacht"]
	if OS.get_environment("ZEIT") != "":
		times = [OS.get_environment("ZEIT")]
	for lvl in levels:
		UiFonts.set_level(str(lvl), root)
		for n in counts:
			for tm in times:
				var t := await _table(int(n), tm == "nacht")
				await _save("gross_%s_%d_%s" % [tm, n, lvl])
				if str(lvl) == "normal" and int(n) == 8 and tm == "tag" and OS.get_environment("STUFE") == "":
					t.show_mau(3, false, "")
					await _frames(30)
					await _save("gross_mau")
					t.set_big(false)
					(t.hand as HandView).layout_rect = t.hand_rect(t.size)   # wie TableScreen bei big_changed
					await _frames(10)
					await _save("gross_normal")
				t.queue_free()
				await _frames(2)
	UiFonts.set_level("normal", root)
	print("RESULT: %d Bilder" % shots)
	await CleanExit.finish(self, 0)


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _table(n: int, night: bool) -> TableView:
	var sizes: Array = []
	for i in n:
		sizes.append([9, 6, 5, 1, 12, 3, 7, 2][i % 8])
	var s := TableSamples.create(n, 5 + n, sizes)
	for k in ["hell_rot_7", "hell_gelb_plus1", "hell_wuenscher"]:
		s.give(0, k)
	if night:
		s.side = "dunkel"
	s.set_top("hell_blau_9" if not night else "dunkel_tuerkis_7")
	s.color = "blau" if not night else "tuerkis"
	s.turn = 0
	s.mau[3] = true
	s.pending = 5                 # Strafplakette „+5“ an der Ablage (1.1.3: über Ablage und Farbschild)
	var t := TableView.new()
	root.add_child(t)
	var hv := HandView.new()
	t.set_hand(hv)
	t.set_big(true)
	await process_frame
	hv.layout_rect = t.hand_rect(t.size)
	t.update_hand_target()
	t.apply_view(s.view_for(0))
	t.director.flush()
	await _frames(50)
	return t


func _save(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	shots += 1
