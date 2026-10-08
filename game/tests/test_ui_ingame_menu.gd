extends SceneTree
# Menü im Spiel (Beta 1.1.2): ☰ neben dem Zurück-Knopf → „Einstellungen“, „Regeln ansehen“, „So geht's“.
#   Einstellungen als Überlagerung (SettingsScreen.personal), Änderungen wirken sofort am Tisch (großer Modus, Hervorheben);
#   Zurück-Taste schließt erst die Überlagerung, dann das Menü; Sichtschutz (Weitergeben) schließt beides und zeigt den Knopf nicht
#   (Regel 15, keine Karten); großer Modus: ☰ unter dem Zurück-Knopf; Nacht: heller Rand wie der Zurück-Knopf.
#   godot_run.ps1 -Script res://tests/test_ui_ingame_menu.gd -Headless
# Kontrollbild (mit Renderer, ohne -Headless): -EnvPairs 'SHOT=1' → docs/module/F2_menue_im_spiel.png (oben Tag mit Menü,
# unten Nacht mit Einstellungen)

const CleanExit := preload("res://tests/clean_exit.gd")
const SETTINGS_PATH := "user://test_ingame_menu_settings.cfg"

var ok := 0
var failed := false
var nav: ScreenNav
var ts: TableScreen


func _initialize() -> void:
	call_deferred("run")


func check(cond: bool, what: String) -> void:
	if cond:
		ok += 1
	else:
		failed = true
		print("FAIL: " + what)


func frames(n := 2) -> void:
	for i in n:
		await process_frame


func _texts(n: Node, out: Array) -> void:
	if n is Label:
		out.append((n as Label).text)
	if n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		_texts(c, out)


func _no_cards(n: Node) -> bool:
	return n.find_children("*", "CardView", true, false).is_empty() and n.find_children("Bilder", "", true, false).is_empty()


func run() -> void:
	GameStarter.test_speed = 0.0
	root.size = Vector2i(1600, 720)
	var app := UiApp.app()
	var real_settings: Variant = app.get("settings") if app != null else null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	if app != null:
		app.set("settings", AppSettings.new(SETTINGS_PATH))
		app.settings.set_value("grosser_modus", false)
		app.settings.set_value("hervorheben", true)
	nav = ScreenNav.new()
	root.add_child(nav)
	await frames(3)
	var cfg := RuleConfig.preset("familie")
	var players := [{"name": "Du", "kind": "human"}, {"name": "Mimi", "kind": "bot"}, {"name": "Socke", "kind": "bot"}]
	var src := GameStarter.local("solo", cfg, players, 1)
	ts = TableScreen.create(src, func() -> void: src.start())
	nav.push(ts, false)
	var deadline := Time.get_ticks_msec() + 15000
	while ts.view.is_empty() and Time.get_ticks_msec() < deadline:
		await frames(1)
	check(not ts.view.is_empty(), "Sicht da")
	await frames(2)

	# ☰ rechts neben dem Zurück-Knopf, gleich groß
	var burger: Button = ts.get("_burger")
	var back: Button = ts.get("_menu_btn")
	check(burger != null and burger.visible and burger.icon != null, "☰-Knopf mit Symbol")
	check(burger.size == back.size and is_equal_approx(burger.position.y, back.position.y) and burger.position.x > back.position.x + back.size.x,
		"☰ neben dem Zurück-Knopf (%s %s / %s %s)" % [str(burger.position), str(burger.size), str(back.position), str(back.size)])
	burger.pressed.emit()
	await frames(2)
	check(ts.is_menu_open(), "Menü offen")
	var menu: IngameMenu = ts.get("_ingame_menu")
	var t: Array = []
	_texts(menu, t)
	check(t.has("Einstellungen") and t.has("Regeln ansehen") and t.has("So geht's"), "Menü: Einstellungen, Regeln, So geht's " + str(t))
	if OS.get_environment("SHOT") == "1":
		await create_timer(0.5).timeout
		var img_day := root.get_texture().get_image()
		ts.set_meta("shot_day", img_day)
	# Zurück-Taste schließt nur das Menü
	check(ts.on_back(), "Zurück verbraucht")
	await frames(2)
	check(not ts.is_menu_open() and ts.get("_confirm") == null and not ts.leaving, "Menü zu, keine Rückfrage")
	# Menü → Regeln
	ts.open_menu()
	await frames(1)
	(ts.get("_ingame_menu") as IngameMenu).find_child("Wahl_regeln", true, false).pressed.emit()
	await frames(2)
	check(ts.is_help_open() and (ts.get("_help") as IngameHelp).tab == "regeln" and not ts.is_menu_open(), "Menü → Regeln ansehen")
	ts.on_back()
	await frames(1)
	ts.open_menu()
	await frames(1)
	(ts.get("_ingame_menu") as IngameMenu).find_child("Wahl_bedienung", true, false).pressed.emit()
	await frames(2)
	check(ts.is_help_open() and (ts.get("_help") as IngameHelp).tab == "bedienung", "Menü → So geht's")
	ts.on_back()
	await frames(1)

	# Menü → Einstellungen
	ts.open_menu()
	await frames(1)
	(ts.get("_ingame_menu") as IngameMenu).find_child("Wahl_einstellungen", true, false).pressed.emit()
	await frames(2)
	check(ts.is_settings_open() and not ts.is_menu_open(), "Einstellungen offen")
	var ov: IngameSettings = ts.get("_settings_ov")
	for key in ["MauTon", "Toene", "Schrift", "GrosserModus", "Hervorheben", "Vibration", "ZugVibration", "Effekte", "Tempo"]:
		check(ov.find_child(key, true, false) != null, "Einstellung „%s“" % key)
	check(_no_cards(ov), "Einstellungen ohne Karten")
	# Live: großer Modus und Hervorheben
	var big_sw: CheckButton = ov.find_child("GrosserModus", true, false)
	big_sw.button_pressed = true
	await frames(3)
	check(ts.table.big and bool(UiApp.setting("grosser_modus", false)), "großer Modus wirkt sofort")
	check(ts.is_settings_open(), "Überlagerung bleibt offen")
	check(is_equal_approx(burger.position.x, back.position.x) and burger.position.y > back.position.y + back.size.y - 1.0
		and is_equal_approx(burger.size.x, BigLayout.MENU), "großer Modus: ☰ unter dem Zurück-Knopf, groß")
	var hl: CheckButton = ov.find_child("Hervorheben", true, false)
	hl.button_pressed = not hl.button_pressed
	await frames(1)
	check(ts.table.highlight == hl.button_pressed, "Hervorheben wirkt sofort")
	hl.button_pressed = true
	# Zurück-Taste schließt die Überlagerung, Partie läuft
	check(ts.on_back(), "Zurück verbraucht (Einstellungen)")
	await frames(2)
	check(not ts.is_settings_open() and ts.get("_confirm") == null and ts.is_inside_tree(), "Einstellungen zu, Tisch bleibt")
	# Als WLAN-Gast oder ohne Computer kein Tempo-Regler
	var plain := IngameSettings.open(ts.get("_top"), false)
	check(plain.find_child("Tempo", true, false) == null, "ohne Computergegner kein Tempo-Regler")
	plain.close()

	# Nacht: ☰ hell wie der Zurück-Knopf
	ts.table.night = 1.0
	await frames(2)
	var sb := burger.get_theme_stylebox("normal") as StyleBoxFlat
	check(sb != null and sb.border_color.get_luminance() > 0.6, "nachts heller Rand")
	ts.open_settings()
	await frames(2)
	if OS.get_environment("SHOT") == "1":
		await create_timer(0.5).timeout
		var img_night := root.get_texture().get_image()
		var day: Image = ts.get_meta("shot_day")
		var w := img_night.get_width()
		var h := img_night.get_height()
		var out := Image.create(w, h * 2, false, img_night.get_format())
		day.convert(img_night.get_format())
		out.blit_rect(day, Rect2i(0, 0, w, h), Vector2i(0, 0))
		out.blit_rect(img_night, Rect2i(0, 0, w, h), Vector2i(0, h))
		out.resize(w / 2, h, Image.INTERPOLATE_LANCZOS)
		var path := ProjectSettings.globalize_path("res://").path_join("../docs/module/F2_menue_im_spiel.png").simplify_path()
		out.save_png(path)
		print("Bild: " + path)

	# Sichtschutz (Weitergeben): schließt Menü und Einstellungen, ☰ unsichtbar, öffnet nicht (Regel 15)
	ts.table.handover.visible = true
	await frames(2)
	check(not ts.is_settings_open(), "Sichtschutz schließt die Einstellungen")
	check(not burger.visible, "Sichtschutz: kein ☰")
	ts.open_menu()
	ts.open_settings()
	await frames(1)
	check(not ts.is_menu_open() and not ts.is_settings_open(), "nichts hinter dem Sichtschutz")
	ts.table.handover.visible = false

	if app != null and real_settings != null:
		app.set("settings", real_settings)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	print("RESULT: %d ok%s" % [ok, ", FEHLER" if failed else ""])
	await CleanExit.finish(self, 1 if failed else 0)
