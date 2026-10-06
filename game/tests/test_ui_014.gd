extends SceneTree
# Oberfläche 0.1.4, headless: Strahlenkranz für den Spieler am Zug (Gegner, eigener Platz, Hand), Denkblase nach 5 s, eigene
# Kartenzahl, „?“ der Großansicht nicht auf dem Mau-Knopf, sanfte Strahlen am Rundenende, Partiestart wie „Nächste Runde“,
# Stempel „Flip-Überraschung“, Regeltexte (Familie, Wünscher +2 immer erlaubt), vertretener Gast „Computer spielt“.

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


func run() -> void:
	await _turn_halo()
	await _think_bubble()
	await _help_badge()
	await _start_deal()
	await _round_end_rays()
	await _flip_surprise()
	_texts()
	print("RESULT: %d ok" % ok)
	await CleanExit.finish(self, 0 if fails == 0 else 1)


func _turn_halo() -> void:
	var s := TableSamples.create(4, 5, [7, 6, 5, 3])
	var v := s.view_for(0)
	v["turn"] = 2
	var t := TableView.new()
	root.add_child(t)
	t.set_hand(DemoHand.new())
	t.apply_view(v)
	await process_frame
	check(t.seat_node(2).halo().active and not t.seat_node(1).halo().active, "Kranz nur beim Spieler am Zug")
	check(t.seat_node(2).halo().box.size.y > 100.0, "Kranz umfasst Name und Fächer (%s)" % str(t.seat_node(2).halo().box))
	check(t.me_badge.visible and t.me_badge.count() == 7, "eigene Kartenzahl sichtbar (7)")
	check(not t.me_badge.halo().active and not t._hand_halo.active, "eigener Kranz aus, wenn ein anderer dran ist")
	v = s.view_for(0)
	v["turn"] = 0
	t.apply_view(v)
	check(t.me_badge.halo().active and t._hand_halo.active and not t.seat_node(2).halo().active, "eigener Zug: Kranz an Name und Hand")
	await create_timer(0.4).timeout
	check(t.seat_node(2).halo().visible == false, "ausgeblendeter Kranz ist unsichtbar (kein Dauer-Neuzeichnen)")
	t.night = 1.0
	check(is_equal_approx(t.me_badge.halo().night, 1.0) and is_equal_approx(t._hand_halo.night, 1.0), "nachts bläulicher Kranz")
	# Vertretener Gast
	var p := {"seat": 1, "name": "Kim", "count": 4, "connected": false, "substituted": true}
	t.seat_node(1).set_player(p)
	check(t.seat_node(1).status_text() == "Computer spielt", "vertretener Gast: „Computer spielt“")
	p.erase("substituted")
	t.seat_node(1).set_player(p)
	check(t.seat_node(1).status_text() == "getrennt", "getrennter Gast ohne Vertretung: „getrennt“")
	t.queue_free()
	await process_frame


func _think_bubble() -> void:
	var s := TableSamples.create(3, 8, [5, 5, 5])
	var v := s.view_for(0)
	v["turn"] = 1
	var t := TableView.new()
	root.add_child(t)
	t.apply_view(v)
	var node := t.seat_node(1)
	check(not node.thinking(), "keine Denkblase sofort")
	node._think = OpponentSeat.THINK_AFTER + 0.1
	check(node.thinking(), "Denkblase nach 5 s")
	t.director.auto_process = false
	t.play_event({"e": "draw", "seat": 1, "count": 1}, 1.0)
	check(not node.thinking(), "Denkblase weg, sobald er handelt")
	node._think = 9.0
	v["turn"] = 2
	t.apply_view(v)
	check(not node.thinking(), "nicht mehr dran: keine Denkblase")
	t.queue_free()
	await process_frame


func _help_badge() -> void:
	var h := HandView.new()
	root.add_child(h)
	var blocked := Rect2(1400, 520, 150, 150)
	var arr: Array[Rect2] = [blocked]
	h.avoid_global = arr
	check(h._badge_blocked(Vector2(1470, 600)), "„?“ auf dem Mau-Knopf wird erkannt")
	check(not h._badge_blocked(Vector2(900, 600)), "„?“ daneben ist frei")
	h.queue_free()
	var t := TableView.new()
	root.add_child(t)
	var hv := HandView.new()
	t.set_hand(hv)
	await process_frame
	check((hv.avoid_global as Array).size() == 1, "Tisch meldet den Mau-Knopf an die Hand")
	hv.big_view_changed.emit(3)
	check(t.mau_button.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Großansicht offen: Mau-Knopf nimmt keine Eingaben")
	hv.big_view_changed.emit(-1)
	check(t.mau_button.mouse_filter == Control.MOUSE_FILTER_STOP, "Großansicht zu: Mau-Knopf wieder aktiv")
	t.queue_free()
	await process_frame


func _start_deal() -> void:
	var s := TableSamples.create(4, 3, [7, 7, 7, 7])
	var v := s.view_for(0)
	var t := TableView.new()
	root.add_child(t)
	t.set_hand(DemoHand.new())
	t.director.auto_process = false
	var ev := [{"e": "round_start", "round": 1, "dealer": 0}, {"e": "deal", "dealer": 0, "count": 7}]
	t.handle_state(ev, v)
	var d := t.play_event(ev[1], 1.0)
	check(d > 0.3, "Austeilen dauert (%.2f s)" % d)
	check(t.seat_node(1) != null and t.seat_node(3) != null, "Partiestart: Plätze stehen vor dem Austeilen")
	check(t.seat_node(1).count() == 0, "Plätze beginnen leer")
	check(t._pile.count > int(v.get("draw_count", 0)), "Stapel zeigt die volle Höhe (%d)" % t._pile.count)
	check(t.discard_cards().is_empty(), "Ablage leer bis zur Startkarte")
	t.director.flush()
	check(t.seat_node(1).count() == int(v["players"][1]["count"]), "nach dem Austeilen: Kartenzahl der Sicht")
	t.queue_free()
	await process_frame


func _round_end_rays() -> void:
	var s := TableSamples.create(3, 4, [0, 3, 2])
	var v := s.view_for(0)
	v["phase"] = "round_over"
	v["ranking"] = [0]
	var t := TableView.new()
	root.add_child(t)
	t.apply_view(v)
	var kids := t._rays_fx.get_children()
	check(kids.size() == 1 and kids[0] is TableEffects.SoftRaysFx, "Rundenende: sanfte Strahlen statt Keilen")
	check(not t.me_badge.halo().active, "Rundenende: kein Kranz")
	t.queue_free()
	await process_frame


func _flip_surprise() -> void:
	var s := TableSamples.create(3, 6, [5, 5, 5])
	var t := TableView.new()
	root.add_child(t)
	t.apply_view(s.view_for(0))
	t.director.auto_process = false
	var d := t.play_event({"e": "flip_surprise", "seat": 1, "face": "dunkel_pink_plus5"}, 1.0)
	check(d > 0.3 and t._plus_armed == 5 and t._last_player == 1, "Flip-Überraschung: Stempel, +5 wie gelegt")
	t.queue_free()
	await process_frame


func _texts() -> void:
	var fam := RuleConfig.preset("familie")
	check(fam.preset_name() == "familie" and fam.flip_surprise == "on", "Familie mit Flip-Überraschung erkannt")
	check(RulesBar.preset_title(fam) == "Familie", "Titel „Familie“")
	check(RulesBar.summary(fam).contains("Flip-Überraschung"), "Kurzbeschreibung nennt die Flip-Überraschung")
	var c := RuleConfig.preset("offiziell")
	c.wild_restriction = "free"
	check(RulesBar.summary(c).contains("Wünscher +2 immer erlaubt") and not RulesBar.summary(c).contains("Joker frei"), "free: „Wünscher +2 immer erlaubt“")
	var found := false
	for o in RulesScreen.OPTIONS:
		if str(o[0]) == "flip_surprise":
			found = str(o[1]) == "Flip-Überraschung"
	check(found, "Regelbildschirm: Zeile „Flip-Überraschung“")
	var g := UiTheme.grabber_texture(46, UiPalette.CREAM, UiPalette.INK)
	check(g.get_width() == 46, "Tempo-Regler: großer Griff")
