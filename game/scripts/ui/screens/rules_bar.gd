class_name RulesBar
extends VBoxContainer
# Regelwahl der Einrichtungen (Übung, Weitergeben, Gastgeber): Voreinstellungen als Auswahlreihe, „Regeln anpassen“ öffnet
# den Regel-Editor. Gespeichert wird immer in App.settings "regeln" (eine Quelle für alle Spielarten).
# compact (vor dem Einhängen setzen, Gastgeber-Lobby): nur eine Zeile – Knopf „Regeln“ (öffnet den Editor mit den
# Voreinstellungen), daneben fett „Familie · 116 Karten“ und darunter die Kurzbeschreibung (höchstens 2 Zeilen, Hausregeln mit
# Zusatzkarten vorn). So bleibt Platz für die Spielerliste (Gerätetest 0.1.1, N2).
# Entsprechen die Regeln einem gespeicherten Satz (RuleSets), steht dessen Name statt „Eigene Regeln“ da (title()).
# Voll (Übung, Weitergeben): unter den Voreinstellungen der Knopf „Gespeichert“ (nur wenn es Sätze oder den Gastgeber-Platz gibt).
# Er zeigt sonnengelb den Namen des passenden Satzes („Gespeichert: Oma-Regeln“) und öffnet RuleSetPicker zum direkten Wählen.
# Kompakt (Gastgeber-Lobby): Weichen die Regeln vom Gastgeber-Platz ab, steht unter dem Regelkopf statt der Kurzbeschreibung
# der Knopf „Regeln von Lena übernehmen“ (WLAN-Symbol, übernimmt sie; mit × zum Ausblenden). So setzt, wer nach dem Weggang des Gastgebers neu eröffnet, die Partie mit
# einem Tipp mit denselben Regeln fort.

signal changed(config: RuleConfig)

const PRESETS := [["offiziell", "Offiziell"], ["familie", "Familie"], ["mau_mau", "Mau-Mau"], ["klassisch500", "500 Punkte"]]
# Hausregeln mit Zusatzkarten in fester Reihenfolge: [Schlüssel, Name]
const EXTRAS := [["swap_cards", "Kartentausch"], ["gamble_cards", "Glücksspiel"], ["discard_color", "Farbe ablegen"]]

var nav: ScreenNav
var compact := false
var _choice: HBoxContainer
var _summary: Label
var _head: Label
var _edit: Button
var _saved_btn: Button              # voll: „Gespeichert“ (RuleSetPicker)
var _picker: RuleSetPicker
var _offer: HBoxContainer           # kompakt: Knopf „Regeln von Lena“ (übernehmen)
var _offer_btn: Button
var _offer_hidden := false


static func current() -> RuleConfig:
	var d: Variant = UiApp.setting("regeln", {})
	return RuleSets.load_config(d)


static func store(cfg: RuleConfig) -> void:
	var app := UiApp.app()
	var st: Variant = app.get("settings") if app != null else null
	if st is Object and (st as Object).has_method("set_value"):
		(st as Object).call("set_value", "regeln", cfg.to_dict())


# Namen der eingeschalteten Hausregeln mit Zusatzkarten, z. B. ["Kartentausch", "Glücksspiel"]
static func extra_names(cfg: RuleConfig) -> Array[String]:
	var out: Array[String] = []
	for e in EXTRAS:
		if str(cfg.get(e[0])) == "on":
			out.append(I18n.t(str(e[1])))
	return out


# „A“, „A und B“, „A, B und C“
static func join_and(items: Array[String]) -> String:
	if items.size() <= 1:
		return "" if items.is_empty() else items[0]
	return I18n.t("%s und %s") % [", ".join(PackedStringArray(items.slice(0, items.size() - 1))), items[-1]]


# Zusatzkarten als Satzteil: „mit Kartentausch und Glücksspiel (118 Karten)“; "" ohne Hausregel-Karten
static func extras_text(cfg: RuleConfig) -> String:
	var names := extra_names(cfg)
	if names.is_empty():
		return ""
	return I18n.t("mit %s (%d Karten)") % [join_and(names), cfg.card_count()]


# Name der Voreinstellung bzw. „Eigene Regeln“
static func preset_title(cfg: RuleConfig) -> String:
	var p := cfg.preset_name()
	for opt in PRESETS:
		if opt[0] == p:
			return I18n.t(str(opt[1]))
	return I18n.t("Eigene Regeln")


# Wie preset_title, kennt aber auch die gespeicherten Sätze dieses Geräts (RuleSets): Voreinstellung → eigener Satz („Oma-Regeln“)
# → Regeln des letzten Gastgebers („Zuletzt gespielt bei Lena“) → „Eigene Regeln“. Für die eigenen Regeln (Einrichtungen,
# Gastgeber-Lobby); die Gast-Lobby zeigt fremde Regeln und bleibt bei preset_title.
static func title(cfg: RuleConfig) -> String:
	if cfg.preset_name() != "":
		return preset_title(cfg)
	var saved := RuleSets.match_name(cfg)
	if saved != "":
		return saved
	if RuleSets.host_matches(cfg):
		return RuleSets.host_title(RuleSets.host_name())
	return I18n.t("Eigene Regeln")


# Kurzbeschreibung der aktiven Regeln (eine Zeile). extras_first (Lobby, Text wird nach 2 Zeilen gekürzt): die Hausregeln mit
# Zusatzkarten vorn und ohne Kartenzahl (die steht dort in der Kopfzeile).
static func summary(cfg: RuleConfig, extras_first := false) -> String:
	var parts: Array[String] = []
	var names := extra_names(cfg)
	if extras_first and not names.is_empty():
		parts.append(I18n.t("mit %s") % join_and(names))
	parts.append(I18n.t("bis zum Letzten") if cfg.round_end == "last" else I18n.t("erster fertig gewinnt"))
	if cfg.effective_scoring() == "points500":
		parts.append(I18n.t("Punkte bis %d") % cfg.target)
	if cfg.stacking == "same":
		parts.append(_lc(I18n.t("Ziehkarten weitergeben")))
	if cfg.penalty_turn == "play":
		parts.append(I18n.t("nach Strafziehen weiterspielen"))
	if cfg.draw_play == "any" and cfg.draw_rule == "one":
		parts.append(I18n.t("nach dem Ziehen beliebige Karte legen"))
	parts.append(I18n.t({"bluff": "Bluffen erlaubt", "enforce": "+2 nur ohne Farbe", "free": "Wünscher +2 immer erlaubt"}[cfg.wild_restriction]))
	if str(cfg.get("flip_surprise")) == "on":
		parts.append(I18n.t("Flip-Überraschung"))
	parts.append(I18n.t("%d Handkarten") % cfg.hand_size)
	parts.append(I18n.t("Rückseiten sichtbar") if cfg.backs_visible else I18n.t("Rückseiten verdeckt"))
	var extras := extras_text(cfg)
	if extras != "" and not extras_first:
		parts.append(extras)
	var s := ", ".join(parts)
	return s.substr(0, 1).to_upper() + s.substr(1)


func _init() -> void:
	add_theme_constant_override("separation", 10)


func _ready() -> void:
	if compact:
		_build_compact()
	else:
		_build_full()
	refresh()


func _build_full() -> void:
	var head := ScreenKit.hbox(14)
	add_child(head)
	var l := ScreenKit.label("Regeln", "", UiFonts.size("zeile"))
	l.add_theme_font_override("font", UiFonts.text(700))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(l)
	head.add_child(ScreenKit.spacer())
	_edit = ScreenKit.button("Regeln anpassen", "GhostButton", "regeln")
	_edit.name = "RegelnAnpassen"
	_edit.add_theme_font_size_override("font_size", UiFonts.size("text"))
	_edit.pressed.connect(_open_editor)
	head.add_child(_edit)
	_choice = ScreenKit.choice(PRESETS, current().preset_name(), _on_preset, UiFonts.px(21))   # vier Knöpfe in einer Reihe: etwas kleiner
	for b in _choice.get_children():
		(b as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_choice)
	_saved_btn = ScreenKit.button("", "GhostButton", "regeln")
	_saved_btn.name = "Gespeichert"
	_saved_btn.add_theme_font_size_override("font_size", UiFonts.size("text"))
	_saved_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_saved_btn.pressed.connect(open_picker)
	add_child(_saved_btn)
	_summary = ScreenKit.hint("", UiFonts.size("hinweis"))
	add_child(_summary)


func _build_compact() -> void:
	var row := ScreenKit.hbox(16)
	add_child(row)
	_edit = ScreenKit.button("Regeln", "GhostButton", "regeln")
	_edit.name = "RegelnAnpassen"
	_edit.tooltip_text = "Regeln anpassen"
	_edit.add_theme_font_size_override("font_size", UiFonts.size("text"))
	_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_edit.pressed.connect(_open_editor)
	row.add_child(_edit)
	var texts := ScreenKit.vbox(0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(texts)
	_head = ScreenKit.label("", "", UiFonts.px(22))   # Lobby: fünf Spieler müssen über der Regelzeile ganz sichtbar bleiben
	_head.name = "RegelnKopf"
	_head.add_theme_font_override("font", UiFonts.text(800))
	texts.add_child(_head)
	_summary = ScreenKit.hint("", UiFonts.size("klein"))
	_summary.max_lines_visible = 2
	_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(_summary)
	# Angebot: Regeln des letzten Gastgebers übernehmen. Steht statt der Kurzbeschreibung unter dem Regelkopf, damit die
	# Spielerliste der Lobby nicht schrumpft (5 Spieler bleiben ganz sichtbar, N2).
	_offer = ScreenKit.hbox(8)
	_offer.name = "Angebot"
	texts.add_child(_offer)
	_offer_btn = ScreenKit.button("", "GhostButton", "wlan")
	_offer_btn.name = "Uebernehmen"
	_offer_btn.add_theme_font_size_override("font_size", UiFonts.size("hinweis"))
	_offer_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_offer_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_offer_btn.pressed.connect(adopt_host_rules)
	_offer.add_child(_offer_btn)
	var dismiss := ScreenKit.icon_button(ScreenKit.glyph("kreuz", 30), "GhostButton", "Ausblenden")
	dismiss.name = "Ausblenden"
	dismiss.pressed.connect(func() -> void:
		_offer_hidden = true
		refresh())
	_offer.add_child(dismiss)


func refresh() -> void:
	var cfg := current()
	if _choice != null:
		ScreenKit.set_choice(_choice, cfg.preset_name())
	var p := cfg.preset_name()
	if compact:
		_head.text = "%s · %s" % [title(cfg), I18n.t("%d Karten") % cfg.card_count()]
		_summary.text = summary(cfg, true) + "."
		var host := RuleSets.host_name()
		_offer.visible = not _offer_hidden and host != "" and not RuleSets.host_matches(cfg)
		_summary.visible = not _offer.visible
		_offer_btn.text = I18n.t("Von %s übernehmen") % host      # kurz (N7: am S10 abgeschnitten); WLAN-Symbol zeigt die Herkunft, lange Namen enden mit …
		_offer_btn.tooltip_text = I18n.t("Mit den Regeln weiterspielen, mit denen du zuletzt bei %s gespielt hast") % host
		return
	# Voll: Knopf „Gespeichert“ mit dem Namen des passenden Satzes bzw. des Gastgeber-Platzes
	var saved := RuleSets.match_name(cfg)
	if saved == "" and RuleSets.host_matches(cfg):
		saved = RuleSets.host_title(RuleSets.host_name())
	var any := RuleSets.count() > 0 or RuleSets.host_name() != ""
	_saved_btn.visible = any
	_saved_btn.theme_type_variation = "PrimaryButton" if saved != "" else "GhostButton"
	_saved_btn.text = (I18n.t("Gespeichert: %s") % saved) if saved != "" else I18n.t("Gespeicherte Regeln …")
	var named := p != "" or (any and saved != "")
	_summary.text = ("" if named else title(cfg) + ": ") + summary(cfg) + "."


func _on_preset(key: String) -> void:
	var cfg := RuleConfig.preset(key)
	RuleSets.choose("")
	store(cfg)
	refresh()
	changed.emit(cfg)


# Voll: gespeicherte Sätze direkt wählen
func open_picker() -> void:
	if _picker != null and is_instance_valid(_picker):
		return
	var parent: Node = nav.top() if nav != null and nav.top() != null else get_tree().root
	_picker = RuleSetPicker.ask(parent, current())
	_picker.picked.connect(func(cfg: RuleConfig, set_name: String) -> void:
		_picker = null
		_apply(cfg, set_name))
	_picker.cancelled.connect(func() -> void: _picker = null)


# Offener Auswahldialog (Zurück-Taste der Einrichtung schließt ihn zuerst); true = war offen
func close_picker() -> bool:
	if _picker != null and is_instance_valid(_picker):
		_picker.cancel()
		_picker = null
		return true
	return false


# Kompakt: Regeln des letzten Gastgebers übernehmen
func adopt_host_rules() -> void:
	var c := RuleSets.host_config()
	if c != null:
		_apply(c, "")


func _apply(cfg: RuleConfig, set_name: String) -> void:
	RuleSets.choose(set_name)
	store(cfg)
	refresh()
	changed.emit(cfg)


func _open_editor() -> void:
	if nav == null:
		return
	var r := RulesScreen.new()
	r.start_tab = "anpassen"
	r.closed.connect(func() -> void:
		refresh()
		changed.emit(current()))
	nav.push(r)


# Englisch: Teil mitten im Satz klein beginnen (die Beschriftung der Regel selbst beginnt groß)
static func _lc(s: String) -> String:
	return s.substr(0, 1).to_lower() + s.substr(1) if I18n.english() else s
