extends SceneTree
# Kontrollbilder der Hand (Modul F1a) mit echtem Renderer, Querformat 1600×720, Szene res://scenes/dev/hand_demo.tscn:
# Fächer mit 5 Karten, Lupe mit 12 Karten (Finger auf einer Karte), Bogen-Karussell mit 25 Karten, angehobene Karte,
# Großansicht mit „?“ (gehalten und nach unten gezogen), Großansicht offen mit „?“-Knopf, Rückseiten-Ansicht, dunkle Seite.
# Aufruf: tools/godot_run.ps1 -Script res://tests/test_ui_hand_shots.gd -Resolution 1600x720 -Timeout 180
# Bilder: docs/module/F1a_<name>.png (Umgebungsvariable SHOT=<name> nimmt nur ein Bild auf).
var demo: Node2D
var hand: HandView
var only := ""
var out_dir := ""


func _initialize() -> void:
	only = OS.get_environment("SHOT")
	out_dir = ProjectSettings.globalize_path("res://").path_join("../docs/module").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	call_deferred("run")


func frames(n: int) -> void:
	for i in n:
		await process_frame


func wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func want(name: String) -> bool:
	return only == "" or only == name


func shot(name: String) -> void:
	await frames(3)
	var path := out_dir.path_join("F1a_%s.png" % name)
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)


# Lokale Position zum Antippen einer Karte: im sichtbaren Streifen oben links.
func tap_point(id: int) -> Vector2:
	var v := hand.card_view(id)
	var h := v.card_size() * v.scale.x * 0.5
	return v.position + Vector2(-h.x + 26.0, -h.y + 60.0).rotated(v.rotation)


func run() -> void:
	demo = load("res://scenes/dev/hand_demo.tscn").instantiate()
	root.add_child(demo)
	await frames(2)
	hand = demo.hand
	demo.show_debug = false
	if want("hand5"):
		demo.deal(5, 3)
		await wait(1.6)
		await shot("hand5")
	if want("hand12"):
		demo.deal(12, 5)
		await wait(1.4)
		var ids := hand.get_order()
		var p := tap_point(ids[6])
		hand.touch_down(p)
		hand.touch_move(p + Vector2(18, 0))
		hand.touch_move(p + Vector2(28, 0))
		await wait(0.5)
		await shot("hand12")
		hand.touch_up(p + Vector2(28, 0))
	if want("hand25"):
		demo.deal(25, 7)
		await wait(1.6)
		await shot("hand25")
	if want("schwung"):
		# Karussell mitten im Schwung: Karten neigen sich gegen die Bewegung
		demo.deal(25, 7)
		await wait(1.6)
		var p := Vector2(1000, 650)
		hand.touch_down(p)
		for k in range(1, 9):
			await process_frame
			hand.touch_move(p - Vector2(45.0 * k, 0))
		hand.touch_up(p - Vector2(360, 0))
		await wait(0.12)
		await shot("schwung")
	if want("angehoben"):
		demo.deal(9, 2)
		await wait(1.2)
		var pick := -1
		for id in hand.get_order():
			if demo._fits(str(demo.pairs[id][demo.side])):
				pick = id
				break
		hand.select(pick)
		await wait(0.8)
		await shot("angehoben")
		hand.select(-1)
	if want("grossansicht"):
		demo.deal(9, 2)
		await wait(1.2)
		var ids := hand.get_order()
		var p := tap_point(ids[4])
		hand.touch_down(p)
		await wait(0.45)
		hand.touch_move(p + Vector2(2, 20))
		hand.touch_move(p + Vector2(4, 82))
		await wait(0.5)
		await shot("grossansicht")
		hand.touch_up(p + Vector2(4, 30))
		await wait(0.3)
	if want("grossansicht_knopf"):
		demo.deal(9, 2)
		await wait(1.2)
		var ids := hand.get_order()
		var p := tap_point(ids[6])
		hand.touch_down(p)
		await wait(0.45)
		hand.touch_up(p)
		await wait(0.5)
		await shot("grossansicht_knopf")
		hand.close_big_view()
	if want("rueckseiten"):
		demo.deal(9, 2)
		await wait(1.0)
		hand.set_peek_backs(true)
		await wait(1.2)
		await shot("rueckseiten")
		hand.set_peek_backs(false)
	if want("dunkel"):
		demo.deal(12, 11)
		demo.set_side("dunkel")
		await wait(1.6)
		await shot("dunkel")
	quit(0)
