extends SceneTree

# Modul E2 – Vertrag zwischen Browser-Client „Lite“ (webclient/) und echtem Gastgeber, headless und ohne Browser.
#  1. Was der Client kennt, wird aus seinen Quellen gelesen (eine Quelle der Wahrheit): Phasen, hints-Felder und Ereignisse aus
#     webclient/autotest.js, Ereignis-Effekte (case '…') aus tisch.js, gesendete Aktionen aus app.js/tisch.js.
#  2. Bot-Partien mit zufälligen Regeln (MauGame + MauBot): Jede Sicht jedes Platzes hat die Felder und Typen, die der Client nutzt;
#     jede Phase und jedes Ereignis ist dem Client bekannt; jede Aktion des Clients kennt das Regelwerk; NetProtocol lässt sie durch.
#  3. NetServer liefert eine aus webclient/ gepackte Zip aus: Seite, alle eingebundenen Skripte, Mau-Töne (mau, mau_mau als m4a/ogg),
#     Schrift, Kartenbild, Katzenbild – mit passenden MIME-Typen; sfx/index.json ist gültig, nennt „mau“ und „mau_mau“, und jede
#     genannte Datei liegt vor.
# Der Ende-zu-Ende-Test mit echtem Chrome ist tools/webtest/web_e2e.ps1 (Gastgeber game/tests/web_host.gd).

const PORT := 24875
var ok := 0
var fails := 0
var web_dir := ""


func check(cond: bool, msg: String) -> void:
	if cond:
		ok += 1
	else:
		fails += 1
		print("FAIL: ", msg)


func _initialize() -> void:
	call_deferred("run")


func read_web(name: String) -> String:
	return FileAccess.get_file_as_string(web_dir.path_join(name))


# Liste von Zeichenketten aus „const NAME = [ '…', … ];“
func js_list(src: String, name: String) -> Array:
	var re := RegEx.create_from_string("const " + name + " = \\[([^\\]]*)\\]")
	var m := re.search(src)
	if m == null:
		return []
	var out: Array = []
	for s in RegEx.create_from_string("'([a-z_]+)'").search_all(m.get_string(1)):
		out.append(s.get_string(1))
	return out


# Schlüssel und Typen aus „const NAME = { key: 'typ', … };“
func js_types(src: String, name: String) -> Dictionary:
	var re := RegEx.create_from_string("const " + name + " = \\{([^}]*)\\}")
	var m := re.search(src)
	var out := {}
	if m == null:
		return out
	for s in RegEx.create_from_string("([a-z_]+): '([a-z]+)'").search_all(m.get_string(1)):
		out[s.get_string(1)] = s.get_string(2)
	return out


func js_type(v) -> String:
	match typeof(v):
		TYPE_ARRAY:
			return "array"
		TYPE_DICTIONARY:
			return "object"
		TYPE_BOOL:
			return "boolean"
		TYPE_INT, TYPE_FLOAT:
			return "number"
		TYPE_STRING:
			return "string"
	return "null"


func run() -> void:
	var t0 := Time.get_ticks_msec()
	web_dir = ProjectSettings.globalize_path("res://").path_join("../webclient").simplify_path()
	var autotest := read_web("autotest.js")
	var tisch := read_web("tisch.js")
	var app := read_web("app.js")
	check(autotest != "" and tisch != "" and app != "", "webclient/ lesbar (%s)" % web_dir)

	# ---------- 1. Was der Client kennt ----------
	var phasen := js_list(autotest, "PHASEN")
	var ereignisse := js_list(autotest, "EREIGNISSE")
	var hint_typen := js_types(autotest, "HINT_FELDER")
	var sicht_typen := js_types(autotest, "SICHT_FELDER")
	var spieler_typen := js_types(autotest, "SPIELER_FELDER")
	check(phasen.size() >= 6 and ereignisse.size() >= 20 and hint_typen.size() >= 10 and sicht_typen.size() >= 15 and spieler_typen.size() >= 8,
		"Listen in autotest.js gefunden (%d/%d/%d/%d/%d)" % [phasen.size(), ereignisse.size(), hint_typen.size(), sicht_typen.size(), spieler_typen.size()])
	var effekte := {}
	for m in RegEx.create_from_string("case '([a-z_]+)'").search_all(tisch):
		effekte[m.get_string(1)] = true
	# Ereignisse mit sichtbarem Effekt am Tisch (Rest gleicht die Sicht ab)
	for e in ["deal", "play", "draw", "skip", "skip_all", "reverse", "color", "flip", "pending", "challenge", "mau", "catch", "penalty",
			"shuffle", "round_over", "game_over", "finish", "pass", "choose_color"]:
		check(effekte.has(e), "tisch.js spielt Ereignis „%s“ ab" % e)
	var aktionen := {}
	for src in [app, tisch]:
		for m in RegEx.create_from_string("a: '([a-z_]+)'").search_all(src):
			aktionen[m.get_string(1)] = true
		for m in RegEx.create_from_string("data-a=\"([a-z_]+)\"").search_all(src):
			aktionen[m.get_string(1)] = true
	aktionen.erase("wunsch")     # nur im Client: öffnet die Farbwahl, schickt dann {a:"color"}
	for a in ["play", "draw", "keep", "challenge", "accept", "color", "mau", "catch", "next_round"]:
		check(aktionen.has(a), "Client sendet Aktion „%s“" % a)
	# Nachrichten des Gastgebers (NetHostSession, HostTable), die der Client auswertet
	var nachrichten := {}
	for m in RegEx.create_from_string("case '([a-z_]+)'").search_all(app):
		nachrichten[m.get_string(1)] = true
	for t in ["welcome", "reject", "lobby", "start", "state", "err", "notice", "pong", "bye"]:
		check(nachrichten.has(t), "app.js wertet Nachricht „%s“ aus" % t)
	# Mau für alle (AGENTS.md Nr. 21): Ton und Blase kommen aus den Ereignissen (jedes Gerät), nicht aus dem eigenen Knopf;
	# kein synthetischer Mau-Ton mehr (Nr. 20).
	var ton := read_web("ton.js")
	check(tisch.contains("mauTon(e.seat, 'mau')") and tisch.contains("mauBlase(e.seat, 'mau'"), "Ereignis „mau“ → Ton und Blase beim Rufenden")
	check(tisch.contains("mauTon(e.seat, 'mau_mau')") and tisch.contains("mauBlase(e.seat, 'mau_mau'"), "Ereignis „finish“ → „Mau-Mau!“ (Ton und große Blase)")
	var mau_knopf := app.substr(app.find("    mau() {"), 700)
	check(app.find("    mau() {") >= 0 and not mau_knopf.contains("Ton.spiele") and not mau_knopf.contains("mauTon("), "Mau-Knopf spielt selbst keinen Ton (kein doppelter Ton)")
	check(ton != "" and not ton.contains("mau(t)") and ton.contains("STUFEN_SPIEL") and ton.contains("stufeSpiel = 'aus'"), "ton.js: kein synthetischer Mau-Ton, Spieltöne standardmäßig aus")
	var blasen := js_list(tisch, "BLASEN")
	check(blasen.size() >= 4, "mindestens 4 Varianten der Mau-Blase (%s)" % ", ".join(PackedStringArray(blasen)))
	var css := read_web("style.css")
	for b in blasen:
		check(css.contains(".mau-blase.v-%s .koerper" % b), "style.css animiert die Blasen-Variante „%s“" % b)
	check(css.contains("prefers-reduced-motion") and css.contains(".mau-blase.v-schlicht"), "Mau-Blase: schlichte Variante bei reduzierten Effekten")
	check(css.contains("#tisch[data-seite=\"dunkel\"] .mau-blase"), "Mau-Blase: nachts Neon")

	# ---------- 2. Bot-Partien gegen die Sicht des Clients ----------
	var rng := RandomNumberGenerator.new()
	rng.seed = 2602
	var seen_events := {}
	var seen_phases := {}
	var seen_hints := {}
	var view_checks := 0
	var bad := {}
	var max_bytes := 0
	for gi in 40:
		var cfg := RulesFixture.random_config(rng) if gi > 0 else RuleConfig.new()
		var n := rng.randi_range(2, 6)
		var pl := RulesFixture.players(n)
		pl[0]["host"] = true
		var g := MauGame.create(cfg, pl, rng.randi())
		var events := g.start_round()
		var steps := 0
		while steps < 1500:
			for s in n:
				var v := g.view_for(s)
				view_checks += 1
				var fe := g.events_for(s, events)
				for e in fe:
					seen_events[str(e.get("e", ""))] = true
				if s == 0:
					max_bytes = maxi(max_bytes, NetProtocol.encode({"t": "state", "events": fe, "view": v}).to_utf8_buffer().size())
				seen_phases[str(v.phase)] = true
				for k in sicht_typen:
					if js_type(v.get(k)) != sicht_typen[k]:
						bad["Sicht.%s: %s statt %s" % [k, js_type(v.get(k)), sicht_typen[k]]] = true
				var h: Dictionary = v.hints
				for k in hint_typen:
					if js_type(h.get(k)) != hint_typen[k]:
						bad["hints.%s: %s statt %s" % [k, js_type(h.get(k)), hint_typen[k]]] = true
					elif hint_typen[k] == "boolean" and bool(h[k]):
						seen_hints[k] = true
				for p in v.players:
					for k in spieler_typen:
						if js_type(p.get(k)) != spieler_typen[k]:
							bad["players[].%s: %s" % [k, js_type(p.get(k))]] = true
				for c in v.hand:
					if js_type(c.get("id")) != "number" or js_type(c.get("face")) != "string":
						bad["hand[] ohne id/face"] = true
				if not (v.pending as Dictionary).is_empty() and not str(v.pending.get("kind", "")) in ["plus1", "plus5", "wuenscher_plus2", "farbjagd"]:
					bad["pending.kind " + str(v.pending.get("kind"))] = true
				if bool(h.need_color) and str(v.phase) != "color":
					bad["need_color außerhalb der Phase color"] = true
				for id in h.wild:
					if not (h.playable as Array).has(id):
						bad["hints.wild nicht in playable"] = true
				if str(v.phase) in ["round_over", "game_over"] and (v.result.get("ranking", []) as Array).size() != n:
					bad["result.ranking unvollständig"] = true
			var ph := g.phase()
			if ph == "round_over" or ph == "game_over":
				break
			# nächster Handelnder: wer etwas tun kann (Zug, Farbwahl, Anzweifeln, Erwischen)
			events = []
			for s in n:
				var a := MauBot.choose(g.view_for(s), rng.randi(), rng.randi_range(0, 2))
				if a.is_empty():
					continue
				var r := g.apply(s, a)
				if r.ok:
					events = r.events
					break
			steps += 1
		check(g.phase() in ["round_over", "game_over"], "Partie %d endet (Phase %s nach %d Schritten)" % [gi, g.phase(), steps])
	for k in bad:
		check(false, "Sicht passt nicht zum Client: " + str(k))
	check(bad.is_empty(), "%d Sichten passen Feld für Feld zum Client" % view_checks)
	for ph in seen_phases:
		check(phasen.has(ph), "Phase „%s“ ist dem Client bekannt" % ph)
	for e in seen_events:
		check(ereignisse.has(e), "Ereignis „%s“ ist dem Client bekannt" % e)
	for k in ["can_draw", "can_keep", "can_challenge", "can_accept", "can_mau", "can_next_round"]:
		check(seen_hints.has(k), "hints.%s kam in den Partien vor" % k)
	print("Sichten: %d, Phasen: %s, Ereignisse: %d Arten, größte state-Nachricht: %d Byte" % [view_checks, str(seen_phases.keys()), seen_events.size(), max_bytes])
	check(max_bytes < 60000, "state-Nachricht bleibt unter 60 KB (%d)" % max_bytes)

	# Jede Aktion des Clients kennt das Regelwerk (keine „Unbekannte Aktion.“) und übersteht NetProtocol.clean_action
	var g2 := MauGame.create(RuleConfig.new(), RulesFixture.players(3), 7)
	g2.start_round()
	for a in aktionen:
		var act := {"a": a, "card": 0, "color": "rot", "target": 1}
		check(not NetProtocol.clean_action(act).is_empty(), "NetProtocol lässt Aktion „%s“ durch" % a)
		var r := g2.apply(1, NetProtocol.clean_action(act))
		check(str(r.reason) != "Unbekannte Aktion.", "Regelwerk kennt Aktion „%s“" % a)

	# ---------- 3. Auslieferung der Dateien ----------
	await serve_check()
	print("Dauer: %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("RESULT: %d ok" % ok if fails == 0 else "%d ok, %d FAIL" % [ok, fails])
	quit(0 if fails == 0 else 1)


func add_dir(z: ZIPPacker, base: String, rel: String) -> int:
	var n := 0
	var dir := base.path_join(rel) if rel != "" else base
	for f in DirAccess.get_files_at(dir):
		z.start_file(rel.path_join(f) if rel != "" else f)
		z.write_file(FileAccess.get_file_as_bytes(dir.path_join(f)))
		z.close_file()
		n += 1
	for d in DirAccess.get_directories_at(dir):
		n += add_dir(z, base, rel.path_join(d) if rel != "" else d)
	return n


func serve_check() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://web_contract"))
	var zip_path := "user://web_contract/web.zip"
	var z := ZIPPacker.new()
	z.open(zip_path)
	var count := add_dir(z, web_dir, "")
	z.close()
	check(count > 100, "Zip aus webclient/ (%d Dateien)" % count)
	var server := NetServer.new()
	server.threaded = false
	server.auto_poll = false
	server.web_zip_path = zip_path
	root.add_child(server)
	if server.start(PORT, PORT, "127.0.0.1") != OK:
		check(false, "NetServer startet auf Port %d" % PORT)
		server.queue_free()
		return
	var index := await http_get(server, "/")
	check(int(index.status) == 200 and str(index.type).contains("text/html"), "/ liefert index.html (%s %s)" % [index.status, index.type])
	var html := (index.body as PackedByteArray).get_string_from_utf8()
	var srcs: Array = []
	for m in RegEx.create_from_string("<script src=\"([^\"]+)\"").search_all(html):
		srcs.append(m.get_string(1))
	check(srcs.size() >= 6, "index.html bindet die Skripte ein (%d)" % srcs.size())
	srcs.append_array(["mock.js", "autotest.js", "style.css"])
	for s in srcs:
		var r := await http_get(server, "/" + s)
		var want := "css" if s.ends_with(".css") else "javascript"
		check(int(r.status) == 200 and str(r.type).contains(want), "/%s (%s %s)" % [s, r.status, r.type])
	var fonts := DirAccess.get_files_at(web_dir.path_join("fonts"))
	var woff := ""
	for f in fonts:
		if f.ends_with(".woff2"):
			woff = f
			break
	for pair in [["sfx/mau.m4a", "audio/mp4"], ["sfx/mau.ogg", "audio/ogg"], ["sfx/mau_mau.m4a", "audio/mp4"], ["sfx/mau_mau.ogg", "audio/ogg"],
			["cards/hell_rot_7.webp", "image/webp"], ["cards/rueckseite.webp", "image/webp"], ["bilder/katze.webp", "image/webp"],
			["fonts/" + woff, "font/woff2"], ["wach.mp4", "video/mp4"]]:
		var r := await http_get(server, "/" + str(pair[0]))
		check(int(r.status) == 200 and str(r.type).contains(pair[1]) and (r.body as PackedByteArray).size() > 500,
			"/%s → %s (%s %s, %d Byte)" % [pair[0], pair[1], r.status, r.type, (r.body as PackedByteArray).size()])
	await sfx_index_check(server)
	server.stop()
	server.queue_free()


# sfx/index.json (AGENTS.md 20): Liste der Tondateien, die der Browser-Client statt seiner Synth-Klänge nutzt, {"name": "datei", …}
# (ton.js: String(liste[name])). Pflicht sind die Aufnahmen des Nutzers „mau“ (Mau!) und „mau_mau“ (Mau-Mau!). Jede genannte Datei
# liegt in webclient/sfx/ und wird mit passendem MIME-Typ ausgeliefert.
func sfx_index_check(server: NetServer) -> void:
	var local := FileAccess.get_file_as_string(web_dir.path_join("sfx/index.json"))
	check(local != "", "webclient/sfx/index.json vorhanden")
	var r := await http_get(server, "/sfx/index.json")
	check(int(r.status) == 200 and str(r.type).contains("json"), "/sfx/index.json ausgeliefert (%s %s)" % [r.status, r.type])
	var parsed: Variant = JSON.parse_string(local)
	check(parsed is Dictionary, "sfx/index.json ist gültiges JSON-Objekt")
	if not parsed is Dictionary:
		return
	var liste: Dictionary = parsed
	for pflicht in ["mau", "mau_mau"]:
		check(liste.has(pflicht), "sfx/index.json nennt „%s“ (%s)" % [pflicht, str(liste.keys())])
	for name in liste:
		var datei: Variant = liste[name]
		check(datei is String and str(datei) != "" and not str(datei).contains("/") and not str(datei).contains(".."),
			"sfx/index.json: „%s“ → schlichter Dateiname (%s)" % [name, str(datei)])
		if not datei is String or str(datei) == "":
			continue
		check(FileAccess.file_exists(web_dir.path_join("sfx").path_join(str(datei))), "sfx/%s (für „%s“) liegt in webclient/sfx/" % [datei, name])
		var want := "audio/mp4" if str(datei).ends_with(".m4a") else ("audio/ogg" if str(datei).ends_with(".ogg") else "audio/")
		var f := await http_get(server, "/sfx/" + str(datei))
		check(int(f.status) == 200 and str(f.type).contains(want) and (f.body as PackedByteArray).size() > 500,
			"/sfx/%s → %s (%s %s, %d Byte)" % [datei, want, f.status, f.type, (f.body as PackedByteArray).size()])


# Einfache HTTP/1.1-Abfrage (Connection: close) gegen den Server im selben Prozess
func http_get(server: NetServer, path: String) -> Dictionary:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", PORT)
	var sent := false
	var buf := PackedByteArray()
	var end := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < end:
		server.poll()
		peer.poll()
		var st := peer.get_status()
		if st == StreamPeerTCP.STATUS_CONNECTED:
			if not sent:
				peer.put_data(("GET %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nConnection: close\r\n\r\n" % [path, PORT]).to_utf8_buffer())
				sent = true
			var n := peer.get_available_bytes()
			if n > 0:
				var got := peer.get_partial_data(n)
				if int(got[0]) == OK:
					buf.append_array(got[1])
			# fertig, sobald Kopf und Content-Length vollständig da sind (falls der Server die Verbindung offen hält)
			var t := buf.get_string_from_ascii()
			var he := t.find("\r\n\r\n")
			if he >= 0:
				var cl := RegEx.create_from_string("(?i)content-length:\\s*(\\d+)").search(t.substr(0, he))
				if cl != null and buf.size() >= he + 4 + int(cl.get_string(1)):
					break
		elif st == StreamPeerTCP.STATUS_NONE or st == StreamPeerTCP.STATUS_ERROR:
			if sent:
				break
		await process_frame
	peer.disconnect_from_host()
	var text := buf.get_string_from_ascii()
	var head_end := text.find("\r\n\r\n")
	if head_end < 0:
		return {"status": 0, "type": "", "body": PackedByteArray()}
	var head := text.substr(0, head_end)
	var status := int(head.get_slice(" ", 1))
	var ctype := ""
	for line in head.split("\r\n"):
		if line.to_lower().begins_with("content-type:"):
			ctype = line.substr(13).strip_edges()
	return {"status": status, "type": ctype, "body": buf.slice(head_end + 4)}
