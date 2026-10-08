class_name Updater
extends Node

# Update-Funktion (übernommen aus Draw2Race 1.0.1, docs/BETA1_PLAN.md 9): neuestes GitHub-Release prüfen, APK laden, Größe und
# SHA-256 aus der GitHub-API prüfen, dann Paket/Version/Signatur (Java: android/build/.../Updater.java) und den System-Installer
# starten. Automatische Prüfung höchstens einmal am Tag (App beim Start, nur Android); Download nur auf Wunsch.
# Gemerkt wird in den Einstellungen: update_last_check (ms), update_release (Roh-JSON des angebotenen Releases).

signal changed

const REPOSITORY := "ShakieVan/Mau-Mau-Flip"
const ENDPOINT := "https://api.github.com/repos/%s/releases/latest" % REPOSITORY
# Beta-Kanal: Testversionen liegen in einem eigenen Repo. Im Beta-Kanal werden beide Quellen abgefragt; die höchste Version
# gewinnt – ein neueres reguläres Release geht also nicht verloren.
const BETA_REPOSITORY := "ShakieVan/Mau-Mau-Flip-Beta"
const ENDPOINT_BETA := "https://api.github.com/repos/%s/releases?per_page=20" % BETA_REPOSITORY
const ASSET := "MauMauFlip-%s.apk"
const MAX_APK_BYTES := 512 * 1024 * 1024
const DAY_MS := 24 * 60 * 60 * 1000
const DIR := "user://updates"
const LIMIT_TEXT := "GitHub-Limit erreicht – später erneut versuchen"

var settings: AppSettings
var status := "Noch nicht geprüft."
var release := {}          # version, notes, size, sha256, url, beta, raw
var busy := false
var percent := -1
var apk_ready := false
var http: HTTPRequest
var hash_thread: Thread
var pending: Array = []    # noch abzufragende Endpunkte dieser Suche
var best := {}             # bestes gefundenes Release dieser Suche
var answered := false      # mindestens eine Quelle hat geantwortet
var failed := false        # mindestens eine Quelle hat nicht geantwortet (kein Netz, GitHub-Limit, Serverfehler)
var failure := ""          # Klartext zum Fehlschlag (failure_text)
var download_dir := DIR    # Ablage der Downloads (Tests: eigener Ordner)

static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))

static func asset_name(version: String) -> String:
	return ASSET % version

static func valid_version(text: String) -> bool:
	var parts := text.split(".")
	if parts.size() != 3:
		return false
	for p in parts:
		if not p.is_valid_int() or int(p) < 0 or p.begins_with("+") or p.begins_with("-"):
			return false
	return true

static func compare_versions(a: String, b: String) -> int:
	# Numerisch je Stelle (0.10.0 > 0.9.9); 1 = a neuer, -1 = b neuer, 0 = gleich.
	var x := a.split(".")
	var y := b.split(".")
	for i in range(3):
		var xi := int(x[i]) if i < x.size() else 0
		var yi := int(y[i]) if i < y.size() else 0
		if xi != yi:
			return 1 if xi > yi else -1
	return 0

static func version_code(version: String) -> int:
	# Android-Versionsnummer wie tools/build.ps1: X.Y.Z → X·1 000 000 + Y·1 000 + Z (0.1.1 → 1001); -1 = ungültig.
	if not valid_version(version):
		return -1
	var p := version.split(".")
	if int(p[1]) > 999 or int(p[2]) > 999:
		return -1
	return int(p[0]) * 1000000 + int(p[1]) * 1000 + int(p[2])

static func default_beta(version: String) -> bool:
	# Beta-Kanal standardmäßig an, wenn die installierte Version keine reguläre ist (reguläre Releases enden auf .0).
	return not version.ends_with(".0")

static func parse(json_text: String, allow_beta := false) -> Dictionary:
	# Nur fertige Releases mit genau einer passenden APK, Größe und SHA-256-Angabe; sonst {}.
	# Vorabversionen nur mit allow_beta. Eine Liste (Beta-Kanal) liefert das Release mit der höchsten Version.
	var json := JSON.new()
	if json_text.strip_edges() == "" or json.parse(json_text) != OK:
		return {}
	if json.data is Array:
		var top := {}
		for entry in json.data:
			var found := parse_release(entry, allow_beta)
			if not found.is_empty() and (top.is_empty() or compare_versions(found.version, top.version) > 0):
				top = found
		return top
	return parse_release(json.data, allow_beta)

static func parse_release(data: Variant, allow_beta := false) -> Dictionary:
	# Reguläre Releases nur aus REPOSITORY; Vorabversionen und alles aus BETA_REPOSITORY nur mit allow_beta.
	if not data is Dictionary or bool(data.get("draft", true)) or (bool(data.get("prerelease", true)) and not allow_beta):
		return {}
	var tag := str(data.get("tag_name", ""))
	if not tag.begins_with("v") or not valid_version(tag.substr(1)):
		return {}
	var version := tag.substr(1)
	var name := asset_name(version)
	var assets: Variant = data.get("assets", [])
	if not assets is Array:
		return {}
	var matches: Array = (assets as Array).filter(func(a: Variant) -> bool: return a is Dictionary and a.get("name") == name)
	if matches.size() != 1:
		return {}
	var asset: Dictionary = matches[0]
	var size := int(asset.get("size", 0))
	var digest := str(asset.get("digest", ""))
	var url := str(asset.get("browser_download_url", ""))
	if size <= 0 or size > MAX_APK_BYTES or not digest.begins_with("sha256:") or digest.length() != 71 or not digest.substr(7).is_valid_hex_number():
		return {}
	var from_beta := url == "https://github.com/%s/releases/download/%s/%s" % [BETA_REPOSITORY, tag, name]
	if url != "https://github.com/%s/releases/download/%s/%s" % [REPOSITORY, tag, name] and not (from_beta and allow_beta):
		return {}
	return {"version": version, "notes": str(data.get("body", "")).left(6000), "size": size,
		"sha256": digest.substr(7).to_lower(), "url": url, "beta": from_beta or bool(data.get("prerelease", false)),
		"raw": JSON.stringify(data)}

func beta() -> bool:
	return bool(settings.get_value("beta", default_beta(current_version()))) if settings != null else default_beta(current_version())

func set_beta(on: bool) -> void:
	# Kanal gewechselt: zwischengespeichertes Ergebnis verwerfen und sofort neu suchen.
	settings.set_value("beta", on)
	settings.reset("update_release")
	release = {}
	apk_ready = false
	check(true)

# HTTPRequest.timeout begrenzt die GESAMTE Anfrage, nicht die Pause zwischen zwei Paketen. Für die Versionsabfrage (klein) passt
# das; ein Download liefe damit nach 30 s ab, egal wie gut die Verbindung ist. Beim Download ist die Grenze daher aus, stattdessen
# bricht ein Wächter erst ab, wenn STALL_TIMEOUT Sekunden lang kein Byte mehr ankommt.
const NO_CONNECTION := "Keine Verbindung zu GitHub. Prüfe das Internet – auch VPN- oder Firewall-Apps können es sperren."
const CHECK_TIMEOUT := 12.0   # je Quelle; danach Klartext statt langem Warten (Nutzerbefund 07.10.2026)
const STALL_TIMEOUT := 30.0
var downloading := false
var last_bytes := -1
var stall := 0.0

func setup(app_settings: AppSettings) -> void:
	settings = app_settings
	http = HTTPRequest.new()
	http.use_threads = true
	http.timeout = CHECK_TIMEOUT
	add_child(http)
	var cached := parse(str(settings.get_value("update_release", "")), beta())
	if not cached.is_empty() and compare_versions(cached.version, current_version()) > 0:
		release = cached
		status = "Neue Version verfügbar."
		apk_ready = FileAccess.file_exists(apk_path())
	elif int(settings.get_value("update_last_check", 0)) > 0:
		# Die automatische Prüfung läuft nur einmal am Tag: Bis zur nächsten zeigt der Status, wann zuletzt erfolgreich geprüft wurde.
		status = I18n.t("Zuletzt geprüft: %s.") % local_time_text(int(settings.get_value("update_last_check", 0)) / 1000)
	# Aufräumen beim Start: Reste abgebrochener Downloads und schon installierte APKs – nur die APK des noch offenen Updates bleibt.
	# Nach einem erfolgreichen Update ist das gemerkte Release nicht mehr neuer: Dann verschwindet die geladene APK.
	prune()

static func local_time_text(unix: int) -> String:
	# „04.10.2026, 21:53“ in der Ortszeit des Geräts.
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var d := Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	return "%02d.%02d.%04d, %02d:%02d" % [d.day, d.month, d.year, d.hour, d.minute]

func available() -> bool:
	return not release.is_empty()

func publish(text: String) -> void:
	status = text
	changed.emit()

func check(manual: bool) -> void:
	if busy or settings == null:
		return
	# Der Zeitpunkt der letzten Prüfung wird erst nach einer vollständigen Antwort gespeichert (finish_check): Ein Fehlschlag (kein
	# Netz, GitHub-Limit) sperrte die automatische Prüfung sonst für 24 h.
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	if not manual and now - int(settings.get_value("update_last_check", 0)) < DAY_MS:
		return
	busy = true
	percent = -1
	publish("Suche nach Updates …")
	pending = [ENDPOINT_BETA, ENDPOINT] if beta() else [ENDPOINT]
	best = {}
	answered = false
	failed = false
	failure = ""
	NetAddresses.suspend_for_internet()
	request_next()

func request_next() -> void:
	# Quellen nacheinander abfragen (ein HTTPRequest), danach auswerten.
	if pending.is_empty():
		finish_check()
		return
	var headers := PackedStringArray(["User-Agent: MauMauFlip/%s" % current_version(),
		"Accept: application/vnd.github+json", "X-GitHub-Api-Version: 2022-11-28"])
	http.download_file = ""
	http.timeout = CHECK_TIMEOUT
	http.request_completed.connect(_checked, CONNECT_ONE_SHOT)
	if http.request(str(pending.pop_front()), headers) != OK:
		http.request_completed.disconnect(_checked)
		failed = true
		if failure == "":
			failure = NO_CONNECTION
		request_next()

func _checked(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	# 404: Repo ohne Release (z. B. noch nichts veröffentlicht) – eine gültige Antwort, kein Fehlschlag.
	if result == HTTPRequest.RESULT_SUCCESS and (code == 200 or code == 404):
		answered = true
	else:
		failed = true
		# Das GitHub-Limit hat Vorrang: Es betrifft alle Quellen desselben Netzes und erklärt den Fehlschlag am besten.
		if failure == "" or rate_limited(code):
			failure = failure_text(result, code, headers, int(Time.get_unix_time_from_system()))
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and body.size() <= 1024 * 1024:
		var found := parse(body.get_string_from_utf8(), beta())
		if not found.is_empty() and (best.is_empty() or compare_versions(found.version, best.version) > 0):
			best = found
	request_next()

func finish_check() -> void:
	# Eine neuere Version wird angeboten, auch wenn eine zweite Quelle (Beta-Kanal) nicht geantwortet hat. Ohne neuere Version zählt
	# ein Fehlschlag: Dann ist „Du hast die neueste Version.“ nicht sicher, und der Prüfzeitpunkt bleibt offen (nächster Start fragt neu).
	busy = false
	NetAddresses.resume_after_internet()
	var newer := not best.is_empty() and compare_versions(best.version, current_version()) > 0
	var store := {}
	if not failed:
		store["update_last_check"] = int(Time.get_unix_time_from_system() * 1000.0)
	if not best.is_empty() and (newer or not failed):
		store["update_release"] = str(best.raw)
	if not store.is_empty():
		settings.set_values(store)
	if newer:
		release = best
		apk_ready = FileAccess.file_exists(apk_path())
		publish("Neue Version verfügbar.")
	elif failed:
		publish(failure if failure != "" else I18n.t(NO_CONNECTION))
	elif best.is_empty():
		release = {}
		publish("Noch kein passendes Release veröffentlicht.")
	else:
		release = {}
		publish("Du hast die neueste Version.")

static func rate_limited(code: int) -> bool:
	# GitHub beantwortet zu viele Anfragen ohne Anmeldung mit 403 (Hauptlimit: 60 je Stunde und IP-Adresse) oder 429.
	return code == 403 or code == 429

static func failure_text(result: int, code: int, headers: PackedStringArray, now_unix: int) -> String:
	# Klartext für eine gescheiterte Versionsabfrage. Im geteilten WLAN (Urlaub, Hotel) teilen sich alle Geräte eine öffentliche Adresse
	# und damit das Limit von 60 Abfragen je Stunde – das soll nicht als „Keine Verbindung.“ erscheinen. Die Antwort nennt in
	# x-ratelimit-reset (Unix-Zeit) bzw. retry-after (Sekunden), wann es wieder geht.
	if result != HTTPRequest.RESULT_SUCCESS:
		return NO_CONNECTION
	if not rate_limited(code):
		return I18n.t("GitHub antwortet gerade nicht (Fehler %d). Bitte später erneut versuchen.") % code
	var retry := -1
	var remaining := ""
	var reset := -1
	for line in headers:
		var colon := line.find(":")
		if colon < 0:
			continue
		var key := line.left(colon).strip_edges().to_lower()
		var value := line.substr(colon + 1).strip_edges()
		if key == "retry-after" and value.is_valid_int():
			retry = int(value)
		elif key == "x-ratelimit-remaining":
			remaining = value
		elif key == "x-ratelimit-reset" and value.is_valid_int():
			reset = int(value)
	var wait := retry
	if wait < 0 and remaining == "0" and reset > 0:
		wait = maxi(0, reset - now_unix)
	if wait < 0:
		return I18n.t(LIMIT_TEXT) + "."
	var minutes := maxi(1, ceili(wait / 60.0))
	return I18n.t(LIMIT_TEXT) + " " + (I18n.t("(in etwa 1 Minute).") if minutes == 1 else I18n.t("(in etwa %d Minuten).") % minutes)

static func release_page(rel: Dictionary, beta_channel: bool) -> String:
	# Ausweg ohne den Updater (Knopf „Im Browser herunterladen“): die GitHub-Seite des angebotenen Releases, sonst die Release-Liste
	# des Kanals. Dort lässt sich die APK auch dann laden und installieren, wenn der Updater selbst defekt ist.
	var url := str(rel.get("url", ""))
	var marker := "/releases/download/"
	if url.begins_with("https://github.com/") and url.contains(marker):
		return url.get_base_dir().replace(marker, "/releases/tag/")
	if beta_channel:
		return "https://github.com/%s/releases" % BETA_REPOSITORY
	return "https://github.com/%s/releases/latest" % REPOSITORY

func open_release_page() -> void:
	OS.shell_open(release_page(release, beta()))

func apk_path() -> String:
	return "%s/%s.apk" % [download_dir, release.get("sha256", "none")]

func download() -> void:
	if busy or release.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(download_dir)
	prune()
	busy = true
	percent = 0
	publish("Lade herunter …")
	http.download_file = apk_path() + ".part"
	http.timeout = 0.0
	downloading = true
	last_bytes = -1
	stall = 0.0
	http.request_completed.connect(_downloaded, CONNECT_ONE_SHOT)
	var headers := PackedStringArray(["User-Agent: MauMauFlip/%s" % current_version(), "Accept: application/octet-stream"])
	NetAddresses.suspend_for_internet()
	if http.request(str(release.url), headers) != OK:
		NetAddresses.resume_after_internet()
		http.request_completed.disconnect(_downloaded)
		busy = false
		downloading = false
		publish("Download fehlgeschlagen.")

func _process(dt: float) -> void:
	if downloading and http != null:
		# Wächter: solange Bytes ankommen, läuft der Download weiter; erst eine Pause von STALL_TIMEOUT bricht ab.
		var bytes := http.get_downloaded_bytes()
		if bytes != last_bytes:
			last_bytes = bytes
			stall = 0.0
		else:
			stall += dt
			if stall > STALL_TIMEOUT:
				http.cancel_request()
				downloading = false
				http.request_completed.disconnect(_downloaded)
				_downloaded(HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray())
				return
	if busy and http != null and http.get_http_client_status() == HTTPClient.STATUS_BODY and not release.is_empty():
		var p := int(http.get_downloaded_bytes() * 100 / maxi(1, int(release.size)))
		if p != percent:
			percent = p
			changed.emit()

func _downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	downloading = false
	NetAddresses.resume_after_internet()
	var part := apk_path() + ".part"
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		busy = false
		DirAccess.remove_absolute(part)
		publish("Download fehlgeschlagen.")
		return
	publish("Prüfe Download …")
	percent = -1
	hash_thread = Thread.new()
	hash_thread.start(_hash_file.bind(part))

func _hash_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	var ok := file != null and file.get_length() == int(release.size)
	if ok:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		while file.get_position() < file.get_length():
			ctx.update(file.get_buffer(1024 * 1024))
		ok = ctx.finish().hex_encode() == str(release.sha256)
	if file != null:
		file.close()
	call_deferred("_hashed", path, ok)

func _hashed(path: String, ok: bool) -> void:
	hash_thread.wait_to_finish()
	busy = false
	if not ok:
		DirAccess.remove_absolute(path)
		publish("Download beschädigt (Prüfsumme falsch) – bitte erneut laden.")
		return
	DirAccess.rename_absolute(path, apk_path())
	apk_ready = true
	publish("Bereit zur Installation.")

func _exit_tree() -> void:
	if hash_thread != null and hash_thread.is_started():
		hash_thread.wait_to_finish()

# --- Android ---
func android() -> Array:
	# [Java-Klasse, Activity] oder [] außerhalb von Android.
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return []
	var activity: Variant = Engine.get_singleton("AndroidRuntime").getActivity()
	var java: Variant = JavaClassWrapper.wrap("com.godot.game.Updater")
	return [java, activity] if java != null and activity != null else []

func can_install() -> bool:
	var a := android()
	return not a.is_empty() and bool(a[0].canInstall(a[1]))

func open_permission() -> void:
	var a := android()
	if not a.is_empty():
		a[0].openInstallPermission(a[1])

func install() -> void:
	var problem := install_file(apk_path(), str(release.version))
	apk_ready = FileAccess.file_exists(apk_path())
	publish("Installer gestartet." if problem == "" else java_text(problem))

func install_file(file: String, version: String) -> String:
	# Installationsberechtigung, dann Paket, höhere Versionsnummer, angekündigte Version und identische Signatur (Updater.java), dann
	# der System-Installer. "" = Installer gestartet, sonst deutscher Grund; eine abgelehnte Datei wird gelöscht.
	var a := android()
	if a.is_empty():
		return I18n.t("Installation nur auf dem Handy möglich.")
	if not can_install():
		open_permission()
		return I18n.t("Bitte „Apps installieren“ für Mau-Mau Flip erlauben (Android 7: „Unbekannte Herkunft“) und erneut tippen.")
	var path := ProjectSettings.globalize_path(file)
	var problem := str(a[0].verify(a[1], path, version))
	if problem != "":
		DirAccess.remove_absolute(file)
		return I18n.t("Update abgelehnt: %s") % java_text(problem)
	return str(a[0].install(a[1], path))

func prune() -> void:
	# Alte Downloads entfernen (nur die APK des offenen Updates behalten).
	var dir := DirAccess.open(download_dir)
	if dir == null:
		return
	for name in dir.get_files():
		if download_dir + "/" + name != apk_path():
			dir.remove(name)

static func java_text(s: String) -> String:
	# Meldungen der Java-Helfer kommen deutsch; „Vorspann: Einzelheit“ wird nur im Vorspann übersetzt.
	var full := I18n.t(s)
	if full != s:
		return full
	var i := s.find(": ")
	if i > 0:
		return I18n.t(s.left(i)) + ": " + s.substr(i + 2)
	return s
