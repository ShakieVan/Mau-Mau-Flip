extends SceneTree

# Online-Spiel Ende zu Ende (docs/online/ENTWURF.md, Abschnitt 6) im selben Prozess über 127.0.0.1: Vermittler-Nachbau
# (NetRelayDouble, TCP 24782), Gastgeber-Sitzung (NetHostSession, WLAN auf TCP 24783 und zugleich online), ein WLAN-Gast, zwei
# Online-App-Gäste (NetClient über den Vermittler, einer per Raum-Link) und – wenn Chrome da ist – der Browser-Client „Lite“
# (Chrome headless öffnet http://127.0.0.1:24782/?r=CODE&autotest=1, tritt bei und meldet „Bereit“).
# Geprüft: alle in derselben Lobby, Online-Kennung, Nachrichten in beide Richtungen, Verbindungsnummern ab 1 000 000, Gastgeber
# verliert den Vermittler (away → mit Token zurück, Gäste kommen als dieselben Spieler wieder), Gast bricht ab und kommt wieder,
# laufende Partie lehnt Neue ab, „Online schließen“ trennt nur die Online-Gäste, finish beendet den Raum ({k:"end"}).
# Bestehendes WLAN-Spiel bleibt unverändert (siehe test_net_session).

const RELAY_PORT := 24782
const HOST_PORT := 24783
const CHROME := "C:/Program Files/Google/Chrome/Application/chrome.exe"

var failures := 0
var checks := 0
var relay: NetRelayDouble
var host: NetHostSession
var clients: Array = []
var inbox := {}
var joined: Array = []
var left: Array = []
var rejoined: Array = []
var host_msgs: Array = []
var online_states: Array = []
var chrome_pid := -1

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)

func _init() -> void:
	relay = NetRelayDouble.new()
	relay.auto_poll = false
	relay.web_zip_path = pack_webclient()
	check(relay.start(RELAY_PORT, RELAY_PORT) == OK, "Vermittler-Nachbau auf %d" % RELAY_PORT)
	host = NetHostSession.new()
	host.auto_poll = false
	host.use_discovery = false
	host.web_zip_path = ""
	host.player_joined.connect(func(id): joined.append(id))
	host.player_left.connect(func(id): left.append(id))
	host.player_rejoined.connect(func(id): rejoined.append(id))
	host.message.connect(func(id, msg): host_msgs.append([id, msg]))
	host.online_changed.connect(func(st, _i): online_states.append(st))
	check(host.start("Lena", HOST_PORT, HOST_PORT) == OK, "Gastgeber im WLAN auf %d" % HOST_PORT)
	run()
	if chrome_pid > 0:
		OS.kill(chrome_pid)
	for c in clients:
		c.close()
		c.free()
	host.stop()
	host.free()
	relay.stop()
	relay.free()
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)

func run() -> void:
	# --- Online öffnen
	check(host.online_state() == "off", "online zunächst aus")
	host.open_online("http://127.0.0.1:%d" % RELAY_PORT)
	check(wait(func(): return host.online_state() == "open"), "Online-Raum offen (%s)" % str(host.online_info()))
	check(online_states == ["connecting", "open"], "online_changed: connecting → open (%s)" % str(online_states))
	var code := str(host.online_info().get("room", ""))
	check(NetProtocol.normalize_room_code(code) == code and code != "", "Raumcode " + code)
	check(str(host.online_info().get("link", "")) == "http://127.0.0.1:%d/?r=%s" % [RELAY_PORT, code], "Link " + str(host.online_info().get("link")))
	# --- Gäste: WLAN, Online (Code), Online (Raum-Link über connect_to wie ClientTable)
	var wlan := new_client("Wlan")
	wlan.connect_to("127.0.0.1", HOST_PORT, "Wlan")
	var mia := new_client("Mia")
	mia.connect_relay("http://127.0.0.1:%d" % RELAY_PORT, code.to_lower().replace("-", " "), "Mia")
	var ole := new_client("Ole")
	ole.connect_to("http://127.0.0.1:%d/?r=%s" % [RELAY_PORT, code], 0, "Ole")
	check(ole.is_online() and ole.room == code and ole.port == 0, "Raum-Link als Adresse → online")
	check(wait(func(): return wlan.state == "open" and mia.state == "open" and ole.state == "open"), "alle drei angenommen (%s/%s/%s)" % [wlan.state, mia.state, ole.state])
	check(joined.size() == 3, "drei Beitritte beim Gastgeber")
	var pm := player_by_name("Mia")
	var po := player_by_name("Ole")
	var pw := player_by_name("Wlan")
	check(int(pm.get("conn", -1)) >= NetProtocol.RELAY_CONN_BASE and int(po.get("conn", -1)) >= NetProtocol.RELAY_CONN_BASE
		and int(pw.get("conn", -1)) > 0 and int(pw.get("conn", -1)) < NetProtocol.RELAY_CONN_BASE, "Verbindungsnummern: online ab 1 000 000, WLAN darunter")
	check(bool(pm.get("online", false)) and not bool(pw.get("online", false)), "Online-Kennung nur für Online-Gäste")
	check(wait(func(): return lobby_size(mia) == 4 and lobby_size(wlan) == 4 and lobby_size(ole) == 4), "Lobby mit 4 Spielern bei WLAN- und Online-Gästen")
	var entry := lobby_entry(mia, int(pm.id))
	check(entry.get("online") == true and not lobby_entry(mia, int(pw.id)).has("online"), "Lobby: online-Feld nur bei Online-Gästen")
	# --- Lite im Browser (Chrome headless)
	lite(code)
	# --- Nachrichten in beide Richtungen
	mia.send({"t": "act", "seq": 1, "a": {"a": "draw"}})
	wlan.send({"t": "act", "seq": 1, "a": {"a": "draw"}})
	check(wait(func(): return host_msgs.size() >= 2), "Spielaktionen von WLAN- und Online-Gast")
	check(host_msgs.any(func(m): return m[0] == int(pm.id) and m[1].a.a == "draw"), "Aktion des Online-Gasts mit seiner id")
	host.broadcast({"t": "notice", "text": "Grüße 🃏"})
	check(wait(func(): return last_of(mia, "notice").get("text") == "Grüße 🃏" and last_of(wlan, "notice").get("text") == "Grüße 🃏"), "broadcast an beide Transporte (Umlaute, Emoji)")
	host.send_to(int(po.id), {"t": "state", "events": [], "view": {"big": "y".repeat(60000)}})
	check(wait(func(): return str(last_of(ole, "state").get("view", {}).get("big", "")).length() == 60000), "großer Stand (60 KB) über den Vermittler")
	# --- Gastgeber verliert den Vermittler: Online-Gäste 4503, Gastgeber verbindet mit Token neu, Gäste kommen wieder
	mia.host_away_ms = 300
	ole.host_away_ms = 300
	var r := host.relay
	r._ws.close()
	r._ws = null
	r._lost("Test")
	check(host.online_state() == "away", "Gastgeber online kurz weg")
	# Beta 1.3.3: Nur der Gastgeber ist weg – seine Online-Gäste gelten nicht als gegangen (keine Vertretung durch den Computer)
	check(bool(host.player(int(pm.id)).connected) and bool(host.player(int(pw.id)).connected), "Online-Gäste bleiben verbunden, WLAN-Gast auch")
	check(wait(func(): return host.online_state() == "open", 6000), "Gastgeber wieder online (Token)")
	check(str(host.online_info().get("room")) == code, "derselbe Raumcode")
	check(wait(func(): return rejoined.has(int(pm.id)) and rejoined.has(int(po.id)), 8000), "Online-Gäste als dieselben Spieler zurück")
	check(wait(func(): return mia.state == "open") and int(mia.my_id) == int(pm.id), "Mia wieder angenommen (id %d, %s, Spieler %d)" % [mia.my_id, mia.state, int(pm.id)])
	# --- Online-Gast bricht ab und kommt mit Token wieder
	rejoined.clear()
	mia._ws.close()
	mia._lost("Test")
	check(wait(func(): return rejoined.has(int(pm.id)), 6000), "Online-Gast nach Abbruch wieder da")
	# --- laufende Partie: Neue ohne Token werden abgelehnt
	host.send_start()
	check(wait(func(): return not last_of(mia, "start").is_empty() and not last_of(wlan, "start").is_empty()), "start an beide Transporte")
	var late := new_client("Spät")
	late.connect_relay("http://127.0.0.1:%d" % RELAY_PORT, code, "Spät")
	check(wait(func(): return late.state == "closed"), "laufende Partie: Neuer online abgelehnt")
	check(late.reject_code == "running", "Ablehnung „running“ (%s)" % late.reject_code)
	# --- unbekannter Raum
	var lost := new_client("Weg")
	lost.connect_relay("http://127.0.0.1:%d" % RELAY_PORT, "MOND-11" if code != "MOND-11" else "MOND-12", "Weg")
	check(wait(func(): return lost.state == "closed"), "unbekannter Raum → endgültig")
	check(lost.close_text.contains("Raum nicht gefunden") and lost.close_text.contains("Link"), "Text: Raum nicht gefunden, Link schicken lassen: " + lost.close_text)
	# --- Online schließen: Online-Gäste bekommen „bye“, WLAN bleibt
	host.close_online()
	check(host.online_state() == "off" and host.relay == null, "online geschlossen")
	check(wait(func(): return mia.state == "closed" and ole.state == "closed"), "Online-Gäste endgültig getrennt")
	check(mia.close_text == I18n.t("Der Gastgeber hat das Online-Spiel geschlossen.") or mia.close_text == I18n.t("Der Gastgeber hat das Spiel beendet."), "Grund: " + mia.close_text)
	pump(300)
	check(wlan.state == "open" and bool(host.player(int(pw.id)).connected), "WLAN-Gast bleibt verbunden")
	check(relay.core.rooms.is_empty(), "Raum beim Vermittler gelöscht")
	# --- erneut online öffnen, dann finish: Raum weg, alle getrennt
	host.open_online("http://127.0.0.1:%d" % RELAY_PORT)
	check(wait(func(): return host.online_state() == "open"), "wieder online")
	var finished := [false]
	host.finished.connect(func(): finished[0] = true)
	host.finish()
	check(wait(func(): return finished[0], 5000), "finish fertig")
	pump(200)
	check(relay.core.rooms.is_empty(), "finish beendet den Online-Raum")
	check(wlan.state == "closed", "WLAN-Gast getrennt")

# Browser-Client „Lite“ über den Vermittler (Chrome headless, Selbsttest tritt bei und meldet Bereit)
func lite(code: String) -> void:
	if not FileAccess.file_exists(CHROME):
		print("HINWEIS: Chrome fehlt – Lite-Gast übersprungen")
		return
	if relay.web_zip_path == "" or not FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../webclient/netz.js")).contains("role=guest"):
		print("HINWEIS: Lite ohne Online-Modus – Lite-Gast übersprungen")
		return
	var profile := ProjectSettings.globalize_path("user://online_test/chrome")
	DirAccess.make_dir_recursive_absolute(profile)
	var url := "http://127.0.0.1:%d/?r=%s&autotest=1" % [RELAY_PORT, code]
	chrome_pid = OS.create_process(CHROME, ["--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
		"--user-data-dir=" + profile, "--window-size=844,390", url])
	check(chrome_pid > 0, "Chrome gestartet")
	var ok := wait(func():
		for p in host.players.values():
			if str(p.kind) == "web" and bool(p.get("online", false)) and bool(p.ready):
				return true
		return false, 30000)
	check(ok, "Lite-Gast online beigetreten und bereit")
	if chrome_pid > 0:
		OS.kill(chrome_pid)
		chrome_pid = -1
	if ok:
		var web: Dictionary = {}
		for p in host.players.values():
			if str(p.kind) == "web":
				web = p
		check(wait(func(): return not bool(host.player(int(web.id)).connected), 5000), "Lite getrennt, Platz bleibt")
		host.remove_player(int(web.id))

func pack_webclient() -> String:
	var src := ProjectSettings.globalize_path("res://").path_join("../webclient").simplify_path()
	if not DirAccess.dir_exists_absolute(src):
		return ""
	var zip_path := "user://online_test/web.zip"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://online_test"))
	var z := ZIPPacker.new()
	if z.open(zip_path) != OK:
		return ""
	_pack_dir(z, src, "")
	z.close()
	return zip_path

func _pack_dir(z: ZIPPacker, dir: String, prefix: String) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".mp4"):
			continue
		z.start_file(prefix + f)
		z.write_file(FileAccess.get_file_as_bytes(dir.path_join(f)))
		z.close_file()
	for d in DirAccess.get_directories_at(dir):
		if d != "test":
			_pack_dir(z, dir.path_join(d), prefix + d + "/")

# ---------- Hilfen ----------

func new_client(n: String) -> NetClient:
	var c := NetClient.new()
	c.name = n
	c.auto_poll = false
	c.persist_tokens = false
	c.reuse_token = false                # mehrere Gäste je Raum im selben Prozess; Rückkehr nutzt das Token aus „welcome“
	c.retry_ms = [150, 300, 600, 800]
	inbox[c] = []
	c.message.connect(func(m): inbox[c].append(m))
	clients.append(c)
	return c

func player_by_name(n: String) -> Dictionary:
	for p in host.players.values():
		if str(p.name) == n:
			return p
	return {}

func pump(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while true:
		relay.poll()
		host.poll()
		for c in clients:
			c.poll()
		if Time.get_ticks_msec() >= end:
			break
		OS.delay_msec(1)

func wait(cond: Callable, ms := 4000) -> bool:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		pump(2)
		if cond.call():
			return true
	return cond.call()

func last_of(c: NetClient, t: String) -> Dictionary:
	for i in range(inbox[c].size() - 1, -1, -1):
		if inbox[c][i].get("t") == t:
			return inbox[c][i]
	return {}

func lobby_size(c: NetClient) -> int:
	return (last_of(c, "lobby").get("players", []) as Array).size()

func lobby_entry(c: NetClient, id: int) -> Dictionary:
	for p in last_of(c, "lobby").get("players", []):
		if int(p.id) == id:
			return p
	return {}
