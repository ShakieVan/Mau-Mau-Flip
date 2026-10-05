class_name UiTheme
extends RefCounted
# Oberflächen-Thema „Papier & Neon“ (res://assets/ui/theme.tres): Papierfarben, Fraunces für Überschriften, Bricolage
# Grotesque für Text, große Touch-Ziele (≥ 84 px Höhe ≈ 48 dp auf einem Handy quer, Basis 1600×720 ≈ 800×360 dp …
# 914×411 dp), Knopfstile hell (Papier) und dunkel (Nacht).
# Typvariationen: PrimaryButton (Sonnengelb), DarkButton (Nacht), GhostButton (nur Rand), TitleLabel, HeadingLabel,
# HintLabel, NightLabel, CardPanel (Papierkarte mit Schatten), NightPanel.
# Neu erzeugen: tests/test_ui_table_theme.gd mit SAVE_THEME=1 (godot_run.ps1 -EnvPairs 'SAVE_THEME=1').

const PATH := "res://assets/ui/theme.tres"
const TOUCH_MIN := 84
const RADIUS := 42

static var _theme: Theme


# Gespeichertes Thema laden, sonst im Code bauen
static func get_theme() -> Theme:
	if _theme == null:
		if ResourceLoader.exists(PATH):
			_theme = load(PATH) as Theme
		if _theme == null:
			_theme = build()
	return _theme


static func save() -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PATH.get_base_dir()))
	var t := build()
	return ResourceSaver.save(t, PATH)


static func box(bg: Color, border := Color(0, 0, 0, 0), border_w := 0, radius := RADIUS, mx := 28.0, my := 26.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = mx
	sb.content_margin_right = mx
	sb.content_margin_top = my
	sb.content_margin_bottom = my
	sb.anti_aliasing = true
	return sb


static func _buttons(t: Theme, type: String, bg: Color, fg: Color, border: Color, border_w: int) -> void:
	t.set_stylebox("normal", type, box(bg, border, border_w))
	t.set_stylebox("hover", type, box(bg.lerp(fg, 0.06), border, border_w))
	t.set_stylebox("pressed", type, box(bg.lerp(fg, 0.16), border, border_w))
	t.set_stylebox("hover_pressed", type, box(bg.lerp(fg, 0.16), border, border_w))
	t.set_stylebox("disabled", type, box(Color(bg, bg.a * 0.5), Color(border, border.a * 0.4), border_w))
	var focus := box(Color(0, 0, 0, 0), UiPalette.TURN, 4)
	focus.draw_center = false
	focus.expand_margin_left = 4
	focus.expand_margin_right = 4
	focus.expand_margin_top = 4
	focus.expand_margin_bottom = 4
	t.set_stylebox("focus", type, focus)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		t.set_color(c, type, fg)
	t.set_color("font_disabled_color", type, Color(fg, 0.4))
	t.set_color("icon_disabled_color", type, Color(fg, 0.4))


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = UiFonts.text(600)
	t.default_font_size = 24
	var ink := UiPalette.INK
	var paper := UiPalette.PAPER
	var cream := UiPalette.CREAM
	# Knöpfe
	for type in ["Button", "OptionButton", "MenuButton"]:
		_buttons(t, type, cream, ink, ink, 3)
		t.set_font("font", type, UiFonts.text(700))
		t.set_font_size("font_size", type, 26)
		t.set_constant("h_separation", type, 12)
	t.set_type_variation("PrimaryButton", "Button")
	_buttons(t, "PrimaryButton", UiPalette.FILL["gelb"], ink, ink, 3)
	t.set_type_variation("DarkButton", "Button")
	_buttons(t, "DarkButton", UiPalette.NIGHT_PANEL, paper, Color(paper, 0.35), 2)
	t.set_type_variation("GhostButton", "Button")
	_buttons(t, "GhostButton", Color(ink, 0.05), ink, Color(ink, 0.35), 2)
	# Beschriftungen
	t.set_color("font_color", "Label", ink)
	t.set_font_size("font_size", "Label", 24)
	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", UiFonts.title(800, false, 50.0, 72.0))
	t.set_font_size("font_size", "TitleLabel", 52)
	t.set_type_variation("HeadingLabel", "Label")
	t.set_font("font", "HeadingLabel", UiFonts.title(700, false, 50.0, 48.0))
	t.set_font_size("font_size", "HeadingLabel", 34)
	t.set_type_variation("HintLabel", "Label")
	t.set_color("font_color", "HintLabel", UiPalette.MUTED_DAY)
	t.set_font_size("font_size", "HintLabel", 20)
	t.set_type_variation("NightLabel", "Label")
	t.set_color("font_color", "NightLabel", paper)
	# Flächen
	var card := box(paper, Color(ink, 0.12), 2, 28, 32.0, 28.0)
	card.shadow_color = Color(0, 0, 0, 0.35)
	card.shadow_size = 18
	card.shadow_offset = Vector2(0, 8)
	t.set_stylebox("panel", "PanelContainer", card)
	t.set_stylebox("panel", "Panel", card)
	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", card)
	t.set_type_variation("NightPanel", "PanelContainer")
	var night := box(UiPalette.NIGHT_PANEL, Color(paper, 0.25), 2, 28, 32.0, 28.0)
	night.shadow_color = Color(0, 0, 0, 0.45)
	night.shadow_size = 18
	night.shadow_offset = Vector2(0, 8)
	t.set_stylebox("panel", "NightPanel", night)
	# Eingabefelder
	t.set_stylebox("normal", "LineEdit", box(cream, Color(ink, 0.45), 2, 22, 22.0, 26.0))
	t.set_stylebox("focus", "LineEdit", box(cream, UiPalette.FILL["blau"], 3, 22, 22.0, 26.0))
	t.set_stylebox("read_only", "LineEdit", box(UiPalette.PAPER_D, Color(ink, 0.25), 2, 22, 22.0, 26.0))
	t.set_color("font_color", "LineEdit", ink)
	t.set_color("font_placeholder_color", "LineEdit", Color(ink, 0.45))
	t.set_color("caret_color", "LineEdit", ink)
	t.set_color("selection_color", "LineEdit", Color(UiPalette.FILL["blau"], 0.35))
	t.set_font_size("font_size", "LineEdit", 26)
	# Schalter und Auswahl
	for type in ["CheckBox", "CheckButton"]:
		t.set_color("font_color", type, ink)
		t.set_color("font_hover_color", type, ink)
		t.set_color("font_pressed_color", type, ink)
		t.set_color("font_hover_pressed_color", type, ink)
		t.set_font_size("font_size", type, 24)
		t.set_constant("h_separation", type, 14)
		var empty := StyleBoxEmpty.new()
		empty.content_margin_top = 22
		empty.content_margin_bottom = 22
		empty.content_margin_left = 8
		empty.content_margin_right = 8
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			t.set_stylebox(st, type, empty)
	t.set_stylebox("panel", "PopupMenu", box(paper, Color(ink, 0.2), 2, 20, 12.0, 12.0))
	t.set_color("font_color", "PopupMenu", ink)
	t.set_color("font_hover_color", "PopupMenu", ink)
	t.set_font_size("font_size", "PopupMenu", 24)
	t.set_constant("v_separation", "PopupMenu", 26)
	t.set_stylebox("hover", "PopupMenu", box(UiPalette.PAPER_D, Color(0, 0, 0, 0), 0, 14, 8.0, 8.0))
	t.set_font_size("font_size", "ItemList", 24)
	t.set_constant("v_separation", "ItemList", 20)
	t.set_color("font_color", "ItemList", ink)
	t.set_stylebox("panel", "ItemList", box(cream, Color(ink, 0.2), 2, 20, 10.0, 10.0))
	# Bildlauf und Schieber: breite Griffe
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, box(Color(ink, 0.06), Color(0, 0, 0, 0), 0, 8, 6.0, 6.0))
		t.set_stylebox("grabber", type, box(Color(ink, 0.35), Color(0, 0, 0, 0), 0, 8, 6.0, 6.0))
		t.set_stylebox("grabber_highlight", type, box(Color(ink, 0.5), Color(0, 0, 0, 0), 0, 8, 6.0, 6.0))
		t.set_stylebox("grabber_pressed", type, box(Color(ink, 0.6), Color(0, 0, 0, 0), 0, 8, 6.0, 6.0))
	var slider := box(Color(ink, 0.18), Color(0, 0, 0, 0), 0, 6, 0.0, 6.0)
	t.set_stylebox("slider", "HSlider", slider)
	t.set_stylebox("grabber_area", "HSlider", box(UiPalette.FILL["blau"], Color(0, 0, 0, 0), 0, 6, 0.0, 6.0))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(UiPalette.FILL["blau"], Color(0, 0, 0, 0), 0, 6, 0.0, 6.0))
	# Fließtext (Kartenhilfe, Regeln)
	t.set_font("normal_font", "RichTextLabel", UiFonts.text(500))
	t.set_font("bold_font", "RichTextLabel", UiFonts.text(800))
	t.set_font("italics_font", "RichTextLabel", UiFonts.title(500, true, 50.0, 24.0))
	t.set_font("bold_italics_font", "RichTextLabel", UiFonts.title(800, true, 50.0, 24.0))
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
		t.set_font_size(k, "RichTextLabel", 24)
	t.set_color("default_color", "RichTextLabel", ink)
	t.set_constant("line_separation", "RichTextLabel", 6)
	# Reiter
	t.set_font_size("font_size", "TabBar", 24)
	t.set_stylebox("tab_selected", "TabBar", box(paper, Color(ink, 0.2), 2, 18, 22.0, 18.0))
	t.set_stylebox("tab_unselected", "TabBar", box(UiPalette.PAPER_D, Color(0, 0, 0, 0), 0, 18, 22.0, 18.0))
	t.set_color("font_selected_color", "TabBar", ink)
	t.set_color("font_unselected_color", "TabBar", Color(ink, 0.6))
	# Hinweise
	t.set_stylebox("panel", "TooltipPanel", box(ink, Color(0, 0, 0, 0), 0, 12, 14.0, 10.0))
	t.set_color("font_color", "TooltipLabel", paper)
	return t


# Beschriftung ohne Thema-Abhängigkeit (für Tisch-Overlays)
static func label(text: String, font: Font, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
