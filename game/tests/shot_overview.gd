extends SceneTree
# Kontrollbilder für den Koordinator: Hauptmenü und eine laufende Übungspartie (mit Renderer, nicht headless).
var out_dir := ""

func _init() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(2.0)
	_shot("menu")
	var cfg := RuleConfig.preset("offiziell")
	var players := [{"name": "Du", "kind": "human"}, {"name": "Lena", "kind": "bot"}, {"name": "Tom", "kind": "bot"}, {"name": "Mia", "kind": "bot"}]
	GameStarter.test_speed = 0.3
	var source := GameStarter.local("solo", cfg, players, 4711)
	main.push(TableScreen.create(source, source.start))
	await _wait(4.0)
	_shot("tisch1")
	await _wait(8.0)
	_shot("tisch2")
	print("RESULT: 1 ok")
	quit(0)

func _wait(s: float) -> void:
	await create_timer(s).timeout

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join("shot_%s.png" % name))
