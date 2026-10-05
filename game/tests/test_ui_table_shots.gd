extends SceneTree
# Kontrollbilder Modul F1b (mit Renderer, nicht headless):
#   godot_run.ps1 -Script res://tests/test_ui_table_shots.gd -Resolution 1600x720 -EnvPairs 'SHOT=flip'
# Ohne SHOT entstehen alle Bilder in docs/module/F1b_<name>.png: tisch_hell, tisch_dunkel, flip, farbwahl, sichtschutz,
# 8_spieler, rundenende, qr, dazu farbrad, effekte (Zusammenstellung einzelner Effekte), hilfe, grossansicht.

var out_dir := ""
var made := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	out_dir = ProjectSettings.globalize_path("res://").path_join("../docs/module").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var only := OS.get_environment("SHOT")
	var shots := ["tisch_hell", "tisch_dunkel", "flip", "farbwahl", "sichtschutz", "8_spieler", "rundenende", "qr", "effekte", "hilfe", "grossansicht"]
	if only != "" and not shots.has(only):
		shots = [only]
	for s in shots:
		if only != "" and only != s:
			continue
		await call("shot_" + s)
		made += 1
	print("RESULT: %d ok" % made)
	quit(0)


func _save(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var path := out_dir.path_join("F1b_%s.png" % name)
	img.save_png(path)
	print("Bild: " + path)


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


# Gemeinsame Ausgangslage wie im Entwurf: 4 Spieler, Blau 9 auf der Ablage, neun Karten auf der Hand mit Wünscher
func _sample_light() -> TableSamples:
	var s := TableSamples.create(4, 5, [0, 6, 5, 2])
	for k in ["hell_rot_7", "hell_rot_flip", "hell_gelb_3", "hell_gelb_plus1", "hell_gruen_aussetzen", "hell_blau_9", "hell_blau_richtungswechsel", "hell_wuenscher", "hell_wuenscher_plus2"]:
		s.give(0, k)
	s.set_top("hell_gelb_9")
	s.set_top("hell_blau_9")
	s.set_draw_top("hell_rot_4")
	s.turn = 0
	return s


func shot_tisch_hell() -> void:
	await _clear()
	var s := _sample_light()
	var t := _table(s)
	await _wait(0.6)
	await _save("tisch_hell")


func shot_tisch_dunkel() -> void:
	await _clear()
	var s := _sample_light()
	s.flip()
	s.turn = 2
	s.mau[3] = true
	var mia: Array = s.hands[3]
	while mia.size() > 1:
		s.deck.append(mia.pop_back())
	s.catch_targets = [3]
	s.pending = 5
	var t := _table(s)
	await _wait(0.6)
	await _save("tisch_dunkel")


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
	await _save("flip")


func shot_farbwahl() -> void:
	await _clear()
	var s := _sample_light()
	var t := _table(s)
	var hand: DemoHand = t.hand
	var joker := s.find_any(0, "hell_wuenscher")
	hand.dragged = joker
	hand.dragged_pos = t.discard_position() + Vector2(70, -70)
	hand.selected = joker
	hand.apply_view(s.view_for(0))
	t.open_color_fields()
	await _wait(0.4)
	t.wish_picker.hover(t.wish_picker.to_global(t.wish_picker.field_center(1)))
	await _wait(0.2)
	await _save("farbwahl")
	# Farbrad (Rückfall) als zweites Bild
	hand.dragged = -1
	hand.selected = -1
	hand.apply_view(s.view_for(0))
	t.wish_picker.close()
	t.open_color_wheel()
	await _wait(0.4)
	t.wish_picker.hover(t.wish_picker.to_global(t.wish_picker.wheel_center + Vector2(120, 90)))
	await _wait(0.1)
	await _save("farbrad")


func shot_sichtschutz() -> void:
	await _clear()
	var s := _sample_light()
	var t := _table(s)
	t.handover.show_for("Lena", 0, 1, 4, s.discard.size(), s.deck.size(), "hell")
	await _wait(0.75)
	t.handover.set("_holding", true)
	await _wait(0.2)
	t.handover.set("_holding", false)
	t.handover.set("_hold", 0.25)
	await _save("sichtschutz")


func shot_8_spieler() -> void:
	await _clear()
	var s := TableSamples.create(8, 3, [7, 6, 9, 1, 4, 12, 2, 5])
	s.flip()
	s.turn = 4
	s.mau[3] = true
	s.dir = -1
	var t := _table(s, 0)
	await _wait(0.6)
	await _save("8_spieler")


func shot_rundenende() -> void:
	await _clear()
	var s := _sample_light()
	s.scoring = "points500"
	s.scores = [180, 95, 240, 60]
	var t := _table(s)
	await _wait(0.3)
	var hand0: Array = s.hands[0]
	while hand0.size() > 0:
		s.deck.append(hand0.pop_back())
	s.give(0, "hell_blau_4")
	var ev := s.play(0, s.find_any(0, "hell_blau_4"))
	var r := s.finish_round(0)
	r[0]["ranking"] = [{"seat": 0, "points": 142}, {"seat": 3, "points": 0}, {"seat": 2, "points": 0}, {"seat": 1, "points": 0}]
	s.scores = [322, 95, 240, 60]
	r[0]["scores"] = s.scores.duplicate()
	ev.append_array(r)
	t.handle_state(ev, s.view_for(0))
	await _wait(1.5)
	await _save("rundenende")


func shot_qr() -> void:
	await _clear()
	var bg := TableBackground.new()
	root.add_child(bg)
	bg.tageszeit = 1.0
	var url := "http://192.168.178.23:24690/"
	var qr := QrCode.encode(url)
	var panel := PanelContainer.new()
	panel.theme = UiTheme.get_theme()
	root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var title := UiTheme.label("Mitspielen im Browser", UiFonts.title(800, false, 50.0, 48.0), 34, UiPalette.INK, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(title)
	var tex := TextureRect.new()
	tex.texture = qr.to_texture(10, 4, UiPalette.INK, Color.WHITE)
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.custom_minimum_size = Vector2(390, 390)
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	col.add_child(tex)
	col.add_child(UiTheme.label(url, UiFonts.text(800, 90.0), 26, UiPalette.INK, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiTheme.label("Version %d · Maske %d · Fehlerkorrektur M" % [qr.version, qr.mask], UiFonts.text(600, 90.0), 17, UiPalette.MUTED_DAY, HORIZONTAL_ALIGNMENT_CENTER))
	await process_frame
	panel.position = (Vector2(1600, 720) - panel.size) * 0.5
	await _wait(0.2)
	await _save("qr")


# Einzelne Effekte nebeneinander: Stempel, Zzz, Mau-Blase, Erwischt, Komet, Farbwelle
func shot_effekte() -> void:
	await _clear()
	var s := _sample_light()
	s.flip()
	var t := _table(s)
	await _wait(0.3)
	t.fx.stamp(Vector2(300, 420), "+5", Color("#FF7FCF"), 64, 3.0)
	var lena := t.seat_node(1)
	lena.sleep_for(3.0)
	t.fx.zzz(lena.position + Vector2(18, -30), 2.0)
	t.fx.bubble(t.seat_node(3).position + Vector2(0, -78), "Mau!", 3.0)
	t.fx.stamp(t.seat_node(2).position + Vector2(0, 60), "Erwischt!", UiPalette.ALERT, 46, 3.0, -0.12)
	t.fx.ring_wave(t.discard_position(), UiPalette.glow("lila"), 60.0, 900.0, 2.4, 14.0, 0.62)
	t.call("_edge_pulse")
	await _wait(0.42)
	await _save("effekte")


# Nur zur Durchsicht (nicht in der Standardliste): Demo-Ablauf, je Schritt ein Bild mitten im Effekt nach %TEMP%/mmf_ablauf_<n>.png
func shot_ablauf() -> void:
	await _clear()
	var sc := TableDemo.scenario()
	var s: TableSamples = sc["sample"]
	var steps: Array = sc["steps"]
	var t := _table(s)
	await _wait(0.5)
	var at := {2: 0.45, 3: 1.2, 4: 0.75, 5: 1.0, 6: 0.75, 7: 0.3, 8: 1.0, 9: 1.0, 10: 1.6, 13: 0.8, 17: 1.3}
	for i in steps.size():
		var ev: Array = (steps[i] as Callable).call()
		t.handle_state(s.events_for(0, ev), s.view_for(0))
		var n := i + 1
		if at.has(n):
			await _wait(float(at[n]))
			await process_frame
			root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("mmf_ablauf_%02d.png" % n))
		while t.director.is_busy():
			await process_frame
		await _wait(0.2)


func shot_hilfe() -> void:
	await _clear()
	var s := _sample_light()
	var t := _table(s)
	t.show_help("hell_wuenscher_plus2", "Wünscher +2",
		"Der Nächste zieht [b]2 Karten[/b] und setzt aus. Du wünschst dir dabei eine Farbe.\n\n" +
		"Erlaubt nur, wenn du [b]keine Karte der aktuellen Farbe[/b] hast. Wer zweifelt, darf anzweifeln: " +
		"Hast du geblufft, ziehst du selbst 2 – sonst zieht der Zweifler 4.\n\n[i]Hausregel aktiv: Ziehkarten weitergeben.[/i]")
	await _wait(0.5)
	await _save("hilfe")


func shot_grossansicht() -> void:
	await _clear()
	var s := _sample_light()
	var t := _table(s)
	var lena := t.seat_node(1)
	t.backs_viewer.show_backs(lena.player_name(), lena.keys)
	await _wait(0.5)
	await _save("grossansicht")
