extends SceneTree
# Kontrollbilder Überlagerungen im Spiel bei Tag und Nacht (Beta 1.1.3) mit echtem Renderer (wegen „_shot“ nicht im Bau):
#   tools/godot_run.ps1 -Script res://tests/test_ui_overlay_night_shot.gd -Resolution 1600x720 -EnvPairs "SHOT_DIR=…"
# → overlay_<einstellungen|regeln|bedienung|menue|kartenhilfe|rundenende|rueckfrage>_<tag|nacht>.png; dazu overlay_flip.png (Regeln offen, Tisch wechselt auf Tag).

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
	for tm in ["tag", "nacht"]:
		var night: bool = tm == "nacht"
		var s := TableSamples.create(4, 9, [])
		if night:
			s.side = "dunkel"
			s.set_top("dunkel_tuerkis_7")
			s.color = "tuerkis"
		var t := TableView.new()
		root.add_child(t)
		t.set_hand(HandView.new())
		t.apply_view(s.view_for(0))
		t.night = 1.0 if night else 0.0
		t.director.flush()
		await _frames(20)
		var o := IngameSettings.open(root, true)
		await _frames(20)
		await _save("overlay_einstellungen_" + tm)
		o.close()
		var h := IngameHelp.open(root, {}, night, true, "regeln")
		await _frames(20)
		await _save("overlay_regeln_" + tm)
		h.show_tab("bedienung")
		await _frames(5)
		await _save("overlay_bedienung_" + tm)
		if night:
			h.show_tab("regeln")
			t.night = 0.0                      # Flip, während die Hilfe offen ist
			await _frames(20)
			await _save("overlay_flip")
		h.close()
		if night:
			t.night = 1.0                      # nach dem Flip-Bild wieder Nacht
			await _frames(5)
		var m := IngameMenu.open(root, Vector2(130, 20))
		await _frames(20)
		await _save("overlay_menue_" + tm)
		m.close()
		# Kartenhilfe, Rundenende und Rückfrage folgen Tag/Nacht ebenfalls (1.1.3)
		t.help_popup.show_help("dunkel_tuerkis_7" if night else "hell_rot_7", "Testkarte", "Zahlenkarte ohne Sonderwirkung.\n\nPasst auf die Farbe und auf jede 7.")
		await _frames(20)
		await _save("overlay_kartenhilfe_" + tm)
		t.help_popup.close()
		t.round_end.show_result([{"seat": 0, "name": "Du", "count": 3}, {"seat": 1, "name": "Mimi", "count": 0}, {"seat": 2, "name": "Kater Karlo", "count": 5}], [1, 0, 2], [0, 0, 0], 0)
		await _frames(40)
		await _save("overlay_rundenende_" + tm)
		t.round_end.hide_view()
		var c := ConfirmBox.ask(root, "Partie verlassen?", "Der Spielstand geht verloren.", "Verlassen", "Weiterspielen")
		await _frames(20)
		await _save("overlay_rueckfrage_" + tm)
		c.queue_free()
		t.queue_free()
		await _frames(2)
	print("RESULT: %d Bilder" % shots)
	await CleanExit.finish(self, 0)


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _save(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	shots += 1
