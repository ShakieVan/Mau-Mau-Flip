class_name NetHostSession
extends Node

# Gastgeber-Sitzung (docs/BETA1_PLAN.md Abschnitt 5), spielunabhängig: kennt nur Spieler, Token, Plätze und Bereit-Status, keine
# Karten. Besitzt den NetServer (ein Port für Seiten, APK und WebSocket) und auf Wunsch die Suche (NetDiscovery als Gastgeber).
#  - Begrüßung prüft Protokoll und Spielversion (exakt gleich), sonst Ablehnung mit Klartext; volle Runde und laufende Partie
#    werden abgelehnt. Wer ein bekanntes Token mitbringt, ist derselbe Spieler (gleiche id, gleicher Platz) – auch mitten in der Partie.
#  - Verbindungsverlust: connected=false, der Platz bleibt reserviert. Der Gastgeber und Computergegner sind lokale Spieler.
#  - Plätze ordnet der Gastgeber (set_seat_order). Lobby-Nachricht: lobby_message(); nach jeder Änderung verteilt (auto_lobby).
# Die Spielsteuerung (Modul G) verbindet sich mit player_joined/left/rejoined und message(id, msg) und sendet mit send_to/broadcast.
# Online-Spiel (docs/online/ENTWURF.md): open_online(vermittler) öffnet zusätzlich einen Raum beim Vermittler (NetRelayHost, gleiche
# Schnittstelle wie NetServer). Verbindungsnummern ab NetProtocol.RELAY_CONN_BASE gehören zum Vermittler (_link wählt den Transport),
# so spielen WLAN- und Online-Gäste in derselben Lobby und Partie. finish/stop beenden auch den Raum ({k:"end"}).
# App-Wechsel (Beta 1.3.3): Gäste melden „away“/„back“ (kurz in einer anderen App), der Gastgeber selbst über PAUSED/FOCUS_OUT bzw.
# RESUMED/FOCUS_IN (app_paused/app_resumed). Feld away je Spieler, in der Lobby verteilt (die Spielsteuerung übernimmt es in die
# Sicht); gone_ms(id) = seit wann weg oder getrennt (Vertretung und Herausnehmen bietet der Gastgeber seit Beta 1.4.2 sofort an).
# Warteliste (Beta 1.4.2, docs/module/dazuholen.md): Bei join_open (oder wenn schon jemand wartet) landen Neue ohne Token mitten in
# der Partie mit seat = −1, waiting = true auf der Warteliste statt „reject running“. Sie bekommen welcome und {t:"lobby", late:true,
# waiting:true, host_name, …}; die Spielsteuerung holt sie an den Tisch (set_waiting false, set_seat_order, start). ordered_ids()
# kennt nur Sitzende, waiting_ids() die Wartenden. Ein getrennter Wartender verfällt nach WAIT_DROP_MS.
# Mau-Mau Flip (Beta 1.6.1, Gastgeber-Übergabe, docs/module/uebergabe.md Abschnitte 1.4, 3 und 3.5):
#  - stop(text, end_room := false): Der Online-Raum endet ({k:"end"}) nur noch ausdrücklich (HostTable.leave, close_online, finish);
#    Freigeben, Abtreten und Übergeben lassen ihn offen.
#  - hello.bk ([gen, epoch, seq]) je Spieler in players[id].bk (backup_ids(): wer Sicherungen bekommt); hello.bk_token erkennt einen
#    Spieler, wenn token unbekannt ist. welcome bekommt zusätzlich welcome_extra (gid, gen, epoch; setzt die Spielsteuerung).
#  - restore_player() trägt Gäste aus einem Spielstand ein, open_online_existing() übernimmt den Raum, online_room() liefert ihn für
#    den Spielstand, send_many() schickt einen Text an mehrere Spieler (online ein send-Rahmen).
#  - Vermittler: replaced (Code 4000) und online_needs_check (/info meldet einen Gastgeber) gehen an die Spielsteuerung. Hört niemand
#    zu, gilt das Verhalten bis 1.6.0 (4000 → Online aufgeben, needs_check → sofort als Gastgeber anmelden).
#  - app_resumed(): „wieder da“ erst, wenn der Vermittler wieder offen ist (ein 4000 aus dem Hintergrund wird so zuerst gelesen).
# Mau-Mau Flip (Beta 1.6.2, WLAN und Spiel-WLAN, docs/module/uebergabe.md 10.1, 10.9 und 10.10):
#  - info() trägt bei laufender Partie gid, gen, epoch (aus welcome_extra) und conn (verbundene entfernte Menschen, Gastgeber-Wächter);
#    set_game_mark(gid, gen, epoch) setzt welcome_extra und frischt /info und die Suche sofort auf.
#  - hello: bk_token gilt nur noch mit bk_gid == welcome_extra.gid (der Gast schickt es an jede Adresse); hp (Port, auf dem der Gast
#    als Gastgeber lauschen würde), ap {ok, perm} (kann ein Spiel-WLAN öffnen) und bk_gid je Spieler (hello_port, ap_caps, backup_gid).
#  - assign_seat(waiting_id, seat_id): Wartenden auf einen getrennten Menschenplatz setzen (zweites welcome mit assigned:true, start,
#    hosts, dann player_rejoined).
#  - drain(max_ms): Gesendetes vor dem Abtreten wirklich hinausschreiben (NetServer.drain, Vermittler flush).
#  - send_hosts(msg): Liste der Erben an die Browser-Gäste im WLAN; die letzte Liste geht nach jedem welcome während der Partie mit.
#  - set_extra_origins(list): zusätzliche erlaubte Ursprünge (frühere Gastgeber) an den Server durchreichen, auch nach Neustart.
#
# Nutzung: var s := NetHostSession.new(); add_child(s); s.start("Lena"); var me := s.host_id; s.message.connect(…)

signal player_joined(id: int)
signal player_left(id: int)
signal player_rejoined(id: int)
signal player_away(id: int, on: bool, changed: bool)   # „away“ (on) bzw. „back“; changed = false: nichts geändert (Gast will den vollen Stand)
signal message(id: int, msg: Dictionary)
signal lobby_changed
signal finished                          # finish() ist fertig: alles geschlossen
signal log_line(text: String)
signal page_visited(address: String)     # ein fremdes Gerät (nicht dieses) hat die Spielseite „/“ abgerufen (Lobby, Beta 1.0.2)
signal online_changed(state: String, info: Dictionary)   # Online-Spiel: off | connecting | open | away | check | stepped_down | failed; info {room, link, error, relay}
signal replaced                          # Beta 1.6.1: ein anderes Gerät führt den Online-Raum (Code 4000) – abtreten
signal online_needs_check(info: Dictionary)   # Beta 1.6.1: beim Neuverbinden meldet /info einen Gastgeber; Probe, dann relay.claim()/step_down()

const HELLO_TIMEOUT_MS := 10000
const CLOSE_GRACE_MS := 3000             # nach „reject“/„bye“: so lange darf der Client selbst schließen (NetServer.close_ws)
const FINISH_MS := 2000                  # finish(): höchstens so lange auf die Clients warten
const WAIT_DROP_MS := 60000            # Warteliste (Beta 1.4.2): ein getrennter Wartender wird nach so vielen ms gestrichen

var auto_poll := true
var hello_timeout_ms := HELLO_TIMEOUT_MS   # so lange darf eine neue Verbindung ohne „hello“ bleiben
var auto_lobby := true                   # nach jeder Änderung die Lobby an alle schicken (solange keine Partie läuft)
var use_discovery := true
var discovery_port := NetProtocol.DISCOVERY_PORT
var game_version := NetProtocol.game_version()   # Tests: andere Version vortäuschen
var web_zip_path := "res://assets/web.zip"     # Browser-Client (an den Server weitergereicht)
var apk_provider := Callable()           # () -> {path, size, name} für /apk (App.apk_share.server_info), an den Server weitergereicht
var max_players := NetProtocol.MAX_PLAYERS
var server: NetServer
var relay: NetRelayHost                  # Online-Spiel über den Vermittler (open_online); Verbindungen ab NetProtocol.RELAY_CONN_BASE
var discovery: NetDiscovery
var host_name := "Gastgeber"
var host_id := 0
var rules := {}
var running := false                     # Partie läuft: Neue ohne Token werden abgelehnt („running“)
var join_open := false                   # Beta 1.4.2: Neue dürfen mitten in die Partie (Warteliste, der Gastgeber holt sie an den Tisch)
var rev := 0
var sid := ""
var players := {}                        # id -> {id, name, kind, token, connected, ready, seat, conn, local, address}
var _conn_player := {}                   # Verbindung -> id
var _pending := {}                       # Verbindung -> {since_ms, info}
var _next_id := 1
var _dirty := false
var _stopping := false
var _finish_at := 0
var welcome_extra := {}                  # Beta 1.6.1: zusätzliche Felder im welcome (gid, gen, epoch; die Spielsteuerung setzt sie)
var _finish_end := true                  # finish(): Online-Raum beenden
var _unaway_pending := false             # Beta 1.6.1: „Gastgeber wieder da“ wartet, bis der Vermittler offen ist
var _unaway_until := 0                   # … höchstens bis dahin (ms); danach „wieder da“ für die WLAN-Gäste, außer bei check/stepped_down
var unaway_max_ms := NetProtocol.RELAY_INFO_TIMEOUT_MS + NetProtocol.RESUME_PROBE_MS
var _extra_origins: Array = []           # Beta 1.6.2: zusätzliche erlaubte Ursprünge (http://ip:port früherer Gastgeber), bleibt über stop()
var _hosts_msg := {}                     # Beta 1.6.2: letzte {t:"hosts"} (geht nach jedem welcome während der Partie an Browser-Gäste)

# ---------- Lebenszyklus ----------

func start(name_of_host: String, port_first := NetProtocol.PORT, port_last := NetProtocol.PORT_LAST, threaded := true) -> Error:
	# Server starten und den Gastgeber als ersten Spieler (Platz 0) eintragen.
	stop()
	NetAddresses.bind_for("host")    # Android: Bindung vor den Sockets (WLAN, eigener Hotspot oder ungebunden – Draw2Race-Regeln)
	server = NetServer.new()
	server.name = "NetServer"
	server.auto_poll = false
	server.threaded = threaded
	server.web_zip_path = web_zip_path
	server.apk_provider = apk_provider
	add_child(server)
	server.ws_opened.connect(_on_open)
	server.ws_message.connect(_on_message)
	server.ws_closed.connect(_on_closed)
	server.ws_dropped.connect(_on_dropped)
	server.log_line.connect(_log)
	server.page_visited.connect(_on_page)
	var err := server.start(port_first, port_last)
	if err != OK:
		_drop_node(server)
		server = null
		NetAddresses.release("host")
		return err
	server.set_extra_origins(_extra_origins)
	if apk_provider.is_valid():
		# Vorbereitung anstoßen (ApkShare kopiert die APK im Hintergrund); ist sie schon bereit, gilt sie sofort.
		var apk = apk_provider.call()
		if apk is Dictionary and not apk.is_empty():
			server.set_apk(apk)
	sid = Crypto.new().generate_random_bytes(6).hex_encode()
	host_name = NetProtocol.clean_name(name_of_host, "Gastgeber")
	host_id = add_local_player(host_name, "app")
	if use_discovery:
		discovery = NetDiscovery.new()
		discovery.name = "NetDiscovery"
		discovery.auto_poll = false
		add_child(discovery)
		discovery.log_line.connect(_log)
		if discovery.start_host(info(), discovery_port) != OK:
			_log("Suche: Port %d belegt – Mitspieler finden das Spiel nur über die Adresse" % discovery_port)
	_changed()
	_log("Gastgeber „%s“ bereit auf Port %d (Protokoll %d, Version %s)" % [host_name, server.port, NetProtocol.PROTO, game_version])
	return OK

func finish(text := "Der Gastgeber hat das Spiel beendet.", end_room := true) -> void:
	# Nicht blockierend beenden: allen „bye“ schicken, poll() schließt alles, sobald die Clients getrennt haben (höchstens FINISH_MS),
	# dann Signal finished. Bevorzugt vor stop(text), weil die Clients dabei weiter abgefragt werden. end_room: Online-Raum beenden.
	if (server == null and relay == null) or _finish_at > 0:
		return
	_finish_end = end_room
	_bye_all(text, FINISH_MS - 500)
	_finish_at = Time.get_ticks_msec() + FINISH_MS

func stop(text := "", end_room := false) -> void:
	# Sofort beenden; mit text vorher „bye“ an alle und bis zu 1 s warten. Signale gehen dabei keine mehr hinaus.
	# end_room (Beta 1.6.1): Online-Raum beim Vermittler beenden ({k:"end"}); sonst bleibt er offen (Übernahme durch einen Gast).
	_stopping = true
	_finish_at = 0
	_unaway_pending = false
	if text != "" and (server != null or relay != null):
		_bye_all(text, 800)
		var end := Time.get_ticks_msec() + 1000
		while Time.get_ticks_msec() < end and _active() > 0:
			if server != null:
				server.poll()
			if relay != null:
				relay.poll()
			OS.delay_msec(5)
	_close_relay(end_room)
	if server != null:
		server.stop()
		_drop_node(server)
		server = null
		NetAddresses.release("host")
	if discovery != null:
		discovery.stop()
		_drop_node(discovery)
		discovery = null
	_stopping = false
	players.clear()
	_conn_player.clear()
	_pending.clear()
	_hosts_msg = {}
	host_id = 0
	running = false

func port() -> int:
	return server.port if server != null else 0

func rebind(after_close := false) -> String:
	# Nach dem Öffnen des Spiel-WLANs (LocalOnlyHotspot): Bindung neu bewerten (NetAddresses.bind_for, Draw2Race-Regeln). Waren Server
	# und Suche ans WLAN gebunden, erreichen sie die Spiel-WLAN-Gäste nicht; dann entstehen beide neu auf demselben Port, solange noch
	# kein Mitspieler verbunden ist. "" = passt, sonst deutscher Hinweis.
	# after_close (Beta 1.1.1): Spiel-WLAN wieder zu – zurück zur Bindung wie beim Eröffnen (meist ans WLAN). War die Sitzung ans
	# Spiel-WLAN gebunden, ist dessen Netz weg; dann entsteht der Server auch mit (nun getrennten) Mitspielern neu.
	if server == null:
		return ""
	var before := NetAddresses.binding()
	if NetAddresses.holding() > 0:
		# Gerade entsteht eine Internet-Verbindung (Vermittler, Updater) ohne Bindung: neu bewerten, sobald sie steht.
		NetAddresses.after_holds(_rebind_after.bind(after_close, before))
		return ""
	return _rebind_after(after_close, before)

func _rebind_after(after_close: bool, before: String) -> String:
	if server == null:
		return ""
	var now := NetAddresses.bind_for("host")
	if now == before:
		return ""
	var guests := players.values().filter(func(p): return not bool(p.get("local", false)) and int(p.get("conn", -1)) >= 0 and int(p.get("conn", -1)) < NetProtocol.RELAY_CONN_BASE)
	if not guests.is_empty() and not (after_close and before == "hotspot"):
		if after_close:
			return I18n.t("Spiel-WLAN ist zu. Kommt jemand aus dem WLAN nicht rein, eröffne das Spiel neu.")
		return I18n.t("Mitspieler sind schon verbunden. Damit das Spiel-WLAN klappt, eröffne das Spiel neu.")
	var p := server.port
	server.stop()
	var err := server.start(p, p)
	for attempt in 4:
		# Unter Last gibt Windows den eben geschlossenen Port manchmal erst einen Augenblick später frei.
		if err == OK:
			break
		OS.delay_msec(25 * (attempt + 1))
		err = server.start(p, p)
	if err != OK:
		err = server.start(NetProtocol.PORT, NetProtocol.PORT_LAST)
	if err != OK:
		return I18n.t("Das Spiel ließ sich nicht neu öffnen. Bitte zurück und neu eröffnen.")
	server.set_extra_origins(_extra_origins)
	server.set_info(info())
	if discovery != null:
		discovery.start_host(info(), discovery_port)
	_log("Neu gebunden (%s → %s) auf Port %d" % [before if before != "" else "ungebunden", now if now != "" else "ungebunden", server.port])
	return ""

func _process(_delta: float) -> void:
	if auto_poll:
		poll()

func _exit_tree() -> void:
	# Umhängen (reparent, z. B. Lobby → Tisch) verlässt den Baum nur kurz. Erst am Ende des Frames prüfen, ob die Sitzung wirklich
	# draußen ist; sonst ginge der Server mitten im Spielstart aus (Gerätetest 0.1.1, H1). Beim Freigeben stoppt NOTIFICATION_PREDELETE.
	_stop_if_detached.call_deferred()

func _stop_if_detached() -> void:
	if not is_inside_tree():
		stop()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		stop()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		app_paused()
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		app_resumed()

# Gastgeber-App geht in den Hintergrund: allen sofort „kurz in einer anderen App“ zeigen (Best effort, danach hält Android an).
func app_paused() -> void:
	if host_id == 0 or not players.has(host_id) or bool(players[host_id].get("away", false)):
		return
	set_away(host_id, true)
	flush()

# Gastgeber-App wieder vorn: Vermittler-Verbindung sofort prüfen, „away“ zurücknehmen (alle bekommen den aktuellen Stand).
# Beta 1.6.1: Zuerst liest der Vermittler-Socket, was im Hintergrund kam (ein 4000 → abtreten, dann kein „wieder da“). Verbindet er
# gerade neu (away/check/connecting), kommt „wieder da“ erst, wenn er wieder offen ist.
func app_resumed() -> void:
	if relay != null:
		relay.check_now()
		relay.poll()
		if relay != null and relay.state == "stepped_down":
			_unaway_pending = false
			return
		if relay != null and relay.state in ["away", "check", "connecting"]:
			_unaway_pending = true
			_unaway_until = Time.get_ticks_msec() + unaway_max_ms   # ohne Internet bliebe der Vermittler sonst für immer „away“
			return
	_unaway_now()

func _unaway_now() -> void:
	_unaway_pending = false
	if host_id != 0 and players.has(host_id) and bool(players[host_id].get("away", false)):
		set_away(host_id, false)
		flush()

# Gesendetes sofort hinausschieben (WLAN ohne Thread und Vermittler); der Server-Thread sendet selbst.
func flush() -> void:
	if server != null and not server.threaded:
		server.poll()
	if relay != null:
		relay.flush()

# Mau-Mau Flip (Beta 1.6.2, 10.7): Gesendetes wirklich hinausschreiben, bevor der Server schließt (Abtreten nach move). flush()
# genügt dafür nicht (mit Server-Thread tut es nichts). Höchstens max_ms; true = alles hinaus (Vermittler: nur angestoßen).
func drain(max_ms := 500) -> bool:
	if relay != null:
		relay.flush()
	if server != null:
		return server.drain(max_ms)
	return true

# Beta 1.6.2 (10.9): zusätzliche erlaubte Ursprünge für den WebSocket (Lite-Seiten früherer Gastgeber, exakt http://ip:port; die
# Prüfung macht der Server). Gilt auch nach einem Neustart des Servers (start, rebind) und über stop() hinweg.
func set_extra_origins(list: Array) -> void:
	_extra_origins = []
	for o in list:
		if o is String and o != "" and not _extra_origins.has(o):
			_extra_origins.append(o)
	if server != null:
		server.set_extra_origins(_extra_origins)

func extra_origins() -> Array:
	return _extra_origins.duplicate()

# Beta 1.6.2 (10.9): {t:"hosts", gid, gen, list, online, ap, ap_name} an die Browser-Gäste im WLAN (online braucht Lite sie nicht,
# die Liste nennt nur LAN-Adressen). Die Nachricht bleibt gemerkt und geht nach jedem welcome während der Partie an jeden
# Browser-Gast im WLAN mit. {} = vergessen.
func send_hosts(msg: Dictionary) -> void:
	_hosts_msg = msg.duplicate(true)
	if _hosts_msg.is_empty():
		return
	_hosts_msg["t"] = "hosts"
	var ids := []
	for id in players:
		if _hosts_to(id):
			ids.append(id)
	send_many(ids, NetProtocol.encode(_hosts_msg))

func hosts_message() -> Dictionary:
	return _hosts_msg.duplicate(true)

func _hosts_to(id: int) -> bool:
	var p: Dictionary = players.get(id, {})
	return not p.is_empty() and str(p.get("kind", "")) == "web" and int(p.get("conn", -1)) >= 0 \
		and int(p.conn) < NetProtocol.RELAY_CONN_BASE

func _send_hosts_after_welcome(id: int) -> void:
	if running and not _hosts_msg.is_empty() and _hosts_to(id):
		send_to(id, _hosts_msg)

# Spieler kurz in einer anderen App (on) bzw. wieder da. Verteilt die Lobby; player_away meldet es der Spielsteuerung.
func set_away(id: int, on: bool) -> void:
	if not players.has(id):
		return
	var p: Dictionary = players[id]
	var changed := bool(p.get("away", false)) != on
	p.away = on
	if on and int(p.get("gone_since", 0)) == 0:
		p.gone_since = maxi(Time.get_ticks_msec(), 1)
	elif not on and bool(p.connected):
		p.gone_since = 0
	if changed:
		_log("Spieler %d „%s“ %s" % [id, p.name, "kurz in einer anderen App" if on else "wieder da"])
		_changed(true)
	player_away.emit(id, on, changed)

func is_away(id: int) -> bool:
	return players.has(id) and bool(players[id].get("away", false))

# Wie lange ein Spieler schon weg (andere App) oder getrennt ist, in ms; 0 = da.
func gone_ms(id: int) -> int:
	if not players.has(id):
		return 0
	var since := int(players[id].get("gone_since", 0))
	return Time.get_ticks_msec() - since if since > 0 else 0

func poll() -> void:
	if server == null and relay == null:
		return
	if server != null:
		server.poll()
	if relay != null:
		relay.poll()
	if discovery != null:
		discovery.poll()
	var now := Time.get_ticks_msec()
	# Beta 1.6.1: „wieder da“ nicht ewig aufschieben (kein Internet: Vermittler bleibt away, ohne Signal). Ein 4000 kommt nur über ein
	# offenes Socket; während der Probe (check) entscheidet der Vermittler gleich selbst (open/stepped_down).
	if _unaway_pending and now >= _unaway_until and (relay == null or not relay.state in ["check", "stepped_down"]):
		_unaway_now()
	for conn in _pending.keys():
		if now - int(_pending[conn].since_ms) > hello_timeout_ms:
			_pending.erase(conn)
			_close(conn, NetWs.CLOSE_TIMEOUT, "Anmeldung fehlt")
	if _finish_at > 0 and (_active() == 0 or now > _finish_at):
		stop("", _finish_end)
		finished.emit()
		return
	for id in waiting_ids():
		if not bool(players[id].connected) and gone_ms(id) > WAIT_DROP_MS:
			_log("Wartender %d „%s“ gestrichen (getrennt)" % [id, players[id].name])
			players.erase(id)
			_changed()
	if _dirty:
		_dirty = false
		_publish()

func _bye_all(text: String, grace_ms: int) -> void:
	var conns := _connected_conns()
	_send_many(conns, NetProtocol.encode({"t": "bye", "text": text}))
	for conn in conns:
		_close(conn, NetWs.CLOSE_GOING_AWAY, "Gastgeber beendet", grace_ms)
	for conn in _pending.keys():
		_close(conn, NetWs.CLOSE_GOING_AWAY, "Gastgeber beendet")
	_pending.clear()

# ---------- Spieler ----------

func add_local_player(player_name: String, kind := "bot") -> int:
	# Gastgeber ("app") oder Computergegner ("bot"): immer verbunden und bereit. -1 = voll.
	if players.size() >= max_players:
		return -1
	var id := _next_id
	_next_id += 1
	players[id] = {"id": id, "name": NetProtocol.unique_name(NetProtocol.clean_name(player_name, "Computer"), _names()), "kind": kind,
		"token": "", "connected": true, "ready": true, "seat": _next_seat(), "conn": -1, "local": true, "address": ""}
	_changed()
	return id

func remove_player(id: int, text := "Der Gastgeber hat dich aus der Runde genommen.") -> void:
	# Spieler entfernen (Gastgeber-Knopf); ein verbundener bekommt „bye“. Plätze rücken nach.
	if not players.has(id) or id == host_id:
		return
	var p: Dictionary = players[id]
	if int(p.conn) >= 0:
		_send(p.conn, NetProtocol.encode({"t": "bye", "text": text}))
		_close(p.conn, NetWs.CLOSE_NORMAL, "entfernt", CLOSE_GRACE_MS)
		_conn_player.erase(p.conn)
	players.erase(id)
	_compact_seats()
	_changed()

func set_seat_order(ids: Array) -> bool:
	# Sitzordnung im Uhrzeigersinn ab Platz 0. Nicht genannte Spieler folgen in ihrer bisherigen Reihenfolge. false = ungültig.
	var seen := {}
	for id in ids:
		if not (id is int) or not players.has(id) or seen.has(id):
			return false
		seen[id] = true
	for id in ids:
		players[id].erase("waiting")         # genannte Wartende sitzen jetzt mit
	var order: Array = ids.duplicate()
	for id in ordered_ids():
		if not seen.has(id):
			order.append(id)
	for i in range(order.size()):
		players[order[i]].seat = i
	_changed()
	return true

func ordered_ids() -> Array:
	# Spieler-ids nach Platz (ohne Wartende).
	var ids := players.keys().filter(func(i): return not bool(players[i].get("waiting", false)))
	ids.sort_custom(func(a, b): return int(players[a].seat) < int(players[b].seat))
	return ids

func waiting_ids() -> Array:
	# Wartende (Beta 1.4.2) in der Reihenfolge ihrer Anmeldung.
	var ids := players.keys().filter(func(i): return bool(players[i].get("waiting", false)))
	ids.sort()
	return ids

func is_waiting(id: int) -> bool:
	return players.has(id) and bool(players[id].get("waiting", false))

func set_waiting(id: int, on: bool) -> void:
	# Wartenden an den Tisch holen (off; den Platz setzt danach set_seat_order) bzw. zurück auf die Warteliste.
	if not players.has(id) or id == host_id:
		return
	if on:
		players[id].waiting = true
		players[id].seat = -1
	else:
		players[id].erase("waiting")
		if int(players[id].seat) < 0:
			players[id].seat = _next_seat()
	_changed()

func accepts_late() -> bool:
	# Nimmt die laufende Partie Neue auf die Warteliste?
	return running and (join_open or not waiting_ids().is_empty())

func player(id: int) -> Dictionary:
	return players.get(id, {})

# Mau-Mau Flip (Beta 1.6.1, Gastgeber-Übergabe): Gast aus einem Spielstand eintragen – getrennt, bereit, mit seinem Token (er meldet
# sich damit wieder an). net: "app" | "web". waiting: zurück auf die Warteliste (Platz −1). Ergebnis: id, −1 = voll.
func restore_player(player_name: String, net: String, player_token: String, waiting := false) -> int:
	if players.size() >= max_players:
		return -1
	var id := _next_id
	_next_id += 1
	players[id] = {"id": id, "name": NetProtocol.clean_name(player_name), "kind": net if NetProtocol.KINDS.has(net) else "app",
		"token": player_token.left(64), "connected": false, "ready": true, "seat": -1 if waiting else _next_seat(), "conn": -1,
		"local": false, "address": "", "gone_since": maxi(Time.get_ticks_msec(), 1)}
	if waiting:
		players[id].waiting = true
	_changed()
	return id

# Beta 1.6.1: denselben Text an mehrere Spieler (online ein einziger send-Rahmen); nicht verbundene und lokale werden übergangen.
func send_many(ids: Array, text: String) -> void:
	var conns := []
	for id in ids:
		if players.has(id) and int(players[id].conn) >= 0:
			conns.append(int(players[id].conn))
	if not conns.is_empty():
		_send_many(conns, text)

# Beta 1.6.1: verbundene App-Gäste, die im hello bk geschickt haben (können Sicherungen halten), ohne Wartende – nach Platz.
func backup_ids() -> Array:
	var out := []
	for id in ordered_ids():
		var p: Dictionary = players[id]
		if not bool(p.local) and bool(p.connected) and int(p.conn) >= 0 and p.get("bk") is Array:
			out.append(id)
	return out

# Beta 1.6.1: Stand der Sicherung [gen, epoch, seq] aus dem letzten hello des Spielers; [] = keiner (Browser, alte App).
func backup_mark(id: int) -> Array:
	return players[id].get("bk", []) if players.has(id) and players[id].get("bk") is Array else []

# Beta 1.6.2: gid der Sicherung aus dem letzten hello ("" = keine/ältere App) – die Abstammungsregel gilt nur für dieselbe Partie.
func backup_gid(id: int) -> String:
	return str(players[id].get("bk_gid", "")) if players.has(id) else ""

# Beta 1.6.2: Port, auf dem dieser App-Gast als Gastgeber lauschen würde (hello.hp); 0 = unbekannt.
func hello_port(id: int) -> int:
	return int(players[id].get("hp", 0)) if players.has(id) else 0

# Beta 1.6.2: Kann dieser App-Gast ein Spiel-WLAN öffnen (hello.ap)? {ok, perm}; ohne Angabe (ältere App, Browser) beides false.
func ap_caps(id: int) -> Dictionary:
	var ap = players[id].get("ap") if players.has(id) else null
	if ap is Dictionary:
		return {"ok": bool(ap.get("ok", false)), "perm": bool(ap.get("perm", false))}
	return {"ok": false, "perm": false}

# Mau-Mau Flip (Beta 1.6.2, 10.10): Wartenden auf den Platz eines getrennten Mitspielers setzen. Verbindung, Art, Adresse, online
# und die Sicherungsangaben des Wartenden gehen auf den Platz-Spieler über (Name und Token des Platzes bleiben), der Eintrag des
# Wartenden fällt weg. Auf derselben Verbindung folgen ein zweites welcome mit id und Token des Platzes und assigned:true, bei
# laufender Partie {t:"start", seat} (with_start), für Browser-Gäste im WLAN die Liste hosts, dann player_rejoined(seat_id) (die
# Spielsteuerung schickt den Stand wie bei einer Rückkehr). false = abgelehnt: waiting_id wartet nicht verbunden, oder seat_id ist
# der Gastgeber, ein Computer, ein Wartender, ein verbundener Spieler oder unbekannt.
func assign_seat(waiting_id: int, seat_id: int, with_start := true) -> bool:
	if waiting_id == seat_id or not is_waiting(waiting_id) or not players.has(seat_id) or seat_id == host_id:
		return false
	var w: Dictionary = players[waiting_id]
	var p: Dictionary = players[seat_id]
	var conn := int(w.get("conn", -1))
	if conn < 0 or not bool(w.connected) or _link(conn) == null:
		return false
	if bool(p.local) or bool(p.get("waiting", false)) or bool(p.connected) or int(p.conn) >= 0 or int(p.seat) < 0:
		return false
	players.erase(waiting_id)
	_conn_player[conn] = seat_id
	p.conn = conn
	p.connected = true
	p.away = bool(w.get("away", false))
	p.gone_since = int(w.get("gone_since", 0)) if bool(p.away) else 0
	p.ready = true
	p.kind = w.kind
	p.address = w.address
	p.online = bool(w.get("online", false))
	for key in ["bk", "bk_gid", "hp", "ap"]:
		if w.has(key):
			p[key] = w[key]
		else:
			p.erase(key)
	var welcome := _welcome(seat_id, str(p.token))
	welcome["assigned"] = true
	_send(conn, NetProtocol.encode(welcome))
	if running and with_start:
		_send(conn, NetProtocol.encode({"t": "start", "seat": int(p.seat)}))
	_send_hosts_after_welcome(seat_id)
	_log("Wartender %d „%s“ sitzt jetzt auf dem Platz von %d „%s“" % [waiting_id, w.name, seat_id, p.name])
	player_rejoined.emit(seat_id)
	_changed(true)
	return true

func seat_of(id: int) -> int:
	return int(players[id].seat) if players.has(id) else -1

func id_at_seat(seat: int) -> int:
	for id in players:
		if int(players[id].seat) == seat:
			return id
	return -1

func set_ready(id: int, ready: bool) -> void:
	if players.has(id) and players[id].ready != ready:
		players[id].ready = ready
		_changed()

func all_ready() -> bool:
	for p in players.values():
		if not p.ready or not p.connected:
			return false
	return true

func set_rules(new_rules: Dictionary) -> void:
	# Regeln ändern: Bereit-Meldungen der Mitspieler verfallen (sie sollen die neuen Regeln sehen).
	rules = new_rules.duplicate(true)
	for p in players.values():
		if not p.local:
			p.ready = false
	_changed()

func set_running(on: bool) -> void:
	running = on
	if not on:
		for id in waiting_ids():         # zurück in der Lobby: Wartende sitzen ganz normal mit
			players[id].erase("waiting")
			players[id].seat = _next_seat()
	_changed()

func send_start() -> void:
	# Partie beginnt: running setzen und jedem verbundenen Mitspieler {t:"start", seat} schicken.
	running = true
	for id in players:
		send_to(id, {"t": "start", "seat": int(players[id].seat)})
	_changed()

func send_to(id: int, msg: Dictionary) -> bool:
	# An einen verbundenen Mitspieler; false = nicht verbunden oder lokal.
	if not players.has(id) or int(players[id].conn) < 0 or _link(int(players[id].conn)) == null:
		return false
	_send(players[id].conn, NetProtocol.encode(msg))
	return true

func broadcast(msg: Dictionary, except_id := -1) -> void:
	var conns := []
	for id in players:
		if id != except_id and int(players[id].conn) >= 0:
			conns.append(players[id].conn)
	_send_many(conns, NetProtocol.encode(msg))

func lobby_message() -> Dictionary:
	var list := []
	for id in ordered_ids() + waiting_ids():
		var p: Dictionary = players[id]
		var entry := {"id": id, "name": p.name, "kind": p.kind, "connected": p.connected, "ready": p.ready, "seat": int(p.seat)}
		if bool(p.get("waiting", false)):
			entry["waiting"] = true         # auf der Warteliste (Beta 1.4.2)
		if bool(p.get("online", false)):
			entry["online"] = true          # über den Vermittler verbunden (Weltkugel in der Lobby)
		if bool(p.get("away", false)):
			entry["away"] = true            # kurz in einer anderen App (Beta 1.3.3; ältere Geräte ignorieren das Feld)
		list.append(entry)
	return {"t": "lobby", "rev": rev, "players": list, "rules": rules, "host_id": host_id}

func waiting_message() -> Dictionary:
	# Lobby-Stand für Wartende mitten in der Partie (Beta 1.4.2): ältere Geräte zeigen eine normale Lobby, danach kommt „start“.
	var m := lobby_message()
	m["late"] = true
	m["waiting"] = true
	m["host_name"] = host_name
	return m

func info() -> Dictionary:
	# Inhalt von /info und der Suchantwort. Beta 1.6.2 (10.1): bei laufender Partie zusätzlich gid, gen, epoch und conn.
	var extra := {"running": running, "sid": sid, "addresses": NetAddresses.own_addresses().map(func(a): return a.address)}
	if running and str(welcome_extra.get("gid", "")) != "":
		extra["gid"] = str(welcome_extra.gid)
		extra["gen"] = int(welcome_extra.get("gen", 0))
		extra["epoch"] = str(welcome_extra.get("epoch", ""))
		extra["conn"] = connected_humans()
	return NetProtocol.make_info(host_name, players.size(), port(), extra)

# Beta 1.6.2: verbundene entfernte Menschen am Tisch (ohne Wartende) – für den Gastgeber-Wächter (10.11).
func connected_humans() -> int:
	var n := 0
	for p in players.values():
		if not bool(p.local) and bool(p.connected) and int(p.conn) >= 0 and not bool(p.get("waiting", false)):
			n += 1
	return n

# Beta 1.6.2: Kennung der Partie (gid, gen, epoch) für welcome, /info und die Suche setzen und beides sofort auffrischen.
# gid "" = keine Partie (welcome_extra leer).
func set_game_mark(gid: String, gen: int, epoch: String) -> void:
	welcome_extra = {} if gid == "" else {"gid": gid, "gen": gen, "epoch": epoch}
	_refresh_info()

func _refresh_info() -> void:
	var i := info()
	if server != null:
		server.set_info(i)
	if discovery != null:
		discovery.set_info(i)

func apk_url(host_header := "") -> String:
	# Adresse der APK, wie der Mitspieler den Gastgeber erreicht (Host-Kopf seiner Verbindung), sonst die erste eigene Adresse.
	var host := host_header
	if host == "" or host.begins_with("127.") or host.begins_with("localhost"):
		var own := NetAddresses.own_addresses()
		if not own.is_empty():
			host = "%s:%d" % [own[0].address, port()]
		elif host == "":
			host = "127.0.0.1:%d" % port()
	return "http://%s/apk" % host

# ---------- Ereignisse des Servers ----------

func _on_page(address: String) -> void:
	if not is_own_address(address):
		page_visited.emit(address)

static func is_own_address(address: String, own: Variant = null) -> bool:
	# Eigene Adresse (Loopback oder eine Schnittstelle dieses Geräts)? own: Liste statt IP.get_local_addresses() (Tests).
	var a := address.trim_prefix("::ffff:").get_slice("%", 0)
	if a == "" or a.begins_with("127.") or a == "::1":
		return true
	for o in (own if own is Array else Array(IP.get_local_addresses())):
		if str(o).trim_prefix("::ffff:").get_slice("%", 0) == a:
			return true
	return false

func _on_open(conn: int, conn_info: Dictionary) -> void:
	_pending[conn] = {"since_ms": Time.get_ticks_msec(), "info": conn_info}

func _on_closed(conn: int, code: int, reason: String) -> void:
	_pending.erase(conn)
	if _stopping or _finish_at > 0 or not _conn_player.has(conn):
		return
	var id: int = _conn_player[conn]
	_conn_player.erase(conn)
	if not players.has(id) or int(players[id].conn) != conn:
		return
	players[id].conn = -1
	players[id].connected = false
	if int(players[id].get("gone_since", 0)) == 0:
		players[id].gone_since = maxi(Time.get_ticks_msec(), 1)
	_log("Spieler %d „%s“ getrennt (%d%s)" % [id, players[id].name, code, " " + reason if reason != "" else ""])
	player_left.emit(id)
	_changed()

func _on_dropped(conn: int, why: String, size: int) -> void:
	if why == "size":
		_send(conn, NetProtocol.encode(I18n.with_lt({"t": "err"}, [I18n.part("Nachricht zu groß (%d Byte) – verworfen.", [size])])))

func _on_message(conn: int, text: String) -> void:
	if _finish_at > 0:
		return
	var raw := NetProtocol.decode(text)
	if raw.is_empty():
		_log("Unverständliche Nachricht auf Verbindung %d verworfen (%d Zeichen)" % [conn, text.length()])
		return
	var msg := NetProtocol.clean_client_message(raw)
	if msg.is_empty():
		return
	if _pending.has(conn):
		if msg.t == "hello":
			_hello(conn, msg, _pending[conn].info)
		return
	if not _conn_player.has(conn):
		return
	var id: int = _conn_player[conn]
	match str(msg.t):
		"hello":
			return
		"ping":
			send_to(id, {"t": "pong", "ts": msg.ts})    # nur ohne Sofortantwort des Server-Threads
		"lobby_ready":
			if not running:
				set_ready(id, bool(msg.ready))
		"away", "back":
			set_away(id, msg.t == "away")
			if msg.t == "back" and not running:
				send_to(id, lobby_message())       # voller Stand der Lobby (in der Partie schickt die Spielsteuerung „state“)
		"log":
			var zeile := "Gast %d „%s“: %s" % [id, players[id].name, str(msg.text).left(300)]
			_log(zeile)
			print(zeile)   # Beta 1.6.15: auch ins Systemprotokoll (adb logcat -s godot), z. B. die Tempo-Zeilen des Browsers
		_:
			message.emit(id, msg)

func _hello(conn: int, msg: Dictionary, conn_info: Dictionary) -> void:
	_pending.erase(conn)
	var url := NetProtocol.apk_page_url(game_version) if bool(conn_info.get("online", false)) else apk_url(str(conn_info.get("host", "")))
	var problem := NetProtocol.check_hello(msg, game_version, url)
	var token := str(msg.get("token", ""))
	var known := -1
	if problem.is_empty() and token != "":
		known = _id_by_token(token)
	if problem.is_empty() and known < 0 and str(msg.get("bk_token", "")) != "" and _bk_gid_matches(msg):
		known = _id_by_token(str(msg.bk_token))     # Beta 1.6.1: Platz-Token aus der Sicherung (Rückfallebene; 1.6.2: nur dieselbe Partie)
	if problem.is_empty() and known < 0:
		if running and not accepts_late():
			problem = {"code": "running", "text": "Die Partie läuft schon. Warte, bis der Gastgeber eine neue Runde eröffnet."}
		elif players.size() >= max_players:
			problem = I18n.with_lt({"code": "full"}, [I18n.part("Die Runde ist voll (höchstens %d Spieler).", [max_players])])
	if not problem.is_empty():
		_log("Anmeldung von %s abgelehnt (%s): %s" % [conn_info.get("address", "?"), problem.code, problem.text])
		var rej := {"t": "reject", "code": problem.code, "text": problem.text}
		if problem.get("lt") is Array:
			rej["lt"] = problem.lt   # Bausteine (I18n): Anzeige in der Sprache des Gastes
		_send(conn, NetProtocol.encode(rej))
		_close(conn, NetWs.CLOSE_NORMAL, problem.code, CLOSE_GRACE_MS)
		return
	if known >= 0:
		var p: Dictionary = players[known]
		var old := int(p.conn)
		if old >= 0 and old != conn:
			_conn_player.erase(old)
			_close(old, NetWs.CLOSE_REPLACED, "neue Verbindung")
		p.conn = conn
		p.connected = true
		p.away = false                  # neu angemeldet = App vorn (sonst schickt der Gast gleich wieder „away“)
		p.gone_since = 0
		p.kind = msg.kind
		p.address = str(conn_info.get("address", ""))
		p.online = bool(conn_info.get("online", false))
		_set_bk(p, msg)
		_conn_player[conn] = known
		_send(conn, NetProtocol.encode(_welcome(known, str(p.token))))
		_send_hosts_after_welcome(known)
		_log("Spieler %d „%s“ wieder da (%s)" % [known, p.name, conn_info.get("address", "?")])
		player_rejoined.emit(known)
		_changed(true)
		return
	var id := _next_id
	_next_id += 1
	var new_token := Crypto.new().generate_random_bytes(NetProtocol.TOKEN_LENGTH / 2).hex_encode()
	var late := running
	players[id] = {"id": id, "name": NetProtocol.unique_name(str(msg.name), _names()), "kind": msg.kind, "token": new_token,
		"connected": true, "ready": false, "seat": -1 if late else _next_seat(), "conn": conn, "local": false,
		"address": str(conn_info.get("address", "")), "online": bool(conn_info.get("online", false))}
	if late:
		players[id].waiting = true          # mitten in der Partie: Warteliste, der Gastgeber holt ihn an den Tisch
	_set_bk(players[id], msg)
	_conn_player[conn] = id
	_send(conn, NetProtocol.encode(_welcome(id, new_token)))
	_send_hosts_after_welcome(id)
	_log("Spieler %d „%s“ beigetreten (%s, %s)" % [id, players[id].name, msg.kind, conn_info.get("address", "?")])
	if late:
		_log("Spieler %d „%s“ wartet auf einen Platz" % [id, players[id].name])
	player_joined.emit(id)
	_changed(true)

func _id_by_token(t: String) -> int:
	for id in players:
		if not players[id].local and str(players[id].token) == t:
			return id
	return -1

func _set_bk(p: Dictionary, msg: Dictionary) -> void:
	# Beta 1.6.1: hello.bk merken (bereinigt in clean_client_message); ohne bk bekommt der Spieler keine Sicherungen.
	# Beta 1.6.2: dazu bk_gid, hp und ap (nur Apps; fehlt ein Feld im neuen hello, fällt der alte Wert weg).
	var app := str(msg.get("kind", "")) == "app"
	if msg.get("bk") is Array and app:
		p.bk = (msg.bk as Array).duplicate()
	else:
		p.erase("bk")
	if app and msg.get("bk_gid") is String and str(msg.bk_gid) != "":
		p.bk_gid = str(msg.bk_gid).left(32)
	else:
		p.erase("bk_gid")
	if app and msg.get("hp") is int and int(msg.hp) >= 1024 and int(msg.hp) <= 65535:
		p.hp = int(msg.hp)
	else:
		p.erase("hp")
	var ap = msg.get("ap")
	if app and ap is Dictionary:
		p.ap = {"ok": ap.get("ok") is bool and bool(ap.ok), "perm": ap.get("perm") is bool and bool(ap.perm)}
	else:
		p.erase("ap")

func _bk_gid_matches(msg: Dictionary) -> bool:
	# Beta 1.6.2 (10.1): bk_token nur für die eigene Partie – ein fremder Gastgeber lernt so höchstens ein Token, das bei ihm nichts gilt.
	var gid := str(welcome_extra.get("gid", ""))
	return gid != "" and msg.get("bk_gid") is String and str(msg.bk_gid) == gid

func _welcome(id: int, player_token: String) -> Dictionary:
	var w := {"t": "welcome", "id": id, "token": player_token, "host_name": host_name, "proto": NetProtocol.PROTO, "game": game_version}
	for key in ["gid", "gen", "epoch"]:      # Beta 1.6.1 (Lite ignoriert die Felder)
		if welcome_extra.has(key):
			w[key] = welcome_extra[key]
	return w

# ---------- Online-Spiel ----------

func open_online(relay_url: String) -> Error:
	# Raum beim Vermittler öffnen (zusätzlich zum WLAN). Fortschritt über online_changed.
	return _new_relay().open(relay_url)

# Mau-Mau Flip (Beta 1.6.1, Gastgeber-Übergabe): bestehenden Online-Raum als Gastgeber übernehmen (Gegenstück zu open_online,
# docs/module/uebergabe.md 3.2). conns: c der Online-Gäste aus dem Spielstand (ohne RELAY_CONN_BASE), sie bekommen 4012.
func open_online_existing(relay_url: String, room: String, room_token: String, conns: Array, max_c := 0, created_unix := 0) -> Error:
	return _new_relay().open_existing(relay_url, room, room_token, conns, max_c, created_unix)

func _new_relay() -> NetRelayHost:
	_close_relay()
	var r := NetRelayHost.new()
	r.name = "NetRelayHost"
	r.auto_poll = false
	r.game_version = game_version
	relay = r
	add_child(r)
	r.ws_opened.connect(_on_open)
	r.ws_message.connect(_on_message)
	r.ws_closed.connect(_on_closed)
	r.ws_dropped.connect(_on_dropped)
	r.log_line.connect(_log)
	r.state_changed.connect(func(st: String) -> void:
		if relay == r:
			_on_relay_state(st)
			online_changed.emit(st, r.info()))
	r.replaced.connect(func() -> void:
		if relay == r:
			_on_relay_replaced())
	r.needs_check.connect(func(i: Dictionary) -> void:
		if relay == r:
			_on_relay_check(i))
	return r

func _on_relay_state(st: String) -> void:
	# Beta 1.6.1: aufgeschobenes „Gastgeber wieder da“ (app_resumed)
	if not _unaway_pending:
		return
	if st == "stepped_down":
		_unaway_pending = false
	elif st in ["open", "failed", "off"]:
		_unaway_now()

func _on_relay_replaced() -> void:
	# Code 4000: Die Spielsteuerung tritt ab (HostTable → _frozen, dann Gast). Hört niemand zu, Online aufgeben wie bis 1.6.0.
	if replaced.get_connections().is_empty():
		relay.give_up("Der Online-Raum wird jetzt von einem anderen Gerät geführt.")
		return
	replaced.emit()

func _on_relay_check(i: Dictionary) -> void:
	# /info meldet einen Gastgeber: Die Spielsteuerung prüft per Probe (claim/step_down). Ohne Empfänger sofort anmelden.
	if online_needs_check.get_connections().is_empty():
		relay.claim()
		return
	online_needs_check.emit(i)

func close_online() -> void:
	# Online-Raum schließen: Online-Gäste bekommen „bye“, der Raum wird beendet. WLAN-Gäste bleiben.
	if relay == null:
		return
	var conns := _connected_conns().filter(func(c): return int(c) >= NetProtocol.RELAY_CONN_BASE)
	relay.send_text_many(conns, NetProtocol.encode({"t": "bye", "text": "Der Gastgeber hat das Online-Spiel geschlossen."}))
	_close_relay(true)
	online_changed.emit("off", {})
	_changed()

# Beta 1.6.1: Online-Raum für den Spielstand: {relay, room, token, conns, max_c, created_unix}; {} = kein Raum.
func online_room() -> Dictionary:
	if relay == null or relay.room == "" or relay.token == "":
		return {}
	var conns := []
	for p in players.values():
		if int(p.conn) >= NetProtocol.RELAY_CONN_BASE:
			conns.append(int(p.conn) - NetProtocol.RELAY_CONN_BASE)
	conns.sort()
	return {"relay": relay.relay_url, "room": relay.room, "token": relay.token, "conns": conns, "max_c": relay.max_c,
		"created_unix": relay.created_unix}

func online_state() -> String:
	return relay.state if relay != null else "off"

func online_info() -> Dictionary:
	return relay.info() if relay != null else {}

func _close_relay(end_room := false) -> void:
	# Vermittler trennen; Online-Spieler gelten als getrennt (Platz bleibt wie bei WLAN-Gästen). end_room (Beta 1.6.1): Raum beenden.
	if relay == null:
		return
	var r := relay
	relay = null
	if _unaway_pending and not _stopping:
		_unaway_now()                 # Beta 1.6.1: ohne Vermittler kommt kein Signal mehr, das „wieder da“ auslöst
	for c in [[r.ws_opened, _on_open], [r.ws_message, _on_message], [r.ws_closed, _on_closed], [r.ws_dropped, _on_dropped]]:
		if (c[0] as Signal).is_connected(c[1]):
			(c[0] as Signal).disconnect(c[1])
	r.close(end_room)
	for conn in _pending.keys():
		if int(conn) >= NetProtocol.RELAY_CONN_BASE:
			_pending.erase(conn)
	if not _stopping:
		for conn in _conn_player.keys():
			if int(conn) >= NetProtocol.RELAY_CONN_BASE:
				_on_closed(conn, NetProtocol.CLOSE_ROOM_ENDED, "Online geschlossen")
	_drop_node(r)

# Transport einer Verbindung: Vermittler (ab RELAY_CONN_BASE) oder WLAN-Server
func _link(conn: int) -> Object:
	return relay if conn >= NetProtocol.RELAY_CONN_BASE else server

func _send(conn: int, text: String) -> void:
	var t: Object = _link(conn)
	if t != null:
		t.send_text(conn, text)

func _send_many(conns: Array, text: String) -> void:
	var lan := []
	var online := []
	for c in conns:
		if int(c) >= NetProtocol.RELAY_CONN_BASE:
			online.append(c)
		else:
			lan.append(c)
	if server != null and not lan.is_empty():
		server.send_text_many(lan, text)
	if relay != null and not online.is_empty():
		relay.send_text_many(online, text)

func _close(conn: int, code: int, reason: String, grace_ms := 0) -> void:
	var t: Object = _link(conn)
	if t != null:
		t.close_ws(conn, code, reason, grace_ms)

func _active() -> int:
	var n := 0
	if server != null:
		n += int(server.stats().get("ws_active", 0))
	if relay != null:
		n += int(relay.stats().get("ws_active", 0))
	return n

# ---------- intern ----------

func _changed(now := false) -> void:
	rev += 1
	_dirty = true
	if now:
		_dirty = false
		_publish()

func _publish() -> void:
	# Lobby verteilen (nur ohne laufende Partie; dann sendet die Spielsteuerung „state“) und /info sowie die Suche auffrischen.
	if server == null and relay == null:
		return
	var i := info()
	if server != null:
		server.set_info(i)
	if discovery != null:
		discovery.set_info(i)
	if auto_lobby and not running:
		broadcast(lobby_message())
	elif running:
		var wait := waiting_ids()
		if not wait.is_empty():
			var text := NetProtocol.encode(waiting_message())
			for id in wait:
				if int(players[id].conn) >= 0:
					_send(players[id].conn, text)
	lobby_changed.emit()

static func _drop_node(n: Node) -> void:
	if n.is_inside_tree():
		n.queue_free()
	else:
		n.free()

func _connected_conns() -> Array:
	var out := []
	for p in players.values():
		if int(p.conn) >= 0:
			out.append(p.conn)
	return out

func _names() -> Array:
	return players.values().map(func(p): return p.name)

func _next_seat() -> int:
	var seat := 0
	for p in players.values():
		seat = maxi(seat, int(p.seat) + 1)
	return seat

func _compact_seats() -> void:
	var ids := ordered_ids()
	for i in range(ids.size()):
		players[ids[i]].seat = i

func _log(text: String) -> void:
	log_line.emit(text)
