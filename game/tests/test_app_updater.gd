extends SceneTree
# Modul C: Update-Funktion ohne Netz – Versionsvergleich, versionCode-Formel (wie tools/build.ps1), strenge Release-Prüfung
# (Release/Beta, Asset-Name, Digest), GitHub-Limit (403/429), Prüfzeitpunkt erst nach Erfolg, Aufräumen geladener APKs.

var ok := 0
var failed := 0

func check(cond: bool, text: String) -> void:
	if cond:
		ok += 1
	else:
		failed += 1
		print("FAIL: ", text)

func release(version: String, repo := Updater.REPOSITORY, prerelease := false) -> Dictionary:
	var name := "MauMauFlip-%s.apk" % version
	return {"draft": false, "prerelease": prerelease, "tag_name": "v" + version, "body": "Neu in " + version,
		"assets": [{"name": name, "size": 1234, "digest": "sha256:" + "ab".repeat(32),
			"browser_download_url": "https://github.com/%s/releases/download/v%s/%s" % [repo, version, name]}]}

func _init() -> void:
	# Versionen: numerisch je Stelle, nur X.Y.Z aus Ziffern.
	check(Updater.compare_versions("0.10.0", "0.9.9") > 0 and Updater.compare_versions("1.2.3", "1.2.3") == 0
		and Updater.compare_versions("0.1.1", "0.2.0") < 0 and Updater.compare_versions("1.0.0", "0.99.99") > 0, "Versionen numerisch verglichen")
	check(Updater.valid_version("0.1.1") and not Updater.valid_version("0.1") and not Updater.valid_version("0.1.1-beta")
		and not Updater.valid_version("v0.1.1") and not Updater.valid_version("0.1.x") and not Updater.valid_version("0.+1.1"), "Versionsschema X.Y.Z")
	# versionCode: X·1 000 000 + Y·1 000 + Z; das Exportprofil trägt genau diesen Wert (tools/build.ps1 rechnet gleich).
	check(Updater.version_code("0.1.1") == 1001 and Updater.version_code("1.2.3") == 1002003 and Updater.version_code("1.0.0") == 1000000
		and Updater.version_code("0.1.1000") == -1 and Updater.version_code("x") == -1, "versionCode-Formel")
	check(Updater.version_code("0.2.0") > Updater.version_code("0.1.999") and Updater.version_code("1.0.0") > Updater.version_code("0.999.999"),
		"versionCode steigt mit jeder höheren Version")
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	var version := Updater.current_version()
	check(presets.contains("version/name=\"%s\"" % version) and presets.contains("version/code=%d\n" % Updater.version_code(version)),
		"Exportprofil: version/name und version/code passen zu project.godot (%s → %d)" % [version, Updater.version_code(version)])
	check(presets.contains("package/unique_name=\"de.maumauflip.game\"") and presets.contains("permissions/vibrate=true")
		and presets.contains("permissions/wake_lock=true") and presets.contains("exclude_filter=\"tests/*\""), "Exportprofil: Paket, Berechtigungen, Tests ausgeschlossen")
	# Beta-Kanal standardmäßig an, wenn die Version nicht auf .0 endet.
	check(Updater.default_beta("0.1.1") and not Updater.default_beta("0.2.0") and not Updater.default_beta("1.0.0") and Updater.default_beta("1.0.10"),
		"Beta-Kanal: Standard nach Versionsende")
	check(Updater.asset_name("0.1.1") == "MauMauFlip-0.1.1.apk", "Asset-Name MauMauFlip-X.Y.Z.apk")

	# Release-Prüfung
	var good := release("0.3.0")
	var parsed := Updater.parse(JSON.stringify(good))
	check(parsed.get("version") == "0.3.0" and parsed.get("sha256") == "ab".repeat(32) and parsed.get("size") == 1234 and parsed.get("beta") == false,
		"gültiges Release erkannt")
	var bad_url := good.duplicate(true)
	bad_url.assets[0].browser_download_url = "https://evil.example/MauMauFlip-0.3.0.apk"
	var draft := good.duplicate(true)
	draft.draft = true
	var no_digest := good.duplicate(true)
	no_digest.assets[0].erase("digest")
	var short_digest := good.duplicate(true)
	short_digest.assets[0].digest = "sha256:abcd"
	var not_hex := good.duplicate(true)
	not_hex.assets[0].digest = "sha256:" + "zz".repeat(32)
	var md5 := good.duplicate(true)
	md5.assets[0].digest = "md5:" + "ab".repeat(33)
	check(Updater.parse(JSON.stringify(bad_url)).is_empty() and Updater.parse(JSON.stringify(draft)).is_empty()
		and Updater.parse(JSON.stringify(no_digest)).is_empty(), "fremde URL, Entwurf oder fehlende Prüfsumme abgelehnt")
	check(Updater.parse(JSON.stringify(short_digest)).is_empty() and Updater.parse(JSON.stringify(not_hex)).is_empty()
		and Updater.parse(JSON.stringify(md5)).is_empty(), "Digest: nur sha256 mit 64 Hex-Zeichen")
	var wrong_name := good.duplicate(true)
	wrong_name.assets[0].name = "Draw2Race-0.3.0.apk"
	wrong_name.assets[0].browser_download_url = "https://github.com/ShakieVan/Mau-Mau-Flip/releases/download/v0.3.0/Draw2Race-0.3.0.apk"
	var debug_name := good.duplicate(true)
	debug_name.assets[0].name = "MauMauFlip-0.3.0-debug.apk"
	var twice := good.duplicate(true)
	twice.assets.append(good.assets[0].duplicate())
	var other_version := good.duplicate(true)
	other_version.tag_name = "v0.3.1"
	check(Updater.parse(JSON.stringify(wrong_name)).is_empty() and Updater.parse(JSON.stringify(debug_name)).is_empty()
		and Updater.parse(JSON.stringify(twice)).is_empty() and Updater.parse(JSON.stringify(other_version)).is_empty(),
		"Asset-Name muss genau MauMauFlip-<Tag-Version>.apk sein, genau einmal")
	var zero := good.duplicate(true)
	zero.assets[0].size = 0
	var no_v := good.duplicate(true)
	no_v.tag_name = "0.3.0"
	check(Updater.parse(JSON.stringify(zero)).is_empty() and Updater.parse(JSON.stringify(no_v)).is_empty() and Updater.parse("").is_empty()
		and Updater.parse("{kaputt").is_empty() and Updater.parse("[]", true).is_empty() and Updater.parse("{\"message\": \"Not Found\"}").is_empty(),
		"Größe 0, Tag ohne v, leere oder kaputte Antwort abgelehnt")
	# Beta-Kanal: Vorabversion und Beta-Repo nur mit allow_beta; aus einer Liste gewinnt die höchste gültige Version.
	var pre := release("0.3.1", Updater.REPOSITORY, true)
	var listing := JSON.stringify([good, pre, draft])
	check(Updater.parse(JSON.stringify(pre)).is_empty() and Updater.parse(JSON.stringify(pre), true).get("beta") == true,
		"Vorabversion nur im Beta-Kanal")
	check(Updater.parse(listing, true).get("version") == "0.3.1" and Updater.parse(listing, false).get("version") == "0.3.0",
		"Liste: höchste Version je Kanal")
	var from_beta_repo := release("0.3.2", Updater.BETA_REPOSITORY, true)
	check(Updater.parse(JSON.stringify(from_beta_repo)).is_empty() and Updater.parse(JSON.stringify(from_beta_repo), true).get("beta") == true
		and Updater.parse(JSON.stringify(from_beta_repo), true).get("url") == "https://github.com/ShakieVan/Mau-Mau-Flip-Beta/releases/download/v0.3.2/MauMauFlip-0.3.2.apk",
		"Beta-Repo nur im Beta-Kanal")
	var beta_as_release := release("0.3.3", Updater.BETA_REPOSITORY, false)
	check(Updater.parse(JSON.stringify(beta_as_release)).is_empty() and Updater.parse(JSON.stringify(beta_as_release), true).get("beta") == true,
		"Beta-Repo zählt auch ohne prerelease-Kennzeichen als Beta")

	# GitHub-Limit, fehlendes Netz und Serverfehler unterschieden.
	var limit_headers := PackedStringArray(["X-RateLimit-Limit: 60", "X-RateLimit-Remaining: 0", "X-RateLimit-Reset: 1000600"])
	var limit_text := Updater.failure_text(HTTPRequest.RESULT_SUCCESS, 403, limit_headers, 1000000)
	check(limit_text.begins_with("GitHub-Limit erreicht – später erneut versuchen") and limit_text.contains("10 Minuten"), "403 mit Wartezeit: " + limit_text)
	check(Updater.failure_text(HTTPRequest.RESULT_SUCCESS, 403, PackedStringArray(), 0) == "GitHub-Limit erreicht – später erneut versuchen."
		and Updater.failure_text(HTTPRequest.RESULT_SUCCESS, 429, PackedStringArray(["retry-after: 30"]), 0).contains("1 Minute)")
		and Updater.failure_text(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), 0) == Updater.NO_CONNECTION
		and Updater.failure_text(HTTPRequest.RESULT_SUCCESS, 502, PackedStringArray(), 0).contains("502"), "403 ohne Angabe, 429, kein Netz, 502")

	# Ablauf mit eigenen Einstellungen und eigenem Download-Ordner (ohne Netz: Antworten werden direkt eingespeist).
	var stamp := Time.get_ticks_usec()
	var store_path := "user://test_app_updater_%d.json" % stamp
	var up := Updater.new()
	up.download_dir = "user://test_app_updates_%d" % stamp
	up.setup(AppSettings.new(store_path))
	check(up.beta() == Updater.default_beta(version) and not up.settings.has_value("beta"), "Beta-Kanal ohne Einstellung nach installierter Version")
	up.busy = true
	up._checked(HTTPRequest.RESULT_SUCCESS, 403, limit_headers, PackedByteArray())
	check(not up.busy and up.status.begins_with("GitHub-Limit erreicht") and not up.settings.has_value("update_last_check"),
		"Fehlschlag (403) sperrt die automatische Prüfung nicht")
	# Noch leeres Beta-Repo ([]) und Haupt-Repo ohne Release (404): gültige Antworten, kein Angebot, Zeitpunkt gemerkt.
	up.busy = true
	up.failed = false
	up.failure = ""
	up._checked(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), "[]".to_utf8_buffer())
	check(not up.available() and up.status == "Noch kein passendes Release veröffentlicht." and up.settings.has_value("update_last_check"),
		"leeres Repo: kein Angebot, Prüfzeitpunkt gemerkt")
	up.settings.reset("update_last_check")
	var next_version := "%d.0.0" % (int(version.split(".")[0]) + 1)
	up.busy = true
	up.failed = false
	up.failure = ""
	up._checked(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(release(next_version)).to_utf8_buffer())
	check(up.available() and up.release.version == next_version and up.settings.has_value("update_last_check") and up.status == "Neue Version verfügbar.",
		"erfolgreiche Prüfung bietet die neuere Version an und merkt den Zeitpunkt")
	check(Updater.release_page(up.release, false) == "https://github.com/ShakieVan/Mau-Mau-Flip/releases/tag/v" + next_version
		and Updater.release_page({}, true) == "https://github.com/ShakieVan/Mau-Mau-Flip-Beta/releases"
		and Updater.release_page({}, false) == "https://github.com/ShakieVan/Mau-Mau-Flip/releases/latest", "Release-Seite für „Im Browser herunterladen“")
	# Aufräumen beim Start: Solange das gemerkte Release neuer ist, bleibt nur seine APK; nach dem Update verschwinden alle Downloads.
	DirAccess.make_dir_recursive_absolute(up.download_dir)
	for file_name in [str(up.release.sha256) + ".apk", "alt.apk", "abgebrochen.apk.part"]:
		var f := FileAccess.open(up.download_dir + "/" + file_name, FileAccess.WRITE)
		f.store_string("x")
		f.close()
	var pending_update := Updater.new()
	pending_update.download_dir = up.download_dir
	pending_update.setup(AppSettings.new(store_path))
	check(pending_update.available() and pending_update.apk_ready and DirAccess.get_files_at(up.download_dir).size() == 1,
		"offenes Update behält beim Start nur seine APK")
	pending_update.settings.set_value("update_release", JSON.stringify(release(version)))
	var after_update := Updater.new()
	after_update.download_dir = up.download_dir
	after_update.setup(AppSettings.new(store_path))
	check(not after_update.available() and DirAccess.get_files_at(up.download_dir).is_empty(), "nach erfolgreichem Update wird die geladene APK gelöscht")
	var time_re := RegEx.create_from_string(r"^Zuletzt geprüft: \d\d\.\d\d\.\d{4}, \d\d:\d\d\.$")
	check(time_re.search(after_update.status) != null, "ohne neue Prüfung zeigt der Status die letzte: " + after_update.status)
	# Kanalwechsel verwirft das gemerkte Release (die neue Suche bleibt hier aus: busy).
	after_update.settings.set_value("update_release", JSON.stringify(release(next_version)))
	after_update.busy = true
	after_update.set_beta(not after_update.beta())
	check(not after_update.settings.has_value("update_release") and after_update.settings.has_value("beta"), "Kanalwechsel: Einstellung gespeichert, Zwischenstand verworfen")
	# Beta-Release aus dem Beta-Repo wird nur im Beta-Kanal angeboten.
	var beta_up := Updater.new()
	beta_up.download_dir = up.download_dir
	beta_up.setup(AppSettings.new(store_path))
	beta_up.settings.set_value("beta", false)
	beta_up.busy = true
	beta_up._checked(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify([release(next_version, Updater.BETA_REPOSITORY, true)]).to_utf8_buffer())
	var off_ok := not beta_up.available()
	beta_up.settings.set_value("beta", true)
	beta_up.busy = true
	beta_up._checked(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify([release(next_version, Updater.BETA_REPOSITORY, true)]).to_utf8_buffer())
	check(off_ok and beta_up.available() and beta_up.release.beta, "Beta-Release nur im Beta-Kanal angeboten")

	var test_dir := up.download_dir
	for node in [up, pending_update, after_update, beta_up]:
		node.free()
	for file_name in DirAccess.get_files_at(test_dir):
		DirAccess.remove_absolute(test_dir + "/" + file_name)
	DirAccess.remove_absolute(test_dir)
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(store_path + suffix)
	print("RESULT: %d ok" % ok)
	quit(1 if failed > 0 else 0)
