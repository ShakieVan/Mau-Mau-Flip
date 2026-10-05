extends SceneTree
# Kontrollbilder T2 (mit Renderer, nicht headless; tools/build.ps1 überspringt *_shot*):
#   godot_run.ps1 -Script res://tests/test_ui_mau_shots.gd -Resolution 1600x720 [-EnvPairs 'SHOT=varianten']
# docs/module/T2_mau_varianten.png  Bilderbogen: jede Variante zu drei Zeitpunkten, Tag und Nacht
# docs/module/T2_tisch_tag.png / T2_tisch_nacht.png  8 Spieler, mehrere Blasen gleichzeitig (Lage, Lesbarkeit)
# docs/module/T2_mau_mau.png  „Mau-Mau!“ beim Fertigwerden

const CleanExit := preload("res://tests/clean_exit.gd")

const ROWS := ["plopp", "ohren", "huepfen", "pfote", "wellen", "neon", "schlicht", "maumau"]
const TIMES := [0.14, 0.42, 1.0]
const TIMES_BIG := [0.2, 0.55, 1.1]
const CELL := Vector2(380, 220)
const HEAD := 46.0

var out_dir := ""
var made := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	out_dir = ProjectSettings.globalize_path("res://").path_join("../docs/module").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var only := OS.get_environment("SHOT")
	for s in ["varianten", "tisch_tag", "tisch_nacht", "mau_mau", "einstellungen"]:
		if only != "" and only != s:
			continue
		await call("shot_" + s)
		made += 1
	print("RESULT: %d ok" % made)
	await CleanExit.finish(self, 0)


func _save_root(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var path := out_dir.path_join("T2_%s.png" % name)
	img.save_png(path)
	print("Bild: " + path)


func _clear() -> void:
	for c in root.get_children():
		if c.name != "App":
			c.queue_free()
	await process_frame


class Cell:
	extends Node2D
	var night := false
	var title := ""
	var seat := 1
	var avatar := Vector2.ZERO

	func _draw() -> void:
		var bg := UiPalette.NIGHT if night else UiPalette.PAPER
		draw_rect(Rect2(Vector2.ZERO, Vector2(380, 220)), bg)
		draw_rect(Rect2(Vector2.ZERO, Vector2(380, 220)), Color(UiPalette.INK, 0.12) if not night else Color(UiPalette.PAPER, 0.1), false, 1.0)
		var f := UiFonts.text(700, 100.0)
		draw_string(f, Vector2(10, 20), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiPalette.ui_muted(1.0 if night else 0.0))
		draw_circle(avatar, 30.0, UiPalette.PAPER if night else UiPalette.INK)
		draw_circle(avatar, 27.0, UiPalette.avatar(seat))
		var fi := UiFonts.text(800, 100.0)
		var w := fi.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		draw_string(fi, avatar + Vector2(-w * 0.5, 8.6), "M", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UiPalette.INK)


func shot_varianten() -> void:
	await _clear()
	var vp := SubViewport.new()
	vp.size = Vector2i(int(CELL.x * 6), int(HEAD + CELL.y * ROWS.size()))
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color("#2A2438")
	bg.size = Vector2(vp.size)
	vp.add_child(bg)
	for col in 6:
		var l := Label.new()
		var t: float = TIMES[col % 3]
		l.text = "%s · %.2f s (Mau-Mau %.2f s)" % ["Tag" if col < 3 else "Nacht", t, float(TIMES_BIG[col % 3])]
		l.position = Vector2(col * CELL.x + 12.0, 12.0)
		l.add_theme_font_override("font", UiFonts.text(700, 100.0))
		l.add_theme_font_size_override("font_size", 17)
		l.add_theme_color_override("font_color", UiPalette.CREAM)
		vp.add_child(l)
	for row in ROWS.size():
		var variant: String = ROWS[row]
		for col in 6:
			var night := col >= 3
			var t: float = (TIMES_BIG if variant == "maumau" else TIMES)[col % 3]
			var cell := Cell.new()
			cell.night = night
			cell.seat = 1 + row % 7
			cell.title = variant + ("  (nur nachts)" if variant == "neon" and not night else "")
			cell.position = Vector2(col * CELL.x, HEAD + row * CELL.y)
			vp.add_child(cell)
			var fx := TableEffects.new()
			fx.night = 1.0 if night else 0.0
			cell.add_child(fx)
			var big := variant == "maumau"
			var probe := TableEffects.MauBubbleFx.new()
			probe.variant = variant
			var ext := probe.extent()
			probe.free()
			var ay := CELL.y - 40.0
			var center := Vector2(CELL.x * 0.5 - ext.get_center().x, ay - 30.0 - 30.0 - ext.end.y)
			cell.avatar = Vector2(center.x + 30.0 if big else CELL.x * 0.5, ay)
			var b := fx.mau_bubble(center, variant, {"speaker": cell.avatar - center, "night": fx.night, "seed": 7 + row, "accent": UiPalette.avatar(cell.seat)})
			b.auto = false
			b.set_age(t)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var path := out_dir.path_join("T2_mau_varianten.png")
	img.save_png(path)
	print("Bild: " + path)
	vp.queue_free()
	await process_frame


func _table(sample: TableSamples, seat := 0) -> TableView:
	var table := TableView.new()
	root.add_child(table)
	table.set_hand(DemoHand.new())
	table.apply_view(sample.view_for(seat))
	return table


func _eight(night: bool) -> TableView:
	var s := TableSamples.create(8, 3, [2, 6, 1, 4, 1, 7, 1, 5])
	if night:
		s.flip()
	s.turn = 0
	for p in [2, 4, 6]:
		s.mau[p] = true
	var t := _table(s, 0)
	return t


func _freeze(b: TableEffects.MauBubbleFx, age: float) -> void:
	b.auto = false
	b.set_age(age)


func shot_tisch_tag() -> void:
	await _clear()
	var t := _eight(false)
	await create_timer(0.5).timeout
	_freeze(t.show_mau(2, false, "ohren"), 0.7)
	_freeze(t.show_mau(4, false, "plopp"), 0.5)
	_freeze(t.show_mau(6, false, "huepfen"), 0.75)
	_freeze(t.show_mau(7, false, "wellen"), 0.35)
	_freeze(t.show_mau(0, false, "pfote"), 0.6)
	await create_timer(0.2).timeout
	await _save_root("tisch_tag")


func shot_tisch_nacht() -> void:
	await _clear()
	var t := _eight(true)
	await create_timer(0.5).timeout
	_freeze(t.show_mau(2, false, "neon"), 0.6)
	_freeze(t.show_mau(4, false, "ohren"), 0.65)
	_freeze(t.show_mau(6, false, "pfote"), 0.55)
	_freeze(t.show_mau(1, false, "plopp"), 0.3)
	_freeze(t.show_mau(0, false, "wellen"), 0.4)
	await create_timer(0.2).timeout
	await _save_root("tisch_nacht")


func shot_mau_mau() -> void:
	await _clear()
	var s := TableSamples.create(4, 5, [1, 6, 5, 2])
	s.set_top("hell_blau_9")
	s.turn = 0
	var hand0: Array = s.hands[0]
	while hand0.size() > 0:
		s.deck.append(hand0.pop_back())
	s.give(0, "hell_blau_4")
	var t := _table(s)
	t.mau_variant_override = ""
	await create_timer(0.4).timeout
	var ev := s.play(0, s.find_any(0, "hell_blau_4"))
	ev.append({"e": "finish", "seat": 0, "place": 1})
	t.handle_state(ev, s.view_for(0))
	await create_timer(0.52 + 0.75).timeout
	await _save_root("mau_mau")
	# Gegner wird fertig (nachts)
	await _clear()
	var s2 := TableSamples.create(4, 6, [5, 6, 1, 4])
	s2.flip()
	var t2 := _table(s2)
	await create_timer(0.4).timeout
	_freeze(t2.show_mau(2, true), 0.75)
	await create_timer(0.15).timeout
	await _save_root("mau_mau_nacht")


# Einstellungen: Abschnitt „Ton“ (Mau-Ton, Probehören „Mau!“/„Mau-Mau!“, Spieltöne)
func shot_einstellungen() -> void:
	await _clear()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(1.0).timeout
	main.call("push", SettingsScreen.new())
	await create_timer(1.0).timeout
	await _save_root("einstellungen")
