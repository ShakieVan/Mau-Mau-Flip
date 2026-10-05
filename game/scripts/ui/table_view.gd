class_name TableView
extends Control
# Der Spieltisch im Querformat (BETA1_PLAN Abschnitt 7, Zielbild art/entwurf/a-papier-neon/hand.png):
# Gegner im Halbkreis (relativ zum eigenen Platz gedreht, nie gespiegelt), Nachziehstapel links von der Mitte mit der
# Gegenseite der obersten Karte, Ablage spiegelbildlich rechts mit Farbring, aktuelle Farbe dazwischen, Richtungsring,
# Hinweisleiste („Du bist dran“), Knöpfe Sortieren/Rückseiten links unten, Mau! rechts unten.
#
# Schnittstelle (TableSource, BETA1_PLAN Abschnitt 6):
#   handle_state(events, view)   Ereignisse über die Tischregie abspielen, danach mit der Sicht abgleichen
#   apply_view(view)             sofortiger Abgleich auf den Endzustand (Start, Wiederverbinden)
#   play_events(events)          nur Ereignisse (ohne Abgleich)
#   signal action(a)             Spielaktion für TableSource.act(): draw, keep, challenge, accept, mau, catch, next_round, color
#   signal sort_pressed / backs_pressed   Knöpfe für die Hand
# Hand-Adapter (Phase 2: HandView aus Modul F1a; in der Demo eine einfache Kartenreihe), alle Methoden optional:
#   apply_view(view)  take_card(id) -> {pos, rot, width} (global)  receive_card(card: {id, face, back}, from_global)
#   landing_point() -> Vector2 (global)  flip_wave(delay, step, dur, faces: {id: face})  set_input_locked(on)
#   own_color_counts() -> {farbe: Anzahl}
# Effektstufe „reduziert“ (App.settings "effekte"): kürzere Abläufe, weniger Teilchen, kein Wackeln, kein Zoom.
# Mau (AGENTS.md Nr. 21): Ereignis „mau“ → Ton "mau" auf jedem Gerät (MauSound, außer Mau-Ton aus) und eine zufällig gewählte,
# animierte Sprechblase beim Rufenden (show_mau); „finish“ → Ton "mau_mau" und die große Doppelblase „Mau-Mau!“.

signal action(a: Dictionary)
signal sort_pressed
signal backs_pressed
signal seat_tapped(seat: int)

const CARD_W := 116.0                 # Stapel und Ablage
const HAND_CARD_W := 150.0            # Ersatzbreite, wenn keine Hand angeschlossen ist
const DISCARD_KEEP := 3               # sichtbare Karten auf der Ablage

var reduced := false: set = set_reduced
var hand: Node = null
var director: Director
var view: Dictionary = {}
var my_seat := 0
var side := "hell"
var night := 0.0: set = set_night
var input_locked := false
var can_next_round := -1              # -1 = automatisch (Platz 0), 0/1 = vom Spielablauf gesetzt

var hand_layer: Node2D
var fx: TableEffects
var fx_top: TableEffects
var wish_picker: WishPicker
var mau_button: MauButton
var hint_bar: Toast
var help_popup: HelpPopup
var backs_viewer: BacksViewer
var round_end: RoundEndView
var handover: HandoverScreen

var _bg: TableBackground
var _world: Node2D
var _ring: DirectionRing
var _seat_layer: Node2D
var _pile: PileView
var _color_ring: ColorRingView
var _discard_layer: Node2D
var _discard: Array[CardView] = []
var _color_mark: ColorMark
var _ui: Control
var _sort_btn: PillButton
var _backs_btn: PillButton
var _act_btns: Dictionary = {}
var _edge: ColorRect
var _overlay: Control
var _seats: Dictionary = {}           # Platz → OpponentSeat
var _n := 0
var _speed := 1.0
var _color := ""
var _discard_rays: JokerRays
var _jagd_armed := false
var _plus_armed := 0
var _last_player := -1
var _flip_running := false
var _shake := 0.0
var _zoom := 1.0
var _press_pos := Vector2.ZERO
var _pressing := false
var _rays_fx: Node2D
var _round_key := ""
var mau_variant_override := ""       # Tests/Kontrollbilder: feste Variante der Mau-Blase ("" = zufällig)
var _mau_rng := RandomNumberGenerator.new()
var _mau_last := ""

var _center := Vector2(800, 320)
var _draw_pos := Vector2(623, 320)
var _discard_pos := Vector2(977, 320)


# ================================================================= Aufbau

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mau_rng.randomize()
	director = Director.new()
	director.handler = self
	add_child(director)
	_bg = TableBackground.new()
	add_child(_bg)
	_world = Node2D.new()
	add_child(_world)
	_ring = DirectionRing.new()
	_world.add_child(_ring)
	_seat_layer = Node2D.new()
	_world.add_child(_seat_layer)
	_pile = PileView.new()
	_world.add_child(_pile)
	_color_ring = ColorRingView.new()
	_world.add_child(_color_ring)
	_discard_layer = Node2D.new()
	_world.add_child(_discard_layer)
	_color_mark = ColorMark.new()
	_world.add_child(_color_mark)
	hand_layer = Node2D.new()
	hand_layer.name = "Hand"
	_world.add_child(hand_layer)
	fx = TableEffects.new()
	_world.add_child(fx)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	hint_bar = Toast.new()
	hint_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(hint_bar)
	_sort_btn = _pill("Farbe", "sortieren")
	_sort_btn.pressed.connect(func() -> void: sort_pressed.emit())
	_backs_btn = _pill("Rückseiten", "rueckseiten")
	_backs_btn.pressed.connect(func() -> void: backs_pressed.emit())
	for key in ["keep", "challenge", "accept"]:
		var label: String = {"keep": "Behalten", "challenge": "Anzweifeln", "accept": "Annehmen"}[key]
		var icon: String = {"keep": "haken", "challenge": "kreuz", "accept": "stapel"}[key]
		var b := _pill(label, icon)
		b.style = "primary"
		b.visible = false
		var a: String = key
		b.pressed.connect(func() -> void: _emit_action({"a": a}))
		_act_btns[key] = b
	mau_button = MauButton.new()
	mau_button.mau_pressed.connect(_on_mau_pressed)
	_ui.add_child(mau_button)
	_edge = ColorRect.new()
	_edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := load("res://assets/shaders/edge_pulse.gdshader") as Shader
	if sh != null:
		var mat := ShaderMaterial.new()
		mat.shader = sh
		_edge.material = mat
	_edge.visible = false
	add_child(_edge)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_rays_fx = Node2D.new()
	_overlay.add_child(_rays_fx)
	# Farbwahl über allem Übrigen (Felder über der Hand, Farbrad als Dialog)
	wish_picker = WishPicker.new()
	_overlay.add_child(wish_picker)
	round_end = RoundEndView.new()
	round_end.next_round.connect(func() -> void: _emit_action({"a": "next_round"}))
	_overlay.add_child(round_end)
	fx_top = TableEffects.new()
	_overlay.add_child(fx_top)
	backs_viewer = BacksViewer.new()
	_overlay.add_child(backs_viewer)
	help_popup = HelpPopup.new()
	_overlay.add_child(help_popup)
	handover = HandoverScreen.new()
	_overlay.add_child(handover)
	wish_picker.color_chosen.connect(_on_wheel_color)
	resized.connect(_layout)


func _ready() -> void:
	reduced = UiApp.reduced_effects()
	var app := UiApp.app()
	var st: Variant = app.get("settings") if app != null else null
	if st is Object and (st as Object).has_signal("changed"):
		(st as Object).connect("changed", _on_setting_changed)
	_layout()
	set_night(night)


# Effektstufe live umschalten (Einstellungen)
func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "effekte":
		reduced = str(value) == "reduziert"


func _pill(text: String, icon: String) -> PillButton:
	var b := PillButton.new()
	b.text = text
	b.icon_name = icon
	_ui.add_child(b)
	return b


func set_reduced(on: bool) -> void:
	reduced = on
	if fx:
		fx.reduced = on
		fx_top.reduced = on
	if _bg:
		_bg.motion = not on


# Hand anschließen (HandView oder Demo-Reihe); der Knoten wandert in hand_layer
func set_hand(node: Node) -> void:
	hand = node
	if node is CanvasItem and node.get_parent() == null:
		hand_layer.add_child(node)


func _layout() -> void:
	var sz := size if size.x > 10.0 else TableLayout.BASE
	_center = TableLayout.table_center(sz)
	_draw_pos = TableLayout.draw_pile_pos(sz)
	_discard_pos = TableLayout.discard_pos(sz)
	_bg.table_center = _center
	_ring.position = _center
	_ring.radii = TableLayout.ring_radii(sz)
	_pile.position = _draw_pos
	_color_ring.position = _discard_pos
	_discard_layer.position = _discard_pos
	_color_mark.position = _center
	wish_picker.position = _discard_pos
	wish_picker.wheel_center = Vector2(sz.x * 0.5, sz.y * 0.47) - _discard_pos
	_sort_btn.size = Vector2(_sort_btn.preferred_width(), PillButton.TOUCH_MIN)
	_backs_btn.size = Vector2(_backs_btn.preferred_width(), PillButton.TOUCH_MIN)
	_sort_btn.position = Vector2(40.0, sz.y - 190.0)
	_backs_btn.position = Vector2(40.0, sz.y - 108.0)
	mau_button.position = Vector2(sz.x - 46.0 - MauButton.SIZE, sz.y - 40.0 - MauButton.SIZE)
	hint_bar.hint_y = sz.y - 207.0
	var x := sz.x - 46.0
	for key in ["accept", "challenge", "keep"]:
		var b: PillButton = _act_btns[key]
		b.size = Vector2(b.preferred_width(), PillButton.TOUCH_MIN)
		x -= b.size.x
		b.position = Vector2(x, sz.y - 300.0)
		x -= 10.0
	_place_seats(false)


func table_center() -> Vector2:
	return _center


func discard_position() -> Vector2:
	return _discard_pos


func draw_pile_position() -> Vector2:
	return _draw_pos


func seat_node(seat: int) -> OpponentSeat:
	return _seats.get(seat) as OpponentSeat


func discard_cards() -> Array[CardView]:
	return _discard


func pile_top() -> CardView:
	return _pile.top


# ================================================================= Abgleich mit der Sicht

func handle_state(events: Array, new_view: Dictionary) -> void:
	director.enqueue(events, new_view)


func play_events(events: Array) -> void:
	director.enqueue(events, {})


func apply_view(v: Dictionary) -> void:
	view = v
	var players: Array = v.get("players", [])
	_n = players.size()
	my_seat = int(v.get("seat", 0))
	if my_seat < 0:
		my_seat = int(v.get("turn", 0))
	side = str(v.get("side", "hell"))
	if not _flip_running:
		set_night(1.0 if side == "dunkel" else 0.0)
	var rules: Dictionary = v.get("rules", {})
	var backs_visible := bool(rules.get("backs_visible", true))
	var show_score := str(rules.get("scoring", "none")) == "points500"
	# Plätze
	var wanted := {}
	for p in players:
		var s := int(p.get("seat", -1))
		if s == my_seat and int(v.get("seat", 0)) >= 0:
			continue
		wanted[s] = p
	for s in _seats.keys():
		if not wanted.has(s):
			(_seats[s] as Node).queue_free()
			_seats.erase(s)
	for s in wanted:
		var node: OpponentSeat = _seats.get(s)
		if node == null:
			node = OpponentSeat.new()
			node.seat = s
			_seat_layer.add_child(node)
			_seats[s] = node
		node.show_score = show_score
		node.compact = TableLayout.compact(_n)
		var fm := TableLayout.fan_metrics(_n)
		node.card_w = fm.x
		node.fan_max_w = fm.y
		node.night = night
		node.set_player(wanted[s], backs_visible)
	_place_seats(false)
	# Stapel, Ablage, Farbe, Richtung
	_pile.set_pile(str(v.get("draw_back", "")), int(v.get("draw_count", 0)))
	var top: Dictionary = v.get("top", {})
	_set_top(str(top.get("face", "")), int(top.get("id", -1)))
	_set_color(str(v.get("color", "")), false)
	_ring.set_direction(int(v.get("dir", 1)))
	var pending: Dictionary = v.get("pending", {})
	_color_ring.pending = int(pending.get("amount", 0)) if not pending.is_empty() else 0
	_color_ring.queue_redraw()
	# Zug, Hinweise, Knöpfe
	var turn := int(v.get("turn", -1))
	var dir := int(v.get("dir", 1))
	for s in _seats:
		var node: OpponentSeat = _seats[s]
		node.set_turn(s == turn, _n > 2 and s == posmod(turn + dir, maxi(_n, 1)))
	_apply_hints(v.get("hints", {}), turn)
	if hand != null and hand.has_method("apply_view"):
		hand.call("apply_view", v)
	# Rundenende
	var phase := str(v.get("phase", "turn"))
	if phase == "round_over" or phase == "game_over":
		_show_round_end(v, {})
	else:
		round_end.hide_view()
		_round_key = ""
		for c in _rays_fx.get_children():
			c.queue_free()
	if not director.is_busy():
		input_locked = false


func _apply_hints(h: Dictionary, turn: int) -> void:
	var me_turn := turn == my_seat and int(view.get("seat", 0)) >= 0
	hint_bar.show_hint(str(h.get("text", "Du bist dran." if me_turn else "")), me_turn)
	var me_player := _player(my_seat)
	if bool(h.get("can_mau", false)):
		mau_button.mode = MauButton.Mode.READY
	elif bool(me_player.get("mau", false)):
		mau_button.mode = MauButton.Mode.CALLED
	else:
		mau_button.mode = MauButton.Mode.IDLE
	var catch_list: Array = h.get("catch", [])
	for s in _seats:
		(_seats[s] as OpponentSeat).catchable = catch_list.has(s) or catch_list.has(float(s))
	_act_btns["keep"].visible = bool(h.get("can_keep", false))
	_act_btns["challenge"].visible = bool(h.get("can_challenge", false))
	_act_btns["accept"].visible = bool(h.get("can_challenge", false))
	_pile.highlight = bool(h.get("can_draw", false)) and me_turn
	if bool(h.get("need_color", false)) and not wish_picker.is_open():
		open_color_wheel()
	_layout_action_buttons()


func _layout_action_buttons() -> void:
	var sz := size if size.x > 10.0 else TableLayout.BASE
	var x := sz.x - 46.0
	for key in ["accept", "challenge", "keep"]:
		var b: PillButton = _act_btns[key]
		if not b.visible:
			continue
		b.size = Vector2(b.preferred_width(), PillButton.TOUCH_MIN)
		x -= b.size.x
		b.position = Vector2(x, sz.y - 300.0)
		x -= 10.0


func _player(seat: int) -> Dictionary:
	for p in view.get("players", []):
		if int(p.get("seat", -1)) == seat:
			return p
	return {}


func _player_name(seat: int) -> String:
	if seat == my_seat:
		return "du"
	return str(_player(seat).get("name", "Platz %d" % (seat + 1)))


func _place_seats(animate: bool) -> void:
	if _n <= 0:
		return
	var sz := size if size.x > 10.0 else TableLayout.BASE
	var pos := TableLayout.seat_positions(_n, my_seat, sz)
	for s in _seats:
		var node: OpponentSeat = _seats[s]
		if s < 0 or s >= pos.size():
			continue
		if animate:
			create_tween().tween_property(node, "position", pos[s], 0.35).set_trans(Tween.TRANS_SINE)
		else:
			node.position = pos[s]


# Position eines Platzes in Weltkoordinaten (eigener Platz = Hand)
func _seat_point(seat: int) -> Vector2:
	if seat == my_seat:
		return _hand_point()
	var node := seat_node(seat)
	if node != null:
		return node.position
	return _center


func _hand_point() -> Vector2:
	if hand != null and hand.has_method("landing_point"):
		return _world.to_local(hand.call("landing_point"))
	var sz := size if size.x > 10.0 else TableLayout.BASE
	return TableLayout.hand_pos(sz) + Vector2(0, 20)


func _set_top(face: String, id: int) -> void:
	if face == "":
		for c in _discard:
			c.queue_free()
		_discard.clear()
		_update_rays()
		return
	if not _discard.is_empty() and _discard[-1].current_key() == face:
		return
	_push_discard(face, id)


func _push_discard(face: String, id: int) -> CardView:
	var c := CardView.new()
	c.width = CARD_W
	c.setup(id, face, "", true)
	var k := _discard.size() + face.hash()
	c.rotation = deg_to_rad(float(posmod(k * 37, 15) - 7))
	c.position = Vector2(float(posmod(k * 13, 11) - 5), float(posmod(k * 7, 9) - 4))
	_discard_layer.add_child(c)
	_discard.append(c)
	while _discard.size() > DISCARD_KEEP:
		var old: CardView = _discard.pop_front()
		old.queue_free()
	_update_rays()
	return c


func _update_rays() -> void:
	if _discard_rays != null and is_instance_valid(_discard_rays):
		_discard_rays.queue_free()
	_discard_rays = null
	if _discard.is_empty():
		return
	var top: CardView = _discard[-1]
	if JokerRays.is_joker(top.current_key()):
		_discard_rays = JokerRays.attach(top, [], side)
		_discard_rays.reduced = reduced


func _set_color(c: String, animate: bool) -> void:
	_color = c
	_color_ring.set_color_key(c, animate)
	_color_mark.set_color_key(c, animate)


func set_night(v: float) -> void:
	night = clampf(v, 0.0, 1.0)
	if _bg == null:
		return
	_bg.tageszeit = night
	_ring.color = UiPalette.ring_color(night)
	for s in _seats:
		(_seats[s] as OpponentSeat).night = night
	_sort_btn.night = night
	_backs_btn.night = night
	for k in _act_btns:
		(_act_btns[k] as PillButton).night = night
	hint_bar.night = night
	fx.night = night
	fx_top.night = night
	_pile.night = night
	_color_mark.night = night
	_color_ring.night = night
	wish_picker.night = night


# Sortierknopf zeigt den Modus („Farbe“, „Wert“, „Punkte“, „Manuell“)
func set_sort_label(text: String) -> void:
	_sort_btn.text = text
	_layout()


func set_backs_active(on: bool) -> void:
	_backs_btn.style = "primary" if on else "ghost"


# Kurze Meldung (TableSource.notice)
func show_notice(text: String, kind := "info") -> void:
	hint_bar.toast(text, kind)


func show_help(face: String, title: String, body: String) -> void:
	help_popup.show_help(face, title, body)


# Farbwahl: Felder beim Ziehen eines Jokers (die Hand meldet hover/drop direkt an wish_picker), Farbrad als Rückfall
func open_color_fields() -> void:
	wish_picker.open_fields(side, _own_counts())


func open_color_wheel() -> void:
	wish_picker.open_wheel(side, _own_counts())


func _own_counts() -> Dictionary:
	if hand != null and hand.has_method("own_color_counts"):
		return hand.call("own_color_counts")
	var counts := {}
	for c in view.get("hand", []):
		var col := CardTextures.color_of(str(c.get("face", "")))
		if col != "":
			counts[col] = int(counts.get(col, 0)) + 1
	return counts


func _on_wheel_color(c: String) -> void:
	if bool((view.get("hints", {}) as Dictionary).get("need_color", false)):
		_emit_action({"a": "color", "color": c})


func _on_mau_pressed() -> void:
	# Kein Ton beim Drücken: Ton und Sprechblase kommen mit dem Ereignis „mau“ auf allen Geräten (AGENTS.md Nr. 21)
	UiApp.vibrate(30, 0.5)
	_emit_action({"a": "mau"})


func _emit_action(a: Dictionary) -> void:
	if input_locked and a.get("a") != "next_round":
		return
	action.emit(a)


# ================================================================= Eingabe

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if wish_picker.mode == "wheel" and event is InputEventMouse:
		var gpos := get_global_transform() * (event as InputEventMouse).position
		if wish_picker.handle_input(event, gpos):
			accept_event()
		return
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_pressing = true
		_press_pos = mb.position
		return
	if not _pressing:
		return
	_pressing = false
	if mb.position.distance_to(_press_pos) > 24.0:
		return
	if _tap(mb.position):
		accept_event()


# Tipp an einer Stelle (lokale Koordinaten des Tisches); true = verbraucht
func _tap(p: Vector2) -> bool:
	var g := get_global_transform() * p
	var wp := _world.to_local(g)
	for s in _seats:
		var node: OpponentSeat = _seats[s]
		if node.hit_catch(g):
			_emit_action({"a": "catch", "target": s})
			return true
	if Rect2(_draw_pos - Vector2(CARD_W, CARD_W * 1.6) * 0.62, Vector2(CARD_W, CARD_W * 1.6) * 1.24).has_point(wp):
		if _pile.highlight and not input_locked:
			_emit_action({"a": "draw"})
			return true
	for s in _seats:
		var node: OpponentSeat = _seats[s]
		if node.hit_fan(g):
			seat_tapped.emit(s)
			# Großansicht nur, wenn die Rückseiten sichtbar sind
			if node.backs_visible():
				backs_viewer.show_backs(node.player_name(), node.keys)
			return true
	return false


# ================================================================= Tischregie

func _d(t: float) -> float:
	return t / maxf(_speed, 0.01) * (0.6 if reduced else 1.0)


func skip_event(ev: Dictionary) -> void:
	fx.clear()
	if str(ev.get("e", "")) == "flip":
		_flip_running = false


func play_event(ev: Dictionary, speed: float) -> float:
	_speed = speed
	var e := str(ev.get("e", ""))
	match e:
		"deal":
			return _ev_deal(ev)
		"play":
			return _ev_play(ev)
		"draw":
			return _ev_draw(ev, false)
		"penalty":
			return _ev_draw(ev, true)
		"skip":
			return _ev_skip(ev)
		"skip_all":
			return _ev_skip_all(ev)
		"reverse":
			return _ev_reverse(ev)
		"color":
			return _ev_color(ev)
		"flip":
			return _ev_flip(ev)
		"pending":
			return _ev_pending(ev)
		"challenge":
			return _ev_challenge(ev)
		"mau":
			return _ev_mau(ev)
		"finish":
			return _ev_finish(ev)
		"catch":
			return _ev_catch(ev)
		"shuffle":
			return _ev_shuffle(ev)
		"round_over":
			return _ev_round_over(ev, false)
		"game_over":
			return _ev_round_over(ev, true)
	return 0.0


func _target() -> Dictionary:
	return director.upcoming_view()


func _target_player(seat: int) -> Dictionary:
	for p in _target().get("players", []):
		if int(p.get("seat", -1)) == seat:
			return p
	return {}


# Rückseiten, die ein Gegner bis zur Zielsicht neu bekommt (Mehrfachmenge Ziel − angezeigt)
func _backs_added(seat: int) -> Array[String]:
	var node := seat_node(seat)
	var out: Array[String] = []
	if node == null:
		return out
	var have := node.keys.duplicate()
	for b in _target_player(seat).get("backs", []):
		var i := have.find(str(b))
		if i >= 0:
			have.remove_at(i)
		else:
			out.append(str(b))
	return out


# Rückseite, die ein Gegner bis zur Zielsicht verliert
func _back_removed(seat: int) -> String:
	var node := seat_node(seat)
	if node == null:
		return ""
	var target: Array = _target_player(seat).get("backs", [])
	if target.is_empty():
		return ""
	var left := target.duplicate()
	for k in node.keys:
		var i := left.find(k)
		if i >= 0:
			left.remove_at(i)
		else:
			return k
	return ""


func _ev_play(ev: Dictionary) -> float:
	var seat := int(ev.get("seat", -1))
	var face := str(ev.get("face", ""))
	var id := int(ev.get("card", -1))
	var dur := _d(0.42)
	var start := {"pos": _center, "rot": 0.0, "width": CARD_W * 0.6, "key": face}
	if seat == my_seat:
		start = {"pos": _hand_point(), "rot": 0.0, "width": HAND_CARD_W, "key": face}
		if hand != null and hand.has_method("take_card"):
			# HandView (F1a) übergibt den Kartenknoten, die Demo-Reihe nur dessen Lage
			var t: Variant = hand.call("take_card", id)
			if t is CardView:
				var cv := t as CardView
				start = {"pos": _world.to_local(cv.global_position), "rot": cv.global_rotation, "width": cv.width * cv.global_scale.x, "key": face}
				cv.queue_free()
			elif t is Dictionary and not (t as Dictionary).is_empty():
				var d := t as Dictionary
				start = {"pos": _world.to_local(d["pos"]), "rot": float(d.get("rot", 0.0)), "width": float(d.get("width", HAND_CARD_W)), "key": face}
	else:
		var node := seat_node(seat)
		if node != null:
			var t := node.take_card(_back_removed(seat))
			start = {"pos": _world.to_local(t["pos"]), "rot": float(t["rot"]), "width": float(t["width"]), "key": str(t["key"])}
	var k := _discard.size() + 1 + face.hash()
	var to_rot := deg_to_rad(float(posmod(k * 37, 15) - 7))
	var flip_to := face if str(start["key"]) != face else ""
	fx.fly_card(str(start["key"]), start["pos"], float(start["rot"]), float(start["width"]), _discard_pos, to_rot, CARD_W, dur,
		{"flip_to": flip_to, "on_land": func() -> void: _land(face, id, seat)})
	_last_player = seat
	_jagd_armed = face.ends_with("_farbjagd")
	_plus_armed = 0
	for kind in ["plus1", "plus5", "wuenscher_plus2"]:
		if face.ends_with("_" + kind):
			_plus_armed = int(kind.right(1))
	return dur + _d(0.1)


func _land(face: String, id: int, seat: int) -> void:
	var c := _push_discard(face, id)
	c.scale = Vector2(1.08, 0.94)
	create_tween().tween_property(c, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var col := CardTextures.color_of(face)
	var dark := face.begins_with("dunkel")
	var tint := UiPalette.glow(col) if col != "" else (UiPalette.MOON if dark else UiPalette.CREAM)
	fx.land_burst(_discard_pos, tint, dark, CARD_W * 0.55)
	UiApp.sound("karte")
	if seat == my_seat:
		UiApp.vibrate(15, 0.5)


func _ev_draw(ev: Dictionary, penalty: bool) -> float:
	var seat := int(ev.get("seat", -1))
	var count := maxi(int(ev.get("count", 1)), 1)
	var faces: Array = ev.get("faces", [])
	var target := _target()
	var me := seat == my_seat
	var slot := _jagd_armed and seat != _last_player and not penalty
	var hidden := not bool((view.get("rules", {}) as Dictionary).get("backs_visible", true))
	var node := seat_node(seat)
	var dest := _seat_point(seat)
	if node != null:
		dest = _world.to_local(node.fan_global_center())
	# Neue eigene Karten (Zielsicht minus aktuelle Hand), um Kennung und Rückseite mitzugeben
	var my_new: Array[Dictionary] = []
	if me:
		var have := {}
		for c in view.get("hand", []):
			have[int(c.get("id", -1))] = true
		for c in target.get("hand", []):
			if not have.has(int(c.get("id", -1))):
				my_new.append(c)
	# Sichtbare Seite jeder gezogenen Karte: zuerst die oberste Stapelseite, dann die übrigen neuen Rückseiten
	var pool: Array[String] = []
	if me:
		for c in my_new:
			if str(c.get("back", "")) != "":
				pool.append(str(c.get("back", "")))
	else:
		pool = _backs_added(seat)
	var fly_keys: Array[String] = []
	for i in count:
		var key := _pile.back_key
		if i == 0:
			pool.erase(key)
		elif not pool.is_empty():
			key = pool.pop_front()
		fly_keys.append(key if key != "" else CardTextures.BACK)
	var final_back := str(target.get("draw_back", _pile.back_key))
	var t := 0.0
	var fly := _d(0.36)
	var used := {}
	for i in count:
		var key := fly_keys[i]
		var face_key: String = str(faces[i]) if me and i < faces.size() else ""
		var card_info := {"id": -1, "face": face_key, "back": key}
		for j in my_new.size():
			if not used.has(j) and (face_key == "" or str(my_new[j].get("face", "")) == face_key):
				used[j] = true
				card_info = my_new[j]
				break
		var flip_to := face_key if me else (CardTextures.BACK if hidden else "")
		var land_key := CardTextures.BACK if hidden and not me else key
		var to_w := HAND_CARD_W if me else (node.card_w if node != null else 60.0)
		var land := func() -> void:
			if me:
				if hand != null and hand.has_method("receive_card"):
					hand.call("receive_card", card_info, _world.to_global(dest))
				UiApp.vibrate(20 + 4 * mini(i, 5), 0.5)
			elif node != null:
				node.add_card(land_key)
		var nxt := fly_keys[i + 1] if i + 1 < count else final_back
		var left := maxi(_pile.count - i - 1, 0)
		var take := func() -> void: _pile.set_pile(nxt, left)
		fx.fly_card(key, _draw_pos, 0.0, CARD_W, dest, 0.0, to_w, fly, {"flip_to": flip_to, "delay": t, "on_land": land})
		var tw := create_tween()
		tw.tween_interval(t + 0.01)
		tw.tween_callback(take)
		if i < 4:
			tw.tween_callback(func() -> void: UiApp.sound("ziehen"))
		if slot:
			t += _d(maxf(0.09, 0.30 * pow(0.8, i)))   # Spielautomat: Takt 300 → 90 ms
		elif count > 1:
			t += _d(0.08 if count < 5 else 0.07)
	var total := t + fly
	var victim_pos := _seat_point(seat) + Vector2(0, -150) if me else _seat_point(seat)
	if node != null:
		victim_pos = node.position
	if penalty:
		fx.stamp(victim_pos + Vector2(0, 48), "Strafe +%d" % count, UiPalette.ALERT, 34, 0.8)
		if me:
			_edge_pulse()
	elif slot:
		var hit_col := UiPalette.glow(_color) if _color != "" else UiPalette.MOON
		var hit := func() -> void:
			fx.float_text(victim_pos + Vector2(0, 36), "Treffer!", 40, hit_col, 1.0, 40.0)
			fx.land_burst(dest, hit_col, true, 50.0)
			if me:
				UiApp.vibrate(60, 0.8)
				_shake = maxf(_shake, 0.45)
		var htw := create_tween()
		htw.tween_interval(total)
		htw.tween_callback(hit)
		total += _d(0.5)
	elif count >= 2 or _plus_armed > 0:
		var big := count >= 5
		var stamp_col := Color("#FF7FCF") if night > 0.5 else UiPalette.INK
		fx.stamp(victim_pos + Vector2(0, 48), "+%d" % count, stamp_col, 64 if big else 50, 0.6)
		if big and not reduced:
			fx.ring_wave(dest, Color("#FF7FCF") if night > 0.5 else UiPalette.ALERT, 20.0, 220.0, 0.6, 9.0)
		if me and not reduced:
			_shake = maxf(_shake, 0.5 if big else 0.3)
	_jagd_armed = false
	_plus_armed = 0
	return total + _d(0.08)


func _ev_deal(ev: Dictionary) -> float:
	var target := _target()
	var players: Array = target.get("players", view.get("players", []))
	var n := players.size()
	if n == 0:
		return 0.0
	UiApp.sound("mischen")
	var per := mini(int(ev.get("count", (target.get("rules", {}) as Dictionary).get("hand_size", 7))), 7)
	var dealer := int(ev.get("dealer", 0))
	var t := 0.0
	var step := _d(0.035)
	var fly := _d(0.3)
	for round_i in per:
		for k in n:
			var s := posmod(dealer + 1 + k, n)
			var dest := _seat_point(s)
			var node := seat_node(s)
			var w := HAND_CARD_W * 0.6 if s == my_seat else (node.card_w if node != null else 60.0)
			if node != null:
				dest = _world.to_local(node.fan_global_center())
			fx.fly_card(_pile.back_key if _pile.back_key != "" else CardTextures.BACK, _draw_pos, 0.0, CARD_W, dest, 0.0, w, fly, {"delay": t, "arc": 30.0})
			t += step
	return t + fly


func _ev_skip(ev: Dictionary) -> float:
	var seat := int(ev.get("seat", -1))
	var p := _seat_point(seat)
	var node := seat_node(seat)
	if node != null:
		node.sleep_for(_d(1.0) + 0.3)
		fx.zzz(node.position + Vector2(18, -30), _d(1.0))
	else:
		fx.zzz(p + Vector2(0, -140), _d(1.0))
		fx.float_text(p + Vector2(0, -100), "Du setzt aus", 34, UiPalette.MOON, _d(1.1), 30.0)
	if seat == my_seat:
		UiApp.vibrate(10, 0.3)
	return _d(0.9)


func _ev_skip_all(ev: Dictionary) -> float:
	var player := int(ev.get("seat", _last_player if _last_player >= 0 else int(view.get("turn", 0))))
	var dir := int(view.get("dir", 1))
	var pts := PackedVector2Array()
	var order: Array[int] = []
	var n := maxi(_n, 1)
	# Der Zugmarker läuft in Spielrichtung einmal um den Tisch, an allen vorbei, zurück zum Spieler
	for k in n + 1:
		var s := posmod(player + dir * k, n)
		order.append(s)
		var p := _seat_point(s)
		if s == my_seat:
			p = _hand_point() + Vector2(0, -120)
		pts.append(p)
	var dur := _d(1.1)
	var col := Color("#FF9ECF") if night > 0.5 else Color("#FF8A24")
	var per := 12
	var path := TableLayout.smooth_path(pts, per)
	var marks := PackedInt32Array()
	for i in pts.size():
		marks.append(i * per)
	fx.comet(path, dur, col, func(i: int) -> void:
		if i > 0 and i < order.size() - 1:
			var node := seat_node(order[i])
			if node != null:
				node.sleep_for(0.8), marks)
	var tw := create_tween()
	tw.tween_interval(dur)
	tw.tween_callback(func() -> void:
		var txt := "Nochmal du!" if player == my_seat else "Nochmal, %s!" % _player_name(player)
		var at := pts[0] + (Vector2(0, -40) if player == my_seat else Vector2(0, 70))
		fx.float_text(at, txt, 40, UiPalette.CREAM, _d(1.0), 30.0))
	return dur + _d(0.5)


func _ev_reverse(ev: Dictionary) -> float:
	var dir := int(ev.get("dir", -int(view.get("dir", 1))))
	var d := _ring.reverse_to(dir, _d(1.0))
	if not _discard.is_empty():
		var top: CardView = _discard[-1]
		var base := top.rotation
		var tw := create_tween()
		tw.tween_property(top, "rotation", base + TAU * (1.0 if dir > 0 else -1.0), d * 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(func() -> void: top.rotation = base)
	return d


func _ev_color(ev: Dictionary) -> float:
	var c := str(ev.get("color", ""))
	var col := UiPalette.glow(c)
	fx.ring_wave(_discard_pos, col, 60.0, maxf(size.x, 1600.0) * 0.75, _d(0.9), 14.0, 0.62)
	var tw := create_tween()
	tw.tween_interval(_d(0.15))
	tw.tween_callback(func() -> void: _set_color(c, true))
	return _d(0.7)


func _ev_pending(ev: Dictionary) -> float:
	_color_ring.pending = int(ev.get("amount", 0))
	_color_ring.pop()
	return _d(0.45)


func _ev_challenge(ev: Dictionary) -> float:
	var ok := bool(ev.get("success", false))
	var text := "Bluff!" if ok else "Sauber!"
	fx.stamp(_discard_pos + Vector2(0, -120), text, UiPalette.ALERT if ok else UiPalette.FILL["gruen"], 54, 0.9, -0.1)
	return _d(1.1)


# „Mau!“: Ton auf jedem Gerät (außer Mau-Ton aus) und eine zufällige Sprechblase beim Rufenden (AGENTS.md Nr. 21)
func _ev_mau(ev: Dictionary) -> float:
	var seat := int(ev.get("seat", -1))
	var node := seat_node(seat)
	if node != null:
		node.player["mau"] = true
		node.queue_redraw()
		node.set("_bump", 1.0)
		create_tween().tween_property(node, "_bump", 0.0, 0.35)
	MauSound.play(-1, seat, "mau")
	show_mau(seat, false)
	return _d(0.7)


# Fertig („Mau-Mau!“): Aufnahme „Mao-Mao“ auf jedem Gerät und die große Doppelblase; danach erst das Rundenende
func _ev_finish(ev: Dictionary) -> float:
	var seat := int(ev.get("seat", -1))
	MauSound.play(-1, seat, "mau_mau")
	show_mau(seat, true)
	return _d(1.0)


# ----------------------------------------------------------------- Mau-Sprechblasen

# Variante für den nächsten Ruf: zufällig (nur Darstellung), nie zweimal dieselbe hintereinander; reduziert = schlicht
func pick_mau_variant() -> String:
	if mau_variant_override != "":
		return mau_variant_override
	if reduced:
		return "schlicht"
	var pool := TableEffects.mau_variants(night > 0.5)
	if pool.size() > 1:
		pool.erase(_mau_last)
	var v: String = pool[_mau_rng.randi_range(0, pool.size() - 1)]
	_mau_last = v
	return v


# Sprechblase beim Rufenden: bei Gegnern am Avatar, beim eigenen Platz über dem Mau-Knopf (sonst über der Hand).
# big = „Mau-Mau!“. Die Blasen liegen in fx_top (über Knöpfen und Rundenende).
func show_mau(seat: int, big := false, variant := "") -> TableEffects.MauBubbleFx:
	var v := variant
	if v == "":
		v = ("maumau_schlicht" if reduced else "maumau") if big else pick_mau_variant()
	var sp := mau_speaker(seat)
	var b := TableEffects.MauBubbleFx.new()
	b.variant = v
	b.night = night
	b.k = 0.86 if TableLayout.compact(_n) else 1.0
	b.accent = UiPalette.avatar(seat)
	b.seed_v = _mau_rng.randi()
	var center := mau_place(sp, b.extent(), b.k, seat)
	b.speaker = Vector2(sp["pos"]) - center
	b.speaker_r = float(sp["r"])
	b.build()
	fx_top.add_child(b)
	b.position = _table_to(fx_top, center)
	return b


# Rufender in Tischkoordinaten: {pos, r (Radius des Avatars bzw. Knopfs), right (Abstand bis hinter Name und Kartenzahl)}
func mau_speaker(seat: int) -> Dictionary:
	var to_table := get_global_transform().affine_inverse()
	var node := seat_node(seat)
	if node != null:
		var p := to_table * node.avatar_global()
		var r := OpponentSeat.AVATAR_R_COMPACT if node.compact else OpponentSeat.AVATAR_R
		var right := (to_table * node.to_global(Vector2(float(node.get("_header_w")) * 0.5, 0.0))).x - p.x
		return {"pos": p, "r": r + 3.0, "right": maxf(right, r)}
	if mau_button.visible and mau_button.is_inside_tree():
		var c := to_table * mau_button.get_global_rect().get_center()
		return {"pos": c, "r": MauButton.SIZE * 0.5 - 8.0, "right": MauButton.SIZE * 0.5}
	var hp := _world.transform * _hand_point()
	return {"pos": hp + Vector2(0, -40), "r": 80.0, "right": 80.0}


# Mitte der Blase (Tischkoordinaten). Lagen: über dem Rufenden, links, rechts hinter Name und Kartenzahl, darunter. Jede Lage
# darf entlang der freien Achse in den Bildschirm rutschen (der Schwanz zeigt weiter zum Rufenden). Gewählt wird die Lage, die
# ganz ins Bild passt und am wenigsten andere Plätze, die Ablage und den Mau-Knopf verdeckt; bei Gleichstand die frühere.
# ext = Umriss der Blase relativ zu ihrer Mitte (MauBubbleFx.extent).
func mau_place(sp: Dictionary, ext: Rect2, k := 1.0, seat := -1) -> Vector2:
	var sz := size if size.x > 10.0 else TableLayout.BASE
	var bounds := Rect2(Vector2(6, 6), sz - Vector2(12, 12))
	var s: Vector2 = sp["pos"]
	var r := float(sp["r"])
	var gap := 30.0 * k
	var cands: Array[Vector2] = [
		Vector2(s.x - ext.get_center().x, s.y - r - gap - ext.end.y),
		Vector2(s.x - r - gap - ext.end.x, s.y - ext.get_center().y - 6.0),
		Vector2(s.x + float(sp["right"]) + gap - ext.position.x, s.y - ext.get_center().y - 6.0),
		Vector2(s.x - ext.get_center().x, s.y + r + gap - ext.position.y),
	]
	var lo := bounds.position - ext.position
	var hi := bounds.end - ext.end
	var avoid := _mau_avoid(seat)
	var best := Vector2.INF
	var best_cost := INF
	for i in cands.size():
		var c := cands[i]
		if i == 0 or i == 3:
			var room := maxf(ext.size.x * 0.5 - 30.0 * k, 0.0)
			c.x = clampf(clampf(c.x, lo.x, maxf(lo.x, hi.x)), c.x - room, c.x + room)
		else:
			var room_y := maxf(ext.size.y * 0.5 - 16.0 * k, 0.0)
			c.y = clampf(clampf(c.y, lo.y, maxf(lo.y, hi.y)), c.y - room_y, c.y + room_y)
		var rect := Rect2(c + ext.position, ext.size)
		if not bounds.encloses(rect):
			continue
		var cost := float(i) * 1500.0
		for a in avoid:
			cost += rect.intersection(a).get_area() if rect.intersects(a) else 0.0
		if cost < best_cost:
			best_cost = cost
			best = c
	if best.is_finite():
		return best
	# Notfall: über dem Rufenden, in den Bildschirm geschoben
	var c0 := cands[0]
	return Vector2(clampf(c0.x, lo.x, maxf(lo.x, hi.x)), clampf(c0.y, lo.y, maxf(lo.y, hi.y)))


# Flächen, die eine Mau-Blase möglichst frei lässt: die anderen Plätze (Kopfzeile und Fächer), die Ablage, der Mau-Knopf
func _mau_avoid(seat: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for s in _seats:
		if s == seat:
			continue
		var node: OpponentSeat = _seats[s]
		var p := _world.transform * node.position
		var r := OpponentSeat.AVATAR_R_COMPACT if node.compact else OpponentSeat.AVATAR_R
		var hw := float(node.get("_header_w"))
		var w := maxf(hw, node.fan_max_w * 0.8)
		var h := r * 2.0 + 8.0 + (44.0 if node.compact else node.card_w * 2.0)
		out.append(Rect2(p.x - w * 0.5, p.y - r - 4.0, w, h))
	var dh := CARD_W * 466.0 / 300.0
	out.append(Rect2(_world.transform * _discard_pos - Vector2(CARD_W * 0.6, dh * 0.6), Vector2(CARD_W * 1.2, dh * 1.2)))
	if seat != my_seat and mau_button.visible:
		out.append(Rect2(mau_button.position, mau_button.size))
	return out


# Punkt aus Tischkoordinaten in die Koordinaten eines Knotens auf einer anderen Ebene (CanvasLayer der Overlays)
func _table_to(node: CanvasItem, p: Vector2) -> Vector2:
	return node.get_global_transform_with_canvas().affine_inverse() * (get_global_transform_with_canvas() * p)


func _ev_catch(ev: Dictionary) -> float:
	var target_seat := int(ev.get("target", -1))
	var p := _seat_point(target_seat) + (Vector2(0, -150) if target_seat == my_seat else Vector2(0, 50))
	fx.stamp(p, "Erwischt!", UiPalette.ALERT, 46, 0.9, -0.12)
	if target_seat == my_seat:
		_edge_pulse()
		UiApp.vibrate(40, 0.6)
	return _d(1.0)


func _ev_shuffle(_ev: Dictionary) -> float:
	UiApp.sound("mischen")
	_pile.riffle(_d(0.8))
	return _d(0.8)


func _ev_round_over(ev: Dictionary, game_over: bool) -> float:
	var target := _target()
	var v := target if not target.is_empty() else view
	var sz := size if size.x > 10.0 else TableLayout.BASE
	var colors: Array = []
	for c in UiPalette.LIGHT_COLORS:
		colors.append(UiPalette.glow(c))
	fx_top.confetti(Rect2(0, 0, sz.x, 10), colors, 320 if game_over else 220)
	_show_round_end(v, ev, game_over)
	UiApp.sound("sieg")
	UiApp.vibrate(30, 0.5)
	return _d(1.4 if game_over else 1.0)


func _show_round_end(v: Dictionary, ev: Dictionary, game_over := false) -> void:
	var ranking: Array = ev.get("ranking", v.get("ranking", []))
	var scores: Variant = ev.get("scores", [])
	if (scores is Array and (scores as Array).is_empty()) or scores == null:
		var arr: Array = []
		for p in v.get("players", []):
			arr.append(int(p.get("score", 0)))
		scores = arr
	# Gleiche Runde schon sichtbar: nicht neu aufbauen (das Ereignis bringt die Rundenpunkte, die Sicht danach nicht)
	var key := str(v.get("round", 0))
	if round_end.visible and key == _round_key:
		return
	_round_key = key
	var rules: Dictionary = v.get("rules", {})
	var can := can_next_round == 1 or (can_next_round < 0 and int(v.get("seat", 0)) == 0)
	var host_name := ""
	for p in v.get("players", []):
		if int(p.get("seat", -1)) == 0:
			host_name = str(p.get("name", ""))
	round_end.show_result(v.get("players", []), ranking, scores, int(v.get("seat", 0)), int(v.get("round", 1)), can,
		str(rules.get("scoring", "none")) == "points500", game_over or str(v.get("phase", "")) == "game_over", host_name)
	for c in _rays_fx.get_children():
		c.queue_free()
	var rays := TableEffects.RaysFx.new()
	rays.position = round_end.winner_anchor() if round_end.size.x > 10.0 else Vector2(800, 200)
	rays.radius = 420.0
	rays.color = Color(1.0, 0.86, 0.35, 0.16)
	rays.material = TableEffects.additive()
	_rays_fx.add_child(rays)


func _edge_pulse() -> void:
	var mat := _edge.material as ShaderMaterial
	if mat == null:
		return
	_edge.visible = true
	mat.set_shader_parameter("size", size)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("intensity", v), 0.0, 0.75, 0.18).set_trans(Tween.TRANS_SINE)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("intensity", v), 0.75, 0.0, 0.55).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void: _edge.visible = false)


# ----------------------------------------------------------------- Flip: Tag ↔ Nacht (06 Abschnitt 4.4)

func _ev_flip(ev: Dictionary) -> float:
	var to_side := str(ev.get("side", "dunkel" if side == "hell" else "hell"))
	var target := _target()
	var k := (0.7 / 1.6 if reduced else 1.0) / maxf(_speed, 0.01)
	var total := 1.6 * k
	_flip_running = true
	input_locked = true
	if hand != null and hand.has_method("set_input_locked"):
		hand.call("set_input_locked", true)
	UiApp.sound("flip")
	UiApp.vibrate(60, 0.3)
	# 0,00 Einatmen: Bild zoomt 3 % hinein
	if not reduced:
		var tw := create_tween()
		tw.tween_method(_set_zoom, 1.0, 1.03, 0.15 * k).set_trans(Tween.TRANS_SINE)
		tw.tween_method(_set_zoom, 1.03, 1.0, 1.0 * k).set_delay(0.9 * k).set_trans(Tween.TRANS_SINE)
	# 0,15 Ablage wendet (alle Karten der Ablage, die oberste zuletzt)
	var top_d: Dictionary = target.get("top", {})
	var new_top := str(top_d.get("face", ""))
	for i in _discard.size():
		var c: CardView = _discard[i]
		var nk := new_top if i == _discard.size() - 1 and new_top != "" else ""
		if nk == "":
			continue
		c.setup(c.card_id, c.current_key(), nk, true)
		c.flip(0.3 * k, 0.15 * k)
	if _discard_rays != null and is_instance_valid(_discard_rays):
		_discard_rays.queue_free()
		_discard_rays = null
	if _discard.size() > 1:
		for i in _discard.size() - 1:
			var c: CardView = _discard[i]
			var tw2 := create_tween()
			tw2.tween_interval(0.15 * k)
			tw2.tween_property(c, "modulate:a", 0.0, 0.3 * k)
	# 0,30 Welle von der Ablage nach außen
	var wave := 1500.0 / k
	var t0 := 0.30 * k
	var new_back := str(target.get("draw_back", ""))
	if new_back != "":
		_pile.flip_to(new_back, 0.24 * k, t0 + _discard_pos.distance_to(_draw_pos) / wave)
	var backs_visible := bool((target.get("rules", view.get("rules", {})) as Dictionary).get("backs_visible", true))
	for s in _seats:
		var node: OpponentSeat = _seats[s]
		var tp := _target_player(s)
		var nk: Array[String] = []
		var tb: Array = tp.get("backs", [])
		if backs_visible and not tb.is_empty():
			for b in tb:
				nk.append(str(b))
		else:
			for j in int(tp.get("count", node.count())):
				nk.append(CardTextures.BACK)
		node.flip_wave(nk, t0 + _discard_pos.distance_to(node.position) / wave, 0.02 * k, 0.2 * k)
	if hand != null and hand.has_method("flip_wave"):
		var faces := {}
		for c in target.get("hand", []):
			faces[int(c.get("id", -1))] = str(c.get("face", ""))
		hand.call("flip_wave", t0 + _discard_pos.distance_to(_hand_point()) / wave, 0.02 * k, 0.2 * k, faces)
	# 0,30–1,20 Stimmung: Himmel, Sonne, Mond, Sterne, Bedienelemente
	var to_night := 1.0 if to_side == "dunkel" else 0.0
	var mood := create_tween()
	mood.tween_interval(t0)
	mood.tween_method(set_night, night, to_night, 0.9 * k).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Haptik: Pause, dann der zweite, stärkere Puls
	var hap := create_tween()
	hap.tween_interval(0.3 * k)
	hap.tween_callback(func() -> void: UiApp.vibrate(120, 0.5))
	# 1,20 Neon zündet (nur zur Nacht), neue Farbe
	var ign := create_tween()
	ign.tween_interval(1.2 * k)
	ign.tween_callback(func() -> void:
		side = to_side
		var tc := str(target.get("color", ""))
		if tc != "":
			_set_color(tc, false)
		if new_top != "" and not _discard.is_empty():
			# Ablage aufräumen: nur noch die gewendete oberste Karte
			var keep: CardView = _discard[-1]
			for c in _discard:
				if c != keep:
					c.queue_free()
			_discard.clear()
			_discard.append(keep)
			_update_rays()
		if to_side == "dunkel":
			_ring.flash = 1.0
			create_tween().tween_property(_ring, "flash", 0.0, 0.5)
			fx.glow_flash(_discard_pos, 190.0, UiPalette.glow(tc) if tc != "" else UiPalette.RING, 0.55, 0.55)
			fx.glow_flash(_draw_pos, 150.0, UiPalette.RING, 0.55, 0.4))
	var end := create_tween()
	end.tween_interval(total)
	end.tween_callback(func() -> void:
		_flip_running = false
		input_locked = false
		if hand != null and hand.has_method("set_input_locked"):
			hand.call("set_input_locked", false))
	return total


func _set_zoom(z: float) -> void:
	_zoom = z
	_world.scale = Vector2(z, z)
	_world.position = _center * (1.0 - z)


func is_flipping() -> bool:
	return _flip_running


func _process(delta: float) -> void:
	if _shake > 0.0 and not reduced:
		_shake = maxf(_shake - delta * 1.6, 0.0)
		var s := _shake * _shake
		var t := Time.get_ticks_msec() * 0.001
		var off := Vector2(sin(t * 47.0) + sin(t * 31.0) * 0.5, cos(t * 41.0) + sin(t * 23.0) * 0.5) * 9.0 * s
		_world.position = _center * (1.0 - _zoom) + off
		_world.rotation = sin(t * 37.0) * 0.012 * s
		if _shake == 0.0:
			_world.rotation = 0.0
			_world.position = _center * (1.0 - _zoom)


# ================================================================= Bausteine des Tisches

class PileView:
	extends Node2D
	# Nachziehstapel: oberste Karte zeigt die Gegenseite der obersten Karte; darunter Kanten je nach Stapelhöhe; Zahl darunter
	var top: CardView
	var back_key := ""
	var count := 0
	var night := 0.0:
		set(v):
			night = v
			queue_redraw()
	var highlight := false:
		set(v):
			highlight = v
			queue_redraw()
	var _time := 0.0
	var _riffle := 0.0

	func _init() -> void:
		top = CardView.new()
		top.width = TableView.CARD_W
		add_child(top)

	func set_pile(key: String, n: int) -> void:
		count = n
		if key != back_key or top.current_key() != key:
			back_key = key
			if key != "":
				top.setup(-1, key, "", true)
		top.visible = n > 0 and key != ""
		queue_redraw()

	# Flip: der ganze Stapel wird umgedreht (Kanten und oberste Karte gemeinsam), danach zeigt er new_key
	func flip_to(new_key: String, dur: float, delay: float) -> void:
		var tw := create_tween()
		if delay > 0.0:
			tw.tween_interval(delay)
		tw.tween_property(self, "scale", Vector2(0.02, 1.04), dur * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void: set_pile(new_key, count))
		tw.tween_property(self, "scale", Vector2.ONE, dur * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	func riffle(dur: float) -> void:
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void:
			_riffle = v
			top.position = Vector2(sin(v * TAU * 3.0) * 10.0 * (1.0 - v), 0)
			queue_redraw(), 0.0, 1.0, dur)
		tw.tween_callback(func() -> void: top.position = Vector2.ZERO)

	func _process(delta: float) -> void:
		_time += delta
		if highlight:
			queue_redraw()

	func _draw() -> void:
		var w := TableView.CARD_W
		var h := w * 466.0 / 300.0
		var dark := back_key.begins_with("dunkel") or back_key == CardTextures.BACK
		var layers := clampi(int(ceil(count / 12.0)), 0, 4)
		for i in range(layers, 0, -1):
			var off := Vector2(i * 2.5, i * 3.0) + Vector2(sin(_riffle * 20.0 + i) * 6.0 * (1.0 - _riffle), 0) * float(_riffle > 0.0)
			var sb := StyleBoxFlat.new()
			sb.bg_color = UiPalette.NIGHT if dark else UiPalette.PAPER_D
			sb.border_color = Color(UiPalette.RING, 0.35) if dark else Color(UiPalette.INK, 0.25)
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(int(w * 0.07))
			sb.shadow_color = Color(0, 0, 0, 0.25)
			sb.shadow_size = 4
			sb.anti_aliasing = true
			draw_style_box(sb, Rect2(-w * 0.5 + off.x, -h * 0.5 + off.y, w, h))
		if count == 0:
			var e := StyleBoxFlat.new()
			e.draw_center = false
			e.border_color = UiPalette.ui_line(night)
			e.set_border_width_all(3)
			e.set_corner_radius_all(int(w * 0.07))
			draw_style_box(e, Rect2(-w * 0.5, -h * 0.5, w, h))
		if highlight:
			var p := 0.5 + 0.5 * sin(_time * 4.0)
			var g := StyleBoxFlat.new()
			g.draw_center = false
			g.border_color = Color(UiPalette.TURN, 0.55 + 0.35 * p)
			g.set_border_width_all(4)
			g.set_corner_radius_all(int(w * 0.09))
			g.expand_margin_left = 7
			g.expand_margin_right = 7
			g.expand_margin_top = 7
			g.expand_margin_bottom = 7
			g.anti_aliasing = true
			draw_style_box(g, Rect2(-w * 0.5, -h * 0.5, w, h))
		var f := UiFonts.text(700, 100.0)
		var t := "Stapel · %d" % count
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		draw_string(f, Vector2(-tw * 0.5, h * 0.5 + 28.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiPalette.ui_muted(night))


class ColorRingView:
	extends Node2D
	# Farbring um die Ablage (Glühen in der aktuellen Farbe) und „+N“-Marke für aufgelaufene Ziehkarten
	const R := 116.0
	var color_key := ""
	var color := Color(1, 1, 1, 0)
	var night := 0.0:
		set(v):
			night = v
			queue_redraw()
	var pending := 0
	var _pop := 0.0
	var _tween: Tween

	func set_color_key(c: String, animate: bool) -> void:
		color_key = c
		var target := UiPalette.glow(c) if c != "" else Color(1, 1, 1, 0)
		if _tween and _tween.is_valid():
			_tween.kill()
		if animate:
			_tween = create_tween()
			_tween.tween_method(func(v: Color) -> void:
				color = v
				queue_redraw(), color, target, 0.35)
		else:
			color = target
			queue_redraw()

	func pop() -> void:
		_pop = 1.0
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void:
			_pop = v
			queue_redraw(), 1.0, 0.0, 0.4)

	func _draw() -> void:
		if color.a > 0.0:
			draw_circle(Vector2.ZERO, R + 16.0, Color(color, 0.07 + 0.08 * night))
			draw_arc(Vector2.ZERO, R + 6.0, 0.0, TAU, 96, Color(color, 0.22), 18.0, true)
			draw_arc(Vector2.ZERO, R, 0.0, TAU, 96, color, 5.0, true)
			draw_arc(Vector2.ZERO, R - 7.0, 0.0, TAU, 96, Color(color, 0.18), 10.0, true)
		if pending > 0:
			var c := Vector2(R * 0.78, -R * 0.78)
			var s := 1.0 + 0.35 * sin(_pop * PI)
			draw_circle(c, 30.0 * s, UiPalette.INK if night < 0.5 else Color("#FF7FCF"))
			draw_circle(c, 26.0 * s, UiPalette.CREAM)
			var f := UiFonts.text(800, 85.0)
			var t := "+%d" % pending
			var fs := int(24 * s)
			var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, c + Vector2(-tw * 0.5, fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiPalette.INK)


class ColorMark:
	extends Node2D
	# Aktuelle Farbe zwischen den Stapeln: Formsymbol und Name (Farbe nie allein: Symbol + Wort)
	var color_key := ""
	var night := 0.0:
		set(v):
			night = v
			queue_redraw()
	var _pop := 0.0

	func set_color_key(c: String, animate: bool) -> void:
		color_key = c
		if animate:
			var tw := create_tween()
			tw.tween_method(func(v: float) -> void:
				_pop = v
				queue_redraw(), 1.0, 0.0, 0.45)
		queue_redraw()

	func _draw() -> void:
		if color_key == "":
			return
		var s := 1.0 + 0.3 * sin(_pop * PI)
		var col := UiPalette.glow(color_key)
		var isz := 46.0 * s
		var bg := UiPalette.NIGHT if night > 0.5 else UiPalette.PAPER
		if night > 0.5:
			draw_circle(Vector2(0, -16), 40.0 * s, Color(col, 0.16))
		draw_texture_rect(UiIcons.symbol(color_key, 96, col, bg.lerp(col, 0.25)), Rect2(Vector2(-isz * 0.5, -16.0 - isz * 0.5), Vector2(isz, isz)), false)
		var f := UiFonts.text(800, 100.0)
		var t := UiPalette.color_name(color_key)
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(f, Vector2(-tw * 0.5, 32.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UiPalette.ui_text(night))
