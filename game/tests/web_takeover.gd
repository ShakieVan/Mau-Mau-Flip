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

const RELAY_PORT := 24961
const H_PORT := 24962
const A_PORT := 24963
const B_PORT := 24964
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
	_run()
	if chrome_pid > 0:
		OS.kill(chrome_pid)
		chrome_pid = -1
	print("  Dauer %d ms" % (Time.get_ticks_msec() - t0))
	finish()


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
