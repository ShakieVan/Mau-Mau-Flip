class_name RulesScreen
extends AppScreen
# Regeln: „Übersicht“ (RulesText.overview zur aktiven Konfiguration) und „Anpassen“ (alle RuleConfig-Optionen mit deutschen
# Bezeichnungen, Voreinstellungen). Jede Änderung landet sofort in App.settings "regeln".

signal closed

# Optionen in Anzeigereihenfolge: [Schlüssel, Bezeichnung, Erklärung, Werte [[wert, text], …]] bzw. Schalter/Zahl
const OPTIONS := [
	["round_end", "Rundenende", "", [["first", "Erster fertig"], ["last", "Bis zum Letzten"]]],
	["scoring", "Wertung", "Punkte gelten nur, wenn die Runde beim ersten Fertigen endet.", [["none", "Ohne Punkte"], ["points500", "Punkte bis zum Ziel"]]],
	["target", "Punkteziel", "", "zahl", 100],
	["hand_size", "Karten zu Beginn", "", "zahl", 1],
	["draw_rule", "Ziehen", "Wenn nichts passt", [["one", "Eine Karte"], ["until_playable", "Bis eine passt"]]],
	["drawn_card", "Gezogene Karte", "Passt sie, …", [["may", "darf gelegt werden"], ["must", "muss gelegt werden"], ["may_not", "erst nächster Zug"]]],
	["stacking", "Ziehkarten weitergeben", "+1 auf +1, +5 auf +5 …: die Summe wächst", [["off", "Aus"], ["same", "Gleiche Karte"]]],
	["wild_restriction", "Wünscher +2 und Farbjagd", "Nur erlaubt, wenn keine Karte der aktuellen Farbe passt", [["bluff", "Bluffen erlaubt"], ["enforce", "App prüft"], ["free", "Immer erlaubt"]]],
	["wild_counts_for_bluff", "Joker zählen beim Anzweifeln mit", "Fassung 2024: ein Wünscher auf der Hand gilt als passend", "schalter"],
	["jagd_wild_stops", "Gezogener Joker beendet die Farbjagd", "", "schalter"],
	["mau_call", "„Mau!“ rufen", "Bei der vorletzten Karte", [["catch", "Erwischen"], ["auto", "App bestraft"], ["reminder", "Nur Hinweis"], ["off", "Aus"]]],
	["mau_penalty", "Strafkarten für vergessenes „Mau!“", "", "zahl", 1],
	["backs_visible", "Rückseiten der Mitspieler sichtbar", "Aus: alle sehen nur eine neutrale Rückseite", "schalter"],
	["peek_own_backs", "Eigene Rückseiten ansehen", "Knopf „Rückseiten“ am Tisch", "schalter"],
	["two_player_reverse_skips", "Zu zweit: Richtungswechsel wirkt wie Aussetzen", "", "schalter"],
	["flip_last_card", "Flip als letzte Karte", "", [["execute", "wird ausgeführt"], ["ignore", "nicht mehr ausgeführt"]]],
]

var start_tab := "uebersicht"
var cfg: RuleConfig
var _tabs: HBoxContainer
var _overview: ScrollContainer
var _editor: ScrollContainer
var _overview_text: RichTextLabel
var _preset_row: HBoxContainer
var _controls := {}                 # Schlüssel → Bedienelement


func build() -> void:
	cfg = RulesBar.current()
	_tabs = ScreenKit.choice([["uebersicht", "Übersicht"], ["anpassen", "Anpassen"]], start_tab, _show_tab, 22, 190.0)
	_tabs.name = "Reiter"
	var content := page("Regeln", true, _tabs)
	_overview = ScreenKit.scroller()
	_overview.name = "Uebersicht"
	content.add_child(_overview)
	var ocard := ScreenKit.card(34.0)
	ocard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overview.add_child(ocard)
	_overview_text = RichTextLabel.new()
	_overview_text.bbcode_enabled = true
	_overview_text.fit_content = true
	_overview_text.scroll_active = false
	_overview_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overview_text.mouse_filter = Control.MOUSE_FILTER_PASS
	ocard.add_child(_overview_text)
	_editor = ScreenKit.scroller()
	_editor.name = "Editor"
	content.add_child(_editor)
	var ecard := ScreenKit.card(30.0)
	ecard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor.add_child(ecard)
	var ev := ScreenKit.vbox(10)
	ecard.add_child(ev)
	var prow := ScreenKit.hbox(14)
	ev.add_child(prow)
	var pl := ScreenKit.label("Voreinstellung", "", 24)
	pl.add_theme_font_override("font", UiFonts.text(700))
	pl.custom_minimum_size = Vector2(300, 0)
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prow.add_child(pl)
	_preset_row = ScreenKit.choice(RulesBar.PRESETS, cfg.preset_name(), apply_preset, 21)
	prow.add_child(_preset_row)
	ev.add_child(_separator())
	for opt in OPTIONS:
		ev.add_child(_option_row(opt))
	_refresh()
	_show_tab(start_tab)


func _separator() -> Control:
	var s := ColorRect.new()
	s.color = Color(UiPalette.INK, 0.12)
	s.custom_minimum_size = Vector2(0, 2)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _option_row(opt: Array) -> Control:
	var key: String = opt[0]
	var kind: Variant = opt[3]
	var ctrl: Control
	if kind is Array:
		ctrl = ScreenKit.choice(kind, str(cfg.get(key)), func(v: String) -> void: set_option(key, v), 20)
	elif str(kind) == "schalter":
		var c := CheckButton.new()
		c.button_pressed = bool(cfg.get(key))
		c.focus_mode = Control.FOCUS_NONE
		c.custom_minimum_size = Vector2(ScreenKit.TOUCH * 1.4, ScreenKit.TOUCH)
		c.toggled.connect(func(on: bool) -> void: set_option(key, on))
		ctrl = c
	else:
		var limits: Array = RuleConfig.NUMBERS[key]
		var step := int(opt[4]) if opt.size() > 4 else 1
		ctrl = ScreenKit.stepper(int(limits[1]), int(limits[2]), int(cfg.get(key)), func(v: int) -> void: set_option(key, v), step)
	ctrl.name = key
	_controls[key] = ctrl
	return ScreenKit.row(str(opt[1]), ctrl, 380.0, str(opt[2]))


func _show_tab(tab: String) -> void:
	start_tab = tab
	_overview.visible = tab == "uebersicht"
	_editor.visible = tab == "anpassen"
	ScreenKit.set_choice(_tabs, tab)
	if tab == "uebersicht":
		_render_overview()


# Einzelne Option setzen und speichern
func set_option(key: String, value: Variant) -> void:
	cfg.apply_dict({key: value})
	RulesBar.store(cfg)
	ScreenKit.set_choice(_preset_row, cfg.preset_name())
	_refresh_enabled()


func apply_preset(name: String) -> void:
	cfg = RuleConfig.preset(name)
	RulesBar.store(cfg)
	_refresh()


# Bedienelemente auf cfg setzen (nach einer Voreinstellung)
func _refresh() -> void:
	ScreenKit.set_choice(_preset_row, cfg.preset_name())
	for opt in OPTIONS:
		var key: String = opt[0]
		var ctrl: Control = _controls.get(key)
		if ctrl == null:
			continue
		var kind: Variant = opt[3]
		if kind is Array:
			ScreenKit.set_choice(ctrl as HBoxContainer, str(cfg.get(key)))
		elif str(kind) == "schalter":
			(ctrl as CheckButton).set_pressed_no_signal(bool(cfg.get(key)))
		else:
			var state: Dictionary = ctrl.get_meta("value")
			state.v = int(cfg.get(key))
			var shown := ctrl.get_child(1) as Label
			shown.text = str(state.v)
			var limits: Array = RuleConfig.NUMBERS[key]
			(ctrl.get_child(0) as Button).disabled = int(state.v) <= int(limits[1])
			(ctrl.get_child(2) as Button).disabled = int(state.v) >= int(limits[2])
	_refresh_enabled()


# Abhängige Optionen ausgrauen (Punkteziel nur mit Punktwertung, Joker-Zählung nur mit Bluff)
func _refresh_enabled() -> void:
	_dim("target", cfg.effective_scoring() == "points500")
	_dim("scoring", cfg.round_end == "first")
	_dim("wild_counts_for_bluff", cfg.wild_restriction == "bluff")
	_dim("mau_penalty", cfg.mau_call != "off")


func _dim(key: String, active: bool) -> void:
	var ctrl: Control = _controls.get(key)
	if ctrl != null and ctrl.get_parent() != null:
		(ctrl.get_parent() as Control).modulate.a = 1.0 if active else 0.45


func _render_overview() -> void:
	var t := ""
	var p := cfg.preset_name()
	t += "[font_size=20][color=#6E6178]%s[/color][/font_size]\n" % ("Voreinstellung: " + str(RuleConfig.PRESET_TITLES[p]) if p != "" else "Eigene Regeln")
	for sec in RulesText.overview(cfg):
		t += "\n[font_size=30][b]%s[/b][/font_size]\n%s\n" % [str(sec.get("title", "")), str(sec.get("text", ""))]
	t += "\n[font_size=30][b]Kurz gesagt[/b][/font_size]\n"
	for line in cfg.describe():
		t += "• %s\n" % line
	_overview_text.text = t


func on_leave() -> void:
	closed.emit()
