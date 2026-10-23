extends SceneTree
# Mau-Mau Flip (Beta 1.6.12): Nachttiere der Natur-Überraschungen (docs/module/natur.md Abschnitt 8.1, Aufgabe T4). Headless an einer
# echten TableView (nature_check.gd, Uhren aus):
#   - nature_check für jede Nacht-id (4 Größen × 2/4/8 Spieler: Sichtbarkeit, deckt, Aufräumen, hit, leave ≤ 0,5 s, Bestimmtheit),
#   - Reaktion beim Antippen über NatureFx.tap (Zustand danach), Scheu der Motte (notice_press), Ortsereignisse,
#   - 1.6.15: UFO nicht mehr scheu (Druck daneben/auf den Stapel und draw lassen es bleiben, shuffle nicht), weicht beim 1. und 2. Tipp
#     aus, erst der 3. verscheucht es; Feuerwerk: Tipp zündet einen Knall an der Stelle (höchstens zweimal); Astronaut: Salto,
#   - ruhige Varianten (Mond mit Mütze, Polarlicht, Sternbild): keine Bewegung (Hülle und Pose über die Zeit gleich),
#   - make(id) liefert genau die Nachttiere, Quelltext ohne Ton, Vibration und Netz.
# Umgebungsvariable NUR=<id,…> prüft nur diese ids (schneller beim Nachbessern).

const CleanExit := preload("res://tests/clean_exit.gd")
const NatureCheck := preload("res://tests/nature_check.gd")
const NT := preload("res://scripts/ui/nature_table.gd")
const Night := preload("res://scripts/ui/nature_night.gd")

var ok := 0
var fails := 0
var t: TableView
var nf: NatureFx


func check(cond: bool, what: String) -> void:
	if cond:
		ok += 1
	else:
		fails += 1
		print("FAIL: " + what)


func _initialize() -> void:
	call_deferred("run")


func only() -> Array:
	var e := OS.get_environment("NUR")
	var out: Array = []
	for id in Night.ids():
		if e == "" or e.split(",").has(id):
			out.append(id)
	return out


func run() -> void:
	t = NatureCheck.make_table(self, Vector2(1600, 720), 4, 1)
	t.set_night(1.0)
	nf = t.nature
	t.fun.cat_chance = 0.0
	await process_frame
	table_checks()
	for id in only():
		var errs := NatureCheck.check_creature(nf, id)
		for e in errs:
			print("  " + e)
		check(errs.is_empty(), "nature_check %s (%d Funde)" % [id, errs.size()])
	tap_checks()
	shy_checks()
	calm_checks()
	source_checks()
	print("RESULT: %d ok, %d failed" % [ok, fails])
	await CleanExit.finish(self, 0 if fails == 0 else 1)


# ================================================================= Tabelle und make

func table_checks() -> void:
	var night_ids: Array = []
	for e in NT.entries():
		if str(e["seite"]) == "nacht" and not bool(e["bestand"]):
			night_ids.append(str(e["id"]))
	check(night_ids.size() == 14, "14 Nacht-Einträge ohne Bestand (%d)" % night_ids.size())
	for id in night_ids:
		check(Night.ids().has(id), "ids() enthält " + id)
		var n := Night.make(id)
		check(n != null and n.has_method("pose_at"), "make(%s) liefert ein Tier" % id)
		if n != null:
			n.free()
		var m := NatureFx.make(id)
		check(m != null, "NatureFx.make(%s) findet das Nachttier" % id)
		if m != null:
			m.free()
	for e in NT.entries():
		if str(e["seite"]) == "tag" or bool(e["bestand"]):
			check(Night.make(str(e["id"])) == null, "make(%s) ist kein Nachttier" % str(e["id"]))


# ================================================================= Antippen

# Weltpunkt, auf den ein Tipp das Tier trifft (Glühwürmchen: das hellste)
func tap_point(id: String) -> Vector2:
	var c := nf.creature()
	if id == "gluehwuermchen":
		var pts: Array = c.get("pts")
		var lum: Array = c.get("lum")
		var best := 0
		for i in pts.size():
			if float(lum[i]) > float(lum[best]):
				best = i
		return nf._layer_to_world("mitte") * (pts[best] as Vector2)
	if id == "ufo":
		return nf._layer_to_world("vorn") * (c.get("pos") as Vector2)
	return nf.world_bounds().get_center()


func spawn_at(id: String, sd: int, tt: float) -> NatureCreature:
	nf.spawn(id, sd)
	nf.seek(tt)
	return nf.creature() as NatureCreature


func free_of_obstacles(p: Vector2) -> bool:
	var obs := nf.obstacles()
	for key in obs:
		for r in obs[key]:
			if (r as Rect2).has_point(p):
				return false
	return true


# freier Punkt (keine Schutzfläche) in der Hülle des laufenden Tiers, (−1, −1) wenn keiner
func free_in_hull() -> Vector2:
	var b := nf.world_bounds()
	for fy in [0.5, 0.3, 0.7, 0.15, 0.85]:
		for fx in [0.5, 0.3, 0.7, 0.15, 0.85]:
			var p := b.position + b.size * Vector2(float(fx), float(fy))
			if free_of_obstacles(p):
				return p
	return Vector2(-1, -1)


# Samen suchen, bei dem das Tier zur Zeit tt an einer freien Stelle sitzt (sonst nimmt der Tisch den Tipp)
func tappable(id: String, tt: float) -> NatureCreature:
	for sd in range(1, 40):
		var c := spawn_at(id, sd, tt)
		if c != null and free_of_obstacles(tap_point(id)):
			return c
	return null


func tap_checks() -> void:
	NatureCheck.show(t, 4, 1)
	var ids := only()
	if ids.has("gluehwuermchen"):
		var c := tappable("gluehwuermchen", 6.0)
		check(c != null, "Glühwürmchen: freie Stelle zum Antippen")
		if c != null:
			var p0: Array = (c.get("pts") as Array).duplicate()
			var hit_p := nf._layer_to_world("mitte").affine_inverse() * tap_point("gluehwuermchen")
			check(nf.tap(tap_point("gluehwuermchen")), "Glühwürmchen: Tipp trifft")
			nf.seek(6.4)
			var away := 0
			var pts: Array = c.get("pts")
			for i in pts.size():
				if (pts[i] as Vector2).distance_to(hit_p) > (p0[i] as Vector2).distance_to(hit_p) + 40.0:
					away += 1
			check(away == pts.size(), "Glühwürmchen: alle stieben vom Tipp weg (%d/%d)" % [away, pts.size()])
			nf.seek(6.0 + 0.9)
			check(c.is_done(), "Glühwürmchen: nach dem Auseinanderstieben ist das Ereignis vorbei")
		# Tipp weit daneben trifft nicht
		var c2 := tappable("gluehwuermchen", 6.0)
		if c2 != null:
			var far := tap_point("gluehwuermchen") + Vector2(0, 400)
			check(not bool(c2.call("hit", nf._layer_to_world("mitte").affine_inverse() * far)), "Glühwürmchen: weit daneben kein Treffer")
	if ids.has("eule"):
		var c := tappable("eule", 7.0)
		check(c != null, "Eule: freie Stelle")
		if c != null:
			var y0 := float(c.get("yaw"))
			check(nf.tap(tap_point("eule")), "Eule: Tipp trifft")
			nf.seek(7.0 + 0.17)
			check(float(c.get("lid")) > 0.9, "Eule: blinzelt")
			nf.seek(7.0 + 0.4)
			check(absf(float(c.get("yaw")) - y0) > 2.0, "Eule: Kopf dreht fast ganz herum (%.2f)" % float(c.get("yaw")))
			nf.seek(7.0 + 1.2)
			var y_tap := float(c.get("yaw"))
			check(not c.is_done() and float(c.get("spread")) < 0.1, "Eule: bleibt sitzen")
			var sd := c.seed_value
			spawn_at("eule", sd, 7.0 + 1.2)
			check(absf(y_tap - float(nf.creature().get("yaw"))) < 0.05, "Eule: Kopf wieder wie vor dem Tipp (%.2f)" % y_tap)
			check(absf(y0) < 1.0, "Eule: Kopf vor dem Tipp vorn")
	if ids.has("mond_muetze"):
		var c := tappable("mond_muetze", 4.0)
		check(c != null, "Mond: freie Stelle")
		if c != null:
			check(float(c.get("eye_open")) < 0.1, "Mond: schläft")
			check(nf.tap(tap_point("mond_muetze")), "Mond: Tipp trifft")
			nf.seek(4.3)
			check(float(c.get("eye_open")) > 0.8, "Mond: wacht kurz auf")
			nf.seek(5.0)
			check(float(c.get("eye_open")) < 0.1, "Mond: schläft weiter")
	if ids.has("sternbild"):
		var c := tappable("sternbild", 6.0)
		check(c != null, "Sternbild: freie Stelle")
		if c != null:
			var b0 := float((c.get("star_b") as Array)[0])
			check(nf.tap(tap_point("sternbild")), "Sternbild: Tipp trifft")
			nf.seek(6.2)
			check(float((c.get("star_b") as Array)[0]) > b0 * 1.5, "Sternbild: Sterne funkeln auf")
			nf.seek(6.5)
			var q: Array = c.get("Q")
			var p: Array = c.get("P")
			check(not (q[10] as Vector2).is_equal_approx(p[10]), "Sternbild: Schwanz wackelt")
	if ids.has("ufo"):
		# 1.6.15: 1. und 2. Tipp → weicht zur Seite aus (bleibt), erst der 3. verscheucht es
		var c := tappable("ufo", 2.6)
		check(c != null, "UFO: freie Stelle über dem Stapel")
		if c != null:
			var p0 := tap_point("ufo")
			check(nf.tap(p0 + Vector2(-8, 0)), "UFO: 1. Tipp trifft")
			check(not c.leaving(), "UFO: 1. Tipp verscheucht es nicht")
			nf.seek(2.6 + 0.3)
			var p1 := tap_point("ufo")
			check(absf(p1.x - p0.x) > 35.0, "UFO: weicht zur Seite aus (%.0f px)" % (p1.x - p0.x))
			check(float(c.get("beam")) < 1.0, "UFO: Lichtkegel flackert beim Ausweichen")
			nf.seek(2.6 + 2.2)
			check(tap_point("ufo").distance_to(p0) < 12.0, "UFO: gleitet zurück über den Stapel")
			var sd := c.seed_value
			check(nf.tap(tap_point("ufo")), "UFO: 2. Tipp trifft")
			check(not c.leaving(), "UFO: 2. Tipp verscheucht es nicht")
			nf.seek(2.6 + 2.6)
			check(nf.tap(tap_point("ufo")), "UFO: 3. Tipp trifft")
			check(c.leaving(), "UFO: 3. Tipp – saust davon")
			nf.seek(2.6 + 2.6 + 0.5)
			check(c.is_done(), "UFO: nach 0,5 s weg")
			# rein in t: gleicher Samen, gleiche Tipps → gleiche Lage
			nf.spawn("ufo", sd)
			nf.seek(2.6)
			var c2 := nf.creature() as NatureCreature
			nf.tap(tap_point("ufo") + Vector2(-8, 0))
			nf.seek(2.9)
			check(tap_point("ufo").is_equal_approx(p1), "UFO: Ausweichen bestimmt (seek)")
			check(c2 != null and c2.tap_count() == 1, "UFO: Tipps gezählt")
	if ids.has("feuerwerk"):
		var c := tappable("feuerwerk", 2.2)
		check(c != null, "Feuerwerk: freie Stelle")
		if c != null:
			var n0 := (c.call("active_bursts") as Array).size()
			check(n0 >= 1, "Feuerwerk: ein Knall leuchtet (%d)" % n0)
			var p := tap_point("feuerwerk")
			var d0 := c.dur
			check(nf.tap(p), "Feuerwerk: Tipp trifft")
			nf.seek(2.2 + 0.25)
			var near := false
			for q in c.call("active_bursts"):
				near = near or (nf._layer_to_world("hinten") * (q as Vector2)).distance_to(p) < 30.0
			check(near, "Feuerwerk: neuer Knall an der Tippstelle")
			check(c.dur >= d0 and c.dur >= 2.2 + 2.0 - 0.01, "Feuerwerk: läuft lang genug für den Knall")
			nf.seek(2.6)
			var p2 := free_in_hull()
			check(p2.x >= 0.0 and nf.tap(p2), "Feuerwerk: 2. Tipp zündet noch einen")
			nf.seek(2.9)
			var p3 := free_in_hull()
			check(p3.x >= 0.0 and not nf.tap(p3), "Feuerwerk: höchstens zwei Knalle per Tipp")
			check(c.tap_count() == 2, "Feuerwerk: zwei Tipps gezählt (%d)" % c.tap_count())
	if ids.has("astronaut"):
		var c := tappable("astronaut", 5.0)
		check(c != null, "Astronaut: freie Stelle neben dem Mond")
		if c != null:
			var r0 := float(c.get("rot"))
			check(nf.tap(tap_point("astronaut")), "Astronaut: Tipp trifft")
			nf.seek(5.0 + 0.95)
			check(absf(float(c.get("rot")) - r0) > 2.0, "Astronaut: Salto (%.2f → %.2f)" % [r0, float(c.get("rot"))])
			check(float(c.get("wave")) > 0.5, "Astronaut: winkt dabei")
			nf.seek(5.0 + 2.1)
			check(not c.is_done(), "Astronaut: schwebt danach weiter")
			var mo: Vector2 = nf.anchors()["mond"]["pos"]
			check(nf.world_bounds().get_center().distance_to(mo) < 330.0, "Astronaut: schwebt neben dem Mond")
	if ids.has("igel"):
		var c := tappable("igel", 3.0)
		check(c != null, "Igel: freie Stelle")
		if c != null:
			check(nf.tap(tap_point("igel")), "Igel: Tipp trifft")
			nf.seek(3.5)
			check(float(c.get("ball")) > 0.95, "Igel: eingerollt")
			nf.seek(3.0 + 2.8)
			check(float(c.get("ball")) < 0.05 and not c.is_done(), "Igel: rollt sich aus und tippelt davon")
			nf.seek(float(c.get("dur")) + 0.05)
			check(c.is_done(), "Igel: danach fertig")
	if ids.has("lampion"):
		var c := tappable("lampion", 5.0)
		check(c != null, "Lampion: freie Stelle")
		if c != null:
			check(nf.tap(tap_point("lampion")), "Lampion: Tipp trifft")
			nf.seek(5.18)
			check(float(c.get("boost")) > 2.0, "Lampion: glüht auf")
			nf.seek(6.5)
			check(float(c.get("boost")) < 1.01, "Lampion: wieder normal")
	# Tiere ohne Reaktion nehmen den Tipp nicht
	for id in ["fledermaus", "satellit", "komet", "polarlicht", "motte"]:
		if not ids.has(id):
			continue
		var c := tappable(id, 3.0)
		if c != null:
			check(not nf.tap(tap_point(id)), "%s: kein Tipp (keine Reaktion)" % id)
	nf.clear()


# ================================================================= Scheu und Ortsereignisse

func shy_checks() -> void:
	var ids := only()
	NatureCheck.show(t, 4, 1)
	if ids.has("ufo"):
		# 1.6.15: nicht mehr scheu – Druck daneben, auf den Stapel und Ziehen lassen es bleiben; Mischen vertreibt es
		var c := spawn_at("ufo", 5, 3.0)
		nf.notice_press(nf.world_bounds().get_center() + Vector2(100, 0))
		nf.notice_press(t.draw_pile_position())
		check(not c.leaving(), "UFO: nicht scheu bei Druck in 130 px und auf den Stapel")
		nf.on_event({"e": "draw", "seat": 2, "count": 1})
		check(not c.leaving(), "UFO: bleibt bei draw")
		nf.on_event({"e": "shuffle"})
		check(c.leaving(), "UFO: geht bei shuffle")
		c = spawn_at("ufo", 5, 3.0)
		check(float(c.get("beam")) > 0.9, "UFO: Lichtkegel an")
		nf.seek(3.2)
		c.leave(true)
		nf.seek(3.3)
		check(float(c.get("beam")) == 0.0, "UFO: Kegel aus beim Abgang")
	if ids.has("motte"):
		var c := spawn_at("motte", 5, 3.0)
		nf.notice_press(nf.world_bounds().get_center() + Vector2(0, 90))
		check(c.leaving(), "Motte: scheu bei Druck in 130 px")
		c = spawn_at("motte", 5, 3.0)
		nf.on_event({"e": "play", "seat": 2})
		check(c.leaving(), "Motte: geht bei play")
		c = spawn_at("motte", 5, 3.0)
		nf.notice_press(Vector2(80, 650))
		check(not c.leaving(), "Motte: Druck weit weg stört nicht")
	nf.clear()


# ================================================================= Effekte reduziert

func calm_checks() -> void:
	var ids := only()
	NatureCheck.show(t, 4, 1)
	nf.set_reduced(true)
	for id in ["mond_muetze", "polarlicht", "sternbild"]:
		if not ids.has(id):
			continue
		nf.spawn(id, 9)
		var c := nf.creature() as NatureCreature
		check(c != null and bool(c.get("calm")), "%s: ruhige Variante" % id)
		if c == null:
			continue
		var a := float(c.get("in_s"))
		var b := float(c.get("dur")) - float(c.get("out_s"))
		check(b - a > 3.0, "%s ruhig: Hauptphase ≥ 3 s" % id)
		nf.seek(a + 0.01)
		var r0 := nf.world_bounds()
		var same := true
		var still := true
		var probe0 := _pose_sig(c, id)
		var tt := a + 0.01
		while tt < b:
			nf.seek(tt)
			var r := nf.world_bounds()
			same = same and r.position.is_equal_approx(r0.position) and r.size.is_equal_approx(r0.size)
			still = still and _pose_sig(c, id) == probe0
			tt += 0.25
		check(same, "%s ruhig: Hülle bleibt gleich" % id)
		check(still, "%s ruhig: keine Bewegung" % id)
		nf.seek(0.0)
		check(float(c.modulate.a) < 0.05, "%s ruhig: blendet ein" % id)
		nf.seek(a + 0.5)
		check(float(c.modulate.a) > 0.95, "%s ruhig: steht" % id)
	nf.clear()
	nf.set_reduced(false)


func _pose_sig(c: Node, id: String) -> String:
	match id:
		"mond_muetze":
			return "%s|%.3f|%.3f|%d|%.3f" % [str(c.get("hat_off")), float(c.get("hat_rot")), float(c.get("swing")), (c.get("zs") as Array).size(), float(c.get("eye_open"))]
		"polarlicht":
			return "%.3f" % float(c.get("u"))
		"sternbild":
			return "%s|%s" % [str(c.get("star_b")), str(c.get("line_f"))]
	return ""


# ================================================================= Quelltext

func source_checks() -> void:
	var f := FileAccess.open("res://scripts/ui/nature_night.gd", FileAccess.READ)
	check(f != null, "nature_night.gd lesbar")
	if f == null:
		return
	var src := f.get_as_text()
	for bad in ["AppSound", "vibrate", "send(", "fetch(", "WebSocket", "http", "CPUParticles2D", "load(\"res://assets"]:
		check(not src.contains(bad), "nature_night.gd ohne „%s“" % bad)
