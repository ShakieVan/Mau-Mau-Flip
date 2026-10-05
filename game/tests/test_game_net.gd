extends SceneTree

# Modul G, HostTable + ClientTable über 127.0.0.1 (TCP 24890/24891): Lobby mit Computergegner und Sitzordnung (Gastgeber nicht auf
# Platz 0), Start, eine ganze Runde (Gäste spielen per MauBot auf ihrer Sicht, der Gastgeber ebenso), Lecktest auf allen
# empfangenen Nachrichten, Fehlaktionen (nicht dran, fremde Karte, next_round vom Gast), Trennen und Wiederkommen mit Token
# (Spiel wartet, Hinweis an alle), Ersatz-Bot, nächste Runde durch den Gastgeber, Versionsablehnung mit /apk-Hinweis,
# Speicherstand und Fortsetzen samt Token, Ende mit „bye“.

const PORT := 24890
const PORT2 := 24891
const SAVE := "user://test_game_netz.json"

var failures := 0
var checks := 0
var host: HostTable
var tables: Array = []                   # ClientTables
var received := {}                       # ClientTable -> Anzahl Stände
var leaks := []
var notes := {}                          # ClientTable -> [Texte]
var host_notes: Array = []
var rng := RandomNumberGenerator.new()
var acted := {}                          # Tisch -> view_rev der letzten eigenen Aktion
var acted_ms := {}                       # Tisch -> Zeitpunkt der letzten eigenen Aktion
var host_states := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)


func _initialize() -> void:
	rng.seed = 2024
	TableSource.clear_saved(SAVE)
	test_game()
	test_resume()
	for c in tables:
		c.leave()
		c.free()
	TableSource.clear_saved(SAVE)
	print("RESULT: %d ok" % checks if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)


# ---------- Hilfen ----------

func new_host(port: int) -> HostTable:
	var h := HostTable.new()
	h.auto_process = false
	h.speed = 0.0
	h.use_discovery = false
	h.save_path = SAVE
	h.notice.connect(func(t: String) -> void: host_notes.append(t))
	h.state_changed.connect(func(_e: Array, _v: Dictionary) -> void: host_states += 1)
	check(h.open("Gastgeberin", port, port) == OK and h.port() == port, "Gastgeber eröffnet auf %d" % port)
	return h


func new_client(player_name: String, port := PORT, token := "") -> ClientTable:
	var c := ClientTable.new()
	c.auto_process = false
	c.reuse_token = false
	c.persist_tokens = false
	c.retry_ms = [150, 300, 600, 800]
	c.ping_ms = 300
	received[c] = 0
	notes[c] = []
	c.notice.connect(func(t: String) -> void: notes[c].append(t))
	c.state_changed.connect(func(ev: Array, v: Dictionary) -> void:
		received[c] += 1
		check_message(c, ev, v))
	tables.append(c)
	c.join("127.0.0.1", port, player_name, token)
	return c


func pump(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while true:
		step()
		if Time.get_ticks_msec() >= end:
			break
		OS.delay_msec(1)


func step() -> void:
	if host != null:
		host.pump()
	for c in tables:
		if c.client != null:
			c.pump()


func wait_until(cond: Callable, ms := 4000) -> bool:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		pump(2)
		if cond.call():
			return true
	return cond.call()


func sorted_ints(a: Array) -> Array:
	var out: Array = []
	for x in a:
		out.append(int(x))
	out.sort()
	return out


# Lecktest je empfangener Nachricht: nur die eigene Sicht, keine fremden Gesichter, kein Seed.
func check_message(c: ClientTable, events: Array, view: Dictionary) -> void:
	var seat := int(view.get("seat", -1))
	var bad := ""
	if seat < 0:
		bad = "Sicht ohne Platz"
	for p in view.get("players", []):
		if (p as Dictionary).has("hand") or (int(p.seat) == seat and not (p.backs as Array).is_empty()):
			bad = "fremde Hand/eigene Rückseiten in players"
	for e in events:
		var d: Dictionary = e
		if str(d.get("e", "")) == "draw" and int(d.seat) != seat and (d.has("faces") or d.has("cards")):
			bad = "fremde gezogene Karten"
		if str(d.get("e", "")) == "challenge" and int(d.seat) != seat and d.has("hand"):
			bad = "fremde Hand beim Anzweifeln"
	var text := JSON.stringify(view) + JSON.stringify(events)
	if text.contains("rng_state") or text.contains("\"snap\"") or text.contains("\"seed\""):
		bad = "Seed/Zufallszustand"
	# Ist der Stand aktuell (gleiche rev wie beim Gastgeber), muss die Hand genau der echten entsprechen.
	if host != null and host.game != null and c.last_rev == host.rev and seat >= 0 and seat < host.game.hands.size():
		var mine: Array = []
		for item in view.hand:
			mine.append(int(item.id))
		mine.sort()
		if mine != sorted_ints(host.game.hands[seat]):
			bad = "Hand passt nicht zum Gastgeber"
	if bad != "":
		leaks.append("%s (Platz %d)" % [bad, seat])


# Jeder Tisch (Gäste und Gastgeber) handelt höchstens einmal je neuem Stand, per MauBot auf der eigenen Sicht.
# Gäste höchstens alle 70 ms (der Server verwirft mehr als 20 Nachrichten/s still); bleibt der Stand 1 s gleich, noch einmal.
func play_once(t: TableSource, rev_now: int) -> void:
	var now := Time.get_ticks_msec()
	var last_ms: int = acted_ms.get(t, 0)
	if acted.get(t, -1) == rev_now and now - last_ms < 1000:
		return
	if t is ClientTable and now - last_ms < 70:
		return
	var v := t.current_view()
	if v.is_empty():
		return
	acted[t] = rev_now
	acted_ms[t] = now
	var a := MauBot.choose(v, rng.randi(), 1)
	if not a.is_empty():
		t.act(a)


func play_step(skip: ClientTable = null) -> void:
	step()
	for c in tables:
		if c.client != null and c != skip and c.connection_state() == "open":
			play_once(c, c.view_rev)
	play_once(host, host_states)


func seat_of(c: ClientTable) -> int:
	return host.session.seat_of(c.my_id)


# ---------- Partie ----------

func test_game() -> void:
	host = new_host(PORT)
	var lobbies := []
	host.lobby_changed.connect(func(l: Dictionary) -> void: lobbies.append(l))
	var bot_id := host.add_bot()
	check(bot_id > 0 and str(host.session.player(bot_id).kind) == "bot", "Lobby: Computergegner hinzugefügt")
	var extra := host.add_bot("Weg")
	host.remove_player(extra)
	check(not host.session.players.has(extra), "Lobby: Computergegner entfernt")
	var anna := new_client("Anna")
	var ben := new_client("Ben")
	var c_lobby := [0]
	anna.lobby_changed.connect(func(_l: Dictionary) -> void: c_lobby[0] += 1)
	check(wait_until(func(): return anna.connection_state() == "open" and ben.connection_state() == "open" and host.session.players.size() == 4),
		"Lobby: zwei Gäste angenommen")
	check(wait_until(func(): return (anna.lobby.get("players", []) as Array).size() == 4), "Lobby: Gast sieht vier Spieler")
	check(not lobbies.is_empty() and c_lobby[0] > 0, "Lobby: lobby_changed bei Gastgeber und Gast")
	check(host.host_urls() is Array, "host_urls() liefert eine Liste (%s)" % str(host.host_urls()))
	# Version falsch → abgelehnt mit /apk-Hinweis
	var old := ClientTable.new()
	old.auto_process = false
	old.reuse_token = false
	old.persist_tokens = false
	var old_state := []
	var old_notes := []
	old.connection_changed.connect(func(s: String) -> void: old_state.append(s))
	old.notice.connect(func(t: String) -> void: old_notes.append(t))
	old.join("127.0.0.1", PORT, "Alt")
	old.client.hello_override = {"game": "0.0.9"}
	var end := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < end and not old_state.has("rejected"):
		host.pump()
		old.pump()
		OS.delay_msec(2)
	check(old_state.has("rejected") and not old_state.has("closed"), "Version: connection_changed rejected (%s)" % str(old_state))
	check(not old_notes.is_empty() and str(old_notes[0]).contains("/apk"), "Version: Hinweis mit /apk (%s)" % str(old_notes))
	old.leave()
	old.free()
	# Sitzordnung: Ben, Gastgeberin, Bot, Anna → Gastgeber auf Platz 1
	check(host.set_seat_order([ben.my_id, host.session.host_id, bot_id, anna.my_id]), "Lobby: Sitzordnung gesetzt")
	check(not host.set_seat_order([999]), "Lobby: ungültige Sitzordnung abgelehnt")
	var cfg := RuleConfig.preset("offiziell")
	host.set_rules(cfg)
	var started := []
	anna.game_started.connect(func(s: int) -> void: started.append(["anna", s]))
	ben.game_started.connect(func(s: int) -> void: started.append(["ben", s]))
	check(host.start(777), "Start")
	check(host.local_seat() == 1 and host.host_seat == 1 and bool(host.seats[1].host), "Start: Gastgeber auf Platz 1 mit host:true")
	check(TableSource.has_saved(SAVE), "Start: Speicherstand geschrieben")
	check(wait_until(func(): return received[anna] > 0 and received[ben] > 0), "Start: beide Gäste bekommen state")
	check(started.has(["anna", 3]) and started.has(["ben", 0]), "Start: start mit Platz (%s)" % str(started))
	check(anna.local_seat() == 3 and ben.local_seat() == 0, "Start: local_seat der Gäste")
	check(host.lobby().get("t") == "lobby", "Lobby-Nachricht auch während der Partie abrufbar")
	# Fehlaktionen
	await_turn_not(anna)
	var n0: int = notes[anna].size()
	var foreign: int = int(host.game.hands[0][0])     # Karte aus Bens Hand
	anna.act({"a": "play", "card": foreign})
	check(wait_until(func(): return notes[anna].size() > n0), "Fehlaktion: fremde Karte bzw. nicht dran → err")
	n0 = notes[anna].size()
	anna.act({"a": "next_round"})
	check(wait_until(func(): return notes[anna].size() > n0) and str(notes[anna].back()).length() > 3, "Fehlaktion: next_round vom Gast → err (%s)" % str(notes[anna].back() if not notes[anna].is_empty() else ""))
	# Spielen bis Anna dran ist, dann trennt sie sich
	var guard := 0
	var t_end := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < t_end and not (host.game.current_seat() == 3 and host.game.phase() in MauGame.PLAY_PHASES):
		guard += 1
		play_step(anna)
		if host.game.phase() == "round_over":
			break
	if host.game.current_seat() == 3:
		var token := anna.token
		check(token.length() == NetProtocol.TOKEN_LENGTH, "Token bekannt")
		var anna_id := anna.my_id
		var ben_notes_before: int = notes[ben].size()
		anna.leave()
		check(wait_until(func(): return not bool(host.game.connected[3])), "Trennen: Gastgeber merkt es, Platz bleibt")
		check(wait_until(func(): return notes[ben].size() > ben_notes_before and str(notes[ben].back()).contains("getrennt")),
			"Trennen: Hinweis an die anderen (%s)" % str(notes[ben].slice(ben_notes_before)))
		check(str(host.current_view().hints.text).contains("getrennt"), "Trennen: Hinweistext beim Gastgeber")
		var rev_before := host.rev
		pump(150)
		for i in 50:
			play_step(anna)
		check(host.game.current_seat() == 3 and host.rev == rev_before, "Trennen: Spiel wartet auf Anna")
		var anna2 := new_client("Anna", PORT, token)
		check(wait_until(func(): return anna2.connection_state() == "open" and received[anna2] > 0), "Wiederkommen: sofort state")
		check(anna2.my_id == anna_id and anna2.local_seat() == 3 and bool(host.game.connected[3]), "Wiederkommen: gleiche id und gleicher Platz")
		anna = anna2
	else:
		check(false, "Anna kam nicht an die Reihe")
	# Rest der Runde
	guard = 0
	t_end = Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < t_end and host.game.phase() != "round_over":
		guard += 1
		play_step()
	check(host.game.phase() == "round_over", "Runde zu Ende gespielt (%d Schritte)" % guard)
	print("  Runde 1: %d ms, Server verwarf %s Nachrichten (Rate); Hinweise Anna %s, Ben %s" % [90000 - (t_end - Time.get_ticks_msec()),
		str(host.session.server.stats().get("rate_dropped", "?")), str(notes[anna]), str(notes[ben])])
	if host.game.phase() != "round_over":
		print("  Stand: Phase %s, am Zug %d, verbunden %s, rev %d, Anna rev %d (%s), Ben rev %d (%s), Hinweis „%s“" % [host.game.phase(),
			host.game.current_seat(), str(host.game.connected), host.rev, anna.last_rev, anna.connection_state(), ben.last_rev,
			ben.connection_state(), str(host.current_view().hints.text)])
	check(wait_until(func(): return anna.last_rev == host.rev and ben.last_rev == host.rev), "Gäste haben den Endstand")
	check(not bool(anna.current_view().hints.can_next_round) and bool(host.current_view().hints.can_next_round),
		"Rundenende: nur der Gastgeber darf weiterschalten")
	var n1: int = notes[ben].size()
	ben.act({"a": "next_round"})
	check(wait_until(func(): return notes[ben].size() > n1) and host.game.phase() == "round_over", "Rundenende: next_round vom Gast abgelehnt")
	host.act({"a": "next_round"})
	check(host.game.round_no == 2 and host.game.phase() in MauGame.PLAY_PHASES, "Gastgeber startet Runde 2")
	check(wait_until(func(): return int(anna.current_view().get("round", 0)) == 2 and int(ben.current_view().get("round", 0)) == 2),
		"Runde 2 bei den Gästen")
	# Ersatz-Bot für einen getrennten Gast
	var ben_seat := seat_of(ben)
	ben.leave()
	check(wait_until(func(): return not bool(host.game.connected[ben_seat])), "Ben getrennt")
	host.substitute_bot(ben_seat)
	check(host.is_bot(ben_seat), "Ersatz-Bot übernimmt Bens Platz")
	guard = 0
	var ben_turns := [0]
	var count_ben := func(ev: Array, _v: Dictionary) -> void:
		for e in ev:
			if str(e.get("e", "")) in ["play", "draw", "pass", "keep", "accept", "challenge"] and int(e.get("seat", -1)) == ben_seat:
				ben_turns[0] += 1
	host.state_changed.connect(count_ben)
	t_end = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < t_end and host.game.phase() != "round_over" and ben_turns[0] < 3:
		guard += 1
		play_step()
	host.state_changed.disconnect(count_ben)
	check(ben_turns[0] >= 1 or host.game.phase() == "round_over", "Ersatz-Bot spielt für Ben (%d Handlungen)" % ben_turns[0])
	check(leaks.is_empty(), "Lecktest: alle empfangenen Nachrichten privat (%s)" % str(leaks.slice(0, 3)))
	check(received[anna] > 20, "Lecktest: genug Nachrichten geprüft (Anna %d)" % received[anna])
	# Speicherstand für den Fortsetzen-Test aufheben
	var data := TableSource.load_saved(SAVE)
	check(str(data.get("mode", "")) == "host" and (data.seats as Array).size() == 4, "Speicherstand: Gastgeber-Partie mit 4 Plätzen")
	saved_for_resume = data
	saved_anna_token = anna.token
	# Ende: bye an alle
	# (Im Test laufen Gastgeber und Gast im selben Thread: erst „bye“ nicht blockierend verteilen, dann aufräumen.)
	var closed_notes: int = notes[anna].size()
	host.autosave = false
	host.session.finish("Der Gastgeber hat das Spiel beendet.")
	check(wait_until(func(): return anna.connection_state() == "closed", 3000), "Gast bekommt bye → closed")
	check(notes[anna].size() > closed_notes and str(notes[anna].back()).contains("beendet"),
		"Gast: Hinweis beim Beenden (%s)" % str(notes[anna].slice(closed_notes)))
	host.leave()
	check(host.session == null, "Gastgeber beendet")
	host.free()
	host = null


var saved_for_resume := {}
var saved_anna_token := ""


func await_turn_not(c: ClientTable) -> void:
	# Fehlaktions-Test braucht einen Stand, in dem Anna nicht dran ist (sonst wäre „nicht dran“ kein Fehler).
	var t_end := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < t_end and host.game.current_seat() == seat_of(c):
		play_step()


func test_resume() -> void:
	if saved_for_resume.is_empty():
		check(false, "Fortsetzen: kein Speicherstand")
		return
	host = HostTable.new()
	host.auto_process = false
	host.speed = 0.0
	host.use_discovery = false
	host.save_path = SAVE
	host.state_changed.connect(func(_e: Array, _v: Dictionary) -> void: host_states += 1)
	check(host.resume(saved_for_resume, PORT2, PORT2) == OK, "Fortsetzen: resume")
	var anna_seat := -1
	for s in host.seats.size():
		if str(host.seats[s].name) == "Anna":
			anna_seat = s
	check(anna_seat >= 0 and not bool(host.game.connected[anna_seat]), "Fortsetzen: Gast erst getrennt")
	check(host.game.round_no == 2 and host.session.running, "Fortsetzen: Runde 2 läuft weiter")
	var a3 := new_client("Anna", PORT2, saved_anna_token)
	check(wait_until(func(): return a3.connection_state() == "open" and received[a3] > 0), "Fortsetzen: Gast kommt mit Token zurück")
	check(a3.local_seat() == anna_seat and bool(host.game.connected[anna_seat]), "Fortsetzen: gleicher Platz")
	var stranger := new_client("Neu", PORT2)
	var st := []
	stranger.connection_changed.connect(func(s: String) -> void: st.append(s))
	check(wait_until(func(): return st.has("rejected")), "Fortsetzen: Neue ohne Token abgelehnt (running)")
	check(HostTable.has_saved(SAVE) and LocalTable.load_saved(SAVE).get("mode") == "host", "Speicherstand über Unterklassen abrufbar")
	# Ben kommt nicht zurück: mit auto_substitute_s übernimmt nach der Wartezeit ein Bot
	var ben_seat := -1
	for s in host.seats.size():
		if str(host.seats[s].name) == "Ben":
			ben_seat = s
	host.auto_substitute_s = 0.2
	var end := Time.get_ticks_msec() + 8000
	var waited := false
	while Time.get_ticks_msec() < end:
		play_step()
		if host.game.phase() == "round_over":
			host.act({"a": "next_round"})
		if host.game.current_seat() == ben_seat and not host.is_bot(ben_seat):
			waited = true
		if host.is_bot(ben_seat) and host.game.current_seat() != ben_seat:
			break
		OS.delay_msec(1)
	check(waited and host.is_bot(ben_seat), "Auto-Ersatz: nach der Wartezeit spielt ein Bot für Ben")
	host.autosave = false
	host.leave()
	host.free()
	host = null
