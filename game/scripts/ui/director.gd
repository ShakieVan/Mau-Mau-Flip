class_name Director
extends Node
# Tischregie (docs/recherche/06_hand_ux_effekte.md 4.1, BETA1_PLAN Abschnitt 4/7): spielt die Ereignisse des Gastgebers der
# Reihe nach ab und gleicht danach mit der mitgeschickten Sicht ab. Die Darstellung verändert nie das Ergebnis: Maßgeblich
# ist immer die Sicht; Ereignisse sind nur das Drehbuch dorthin.
# Rückstand: Liegen mehr als 3 Ereignisse an, läuft alles doppelt so schnell; bei mehr als 8 werden die Effekte übersprungen
# (skip_event je Ereignis) und sofort der Endzustand der letzten Sicht gesetzt. Ereignisse ohne Animation (quiet_events, vom
# Handler gesetzt, z. B. „turn“) zählen nicht mit; sonst liefe z. B. ein Glücksspiel-Treffer (Wurf, Ziehen, Einsatz zurück,
# turn) immer im doppelten Tempo.
# Der Handler (TableView) stellt bereit:
#   play_event(ev: Dictionary, speed: float) -> float   startet die Animation, liefert ihre Dauer in Sekunden
#   skip_event(ev: Dictionary) -> void                  Ereignis ohne Animation verbuchen (z. B. laufende Effekte beenden)
#   apply_view(view: Dictionary) -> void                Abgleich auf den Endzustand

signal event_started(ev: Dictionary)
signal view_applied(view: Dictionary)
signal idle

const FAST_BACKLOG := 3
const SKIP_BACKLOG := 8
const FAST_SPEED := 2.0

var handler: Object = null
var quiet_events := {}            # Ereignisnamen ohne Animation (z. B. "turn"): zählen nicht zum Rückstand
var auto_process := true          # false: Zeit nur über step() (Tests)
var skipped := 0                  # übersprungene Ereignisse (Statistik/Tests)
var played := 0

var _queue: Array[Dictionary] = []   # {"ev": …} oder {"view": …}
var _wait := 0.0
var _busy := false


func _process(delta: float) -> void:
	if auto_process:
		step(delta)


# Ereignisse und (optional) die Sicht danach einreihen. Eine leere Sicht bedeutet: kein Abgleich nach diesen Ereignissen.
func enqueue(events: Array, view: Dictionary = {}) -> void:
	for ev in events:
		if ev is Dictionary:
			_queue.append({"ev": ev})
	if not view.is_empty():
		_queue.append({"view": view})
	if not _busy:
		_run()


# Ereignisse, die noch nicht begonnen haben (ohne reine Buchungen wie „turn“, die nichts abspielen)
func backlog() -> int:
	var n := 0
	for item in _queue:
		if item.has("ev") and not quiet_events.has(str((item["ev"] as Dictionary).get("e", ""))):
			n += 1
	return n


func is_busy() -> bool:
	return _busy or not _queue.is_empty()


# Nächste anstehende Sicht (Ziel des laufenden Abschnitts); leer, wenn keine eingereiht ist
func upcoming_view() -> Dictionary:
	for item in _queue:
		if item.has("view"):
			return item["view"]
	return {}


func current_speed() -> float:
	return FAST_SPEED if backlog() > FAST_BACKLOG else 1.0


func step(delta: float) -> void:
	if _wait > 0.0:
		if backlog() > SKIP_BACKLOG:
			_wait = 0.0           # großer Rückstand: laufende Animation nicht abwarten
		else:
			_wait -= delta
			if _wait > 0.0:
				return
	_busy = false
	_run()


# Alles sofort: Effekte überspringen, letzte Sicht setzen (z. B. beim Wiederverbinden oder Verlassen der Szene)
func flush() -> void:
	_wait = 0.0
	_skip_to_last_view(true)
	_busy = false


func clear() -> void:
	_queue.clear()
	_wait = 0.0
	_busy = false


func _run() -> void:
	while not _queue.is_empty():
		if backlog() > SKIP_BACKLOG:
			_skip_to_last_view(false)
			continue
		var speed := current_speed()
		var item: Dictionary = _queue.pop_front()
		if item.has("view"):
			if handler != null:
				handler.call("apply_view", item["view"])
			view_applied.emit(item["view"])
			continue
		var ev: Dictionary = item["ev"]
		event_started.emit(ev)
		played += 1
		var d := 0.0
		if handler != null:
			d = float(handler.call("play_event", ev, speed))
		if d > 0.0:
			_wait = d
			_busy = true
			return
	_busy = false
	idle.emit()


# Überspringt alle Ereignisse bis zur letzten eingereihten Sicht und gleicht damit ab. Ohne Sicht (all=true) wird alles verbucht.
func _skip_to_last_view(all: bool) -> void:
	var last := -1
	for i in _queue.size():
		if _queue[i].has("view"):
			last = i
	if last < 0 and not all:
		# keine Sicht in Reichweite: Ereignisse trotzdem verbuchen, damit der Rückstand schrumpft
		last = _queue.size() - 1
	if all:
		last = _queue.size() - 1
	var final_view: Dictionary = {}
	for i in last + 1:
		var item: Dictionary = _queue[i]
		if item.has("ev"):
			skipped += 1
			if handler != null:
				handler.call("skip_event", item["ev"])
		else:
			final_view = item["view"]
	_queue = _queue.slice(last + 1)
	if not final_view.is_empty():
		if handler != null:
			handler.call("apply_view", final_view)
		view_applied.emit(final_view)
