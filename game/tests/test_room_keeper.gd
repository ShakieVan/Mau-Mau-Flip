extends SceneTree

# Mau-Mau Flip (Beta 1.6.16, Raum behalten, docs/module/raum_behalten.md): Gastgeber und Gäste über den Vermittler-Nachbau (NetRelayDouble).
#  - Einheiten: RoomKeeper.stale_hello, Datei-Prüfung (load_saved), AppSettings.clean_return, GuestReturn (merken, Unterzeile, vergessen).
#  - Ablauf: Partie mit zwei App-Gästen (mit Sicherung); Ben ist beim Verlassen weg (suspend). Der Gastgeber verlässt den Tisch → Anna
#    bekommt „bye“, der Raum bleibt beim Vermittler (Raumhalter). Ben kommt mit seiner Sicherung wieder → „bye“ (keine Übernahme möglich,
#    Sicherung gelöscht). Neuer App-Gast und Browser-Gast → 4503 (warten). Neue Lobby → derselbe Raumcode (Anschluss übernommen),
#    die Wartenden landen von selbst darin. Lobby verlassen und discard() → Raum beim Vermittler weg.
#  - Datei: App „beendet“ (Halter weg, Raum in der Frist) → neue Lobby holt den Raum per open_existing zurück; Raum abgelaufen →
#    automatisch neuer Raum (neuer Code).
#  - Höchstdauer: Nach KEEP_S endet der gehaltene Raum.
#   tools/godot_run.ps1 -Script res://tests/test_room_keeper.gd -Headless -Timeout 120

const RELAY_PORT := 24931
const HOST_PORT := 24932
const KEEP_FILE := "user://eigener_raum_test.json"
const SETTINGS_FILE := "user://einstellungen_raum_test.json"
const BACKUP := "user://raum_test_%s.json"

var failures := 0
var checks := 0
var relay: NetRelayDouble
var url := ""
var hosts: Array = []
var tables: Array = []
var webs: Array = []
var fake_now := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)


func _initialize() -> void:
	relay = NetRelayDouble.new()
	relay.auto_poll = false
	check(relay.start(RELAY_PORT, RELAY_PORT) == OK, "Vermittler-Nachbau auf %d" % RELAY_PORT)
	url = "http://127.0.0.1:%d" % RELAY_PORT
	RoomKeeper.enabled = true
	GuestReturn.enabled = true
	RoomKeeper.attach = false
	RoomKeeper.save_path = KEEP_FILE
	RoomKeeper._delete_saved()
	var app := root.get_node_or_null("App")
	var old_settings: Variant = app.get("settings") if app != null else null
	if app != null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
		app.set("settings", AppSettings.new(SETTINGS_FILE))
	run_units()
	run_flow()
	run_file()
	run_expire()
	# aufräumen
	RoomKeeper.discard()
	RoomKeeper.enabled = false
	GuestReturn.enabled = false
	RoomKeeper.clock = Callable()
	for c in tables:
		c.leave()
		c.free()
	for w in webs:
		(w as NetClient).close()
		(w as NetClient).free()
	for h in hosts:
		if is_instance_valid(h):
			h.leave()
			h.free()
	RoomKeeper.discard()
	relay.stop()
	relay.free()
	if app != null:
		app.set("settings", old_settings)
	for p in [SETTINGS_FILE, KEEP_FILE, BACKUP % "anna", BACKUP % "ben", BACKUP % "carl"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("RESULT: %d ok" % checks if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)


# ---------- Einheiten ----------

func run_units() -> void:
	check(RoomKeeper.stale_hello({"t": "hello", "bk_gid": "abc1"}, "abc1", []), "stale: Sicherung derselben Partie (bk_gid)")
	check(RoomKeeper.stale_hello({"t": "hello", "bk_token": "t1"}, "", ["t1", "t2"]), "stale: Platz-Token aus der Sicherung")
	check(not RoomKeeper.stale_hello({"t": "hello", "token": "t1"}, "abc1", ["t1"]), "nicht stale: nur das Token (ohne Sicherung)")
	check(not RoomKeeper.stale_hello({"t": "hello", "bk": [0, "", 0]}, "abc1", ["t1"]), "nicht stale: App ohne Sicherung")
	check(not RoomKeeper.stale_hello({"t": "hello", "bk_gid": "ffff"}, "abc1", []), "nicht stale: Sicherung einer anderen Partie")
	check(not RoomKeeper.stale_hello({"t": "hello", "bk_gid": ""}, "", []), "nicht stale: Lobby ohne Partie")
	# Datei
	var now := RoomKeeper.now_unix()
	var good := {"relay": url, "room": "KATZE-42", "token": "abc", "max_c": 3, "created_unix": now - 3600, "seen_unix": now - 30}
	_write_keep(good)
	check(RoomKeeper.load_saved().get("room", "") == "KATZE-42", "Datei: gültig")
	check(int(RoomKeeper.load_saved().get("max_c", -1)) == 3, "Datei: max_c")
	_write_keep(_with(good, "seen_unix", now - RoomKeeper.REUSE_GRACE_S - 5))
	check(RoomKeeper.load_saved().is_empty(), "Datei: Lebenszeichen zu alt (Vermittler hat den Raum gelöscht)")
	_write_keep(_with(good, "created_unix", now - RoomKeeper.LIFE_S + RoomKeeper.MIN_LIFE_S - 60))
	check(RoomKeeper.load_saved().is_empty(), "Datei: zu wenig Restlaufzeit")
	_write_keep(_with(good, "room", "XX"))
	check(RoomKeeper.load_saved().is_empty(), "Datei: kaputter Raumcode")
	_write_keep(_with(good, "token", ""))
	check(RoomKeeper.load_saved().is_empty(), "Datei: ohne Token")
	_write_keep(good)
	check(RoomKeeper.reusable(url).get("live", true) == false, "reusable: aus der Datei (ohne Halter)")
	check(RoomKeeper.reusable("http://127.0.0.1:1").is_empty(), "reusable: anderer Vermittler")
	RoomKeeper._delete_saved()
	check(RoomKeeper.reusable(url).is_empty(), "reusable: nichts gemerkt")
	# AppSettings.clean_return
	check(AppSettings.clean_return({"room": "katze 42", "relay": url, "host": "Lena", "t": 5}) == {"room": "KATZE-42", "relay": url, "host": "Lena", "t": 5},
		"clean_return: Code vereinheitlicht")
	check(AppSettings.clean_return({"room": "KATZE-42", "relay": "", "t": 5}) == null, "clean_return: ohne Vermittler ungültig")
	check(AppSettings.clean_return({"room": "KATZE-42", "relay": url}) == null, "clean_return: ohne Zeit ungültig")
	check(AppSettings.clean_return({"room": "KATZE-42", "relay": url, "t": 5}).get("host") == "", "clean_return: ohne Name")


# ---------- Ablauf ----------

func run_flow() -> void:
	var host := make_host()
	check(host.open("Gastgeberin", HOST_PORT, HOST_PORT) == OK, "Gastgeber im WLAN")
	host.open_online(url)
	check(wait_until(func(): return host.session.online_state() == "open"), "Online-Raum offen")
	check(not host.session.online_kept, "erster Raum: neu (nicht gemerkt)")
	var code := str(host.session.online_info().get("room", ""))
	var link := str(host.session.online_info().get("link", ""))
	var anna := new_client("anna", link)
	var ben := new_client("ben", link)
	check(wait_until(func(): return anna.connection_state() == "open" and ben.connection_state() == "open" and host.session.players.size() == 3),
		"zwei App-Gäste angenommen")
	host.set_rules(RuleConfig.preset("offiziell"))
	check(host.start(4711), "Start")
	check(wait_until(func(): return not anna.backup.is_empty() and not ben.backup.is_empty()), "beide Gäste halten eine Sicherung")
	# GuestReturn mit einem echten Online-Gast
	GuestReturn.remember(anna, 1000)
	var d := GuestReturn.current(1000 + 120)
	check(d.get("room", "") == code and d.get("host", "") == "Gastgeberin", "GuestReturn: Raum und Gastgeber gemerkt (%s)" % str(d))
	check(GuestReturn.subline(d, 1000 + 125) == "%s · bei Gastgeberin · vor 3 min" % code, "GuestReturn: Unterzeile (%s)" % GuestReturn.subline(d, 1000 + 125))
	check(GuestReturn.current(1000 + GuestReturn.MAX_AGE_S + 1).is_empty(), "GuestReturn: nach MAX_AGE_S nicht mehr angeboten")
	GuestReturn.forget()
	check(GuestReturn.current(1000 + 120).is_empty(), "GuestReturn: vergessen")
	# Ben ist gerade weg (Socket ohne bye zu, Sicherung bleibt)
	ben.suspend()
	check(wait_until(func(): return not bool(host.game.connected[host.session.seat_of(ben.my_id)])), "Ben getrennt")
	# Gastgeber verlässt den Tisch
	var kept_text := host.keepable_room()
	check(kept_text == code, "keepable_room: %s" % kept_text)
	host.leave()
	var k := RoomKeeper.current
	check(k != null and k.relay != null and k.relay.room == code, "Raumhalter hält den Raum %s" % code)
	check(k != null and k.gid != "" and k.tokens.size() >= 3, "Raumhalter kennt Partie und Platz-Token (%d)" % (k.tokens.size() if k != null else -1))
	check(k != null and k.relay.needs_check.get_connections().is_empty() and k.relay.state_changed.get_connections().size() == 1
		and k.relay.ws_message.get_connections().size() == 1, "Anschluss: keine Verbindungen der alten Sitzung mehr")
	check(FileAccess.file_exists(KEEP_FILE) and RoomKeeper.load_saved().get("room", "") == code, "Datei mit dem Raum geschrieben")
	check(wait_until(func(): return anna.connection_state() == "closed"), "Anna: Verbindung beendet")
	check(anna.client != null and anna.client.bye_id == "Der Gastgeber hat das Spiel beendet.", "Anna bekam bye")
	check(anna.backup.is_empty(), "Annas Sicherung gelöscht")
	pump(200)
	check(relay.core.rooms.has(code) and int(relay.core.rooms[code].host) >= 0, "Raum beim Vermittler noch offen, Gastgeber verbunden")
	# Ben kommt mit seiner Sicherung zurück → bye (sonst übernähme sein HostSwitch den verlassenen Raum)
	ben.resume_guest()
	check(wait_until(func(): return ben.connection_state() == "closed"), "Ben: Verbindung beendet (%s)" % ben.connection_state())
	check(ben.client != null and ben.client.bye_id != "", "Ben bekam bye")
	check(ben.backup.is_empty() and not FileAccess.file_exists(BACKUP % "ben"), "Bens Sicherung gelöscht")
	check(RoomKeeper.current != null and int(RoomKeeper.current.stats.bye) == 1, "Raumhalter: 1 bye")
	# Abriss der Vermittler-Verbindung: Der Halter meldet sich selbst wieder an (ohne Probe)
	var kr: NetRelayHost = RoomKeeper.current.relay
	kr._ws.close()
	kr._ws = null
	kr._lost("Test")
	check(kr.state == "away", "Halter: Verbindung weg")
	check(wait_until(func(): return RoomKeeper.current != null and RoomKeeper.current.relay.state == "open", 8000), "Halter: wieder angemeldet")
	check(RoomKeeper.current != null and RoomKeeper.current.relay.room == code, "Halter: derselbe Raum")
	# Neue Gäste ohne Sicherung: warten (4503)
	var carl := new_client("carl", link)
	var web := new_web("Dora", code)
	check(wait_until(func(): return carl.client.host_away and web.host_away), "Carl und Browser-Gast: Gastgeber kurz weg (4503)")
	check(carl.connection_state() == "connecting", "Carl versucht es weiter")
	check(int(RoomKeeper.current.stats.wait) >= 2, "Raumhalter: wartende Gäste (%d)" % int(RoomKeeper.current.stats.wait))
	# Neue Lobby: derselbe Raum
	var host2 := make_host()
	check(host2.open("Gastgeberin", HOST_PORT, HOST_PORT) == OK, "neue Lobby")
	check(RoomKeeper.reusable(url).get("room", "") == code and RoomKeeper.reusable(url).get("live", false) == true, "reusable: laufender Halter")
	check(host2.open_online(url) == OK, "open_online")
	check(host2.session.online_state() == "open" and str(host2.session.online_info().get("room", "")) == code, "gleicher Raumcode %s sofort offen" % code)
	check(host2.session.online_kept, "online_kept")
	check(RoomKeeper.current == null and not FileAccess.file_exists(KEEP_FILE), "Halter und Datei aufgegeben")
	check(wait_until(func(): return carl.connection_state() == "open", 6000), "Carl landet von selbst in der neuen Lobby")
	check(wait_until(func(): return web.state == "open", 6000), "Browser-Gast ebenso")
	check(host2.session.players.size() == 3, "Lobby: Gastgeberin, Carl, Dora (%d)" % host2.session.players.size())
	check(relay.core.rooms.size() == 1, "nur ein Raum beim Vermittler")
	# Lobby schließen → wieder gehalten; discard() beendet ihn
	host2.leave()
	check(RoomKeeper.current != null and RoomKeeper.current.relay.room == code, "Lobby verlassen: Raum wieder gehalten")
	check(RoomKeeper.current.gid == "", "Lobby ohne Partie: keine gid")
	check(wait_until(func(): return carl.connection_state() == "closed"), "Carl bekommt bye")
	RoomKeeper.discard()
	pump(300)
	check(not relay.core.rooms.has(code), "discard(): Raum beim Vermittler beendet")
	check(RoomKeeper.current == null and not FileAccess.file_exists(KEEP_FILE), "discard(): nichts mehr gemerkt")


# ---------- Datei (App beendet) ----------

func run_file() -> void:
	var host := make_host()
	check(host.open("Gastgeberin", HOST_PORT, HOST_PORT) == OK, "Datei: Lobby")
	host.open_online(url)
	check(wait_until(func(): return host.session.online_state() == "open"), "Datei: Raum offen")
	var code := str(host.session.online_info().get("room", ""))
	host.leave()
	kill_keeper()
	pump(300)
	check(relay.core.rooms.has(code) and int(relay.core.rooms[code].host) < 0, "Datei: Raum ohne Gastgeber in der Frist")
	check(RoomKeeper.reusable(url).get("live", true) == false and RoomKeeper.reusable(url).get("room", "") == code, "Datei: reusable aus der Datei")
	var host2 := make_host()
	check(host2.open("Gastgeberin", HOST_PORT, HOST_PORT) == OK, "Datei: neue Lobby")
	host2.open_online(url)
	check(host2.session.online_kept, "Datei: online_kept")
	check(wait_until(func(): return host2.session.online_state() == "open"), "Datei: Raum zurückgeholt (open_existing)")
	check(str(host2.session.online_info().get("room", "")) == code, "Datei: derselbe Raumcode")
	check(not FileAccess.file_exists(KEEP_FILE), "Datei: aufgebraucht")
	# Raum abgelaufen: neuer Raum
	host2.leave()
	kill_keeper()
	check(wait_until(func(): return relay.core.rooms.has(code) and int(relay.core.rooms[code].host) < 0), "Datei: Gastgeber wieder weg")
	relay.advance(11 * 60 * 1000)
	pump(200)
	check(not relay.core.rooms.has(code), "Datei: Vermittler hat den Raum nach der Frist gelöscht")
	var host3 := make_host()
	check(host3.open("Gastgeberin", HOST_PORT, HOST_PORT) == OK, "Datei: dritte Lobby")
	host3.open_online(url)
	check(wait_until(func(): return host3.session.online_state() == "open" and str(host3.session.online_info().get("room", "")) != code, 6000),
		"Datei: Raum weg → neuer Raum (%s)" % str(host3.session.online_info().get("room", "")))
	check(not host3.session.online_kept, "Datei: neuer Raum ist nicht gemerkt")
	host3.leave()
	RoomKeeper.discard()
	pump(200)


# ---------- Höchstdauer ----------

func run_expire() -> void:
	fake_now = RoomKeeper.now_unix()
	RoomKeeper.clock = func() -> int: return fake_now
	var host := make_host()
	check(host.open("Gastgeberin", HOST_PORT, HOST_PORT) == OK, "Ablauf: Lobby")
	host.open_online(url)
	check(wait_until(func(): return host.session.online_state() == "open"), "Ablauf: Raum offen")
	var code := str(host.session.online_info().get("room", ""))
	host.leave()
	check(RoomKeeper.current != null, "Ablauf: gehalten")
	fake_now += RoomKeeper.KEEP_S - 5
	pump(100)
	check(RoomKeeper.current != null and relay.core.rooms.has(code), "Ablauf: kurz vor KEEP_S noch gehalten")
	fake_now += 10
	pump(300)
	check(RoomKeeper.current == null and not relay.core.rooms.has(code), "Ablauf: nach KEEP_S beendet")
	check(not FileAccess.file_exists(KEEP_FILE), "Ablauf: Datei gelöscht")
	RoomKeeper.clock = Callable()


# ---------- Hilfen ----------

# Halter wie beim Beenden der App: Anschluss zu ohne {k:"end"}, Datei bleibt
func kill_keeper() -> void:
	var k := RoomKeeper.current
	if k == null:
		check(false, "kein Halter")
		return
	var r := k.relay
	k._release()
	r.close(false)
	r.free()


func make_host() -> HostTable:
	var h := HostTable.new()
	h.auto_process = false
	h.speed = 0.0
	h.use_discovery = false
	h.autosave = false
	h.alive_ms = 400
	hosts.append(h)
	return h


func new_client(who: String, link: String) -> ClientTable:
	var c := ClientTable.new()
	c.auto_process = false
	c.reuse_token = false
	c.persist_tokens = false
	c.retry_ms = [100, 200, 400]
	c.ping_ms = 300
	c.host_away_ms = 300
	c.backup_path = BACKUP % who
	TableSource.clear_saved(c.backup_path)
	tables.append(c)
	c.join(link, 0, who.capitalize())
	return c


func new_web(who: String, code: String) -> NetClient:
	var c := NetClient.new()
	c.auto_poll = false
	c.reuse_token = false
	c.persist_tokens = false
	c.retry_ms = [100, 200, 400]
	c.ping_ms = 300
	c.host_away_ms = 300
	webs.append(c)
	c.connect_relay(url, code, who, "web")
	return c


func _write_keep(d: Dictionary) -> void:
	var f := FileAccess.open(KEEP_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func _with(d: Dictionary, key: String, value: Variant) -> Dictionary:
	var out := d.duplicate()
	out[key] = value
	return out


func pump(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while true:
		step()
		if Time.get_ticks_msec() >= end:
			break
		OS.delay_msec(1)


func step() -> void:
	relay.poll()
	for h in hosts:
		if is_instance_valid(h) and h.session != null:
			h.pump()
	for c in tables:
		if c.client != null:
			c.pump()
	for w in webs:
		(w as NetClient).poll()
	if RoomKeeper.current != null and is_instance_valid(RoomKeeper.current):
		RoomKeeper.current.pump()


func wait_until(cond: Callable, ms := 4000) -> bool:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		pump(2)
		if cond.call():
			return true
	return cond.call()
