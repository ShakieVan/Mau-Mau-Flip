class_name RulesScreen
extends AppScreen
# Regeln: „Übersicht“ (RulesText.overview zur aktiven Konfiguration) und „Anpassen“ (alle RuleConfig-Optionen mit deutschen
# Bezeichnungen, Voreinstellungen). Jede Änderung landet sofort in App.settings "regeln".
# Die Hausregeln mit Zusatzkarten (Kartentausch samt Tauschrichtung, Glücksspiel, Farbe mit ablegen) stehen in einem eigenen
# Abschnitt mit kleinen Kartenbildern; die Kartenzahl der Partie (112–124) steht oben neben den Voreinstellungen und im
# Abschnittskopf. Die Tauschrichtung ist nur mit Kartentausch bedienbar.
# Gespeicherte Regelsätze (RuleSets, Nutzerwunsch 06.10.2026): Abschnitt „Gespeichert“ unter den Voreinstellungen. Kopfreihe:
# Bezeichnung, Hinweis „Antippen lädt, × löscht“ und rechts „Speichern unter …“ (RuleSetSaveBox). Darunter die Knöpfe über die
# ganze Breite, umbrechend: zuerst – falls vorhanden – „Zuletzt gespielt bei <Gastgeber>“ (Regeln des letzten Gastgebers, von
# selbst gemerkt), dann je Satz ein Knopf mit kleinem × (Prüfung 06.10.2026). Tippen lädt; der passende Satz ist wie eine
# Voreinstellung hervorgehoben (bei gleichen Regeln der zuletzt gewählte, RuleSets.chosen_name). Das × (wie bisher auch
# Gedrückthalten bzw. Rechtsklick) fragt, ob der Satz gelöscht werden soll – ohne ihn zu laden, die eingestellten Regeln bleiben.
# Übersicht: unter den Absätzen „Besondere Karten“ (special_cards): jede Aktions- und aktive Zusatzkarte mit kleinem Kartenbild
# und den Sätzen der Kartenhilfe (RulesText.card_help) zu den aktiven Regeln.

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
	["penalty_turn", "Nach dem Strafziehen", "Wer +1, +5 … abbekommt: aussetzen oder gleich weiterspielen", [["skip", "Aussetzen"], ["play", "Weiterspielen"]]],
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
# Hausregeln mit Zusatzkarten: wie OPTIONS, dazu die Gesichter für die Kartenbilder; "an_aus" = Schalter für "on"/"off".
const EXTRA_OPTIONS := [
	["swap_cards", "Kartentausch", "4 Zusatzkarten: Alle geben ihre ganze Hand weiter", "an_aus", ["hell_rot_tausch", "dunkel_tuerkis_tausch"]],
	["swap_direction", "Tauschrichtung", "Wohin die Hände wandern (nur mit Kartentausch)", [["clockwise", "Im Uhrzeigersinn"], ["play", "In Spielrichtung"]], []],
	["gamble_cards", "Glücksspiel", "2 Joker: verdeckt setzen und drücken, bis ein Treffer kommt", "an_aus", ["hell_gluecksspiel", "dunkel_gluecksspiel"]],
	["discard_color", "Farbe mit ablegen", "6 Zusatzkarten: Alle Karten der Farbe mit ablegen", "an_aus", ["hell_gruen_ablegen", "hell_ablegen_joker"]],
]
const LABEL_W := 380.0
const THUMB_W := 96.0
const LONG_PRESS := 0.55             # Sekunden gedrückt halten = löschen

var start_tab := "uebersicht"
var cfg: RuleConfig
var _tabs: HBoxContainer
var _overview: ScrollContainer
var _editor: ScrollContainer
var _overview_text: RichTextLabel
var _special_box: VBoxContainer     # Übersicht: „Besondere Karten“
var _overview_short: RichTextLabel  # Übersicht: „Kurz gesagt“
var _preset_row: HBoxContainer
var _controls := {}                 # Schlüssel → Bedienelement
var _count_labels: Array[Label] = []
var _sets_box: HFlowContainer       # Knöpfe der gespeicherten Sätze
var _sets_hint: Label               # „Antippen lädt, gedrückt halten löscht“
var _save_btn: Button
var _save_box: RuleSetSaveBox
var _confirm: ConfirmBox


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
	var ov := ScreenKit.vbox(10)
	ocard.add_child(ov)
	_overview_text = _rich()
	ov.add_child(_overview_text)
	_special_box = ScreenKit.vbox(14)
	_special_box.name = "BesondereKarten"
	ov.add_child(_special_box)
	_overview_short = _rich()
	ov.add_child(_overview_short)
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
	prow.add_child(ScreenKit.spacer())
	var top_count := _count_pill()
	top_count.name = "KartenzahlOben"
	prow.add_child(top_count)
	ev.add_child(_sets_row())
	ev.add_child(_separator())
	for opt in OPTIONS:
		ev.add_child(_option_row(opt))
	# Hausregeln mit Zusatzkarten
	ev.add_child(_separator())
	var xhead := ScreenKit.hbox(14)
	xhead.custom_minimum_size = Vector2(0, 64)
	ev.add_child(xhead)
	var xh := ScreenKit.heading("Hausregeln mit Zusatzkarten", 30)
	xh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xhead.add_child(xh)
	xhead.add_child(ScreenKit.spacer())
	var count := _count_pill()
	count.name = "Kartenzahl"
	xhead.add_child(count)
	ev.add_child(ScreenKit.hint("Jede bringt eigene Karten mit. Ohne sie wird mit 112 Karten gespielt.", 18))
	for opt in EXTRA_OPTIONS:
		ev.add_child(_extra_row(opt))
	_refresh()
	_show_tab(start_tab)


# Abschnitt „Gespeichert“: Kopfreihe mit Bezeichnung, Hinweis und „Speichern unter …“, darunter die Sätze als Knöpfe über die
# ganze Breite (umbrechend, Gastgeber-Platz zuerst)
func _sets_row() -> Control:
	var row := ScreenKit.vbox(8)
	row.name = "Gespeichert"
	var head := ScreenKit.hbox(18)
	row.add_child(head)
	var l := ScreenKit.label("Gespeichert", "", 24)
	l.add_theme_font_override("font", UiFonts.text(700))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(l)
	_sets_hint = ScreenKit.hint("", 17)
	_sets_hint.name = "Hinweis"
	_sets_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sets_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(_sets_hint)
	head.add_child(ScreenKit.spacer())
	_save_btn = ScreenKit.button("Speichern unter …", "", "regeln")
	_save_btn.name = "SpeichernUnter"
	_save_btn.tooltip_text = "Die eingestellten Regeln unter einem Namen speichern"
	_save_btn.add_theme_font_size_override("font_size", 20)
	_save_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_save_btn.custom_minimum_size.y = 64.0          # flache Kopfreihe, damit die Optionen im Bild bleiben
	for st in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		var sb := UiTheme.get_theme().get_stylebox(st, "Button") if UiTheme.get_theme().has_stylebox(st, "Button") else null
		if sb != null:
			sb = sb.duplicate()
			sb.content_margin_top = 4.0
			sb.content_margin_bottom = 4.0
			_save_btn.add_theme_stylebox_override(st, sb)
	_save_btn.pressed.connect(save_as)
	head.add_child(_save_btn)
	_sets_box = HFlowContainer.new()
	_sets_box.name = "Saetze"
	_sets_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sets_box.add_theme_constant_override("h_separation", 8)
	_sets_box.add_theme_constant_override("v_separation", 8)
	row.add_child(_sets_box)
	_rebuild_sets()
	return row


func _rebuild_sets() -> void:
	if _sets_box == null:
		return
	for c in _sets_box.get_children():
		_sets_box.remove_child(c)
		c.queue_free()
	# Gastgeber-Platz zuerst: Er ist der Weg, mit dem jemand die Partie eines gegangenen Gastgebers fortsetzt
	var host := RuleSets.host_name()
	if host != "":
		var hb := ScreenKit.button(RuleSets.host_title(host), "GhostButton", "wlan")
		hb.name = "Gastgeber"
		hb.tooltip_text = "Regeln, mit denen du zuletzt im WLAN-Spiel von %s gespielt hast" % host
		hb.add_theme_font_size_override("font_size", 21)
		hb.set_meta("host", true)
		hb.pressed.connect(apply_host_rules)
		_sets_box.add_child(hb)
	var all := RuleSets.list()
	for i in all.size():
		var n := str(all[i].name)
		# Satzknopf (laden) mit kleinem × daneben (löschen mit Rückfrage, lädt nichts)
		var pair := ScreenKit.hbox(0)
		pair.name = "Satz%d" % i
		var b := ScreenKit.button(n, "GhostButton")
		b.name = "Laden"
		b.tooltip_text = "Antippen lädt"
		b.add_theme_font_size_override("font_size", 21)
		b.set_meta("set", n)
		b.button_down.connect(_on_set_down.bind(b))
		b.pressed.connect(_on_set_pressed.bind(b))
		b.gui_input.connect(_on_set_input.bind(b))
		pair.add_child(b)
		var x := ScreenKit.icon_button(ScreenKit.glyph("kreuz", 24), "GhostButton", "„%s“ löschen" % n)
		x.name = "Loeschen"
		x.custom_minimum_size = Vector2(48, ScreenKit.TOUCH)
		x.set_meta("delete", n)
		x.pressed.connect(ask_delete.bind(n))
		pair.add_child(x)
		_sets_box.add_child(pair)
	if _sets_box.get_child_count() == 0:
		var h := ScreenKit.hint("Noch nichts gespeichert. Stell die Regeln ein und tippe oben auf „Speichern unter …“.", 18)
		h.name = "Leer"
		h.custom_minimum_size = Vector2(0, ScreenKit.TOUCH)
		h.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_sets_box.add_child(h)
	if _sets_hint != null:
		_sets_hint.text = "Antippen lädt, × löscht" if not all.is_empty() else ("Antippen lädt die Regeln" if host != "" else "")
		_sets_hint.visible = _sets_hint.text != ""
	_refresh_sets()


# Hervorhebung wie bei den Voreinstellungen: der passende eigene Satz (bei Doppelten der zuletzt gewählte) und der Gastgeber-Platz
func _refresh_sets() -> void:
	if _sets_box == null:
		return
	var active := active_set_name()
	var host_on := RuleSets.host_matches(cfg)
	for b in _sets_box.find_children("*", "Button", true, false):
		if not b.has_meta("host") and not b.has_meta("set"):
			continue
		var on :=host_on if b.has_meta("host") else str(b.get_meta("set", "")) == active
		(b as Button).theme_type_variation = "PrimaryButton" if on else "GhostButton"


# Gedrückt halten: nach LONG_PRESS die Lösch-Rückfrage (wenn der Knopf noch gedrückt ist; Wischen bricht den Druck ab)
func _on_set_down(b: Button) -> void:
	b.set_meta("long", false)
	var token := int(b.get_meta("hold", 0)) + 1
	b.set_meta("hold", token)
	get_tree().create_timer(LONG_PRESS).timeout.connect(_on_set_held.bind(b, token))


func _on_set_held(held: Variant, token: int) -> void:
	if not is_instance_valid(held) or not held is Button:
		return
	var b := held as Button
	if not b.is_inside_tree() or int(b.get_meta("hold", 0)) != token or not b.is_pressed():
		return
	b.set_meta("long", true)
	UiApp.vibrate(30, 0.5)
	ask_delete(str(b.get_meta("set", "")))


# Loslassen nach dem Halten lädt nicht
func _on_set_pressed(b: Button) -> void:
	b.set_meta("hold", int(b.get_meta("hold", 0)) + 1)
	if bool(b.get_meta("long", false)):
		b.set_meta("long", false)
		return
	apply_set(str(b.get_meta("set", "")))


# Am PC: Rechtsklick = löschen
func _on_set_input(event: InputEvent, b: Button) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		ask_delete(str(b.get_meta("set", "")))


# Name des eigenen Satzes, der genau den aktuellen Regeln entspricht ("" = keiner; bei Doppelten der zuletzt gewählte)
func active_set_name() -> String:
	return RuleSets.match_name(cfg)


func apply_set(set_name: String) -> void:
	var c := RuleSets.config(set_name)
	if c == null:
		_rebuild_sets()
		return
	cfg = c
	RuleSets.choose(set_name)
	RulesBar.store(cfg)
	_refresh()


func apply_host_rules() -> void:
	var c := RuleSets.host_config()
	if c == null:
		return
	cfg = c
	RuleSets.choose("")
	RulesBar.store(cfg)
	_refresh()


# „Speichern unter …“: Vorschlag ist der zuletzt geladene Satz, wenn die Regeln seitdem geändert wurden (zum Überschreiben).
# Nach einer Voreinstellung oder dem Gastgeber-Platz gibt es keinen Vorschlag (RuleSets.choose("")).
func save_as() -> void:
	if _save_box != null and is_instance_valid(_save_box):
		return
	var suggestion := ""
	var chosen := RuleSets.chosen_name()
	if chosen != "" and not RuleSets.matches(chosen, cfg):
		suggestion = chosen
	_save_box = RuleSetSaveBox.ask(self, cfg, suggestion)
	_save_box.saved.connect(func(n: String) -> void:
		_save_box = null
		_rebuild_sets()
		toast("Gespeichert: „%s“" % n))
	_save_box.cancelled.connect(func() -> void: _save_box = null)


# Löschen eines beliebigen Satzes (gedrückt halten), mit Rückfrage. Die eingestellten Regeln bleiben unverändert.
func ask_delete(set_name: String) -> void:
	var n := RuleSets.stored_name(set_name)
	if n == "" or (_confirm != null and is_instance_valid(_confirm)) or (_save_box != null and is_instance_valid(_save_box)):
		return
	_confirm = ConfirmBox.ask(self, "„%s“ löschen?" % n, "Der gespeicherte Regelsatz wird entfernt. Die eingestellten Regeln bleiben, wie sie sind.", "Löschen", "Behalten")
	_confirm.answered.connect(func(yes: bool) -> void:
		_confirm = null
		if not yes:
			return
		if not RuleSets.remove(n):
			toast("Löschen hat nicht geklappt. Ist der Speicher des Geräts voll?")
			return
		_rebuild_sets()
		toast("Gelöscht: „%s“" % n))


# Zurück schließt zuerst eine offene Rückfrage bzw. den Speichern-Dialog
func on_back() -> bool:
	if _save_box != null and is_instance_valid(_save_box):
		_save_box.cancel()
		_save_box = null
		return true
	if _confirm != null and is_instance_valid(_confirm):
		_confirm.cancel()
		_confirm = null
		return true
	return false


func _separator() -> Control:
	var s := ColorRect.new()
	s.color = Color(UiPalette.INK, 0.12)
	s.custom_minimum_size = Vector2(0, 2)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


# Kartenzahl als Pille („116 Karten“); Sonnengelb, sobald Zusatzkarten im Spiel sind
func _count_pill() -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := ScreenKit.label("", "", 22)
	l.add_theme_font_override("font", UiFonts.text(800))
	l.name = "Text"
	p.add_child(l)
	_count_labels.append(l)
	return p


func _option_row(opt: Array) -> Control:
	var key: String = opt[0]
	var kind: Variant = opt[3]
	var ctrl: Control
	if kind is Array:
		ctrl = ScreenKit.choice(kind, str(cfg.get(key)), func(v: String) -> void: set_option(key, v), 20)
	elif str(kind) == "schalter" or str(kind) == "an_aus":
		var c := CheckButton.new()
		var as_text := str(kind) == "an_aus"
		c.button_pressed = str(cfg.get(key)) == "on" if as_text else bool(cfg.get(key))
		c.focus_mode = Control.FOCUS_NONE
		c.custom_minimum_size = Vector2(ScreenKit.TOUCH * 1.4, ScreenKit.TOUCH)
		ScreenKit.style_switch(c)
		c.toggled.connect(func(on: bool) -> void: set_option(key, ("on" if on else "off") if as_text else on))
		ctrl = c
	else:
		var limits: Array = RuleConfig.NUMBERS[key]
		var step := int(opt[4]) if opt.size() > 4 else 1
		ctrl = ScreenKit.stepper(int(limits[1]), int(limits[2]), int(cfg.get(key)), func(v: int) -> void: set_option(key, v), step)
	ctrl.name = key
	_controls[key] = ctrl
	return ScreenKit.row(str(opt[1]), ctrl, LABEL_W, str(opt[2]))


# Zeile einer Hausregel: vorn die Kartenbilder (bzw. Platz dafür), damit Bezeichnungen und Bedienelemente bündig bleiben
func _extra_row(opt: Array) -> Control:
	var r := _option_row(opt)
	var thumbs := CardThumbs.new()
	thumbs.name = "Karten"
	thumbs.keys = opt[4]
	thumbs.custom_minimum_size = Vector2(THUMB_W, ScreenKit.TOUCH)
	r.add_child(thumbs)
	r.move_child(thumbs, 0)
	var left := r.get_child(1) as Control
	left.custom_minimum_size.x = LABEL_W - THUMB_W - float(r.get_theme_constant("separation"))
	return r


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
	_refresh_sets()
	_refresh_enabled()


func apply_preset(name: String) -> void:
	cfg = RuleConfig.preset(name)
	RuleSets.choose("")
	RulesBar.store(cfg)
	_refresh()


# Bedienelemente auf cfg setzen (nach einer Voreinstellung)
func _refresh() -> void:
	ScreenKit.set_choice(_preset_row, cfg.preset_name())
	_refresh_sets()
	var all: Array = OPTIONS.duplicate()
	all.append_array(EXTRA_OPTIONS)
	for opt in all:
		var key: String = opt[0]
		var ctrl: Control = _controls.get(key)
		if ctrl == null:
			continue
		var kind: Variant = opt[3]
		if kind is Array:
			ScreenKit.set_choice(ctrl as HBoxContainer, str(cfg.get(key)))
		elif str(kind) == "schalter":
			(ctrl as CheckButton).set_pressed_no_signal(bool(cfg.get(key)))
		elif str(kind) == "an_aus":
			(ctrl as CheckButton).set_pressed_no_signal(str(cfg.get(key)) == "on")
		else:
			var state: Dictionary = ctrl.get_meta("value")
			state.v = int(cfg.get(key))
			var shown := ctrl.get_child(1) as Label
			shown.text = str(state.v)
			var limits: Array = RuleConfig.NUMBERS[key]
			(ctrl.get_child(0) as Button).disabled = int(state.v) <= int(limits[1])
			(ctrl.get_child(2) as Button).disabled = int(state.v) >= int(limits[2])
	_refresh_enabled()


# Abhängige Optionen ausgrauen (Punkteziel nur mit Punktwertung, Joker-Zählung nur mit Bluff); die Tauschrichtung ist ohne
# Kartentausch zusätzlich gesperrt. Dazu die Kartenzahl der Partie.
func _refresh_enabled() -> void:
	_dim("target", cfg.effective_scoring() == "points500")
	_dim("scoring", cfg.round_end == "first")
	_dim("wild_counts_for_bluff", cfg.wild_restriction == "bluff")
	_dim("mau_penalty", cfg.mau_call != "off")
	_dim("swap_direction", cfg.swap_cards == "on", true)
	var n := cfg.card_count()
	for l in _count_labels:
		l.text = "%d Karten" % n
		var pill := l.get_parent() as PanelContainer
		var extra := n > CardDB.CARD_COUNT
		var sb := UiTheme.box(UiPalette.FILL["gelb"] if extra else Color(UiPalette.INK, 0.06), Color(UiPalette.INK, 0.8 if extra else 0.3), 2, 24, 20.0, 8.0)
		pill.add_theme_stylebox_override("panel", sb)
		pill.tooltip_text = "Kartenzahl der Partie"


# active = false: Zeile halb durchsichtig; lock: zusätzlich alle Knöpfe des Bedienelements gesperrt
func _dim(key: String, active: bool, lock := false) -> void:
	var ctrl: Control = _controls.get(key)
	if ctrl != null and ctrl.get_parent() != null:
		(ctrl.get_parent() as Control).modulate.a = 1.0 if active else 0.45
		if lock:
			for b in ctrl.find_children("*", "BaseButton", true, false):
				(b as BaseButton).disabled = not active
			if ctrl is BaseButton:
				(ctrl as BaseButton).disabled = not active


func _render_overview() -> void:
	var t := ""
	var p := cfg.preset_name()
	var head := ("Voreinstellung: " + str(RuleConfig.PRESET_TITLES[p])) if p != "" else "Eigene Regeln"
	var saved := active_set_name()
	if p == "" and saved != "":
		head = "Gespeichert: " + saved
	elif p == "" and RuleSets.host_matches(cfg):
		head = RuleSets.host_title(RuleSets.host_name())
	head += " · %d Karten" % cfg.card_count()
	var extras := RulesBar.extra_names(cfg)
	if not extras.is_empty():
		head += " · Hausregeln: " + RulesBar.join_and(extras)
	t += "[font_size=20][color=#6E6178]%s[/color][/font_size]\n" % head.replace("[", "[lb]")
	for sec in RulesText.overview(cfg):
		t += "\n[font_size=30][b]%s[/b][/font_size]\n%s\n" % [str(sec.get("title", "")), str(sec.get("text", ""))]
	_overview_text.text = t
	_render_special()
	var s := "[font_size=30][b]Kurz gesagt[/b][/font_size]\n"
	for line in cfg.describe():
		s += "• %s\n" % line
	_overview_short.text = s


func _rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r


# Abschnitt „Besondere Karten“: je Karte ein kleines Bild, Name, Seite und die Kartenhilfe zu den aktiven Regeln
func _render_special() -> void:
	for c in _special_box.get_children():
		_special_box.remove_child(c)
		c.queue_free()
	var h := ScreenKit.label("Besondere Karten", "", 30)
	h.add_theme_font_override("font", UiFonts.text(800))
	_special_box.add_child(h)
	var sp := special_cards(cfg)
	for e in sp:
		var row := ScreenKit.hbox(18)
		row.name = str(e.kind)
		var thumbs := CardThumbs.new()
		thumbs.keys = e.keys
		thumbs.custom_minimum_size = Vector2(118, 100)
		thumbs.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(thumbs)
		var v := ScreenKit.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		var head := ScreenKit.hbox(12)
		v.add_child(head)
		var tl := ScreenKit.label(str(e.title), "", 24)
		tl.add_theme_font_override("font", UiFonts.text(800))
		head.add_child(tl)
		var sl := ScreenKit.label(str(e.side), "HintLabel", 18)
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(sl)
		var tx := ScreenKit.text_block(" ".join(PackedStringArray(e.lines)), 20)
		tx.name = "Text"
		v.add_child(tx)
		_special_box.add_child(row)
	var off := RulesBar.EXTRAS.filter(func(x: Array) -> bool: return str(cfg.get(str(x[0]))) != "on").map(func(x: Array) -> String: return str(x[1]))
	if not off.is_empty():
		var names: Array[String] = []
		names.assign(off)
		_special_box.add_child(ScreenKit.hint("Weitere Zusatzkarten gibt es als Hausregel unter „Anpassen“: %s." % RulesBar.join_and(names), 18))


# Besondere Karten der aktiven Regeln: [{kind, title, side, keys (Kartenbilder), lines}]. Die Sätze stammen aus RulesText.card_help;
# die Farbangabe („Passt auf Rot …“) wird allgemein, der Wert steht nur bei Punktwertung da. Zusatzkarten nur, wenn ihre Hausregel an ist.
static func special_cards(c: RuleConfig) -> Array[Dictionary]:
	var list := [
		["plus1", "Helle Seite", ["hell_rot_plus1"]],
		["aussetzen", "Helle Seite", ["hell_gelb_aussetzen"]],
		["wuenscher_plus2", "Helle Seite", ["hell_wuenscher_plus2"]],
		["plus5", "Dunkle Seite", ["dunkel_pink_plus5"]],
		["alle_aussetzen", "Dunkle Seite", ["dunkel_tuerkis_alle_aussetzen"]],
		["farbjagd", "Dunkle Seite", ["dunkel_farbjagd"]],
		["richtungswechsel", "Beide Seiten", ["hell_gruen_richtungswechsel", "dunkel_orange_richtungswechsel"]],
		["flip", "Beide Seiten", ["hell_blau_flip", "dunkel_lila_flip"]],
		["wuenscher", "Beide Seiten", ["hell_wuenscher", "dunkel_wuenscher"]],
	]
	if c.swap_cards == "on":
		list.append(["tausch", "Hausregel, beide Seiten", ["hell_rot_tausch", "dunkel_tuerkis_tausch"]])
	if c.gamble_cards == "on":
		list.append(["gluecksspiel", "Hausregel, beide Seiten", ["hell_gluecksspiel", "dunkel_gluecksspiel"]])
	if c.discard_color == "on":
		list.append(["ablegen", "Hausregel, beide Seiten", ["hell_gruen_ablegen", "dunkel_lila_ablegen"]])
		list.append(["ablegen_joker", "Hausregel, beide Seiten", ["hell_ablegen_joker", "dunkel_ablegen_joker"]])
	var points := c.effective_scoring() == "points500"
	var out: Array[Dictionary] = []
	for e in list:
		var kind := str(e[0])
		var key := str(e[2][0])
		var f := CardDB.parse_key(key)
		var colored := str(f.get("color", "")) != ""
		var lines: Array[String] = []
		for line in RulesText.card_help(key, c):
			if colored and line.begins_with("Passt auf "):
				line = "Passt auf ihre Farbe und auf jede Karte mit demselben Symbol."
			elif line.begins_with("Wert: ") or (not points and line.begins_with("Zählt ")):
				continue
			if kind == "flip":
				line = line.replace("die " + RulesText.side_name(CardDB.other_side(str(f.side))), "die andere Seite")
			lines.append(line)
		out.append({"kind": kind, "title": RulesText.kind_name(kind) if kind != "ablegen" else "Farbe ablegen", "side": e[1], "keys": e[2], "lines": lines})
	return out


func on_leave() -> void:
	closed.emit()


# Kleine Kartenbilder einer Hausregel, leicht aufgefächert (Bilder aus Modul B, res://assets/cards/)
class CardThumbs:
	extends Control
	var keys: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var n := keys.size()
		if n == 0:
			return
		var h := minf(size.y - 8.0, 76.0)
		var w := h * float(CardTextures.SIZE.x) / float(CardTextures.SIZE.y)
		var shadow := StyleBoxFlat.new()
		shadow.bg_color = Color(0, 0, 0, 0.16)
		shadow.set_corner_radius_all(int(w * 0.12))
		for i in n:
			var t := 0.0 if n == 1 else float(i) / float(n - 1) - 0.5
			var c := size * 0.5 + Vector2(t * w * 0.75, absf(t) * 4.0)
			draw_set_transform(c, deg_to_rad(t * 20.0), Vector2.ONE)
			var rect := Rect2(Vector2(-w, -h) * 0.5, Vector2(w, h))
			draw_style_box(shadow, Rect2(rect.position + Vector2(2, 3), rect.size))
			draw_texture_rect(CardTextures.get_texture(str(keys[i])), rect, false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
