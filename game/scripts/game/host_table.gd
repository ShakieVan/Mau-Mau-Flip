class_name HostTable
extends GameTable
# Netzwerkspiel, Gastgeber-Seite (Modul G): Lobby und Partie über NetHostSession (Modul D), Regelwerk und Computergegner laufen hier.
#
# Lobby: Gastgeber = erster Spieler (Name aus App.settings), App- und Browser-Gäste melden sich über den NetServer an (Port 24690…),
# Computergegner hinzufügen/entfernen, Sitzordnung (Liste von Spieler-ids), Regeln. start() erzeugt MauGame in dieser Sitzordnung,
# der Gastgeber-Platz bekommt host:true (nur er darf „next_round“).
# Partie: Nach jeder Änderung bekommt jeder verbundene Gast {t:"state", rev, seq_ack?, events: events_for(seat), view: view_for(seat)},
# der Gastgeber selbst state_changed. Aktionen der Gäste ({t:"act"}) gelten immer für den Platz des Absenders; Ablehnung als
# {t:"err", text}. Getrennte Spieler behalten ihren Platz; ist ein getrennter Mensch am Zug, wartet das Spiel (Hinweis an alle).
# substitute_bot(seat) lässt einen Bot für ihn spielen (auto_substitute_s > 0: automatisch nach so vielen Sekunden). Wer mit
# seinem Token zurückkommt, bekommt sofort den aktuellen Stand und spielt selbst weiter.
# Speicherstand nach jeder Änderung (user://laufende_partie.json), resume() setzt eine Partie samt Token der Gäste fort.

const BOT_NAMES := ["Minka", "Mogli", "Luna", "Tiger", "Socke", "Krümel", "Flocke", "Pünktchen", "Schnurri", "Mieze"]

var session: NetHostSession
var rules := RuleConfig.new()
var use_discovery := true
var discovery_port := NetProtocol.DISCOVERY_PORT
var web_zip_path := "res://assets/web.zip"
var threaded := true             # Netz-Thread des Servers (Modul D)
var auto_substitute_s := 0.0     # 0 = warten (Standard); > 0: Bot übernimmt einen getrennten Menschen am Zug nach so vielen s

var _seat_ids: Array = []        # Platz -> Spieler-id der Sitzung
var _seq := {}                   # Spieler-id -> letzte seq seiner Aktionen (seq_ack)
var _waiting_seat := -1          # getrennter Mensch am Zug
var _wait_since := 0


# Lobby eröffnen. host_name "" = Name aus den Einstellungen.
func open(host_name := "", port_first := NetProtocol.PORT, port_last := NetProtocol.PORT_LAST) -> Error:
	_close_session()
	session = NetHostSession.new()
	session.name = "Sitzung"
	session.auto_poll = false
	session.use_discovery = use_discovery
	session.discovery_port = discovery_port
	session.web_zip_path = web_zip_path
	session.apk_provider = _apk_info
	add_child(session)
	session.player_left.connect(_on_left)
	session.player_rejoined.connect(_on_rejoined)
	session.message.connect(_on_message)
	session.lobby_changed.connect(func() -> void: lobby_changed.emit(session.lobby_message()))
	var err := session.start(host_name if host_name != "" else _own_name(), port_first, port_last, threaded)
	if err != OK:
		_close_session()
		notice.emit(I18n.t("Das Spiel ließ sich nicht eröffnen (Port %d–%d belegt?).") % [port_first, port_last])
		return err
	session.set_rules(rules.to_dict())
	return OK


func mode() -> String:
	return "host"


func local_seat() -> int:
	return host_seat if game != null else (session.seat_of(session.host_id) if session != null else -1)


func port() -> int:
	return session.port() if session != null else 0


# Adressen für QR-Code und Text, beste zuerst, z. B. "http://192.168.178.8:24690/".
func host_urls() -> Array[String]:
	var out: Array[String] = []
	if session != null:
		for u in NetAddresses.urls(session.port()):
			out.append(str(u))
	return out


func lobby() -> Dictionary:
	return session.lobby_message() if session != null else {}


func is_running() -> bool:
	return game != null


# --- Lobby ---

func add_bot(bot_name := "") -> int:
	if session == null or game != null:
		return -1
	if bot_name == "":
		var taken: Array = session.players.values().map(func(p): return str(p.name))
		for n in BOT_NAMES:
			if not taken.has(n):
				bot_name = n
				break
	return session.add_local_player(bot_name if bot_name != "" else "Computer", "bot")


# Spieler entfernen. Während der Partie übernimmt stattdessen ein Bot den Platz.
func remove_player(id: int) -> void:
	if session == null or id == session.host_id:
		return
	if game != null:
		var s := _seat_ids.find(id)
		if s >= 0:
			substitute_bot(s)
		return
	session.remove_player(id)


func set_seat_order(ids: Array) -> bool:
	return session != null and game == null and session.set_seat_order(ids)


func set_rules(cfg: RuleConfig) -> void:
	rules = cfg.duplicate_config()
	if session != null:
		session.set_rules(rules.to_dict())


# Partie beginnen (mindestens zwei Spieler). false = nicht möglich (Hinweis kommt als notice).
func start(rng_seed := 0) -> bool:
	if session == null:
		return false
	if session.players.size() < 2:
		notice.emit("Es braucht mindestens zwei Spieler.")
		return false
	_seat_ids = session.ordered_ids()
	var list: Array = []
	for id in _seat_ids:
		var p: Dictionary = session.player(id)
		list.append({"name": str(p.name), "kind": "bot" if str(p.kind) == "bot" else "human", "host": id == session.host_id,
			"id": id, "net": str(p.kind), "token": str(p.token)})
	_create_game(rules, list, rng_seed)
	for s in _seat_ids.size():
		game.set_connected(s, bool(session.player(_seat_ids[s]).connected))
	_seq.clear()
	_waiting_seat = -1
	session.send_start()
	game_started.emit(host_seat)
	_begin_round()
	return true


# Partie fortsetzen (Daten aus TableSource.load_saved()): Sitzung neu eröffnen, Gäste mit ihren Token eintragen (getrennt, bis sie
# zurückkommen), Computergegner neu anlegen.
func resume(data: Dictionary, port_first := NetProtocol.PORT, port_last := NetProtocol.PORT_LAST) -> Error:
	if str(data.get("mode", "")) != "host" or not data.get("game") is Dictionary:
		return ERR_INVALID_DATA
	var saved: Array = data.get("seats", [])
	var hs := int(data.get("host_seat", 0))
	var host_name := str(saved[hs].name) if hs >= 0 and hs < saved.size() else ""
	rules = RuleConfig.from_dict((data.game as Dictionary).get("config", {}))
	var err := open(host_name, port_first, port_last)
	if err != OK:
		return err
	_restore_seats(data)
	var ids: Array = []
	for s in seats.size():
		var p: Dictionary = seats[s]
		var id := -1
		if s == host_seat:
			id = session.host_id
		elif str(p.kind) == "bot":
			id = session.add_local_player(str(p.name), "bot")
		else:
			id = _restore_guest(p)
		p.id = id
		ids.append(id)
	session.set_seat_order(ids)
	_seat_ids = ids
	game = MauGame.from_dict(data.game)
	for s in seats.size():
		game.set_connected(s, s == host_seat or str(seats[s].kind) == "bot")
	session.set_running(true)
	_plan_dirty = true
	game_started.emit(host_seat)
	_changed([])
	return OK


# Ein Computergegner spielt für diesen Platz, bis der Mensch zurückkommt bzw. selbst wieder handelt.
func substitute_bot(seat: int) -> void:
	if game == null or seat < 0 or seat >= seats.size() or seat == host_seat or is_bot(seat):
		return
	_substitute[seat] = true
	_waiting_seat = -1
	_tell_all([I18n.part("Ein Computergegner spielt für %s.", [seat_name(seat)])])
	_changed([])


# Getrennte Gäste ohne Vertretung (Knopf „Computer spielt für …“ am Tisch des Gastgebers)
func substitutable_seats() -> Array:
	var out: Array = []
	if game == null:
		return out
	for s in seats.size():
		if _is_remote(s) and not _substitute.has(s) and not bool(game.connected[s]):
			out.append(s)
	return out


# Getrennter Mensch, auf dessen Zug das Spiel wartet (−1 = keiner)
func waiting_seat() -> int:
	return _waiting_seat


func is_substituted(seat: int) -> bool:
	return _substitute.has(seat)


func act(action: Dictionary) -> void:
	if game == null:
		notice.emit("Die Partie hat noch nicht begonnen.")
		return
	var r := _apply(host_seat, action)
	if not bool(r.ok):
		notice.emit(I18n.reason(r))


# Zurück in die Lobby (Partie verwerfen, Spieler bleiben).
func back_to_lobby() -> void:
	game = null
	_plan = {}
	_substitute.clear()
	if session != null:
		session.set_running(false)
	if autosave:
		clear_saved(save_path)


func leave() -> void:
	_close_session()
	if autosave:
		clear_saved(save_path)


func _close_session() -> void:
	game = null
	_plan = {}
	_substitute.clear()
	if session != null:
		session.stop("Der Gastgeber hat das Spiel beendet.")
		if session.is_inside_tree():
			session.queue_free()
		else:
			session.free()
		session = null


# --- intern ---

func _poll_extra() -> void:
	if session != null:
		session.poll()


func _bots_paused() -> bool:
	return session == null


func _pre_step() -> bool:
	if auto_substitute_s > 0.0 and _waiting_seat >= 0 and Time.get_ticks_msec() - _wait_since > int(auto_substitute_s * 1000.0):
		substitute_bot(_waiting_seat)
		return true
	return false


func _is_remote(seat: int) -> bool:
	return seat >= 0 and seat < seats.size() and seat != host_seat and str(seats[seat].kind) != "bot"


func _after_change() -> void:
	var cur := game.current_seat()
	if cur >= 0 and _is_remote(cur) and not _substitute.has(cur) and not bool(game.connected[cur]):
		if _waiting_seat != cur:
			_waiting_seat = cur
			_wait_since = Time.get_ticks_msec()
			_tell_all([I18n.part("%s ist getrennt – warte …", [seat_name(cur)])])
	else:
		_waiting_seat = -1


func _patch_view(seat: int, v: Dictionary) -> void:
	if _waiting_seat >= 0 and seat != _waiting_seat:
		(v.hints as Dictionary).text = "%s ist getrennt – warte …" % seat_name(_waiting_seat)
		(v.hints as Dictionary).lt = [I18n.part("%s ist getrennt – warte …", [seat_name(_waiting_seat)])]


func _distribute(events: Array) -> void:
	for s in seats.size():
		if s == host_seat:
			_last_view = view_of(s)
			state_changed.emit(game.events_for(s, events), _last_view)
		elif _is_remote(s) and bool(game.connected[s]):
			_send_state(s, events)


func _send_state(seat: int, events: Array) -> void:
	var id: int = _seat_ids[seat]
	var msg := {"t": "state", "rev": rev, "events": game.events_for(seat, events), "view": view_of(seat)}
	if _seq.has(id):
		msg.seq_ack = _seq[id]
	session.send_to(id, msg)


# Meldung an alle: lt = Bausteine (I18n), jedes Gerät zeigt sie in seiner Sprache; "text" bleibt deutsch für ältere Geräte.
func _tell_all(lt: Array) -> void:
	notice.emit(I18n.render(lt))
	if session != null:
		session.broadcast(I18n.with_lt({"t": "notice"}, lt))


func _on_left(id: int) -> void:
	if game == null:
		return
	var s := _seat_ids.find(id)
	if s < 0:
		return
	game.set_connected(s, false)
	notice.emit(I18n.t("%s ist getrennt.") % seat_name(s))
	_changed([])


func _on_rejoined(id: int) -> void:
	if game == null:
		return
	var s := _seat_ids.find(id)
	if s < 0:
		return
	game.set_connected(s, true)
	if _substitute.has(s):
		_substitute.erase(s)
	notice.emit(I18n.t("%s ist wieder da.") % seat_name(s))
	_changed([])                 # schickt allen (auch dem Zurückgekehrten) sofort den aktuellen Stand


func _on_message(id: int, msg: Dictionary) -> void:
	if str(msg.get("t", "")) != "act":
		return
	if msg.get("seq") is int:
		_seq[id] = int(msg.seq)
	var a: Dictionary = msg.get("a", {}) if msg.get("a") is Dictionary else {}
	if game == null:
		_err(id, "Die Partie hat noch nicht begonnen.")
		return
	var s := _seat_ids.find(id)
	if s < 0:
		_err(id, "Du sitzt nicht mit am Tisch.")
		return
	if str(a.get("a", "")) == "next_round" and id != session.host_id:
		_err(id, "Die nächste Runde startet der Gastgeber.")
		return
	if _substitute.has(s) and str(a.get("a", "")) != "":
		_substitute.erase(s)    # der Mensch spielt wieder selbst
		_plan_dirty = true
	var r := _apply(s, a)
	if not bool(r.ok):
		_err(id, str(r.reason), r.get("reason_lt", []))


func _err(id: int, text: String, lt: Array = []) -> void:
	var msg := {"t": "err", "text": text}
	if not lt.is_empty() and not (lt.size() == 1 and lt[0] is String):   # Bausteine nur bei Platzhaltern (sonst ist text die msgid)
		msg["lt"] = lt
	if _seq.has(id):
		msg.seq_ack = _seq[id]
	session.send_to(id, msg)


func _restore_guest(p: Dictionary) -> int:
	# Gast mit Token wieder eintragen (NetHostSession hat dafür keine eigene Funktion; Felder wie in _hello).
	var id: int = session._next_id
	session._next_id += 1
	session.players[id] = {"id": id, "name": str(p.name), "kind": str(p.get("net", "app")), "token": str(p.get("token", "")),
		"connected": false, "ready": true, "seat": session._next_seat(), "conn": -1, "local": false, "address": ""}
	return id


func _save_extra() -> Dictionary:
	return {"port": port()}


func _apk_info() -> Dictionary:
	var app := _app()
	if app == null or app.get("apk_share") == null:
		return {"keine": true}
	var share: ApkShare = app.get("apk_share")
	return share.server_info() if share.available() else {"keine": true}


func _own_name() -> String:
	var app := _app()
	if app != null and app.get("settings") is AppSettings:
		return (app.get("settings") as AppSettings).player_name()
	return "Gastgeber"


func _app() -> Node:
	var loop := Engine.get_main_loop()
	return (loop as SceneTree).root.get_node_or_null("App") if loop is SceneTree else null
