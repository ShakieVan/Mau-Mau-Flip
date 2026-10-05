extends SceneTree
# Modul F1a: Gestenerkennung der Hand als reine Zustandsmaschine (HandLayout.Gesture), nur mit Zeit und Weg als Eingabe:
# Tipp, Doppeltipp, 8-dp-Toleranz, Winkelentscheidung (|dy| > 1,2·|dx|), Ausspielen per Schwelle oder Schnippen (> 1200 dp/s,
# ±35°), Zurückziehen bricht ab, Halten 350 ms → Großansicht, danach oben = ausspielen, seitlich = umsortieren,
# unten auf das „?“ (40 dp) = Hilfe, Loslassen ohne Zug = Großansicht bleibt; aus dem seitlichen Gleiten nach oben ausspielen.
# Aufruf: tools/godot_run.ps1 -Script res://tests/test_ui_hand_gesture.gd -Headless
const DP := 2.0
var ok := 0
var failed := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		ok += 1
	else:
		failed += 1
		print("FAIL: ", msg)


func fresh() -> HandLayout.Gesture:
	var g := HandLayout.Gesture.new()
	g.dp = DP
	g.play_dist = 180.0
	g.help_dist = 40.0 * DP
	return g


# Bewegung in gleichmäßigen Schritten (je 16 ms) von a nach b; gibt alle Ereignisse zurück.
func path(g: HandLayout.Gesture, t0: float, a: Vector2, b: Vector2, steps: int) -> Array:
	var evs: Array = []
	for k in range(1, steps + 1):
		var e := g.move(t0 + k * 16.0, a.lerp(b, float(k) / steps))
		if e != "" and e != "move":
			evs.append(e)
	return evs


func _init() -> void:
	var p0 := Vector2(800, 640)
	# Tipp und Doppeltipp
	var g := fresh()
	g.press(0.0, p0)
	check(g.release(90.0, p0) == "tap", "Tipp")
	g.press(200.0, p0 + Vector2(3, 2))
	check(g.release(260.0, p0 + Vector2(3, 2)) == "double_tap", "Doppeltipp innerhalb 350 ms")
	g.press(320.0, p0)
	check(g.release(380.0, p0) == "tap", "dritter Tipp zählt neu")
	g = fresh()
	g.press(0.0, p0)
	g.release(80.0, p0)
	g.press(600.0, p0)
	check(g.release(650.0, p0) == "tap", "zu langsam für Doppeltipp")
	g = fresh()
	g.press(0.0, p0)
	g.release(80.0, p0)
	g.press(150.0, p0 + Vector2(120, 0))
	check(g.release(200.0, p0 + Vector2(120, 0)) == "tap", "Doppeltipp nur am selben Ort")
	# Toleranz 8 dp
	g = fresh()
	g.press(0.0, p0)
	check(g.move(50.0, p0 + Vector2(7.0 * DP, 0)) == "", "unter 8 dp keine Bewegung")
	check(g.state == HandLayout.Gesture.S.PENDING, "noch unentschieden")
	check(g.release(100.0, p0 + Vector2(7.0 * DP, 0)) == "tap", "kleine Bewegung bleibt Tipp")
	# Winkelentscheidung
	g = fresh()
	g.press(0.0, p0)
	check(g.move(40.0, p0 + Vector2(12, -20)) == "play_drag", "steil nach oben = Ausspielen ziehen")
	g = fresh()
	g.press(0.0, p0)
	check(g.move(40.0, p0 + Vector2(20, -20)) == "horizontal", "45° = seitlich")
	check(g.release(80.0, p0 + Vector2(40, -20)) == "horizontal_end", "seitliches Gleiten endet")
	g = fresh()
	g.press(0.0, p0)
	check(g.move(40.0, p0 + Vector2(2, 24)) == "down", "nach unten ohne Halten")
	check(g.release(80.0, p0 + Vector2(2, 30)) == "cancel", "nach unten ohne Halten bewirkt nichts")
	# Ausspielen über die Schwelle
	g = fresh()
	g.press(0.0, p0)
	var evs := path(g, 0.0, p0, p0 + Vector2(10, -220), 40)
	check(evs.has("play_drag") and g.play_armed, "Zug über die Schwelle macht scharf")
	check(g.release(40 * 16.0 + 300.0, p0 + Vector2(10, -220)) == "play", "Loslassen über der Schwelle spielt aus")
	# Zurückziehen bricht ab
	g = fresh()
	g.press(0.0, p0)
	path(g, 0.0, p0, p0 + Vector2(0, -220), 30)
	path(g, 30 * 16.0, p0 + Vector2(0, -220), p0 + Vector2(0, -60), 30)
	check(not g.play_armed, "Zurückziehen entschärft")
	check(g.release(60 * 16.0 + 300.0, p0 + Vector2(0, -60)) == "cancel", "zurückgezogen und losgelassen = Abbruch")
	# Schnippen
	g = fresh()
	g.press(0.0, p0)
	path(g, 0.0, p0, p0 + Vector2(0, -90), 3)        # 90 px in 48 ms ≈ 1875 px/s < 2400 (1200 dp/s)
	check(g.release(48.0, p0 + Vector2(0, -90)) == "cancel", "zu langsam für Schnippen")
	g = fresh()
	g.press(0.0, p0)
	path(g, 0.0, p0, p0 + Vector2(10, -150), 3)       # ≈ 3100 px/s, fast senkrecht
	check(g.release(48.0, p0 + Vector2(10, -150)) == "play", "Schnippen nach oben spielt aus")
	check(g.velocity.y < -2400.0, "Geschwindigkeit beim Loslassen gemessen (%.0f px/s)" % g.velocity.y)
	check(g.is_flick(Vector2(0, -2600)) and not g.is_flick(Vector2(2000, -2600)) and g.is_flick(Vector2(1700, -2600)), "Schnippen nur innerhalb ±35°")
	check(not g.is_flick(Vector2(0, 2600)), "Schnippen nach unten zählt nicht")
	# Halten → Großansicht
	g = fresh()
	g.press(0.0, p0)
	check(g.tick(349.0) == "", "vor 350 ms kein Halten")
	check(g.tick(350.0) == "hold", "350 ms = Halten")
	check(g.tick(400.0) == "", "Halten nur einmal")
	check(g.release(500.0, p0) == "hold_release", "Loslassen ohne Zug: Großansicht bleibt")
	g = fresh()
	g.press(0.0, p0)
	g.move(200.0, p0 + Vector2(4, 3))
	check(g.tick(360.0) == "hold", "Zittern unter der Toleranz verhindert Halten nicht")
	# Halten + seitlich = umsortieren
	g = fresh()
	g.press(0.0, p0)
	g.tick(360.0)
	check(g.move(380.0, p0 + Vector2(30, 6)) == "reorder", "Halten + seitlich = umsortieren")
	check(g.release(500.0, p0 + Vector2(160, 0)) == "reorder_end", "Umsortieren endet")
	# Halten + nach oben = ausspielen
	g = fresh()
	g.press(0.0, p0)
	g.tick(360.0)
	check(g.move(380.0, p0 + Vector2(3, -30)) == "play_drag", "Halten + oben = ausspielen ziehen")
	# Halten + nach unten auf das „?“
	g = fresh()
	g.press(0.0, p0)
	g.tick(360.0)
	check(g.move(380.0, p0 + Vector2(2, 20)) == "help_drag", "Halten + unten = zum „?“")
	check(not g.help_armed, "noch nicht am „?“")
	g.move(420.0, p0 + Vector2(4, 40.0 * DP))
	check(g.help_armed, "40 dp nach unten: „?“ scharf")
	check(g.release(460.0, p0 + Vector2(4, 40.0 * DP)) == "help", "Loslassen am „?“ öffnet die Hilfe")
	g = fresh()
	g.press(0.0, p0)
	g.tick(360.0)
	g.move(380.0, p0 + Vector2(0, 30))
	check(g.release(420.0, p0 + Vector2(0, 30)) == "cancel", "zu kurz nach unten: keine Hilfe")
	g = fresh()
	g.help_dist = 16.0
	g.press(0.0, Vector2(800, 700))
	g.tick(360.0)
	g.move(380.0, Vector2(800, 717))
	check(g.help_armed, "am unteren Rand genügt ein kürzerer Zug")
	# Halten über eine ruhende Bewegung: move liefert das Halten selbst
	g = fresh()
	g.press(0.0, p0)
	check(g.move(400.0, p0 + Vector2(2, 1)) == "hold", "Halten wird auch beim Bewegen erkannt")
	# aus dem seitlichen Gleiten nach oben ausspielen (Lupe: zur Karte gleiten, dann hochwischen)
	g = fresh()
	g.press(0.0, p0)
	evs = path(g, 0.0, p0, p0 + Vector2(200, 0), 10)
	check(evs == ["horizontal"], "Gleiten")
	evs = path(g, 160.0, p0 + Vector2(200, 0), p0 + Vector2(206, -60), 6)
	check(evs.has("play_drag"), "nach dem Gleiten hochwischen = Ausspielen ziehen")
	check(g.start == p0 + Vector2(200, 0), "Schwelle zählt ab dem Umkehrpunkt")
	g = fresh()
	g.press(0.0, p0)
	evs = path(g, 0.0, p0, p0 + Vector2(300, -30), 20)
	check(not evs.has("play_drag"), "leicht schräges Gleiten bleibt Gleiten")
	g = fresh()
	g.up_from_horizontal = false
	g.press(0.0, p0)
	path(g, 0.0, p0, p0 + Vector2(200, 0), 10)
	evs = path(g, 160.0, p0 + Vector2(200, 0), p0 + Vector2(200, -80), 6)
	check(evs.is_empty(), "abschaltbar")
	print("RESULT: %d ok" % ok)
	quit(0 if failed == 0 else 1)
