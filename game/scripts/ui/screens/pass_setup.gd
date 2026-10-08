class_name PassSetupScreen
extends AppScreen
# „Auf einem Handy“ (Weitergeben) einrichten: Namen in Sitzordnung (2–10 Plätze, + / −, Reihenfolge mit Pfeilen),
# Computergegner dazu, Regeln, Start. Die letzten Namen bleiben gemerkt (App.settings "letzte_namen").
# Eingabefelder rücken beim Antippen nach oben, damit die Bildschirmtastatur sie nicht verdeckt.

const MAX := 10

var entries: Array = []             # [{name, kind}] in Sitzordnung
var _list: VBoxContainer
var _scroll: ScrollContainer
var _add_human: Button
var _add_bot: Button
var _count: Label
var _rules: RulesBar
var _bot_no := 0


func build() -> void:
	var recent: Variant = UiApp.setting("letzte_namen", [])
	var names: Array = recent if recent is Array else []
	for i in range(mini(names.size(), 4)):
		entries.append({"name": str(names[i]), "kind": "human"})
	while entries.size() < 2:
		entries.append({"name": "", "kind": "human"})
	var content := page("Auf einem Handy")
	var cols := ScreenKit.hbox(28)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cols)
	var left := ScreenKit.card(24.0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.35
	cols.add_child(left)
	var lv := ScreenKit.vbox(12)
	left.add_child(lv)
	var head := ScreenKit.hbox(14)
	lv.add_child(head)
	head.add_child(ScreenKit.heading("Mitspieler"))
	_count = ScreenKit.label("", "HintLabel", UiFonts.size("text"))
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_count)
	# Hinweis im Bildlauf über der Liste: bei großer Schrift und offener Tastatur bleibt Platz für die Namensfelder
	_scroll = ScreenKit.scroller()
	lv.add_child(_scroll)
	var inner := ScreenKit.vbox(10)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(inner)
	inner.add_child(ScreenKit.hint("Tragt euch so ein, wie ihr sitzt – links herum: Nach Platz 1 kommt, wer links daneben sitzt.", UiFonts.size("hinweis")))
	_list = ScreenKit.vbox(10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(_list)
	var add_row := ScreenKit.hbox(12)
	lv.add_child(add_row)
	_add_human = ScreenKit.button("+ Mitspieler", "", "spieler")
	_add_human.name = "PlusMensch"
	_add_human.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_human.pressed.connect(func() -> void: _add("human"))
	add_row.add_child(_add_human)
	_add_bot = ScreenKit.button("+ Computergegner", "", "roboter")
	_add_bot.name = "PlusComputer"
	_add_bot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_bot.pressed.connect(func() -> void: _add("bot"))
	add_row.add_child(_add_bot)
	var right := ScreenKit.card(24.0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var rv := ScreenKit.vbox(16)
	right.add_child(rv)
	# Regeln und Hinweis im Bildlauf (große Schrift: lieber blättern als abschneiden), Start immer sichtbar darunter
	var rscroll := ScreenKit.scroller()
	rv.add_child(rscroll)
	var rinner := ScreenKit.vbox(16)
	rinner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rscroll.add_child(rinner)
	_rules = RulesBar.new()
	_rules.nav = nav
	rinner.add_child(_rules)
	rinner.add_child(ScreenKit.hint("Vor jedem Zug erscheint ein Sichtschutz ohne Karten. Erst wer dran ist, deckt durch Halten auf.", UiFonts.size("hinweis")))
	var start := ScreenKit.button("Los geht's", "PrimaryButton", "start")
	start.name = "Start"
	start.custom_minimum_size = Vector2(0, 100)
	start.add_theme_font_size_override("font_size", UiFonts.size("start"))
	start.pressed.connect(start_game)
	rv.add_child(start)
	_rebuild()


func on_enter() -> void:
	if _rules != null:
		_rules.nav = nav
		_rules.refresh()


# Zurück schließt zuerst die Auswahl „Gespeicherte Regeln“
func on_back() -> bool:
	return _rules != null and _rules.close_picker()


func _add(kind: String) -> void:
	if entries.size() >= MAX:
		return
	if kind == "bot":
		var used := {}
		for e in entries:
			used[str(e.name)] = true
		var n := ""
		for cand in SoloSetupScreen.BOT_NAMES:
			if not used.has(cand):
				n = cand
				break
		entries.append({"name": n if n != "" else I18n.t("Computer %d") % (entries.size() + 1), "kind": "bot"})
	else:
		entries.append({"name": "", "kind": "human"})
	_rebuild()
	if kind == "human":
		var last := _list.get_child(_list.get_child_count() - 1)
		var le := last.find_child("Name", true, false) as LineEdit
		if le != null:
			le.call_deferred("grab_focus")
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _remove(i: int) -> void:
	if entries.size() <= 2:
		toast("Mindestens zwei Plätze.")
		return
	entries.remove_at(i)
	_rebuild()


func _move(i: int, d: int) -> void:
	var j := i + d
	if j < 0 or j >= entries.size():
		return
	var e: Dictionary = entries[i]
	entries[i] = entries[j]
	entries[j] = e
	_rebuild()


func _rebuild() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for i in entries.size():
		_list.add_child(_row(i))
	_add_human.disabled = entries.size() >= MAX
	_add_bot.disabled = entries.size() >= MAX
	var humans := 0
	for e in entries:
		if e.kind == "human":
			humans += 1
	_count.text = I18n.t("%d Plätze · %d Menschen") % [entries.size(), humans]


func _row(i: int) -> Control:
	var e: Dictionary = entries[i]
	var row := ScreenKit.hbox(10)
	row.custom_minimum_size = Vector2(0, ScreenKit.TOUCH)
	var no := ScreenKit.label(str(i + 1), "", UiFonts.size("zeile"), Color(UiPalette.INK, 0.72))
	no.add_theme_font_override("font", UiFonts.text(800))
	no.custom_minimum_size = Vector2(30, 0)
	no.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(no)
	var av := ScreenKit.avatar(i, str(e.name) if str(e.name) != "" else "?", str(e.kind), 52.0)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(av)
	if e.kind == "bot":
		var l := ScreenKit.label(str(e.name), "", UiFonts.size("zeile"))
		l.add_theme_font_override("font", UiFonts.text(700))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		var tag := ScreenKit.label("Computer", "HintLabel", UiFonts.size("hinweis"))
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tag)
	else:
		var le := LineEdit.new()
		le.name = "Name"
		le.text = str(e.name)
		le.placeholder_text = I18n.t("Name Platz %d") % (i + 1)
		le.max_length = AppSettings.NAME_MAX
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.custom_minimum_size = Vector2(0, ScreenKit.TOUCH)
		le.select_all_on_focus = true
		le.text_changed.connect(func(t: String) -> void:
			e.name = AppSettings.filter_name(t) if t != "" else ""
			(av as ScreenKit.AvatarDot).initial = t.substr(0, 1).to_upper() if t != "" else "?"
			av.queue_redraw())
		le.focus_entered.connect(func() -> void: _lift(row))
		le.text_submitted.connect(func(_t: String) -> void: le.release_focus())
		row.add_child(le)
	var up := ScreenKit.icon_button(ScreenKit.glyph("pfeil", 40, -90), "GhostButton", "nach vorn")
	up.disabled = i == 0
	up.pressed.connect(_move.bind(i, -1))
	row.add_child(up)
	var down := ScreenKit.icon_button(ScreenKit.glyph("pfeil", 40, 90), "GhostButton", "nach hinten")
	down.disabled = i == entries.size() - 1
	down.pressed.connect(_move.bind(i, 1))
	row.add_child(down)
	var rm := ScreenKit.icon_button(ScreenKit.glyph("kreuz", 36), "GhostButton", "entfernen")
	rm.disabled = entries.size() <= 2
	rm.pressed.connect(_remove.bind(i))
	row.add_child(rm)
	return row


# Feld nach oben holen (Bildschirmtastatur im Querformat deckt die untere Hälfte)
func _lift(row: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(row):
		_scroll.scroll_vertical = int(row.position.y)


# Endgültige Spielerliste: leere Namen → „Spieler n“, doppelte Namen bekommen eine Nummer
func players() -> Array:
	var out: Array = []
	var seen := {}
	for i in entries.size():
		var e: Dictionary = entries[i]
		var n := AppSettings.clean_name(str(e.name))
		if n == "":
			n = I18n.t("Spieler %d") % (i + 1)
		var base := n
		var k := 2
		while seen.has(n.to_lower()):
			n = "%s %d" % [base.substr(0, AppSettings.NAME_MAX - 2), k]
			k += 1
		seen[n.to_lower()] = true
		out.append({"name": n, "kind": str(e.kind)})
	return out


func start_game() -> void:
	var list := players()
	var humans: Array = []
	for p in list:
		if p.kind == "human":
			humans.append(p.name)
	if humans.size() < 2:
		toast("Mindestens zwei Menschen – allein lieber das Übungsspiel.")
		return
	var app := UiApp.app()
	var st: Variant = app.get("settings") if app != null else null
	if st is Object and (st as Object).has_method("remember_names"):
		var typed: Array = []
		for e in entries:
			if e.kind == "human" and str(e.name) != "":
				typed.append(str(e.name))
		(st as Object).call("remember_names", typed)
	var source := GameStarter.local("pass", RulesBar.current(), list)
	if source == null:
		toast("Die Spielsteuerung fehlt.")
		return
	nav.push(TableScreen.create(source, source.start))
