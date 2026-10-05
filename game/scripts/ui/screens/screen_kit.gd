class_name ScreenKit
extends RefCounted
# Bausteine der Menübildschirme (Papier & Neon, Thema res://assets/ui/theme.tres): große Knöpfe (≥ 84 px), Überschriften,
# Zahlenwähler, Auswahlreihen, Schalter, Papierkarten. Alles im Code gebaut, damit die Bildschirme ohne .tscn auskommen.

const ICON_DIR := "res://assets/ui/"
const TOUCH := 84.0

static var _icons: Dictionary = {}


# Bediensymbol aus Modul B (96×96, cremefarben; der Knopf färbt es über icon_*_color in der Schriftfarbe ein)
static func icon(name: String) -> Texture2D:
	if name == "":
		return null
	if _icons.has(name):
		return _icons[name]
	var path := ICON_DIR + name + ".png"
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_icons[name] = tex
	return tex


# Gezeichnetes Symbol (UiIcons: "pfeil", "haken", "kreuz" …), cremefarben wie die Symbole aus Modul B, optional gedreht
static func glyph(name: String, px := 40, deg := 0) -> Texture2D:
	var key := "glyph|%s|%d|%d" % [name, px, deg]
	if _icons.has(key):
		return _icons[key]
	var tex := UiIcons.icon(name, px, UiPalette.CREAM)
	if deg != 0 and tex != null:
		var img := tex.get_image()
		img.clear_mipmaps()
		match deg:
			90:
				img.rotate_90(CLOCKWISE)
			-90, 270:
				img.rotate_90(COUNTERCLOCKWISE)
			180:
				img.rotate_180()
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex


# Quadratischer Symbolknopf (84 × 84)
static func icon_button(tex: Texture2D, variation := "GhostButton", tip := "") -> Button:
	var b := button("", variation, "", TOUCH)
	b.icon = tex
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.tooltip_text = tip
	return b


# Knopf; variation: "" (Papier), "PrimaryButton" (Sonnengelb), "DarkButton", "GhostButton"
static func button(text: String, variation := "", icon_name := "", min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(min_w, TOUCH)
	b.focus_mode = Control.FOCUS_NONE
	var tex := icon(icon_name)
	if tex != null:
		b.icon = tex
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 40)
	return b


static func label(text: String, variation := "", size := 0, color := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func title(text: String) -> Label:
	return label(text, "TitleLabel")


static func heading(text: String, size := 30) -> Label:
	var l := label(text, "HeadingLabel")
	l.add_theme_font_size_override("font_size", size)
	return l


static func hint(text: String, size := 20) -> Label:
	var l := label(text, "HintLabel", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func text_block(text: String, size := 22) -> Label:
	var l := label(text, "", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


# Papierkarte mit Innenabstand
static func card(margin := 28.0, night := false) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "NightPanel" if night else "CardPanel"
	var sb: StyleBoxFlat = UiTheme.box(UiPalette.NIGHT_PANEL if night else UiPalette.PAPER, Color(UiPalette.INK, 0.12) if not night else Color(UiPalette.PAPER, 0.25), 2, 28, margin, margin * 0.85)
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 16
	sb.shadow_offset = Vector2(0, 6)
	p.add_theme_stylebox_override("panel", sb)
	return p


static func vbox(sep := 14) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 14) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func spacer(h := true) -> Control:
	var c := Control.new()
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


# Zahlenwähler „−  n  +“; on_change(neuer Wert)
static func stepper(min_v: int, max_v: int, value: int, on_change: Callable, step := 1, unit := "") -> HBoxContainer:
	var row := hbox(10)
	var minus := button("−", "GhostButton", "", TOUCH)
	var plus := button("+", "GhostButton", "", TOUCH)
	var shown := label("", "", 34)
	shown.add_theme_font_override("font", UiFonts.text(800, 100.0))
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shown.custom_minimum_size = Vector2(110 if unit != "" else 64, 0)
	row.add_child(minus)
	row.add_child(shown)
	row.add_child(plus)
	var state := {"v": clampi(value, min_v, max_v)}
	var refresh := func() -> void:
		shown.text = str(state.v) + unit
		minus.disabled = int(state.v) <= min_v
		plus.disabled = int(state.v) >= max_v
	refresh.call()
	minus.pressed.connect(func() -> void:
		state.v = maxi(min_v, int(state.v) - step)
		refresh.call()
		on_change.call(int(state.v)))
	plus.pressed.connect(func() -> void:
		state.v = mini(max_v, int(state.v) + step)
		refresh.call()
		on_change.call(int(state.v)))
	row.set_meta("value", state)
	return row


# Auswahlreihe: options = [[schlüssel, beschriftung], …]; gewählt = Sonnengelb, sonst Papier. on_change(schlüssel)
static func choice(options: Array, value: String, on_change: Callable, font_size := 22, min_w := 0.0) -> HBoxContainer:
	var row := hbox(8)
	var buttons: Array[Button] = []
	for opt in options:
		var key := str(opt[0])
		var b := button(str(opt[1]), "PrimaryButton" if key == value else "GhostButton", "", min_w)
		b.add_theme_font_size_override("font_size", font_size)
		b.set_meta("key", key)
		buttons.append(b)
		row.add_child(b)
	for b in buttons:
		var key := str(b.get_meta("key"))
		b.pressed.connect(func() -> void:
			for o in buttons:
				o.theme_type_variation = "PrimaryButton" if o == b else "GhostButton"
			on_change.call(key))
	return row


# Auswahlreihe nachträglich setzen (ohne Signal)
static func set_choice(row: HBoxContainer, value: String) -> void:
	for b in row.get_children():
		if b is Button and (b as Button).has_meta("key"):
			(b as Button).theme_type_variation = "PrimaryButton" if str(b.get_meta("key")) == value else "GhostButton"


# Schalter mit Beschriftung (CheckButton, ganze Zeile antippbar)
static func switch(text: String, on: bool, on_change: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.custom_minimum_size = Vector2(0, TOUCH)
	c.alignment = HORIZONTAL_ALIGNMENT_LEFT
	c.toggled.connect(func(v: bool) -> void: on_change.call(v))
	return c


# Beschriftete Zeile: links Text (fester Anteil), rechts das Bedienelement
static func row(text: String, control: Control, label_w := 300.0, sub := "") -> HBoxContainer:
	var r := hbox(18)
	var left := vbox(0)
	left.custom_minimum_size = Vector2(label_w, 0)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	var l := label(text, "", 24)
	l.add_theme_font_override("font", UiFonts.text(700))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(l)
	if sub != "":
		left.add_child(hint(sub, 17))
	r.add_child(left)
	r.add_child(control)
	return r


# Runder Avatar (Farbe je Platz, Initiale) als TextureRect-Ersatz
static func avatar(seat: int, name: String, kind := "human", diameter := 52.0) -> Control:
	var a := AvatarDot.new()
	a.seat = seat
	a.initial = name.substr(0, 1).to_upper()
	a.kind = kind
	a.custom_minimum_size = Vector2(diameter, diameter)
	return a


# Bildlauf mit großem Griff, nur senkrecht
static func scroller() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


class AvatarDot:
	extends Control
	var seat := 0
	var initial := ""
	var kind := "human"

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		var c := size * 0.5
		draw_circle(c, r, UiPalette.INK)
		draw_circle(c, r - 3.0, UiPalette.avatar(seat))
		var f := UiFonts.text(800, 100.0)
		var fs := int(r * 0.9)
		var w := f.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, c + Vector2(-w * 0.5, fs * 0.36), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiPalette.INK)
		if kind == "bot":
			var bc := c + Vector2(r * 0.72, r * 0.72)
			draw_circle(bc, r * 0.42, UiPalette.INK)
			var sf := int(r * 0.42)
			var tw := f.get_string_size("KI", HORIZONTAL_ALIGNMENT_LEFT, -1, sf).x
			draw_string(f, bc + Vector2(-tw * 0.5, sf * 0.36), "KI", HORIZONTAL_ALIGNMENT_LEFT, -1, sf, UiPalette.PAPER)


static func clear_cache() -> void:
	_icons.clear()
