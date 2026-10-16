extends SceneTree
# Mau-Mau Flip (Beta 1.6.3, Easter Eggs Teil 2 „Necken“, docs/module/eastereggs2.md Abschnitte 2, 3 und 9): Oberfläche am Tisch,
# headless mit eingespritzter Uhr (TeaseFx.tick, source.fx_clock) und einer Spielsteuerungs-Attrappe (FakeSource).
#   Gesten: Kopf → Menü, Fächer mit sichtbaren Rückseiten → Großansicht, ohne → Menü, Erwischt geht vor, Tipp daneben schließt und
#   wirkt weiter; Menü schließt bei Platzwechsel, Rundenende, 15 s (Beta 1.6.7; vorher 5 s), aber nicht mehr bei Zugwechsel (frischt
#   auf, springt nicht) oder Erwischbarkeit (Buzzer bleibt drückbar, auch unter der Blase); nie über einem „Erwischt!“-Knopf; „1 Karte“.
#   Menüeinträge nach lokaler Uhr (vor/nach 10 s), Ziel mit Necken aus, Ziel Bot, eigener Wunsch → send_fx.
#   Effekte und Töne je Rolle (Ziel normal, Absender −12 dB, Zuschauer still bzw. Plopp leise), Vibration, Wecker abstellen,
#   Schnarchen ausblenden, Kugeln je Platz ≤ 3, „Mpf!“, Reaktionstöne ≤ 2 gleichzeitig und 600 ms je Name, fx_no-Zeilen/Ausgrauen,
#   Necken aus, Weitergeben, reduziert, großer Modus, Hindernisse für die Sofort-Leiste, Übung über die echte LocalTable.
#   Beta 1.6.5: 4 Reaktionsknöpfe statt Lachgesicht mit Fächer – Reihenfolge Lachen, Klatschen, Daumen hoch, Schreck, ein echter Tipp
#   (Viewport-Eingabe) je Knopf sendet genau diese Reaktion, ≥ 44 px Trefferfläche, in der Sperrzeit grau ohne Senden, nichts verdeckt
#   (Hand, Stapel, Mau, Erwischt, Sortieren/Rückseiten, Hinweisleiste, Fächer) bei 2–8 Spielern, Schrift normal bis sehr groß und
#   im großen Modus (in der Zeile „Du“ vor der Kartenzahl).
#   Beta 1.6.6: Furzkissen (cushion_checks; Menüzeile, Vorprüfung, Bestätigung, Ablehnung, Pups je Rolle, Lage, reduziert, Necken
#   aus, Platzwechsel, großer Modus, Schrift „Sehr groß“) und in der Übung auf den Computergegner.
#   Gerätetest 1.6.6 (F1): Menü- und Reaktionsknöpfe haben Vorrang vor Mau-Katze und Schmetterling (surprise_checks).

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


# Beta 1.6.7: Probleme der sichtbaren „Erwischt!“-Buzzer (Bildschirmkoordinaten). Leer = nichts.
func buzzer_issues() -> Array:
	var out: Array = []
	var rects := {}
	var stacks: Array[Rect2] = []
	for c: CardView in [t.pile_top(), t.discard_top()]:
		if c != null and is_instance_valid(c) and c.is_visible_in_tree():
			var w := c.width * c.global_scale.x
			stacks.append(Rect2(c.get_global_transform_with_canvas().origin - Vector2(w * 0.5, w * 0.78), Vector2(w, w * 1.56)))
	for s in t.get("_seats"):
		var node := t.seat_node(int(s))
		if node == null or not node.catchable:
			continue
		var xf := node.get_global_transform_with_canvas()
		var r := node._catch_rect()
		var g := Rect2(xf * r.position, r.size * xf.get_scale().abs())
		rects[int(s)] = g
		if g.size.x < 145.0 or g.size.y < 84.0:
			out.append("klein %d %s" % [s, g])
		if not Rect2(Vector2.ZERO, t.size).grow(2.0).encloses(g):
			out.append("raus %d %s" % [s, g])
		if g.intersects(t.mau_button.get_global_rect()):
			out.append("Mau %d %s" % [s, g])
		for st in stacks:
			if g.grow(-2.0).intersects(st):
				out.append("Stapel %d %s↔%s" % [s, g, st])
	var ks := rects.keys()
	for i in ks.size():
		for j in range(i + 1, ks.size()):
			if (rects[ks[i]] as Rect2).intersects(rects[ks[j]]):
				out.append("überlappt %d/%d" % [ks[i], ks[j]])
	return out


func run() -> void:
	await setup()
	# --- Aufbau
	check(tf.layer != null and tf.layer.get_parent() == t.get("_overlay"), "Effekt-Ebene liegt in den Overlays des Tisches")
	check(tf.reactions.get_index() > t.round_end.get_index() and tf.reactions.get_index() < t.handover.get_index(), "Reaktionsknöpfe über dem Rundenende, unter dem Sichtschutz")
	check(tf.reactions.visible and tf.reactions.centers.size() == 5, "5 Reaktionsknöpfe am eigenen Platz sichtbar (Netz, Necken an; 1.6.11: mit Bäää)")
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
	check(keys == ["ball", "snore", "alarm", "kissen_geheim", "kissen_name", "backs"], "Menü am Spieler am Zug: Kugel, Schnarchen, Wecker, 2 Kissen, Karten ansehen (%s)" % str(keys))
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

	# --- Beta 1.6.7 (Nutzerwunsch 16.10.2026): Zugwechsel und erwischbare Plätze schließen das Menü nicht mehr. Beim Zugwechsel frischt
	#     es auf (Schnarchen/Wecker grau bzw. aktiv) und bleibt an seiner Stelle; der Buzzer bleibt sichtbar und drückbar.
	sample.turn = 1
	show(sample.view_for(0))
	clock += 10000
	tf.tick(0.45)
	tf.open_menu(1)
	var m0 := tf.menu
	check(bool(m0.items[1].on) and bool(m0.items[2].on), "Lena am Zug, ab 10 s: Schnarchen/Wecker aktiv")
	var ball0: Vector2 = m0.get_global_transform_with_canvas() * m0.button_center(0)
	sample.turn = 3
	show(sample.view_for(0))
	tf.tick(0.2)
	check(tf.menu == m0, "Zugwechsel: Menü bleibt offen")
	keys = tf.menu.items.map(func(it: Dictionary) -> String: return str(it.key))
	check(keys == ["ball", "snore", "alarm", "kissen_geheim", "kissen_name", "backs"] and bool(tf.menu.items[0].on) and not bool(tf.menu.items[1].on) and not bool(tf.menu.items[2].on),
		"Zugwechsel: Schnarchen/Wecker grau, Kugel aktiv (%s)" % str(keys))
	check(tf.menu.note == "Erst, wenn Lena dran ist.", "Zugwechsel: Hinweis „Erst, wenn Lena dran ist.“ (%s)" % tf.menu.note)
	var ball1: Vector2 = m0.get_global_transform_with_canvas() * m0.button_center(0)
	check(ball1.distance_to(ball0) < 2.0, "Zugwechsel: Menü springt nicht (Papierkugel bleibt an ihrer Stelle, %s → %s)" % [ball0, ball1])
	sample.turn = 1
	show(sample.view_for(0))
	tf.tick(0.2)
	check(tf.menu == m0 and not bool(tf.menu.items[1].on) and tf.menu.note == "Erst, wenn Lena eine Weile überlegt.", "Lena wieder am Zug: erst nach 10 s (%s)" % tf.menu.note)
	clock += 10000
	tf.tick(0.2)
	check(bool(tf.menu.items[1].on) and bool(tf.menu.items[2].on) and tf.menu.note == "", "… dann aktiv")
	# erwischbarer Platz: Menü bleibt offen, liegt nicht über dem Buzzer, ein echter Tipp darauf erwischt (Menü zu wie bei jedem Tipp daneben)
	sample.catch_targets = [3]
	show(sample.view_for(0))
	tf.tick(0.02)
	check(tf.menu == m0, "erwischbarer Platz: Menü bleibt offen")
	var n3 := t.seat_node(3)
	check(n3.catchable and not Rect2(m0.position, m0.size).intersects(tf.catch_rect_of(3, m0.get_parent(), 0.0)) and m0.buzzers.is_empty(),
		"Menü liegt nicht über dem neuen Buzzer")
	var buzz3: Vector2 = n3.get_global_transform_with_canvas() * n3._catch_rect().get_center()
	var acts: Array = []
	t.action.connect(func(a: Dictionary) -> void: acts.append(a))
	tap_screen(buzz3)
	check(acts.size() == 1 and str(acts[0].a) == "catch" and int(acts[0].target) == 3 and tf.menu == null, "echter Tipp auf den Buzzer: erwischt, Menü zu (%s)" % str(acts))
	# Menüknöpfe bleiben neben einem Buzzer nutzbar
	tf.tick(0.45)
	tf.open_menu(1)
	src.sent.clear()
	tap_screen(tf.menu.get_global_transform_with_canvas() * tf.menu.button_center(0))
	check(src.sent == [{"k": "ball", "to": 1}] and tf.menu == null, "Buzzer sichtbar: Papierkugel im Menü geht weiter (%s)" % str(src.sent))
	# Buzzer unter der Blase (erzwungen, z. B. nach Größenwechsel): wird über der Blase gezeichnet, der Tipp darauf gehört dem Tisch
	tf.tick(0.45)
	tf.open_menu(1)
	var cr3 := tf.catch_rect_of(3, tf.menu.get_parent(), 0.0)
	tf.menu.position = cr3.get_center() - tf.menu.size * 0.5
	tf.tick(0.02)
	check(tf.menu.buzzers.size() == 1 and not tf.menu._has_point(tf.menu.get_global_transform_with_canvas().affine_inverse() * buzz3),
		"Buzzer unter der Blase: Menü zeichnet ihn und lässt den Tipp durch")
	acts.clear()
	tap_screen(buzz3)
	check(acts.size() == 1 and str(acts[0].a) == "catch" and int(acts[0].target) == 3 and tf.menu == null, "Tipp auf den Buzzer über der Blase erwischt (%s)" % str(acts))
	sample.catch_targets = [1]
	show(sample.view_for(0))
	acts.clear()
	var n1 := t.seat_node(1)
	t._tap(t.get_global_transform().affine_inverse() * n1.to_global(n1._catch_rect().get_center()))
	check(acts.size() == 1 and str(acts[0].a) == "catch", "„Erwischt!“ geht vor allem anderen")
	# Bildprüfung 1.6.7: überlappende Tippbereiche zweier Buzzer (großer Modus, Nachbarzeilen) – der nächstgelegene gewinnt
	sample.catch_targets = [1, 3]
	show(sample.view_for(0))
	var nb3 := t.seat_node(3)
	var c1 := n1._catch_rect()
	var c3 := nb3._catch_rect()
	var sc := n1.get_global_transform().get_scale().y
	var old3 := nb3.global_position
	nb3.global_position += n1.to_global(c1.position + Vector2(0.0, c1.size.y + 4.0)) - nb3.to_global(c3.position)
	acts.clear()
	var edge := nb3.to_global(c3.position + Vector2(c3.size.x * 0.5, 3.0))
	check(n1.hit_catch(edge) and nb3.hit_catch(edge), "Testaufbau: Tippbereiche überlappen (Maßstab %.2f)" % sc)
	t._tap(t.get_global_transform().affine_inverse() * edge)
	check(acts.size() == 1 and int(acts[0].target) == 3, "oberer Rand des unteren Buzzers erwischt den unteren (%s)" % str(acts))
	acts.clear()
	t._tap(t.get_global_transform().affine_inverse() * n1.to_global(c1.position + Vector2(c1.size.x * 0.5, c1.size.y - 3.0)))
	check(acts.size() == 1 and int(acts[0].target) == 1, "unterer Rand des oberen Buzzers erwischt den oberen (%s)" % str(acts))
	nb3.global_position = old3
	sample.catch_targets = []
	show(sample.view_for(0))
	# übrige Schließgründe bleiben: Platzwechsel, Rundenende, 15 s ohne Tipp, Tipp daneben
	tf.tick(0.45)
	tf.open_menu(2)
	t.play_event({"e": "seats", "map": [0, 1, 2, 3]}, 1.0)
	check(tf.menu == null, "Platzwechsel schließt das Menü")
	fx("ball", 0, 2)
	t.play_event({"e": "seats", "map": [0, 1, 2, 3]}, 1.0)
	check(tf.effects().is_empty(), "Platzwechsel räumt die Effekte ab")
	tf.open_menu(2)
	sample.phase = "round_over"
	show(sample.view_for(0))
	check(tf.menu == null, "Rundenende schließt das Menü")
	sample.phase = "turn"
	show(sample.view_for(0))
	tf.open_menu(2)
	tf.tick(5.1)
	check(tf.menu != null, "nach 5 s noch offen (Beta 1.6.7: 15 s)")
	tf.tick(9.8)
	check(tf.menu != null, "nach 14,9 s noch offen")
	tf.tick(0.2)
	check(tf.menu == null and is_equal_approx(TeaseFx.MENU_IDLE_S, 15.0), "15 s ohne Tipp: Menü zu")
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
	check(keys == ["ball", "kissen_geheim", "kissen_name", "backs"], "Bot nicht am Zug: Kugel, 2 Kissen, Karten ansehen (%s)" % str(keys))
	check(tf.menu.rows().size() == 1, "Bot: alle Knöpfe in einer Reihe (%s)" % str(tf.menu.rows()))
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

	# --- Beta 1.6.5: Reaktionsknöpfe (1.6.11: fünf), ein echter Tipp je Knopf sendet genau diese Reaktion; Hindernisse für die Sofort-Leiste
	clock += 10000                   # eigener Reaktions-Eimer wieder voll
	tf.tick(0.2)
	src.sent.clear()
	check(TeaseMenu.REACT_ORDER == ["lachen", "klatschen", "daumen", "schreck", "baeh"], "Reihenfolge Lachen, Klatschen, Daumen hoch, Schreck, Bäää")
	# Beta 1.6.5: Reaktionen als feste Bilder (Fluent Emoji, SVG, wie im Browser), scharf genug für groß: ≥ 384 px, mit Mipmaps
	var tex_ok := TeaseFx.REACT_TEX.keys().size() == 5
	for r_name in TeaseMenu.REACT_ORDER:
		var tex: Texture2D = TeaseFx.REACT_TEX.get(r_name)
		tex_ok = tex_ok and tex != null and tex.get_width() >= 384 and tex.get_height() == tex.get_width() \
			and tex.get_image().has_mipmaps() and tex.resource_path == "res://assets/ui/reaktionen/%s.svg" % r_name
	check(tex_ok, "5 Reaktionsbilder aus assets/ui/reaktionen (SVG, ≥ 384 px, Mipmaps)")
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
	# 1.6.11: als Reihe oder als Block 3 + 2 – in Lesereihenfolge (in einer Reihe nach rechts, die nächste Reihe darunter)
	var order_ok := true
	for i in range(1, rb.centers.size()):
		var p0: Vector2 = rb.centers[i - 1]
		var p1: Vector2 = rb.centers[i]
		order_ok = order_ok and ((absf(p1.y - p0.y) < 1.0 and p1.x > p0.x) or p1.y > p0.y + rb.r)
	check(order_ok, "Knöpfe in Lesereihenfolge (%s)" % str(rb.centers))
	var labels: Array = []
	for i in TeaseMenu.REACT_ORDER.size():
		labels.append(rb._get_tooltip(rb.centers[i]))
	check(labels == ["Lachen", "Klatschen", "Daumen hoch", "Schreck", "Bäää"], "Hilfetexte je Knopf (%s)" % str(labels))
	for i in TeaseMenu.REACT_ORDER.size():
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
	check(tf.reactions.r >= 22.0 and badge.row_reserve > tf.reactions.r * 2.0 * TeaseMenu.REACT_ORDER.size(), "großer Modus: Knöpfe ≥ 44 px, Zeile kürzt den Namen (r %.0f, Platz %.0f)" % [tf.reactions.r, badge.row_reserve])
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
				# Beta 1.6.7: „Erwischt!“-Buzzer – zwei Nachbarn gleichzeitig (im normalen Modus auch alle Mitspieler): groß, im Bild,
				# getrennt, nicht über Mau-Knopf und Stapeln
				var sets: Array = [[1, 2] if n > 2 else [1]]
				if not big_on and n > 3:
					sets.append(range(1, n))
				for cs in sets:
					sample.catch_targets = cs
					show(sample.view_for(0))
					await create_timer(0.6 if big_on else 0.05).timeout
					var bz := buzzer_issues()
					check(bz.is_empty(), "%s, erwischbar %s: Buzzer groß, im Bild, getrennt, frei von Mau und Stapeln (%s)" % [what, str(cs), str(bz)])
				sample.catch_targets = []
	UiFonts.set_level("normal", root)

	await cushion_checks()
	await surprise_checks()

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
	check(keys.filter(func(x: String) -> bool: return x != "backs") == ["ball", "kissen_geheim", "kissen_name"], "Übung: nur Papierkugel und die 2 Kissen (%s)" % str(keys))
	check(tz.menu.rows().size() == 1, "Übung: eine Reihe (%s)" % str(tz.menu.rows()))
	tz._on_menu_chosen("ball")
	check(tz.effects_of("ball").size() == 1, "Übung: Kugel kommt sofort als Ereignis an")
	# Beta 1.6.6: Furzkissen auf den Computergegner (lokal): Wahl → Bestätigung als leise Zeile, danach gesperrt
	# (Beta 1.6.10: echter Tipp auf den runden Knopf „Kissen geheim“)
	tz.open_menu(bot_seat)
	check(tz.menu.key_on("kissen_geheim") and tz.menu.key_on("kissen_name"), "Übung: beide Kissen-Knöpfe am Computergegner aktiv")
	await process_frame
	tap_screen(tz.menu.get_global_transform_with_canvas() * tz.menu.button_center(keys.find("kissen_geheim")))
	check(tz.menu == null, "Übung: Tipp „Kissen geheim“ legt sofort, Menü zu")
	var toasts: Array = ts.table.hint_bar._toasts.map(func(e: Dictionary) -> String: return str(e.text))
	check(toasts.has("Kissen liegt bei %s." % tz._name(bot_seat)), "Übung: Bestätigung „Kissen liegt bei …“ (%s)" % str(toasts))
	tz.tick(0.45)
	tz.open_menu(bot_seat)
	check(not tz.menu.key_on("kissen_geheim") and not tz.menu.key_on("kissen_name") and tz.menu.note.contains("Das Kissen muss sich erst wieder aufpusten."),
		"Übung: danach beide gesperrt (%s)" % tz.menu.note)
	tz.close_menu(false)
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


# Beta 1.6.6: Furzkissen (docs/module/eastereggs2.md 12.4) – ab 1.6.10 runde Knöpfe „Kissen geheim“/„Kissen mit Namen“ (echter Tipp), Vorprüfung nur mit dem
# eigenen Kissen (rate/busy mit Hinweis), Bestätigung nur als leise Zeile beim Leger, Ablehnung mit Kissen-Texten (ohne Ausgrauen der
# übrigen Knöpfe), Pups je Rolle (Ziel laut + 150 ms Vibration + groß, alle anderen leise, auch der Leger), Zeile „Kim war's!“ nur
# mit reveal und from, sonst „Wer war das?“, Lage im Bild ohne harte Hindernisse, reduziert, Necken aus, Platzwechsel, großer Modus.
func cushion_checks() -> void:
	await setup("client", 1, 4)
	var hb: Toast = t.hint_bar
	var toasts := func() -> Array: return hb._toasts.map(func(e: Dictionary) -> String: return str(e.text))
	# --- Menü (Beta 1.6.10): zwei runde Knöpfe „Kissen geheim“ und „Kissen mit Namen“ wie die übrigen, in Reihe 2 unter
	#     Kugel/Schnarchen/Wecker/Karten ansehen; bis 1.6.9 eine eigene Zeile mit Kissenbild und Text-Knöpfen (am Tisch tippten alle
	#     auf das Bild)
	tf.open_menu(1)
	var m := tf.menu
	var keys: Array = m.items.map(func(it: Dictionary) -> String: return str(it.key))
	check(keys == ["ball", "snore", "alarm", "kissen_geheim", "kissen_name", "backs"], "Kissen als runde Knöpfe (%s)" % str(keys))
	var labels: Array = m.items.map(func(it: Dictionary) -> String: return str(it.label))
	check(labels.slice(3, 5) == ["Kissen geheim", "Kissen mit Namen"], "Beschriftung „Kissen geheim“/„Kissen mit Namen“ (%s)" % str(labels))
	check(m.key_on("kissen_geheim") and m.key_on("kissen_name"), "beide Kissen-Knöpfe aktiv")
	var rs: Array = m.rows()
	check(rs.size() == 2 and rs[0] == [0, 1, 2, 5] and rs[1] == [3, 4], "Mensch: Reihe 1 Kugel/Schnarchen/Wecker/Karten, Reihe 2 die Kissen (%s)" % str(rs))
	var kg := m.button_center(3)
	var kn := m.button_center(4)
	var bc := Rect2(Vector2.ZERO, m.size).grow(-TeaseMenu.BTN_R)
	check(is_equal_approx(kg.y, kn.y) and kg.y > m.button_center(0).y + TeaseMenu.BTN_R * 2.0 and kn.x - kg.x >= TeaseMenu.BTN_R * 2.0 + 20.0
		and bc.has_point(kg) and bc.has_point(kn),
		"Kissen-Knöpfe nebeneinander unter der ersten Reihe, in der Blase (%s %s)" % [kg, kn])
	var sep := true
	for i in m.items.size():
		for j in m.items.size():
			if i < j and m.button_center(i).distance_to(m.button_center(j)) < (TeaseMenu.BTN_R + 10.0) * 2.0:
				sep = false
	check(sep, "Trefferflächen der 6 Knöpfe überlappen nicht")
	check(m.key_at(kg) == "kissen_geheim" and m.key_at(kn) == "kissen_name", "Trefferfläche: Knopfmitte gehört zum Knopf")
	check(Rect2(Vector2.ZERO, t.size).encloses(Rect2(m.position, m.size)), "Menü mit zwei Reihen ganz im Bild")
	src.sent.clear()
	tap_screen(m.get_global_transform_with_canvas() * kn)
	check(src.sent == [{"k": "kissen", "to": 1, "reveal": true}] and tf.menu == null, "Tipp „Kissen mit Namen“ → Wunsch mit reveal, Menü zu (%s)" % str(src.sent))
	tf.tick(0.45)
	tf.open_menu(3)
	src.sent.clear()
	tap_screen(tf.menu.get_global_transform_with_canvas() * tf.menu.button_center(tf.menu.items.find_custom(func(it: Dictionary) -> bool: return it.key == "kissen_geheim")))
	check(src.sent == [{"k": "kissen", "to": 3, "reveal": false}] and tf.menu == null, "Tipp „Kissen geheim“ → Wunsch ohne reveal, Menü zu (%s)" % str(src.sent))
	check(tf.effects().is_empty() and snd.log.is_empty(), "Legen allein: kein Bild, kein Ton")
	# --- Bestätigung (nur beim Leger): leise Zeile, dann eigene Sperre bzw. „liegt schon“
	var conf := NetProtocol.make_cushion(0, 1, true)
	src.tease.commit(conf, clock)
	src.fx_event.emit(conf)
	check(toasts.call().has("Kissen liegt bei Lena.") and tf.effects().is_empty() and snd.log.is_empty(), "Bestätigung: Zeile „Kissen liegt bei Lena.“, kein Bild, kein Ton")
	tf.tick(0.45)
	tf.open_menu(3)
	check(not tf.menu.key_on("kissen_geheim") and not tf.menu.key_on("kissen_name") and tf.menu.note.contains("Das Kissen muss sich erst wieder aufpusten.")
		and bool(tf.menu.items[0].on), "eigene Sperre: beide Kissen grau mit Hinweis, Kugel bleibt aktiv (%s)" % tf.menu.note)
	for kk in ["kissen_geheim", "kissen_name"]:
		src.sent.clear()
		tap_screen(tf.menu.get_global_transform_with_canvas() * tf.menu.button_center(tf.menu.items.find_custom(func(it: Dictionary) -> bool: return it.key == kk)))
		check(src.sent.is_empty() and tf.menu != null, "gesperrt: Tipp „%s“ sendet nichts, Menü bleibt" % kk)
	tf.close_menu(false)
	clock += TeaseRules.CUSHION_BLOCK_MIN_MS + 10
	tf.tick(0.45)
	tf.open_menu(1)
	check(not tf.menu.key_on("kissen_geheim") and not tf.menu.key_on("kissen_name") and tf.menu.note.contains("Da liegt schon ein Kissen."),
		"eigenes Kissen liegt beim Ziel: beide grau, „Da liegt schon ein Kissen.“ (%s)" % tf.menu.note)
	tf.close_menu(false)
	tf.tick(0.45)
	tf.open_menu(3)
	check(tf.menu.key_on("kissen_geheim") and tf.menu.key_on("kissen_name") and not tf.menu.note.contains("Kissen"), "anderes Ziel nach der Mindestzeit wieder frei (%s)" % tf.menu.note)
	tf.close_menu(false)
	# fremde Bestätigung (sollte nie kommen): nichts
	var n_t: int = toasts.call().size()
	src.fx_event.emit(NetProtocol.make_cushion(2, 3, true))
	check(toasts.call().size() == n_t, "Bestätigung eines anderen Legers: keine Zeile")
	# --- Ablehnung (fx_no mit k "kissen"): Kissen-Texte, übrige Knöpfe nicht ausgegraut
	src._fx_refuse("busy", "kissen")
	check(toasts.call()[-1] == "Da liegt schon ein Kissen.", "fx_no busy (Kissen) → „Da liegt schon ein Kissen.“")
	src._fx_refuse("rate", "kissen")
	check(toasts.call()[-1] == "Das Kissen muss sich erst wieder aufpusten." and not tf.rate_limited() and not tf.reactions.gray,
		"fx_no rate (Kissen) → Zeile, Reaktionen bleiben aktiv")
	tf._last_target = 1
	src._fx_refuse("busy")
	check(toasts.call()[-1] == "Lena wird gerade schon geweckt.", "fx_no busy ohne k: wie bisher")
	# --- Pups am Mitspieler (ich bin der geheime Leger: Kopie mit from) → leise, „Wer war das?“
	snd.log.clear()
	tf.vibrations.clear()
	var pop := NetProtocol.make_cushion_pop(1, false, 0)
	src.tease.commit(pop, clock)
	src.fx_event.emit(pop)
	var cf: Array = tf.effects_of("kissen")
	check(cf.size() == 1 and sounds() == ["furzkissen leise"] and tf.vibrations.is_empty(), "Pups bei Lena: Bild, Ton leise beim Leger, keine Vibration (%s)" % str(sounds()))
	check(src.tease.cushion_at(1).is_empty(), "Spiegel: Kissen nach dem Pups weg")
	var c1: TeaseFx.CushionFx = cf[0]
	check(is_equal_approx(c1.cw, TeaseFx.CUSHION_W) and c1.target == 1, "Kissen an Mitspielern: Größe CUSHION_W")
	tf.tick(0.1)
	check(c1.squash() < 0.05, "erst rund …")
	tf.tick(0.25)
	check(c1.squash() > 0.8, "… dann plattgedrückt (%.2f)" % c1.squash())
	check(float(t.seat_node(1).get("_bump")) > 0.0, "Avatar staucht sich")
	var texts: Array = tf.effects_of("text").map(func(e: TeaseFx.TextFx) -> String: return e.text)
	check(texts.is_empty(), "Zeile noch nicht (erst „Pfffrt!“)")
	tf.tick(0.9)
	texts = tf.effects_of("text").map(func(e: TeaseFx.TextFx) -> String: return e.text)
	check(texts == ["Wer war das?"], "geheim: „Wer war das?“, auch beim Leger (%s)" % str(texts))
	tf.tick(1.4)
	check(tf.effects_of("kissen").is_empty(), "Kissen räumt sich nach %.1f s auf" % TeaseFx.CUSHION_S)
	tf.clear()
	# Lage: ganz im Bild, keine harten Hindernisse (Mau, Erwischt, Stapel, Hand, Knöpfe), an jedem Platz
	for s in [1, 2, 3, 0]:
		src.fx_event.emit(NetProtocol.make_cushion_pop(s, true, 2 if s != 2 else 1))
		var fx_s: TeaseFx.CushionFx = tf.effects_of("kissen")[-1]
		var br := fx_s.area()
		var rr := Rect2(fx_s.position + br.position, br.size)
		var hits: Array = []
		for b: Rect2 in tf._blockers(s).hard:
			if rr.grow(-2.0).intersects(b):
				hits.append(b)
		check(Rect2(Vector2.ZERO, t.size).encloses(rr) and hits.is_empty(), "Platz %d: Kissen ganz im Bild, über keinem harten Hindernis (%s, %s)" % [s, rr, str(hits)])
		tf.clear()
	# --- Pups beim Ziel (ich), mit Namen: laut, Vibration 150 ms, groß, „Lena war's!“
	snd.log.clear()
	tf.vibrations.clear()
	src.fx_event.emit(NetProtocol.make_cushion_pop(0, true, 1))
	var mine: TeaseFx.CushionFx = tf.effects_of("kissen")[0]
	check(sounds() == ["furzkissen"] and tf.vibrations == [150] and is_equal_approx(mine.cw, TeaseFx.CUSHION_W_ME), "Ziel: Ton laut, Vibration 150 ms, groß (%s %s)" % [str(sounds()), str(tf.vibrations)])
	var mbr := mine.area()
	var mb := Rect2(mine.position + mbr.position, mbr.size)
	var rbx := tf.reactions.get_global_transform_with_canvas()
	var rbg := Rect2(rbx * tf.reactions.bounds().position, tf.reactions.bounds().size)
	var lx := tf.layer.get_global_transform_with_canvas()
	check(mine.position.y < float(tf.anchor(0).pos.y) and not Rect2(lx * mb.position, mb.size).grow(-2.0).intersects(rbg),
		"Ziel: Kissen über dem Namensschild, nicht über den Reaktionsknöpfen (%s / %s)" % [Rect2(lx * mb.position, mb.size), rbg])
	tf.tick(1.3)
	var lines: Array = tf.effects_of("text")
	check(lines.size() == 1 and (lines[0] as TeaseFx.TextFx).text == "Lena war's!" and (lines[0] as TeaseFx.TextFx).size_px >= UiFonts.size("hinweisleiste"),
		"Ziel: „Lena war's!“ in Bannergröße")
	tf.clear()
	# Zuschauer, mit Namen → leise, „Lena war's!“; reveal ohne from → „Wer war das?“
	snd.log.clear()
	src.fx_event.emit(NetProtocol.make_cushion_pop(2, true, 1))
	tf.tick(1.3)
	texts = tf.effects_of("text").map(func(e: TeaseFx.TextFx) -> String: return e.text)
	check(sounds() == ["furzkissen leise"] and texts == ["Lena war's!"], "Zuschauer: leise, „Lena war's!“ (%s %s)" % [str(sounds()), str(texts)])
	tf.clear()
	src.fx_event.emit({"t": "fx", "k": "kissen_pop", "to": 2, "reveal": true})
	tf.tick(1.3)
	texts = tf.effects_of("text").map(func(e: TeaseFx.TextFx) -> String: return e.text)
	check(texts == ["Wer war das?"], "reveal ohne from: „Wer war das?“")
	tf.clear()
	# Platzwechsel: Kissen weg, die Zeile kommt nicht mehr
	src.fx_event.emit(NetProtocol.make_cushion_pop(3, true, 1))
	t.play_event({"e": "seats", "map": [0, 1, 2, 3]}, 1.0)
	tf.tick(1.5)
	check(tf.effects().is_empty(), "Platzwechsel: Kissen und ausstehende Zeile weg")
	# reduziert: liegt schon flach, kein Stauchen
	t.reduced = true
	t.seat_node(1).set("_bump", 0.0)
	src.fx_event.emit(NetProtocol.make_cushion_pop(1, false))
	var red: TeaseFx.CushionFx = tf.effects_of("kissen")[0]
	tf.tick(0.05)
	var sq0 := red.squash()
	tf.tick(0.4)
	check(red.reduced and is_equal_approx(sq0, red.squash()) and is_zero_approx(float(t.seat_node(1).get("_bump"))), "reduziert: kein Plattdrücken, kein Stauchen")
	t.reduced = false
	tf.clear()
	# Necken aus: nichts
	tf.set_enabled(false)
	snd.log.clear()
	src.fx_event.emit(NetProtocol.make_cushion_pop(0, true, 1))
	src.fx_event.emit(NetProtocol.make_cushion(0, 2, true))
	check(tf.effects().is_empty() and snd.log.is_empty(), "Necken aus: kein Pups, kein Ton")
	tf.set_enabled(true)
	# Ziel mit Necken aus: keine Kissen-Zeile
	src._fx_offs = [3]
	tf.open_menu(3)
	check(not tf.menu.items.any(func(it: Dictionary) -> bool: return TeaseMenu.is_cushion(str(it.key))), "Ziel mit Necken aus: keine Kissen-Knöpfe")
	tf.close_menu(false)
	src._fx_offs = []
	# großer Modus: Pups an der Listenzeile, ganz im Bild
	t.set_big(true)
	show(sample.view_for(0))
	await create_timer(1.0).timeout
	tf.tick(0.2)
	for s in [1, 0]:
		src.fx_event.emit(NetProtocol.make_cushion_pop(s, true, 2))
		var fb: TeaseFx.CushionFx = tf.effects_of("kissen")[-1]
		var bb := fb.area()
		check(Rect2(Vector2.ZERO, t.size).encloses(Rect2(fb.position + bb.position, bb.size)) and fb.cw > TeaseFx.CUSHION_W and fb.text_side,
			"großer Modus, Platz %d: Kissen größer, Text in der Zeile, ganz im Bild" % s)
		tf.clear()
	tf.tick(0.45)
	tf.open_menu(1)
	check(tf.menu != null and Rect2(Vector2.ZERO, t.size).encloses(Rect2(tf.menu.position, tf.menu.size)), "großer Modus: Menü mit Kissen-Knöpfen ganz im Bild")
	tf.close_menu(false)
	t.set_big(false)
	# Schrift „Sehr groß“: Menü passt
	UiFonts.set_level("sehr_gross", root)
	t._layout()
	show(sample.view_for(0))
	tf.tick(0.45)
	for s in [1, 2, 3]:
		tf.open_menu(s)
		check(Rect2(Vector2.ZERO, t.size).encloses(Rect2(tf.menu.position, tf.menu.size)), "Sehr groß: Menü an Platz %d ganz im Bild (%s)" % [s, Rect2(tf.menu.position, tf.menu.size)])
		tf.close_menu(false)
	UiFonts.set_level("normal", root)


# Gerätetest 1.6.6 (F1): Menü- und Reaktionsknöpfe haben immer Vorrang vor den Überraschungen (FunFx: Mau-Katze auf dem Stapel,
# Schmetterling). Die Katze liegt jeweils genau unter dem getippten Knopf, der Schmetterling fliegt. Ohne Menü schiebt der Tipp die Katze
# weiter weg. Ursache des Befunds war das Selbstschließen nach 5 s (der Tipp kam am Gerät ~12 s nach dem Öffnen): Danach trifft der
# Tipp den Tisch und sendet nichts – auch das ist hier festgehalten.
func surprise_checks() -> void:
	await setup("client", 1, 4)
	var fun: FunFx = t.fun
	fun.auto_process = false
	fun.cat.arrive(t._draw_pos, t.pile_w, t.size.x, true)
	for i in 80:
		fun.tick(0.1)
	fun.sky.launch(false, fun.rng, t.size)
	check(fun.cat.st == "sleep" and fun.sky.active() and fun.sky.kind == "butterfly", "Überraschungen laufen: Katze schläft auf dem Stapel, Schmetterling fliegt")
	clock += TeaseRules.FX_SLOW_MS + 1000          # Schnarchen/Wecker frei
	tf.tick(0.2)
	var cat_under := func(screen: Vector2) -> bool:
		fun.cat.position = t._world.to_local(screen) + Vector2(0, 16.0 * fun.cat.k)
		return fun.cat.hit(t._world.to_local(screen))
	# runde Knöpfe: Papierkugel, Schnarchen, Wecker, Kissen geheim, Kissen mit Namen, Karten ansehen (Beta 1.6.10: Kissen auch rund)
	tf.open_menu(1)
	var keys: Array = tf.menu.items.map(func(it: Dictionary) -> String: return str(it.key))
	tf.close_menu(false)
	check(keys == ["ball", "snore", "alarm", "kissen_geheim", "kissen_name", "backs"], "runde Knöpfe (%s)" % str(keys))
	for i in keys.size():
		clock += 10000
		tf.tick(0.45)
		tf.open_menu(1)
		var m := tf.menu
		var bp: Vector2 = m.get_global_transform_with_canvas() * m.button_center(i)
		check(cat_under.call(bp) and m.key_on(str(keys[i])), "Katze liegt unter „%s“ (aktiv)" % keys[i])
		src.sent.clear()
		t.backs_viewer.visible = false
		tap_screen(bp)
		if keys[i] == "backs":
			check(src.sent.is_empty() and t.backs_viewer.visible and tf.menu == null and fun.cat.st == "sleep", "Katze: Tipp „Karten ansehen“ öffnet die Großansicht")
			t.backs_viewer.visible = false
		elif TeaseMenu.is_cushion(str(keys[i])):
			check(src.sent == [{"k": "kissen", "to": 1, "reveal": keys[i] == "kissen_name"}] and tf.menu == null and fun.cat.st == "sleep",
				"Katze + Schmetterling: Tipp „%s“ sendet das Kissen, Katze bleibt (%s, %s)" % [keys[i], str(src.sent), fun.cat.st])
		else:
			check(src.sent == [{"k": keys[i], "to": 1}] and tf.menu == null and fun.cat.st == "sleep", "Katze: Tipp „%s“ sendet (%s)" % [keys[i], str(src.sent)])
	# die 5 Reaktionsknöpfe (1.6.11: mit Bäää)
	var rb := tf.reactions
	for i in TeaseMenu.REACT_ORDER.size():
		clock += 10000
		tf.tick(0.2)
		var rp: Vector2 = rb.get_global_transform_with_canvas() * rb.centers[i]
		check(cat_under.call(rp), "Katze liegt unter Reaktion %d" % (i + 1))
		src.sent.clear()
		tap_screen(rp)
		check(src.sent == [{"k": "react", "r": TeaseMenu.REACT_ORDER[i]}] and fun.cat.st == "sleep", "Katze: Reaktion %d sendet (%s)" % [i + 1, str(src.sent)])
	# Menü nach 15 s (bis 1.6.6: 5 s) von selbst zu: ein später Tipp auf die alte Stelle sendet nichts (so am Gerät, F1)
	clock += 10000
	tf.tick(0.45)
	tf.open_menu(1)
	var late: Vector2 = tf.menu.get_global_transform_with_canvas() * tf.menu.button_center(4)
	for i in 76:                                # Beta 1.6.7: 15 s (vorher 5 s)
		tf.tick(0.2)
	src.sent.clear()
	tap_screen(late)
	check(tf.menu == null and src.sent.is_empty(), "15 s ohne Tipp: Menü zu, später Tipp auf „Kissen mit Namen“ sendet nichts")
	# ohne Menü: Tipp auf die Katze schiebt sie weg (wie bisher)
	var cp: Vector2 = t._world.get_global_transform_with_canvas() * t._draw_pos
	check(cat_under.call(cp), "Katze auf dem Stapel antippbar")
	tap_screen(cp)
	check(fun.cat.angry and src.sent.is_empty(), "ohne Menü: Tipp auf die Katze schiebt sie weg (%s)" % fun.cat.st)
