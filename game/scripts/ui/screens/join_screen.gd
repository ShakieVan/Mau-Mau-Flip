class_name JoinScreen
extends AppScreen
# Beitreten (ClientTable, Modul G): oben das Adressfeld (die Bildschirmtastatur deckt im Querformat die untere Hälfte),
# darunter die im WLAN gefundenen Spiele (NetDiscovery) mit Name und Spielerzahl. Nach dem Verbinden zeigt dieselbe Seite die
# Lobby des Gastgebers (Spieler, Regeln, „Warte auf den Gastgeber …“); beginnt die Partie, kommt der Tisch.

var client: ClientTable
var discovery: NetDiscovery
var _address: LineEdit
var _connect_btn: Button
var _status: Label
var _games: VBoxContainer
var _search_box: Control
var _lobby_box: Control
var _lobby_list: VBoxContainer
var _lobby_rules: Label
var _ready_btn: Button
var _started := false


func build() -> void:
	var content := page("Beitreten")
	var top := ScreenKit.hbox(14)
	content.add_child(top)
	_address = LineEdit.new()
	_address.name = "Adresse"
	_address.placeholder_text = "Adresse des Gastgebers, z. B. 192.168.178.8"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.custom_minimum_size = Vector2(0, ScreenKit.TOUCH)
	_address.text = str(UiApp.setting("letzte_adresse", ""))
	_address.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	_address.text_submitted.connect(func(_t: String) -> void: _connect_typed())
	top.add_child(_address)
	_connect_btn = ScreenKit.button("Verbinden", "PrimaryButton", "start")
	_connect_btn.name = "Verbinden"
	_connect_btn.pressed.connect(_connect_typed)
	top.add_child(_connect_btn)
	_status = ScreenKit.label("Suche Spiele im WLAN …", "HintLabel", 21)
	_status.name = "Status"
	content.add_child(_status)
	# Suche
	var search := ScreenKit.card(24.0)
	search.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_search_box = search
	content.add_child(search)
	var sv := ScreenKit.vbox(10)
	search.add_child(sv)
	sv.add_child(ScreenKit.heading("Gefundene Spiele", 28))
	var scroll := ScreenKit.scroller()
	sv.add_child(scroll)
	_games = ScreenKit.vbox(10)
	_games.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_games)
	# Lobby nach dem Verbinden
	var lobby := ScreenKit.card(24.0)
	lobby.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lobby.visible = false
	_lobby_box = lobby
	content.add_child(lobby)
	var lv := ScreenKit.hbox(26)
	lobby.add_child(lv)
	var lleft := ScreenKit.vbox(8)
	lleft.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_child(lleft)
	lleft.add_child(ScreenKit.heading("Am Tisch", 28))
	var lscroll := ScreenKit.scroller()
	lleft.add_child(lscroll)
	_lobby_list = ScreenKit.vbox(6)
	_lobby_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lscroll.add_child(_lobby_list)
	var lright := ScreenKit.vbox(14)
	lright.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_child(lright)
	lright.add_child(ScreenKit.heading("Regeln dieser Partie", 28))
	_lobby_rules = ScreenKit.text_block("", 20)
	lright.add_child(_lobby_rules)
	lright.add_child(ScreenKit.spacer(false))
	lright.add_child(ScreenKit.hint("Der Gastgeber legt die Sitzordnung fest und startet die Partie.", 19))
	_ready_btn = ScreenKit.button("Bereit", "PrimaryButton", "haken")
	_ready_btn.name = "Bereit"
	_ready_btn.toggle_mode = true
	_ready_btn.icon = ScreenKit.glyph("haken", 40)
	_ready_btn.toggled.connect(func(on: bool) -> void:
		if client != null:
			client.set_ready(on)
		_ready_btn.text = "Bereit ✓" if on else "Bereit")
	lright.add_child(_ready_btn)
	_start_search()
	_refresh_games()


func _start_search() -> void:
	if discovery != null:
		return
	discovery = NetDiscovery.new()
	discovery.name = "Suche"
	add_child(discovery)
	discovery.games_changed.connect(_refresh_games)
	if discovery.start_search() != OK:
		_status.text = "Suche nicht möglich – Adresse oben eingeben."


func _stop_search() -> void:
	if discovery != null and is_instance_valid(discovery):
		discovery.stop()
		discovery.queue_free()
	discovery = null


func _refresh_games() -> void:
	if _games == null or client != null:
		return
	for c in _games.get_children():
		_games.remove_child(c)
		c.queue_free()
	var list: Array = discovery.games_list() if discovery != null else []
	if list.is_empty():
		_games.add_child(ScreenKit.hint("Noch nichts gefunden. Der Gastgeber tippt auf „Spiel eröffnen“; beide Geräte im selben WLAN. Klappt die Suche nicht, die Adresse unter dem QR-Code des Gastgebers oben eintippen.", 20))
		return
	_status.text = "%d %s gefunden – antippen zum Beitreten." % [list.size(), "Spiel" if list.size() == 1 else "Spiele"]
	for g in list:
		_games.add_child(_game_button(g))


func _game_button(g: Dictionary) -> Control:
	var b := ScreenKit.button("", "" if bool(g.get("compatible", true)) else "GhostButton")
	b.custom_minimum_size = Vector2(0, 96)
	var inner := ScreenKit.hbox(18)
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 26
	inner.offset_right = -26
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(inner)
	var name_text := str(g.get("name", "?"))
	inner.add_child(ScreenKit.avatar(0, name_text, "human", 56.0))
	var texts := ScreenKit.vbox(0)
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(texts)
	var t := ScreenKit.label("Spiel von %s" % name_text, "", 28)
	t.add_theme_font_override("font", UiFonts.title(800, false, 50.0, 48.0))
	texts.add_child(t)
	var detail := "%d %s · %s" % [int(g.get("players", 0)), "Spieler", str(g.get("address", ""))]
	if bool(g.get("running", false)):
		detail += " · Partie läuft"
	if not bool(g.get("compatible", true)):
		detail += " · andere Version (%s)" % str(g.get("version", "?"))
	texts.add_child(ScreenKit.label(detail, "HintLabel", 19))
	var addr := str(g.get("address", ""))
	var port := int(g.get("port", NetProtocol.PORT))
	b.pressed.connect(func() -> void: join(addr, port))
	return b


# Eingetippte Adresse: „192.168.1.5“, „192.168.1.5:24690“ oder „http://192.168.1.5:24690/“
static func parse_address(text: String) -> Dictionary:
	var t := text.strip_edges().trim_prefix("http://").trim_prefix("https://")
	var slash := t.find("/")
	if slash >= 0:
		t = t.substr(0, slash)
	var port := NetProtocol.PORT
	var colon := t.rfind(":")
	if colon > 0 and t.substr(colon + 1).is_valid_int():
		port = int(t.substr(colon + 1))
		t = t.substr(0, colon)
	if t == "":
		return {}
	return {"address": t, "port": port}


func _connect_typed() -> void:
	_address.release_focus()
	var a := parse_address(_address.text)
	if a.is_empty():
		toast("Bitte die Adresse des Gastgebers eingeben.")
		return
	var app := UiApp.app()
	if app != null:
		app.settings.set_value("letzte_adresse", _address.text.strip_edges())
	join(str(a.address), int(a.port))


func join(address: String, port: int) -> void:
	if client != null:
		client.leave()
		client.queue_free()
	client = GameStarter.client()
	add_child(client)
	client.connection_changed.connect(_on_connection)
	client.lobby_changed.connect(_on_lobby)
	client.game_started.connect(_on_started)
	client.notice.connect(func(t: String) -> void: _status.text = t)
	_status.text = "Verbinde mit %s …" % address
	var who := str(UiApp.setting("name", ""))
	if client.join(address, port, who) != OK:
		_status.text = "Verbindung nicht möglich."
		_back_to_search()


func _on_connection(state: String) -> void:
	match state:
		"open":
			_status.text = "Verbunden. Warte auf den Gastgeber …"
			_search_box.visible = false
			_lobby_box.visible = true
			_stop_search()
		"connecting":
			_status.text = "Verbinde …"
		"rejected", "closed":
			if not _started:
				_back_to_search()


func _back_to_search() -> void:
	if client != null:
		var c := client
		client = null
		c.leave()
		c.queue_free()
	_lobby_box.visible = false
	_search_box.visible = true
	_ready_btn.set_pressed_no_signal(false)
	_start_search()
	_refresh_games()


func _on_lobby(l: Dictionary) -> void:
	for c in _lobby_list.get_children():
		_lobby_list.remove_child(c)
		c.queue_free()
	var players: Array = (l.get("players", []) as Array).duplicate()
	players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("seat", 0)) < int(b.get("seat", 0)))
	var me := client.my_id if client != null else -1
	for i in players.size():
		var p: Dictionary = players[i]
		var row := ScreenKit.hbox(12)
		row.custom_minimum_size = Vector2(0, 60)
		var kind := str(p.get("kind", "app"))
		var av := ScreenKit.avatar(i, str(p.get("name", "?")), "bot" if kind == "bot" else "human", 46.0)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(av)
		var n := ScreenKit.label(str(p.get("name", "")) + ("  (du)" if int(p.get("id", -2)) == me else ""), "", 23)
		n.add_theme_font_override("font", UiFonts.text(700))
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		var tag: String = {"app": "App", "web": "Browser", "bot": "Computer"}.get(kind, kind)
		if int(p.get("id", -1)) == int(l.get("host_id", -2)):
			tag = "Gastgeber"
		if not bool(p.get("connected", true)):
			tag += " · getrennt"
		elif bool(p.get("ready", false)):
			tag += " · bereit"
		var tl := ScreenKit.label(tag, "HintLabel", 18)
		tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tl)
		_lobby_list.add_child(row)
	var rules: Variant = l.get("rules", {})
	var cfg := RuleConfig.from_dict(rules if rules is Dictionary else {})
	_lobby_rules.text = "\n".join(PackedStringArray(cfg.describe()))


func _on_started(_seat: int) -> void:
	if _started or client == null:
		return
	_started = true
	_stop_search()
	nav.replace(TableScreen.create(client))


func on_back() -> bool:
	if client != null:
		_back_to_search()
		return true
	return false


func on_leave() -> void:
	if nav != null and not nav.stack.has(self):
		_stop_search()
		if client != null and not _started:
			client.leave()
