class_name GameTable
extends TableSource
# Gemeinsame Basis von LocalTable und HostTable (Modul G): MauGame im eigenen Prozess, Computergegner-Takt, Speicherstand.
#
# Ablauf: Jede angenommene Aktion (Mensch, Bot oder Netz-Gast) läuft über _apply() → _changed(events): Zähler, Speicherstand,
# Verteilung (_distribute, je Unterklasse) und Neuplanung des nächsten Bot-Zugs. Bots handeln nie sofort, sondern nach einer
# Denkpause (0,6–1,2 s × speed). Sie werden auch außerhalb ihres Zugs gefragt (Erwischen); Menschen bekommen beim offenen
# Mau-Fenster eine Schonfrist (MAU_GRACE), bevor ein Bot sie erwischt oder mit seinem Zug das Fenster schließt.
# busy_check (optional, z. B. director.is_busy) hält Bots an, solange die Oberfläche noch Ereignisse abspielt.
# Zeit läuft nur in pump() (aus _process, wenn auto_process; Tests rufen pump() selbst und setzen speed = 0).

const THINK_MIN := 0.6
const THINK_MAX := 1.2
const MAU_THINK := 0.35          # „Mau!“ rufen Bots etwas schneller
const MAU_GRACE := 1.5           # Schonfrist für Menschen im Mau-Fenster (Regelbericht: etwa 1,5 s)
const ROUND_PAUSE := 1.2         # zusätzlich nach dem Austeilen
const BUSY_RETRY := 0.3          # Oberfläche beschäftigt: so lange später erneut versuchen
const NEXT_ROUND_TAIL := " Weiter mit der nächsten Runde."

var speed := 1.0                 # Faktor für alle Pausen; 0 = keine (Tests)
var think_factor := 1.0          # nur Bedenkzeit der Computergegner (Regler „Tempo der Computergegner“, AppSettings.think_factor)
var bot_level := 1               # MauBot-Stufe 0–2
var auto_process := true
var autosave := true
var save_path := SAVE_PATH
var busy_check := Callable()     # () -> bool: true = Oberfläche spielt noch ab, Bots warten
var max_steps := 400             # höchstens so viele Bot-Aktionen je pump()

var game: MauGame
var seats: Array = []            # je Platz {name, kind: "human"|"bot", host: bool, …}
var host_seat := 0               # darf „next_round“ (Gastgeber-Platz im Regelwerk)
var rev := 0                     # Stand-Zähler, steigt mit jeder Änderung

var _substitute := {}            # Platz -> true: Bot spielt für einen Menschen (HostTable.substitute_bot)
var _rng := RandomNumberGenerator.new()
var _plan := {}                  # nächster Bot-Zug {seat, action, at}
var _plan_dirty := true
var _extra_pause := 0.0
var _last_view := {}


func _process(_delta: float) -> void:
	if auto_process:
		pump()


# Arbeit, die jetzt fällig ist: Netz abfragen, Sichtschutz melden, Bots ziehen lassen.
func pump() -> void:
	_poll_extra()
	if game == null:
		return
	for i in max_steps:
		if not _step():
			break


func current_view() -> Dictionary:
	return _last_view


func is_bot(seat: int) -> bool:
	return seat >= 0 and seat < seats.size() and (str(seats[seat].kind) == "bot" or _substitute.has(seat))


func seat_name(seat: int) -> String:
	return str(seats[seat].name) if seat >= 0 and seat < seats.size() else "?"


# Sicht eines Platzes, angepasst an die Spielsteuerung: can_next_round nach _may_continue, Unterklassen-Hinweise.
func view_of(seat: int) -> Dictionary:
	var v := game.view_for(seat)
	var h: Dictionary = v.hints
	var can := game.phase() == "round_over" and _may_continue(seat)
	if bool(h.get("can_next_round", false)) != can:
		h.can_next_round = can
		var t := str(h.get("text", ""))
		if can and not t.ends_with(NEXT_ROUND_TAIL):
			h.text = t + NEXT_ROUND_TAIL
		elif not can and t.ends_with(NEXT_ROUND_TAIL):
			h.text = t.trim_suffix(NEXT_ROUND_TAIL)
	_patch_view(seat, v)
	return v


# --- für Unterklassen ---

func _poll_extra() -> void:
	pass


func _pre_step() -> bool:
	return false


func _bots_paused() -> bool:
	return false


func _may_continue(seat: int) -> bool:
	return seat == host_seat


func _patch_view(_seat: int, _v: Dictionary) -> void:
	pass


func _distribute(_events: Array) -> void:
	pass


func _after_change() -> void:
	pass


func _save_extra() -> Dictionary:
	return {}


# --- Partie ---

func _create_game(cfg: RuleConfig, players: Array, rng_seed: int) -> void:
	if rng_seed == 0:
		rng_seed = int(Crypto.new().generate_random_bytes(6).hex_encode().hex_to_int())
	seats = []
	host_seat = -1
	for i in players.size():
		var p: Dictionary = (players[i] as Dictionary).duplicate(true)
		p.kind = "bot" if str(p.get("kind", "human")) == "bot" else "human"
		p.name = str(p.get("name", "Spieler %d" % (i + 1)))
		if bool(p.get("host", false)) and host_seat < 0:
			host_seat = i
		p.host = false
		seats.append(p)
	if host_seat < 0:
		host_seat = 0
	seats[host_seat].host = true
	_substitute.clear()
	_rng.seed = rng_seed ^ 0x5EED
	game = MauGame.create(cfg, seats, rng_seed)
	rev = 0


func _begin_round() -> void:
	_changed(game.start_round())


# Aktion eines Platzes anwenden; „next_round“ immer über den Gastgeber-Platz (Rechte prüft der Aufrufer).
func _apply(seat: int, action: Dictionary) -> Dictionary:
	var r: Dictionary
	if str(action.get("a", "")) == "next_round" and game.phase() == "round_over":
		r = game.apply(host_seat, {"a": "next_round"})
		if not bool(r.ok) and host_seat != 0:
			r = game.apply(0, {"a": "next_round"})      # Regelwerk ohne Gastgeber-Platz: nur Platz 0 darf
	else:
		r = game.apply(seat, action)
	if bool(r.ok):
		_changed(r.events)
	return r


func _changed(events: Array) -> void:
	rev += 1
	_plan_dirty = true
	_plan = {}
	for e in events:
		if str((e as Dictionary).get("e", "")) == "round_start":
			_extra_pause = ROUND_PAUSE
	_after_change()
	if autosave:
		_save()
	_distribute(events)


# --- Computergegner ---

func _step() -> bool:
	if _pre_step():
		return true
	if _bots_paused():
		return false
	if _plan_dirty:
		_plan_dirty = false
		_plan = _next_bot_plan()
	if _plan.is_empty():
		return false
	var now := Time.get_ticks_msec()
	if now < int(_plan.at):
		return false
	if _ui_busy():
		_plan.at = now + int(BUSY_RETRY * 1000.0 * speed)
		return false
	var p := _plan
	_plan = {}
	var seat := int(p.seat)
	var r := _apply(seat, p.action)
	if not bool(r.ok):
		# Darf nicht vorkommen (Hinweise = Regeln); trotzdem nie hängen bleiben.
		push_warning("Computergegner %d: %s abgelehnt (%s)" % [seat, str(p.action), r.reason])
		for alt in [{"a": "draw"}, {"a": "accept"}, {"a": "keep"}, {"a": "color", "color": str((game.view_for(seat).colors as Array)[0])}]:
			if bool(_apply(seat, alt).ok):
				return true
		return false
	return true


func _next_bot_plan() -> Dictionary:
	var phase := game.phase()
	if not phase in MauGame.PLAY_PHASES:
		return {}
	var cur := game.current_seat()
	var order: Array = []
	if is_bot(cur):
		order.append(cur)
	for s in seats.size():
		if s != cur and is_bot(s):
			order.append(s)
	for s in order:
		var a := MauBot.choose(game.view_for(s), _rng.randi(), bot_level)
		if a.is_empty():
			continue
		var name := str(a.get("a", ""))
		var delay := _rng.randf_range(THINK_MIN, THINK_MAX) * think_factor
		if name == "mau":
			delay = MAU_THINK * minf(think_factor, 1.0)
		var mo := game.mau_open
		var grace: bool = mo >= 0 and mo != s and not is_bot(mo) and not bool(game.mau_said[mo])
		if grace:
			delay = maxf(delay, MAU_GRACE + _rng.randf_range(0.0, 0.5))
		delay += _extra_pause
		_extra_pause = 0.0
		return {"seat": s, "action": a, "at": Time.get_ticks_msec() + int(delay * 1000.0 * speed)}
	return {}


func _ui_busy() -> bool:
	return busy_check.is_valid() and bool(busy_check.call())


# --- Speicherstand ---

func _save() -> void:
	if game == null:
		return
	var d := {"format": 1, "mode": mode(), "saved": Time.get_datetime_string_from_system(), "game": game.to_dict(),
		"seats": seats.duplicate(true), "host_seat": host_seat, "extra": _save_extra()}
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(d))
	f.close()
	DirAccess.rename_absolute(tmp, save_path)


# Gespeicherte Plätze zurückholen (JSON macht aus Zahlen float).
func _restore_seats(data: Dictionary) -> void:
	seats = []
	for p in data.get("seats", []):
		var d: Dictionary = (p as Dictionary).duplicate(true)
		for k in d:
			if d[k] is float and float(d[k]) == floorf(float(d[k])):
				d[k] = int(d[k])
		seats.append(d)
	host_seat = int(data.get("host_seat", 0))
	_substitute.clear()
	_rng.seed = Time.get_ticks_usec()
