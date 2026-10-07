extends SceneTree

# Modul D, reine Funktionen: Nachrichten (JSON, Zahlen → int, Prüfung je Typ), Namensfilter, Begrüßung mit Versionsprüfung,
# Sofortantwort auf „ping“, Suchformat, Adressrechnung, WebSocket-Rahmen (RFC 6455: Schlüssel, Längen 7/16/64 Bit, Maskierung,
# Fehlerfälle, UTF-8) sowie HTTP-Kopf, Herkunftsprüfung, Cache-Regeln und die Einordnung der Netzschnittstellen.

var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)

func _init() -> void:
	test_decode()
	test_client_messages()
	test_names()
	test_hello()
	test_auto_reply()
	test_discovery_format()
	test_addresses()
	test_ws_key()
	test_ws_frames()
	test_ws_errors()
	test_utf8()
	test_http_helpers()
	test_interfaces()
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)

func test_decode() -> void:
	var m := NetProtocol.decode("{\"t\":\"act\",\"seq\":3,\"a\":{\"a\":\"play\",\"card\":17.0,\"list\":[1,2.5,3]},\"ts\":1759600000123}")
	check(m.get("t") == "act" and m.seq is int and m.seq == 3, "seq wird int")
	check(m.a.card is int and m.a.card == 17, "verschachtelte Zahl wird int")
	check(m.a.list[0] is int and m.a.list[1] is float, "Liste: ganze Zahlen int, Brüche float")
	check(m.ts is int and m.ts == 1759600000123, "Zeitstempel in ms bleibt exakt")
	check(NetProtocol.decode("[1,2]").is_empty(), "Liste statt Objekt verworfen")
	check(NetProtocol.decode("{\"x\":1}").is_empty(), "ohne Typ verworfen")
	check(NetProtocol.decode("{\"t\":5}").is_empty(), "Typ keine Zeichenkette verworfen")
	check(NetProtocol.decode("{kaputt").is_empty(), "kein JSON verworfen")
	var big := "{\"t\":\"log\",\"text\":\"%s\"}" % "x".repeat(NetProtocol.MAX_CLIENT_MESSAGE)
	check(NetProtocol.decode(big).is_empty(), "über 8 KB verworfen")
	check(not NetProtocol.decode(big, NetProtocol.MAX_HOST_MESSAGE).is_empty(), "mit größerer Grenze angenommen")
	var deep := "{\"t\":\"x\",\"a\":" + "[".repeat(40) + "1" + "]".repeat(40) + "}"
	var d := NetProtocol.decode(deep)
	check(d.get("t") == "x", "tiefe Verschachtelung bricht nicht ab")
	check(NetProtocol.encode({"t": "pong", "ts": 5}) == "{\"t\":\"pong\",\"ts\":5}", "encode erzeugt kompaktes JSON")

func test_client_messages() -> void:
	var h := NetProtocol.clean_client_message({"t": "hello", "proto": 1, "game": "0.1.1", "name": "  Anna\u0007  ", "kind": "web", "token": "abc", "x": 1})
	check(h.name == "Anna" and h.kind == "web" and h.token == "abc" and not h.has("x"), "hello bereinigt")
	var h2 := NetProtocol.clean_client_message({"t": "hello", "proto": "1", "kind": "toaster"})
	check(h2.proto == -1 and h2.kind == "web" and h2.name == "Gast" and h2.game == "", "hello mit falschen Typen")
	var a := NetProtocol.clean_client_message({"t": "act", "seq": 4, "a": {"a": "play", "card": 7, "color": "rot", "evil": [1], "target": "x"}})
	check(a.a == {"a": "play", "card": 7, "color": "rot"} and a.seq == 4, "act: nur bekannte Felder mit Typ")
	check(NetProtocol.clean_client_message({"t": "act", "a": {"card": 1}}).is_empty(), "act ohne Aktionsnamen verworfen")
	check(NetProtocol.clean_client_message({"t": "act", "a": "play"}).is_empty(), "act ohne Objekt verworfen")
	check(NetProtocol.clean_client_message({"t": "lobby_ready", "ready": true}) == {"t": "lobby_ready", "ready": true}, "lobby_ready")
	check(NetProtocol.clean_client_message({"t": "lobby_ready", "ready": 1}).is_empty(), "lobby_ready ohne bool verworfen")
	var lg := NetProtocol.clean_client_message({"t": "log", "text": "Fehler\nZeile 2\u0001" +"y".repeat(5000)})
	check(lg.text.begins_with("Fehler\nZeile 2y") and lg.text.length() == NetProtocol.MAX_LOG_TEXT, "log gekürzt, Steuerzeichen raus, Zeilenumbruch bleibt")
	check(NetProtocol.clean_client_message({"t": "ping", "ts": 12}).ts == 12, "ping")
	check(NetProtocol.clean_client_message({"t": "neu", "x": 1}).get("x") == 1, "unbekannter Typ geht durch")

func test_names() -> void:
	check(NetProtocol.clean_name("  Lena  ") == "Lena", "Leerraum an den Rändern")
	check(NetProtocol.clean_name("Ä Ö  ü\tß") == "Ä Ö ü ß", "Umlaute bleiben, Leerraum zusammengefasst")
	check(NetProtocol.clean_name("Abcdefghijklmnopqrstuvwxyz").length() == NetProtocol.MAX_NAME, "auf %d Zeichen gekürzt" % NetProtocol.MAX_NAME)
	check(NetProtocol.clean_name(char(0x202E) + "nna" + char(0x200B)) == "nna", "Richtungs- und Nullbreitenzeichen entfernt")
	check(NetProtocol.clean_name("\u0001\u0002") == "Gast", "leer → Ersatzname")
	check(NetProtocol.clean_name("", "Computer") == "Computer", "eigener Ersatzname")
	var zalgo := NetProtocol.clean_name("a" + char(0x301) + char(0x302) + char(0x303) + char(0x304) + char(0x305) + "b")
	check(zalgo == "a" + char(0x301) + char(0x302) + "b", "höchstens zwei kombinierende Zeichen")
	check(NetProtocol.unique_name("Anna", ["Anna", "Ben"]) == "Anna 2", "doppelter Name bekommt Ziffer")
	check(NetProtocol.unique_name("Anna", ["Anna", "Anna 2"]) == "Anna 3", "nächste freie Ziffer")
	check(NetProtocol.unique_name("Abcdefghijklmn", ["Abcdefghijklmn"]).length() <= NetProtocol.MAX_NAME, "Ziffer passt in die Länge")

func test_hello() -> void:
	var v := NetProtocol.game_version()
	var expected := str(ProjectSettings.get_setting("application/config/version", ""))
	check(v == expected and v.split(".").size() == 3, "Spielversion aus project.godot (%s)" % v)
	var hello := NetProtocol.make_hello("Ben", "app", "tok")
	check(hello.proto == NetProtocol.PROTO and hello.game == v and hello.token == "tok" and hello.kind == "app", "make_hello")
	check(NetProtocol.check_hello(NetProtocol.clean_client_message(hello), v).is_empty(), "passende Begrüßung angenommen")
	var url := "http://192.168.1.5:24690/apk"
	var p := NetProtocol.check_hello({"proto": 2, "game": v}, v, url)
	check(p.get("code") == "proto", "falsches Protokoll → proto")
	var old := NetProtocol.check_hello({"proto": 1, "game": "0.1.0", "kind": "app"}, v, url)
	check(old.get("code") == "version" and old.text.contains("App vom Gastgeber holen: " + url) and old.text.contains("0.1.0"), "ältere App → version mit APK-Hinweis")
	var web := NetProtocol.check_hello({"proto": 1, "game": "0.0.9", "kind": "web"}, v, url)
	check(web.text.contains("Seite neu laden") and web.text.contains("App vom Gastgeber holen"), "Browser: neu laden plus APK-Hinweis")
	var newer_version := "%d.0.0" % (int(v.split(".")[0]) + 1)   # immer neuer als die eigene Version
	var newer := NetProtocol.check_hello({"proto": 1, "game": newer_version, "kind": "app"}, v, url)
	check(newer.get("code") == "version" and newer.text.contains("Gastgeber sollte") and not newer.text.contains("/apk"), "neuere App → Gastgeber aktualisieren, keine Rückstufung")
	check(NetProtocol.compare_versions("0.1.10", "0.1.9") == 1 and NetProtocol.compare_versions("1.0", "1.0.0") == 0, "Versionsvergleich")

func test_auto_reply() -> void:
	var r := NetProtocol.auto_reply("{\"t\":\"ping\",\"ts\":1234}")
	check(r == "{\"t\":\"pong\",\"ts\":1234}", "ping → pong mit demselben ts (%s)" % r)
	check(NetProtocol.auto_reply("{\"t\":\"act\",\"a\":{\"a\":\"ping\"}}") == "", "andere Nachricht mit \"ping\" → keine Sofortantwort")
	check(NetProtocol.auto_reply("{\"t\":\"ping\",\"ts\":\"x\"}") == "{\"t\":\"pong\",\"ts\":0}", "ts ohne Zahl → 0")
	check(NetProtocol.auto_reply("{\"t\":\"lobby_ready\",\"ready\":true}") == "", "lobby_ready geht weiter")

func test_discovery_format() -> void:
	check(NetProtocol.is_query("MMF?".to_ascii_buffer()), "Anfrage erkannt")
	check(not NetProtocol.is_query("D2R?".to_ascii_buffer()) and not NetProtocol.is_query(PackedByteArray([1, 2])), "fremde Anfrage verworfen")
	var info := NetProtocol.make_info("Lena", 3, 24690, {"running": false, "sid": "abc", "addresses": ["192.168.1.5", "10.0.0.2"]})
	var back := NetProtocol.parse_reply(NetProtocol.make_reply(info))
	check(back.name == "Lena" and back.players == 3 and back.port == 24690 and back.version == NetProtocol.game_version(), "Antwort übersteht Hin und Zurück")
	check(back.compatible and back.addresses == ["192.168.1.5", "10.0.0.2"] and back.sid == "abc" and back.max == NetProtocol.MAX_PLAYERS, "Antwort: passend, Adressen, sid")
	var other := info.duplicate()
	other.version = "0.0.1"
	check(not NetProtocol.parse_reply(NetProtocol.make_reply(other)).compatible, "andere Version: nicht passend")
	check(NetProtocol.parse_reply("{\"m\":\"D2R-HOST\",\"port\":1}".to_utf8_buffer()).is_empty(), "fremdes Spiel verworfen")
	check(NetProtocol.parse_reply(PackedByteArray([0x7B, 0, 0x7D])).is_empty(), "Steuerbytes verworfen")
	var many := info.duplicate()
	many.addresses = []
	for i in range(80):
		many.addresses.append("10.0.%d.1" % i)
	check(NetProtocol.make_reply(many).size() <= NetProtocol.MAX_DISCOVERY_BYTES, "Antwort bleibt unter 1 KB")

func test_addresses() -> void:
	check(NetProtocol.ipv4_to_int("192.168.1.5") == 0xC0A80105 and NetProtocol.ipv4_to_int("1.2.3") == -1 and NetProtocol.ipv4_to_int("1.2.3.256") == -1, "ipv4_to_int")
	check(NetProtocol.directed_broadcast("192.168.43.17", 24) == "192.168.43.255" and NetProtocol.directed_broadcast("10.1.2.3", 16) == "10.1.255.255", "gerichteter Rundruf")
	check(NetProtocol.usable_ipv4("192.168.1.5") and not NetProtocol.usable_ipv4("127.0.0.1") and not NetProtocol.usable_ipv4("169.254.3.4"), "usable: Loopback/Link-local nicht")
	check(not NetProtocol.usable_ipv4("192.0.0.2") and not NetProtocol.usable_ipv4("224.0.0.1") and not NetProtocol.usable_ipv4("0.0.0.0"), "usable: CLAT, Multicast, 0.0.0.0 nicht")
	check(NetProtocol.is_private_ipv4("172.20.1.1") and NetProtocol.is_private_ipv4("10.9.9.9") and not NetProtocol.is_private_ipv4("8.8.8.8"), "private Netze")
	check(NetProtocol.parse_address("192.168.1.5") == {"address": "192.168.1.5", "port": NetProtocol.PORT}, "Adresse ohne Port")
	check(NetProtocol.parse_address(" http://192.168.1.5:24691/ ") == {"address": "192.168.1.5", "port": 24691}, "Adresse mit Schema, Port und /")
	check(NetProtocol.parse_address("192,168,1,5:9") == {"address": "192.168.1.5", "port": 9}, "Kommas statt Punkte (Handy-Tastatur)")
	check(NetProtocol.parse_address("hallo").is_empty() and NetProtocol.parse_address("1.2.3.4:99999").is_empty(), "ungültige Adressen")

func test_ws_key() -> void:
	check(NetWs.accept_key("dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", "Sec-WebSocket-Accept wie im RFC-Beispiel")
	check(NetWs.valid_key("dGhlIHNhbXBsZSBub25jZQ==") and not NetWs.valid_key("abc") and not NetWs.valid_key(""), "Schlüssel geprüft")

func naive_mask(data: PackedByteArray, key: PackedByteArray) -> PackedByteArray:
	var out := data.duplicate()
	for i in range(out.size()):
		out[i] = out[i] ^ key[i % 4]
	return out

func test_ws_frames() -> void:
	var key := PackedByteArray([0x37, 0xFA, 0x21, 0x3D])
	var ok_all := true
	for n in range(0, 11):
		var d := PackedByteArray()
		for i in range(n):
			d.append((i * 37 + 5) & 255)
		if NetWs.apply_mask(d, key) != naive_mask(d, key):
			ok_all = false
	check(ok_all, "Maskierung je 4 Byte = Einzelbyte-XOR (Längen 0–10)")
	# RFC 6455 5.7: maskiertes „Hello“
	var hello := PackedByteArray([0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58])
	var f := NetWs.parse_frame(hello, 0, 1000)
	check(f.status == "ok" and f.fin and f.opcode == 1 and f.masked and f.payload.get_string_from_utf8() == "Hello" and f.size == 11, "RFC-Beispiel maskiertes Hello")
	check(NetWs.encode_frame(NetWs.OP_TEXT, "Hello".to_utf8_buffer(), true, true, key) == hello, "maskiert kodiert wie im RFC")
	check(NetWs.text_frame("Hello") == PackedByteArray([0x81, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f]), "unmaskierter Textrahmen")
	for n in [0, 125, 126, 65535, 65536, 70000]:
		var data := PackedByteArray()
		data.resize(n)
		for i in range(0, n, 97):
			data[i] = i & 255
		var frame := NetWs.encode_frame(NetWs.OP_TEXT, data, true, true)
		var g := NetWs.parse_frame(frame, 0, 100000)
		check(g.status == "ok" and g.payload == data and g.size == frame.size(), "Länge %d hin und zurück (Kopf %d Byte)" % [n, frame.size() - n])
	var two := NetWs.text_frame("a") + NetWs.text_frame("bc")
	var first := NetWs.parse_frame(two, 0, 10)
	var second := NetWs.parse_frame(two, first.size, 10)
	check(first.payload.get_string_from_utf8() == "a" and second.payload.get_string_from_utf8() == "bc", "zwei Rahmen hintereinander")
	var part := NetWs.encode_frame(NetWs.OP_TEXT, "x".repeat(300).to_utf8_buffer(), true, true)
	var need_all := true
	for cut in [0, 1, 2, 3, 5, 7, 8, 100, part.size() - 1]:
		if NetWs.parse_frame(part.slice(0, cut), 0, 1000).status != "need":
			need_all = false
	check(need_all, "unvollständige Rahmen → need")
	var cl := NetWs.parse_close(NetWs.close_payload(1008, "zu viele"))
	check(cl == [1008, "zu viele"], "Close-Code und Grund")
	check(NetWs.parse_close(PackedByteArray()) == [1005, ""], "Close ohne Code")
	check(NetWs.close_payload(1000, "ä".repeat(200)).size() <= 125, "Close-Grund gekürzt")
	check(NetWs.valid_close_code(1000) and NetWs.valid_close_code(4000) and not NetWs.valid_close_code(1005) and not NetWs.valid_close_code(999), "erlaubte Close-Codes")

func test_ws_errors() -> void:
	check(NetWs.parse_frame(PackedByteArray([0xC1, 0x80, 0, 0, 0, 0]), 0, 100).code == 1002, "RSV-Bit → 1002")
	check(NetWs.parse_frame(PackedByteArray([0x83, 0x80, 0, 0, 0, 0]), 0, 100).code == 1002, "unbekannter Opcode → 1002")
	check(NetWs.parse_frame(PackedByteArray([0x09, 0x80, 0, 0, 0, 0]), 0, 100).code == 1002, "fragmentierter Ping → 1002")
	check(NetWs.parse_frame(PackedByteArray([0x89, 0xFE, 0, 126]), 0, 1000).code == 1002, "Ping über 125 Byte → 1002")
	check(NetWs.parse_frame(PackedByteArray([0x81, 0xFE, 0x10, 0x00]), 0, 1000).code == 1009, "zu großer Rahmen → 1009 vor den Daten")
	check(NetWs.parse_frame(PackedByteArray([0x81, 0xFF, 0x80, 0, 0, 0, 0, 0, 0, 0]), 0, 1000).code == 1002, "64-Bit-Länge mit oberstem Bit → 1002")

func test_utf8() -> void:
	check(NetWs.valid_utf8("Grüße 🃏 Mau!".to_utf8_buffer()), "gültiges UTF-8 mit Umlaut und Emoji")
	check(NetWs.valid_utf8(PackedByteArray()), "leer ist gültig")
	check(not NetWs.valid_utf8(PackedByteArray([0xC0, 0xAF])), "Überlänge ungültig")
	check(not NetWs.valid_utf8(PackedByteArray([0xED, 0xA0, 0x80])), "Surrogat ungültig")
	check(not NetWs.valid_utf8(PackedByteArray([0xF4, 0x90, 0x80, 0x80])), "über U+10FFFF ungültig")
	check(not NetWs.valid_utf8(PackedByteArray([0x61, 0xE2, 0x82])), "abgeschnitten ungültig")
	check(not NetWs.valid_utf8(PackedByteArray([0x80])), "einzelnes Folgebyte ungültig")

func test_http_helpers() -> void:
	var r := NetServer.parse_head("GET /cards/a%20b.webp?v=3 HTTP/1.1\r\nHost: 192.168.1.5:24690\r\nAccept-Encoding: gzip\r\nX-A: 1\r\nx-a: 2")
	check(r.ok and r.method == "GET" and r.path == "/cards/a b.webp" and r.query == "v=3", "Anfragezeile zerlegt")
	check(r.headers.host == "192.168.1.5:24690" and r.headers["x-a"] == "1, 2", "Kopfzeilen klein, doppelte zusammengefasst")
	check(not NetServer.parse_head("GET /\r\n").ok and not NetServer.parse_head("HALLO").ok, "Unsinn erkannt")
	check(not NetServer.parse_head("GET / HTTP/1.1\r\nkaputt").ok, "Kopfzeile ohne Doppelpunkt erkannt")
	check(NetServer.origin_allowed("", "192.168.1.5:24690"), "ohne Herkunft erlaubt (App)")
	check(NetServer.origin_allowed("http://192.168.1.5:24690", "192.168.1.5:24690"), "gleiche Herkunft erlaubt")
	check(not NetServer.origin_allowed("http://evil.example", "192.168.1.5:24690"), "fremde Herkunft abgelehnt")
	check(not NetServer.origin_allowed("http://192.168.1.5:24691", "192.168.1.5:24690"), "anderer Port abgelehnt")
	check(not NetServer.origin_allowed("null", "192.168.1.5:24690"), "Herkunft null abgelehnt")
	check(NetServer.origin_allowed("http://Host.local", "host.local:80"), "Standardport 80")
	check(NetServer.versioned("/app.js", "v=0.1.1") and NetServer.versioned("/app.3f9a1c2e.js", "") and NetServer.versioned("/app.0.1.1.js", ""), "versionierte Dateien erkannt")
	check(not NetServer.versioned("/index.html", "") and not NetServer.versioned("/cards/hell_rot_7.webp", ""), "unversionierte Dateien")
	check(NetServer.mime_type("a/b.webp") == "image/webp" and NetServer.mime_type("x.WOFF2") == "font/woff2" and NetServer.mime_type("s.css").begins_with("text/css"), "MIME-Typen")
	check(NetServer.mime_type("m.m4a") == "audio/mp4" and NetServer.mime_type("x.ogg") == "audio/ogg" and NetServer.mime_type("x.wav") == "audio/wav" and NetServer.mime_type("x.svg") == "image/svg+xml", "MIME-Typen Ton und SVG")
	check(NetServer.mime_type("x.unbekannt") == "application/octet-stream", "unbekannte Endung")

func test_interfaces() -> void:
	check(NetAddresses.classify("wlan0") == "wlan" and NetAddresses.classify("swlan0") == "hotspot" and NetAddresses.classify("rmnet_data0") == "mobile", "Android-Schnittstellen")
	check(NetAddresses.classify("ap0") == "hotspot" and NetAddresses.classify("ccmni1") == "mobile" and NetAddresses.classify("v4-rmnet0") == "mobile", "Hotspot und Mobilfunk")
	check(NetAddresses.classify("WLAN") == "wlan" and NetAddresses.classify("Ethernet") == "lan" and NetAddresses.classify("vEthernet (WSL)") == "virtual", "Windows-Namen")
	check(NetAddresses.classify("LAN-Verbindung* 2") == "virtual" and NetAddresses.classify("Bluetooth-Netzwerkverbindung") == "virtual", "Windows: virtuelle Adapter")
	NetAddresses.override_interfaces = [
		{"name": "rmnet_data0", "address": "10.180.3.4", "prefix": 30},
		{"name": "swlan0", "address": "172.17.251.253", "prefix": 24},
		{"name": "wlan0", "address": "192.168.178.40", "prefix": 24},
		{"name": "v4-rmnet_data0", "address": "192.0.0.4", "prefix": 29},
		{"name": "lo", "address": "127.0.0.1", "prefix": 8},
		{"name": "dummy0", "address": "10.0.0.9", "prefix": 24}]
	var own := NetAddresses.own_addresses()
	check(own.map(func(a): return a.address) == ["192.168.178.40", "172.17.251.253"], "QR-Adressen: WLAN, dann Hotspot, ohne Mobilfunk (%s)" % str(own))
	check(own[0].kind == "wlan" and own[1].kind == "hotspot", "Arten der Adressen")
	var targets := NetAddresses.broadcast_targets()
	check(targets.has("255.255.255.255") and targets.has("192.168.178.255") and targets.has("172.17.251.255") and not targets.has("10.180.3.7"), "Rundruf-Ziele ohne Mobilfunk (%s)" % str(targets))
	NetAddresses.override_interfaces = null
	check(NetAddresses.own_addresses().all(func(a): return NetProtocol.usable_ipv4(a.address)), "echte Adressen dieses PCs brauchbar")
