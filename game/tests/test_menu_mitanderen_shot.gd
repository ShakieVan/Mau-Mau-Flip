extends SceneTree
# Kontrollbild Hauptmenü und „Mit anderen spielen“ (Deutsch und Englisch), nicht als Test gestartet (_shot).
#   tools/godot_run.ps1 -Script res://tests/test_menu_mitanderen_shot.gd -Resolution 1600x720 -EnvPairs "SHOT_DIR=…"
var out_dir := ""

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://")
	for lang in ["de", "en"]:
		I18n.set_language(lang)
		var nav := ScreenNav.new()
		nav.autostart = false
		root.add_child(nav)
		await create_timer(0.4).timeout
		nav.push(MainMenuScreen.new(), false)
		await create_timer(0.8).timeout
		root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("menu_%s_haupt.png" % lang))
		nav.push(WlanScreen.new(), false)
		await create_timer(0.8).timeout
		root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("menu_%s_mitanderen.png" % lang))
		nav.queue_free()
		await create_timer(0.2).timeout
	I18n.set_language("de")
	quit()
