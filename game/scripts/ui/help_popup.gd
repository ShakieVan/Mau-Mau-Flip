class_name HelpPopup
extends Control
# Kartenhilfe (AGENTS.md Nr. 18: Karte halten, nach unten auf „?“ ziehen): Großansicht der Karte links, rechts Titel in
# Fraunces und kurzer Hilfetext (BBCode, z. B. [b]…[/b]) in Bricolage, passend zu den aktiven Hausregeln (Text liefert
# RulesText, Modul A). Schließen per Knopf oder Tipp neben die Karte.

signal closed

var _dim: ColorRect
var _panel: PanelContainer
var _card_holder: Control
var _card: CardView
var _title: Label
var _kicker: Label
var _body: RichTextLabel
var _col: VBoxContainer
var _close_btn: PillButton


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_dim = ColorRect.new()
	_dim.color = Color(0.03, 0.04, 0.10, 0.62)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_panel = PanelContainer.new()
	var sb := UiTheme.box(UiPalette.PAPER, Color(UiPalette.INK, 0.12), 2, 34, 34.0, 30.0)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 24
	sb.shadow_offset = Vector2(0, 10)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 34)
	_panel.add_child(row)
	_card_holder = Control.new()
	_card_holder.custom_minimum_size = Vector2(250, 388)
	_card_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_card_holder)
	_card = CardView.new()
	_card.width = 240.0
	_card.position = Vector2(125, 194)
	_card_holder.add_child(_card)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(640, 0)
	col.add_theme_constant_override("separation", 10)
	row.add_child(col)
	_kicker = UiTheme.label("KARTENHILFE", UiFonts.text(800, 100.0), 15, UiPalette.MUTED_DAY)
	col.add_child(_kicker)
	_title = UiTheme.label("", UiFonts.title(800, false, 50.0, 72.0), 46, UiPalette.INK)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(640, 0)
	col.add_child(_title)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true         # Höhe aus dem Text (Breite fest: 640 px)
	_body.scroll_active = false
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.custom_minimum_size = Vector2(640, 0)
	_body.add_theme_font_override("normal_font", UiFonts.text(500, 100.0))
	_body.add_theme_font_override("bold_font", UiFonts.text(800, 100.0))
	_body.add_theme_font_override("italics_font", UiFonts.title(500, true, 50.0, 24.0))
	for k in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		_body.add_theme_font_size_override(k, 24)
	_body.add_theme_color_override("default_color", UiPalette.INK)
	_body.add_theme_constant_override("line_separation", 7)
	col.add_child(_body)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	var close_btn := PillButton.new()
	close_btn.text = "Verstanden"
	close_btn.icon_name = "haken"
	close_btn.style = "primary"
	close_btn.night = 0.0
	close_btn.font_size = UiFonts.px(22)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_btn.pressed.connect(close)
	col.add_child(close_btn)
	_col = col
	_close_btn = close_btn
	_apply_font_sizes()


# Schriftgrößen aus UiFonts (Einstellung „Schriftgröße“); die Textspalte wächst mit, damit der Text nicht zu hoch wird
func _apply_font_sizes() -> void:
	_kicker.add_theme_font_size_override("font_size", UiFonts.px(15))
	_title.add_theme_font_size_override("font_size", UiFonts.px(46))
	for k in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		_body.add_theme_font_size_override(k, UiFonts.size("text"))
	var w := roundf(640.0 * (1.0 + (UiFonts.scale - 1.0) * 0.8))
	for c: Control in [_col, _title, _body]:
		c.custom_minimum_size.x = w
	_close_btn.font_size = UiFonts.px(22)
	_close_btn.text = _close_btn.text   # Breite neu anpassen


func show_help(face: String, title: String, body: String, kicker := "Kartenhilfe") -> void:
	_apply_font_sizes()
	_card.setup(-1, face, "", true)
	_title.text = title
	_kicker.text = kicker.to_upper()
	_body.text = body
	visible = true
	_panel.reset_size()
	_center_panel()
	modulate.a = 0.0
	_panel.scale = Vector2.ONE * 0.94
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.16)
	tw.parallel().tween_property(_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _center_panel() -> void:
	var ps := _panel.get_combined_minimum_size()
	_panel.size = ps
	_panel.position = (size - ps) * 0.5
	_panel.pivot_offset = ps * 0.5


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible:
		_center_panel()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		if not Rect2(_panel.position, _panel.size).has_point(mb.position):
			close()
		accept_event()
