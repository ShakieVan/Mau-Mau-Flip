extends SceneTree
# Kontrollbilder „Erwischt!“-Knopf (Nutzerbefund 08.10.2026, wegen „_shot“ nicht in tools/build.ps1):
#   tools/godot_run.ps1 -Script res://tests/test_ui_catch_shot.gd -Resolution 1600x720 -EnvPairs "SHOT_DIR=…"
# Offenes Erwischen-Fenster (catch an) mit Strafplakette, Farbschild, Schein und Denkblase am nächsten Spieler:
# erwischen_<normal|gross>_<tag|nacht>_<n>.png für 3 und 6 Spieler (2 und 5 Gegner).

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
	for big in [false, true]:
		for n in [3, 6]:
			for tm in ["tag", "nacht"]:
				var t := await _table(int(n), tm == "nacht", bool(big))
				await _save("erwischen_%s_%s_%d" % ["gross" if big else "normal", tm, n])
				t.queue_free()
				await _frames(2)
	print("RESULT: %d Bilder" % shots)
	await CleanExit.finish(self, 0)


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _table(n: int, night: bool, big: bool) -> TableView:
	var sizes: Array = []
	for i in n:
		sizes.append([9, 1, 5, 6, 12, 3][i % 6])
	var s := TableSamples.create(n, 5 + n, sizes)
	for k in ["hell_rot_7", "hell_gelb_plus1", "hell_wuenscher"]:
		s.give(0, k)
	if night:
		s.side = "dunkel"
	s.set_top("hell_blau_9" if not night else "dunkel_tuerkis_7")
	s.color = "blau" if not night else "tuerkis"
	s.turn = 2                    # der Nächste nach dem Vergesslichen (Platz 1) ist dran: Schein und Denkblase
	s.pending = 5
	s.catch_targets = [1]
	var t := TableView.new()
	root.add_child(t)
	var hv := HandView.new()
	t.set_hand(hv)
	t.set_big(big)
	await process_frame
	hv.layout_rect = t.hand_rect(t.size)
	t.update_hand_target()
	t.apply_view(s.view_for(0))
	t.director.flush()
	await create_timer(5.6).timeout     # Denkblase erscheint nach 5 s
	return t


func _save(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	shots += 1
