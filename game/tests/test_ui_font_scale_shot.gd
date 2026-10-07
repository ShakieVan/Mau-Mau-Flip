extends SceneTree
# Beta 1.0.1, Einstellung „Schriftgröße“: Kontrollbilder der wichtigen Bildschirme und des Tisches in allen drei Stufen
# (normal, gross, sehr_gross) und Prüfung auf Überlauf: kein sichtbares Bedienelement ragt über den Bildschirm bzw. über
# seinen Bildlauf hinaus, keine einzeilige Beschriftung ist schmaler als ihr Text. Mit echtem Renderer (wegen „_shot“ nicht
# in tools/build.ps1):
#   tools/godot_run.ps1 -Script res://tests/test_ui_font_scale_shot.gd -Resolution 1600x720 -EnvPairs "SHOT_DIR=…"
# Optional STUFE=gross (nur eine Stufe). Die Stufe wird nur in UiFonts gesetzt, nicht in App.settings gespeichert.

const CleanExit := preload("res://tests/clean_exit.gd")

var out_dir := ""
var shots := 0
var problems: Array[String] = []
var level := ""


func _initialize() -> void:
	call_deferred("run")


func wait(t: float) -> void:
	await create_timer(t).timeout


func run() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://")
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1600, 720)
	GameStarter.test_speed = 0.0
	var levels: Array = ["normal", "gross", "sehr_gross"]
	var only := OS.get_environment("STUFE")
	if only != "":
		levels = [only]
	for lvl in levels:
		level = str(lvl)
		UiFonts.set_level(level, root)
		await screens()
		await table()
	UiFonts.set_level("normal", root)
	for p in problems:
		print("UEBERLAUF: " + p)
	print("RESULT: %d Bilder, %d Überläufe" % [shots, problems.size()])
	await CleanExit.finish(self, 0)


func screens() -> void:
	var nav := ScreenNav.new()
	nav.autostart = false
	root.add_child(nav)
	UiFonts.set_level(level, root)   # ScreenNav setzt beim Start die gespeicherte Stufe
	await wait(0.2)
	var list: Array = [
		["hauptmenue", MainMenuScreen.new()],
		["einstellungen", SettingsScreen.new()],
		["uebung", SoloSetupScreen.new()],
		["weitergeben", PassSetupScreen.new()],
		["wlan", WlanScreen.new()],
		["beitreten", JoinScreen.new()],
	]
	for e in list:
		nav.push(e[1], false)
		await wait(0.5)
		await snap(str(e[0]), nav)
		var scrolls := nav.top().find_children("*", "ScrollContainer", true, false)
		if not scrolls.is_empty():
			for s in scrolls:
				(s as ScrollContainer).scroll_vertical = 100000
			await wait(0.3)
			await snap(str(e[0]) + "_unten", nav)
		nav.go_back()
		await wait(0.3)
	var rs := RulesScreen.new()
	nav.push(rs, false)
	await wait(0.6)
	await snap("regeln", nav)
	rs._overview.scroll_vertical = 100000
	await wait(0.3)
	await snap("regeln_unten", nav)
	rs._show_tab("anpassen")
	await wait(0.4)
	await snap("regeln_anpassen", nav)
	nav.go_back()
	await wait(0.3)
	var lobby := HostLobbyScreen.new()
	nav.push(lobby, false)
	await wait(0.5)
	for i in 4:
		lobby.host.add_bot()
	await wait(0.6)
	await snap("lobby", nav)
	nav.queue_free()
	await wait(0.3)


func table() -> void:
	var s := TableSamples.create(4, 5, [0, 6, 5, 2])
	for k in ["hell_rot_7", "hell_rot_flip", "hell_gelb_3", "hell_gelb_plus1", "hell_gruen_aussetzen", "hell_blau_9", "hell_blau_richtungswechsel", "hell_wuenscher", "hell_wuenscher_plus2"]:
		s.give(0, k)
	s.set_top("hell_gelb_9")
	s.set_top("hell_blau_9")
	s.set_draw_top("hell_rot_4")
	s.turn = 1
	var t := TableView.new()
	root.add_child(t)
	t.set_hand(DemoHand.new())
	t.apply_view(s.view_for(0))
	await wait(0.8)
	t.hint_bar.show_hint("+1 auf dich – Zieh 2.", true)
	await wait(0.6)
	await snap("tisch", t)
	t.queue_free()
	await wait(0.3)


func snap(name: String, scope: Node) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join("schrift_%s_%s.png" % [level, name]))
	shots += 1
	check_overflow(name, scope)


# Sichtbare Controls: rechts/unten nicht über den Bildschirm, im Bildlauf nicht breiter als dieser; einzeilige Labels nicht
# schmaler als ihr Text
func check_overflow(name: String, scope: Node) -> void:
	var vp := Rect2(Vector2.ZERO, Vector2(root.size))
	for n in scope.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree() or c.size.x < 1.0 or c.get_global_transform().get_scale().x < 0.99:
			continue
		var r := c.get_global_rect()
		var sc := _scroll_of(c)
		var where := "%s/%s: %s „%s“" % [level, name, c.get_class(), _text(c)]
		if sc != null:
			var sr := sc.get_global_rect()
			if r.end.x > sr.end.x + 2.0 and sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
				_report(where + " breiter als Bildlauf (%d > %d)" % [r.end.x, sr.end.x])
		elif r.end.x > vp.end.x + 2.0 or r.end.y > vp.end.y + 2.0:
			_report(where + " ragt aus dem Bild (%d, %d)" % [r.end.x, r.end.y])
		if c is Label:
			var l := c as Label
			if l.autowrap_mode == TextServer.AUTOWRAP_OFF and l.text != "" and not l.text.contains("\n"):
				var f := l.get_theme_font("font")
				var w := f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
				if w > l.size.x + 2.0:
					_report(where + " abgeschnitten (%d > %d)" % [w, l.size.x])


func _report(t: String) -> void:
	if not problems.has(t):
		problems.append(t)


func _scroll_of(c: Control) -> ScrollContainer:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


func _text(c: Control) -> String:
	var t := ""
	if c is Label:
		t = (c as Label).text
	elif c is Button:
		t = (c as Button).text
	return t.left(40).replace("\n", " ")
