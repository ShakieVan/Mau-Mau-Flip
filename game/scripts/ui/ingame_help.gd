class_name IngameHelp
extends Control
# Regeln und Hilfe im Spiel (Beta 1.0.2): Überlagerung über dem Tisch, geöffnet aus dem Spielmenü („Partie verlassen?“).
#   Reiter „Regeln“: die aktiven Regeln dieser Partie (view.rules → RulesText.overview) samt „Besondere Karten“
#                    (RulesScreen.special_cards mit kleinen Kartenbildern) und „Kurz gesagt“; nur lesen, blätterbar.
#   Reiter „So geht's“: Bedienung und Gesten (RulesText.controls).
# Die Partie läuft weiter; Schließen per Knopf, Tipp daneben oder Zurück-Taste (TableScreen.on_back). Tag/Nacht nach dem Tisch,
# Schriftgrößen aus UiFonts (live über UiFonts.rescale_tree). show_cards = false lässt die Kartenbilder weg (Regel 15:
# Sichtschutz beim Weitergeben zeigt keine Karten; der Tisch schließt die Überlagerung ohnehin, sobald er erscheint).

signal closed

var cfg: RuleConfig
var night := false
var show_cards := true
var tab := "regeln"

var _card: PanelContainer
var _scroll: ScrollContainer
var _content: VBoxContainer
var _tabs: Dictionary = {}     # "regeln"/"bedienung" → Button


static func open(parent: Node, rules: Variant, is_night: bool, cards := true, first_tab := "regeln") -> IngameHelp:
	var o := IngameHelp.new()
	o.theme = UiTheme.get_theme()
	o.cfg = RuleSets.load_config(rules) if rules is Dictionary and not (rules as Dictionary).is_empty() else RuleConfig.new()
	o.night = is_night
	o.show_cards = cards
	o.tab = first_tab
	parent.add_child(o)
	o._build()
	return o


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	name = "RegelnImSpiel"


func _build() -> void:
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 120)
	for side in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 24)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	_card = ScreenKit.card(26.0, night)
	m.add_child(_card)
	var v := ScreenKit.vbox(12)
	_card.add_child(v)
	var head := ScreenKit.hbox(12)
	v.add_child(head)
	for t in [["regeln", "Regeln"], ["bedienung", "So geht's"]]:
		var b := ScreenKit.button(str(t[1]), "")
		b.name = "Reiter_" + str(t[0])
		b.toggle_mode = true
		b.pressed.connect(show_tab.bind(str(t[0])))
		head.add_child(b)
		_tabs[t[0]] = b
	head.add_child(ScreenKit.spacer())
	var close_btn := ScreenKit.button("Schließen", "PrimaryButton", "kreuz")
	close_btn.name = "Schliessen"
	close_btn.pressed.connect(close)
	head.add_child(close_btn)
	_scroll = ScreenKit.scroller()
	_scroll.name = "Inhalt"
	v.add_child(_scroll)
	_content = ScreenKit.vbox(10)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	show_tab(tab)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)


func show_tab(which: String) -> void:
	tab = which if which == "bedienung" else "regeln"
	for k in _tabs:
		var b: Button = _tabs[k]
		b.set_pressed_no_signal(k == tab)
		b.theme_type_variation = "PrimaryButton" if k == tab else "GhostButton"
		# nachts ist der nicht gewählte Reiter sonst dunkle Schrift auf dunkler Karte (Gerätetest 1.1.2)
		for fc in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
			if night and k != tab:
				b.add_theme_color_override(fc, UiPalette.PAPER)
			else:
				b.remove_theme_color_override(fc)
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	if tab == "regeln":
		_fill_rules()
	else:
		for sec in RulesText.controls(cfg):
			_section(str(sec.title), str(sec.text))
	_scroll.scroll_vertical = 0


func _fill_rules() -> void:
	var p := cfg.preset_name()
	var head := ("Voreinstellung: " + str(RuleConfig.PRESET_TITLES[p])) if p != "" else "Eigene Regeln"
	head += " · %d Karten" % cfg.card_count()
	var extras := RulesBar.extra_names(cfg)
	if not extras.is_empty():
		head += " · Hausregeln: " + RulesBar.join_and(extras)
	_content.add_child(_text(head, UiFonts.size("text"), true))
	for sec in RulesText.overview(cfg):
		if str(sec.title) == "Weitere besondere Karten":
			continue        # Hinweis aufs Einschalten unter „Anpassen“ passt nicht in eine laufende Partie
		_section(str(sec.title), str(sec.text))
	_content.add_child(_heading("Besondere Karten", UiFonts.size("zwischen")))
	for e in RulesScreen.special_cards(cfg):
		var row := ScreenKit.hbox(18)
		row.name = "Karte_" + str(e.kind)
		if show_cards:
			var thumbs := RulesScreen.CardThumbs.new()
			thumbs.name = "Bilder"
			thumbs.keys = e.keys
			thumbs.custom_minimum_size = Vector2(118, 100)
			thumbs.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			row.add_child(thumbs)
		var col := ScreenKit.vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		col.add_child(_heading("%s  ·  %s" % [str(e.title), str(e.side)], UiFonts.size("zeile")))
		col.add_child(_text(" ".join(PackedStringArray(e.lines)), UiFonts.size("text")))
		_content.add_child(row)
	_content.add_child(_heading("Kurz gesagt", UiFonts.size("zwischen")))
	var s := ""
	for line in cfg.describe():
		s += "• %s\n" % line
	_content.add_child(_text(s.strip_edges(), UiFonts.size("text")))


func _section(title: String, text: String) -> void:
	var v := ScreenKit.vbox(2)
	v.name = "Absatz"
	v.add_child(_heading(title, UiFonts.size("zwischen")))
	v.add_child(_text(text, UiFonts.size("text")))
	_content.add_child(v)


func _heading(text: String, fs: int) -> Label:
	var l := ScreenKit.label(text, "NightLabel" if night else "", fs)
	l.add_theme_font_override("font", UiFonts.text(800))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _text(text: String, fs: int, muted := false) -> Label:
	var l := ScreenKit.label(text, "NightLabel" if night else ("HintLabel" if muted else ""), fs)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if night and muted:
		l.modulate.a = 0.75
	return l


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.1, 0.55))


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if not _card.get_global_rect().has_point(get_global_transform() * mb.position):
			close()
		accept_event()


func is_open() -> bool:
	return is_inside_tree() and not is_queued_for_deletion()


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()
