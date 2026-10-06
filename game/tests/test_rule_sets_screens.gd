extends SceneTree
# Gespeicherte Regelsätze auf den Bildschirmen, headless bei 1600 × 720 (Nutzerwunsch 06.10.2026, Nachbesserung nach der Prüfung):
#  - Regel-Editor: „Speichern unter …“ oben rechts, Zeile „Gespeichert“ (leer mit Hinweis ohne „Antippen …“), Gastgeber-Platz als
#    erster Knopf, Speichern-Dialog (Name, Zeichenfilter, leerer Name, Rückfrage zum Überschreiben in eigener Zeile mit gesperrtem
#    „Speichern“ und Doppeltipp-Sperre, Grenze 12), Tippen lädt, Hervorhebung, Löschen per Gedrückthalten bzw. Rechtsklick (lädt
#    nichts), Vorschlag nach Voreinstellung leer, Doppelte zeigen überall den zuletzt gewählten Namen, Zurück schließt Dialog und
#    Rückfrage, 12 lange Namen: Gastgeber-Platz und erste Option bleiben erreichbar.
#  - Regelzeile: voll mit Knopf „Gespeichert“ und Auswahl (RuleSetPicker), kompakt mit dem Knopf „Regeln von Lena“ (übernehmen).
#  - App-Gast über einen echten HostTable und „Beitreten“ (127.0.0.1, TCP 24895): Die Lobby merkt sich nichts (bloßes Beitreten
#    überschreibt den Gastgeber-Platz nicht), Regelkopf „Regeln von Lena“ bzw. Name des gespeicherten Satzes, Hinweis, wo die Regeln
#    stehen, „Regeln speichern“ (Titel fest, Gastgeber in der Zeile darunter, Regeländerung bei offenem Dialog, Dialog wandert beim
#    Start an den Tisch), „Bereit“ ohne Haken im nicht bereiten Zustand. Am Tisch: Sicht merkt „Zuletzt gespielt bei Lena“ (leere
#    oder kaputte Regeln nicht), Spielmenü bleibt beim Speichern offen und zeigt „Gespeichert als …“, Leiste „Verbindung zum
#    Gastgeber beendet.“ mit Hinweis, „Gespeichert: …“ und „Selbst eröffnen“ (neue Lobby mit genau diesen Regeln).
#  - Danach eröffnet dieses Gerät: Lobby bietet „Regeln von Lena“ zum Übernehmen an; Editor mit Satz bzw. Gastgeber-Platz; die Partie
#    startet mit genau diesen Regeln. Gastgeber- und Übungspartien schreiben nichts in den Gastgeber-Platz.
# Läuft mit eigener Einstellungsdatei (App.settings wird für die Dauer des Tests ersetzt): Auch ein Abbruch durch die Zeitgrenze
# lässt die echten Einstellungen der App unberührt.
#   godot_run.ps1 -Script res://tests/test_rule_sets_screens.gd -Headless -Timeout 240

const CleanExit := preload("res://tests/clean_exit.gd")
const PORT := 24895
const SETTINGS_PATH := "user://test_rule_sets_screens_einstellungen.json"
const LONG_NAMES := ["Ferienhaus Ostsee 26", "Weihnachten bei Oma", "WWWWWWWWWWWWWWWWWWWW", "Kneipenabend Freitag", "Schnelle Runde (3+4)",
	"Kinder & Großeltern", "Turnier Vereinsheim", "Zu zweit im Zug", "Lange Nacht 500 Pkt", "Mau-Mau klassisch", "Probe Glücksspiel", "Sonntag Nachmittag"]

var ok := 0
var failed := false
var nav: ScreenNav
var nav2: ScreenNav
var host: HostTable
var _real_settings: AppSettings


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


func wait_for(cond: Callable, ms := 5000) -> bool:
	var deadline := Time.get_ticks_msec() + ms
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return cond.call()


func run() -> void:
	GameStarter.test_speed = 0.0
	var app := UiApp.app()
	if app == null:
		print("FAIL: App fehlt")
		quit(1)
		return
	use_test_settings(app)
	root.size = Vector2i(1600, 720)
	await frames(2)
	nav = ScreenNav.new()
	nav.autostart = false
	root.add_child(nav)
	await frames(3)
	await editor()
	await long_names()
	await bars()
	await guest()
	await reopen_as_host()
	await local_game()
	restore_settings(app)
	if failed:
		print("FAIL: test_rule_sets_screens")
	else:
		print("RESULT: %d ok" % ok)
	await CleanExit.finish(self, 1 if failed else 0)


# ----------------------------------------------------------------- Hilfen

# Eigene Einstellungsdatei statt der echten der App (user://einstellungen.json)
func use_test_settings(app: Node) -> void:
	_remove_files(SETTINGS_PATH)
	_real_settings = app.settings
	var st := AppSettings.new(SETTINGS_PATH)
	st.set_value("name", "Tester")
	app.settings = st


func restore_settings(app: Node) -> void:
	if _real_settings != null:
		app.settings = _real_settings
	_remove_files(SETTINGS_PATH)


func _remove_files(p: String) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(p + suffix):
			DirAccess.remove_absolute(p + suffix)


func settings() -> AppSettings:
	return UiApp.app().settings


func house() -> RuleConfig:
	var cfg := RuleConfig.preset("familie")
	cfg.gamble_cards = "on"
	cfg.discard_color = "on"
	cfg.hand_size = 6
	return cfg


func chip(rs: RulesScreen, set_name: String) -> Button:
	for b in rs._sets_box.find_children("Laden", "Button", true, false):
		if str(b.get_meta("set", "")) == set_name:
			return b
	return null


# Kleines × neben dem Satzknopf
func cross(rs: RulesScreen, set_name: String) -> Button:
	var b := chip(rs, set_name)
	return b.get_parent().find_child("Loeschen", false, false) as Button if b != null else null


func host_chip(rs: RulesScreen) -> Button:
	return rs._sets_box.find_child("Gastgeber", false, false) as Button


func active_chips(rs: RulesScreen) -> Array:
	var out := []
	for b in rs._sets_box.find_children("*", "Button", true, false):
		if (b as Button).theme_type_variation == "PrimaryButton":
			out.append((b as Button).text)
	return out


func chosen(row: HBoxContainer) -> String:
	for b in row.get_children():
		if b is Button and (b as Button).theme_type_variation == "PrimaryButton" and b.has_meta("key"):
			return str(b.get_meta("key"))
	return ""


func box_title(box: Control) -> String:
	for l in box.find_children("*", "Label", true, false):
		if (l as Label).theme_type_variation == "HeadingLabel":
			return (l as Label).text
	return ""


func inside(inner: Rect2, outer: Rect2, tol := 1.0) -> bool:
	return outer.grow(tol).encloses(inner)


# ----------------------------------------------------------------- Regel-Editor

func editor() -> void:
	RulesBar.store(RuleConfig.preset("offiziell"))
	var rs := RulesScreen.new()
	rs.start_tab = "anpassen"
	nav.push(rs, false)
	await frames(3)
	var screen := Rect2(Vector2.ZERO, Vector2(1600, 720))
	check(rs.find_child("Gespeichert", true, false) != null and rs._sets_box.find_child("Leer", false, false) != null, "Editor: Zeile „Gespeichert“ mit Hinweis, solange nichts gespeichert ist")
	check(not rs._sets_hint.visible, "leer: kein Hinweis „Antippen lädt …“ neben „Noch nichts gespeichert“")
	check(inside(rs._save_btn.get_global_rect(), screen) and rs.find_child("Gespeichert", true, false).is_ancestor_of(rs._save_btn), "„Speichern unter …“ in der Kopfreihe von „Gespeichert“")
	check(rs.find_child("Loeschen", true, false) == null, "kein eigener Knopf „Löschen“ mehr")
	# Eigene Regeln einstellen und speichern
	var a := house()
	RulesBar.store(a)
	rs.cfg = RulesBar.current()
	rs._refresh()
	rs.save_as()
	await frames(2)
	var box := rs._save_box
	check(box != null and is_instance_valid(box) and box.field.text == "", "Dialog offen, ohne Vorschlag")
	if box == null:
		return
	check(inside(box.field.get_global_rect(), Rect2(0, 0, 1600, 340)) and inside(box._yes.get_global_rect(), Rect2(0, 0, 1600, 340))
		and inside(box._no.get_global_rect(), Rect2(0, 0, 1600, 340)) and inside(box._msg.get_global_rect(), Rect2(0, 0, 1600, 360)),
		"Namensfeld, Knöpfe und Meldung in der oberen Hälfte (Bildschirmtastatur) (%s, %s, %s)" % [str(box.field.get_global_rect()), str(box._yes.get_global_rect()), str(box._msg.get_global_rect())])
	check((box.find_child("Inhalt", true, false) as Label).text.begins_with("Mit Kartentausch") or (box.find_child("Inhalt", true, false) as Label).text.contains("Kartentausch"),
		"Dialog zeigt, was gespeichert wird")
	check(box_title(box) == "Regeln speichern" and box._msg.text == RuleSetSaveBox.HINT_EDITOR and not box._msg.text.contains("Anpassen"),
		"Regel-Editor: Titel fest, Hinweis ohne Verweis auf „Regeln“ → „Anpassen“ (%s)" % box._msg.text)
	box.confirm()
	await frames(1)
	check(is_instance_valid(box) and not box.is_queued_for_deletion() and box._msg.text.contains("Namen") and RuleSets.count() == 0, "leerer Name: Hinweis, nichts gespeichert")
	box.field.text = "Oma[1]%"
	box.field.text_changed.emit("Oma[1]%")
	check(box.field.text == "Oma1", "Zeichenfilter beim Tippen (%s)" % box.field.text)
	box.field.text = "  Oma-Regeln  "
	box.confirm()
	await frames(2)
	check(RuleSets.names() == ["Oma-Regeln"] and RuleSets.matches("Oma-Regeln", a) and rs._save_box == null, "gespeichert: „Oma-Regeln“")
	var c := chip(rs, "Oma-Regeln")
	check(c != null and c.theme_type_variation == "PrimaryButton" and rs._sets_box.find_child("Leer", false, false) == null,
		"Satz erscheint hervorgehoben")
	check(rs._sets_hint.visible and rs._sets_hint.text == "Antippen lädt, × löscht", "Hinweis zum Laden und Löschen (sichtbar, kein Tooltip)")
	check(cross(rs, "Oma-Regeln") != null and cross(rs, "Oma-Regeln").get_global_rect().size.x < c.get_global_rect().size.x, "kleines × neben dem Satz")
	var sh := rs._save_btn.get_global_rect()
	check(sh.position.y < rs._sets_box.get_global_rect().position.y and rs._sets_box.get_global_rect().position.x < 200.0,
		"„Speichern unter …“ in der Kopfreihe über den Sätzen, die Sätze beginnen links (%s, %s)" % [str(sh), str(rs._sets_box.get_global_rect())])
	check(chosen(rs._preset_row) == "" and RulesBar.title(RulesBar.current()) == "Oma-Regeln", "Regeln tragen den Namen des Satzes")
	# Ändern: keine Hervorhebung mehr; „Speichern unter …“ schlägt den geladenen Satz vor, Überschreiben mit Rückfrage
	rs.set_option("hand_size", 9)
	check(active_chips(rs).is_empty(), "geändert: kein Satz hervorgehoben")
	rs.save_as()
	await frames(2)
	box = rs._save_box
	check(box.field.text == "Oma-Regeln", "Vorschlag: der geladene Satz (%s)" % box.field.text)
	box.confirm()
	await frames(3)
	check(box._pending == "Oma-Regeln" and box._question.visible and box._question_label.text.contains("gibt es schon") and not box._msg.visible
		and RuleSets.config("Oma-Regeln").hand_size == 6, "gleicher Name: Rückfrage in eigener Zeile, noch nicht überschrieben")
	check(box._yes.disabled and box._yes.text == "Speichern" and box._over.get_global_rect().position.y > box._yes.get_global_rect().end.y,
		"Rückfrage: „Speichern“ gesperrt, „Überschreiben“ eine Zeile tiefer (%s / %s)" % [str(box._yes.get_global_rect()), str(box._over.get_global_rect())])
	box.confirm()                      # zweiter Tipp bzw. Eingabetaste: nichts
	box._over.pressed.emit()           # Doppeltipp: zu schnell nach der Rückfrage
	await frames(1)
	check(is_instance_valid(box) and box._pending == "Oma-Regeln" and RuleSets.config("Oma-Regeln").hand_size == 6, "Doppeltipp überschreibt nicht")
	box.field.text_changed.emit(box.field.text)       # weitertippen = anderer Name
	check(box._pending == "" and not box._question.visible and not box._yes.disabled and is_instance_valid(box), "Weitertippen: Rückfrage verfällt")
	box.confirm()
	check(box._pending == "Oma-Regeln", "wieder gefragt")
	box._other.pressed.emit()          # „Anderer Name“
	check(box._pending == "" and not box._question.visible and box._msg.visible, "„Anderer Name“: Rückfrage zu")
	box.confirm()
	box._asked_ms -= RuleSetSaveBox.GUARD_MS + 100
	box._over.pressed.emit()           # „Überschreiben“ nach dem Lesen
	await frames(2)
	check(RuleSets.count() == 1 and RuleSets.config("Oma-Regeln").hand_size == 9 and chip(rs, "Oma-Regeln").theme_type_variation == "PrimaryButton", "überschrieben")
	# Zweiter Satz, Laden per Tipp
	rs.apply_preset("klassisch500")
	rs.set_option("target", 300)
	rs.save_as()
	await frames(2)
	rs._save_box.field.text = "Kneipe"
	rs._save_box.confirm()
	await frames(2)
	check(RuleSets.names() == ["Oma-Regeln", "Kneipe"] and active_chips(rs) == ["Kneipe"], "zweiter Satz „Kneipe“")
	chip(rs, "Oma-Regeln").pressed.emit()
	await frames(1)
	check(RulesBar.current().hand_size == 9 and RulesBar.current().gamble_cards == "on" and active_chips(rs) == ["Oma-Regeln"], "Tippen lädt „Oma-Regeln“")
	check((rs._controls["hand_size"].get_child(1) as Label).text == "9" and (rs._controls["gamble_cards"] as CheckButton).button_pressed, "Bedienelemente zeigen den geladenen Satz")
	rs._show_tab("uebersicht")
	await frames(1)
	check(rs._overview_text.text.contains("Gespeichert: Oma-Regeln · 124 Karten"), "Übersicht: Name des Satzes")
	rs._show_tab("anpassen")
	# Gleiche Regeln wie eine Voreinstellung: beide hervorgehoben
	rs.apply_preset("mau_mau")
	rs.save_as()
	await frames(2)
	rs._save_box.field.text = "Tradition"
	rs._save_box.confirm()
	await frames(2)
	check(chosen(rs._preset_row) == "mau_mau" and active_chips(rs) == ["Tradition"] and RulesBar.title(RulesBar.current()) == "Mau-Mau", "Satz = Voreinstellung: beide hervorgehoben, Titel der Voreinstellung")
	# Nach einer Voreinstellung schlägt „Speichern unter …“ keinen alten Satz mehr vor
	chip(rs, "Oma-Regeln").pressed.emit()
	rs.apply_preset("familie")
	rs.save_as()
	await frames(2)
	check(rs._save_box.field.text == "", "nach einer Voreinstellung: kein Vorschlag (%s)" % rs._save_box.field.text)
	rs._save_box.cancel()
	await frames(1)
	# Löschen per Gedrückthalten, ohne zu laden: Die eingestellten (ungespeicherten) Regeln bleiben
	var unsaved := RuleConfig.preset("familie")
	unsaved.hand_size = 10
	RulesBar.store(unsaved)
	rs.cfg = RulesBar.current()
	rs._refresh()
	await press_and_hold(chip(rs, "Tradition"), RulesScreen.LONG_PRESS * 0.3)   # kurzer Tipp
	await wait(RulesScreen.LONG_PRESS)
	check(RulesBar.current().preset_name() == "mau_mau" and rs._confirm == null, "kurzer Tipp lädt, keine Rückfrage")
	RulesBar.store(unsaved)
	rs.cfg = RulesBar.current()
	rs._refresh()
	await press_and_hold(chip(rs, "Tradition"))
	check(rs._confirm != null and is_instance_valid(rs._confirm) and RulesBar.current().hand_size == 10, "gedrückt gehalten: Rückfrage zum Löschen, nichts geladen")
	check(rs.on_back() and rs._confirm == null and RuleSets.has_set("Tradition"), "Zurück: Rückfrage zu, nichts gelöscht")
	await frames(1)
	await press_and_hold(chip(rs, "Tradition"))
	(rs._confirm.find_child("Ja", true, false) as Button).pressed.emit()
	await frames(2)
	check(not RuleSets.has_set("Tradition") and chip(rs, "Tradition") == null, "„Tradition“ gelöscht")
	check(RulesBar.current().hand_size == 10 and RulesBar.current().preset_name() == "" and rs.cfg.hand_size == 10, "Löschen lässt die eingestellten Regeln stehen")
	# Am PC: Rechtsklick fragt ebenfalls
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	chip(rs, "Kneipe").gui_input.emit(right)
	await frames(1)
	check(rs._confirm != null and is_instance_valid(rs._confirm), "Rechtsklick: Rückfrage zum Löschen")
	rs._confirm.cancel()
	await frames(1)
	# Das × daneben: Rückfrage, lädt nichts; „Behalten“ lässt den Satz stehen
	var before := RulesBar.current().to_dict()
	cross(rs, "Kneipe").pressed.emit()
	await frames(1)
	check(rs._confirm != null and is_instance_valid(rs._confirm) and RulesBar.current().to_dict() == before, "×: Rückfrage zum Löschen, nichts geladen")
	(rs._confirm.find_child("Nein", true, false) as Button).pressed.emit()
	await frames(2)
	check(RuleSets.has_set("Kneipe") and chip(rs, "Kneipe") != null, "×, „Behalten“: Satz bleibt")
	# Doppelte Regeln: überall der zuletzt gewählte Name (Editor, Regelzeile)
	RuleSets.save("Oma Kopie", RuleSets.config("Oma-Regeln"))
	rs._rebuild_sets()
	chip(rs, "Oma Kopie").pressed.emit()
	await frames(1)
	check(active_chips(rs) == ["Oma Kopie"] and RulesBar.title(RulesBar.current()) == "Oma Kopie" and RuleSets.match_name(RulesBar.current()) == "Oma Kopie",
		"Doppelte: Editor und Regelzeile zeigen „Oma Kopie“ (%s, %s)" % [str(active_chips(rs)), RulesBar.title(RulesBar.current())])
	chip(rs, "Oma-Regeln").pressed.emit()
	await frames(1)
	check(active_chips(rs) == ["Oma-Regeln"] and RulesBar.title(RulesBar.current()) == "Oma-Regeln", "Doppelte: wieder „Oma-Regeln“")
	RuleSets.remove("Oma Kopie")
	rs._rebuild_sets()
	rs.apply_preset("mau_mau")
	# Grenze 12
	for i in range(RuleSets.count(), RuleSets.MAX):
		var cfg := RuleConfig.new()
		cfg.mau_penalty = 1 + (i % 4)
		cfg.hand_size = 5 + (i % 6)
		RuleSets.save("Satz %d" % i, cfg)
	rs._rebuild_sets()
	await frames(2)
	check(rs._sets_box.get_child_count() == RuleSets.MAX, "12 Knöpfe")
	var rows_ok := inside(rs._save_btn.get_global_rect(), screen) and rs._sets_box.size.y > ScreenKit.TOUCH * 1.5
	check(rows_ok, "12 Sätze brechen um (%s)" % str(rs._sets_box.size))
	rs.save_as()
	await frames(2)
	rs._save_box.field.text = "Dreizehn"
	rs._save_box.confirm()
	await frames(1)
	check(is_instance_valid(rs._save_box) and rs._save_box._msg.text.contains("Schon 12") and rs._save_box._msg.text.contains("×") and not RuleSets.has_set("Dreizehn"),
		"13. Satz: Hinweis aufs Löschen per ×, Dialog bleibt offen")
	rs._save_box.field.text = "kneipe"
	rs._save_box.confirm()
	await frames(1)
	check(is_instance_valid(rs._save_box) and rs._save_box._pending == "Kneipe" and not rs._save_box._msg.visible, "bei 12 Sätzen: vorhandener Name → Überschreiben möglich")
	check(rs.on_back() and rs._save_box == null, "Zurück schließt den Dialog")
	await frames(2)
	check(RuleSets.config("Kneipe").target == 300, "abgebrochen: nichts überschrieben")
	for i in range(2, RuleSets.MAX):
		RuleSets.remove("Satz %d" % i)
	# Tipp neben den Dialog bricht ab
	rs.save_as()
	await frames(2)
	box = rs._save_box
	var cancelled := [false]
	box.cancelled.connect(func() -> void: cancelled[0] = true)
	var outside := InputEventMouseButton.new()
	outside.button_index = MOUSE_BUTTON_LEFT
	outside.pressed = true
	outside.position = Vector2(800, 690)
	box._gui_input(outside)
	await frames(2)
	check(cancelled[0] and rs._save_box == null, "Tipp daneben bricht ab")
	rs.save_as()
	await frames(2)
	rs._save_box._no.pressed.emit()
	await frames(2)
	check(rs._save_box == null and RuleSets.count() == 2, "„Abbrechen“")
	nav.go_back()
	await wait(0.3)


# Gedrückt halten wie am Touchscreen (echte Eingabe über das Fenster): drücken, LONG_PRESS warten, loslassen
func press_and_hold(b: Button, hold := RulesScreen.LONG_PRESS + 0.15) -> void:
	var pos := b.get_global_rect().get_center()
	mouse_button(pos, true)
	await wait(hold)
	mouse_button(pos, false)
	await frames(2)


func mouse_button(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	e.position = pos
	e.global_position = pos
	root.push_input(e, true)


# ----------------------------------------------------------------- 12 lange Namen und der Gastgeber-Platz (Prüfung 06.10.2026)

func long_names() -> void:
	var keep := RuleSets.list()
	settings().reset(RuleSets.KEY)
	for i in LONG_NAMES.size():
		var c := RuleConfig.new()
		c.hand_size = 5 + (i % 6)
		c.mau_penalty = 1 + (i % 4)
		if i == 2:
			c.gamble_cards = "on"
		RuleSets.save(LONG_NAMES[i], c)
	var before_host: Variant = settings().get_value(RuleSets.HOST_KEY)
	RuleSets.remember_host(house().to_dict(), "Maximilian12")
	RulesBar.store(RuleSets.config("Kinder & Großeltern"))
	var rs := RulesScreen.new()
	rs.start_tab = "anpassen"
	nav.push(rs, false)
	await frames(4)
	var screen := Rect2(Vector2.ZERO, Vector2(1600, 720))
	var hb := host_chip(rs)
	check(hb != null and hb.get_index() == 0 and inside(hb.get_global_rect(), screen), "12 lange Namen: Gastgeber-Platz als erster Knopf im Bild (%s)" % (str(hb.get_global_rect()) if hb != null else "-"))
	check(rs._sets_box.size.x > 1000.0, "Sätze nutzen die ganze Breite (%s)" % str(rs._sets_box.size))
	var first := rs._controls.get("round_end") as Control
	var rows := int(round((rs._sets_box.size.y + 8.0) / (ScreenKit.TOUCH + 8.0)))
	check(rows <= 4, "12 lange Namen + Gastgeber: höchstens 4 Reihen (%d, %s)" % [rows, str(rs._sets_box.size)])
	check(first != null and first.get_global_rect().position.y < 720.0, "erste Option „Rundenende“ beginnt im Bild (%s; Sätze %s, Speichern %s)" % [str(first.get_global_rect()) if first != null else "-", str(rs._sets_box.get_global_rect()), str(rs._save_btn.get_global_rect())])
	check(inside(rs._save_btn.get_global_rect(), screen), "„Speichern unter …“ im Bild")
	nav.go_back()
	await wait(0.3)
	settings().set_value(RuleSets.KEY, keep)
	if before_host is Dictionary and not (before_host as Dictionary).is_empty():
		settings().set_value(RuleSets.HOST_KEY, before_host)
	else:
		settings().reset(RuleSets.HOST_KEY)


# ----------------------------------------------------------------- Regelzeile (RulesBar)

func bars() -> void:
	RulesBar.store(RuleSets.config("Kneipe"))
	var compact := RulesBar.new()
	compact.compact = true
	root.add_child(compact)
	var full := RulesBar.new()
	root.add_child(full)
	await frames(2)
	check(compact._head.text == "Kneipe · 112 Karten", "kompakt: Name des Satzes (%s)" % compact._head.text)
	check(full._saved_btn.visible and full._saved_btn.text == "Gespeichert: Kneipe" and full._saved_btn.theme_type_variation == "PrimaryButton" and chosen(full._choice) == "",
		"voll: Knopf „Gespeichert: Kneipe“ hervorgehoben (%s)" % full._saved_btn.text)
	check(not full._summary.text.begins_with("Kneipe") and full._summary.text.begins_with("Erster fertig"), "voll: Kurzbeschreibung ohne doppelten Namen (%s)" % full._summary.text)
	check(not compact._offer.visible, "kompakt: ohne Gastgeber-Platz kein Angebot")
	var other := RuleSets.config("Kneipe")
	other.target = 400
	RulesBar.store(other)
	compact.refresh()
	full.refresh()
	check(compact._head.text == "Eigene Regeln · 112 Karten" and full._summary.text.begins_with("Eigene Regeln: "), "geändert: wieder „Eigene Regeln“")
	check(full._saved_btn.text == "Gespeicherte Regeln …" and full._saved_btn.theme_type_variation == "GhostButton", "voll: Knopf „Gespeicherte Regeln …“")
	# Auswahl direkt in der Einrichtung
	var got := []
	full.changed.connect(func(c: RuleConfig) -> void: got.append(c))
	full.open_picker()
	await frames(3)
	var picker := full._picker
	check(picker != null and is_instance_valid(picker) and picker.flow.get_child_count() == 2, "Auswahl „Gespeicherte Regeln“ mit 2 Sätzen")
	if picker != null:
		var oma_btn: Button = null
		for b in picker.flow.get_children():
			if b is Button and str(b.get_meta("set", "")) == "Oma-Regeln":
				oma_btn = b
		oma_btn.pressed.emit()
		await frames(1)
	check(full._picker == null and RulesBar.current().equals(RuleSets.config("Oma-Regeln")) and got.size() == 1 and RuleSets.chosen_name() == "Oma-Regeln",
		"Auswahl lädt „Oma-Regeln“ und meldet changed")
	check(full._saved_btn.text == "Gespeichert: Oma-Regeln", "danach „Gespeichert: Oma-Regeln“")
	full.open_picker()
	await frames(1)
	check(full.close_picker() and full._picker == null and not full.close_picker(), "close_picker (Zurück) schließt die Auswahl")
	# Kompakt: Angebot „Regeln von Lena“, sobald es einen abweichenden Gastgeber-Platz gibt
	var lena := house()
	RuleSets.remember_host(lena.to_dict(), "Lena")
	compact.refresh()
	check(compact._offer.visible and compact._offer_btn.text == "Regeln von Lena übernehmen", "kompakt: Angebot sichtbar (%s)" % compact._offer_btn.text)
	var cgot := []
	compact.changed.connect(func(c: RuleConfig) -> void: cgot.append(c))
	compact._offer_btn.pressed.emit()
	check(RuleSets.same(RulesBar.current(), lena) and cgot.size() == 1 and not compact._offer.visible and compact._head.text == "Zuletzt gespielt bei Lena · 124 Karten",
		"übernommen: Regeln von Lena, Angebot weg (%s)" % compact._head.text)
	RulesBar.store(RuleConfig.preset("offiziell"))
	compact.refresh()
	check(compact._offer.visible, "andere Regeln: Angebot wieder da")
	(compact._offer.find_child("Ausblenden", false, false) as Button).pressed.emit()
	check(not compact._offer.visible, "„×“ blendet das Angebot aus")
	full.refresh()
	check(full._saved_btn.visible, "voll: Knopf auch mit Gastgeber-Platz")
	settings().reset(RuleSets.HOST_KEY)
	compact.queue_free()
	full.queue_free()
	await frames(1)


# ----------------------------------------------------------------- App-Gast

func guest() -> void:
	var lena := house()
	host = HostTable.new()
	host.name = "TestGastgeber"
	host.use_discovery = false
	host.autosave = false
	host.speed = 0.0
	host.set_rules(lena)
	root.add_child(host)
	check(host.open("Lena", PORT, PORT) == OK, "Gastgeber „Lena“ eröffnet auf %d" % PORT)
	nav2 = ScreenNav.new()
	nav2.autostart = false
	root.add_child(nav2)
	await frames(2)
	var join := JoinScreen.new()
	nav2.push(join, false)
	await frames(2)
	# Ein früherer Gastgeber („Ben“) ist gemerkt: Bloßes Beitreten bei Lena darf ihn nicht überschreiben
	var ben := RuleConfig.preset("mau_mau")
	ben.hand_size = 5
	RuleSets.remember_host(ben.to_dict(), "Ben")
	var slot_before: Variant = settings().get_value(RuleSets.HOST_KEY)
	join.join("127.0.0.1", PORT)
	await wait_for(func() -> bool: return join.host_rules != null, 6000)
	var screen := Rect2(0, 0, 1600, 720)
	check(join.host_rules != null and RuleSets.same(join.host_rules, lena), "Gast-Lobby: Regeln des Gastgebers angekommen")
	check(settings().get_value(RuleSets.HOST_KEY) == slot_before and RuleSets.host_name() == "Ben", "Lobby merkt sich nichts: „Zuletzt gespielt bei Ben“ bleibt")
	var lobby_copy: Dictionary = join.client.lobby.duplicate(true)
	lobby_copy["rules"] = "kaputt"
	join._on_lobby(lobby_copy)
	lobby_copy["rules"] = {}
	join._on_lobby(lobby_copy)
	check(RuleSets.host_name() == "Ben" and RuleSets.same(join.host_rules, lena), "kaputte bzw. leere Lobby-Regeln: nichts gemerkt, letzte Regeln bleiben")
	join._on_lobby(join.client.lobby)
	check(RuleSets.count() == 2, "der Gastgeber-Platz zählt nicht zu den eigenen Sätzen")
	check(join._lobby_head.text == "Regeln von Lena · 124 Karten · mit Kartentausch, Glücksspiel und Farbe ablegen", "Regelkopf aus Sicht des Gastes (%s)" % join._lobby_head.text)
	check(join._lobby_hint.text.contains("„Zuletzt gespielt bei Lena“") and inside(join._lobby_hint.get_global_rect(), screen), "Hinweis, wo die Regeln später stehen (%s)" % join._lobby_hint.text)
	check(join._ready_btn.icon == null and join._ready_btn.text == "Bereit", "„Bereit“ ohne Haken, solange nicht bereit")
	check(join._save_btn.text == "Regeln speichern" and not join._save_btn.disabled and join._save_btn.is_visible_in_tree(), "Knopf „Regeln speichern“")
	check(inside(join._save_btn.get_global_rect(), screen) and inside(join._ready_btn.get_global_rect(), screen), "„Regeln speichern“ und „Bereit“ im Bild")
	join.save_rules()
	await frames(2)
	var box := join._save_box
	check(box != null and box.field.text == "Regeln von Lena" and box_title(box) == "Regeln speichern", "Vorschlag „Regeln von Lena“, Titel fest (%s)" % (box.field.text if box != null else "-"))
	if box == null:
		return
	check((box.find_child("Inhalt", true, false) as Label).text.begins_with("Regeln von Lena: ") and box._msg.text == RuleSetSaveBox.HINT_GUEST,
		"Gastgeber in der Zeile unter dem Titel, Hinweis für Gäste")
	# Der Gastgeber ändert die Regeln, während der Dialog offen ist: gespeichert werden die neuen
	var changed := RuleConfig.preset("mau_mau")
	changed.hand_size = 8
	host.set_rules(changed)
	await wait_for(func() -> bool: return join.host_rules != null and join.host_rules.hand_size == 8)
	check(is_instance_valid(box) and RuleSets.same(box.cfg, changed) and box._msg.text.contains("geändert"), "offener Dialog übernimmt die neuen Regeln")
	host.set_rules(lena)
	await wait_for(func() -> bool: return join.host_rules != null and join.host_rules.hand_size == 6)
	check(RuleSets.same(box.cfg, lena) and RuleSets.host_name() == "Ben", "zurück; Gastgeber-Platz weiter unberührt")
	box.field.text = "Lenas Runde"
	box.confirm()
	await frames(2)
	check(RuleSets.matches("Lenas Runde", lena) and join._save_btn.text == "Gespeichert", "gespeichert, Knopf zeigt „Gespeichert“")
	check(join._lobby_head.text.begins_with("Lenas Runde · 124 Karten"), "Regelkopf zeigt den Namen des Satzes (%s)" % join._lobby_head.text)
	join._ready_btn.button_pressed = true
	check(join._ready_btn.text == "Bereit ✓" and join._ready_btn.icon == null, "bereit: ein Haken, nur im Text")
	# Dialog noch offen, als der Gastgeber startet: Er kommt samt Namen mit an den Tisch
	join.save_rules()
	await frames(2)
	var open_box := join._save_box
	open_box.field.text = "Lena Urlaub"
	host.add_bot()
	check(host.start(), "Partie startet")
	await wait_for(func() -> bool: return nav2.top() is TableScreen and not (nav2.top() as TableScreen).view.is_empty(), 6000)
	var gts := nav2.top() as TableScreen
	check(gts != null and gts.source is ClientTable and not gts.view.is_empty(), "Tisch des App-Gasts mit Sicht")
	if gts == null:
		return
	check(is_instance_valid(open_box) and gts._save_box == open_box and open_box.get_parent() == gts._top and open_box.field.text == "Lena Urlaub",
		"Speichern-Dialog mit getipptem Namen an den Tisch mitgenommen")
	open_box.confirm()
	await frames(2)
	check(RuleSets.matches("Lena Urlaub", lena) and gts._save_box == null, "am Tisch gespeichert: „Lena Urlaub“")
	# Am Tisch merkt der Gast die Regeln aus der Sicht
	await wait_for(func() -> bool: return RuleSets.host_name() == "Lena", 3000)
	check(RuleSets.host_name() == "Lena" and RuleSets.host_matches(lena), "am Tisch: Regeln aus der Sicht gemerkt (%s)" % RuleSets.host_name())
	var good: Dictionary = gts.view.duplicate(true)
	RuleSets.remember_host(ben.to_dict(), "Ben")
	var empty := good.duplicate(true)
	empty["rules"] = {}
	gts._on_state([], empty)
	check(RuleSets.host_name() == "Ben", "Sicht mit leeren Regeln: nichts gemerkt")
	gts._on_state([], good)
	check(RuleSets.host_name() == "Lena" and RuleSets.host_matches(lena), "Sicht mit Regeln: wieder Lena")
	# Spielmenü: „Partie verlassen?“ bleibt beim Speichern offen
	gts.on_back()
	await frames(2)
	check(gts._confirm != null and is_instance_valid(gts._confirm), "Spielmenü offen")
	var opt := gts._confirm.find_child("RegelnSpeichern", true, false) as Button if gts._confirm != null else null
	check(opt != null and opt.text == "Gespeichert als „Lena Urlaub“", "Spielmenü zeigt den gespeicherten Namen (%s)" % (opt.text if opt != null else "-"))
	if opt != null:
		opt.pressed.emit()
	await frames(2)
	check(gts._confirm != null and is_instance_valid(gts._confirm) and gts._save_box != null and gts._save_box.get_index() > gts._confirm.get_index(),
		"Rückfrage bleibt offen, Speichern-Dialog liegt darüber")
	if gts._save_box != null:
		check(gts._save_box.field.text == "Lena Urlaub" and box_title(gts._save_box) == "Regeln speichern", "Vorschlag: der passende Satz (%s)" % gts._save_box.field.text)
		gts._save_box.field.text = "Lena Sommer"
		gts._save_box.confirm()
	await frames(2)
	check(RuleSets.matches("Lena Sommer", lena) and gts._save_box == null and gts._confirm != null and opt.text == "Gespeichert als „Lena Sommer“",
		"gespeichert: Spielmenü noch offen, zeigt „Gespeichert als …“ (%s)" % opt.text)
	check(gts.on_back() and gts._confirm == null, "Zurück schließt das Spielmenü")
	await frames(2)
	# Gastgeber geht: Leiste mit Hinweis, „Gespeichert: …“ und „Selbst eröffnen“
	host.leave()
	await wait(1.0)
	if not gts._conn_save.visible:
		gts._on_connection("closed")         # im selben Prozess kommt das „bye“ oft nicht an, der Gast versucht es dann neu
	check(gts._conn.visible and gts._conn_save.visible and gts._conn_host.visible and gts._conn_label.text.contains("beendet"), "Verbindung beendet: „Selbst eröffnen“ und „Regeln speichern“")
	check(gts._conn_sub.visible and gts._conn_sub.text.contains("Lena") and gts._conn_sub.text.contains("gemerkt"), "Leiste sagt, dass die Regeln gemerkt sind (%s)" % gts._conn_sub.text)
	check(gts._conn_save.text == "Gespeichert: „Lena Sommer“", "Leiste zeigt den Speicherstand (%s)" % gts._conn_save.text)
	check(inside(gts._conn.get_global_rect(), screen), "Leiste passt ins Bild (%s)" % str(gts._conn.get_global_rect()))
	gts._conn_save.pressed.emit()
	await frames(2)
	check(gts._save_box != null and is_instance_valid(gts._save_box), "Leiste: Speichern-Dialog")
	check(gts.on_back() and gts._save_box == null, "Zurück schließt den Dialog am Tisch")
	await frames(2)
	RulesBar.store(RuleConfig.preset("offiziell"))
	gts._conn_host.pressed.emit()
	await wait(0.4)
	var own := nav2.top() as HostLobbyScreen
	check(own != null and own.host != null and RuleSets.same(RulesBar.current(), lena) and RuleSets.same(own.host.rules, lena),
		"„Selbst eröffnen“: neue Gastgeber-Lobby mit den Regeln von Lena")
	if own != null and own.host != null:
		own.host.autosave = false
		check(own._rules._head.text == "Lena Sommer · 124 Karten" and not own._rules._offer.visible, "neue Lobby: Name des Satzes, kein Angebot nötig (%s)" % own._rules._head.text)
		own.host.leave()
	await wait(0.3)
	nav2.queue_free()
	nav2 = null
	if is_instance_valid(host):
		host.queue_free()
	await frames(2)


# ----------------------------------------------------------------- Dieses Gerät eröffnet mit denselben Regeln

func reopen_as_host() -> void:
	var lena := house()
	RulesBar.store(RuleConfig.preset("offiziell"))
	var lobby := HostLobbyScreen.new()
	nav.push(lobby, false)
	await frames(3)
	check(lobby.host != null and lobby.host.port() > 0, "neue Gastgeber-Lobby")
	if lobby.host == null or lobby.host.port() <= 0:
		return
	lobby.host.autosave = false
	check(lobby._rules._head.text == "Offiziell · 112 Karten", "Lobby: noch die eigenen Regeln")
	check(lobby._rules._offer.visible and lobby._rules._offer_btn.text == "Regeln von Lena übernehmen" and inside(lobby._rules._offer_btn.get_global_rect(), Rect2(0, 0, 1600, 720)),
		"Lobby bietet „Regeln von Lena“ zum Übernehmen an")
	check(inside(lobby._start.get_global_rect(), Rect2(0, 0, 1600, 720)) and not lobby._rules._summary.visible, "Start bleibt mit Angebot im Bild, das Angebot steht statt der Kurzbeschreibung")
	for i in 4:
		lobby.host.add_bot()
	await wait(0.3)
	var area := lobby._scroll.get_global_rect()
	var all_in := lobby._list.get_child_count() == 5
	for r in lobby._list.get_children():
		if not inside((r as Control).get_global_rect(), area):
			all_in = false
	check(all_in, "mit Angebot: alle 5 Spieler ganz sichtbar (N2; Liste %s)" % str(area))
	for i in 4:
		lobby._remove_bot()
		await frames(2)
	await wait(0.2)
	# „Regeln“ → gespeicherter Satz „Lenas Runde“
	lobby._rules._open_editor()
	await wait(0.3)
	var rs := nav.top() as RulesScreen
	check(rs != null and rs.start_tab == "anpassen", "Regel-Editor aus der Lobby")
	if rs == null:
		return
	check(chip(rs, "Lenas Runde") != null and host_chip(rs) != null and host_chip(rs).text == "Zuletzt gespielt bei Lena" and host_chip(rs).get_index() == 0,
		"Editor: Satz und „Zuletzt gespielt bei Lena“ (vorn)")
	chip(rs, "Lenas Runde").pressed.emit()
	await frames(1)
	check(active_chips(rs).has("Lenas Runde") and active_chips(rs).has("Zuletzt gespielt bei Lena") and not active_chips(rs).has("Lena Urlaub") and not active_chips(rs).has("Lena Sommer"),
		"geladen: Satz und Gastgeber-Platz hervorgehoben (%s)" % str(active_chips(rs)))
	nav.go_back()
	await wait(0.4)
	check(RuleSets.same(lobby.host.rules, lena) and lobby.host.lobby().get("rules", {}) == lena.to_dict(), "Lobby verteilt genau die Regeln von Lena")
	check(lobby._rules._head.text == "Lenas Runde · 124 Karten" and not lobby._rules._offer.visible, "Lobby: Name des Satzes, Angebot weg (%s)" % lobby._rules._head.text)
	# Über das Angebot der Lobby (ohne Editor)
	lobby._rules._open_editor()
	await wait(0.3)
	rs = nav.top() as RulesScreen
	rs.apply_preset("offiziell")
	nav.go_back()
	await wait(0.4)
	check(lobby.host.rules.preset_name() == "offiziell" and lobby._rules._offer.visible, "zwischendurch Offiziell, Angebot wieder da")
	lobby._rules._offer_btn.pressed.emit()
	await frames(2)
	check(RuleSets.same(lobby.host.rules, lena) and lobby.host.lobby().get("rules", {}) == lena.to_dict(), "Angebot übernommen: Lobby verteilt die Regeln von Lena")
	# Über den Gastgeber-Platz im Editor (ohne vorher zu speichern)
	lobby._rules._open_editor()
	await wait(0.3)
	rs = nav.top() as RulesScreen
	rs.apply_preset("offiziell")
	nav.go_back()
	await wait(0.4)
	check(lobby.host.rules.preset_name() == "offiziell", "zwischendurch Offiziell")
	lobby._rules._open_editor()
	await wait(0.3)
	rs = nav.top() as RulesScreen
	host_chip(rs).pressed.emit()
	await frames(1)
	check(host_chip(rs).theme_type_variation == "PrimaryButton", "„Zuletzt gespielt bei Lena“ geladen")
	nav.go_back()
	await wait(0.4)
	check(RuleSets.same(lobby.host.rules, lena), "Lobby: Regeln des letzten Gastgebers")
	# Start: die Partie läuft mit genau diesen Regeln; als Gastgeber merkt sich das Gerät nichts als „Zuletzt gespielt bei …“
	RuleSets.remember_host(RuleConfig.preset("mau_mau").to_dict(), "Ben")
	var slot: Variant = settings().get_value(RuleSets.HOST_KEY)
	lobby.host.add_bot()
	await frames(2)
	var h := lobby.host
	lobby.start_game()
	await wait(0.6)
	check(nav.top() is TableScreen and h.game != null and h.game.config.equals(lena), "Partie startet mit den Regeln von Lena")
	await wait(0.5)
	check(settings().get_value(RuleSets.HOST_KEY) == slot, "Gastgeber-Partie schreibt nichts in den Gastgeber-Platz")
	if nav.top() is TableScreen:
		(nav.top() as TableScreen)._leave_now()
	await wait(0.4)


# ----------------------------------------------------------------- Übungspartie (lokal): schreibt nichts in den Gastgeber-Platz

func local_game() -> void:
	var slot: Variant = settings().get_value(RuleSets.HOST_KEY)
	var src := GameStarter.local("solo", house(), [{"name": "Tester", "kind": "human"}, {"name": "Minka", "kind": "bot"}])
	check(src != null, "Übungspartie")
	if src == null:
		return
	nav.push(TableScreen.create(src, src.start), false)
	await wait(0.8)
	var ts := nav.top() as TableScreen
	check(ts != null and not ts.view.is_empty() and settings().get_value(RuleSets.HOST_KEY) == slot, "Übungspartie schreibt nichts in den Gastgeber-Platz")
	if ts != null:
		ts._leave_now()
	await wait(0.4)
