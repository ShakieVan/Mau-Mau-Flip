class_name IngameSettings
extends Control
# Persönliche Einstellungen im Spiel (Beta 1.1.2, ☰ → „Einstellungen“): Überlagerung über dem Tisch, die Partie läuft weiter.
# Dieselben Zeilen wie im Einstellungsbildschirm (SettingsScreen.personal: Ton, Schrift, großer Modus, Hervorheben, Vibration,
# Effekte, Tempo der Computergegner nur mit Computergegnern). Jede Änderung landet sofort in App.settings und wirkt live am Tisch.
# Papierkarte auch nachts (die Bedienelemente sind für Papier gestaltet). Schließen per Knopf, Tipp daneben oder Zurück-Taste
# (TableScreen.on_back). Keine Karten (Regel 15).

signal closed

var _card: PanelContainer


static func open(parent: Node, tempo := false) -> IngameSettings:
	var o := IngameSettings.new()
	o.theme = UiTheme.get_theme()
	parent.add_child(o)
	o._build(tempo)
	return o


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	name = "EinstellungenImSpiel"


func _build(tempo: bool) -> void:
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 90)
	for side in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 24)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	_card = ScreenKit.card(26.0)
	m.add_child(_card)
	var v := ScreenKit.vbox(12)
	_card.add_child(v)
	var head := ScreenKit.hbox(12)
	v.add_child(head)
	head.add_child(ScreenKit.heading("Einstellungen", UiFonts.size("dialog")))
	head.add_child(ScreenKit.spacer())
	var close_btn := ScreenKit.button("Schließen", "PrimaryButton", "kreuz")
	close_btn.name = "Schliessen"
	close_btn.pressed.connect(close)
	head.add_child(close_btn)
	var scroll := ScreenKit.scroller()
	scroll.name = "Inhalt"
	v.add_child(scroll)
	var cols := ScreenKit.hbox(30)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cols)
	var left := ScreenKit.vbox(16)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var right := ScreenKit.vbox(16)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var section := func(_p: Control, title: String) -> VBoxContainer:
		var sec := ScreenKit.vbox(12)
		sec.name = "Abschnitt"
		sec.add_child(ScreenKit.heading(title, UiFonts.size("zwischen")))
		(left if title == "Ton" else right).add_child(sec)
		return sec
	SettingsScreen.personal(cols, section, tempo)
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


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()
