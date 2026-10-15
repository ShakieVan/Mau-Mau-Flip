extends "res://tests/handover_wlan_ui_kit.gd"
# Mau-Mau Flip (Beta 1.6.2, Befunde des Gerätetests docs/geraetetest/1.6.2/BERICHT.md), ohne Server und ohne Android:
#  F1  Offenes Spiel-WLAN neben dem WLAN (Android ≤ 15: Bindung ""): HostTable erkennt es über den GameWifiWatch (setzt
#      hotspot_check, ohne dass ein Test es einspritzt) → wlan.ap, ap_seat, Übergabe „qr“ mit Warnzeile; Spiel-WLAN zu → wieder „lan“.
#      Watch verlässt den Baum → hotspot_check gelöst. Am PC ohne Watch: own_game_wifi_open() falsch.
#  F1  lan_ok/lan_reach: Spiel-WLAN des Gastgebers weg, Gerät zurück im Heim-WLAN /16, das die alte Adresse zufällig umfasst →
#      kein „selbes Netz“ mehr (vorher wahr: normale WLAN-Übernahme ohne eigenes Spiel-WLAN); eigene Spiel-WLAN-Adresse noch da → wahr;
#      ohne Spiel-WLAN bzw. Spiel-WLAN eines Mitspielers wie bisher. Auch über HostSwitch.lan_ok() mit NetAddresses.override_interfaces.
#  F2  NetAddresses.bind_for("join"): Adresse in Spiel-WLAN und WLAN zugleich (S10: swlan0 192.168.178.254/24, Heim 192.168.178.9/16)
#      → abwechselnd WLAN und ungebunden (vorher immer ungebunden: S21 im Heim-WLAN unerreichbar); nur im Hotspot → ungebunden.
#  F3  NetClient bindet bei jedem Neuversuch neu: tote Bindung (verlorenes Spiel-WLAN) → bind_wifi beim nächsten Versuch.
#  B1  HostTable nach ≥ wake_pause_ms im Hintergrund: Wächter fragt sofort (scan_soon), Aktionen/Bots halten an („Einen Moment –
#      gleich geht es weiter.“); ein Rivale mit höherer gen gewinnt schon beim ersten Scan (sonst erst beim zweiten); kurze Pause nichts.
#  B2  WLAN-Gast: Gastgeber laut Stand „kurz in einer anderen App“ → „Gastgeber kurz weg – warte …“.
#   godot_run.ps1 -Script res://tests/test_wlan_fixes.gd -Headless

const CleanExit := preload("res://tests/clean_exit.gd")
const ANDROID_PATH := "res://scripts/app/net_android.gd"

var ok := 0
var failed := false
var wall := 0


func _initialize() -> void:
	call_deferred("run")


func check(cond: bool, what: String) -> void:
	if cond:
		ok += 1
	else:
		failed = true
		print("FAIL: " + what)


func run() -> void:
	f1_watch()
	f1_lan_reach()
	b1_wake()
	b2_hint()
	f2_f3_binding()
	if failed:
		print("FAIL: test_wlan_fixes")
	else:
		print("RESULT: %d ok" % ok)
	await CleanExit.finish(self, 1 if failed else 0)


static func _has_note(list: Array, text: String) -> bool:
	return list.any(func(x): return I18n.render(x if x is Array else [x]) == text)


# --- F1: Spiel-WLAN über den GameWifiWatch ---
func f1_watch() -> void:
	var ht := make_host(false)
	check(not HostTable.own_game_wifi_open(), "F1: am PC ohne Watch kein eigenes Spiel-WLAN")
	check(not ht.hotspot_check.is_valid(), "F1: Ausgangslage ohne eingespritzte Prüfung")
	var st := {"status": "off"}
	var addr := [""]
	var w := GameWifiWatch.new()
	w.manual = true
	w.available_source = func() -> bool: return true
	w.state_source = func() -> Dictionary: return st.duplicate()
	w.start_source = func() -> String: return ""
	w.stop_source = func() -> bool: return true
	w.address_source = func() -> String: return str(addr[0])
	w.addrs_source = func() -> Array: return ["192.168.178.9"] + ([str(addr[0])] if str(addr[0]) != "" else [])
	w.binding_source = func() -> String: return ""          # Android 15, Spiel-WLAN und WLAN: ungebunden (host_plan)
	w.qr_active = func() -> bool: return false
	w.qr_state = func() -> Dictionary: return {}
	w.qr_release = func() -> void: pass
	w.old_net = func() -> bool: return false
	w.now_ms = func() -> int: return wall
	w.setup(ht)
	check(ht.hotspot_check.is_valid(), "F1: Watch setzt hotspot_check am HostTable")
	root.add_child(w)
	w.poll()
	check(not bool(ht.game_wifi().ap) and ht.handover_how(1) == "lan", "F1: ohne Spiel-WLAN how lan (%s)" % ht.handover_how(1))
	# Spiel-WLAN geht auf (Bindung bleibt "")
	st["status"] = "on"
	addr[0] = "192.168.178.254"
	wall += GameWifiWatch.POLL_MS
	w.poll()
	var gw := ht.game_wifi()
	check(bool(gw.ap) and int(gw.ap_seat) == ht.host_seat, "F1: offenes Spiel-WLAN → wlan.ap, ap_seat = Gastgeber (%s)" % [gw])
	check(ht.handover_how(1) == "qr", "F1: geplante Übergabe an Lena how qr (%s)" % ht.handover_how(1))
	check(_has_note(ht.handover_warnings(1), "Alle müssen danach einen neuen QR-Code scannen."),
		"F1: Warnzeile „Alle müssen danach …“ (%s)" % [ht.handover_warnings(1)])
	var snap: Dictionary = ht._snapshot()
	check(bool(snap.wlan.ap) and int(snap.wlan.ap_seat) == ht.host_seat, "F1: Sicherung trägt wlan.ap (%s)" % [snap.wlan])
	check(ht.hosts_message().get("ap") == true, "F1: hosts.ap für Browser-Gäste")
	# Spiel-WLAN zu → wieder lan
	st["status"] = "stopped"
	addr[0] = ""
	wall += GameWifiWatch.POLL_MS
	w.poll()
	check(not bool(ht.game_wifi().ap) and ht.handover_how(1) == "lan", "F1: Spiel-WLAN zu → ap aus, how lan (%s)" % [ht.game_wifi()])
	# Eingespritzte Prüfung bleibt; Watch weg → Prüfung gelöst
	root.remove_child(w)
	check(not ht.hotspot_check.is_valid(), "F1: Watch verlässt den Baum → hotspot_check gelöst")
	var own := func() -> bool: return true
	ht.hotspot_check = own
	var w2 := GameWifiWatch.new()
	w2.manual = true
	w2.setup(ht)
	check(ht.hotspot_check == own, "F1: eingespritzte Prüfung bleibt")
	w2.free()
	w.free()
	ht.free()


# --- F1: „im Netz des alten Gastgebers“ bei Spiel-WLAN ---
func f1_lan_reach() -> void:
	var home16 := [{"name": "wlan0", "address": "192.168.178.9", "prefix": 16}]
	var d := {"host_seat": 0, "seats": [{"name": "S21"}, {"name": "Kim", "addr": "192.168.35.17"}],
		"wlan": {"ap": true, "ap_seat": 0, "addrs": ["192.168.35.250"], "port": 24690}}
	var targets := ["192.168.35.250"]
	check(NetProtocol.same_net("192.168.178.9", "192.168.35.250", 16), "F1: Ausgangslage – /16 umfasst die alte Spiel-WLAN-Adresse")
	check(not HostSwitch.lan_reach(d, targets, 1, home16), "F1: Spiel-WLAN weg, zurück im Heim-WLAN /16 → nicht im Netz des Gastgebers")
	var still := home16 + [{"name": "wlan0", "address": "192.168.35.17", "prefix": 24}]
	check(HostSwitch.lan_reach(d, targets, 1, still), "F1: eigene Spiel-WLAN-Adresse noch da → im Netz")
	var plain := d.duplicate(true)
	plain.wlan.ap = false
	check(HostSwitch.lan_reach(plain, targets, 1, home16), "F1: ohne Spiel-WLAN wie bisher über das Präfix")
	var foreign := d.duplicate(true)
	foreign.wlan.ap_seat = 1
	check(HostSwitch.lan_reach(foreign, targets, 1, home16), "F1: Spiel-WLAN eines Mitspielers – wie bisher")
	check(HostSwitch.lan_reach(d, targets, -1, home16), "F1: eigener Platz unbekannt – wie bisher")
	check(not HostSwitch.lan_reach(d, targets, 1, [{"name": "wlan0", "address": "10.0.0.5", "prefix": 24}]), "F1: fremdes Netz – nicht im Netz")
	# über HostSwitch.lan_ok() mit einer Gast-Sicherung und eingespritzten Schnittstellen
	var now := int(Time.get_unix_time_from_system())
	var b := guest_backup(game_dict(), 0, now)
	(b.seats[1] as Dictionary)["addr"] = "192.168.49.23"
	var ct := guest_table(b)
	ct.address = "192.168.49.1"
	var sw := HostSwitch.new()
	sw.auto_process = false
	sw.source = ct
	NetAddresses.override_interfaces = [{"name": "wlan0", "address": "192.168.178.9", "prefix": 16}]
	check(NetProtocol.same_net("192.168.178.9", "192.168.49.1", 16) and not sw.lan_ok(), "F1: lan_ok() ohne die eigene Spiel-WLAN-Adresse falsch")
	NetAddresses.override_interfaces = [{"name": "wlan0", "address": "192.168.49.23", "prefix": 24}]
	check(sw.lan_ok(), "F1: lan_ok() mit der eigenen Spiel-WLAN-Adresse wahr")
	NetAddresses.override_interfaces = null
	sw.source = null
	sw.free()
	ct.free()


# --- B1: Rückkehr des Gastgebers aus dem Hintergrund ---
func _waking_host() -> HostTable:
	var ht := make_host(false)
	ht.ms_clock = func() -> int: return wall
	var disc := NetDiscovery.new()
	disc.auto_poll = false
	ht.session.discovery = disc
	ht.session.add_child(disc)
	return ht


func _rival() -> Dictionary:
	return {"gid": GID, "gen": 2, "epoch": "ffff0000", "conn": 5, "sid": "rivale", "name": "Kim", "address": "192.168.178.9",
		"addresses": ["192.168.178.9"], "port": 24690}


func b1_wake() -> void:
	wall = 1000
	var ht := _waking_host()
	var notes: Array = []
	ht.notice.connect(func(t: String) -> void: notes.append(t))
	check(not ht.wake_check(5000) and not ht.is_waking(), "B1: kurze Pause – keine Prüfung")
	ht._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	wall += NetProtocol.WAKE_PAUSE_MS + 1000
	ht.session.discovery.set("_next_scan_ms", 999999)
	ht._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(ht.is_waking(), "B1: nach langer Pause läuft die Wächter-Prüfung")
	check(int(ht.session.discovery.get("_next_scan_ms")) == 0, "B1: Wächter fragt sofort (scan_soon)")
	check(ht._hold_reason() == "Einen Moment – gleich geht es weiter." and ht._bots_paused(), "B1: Aktionen und Bots halten an")
	ht.act({"a": "draw"})
	check(notes.has("Einen Moment – gleich geht es weiter."), "B1: eigene Aktion wartet (%s)" % [notes])
	ht._on_rival(_rival())
	check(not ht.step_target.is_empty() and str(ht.step_target.get("how", "")) == "lan" and ht.is_frozen(),
		"B1: Rivale mit höherer gen gewinnt beim ersten Scan → abtreten (%s)" % [ht.step_target])
	ht.free()
	# Gegenprobe ohne Rückkehr: erst der zweite Scan entscheidet
	var h2 := _waking_host()
	h2._on_rival(_rival())
	check(h2.step_target.is_empty() and not h2.is_frozen(), "B1: ohne Rückkehr entscheidet ein Scan noch nicht")
	h2._on_rival(_rival())
	check(not h2.step_target.is_empty(), "B1: … der zweite schon")
	h2.free()
	# Prüfung läuft ab
	var h3 := _waking_host()
	check(h3.wake_check(NetProtocol.WAKE_PAUSE_MS), "B1: Prüfung beginnt")
	wall += NetProtocol.WAKE_CHECK_MS
	h3._poll_wake(wall)
	check(not h3.is_waking() and h3._hold_reason() == "" and not h3._bots_paused(), "B1: nach WAKE_CHECK_MS geht es weiter")
	h3.free()


# --- B2: Hinweis beim Neuverbinden im WLAN ---
func b2_hint() -> void:
	var now := int(Time.get_unix_time_from_system())
	var ct := guest_table(guest_backup(game_dict(), 0, now))
	var nc := NetClient.new()
	nc.auto_poll = false
	ct.client = nc
	ct._view = {"players": [{"name": "Hanna", "host": true, "away": true}, {"name": "Lena", "host": false}]}
	check(ct.connection_hint() == "Gastgeber kurz weg – warte …", "B2: Gastgeber in anderer App → kurz weg (%s)" % ct.connection_hint())
	ct._view = {"players": [{"name": "Hanna", "host": true, "away": false}]}
	check(ct.connection_hint() == "Verbindung zum Gastgeber unterbrochen – warte …", "B2: sonst unterbrochen (%s)" % ct.connection_hint())
	ct.client = null
	nc.free()
	ct.free()


# --- F2/F3: Bindung beim Beitritt ---
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
	func in_wifi(st: Dictionary, address: String) -> bool:
		return real.in_wifi(st, address)
	func bound_to_wifi(st: Dictionary) -> bool:
		return real.bound_to_wifi(st)
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
		return true


# S10 (Android 12) nach dem Öffnen des eigenen Spiel-WLANs: Heim-WLAN /16, Spiel-WLAN swlan0 im selben Bereich (Gerätetest b08).
static func overlap_state() -> Dictionary:
	return {"android": true, "bound": null, "networks": [
		{"transport": "wifi", "iface": "wlan0", "addresses": ["192.168.178.9/16"], "gateway": "192.168.178.1", "handle": "101",
			"default": true, "internet": true}],
		"interfaces": [{"name": "wlan0", "address": "192.168.178.9", "prefix": 16},
			{"name": "swlan0", "address": "192.168.178.254", "prefix": 24}]}


func f2_f3_binding() -> void:
	if not ResourceLoader.exists(ANDROID_PATH):
		return
	var fake := FakeAndroid.new()
	fake.real = load(ANDROID_PATH)
	NetAddresses.set_helper(fake)
	fake.s = overlap_state()
	check(fake.real.in_hotspot(fake.s, "192.168.178.8") and fake.real.in_wifi(fake.s, "192.168.178.8"),
		"F2: 192.168.178.8 liegt in Spiel-WLAN und Heim-WLAN")
	check(fake.real.join_binding(fake.s, "192.168.178.8") == "", "F2: Ausgangslage – Regel allein: ungebunden (Kernel nimmt swlan0)")
	var first := NetAddresses.bind_for("join", "192.168.178.8")
	check(first == "wifi" and fake.calls == ["bind_wifi"], "F2: erster Versuch ans WLAN (%s, %s)" % [first, fake.calls])
	fake.s.bound = {"transport": "wifi", "handle": "101"}
	var second := NetAddresses.bind_for("join", "192.168.178.8")
	check(second == "" and fake.calls.back() == "unbind", "F2: zweiter Versuch ungebunden (Spiel-WLAN) (%s, %s)" % [second, fake.calls])
	fake.s.bound = null
	var third := NetAddresses.bind_for("join", "192.168.178.8")
	check(third == "wifi", "F2: dritter Versuch wieder ans WLAN (%s)" % third)
	NetAddresses.release("join")
	# nur im eigenen Hotspot (nicht im WLAN): wie bisher ungebunden, ohne Wechsel
	fake.calls.clear()
	var hs := overlap_state()
	(hs.interfaces as Array)[1] = {"name": "swlan0", "address": "10.20.30.1", "prefix": 24}
	fake.s = hs
	check(NetAddresses.bind_for("join", "10.20.30.7") == "" and NetAddresses.bind_for("join", "10.20.30.7") == "", "F2: nur im Hotspot → ungebunden")
	NetAddresses.release("join")
	# F3: Prozess an ein verlorenes Netz gebunden (Spiel-WLAN weg) – der Neuversuch bindet neu
	fake.calls.clear()
	fake.s = {"android": true, "bound": {"transport": "?", "handle": "555"}, "networks": [
		{"transport": "wifi", "iface": "wlan0", "addresses": ["192.168.178.9/16"], "gateway": "192.168.178.1", "handle": "101",
			"default": true, "internet": true}],
		"interfaces": [{"name": "wlan0", "address": "192.168.178.9", "prefix": 16}]}
	var nc := NetClient.new()
	nc.auto_poll = false
	nc.persist_tokens = false
	nc.connect_to("127.0.0.1", 24989, "Kim")
	var after_join := fake.calls.count("bind_wifi")
	nc.reconnect_now()
	check(after_join == 1 and fake.calls.count("bind_wifi") == 2, "F3: Neuversuch bindet neu (%s)" % [fake.calls])
	nc.close()
	nc.free()
	NetAddresses.release("join")
	NetAddresses.set_helper(null)
