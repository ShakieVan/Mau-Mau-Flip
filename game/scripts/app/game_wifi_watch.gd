class_name GameWifiWatch
extends Node
# Mau-Mau Flip (Beta 1.6.2, Gastgeber-Übergabe im WLAN, docs/module/uebergabe.md 10.2 und 10.8): Wächter über Spiel-WLAN und Bindung
# des Gastgebers am Tisch. Bisher hingen Neu-Binden und Zustandsabfrage am _process von GameWifiPanel; am Tisch lebt das Panel nur im
# SeatManager-Overlay. Schloss der neue Gastgeber das Overlay zu früh, blieb der Server ans alte Netz gebunden. Der TableScreen des
# Gastgebers legt diesen Node an, solange eine Netzpartie läuft (auch ohne Overlay); GameWifiPanel liest dann nur state/address.
# - Alle POLL_MS: Spiel-WLAN-Zustand, Bindung (NetAddresses.binding) und eigene Adressen lesen. Ändert sich etwas (Spiel-WLAN auf/zu,
#   Adresse da, Bindung, Adressen), dann session.rebind(…) wie im Panel und danach host.refresh_addrs() (HostTable: wlan.addrs/past,
#   wlan.ap/ap_seat, hosts und bk neu), Signal changed.
# - auto_open(): Spiel-WLAN ohne Tippen öffnen (neuer Gastgeber nach Übernahme bzw. Ziel einer geplanten Übergabe how:"qr"), nur mit
#   schon erteilter Erlaubnis. Zuerst das fremde Spiel-WLAN aus dem QR-Code verlassen (QrJoin.wifi_release). Meldet Android
#   incompatible_mode oder hängt das Gerät noch im alten Netz (System-WLAN, Kamera-QR: wifi_release trennt dort nichts), höchstens
#   AUTO_RETRIES weitere Versuche im Abstand von AUTO_GAP_MS; dann auto_done(false, Fehler) – die Oberfläche zeigt „Neu öffnen“.
# - lost("own"): eigenes Spiel-WLAN ging zu, ohne dass close() es schloss (Android). lost("foreign"): Der Gastgeber sitzt im
#   Spiel-WLAN eines Mitspielers (foreign_ap, wlan.ap mit ap_seat != host_seat) und dieses Netz ist weg (QrWifi „lost“/„unavailable“
#   oder keine eigene Adresse mehr). Einmal je Netz.
# Alle Quellen (Zustand, Start, Adressen, Bindung, QR-Spiel-WLAN) und die Uhr sind einspritzbar (Tests: test_game_wifi_watch.gd);
# manual = true schaltet _process ab, die Tests rufen tick().

signal changed
signal lost(what: String)
signal auto_done(ok: bool, error: String)

const POLL_MS := 1500
const AUTO_POLL_MS := 400
const AUTO_RETRIES := 3
const AUTO_GAP_MS := 2000
const AUTO_WAIT_MS := 15000             # so lange je Versuch auf „on“ warten, wenn Android nichts meldet
const REBIND_WAIT_MS := 5000            # nach dem Schließen spätestens dann zurückbinden (wie GameWifiPanel)
const NO_RETRY := ["permission", "unsupported", "tethering_disallowed", "location_off", "ap_running"]

static var _current: WeakRef = null

var host: Object = null                 # HostTable (session.rebind, refresh_addrs) bzw. ein Double
var available_source: Callable = NetAndroid.game_wifi_available
var state_source: Callable = NetAndroid.game_wifi_state
var start_source: Callable = NetAndroid.game_wifi_start
var stop_source: Callable = NetAndroid.game_wifi_stop
var address_source := Callable()        # () -> String: eigene Adresse im Spiel-WLAN; Standard _own_address
var addrs_source := Callable()          # () -> Array[String]: eigene Adressen; Standard NetAddresses.own_addresses
var binding_source: Callable = NetAddresses.binding
var qr_active: Callable = QrJoin.wifi_active
var qr_state: Callable = QrJoin.wifi_state
var qr_release: Callable = QrJoin.wifi_release
var old_net := Callable()               # () -> bool: hängt das Gerät noch in einem anderen WLAN? Standard _in_old_net
var now_ms: Callable = Time.get_ticks_msec
var manual := false                     # Tests: kein _process, tick() von Hand

var state := {}                         # letzter Zustand (NetAndroid.game_wifi_state)
var address := ""                       # eigene Adresse im offenen Spiel-WLAN
var addrs: Array = []                   # eigene Adressen beim letzten Blick
var bound := ""                         # Bindung beim letzten Blick
var hint := ""                          # Hinweis aus session.rebind ("" = passt)
var auto_state := ""                    # "" | running | waiting | done | failed | permission
var auto_error := ""
var auto_tries := 0
var foreign_ap := false:                # Gastgeber sitzt im Spiel-WLAN eines Mitspielers (HostSwitch/TableScreen setzt es)
	set(v):
		if v != foreign_ap:
			_foreign_lost = false
		foreign_ap = v

var _started := false                   # erster Blick getan
var _next_poll := 0
var _rebound := false                   # Sitzung ist aufs offene Spiel-WLAN gebunden
var _close_at := 0
var _closing := false                   # close() hat geschlossen: kein lost("own")
var _was_on := false
var _foreign_lost := false
var _attempt_at := 0
var _retry_at := 0
var _auto_poll := 0
var _before: Array = []                 # Hotspot-Adressen vor dem Öffnen (die neue ist die des Spiel-WLANs)


static func current() -> GameWifiWatch:
	# Der Wächter am Tisch des Gastgebers (für GameWifiPanel im SeatManager-Overlay), null = keiner.
	var w = _current.get_ref() if _current != null else null
	return w as GameWifiWatch if is_instance_valid(w) else null


func _init() -> void:
	name = "GameWifiWatch"


func setup(host_table: Object) -> GameWifiWatch:
	host = host_table
	# Gerätetest 1.6.2 (F1): HostTable erkennt das eigene Spiel-WLAN (wlan.ap) über diesen Watch, nicht an der Bindung – bis Android 15
	# bleibt sie mit Spiel-WLAN und WLAN zugleich "" (host_plan). Eine eingespritzte Prüfung (Tests) bleibt.
	if host != null and "hotspot_check" in host:
		var c: Variant = host.get("hotspot_check")
		if not (c is Callable and (c as Callable).is_valid()):
			host.set("hotspot_check", own_open)
	return self


# Ist das eigene Spiel-WLAN offen (letzter Zustand) bzw. der Prozess an den eigenen Hotspot gebunden (Android 16+ ohne WLAN)?
func own_open() -> bool:
	return str(state.get("status", "")) == "on" or str(binding_source.call()) == "hotspot"


func _enter_tree() -> void:
	_current = weakref(self)


func _exit_tree() -> void:
	if current() == self:
		_current = null
	if host != null and is_instance_valid(host) and "hotspot_check" in host:
		var c: Variant = host.get("hotspot_check")
		if c is Callable and (c as Callable).get_object() == self:
			host.set("hotspot_check", Callable())


func _process(_delta: float) -> void:
	if not manual:
		tick()


# Ein Schritt (aus _process bzw. in Tests von Hand): automatisches Öffnen fortführen, alle POLL_MS das Netz bewerten.
func tick() -> void:
	var now := _now()
	if (auto_state == "running" and now >= _auto_poll) or (auto_state == "waiting" and now >= _retry_at):
		_auto_poll = now + AUTO_POLL_MS
		_auto_step(now)
	if not _started or now >= _next_poll:
		poll()


# Netz bewerten (sofort). Ändert sich etwas: rebind, refresh_addrs, changed.
func poll() -> void:
	var now := _now()
	_next_poll = now + POLL_MS
	var first := not _started
	_started = true
	if bool(available_source.call()):
		var st: Variant = state_source.call()
		state = st if st is Dictionary else {}
	else:
		state = {"status": "off", "error": "unsupported"}
	var on := str(state.get("status", "")) == "on"
	var acted := false
	if on:
		_close_at = 0
		if address == "":
			address = str(_call_or(address_source, _own_address))
	elif _was_on and not _closing:
		lost.emit("own")
	if not on and str(state.get("status", "")) != "starting":
		_closing = false
		if not _rebound:
			address = ""
	_was_on = on
	if on and address != "" and not _rebound:
		_rebound = true
		_rebind(false)
		acted = true
	elif _rebound and not on and str(state.get("status", "")) != "starting":
		if _close_at == 0:
			_close_at = now
		if str(_call_or(address_source, _own_address)) == "" or now - _close_at >= REBIND_WAIT_MS:
			_rebound = false
			_close_at = 0
			address = ""
			_rebind(true)
			acted = true
	var now_addrs: Array = _addrs()
	var now_bound := str(binding_source.call())
	if not acted and (first or now_bound != bound or now_addrs != addrs):
		_rebind(false)
		acted = true
	if acted:
		bound = str(binding_source.call())
		addrs = _addrs()
		if host != null and host.has_method("refresh_addrs"):
			host.refresh_addrs()
		changed.emit()
	_check_foreign()


# Eigenes Spiel-WLAN ohne Tippen öffnen. "" = läuft bzw. schon offen; "permission" = Erlaubnis fehlt (die Oberfläche zeigt
# „Spiel-WLAN öffnen“ mit dem Erlaubnisdialog); "unsupported"; "ap_running" = der normale Hotspot läuft (die App ändert ihn nie).
func auto_open() -> String:
	# Gegenprüfung 1.6.2: Läuft schon ein Versuch (bzw. wartet er auf die nächste Wiederholung), nichts neu anstoßen – ein zweites
	# startLocalOnlyHotspot kann scheitern (incompatible_mode) und setzte die Wiederholungen zurück.
	if auto_state in ["running", "waiting"]:
		return ""
	auto_tries = 0
	auto_error = ""
	if not bool(available_source.call()):
		return _give_up("unsupported", false)
	var st: Variant = state_source.call()
	state = st if st is Dictionary else {}
	match str(state.get("status", "")):
		"on":
			auto_state = "done"
			_next_poll = 0
			return ""
		"starting":
			auto_state = "running"
			_attempt_at = _now()
			return ""
	if not bool(state.get("granted", true)):
		auto_state = "permission"
		auto_error = "permission"
		return "permission"
	if int(state.get("ap_enabled", -1)) == 1:
		return _give_up("ap_running", false)
	_attempt(_now())
	return "" if auto_state in ["running", "waiting", "done"] else auto_error


# Spiel-WLAN schließen (Knopf); kein lost("own"), die Sitzung wird wie im Panel zurückgebunden.
func close() -> void:
	_closing = true
	auto_state = ""
	stop_source.call()
	_next_poll = 0


func _attempt(now: int) -> void:
	auto_tries += 1
	if bool(qr_active.call()):
		qr_release.call()                 # STA/AP: das fremde Spiel-WLAN zuerst verlassen (10.8)
	_before = _hotspot_addresses()
	address = ""
	_rebound = false
	_closing = false
	auto_state = "running"
	auto_error = str(start_source.call())
	_attempt_at = now
	_auto_poll = now + AUTO_POLL_MS
	if auto_error != "":
		_attempt_failed(now)
	else:
		_auto_step(now)


func _auto_step(now: int) -> void:
	if auto_state == "waiting":
		if now >= _retry_at:
			_attempt(now)
		return
	var st: Variant = state_source.call()
	state = st if st is Dictionary else {}
	match str(state.get("status", "")):
		"on":
			auto_state = "done"
			auto_error = ""
			_next_poll = 0                    # gleich neu binden
			auto_done.emit(true, "")
		"failed", "stopped":
			auto_error = str(state.get("error", ""))
			if auto_error == "":
				auto_error = "generic" if str(state.get("status", "")) == "failed" else "stopped"
			_attempt_failed(now)
		_:
			if now - _attempt_at >= AUTO_WAIT_MS:
				auto_error = "generic"
				_attempt_failed(now)


func _attempt_failed(now: int) -> void:
	var worth := not auto_error in NO_RETRY and (auto_error == "incompatible_mode" or bool(_call_or(old_net, _in_old_net)))
	if worth and auto_tries <= AUTO_RETRIES:
		auto_state = "waiting"
		_retry_at = now + AUTO_GAP_MS
		return
	_give_up(auto_error, true)


func _give_up(error: String, emit: bool) -> String:
	auto_state = "failed"
	auto_error = error
	if emit:
		auto_done.emit(false, error)
	return error


func _rebind(after_close: bool) -> void:
	var session = host.get("session") if host != null else null
	if session != null and session.has_method("rebind"):
		hint = str(session.rebind(after_close))


func _check_foreign() -> void:
	if not foreign_ap or _foreign_lost:
		return
	var gone := false
	if bool(qr_active.call()):
		var q: Variant = qr_state.call()
		gone = q is Dictionary and str((q as Dictionary).get("status", "")) in ["lost", "unavailable"]
	if not gone and addrs.is_empty() and _started:
		gone = true                       # über die Systemeinstellungen beigetreten: keine eigene Adresse mehr
	if gone:
		_foreign_lost = true
		lost.emit("foreign")


func _now() -> int:
	return int(now_ms.call())


func _addrs() -> Array:
	var a: Variant = _call_or(addrs_source, _own_addrs)
	return (a as Array).duplicate() if a is Array else []


func _call_or(c: Callable, fallback: Callable) -> Variant:
	return c.call() if c.is_valid() else fallback.call()


func _own_addrs() -> Array:
	return NetAddresses.own_addresses().map(func(a): return str(a.address))


func _hotspot_addresses() -> Array:
	if NetAndroid.wifi_stub is Dictionary or not NetAndroid.available():
		return []
	return NetAndroid.hotspot_addresses(NetAndroid.state())


func _own_address() -> String:
	if NetAndroid.wifi_stub is Dictionary:
		return str(NetAndroid.wifi_stub.get("address", "")) if str(state.get("status", "")) == "on" else ""
	if not NetAndroid.available():
		return ""
	return NetAndroid.game_wifi_address(NetAndroid.state(), _before)


func _in_old_net() -> bool:
	# Hängt das Gerät noch in einem WLAN (System-WLAN, Kamera-QR) und kann WLAN und Spiel-WLAN nicht gleichzeitig?
	if bool(qr_active.call()):
		return true
	if NetAndroid.wifi_stub is Dictionary or not NetAndroid.available():
		return false
	return NetAndroid.wifi_connected(NetAndroid.state()) and not bool(state.get("concurrency", false))
