class_name TableScreen
extends AppScreen
# Der Spieltisch als Bildschirm: TableView (F1b) + HandView (F1a) an einer TableSource (Modul G).
#   source.state_changed → TableView.handle_state (Regie spielt die Ereignisse, danach Abgleich; der Hand-Adapter
#                          HandView.apply_view setzt Karten und spielbare Karten aus view.hand/hints.playable)
#   HandView.play_requested → source.act(play); Wünscher: beim Ziehen Farbfelder um die Ablage (drag_started/moved/ended),
#                             sonst (Doppeltipp, Schnippen, daneben fallen gelassen) das Farbrad
#   TableView.action → source.act (ziehen, behalten, anzweifeln, annehmen, erwischen, nächste Runde, Farbwahl)
#   Mau-Knopf → act mau (ohne Ton); Ton und Sprechblase kommen mit dem Ereignis „mau“ auf allen Geräten (TableView, MauSound)
#   help_requested → Kartenhilfe (RulesText zur aktiven RuleConfig aus view.rules)
#   Sortierknopf → HandView.set_sort_mode + App.settings "sortierung"; Rückseiten-Knopf: halten = eigene Rückseiten
#   handover → Sichtschutz (HandoverScreen), Aufdecken → source.reveal(); notice → Meldung; connection_changed → „Verbinde neu …“
# Schichtung: Die Overlays der TableView (Farbwahl, Hilfe, Sichtschutz, Rundenende, Großansicht) liegen in einem CanvasLayer
# über der Hand (layer 5), eigene Knöpfe und Rückfragen darüber (layer 6). So kann keine Karte der Hand sie überdecken.

const OVERLAY_LAYER := 5
const TOP_LAYER := 6
const SORT_MODES := ["farbe", "wert", "punkte", "manuell"]
const SORT_LABELS := {"farbe": "Farbe", "wert": "Wert", "punkte": "Punkte", "manuell": "Eigene"}
const PEEK_TAP_MS := 300

var source: TableSource
var starter := Callable()
var table: TableView
var hand: HandView
var view: Dictionary = {}
var overlay: CanvasLayer             # Overlays der TableView
var top_layer: CanvasLayer           # Menü-Knopf, Rundenende-Menü, Verbindung, Rückfrage
var leaving := false

var _top: Control
var _menu_btn: Button
var _round_menu: Button
var _conn: PanelContainer
var _conn_label: Label
var _conn_menu: Button
var _confirm: ConfirmBox
var _wild_drag := -1                 # Wünscher, der gerade gezogen wird (Farbfelder offen)
var _pending_wild := -1              # Wünscher wartet auf das Farbrad
var _last_play := -1                 # optimistisch ausgespielt, Antwort steht aus
var _last_seat := -1                 # zuletzt gezeigter Platz (Sichtschutz: von wem kommt das Handy)
var _peek_down_ms := -1
var _peek_on := false
var _peek_was_on := false
var _handover_pending := false


# starter: wird aufgerufen, sobald der Tisch an der Quelle hängt (z. B. LocalTable.start, HostTable.start)
static func create(src: TableSource, start_call := Callable()) -> TableScreen:
	var s := TableScreen.new()
	s.source = src
	s.starter = start_call
	return s


func covers_background() -> bool:
	return true


func build() -> void:
	table = TableView.new()
	table.name = "Tisch"
	add_child(table)
	hand = HandView.new()
	hand.name = "Hand"
	table.set_hand(hand)
	var mode := str(UiApp.setting("sortierung", "farbe"))
	if not SORT_MODES.has(mode):
		mode = "farbe"
	hand.set_sort_mode(mode)
	table.set_sort_label(SORT_LABELS[mode])
	# Overlays der TableView über die Hand heben (eigener CanvasLayer, gleiche Koordinaten: der Tisch liegt bei 0,0)
	overlay = CanvasLayer.new()
	overlay.name = "Overlays"
	overlay.layer = OVERLAY_LAYER
	add_child(overlay)
	var ov: Control = table.get("_overlay")
	if ov != null:
		ov.reparent(overlay, false)
	top_layer = CanvasLayer.new()
	top_layer.name = "Oben"
	top_layer.layer = TOP_LAYER
	add_child(top_layer)
	_top = Control.new()
	_top.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.theme = UiTheme.get_theme()
	top_layer.add_child(_top)
	_build_top()
	# Verdrahtung Tisch und Hand
	table.action.connect(_on_table_action)
	table.sort_pressed.connect(_cycle_sort)
	if table.mau_button.mau_pressed.is_connected(table._on_mau_pressed):
		table.mau_button.mau_pressed.disconnect(table._on_mau_pressed)
	table.mau_button.mau_pressed.connect(_on_mau)
	var backs_btn: Control = table.get("_backs_btn")
	if backs_btn != null:
		backs_btn.gui_input.connect(_on_backs_input)
	table.wish_picker.color_chosen.connect(_on_color_chosen)
	table.wish_picker.cancelled.connect(_on_color_cancelled)
	table.handover.revealed.connect(_on_revealed)
	table.help_popup.closed.connect(func() -> void: hand.close_big_view())
	hand.play_requested.connect(_on_play_requested)
	hand.drag_started.connect(_on_drag_started)
	hand.drag_moved.connect(_on_drag_moved)
	hand.drag_ended.connect(_on_drag_ended)
	hand.help_requested.connect(_on_help)
	hand.play_denied.connect(_on_play_denied)
	hand.sort_mode_changed.connect(_on_sort_mode_changed)
	resized.connect(_layout)
	_layout()
	# Quelle anschließen (sie gehört ab jetzt diesem Bildschirm)
	if source != null:
		if source.get_parent() == null:
			add_child(source)
		elif source.get_parent() != self:
			source.reparent(self)
		source.state_changed.connect(_on_state)
		source.notice.connect(_on_notice)
		source.handover.connect(_on_handover)
		source.connection_changed.connect(_on_connection)
		if source is GameTable:
			(source as GameTable).busy_check = _ui_busy
		var v := source.current_view()
		if not v.is_empty():
			_on_state([], v)
	if starter.is_valid():
		starter.call()


func _build_top() -> void:
	_menu_btn = ScreenKit.button("", "GhostButton", "zurueck", ScreenKit.TOUCH)
	_menu_btn.name = "Menue"
	_menu_btn.tooltip_text = "Partie verlassen"
	_menu_btn.position = Vector2(14, 10)
	_menu_btn.size = Vector2(ScreenKit.TOUCH, ScreenKit.TOUCH)
	_menu_btn.modulate.a = 0.85
	_menu_btn.pressed.connect(func() -> void: on_back())
	_top.add_child(_menu_btn)
	_round_menu = ScreenKit.button("Zum Menü", "", "zurueck")
	_round_menu.name = "ZumMenue"
	_round_menu.visible = false
	_round_menu.pressed.connect(_leave_now)
	_top.add_child(_round_menu)
	_conn = ScreenKit.card(22.0, true)
	_conn.visible = false
	_top.add_child(_conn)
	var row := ScreenKit.hbox(18)
	_conn.add_child(row)
	_conn_label = ScreenKit.label("Verbinde neu …", "NightLabel", 24)
	_conn_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_conn_label)
	_conn_menu = ScreenKit.button("Zum Menü", "DarkButton")
	_conn_menu.visible = false
	_conn_menu.pressed.connect(_leave_now)
	row.add_child(_conn_menu)


func on_enter() -> void:
	if overlay != null:
		overlay.visible = true
		top_layer.visible = true
	_keep_screen(true)


func on_leave() -> void:
	if overlay != null:
		overlay.visible = false
		top_layer.visible = false


static func _keep_screen(on: bool) -> void:
	var app := UiApp.app()
	if app != null and app.has_method("set_keep_screen_on"):
		app.call("set_keep_screen_on", on)


func _layout() -> void:
	var sz := size if size.x > 10.0 else Vector2(1600, 720)
	hand.layout_rect = Rect2(270.0, sz.y - 220.0, maxf(sz.x - 540.0, 400.0), 220.0)
	var xf := table.get_global_transform()
	hand.play_target = xf * table.discard_position()
	hand.spawn_from = xf * table.draw_pile_position()
	_round_menu.size = Vector2(_round_menu.get_combined_minimum_size().x + 20.0, ScreenKit.TOUCH)
	_round_menu.position = Vector2(sz.x - _round_menu.size.x - 22.0, 14.0)
	_conn.reset_size()
	_conn.position = Vector2((sz.x - _conn.size.x) * 0.5, 16.0)


func _process(_delta: float) -> void:
	if table == null:
		return
	_round_menu.visible = table.round_end.visible and not table.handover.visible
	_menu_btn.visible = not table.handover.visible
	# Ziel der Ausspiel-Flüge folgt dem Tisch (Größenwechsel)
	if not hand.play_target.is_finite():
		_layout()


# ================================================================= Quelle → Oberfläche

func _on_state(events: Array, v: Dictionary) -> void:
	if leaving:
		return
	view = v
	_last_play = -1
	var hints: Dictionary = v.get("hints", {})
	if hints.has("can_next_round"):
		table.can_next_round = 1 if bool(hints.get("can_next_round", false)) else 0
	var rules: Dictionary = v.get("rules", {})
	var peek_ok := bool(rules.get("peek_own_backs", true)) and int(v.get("seat", -1)) >= 0
	var backs_btn: Control = table.get("_backs_btn")
	if backs_btn != null:
		backs_btn.visible = peek_ok
	if not peek_ok and _peek_on:
		_set_peek(false)
	var seat := int(v.get("seat", -1))
	if seat >= 0:
		_last_seat = seat
	if _handover_pending and seat >= 0:
		_handover_pending = false
	table.handle_state(events, v)


# Bots warten, solange die Regie noch abspielt
func _ui_busy() -> bool:
	return table != null and is_instance_valid(table) and table.director.is_busy()


func _on_notice(text: String) -> void:
	if _last_play >= 0:
		hand.cancel_play(_last_play)
		_last_play = -1
	table.show_notice(text, "warn")


# Weitergeben: Sichtschutz vor dem nächsten Menschen; die alte Hand verschwindet darunter
func _on_handover(next_seat: int, player_name: String) -> void:
	_handover_pending = true
	_set_peek(false)
	hand.close_big_view()
	table.wish_picker.close()
	table.help_popup.close()
	var n: int = (view.get("players", []) as Array).size()
	var from := _last_seat if _last_seat >= 0 else next_seat
	table.handover.show_for(player_name, from, next_seat, maxi(n, 1), int(view.get("discard_count", 0)), int(view.get("draw_count", 0)), str(view.get("side", "hell")))
	hand.set_cards([])


func _on_revealed() -> void:
	if source != null:
		source.reveal()


func _on_connection(state: String) -> void:
	match state:
		"open":
			_conn.visible = false
		"connecting":
			_conn_label.text = "Verbinde neu …"
			_conn_menu.visible = false
			_conn.visible = true
		"closed", "rejected":
			_conn_label.text = "Verbindung zum Gastgeber beendet."
			_conn_menu.visible = true
			_conn.visible = true
	_layout()


# ================================================================= Oberfläche → Quelle

func _act(a: Dictionary) -> void:
	if source != null and not leaving:
		source.act(a)


func _on_table_action(a: Dictionary) -> void:
	_act(a)


func _on_mau() -> void:
	# Kein Ton beim Drücken: Ton und Sprechblase kommen mit dem Ereignis „mau“ auf allen Geräten (AGENTS.md Nr. 21), so
	# klingt er auch hier genau einmal.
	UiApp.vibrate(30, 0.5)
	_act({"a": "mau"})


func _card_face(id: int) -> String:
	for c in view.get("hand", []):
		if int(c.get("id", -1)) == id:
			return str(c.get("face", ""))
	return ""


func _is_wild(id: int, face: String) -> bool:
	var hints: Dictionary = view.get("hints", {})
	var wild: Array = hints.get("wild", [])
	if wild.has(id) or wild.has(float(id)):
		return true
	return JokerRays.is_joker(face)


func _on_play_requested(id: int, drop_global: Vector2) -> void:
	var face := _card_face(id)
	if _is_wild(id, face):
		var col := ""
		if _wild_drag == id and table.wish_picker.mode == "fields":
			col = table.wish_picker.color_at(drop_global)
			table.wish_picker.close()
		_wild_drag = -1
		if col != "":
			_last_play = id
			_act({"a": "play", "card": id, "color": col})
		else:
			_pending_wild = id
			table.open_color_wheel()
		return
	_last_play = id
	_act({"a": "play", "card": id})


func _on_drag_started(id: int, face: String) -> void:
	var playable: Array = (view.get("hints", {}) as Dictionary).get("playable", [])
	if _is_wild(id, face) and (playable.has(id) or playable.has(float(id))):
		_wild_drag = id
		table.open_color_fields()


func _on_drag_moved(global: Vector2) -> void:
	if _wild_drag >= 0 and table.wish_picker.mode == "fields":
		table.wish_picker.hover(global)


func _on_drag_ended(id: int, _global: Vector2, played: bool) -> void:
	if _wild_drag == id or (not played and table.wish_picker.mode == "fields"):
		if table.wish_picker.mode == "fields":
			table.wish_picker.close()
		_wild_drag = -1


func _on_color_chosen(color: String) -> void:
	if _pending_wild >= 0:
		var id := _pending_wild
		_pending_wild = -1
		_last_play = id
		_act({"a": "play", "card": id, "color": color})


func _on_color_cancelled() -> void:
	if _pending_wild >= 0:
		hand.cancel_play(_pending_wild)
		_pending_wild = -1


func _on_play_denied(_id: int) -> void:
	var turn := int(view.get("turn", -1))
	var me := int(view.get("seat", -1))
	if turn != me:
		table.show_notice("Du bist gerade nicht dran.")
	else:
		var hints: Dictionary = view.get("hints", {})
		var t := str(hints.get("text", ""))
		table.show_notice("Diese Karte passt gerade nicht." if t == "" or t == "Du bist dran." else t)


func _on_help(id: int, face: String) -> void:
	var key := face if face != "" else _card_face(id)
	var cfg := RuleConfig.from_dict(view.get("rules", {}))
	var lines := RulesText.card_help(key, cfg)
	var body := ""
	for i in lines.size():
		body += ("[b]%s[/b]" % lines[i]) if i == 0 else ("\n\n" + lines[i])
	table.show_help(key, RulesText.face_title(key), body)


func _cycle_sort() -> void:
	var cur := hand.sort_mode
	var i := SORT_MODES.find(cur)
	var next: String = SORT_MODES[(i + 1) % SORT_MODES.size()]
	_apply_sort(next)
	table.show_notice("Sortiert nach %s" % SORT_LABELS[next] if next != "manuell" else "Eigene Reihenfolge – Karte halten und seitlich ziehen")


func _on_sort_mode_changed(mode: String) -> void:
	_apply_sort(mode)


func _apply_sort(mode: String) -> void:
	if hand.sort_mode != mode:
		hand.set_sort_mode(mode)
	table.set_sort_label(SORT_LABELS.get(mode, "Farbe"))
	var app := UiApp.app()
	var st: Variant = app.get("settings") if app != null else null
	if st is Object:
		(st as Object).call("set_value", "sortierung", mode)


# Rückseiten-Knopf: halten = Rückseiten zeigen, solange gedrückt; kurzer Tipp schaltet um
func _on_backs_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var rules: Dictionary = view.get("rules", {})
	if not bool(rules.get("peek_own_backs", true)):
		if mb.pressed:
			table.show_notice("Eigene Rückseiten sind bei diesen Regeln aus.")
		return
	if mb.pressed:
		_peek_down_ms = Time.get_ticks_msec()
		_peek_was_on = _peek_on
		_set_peek(true)
	elif _peek_down_ms >= 0:
		var held := Time.get_ticks_msec() - _peek_down_ms
		if held >= PEEK_TAP_MS or _peek_was_on:
			_set_peek(false)
		_peek_down_ms = -1


func _set_peek(on: bool) -> void:
	_peek_on = on
	if hand != null:
		hand.set_peek_backs(on)
	if table != null:
		table.set_backs_active(on)


# ================================================================= Verlassen

func on_back() -> bool:
	if leaving:
		return true
	if table != null and table.help_popup.visible:
		table.help_popup.close()
		return true
	if table != null and table.backs_viewer.visible:
		table.backs_viewer.close()
		return true
	if hand != null and hand.is_big_view_open():
		hand.close_big_view()
		return true
	if _confirm != null and is_instance_valid(_confirm):
		_confirm.queue_free()
		_confirm = null
		return true
	var phase := str(view.get("phase", ""))
	if phase == "game_over":
		_leave_now()
		return true
	var text := "Die Partie endet für alle." if source != null and source.mode() == "host" else ("Du verlässt das Spiel des Gastgebers." if source != null and source.mode() == "client" else "Der Spielstand geht verloren.")
	_confirm = ConfirmBox.ask(_top, "Partie verlassen?", text, "Verlassen", "Weiterspielen")
	_confirm.answered.connect(func(yes: bool) -> void:
		_confirm = null
		if yes:
			_leave_now())
	return true


func _leave_now() -> void:
	if leaving:
		return
	leaving = true
	if source != null:
		source.leave()
	if nav != null:
		nav.home()
