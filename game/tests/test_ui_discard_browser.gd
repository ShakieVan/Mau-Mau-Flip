extends SceneTree
# „Ablage durchsehen“ (Beta 1.0.1) am echten Tisch mit einer Regel-Sicht (view.discard_log): Tipp auf die Ablage schiebt die
# oberste Karte zur Seite (Leger, Wunschfarbe, Zähler), Tipp auf den Seitenstapel eine zurück, Tipp sonst alle zurück; eine neue
# Ablage (jemand legt) setzt sofort zurück; Nacht ohne Fehler. Mit Fenster (ohne --headless) und SHOT=1 entsteht das Kontrollbild
# docs/module/F2_ablage_durchsehen.png (Nacht, zwei Karten verschoben):
#   godot_run.ps1 -Script res://tests/test_ui_discard_browser.gd -Resolution 1600x720 -EnvPairs 'SHOT=1'

const CleanExit := preload("res://tests/clean_exit.gd")

var ok := 0
var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		ok += 1
	else:
		fails += 1
		print("FAIL: " + what)


func _initialize() -> void:
	call_deferred("run")


func _game() -> MauGame:
	var g := RulesFixture.build(RuleConfig.new(), 3, {"hands": [["hell_rot_7", "hell_blau_1", "hell_gelb_2"], ["hell_wuenscher", "hell_gelb_1", "hell_rot_1"],
		["hell_blau_4", "hell_gruen_2", "hell_gruen_1"]], "top": "hell_rot_5", "discard": ["hell_gelb_3"]})
	g.apply(0, {"a": "play", "card": RulesFixture.card(g, 0, "hell_rot_7")})
	g.apply(1, {"a": "play", "card": RulesFixture.card(g, 1, "hell_wuenscher"), "color": "blau"})
	return g


# Weltpunkt des Tisches → lokaler Tippunkt der Tischfläche
func _tap_world(t: TableView, world: Vector2) -> bool:
	var wn: Node2D = t.discard_layer().get_parent()
	var g := wn.get_global_transform() * world
	return t._tap(t.get_global_transform().affine_inverse() * g)


func _tap_discard(t: TableView) -> bool:
	return _tap_world(t, t.discard_position())


func _tap_side(t: TableView) -> bool:
	var b := t.discard_browser
	return _tap_world(t, t.discard_position() + b._side_pos(b.moved - 1))


func run() -> void:
	var g := _game()
	var t := TableView.new()
	root.add_child(t)
	t.set_hand(DemoHand.new())
	t.director.auto_process = false
	t.apply_view(g.view_for(2))
	await process_frame
	var b := t.discard_browser
	check(b.total() == 4 and b.moved == 0 and not b.is_open(), "Protokoll mit 4 Karten übernommen (%d)" % b.total())
	check(_tap_discard(t), "Tipp auf die Ablage verbraucht")
	check(b.moved == 1 and b.is_open() and not t.discard_layer().visible, "eine Karte zur Seite, Tischablage ausgeblendet")
	var e: Dictionary = b.entries[b.entries.size() - b.moved]
	check(b.entry_label(e) == "von Ben" and str(e.c) == "blau" and b.counter_text() == "1 von 4",
		"Beschriftung: %s, Wunsch %s, %s" % [b.entry_label(e), str(e.c), b.counter_text()])
	_tap_discard(t)
	_tap_discard(t)
	e = b.entries[b.entries.size() - b.moved]
	check(b.moved == 3 and b.entry_label(e) == "Startkarte" and b.counter_text() == "3 von 4", "drei zur Seite, Startkarte (%s)" % b.entry_label(e))
	await create_timer(0.5).timeout
	check(_tap_side(t) and b.moved == 2, "Tipp auf den Seitenstapel schiebt eine zurück (%d)" % b.moved)
	e = b.entries[b.entries.size() - b.moved]
	check(b.entry_label(e) == "von Anna", "darunter Annas Karte (%s)" % b.entry_label(e))
	await create_timer(0.5).timeout
	_tap_world(t, t.discard_position() + Vector2(250, 200))      # Tipp sonst (wirkt danach normal weiter)
	check(b.moved == 0, "Tipp sonst schiebt alle zurück")
	await create_timer(0.8).timeout
	check(not b.is_open() and t.discard_layer().visible, "nach dem Zurückschieben wieder die Tischablage")
	# alle Karten durch, dann ein weiterer Tipp: nichts mehr zu schieben, bleibt offen
	for i in 5:
		_tap_discard(t)
	check(b.moved == 4, "nicht mehr als die Ablage (%d)" % b.moved)
	# neue Ablage: sofort zurück
	b.close_now()
	_tap_discard(t)
	var ev: Array = (g.apply(2, {"a": "play", "card": RulesFixture.card(g, 2, "hell_blau_4")}) as Dictionary).events
	t.handle_state(g.events_for(2, ev), g.view_for(2))
	check(b.moved == 0 and not b.is_open(), "jemand legt: alles springt zurück")
	t.director.step(30.0)
	check(b.total() == 5 and b.moved == 0, "neues Protokoll übernommen (%d)" % b.total())
	# gleiches Protokoll erneut: kein Rücksetzen
	_tap_discard(t)
	t.apply_view(g.view_for(2))
	check(b.moved == 1, "gleiche Sicht setzt nicht zurück")
	# Nacht
	t.set_night(1.0)
	_tap_discard(t)
	await process_frame
	check(b.moved == 2 and b.night == 1.0, "Nacht")
	if OS.get_environment("SHOT") != "" and DisplayServer.get_name() != "headless":
		await create_timer(0.8).timeout
		var img := root.get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://").path_join("../docs/module/F2_ablage_durchsehen.png").simplify_path()
		img.save_png(path)
		print("Bild: " + path)
	print("RESULT: %d ok" % ok if fails == 0 else "RESULT: %d ok, %d FAIL" % [ok, fails])
	await CleanExit.finish(self, 0 if fails == 0 else 1)
