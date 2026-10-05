class_name WlanScreen
extends AppScreen
# „Im WLAN spielen“: eigener Name (oben, wegen der Bildschirmtastatur), dann „Spiel eröffnen“ (Gastgeber) oder „Beitreten“.

var _name: LineEdit


func build() -> void:
	var content := page("Im WLAN spielen")
	var name_row := ScreenKit.hbox(16)
	content.add_child(name_row)
	var l := ScreenKit.label("Dein Name", "", 26)
	l.add_theme_font_override("font", UiFonts.text(700))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(l)
	_name = LineEdit.new()
	_name.name = "Name"
	_name.text = str(UiApp.setting("name", ""))
	_name.placeholder_text = "So sehen dich die anderen"
	_name.max_length = AppSettings.NAME_MAX
	_name.custom_minimum_size = Vector2(460, ScreenKit.TOUCH)
	_name.text_changed.connect(_on_name)
	_name.text_submitted.connect(func(_t: String) -> void: _name.release_focus())
	name_row.add_child(_name)
	var cols := ScreenKit.hbox(28)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cols)
	cols.add_child(_choice_card("Spiel eröffnen", "Du bist Gastgeber. Mitspieler kommen per App über die Suche oder ohne App per QR-Code im Browser dazu – auch iPhones.", "qr", "PrimaryButton", "Eröffnen", _host))
	cols.add_child(_choice_card("Beitreten", "Ein Spiel in der Nähe suchen oder die Adresse des Gastgebers eingeben. Alle müssen im selben WLAN sein.", "wlan", "", "Suchen", _join))


func _choice_card(title_text: String, text: String, icon_name: String, variation: String, button_text: String, action: Callable) -> Control:
	var card := ScreenKit.card(30.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := ScreenKit.vbox(16)
	card.add_child(v)
	var head := ScreenKit.hbox(16)
	v.add_child(head)
	var ic := TextureRect.new()
	ic.texture = ScreenKit.icon(icon_name)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(56, 56)
	ic.modulate = UiPalette.INK
	head.add_child(ic)
	head.add_child(ScreenKit.heading(title_text, 36))
	v.add_child(ScreenKit.text_block(text, 22))
	v.add_child(ScreenKit.spacer(false))
	var b := ScreenKit.button(button_text, variation, "start")
	b.name = button_text
	b.custom_minimum_size = Vector2(0, 96)
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(action)
	v.add_child(b)
	return card


func _on_name(t: String) -> void:
	var app := UiApp.app()
	var st: Variant = app.get("settings") if app != null else null
	if st is Object:
		(st as Object).call("set_value", "name", AppSettings.clean_name(t))


func my_name() -> String:
	var n := AppSettings.clean_name(_name.text)
	if n != "":
		return n
	var app := UiApp.app()
	var st: Variant = app.get("settings") if app != null else null
	if st is Object and (st as Object).has_method("player_name"):
		return str((st as Object).call("player_name"))
	return "Gastgeber"


func _host() -> void:
	nav.push(HostLobbyScreen.new())


func _join() -> void:
	nav.push(JoinScreen.new())
