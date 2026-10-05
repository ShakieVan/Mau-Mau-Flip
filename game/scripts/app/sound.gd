class_name AppSound
extends Node

# Kurze Töne der App (docs/BETA1_PLAN.md 1 „Töne“): play("karte") spielt res://assets/sfx/karte.ogg (sonst .wav). Fehlt die Datei,
# bleibt es still – Modul B liefert die Töne nach und nach. Mehrere Töne dürfen sich überlagern (kleiner Vorrat an Abspielern).
# Lautstärke: „mau“ nach Einstellung mau_ton (aus = stumm, leise -14 dB, normal -6 dB), alle anderen -8 dB.
# Den Mau-Ton spielt nur das Gerät, auf dem „Mau!“ gedrückt wurde (Katzen-Leitplanke, Plan 5) – das entscheidet der Aufrufer.

const DIR := "res://assets/sfx/"
const NAMES := ["mau", "karte", "ziehen", "mischen", "flip", "sieg", "fehler", "dran"]
const MAU_DB := {"aus": -80.0, "leise": -14.0, "normal": -6.0}
const OTHER_DB := -8.0
const VOICES := 6

var settings: AppSettings         # optional; ohne Einstellungen gilt mau_ton „normal“
var enabled := true               # z. B. für Tests oder einen künftigen Gesamtschalter
var _streams := {}                # Name → AudioStream oder null (nicht vorhanden)
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var last_played := ""             # für Tests: zuletzt gestarteter Ton ("" = keiner)
var last_db := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_players()

func _ensure_players() -> void:
	if not _players.is_empty():
		return
	for i in range(VOICES):
		var p := AudioStreamPlayer.new()
		p.name = "Stimme%d" % i
		add_child(p)
		_players.append(p)

static func path_for(sound_name: String) -> String:
	# Vorhandene Datei für den Namen ("" = keine). Nach dem Export liegen nur die importierten Fassungen im Paket; ResourceLoader
	# kennt sie trotzdem unter dem Originalpfad.
	for ext in ["ogg", "wav"]:
		var path := "%s%s.%s" % [DIR, sound_name, ext]
		if ResourceLoader.exists(path):
			return path
	return ""

func stream(sound_name: String) -> AudioStream:
	if not _streams.has(sound_name):
		var path := path_for(sound_name)
		_streams[sound_name] = load(path) as AudioStream if path != "" else null
	return _streams[sound_name]

func volume_db(sound_name: String) -> float:
	# Lautstärke in dB; -80 = stumm.
	if sound_name == "mau":
		var mode := str(settings.get_value("mau_ton", "normal")) if settings != null else "normal"
		return float(MAU_DB.get(mode, MAU_DB.normal))
	return OTHER_DB

func play(sound_name: String) -> bool:
	# true = Ton gestartet. Stumm geschaltet, unbekannt oder ohne Datei: false, ohne Fehlermeldung.
	if not enabled:
		return false
	var db := volume_db(sound_name)
	if db <= -80.0:
		return false
	var s := stream(sound_name)
	if s == null:
		return false
	_ensure_players()
	if not is_inside_tree():
		return false
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = s
	p.volume_db = db
	p.play()
	last_played = sound_name
	last_db = db
	return true

func stop_all() -> void:
	for p in _players:
		p.stop()
