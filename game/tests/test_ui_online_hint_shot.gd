extends SceneTree
# Kontrollbilder Beta 1.3.3 (mit Renderer; „_shot“: vom Testlauf ausgenommen):
#   tools/godot_run.ps1 -Script res://tests/test_ui_online_hint_shot.gd -Resolution 1600x720
# Zurück-Pfeil oben links (jetzt gezeichnet wie das ☰, statt eingefärbtem Bild – Nutzerbefund: schwarzes Quadrat) und die Hinweise
# bei Online-Aussetzern, je Tag/Nacht, normal und groß:
# docs/geraetetest/1.3.3/online_hinweis_<gastgeber|gast|gastweg>_<normal|gross>_<tag|nacht>.png

var nav: ScreenNav
var ts: TableScreen
var shots := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(1600, 720)
	var out := ProjectSettings.globalize_path("res://").path_join("../docs/geraetetest/1.3.3").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	nav = ScreenNav.new()
	root.add_child(nav)
	await process_frame
	var players := [{"name": "Du", "kind": "human"}, {"name": "Püppi", "kind": "bot"}, {"name": "Socke", "kind": "bot"}]
	var src := GameStarter.local("solo", RuleConfig.preset("familie"), players, 1)
	src.speed = 0.0
	ts = TableScreen.create(src, func() -> void: src.start())
	nav.push(ts, false)
	await create_timer(3.0).timeout
	var texts := {"gastgeber": "Online-Verbindung unterbrochen – verbinde neu …", "gast": "Verbindung zum Gastgeber unterbrochen – warte …",
		"gastweg": "Gastgeber kurz weg – warte …"}
	for big in [false, true]:
		ts.table.set_big(big)
		for tm in ["tag", "nacht"]:
			ts.table.night = 1.0 if tm == "nacht" else 0.0
			for k in texts:
				ts._conn_label.text = texts[k]
				for b: Control in [ts._conn_menu, ts._conn_save, ts._conn_host, ts._conn_sub]:
					b.visible = false
				ts._conn.visible = true
				ts._layout()
				for i in 6:
					await process_frame
				ts.table.night = 1.0 if tm == "nacht" else 0.0
				await process_frame
				await process_frame
				root.get_texture().get_image().save_png(out.path_join("online_hinweis_%s_%s_%s.png" % [k, "gross" if big else "normal", tm]))
				shots += 1
	print("RESULT: %d ok" % shots)
	quit(0)
