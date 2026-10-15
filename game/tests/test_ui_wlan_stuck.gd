extends "res://tests/handover_wlan_ui_kit.gd"
# Mau-Mau Flip (Beta 1.6.2, Gerätetest docs/geraetetest/1.6.2/BERICHT.md, F2 und B1): Oberfläche nur mit Doubles (ohne Server).
#   L  App-Gast hängt bei „Der Tisch wird geladen …“ (alter Gastgeber nach dem Abtreten erreicht den neuen nicht): Der Verbindungs-
#      streifen steht sofort (das Signal „connecting“ kam vor dem Tisch); nach load_stuck_ms „Der Gastgeber antwortet nicht.“ mit
#      „Die Partie bleibt gemerkt …“ und „Zum Hauptmenü“ → Tisch ohne bye zu, Sicherung bleibt, Hauptmenü. Kommt der Stand doch, geht
#      der Streifen; die Lage des Wächters geht vor. Ohne Sicherung führt der Knopf wie „Zum Menü“ hinaus.
#   R  Gastgeber nach der Rückkehr aus dem Hintergrund (Wächter-Prüfung): Streifen „Einen Moment – gleich geht es weiter.“
#   godot_run.ps1 -Script res://tests/test_ui_wlan_stuck.gd -Headless

const CleanExit := preload("res://tests/clean_exit.gd")

var ok := 0
var failed := false
var nav: RecNav


func _initialize() -> void:
	call_deferred("run")


func check(cond: bool, what: String) -> void:
	if cond:
		ok += 1
	else:
		failed = true
		print("FAIL: " + what)


func frames(n := 2) -> void:
	for i in n:
		await process_frame


func run() -> void:
	GameStarter.test_speed = 0.0
	root.size = Vector2i(1600, 720)
	nav = RecNav.new()
	nav.autostart = false
	root.add_child(nav)
	nav.push(AppScreen.new(), false)
	await frames(3)
	await loading_part()
	await waking_part()
	TableScreen.load_stuck_ms = 20000
	if failed:
		print("FAIL: test_ui_wlan_stuck")
	else:
		print("RESULT: %d ok" % ok)
	await CleanExit.finish(self, 1 if failed else 0)


func _stuck_table(with_backup := true) -> Array:
	var now := int(Time.get_unix_time_from_system())
	var ct := guest_table(guest_backup(game_dict(), 0, now) if with_backup else {})
	var nc := NetClient.new()
	nc.auto_poll = false
	nc.state = "connecting"              # verbindet immer wieder neu, der neue Gastgeber antwortet nie
	ct.client = nc
	var ts := TableScreen.create(ct)
	nav.push(ts, false)
	await frames(3)
	if ts._switch != null:
		ts._switch.auto_process = false
	return [ts, ct, nc]


func loading_part() -> void:
	TableScreen.load_stuck_ms = 300
	var parts: Array = await _stuck_table()
	var ts: TableScreen = parts[0]
	var ct: ClientTable = parts[1]
	check(ts._loading.visible, "L: Ladehinweis steht")
	check(ts._conn.visible and ts._conn_label.text == "Verbindung zum Gastgeber unterbrochen – warte …",
		"L: Verbindungsstreifen sofort (%s)" % ts._conn_label.text)
	check(not ts._conn_later.visible, "L: noch kein „Zum Hauptmenü“")
	await create_timer(0.4).timeout
	await frames(2)
	check(ts._conn.visible and ts._conn_label.text == "Der Gastgeber antwortet nicht.", "L: nach der Frist „antwortet nicht“ (%s)" % ts._conn_label.text)
	check(ts._conn_later.visible and ts._conn_sub.visible
		and ts._conn_sub.text == "Die Partie bleibt gemerkt – im Hauptmenü kannst du sie fortsetzen.", "L: „Zum Hauptmenü“ mit Satz")
	check(not ts._conn_menu.visible and not ts._conn_take.visible, "L: keine anderen Knöpfe")
	# Lage des Wächters geht vor
	var sw := FakeSwitch.new()
	sw.auto_process = false
	sw.source = ct
	var real_sw := ts._switch
	ts._switch = sw
	sw.state = "missing"
	await frames(2)
	check(ts._conn_label.text != "Der Gastgeber antwortet nicht." and not ts._conn_later.visible, "L: Wächter-Streifen geht vor (%s)" % ts._conn_label.text)
	sw.state = "watch"
	await frames(3)
	check(ts._conn_label.text == "Der Gastgeber antwortet nicht." and ts._conn_later.visible, "L: danach wieder „antwortet nicht“ (%s)" % ts._conn_label.text)
	ts._switch = real_sw
	sw.source = null
	sw.free()
	# Stand kommt doch → Streifen weg bzw. wieder Verbindungsstand
	ts._loading.visible = false
	await frames(2)
	check(not ts._conn_later.visible and ts._conn_label.text == "Verbindung zum Gastgeber unterbrochen – warte …",
		"L: Stand da → „Zum Hauptmenü“ weg (%s)" % ts._conn_label.text)
	ts._loading.visible = true
	await frames(2)
	check(ts._conn_later.visible, "L: wieder ohne Stand → Knopf")
	# Zum Hauptmenü: ohne bye, Sicherung bleibt
	nav.record = true
	ts._conn_later.pressed.emit()
	check(ts.leaving and ct._leaving and not ct.backup.is_empty() and nav.log.size() == 1 and nav.log[0] == ["home"],
		"L: „Zum Hauptmenü“ → Tisch zu ohne Verlassen, Hauptmenü (%s)" % [nav.log])
	nav.drop_log()
	nav.record = false
	nav.pop(false)
	await frames(2)
	# ohne Sicherung: wie „Zum Menü“ (leave)
	var p2: Array = await _stuck_table(false)
	var ts2: TableScreen = p2[0]
	await create_timer(0.4).timeout
	await frames(2)
	check(ts2._conn_later.visible and not ts2._conn_sub.visible, "L: ohne Sicherung kein Satz „bleibt gemerkt“")
	nav.record = true
	ts2.pause_to_menu()
	check(ts2.leaving and nav.log.size() == 1 and nav.log[0] == ["home"], "L: ohne Sicherung verlassen (%s)" % [nav.log])
	nav.drop_log()
	nav.record = false
	nav.pop(false)
	await frames(2)


func waking_part() -> void:
	TableScreen.wifi_watch_factory = func(h: HostTable) -> Node:
		var w := FakeWatch.new()
		w.host = h
		return w
	var ht := make_host(false)
	var clock := [1000]
	ht.ms_clock = func() -> int: return int(clock[0])
	var disc := NetDiscovery.new()
	disc.auto_poll = false
	ht.session.discovery = disc
	ht.session.add_child(disc)
	var ts := TableScreen.create(ht)
	nav.push(ts, false)
	await frames(3)
	if ts._switch != null:
		ts._switch.auto_process = false
	check(ht.wake_check(NetProtocol.WAKE_PAUSE_MS), "R: Wächter-Prüfung beginnt")
	await frames(2)
	check(ts._conn.visible and ts._conn_label.text == "Einen Moment – gleich geht es weiter.", "R: Streifen „Einen Moment …“ (%s)" % ts._conn_label.text)
	clock[0] += NetProtocol.WAKE_CHECK_MS
	await frames(2)
	check(not ts._conn.visible, "R: danach kein Streifen")
	nav.pop(false)
	await frames(2)
	TableScreen.wifi_watch_factory = Callable()
