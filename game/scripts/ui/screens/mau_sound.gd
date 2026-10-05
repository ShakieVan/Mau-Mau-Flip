class_name MauSound
extends RefCounted
# Mau-Töne am Tisch (AGENTS.md Nr. 20/21): Jedes Gerät spielt beim Ereignis „mau“ die Aufnahme „Mao“ (App.sound "mau") und
# beim Fertigwerden („finish“) „Mao-Mao“ (App.sound "mau_mau") – egal, welcher Platz ruft. Ausnahme: Mau-Ton steht auf „aus“
# (dann bleibt es still, die Sprechblase erscheint trotzdem). Der eigene Knopfdruck spielt nichts; der Ton kommt einmal, aus dem
# Ereignis. Entprellung: derselbe Ton für denselben Platz höchstens einmal je Sekunde (z. B. Wiederholung nach Wiederverbinden).
# Lautstärke und Dateien regelt AppSound (mau_ton: aus / leise / normal).

const DEBOUNCE_MS := 1000
const PROBE_MS := 800

static var last_ms := -100000       # Zeitpunkt des letzten gestarteten Mau-Tons (ms)
static var last_path := ""          # für Tests: zuletzt gespielte Datei
static var requests: Array = []     # für Tests: angeforderte Töne [{sound, seat, played}] (höchstens 32)
static var _last := {}              # "<ton>:<platz>" → ms
static var _probe_ms := -100000


# Ton für einen Platz anfordern (Tischregie). sound_name: "mau" oder "mau_mau". true = Ton gestartet; false = entprellt,
# Mau-Ton aus, Datei fehlt oder keine App.
static func play(now_ms := -1, seat := -1, sound_name := "mau") -> bool:
	var now := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	var key := "%s:%d" % [sound_name, seat]
	if _last.has(key) and now - int(_last[key]) < DEBOUNCE_MS:
		_log(sound_name, seat, false)
		return false
	_last[key] = now
	var ok := _app_play(sound_name, false)
	_log(sound_name, seat, ok)
	if ok:
		last_ms = now
	return ok


# Probehören in den Einstellungen: "mau" oder "mau_mau"; bei Mau-Ton „aus“ leise. Kurze eigene Sperre gegen Dauerdrücken.
static func probe(sound_name := "mau") -> bool:
	var now := Time.get_ticks_msec()
	if now - _probe_ms < PROBE_MS:
		return false
	_probe_ms = now
	return _app_play(sound_name, true)


static func level() -> String:
	var v := str(UiApp.setting("mau_ton", "normal"))
	return v if AppSettings.MAU_TON.has(v) else "normal"


static func _app_play(sound_name: String, preview: bool) -> bool:
	var app := UiApp.app()
	var s: Variant = app.get("sound") if app != null else null
	if not (s is Object) or not (s as Object).has_method("play"):
		return false
	var ok := bool((s as Object).call("play_preview" if preview else "play", sound_name))
	if ok:
		last_path = AppSound.path_for(sound_name)
	return ok


static func _log(sound_name: String, seat: int, played: bool) -> void:
	requests.append({"sound": sound_name, "seat": seat, "played": played})
	if requests.size() > 32:
		requests.pop_front()


# Zustand zurücksetzen (Tests, neue Partie)
static func reset() -> void:
	last_ms = -100000
	last_path = ""
	requests.clear()
	_last.clear()
	_probe_ms = -100000
