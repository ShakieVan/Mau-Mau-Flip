extends SceneTree
# Bildschirmtastatur (Nutzerbefund 06.10.2026: Namensfeld unter der Samsung-Tastatur im Querformat), bei 1600 × 720 mit simulierter
# Tastaturhöhe (ScreenNav.keyboard_height_override): Solange ein Eingabefeld den Fokus hat, endet der Bildschirm an der Tastatur,
# das Feld ist ganz zu sehen; danach steht alles wieder wie vorher. Dazu „Besondere Karten“ in der Regel-Übersicht.
#   godot_run.ps1 -Script res://tests/test_screens_keyboard.gd -Headless -Timeout 90
# Kontrollbilder (nicht headless): -EnvPairs "SHOT_DIR=<Ordner>" -Resolution 1600x720

const CleanExit := preload("res://tests/clean_exit.gd")
const KB := 340.0

var ok := 0
var failed := false
var nav: ScreenNav
var shot_dir := ""


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
	shot_dir = OS.get_environment("SHOT_DIR")
	var rules_backup: Variant = UiApp.setting("regeln", {})
	root.size = Vector2i(1600, 720)
	await frames(2)
	nav = ScreenNav.new()
	nav.autostart = false
	root.add_child(nav)
	await frames(2)
	# Weitergeben: viele Mitspieler, das letzte Namensfeld liegt tief
	var ps := PassSetupScreen.new()
	nav.push(ps, false)
	await frames(3)
	for i in 5:
		ps._add("human")
		await frames(2)
	await frames(3)
	var fields := ps.find_children("Name", "LineEdit", true, false)
	await keyboard_case(ps, fields[-1] as LineEdit, "Weitergeben, letzter Name", "tastatur_weitergeben")
	await keyboard_case(ps, fields[0] as LineEdit, "Weitergeben, erster Name")
	nav.go_back()
	await wait(0.3)
	# Einstellungen, WLAN, Übung
	var st := SettingsScreen.new()
	nav.push(st, false)
	await frames(3)
	await keyboard_case(st, st._name, "Einstellungen, Name")
	nav.go_back()
	await wait(0.3)
	var wl := WlanScreen.new()
	nav.push(wl, false)
	await frames(3)
	await keyboard_case(wl, wl._name, "WLAN, Name")
	nav.go_back()
	await wait(0.3)
	# Regeln speichern (Dialog über dem Regel-Editor)
	var rs := RulesScreen.new()
	rs.start_tab = "anpassen"
	nav.push(rs, false)
	await frames(3)
	rs.save_as()
	await frames(3)
	await keyboard_case(rs, rs._save_box.field, "Regeln speichern, Name")
	rs._save_box.cancel()
	await frames(2)
	# Ohne Fokus bleibt die Tastaturhöhe wirkungslos (z. B. eine stehengebliebene Meldung des Systems)
	ScreenNav.keyboard_height_override = KB
	await frames(4)
	check(rs.offset_bottom == 0.0 and rs.offset_top == 0.0, "ohne Eingabefeld mit Fokus: nichts gestaucht")
	ScreenNav.keyboard_height_override = -1.0
	# Übersicht: Besondere Karten
	await special_cards(rs)
	nav.go_back()
	await wait(0.3)
	if UiApp.app() != null:
		UiApp.app().settings.set_value("regeln", rules_backup if rules_backup is Dictionary else {})
	if failed:
		print("FAIL: test_screens_keyboard")
	else:
		print("RESULT: %d ok" % ok)
	await CleanExit.finish(self, 1 if failed else 0)


func keyboard_case(screen: AppScreen, field: LineEdit, what: String, shot := "") -> void:
	check(field != null, what + ": Feld gefunden")
	if field == null:
		return
	field.grab_focus()
	ScreenNav.keyboard_height_override = KB
	await frames(8)
	check(screen.offset_bottom <= -KB, "%s: Bildschirm endet an der Tastatur (%.0f)" % [what, screen.offset_bottom])
	check(nav.field_visible(field), "%s: Feld über der Tastatur sichtbar (%s)" % [what, str(field.get_global_rect())])
	if shot != "" and shot_dir != "":
		var kb := ColorRect.new()
		kb.color = Color(0.15, 0.15, 0.18, 0.92)
		kb.position = Vector2(0, 720.0 - KB)
		kb.size = Vector2(1600, KB)
		root.add_child(kb)
		await frames(3)
		root.get_texture().get_image().save_png(shot_dir.path_join(shot + ".png"))
		kb.queue_free()
	field.release_focus()
	await frames(3)
	check(screen.offset_bottom == 0.0 and screen.offset_top == 0.0, "%s: nach dem Schließen wieder volle Höhe" % what)
	ScreenNav.keyboard_height_override = -1.0
	await frames(1)


func special_cards(rs: RulesScreen) -> void:
	var house := RuleConfig.preset("familie")
	house.gamble_cards = "on"
	house.discard_color = "on"
	house.round_end = "first"
	RulesBar.store(house)
	rs.cfg = RulesBar.current()
	rs._show_tab("uebersicht")
	await frames(3)
	var sp := RulesScreen.special_cards(rs.cfg)
	var kinds := sp.map(func(e: Dictionary) -> String: return str(e.kind))
	for k in ["plus1", "plus5", "aussetzen", "alle_aussetzen", "richtungswechsel", "flip", "wuenscher", "wuenscher_plus2", "farbjagd", "tausch", "gluecksspiel", "ablegen", "ablegen_joker"]:
		check(kinds.has(k), "Besondere Karten: %s" % k)
	var gamble: Dictionary = sp[kinds.find("gluecksspiel")]
	var expect: Array[String] = []
	for line in RulesText.card_help("hell_gluecksspiel", rs.cfg):
		if not line.begins_with("Wert: "):
			expect.append(line)
	check(gamble.lines == expect, "Glücksspiel: genau die Kartenhilfe")
	var plus1: Dictionary = sp[kinds.find("plus1")]
	check(not " ".join(PackedStringArray(plus1.lines)).contains("Rot"), "Ziehkarte: keine einzelne Farbe genannt")
	check(" ".join(PackedStringArray(plus1.lines)).contains("drauflegen"), "Familie: Stapeln bei +1 erwähnt")
	var flip: Dictionary = sp[kinds.find("flip")]
	check(str(flip.lines[0]).contains("die andere Seite"), "Flip: „die andere Seite“ (%s)" % str(flip.lines[0]))
	check(rs._special_box.find_child("gluecksspiel", false, false) != null and rs._overview_short.text.contains("Kurz gesagt"), "Übersicht: Abschnitt und „Kurz gesagt“ danach")
	var off := RulesScreen.special_cards(RuleConfig.preset("offiziell"))
	check(off.size() == 9, "Offiziell: nur die 9 Aktionskarten (%d)" % off.size())
	if shot_dir != "":
		rs._overview.scroll_vertical = int(rs._special_box.position.y + 20)
		await frames(4)
		root.get_texture().get_image().save_png(shot_dir.path_join("regeln_besondere_karten.png"))
