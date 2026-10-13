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
# Oberfläche: swapped(new_source, note) → Tisch ersetzen (nav.replace(TableScreen.create(new_source))) und note zeigen. Zustand
# (state_changed), missing(), countdown_ms(), can_continue()/continue_warnings()/continue_as_host() für den Verbindungsstreifen.
# Tests: auto_process = false und pump() selbst rufen; Fristen als Eigenschaften, wall_ms einspritzbar, host_factory/client_factory.

signal state_changed(state: String)
signal swapped(new_source: TableSource, note: String)   # neue Quelle für den Tisch (ohne Elternknoten; HostSwitch hängt schon daran)
signal confirm_needed(info: Dictionary)                 # resume_saved: Rückfrage {role, age_min, warnings: [lt]}

const NODE_NAME := "HostSwitch"
const WATCH_PHASES := ["turn", "drawn", "challenge", "color", "gamble", "discard_pick", "round_over"]   # MauGame.PLAY_PHASES + round_over

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

var state := "off"
var source: TableSource              # überwachte Quelle (ClientTable oder HostTable), null im Ablauf resume_saved
var last_error := ""                 # deutsche msgid (I18n.t), z. B. Raum abgelaufen
var takeovers := 0                   # Tests/Log: so oft hat dieses Gerät übernommen

# Gast-Wächter
var _armed_at := 0
var _away_since := 0
var _seen_rev := -1
var _probe_at := 0
var _probe_welcomes := 0
var _take_at := -1
var _check := ""                     # checking/resuming: "join" | "info" | "fresh" | "decided"
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
static func deadline_for(last: int, gone: int, away_since: int, t_silent: int, t_away: int, link: int) -> int:
	if away_since > 0 and (gone <= 0 or away_since <= gone + link):
		return maxi(away_since + t_away, (gone if gone > 0 else last) + t_silent)
	if gone > 0:
		return gone + t_silent
	return last + t_silent


# Fortsetzbarer Stand aus der Datei ({} = nichts anzubieten): online (Raum jünger als 24 h) oder eigene Gastgeber-Datei im WLAN.
static func saved_offer(path := TableSource.NET_SAVE_PATH, now_unix := -1) -> Dictionary:
	var d := MatchSnapshot.read(path)
	var now := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	if d.is_empty() or not MatchSnapshot.resumable(d, now):
		return {}
	if (d.online as Dictionary).is_empty() and str(d.role) != "host":
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
		if ct.client != null:
			ct.client.clock = now_wall
		if not ct.handover_received.is_connected(_on_handover):
			ct.handover_received.connect(_on_handover)
		_go("off")


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


# Knopf „Spiel als Gastgeber fortsetzen“ möglich? (jeder App-Gast mit Sicherung, sobald der Gastgeber fehlt)
func can_continue() -> bool:
	return state in ["missing", "waiting"] and _watched() != null and _armed(_watched())


# Warnzeilen zur Rückfrage (Bausteine): Sicherung nicht aktuell, WLAN-Mitspieler am Tisch.
func continue_warnings() -> Array:
	var ct := _watched()
	return _warnings(ct.backup if ct != null else {}, ct != null and ct.backup_current())


# „Spiel als Gastgeber fortsetzen“ (nach der Rückfrage): /info und frische Probe, dann Übernahme. false = gerade nicht möglich.
func continue_as_host() -> bool:
	if not can_continue():
		return false
	_manual = true
	_probe_welcomes = _watched().client.welcomes
	_begin_final()
	return true


# Hauptmenü „Partie fortsetzen“: Stand aus der Datei (saved_offer). Ablauf siehe oben; Ergebnis über swapped bzw. confirm_needed.
func resume_saved(data: Dictionary) -> Error:
	var d := MatchSnapshot.clean(data)
	if d.is_empty() or not MatchSnapshot.resumable(d, now_wall() / 1000):
		return ERR_INVALID_DATA
	var mine := int(d.host_seat) if str(d.role) == "host" else int(d.my_seat)
	if mine < 0 or MatchSnapshot.seat_token(d, mine) == "":
		return ERR_INVALID_DATA
	_detach()
	_saved = d
	last_error = ""
	var o: Dictionary = d.online
	if o.is_empty():
		if str(d.role) != "host":
			return ERR_UNAVAILABLE
		_back_state = "expired"
		_take_over(d, -1, 0, [])            # WLAN: eigene Partie auf dem gespeicherten Port (sofort, ohne Raum)
		return OK if state == "host" else ERR_CANT_OPEN
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
	if _new != null and is_instance_valid(_new) and _new is HostTable:
		_drop_host(_new as HostTable)
	_new = null
	_go("off")


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
	match state:
		"off", "watch", "missing", "waiting", "checking":
			_poll_guest(now)
		"taking":
			_poll_taking(now)
		"host":
			_poll_note(now)
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
		if state != "off":
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
		_go("off")
		return
	if state != "watch" and c.welcomes > _probe_welcomes:
		_back_to_watch(now)          # ein Gastgeber hat geantwortet (auch ein neuer)
		return
	match state:
		"watch":
			if _armed_at > now:
				_armed_at = now              # Uhr zurückgestellt: ab jetzt zählen
			var last := maxi(c.last_host_wall if c.last_host_wall <= now else _armed_at, _armed_at)
			var gone := c.host_away_wall if c.host_away_wall >= last and c.host_away_wall <= now else 0
			if now >= deadline_for(last, gone, _away_since, t_silent_ms, t_away_ms, away_link_ms):
				_start_probe(c, now)
				_go("missing")
		"missing":
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
			if _take_at >= 0 and now >= _take_at:
				_begin_final()
		"checking":
			_poll_final(ct, now)


func _poll_final(ct: ClientTable, now: int) -> void:
	var c := ct.client
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
	_armed_at = now
	_go("watch")


func _reset_watch() -> void:
	_take_at = -1
	_check = ""
	_manual = false
	_away_since = 0
	_seen_rev = -1


func _armed(ct: ClientTable) -> bool:
	if ct == null or ct.client == null or not ct.client.is_online() or ct.backup.is_empty() or ct.is_retired() or not ct.backups:
		return false
	if not ct.phase() in WATCH_PHASES:
		return false
	var gid := ct.game_gid()
	return gid != "" and str(ct.backup.get("gid", "")) == gid and ct.backup_seat() >= 0


func _watched() -> ClientTable:
	return source as ClientTable


func _guest() -> ClientTable:
	return _flow_ct if _flow_ct != null else source as ClientTable


static func _warnings(d: Dictionary, current: bool) -> Array:
	var out: Array = []
	if not current:
		out.append(I18n.part("Dein Spielstand ist vielleicht nicht der neueste."))
	if bool(d.get("wlan_humans", false)):
		out.append(I18n.part("WLAN-Mitspieler kommen dann nicht mit."))
	return out


# --- Übernahme ---

func _take_over_backup(ct: ClientTable) -> void:
	var seat := ct.backup_seat()
	_back_state = "watch"
	_take_over(ct.backup.duplicate(true), seat, takeover_within_ms,
		[I18n.part("%s führt das Spiel weiter (Gastgeber war weg).", [_seat_name(ct.backup, seat)])])


# Stand übernehmen: Gast-Socket zu (ohne bye), HostTable.resume(data, seat) samt Online-Raum; within_ms bis zum room-Rahmen.
func _take_over(data: Dictionary, seat: int, within_ms: int, note_lt: Array) -> void:
	var ct := _guest()
	if ct != null:
		ct.suspend()
	var ht := _make_host()
	add_child(ht)
	_new = ht
	# Die Datei bleibt, wie sie ist, bis der Raum übernommen ist (_finish_take): Stirbt die App vorher, läge sonst eine Gastgeber-Datei
	# (role "host", gen + 1) eines Geräts herum, das nie Gastgeber war – das Hauptmenü setzte sie ohne Rückfrage fort.
	_new_autosave = ht.autosave
	ht.autosave = false
	if ht.resume(data, seat, port_first, port_last) != OK:
		_take_failed(false)
		return
	_note_lt = note_lt                       # Meldung an alle, sobald die Gäste zurück sind (_poll_note)
	_note_wait = []
	for s in (data.get("seats", []) as Array).size():
		var p: Dictionary = data.seats[s]
		if s != seat and s != int(data.get("host_seat", -1)) and str(p.get("kind", "")) != "bot" and str(p.get("token", "")) != "":
			_note_wait.append(str(p.token))
	_take_until = now_wall() + maxi(within_ms, 0)
	_go("taking")
	if (data.get("online", {}) as Dictionary).is_empty():
		_finish_take()                       # WLAN (eigene Partie): kein Raum zu übernehmen


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
	if st == "open":
		_finish_take()
	elif st == "stepped_down":
		_take_failed(false)                  # gleichzeitig übernommen und verloren (4000): wieder Gast, die eigene gen gilt nicht
	elif st == "failed" or st == "off":
		var r := ht.session.relay
		_take_failed(r != null and r.close_code in [NetProtocol.CLOSE_ROOM_UNKNOWN, NetProtocol.CLOSE_BAD_TOKEN])
	elif now >= _take_until:
		_take_failed(false)


func _finish_take() -> void:
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
	remove_child(ht)
	_move_to(ht)
	_note_until = now_wall() + ht.settle_max_ms
	swapped.emit(ht, I18n.t("Du bist jetzt Gastgeber. Bitte lass die App offen."))


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
	_back_state = state if state in ["joining", "resuming"] else "watch"
	_end_probe()
	_take_over(d.duplicate(true), seat, int(m.within_ms), [I18n.part("%s ist jetzt Gastgeber.", [_seat_name(d, seat)])])


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
func _on_stepped_down(new_host: String) -> void:
	var ht := source as HostTable
	if ht == null:
		return
	_end_probe()
	var data := ht.handover_shutdown()
	ht.autosave = false                      # die Datei gehört jetzt dem Gast-Tisch (gleicher Pfad)
	var d := MatchSnapshot.clean(data)
	if d.is_empty() or (d.online as Dictionary).is_empty():
		_go("off")                           # WLAN: Stufe 2
		return
	var seat := int(d.my_seat) if int(d.my_seat) >= 0 else int(d.host_seat)
	var ct := _make_client()
	add_child(ct)
	_flow_ct = ct
	ct.handover_received.connect(_on_handover)
	ct.join(NetProtocol.room_link(str(d.online.relay), str(d.online.room)), 0, _seat_name(d, seat), MatchSnapshot.seat_token(d, seat))
	ct.adopt_backup(d, seat)
	_join_until = now_wall() + join_wait_ms
	_join_name = new_host
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
	var ct := _flow_ct
	if ct == null:
		_go("off")
		return
	_pump_node(ct)
	var c := ct.client
	if c != null and c.welcomes > _probe_welcomes and c.state == "open":
		# Ein Gastgeber antwortet: als Gast weiter (ein jüngerer Zweig auf diesem Gerät kommt über hello.bk zurück)
		var note := I18n.t("%s führt das Spiel inzwischen. Du spielst als Gast weiter.") % ct.host_name() if str(_saved.role) == "host" else ""
		_finish_guest(note)
		return
	if c == null or ct.connection_state() in ["closed", "rejected", "ended"]:
		last_error = "Der Online-Raum ist abgelaufen. Die Partie lässt sich nicht mehr fortsetzen."
		_free_flow_ct()
		_go("expired")
		return
	if state == "confirm":
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


func _decide() -> void:
	var age := MatchSnapshot.age_s(_saved, now_wall() / 1000)
	if str(_saved.role) == "host" and age < NetProtocol.RESUME_QUIET_MIN * 60:
		_resume_from_saved()                 # eigene Partie, eben erst gespeichert: ohne Rückfrage (eigener Zweig, gen bleibt)
		return
	_check = "decided"
	_go("confirm")
	confirm_needed.emit({"role": str(_saved.role), "age_min": maxi(age, 0) / 60,
		"warnings": _warnings(_saved, str(_saved.role) == "host")})


func _resume_from_saved() -> void:
	var guest := str(_saved.role) == "guest"
	var seat := int(_saved.my_seat) if guest else -1
	_back_state = "resuming"
	_take_over(_saved, seat, takeover_within_ms,
		[I18n.part("%s führt das Spiel weiter (Gastgeber war weg).", [_seat_name(_saved, seat)])] if guest else [])


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


# --- Hilfen ---

func _detach() -> void:
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
