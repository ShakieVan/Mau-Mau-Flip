extends SceneTree
# Kontrollbilder Beta 1.2.1 mit echtem Renderer (wegen „_shot“ nicht in tools/build.ps1):
#   tools/godot_run.ps1 -Script res://tests/test_ui_stats_shot.gd -Resolution 1600x720 -EnvPairs "SHOT_DIR=…"
# statistik_einstellungen (Abschnitt „Deine Statistik“ mit Beispielzahlen), statistik_rundenende_<tag|nacht> (kleiner Satz unter der
# Unterzeile), statistik_rand_<tag|nacht> (großer Modus: kräftige Ränder der Handkarten). App.stats und „grosser_modus“ werden
# danach wiederhergestellt. Prüft dabei: Zeilen im Abschnitt, Rand nur im großen Modus und nur in der Hand, Zurücksetzen per Rückfrage.

const CleanExit := preload("res://tests/clean_exit.gd")

var out_dir := ""
var shots := 0
var failed := 0


func _initialize() -> void:
	call_deferred("run")


func check(cond: bool, text: String) -> void:
	if not cond:
		failed += 1
		print("FAIL: ", text)


func run() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://")
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1600, 720)
	var app := UiApp.app()
	var stats: AppStats = app.stats
	var stats_backup := stats.data.duplicate()
	var big_set: bool = app.settings.has_value("grosser_modus")
	var big_backup: Variant = app.settings.get_value("grosser_modus")
	stats.data = {"partien": 14, "runden": 37, "runden_gewonnen": 12, "partien_gewonnen": 2, "mau_mau": 15, "erwischt_selbst": 4,
		"erwischt_worden": 3, "groesste_hand": 23, "gluecksspiel_max": 9, "kartentausch": 5, "flip": 11, "partien_weitergeben": 6}
	# Einstellungen
	var nav := ScreenNav.new()
	nav.autostart = false
	root.add_child(nav)
	await _frames(10)
	var screen := SettingsScreen.new()
	nav.push(screen, false)
	await _frames(40)
	var list := screen.find_child("StatistikZahlen", true, false)
	check(list != null and list.get_child_count() == AppStats.KEYS.size(), "Statistik-Zeilen")
	var reset_btn := screen.find_child("StatistikZuruecksetzen", true, false) as Button
	for s in screen.find_children("*", "ScrollContainer", true, false):
		(s as ScrollContainer).ensure_control_visible(reset_btn)
	await _frames(20)
	await _save("statistik_einstellungen")
	# Zurücksetzen: Rückfrage, „Behalten“ ändert nichts
	reset_btn.pressed.emit()
	await _frames(5)
	var box := screen.find_child("Rueckfrage", true, false) as ConfirmBox
	check(box != null, "Rückfrage erscheint")
	await _save("statistik_rueckfrage")
	if box != null:
		box.cancel()
	await _frames(3)
	check(stats.value("partien") == 14, "Behalten ändert nichts")
	nav.queue_free()
	await _frames(3)
	# Rundenende mit Satz (Tag, Nacht)
	for night in [false, true]:
		var v := RoundEndView.new()
		root.add_child(v)
		v.set_night(1.0 if night else 0.0)
		v.note = AppStats.round_note("runde", 12)
		var players := [{"seat": 0, "name": "Lena", "count": 0}, {"seat": 1, "name": "Du", "count": 3}, {"seat": 2, "name": "Opa", "count": 5}]
		v.show_result(players, [0, 2, 1], [1, 0, 0], 0, 3)
		await _frames(40)
		await _save("statistik_rundenende_%s" % ("nacht" if night else "tag"))
		v.queue_free()
		await _frames(2)
	# Großer Modus: kräftige Ränder der Handkarten
	for night in [false, true]:
		app.settings.set_value("grosser_modus", true)
		var t := await _table(night)
		var hand_cards := t.hand.find_children("*", "CardView", false, false)
		check(not hand_cards.is_empty() and (hand_cards[0] as CardView).has_strong_edge(), "Handkarten: kräftiger Rand im großen Modus")
		await _save("statistik_rand_%s" % ("nacht" if night else "tag"))
		app.settings.set_value("grosser_modus", false)
		await _frames(2)
		check(not (hand_cards[0] as CardView).has_strong_edge(), "Rand aus, wenn der große Modus aus ist")
		t.queue_free()
		await _frames(2)
	stats.data = stats_backup
	stats.save()
	if big_set:
		app.settings.set_value("grosser_modus", big_backup)
	else:
		app.settings.reset("grosser_modus")
	print("RESULT: %d Bilder, %d failed" % [shots, failed])
	await CleanExit.finish(self, 1 if failed > 0 else 0)


func _table(night: bool) -> TableView:
	var s := TableSamples.create(4, 9, [12, 6, 5, 3])
	if night:
		s.side = "dunkel"
	s.set_top("hell_blau_9" if not night else "dunkel_tuerkis_7")
	s.color = "blau" if not night else "tuerkis"
	s.turn = 0
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


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _save(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	shots += 1
