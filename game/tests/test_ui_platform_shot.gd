extends SceneTree
# Kontrollbilder der Richtungs-Plattform (DirectionRing, mit Renderer, nicht headless; vom Testlauf ausgenommen):
#   godot_run.ps1 -Script res://tests/test_ui_platform_shot.gd -Resolution 1600x720 [-EnvPairs 'SHOT=b_tag']
# Bilder in docs/module/optik_plattform_<variante>_<lage>.png: Varianten a (schlank) und b (breit, Standard), je Tag, Nacht
# und mitten im Richtungswechsel (b auch nachts: b_nachtwechsel); dazu Ausschnitte in doppelter Größe nach %TEMP%/mmf_plattform_<name>_zoom.png.
# Zusätzlich (nur mit SHOT): spieler3, spieler8 (Abstände zu den Gegnerplätzen), flip (Dämmerung), schmal (mit -Resolution 1280x720).

var out_dir := ""
var made := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	out_dir = ProjectSettings.globalize_path("res://").path_join("../docs/module").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var only := OS.get_environment("SHOT")
	var shots := ["a_tag", "a_nacht", "a_wechsel", "b_tag", "b_nacht", "b_wechsel", "b_nachtwechsel"]
	if only != "":
		shots = Array(only.split(","))
	for s in shots:
		var parts: PackedStringArray = str(s).split("_")
		if parts.size() == 2 and parts[0] in ["a", "b"]:
			await _shot(parts[0], parts[1])
		else:
			await call("shot_" + str(s))
		made += 1
	print("RESULT: %d ok" % made)
	quit(0)


func _save(name: String, zoom := true) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var path := out_dir.path_join("optik_plattform_%s.png" % name)
	img.save_png(path)
	print("Bild: " + path)
	if zoom:
		var crop := img.get_region(Rect2i(330, 110, 940, 470))
		crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_NEAREST)
		var zp := OS.get_environment("TEMP").path_join("mmf_plattform_%s_zoom.png" % name)
		crop.save_png(zp)
		print("Ausschnitt: " + zp)


func _clear() -> void:
	for c in root.get_children():
		if c.name != "App":
			c.queue_free()
	await process_frame


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _table(sample: TableSamples, seat := 0) -> TableView:
	var table := TableView.new()
	root.add_child(table)
	var hand := DemoHand.new()
	table.set_hand(hand)
	table.apply_view(sample.view_for(seat))
	return table


func _ring(t: TableView) -> DirectionRing:
	return t.get("_ring") as DirectionRing


# Ausgangslage wie test_ui_table_shots.gd: 4 Spieler, Blau 9 auf der Ablage, neun Karten auf der Hand
func _sample_light() -> TableSamples:
	var s := TableSamples.create(4, 5, [0, 6, 5, 2])
	for k in ["hell_rot_7", "hell_rot_flip", "hell_gelb_3", "hell_gelb_plus1", "hell_gruen_aussetzen", "hell_blau_9", "hell_blau_richtungswechsel", "hell_wuenscher", "hell_wuenscher_plus2"]:
		s.give(0, k)
	s.set_top("hell_gelb_9")
	s.set_top("hell_blau_9")
	s.set_draw_top("hell_rot_4")
	s.turn = 0
	return s


func _shot(variant: String, lage: String) -> void:
	await _clear()
	var s := _sample_light()
	if lage.begins_with("nacht"):
		s.flip()
		s.turn = 2
	var t := _table(s)
	var ring := _ring(t)
	ring.style = DirectionRing.Style.SLIM if variant == "a" else DirectionRing.Style.WIDE
	await _wait(0.5)
	if lage.ends_with("wechsel"):
		ring.reverse_to(-1, 1.0)
		await _wait(0.57)
	await _save("%s_%s" % [variant, lage])


func shot_spieler3() -> void:
	await _clear()
	var s := TableSamples.create(3, 5, [0, 6, 5])
	s.set_top("hell_blau_9")
	var t := _table(s)
	await _wait(0.5)
	await _save("spieler3", false)


func shot_spieler8() -> void:
	await _clear()
	var s := TableSamples.create(8, 3, [7, 6, 9, 1, 4, 12, 2, 5])
	s.flip()
	s.turn = 4
	s.dir = -1
	var t := _table(s, 0)
	await _wait(0.5)
	await _save("spieler8", false)


func shot_flip() -> void:
	await _clear()
	var s := _sample_light()
	s.give(0, "hell_blau_flip")
	var t := _table(s)
	await _wait(0.4)
	var ev := s.play(0, s.find_any(0, "hell_blau_flip"))
	ev.append_array(s.flip())
	s.advance()
	t.handle_state(s.events_for(0, ev), s.view_for(0))
	await _wait(1.07)
	await _save("flip", false)


# Mit -Resolution 1280x720 starten (16:9): Loch bleibt weit genug für Stapel und Farbring
func shot_schmal() -> void:
	await _clear()
	var t := _table(_sample_light())
	await _wait(0.5)
	await _save("schmal", false)
