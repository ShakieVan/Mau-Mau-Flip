extends SceneTree
# Englische Fassung (Beta 1.2.2): Lückentest und Prüfung der Übersetzungsmechanik (I18n, game/i18n/*.po, webclient/i18n*.js).
#
# Immer streng (Fehler = FAIL):
#   - .po-Dateien lesbar, keine msgid doppelt (auch nicht über Dateien hinweg), Platzhalter in msgid und msgstr gleich.
#   - Mechanik: Englisch einstellen übersetzt, Deutsch bleibt Quelle; Bausteine (lt) ergeben deutsch genau hints.text.
#   - Bot-Partien: Hinweise (hints.lt) und Ablehnungsgründe (reason_lt) rendern deutsch identisch zum gesendeten Text.
# Lücken (noch deutsche Texte in englischer Anzeige, msgid ohne msgstr) – je nach UMFANG:
#   UMFANG=bericht  nur melden (Zeilen „LÜCKE: …“ und Summe), nicht scheitern      (Standard bis zum Ende von Beta 1.2.2)
#   UMFANG=streng   jede Lücke ist ein FAIL
# Eingesammelt wird aus: Hauptmenü, Einstellungen, Regeln, Übung, Weitergeben, WLAN (Labels, Knöpfe, Tooltips, Platzhalter,
# RichText), dem Tisch-Demo-Ablauf (Overlays, Rundenende), RulesText (Übersicht, Bedienung, Kartenhilfe aller Gesichter),
# Hinweisen und Ablehnungsgründen aus Bot-Partien und allem, was während des Laufs durch I18n.t ging (I18n.collect).
# Browser-Seite: test_web_contract prüft, dass jeder in t(...) verwendete Text im englischen Wörterbuch steht.
#   godot_run.ps1 -Script res://tests/test_i18n.gd -Headless -Timeout 300   (UMFANG=streng über -EnvPairs)

const CleanExit := preload("res://tests/clean_exit.gd")
const STANDARD_UMFANG := "streng"

# In jeder Sprache gleich (Glossar: unübersetzt)
const KEEP := ["Mau-Mau Flip", "Mau-Mau!", "Mau!", "Mau-Mau", "Mao-Mao", "Mao", "Deutsch", "English", "ShakieVan", "Quick Share"]
const GERMAN_WORDS := ["und", "der", "die", "das", "den", "dem", "nicht", "ist", "du", "dein", "deine", "deinen", "mit", "für",
	"oder", "eine", "einen", "ein", "Karte", "Karten", "Spieler", "Runde", "Partie", "zurück", "Zurück", "Einstellungen", "Regeln",
	"wähle", "Wähle", "lege", "zieh", "Gastgeber", "Gast", "Seite", "Farbe", "Bitte", "bitte", "noch", "keine", "auf", "Aus",
	"Rot", "Gelb", "Blau", "Lila", "Aussetzen", "Wünscher", "Farbjagd", "Ziehen", "Legen", "Spiel", "Hausregeln", "Weitergeben",
	"Übung", "Ton", "Schrift", "Neu", "Starten", "Abbrechen", "Speichern", "Laden", "Löschen", "jetzt", "Jetzt", "wird", "sind"]

var ok := 0
var failed := false
var strict := false
var gaps := {}                 # Text → Fundort
var unknown := {}              # Text ohne msgid und unübersetzt (nur Hinweis: kann ein Name sein)
var po_ids := {}               # msgid → Datei
var po_empty := {}             # msgid ohne msgstr → Datei


func _initialize() -> void:
	call_deferred("run")


func check(cond: bool, what: String) -> void:
	if cond:
		ok += 1
	else:
		failed = true
		print("FAIL: " + what)


func frames(n := 2) -> void:
	for i in n:
		await process_frame


func run() -> void:
	var umfang := OS.get_environment("UMFANG")
	strict = (umfang if umfang != "" else STANDARD_UMFANG) == "streng"
	GameStarter.test_speed = 0.0
	check(I18n.language() == "de", "Testlauf startet auf Deutsch (I18n.forced_test), ist %s" % TranslationServer.get_locale())
	check_po_files()
	check_mechanics()
	check_bot_games()
	I18n.set_language("en")
	I18n.collect = true
	I18n.seen.clear()
	collect_rules_text()
	scan_sources()
	await collect_screens()
	await collect_table()
	for k in I18n.seen:
		consider(str(I18n.seen[k]), "I18n.t(%s)" % str(k).left(60))
	I18n.collect = false
	I18n.set_language("de")
	check(I18n.t("Einstellungen") == "Einstellungen", "zurück auf Deutsch")
	report()
	await CleanExit.finish(self, 1 if failed else 0)


# --- .po-Dateien ---

func check_po_files() -> void:
	for path in I18n.FILES:
		var abs_path := ProjectSettings.globalize_path(path)
		check(FileAccess.file_exists(path), "Datei fehlt: " + path)
		if not FileAccess.file_exists(path):
			continue
		var entries := parse_po(FileAccess.get_file_as_string(path))
		check(entries.size() > 0, "keine Einträge in " + abs_path)
		for e in entries:
			var id := str(e[0])
			var s := str(e[1])
			if id == "":
				continue
			if po_ids.has(id):
				check(false, "msgid doppelt (%s und %s): %s" % [po_ids[id], path.get_file(), id])
			po_ids[id] = path.get_file()
			if s == "":
				po_empty[id] = path.get_file()
				continue
			var a := I18n.placeholders(id)
			var b := I18n.placeholders(s)
			check(a == b, "Platzhalter ungleich in %s: „%s“ %s → „%s“ %s" % [path.get_file(), id, str(a), s, str(b)])
	check(TranslationServer.get_loaded_locales().has("en"), "englische Übersetzung geladen (project.godot)")


# Einfacher gettext-Leser: [[msgid, msgstr], …] (mehrzeilige Strings, \n \" \\)
static func parse_po(text: String) -> Array:
	var out: Array = []
	var cur_id := ""
	var cur_str := ""
	var field := ""
	var have := false
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#") or line == "":
			continue
		if line.begins_with("msgid "):
			if have:
				out.append([cur_id, cur_str])
			cur_id = _unquote(line.substr(6))
			cur_str = ""
			field = "id"
			have = true
		elif line.begins_with("msgstr "):
			cur_str = _unquote(line.substr(7))
			field = "str"
		elif line.begins_with("\""):
			if field == "id":
				cur_id += _unquote(line)
			elif field == "str":
				cur_str += _unquote(line)
	if have:
		out.append([cur_id, cur_str])
	return out


static func _unquote(s: String) -> String:
	var t := s.strip_edges()
	if t.length() >= 2 and t.begins_with("\"") and t.ends_with("\""):
		t = t.substr(1, t.length() - 2)
	return t.replace("\\n", "\n").replace("\\\"", "\"").replace("\\\\", "\\")


# --- Mechanik ---

func check_mechanics() -> void:
	var lt: Array = [I18n.part("%s ist dran.", ["Lena"]), "Denk an „Mau!“"]
	check(I18n.render(lt, false) == "Lena ist dran. Denk an „Mau!“", "Bausteine deutsch")
	var nested: Array = [I18n.part("Du bist dran – %s.", [I18n.tr_arg(I18n.part("lege %s oder %s", [I18n.tr_arg("Blau"), I18n.tr_arg(I18n.part("eine %d", [9]))]))])]
	check(I18n.render(nested, false) == "Du bist dran – lege Blau oder eine 9.", "verschachtelte Bausteine deutsch: " + I18n.render(nested, false))
	# JSON-Weg (Zahlen kommen als float)
	var back: Variant = JSON.parse_string(JSON.stringify(nested))
	check(I18n.render(back, false) == I18n.render(nested, false), "Bausteine überstehen JSON")
	check(I18n.msg_text({"text": "Abgelehnt."}) == "Abgelehnt." and I18n.msg_text({}, "Das geht gerade nicht.") == "Das geht gerade nicht.", "msg_text deutsch")
	check(I18n.placeholders("%s hat %d Karten (%.1f %%)") == ["%s", "%d", "%.1f"], "Platzhalter erkannt")
	I18n.set_language("en")
	check(I18n.english() and I18n.t("Einstellungen") == "Settings", "Englisch: Einstellungen → Settings (%s)" % I18n.t("Einstellungen"))
	check(I18n.render(lt) == "Lena's turn. Remember “Mau!”", "Bausteine englisch: " + I18n.render(lt))
	check(I18n.render(back) == "Your turn – play Blue or a 9.", "verschachtelt englisch: " + I18n.render(back))
	check(I18n.t("Unbekannter Text ohne Übersetzung") == "Unbekannter Text ohne Übersetzung", "unbekannter Text bleibt")
	var lbl := Label.new()
	lbl.text = "Einstellungen"
	root.add_child(lbl)
	check(lbl.atr(lbl.text) == "Settings", "Label übersetzt sich selbst")
	lbl.queue_free()
	I18n.set_language("de")
	check(I18n.t("Einstellungen") == "Einstellungen" and I18n.render(lt) == "Lena ist dran. Denk an „Mau!“", "Deutsch: Quelle unverändert")
	check(I18n.resolve("de") == "de" and I18n.resolve("en") == "en" and I18n.resolve("auto") in ["de", "en"], "Einstellung auflösen")
	check(AppSettings.defaults().get(I18n.SETTING) == "auto" and AppSettings.sanitize(I18n.SETTING, "fr") == null
		and AppSettings.sanitize(I18n.SETTING, "en") == "en", "Einstellung „sprache“: Standard auto, nur auto/de/en")


# --- Bot-Partien: Hinweise und Ablehnungsgründe als Bausteine ---

func check_bot_games() -> void:
	var texts := {}
	var mism := 0
	for i in 12:
		var rng := RandomNumberGenerator.new()
		rng.seed = 4711 * i + 5
		var cfg := RulesFixture.random_config(rng)
		var n := rng.randi_range(2, 6)
		var g := MauGame.create(cfg, RulesFixture.players(n, "bot"), rng.randi())
		g.start_round()
		var steps := 0
		while g.state in MauGame.PLAY_PHASES and steps < 400:
			steps += 1
			for s in n:
				var h: Dictionary = g.view_for(s).hints
				var lt: Array = h.get("lt", [])
				if I18n.render(lt, false) != str(h.text):
					mism += 1
					if mism <= 3:
						print("Bausteine ≠ Text: „%s“ vs „%s“" % [I18n.render(lt, false), h.text])
				texts[JSON.stringify(lt)] = lt
			# ein ungültiger Zug eines anderen Platzes und eine zufällige Karte des Spielers am Zug → Ablehnungsgründe
			var cur := g.current_seat()
			var other := (cur + 1) % n
			var hand: Array = g.hands[cur]
			for r in [g.apply(other, {"a": "draw"}), g.apply(cur, {"a": "play", "card": int(hand[rng.randi_range(0, hand.size() - 1)]) if not hand.is_empty() else -1, "color": "keine"})]:
				if not bool(r.ok):
					var rl: Array = r.get("reason_lt", [])
					if I18n.render(rl, false) != str(r.reason):
						mism += 1
						print("reason_lt ≠ reason: „%s“ vs „%s“" % [I18n.render(rl, false), r.reason])
					texts[JSON.stringify(rl)] = rl
				else:
					break
			if g.state not in MauGame.PLAY_PHASES:
				break
			var act := MauBot.choose(g.view_for(g.current_seat()), rng.randi(), 1)
			if act.is_empty():
				break
			g.apply(g.current_seat(), act)
	check(mism == 0, "Bausteine ergeben deutsch genau den gesendeten Text (%d Abweichungen)" % mism)
	check(texts.size() > 20, "genug verschiedene Hinweise gesehen (%d)" % texts.size())
	I18n.set_language("en")
	for k in texts:
		consider(I18n.render(texts[k]), "Hinweis/Grund " + str(k).left(80))
	I18n.set_language("de")


# --- RulesText ---

func collect_rules_text() -> void:
	for preset in RuleConfig.preset_names():
		var cfg := RuleConfig.preset(str(preset))
		for sec in RulesText.overview(cfg):
			for v in (sec as Dictionary).values():
				if v is String:
					consider(I18n.t(v), "RulesText.overview")
		for sec in RulesText.controls(cfg):
			for v in (sec as Dictionary).values():
				if v is String:
					consider(I18n.t(v), "RulesText.controls")
	var all_cfg := RuleConfig.preset("familie")
	for key in TableSamples.faces_light() + TableSamples.faces_dark():
		for line in RulesText.card_help(key, all_cfg):
			consider(I18n.t(line), "Kartenhilfe " + key)
		consider(I18n.t(RulesText.face_title(key)), "Kartenname " + key)


# --- Bildschirme ---

func collect_screens() -> void:
	var nav := ScreenNav.new()
	nav.autostart = false
	root.add_child(nav)
	await frames(2)
	for screen in [MainMenuScreen.new(), SettingsScreen.new(), RulesScreen.new(), SoloSetupScreen.new(), PassSetupScreen.new(), WlanScreen.new()]:
		nav.push(screen, false)
		await frames(3)
		collect_nodes(screen, screen.get_script().resource_path.get_file())
		nav.pop(false)
		await frames(2)
	nav.queue_free()
	await frames(2)


func collect_table() -> void:
	var demo: Control = load("res://scenes/dev/table_demo.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	demo.set("auto", false)
	Engine.time_scale = 8.0
	var steps: int = (demo.get("steps") as Array).size()
	for i in steps:
		demo.call("next_step")
		var guard := 0
		while (demo.get("table") as TableView).director.is_busy() and guard < 2000:
			await process_frame
			guard += 1
		collect_nodes(demo, "Tisch (Schritt %d)" % i)
	Engine.time_scale = 1.0
	demo.queue_free()
	await frames(2)


func collect_nodes(node: Node, where: String) -> void:
	if node is Control:
		var c := node as Control
		if c.tooltip_text != "":
			consider(c.atr(c.tooltip_text), where + " Tooltip " + str(c.name))
	if node is Label:
		consider_node(node, (node as Label).text, where + " " + str(node.name))
	elif node is Button:
		consider_node(node, (node as Button).text, where + " " + str(node.name))
	elif node is LineEdit:
		consider(node.atr((node as LineEdit).placeholder_text), where + " Platzhalter " + str(node.name))
	elif node is RichTextLabel:
		consider((node as RichTextLabel).get_parsed_text(), where + " " + str(node.name))
	for ch in node.get_children():
		collect_nodes(ch, where)




# --- Quelltext-Scan (Bereich B: Tisch und Regeltexte): jeder Text, der an I18n.t/_t/I18n.part/toast/show_notice geht, braucht eine msgid ---

const SCAN_DIRS := ["res://scripts/ui", "res://scripts/rules", "res://scripts/game"]
const SCAN_SCREENS := ["rules_screen.gd", "rules_bar.gd"]


func scan_sources() -> void:
	var re := RegEx.new()
	re.compile("(?:I18n\\.t|\\b_t|I18n\\.part|\\.toast|show_notice)\\(\"((?:[^\"\\\\]|\\\\.)*)\"")
	var files: Array[String] = []
	for d in SCAN_DIRS:
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				files.append(d + "/" + f)
	for f in SCAN_SCREENS:
		files.append("res://scripts/ui/screens/" + f)
	var n := 0
	for path in files:
		var src := FileAccess.get_file_as_string(path)
		for m in re.search_all(src):
			var t := m.get_string(1).replace("\\\"", "\"").replace("\\n", "\n").replace("\\\\", "\\")
			n += 1
			if t.strip_edges() == "" or KEEP.has(t) or not _has_letter(t):
				continue
			if not po_ids.has(t):
				gaps[t] = "Quelltext " + path.get_file()
	check(n > 100, "Quelltext-Scan fand Aufrufe (%d)" % n)


static func _has_letter(t: String) -> bool:
	for ch in t:
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or "äöüÄÖÜß".contains(ch):
			return true
	return false
# --- Lücken ---

func consider(text: String, where: String) -> void:
	var t := text.strip_edges()
	if t == "" or gaps.has(t):
		return
	if po_empty.has(t) or looks_german(t):
		gaps[t] = where


static func looks_german(text: String) -> bool:
	var t := text
	for k in KEEP:
		t = t.replace(k, "")
	var anon := RegEx.create_from_string("Spieler \\d+")   # Ersatznamen sind Daten, keine Texte
	t = anon.sub(t, "", true)
	for ch in "äöüÄÖÜß":
		if t.contains(ch):
			return true
	var words := PackedStringArray()
	var cur := ""
	for ch in t:
		if ch.is_valid_identifier() or ch == "ä" or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z"):
			cur += ch
		else:
			if cur != "":
				words.append(cur)
			cur = ""
	if cur != "":
		words.append(cur)
	for w in words:
		if GERMAN_WORDS.has(w):
			return true
	return false


func report() -> void:
	var keys := gaps.keys()
	keys.sort()
	for k in keys:
		print("LÜCKE: %s  [%s]" % [str(k).replace("\n", " ⏎ ").left(160), gaps[k]])
	for id in po_empty:
		if not gaps.has(id):
			print("LÜCKE: msgid ohne msgstr (%s): %s" % [po_empty[id], str(id).left(160)])
	var uk := unknown.keys()
	uk.sort()
	for k in uk:
		print("UNBEKANNT: %s  [%s]" % [str(k).left(120), unknown[k]])
	var total := gaps.size() + po_empty.size()
	print("Lücken: %d (%s)" % [total, "streng" if strict else "bericht"])
	if strict:
		check(total == 0, "keine Lücken in der englischen Fassung (%d)" % total)
	if failed:
		print("FAIL: test_i18n")
	else:
		print("RESULT: %d ok" % ok)


# Text eines Knotens: übersetzt prüfen; ohne msgid und unverändert → Hinweis „UNBEKANNT“ (kann ein Name sein)
func consider_node(node: Node, raw: String, where: String) -> void:
	var tr_text: String = node.atr(raw)
	consider(tr_text, where)
	var t := raw.strip_edges()
	if tr_text == raw and t != "" and _has_letter(t) and not KEEP.has(t) and not po_ids.has(t) and not unknown.has(t):
		unknown[t] = where
