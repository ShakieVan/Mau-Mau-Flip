extends SceneTree

# Modul D, WLAN-Bindung und QR-Adressen auf Android ohne Gerät: NetAddresses mit einem Ersatz für NetAndroid, der die echten
# Entscheidungsregeln von Modul C (res://scripts/app/net_android.gd: wifi_handle, host_plan, join_binding …) auf erfundene
# Netzzustände anwendet und nur die Java-Aufrufe (bind_wifi, bind_network, unbind, multicast) mitschreibt. Fälle nach den
# Draw2Race-Geräteprotokollen: Heim-WLAN, Hotspot plus WLAN, nur Hotspot (Android 16 als eigenes Netz, Android 15 nur Schnittstelle),
# Gastgeber im eigenen Hotspot, Freigabe erst nach dem letzten Zweck.

const ANDROID_PATH := "res://scripts/app/net_android.gd"

var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)

class FakeAndroid:
	extends RefCounted
	var real                       # das echte NetAndroid-Skript (statische Regeln)
	var s := {}
	var calls: Array = []

	func state() -> Dictionary:
		return s.duplicate(true)
	func interfaces() -> Array:
		return s.get("interfaces", [])
	func wifi_handle(st: Dictionary) -> String:
		return real.wifi_handle(st)
	func wifi_addresses(st: Dictionary) -> Array:
		return real.wifi_addresses(st)
	func hotspot_addresses(st: Dictionary) -> Array:
		return real.hotspot_addresses(st)
	func hotspot_handle(st: Dictionary) -> String:
		return real.hotspot_handle(st)
	func host_plan(st: Dictionary, sockets = null) -> Dictionary:
		return real.host_plan(st, sockets)
	func join_binding(st: Dictionary, address: String) -> String:
		return real.join_binding(st, address)
	func in_hotspot(st: Dictionary, address: String) -> bool:
		return real.in_hotspot(st, address)
	func bound_to_wifi(st: Dictionary) -> bool:
		return real.bound_to_wifi(st)
	func wifi_gateway(st := {}) -> String:
		return real.wifi_gateway(st)
	func bind_wifi() -> String:
		calls.append("bind_wifi")
		return ""
	func bind_network(handle: String) -> String:
		calls.append("bind_network " + handle)
		return ""
	func unbind() -> bool:
		calls.append("unbind")
		return true
	func multicast(acquire: bool) -> bool:
		calls.append("multicast %s" % acquire)
		return true

func home_wifi() -> Dictionary:
	return {"android": true, "bound": null, "networks": [
		{"transport": "wifi", "iface": "wlan0", "addresses": ["192.168.178.40/24"], "gateway": "192.168.178.1", "handle": "101",
			"default": true, "internet": true, "validated": true},
		{"transport": "mobile", "iface": "rmnet_data0", "addresses": ["10.180.3.4/30"], "gateway": "10.180.3.5", "handle": "102",
			"default": false, "internet": true}],
		"interfaces": [{"name": "wlan0", "address": "192.168.178.40", "prefix": 24}, {"name": "rmnet_data0", "address": "10.180.3.4", "prefix": 30}]}

func hotspot_and_wifi() -> Dictionary:
	# S21 (Android 15): eigener Hotspot nur als Schnittstelle swlan0, dazu im Heim-WLAN.
	var s := home_wifi()
	s.interfaces.append({"name": "swlan0", "address": "172.17.251.253", "prefix": 24})
	return s

func hotspot_only_16() -> Dictionary:
	# S24 Ultra (Android 16): eigener Hotspot als „lokales Netz“, kein WLAN, mobile Daten an.
	return {"android": true, "bound": null, "networks": [
		{"transport": "wifi", "iface": "swlan0", "addresses": ["10.110.43.61/24"], "gateway": "", "handle": "303", "local": true,
			"default": false, "internet": false},
		{"transport": "mobile", "iface": "rmnet_data0", "addresses": ["10.180.3.4/30"], "gateway": "10.180.3.5", "handle": "102",
			"default": true, "internet": true}],
		"interfaces": [{"name": "swlan0", "address": "10.110.43.61", "prefix": 24}, {"name": "rmnet_data0", "address": "10.180.3.4", "prefix": 30}]}

func hotspot_only_15() -> Dictionary:
	# S21 (Android 15) mit Hotspot, ohne WLAN: der Hotspot ist kein Netz, nur eine Schnittstelle.
	return {"android": true, "bound": null, "networks": [
		{"transport": "mobile", "iface": "rmnet_data0", "addresses": ["10.180.3.4/30"], "gateway": "10.180.3.5", "handle": "102",
			"default": true, "internet": true}],
		"interfaces": [{"name": "swlan0", "address": "172.17.251.253", "prefix": 24}, {"name": "rmnet_data0", "address": "10.180.3.4", "prefix": 30}]}

func _init() -> void:
	if not ResourceLoader.exists(ANDROID_PATH):
		print("RESULT: 0 ok (NetAndroid fehlt – übersprungen)")
		quit(0)
		return
	var fake := FakeAndroid.new()
	fake.real = load(ANDROID_PATH)
	NetAddresses.set_helper(fake)

	# Heim-WLAN: Mitspieler bindet ans WLAN; QR-Adresse nur die WLAN-Adresse (Mobilfunk nie).
	fake.s = home_wifi()
	check(NetAddresses.bind_for("join", "192.168.178.20") == "wifi" and fake.calls == ["bind_wifi"], "Beitritt im Heim-WLAN → ans WLAN gebunden %s" % str(fake.calls))
	var own := NetAddresses.own_addresses(-1)
	check(own.map(func(a): return [a.address, a.kind]) == [["192.168.178.40", "wlan"]], "QR: nur WLAN-Adresse (%s)" % str(own))
	check(NetAddresses.broadcast_targets() == ["255.255.255.255", "192.168.178.255"], "Suche: Rundruf ins WLAN, nicht ins Mobilnetz (%s)" % str(NetAddresses.broadcast_targets()))
	check(NetAddresses.gateway() == "192.168.178.1", "WLAN-Gateway für die Suche")
	# schon richtig gebunden: kein zweites bind
	fake.calls.clear()
	fake.s.bound = {"transport": "wifi", "handle": "101"}
	check(NetAddresses.bind_for("search") == "wifi" and fake.calls.is_empty(), "schon ans WLAN gebunden → nichts zu tun")
	NetAddresses.release("search")
	check(fake.calls.is_empty(), "release: ein anderer Zweck (join) bindet noch")
	NetAddresses.release("join")
	check(fake.calls == ["unbind"] and NetAddresses.bound_to == "", "letzter Zweck beendet → gelöst")

	# Gastgeber mit Hotspot und WLAN: ungebunden (Mitspieler in beiden Netzen); QR zeigt beide, WLAN zuerst.
	fake.calls.clear()
	fake.s = hotspot_and_wifi()
	check(NetAddresses.bind_for("host") == "" and fake.calls.is_empty(), "Gastgeber mit Hotspot und WLAN → ungebunden %s" % str(fake.calls))
	own = NetAddresses.own_addresses(-1)
	check(own.map(func(a): return [a.address, a.kind]) == [["192.168.178.40", "wlan"], ["172.17.251.253", "hotspot"]], "QR: WLAN, dann Hotspot (%s)" % str(own))
	NetAddresses.release("host")

	# Nur Hotspot, Android 16: an das Hotspot-Netz binden.
	fake.calls.clear()
	fake.s = hotspot_only_16()
	check(NetAddresses.bind_for("host") == "hotspot" and fake.calls == ["bind_network 303"], "nur Hotspot (Android 16) → an den Hotspot gebunden %s" % str(fake.calls))
	own = NetAddresses.own_addresses(-1)
	check(own.map(func(a): return [a.address, a.kind]) == [["10.110.43.61", "hotspot"]], "QR: Hotspot-Adresse (%s)" % str(own))
	NetAddresses.release("host")
	check(fake.calls.back() == "unbind", "Gastgeber beendet → gelöst")

	# Nur Hotspot, Android 15: ungebunden (Hotspot ist kein Netz), eine alte Bindung wird gelöst.
	fake.calls.clear()
	fake.s = hotspot_only_15()
	fake.s.bound = {"transport": "wifi", "handle": "101"}
	check(NetAddresses.bind_for("host") == "" and fake.calls == ["unbind"], "nur Hotspot (Android 15) → ungebunden, alte Bindung gelöst %s" % str(fake.calls))
	NetAddresses.release("host")

	# Mitspieler, dessen Gastgeber im eigenen Hotspot liegt (Android 15): ungebunden.
	fake.calls.clear()
	fake.s = hotspot_only_15()
	check(NetAddresses.bind_for("join", "172.17.251.10") == "" and fake.calls.is_empty(), "Gastgeber im eigenen Hotspot → ungebunden %s" % str(fake.calls))
	# Kein WLAN, Beitritt zu einer fremden Adresse: Hinweis, keine Bindung.
	check(NetAddresses.bind_for("join", "192.168.1.9") == "" and NetAddresses.bind_problem == "Kein WLAN verbunden.", "ohne WLAN: Hinweis")
	NetAddresses.release("join")

	# Multicast-Sperre über NetAndroid
	fake.calls.clear()
	check(NetAddresses.multicast(true) and fake.calls == ["multicast true"], "Multicast-Sperre geholt")
	# ohne Bindung (Schalter aus) passiert nichts
	NetAddresses.use_binding = false
	fake.calls.clear()
	fake.s = home_wifi()
	check(NetAddresses.bind_for("join", "192.168.178.20") == "" and fake.calls.is_empty(), "use_binding=false → keine Bindung")
	NetAddresses.release("join")
	NetAddresses.use_binding = true
	NetAddresses.set_helper(null)
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)
