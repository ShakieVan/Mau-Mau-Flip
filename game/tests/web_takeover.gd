extends "res://tests/handover_kit.gd"

# Mau-Mau Flip (Beta 1.6.1, Gastgeber-Übergabe): Regressionstest mit dem ECHTEN Browser-Client „Lite“ (docs/module/uebergabe.md 5, 7
# letzter Punkt). Kein test_*-Skript: tools/build.ps1 startet ihn nach dem Browser-Onlinetest (Invoke-WebTakeoverTest), weil er Chrome
# braucht; einzeln: tools/godot_run.ps1 -Script res://tests/web_takeover.gd -Headless -Timeout 200.
# Vermittler-Nachbau (TCP 24961) mit Lader relay/public und webclient/ als web.zip, Gastgeberin Hanna, App-Gäste Anna und Ben (mit
# HostSwitch), Lite in Chrome headless (Selbsttest webclient/autotest.js: tritt bei, meldet Bereit, spielt über die Oberfläche).
#  1  Übernahme online: Hanna stirbt still, Anna (Rang 0) übernimmt; Lite bekommt 4012 (bekannte c), meldet sich mit seinem Token
#     beim neuen Gastgeber an, sitzt auf seinem Platz und spielt weiter.
#  2  Lite mit neuer c während eines still toten Gastgebers: Anna stirbt still, Lite verliert die Verbindung und meldet sich mit neuer c
#     an (das hello hängt beim toten Gastgeber, „pong“ kommt vom Vermittler – Lite merkt nichts). Ben übernimmt; die neue c steht in
#     keinem Schnappschuss, erst der 4012-Rundumschlag holt Lite zurück. Lite sitzt auf seinem Platz und spielt weiter.
# Lite-Code bleibt unverändert; geprüft wird über den Gastgeber (Token, Platz, verbunden, eigene Aktionen, Zug geht weiter).
# Beta 1.6.2 (WLAN, docs/module/uebergabe.md 10.9/10.16, Gegenprüfung) – über die eigene LAN-Adresse des PCs (privat→privat wie im
# echten WLAN; ohne private Adresse übersprungen), Lite vom Server der Gastgeberin (web.zip aus webclient/):
#  W4 Lite tritt in der Lobby bei (welcome ohne gid), die Partie startet; Lite kennt gid/gen und die Erben nur aus hosts.
#  W1 Hanna fällt aus (Server zu), Anna übernimmt auf einem anderen Port; Lite findet sie über hosts und /info (fetch über Ursprünge),
#     verbindet sich mit fremdem Ursprung (Herkunftsliste wlan.past) und dem eigenen Token, sitzt auf seinem Platz und spielt weiter.
#  W3 Ziel von „Seite neu laden“ (#t=Token&n=Name auf dem neuen Ursprung, frisches Profil ohne gespeichertes Token): Lite sitzt
#     wieder auf seinem Platz.

const RELAY_PORT := 24961
const H_PORT := 24962
const A_PORT := 24963
const B_PORT := 24964
const LH_PORT := 24965          # Beta 1.6.2: WLAN-Teil (Hanna, Anna)
const LA_PORT := 24966
const CHROME := "C:/Program Files/Google/Chrome/Application/chrome.exe"

var chrome_pid := -1
var lite_token := ""
var lite_seat := -1
var lite_acts := 0              # Aktionen von Lites Platz beim aktuellen Gastgeber
var _listening: Array = []      # Gastgeber, deren session.message schon gezählt wird
var _round_over_ms := 0


func _initialize() -> void:
	rng.seed = 1612
	var t0 := Time.get_ticks_msec()
	if not FileAccess.file_exists(CHROME):
		print("HINWEIS: Chrome fehlt – Lite-Übernahmetest übersprungen")
		print("RESULT: 0 ok")
		quit(0)
		return
	var pub := ProjectSettings.globalize_path("res://").path_join("../relay/public").simplify_path()
	relay_port = RELAY_PORT
	relay = NetRelayDouble.new()
	relay.auto_poll = false
	relay.web_zip_path = _pack_webclient()
	if DirAccess.dir_exists_absolute(pub):
		relay.public_dir = pub
	check(relay.web_zip_path != "" and relay.public_dir != "", "webclient und relay/public vorhanden")
	check(relay.start(RELAY_PORT, RELAY_PORT) == OK, "Vermittler-Nachbau auf %d" % RELAY_PORT)
	if OS.get_environment("NUR") != "lan":
		_run()
	_stop_chrome()
	if OS.get_environment("NUR") != "online":
		_clear_devs()
		var t1 := Time.get_ticks_msec()
		_run_lan()
		_stop_chrome()
		print("  WLAN-Teil %d ms" % (Time.get_ticks_msec() - t1))
	print("  Dauer %d ms" % (Time.get_ticks_msec() - t0))
	finish()


# Gastgeber-Tische liefern Lite aus dem gepackten webclient/ aus (WLAN-Teil: die Seite kommt vom Gastgeber).
func make_host() -> HostTable:
	var h := super()
	if relay != null and relay.web_zip_path != "":
		h.web_zip_path = relay.web_zip_path
	return h


func _stop_chrome() -> void:
	if chrome_pid > 0:
		OS.kill(chrome_pid)
		chrome_pid = -1
		pump(300)


func _start_chrome(url: String, profile_name: String) -> void:
	var profile := ProjectSettings.globalize_path("user://web_takeover_test/" + profile_name)
	_wipe(profile)
	DirAccess.make_dir_recursive_absolute(profile)
	chrome_pid = OS.create_process(CHROME, ["--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
		"--mute-audio", "--user-data-dir=" + profile, "--window-size=844,390", url])
	check(chrome_pid > 0, "Chrome gestartet (%s)" % profile_name)


# Alle Geräte des Online-Teils abbauen (ohne bye, Dateien weg), Lite-Zähler zurück.
func _clear_devs() -> void:
	for d in devs:
		var s: TableSource = d.src()
		if s is HostTable:
			(s as HostTable).autosave = false
			if (s as HostTable).session != null:
				(s as HostTable).leave()
		elif s is ClientTable:
			(s as ClientTable).leave()
		if s != null:
			garbage.append(s)
		TableSource.clear_saved(d.path)
	for g in garbage:
		if is_instance_valid(g):
			if g is HostTable:
				(g as HostTable).autosave = false
			if g.get_parent() != null:
				g.get_parent().remove_child(g)
			g.free()
	garbage.clear()
	devs.clear()
	_listening.clear()
	lite_token = ""
	lite_seat = -1
	lite_acts = 0
	pump(200)


# Eigene private IPv4 des PCs (WLAN/LAN), "" = keine.
func _lan_ip() -> String:
	for a in NetAddresses.own_addresses():
		var ip := str(a.address)
		if NetProtocol.is_private_ipv4(ip) and not ip.begins_with("127.") and str(a.kind) != "virtual":
			return ip
	return ""


# ---------- Beta 1.6.2: WLAN (W4, W1, W3) ----------

func _run_lan() -> void:
	var ip := _lan_ip()
	if ip == "":
		print("HINWEIS: keine private LAN-Adresse – WLAN-Teil (W1, W3, W4) übersprungen")
		return
	var h := host_dev("Hanna", LH_PORT, false)
	var a := guest_dev("Anna", ip, LA_PORT, true, LH_PORT)
	a.sw.net_check = func(_targets: Array) -> bool: return true     # LAN da (die Prüfung selbst testen test_takeover_wlan)
	a.sw.discovery_setup = func(n: NetDiscovery) -> void:
		n.use_broadcast = false                                       # keine fremden Partien im echten Netz
		n.probe_local = false
		n.ports = []
	check(wait_until(func(): return a.ct().my_id > 0), "W: Anna (App) im WLAN bei Hanna (%s:%d)" % [ip, LH_PORT])
	var ht := h.ht()
	ht.add_bot("Minka")
	# W4: Lite in der Lobby (welcome ohne gid), Seite vom Server der Gastgeberin, Suche nach 3 s „getrennt“
	_start_chrome("http://%s:%d/?autotest=1&runden=9&suche_ab=3000" % [ip, LH_PORT], "chrome_lan")
	check(wait_until(func(): return not _lite_player(ht).is_empty() and bool(_lite_player(ht).ready), 40000), "W4: Lite in der Lobby beigetreten und bereit")
	var lp := _lite_player(ht)
	if lp.is_empty():
		return
	lite_token = str(lp.token)
	var cfg := RuleConfig.preset("offiziell")
	cfg.hand_size = 10
	ht.set_rules(cfg)
	check(ht.start(rng.randi_range(1, 9999)), "W4: Start")
	lite_seat = _seat_of_token(ht, lite_token)
	check(lite_seat >= 0, "W4: Lite hat einen Platz (%d)" % lite_seat)
	_listen_host(ht)
	check(_lite_plays(30000), "W4: Lite spielt bei Hanna (%d Aktionen)" % lite_acts)
	var anna_url := "http://%s:%d/" % [ip, LA_PORT]
	var hm := ht.hosts_message()
	check(str(hm.get("gid", "")) == ht.gid and (hm.get("list", []) as Array).any(func(e): return str(e.get("url", "")) == anna_url),
		"W4: hosts an Lite mit gid und Annas Adresse (%s)" % str(hm.get("list", [])))
	check(wait_until(func(): return a.ct().backup_current(), 3000) and a.sw.rank() == 0, "W1: Anna mit aktueller Sicherung, Rang 0")
	# W1: Hanna fällt aus, Anna übernimmt auf ihrem eigenen Port; Lite sucht reihum und zieht mit fremdem Ursprung um
	var hanna_seat := ht.host_seat
	_wait_not_lite_turn(ht)
	kill_lan_closed(h)
	check(wait_until(func(): return a.sw.takeovers == 1, 15000), "W1: Anna übernimmt (Zustand %s)" % a.sw.state)
	var at := a.ht()
	if at == null:
		return
	check(at.port() == LA_PORT, "W1: Anna führt auf Port %d (%d)" % [LA_PORT, at.port()])
	check(at.session.extra_origins().has("http://%s:%d" % [ip, LH_PORT]), "W1: Hannas Ursprung erlaubt (%s)" % str(at.session.extra_origins()))
	if OS.get_environment("OHNE_HERKUNFT") != "":
		at.session.set_extra_origins([])     # Gegenprobe von Hand: ohne Herkunftsliste muss W1 scheitern (fremder Ursprung abgelehnt)
	_listen_host(at)
	at.substitute_bot(hanna_seat)
	check(wait_until(func(): return _lite_back_lan(at), 40000), "W1: Lite findet Anna über hosts und /info, sitzt mit Token auf seinem Platz")
	check(_lite_plays(45000), "W1: Lite spielt bei Anna weiter (%d Aktionen)" % lite_acts)
	# W3: Ziel von „Seite neu laden“ – neuer Ursprung mit #t=Token&n=Name, frisches Profil (kein Token gespeichert)
	_wait_not_lite_turn(at)
	_stop_chrome()
	check(wait_until(func(): return not bool(_lite_player(at).get("connected", true)), 15000), "W3: alte Lite-Seite weg")
	_start_chrome("http://%s:%d/?autotest=1&runden=9#t=%s&n=Lite" % [ip, LA_PORT, lite_token], "chrome_lan_neu")
	check(wait_until(func(): return _lite_back_lan(at), 40000), "W3: Lite mit #t= auf dem neuen Ursprung wieder auf seinem Platz")


func _lite_back_lan(h: HostTable) -> bool:
	var p := _lite_player(h)
	return not p.is_empty() and bool(p.connected) and int(p.conn) >= 0 and int(p.conn) < NetProtocol.RELAY_CONN_BASE \
		and _seat_of_token(h, lite_token) == lite_seat and h.game != null and bool(h.game.connected[lite_seat])


func _run() -> void:
	var h := host_dev("Hanna", H_PORT)
	var link := str(h.ht().session.online_info().link)
	var code := str(h.ht().session.online_info().room)
	var a := guest_dev("Anna", link, A_PORT)
	var b := guest_dev("Ben", link, B_PORT)
	check(wait_until(func(): return a.ct().my_id > 0 and b.ct().my_id > 0), "App-Gäste angemeldet")
	# --- Lite über den Lader (wie beim Worker: /?r=CODE → /info?room= → /c/<version>/?r=CODE)
	var profile := ProjectSettings.globalize_path("user://web_takeover_test/chrome")
	_wipe(profile)
	DirAccess.make_dir_recursive_absolute(profile)
	chrome_pid = OS.create_process(CHROME, ["--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
		"--mute-audio", "--user-data-dir=" + profile, "--window-size=844,390",
		"http://127.0.0.1:%d/?r=%s&autotest=1&runden=9" % [RELAY_PORT, code.to_lower()]])
	check(chrome_pid > 0, "Chrome gestartet")
	var ht := h.ht()
	check(wait_until(func(): return not _lite_player(ht).is_empty() and bool(_lite_player(ht).ready), 40000),
		"Lite beigetreten und bereit")
	var lp := _lite_player(ht)
	if lp.is_empty():
		return
	lite_token = str(lp.token)
	check(lite_token != "", "Lite hat ein Token")
	var cfg := RuleConfig.preset("offiziell")
	cfg.hand_size = 10                      # längere Runden: beide Übernahmen fallen in die erste Runde
	ht.set_rules(cfg)
	check(ht.start(rng.randi_range(1, 9999)), "Start")
	lite_seat = _seat_of_token(ht, lite_token)
	check(lite_seat >= 0, "Lite hat einen Platz (%d)" % lite_seat)
	_listen_host(ht)
	check(wait_until(func(): return a.ct().view_rev > 0 and b.ct().view_rev > 0), "App-Gäste haben den Stand")
	check(_lite_plays(30000), "Lite spielt bei Hanna (%d Aktionen)" % lite_acts)
	check(wait_until(func(): return a.ct().backup_current() and b.ct().backup_current(), 3000), "Sicherungen aktuell")
	check(a.sw.rank() == 0 and b.sw.rank() == 1, "Rang Anna 0, Ben 1 (%d, %d)" % [a.sw.rank(), b.sw.rank()])

	# ---------- 1: Übernahme online, Lite folgt per 4012 mit Token ----------
	var hanna_seat := ht.host_seat
	var lite_c := _lite_c(ht)
	check(lite_c > 0, "1: Lites c beim Vermittler (%d)" % lite_c)
	check(((a.ct().backup.get("online", {}) as Dictionary).get("conns", []) as Array).has(lite_c), "1: Lites c steht in Annas Sicherung")
	_wait_not_lite_turn(ht)
	kill_still(h)
	check(wait_until(func(): return a.sw.takeovers == 1, 10000), "1: Anna übernimmt (Zustand %s)" % a.sw.state)
	var at := a.ht()
	if at == null:
		return
	_listen_host(at)
	at.substitute_bot(hanna_seat)           # Hanna ist weg: der Computer spielt für sie
	check(wait_until(func(): return _lite_back(at), 15000), "1: Lite meldet sich mit Token bei Anna an (gleicher Platz, verbunden)")
	check(_lite_c(at) != lite_c, "1: Lite mit neuer c (%d → %d)" % [lite_c, _lite_c(at)])
	check(wait_until(func(): return b.ct() != null and b.ct().connection_state() == "open" and b.ct().host_name() == "Anna", 6000), "1: Ben folgt")
	check(_lite_plays(45000), "1: Lite spielt bei Anna weiter (%d Aktionen)" % lite_acts)
	check(a.sw.takeovers == 1 and b.sw.takeovers == 0, "1: genau eine Übernahme")

	# ---------- 2: Lite mit neuer c während Anna still tot ist → Rundumschlag ----------
	check(wait_until(func(): return b.ct().backup_current() and int(b.ct().backup.get("gen", 0)) == at.gen, 4000), "2: Bens Sicherung aktuell (gen %d)" % at.gen)
	check(b.sw.rank() == 0, "2: Ben ist Rang 0 (%d)" % b.sw.rank())
	b.sw.t_silent_ms = 5000                 # Zeit für Lites neue Anmeldung beim toten Gastgeber, bevor Ben übernimmt
	if OS.get_environment("OHNE_RUNDUMSCHLAG") != "":
		# Gegenprobe von Hand: ohne Rundumschlag muss Fall 2 scheitern (Lite hängt mit seiner neuen c)
		b.sw.state_changed.connect(func(st: String) -> void:
			if st == "taking":
				((b.sw._new as HostTable).session.relay as NetRelayHost).sweep_extra = 0)
	var anna_seat := at.host_seat
	_wait_not_lite_turn(at)
	var old_c := _lite_c(at)
	var known: Array = ((b.ct().backup.get("online", {}) as Dictionary).get("conns", []) as Array).duplicate()
	var before: Array = (relay.core.rooms[code].guests as Dictionary).keys()
	kill_still(a)
	var g: Dictionary = relay.core.rooms[code].guests
	check(g.has(old_c), "2: Lites Socket beim Vermittler (c %d)" % old_c)
	if g.has(old_c):
		relay.close_ws(int(g[old_c]), 1011, "Test: Funkloch")   # Lite verbindet nach 1 s neu (neue c, hello an den toten Gastgeber)
	var new_c := [-1]
	# Ben hat sich noch nicht neu angemeldet (Wächter in watch): die neue c ist Lites
	var lite_new := func() -> bool:
		for c in (relay.core.rooms[code].guests as Dictionary).keys():
			if not before.has(c) and int(c) > old_c:
				new_c[0] = int(c)
		return new_c[0] > 0 and b.sw.state == "watch"
	check(wait_until(lite_new, 4000), "2: Lite meldet sich mit neuer c beim toten Gastgeber an (c %d)" % new_c[0])
	check(b.sw.takeovers == 0 and not known.has(new_c[0]), "2: die neue c steht in keiner Sicherung, noch keine Übernahme")
	pump(600)
	check(b.sw.takeovers == 0, "2: Lite bleibt ohne Antwort hängen (Ben wartet noch)")
	check(wait_until(func(): return b.sw.takeovers == 1, 15000), "2: Ben übernimmt (Zustand %s)" % b.sw.state)
	var bt := b.ht()
	if bt == null:
		return
	_listen_host(bt)
	bt.substitute_bot(anna_seat)
	bt.substitute_bot(hanna_seat)
	check(wait_until(func(): return _lite_back(bt), 15000), "2: Rundumschlag holt Lite zurück (Token, gleicher Platz, verbunden)")
	check(_lite_c(bt) != new_c[0], "2: Lite nach 4012 mit weiterer c (%d → %d)" % [new_c[0], _lite_c(bt)])
	check(_lite_plays(45000), "2: Lite spielt bei Ben weiter (%d Aktionen)" % lite_acts)
	check(int(relay.stats().get("rate_dropped", 0)) == 0, "Vermittler verwarf keine Rahmen")


# ---------- Lite beim Gastgeber ----------

func _lite_player(h: HostTable) -> Dictionary:
	for p in h.session.players.values():
		if str(p.kind) == "web" and (lite_token == "" or str(p.token) == lite_token):
			return p
	return {}


func _seat_of_token(h: HostTable, token: String) -> int:
	return seat_of_token(h, token)


func _lite_c(h: HostTable) -> int:
	var p := _lite_player(h)
	return int(p.conn) - NetProtocol.RELAY_CONN_BASE if not p.is_empty() and int(p.conn) >= NetProtocol.RELAY_CONN_BASE else -1


func _lite_back(h: HostTable) -> bool:
	var p := _lite_player(h)
	return not p.is_empty() and bool(p.connected) and int(p.conn) >= NetProtocol.RELAY_CONN_BASE and _seat_of_token(h, lite_token) == lite_seat \
		and h.game != null and bool(h.game.connected[lite_seat])


func _listen_host(h: HostTable) -> void:
	if _listening.has(h):
		return
	_listening.append(h)
	h.session.message.connect(func(id: int, m: Dictionary) -> void:
		if str(m.get("t", "")) == "act" and _seat_of_token(h, lite_token) == lite_seat and str(h.session.player(id).get("token", "")) == lite_token:
			lite_acts += 1)


# Lite handelt beim aktuellen Gastgeber mindestens einmal, und der Zug geht danach von Lites Platz weiter.
func _lite_plays(ms: int) -> bool:
	var start_acts := lite_acts
	var passed := [false]
	var was_lite := [false]
	return _drive(func():
		var h := host_now()
		if h == null or h.game == null:
			return false
		var on := h.game.current_seat() == lite_seat and h.game.phase() in MauGame.PLAY_PHASES
		if was_lite[0] and not on and lite_acts > start_acts:
			passed[0] = true
		was_lite[0] = on
		return passed[0], ms)


# Warten, bis Lite nicht am Zug ist (damit keine Aktion von Lite in den toten Gastgeber läuft und der Selbsttest auf eine Antwort wartet).
func _wait_not_lite_turn(h: HostTable) -> void:
	_drive(func(): return h.game.current_seat() != lite_seat and h.game.phase() in MauGame.PLAY_PHASES, 20000)


# Pumpen; App-Geräte spielen per MauBot, beim Rundenende startet der Gastgeber die nächste Runde.
func _drive(cond: Callable, ms: int) -> bool:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		pump(5)
		var h := host_now()
		if h != null and h.game != null and not h.is_settling():
			if h.game.phase() == "round_over":
				if _round_over_ms == 0:
					_round_over_ms = Time.get_ticks_msec()
				elif Time.get_ticks_msec() - _round_over_ms > 1500:
					_round_over_ms = 0
					h.act({"a": "next_round"})
			else:
				_round_over_ms = 0
				for d in devs:
					if d.dead:
						continue
					var t: TableSource = d.src()
					if t == null or (t is ClientTable and ((t as ClientTable).client == null or t.connection_state() != "open")):
						continue
					_act(t, t.current_view(), h)
		if cond.call():
			return true
	return cond.call()


# ---------- Hilfen ----------

func _pack_webclient() -> String:
	var src := ProjectSettings.globalize_path("res://").path_join("../webclient").simplify_path()
	if not DirAccess.dir_exists_absolute(src):
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://web_takeover_test"))
	var zip_path := "user://web_takeover_test/web.zip"
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


func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(d))
		DirAccess.remove_absolute(dir.path_join(d))
