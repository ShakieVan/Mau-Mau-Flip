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
#   Glücksspiel (eigener Einsatz fällig): Ausspielen einer Handkarte → act stake (ohne Farbwahl, Ziel ist der Einsatzstapel);
#                             der Knopf in der Tischmitte schickt press über TableView.action
#   „Spielbare Karten hervorheben“ aus: eine unpassende Karte springt zurück, Hinweis „Die Karte passt nicht.“
#   Sortierknopf → HandView.set_sort_mode + App.settings "sortierung"; Rückseiten-Knopf: halten = eigene Rückseiten
#   handover → Sichtschutz (HandoverScreen), Aufdecken → source.reveal(); notice → Meldung; connection_changed → „Verbinde neu …“
#   App-Gast: jede Sicht merkt sich view.rules als Regeln des Gastgebers (RuleSets.remember_host, schreibt nur bei Änderung;
#             nur hier, nicht schon in der Lobby). „Regeln speichern“ im Spielmenü („Partie verlassen?“ bleibt dabei offen) und in
#             der Leiste „Verbindung zum Gastgeber beendet.“; beide zeigen „Gespeichert: …“, wenn die Regeln schon einem Satz
#             entsprechen. Die Leiste sagt dazu, dass die Regeln gemerkt sind, und bietet „Selbst eröffnen“: neue Gastgeber-Lobby
#             mit genau diesen Regeln (Übernahme, wenn der Gastgeber gehen musste). Ein Speichern-Dialog, der in der Lobby offen war,
#             kommt mit an den Tisch (adopt_save_box).
#             Kommt am Tisch eine Lobby an, ist diese Partie vorbei: Der Gastgeber hat eine neue Runde eröffnet, und der Gast hat
#             sich (z. B. nach einem Funkloch, ohne „bye“) dorthin neu verbunden. Dann geht es mit derselben Verbindung in die Lobby
#             (JoinScreen.with_client) statt am alten Tisch stehen zu bleiben (Nachtest 1, Nachbesserung; wie der Browser-Client).
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
var _menu_night := -1                  # zuletzt angewandte Seite des Zurück-Knopfs (0 Tag, 1 Nacht)
var _online_away := false              # Gastgeber: Vermittler-Verbindung unterbrochen (Hinweis oben, Beta 1.3.3)
var _round_menu: Button
var _conn: PanelContainer
var _conn_label: Label
var _conn_sub: Label                 # App-Gast: „Die Regeln von Lena sind gemerkt …“
var _conn_menu: Button
var _conn_save: Button               # App-Gast: „Regeln speichern“, wenn die Verbindung zum Gastgeber beendet ist
var _conn_host: Button               # App-Gast: „Selbst eröffnen“ mit den Regeln dieser Partie
var _save_opt: Button                # Spielmenü des App-Gasts: „Regeln dieser Partie speichern“
var _confirm: ConfirmBox
var _save_box: RuleSetSaveBox
var _help: IngameHelp                # Spielmenü: „Regeln ansehen“ / „So geht's“ (1.0.2)
var _burger: Button                  # ☰ neben dem Zurück-Knopf: Menü im Spiel (Beta 1.1.2)
var _ingame_menu: IngameMenu
var _settings_ov: IngameSettings     # ☰ → „Einstellungen“: persönliche Einstellungen über dem Tisch
var _wild_drag := -1                # Wünscher, der gerade gezogen wird (Farbfelder offen)
var _pending_wild := -1              # Wünscher wartet auf das Farbrad
var _last_play := -1                 # optimistisch ausgespielt, Antwort steht aus
var _last_seat := -1                 # zuletzt gezeigter Platz (Sichtschutz: von wem kommt das Handy)
var _peek_down_ms := -1
var _peek_on := false
var _peek_was_on := false
var _handover_pending := false
var _sub_btn: Button                 # Gastgeber: „Computer für Kim spielen lassen“ (Gast ≥ 30 s weg, M4, Beta 1.3.3)
var _sub_seat := -1
var _sub_hint: PanelContainer        # Gastgeber: vorher nur „Kim ist kurz weg“ bzw. „… ist kurz in einer anderen App“
var _sub_hint_label: Label
var _sub_hint_seat := -1
var _sub_next_ms := 0                # nächste Prüfung der 30-s-Frist
var _host_app_away := false          # Gast: Gastgeber kurz in einer anderen App (Hinweis oben)


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
	table.big_changed.connect(func(_on: bool) -> void: _layout())
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
		if source.mode() == "client":
			source.lobby_changed.connect(_on_client_lobby)
		if source is GameTable:
			(source as GameTable).busy_check = _ui_busy
		var v := source.current_view()
		if not v.is_empty():
			_on_state([], v)
	if starter.is_valid():
		starter.call()


func _build_top() -> void:
	# Pfeil gezeichnet wie das ☰ (UiIcons), nicht als eingefärbtes Bild: Auf einem Gast-Gerät (1.3.2, Tag) erschien statt des Pfeils ein
	# schwarzes Quadrat – Texture2D.get_image() liest im Compatibility-Renderer je nach GPU nichts Brauchbares zurück.
	_menu_btn = ScreenKit.button("", "GhostButton", "", ScreenKit.TOUCH)
	_menu_btn.icon = UiIcons.icon("zurueck", 40, UiPalette.INK)
	_menu_btn.expand_icon = false
	_menu_btn.add_theme_constant_override("icon_max_width", 40)
	_menu_btn.name = "Menue"
	_menu_btn.tooltip_text = "Partie verlassen"
	_menu_btn.position = Vector2(14, 10)
	_menu_btn.size = Vector2(ScreenKit.TOUCH, ScreenKit.TOUCH)
	_menu_btn.modulate.a = 0.85
	_menu_btn.pressed.connect(func() -> void: on_back())
	_top.add_child(_menu_btn)
	_burger = ScreenKit.button("", "GhostButton", "", ScreenKit.TOUCH)
	_burger.name = "MenueKnopf"
	_burger.tooltip_text = "Menü: Einstellungen, Regeln, So geht's"
	_burger.size = Vector2(ScreenKit.TOUCH, ScreenKit.TOUCH)
	_burger.modulate.a = 0.85
	_burger.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_burger.pressed.connect(open_menu)
	_top.add_child(_burger)
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
	var texts := ScreenKit.vbox(2)
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(texts)
	_conn_label = ScreenKit.label("Verbinde neu …", "NightLabel", 24)
	_conn_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.add_child(_conn_label)
	_conn_sub = ScreenKit.label("", "NightLabel", 18)
	_conn_sub.name = "Gemerkt"
	_conn_sub.modulate.a = 0.8
	_conn_sub.visible = false
	texts.add_child(_conn_sub)
	_conn_host = ScreenKit.button("Selbst eröffnen", "PrimaryButton", "qr")
	_conn_host.name = "SelbstEroeffnen"
	_conn_host.tooltip_text = "Neues Spiel mit den Regeln dieser Partie eröffnen"
	_conn_host.visible = false
	_conn_host.pressed.connect(open_own_game)
	row.add_child(_conn_host)
	_conn_save = ScreenKit.button("Regeln speichern", "DarkButton")
	_conn_save.name = "RegelnSpeichern"
	_conn_save.visible = false
	_conn_save.pressed.connect(save_host_rules)
	row.add_child(_conn_save)
	_conn_menu = ScreenKit.button("Zum Menü", "DarkButton")
	_conn_menu.visible = false
	_conn_menu.pressed.connect(_leave_now)
	row.add_child(_conn_menu)
	_sub_btn = ScreenKit.button("", "PrimaryButton", "bot")
	_sub_btn.name = "ComputerUebernimmt"
	_sub_btn.tooltip_text = "Ein Computergegner spielt für den getrennten Gast, bis er zurückkommt."
	_sub_btn.visible = false
	_sub_btn.pressed.connect(ask_substitute)
	_top.add_child(_sub_btn)
	_sub_hint = ScreenKit.card(12.0, false)
	_sub_hint.name = "KurzWeg"
	_sub_hint.visible = false
	_sub_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_hint_label = ScreenKit.label("", "", 22)
	_sub_hint.add_child(_sub_hint_label)
	_top.add_child(_sub_hint)


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
	hand.layout_rect = table.hand_rect(sz)   # großer Modus: größere Karten (BigLayout.hand_rect)
	var mb := BigLayout.MENU if table.big else ScreenKit.TOUCH
	_menu_btn.size = Vector2(mb, mb)
	_menu_btn.custom_minimum_size = Vector2(mb, mb)
	# ☰ rechts neben dem Zurück-Knopf; im großen Modus darunter (rechts daneben beginnt dort der riesige Stapel)
	_burger.size = Vector2(mb, mb)
	_burger.custom_minimum_size = Vector2(mb, mb)
	_burger.position = Vector2(14.0, 10.0 + _menu_btn.size.y + 12.0) if table.big else Vector2(14.0 + _menu_btn.size.x + 12.0, 10.0)
	table.update_hand_target()          # Ablage bzw. Einsatzstapel (Glücksspiel), neue Karten vom Nachziehstapel
	_round_menu.size = Vector2(_round_menu.get_combined_minimum_size().x + 20.0, ScreenKit.TOUCH)
	_round_menu.position = Vector2(sz.x - _round_menu.size.x - 22.0, 14.0)
	_conn.reset_size()
	_conn.position = Vector2((sz.x - _conn.size.x) * 0.5, 16.0)
	_sub_btn.size = Vector2(_sub_btn.get_combined_minimum_size().x + 20.0, ScreenKit.TOUCH)
	_sub_btn.position = Vector2((_burger.position.x + _burger.size.x if not table.big else 14.0 + _menu_btn.size.x) + 14.0, 10.0)
	_sub_hint.reset_size()
	_sub_hint.position = _sub_btn.position + Vector2(0.0, (ScreenKit.TOUCH - _sub_hint.size.y) * 0.5)


func _process(_delta: float) -> void:
	if table == null:
		return
	_round_menu.visible = table.round_end.visible and not table.handover.visible
	_menu_btn.visible = not table.handover.visible
	_burger.visible = _menu_btn.visible
	if table.handover.visible:
		if is_help_open():
			_help.close()                # Regel 15: beim Weitergeben keine Karten, auch keine Regelbilder
		if is_menu_open():
			_ingame_menu.close()
		if is_settings_open():
			_settings_ov.close()
	_sync_conn_hint()
	_sync_menu_night()
	# „Computer für … spielen lassen“ verdeckt sonst die Frage über dem Farbrad (Ablegen-Joker)
	if _sub_btn != null:
		if Time.get_ticks_msec() >= _sub_next_ms:
			_sub_next_ms = Time.get_ticks_msec() + 500     # 30-s-Frist und Abwesenheit ohne neuen Stand nachführen
			_refresh_substitute()
		_sub_btn.visible = _sub_seat >= 0 and not table.wish_picker.is_open()
		_sub_hint.visible = _sub_seat < 0 and _sub_hint_seat >= 0 and not table.wish_picker.is_open()
		if _sub_hint.visible and bool(_sub_hint.get_meta("night", false)) != (table.night > 0.5):
			ScreenKit.set_card_night(_sub_hint, table.night > 0.5)
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
	var raw_rules: Variant = v.get("rules", {})
	var rules: Dictionary = raw_rules if raw_rules is Dictionary else {}
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
	if source != null and source.mode() == "client" and not rules.is_empty():
		RuleSets.remember_host(rules, _host_name())
	_record_stats(events, v)
	table.handle_state(events, v)
	_refresh_substitute()


# Statistik je Gerät (AppStats, Beta 1.2.1): zählt die gelieferten Ereignisse; der kleine Satz („Dein 12. Rundensieg!“) wartet
# im Rundenende, bis die Regie dort ankommt. Eine neue Runde löscht ihn.
func _record_stats(events: Array, v: Dictionary) -> void:
	var app := UiApp.app()
	var st: Variant = app.get("stats") if app != null else null
	if source == null or not st is Object or not (st as Object).has_method("record"):
		return
	var note := str((st as Object).call("record", events, v, source.mode()))
	if table == null or table.round_end == null:
		return
	if note != "":
		table.round_end.note = note
	else:
		for e in events:
			if e is Dictionary and str(e.get("e", "")) == "round_start":
				table.round_end.note = ""


# Bots warten, solange die Regie noch abspielt
func _ui_busy() -> bool:
	return table != null and is_instance_valid(table) and table.director.is_busy()


func _on_notice(text: String) -> void:
	if _last_play >= 0:
		hand.cancel_play(_last_play)
		_last_play = -1
	table.gamble_machine.press_sent = false
	table.gamble_machine.queue_redraw()      # „Aufhören“ wieder zeigen
	table.pick_retry()                        # „Farbe mit ablegen“: Auswahl wieder anbieten
	table.show_notice(text, "warn")


# Weitergeben: Sichtschutz vor dem nächsten Menschen; die alte Hand verschwindet darunter
func _on_handover(next_seat: int, player_name: String) -> void:
	_handover_pending = true
	_set_peek(false)
	hand.close_big_view()
	table.wish_picker.close()
	table.help_popup.close()
	var n: int = (view.get("players", []) as Array).size()
	var from := _last_seat               # -1 zu Partiebeginn: Sichtschutz ohne Richtung
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
			_conn_label.text = _conn_hint()
			_conn_menu.visible = false
			_conn_save.visible = false
			_conn_host.visible = false
			_conn_sub.visible = false
			_conn.visible = true
		"closed", "rejected", "ended":
			# Spielende und Gastgeber weg (N6) bzw. Wiederverbinden abgelehnt: klar „Spiel beendet“, Weg ins Menü
			var over := state == "ended" or (state == "rejected" and not view.is_empty())
			_conn_label.text = "Spiel beendet." if over else "Verbindung zum Gastgeber beendet."
			_conn_menu.visible = true
			var guest := _guest_rules() != null
			_conn_save.visible = guest
			_conn_host.visible = guest
			_conn_sub.visible = guest
			_conn_sub.text = I18n.t("Die Regeln von %s sind gemerkt. Eröffne selbst, dann spielt ihr mit ihnen weiter.") % _host_name()
			_refresh_saved_state()
			_conn.visible = true
	_layout()


# App-Gast: Lobby am Tisch = neue Runde des Gastgebers. Verbindung an die Lobby übergeben, dieser Tisch ist zu Ende.
func _on_client_lobby(l: Dictionary) -> void:
	if leaving or nav == null or not source is ClientTable or (l.get("players", []) as Array).is_empty():
		return
	leaving = true
	var ct := source as ClientTable
	for c in [[ct.state_changed, _on_state], [ct.notice, _on_notice], [ct.handover, _on_handover],
			[ct.connection_changed, _on_connection], [ct.lobby_changed, _on_client_lobby]]:
		if (c[0] as Signal).is_connected(c[1]):
			(c[0] as Signal).disconnect(c[1])
	source = null
	if _confirm != null and is_instance_valid(_confirm):
		_confirm.queue_free()
		_confirm = null
	var js := JoinScreen.with_client(ct)
	nav.replace(js)
	nav.toast("Diese Partie ist vorbei. Der Gastgeber hat eine neue Runde eröffnet.")


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


# Ablegen-Joker: zuerst die Ablegefarbe im Farbrad (mit Frage), Farbfelder beim Ziehen gibt es für ihn nicht
static func is_discard_joker(face: String) -> bool:
	return str(CardDB.parse_key(face).get("kind", "")) == CardDB.DISCARD_WILD


func _is_wild(id: int, face: String) -> bool:
	var hints: Dictionary = view.get("hints", {})
	var wild: Array = hints.get("wild", [])
	if wild.has(id) or wild.has(float(id)):
		return true
	return JokerRays.is_joker(face)


# Glücksspiel: Der eigene Einsatz ist fällig (Handkarten gehen verdeckt auf den Einsatzstapel)
func _staking() -> bool:
	var raw: Variant = view.get("gamble", {})
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		return false
	var gb: Dictionary = raw
	var me := int(view.get("seat", -1))
	return me >= 0 and int(gb.get("seat", -2)) == me and str(gb.get("need", "")) == "stake"


func _on_play_requested(id: int, drop_global: Vector2) -> void:
	if _staking():
		_last_play = id
		_act({"a": "stake", "card": id})
		return
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
			if is_discard_joker(face):
				table.wish_picker.open_wheel(table.side, table.call("_own_counts"), "Welche Farbe legst du mit ab?")
			else:
				table.open_color_wheel()
		return
	_last_play = id
	_act({"a": "play", "card": id})


func _on_drag_started(id: int, face: String) -> void:
	if _staking():
		return
	var playable: Array = (view.get("hints", {}) as Dictionary).get("playable", [])
	if _is_wild(id, face) and not is_discard_joker(face) and (playable.has(id) or playable.has(float(id))):
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
	elif not hand.highlight and str(view.get("phase", "")) in ["turn", "drawn", "challenge"]:
		# ohne Hervorheben: die Karte springt zurück, ein kurzer Hinweis, keine Strafe
		table.show_notice("Die Karte passt nicht.")
	else:
		var hints: Dictionary = view.get("hints", {})
		var t := table.hint_text(str(hints.get("text", "")))
		table.show_notice("Diese Karte passt gerade nicht." if t == "" or t == "Du bist dran." else table._hint_local(str(hints.get("text", "")), hints.get("lt", []) if hints.get("lt") is Array else []))


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
	table.show_notice(I18n.t("Sortiert nach %s") % I18n.t(SORT_LABELS[next]) if next != "manuell" else "Eigene Reihenfolge – Karte halten und seitlich ziehen")


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

# Hinweis bei Online-Aussetzern (Beta 1.3.3, Nutzerbefund 1.3.2: niemand sah, dass die Verbindung weg war).
# Gast: Text je nach Lage (Gastgeber kurz weg / Verbindung unterbrochen), auch wenn er während des Wartens wechselt.
# Gastgeber: solange seine Verbindung zum Vermittler neu aufgebaut wird, „Online-Verbindung unterbrochen – verbinde neu …“.
func _conn_hint() -> String:
	return str(source.call("connection_hint")) if source != null and source.has_method("connection_hint") else "Verbinde neu …"


func _sync_conn_hint() -> void:
	if source is HostTable:
		var s: NetHostSession = (source as HostTable).session
		var away := s != null and s.online_state() == "away"
		if away == _online_away:
			return
		_online_away = away
		_conn_label.text = "Online-Verbindung unterbrochen – verbinde neu …"
		for b: Control in [_conn_menu, _conn_save, _conn_host, _conn_sub]:
			b.visible = false
		_conn.visible = away
		_layout()
	elif _conn.visible and _conn_label.text != _conn_hint() and source != null and source.has_method("connection_state") \
			and str(source.call("connection_state")) == "connecting":
		_conn_label.text = _conn_hint()
		_layout()
	else:
		# Gast (Beta 1.3.3): Gastgeber meldet „kurz in einer anderen App“ → deutlich oben, solange die Verbindung offen ist
		var who := _away_host_name()
		if who != "":
			var text := I18n.t("%s (Gastgeber) ist kurz in einer anderen App – warte …") % who
			_host_app_away = true
			if not _conn.visible or _conn_label.text != text:
				_conn_label.text = text
				for b: Control in [_conn_menu, _conn_save, _conn_host, _conn_sub]:
					b.visible = false
				_conn.visible = true
				_layout()
		elif _host_app_away:
			_host_app_away = false
			if source != null and str(source.call("connection_state")) == "open":
				_conn.visible = false
			_layout()


# Name des Gastgebers, wenn er laut Stand kurz in einer anderen App ist (nur App-Gast, Verbindung offen); sonst "".
func _away_host_name() -> String:
	if not source is ClientTable or str(source.call("connection_state")) != "open":
		return ""
	for p in view.get("players", []):
		if p is Dictionary and bool(p.get("host", false)) and bool(p.get("away", false)):
			return str(p.get("name", ""))
	return ""


# Zurück-Knopf nachts hell (Nutzerbefund 07.10.2026: auf der Nachtseite unsichtbar): heller Pfeil und heller Rand, tagsüber wie bisher.
func _sync_menu_night() -> void:
	var n := 1 if table.night > 0.5 else 0
	if n == _menu_night:
		return
	_menu_night = n
	_menu_btn.icon = UiIcons.icon("zurueck", 40, UiPalette.PAPER if n == 1 else UiPalette.INK)
	_menu_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# ☰ (Beta 1.1.2) im selben Stil: gezeichnete Striche, tagsüber Druckfarbe, nachts hell
	_burger.icon = UiIcons.icon("menue", 40, UiPalette.PAPER if n == 1 else UiPalette.INK)
	for b: Button in [_menu_btn, _burger]:
		for ic in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color"]:
			if n == 1 or b == _menu_btn:
				b.add_theme_color_override(ic, Color.WHITE)    # Pfeil in seiner gezeichneten Farbe
			else:
				b.remove_theme_color_override(ic)
		for st in ["normal", "hover", "pressed", "focus"]:
			if n == 1:
				var sb := StyleBoxFlat.new()
				sb.bg_color = Color(UiPalette.PAPER, 0.10 if st == "normal" else 0.2)
				sb.border_color = Color(UiPalette.PAPER, 0.75)
				sb.set_border_width_all(2)
				sb.set_corner_radius_all(int(ScreenKit.TOUCH * 0.5))
				b.add_theme_stylebox_override(st, sb)
			else:
				b.remove_theme_stylebox_override(st)


func on_back() -> bool:
	if leaving:
		return true
	if is_settings_open():
		_settings_ov.close()
		return true
	if is_menu_open():
		_ingame_menu.close()
		return true
	if is_help_open():
		_help.close()
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
	if _save_box != null and is_instance_valid(_save_box):
		_save_box.cancel()
		_save_box = null
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
	var rules_opt := _confirm.add_option("Regeln ansehen", "regeln")
	rules_opt.name = "RegelnAnsehen"
	rules_opt.pressed.connect(open_help.bind("regeln"))
	var how_opt := _confirm.add_option("So geht's", "hilfe")
	how_opt.name = "SoGehts"
	how_opt.pressed.connect(open_help.bind("bedienung"))
	# beide nebeneinander in einer Zeile, damit die Rückfrage auch bei großer Schrift niedrig bleibt
	var help_row := ScreenKit.hbox(16)
	help_row.name = "Hilfe"
	rules_opt.get_parent().add_child(help_row)
	help_row.get_parent().move_child(help_row, rules_opt.get_index())
	for b: Button in [rules_opt, how_opt]:
		b.reparent(help_row, false)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _guest_rules() != null:
		# Die Rückfrage bleibt offen: Wer gehen wollte, geht nach dem Speichern mit „Verlassen“.
		_save_opt = _confirm.add_option("Regeln dieser Partie speichern", "regeln")
		_save_opt.name = "RegelnSpeichern"
		_save_opt.pressed.connect(save_host_rules)
		_refresh_saved_state()
	return true


# Spielmenü → „Regeln ansehen“ (tab "regeln") bzw. „So geht's“ (tab "bedienung"): Die Rückfrage schließt, die Überlagerung
# zeigt die Regeln dieser Partie (view.rules) bzw. die Bedienung; die Partie läuft weiter. Nicht während des Sichtschutzes.
func open_help(which := "regeln") -> void:
	if _confirm != null and is_instance_valid(_confirm):
		_confirm.queue_free()
		_confirm = null
	if is_help_open():
		_help.show_tab(which)
		return
	if table == null or table.handover.visible:
		return
	_help = IngameHelp.open(_top, view.get("rules", {}), table.night > 0.5, true, which)
	_help.closed.connect(func() -> void: _help = null)


func is_help_open() -> bool:
	return _help != null and is_instance_valid(_help) and not _help.is_queued_for_deletion()


# ☰ (Beta 1.1.2): Menü unter dem Knopf mit „Einstellungen“, „Regeln ansehen“, „So geht's“. Nicht während des Sichtschutzes.
func open_menu() -> void:
	if table == null or table.handover.visible or leaving or is_menu_open():
		return
	if _confirm != null and is_instance_valid(_confirm):
		_confirm.queue_free()
		_confirm = null
	var at := _burger.position + Vector2(_burger.size.x + 12.0, 0.0) if table.big else _burger.position + Vector2(0.0, _burger.size.y + 10.0)
	_ingame_menu = IngameMenu.open(_top, at)
	_ingame_menu.chosen.connect(func(key: String) -> void:
		if key == "einstellungen":
			open_settings()
		else:
			open_help(key))
	_ingame_menu.closed.connect(func() -> void: _ingame_menu = null)


func is_menu_open() -> bool:
	return _ingame_menu != null and is_instance_valid(_ingame_menu) and not _ingame_menu.is_queued_for_deletion()


# Persönliche Einstellungen über dem Tisch; die Partie läuft weiter, Änderungen wirken sofort (App.settings.changed).
func open_settings() -> void:
	if table == null or table.handover.visible or is_settings_open():
		return
	if is_help_open():
		_help.close()
	_settings_ov = IngameSettings.open(_top, _has_bots())
	_settings_ov.closed.connect(func() -> void: _settings_ov = null)


func is_settings_open() -> bool:
	return _settings_ov != null and is_instance_valid(_settings_ov) and not _settings_ov.is_queued_for_deletion()


# Tempo-Regler nur, wo er wirkt: Computergegner an diesem Tisch, den dieses Gerät rechnet (nicht als WLAN-Gast)
func _has_bots() -> bool:
	var gt := source as GameTable
	if gt == null:
		return false
	for p in gt.seats:
		if p is Dictionary and str((p as Dictionary).get("kind", "")) == "bot":
			return true
	return false


# App-Gast: Regeln des Gastgebers aus der Sicht (null = kein Gast oder noch keine Sicht)
func _guest_rules() -> RuleConfig:
	if source == null or source.mode() != "client":
		return null
	var rules: Variant = view.get("rules", {})
	if not rules is Dictionary or (rules as Dictionary).is_empty():
		return null
	return RuleSets.load_config(rules)


# Name des Gastgebers: Lobby (Spieler mit host_id), sonst die Begrüßung, sonst „Gastgeber“
func _host_name() -> String:
	var ct := source as ClientTable
	if ct == null:
		return "Gastgeber"
	var welcomed := ct.client.host_name if ct.client != null else ""
	return RuleSets.host_name_in_lobby(ct.lobby, welcomed if welcomed != "" else "Gastgeber")


# „Regeln speichern“ (Spielmenü bzw. Verbindungsleiste des App-Gasts): Regeln der Partie als eigenen Satz ablegen. Der Dialog
# liegt über einer offenen Rückfrage; die bleibt stehen.
func save_host_rules() -> void:
	var cfg := _guest_rules()
	if cfg == null or (_save_box != null and is_instance_valid(_save_box)):
		return
	var who := _host_name()
	var suggestion := RuleSets.match_name(cfg)
	if suggestion == "":
		suggestion = RuleSets.suggestion_for_host(who)
	_wire_save_box(RuleSetSaveBox.ask(_top, cfg, suggestion, who))


# Speichern-Dialog aus der Lobby übernehmen (die Partie hat begonnen, während er offen war); getippter Name bleibt
func adopt_save_box(box: RuleSetSaveBox) -> void:
	if box == null or not is_instance_valid(box) or box.is_queued_for_deletion():
		return
	if _save_box != null and is_instance_valid(_save_box):
		box.queue_free()
		return
	if box.get_parent() != _top:
		box.reparent(_top, false)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wire_save_box(box)
	box._focus_field.call_deferred()


func _wire_save_box(box: RuleSetSaveBox) -> void:
	_save_box = box
	box.saved.connect(func(n: String) -> void:
		_save_box = null
		_refresh_saved_state()
		if _confirm == null or not is_instance_valid(_confirm):
			table.show_notice(I18n.t("Gespeichert: „%s“") % n))
	box.cancelled.connect(func() -> void: _save_box = null)


# „Regeln speichern“ zeigt „Gespeichert: …“, wenn die Regeln der Partie schon einem eigenen Satz entsprechen (Leiste und Spielmenü)
func _refresh_saved_state() -> void:
	var cfg := _guest_rules()
	var saved := RuleSets.match_name(cfg) if cfg != null else ""
	if _conn_save != null:
		_conn_save.text = (I18n.t("Gespeichert: „%s“") % saved) if saved != "" else "Regeln speichern"
	if _save_opt != null and is_instance_valid(_save_opt):
		_save_opt.text = (I18n.t("Gespeichert als „%s“") % saved) if saved != "" else "Regeln dieser Partie speichern"
	if _conn != null and _conn.visible:
		_layout()


# „Selbst eröffnen“ (App-Gast, Verbindung beendet): mit genau den Regeln dieser Partie eine neue Gastgeber-Lobby öffnen
func open_own_game() -> void:
	var cfg := _guest_rules()
	if cfg == null or leaving or nav == null:
		return
	leaving = true
	RulesBar.store(cfg)
	if source != null:
		source.leave()
	nav.replace(HostLobbyScreen.new())


func _leave_now() -> void:
	if leaving:
		return
	leaving = true
	if source != null:
		source.leave()
	if nav != null:
		nav.home()


# ================================================================= Gastgeber: Computer übernimmt (M4)

# Knopf „Computer spielt für …“, solange ein Gast getrennt ist (zuerst der, auf den das Spiel wartet). Kommt er zurück, spielt er
# selbst weiter (HostTable._on_rejoined beendet die Vertretung).
# Beta 1.3.3 (Nutzerbefund: „Computer spielt für Püppi“ wirkte wie ein Zustand): Der Knopf heißt „Computer für %s spielen lassen“ und
# kommt erst, wenn der Gast 30 s weg (andere App) oder getrennt ist; vorher nur der Hinweis „%s ist kurz weg“ bzw. „… in einer anderen App“.
func _refresh_substitute() -> void:
	if _sub_btn == null:
		return
	var old_seat := _sub_seat
	var old_hint := _sub_hint_label.text
	_sub_seat = -1
	_sub_hint_seat = -1
	if source is HostTable and not leaving and not str(view.get("phase", "")) in ["round_end", "game_over"]:
		var ht := source as HostTable
		var w := ht.waiting_seat()
		var cur := int(view.get("turn", -1))
		var list: Array = ht.substitutable_seats()
		if not list.is_empty():
			_sub_seat = w if list.has(w) else (cur if list.has(cur) else int(list[0]))
		else:
			var absent: Array = ht.absent_seats()
			if not absent.is_empty():
				_sub_hint_seat = w if absent.has(w) else (cur if absent.has(cur) else int(absent[0]))
				var who := ht.seat_name(_sub_hint_seat)
				_sub_hint_label.text = (I18n.t("%s ist kurz in einer anderen App") if ht.is_away(_sub_hint_seat) else I18n.t("%s ist kurz weg")) % who
	_sub_btn.visible = _sub_seat >= 0
	_sub_hint.visible = _sub_seat < 0 and _sub_hint_seat >= 0
	if _sub_seat >= 0:
		_sub_btn.text = I18n.t("Computer für %s spielen lassen") % (source as HostTable).seat_name(_sub_seat)
	if _sub_seat != old_seat or _sub_hint_label.text != old_hint:
		_layout()


func ask_substitute() -> void:
	if _sub_seat < 0 or not source is HostTable:
		return
	var seat := _sub_seat
	var who := (source as HostTable).seat_name(seat)
	if _confirm != null and is_instance_valid(_confirm):
		_confirm.queue_free()
	_confirm = ConfirmBox.ask(_top, "Computer übernimmt?", I18n.t("Ein Computergegner spielt für %s. Kommt %s zurück, spielt er wieder selbst.") % [who, who], "Übernehmen", "Abbrechen")
	_confirm.answered.connect(func(yes: bool) -> void:
		_confirm = null
		if yes and source is HostTable:
			(source as HostTable).substitute_bot(seat)
		_refresh_substitute())
