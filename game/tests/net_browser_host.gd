extends SceneTree

# Modul D, Browser-Test – Godot-Seite (kein test_*.gd: läuft nur zusammen mit Chrome über tools/nettest/browser_test.ps1).
# Packt die Testseite tools/nettest/page/ per ZIPPacker in eine Zip, startet NetHostSession auf Port 24800 und wartet, bis der
# Browser per WebSocket „BROWSER-OK“ bzw. „BROWSER-FAIL“ meldet (Zeitgrenze NETTEST_SECONDS, Standard 60 s). Nach dem Wiederbeitritt
# des Browsers schickt er ein „state“ mit Umlauten, Emoji und 70 KB (64-Bit-Länge), das die Seite prüft.
# Umgebung: NETTEST_PAGE (Ordner der Testseite), NETTEST_SECONDS, NETTEST_PORT.

var failures := 0
var checks := 0
var joined: Array = []
var rejoined: Array = []
var logs: Array = []
var browser_line := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)

func pack(dir_path: String, zip_path: String) -> int:
	DirAccess.make_dir_recursive_absolute(zip_path.get_base_dir())
	var z := ZIPPacker.new()
	if z.open(zip_path) != OK:
		return 0
	var n := 0
	for file in DirAccess.get_files_at(dir_path):
		z.start_file(file)
		z.write_file(FileAccess.get_file_as_bytes(dir_path.path_join(file)))
		z.close_file()
		n += 1
	z.close()
	return n

func _init() -> void:
	var page := OS.get_environment("NETTEST_PAGE")
	if page == "":
		page = ProjectSettings.globalize_path("res://").path_join("../tools/nettest/page").simplify_path()
	var seconds := int(OS.get_environment("NETTEST_SECONDS")) if OS.get_environment("NETTEST_SECONDS").is_valid_int() else 60
	var port := int(OS.get_environment("NETTEST_PORT")) if OS.get_environment("NETTEST_PORT").is_valid_int() else 24800
	var zip_path := "user://nettest/browser.zip"
	check(pack(page, zip_path) >= 3, "Testseite gepackt (%s)" % page)
	var session := NetHostSession.new()
	session.auto_poll = false
	session.use_discovery = false
	session.web_zip_path = zip_path
	session.player_joined.connect(func(id): joined.append(id))
	session.player_rejoined.connect(func(id):
		rejoined.append(id)
		session.send_to(id, {"t": "state", "events": [], "view": {"text": "Grüße 🃏 Mau", "big": "y".repeat(70000), "seat": 2}}))
	session.log_line.connect(func(t):
		logs.append(t)
		print("LOG: ", t.left(200))
		if t.contains("BROWSER-OK") or t.contains("BROWSER-FAIL"):
			browser_line = t)
	# Halter auf Port + 1: nimmt Verbindungen an und antwortet nie. Ein offener Abruf der Seite dorthin hält Chromes virtuelle Zeit an
	# (--virtual-time-budget wartet nicht auf WebSocket-Verkehr), bis die Seite ihn nach dem Test abbricht.
	var holder := TCPServer.new()
	var held: Array = []
	check(holder.listen(port + 1, "127.0.0.1") == OK, "Halter auf Port %d" % (port + 1))
	check(session.start("Netztest", port, port) == OK, "Server auf Port %d" % port)
	print("SERVER-BEREIT ", session.port())
	var end := Time.get_ticks_msec() + seconds * 1000
	var settle := -1
	while Time.get_ticks_msec() < end and (settle < 0 or Time.get_ticks_msec() < settle):
		session.poll()
		while holder.is_connection_available():
			held.append(holder.take_connection())
		if browser_line != "" and settle < 0:
			settle = Time.get_ticks_msec() + 300
		OS.delay_msec(2)
	for h in held:
		h.disconnect_from_host()
	holder.stop()
	check(browser_line.contains("BROWSER-OK"), "Browser meldet Erfolg: %s" % (browser_line.left(400) if browser_line != "" else "nichts innerhalb %d s" % seconds))
	check(joined.size() == 1 and rejoined.size() == 1 and joined[0] == rejoined[0], "ein Browser-Spieler, Wiederbeitritt mit derselben id")
	if joined.size() == 1:
		var p := session.player(joined[0])
		check(p.get("kind") == "web" and p.get("name") == "Chrome" and p.get("ready") == true, "Art web, Name, bereit (%s)" % str(p))
	check(logs.any(func(l): return l.contains("Großer Logeintrag")), "Browser-Log über 5 KB angekommen (gekürzt)")
	var stats := session.server.stats() if session.server != null else {}
	check(int(stats.get("ws_opened", 0)) == 2 and int(stats.get("origin_rejected", 0)) == 0 and int(stats.get("protocol_errors", 0)) == 0, "zwei WebSockets, keine Fehler (%s)" % str(stats))
	check(int(stats.get("tls_rejected", 0)) >= 1, "https-Versuch des Browsers sofort abgewiesen (%d)" % int(stats.get("tls_rejected", 0)))
	check(int(stats.get("gzip", 0)) >= 1, "app.js gzip-komprimiert an Chrome (%d)" % int(stats.get("gzip", 0)))
	check(int(stats.get("http", 0)) >= 4, "Seite, Skript, Stil und /info über HTTP (%d Anfragen)" % int(stats.get("http", 0)))
	session.stop()
	session.free()
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)
