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


static func heading(text: String, size := 0) -> Label:
	var l := label(text, "HeadingLabel")
	l.add_theme_font_size_override("font_size", size if size > 0 else UiFonts.size("zwischen"))
	return l


static func hint(text: String, size := 0) -> Label:
	var l := label(text, "HintLabel", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func text_block(text: String, size := 0) -> Label:
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
	p.set_meta("margin", margin)
	return p


# Karte live auf Tag (Papier) oder Nacht (dunkle Karte) stellen (Beta 1.1.3, Überlagerungen im Spiel): Hintergrund und ein
# kleines Nachtthema auf der Karte, das nur Farben ersetzt (Schriften und Größen kommen weiter aus dem Hauptthema, auch live).
static func set_card_night(p: PanelContainer, night: bool) -> void:
	var margin := float(p.get_meta("margin", 28.0))
	p.theme_type_variation = "NightPanel" if night else "CardPanel"
	var sb: StyleBoxFlat = UiTheme.box(UiPalette.NIGHT_PANEL if night else UiPalette.PAPER, Color(UiPalette.PAPER, 0.25) if night else Color(UiPalette.INK, 0.12), 2, 28, margin, margin * 0.85)
	sb.shadow_color = Color(0, 0, 0, 0.45 if night else 0.28)
	sb.shadow_size = 16
	sb.shadow_offset = Vector2(0, 6)
	p.add_theme_stylebox_override("panel", sb)
	p.theme = night_theme() if night else null
	p.set_meta("night", night)


static var _night_theme: Theme

# Farben für Bedienelemente auf einer dunklen Karte: helle Schrift, Geisterknöpfe mit hellem Rand, innere Papierkarten dunkel,
# helle Bildlaufgriffe und Schieberleiste. Sonnengelbe und cremefarbene Knöpfe und die Schalter bleiben hell (gut sichtbar).
# Fehlende Einträge (Schriften, Größen, PrimaryButton, Button) sucht Godot weiter oben im Hauptthema.
static func night_theme() -> Theme:
	if _night_theme != null:
		return _night_theme
	var t := Theme.new()
	var paper := UiPalette.PAPER
	for type in ["Label", "TitleLabel", "HeadingLabel", "NightLabel"]:
		t.set_color("font_color", type, paper)
	t.set_color("font_color", "HintLabel", UiPalette.MUTED_NIGHT)
	UiTheme._buttons(t, "GhostButton", Color(paper, 0.07), paper, Color(paper, 0.45), 2)
	for type in ["CheckBox", "CheckButton"]:
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			t.set_color(c, type, paper)
	var inner := UiTheme.box(Color("#262D5C"), Color(paper, 0.2), 2, 28, 32.0, 28.0)
	for type in ["PanelContainer", "CardPanel"]:
		t.set_stylebox("panel", type, inner)
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, UiTheme.box(Color(paper, 0.08), Color(0, 0, 0, 0), 0, 8, 6.0, 6.0))
		t.set_stylebox("grabber", type, UiTheme.box(Color(paper, 0.4), Color(0, 0, 0, 0), 0, 8, 6.0, 6.0))
		t.set_stylebox("grabber_highlight", type, UiTheme.box(Color(paper, 0.55), Color(0, 0, 0, 0), 0, 8, 6.0, 6.0))
		t.set_stylebox("grabber_pressed", type, UiTheme.box(Color(paper, 0.65), Color(0, 0, 0, 0), 0, 8, 6.0, 6.0))
	t.set_stylebox("slider", "HSlider", UiTheme.box(Color(paper, 0.28), Color(0, 0, 0, 0), 0, 6, 0.0, 6.0))
	_night_theme = t
	return t


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
	var shown := label("", "", UiFonts.size("zahl"))
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
static func choice(options: Array, value: String, on_change: Callable, font_size := 0, min_w := 0.0) -> HBoxContainer:
	var row := hbox(8)
	var buttons: Array[Button] = []
	for opt in options:
		var key := str(opt[0])
		var b := button(str(opt[1]), "PrimaryButton" if key == value else "GhostButton", "", min_w)
		b.add_theme_font_size_override("font_size", font_size if font_size > 0 else UiFonts.size("text"))
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
	style_switch(c)
	c.toggled.connect(func(v: bool) -> void: on_change.call(v))
	return c


# Schalterzeile mit fetter Bezeichnung und Erklärung darunter (links), Schalter rechts; der Schalter heißt switch_name
static func switch_row(text: String, sub: String, on: bool, on_change: Callable, switch_name := "") -> HBoxContainer:
	var c := CheckButton.new()
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.custom_minimum_size = Vector2(TOUCH * 1.4, TOUCH)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if switch_name != "":
		c.name = switch_name
	style_switch(c)
	c.toggled.connect(func(v: bool) -> void: on_change.call(v))
	var r := row(text, c, 0.0, sub)
	(r.get_child(0) as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


# Großer Schalter im Stil Papier & Neon statt des kleinen Standardsymbols (auf den Bildschirmfotos der Beta kaum zu treffen):
# aus = Papierkante mit Knopf links, an = Sonnengelb mit Knopf rechts; ausgegraut halb durchsichtig.
const SWITCH_SIZE := Vector2i(88, 48)

static func style_switch(c: CheckButton) -> void:
	for on in [true, false]:
		for dis in [false, true]:
			var tex := switch_icon(on, dis)
			var base := ("checked" if on else "unchecked") + ("_disabled" if dis else "")
			c.add_theme_icon_override(base, tex)
			c.add_theme_icon_override(base + "_mirrored", tex)


static func switch_icon(on: bool, disabled := false) -> Texture2D:
	var key := "schalter|%s|%s" % [on, disabled]
	if _icons.has(key):
		return _icons[key]
	var w := SWITCH_SIZE.x
	var h := SWITCH_SIZE.y
	var a := 0.45 if disabled else 1.0
	var r := h * 0.5
	var track: Color = UiPalette.FILL["gelb"] if on else UiPalette.PAPER_D
	var ink := UiPalette.INK.to_html(false)
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\">" % [w, h, w, h]
	svg += "<rect x=\"2\" y=\"2\" width=\"%d\" height=\"%d\" rx=\"%.1f\" fill=\"#%s\" fill-opacity=\"%.2f\" stroke=\"#%s\" stroke-opacity=\"%.2f\" stroke-width=\"3\"/>" \
		% [w - 4, h - 4, r - 2.0, track.to_html(false), a, ink, (0.9 if on else 0.45) * a]
	var kx := w - r if on else r
	svg += "<circle cx=\"%.1f\" cy=\"%.1f\" r=\"%.1f\" fill=\"#%s\" fill-opacity=\"%.2f\" stroke=\"#%s\" stroke-opacity=\"%.2f\" stroke-width=\"3\"/>" \
		% [kx, r, r - 8.0, UiPalette.CREAM.to_html(false), a, ink, (0.9 if on else 0.55) * a]
	svg += "</svg>"
	var img := Image.new()
	var tex: Texture2D = null
	if img.load_svg_from_string(svg, 1.0) == OK:
		tex = ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex


# Beschriftete Zeile: links Text (fester Anteil), rechts das Bedienelement
static func row(text: String, control: Control, label_w := 300.0, sub := "") -> HBoxContainer:
	var r := hbox(18)
	var left := vbox(0)
	left.custom_minimum_size = Vector2(label_w, 0)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	var l := label(text, "", UiFonts.size("zeile"))
	l.add_theme_font_override("font", UiFonts.text(700))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(l)
	if sub != "":
		left.add_child(hint(sub, UiFonts.size("klein")))
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


# Bildlauf mit großem Griff, nur senkrecht; am Touchscreen auch per Wischen über den Inhalt (TouchScroll)
static func scroller() -> ScrollContainer:
	var s := TouchScroll.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


# Ein Bedienelement im Bildlauf reicht Druck und Bewegung an den ScrollContainer weiter (MOUSE_FILTER_PASS), damit er die
# Wischgeste bekommt. Betrifft Karten (PanelContainer hält sonst alles fest), Zeilen und Knöpfe. Ein Knopf löst nicht aus, sobald
# der Bildlauf begonnen hat (Godot meldet NOTIFICATION_SCROLL_BEGIN, BaseButton bricht den Druck ab). Eingabefelder,
# Schieberegler und innere Bildläufe behalten ihre eigenen Gesten.
static func let_scroll(c: Control) -> void:
	if c.mouse_filter != Control.MOUSE_FILTER_STOP:
		return
	if c is LineEdit or c is TextEdit or c is Range or c is ScrollContainer or c is ItemList or c is Tree or c is GraphEdit:
		return
	if c is Container or c is Panel or c is BaseButton or c is ColorRect or c is TextureRect or c is Label or c is RichTextLabel:
		c.mouse_filter = Control.MOUSE_FILTER_PASS


class TouchScroll:
	extends ScrollContainer
	# ScrollContainer, der am Touchscreen auch per Wischen über Karten und Knöpfe blättert (Gerätetest 0.1.1, M2: vorher nur über
	# den schmalen Scrollbalken). Alles, was in ihm landet – auch später, etwa neu aufgebaute Spielerlisten –, bekommt
	# ScreenKit.let_scroll. Die Totzone verhindert, dass ein leicht zitternder Tipp schon als Wischen gilt und den Knopf abbricht.
	const DEADZONE := 14

	func _init() -> void:
		scroll_deadzone = DEADZONE

	func _enter_tree() -> void:
		var tree := get_tree()
		if not tree.node_added.is_connected(_on_node_added):
			tree.node_added.connect(_on_node_added)
		_adopt(self)

	func _exit_tree() -> void:
		var tree := get_tree()
		if tree != null and tree.node_added.is_connected(_on_node_added):
			tree.node_added.disconnect(_on_node_added)

	func _on_node_added(n: Node) -> void:
		if n is Control and is_ancestor_of(n):
			ScreenKit.let_scroll(n as Control)

	func _adopt(n: Node) -> void:
		for c in n.get_children():
			if c is Control:
				ScreenKit.let_scroll(c as Control)
				if not (c is ScrollContainer):
					_adopt(c)


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
			var sf := maxi(int(r * 0.42), UiFonts.size("mini"))
			ScreenKit.draw_bot_badge(self, bc, maxf(r * 0.42, sf * 0.85))


# Symbol in einer anderen Farbe (Alpha bleibt), z. B. der helle Roboterkopf im dunklen Abzeichen der Computergegner
static var _tinted := {}


static func icon_tinted(name: String, col: Color) -> Texture2D:
	var key := name + "|" + col.to_html()
	if _tinted.has(key):
		return _tinted[key]
	var src := icon(name)
	if src == null:
		return null
	var img := src.get_image()
	if img == null:
		return src
	img = img.duplicate()
	img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				img.set_pixel(x, y, Color(col.r, col.g, col.b, c.a))
	var tex := ImageTexture.create_from_image(img)
	_tinted[key] = tex
	return tex


# Abzeichen „Computergegner“: Roboterkopf statt „KI“ (Nutzerwunsch 07.10.2026: manche Menschen haben Angst vor KI)
static func draw_bot_badge(ci: CanvasItem, center: Vector2, radius: float) -> void:
	ci.draw_circle(center, radius, UiPalette.INK)
	var tex := icon_tinted("roboter", UiPalette.PAPER)
	if tex != null:
		var s := radius * 1.45
		ci.draw_texture_rect(tex, Rect2(center - Vector2(s, s) * 0.5, Vector2(s, s)), false)


static func clear_cache() -> void:
	_icons.clear()
	_tinted.clear()
