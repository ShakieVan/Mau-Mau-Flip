class_name HostLobbyScreen
extends AppScreen
# Spiel eröffnen (HostTable, Modul G): links großer QR-Code mit http://<ip>:<port>/ und Adresse als Text samt Hinweisen
# (Warnseite → „Weiter“, iPhone: Safari, Hotel-WLAN → Hotspot), rechts die Spielerliste in Sitzordnung (Pfeile ändern sie),
# App/Browser/Computer-Kennung, verbunden-Status, Computergegner + / −, Regeln, Start ab 2 Spielern.

var host: HostTable
var lobby: Dictionary = {}
var _qr: TextureRect
var _url: Label
var _more: Label
var _list: VBoxContainer
var _start: Button
var _count: Label
var _rules: RulesBar
var _bot_minus: Button
var _bot_plus: Button
var _started := false


func build() -> void:
	host = GameStarter.host()
	add_child(host)
	var who := str(UiApp.setting("name", ""))
	var err := host.open(who)
	host.lobby_changed.connect(_on_lobby)
	host.notice.connect(func(t: String) -> void: toast(t))
	var content := page("Spiel eröffnen")
	var cols := ScreenKit.hbox(26)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cols)
	# --- links: QR-Code und Hinweise
	var left := ScreenKit.card(24.0)
	left.custom_minimum_size = Vector2(520, 0)
	cols.add_child(left)
	var lv := ScreenKit.vbox(10)
	left.add_child(lv)
	var qrow := ScreenKit.hbox(20)
	lv.add_child(qrow)
	_qr = TextureRect.new()
	_qr.name = "QR"
	_qr.custom_minimum_size = Vector2(250, 250)
	_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	qrow.add_child(_qr)
	var qtext := ScreenKit.vbox(6)
	qtext.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qrow.add_child(qtext)
	qtext.add_child(ScreenKit.heading("Ohne App mitspielen", 26))
	qtext.add_child(ScreenKit.hint("QR-Code mit der Kamera scannen oder die Adresse im Browser eintippen:", 18))
	_url = ScreenKit.label("", "", 25)
	_url.name = "Adresse"
	_url.add_theme_font_override("font", UiFonts.text(800, 90.0))
	_url.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	qtext.add_child(_url)
	_more = ScreenKit.hint("", 16)
	qtext.add_child(_more)
	lv.add_child(ScreenKit.hint("• Mit App: „Im WLAN spielen“ → „Beitreten“, das Spiel erscheint von selbst.", 18))
	lv.add_child(ScreenKit.hint("• Warnseite „nicht sicher“? Das ist normal im eigenen WLAN: „Weiter“ bzw. „Trotzdem öffnen“.", 18))
	lv.add_child(ScreenKit.hint("• iPhone: am besten mit Safari öffnen.", 18))
	lv.add_child(ScreenKit.hint("• Hotel- oder Gäste-WLAN sieht sich oft nicht gegenseitig: dann einen Hotspot an diesem Handy öffnen und die anderen damit verbinden.", 18))
	# --- rechts: Spieler, Regeln, Start
	var right := ScreenKit.card(24.0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var rv := ScreenKit.vbox(10)
	right.add_child(rv)
	var head := ScreenKit.hbox(12)
	rv.add_child(head)
	head.add_child(ScreenKit.heading("Spieler", 30))
	_count = ScreenKit.label("", "HintLabel", 19)
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_count)
	head.add_child(ScreenKit.spacer())
	_bot_minus = ScreenKit.button("−", "GhostButton", "", ScreenKit.TOUCH)
	_bot_minus.name = "MinusComputer"
	_bot_minus.pressed.connect(_remove_bot)
	head.add_child(_bot_minus)
	var bl := ScreenKit.label("Computer", "", 20)
	bl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(bl)
	_bot_plus = ScreenKit.button("+", "GhostButton", "roboter", ScreenKit.TOUCH)
	_bot_plus.name = "PlusComputer"
	_bot_plus.pressed.connect(func() -> void: host.add_bot())
	head.add_child(_bot_plus)
	var scroll := ScreenKit.scroller()
	rv.add_child(scroll)
	_list = ScreenKit.vbox(6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var bottom := ScreenKit.hbox(14)
	rv.add_child(bottom)
	_rules = RulesBar.new()
	_rules.nav = nav
	_rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rules.changed.connect(func(cfg: RuleConfig) -> void: host.set_rules(cfg))
	bottom.add_child(_rules)
	_start = ScreenKit.button("Start", "PrimaryButton", "start", 200.0)
	_start.name = "Start"
	_start.custom_minimum_size = Vector2(220, 110)
	_start.add_theme_font_size_override("font_size", 30)
	_start.size_flags_vertical = Control.SIZE_SHRINK_END
	_start.pressed.connect(start_game)
	bottom.add_child(_start)
	_show_address(err)
	_on_lobby(host.lobby())


func on_enter() -> void:
	if _rules != null:
		_rules.nav = nav
		_rules.refresh()


func _show_address(err: Error) -> void:
	var urls := host.host_urls() if err == OK else ([] as Array[String])
	if err != OK:
		_url.text = "Kein freier Port – bitte die App neu starten."
		_qr.texture = null
		return
	if urls.is_empty():
		_url.text = "Kein WLAN gefunden"
		_more.text = "Mit einem WLAN verbinden oder einen Hotspot öffnen, dann diese Seite neu öffnen."
		_qr.texture = null
		return
	_url.text = urls[0].trim_prefix("http://").trim_suffix("/")
	_more.text = ("Auch: " + ", ".join(PackedStringArray(urls.slice(1).map(func(u: String) -> String: return u.trim_prefix("http://").trim_suffix("/"))))) if urls.size() > 1 else ""
	var qr := QrCode.encode(urls[0])
	if qr != null:
		_qr.texture = qr.to_texture(8, 3, UiPalette.INK, Color.WHITE)


func _on_lobby(l: Dictionary) -> void:
	lobby = l
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var players: Array = (l.get("players", []) as Array).duplicate()
	players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("seat", 0)) < int(b.get("seat", 0)))
	var host_id := int(l.get("host_id", -1))
	var bots := 0
	for i in players.size():
		var p: Dictionary = players[i]
		if str(p.get("kind", "")) == "bot":
			bots += 1
		_list.add_child(_row(p, i, players.size(), host_id))
	_count.text = "%d von 10" % players.size()
	_start.disabled = players.size() < 2
	_bot_minus.disabled = bots == 0
	_bot_plus.disabled = players.size() >= NetProtocol.MAX_PLAYERS


func _row(p: Dictionary, i: int, n: int, host_id: int) -> Control:
	var row := ScreenKit.hbox(10)
	row.custom_minimum_size = Vector2(0, 72)
	var id := int(p.get("id", -1))
	var kind := str(p.get("kind", "app"))
	var no := ScreenKit.label(str(i + 1), "", 22, Color(UiPalette.INK, 0.55))
	no.custom_minimum_size = Vector2(26, 0)
	no.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(no)
	var av := ScreenKit.avatar(i, str(p.get("name", "?")), "bot" if kind == "bot" else "human", 48.0)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(av)
	var texts := ScreenKit.vbox(0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(texts)
	var nl := ScreenKit.label(str(p.get("name", "")), "", 24)
	nl.add_theme_font_override("font", UiFonts.text(700))
	texts.add_child(nl)
	var tag: String = {"app": "App", "web": "Browser", "bot": "Computer"}.get(kind, kind)
	if id == host_id:
		tag = "Gastgeber (du)"
	var connected := bool(p.get("connected", true))
	if not connected:
		tag += " · getrennt"
	elif kind != "bot" and id != host_id:
		tag += " · verbunden" + (" · bereit" if bool(p.get("ready", false)) else "")
	var tl := ScreenKit.label(tag, "HintLabel", 17)
	if not connected:
		tl.add_theme_color_override("font_color", UiPalette.ALERT)
	texts.add_child(tl)
	var ic := TextureRect.new()
	ic.texture = ScreenKit.icon({"app": "spieler", "web": "wlan", "bot": "roboter"}.get(kind, "spieler"))
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(34, 34)
	ic.modulate = Color(UiPalette.INK, 0.6)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var up := ScreenKit.icon_button(ScreenKit.glyph("pfeil", 36, -90), "GhostButton", "nach vorn")
	up.disabled = i == 0
	up.pressed.connect(_move.bind(id, -1))
	row.add_child(up)
	var down := ScreenKit.icon_button(ScreenKit.glyph("pfeil", 36, 90), "GhostButton", "nach hinten")
	down.disabled = i == n - 1
	down.pressed.connect(_move.bind(id, 1))
	row.add_child(down)
	var rm := ScreenKit.icon_button(ScreenKit.glyph("kreuz", 32), "GhostButton", "entfernen")
	rm.disabled = id == host_id
	rm.pressed.connect(func() -> void: host.remove_player(id))
	row.add_child(rm)
	return row


func _ordered_ids() -> Array:
	var players: Array = (lobby.get("players", []) as Array).duplicate()
	players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("seat", 0)) < int(b.get("seat", 0)))
	return players.map(func(p: Dictionary) -> int: return int(p.get("id", -1)))


func _move(id: int, d: int) -> void:
	var ids := _ordered_ids()
	var i := ids.find(id)
	var j := i + d
	if i < 0 or j < 0 or j >= ids.size():
		return
	ids[i] = ids[j]
	ids[j] = id
	host.set_seat_order(ids)


func _remove_bot() -> void:
	var players: Array = lobby.get("players", [])
	for k in range(players.size() - 1, -1, -1):
		var p: Dictionary = players[k]
		if str(p.get("kind", "")) == "bot":
			host.remove_player(int(p.get("id", -1)))
			return


func start_game() -> void:
	if (lobby.get("players", []) as Array).size() < 2:
		toast("Es braucht mindestens zwei Spieler – Computergegner gehen auch.")
		return
	_started = true
	host.set_rules(RulesBar.current())
	nav.replace(TableScreen.create(host, func() -> void:
		if not host.start():
			toast("Start nicht möglich.")))


func on_back() -> bool:
	var guests := 0
	for p in lobby.get("players", []):
		if str(p.get("kind", "")) != "bot" and int(p.get("id", -1)) != int(lobby.get("host_id", -1)):
			guests += 1
	if guests == 0:
		return false
	var box := ConfirmBox.ask(self, "Lobby schließen?", "%d Mitspieler sind verbunden und werden getrennt." % guests, "Schließen", "Bleiben")
	box.answered.connect(func(yes: bool) -> void:
		if yes:
			host.leave()
			nav.pop())
	return true


func on_leave() -> void:
	if not _started and host != null and is_instance_valid(host) and host.get_parent() == self and nav != null and not nav.stack.has(self):
		host.leave()
