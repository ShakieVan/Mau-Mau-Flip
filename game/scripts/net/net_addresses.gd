class_name NetAddresses
extends RefCounted

# Eigene Adressen für QR-Code und Suche. Dünne Hülle um NetAndroid (res://scripts/app/net_android.gd, Modul C, nach dem Muster von
# Draw2Race: state(), interfaces(), wifi_addresses(s), hotspot_addresses(s), multicast(bool), wifi_gateway(s)). Fehlt das Skript oder
# eine Funktion, gilt IP.get_local_interfaces() mit Einordnung nach Schnittstellennamen (Präfix /24 angenommen).
# Reihenfolge für den QR-Code: WLAN, eigener Hotspot, LAN, Sonstiges, virtuelle Adapter. Mobilfunk (rmnet, ccmni, CLAT 192.0.0.x …),
# Loopback und Link-local erscheinen nie. Nur Hauptthread (JNI).

const HELPER_PATH := "res://scripts/app/net_android.gd"
const MOBILE := ["rmnet", "v4-", "ccmni", "clat", "pdp", "seth", "ppp", "dummy", "umts", "wwan", "ipsec", "p2p", "aware", "nan"]
const HOTSPOT := ["swlan", "softap", "ap", "wlan1", "wlan2"]
const VIRTUAL := ["vethernet", "virtualbox", "vmware", "hyper-v", "wsl", "loopback", "bluetooth", "tailscale", "zerotier", "docker",
	"vpn", "tap", "tun", "utun", "npcap", "hamachi", "radmin", "lan-verbindung*", "local area connection*"]
const ORDER := ["wlan", "hotspot", "lan", "other", "virtual"]
const CACHE_MS := 3000

static var override_interfaces = null   # Tests: [{name, address, prefix}] statt der echten Schnittstellen
static var _helper: Object = null
static var _helper_checked := false
static var _helper_methods := {}
static var _cache: Array = []
static var _cache_ms := -100000

static func helper() -> Object:
	# NetAndroid von Modul C, falls vorhanden und ladbar.
	if not _helper_checked:
		_helper_checked = true
		if ResourceLoader.exists(HELPER_PATH):
			var s = load(HELPER_PATH)
			if s is GDScript:
				set_helper(s)
	return _helper

static func set_helper(obj: Object) -> void:
	# Tests: Ersatz für NetAndroid (ein Objekt mit denselben Methoden); null = wieder das echte Skript laden.
	_helper = obj
	_helper_checked = obj != null
	_helper_methods = {}
	if obj is GDScript:
		for m in (obj as GDScript).get_script_method_list():
			_helper_methods[str(m.name)] = true

static func _has(method: String) -> bool:
	var h := helper()
	if h == null:
		return false
	return _helper_methods.has(method) if h is GDScript else h.has_method(method)

static func _call(method: String, args := []) -> Variant:
	if not _has(method):
		return null
	return _helper.callv(method, args)

static func classify(iface: String) -> String:
	# Art einer Schnittstelle nach ihrem Namen (Android: wlan0/swlan0/rmnet…, Windows: Anzeigename).
	var n := iface.to_lower()
	for p in MOBILE:
		if n.begins_with(p):
			return "mobile"
	for p in HOTSPOT:
		if n.begins_with(p):
			return "hotspot"
	for p in VIRTUAL:
		if n.begins_with(p) or n.contains(p):
			return "virtual"
	if n.begins_with("wlan") or n.begins_with("wi-fi") or n.begins_with("wifi") or n.begins_with("wl") or n.contains("wireless"):
		return "wlan"
	if n.begins_with("eth") or n.begins_with("en") or n.begins_with("ethernet") or n.begins_with("lan"):
		return "lan"
	return "other"

static func interfaces() -> Array:
	# Eigene IPv4-Adressen [{name, address, prefix, broadcast}] ohne Loopback, Link-local und CLAT.
	var raw := []
	if override_interfaces is Array:
		raw = override_interfaces
	else:
		var data = _call("interfaces")
		if data is Array:
			raw = data
		else:
			for iface in IP.get_local_interfaces():
				for a in iface.get("addresses", []):
					raw.append({"name": str(iface.get("friendly", iface.get("name", ""))), "address": str(a), "prefix": 24})
	var out := []
	for entry in raw:
		if not entry is Dictionary:
			continue
		var address := str(entry.get("address", ""))
		if not NetProtocol.usable_ipv4(address) or out.any(func(o): return o.address == address):
			continue
		var prefix := int(entry.get("prefix", 24))
		var bc := str(entry.get("broadcast", ""))
		if NetProtocol.ipv4_to_int(bc) <= 0:
			bc = NetProtocol.directed_broadcast(address, prefix)
		out.append({"name": str(entry.get("name", "")), "address": address, "prefix": prefix, "broadcast": bc})
	return out

static func own_addresses(max_age_ms := CACHE_MS) -> Array:
	# Adressen für QR-Code und Anzeige: [{address, kind ("wlan"|"hotspot"|"lan"|"other"|"virtual"), iface}], beste zuerst.
	var now := Time.get_ticks_msec()
	if now - _cache_ms <= max_age_ms and override_interfaces == null:
		return _cache.duplicate(true)
	var wlan := {}
	var spots := {}
	if override_interfaces == null and _has("state") and _has("wifi_addresses") and _has("hotspot_addresses"):
		var s = _call("state")
		if s is Dictionary and bool(s.get("android", false)):
			for a in _helper.callv("wifi_addresses", [s]):
				wlan[str(a)] = true
			for a in _helper.callv("hotspot_addresses", [s]):
				spots[str(a)] = true
	var out := []
	for i in interfaces():
		var kind := classify(str(i.name))
		if wlan.has(i.address):
			kind = "wlan"
		elif spots.has(i.address):
			kind = "hotspot"
		if kind == "mobile":
			continue
		out.append({"address": i.address, "kind": kind, "iface": i.name})
	out.sort_custom(func(a, b):
		var ra := ORDER.find(a.kind) * 2 + (0 if NetProtocol.is_private_ipv4(a.address) else 1)
		var rb := ORDER.find(b.kind) * 2 + (0 if NetProtocol.is_private_ipv4(b.address) else 1)
		return ra < rb)
	if override_interfaces == null:
		_cache = out.duplicate(true)
		_cache_ms = now
	return out

static func urls(port: int) -> Array:
	# "http://<adresse>:<port>/" je eigener Adresse, beste zuerst (QR-Code nimmt die erste).
	return own_addresses().map(func(a): return "http://%s:%d/" % [a.address, port])

static func broadcast_targets() -> Array:
	# Ziele der Suche: gerichteter Rundruf je Schnittstelle (ohne Mobilfunk) und 255.255.255.255.
	var out := ["255.255.255.255"]
	for i in interfaces():
		if classify(str(i.name)) != "mobile" and i.broadcast != "" and not out.has(i.broadcast):
			out.append(i.broadcast)
	return out

static func multicast(acquire: bool) -> bool:
	# Multicast-Sperre (Android, sonst false). Godot nimmt für Rundruf-Sockets zusätzlich selbst eine.
	var r = _call("multicast", [acquire])
	return r is bool and r

static func gateway() -> String:
	# Gateway des WLANs (im Handy-Hotspot ist das der Gastgeber), "" wenn unbekannt.
	if not _has("wifi_gateway"):
		return ""
	var s = _call("state") if _has("state") else {}
	var g = _helper.callv("wifi_gateway", [s if s is Dictionary else {}])
	return str(g) if g is String and NetProtocol.ipv4_to_int(str(g)) > 0 else ""

# --- WLAN-Bindung (Android, Regeln aus Draw2Race NetLobby._bind, dort auf Geräten erprobt) ---
# Ein WLAN ohne Internet (Handy-Hotspot im Urlaub) wird bei eingeschalteten mobilen Daten nie Androids Standardnetz; ungebundene
# Sockets liefen dann ins Mobilnetz. Darum bindet sich der Prozess vor dem Anlegen der Sockets ans passende Netz – die Bindung gilt nur
# für danach erzeugte Sockets. Zwecke: "search" (Suche), "join" (Beitritt zu address), "host" (Eröffnen). Gelöst wird erst, wenn kein
# Zweck mehr bindet (release), damit Update-Suche und Internet wieder gehen. Am PC und ohne NetAndroid: nichts zu tun.

static var use_binding := true
static var bound_to := ""                # "wifi" | "hotspot" | "" – Bindung der zuletzt angelegten Sockets
static var bind_problem := ""
static var _owners := {}
static var _last_address := {}          # letzte Adresse je Zweck (für das Wiederherstellen nach einer Internet-Anfrage)

static func _android_state() -> Dictionary:
	if not use_binding or override_interfaces != null or not _has("state"):
		return {}
	var s = _call("state")
	return s if s is Dictionary and bool(s.get("android", false)) else {}

static func bind_for(purpose: String, address := "") -> String:
	# Vor dem Anlegen neuer Sockets aufrufen. Ergebnis: woran die gleich entstehenden Sockets gebunden sind ("wifi", "hotspot", "").
	_owners[purpose] = true
	_last_address[purpose] = address
	bind_problem = ""
	if holding() > 0:
		_rebind = true       # ausgesetzt (Internet-Verbindung entsteht gerade): erst beim Freigeben binden
		return ""
	var s := _android_state()
	if s.is_empty() or not ["wifi_handle", "hotspot_addresses", "host_plan", "join_binding", "in_hotspot", "bind_wifi", "bind_network",
			"hotspot_handle", "unbind", "bound_to_wifi"].all(func(m): return _has(m)):
		return ""
	var wifi := str(_helper.callv("wifi_handle", [s]))
	var spots: Array = _helper.callv("hotspot_addresses", [s])
	var target := "wifi"
	if purpose == "host" and not spots.is_empty():
		target = str((_helper.callv("host_plan", [s]) as Dictionary).get("bind", ""))
	elif purpose == "join" and bool(_helper.callv("in_hotspot", [s, address])):
		target = str(_helper.callv("join_binding", [s, address]))
	if target == "hotspot":
		var problem := Updater.java_text(str(_helper.callv("bind_network", [_helper.callv("hotspot_handle", [s])])))
		if problem == "":
			bound_to = "hotspot"
			return bound_to
		bind_problem = problem
		target = ""
	if target == "" or wifi == "":
		if s.get("bound") is Dictionary:
			_call("unbind")
		bound_to = ""
		if target != "" and wifi == "":
			bind_problem = I18n.t("Kein WLAN verbunden.")
		return ""
	if bool(_helper.callv("bound_to_wifi", [s])):
		bound_to = "wifi"
		return bound_to
	var err := Updater.java_text(str(_call("bind_wifi")))
	bound_to = "wifi" if err == "" else ""
	bind_problem = err
	return bound_to

# Internet-Verbindungen (Update-Prüfung, APK-Download, Verbindung zum Vermittler): Eine Bindung an ein Netz, das womöglich kein
# Internet hat (eigenes Spiel-WLAN ab Android 16, Spiel-WLAN eines anderen Gastgebers, WLAN ohne Internet), wird ausgesetzt, damit
# die neuen Sockets über das Standardnetz laufen (Nutzerbefund 07.10.2026: „Jetzt prüfen“ hing bei offenem Spiel-WLAN und meldete
# „Keine Verbindung.“). Mehrere Nutzer gleichzeitig (Updater, Vermittler-Gastgeber, Vermittler-Gast) halten je einen Halt
# (hold_unbound, gezählt je Halter). Erst wenn der letzte Halt frei ist (release_hold) oder seine Frist abgelaufen ist (expire_holds),
# wird die vorige Bindung wiederhergestellt. Bestehende Sockets behalten ihr Netz. bind_for während eines Halts merkt sich den Zweck
# nur und bindet beim Wiederherstellen.
const HOLD_MS := 15000

static var clock_ms := -1               # nur Tests: feste Uhr statt Time.get_ticks_msec()
static var _holds := {}                 # Halter -> Frist (ms, 0 = ohne Frist)
static var _held_bound := ""            # Bindung vor dem ersten Halt
static var _rebind := false             # beim Freigeben neu binden
static var _after_holds: Array = []     # Callables, die nach dem Wiederherstellen laufen

static func _now() -> int:
	return clock_ms if clock_ms >= 0 else Time.get_ticks_msec()

static func holding() -> int:
	# Zahl der Halter (abgelaufene Fristen werden dabei geräumt).
	expire_holds()
	return _holds.size()

static func is_held(holder: String) -> bool:
	return _holds.has(holder)

static func binding() -> String:
	# Bindung, die gilt bzw. nach dem Aussetzen wieder gilt.
	return _held_bound if not _holds.is_empty() else bound_to

static func hold_unbound(holder: String, timeout_ms := HOLD_MS) -> void:
	# Bindung aussetzen, bis release_hold(holder) oder die Frist abläuft (timeout_ms <= 0: ohne Frist).
	expire_holds()
	if _holds.is_empty():
		_held_bound = bound_to
		_rebind = bound_to != ""
		if bound_to != "":
			_call("unbind")
			bound_to = ""
	_holds[holder] = (_now() + timeout_ms) if timeout_ms > 0 else 0

static func release_hold(holder: String) -> void:
	if not _holds.has(holder):
		return
	_holds.erase(holder)
	if _holds.is_empty():
		_restore()

static func expire_holds() -> void:
	if _holds.is_empty():
		return
	var now := _now()
	for holder in _holds.keys():
		var until := int(_holds[holder])
		if until > 0 and now >= until:
			_holds.erase(holder)
	if _holds.is_empty():
		_restore()

static func after_holds(callable: Callable) -> void:
	# callable läuft, sobald kein Halt mehr besteht (sofort, wenn keiner besteht).
	if holding() == 0:
		callable.call()
	else:
		_after_holds.append(callable)

static func _restore() -> void:
	var again := _rebind
	_rebind = false
	_held_bound = ""
	if again:
		for purpose in _owners.keys():
			bind_for(str(purpose), str(_last_address.get(purpose, "")))
	var calls := _after_holds
	_after_holds = []
	for c in calls:
		if (c as Callable).is_valid():
			(c as Callable).call()

static func suspend_for_internet() -> void:
	# Updater: Halt ohne Frist, resume_after_internet gibt ihn frei.
	hold_unbound("updater", 0)


static func resume_after_internet() -> void:
	release_hold("updater")


static func release(purpose: String) -> void:
	# Zweck beendet; ohne weitere Zwecke wird die Bindung gelöst.
	_owners.erase(purpose)
	_last_address.erase(purpose)
	if _owners.is_empty():
		_rebind = false
		_held_bound = ""
	if _owners.is_empty() and bound_to != "":
		_call("unbind")
		bound_to = ""
