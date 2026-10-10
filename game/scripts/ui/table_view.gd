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
# Hausregeln mit Zusatzkarten (TableHouseRules): Kartentausch (swap_hands), Glücksspiel (Automat GambleMachine in der Mitte,
# Einsatzstapel StakePile am Platz; Setzen über die Hand, Knopf-Tipp → action press) und Farbe mit ablegen (discard_color).
# „Spielbare Karten hervorheben“ aus (App.settings "hervorheben"): die Hand markiert nichts, der Hinweis verrät nicht „nichts passt“.

signal action(a: Dictionary)
signal sort_pressed
signal backs_pressed
signal seat_tapped(seat: int)
signal big_changed(on: bool)          # großer Modus umgeschaltet (TableScreen legt die Hand neu)
signal night_switched(on: bool)       # Tag/Nacht über die Schwelle 0,5 gewechselt (Überlagerungen im Spiel folgen, 1.1.3)

const GROUP := "tisch_ansicht"         # Gruppe des Tisches: Überlagerungen finden ihn darüber (follow_night)

const CARD_W := 116.0                 # Stapel und Ablage
const HAND_CARD_W := 150.0            # Ersatzbreite, wenn keine Hand angeschlossen ist
const DISCARD_KEEP := 3               # sichtbare Karten auf der Ablage
const DISCARD_UNDER_MAX := 7          # zusätzlich höchstens so viele mitabgelegte Karten unter der obersten (Farbe mit ablegen)
# Bausteine der Hausregeln per preload (laufen so auch, bevor ein Import den Klassen-Cache erneuert hat)
const GambleMachineScript := preload("res://scripts/ui/gamble_machine.gd")
const StakePileScript := preload("res://scripts/ui/stake_pile.gd")
const DiscardBrowserScript := preload("res://scripts/ui/discard_browser.gd")
const HouseRulesScript := preload("res://scripts/ui/table_house_rules.gd")
const HINT_NOTHING_FITS := "Du bist dran – nichts passt"

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
var gamble_machine: GambleMachineScript   # Glücksspiel-Automat (nur während eines Glücksspiels sichtbar)
var stake_pile: StakePileScript           # Einsatzstapel des Glücksspielers
var staking := false                  # eigener Einsatz fällig: ausgespielte Handkarten gehen auf den Einsatz
var highlight := true                 # „Spielbare Karten hervorheben“ (persönliche Einstellung)

var _bg: TableBackground
var _world: Node2D
var _ring: DirectionRing
var _seat_layer: Node2D
var _catch_layer: Node2D
var _pile: PileView
var _color_ring: ColorRingView
var _pending_badge: PendingBadge      # „+N“-Plakette über Ablage und Farbschild (1.1.3)
var _discard_layer: Node2D
var _discard: Array[CardView] = []
var _color_mark: ColorMark
var _ui: Control
var _sort_btn: PillButton
var _backs_btn: PillButton
var _act_btns: Dictionary = {}
var _pick_key := ""                  # laufende eigene Auswahl „Farbe mit ablegen“ (Runde, Platz, Farbe); "" = keine
var _pick_color := false             # Ablegen-Joker: nach der Auswahl noch die Spielfarbe wählen
var _pick_wait := false              # Farbrad für die Spielfarbe ist offen
var _pick_cards: Array = []
var _edge: ColorRect
var _overlay: Control
var _seats: Dictionary = {}           # Platz → OpponentSeat
var _n := 0
var _speed := 1.0
var _color := ""
var _discard_rays: JokerRays
var discard_browser: DiscardBrowserScript # „Ablage durchsehen“ (1.0.1): Tipp auf die Ablage schiebt Karten zur Seite
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
var _house: HouseRulesScript
var me_badge: OpponentSeat            # eigener Platz (0.1.4): Name, Kartenzahl, Strahlenkranz und Denkblase links über den Knöpfen
var list_header: ListHeader           # großer Modus: Kreispfeil der Spielrichtung + „Reihenfolge“ über der Liste (08.10.2026)
var _hand_halo: OpponentSeat.TurnHaloScript              # Strahlenkranz um die eigene Hand am Zug
var _hand_halo_want := false                                # eigener Zug: Schein soll an, sobald keine Animation mehr läuft
var _hand_halo_cards := 0                                   # so viele Karten muss die Hand haben, bevor der Schein angeht

var _center := Vector2(800, 320)
var _draw_pos := Vector2(623, 320)
var _discard_pos := Vector2(977, 320)

# Großer Modus (Beta 1.1.1, BigLayout): riesiger Stapel und Ablage, Spielerliste rechts (die Plätze werden zu Listenzeilen und
# rollen: wer dran ist oben, darunter der Nächste). Persönliche Einstellung "grosser_modus", live umschaltbar.
var big := false
var pile_w := CARD_W                  # Breite von Stapel und Ablage (groß: BigLayout.pile_w)
var _list_slot := {}                  # Platz → fortlaufende Stelle in der Liste (rollt weich zum Ziel)
var _list_target := {}
var _list_turn := -1
var _list_dir := 0
var _list_flip := -1.0                # Richtungswechsel: 0 … 1 (Zeilen klappen zu, Reihenfolge dreht, klappen auf); < 0 = aus
var _was_my_turn := false


# ================================================================= Aufbau

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mau_rng.randomize()
	director = Director.new()
	director.handler = self
	# reine Buchungen ohne Animation: zählen nicht zum Rückstand (sonst doppeltes Tempo z. B. bei jedem Glücksspiel-Treffer)
	director.quiet_events = {"turn": true, "keep": true, "accept": true, "choose_color": true, "pass": true, "round_start": true,
		"start": true}
	add_child(director)
	_bg = TableBackground.new()
	add_child(_bg)
	_world = Node2D.new()
	add_child(_world)
	_ring = DirectionRing.new()
	_world.add_child(_ring)
	_seat_layer = Node2D.new()
	_world.add_child(_seat_layer)
	me_badge = OpponentSeat.new()
	me_badge.name = "Ich"
	me_badge.header_only = true
	me_badge.visible = false
	_world.add_child(me_badge)
	list_header = ListHeader.new()
	list_header.name = "Reihenfolge"
	list_header.visible = false
	_world.add_child(list_header)
	_pile = PileView.new()
	_world.add_child(_pile)
	_color_ring = ColorRingView.new()
	_world.add_child(_color_ring)
	_discard_layer = Node2D.new()
	_world.add_child(_discard_layer)
	_color_mark = ColorMark.new()
	_world.add_child(_color_mark)
	_pending_badge = PendingBadge.new()
	_pending_badge.name = "Strafplakette"
	_pending_badge.ring = _color_ring
	_color_ring.badge = _pending_badge
	_world.add_child(_pending_badge)
	discard_browser = DiscardBrowserScript.new()
	discard_browser.name = "AblageDurchsehen"
	discard_browser.opened_changed.connect(func(open: bool) -> void:
		_discard_layer.visible = not open
		_pending_badge.visible = not open)
	_world.add_child(discard_browser)
	stake_pile = StakePileScript.new()
	stake_pile.name = "Einsatz"
	_world.add_child(stake_pile)
	gamble_machine = GambleMachineScript.new()
	gamble_machine.name = "Gluecksspiel"
	_world.add_child(gamble_machine)
	_house = HouseRulesScript.new(self)
	hand_layer = Node2D.new()
	hand_layer.name = "Hand"
	_world.add_child(hand_layer)
	_hand_halo = OpponentSeat.TurnHaloScript.new()
	_hand_halo.name = "Kranz"
	_hand_halo.reach = 70.0
	hand_layer.add_child(_hand_halo)
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
	for key in ["keep", "challenge", "accept", "pick", "undo"]:
		var label: String = {"keep": "Behalten", "challenge": "Anzweifeln", "accept": "Annehmen", "pick": "Ablegen", "undo": "Zurücknehmen"}[key]
		var icon: String = {"keep": "haken", "challenge": "kreuz", "accept": "stapel", "pick": "haken", "undo": "zurueck"}[key]
		var b := _pill(label, icon)
		b.style = "ghost" if key == "undo" else "primary"
		b.visible = false
		var a: String = key
		if a == "pick":
			b.pressed.connect(_on_pick_pressed)
		elif a == "undo":
			b.pressed.connect(undo_pick)
		else:
			b.pressed.connect(func() -> void: _emit_action({"a": a}))
		_act_btns[key] = b
	mau_button = MauButton.new()
	mau_button.mau_pressed.connect(_on_mau_pressed)
	_ui.add_child(mau_button)
	# „Erwischt!“-Knöpfe der Plätze über Tisch, Hand und Hinweisleiste, aber unter Farbwahl und Überlagerungen (Nutzerbefund 08.10.2026)
	_catch_layer = Node2D.new()
	_catch_layer.name = "ErwischtEbene"
	add_child(_catch_layer)
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
	wish_picker.cancelled.connect(_on_wheel_cancelled)
	resized.connect(_layout)


func _ready() -> void:
	add_to_group(GROUP)
	reduced = UiApp.reduced_effects()
	highlight = HandView.truthy(UiApp.setting("hervorheben", true))
	var app := UiApp.app()
	var st: Variant = app.get("settings") if app != null else null
	if st is Object and (st as Object).has_signal("changed"):
		(st as Object).connect("changed", _on_setting_changed)
	set_big(HandView.truthy(UiApp.setting("grosser_modus", false)))
	set_night(night)


# Effektstufe, Hervorheben und großen Modus live umschalten (Einstellungen; die Hand hört selbst auf „hervorheben“)
func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "grosser_modus":
		set_big(HandView.truthy(value))
	elif key == "effekte":
		reduced = str(value) == "reduziert"
	elif key == "hervorheben":
		highlight = HandView.truthy(value)
		if not view.is_empty():
			_apply_hints(view.get("hints", {}), int(view.get("turn", -1)))


func _pill(text: String, icon: String) -> PillButton:
	var b := PillButton.new()
	b.text = text
	b.icon_name = icon
	_ui.add_child(b)
	return b


func set_reduced(on: bool) -> void:
	reduced = on
	if discard_browser:
		discard_browser.reduced = on
	if gamble_machine:
		gamble_machine.reduced = on
	if fx:
		fx.reduced = on
		fx_top.reduced = on
	if _bg:
		_bg.motion = not on
	if list_header:
		list_header.reduced = on
	if me_badge:
		me_badge.reduced = on
		_hand_halo.motion = not on
		for s in _seats:
			(_seats[s] as OpponentSeat).reduced = on


# Hand anschließen (HandView oder Demo-Reihe); der Knoten wandert in hand_layer
func set_hand(node: Node) -> void:
	hand = node
	if node is CanvasItem and node.get_parent() == null:
		hand_layer.add_child(node)
	# Großansicht offen: Eingaben gehen zuerst an die Hand („?“ der Kartenhilfe), nicht an den Mau-Knopf darunter
	if node != null and node.has_signal("big_view_changed") and not node.is_connected("big_view_changed", _on_big_view):
		node.connect("big_view_changed", _on_big_view)
	_update_avoid()


func _on_big_view(id: int) -> void:
	mau_button.mouse_filter = Control.MOUSE_FILTER_STOP if id == -1 else Control.MOUSE_FILTER_IGNORE


# Flächen, auf die die Hand das „?“ der Großansicht nicht legt (Mau-Knopf)
func _update_avoid() -> void:
	if hand != null and "avoid_global" in hand and mau_button.is_inside_tree():
		var arr: Array[Rect2] = [mau_button.get_global_rect()]
		hand.set("avoid_global", arr)


func _layout() -> void:
	var sz := size if size.x > 10.0 else TableLayout.BASE
	if big:
		pile_w = BigLayout.pile_w(sz)
		_center = BigLayout.table_center(sz)
		_draw_pos = BigLayout.draw_pile_pos(sz)
		_discard_pos = BigLayout.discard_pos(sz)
	else:
		pile_w = CARD_W
		_center = TableLayout.table_center(sz)
		_draw_pos = TableLayout.draw_pile_pos(sz)
		_discard_pos = TableLayout.discard_pos(sz)
	_bg.table_center = _center
	_ring.position = _center
	_ring.radii = TableLayout.ring_radii(sz)
	_pile.position = _draw_pos
	_pile.set_width(pile_w)
	_color_ring.position = _discard_pos
	_pending_badge.position = _discard_pos
	_color_ring.card_size = Vector2(pile_w, pile_w * CardView.ASPECT) if big else Vector2.ZERO
	_color_ring.queue_redraw()
	_discard_layer.position = _discard_pos
	for c in _discard:
		c.width = pile_w
	discard_browser.position = _discard_pos
	discard_browser.set_big(big, pile_w)
	_color_mark.position = BigLayout.color_mark_pos(sz) if big else _center
	_color_mark.k = BigLayout.COLOR_SCALE if big else 1.0
	gamble_machine.position = _center
	wish_picker.position = _discard_pos
	wish_picker.wheel_center = Vector2(sz.x * 0.5, sz.y * 0.47) - _discard_pos
	var pk := 1.0 if not big else BigLayout.PILL_H / PillButton.TOUCH_MIN
	for b: PillButton in [_sort_btn, _backs_btn] + _act_btns.values():
		b.font_size = UiFonts.px(BigLayout.PILL_FONT if big else 20)
		b.big = pk
	_sort_btn.size = Vector2(_sort_btn.preferred_width(), _sort_btn.touch_h())
	_backs_btn.size = Vector2(_backs_btn.preferred_width(), _backs_btn.touch_h())
	_sort_btn.position = BigLayout.sort_pos(sz) if big else Vector2(40.0, sz.y - 190.0)
	_backs_btn.position = BigLayout.backs_pos(sz) if big else Vector2(40.0, sz.y - 108.0)
	var ms := BigLayout.MAU if big else MauButton.SIZE
	mau_button.custom_minimum_size = Vector2(ms, ms)
	mau_button.size = Vector2(ms, ms)
	mau_button.position = BigLayout.mau_pos(sz) if big else Vector2(sz.x - 46.0 - MauButton.SIZE, sz.y - 40.0 - MauButton.SIZE)
	if not big:
		me_badge.position = Vector2(44.0, sz.y - 238.0)
	var head := BigLayout.list_head_rect(sz)
	list_header.position = head.position
	list_header.head_size = head.size
	list_header.visible = big
	_update_avoid()
	hint_bar.hint_y = BigLayout.hint_y(sz) if big else sz.y - 207.0
	hint_bar.pivot_offset = Vector2(sz.x * 0.5, hint_bar.hint_y)
	hint_bar.scale = Vector2.ONE * (BigLayout.HINT_SCALE if big else 1.0)
	hint_bar.opaque = big
	hint_bar.queue_redraw()
	_layout_action_buttons(true)
	_place_seats(false)
	if _house != null:
		_house.place_pile()
	update_hand_target()


# Großer Modus an/aus (Einstellung "grosser_modus", live): Plätze werden zu Listenzeilen, Stapel und Ablage riesig, Knöpfe größer,
# ruhiger Hintergrund. Die Hand legt TableScreen über big_changed neu (BigLayout.hand_rect).
func set_big(on: bool) -> void:
	var changed := on != big
	big = on
	_bg.calm = on
	_ring.visible = not on
	for s in _seats:
		var node: OpponentSeat = _seats[s]
		node.compact = TableLayout.compact(_n) and not on
		node.list_mode = on
	me_badge.list_mode = on
	me_badge.me_entry = on
	me_badge.header_only = true
	if not on:                            # Liste blendet Zeilen aus (fertig, unter der letzten Zeile); am Tisch alle sichtbar
		for s in _seats:
			(_seats[s] as CanvasItem).modulate.a = 1.0
			(_seats[s] as CanvasItem).z_index = 0
		me_badge.modulate.a = 1.0
	_list_slot.clear()
	_list_target.clear()
	_list_flip = -1.0
	_layout()
	_update_rays()                        # Joker-Strahlen passend zur neuen Kartengröße
	if changed:
		big_changed.emit(on)


# Handbereich für TableScreen (normal wie bisher, groß mit größeren Karten)
func hand_rect(sz: Vector2) -> Rect2:
	if big:
		return BigLayout.hand_rect(sz)
	return Rect2(270.0, sz.y - 220.0, maxf(sz.x - 540.0, 400.0), 220.0)


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


# Oberste bzw. unterste angezeigte Ablagekarte (null = Ablage leer) und ihre Ebene (Flüge unter die oberste Karte)
func discard_top() -> CardView:
	return _discard[-1] if not _discard.is_empty() else null


func discard_bottom() -> CardView:
	return _discard[0] if not _discard.is_empty() else null


func discard_layer() -> Node2D:
	return _discard_layer


# Mitabgelegte Karte (Farbe mit ablegen) wird Teil der Ablage, direkt unter der obersten Karte
func adopt_under_top(c: CardView) -> void:
	if c == null or not is_instance_valid(c):
		return
	if c.get_parent() != _discard_layer:
		c.reparent(_discard_layer)
	if _discard.is_empty():
		_discard.append(c)
		return
	var top: CardView = _discard[-1]
	if c.get_index() > top.get_index():
		_discard_layer.move_child(c, top.get_index())
	_discard.insert(_discard.size() - 1, c)
	while _discard.size() > DISCARD_KEEP + DISCARD_UNDER_MAX:
		var old: CardView = _discard.pop_front()
		old.queue_free()


# Glücksspiel: Einsatzstapel eines Platzes (Tischkoordinaten). Eigener Platz: vor der Hand links; Gegner: neben dem Fächer zur
# Tischmitte hin (oben sitzende rechts daneben), immer im Bild.
func stake_point(seat: int) -> Vector2:
	var sz := size if size.x > 10.0 else TableLayout.BASE
	var node := seat_node(seat)
	if node == null or (seat == my_seat and int(view.get("seat", -1)) >= 0):
		if big:                           # großer Modus: über dem Nachziehstapel, links neben der Hand
			return Vector2(BigLayout.hand_rect(sz).position.x + 30.0, BigLayout.hint_y(sz) - 90.0)
		return TableLayout.own_stake_pos(sz)
	if big:                               # großer Modus: links neben der Listenzeile
		var bw := stake_card_w(seat)
		var by := clampf(node.position.y, bw * CardView.ASPECT * 0.5 + 8.0, sz.y - bw * CardView.ASPECT * 0.5 - 40.0)
		return Vector2(node.position.x - node.row_size.x * 0.5 - bw * 0.6 - 14.0, by)
	var side := 1.0 if node.position.x <= _center.x + 40.0 else -1.0
	var half := (OpponentSeat.BAR_W if node.compact else node.fan_max_w) * 0.5
	var w := stake_card_w(seat)
	var y := node.header_height() * 0.5 + 10.0 + (24.0 if node.compact else node.card_w * 0.78)
	var p := node.position + Vector2(side * (half + w * 0.6 + 16.0), y)
	var h := w * CardView.ASPECT
	return Vector2(clampf(p.x, w * 0.6 + 8.0, sz.x - w * 0.6 - 8.0), clampf(p.y, h * 0.5 + 8.0, sz.y - h * 0.5 - 40.0))


func stake_card_w(seat: int) -> float:
	var node := seat_node(seat)
	if node == null or (seat == my_seat and int(view.get("seat", -1)) >= 0):
		return 96.0 if big else 70.0
	if big:
		return 80.0
	return clampf(node.card_w, 48.0, 64.0)


# Aktuelle Farbe in der Mitte ein/aus (während eines Glücksspiels steht dort der Automat; der Farbring zeigt die Farbe weiter)
func set_color_mark_visible(on: bool) -> void:
	_color_mark.visible = on


# Ziel der Hand: ausgespielte Karten fliegen zur Ablage bzw. beim eigenen Einsatz auf den Einsatzstapel; neue kommen vom Stapel
func update_hand_target() -> void:
	if hand == null or not ("play_target" in hand):
		return
	var xf := get_global_transform()
	if staking:
		hand.set("play_target", xf * stake_pile.position)
		var cw := HandLayout.card_width(float((hand.get("layout_rect") as Rect2).size.y)) if "layout_rect" in hand else HAND_CARD_W
		hand.set("play_target_scale", stake_pile.card_w / maxf(cw, 1.0))
	else:
		hand.set("play_target", xf * _discard_pos)
		var hw := HandLayout.card_width(float((hand.get("layout_rect") as Rect2).size.y)) if "layout_rect" in hand else HAND_CARD_W
		hand.set("play_target_scale", pile_w / maxf(hw, 1.0) if big else 0.66)
	if "spawn_from" in hand:
		hand.set("spawn_from", xf * _draw_pos)


# ================================================================= Abgleich mit der Sicht

func handle_state(events: Array, new_view: Dictionary) -> void:
	_close_browser_on(events)
	director.enqueue(events, new_view)


func play_events(events: Array) -> void:
	_close_browser_on(events)
	director.enqueue(events, {})


# Ablage durchsehen: Ändert sich die Ablage (Legen, Flip, Mischen …), springt alles sofort zurück.
func _close_browser_on(events: Array) -> void:
	for e in events:
		if e is Dictionary and str(e.get("e", "")) in ["play", "flip", "shuffle", "discard_color", "stake_discard", "start", "round_start"]:
			discard_browser.close_now()
			return


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
			node.reduced = reduced
			_seat_layer.add_child(node)
			node.attach_catch_layer(_catch_layer)
			_seats[s] = node
		node.show_score = show_score
		node.compact = TableLayout.compact(_n) and not big
		node.list_mode = big
		var fm := TableLayout.fan_metrics(_n)
		node.card_w = fm.x
		node.fan_max_w = fm.y
		node.night = night
		node.set_player(wanted[s], backs_visible)
	if not big:
		_place_seats(false)
	# Stapel, Ablage, Farbe, Richtung
	_pile.set_pile(str(v.get("draw_back", "")), int(v.get("draw_count", 0)))
	var top: Dictionary = v.get("top", {})
	_set_top(str(top.get("face", "")), int(top.get("id", -1)))
	var names: Array = []
	for p in players:
		names.append(str(p.get("name", "")))
	discard_browser.set_log(v.get("discard_log", []) if v.get("discard_log", []) is Array else [], names)
	_set_color(str(v.get("color", "")), false)
	_ring.set_direction(int(v.get("dir", 1)))
	var pending: Dictionary = v.get("pending", {})
	_color_ring.pending = int(pending.get("amount", 0)) if not pending.is_empty() else 0
	_color_ring.queue_redraw()
	# Zug, Hinweise, Knöpfe
	var turn := int(v.get("turn", -1))
	var next := next_seat(players, turn, int(v.get("dir", 1)))
	for s in _seats:
		var node: OpponentSeat = _seats[s]
		node.set_turn(s == turn and not str(v.get("phase", "")) in ["round_over", "game_over"], s == next)
	_apply_me(v, turn, next)
	if big:
		_update_list(true)
	_apply_hints(v.get("hints", {}), turn)
	if hand != null and hand.has_method("apply_view"):
		hand.call("apply_view", v)
	_apply_pick(v)
	_house.apply_view(v)
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


# Eigener Platz (0.1.4): Name mit Kartenzahl, am Zug Strahlenkranz um Namen und Hand (nur am eigenen Gerät mit Platz)
func _apply_me(v: Dictionary, turn: int, next: int) -> void:
	var mine := int(v.get("seat", 0)) >= 0 and not _player(my_seat).is_empty()
	var phase := str(v.get("phase", "turn"))
	var playing := phase != "round_over" and phase != "game_over"
	me_badge.visible = mine
	if mine:
		me_badge.night = night
		me_badge.set_player(_player(my_seat), false)
		me_badge.set_turn(turn == my_seat and playing, next == my_seat)
	else:
		me_badge.set_turn(false)
	_hand_halo_want = mine and turn == my_seat and playing
	_hand_halo_cards = (v.get("hand", []) as Array).size()
	_sync_hand_halo(0.0)
	if _hand_halo_want and not _was_my_turn:
		_notify_my_turn()
	_was_my_turn = _hand_halo_want


# „Du bist dran“ (Beta 1.1.1): Dran-Ton nach der Einstellung Spieltöne (AppSound), kurze Vibration nur mit "zug_vibration" (ab Werk an)
func _notify_my_turn() -> void:
	UiApp.sound("dran")
	if HandView.truthy(UiApp.setting("zug_vibration", true)) and (OS.has_feature("mobile") or OS.get_name() == "Android"):
		Input.vibrate_handheld(160)


# Schein hinter der eigenen Hand: erst an, wenn Austeilen und andere Animationen fertig sind (Nutzerbefund 06.10.2026: beim
# Austeilen wanderte er mit den hereinfliegenden Karten mit); danach gleitet er weich zum Kasten der Handkarten.
func _sync_hand_halo(delta: float) -> void:
	var busy := (director != null and director.is_busy()) or (hand != null and hand.has_method("is_settling") and bool(hand.call("is_settling")))
	# beim Austeilen kommen die Karten einzeln an: erst wenn alle da sind (Nutzerbefund 06.10.2026, Schein wanderte mit)
	if hand != null and hand.has_method("card_count") and int(hand.call("card_count")) < _hand_halo_cards:
		busy = true
	# Animationen verzögern nur das Einschalten; ein schon leuchtender Schein bleibt an (kein Flackern beim Umsortieren)
	_hand_halo.set_active(_hand_halo_want and (_hand_halo.active or not busy))
	if not _hand_halo.visible or hand == null or not (hand is Node2D):
		return
	# fest mittig im Kartenfeld (Nutzerwunsch 06.10.2026): wandert weder beim Ausspielen noch beim Ziehen oder Kleinerwerden der Hand
	var lr: Variant = hand.get("layout_rect")
	if not (lr is Rect2) or (lr as Rect2).size.x < 1.0:
		return
	var field: Rect2 = lr
	var w := field.size.x * 0.7
	var r := Rect2(field.position.x + (field.size.x - w) * 0.5, field.position.y + field.size.y * 0.5, w, field.size.y)   # ½ Höhe tiefer (Nutzerwunsch)
	var xf := (hand as Node2D).transform
	var gr := Rect2(xf * r.position, (xf.basis_xform(r.size)).abs())
	if not gr.is_equal_approx(_hand_halo.box):
		_hand_halo.set_box(gr, 90.0)


# Jemand hat gehandelt: seine Denkblase verschwindet, die Uhr beginnt neu
func _poke(seat: int) -> void:
	if seat == my_seat and me_badge.visible:
		me_badge.poke()
	var node := seat_node(seat)
	if node != null:
		node.poke()


# „gleich dran“: der nächste Platz in Spielrichtung, der noch mitspielt (place 0). Fertige Spieler („bis zum Letzten“) überspringt
# das Spiel, also auch die Anzeige (Nachtest 1, N3). Mit nur zwei Spielern im Spiel sagt die Marke nichts: -1. Ein Aussetzen steht
# erst fest, wenn die Karte liegt; dann kommt ohnehin eine neue Sicht.
static func next_seat(players: Array, turn: int, dir: int) -> int:
	var n := players.size()
	if turn < 0 or turn >= n:
		return -1
	var active := {}
	for i in n:
		var p: Dictionary = players[i]
		if int(p.get("place", 0)) == 0:
			active[int(p.get("seat", i))] = true
	if active.size() <= 2:
		return -1
	var step := -1 if dir < 0 else 1
	var s := turn
	for i in n - 1:
		s = posmod(s + step, n)
		if active.has(s):
			return s
	return -1


func _apply_hints(h: Dictionary, turn: int) -> void:
	var me_turn := turn == my_seat and int(view.get("seat", 0)) >= 0
	var text := str(h.get("text", "Du bist dran." if me_turn else ""))
	var dp := discard_pick_of(view)
	var shown := ""
	if not dp.is_empty() and (int(dp.get("seat", -1)) != my_seat or int(view.get("seat", 0)) < 0):
		shown = I18n.t("%s wählt aus …") % str(_player(int(dp.get("seat", -1))).get("name", "?"))
	else:
		shown = _hint_local(text, h.get("lt", []) if h.get("lt") is Array else [])
	hint_bar.show_hint(shown, me_turn)
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


# ================================================================= Farbe mit ablegen: Auswahl (Phase discard_pick)

static func discard_pick_of(v: Dictionary) -> Dictionary:
	var raw: Variant = v.get("discard_pick", {})
	return raw if raw is Dictionary else {}


# Eigene Auswahl: Kandidaten (hints.can_pick) in der Hand vorausgewählt, Knopf „Ablegen (n)“. Beim Ablegen-Joker (hints.pick_color)
# folgt nach dem Knopf das Farbrad „Mit welcher Farbe geht es weiter?“. Eine laufende Auswahl wird bei neuer Sicht nicht
# zurückgesetzt (gleicher Schlüssel aus Runde, Platz und Farbe).
func _apply_pick(v: Dictionary) -> void:
	var dp := discard_pick_of(v)
	var h: Dictionary = v.get("hints", {})
	var cands: Array = h.get("can_pick", [])
	var mine := not dp.is_empty() and int(v.get("seat", -1)) >= 0 and int(dp.get("seat", -1)) == int(v.get("seat", -1))
	var b: PillButton = _act_btns["pick"]
	if not mine:
		if _pick_key != "":
			_pick_key = ""
			_pick_wait = false
			if wish_picker.mode == "wheel" and wish_picker.title != "":
				wish_picker.close()
			if hand != null and hand.has_method("clear_pick"):
				hand.call("clear_pick")
		b.visible = false
		(_act_btns["undo"] as PillButton).visible = false
		_layout_action_buttons()
		return
	_pick_color = bool(h.get("pick_color", false))
	var key := "%s/%s/%s" % [str(v.get("round", 0)), str(dp.get("seat", -1)), str(dp.get("color", ""))]
	if key != _pick_key:
		_pick_key = key
		_pick_wait = false
		if hand != null and hand.has_method("set_pick"):
			hand.call("set_pick", cands)
			if not hand.is_connected("pick_changed", _on_pick_changed):
				hand.connect("pick_changed", _on_pick_changed)
		if _pick_color and cands.is_empty():   # Ablegen-Joker ohne Karten dieser Farbe: gleich die Spielfarbe
			_pick_key = key
			_on_pick_pressed()
			return
	b.visible = not _pick_wait
	(_act_btns["undo"] as PillButton).visible = not _pick_wait and bool(h.get("can_undo", false))
	_update_pick_button()


func _on_pick_changed(_ids: Array) -> void:
	_update_pick_button()


func picked_cards() -> Array:
	if hand != null and hand.has_method("get_pick"):
		return hand.call("get_pick")
	return []


func _update_pick_button() -> void:
	var b: PillButton = _act_btns["pick"]
	var cands: Array = (view.get("hints", {}) as Dictionary).get("can_pick", [])
	b.text = I18n.t("Ablegen (%d)") % picked_cards().size() if not cands.is_empty() else "Weiter"
	_layout_action_buttons()


func _on_pick_pressed() -> void:
	if _pick_key == "" or input_locked:
		return
	_pick_cards = picked_cards()
	if _pick_color:
		_pick_wait = true
		(_act_btns["pick"] as PillButton).visible = false
		(_act_btns["undo"] as PillButton).visible = false
		wish_picker.open_wheel(side, _own_counts_after(_pick_cards), "Mit welcher Farbe geht es weiter?")
		return
	(_act_btns["pick"] as PillButton).visible = false
	(_act_btns["undo"] as PillButton).visible = false
	_emit_action({"a": "discard_pick", "cards": _pick_cards.duplicate()})


# Abgelehnt (Meldung): Knopf bzw. Farbrad wieder anbieten
func pick_retry() -> void:
	if _pick_key == "":
		return
	_pick_wait = false
	(_act_btns["pick"] as PillButton).visible = true
	(_act_btns["undo"] as PillButton).visible = can_undo_pick()
	_update_pick_button()


# Eigene Ablege-Auswahl offen und der Gastgeber erlaubt das Zurücknehmen (hints.can_undo)?
func can_undo_pick() -> bool:
	return _pick_key != "" and bool((view.get("hints", {}) as Dictionary).get("can_undo", false))


# Ganzen Zug zurücknehmen (Knopf „Zurücknehmen“, Zurück-Taste, Farbrad der Spielfarbe weggeklickt): Die Ablegen-Karte springt
# zurück in die Hand, die Auswahl verfällt. Ohne hints.can_undo (alter Gastgeber) bleibt die Auswahl offen.
func undo_pick() -> void:
	if _pick_key == "" or input_locked:
		return
	if not can_undo_pick():
		pick_retry()
		return
	if wish_picker.is_open():
		wish_picker.close()
	_pick_wait = false
	(_act_btns["pick"] as PillButton).visible = false
	(_act_btns["undo"] as PillButton).visible = false
	_layout_action_buttons()
	_emit_action({"a": "undo"})


# Farbrad weggeklickt: beim Ablegen-Joker (Spielfarbe) den Zug zurücknehmen; die Farbwahl nach einem Flip mit Joker oben (Phase
# color) ist endgültig und lässt sich nicht wegklicken – das Rad kommt sofort wieder.
func _on_wheel_cancelled() -> void:
	if _pick_wait:
		undo_pick()
		return
	var h: Dictionary = view.get("hints", {})
	if bool(h.get("need_color", false)) and str(view.get("phase", "")) == "color" and not input_locked:
		open_color_wheel()
		show_notice(I18n.t("Erst die Farbe wählen."))


# Farbanzahl der Hand ohne die Karten, die gleich mit abgelegt werden
func _own_counts_after(gone: Array) -> Dictionary:
	var counts := {}
	for c in view.get("hand", []):
		if gone.has(int(c.get("id", -1))) or gone.has(float(c.get("id", -1))):
			continue
		var col := CardTextures.color_of(str(c.get("face", "")))
		if col != "":
			counts[col] = int(counts.get(col, 0)) + 1
	return counts


# Hinweistext für die Leiste: Ohne „Spielbare Karten hervorheben“ verrät er nicht, dass nichts passt (sonst wäre das die Markierung).
func hint_text(text: String) -> String:
	if not highlight and text.begins_with(HINT_NOTHING_FITS):
		return "Du bist dran." + (" Denk an „Mau!“" if text.ends_with("Denk an „Mau!“") else "")
	return text


# Hinweis in der eigenen Sprache (I18n): aus den Bausteinen hints.lt des Gastgebers bzw. der deutschen msgid; die Kürzung von
# hint_text (Hervorheben aus) wird auf Bausteine übertragen.
func _hint_local(text: String, lt: Array) -> String:
	var shown := hint_text(text)
	if shown == text:
		return I18n.render(lt) if not lt.is_empty() else I18n.t(text)
	var parts: Array = ["Du bist dran."]
	if shown.ends_with("Denk an „Mau!“"):
		parts.append("Denk an „Mau!“")
	return I18n.render(parts)


func _layout_action_buttons(all := false) -> void:
	var sz := size if size.x > 10.0 else TableLayout.BASE
	var x := sz.x - 46.0
	var y := sz.y - 300.0
	if big:                               # vor der Spielerliste, über der Hinweisleiste
		x = BigLayout.list_rect(sz).position.x - 16.0
		y = BigLayout.hint_y(sz) - 44.0 - BigLayout.PILL_H
	for key in ["pick", "undo", "accept", "challenge", "keep"]:
		var b: PillButton = _act_btns[key]
		if not b.visible and not all:
			continue
		b.size = Vector2(b.preferred_width(), b.touch_h())
		x -= b.size.x
		b.position = Vector2(x, y)
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


# ================================================================= Spielerliste (großer Modus)

# Einträge der Liste: alle Plätze, dazu die eigene Zeile („Du“), wenn dieses Gerät einen Platz hat. Fertige Spieler („bis zum
# Letzten“, place > 0) verschwinden, solange die Runde läuft (Nutzerentscheidung 08.10.2026); am Rundenende stehen alle wieder da.
func _list_entries() -> Dictionary:
	var out := {}
	for s in _seats:
		out[s] = _seats[s]
	if me_badge.visible and int(view.get("seat", 0)) >= 0 and not out.has(my_seat):
		out[my_seat] = me_badge
	if str(view.get("phase", "")) in ["round_over", "game_over"]:
		return out
	var playing := {}
	for s in out:
		if int(_player(s).get("place", 0)) == 0:
			playing[s] = out[s]
	return playing if not playing.is_empty() else out


# Reihenfolge neu (wer dran ist oben, darunter der Nächste in Spielrichtung). animate: Zugwechsel rollt die Liste weiter (oben
# raus, unten wieder rein); ein Richtungswechsel klappt die Zeilen kurz zu und zeigt die Reihenfolge andersherum.
func _update_list(animate: bool) -> void:
	var entries := _list_entries()
	var seats: Array = entries.keys()
	var n := seats.size()
	if n == 0:
		return
	var turn := int(view.get("turn", -1))
	var dir := -1 if int(view.get("dir", 1)) < 0 else 1
	if turn < 0 or not entries.has(turn) or str(view.get("phase", "")) in ["round_over", "game_over"]:
		turn = _list_turn if entries.has(_list_turn) else turn
	var order := BigLayout.list_order(seats, turn, dir)
	var reverse := animate and _list_dir != 0 and dir != _list_dir and n > 2 and not reduced
	list_header.set_dir(dir, animate and _list_dir != 0)
	_list_turn = turn
	_list_dir = dir
	for s in _list_slot.keys():
		if not entries.has(s):
			_list_slot.erase(s)
			_list_target.erase(s)
	for i in n:
		var s: int = order[i]
		if not animate or not _list_slot.has(s):
			_list_slot[s] = float(i)
			_list_target[s] = float(i)
		elif reverse:
			_list_target[s] = float(i)      # Sprung zur Hälfte des Zuklappens
		else:
			_list_target[s] = BigLayout.roll_target(float(_list_slot[s]), i, n)
	if reverse:
		_list_flip = 0.0
	_position_list()


func _step_list(delta: float) -> void:
	if _list_flip >= 0.0:
		var before := _list_flip
		_list_flip += delta / 0.6
		if before < 0.5 and _list_flip >= 0.5:
			for s in _list_target:
				_list_slot[s] = float(_list_target[s])
		if _list_flip >= 1.0:
			_list_flip = -1.0
	else:
		var a := 1.0 - exp(-delta * (16.0 if reduced else 9.0))
		for s in _list_target:
			var cur := float(_list_slot.get(s, 0.0))
			var to := float(_list_target[s])
			_list_slot[s] = to if absf(to - cur) < 0.002 else lerpf(cur, to, a)
	_position_list()


func _position_list() -> void:
	var entries := _list_entries()
	var n := entries.size()
	var sz := size if size.x > 10.0 else TableLayout.BASE
	var rows := BigLayout.list_rows(sz, n)
	var k := int(rows["k"])
	var fy := absf(cos(_list_flip * PI)) if _list_flip >= 0.0 else 1.0
	for s in _seats:                      # nicht (mehr) in der Liste: fertige Spieler ausblenden
		if not entries.has(s):
			(_seats[s] as CanvasItem).modulate.a = 0.0
	if not entries.has(my_seat) or entries[my_seat] != me_badge:
		me_badge.modulate.a = 0.0
	for s in entries:
		var node: OpponentSeat = entries[s]
		var w := BigLayout.wrap(float(_list_slot.get(s, 0.0)), n)
		# verdeckte Zeilen liegen unter der letzten sichtbaren (Flüge zu ihnen enden am Listenende)
		var wy := minf(w, float(k) - 0.5)
		node.position = Vector2(float(rows["x"]), BigLayout.row_y(wy, rows))
		node.row_size = Vector2(float(rows["w"]), BigLayout.row_h(w, rows))
		node.modulate.a = BigLayout.row_alpha(w, n, k)
		node.z_index = 0
		if node.catchable and node.modulate.a < 0.99 and k >= 1:
			# Erwischbar, aber außerhalb der sichtbaren Zeilen (z. B. wer gerade gelegt hat, steht ganz unten): die Zeile über die
			# letzte sichtbare legen, damit „Erwischt!“ zu sehen ist (Nutzerbefund 08.10.2026)
			node.position = Vector2(float(rows["x"]), BigLayout.row_y(float(k) - 1.0, rows))
			node.row_size = Vector2(float(rows["w"]), BigLayout.row_h(float(k) - 1.0, rows))
			node.modulate.a = 1.0
			node.z_index = 1                # auch über der eigenen Zeile „Du“ (me_badge liegt über der Platzebene)
		if not is_equal_approx(node.flip_y, fy):
			node.flip_y = fy
			node.queue_redraw()


# Stelle eines Platzes in der Liste (0 = oben, wer dran ist); -1 = nicht in der Liste (Tests)
func list_index(seat: int) -> int:
	if not _list_target.has(seat):
		return -1
	return posmod(roundi(float(_list_target[seat])), maxi(_list_entries().size(), 1))


func _place_seats(animate: bool) -> void:
	if _n <= 0:
		return
	if big:
		_update_list(animate)
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
	c.width = pile_w
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


# Überlagerung im Spiel (Einstellungen, Menü, Regeln, So geht's) folgt Tag/Nacht des Tisches: apply(nacht) sofort und bei jedem
# Wechsel über die Schwelle (Flip), solange node lebt. Ohne Tisch im Baum (Tests, Menüs) bleibt es beim Tag. → Tisch oder null
static func follow_night(node: Node, apply: Callable) -> TableView:
	if node == null or not node.is_inside_tree():
		return null
	var tv := node.get_tree().get_first_node_in_group(GROUP) as TableView
	if tv == null:
		return null
	apply.call(tv.night > 0.5)
	if not tv.night_switched.is_connected(apply):
		tv.night_switched.connect(apply)      # apply ist eine Methode der Überlagerung: Godot trennt beim Freigeben selbst
	return tv


func set_night(v: float) -> void:
	var was := night > 0.5
	night = clampf(v, 0.0, 1.0)
	if (night > 0.5) != was:
		night_switched.emit(night > 0.5)
	if _bg == null:
		return
	_bg.tageszeit = night
	_ring.color = UiPalette.ring_color(night)
	gamble_machine.night = night
	stake_pile.night = night
	for s in _seats:
		(_seats[s] as OpponentSeat).night = night
	me_badge.night = night
	list_header.night = night
	_hand_halo.night = night
	_sort_btn.night = night
	_backs_btn.night = night
	for k in _act_btns:
		(_act_btns[k] as PillButton).night = night
	hint_bar.night = night
	fx.night = night
	fx_top.night = night
	_pile.night = night
	_color_mark.night = night
	discard_browser.night = night
	_color_ring.night = night
	wish_picker.night = night
	# Kartenhilfe und Rundenende: nachts dunkle Karte (1.1.3)
	if help_popup != null and help_popup.night != (night > 0.5):
		help_popup.set_night(night > 0.5)
	if round_end != null:
		round_end.set_night(night)


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
	if _pick_wait:
		_pick_wait = false
		_emit_action({"a": "discard_pick", "cards": _pick_cards.duplicate(), "color": c})
		return
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
		if _gamble_pressable() and gamble_machine.hit(get_global_transform() * mb.position):
			gamble_machine.set_down(true)
		return
	gamble_machine.set_down(false)
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
	if discard_browser.handle_tap(discard_browser.to_local(g)):    # Ablage/Seitenstapel; sonst schiebt es alles zurück
		return true
	for s in _seats:
		var node: OpponentSeat = _seats[s]
		if node.hit_catch(g):
			_emit_action({"a": "catch", "target": s})
			return true
	if gamble_machine.hit_stop(g):
		stop_gamble()
		return true
	if gamble_machine.hit(g):
		if _gamble_pressable():
			press_gamble()
		return true
	if Rect2(_draw_pos - Vector2(pile_w, pile_w * 1.6) * 0.62, Vector2(pile_w, pile_w * 1.6) * 1.24).has_point(wp):
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


# Glücksspielknopf: nur der Glücksspieler, nur wenn der Druck fällig ist, und nur einmal bis zur nächsten Sicht
func _gamble_pressable() -> bool:
	return gamble_machine.active and gamble_machine.can_press and not gamble_machine.press_sent and not input_locked


func press_gamble() -> bool:
	if not _gamble_pressable():
		return false
	gamble_machine.press_sent = true
	gamble_machine.press_anim()
	UiApp.vibrate(30, 0.6)
	_emit_action({"a": "press"})
	return true


# „Aufhören“: nur der Glücksspieler, nur bei hints.can_stop, einmal bis zur nächsten Sicht
func stop_gamble() -> bool:
	var m := gamble_machine
	if not m.active or not m.can_stop or m.press_sent or input_locked:
		return false
	m.press_sent = true
	m.queue_redraw()
	UiApp.vibrate(20, 0.4)
	_emit_action({"a": "stop"})
	return true


# ================================================================= Tischregie

func _d(t: float) -> float:
	return t / maxf(_speed, 0.01) * (0.6 if reduced else 1.0)


func skip_event(ev: Dictionary) -> void:
	fx.clear()
	if str(ev.get("e", "")) == "flip":
		_flip_running = false
	_house.skip(ev)


func play_event(ev: Dictionary, speed: float) -> float:
	_speed = speed
	var e := str(ev.get("e", ""))
	if ev.has("seat"):
		_poke(int(ev.get("seat", -1)))
	match e:
		"deal":
			return _ev_deal(ev)
		"play":
			return _ev_play(ev)
		"draw":
			return _ev_draw(ev, false)
		"penalty":
			return _ev_penalty(ev)
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
		"flip_surprise":
			return _ev_flip_surprise(ev)
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
		"swap_hands":
			return _house.ev_swap(ev)
		"gamble_start":
			return _house.ev_gamble_start(ev)
		"stake":
			return _house.ev_stake(ev)
		"gamble_roll":
			return _house.ev_roll(ev)
		"stake_back":
			return _house.ev_stake_back(ev)
		"stake_discard":
			return _house.ev_stake_discard(ev)
		"discard_color":
			return _house.ev_discard_color(ev)
		"unplay":
			return _ev_unplay(ev)
	return 0.0


# Zurückgenommen (Farbe mit ablegen): Die Ablegen-Karte fliegt von der Ablage zurück zum Leger, darunter liegt wieder die alte Karte.
func _ev_unplay(ev: Dictionary) -> float:
	var seat := int(ev.get("seat", -1))
	var face := str(ev.get("face", ""))
	if not _discard.is_empty() and _discard[-1].current_key() == face:
		var c: CardView = _discard.pop_back()
		c.queue_free()
	_set_top(str(ev.get("top", "")), int(ev.get("top_id", -1)))
	_update_rays()
	var to := _hand_point()
	var w := HAND_CARD_W
	if seat != my_seat:
		var node := seat_node(seat)
		if node == null:
			return 0.0
		to = _world.to_local(node.global_position)
		w = pile_w * 0.6
	var dur := _d(0.32)
	fx.fly_card(face, _discard_pos, 0.0, pile_w, to, 0.0, w, dur, {})
	return dur


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
	var start := {"pos": _center, "rot": 0.0, "width": pile_w * 0.6, "key": face}
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
	fx.fly_card(str(start["key"]), start["pos"], float(start["rot"]), float(start["width"]), _discard_pos, to_rot, pile_w, dur,
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
	fx.land_burst(_discard_pos, tint, dark, pile_w * 0.55)
	UiApp.sound("karte")
	if seat == my_seat:
		UiApp.vibrate(15, 0.5)


# Strafe für vergessenes „Mau!“: nur der Stempel. Die Karten fliegen beim gleich folgenden „draw“-Ereignis (mit der echten Zahl);
# früher flogen sie hier und dort, also doppelt (1.4.1).
func _ev_penalty(ev: Dictionary) -> float:
	var seat := int(ev.get("seat", -1))
	var count := maxi(int(ev.get("count", 1)), 1)
	var node := seat_node(seat)
	var victim_pos := _seat_point(seat) + Vector2(0, -150) if seat == my_seat else _seat_point(seat)
	if node != null:
		victim_pos = node.position
	fx.stamp(victim_pos + Vector2(0, 48), I18n.t("Strafe +%d") % count, UiPalette.ALERT, 34, 0.8)
	if seat == my_seat:
		_edge_pulse()
	return _d(0.35)


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
			var cid := int(c.get("id", -1))
			if not have.has(cid) and not _house.is_reserved(cid):    # eigene Einsatzkarten kommen gleich mit stake_back
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
		fx.fly_card(key, _draw_pos, 0.0, pile_w, dest, 0.0, to_w, fly, {"flip_to": flip_to, "delay": t, "on_land": land})
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
		fx.stamp(victim_pos + Vector2(0, 48), I18n.t("Strafe +%d") % count, UiPalette.ALERT, 34, 0.8)
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
	_prepare_deal(target, int(ev.get("count", 7)))
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
			fx.fly_card(_pile.back_key if _pile.back_key != "" else CardTextures.BACK, _draw_pos, 0.0, pile_w, dest, 0.0, w, fly, {"delay": t, "arc": 30.0})
			t += step
	return t + fly


# Flip-Überraschung (Hausregel flip_surprise): Die Aktionskarte oben wirkt, als hätte der Flip-Spieler sie gelegt. Kurzer Stempel
# über der Ablage; die folgenden Wirkungs-Ereignisse (Ziehen, Aussetzen …) zeigen sich wie nach einem normalen Legen.
func _ev_flip_surprise(ev: Dictionary) -> float:
	var face := str(ev.get("face", ""))
	_last_player = int(ev.get("seat", -1))
	_jagd_armed = face.ends_with("_farbjagd")
	_plus_armed = 0
	for kind in ["plus1", "plus5", "wuenscher_plus2"]:
		if face.ends_with("_" + kind):
			_plus_armed = int(kind.right(1))
	var col := Color("#FF7FCF") if night > 0.5 else UiPalette.ALERT
	fx.stamp(_discard_pos + Vector2(0, -minf(pile_w * 0.95, _discard_pos.y - 60.0)), "Flip-Überraschung!", col, 34, 0.75)
	if not reduced:
		fx.ring_wave(_discard_pos, col, 30.0, 170.0, _d(0.5), 7.0)
	UiApp.vibrate(20, 0.4)
	return _d(0.85)


# Partiestart (Gerätetest 0.1.4): Ohne bisherige Sicht gäbe es noch keine Plätze (Karten flögen in die Mitte) und der Stapel stünde
# auf 0. Dann wie bei „Nächste Runde“ zuerst den leeren Tisch der Zielsicht aufbauen: alle Plätze mit 0 Karten, volle Stapelhöhe,
# keine Ablage, niemand am Zug. Danach fliegen die Karten vom Stapel zu den Plätzen.
func _prepare_deal(target: Dictionary, per: int) -> void:
	if target.is_empty():
		return
	var tp: Array = target.get("players", [])
	var missing := view.is_empty()
	for p in tp:
		var s := int(p.get("seat", -1))
		if s != int(target.get("seat", 0)) and not _seats.has(s):
			missing = true
	if not missing:
		return
	var prep: Dictionary = target.duplicate(true)
	var dealt := 0
	for p in prep.get("players", []):
		dealt += int(p.get("count", 0))
		p["count"] = 0
		p["backs"] = []
		p["mau"] = false
	prep["hand"] = []
	prep["top"] = {}
	prep["color"] = ""
	prep["turn"] = -1
	prep["hints"] = {}
	prep["pending"] = {}
	prep["phase"] = "deal"
	prep["draw_count"] = int(target.get("draw_count", 0)) + maxi(dealt, per * tp.size()) + 1
	apply_view(prep)


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
	UiApp.sound("schnurren")
	if seat == my_seat:
		UiApp.vibrate(10, 0.3)
	return _d(0.9)


func _ev_skip_all(ev: Dictionary) -> float:
	UiApp.sound("schnurren")
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
		var txt := I18n.t("Nochmal du!") if player == my_seat else I18n.t("Nochmal, %s!") % _player_name(player)
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
	b.k = 1.2 if big else (0.86 if TableLayout.compact(_n) else 1.0)
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
		var r := node.avatar_radius()
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
	var dh := pile_w * 466.0 / 300.0
	if big:                               # großer Modus: die anderen Listenzeilen und die obere Hälfte der Ablage
		var entries := _list_entries()
		for s in entries:
			var e: OpponentSeat = entries[s]
			if s != seat and e.modulate.a > 0.5:
				var lr := e.list_rect()
				out.append(Rect2(_world.transform * (e.position + lr.position), lr.size))
		out.append(Rect2(_world.transform * _discard_pos - Vector2(pile_w * 0.5, dh * 0.5), Vector2(pile_w, dh * 0.5)))
		if seat != my_seat and mau_button.visible:
			out.append(Rect2(mau_button.position, mau_button.size))
		return out
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
	out.append(Rect2(_world.transform * _discard_pos - Vector2(pile_w * 0.6, dh * 0.6), Vector2(pile_w * 1.2, dh * 1.2)))
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
	fx_top.celebrate(Rect2(0, 0, sz.x, 10), 320 if game_over else 220)
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
	# Sanfte Lichtstrahlen wie am Tisch hinter dem Ergebnis (0.1.4, statt der harten Keile)
	var rays := TableEffects.SoftRaysFx.new()
	rays.position = round_end.winner_anchor() if round_end.size.x > 10.0 else Vector2(800, 200)
	rays.radius = 900.0
	rays.tint = Color(1.0, 0.84, 0.45, 0.55) if night < 0.5 else Color(0.62, 0.70, 1.0, 0.45)
	rays.motion = not reduced
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
	if big:
		_step_list(delta)
	if _hand_halo_want or _hand_halo.visible:
		_sync_hand_halo(delta)
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
	var w := TableView.CARD_W            # Kartenbreite (großer Modus: BigLayout.pile_w, dann kräftiger Rand)
	var _label: Node2D

	func _init() -> void:
		top = CardView.new()
		top.width = TableView.CARD_W
		add_child(top)

	func set_width(v: float) -> void:
		if is_equal_approx(v, w):
			return
		w = v
		top.width = v
		queue_redraw()

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
		if w > 200.0:                    # großer Modus: kräftiger Rand um den Stapel
			var o := StyleBoxFlat.new()
			o.draw_center = false
			o.border_color = UiPalette.CREAM if night > 0.5 else UiPalette.INK
			o.set_border_width_all(5)
			o.set_corner_radius_all(int(w * 0.075))
			o.expand_margin_left = 4
			o.expand_margin_right = 4
			o.expand_margin_top = 4
			o.expand_margin_bottom = 4
			o.anti_aliasing = true
			draw_style_box(o, Rect2(-w * 0.5, -h * 0.5, w, h))
		if highlight:
			var p := 0.5 + 0.5 * sin(_time * 4.0)
			var g := StyleBoxFlat.new()
			g.draw_center = false
			g.border_color = Color(UiPalette.TURN, 0.55 + 0.35 * p)
			g.set_border_width_all(4 if w <= 200.0 else 9)
			g.set_corner_radius_all(int(w * 0.09))
			var em := 7 if w <= 200.0 else 12
			g.expand_margin_left = em
			g.expand_margin_right = em
			g.expand_margin_top = em
			g.expand_margin_bottom = em
			g.anti_aliasing = true
			draw_style_box(g, Rect2(-w * 0.5, -h * 0.5, w, h))
		if _label == null:
			_label = Node2D.new()
			add_child(_label)
			_label.draw.connect(_draw_label)
		_label.queue_redraw()

	# Zahl der Karten: unter dem Stapel; im großen Modus groß oben auf dem Stapel (unten liegt die Hand)
	func _draw_label() -> void:
		var h := w * 466.0 / 300.0
		var f := UiFonts.text(700 if w <= 200.0 else 800, 100.0)
		var t := I18n.t("Stapel · %d") % count
		if w <= 200.0:
			var sfs := UiFonts.size("hinweis")
			var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
			_label.draw_string(f, Vector2(-tw * 0.5, h * 0.5 + 12.0 + sfs * 0.75), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, UiPalette.ui_muted(night))
			return
		var bfs := UiFonts.px(34)
		var bw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs).x + 32.0
		var bh := bfs + 18.0
		var r := Rect2(w * 0.5 - bw - 16.0, -h * 0.5 + 22.0, bw, bh)   # rechts oben: der Eckindex links oben bleibt frei
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiPalette.CREAM if night > 0.5 else UiPalette.INK
		sb.set_corner_radius_all(int(bh * 0.5))
		sb.anti_aliasing = true
		_label.draw_style_box(sb, r)
		_label.draw_string(f, Vector2(r.position.x + 16.0, r.get_center().y + bfs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs, UiPalette.INK if night > 0.5 else UiPalette.CREAM)


class ColorRingView:
	extends Node2D
	# Farbring um die Ablage (Glühen in der aktuellen Farbe) und „+N“-Marke für aufgelaufene Ziehkarten
	const R := 116.0
	var card_size := Vector2.ZERO        # großer Modus: Kartenmaß der Ablage (Rahmen statt Ring)
	var color_key := ""
	var color := Color(1, 1, 1, 0)
	var night := 0.0:
		set(v):
			night = v
			queue_redraw()
	var pending := 0
	var _pop := 0.0
	var badge: Node2D                    # PendingBadge über Ablage und Farbschild (zeichnet die „+N“-Plakette)
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
		var big := card_size.x > 0.0
		if color.a > 0.0 and big:
			# großer Modus: kräftiger Rahmen in der aktuellen Farbe um die Ablagekarte statt des Rings
			var r := Rect2(-card_size * 0.5, card_size)
			for g in [[22.0, 0.10 + 0.08 * night], [12.0, 0.25]]:
				var sb := StyleBoxFlat.new()
				sb.draw_center = false
				sb.border_color = Color(color, float(g[1]))
				sb.set_border_width_all(int(g[0]))
				sb.set_corner_radius_all(int(card_size.x * 0.08 + float(g[0])))
				sb.expand_margin_left = float(g[0])
				sb.expand_margin_right = float(g[0])
				sb.expand_margin_top = float(g[0])
				sb.expand_margin_bottom = float(g[0])
				sb.anti_aliasing = true
				draw_style_box(sb, r)
			var edge := StyleBoxFlat.new()
			edge.draw_center = false
			edge.border_color = color
			edge.set_border_width_all(8)
			edge.set_corner_radius_all(int(card_size.x * 0.08 + 6.0))
			edge.expand_margin_left = 7
			edge.expand_margin_right = 7
			edge.expand_margin_top = 7
			edge.expand_margin_bottom = 7
			edge.anti_aliasing = true
			draw_style_box(edge, r)
		elif color.a > 0.0:
			draw_circle(Vector2.ZERO, R + 16.0, Color(color, 0.07 + 0.08 * night))
			draw_arc(Vector2.ZERO, R + 6.0, 0.0, TAU, 96, Color(color, 0.22), 18.0, true)
			draw_arc(Vector2.ZERO, R, 0.0, TAU, 96, color, 5.0, true)
			draw_arc(Vector2.ZERO, R - 7.0, 0.0, TAU, 96, Color(color, 0.18), 10.0, true)
		if badge != null:
			badge.queue_redraw()

	# Mitte der „+N“-Plakette relativ zur Ablage. Großer Modus (1.1.3): an der rechten Kante unterhalb der Mitte, also in der
	# freien Farbspalte unter dem Farbschild, nicht oben am Bildrand und nicht unter dem Schild. Sonst oben rechts am Ring.
	func badge_center() -> Vector2:
		if card_size.x > 0.0:
			return Vector2(card_size.x * 0.5, card_size.y * 0.12)
		return Vector2(R * 0.78, -R * 0.78)


class PendingBadge:
	extends Node2D
	# „+N“-Plakette der angesammelten Ziehkarten (Daten aus ColorRingView). Eigener Knoten über Ablage und Farbschild, aber unter
	# Ablage-Durchsehen, Einsatz, Automat, Hand und fliegenden Karten (Gerätetest 1.1.2: im großen Modus lag sie verdeckt hinter
	# Ablage und Farbschild).
	var ring: ColorRingView

	func _draw() -> void:
		if ring == null or ring.pending <= 0:
			return
		var c := ring.badge_center()
		var s := (1.0 + 0.35 * sin(ring._pop * PI)) * (1.8 if ring.card_size.x > 0.0 else 1.0)
		draw_circle(c + Vector2(0, 4.0 * s), 31.0 * s, Color(0, 0, 0, 0.25))      # leichter Schatten: hebt sie von der Karte ab
		draw_circle(c, 30.0 * s, UiPalette.INK if ring.night < 0.5 else Color("#FF7FCF"))
		draw_circle(c, 26.0 * s, UiPalette.CREAM)
		var f := UiFonts.text(800, 85.0)
		var t := "+%d" % ring.pending
		var fs := int(UiFonts.size("text") * s)
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, c + Vector2(-tw * 0.5, fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiPalette.INK)


class ColorMark:
	extends Node2D
	# Aktuelle Farbe zwischen den Stapeln: Formsymbol und Name (Farbe nie allein: Symbol + Wort). Großer Modus: k > 1, auf einem
	# kontrastreichen Schild neben der Ablage.
	var color_key := ""
	var night := 0.0:
		set(v):
			night = v
			queue_redraw()
	var k := 1.0:
		set(v):
			k = v
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
		var isz := 46.0 * s * k
		var bg := UiPalette.NIGHT if night > 0.5 else UiPalette.PAPER
		var f := UiFonts.text(800, 100.0)
		var t := I18n.t(UiPalette.color_name(color_key))
		var cfs := int(UiFonts.size("text") * k)
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
		var sy := -16.0 * k
		var ty := 22.0 * k + cfs * 0.45
		if k > 1.0:                          # Schild: hebt Symbol und Wort klar vom Hintergrund ab
			var pw := maxf(isz, tw) + 40.0
			var plate := Rect2(-pw * 0.5, sy - isz * 0.5 - 18.0, pw, ty - (sy - isz * 0.5 - 18.0) + 20.0)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(bg, 0.94)
			sb.border_color = col
			sb.set_border_width_all(6)
			sb.set_corner_radius_all(26)
			sb.anti_aliasing = true
			sb.shadow_color = Color(0, 0, 0, 0.25)
			sb.shadow_size = 5
			draw_style_box(sb, plate)
		elif night > 0.5:
			draw_circle(Vector2(0, -16), 40.0 * s, Color(col, 0.16))
		draw_texture_rect(UiIcons.symbol(color_key, 128 if k > 1.0 else 96, col, bg.lerp(col, 0.25)), Rect2(Vector2(-isz * 0.5, sy - isz * 0.5), Vector2(isz, isz)), false)
		draw_string(f, Vector2(-tw * 0.5, ty), t, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, UiPalette.ui_text(night))
