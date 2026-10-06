extends SceneTree
# Kontrollbilder 0.1.4 (mit Renderer, nicht headless; „_shot“: vom Testlauf ausgenommen):
#   godot_run.ps1 -Script res://tests/test_ui_014_shot.gd -Resolution 1600x720
# docs/module/optik_014_<name>.png: dran_tag (Gegner vor der Sonne am Zug, mit Denkblase), ich_nacht (eigener Zug nachts:
# Kranz an Name und Hand, eigene Kartenzahl), rundenende (sanfte Strahlen statt Keilen).

var out_dir := ""


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	out_dir = ProjectSettings.globalize_path("res://").path_join("../docs/module").simplify_path()
	await _shot_turn(false, 1, "dran_tag")
	await _shot_turn(true, 0, "ich_nacht")
	await _shot_round_end()
	print("RESULT: 3 ok")
	quit(0)


func _table(night: bool, turn: int) -> TableView:
	var s := TableSamples.create(3, 5, [9, 6, 5])
	if night:
		s.side = "dunkel"
	var v := s.view_for(0)
	v["turn"] = turn
	var t := TableView.new()
	root.add_child(t)
	var hv := HandView.new()
	t.set_hand(hv)
	await process_frame
	var sz := t.size
	hv.layout_rect = Rect2(270.0, sz.y - 220.0, maxf(sz.x - 540.0, 400.0), 220.0)
	t.apply_view(v)
	t.director.flush()
	return t


func _shot_turn(night: bool, turn: int, name: String) -> void:
	var t := await _table(night, turn)
	if turn != 0:
		t.seat_node(turn)._think = 6.0
	else:
		t.me_badge._think = 6.0
	for i in 40:
		await process_frame
	await _save(name)
	t.queue_free()
	await process_frame


func _shot_round_end() -> void:
	var s := TableSamples.create(3, 4, [0, 3, 2])
	var v := s.view_for(0)
	v["phase"] = "round_over"
	v["ranking"] = [0]
	var t := TableView.new()
	root.add_child(t)
	await process_frame
	t.apply_view(v)
	for i in 30:
		await process_frame
	await _save("rundenende")
	t.queue_free()
	await process_frame


func _save(name: String) -> void:
	await process_frame
	var img := root.get_texture().get_image()
	var path := out_dir.path_join("optik_014_" + name + ".png")
	img.save_png(path)
	print("Bild: " + path)
