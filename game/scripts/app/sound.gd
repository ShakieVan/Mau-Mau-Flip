class_name AppSound
extends Node

# Kurze Töne der App (docs/BETA1_PLAN.md 1 „Töne“, Modul S): play("karte") spielt res://assets/sfx/karte.ogg (sonst .wav). Fehlt die
# Datei, bleibt es still, ohne Fehlermeldung. Mehrere Töne dürfen sich überlagern (kleiner Vorrat an Abspielern); beim Start werden alle
# Töne vorgeladen.
#
# Mau-Töne (AGENTS.md Nr. 20/21): die Aufnahmen des Nutzers, aufbereitet mit tools/make_mau_aufnahmen.sh.
#   - "mau"     → assets/sfx/mau.ogg     („Mao“, jemand ruft „Mau!“)
#   - "mau_mau" → assets/sfx/mau_mau.ogg („Mao-Mao“, jemand wird fertig)
#   - Lautstärke nach Einstellung mau_ton: aus = stumm, leise -12 dB, normal -2 dB. Die Dateien sind schon für den
#     Handy-Lautsprecher ausgesteuert (Spitze -1 dBTP, etwa -12/-10 LUFS); -2 dB lässt Luft, falls ein Spielton gleichzeitig klingt.
#   - Die Töne spielen auf JEDEM Gerät am Tisch (Ereignis „mau“ bzw. „finish“). Doppelte Auslöser fängt der Aufrufer ab
#     (MauSound: 1 s je Platz); hier gibt es keine Gerätesperre mehr.
# Übrige Töne (KI-erzeugt mit MOSS-SoundEffect v2.0, tools/make_sfx_moss.py --spiel, audio/sfx_README.md): Einstellung „toene“
# (aus | leise | normal, Standard aus → still; leise -12.5 dB, normal -4.5 dB); mau_ton wirkt nicht auf sie. Der Abgleich der Töne
# untereinander steckt in den Dateien (karte dezent, dran und sieg am lautesten). Die Stufen liegen 2.5 dB bzw. 10.5 dB unter Mau
# „normal“; im Browser-Client (webclient/ton.js STUFEN_SPIEL) entspricht das 0.75 bzw. 0.3 bei Mau 1.0, damit beide gleich klingen.
# Derselbe Ton wird innerhalb von 40 ms nur einmal gestartet (z. B. mehrere Karten im selben Bild).

const DIR := "res://assets/sfx/"
const NAMES := ["mau", "mau_mau", "karte", "ziehen", "mischen", "flip", "sieg", "fehler", "dran", "schnurren"]
const MAU_NAMES := ["mau", "mau_mau"]
const MAU_DB := {"aus": -80.0, "leise": -12.0, "normal": -2.0}
const TON_DB := {"aus": -80.0, "leise": -12.5, "normal": -4.5}
const MAU_TON_STANDARD := "normal"
const TOENE_STANDARD := "aus"              # Spieltöne sind ab Werk aus (Nutzerwunsch 05.10.2026)
const TRIM_DB := {}                        # Feinabgleich je Ton in dB (leer: Dateien sind abgeglichen, audio/sfx_README.md; der Browser kennt keinen)
const RETRIGGER_MS := 40
const VOICES := 6

var settings: AppSettings         # optional; ohne Einstellungen gelten die Standardwerte
var enabled := true               # z. B. für Tests oder einen künftigen Gesamtschalter
var dir := DIR                    # Ordner der Tondateien (Tests: nicht vorhandener Ordner = alles fehlt)
var now_override := -1            # für Tests: feste Uhr in ms (-1 = Time.get_ticks_msec)
var _streams := {}                # Dateiname ohne Endung → AudioStream oder null (nicht vorhanden)
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_start := {}             # Name → Startzeit (ms) für RETRIGGER_MS
var last_played := ""             # für Tests: zuletzt gestarteter Ton ("" = keiner)
var last_db := 0.0
var last_file := ""               # für Tests: Dateiname (ohne Endung) des zuletzt gestarteten Tons

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_players()
	preload_all()

func _ensure_players() -> void:
	if not _players.is_empty():
		return
	for i in range(VOICES):
		var p := AudioStreamPlayer.new()
		p.name = "Stimme%d" % i
		add_child(p)
		_players.append(p)

# --- Dateien ---

static func path_for(sound_name: String, folder: String = DIR) -> String:
	# Vorhandene Datei für den Namen ("" = keine). Nach dem Export liegen nur die importierten Fassungen im Paket; ResourceLoader
	# kennt sie trotzdem unter dem Originalpfad.
	for ext in ["ogg", "wav"]:
		var path := "%s%s.%s" % [folder, sound_name, ext]
		if ResourceLoader.exists(path):
			return path
	return ""

static func is_mau(sound_name: String) -> bool:
	return MAU_NAMES.has(sound_name)

func stream(sound_name: String) -> AudioStream:
	# Stream zu einem Ton; null = keine Datei. Einmal geladen, bleibt er im Speicher.
	if sound_name == "":
		return null
	if not _streams.has(sound_name):
		var path := path_for(sound_name, dir)
		_streams[sound_name] = load(path) as AudioStream if path != "" else null
	return _streams[sound_name]

func preload_all() -> int:
	# Lädt alle Töne vor (kein Ruckeln beim ersten Abspielen). Ergebnis: Zahl der vorhandenen Dateien.
	var count := 0
	for sound_name in NAMES:
		if stream(sound_name) != null:
			count += 1
	return count

func is_loaded(file: String) -> bool:
	return _streams.get(file) != null

# --- Lautstärke ---

func level(key: String) -> String:
	# Eingestellte Stufe (aus | leise | normal) für "mau_ton" oder "toene"; Ungültiges gilt als Standard.
	var fallback := TOENE_STANDARD if key == "toene" else MAU_TON_STANDARD
	var value := str(settings.get_value(key, fallback)) if settings != null else fallback
	return value if TON_DB.has(value) else fallback

func volume_db(sound_name: String) -> float:
	# Lautstärke in dB; -80 = stumm.
	if is_mau(sound_name):
		return float(MAU_DB[level("mau_ton")])
	var base := float(TON_DB[level("toene")])
	if base <= -80.0:
		return -80.0
	return base + float(TRIM_DB.get(sound_name, 0.0))

func now_ms() -> int:
	return now_override if now_override >= 0 else Time.get_ticks_msec()

# --- Abspielen ---

func play(sound_name: String) -> bool:
	# true = Ton gestartet. Stumm geschaltet, unbekannt oder ohne Datei: false, ohne Fehlermeldung.
	if not enabled:
		return false
	var db := volume_db(sound_name)
	if db <= -80.0:
		return false
	if is_mau(sound_name):
		return _start(sound_name, db)       # keine Sperre: Entprellung je Platz macht MauSound
	var now := now_ms()
	if _last_start.has(sound_name) and now - int(_last_start[sound_name]) < RETRIGGER_MS:
		return false
	if not _start(sound_name, db):
		return false
	_last_start[sound_name] = now
	return true

func play_preview(sound_name := "mau") -> bool:
	# Probehören in den Einstellungen: "mau" oder "mau_mau" in der eingestellten Lautstärke; bei mau_ton „aus“ mit „leise“, denn
	# der Knopf wurde ausdrücklich gedrückt. Unbekannter Name oder fehlende Datei: false.
	if not enabled or not is_mau(sound_name):
		return false
	var mode := level("mau_ton")
	return _start(sound_name, float(MAU_DB["leise" if mode == "aus" else mode]))

func _start(sound_name: String, db: float) -> bool:
	var s := stream(sound_name)
	if s == null:
		return false
	_ensure_players()
	if not is_inside_tree():
		return false
	var p := _free_player()
	p.stream = s
	p.volume_db = db
	p.play()
	last_played = sound_name
	last_db = db
	last_file = sound_name
	return true

func _free_player() -> AudioStreamPlayer:
	# Erst ein freier Abspieler, sonst der am längsten laufende (reihum).
	for i in range(_players.size()):
		var p := _players[(_next + i) % _players.size()]
		if not p.playing:
			_next = (_next + i + 1) % _players.size()
			return p
	var oldest := _players[_next]
	_next = (_next + 1) % _players.size()
	return oldest

func playing_count() -> int:
	var n := 0
	for p in _players:
		if p.playing:
			n += 1
	return n

func stop_all() -> void:
	for p in _players:
		p.stop()
