extends SceneTree
# Stift am Tisch (Nutzerbefund 25.10.2026: „Doppelklick mit dem Stift auf Jokerkarten funktioniert nicht“). Seit Beta 1.6.13 erzeugt
# App.enable_pen_touch zu jedem Stiftdruck eine Berührung; Godot schickt die nachgebildete Berührung VOR dem Mausereignis (beim Finger
# umgekehrt: nachgebildete Maus zuerst). Die Hand öffnet das Farbrad beim Loslassen der Berührung, das Maus-Loslassen desselben Tipps
# kam danach im Farbrad an (TableView._gui_input reicht es weiter) und brach es als „Tipp daneben“ sofort ab (WishPicker.handle_input).
# Nachgestellt mit Input.parse_input_event wie die Android-Schicht, echter TableScreen mit LocalTable:
#   - Stift-Doppeltipp auf den Wünscher: Farbrad bleibt offen; Stifttipp auf ein Viertel legt ihn mit dieser Farbe
#   - Stifttipp neben das Rad bricht weiter ab (Joker zurück in der Hand)
#   - Finger-Doppeltipp: Rad bleibt offen wie bisher
#   - Joker mit dem Finger auf die Ablage ziehen: keine Farbfelder mehr (Nutzerwunsch 25.10.2026), danach das Farbrad
#   - Kartenhilfe mit dem Stift (halten, nach unten): bleibt offen, ein Tipp daneben schließt sie. Sie war nicht betroffen (das
#     Maus-Loslassen geht an das Steuerelement, das den Druck bekam, nicht an die neu geöffnete Hilfe) – Absicherung für später.
#   godot_run.ps1 -Script res://tests/test_ui_wheel_pen.gd -Headless -Timeout 120

const CleanExit := preload("res://tests/clean_exit.gd")
const AppScript := preload("res://scripts/app/app.gd")

var ok := 0
var fails := 0


func _initialize() -> void:
	call_deferred("run")


func check(cond: bool, what: String) -> void:
	if cond:
		ok += 1
	else:
		fails += 1
		print("FAIL: " + what)


func frames(n := 2) -> void:
	for i in n:
		await process_frame


func wait(t: float) -> void:
	await create_timer(t).timeout


func run() -> void:
	root.size = Vector2i(1600, 720)
	var was := Input.is_emulating_touch_from_mouse()
	AppScript.enable_pen_touch()
	var app := UiApp.app()
	var had_hl: bool = app != null and app.settings.has_value("hervorheben")
	var hl_backup: Variant = UiApp.setting("hervorheben", true)
	if app != null:
		app.settings.set_value("hervorheben", true)
	await pen_double_tap_test()
	await pen_cancel_test()
	await finger_double_tap_test()
	await drag_joker_test()
	await pen_help_test()
	if app != null:
		if had_hl:
			app.settings.set_value("hervorheben", hl_backup)
		else:
			app.settings.reset("hervorheben")
	Input.emulate_touch_from_mouse = was
	if fails > 0:
		print("FAIL: test_ui_wheel_pen (%d)" % fails)
	print("RESULT: %d ok" % ok)
	await CleanExit.finish(self, 1 if fails > 0 else 0)


# ----------------------------------------------------------------- Vorrichtung (wie test_ui_new_cards.gd)

func make_table() -> TableScreen:
	var g := RulesFixture.build(RuleConfig.new(), 3, {"hands": [["hell_wuenscher", "hell_blau_2", "hell_gelb_7"], ["hell_gelb_1"],
		["hell_gelb_2"]], "top": "hell_rot_5", "current": 0}, 4711)
	var seats: Array = []
	for i in 3:
		if i > 0:
			(g.players[i] as Dictionary)["kind"] = "bot"
		seats.append({"name": str(g.players[i].name), "kind": "human" if i == 0 else "bot", "host": i == 0})
	var t := LocalTable.new()
	t.auto_process = false
	t.autosave = false
	t.speed = 0.0
	var data := {"mode": "solo", "game": g.to_dict(), "seats": seats, "host_seat": 0}
	var ts := TableScreen.create(t, func() -> void: t.resume(data))
	root.add_child(ts)
	await frames(3)
	await settle(ts)
	return ts


func game_of(ts: TableScreen) -> MauGame:
	return (ts.source as LocalTable).game


func close_table(ts: TableScreen) -> void:
	ts.leaving = true
	ts.queue_free()
	await frames(3)


func settle(ts: TableScreen, extra := 0.4) -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while ts.table.director.is_busy() and Time.get_ticks_msec() < deadline:
		await frames(1)
	await wait(extra)


func send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


# Fensterkoordinaten eines Punkts im lokalen System eines Node2D
func win_of(n: Node2D, p: Vector2) -> Vector2:
	return root.get_final_transform() * (n.get_global_transform_with_canvas() * p)


# Gut antippbare Stelle einer Handkarte (oben links, wie test_ui_hand_pen.gd)
func card_point(ts: TableScreen, id: int) -> Vector2:
	var v := ts.hand.card_view(id)
	var h := v.card_size() * v.scale.x * 0.5
	return win_of(ts.hand, v.position + Vector2(-h.x + 22.0, -h.y + 50.0).rotated(v.rotation))


# Stiftspitze wie GodotInputHandler: linke Maustaste (die Berührung erzeugt Godot selbst, App.enable_pen_touch)
func pen_button(w: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	ev.pressed = pressed
	ev.position = w
	ev.global_position = w
	send(ev)


func pen_move(w: Vector2, rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.position = w
	ev.global_position = w
	ev.relative = rel
	ev.pressure = 0.6
	send(ev)


func pen_tap(w: Vector2) -> void:
	pen_button(w, true)
	await frames(2)
	pen_button(w, false)
	await frames(2)


func pen_double_tap(w: Vector2) -> void:
	pen_button(w, true)
	await frames(1)
	pen_button(w, false)
	await frames(2)
	pen_button(w, true)
	await frames(1)
	pen_button(w, false)


func finger(w: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = w
	ev.pressed = pressed
	send(ev)


func finger_drag(w: Vector2, rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = 0
	ev.position = w
	ev.relative = rel
	send(ev)


# Fensterpunkt in einem Viertel des Farbrads und dessen Farbe
func wheel_point(ts: TableScreen) -> Array:
	var wp := ts.table.wish_picker
	for a in [-0.75 * PI, -0.25 * PI, 0.25 * PI, 0.75 * PI]:
		var local := wp.wheel_center + Vector2.from_angle(a) * (WishPicker.WHEEL_INNER + WishPicker.WHEEL_R) * 0.5
		var col := wp.color_at(wp.get_global_transform() * local)
		if col != "":
			return [win_of(wp, local), col]
	return [Vector2.ZERO, ""]


# ----------------------------------------------------------------- Fälle

func pen_double_tap_test() -> void:
	var ts := await make_table()
	var g := game_of(ts)
	var joker := RulesFixture.card(g, 0, "hell_wuenscher")
	check(joker >= 0 and g.current_seat() == 0, "Stift: Wünscher auf der Hand, Platz 0 am Zug")
	await pen_double_tap(card_point(ts, joker))
	await frames(4)
	check(ts.table.wish_picker.mode == "wheel", "Stift-Doppeltipp auf den Wünscher: Farbrad bleibt offen (Nutzerbefund nachgestellt, mode = „%s“)"
		% ts.table.wish_picker.mode)
	var wp: Array = wheel_point(ts)
	check(str(wp[1]) != "", "Farbrad: Viertel gefunden")
	await pen_tap(wp[0])
	await settle(ts)
	check(not (g.hands[0] as Array).has(joker) and g.color == str(wp[1]),
		"Stifttipp aufs Farbrad legt den Wünscher mit „%s“ (Farbe %s, Hand %s)" % [str(wp[1]), g.color, str(g.hands[0])])
	await close_table(ts)


func pen_cancel_test() -> void:
	var ts := await make_table()
	var g := game_of(ts)
	var joker := RulesFixture.card(g, 0, "hell_wuenscher")
	await pen_double_tap(card_point(ts, joker))
	await frames(4)
	check(ts.table.wish_picker.mode == "wheel", "Stift: Farbrad offen")
	await pen_tap(root.get_final_transform() * Vector2(60, 60))
	await settle(ts)
	check(ts.table.wish_picker.mode == "" and (g.hands[0] as Array).has(joker) and g.current_seat() == 0,
		"Stifttipp neben das Rad bricht ab, der Wünscher bleibt in der Hand")
	await close_table(ts)


func finger_double_tap_test() -> void:
	var ts := await make_table()
	var g := game_of(ts)
	var joker := RulesFixture.card(g, 0, "hell_wuenscher")
	var w := card_point(ts, joker)
	finger(w, true)
	await frames(1)
	finger(w, false)
	await frames(2)
	finger(w, true)
	await frames(1)
	finger(w, false)
	await frames(4)
	check(ts.table.wish_picker.mode == "wheel", "Finger-Doppeltipp auf den Wünscher: Farbrad offen (mode = „%s“)" % ts.table.wish_picker.mode)
	await close_table(ts)


# Nutzerwunsch 25.10.2026: Beim Ziehen eines Jokers erscheinen keine Farbfelder mehr (man landete zu oft versehentlich darauf); nach
# dem Ablegen kommt das Farbrad.
func drag_joker_test() -> void:
	var ts := await make_table()
	var g := game_of(ts)
	var joker := RulesFixture.card(g, 0, "hell_wuenscher")
	var w := card_point(ts, joker)
	var step := Vector2(0, -24.0) * root.get_final_transform().get_scale().y
	finger(w, true)
	await frames(1)
	var opened_while_dragging := false
	for k in range(1, 16):
		finger_drag(w + step * k, step)
		await frames(1)
		if ts.table.wish_picker.mode != "":
			opened_while_dragging = true
	check(not opened_while_dragging, "Joker nach oben ziehen: keine Farbfelder um die Ablage")
	finger(w + step * 15, false)
	await frames(4)
	check(ts.table.wish_picker.mode == "wheel", "Joker auf die Ablage gezogen: danach das Farbrad (mode = „%s“)" % ts.table.wish_picker.mode)
	var wp: Array = wheel_point(ts)
	finger(wp[0], true)
	await frames(2)
	finger(wp[0], false)
	await settle(ts)
	check(not (g.hands[0] as Array).has(joker) and str(wp[1]) != "" and g.color == str(wp[1]),
		"Fingertipp aufs Farbrad legt den gezogenen Wünscher mit „%s“ (Farbe %s)" % [str(wp[1]), g.color])
	await close_table(ts)


func pen_help_test() -> void:
	var ts := await make_table()
	var g := game_of(ts)
	var card := RulesFixture.card(g, 0, "hell_blau_2")
	var w := card_point(ts, card)
	pen_button(w, true)
	await wait(0.5)                              # halten: Großansicht
	check(ts.hand.is_big_view_open(), "Stift halten: Großansicht")
	var step := 20.0 * root.get_final_transform().get_scale().y
	for k in range(1, 9):
		pen_move(w + Vector2(0, step * k), Vector2(0, step))
		await frames(1)
	pen_button(w + Vector2(0, step * 8), false)
	await frames(4)
	check(ts.table.help_popup.visible, "Stift halten und nach unten auf „?“: Kartenhilfe bleibt offen")
	await pen_tap(root.get_final_transform() * Vector2(40, 40))
	await frames(3)
	check(not ts.table.help_popup.visible, "Stifttipp neben die Hilfe schließt sie")
	await close_table(ts)
