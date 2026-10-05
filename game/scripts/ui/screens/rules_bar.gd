class_name RulesBar
extends VBoxContainer
# Regelwahl der Einrichtungen (Übung, Weitergeben, Gastgeber): Voreinstellungen als Auswahlreihe, „Regeln anpassen“ öffnet
# den Regel-Editor. Gespeichert wird immer in App.settings "regeln" (eine Quelle für alle Spielarten).

signal changed(config: RuleConfig)

const PRESETS := [["offiziell", "Offiziell"], ["familie", "Familie"], ["mau_mau", "Mau-Mau"], ["klassisch500", "500 Punkte"]]

var nav: ScreenNav
var _choice: HBoxContainer
var _summary: Label


static func current() -> RuleConfig:
	var d: Variant = UiApp.setting("regeln", {})
	return RuleConfig.from_dict(d if d is Dictionary else {})


static func store(cfg: RuleConfig) -> void:
	var app := UiApp.app()
	var st: Variant = app.get("settings") if app != null else null
	if st is Object and (st as Object).has_method("set_value"):
		(st as Object).call("set_value", "regeln", cfg.to_dict())


# Kurzbeschreibung der aktiven Regeln (eine Zeile)
static func summary(cfg: RuleConfig) -> String:
	var parts: Array[String] = []
	parts.append("bis zum Letzten" if cfg.round_end == "last" else "erster fertig gewinnt")
	if cfg.effective_scoring() == "points500":
		parts.append("Punkte bis %d" % cfg.target)
	if cfg.stacking == "same":
		parts.append("Ziehkarten weitergeben")
	parts.append({"bluff": "Bluffen erlaubt", "enforce": "+2 nur ohne Farbe", "free": "Joker frei"}[cfg.wild_restriction])
	parts.append("%d Karten" % cfg.hand_size)
	parts.append("Rückseiten sichtbar" if cfg.backs_visible else "Rückseiten verdeckt")
	var s := ", ".join(parts)
	return s.substr(0, 1).to_upper() + s.substr(1)


func _init() -> void:
	add_theme_constant_override("separation", 10)


func _ready() -> void:
	var head := ScreenKit.hbox(14)
	add_child(head)
	var l := ScreenKit.label("Regeln", "", 24)
	l.add_theme_font_override("font", UiFonts.text(700))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(l)
	head.add_child(ScreenKit.spacer())
	var edit := ScreenKit.button("Regeln anpassen", "GhostButton", "regeln")
	edit.name = "RegelnAnpassen"
	edit.add_theme_font_size_override("font_size", 21)
	edit.pressed.connect(_open_editor)
	head.add_child(edit)
	_choice = ScreenKit.choice(PRESETS, current().preset_name(), _on_preset, 21)
	for b in _choice.get_children():
		(b as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_choice)
	_summary = ScreenKit.hint("", 18)
	add_child(_summary)
	refresh()


func refresh() -> void:
	var cfg := current()
	ScreenKit.set_choice(_choice, cfg.preset_name())
	var p := cfg.preset_name()
	_summary.text = ("Eigene Regeln: " if p == "" else "") + summary(cfg) + "."


func _on_preset(key: String) -> void:
	var cfg := RuleConfig.preset(key)
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
