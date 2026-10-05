extends SceneTree
# Rauchtest CardView/CardTextures: Platzhalter ohne Kartenbilder, Wende, Umriss.
func _init() -> void:
	var ok := 0
	var c := CardView.new().setup(3, "hell_rot_7", "dunkel_lila_6")
	root.add_child(c)
	if c.current_key() == "hell_rot_7": ok += 1
	else: print("FAIL: Vorderseite")
	c.width = 150.0
	if absf(c.card_size().y - 150.0 * 466.0 / 300.0) < 0.01: ok += 1
	else: print("FAIL: Größe")
	c.show_side(false)
	if c.current_key() == "dunkel_lila_6": ok += 1
	else: print("FAIL: Rückseite")
	c.position = Vector2(100, 100)
	if c.contains_global_point(Vector2(100, 100)) and not c.contains_global_point(Vector2(400, 400)): ok += 1
	else: print("FAIL: Treffertest")
	if CardTextures.color_of("dunkel_tuerkis_plus5") == "tuerkis" and CardTextures.color_of("hell_wuenscher") == "": ok += 1
	else: print("FAIL: Farbe aus Schlüssel")
	print("RESULT: %d ok" % ok)
	quit(0 if ok == 5 else 1)
