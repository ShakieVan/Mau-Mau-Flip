class_name QrJoin
extends RefCounted
# QR-Code scannen unter „Beitreten“ (Beta 1.4.3; Anlass: Gäste mit eingeschalteten mobilen Daten erreichen die Spielseite im
# Spiel-WLAN nicht, weil Chrome die Anfrage ins Mobilnetz schickt – in der App bindet sich die Verbindung ans WLAN).
# - parse(text): reine Auswertung eines gescannten Texts (testbar): WLAN-Spiel-Link, Online-Link, App-Link, Spiel-WLAN-QR, Unbekanntes.
# - Scanner: Google Code Scanner (QrScan.java, ohne Kamera-Erlaubnis; braucht die Google-Play-Dienste).
# - Spiel-WLAN aus dem WLAN-QR: QrWifi.java (WifiNetworkSpecifier, ab Android 10). Solange es läuft, binden „join“ und „search“
#   an dieses Netz (NetAddresses.pinned). wifi_release() zieht die Anfrage zurück (Spiel verlassen, Beitreten-Seite verlassen).
# Am PC und in Tests ersetzen scan_stub/wifi_stub die Java-Helfer.

const MAX_TEXT := 1024
const INJECT_MAX_AGE_MS := 120000

static var scan_stub = null      # Dictionary {available, start_error, results: Array[Dictionary]} statt Java; null = echtes Android
static var wifi_stub = null      # Dictionary {sdk, connect_error, state: Dictionary, bind_error, released (Zähler)} statt Java
static var _owner_client := 0    # Instanz-ID der ClientTable, die über das Spiel-WLAN aus dem QR-Code verbunden ist
static var _active := false      # Anfrage ans Spiel-WLAN läuft


# --- Auswertung -------------------------------------------------------------------------------------------------------------

# Ergebnis: {kind, …}
#   "wlan":    address, port                (http://<private IP>[:Port][/…], auch maumauflip://join?h=&p=)
#   "online":  room, relay ("" = Vermittler aus den Einstellungen)   (https://<vermittler>/?r=CODE, maumauflip://join?r=&v=)
#   "wifi":    ssid, password, security (wpa2|wpa3|open), hidden   (WIFI:S:…;T:WPA;P:…;;)
#   "invalid": error (erkannt, aber unbrauchbar)      "unknown": error (kein Code dieses Spiels)
static func parse(raw: String) -> Dictionary:
	var t := raw.strip_edges()
	if t == "" or t.length() > MAX_TEXT:
		return _unknown()
	var low := t.to_lower()
	if low.begins_with("wifi:"):
		return parse_wifi(t)
	if low.begins_with(NetAndroid.APP_LINK_SCHEME + "://"):
		var link := NetAndroid.parse_app_link(t)
		if not bool(link.get("ok", false)):
			return {"kind": "invalid", "error": str(link.get("error", ""))}
		if str(link.get("room", "")) != "":
			return {"kind": "online", "room": str(link.room), "relay": str(link.get("relay", ""))}
		return {"kind": "wlan", "address": str(link.address), "port": int(link.port)}
	if low.begins_with("http://") or low.begins_with("https://"):
		var room := NetProtocol.parse_room_link(t)
		if not room.is_empty():
			return {"kind": "online", "room": str(room.room), "relay": str(room.relay)}
		return _parse_game_url(t)
	return _unknown()


static func _unknown() -> Dictionary:
	return {"kind": "unknown", "error": I18n.t("Das ist kein QR-Code von Mau-Mau Flip. Scanne den Code auf dem Handy des Gastgebers.")}


static func _parse_game_url(t: String) -> Dictionary:
	# http://192.168.43.1:24690/ (Spielseite des Gastgebers im WLAN), Groß/Klein egal (QR-Codes im Alphanumerik-Modus sind groß)
	var rest := t.substr(t.find("://") + 3)
	for cut in ["/", "?", "#"]:
		var i := rest.find(cut)
		if i >= 0:
			rest = rest.left(i)
	var host := rest
	var port := NetProtocol.PORT
	var colon := rest.rfind(":")
	if colon >= 0:
		host = rest.left(colon)
		var p := rest.substr(colon + 1)
		if not p.is_valid_int() or int(p) < 1 or int(p) > 65535:
			return {"kind": "invalid", "error": I18n.t("Der Link zum Spiel ist unvollständig. Scanne den QR-Code beim Gastgeber noch einmal.")}
		port = int(p)
	if NetAndroid.private_ipv4(host):
		return {"kind": "wlan", "address": host, "port": port}
	return {"kind": "unknown", "error": I18n.t("Dieser Link führt nicht zu einem Spiel in deiner Nähe. Scanne den QR-Code auf dem Handy des Gastgebers.")}


# WLAN-QR (ZXing-Format): WIFI:T:WPA;S:<ssid>;P:<passwort>;H:true;; – Felder in beliebiger Reihenfolge, Schlüssel groß oder klein,
# \ ; , : " mit Backslash geschützt; ein Wert in Anführungszeichen (ältere Erzeuger) wird ausgepackt.
static func parse_wifi(t: String) -> Dictionary:
	var bad := {"kind": "invalid", "error": I18n.t("Dieser WLAN-Code ist unvollständig. Lass den Gastgeber das Spiel-WLAN neu öffnen und scanne noch einmal.")}
	var body := t.substr(5)
	var fields := {}
	var key := ""
	var value := ""
	var in_value := false
	var esc := false
	for ch in body:
		if esc:
			if in_value:
				value += ch
			else:
				key += ch
			esc = false
		elif ch == "\\":
			esc = true
		elif ch == ";":
			if key.strip_edges() != "":
				fields[key.strip_edges().to_upper()] = value
			key = ""
			value = ""
			in_value = false
		elif ch == ":" and not in_value:
			in_value = true
		elif in_value:
			value += ch
		else:
			key += ch
	if esc:
		return bad
	if key.strip_edges() != "":
		fields[key.strip_edges().to_upper()] = value
	var ssid := _unquote(str(fields.get("S", "")))
	var password := _unquote(str(fields.get("P", "")))
	var type := str(fields.get("T", "")).strip_edges().to_upper()
	if ssid == "" or ssid.to_utf8_buffer().size() > 32:
		return bad
	var security := ""
	match type:
		"WPA", "WPA2", "WPA/WPA2", "WPA2/WPA3":
			security = "wpa2"
		"SAE", "WPA3":
			security = "wpa3"
		"NOPASS", "NONE", "OPEN":
			security = "open"
		"":
			security = "wpa2" if password != "" else "open"
		"WEP":
			return {"kind": "invalid", "error": I18n.t("Dieses WLAN nutzt eine veraltete Verschlüsselung (WEP). Verbinde dich bitte in den WLAN-Einstellungen.")}
		_:
			return bad
	if security == "open":
		password = ""
	elif password.length() < 8 or password.length() > 64:
		return bad
	var hidden := str(fields.get("H", "")).strip_edges().to_lower() == "true"
	return {"kind": "wifi", "ssid": ssid, "password": password, "security": security, "hidden": hidden}


static func _unquote(v: String) -> String:
	if v.length() >= 2 and v.begins_with("\"") and v.ends_with("\""):
		return v.substr(1, v.length() - 2)
	return v


# --- Scanner ----------------------------------------------------------------------------------------------------------------

static func _java(cls: String) -> Array:
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return []
	var activity = Engine.get_singleton("AndroidRuntime").getActivity()
	var java = JavaClassWrapper.wrap("com.godot.game." + cls)
	return [java, activity] if java != null and activity != null else []


static func scan_available() -> bool:
	if scan_stub is Dictionary:
		return bool(scan_stub.get("available", true))
	var j := _java("QrScan")
	return not j.is_empty() and bool(j[0].available(j[1]))


static func scan_start() -> String:
	# "" = Scanner geöffnet (Ergebnis über scan_take), sonst Fehlercode: no_gms | busy | exception | android
	if scan_stub is Dictionary:
		return str(scan_stub.get("start_error", "")) if scan_available() else "no_gms"
	var j := _java("QrScan")
	if j.is_empty():
		return "android"
	return str(j[0].start(j[1]))


static func scan_take() -> Dictionary:
	# {status: idle|scanning|done|cancelled|failed, text, error, source}; ein über adb eingespeister Text (source "intent") älter
	# als 2 min zählt nicht.
	var r := {}
	if scan_stub is Dictionary:
		var list: Array = scan_stub.get("results", [])
		r = list.pop_front() if not list.is_empty() else {"status": "idle"}
	else:
		var j := _java("QrScan")
		if j.is_empty():
			return {"status": "idle"}
		var data = JSON.parse_string(str(j[0].take()))
		r = data if data is Dictionary else {"status": "idle"}
	if str(r.get("source", "")) == "intent" and float(r.get("now", 0)) - float(r.get("at", 0)) > INJECT_MAX_AGE_MS:
		return {"status": "idle"}
	return r


static func scan_error_text(code: String) -> String:
	match code:
		"cancelled":
			return ""
		"no_gms", "android":
			return I18n.t("Der QR-Scanner braucht die Google-Play-Dienste, die es hier nicht gibt. Tritt über den Raumcode oder die Liste unten bei.")
		"module":
			return I18n.t("Der Scanner wird gerade von Google geladen. Versuch es in einem Moment noch einmal.")
		"busy":
			return ""
	return I18n.t("Der Scanner ließ sich nicht öffnen. Tritt über den Raumcode oder die Liste unten bei.")


# --- Spiel-WLAN aus dem WLAN-QR ---------------------------------------------------------------------------------------------

static func wifi_supported() -> bool:
	# WifiNetworkSpecifier gibt es ab Android 10 (SDK 29).
	if wifi_stub is Dictionary:
		return int(wifi_stub.get("sdk", 34)) >= 29
	return not _java("QrWifi").is_empty() and OS.get_name() == "Android" and _sdk() >= 29


static func _sdk() -> int:
	var s := NetAndroid.state()
	return int(s.get("sdk", 0))


static func wifi_connect(ssid: String, password: String, security: String) -> String:
	# "" = Anfrage läuft (Systemdialog), sonst Fehlercode old_android | exception | android
	var err := ""
	if wifi_stub is Dictionary:
		err = str(wifi_stub.get("connect_error", "")) if wifi_supported() else "old_android"
	else:
		var j := _java("QrWifi")
		err = "android" if j.is_empty() else str(j[0].request(j[1], ssid, password, security))   # nicht „connect“ (Object.connect)
	_active = err == ""
	return err


static func wifi_state() -> Dictionary:
	# {status: idle|connecting|available|unavailable|lost, ssid, handle, gateway, address}
	if wifi_stub is Dictionary:
		var st: Variant = wifi_stub.get("state", {})
		return (st as Dictionary).duplicate() if st is Dictionary else {}
	var j := _java("QrWifi")
	if j.is_empty():
		return {"status": "idle"}
	var data = JSON.parse_string(str(j[0].state(j[1])))
	return data if data is Dictionary else {"status": "idle"}


static func wifi_bind() -> String:
	# NetAddresses.pinned: Prozess an das Spiel-WLAN binden. "" = gebunden, sonst Grund.
	if wifi_stub is Dictionary:
		return str(wifi_stub.get("bind_error", ""))
	var j := _java("QrWifi")
	return I18n.t("Nur auf Android möglich.") if j.is_empty() else Updater.java_text(str(j[0].bind(j[1])))


static func wifi_pin() -> void:
	# Ab jetzt binden Beitreten und Suche ans Spiel-WLAN aus dem QR-Code.
	NetAddresses.pinned = QrJoin.wifi_bind


static func wifi_active() -> bool:
	return _active


static func wifi_release() -> bool:
	# Anfrage zurückziehen: Android trennt das Spiel-WLAN, das Handy kommt wieder normal ins Internet. true = es lief eine.
	var was := _active
	_active = false
	_owner_client = 0
	NetAddresses.pinned = Callable()
	if NetAddresses.bound_to == "qr_wifi":
		NetAddresses.bound_to = ""
	if wifi_stub is Dictionary:
		if was:
			wifi_stub["released"] = int(wifi_stub.get("released", 0)) + 1
			wifi_stub["state"] = {"status": "idle"}
		return was
	var j := _java("QrWifi")
	if not j.is_empty():
		was = bool(j[0].release(j[1])) or was
	return was


static func attach(client: Object) -> void:
	# Verbindung steht: das Spiel-WLAN gehört ab jetzt zu dieser ClientTable (freigegeben, wenn sie das Spiel verlässt).
	if _active and client != null:
		_owner_client = client.get_instance_id()


static func client_left(client: Object) -> void:
	if client != null and _owner_client != 0 and client.get_instance_id() == _owner_client:
		wifi_release()


# Spiel-WLAN aus dem QR-Code weg (Gastgeber hat es geschlossen, außer Reichweite): Anfrage zurückziehen. Solange sie läuft, verbindet
# sich ein Handy ohne zweiten WLAN-Empfänger nicht wieder mit dem normalen WLAN (Gerätetest 1.4.3, S10). Aus ClientTable.pump,
# höchstens alle LOST_CHECK_MS. true = freigegeben.
const LOST_CHECK_MS := 2000
static var _lost_check_ms := -LOST_CHECK_MS

static func check_lost(client: Object, now_ms: int = -1) -> bool:
	if not _active or _owner_client == 0 or client == null or client.get_instance_id() != _owner_client:
		return false
	var now := Time.get_ticks_msec() if now_ms < 0 else now_ms
	if now - _lost_check_ms < LOST_CHECK_MS:
		return false
	_lost_check_ms = now
	if str(wifi_state().get("status", "")) in ["lost", "unavailable"]:
		wifi_release()
		return true
	return false


static func wifi_status_text(st: Dictionary, ssid: String) -> String:
	match str(st.get("status", "")):
		"connecting":
			return I18n.t("Verbinde mit dem Spiel-WLAN „%s“ … Bestätige die Anfrage von Android.") % ssid
		"available":
			return I18n.t("Im Spiel-WLAN „%s“ – suche das Spiel …") % ssid
		"unavailable":
			return I18n.t("Keine Verbindung zum Spiel-WLAN „%s“. Ist das Spiel-WLAN des Gastgebers noch offen und bist du in der Nähe? Scanne noch einmal.") % ssid
		"lost":
			return I18n.t("Das Spiel-WLAN „%s“ ist weg. Scanne den WLAN-Code noch einmal.") % ssid
	return ""


static func old_android_text(ssid: String, password: String) -> String:
	if password == "":
		return I18n.t("Verbinde dich in den WLAN-Einstellungen mit „%s“ und komm dann hierher zurück – das Spiel erscheint unten in der Liste.") % ssid
	return I18n.t("Verbinde dich in den WLAN-Einstellungen mit „%s“ (Passwort: %s) und komm dann hierher zurück – das Spiel erscheint unten in der Liste.") % [ssid, password]
