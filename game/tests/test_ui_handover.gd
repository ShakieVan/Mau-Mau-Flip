extends SceneTree
# Mau-Mau Flip (Beta 1.6.1, Gastgeber-Übergabe, docs/module/uebergabe.md 4.1, 4.4, 6): Oberfläche ohne Netz.
#   ☰-Eintrag „Gastgeber übergeben …“ (ausgegraut mit Grund; kein Eintrag ohne Netz-Gastgeber), Auswahldialog (ausgegraute Mitspieler
#   mit Grund, Wahl verschwindet, wenn der Gewählte nicht mehr geht, „Übergeben“ → chosen), Verbindungsstreifen des Gasts aus dem
#   HostSwitch (Countdown nach Rang, „warte …“, Knopf „Spiel als Gastgeber fortsetzen“ mit Rückfrage und Warnzeilen, Raum abgelaufen),
#   Hauptmenü „Partie fortsetzen“ (Zeile Name · Runde · Alter) und „Partie verwerfen“ (Rückfrage, Datei weg).
#   Der Wächter ist ein FakeSwitch (HostSwitch mit festen Antworten), die Partie ein Übungsspiel.
#   godot_run.ps1 -Script res://tests/test_ui_handover.gd -Headless
# Kontrollbilder: test_ui_handover_shot.gd

const CleanExit := preload("res://tests/clean_exit.gd")
const SAVE := "user://test_ui_handover_partie.json"

var ok := 0
var failed := false
var nav: ScreenNav
var ts: TableScreen


class FakeSwitch:
	extends HostSwitch
	var fake_ms := -1
	var fake_take := true
	var warn: Array = []
	var continued := 0

	func countdown_ms() -> int:
		return fake_ms

	func can_continue() -> bool:
		return fake_take

	func continue_warnings() -> Array:
		return warn

	func continue_as_host() -> bool:
		continued += 1
		return true


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


# Netzpartie als Datei (role host, online-Raum vor 10 min, Stand vor saved_ago s)
static func write_snapshot(path: String, now: int, saved_ago: int, game_dict: Dictionary) -> void:
	var seats := [{"name": "Du", "kind": "human", "host": true, "net": "app", "token": "t0"},
		{"name": "Lena", "kind": "human", "host": false, "net": "app", "token": "t1", "link": "online"},
		{"name": "Ben", "kind": "human", "host": false, "net": "web", "token": "t2", "link": "online"},
		{"name": "Minka", "kind": "bot", "host": false, "net": "bot", "token": ""}]
	var extra := {"gid": "ab12cd34ef567890", "gen": 1, "epoch": "a1b2c3d4", "seq": 12,
		"online": {"relay": "wss://vermittler.test", "room": "KATZE-42", "token": "r", "conns": [1, 2], "max_c": 2, "created_unix": now - 600}}
	TableSource.write_saved(path, MatchSnapshot.make(game_dict, seats, 0, extra, now - saved_ago, "host"))


func run() -> void:
	GameStarter.test_speed = 0.0
	root.size = Vector2i(1600, 720)
	nav = ScreenNav.new()
	nav.autostart = false
	root.add_child(nav)
	await frames(3)
	var players := [{"name": "Du", "kind": "human"}, {"name": "Lena", "kind": "bot"}, {"name": "Ben", "kind": "bot"}, {"name": "Minka", "kind": "bot"}]
	var src := GameStarter.local("solo", RuleConfig.preset("familie"), players, 7)
	src.max_steps = 0
	ts = TableScreen.create(src, func() -> void: src.start())
	nav.push(ts, false)
	var deadline := Time.get_ticks_msec() + 15000
	while ts.view.is_empty() and Time.get_ticks_msec() < deadline:
		await frames(1)
	check(not ts.view.is_empty(), "Sicht da")
	var game_dict := src.game.to_dict()

	# --- ☰: kein Eintrag ohne Netz-Gastgeber; ausgegraut mit Grund
	check(ts.handover_entry().is_empty(), "Übungsspiel: kein „Gastgeber übergeben …“")
	var m := IngameMenu.open(ts._top, Vector2(130, 20), IngameMenu.HOST_ITEMS + [IngameMenu.HANDOVER_ITEM + ["Geht in dieser Version nur, wenn alle online mitspielen."]] + IngameMenu.ITEMS)
	await frames(2)
	var hb := m.find_child("Wahl_uebergeben", true, false) as Button
	var why := m.find_child("Grund", true, false) as Label
	check(hb != null and hb.disabled, "Eintrag ausgegraut")
	check(why != null and why.text.begins_with("Geht in dieser Version"), "Grund unter dem Eintrag")
	m.close()
	m = IngameMenu.open(ts._top, Vector2(130, 20), IngameMenu.HOST_ITEMS + [IngameMenu.HANDOVER_ITEM + [""]] + IngameMenu.ITEMS)
	await frames(1)
	hb = m.find_child("Wahl_uebergeben", true, false) as Button
	check(hb != null and not hb.disabled and m.find_child("Grund", true, false) == null, "Eintrag wählbar ohne Grund")
	var picked: Array = []
	m.chosen.connect(func(k: String) -> void: picked.append(k))
	hb.pressed.emit()
	await frames(1)
	check(picked == ["uebergeben"], "Wahl „uebergeben“")

	# --- Auswahldialog
	var rows := [{"seat": 1, "name": "Lena", "kind": "human", "reason": ""},
		{"seat": 2, "name": "Ben", "kind": "human", "reason": "Nur Mitspieler mit der App können Gastgeber werden."}]
	var dlg := HostPickDialog.open(ts._top, func() -> Array: return rows)
	await frames(2)
	var go := dlg.find_child("Uebergeben", true, false) as Button
	var lena := dlg.find_child("Platz_1", true, false) as Button
	var ben := dlg.find_child("Platz_2", true, false) as Button
	check(go.disabled and lena != null and not lena.disabled and ben != null and ben.disabled, "Dialog: Ben ausgegraut, noch keine Wahl")
	check(ben.find_child("Grund", true, false) != null, "Dialog: Grund bei Ben")
	lena.pressed.emit()
	await frames(1)
	check(not go.disabled and (dlg.find_child("Haken", true, false) as Control).visible, "Dialog: Lena gewählt")
	rows[0] = {"seat": 1, "name": "Lena", "kind": "human", "reason": "Lena ist gerade nicht verbunden."}   # gleiche Liste (Lambda)
	dlg.refresh()
	await frames(1)
	go = dlg.find_child("Uebergeben", true, false) as Button
	check(go.disabled and (dlg.find_child("Platz_1", true, false) as Button).disabled, "Dialog: Wahl weg, wenn Lena sich trennt")
	rows[0] = {"seat": 1, "name": "Lena", "kind": "human", "reason": ""}
	dlg.refresh(true)
	await frames(1)
	(dlg.find_child("Platz_1", true, false) as Button).pressed.emit()
	var got: Array = []
	dlg.chosen.connect(func(s: int, n: String) -> void: got.append([s, n]))
	(dlg.find_child("Uebergeben", true, false) as Button).pressed.emit()
	await frames(1)
	check(got == [[1, "Lena"]] and (not is_instance_valid(dlg) or dlg.is_queued_for_deletion()),"Dialog: Übergeben → chosen(1, Lena), zu (%s)" % [got])

	# --- Verbindungsstreifen des Gasts
	var sw := FakeSwitch.new()
	sw.auto_process = false
	ts._switch = sw
	sw.state = "waiting"
	sw.fake_ms = 23400
	await frames(2)
	check(ts._conn.visible and ts._conn_label.text == "Gastgeber antwortet nicht. Du übernimmst in 24 s.", "Streifen mit Countdown (%s)" % ts._conn_label.text)
	check(ts._conn_take.visible, "Knopf „Spiel als Gastgeber fortsetzen“")
	sw.fake_ms = -1
	sw.fake_take = false
	await frames(2)
	check(ts._conn_label.text == "Gastgeber antwortet nicht – warte …" and not ts._conn_take.visible, "ohne Rang: „warte …“, Knopf erst mit can_continue")
	sw.fake_take = true
	sw.warn = [I18n.part("Dein Spielstand ist vielleicht nicht der neueste."), I18n.part("WLAN-Mitspieler kommen dann nicht mit.")]
	await frames(1)
	ts._conn_take.pressed.emit()
	await frames(2)
	var box := ts._confirm
	check(box != null and box.name == "AlsGastgeberFortsetzen", "Rückfrage offen")
	var notes := box.find_children("Warnung*", "Label", true, false) if box != null else []
	check(notes.size() == 2, "zwei Warnzeilen (%d)" % notes.size())
	(box.find_child("Ja", true, false) as Button).pressed.emit()
	await frames(1)
	check(sw.continued == 1, "Fortsetzen → continue_as_host")
	sw.state = "gone"
	sw.last_error = "Der Online-Raum ist abgelaufen. Die Partie lässt sich nicht mehr fortsetzen."
	await frames(2)
	check(ts._conn.visible and ts._conn_label.text.begins_with("Der Online-Raum ist abgelaufen") and ts._conn_menu.visible and not ts._conn_take.visible,
		"Raum abgelaufen: Meldung und „Zum Menü“")
	sw.state = "watch"
	await frames(2)
	check(not ts._conn.visible and not ts._conn_take.visible, "Gastgeber wieder da: Streifen weg")
	ts._switch = null
	sw.free()

	# --- Hauptmenü
	var now := int(Time.get_unix_time_from_system())
	TableSource.clear_saved(SAVE)
	var mm := MainMenuScreen.new()
	mm.save_path = SAVE
	mm.now_unix = now
	nav.push(mm, false)
	await frames(3)
	check(not mm.resume_row.visible, "ohne Datei kein „Partie fortsetzen“")
	write_snapshot(SAVE, now, 170, game_dict)
	mm.refresh_resume()
	await frames(1)
	var sub := mm.resume_row.find_child("Unterzeile", true, false) as Label
	check(mm.resume_row.visible and sub.text == "Lena, Ben … · Runde 1 · vor 3 min", "Zeile „%s“" % (sub.text if sub != null else "?"))
	var gd := game_dict.duplicate(true)
	gd["phase"] = "game_over"
	write_snapshot(SAVE, now, 170, gd)
	mm.refresh_resume()
	check(not mm.resume_row.visible, "Partie vorbei: nichts anzubieten")
	write_snapshot(SAVE, now, 13 * 3600, game_dict)
	mm.refresh_resume()
	check(not mm.resume_row.visible, "älter als 12 h: nichts anzubieten")
	write_snapshot(SAVE, now, 60, game_dict)
	mm.refresh_resume()
	(mm.resume_row.find_child("PartieVerwerfen", true, false) as Button).pressed.emit()
	await frames(1)
	var vb := mm.find_child("Verwerfen", true, false)
	check(vb is ConfirmBox, "Verwerfen fragt nach")
	check(mm.on_back() and TableSource.has_saved(SAVE), "Zurück: Datei bleibt")
	await frames(1)
	(mm.resume_row.find_child("PartieVerwerfen", true, false) as Button).pressed.emit()
	await frames(1)
	(mm.find_child("Verwerfen", true, false).find_child("Ja", true, false) as Button).pressed.emit()
	await frames(1)
	check(not TableSource.has_saved(SAVE) and not mm.resume_row.visible, "verworfen: Datei weg, Zeile weg")
	# Nach „Partie fortsetzen“ gehört der HostSwitch dem Tisch: Das Hauptmenü löst seine Signale (sonst zweiter Tisch bei jedem Wechsel)
	var hs := HostSwitch.new()
	hs.auto_process = false
	mm.add_child(hs)
	mm._resume_sw = hs
	mm._hook_resume(hs)
	var keep_nav := mm.nav
	mm.nav = null
	hs.swapped.emit(null, "")
	mm.nav = keep_nav
	check(mm._resume_sw == null and not hs.swapped.is_connected(mm._on_resume_swapped) and not hs.state_changed.is_connected(mm._on_resume_state)
		and not hs.confirm_needed.is_connected(mm._on_resume_confirm), "nach dem Wechsel: Hauptmenü hört nicht mehr auf den HostSwitch")
	hs.free()
	# Gerätetest 1.6.1: „Partie fortsetzen“, ein anderer Gastgeber antwortet. Der echte Ablauf (_finish_guest) zieht mit dem Gast-Tisch
	# um (attach meldet dabei „off“) und meldet erst danach swapped – das Hauptmenü darf „off“ nicht als Abbruch nehmen.
	var depth_before := nav.depth()
	var hs2 := HostSwitch.new()
	hs2.auto_process = false
	hs2.save_path = SAVE
	mm.add_child(hs2)
	mm._resume_sw = hs2
	mm._hook_resume(hs2)
	hs2.state = "resuming"
	var gct := GameStarter.client()
	gct.backup_path = SAVE
	gct.persist_backup = false
	gct.auto_process = false
	hs2.add_child(gct)
	hs2._flow_ct = gct
	var states: Array = []
	hs2.state_changed.connect(func(st: String) -> void: states.append(st))
	hs2._finish_guest("Anna führt das Spiel inzwischen. Du spielst als Gast weiter.")
	await frames(2)
	check(states.has("off"), "Übernahme als Gast meldet unterwegs „off“ (%s)" % [states])
	check(nav.top() is TableScreen and (nav.top() as TableScreen).source == gct and nav.depth() == depth_before + 1,
		"Fortsetzen als Gast: Tisch kommt obenauf (oben %s, Tiefe %d → %d)" % [nav.top(), depth_before, nav.depth()])
	check(mm._resume_sw == null and not hs2.swapped.is_connected(mm._on_resume_swapped) and hs2.get_parent() == gct,
		"Fortsetzen als Gast: HostSwitch gehört dem Gast-Tisch, Hauptmenü hört nicht mehr zu")
	check(mm.find_child("FortsetzenWarten", true, false) == null, "Fortsetzen als Gast: „Verbinde …“ ist zu")
	if nav.top() is TableScreen:
		var tts := nav.top() as TableScreen
		tts.leaving = true
		nav.pop(false)
		await frames(2)
	elif gct.get_parent() == null:
		gct.free()
	# Abbruch bleibt Abbruch: hängt der HostSwitch noch am Hauptmenü, beendet „off“ den Ablauf
	var hs3 := HostSwitch.new()
	hs3.auto_process = false
	mm.add_child(hs3)
	mm._resume_sw = hs3
	mm._hook_resume(hs3)
	hs3.state = "resuming"
	hs3.cancel()
	await frames(1)
	check(mm._resume_sw == null and (not is_instance_valid(hs3) or hs3.is_queued_for_deletion()), "Abbrechen: Ablauf zu")
	TableSource.clear_saved(SAVE)
	print("RESULT: %d ok%s" % [ok, ", FEHLER" if failed else ""])
	await CleanExit.finish(self, 1 if failed else 0)
