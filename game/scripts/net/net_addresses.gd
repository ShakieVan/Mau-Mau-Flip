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

static func _android_state() -> Dictionary:
	if not use_binding or override_interfaces != null or not _has("state"):
		return {}
	var s = _call("state")
	return s if s is Dictionary and bool(s.get("android", false)) else {}

static func bind_for(purpose: String, address := "") -> String:
	# Vor dem Anlegen neuer Sockets aufrufen. Ergebnis: woran die gleich entstehenden Sockets gebunden sind ("wifi", "hotspot", "").
	_owners[purpose] = true
	bind_problem = ""
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
		var problem := str(_helper.callv("bind_network", [_helper.callv("hotspot_handle", [s])]))
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
			bind_problem = "Kein WLAN verbunden."
		return ""
	if bool(_helper.callv("bound_to_wifi", [s])):
		bound_to = "wifi"
		return bound_to
	var err := str(_call("bind_wifi"))
	bound_to = "wifi" if err == "" else ""
	bind_problem = err
	return bound_to

static func release(purpose: String) -> void:
	# Zweck beendet; ohne weitere Zwecke wird die Bindung gelöst.
	_owners.erase(purpose)
	if _owners.is_empty() and bound_to != "":
		_call("unbind")
		bound_to = ""
