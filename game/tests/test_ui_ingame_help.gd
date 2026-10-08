extends SceneTree
# Regeln und Hilfe im Spiel (Beta 1.0.2): Spielmenü → „Regeln ansehen“ / „So geht's“ (IngameHelp), ohne die Partie zu verlassen.
#   Zurück-Taste schließt die Überlagerung, Tisch bleibt; Regeln aus view.rules samt „Besondere Karten“; Bedienung passend zu den
#   Hausregeln; Nacht; Schriftstufe; Sichtschutz (Weitergeben) schließt sie und lässt sie nicht öffnen (Regel 15).
#   godot_run.ps1 -Script res://tests/test_ui_ingame_help.gd -Headless
# Kontrollbild (mit Renderer, ohne -Headless): -EnvPairs 'SHOT=1' → docs/module/F2_regeln_im_spiel.png (Tag, Reiter Regeln)

const CleanExit := preload("res://tests/clean_exit.gd")

var ok := 0
var failed := false
var nav: ScreenNav
var ts: TableScreen


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


func _texts(n: Node, out: Array) -> void:
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		_texts(c, out)


func run() -> void:
	GameStarter.test_speed = 0.0
	root.size = Vector2i(1600, 720)
	nav = ScreenNav.new()
	root.add_child(nav)
	await frames(3)
	var cfg := RuleConfig.preset("familie")
	var players := [{"name": "Du", "kind": "human"}, {"name": "Mimi", "kind": "bot"}, {"name": "Socke", "kind": "bot"}]
	var src := GameStarter.local("solo", cfg, players, 1)
	ts = TableScreen.create(src, func() -> void: src.start())
	nav.push(ts, false)
	var deadline := Time.get_ticks_msec() + 15000
	while ts.view.is_empty() and Time.get_ticks_msec() < deadline:
		await frames(1)
	check(not ts.view.is_empty(), "Sicht da")

	# Spielmenü: beide neuen Wahlmöglichkeiten
	ts.on_back()
	await frames(2)
	var confirm: ConfirmBox = ts.get("_confirm")
	check(confirm != null, "Rückfrage offen")
	var rb: Button = confirm.find_child("RegelnAnsehen", true, false) if confirm != null else null
	var hb: Button = confirm.find_child("SoGehts", true, false) if confirm != null else null
	check(rb != null and rb.text == "Regeln ansehen", "Knopf „Regeln ansehen“")
	check(hb != null and hb.text == "So geht's", "Knopf „So geht's“")
	rb.pressed.emit()
	await frames(3)
	check(ts.is_help_open(), "Regeln offen")
	check(ts.get("_confirm") == null, "Rückfrage zu")
	var help: IngameHelp = ts.get("_help")
	check(help.tab == "regeln" and not help.night, "Reiter Regeln, Tag")
	var t: Array = []
	_texts(help, t)
	check(t.has("Besondere Karten") and t.has("Ziel") and t.has("Glücksspiel"), "Regeln mit besonderen Karten und Hausregel")
	check(not t.has("Weitere besondere Karten"), "kein Hinweis aufs Anpassen")
	check(help.find_child("Karte_gluecksspiel", true, false) != null, "Glücksspiel-Joker unter Besondere Karten")
	check(help.find_child("Bilder", true, false) != null, "Kartenbilder")
	var head_txt := str(t[0]) if not t.is_empty() else ""
	check(head_txt.begins_with("Eigene Regeln") or head_txt.begins_with("Voreinstellung"), "Kopfzeile: " + head_txt)

	if OS.get_environment("SHOT") == "1":
		await create_timer(0.6).timeout
		var img := root.get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://").path_join("../docs/module/F2_regeln_im_spiel.png").simplify_path()
		img.save_png(path)
		print("Bild: " + path)

	# Reiter wechseln
	help.show_tab("bedienung")
	await frames(2)
	t.clear()
	_texts(help, t)
	check(t.has("Karte ausspielen") and t.has("Hilfe zu einer Karte") and t.has("Ablage durchsehen") and t.has("Glücksspiel"), "So geht's mit Glücksspiel")
	check(t.has("Farbe ablegen"), "Ablegen mit Hausregel (Familie)")
	# Zurück-Taste schließt nur die Überlagerung
	check(ts.on_back(), "Zurück verbraucht")
	await frames(2)
	check(not ts.is_help_open() and not ts.leaving and ts.get("_confirm") == null, "Hilfe zu, Partie läuft, keine Rückfrage")
	check(ts.is_inside_tree(), "Tisch bleibt")

	# Direkt „So geht's“, Schriftstufe groß
	UiFonts.set_level("gross", root)
	ts.open_help("bedienung")
	await frames(2)
	help = ts.get("_help")
	check(help.tab == "bedienung", "So geht's direkt")
	var lbl: Label = null
	for n in help.find_children("*", "Label", true, false):
		if (n as Label).text == "Karte ausspielen":
			lbl = n
	check(lbl != null and lbl.get_theme_font_size("font_size") == UiFonts.size("zwischen"), "Schriftstufe groß wirkt")
	UiFonts.set_level("normal", root)
	await frames(1)
	check(lbl != null and lbl.get_theme_font_size("font_size") == UiFonts.size("zwischen"), "zurück auf normal")

	# Sichtschutz (Weitergeben): Überlagerung schließt, öffnet nicht
	ts.table.handover.visible = true
	await frames(2)
	check(not ts.is_help_open(), "Sichtschutz schließt die Hilfe")
	ts.open_help("regeln")
	await frames(1)
	check(not ts.is_help_open(), "keine Hilfe hinter dem Sichtschutz")
	ts.table.handover.visible = false

	# Nacht
	ts.table.night = 1.0
	ts.open_help("regeln")
	await frames(2)
	help = ts.get("_help")
	check(help.night, "Nachtseite")
	var night_lbl := 0
	for n in help.find_children("*", "Label", true, false):
		if (n as Label).get_theme_color("font_color").get_luminance() > 0.6:
			night_lbl += 1
	check(night_lbl > 10, "helle Schrift nachts")
	var other_tab := help.find_child("Reiter_bedienung", true, false) as Button
	check(other_tab != null and other_tab.get_theme_color("font_color") == UiPalette.PAPER, "nicht gewählter Reiter nachts hell")
	help.show_tab("bedienung")
	var rules_tab := help.find_child("Reiter_regeln", true, false) as Button
	check(rules_tab.get_theme_color("font_color") == UiPalette.PAPER and other_tab.get_theme_color("font_color") == UiPalette.INK, "Reiterwechsel nachts: Farben getauscht")
	# Flip während die Hilfe offen ist: Karte wechselt live auf Papier und zurück (1.1.3)
	var card := help.get("_card") as PanelContainer
	ts.table.night = 0.0
	await frames(1)
	check(not help.night and (card.get_theme_stylebox("panel") as StyleBoxFlat).bg_color == UiPalette.PAPER
		and rules_tab.get_theme_color("font_color") == UiPalette.INK, "Flip auf Tag: Papierkarte, dunkle Schrift")
	ts.table.night = 1.0
	await frames(1)
	check(help.night and (card.get_theme_stylebox("panel") as StyleBoxFlat).bg_color == UiPalette.NIGHT_PANEL, "Flip auf Nacht: dunkle Karte")
	help.close()
	await frames(1)
	check(not ts.is_help_open(), "Schließen-Knopf")

	# Texte ohne Mau und ohne Rückseiten
	var c2 := RuleConfig.new()
	c2.mau_call = "off"
	c2.peek_own_backs = false
	c2.backs_visible = false
	c2.discard_color = "on"
	var titles: Array = []
	for s in RulesText.controls(c2):
		titles.append(s.title)
	check(not titles.has("Mau rufen") and titles.has("Farbe ablegen") and not titles.has("Glücksspiel"), "So geht's folgt den Regeln")

	print("RESULT: %d ok%s" % [ok, ", FEHLER" if failed else ""])
	await CleanExit.finish(self, 1 if failed else 0)
