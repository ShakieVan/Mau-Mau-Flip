class_name HostLobbyScreen
extends AppScreen
# Spiel eröffnen (HostTable, Modul G; Beta 1.0.2 für Menschen ohne Technikhintergrund): Kopfzeile „So geht's“ (HostHelpDialog),
# „Regeln“ (Regel-Editor) und „Start“ – Start ist immer zu sehen und ab 2 Spielern aktiv. Darunter ein seitlich blätterbarer
# Bereich mit Einrasten (LobbyPager): links „Mitspieler einladen“ mit ① WLAN und ② Spiel (InvitePanel), rechts die Spielerliste
# in Sitzordnung (Pfeile ändern sie) mit App/Browser/Computer-Kennung und verbunden-Status, darunter Regelzeile, Spielerzahl und
# Computergegner − / +. Die jeweils andere Seite ragt ins Bild. 1600 × 720: fünf Spieler ganz sichtbar, darüber per Wischen.
# Nach „+“ oder einem Pfeil rollt die Liste zum betroffenen Spieler.

const ROW_H := 72.0

var host: HostTable
var lobby: Dictionary = {}
var pager: LobbyPager
var invite: InvitePanel
var _scroll: ScrollContainer
var _list: VBoxContainer
var _start: Button
var _help_btn: Button
var _rules_btn: Button
var _count: Label
var _rules: RulesBar
var _bot_minus: Button
var _bot_plus: Button
var _confirm: ConfirmBox
var _help: HostHelpDialog
var _started := false
var _focus_id := -1                 # Spieler, zu dem die Liste nach dem nächsten Neuaufbau rollt
var _focus_last := false            # … bzw. zum letzten (neuer Computergegner)


func build() -> void:
	host = GameStarter.host()
	add_child(host)
	var who := str(UiApp.setting("name", ""))
	var err := host.open(who)
	host.lobby_changed.connect(_on_lobby)
	host.notice.connect(func(t: String) -> void: toast(t))
	if err != OK:
		toast("Kein freier Port – bitte die App neu starten.")
	# Kopfzeile: So geht's, Regeln, Start
	var tools := ScreenKit.hbox(12)
	_help_btn = ScreenKit.button("So geht's", "GhostButton", "hilfe")
	_help_btn.name = "SoGehts"
	_help_btn.pressed.connect(open_help)
	tools.add_child(_help_btn)
	_rules_btn = ScreenKit.button("Regeln", "GhostButton", "regeln")
	_rules_btn.name = "Regeln"
	_rules_btn.tooltip_text = "Regeln ansehen und anpassen"
	tools.add_child(_rules_btn)
	_start = ScreenKit.button("Start", "PrimaryButton", "start", 200.0)
	_start.name = "Start"
	_start.add_theme_font_size_override("font_size", UiFonts.size("start"))
	_start.pressed.connect(start_game)
	tools.add_child(_start)
	var content := page("Spiel eröffnen", true, tools)
	pager = LobbyPager.new()
	pager.blocked = func() -> bool: return _dialog_open() or (nav != null and nav.top() != self)
	content.add_child(pager)
	# --- Seite 1: Einladen
	invite = InvitePanel.new()
	pager.add_page(invite)
	invite.setup(host, err != OK)
	# --- Seite 2: Spieler (Bildlauf), darunter Regeln, Spielerzahl und Computergegner
	var right := ScreenKit.card(24.0)
	right.name = "Mitspieler"
	pager.add_page(right)
	var rv := ScreenKit.vbox(10)
	right.add_child(rv)
	_scroll = ScreenKit.scroller()
	_scroll.name = "Spielerliste"
	rv.add_child(_scroll)
	_list = ScreenKit.vbox(4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	var line := ColorRect.new()
	line.color = Color(UiPalette.INK, 0.12)
	line.custom_minimum_size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rv.add_child(line)
	var bottom := ScreenKit.hbox(12)
	rv.add_child(bottom)
	_rules = RulesBar.new()
	_rules.compact = true
	_rules.nav = nav
	_rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rules.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rules.changed.connect(func(cfg: RuleConfig) -> void: host.set_rules(cfg))
	bottom.add_child(_rules)
	_rules._edit.visible = false                 # „Regeln“ steht oben in der Kopfzeile
	_rules_btn.pressed.connect(func() -> void:
		_rules.nav = nav
		_rules._open_editor())
	_count = ScreenKit.label("", "HintLabel", UiFonts.size("text"))
	_count.name = "Spielerzahl"
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_count)
	_bot_minus = ScreenKit.button("−", "GhostButton", "", ScreenKit.TOUCH)
	_bot_minus.name = "MinusComputer"
	_bot_minus.tooltip_text = "Computergegner entfernen"
	_bot_minus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bot_minus.pressed.connect(_remove_bot)
	bottom.add_child(_bot_minus)
	var bl := ScreenKit.label("Computer", "", UiFonts.size("text"))
	bl.add_theme_font_override("font", UiFonts.text(700))
	bl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(bl)
	_bot_plus = ScreenKit.button("+", "GhostButton", "roboter", ScreenKit.TOUCH)
	_bot_plus.name = "PlusComputer"
	_bot_plus.tooltip_text = "Computergegner hinzufügen"
	_bot_plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bot_plus.pressed.connect(func() -> void:
		_focus_last = true
		host.add_bot())
	bottom.add_child(_bot_plus)
	_on_lobby(host.lobby())


func on_enter() -> void:
	if _rules != null:
		_rules.nav = nav
		_rules.refresh()


func show_page(i: int, animate := true) -> void:
	if pager != null:
		pager.show_page(i, animate)


func open_help() -> void:
	if _help != null and is_instance_valid(_help):
		return
	_help = HostHelpDialog.open(self)
	_help.closed.connect(func() -> void: _help = null)


func _dialog_open() -> bool:
	return (_help != null and is_instance_valid(_help)) or (_confirm != null and is_instance_valid(_confirm))


# Mitspieler ohne Gastgeber und Computergegner
static func guest_count(l: Dictionary) -> int:
	var n := 0
	for p in l.get("players", []):
		if str(p.get("kind", "")) != "bot" and int(p.get("id", -1)) != int(l.get("host_id", -1)):
			n += 1
	return n


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
	var focus: Control = null
	for i in players.size():
		var p: Dictionary = players[i]
		if str(p.get("kind", "")) == "bot":
			bots += 1
		var row := _row(p, i, players.size(), host_id)
		_list.add_child(row)
		if int(p.get("id", -1)) == _focus_id or (_focus_last and i == players.size() - 1):
			focus = row
	_focus_id = -1
	_focus_last = false
	if focus != null:
		_scroll_to.call_deferred(focus)
	_count.text = "%d von %d Spielern" % [players.size(), NetProtocol.MAX_PLAYERS]
	_start.disabled = players.size() < 2
	_bot_minus.disabled = bots == 0
	_bot_plus.disabled = players.size() >= NetProtocol.MAX_PLAYERS
	if invite != null:
		invite.set_guests(guest_count(l))


# Zeile ganz in den sichtbaren Bereich holen (nach dem Layout)
func _scroll_to(row: Control) -> void:
	if is_instance_valid(row) and row.is_inside_tree() and _scroll != null:
		await get_tree().process_frame
		if is_instance_valid(row) and row.is_inside_tree():
			_scroll.ensure_control_visible(row)


func _row(p: Dictionary, i: int, n: int, host_id: int) -> Control:
	var row := ScreenKit.hbox(10)
	row.custom_minimum_size = Vector2(0, ROW_H)
	var id := int(p.get("id", -1))
	row.name = "Spieler%d" % id
	var kind := str(p.get("kind", "app"))
	var no := ScreenKit.label(str(i + 1), "", UiFonts.size("text"), Color(UiPalette.INK, 0.72))
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
	var nl := ScreenKit.label(str(p.get("name", "")), "", UiFonts.size("zeile"))
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
	var tl := ScreenKit.label(tag, "HintLabel", UiFonts.size("klein"))
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
	var up := _row_button(ScreenKit.glyph("pfeil", 34, -90), "nach vorn")
	up.disabled = i == 0
	up.pressed.connect(_move.bind(id, -1))
	row.add_child(up)
	var down := _row_button(ScreenKit.glyph("pfeil", 34, 90), "nach hinten")
	down.disabled = i == n - 1
	down.pressed.connect(_move.bind(id, 1))
	row.add_child(down)
	var rm := _row_button(ScreenKit.glyph("kreuz", 30), "entfernen")
	rm.disabled = id == host_id
	rm.pressed.connect(func() -> void: host.remove_player(id))
	row.add_child(rm)
	return row


# Symbolknopf einer Spielerzeile (etwas flacher als die übrigen Knöpfe, damit fünf Zeilen ganz sichtbar sind)
func _row_button(tex: Texture2D, tip: String) -> Button:
	var b := ScreenKit.icon_button(tex, "GhostButton", tip)
	var th := UiTheme.get_theme()
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		if th.has_stylebox(st, "GhostButton"):
			var sb := th.get_stylebox(st, "GhostButton").duplicate() as StyleBox
			sb.content_margin_top = 6.0
			sb.content_margin_bottom = 6.0
			b.add_theme_stylebox_override(st, sb)
	b.custom_minimum_size = Vector2(ROW_H + 4.0, ROW_H)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


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
	_focus_id = id
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
	if _help != null and is_instance_valid(_help):
		_help.close()               # „So geht's“ schließen
		_help = null
		return true
	if _confirm != null and is_instance_valid(_confirm):
		_confirm.cancel()            # offene Rückfrage: Zurück heißt „Bleiben“
		_confirm = null
		return true
	var guests := guest_count(lobby)
	if guests == 0:
		return false
	_confirm = ConfirmBox.ask(self, "Lobby schließen?", close_text(guests), "Schließen", "Bleiben")
	_confirm.answered.connect(func(yes: bool) -> void:
		_confirm = null
		if yes:
			host.leave()
			nav.pop())
	return true


# Text der Rückfrage „Lobby schließen?“ (Einzahl und Mehrzahl; Nachtest 1: „1 Mitspieler sind …“)
static func close_text(guests: int) -> String:
	if guests == 1:
		return "1 Mitspieler ist verbunden und wird getrennt."
	return "%d Mitspieler sind verbunden und werden getrennt." % guests


func on_leave() -> void:
	if not _started and host != null and is_instance_valid(host) and host.get_parent() == self and nav != null and not nav.stack.has(self):
		host.leave()
