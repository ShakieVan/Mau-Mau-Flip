class_name SeatManager
extends Control
# Feld „Mitspieler“ im Spiel (Beta 1.4.2, docs/module/dazuholen.md 4): nur beim Gastgeber eines Netzwerkspiels (HostTable), über
# ☰ → „Mitspieler dazuholen“ / „Mitspieler entfernen“ und das Zurück-Menü. Überlagerung über dem Tisch (tags Papier, nachts dunkel,
# folgt dem Tisch), die Partie läuft weiter. Zwei Seiten:
#   „Dazuholen“: das Einladefeld der Lobby (InvitePanel: WLAN-/Spiel-WLAN-QR, Online-QR, Raumcode, „Link teilen“) und
#                „+ Computergegner“.
#   „Am Tisch“:  die Sitzordnung als Liste. Wartende (Warteliste der Sitzung) und neue Computergegner stehen hervorgehoben darin und
#                rücken mit ▲▼ an ihren Platz (die Sitzenden bleiben, wie sie sind); „An den Tisch holen“ mit Rückfrage („Kim setzt
#                sich zwischen Anna und Ben und bekommt 5 Karten.“), „Ablehnen“. Bei jedem Sitzenden außer dem Gastgeber ✕ „Aus dem
#                Spiel nehmen“ mit Rückfrage. Aufgeschobene Aufträge zeigen „Kommt nach diesem Zug dazu“ / „Geht nach diesem Zug“ und
#                lassen sich zurücknehmen.
# Solange das Feld offen ist, dürfen Neue auf die Warteliste (HostTable.set_join_open). Kommt jemand neu dazu, springt die Ansicht
# auf „Am Tisch“. Nichts passiert ohne Tippen und Rückfrage. Keine Karten (Regel 15).

signal closed

const ROW_H := 72.0
const WAIT_COLOR := Color("#F59E1B")

var host: HostTable
var invite: InvitePanel
var night := false
var page := "dazuholen"
var _card: PanelContainer
var _tabs: HBoxContainer
var _pages := {}
var _list: VBoxContainer
var _scroll: ScrollContainer
var _count: Label
var _bot_btn: Button
var _bot_btn2: Button
var _hint: Label
var _confirm: ConfirmBox
var _order: Array = []            # Sitzordnung samt Wartenden (Spieler-ids der Sitzung; Computer-Platzhalter: id ≤ BOT_ID)
var _bots: Array = []             # Platzhalter neuer Computergegner (noch nicht angefragt)
var _next_bot := -100
var _sig := ""
var _seen_waiting: Array = []
var _check_ms := 0

const BOT_ID := -100


static func open(parent: Node, host_table: HostTable, first_page := "dazuholen") -> SeatManager:
	var m := SeatManager.new()
	m.theme = UiTheme.get_theme()
	m.host = host_table
	parent.add_child(m)
	m._build(first_page)
	TableView.follow_night(m, m.set_night)
	return m


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	name = "Mitspieler"


func _build(first_page: String) -> void:
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 60)
	for side in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 20)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	_card = ScreenKit.card(22.0)
	m.add_child(_card)
	var v := ScreenKit.vbox(12)
	_card.add_child(v)
	var head := ScreenKit.hbox(14)
	v.add_child(head)
	var title := ScreenKit.heading("Mitspieler", UiFonts.size("dialog"))
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	_tabs = ScreenKit.choice([["dazuholen", "Dazuholen"], ["tisch", "Am Tisch"]], first_page, show_page, UiFonts.size("text"))
	_tabs.name = "Seiten"
	_tabs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_tabs)
	head.add_child(ScreenKit.spacer())
	var close_btn := ScreenKit.button("Schließen", "PrimaryButton", "kreuz")
	close_btn.name = "Schliessen"
	close_btn.pressed.connect(close)
	head.add_child(close_btn)
	# --- Seite „Dazuholen“: Einladefeld der Lobby, darunter Computergegner
	var p1 := ScreenKit.vbox(10)
	p1.name = "Dazuholen"
	p1.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(p1)
	_pages["dazuholen"] = p1
	var sc := ScreenKit.scroller()
	sc.name = "Einladen"
	p1.add_child(sc)
	invite = InvitePanel.new()
	invite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	invite.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.add_child(invite)
	invite.setup(host)
	var row1 := ScreenKit.hbox(12)
	p1.add_child(row1)
	var h1 := ScreenKit.hint("Wer den Code scannt, erscheint unter „Am Tisch“. Dort wählst du seinen Platz.", UiFonts.size("hinweis"))
	h1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row1.add_child(h1)
	_bot_btn = ScreenKit.button("Computergegner dazuholen", "GhostButton", "roboter")
	_bot_btn.name = "PlusComputer"
	_bot_btn.tooltip_text = "Ein Computergegner spielt mit."
	_bot_btn.pressed.connect(add_bot_slot)
	row1.add_child(_bot_btn)
	# --- Seite „Am Tisch“: Sitzordnung mit Wartenden
	var p2 := ScreenKit.vbox(10)
	p2.name = "AmTisch"
	p2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(p2)
	_pages["tisch"] = p2
	_scroll = ScreenKit.scroller()
	_scroll.name = "Sitzordnung"
	p2.add_child(_scroll)
	_list = ScreenKit.vbox(4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	var row2 := ScreenKit.hbox(12)
	p2.add_child(row2)
	_hint = ScreenKit.hint("", UiFonts.size("hinweis"))
	_hint.name = "Hinweis"
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row2.add_child(_hint)
	_count = ScreenKit.label("", "HintLabel", UiFonts.size("text"))
	_count.name = "Spielerzahl"
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row2.add_child(_count)
	_bot_btn2 = ScreenKit.button("Computergegner dazuholen", "GhostButton", "roboter")
	_bot_btn2.name = "PlusComputer2"
	_bot_btn2.tooltip_text = "Ein Computergegner spielt mit."
	_bot_btn2.pressed.connect(add_bot_slot)
	row2.add_child(_bot_btn2)
	if host != null:
		host.set_join_open(true)
		host.lobby_changed.connect(_on_lobby)
		host.state_changed.connect(func(_e: Array, _v: Dictionary) -> void: refresh())
		_seen_waiting = host.waiting_ids().duplicate()
	show_page(first_page)
	refresh(true)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.1, 0.55))


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if not _card.get_global_rect().has_point(get_global_transform() * mb.position):
			close()
		accept_event()


func _process(_delta: float) -> void:
	# Abwesenheit, Verbindung und aufgeschobene Aufträge ändern sich auch ohne neuen Stand: zweimal je Sekunde nachsehen
	if Time.get_ticks_msec() >= _check_ms:
		_check_ms = Time.get_ticks_msec() + 500
		refresh()


func show_page(key: String) -> void:
	page = key if _pages.has(key) else "dazuholen"
	for k in _pages:
		(_pages[k] as Control).visible = k == page
	ScreenKit.set_choice(_tabs, page)


func close() -> void:
	if is_queued_for_deletion():
		return
	if _confirm != null and is_instance_valid(_confirm):
		_confirm.queue_free()
		_confirm = null
	if host != null and is_instance_valid(host):
		host.set_join_open(false)       # Wartende bleiben trotzdem angenommen (NetHostSession.accepts_late)
	closed.emit()
	queue_free()


# Zurück-Taste: zuerst eine offene Rückfrage
func on_back() -> void:
	if _confirm != null and is_instance_valid(_confirm):
		_confirm.cancel()
		_confirm = null
		return
	close()


func is_confirm_open() -> bool:
	return _confirm != null and is_instance_valid(_confirm) and not _confirm.is_queued_for_deletion()


# Tag/Nacht des Tisches: dunkle Karte, auch die inneren Karten des Einladefelds (sonst helle Schrift auf Papier)
func set_night(on: bool) -> void:
	night = on
	if _card == null:
		return
	ScreenKit.set_card_night(_card, on)
	for c in _card.find_children("*", "PanelContainer", true, false):
		if (c as PanelContainer).has_meta("margin"):        # mit ScreenKit.card gebaut (Schritte ① ②, Online)
			ScreenKit.set_card_night(c as PanelContainer, on)
	refresh(true)


func _on_lobby(l: Dictionary) -> void:
	if invite != null:
		invite.set_guests(HostLobbyScreen.guest_count(l))
		invite.set_online_guests(HostLobbyScreen.online_count(l))
	var w := host.waiting_ids() if host != null else []
	for id in w:
		if not _seen_waiting.has(id):
			show_page("tisch")         # jemand Neues wartet: gleich die Platzwahl zeigen
	_seen_waiting = w.duplicate()
	refresh()


# ---------------------------------------------------------------- Modell

func _seat_ids() -> Array:
	var raw: Variant = host.get("_seat_ids") if host != null else []
	return (raw as Array).duplicate() if raw is Array else []


# Sitzordnung samt Wartenden: Sitzende in Platzreihenfolge, jeder Wartende bleibt hinter dem, hinter den man ihn gerückt hat;
# Neue kommen ans Ende (also vor den Gastgeber, im Uhrzeigersinn hinter den Letzten).
func _rebuild_order() -> void:
	var seated := _seat_ids()
	var extra: Array = []
	if host != null:
		for id in host.waiting_ids():
			if host.seat_op_of(int(id)) == "":
				extra.append(int(id))
	extra.append_array(_bots)
	extra.sort_custom(func(a: int, b: int) -> bool:
		var ia := _order.find(a)
		var ib := _order.find(b)
		if ia < 0:
			return false
		if ib < 0:
			return true
		return ia < ib)
	var res := seated.duplicate()
	for w in extra:
		var i := _order.find(w)
		var pos := res.size()
		if i >= 0:
			pos = 0
			for j in range(i - 1, -1, -1):
				var k := res.find(_order[j])
				if k >= 0:
					pos = k + 1
					break
		res.insert(pos, w)
	_order = res


func _is_bot_slot(id: int) -> bool:
	return id <= BOT_ID


# Platz in der neuen Sitzordnung (Zahl der Sitzenden davor)
func place_of(id: int) -> int:
	var seated := _seat_ids()
	var n := 0
	for x in _order:
		if int(x) == id:
			return n
		if seated.has(x):
			n += 1
	return n


# Nachbarn eines Wartenden (Namen der Sitzenden davor und dahinter, im Kreis)
func neighbours(id: int) -> Array:
	var seated := _seat_ids()
	if seated.is_empty():
		return ["", ""]
	var at := place_of(id)
	var before := posmod(at - 1, seated.size())
	var after := at % seated.size()
	return [host.seat_name(before), host.seat_name(after)]


func move(id: int, d: int) -> void:
	var i := _order.find(id)
	var j := i + d
	if i < 0 or j < 0 or j >= _order.size():
		return
	_order[i] = _order[j]
	_order[j] = id
	refresh(true)


func _room_left() -> bool:
	if host == null or host.game == null:
		return false
	var adds := host.pending_seat_ops().filter(func(o): return str(o.op) != "out").size()
	return host.seats.size() + adds < MauGame.MAX_PLAYERS


# ---------------------------------------------------------------- Liste

func refresh(force := false) -> void:
	if host == null or _list == null or not is_instance_valid(host):
		return
	_rebuild_order()
	var seated := _seat_ids()
	var parts: Array = [night, _order, host.pending_seat_ops(), _room_left(), I18n.language()]
	for id in _order:
		var s := seated.find(id)
		if s >= 0:
			parts.append([s, host.seat_name(s), host.is_away(s), _connected(s), host.is_substituted(s)])
		elif not _is_bot_slot(int(id)):
			var p := host.session.player(int(id)) if host.session != null else {}
			parts.append([str(p.get("name", "")), bool(p.get("connected", true))])
	var sig := JSON.stringify(parts)
	if sig == _sig and not force:
		return
	_sig = sig
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var pending: Array = host.pending_seat_ops()
	var room := _room_left()
	var waiting := 0
	for i in _order.size():
		var id := int(_order[i])
		if not seated.has(id):
			waiting += 1
		_list.add_child(_row(id, i, seated))
	for o in pending:
		if str(o.op) == "bot":
			_list.add_child(_pending_bot_row(o))
	_count.text = I18n.t("%d von %d Spielern") % [seated.size(), MauGame.MAX_PLAYERS]
	_bot_btn.disabled = not room
	_bot_btn2.disabled = not room
	if not room:
		_hint.text = I18n.t("Am Tisch ist kein Platz mehr.")
	elif waiting > 0:
		_hint.text = I18n.t("Mit ▲ ▼ rückst du Neue an ihren Platz, dann „An den Tisch“.")
	else:
		_hint.text = I18n.t("Neue Mitspieler erscheinen hier, sobald sie den Code scannen.")
	var tab := _tabs.get_child(1) as Button
	if tab != null:
		tab.text = I18n.t("Am Tisch") + ("  (%d)" % waiting if waiting > 0 else "")


func _connected(s: int) -> bool:
	return host.game == null or s >= host.game.connected.size() or bool(host.game.connected[s])


func _ink(a := 1.0) -> Color:
	return Color(UiPalette.PAPER if night else UiPalette.INK, a)


func _row(id: int, i: int, seated: Array) -> Control:
	var s := seated.find(id)
	var wait := s < 0
	var bot_slot := _is_bot_slot(id)
	var p: Dictionary = host.session.player(id) if host.session != null and not bot_slot else {}
	var op := host.seat_op_of(id) if not bot_slot else ""
	var name_text := host.seat_name(s) if s >= 0 else (I18n.t("Neuer Computergegner") if bot_slot else str(p.get("name", "?")))
	var kind := "bot" if bot_slot else str(p.get("kind", "app"))
	if s >= 0 and host.is_bot(s):
		kind = "bot"
	var outer := PanelContainer.new()
	outer.name = ("Wartet%d" % id) if wait else ("Platz%d" % s)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(18)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 6.0
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 2.0
	if wait or op == "out":
		sb.bg_color = Color(WAIT_COLOR if wait else UiPalette.ALERT, 0.16)
		sb.border_color = Color(WAIT_COLOR if wait else UiPalette.ALERT, 0.85)
		sb.set_border_width_all(3)
	else:
		sb.bg_color = Color(0, 0, 0, 0)
	outer.add_theme_stylebox_override("panel", sb)
	var row := ScreenKit.hbox(10)
	row.custom_minimum_size = Vector2(0, ROW_H)
	outer.add_child(row)
	var no := ScreenKit.label(str(i + 1), "", UiFonts.size("text"), _ink(0.72))
	no.custom_minimum_size = Vector2(30, 0)
	no.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(no)
	var av := ScreenKit.avatar(s if s >= 0 else i, name_text, "bot" if kind == "bot" else "human", 48.0)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(av)
	var texts := ScreenKit.vbox(0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(texts)
	var nl := ScreenKit.label(name_text, "", UiFonts.size("zeile"))
	nl.add_theme_font_override("font", UiFonts.text(700))
	texts.add_child(nl)
	var tag: String = I18n.t({"app": "App", "web": "Browser", "bot": "Computer"}.get(kind, kind))
	var alert := false
	if s >= 0 and s == host.host_seat:
		tag = I18n.t("Gastgeber (du)")
	elif not bot_slot and bool(p.get("online", false)):
		tag += " · " + I18n.t("online")
	if op == "in" or op == "bot":
		tag += " · " + I18n.t("Kommt nach diesem Zug dazu")
	elif op == "out":
		tag += " · " + I18n.t("Geht nach diesem Zug")
	elif wait:
		tag += " · " + I18n.t("wartet auf einen Platz")
		if not bot_slot and not bool(p.get("connected", true)):
			tag += " · " + I18n.t("getrennt")
			alert = true
	elif s >= 0 and s != host.host_seat and kind != "bot":
		if host.is_substituted(s):
			tag += " · " + I18n.t("Computer spielt für ihn")
		if host.is_away(s):
			tag += " · " + I18n.t("kurz in einer anderen App")
			alert = true
		elif not _connected(s):
			tag += " · " + I18n.t("getrennt")
			alert = true
	var tl := ScreenKit.label(tag, "HintLabel", UiFonts.size("klein"))
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if alert:
		tl.add_theme_color_override("font_color", UiPalette.ALERT if not night else Color("#FF9AA0"))
	texts.add_child(tl)
	if wait and op == "":
		var up := _row_button(ScreenKit.glyph("pfeil", 34, -90), "nach vorn")
		up.name = "Hoch"
		up.disabled = i == 0
		up.pressed.connect(move.bind(id, -1))
		row.add_child(up)
		var down := _row_button(ScreenKit.glyph("pfeil", 34, 90), "nach hinten")
		down.name = "Runter"
		down.disabled = i == _order.size() - 1
		down.pressed.connect(move.bind(id, 1))
		row.add_child(down)
		var seat_btn := ScreenKit.button("An den Tisch", "PrimaryButton")
		seat_btn.name = "AnDenTisch"
		seat_btn.disabled = not _room_left()
		seat_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		seat_btn.pressed.connect(ask_seat.bind(id))
		row.add_child(seat_btn)
		var no_btn := ScreenKit.button("Entfernen" if bot_slot else "Ablehnen", "GhostButton")
		no_btn.name = "Ablehnen"
		no_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		no_btn.pressed.connect(ask_reject.bind(id))
		row.add_child(no_btn)
	elif op != "":
		var undo := ScreenKit.button("Zurücknehmen", "GhostButton")
		undo.name = "Zuruecknehmen"
		undo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		undo.pressed.connect(func() -> void:
			host.cancel_seat_op(id)
			refresh(true))
		row.add_child(undo)
	elif s >= 0 and s != host.host_seat:
		var rm := ScreenKit.button("Aus dem Spiel nehmen", "GhostButton")
		rm.name = "Entfernen"
		rm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rm.pressed.connect(ask_remove_seat.bind(s))
		row.add_child(rm)
	return outer


func _pending_bot_row(o: Dictionary) -> Control:
	var row := ScreenKit.hbox(10)
	row.name = "ComputerKommt"
	row.custom_minimum_size = Vector2(0, ROW_H)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(30, 0)
	row.add_child(pad)
	var av := ScreenKit.avatar(int(o.get("at", 0)), str(o.get("name", "?")), "bot", 48.0)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(av)
	var l := ScreenKit.label(I18n.t("%s (Computer) · Kommt nach diesem Zug dazu") % str(o.get("name", "")), "", UiFonts.size("text"))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var undo := ScreenKit.button("Zurücknehmen", "GhostButton")
	undo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	undo.pressed.connect(func() -> void:
		host.cancel_seat_op(-1)
		refresh(true))
	row.add_child(undo)
	return row


func _row_button(tex: Texture2D, tip: String) -> Button:
	var b := ScreenKit.icon_button(tex, "GhostButton", tip)
	b.custom_minimum_size = Vector2(ROW_H, ROW_H - 6.0)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


# ---------------------------------------------------------------- Aufträge (immer mit Rückfrage)

# Neuer Computergegner: Platzhalter am Ende der Liste, wird wie ein Wartender an seinen Platz gerückt
func add_bot_slot() -> void:
	if not _room_left():
		return
	_bots.append(_next_bot)
	_order.append(_next_bot)
	_next_bot -= 1
	show_page("tisch")
	refresh(true)
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


static func not_now_text() -> String:
	return " " + I18n.t("Das passiert nach diesem Zug.")


func ask_seat(id: int) -> void:
	if host == null or host.game == null:
		return
	var bot_slot := _is_bot_slot(id)
	var who := I18n.t("Ein Computergegner") if bot_slot else str(host.session.player(id).get("name", "?"))
	var nb := neighbours(id)
	var k := host.join_card_count()
	var text := ""
	if k <= 0:
		text = I18n.t("%s setzt sich zwischen %s und %s und bekommt die Karten mit der nächsten Runde.") % [who, nb[0], nb[1]]
	elif k == 1:
		text = I18n.t("%s setzt sich zwischen %s und %s und bekommt 1 Karte.") % [who, nb[0], nb[1]]
	else:
		text = I18n.t("%s setzt sich zwischen %s und %s und bekommt %d Karten.") % [who, nb[0], nb[1], k]
	if not host.game.can_change_seats():
		text += not_now_text()
	var title := I18n.t("Computergegner dazuholen?") if bot_slot else I18n.t("%s an den Tisch holen?") % who
	_ask(title, text, "Dazuholen", func() -> void:
		var ok := false
		var at := place_of(id)
		if bot_slot:
			ok = host.add_bot_at(at)
			if ok:
				_bots.erase(id)
				_order.erase(id)
		else:
			ok = host.seat_in(id, at)
		if not ok:
			_toast(I18n.t("Am Tisch ist kein Platz mehr."))
		refresh(true))


func ask_reject(id: int) -> void:
	if _is_bot_slot(id):
		_bots.erase(id)
		_order.erase(id)
		refresh(true)
		return
	var who := str(host.session.player(id).get("name", "?"))
	_ask(I18n.t("%s nicht dazuholen?") % who, I18n.t("%s bekommt Bescheid und kann es später noch einmal versuchen.") % who, "Ablehnen",
		func() -> void:
			host.reject_waiting(id)
			refresh(true))


func ask_remove_seat(seat: int) -> void:
	if _confirm != null and is_instance_valid(_confirm):
		_confirm.queue_free()
	_confirm = SeatManager.ask_remove(self, host, seat, func() -> void: refresh(true))
	if _confirm != null:
		_confirm.answered.connect(func(_y: bool) -> void: _confirm = null)


func _ask(title: String, text: String, yes: String, on_yes: Callable) -> void:
	if _confirm != null and is_instance_valid(_confirm):
		_confirm.queue_free()
	_confirm = ConfirmBox.ask(self, title, text, yes, "Abbrechen")
	_confirm.answered.connect(func(y: bool) -> void:
		_confirm = null
		if y:
			on_yes.call())


func _toast(text: String) -> void:
	var tv := get_tree().get_first_node_in_group(TableView.GROUP) as TableView
	if tv != null:
		tv.show_notice(text, "warn")


# Rückfrage „%s aus dem Spiel nehmen?“ (Feld „Mitspieler“ und Sofort-Leiste am Tisch). Bei „Herausnehmen“ HostTable.remove_seat
# (wartet bis nach dem Zug, außer der Platz ist am Zug), danach done. null, wenn der Platz nicht herausgenommen werden kann.
static func ask_remove(parent: Node, host_table: HostTable, seat: int, done := Callable()) -> ConfirmBox:
	if host_table == null or host_table.game == null or seat < 0 or seat >= host_table.seats.size() or seat == host_table.host_seat:
		return null
	var who := host_table.seat_name(seat)
	var text := I18n.t("%s scheidet aus. Seine Karten kommen unter den Ziehstapel.") % who
	if not host_table.is_bot(seat):
		text += " " + I18n.t("Über „Mitspieler dazuholen“ kann er später neu einsteigen.")
	if host_table.seats.size() <= 2:
		text += " " + I18n.t("Dann bleibt nur ein Spieler übrig – die Partie endet.")
	elif not host_table.game.can_remove_now(seat):
		text += not_now_text()
	var box := ConfirmBox.ask(parent, I18n.t("%s aus dem Spiel nehmen?") % who, text, "Herausnehmen", "Abbrechen")
	box.answered.connect(func(yes: bool) -> void:
		if yes and is_instance_valid(host_table) and seat < host_table.seats.size() and host_table.seat_name(seat) == who:
			host_table.remove_seat(seat)
		if done.is_valid():
			done.call())
	return box


# Sprache gewechselt: Liste neu
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _list != null:
		refresh.call_deferred(true)
