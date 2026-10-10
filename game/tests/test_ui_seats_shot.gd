extends SceneTree
# Kontrollbilder Beta 1.4.2, Mitspieler dazuholen und entfernen (mit Renderer; „_shot“: vom Testlauf ausgenommen):
#   tools/godot_run.ps1 -Script res://tests/test_ui_seats_shot.gd -Resolution 1600x720 -Timeout 300
# Je Durchgang (de normal, en normal, de „Sehr groß“): Feld „Mitspieler“ (Einladen, Am Tisch mit Wartendem) tags/nachts, Rückfrage
# „… an den Tisch holen?“, Tisch kurz nach dem Dazuholen („Hallo!“), Zurück-Menü des Gastgebers, Warteliste beim Gast, Sofort-Leiste
# (getrennter Gast) tags/nachts normal und groß, Rückfrage „… aus dem Spiel nehmen?“:
# docs/geraetetest/1.4.2/dazuholen_<bild>_<de|en>_<normal|sehr_gross>[_<tag|nacht>].png

const CleanExit := preload("res://tests/clean_exit.gd")

var out := ""
var shots := 0
var nav: ScreenNav
var nav2: ScreenNav
var tag := ""


func _initialize() -> void:
	call_deferred("run")


func wait(t: float) -> void:
	await create_timer(t).timeout


func frames(n := 2) -> void:
	for i in n:
		await process_frame


func _wait_for(cond: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not bool(cond.call()) and Time.get_ticks_msec() < deadline:
		await frames(1)
	return bool(cond.call())


func shot(name: String) -> void:
	await frames(6)
	root.get_texture().get_image().save_png(out.path_join("dazuholen_%s_%s.png" % [name, tag]))
	shots += 1


func run() -> void:
	root.size = Vector2i(1600, 720)
	out = ProjectSettings.globalize_path("res://").path_join("../docs/geraetetest/1.4.2").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	GameStarter.test_speed = 0.0
	var app := UiApp.app()
	var big_backup: Variant = UiApp.setting("grosser_modus", false)
	var rules_backup: Variant = UiApp.setting("regeln", {})
	var name_backup: Variant = UiApp.setting("name", "")
	var font_backup: Variant = UiApp.setting("schrift", "normal")
	for pass_ in [["de", "normal"], ["en", "normal"], ["de", "sehr_gross"]]:
		I18n.set_language(str(pass_[0]))
		app.settings.set_value("schrift", str(pass_[1]))
		UiFonts.set_level(str(pass_[1]))
		tag = "%s_%s" % pass_
		await one_pass()
	I18n.set_language("de")
	UiFonts.set_level("normal")
	if app != null:
		app.settings.set_value("grosser_modus", big_backup)
		app.settings.set_value("name", name_backup)
		app.settings.set_value("schrift", font_backup)
		app.settings.set_value("regeln", rules_backup if rules_backup is Dictionary else {})
	print("RESULT: %d ok" % shots)
	await CleanExit.finish(self, 0)


func _night(ts: TableScreen, on: bool) -> void:
	ts.table.set_night(1.0 if on else 0.0)
	await frames(4)


func one_pass() -> void:
	UiApp.app().settings.set_value("regeln", RuleConfig.new().to_dict())
	UiApp.app().settings.set_value("name", "Shakie")
	UiApp.app().settings.set_value("grosser_modus", false)
	nav = ScreenNav.new()
	nav.autostart = false
	root.add_child(nav)
	await frames(2)
	nav.push(HostLobbyScreen.new(), false)
	await frames(3)
	var lobby := nav.top() as HostLobbyScreen
	var host := lobby.host
	host.autosave = false
	var port := host.port()
	host.add_bot("Minka")
	host.add_bot("Mogli")
	await wait(0.2)
	lobby.start_game()
	await _wait_for(func() -> bool: return nav.top() is TableScreen and host.game != null, 4.0)
	var ts := nav.top() as TableScreen
	await _wait_for(func() -> bool: return host.game.state == "turn" and host.game.current == host.host_seat and not ts.table.director.is_busy(), 10.0)
	await _night(ts, false)
	ts.open_seat_manager("dazuholen")
	await wait(0.4)
	await shot("einladen_tag")
	await _night(ts, true)
	await shot("einladen_nacht")
	await _night(ts, false)
	# Gast meldet sich
	nav2 = ScreenNav.new()
	nav2.autostart = false
	root.add_child(nav2)
	await frames(2)
	nav2.push(JoinScreen.new(), false)
	await frames(2)
	UiApp.app().settings.set_value("name", "Kim")
	(nav2.top() as JoinScreen).join("127.0.0.1", port)
	await _wait_for(func() -> bool: return not host.waiting_ids().is_empty(), 6.0)
	await wait(0.6)
	# Warteliste beim Gast (Gastgeber-Ebenen kurz aus)
	for l: CanvasItem in [ts]:
		l.visible = false
	ts.overlay.visible = false
	ts.top_layer.visible = false
	await shot("gast_warteliste")
	ts.visible = true
	ts.overlay.visible = true
	ts.top_layer.visible = true
	nav2.visible = false
	var sm := ts._seat_mgr
	var gid := int(host.waiting_ids()[0])
	sm.move(gid, -1)
	sm.move(gid, -1)
	await shot("am_tisch_tag")
	await _night(ts, true)
	await shot("am_tisch_nacht")
	await _night(ts, false)
	sm.ask_seat(gid)
	await wait(0.3)
	await shot("rueckfrage_dazuholen")
	sm._confirm._answer(true)
	sm.close()
	await wait(0.35)
	await shot("hallo")
	await _wait_for(func() -> bool: return host.game.state == "turn" and not ts.table.director.is_busy(), 10.0)
	# Zurück-Menü
	ts.on_back()
	await wait(0.3)
	await shot("zurueck_menue")
	ts._confirm.queue_free()
	ts._confirm = null
	# Gast weg → Sofort-Leiste
	nav2.queue_free()
	nav2 = null
	await _wait_for(func() -> bool: return ts._sub_hint.visible, 4.0)
	await wait(0.3)
	await shot("leiste_normal_tag")
	await _night(ts, true)
	await shot("leiste_normal_nacht")
	UiApp.app().settings.set_value("grosser_modus", true)
	await wait(0.6)
	await shot("leiste_gross_nacht")
	await _night(ts, false)
	await shot("leiste_gross_tag")
	ts.ask_kick()
	await wait(0.3)
	await shot("rueckfrage_entfernen")
	ts._confirm._answer(true)
	await wait(0.25)
	await shot("entfernt_gross")
	await wait(1.0)
	ts._leave_now()
	await wait(0.5)
	nav.queue_free()
	await wait(0.3)
