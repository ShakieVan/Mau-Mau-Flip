extends SceneTree

# Modul E2 – Testgastgeber für den Browser-Client „Lite“ (kein test_*.gd: läuft nur zusammen mit einem Browser).
# ECHTER Gastgeber: HostTable (Modul G) mit NetHostSession/NetServer (Modul D) und MauGame/MauBot (Modul A) – dieselbe Spielsteuerung
# wie am Gastgeber-Handy: Lobby, Computergegner mit Denkpausen und Mau-Schonfrist, Verteilung je Platz (events_for/view_for, rev,
# seq_ack), err bei Ablehnung, notice an alle, Warten auf getrennte Menschen, Wiederkommen mit Token.
# Nur der Gastgeber-Platz selbst (im Spiel der Mensch am Gastgeber-Handy) wird hier von MauBot auf seiner Sicht gespielt (host.act),
# und „Nächste Runde“ tippt er nach 4 s an. web.zip wird wie tools/build.ps1 -Target Web aus webclient/ gepackt (ohne versteckte Dateien).
#
# Ablauf: Server starten → Browser treten bei und melden „Bereit“ → host.start() → Rundenende → (WEB_RUNDEN) → warten, bis alle
# Browser weg sind → zurück in die Lobby (nächster Browser, WEB_SITZUNGEN) → Ende mit „RESULT: n ok“, wenn jeder Browser-Selbsttest
# per {t:"log", text:"AUTOTEST OK…"} bestanden hat (WEB_ERWARTE_OK=1) bzw. ohne Prüfung (0, z. B. Gerätetest am Handy).
#
# Umgebung: WEB_PORT (24870), WEB_SEKUNDEN (240), WEB_BOTS (2 zusätzliche Computergegner), WEB_TEMPO (Faktor für alle Denkpausen,
#           0.5), WEB_PRESET (""), WEB_REGELN (JSON, z. B. {"stacking":"same"}), WEB_SEED (4711), WEB_SITZUNGEN (1),
#           WEB_RUNDEN (nach so vielen Rundenenden keine neue Runde, 1), WEB_HALTER (1: Port+1 nimmt an und antwortet nie,
#           für Chrome --dump-dom), WEB_ERWARTE_OK (1), WEB_ZIP ("" = aus webclient/ packen),
#           WEB_NACH_BERICHT (ms; >= 0: Sitzung endet so lange nach dem Selbsttest-Bericht, auch wenn der Browser bleibt – Handy; -1 aus).
#           WEB_SZENE ("farbwahl": gebaute Lage mit 3 Plätzen, der Browser muss nach seinem Flip die Farbe wählen).
# Aufruf über tools/webtest/web_e2e.ps1 (startet diesen Gastgeber im Hintergrund und Chrome dazu).

const THINK_MIN := 0.6
const THINK_MAX := 1.2
const NEXT_ROUND_MS := 4000

var host: HostTable
var cfg: RuleConfig
var web_ids: Array = []           # Browser-Spieler dieser Sitzung
var holder: TCPServer
var held: Array = []
var stats := {"web_acts": 0, "web_rejects": 0, "host_acts": 0, "host_rejects": 0, "rejoins": 0, "left": 0, "rounds": 0,
	"mau": 0, "finish": 0, "notices": 0}
var autotest_ok := 0
var autotest_fail := 0
var problems: Array = []
var rng := RandomNumberGenerator.new()
var report_at := -1
var speed := 0.5
var _rev_seen := 0
var _plan := {}                   # nächster Zug des Gastgeber-Platzes {a, at}
var _plan_rev := -1


func env_int(k: String, d: int) -> int:
	var v := OS.get_environment(k)
	return int(v) if v.is_valid_int() else d


func env_float(k: String, d: float) -> float:
	var v := OS.get_environment(k)
	return float(v) if v.is_valid_float() else d


# wie tools/build.ps1 Build-WebZip: Pfade relativ zu webclient/, „/“ als Trenner, ohne versteckte Dateien und Ordnereinträge
func add_dir(z: ZIPPacker, base: String, rel: String) -> int:
	var n := 0
	var dir := base.path_join(rel) if rel != "" else base
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("."):
			continue
		z.start_file(rel.path_join(f) if rel != "" else f)
		z.write_file(FileAccess.get_file_as_bytes(dir.path_join(f)))
		z.close_file()
		n += 1
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with("."):
			continue
		n += add_dir(z, base, rel.path_join(d) if rel != "" else d)
	return n


func _initialize() -> void:
	var port := env_int("WEB_PORT", 24870)
	var seconds := env_int("WEB_SEKUNDEN", 240)
	var sitzungen := env_int("WEB_SITZUNGEN", 1)
	var runden_max := env_int("WEB_RUNDEN", 1)
	var erwarte_ok := env_int("WEB_ERWARTE_OK", 1) == 1
	var game_seed := env_int("WEB_SEED", 4711)
	var nach_bericht := env_int("WEB_NACH_BERICHT", -1)
	speed = env_float("WEB_TEMPO", 0.5)
	rng.seed = game_seed
	var zip_path := OS.get_environment("WEB_ZIP")
	if zip_path == "":
		var web := ProjectSettings.globalize_path("res://").path_join("../webclient").simplify_path()
		zip_path = "user://web_e2e/web.zip"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://web_e2e"))
		var z := ZIPPacker.new()
		z.open(zip_path)
		print("web.zip aus webclient/: %d Dateien" % add_dir(z, web, ""))
		z.close()
	cfg = RuleConfig.preset(OS.get_environment("WEB_PRESET")) if OS.get_environment("WEB_PRESET") != "" else RuleConfig.new()
	var extra := OS.get_environment("WEB_REGELN")
	if extra != "":
		var d = JSON.parse_string(extra)
		if d is Dictionary:
			cfg.apply_dict(d)

	host = HostTable.new()
	host.auto_process = false
	host.autosave = false
	host.use_discovery = false
	host.web_zip_path = zip_path
	host.speed = speed
	host.set_rules(cfg)
	host.notice.connect(func(t: String) -> void:
		stats.notices += 1
		print("HINWEIS: ", t))
	host.state_changed.connect(_on_host_state)
	if host.open("Lena", port, port) != OK:
		print("FAIL: Server startet nicht auf Port %d" % port)
		host.free()
		quit(1)
		return
	var session := host.session
	session.log_line.connect(_on_log)
	session.message.connect(_on_web_message)
	session.player_joined.connect(func(id: int) -> void:
		if str(session.player(id).get("kind")) == "web":
			web_ids.append(id)
			print("Browser beigetreten: id %d „%s“" % [id, session.player(id).get("name", "")]))
	session.player_left.connect(func(_id: int) -> void: stats.left += 1)
	session.player_rejoined.connect(func(id: int) -> void:
		stats.rejoins += 1
		print("Browser zurück: id %d" % id))
	for i in env_int("WEB_BOTS", 2):
		host.add_bot()
	if env_int("WEB_HALTER", 1) == 1:
		holder = TCPServer.new()
		if holder.listen(port + 1, "127.0.0.1") != OK:
			print("Hinweis: Halter-Port %d belegt" % (port + 1))
	print("SERVER-BEREIT %d (Version %s, HostTable, Tempo %.2f)" % [host.port(), session.game_version, speed])

	var end := Time.get_ticks_msec() + seconds * 1000
	var round_over_at := -1
	var lost_since := -1
	var played := false
	var done_sessions := 0
	while Time.get_ticks_msec() < end:
		_rev_seen = host.rev
		host.pump()
		if holder != null:
			while holder.is_connection_available():
				held.append(holder.take_connection())
		var now := Time.get_ticks_msec()
		if host.game == null:
			if not web_ids.is_empty() and host.session.all_ready():
				_start_game(game_seed + done_sessions)
				played = true
				round_over_at = -1
		else:
			var ph := host.game.phase()
			if ph == "round_over" or ph == "game_over":
				if round_over_at < 0:
					round_over_at = now
					stats.rounds += 1
				elif now - round_over_at > NEXT_ROUND_MS and ph == "round_over" and stats.rounds < runden_max:
					round_over_at = -1
					var rev0 := host.rev
					host.act({"a": "next_round"})
					print("next_round (Gastgeber): %s" % ("ok" if host.rev != rev0 else "abgelehnt"))
			else:
				round_over_at = -1
				_host_step(now)
		# Sitzung zu Ende, wenn nach dem Spiel alle Browser 4 s weg sind
		var any_conn := web_ids.any(func(id): return bool(host.session.player(id).get("connected", false)))
		if nach_bericht >= 0 and report_at >= 0 and now - report_at > nach_bericht:
			any_conn = false
			lost_since = 0
			report_at = -1
		if played and not any_conn:
			if lost_since < 0:
				lost_since = now
			elif now - lost_since > 4000:
				done_sessions += 1
				print("Sitzung %d beendet (Phase %s)" % [done_sessions, host.game.phase() if host.game != null else "-"])
				if done_sessions >= sitzungen:
					break
				_reset_session()
				played = false
				lost_since = -1
		else:
			lost_since = -1
		OS.delay_msec(4)
	print("STATS: %s autotest_ok=%d autotest_fail=%d" % [JSON.stringify(stats), autotest_ok, autotest_fail])
	host.leave()
	host.free()
	for c in held:
		(c as StreamPeerTCP).disconnect_from_host()
	if holder != null:
		holder.stop()
	if Time.get_ticks_msec() >= end:
		problems.append("Zeitgrenze (%d s) erreicht, %d von %d Sitzungen" % [seconds, done_sessions, sitzungen])
	if erwarte_ok and autotest_ok < sitzungen:
		problems.append("Browser-Selbsttest: %d ok, %d fehlgeschlagen, erwartet %d" % [autotest_ok, autotest_fail, sitzungen])
	if stats.host_rejects > 0:
		problems.append("%d Züge des Gastgeber-Platzes abgelehnt" % stats.host_rejects)
	if problems.is_empty():
		print("RESULT: %d ok" % (done_sessions + autotest_ok))
	else:
		for p in problems:
			print("FAIL: ", p)
	quit(0 if problems.is_empty() else 1)


func _start_game(game_seed: int) -> void:
	if not host.start(game_seed):
		print("FAIL: host.start() abgelehnt")
		return
	var szene := OS.get_environment("WEB_SZENE")
	if szene == "farbwahl" and host.seats.size() == 3 and str(host.seats[2].kind) == "human" and host.host_seat == 0:
		# Platz 2 (Browser) hat nur den Flip passend; nach dem Flip liegt ein Joker oben → Phase „color“, Aktion {a:"color"}
		var g := RulesFixture.build(cfg, 3, {"side": "hell", "current": 2, "color": "rot", "top": "hell_rot_5",
			"discard": ["hell_gelb_9/dunkel_wuenscher"],
			"hands": [["hell_blau_1", "hell_gelb_2", "hell_gruen_3", "hell_blau_7", "hell_gelb_8"],
				["hell_gruen_1", "hell_blau_2", "hell_gelb_3", "hell_gruen_7", "hell_blau_8"],
				["hell_rot_flip", "hell_blau_3", "hell_gelb_4", "hell_gruen_2"]]}, game_seed)
		for s in 3:
			g.players[s] = (host.seats[s] as Dictionary).duplicate()
			g.set_connected(s, bool(host.session.player(host._seat_ids[s]).connected))
		host.game = g
		host._changed([])
	var names := PackedStringArray()
	for p in host.seats:
		names.append("%s (%s)" % [p.name, p.kind])
	print("PARTIE: %s, Gastgeber-Platz %d%s" % [", ".join(names), host.host_seat, " Szene " + szene if szene != "" else ""])


# Gastgeber-Platz: MauBot auf der eigenen Sicht, mit Denkpause wie die Computergegner (Erwischen erst nach der Schonfrist)
func _host_step(now: int) -> void:
	if _plan_rev != host.rev:
		_plan_rev = host.rev
		_plan = {}
		var wahl := MauBot.choose(host.view_of(host.host_seat), rng.randi(), 1)
		if not wahl.is_empty():
			var delay := rng.randf_range(THINK_MIN, THINK_MAX)
			match str(wahl.a):
				"mau":
					delay = GameTable.MAU_THINK
				"catch":
					delay = maxf(delay, GameTable.MAU_GRACE + 0.3)
			_plan = {"a": wahl, "at": now + int(delay * 1000.0 * speed)}
	if _plan.is_empty() or now < int(_plan.at):
		return
	var action: Dictionary = _plan.a
	_plan = {}
	var rev0 := host.rev
	host.act(action)
	stats.host_acts += 1
	if host.rev == rev0:
		stats.host_rejects += 1
		print("Gastgeber-Platz abgelehnt: %s" % JSON.stringify(action))


# Stand für den Gastgeber-Platz (gefiltert): Mau-Ereignisse zählen
func _on_host_state(events: Array, _view: Dictionary) -> void:
	for e in events:
		var name := str((e as Dictionary).get("e", ""))
		if name == "mau" or name == "finish":
			stats[name] += 1
			print("%s: Platz %d" % [name.to_upper(), int(e.get("seat", -1))])


# Aktionen der Browser verarbeitet HostTable (dieser Empfänger hängt danach): angenommen, wenn sich rev geändert hat.
func _on_web_message(id: int, msg: Dictionary) -> void:
	if str(msg.get("t")) != "act":
		print("Nachricht von %d: %s" % [id, JSON.stringify(msg).left(200)])
		return
	stats.web_acts += 1
	var ok := host.rev != _rev_seen
	_rev_seen = host.rev
	if not ok:
		stats.web_rejects += 1
	print("Browser id %d: %s → %s" % [id, JSON.stringify(msg.get("a", {})), "ok" if ok else "ABGELEHNT"])


func _on_log(t: String) -> void:
	if t.contains("AUTOTEST OK"):
		autotest_ok += 1
		report_at = Time.get_ticks_msec()
	elif t.contains("AUTOTEST FAIL"):
		autotest_fail += 1
		report_at = Time.get_ticks_msec()
	print("LOG: ", t.left(900))


func _reset_session() -> void:
	# Partie verwerfen, Browser dieser Sitzung entfernen, zurück in die Lobby: der nächste Browser (frisches Profil, ohne Token) kann beitreten
	host.back_to_lobby()
	for id in web_ids:
		host.remove_player(id)
	web_ids.clear()
	_plan = {}
	_plan_rev = -1
