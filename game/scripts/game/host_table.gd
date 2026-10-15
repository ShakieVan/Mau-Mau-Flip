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
# App-Wechsel (Beta 1.3.3): „away“/„back“ der Gäste und des Gastgebers (NetHostSession.player_away) landen als away:true in
# view.players (Gastgeber-Eintrag zusätzlich host:true); „back“ schickt dem Gast den vollen Stand. Der Knopf „Computer für … spielen
# lassen“ (substitutable_seats) kam bis Beta 1.4.1 erst nach sub_offer_ms (30 s); seit Beta 1.4.2 ist sub_offer_ms 0: Jeder abwesende Gast
# (absent_seats) bekommt sofort „Computer übernimmt“ und „Aus dem Spiel nehmen“. Ein Gast in einer anderen App wird nie automatisch vertreten.
# Plätze mitten im Spiel (Beta 1.4.2, docs/module/dazuholen.md): seat_in(id, at) holt einen Wartenden (NetHostSession-Warteliste) an den
# Tisch, add_bot_at(at) einen Computergegner, remove_seat(seat) nimmt einen Platz heraus (nie den Gastgeber). Die Aufträge warten in
# _seat_ops, bis MauGame es erlaubt (zwischen zwei Zügen bzw. am Rundenende; den Platz am Zug nimmt man sofort heraus), und gehen
# jeweils als eigener Stand hinaus (nie zusammen mit Ereignissen in alter Platznummerierung). Der Neue bekommt {t:"start", seat},
# der Entfernte „bye“.
# Speicherstand nach jeder Änderung (user://laufende_partie.json), resume() setzt eine Partie samt Token der Gäste fort.
# Mau-Mau Flip (Beta 1.6.1, Gastgeber-Übergabe, docs/module/uebergabe.md Abschnitte 1, 2, 4.1, 4.5, 4.6):
#  - Speicherstand als MatchSnapshot (format 2) in TableSource.NET_SAVE_PATH; jeder Menschenplatz hat dauerhaft ein Token, auch der
#    Gastgeber (seats[host_seat].token, entsteht in start()). Abstammung: gid (Partie), gen (steigt genau bei Wechsel von host_seat),
#    epoch (neu je gen), parent, seq (je Änderung).
#  - Nach jeder Änderung zuerst Sicherung ({t:"bk"} an App-Gäste mit hello.bk) und eigene Datei, danach die Sichten; nach
#    alive_ms Stille {t:"alive"}. backup_enabled schaltet die Sicherung ab (Tests mit vielen Zügen je pump()).
#  - resume(data, my_seat): eigener Zweig (my_seat < 0 oder = host_seat) oder Übernahme (gen + 1); Warteliste und Vertretungen
#    kommen mit; Einschwingzeit (_settling, höchstens settle_max_ms): Bots und Aktionen warten, bis die Erben zurück sind.
#  - Eingefroren (_frozen): bei Code 4000 (replaced) und während einer Übergabe – kein Speichern, kein Verteilen, keine Bots, keine
#    Meldungen „getrennt“. Danach Signal stepped_down; die Oberfläche (HostSwitch) ruft handover_shutdown() und meldet sich als Gast an.
#  - handover_to(seat): geplante Übergabe; Abstammungsregel bei hello.bk (jüngerer Zweig → handover own:true); Fehlschlag nach
#    handover_timeout_ms prüft das Socket (check_now) und taut auf.
#  - Vorsichtiges Neuverbinden: online_check (Probe als Gast durch die Oberfläche), dann probe_done(). Ohne Empfänger: sofort anmelden.
#  - Schließen der App beendet den Online-Raum nicht (Übernahme möglich); nur leave() („Tisch verlassen“) schickt {k:"end"}.
# Mau-Mau Flip (Beta 1.6.2, WLAN und Spiel-WLAN, docs/module/uebergabe.md 10.2/10.3/10.7/10.9–10.11):
#  - Ersatz-Rangfolge ohne WLAN-Sperre: erst Link „wlan“, dann „online“ (nur mit Raum); im Spiel-WLAN (wlan.ap) je Gruppe zuerst
#    Geräte, die eines öffnen können (ap.perm vor ap.ok). Geplante Übergabe auch im WLAN, Spiel-WLAN und gemischt (how lan/qr/online).
#  - Bestätigte Übergabe: Erst handover_ok des Ziels (bzw. 4000) löst move an die eigenen WLAN-Gäste aus, dann session.drain(500),
#    dann stepped_down; step_target sagt der Oberfläche, wohin ({how, name, addr, port, room, relay}).
#  - Stand: seats[*].addr/hp/ap, wlan {port, addrs, ap, ap_seat, past}; refresh_addrs() nach Neu-Binden/Spiel-WLAN (GameWifiWatch).
#  - Browser-Gäste bekommen {t:"hosts"} (Erben mit Link „wlan“ als http://addr:hp/, Raum-Link, ap, ap_name); frühere Gastgeber-Adressen
#    (wlan.past, Wächter-Funde) sind als Herkunft erlaubt (session.set_extra_origins).
#  - seat_assign(): Wartenden auf den Platz eines getrennten Mitspielers setzen; nach resume() ist die Warteliste offen, solange ein
#    Menschenplatz getrennt ist.
#  - Gastgeber-Wächter (_on_rival): zwei Gastgeber derselben gid im Netz – mehr verbundene Menschen, dann gen, dann epoch gewinnt; der
#    Verlierer tritt nach rival_confirm gleichen Scans ab (move lan an seine Gäste), der Gewinner hebt seine gen über die des anderen;
#    der Verlierer wartet dafür (höchstens rival_gen_wait weitere Scans), sonst holte die Abstammungsregel seinen Zweig zurück.
# Mau-Mau Flip (Beta 1.6.3, Easter Eggs Teil 2 „Necken“, docs/module/eastereggs2.md Abschnitte 1, 4 und 6):
#  - {t:"fx"} eines Gasts bzw. send_fx() des Gastgebers prüft tease (TeaseRules, Uhr _now_ms) gegen den Tisch (_fx_table). Angenommen:
#    {t:"fx", k, from, to?, r?} per send_many an alle sitzenden entfernten Menschen (nie an die Warteliste) und fx_event am eigenen Tisch;
#    abgelehnt mit late/busy/rate: {t:"fx_no", why} nur an den Absender (Gastgeber: fx_refused), sonst still. Eingefroren, in der
#    Einschwingzeit und während der Wächter-Prüfung nach der Rückkehr nimmt er nichts an.
#  - fx_pref je Spieler-id (_fx_off_ids, nur im Speicher; nach einer Übernahme schicken die Gäste ihn mit dem nächsten welcome neu):
#    Ändert sich die Liste der Plätze (auch durch Platzwechsel, _after_distribute), geht {t:"fx_offs"} an alle Sitzenden; ein
#    zurückkehrender oder dazugeholter Gast bekommt sie einzeln. Kein _changed, kein _persist, kein bk, kein seq.
# Mau-Mau Flip (Beta 1.6.6, Furzkissen, docs/module/eastereggs2.md Abschnitt 12):
#  - fx kissen {to, reveal}: tease prüft (busy = liegt schon eins, rate = Sperre des Legers), _cushion_place lost die Sperre (1–3 min,
#    fx_rand) aus und bestätigt nur dem Leger. Ausgelöst wird in GameTable._apply bei der nächsten angenommenen Lege-/Zieh-Aktion des
#    Ziels (auch Bots); _cushion_pop schickt kissen_pop an alle Sitzenden, geheim ohne from (nur der Leger bekommt from). Offene Kissen
#    stehen nicht im Speicherstand und nicht in der Sicherung: Übergabe, Rundenende und seats lassen sie verfallen.

signal stepped_down(new_host: String)         # Beta 1.6.1: ein anderes Gerät führt jetzt das Spiel ("" = Name unbekannt)
signal online_check(info: Dictionary)         # Beta 1.6.1: /info meldet einen Gastgeber – Probe als Gast, dann probe_done()

const BOT_NAMES := ["Minka", "Mogli", "Luna", "Tiger", "Socke", "Krümel", "Flocke", "Pünktchen", "Schnurri", "Mieze"]

var session: NetHostSession
var rules := RuleConfig.new()
var use_discovery := true
var discovery_port := NetProtocol.DISCOVERY_PORT
var web_zip_path := "res://assets/web.zip"
var threaded := true             # Netz-Thread des Servers (Modul D)
var auto_substitute_s := 0.0     # 0 = warten (Standard); > 0: Bot übernimmt einen getrennten Menschen am Zug nach so vielen s
var sub_offer_ms := NetProtocol.SUB_OFFER_MS   # so lange weg/getrennt, bis „Computer für … spielen lassen“ erscheint

var _seat_ids: Array = []        # Platz -> Spieler-id der Sitzung
var _seq := {}                   # Spieler-id -> letzte seq seiner Aktionen (seq_ack)
var _waiting_seat := -1          # getrennter Mensch am Zug
var _wait_since := 0
var _seat_ops: Array = []         # aufgeschobene Platzaufträge [{op: "in"|"bot"|"out", id, at, name}] (Beta 1.4.2)
var _ops_busy := false
var _gone_names := {}             # in dieser Partie herausgenommene Namen (neue Computergegner heißen anders)

# --- Gastgeber-Übergabe (Beta 1.6.1) ---
var backup_enabled := true        # Sicherung an App-Gäste ({t:"bk"}, {t:"alive"})
var alive_ms := NetProtocol.BACKUP_ALIVE_MS
var settle_max_ms := NetProtocol.TAKEOVER_SETTLE_MAX_MS
var handover_within_ms := NetProtocol.HANDOVER_WITHIN_MS
var handover_timeout_ms := NetProtocol.HANDOVER_TIMEOUT_MS
var clock := Callable()           # Tests: () -> Wanduhr in s (sonst Time.get_unix_time_from_system)
var ms_clock := Callable()        # Tests: () -> Monotonuhr in ms (sonst Time.get_ticks_msec)
var gid := ""                     # Kennung der Partie (bleibt über alle Übergaben)
var gen := 0                      # Generation des Gastgebers (steigt genau bei Wechsel von host_seat)
var epoch := ""                   # neu je gen
var parent: Array = NetProtocol.BK_NONE.duplicate()   # [gen, epoch, seq] des Stands, aus dem dieser Zweig entstand
var seq := 0                      # Zähler der Schnappschüsse (je _changed)
var _frozen := false              # eingefroren: replaced oder Übergabe läuft
var _settling := false            # Einschwingzeit nach resume()
var _settle_until := 0
var _settle_tokens: Array = []    # auf deren hello wartet die Einschwingzeit
var _settle_note: Array = []      # Meldung an alle am Ende der Einschwingzeit (Bausteine, announce_after_settle)
var _handover := {}               # laufende Übergabe {seat, id, name, own, until, checking}
var _own_tried := {}              # "Token:gen" -> true: handover own:true höchstens einmal je Gast und gen
var _last_bk_ms := 0              # zuletzt bk/alive an die App-Gäste
var _step_note := {}              # stepped_down wartet auf das Ende von session.poll() {name}
var _addrs: Array = []            # eigene Adressen für wlan.addrs (einmal je start/resume, nicht je Änderung: JNI auf Android)

# --- WLAN und Spiel-WLAN (Beta 1.6.2) ---
var step_target := {}             # nach stepped_down: wohin es weitergeht {how:"lan"|"online"|"qr", name, addr, port, room, relay}
var hotspot_check := Callable()   # () -> bool „eigenes Spiel-WLAN offen“: setzt der GameWifiWatch des Tisches (Gerätetest 1.6.2, F1), Tests
                                  # spritzen es ein; ungültig: own_game_wifi_open()
var wake_pause_ms := NetProtocol.WAKE_PAUSE_MS   # Gerätetest 1.6.2 (B1): so lange im Hintergrund, dann beim Zurückkommen erst der Wächter
var wake_check_ms := NetProtocol.WAKE_CHECK_MS   # … und so lange Aktionen und Bots anhalten, bis seine Antworten da sind
var _paused_at := -1              # App ging in den Hintergrund (ms), −1 = vorn
var _wake_until := 0              # Wächter-Prüfung nach der Rückkehr läuft bis dahin (ms), 0 = keine
var rival_confirm := 2            # Gastgeber-Wächter: so viele gleiche Scans hintereinander, bis der Verlierer abtritt
var rival_gen_wait := 4           # … und höchstens so viele weitere, bis der Gewinner seine gen angehoben hat (Gegenprüfung 1.6.2)
var drain_ms := 500               # vor dem Abtreten: so lange darf das Hinausschreiben dauern
var step_grace_ms := 300          # … danach noch so lange (Frames laufen weiter, eingefroren), bis stepped_down den Server schließt
var _step_at := 0                 # stepped_down frühestens dann (ms)
var scan_ms := -1                 # Wächter-Scan der Suche (−1 = Standard NetProtocol.HOST_SCAN_MS, 0 = aus)
var scan_ports: Array = []        # Tests: UDP-Ports der Wächter-Anfragen (mehrere Gastgeber auf 127.0.0.1)
var scan_probe_local := false     # Tests: auch 127.0.0.1 fragen
var scan_broadcast := true        # Tests: false = nur Unicast
var _ap := false                  # die Partie läuft in einem Spiel-WLAN (wlan.ap)
var _ap_seat := -1                # Platz, dessen Handy das Spiel-WLAN führt (−1 = keins)
var _past: Array = []             # frühere Gastgeber-Adressen dieser Partie "ip:port" (wlan.past, höchstens PAST_MAX)
var _addrs_port := 0              # Port zu _addrs (für past beim Neu-Binden)
var _rival := {}                  # Wächter: {sid, lose, n} – Ergebnis der letzten Scans
var _join_auto := false           # Warteliste nach resume() offen, solange ein Menschenplatz getrennt ist
var _join_restore := false        # … danach gilt wieder dieser Wert
var _hosts_key := ""              # zuletzt verschickte hosts-Liste (JSON)
var _scan_key := ""               # zuletzt gesetzte Unicast-Ziele des Wächters
var _step_drain := false          # vor stepped_down erst session.drain()

# --- Necken (Beta 1.6.3) ---
var _fx_off_ids := {}             # Spieler-id -> true: Necken aus (fx_pref; nur im Speicher)
var _fx_offs_key := ""            # zuletzt an die Sitzenden verschickte Liste fx_offs (JSON); "" = noch keine


func _init() -> void:
	save_path = NET_SAVE_PATH       # Beta 1.6.1: eigene Datei der Netzpartie


# Lobby eröffnen. host_name "" = Name aus den Einstellungen.
func open(host_name := "", port_first := NetProtocol.PORT, port_last := NetProtocol.PORT_LAST) -> Error:
	return _open_session(host_name, port_first, port_last, false)


func _open_session(host_name: String, port_first: int, port_last: int, quiet: bool) -> Error:
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
	session.player_away.connect(_on_away)
	session.message.connect(_on_message)
	session.lobby_changed.connect(func() -> void: lobby_changed.emit(session.lobby_message()))
	session.replaced.connect(_on_replaced)
	session.online_needs_check.connect(_on_needs_check)
	var err := session.start(host_name if host_name != "" else _own_name(), port_first, port_last, threaded)
	if err != OK:
		_close_session()
		if not quiet:
			notice.emit(I18n.t("Das Spiel ließ sich nicht eröffnen (Port %d–%d belegt?).") % [port_first, port_last])
		return err
	session.set_rules(rules.to_dict())
	if session.discovery != null:
		session.discovery.rival.connect(_on_rival)     # Beta 1.6.2: Gastgeber-Wächter (10.11)
		session.discovery.ports = scan_ports.duplicate()
		session.discovery.probe_local = scan_probe_local
		session.discovery.use_broadcast = scan_broadcast
		if scan_ms >= 0:
			session.discovery.scan_ms = scan_ms
	_scan_key = ""
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
		bot_name = free_bot_name()
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
		var tok := str(p.token)
		if id == session.host_id:
			tok = _new_token()     # Beta 1.6.1: auch der Gastgeber-Platz hat ein Token (Rückkehr als Gast nach einer Übergabe)
		list.append({"name": str(p.name), "kind": "bot" if str(p.kind) == "bot" else "human", "host": id == session.host_id,
			"id": id, "net": str(p.kind), "token": tok})
	_create_game(rules, list, rng_seed)
	for s in _seat_ids.size():
		game.set_connected(s, bool(session.player(_seat_ids[s]).connected))
		_note_link(s)
	_seq.clear()
	_waiting_seat = -1
	_reset_handover_state()
	gid = NetProtocol.new_gid()
	gen = 1
	epoch = NetProtocol.new_epoch()
	parent = NetProtocol.BK_NONE.duplicate()
	seq = 0
	_last_bk_ms = _now_ms()
	_note_addrs()
	_past = []
	_ap = false
	_ap_seat = -1
	_update_ap(false)
	_apply_origins()
	step_target = {}
	_join_auto = false
	_update_welcome()
	_hosts_key = ""
	tease.reset()                 # Beta 1.6.3
	_fx_offs_key = ""
	if not _fx_offs.is_empty():   # die Liste der neuen Partie berechnet _fx_sync_offs nach dem ersten Verteilen
		_fx_offs = []
		fx_offs_changed.emit([])
	session.send_start()
	game_started.emit(host_seat)
	_begin_round()
	_send_hosts()                 # Beta 1.6.2: Browser-Gäste kennen gid/gen nur aus hosts (auch mit leerer Liste)
	return true


# Partie fortsetzen (Daten aus TableSource.load_saved() bzw. einer Sicherung, MatchSnapshot): Sitzung neu eröffnen, Gäste mit ihren
# Token eintragen (getrennt, bis sie zurückkommen), Computergegner neu anlegen.
# Beta 1.6.1: my_seat < 0 oder = host_seat: eigener Zweig (gen, epoch bleiben; WLAN zuerst auf dem gespeicherten Port). Sonst
# Übernahme durch den Gast auf my_seat: host_seat wechselt, der alte Gastgeber-Platz wird ein getrennter App-Gast mit seinem Token,
# parent = alter Stand, gen + 1, neue epoch. Alle Tokens bleiben an ihren Plätzen. Warteliste, join_open und Vertretungen kommen mit;
# ein Online-Raum wird übernommen (open_online_existing). Danach Einschwingzeit (Bots und Aktionen warten auf die Erben).
func resume(data: Dictionary, my_seat := -1, port_first := NetProtocol.PORT, port_last := NetProtocol.PORT_LAST) -> Error:
	var snap := MatchSnapshot.clean(data)
	if snap.is_empty():
		return ERR_INVALID_DATA
	var saved: Array = snap.seats
	var old_hs := int(snap.host_seat)
	if my_seat >= saved.size():
		return ERR_INVALID_PARAMETER
	var takeover := my_seat >= 0 and my_seat != old_hs
	if takeover and (str(saved[my_seat].get("kind", "")) == "bot" or str(saved[my_seat].get("token", "")) == ""):
		return ERR_INVALID_PARAMETER
	var hs := my_seat if takeover else old_hs
	var host_name := str(saved[hs].name)
	rules = RuleConfig.from_dict((snap.game as Dictionary).get("config", {}))
	var err := ERR_UNAVAILABLE
	var wp := int(snap.wlan.port)
	if not takeover and wp > 0 and wp >= port_first and wp <= port_last:
		err = _open_session(host_name, wp, wp, true)     # gleiche Adresse: App- und Browser-Gäste finden von selbst zurück
	if err != OK:
		err = open(host_name, port_first, port_last)
	if err != OK:
		return err
	_restore_seats(snap)
	var has_room := not (snap.online as Dictionary).is_empty()
	var wx := _wlan_extra(snap, data)
	if takeover:
		for s in seats.size():
			seats[s].host = s == hs
		seats[old_hs].net = "app"            # der alte Gastgeber kommt mit der App zurück
		# Beta 1.6.2 (10.2): „online“ nur, wenn die Partie einen Raum hat – sonst stimmen Rangfolge und how einer Übergabe an ihn nicht
		seats[old_hs].link = "online" if has_room else "wlan"
		if not has_room:
			var olds: Array = (snap.wlan as Dictionary).get("addrs", [])
			if not olds.is_empty() and NetProtocol.ipv4_to_int(str(olds[0])) > 0:
				seats[old_hs].addr = str(olds[0])
			if int(snap.wlan.port) > 0:
				seats[old_hs].hp = int(snap.wlan.port)
		host_seat = hs
	var ids: Array = []
	for s in seats.size():
		var p: Dictionary = seats[s]
		var id := -1
		if s == host_seat:
			id = session.host_id
		elif str(p.kind) == "bot":
			id = session.add_local_player(str(p.name), "bot")
		else:
			id = session.restore_player(str(p.name), str(p.get("net", "app")), str(p.get("token", "")))
		p.id = id
		ids.append(id)
	session.set_seat_order(ids)
	_seat_ids = ids
	for w in snap.waiting:
		session.restore_player(str(w.name), str(w.net), str(w.token), true)
	# Beta 1.6.2 (10.10): Nach einer Übernahme oder einem Umzug (anderer Port, keine der früheren Adressen) ist die Warteliste offen,
	# solange ein Menschenplatz getrennt ist (Browser-Gäste kommen dann als Neue), danach wieder wie gespeichert (_poll_join_auto).
	# Fortsetzen an derselben Adresse: wie gespeichert – alle Gäste finden mit ihrem Token zurück, Neue bekommen „reject running“.
	_join_restore = bool(snap.join_open)
	_join_auto = takeover or _moved_since(snap)
	session.join_open = true if _join_auto else _join_restore
	game = MauGame.from_dict(snap.game)
	if game.seat_count() != seats.size():
		_close_session("", false)
		return ERR_INVALID_DATA
	game.set_host(host_seat)
	for s in seats.size():
		game.set_connected(s, s == host_seat or str(seats[s].kind) == "bot")
	for s in snap.substitute:
		if _is_remote(int(s)):
			_substitute[int(s)] = true
	_gone_names.clear()
	for n in snap.gone_names:
		_gone_names[str(n)] = true
	_seq.clear()
	_waiting_seat = -1
	_reset_handover_state()
	gid = str(snap.gid) if str(snap.gid) != "" else NetProtocol.new_gid()
	gen = maxi(int(snap.gen), 1)
	epoch = str(snap.epoch) if str(snap.epoch) != "" else NetProtocol.new_epoch()
	parent = (snap.parent as Array).duplicate()
	seq = int(snap.seq)
	if takeover:
		parent = [gen, epoch, seq]
		gen += 1
		epoch = NetProtocol.new_epoch()
	# Beta 1.6.2: Spiel-WLAN und frühere Gastgeber-Adressen (Herkunft der Lite-Seiten, 10.9)
	_ap = bool(wx.ap)
	_ap_seat = int(wx.ap_seat) if _ap else -1
	if _ap and (_ap_seat < 0 or _ap_seat >= seats.size()):
		_ap_seat = old_hs                    # Stand einer 1.6.1-App ohne ap_seat: der (alte) Gastgeber führte das Netz
	_past = []
	for p in wx.past:
		_add_past_entry(str(p))
	var wp_old := int(snap.wlan.port)
	if wp_old > 0:
		for a in (snap.wlan as Dictionary).get("addrs", []):
			_add_past(str(a), wp_old)
	_note_addrs()
	_update_ap(false)
	_apply_origins()
	_hosts_key = ""
	step_target = {}
	_update_welcome()
	# Einschwingzeit: auf die Erben und alle, die die letzte Sicherung hatten (außer dem eigenen Platz)
	_settle_tokens = []
	for t in (snap.heirs as Array) + (snap.bk_to as Array):
		if str(t) != "" and str(t) != str(seats[host_seat].get("token", "")) and not _settle_tokens.has(str(t)):
			_settle_tokens.append(str(t))
	_settling = not _settle_tokens.is_empty()
	_settle_until = _now_ms() + settle_max_ms
	session.set_running(true)
	var o: Dictionary = snap.online
	if not o.is_empty() and str(o.relay) != "" and str(o.token) != "":
		session.open_online_existing(str(o.relay), str(o.room), str(o.token), o.conns, int(o.max_c), int(o.created_unix))
	_last_bk_ms = _now_ms()
	_plan_dirty = true
	tease.reset()                 # Beta 1.6.3: neue Sitzung, neue Spieler-ids – die Gäste melden fx_pref nach ihrem welcome neu
	_fx_off_ids.clear()
	_fx_offs = []
	_fx_offs_key = ""
	game_started.emit(host_seat)
	_changed([])
	_send_hosts()                 # Beta 1.6.2: geht nach jedem welcome an zurückkehrende Browser-Gäste (neue gen)
	return OK


# Ein Computergegner spielt für diesen Platz, bis der Mensch zurückkommt bzw. selbst wieder handelt.
func substitute_bot(seat: int) -> void:
	if game == null or _frozen or seat < 0 or seat >= seats.size() or seat == host_seat or is_bot(seat):
		return
	_substitute[seat] = true
	_waiting_seat = -1
	_tell_all([I18n.part("Ein Computergegner spielt für %s.", [seat_name(seat)])])
	_changed([])


# Gäste ohne Vertretung, die getrennt oder kurz in einer anderen App sind (Hinweis „… ist kurz weg“ am Tisch des Gastgebers)
func absent_seats() -> Array:
	var out: Array = []
	if game == null:
		return out
	for s in seats.size():
		if _is_remote(s) and not _substitute.has(s) and (not bool(game.connected[s]) or is_away(s)):
			out.append(s)
	return out


# … davon die, die schon sub_offer_ms weg sind: erst dann der Knopf „Computer für … spielen lassen“ (Beta 1.3.3)
func substitutable_seats() -> Array:
	return absent_seats().filter(func(s): return absent_ms(s) >= sub_offer_ms)


# Platz kurz in einer anderen App („away“)?
func is_away(seat: int) -> bool:
	return session != null and seat >= 0 and seat < _seat_ids.size() and session.is_away(int(_seat_ids[seat]))


# Seit wann (ms) ein Platz weg oder getrennt ist; 0 = da.
func absent_ms(seat: int) -> int:
	return session.gone_ms(int(_seat_ids[seat])) if session != null and seat >= 0 and seat < _seat_ids.size() else 0


# Getrennter Mensch, auf dessen Zug das Spiel wartet (−1 = keiner)
func waiting_seat() -> int:
	return _waiting_seat


func is_substituted(seat: int) -> bool:
	return _substitute.has(seat)


# --- Plätze mitten im Spiel (Beta 1.4.2) ---

# Neue dürfen auf die Warteliste (solange beim Gastgeber das Feld „Mitspieler“ offen ist).
func set_join_open(on: bool) -> void:
	if _join_auto:
		_join_restore = on        # Beta 1.6.2: nach einer Übernahme bleibt sie offen, solange ein Menschenplatz getrennt ist
		on = true
	if session != null:
		session.join_open = on


# Wartende Gäste (Spieler-ids der Sitzung) in der Reihenfolge ihrer Anmeldung.
func waiting_ids() -> Array:
	return session.waiting_ids() if session != null else []


# Wartenden an Stelle at (0 … Spielerzahl, Index in der neuen Sitzordnung) an den Tisch holen. false = nicht möglich.
func seat_in(id: int, at: int) -> bool:
	if game == null or _frozen or session == null or not session.is_waiting(id) or _queued(id) or not _room_for_one():
		return false
	_seat_ops.append({"op": "in", "id": id, "at": at, "name": str(session.player(id).name)})
	_run_seat_ops()
	return true


# Computergegner an Stelle at dazuholen. false = kein Platz frei.
func add_bot_at(at: int, bot_name := "") -> bool:
	if game == null or _frozen or session == null or not _room_for_one():
		return false
	if bot_name == "":
		bot_name = free_bot_name()
	_seat_ops.append({"op": "bot", "id": -1, "at": at, "name": bot_name if bot_name != "" else "Computer"})
	_run_seat_ops()
	return true


# Name für einen neuen Computergegner (Gerätetest 1.4.2: nach dem Herausnehmen von „Mogli“ kam wieder ein „Mogli“): weder am Tisch,
# auf der Warteliste, in offenen Aufträgen noch in dieser Partie schon herausgenommen. Sind alle verbraucht, wieder ein
# herausgenommener; zuletzt „Computer“ (NetSession macht ihn eindeutig).
func free_bot_name() -> String:
	var taken: Array = session.players.values().map(func(p): return str(p.name)) if session != null else []
	for o in _seat_ops:
		taken.append(str(o.get("name", "")))
	for s in seats.size():
		taken.append(seat_name(s))
	for pass_ in 2:
		for n in BOT_NAMES:
			if not taken.has(n) and (pass_ == 1 or not _gone_names.has(n)):
				return n
	return "Computer"


# Platz herausnehmen (Mensch oder Computer, nie der Gastgeber). Ist der Platz am Zug, sofort; sonst nach diesem Zug.
func remove_seat(seat: int) -> bool:
	if game == null or _frozen or seat < 0 or seat >= seats.size() or seat == host_seat:
		return false
	var id := int(_seat_ids[seat])
	if _queued(id):
		return false
	_gone_names[seat_name(seat)] = true
	_seat_ops.append({"op": "out", "id": id, "at": seat, "name": seat_name(seat)})
	_run_seat_ops()
	return true


# Wartenden ablehnen: er bekommt „bye“ und verschwindet von der Warteliste.
func reject_waiting(id: int) -> void:
	cancel_seat_op(id)
	if session != null and session.is_waiting(id):
		session.remove_player(id, "Der Gastgeber hat dich nicht dazugeholt.")


# Aufgeschobenen Auftrag zurücknehmen (Spieler-id; Computergegner: −1 nimmt alle noch nicht angelegten zurück).
func cancel_seat_op(id: int) -> void:
	_seat_ops = _seat_ops.filter(func(o): return int(o.id) != id)


# Aufträge, die noch warten (Anzeige „Kommt nach diesem Zug dazu“ / „Geht nach diesem Zug“): [{op, id, at, name}].
func pending_seat_ops() -> Array:
	return _seat_ops.duplicate(true)


# Wartet ein Auftrag für diesen Spieler (id der Sitzung)?
func seat_op_of(id: int) -> String:
	for o in _seat_ops:
		if int(o.id) == id:
			return str(o.op)
	return ""


# Karten, die ein Dazugeholter jetzt bekäme (Rückfrage „… bekommt 5 Karten“); am Rundenende 0.
func join_card_count() -> int:
	return game.join_card_count() if game != null else 0


func _queued(id: int) -> bool:
	return seat_op_of(id) != ""


func _room_for_one() -> bool:
	var adds := _seat_ops.filter(func(o): return str(o.op) != "out").size()
	return seats.size() + adds < MauGame.MAX_PLAYERS


# Aufgeschobene Aufträge der Reihe nach ausführen, solange das Regelwerk es erlaubt. Jeder ausgeführte Auftrag geht als eigener Stand
# hinaus (_changed in _seat_insert/_seat_remove), danach kommt der nächste.
func _run_seat_ops() -> void:
	if _ops_busy or _frozen or game == null or session == null:
		return
	_ops_busy = true
	while not _seat_ops.is_empty() and game != null:
		var o: Dictionary = _seat_ops[0]
		if str(o.op) == "out":
			var s := _seat_ids.find(int(o.id))
			if s < 0 or s == host_seat:
				_seat_ops.pop_front()
				continue
			if not game.can_remove_now(s):
				break
			_seat_ops.pop_front()
			_seat_remove(s)
		else:
			if str(o.op) == "in" and not session.is_waiting(int(o.id)):
				_seat_ops.pop_front()            # inzwischen abgelehnt oder gestrichen
				continue
			if not game.can_change_seats():
				break
			_seat_ops.pop_front()
			_seat_insert(o)
	_ops_busy = false


func _seat_insert(o: Dictionary) -> void:
	var bot := str(o.op) == "bot"
	var id := int(o.id)
	if bot:
		id = session.add_local_player(str(o.name), "bot")
		if id < 0:
			return
	var p: Dictionary = session.player(id)
	var at := clampi(int(o.at), 0, seats.size())
	var r := game.insert_player(at, {"name": str(p.name), "kind": "bot" if bot else "human"})
	if not bool(r.ok):
		if bot:
			session.remove_player(id)
		return
	seats.insert(at, {"name": str(p.name), "kind": "bot" if bot else "human", "host": false, "id": id, "net": str(p.kind),
		"token": str(p.get("token", ""))})
	_seat_ids.insert(at, id)
	var sub := {}
	for s in _substitute:
		sub[int(s) + 1 if int(s) >= at else int(s)] = true
	_substitute = sub
	if _ap_seat >= at:
		_ap_seat += 1                # Beta 1.6.2: Platz, der das Spiel-WLAN führt, rückt mit
	host_seat = game.host
	_waiting_seat = -1
	_plan_dirty = true
	game.set_connected(at, bool(p.get("connected", true)))
	_note_link(at)
	session.set_seat_order(_seat_ids)            # holt ihn auch von der Warteliste (waiting weg)
	if not bot:
		session.send_to(id, {"t": "start", "seat": at})
	_tell_all([I18n.part("%s spielt jetzt mit.", [str(p.name)])])
	_changed(r.events)
	if not bot:
		_fx_offs_to(id)              # Beta 1.6.3: der Neue kennt die Liste noch nicht (sein welcome kam auf der Warteliste)


func _seat_remove(s: int) -> void:
	var id := int(_seat_ids[s])
	var gone := seat_name(s)
	var r := game.remove_player(s)
	if not bool(r.ok):
		return
	seats.remove_at(s)
	_seat_ids.remove_at(s)
	var sub := {}
	for k in _substitute:
		if int(k) != s:
			sub[int(k) - 1 if int(k) > s else int(k)] = true
	_substitute = sub
	host_seat = game.host
	if _ap_seat == s:
		_ap_seat = host_seat if _ap else -1   # Beta 1.6.2: wer das Spiel-WLAN führte, ist weg – bei Verlust öffnet der Gastgeber neu
	elif _ap_seat > s:
		_ap_seat -= 1
	_waiting_seat = -1
	_plan_dirty = true
	_seq.erase(id)
	_fx_off_ids.erase(id)        # Beta 1.6.3
	session.remove_player(id, "Der Gastgeber hat dich aus dem Spiel genommen.")
	session.set_seat_order(_seat_ids)
	_tell_all([I18n.part("%s ist nicht mehr dabei.", [gone])])
	_changed(r.events)


func _after_distribute() -> void:
	_send_hosts()                 # Beta 1.6.2: Erben-Liste für Browser-Gäste, nur bei Änderung
	_fx_sync_offs()               # Beta 1.6.3: fx_offs nach Platzwechseln (neue Nummern), nur bei Änderung
	if not _seat_ops.is_empty():
		_run_seat_ops()


func act(action: Dictionary) -> void:
	if game == null:
		notice.emit("Die Partie hat noch nicht begonnen.")
		return
	var wait := _hold_reason()
	if wait != "":
		notice.emit(I18n.t(wait))
		return
	var r := _apply(host_seat, action)
	if not bool(r.ok):
		notice.emit(I18n.reason(r))


# Zurück in die Lobby (Partie verwerfen, Spieler bleiben).
func back_to_lobby() -> void:
	game = null
	_plan = {}
	_seat_ops.clear()
	_substitute.clear()
	_reset_handover_state()
	gid = ""
	_join_auto = false
	_hosts_key = ""
	tease.reset()                 # Beta 1.6.3
	_fx_offs = []
	_fx_offs_key = ""
	if session != null:
		session.set_game_mark("", 0, "")
		session.send_hosts({})
		session.set_running(false)
	if autosave:
		clear_saved(save_path)


# „Tisch verlassen“: ausdrückliches Ende – „bye“ an alle, der Online-Raum wird beendet, der Speicherstand gelöscht.
func leave() -> void:
	_close_session()
	if autosave:
		clear_saved(save_path)


# end_room (Beta 1.6.1): Online-Raum beim Vermittler beenden ({k:"end"}); beim Abtreten (handover_shutdown) bleibt er offen.
func _close_session(text := "Der Gastgeber hat das Spiel beendet.", end_room := true) -> void:
	game = null
	_plan = {}
	_seat_ops.clear()
	_substitute.clear()
	_reset_handover_state()
	if session != null:
		session.stop(text, end_room)
		if session.is_inside_tree():
			session.queue_free()
		else:
			session.free()
		session = null


# --- Gastgeber-Übergabe (Beta 1.6.1, docs/module/uebergabe.md) ---

# Stand [gen, epoch, seq] dieses Gastgebers.
func mark() -> Array:
	return [gen, epoch, seq]


func is_frozen() -> bool:
	return _frozen


func is_settling() -> bool:
	return _settling


# --- Rückkehr aus dem Hintergrund (Gerätetest 1.6.2, B1) ---
# Nach der HOME-Übernahme war der zurückkehrende alte Gastgeber einige Sekunden lang selbst Gastgeber (Sofort-Leiste „Kim ist
# getrennt“), parallel zum neuen, bis der Wächter nach zwei Scans (HOST_SCAN_MS) entschied – ein Zug in diesem Fenster ginge verloren.
# Jetzt: War die App mindestens wake_pause_ms im Hintergrund (eine Übernahme braucht ≥ T_SILENT), fragt der Wächter beim Zurückkommen
# sofort (NetDiscovery.scan_soon), und der Tisch hält Aktionen und Bots wake_check_ms lang an („Einen Moment – gleich geht es weiter.“).
# Meldet sich in dieser Zeit ein Gastgeber derselben Partie mit höherer gen, der nach der Wächter-Regel gewinnt, tritt dieser Tisch
# sofort ab (ohne zweiten Scan: Die höhere gen heißt, dass während der Abwesenheit übernommen wurde).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		if _paused_at < 0:
			_paused_at = _now_ms()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		if _paused_at >= 0:
			wake_check(_now_ms() - _paused_at)
		_paused_at = -1


# Nach paused_ms im Hintergrund: Wächter sofort fragen und kurz anhalten. true = Prüfung läuft.
func wake_check(paused_ms: int) -> bool:
	if paused_ms < wake_pause_ms or game == null or session == null or gid == "" or _frozen:
		return false
	var d := session.discovery
	if d == null or d.scan_ms <= 0:
		return false                 # ohne Wächter-Suche gibt es nichts abzuwarten
	_wake_until = _now_ms() + wake_check_ms
	d.scan_soon()
	return true


# Läuft gerade die Wächter-Prüfung nach der Rückkehr?
func is_waking() -> bool:
	return _wake_until > 0 and _now_ms() < _wake_until


func _poll_wake(now: int) -> void:
	if _wake_until > 0 and now >= _wake_until:
		_wake_until = 0
		_plan_dirty = true           # Bots planen wieder


# Platz, an den gerade übergeben wird (−1 = keine Übergabe).
func handover_seat() -> int:
	return int(_handover.get("seat", -1)) if not _handover.is_empty() else -1


# Token des Gastgeber-Platzes (Probe als Gast beim vorsichtigen Neuverbinden, Rückkehr nach dem Abtreten).
func host_token() -> String:
	return str(seats[host_seat].get("token", "")) if host_seat >= 0 and host_seat < seats.size() else ""


# Ersatz-Rangfolge (Abschnitt 4.2, Beta 1.6.2: 10.3): Tokens der App-Gäste im bk-Verteiler, verbunden und nicht away, im
# Uhrzeigersinn ab dem Platz nach dem Gastgeber. Erst alle mit Link „wlan“ (ein WLAN-Erbe erreicht LAN und Raum), dann die mit Link
# „online“ (nur mit Raum und ohne WLAN-Mitspieler am Tisch). Läuft die Partie in einem Spiel-WLAN (wlan.ap), kommen je Gruppe zuerst
# Geräte, die selbst eines öffnen können (ap.perm vor ap.ok), danach die übrigen. WLAN-Erben sperrt nichts mehr.
func heirs() -> Array:
	var out: Array = []
	if session == null or game == null:
		return out
	var ok := {}
	for id in session.backup_ids():
		if not session.is_away(id):
			ok[id] = true
	# Gegenprüfung: Online-Erben nur ohne WLAN-Mitspieler am Tisch (wie 1.6.1). Fällt beim Gastgeber nur das Internet aus, merken die
	# WLAN-Gäste nichts (der Server-Thread antwortet) – ein Online-Erbe eröffnete sonst ein zweites Spiel. Von Hand bleibt es möglich.
	var online_heirs := not session.online_room().is_empty() and not wlan_humans()
	var groups: Array = [[], []]           # wlan, online
	for i in range(1, seats.size()):
		var s := (host_seat + i) % seats.size()
		if not _is_remote(s) or not ok.has(int(_seat_ids[s])):
			continue
		var online := _seat_online(s)
		if online and not online_heirs:
			continue
		(groups[1 if online else 0] as Array).append(s)
	for g in groups:
		var buckets: Array = [[], [], []] if _ap else [[]]
		for s in g:
			var b := 0
			if _ap:
				var caps := session.ap_caps(int(_seat_ids[s]))
				b = 0 if bool(caps.ok) and bool(caps.perm) else (1 if bool(caps.ok) else 2)
			(buckets[b] as Array).append(s)
		for bucket in buckets:
			for s in bucket:
				out.append(str(seats[s].get("token", "")))
	return out


# Sitzt ein entfernter Mensch am Tisch, der (zuletzt) über das WLAN verbunden war? (Beta 1.6.2: sperrt nur noch Online-Erben in
# heirs(); steht im Stand und für die Warnzeile „WLAN-Mitspieler brauchen dann Internet.“)
func wlan_humans() -> bool:
	for s in seats.size():
		if _is_remote(s) and str(seats[s].get("link", "")) == "wlan":
			return true
	return false


# Warum an diesen Platz nicht übergeben werden kann (Bausteine für den Dialog, ausgegraut); [] = möglich.
# Beta 1.6.2 (10.7): auch im WLAN, Spiel-WLAN und gemischt; ein Online-Ziel nur bei offenem Raum, bei how "qr" nur Geräte, die ein
# Spiel-WLAN öffnen können.
func handover_block(seat: int) -> Array:
	if game == null or session == null or _frozen or seat < 0 or seat >= seats.size() or seat == host_seat:
		return [I18n.part("Das geht gerade nicht.")]
	var id := int(_seat_ids[seat])
	if not _is_remote(seat) or str(session.player(id).get("kind", "")) != "app" or session.backup_mark(id).is_empty():
		return [I18n.part("Nur Mitspieler mit der App können Gastgeber werden.")]
	if not session.backup_ids().has(id) or session.is_away(id):
		return [I18n.part("%s ist gerade nicht verbunden.", [seat_name(seat)])]
	var how := handover_how(seat)
	if how == "online" and session.online_state() != "open":
		return [I18n.part("Das geht gerade nicht.")]
	if how == "qr" and not bool(session.ap_caps(id).ok):
		return [I18n.part("Kann kein Spiel-WLAN öffnen.")]
	return []


# Beta 1.6.2 (10.7): Art einer Übergabe an diesen Platz – "qr", wenn die Partie im Spiel-WLAN dieses Gastgebers läuft (das Ziel
# öffnet ein eigenes); sonst "lan", wenn das Ziel über das WLAN verbunden ist (auch im Spiel-WLAN eines Dritten); sonst "online".
# Gegenprüfung: Ein online verbundenes Ziel ist immer "online" – auch bei eigenem Spiel-WLAN (gemischt); es öffnete sonst ein Spiel-WLAN
# in einer anderen Stadt, und die WLAN-Gäste bekämen einen QR-Code, den sie nie erreichen.
func handover_how(seat: int) -> String:
	if seat >= 0 and seat < seats.size() and _seat_online(seat):
		return "online"
	if _ap and _ap_seat == host_seat:
		return "qr"
	if seat >= 0 and seat < seats.size():
		return "lan"
	return "online"


# Beta 1.6.2: Zusatzzeile eines wählbaren Ziels im Auswahldialog (Bausteine); [] = keine.
func handover_notes(seat: int) -> Array:
	if game == null or session == null or seat < 0 or seat >= seats.size() or not _is_remote(seat):
		return []
	var caps := session.ap_caps(int(_seat_ids[seat]))
	if handover_how(seat) == "qr" and bool(caps.ok) and not bool(caps.perm):
		return [I18n.part("Muss das Spiel-WLAN erlauben.")]
	return []


# Beta 1.6.2: Warnzeilen des Auswahldialogs (Bausteine je Zeile); seat ≥ 0: für dieses Ziel.
func handover_warnings(seat := -1) -> Array:
	var out: Array = []
	if game == null or session == null:
		return out
	if _ap and _ap_seat == host_seat and (seat < 0 or handover_how(seat) == "qr"):
		out.append([I18n.part("Alle müssen danach einen neuen QR-Code scannen.")])
	if seat >= 0 and seat < seats.size() and handover_how(seat) == "online" and wlan_humans():
		out.append([I18n.part("WLAN-Mitspieler brauchen dann Internet.")])
	return out


# Beta 1.6.2: Spiel-WLAN der Partie (wlan.ap) und der Platz, dessen Handy es führt (−1 = keins).
func game_wifi() -> Dictionary:
	return {"ap": _ap, "ap_seat": _ap_seat}


# Beta 1.6.2: frühere Gastgeber-Adressen dieser Partie ("ip:port").
func past_hosts() -> Array:
	return _past.duplicate()


# Geplante Übergabe (Abschnitt 4.1): Das Ziel bekommt den vollständigen Stand ({t:"handover", z}), alle die Meldung, der Tisch friert
# ein. Das Ziel übernimmt den Raum (der Vermittler schließt diesen Gastgeber mit 4000 → stepped_down). Kommt binnen
# handover_timeout_ms kein 4000, prüft check_now() das Socket; lebt es, taut der Tisch auf. false = nicht möglich (notice).
# Beta 1.6.2 (10.7): handover trägt how; meldet das Ziel handover_ok (bzw. kommt das 4000), gehen move an die eigenen WLAN-Gäste,
# dann session.drain() und stepped_down (step_target). Ohne Raum taut der Tisch nach handover_timeout_ms ohne check_now auf.
func handover_to(seat: int) -> bool:
	var why := handover_block(seat)
	if not why.is_empty():
		notice.emit(I18n.render(why))
		return false
	var z := MatchSnapshot.pack(_snapshot())
	if z == "":
		push_warning("Gastgeber-Übergabe: Spielstand zu groß")
		notice.emit(I18n.t("Das geht gerade nicht."))
		return false
	return _begin_handover(seat, NetProtocol.make_handover(gid, mark(), z, handover_within_ms), false)


func _begin_handover(seat: int, msg: Dictionary, own: bool) -> bool:
	var id := int(_seat_ids[seat])
	var how := handover_how(seat)
	msg["how"] = how                         # Beta 1.6.2 (10.7): lan | qr | online
	if not session.send_to(id, msg):
		return false
	if not own:
		_tell_all([I18n.part("Gastgeber wechselt zu %s …", [seat_name(seat)])])
	session.flush()
	_frozen = true
	# next_gen: gen des Ziels, sobald es führt (Übernahme gen + 1; own:true behält eine höhere gen des Ziels)
	var next_gen := gen + 1 if not own else maxi(int(msg.get("gen", 0)), gen + 1)
	_handover = {"seat": seat, "id": id, "name": seat_name(seat), "own": own, "until": _now_ms() + handover_timeout_ms, "checking": false,
		"how": how, "addr": _address_of(id), "hp": session.hello_port(id), "next_gen": next_gen}
	return true


# Beta 1.6.2 (10.7 Schritt 3): Das Ziel der laufenden Übergabe führt jetzt (handover_ok). qr: Es öffnet ein eigenes Spiel-WLAN.
# Gegenprüfung: Es zählt die Antwort des Ziels – qr nur, wenn es selbst ein Spiel-WLAN öffnet; meldet es einen Port, führt es im
# bisherigen Netz (lan). Sonst hätte der alte Gastgeber sein Spiel-WLAN geschlossen, während das Ziel darin führt.
func _on_handover_ok(port_: int, qr: bool) -> void:
	var how := "qr" if qr else ("lan" if port_ > 0 else str(_handover.get("how", "lan")))
	if how == "qr" and not qr:
		how = "lan"
	if how == "lan" and port_ <= 0:
		port_ = int(_handover.get("hp", 0))
	var name_ := str(_handover.get("name", "")) if not bool(_handover.get("own", false)) else ""
	_step_away(_move_target(how, str(_handover.get("name", "")), str(_handover.get("addr", "")), port_), name_,
		int(_handover.get("next_gen", gen + 1)), "", int(_handover.get("id", -1)))


# Ziel eines Umzugs {how, name, addr, port, room, relay}: lan = Server des neuen Gastgebers, online = eigener Raum, qr = nur der Name.
func _move_target(how: String, host_name: String, addr: String, port_: int) -> Dictionary:
	var t := {"how": how, "name": host_name, "addr": "", "port": 0, "room": "", "relay": ""}
	match how:
		"lan":
			t.addr = addr
			t.port = port_ if port_ > 0 else NetProtocol.PORT
		"online":
			var o := session.online_room() if session != null else {}
			t.room = str(o.get("room", ""))
			t.relay = str(o.get("relay", ""))
	return t


# Abtreten mit Umzug (10.7 Schritt 3, 10.11): einfrieren, move an alle eigenen verbundenen WLAN-Gäste (Online-Gäste folgen über den
# Raum per 4000/4012; except_id = das Ziel), danach in _poll_extra session.drain() und stepped_down mit step_target.
func _step_away(target: Dictionary, note_name: String, next_gen: int, next_epoch: String, except_id := -1) -> void:
	_frozen = true
	var sent := 0
	_handover = {}
	step_target = target.duplicate()
	if session != null and gid != "":
		var how := str(target.how)
		var send := not (how == "lan" and NetProtocol.ipv4_to_int(str(target.addr)) <= 0) \
			and not (how == "online" and (str(target.room) == "" or str(target.relay) == ""))
		if send:
			var m := NetProtocol.make_move(gid, maxi(next_gen, 1), next_epoch, how, str(target.name), str(target.addr), int(target.port),
				str(target.room), str(target.relay))
			var ids: Array = []
			for id in session.players:
				var p: Dictionary = session.players[id]
				if int(id) != except_id and not bool(p.get("local", false)) and bool(p.get("connected", false)) and not bool(p.get("online", false)):
					ids.append(int(id))
			session.send_many(ids, NetProtocol.encode(m))
			sent = ids.size()
	_step_note = {"name": note_name}
	_step_drain = true
	_step_at = _now_ms() + step_grace_ms if sent > 0 else 0


# Probe als Gast (online_check) beendet: other = ein anderes Gerät führt den Raum (abtreten), sonst als Gastgeber anmelden.
func probe_done(other: bool, new_host := "") -> void:
	if session == null or session.relay == null:
		return
	if not other:
		session.relay.claim()
		return
	session.relay.step_down()
	# Beta 1.6.2 (10.12): WLAN-Gäste ziehen über den Raum mit
	_step_away(_move_target("online", new_host, "", 0), new_host, gen + 1, "")


# Meldung an alle, sobald die Einschwingzeit vorbei ist (z. B. „%s ist jetzt Gastgeber.“); ohne Einschwingzeit sofort.
func announce_after_settle(lt: Array) -> void:
	if _settling:
		_settle_note = lt
	elif not _frozen:
		_tell_all(lt)


# Abtreten (Abschnitt 4.5): Tisch ohne „bye“ und ohne end abbauen. Ergebnis: eigener Stand mit role "guest" und my_seat (liegt auch in
# save_path), damit die Oberfläche als Gast zurückkehrt (Token seats[my_seat].token) und hello.bk schickt.
# Beta 1.6.2: step_target bleibt danach lesbar (wohin die Oberfläche als Gast geht).
func handover_shutdown() -> Dictionary:
	var d := {}
	if game != null:
		d = MatchSnapshot.make(game.to_dict(), seats, host_seat, _save_extra(), _unix(), "guest")
		d["my_seat"] = host_seat
		if autosave:
			write_saved(save_path, d)
	var target := step_target
	_close_session("", false)
	_frozen = false
	step_target = target
	return d


func _reset_handover_state() -> void:
	_frozen = false
	_settling = false
	_settle_tokens = []
	_settle_note = []
	_handover = {}
	_own_tried.clear()
	_step_note = {}
	_step_drain = false
	_rival = {}


func _update_welcome() -> void:
	if session != null:
		session.set_game_mark(gid, gen, epoch)     # Beta 1.6.2: welcome, /info und Suchantwort (gid, gen, epoch)


# Warum Aktionen gerade warten müssen (msgid; "" = keine): Übergabe/Abtreten bzw. Einschwingzeit.
func _hold_reason() -> String:
	if _frozen:
		return "Einen Moment – der Gastgeber wechselt."
	if _settling or is_waking():
		return "Einen Moment – gleich geht es weiter."
	return ""


# Code 4000 (über NetHostSession.replaced): sofort einfrieren; stepped_down kommt nach session.poll() (_poll_extra).
# Beta 1.6.2 (10.7, 10.12): Vor dem Abtreten move an die eigenen WLAN-Gäste – zum Ziel der laufenden Übergabe (Rückfall: Port aus
# hello.hp, weil handover_ok noch fehlt), sonst über den Raum. Kam handover_ok schon, bleibt es dabei (das 4000 wird verworfen).
func _on_replaced() -> void:
	_frozen = true
	if not step_target.is_empty():
		return
	if not _handover.is_empty():
		var how := str(_handover.get("how", "online"))
		var name_ := str(_handover.get("name", "")) if not bool(_handover.get("own", true)) else ""
		_step_away(_move_target(how, str(_handover.get("name", "")), str(_handover.get("addr", "")), int(_handover.get("hp", 0))), name_,
			int(_handover.get("next_gen", gen + 1)), "", int(_handover.get("id", -1)))
		return
	_step_away(_move_target("online", "", "", 0), "", gen + 1, "")


func _on_needs_check(info: Dictionary) -> void:
	if online_check.get_connections().is_empty():
		if session != null and session.relay != null:
			session.relay.claim()       # niemand probt: anmelden wie bis 1.6.0
		return
	online_check.emit(info)


func _emit_stepped_down() -> void:
	var n := str(_step_note.get("name", ""))
	_step_note = {}
	if stepped_down.get_connections().is_empty() or game == null:
		# Noch keine Oberfläche dafür: Online aufgeben wie bis 1.6.0 (Online-Gäste getrennt), mit WLAN-Gästen und Bots weiterspielen.
		_frozen = false
		_handover = {}
		step_target = {}
		if session != null and session.relay != null:
			session.relay.give_up("Der Online-Raum wird jetzt von einem anderen Gerät geführt.")
		if game != null:
			_resync_connected()
			_changed([])
		return
	stepped_down.emit(n)


func _poll_handover(now: int) -> void:
	if _handover.is_empty():
		return
	var r := session.relay
	if not bool(_handover.checking):
		if now < int(_handover.until):
			return
		_handover.checking = true
		if r != null:
			r.check_now()
		return
	if r == null or r.state in ["open", "failed", "off"] and not (r.state == "open" and r.check_pending()):
		_handover_failed()     # Socket lebt ohne 4000 (bzw. kein Raum mehr): Übergabe gescheitert, weiter Gastgeber


func _handover_failed() -> void:
	var n := str(_handover.get("name", ""))
	var own := bool(_handover.get("own", false))
	_handover = {}
	_frozen = false
	_resync_connected()
	_plan_dirty = true
	if not own:
		notice.emit(I18n.t("Übergabe an %s hat nicht geklappt. Du bleibst Gastgeber.") % n)
	_changed([])


# Nach dem Auftauen: Verbindungsstand aus der Sitzung übernehmen (eingefroren wirkten _on_left/_on_rejoined nicht).
func _resync_connected() -> void:
	if game == null or session == null:
		return
	for s in seats.size():
		if _is_remote(s):
			game.set_connected(s, bool(session.player(int(_seat_ids[s])).get("connected", false)))


func _poll_settle(now: int) -> void:
	if not _settling:
		return
	var back := true
	for t in _settle_tokens:
		var id := _id_of_token(str(t))
		if id >= 0 and not bool(session.player(id).get("connected", false)):
			back = false
			break
	if back or now >= _settle_until:
		_settling = false
		_settle_tokens = []
		_plan_dirty = true
		if not _settle_note.is_empty():
			var lt := _settle_note
			_settle_note = []
			_tell_all(lt)


func _poll_alive(now: int) -> void:
	if _frozen or not backup_enabled or gid == "" or now - _last_bk_ms < alive_ms:
		return
	if not (game.phase() in MauGame.PLAY_PHASES or game.phase() == "round_over"):
		return
	_last_bk_ms = now
	var ids := session.backup_ids()
	if not ids.is_empty():
		session.send_many(ids, NetProtocol.encode(NetProtocol.make_alive(gid, mark())))


# Abstammungsregel (Abschnitt 4.3.5): Hält ein App-Gast einen jüngeren Zweig (hello.bk), bekommt er das Spiel zurück
# (handover own:true ohne z; das Ziel nimmt seine eigene Sicherung oder antwortet handover_no). Je Gast und gen höchstens einmal.
func _check_lineage(id: int) -> void:
	if _frozen or gid == "" or game == null:
		return
	var m := session.backup_mark(id)
	if m.is_empty() or int(m[0]) < 1:
		return
	var bg := session.backup_gid(id)
	if bg != "" and bg != gid:
		return     # Beta 1.6.2 (10.1): Sicherung einer anderen Partie – keine Abstammung
	var s := _seat_ids.find(id)
	if s < 0 or not _is_remote(s):
		return
	var newer := int(m[0]) > gen
	if not newer and _settling and int(m[0]) == int(parent[0]) and str(m[1]) == str(parent[1]) and int(m[2]) > int(parent[2]):
		# neuerer Stand derselben Vorgeneration, noch keine Aktion angenommen. Beta 1.6.2 (10.12): nicht an einen Online-Gast, solange
		# WLAN-Mitspieler am Tisch sitzen – sonst zöge ein einzelner Zug, der vor dem Ausfall nur noch über den Vermittler hinausging
		# (der Server des alten Gastgebers verwarf ihn beim Schließen), die ganze Partie ins Internet; Online-Gäste übernehmen dort nur
		# von Hand. Dieser Zug geht verloren (wie ohne ihn). Ein echter jüngerer Zweig (gen höher) holt das Spiel weiterhin zurück.
		newer = not (handover_how(s) == "online" and wlan_humans())
	if not newer:
		return
	var key := "%s:%d" % [str(seats[s].get("token", "")), gen]
	if _own_tried.has(key) or not handover_block(s).is_empty():
		return
	_own_tried[key] = true
	# host_gen: Liegt die gen des Ziels nicht schon darüber (Einschwing-Regel), führt es mit host_gen + 1 weiter – sonst holte dieser
	# Gastgeber das Spiel mit seiner höheren gen gleich wieder zurück (Hin und Her).
	_begin_handover(s, NetProtocol.make_handover(gid, m, "", handover_within_ms, gen), true)


func _id_of_token(t: String) -> int:
	if session == null or t == "":
		return -1
	for id in session.players:
		if str(session.players[id].get("token", "")) == t:
			return int(id)
	return -1


# Über welchen Weg ein entfernter Platz (zuletzt) verbunden war: "online" (Vermittler) oder "wlan" – für wlan_humans und den Stand.
func _note_link(s: int) -> void:
	if not _is_remote(s) or session == null:
		return
	var id := int(_seat_ids[s])
	var p: Dictionary = session.player(id)
	if bool(p.get("connected", false)):
		var online := bool(p.get("online", false))
		seats[s]["link"] = "online" if online else "wlan"
		# Beta 1.6.2 (10.2): Adresse im WLAN, Gastgeber-Port und Spiel-WLAN-Fähigkeit (Suche, hosts, Rangfolge, Stand)
		var a := _address_of(id)
		if not online and NetProtocol.ipv4_to_int(a) > 0:
			seats[s]["addr"] = a
		var hp := session.hello_port(id)
		if hp > 0:
			seats[s]["hp"] = hp
		if str(p.get("kind", "")) == "app":
			seats[s]["ap"] = session.ap_caps(id)
		else:
			seats[s].erase("ap")


# Eigene Adressen für wlan.addrs merken (Stufe 2 liest sie). NetAddresses fragt auf Android per JNI alle Netze ab – nicht je Änderung.
func _note_addrs() -> void:
	_addrs = NetAddresses.own_addresses().map(func(a): return str(a.address))
	_addrs_port = port()


# --- WLAN und Spiel-WLAN (Beta 1.6.2, docs/module/uebergabe.md Abschnitt 10) ---

# Nach Neu-Binden bzw. Öffnen/Schließen des Spiel-WLANs (GameWifiWatch, 10.2): eigene Adressen neu ermitteln (die bisherigen kommen
# nach wlan.past – Lite-Seiten von dort dürfen sich weiter verbinden), wlan.ap/ap_seat fortschreiben, dann hosts und Sicherung neu.
func refresh_addrs() -> void:
	if session == null:
		return
	var old: Array = _addrs.duplicate()
	var old_port := _addrs_port
	_note_addrs()
	var kept := false
	if old_port > 0:
		for a in old:
			if not _addrs.has(a) or old_port != _addrs_port:
				_add_past(str(a), old_port)
			else:
				kept = true
	if old_port > 0 and not old.is_empty() and not kept:      # keine frühere Adresse mehr erreichbar: umgezogen
		_join_auto_after_move()
	_update_ap(true)
	_apply_origins()
	_update_scan()
	if game != null and not _frozen and gid != "":
		_changed([])                 # neue Sicherung (wlan), hosts über _after_distribute


# Beta 1.6.2 (10.10): Wartenden (waiting_id) auf den Platz eines getrennten Mitspielers setzen – er spielt mit dessen Karten weiter
# (Browser-Gäste nach einem Umzug, alte Lite-Fassungen). Nur in der laufenden Partie, nicht eingefroren, nur entfernte Menschenplätze
# ohne Verbindung. Eine Vertretung durch den Computer endet dabei (_on_rejoined). false = nicht möglich.
func seat_assign(waiting_id: int, seat: int) -> bool:
	if game == null or _frozen or session == null or not session.is_waiting(waiting_id) or _queued(waiting_id):
		return false
	if not _is_remote(seat):
		return false
	var id := int(_seat_ids[seat])
	if bool(session.player(id).get("connected", false)):
		return false
	return session.assign_seat(waiting_id, id)


# Menschenplätze ohne Verbindung (Auswahl „Auf den Platz von %s setzen“).
func free_human_seats() -> Array:
	var out: Array = []
	if game == null or session == null:
		return out
	for s in seats.size():
		if _is_remote(s) and not bool(session.player(int(_seat_ids[s])).get("connected", false)):
			out.append(s)
	return out


# Gastgeber-Wächter (10.11): Ein anderer Gastgeber derselben Partie antwortet auf den eigenen Scan (NetDiscovery.rival). Beide rechnen
# dieselbe Regel: Der andere gewinnt mit mehr verbundenen Menschen (conn), dann höherer gen, dann größerer epoch. Gemischt mit offenem
# Raum tritt dieser Gastgeber nur bei kleinerer gen ab (sonst entscheidet der Vermittler). Der Verlierer tritt nach rival_confirm
# gleichen Ergebnissen hintereinander ab; der Gewinner hebt seine gen sofort über die des anderen (sonst holte die Abstammungsregel den
# Zweig des Verlierers zurück, sobald dessen Gäste ankommen). Die Adressen des anderen werden auf beiden Seiten erlaubte Herkunft.
func _on_rival(info: Dictionary) -> void:
	if game == null or session == null or _frozen or gid == "" or str(info.get("gid", "")) != gid:
		return
	var rport := int(info.get("port", 0))
	var grew := false
	var addrs: Array = (info.get("addresses", []) as Array).duplicate() if info.get("addresses") is Array else []
	if str(info.get("address", "")) != "" and not addrs.has(str(info.address)):
		addrs.push_front(str(info.address))
	for a in addrs:
		grew = _add_past(str(a), rport) or grew
	if grew:
		_apply_origins()
	var mine := session.info()
	var my_conn := int(mine.get("conn", session.connected_humans()))
	var o_conn := int(info.get("conn", 0))
	var o_gen := int(info.get("gen", 0))
	var o_epoch := str(info.get("epoch", ""))
	var room_open := not session.online_room().is_empty() and session.online_state() == "open"
	var out := rival_outcome(room_open, my_conn, gen, epoch, o_conn, o_gen, o_epoch)
	var lose := bool(out.lose)
	var key := str(info.get("sid", "")) if str(info.get("sid", "")) != "" else "%s:%d" % [str(info.get("address", "")), rport]
	if str(_rival.get("sid", "")) != key or bool(_rival.get("lose", false)) != lose:
		_rival = {"sid": key, "lose": lose, "n": 0}
	_rival.n = int(_rival.n) + 1
	if bool(out.raise):
		parent = mark()
		gen = o_gen + 1
		epoch = NetProtocol.new_epoch()
		_update_welcome()
		_changed([])                         # Sicherung mit der neuen gen sofort an die eigenen Gäste
		return
	# Gegenprüfung: Abtreten erst, wenn der Gewinner seine gen schon über die eigene gehoben hat – sonst gäbe die Abstammungsregel
	# (_check_lineage) ihm das Spiel zurück an einen der eigenen Gäste, sobald sie mit ihrer Sicherung ankommen. Hat er nach
	# rival_gen_wait weiteren Scans noch nicht angehoben (verpasste Scans, UDP-Verlust), trotzdem abtreten.
	# Gerätetest 1.6.2 (B1): direkt nach der Rückkehr aus dem Hintergrund genügt ein Scan, wenn der andere schon eine höhere gen hat.
	if lose and is_waking() and o_gen > gen:
		_wake_until = 0
		_lose_to_rival(info)
	elif lose and int(_rival.n) >= rival_confirm and (o_gen > gen or int(_rival.n) >= rival_confirm + rival_gen_wait):
		_lose_to_rival(info)
	elif grew:
		_changed([])                         # wlan.past in der Sicherung


# Wächter-Entscheidung (10.11) aus Sicht dieses Gastgebers: lose = der andere gewinnt (tritt nach rival_confirm Scans ab), raise = dieser
# gewinnt und hebt seine gen über die des anderen (raise geht vor lose). Mit offenem eigenem Raum tritt er nur bei kleinerer gen ab
# (gleiche gen: der Vermittler entscheidet); angehoben wird nach der vollen Regel auch dann (Gegenprüfung: Ein Gewinner mit offenem
# Raum gegen einen Verlierer ohne Vermittler träte sonst selbst ab bzw. verlöre per Abstammung die Züge der Mehrheit).
static func rival_outcome(room_open: bool, my_conn: int, my_gen: int, my_epoch: String, o_conn: int, o_gen: int, o_epoch: String) -> Dictionary:
	var win := rival_wins(my_conn, my_gen, my_epoch, o_conn, o_gen, o_epoch)
	var lose := o_gen > my_gen if room_open else rival_wins(o_conn, o_gen, o_epoch, my_conn, my_gen, my_epoch)
	var raise := win and my_gen <= o_gen
	return {"lose": lose and not raise, "raise": raise}


# Gewinnt der Gastgeber a gegen b? (Wächter-Regel 10.11; symmetrisch, beide Seiten rechnen dasselbe)
static func rival_wins(a_conn: int, a_gen: int, a_epoch: String, b_conn: int, b_gen: int, b_epoch: String) -> bool:
	if a_conn != b_conn:
		return a_conn > b_conn
	if a_gen != b_gen:
		return a_gen > b_gen
	return a_epoch > b_epoch


func _lose_to_rival(info: Dictionary) -> void:
	var addr := str(info.get("address", ""))
	if NetProtocol.ipv4_to_int(addr) <= 0:
		var list: Array = info.get("addresses", []) if info.get("addresses") is Array else []
		addr = str(list[0]) if not list.is_empty() else ""
	var host_name := str(info.get("name", ""))
	_tell_all([I18n.part("%s führt dieses Spiel schon – ihr spielt dort weiter.", [host_name])])
	_step_away(_move_target("lan", host_name, addr, int(info.get("port", 0))), host_name, maxi(int(info.get("gen", 0)), 1),
		str(info.get("epoch", "")))


# Erben-Liste für Browser-Gäste ({t:"hosts"}, 10.9): Erben mit Link „wlan“ in Rangfolge als http://addr:hp/, Raum-Link, Spiel-WLAN und
# wer bei dessen Verlust ein neues öffnet. Geht nur bei Änderung hinaus (die Sitzung schickt die letzte nach jedem welcome mit).
func hosts_message() -> Dictionary:
	var list: Array = []
	if session == null or game == null:
		return {}
	for t in heirs():
		var s := _seat_of_token(str(t))
		if s < 0 or _seat_online(s):
			continue
		var a := str(seats[s].get("addr", ""))
		if NetProtocol.ipv4_to_int(a) <= 0:
			continue
		var hp := int(seats[s].get("hp", 0))
		list.append({"name": seat_name(s), "url": "http://%s:%d/" % [a, hp if hp > 0 else NetProtocol.PORT]})
	var o := session.online_room()
	var online := NetProtocol.room_link(str(o.relay), str(o.room)) if not o.is_empty() else ""
	return NetProtocol.make_hosts(gid, gen, list, online, _ap, _ap_name())


func _send_hosts() -> void:
	if session == null or game == null or gid == "" or _frozen:
		return
	var m := hosts_message()
	var key := JSON.stringify(m)
	_update_scan()
	if key == _hosts_key:
		return
	_hosts_key = key
	session.send_hosts(m)


# Wer bei Verlust des Spiel-WLANs ein neues öffnet (10.8): Führte der Gastgeber es selbst, Rang 0; sitzt er im Spiel-WLAN eines
# anderen, er selbst.
func _ap_name() -> String:
	if not _ap:
		return ""
	if _ap_seat >= 0 and _ap_seat != host_seat:
		return seat_name(host_seat)
	var h := heirs()
	var s := _seat_of_token(str(h[0])) if not h.is_empty() else -1
	return seat_name(s) if s >= 0 else ""


# wlan.ap fortschreiben: eigenes Spiel-WLAN offen → ap, ap_seat = Gastgeber. closing: ist es zu und führte der Gastgeber es selbst,
# läuft die Partie nicht mehr im Spiel-WLAN (das eines Mitspielers bleibt, bis sein Verlust gemeldet wird).
# Gerätetest 1.6.2 (F1): Bis Android 15 ist ein offenes Spiel-WLAN neben dem WLAN nie an der Bindung zu erkennen (host_plan: „Hotspot
# und WLAN → ungebunden“, binding() == ""); die Partie lief deshalb nie als wlan.ap. Darum fragt hotspot_check den Zustand des
# Spiel-WLANs (GameWifiWatch bzw. own_game_wifi_open).
func _update_ap(closing: bool) -> void:
	var on: bool = bool(hotspot_check.call()) if hotspot_check.is_valid() else own_game_wifi_open()
	if on:
		_ap = true
		_ap_seat = host_seat
	elif closing and _ap and _ap_seat == host_seat:
		_ap = false
		_ap_seat = -1


# Ist das eigene Spiel-WLAN offen? Ohne GameWifiWatch (z. B. direkt nach start/resume): an den Hotspot gebunden (Android 16+ ohne WLAN)
# oder auf Android laut GameWifi.hotspotState „on“ (nie mit der PC-Simulation NetAndroid.wifi_stub – die gehört dem Watch).
static func own_game_wifi_open() -> bool:
	if NetAddresses.binding() == "hotspot":
		return true
	if OS.get_name() != "Android" or NetAndroid.wifi_stub is Dictionary or not NetAndroid.game_wifi_available():
		return false
	return str(NetAndroid.game_wifi_state().get("status", "")) == "on"


# Erlaubte Herkunft: alle früheren Gastgeber-Adressen (10.9).
func _apply_origins() -> void:
	if session != null:
		session.set_extra_origins(_past.map(func(p): return "http://" + str(p)))


# Unicast-Ziele des Wächters: Adressen der Erben und früherer Gastgeber (Rundrufe filtern manche Router).
func _update_scan() -> void:
	if session == null or session.discovery == null:
		return
	var ips: Array = []
	for s in seats.size():
		var a := str(seats[s].get("addr", ""))
		if _is_remote(s) and NetProtocol.ipv4_to_int(a) > 0 and not ips.has(a):
			ips.append(a)
	for p in _past:
		var a := str(p).get_slice(":", 0)
		if not ips.has(a) and not _addrs.has(a):
			ips.append(a)
	var key := ",".join(ips)
	if key == _scan_key:
		return
	_scan_key = key
	session.discovery.manual = ips


func _add_past(ip: String, port_: int) -> bool:
	ip = ip.trim_prefix("::ffff:")
	if NetProtocol.ipv4_to_int(ip) <= 0 or port_ <= 0 or port_ > 65535:
		return false
	return _add_past_entry("%s:%d" % [ip, port_])


func _add_past_entry(entry: String) -> bool:
	var ip := entry.get_slice(":", 0)
	var p := entry.get_slice(":", 1)
	if entry.get_slice_count(":") != 2 or NetProtocol.ipv4_to_int(ip) <= 0 or not p.is_valid_int() or int(p) <= 0 or int(p) > 65535:
		return false
	if _past.has(entry):
		return false
	_past.append(entry)
	while _past.size() > NetProtocol.PAST_MAX:
		_past.pop_front()
	return true


# ap, ap_seat und past aus dem Stand (MatchSnapshot.clean; Rückfall auf die Rohdaten, falls clean die Felder nicht kennt).
static func _wlan_extra(snap: Dictionary, data: Dictionary) -> Dictionary:
	var w: Dictionary = snap.get("wlan", {}) if snap.get("wlan") is Dictionary else {}
	if not w.has("past") and data.get("wlan") is Dictionary:
		w = data.wlan
	var ap_seat = w.get("ap_seat", -1)
	var past: Array = []
	if w.get("past") is Array:
		for p in w.past:
			if p is String:
				past.append(p)
	return {"ap": w.get("ap") == true, "ap_seat": int(ap_seat) if (ap_seat is int or ap_seat is float) else -1, "past": past}


# Beta 1.6.2 (10.10): Ist dieser Gastgeber seit dem Stand umgezogen (anderer Port oder keine der gespeicherten Adressen mehr)? Ohne
# gespeicherten Port bzw. Adressen (Stand einer älteren App) gilt er als nicht umgezogen.
func _moved_since(snap: Dictionary) -> bool:
	var wp := int(snap.wlan.port)
	if wp <= 0:
		return false
	if session.port() != wp:
		return true
	var olds: Array = (snap.wlan as Dictionary).get("addrs", [])
	if olds.is_empty():
		return false
	var own: Array = NetAddresses.own_addresses().map(func(a): return str(a.address))
	for a in olds:
		if own.has(str(a)):
			return false
	return true


# Beta 1.6.2 (10.10): Umzug während der Partie (refresh_addrs, z. B. Spiel-WLAN nach dem Fortsetzen geöffnet): Warteliste wie nach
# einer Übernahme offen halten, solange ein Menschenplatz getrennt ist.
func _join_auto_after_move() -> void:
	if _join_auto or session == null or game == null or not session.running or free_human_seats().is_empty():
		return
	_join_restore = session.join_open
	_join_auto = true
	session.join_open = true


# Nach resume(): Warteliste wieder wie vorher, sobald kein Menschenplatz mehr getrennt ist (10.10).
func _poll_join_auto() -> void:
	if not _join_auto or session == null or game == null:
		return
	if free_human_seats().is_empty():
		_join_auto = false
		session.join_open = _join_restore


# Ist der Platz über den Vermittler verbunden (bzw. war er es zuletzt)?
func _seat_online(s: int) -> bool:
	if session == null or s < 0 or s >= _seat_ids.size():
		return false
	var p: Dictionary = session.player(int(_seat_ids[s]))
	if bool(p.get("connected", false)):
		return bool(p.get("online", false))
	return str(seats[s].get("link", "")) == "online"


func _seat_of_token(t: String) -> int:
	if t == "":
		return -1
	for s in seats.size():
		if str(seats[s].get("token", "")) == t:
			return s
	return -1


# IPv4 eines verbundenen Spielers aus Sicht des Gastgebers ("" = unbekannt, z. B. online).
func _address_of(id: int) -> String:
	var a := str(session.player(id).get("address", "")).trim_prefix("::ffff:") if session != null else ""
	return a if NetProtocol.ipv4_to_int(a) > 0 else ""


func _new_token() -> String:
	return Crypto.new().generate_random_bytes(NetProtocol.TOKEN_LENGTH / 2).hex_encode()


func _now_ms() -> int:
	return int(ms_clock.call()) if ms_clock.is_valid() else Time.get_ticks_msec()


func _unix() -> int:
	return int(clock.call()) if clock.is_valid() else int(Time.get_unix_time_from_system())


# --- intern ---

func _changed(events: Array) -> void:
	if _frozen:
		return       # Beta 1.6.1: eingefroren – kein Speichern, kein Verteilen (Abschnitt 3.3)
	super._changed(events)


# Beta 1.6.1: erst Sicherung (eigene Datei, {t:"bk"} an die App-Gäste mit hello.bk), danach verteilt _distribute die Sichten.
func _persist() -> void:
	if game == null:
		return
	seq += 1
	var ids: Array = session.backup_ids() if backup_enabled and gid != "" and session != null else []
	if not autosave and ids.is_empty():
		return
	var snap := _snapshot()
	if autosave:
		write_saved(save_path, snap)
	if ids.is_empty():
		return
	var z := MatchSnapshot.pack(snap)
	if z == "":
		push_warning("Sicherung zu groß – nicht verschickt (seq %d)" % seq)
		return
	session.send_many(ids, NetProtocol.encode(NetProtocol.make_bk(gid, mark(), z)))
	_last_bk_ms = _now_ms()


func _snapshot() -> Dictionary:
	return MatchSnapshot.make(game.to_dict(), seats, host_seat, _save_extra(), _unix())


func _poll_extra() -> void:
	if session != null:
		session.poll()
	if not _step_note.is_empty():
		if _step_drain and session != null:
			_step_drain = false
			session.drain(drain_ms)  # Beta 1.6.2: move wirklich hinaus, bevor die Oberfläche den Server schließt
		if _now_ms() < _step_at:
			return               # … und den Gästen einen Augenblick zum Lesen lassen (Schließen mit ungelesenen Daten kann sie verwerfen)
		_emit_stepped_down()     # nach session.poll(): die Oberfläche darf jetzt die Sitzung abbauen
	if game == null or session == null:
		return
	var now := _now_ms()
	_poll_settle(now)
	_poll_wake(now)
	_poll_handover(now)
	_poll_join_auto()
	if game != null and session != null:
		_poll_alive(now)


func _bots_paused() -> bool:
	return session == null or _frozen or _settling or is_waking()


func _pre_step() -> bool:
	if _frozen or _settling or is_waking():
		return false
	# nie für einen Gast, der nur kurz in einer anderen App ist
	if auto_substitute_s > 0.0 and _waiting_seat >= 0 and not is_away(_waiting_seat) and Time.get_ticks_msec() - _wait_since > int(auto_substitute_s * 1000.0):
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
			if not is_away(cur):     # sonst steht dort schon „… ist kurz in einer anderen App – warte …“
				_tell_all([I18n.part("%s ist getrennt – warte …", [seat_name(cur)])])
	else:
		_waiting_seat = -1


func _patch_view(seat: int, v: Dictionary) -> void:
	# Spielerliste: Gastgeber (host) und „kurz in einer anderen App“ (away), Beta 1.3.3
	for p in v.get("players", []):
		var s := int((p as Dictionary).get("seat", -1))
		if s == host_seat:
			p["host"] = true
		if is_away(s):
			p["away"] = true
	var cur := game.current_seat()
	if cur >= 0 and cur != seat and is_away(cur) and _is_remote(cur) and not _substitute.has(cur):
		(v.hints as Dictionary).text = "%s ist kurz in einer anderen App – warte …" % seat_name(cur)
		(v.hints as Dictionary).lt = [I18n.part("%s ist kurz in einer anderen App – warte …", [seat_name(cur)])]
	elif _waiting_seat >= 0 and seat != _waiting_seat:
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
	if game == null or _frozen:
		return
	var s := _seat_ids.find(id)
	if s < 0:
		return
	game.set_connected(s, false)
	# Kurz in einer anderen App: Android trennt Hintergrund-Apps oft nach Sekunden (Gerätetest 1.3.3); der Platz zeigt dann schon
	# „kurz in einer anderen App“, ein zusätzliches „getrennt“ widerspräche dem.
	if not is_away(s):
		notice.emit(I18n.t("%s ist getrennt.") % seat_name(s))
	_changed([])


func _on_rejoined(id: int) -> void:
	if game == null or _frozen:
		return
	var s := _seat_ids.find(id)
	if s < 0:
		return
	game.set_connected(s, true)
	_note_link(s)
	if _substitute.has(s):
		_substitute.erase(s)
	notice.emit(I18n.t("%s ist wieder da.") % seat_name(s))
	# Beta 1.6.1: Abstammung zuerst – hält er einen jüngeren Zweig, bekommt er das Spiel zurück. Ein bk vorher (_changed) überschriebe
	# seine Sicherung (höhere gen), und handover own:true fände seine Marke nicht mehr.
	_check_lineage(id)
	if not _frozen:
		_changed([])             # schickt allen (auch dem Zurückgekehrten) sofort den aktuellen Stand
		_fx_offs_to(id)          # Beta 1.6.3: nach seinem welcome einmal die Liste fx_offs


# „away“/„back“ (Gast oder Gastgeber selbst): Änderung → alle bekommen den neuen Stand; „back“ ohne Änderung → nur dieser Gast
# (er will nach der Rückkehr in die App den vollen Stand).
func _on_away(id: int, _on: bool, changed: bool) -> void:
	if game == null or _frozen:
		return
	var s := _seat_ids.find(id)
	if s < 0:
		return
	if changed:
		_changed([])
	elif _is_remote(s) and bool(game.connected[s]):
		_send_state(s, [])


func _on_message(id: int, msg: Dictionary) -> void:
	if str(msg.get("t", "")) == "handover_ok":
		# Beta 1.6.2 (10.7): nur vom Ziel der laufenden Übergabe; danach (oder nach einem 4000) wird alles Weitere verworfen. Bei einem
		# Online-Ziel entscheidet wie in 1.6.1 das 4000 des Vermittlers (handover_ok schadet dort nicht).
		if not _handover.is_empty() and int(_handover.id) == id and step_target.is_empty() \
				and (str(_handover.get("how", "")) != "online" or msg.get("qr") == true):
			_on_handover_ok(int(msg.get("port", 0)) if msg.get("port") is int else 0, msg.get("qr") == true)
		return
	if str(msg.get("t", "")) == "handover_no":
		# Beta 1.6.1: Ziel von handover own:true hat abgelehnt (Sicherung passt nicht mehr) → auftauen, weiter Gastgeber
		if not _handover.is_empty() and int(_handover.id) == id:
			_handover_failed()
		return
	if str(msg.get("t", "")) == "fx":
		_on_fx(id, msg)              # Beta 1.6.3: Necken
		return
	if str(msg.get("t", "")) == "fx_pref":
		_on_fx_pref(id, msg.get("off") == true)
		return
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
	var wait := _hold_reason()
	if wait != "":
		_err(id, wait)            # Beta 1.6.1: Übergabe bzw. Einschwingzeit
		return
	if _substitute.has(s) and str(a.get("a", "")) != "":
		_substitute.erase(s)    # der Mensch spielt wieder selbst
		_plan_dirty = true
	var r := _apply(s, a)
	if not bool(r.ok):
		_err(id, str(r.reason), r.get("reason_lt", []))


# --- Necken (Beta 1.6.3, docs/module/eastereggs2.md) ---

# Wunsch des Gastgebers selbst: dieselbe Prüfung wie für Gäste.
func send_fx(req: Dictionary) -> void:
	if session != null:
		_on_fx(session.host_id, NetProtocol.make_fx_request(req))


# Einstellung „necken“ des Gastgebers (er steht selbst in fx_offs).
func set_fx_off(off: bool) -> void:
	_fx_off_self = off
	_fx_sync_offs()


func _on_fx(id: int, msg: Dictionary) -> void:
	if game == null or session == null or _frozen or _settling or is_waking() or msg.is_empty():
		return                        # Übergabe, Einschwingzeit, Wächter-Prüfung: nichts annehmen (ohne fx_no)
	var sender := _seat_ids.find(id)   # Warteliste: −1 → still verworfen
	var now := _fx_now()
	var why := tease.check(sender, msg, _fx_table(), now)
	if why != "":
		if why in TeaseRules.REFUSALS:
			if id == session.host_id:
				_fx_refuse(why, str(msg.k))
			else:
				session.send_to(id, NetProtocol.make_fx_no(why, str(msg.k)))
		return
	if str(msg.k) == TeaseRules.CUSHION:
		_cushion_place(id, sender, int(msg.to), (msg.get("reveal") is bool and bool(msg.reveal)), now)
		return
	var m := NetProtocol.make_fx(str(msg.k), sender, int(msg.get("to", -1)), str(msg.get("r", "")))
	var ids: Array = []
	for s in seats.size():
		if _is_remote(s):
			ids.append(int(_seat_ids[s]))   # sitzende entfernte Menschen; send_many übergeht nicht verbundene
	session.send_many(ids, NetProtocol.encode(m))
	_fx_deliver(m)                   # verbuchen und am eigenen Tisch zeigen


# Beta 1.6.6: Vorprüfung des Gastgeber-Bildschirms. tease ist hier maßgeblich und kennt fremde Kissen – das darf die Oberfläche nicht
# verraten: Liegt bei diesem Ziel das Kissen eines anderen, sieht der Knopf aus wie bei jedem Gast (aktiv), der Gastgeber erfährt es
# erst beim Drücken (fx_refused busy wie fx_no an einen Gast).
func fx_check(req: Dictionary) -> String:
	var why := super.fx_check(req)
	if why == "busy" and str(req.get("k", "")) == TeaseRules.CUSHION and req.get("to") is int \
			and int(tease.cushion_at(int(req.to)).get("from", -1)) != local_seat():
		return ""
	return why


# Beta 1.6.6 (Furzkissen, docs/module/eastereggs2.md Abschnitt 12): legen. Die Sperre des Legers wird hier ausgelost (1–3 min, fx_rand)
# und nie verschickt. Bestätigung nur an den Leger – auch der Gastgeber-Bildschirm erfährt nichts, wenn er nicht selbst gelegt hat.
func _cushion_place(id: int, sender: int, to: int, reveal: bool, now: int) -> void:
	tease.place_cushion(sender, to, reveal, now, _cushion_block_ms())
	var m := NetProtocol.make_cushion(sender, to, reveal)
	if id == session.host_id:
		fx_event.emit(m)
	else:
		session.send_to(id, m)


# Beta 1.6.6: Das Kissen am Platz seat löst aus (GameTable._apply, nach dem Stand dieses Zugs). reveal: alle bekommen from. Geheim: alle
# Sitzenden ohne from, nur der Leger (falls entfernt und verbunden) eine Kopie mit from; der eigene Tisch zeigt from nur, wenn der Gastgeber
# selbst gelegt hat. Ziel oder Leger mit Necken aus, eingefroren oder in der Einschwingzeit: verfällt still.
func _cushion_pop(seat: int, c: Dictionary) -> void:
	if game == null or session == null or _frozen or _settling:
		return
	var offs := _fx_off_seats_now()
	var from := int(c.get("from", -1))
	if offs.has(seat) or offs.has(from) or from < 0 or from >= seats.size():
		return
	var reveal := bool(c.get("reveal", false))
	var m := NetProtocol.make_cushion_pop(seat, reveal, from if reveal else -1)
	var mine := NetProtocol.make_cushion_pop(seat, reveal, from)
	var ids: Array = []
	for s in seats.size():
		if _is_remote(s) and (reveal or s != from):
			ids.append(int(_seat_ids[s]))
	session.send_many(ids, NetProtocol.encode(m))
	if not reveal and from != host_seat and _is_remote(from):
		session.send_to(int(_seat_ids[from]), mine)
	_fx_deliver(mine if from == host_seat else m)


func _on_fx_pref(id: int, off: bool) -> void:
	if bool(_fx_off_ids.get(id, false)) == off:
		return
	if off:
		_fx_off_ids[id] = true
	else:
		_fx_off_ids.erase(id)
	_fx_sync_offs()


# Tisch-Beschreibung für TeaseRules.check aus den eigenen Daten (bot = echter Computergegner; gone = getrennt, away oder vertreten).
func _fx_table() -> Dictionary:
	var list: Array = []
	var offs := _fx_off_seats_now()
	for s in seats.size():
		var bot := str(seats[s].kind) == "bot"
		var gone := false
		if not bot:
			gone = is_away(s) or _substitute.has(s) or (s != host_seat and not bool(game.connected[s]))
		list.append({"bot": bot, "gone": gone, "off": offs.has(s)})
	return {"mode": mode(), "phase": game.phase(), "turn": game.current_seat(), "seats": list}


func _fx_off_seats_now() -> Array:
	var out: Array = []
	for s in _seat_ids.size():
		var id := int(_seat_ids[s])
		if (s == host_seat and _fx_off_self) or (s != host_seat and bool(_fx_off_ids.get(id, false))):
			out.append(s)
	return out


# Liste fx_offs neu berechnen; bei Änderung an den eigenen Tisch (fx_offs_changed) und an alle Sitzenden.
func _fx_sync_offs() -> void:
	if game == null or session == null or _frozen:
		return
	var list := _fx_off_seats_now()
	var key := JSON.stringify(list)
	if key == _fx_offs_key or (_fx_offs_key == "" and list.is_empty()):
		_fx_offs_key = key
		return
	_fx_offs_key = key
	_fx_offs = list
	fx_offs_changed.emit(list.duplicate())
	var ids: Array = []
	for s in seats.size():
		if _is_remote(s):
			ids.append(int(_seat_ids[s]))
	session.send_many(ids, NetProtocol.encode(NetProtocol.make_fx_offs(list)))


# Einem Gast nach seinem welcome bzw. beim Dazuholen die aktuelle Liste schicken (leer: nichts, er beginnt ohnehin leer).
func _fx_offs_to(id: int) -> void:
	if game == null or session == null or _frozen or _fx_offs.is_empty() or _seat_ids.find(id) < 0:
		return
	session.send_to(id, NetProtocol.make_fx_offs(_fx_offs))


func _fx_now() -> int:
	return int(fx_clock.call()) if fx_clock.is_valid() else _now_ms()


func _err(id: int, text: String, lt: Array = []) -> void:
	var msg := {"t": "err", "text": text}
	if not lt.is_empty() and not (lt.size() == 1 and lt[0] is String):   # Bausteine nur bei Platzhaltern (sonst ist text die msgid)
		msg["lt"] = lt
	if _seq.has(id):
		msg.seq_ack = _seq[id]
	session.send_to(id, msg)


# Beta 1.6.1: Felder des Schnappschusses über das Regelwerk hinaus (MatchSnapshot.EXTRA_KEYS).
func _save_extra() -> Dictionary:
	var sub: Array = _substitute.keys().map(func(k): return int(k))
	sub.sort()
	var waiting: Array = []
	var bk_to: Array = []
	var online := {}
	var addrs: Array = []
	if session != null:
		for id in session.waiting_ids():
			var p: Dictionary = session.player(id)
			waiting.append({"name": str(p.name), "net": str(p.kind), "token": str(p.get("token", ""))})
		for id in session.backup_ids():
			var s := _seat_ids.find(id)
			if s >= 0:
				bk_to.append(str(seats[s].get("token", "")))
		online = session.online_room()
		addrs = _addrs.duplicate()
	# join_open: nach einer Übernahme offen gehalten (_join_auto) – gespeichert wird der Wert, der danach wieder gilt
	var jo: bool = _join_restore if _join_auto else (session != null and session.join_open)
	return {"gid": gid, "gen": gen, "epoch": epoch, "parent": parent.duplicate(), "seq": seq, "substitute": sub,
		"gone_names": _gone_names.keys(), "waiting": waiting, "join_open": jo, "heirs": heirs(),
		"bk_to": bk_to, "wlan_humans": wlan_humans(), "online": online,
		"wlan": {"port": port(), "addrs": addrs, "ap": _ap, "ap_seat": _ap_seat if _ap else -1, "past": _past.duplicate()}}


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
