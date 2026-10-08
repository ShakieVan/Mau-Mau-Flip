extends SceneTree

# Beta 1.3.3: Netzbindung aussetzen für Internet-Verbindungen (NetAddresses.hold_unbound/release_hold/expire_holds). Auf Android 16
# bindet der Gastgeber mit offenem Spiel-WLAN den Prozess ans Hotspot-Netz ohne Internet; neue Sockets zum Vermittler liefen dann
# dorthin. Geprüft mit einem Ersatz für NetAndroid (nur die Java-Aufrufe werden mitgeschrieben):
#  1. Zähler: verschachtelte Halter, Frist, Bindungswunsch während des Halts, after_holds, Updater (suspend/resume) unverändert.
#  2. NetRelayHost und NetClient (online) setzen beim Verbinden aus und geben bei „offen“ bzw. beim Fehlschlag wieder frei
#     (Vermittler-Nachbau NetRelayDouble auf 127.0.0.1:24786).
#  3. Letzter Raumcode (AppSettings „letzter_raum“): bereinigt, Standard-Vermittler nicht gespeichert, übersteht einen Neustart.

const ANDROID_PATH := "res://scripts/app/net_android.gd"
const PORT := 24786

var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)

class FakeAndroid:
	extends RefCounted
	var real
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
		s.bound = {"transport": "wifi", "handle": real.wifi_handle(s)}
		return ""
	func bind_network(handle: String) -> String:
		calls.append("bind_network " + handle)
		s.bound = {"transport": "wifi", "handle": handle}
		return ""
	func unbind() -> bool:
		calls.append("unbind")
		s.bound = null
		return true

func home_wifi() -> Dictionary:
	return {"android": true, "bound": null, "networks": [
		{"transport": "wifi", "iface": "wlan0", "addresses": ["192.168.178.40/24"], "gateway": "192.168.178.1", "handle": "101",
			"default": true, "internet": true, "validated": true},
		{"transport": "mobile", "iface": "rmnet_data0", "addresses": ["10.180.3.4/30"], "gateway": "10.180.3.5", "handle": "102",
			"default": false, "internet": true}],
		"interfaces": [{"name": "wlan0", "address": "192.168.178.40", "prefix": 24}, {"name": "rmnet_data0", "address": "10.180.3.4", "prefix": 30}]}

func hotspot_only_16() -> Dictionary:
	return {"android": true, "bound": null, "networks": [
		{"transport": "wifi", "iface": "swlan0", "addresses": ["10.110.43.61/24"], "gateway": "", "handle": "303", "local": true,
			"default": false, "internet": false},
		{"transport": "mobile", "iface": "rmnet_data0", "addresses": ["10.180.3.4/30"], "gateway": "10.180.3.5", "handle": "102",
			"default": true, "internet": true}],
		"interfaces": [{"name": "swlan0", "address": "10.110.43.61", "prefix": 24}, {"name": "rmnet_data0", "address": "10.180.3.4", "prefix": 30}]}

func _init() -> void:
	if not ResourceLoader.exists(ANDROID_PATH):
		print("RESULT: 0 ok (NetAndroid fehlt – übersprungen)")
		quit(0)
		return
	var fake := FakeAndroid.new()
	fake.real = load(ANDROID_PATH)
	NetAddresses.set_helper(fake)
	test_counter(fake)
	test_sockets(fake)
	NetAddresses.set_helper(null)
	test_last_room()
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)

# ---------- 1. Zähler ----------

func test_counter(fake: FakeAndroid) -> void:
	# Android 16, Spiel-WLAN offen: Gastgeber ans Hotspot-Netz gebunden
	fake.s = hotspot_only_16()
	check(NetAddresses.bind_for("host") == "hotspot" and fake.calls == ["bind_network 303"], "Gastgeber ans Spiel-WLAN gebunden %s" % str(fake.calls))
	fake.calls.clear()
	NetAddresses.hold_unbound("a")
	check(fake.calls == ["unbind"] and NetAddresses.bound_to == "" and NetAddresses.holding() == 1 and NetAddresses.binding() == "hotspot",
		"erster Halt: Bindung gelöst %s" % str(fake.calls))
	NetAddresses.hold_unbound("b")
	check(fake.calls == ["unbind"] and NetAddresses.holding() == 2, "zweiter Halt: nichts Neues")
	NetAddresses.release_hold("a")
	check(fake.calls == ["unbind"] and NetAddresses.bound_to == "" and NetAddresses.holding() == 1, "ein Halt frei, einer hält noch")
	NetAddresses.release_hold("a")
	check(NetAddresses.holding() == 1, "doppelte Freigabe zählt nicht")
	NetAddresses.release_hold("b")
	check(fake.calls == ["unbind", "bind_network 303"] and NetAddresses.bound_to == "hotspot" and NetAddresses.holding() == 0,
		"letzter Halt frei → wieder ans Spiel-WLAN %s" % str(fake.calls))

	# Frist: ein vergessener Halt läuft nach HOLD_MS ab
	fake.calls.clear()
	NetAddresses.clock_ms = 1000
	NetAddresses.hold_unbound("c", 500)
	NetAddresses.hold_unbound("ohne_frist", 0)
	NetAddresses.clock_ms = 1499
	check(NetAddresses.holding() == 2 and NetAddresses.bound_to == "", "vor der Frist: hält")
	NetAddresses.clock_ms = 1500
	check(NetAddresses.holding() == 1 and NetAddresses.is_held("ohne_frist") and not NetAddresses.is_held("c"), "Frist abgelaufen: Halter c weg")
	NetAddresses.release_hold("ohne_frist")
	check(NetAddresses.bound_to == "hotspot" and fake.calls == ["unbind", "bind_network 303"], "danach wieder gebunden %s" % str(fake.calls))
	fake.calls.clear()
	NetAddresses.hold_unbound("d")      # Standardfrist HOLD_MS
	NetAddresses.clock_ms = 1500 + NetAddresses.HOLD_MS
	NetAddresses.expire_holds()
	check(NetAddresses.holding() == 0 and NetAddresses.bound_to == "hotspot" and fake.calls == ["unbind", "bind_network 303"],
		"Standardfrist %d ms → wieder gebunden %s" % [NetAddresses.HOLD_MS, str(fake.calls)])
	NetAddresses.clock_ms = -1

	# Bindungswunsch während des Halts: erst beim Freigeben; after_holds läuft danach
	fake.calls.clear()
	NetAddresses.hold_unbound("e")
	check(NetAddresses.bind_for("host") == "" and fake.calls == ["unbind"], "bind_for während des Halts bindet nicht %s" % str(fake.calls))
	var ran := []
	NetAddresses.after_holds(func(): ran.append(NetAddresses.bound_to))
	check(ran.is_empty(), "after_holds wartet")
	NetAddresses.release_hold("e")
	check(ran == ["hotspot"], "after_holds läuft nach dem Wiederbinden %s" % str(ran))
	var now := []
	NetAddresses.after_holds(func(): now.append(true))
	check(now == [true], "after_holds ohne Halt: sofort")
	NetAddresses.release("host")
	check(NetAddresses.bound_to == "" and fake.calls.back() == "unbind", "Gastgeber beendet → gelöst")

	# Updater wie bisher: ohne Bindung nichts zu tun, mit Bindung lösen und wiederherstellen
	fake.calls.clear()
	fake.s = home_wifi()
	NetAddresses.suspend_for_internet()
	NetAddresses.resume_after_internet()
	check(fake.calls.is_empty() and NetAddresses.holding() == 0, "Updater ohne Bindung: keine Aufrufe")
	check(NetAddresses.bind_for("join", "192.168.178.20") == "wifi", "Beitritt im WLAN gebunden")
	fake.calls.clear()
	NetAddresses.suspend_for_internet()
	NetAddresses.hold_unbound("vermittler")
	NetAddresses.resume_after_internet()
	check(fake.calls == ["unbind"] and NetAddresses.bound_to == "", "Updater fertig, Vermittler hält noch")
	NetAddresses.release_hold("vermittler")
	check(fake.calls == ["unbind", "bind_wifi"] and NetAddresses.bound_to == "wifi", "beide fertig → wieder ans WLAN %s" % str(fake.calls))
	# Zweck endet während des Halts: nichts wiederherstellen
	fake.calls.clear()
	NetAddresses.hold_unbound("f")
	NetAddresses.release("join")
	NetAddresses.release_hold("f")
	check(fake.calls == ["unbind"] and NetAddresses.bound_to == "", "Zweck während des Halts beendet → bleibt gelöst %s" % str(fake.calls))

# ---------- 2. Vermittler-Gastgeber und -Gast ----------

func test_sockets(fake: FakeAndroid) -> void:
	fake.s = hotspot_only_16()
	fake.calls.clear()
	check(NetAddresses.bind_for("host") == "hotspot", "Gastgeber ans Spiel-WLAN gebunden")
	var relay := NetRelayDouble.new()
	relay.auto_poll = false
	relay.web_zip_path = ""
	check(relay.start(PORT, PORT) == OK, "Nachbau lauscht auf %d" % PORT)
	var host := NetRelayHost.new()
	host.auto_poll = false
	fake.calls.clear()
	host.open(relay.base_url())
	check(NetAddresses.is_held(host.hold_id()) and NetAddresses.bound_to == "" and fake.calls == ["unbind"],
		"Raum öffnen: Bindung ausgesetzt %s" % str(fake.calls))
	var all := [relay, host]
	check(wait(all, func(): return host.state == "open"), "Raum offen (%s %s)" % [host.state, host.error])
	check(not NetAddresses.is_held(host.hold_id()) and NetAddresses.bound_to == "hotspot" and fake.calls == ["unbind", "bind_network 303"],
		"Socket offen → wieder ans Spiel-WLAN %s" % str(fake.calls))

	# Gast online: hält beim Verbinden, gibt bei „offen“ frei
	var guest := NetClient.new()
	guest.auto_poll = false
	guest.persist_tokens = false
	all.append(guest)
	fake.calls.clear()
	guest.connect_relay(relay.base_url(), host.room, "Mia")
	check(NetAddresses.is_held(guest.hold_id()) and NetAddresses.bound_to == "", "Gast verbindet: Bindung ausgesetzt")
	var guest_open := func() -> bool: return guest._ws != null and guest._ws.get_ready_state() == WebSocketPeer.STATE_OPEN
	check(wait(all, func(): return not NetAddresses.is_held(guest.hold_id()) and guest_open.call()), "Gast-Socket offen → frei")
	check(NetAddresses.bound_to == "hotspot" and NetAddresses.holding() == 0, "wieder gebunden %s" % str(fake.calls))

	# Neuverbinden des Gastgebers (Vermittler kurz weg): hält erneut, gibt wieder frei
	fake.calls.clear()
	host._ws.close()
	host._ws = null
	host._lost("Test")
	check(host.state == "away" and not NetAddresses.is_held(host.hold_id()) and NetAddresses.bound_to == "hotspot", "Vermittler weg: kein Halt beim Warten")
	host._retry_at = -1
	host._connect()
	check(NetAddresses.is_held(host.hold_id()) and NetAddresses.bound_to == "", "Neuverbinden: Bindung ausgesetzt")
	check(wait(all, func(): return host.state == "open" and NetAddresses.holding() == 0), "wieder offen, frei (%s)" % host.state)
	check(NetAddresses.bound_to == "hotspot", "nach dem Neuverbinden wieder ans Spiel-WLAN")
	guest.close()
	host.close()
	pump(all, 50)
	guest.free()
	host.free()
	relay.stop()
	relay.free()

	# Fehlerpfad: Vermittler nicht erreichbar (Port ohne Dienst) → frei, Bindung zurück
	var bad := NetRelayHost.new()
	bad.auto_poll = false
	bad.retry_ms = [30]
	bad.connect_timeout_ms = 400
	bad.open("http://127.0.0.1:1")
	check(NetAddresses.is_held(bad.hold_id()), "Fehlerpfad Gastgeber: zuerst ausgesetzt")
	check(wait([bad], func(): return bad.state == "failed"), "Vermittler nicht erreichbar → failed (%s)" % bad.state)
	check(NetAddresses.holding() == 0 and NetAddresses.bound_to == "hotspot", "Fehlerpfad Gastgeber: frei, wieder gebunden")
	bad.free()
	var lone := NetClient.new()
	lone.auto_poll = false
	lone.auto_reconnect = false
	lone.persist_tokens = false
	lone.connect_timeout_ms = 400
	lone.connect_relay("http://127.0.0.1:1", "KATZE-42", "Mia")
	check(NetAddresses.is_held(lone.hold_id()), "Fehlerpfad Gast: zuerst ausgesetzt")
	check(wait([lone], func(): return lone.state == "closed"), "Gast: Vermittler nicht erreichbar → closed (%s)" % lone.state)
	check(NetAddresses.holding() == 0 and NetAddresses.bound_to == "hotspot", "Fehlerpfad Gast: frei, wieder gebunden")
	lone.free()
	# Freigeben des Knotens mitten im Verbinden gibt den Halt ebenfalls frei
	var gone := NetRelayHost.new()
	gone.open("http://127.0.0.1:1")
	var gid := gone.hold_id()
	gone.free()
	check(not NetAddresses.is_held(gid) and NetAddresses.bound_to == "hotspot", "Knoten freigegeben → Halt frei")
	NetAddresses.release("host")

# ---------- 3. Letzter Raumcode ----------

func test_last_room() -> void:
	var path := "user://test_net_hold_einstellungen.json"
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	var st := AppSettings.new(path)
	check(st.get_value("letzter_raum", {}) == {}, "ab Werk kein Raum")
	check(st.set_value("letzter_raum", {"room": "katze 42", "relay": NetProtocol.RELAY_DEFAULT}), "Raum gespeichert")
	check(st.get_value("letzter_raum") == {"room": "KATZE-42", "relay": ""}, "Code bereinigt, Standard-Vermittler nicht gespeichert: %s" % str(st.get_value("letzter_raum")))
	check(st.set_value("letzter_raum", {"room": "MOND-10", "relay": "eigen.example.org/"}), "eigener Vermittler")
	var again := AppSettings.new(path)
	check(again.get_value("letzter_raum") == {"room": "MOND-10", "relay": "https://eigen.example.org"}, "nach Neustart: %s" % str(again.get_value("letzter_raum")))
	check(AppSettings.sanitize("letzter_raum", {"room": "KA-1"}) == null and AppSettings.sanitize("letzter_raum", "MOND-10") == null
		and AppSettings.sanitize("letzter_raum", {"room": 5}) == null, "ungültige Räume abgewiesen")
	check(AppSettings.sanitize("letzter_raum", {"room": "MOND-10", "relay": "a b"}) == {"room": "MOND-10", "relay": ""}
		and AppSettings.sanitize("letzter_raum", {"room": "MOND-10", "relay": 7}) == {"room": "MOND-10", "relay": ""}, "ungültiger Vermittler → Standard")
	# Datei von Hand verdorben: Standard statt Absturz
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{\"version\":1,\"letzter_raum\":{\"room\":\"???\"}}")
	f.close()
	check(AppSettings.new(path).get_value("letzter_raum", {}) == {}, "verdorbener Eintrag → kein Raum")
	again.reset("letzter_raum")
	check(AppSettings.new(path).get_value("letzter_raum", {}) == {}, "gelöscht bleibt gelöscht")
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func pump(nodes: Array, ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		for n in nodes:
			if is_instance_valid(n):
				n.poll()
		OS.delay_msec(2)

func wait(nodes: Array, cond: Callable, ms := 4000) -> bool:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		pump(nodes, 4)
		if cond.call():
			return true
	return cond.call()
