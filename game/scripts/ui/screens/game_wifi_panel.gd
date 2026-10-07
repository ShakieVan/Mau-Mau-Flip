class_name GameWifiPanel
extends Control
# Spiel-WLAN (Beta 1.0.1, Android LocalOnlyHotspot über NetAndroid/GameWifi.java), über der Lobby „Spiel eröffnen“.
# Ablauf: Erlaubnis („Geräte in der Nähe“ ab Android 13, Standort bis 12) → Start → Adresse im Spiel-WLAN aus den Schnittstellen →
# Server neu binden (NetHostSession.rebind) → großer QR-Code mit Schrittleiste „1 WLAN beitreten · 2 Spiel öffnen“ (nie zwei QR-Codes
# nebeneinander: die Kamera greift sonst zufällig einen). Tipp auf den QR-Code oder die Schritte wechselt. Fehler mit kurzem Text.
# Das Spiel-WLAN bleibt offen, wenn das Panel schließt („Fertig“), und endet mit der App oder per „Spiel-WLAN schließen“.

signal closed

const POLL_S := 0.4
const ADDRESS_WAIT_MS := 6000           # so lange nach „on“ auf die Adresse der neuen Schnittstelle warten
const STEP_COLORS := [Color("#2E9E6A"), Color("#6C55E0")]

static var _before: Array = []          # Hotspot-Adressen vor dem Start (die neue ist die des Spiel-WLANs)

var host: HostTable
var step := 0                            # 0 = WLAN-QR, 1 = Spiel-QR
var wifi := {}                           # letzter Zustand (NetAndroid.game_wifi_state)
var address := ""
var problem := ""                        # Fehlercode für den Text (wie GameWifi.java), "" = keiner
var hint := ""                           # Zusatzhinweis (z. B. aus rebind)
var _card: PanelContainer
var _qr: TextureRect
var _frame: PanelContainer
var _steps: Array[Button] = []
var _title: Label
var _text: Label
var _lines: VBoxContainer
var _retry: Button
var _stop: Button
var _poll := 0.0
var _on_since := 0
var _rebound := false
var _waiting_permission := false


static func open(parent: Node, host_table: HostTable) -> GameWifiPanel:
	var p := GameWifiPanel.new()
	p.host = host_table
	p.theme = UiTheme.get_theme()
	parent.add_child(p)
	p._build()
	p._begin()
	return p


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	name = "SpielWlan"


func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = ScreenKit.card(26.0)
	_card.custom_minimum_size = Vector2(1060, 0)
	center.add_child(_card)
	var row := ScreenKit.hbox(28)
	_card.add_child(row)
	_frame = PanelContainer.new()
	_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_frame)
	_qr = TextureRect.new()
	_qr.name = "QR"
	_qr.custom_minimum_size = Vector2(340, 340)
	_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_qr.mouse_filter = Control.MOUSE_FILTER_STOP
	_qr.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			set_step(1 - step))
	_frame.add_child(_qr)
	var v := ScreenKit.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	_title = ScreenKit.heading("Spiel-WLAN", 34)
	v.add_child(_title)
	var steps := ScreenKit.hbox(10)
	v.add_child(steps)
	for i in 2:
		var b := ScreenKit.button(["1  WLAN beitreten", "2  Spiel öffnen"][i], "GhostButton")
		b.name = "Schritt%d" % (i + 1)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", UiFonts.px(22))
		b.pressed.connect(set_step.bind(i))
		steps.add_child(b)
		_steps.append(b)
	_lines = ScreenKit.vbox(4)
	v.add_child(_lines)
	_text = ScreenKit.hint("", UiFonts.px(20))
	_text.name = "Text"
	v.add_child(_text)
	v.add_child(ScreenKit.spacer(false))
	var buttons := ScreenKit.hbox(12)
	v.add_child(buttons)
	_retry = ScreenKit.button("Neu öffnen", "GhostButton")
	_retry.name = "Erneut"
	_retry.pressed.connect(_begin)
	buttons.add_child(_retry)
	_stop = ScreenKit.button("Spiel-WLAN schließen", "GhostButton")
	_stop.name = "Schliessen"
	_stop.pressed.connect(func() -> void:
		NetAndroid.game_wifi_stop()
		problem = ""
		wifi = NetAndroid.game_wifi_state()
		_refresh())
	buttons.add_child(_stop)
	var done := ScreenKit.button("Fertig", "PrimaryButton")
	done.name = "Fertig"
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done.pressed.connect(close)
	buttons.add_child(done)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.1, 0.6))


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


# --- Ablauf ---

func _begin() -> void:
	problem = ""
	hint = ""
	_rebound = false
	if not NetAndroid.game_wifi_available():
		problem = "unsupported"
		_refresh()
		return
	wifi = NetAndroid.game_wifi_state()
	if str(wifi.get("status", "")) in ["on", "starting"]:
		_on_since = Time.get_ticks_msec()
		_refresh()
		return
	if not bool(wifi.get("granted", true)) and not _ask_permission():
		return
	_start()


# true = Erlaubnis da; false = Dialog offen (Antwort über on_request_permissions_result) bzw. abgelehnt.
func _ask_permission() -> bool:
	var perm := NetAndroid.game_wifi_permission()
	if NetAndroid.wifi_stub is Dictionary:
		problem = "permission"
		_refresh()
		return false
	if OS.request_permission(perm):
		return true
	_waiting_permission = true
	if not get_tree().on_request_permissions_result.is_connected(_on_permission):
		get_tree().on_request_permissions_result.connect(_on_permission)
	wifi["status"] = "starting"
	_refresh()
	return false


func _on_permission(permission: String, granted: bool) -> void:
	if not _waiting_permission or permission != NetAndroid.game_wifi_permission():
		return
	_waiting_permission = false
	if granted:
		_start()
	else:
		problem = "permission"
		wifi = NetAndroid.game_wifi_state()
		_refresh()


func _start() -> void:
	wifi = NetAndroid.game_wifi_state()
	if int(wifi.get("ap_enabled", -1)) == 1:
		problem = "ap_running"
		_refresh()
		return
	_before = NetAndroid.hotspot_addresses(NetAndroid.state())
	address = ""
	var err := NetAndroid.game_wifi_start()
	problem = err
	wifi = NetAndroid.game_wifi_state()
	_on_since = Time.get_ticks_msec()
	_refresh()


func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0 or problem != "" or _waiting_permission:
		return
	_poll = POLL_S
	var st := str(wifi.get("status", ""))
	if st != "starting" and (st != "on" or (address != "" and _rebound)):
		return
	var was := st
	wifi = NetAndroid.game_wifi_state()
	if str(wifi.get("status", "")) == "on" and was != "on":
		_on_since = Time.get_ticks_msec()
	_refresh()


func _find_address() -> String:
	if NetAndroid.wifi_stub is Dictionary:
		return str(NetAndroid.wifi_stub.get("address", ""))
	return NetAndroid.game_wifi_address(NetAndroid.state(), _before)


# Anzeige aus dem Zustand
func _refresh() -> void:
	var st := str(wifi.get("status", "off"))
	if problem == "" and st == "failed":
		problem = str(wifi.get("error", "generic"))
	if st == "on" and problem == "":
		if address == "":
			address = _find_address()
		if address != "" and not _rebound:
			_rebound = true
			if host != null and host.session != null:
				hint = host.session.rebind()
	var shown := wifi.duplicate()
	if problem != "":
		shown["status"] = "failed"
		shown["error"] = problem
	var msg := NetAndroid.game_wifi_message(shown)
	_title.text = str(msg.title)
	var text := str(msg.text)
	if st == "on" and problem == "" and address == "" and Time.get_ticks_msec() - _on_since > ADDRESS_WAIT_MS:
		text = "Die Adresse im Spiel-WLAN ist noch unbekannt. Tippe auf „Neu öffnen“."
	if hint != "":
		text += "\n" + hint
	_text.text = text
	var on := st == "on" and problem == ""
	_retry.visible = bool(msg.get("retry", false)) or (on and address == "")
	_stop.visible = on or st == "starting"
	for b in _steps:
		b.disabled = not on
		b.get_parent().visible = on
	_show_step(on)


func set_step(i: int) -> void:
	step = clampi(i, 0, 1)
	_show_step(str(wifi.get("status", "")) == "on" and problem == "")


func qr_text() -> String:
	# Inhalt des gerade gezeigten QR-Codes ("" = keiner).
	if str(wifi.get("status", "")) != "on" or problem != "":
		return ""
	if step == 0:
		return NetAndroid.wifi_qr_text(str(wifi.get("ssid", "")), str(wifi.get("password", "")), str(wifi.get("security", "wpa2"))) \
			if str(wifi.get("ssid", "")) != "" else ""
	return NetAndroid.game_url(address, host.port() if host != null and host.port() > 0 else NetAndroid.GAME_WIFI_PORT)


func _show_step(on: bool) -> void:
	for c in _lines.get_children():
		_lines.remove_child(c)
		c.queue_free()
	for i in _steps.size():
		_steps[i].set_pressed_no_signal(i == step)
	var text := qr_text() if on else ""
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(10)
	sb.set_border_width_all(8)
	sb.border_color = STEP_COLORS[step] if on else Color(UiPalette.INK, 0.15)
	_frame.add_theme_stylebox_override("panel", sb)
	_frame.visible = on                  # ohne Spiel-WLAN kein leeres QR-Feld
	_qr.texture = null
	if text != "":
		var qr := QrCode.encode(text)
		if qr != null:
			_qr.texture = qr.to_texture(8, 2, UiPalette.INK, Color.WHITE)
	if not on:
		return
	if step == 0:
		_lines.add_child(ScreenKit.hint("Mit der Kamera scannen oder in den WLAN-Einstellungen eintragen:", UiFonts.px(19)))
		_lines.add_child(_value("Name", str(wifi.get("ssid", ""))))
		if str(wifi.get("password", "")) != "":
			_lines.add_child(_value("Passwort", str(wifi.get("password", ""))))
		_lines.add_child(ScreenKit.hint("Meldet das Handy „Kein Internet“: verbunden bleiben. Dann auf „2 Spiel öffnen“ tippen.", UiFonts.px(18)))
	else:
		_lines.add_child(ScreenKit.hint("Im Spiel-WLAN den Code scannen oder im Browser eintippen:", UiFonts.px(19)))
		_lines.add_child(_value("Adresse", text.trim_prefix("http://").trim_suffix("/") if text != "" else "wird ermittelt …"))
		_lines.add_child(ScreenKit.hint("Mit App: „Im WLAN spielen“ → „Beitreten“, das Spiel erscheint von selbst.", UiFonts.px(18)))


func _value(caption: String, value: String) -> Control:
	var r := ScreenKit.hbox(12)
	var c := ScreenKit.label(caption, "HintLabel", UiFonts.px(20))
	c.custom_minimum_size = Vector2(120, 0)
	r.add_child(c)
	var l := ScreenKit.label(value, "", 30)
	l.name = caption
	l.add_theme_font_override("font", UiFonts.text(800, 90.0))
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(l)
	return r
