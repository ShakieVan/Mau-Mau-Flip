class_name TableDemo
extends Control
# Tisch-Demo (Modul F1b): spielt eine vorbereitete Ereignisfolge mit Beispielsichten ab – 4 Spieler, Aussetzen, Flip
# (Tag → Nacht), Wünscher mit Farbwelle, +5, Mau, Ziehen, Richtungswechsel, Alle aussetzen, Farbjagd (Spielautomat), Sieg.
# Bedienung: Leertaste/Tipp oben rechts „Weiter“ = nächster Schritt, A = automatisch, R = neu, F = Farbrad, H = Kartenhilfe,
# S = Sichtschutz, E = Effekte voll/reduziert. Aufruf: Szene res://scenes/dev/table_demo.tscn starten.

const STEP_PAUSE := 0.6

var table: TableView
var hand: DemoHand
var sample: TableSamples
var steps: Array[Callable] = []
var step_no := 0
var auto := true
var _wait := 1.2
var _info: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	table = TableView.new()
	add_child(table)
	hand = DemoHand.new()
	table.set_hand(hand)
	table.action.connect(func(a: Dictionary) -> void: table.show_notice("Aktion: %s" % JSON.stringify(a)))
	table.sort_pressed.connect(func() -> void: table.show_notice("Sortieren (Hand: Modul F1a)"))
	table.backs_pressed.connect(func() -> void: table.show_notice("Eigene Rückseiten (Hand: Modul F1a)"))
	table.wish_picker.color_chosen.connect(func(c: String) -> void: table.show_notice("Farbe gewählt: %s" % UiPalette.color_name(c)))
	table.handover.revealed.connect(func() -> void: table.show_notice("Aufgedeckt"))
	_info = UiTheme.label("", UiFonts.text(600, 90.0), 15, Color(1, 1, 1, 0.6))
	_info.position = Vector2(14, 8)
	add_child(_info)
	restart()


func restart() -> void:
	var sc := scenario()
	sample = sc["sample"]
	steps.assign(sc["steps"])
	step_no = 0
	table.director.clear()
	table.fx.clear()
	table.apply_view(sample.view_for(0))
	_wait = 1.2


# Ausgangslage und Schritte. Jeder Schritt verändert sample und liefert die Ereignisse.
static func scenario() -> Dictionary:
	var s := TableSamples.create(4, 11, [0, 1, 3, 1])
	# Eigene Karten: 5 Stück, jede mit der Seite, die gespielt wird
	for k in ["hell_blau_7", "dunkel_wuenscher", "dunkel_lila_alle_aussetzen", "dunkel_farbjagd", "dunkel_orange_5"]:
		s.give(0, k)
	for k in ["hell_blau_aussetzen", "dunkel_lila_plus5", "dunkel_lila_richtungswechsel", "dunkel_orange_2", "dunkel_orange_9"]:
		s.give(1, k)
	for k in ["dunkel_orange_8", "dunkel_orange_4"]:
		s.give(2, k)
	s.give(3, "hell_blau_flip")
	s.give(3, "dunkel_lila_3")
	s.set_top("hell_blau_9")
	s.turn = 0
	var st: Array[Callable] = []
	var me := func(k: String) -> int: return s.find_any(0, k)
	st.append(func() -> Array:                                   # 1 Ich lege Blau 7
		var ev := s.play(0, s.find_any(0, "hell_blau_7"))
		s.advance()
		return ev)
	st.append(func() -> Array:                                   # 2 Lena: Aussetzen → Tom setzt aus
		var ev := s.play(1, s.find_any(1, "hell_blau_aussetzen"))
		ev.append({"e": "skip", "seat": 2})
		s.advance(2)
		return ev)
	st.append(func() -> Array:                                   # 3 Mia: Flip → Nacht
		var ev := s.play(3, s.find_any(3, "hell_blau_flip"))
		ev.append_array(s.flip())
		s.advance()
		return ev)
	st.append(func() -> Array:                                   # 4 Ich: Wünscher → Lila
		var ev := s.play(0, me.call("dunkel_wuenscher"), "lila")
		s.advance()
		return ev)
	st.append(func() -> Array:                                   # 5 Lena: +5 → Tom zieht 5 und setzt aus
		s.stack_deck(["dunkel_pink_2", "dunkel_tuerkis_7", "dunkel_orange_1", "dunkel_pink_flip", "dunkel_lila_9"])
		var ev := s.play(1, s.find_any(1, "dunkel_lila_plus5"))
		ev.append_array(s.draw(2, 5))
		ev.append({"e": "skip", "seat": 2})
		s.advance(2)
		return ev)
	st.append(func() -> Array:                                   # 6 Mia legt, hat noch eine Karte: Mau!
		var ev := s.play(3, s.find_any(3, "dunkel_lila_3"))
		ev.append_array(s.call_mau(3))
		s.advance()
		return ev)
	st.append(func() -> Array:                                   # 7 Ich ziehe eine Karte
		s.stack_deck(["dunkel_orange_3"])
		var ev := s.draw(0, 1)
		s.advance()
		return ev)
	st.append(func() -> Array:                                   # 8 Lena: Richtungswechsel
		var ev := s.play(1, s.find_any(1, "dunkel_lila_richtungswechsel"))
		s.dir = -1
		ev.append({"e": "reverse", "dir": -1})
		s.advance()
		return ev)
	st.append(func() -> Array:                                   # 9 Ich: Alle aussetzen → nochmal ich
		var ev := s.play(0, me.call("dunkel_lila_alle_aussetzen"))
		ev.append({"e": "skip_all", "seat": 0})
		return ev)
	st.append(func() -> Array:                                   # 10 Ich: Farbjagd Orange → Mia zieht bis Orange
		s.stack_deck(["dunkel_pink_5", "dunkel_tuerkis_2", "dunkel_lila_8", "dunkel_orange_6"])
		var ev := s.play(0, me.call("dunkel_farbjagd"), "orange")
		s.mau.erase(3)
		ev.append_array(s.draw(3, 4))
		s.advance(2)
		return ev)
	st.append(func() -> Array:                                   # 11 Tom: Orange 8
		var ev := s.play(2, s.find_any(2, "dunkel_orange_8"))
		s.advance()
		return ev)
	st.append(func() -> Array:                                   # 12 Lena: Orange 2
		var ev := s.play(1, s.find_any(1, "dunkel_orange_2"))
		s.advance()
		return ev)
	st.append(func() -> Array:                                   # 13 Ich: Orange 5 und Mau!
		var ev := s.play(0, me.call("dunkel_orange_5"))
		ev.append_array(s.call_mau(0))
		s.advance()
		return ev)
	st.append(func() -> Array:                                   # 14 Mia: Orange 6
		var ev := s.play(3, s.find_any(3, "dunkel_orange_6"))
		s.advance()
		return ev)
	st.append(func() -> Array:                                   # 15 Tom: Orange 4
		var ev := s.play(2, s.find_any(2, "dunkel_orange_4"))
		s.advance()
		return ev)
	st.append(func() -> Array:                                   # 16 Lena: Orange 9
		var ev := s.play(1, s.find_any(1, "dunkel_orange_9"))
		s.advance()
		return ev)
	st.append(func() -> Array:                                   # 17 Ich: letzte Karte → Mau-Mau, Rundenende
		var ev := s.play(0, me.call("dunkel_orange_3"))
		ev.append_array(s.finish_round(0))
		return ev)
	return {"sample": s, "steps": st}


func next_step() -> bool:
	if step_no >= steps.size():
		return false
	var events: Array = steps[step_no].call()
	step_no += 1
	table.handle_state(sample.events_for(0, events), sample.view_for(0))
	return true


func _process(delta: float) -> void:
	_info.text = "Schritt %d/%d · %s · Leertaste weiter, A auto (%s), R neu, F Farbrad, H Hilfe, S Sichtschutz, E Effekte (%s)" % [
		step_no, steps.size(), sample.side, "an" if auto else "aus", "reduziert" if table.reduced else "voll"]
	if not auto or table.director.is_busy():
		return
	_wait -= delta
	if _wait <= 0.0:
		_wait = STEP_PAUSE
		if not next_step():
			_wait = 4.0
			auto = false


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_SPACE:
			next_step()
		KEY_A:
			auto = not auto
		KEY_R:
			restart()
		KEY_F:
			table.open_color_wheel()
		KEY_H:
			table.show_help("hell_wuenscher", "Wünscher", "Leg ihn auf [b]jede[/b] Karte und wünsch dir eine Farbe. Der Nächste muss diese Farbe bedienen oder einen Joker legen.")
		KEY_S:
			table.handover.show_for("Lena", 0, 1, 4, sample.discard.size(), sample.deck.size(), sample.side)
		KEY_E:
			table.reduced = not table.reduced
