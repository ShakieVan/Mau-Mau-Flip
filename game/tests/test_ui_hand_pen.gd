extends SceneTree
# Stift (Beta 1.6.13, Nutzerbefund am S24: Knöpfe gingen mit dem Stift, Karten antippen und legen nicht). Godot 4.6.1 meldet Stift und
# Maus auf Android als Mausereignisse und schaltet emulate_touch_from_mouse auf Geräten mit Touchscreen ab; die Hand hört nur auf
# Berührungen. Nachgestellt mit Input.parse_input_event (wie die Android-Schicht): erst ohne Umwandlung (Fehler: nichts passiert), dann
# mit App.enable_pen_touch (antippen, nach oben legen, Großansicht). Dazu: Finger lösen weiterhin genau eine Berührung aus (deren
# nachgebildete Mausereignisse werden nicht zurückverwandelt), ein Stiftdruck ebenso genau eine.
# Aufruf: tools/godot_run.ps1 -Script res://tests/test_ui_hand_pen.gd -Headless
const DT := 1.0 / 60.0
const AppScript := preload("res://scripts/app/app.gd")
var ok := 0
var failed := 0
var hand: HandView
var clock := 1000.0
var log: Array = []
var downs := 0


class CountingHand:
	extends HandView
	var downs := 0

	func touch_down(p: Vector2, t_ms := -1.0) -> bool:
		downs += 1
		return super.touch_down(p, t_ms)


func check(cond: bool, msg: String) -> void:
	if cond:
		ok += 1
	else:
		failed += 1
		print("FAIL: ", msg)


func _initialize() -> void:
	call_deferred("run")


func step(n := 1) -> void:
	for k in n:
		clock += DT * 1000.0
		hand.clock_ms = clock
		hand.step(DT)


func settle(seconds := 1.0) -> void:
	step(int(seconds / DT))


func new_hand() -> void:
	if hand != null:
		hand.free()
	hand = CountingHand.new()
	hand.haptics = false
	root.add_child(hand)
	hand.set_process(false)
	hand.clock_ms = clock
	var vr := hand._view_rect()
	hand.layout_rect = Rect2(270, vr.end.y - 220.0, 1060, 220)
	log.clear()
	hand.play_requested.connect(func(id: int, _g: Vector2) -> void: log.append(["play", id]))
	hand.selection_changed.connect(func(id: int) -> void: log.append(["select", id]))
	hand.big_view_changed.connect(func(id: int) -> void: log.append(["big", id]))
	var faces := ["hell_wuenscher", "hell_blau_9", "hell_rot_7", "hell_gelb_3", "hell_rot_2"]
	var cs: Array = []
	for i in faces.size():
		cs.append({"id": i, "face": faces[i], "back": "dunkel_lila_%d" % (1 + i)})
	hand.set_cards(cs)
	hand.set_playable([0, 1, 2, 3, 4])
	hand.play_target = Vector2(980, 320)
	settle()


func events(name: String) -> Array:
	return log.filter(func(e: Array) -> bool: return e[0] == name)


func tap_point(id: int) -> Vector2:
	var v := hand.card_view(id)
	var h := v.card_size() * v.scale.x * 0.5
	return v.position + Vector2(-h.x + 22.0, -h.y + 50.0).rotated(v.rotation)


func win(p: Vector2) -> Vector2:
	return root.get_final_transform() * (hand.get_global_transform_with_canvas() * p)


func send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


# Stiftspitze wie GodotInputHandler/AndroidInputHandler: Linksklick, Ziehen mit gedrückter linker Taste, Loslassen
func pen_button(p: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	ev.pressed = pressed
	ev.position = win(p)
	ev.global_position = ev.position
	send(ev)


func pen_move(p: Vector2, rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.position = win(p)
	ev.global_position = ev.position
	ev.relative = rel
	ev.pressure = 0.6
	send(ev)


func pen_hover(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = win(p)
	ev.global_position = ev.position
	send(ev)


func pen_swipe_up(p: Vector2) -> void:
	pen_button(p, true)
	for k in range(1, 15):
		step()
		pen_move(p + Vector2(0, -17.0 * k), Vector2(0, -17.0))
	step(3)
	pen_button(p + Vector2(0, -17.0 * 14), false)
	step(2)


func pen_tap(p: Vector2) -> void:
	pen_button(p, true)
	step(4)
	pen_button(p, false)
	step(2)


func finger(p: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = win(p)
	ev.pressed = pressed
	send(ev)


func run() -> void:
	var was := Input.is_emulating_touch_from_mouse()
	# ---------------------------------------------------------------- vorher: wie Android ohne Umwandlung
	Input.emulate_touch_from_mouse = false
	new_hand()
	pen_hover(tap_point(2))
	pen_tap(tap_point(2))
	pen_swipe_up(tap_point(1))
	settle(0.5)
	check(events("select").is_empty() and events("play").is_empty() and (hand as CountingHand).downs == 0,
		"ohne Umwandlung erreicht der Stift die Hand nicht (Nutzerbefund nachgestellt: %s)" % str(log))

	# ---------------------------------------------------------------- mit App.enable_pen_touch
	check(AppScript.enable_pen_touch(), "enable_pen_touch schaltet die Umwandlung ein")
	check(Input.is_emulating_touch_from_mouse(), "emulate_touch_from_mouse ist an")
	check(not AppScript.enable_pen_touch(), "zweiter Aufruf: schon an, nichts zu tun")
	new_hand()
	pen_tap(tap_point(2))
	check(events("select") == [["select", 2]], "Stift tippt Karte 2 an: ausgewählt (%s)" % str(log))
	check((hand as CountingHand).downs == 1, "ein Stiftdruck = genau eine Berührung (%d)" % (hand as CountingHand).downs)
	settle(0.3)
	pen_swipe_up(tap_point(1))
	check(events("play") == [["play", 1]], "Stift zieht Karte 1 nach oben: ausgespielt (%s)" % str(log))
	check((hand as CountingHand).downs == 2, "zweiter Stiftdruck = zweite Berührung (%d)" % (hand as CountingHand).downs)

	# Halten: Großansicht öffnet sich wie mit dem Finger
	new_hand()
	var p3 := tap_point(3)
	pen_button(p3, true)
	step(25)
	check(hand.is_big_view_open() and events("big").size() >= 1, "Stift halten: Großansicht öffnet sich (%s)" % str(log))
	pen_button(p3, false)
	hand.close_big_view()
	settle(0.3)

	# Karussell (ab 16 Karten): mit dem Stift waagerecht wischen rollt die Hand
	new_hand()
	var cs: Array = []
	var colors := ["rot", "gelb", "gruen", "blau"]
	for i in 20:
		cs.append({"id": 100 + i, "face": "hell_%s_%d" % [colors[i % 4], 1 + (i / 4) % 9], "back": "dunkel_lila_1"})
	hand.set_cards(cs)
	settle()
	check(hand.get_mode() == HandLayout.Mode.CAROUSEL, "20 Karten: Karussell")
	var s0 := hand.get_scroll()
	var lr := hand.layout_rect
	var p0 := Vector2(lr.position.x + lr.size.x * 0.75, lr.position.y + lr.size.y * 0.55)
	pen_button(p0, true)
	for k in range(1, 16):
		step()
		pen_move(p0 + Vector2(-24.0 * k, 0), Vector2(-24.0, 0))
	pen_button(p0 + Vector2(-24.0 * 15, 0), false)
	settle(1.0)
	check(absf(hand.get_scroll() - s0) >= 1.0 and events("play").is_empty(), "Stift wischt das Karussell weiter (%.2f → %.2f)" % [s0, hand.get_scroll()])
	# Halten und seitlich ziehen: umsortieren
	new_hand()
	var order0 := hand.get_order().duplicate()
	var q := tap_point(1)
	pen_button(q, true)
	step(25)
	for k in range(1, 12):
		step()
		pen_move(q + Vector2(28.0 * k, 0), Vector2(28.0, 0))
	pen_button(q + Vector2(28.0 * 11, 0), false)
	settle(0.6)
	check(hand.get_order() != order0 and events("play").is_empty(), "Stift halten und seitlich ziehen: umsortiert (%s → %s)" % [str(order0), str(hand.get_order())])

	# Finger bleiben unverändert: eine echte Berührung, ihre nachgebildeten Mausereignisse werden nicht zurückverwandelt
	new_hand()
	var p4 := tap_point(4)
	finger(p4, true)
	step(4)
	finger(p4, false)
	step(2)
	check((hand as CountingHand).downs == 1, "Finger: genau eine Berührung (%d)" % (hand as CountingHand).downs)
	check(events("select") == [["select", 4]], "Finger tippt Karte 4 an (%s)" % str(log))

	Input.emulate_touch_from_mouse = was
	hand.free()
	print("RESULT: %d ok, %d failed" % [ok, failed])
	quit(1 if failed > 0 else 0)
