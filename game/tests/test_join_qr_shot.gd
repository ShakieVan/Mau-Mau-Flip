extends SceneTree
# Kontrollbild „Beitreten“ mit dem kleinen Knopf „QR-Code scannen“ in der Kopfzeile (Beta 1.4.3): Deutsch/Englisch, Schrift normal/sehr groß, dazu eine
# Meldung (Spiel-WLAN wird verbunden). Nicht als Test gestartet (_shot).
#   tools/godot_run.ps1 -Script res://tests/test_join_qr_shot.gd -Resolution 1600x720 -EnvPairs "SHOT_DIR=…"
var out_dir := ""

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://")
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1600, 720)
	QrJoin.wifi_stub = {"sdk": 34, "state": {"status": "connecting"}}
	for lang in ["de", "en"]:
		I18n.set_language(lang)
		for level in ["normal", "sehr_gross"]:
			var nav := ScreenNav.new()
			nav.autostart = false
			root.add_child(nav)
			UiFonts.set_level(level, root)
			await create_timer(0.3).timeout
			var js := JoinScreen.new()
			nav.push(js, false)
			await create_timer(0.8).timeout
			root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("beitreten_qr_%s_%s.png" % [lang, level]))
			js.handle_scan("WIFI:T:WPA;S:AndroidShare_4821;P:k7m3x9q2w5r8t4z;;")
			await create_timer(0.4).timeout
			root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("beitreten_qr_%s_%s_wlan.png" % [lang, level]))
			QrJoin.wifi_release()
			nav.queue_free()
			await create_timer(0.2).timeout
	UiFonts.set_level("normal", root)
	I18n.set_language("de")
	QrJoin.wifi_stub = null
	quit()
