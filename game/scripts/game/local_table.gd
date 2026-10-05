class_name LocalTable
extends GameTable
# Übungsspiel ("solo": 1 Mensch + Computergegner) und Weitergeben ("pass": 2–10 Menschen an einem Gerät, optional Bots).
#
# Weitergeben: Gezeigt wird immer genau eine Hand (local_seat). Muss ein anderer Mensch handeln (Zug, Anzweifeln, Farbwahl,
# gezogene Karte), kommt erst handover(next_seat, name) – die Oberfläche zeigt den Sichtschutz und ruft reveal() auf –, und erst
# dann state_changed mit der Sicht des neuen Menschen. Bis dahin ist local_seat() = -1, Ereignisse werden gesammelt und Bots
# warten. Zwischen zwei Menschen kommt also nie eine Sicht mit fremder Hand heraus. Ziehen Bots zwischendurch, sieht der zuletzt
# gezeigte Mensch zu (seine eigene Hand). Hat er gerade seine vorletzte Karte gelegt, wartet der Sichtschutz die Mau-Schonfrist ab,
# damit „Mau!“ auch nach dem Legen geht.
#
# Nutzung:
#   var t := LocalTable.new(); add_child(t)
#   t.setup("solo", [{name="Lena", kind="human"}, {name="Minka", kind="bot"}], RuleConfig.preset("offiziell"))
#   t.state_changed.connect(table_view.handle_state); t.handover.connect(…); t.start()

const HANDOVER_PAUSE := 0.6      # nach dem eigenen Zug, bevor der Sichtschutz kommt (Karte fliegt noch)

var _mode := "solo"
var _shown := -1                 # gezeigte Hand
var _awaiting := -1              # Sichtschutz gemeldet, wartet auf reveal()
var _handover_to := -1           # Sichtschutz geplant
var _handover_at := 0
var _buffer: Array = []          # Ereignisse, während keine Hand gezeigt wird


# players: [{name, kind: "human"|"bot"}] in Sitzordnung (Uhrzeigersinn). false = ungültige Besetzung.
func setup(table_mode: String, players: Array, config: RuleConfig = null, rng_seed := 0) -> bool:
	var humans := 0
	for p in players:
		if str((p as Dictionary).get("kind", "human")) != "bot":
			humans += 1
	if not table_mode in ["solo", "pass"] or players.size() < 2 or players.size() > 10 or humans < 1 \
			or (table_mode == "solo" and humans != 1) or (table_mode == "pass" and humans < 2):
		notice.emit("Ungültige Besetzung (%s, %d Spieler, davon %d Menschen)." % [table_mode, players.size(), humans])
		return false
	_mode = table_mode
	var list: Array = []
	var host_set := false
	for p in players:
		var d: Dictionary = (p as Dictionary).duplicate()
		d.host = not host_set and str(d.get("kind", "human")) != "bot"
		host_set = host_set or bool(d.host)
		list.append(d)
	_create_game(config if config != null else RuleConfig.new(), list, rng_seed)
	_shown = -1
	_awaiting = -1
	_handover_to = -1
	_buffer.clear()
	return true


func start() -> void:
	if game == null:
		return
	if _mode == "solo":
		_shown = _first_human()
	game_started.emit(_shown if _mode == "solo" else _first_human())
	_begin_round()


# Fortsetzen aus TableSource.load_saved(); false = passt nicht.
func resume(data: Dictionary) -> bool:
	if not str(data.get("mode", "")) in ["solo", "pass"] or not data.get("game") is Dictionary:
		return false
	_mode = str(data.mode)
	_restore_seats(data)
	game = MauGame.from_dict(data.game)
	if game.seat_count() != seats.size() or seats.size() < 2:
		game = null
		return false
	_shown = -1
	_awaiting = -1
	_handover_to = -1
	_buffer.clear()
	_plan_dirty = true
	if _mode == "solo":
		_shown = _first_human()
		game_started.emit(_shown)
		_emit(_shown, [])
	else:
		game_started.emit(_first_human())
		_schedule_handover(_first_needed(), true)
	return true


func mode() -> String:
	return _mode


func local_seat() -> int:
	return _shown


# Platz, auf dessen reveal() gewartet wird (-1: keiner).
func pending_handover() -> int:
	return _awaiting


func act(action: Dictionary) -> void:
	if game == null:
		notice.emit("Es läuft keine Partie.")
		return
	if str(action.get("a", "")) == "next_round":
		var r := _apply(host_seat, action)
		if not bool(r.ok):
			notice.emit(str(r.reason))
		return
	if _shown < 0:
		notice.emit("Erst das Handy weitergeben.")
		return
	var res := _apply(_shown, action)
	if not bool(res.ok):
		notice.emit(str(res.reason))


func reveal() -> void:
	if _awaiting < 0:
		return
	_shown = _awaiting
	_awaiting = -1
	var ev := _buffer
	_buffer = []
	_plan_dirty = true
	_emit(_shown, ev)


func leave() -> void:
	game = null
	_plan = {}
	_buffer.clear()
	_shown = -1
	_awaiting = -1
	_handover_to = -1
	if autosave:
		clear_saved(save_path)


# --- intern ---

func _may_continue(seat: int) -> bool:
	return seat >= 0 and not is_bot(seat)      # am eigenen Gerät darf jeder Mensch weiterschalten


func _emit(seat: int, events: Array) -> void:
	_last_view = view_of(seat)
	state_changed.emit(game.events_for(seat, events), _last_view)


func _distribute(events: Array) -> void:
	if _mode == "solo":
		_emit(_shown, events)
		return
	if _awaiting >= 0 or _shown < 0:
		_buffer.append_array(events)
		if _shown < 0 and _awaiting < 0:
			_schedule_handover(_first_needed(), true)
		return
	_emit(_shown, events)
	var need := _needed_human()
	if need >= 0 and need != _shown:
		_schedule_handover(need, false)
	else:
		_handover_to = -1


func _schedule_handover(seat: int, now := false) -> void:
	if seat < 0:
		return
	if seat == _handover_to and not now:
		return
	_handover_to = seat
	var delay := 0.0 if now else HANDOVER_PAUSE
	var mo := game.mau_open
	if not now and mo >= 0 and mo == _shown and not bool(game.mau_said[mo]):
		delay = maxf(delay, MAU_GRACE)
	_handover_at = Time.get_ticks_msec() + int(delay * 1000.0 * speed)


func _pre_step() -> bool:
	if _mode != "pass" or _handover_to < 0 or _awaiting >= 0:
		return false
	var need := _first_needed() if _shown < 0 else _needed_human()
	if need < 0 or need == _shown:
		_handover_to = -1
		return false
	_handover_to = need
	if Time.get_ticks_msec() < _handover_at or _ui_busy():
		return false
	_awaiting = _handover_to
	_handover_to = -1
	_shown = -1
	handover.emit(_awaiting, seat_name(_awaiting))
	return true


func _bots_paused() -> bool:
	return _mode == "pass" and (_awaiting >= 0 or _shown < 0)


# Mensch, der jetzt handeln muss (-1: ein Bot oder niemand).
func _needed_human() -> int:
	var actor := game.current_seat()
	return actor if actor >= 0 and not is_bot(actor) else -1


# Für den Anfang: der Mensch am Zug, sonst der nächste Mensch in Spielrichtung.
func _first_needed() -> int:
	var actor := game.current_seat()
	if actor < 0:
		return _first_human()
	var n := seats.size()
	for k in n:
		var s := posmod(actor + k * game.dir, n)
		if not is_bot(s):
			return s
	return _first_human()


func _first_human() -> int:
	for s in seats.size():
		if not is_bot(s):
			return s
	return -1
