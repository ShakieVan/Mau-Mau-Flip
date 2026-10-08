class_name GameWifiPanel
extends VBoxContainer
# Inhalt von „① WLAN“ in der Gastgeber-Lobby (Beta 1.0.2; vorher eigenes Fenster über der Lobby, Beta 1.0.1). Zeigt je nach Netz:
#   none      – kein Netz: großer Knopf „Spiel-WLAN öffnen“ (Android LocalOnlyHotspot über NetAndroid/GameWifi.java)
#   wlan      – Gastgeber ist in einem WLAN: „Mitspieler verbinden sich mit demselben WLAN“ und „Lieber eigenes Spiel-WLAN“
#   hotspot   – der normale Hotspot läuft: ihn nutzen (die App ändert ihn nie)
#   starting  – Spiel-WLAN geht auf
#   game_wifi – Spiel-WLAN offen: WLAN-QR-Code, Name und Passwort als Text, „Spiel-WLAN schließen“
#   problem   – Öffnen klappte nicht: kurzer Text, ggf. „Neu öffnen“, „Zurück“
# Ablauf beim Öffnen: Erlaubnis („Geräte in der Nähe“ ab Android 13, Standort bis 12) → Start → Adresse im Spiel-WLAN aus den
# Schnittstellen → Server neu binden (NetHostSession.rebind). Das Spiel-WLAN bleibt offen, bis man es schließt oder die App endet.
# Das Netz wird alle NET_POLL_S neu bewertet; changed meldet eine neue Netzart oder Adresse (InvitePanel baut dann ② neu).
# Am PC und in Tests ersetzt NetAndroid.wifi_stub das Spiel-WLAN und net_stub das übrige Netz.

signal changed

const POLL_S := 0.4
const NET_POLL_S := 1.5
const ADDRESS_WAIT_MS := 6000           # so lange nach „on“ auf die Adresse der neuen Schnittstelle warten
const QR_SIZE := 220.0

static var _before: Array = []          # Hotspot-Adressen vor dem Start (die neue ist die des Spiel-WLANs)
# Simulation statt Netzwerkzustand und Adressen des Gastgebers: {mode: "none" | "wlan" | "hotspot", urls: ["http://…/"]}
static var net_stub = null

var host: HostTable
var mode := "none"
var wifi := {}                           # letzter Zustand (NetAndroid.game_wifi_state)
var address := ""                        # eigene Adresse im Spiel-WLAN
var urls: Array = []                     # Spieladressen des Gastgebers (HostTable.host_urls)
var problem := ""                        # Fehlercode für den Text (wie GameWifi.java), "" = keiner
var hint := ""                           # Zusatzhinweis (z. B. aus rebind)
var _qr: TextureRect
var _qr_text := ""
var _text: Label
var _small: Label
var _values: VBoxContainer
var _open: Button
var _own: Button
var _retry: Button
var _back: Button
var _stop: Button
var _poll := 0.0
var _net_poll := 0.0
var _on_since := 0
var _rebound := false                    # Sitzung ist aufs offene Spiel-WLAN neu gebunden (nach dem Schließen zurückbinden)
var _close_at := 0                       # Spiel-WLAN zu seit (ms); Rückbindung spätestens nach REBIND_WAIT_MS
const REBIND_WAIT_MS := 5000
var _started := false                   # ein Öffnen wurde angestoßen (Fehlschlag zählt dann als problem)
var _waiting_permission := false


func _init() -> void:
	name = "SpielWlan"
	add_theme_constant_override("separation", 12)
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func setup(host_table: HostTable) -> void:
	host = host_table
	_build()
	if NetAndroid.game_wifi_available():
		wifi = NetAndroid.game_wifi_state()
		_on_since = Time.get_ticks_msec()
	refresh_net(true)


func _build() -> void:
	var row := ScreenKit.hbox(18)
	add_child(row)
	_qr = TextureRect.new()
	_qr.name = "QR"
	_qr.custom_minimum_size = Vector2(QR_SIZE, QR_SIZE)
	_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_qr.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_qr)
	var v := ScreenKit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	_text = ScreenKit.text_block("", UiFonts.size("text"))
	_text.name = "Text"
	v.add_child(_text)
	_small = ScreenKit.hint("", UiFonts.size("hinweis"))
	_small.name = "Hinweis"
	v.add_child(_small)
	_values = ScreenKit.vbox(0)          # Name und Passwort über die ganze Breite (große Schrift: kein Umbruch im Passwort)
	add_child(_values)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 12)
	buttons.add_theme_constant_override("v_separation", 10)
	add_child(buttons)
	_open = ScreenKit.button("Spiel-WLAN öffnen", "PrimaryButton", "wlan")
	_open.name = "Oeffnen"
	_open.custom_minimum_size = Vector2(0, 92)
	_open.add_theme_font_size_override("font_size", UiFonts.size("start"))
	_open.pressed.connect(open_wifi)
	buttons.add_child(_open)
	_own = ScreenKit.button("Lieber eigenes Spiel-WLAN", "GhostButton", "wlan")
	_own.name = "EigenesWlan"
	_own.add_theme_font_size_override("font_size", UiFonts.size("text"))
	_own.pressed.connect(open_wifi)
	buttons.add_child(_own)
	_retry = ScreenKit.button("Neu öffnen", "PrimaryButton")
	_retry.name = "Erneut"
	_retry.pressed.connect(open_wifi)
	buttons.add_child(_retry)
	_back = ScreenKit.button("Zurück", "GhostButton")
	_back.name = "ProblemZurueck"
	_back.pressed.connect(dismiss_problem)
	buttons.add_child(_back)
	_stop = ScreenKit.button("Spiel-WLAN schließen", "GhostButton")
	_stop.name = "Schliessen"
	_stop.add_theme_font_size_override("font_size", UiFonts.size("hinweis"))
	_stop.pressed.connect(close_wifi)
	buttons.add_child(_stop)


# --- Netz ---

# Netzart aus Netzwerkzustand (NetAndroid.state), Spiel-WLAN-Zustand, Fehler und Spieladressen
static func detect_mode(s: Dictionary, st: Dictionary, problem_code: String, host_urls: Array) -> String:
	if problem_code != "":
		return "problem"
	var status := str(st.get("status", "off"))
	if status == "on":
		return "game_wifi"
	if status == "starting":
		return "starting"
	if bool(s.get("android", false)):
		if int(st.get("ap_enabled", -1)) == 1:
			return "hotspot"
		if NetAndroid.wifi_connected(s):
			return "wlan"
		if not NetAndroid.hotspot_interfaces(s).is_empty():
			return "hotspot"
		return "none"
	return "wlan" if not host_urls.is_empty() else "none"


# Netz neu bewerten; changed nur bei neuer Netzart oder Adresse (force: immer)
func refresh_net(force := false) -> void:
	var old_mode := mode
	var old_url := game_url()
	var st := str(wifi.get("status", ""))
	if problem == "" and _started and st in ["failed", "stopped"]:
		problem = (str(wifi.get("error", "")) if st == "failed" else "stopped")
		if problem == "":
			problem = "generic"
	if net_stub is Dictionary:
		urls = (net_stub.get("urls", []) as Array).duplicate()
	else:
		urls = Array(host.host_urls()) if host != null else []
	if str(wifi.get("status", "")) == "on" and problem == "":
		if address == "":
			address = _find_address()
		if address != "" and not _rebound:
			_rebound = true
			if host != null and host.session != null:
				hint = host.session.rebind()
	elif _rebound and not (st in ["on", "starting"]):
		# Spiel-WLAN zu (Knopf oder Android): Gastgeber-Sitzung wieder wie beim Eröffnen binden, sobald dessen Adresse weg ist
		if _close_at == 0:
			_close_at = Time.get_ticks_msec()
		if _game_wifi_gone() or Time.get_ticks_msec() - _close_at >= REBIND_WAIT_MS:
			_rebound = false
			_close_at = 0
			if host != null and host.session != null:
				hint = host.session.rebind(true)
	if net_stub is Dictionary:
		var m := detect_mode({}, wifi, problem, [])
		mode = m if m in ["problem", "game_wifi", "starting"] else str(net_stub.get("mode", "none"))
	else:
		mode = detect_mode(NetAndroid.state(), wifi, problem, urls)
	_show()
	if force or mode != old_mode or game_url() != old_url:
		changed.emit()


# Adresse für „② Spiel“: im Spiel-WLAN dessen Adresse, sonst die erste des Gastgebers; "" = kein Netz
func game_url() -> String:
	var port := host.port() if host != null and host.port() > 0 else NetAndroid.GAME_WIFI_PORT
	if mode == "game_wifi" and address != "":
		return NetAndroid.game_url(address, port)
	if mode == "none" or urls.is_empty():
		return ""
	return str(urls[0])


# Inhalt des WLAN-QR-Codes ("" = keiner)
func qr_text() -> String:
	if mode != "game_wifi" or str(wifi.get("ssid", "")) == "":
		return ""
	return NetAndroid.wifi_qr_text(str(wifi.get("ssid", "")), str(wifi.get("password", "")), str(wifi.get("security", "wpa2")))


# --- Ablauf ---

func open_wifi() -> void:
	problem = ""
	hint = ""
	_rebound = false
	address = ""
	_started = true
	if not NetAndroid.game_wifi_available():
		problem = "unsupported"
		refresh_net()
		return
	wifi = NetAndroid.game_wifi_state()
	if str(wifi.get("status", "")) in ["on", "starting"]:
		_on_since = Time.get_ticks_msec()
		refresh_net()
		return
	if not bool(wifi.get("granted", true)) and not _ask_permission():
		return
	_start()


func close_wifi() -> void:
	NetAndroid.game_wifi_stop()
	problem = ""
	hint = ""
	address = ""
	_started = false
	_close_at = 0                           # _rebound bleibt: refresh_net bindet die Sitzung zurück
	wifi = NetAndroid.game_wifi_state()
	refresh_net()


func dismiss_problem() -> void:
	problem = ""
	_started = false
	if NetAndroid.game_wifi_available():
		wifi = NetAndroid.game_wifi_state()
	refresh_net()


# true = Erlaubnis da; false = Dialog offen (Antwort über on_request_permissions_result) bzw. abgelehnt.
func _ask_permission() -> bool:
	var perm := NetAndroid.game_wifi_permission()
	if NetAndroid.wifi_stub is Dictionary:
		problem = "permission"
		refresh_net()
		return false
	if OS.request_permission(perm):
		return true
	_waiting_permission = true
	if not get_tree().on_request_permissions_result.is_connected(_on_permission):
		get_tree().on_request_permissions_result.connect(_on_permission)
	wifi["status"] = "starting"
	refresh_net()
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
		refresh_net()


func _start() -> void:
	wifi = NetAndroid.game_wifi_state()
	if int(wifi.get("ap_enabled", -1)) == 1:
		problem = "ap_running"
		refresh_net()
		return
	_before = NetAndroid.hotspot_addresses(NetAndroid.state())
	address = ""
	problem = NetAndroid.game_wifi_start()
	wifi = NetAndroid.game_wifi_state()
	_on_since = Time.get_ticks_msec()
	refresh_net()


func _process(delta: float) -> void:
	if host == null or _waiting_permission:
		return
	_poll -= delta
	_net_poll -= delta
	var st := str(wifi.get("status", ""))
	var busy := problem == "" and (st == "starting" or (st == "on" and address == ""))
	if busy and _poll <= 0.0:
		_poll = POLL_S
		var was := st
		wifi = NetAndroid.game_wifi_state()
		if str(wifi.get("status", "")) == "on" and was != "on":
			_on_since = Time.get_ticks_msec()
		refresh_net()
		return
	if _net_poll <= 0.0:
		_net_poll = NET_POLL_S
		if NetAndroid.game_wifi_available() and not (NetAndroid.wifi_stub is Dictionary):
			wifi = NetAndroid.game_wifi_state()       # Android kann das Spiel-WLAN beenden
		refresh_net()


func _find_address() -> String:
	if NetAndroid.wifi_stub is Dictionary:
		return str(NetAndroid.wifi_stub.get("address", ""))
	return NetAndroid.game_wifi_address(NetAndroid.state(), _before)


# Spiel-WLAN-Schnittstelle verschwunden (Stub: sofort)
func _game_wifi_gone() -> bool:
	if NetAndroid.wifi_stub is Dictionary:
		return true
	return NetAndroid.game_wifi_address(NetAndroid.state(), _before) == ""


# --- Anzeige ---

func _show() -> void:
	if _text == null:
		return
	var can := NetAndroid.game_wifi_available()
	var text := ""
	var small := ""
	for c in _values.get_children():
		_values.remove_child(c)
		c.queue_free()
	match mode:
		"game_wifi":
			text = "Kamera auf den Code halten – so kommt das Handy ins Spiel-WLAN."
			_values.add_child(_value("Name", str(wifi.get("ssid", ""))))
			if str(wifi.get("password", "")) != "":
				_values.add_child(_value("Passwort", str(wifi.get("password", ""))))
			if address == "" and Time.get_ticks_msec() - _on_since > ADDRESS_WAIT_MS:
				small = "Die Adresse im Spiel-WLAN ist noch unbekannt. Schließe es und öffne es neu."
		"starting":
			text = "Spiel-WLAN wird geöffnet …"
		"wlan":
			text = "Mitspieler verbinden sich mit demselben WLAN wie du."
			if can:
				small = "Klappt das nicht, z. B. im Hotel? Dann öffne ein eigenes:"
		"hotspot":
			text = "Dein Hotspot läuft: Verbinde die anderen Handys damit."
			small = "Die App ändert deinen Hotspot nie."
		"problem":
			var msg := NetAndroid.game_wifi_message({"status": "stopped"}) if problem == "stopped" \
				else NetAndroid.game_wifi_message({"status": "failed", "error": problem, "sdk": int(wifi.get("sdk", 33))})
			text = str(msg.title)
			small = str(msg.text)
		_:
			text = "Noch kein WLAN da. Öffne ein eigenes Spiel-WLAN – ganz ohne Internet." if can \
				else "Noch kein WLAN da. Verbinde dich mit einem WLAN oder schalte deinen Hotspot ein."
	if hint != "":
		small = (small + "\n" if small != "" else "") + hint
	_text.text = text
	_text.add_theme_font_override("font", UiFonts.text(800 if mode == "problem" else 600))
	_small.text = small
	_small.visible = small != ""
	_open.visible = mode == "none" and can
	_own.visible = mode == "wlan" and can
	_stop.visible = mode in ["game_wifi", "starting"]
	_retry.visible = mode == "problem" and (problem == "stopped"
		or bool(NetAndroid.game_wifi_message({"status": "failed", "error": problem}).get("retry", false)))
	_back.visible = mode == "problem"
	var q := qr_text()
	_qr.visible = q != ""
	if q != _qr_text:
		_qr_text = q
		_qr.texture = null
		if q != "":
			var code := QrCode.encode(q)
			if code != null:
				_qr.texture = code.to_texture(8, 2, UiPalette.INK, Color.WHITE)


func _value(caption: String, value: String) -> Control:
	var r := ScreenKit.hbox(18)
	var c := ScreenKit.label(caption, "HintLabel", UiFonts.size("hinweis"))
	c.custom_minimum_size = Vector2(QR_SIZE, 0)          # Werte stehen bündig neben dem QR-Code
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(c)
	var l := ScreenKit.label(value, "", UiFonts.size("zeile"))
	l.name = caption
	l.add_theme_font_override("font", UiFonts.text(800, 90.0))
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(l)
	return r
