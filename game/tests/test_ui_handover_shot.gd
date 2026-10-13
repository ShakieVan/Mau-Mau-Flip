extends SceneTree
# Kontrollbilder Beta 1.6.1, Gastgeber-Übergabe (mit Renderer; „_shot“: vom Testlauf ausgenommen):
#   tools/godot_run.ps1 -Script res://tests/test_ui_handover_shot.gd -Resolution 1600x720 [-EnvPairs "SHOT_DIR=…"]
# Ohne SHOT_DIR nach docs/module/optik_161_*.png:
#   menue_<tag|nacht>           ☰-Menü des Gastgebers mit „Gastgeber übergeben …“ (Tag wählbar, Nacht ausgegraut mit Grund);
#   menue_sehr_gross_nacht      dasselbe mit Schrift „Sehr groß“ (flachere Knöpfe bzw. zwei Spalten)
#   auswahl_<tag|nacht>         Auswahldialog: Lena gewählt, Ben (Browser) ausgegraut mit Grund, Kim nicht verbunden
#   streifen_<tag|nacht>        Gast: „Gastgeber antwortet nicht. Du übernimmst in 24 s.“ mit Knopf „Spiel als Gastgeber fortsetzen“
#   streifen_gross_nacht        dasselbe im großen Modus, Schrift „Sehr groß“, ohne Rang („warte …“)
#   rueckfrage_<tag|nacht>      Rückfrage mit beiden Warnzeilen
#   hauptmenue, hauptmenue_sehr_gross, hauptmenue_en   Hauptmenü mit „Partie fortsetzen“ und „Partie verwerfen“

const SAVE := "user://test_ui_handover_shot_partie.json"

var nav: ScreenNav
var ts: TableScreen
var out := ""
var shots := 0


class FakeSwitch:
	extends HostSwitch
	var fake_ms := -1
	var fake_take := true
	var warn: Array = []

	func countdown_ms() -> int:
		return fake_ms

	func can_continue() -> bool:
		return fake_take

	func continue_warnings() -> Array:
		return warn


func _initialize() -> void:
	call_deferred("run")


func shot(file: String) -> void:
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("optik_161_%s.png" % file))
	shots += 1


func night(on: bool) -> void:
	ts.table.set_night(1.0 if on else 0.0)


func run() -> void:
	root.size = Vector2i(1600, 720)
	GameStarter.test_speed = 0.0
	out = OS.get_environment("SHOT_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("res://").path_join("../docs/module").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	var app := UiApp.app()
	if app != null and app.get("settings") != null:
		app.settings.set_value("grosser_modus", false)
	nav = ScreenNav.new()
	nav.autostart = false
	root.add_child(nav)
	await process_frame
	var players := [{"name": "Du", "kind": "human"}, {"name": "Lena", "kind": "bot"}, {"name": "Ben", "kind": "bot"}, {"name": "Kim", "kind": "bot"}]
	var src := GameStarter.local("solo", RuleConfig.preset("familie"), players, 7)
	src.max_steps = 0
	ts = TableScreen.create(src, func() -> void: src.start())
	nav.push(ts, false)
	await create_timer(3.0).timeout
	ts._sub_next_ms = 1 << 60
	var game_dict := src.game.to_dict()

	# ☰-Menü
	for tm in ["tag", "nacht"]:
		night(tm == "nacht")
		var reason := "" if tm == "tag" else I18n.t("Geht in dieser Version nur, wenn alle online mitspielen.")
		var at := ts._burger.position + Vector2(0.0, ts._burger.size.y + 10.0)
		var m := IngameMenu.open(ts._top, at, IngameMenu.HOST_ITEMS + [IngameMenu.HANDOVER_ITEM + [reason]] + IngameMenu.ITEMS)
		await shot("menue_" + tm)
		m.close()
	UiFonts.set_level("sehr_gross", root)
	var m2 := IngameMenu.open(ts._top, ts._burger.position + Vector2(0.0, ts._burger.size.y + 10.0),
		IngameMenu.HOST_ITEMS + [IngameMenu.HANDOVER_ITEM + [I18n.t("%s ist gerade nicht verbunden.") % "Lena"]] + IngameMenu.ITEMS)
	await shot("menue_sehr_gross_nacht")
	m2.close()
	UiFonts.set_level("normal", root)

	# Auswahldialog
	var rows := [{"seat": 1, "name": "Lena", "kind": "human", "reason": ""},
		{"seat": 2, "name": "Ben", "kind": "human", "reason": I18n.t("Nur Mitspieler mit der App können Gastgeber werden.")},
		{"seat": 3, "name": "Kim", "kind": "human", "reason": I18n.t("%s ist gerade nicht verbunden.") % "Kim"}]
	for tm in ["tag", "nacht"]:
		night(tm == "nacht")
		var d := HostPickDialog.open(ts._top, func() -> Array: return rows)
		await process_frame
		(d.find_child("Platz_1", true, false) as Button).pressed.emit()
		await shot("auswahl_" + tm)
		d.close()

	# Verbindungsstreifen und Rückfrage
	var sw := FakeSwitch.new()
	sw.auto_process = false
	ts._switch = sw
	sw.state = "waiting"
	sw.warn = [I18n.part("Dein Spielstand ist vielleicht nicht der neueste."), I18n.part("WLAN-Mitspieler kommen dann nicht mit.")]
	for tm in ["tag", "nacht"]:
		night(tm == "nacht")
		sw.fake_ms = 23400
		await shot("streifen_" + tm)
		ts.ask_continue_as_host()
		await shot("rueckfrage_" + tm)
		ts._confirm.queue_free()
		ts._confirm = null
	UiFonts.set_level("sehr_gross", root)
	ts.table.set_big(true)
	night(true)
	sw.fake_ms = -1
	await process_frame
	ts._layout()
	await shot("streifen_gross_nacht")
	ts.table.set_big(false)
	UiFonts.set_level("normal", root)
	ts._switch = null
	sw.free()

	# Hauptmenü
	var now := int(Time.get_unix_time_from_system())
	var seats := [{"name": "Du", "kind": "human", "host": true, "net": "app", "token": "t0"},
		{"name": "Lena", "kind": "human", "host": false, "net": "app", "token": "t1"},
		{"name": "Ben", "kind": "human", "host": false, "net": "web", "token": "t2"},
		{"name": "Kim", "kind": "human", "host": false, "net": "app", "token": "t3"},
		{"name": "Minka", "kind": "bot", "host": false, "net": "bot", "token": ""}]
	game_dict["round"] = 3
	TableSource.write_saved(SAVE, MatchSnapshot.make(game_dict, seats, 0, {"gid": "ab12cd34ef567890", "gen": 1, "epoch": "a1b2c3d4",
		"online": {"relay": "wss://vermittler.test", "room": "KATZE-42", "token": "r", "conns": [1], "max_c": 1, "created_unix": now - 900}},
		now - 12 * 60, "host"))
	for v in [["normal", "de", "hauptmenue"], ["sehr_gross", "de", "hauptmenue_sehr_gross"], ["normal", "en", "hauptmenue_en"]]:
		UiFonts.set_level(str(v[0]), root)
		I18n.set_language(str(v[1]))
		var mm := MainMenuScreen.new()
		mm.save_path = SAVE
		mm.now_unix = now
		nav.push(mm, false)
		await create_timer(0.6).timeout
		await shot(str(v[2]))
		nav.pop(false)
		await create_timer(0.3).timeout
	UiFonts.set_level("normal", root)
	I18n.set_language("de")
	TableSource.clear_saved(SAVE)
	print("RESULT: %d ok" % shots)
	quit(0)
