extends Node
# Autoload „App“ (docs/BETA1_PLAN.md 9, Modul C): Einstellungen, Ton, Updater, ApkShare, Vibration und Bildschirm-an für alle Szenen.
#   App.settings.get_value(key, default) / set_value(key, value)  – speichert sofort (AppSettings, user://einstellungen.json)
#   App.sound.play(name)                                        – "mau", "karte", "ziehen", "mischen", "flip", "sieg", "fehler", "dran"
#   App.vibrate(ms, strength)   App.set_keep_screen_on(on)   App.version()   App.is_android()
#   App.updater (Updater)   App.apk_share (ApkShare)
# Die automatische Update-Prüfung (höchstens einmal am Tag) läuft nur in der Android-App, nie in Tests oder am PC: Sonst fragte jeder
# Testlauf GitHub ab (Limit 60 Abfragen je Stunde und Adresse).

const MOBILE_MAX_FPS := 60

# App-Link „In der App spielen“ (Beta 1.0.2): Beim Start und beim Fortsetzen holt die App einen wartenden Link ab
# (NetAndroid.take_app_link) und hält ihn in app_link, bis das Hauptmenü ihn übernimmt (take_pending_link → JoinScreen.handle_link).
signal app_link_received
var app_link := {}                      # {ok, address, port, error} aus NetAndroid.parse_app_link; {} = keiner

var settings: AppSettings
var sound: AppSound
var updater: Updater
var apk_share: ApkShare
var _keep_on := true
var _logged_status := ""
var _apk_logged := false

func _init() -> void:
	# Schon im Konstruktor, damit andere Autoloads und Testskripte sofort lesen können.
	settings = AppSettings.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("mobile"):
		# Höchstens 60 Bilder/s (Gerätetest 0.1.1, M3): Das S21 lief mit 120 Hz und rechnete jedes Bild doppelt; mit Grenze
		# gleichmäßiger Takt, halbe Last für Prozessor und GPU, weniger Akku und Wärme.
		Engine.max_fps = MOBILE_MAX_FPS
	sound = AppSound.new()
	sound.name = "Sound"
	sound.settings = settings
	add_child(sound)
	updater = Updater.new()
	updater.name = "Updater"
	add_child(updater)
	updater.setup(settings)
	apk_share = ApkShare.new()
	apk_share.name = "ApkShare"
	add_child(apk_share)
	apk_share.setup()
	_keep_on = bool(ProjectSettings.get_setting("display/window/energy_saving/keep_screen_on", true))
	print("Mau-Mau Flip %s (%s)" % [version(), OS.get_name()])
	check_app_link()
	if is_android():
		updater.changed.connect(_log_update)
		updater.check(false)
		_log_android()

func _log_android() -> void:
	# Ins Android-Log (adb logcat -s godot): Netzlage und die Java-Helfer im fertigen Paket (NetHelper, Updater, ApkShare). Die Prüfsumme
	# der eigenen APK wird dabei einmal je installierter Version berechnet und gemerkt (Angebot für /apk und „App teilen“).
	for line in NetAndroid.summary(NetAndroid.state()):
		print("Netz: ", line)
	print("Java-Helfer: NetHelper %s, Updater %s (Installieren erlaubt: %s), ApkShare %s" % [NetAndroid.available(),
		not updater.android().is_empty(), updater.can_install(), apk_share.available()])
	apk_share.changed.connect(_log_apk)
	apk_share.prepare_hash()
	_log_apk()

func _log_apk() -> void:
	if apk_share.sha256 != "" and not _apk_logged:
		_apk_logged = true
		print("Eigene APK: %s, %d Bytes, SHA-256 %s" % [apk_share.share_name(), apk_share.size_bytes(), apk_share.sha256])

func selftest() -> bool:
	# Gerätetest der Java-Helfer samt APK-Kopie für /apk (Ergebnis im Log). Für ein verstecktes Entwicklermenü (Modul F) gedacht;
	# Startparameter wirken bei Release-APKs nicht (Godot verwirft sie für exportierte Activities).
	var problems: Array[String] = []
	for line in NetAndroid.summary(NetAndroid.state()):
		print("Selbsttest Netz: ", line)
	if not NetAndroid.available():
		problems.append("NetHelper nicht erreichbar")
	print("Selbsttest Updater: installierte Version %s, Installieren erlaubt: %s" % [version(), updater.can_install()])
	if updater.android().is_empty():
		problems.append("Updater.java nicht erreichbar")
	print("Selbsttest ApkShare: verfügbar %s, %d Bytes, Version %s" % [apk_share.available(), apk_share.size_bytes(), apk_share.version()])
	var started := Time.get_ticks_msec()
	var info := apk_share.server_info()
	while info.is_empty() and apk_share.available() and Time.get_ticks_msec() - started < 60000:
		await get_tree().create_timer(0.25).timeout
		info = apk_share.server_info()
	if info.is_empty():
		problems.append("ApkShare lieferte keine Datei (%s)" % apk_share.status)
	else:
		var f := FileAccess.open(str(info.path), FileAccess.READ)
		var readable := f != null and f.get_length() == int(info.size)
		if f != null:
			f.close()
		print("Selbsttest ApkShare: %s, %d Bytes, SHA-256 %s, lesbar %s, %d ms" % [info.name, int(info.size), info.sha256, readable, Time.get_ticks_msec() - started])
		if not readable:
			problems.append("APK-Kopie nicht lesbar")
		apk_share.release_file()
	print("Selbsttest: " + ("OK" if problems.is_empty() else "FEHLER – " + "; ".join(problems)))
	return problems.is_empty()

func _log_update() -> void:
	# Ins Android-Log (adb logcat -s godot): Ergebnis der Update-Prüfung.
	if updater.status != _logged_status:
		_logged_status = updater.status
		print("Updater: %s (Kanal %s)" % [updater.status, "Beta" if updater.beta() else "Release"])

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		check_app_link()


func check_app_link() -> bool:
	# Wartenden App-Link abholen; true = einer kam (Signal app_link_received).
	var link := NetAndroid.take_app_link()
	if link == "":
		return false
	app_link = NetAndroid.parse_app_link(link)
	print("App-Link: %s → %s" % [link, "ok" if bool(app_link.ok) else "abgewiesen"])
	app_link_received.emit()
	return true


func take_pending_link() -> Dictionary:
	var l := app_link
	app_link = {}
	return l

func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))

func is_android() -> bool:
	return OS.get_name() == "Android"

func vibrate(ms: int, strength: float = -1.0) -> void:
	# Kurzes Rütteln (nur Handy, nur mit Einstellung „vibration“). strength 0..1, -1 = Gerätestandard.
	if not bool(settings.get_value("vibration", true)) or ms <= 0:
		return
	if is_android() or OS.has_feature("mobile"):
		Input.vibrate_handheld(ms, clampf(strength, 0.0, 1.0) if strength >= 0.0 else -1.0)

func set_keep_screen_on(on: bool) -> void:
	# Bildschirm bleibt an (z. B. während einer Partie oder in der Lobby des Gastgebers).
	_keep_on = on
	DisplayServer.screen_set_keep_on(on)

func keep_screen_on() -> bool:
	return _keep_on
