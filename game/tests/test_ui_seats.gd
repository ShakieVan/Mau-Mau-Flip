extends SceneTree
# Mitspieler dazuholen und entfernen, Oberfläche des Gastgebers (Beta 1.4.2, docs/module/dazuholen.md 4), headless mit echten
# Bildschirmen und echtem Netz über 127.0.0.1:
#   M   ☰-Menü des Netz-Gastgebers mit „Mitspieler dazuholen“ / „Mitspieler entfernen“ (Solo ohne), Feld „Mitspieler“ öffnet das
#       Einladefeld und öffnet die Warteliste (join_open), Schließen macht sie zu.
#   W   App-Gast meldet sich mitten in der Partie: Warteliste beim Gast („Du bist auf der Warteliste …“), beim Gastgeber springt das
#       Feld auf „Am Tisch“; ▲▼ rücken ihn, Rückfrage „… setzt sich zwischen … und bekommt … Karten.“, danach sitzt er am Tisch
#       (Gast: TableScreen mit richtigem Platz; Gastgeber: ein Gegnerplatz mehr).
#   B   Computergegner per Platzhalter dazuholen und über ✕ mit Rückfrage wieder herausnehmen (Platzknoten verschwinden).
#   S   Gast getrennt: sofort die Leiste mit „Computer übernimmt“ / „Aus dem Spiel nehmen“; Herausnehmen mit Rückfrage, auch im
#       großen Modus (Liste); danach keine Leiste mehr.
#   godot_run.ps1 -Script res://tests/test_ui_seats.gd -Headless -Timeout 150

const CleanExit := preload("res://tests/clean_exit.gd")

var ok := 0
var failed := false
var nav: ScreenNav
var nav2: ScreenNav


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


func wait(t: float) -> void:
	await create_timer(t).timeout


func _wait_for(cond: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not bool(cond.call()) and Time.get_ticks_msec() < deadline:
		await frames(1)
	return bool(cond.call())


func run() -> void:
	GameStarter.test_speed = 0.0
	var app := UiApp.app()
	var rules_backup: Variant = UiApp.setting("regeln", {})
	var big_backup: Variant = UiApp.setting("grosser_modus", false)
	root.size = Vector2i(1600, 720)
	nav = ScreenNav.new()
	nav.autostart = true
	root.add_child(nav)
	await frames(3)
	await solo_menu()
	await net_flow()
	if app != null:
		app.settings.set_value("regeln", rules_backup if rules_backup is Dictionary else {})
		app.settings.set_value("grosser_modus", big_backup)
	if failed:
		print("FAIL: test_ui_seats")
	else:
		print("RESULT: %d ok" % ok)
	await CleanExit.finish(self, 1 if failed else 0)


func _menu_keys(ts: TableScreen) -> Array:
	var out: Array = []
	if ts._ingame_menu == null:
		return out
	for b in ts._ingame_menu.find_children("Wahl_*", "Button", true, false):
		out.append(str(b.name).trim_prefix("Wahl_"))
	return out


# Solo: kein „Mitspieler“ im Menü
func solo_menu() -> void:
	var players := [{"name": "Du", "kind": "human"}, {"name": "Minka", "kind": "bot"}]
	var src := GameStarter.local("solo", RuleConfig.new(), players, 1)
	var ts := TableScreen.create(src, func() -> void: src.start())
	nav.push(ts, false)
	await wait(0.5)
	ts.open_menu()
	await frames(2)
	var keys := _menu_keys(ts)
	check(keys.has("einstellungen") and not keys.has("dazuholen") and not ts.is_net_host(), "M: Solo ohne Mitspieler-Einträge (%s)" % [keys])
	ts._ingame_menu.close()
	ts._leave_now()
	await wait(0.3)


func _guest_nav() -> ScreenNav:
	var n := ScreenNav.new()
	n.autostart = false
	root.add_child(n)
	return n


func net_flow() -> void:
	UiApp.app().settings.set_value("regeln", RuleConfig.new().to_dict())
	UiApp.app().settings.set_value("grosser_modus", false)
	nav.push(HostLobbyScreen.new(), false)
	await frames(3)
	var lobby := nav.top() as HostLobbyScreen
	check(lobby != null and lobby.host != null and lobby.host.port() > 0, "Lobby des Gastgebers offen")
	if lobby == null or lobby.host == null or lobby.host.port() <= 0:
		return
	var host := lobby.host
	host.autosave = false
	var port := host.port()
	host.add_bot()
	host.add_bot()
	await wait(0.2)
	lobby.start_game()
	check(await _wait_for(func() -> bool: return nav.top() is TableScreen and host.game != null, 4.0), "Partie läuft")
	var hts := nav.top() as TableScreen
	if hts == null:
		return
	await wait(0.4)
	check(hts.table._seats.size() == 2, "zwei Gegnerplätze (%d)" % hts.table._seats.size())
	# --- M: Menü und Feld
	hts.open_menu()
	await frames(2)
	var keys := _menu_keys(hts)
	check(keys.slice(0, 2) == ["dazuholen", "entfernen"] and keys.has("einstellungen"), "M: Menü des Gastgebers (%s)" % [keys])
	hts._ingame_menu._choose("dazuholen")
	await frames(2)
	var sm := hts._seat_mgr
	check(hts.is_seat_manager_open() and sm.page == "dazuholen" and sm.invite != null and sm.invite.is_visible_in_tree(), "M: Feld „Mitspieler“ mit Einladefeld")
	check(host.session.join_open, "M: Warteliste offen, solange das Feld offen ist")
	check(not hts._sub_hint.visible, "M: keine Leiste ohne Abwesende")
	# --- W: Gast mitten in der Partie
	nav2 = _guest_nav()
	await frames(2)
	nav2.push(JoinScreen.new(), false)
	await frames(2)
	var js := nav2.top() as JoinScreen
	js.join("127.0.0.1", port)
	check(await _wait_for(func() -> bool: return not host.waiting_ids().is_empty(), 6.0), "W: Gast auf der Warteliste")
	var gid := int(host.waiting_ids()[0]) if not host.waiting_ids().is_empty() else -1
	check(await _wait_for(func() -> bool: return js._lobby_hint.text.begins_with("Du bist auf der Warteliste"), 3.0) and not js._ready_btn.visible,
		"W: Gast sieht die Warteliste (%s)" % js._lobby_hint.text)
	check(await _wait_for(func() -> bool: return sm.page == "tisch", 2.0), "W: Feld springt auf „Am Tisch“")
	await frames(2)
	check(sm._order.size() == 4 and int(sm._order[3]) == gid and sm.place_of(gid) == 3, "W: Neuer zuerst am Ende (%s)" % [sm._order])
	var row := sm._list.find_child("Wartet%d" % gid, true, false)
	check(row != null and row.find_child("AnDenTisch", true, false) != null, "W: Zeile mit „An den Tisch“")
	sm.move(gid, -1)
	sm.move(gid, -1)
	check(sm.place_of(gid) == 1, "W: zwei Plätze nach vorn (%d)" % sm.place_of(gid))
	var nb := sm.neighbours(gid)
	sm.ask_seat(gid)
	await frames(2)
	check(sm.is_confirm_open(), "W: Rückfrage")
	var txt := ""
	for l in sm._confirm.find_children("*", "Label", true, false):
		txt += (l as Label).text + " | "
	check(txt.contains("zwischen %s und %s" % nb) and txt.contains("Karten"), "W: Rückfrage nennt Platz und Karten (%s)" % txt)
	await _until_host_turn(host)
	sm._confirm._answer(true)
	check(await _wait_for(func() -> bool: return host.seats.size() == 4, 4.0), "W: Gast sitzt (Plätze %d)" % host.seats.size())
	check(await _wait_for(func() -> bool: return nav2.top() is TableScreen, 5.0), "W: Gast am Tisch")
	var gts := nav2.top() as TableScreen
	var gseat := host._seat_ids.find(gid)
	check(gseat == 1, "W: am gewählten Platz (%d)" % gseat)
	if gts != null:
		check(await _wait_for(func() -> bool: return int(gts.view.get("seat", -1)) == gseat and not (gts.view.get("hand", []) as Array).is_empty(), 4.0),
			"W: Gast sieht seinen Platz und Karten (%d)" % int(gts.view.get("seat", -1)))
	check(await _wait_for(func() -> bool: return hts.table._seats.size() == 3 and not hts.table.director.is_busy(), 12.0),
		"W: Gastgeber zeigt drei Gegner (%d, busy %s, Rückstand %d, state %s, dran %d)" % [hts.table._seats.size(), hts.table.director.is_busy(), hts.table.director.backlog(), host.game.state, host.game.current])
	var names := []
	for s in hts.table._seats:
		names.append([int(s), (hts.table._seats[s] as OpponentSeat).seat, (hts.table._seats[s] as OpponentSeat).player_name()])
	var consistent := true
	for e in names:
		consistent = consistent and int(e[0]) == int(e[1]) and str(e[2]) == host.seat_name(int(e[0]))
	check(consistent, "W: Platzknoten passen zu den Plätzen (%s)" % [names])
	# --- B: Computergegner dazu und wieder heraus
	sm.add_bot_slot()
	await frames(2)
	var bid := int(sm._bots[0]) if not sm._bots.is_empty() else 0
	check(sm._bots.size() == 1 and sm._order.has(bid), "B: Platzhalter in der Liste")
	sm.ask_seat(bid)
	await frames(1)
	await _until_host_turn(host)
	sm._confirm._answer(true)
	check(await _wait_for(func() -> bool: return host.seats.size() == 5, 4.0) and sm._bots.is_empty(), "B: Computergegner sitzt")
	check(await _wait_for(func() -> bool: return hts.table._seats.size() == 4 and not hts.table.director.is_busy(), 12.0), "B: vier Gegner")
	var bot_seat := host.seats.size() - 1
	await frames(2)
	var rm := sm._list.find_child("Platz%d" % bot_seat, true, false)
	check(rm != null and rm.find_child("Entfernen", true, false) != null, "B: ✕ beim Computergegner")
	check(sm._list.find_child("Platz%d" % host.host_seat, true, false).find_child("Entfernen", true, false) == null, "B: Gastgeber ohne ✕")
	sm.ask_remove_seat(bot_seat)
	await frames(1)
	check(sm.is_confirm_open(), "B: Rückfrage beim Herausnehmen")
	await _until_host_turn(host)
	sm._confirm._answer(true)
	check(await _wait_for(func() -> bool: return host.seats.size() == 4, 4.0), "B: Computergegner heraus")
	check(await _wait_for(func() -> bool: return hts.table._seats.size() == 3 and not hts.table.director.is_busy(), 12.0), "B: wieder drei Gegner")
	sm.close()
	await frames(2)
	check(not hts.is_seat_manager_open() and not host.session.join_open, "M: Schließen macht die Warteliste zu")
	# --- S: Gast weg → Leiste, Herausnehmen im großen Modus
	UiApp.app().settings.set_value("grosser_modus", true)
	await frames(3)
	check(hts.table.big, "S: großer Modus an")
	nav2.queue_free()
	nav2 = null
	check(await _wait_for(func() -> bool: return hts._sub_hint.visible, 4.0) and hts._sub_hint_label.text == "%s ist getrennt" % host.seat_name(gseat)
			and hts._sub_btn.is_visible_in_tree() and hts._kick_btn.is_visible_in_tree(), "S: sofort beide Knöpfe (%s)" % hts._sub_hint_label.text)
	check(Rect2(0, 0, 1600, 720).encloses(hts._sub_hint.get_global_rect()), "S: Leiste im Bild (%s)" % hts._sub_hint.get_global_rect())
	hts.ask_kick()
	await frames(1)
	check(hts._confirm != null and is_instance_valid(hts._confirm), "S: Rückfrage")
	await _until_host_turn(host)
	hts._confirm._answer(true)
	check(await _wait_for(func() -> bool: return host.seats.size() == 3, 4.0), "S: Gast heraus")
	check(await _wait_for(func() -> bool: return hts.table._seats.size() == 2 and not hts.table.director.is_busy(), 12.0), "S: zwei Gegner in der Liste")
	await wait(0.3)
	check(not hts._sub_hint.visible, "S: Leiste weg")
	hts._leave_now()
	await wait(0.5)


# Aufträge wirken zwischen zwei Zügen: Rückfragen erst bestätigen, wenn das Spiel in „turn“ steht (sonst warten sie; das prüft der Kern)
func _until_host_turn(host: HostTable) -> void:
	await _wait_for(func() -> bool: return host.game != null and host.game.state == "turn", 4.0)
