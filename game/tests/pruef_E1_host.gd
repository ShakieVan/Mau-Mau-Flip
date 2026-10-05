extends SceneTree

# Prüfer E1 (vorübergehend, nach Gebrauch löschen): echter Gastgeber für den Browser-Client „Lite“.
# NetHostSession (Modul D) liefert webclient/ als Zip aus, MauGame + MauBot (Modul A) spielen; Platz 0 ist der Gastgeber (Bot).
# Umgebung: PRUEF_PORT (24861), PRUEF_SECONDS (300), PRUEF_BOTS (zusätzliche Bots, 2), PRUEF_PRESET (""), PRUEF_RULES (JSON),
#           PRUEF_TAKT (ms je Bot-Aktion, 450), PRUEF_TRENNEN (nach n eigenen Aktionen die Verbindung hart trennen, 0 = nie),
#           PRUEF_ENDE (Partie nach Rundenende beenden und Lobby schicken: 1).

var session: NetHostSession
var game: MauGame
var seat_ids: Array = []
var web_ids: Array = []
var web_acts := 0
var states := 0
var errs := 0
var logs: Array = []
var getrennt_am := -1
var getrennt_getan := false
var rejoins := 0
var beendet := false

func env_int(k: String, d: int) -> int:
	var v := OS.get_environment(k)
	return int(v) if v.is_valid_int() else d

func add_dir(z: ZIPPacker, base: String, rel: String) -> int:
	var n := 0
	var dir := base.path_join(rel) if rel != "" else base
	for f in DirAccess.get_files_at(dir):
		z.start_file(rel.path_join(f) if rel != "" else f)
		z.write_file(FileAccess.get_file_as_bytes(dir.path_join(f)))
		z.close_file()
		n += 1
	for d in DirAccess.get_directories_at(dir):
		n += add_dir(z, base, rel.path_join(d) if rel != "" else d)
	return n

func web_seat(id: int) -> int:
	return seat_ids.find(id)

func send_state(events: Array, actor_id := -1, seq := -1) -> void:
	for id in web_ids:
		var s := web_seat(id)
		var m := {"t": "state", "events": game.events_for(s, events), "view": game.view_for(s)}
		if id == actor_id and seq >= 0:
			m["seq_ack"] = seq
		session.send_to(id, m)
	states += 1

func _init() -> void:
	var port := env_int("PRUEF_PORT", 24861)
	var seconds := env_int("PRUEF_SECONDS", 300)
	var takt := env_int("PRUEF_TAKT", 450)
	var trennen := env_int("PRUEF_TRENNEN", 0)
	var ende_lobby := env_int("PRUEF_ENDE", 0)
	var web := ProjectSettings.globalize_path("res://").path_join("../webclient").simplify_path()
	var zip_path := "user://pruef_e1/web.zip"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://pruef_e1"))
	var z := ZIPPacker.new()
	z.open(zip_path)
	print("Zip-Dateien: ", add_dir(z, web, ""))
	z.close()
	session = NetHostSession.new()
	session.auto_poll = false
	session.use_discovery = false
	session.web_zip_path = zip_path
	var cfg := RuleConfig.preset(OS.get_environment("PRUEF_PRESET")) if OS.get_environment("PRUEF_PRESET") != "" else RuleConfig.new()
	var extra := OS.get_environment("PRUEF_RULES")
	if extra != "":
		var d = JSON.parse_string(extra)
		if d is Dictionary:
			cfg.apply_dict(d)
	session.log_line.connect(func(t: String):
		logs.append(t)
		print("LOG: ", t.left(400)))
	session.player_joined.connect(func(id: int):
		if session.player(id).get("kind") == "web":
			web_ids.append(id))
	session.player_left.connect(func(id: int):
		if game != null and web_seat(id) >= 0:
			game.set_connected(web_seat(id), false)
			send_state([]))
	session.player_rejoined.connect(func(id: int):
		rejoins += 1
		if game != null and web_seat(id) >= 0:
			game.set_connected(web_seat(id), true)
			send_state([]))
	session.message.connect(func(id: int, msg: Dictionary):
		if str(msg.get("t")) != "act" or game == null:
			print("MSG ", id, ": ", JSON.stringify(msg).left(200))
			return
		var s := web_seat(id)
		var r := game.apply(s, msg.a)
		web_acts += 1
		print("ACT web seat %d: %s -> %s %s" % [s, JSON.stringify(msg.a), "ok" if r.ok else "ABGELEHNT", r.reason])
		if not r.ok:
			errs += 1
			session.send_to(id, {"t": "err", "text": r.reason})
			return
		send_state(r.events, id, int(msg.get("seq", -1))))
	if session.start("Prüfhost", port, port) != OK:
		print("FAIL: Server startet nicht")
		quit(1)
		return
	session.set_rules(cfg.to_dict())
	for i in env_int("PRUEF_BOTS", 2):
		session.add_local_player("Bot%d" % (i + 1), "bot")
	print("SERVER-BEREIT ", session.port())
	var end := Time.get_ticks_msec() + seconds * 1000
	var next_bot := 0
	var rng_n := 1
	var round_over_at := -1
	var lost_since := -1
	var played := false
	while Time.get_ticks_msec() < end:
		session.poll()
		var now := Time.get_ticks_msec()
		if game == null:
			if not beendet and not web_ids.is_empty() and session.all_ready():
				seat_ids = session.ordered_ids()
				var pl: Array = []
				for id in seat_ids:
					var p := session.player(id)
					pl.append({"name": p.name, "kind": "bot" if p.local else "human"})
				game = MauGame.create(cfg, pl, 4711)
				session.send_start()
				send_state(game.start_round())
				next_bot = now + 1500
				played = true
				print("PARTIE: ", JSON.stringify(pl))
		elif now >= next_bot:
			next_bot = now + takt
			var ph := game.phase()
			if ph == "round_over" or ph == "game_over":
				if round_over_at < 0:
					round_over_at = now
				elif now - round_over_at > 5000:
					round_over_at = -1
					if ende_lobby == 1 or ph == "game_over":
						print("PARTIE-ENDE: zurück in die Lobby")
						game = null
						beendet = true
						session.set_running(false)
						ende_lobby = 0
					else:
						var r := game.apply(0, {"a": "next_round"})
						print("next_round: ", r.ok, " ", r.reason)
						if r.ok:
							send_state(r.events)
			else:
				for s in seat_ids.size():
					if not session.player(seat_ids[s]).local:
						continue
					var a := MauBot.choose(game.view_for(s), rng_n, 1)
					rng_n += 1
					if a.is_empty():
						continue
					var r := game.apply(s, a)
					if r.ok:
						send_state(r.events)
					else:
						print("Bot ", s, " abgelehnt: ", JSON.stringify(a), " ", r.reason)
					break
		if trennen > 0 and not getrennt_getan and web_acts >= trennen and not web_ids.is_empty():
			getrennt_getan = true
			var p := session.player(web_ids[0])
			print("TRENNE Verbindung ", p.conn, " hart")
			session.server.close_ws(int(p.conn), NetWs.CLOSE_GOING_AWAY, "Prüfer")
		# Ende, wenn der Browser nach dem Spiel länger weg ist
		var any_conn := web_ids.any(func(id): return bool(session.player(id).get("connected", false)))
		if played and not any_conn:
			if lost_since < 0:
				lost_since = now
			elif now - lost_since > 12000:
				print("Browser seit 12 s weg – Ende")
				break
		else:
			lost_since = -1
		OS.delay_msec(5)
	print("STATS: web_acts=%d errs=%d states=%d rejoins=%d phase=%s" % [web_acts, errs, states, rejoins, game.phase() if game != null else "-"])
	session.stop()
	session.free()
	print("RESULT: 1 ok")
	quit(0)
