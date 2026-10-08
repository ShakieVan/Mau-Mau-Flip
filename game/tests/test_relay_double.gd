extends SceneTree

# Online-Spiel (docs/online/ENTWURF.md, Abschnitt 6): GDScript-Nachbau des Vermittlers (NetRelayDouble) und Protokollhilfen.
#  1. Raumcodes und Adressen (NetProtocol.normalize_room_code wie normalizeCode in relay/src/core.js, Vermittler-Adresse, Raum-Link),
#     Wortliste des Nachbaus ⊂ relay/src/words.js.
#  2. Raumlogik (NetRelayDouble.Core) ohne Netz: Anlegen, Gäste, Umschlag, Grenzen, Gastgeber weg (4503), Rückkehr mit Token,
#     Ersetzen (4000), Ablauf nach 10 min / 24 h, kick, end, Rate und Größe.
#  3. Gemeinsame Testvektoren relay/test/vectors.json (dieselben laufen in Chrome gegen core.js), falls vorhanden.
#  4. Über echte Sockets (127.0.0.1:24781): /info, /info?room=, Gastgeber (NetRelayHost) und Gast (NetClient) mit Herzschlag.

const PORT := 24781
const VECTORS := "res://../relay/test/vectors.json"

var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)

func _init() -> void:
	test_codes()
	test_core()
	test_vectors()
	test_sockets()
	print("RESULT: %d ok" % (checks - failures) if failures == 0 else "RESULT: %d ok, %d FAIL" % [checks - failures, failures])
	quit(1 if failures else 0)

# ---------- 1. Codes und Adressen ----------

func test_codes() -> void:
	var n := NetProtocol.normalize_room_code
	check(n.call("KATZE-42") == "KATZE-42" and n.call(" katze 42 ") == "KATZE-42" and n.call("katze42") == "KATZE-42"
		and n.call("Katze_42") == "KATZE-42" and n.call("katze.42") == "KATZE-42", "Raumcode normalisieren")
	check(n.call("Löwe-12") == "LOEWE-12" and n.call("BÄR 33") == "BAER-33", "Umlaute → AE/OE/UE")
	for bad in ["", "KA-42", "KATZE-4", "KATZE-420", "KATZE-05", "42-KATZE", "KATZE!42", "SCHMETTERLING-42", "KATZE-42X"]:
		check(n.call(bad) == "", "ungültig: „%s“ → „%s“" % [bad, n.call(bad)])
	var r := NetProtocol.normalize_relay_url
	check(r.call("mmf.shakie.workers.dev") == "https://mmf.shakie.workers.dev", "Vermittler ohne Schema → https")
	check(r.call("https://MMF.shakie.workers.dev/") == "https://mmf.shakie.workers.dev" and r.call("http://localhost:24700/x?y") == "http://localhost:24700",
		"Vermittler: Pfad und Schrägstrich weg, http bleibt")
	check(r.call("wss://a.b") == "https://a.b" and r.call("") == "" and r.call("ftp://a.b") == "" and r.call("a b") == "" and r.call("a.b:99999") == "",
		"Vermittler: ungültige Adressen")
	check(NetProtocol.relay_ws_url("https://a.b", "role=guest&room=KATZE-42") == "wss://a.b/ws?role=guest&room=KATZE-42"
		and NetProtocol.relay_ws_url("http://localhost:24700", "x=1") == "ws://localhost:24700/ws?x=1", "WebSocket-Adresse wss/ws")
	check(NetProtocol.room_link("a.b", "katze 42") == "https://a.b/?r=KATZE-42", "Raum-Link")
	var p := NetProtocol.parse_room_link("https://a.b/?r=katze-42")
	check(p.get("relay") == "https://a.b" and p.get("room") == "KATZE-42", "Raum-Link lesen")
	check(NetProtocol.parse_room_link("192.168.1.5").is_empty() and NetProtocol.parse_room_link("https://a.b/").is_empty(), "kein Raum-Link")
	check(NetProtocol.relay_host("https://a.b:8443") == "a.b:8443" and NetProtocol.relay_host("http://localhost:24700") == "http://localhost:24700",
		"Vermittler-Host für App-Link")
	check(NetProtocol.apk_page_url("1.2.0").contains("/Mau-Mau-Flip/releases") and NetProtocol.apk_page_url("1.2.3").contains("Mau-Mau-Flip-Beta"),
		"APK für Online-Gäste: GitHub-Release bzw. Beta")
	# App-Link mit Raum (maumauflip://join?r=&v=) und Einstellung „vermittler“
	var l := NetAndroid.parse_app_link("maumauflip://join?r=katze-42&v=mau.x.workers.dev")
	check(l.ok and l.room == "KATZE-42" and l.relay == "https://mau.x.workers.dev", "App-Link mit Raum und Vermittler: %s" % str(l))
	l = NetAndroid.parse_app_link(NetAndroid.app_link_room("MOND-10", "http://localhost:24700"))
	check(l.ok and l.room == "MOND-10" and l.relay == "http://localhost:24700", "App-Link mit http-Vermittler (Nachbau): %s" % str(l))
	l = NetAndroid.parse_app_link("maumauflip://join?r=MOND-10")
	check(l.ok and l.relay == "", "App-Link ohne v: Vermittler aus den Einstellungen")
	check(not NetAndroid.parse_app_link("maumauflip://join?r=MOND").ok and not NetAndroid.parse_app_link("maumauflip://join?r=MOND-10&v=a%20b").ok,
		"App-Link mit falschem Code/Vermittler abgewiesen")
	check(NetAndroid.parse_app_link("maumauflip://join?h=192.168.1.5&p=24690").get("address") == "192.168.1.5", "WLAN-App-Link unverändert")
	check(AppSettings.defaults().get("vermittler") == NetProtocol.RELAY_DEFAULT and AppSettings.sanitize("vermittler", "a.b/") == "https://a.b"
		and AppSettings.sanitize("vermittler", "") == "" and AppSettings.sanitize("vermittler", "a b") == null and AppSettings.sanitize("vermittler", 5) == null,
		"Einstellung „vermittler“")
	var i2 := "{\"game\":\"mau-mau-flip\",\"relay\":2}"
	var i1 := "{\"game\":\"mau-mau-flip\",\"relay\":1}"
	check(SettingsScreen.relay_test_text(false, "", 0, "1.2.2", -1).contains("nicht erreichbar")
		and SettingsScreen.relay_test_text(true, i2, 42, "1.2.2", 200).contains("42 ms")
		and SettingsScreen.relay_test_text(true, i2, 42, "1.2.2", 404).contains("noch nicht auf GitHub")
		and SettingsScreen.relay_test_text(true, i1, 42, "1.2.2", 404).contains("zu alt")
		and not SettingsScreen.relay_test_text(true, i1, 42, "1.2.2", 404).contains("Sync fork")
		and SettingsScreen.relay_test_text(true, "<html>", 42, "1.2.2", -1).contains("kein Vermittler"), "Text „Verbindung testen“")
	check(InviteSteps.online_glow("open", 0) and not InviteSteps.online_glow("open", 1) and not InviteSteps.online_glow("connecting", 0)
		and InviteSteps.online_done("away", 1) and not InviteSteps.online_done("off", 1), "Online-Weg: Leuchten und Haken")
	# Wortliste des Nachbaus steht in relay/src/words.js, alle Wörter sind gültige Codes
	var words_js := ProjectSettings.globalize_path("res://").path_join("../relay/src/words.js")
	if FileAccess.file_exists(words_js):
		var src := FileAccess.get_file_as_string(words_js)
		for w in NetRelayDouble.Core.WORDS:
			check(src.contains("'%s'" % w), "Wort %s steht in relay/src/words.js" % w)
			check(n.call(w + "-10") == w + "-10", "Wort %s ergibt einen gültigen Code" % w)
		var re := RegEx.create_from_string("'([A-Z]+)'")
		var head := src.left(src.find("export const FORBIDDEN"))
		var count := 0
		for m in re.search_all(head):
			count += 1
			check(n.call(m.get_string(1) + "-99") == m.get_string(1) + "-99", "words.js: %s ist als Code gültig (App-Normalisierung)" % m.get_string(1))
		check(count > 100, "words.js gelesen (%d Wörter)" % count)
	else:
		print("HINWEIS: relay/src/words.js fehlt – Wortlisten-Abgleich übersprungen")

# ---------- 2. Raumlogik ----------

func core() -> NetRelayDouble.Core:
	var c := NetRelayDouble.Core.new()
	c.base_url = "https://r.test"
	c.versions = ["1.2.2"]
	c.rng.seed = 7
	return c

static func frames(actions: Array, sock: int) -> Array:
	# Gesendete Texte an sock, JSON-Umschläge als Dictionary
	var out := []
	for a in actions:
		if a[0] == "send" and int(a[1]) == sock:
			var j := JSON.new()
			out.append(j.data if j.parse(str(a[2])) == OK and j.data is Dictionary else str(a[2]))
	return out

static func closes(actions: Array) -> Dictionary:
	var out := {}
	for a in actions:
		if a[0] == "close":
			out[int(a[1])] = int(a[2])
	return out

func test_core() -> void:
	var c := core()
	var t := 1000
	c.connect_socket(1, {"role": "host", "proto": "1", "v": "1.2.2"}, "", t)
	var a := c.take_actions()
	var room: Dictionary = frames(a, 1)[0]
	var code := str(room.get("room", ""))
	check(room.get("k") == "room" and NetProtocol.normalize_room_code(code) == code and str(room.get("token", "")).length() == 32
		and room.get("link") == "https://r.test/?r=" + code and int(room.limits.guests) == 16, "Raum angelegt: %s" % str(room))
	var token := str(room.token)
	check(c.info({"room": code.to_lower()}, t).room == {"open": true, "host": true, "version": "1.2.2"} and c.info({"room": "KATZE-11"}, t).room.open == false
		and int(c.info({}, t).relay) == 2, "info mit und ohne Raum")
	# Gäste
	c.connect_socket(10, {"role": "guest", "room": code}, "Agent/1", t)
	c.connect_socket(11, {"role": "guest", "room": code.replace("-", " ")}, "x".repeat(300), t)
	a = c.take_actions()
	var hf := frames(a, 1)
	check(hf.size() == 2 and hf[0] == {"k": "open", "c": 1.0, "info": {"agent": "Agent/1"}} and int(hf[1].c) == 2
		and str(hf[1].info.agent).length() == 120, "open je Gast, c ab 1, agent gekürzt: %s" % str(hf))
	c.connect_socket(12, {"role": "guest", "room": "KATZE-11"}, "", t)
	check(closes(c.take_actions()) == {12: 4404}, "Gast ohne Raum → 4404")
	# Umschlag
	c.message(10, "{\"t\":\"hello\"}", t)
	a = c.take_actions()
	check(frames(a, 1) == [{"k": "msg", "c": 1.0, "d": "{\"t\":\"hello\"}"}], "Gast → Gastgeber als msg mit Rohtext")
	c.message(1, JSON.stringify({"k": "send", "c": [1, 2], "d": "{\"t\":\"lobby\"}"}), t)
	a = c.take_actions()
	check(frames(a, 10) == [{"t": "lobby"}] and frames(a, 11) == [{"t": "lobby"}] and frames(a, 1).is_empty(), "send an mehrere, unverändert")
	c.message(1, JSON.stringify({"k": "send", "c": 7, "d": "x"}), t)
	check(frames(c.take_actions(), 1) == [{"k": "err", "code": "unknown_c", "c": 7.0}], "send an unbekannte Verbindung → err unknown_c")
	c.message(1, "kein json", t)
	c.message(1, JSON.stringify({"k": "send", "c": [1.5], "d": "x"}), t)
	c.message(1, JSON.stringify({"k": "was"}), t)
	check(frames(c.take_actions(), 1) == [{"k": "err", "code": "bad"}, {"k": "err", "code": "bad"}, {"k": "err", "code": "bad"}], "Unsinn → err bad")
	c.message(10, "ping", t)
	check(frames(c.take_actions(), 10) == ["pong"], "Herzschlag ping → pong")
	# Größe und Rate
	c.message(10, "x".repeat(8193), t)
	check(frames(c.take_actions(), 1) == [{"k": "drop", "c": 1.0, "why": "size", "size": 8193.0}], "Gast-Nachricht > 8 KB → drop size")
	var sent := 0
	var dropped := 0
	for i in 60:
		c.message(11, "{}", t + 10)
		for f in frames(c.take_actions(), 1):
			if f.k == "msg":
				sent += 1
			elif f.k == "drop" and f.why == "rate":
				dropped += 1
	check(sent == 40 and dropped == 20, "Rate: Spitze 40, dann drop rate (%d/%d)" % [sent, dropped])
	for i in 13:
		for j in 40:
			c.message(11, "{}", t + 10 + i * 900)
	a = c.take_actions()
	check(closes(a) == {11: 4429} and frames(a, 1).back() == {"k": "close", "c": 2.0, "code": 4429.0}, "Dauerverstoß 10 s → 4429: %s" % str(closes(a)))
	# kick
	c.connect_socket(13, {"role": "guest", "room": code}, "", t)
	a = c.take_actions()
	check(int(frames(a, 1)[0].c) == 3, "neue Nummer nach Rauswurf")
	c.message(1, JSON.stringify({"k": "kick", "c": 3, "code": 4000, "reason": "neu"}), t)
	a = c.take_actions()
	check(closes(a) == {13: 4000} and frames(a, 1) == [{"k": "close", "c": 3.0, "code": 4000.0}], "kick schließt mit Code und bestätigt")
	c.closed(13, 4000, t)
	check(c.take_actions().is_empty(), "Schließen eines schon geschlossenen Gasts meldet nichts")
	c.closed(10, 1000, t)
	check(frames(c.take_actions(), 1) == [{"k": "close", "c": 1.0, "code": 1000.0}], "Gast geht → close an den Gastgeber")
	# Gastgeber weg → 4503, Rückkehr mit Token
	c.connect_socket(14, {"role": "guest", "room": code}, "", t)
	c.take_actions()
	c.closed(1, 1006, t + 100)
	check(closes(c.take_actions()) == {14: 4503}, "Gastgeber weg → Gäste 4503")
	c.connect_socket(15, {"role": "guest", "room": code}, "", t + 200)
	check(closes(c.take_actions()) == {15: 4503} and c.info({"room": code}, t).room.host == false, "Gast während der Abwesenheit → 4503")
	c.connect_socket(2, {"role": "host", "room": code, "token": "falsch"}, "", t + 300)
	check(closes(c.take_actions()) == {2: 4403}, "Rückkehr mit falschem Token → 4403")
	c.connect_socket(3, {"role": "host", "room": code, "token": token}, "", t + 400)
	a = c.take_actions()
	var back: Dictionary = frames(a, 3)[0]
	check(back.k == "room" and back.room == code and not back.has("token"), "Rückkehr mit Token: room ohne Token")
	c.connect_socket(16, {"role": "guest", "room": code}, "", t + 500)
	check(int(frames(c.take_actions(), 3)[0].c) == 5, "Nummern laufen nach der Rückkehr weiter (keine Wiederverwendung)")
	c.connect_socket(4, {"role": "host", "room": code, "token": token}, "", t + 600)
	a = c.take_actions()
	check(closes(a) == {3: 4000} and frames(a, 4)[0].k == "room", "zweiter Gastgeber mit Token ersetzt den ersten (4000)")
	# Abwesenheit 10 min
	c.closed(4, 1006, t + 1000)
	c.take_actions()
	c.tick(t + 1000 + 599000)
	check(c.rooms.has(code), "nach 9:59 min noch da")
	c.tick(t + 1000 + 600000)
	check(not c.rooms.has(code) and c.info({"room": code}, t).room.open == false, "nach 10 min Abwesenheit gelöscht")
	c.connect_socket(5, {"role": "host", "room": code, "token": token}, "", t + 700000)
	check(closes(c.take_actions()) == {5: 4404}, "Rückkehr nach Ablauf → 4404")
	# Lebensdauer und end
	c.connect_socket(6, {"role": "host", "proto": "1", "v": "1.2.2"}, "", 0)
	var code2 := str(frames(c.take_actions(), 6)[0].room)
	c.connect_socket(20, {"role": "guest", "room": code2}, "", 0)
	c.take_actions()
	c.tick(24 * 3600 * 1000)
	check(closes(c.take_actions()) == {20: 1001, 6: 1001} and c.rooms.is_empty(), "Lebensdauer 24 h → 1001 an alle")
	c.connect_socket(7, {"role": "host", "proto": "1", "v": "1.2.2"}, "", 0)
	var code3 := str(frames(c.take_actions(), 7)[0].room)
	c.connect_socket(21, {"role": "guest", "room": code3}, "", 0)
	c.take_actions()
	c.message(7, "{\"k\":\"end\"}", 1)
	check(closes(c.take_actions()) == {21: 1001, 7: 1001} and c.rooms.is_empty(), "end → 1001 an alle, Raum weg")
	# volle Räume
	c.connect_socket(8, {"role": "host", "proto": "1", "v": "1.2.2"}, "", 0)
	var code4 := str(frames(c.take_actions(), 8)[0].room)
	for i in 16:
		c.connect_socket(100 + i, {"role": "guest", "room": code4}, "", 0)
	c.connect_socket(200, {"role": "guest", "room": code4}, "", 0)
	check(closes(c.take_actions()) == {200: 4409}, "17. Gast → 4409")
	# Codes sind eindeutig
	var seen := {}
	for i in 200:
		var k := c.new_code()
		seen[k] = true
		c.rooms[k] = {}
	check(seen.size() == 200 or c.new_code() == "", "Kollisionsprüfung: neue Codes sind frei")

# ---------- 3. Gemeinsame Testvektoren ----------

func test_vectors() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../relay/test/vectors.json")
	if not FileAccess.file_exists(path):
		print("HINWEIS: relay/test/vectors.json fehlt – Vektoren übersprungen")
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(data is Dictionary and data.get("cases") is Array, "vectors.json lesbar")
	if not data is Dictionary:
		return
	# Codes: App-Normalisierung prüft nur die Form; Wörter außerhalb der Liste lehnt erst der Vermittler ab
	var words_src := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../relay/src/words.js"))
	for pair in data.get("codes", []):
		var got := NetProtocol.normalize_room_code(str(pair[0]))
		var want := str(pair[1])
		var ok: bool = got == want or (want == "" and got != "" and not words_src.contains("'%s'" % got.get_slice("-", 0)))
		check(ok, "Code „%s“ → „%s“, erwartet „%s“" % [pair[0], got, want])
	var steps := 0
	for case in data.cases:
		steps += run_case(case, str(data.get("origin", "")), str(data.get("token", "")))
	print("Vektoren: %d Fälle, %d Schritte" % [data.cases.size(), steps])
	check(steps > 50, "Vektoren gelaufen (%d Schritte)" % steps)

func run_case(case: Dictionary, origin: String, token: String) -> int:
	var c := NetRelayDouble.Core.new()
	c.base_url = origin
	c.fixed_token = token
	var ids := {}                 # Name → Socket
	var names := {}               # Socket → Name
	var t := 0
	var n := 0
	var name := str(case.get("name", "?"))
	for step in case.steps:
		n += 1
		var where := "%s #%d (%s)" % [name, n, str(step.get("do"))]
		if step.has("t"):
			t = int(step.t)
		var who := str(step.get("as", ""))
		var sock: int = ids.get(who, -1)
		match str(step.do):
			"connect":
				sock = ids.size() + 1
				ids[who] = sock
				names[sock] = who
				var q: Dictionary = (step.q as Dictionary).duplicate()
				for k in q:
					q[k] = str(int(q[k])) if q[k] is float else q[k]
				var status := c.connect_socket(sock, q, str(q.get("agent", "")), t)
				if step.has("http"):
					check(status == int(step.http), "%s: HTTP %d erwartet, %d" % [where, int(step.http), status])
					c.take_actions()
					ids.erase(who)
				else:
					check(status == 101, "%s: angenommen erwartet (%d)" % [where, status])
			"text":
				var text := "x".repeat(int(step.fill)) if step.has("fill") else str(step.text)
				for i in int(step.get("repeat", 1)):
					c.message(sock, text, t)
			"frame":
				c.message(sock, JSON.stringify(step.frame), t)
			"close":
				c.closed(sock, int(step.code), t)
			"alarm":
				c.tick(t)
			"info":
				var got: Dictionary = c.info({"room": "KATZE-42"}, t).room
				for k in step.info:
					check(got.get(k) == step.info[k], "%s: info.%s = %s, erwartet %s" % [where, k, str(got.get(k)), str(step.info[k])])
		if not step.has("http"):
			compare(c.take_actions(), step.get("expect", []), names, where)
		if step.has("alarm"):
			var at := c.alarm_at("KATZE-42")
			var want: Variant = step.alarm
			check((want == null and at < 0) or (want != null and at == int(want)), "%s: Alarm %d, erwartet %s" % [where, at, str(want)])
		if step.has("stored"):
			check(c.rooms.has("KATZE-42") == bool(step.stored), "%s: gespeichert = %s erwartet" % [where, str(step.stored)])
	return n

func compare(actions: Array, expect: Array, names: Dictionary, where: String) -> void:
	var want := []
	for e in expect:
		for i in int(e.get("times", 1)):
			want.append(e)
	if actions.size() != want.size():
		check(false, "%s: %d Ausgaben, erwartet %d: %s" % [where, actions.size(), want.size(), str(actions).left(400)])
		return
	for i in actions.size():
		var a: Array = actions[i]
		var e: Dictionary = want[i]
		var to := str(names.get(int(a[1]), "?"))
		var ok := to == str(e.to)
		if e.has("close"):
			ok = ok and a[0] == "close" and int(a[2]) == int(e.close)
		elif e.has("text"):
			ok = ok and a[0] == "send" and str(a[2]) == str(e.text)
		elif e.has("frame"):
			var f = JSON.parse_string(str(a[2])) if a[0] == "send" else null
			ok = ok and f is Dictionary and subset(e.frame, f)
			for k in e.get("absent", []):
				ok = ok and f is Dictionary and not (f as Dictionary).has(k)
		if not ok:
			check(false, "%s: Ausgabe %d = %s an %s, erwartet %s" % [where, i, str(a).left(200), to, str(e).left(200)])
			return

static func subset(want: Variant, got: Variant) -> bool:
	if want is Dictionary:
		if not got is Dictionary:
			return false
		for k in want:
			if not (got as Dictionary).has(k) or not subset(want[k], got[k]):
				return false
		return true
	if want is Array:
		if not got is Array or (want as Array).size() != (got as Array).size():
			return false
		for i in (want as Array).size():
			if not subset(want[i], got[i]):
				return false
		return true
	if want is float or want is int:
		return (got is float or got is int) and float(want) == float(got)
	return want == got

# ---------- 4. Echte Sockets ----------

func test_sockets() -> void:
	var relay := NetRelayDouble.new()
	relay.auto_poll = false
	relay.web_zip_path = ""
	check(relay.start(PORT, PORT) == OK, "Nachbau lauscht auf %d" % PORT)
	var info := http_get("/info", relay)
	check(info.get("game") == "mau-mau-flip" and int(info.get("relay", 0)) == 2, "/info: %s" % str(info))
	var host := NetRelayHost.new()
	host.auto_poll = false
	host.ping_ms = 200
	var opened := []
	var msgs := []
	var closed := []
	host.ws_opened.connect(func(conn, i): opened.append([conn, i]))
	host.ws_message.connect(func(conn, t): msgs.append([conn, t]))
	host.ws_closed.connect(func(conn, code, _r): closed.append([conn, code]))
	host.open(relay.base_url())
	var all := [relay, host]
	check(wait(all, func(): return host.state == "open"), "Gastgeber-Raum offen (%s %s)" % [host.state, host.error])
	var code := host.room
	check(host.link == "http://127.0.0.1:%d/?r=%s" % [PORT, code], "Link des Raums: " + host.link)
	var rinfo := http_get("/info?room=" + code, relay)
	check(rinfo.get("room", {}).get("open") == true and rinfo.room.get("host") == true, "/info?room=: %s" % str(rinfo))
	var guest := NetClient.new()
	guest.auto_poll = false
	guest.persist_tokens = false
	guest.ping_ms = 200
	all.append(guest)
	guest.connect_relay(relay.base_url(), code.to_lower(), "Mia")
	check(wait(all, func(): return opened.size() == 1 and msgs.size() == 1), "Gast verbunden, hello kommt beim Gastgeber an")
	var conn: int = opened[0][0] if not opened.is_empty() else -1
	check(conn == NetProtocol.RELAY_CONN_BASE + 1 and bool(opened[0][1].get("online", false)), "Verbindungsnummer 1 000 001, online")
	check(not msgs.is_empty() and str(msgs[0][1]).contains("\"hello\""), "Rohtext hello")
	host.send_text(conn, NetProtocol.encode({"t": "welcome", "id": 2, "token": "abc", "host_name": "Lena"}))
	check(wait(all, func(): return guest.state == "open"), "Gast angenommen (welcome über den Vermittler)")
	# Herzschlag: beide schicken „ping“, Antworten kommen vom Vermittler, nicht vom Gastgeber
	var before := msgs.size()
	pump(all, 700)
	check(msgs.size() == before and guest.state == "open" and host.state == "open" and int(relay.stats().get("auto_replies", 0)) >= 4,
		"Herzschlag ping/pong ohne Gastgeber (%d Antworten)" % int(relay.stats().get("auto_replies", 0)))
	# Gastgeber-Verbindung bricht ab → Gast 4503, wartet; Gastgeber kommt mit Token zurück
	host._ws.close()
	host._ws = null
	host._lost("Test")
	# Beta 1.3.3: Während „away“ gilt der Gast für die Sitzung nicht als gegangen (kein ws_closed); nach der Rückkehr läuft eine Frist.
	check(host.state == "away" and closed.is_empty(), "Gastgeber getrennt → away, Gast bleibt für die Sitzung verbunden")
	host.resync_grace_ms = 600
	guest.host_away_ms = 400
	check(wait(all, func(): return host.state == "open"), "Gastgeber wieder da (Token)")
	check(host.room == code, "gleicher Raumcode nach der Rückkehr")
	check(wait(all, func(): return opened.size() == 2, 5000), "Gast verbindet nach 4503 neu")
	check(opened.size() == 2 and int(opened[1][0]) > conn, "neue Verbindungsnummer")
	check(wait(all, func(): return closed.size() == 1 and int(closed[0][0]) == conn and int(closed[0][1]) == NetProtocol.CLOSE_HOST_AWAY, 3000),
		"alte Verbindung gilt erst nach der Frist als getrennt")
	# Ende: Gast bekommt 1001
	host.close()
	check(wait(all, func(): return guest.state == "closed"), "Raum beendet → Gast endgültig getrennt")
	check(guest.close_text != "", "Grund: " + guest.close_text)
	guest.free()
	host.free()
	relay.stop()
	relay.free()

func pump(nodes: Array, ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		for n in nodes:
			if is_instance_valid(n):
				n.poll()
		OS.delay_msec(2)

func wait(nodes: Array, cond: Callable, ms := 4000) -> bool:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		pump(nodes, 4)
		if cond.call():
			return true
	return cond.call()

func http_get(path: String, relay: NetRelayDouble) -> Dictionary:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", PORT)
	var buf := PackedByteArray()
	var sent := false
	var end := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < end:
		relay.poll()
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			if not sent:
				peer.put_data(("GET %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nConnection: close\r\n\r\n" % [path, PORT]).to_ascii_buffer())
				sent = true
			var n := peer.get_available_bytes()
			if n > 0:
				buf.append_array(peer.get_data(n)[1])
				var text := buf.get_string_from_utf8()
				var cut := text.find("\r\n\r\n")
				if cut >= 0 and text.ends_with("}"):
					var d = JSON.parse_string(text.substr(cut + 4))
					return d if d is Dictionary else {}
		elif sent:
			break
		OS.delay_msec(2)
	return {}
