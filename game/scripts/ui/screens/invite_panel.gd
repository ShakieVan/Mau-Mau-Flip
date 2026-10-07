class_name InvitePanel
extends VBoxContainer
# „Mitspieler einladen“ (linke Seite der Gastgeber-Lobby, Beta 1.0.2): „① WLAN“ (GameWifiPanel) und „② Spiel“ nebeneinander, je
# mit QR-Code und einem Satz Anleitung. ② zeigt die Spieladresse (QR-Code und Text) und den Hinweis für App-Gäste; ohne Netz
# „Noch kein WLAN aktiv“. Der nächste offene Schritt leuchtet (Wellen vom Rand nach innen, pulsierend; Effekte reduziert: ruhiger
# Leuchtrand), erledigte Schritte tragen einen grünen Haken (Logik in InviteSteps).

const GLOW_COLOR := Color("#F59E1B")
const DONE_COLOR := Color("#2E9E6A")

var host: HostTable
var steps := InviteSteps.new()
var port_error := false
var wifi: GameWifiPanel                  # Inhalt von ①
var glows: Array[Glow] = []
var checks: Array[Control] = []
var _qr: TextureRect
var _qr_text := ""
var _url: Label
var _url_hint: Label
var _app_hint: Label
var _no_net: VBoxContainer


func _init() -> void:
	name = "Einladen"
	add_theme_constant_override("separation", 12)


func setup(host_table: HostTable, port_failed := false) -> void:
	host = host_table
	port_error = port_failed
	var head := ScreenKit.heading("Mitspieler einladen", UiFonts.size("zwischen"))
	add_child(head)
	var row := ScreenKit.hbox(20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(row)
	wifi = GameWifiPanel.new()
	row.add_child(_step_card(1, "WLAN", wifi))
	row.add_child(_step_card(2, "Spiel", _build_step2()))
	wifi.changed.connect(_on_net)
	wifi.setup(host)
	# „Spiel-WLAN schließen“ in die Kopfzeile von ① (spart Höhe bei großer Schrift)
	var stop := wifi.find_child("Schliessen", true, false) as Button
	var head1 := checks[0].get_parent()
	stop.reparent(head1)
	head1.move_child(stop, checks[0].get_index())
	stop.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if host != null and host.session != null:
		host.session.page_visited.connect(func(_a: String) -> void:
			steps.page_visited()
			apply())


# Anzahl Mitspieler (ohne Gastgeber und Computer) aus der Lobby
func set_guests(n: int) -> void:
	steps.set_guests(n)
	apply()


func _on_net() -> void:
	var url := "" if port_error else wifi.game_url()
	steps.set_net(url != "", wifi.mode)
	_url.text = url.trim_prefix("http://").trim_suffix("/")
	_qr.visible = url != ""
	_url.get_parent().visible = url != ""
	_no_net.visible = url == ""
	if url != _qr_text:
		_qr_text = url
		_qr.texture = null
		if url != "":
			var code := QrCode.encode(url)
			if code != null:
				_qr.texture = code.to_texture(8, 3, UiPalette.INK, Color.WHITE)
	apply()


# Leuchten und Haken nach InviteSteps
func apply() -> void:
	var g := steps.glow()
	var reduced := UiApp.reduced_effects()
	for i in glows.size():
		glows[i].reduced = reduced
		glows[i].active = g == i + 1
	checks[0].visible = steps.step1_done()
	checks[1].visible = steps.step2_done()


func game_url() -> String:
	return _qr_text


func _build_step2() -> Control:
	var body := ScreenKit.vbox(12)
	body.name = "Spiel"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var row := ScreenKit.hbox(18)
	body.add_child(row)
	_qr = TextureRect.new()
	_qr.name = "QR"
	_qr.custom_minimum_size = Vector2(GameWifiPanel.QR_SIZE, GameWifiPanel.QR_SIZE)
	_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_qr.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_qr)
	var v := ScreenKit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	_url_hint = ScreenKit.text_block("Kamera auf den Code halten oder die Adresse im Browser eintippen:", UiFonts.size("text"))
	v.add_child(_url_hint)
	_url = ScreenKit.label("", "", UiFonts.size("zeile"))
	_url.name = "Adresse"
	_url.add_theme_font_override("font", UiFonts.text(800, 90.0))
	_url.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	v.add_child(_url)
	_app_hint = ScreenKit.hint("Mit der App? Einfach „Beitreten“ antippen.", UiFonts.size("hinweis"))
	_app_hint.name = "AppHinweis"
	v.add_child(_app_hint)
	_no_net = ScreenKit.vbox(8)
	_no_net.name = "KeinNetz"
	_no_net.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_no_net)
	var l := ScreenKit.label("Kein freier Port" if port_error else "Noch kein WLAN aktiv", "", UiFonts.size("zeile"))
	l.add_theme_font_override("font", UiFonts.text(800))
	_no_net.add_child(l)
	_no_net.add_child(ScreenKit.hint("Bitte die App neu starten." if port_error else "Sobald bei ① ein WLAN da ist, erscheint hier der Code zum Spiel.",
		UiFonts.size("hinweis")))
	return body


func _step_card(n: int, title_text: String, body: Control) -> Control:
	var slot := MarginContainer.new()
	slot.name = "Schritt%d" % n
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot.size_flags_stretch_ratio = 1.0
	var card := ScreenKit.card(22.0)
	slot.add_child(card)
	var v := ScreenKit.vbox(12)
	card.add_child(v)
	var head := ScreenKit.hbox(12)
	v.add_child(head)
	head.add_child(Badge.make(n))
	var t := ScreenKit.heading(title_text, UiFonts.size("abschnitt"))
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(t)
	head.add_child(ScreenKit.spacer())
	var chk := Check.new()
	chk.name = "Haken"
	chk.visible = false
	head.add_child(chk)
	checks.append(chk)
	v.add_child(body)
	var glow := Glow.new()
	glow.name = "Leuchten"
	slot.add_child(glow)
	glows.append(glow)
	return slot


# Leuchtrand des nächsten Schritts: Linien vom Rand nach innen, deren Helligkeit als Welle nach innen läuft; reduziert: ein ruhiger Rand
class Glow:
	extends Control
	var active := false:
		set(v):
			active = v
			queue_redraw()
	var reduced := false
	var _t := 0.0
	var _sb: StyleBoxFlat

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sb = StyleBoxFlat.new()
		_sb.draw_center = false
		_sb.set_corner_radius_all(28)
		_sb.anti_aliasing = true

	func _process(delta: float) -> void:
		if active and not reduced:
			_t += delta
			queue_redraw()

	func _draw() -> void:
		if not active:
			return
		var r := Rect2(Vector2.ZERO, size)
		if reduced:
			_sb.set_border_width_all(5)
			_sb.border_color = Color(GLOW_COLOR, 0.95)
			_sb.set_corner_radius_all(30)
			draw_style_box(_sb, r.grow(2.0))
			return
		var n := 8
		for i in n:
			var inset := -10.0 + i * 3.0             # außen (−10) → innen (+11)
			var wave := 0.5 + 0.5 * sin(_t * 3.2 - i * 0.75)
			var a := (1.0 - float(i) / n) * (0.35 + 0.65 * wave)
			_sb.set_border_width_all(3)
			_sb.border_color = Color(GLOW_COLOR, clampf(a, 0.0, 1.0))
			_sb.set_corner_radius_all(maxi(8, int(28 - inset)))
			draw_style_box(_sb, r.grow(-inset))


# Grüner Haken (erledigter Schritt)
class Check:
	extends Control
	var _tex: Texture2D

	func _init() -> void:
		custom_minimum_size = Vector2(48, 48)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tex = UiIcons.icon("haken", 30, Color.WHITE)

	func _draw() -> void:
		var c := size / 2.0
		var rad := minf(size.x, size.y) / 2.0
		draw_circle(c, rad, DONE_COLOR)
		if _tex != null:
			draw_texture(_tex, c - _tex.get_size() / 2.0)


# Runde Ziffer ① / ②
class Badge:
	extends PanelContainer

	static func make(n: int) -> Badge:
		var b := Badge.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiPalette.INK
		sb.set_corner_radius_all(40)
		b.add_theme_stylebox_override("panel", sb)
		b.custom_minimum_size = Vector2(52, 52)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := ScreenKit.label(str(n), "", UiFonts.size("zwischen"), UiPalette.CREAM)
		l.add_theme_font_override("font", UiFonts.text(800))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_child(l)
		return b
