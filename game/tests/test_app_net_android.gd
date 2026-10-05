extends SceneTree
# Modul C: NetAndroid (aus Draw2Race übernommen) – Einordnung von WLAN, eigenem Hotspot und Mobilnetz als reine Funktionen des
# Netzstatus, mit den Werten aus den Draw2Race-Geräteprotokollen (S24 Ultra, Android 16, 04.10.2026; S21, Android 15), dazu IPv4-Hilfen.

var ok := 0
var failed := 0

func check(cond: bool, text: String) -> void:
	if cond:
		ok += 1
	else:
		failed += 1
		print("FAIL: ", text)

const S24_WLAN := {"handle": "3233221103629", "transport": "wifi", "iface": "wlan0", "addresses": ["192.168.178.4/16"], "gateway": "192.168.178.1",
	"internet": true, "validated": true, "default": true}
const S24_SPOT := {"handle": "3237516070925", "transport": "wifi", "iface": "swlan0", "addresses": ["10.110.43.61/24"], "gateway": "",
	"internet": false, "validated": false, "default": false, "local": true}
const S24_MOBILE := {"handle": "432902426637", "transport": "mobile", "iface": "rmnet_data0", "addresses": ["192.0.0.2/27"], "gateway": "",
	"internet": true, "validated": true, "default": true}
const S24_IFACES := [{"name": "wlan0", "address": "192.168.178.4", "prefix": 16, "broadcast": "192.168.255.255"},
	{"name": "swlan0", "address": "10.110.43.61", "prefix": 24, "broadcast": "10.110.43.255"}]
const S24_RMNET := {"name": "rmnet_data0", "address": "192.0.0.2", "prefix": 27, "broadcast": "192.0.0.31"}

func s24(nets: Array, ifaces: Array, bound: Variant = null) -> Dictionary:
	return {"android": true, "networks": nets, "interfaces": ifaces, "bound": bound, "wifi_gateway": "", "dhcp_gateway": ""}

func _init() -> void:
	# IPv4-Hilfen
	check(NetAndroid.ipv4_to_int("192.168.1.2") == 0xC0A80102 and NetAndroid.ipv4_to_int("256.1.1.1") == -1 and NetAndroid.ipv4_to_int("1.2.3") == -1
		and NetAndroid.int_to_ipv4(0xC0A80102) == "192.168.1.2", "IPv4 in Zahl und zurück")
	check(NetAndroid.directed_broadcast("192.168.43.17", 24) == "192.168.43.255" and NetAndroid.directed_broadcast("10.0.5.9", 16) == "10.0.255.255"
		and NetAndroid.directed_broadcast("x", 24) == "", "gerichteter Rundruf")
	check(NetAndroid.usable_ipv4("192.168.1.2") and not NetAndroid.usable_ipv4("127.0.0.1") and not NetAndroid.usable_ipv4("169.254.3.4")
		and not NetAndroid.usable_ipv4("0.0.0.0"), "brauchbare eigene Adresse")
	# Einfacher Fall (Draw2Race test_lobby): WLAN plus Hotspot-Schnittstelle, Mobilfunk und CLAT zählen nicht.
	var raw := {"android": true, "networks": [{"transport": "wifi", "addresses": ["192.168.1.20/24"]}, {"transport": "mobile", "addresses": ["10.1.2.3/30"]}],
		"interfaces": [{"name": "wlan0", "address": "192.168.1.20"}, {"name": "rmnet_data0", "address": "10.1.2.3"}, {"name": "swlan0", "address": "172.17.251.1"},
		{"name": "v4-rmnet_data1", "address": "192.0.0.4"}]}
	check(NetAndroid.wifi_connected(raw) and NetAndroid.hotspot_addresses(raw) == ["172.17.251.1"], "WLAN erkannt, Hotspot-Adresse ohne Mobil-/CLAT-Schnittstellen")
	raw.networks = [raw.networks[1]]
	check(not NetAndroid.wifi_connected(raw) and not NetAndroid.wifi_connected({"android": false, "interfaces": []}), "ohne WLAN: kein WLAN gemeldet")
	# S24: WLAN und Hotspot zugleich (Android 16 meldet den Hotspot als lokales Netz).
	var both := s24([S24_WLAN, S24_SPOT], S24_IFACES)
	var plan := NetAndroid.host_plan(both)
	check(NetAndroid.hotspot_network(S24_SPOT) and not NetAndroid.hotspot_network(S24_WLAN) and not NetAndroid.hotspot_network(S24_MOBILE), "S24: swlan0 ist der eigene Hotspot")
	check(NetAndroid.wifi_handle(both) == "3233221103629" and NetAndroid.wifi_addresses(both) == ["192.168.178.4"] and NetAndroid.hotspot_addresses(both) == ["10.110.43.61"],
		"S24: WLAN = wlan0, Hotspot = 10.110.43.61")
	check(plan.bind == "" and plan.reach == ["wlan", "hotspot"] and plan.hint != "" and not plan.warn, "S24 als Gastgeber: ungebunden, in beiden Netzen erreichbar")
	check(NetAndroid.in_hotspot(both, "10.110.43.150") and not NetAndroid.in_hotspot(both, "192.168.178.20"), "Mitspieler im eigenen Hotspot erkannt")
	var tied := NetAndroid.host_plan(both, "wifi")
	check(tied.reach == ["wlan"] and tied.warn and tied.hint.contains("neu eröffnest"), "gebundene Sockets: nur WLAN, Hinweis „neu eröffnen“")
	# Bis Android 15: Hotspot nur als Schnittstelle.
	var old := s24([S24_WLAN], S24_IFACES)
	check(NetAndroid.hotspot_addresses(old) == ["10.110.43.61"] and NetAndroid.host_plan(old).bind == "", "Android 15: Hotspot als Schnittstelle, ungebunden")
	# WLAN aus: Mobilnetz Standard, Bindung zeigt aufs verlorene WLAN.
	var lost_bind := {"handle": "3233221103629", "transport": "?", "addresses": [], "gateway": ""}
	var off := s24([S24_MOBILE, S24_SPOT], [S24_IFACES[1], S24_RMNET], lost_bind)
	var off_plan := NetAndroid.host_plan(off)
	check(not NetAndroid.wifi_connected(off) and not NetAndroid.bound_to_wifi(off) and off_plan.bind == "hotspot" and off_plan.reach == ["hotspot"]
		and NetAndroid.hotspot_handle(off) == "3237516070925", "WLAN aus: Gastgeber bindet an den eigenen Hotspot")
	check(NetAndroid.join_binding(both, "10.110.43.150") == "hotspot" and NetAndroid.join_binding(old, "10.110.43.150") == ""
		and NetAndroid.join_binding(both, "192.168.178.20") == "wifi", "Beitritt: Bindung nach Lage des Gastgebers")
	var home := NetAndroid.host_plan(s24([S24_WLAN], [S24_IFACES[0]]))
	check(home.bind == "wifi" and home.reach == ["wlan"] and home.hint == "", "ohne Hotspot: Gastgeber bindet ans WLAN")
	var dull: Dictionary = S24_WLAN.merged({"validated": false, "default": false}, true)
	var dull_plan := NetAndroid.host_plan(s24([dull, S24_MOBILE, S24_SPOT], S24_IFACES + [S24_RMNET]))
	check(dull_plan.reach == ["hotspot"] and dull_plan.warn and dull_plan.hint.contains("kein Internet"), "WLAN ohne Internet: klare Warnung")
	check(NetAndroid.summary(both).size() > 3 and NetAndroid.in_subnet("192.168.1.9", "192.168.178.4", 16) and not NetAndroid.in_subnet("10.110.44.1", "10.110.43.61", 24),
		"Zusammenfassung und Netzvergleich")
	print("RESULT: %d ok" % ok)
	quit(1 if failed > 0 else 0)
