class_name InvitePanel
extends VBoxContainer
# „Mitspieler einladen“ (linke Seite der Gastgeber-Lobby, Beta 1.0.2): „① WLAN“ (GameWifiPanel) und „② Spiel“ nebeneinander, je
# mit QR-Code und einem Satz Anleitung. ② zeigt die Spieladresse (QR-Code und Text) und den Hinweis für App-Gäste; ohne Netz
# „Noch kein WLAN aktiv“. Der nächste offene Schritt leuchtet (Wellen vom Rand nach innen, pulsierend; Effekte reduziert: ruhiger
# Leuchtrand), erledigte Schritte tragen einen grünen Haken (Logik in InviteSteps).
# Weg „Online (Internet)“ (docs/online/ENTWURF.md 3): Umschalter oben rechts; ohne Vermittler-Adresse Hinweis und Knopf zu den
# Einstellungen, sonst „Online öffnen“ → Raumcode groß, Link, QR-Code, „Teilen“ (Android-Teilen-Menü, sonst Zwischenablage) und
# „Online schließen“. Leuchtet, bis der erste Online-Gast da ist (InviteSteps.online_glow), dann Haken.

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
var _way: HBoxContainer
var _lan_row: Control
var _online: Control                     # Weg „Online (Internet)“
var _on_glow: Glow
var _on_check: Check
var _on_views := {}                      # Zustand → Teilansicht
var _on_qr: TextureRect
var _on_qr_text := ""
var _on_code: Label
var _on_link: Label
var _on_status: Label
var _on_error: Label
var _on_relay: Label
var _on_custom: Label
var online_guests := 0


func _init() -> void:
	name = "Einladen"
	add_theme_constant_override("separation", 12)


func setup(host_table: HostTable, port_failed := false) -> void:
	host = host_table
	port_error = port_failed
	var head_row := ScreenKit.hbox(16)
	add_child(head_row)
	var head := ScreenKit.heading("Mitspieler einladen", UiFonts.size("zwischen"))
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_row.add_child(head)
	head_row.add_child(ScreenKit.spacer())
	# Weg wählen (docs/online/ENTWURF.md 3): „Im WLAN“ (① ②) oder „Online (Internet)“. Beide Wege gelten zugleich, die Wahl
	# zeigt nur die Anleitung.
	_way = ScreenKit.choice([["wlan", "Im WLAN"], ["online", "Online (Internet)"]], "wlan", show_way, UiFonts.size("text"))
	_way.name = "Weg"
	_way.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_row.add_child(_way)
	var row := ScreenKit.hbox(20)
	row.name = "WegWlan"
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lan_row = row
	add_child(row)
	_online = _build_online()
	_online.visible = false
	add_child(_online)
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
		host.session.online_changed.connect(func(_s: String, _i: Dictionary) -> void: refresh_online())
	refresh_online()


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


# ---------- Weg „Online (Internet)“ ----------

# Anleitung umschalten: "wlan" oder "online"
func show_way(way: String) -> void:
	if _lan_row == null:
		return
	_lan_row.visible = way != "online"
	_online.visible = way == "online"
	if _way != null:
		ScreenKit.set_choice(_way, way)
	refresh_online()


func way() -> String:
	return "online" if _online != null and _online.visible else "wlan"


# Anzahl der Online-Gäste (Lobby, Feld online)
func set_online_guests(n: int) -> void:
	online_guests = maxi(n, 0)
	refresh_online()


func relay_url() -> String:
	return NetProtocol.effective_relay(str(UiApp.setting("vermittler", "")))


func online_state() -> String:
	return host.session.online_state() if host != null and host.session != null else "off"


func online_info() -> Dictionary:
	return host.session.online_info() if host != null and host.session != null else {}


# Online öffnen (Vermittler aus den Einstellungen)
func open_online() -> void:
	if host == null or host.session == null:
		return
	var url := relay_url()
	if url == "":
		refresh_online()
		return
	host.session.open_online(url)
	refresh_online()


func close_online() -> void:
	if host != null and host.session != null:
		host.session.close_online()
	refresh_online()


# Link teilen: Android-Teilen-Menü, sonst in die Zwischenablage
func share_link() -> void:
	var link := str(online_info().get("link", ""))
	if link == "":
		return
	var text := I18n.t("Spiel mit bei Mau-Mau Flip! Raumcode %s – oder einfach den Link öffnen: %s") % [str(online_info().get("room", "")), link]
	if NetAndroid.share_text(text, I18n.t("Einladung teilen")) != "":
		DisplayServer.clipboard_set(link)
		var s := _screen()
		if s != null:
			s.toast(I18n.t("Link kopiert – zum Beispiel in einen Messenger einfügen."))


func _screen() -> AppScreen:
	var n: Node = get_parent()
	while n != null and not n is AppScreen:
		n = n.get_parent()
	return n as AppScreen


func _open_settings() -> void:
	var s := _screen()
	if s != null and s.nav != null:
		s.nav.push(SettingsScreen.new())


# Ansicht nach Zustand: ohne Vermittler-Adresse („setup“), aus, verbindet, offen, kurz weg, gescheitert
func refresh_online() -> void:
	if _online == null:
		return
	var st := online_state()
	var info := online_info()
	var view := st
	if st == "off":
		view = "setup" if relay_url() == "" else "off"
	elif st == "away":
		view = "open"
	for k in _on_views:
		(_on_views[k] as Control).visible = k == view
	_on_custom.visible = not NetProtocol.is_default_relay(relay_url())
	_on_relay.text = I18n.t("Vermittler: %s") % NetProtocol.relay_host(relay_url()) if relay_url() != "" else ""
	if view == "open":
		var code := str(info.get("room", ""))
		var link := str(info.get("link", ""))
		_on_code.text = code
		_on_link.text = link.trim_prefix("https://")
		_on_status.text = I18n.t("Online-Verbindung unterbrochen – verbinde neu …") if st == "away" else \
			(I18n.t("1 Mitspieler online") if online_guests == 1 else (I18n.t("%d Mitspieler online") % online_guests if online_guests > 1 else I18n.t("Warte auf Mitspieler …")))
		if link != _on_qr_text:
			_on_qr_text = link
			_on_qr.texture = null
			var qr := QrCode.encode(link) if link != "" else null
			if qr != null:
				_on_qr.texture = qr.to_texture(8, 3, UiPalette.INK, Color.WHITE)
	elif view == "failed":
		_on_error.text = I18n.t(str(info.get("error", ""))) if str(info.get("error", "")) != "" else I18n.t("Vermittler nicht erreichbar.")
	_on_glow.reduced = UiApp.reduced_effects()
	_on_glow.active = InviteSteps.online_glow(st, online_guests) and way() == "online"
	_on_check.visible = InviteSteps.online_done(st, online_guests)


func _build_online() -> Control:
	var slot := MarginContainer.new()
	slot.name = "WegOnline"
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var card := ScreenKit.card(22.0)
	slot.add_child(card)
	var v := ScreenKit.vbox(12)
	card.add_child(v)
	var head := ScreenKit.hbox(12)
	v.add_child(head)
	var globe := TextureRect.new()
	globe.texture = HostLobbyScreen.globe_texture(52, UiPalette.INK)
	globe.custom_minimum_size = Vector2(52, 52)
	globe.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(globe)
	var t := ScreenKit.heading("Online (Internet)", UiFonts.size("abschnitt"))
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(t)
	head.add_child(ScreenKit.spacer())
	_on_relay = ScreenKit.label("", "HintLabel", UiFonts.size("klein"))
	_on_relay.name = "Vermittler"
	_on_relay.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_on_relay.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_on_relay)
	_on_check = Check.new()
	_on_check.name = "Haken"
	_on_check.visible = false
	head.add_child(_on_check)
	# ohne Vermittler-Adresse
	var setup := ScreenKit.vbox(12)
	setup.name = "OhneVermittler"
	setup.add_child(ScreenKit.text_block("Für das Spiel über das Internet braucht die App die Adresse eines Vermittlers. Trag sie in den Einstellungen unter „Online“ ein.", UiFonts.size("text")))
	var to_settings := ScreenKit.button("Zu den Einstellungen", "PrimaryButton")
	to_settings.name = "ZuDenEinstellungen"
	to_settings.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	to_settings.pressed.connect(_open_settings)
	setup.add_child(to_settings)
	v.add_child(setup)
	_on_views["setup"] = setup
	# aus
	var off := ScreenKit.vbox(12)
	off.name = "Aus"
	off.add_child(ScreenKit.text_block("Mitspieler, die nicht im selben WLAN sind, treten über das Internet bei – mit Raumcode, Link oder QR-Code. Die Spiellogik bleibt auf diesem Handy.", UiFonts.size("text")))
	var open_btn := ScreenKit.button("Online öffnen", "PrimaryButton", "start")
	open_btn.name = "OnlineOeffnen"
	open_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	open_btn.disabled = host == null or host.session == null
	open_btn.pressed.connect(open_online)
	off.add_child(open_btn)
	v.add_child(off)
	_on_views["off"] = off
	# verbindet
	var conn := ScreenKit.text_block("Verbinde mit dem Vermittler …", UiFonts.size("text"))
	conn.name = "Verbinde"
	v.add_child(conn)
	_on_views["connecting"] = conn
	# offen (auch „kurz weg“)
	var open := ScreenKit.hbox(18)
	open.name = "Offen"
	_on_qr = TextureRect.new()
	_on_qr.name = "QR"
	_on_qr.custom_minimum_size = Vector2(260, 260)
	_on_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_on_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_on_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_on_qr.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	open.add_child(_on_qr)
	var ov := ScreenKit.vbox(8)
	ov.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open.add_child(ov)
	# Ganz vorn: Link teilen (Teilen-Menü) und der QR-Code links; der Raumcode zum Abtippen folgt darunter.
	var share := ScreenKit.button("Link teilen", "PrimaryButton", "teilen")
	share.name = "Teilen"
	share.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	share.custom_minimum_size = Vector2(0, ScreenKit.TOUCH + 12)
	share.pressed.connect(share_link)
	ov.add_child(share)
	_on_custom = ScreenKit.hint("Schick deinen Mitspielern den Link. Der Code allein klappt nur mit dem Standard-Vermittler.", UiFonts.size("hinweis"))
	_on_custom.name = "EigenerVermittlerHinweis"
	ov.add_child(_on_custom)
	ov.add_child(ScreenKit.label("Oder den Raumcode zum Abtippen:", "HintLabel", UiFonts.size("hinweis")))
	_on_code = ScreenKit.label("", "", UiFonts.size("titel"))
	_on_code.name = "Raumcode"
	_on_code.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_on_code.add_theme_font_override("font", UiFonts.title(800, false, 50.0, 48.0))
	ov.add_child(_on_code)
	_on_link = ScreenKit.label("", "", UiFonts.size("text"))
	_on_link.name = "Link"
	_on_link.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_on_link.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_on_link.visible = false                 # QR-Code und „Link teilen“ tragen den Link, spart Höhe
	ov.add_child(_on_link)
	ov.add_child(ScreenKit.hint("In der App: „Beitreten“ und den Code eingeben. Ohne App: Link oder QR-Code im Browser öffnen.", UiFonts.size("hinweis")))
	_on_status = ScreenKit.label("", "", UiFonts.size("text"))
	_on_status.name = "OnlineStatus"
	_on_status.add_theme_font_override("font", UiFonts.text(700))
	var btns := HFlowContainer.new()
	btns.add_theme_constant_override("h_separation", 12)
	btns.add_theme_constant_override("v_separation", 12)
	ov.add_child(btns)
	_on_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btns.add_child(_on_status)
	var close := ScreenKit.button("Online schließen", "GhostButton")
	close.name = "OnlineSchliessen"
	close.pressed.connect(close_online)
	btns.add_child(close)
	v.add_child(open)
	_on_views["open"] = open
	# gescheitert
	var failed := ScreenKit.vbox(12)
	failed.name = "Gescheitert"
	_on_error = ScreenKit.text_block("", UiFonts.size("text"))
	_on_error.name = "Fehler"
	_on_error.add_theme_color_override("font_color", UiPalette.ALERT)
	failed.add_child(_on_error)
	var frow := ScreenKit.hbox(12)
	failed.add_child(frow)
	var retry := ScreenKit.button("Nochmal versuchen", "PrimaryButton")
	retry.name = "Nochmal"
	retry.pressed.connect(open_online)
	frow.add_child(retry)
	var fset := ScreenKit.button("Zu den Einstellungen", "GhostButton")
	fset.pressed.connect(_open_settings)
	frow.add_child(fset)
	v.add_child(failed)
	_on_views["failed"] = failed
	_on_glow = Glow.new()
	_on_glow.name = "Leuchten"
	slot.add_child(_on_glow)
	return slot


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


# Sprache gewechselt: zusammengesetzte Zeilen des Online-Wegs neu setzen
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _online != null:
		refresh_online.call_deferred()
