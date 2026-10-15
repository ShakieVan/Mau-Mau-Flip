class_name ClientTable
extends TableSource
# Netzwerkspiel, App-Mitspieler (Modul G): NetClient (Modul D) zur Adresse des Gastgebers. Meldet sich mit Name, kind "app" und –
# falls bekannt – Token an; verbindet bei Verlust selbst neu (als derselbe Spieler). Der Gastgeber entscheidet alles, hier kommen
# nur die eigene Sicht und die für diesen Platz gefilterten Ereignisse an.
#   lobby → lobby_changed (waiting:true = Warteliste mitten in der Partie, Feld waiting) · start → game_started
#   state → state_changed · err/notice → notice
#   reject → connection_changed("rejected") + notice (bei falscher Version mit Hinweis auf /apk) · bye → notice + "closed"
# act() schickt {t:"act", seq, a}.
# Mau-Mau Flip (Beta 1.6.1, Gastgeber-Übergabe, docs/module/uebergabe.md Abschnitte 2, 3.5, 4.1, 4.3):
#  - Sicherung: hello.bk = Marke der eigenen Sicherung (BK_NONE ohne), bk_token = Token des eigenen Platzes daraus – nur wenn die Datei
#    zu diesem Online-Raum gehört. {t:"bk"} wird entpackt und als eigene Datei (backup_path, role "guest", my_seat aus dem eigenen
#    Token) geschrieben – nur bei gleicher gid wie der Gastgeber (welcome) und gen ≥ gen der vorhandenen Sicherung derselben Partie.
#    head = Marke des letzten bk/alive („aktuell“, wenn sie der Sicherung entspricht).
#  - Datei löschen: eigenes Verlassen, bye, herausgenommen, lobby ohne waiting (die Partie dieser Sicherung ist vorbei), start mit
#    anderer gid. Nach einer Übernahme (retire) fasst dieser Tisch die Datei nie mehr an – sie gehört dann dem Gastgeber-Tisch.
#  - {t:"handover"} geht geprüft an HostSwitch (handover_received); ohne Sicherungen (backups aus) antwortet der Tisch mit handover_no.
#  - suspend() trennt ohne „bye“ und ohne Datei zu löschen (Übernahme läuft), resume_guest() meldet sich wieder an.
# Mau-Mau Flip (Beta 1.6.2, WLAN und Spiel-WLAN, docs/module/uebergabe.md Abschnitte 10.5–10.7):
#  - Sicherung beim Beitritt an jeder Adresse und in jedem Raum, wenn MatchSnapshot.resumable(…, true); hello trägt dazu bk_gid, hp
#    (listen_port) und ap (ap_info, von app/ eingespritzt).
#  - move_to(addr, port) / follow_room(relay, room): zum neuen Gastgeber umziehen – Socket ohne „bye“ zu, join mit dem eigenen
#    Platz-Token; Sicherung, head/head_gid und Token bleiben. Signal moved (HostSwitch: zurück nach watch mit frischen Zählern).
#  - send_and_drain(msg): senden und den Sendepuffer leeren (handover_ok vor suspend()).
# Mau-Mau Flip (Beta 1.6.3, Easter Eggs Teil 2 „Necken“, docs/module/eastereggs2.md Abschnitte 4 und 6.1):
#  - send_fx(req) → {t:"fx"}; set_fx_off(off) → {t:"fx_pref"} (auch nach jedem welcome). fx → fx_event (nur mit Platz und Sicht),
#    fx_no → fx_refused, fx_offs → fx_offs_changed. Sichten und Ereignisse füttern den Spiegel tease (fx_check der Oberfläche).
#  - Beta 1.6.6 (Furzkissen): fx kissen (nur als Leger: Bestätigung, Spiegel sperrt die Mindestzeit) und kissen_pop (alle) → fx_event;
#    fx_no mit k:"kissen" setzt fx_refused_kind.

signal backup_changed                              # Beta 1.6.1: neue Sicherung (bk) liegt in backup
signal handover_received(msg: Dictionary)          # Beta 1.6.1: geprüftes {t:"handover"} (z oder own:true) → HostSwitch
signal host_message(msg: Dictionary)               # Beta 1.6.1: jede Nachricht des Gastgebers nach dem welcome (Tests, Protokoll)
signal moved(host_address: String, host_port: int) # Beta 1.6.2: move_to/follow_room – neuer NetClient zur neuen Adresse

var client: NetClient
var auto_process := true
var reuse_token := true          # Token je Gastgeber-Adresse wiederverwenden (Tests mit mehreren Clients: false)
var persist_tokens := true
var retry_ms: Array = []         # Tests: kürzere Abstände beim Neuverbinden
var ping_ms := 0
var host_away_ms := -1           # Tests: Wartezeit nach 4503 (−1 = Standard)
var lobby := {}
var my_id := 0
var token := ""
var view_rev := 0                # Anzahl empfangener Stände
var last_rev := -1               # rev des Gastgebers im letzten Stand
var address := ""
var port := 0
var waiting := false              # Beta 1.4.2: mitten in der Partie auf der Warteliste ({t:"lobby", waiting:true}), bis „start“ kommt
# --- Gastgeber-Übergabe (Beta 1.6.1) ---
var backups := true               # App hält Sicherungen (hello.bk); false = Gast ohne Sicherung (Tests: wie eine App ohne bk)
var backup_path := NET_SAVE_PATH
var persist_backup := true        # Sicherung als Datei lesen und schreiben (siehe _files)
var backup := {}                  # MatchSnapshot dieser Partie (role "guest" mit my_seat, oder die eigene Gastgeber-Datei); {} = keine
var head: Array = []              # Marke [gen, epoch, seq] des letzten bk/alive vom Gastgeber
var head_gid := ""
var clock := Callable()           # Tests: () -> Wanduhr in ms (an NetClient weitergereicht)
# --- WLAN und Spiel-WLAN (Beta 1.6.2) ---
var listen_port := NetProtocol.PORT   # hello.hp: Port, auf dem dieses Gerät als Gastgeber lauschen würde (HostSwitch.port_first)
var ap_info := Callable()             # () -> {ok, perm} für hello.ap (ungültig: NetClient.ap_info_default aus app/)

var _seat := -1
var _view := {}
var _seq := 0
var _rejected := false
var _leaving := false
var _ended := false               # Spiel beendet: Gastgeber nach dem Spielende nicht mehr erreichbar (N6)
var _retired := false             # Beta 1.6.1: dieses Gerät führt das Spiel jetzt (Datei gehört dem Gastgeber-Tisch)
var _game_gid := ""               # Beta 1.6.1: gid der Partie, in der dieser Tisch zuletzt saß (aus welcome)
var _name := ""

# Nach dem Ende einer Runde bzw. der Partie gibt der Gast das Neuverbinden auf, wenn der Gastgeber so oft nicht erreichbar war
# (N6: App im Hintergrund, der Gastgeber ist inzwischen ins Menü gegangen). Mitten in der Partie wird weiter versucht.
const GIVE_UP := {"game_over": 1, "round_end": 3}


# Beitreten. with_token: als bekannter Spieler zurückkommen (sonst Token aus dem Speicher des NetClient).
func join(host_address: String, host_port := NetProtocol.PORT, player_name := "", with_token := "") -> Error:
	_drop_client()
	address = host_address
	port = host_port
	_rejected = false
	_leaving = false
	_ended = false
	_retired = false
	_name = player_name if player_name != "" else _own_name()
	client = NetClient.new()
	client.name = "NetClient"
	client.auto_poll = false
	client.reuse_token = reuse_token
	client.persist_tokens = persist_tokens
	client.clock = clock
	if not retry_ms.is_empty():
		client.retry_ms = retry_ms.duplicate()
	if ping_ms > 0:
		client.ping_ms = ping_ms
	if host_away_ms >= 0:
		client.host_away_ms = host_away_ms
	client.listen_port = listen_port
	client.ap_info = ap_info
	add_child(client)
	_connect_client()
	head = []
	head_gid = ""
	if backups:
		_load_backup(host_address)
	var err := client.connect_to(host_address, host_port, _name, "app")
	if with_token != "":
		client.token = with_token      # die Begrüßung entsteht erst in poll(), sobald der Socket offen ist
	_offer_backup()
	return err


func mode() -> String:
	return "client"


func local_seat() -> int:
	return _seat


func current_view() -> Dictionary:
	return _view


func connection_state() -> String:
	return "ended" if _ended else ("rejected" if _rejected else (client.state if client != null else "closed"))


# Hinweis beim Neuverbinden (Beta 1.3.3): „Gastgeber kurz weg – warte …“ (4503) bzw. „Verbindung zum Gastgeber unterbrochen – warte …“
func connection_hint() -> String:
	return _hint_text()


# Vom Gastgeber herausgenommen (bye oder Ablehnung beim Wiederverbinden mit altem Token, Gerätetest 1.4.2)
func was_removed() -> bool:
	return client != null and client.removed


func _hint_text() -> String:
	# Gerätetest 1.6.2 (B2): Im WLAN gibt es kein 4503; dort sagt der letzte Stand, dass der Gastgeber kurz in einer anderen App ist
	# (away am Platz). Dann wie online „Gastgeber kurz weg – warte …“ statt „Verbindung … unterbrochen“.
	if host_away():
		return "Gastgeber kurz weg – warte …"
	return client.hint() if client != null else "Verbindung zum Gastgeber unterbrochen – warte …"


func act(action: Dictionary) -> void:
	if client == null or client.state != "open":
		notice.emit("Keine Verbindung zum Gastgeber – einen Moment …")
		return
	_seq += 1
	if client.send({"t": "act", "seq": _seq, "a": action}) != OK:
		notice.emit("Senden fehlgeschlagen – die Verbindung wird erneuert.")


# Mau-Mau Flip (Beta 1.6.3, Necken): Wunsch an den Gastgeber; das Ergebnis kommt als fx (fx_event, auch für den Absender) oder fx_no.
func send_fx(req: Dictionary) -> void:
	var m := NetProtocol.make_fx_request(req)
	if m.is_empty() or client == null or client.state != "open":
		return
	client.send(m)


# Beta 1.6.3: Einstellung „necken“ – geht sofort (und nach jedem welcome) als fx_pref an den Gastgeber.
func set_fx_off(off: bool) -> void:
	var changed := off != _fx_off_self
	_fx_off_self = off
	if changed:
		_send_fx_pref()


func _send_fx_pref() -> void:
	if client != null and client.state == "open":
		client.send({"t": "fx_pref", "off": _fx_off_self})


# Bereit-Meldung in der Lobby.
func set_ready(ready: bool) -> void:
	if client != null and client.state == "open":
		client.send({"t": "lobby_ready", "ready": ready})


func leave() -> void:
	_leaving = true
	QrJoin.client_left(self)   # Beta 1.4.3: Spiel-WLAN aus dem QR-Code freigeben (Handy kommt wieder normal ins Internet)
	_drop_client()
	_clear_backup()            # Beta 1.6.1: eigenes Verlassen – die Sicherung wird nicht mehr gebraucht


func _process(_delta: float) -> void:
	if auto_process:
		pump()


func pump() -> void:
	if client != null:
		client.poll()
		_check_give_up()
	QrJoin.check_lost(self)   # Beta 1.4.3: Spiel-WLAN aus dem QR-Code weg → freigeben (Handy kommt wieder ins normale WLAN)


# --- Gastgeber-Übergabe (Beta 1.6.1) ---

# gid der Partie des Gastgebers (aus dem letzten welcome; "" = Lobby oder älterer Gastgeber).
func host_gid() -> String:
	return str(client.welcome_info.get("gid", "")) if client != null else ""


# gid der laufenden Partie: aus dem welcome bzw. (angemeldet in der Lobby) aus dem ersten bk/alive; "" = unbekannt.
func game_gid() -> String:
	return host_gid() if host_gid() != "" else _game_gid


# Eigener Platz in der Sicherung (aus dem eigenen Token); −1 = keiner (Warteliste, Computer, keine Sicherung).
func backup_seat() -> int:
	if backup.is_empty():
		return -1
	var t := client.token if client != null and client.token != "" else MatchSnapshot.own_token(backup)
	return _seat_of_token(backup, t)


# Entspricht die Sicherung dem letzten bk/alive des Gastgebers? (Abschnitt 4.2: nur dann automatische Übernahme)
func backup_current() -> bool:
	return not backup.is_empty() and not head.is_empty() and head_gid == str(backup.get("gid", "")) \
		and NetProtocol.compare_marks(head, MatchSnapshot.mark(backup)) == 0


# Stand übernehmen (geplante Übergabe mit z, Abtreten des alten Gastgebers, Fortsetzen aus dem Hauptmenü): als Sicherung merken,
# Datei schreiben (role "guest", my_seat aus dem eigenen Token) und künftig im hello melden.
func adopt_backup(data: Dictionary, seat := -2) -> void:
	var d := MatchSnapshot.clean(data)
	if d.is_empty() or _retired:
		return
	if seat == -2:
		seat = _seat_of_token(d, client.token if client != null and client.token != "" else MatchSnapshot.own_token(d))
	d["role"] = "guest"
	d["my_seat"] = seat
	backup = d
	if _files():
		MatchSnapshot.write(backup_path, d)
	_offer_backup()


# Sicherung nur im Speicher übernehmen (Hauptmenü: die eigene Datei bleibt, wie sie ist) – für hello.bk und eine spätere Übernahme.
func use_backup(data: Dictionary) -> void:
	var d := MatchSnapshot.clean(data)
	if d.is_empty() or _retired:
		return
	backup = d
	_offer_backup()


# Gast-Socket ohne „bye“ schließen, Sicherung und Datei bleiben (Übernahme läuft, HostSwitch). resume_guest() meldet sich wieder an.
func suspend() -> void:
	_leaving = true
	_drop_client()


# Nach einer abgebrochenen Übernahme wieder als Gast anmelden (gleiche Adresse, gleiches Token, Sicherung aus dem Speicher).
func resume_guest() -> Error:
	var keep := backup
	var tok := token if token != "" else MatchSnapshot.own_token(keep)
	var err := join(address, port, _name, tok)
	if not keep.is_empty():
		backup = keep
		if _files():
			MatchSnapshot.write(backup_path, keep)    # die Übernahme hatte die Datei schon als Gastgeber (gen + 1) geschrieben
		_offer_backup()
	return err


# Beta 1.6.2 (Abschnitt 10.5): zum neuen Gastgeber umziehen (Suche, move, Wächter). Der Gast-Socket schließt ohne „bye“, dann join an
# die neue Adresse mit dem eigenen Platz-Token (Tokens liegen im NetClient je ip:port, deshalb ausdrücklich). Sicherung, head/head_gid
# und Token bleiben – backup_current() gilt weiter bis zum nächsten bk. Signal moved: Der neue NetClient zählt von vorn (welcomes,
# last_host_wall), der HostSwitch setzt darauf seine Zähler zurück.
func move_to(host_address: String, host_port := NetProtocol.PORT) -> Error:
	var keep := backup
	var keep_head := head.duplicate()
	var keep_gid := head_gid
	var tok := own_seat_token()
	var err := join(host_address, host_port, _name, tok)
	if not keep.is_empty():
		backup = keep
	if not keep_head.is_empty():
		head = keep_head
		head_gid = keep_gid
	_offer_backup()
	moved.emit(address, port)
	return err


# Beta 1.6.2: dasselbe über den Raum-Link (WLAN-Gast folgt einem Online-Gastgeber, Abschnitte 10.4, 10.12).
func follow_room(relay: String, room_code: String) -> Error:
	return move_to(NetProtocol.room_link(relay, room_code), 0)


# Token des eigenen Platzes: aktuelle Anmeldung, sonst letztes welcome, sonst aus der Sicherung.
func own_seat_token() -> String:
	if client != null and client.token != "":
		return client.token
	if token != "":
		return token
	return MatchSnapshot.own_token(backup) if not backup.is_empty() else ""


# Beta 1.6.2 (Abschnitt 10.7): senden und den Sendepuffer leeren, bevor suspend() den NetClient freigibt (handover_ok). true = hinaus.
func send_and_drain(msg: Dictionary, max_ms := 300) -> bool:
	if client == null or client.send(msg) != OK:
		return false
	return client.drain(max_ms)


# Dieses Gerät führt das Spiel jetzt: Verbindung zu, Datei nie mehr anfassen (sie gehört dem Gastgeber-Tisch, gleicher Pfad).
func retire() -> void:
	_retired = true
	_leaving = true
	_drop_client()


func is_retired() -> bool:
	return _retired


# handover own:true ablehnen (Sicherung passt nicht mehr, Abschnitt 4.3.5) bzw. handover mit fremder Partie.
func decline_handover() -> void:
	if client != null and client.state == "open":
		client.send({"t": "handover_no"})


# Spieler-Name dieses Geräts (Anmeldung)
func player_name() -> String:
	return _name


# Spielend am Tisch? Nur in den Spielphasen und am Rundenende ist der Wächter scharf.
func phase() -> String:
	return str(_view.get("phase", ""))


# Gastgeber laut letztem Stand gerade in einer anderen App?
func host_away() -> bool:
	for p in _view.get("players", []):
		if p is Dictionary and bool(p.get("host", false)):
			return bool(p.get("away", false))
	return false


# Spieler-Name des Gastgebers laut welcome
func host_name() -> String:
	return client.host_name if client != null else ""


func _load_backup(_host_address: String) -> void:
	# Sicherung aus der Datei. Beta 1.6.2 (Abschnitt 10.6): an jeder Adresse und in jedem Raum, wenn sie fortsetzbar ist (Raumalter
	# zählt nicht) – App-Gäste landen so über jeden Weg (Suche, QR im neuen Spiel-WLAN, neuer Raumcode) per bk_token auf ihrem Platz.
	# Der Gastgeber nimmt bk_token nur bei passender bk_gid.
	backup = {}
	if not _files():
		return
	var d := MatchSnapshot.read(backup_path)
	if d.is_empty() or str(d.gid) == "":
		return
	var now := int(clock.call()) / 1000 if clock.is_valid() else int(Time.get_unix_time_from_system())
	if not MatchSnapshot.resumable(d, now, true):
		return
	backup = d


# Datei benutzen? Nicht, wenn auch die Token nur im Speicher liegen (persist_tokens aus) und der gemeinsame Standardpfad gilt: Tests
# mit mehreren Gästen in einem Prozess teilten sich sonst eine Datei (und damit über bk_token einen Platz).
func _files() -> bool:
	return persist_backup and (persist_tokens or backup_path != NET_SAVE_PATH)


func _offer_backup() -> void:
	if client == null:
		return
	if not backups:
		client.bk = []
		client.bk_token = ""
		client.bk_gid = ""
		return
	client.bk = MatchSnapshot.mark(backup) if not backup.is_empty() else NetProtocol.BK_NONE.duplicate()
	client.bk_token = MatchSnapshot.own_token(backup) if not backup.is_empty() else ""
	client.bk_gid = str(backup.get("gid", "")) if not backup.is_empty() else ""   # Beta 1.6.2


func _clear_backup() -> void:
	backup = {}
	head = []
	head_gid = ""
	if _files() and not _retired:
		clear_saved(backup_path)
	_offer_backup()


func _on_bk(msg: Dictionary) -> void:
	var m := NetProtocol.clean_backup_message(msg)
	if m.is_empty() or _retired:
		return
	head = [int(m.gen), str(m.epoch), int(m.seq)]
	head_gid = str(m.gid)
	if host_gid() == "" or host_gid() == head_gid:
		_game_gid = head_gid         # Partie, in der dieser Tisch sitzt (auch wenn das welcome aus der Lobby keine gid trug)
	if not backups or str(m.t) != "bk":
		return
	var gid := str(m.gid)
	if host_gid() != "" and gid != host_gid():
		return
	if not backup.is_empty() and str(backup.gid) == gid and int(m.gen) < int(backup.gen):
		return       # wir halten einen jüngeren Zweig derselben Partie (Abstammung, Abschnitt 4.3.5)
	var d := MatchSnapshot.unpack(str(m.z))
	if d.is_empty() or str(d.gid) != gid or NetProtocol.compare_marks(MatchSnapshot.mark(d), head) != 0:
		return
	d["role"] = "guest"
	d["my_seat"] = _seat_of_token(d, client.token)
	backup = d
	if _files():
		MatchSnapshot.write(backup_path, d)
	_offer_backup()
	backup_changed.emit()


static func _seat_of_token(d: Dictionary, t: String) -> int:
	if t == "" or not d.get("seats") is Array:
		return -1
	var seats: Array = d.seats
	for s in seats.size():
		if seats[s] is Dictionary and str((seats[s] as Dictionary).get("token", "")) == t:
			return s
	return -1


# Spielende und Gastgeber weg: nicht endlos „Verbinde neu …“, sondern „Spiel beendet“ (connection_changed "ended")
func _check_give_up() -> void:
	if client == null or _ended or client.state != "connecting":
		return
	var limit := int(GIVE_UP.get(str(_view.get("phase", "")), 0))
	if limit > 0 and client.attempts > limit:     # so viele Versuche sind gescheitert
		_ended = true
		_drop_client()
		connection_changed.emit("ended")


# --- intern ---

func _connect_client() -> void:
	client.state_changed.connect(_on_state)
	client.welcomed.connect(_on_welcomed)
	client.message.connect(_on_message)
	client.rejected.connect(_on_rejected)
	client.closed.connect(_on_closed)


func _drop_client() -> void:
	if client == null:
		return
	for c in [[client.state_changed, _on_state], [client.welcomed, _on_welcomed], [client.message, _on_message],
			[client.rejected, _on_rejected], [client.closed, _on_closed]]:
		if (c[0] as Signal).is_connected(c[1]):
			(c[0] as Signal).disconnect(c[1])
	client.close("Verlassen.")
	if client.is_inside_tree():
		client.queue_free()
	else:
		client.free()
	client = null


func _on_state(st: String) -> void:
	if st == "closed" and _rejected:
		return
	connection_changed.emit(st)


func _on_welcomed(id: int, _host_name: String) -> void:
	my_id = id
	token = client.token
	if host_gid() != "":
		_game_gid = host_gid()
	# Beta 1.6.3 (Necken): Der Gastgeber kennt nach jeder Anmeldung (auch nach einer Übernahme) nur, was wir ihm jetzt sagen; seine
	# Liste fx_offs kommt danach neu (bis dahin keine).
	tease.reset()
	_clear_fx_offs()
	_send_fx_pref()


# Mau-Mau Flip (Beta 1.6.3, Easter Eggs Teil 2): Liste fx_offs vergessen (nach welcome, in der Lobby, bei einer neuen Partie). Der
# Gastgeber schickt eine leere Liste nie (HostTable._fx_sync_offs), sonst hielte ein Gast die Plätze der vorigen Partie fest.
func _clear_fx_offs() -> void:
	if not _fx_offs.is_empty():
		_fx_offs = []
		fx_offs_changed.emit([])


func _on_message(msg: Dictionary) -> void:
	host_message.emit(msg)
	match str(msg.get("t", "")):
		"lobby":
			# Lobby-Stände verteilt der Gastgeber nur ohne laufende Partie: Ein alter Stand gilt nicht mehr (sonst zeigte ein neuer
			# Tisch kurz die vorige Partie).
			lobby = msg
			waiting = bool(msg.get("waiting", false))
			# Beta 1.6.1: Partie in die Lobby zurückgeholt – die Sicherung dieser Partie ist überholt (nicht die einer anderen)
			if not waiting and not backup.is_empty() and _game_gid != "" and str(backup.gid) == _game_gid:
				_clear_backup()
			_view = {}
			_seat = -1
			tease.reset()                # Beta 1.6.3
			_clear_fx_offs()
			lobby_changed.emit(msg)
		"start":
			_seat = int(msg.get("seat", -1))
			waiting = false
			# Beta 1.6.1: neue Partie (bzw. dazugeholt in eine andere als die gesicherte) – alte Sicherung weg
			if not backup.is_empty() and str(backup.gid) != host_gid():
				_clear_backup()
			_clear_fx_offs()             # Beta 1.6.3: die Liste der neuen Partie kommt danach (leer: gar nicht)
			game_started.emit(_seat)
		"state":
			if not msg.get("view") is Dictionary:
				return
			view_rev += 1
			last_rev = int(msg.get("rev", -1))
			_view = msg.view
			_seat = int(_view.get("seat", _seat))
			var evs: Array = msg.get("events", []) if msg.get("events") is Array else []
			var now := _fx_now()
			tease.note_events(evs, now)  # Beta 1.6.3: Spiegel der Necken-Regeln (Uhr wie die Denkblase, Zugwechsel)
			tease.note_view(_view, now)
			state_changed.emit(evs, _view)
		"fx":
			var m := NetProtocol.clean_fx(msg)   # Beta 1.6.3: Necken (an alle Sitzenden, auch an den Absender)
			# Beta 1.6.6: die Kissen-Bestätigung gilt nur für den eigenen Platz (sie geht nur an den Leger)
			if not m.is_empty() and _seat >= 0 and not _view.is_empty() \
					and (str(m.k) != TeaseRules.CUSHION or int(m.from) == _seat):
				_fx_deliver(m)
		"fx_no":
			var why := NetProtocol.clean_fx_no(msg)   # Beta 1.6.3: eigener Wunsch abgelehnt
			if why != "":
				_fx_refuse(why, NetProtocol.clean_fx_no_kind(msg))   # Beta 1.6.6: fx_refused_kind (Furzkissen)
		"fx_offs":
			var offs := NetProtocol.clean_fx_offs(msg)   # Beta 1.6.3: Plätze mit Necken aus
			if offs != _fx_offs:
				_fx_offs = offs
				fx_offs_changed.emit(offs.duplicate())
		"err", "notice":
			notice.emit(I18n.msg_text(msg, "Das geht gerade nicht."))   # eigene Sprache (I18n: lt oder msgid)
		"bk", "alive":
			_on_bk(msg)                  # Beta 1.6.1: Sicherung bzw. Lebenszeichen
		"handover":
			var m := NetProtocol.clean_backup_message(msg)
			if m.is_empty() or _retired:
				return
			if not backups:
				decline_handover()       # hält keine Sicherung: der Gastgeber taut sofort auf
				return
			handover_received.emit(m)    # HostSwitch (ohne ihn: Gastgeber taut nach seiner Frist auf)


func _on_rejected(code: String, text: String) -> void:
	_rejected = true
	if client != null and client.removed:
		_clear_backup()                # Beta 1.6.1: herausgenommen
	if client != null and client.removed and waiting:
		text = I18n.t("Der Gastgeber hat dich nicht dazugeholt.")   # stand nur auf der Warteliste
	if code == "version" and not text.contains("/apk"):
		text += " " + I18n.t("App vom Gastgeber holen: %s") % ("http://%s:%d/apk" % [address, port])
	connection_changed.emit("rejected")
	notice.emit(text)


func _on_closed(text: String) -> void:
	if client != null and (client.bye_id != "" or client.removed) and not _leaving:
		_clear_backup()                # Beta 1.6.1: „bye“ (Ende bzw. herausgenommen)
	if _rejected or _leaving:
		return
	notice.emit(text)


func _own_name() -> String:
	var loop := Engine.get_main_loop()
	var app: Node = (loop as SceneTree).root.get_node_or_null("App") if loop is SceneTree else null
	if app != null and app.get("settings") is AppSettings:
		return (app.get("settings") as AppSettings).player_name()
	return "Gast"
