extends SceneTree

# Mau-Mau Flip (Beta 1.6.1, Gastgeber-Übergabe): Sicherung, Fortsetzen durch den Gastgeber, Einfrieren und Abtreten
# (docs/module/uebergabe.md Abschnitte 2, 4.1, 4.5, 7) – HostTable mit ClientTables über den Vermittler-Nachbau (NetRelayDouble,
# TCP 24973) bzw. im WLAN (24974–24979), synchron gepumpt.
#  1  Online: bk nur an App-Gäste mit hello.bk (nie an Gäste ohne bk), bk vor jeder Sicht, alive nach Stille; eigene Datei
#     (NET_SAVE_PATH-Form) mit Raum, conns, Erben. Gastgeber stürzt ab (Freigeben ohne „Tisch verlassen“): Raum bleibt offen.
#     resume() aus der Datei: gleicher Raumcode, gleicher WLAN-Port, gen/epoch bleiben, Einschwingzeit bis der Sicherungsempfänger
#     zurück ist, Gäste per Token auf ihren Plätzen. leave(): Datei weg, Raum beendet.
#  2  WLAN mit Warteliste: Fortsetzen auf demselben Port, App-Gast und Wartender finden von selbst zurück (Wartender bleibt auf der
#     Warteliste statt „reject running“), join_open bleibt; WLAN-Mitspieler sind Erben (Beta 1.6.2, keine Sperre mehr).
#  3  Geplante Übergabe ohne Antwort des Ziels: handover an das Ziel, Meldung an alle, eingefroren (Aktionen abgelehnt, keine Datei),
#     nach der Frist check_now → aufgetaut, gen unverändert. Abstammung: Gast mit jüngerem hello.bk bekommt handover own:true,
#     handover_no taut auf, kein zweiter Versuch. Übernahme durch einen anderen Gastgeber (4000): stepped_down, keine Meldung
#     „getrennt“, keine Datei mehr; handover_shutdown() → Datei role "guest", Raum bleibt; der alte Gastgeber kommt als Gast auf
#     seinen Platz zurück.

const RELAY_PORT := 24973
const HOST_PORT := 24974
const HOST_LAST := 24976
const WLAN_PORT := 24977
const TAKE_PORT := 24978
const PATH := "user://test_host_resume.json"
const PATH_B := "user://test_host_resume_b.json"

var failures := 0
var checks := 0
var relay: NetRelayDouble
var rng := RandomNumberGenerator.new()
var hosts: Array = []
var clients: Array = []
var inbox := {}            # ClientTable -> [Nachrichten des Gastgebers, roh]


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)


func _initialize() -> void:
	rng.seed = 2024
	relay = NetRelayDouble.new()
	relay.auto_poll = false
	relay.web_zip_path = ""
	check(relay.start(RELAY_PORT, RELAY_PORT) == OK, "Vermittler-Nachbau auf %d" % RELAY_PORT)
	TableSource.clear_saved(PATH)
	TableSource.clear_saved(PATH_B)
	var t0 := Time.get_ticks_msec()
	_online_resume()
	_wlan_resume()
	_frozen_and_step_down()
	print("  Dauer %d ms" % (Time.get_ticks_msec() - t0))
	for c in clients:
		if is_instance_valid(c):
			c.leave()
			c.free()
	for h in hosts:
		if is_instance_valid(h):
			h.autosave = false
			h.leave()
			h.free()
	relay.stop()
	relay.free()
	TableSource.clear_saved(PATH)
	TableSource.clear_saved(PATH_B)
	print("RESULT: %d ok" % checks if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)


# ---------- 1: online ----------

func _online_resume() -> void:
	var h := new_host(PATH)
	h.alive_ms = 300
	check(h.open("Gastgeberin", HOST_PORT, HOST_PORT) == OK, "1: Gastgeberin im WLAN")
	h.session.open_online(relay.base_url())
	check(wait_until(func(): return h.session.online_state() == "open"), "1: Online-Raum offen")
	var code := str(h.session.online_info().room)
	var link := str(h.session.online_info().link)
	var anna := new_client("Anna", link, 0, "", true)
	var ben := new_client("Ben", link, 0, "", false)
	check(wait_until(func(): return anna.my_id > 0 and ben.my_id > 0), "1: zwei App-Gäste online")
	check(h.session.backup_ids() == [anna.my_id], "1: nur Anna hat hello.bk (Sicherungsempfängerin)")
	h.add_bot("Minka")
	h.set_rules(RuleConfig.preset("offiziell"))
	check(h.start(99), "1: Start")
	check(wait_until(func(): return anna.view_rev > 0 and ben.view_rev > 0), "1: Gäste bekommen den Stand")
	check(_count(anna, "bk") > 0 and _count(ben, "bk") == 0, "1: bk an Anna (%d), nie an Ben ohne hello.bk" % _count(anna, "bk"))
	var first := MatchSnapshot.unpack(str(_last(anna, "bk").get("z", "")))
	check(not first.is_empty() and str(first.gid) == h.gid and MatchSnapshot.own_token(first) == h.host_token(), "1: Sicherung entpackbar, gleiche Partie")
	_play([h], h, 10)
	check(_bk_before_each_state(anna), "1: bk kommt vor jeder Sicht (Reihenfolge je Gast)")
	var bk := _last(anna, "bk")
	check(wait_until(func(): return int(_last(anna, "bk").get("seq", -1)) == h.seq), "1: letzte bk-Marke = Stand des Gastgebers")
	bk = _last(anna, "bk")
	check(int(bk.get("gen", 0)) == 1 and str(bk.get("epoch", "")) == h.epoch and str(bk.get("gid", "")) == h.gid, "1: bk mit gid/gen/epoch")
	# alive nach Stille (alive_ms 300): warten ohne Züge der Menschen (Computergegner ziehen bis zum nächsten Menschen)
	pump(200)
	var alive_before := _count(anna, "alive")
	var rev := h.rev
	check(wait_until(func(): return _count(anna, "alive") > alive_before, 3000) and h.rev == rev, "1: alive nach Stille")
	var al := NetProtocol.clean_backup_message(_last(anna, "alive"))
	check(not al.is_empty() and int(al.seq) == h.seq and str(al.gid) == h.gid, "1: alive mit aktueller Marke")
	check(_count(ben, "alive") == 0, "1: kein alive an Ben")
	# Eigene Datei
	var d := MatchSnapshot.read(PATH)
	check(not d.is_empty() and str(d.role) == "host" and int(d.format) == 2 and str(d.gid) == h.gid and int(d.seq) == h.seq, "1: eigene Datei aktuell (seq %d)" % int(d.get("seq", -1)))
	var o: Dictionary = d.get("online", {})
	check(str(o.get("room", "")) == code and str(o.get("token", "")) != "" and (o.get("conns", []) as Array).size() == 2, "1: Datei kennt Raum, Raum-Token und beide c")
	check(d.heirs == [anna.token] and d.bk_to == [anna.token] and not bool(d.wlan_humans), "1: Erben = Anna (Ben ohne Sicherung)")
	check(int(d.wlan.port) == HOST_PORT, "1: WLAN-Port im Stand")
	for c in [anna, ben]:
		c.client.host_away_ms = 300
	# Absturz: Freigeben ohne leave()
	var seq_before := h.seq
	var gen_before := h.gen
	var epoch_before := h.epoch
	var seats_before := {"Anna": h.session.seat_of(anna.my_id), "Ben": h.session.seat_of(ben.my_id)}
	drop(h)
	pump(300)
	check(relay.core.rooms.has(code), "1: Absturz beendet den Raum nicht")
	var h2 := new_host(PATH)
	check(h2.resume(MatchSnapshot.read(PATH), -1, HOST_PORT, HOST_LAST) == OK, "1: Fortsetzen aus der Datei")
	check(h2.port() == HOST_PORT, "1: gleicher WLAN-Port (%d)" % h2.port())
	check(h2.gen == gen_before and h2.epoch == epoch_before and h2.seq == seq_before + 1, "1: eigener Zweig – gen/epoch bleiben, seq zählt weiter")
	check(h2.is_settling(), "1: Einschwingzeit wartet auf Anna")
	check(wait_until(func(): return h2.session.online_state() == "open" and str(h2.session.online_info().room) == code), "1: gleicher Raumcode")
	var back := func() -> bool:
		var a := _seat_of_token(h2, anna.token)
		var b := _seat_of_token(h2, ben.token)
		return a >= 0 and b >= 0 and bool(h2.game.connected[a]) and bool(h2.game.connected[b])
	check(wait_until(back, 8000), "1: Gäste per Token zurück")
	check(_seat_of_token(h2, anna.token) == seats_before.Anna and _seat_of_token(h2, ben.token) == seats_before.Ben, "1: auf denselben Plätzen")
	check(wait_until(func(): return not h2.is_settling(), 2000), "1: Einschwingzeit endet, sobald Anna zurück ist")
	# Beta 1.6.2 (10.10): Fortsetzen an derselben Adresse ist kein Umzug – die Warteliste bleibt wie gespeichert (zu), Neue werden
	# mit „reject running“ abgewiesen
	check(not h2.session.join_open, "1: Warteliste bleibt zu (kein Umzug)")
	var neu := new_client("Neu", "127.0.0.1", HOST_PORT)
	var neu_st := []
	neu.connection_changed.connect(func(s: String) -> void: neu_st.append(s))
	check(wait_until(func(): return neu_st.has("rejected"), 4000), "1: Neue ohne Token abgelehnt (running) (%s)" % str(neu_st))
	neu.leave()
	var rev2 := h2.rev
	_play([h2], h2, 6)
	check(h2.rev > rev2, "1: Partie läuft nach dem Fortsetzen weiter")
	check(wait_until(func(): return anna.last_rev == h2.rev), "1: Anna hat den neuen Stand")
	h2.leave()
	check(not FileAccess.file_exists(PATH), "1: „Tisch verlassen“ löscht die Datei")
	check(wait_until(func(): return not relay.core.rooms.has(code)), "1: „Tisch verlassen“ beendet den Raum")
	drop(h2)
	for c in [anna, ben]:
		c.leave()


# ---------- 2: WLAN mit Warteliste ----------

func _wlan_resume() -> void:
	var w := new_host(PATH)
	check(w.open("Wanda", WLAN_PORT, WLAN_PORT) == OK, "2: Gastgeberin im WLAN")
	var cara := new_client("Cara", "127.0.0.1", WLAN_PORT, "", true)
	check(wait_until(func(): return cara.my_id > 0), "2: Cara im WLAN")
	w.add_bot("Minka")
	w.set_rules(RuleConfig.preset("offiziell"))
	check(w.start(5), "2: Start")
	w.set_join_open(true)
	var dora := new_client("Dora", "127.0.0.1", WLAN_PORT, "", false)
	check(wait_until(func(): return dora.waiting and w.waiting_ids().size() == 1), "2: Dora wartet")
	_play([w], w, 4)
	check(w.wlan_humans() and w.heirs() == [cara.token], "2: WLAN-Mitspieler am Tisch erben (Beta 1.6.2)")
	var d := MatchSnapshot.read(PATH)
	check((d.waiting as Array).size() == 1 and str(d.waiting[0].name) == "Dora" and str(d.waiting[0].token) == dora.token and bool(d.join_open),
		"2: Warteliste und join_open im Stand")
	check(bool(d.wlan_humans) and d.heirs == [cara.token], "2: Stand mit Erben trotz wlan_humans (Beta 1.6.2)")
	var cara_seat := w.session.seat_of(cara.my_id)
	drop(w)
	pump(200)
	var w2 := new_host(PATH)
	check(w2.resume(MatchSnapshot.read(PATH), -1, WLAN_PORT, WLAN_PORT) == OK and w2.port() == WLAN_PORT, "2: Fortsetzen auf demselben Port")
	check(w2.session.join_open, "2: join_open bleibt")
	var dora_back := func() -> bool:
		var id := w2._id_of_token(dora.token)
		return id >= 0 and w2.session.is_waiting(id) and bool(w2.session.player(id).connected)
	check(wait_until(func(): return cara.connection_state() == "open" and bool(w2.game.connected[cara_seat]), 8000), "2: Cara findet von selbst zurück")
	check(wait_until(dora_back, 8000), "2: Dora findet zurück und wartet wieder")
	# Der Gastgeber sieht Dora schon wartend, bevor ihr Gerät die Antwort verarbeitet hat (wackelte im parallelen Bau): kurz warten
	check(wait_until(func(): return dora.connection_state() == "open" and dora.waiting, 4000) and not dora.client.removed,
		"2: Dora nicht abgewiesen (%s, wartet %s, entfernt %s)" % [dora.connection_state(), dora.waiting, dora.client.removed])
	check(w2.seat_in(w2._id_of_token(dora.token), 1), "2: Dora lässt sich an den Tisch holen")
	check(wait_until(func(): return dora.view_rev > 0, 4000), "2: Dora spielt mit")
	w2.leave()
	check(not FileAccess.file_exists(PATH), "2: Verlassen löscht die Datei")
	drop(w2)
	for c in [cara, dora]:
		c.leave()


# ---------- 3: Einfrieren, Abstammung, Abtreten ----------

func _frozen_and_step_down() -> void:
	var h := new_host(PATH_B)
	h.handover_timeout_ms = 400
	var notes: Array = []
	h.notice.connect(func(t: String) -> void: notes.append(t))
	var stepped: Array = []
	h.stepped_down.connect(func(n: String) -> void: stepped.append(n))
	check(h.open("Hanna", HOST_PORT, HOST_PORT) == OK, "3: Gastgeberin")
	h.session.open_online(relay.base_url())
	check(wait_until(func(): return h.session.online_state() == "open"), "3: Online-Raum offen")
	var code := str(h.session.online_info().room)
	var link := str(h.session.online_info().link)
	var gina := new_client("Gina", link, 0, "", true)
	check(wait_until(func(): return gina.my_id > 0), "3: Gina online mit Sicherung")
	h.add_bot("Minka")
	h.set_rules(RuleConfig.preset("offiziell"))
	check(h.start(31), "3: Start")
	check(wait_until(func(): return gina.view_rev > 0), "3: Gina hat den Stand")
	var gseat := h.session.seat_of(gina.my_id)
	check(h.handover_block(gseat).is_empty(), "3: Übergabe an Gina möglich (%s)" % str(h.handover_block(gseat)))
	var bot_seat := -1
	for s in h.seats.size():
		if str(h.seats[s].kind) == "bot":
			bot_seat = s
	check(not h.handover_block(h.host_seat).is_empty() and h.handover_block(bot_seat) == ["Nur Mitspieler mit der App können Gastgeber werden."],
		"3: nicht an sich selbst und nicht an den Computer")
	# --- geplante Übergabe, das Ziel antwortet nicht
	var gen0 := h.gen
	var file0 := FileAccess.get_file_as_string(PATH_B)
	check(h.handover_to(gseat), "3: handover_to(Gina)")
	check(h.is_frozen() and h.handover_seat() == gseat, "3: eingefroren")
	check(wait_until(func(): return not _last(gina, "handover").is_empty()), "3: Gina bekommt handover")
	var ho := NetProtocol.clean_backup_message(_last(gina, "handover"))
	check(not ho.is_empty() and ho.has("z") and str(ho.gid) == h.gid and int(ho.within_ms) == NetProtocol.HANDOVER_WITHIN_MS, "3: handover mit Stand und Frist")
	check(MatchSnapshot.unpack(str(ho.get("z", ""))).get("gid", "") == h.gid, "3: Stand im handover entpackbar")
	check(_has_notice(gina, "Gastgeber wechselt zu %s …"), "3: Meldung „Gastgeber wechselt …“ an alle")
	var errs := _count(gina, "err")
	gina.act({"a": "draw"})
	check(wait_until(func(): return _count(gina, "err") > errs), "3: Aktion abgelehnt")
	check(str(_last(gina, "err").get("text", "")) == "Einen Moment – der Gastgeber wechselt.", "3: … mit „Einen Moment – der Gastgeber wechselt.“")
	var rev0 := h.rev
	h.act({"a": "draw"})
	check(h.rev == rev0 and notes.has(I18n.t("Einen Moment – der Gastgeber wechselt.")), "3: eigene Aktion wartet ebenfalls")
	check(FileAccess.get_file_as_string(PATH_B) == file0, "3: eingefroren – keine Datei geschrieben")
	check(wait_until(func(): return not h.is_frozen(), 4000), "3: nach der Frist (check_now, pong) aufgetaut")
	check(h.gen == gen0 and notes.has(I18n.t("Übergabe an %s hat nicht geklappt. Du bleibst Gastgeber.") % "Gina"), "3: Fehlschlag gemeldet, gen unverändert")
	# --- Abstammung: Gina meldet sich mit einem jüngeren Zweig → handover own:true; handover_no taut auf
	var hos := _count(gina, "handover")
	gina.client.hello_override = {"bk": [h.gen + 1, "abcd1234", 3]}
	_reconnect(gina)
	check(wait_until(func(): return _count(gina, "handover") > hos, 4000), "3: jüngerer Zweig → handover an Gina")
	var own := NetProtocol.clean_backup_message(_last(gina, "handover"))
	check(bool(own.get("own", false)) and not own.has("z") and int(own.gen) == h.gen + 1 and int(own.seq) == 3 \
		and int(own.get("host_gen", 0)) == h.gen, "3: handover own:true mit Ginas Marke und eigener gen")
	check(h.is_frozen(), "3: eingefroren während own:true")
	gina.client.send({"t": "handover_no"})
	check(wait_until(func(): return not h.is_frozen()), "3: handover_no taut auf")
	hos = _count(gina, "handover")
	_reconnect(gina)
	pump(400)
	check(_count(gina, "handover") == hos and not h.is_frozen(), "3: kein zweiter Versuch je Gast und gen")
	gina.client.hello_override = {"bk": NetProtocol.BK_NONE}
	_reconnect(gina)
	check(wait_until(func(): return bool(h.game.connected[gseat]) and gina.connection_state() == "open"), "3: Gina wieder normal da")
	# --- Übernahme durch Gina (4000 beim alten Gastgeber)
	var old_seat := h.host_seat
	var old_token := h.host_token()
	var snap := h._snapshot()
	gina.leave()                 # das Ziel schließt seinen Gast-Socket zuerst (HostSwitch)
	pump(100)
	var file1 := FileAccess.get_file_as_string(PATH_B)
	var t := new_host("user://test_host_resume_t.json")
	t.autosave = false
	check(t.resume(snap, gseat, TAKE_PORT, TAKE_PORT) == OK, "3: Gina übernimmt mit dem Stand")
	notes.clear()
	check(wait_until(func(): return not stepped.is_empty()), "3: alter Gastgeber bekommt 4000 → stepped_down")
	check(h.is_frozen() and stepped.size() == 1, "3: eingefroren, stepped_down genau einmal")
	pump(300)
	check(notes.filter(func(n): return str(n).contains("getrennt")).is_empty(), "3: keine Meldung „getrennt“ (%s)" % str(notes))
	check(FileAccess.get_file_as_string(PATH_B) == file1, "3: nach 4000 keine Datei geschrieben")
	check(wait_until(func(): return t.session.online_state() == "open" and str(t.session.online_info().room) == code), "3: Gina führt denselben Raum")
	var mine := h.handover_shutdown()
	check(str(mine.get("role", "")) == "guest" and int(mine.get("my_seat", -1)) == old_seat and h.session == null and h.game == null, "3: handover_shutdown → Gast-Stand, Sitzung abgebaut")
	var saved := MatchSnapshot.read(PATH_B)
	check(str(saved.get("role", "")) == "guest" and MatchSnapshot.own_token(saved) == old_token, "3: Datei role guest mit eigenem Platz-Token")
	pump(200)
	check(relay.core.rooms.has(code), "3: Abtreten beendet den Raum nicht")
	var hanna := new_client("Hanna", link, 0, old_token, true)
	check(wait_until(func(): return hanna.view_rev > 0, 6000), "3: alter Gastgeber kommt als Gast zurück")
	check(hanna.local_seat() == old_seat and bool(t.game.connected[old_seat]), "3: auf seinem eigenen Platz")
	check(t.gen == int(snap.gen) + 1, "3: Gina hat gen + 1")
	t.leave()
	drop(t)
	drop(h)
	hanna.leave()


# ---------- Hilfen ----------

func new_host(path: String) -> HostTable:
	var h := HostTable.new()
	h.auto_process = false
	h.speed = 0.0
	h.use_discovery = false
	h.save_path = path
	hosts.append(h)
	return h


func drop(h: HostTable) -> void:
	hosts.erase(h)
	h.free()


func new_client(player_name: String, address: String, port := 0, token := "", with_bk := false) -> ClientTable:
	var c := ClientTable.new()
	c.auto_process = false
	c.reuse_token = false
	c.persist_tokens = false
	c.retry_ms = [100, 200, 400]
	c.ping_ms = 300
	c.backups = with_bk          # ohne: wie eine App ohne hello.bk (Lecktest)
	c.persist_backup = false     # mehrere „Geräte“ in einem Prozess: keine gemeinsame Datei
	clients.append(c)
	inbox[c] = []
	c.join(address, port, player_name, token)
	if with_bk:
		c.client.hello_override = {"bk": NetProtocol.BK_NONE}   # Marke fest auf „keine Sicherung“ (Abstammung wird hier gezielt gesetzt)
	c.client.message.connect(func(m: Dictionary) -> void: inbox[c].append(m))
	return c


# Verbindung des Gastes kappen; er meldet sich von selbst mit Token neu an.
func _reconnect(c: ClientTable) -> void:
	var before := c.client.attempts
	c.client._ws.close()
	wait_until(func(): return c.connection_state() != "open" or c.client.attempts != before, 1000)
	wait_until(func(): return c.connection_state() == "open", 4000)
	pump(100)


func _count(c: ClientTable, t: String) -> int:
	return (inbox[c] as Array).filter(func(m): return str(m.get("t", "")) == t).size()


func _last(c: ClientTable, t: String) -> Dictionary:
	var list: Array = inbox[c]
	for i in range(list.size() - 1, -1, -1):
		if str(list[i].get("t", "")) == t:
			return list[i]
	return {}


func _has_notice(c: ClientTable, template: String) -> bool:
	for m in inbox[c]:
		if str(m.get("t", "")) == "notice" and JSON.stringify(m.get("lt", [])).contains(template.replace("%s", "").left(12)):
			return true
	return false


# Jede Sicht nach der ersten Sicherung kommt erst nach einer Sicherung desselben Stands (bk seit der letzten Sicht).
func _bk_before_each_state(c: ClientTable) -> bool:
	var seen_bk := false
	var fresh := false
	for m in inbox[c]:
		match str(m.get("t", "")):
			"bk":
				seen_bk = true
				fresh = true
			"state":
				if seen_bk and not fresh:
					return false
				fresh = false
	return seen_bk


func _seat_of_token(h: HostTable, token: String) -> int:
	for s in h.seats.size():
		if str(h.seats[s].get("token", "")) == token:
			return s
	return -1


func _play(hs: Array, h: HostTable, moves: int) -> void:
	var done := 0
	var end := Time.get_ticks_msec() + 6000
	while done < moves and Time.get_ticks_msec() < end:
		pump(5)
		if h.game == null or h.game.phase() in ["round_over", "game_over"]:
			break
		for t in [h] + clients:
			if not is_instance_valid(t) or (t is ClientTable and (t.client == null or t.connection_state() != "open")):
				continue
			var v: Dictionary = t.current_view()
			if v.is_empty():
				continue
			var a := MauBot.choose(v, rng.randi(), 1)
			if not a.is_empty() and str(a.get("a", "")) != "next_round":
				var before := h.rev
				t.act(a)
				pump(5)
				if h.rev != before:
					done += 1


func step() -> void:
	relay.poll()
	for h in hosts:
		if is_instance_valid(h):
			h.pump()
	for c in clients:
		if is_instance_valid(c) and c.client != null:
			c.pump()


func pump(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while true:
		step()
		if Time.get_ticks_msec() >= end:
			break
		OS.delay_msec(1)


func wait_until(cond: Callable, ms := 4000) -> bool:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		pump(2)
		if cond.call():
			return true
	return cond.call()
