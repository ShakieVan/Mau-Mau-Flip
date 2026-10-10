class_name IngameMenu
extends Control
# Menü im Spiel (Beta 1.1.2): kleine Karte (tags Papier, nachts dunkel, 1.1.3) unter dem ☰-Knopf oben links (TableScreen) mit „Einstellungen“, „Regeln ansehen“
# und „So geht's“; beim Gastgeber eines Netzwerkspiels davor „Mitspieler dazuholen“ / „Mitspieler entfernen“ (HOST_ITEMS, Beta 1.4.2).
# Wahl → chosen(key) und schließt; Tipp daneben oder Zurück-Taste (TableScreen.on_back) schließt ohne Wahl.
# Zeigt keine Karten (Regel 15); beim Sichtschutz schließt TableScreen das Menü.

signal chosen(key: String)
signal closed

const ITEMS := [["einstellungen", "Einstellungen"], ["regeln", "Regeln ansehen"], ["bedienung", "So geht's"]]
# Nur beim Gastgeber eines Netzwerkspiels davor (Beta 1.4.2, docs/module/dazuholen.md): Feld „Mitspieler“ (SeatManager)
const HOST_ITEMS := [["dazuholen", "Mitspieler dazuholen"], ["entfernen", "Mitspieler entfernen"]]

var _card: PanelContainer
var night := false


static func open(parent: Node, at: Vector2, items: Array = ITEMS) -> IngameMenu:
	var m := IngameMenu.new()
	m.theme = UiTheme.get_theme()
	parent.add_child(m)
	m._build(at, items)
	TableView.follow_night(m, m.set_night)
	return m


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	name = "MenueImSpiel"


func _build(at: Vector2, items: Array) -> void:
	_card = ScreenKit.card(22.0)
	_card.position = at
	add_child(_card)
	var v := ScreenKit.vbox(12)
	_card.add_child(v)
	for it in items:
		var b := ScreenKit.button(str(it[1]), "GhostButton", "", 360.0)
		b.name = "Wahl_" + str(it[0])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", UiFonts.size("zeile"))
		b.pressed.connect(_choose.bind(str(it[0])))
		v.add_child(b)
	_card.reset_size()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.12)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.1, 0.35))


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if not _card.get_global_rect().has_point(get_global_transform() * mb.position):
			close()
		accept_event()


func _choose(key: String) -> void:
	if is_queued_for_deletion():
		return
	close()
	chosen.emit(key)


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


# Tag/Nacht des Tisches (TableView.follow_night): nachts dunkle Karte mit heller Schrift und hellen Bedienelementen
func set_night(on: bool) -> void:
	night = on
	if _card != null:
		ScreenKit.set_card_night(_card, on)
