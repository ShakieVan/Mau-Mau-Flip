extends SceneTree
# Bildschirme zu den Hausregeln mit Zusatzkarten und zur persönlichen Einstellung „Spielbare Karten hervorheben“, headless bei
# 1600 × 720 (Basisgröße, wie das S21 quer):
#  - Regel-Editor: Zeilen für Kartentausch, Tauschrichtung (nur mit Kartentausch bedienbar), Glücksspiel und Farbe mit ablegen,
#    Kartenbilder, Kartenzahl der Partie (112 … 124) oben und im Abschnittskopf, Erkennung der Voreinstellungen (Familie enthält
#    den Kartentausch; die Richtung zählt ohne Kartentausch nicht), Übersicht mit Kartenzahl und Hausregeln.
#  - RulesBar.summary und die Regelkopfzeile der Gast-Lobby nennen die Hausregeln mit Kartenzahl.
#  - RulesText.card_help für alle neuen Karten (Kartentausch, Glücksspiel, Ablegen-Karte, Ablegen-Joker) passend zu den Regeln.
#  - Einstellungen: Schalter „Spielbare Karten hervorheben“ mit Hinweis „Nur auf diesem Gerät“, speichert sofort, Signal changed.
#  - Gerätetest N2: In der Gastgeber-Lobby sind 5 Spieler ganz sichtbar, „+“ rollt zum neuen Spieler, Start und Regeln bleiben im
#    Bild; Gast-Lobby bei 1600 × 720: Spieler, Regelkopf und „Bereit“ sichtbar, Regeländerungen des Gastgebers kommen an.
# Läuft mit eigener Einstellungsdatei (App.settings wird für die Dauer des Tests ersetzt), die echten Einstellungen bleiben unberührt.
#   godot_run.ps1 -Script res://tests/test_screens_rules.gd -Headless -Timeout 120

const CleanExit := preload("res://tests/clean_exit.gd")
const SETTINGS_PATH := "user://test_screens_rules_einstellungen.json"

var ok := 0
var failed := false
var nav: ScreenNav
var nav2: ScreenNav


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


func wait(t: float) -> void:
	await create_timer(t).timeout


func run() -> void:
	GameStarter.test_speed = 0.0
	var app := UiApp.app()
	# Eigene Einstellungsdatei statt user://einstellungen.json (ohne gespeicherte Regelsätze, sonst trügen passende Regeln deren
	# Namen). Auch ein Abbruch durch die Zeitgrenze lässt so die echten Einstellungen der App unberührt.
	var real_settings: AppSettings = app.settings if app != null else null
	if app != null:
		_remove_files(SETTINGS_PATH)
		var st := AppSettings.new(SETTINGS_PATH)
		st.set_value("name", "Tester")
		app.settings = st
	root.size = Vector2i(1600, 720)
	await frames(2)
	nav = ScreenNav.new()
	nav.autostart = false
	root.add_child(nav)
	await frames(3)
	summaries()
	card_help()
	await rules_editor()
	await settings_switch()
	await lobbies()
	if app != null and real_settings != null:
		app.settings = real_settings
		_remove_files(SETTINGS_PATH)
	if failed:
		print("FAIL: test_screens_rules")
	else:
		print("RESULT: %d ok" % ok)
	await CleanExit.finish(self, 1 if failed else 0)


# ----------------------------------------------------------------- Hilfen

func _remove_files(p: String) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(p + suffix):
			DirAccess.remove_absolute(p + suffix)


func house(swap := true, gamble := true, discard := true, base := "familie") -> RuleConfig:
	var cfg := RuleConfig.preset(base)
	cfg.swap_cards = "on" if swap else "off"
	cfg.gamble_cards = "on" if gamble else "off"
	cfg.discard_color = "on" if discard else "off"
	cfg.flip_surprise = "off"             # 0.1.4: so bleibt „alle Hausregeln“ von der neuen Familie verschieden
	cfg.swap_direction = "clockwise"
	return cfg


# Schlüssel des hervorgehobenen Knopfs einer Auswahlreihe ("" = keiner)
func chosen(row: Container) -> String:
	for b in row.get_children():
		if b is Button and (b as Button).theme_type_variation == "PrimaryButton" and b.has_meta("key"):
			return str(b.get_meta("key"))
	return ""


func choice_button(row: Container, key: String) -> Button:
	for b in row.get_children():
		if b is Button and b.has_meta("key") and str(b.get_meta("key")) == key:
			return b
	return null


func locked(row: Control) -> bool:
	for b in row.find_children("*", "BaseButton", true, false):
		if not (b as BaseButton).disabled:
			return false
	return true


func inside(inner: Rect2, outer: Rect2, tol := 1.0) -> bool:
	return outer.grow(tol).encloses(inner)


# ----------------------------------------------------------------- Kurzbeschreibungen

func summaries() -> void:
	var off := RuleConfig.preset("offiziell")
	var s := RulesBar.summary(off)
	check(not s.contains("mit ") and s.contains("7 Handkarten") and not s.contains("Karten)"), "Offiziell: keine Zusatzkarten (%s)" % s)
	check(RulesBar.summary(RuleConfig.preset("familie")).ends_with("mit Kartentausch, Glücksspiel und Farbe ablegen (124 Karten)"), "Familie: alle Zusatzkarten (124 Karten)")
	var all := house()
	check(RulesBar.summary(all).ends_with("mit Kartentausch, Glücksspiel und Farbe ablegen (124 Karten)"), "alle Hausregeln mit 124 Karten (%s)" % RulesBar.summary(all))
	check(RulesBar.summary(house(false, true, false, "offiziell")).ends_with("mit Glücksspiel (114 Karten)"), "nur Glücksspiel: 114 Karten")
	check(RulesBar.summary(house(false, false, true, "offiziell")).ends_with("mit Farbe ablegen (118 Karten)"), "nur Farbe ablegen: 118 Karten")
	var first := RulesBar.summary(all, true)
	check(first.begins_with("Mit Kartentausch, Glücksspiel und Farbe ablegen, bis zum Letzten") and not first.contains("124"),
		"Lobby-Fassung: Hausregeln vorn, ohne Kartenzahl (%s)" % first)
	check(RulesBar.extras_text(off) == "" and RulesBar.extra_names(all) == ["Kartentausch", "Glücksspiel", "Farbe ablegen"], "extra_names")
	check(RulesBar.preset_title(RuleConfig.preset("familie")) == "Familie" and RulesBar.preset_title(all) == "Eigene Regeln", "preset_title")
	check(JoinScreen.lobby_head(RuleConfig.preset("familie")) == "Familie · 124 Karten · mit Kartentausch, Glücksspiel und Farbe ablegen", "Gast-Lobby: Familie")
	check(JoinScreen.lobby_head(off) == "Offiziell · 112 Karten", "Gast-Lobby: Offiziell")
	check(JoinScreen.lobby_head(all) == "Eigene Regeln · 124 Karten · mit Kartentausch, Glücksspiel und Farbe ablegen", "Gast-Lobby: alle Hausregeln")
	check(JoinScreen.lobby_head(all, "Lena") == "Regeln von Lena · 124 Karten · mit Kartentausch, Glücksspiel und Farbe ablegen"
		and JoinScreen.lobby_head(RuleConfig.preset("familie"), "Lena") == "Familie · 124 Karten · mit Kartentausch, Glücksspiel und Farbe ablegen", "Gast-Lobby: eigene Regeln des Gastgebers heißen „Regeln von Lena“")
	# Regeltext der Gast-Lobby (RuleConfig.describe) nennt jede Hausregel
	var lines := "\n".join(PackedStringArray(all.describe()))
	check(lines.contains("Kartentausch:") and lines.contains("Glücksspiel:") and lines.contains("Farbe ablegen:") and lines.contains("124 Karten"),
		"Regelübersicht für Gäste nennt die Hausregeln und die Kartenzahl")


# ----------------------------------------------------------------- Kartenhilfe

func card_help() -> void:
	var on := house()
	var off := RuleConfig.preset("offiziell")
	var faces := {"hell_rot_tausch": 20, "dunkel_lila_tausch": 20, "hell_gluecksspiel": 50, "dunkel_gluecksspiel": 50,
		"hell_blau_ablegen": 30, "dunkel_orange_ablegen": 30, "hell_ablegen_joker": 50, "dunkel_ablegen_joker": 50}
	var titles := {"hell_rot_tausch": "Rot Kartentausch", "dunkel_lila_tausch": "Lila Kartentausch", "hell_gluecksspiel": "Glücksspiel",
		"hell_blau_ablegen": "Blau ablegen", "dunkel_orange_ablegen": "Orange ablegen", "hell_ablegen_joker": "Ablegen-Joker"}
	for key in faces:
		for cfg in [on, off]:
			var lines := RulesText.card_help(key, cfg)
			var text := "\n".join(PackedStringArray(lines))
			var tag := "%s (%s)" % [key, "an" if cfg == on else "aus"]
			check(lines.size() >= 3 and not text.contains("Unbekannte") and not text.contains("%") and not text.contains("_"), "Hilfe %s vollständig" % tag)
			check(lines[-1] == "Wert: %d Punkte." % int(faces[key]), "Hilfe %s: Punktwert (%s)" % [tag, lines[-1]])
			check(text.contains("gerade nicht im Spiel") == (cfg == off), "Hilfe %s: Hinweis „nicht im Spiel“ nur ohne die Hausregel" % tag)
	for key in titles:
		check(RulesText.face_title(key) == titles[key], "Titel %s" % key)
	# Kartentausch: Wirkung zuerst, Richtung, Farbe, letzte Karte nach Rundenende, Mau
	var t := RulesText.card_help("hell_rot_tausch", on)
	check(t[0].contains("ganze Hand") and t[0].contains("im Uhrzeigersinn"), "Kartentausch: Wirkung und Richtung (%s)" % t[0])
	check("\n".join(PackedStringArray(t)).contains("Passt auf Rot und auf jeden Kartentausch"), "Kartentausch: passt auf Rot")
	check("\n".join(PackedStringArray(t)).contains("die anderen tauschen trotzdem"), "Kartentausch bis zum Letzten: die anderen tauschen weiter")
	check("\n".join(PackedStringArray(t)).contains("muss nicht „Mau!“"), "Kartentausch: kein Mau nötig")
	var play_dir := house()
	play_dir.swap_direction = "play"
	check(RulesText.card_help("dunkel_lila_tausch", play_dir)[0].contains("aktuellen Spielrichtung"), "Kartentausch in Spielrichtung")
	var first_cfg := house(true, true, true, "offiziell")
	first_cfg.mau_call = "off"
	var tf := "\n".join(PackedStringArray(RulesText.card_help("hell_rot_tausch", first_cfg)))
	check(tf.contains("gewinnst die Runde") and not tf.contains("Mau"), "Kartentausch, Erster fertig, ohne Mau")
	# Glücksspiel
	var g := "\n".join(PackedStringArray(RulesText.card_help("hell_gluecksspiel", on)))
	check(RulesText.card_help("hell_gluecksspiel", on)[0].begins_with("Joker: passt immer") and g.contains("1:1 und 1:10")
		and g.contains("Glücksspielknopf") and g.contains("1 bis 10") and g.contains("darfst du auch aufhören"), "Glücksspiel: Ablauf (mit Aufhören)")
	check(g.contains("Ziehstrafe"), "Glücksspiel mit Stapeln: passt nicht unter einer Ziehstrafe")
	# Farbe mit ablegen
	var a := RulesText.card_help("hell_blau_ablegen", on)
	check(a[0].contains("welche deiner Karten in Blau") and "\n".join(PackedStringArray(a)).contains("Passt auf Blau"), "Ablegen-Karte: Blau (%s)" % a[0])
	var j := RulesText.card_help("dunkel_ablegen_joker", on)
	check(j[0].begins_with("Joker: passt immer") and j[0].contains("Tippe auf eine Karte der Farbe") and j[0].contains("zum Schluss die Farbe"), "Ablegen-Joker: Wirkung (%s)" % j[0])
	check("\n".join(PackedStringArray(j)).contains("Joker auf deiner Hand bleiben"), "Ablegen-Joker: Joker bleiben")
	# Wertung mit Punkten
	var pts := house(true, true, true, "klassisch500")
	check(RulesText.card_help("hell_rot_tausch", pts)[-1] == "Zählt 20 Punkte bei der Wertung.", "Kartentausch: zählt 20 Punkte")


# ----------------------------------------------------------------- Regel-Editor

func rules_editor() -> void:
	RulesBar.store(RuleConfig.preset("offiziell"))
	var rs := RulesScreen.new()
	rs.start_tab = "anpassen"
	nav.push(rs, false)
	await frames(3)
	for key in ["swap_cards", "swap_direction", "gamble_cards", "discard_color"]:
		check(rs._controls.has(key), "Editor: Zeile %s" % key)
	if not rs._controls.has("swap_cards"):
		return
	# 0.1.3: kein Anzweifeln mehr in der Oberfläche; Glücksspiel nennt das Aufhören
	var wr := rs._controls.get("wild_restriction") as Container
	var wr_keys: Array = []
	if wr != null:
		for b in wr.get_children():
			wr_keys.append(str(b.get_meta("key", "")))
	check(wr_keys == ["free", "enforce"] and chosen(wr) == "free", "Wünscher +2: nur „Immer erlaubt“/„App prüft“, Standard frei (%s)" % str(wr_keys))
	check(not rs._controls.has("wild_counts_for_bluff"), "Schalter „Joker zählen beim Anzweifeln mit“ entfällt")
	var gamble_row := rs._controls["gamble_cards"].get_parent() as Control
	var gamble_texts := ""
	for l in gamble_row.find_children("*", "Label", true, false):
		gamble_texts += (l as Label).text + " "
	check(gamble_texts.contains("aufhören") and not gamble_texts.contains("bis ein Treffer"), "Glücksspiel-Kurztext mit Aufhören")
	var sw := rs._controls["swap_cards"] as CheckButton
	var dir := rs._controls["swap_direction"] as Container
	var ga := rs._controls["gamble_cards"] as CheckButton
	var dc := rs._controls["discard_color"] as CheckButton
	var count := func() -> String:
		var texts: Array = []
		for l in rs._count_labels:
			texts.append(l.text)
		return texts[0] if texts.size() == 2 and texts[0] == texts[1] else "uneinig: " + str(texts)
	check(rs.find_child("Kartenzahl", true, false) != null and rs.find_child("KartenzahlOben", true, false) != null, "Editor: Kartenzahl oben und im Abschnitt")
	check(not sw.button_pressed and not ga.button_pressed and not dc.button_pressed and count.call() == "112 Karten", "Offiziell: Hausregeln aus, 112 Karten")
	check(locked(dir) and chosen(dir) == "clockwise", "Tauschrichtung ohne Kartentausch gesperrt")
	check(sw.has_theme_icon_override("checked") and sw.has_theme_icon_override("unchecked"), "großer Schalter (eigene Symbole)")
	# Kartenbilder der Hausregeln
	var thumbs := rs.find_children("Karten", "", true, false)
	var keys_ok := thumbs.size() == 4
	for th in thumbs:
		for k in th.get("keys"):
			if not CardTextures.has_image(str(k)):
				keys_ok = false
	check(keys_ok, "Kartenbilder: 4 Zeilen, alle Bilder vorhanden (%d)" % thumbs.size())
	# Voreinstellung Familie (0.1.4): alle Zusatzkarten an, 124 Karten, Tausch in Spielrichtung
	choice_button(rs._preset_row, "familie").pressed.emit()
	await frames(1)
	check(sw.button_pressed and ga.button_pressed and dc.button_pressed and RulesBar.current().swap_cards == "on" and count.call() == "124 Karten"
		and not locked(dir) and chosen(dir) == "play", "Familie: Zusatzkarten an, 124 Karten, Richtung bedienbar")
	check(chosen(rs._preset_row) == "familie" and RulesBar.current().preset_name() == "familie", "Familie erkannt")
	# Kartentausch aus: eigene Regeln; wieder an: Familie
	sw.button_pressed = false
	await frames(1)
	check(RulesBar.current().swap_cards == "off" and RulesBar.current().preset_name() == "" and chosen(rs._preset_row) == "", "Familie ohne Kartentausch = eigene Regeln")
	check(locked(dir) and count.call() == "120 Karten", "ohne Kartentausch: Richtung gesperrt, 120 Karten")
	sw.button_pressed = true
	await frames(1)
	check(RulesBar.current().preset_name() == "familie" and chosen(rs._preset_row) == "familie", "Kartentausch wieder an: Familie")
	# Richtung im Uhrzeigersinn: eigene Regeln; zurück in Spielrichtung: Familie
	choice_button(dir, "clockwise").pressed.emit()
	await frames(1)
	check(RulesBar.current().swap_direction == "clockwise" and chosen(rs._preset_row) == "" and chosen(dir) == "clockwise", "Im Uhrzeigersinn: eigene Regeln")
	# 0.1.3: vier Richtungen, umbrechend in der Zeile
	var keys: Array = []
	for b in dir.get_children():
		keys.append(str(b.get_meta("key", "")))
	check(keys == ["clockwise", "counter", "play", "against"] and dir is HFlowContainer, "Tauschrichtung: 4 Knöpfe umbrechend (%s)" % str(keys))
	var right_edge := rs._editor.get_global_rect().end.x
	var fits := true
	for b in dir.get_children():
		if (b as Control).get_global_rect().end.x > right_edge + 1.0:
			fits = false
	check(fits, "Tauschrichtung: alle Knöpfe im Bild")
	for k in ["counter", "against"]:
		choice_button(dir, k).pressed.emit()
		await frames(1)
		check(RulesBar.current().swap_direction == k and chosen(dir) == k, "Tauschrichtung %s" % k)
	choice_button(dir, "play").pressed.emit()
	await frames(1)
	check(chosen(rs._preset_row) == "familie", "In Spielrichtung: wieder Familie")
	# Offiziell mit Richtung „in Spielrichtung“ und Kartentausch aus bleibt Offiziell (die Richtung zählt dann nicht)
	choice_button(rs._preset_row, "offiziell").pressed.emit()
	sw.button_pressed = true
	choice_button(dir, "play").pressed.emit()
	sw.button_pressed = false
	await frames(1)
	check(RulesBar.current().swap_direction == "play" and RulesBar.current().preset_name() == "offiziell" and chosen(rs._preset_row) == "offiziell",
		"Richtung ohne Kartentausch zählt nicht: Offiziell")
	# Gesperrte Richtung lässt sich nicht umstellen
	check(choice_button(dir, "clockwise").disabled, "gesperrter Knopf")
	# Glücksspiel und Farbe ablegen: Kartenzahl 114 → 120 → 124
	ga.button_pressed = true
	await frames(1)
	check(RulesBar.current().gamble_cards == "on" and count.call() == "114 Karten", "Glücksspiel: 114 Karten (%s)" % count.call())
	dc.button_pressed = true
	await frames(1)
	check(RulesBar.current().discard_color == "on" and count.call() == "120 Karten", "Glücksspiel + Farbe ablegen: 120 Karten (%s)" % count.call())
	sw.button_pressed = true
	await frames(1)
	check(RulesBar.current().card_count() == 124 and count.call() == "124 Karten" and chosen(rs._preset_row) == "", "alle drei: 124 Karten, eigene Regeln")
	# Offiziell setzt die Zusatzkarten zurück, Familie schaltet sie wieder ein
	rs.apply_preset("offiziell")
	await frames(1)
	check(not ga.button_pressed and not dc.button_pressed and not sw.button_pressed and count.call() == "112 Karten", "Voreinstellung setzt die Schalter")
	rs.apply_preset("familie")
	await frames(1)
	check(ga.button_pressed and dc.button_pressed and sw.button_pressed and count.call() == "124 Karten" and RulesBar.current().flip_surprise == "on",
		"Familie: Schalter an, Flip-Überraschung an")
	# Flip dreht (1.0.2): Familie „Nur die gelegte Karte“; „Ganze Ablage“ macht eigene Regeln daraus
	var fm := rs._controls["flip_mode"] as Container
	check(chosen(fm) == "card" and choice_button(fm, "pile").text == "Ganze Ablage (offiziell)" and choice_button(fm, "card").text == "Nur die gelegte Karte",
		"Flip dreht: Zeile mit beiden Werten, Familie = nur die Karte")
	choice_button(fm, "pile").pressed.emit()
	await frames(1)
	check(RulesBar.current().flip_mode == "pile" and chosen(rs._preset_row) == "", "Flip dreht ganze Ablage: eigene Regeln")
	choice_button(fm, "card").pressed.emit()
	await frames(1)
	check(chosen(rs._preset_row) == "familie", "Flip dreht nur die Karte: wieder Familie")
	# Übersicht
	RulesBar.store(house())
	rs.cfg = RulesBar.current()
	rs._show_tab("uebersicht")
	await frames(2)
	var ov := rs._overview_text.text
	check(ov.contains("Eigene Regeln · 124 Karten · Hausregeln: Kartentausch, Glücksspiel und Farbe ablegen"), "Übersicht: Kopf mit Kartenzahl und Hausregeln")
	check(ov.contains("[b]Kartentausch[/b]") and ov.contains("[b]Glücksspiel[/b]") and ov.contains("[b]Farbe ablegen[/b]"), "Übersicht: Abschnitte der Hausregeln")
	RulesBar.store(RuleConfig.preset("familie"))
	rs.cfg = RulesBar.current()
	rs._show_tab("uebersicht")
	check(rs._overview_text.text.contains("Voreinstellung: Familie · 124 Karten · Hausregeln: Kartentausch, Glücksspiel und Farbe ablegen"), "Übersicht: Familie mit 124 Karten")
	nav.go_back()
	await wait(0.3)


# ----------------------------------------------------------------- Einstellungen

func settings_switch() -> void:
	var app := UiApp.app()
	nav.push(SettingsScreen.new(), false)
	await frames(3)
	var st := nav.top()
	var sw := st.find_child("Hervorheben", true, false) as CheckButton
	check(sw != null, "Einstellungen: Schalter „Spielbare Karten hervorheben“")
	if sw == null or app == null:
		nav.go_back()
		return
	var row := sw.get_parent()
	var texts := ""
	for l in row.find_children("*", "Label", true, false):
		texts += (l as Label).text + "|"
	check(texts.contains("Spielbare Karten hervorheben") and texts.contains("Nur auf diesem Gerät"), "Bezeichnung und Hinweis „Nur auf diesem Gerät“ (%s)" % texts)
	check(sw.button_pressed == bool(UiApp.setting("hervorheben", true)), "Schalter zeigt die Einstellung")
	var got := []
	var on_changed := func(key: String, value: Variant) -> void:
		if key == "hervorheben":
			got.append(value)
	app.settings.changed.connect(on_changed)
	sw.button_pressed = true
	sw.button_pressed = false
	check(app.settings.get_value("hervorheben", true) == false and got.has(false), "aus: gespeichert, changed gemeldet")
	check(AppSettings.new(app.settings.path).get_value("hervorheben") == false, "aus: in der Datei")
	sw.button_pressed = true
	check(app.settings.get_value("hervorheben", false) == true and got.back() == true, "wieder an")
	app.settings.changed.disconnect(on_changed)
	# Die Regeln kennen keine solche Option (persönlich, nie eine Regel des Gastgebers)
	check(not RuleConfig.keys().has("hervorheben") and not RuleConfig.new().to_dict().has("hervorheben"), "keine Regeloption")
	nav.go_back()
	await wait(0.3)


# ----------------------------------------------------------------- Lobbys (N2)

func lobbies() -> void:
	RulesBar.store(RuleConfig.preset("familie"))
	var lobby := HostLobbyScreen.new()
	nav.push(lobby, false)
	await frames(3)
	var host := lobby.host
	check(host != null and host.port() > 0, "Lobby offen")
	if host == null or host.port() <= 0:
		return
	host.autosave = false                 # einen gespeicherten Spielstand der App nicht anrühren
	check(lobby._rules.compact and lobby._rules._head.text == "Familie · 124 Karten","Lobby: Regeln kompakt mit Kartenzahl (%s)" % lobby._rules._head.text)
	check(lobby._rules._summary.text.begins_with("Mit Kartentausch"), "Lobby: Hausregeln vorn in der Kurzbeschreibung")
	# App-Gast über „Beitreten“
	nav2 = ScreenNav.new()
	nav2.autostart = false
	root.add_child(nav2)
	await frames(2)
	var join := JoinScreen.new()
	nav2.push(join, false)
	await frames(2)
	join.join("127.0.0.1", host.port())
	var deadline := Time.get_ticks_msec() + 6000
	while (host.lobby().get("players", []) as Array).size() < 2 and Time.get_ticks_msec() < deadline:
		await frames(1)
	for i in 3:
		host.add_bot()
	lobby.show_page(1, false)             # Beta 1.0.2: Spielerliste rechts vom Einladen-Bereich
	await wait(0.4)
	# Gastgeber: 5 Spieler ganz sichtbar, Start und Regeln im Bild
	var screen := Rect2(Vector2.ZERO, Vector2(1600, 720))
	var area := lobby._scroll.get_global_rect()
	var rows := lobby._list.get_children()
	var all_in := rows.size() == 5
	for r in rows:
		if not inside((r as Control).get_global_rect(), area):
			all_in = false
	check(all_in, "Lobby 1600 × 720: alle 5 Spieler ganz sichtbar (%d Zeilen, Liste %s)" % [rows.size(), str(area)])
	check(inside(lobby._start.get_global_rect(), screen) and inside(lobby._rules.get_global_rect(), screen), "Lobby: Start und Regeln im Bild")
	check(lobby._count.text == "5 von 10 Spielern", "Lobby: Spielerzahl (%s)" % lobby._count.text)
	# Gast: Spieler, Regelkopf und „Bereit“ sichtbar
	deadline = Time.get_ticks_msec() + 3000
	while join._lobby_list.get_child_count() < 5 and Time.get_ticks_msec() < deadline:
		await frames(1)
	await frames(3)
	var garea := (join._lobby_list.get_parent() as Control).get_global_rect()
	var grows := join._lobby_list.get_children()
	var g_in := grows.size() == 5
	var g_rects := []
	for r in grows:
		g_rects.append((r as Control).get_global_rect())
		if not inside((r as Control).get_global_rect(), garea):
			g_in = false
	check(g_in, "Gast-Lobby 1600 × 720: alle 5 Spieler sichtbar (%d, Liste %s, Zeilen %s)" % [grows.size(), str(garea), str(g_rects)])
	check(join._ready_btn.is_visible_in_tree() and inside(join._ready_btn.get_global_rect(), screen), "Gast-Lobby: „Bereit“ im Bild (%s)" % str(join._ready_btn.get_global_rect()))
	check(join._lobby_head.text == "Familie · 124 Karten · mit Kartentausch, Glücksspiel und Farbe ablegen" and inside(join._lobby_head.get_global_rect(), screen),
		"Gast-Lobby: Regelkopf sichtbar (%s)" % join._lobby_head.text)
	# Regeländerung des Gastgebers kommt beim Gast an
	var all := house()
	RulesBar.store(all)
	lobby._rules.refresh()
	host.set_rules(all)
	deadline = Time.get_ticks_msec() + 3000
	while not join._lobby_head.text.begins_with("Regeln von ") and Time.get_ticks_msec() < deadline:
		await frames(1)
	check(join._lobby_head.text.begins_with("Regeln von ") and join._lobby_head.text.ends_with(" · 124 Karten · mit Kartentausch, Glücksspiel und Farbe ablegen"),
		"Gast-Lobby: neue Regeln, aus Sicht des Gastes „Regeln von …“ (%s)" % join._lobby_head.text)
	check(lobby._rules._head.text == "Eigene Regeln · 124 Karten", "Lobby: Regelkopf nach Änderung")
	# „+“ bis 10 Spieler: die Liste rollt zum neuen Spieler
	for i in 5:
		lobby._bot_plus.pressed.emit()
		await frames(2)
	await wait(0.3)
	var last := lobby._list.get_child(lobby._list.get_child_count() - 1) as Control
	check(lobby._list.get_child_count() == 10 and lobby._scroll.scroll_vertical > 0 and inside(last.get_global_rect(), lobby._scroll.get_global_rect()),
		"Lobby: nach „+“ ist der neue Spieler sichtbar (Bildlauf %d)" % lobby._scroll.scroll_vertical)
	check(lobby._bot_plus.disabled, "Lobby: bei 10 Spielern kein „+“ mehr")
	# Pfeil nach vorn beim letzten: Liste bleibt beim verschobenen Spieler
	var last_id := int(str(last.name).trim_prefix("Spieler"))
	lobby._move(last_id, -1)
	await frames(3)
	await wait(0.2)
	var moved := lobby._list.find_child("Spieler%d" % last_id, false, false) as Control
	check(moved != null and moved.get_index() == 8 and inside(moved.get_global_rect(), lobby._scroll.get_global_rect()), "Lobby: verschobener Spieler bleibt sichtbar")
	join._back_to_search()
	host.leave()
	nav2.queue_free()
	nav.go_back()
	await wait(0.3)
