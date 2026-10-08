extends SceneTree
# Nachbesserung nach Nachtest 1 der Beta 0.1.1 (docs/geraetetest/0.1.1/NACHTEST1.md), headless mit echten Bildschirmen und echtem
# Netz über 127.0.0.1:
#  N3  „gleich dran“ überspringt fertige Spieler („bis zum Letzten“): TableView.next_seat und die Marken am Tisch.
#  N4  App-Gast: „Bereit ✓“ folgt dem eigenen Stand der Lobby. Ändert der Gastgeber die Regeln, steht der Knopf wieder auf „Bereit“,
#      und ein Tipp genügt, um wieder bereit zu sein.
#  R   App-Gast kommt mitten in der Partie über „Beitreten“ zurück (App neu gestartet, Token gespeichert): Er landet am Tisch auf
#      seinem Platz mit seiner Hand, nicht in einer leeren Lobby (der Gastgeber schickt dabei kein „start“, nur den Stand).
#  L   App-Gast verpasst das Ende (Funkloch, kein „bye“), der Gastgeber eröffnet ein neues Spiel am selben Port: Der Gast verbindet
#      neu und landet in der neuen Lobby statt am alten Tisch (Gerätetest-Bild r1_m07); nach „Start“ sitzt er am neuen Tisch.
#  T   Rückfrage „Lobby schließen?“ mit einem Gast: „1 Mitspieler ist verbunden und wird getrennt.“
#  B   „bye“ des Gastgebers in der Lobby: Der App-Gast ist zurück bei der Suche und sieht den Grund statt „Verbunden. Warte …“.
#  (N5, Grauschleier nach Enter, liegt in game/android/build/src/main/java/com/godot/game/GodotApp.java und ist nur am Gerät prüfbar.)
#   godot_run.ps1 -Script res://tests/test_screens_nachtest1.gd -Headless -Timeout 150

const CleanExit := preload("res://tests/clean_exit.gd")

var ok := 0
var failed := false
var nav: ScreenNav
var nav2: ScreenNav
var nav3: ScreenNav


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


func wait(t: float) -> void:
	await create_timer(t).timeout


func run() -> void:
	GameStarter.test_speed = 0.0
	var app := UiApp.app()
	var settings_backup: Variant = UiApp.setting("regeln", {})
	var host_rules_backup: Variant = UiApp.setting("regeln_gastgeber", {})
	root.size = Vector2i(1600, 720)
	await frames(2)
	await next_seat_unit()
	await next_seat_table()
	check(HostLobbyScreen.close_text(1) == "1 Mitspieler ist verbunden und wird getrennt.", "Rückfrage Lobby: Einzahl")
	check(HostLobbyScreen.close_text(3) == "3 Mitspieler sind verbunden und werden getrennt.", "Rückfrage Lobby: Mehrzahl")
	nav = ScreenNav.new()
	nav.autostart = true
	root.add_child(nav)
	await frames(3)
	await net_flow()
	if app != null:
		app.settings.set_value("regeln", settings_backup if settings_backup is Dictionary else {})
		if host_rules_backup is Dictionary and not (host_rules_backup as Dictionary).is_empty():
			app.settings.set_value("regeln_gastgeber", host_rules_backup)
		else:
			app.settings.reset("regeln_gastgeber")
	if failed:
		print("FAIL: test_screens_nachtest1")
	else:
		print("RESULT: %d ok" % ok)
	await CleanExit.finish(self, 1 if failed else 0)


# ----------------------------------------------------------------- N3: „gleich dran“

static func _places(places: Array) -> Array:
	var out := []
	for i in places.size():
		out.append({"seat": i, "name": "S%d" % i, "count": 0 if int(places[i]) > 0 else 5, "place": places[i]})
	return out


func next_seat_unit() -> void:
	check(TableView.next_seat(_places([0, 0, 0, 0]), 1, 1) == 2, "4 Spieler: nach 1 kommt 2")
	check(TableView.next_seat(_places([0, 0, 0, 0]), 0, -1) == 3, "4 Spieler gegen den Uhrzeigersinn: nach 0 kommt 3")
	check(TableView.next_seat(_places([0, 0, 1, 0, 0]), 1, 1) == 3, "fertiger Platz 2 wird übersprungen")
	check(TableView.next_seat(_places([0, 0, 1, 0, 0]), 3, -1) == 1, "fertiger Platz 2 wird auch rückwärts übersprungen")
	check(TableView.next_seat(_places([1, 0, 2, 0, 0, 0]), 5, 1) == 1, "über den Anfang hinweg, Platz 0 fertig")
	check(TableView.next_seat(_places([0, 3, 1, 2, 0, 0]), 0, 1) == 4, "mehrere Fertige hintereinander")
	check(TableView.next_seat(_places([0, 0, 0]), 0, 1) == 1, "3 Spieler: Marke")
	check(TableView.next_seat(_places([0, 0]), 0, 1) == -1, "2 Spieler: keine Marke")
	check(TableView.next_seat(_places([0, 1, 0, 2]), 0, 1) == -1, "nur noch 2 im Spiel: keine Marke")
	check(TableView.next_seat(_places([0, 0, 0]), -1, 1) == -1, "kein Zug: keine Marke")


# Wie am S21 (n1_e26): 6 Plätze, „bis zum Letzten“, Platz 1 ist fertig, Platz 0 am Zug
func next_seat_table() -> void:
	var sample := TableSamples.create(6, 11)
	var v: Dictionary = sample.view_for(3)
	var players: Array = v.get("players", [])
	(players[1] as Dictionary)["place"] = 1
	(players[1] as Dictionary)["count"] = 0
	v["turn"] = 0
	v["dir"] = 1
	var t := TableView.new()
	root.add_child(t)
	t.set_hand(DemoHand.new())
	t.director.auto_process = false
	t.apply_view(v)
	await frames(2)
	var seat1: OpponentSeat = t._seats.get(1)
	var seat2: OpponentSeat = t._seats.get(2)
	check(seat1 != null and not seat1._next, "Tisch: fertiger Spieler ist nicht „gleich dran“")
	check(seat2 != null and seat2._next, "Tisch: der nächste Mitspielende ist „gleich dran“")
	v["dir"] = -1
	t.apply_view(v)
	var seat5: OpponentSeat = t._seats.get(5)
	check(seat5 != null and seat5._next and not seat2._next, "Tisch: Richtungswechsel – Platz 5 ist „gleich dran“")
	t.queue_free()
	await frames(2)


# ----------------------------------------------------------------- N4, R, L: WLAN über die Bildschirme

func _guest_nav() -> ScreenNav:
	var n := ScreenNav.new()
	n.autostart = false
	root.add_child(n)
	return n


func _wait_for(cond: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not bool(cond.call()) and Time.get_ticks_msec() < deadline:
		await frames(1)
	return bool(cond.call())


func _guest_entry(host: HostTable) -> Dictionary:
	var l := host.lobby()
	for p in l.get("players", []):
		if str(p.get("kind", "")) == "app" and int(p.get("id", -1)) != int(l.get("host_id", -1)):
			return p
	return {}


func net_flow() -> void:
	var app := UiApp.app()
	if app != null:
		app.settings.set_value("regeln", RuleConfig.new().to_dict())
	await frames(2)
	nav.push(HostLobbyScreen.new(), false)
	await frames(3)
	var lobby := nav.top() as HostLobbyScreen
	check(lobby != null and lobby.host != null and lobby.host.port() > 0, "Lobby des Gastgebers offen")
	if lobby == null or lobby.host == null or lobby.host.port() <= 0:
		return
	var host := lobby.host
	var port := host.port()
	nav2 = _guest_nav()
	await frames(2)
	nav2.push(JoinScreen.new(), false)
	await frames(2)
	var join := nav2.top() as JoinScreen
	join.join("127.0.0.1", port)
	check(await _wait_for(func() -> bool: return not _guest_entry(host).is_empty(), 6.0), "App-Gast in der Lobby")
	await wait(0.3)
	# --- N4: Bereit, Regeländerung, wieder bereit
	join._ready_btn.button_pressed = true
	check(await _wait_for(func() -> bool: return bool(_guest_entry(host).get("ready", false)), 3.0), "N4: Gastgeber sieht den Gast als bereit")
	await wait(0.2)
	check(join._ready_btn.button_pressed and join._ready_btn.text == "Bereit ✓", "N4: Knopf zeigt „Bereit ✓“")
	host.set_rules(RuleConfig.preset("familie"))
	check(await _wait_for(func() -> bool: return not join._ready_btn.button_pressed, 3.0), "N4: Regeländerung setzt den Knopf des Gasts zurück")
	check(join._ready_btn.text == "Bereit", "N4: Text wieder „Bereit“ (%s)" % join._ready_btn.text)
	check(not bool(_guest_entry(host).get("ready", true)), "N4: Gastgeber sieht den Gast nicht mehr bereit")
	join._ready_btn.button_pressed = true                  # ein Tipp
	check(await _wait_for(func() -> bool: return bool(_guest_entry(host).get("ready", false)), 3.0), "N4: ein Tipp macht wieder bereit")
	await wait(0.2)
	check(join._ready_btn.button_pressed and join._ready_btn.text == "Bereit ✓", "N4: Knopf wieder „Bereit ✓“")
	# --- Start mit Gast und einem Computergegner
	host.add_bot()
	await wait(0.3)
	lobby.start_game()
	await wait(0.6)
	var hts := nav.top() as TableScreen
	check(hts != null and host.is_running(), "Partie läuft beim Gastgeber")
	check(await _wait_for(func() -> bool: return nav2.top() is TableScreen and not ((nav2.top() as TableScreen).view.get("hand", []) as Array).is_empty(), 5.0), "App-Gast am Tisch mit Hand")
	var gts := nav2.top() as TableScreen
	if hts == null or gts == null:
		return
	var guest_seat := int(gts.view.get("seat", -1))
	var guest_id := int(_guest_entry(host).get("id", -1))
	check(guest_seat >= 0 and guest_id > 0, "Platz des Gasts bekannt (%d)" % guest_seat)
	# --- R: App des Gasts „abgewürgt“ (alles frei, ohne Abmelden), dann über „Beitreten“ zurück
	nav2.queue_free()
	nav2 = null
	check(await _wait_for(func() -> bool: return host.game != null and not bool(host.game.connected[guest_seat]), 4.0), "R: Gastgeber sieht den Gast getrennt")
	nav3 = _guest_nav()
	await frames(2)
	nav3.push(JoinScreen.new(), false)
	await frames(2)
	var join3 := nav3.top() as JoinScreen
	join3.join("127.0.0.1", port)
	check(await _wait_for(func() -> bool: return nav3.top() is TableScreen, 5.0), "R: Rückkehrer kommt an den Tisch (nicht in eine leere Lobby)")
	var rts := nav3.top() as TableScreen
	if rts == null:
		return
	check(await _wait_for(func() -> bool: return not (rts.view.get("hand", []) as Array).is_empty(), 3.0), "R: Rückkehrer hat seine Hand")
	check(int(rts.view.get("seat", -1)) == guest_seat, "R: derselbe Platz (%d)" % int(rts.view.get("seat", -1)))
	check(host.game != null and bool(host.game.connected[guest_seat]), "R: Gastgeber sieht ihn wieder verbunden")
	check(int(_guest_entry(host).get("id", -2)) == guest_id, "R: derselbe Spieler (Token)")
	check(rts.source is ClientTable and (rts.source as ClientTable).get_parent() == rts, "R: Tisch hat die Verbindung übernommen")
	# --- L: Funkloch beim Gast, der Gastgeber verlässt die Partie und eröffnet neu
	var ct := rts.source as ClientTable
	check(ct != null and ct.client != null, "L: Verbindung des Gasts vorhanden")
	if ct == null or ct.client == null:
		return
	ct.client.retry_ms = [250]
	ct.client._lost("Funkloch (Test)")
	hts._leave_now()                                       # „bye“ erreicht den getrennten Gast nicht
	await wait(0.6)
	check(nav.top() is MainMenuScreen, "L: Gastgeber im Hauptmenü")
	check(rts._conn.visible and rts._conn_label.text == "Verbindung zum Gastgeber unterbrochen – warte …", "L: Gast zeigt „Verbindung zum Gastgeber unterbrochen – warte …“ (%s)" % rts._conn_label.text)
	nav.push(HostLobbyScreen.new(), false)
	await frames(3)
	var lobby2 := nav.top() as HostLobbyScreen
	check(lobby2 != null and lobby2.host != null and lobby2.host.port() > 0, "L: neue Lobby offen")
	if lobby2 == null or lobby2.host == null:
		return
	var host2 := lobby2.host
	if host2.port() != port:
		print("Hinweis: neue Lobby auf Port %d statt %d – der Gast versucht es dort" % [host2.port(), port])
		ct.client.port = host2.port()
	check(await _wait_for(func() -> bool: return nav3.top() is JoinScreen, 6.0), "L: Gast wechselt vom alten Tisch in die neue Lobby")
	var join4 := nav3.top() as JoinScreen
	if join4 == null:
		return
	check(join4.client == ct and ct.get_parent() == join4, "L: dieselbe Verbindung, jetzt bei der Lobby")
	check(join4._lobby_box.visible and not join4._search_box.visible, "L: Lobby statt Suche sichtbar")
	check(await _wait_for(func() -> bool: return join4._lobby_list.get_child_count() == 2, 3.0), "L: Lobby zeigt Gastgeber und Gast (%d)" % join4._lobby_list.get_child_count())
	check(ct.current_view().is_empty() and ct.local_seat() == -1, "L: alter Spielstand verworfen")
	check(not join4._ready_btn.button_pressed, "L: neu in der Lobby: nicht bereit")
	await wait(0.5)
	check(not is_instance_valid(rts), "L: alter Tisch abgebaut")
	check(ct.client != null and ct.client.state == "open", "L: Verbindung bleibt nach dem Abbau des alten Tisches offen")
	host2.add_bot()
	await wait(0.3)
	lobby2.start_game()
	check(await _wait_for(func() -> bool: return nav3.top() is TableScreen and not ((nav3.top() as TableScreen).view.get("hand", []) as Array).is_empty(), 5.0), "L: nach „Start“ sitzt der Gast am neuen Tisch")
	var nts := nav3.top() as TableScreen
	if nts != null:
		check(nts.source == ct and ct.client != null and ct.client.state == "open", "L: neuer Tisch mit derselben Verbindung")
	# Aufräumen: Gastgeber verlässt, Gast sieht das Ende
	var hts2 := nav.top() as TableScreen
	if hts2 != null:
		hts2._leave_now()
	await wait(1.2)
	await bye_in_lobby()


# „bye“ des Gastgebers, während der App-Gast in der Lobby wartet: zurück zur Suche, der Grund bleibt stehen (vorher blieb
# „Verbunden. Warte auf den Gastgeber …“ über der leeren Suche stehen, am S10 gesehen).
func bye_in_lobby() -> void:
	nav.home(false)
	await frames(2)
	nav.push(HostLobbyScreen.new(), false)
	await frames(3)
	var lobby3 := nav.top() as HostLobbyScreen
	if lobby3 == null or lobby3.host == null or lobby3.host.port() <= 0:
		check(false, "B: Lobby offen")
		return
	var n4 := _guest_nav()
	await frames(2)
	n4.push(JoinScreen.new(), false)
	await frames(2)
	var j := n4.top() as JoinScreen
	j.join("127.0.0.1", lobby3.host.port())
	check(await _wait_for(func() -> bool: return j.client != null and j.client.connection_state() == "open" and j._lobby_box.visible, 5.0), "B: Gast in der Lobby")
	if j.client == null or j.client.client == null:
		return
	j.client.client._handle({"t": "bye", "text": "Der Gastgeber hat das Spiel beendet."})
	# sofort: der Grund steht da (findet die Suche danach ein Spiel, meldet sie das – hier die noch offene Lobby auf demselben PC)
	check(j._search_box.visible and not j._lobby_box.visible, "B: zurück zur Suche")
	check(j._status.text == "Der Gastgeber hat das Spiel beendet.", "B: Grund steht da (%s)" % j._status.text)
	await frames(3)
	check(j._status.text != "Verbunden. Warte auf den Gastgeber …", "B: nicht mehr „Verbunden. Warte …“ (%s)" % j._status.text)
	lobby3.host.leave()
	nav.pop(false)
	await wait(0.4)
