extends "res://tests/handover_wlan_ui_kit.gd"
# Kontrollbilder Beta 1.6.2, Gastgeber-Übergabe im WLAN und Spiel-WLAN (mit Renderer; „_shot“: vom Testlauf ausgenommen):
#   tools/godot_run.ps1 -Script res://tests/test_ui_handover_wlan_shot.gd -Resolution 1600x720 [-EnvPairs "SHOT_DIR=…"]
# Ohne SHOT_DIR nach docs/module/optik_162_*.png:
#   scan_<tag|nacht>            Gast: „Spiel-WLAN von Hanna ist weg.“ mit „Neues Spiel-WLAN bei Anna – QR-Code scannen“
#   scan_gross_nacht            dasselbe im großen Modus, Schrift „Sehr groß“
#   abgelaufen_<tag|nacht>      Raum abgelaufen: „In neuem Raum fortsetzen“, „Mit neuem Code beitreten“, „Zum Menü“
#   platz_<tag|nacht>           „Mitspieler“ → „Am Tisch“: Kim wartet, „Auf den Platz von Ben setzen“
#   platz_rueckfrage_tag        Rückfrage „Kim spielt dann mit den Karten von Ben weiter.“ · „Hinsetzen“
#   platz_sehr_gross_nacht      „Am Tisch“ mit Schrift „Sehr groß“
#   auswahl_<tag|nacht>         Auswahldialog: Lena gewählt mit „Muss das Spiel-WLAN erlauben.“, Warnzeile „Alle müssen danach …“
#   auswahl_sehr_gross_nacht    dasselbe mit Schrift „Sehr groß“
#   verlassen_tag               „Partie verlassen?“ mit „Dein Spiel-WLAN geht dann zu …“
#   hauptmenue_spielwlan, hauptmenue_spielwlan_sehr_gross   Rückfrage „Spiel-WLAN neu öffnen“ · „Beim neuen Gastgeber scannen“
#   hauptmenue_abgelaufen       Raum abgelaufen mit „In neuem Raum fortsetzen“ und „Mit neuem Code beitreten“

const SAVE := "user://test_ui_handover_wlan_shot_partie.json"

var nav: ScreenNav
var out := ""
var shots := 0


func _initialize() -> void:
	call_deferred("run")


func shot(file: String) -> void:
	await create_timer(0.3).timeout          # Einblenden der Überlagerungen (0,15 s) abwarten
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("optik_162_%s.png" % file))
	shots += 1


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
	nav.push(AppScreen.new(), false)
	await process_frame
	var now := int(Time.get_unix_time_from_system())
	var gd := game_dict()

	# --- Gast: Streifen (Tischbild aus einem Übungsspiel, Sicherung aus einem Gast-Tisch ohne Verbindung)
	var players := [{"name": "Du", "kind": "human"}, {"name": "Hanna", "kind": "bot"}, {"name": "Ben", "kind": "bot"}, {"name": "Anna", "kind": "bot"}]
	var src := GameStarter.local("solo", RuleConfig.preset("familie"), players, 7)
	src.max_steps = 0
	var ts := TableScreen.create(src, func() -> void: src.start())
	nav.push(ts, false)
	await create_timer(3.0).timeout
	ts._sub_next_ms = 1 << 60
	var ct := guest_table(guest_backup(gd, 0, now, true))
	var sw := FakeSwitch.new()
	sw.auto_process = false
	sw.source = ct
	ts._switch = sw
	sw.state = "scan"
	for tm in ["tag", "nacht"]:
		ts.table.set_night(1.0 if tm == "nacht" else 0.0)
		await shot("scan_" + tm)
	UiFonts.set_level("sehr_gross", root)
	ts.table.set_big(true)
	await process_frame
	ts._layout()
	await shot("scan_gross_nacht")
	ts.table.set_big(false)
	UiFonts.set_level("normal", root)
	sw.state = "gone"
	sw.last_error = "Der Online-Raum ist abgelaufen. Die Partie lässt sich nicht mehr fortsetzen."
	for tm in ["tag", "nacht"]:
		ts.table.set_night(1.0 if tm == "nacht" else 0.0)
		await shot("abgelaufen_" + tm)
	sw.state = "watch"
	ts._switch = null
	sw.free()
	ct.free()
	ts.leaving = true
	nav.pop(false)
	await create_timer(0.3).timeout

	# --- Gastgeber: „Am Tisch“ und Auswahldialog
	TableScreen.wifi_watch_factory = func(_h: HostTable) -> Node:
		var w := FakeWatch.new()
		w.state = {"status": "on", "ssid": "MMF-4821", "password": "katze123", "security": "wpa2"}
		w.address = "192.168.49.1"
		return w
	var ht := make_host(true)
	var hs := TableScreen.create(ht)
	nav.push(hs, false)
	await create_timer(0.5).timeout
	hs._sub_next_ms = 1 << 60
	for tm in ["tag", "nacht"]:
		hs.table.set_night(1.0 if tm == "nacht" else 0.0)
		hs.open_seat_manager("tisch")
		await shot("platz_" + tm)
		if tm == "tag":
			(hs._seat_mgr.find_child("AufPlatz2", true, false) as Button).pressed.emit()
			await shot("platz_rueckfrage_tag")
		hs._seat_mgr.close()
		await process_frame
	UiFonts.set_level("sehr_gross", root)
	hs.open_seat_manager("tisch")
	await shot("platz_sehr_gross_nacht")
	hs._seat_mgr.close()
	UiFonts.set_level("normal", root)
	await process_frame
	for v in [["tag", "normal"], ["nacht", "normal"], ["nacht", "sehr_gross"]]:
		hs.table.set_night(1.0 if v[0] == "nacht" else 0.0)
		UiFonts.set_level(str(v[1]), root)
		hs.open_host_pick()
		await process_frame
		(hs._pick.find_child("Platz_1", true, false) as Button).pressed.emit()
		await shot("auswahl_" + str(v[0]) if v[1] == "normal" else "auswahl_sehr_gross_nacht")
		hs._pick.close()
		await process_frame
	UiFonts.set_level("normal", root)
	hs.leaving = true
	nav.pop(false)
	await create_timer(0.3).timeout
	TableScreen.wifi_watch_factory = Callable()

	# --- „Partie verlassen?“ eines Gasts, der das Spiel-WLAN führt
	var ct2 := guest_table(guest_backup(gd, 1, now))
	var gs := TableScreen.create(ct2)
	nav.push(gs, false)
	await create_timer(0.3).timeout
	gs.table.set_night(0.0)
	gs.on_back()
	await shot("verlassen_tag")
	gs.leaving = true
	nav.pop(false)
	await create_timer(0.3).timeout

	# --- Hauptmenü
	var d := guest_backup(gd, 0, now)
	d["role"] = "host"
	d["my_seat"] = -1
	TableSource.write_saved(SAVE, d)
	for v in [["normal", "hauptmenue_spielwlan"], ["sehr_gross", "hauptmenue_spielwlan_sehr_gross"]]:
		UiFonts.set_level(str(v[0]), root)
		var mm := MainMenuScreen.new()
		mm.save_path = SAVE
		mm.now_unix = now
		nav.push(mm, false)
		await create_timer(0.4).timeout
		mm._on_resume_confirm({"role": "host", "age_min": 3, "warnings": [], "ap": true})
		await shot(str(v[1]))
		mm._close_resume_box()
		nav.pop(false)
		await create_timer(0.3).timeout
	UiFonts.set_level("normal", root)
	var mm2 := MainMenuScreen.new()
	mm2.save_path = SAVE
	mm2.now_unix = now
	nav.push(mm2, false)
	await create_timer(0.4).timeout
	var sw2 := FakeSwitch.new()
	sw2.auto_process = false
	mm2.add_child(sw2)
	mm2._resume_sw = sw2
	mm2._hook_resume(sw2)
	sw2._saved = guest_backup(gd, 0, now, true)
	sw2.last_error = "Der Online-Raum ist abgelaufen. Die Partie lässt sich nicht mehr fortsetzen."
	sw2._go("expired")
	await shot("hauptmenue_abgelaufen")
	mm2._close_resume_box()
	mm2._end_resume()
	TableSource.clear_saved(SAVE)
	print("RESULT: %d ok" % shots)
	quit(0)
