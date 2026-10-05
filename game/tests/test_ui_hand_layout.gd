extends SceneTree
# Modul F1a: reine Rechnungen der Hand (HandLayout): Stufenwahl mit Hysterese, Fischauge, Fächer, Lupe, Bogen-Karussell
# (alle Karten sichtbar, stetig beim Scrollen), Gruppenlücken, Streifen-Index, Schwung-Projektion, Einrasten, Gummiband,
# Federn (kritisch gedämpft ohne Überschwingen, stabil bei großem Schritt) und Geschwindigkeit aus Touchproben.
# Aufruf: tools/godot_run.ps1 -Script res://tests/test_ui_hand_layout.gd -Headless
const W := 1100.0
const H := 220.0
var ok := 0
var failed := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		ok += 1
	else:
		failed += 1
		print("FAIL: ", msg)


func near(a: float, b: float, eps := 0.01) -> bool:
	return absf(a - b) <= eps


func _init() -> void:
	var M := HandLayout.Mode
	# Stufenwahl
	for n in range(0, 8):
		check(HandLayout.choose_mode(n, M.FAN) == M.FAN, "Fächer bei %d" % n)
	for n in range(8, 16):
		check(HandLayout.choose_mode(n, M.LENS) == M.LENS, "Lupe bei %d" % n)
	check(HandLayout.choose_mode(16, M.LENS) == M.CAROUSEL, "Karussell ab 16")
	check(HandLayout.choose_mode(15, M.CAROUSEL) == M.CAROUSEL, "Hysterese 15 bleibt Karussell")
	check(HandLayout.choose_mode(14, M.CAROUSEL) == M.CAROUSEL, "Hysterese 14 bleibt Karussell")
	check(HandLayout.choose_mode(13, M.CAROUSEL) == M.LENS, "zurück zur Lupe bei 13")
	check(HandLayout.choose_mode(6, M.CAROUSEL) == M.FAN, "Karussell → Fächer bei 6")
	check(HandLayout.choose_mode(15, M.LENS) == M.LENS, "15 aus der Lupe bleibt Lupe")
	# Fischauge und Stammfunktion
	check(near(HandLayout.fisheye(0.0), HandLayout.FISH_S_MAX), "Fischauge Mitte = s_max")
	check(near(HandLayout.fisheye(20.0), HandLayout.FISH_S_MIN, 0.001), "Fischauge Rand = s_min")
	check(near(HandLayout.fisheye(1.7), HandLayout.fisheye(-1.7)), "Fischauge symmetrisch")
	var deriv_ok := true
	for d in [-6.0, -2.5, -0.4, 0.0, 1.0, 3.3, 8.0]:
		var num := (HandLayout.fisheye_offset(d + 0.001) - HandLayout.fisheye_offset(d - 0.001)) / 0.002
		if not near(num, HandLayout.fisheye(d), 0.05):
			deriv_ok = false
	check(deriv_ok, "Stammfunktion des Fischauges")
	check(near(HandLayout.erf(0.0), 0.0, 1e-6) and near(HandLayout.erf(1.0), 0.8427008, 1e-5) and near(HandLayout.erf(-2.0), -0.9953223, 1e-5), "erf")
	# Fächer mit 5 Karten
	var cw := HandLayout.card_width(H)
	check(near(cw, 189.2, 0.1), "Kartenbreite wie im Entwurf (190 px)")
	var fan := HandLayout.layout(5, 0.0, -1.0, M.FAN, W, H)
	check(fan.size() == 5, "5 Transforms")
	check(near(fan[2].origin.x, W * 0.5) and near(fan[2].get_rotation(), 0.0), "Fächer: mittlere Karte mittig und gerade")
	check(near(fan[0].origin.x + fan[4].origin.x, W, 0.01) and near(fan[0].get_rotation(), -fan[4].get_rotation()), "Fächer symmetrisch")
	check(fan[0].get_rotation() < 0.0 and fan[0].origin.y > fan[2].origin.y, "Fächer: Bogen (links nach links geneigt, abgesenkt)")
	check(near(fan[2].origin.y, H), "Kartenmitte ruht auf der Unterkante (obere Hälfte sichtbar)")
	var step := fan[1].origin.x - fan[0].origin.x
	check(step >= HandLayout.FAN_STEP_MIN - 1.0, "Fächer: Abstand ≥ 48 dp (%.1f)" % step)
	var fan7 := HandLayout.layout(7, 0.0, -1.0, M.FAN, W, H)
	check(absf(fan7[0].get_rotation()) <= deg_to_rad(12.0) + 1e-4, "Fächer: Drehung höchstens 12°")
	check(fan7[1].origin.x - fan7[0].origin.x >= HandLayout.FAN_STEP_MIN - 1.0, "Fächer 7: jede Karte antippbar")
	check(fan7[6].origin.x + cw * 0.5 <= W + 1.0 and fan7[0].origin.x - cw * 0.5 >= -1.0, "Fächer 7 passt in den Bereich")
	# Lupe mit 12 Karten
	var lens := HandLayout.layout(12, 0.0, -1.0, M.LENS, W, H)
	check(lens[11].origin.x + cw * 0.5 <= W + 1.0 and lens[0].origin.x - cw * 0.5 >= -1.0, "Lupe 12 passt in den Bereich")
	var lf := HandLayout.layout(12, 0.0, 5.0, M.LENS, W, H)
	check(lf[5].origin.y < lens[5].origin.y - HandLayout.LENS_LIFT * 0.9, "Lupe hebt die Karte unter dem Finger (+24 dp)")
	check(near(lf[5].get_scale().x, 1.15, 0.01), "Lupe vergrößert auf 1,15")
	check(lf[6].origin.x - lf[5].origin.x > lens[6].origin.x - lens[5].origin.x + 10.0, "Nachbarn weichen aus")
	check(lf[11].origin.x + cw * 0.5 <= W + 1.0 and lf[0].origin.x - cw * 0.5 >= -1.0, "Lupe bleibt im Bereich")
	check(lf[0].get_scale().x < 1.01 and lf[11].get_scale().x < 1.01, "Lupe wirkt nur in der Nähe")
	var mono := true
	for i in range(1, 12):
		if lf[i].origin.x <= lf[i - 1].origin.x + 4.0:
			mono = false
	check(mono, "Lupe: Reihenfolge und Streifen bleiben erhalten")
	# Lupe mit 15 Karten und Lücken
	var gaps15 := PackedInt32Array([4, 8, 12])
	var l15 := HandLayout.layout(15, 0.0, -1.0, M.LENS, W, H, gaps15)
	check(l15[14].origin.x + cw * 0.5 <= W + 1.0 and l15[0].origin.x - cw * 0.5 >= -1.0, "Lupe 15 mit Lücken passt")
	var s_in := l15[3].origin.x - l15[2].origin.x
	var s_gap := l15[4].origin.x - l15[3].origin.x
	check(near(s_gap - s_in, HandLayout.GROUP_GAP, 1.0), "Gruppenlücke 6 dp (%.1f)" % (s_gap - s_in))
	# Bogen-Karussell
	var car := HandLayout.layout(25, 12.0, -1.0, M.CAROUSEL, W, H)
	check(near(car[12].origin.x, W * 0.5) and near(car[12].get_scale().x, 1.0), "Karussell: Mitte groß und mittig")
	check(near(car[13].origin.x - car[12].origin.x, HandLayout.FISH_S_MAX, 8.0), "Karussell: Abstand in der Mitte ≈ 52 dp")
	check(car[1].origin.x - car[0].origin.x < 25.0, "Karussell: am Rand gestaucht")
	check(car[0].get_scale().x < 0.87 and car[0].origin.y > car[12].origin.y + 20.0, "Karussell: Rand kleiner und abgesenkt")
	check(near(HandLayout.shade(25, 12.0, M.CAROUSEL, 0), 0.75, 0.01) and near(HandLayout.shade(25, 12.0, M.CAROUSEL, 12), 1.0), "Karussell: Rand auf 75 % abgedunkelt")
	check(car[0].get_rotation() < -0.1 and car[24].get_rotation() > 0.1, "Karussell: Drehung folgt dem Bogen")
	for n in [16, 25, 40, 60]:
		for sc in [0.0, float(n - 1)]:
			var xs := HandLayout.layout(n, sc, -1.0, M.CAROUSEL, W, H)
			var inside := true
			var strips := true
			for i in n:
				var half := cw * xs[i].get_scale().x * 0.5
				if xs[i].origin.x - half < -2.0 or xs[i].origin.x + half > W + 2.0:
					inside = false
				if i > 0 and xs[i].origin.x - xs[i - 1].origin.x < 1.0:
					strips = false
			check(inside and strips, "Karussell %d bei scroll %d: alle Karten als Streifen sichtbar" % [n, int(sc)])
	# Stetigkeit beim Scrollen (auch über Gruppenlücken)
	var g := PackedInt32Array([5, 11, 17, 22])
	var jump := 0.0
	for k in 400:
		var s0 := k * 0.06
		var a := HandLayout.layout(25, s0, -1.0, M.CAROUSEL, W, H, g)
		var b := HandLayout.layout(25, s0 + 0.001, -1.0, M.CAROUSEL, W, H, g)
		for i in 25:
			jump = maxf(jump, a[i].origin.distance_to(b[i].origin))
	check(jump < 0.5, "Karussell stetig (größter Sprung %.3f px)" % jump)
	var cg := HandLayout.layout(25, 11.0, -1.0, M.CAROUSEL, W, H, g)
	check(near(cg[11].origin.x, W * 0.5, 0.01), "Karussell mit Lücken: Karte unter scroll mittig")
	check(cg[11].origin.x - cg[10].origin.x > cg[12].origin.x - cg[11].origin.x + 5.0, "Karussell: Lücke vor neuer Farbgruppe")
	# Streifen-Index
	var fx := HandLayout.layout(5, 0.0, -1.0, M.FAN, W, H)
	var ok_idx := true
	for i in 5:
		var left := fx[i].origin.x - cw * 0.5
		var right := fx[i + 1].origin.x - cw * 0.5 if i < 4 else fx[i].origin.x + cw * 0.5
		var f := HandLayout.index_at(5, (left + right) * 0.5, 0.0, M.FAN, W, H)
		if not near(f, float(i), 0.02):
			ok_idx = false
	check(ok_idx, "Streifenmitte ergibt den Kartenindex")
	check(near(HandLayout.index_at(5, -50.0, 0.0, M.FAN, W, H), -0.5) and near(HandLayout.index_at(5, W + 50.0, 0.0, M.FAN, W, H), 4.5), "Index außerhalb begrenzt")
	var ci := HandLayout.index_at(25, W * 0.5 - cw * 0.5 + 20.0, 12.0, M.CAROUSEL, W, H)
	check(roundi(ci) == 12, "Karussell: Index unter der Mitte")
	# Schwung, Einrasten, Gummiband
	check(near(HandLayout.project(0.0, 1000.0), 499.0, 0.5), "Projektion 0,998: v·0,499 s")
	check(near(HandLayout.project(3.0, -10.0), 3.0 - 4.99, 0.01), "Projektion rückwärts")
	check(HandLayout.snap(7.4, 25) == 7 and HandLayout.snap(7.6, 25) == 8 and HandLayout.snap(-3.0, 25) == 0 and HandLayout.snap(31.0, 25) == 24, "Einrasten auf Kartenmitte, begrenzt")
	check(near(HandLayout.rubber_band(0.0, 500.0), 0.0), "Gummiband 0")
	var rb_mono := true
	var prev := 0.0
	for k in range(1, 50):
		var x := k * 40.0
		var r := HandLayout.rubber_band(x, 500.0)
		if r <= prev or r >= x or r >= 500.0:
			rb_mono = false
		prev = r
	check(rb_mono, "Gummiband: wächst, bleibt unter Zug und Grenze d")
	check(near(HandLayout.rubber_band(100.0, 500.0), (1.0 - 1.0 / (100.0 * 0.55 / 500.0 + 1.0)) * 500.0) and near(HandLayout.rubber_band(-80.0, 500.0), -HandLayout.rubber_band(80.0, 500.0)), "Gummiband-Formel, symmetrisch")
	check(near(HandLayout.rubber_scroll(5.0, 25, 104.0, W), 5.0) and HandLayout.rubber_scroll(-2.0, 25, 104.0, W) > -2.0 and HandLayout.rubber_scroll(26.0, 25, 104.0, W) < 26.0, "Gummiband im Scrollwert nur außerhalb")
	# Federn
	var x0 := 0.0
	var v0 := 0.0
	var overshoot := false
	for k in 240:
		var r := HandLayout.spring(x0, v0, 10.0, 5.0, 1.0, 1.0 / 60.0)
		x0 = r.x
		v0 = r.y
		if x0 > 10.0 + 1e-6:
			overshoot = true
	check(not overshoot and near(x0, 10.0, 0.01), "kritisch gedämpft: erreicht das Ziel ohne Überschwingen")
	# Schwung als Startgeschwindigkeit mit ω ≥ 1/τ: kein Überschwingen über das projizierte Ziel
	var target := HandLayout.project(0.0, 8.0)
	x0 = 0.0
	v0 = 8.0
	overshoot = false
	for k in 300:
		var r := HandLayout.spring(x0, v0, target, 5.0, 1.0, 1.0 / 60.0)
		x0 = r.x
		v0 = r.y
		if x0 > target + 1e-6:
			overshoot = true
	check(not overshoot and near(x0, target, 0.01), "Einrasten nach Schwung ohne Überschwingen")
	var big := HandLayout.spring(0.0, 0.0, 1.0, 17.0, 0.8, 0.5)
	check(absf(big.x - 1.0) < 0.1 and is_finite(big.y), "Feder stabil bei großem Schritt")
	x0 = 0.0
	v0 = 0.0
	for k in 120:
		var r := HandLayout.spring(x0, v0, 1.0, 17.0, 0.8, 1.0 / 60.0)
		x0 = r.x
		v0 = r.y
	check(near(x0, 1.0, 0.001), "unterdämpfte Feder kommt zur Ruhe")
	# Geschwindigkeit aus Touchproben
	var vt := HandLayout.Velocity.new()
	for k in 30:
		vt.add(k * 10.0, Vector2(k * 10.0, -k * 5.0))
	var v := vt.get_velocity(290.0)
	check(near(v.x, 1000.0, 1.0) and near(v.y, -500.0, 1.0), "Geschwindigkeit 1000 px/s")
	vt.reset()
	vt.add(0.0, Vector2.ZERO)
	vt.add(10.0, Vector2(50, 0))
	vt.add(400.0, Vector2(50, 0))
	check(vt.get_velocity(400.0).length() < 1.0, "Finger stand still: keine Geschwindigkeit")
	print("RESULT: %d ok" % ok)
	quit(0 if failed == 0 else 1)
