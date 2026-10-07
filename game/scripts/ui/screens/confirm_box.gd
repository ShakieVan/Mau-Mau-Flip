class_name ConfirmBox
extends Control
# Rückfrage als Papierkarte über abgedunkeltem Hintergrund („Partie verlassen?“). Tipp daneben = Abbrechen.

signal answered(yes: bool)

var _card: PanelContainer
var _box: VBoxContainer
var _row: HBoxContainer


static func ask(parent: Node, title_text: String, text: String, yes_text: String, no_text: String) -> ConfirmBox:
	var box := ConfirmBox.new()
	box.theme = UiTheme.get_theme()
	parent.add_child(box)
	box._build(title_text, text, yes_text, no_text)
	return box


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	name = "Rueckfrage"


func _build(title_text: String, text: String, yes_text: String, no_text: String) -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = ScreenKit.card(34.0)
	_card.custom_minimum_size = Vector2(620, 0)
	center.add_child(_card)
	var v := ScreenKit.vbox(18)
	_card.add_child(v)
	_box = v
	v.add_child(ScreenKit.heading(title_text, UiFonts.size("dialog")))
	if text != "":
		v.add_child(ScreenKit.text_block(text, UiFonts.size("text")))
	var row := ScreenKit.hbox(16)
	_row = row
	v.add_child(row)
	var no := ScreenKit.button(no_text, "")
	no.name = "Nein"
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.pressed.connect(_answer.bind(false))
	row.add_child(no)
	var yes := ScreenKit.button(yes_text, "PrimaryButton")
	yes.name = "Ja"
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes.pressed.connect(_answer.bind(true))
	row.add_child(yes)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.1, 0.55))


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if not _card.get_global_rect().has_point(get_global_transform() * mb.position):
			_answer(false)
		accept_event()


# Zusätzliche Wahl über den beiden Antworten (ganze Breite, Papier-Knopf), z. B. „Regeln speichern“ im Spielmenü des Gastes. Der
# Aufrufer verbindet pressed; die Rückfrage bleibt dabei offen, bis er sie schließt (cancel()).
func add_option(text: String, icon_name := "") -> Button:
	var b := ScreenKit.button(text, "GhostButton", icon_name)
	b.name = "Wahl%d" % _box.get_child_count()
	_box.add_child(b)
	_box.move_child(b, _row.get_index())
	return b


# Wie „Nein“ (z. B. Zurück-Taste bei offener Rückfrage)
func cancel() -> void:
	_answer(false)


func _answer(yes: bool) -> void:
	if is_queued_for_deletion():
		return
	answered.emit(yes)
	queue_free()
