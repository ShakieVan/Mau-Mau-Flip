class_name RoomKeeper
extends Node
# Mau-Mau Flip (Beta 1.6.16, Raum behalten, docs/module/raum_behalten.md): Raumhalter des Gastgebers. Verlässt der Gastgeber Tisch oder
# Lobby („Partie verlassen“, „Lobby schließen“), endet sein Online-Raum nicht mehr ({k:"end"}): HostTable.leave übergibt den
# Vermittler-Anschluss (NetRelayHost, Socket bleibt offen) hierher. Eröffnet er danach wieder ein Spiel, holt die Lobby den Raum zurück
# (take → NetHostSession.adopt_online) – derselbe Raumcode, Gäste mit dem gemerkten Code oder Link kommen einfach wieder hinein.
#  - Gäste, die in der Zwischenzeit kommen: Wer eine Sicherung der beendeten Partie meldet (hello.bk_gid = gid der Partie bzw.
#    hello.bk_token eines ihrer Plätze), bekommt „bye“ („Der Gastgeber hat das Spiel beendet.“) – er löscht seine Sicherung und kann den
#    verlassenen Raum nicht per HostSwitch übernehmen. Alle anderen (App ohne Sicherung, Browser) bekommen 4503 („Gastgeber kurz weg“):
#    Sie versuchen es alle 10 s erneut und landen in der neuen Lobby, sobald der Gastgeber wieder eröffnet.
#  - Höchstens KEEP_S nach dem Verlassen, danach endet der Raum. Raum weg (failed), von einem anderen Gerät übernommen (stepped_down)
#    oder off: vergessen (in pump nach poll). Neuverbinden nach einem Abriss geht ohne Probe (needs_check ohne Empfänger → claim).
#  - Datei save_path {relay, room, token, max_c, created_unix, seen_unix, gid}: Wird die App beendet, hält der Vermittler den Raum noch
#    grace_s (600 s) ab dem letzten Lebenszeichen; bis REUSE_GRACE_S danach holt take() ihn per open_existing zurück.
#  - Wiederverwendet wird nur mit mindestens MIN_LIFE_S Restlaufzeit (der Vermittler hält einen Raum höchstens LIFE_S ab dem Anlegen).
# Nur in der App eingeschaltet (enabled, App._init); Tests schalten es selbst ein und pumpen den Halter (auto_process = false, pump()).

const KEEP_S := 1800                # so lange hält die App den Raum nach dem Verlassen höchstens
const LIFE_S := 86400               # Vermittler: Lebensdauer eines Raums ab Anlegen (relay/src/core.js life_s)
const MIN_LIFE_S := 10800           # wiederverwenden nur mit mindestens 3 h Restlaufzeit
const REUSE_GRACE_S := 540          # ohne laufenden Halter: Datei gilt so lange ab dem letzten Lebenszeichen (Vermittler grace_s 600)
const SEEN_EVERY_S := 60            # Lebenszeichen in der Datei
const HELLO_WAIT_MS := 10000        # so lange darf ein Gast ohne hello bleiben, dann 4503
const SAVE_PATH := "user://eigener_raum.json"
const BYE_TEXT := "Der Gastgeber hat das Spiel beendet."

static var enabled := false         # App._init: an, außer in Testläufen
static var current: RoomKeeper = null
static var save_path := SAVE_PATH
static var clock := Callable()      # Tests: () -> Wanduhr in s
static var attach := true           # Tests: false = nicht in den Baum hängen (pump() selbst rufen)

var relay: NetRelayHost
var gid := ""                       # Partie, die in diesem Raum lief ("" = nur Lobby)
var tokens: Array = []              # Platz-Token dieser Partie (Gäste und Gastgeber)
var since_unix := 0                 # Zeitpunkt des Verlassens
var auto_process := true
var stats := {"bye": 0, "wait": 0}
var _pending := {}                  # conn -> Frist (ms) für das hello
var _seen_unix := 0


# --- Statische Schnittstelle ---

static func now_unix() -> int:
	return int(clock.call()) if clock.is_valid() else int(Time.get_unix_time_from_system())


# Raum halten: r gehört danach dem Halter (Kind dieses Knotens). game_gid/seat_tokens: die beendete Partie (für „bye“ statt Warten).
# Ein anderer gehaltener Raum endet dabei.
static func keep(r: NetRelayHost, game_gid := "", seat_tokens: Array = []) -> RoomKeeper:
	if r == null:
		return null
	if current != null and is_instance_valid(current):
		if current.relay != null and current.relay.room == r.room:
			current._release()
		else:
			current.end_room()
	var k := RoomKeeper.new()
	k.name = "Raumhalter"
	k.gid = game_gid
	k.tokens = seat_tokens.filter(func(t): return t is String and str(t) != "")
	k.since_unix = now_unix()
	k._hold(r)
	current = k
	var tree := Engine.get_main_loop() as SceneTree
	if attach and tree != null and tree.root != null:
		tree.root.add_child.call_deferred(k)
	k._save()
	k._log("Raum %s bleibt bis zu %d min erhalten" % [r.room, KEEP_S / 60])
	return k


# Lässt sich für diesen Vermittler ein eigener Raum wiederverwenden? {room, relay, live} bzw. {}.
static func reusable(relay_url: String) -> Dictionary:
	var url := NetProtocol.normalize_relay_url(relay_url)
	if url == "":
		return {}
	var k := live()
	if k != null:
		if k.relay.relay_url == url and _life_ok(k.relay.created_unix):
			return {"room": k.relay.room, "relay": url, "live": true}
		return {}
	var d := load_saved()
	if not d.is_empty() and str(d.relay) == url:
		return {"room": str(d.room), "relay": url, "live": false}
	return {}


# Raum für eine neue Lobby übernehmen: {node: NetRelayHost (offen, ohne Elternknoten), room, relay} vom laufenden Halter bzw.
# {room, token, relay, max_c, created_unix} aus der Datei (open_existing); {} = nichts (ein unpassender Halter endet dabei).
static func take(relay_url: String) -> Dictionary:
	var url := NetProtocol.normalize_relay_url(relay_url)
	var k := live()
	if k != null:
		if url == "" or k.relay.relay_url != url or not _life_ok(k.relay.created_unix):
			k.end_room()
			return {}
		var r := k.relay
		k._release()
		_delete_saved()
		return {"node": r, "room": r.room, "relay": url}
	var d := load_saved()
	_delete_saved()
	if d.is_empty() or str(d.relay) != url:
		return {}
	return d


# Gehaltenen Raum beenden ({k:"end"}) und vergessen (auch die Datei).
static func discard() -> void:
	if current != null and is_instance_valid(current):
		current.end_room()
	_delete_saved()


# Laufender Halter mit offenem bzw. wiederkehrendem Anschluss (sonst null)
static func live() -> RoomKeeper:
	if current == null or not is_instance_valid(current) or current.is_queued_for_deletion() or current.relay == null:
		return null
	if not current.relay.state in ["open", "away", "check", "connecting"] or current.relay.room == "" or current.relay.token == "":
		return null
	return current


# Datei lesen und prüfen: gültig nur mit Raum, Token, Vermittler, Restlaufzeit und jüngstem Lebenszeichen; sonst {}.
static func load_saved() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not data is Dictionary:
		return {}
	var room := NetProtocol.normalize_room_code(str(data.get("room", "")))
	var relay_url := NetProtocol.normalize_relay_url(str(data.get("relay", "")))
	var token := str(data.get("token", "")).left(128) if data.get("token") is String else ""
	var created := int(data.get("created_unix", 0)) if data.get("created_unix") is float or data.get("created_unix") is int else 0
	var seen := int(data.get("seen_unix", 0)) if data.get("seen_unix") is float or data.get("seen_unix") is int else 0
	var max_c := int(data.get("max_c", 0)) if data.get("max_c") is float or data.get("max_c") is int else 0
	if room == "" or relay_url == "" or token == "" or not _life_ok(created):
		return {}
	var now := now_unix()
	if seen <= 0 or seen > now + 60 or now - seen > REUSE_GRACE_S:
		return {}
	return {"room": room, "relay": relay_url, "token": token, "max_c": maxi(max_c, 0), "created_unix": created}


static func _life_ok(created: int) -> bool:
	return created > 0 and created + LIFE_S - now_unix() >= MIN_LIFE_S


static func _delete_saved() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


# Gast mit Sicherung der beendeten Partie (er bekäme sonst 4503 und übernähme den Raum)
static func stale_hello(msg: Dictionary, game_gid: String, seat_tokens: Array) -> bool:
	if game_gid != "" and str(msg.get("bk_gid", "")) == game_gid:
		return true
	var bt := str(msg.get("bk_token", ""))
	return bt != "" and seat_tokens.has(bt)


# --- Halter ---

func _hold(r: NetRelayHost) -> void:
	relay = r
	r.auto_poll = false
	if r.get_parent() != null:
		r.get_parent().remove_child(r)
	add_child(r)
	r.ws_opened.connect(_on_open)
	r.ws_message.connect(_on_message)
	r.ws_closed.connect(_on_closed)
	r.state_changed.connect(_on_state)


# Anschluss herausgeben (take): wartende Gäste bekommen 4503 (sie kommen in 10 s wieder), Signale lösen, Knoten weg.
func _release() -> void:
	var r := relay
	relay = null
	if current == self:
		current = null
	if r != null:
		for conn in _pending.keys():
			r.close_ws(conn, NetProtocol.CLOSE_HOST_AWAY, "host away")
		for c in [[r.ws_opened, _on_open], [r.ws_message, _on_message], [r.ws_closed, _on_closed], [r.state_changed, _on_state]]:
			if (c[0] as Signal).is_connected(c[1]):
				(c[0] as Signal).disconnect(c[1])
		if r.get_parent() == self:
			remove_child(r)
	_pending.clear()
	_free_self()


# Raum beenden und vergessen
func end_room() -> void:
	var r := relay
	relay = null
	if current == self:
		current = null
	if r != null:
		_log("Raum %s beendet" % r.room)
		for c in [[r.ws_opened, _on_open], [r.ws_message, _on_message], [r.ws_closed, _on_closed], [r.state_changed, _on_state]]:
			if (c[0] as Signal).is_connected(c[1]):
				(c[0] as Signal).disconnect(c[1])
		r.close(true)
		if r.get_parent() == self:
			remove_child(r)
		r.queue_free()
	_pending.clear()
	_delete_saved()
	_free_self()


func _forget(why: String) -> void:
	var r := relay
	relay = null
	if current == self:
		current = null
	if r != null:
		_log("Raum %s vergessen (%s)" % [r.room, why])
		for c in [[r.ws_opened, _on_open], [r.ws_message, _on_message], [r.ws_closed, _on_closed], [r.state_changed, _on_state]]:
			if (c[0] as Signal).is_connected(c[1]):
				(c[0] as Signal).disconnect(c[1])
		r.close(false)
		if r.get_parent() == self:
			remove_child(r)
		r.queue_free()
	_pending.clear()
	_delete_saved()
	_free_self()


func _free_self() -> void:
	if not is_queued_for_deletion():
		queue_free()                # geht auch außerhalb des Baums (aufgeschobenes add_child, Tests)


func _process(_delta: float) -> void:
	if auto_process:
		pump()


func pump() -> void:
	if relay == null:
		return
	relay.poll()
	if relay.state in ["failed", "off", "stepped_down"]:
		_forget(relay.state)        # Raum weg, von einem anderen Gerät übernommen bzw. geschlossen (nach poll, nie im Signal)
		return
	var now_ms := Time.get_ticks_msec()
	for conn in _pending.keys():
		if now_ms >= int(_pending[conn]):
			_pending.erase(conn)
			stats.wait += 1
			relay.close_ws(conn, NetProtocol.CLOSE_HOST_AWAY, "host away")
	var now := now_unix()
	if now - since_unix >= KEEP_S:
		end_room()
		return
	if relay.state == "open" and now - _seen_unix >= SEEN_EVERY_S:
		_save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if relay != null:
			relay.check_now()
	elif what == NOTIFICATION_PREDELETE:
		if current == self:
			current = null


func _save() -> void:
	if relay == null or relay.room == "" or relay.token == "":
		return
	_seen_unix = now_unix()
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"relay": relay.relay_url, "room": relay.room, "token": relay.token, "max_c": relay.max_c,
		"created_unix": relay.created_unix, "seen_unix": _seen_unix, "gid": gid}))
	f.close()


func _on_open(conn: int, _info: Dictionary) -> void:
	_pending[conn] = Time.get_ticks_msec() + HELLO_WAIT_MS


func _on_message(conn: int, text: String) -> void:
	if not _pending.has(conn) or relay == null:
		return
	var raw := NetProtocol.decode(text)
	var msg := NetProtocol.clean_client_message(raw) if not raw.is_empty() else {}
	if msg.is_empty() or str(msg.get("t", "")) != "hello":
		return
	_pending.erase(conn)
	if stale_hello(msg, gid, tokens):
		stats.bye += 1
		relay.send_text(conn, NetProtocol.encode({"t": "bye", "text": BYE_TEXT}))
		relay.close_ws(conn, NetWs.CLOSE_GOING_AWAY, "Gastgeber beendet", NetHostSession.CLOSE_GRACE_MS)
	else:
		stats.wait += 1
		relay.close_ws(conn, NetProtocol.CLOSE_HOST_AWAY, "host away")


func _on_closed(conn: int, _code: int, _reason: String) -> void:
	_pending.erase(conn)


func _on_state(st: String) -> void:
	if st == "open":
		_save()                     # Lebenszeichen (Vergessen erst in pump, nie mitten im Signal des Anschlusses)


func _log(text: String) -> void:
	print("[Raumhalter] ", text)
