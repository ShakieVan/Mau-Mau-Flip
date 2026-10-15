extends "res://tests/handover_wlan_ui_kit.gd"
# Mau-Mau Flip (Beta 1.6.2, Gastgeber-Übergabe im WLAN und Spiel-WLAN, docs/module/uebergabe.md 10.2, 10.7, 10.8, 10.10, 10.13–10.15):
# Oberfläche nur mit Doubles (handover_wlan_ui_kit.gd) – ohne Server, ohne Suche auf UDP, ohne Android (parallele Spur von build.ps1).
#   G  Gastgeber-Tisch: GameWifiWatch entsteht (Meta am HostTable, foreign_ap), Einladefeld zeigt nur den Watch-Zustand (QR des
#      Spiel-WLANs, „schließen“ geht an den Watch, Fehlschlag von auto_open → „Neu öffnen“), Anfrage des HostSwitch nach einem eigenen
#      Spiel-WLAN bzw. lost("foreign") → „Dazuholen“ + auto_open.
#   A  Auswahldialog: Lena wählbar mit „Muss das Spiel-WLAN erlauben.“, Ben ausgegraut, Warnzeile „Alle müssen danach …“ (rot, nachts hell).
#   S  „Mitspieler“ → „Am Tisch“: Kim wartet, Knopf „Auf den Platz von Ben setzen“ mit Rückfrage → seat_assign(Kim, Ben).
#   W  App-Gast: Streifen scan „Spiel-WLAN von Hanna ist weg.“ mit „Neues Spiel-WLAN bei Anna – QR-Code scannen“ → Tisch ohne bye
#      zu, JoinScreen.rejoin(gid, Lena); Rückfrage mit Warnzeile „Nur wenn Anna nicht übernimmt …“; im WLAN „Suche den neuen
#      Gastgeber …“; eben selbst mit qr abgegeben (Nachtest 1.6.2): „Einen Moment – der Gastgeber wechselt.“ mit QR-Knopf, ohne
#      „Spiel als Gastgeber fortsetzen“; Raum abgelaufen: „In neuem Raum fortsetzen“ / „Mit neuem Code beitreten“; „Partie verlassen?“ warnt, wenn dieses
#      Handy als Gast das Spiel-WLAN führt.
#   M  Hauptmenü: eigene Partie im Spiel-WLAN → „Spiel-WLAN neu öffnen“ / „Beim neuen Gastgeber scannen“ (→ rejoin); Raum abgelaufen
#      → „In neuem Raum fortsetzen“ / „Mit neuem Code beitreten“.
#   godot_run.ps1 -Script res://tests/test_ui_handover_wlan.gd -Headless
# Kontrollbilder: test_ui_handover_wlan_shot.gd

const CleanExit := preload("res://tests/clean_exit.gd")
const SAVE := "user://test_ui_handover_wlan_partie.json"

var ok := 0
var failed := false
var nav: RecNav


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


func run() -> void:
	GameStarter.test_speed = 0.0
	root.size = Vector2i(1600, 720)
	nav = RecNav.new()
	nav.autostart = false
	root.add_child(nav)
	nav.push(AppScreen.new(), false)          # Boden des Stapels (pop entfernt nur darüber)
	await frames(3)
	await host_part()
	await guest_part()
	await menu_part()
	TableScreen.wifi_watch_factory = Callable()
	TableSource.clear_saved(SAVE)
	if failed:
		print("FAIL: test_ui_handover_wlan")
	else:
		print("RESULT: %d ok" % ok)
	await CleanExit.finish(self, 1 if failed else 0)


func _labels(n: Node) -> Array:
	return n.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)


# --- G, A, S: Gastgeber ---
func host_part() -> void:
	var watches: Array = []
	TableScreen.wifi_watch_factory = func(h: HostTable) -> Node:
		var w := FakeWatch.new()
		w.host = h
		w.state = {"status": "on", "ssid": "MMF-4821", "password": "katze123", "security": "wpa2"}
		w.address = "192.168.49.1"
		watches.append(w)
		return w
	var ht := make_host(true)
	var ts := TableScreen.create(ht)
	nav.push(ts, false)
	await frames(3)
	ts._sub_next_ms = 1 << 60
	check(ts.is_net_host() and watches.size() == 1 and ts.wifi_watch() == watches[0], "G: Gastgeber-Tisch legt einen GameWifiWatch an")
	var w: FakeWatch = watches[0] if not watches.is_empty() else null
	if w == null:
		return
	check(GameWifiPanel.find_watch(ht) == w, "G: Watch als Meta am HostTable")
	check(not w.foreign_ap, "G: eigenes Spiel-WLAN → foreign_ap aus")
	ht.set("_ap_seat", 1)
	ts._sync_foreign_ap()
	check(w.foreign_ap, "G: Spiel-WLAN eines Mitspielers → foreign_ap an")
	ht.set("_ap_seat", 0)
	ts._sync_foreign_ap()
	# Einladefeld: nur Anzeige des Watch-Zustands
	ts.open_seat_manager("dazuholen")
	await frames(2)
	check(ts.is_seat_manager_open(), "G: „Mitspieler“ offen")
	var panel := ts._seat_mgr.invite.wifi if ts.is_seat_manager_open() else null
	check(panel != null and panel.watch == w and panel.mode == "game_wifi" and panel.qr_text() != "" and panel.address == "192.168.49.1",
		"G: Einladefeld zeigt das Spiel-WLAN des Watch (%s, %s)" % [panel.mode if panel else "?", panel.address if panel else "?"])
	panel.close_wifi()
	check(w.closed == 1, "G: „Spiel-WLAN schließen“ geht an den Watch")
	w.state = {"status": "off"}
	w.address = ""
	w.auto_state = "failed"
	w.auto_error = "incompatible_mode"
	w.auto_tries = 4
	panel._read_watch()
	panel.refresh_net()
	check(panel.mode == "problem" and panel.problem == "incompatible_mode", "G: auto_open gescheitert → Fehlerhinweis (%s)" % panel.mode)
	panel.dismiss_problem()
	panel._read_watch()
	panel.refresh_net()
	check(panel.mode != "problem", "G: „Zurück“ – derselbe Fehlschlag kommt nicht wieder")
	ts._seat_mgr.close()
	await frames(2)
	# Anfrage des HostSwitch nach einem eigenen Spiel-WLAN (Übernahme) bzw. lost("foreign")
	ts._switch.game_wifi_pending = true
	ts._sub_next_ms = 0
	await frames(2)
	ts._sub_next_ms = 1 << 60
	check(w.opened == 1 and ts.is_seat_manager_open() and ts._seat_mgr.page == "dazuholen" and ts._seat_mgr.invite.way() == "wlan",
		"G: Übernahme mit Spiel-WLAN → „Dazuholen“ und auto_open (%d)" % w.opened)
	ts._seat_mgr.close()
	await frames(1)
	w.lost.emit("foreign")
	await frames(1)
	check(w.opened == 2 and ts.is_seat_manager_open(), "G: fremdes Spiel-WLAN weg → eigenes öffnen")
	ts._seat_mgr.close()
	await frames(1)
	check(TableScreen.note_is(I18n.t("Neuer Raum %s. Schick den anderen den Link – sie kommen damit auf ihre Plätze.") % "KATZE-42",
		"Neuer Raum %s. Schick den anderen den Link – sie kommen damit auf ihre Plätze.") and not TableScreen.note_is("Neuer Raum", "Neuer Raum %s. Schick den anderen den Link – sie kommen damit auf ihre Plätze."),
		"G: Meldung „Neuer Raum …“ erkannt")

	# --- A: Auswahldialog
	var cands := ts.handover_candidates()
	var lena: Dictionary = cands[0] if not cands.is_empty() else {}
	check(cands.size() == 2 and str(lena.get("reason", "?")) == "" and str(lena.get("note", "")) == "Muss das Spiel-WLAN erlauben.",
		"A: Lena wählbar mit Hinweis (%s)" % [cands])
	check(cands.size() == 2 and str(cands[1].reason) != "", "A: Ben (Browser) ausgegraut")
	check(ts.handover_warnings(-1) == ["Alle müssen danach einen neuen QR-Code scannen."], "A: Warnzeile Spiel-WLAN (%s)" % [ts.handover_warnings(-1)])
	ts.open_host_pick()
	await frames(2)
	var dlg := ts._pick
	check(dlg != null and dlg.find_child("Hinweis", true, false) != null and not (dlg.find_child("Platz_1", true, false) as Button).disabled,
		"A: Hinweiszeile bei Lena, wählbar")
	check(dlg != null and (dlg.find_child("Platz_2", true, false) as Button).disabled, "A: Ben ausgegraut")
	var warn_box := dlg.find_child("Warnungen", true, false) as Control if dlg != null else null
	var warn_lines := warn_box.get_children() if warn_box != null else []
	check(warn_box != null and warn_box.visible and warn_lines.size() == 1
		and (warn_lines[0] as Label).text == "Alle müssen danach einen neuen QR-Code scannen."
		and (warn_lines[0] as Label).get_theme_color("font_color") == UiPalette.ALERT, "A: Warnzeile rot über den Knöpfen")
	(dlg.find_child("Platz_1", true, false) as Button).pressed.emit()
	await frames(1)
	dlg.set_night(true)
	check((warn_box.get_child(0) as Label).get_theme_color("font_color") != UiPalette.ALERT, "A: nachts helleres Rot")
	# Warnzeilen je Ziel aus dem Provider
	var rows := [{"seat": 1, "name": "Lena", "kind": "human", "reason": ""}, {"seat": 2, "name": "Ben", "kind": "human", "reason": ""}]
	var d2 := HostPickDialog.open(ts._top, func() -> Array: return rows,
		func(s: int) -> Array: return ["WLAN-Mitspieler brauchen dann Internet."] if s == 2 else [])
	await frames(1)
	var wb2 := d2.find_child("Warnungen", true, false) as Control
	check(not wb2.visible, "A: ohne Wahl keine Warnzeile")
	(d2.find_child("Platz_2", true, false) as Button).pressed.emit()
	await frames(1)
	check(wb2.visible and wb2.get_child_count() == 1, "A: Online-Ziel → „WLAN-Mitspieler brauchen dann Internet.“")
	(d2.find_child("Platz_1", true, false) as Button).pressed.emit()
	await frames(2)
	check(not wb2.visible, "A: anderes Ziel → Warnzeile weg")
	d2.close()
	dlg.close()
	await frames(1)

	# --- S: Auf den Platz von Ben setzen
	ts.open_seat_manager("tisch")
	await frames(2)
	var sm := ts._seat_mgr
	check(sm != null and sm.assign_seats() == [2], "S: freier Menschenplatz Ben (%s)" % [sm.assign_seats() if sm else []])
	var ab := sm.find_child("AufPlatz2", true, false) as Button if sm != null else null
	check(ab != null and ab.text == "Auf den Platz von Ben setzen" and sm.find_child("Wartender5", true, false) != null,
		"S: Knopf unter Kims Zeile (%s)" % (ab.text if ab else "?"))
	check(sm.find_child("AufPlatz1", true, false) == null, "S: Lena ist verbunden – kein Knopf")
	ab.pressed.emit()
	await frames(1)
	var box := sm._confirm
	check(box != null and _labels(box).has("Auf den Platz von Ben setzen") and _labels(box).has("Kim spielt dann mit den Karten von Ben weiter."),
		"S: Rückfrage (%s)" % [_labels(box) if box else []])
	check(box != null and (box.find_child("Ja", true, false) as Button).text == "Hinsetzen", "S: Knopf „Hinsetzen“")
	(box.find_child("Ja", true, false) as Button).pressed.emit()
	await frames(1)
	check(ht.assigned == [[5, 2]], "S: seat_assign(Kim, Ben) (%s)" % [ht.assigned])
	ht.set("_frozen", true)
	check(sm.assign_seats().is_empty(), "S: eingefroren → keine Platzwahl")
	ht.set("_frozen", false)
	sm.close()
	await frames(1)
	ts.leaving = true
	nav.pop(false)
	await frames(2)
	TableScreen.wifi_watch_factory = Callable()
	if is_instance_valid(ts):
		ts.queue_free()
	await frames(1)


# --- W: App-Gast ---
func guest_part() -> void:
	var now := int(Time.get_unix_time_from_system())
	var gd := game_dict()
	var ct := guest_table(guest_backup(gd, 0, now, true))
	var ts := TableScreen.create(ct)
	nav.push(ts, false)
	await frames(3)
	var real_sw := ts._switch
	real_sw.auto_process = false
	var sw := FakeSwitch.new()
	sw.auto_process = false
	sw.source = ct
	ts._switch = sw
	sw.state = "scan"
	await frames(2)
	check(ts._conn.visible and ts._conn_label.text == "Spiel-WLAN von Hanna ist weg.", "W: Streifen scan (%s)" % ts._conn_label.text)
	check(ts._conn_scan.visible and ts._conn_scan.text == "Neues Spiel-WLAN bei Anna – QR-Code scannen", "W: Knopf scannen (%s)" % ts._conn_scan.text)
	check(ts._conn_take.visible and not ts._conn_newroom.visible and not ts._conn_newcode.visible, "W: dazu „Spiel als Gastgeber fortsetzen“")
	ts.ask_continue_as_host()
	await frames(1)
	var notes := _labels(ts._confirm) if ts._confirm != null else []
	check(notes.has("Nur wenn Anna nicht übernimmt – sonst gibt es zwei Spiele."), "W: Warnzeile „Nur wenn Anna …“ (%s)" % [notes])
	ts._confirm.cancel()
	await frames(1)
	# Nachtest 1.6.2: eben selbst mit qr abgegeben (handed_off) – warten statt „Spiel-WLAN von … ist weg.“, QR-Knopf bleibt, keine Übernahme
	sw.set("_handoff_until", sw.now_wall() + 60000)
	await frames(2)
	check(sw.handed_off() and ts._conn.visible and ts._conn_label.text == "Einen Moment – der Gastgeber wechselt.",
		"W: abgetreten – „Einen Moment …“ (%s)" % ts._conn_label.text)
	check(ts._conn_scan.visible and ts._conn_scan.text == "Neues Spiel-WLAN bei Anna – QR-Code scannen" and not ts._conn_take.visible,
		"W: abgetreten – QR-Knopf, ohne „Spiel als Gastgeber fortsetzen“")
	sw.set("_handoff_until", 0)
	await frames(2)
	check(ts._conn_label.text == "Spiel-WLAN von Hanna ist weg." and ts._conn_take.visible, "W: Wartezeit vorbei – scan wie nach einem Ausfall")
	# im WLAN: Suche statt „warte …“
	sw.state = "missing"
	await frames(2)
	check(ts._conn_label.text == "Gastgeber antwortet nicht – warte …", "W: ohne Verbindung „warte …“ (%s)" % ts._conn_label.text)
	var nc := NetClient.new()
	nc.auto_poll = false
	ct.client = nc
	await frames(2)
	check(ts._conn_label.text == "Suche den neuen Gastgeber …" and not ts._conn_scan.visible, "W: WLAN-Gast sucht (%s)" % ts._conn_label.text)
	ct.client = null
	nc.free()
	# Raum abgelaufen
	sw.state = "gone"
	await frames(2)
	check(ts._conn_newroom.visible and ts._conn_newcode.visible and ts._conn_menu.visible and not ts._conn_scan.visible,
		"W: Raum abgelaufen – neuer Raum, neuer Code, Zum Menü")
	ts._conn_newroom.pressed.emit()
	check(sw.new_rooms == 1, "W: „In neuem Raum fortsetzen“ → resume_new_room")
	sw.state = "watch"
	await frames(2)
	check(not ts._conn_newroom.visible and not ts._conn_newcode.visible and not ts._conn_scan.visible
		and not ts._conn_label.text.begins_with("Der Online-Raum"), "W: Lage vorbei – Knöpfe des Wächters weg (%s)" % ts._conn_label.text)
	# „Partie verlassen?“ ohne / mit eigenem Spiel-WLAN
	ts.on_back()
	await frames(1)
	check(ts._confirm != null and not _labels(ts._confirm).has("Dein Spiel-WLAN geht dann zu – alle müssen einen neuen QR-Code scannen."),
		"W: Verlassen ohne eigenes Spiel-WLAN: keine Warnzeile")
	ts._confirm.queue_free()
	ts._confirm = null
	ct.backup = guest_backup(gd, 1, now)
	check(ts.leads_guest_wifi(), "W: Lena führt das Spiel-WLAN")
	ts.on_back()
	await frames(1)
	check(ts._confirm != null and _labels(ts._confirm).has("Dein Spiel-WLAN geht dann zu – alle müssen einen neuen QR-Code scannen."),
		"W: Verlassen mit eigenem Spiel-WLAN: Warnzeile")
	ts._confirm.queue_free()
	ts._confirm = null
	ct.backup = guest_backup(gd, 0, now, true)
	# „Mit neuem Code beitreten“: Tisch ohne bye zu, Beitrittsseite
	nav.record = true
	sw.state = "gone"
	await frames(2)
	ts._conn_newcode.pressed.emit()
	check(ts.leaving and ct._leaving and nav.log.size() == 3 and nav.log[0] == ["home"] and nav.log[2][1] is JoinScreen
		and (nav.log[2][1] as JoinScreen).rejoin_gid == "", "W: „Mit neuem Code beitreten“ → Beitrittsseite (%s)" % [nav.log])
	nav.drop_log()
	# scan → JoinScreen.rejoin(gid, Name aus der Sicherung)
	ts.leaving = false
	sw.state = "scan"
	ts._switch = sw
	await frames(2)
	ts.scan_new_wifi()
	var js: JoinScreen = nav.log[0][1] if nav.log.size() == 1 and nav.log[0][0] == "replace" and nav.log[0][1] is JoinScreen else null
	check(js != null and js.rejoin_gid == GID and js.rejoin_name == "Lena" and js.join_name() == "Lena",
		"W: Scannen → JoinScreen.rejoin(%s, %s)" % [js.rejoin_gid if js else "?", js.rejoin_name if js else "?"])
	check(ts.leaving and ct.client == null and not ct.backup.is_empty(), "W: Gast-Tisch ohne Verlassen zu, Sicherung bleibt")
	nav.drop_log()
	nav.record = false
	sw.free()
	nav.pop(false)
	await frames(2)
	if is_instance_valid(ts):
		ts.queue_free()
	await frames(1)


# --- M: Hauptmenü ---
func menu_part() -> void:
	var now := int(Time.get_unix_time_from_system())
	var gd := game_dict()
	var mm := MainMenuScreen.new()
	mm.save_path = SAVE
	mm.now_unix = now
	nav.push(mm, false)
	await frames(3)
	# eigene Partie im Spiel-WLAN (Gastgeber-Datei)
	var d := guest_backup(gd, 0, now)
	d["role"] = "host"
	d["my_seat"] = -1
	TableSource.write_saved(SAVE, d)
	check(mm.resume_in_game_wifi({"role": "host", "age_min": 3}), "M: Gastgeber-Datei mit wlan.ap → Rückfrage Spiel-WLAN")
	check(not mm.resume_in_game_wifi({"role": "host", "age_min": 3, "ap": false}), "M: ap:false vom HostSwitch gilt")
	var sw := FakeSwitch.new()
	sw.auto_process = false
	mm.add_child(sw)
	mm._resume_sw = sw
	mm._hook_resume(sw)
	sw._saved = d
	sw.state = "confirm"
	mm._on_resume_confirm({"role": "host", "age_min": 3, "warnings": [], "ap": true})
	await frames(1)
	var box := mm.find_child("FortsetzenRueckfrage", true, false) as ConfirmBox
	check(box != null and (box.find_child("Ja", true, false) as Button).text == "Spiel-WLAN neu öffnen"
		and box.find_child("BeimNeuenScannen", true, false) != null, "M: „Spiel-WLAN neu öffnen“ · „Beim neuen Gastgeber scannen“")
	nav.record = true
	(box.find_child("BeimNeuenScannen", true, false) as Button).pressed.emit()
	await frames(1)
	var js: JoinScreen = nav.log[1][1] if nav.log.size() == 2 and nav.log[1][1] is JoinScreen else null
	check(js != null and nav.log[0][1] is WlanScreen and js.rejoin_gid == GID and js.rejoin_name == "Hanna",
		"M: Scannen → Beitrittsseite rejoin (%s)" % [nav.log])
	check(mm._resume_sw == null and (not is_instance_valid(sw) or sw.is_queued_for_deletion() or sw.state == "off"), "M: Ablauf beendet, Datei bleibt")
	check(TableSource.has_saved(SAVE), "M: Datei bleibt")
	nav.drop_log()
	# Raum abgelaufen
	var sw2 := FakeSwitch.new()
	sw2.auto_process = false
	mm.add_child(sw2)
	mm._resume_sw = sw2
	mm._hook_resume(sw2)
	sw2._saved = guest_backup(gd, 0, now, true)
	sw2.last_error = "Der Online-Raum ist abgelaufen. Die Partie lässt sich nicht mehr fortsetzen."
	sw2._go("expired")
	await frames(1)
	var ex := mm.find_child("FortsetzenAbgelaufen", true, false) as ConfirmBox
	check(ex != null and ex.find_child("NeuerRaum", true, false) != null and ex.find_child("NeuerCode", true, false) != null,
		"M: Raum abgelaufen – „In neuem Raum fortsetzen“ und „Mit neuem Code beitreten“")
	(ex.find_child("NeuerRaum", true, false) as Button).pressed.emit()
	await frames(1)
	check(sw2.new_rooms == 1 and mm._resume_sw == sw2, "M: „In neuem Raum fortsetzen“ → resume_new_room, Ablauf läuft weiter")
	sw2._go("taking")
	sw2._go("expired")
	await frames(1)
	ex = mm.find_child("FortsetzenAbgelaufen", true, false) as ConfirmBox
	(ex.find_child("NeuerCode", true, false) as Button).pressed.emit()
	await frames(1)
	check(nav.log.size() == 2 and nav.log[1][1] is JoinScreen and (nav.log[1][1] as JoinScreen).rejoin_gid == "" and mm._resume_sw == null,
		"M: „Mit neuem Code beitreten“ → Beitrittsseite (%s)" % [nav.log])
	nav.drop_log()
	nav.record = false
	# ohne neuen Raum (kein Vermittler im Stand): nur „Mit neuem Code beitreten“
	var sw3 := HostSwitch.new()
	sw3.auto_process = false
	mm.add_child(sw3)
	mm._resume_sw = sw3
	mm._hook_resume(sw3)
	sw3._saved = guest_backup(gd, 0, now)
	sw3._go("expired")
	await frames(1)
	ex = mm.find_child("FortsetzenAbgelaufen", true, false) as ConfirmBox
	check(ex != null and ex.find_child("NeuerRaum", true, false) == null and ex.find_child("NeuerCode", true, false) != null,
		"M: ohne Vermittler kein „In neuem Raum fortsetzen“")
	check(mm.on_back() and mm._resume_sw == null, "M: Zurück schließt")
	await frames(1)
	nav.pop(false)
	await frames(1)
