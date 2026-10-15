extends SceneTree
# Mau-Mau Flip (Beta 1.6.3, Easter Eggs Teil 2 „Necken“, docs/module/eastereggs2.md Abschnitte 2, 3 und 9): Oberfläche am Tisch,
# headless mit eingespritzter Uhr (TeaseFx.tick, source.fx_clock) und einer Spielsteuerungs-Attrappe (FakeSource).
#   Gesten: Kopf → Menü, Fächer mit sichtbaren Rückseiten → Großansicht, ohne → Menü, Erwischt geht vor, Tipp daneben schließt und
#   wirkt weiter; Menü schließt bei Zugwechsel, Erwischbarkeit, Platzwechsel, 5 s; nie über einem „Erwischt!“-Knopf; „1 Karte“.
#   Menüeinträge nach lokaler Uhr (vor/nach 10 s), Ziel mit Necken aus, Ziel Bot, eigener Wunsch → send_fx.
#   Effekte und Töne je Rolle (Ziel normal, Absender −12 dB, Zuschauer still bzw. Plopp leise), Vibration, Wecker abstellen,
#   Schnarchen ausblenden, Kugeln je Platz ≤ 3, „Mpf!“, Reaktionstöne ≤ 2 gleichzeitig und 600 ms je Name, fx_no-Zeilen/Ausgrauen,
#   Necken aus, Weitergeben, reduziert, großer Modus, Hindernisse für die Sofort-Leiste, Übung über die echte LocalTable.
#   Beta 1.6.5: 4 Reaktionsknöpfe statt Lachgesicht mit Fächer – Reihenfolge Lachen, Klatschen, Daumen hoch, Schreck, ein echter Tipp
#   (Viewport-Eingabe) je Knopf sendet genau diese Reaktion, ≥ 44 px Trefferfläche, in der Sperrzeit grau ohne Senden, nichts verdeckt
#   (Hand, Stapel, Mau, Erwischt, Sortieren/Rückseiten, Hinweisleiste, Fächer) bei 2–8 Spielern, Schrift normal bis sehr groß und
#   im großen Modus (in der Zeile „Du“ vor der Kartenzahl).

const CleanExit := preload("res://tests/clean_exit.gd")

var ok := 0
var fails := 0
var clock := 100000


func check(cond: bool, what: String) -> void:
	if cond:
		ok += 1
	else:
		fails += 1
		print("FAIL: " + what)


func _initialize() -> void:
	call_deferred("run")


class FakeSource:
	extends TableSource
	var m := "client"
	var seat := 0
	var v: Dictionary = {}
	var sent: Array = []

	func mode() -> String:
		return m

	func local_seat() -> int:
		return seat

	func current_view() -> Dictionary:
		return v

	func send_fx(req: Dictionary) -> void:
		sent.append(req)


class FakeSound:
	extends RefCounted
	var log: Array = []
	var fades: Array = []

	func play(n: String, db := 0.0) -> bool:
		log.append([n, db])
		return true

	func fade_out(n: String, _ms := 300) -> bool:
		fades.append(n)
		return true


func now_ms() -> int:
	return clock


var sample: TableSamples
var src: FakeSource
var t: TableView
var tf: TeaseFx
var snd: FakeSound


func show(v: Dictionary) -> void:
	src.v = v
	src.tease.note_view(v, clock)
	t.apply_view(v)


func head_pos(seat: int) -> Vector2:
	var node := t.seat_node(seat)
	return t.get_global_transform().affine_inverse() * node.avatar_global()


func setup(mode := "client", turn := 1, players := 4) -> void:
	if t != null:
		t.queue_free()
		await process_frame
	sample = TableSamples.create(players, 7)
	sample.turn = turn
	src = FakeSource.new()
	src.m = mode
	src.fx_clock = now_ms
	root.add_child(src)
	t = TableView.new()
	root.add_child(t)
	t.sprueche.set_level("aus")
	tf = t.tease
	tf.auto_process = false
	snd = FakeSound.new()
	tf.sound = snd
	tf.vibrate_cb = func(_ms: int) -> void: pass
	show(sample.view_for(0))
	tf.attach(src)
	tf.tick(0.0)


func fx(k: String, from: int, to := -1, r := "") -> void:
	clock += 300                     # die Tisch-Grenze (8, +4 je s) bleibt so offen
	var m := NetProtocol.make_fx(k, from, to, r)
	src.tease.commit(m, clock)
	src.fx_event.emit(m)


func sounds() -> Array:
	return snd.log.map(func(e: Array) -> String: return "%s%s" % [e[0], "" if float(e[1]) == 0.0 else " leise"])


# Beta 1.6.5: echter Tipp über den Viewport (drücken, loslassen) – so zählt auch, ob ein anderes Steuerelement den Tipp abfängt
func tap_screen(pos: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		e.position = pos
		e.global_position = pos
		root.push_input(e, true)


# Beta 1.6.5: Was die Reaktionsknöpfe überdecken (Bildschirmkoordinaten): Hand, Ziehstapel, Ablage, Mau, Sortieren, Rückseiten,
# Hinweisleiste, „Erwischt!“-Felder und Fächer der Mitspieler, Listenzeilen der anderen (großer Modus). Leer = nichts.
func covered_by_reactions() -> Array:
	var out: Array = []
	var rb := tf.reactions
	if not rb.visible:
		return ["unsichtbar"]
	var xf := rb.get_global_transform_with_canvas()
	var bars: Array[Rect2] = []
	for c in rb.centers:
		bars.append(Rect2(xf * c - Vector2.ONE * rb.r, Vector2.ONE * rb.r * 2.0))
	var tg := t.get_global_transform_with_canvas()
	var hr := t.hand_rect(t.size)
	var items := {"Hand": Rect2(tg * (hr.position + Vector2(0, 40)), hr.size - Vector2(0, 40)),
		"Mau": t.mau_button.get_global_rect()}
	for b in [["Sortieren", t.get("_sort_btn")], ["Rückseiten", t.get("_backs_btn")]]:
		if (b[1] as Control).is_visible_in_tree():
			items[b[0]] = (b[1] as Control).get_global_rect()
	for c: CardView in [t.pile_top(), t.discard_top()]:
		if c != null and is_instance_valid(c) and c.is_visible_in_tree():
			var w := c.width * c.global_scale.x
			items["Stapel %s" % c.get_instance_id()] = Rect2(c.get_global_transform_with_canvas().origin - Vector2(w * 0.5, w * 0.78), Vector2(w, w * 1.56))
	var hb := t.hint_bar
	if hb.hint != "":
		var tw := UiFonts.text(700, 100.0).get_string_size(hb.hint, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFonts.size("hinweisleiste")).x + 40.0
		var cx := hb.get_global_rect().get_center().x
		items["Hinweis"] = Rect2(cx - tw * 0.5, hb.global_position.y + hb.hint_y - hb.hint_h() * 0.5, tw, hb.hint_h())
	for s in t.get("_seats"):
		var node := t.seat_node(int(s))
		if node == null or not node.is_visible_in_tree() or node.modulate.a < 0.5:
			continue
		var cr: Rect2 = tf.catch_rect_of(int(s), rb).grow(-18.0)
		items["Erwischt %d" % s] = Rect2(xf * cr.position, cr.size)
		if node.list_mode:
			items["Zeile %d" % s] = Rect2(node.to_global(node.list_rect().position), node.list_rect().size)
		for c: Dictionary in node.fan_cards():
			var w := float(c.width)
			items["Fächer %d" % s] = Rect2(Vector2(c.pos) - Vector2(w * 0.5, w * 0.78), Vector2(w, w * 1.56)).merge(items.get("Fächer %d" % s, Rect2(Vector2(c.pos), Vector2.ZERO)))
	for key in items:
		var r: Rect2 = items[key]
		for b in bars:
			if b.grow(-1.0).intersects(r):
				out.append("%s %s↔%s" % [key, b, r])
				break
	return out


func run() -> void:
	await setup()
	# --- Aufbau
	check(tf.layer != null and tf.layer.get_parent() == t.get("_overlay"), "Effekt-Ebene liegt in den Overlays des Tisches")
	check(tf.reactions.get_index() > t.round_end.get_index() and tf.reactions.get_index() < t.handover.get_index(), "Reaktionsknöpfe über dem Rundenende, unter dem Sichtschutz")
	check(tf.reactions.visible and tf.reactions.centers.size() == 4, "4 Reaktionsknöpfe am eigenen Platz sichtbar (Netz, Necken an)")
	# Gerätetest 1.6.3: nicht über Farbrad, Rückseiten-Großansicht, Kartenhilfe und Rückfragen/Menüs (modal_cb, TableScreen)
	t.wish_picker.open_wheel("hell")
	tf.tick(0.016)
	check(not tf.reactions.visible and tf.covered(), "Farbrad offen: Reaktionsknöpfe weg")
	t.wish_picker.close()
	tf.tick(0.016)
	check(tf.reactions.visible, "Farbrad zu: Reaktionsknöpfe wieder da")
	t.backs_viewer.visible = true
	tf.tick(0.016)
	check(not tf.reactions.visible, "Rückseiten-Großansicht: Reaktionsknöpfe weg")
	t.backs_viewer.visible = false
	t.help_popup.visible = true
	tf.tick(0.016)
	check(not tf.reactions.visible, "Kartenhilfe: Reaktionsknöpfe weg")
	t.help_popup.visible = false
	var modal := [true]
	tf.modal_cb = func() -> bool: return modal[0]
	tf.tick(0.016)
	check(not tf.reactions.visible, "Rückfrage/Menü (modal_cb): Reaktionsknöpfe weg")
	modal[0] = false
	tf.tick(0.016)
	check(tf.reactions.visible, "Rückfrage zu: Reaktionsknöpfe wieder da")
	tf.modal_cb = Callable()

	# --- Kopf-Tipp → Menü mit Papierkugel, Schnarchen/Wecker (nur beim Spieler am Zug, vor 10 s ausgegraut), Karten ansehen
	check(t._tap(head_pos(1)), "Kopf-Tipp wird verbraucht")
	check(tf.menu != null and tf.menu.seat == 1, "Kopf-Tipp öffnet das Necken-Menü")
	var keys: Array = tf.menu.items.map(func(it: Dictionary) -> String: return str(it.key))
	check(keys == ["ball", "snore", "alarm", "backs"], "Menü am Spieler am Zug: Kugel, Schnarchen, Wecker, Karten ansehen (%s)" % str(keys))
	check(bool(tf.menu.items[0].on) and not bool(tf.menu.items[1].on) and not bool(tf.menu.items[2].on), "vor 10 s: Schnarchen/Wecker ausgegraut, Kugel aktiv")
	check(tf.menu.note == "Erst, wenn Lena eine Weile überlegt.", "Hinweis unter den Knöpfen (%s)" % tf.menu.note)
	check(tf.menu.title == "Lena · 7 Karten", "Titel mit Kartenzahl (%s)" % tf.menu.title)
	clock += 10000
	tf.tick(0.3)
	check(bool(tf.menu.items[1].on) and bool(tf.menu.items[2].on) and tf.menu.note == "", "ab 10 s: Schnarchen/Wecker aktiv")
	# nie über einem „Erwischt!“-Knopf (alle Plätze)
	var clean := true
	for s in [1, 2, 3]:
		tf.close_menu(false)
		tf.open_menu(s)
		var mr := Rect2(tf.menu.position, tf.menu.size)
		if mr.intersects(tf.catch_rect_of(s, tf.menu.get_parent())):
			clean = false
		if not Rect2(Vector2.ZERO, t.size).encloses(mr):
			clean = false
	check(clean, "Menü liegt nie über dem „Erwischt!“-Feld des Ziels und ganz im Bild")
	# Wahl → send_fx, Menü zu
	tf.close_menu(false)
	tf.open_menu(1)
	tf._on_menu_chosen("snore")
	check(src.sent == [{"k": "snore", "to": 1}] and tf.menu == null, "Schnarchen gewählt: Wunsch an die Steuerung, Menü zu")
	check(tf.effects().is_empty(), "Absender sieht erst etwas, wenn das fx des Gastgebers kommt")

	# --- Schnarchen: Absender hört leise, Ziel handelt → ausblenden
	fx("snore", 0, 1)
	check(tf.effects_of("snore").size() == 1 and sounds() == ["schnarchen leise"], "Schnarchen beim Absender: Bild + leiser Ton (%s)" % str(sounds()))
	tf.tick(1.0)
	t.play_event({"e": "draw", "seat": 1, "count": 1}, 1.0)
	tf.tick(0.1)
	check((tf.effects_of("snore")[0] as TeaseFx.SnoreFx).ending and snd.fades == ["schnarchen"], "Ziel handelt: Schnarchen blendet aus (Ton 0,3 s)")
	tf.tick(0.4)
	check(tf.effects_of("snore").is_empty(), "Schnarchen danach weg")
	# Zuschauer: nur Bild
	snd.log.clear()
	fx("snore", 3, 1)
	check(tf.effects_of("snore").size() == 1 and snd.log.is_empty(), "Zuschauer: Schnarchen nur als Bild")
	tf.clear()
	# Necken aus während des eigenen (leisen) Schnarchens: der Ton blendet mit aus (Gegenprüfung 1.6.3)
	snd.fades.clear()
	fx("snore", 0, 1)
	tf.set_enabled(false)
	check(snd.fades == ["schnarchen"] and tf.effects().is_empty(), "Necken aus: laufendes Schnarchen blendet aus (%s)" % str(snd.fades))
	tf.set_enabled(true)
	snd.fades.clear()
	# kommt zu spät (Ziel nicht am Zug): nichts
	fx("alarm", 3, 2)
	check(tf.effects().is_empty(), "Wecker für jemanden, der nicht am Zug ist: nichts")

	# --- Wecker beim Ziel (ich): groß, 3 s Ticken ohne Ton, dann Klingeln + Vibration 3 × 250 ms; Katze springt
	sample.turn = 0
	show(sample.view_for(0))
	snd.log.clear()
	tf.vibrations.clear()
	fx("alarm", 1, 0)
	var al: TeaseFx.AlarmFx = tf.effects_of("alarm")[0]
	check(al.big_clock and al.loud, "Wecker beim Ziel: groß")
	var texts: Array = tf.effects_of("text").map(func(e: TeaseFx.TextFx) -> String: return e.text)
	check(texts.has("Lena hat dir einen Wecker gestellt!"), "Text beim Ziel (%s)" % str(texts))
	t.fun.cat.arrive(Vector2(623, 320), 116.0, 1600.0, true)
	for i in 30:
		tf.tick(0.1)
	check(snd.log.is_empty() and al.state == "tick", "3 s Ticken ohne Ton")
	for i in 5:
		tf.tick(0.1)
	check(al.state == "ring" and sounds() == ["wecker"], "danach klingelt er laut (%s)" % str(sounds()))
	check(t.fun.cat.st == "out" or t.fun.cat.st == "hopdown" or t.fun.cat.angry, "Mau-Katze springt beim Klingeln davon")
	for i in 10:
		tf.tick(0.1)
	check(tf.vibrations == [250, 250, 250], "Vibration 3 × 250 ms (%s)" % str(tf.vibrations))
	for i in 20:
		tf.tick(0.1)
	check(tf.effects_of("alarm").is_empty(), "Wecker räumt sich auf")
	# Wecker abstellen: Ziel handelt während des Tickens
	snd.log.clear()
	fx("alarm", 1, 0)
	al = tf.effects_of("alarm")[0]
	tf.tick(1.0)
	var set_line: TeaseFx.TextFx = null
	for e in tf.effects_of("text"):
		if (e as TeaseFx.TextFx).text == "Lena hat dir einen Wecker gestellt!":
			set_line = e
	check(set_line != null and al.banner == set_line, "Wecker merkt sich seine Zeile")
	var set_left := set_line.position.x - set_line.text_width() * 0.5 if set_line != null else 0.0
	var set_y := set_line.position.y if set_line != null else 0.0
	t.play_event({"e": "draw", "seat": 0, "count": 1}, 1.0)
	check(al.state == "fall", "Ziel handelt beim Ticken: Wecker fällt um")
	texts = tf.effects_of("text").map(func(e: TeaseFx.TextFx) -> String: return e.text)
	check(texts.has("Gerade noch geschafft!"), "„Gerade noch geschafft!“")
	# Gerätetest 1.6.3: ersetzt die Zeile „… hat dir einen Wecker gestellt!“ an ihrer Stelle, nicht quer über ihr und dem Wecker
	check(not texts.has("Lena hat dir einen Wecker gestellt!") and texts.size() == 1, "alte Weckerzeile verschwindet (%s)" % str(texts))
	var done_line: TeaseFx.TextFx = tf.effects_of("text")[0]
	var done_left := done_line.position.x - done_line.text_width() * 0.5
	check(absf(done_left - set_left) < 1.0 and absf(done_line.position.y - set_y) < 1.0,
		"„Gerade noch geschafft!“ an der Stelle der Weckerzeile (%.0f,%.0f / %.0f,%.0f)" % [done_left, done_line.position.y, set_left, set_y])
	check(done_left > al.position.x + al.size_s() * 1.2, "„Gerade noch geschafft!“ rechts neben dem Wecker (%.0f > %.0f)" % [done_left, al.position.x + al.size_s() * 1.2])
	for i in 40:
		tf.tick(0.1)
	check(not sounds().has("wecker"), "abgestellter Wecker klingelt nicht")
	# Absender des Weckers: Klingeln leise
	sample.turn = 1
	show(sample.view_for(0))
	snd.log.clear()
	tf.clear()
	fx("alarm", 0, 1)
	for i in 36:
		tf.tick(0.1)
	check(sounds() == ["wecker leise"], "Absender hört das Klingeln leise (%s)" % str(sounds()))
	# Zugwechsel stellt den Wecker ebenfalls ab
	tf.clear()
	fx("alarm", 0, 1)
	sample.turn = 2
	show(sample.view_for(0))
	check((tf.effects_of("alarm")[0] as TeaseFx.AlarmFx).state == "fall", "Zugwechsel: Wecker fällt um")
	tf.clear()

	# --- Papierkugel: Rollen, Treffer, liegt 3 s, höchstens 3 je Platz, Bot „Mpf!“
	snd.log.clear()
	tf.vibrations.clear()
	fx("ball", 0, 2)
	check(sounds() == ["papier_wurf"], "Absender: Wurf-Ton")
	var b: TeaseFx.BallFx = tf.effects_of("ball")[0]
	tf.tick(0.35)
	check(b.state == "fly" and b.ball_pos().distance_to(b.from.lerp(b.to, 0.5)) > 60.0, "Kugel fliegt im Bogen (nicht auf der Geraden)")
	tf.tick(0.4)
	check(b.state == "bounce" and sounds() == ["papier_wurf"], "Treffer: Absender hört keinen Plopp")
	texts = tf.effects_of("text").map(func(e: TeaseFx.TextFx) -> String: return e.text)
	check(texts.has("Mpf!"), "Bot getroffen: „Mpf!“")
	tf.tick(0.4)
	check(b.state == "lie", "Kugel bleibt liegen")
	tf.tick(3.1)
	check(b.state == "fade", "nach 3 s blendet sie aus")
	snd.log.clear()
	fx("ball", 1, 0)
	tf.tick(0.75)
	check(sounds() == ["papier_plopp"] and tf.vibrations == [40], "Ziel: Plopp laut + Vibration 40 ms (%s)" % str(sounds()))
	texts = tf.effects_of("text").map(func(e: TeaseFx.TextFx) -> String: return e.text)
	check(texts.has("Papierkugel von Lena!"), "Ziel: „Papierkugel von Lena!“")
	snd.log.clear()
	fx("ball", 1, 3)
	tf.tick(0.75)
	check(sounds() == ["papier_plopp leise"], "Zuschauer: Plopp leise (%s)" % str(sounds()))
	tf.clear()
	for i in 4:
		fx("ball", 1, 3)
		tf.tick(0.2)
	check(tf.effects_of("ball").size() == 3, "höchstens 3 Kugeln je Platz")
	tf.clear()

	# --- Reaktionen: Bild am Absender, Töne ≤ 2 gleichzeitig, 600 ms je Name
	snd.log.clear()
	fx("react", 1, -1, "lachen")
	fx("react", 2, -1, "klatschen")
	fx("react", 3, -1, "daumen")
	check(tf.effects_of("react").size() == 3 and sounds() == ["lachen", "klatschen"], "3 Reaktionen: 3 Bilder, höchstens 2 Töne (%s)" % str(sounds()))
	var xs: Array = tf.effects_of("react").map(func(e: Node2D) -> float: return e.position.x)
	tf.tick(2.0)
	snd.log.clear()
	fx("react", 0, -1, "schreck")
	tf.tick(0.2)
	fx("react", 0, -1, "schreck")
	check(sounds() == ["schreck"], "derselbe Name innerhalb von 600 ms: einmal")
	var mine: Array = tf.effects_of("react").filter(func(e: TeaseFx.ReactFx) -> bool: return e.seat == 0 and e.t < 0.5)
	check(mine.size() == 2 and absf((mine[0] as Node2D).position.x - (mine[1] as Node2D).position.x) > 20.0, "schnell hintereinander: nebeneinander")
	tf.tick(0.7)
	fx("react", 0, -1, "schreck")
	check(sounds() == ["schreck", "schreck"], "nach 600 ms wieder mit Ton")
	tf.tick(2.0)
	check(tf.effects_of("react").is_empty(), "Reaktionen räumen sich auf")

	# --- fx_no beim Absender: leise Zeile bzw. Ausgrauen, kein Fehlerton
	tf._last_target = 1
	src.fx_refused.emit("late")
	var hb: Toast = t.hint_bar
	check(not hb._toasts.is_empty() and str(hb._toasts[-1].text) == "Zu spät – Lena hat schon gespielt.", "fx_no late → Zeile")
	src.fx_refused.emit("busy")
	check(str(hb._toasts[-1].text) == "Lena wird gerade schon geweckt.", "fx_no busy → Zeile")
	var n_toasts := hb._toasts.size()
	tf.open_menu(1)
	src.fx_refused.emit("rate")
	check(hb._toasts.size() == n_toasts and not bool(tf.menu.items[0].on) and tf.reactions.gray and tf.reactions.dim and tf.reactions._shake > 0.0, "fx_no rate → nur ausgegraut, Reaktionsknöpfe blass und wackeln")
	tf.tick(1.3)
	check(bool(tf.menu.items[0].on), "nach kurzer Zeit wieder aktiv")

	# --- Menü schließt: Zugwechsel, erwischbarer Platz, Platzwechsel, 5 s, Tipp daneben (der weiter wirkt)
	sample.turn = 3
	show(sample.view_for(0))
	check(tf.menu == null, "Zugwechsel schließt das Menü")
	tf.open_menu(1)
	sample.catch_targets = [1]
	show(sample.view_for(0))
	check(tf.menu == null, "erwischbarer Platz schließt das Menü (Erwischen geht vor)")
	var acts: Array = []
	t.action.connect(func(a: Dictionary) -> void: acts.append(a))
	var n1 := t.seat_node(1)
	t._tap(t.get_global_transform().affine_inverse() * n1.to_global(n1._catch_rect().get_center()))
	check(acts.size() == 1 and str(acts[0].a) == "catch", "„Erwischt!“ geht vor allem anderen")
	sample.catch_targets = []
	show(sample.view_for(0))
	tf.open_menu(2)
	t.play_event({"e": "seats", "map": [0, 1, 2, 3]}, 1.0)
	check(tf.menu == null, "Platzwechsel schließt das Menü")
	fx("ball", 0, 2)
	t.play_event({"e": "seats", "map": [0, 1, 2, 3]}, 1.0)
	check(tf.effects().is_empty(), "Platzwechsel räumt die Effekte ab")
	tf.open_menu(2)
	tf.tick(5.1)
	check(tf.menu == null, "5 s ohne Tipp: Menü zu")
	tf.open_menu(2)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(5, 700)
	tf.menu._input(press)
	check(tf.menu == null, "Tipp daneben schließt das Menü (ohne ihn zu verbrauchen)")
	t._tap(head_pos(2))
	check(tf.menu == null, "derselbe Kopf direkt danach öffnet nicht gleich wieder")
	tf.tick(0.45)
	t._tap(head_pos(2))
	check(tf.menu != null and tf.menu.seat == 2, "später öffnet er wieder")
	keys = tf.menu.items.map(func(it: Dictionary) -> String: return str(it.key))
	check(keys == ["ball", "backs"], "Bot nicht am Zug: nur Kugel und Karten ansehen (%s)" % str(keys))
	tf._on_menu_chosen("backs")
	check(t.backs_viewer.visible and tf.menu == null, "„Karten ansehen“ öffnet die Großansicht")
	t.backs_viewer.visible = false
	# 1 Karte im Titel
	sample.hands[3] = [sample.hands[3][0]]
	show(sample.view_for(0))
	tf.open_menu(3)
	check(tf.menu.title == "Mia · 1 Karte", "Titel „1 Karte“ (%s)" % tf.menu.title)
	tf.close_menu(false)
	# Ziel mit Necken aus
	src._fx_offs = [1]
	src.fx_offs_changed.emit([1])
	tf.open_menu(1)
	keys = tf.menu.items.map(func(it: Dictionary) -> String: return str(it.key))
	check(keys == ["backs"] and tf.menu.note == "Lena möchte gerade nicht geneckt werden.", "Ziel mit Necken aus: Hinweis, nur Karten ansehen")
	tf.close_menu(false)
	src._fx_offs = []
	# Rückseiten verdeckt: Fächer-Tipp öffnet das Menü
	sample.backs_visible = false
	show(sample.view_for(0))
	var node1 := t.seat_node(1)
	var fan_p := t.get_global_transform().affine_inverse() * node1.fan_global_center()
	tf.tick(0.45)
	t._tap(fan_p)
	check(tf.menu != null and tf.menu.seat == 1 and not t.backs_viewer.visible, "Rückseiten verdeckt: Fächer öffnet das Menü")
	tf.close_menu(false)
	sample.backs_visible = true
	show(sample.view_for(0))
	t._tap(t.get_global_transform().affine_inverse() * node1.fan_global_center())
	check(t.backs_viewer.visible and tf.menu == null, "Rückseiten sichtbar: Fächer öffnet wie bisher die Großansicht")
	t.backs_viewer.visible = false

	# --- Beta 1.6.5: 4 Reaktionsknöpfe, ein echter Tipp je Knopf sendet genau diese Reaktion; Hindernisse für die Sofort-Leiste
	clock += 10000                   # eigener Reaktions-Eimer wieder voll
	tf.tick(0.2)
	src.sent.clear()
	check(TeaseMenu.REACT_ORDER == ["lachen", "klatschen", "daumen", "schreck"], "Reihenfolge Lachen, Klatschen, Daumen hoch, Schreck")
	# Beta 1.6.5: Reaktionen als feste Bilder (Fluent Emoji, SVG, wie im Browser), scharf genug für groß: ≥ 384 px, mit Mipmaps
	var tex_ok := TeaseFx.REACT_TEX.keys().size() == 4
	for r_name in TeaseMenu.REACT_ORDER:
		var tex: Texture2D = TeaseFx.REACT_TEX.get(r_name)
		tex_ok = tex_ok and tex != null and tex.get_width() >= 384 and tex.get_height() == tex.get_width() \
			and tex.get_image().has_mipmaps() and tex.resource_path == "res://assets/ui/reaktionen/%s.svg" % r_name
	check(tex_ok, "4 Reaktionsbilder aus assets/ui/reaktionen (SVG, ≥ 384 px, Mipmaps)")
	var img_d := (TeaseFx.REACT_TEX["daumen"] as Texture2D).get_image()
	img_d.decompress()
	var opaque := 0
	var stp := img_d.get_width() / 32
	for y in range(0, img_d.get_height(), stp):
		for x in range(0, img_d.get_width(), stp):
			if img_d.get_pixel(x, y).a > 0.5:
				opaque += 1
	check(opaque > 300, "Daumen-Bild ist gefüllt (%d von 1024 Stichproben deckend)" % opaque)
	check(not TeaseFx.REACT_TEX.has("ball") and not TeaseFx.REACT_TEX.has("snore"), "andere Bilder bleiben gezeichnet")
	var rb := tf.reactions
	check(rb.r * 2.0 >= 44.0 and rb.hit_r() * 2.0 >= 48.0, "Knöpfe groß genug (Durchmesser %.0f, Treffer %.0f)" % [rb.r * 2.0, rb.hit_r() * 2.0])
	var xs_b: Array = rb.centers.map(func(p: Vector2) -> float: return p.x)
	check(xs_b[0] < xs_b[1] and xs_b[1] < xs_b[2] and xs_b[2] < xs_b[3], "Knöpfe von links nach rechts in dieser Reihenfolge (%s)" % str(xs_b))
	var labels: Array = []
	for i in 4:
		labels.append(rb._get_tooltip(rb.centers[i]))
	check(labels == ["Lachen", "Klatschen", "Daumen hoch", "Schreck"], "Hilfetexte je Knopf (%s)" % str(labels))
	for i in 4:
		clock += 10000
		tf.tick(0.2)
		src.sent.clear()
		tap_screen(rb.get_global_transform_with_canvas() * rb.centers[i])
		check(src.sent == [{"k": "react", "r": TeaseMenu.REACT_ORDER[i]}], "Tipp auf Knopf %d → %s (%s)" % [i + 1, TeaseMenu.REACT_ORDER[i], str(src.sent)])
	# neben den Knöpfen (zwischen zweien, darüber) wird nichts gesendet; das eigene Namensschild öffnet nichts mehr
	clock += 10000
	tf.tick(0.2)
	src.sent.clear()
	tap_screen(rb.get_global_transform_with_canvas() * ((rb.centers[0] + rb.centers[1]) * 0.5 + Vector2(0, rb.r + 14.0)))
	check(src.sent.is_empty(), "Tipp neben die Knöpfe sendet nichts")
	var me_p := t.get_global_transform().affine_inverse() * t.me_badge.avatar_global()
	check(not t._tap(me_p) and src.sent.is_empty(), "Tipp aufs eigene Namensschild: kein Fächer, nichts gesendet")
	# Sperrzeit: eigener Eimer leer → alle grau, ein Tipp sendet nichts
	for i in TeaseRules.REACT_BUCKET + 1:
		src.tease.commit(NetProtocol.make_fx("react", 0, -1, "lachen"), clock)
	tf.tick(0.2)
	check(rb.gray, "Sperrzeit: alle Knöpfe ausgegraut")
	src.sent.clear()
	tap_screen(rb.get_global_transform_with_canvas() * rb.centers[2])
	check(src.sent.is_empty(), "Sperrzeit: Tipp sendet nichts")
	clock += 30000
	tf.tick(0.2)
	check(not rb.gray, "nach der Sperrzeit wieder aktiv")
	var obs := tf.obstacles()
	check(obs.size() >= 1 and obs[0].size.x > 200.0, "Hindernisse: Reaktionsknöpfe (%s)" % str(obs))
	tf.open_menu(1)
	check(tf.obstacles().size() == 2, "Hindernisse: dazu das offene Menü")
	tf.close_menu(false)
	var cover := covered_by_reactions()
	check(cover.is_empty(), "Knöpfe verdecken nichts (%s)" % str(cover))

	# --- Necken aus: nichts sehen, hören oder schicken; Kopf-Tipp wie früher
	tf.set_enabled(false)
	check(src.fx_off() and not tf.reactions.visible, "Necken aus: Steuerung erfährt es, Reaktionsknöpfe weg")
	snd.log.clear()
	fx("react", 1, -1, "lachen")
	fx("ball", 1, 0)
	check(tf.effects().is_empty() and snd.log.is_empty(), "Necken aus: keine Effekte, keine Töne")
	t._tap(head_pos(1))
	check(tf.menu == null and t.backs_viewer.visible, "Necken aus: Kopf-Tipp öffnet wie früher die Rückseiten")
	t.backs_viewer.visible = false
	tf.set_enabled(true)
	check(not src.fx_off() and tf.reactions.visible, "Necken wieder an")

	# --- reduziert: Kugel ohne Flug, Reaktion steigt nicht
	t.reduced = true
	fx("ball", 1, 3)
	tf.tick(0.02)
	tf.tick(0.02)
	check((tf.effects_of("ball")[0] as TeaseFx.BallFx).state == "lie", "reduziert: Kugel erscheint gleich am Ziel")
	t.reduced = false
	tf.clear()

	# --- großer Modus: Avatar der Zeile öffnet das Menü, Reaktionsknopf links in der Zeile „Du“
	t.set_big(true)
	show(sample.view_for(0))
	tf.tick(0.1)
	check(tf.big and tf.k() > 1.2, "großer Modus: Maße × 1,3")
	var row := t.seat_node(1)
	tf.tick(0.45)
	t._tap(t.get_global_transform().affine_inverse() * row.avatar_global())
	check(tf.menu != null and tf.menu.seat == 1, "großer Modus: Avatar der Zeile öffnet das Menü")
	var mr2 := Rect2(tf.menu.position, tf.menu.size)
	check(Rect2(Vector2.ZERO, t.size).encloses(mr2), "großer Modus: Menü ganz im Bild")
	tf.close_menu(false)
	# Rest der Zeile (rechts vom Avatar) bei verdeckten Rückseiten: wie bisher kein Menü (Gegenprüfung 1.6.3)
	sample.backs_visible = false
	show(sample.view_for(0))
	tf.tick(0.45)
	var lr := row.list_rect()
	var row_p := t.get_global_transform().affine_inverse() * row.to_global(Vector2(lr.end.x - 30.0, lr.get_center().y))
	t._tap(row_p)
	check(tf.menu == null and not t.backs_viewer.visible, "großer Modus: Tipp auf die Zeile neben dem Avatar öffnet kein Menü")
	sample.backs_visible = true
	show(sample.view_for(0))
	tf.tick(0.2)
	await create_timer(1.0).timeout             # Liste fertig gerollt
	tf.tick(0.2)
	var badge := t.me_badge
	var row_g := Rect2(badge.to_global(badge.list_rect().position), badge.list_rect().size)
	var count_g := badge.to_global(badge.count_rect().position).x
	var rbg := Rect2(tf.reactions.get_global_transform_with_canvas() * tf.reactions.bounds().position, tf.reactions.bounds().size)
	check(tf.reactions.visible and row_g.grow(2.0).encloses(rbg.grow(-4.0)), "großer Modus: Knöpfe in der Zeile „Du“ (%s in %s)" % [rbg, row_g])
	check(rbg.end.x - 4.0 <= count_g, "großer Modus: Knöpfe vor der großen Kartenzahl")
	check(tf.reactions.r >= 22.0 and badge.row_reserve > tf.reactions.r * 8.0, "großer Modus: Knöpfe ≥ 44 px, Zeile kürzt den Namen (r %.0f, Platz %.0f)" % [tf.reactions.r, badge.row_reserve])
	var name_room: float = rbg.position.x - badge.to_global(Vector2(-badge.row_size.x * 0.5 + 12.0 + badge.avatar_radius() * 2.0 + 14.0, 0)).x
	var du_w := UiFonts.text(800, 100.0).get_string_size("Du", HORIZONTAL_ALIGNMENT_LEFT, -1, mini(UiFonts.px(36), int(badge.row_size.y * 0.46))).x
	check(name_room >= du_w, "großer Modus: „Du“ passt noch vor die Knöpfe (%.0f ≥ %.0f)" % [name_room, du_w])
	src.sent.clear()
	clock += 10000
	tf.tick(0.2)
	tap_screen(tf.reactions.get_global_transform_with_canvas() * tf.reactions.centers[1])
	check(src.sent == [{"k": "react", "r": "klatschen"}], "großer Modus: Tipp auf den zweiten Knopf → Klatschen")
	var cover_b := covered_by_reactions()
	check(cover_b.is_empty(), "großer Modus: Knöpfe verdecken nichts (%s)" % str(cover_b))
	t.set_big(false)
	tf.tick(0.2)
	check(is_zero_approx(badge.row_reserve), "normaler Modus: Zeile ohne Reservierung")

	# --- Lage bei 2–8 Spielern, Schrift normal bis sehr groß, normal und groß: nichts verdeckt, ganz im Bild, Knöpfe ≥ 44 px
	for n in [2, 3, 4, 5, 6, 8]:
		for level in ["normal", "gross", "sehr_gross"]:
			for big_on in [false, true]:
				await setup("client", 1, n)
				UiFonts.set_level(level, root)
				t.set_big(big_on)
				t._layout()
				show(sample.view_for(0))
				await create_timer(1.0 if big_on else 0.1).timeout
				tf.tick(0.2)
				var what := "%d Spieler, %s%s" % [n, level, ", groß" if big_on else ""]
				var cv := covered_by_reactions()
				var bb := Rect2(tf.reactions.get_global_transform_with_canvas() * tf.reactions.bounds().position, tf.reactions.bounds().size)
				check(tf.reactions.visible and cv.is_empty(), "%s: Knöpfe verdecken nichts (%s)" % [what, str(cv)])
				check(Rect2(Vector2.ZERO, t.size).grow(2.0).encloses(bb) and tf.reactions.r >= 22.0, "%s: ganz im Bild, ≥ 44 px (%s)" % [what, bb])
	UiFonts.set_level("normal", root)

	# --- Weitergeben: nichts (kein Knopf, Kopf wie früher)
	await setup("pass")
	check(not tf.reactions.visible and not tf.can_open(1), "Weitergeben: kein Necken, keine Reaktionsknöpfe")
	t._tap(head_pos(1))
	check(tf.menu == null and t.backs_viewer.visible, "Weitergeben: Kopf öffnet die Rückseiten")
	t.queue_free()
	t = null

	# --- Übung über die echte LocalTable am TableScreen: nur Papierkugel auf Computergegner
	var nav := ScreenNav.new()
	root.add_child(nav)
	await process_frame
	var players := [{"name": "Karlo", "kind": "bot"}, {"name": "Du", "kind": "human"}, {"name": "Mimi", "kind": "bot"}]
	var local := GameStarter.local("solo", RuleConfig.preset("familie"), players, 1)
	var ts := TableScreen.create(local, func() -> void: local.start())
	nav.push(ts, false)
	var deadline := Time.get_ticks_msec() + 15000
	await create_timer(0.5).timeout
	while ts.table.director.is_busy() and Time.get_ticks_msec() < deadline:
		await process_frame
	var tz := ts.table.tease
	tz.auto_process = false
	tz.sound = FakeSound.new()
	check(not tz.reactions.visible, "Übung: keine Reaktionsknöpfe")
	var bot_seat := 0 if ts.table.my_seat != 0 else 2
	check(tz.open_menu(bot_seat), "Übung: Menü am Computergegner")
	keys = tz.menu.items.map(func(it: Dictionary) -> String: return str(it.key))
	check(keys[0] == "ball" and not keys.has("snore") and not keys.has("alarm"), "Übung: nur die Papierkugel (%s)" % str(keys))
	tz._on_menu_chosen("ball")
	check(tz.effects_of("ball").size() == 1, "Übung: Kugel kommt sofort als Ereignis an")
	check(ts.bar_obstacles().size() >= 1, "TableScreen.bar_obstacles läuft mit")
	tz.open_menu(bot_seat)
	var with_menu := ts.bar_obstacles().size()
	tz.close_menu(false)
	check(with_menu == ts.bar_obstacles().size() + 1, "Sofort-Leiste meidet das offene Menü")
	# Gerätetest 1.6.3: TableScreen meldet Rückfragen und Menüs über modal_cb (Reaktionsknopf verschwindet darunter)
	check(tz.modal_cb.is_valid() and not tz.covered(), "TableScreen: modal_cb verdrahtet, nichts offen")
	ts.open_menu()
	await process_frame
	check(ts.is_menu_open() and tz.covered(), "☰-Menü offen: Reaktionsknopf verdeckt")
	ts.on_back()
	await process_frame
	ts.on_back()                               # „Partie verlassen?“
	await process_frame
	check(ts.get("_confirm") != null and tz.covered(), "„Partie verlassen?“: Reaktionsknopf verdeckt")
	ts.on_back()
	await process_frame
	check(not tz.covered() and not ts.leaving, "Rückfrage zu: wieder frei")

	print("RESULT: %d ok%s" % [ok, ", FEHLER" if fails > 0 else ""])
	await CleanExit.finish(self, 1 if fails > 0 else 0)
