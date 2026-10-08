extends SceneTree
# Großer Modus (Beta 1.1.1, BigLayout + TableView.set_big), headless: wichtige Bedienelemente überlappen nicht (Zurück, Stapel,
# Ablage, Farbe, Liste, Mau, Sortieren/Rückseiten, Hand) in mehreren Bildgrößen; Reihenfolge der Spielerliste nach Spielrichtung
# (wer dran ist oben, darunter der Nächste), Rollen beim Zugwechsel, andersherum beim Richtungswechsel; Umschalten live hin und
# zurück; Tipp auf eine Listenzeile öffnet die Rückseiten; Kartenflüge docken an die Listenzeile an.

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
	_geometry()
	_order()
	await _table()
	print("RESULT: %d ok" % ok)
	await CleanExit.finish(self, 0 if fails == 0 else 1)


func _geometry() -> void:
	for sz: Vector2 in [Vector2(1600, 720), Vector2(1600, 740), Vector2(1600, 800), Vector2(1600, 900), Vector2(1480, 720)]:
		var w := BigLayout.pile_w(sz)
		var h := w * CardView.ASPECT
		var menu := Rect2(14, 10, BigLayout.MENU, BigLayout.MENU)
		var pile := Rect2(BigLayout.draw_pile_pos(sz) - Vector2(w, h) * 0.5, Vector2(w, h))
		var disc := Rect2(BigLayout.discard_pos(sz) - Vector2(w, h) * 0.5, Vector2(w, h))
		var pile_top := Rect2(pile.position, Vector2(w, h * 0.5))
		var disc_top := Rect2(disc.position, Vector2(w, h * 0.5))
		var list := BigLayout.list_rect(sz)
		var mau := Rect2(BigLayout.mau_pos(sz), Vector2(BigLayout.MAU, BigLayout.MAU))
		var col := BigLayout.color_column(sz)
		var hand := BigLayout.hand_rect(sz)
		var card_h := HandLayout.card_width(hand.size.y) * CardView.ASPECT
		var hand_vis := Rect2(hand.position.x, sz.y - card_h * 0.5, hand.size.x, card_h * 0.5)
		var sort := Rect2(BigLayout.sort_pos(sz), Vector2(250, BigLayout.PILL_H))
		var backs := Rect2(BigLayout.backs_pos(sz), Vector2(250, BigLayout.PILL_H))
		var tag := "%dx%d" % [sz.x, sz.y]
		check(h >= sz.y * 0.66, "%s: Ablage fast so hoch wie das Bild (%.0f)" % [tag, h])
		check(w >= 300.0, "%s: Stapel riesig (%.0f px breit)" % [tag, w])
		var screen := Rect2(Vector2.ZERO, sz)
		for r: Rect2 in [pile, disc, list, mau, sort, backs]:
			check(screen.encloses(r), "%s: %s im Bild" % [tag, str(r)])
		var pairs := [["Zurück", menu, "Stapel", pile], ["Stapel", pile, "Ablage", disc], ["Ablage", disc, "Liste", list],
			["Liste", list, "Mau", mau], ["Hand", hand_vis, "Mau", mau], ["Hand", hand_vis, "Liste", list],
			["Hand", hand_vis, "obere Hälfte Ablage", disc_top], ["Hand", hand_vis, "obere Hälfte Stapel", pile_top],
			["Sortieren", sort, "Rückseiten", backs], ["Sortieren", sort, "Hand", hand_vis], ["Rückseiten", backs, "Hand", hand_vis],
			["Farbe", col, "Ablage", disc], ["Farbe", col, "Liste", list]]
		for p in pairs:
			check(not (p[1] as Rect2).intersects(p[3] as Rect2), "%s: %s überlappt nicht %s" % [tag, p[0], p[2]])
		check(col.size.x >= BigLayout.COLOR_MIN - 1.0, "%s: Farbspalte breit genug" % tag)
		check(BigLayout.hint_y(sz) < sz.y - card_h * 0.5, "%s: Hinweisleiste über den Handkarten" % tag)
		# Zeilen: alle sichtbaren innerhalb der Liste, mindestens Touch-Höhe
		for n in range(2, 11):
			var rows := BigLayout.list_rows(sz, n)
			var k := int(rows["k"])
			check(k >= mini(n, 4), "%s n=%d: mindestens %d Zeilen sichtbar (%d)" % [tag, n, mini(n, 4), k])
			var last := BigLayout.row_y(float(k - 1), rows) + float(rows["h1"]) * 0.5
			var first := BigLayout.row_y(0.0, rows) - float(rows["h0"]) * 0.5
			check(first >= list.position.y - 0.5 and last <= list.end.y + 0.5, "%s n=%d: Zeilen in der Liste" % [tag, n])
			check(float(rows["h1"]) >= BigLayout.ROW_MIN - 0.5, "%s n=%d: Zeilen groß genug" % [tag, n])


func _order() -> void:
	var o := BigLayout.list_order([0, 1, 2, 3], 1, 1)
	check(o == [1, 2, 3, 0], "Richtung 1: dran oben, dann der Nächste (%s)" % str(o))
	o = BigLayout.list_order([3, 1, 0, 2], 1, -1)
	check(o == [1, 0, 3, 2], "Richtung −1: andersherum (%s)" % str(o))
	# Rollen: die oberste Zeile (Stelle 0) wandert nach oben hinaus und kommt unten wieder herein (kürzester Weg)
	check(is_equal_approx(BigLayout.roll_target(0.0, 3, 4), -1.0), "oben raus")
	check(is_equal_approx(BigLayout.roll_target(2.0, 1, 4), 1.0), "eins hoch")
	check(is_equal_approx(BigLayout.roll_target(0.0, 1, 2), -1.0), "zwei Spieler: rollt nach oben")
	check(is_equal_approx(BigLayout.wrap(-1.0, 4), 3.0) and is_equal_approx(BigLayout.wrap(-0.25, 4), -0.25), "Stelle umbrechen")
	check(BigLayout.row_alpha(-0.5, 4, 4) == 0.0 and BigLayout.row_alpha(0.0, 4, 4) == 1.0 and BigLayout.row_alpha(3.4, 4, 4) < 0.3,
		"Ein- und Ausblenden am Rand")


func _settle(t: TableView, frames := 90) -> void:
	for i in frames:
		await process_frame


func _table() -> void:
	root.size = Vector2i(1600, 720)
	for n in [3, 8]:
		var s := TableSamples.create(n, 11 + n, [])
		s.turn = 1
		var t := TableView.new()
		root.add_child(t)
		t.set_hand(DemoHand.new())
		t.set_big(true)
		t.apply_view(s.view_for(0))
		await _settle(t, 4)
		check(t.big and t.seat_node(1).list_mode and t.me_badge.list_mode, "%d Spieler: Plätze sind Listenzeilen" % n)
		check(not t._ring.visible and t._bg.calm, "%d Spieler: ruhiger Hintergrund ohne Richtungsring" % n)
		check(t.list_index(1) == 0 and t.list_index(2) == 1 and t.list_index(0) == n - 1, "%d Spieler: Reihenfolge dran → nächster" % n)
		var list := BigLayout.list_rect(t.size)
		check(list.has_point(t.seat_node(1).position) and list.has_point(t.seat_node(2).position), "%d Spieler: Zeilen rechts in der Liste" % n)
		check(t.seat_node(1).position.y < t.seat_node(2).position.y, "%d Spieler: wer dran ist steht oben" % n)
		# Zugwechsel: Liste rollt (Ziel sofort, Lage weich)
		s.advance(1)
		t.apply_view(s.view_for(0))
		check(t.list_index(2) == 0 and t.list_index(1) == n - 1, "%d Spieler: Zugwechsel rollt weiter" % n)
		await _settle(t)
		check(absf(t.seat_node(2).position.y - BigLayout.row_y(0.0, BigLayout.list_rows(t.size, n))) < 1.0, "%d Spieler: Liste ist nachgerollt" % n)
		# Richtungswechsel: andersherum, der vorige Platz ist jetzt der Nächste
		s.dir = -1
		t.apply_view(s.view_for(0))
		check(t.list_index(2) == 0 and t.list_index(1) == 1, "%d Spieler: Richtungswechsel zeigt andersherum" % n)
		check(t._list_flip >= 0.0, "%d Spieler: Zeilen klappen beim Richtungswechsel" % n)
		await create_timer(0.9).timeout
		check(t._list_flip < 0.0 and is_equal_approx(t.seat_node(2).flip_y, 1.0), "%d Spieler: Klappen beendet (%.2f, %.2f)" % [n, t._list_flip, t.seat_node(2).flip_y])
		# Tipp auf eine Zeile: Rückseiten (sichtbar laut Regel)
		var node := t.seat_node(2)
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		for pressed in [true, false]:
			e = e.duplicate()
			e.pressed = pressed
			e.position = node.position
			t._gui_input(e)
		check(t.backs_viewer.visible, "%d Spieler: Tipp auf die Zeile öffnet die Rückseiten" % n)
		t.backs_viewer.hide()
		# Kartenflug dockt an die Zeile an (Ziel = große Kartenzahl)
		check(node.list_rect().has_point(node.to_local(node.fan_global_center())), "%d Spieler: Flugziel in der Zeile" % n)
		# Knöpfe größer, Mau-Knopf an der alten Stelle (rechts unten)
		check(t.mau_button.size.x == BigLayout.MAU and t._sort_btn.size.y >= BigLayout.PILL_H, "%d Spieler: Knöpfe größer" % n)
		check(t.pile_w > 300.0 and t._pile.top.width == t.pile_w, "%d Spieler: Stapel riesig" % n)
		# zurück in den normalen Modus
		t.set_big(false)
		await _settle(t, 2)
		check(not t.seat_node(1).list_mode and t.seat_node(1).compact == (n >= 7) and t._ring.visible and not t._bg.calm, "%d Spieler: normal wieder hergestellt" % n)
		check(t.pile_w == TableView.CARD_W and t.mau_button.size.x == MauButton.SIZE and t._sort_btn.size.y < BigLayout.PILL_H, "%d Spieler: Größen normal" % n)
		check(is_equal_approx(t.seat_node(2).modulate.a, 1.0) and t.seat_node(2).scale == Vector2.ONE, "%d Spieler: Zeilen wieder Plätze" % n)
		t.set_big(true)
		await _settle(t, 2)
		check(t.list_index(2) == 0, "%d Spieler: wieder groß, Liste sofort richtig" % n)
		t.queue_free()
		await process_frame
