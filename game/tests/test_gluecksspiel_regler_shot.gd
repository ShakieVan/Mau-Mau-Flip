extends SceneTree
# Kontrollbilder des Reglers „Glücksspiel-Treffer“ (Nutzer 07.11.2026: „von 1:3 bis 1:10 stufenlos“) mit echtem Renderer (nicht
# headless; wegen „_shot“ startet tools/build.ps1 das Skript nicht als Test): Regel-Editor, Abschnitt „Hausregeln mit Zusatzkarten“
# mit Familie (bis 1:6), Regler auf 1:7, auf 1:3, gesperrt (Offiziell), nachts (dunkle Karte wie im Spiel) und auf Englisch.
# Läuft mit eigener Einstellungsdatei (App.settings wird ersetzt), die echten Einstellungen bleiben unberührt.
#   tools/godot_run.ps1 -Script res://tests/test_gluecksspiel_regler_shot.gd -Resolution 1600x720 -EnvPairs "SHOT_DIR=…"

const CleanExit := preload("res://tests/clean_exit.gd")
const SETTINGS_PATH := "user://test_gluecksspiel_regler_einstellungen.json"

var out_dir := ""
var shots := 0


func _initialize() -> void:
	call_deferred("run")


func wait(t: float) -> void:
	await create_timer(t).timeout


func run() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://")
	var app := UiApp.app()
	var real: AppSettings = app.settings
	_remove_files(SETTINGS_PATH)
	app.settings = AppSettings.new(SETTINGS_PATH)
	RulesBar.store(RuleConfig.preset("familie"))
	var nav := ScreenNav.new()
	nav.autostart = false
	root.add_child(nav)
	await wait(0.3)
	var rs := RulesScreen.new()
	rs.start_tab = "anpassen"
	nav.push(rs, false)
	await wait(0.8)
	var odds := rs._controls["gamble_max"] as Control
	var slider := odds.find_child("Regler", true, false) as HSlider
	# Abschnitt mit den Hausregeln ins Bild holen (Zeile „Glücksspiel“ oben, darunter der Regler und „Farbe mit ablegen“)
	rs._editor.scroll_vertical = int((rs._controls["gamble_cards"] as Control).get_parent().position.y)
	await wait(0.4)
	shot("familie")
	slider.value = 7.0
	await wait(0.3)
	shot("1_7")
	slider.value = 3.0
	await wait(0.3)
	shot("1_3")
	rs.apply_preset("offiziell")
	await wait(0.3)
	shot("gesperrt")
	rs.apply_preset("familie")
	slider.value = 8.0
	var card := rs._editor.get_child(0) as PanelContainer
	ScreenKit.set_card_night(card, true)
	await wait(0.4)
	shot("nacht")
	ScreenKit.set_card_night(card, false)
	TranslationServer.set_locale("en")
	await wait(0.6)
	shot("englisch")
	TranslationServer.set_locale("de")
	app.settings = real
	_remove_files(SETTINGS_PATH)
	print("RESULT: %d ok" % shots)
	await CleanExit.finish(self, 0)


func _remove_files(p: String) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(p + suffix):
			DirAccess.remove_absolute(p + suffix)


func shot(shot_name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join("optik_gluecksspiel_regler_%s.png" % shot_name))
	shots += 1
