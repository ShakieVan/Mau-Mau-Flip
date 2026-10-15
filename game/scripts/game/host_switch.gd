class_name HostSwitch
extends Node
# Mau-Mau Flip (Beta 1.6.1, Gastgeber-Übergabe, docs/module/uebergabe.md Abschnitte 4.2–4.5, 5): Wechsel zwischen Gast- und
# Gastgeber-Tisch. Ein HostSwitch hängt als Kind an der Quelle des Tisches (ensure(source)) und zieht bei jedem Wechsel mit um.
#
# Gast (ClientTable, online, mit Sicherung derselben Partie, nur in MauGame.PLAY_PHASES und round_over):
#   watch    Wächter: Gastgeber fehlt nach T_SILENT ab der letzten Nachricht bzw. ab 4503, nach T_AWAY ab seinem „away“ (auch wenn
#            danach 4503 kommt oder das away bis AWAY_LINK_MS nach dem 4503 eintrifft; deadline_for). Wanduhr (wall_ms, einspritzbar).
#   missing  neu als Gast anmelden (NetClient.reconnect_now, neue c); welcome → watch.
#   waiting  Verbindung angenommen, aber unbeantwortet (bzw. 4503): Wartezeit Rang × T_STEP (Rang aus heirs der Sicherung, nur wenn die
#            Sicherung aktuell ist; sonst keine Automatik, nur continue_as_host()). Vermittler nicht erreichbar → nie übernehmen.
#   checking unmittelbar davor: /info – host:false → übernehmen; host:true → frische Probe (neue c), PROBE_MS still → übernehmen,
#            welcome → watch; Raum weg → gone.
#   taking   HostTable.resume(Sicherung, eigener Platz) samt open_online_existing; room-Rahmen binnen within_ms → swapped(HostTable);
#            sonst Abbruch: Gastgeber-Socket zu, Datei wie vorher, wieder als Gast anmelden.
#   Geplante Übergabe: {t:"handover", z} bzw. own:true (eigene Sicherung genau dieser Marke, sonst handover_no) → taking, ohne Prüfung.
# Gastgeber (HostTable):
#   probe    online_check (vorsichtiges Neuverbinden): Probe als Gast mit dem eigenen Platz-Token; welcome → probe_done(true) →
#            stepped_down; still/4503/Raum weg → probe_done(false) (anmelden); Vermittler nicht erreichbar → erneut proben.
#   joining  stepped_down → become_guest: HostTable ohne bye/end abbauen (handover_shutdown), als Gast mit dem eigenen Platz-Token
#            und hello.bk der eigenen Datei anmelden; welcome (oder Frist) → swapped(ClientTable).
# Hauptmenü „Partie fortsetzen“ (resume_saved): zuerst als Gast mit dem eigenen Platz-Token (resuming); antwortet ein Gastgeber →
#   swapped(ClientTable). Sonst (/info host:false bzw. frische Probe still): eigene Gastgeber-Datei jünger als RESUME_QUIET_MIN →
#   sofort fortsetzen, sonst confirm (Signal confirm_needed, Antwort confirm_resume). WLAN: nur die eigene Gastgeber-Datei, sofort.
#   Raum abgelaufen → expired (last_error).
#
# Mau-Mau Flip (Beta 1.6.2, WLAN und Spiel-WLAN, docs/module/uebergabe.md Abschnitte 10.4, 10.5, 10.7, 10.8, 10.12–10.14):
#   - Wächter auch im WLAN (ohne Vermittler): jede Nachricht des Gastgebers zählt (auch pong), Gegenstück zu 4503 ist
#     NetClient.host_lost_wall. missing: neu verbinden und eigene NetDiscovery-Suche nach der gid (Rundruf und Unicast an wlan.addrs
#     und die addr der Erben); Fund mit gen ≥ Sicherung → folgen (ClientTable.move_to, Signal moved → watch mit frischen Zählern).
#     Sonst waiting nur mit lan_ok() (eine eigene Adresse im Netz des alten Gastgebers; net_check einspritzbar) – sonst nie automatisch.
#     checking im WLAN: LAN_SEARCH_MS suchen und frisch verbinden; gemischt danach eine Probe beim Vermittler mit eigenem Token
#     (antwortet dort ein Gastgeber → follow_room). WLAN-Gäste einer gemischten Partie proben den Raum auch in waiting.
#   - Spiel-WLAN (wlan.ap) weg (lan_ok falsch): nur Rang 0 übernimmt, wenn der Gastgeber das Netz führte (ap_seat = host_seat), und
#     öffnet nach wifi_release ein eigenes (Hinweis „… Öffne das Spiel-WLAN …“, auto_open); alle anderen → scan (scan_names: wessen
#     Netz weg ist, wer ein neues öffnet). scan sucht weiter und folgt bei einem Fund; von Hand bleibt continue_as_host (Warnzeile).
#   - move vom Gastgeber (10.7): lan → move_to, online → follow_room, qr → scan mit dem Namen des neuen Gastgebers.
#   - Geplante Übergabe (Ziel) mit how: lan/online – resume, dann handover_ok{port} über den Gast-Socket und leeren (send_and_drain),
#     erst dann suspend; qr – handover_ok{qr} geleert, suspend, wifi_release, resume, eigenes Spiel-WLAN. Ohne Raum gilt sofort.
#   - Abtreten (stepped_down) nach HostTable.step_target: lan → Gast beim neuen Server, online wie 1.6.1, qr → eigenes Spiel-WLAN zu
#     (wifi_stop), Gast-Tisch ohne Verbindung im Zustand scan – Nachtest 1.6.2: die ersten handoff_wait_ms nur warten (handed_off,
#     „Einen Moment – der Gastgeber wechselt.“, QR-Knopf), ohne „Spiel als Gastgeber fortsetzen“.
#   - Gemischt: Ein WLAN-Erbe ohne Vermittler (Netzfehler, Frist; nicht 4404/4403) führt fürs LAN sofort weiter; der Raum wird im
#     Hintergrund alle room_retry_ms erneut übernommen.
#   - resume_new_room() in gone (Tisch) und expired (Hauptmenü): alte Partie in einem neuen Raum (gen + 1 bei einem Gast-Stand),
#     Warteliste offen. saved_offer/resume_saved: auch WLAN-Gast-Dateien und abgelaufene Räume (resumable(…, true)); WLAN-Dateien
#     suchen zuerst menu_search_ms nach der gid (Fund → als Gast weiter), sonst eigene Datei sofort fortsetzen (bei wlan.ap Rückfrage
#     mit ap:true: „Spiel-WLAN neu öffnen“ = confirm_resume(true), „Beim neuen Gastgeber scannen“ = cancel()), Gast-Datei Rückfrage.
#
# Oberfläche: swapped(new_source, note) → Tisch ersetzen (nav.replace(TableScreen.create(new_source))) und note zeigen. Zustand
# (state_changed), missing(), countdown_ms(), can_continue()/continue_warnings()/continue_as_host() für den Verbindungsstreifen.
# Tests: auto_process = false und pump() selbst rufen; Fristen als Eigenschaften, wall_ms einspritzbar, host_factory/client_factory.

signal state_changed(state: String)
signal swapped(new_source: TableSource, note: String)   # neue Quelle für den Tisch (ohne Elternknoten; HostSwitch hängt schon daran)
signal confirm_needed(info: Dictionary)                 # resume_saved: Rückfrage {role, age_min, warnings: [lt], ap}

const NODE_NAME := "HostSwitch"
const WATCH_PHASES := ["turn", "drawn", "challenge", "color", "gamble", "discard_pick", "round_over"]   # MauGame.PLAY_PHASES + round_over
const GUEST_STATES := ["off", "watch", "missing", "waiting", "checking", "scan"]

var auto_process := true
var automatic := true                # automatische Übernahme nach Rang (sonst nur von Hand)
var t_silent_ms := NetProtocol.T_SILENT_MS
var t_away_ms := NetProtocol.T_AWAY_MS
var away_link_ms := NetProtocol.AWAY_LINK_MS
var t_step_ms := NetProtocol.T_STEP_MS
var probe_ms := NetProtocol.PROBE_MS
var takeover_within_ms := NetProtocol.HANDOVER_WITHIN_MS   # automatische Übernahme: so lange bis zum room-Rahmen
var join_wait_ms := 15000            # Abtreten: so lange auf das welcome warten, dann trotzdem wechseln
var wall_ms := Callable()            # Tests: () -> Wanduhr in ms (sonst Time.get_unix_time_from_system)
var save_path := TableSource.NET_SAVE_PATH
var port_first := NetProtocol.PORT
var port_last := NetProtocol.PORT_LAST
var host_factory := Callable()       # () -> HostTable (Standard GameStarter.host())
var client_factory := Callable()     # () -> ClientTable (Standard GameStarter.client())
var host_setup := Callable()         # (HostTable) -> void: weitere Einstellungen nach dem Anlegen
var client_setup := Callable()       # (ClientTable) -> void
# --- WLAN und Spiel-WLAN (Beta 1.6.2) ---
var lan_search_ms := NetProtocol.LAN_SEARCH_MS   # checking im WLAN: so lange suchen, bevor übernommen wird
var menu_search_ms := 3000           # Hauptmenü, WLAN-Datei: so lange nach der gid suchen
var room_retry_ms := 15000           # WLAN-Erbe ohne Vermittler: so oft den Raum erneut übernehmen
var room_probe_every_ms := 10000     # WLAN-Gast einer gemischten Partie in waiting: so oft beim Vermittler proben
var discovery_port := NetProtocol.DISCOVERY_PORT
var discovery_setup := Callable()    # Tests: (NetDiscovery) -> void – use_broadcast, probe_local, ports, now_ms
var net_check := Callable()          # Tests: (Adressen des alten Gastgebers: Array) -> bool, ersetzt lan_ok()
var wifi_release := Callable()       # () -> void: Spiel-WLAN aus dem QR-Code freigeben (Standard QrJoin.wifi_release)
var wifi_stop := Callable()          # () -> void: eigenes Spiel-WLAN schließen (Standard NetAndroid.game_wifi_stop)
var auto_open := Callable()          # (HostTable) -> void: eigenes Spiel-WLAN öffnen (Tests; der Tisch öffnet es nach dem Hinweis selbst)
var game_wifi_pending := false       # nach einer Übernahme mit Spiel-WLAN: ein eigenes öffnen (take_game_wifi_request)
var handoff_wait_ms := 60000         # Nachtest 1.6.2: nach dem Abtreten mit qr so lange nur warten (kein „Spiel als Gastgeber fortsetzen“)

var state := "off"
var source: TableSource              # überwachte Quelle (ClientTable oder HostTable), null im Ablauf resume_saved
var last_error := ""                 # deutsche msgid (I18n.t), z. B. Raum abgelaufen
var takeovers := 0                   # Tests/Log: so oft hat dieses Gerät übernommen
var follows := 0                     # Tests/Log (Beta 1.6.2): so oft ist dieser Gast einem neuen Gastgeber gefolgt (Suche, move, Raum)

# Gast-Wächter
var _armed_at := 0
var _away_since := 0
var _seen_rev := -1
var _probe_at := 0
var _probe_welcomes := 0
var _take_at := -1
var _check := ""                     # checking/resuming: "join" | "info" | "fresh" | "decided"; WLAN: "lan" | "room" | "search"
var _manual := false
# Übernahme
var _new: Node                       # HostTable (taking) bzw. ClientTable (joining) im Aufbau
var _take_until := 0
var _back_state := "watch"           # Zustand nach einer abgebrochenen Übernahme
var _new_autosave := true            # autosave des neuen Gastgeber-Tisches, gilt erst ab _finish_take
# Gastgeber
var _probe: NetClient
var _probe_info := {}
var _probe_retry_at := -1
# Abläufe mit eigenem Gast-Tisch (Abtreten, Hauptmenü)
var _flow_ct: ClientTable
var _join_until := 0
var _join_name := ""
var _saved := {}
var _pending_ho := {}                 # {t:"handover"}, wird in pump() ausgeführt
var _note_lt: Array = []              # nach einer Übernahme: Meldung an alle („… ist jetzt Gastgeber.“)
var _note_wait: Array = []            # … sobald diese Gäste (Token) wieder verbunden sind
var _note_until := 0                  # … spätestens dann
# WLAN und Spiel-WLAN (Beta 1.6.2)
var _search: NetDiscovery             # eigene Suche nach der gid (Gast: missing/waiting/checking/scan; Hauptmenü)
var _scan_name := ""                  # scan: Name dessen, der ein neues Spiel-WLAN öffnet ("" = nach Regel aus der Sicherung)
var _scan_next := ""                  # Abtreten mit qr: an der neuen Quelle gleich nach scan (mit diesem Namen)
var _take_lan := false                # Übernahme fürs WLAN: ohne Vermittler gilt sie trotzdem (Raum im Hintergrund wiederholen)
var _take_ap := false                 # Übernahme mit eigenem Spiel-WLAN (das alte ist weg bzw. geplant mit how "qr")
var _take_room := {}                  # online-Teil des übernommenen Stands (Hintergrund-Wiederholung)
var _new_room := ""                   # resume_new_room: Vermittler, bei dem ein neuer Raum entsteht
var _room_retry := {}                 # Gastgeber: {room, at} – Raum erneut übernehmen, bis er offen ist
var _room_probe: NetClient            # WLAN-Gast einer gemischten Partie: Probe beim Vermittler mit eigenem Token
var _room_probe_at := 0
var _pending_move := {}               # {t:"move"}, wird in pump() ausgeführt
var _ho_how := ""                     # how des zuletzt empfangenen handover (roh, aus host_message)
var _handoff_until := 0               # Nachtest 1.6.2: scan nach eigenem Abtreten mit qr – bis dahin warten statt übernehmen (handed_off)


func _init() -> void:
	name = NODE_NAME


# Vorhandenen HostSwitch einer Quelle holen oder anlegen (Kind der Quelle).
static func ensure(src: TableSource) -> HostSwitch:
	var s := src.get_node_or_null(NODE_NAME) as HostSwitch
	if s == null:
		s = HostSwitch.new()
		src.add_child(s)
		s.attach(src)
	return s


# Frist bis „Gastgeber fehlt“ (Abschnitt 4.3): last = letzte Nachricht, gone = 4503 (0 = keins), away_since = away des Gastgebers.
# Beta 1.6.2: im WLAN ist gone der erste gescheiterte Neuversuch (NetClient.host_lost_wall).
static func deadline_for(last: int, gone: int, away_since: int, t_silent: int, t_away: int, link: int) -> int:
	if away_since > 0 and (gone <= 0 or away_since <= gone + link):
		return maxi(away_since + t_away, (gone if gone > 0 else last) + t_silent)
	if gone > 0:
		return gone + t_silent
	return last + t_silent


# Fortsetzbarer Stand aus der Datei ({} = nichts anzubieten). Beta 1.6.2: online, WLAN (Gastgeber- und Gast-Datei) und auch ein
# abgelaufener Online-Raum (resume_new_room, 10.13).
static func saved_offer(path := TableSource.NET_SAVE_PATH, now_unix := -1) -> Dictionary:
	var d := MatchSnapshot.read(path)
	var now := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	if d.is_empty() or not MatchSnapshot.resumable(d, now, true):
		return {}
	return d


func attach(src: TableSource) -> void:
	_detach()
	source = src
	_reset_watch()
	if src is HostTable:
		var ht := src as HostTable
		ht.stepped_down.connect(_on_stepped_down)
		ht.online_check.connect(_on_online_check)
		_go("host")
	elif src is ClientTable:
		var ct := src as ClientTable
		ct.clock = now_wall
		ct.listen_port = port_first          # hello.hp: hier würde dieses Gerät als Gastgeber lauschen
		if ct.client != null:
			ct.client.clock = now_wall
		if not ct.handover_received.is_connected(_on_handover):
			ct.handover_received.connect(_on_handover)
		if not ct.moved.is_connected(_on_moved):
			ct.moved.connect(_on_moved)
		if not ct.host_message.is_connected(_on_host_message):
			ct.host_message.connect(_on_host_message)
		_go("off")
		if _scan_next != "":
			var n := _scan_next
			_scan_next = ""
			_handoff_until = now_wall() + maxi(handoff_wait_ms, 0)   # vor _enter_scan: schon state_changed sieht handed_off()
			_enter_scan(n)


func now_wall() -> int:
	return int(wall_ms.call()) if wall_ms.is_valid() else int(Time.get_unix_time_from_system() * 1000.0)


# --- für die Oberfläche ---

# Gastgeber fehlt (Streifen „Gastgeber antwortet nicht …“, Knopf „Spiel als Gastgeber fortsetzen“)
func missing() -> bool:
	return state in ["missing", "waiting", "checking"]


# Restzeit bis zur automatischen Übernahme (ms); −1 = keine Automatik (kein Rang, nicht aktuell) bzw. gerade keine Wartezeit.
func countdown_ms() -> int:
	if state != "waiting" or _take_at < 0 or _manual:
		return -1
	return maxi(_take_at - now_wall(), 0)


func rank() -> int:
	var ct := _watched()
	if ct == null or ct.backup.is_empty() or ct.client == null:
		return -1
	return (ct.backup.get("heirs", []) as Array).find(ct.client.token)


func is_current() -> bool:
	var ct := _watched()
	return ct != null and ct.backup_current()


# Nachtest 1.6.2: Dieses Gerät hat eben selbst geplant mit qr abgegeben (eigenes Spiel-WLAN beim Abtreten geschlossen) und steht
# deshalb in scan. Bis handoff_wait_ms vorbei sind, ist das kein Ausfall: Streifen „Einen Moment – der Gastgeber wechselt.“ (mit
# QR-Knopf zum neuen Spiel-WLAN), kein „Spiel als Gastgeber fortsetzen“ – ein Tipp dort eröffnete einen zweiten Zweig. Kommt das
# Ziel bis dahin nicht an, gilt scan wie nach einem Ausfall.
func handed_off() -> bool:
	return state == "scan" and _handoff_until > 0 and now_wall() < _handoff_until


# Knopf „Spiel als Gastgeber fortsetzen“ möglich? (jeder App-Gast mit Sicherung, sobald der Gastgeber fehlt; Beta 1.6.2 auch in scan,
# Nachtest 1.6.2 nicht direkt nach dem eigenen Abtreten: handed_off)
func can_continue() -> bool:
	var ct := _watched()
	if state == "scan":
		return ct != null and not ct.backup.is_empty() and ct.backup_seat() >= 0 and not ct.is_retired() and not handed_off()
	return state in ["missing", "waiting"] and ct != null and _armed(ct)


# Warnzeilen zur Rückfrage (Bausteine): Sicherung nicht aktuell; Beta 1.6.2: im Zustand scan „Nur wenn %s nicht übernimmt …“, als
# Online-Gast mit WLAN-Mitspielern „WLAN-Mitspieler brauchen dann Internet.“ („… kommen dann nicht mit.“ entfällt, 10.12).
func continue_warnings() -> Array:
	var ct := _watched()
	var out := _warnings(ct.backup if ct != null else {}, ct != null and ct.backup_current())
	if state == "scan":
		out.append(I18n.part("Nur wenn %s nicht übernimmt – sonst gibt es zwei Spiele.", [str(scan_names()[1])]))
	elif ct != null and ct.client != null and ct.client.is_online() and bool(ct.backup.get("wlan_humans", false)):
		out.append(I18n.part("WLAN-Mitspieler brauchen dann Internet."))
	return out


# „Spiel als Gastgeber fortsetzen“ (nach der Rückfrage): /info und frische Probe, dann Übernahme. false = gerade nicht möglich.
func continue_as_host() -> bool:
	if not can_continue():
		return false
	var ct := _watched()
	_manual = true
	if ct.client == null:
		_take_over_backup(ct)                # scan ohne Verbindung (abgetretener Gastgeber im Spiel-WLAN): nichts zu prüfen
		return true
	_probe_welcomes = ct.client.welcomes
	_begin_final()
	return true


# Beta 1.6.2 (10.8): Spiel-WLAN weg – [wessen Netz weg ist, wer ein neues öffnet] (Streifen „Spiel-WLAN von %s ist weg.“, Knopf
# „Neues Spiel-WLAN bei %s – QR-Code scannen“). Führte der Gastgeber das Netz, öffnet Rang 0 ein neues, sonst der Gastgeber selbst.
func scan_names() -> Array:
	var ct := _watched()
	var names := scan_names_of(ct.backup if ct != null else _saved)
	if _scan_name != "":
		names[1] = _scan_name
	return names


static func scan_names_of(d: Dictionary) -> Array:
	var hs := int(d.get("host_seat", -1))
	var ap := _ap_seat_of(d)
	var opener := hs
	if ap == hs:
		opener = -1
		var heirs: Array = d.get("heirs", []) if d.get("heirs") is Array else []
		if not heirs.is_empty():
			opener = ClientTable._seat_of_token(d, str(heirs[0]))
	return [_seat_name(d, ap) if ap >= 0 else "?", _seat_name(d, opener) if opener >= 0 else "?"]


# Beta 1.6.2: Liegt eine eigene Adresse im Netz des alten Gastgebers (Adresse der Verbindung, wlan.addrs)? Ohne wird im WLAN nie
# automatisch übernommen (Gegenstück zu NetClient.reached online). net_check ersetzt die Prüfung in Tests.
func lan_ok() -> bool:
	var ct := _watched()
	var d: Dictionary = ct.backup if ct != null else _saved
	var targets: Array = []
	if ct != null and NetProtocol.ipv4_to_int(ct.address) > 0:
		targets.append(ct.address)
	var w: Dictionary = d.get("wlan", {}) if d.get("wlan") is Dictionary else {}
	for a in w.get("addrs", []):
		if NetProtocol.ipv4_to_int(str(a)) > 0 and not targets.has(str(a)):
			targets.append(str(a))
	if net_check.is_valid():
		return bool(net_check.call(targets))
	var mine := -1
	if ct != null:
		mine = ct.backup_seat()
	elif str(d.get("role", "")) == "guest":
		mine = int(d.get("my_seat", -1))
	return lan_reach(d, targets, mine, NetAddresses.interfaces())


# Gerätetest 1.6.2 (F1): Reine Entscheidung zu lan_ok(). targets = Adressen des alten Gastgebers, mine = eigener Platz in d (−1 =
# unbekannt), ifaces = eigene Schnittstellen [{address, prefix}].
# - Führte der alte Gastgeber selbst das Spiel-WLAN (wlan.ap, ap_seat = Gastgeber) und sah er diesen Platz unter einer Adresse
#   (seats[mine].addr), dann ist sein Netz nur noch da, wenn diese eigene Adresse noch da ist. Sonst ist das Spiel-WLAN weg – auch
#   wenn das Heim-WLAN, in das Android von selbst zurückging, die alte Adresse zufällig mit umfasst (S10: 192.168.178.9/16 gegen
#   192.168.35.250; ohne diese Regel lief die Übernahme als normale WLAN-Übernahme, ohne eigenes Spiel-WLAN).
# - Sonst: Liegt eine eigene Adresse im selben Netz (Präfix der eigenen Schnittstelle) wie eine Adresse des alten Gastgebers?
static func lan_reach(d: Dictionary, targets: Array, mine: int, ifaces: Array) -> bool:
	for t in targets:
		if str(t).begins_with("127."):
			return true                      # PC-Tests: alles auf diesem Rechner
	if _is_ap(d) and _ap_seat_of(d) == int(d.get("host_seat", -1)):
		var seats: Array = d.get("seats", []) if d.get("seats") is Array else []
		var addr := ""
		if mine >= 0 and mine < seats.size() and seats[mine] is Dictionary:
			addr = str((seats[mine] as Dictionary).get("addr", ""))
		if NetProtocol.ipv4_to_int(addr) > 0 and not addr.begins_with("127."):
			if not ifaces.any(func(i): return i is Dictionary and str(i.get("address", "")) == addr):
				return false                 # eigene Adresse im Spiel-WLAN weg: das Netz des Gastgebers ist weg
	for i in ifaces:
		if not i is Dictionary:
			continue
		for t in targets:
			if NetProtocol.same_net(str(i.get("address", "")), str(t), int(i.get("prefix", 24))):
				return true
	return false


# Beta 1.6.2: nach einer Übernahme mit Spiel-WLAN soll der Tisch ein eigenes öffnen (einmal; true = jetzt öffnen).
func take_game_wifi_request() -> bool:
	var p := game_wifi_pending
	game_wifi_pending = false
	return p


# Hauptmenü „Partie fortsetzen“: Stand aus der Datei (saved_offer). Ablauf siehe oben; Ergebnis über swapped bzw. confirm_needed.
func resume_saved(data: Dictionary) -> Error:
	var d := MatchSnapshot.clean(data)
	if d.is_empty() or not MatchSnapshot.resumable(d, now_wall() / 1000, true):
		return ERR_INVALID_DATA
	var mine := int(d.host_seat) if str(d.role) == "host" else int(d.my_seat)
	if mine < 0 or MatchSnapshot.seat_token(d, mine) == "":
		return ERR_INVALID_DATA
	_detach()
	_saved = d
	last_error = ""
	var o: Dictionary = d.online
	if o.is_empty():
		# Beta 1.6.2 (10.14): WLAN – zuerst nach der gid suchen (führt schon jemand?), dann eigener Zweig bzw. Rückfrage
		_check = "search"
		_probe_at = now_wall()
		_start_search(d, null)
		_go("resuming")
		return OK
	var ct := _make_client()
	add_child(ct)
	_flow_ct = ct
	ct.handover_received.connect(_on_handover)
	ct.join(NetProtocol.room_link(str(o.relay), str(o.room)), 0, str(d.seats[mine].name), MatchSnapshot.seat_token(d, mine))
	ct.use_backup(d)                        # hello.bk: Abstammung (ein jüngerer Zweig auf diesem Gerät wird zurückgeholt)
	_check = "join"
	_probe_at = now_wall()
	_probe_welcomes = 0
	_go("resuming")
	return OK


func confirm_resume(yes: bool) -> void:
	if state != "confirm":
		return
	if yes:
		_resume_from_saved()
	else:
		cancel()


# Ablauf abbrechen (Hauptmenü „Weiter warten“/Zurück): eigener Gast-Tisch weg, Datei bleibt.
func cancel() -> void:
	if _flow_ct != null:
		_free_flow_ct()
	_end_probe()
	_end_room_probe()
	_stop_search()
	if _new != null and is_instance_valid(_new) and _new is HostTable:
		_drop_host(_new as HostTable)
	_new = null
	_new_room = ""
	_go("off")


# Beta 1.6.2 (10.13): „In neuem Raum fortsetzen“ möglich? Raum abgelaufen (gone am Tisch, expired im Hauptmenü) und ein Stand mit
# Vermittler-Adresse liegt vor.
func can_new_room() -> bool:
	var d := _new_room_data()
	return not d.is_empty() and str((d.get("online", {}) as Dictionary).get("relay", "")) != ""


# „In neuem Raum fortsetzen“: alte Partie mit neuem Raum beim selben Vermittler (gen + 1 bei einem Gast-Stand, eigener Zweig behält
# sie), Warteliste offen; Ergebnis über swapped mit „Neuer Raum %s …“. false = gerade nicht möglich.
func resume_new_room() -> bool:
	if not can_new_room():
		return false
	var d := _new_room_data()
	var seat := -1
	if state == "gone":
		seat = _watched().backup_seat()
	elif str(d.get("role", "")) == "guest":
		seat = int(d.get("my_seat", -1))
	var data := d.duplicate(true)
	_new_room = str((d.online as Dictionary).get("relay", ""))
	data["online"] = {}                      # der alte Raum gilt nicht mehr
	_back_state = state
	_take_lan = false
	_take_ap = false
	_end_probe()
	_end_room_probe()
	_stop_search()
	_take_over(data, seat, takeover_within_ms, [])
	return state in ["taking", "host"]


# --- Ablauf ---

func _process(_delta: float) -> void:
	if auto_process:
		pump()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and state == "watch":
		_armed_at = now_wall()      # eigene Pause zählt nicht als Stille des Gastgebers


func pump() -> void:
	var now := now_wall()
	if not _pending_ho.is_empty():
		var m := _pending_ho
		_pending_ho = {}
		_handle_handover(m)
	if not _pending_move.is_empty():
		var mv := _pending_move
		_pending_move = {}
		_handle_move(mv)
	match state:
		"off", "watch", "missing", "waiting", "checking", "scan":
			_poll_guest(now)
		"taking":
			_poll_taking(now)
		"host":
			_poll_note(now)
			_poll_room_retry(now)
		"probe":
			_poll_probe(now)
		"joining":
			_poll_joining(now)
		"resuming":
			_poll_resume(now)
		"confirm":
			_poll_resume(now)


func _poll_guest(now: int) -> void:
	var ct := source as ClientTable
	if ct == null:
		return
	var c := ct.client
	if c == null:
		if state == "scan":
			_poll_search_follow(ct)          # abgetretener Gastgeber (qr): ohne Verbindung, nur die Suche
		elif state != "off":
			_stop_search()
			_end_room_probe()
			_go("off")
		return
	if ct.view_rev != _seen_rev:
		_seen_rev = ct.view_rev
		if ct.host_away():
			if _away_since == 0:
				_away_since = now
		else:
			_away_since = 0
	var armed := _armed(ct)
	if state == "off":
		if armed:
			_reset_watch()
			_armed_at = now
			_go("watch")
		return
	if not armed and not _manual:
		_reset_watch()
		_stop_search()
		_end_room_probe()
		_go("off")
		return
	if state != "watch" and c.welcomes > _probe_welcomes:
		_back_to_watch(now)          # ein Gastgeber hat geantwortet (auch ein neuer)
		return
	if state != "watch" and _poll_search_follow(ct):
		return                       # Beta 1.6.2: Suche hat die Partie gefunden – umgezogen (moved → watch)
	match state:
		"watch":
			if _armed_at > now:
				_armed_at = now              # Uhr zurückgestellt: ab jetzt zählen
			var last := maxi(c.last_host_wall if c.last_host_wall <= now else _armed_at, _armed_at)
			var lost := _lost_wall(c)
			var gone := lost if lost >= last and lost <= now else 0
			if now >= deadline_for(last, gone, _away_since, t_silent_ms, t_away_ms, away_link_ms):
				_start_probe(c, now)
				if not c.is_online():
					_start_search(ct.backup, ct)
				_go("missing")
		"missing":
			if not c.is_online():
				_poll_missing_lan(ct, c, now)
				return
			var away_hit := c.away_code_wall >= _probe_at
			if away_hit or now - _probe_at >= probe_ms:
				if c.reached or away_hit:
					_take_at = -1
					var r := rank()
					if automatic and r >= 0 and ct.backup_current():
						_take_at = now + r * t_step_ms
					_go("waiting")
				else:
					_start_probe(c, now)     # Vermittler nicht erreichbar (eigenes Netz weg): weiter versuchen, nie übernehmen
		"waiting":
			if not c.is_online() and _poll_room_follow(ct, now):
				return
			if _take_at >= 0 and now >= _take_at:
				_begin_final()
		"checking":
			_poll_final(ct, now)


# Beta 1.6.2 (10.4, 10.8): missing im WLAN – nach probe_ms ohne welcome und ohne Fund.
func _poll_missing_lan(ct: ClientTable, c: NetClient, now: int) -> void:
	if now - _probe_at < probe_ms:
		return
	var d: Dictionary = ct.backup
	var r := rank()
	var lan := lan_ok()
	if _is_ap(d) and not lan:
		# Spiel-WLAN weg: Führte der Gastgeber das Netz, übernimmt nur Rang 0 (und öffnet ein eigenes); alle anderen scannen. Führte es
		# ein anderer (der Gastgeber saß selbst darin), öffnet der Gastgeber ein neues – niemand übernimmt.
		if _ap_seat_of(d) == int(d.get("host_seat", -1)) and r == 0:
			# Gegenprüfung 1.6.2: nicht sofort – „Netz weg“ kann auch nur ein Funkloch dieses Geräts sein (anderes Zimmer). Noch
			# t_step_ms mit Countdown (Neuverbinden und Suche laufen weiter; ein welcome beendet das Warten), dann erst übernehmen.
			_take_at = now + t_step_ms if automatic and ct.backup_current() else -1
			_go("waiting")
		else:
			_enter_scan("")
		return
	if not lan:
		_start_probe(c, now)         # eigenes Netz weg: weiter versuchen und suchen, nie automatisch übernehmen
		return
	_take_at = -1
	if automatic and r >= 0 and ct.backup_current():
		_take_at = now + r * t_step_ms
	_go("waiting")


func _poll_final(ct: ClientTable, now: int) -> void:
	var c := ct.client
	if _check == "lan":
		# Beta 1.6.2: im WLAN LAN_SEARCH_MS suchen und frisch verbinden (Fund bzw. welcome erledigt _poll_guest)
		if now - _probe_at < lan_search_ms:
			return
		if (ct.backup.get("online", {}) as Dictionary).is_empty():
			_take_over_backup(ct)
		else:
			_check = "room"                  # gemischt: führt schon jemand den Raum?
			_end_room_probe()
			_start_room_probe(ct)
		return
	if _check == "room":
		if _room_probe == null:
			_start_room_probe(ct)
			return
		_room_probe.poll()
		var pr := _room_probe.probe_result
		if pr == "":
			return
		_end_room_probe()
		if pr == "answered":
			_follow_room(ct)                 # ein Online-Erbe führt: über den Raum weiter
		else:
			_take_over_backup(ct)            # niemand im Raum bzw. Vermittler nicht erreichbar: fürs LAN übernehmen (10.12)
		return
	if _check == "info":
		if c.info_pending():
			return
		var r := c.info_result
		if not bool(r.get("ok", false)):
			_retry_later(now)                # Vermittler nicht erreichbar: nie blind übernehmen
		elif not bool(r.get("open", true)):
			last_error = "Der Online-Raum ist abgelaufen. Die Partie lässt sich nicht mehr fortsetzen."
			_go("gone")
		elif not bool(r.get("host", true)):
			_take_over_backup(ct)
		else:
			_check = "fresh"                 # jemand ist angemeldet: frische Probe (der Ersatz kennt meine alte c vielleicht nicht)
			_start_probe(c, now)
		return
	if _check == "fresh":
		var away_hit := c.away_code_wall >= _probe_at
		if away_hit:
			_take_over_backup(ct)            # der Angemeldete ist inzwischen weg
		elif now - _probe_at >= probe_ms:
			if c.reached:
				_take_over_backup(ct)        # angenommen, aber niemand antwortet: der Angemeldete ist ein totes Socket
			else:
				_retry_later(now)


func _begin_final() -> void:
	var ct := _watched()
	if not ct.client.is_online():
		_check = "lan"                       # Beta 1.6.2: WLAN – suchen und frisch verbinden statt /info
		_start_probe(ct.client, now_wall())
		_start_search(ct.backup, ct)
		_go("checking")
		return
	_check = "info"
	ct.client.query_info()
	_go("checking")


func _retry_later(now: int) -> void:
	_take_at = now + probe_ms
	_check = ""
	_go("waiting")


func _start_probe(c: NetClient, now: int) -> void:
	_probe_at = now
	_probe_welcomes = c.welcomes
	c.reconnect_now()


func _back_to_watch(now: int) -> void:
	_reset_watch()
	_stop_search()
	_end_room_probe()
	_armed_at = now
	_go("watch")


func _reset_watch() -> void:
	_take_at = -1
	_check = ""
	_manual = false
	_away_since = 0
	_seen_rev = -1
	_scan_name = ""
	_handoff_until = 0


# Beta 1.6.2: scharf auch im WLAN (Sicherung derselben gid; WLAN oder Raum).
func _armed(ct: ClientTable) -> bool:
	if ct == null or ct.client == null or ct.backup.is_empty() or ct.is_retired() or not ct.backups:
		return false
	if not ct.client.is_online() and ct.address == "":
		return false
	if not ct.phase() in WATCH_PHASES:
		return false
	var gid := ct.game_gid()
	return gid != "" and str(ct.backup.get("gid", "")) == gid and ct.backup_seat() >= 0


func _watched() -> ClientTable:
	return source as ClientTable


func _guest() -> ClientTable:
	return _flow_ct if _flow_ct != null else source as ClientTable


static func _warnings(_d: Dictionary, current: bool) -> Array:
	var out: Array = []
	if not current:
		out.append(I18n.part("Dein Spielstand ist vielleicht nicht der neueste."))
	return out


# Gegenstück zu 4503 (Beta 1.6.2): online das erste 4503, im WLAN der erste gescheiterte Neuversuch.
static func _lost_wall(c: NetClient) -> int:
	return c.host_away_wall if c.is_online() else c.host_lost_wall


# --- WLAN: Suche, Umzug, Spiel-WLAN (Beta 1.6.2) ---

# Spiel-WLAN der Partie (wlan.ap) laut Stand
static func _is_ap(d: Dictionary) -> bool:
	var w: Dictionary = d.get("wlan", {}) if d.get("wlan") is Dictionary else {}
	return bool(w.get("ap", false))


# Platz, dessen Handy das Spiel-WLAN führt (ohne Feld bzw. −1: der Gastgeber, Stand einer 1.6.1-App)
static func _ap_seat_of(d: Dictionary) -> int:
	var w: Dictionary = d.get("wlan", {}) if d.get("wlan") is Dictionary else {}
	var s := int(w.get("ap_seat", -1))
	return s if s >= 0 else int(d.get("host_seat", -1))


# Suche nach der gid starten bzw. Unicast-Ziele ergänzen: wlan.addrs, Adresse der Verbindung, addr der Erben (10.4).
func _start_search(d: Dictionary, ct: ClientTable) -> void:
	if _search == null:
		_search = NetDiscovery.new()
		_search.name = "Suche"
		_search.auto_poll = false
		if discovery_setup.is_valid():
			discovery_setup.call(_search)
		add_child(_search)
		if _search.start_search(discovery_port) != OK:
			push_warning("HostSwitch: Suche nicht möglich")
	var targets: Array = []
	if ct != null and NetProtocol.ipv4_to_int(ct.address) > 0:
		targets.append(ct.address)
	var w: Dictionary = d.get("wlan", {}) if d.get("wlan") is Dictionary else {}
	targets.append_array(w.get("addrs", []))
	var seats: Array = d.get("seats", []) if d.get("seats") is Array else []
	for t in d.get("heirs", []):
		var s := ClientTable._seat_of_token(d, str(t))
		if s >= 0:
			targets.append(str((seats[s] as Dictionary).get("addr", "")))
	for a in targets:
		if NetProtocol.ipv4_to_int(str(a)) > 0:
			_search.add_manual(str(a))


func _stop_search() -> void:
	if _search == null:
		return
	var s := _search
	_search = null
	s.stop()
	if s.get_parent() == self:
		remove_child(s)
	s.free()


# Gastgeber derselben Partie mit gen ≥ Stand gefunden? Der gerade vermisste Gastgeber selbst (gleiche Adresse und Port) zählt nicht.
func _found(d: Dictionary, skip_addr := "", skip_port := 0) -> Dictionary:
	if _search == null:
		return {}
	_search.poll()
	var gid := str(d.get("gid", ""))
	if gid == "":
		return {}
	for e in _search.find_gid(gid):
		if int(e.get("gen", 0)) < int(d.get("gen", 0)) or int(e.get("port", 0)) <= 0:
			continue
		if skip_port > 0 and int(e.port) == skip_port and (str(e.address) == skip_addr or (e.get("addresses", []) as Array).has(skip_addr)):
			continue
		return e
	return {}


# Suche abfragen; bei einem Fund umziehen (move_to → moved → watch). true = umgezogen.
func _poll_search_follow(ct: ClientTable) -> bool:
	if _search == null or ct.backup.is_empty():
		return false
	var e := _found(ct.backup, ct.address, ct.port)
	if e.is_empty():
		return false
	follows += 1
	_stop_search()
	_end_room_probe()
	ct.move_to(str(e.address), int(e.port))
	if ct.client == null or state != "watch":
		_back_to_watch(now_wall())
	return true


# Gemischt (10.12): WLAN-Gast in waiting probt den Raum; antwortet dort ein Gastgeber, geht es über den Raum weiter. true = gefolgt.
func _poll_room_follow(ct: ClientTable, now: int) -> bool:
	if (ct.backup.get("online", {}) as Dictionary).is_empty():
		return false
	if _room_probe == null:
		if now >= _room_probe_at:
			_start_room_probe(ct)
		return false
	_room_probe.poll()
	var pr := _room_probe.probe_result
	if pr == "":
		return false
	_end_room_probe()
	_room_probe_at = now + room_probe_every_ms
	if pr != "answered":
		return false
	_follow_room(ct)
	return true


func _start_room_probe(ct: ClientTable) -> void:
	var o: Dictionary = ct.backup.get("online", {})
	_room_probe = NetClient.new()
	_room_probe.name = "Raumprobe"
	_room_probe.auto_poll = false
	_room_probe.clock = now_wall
	add_child(_room_probe)
	_room_probe.connect_probe(str(o.get("relay", "")), str(o.get("room", "")), ct.player_name(), ct.own_seat_token(), probe_ms)


func _end_room_probe() -> void:
	if _room_probe == null:
		return
	var p := _room_probe
	_room_probe = null
	p.close()
	if p.get_parent() == self:
		remove_child(p)
	p.free()


# Über den Raum der Sicherung weiterspielen (10.5 _follow_room)
func _follow_room(ct: ClientTable) -> void:
	var o: Dictionary = ct.backup.get("online", {})
	follows += 1
	_stop_search()
	ct.follow_room(str(o.get("relay", "")), str(o.get("room", "")))
	if ct.client == null or state != "watch":
		_back_to_watch(now_wall())


# Spiel-WLAN weg (10.8): neuen QR-Code scannen; die Suche läuft weiter (alle im selben Ersatz-WLAN → folgen ohne Scan).
func _enter_scan(opener: String) -> void:
	var ct := _watched()
	_scan_name = opener
	_take_at = -1
	_end_room_probe()
	if ct != null:
		if ct.client != null:
			_probe_welcomes = ct.client.welcomes
		_start_search(ct.backup, ct)
	_go("scan")


# ClientTable.moved: neuer NetClient zählt von vorn (welcomes, last_host_wall) – Wächter mit frischen Zählern (10.5).
func _on_moved(_addr: String, _port: int) -> void:
	_stop_search()
	_end_room_probe()
	_probe_welcomes = 0
	if state in GUEST_STATES and state != "off":
		_back_to_watch(now_wall())


func _on_host_message(m: Dictionary) -> void:
	match str(m.get("t", "")):
		"move":
			_pending_move = m                # in pump(): dort darf der Tisch die Verbindung abbauen
		"handover":
			_ho_how = str(m.get("how", "")) if m.get("how") is String else ""


# {t:"move"} des alten Gastgebers (10.7, 10.11): lan → umziehen, online → über den Raum, qr → neuen QR-Code scannen.
func _handle_move(m: Dictionary) -> void:
	var ct := _watched()
	if ct == null or ct.is_retired() or not state in GUEST_STATES:
		return
	var mv := NetProtocol.clean_move(m, ct.game_gid())
	if mv.is_empty():
		return
	match str(mv.how):
		"lan":
			if ct.address == str(mv.addr) and ct.port == int(mv.port):
				return                       # schon dort (ClientTable bzw. Suche war schneller)
			follows += 1
			_stop_search()
			ct.move_to(str(mv.addr), int(mv.port))
			if ct.client == null or state != "watch":
				_back_to_watch(now_wall())
		"online":
			if ct.client != null and ct.client.is_online():
				return                       # Online-Gäste folgen über 4000/4012
			follows += 1
			_stop_search()
			ct.follow_room(str(mv.relay), str(mv.room))
			if ct.client == null or state != "watch":
				_back_to_watch(now_wall())
		"qr":
			_enter_scan(str(mv.name))


func _release_wifi() -> void:
	if wifi_release.is_valid():
		wifi_release.call()
	else:
		QrJoin.wifi_release()


func _stop_own_wifi() -> void:
	if wifi_stop.is_valid():
		wifi_stop.call()
	else:
		NetAndroid.game_wifi_stop()


# Nach der Übernahme ein eigenes Spiel-WLAN (10.8 Schritt 4): auto_open (Tests) bzw. Anfrage an den Tisch (take_game_wifi_request;
# der Tisch erkennt es auch am Hinweis „… Öffne das Spiel-WLAN …“).
func _want_game_wifi(ht: HostTable) -> void:
	game_wifi_pending = true
	if auto_open.is_valid():
		game_wifi_pending = false
		auto_open.call(ht)


# Gastgeber: Raum im Hintergrund erneut übernehmen, bis er offen ist (WLAN-Erbe ohne Vermittler, 10.12).
func _poll_room_retry(now: int) -> void:
	if _room_retry.is_empty():
		return
	var ht := source as HostTable
	if ht == null or ht.session == null:
		_room_retry = {}
		return
	var st := ht.session.online_state()
	if st in ["open", "stepped_down", "check", "away"]:
		if st != "away":
			_room_retry = {}
		return
	var r := ht.session.relay
	if r != null and r.close_code in [NetProtocol.CLOSE_ROOM_UNKNOWN, NetProtocol.CLOSE_BAD_TOKEN]:
		_room_retry = {}                     # Raum weg: weiter nur im LAN (später resume_new_room)
		return
	if not st in ["failed", "off"] or now < int(_room_retry.at):
		return
	_room_retry.at = now + room_retry_ms
	var o: Dictionary = _room_retry.room
	ht.session.open_online_existing(str(o.relay), str(o.room), str(o.token), o.get("conns", []), int(o.get("max_c", 0)),
		int(o.get("created_unix", 0)))


# --- Übernahme ---

func _take_over_backup(ct: ClientTable) -> void:
	var seat := ct.backup_seat()
	_back_state = "watch"
	var lan := ct.client == null or not ct.client.is_online()
	_take_lan = lan
	_take_ap = lan and _is_ap(ct.backup) and not lan_ok()    # Spiel-WLAN weg: eigenes öffnen (10.8)
	_stop_search()
	_end_room_probe()
	_take_over(ct.backup.duplicate(true), seat, takeover_within_ms,
		[I18n.part("%s führt das Spiel weiter (Gastgeber war weg).", [_seat_name(ct.backup, seat)])])


# Stand übernehmen: Gast-Socket zu (ohne bye), HostTable.resume(data, seat) samt Online-Raum; within_ms bis zum room-Rahmen.
# Beta 1.6.2: how = geplante Übergabe (handover_ok an den alten Gastgeber). lan/online: resume bei offenem Gast-Socket, dann
# handover_ok{port} geleert, dann suspend; qr: handover_ok{qr} geleert, suspend, wifi_release, dann resume. _take_ap: vorher
# wifi_release, danach eigenes Spiel-WLAN; _new_room: neuer Raum statt des alten.
func _take_over(data: Dictionary, seat: int, within_ms: int, note_lt: Array, how := "") -> void:
	var ct := _guest()
	var keep_open := ct != null and ct.client != null and how in ["lan", "online"]
	if ct != null and not keep_open:
		if how == "qr":
			ct.send_and_drain(NetProtocol.make_handover_ok(0, true))
		ct.suspend()
	if _take_ap:
		_release_wifi()                      # vor resume: bind_for("host") darf nicht am toten Netz hängen
	var ht := _make_host()
	add_child(ht)
	_new = ht
	# Die Datei bleibt, wie sie ist, bis der Raum übernommen ist (_finish_take): Stirbt die App vorher, läge sonst eine Gastgeber-Datei
	# (role "host", gen + 1) eines Geräts herum, das nie Gastgeber war – das Hauptmenü setzte sie ohne Rückfrage fort.
	_new_autosave = ht.autosave
	ht.autosave = false
	if ht.resume(data, seat, port_first, port_last) != OK:
		if keep_open:
			_drop_host(ht)                   # Gast-Socket steht noch: ablehnen, der alte Gastgeber taut auf
			_new = null
			_take_lan = false
			_take_ap = false
			ct.decline_handover()
			_reset_watch()
			_armed_at = now_wall()
			_go(_back_state)
			return
		_take_failed(false)
		return
	if keep_open:
		ct.send_and_drain(NetProtocol.make_handover_ok(ht.port(), false))   # vor dem 4000 des Vermittlers bzw. dem Abbau
		ct.suspend()
	_take_room = (data.get("online", {}) as Dictionary).duplicate(true)
	if _new_room != "":
		ht.session.open_online(_new_room)
		ht.set_join_open(true)
	_note_lt = note_lt                       # Meldung an alle, sobald die Gäste zurück sind (_poll_note)
	_note_wait = []
	for s in (data.get("seats", []) as Array).size():
		var p: Dictionary = data.seats[s]
		if s != seat and s != int(data.get("host_seat", -1)) and str(p.get("kind", "")) != "bot" and str(p.get("token", "")) != "":
			_note_wait.append(str(p.token))
	_take_until = now_wall() + maxi(within_ms, 0)
	_go("taking")
	if _take_room.is_empty() and _new_room == "":
		_finish_take()                       # WLAN: kein Raum zu übernehmen


func _poll_taking(now: int) -> void:
	var ht := _new as HostTable
	if ht == null or not is_instance_valid(ht):
		_new = null
		_go(_back_state)
		return
	_pump_node(ht)
	if ht.session == null:
		_take_failed(false)
		return
	var st := ht.session.online_state()
	var r := ht.session.relay
	var dead := r != null and r.close_code in [NetProtocol.CLOSE_ROOM_UNKNOWN, NetProtocol.CLOSE_BAD_TOKEN]
	var lan_first := _take_lan and _new_room == ""
	if st == "open":
		_finish_take()
	elif st == "stepped_down":
		_take_failed(false)                  # gleichzeitig übernommen und verloren (4000): wieder Gast, die eigene gen gilt nicht
	elif st == "failed" or st == "off":
		if lan_first:
			_finish_take(not dead)           # Beta 1.6.2 (10.12): WLAN-Erbe ohne Vermittler führt fürs LAN, Raum im Hintergrund
		else:
			_take_failed(dead and _new_room == "")
	elif now >= _take_until:
		if lan_first:
			_finish_take(true)
		else:
			_take_failed(false)


func _finish_take(retry_room := false) -> void:
	var ht := _new as HostTable
	_new = null
	takeovers += 1
	var ct := _guest()
	if ct != null:
		ct.retire()                          # Datei gehört jetzt dem Gastgeber-Tisch
	if _flow_ct != null:
		_free_flow_ct()
	_saved = {}
	ht.autosave = _new_autosave
	if ht.autosave and ht.game != null:
		TableSource.write_saved(ht.save_path, ht._snapshot())   # jetzt erst die eigene Gastgeber-Datei (Stand des letzten bk)
	var note := I18n.t("Du bist jetzt Gastgeber. Bitte lass die App offen.")
	if _new_room != "" and ht.session != null:
		note = I18n.t("Neuer Raum %s. Schick den anderen den Link – sie kommen damit auf ihre Plätze.") % str(ht.session.online_info().get("room", ""))
	elif _take_ap:
		note = I18n.t("Du bist jetzt Gastgeber. Öffne das Spiel-WLAN und lass die anderen den QR-Code scannen.")
	var ap := _take_ap
	var room := _take_room
	_take_lan = false
	_take_ap = false
	_take_room = {}
	_new_room = ""
	remove_child(ht)
	_move_to(ht)
	_note_until = now_wall() + ht.settle_max_ms
	_room_retry = {"room": room, "at": now_wall() + room_retry_ms} if retry_room and not room.is_empty() else {}
	# Gegenprüfung 1.6.2: Anfrage vor swapped – der neue Tisch holt sie beim Aufbau ab (ein Weg), statt sie ≤ 500 ms später in
	# _process ein zweites Mal zu öffnen
	if ap:
		_want_game_wifi(ht)
	swapped.emit(ht, note)


# Meldung nach einer Übernahme erst, wenn die Gäste zurück sind (sonst ginge sie ins Leere, wenn keine Einschwingzeit läuft – z. B.
# wenn das Ziel der einzige Erbe war); HostTable.announce_after_settle wartet zusätzlich auf deren Ende.
func _poll_note(now: int) -> void:
	var ht := source as HostTable
	if _note_lt.is_empty() or ht == null or ht.session == null:
		_note_lt = []
		return
	if now < _note_until:
		for t in _note_wait:
			var id := ht._id_of_token(str(t))
			if id >= 0 and not bool(ht.session.player(id).get("connected", false)):
				return
	var lt := _note_lt
	_note_lt = []
	_note_wait = []
	ht.announce_after_settle(lt)


func _take_failed(gone: bool) -> void:
	if _new != null and is_instance_valid(_new) and _new is HostTable:
		_drop_host(_new as HostTable)
	_new = null
	_note_lt = []
	_take_lan = false
	_take_ap = false
	_take_room = {}
	_new_room = ""
	var ct := _guest()
	if gone:
		last_error = "Der Online-Raum ist abgelaufen. Die Partie lässt sich nicht mehr fortsetzen."
	if ct != null:
		ct.resume_guest()                    # Datei wie vor dem Versuch (die gen der Übernahme gilt nicht)
	_reset_watch()
	var now := now_wall()
	_armed_at = now
	if _back_state == "resuming":
		_check = "join"
		_probe_at = now
		_probe_welcomes = ct.client.welcomes if ct != null and ct.client != null else 0
	elif _back_state == "joining":
		_join_until = now + join_wait_ms
	if gone:
		_go("expired" if _flow_ct != null or source == null else "gone")
	else:
		_go(_back_state)


func _drop_host(ht: HostTable) -> void:
	ht.autosave = false
	ht.handover_shutdown()                   # Sitzung ohne bye und ohne end schließen
	if ht.get_parent() == self:
		remove_child(ht)
	ht.free()


# --- geplante Übergabe (Ziel) ---

# Signal des Gast-Tisches (mitten in der Verarbeitung einer Nachricht): erst in pump() ausführen, dort darf der Tisch die Verbindung
# abbauen.
func _on_handover(m: Dictionary) -> void:
	_pending_ho = m


func _handle_handover(m: Dictionary) -> void:
	var ct := _guest()
	var raw_how := _ho_how
	_ho_how = ""
	if ct == null or ct.client == null or state == "taking":
		return
	var want := [int(m.gen), str(m.epoch), int(m.seq)]
	var d := {}
	if m.has("z"):
		d = MatchSnapshot.unpack(str(m.z))
		var gid := ct.game_gid()
		if d.is_empty() or str(d.gid) != str(m.gid) or (gid != "" and gid != str(m.gid)) or NetProtocol.compare_marks(MatchSnapshot.mark(d), want) != 0:
			ct.decline_handover()
			return
	else:
		d = ct.backup                        # own:true: eigene Sicherung genau dieser Marke (Abstammung, 4.3.5)
		if d.is_empty() or str(d.get("gid", "")) != str(m.gid) or NetProtocol.compare_marks(MatchSnapshot.mark(d), want) != 0:
			ct.decline_handover()
			return
	var seat := ClientTable._seat_of_token(d, ct.client.token)
	if seat < 0:
		ct.decline_handover()
		return
	if m.has("z"):
		ct.adopt_backup(d, seat)             # eigene Datei: vollständiger Stand vom Gastgeber
		d = ct.backup
	elif int(m.get("host_gen", 0)) >= int(d.get("gen", 0)):
		# own:true aus der Einschwing-Regel (gleiche Vorgeneration, höheres seq): Der Absender hat schon eine höhere gen. Dieser Zweig
		# führt mit host_gen + 1 weiter (parent = eigene Marke, neue epoch), sonst holte der Absender das Spiel gleich zurück.
		d = d.duplicate(true)
		d["parent"] = MatchSnapshot.mark(d)
		d["gen"] = int(m.host_gen) + 1
		d["epoch"] = NetProtocol.new_epoch()
	# Beta 1.6.2 (10.7): Art der Übergabe – lan, qr oder online (ältere Gastgeber ohne how: nach der eigenen Verbindung)
	var how := str(m.get("how", raw_how))
	if not how in NetProtocol.MOVE_HOWS:
		how = "online" if ct.client.is_online() else "lan"
	_back_state = state if state in ["joining", "resuming"] else "watch"
	_end_probe()
	_end_room_probe()
	_stop_search()
	_take_lan = how != "online"
	_take_ap = how == "qr"
	_take_over(d.duplicate(true), seat, int(m.within_ms), [I18n.part("%s ist jetzt Gastgeber.", [_seat_name(d, seat)])], how)


# --- Gastgeber: vorsichtiges Neuverbinden und Abtreten ---

func _on_online_check(info: Dictionary) -> void:
	if state == "probe" or not source is HostTable:
		return
	_probe_info = info
	_start_host_probe()


func _start_host_probe() -> void:
	var ht := source as HostTable
	_end_probe()
	_probe = NetClient.new()
	_probe.name = "Probe"
	_probe.auto_poll = false
	_probe.clock = now_wall
	add_child(_probe)
	_probe_retry_at = -1
	_go("probe")
	_probe.connect_probe(str(_probe_info.get("relay", "")), str(_probe_info.get("room", "")), ht.seat_name(ht.host_seat), ht.host_token(), probe_ms)


func _poll_probe(now: int) -> void:
	var ht := source as HostTable
	if ht == null or ht.session == null or ht.session.relay == null or ht.session.online_state() != "check":
		_end_probe()
		_go("host")
		return
	if _probe == null:
		if _probe_retry_at >= 0 and now >= _probe_retry_at:
			_start_host_probe()
		return
	_probe.poll()
	var r := _probe.probe_result
	if r == "":
		return
	var who := _probe.host_name
	_end_probe()
	if r == "unreachable":
		_probe_retry_at = now + probe_ms     # Vermittler gerade nicht erreichbar: nie blind anmelden
		return
	_go("host")
	ht.probe_done(r == "answered", who if r == "answered" else "")


func _end_probe() -> void:
	if _probe == null:
		return
	var p := _probe
	_probe = null
	p.close()
	if p.get_parent() == self:
		remove_child(p)
	p.free()


# Abtreten (4.5): HostTable ohne bye/end abbauen, als Gast mit dem eigenen Platz-Token und hello.bk der eigenen Datei zurück.
# Beta 1.6.2 (10.7 Schritt 4, 10.11): wohin, sagt HostTable.step_target – lan: Server des neuen Gastgebers; online: Raum; qr: eigenes
# Spiel-WLAN zu, Gast-Tisch ohne Verbindung im Zustand scan (neuen QR-Code scannen, die Suche läuft).
func _on_stepped_down(new_host: String) -> void:
	var ht := source as HostTable
	if ht == null:
		return
	_end_probe()
	_room_retry = {}
	var st: Variant = ht.get("step_target")
	var target: Dictionary = (st as Dictionary).duplicate() if st is Dictionary else {}
	var data := ht.handover_shutdown()
	ht.autosave = false                      # die Datei gehört jetzt dem Gast-Tisch (gleicher Pfad)
	var d := MatchSnapshot.clean(data)
	if d.is_empty():
		_go("off")
		return
	var o: Dictionary = d.online
	var how := str(target.get("how", ""))
	if how == "lan" and (NetProtocol.ipv4_to_int(str(target.get("addr", ""))) <= 0 or int(target.get("port", 0)) <= 0):
		how = ""
	if how == "online" and (str(target.get("room", "")) == "" or str(target.get("relay", "")) == ""):
		target["room"] = str(o.get("room", ""))
		target["relay"] = str(o.get("relay", ""))
	if how == "":
		how = "online" if not o.is_empty() else ""
		target["room"] = str(o.get("room", ""))
		target["relay"] = str(o.get("relay", ""))
	if how == "" or (how == "online" and str(target.room) == ""):
		_go("off")                           # WLAN ohne Ziel: nichts, wohin es weitergeht
		return
	var seat := int(d.my_seat) if int(d.my_seat) >= 0 else int(d.host_seat)
	if new_host == "":
		new_host = str(target.get("name", ""))
	var ct := _make_client()
	add_child(ct)
	_flow_ct = ct
	ct.handover_received.connect(_on_handover)
	match how:
		"lan":
			ct.join(str(target.addr), int(target.port), _seat_name(d, seat), MatchSnapshot.seat_token(d, seat))
		"online":
			ct.join(NetProtocol.room_link(str(target.relay), str(target.room)), 0, _seat_name(d, seat), MatchSnapshot.seat_token(d, seat))
		"qr":
			_stop_own_wifi()                 # das eigene Spiel-WLAN geht zu (move ist schon geleert hinaus)
	ct.adopt_backup(d, seat)
	_join_name = new_host
	if how == "qr":
		# Kein Netz zu den anderen mehr: gleich als Gast im Zustand scan (neuen QR-Code scannen; die Suche findet den neuen Gastgeber)
		_scan_next = new_host if new_host != "" else "?"
		_finish_guest(I18n.t("Du spielst jetzt als Gast weiter. Gastgeber ist %s.") % _scan_next)
		return
	_join_until = now_wall() + join_wait_ms
	_go("joining")


func _poll_joining(now: int) -> void:
	var ct := _flow_ct
	if ct == null:
		_go("off")
		return
	_pump_node(ct)
	var c := ct.client
	if c != null and c.welcomes > 0:
		_finish_guest(I18n.t("Du spielst jetzt als Gast weiter. Gastgeber ist %s.") % ct.host_name())
	elif now >= _join_until or c == null or ct.connection_state() in ["closed", "rejected", "ended"]:
		_finish_guest(I18n.t("Du spielst jetzt als Gast weiter. Gastgeber ist %s.") % (_join_name if _join_name != "" else "?"))


func _finish_guest(note: String) -> void:
	var ct := _flow_ct
	_flow_ct = null
	_saved = {}
	remove_child(ct)
	_move_to(ct)
	swapped.emit(ct, note)


# --- Hauptmenü „Partie fortsetzen“ ---

func _poll_resume(now: int) -> void:
	if _check == "search":
		_poll_menu_search(now)
		return
	var ct := _flow_ct
	if ct == null:
		if state != "confirm":
			_go("off")
		return
	_pump_node(ct)
	var c := ct.client
	if c != null and c.welcomes > _probe_welcomes and c.state == "open":
		# Ein Gastgeber antwortet: als Gast weiter (ein jüngerer Zweig auf diesem Gerät kommt über hello.bk zurück)
		var note := I18n.t("%s führt das Spiel inzwischen. Du spielst als Gast weiter.") % ct.host_name() if str(_saved.role) == "host" else ""
		_finish_guest(note)
		return
	var lan := c != null and not c.is_online()
	if c == null or ct.connection_state() in ["closed", "rejected", "ended"] or (lan and _check == "join" and now - _probe_at >= probe_ms):
		_free_flow_ct()
		if lan:
			_decide_wlan()                   # Beta 1.6.2: gefunden, aber keine Antwort – wie „niemand führt“
			return
		last_error = "Der Online-Raum ist abgelaufen. Die Partie lässt sich nicht mehr fortsetzen."
		_go("expired")
		return
	if state == "confirm" or lan:
		return
	match _check:
		"join":
			if c.away_code_wall >= _probe_at or now - _probe_at >= probe_ms:
				_check = "info"
				c.query_info()
		"info":
			if c.info_pending():
				return
			var r := c.info_result
			if not bool(r.get("ok", false)):
				_check = "join"              # Vermittler nicht erreichbar: weiter als Gast versuchen
				_probe_at = now
			elif not bool(r.get("open", true)):
				last_error = "Der Online-Raum ist abgelaufen. Die Partie lässt sich nicht mehr fortsetzen."
				_free_flow_ct()
				_go("expired")
			elif not bool(r.get("host", true)):
				_decide()
			else:
				_check = "fresh"
				_start_probe(c, now)
		"fresh":
			if c.away_code_wall >= _probe_at:
				_decide()
			elif now - _probe_at >= probe_ms:
				if c.reached:
					_decide()
				else:
					_check = "join"
					_probe_at = now


# Beta 1.6.2 (10.14): WLAN-Datei – menu_search_ms nach der gid suchen. Fund mit gen ≥ Datei → als Gast dorthin (welcome → swapped).
func _poll_menu_search(now: int) -> void:
	var e := _found(_saved)
	if not e.is_empty():
		_stop_search()
		var mine := int(_saved.host_seat) if str(_saved.role) == "host" else int(_saved.my_seat)
		var ct := _make_client()
		add_child(ct)
		_flow_ct = ct
		ct.handover_received.connect(_on_handover)
		ct.join(str(e.address), int(e.port), str(_saved.seats[mine].name), MatchSnapshot.seat_token(_saved, mine))
		ct.use_backup(_saved)
		_check = "join"
		_probe_at = now
		_probe_welcomes = 0
		return
	if now - _probe_at >= menu_search_ms:
		_stop_search()
		_decide_wlan()


func _decide() -> void:
	var age := MatchSnapshot.age_s(_saved, now_wall() / 1000)
	if str(_saved.role) == "host" and age < NetProtocol.RESUME_QUIET_MIN * 60:
		_resume_from_saved()                 # eigene Partie, eben erst gespeichert: ohne Rückfrage (eigener Zweig, gen bleibt)
		return
	_check = "decided"
	_go("confirm")
	confirm_needed.emit({"role": str(_saved.role), "age_min": maxi(age, 0) / 60,
		"warnings": _warnings(_saved, str(_saved.role) == "host"), "ap": false})


# Beta 1.6.2 (10.14, 10.8): WLAN-Datei, niemand führt die Partie. Eigene Gastgeber-Datei → sofort fortsetzen (Port wie 1.6.1), mit
# Spiel-WLAN aber Rückfrage (er sieht nicht, ob jemand übernommen hat): ap:true – „Spiel-WLAN neu öffnen“ (confirm_resume(true)) oder
# „Beim neuen Gastgeber scannen“ (cancel(), Oberfläche: JoinScreen). Gast-Datei → Rückfrage „Spiel als Gastgeber fortsetzen?“.
func _decide_wlan() -> void:
	var age := MatchSnapshot.age_s(_saved, now_wall() / 1000)
	var host := str(_saved.role) == "host"
	if host and not _is_ap(_saved):
		_resume_from_saved()
		return
	_check = "decided"
	_go("confirm")
	confirm_needed.emit({"role": str(_saved.role), "age_min": maxi(age, 0) / 60, "warnings": _warnings(_saved, host),
		"ap": host and _is_ap(_saved)})


func _resume_from_saved() -> void:
	var guest := str(_saved.role) == "guest"
	var seat := int(_saved.my_seat) if guest else -1
	var wlan := (_saved.online as Dictionary).is_empty()
	_back_state = "expired" if wlan else "resuming"
	_take_lan = wlan
	_take_ap = wlan and _is_ap(_saved)       # Spiel-WLAN: eigenes neu öffnen (10.8)
	# Gegenprüfung 1.6.2: Scheitert das Eröffnen einer WLAN-Partie (Ports belegt), landet sie in expired – mit eigener Meldung statt
	# „Der Online-Raum ist abgelaufen …“
	if wlan:
		last_error = "Das Spiel ließ sich gerade nicht eröffnen. Bitte noch einmal versuchen."
	_take_over(_saved, seat, takeover_within_ms,
		[I18n.part("%s führt das Spiel weiter (Gastgeber war weg).", [_seat_name(_saved, seat)])] if guest else [])
	if wlan and state != "expired":
		last_error = ""


func _free_flow_ct() -> void:
	var ct := _flow_ct
	_flow_ct = null
	if ct == null or not is_instance_valid(ct):
		return
	if not ct.is_retired():
		ct.suspend()                         # ohne bye, Datei bleibt
	if ct.get_parent() == self:
		remove_child(ct)
	ct.free()


# Stand für resume_new_room: im Hauptmenü die Datei (expired), am Tisch die Sicherung (gone).
func _new_room_data() -> Dictionary:
	if state == "expired" and not _saved.is_empty():
		return _saved
	var ct := _watched()
	if state == "gone" and ct != null and not ct.backup.is_empty() and ct.backup_seat() >= 0 and not ct.is_retired():
		return ct.backup
	return {}


# --- Hilfen ---

func _detach() -> void:
	_stop_search()
	_end_room_probe()
	if source == null or not is_instance_valid(source):
		source = null
		return
	if source is HostTable:
		var ht := source as HostTable
		if ht.stepped_down.is_connected(_on_stepped_down):
			ht.stepped_down.disconnect(_on_stepped_down)
		if ht.online_check.is_connected(_on_online_check):
			ht.online_check.disconnect(_on_online_check)
	elif source is ClientTable:
		var ct := source as ClientTable
		if ct.handover_received.is_connected(_on_handover):
			ct.handover_received.disconnect(_on_handover)
		if ct.moved.is_connected(_on_moved):
			ct.moved.disconnect(_on_moved)
		if ct.host_message.is_connected(_on_host_message):
			ct.host_message.disconnect(_on_host_message)
	source = null


# Mit der neuen Quelle umziehen: HostSwitch wird ihr Kind und überwacht sie.
func _move_to(src: TableSource) -> void:
	var p := get_parent()
	if p != null:
		p.remove_child(self)
	src.add_child(self)
	attach(src)


func _make_host() -> HostTable:
	var ht: HostTable = host_factory.call() if host_factory.is_valid() else GameStarter.host()
	ht.save_path = save_path
	if host_setup.is_valid():
		host_setup.call(ht)
	return ht


func _make_client() -> ClientTable:
	var ct: ClientTable = client_factory.call() if client_factory.is_valid() else GameStarter.client()
	ct.backup_path = save_path
	ct.clock = now_wall
	ct.listen_port = port_first
	if client_setup.is_valid():
		client_setup.call(ct)
	return ct


# Kinder im Aufbau abfragen, solange sie es nicht selbst tun (nicht im Baum bzw. auto_process aus).
func _pump_node(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	if n is GameTable and (not n.is_inside_tree() or not (n as GameTable).auto_process):
		(n as GameTable).pump()
	elif n is ClientTable and (not n.is_inside_tree() or not (n as ClientTable).auto_process):
		(n as ClientTable).pump()


static func _seat_name(d: Dictionary, seat: int) -> String:
	var seats: Array = d.get("seats", []) if d.get("seats") is Array else []
	if seat < 0:
		seat = int(d.get("host_seat", -1))
	return str((seats[seat] as Dictionary).get("name", "?")) if seat >= 0 and seat < seats.size() else "?"


func _go(s: String) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(s)
