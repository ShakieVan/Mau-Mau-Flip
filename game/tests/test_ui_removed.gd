extends SceneTree
# Meldungen beim Dazuholen/Entfernen (Gerätetest 1.4.2), headless mit echten Bildschirmen und echtem Netz über 127.0.0.1:
#   L   Kein leerer Tisch: Ein App-Gast-Tisch ohne Stand zeigt „Der Tisch wird geladen …“; mit dem ersten Stand verschwindet es.
#   P   Sofort-Leiste bei „Schrift: Sehr groß“ verdeckt weder Gegnerplätze noch die Hinweisleiste.
#   R   Gast wird entfernt, während seine Verbindung weg ist (App im Hintergrund, „bye“ kommt nicht an). Beim Wiederverbinden mit dem
#       alten Token: „Der Gastgeber hat dich aus dem Spiel genommen.“ mit „Wieder beitreten“ (nicht „Spiel beendet.“).
#   J   „Wieder beitreten“ → Beitrittsseite; die Partie läuft und der Gastgeber nimmt niemanden auf: „Das Spiel läuft schon. Bitte den
#       Gastgeber, dich dazuzuholen …“. Die Meldung bleibt stehen, auch wenn die Suche Spiele meldet (_refresh_games).
#   N   Neuer Computergegner heißt nicht wie ein in dieser Partie herausgenommener.
#   godot_run.ps1 -Script res://tests/test_ui_removed.gd -Headless -Timeout 150

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
	var font_backup: Variant = UiApp.setting("schrift", "normal")
	var name_backup: Variant = UiApp.setting("name", "")
	root.size = Vector2i(1600, 720)
	nav = ScreenNav.new()
	nav.autostart = true
	root.add_child(nav)
	await frames(3)
	await loading_cover()
	await removed_flow()
	UiFonts.set_level("normal")
	if app != null:
		app.settings.set_value("regeln", rules_backup if rules_backup is Dictionary else {})
		app.settings.set_value("grosser_modus", big_backup)
		app.settings.set_value("schrift", font_backup)
		app.settings.set_value("name", name_backup)
	if failed:
		print("FAIL: test_ui_removed")
	else:
		print("RESULT: %d ok" % ok)
	await CleanExit.finish(self, 1 if failed else 0)


func _guest_nav() -> ScreenNav:
	var n := ScreenNav.new()
	n.autostart = false
	root.add_child(n)
	return n


# L: Tisch eines App-Gasts ohne Stand
func loading_cover() -> void:
	var ct := ClientTable.new()
	var ts := TableScreen.create(ct)
	nav.push(ts, false)
	await frames(3)
	check(ts._loading != null and ts._loading.is_visible_in_tree(), "L: ohne Stand der Ladehinweis statt leerem Tisch")
	var lt := ts._loading.find_child("LadenText", true, false) as Label
	check(lt != null and lt.text == "Der Tisch wird geladen …", "L: Text des Ladehinweises")
	ts._leave_now()
	await wait(0.3)


func removed_flow() -> void:
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
	host.add_bot("Minka")
	host.add_bot("Mogli")
	await wait(0.2)
	lobby.start_game()
	check(await _wait_for(func() -> bool: return nav.top() is TableScreen and host.game != null, 4.0), "Partie läuft")
	var hts := nav.top() as TableScreen
	if hts == null:
		return
	await wait(0.3)
	# Gast kommt über das Feld „Mitspieler“ an den Tisch
	hts.open_seat_manager("dazuholen")
	await frames(2)
	var sm := hts._seat_mgr
	nav2 = _guest_nav()
	await frames(2)
	nav2.push(JoinScreen.new(), false)
	await frames(2)
	UiApp.app().settings.set_value("name", "Kim")
	(nav2.top() as JoinScreen).join("127.0.0.1", port)
	check(await _wait_for(func() -> bool: return not host.waiting_ids().is_empty(), 6.0), "Gast auf der Warteliste")
	if host.waiting_ids().is_empty():
		return
	var gid := int(host.waiting_ids()[0])
	await _wait_for(func() -> bool: return sm.page == "tisch", 2.0)
	sm.ask_seat(gid)
	await frames(2)
	await _until_host_turn(host)
	sm._confirm._answer(true)
	check(await _wait_for(func() -> bool: return nav2.top() is TableScreen, 5.0), "Gast am Tisch")
	var gts := nav2.top() as TableScreen
	if gts == null:
		return
	check(await _wait_for(func() -> bool: return not gts.view.is_empty(), 4.0) and not gts._loading.visible, "L: mit dem Stand kein Ladehinweis mehr")
	sm.close()
	await frames(2)
	check(not host.session.join_open, "Warteliste zu")
	var gct := gts.source as ClientTable
	var gseat := host._seat_ids.find(gid)
	# Verbindung still weg (App im Hintergrund): Neuversuch erst viel später
	gct.client.retry_ms = [60000]
	gct.client._lost("Hintergrund (Test)")
	check(await _wait_for(func() -> bool: return host.game != null and not bool(host.game.connected[gseat]), 4.0), "Gastgeber sieht den Gast getrennt")
	# P: „…“ bei sehr großer Schrift frei von Plätzen, Stapeln, Hinweis und Knöpfen; die Leiste bleibt zu, bis man tippt
	UiApp.app().settings.set_value("schrift", "sehr_gross")
	UiFonts.set_level("sehr_gross")
	await frames(3)
	hts._layout()
	check(await _wait_for(func() -> bool: return hts._sub_dots.visible and hts.table._seats.size() == 3 and not hts.table.director.is_busy(), 12.0), "P: „…“ sichtbar, drei Gegner")
	await wait(0.7)
	await frames(2)
	check(not hts._sub_hint.visible, "P: Leiste zu")
	var dots := hts._sub_dots.get_global_rect()
	var blocks := _dots_blocks(hts)
	check(blocks.size() >= 10, "P: Plätze, Stapel, Knöpfe als Hindernisse (%d, Hinweis „%s“, Plätze %d)" % [blocks.size(), hts.table.hint_bar.hint, (hts.view.get("players", []) as Array).size()])
	check(Rect2(0, 0, 1600, 720).encloses(dots), "P: „…“ im Bild (%s)" % dots)
	var under := blocks.filter(func(b: Rect2) -> bool: return dots.intersects(b))
	check(under.is_empty(), "P: „…“ verdeckt nichts (%s; %s)" % [dots, under])
	# T (Nutzerbefund 31.10.2026): Die Leiste lag über „Behalten“, der Zug ließ sich nicht beenden. Jetzt wirkt der Tipp, ob sie offen ist oder nicht
	var keep: PillButton = hts.table._act_btns["keep"]
	var keeps := [0]
	var count_keep := func() -> void: keeps[0] += 1
	keep.pressed.connect(count_keep)
	keep.visible = true
	hts.table._layout_action_buttons()
	var keep_at := keep.get_global_rect().get_center()
	nav2.visible = false                 # der Gast liegt im selben Fenster über dem Tisch des Gastgebers
	_tap(keep_at)
	check(keeps[0] == 1, "T: „Behalten“ erreichbar, solange jemand weg ist")
	_tap(dots.get_center())
	check(hts._sub_open and hts._sub_hint.visible and hts._sub_btn.is_visible_in_tree() and hts._kick_btn.is_visible_in_tree(), "T: Tipp auf „…“ öffnet die Leiste")
	var bar := hts._sub_hint.get_global_rect()
	check(Rect2(0, 0, 1600, 720).encloses(bar), "T: Leiste im Bild (%s)" % bar)
	check(not bar.intersects(hts.table.mau_button.get_global_rect()) and not bar.intersects(keep.get_global_rect()), "T: Leiste frei von Mau-Knopf und „Behalten“ (%s)" % bar)
	_tap(bar.get_center() + Vector2(0.0, bar.size.y * 0.5 - 4.0))
	check(hts._sub_hint.visible and hts._confirm == null, "T: Tipp in die Leiste neben die Knöpfe lässt sie offen")
	keep.visible = true
	_tap(keep_at)
	check(keeps[0] == 2 and not hts._sub_hint.visible, "T: Tipp auf „Behalten“ wirkt und schließt die Leiste")
	keep.pressed.disconnect(count_keep)
	keep.visible = false
	nav2.visible = true
	_tap(dots.get_center())
	check(hts._sub_hint.visible, "T: wieder auf")
	_tap(dots.get_center())
	check(not hts._sub_open and not hts._sub_hint.visible, "T: zweiter Tipp auf „…“ schließt")
	hts.toggle_bar()
	_tap(Vector2(800, 360))
	check(not hts._sub_hint.visible, "T: Tipp daneben schließt")
	hts.toggle_bar()
	hts._sub_close_ms = 0
	await frames(2)
	check(not hts._sub_hint.visible, "T: schließt sich von selbst")
	hts.toggle_bar()
	check(hts.on_back() and not hts._sub_hint.visible and hts._confirm == null, "T: Zurück-Taste schließt zuerst die Leiste")
	UiApp.app().settings.set_value("schrift", "normal")
	UiFonts.set_level("normal")
	hts._layout()
	# R: Gastgeber nimmt den Gast heraus; das „bye“ erreicht ihn nicht
	await _until_host_turn(host)
	hts.toggle_bar()
	check(host.remove_seat(gseat), "R: Herausnehmen angenommen")
	check(await _wait_for(func() -> bool: return host.seats.size() == 3, 4.0), "R: Gast heraus")
	check(await _wait_for(func() -> bool: return not hts._sub_dots.visible and not hts._sub_hint.visible, 2.0), "R: „…“ und offene Leiste weg")
	gct.client._retry_at = Time.get_ticks_msec()       # App wieder vorn: sofort neu verbinden (mit altem Token)
	check(await _wait_for(func() -> bool: return gts._conn.visible and gts._conn_rejoin.visible, 6.0),
		"R: Leiste mit „Wieder beitreten“ (%s, %s)" % [gts._conn_label.text, gct.connection_state()])
	check(gts._conn_label.text == "Der Gastgeber hat dich aus dem Spiel genommen.", "R: klare Meldung (%s)" % gts._conn_label.text)
	check(gct.was_removed() and gct.client.reject_code == "running", "R: über die Ablehnung erkannt (%s)" % gct.client.reject_code)
	check(gts._conn_menu.visible and not gts._conn_host.visible, "R: „Zum Menü“, kein „Selbst eröffnen“")
	# J: wieder beitreten → Beitrittsseite mit Meldung, die stehen bleibt
	gts.rejoin()
	check(await _wait_for(func() -> bool: return nav2.top() is JoinScreen, 3.0), "J: Beitrittsseite")
	var js := nav2.top() as JoinScreen
	if js != null:
		var want := "Das Spiel läuft schon. Bitte den Gastgeber, dich dazuzuholen (☰ → Mitspieler dazuholen)."
		check(await _wait_for(func() -> bool: return js._status.text == want, 6.0), "J: Hinweis zum Dazuholen (%s)" % js._status.text)
		js._refresh_games()
		await wait(1.2)
		js._refresh_games()
		check(js._status.text == want, "J: Meldung bleibt nach der Suche stehen (%s)" % js._status.text)
		# Gastgeber öffnet die Warteliste, der Gast tippt erneut: Warteliste, passender Satz
		hts.open_seat_manager("dazuholen")
		await frames(2)
		js.join("127.0.0.1", port)
		check(await _wait_for(func() -> bool: return not host.waiting_ids().is_empty(), 6.0), "J: wieder auf der Warteliste")
		check(await _wait_for(func() -> bool: return js._status.text.begins_with("Das Spiel läuft schon. Der Gastgeber kann dich dazuholen"), 3.0),
			"J: Satz zur Warteliste (%s)" % js._status.text)
		# Ablehnen: „nicht dazugeholt“ bleibt stehen
		host.reject_waiting(int(host.waiting_ids()[0]))
		check(await _wait_for(func() -> bool: return js._status.text == "Der Gastgeber hat dich nicht dazugeholt.", 4.0), "J: Ablehnung (%s)" % js._status.text)
		js._refresh_games()
		await wait(0.3)
		js._refresh_games()
		check(js._status.text == "Der Gastgeber hat dich nicht dazugeholt.", "J: Ablehnung bleibt stehen (%s)" % js._status.text)
		if hts.is_seat_manager_open():
			hts._seat_mgr.close()
	# N: Computergegner „Mogli“ heraus, ein neuer heißt anders
	var mseat := -1
	for s in host.seats.size():
		if host.seat_name(s) == "Mogli":
			mseat = s
	await _until_host_turn(host)
	check(mseat >= 0 and host.remove_seat(mseat), "N: Mogli heraus")
	await _wait_for(func() -> bool: return host.seats.size() == 2, 4.0)
	var nn := host.free_bot_name()
	check(nn != "Mogli" and nn != "Minka" and nn != host.seat_name(host.host_seat), "N: neuer Name (%s)" % nn)
	nav2.queue_free()
	nav2 = null
	hts._leave_now()
	await wait(0.5)


func _until_host_turn(host: HostTable) -> void:
	await _wait_for(func() -> bool: return host.game != null and host.game.state == "turn", 4.0)


func _tap(pos: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		e.position = pos
		e.global_position = pos
		root.push_input(e, true)


# Was der „…“-Knopf nicht verdecken darf (Bildschirmkoordinaten): Knöpfe, Gegnerplätze samt Fächer, Stapel, Hinweisleiste, Reaktionsknöpfe
func _dots_blocks(ts: TableScreen) -> Array[Rect2]:
	var out: Array[Rect2] = [ts._menu_btn.get_global_rect(), ts._burger.get_global_rect(), ts.table.mau_button.get_global_rect()]
	for s in (ts.view.get("players", []) as Array).size():
		var node := ts.table.seat_node(s)
		if node == null or not node.visible or s == int(ts.view.get("seat", -1)):
			continue
		var av := node.avatar_global()
		var r := Rect2(av - Vector2(34, 34), Vector2(68, 68))
		r = r.expand(av + Vector2(node.fan_max_w * 0.5 + 40.0, 0.0))   # Name und Kartenzahl rechts vom Avatar
		for c: Dictionary in node.fan_cards():
			var w := float(c.width)
			var p: Vector2 = c.pos
			r = r.merge(Rect2(p - Vector2(w * 0.6, w * 0.85), Vector2(w * 1.2, w * 1.7)))
		out.append(r.grow(4.0))
	for c: CardView in [ts.table.pile_top(), ts.table.discard_top()]:
		if c != null and is_instance_valid(c) and c.is_visible_in_tree():
			var w := c.width * c.global_scale.x
			out.append(Rect2(c.global_position - Vector2(w * 0.6, w * 0.85), Vector2(w * 1.2, w * 1.7)))
	var hb := ts.table.hint_bar
	if hb != null and hb.hint != "":
		var tw := UiFonts.text(700, 100.0).get_string_size(hb.hint, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFonts.size("hinweisleiste")).x + 40.0
		var cx := hb.get_global_rect().get_center().x
		out.append(Rect2(cx - tw * 0.5 - 6.0, hb.global_position.y + hb.hint_y - hb.hint_h() * 0.5 - 6.0, tw + 12.0, hb.hint_h() + 12.0))
	var rb := ts.table.tease.reactions
	if rb != null and rb.visible:
		out.append(Rect2(rb.get_global_transform_with_canvas() * rb.bounds().position, rb.bounds().size))
	ts.table._layout_action_buttons(true)                              # „Behalten“ & Co., auch wenn sie gerade nicht zu sehen sind
	for key in ["pick", "undo", "accept", "challenge", "keep"]:
		out.append((ts.table._act_btns[key] as PillButton).get_global_rect())
	return out
