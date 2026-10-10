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
# (aus | leise | normal, Standard normal; leise -12.5 dB, normal -4.5 dB); mau_ton wirkt nicht auf sie. Der Abgleich der Töne
# untereinander steckt in den Dateien (karte dezent, dran und sieg am lautesten). Die Stufen liegen 2.5 dB bzw. 10.5 dB unter Mau
# „normal“; im Browser-Client (webclient/ton.js STUFEN_SPIEL) entspricht das 0.75 bzw. 0.3 bei Mau 1.0, damit beide gleich klingen.
# Derselbe Ton wird innerhalb von 40 ms nur einmal gestartet (z. B. mehrere Karten im selben Bild).
#
# Android (Beta 1.4.8): Nach einem Telefonat blieb die App stumm (S24, Android 16). Godot 4.6 gibt auf Android über einen einzigen
# OpenSL-ES-Abspieler aus, der nie neu angelegt wird; bleibt seine Puffer-Kette nach einem Wechsel der Ausgabe stehen, ist bis zum
# Neustart Ruhe, und GDScript kann den Treiber nicht neu starten. Deshalb spielen die Töne auf Android über SoundPool
# (android/build/src/main/java/com/godot/game/SfxPool.java, Dateien als res/raw/sfx_<name>.ogg, kopiert von tools/build.ps1).
# Lautstärken, Stufen, Jubel-Zufall und Sperre bleiben hier; nur das Abspielen wandert nach Java. Ist ein Ton dort (noch) nicht
# geladen, spielt Godot wie bisher. Am PC und in Tests bleibt es bei Godot (native = null; Tests setzen eine Attrappe).
# Beta 1.5.1: Nach PAUSED → RESUMED wird der SoundPool frisch angelegt (Android schaltet nach einem Anruf im Hintergrund die alten
# Abspieler dauerhaft stumm, siehe _notification und SfxPool.rebuild).

const DIR := "res://assets/sfx/"
const NAMES := ["mau", "mau_mau", "karte", "ziehen", "mischen", "flip", "jubel_1", "jubel_2", "fehler", "dran", "schnurren"]
const JUBEL := ["jubel_1", "jubel_2"]       # Ereignis "sieg" spielt zufällig eine der beiden Jubel-Dateien (Nutzerentscheidung 10.10.2026)
const JUBEL_FADE_S := 0.6
const MAU_NAMES := ["mau", "mau_mau"]
const MAU_DB := {"aus": -80.0, "leise": -12.0, "normal": -2.0}
const TON_DB := {"aus": -80.0, "leise": -12.5, "normal": -4.5}
const MAU_TON_STANDARD := "normal"
const TOENE_STANDARD := "normal"           # Spieltöne ab Werk normal (Nutzerentscheidung 10.10.2026; vorher aus, 05.10.2026 „nur Mau-Ton an“)
const TRIM_DB := {}                        # Feinabgleich je Ton in dB (leer: Dateien sind abgeglichen, audio/sfx_README.md; der Browser kennt keinen)
const RETRIGGER_MS := 40

# „Nicht stören“ (Beta 1.5.1): Android setzt die Lautstärke von Spieltönen (USAGE_GAME/Medien) auf 0, wenn der Filter Medien nicht erlaubt
# (S24 des Nutzers: Zeitplan 20–7 Uhr). Die App umgeht das nicht, sie weist nur darauf hin (Toast + Zeile in den Einstellungen).
const DND_ALL := 1
const DND_PRIORITY := 2
const DND_NONE := 3
const DND_ALARMS := 4
const DND_CATEGORY_MEDIA := 64            # NotificationManager.Policy.PRIORITY_CATEGORY_MEDIA
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
var jubel_pick := -1             # für Tests: 0/1 erzwingt eine Jubel-Datei (-1 = Zufall)
var last_file := ""               # für Tests: Dateiname (ohne Endung) des zuletzt gestarteten Tons
var native: Object = null         # Android: SfxPool (JavaClassWrapper); Tests: Attrappe mit play/stopAll/fade/pause/resume
var last_native := false          # für Tests: zuletzt über native gespielt
var _native_playing: Array[Dictionary] = []   # {id, file, until (ms), vol} der über native gestarteten Töne
var _dnd_was_muted := false        # letzter geprüfter Zustand: Hinweis nur, wenn „Nicht stören“ neu stumm schaltet
var dnd_toasts := 0               # für Tests: wie oft der Hinweis gezeigt wurde
var _was_paused := false          # PAUSED gesehen: beim nächsten RESUMED SoundPool neu aufbauen
var rebuilds := 0                 # für Tests: angestoßene Neuaufbauten

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_players()
	preload_all()
	if native == null and OS.get_name() == "Android":
		native = _android_pool()
		dnd_check()

func _android_pool() -> Object:
	# SoundPool anlegen; null = nicht verfügbar (dann spielt Godot).
	if not Engine.has_singleton("AndroidRuntime"):
		return null
	var activity: Variant = Engine.get_singleton("AndroidRuntime").getActivity()
	var java: Variant = JavaClassWrapper.wrap("com.godot.game.SfxPool")
	if activity == null or java == null:
		return null
	var found := int(java.init(activity, ",".join(PackedStringArray(NAMES))))
	print("Töne über SoundPool: %d Dateien" % found)
	return java if found > 0 else null

func _notification(what: int) -> void:
	# Wie Godots eigene Ausgabe: beim Verlassen anhalten, beim Zurückkehren fortsetzen.
	# Neuaufbau (Beta 1.5.1, S24 10.10.2026): Beginnt ein Anruf, während die App im Hintergrund liegt, schaltet Android ihre
	# vorhandenen Abspieler stumm und hebt das nicht wieder auf (auch neue Töne desselben SoundPool bleiben stumm). Deshalb nach
	# PAUSED → RESUMED den Vorrat frisch anlegen (SfxPool.rebuild: alter Pool spielt, bis der neue geladen ist). Nicht bei jedem
	# FOCUS_IN, damit z. B. das Herunterziehen der Benachrichtigungen nichts neu aufbaut.
	if native == null:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		native.pause()
		if what == NOTIFICATION_APPLICATION_PAUSED:
			_was_paused = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		native.resume()
		if what == NOTIFICATION_APPLICATION_RESUMED and _was_paused:
			_was_paused = false
			native.rebuild("zurück in der App")
			rebuilds += 1
		dnd_check()

# --- „Nicht stören“ ---

static func dnd_mutes(filter: int, categories: int) -> bool:
	# Schaltet dieser Unterbrechungsfilter Medien/Spieltöne stumm? filter 1 = alles erlaubt, 2 = nur Priorität (categories = erlaubte
	# Kategorien, -1 = nicht lesbar → vorsichtshalber stumm), 3 = gar nichts, 4 = nur Wecker; 0/unbekannt = nein.
	match filter:
		DND_PRIORITY:
			return categories < 0 or (categories & DND_CATEGORY_MEDIA) == 0
		DND_NONE, DND_ALARMS:
			return true
	return false

func dnd_muted() -> bool:
	# true = Töne sind eingeschaltet, aber „Nicht stören“ macht sie stumm. Ohne Android-Anbindung immer false.
	if native == null or (level("toene") == "aus" and level("mau_ton") == "aus"):
		return false
	var filter := int(native.interruptionFilter())
	var categories := int(native.priorityCategories()) if filter == DND_PRIORITY else -1
	return dnd_mutes(filter, categories)

func dnd_check() -> bool:
	# Beim Start und beim Zurückkehren: Toast „Nicht stören …“, wenn die Töne neu stumm sind (nicht bei jedem Zurückkehren, solange
	# der Zustand gleich bleibt). true = Hinweis gezeigt. Kein Systemdialog, keine Berechtigungsanfrage.
	var muted := dnd_muted()
	var show := muted and not _dnd_was_muted
	_dnd_was_muted = muted
	if show:
		dnd_toasts += 1
		native.toast(dnd_text())
	return show

static func dnd_text() -> String:
	return I18n.t("„Nicht stören“ ist an – die Spieltöne sind stumm.")

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
	if sound_name == "sieg":
		return _play_jubel()
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

func _play_jubel() -> bool:
	# Ereignis "sieg": zufällig eine der beiden Jubel-Dateien; läuft schon einer, startet kein zweiter (Jubel ist ~7 s lang).
	var db := volume_db("sieg")
	if db <= -80.0:
		return false
	for p in _players:
		if p.playing and JUBEL.has(_file_of(p)):
			return false
	for e in _native_active():
		if JUBEL.has(str(e.file)):
			return false
	var pick: String = JUBEL[randi() % JUBEL.size()] if jubel_pick < 0 else JUBEL[jubel_pick % JUBEL.size()]
	if not _start(pick, db):
		return false
	last_played = "sieg"
	return true

func _file_of(p: AudioStreamPlayer) -> String:
	for n in JUBEL:
		if _streams.get(n) != null and p.stream == _streams[n]:
			return n
	return ""

func fade_out_jubel() -> void:
	# Beim Verlassen des Tisches: Jubel sanft ausblenden statt abzuschneiden.
	for p in _players:
		if p.playing and JUBEL.has(_file_of(p)) and is_inside_tree():
			var tw := create_tween()
			tw.tween_property(p, "volume_db", -60.0, JUBEL_FADE_S)
			tw.tween_callback(p.stop)
	for e in _native_active():
		if JUBEL.has(str(e.file)):
			native.fade(int(e.id), float(e.vol), int(JUBEL_FADE_S * 1000.0))
			_native_playing.erase(e)

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
	last_native = _start_native(sound_name, s, db)
	if not last_native:
		var p := _free_player()
		p.stream = s
		p.volume_db = db
		p.play()
	last_played = sound_name
	last_db = db
	last_file = sound_name
	return true

func _start_native(sound_name: String, s: AudioStream, db: float) -> bool:
	# Android: über SoundPool. false = nicht möglich (noch nicht geladen o. ä.), dann spielt Godot.
	if native == null:
		return false
	var vol := clampf(db_to_linear(db), 0.0, 1.0)
	var id := int(native.play(sound_name, vol))
	if id <= 0:
		return false
	var active := _native_active()
	if active.size() >= VOICES:
		_native_playing.erase(active[0])     # SoundPool verdrängt den ältesten Ton selbst (6 Stimmen wie hier)
	_native_playing.append({"id": id, "file": sound_name, "vol": vol, "until": now_ms() + int(ceil(s.get_length() * 1000.0))})
	return true

func _native_active() -> Array[Dictionary]:
	# Über native gestartete Töne, die nach ihrer Länge noch laufen (SoundPool meldet das Ende nicht).
	var now := now_ms()
	var still: Array[Dictionary] = []
	for e in _native_playing:
		if int(e.until) > now:
			still.append(e)
	_native_playing = still
	return still.duplicate()

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
	var n := _native_active().size()
	for p in _players:
		if p.playing:
			n += 1
	return n

func stop_all() -> void:
	for p in _players:
		p.stop()
	if native != null:
		native.stopAll()
	_native_playing.clear()
