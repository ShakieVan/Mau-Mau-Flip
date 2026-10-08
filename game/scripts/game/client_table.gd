class_name ClientTable
extends TableSource
# Netzwerkspiel, App-Mitspieler (Modul G): NetClient (Modul D) zur Adresse des Gastgebers. Meldet sich mit Name, kind "app" und –
# falls bekannt – Token an; verbindet bei Verlust selbst neu (als derselbe Spieler). Der Gastgeber entscheidet alles, hier kommen
# nur die eigene Sicht und die für diesen Platz gefilterten Ereignisse an.
#   lobby → lobby_changed · start → game_started · state → state_changed · err/notice → notice
#   reject → connection_changed("rejected") + notice (bei falscher Version mit Hinweis auf /apk) · bye → notice + "closed"
# act() schickt {t:"act", seq, a}.

var client: NetClient
var auto_process := true
var reuse_token := true          # Token je Gastgeber-Adresse wiederverwenden (Tests mit mehreren Clients: false)
var persist_tokens := true
var retry_ms: Array = []         # Tests: kürzere Abstände beim Neuverbinden
var ping_ms := 0
var lobby := {}
var my_id := 0
var token := ""
var view_rev := 0                # Anzahl empfangener Stände
var last_rev := -1               # rev des Gastgebers im letzten Stand
var address := ""
var port := 0

var _seat := -1
var _view := {}
var _seq := 0
var _rejected := false
var _leaving := false
var _ended := false               # Spiel beendet: Gastgeber nach dem Spielende nicht mehr erreichbar (N6)

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
	client = NetClient.new()
	client.name = "NetClient"
	client.auto_poll = false
	client.reuse_token = reuse_token
	client.persist_tokens = persist_tokens
	if not retry_ms.is_empty():
		client.retry_ms = retry_ms.duplicate()
	if ping_ms > 0:
		client.ping_ms = ping_ms
	add_child(client)
	client.state_changed.connect(_on_state)
	client.welcomed.connect(_on_welcomed)
	client.message.connect(_on_message)
	client.rejected.connect(_on_rejected)
	client.closed.connect(_on_closed)
	var err := client.connect_to(host_address, host_port, player_name if player_name != "" else _own_name(), "app")
	if with_token != "":
		client.token = with_token      # die Begrüßung entsteht erst in poll(), sobald der Socket offen ist
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
	return client.hint() if client != null else "Verbindung zum Gastgeber unterbrochen – warte …"


func act(action: Dictionary) -> void:
	if client == null or client.state != "open":
		notice.emit("Keine Verbindung zum Gastgeber – einen Moment …")
		return
	_seq += 1
	if client.send({"t": "act", "seq": _seq, "a": action}) != OK:
		notice.emit("Senden fehlgeschlagen – die Verbindung wird erneuert.")


# Bereit-Meldung in der Lobby.
func set_ready(ready: bool) -> void:
	if client != null and client.state == "open":
		client.send({"t": "lobby_ready", "ready": ready})


func leave() -> void:
	_leaving = true
	_drop_client()


func _process(_delta: float) -> void:
	if auto_process:
		pump()


func pump() -> void:
	if client != null:
		client.poll()
		_check_give_up()


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


func _on_message(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"lobby":
			# Lobby-Stände verteilt der Gastgeber nur ohne laufende Partie: Ein alter Stand gilt nicht mehr (sonst zeigte ein neuer
			# Tisch kurz die vorige Partie).
			lobby = msg
			_view = {}
			_seat = -1
			lobby_changed.emit(msg)
		"start":
			_seat = int(msg.get("seat", -1))
			game_started.emit(_seat)
		"state":
			if not msg.get("view") is Dictionary:
				return
			view_rev += 1
			last_rev = int(msg.get("rev", -1))
			_view = msg.view
			_seat = int(_view.get("seat", _seat))
			state_changed.emit(msg.get("events", []) if msg.get("events") is Array else [], _view)
		"err", "notice":
			notice.emit(I18n.msg_text(msg, "Das geht gerade nicht."))   # eigene Sprache (I18n: lt oder msgid)


func _on_rejected(code: String, text: String) -> void:
	_rejected = true
	if code == "version" and not text.contains("/apk"):
		text += " " + I18n.t("App vom Gastgeber holen: %s") % ("http://%s:%d/apk" % [address, port])
	connection_changed.emit("rejected")
	notice.emit(text)


func _on_closed(text: String) -> void:
	if _rejected or _leaving:
		return
	notice.emit(text)


func _own_name() -> String:
	var loop := Engine.get_main_loop()
	var app: Node = (loop as SceneTree).root.get_node_or_null("App") if loop is SceneTree else null
	if app != null and app.get("settings") is AppSettings:
		return (app.get("settings") as AppSettings).player_name()
	return "Gast"
