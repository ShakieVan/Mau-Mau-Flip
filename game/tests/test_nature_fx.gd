extends SceneTree
# Mau-Mau Flip (Beta 1.6.12): Natur-Überraschungen, App-Kern (docs/module/natur.md Abschnitt 8.1, Aufgabe T1). Headless mit Probe-Tier
# (make_cb), eingespritzter Uhr (auto_process = false, tick) und festem Zufall, an einer echten TableView mit HandView.
#   Tabelle (29 Einträge seit 1.6.15, Felder, ruhig, vorn, Shader-Formeln), Plattform-Punkt = DirectionRing.point_at, Dauerlauf 10 h
#   (Abstände, nie zwei gleichzeitig, auch nicht mit Katze/Himmel/Necken, Wiederholungssperre, Obergrenzen, Seite, alle Zufallsereignisse),
#   Bedingungen (großer Modus, Dialog, Erwischt, Rundenende, Phasen, Regie < 2 s ruhig, reduziert, fremder Zug), Flip-Anlass,
#   Trödeln (Schnecke, Katze), Abbruch (eigener Zug, mau, Dialog, Necken, shuffle – UFO bleibt beim Ziehen –, play, Hand, Größe, großer
#   Modus, reduziert), Anker ecke_unten_rechts (Strand),
#   Tippen am echten Tisch (Stapel unter dem UFO, Ablage neben der Motte, Kopf, Biene über der Hand, freier Spatz, Leere),
#   Ebenen, Aufräumen (1000 Ereignisse), Bestand-Brücke, keine Töne/kein Netz im Quelltext, Vorführung, nature_check am Probe-Tier.

const CleanExit := preload("res://tests/clean_exit.gd")
const NatureCheck := preload("res://tests/nature_check.gd")
const NT := preload("res://scripts/ui/nature_table.gd")

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


# Probe-Tier: steht am Anker seines Eintrags (Kasten 40 × 40), merkt sich Tipp, Druck und Ereignisse
class Probe:
	extends "res://scripts/ui/nature_creature.gd"
	static var min_dur := 0.0
	var pos := Vector2.ZERO
	var reacted := 0
	var pressed := 0

	func setup(c: Dictionary) -> void:
		in_s = 0.5
		out_s = 0.5
		if min_dur > 0.0:
			dur = maxf(dur, min_dur)
		var o: Variant = c.get("ort")
		var ctr: Vector2 = c.get("center", Vector2(800, 320))
		if o is Rect2:
			pos = (o as Rect2).get_center()
		elif o is Dictionary and (o as Dictionary).has("pos"):
			pos = (o as Dictionary)["pos"]
		elif o is Dictionary and (o as Dictionary).has("deg"):
			pos = band(float((o as Dictionary)["deg"]))
		elif o is Dictionary and (o as Dictionary).has("center"):
			pos = (o as Dictionary)["center"]
		else:
			pos = ctr
		pos += Vector2(rng.randf_range(-3.0, 3.0), 0)

	func pose_at(tt: float) -> void:
		alpha = edge_fade(tt)

	func bounds() -> Rect2:
		return box(pos, Vector2(20, 20)) if alpha > 0.0 else Rect2()

	func on_tap(_p: Vector2) -> void:
		reacted += 1

	func on_press(_p: Vector2) -> void:
		pressed += 1

	func _draw() -> void:
		draw_rect(bounds(), Color(1, 0, 1, 0.5))


func probe(_id: String) -> Node2D:
	return Probe.new()


var t: TableView
var nf: NatureFx


func fresh(players := 4, turn := 1, sz := Vector2(1600, 720)) -> void:
	if t != null:
		t.queue_free()
		await process_frame
	t = NatureCheck.make_table(self, sz, players, turn)
	nf = t.nature
	nf.make_cb = probe
	nf.rng.seed = 3
	t.fun.cat_chance = 0.0
	Probe.min_dur = 0.0


func view_for(turn: int, players := 4, phase := "turn", catch: Array = []) -> Dictionary:
	var s := TableSamples.create(players, 7)
	s.turn = turn
	var v := s.view_for(0)
	v["phase"] = phase
	(v["hints"] as Dictionary)["catch"] = catch
	v["side"] = "dunkel" if t != null and t.night > 0.5 else "hell"
	return v


# Planer scharf machen: einmal aktiv werden, dann ist der Zufallsstart sofort fällig
func arm() -> void:
	nf.tick(0.5)
	nf.due = nf.now


func run_for(seconds: float, dt := 0.5, with_fun := false) -> void:
	var end := nf.now + seconds
	while nf.now < end - 1e-6:
		nf.tick(dt)
		if with_fun:
			t.fun.tick(dt)


func run() -> void:
	table_checks()
	await fresh()
	band_checks()
	await long_run()
	await condition_checks()
	await flip_checks()
	await snail_checks()
	await abort_checks()
	await tap_checks()
	await layer_checks()
	await cleanup_checks()
	await bridge_checks()
	await demo_checks()
	await probe_check()
	source_checks()
	print("RESULT: %d ok, %d failed" % [ok, fails])
	await CleanExit.finish(self, 0 if fails == 0 else 1)


# ================================================================= Tabelle

func table_checks() -> void:
	var all: Array = NT.entries()
	check(all.size() == 29, "Tabelle: 29 Einträge (%d)" % all.size())
	var ids := {}
	var keys := ["id", "seite", "zufall", "nach_flip", "troedeln", "ebene", "ort", "dauer", "ruhig", "tipp", "scheu", "fremder_zug",
		"je_partie", "je_runde", "deckt", "deckt_max_s", "bestand"]
	var places := ["himmel", "himmel_oben", "himmel_fern", "himmel_frei", "himmel_bogen", "sonne", "mond", "band_hinten", "band_schulter",
		"band_vorn_seite", "band_zum_platz", "tisch_quer", "tisch_rund", "handkarte", "stapel_oben", "ablage_ring", "aufsteigend",
		"ecke_unten_rechts"]
	var calm: Array = []
	var front: Array = []
	var rand := {"tag": 0, "nacht": 0}
	for e in all:
		var id := str(e["id"])
		check(not ids.has(id), "Tabelle: id %s eindeutig" % id)
		ids[id] = true
		for k in keys:
			check(e.has(k), "Tabelle: %s hat %s" % [id, k])
		check(str(e["seite"]) in ["tag", "nacht"] and str(e["ebene"]) in ["hinten", "mitte", "vorn"] and places.has(str(e["ort"])),
			"Tabelle: %s Seite/Ebene/Ort gültig" % id)
		var d: Array = e["dauer"]
		check(d.size() == 2 and float(d[0]) > 0.0 and float(d[1]) >= float(d[0]) and float(d[1]) <= 40.0, "Tabelle: %s Dauer %s" % [id, str(d)])
		check(float(e["zufall"]) >= 0.0 and float(e["nach_flip"]) >= 0.0 and int(e["je_partie"]) >= 0 and int(e["je_runde"]) >= 0,
			"Tabelle: %s Gewichte und Grenzen ≥ 0" % id)
		check(float(e["zufall"]) > 0.0 or float(e["nach_flip"]) > 0.0 or bool(e["troedeln"]), "Tabelle: %s hat einen Auslöser" % id)
		if bool(e["ruhig"]):
			calm.append(id)
		if str(e["ebene"]) == "vorn":
			front.append(id)
			# 1.6.15: das UFO ist nicht mehr scheu (weicht beim Antippen aus), die Biene bleibt scheu
			check(bool(e["fremder_zug"]) and (bool(e["scheu"]) or id == "ufo") and not (e["deckt"] as Array).is_empty()
				and float(e["deckt_max_s"]) > 0.0, "Tabelle: vorn %s nur im fremden Zug, scheu (außer UFO), mit deckt" % id)
		else:
			check((e["deckt"] as Array).is_empty(), "Tabelle: %s (nicht vorn) deckt nichts" % id)
		if float(e["zufall"]) > 0.0:
			rand[str(e["seite"])] = int(rand[str(e["seite"])]) + 1
	calm.sort()
	check(calm == ["mond_muetze", "polarlicht", "regenbogen", "sternbild", "wolke"], "Tabelle: ruhig genau die fünf (%s)" % str(calm))
	front.sort()
	check(front == ["biene", "ufo"], "Tabelle: vorn nur Biene und UFO (%s)" % str(front))
	check(int(rand["tag"]) >= 5 and int(rand["nacht"]) >= 5, "Tabelle: jede Seite hat Zufallseinträge (%s)" % str(rand))
	check(NT.ids("tag").size() == 14 and NT.ids("nacht").size() == 15, "Tabelle: 14 Tag, 15 Nacht")
	check(not bool(NT.entry("ufo")["scheu"]) and str(NT.entry("ufo")["tipp"]) != "" and bool(NT.entry("biene")["scheu"]),
		"Tabelle: UFO nicht scheu, mit Tipp (1.6.15); Biene scheu")
	check(bool(NT.entry("schmetterling")["bestand"]) and bool(NT.entry("sternschnuppe")["bestand"]), "Tabelle: Bestand")
	check(NT.entry("sternbild").has("form") and (NT.entry("sternbild")["form"]["punkte"] as Array).size() == 11, "Tabelle: Sternbild mit 11 Sternen")
	# JSON-Rundreise (so vergleicht test_web_contract mit natur.js)
	var rt: Variant = JSON.parse_string(JSON.stringify(NT.DATA))
	check(rt is Dictionary and (rt as Dictionary).size() == 2, "Tabelle: JSON-Rundreise")
	# gleich der Tabelle im Browser-Client (webclient/natur.js zwischen /*NATUR-DATEN*/ und /*ENDE*/; T7 prüft es in test_web_contract)
	var js := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../webclient/natur.js"))
	var a := js.find("/*NATUR-DATEN*/")
	var b := js.find("/*ENDE*/")
	if a >= 0 and b > a:
		var lite: Variant = JSON.parse_string(js.substr(a + 15, b - a - 15))
		check(lite is Dictionary and lite == rt, "Tabelle: gleich webclient/natur.js")
		if lite is Dictionary and lite != rt:
			for i in mini((lite["ereignisse"] as Array).size(), (rt["ereignisse"] as Array).size()):
				if lite["ereignisse"][i] != rt["ereignisse"][i]:
					print("  natur.js: ", JSON.stringify(lite["ereignisse"][i]), "\n  App:      ", JSON.stringify(rt["ereignisse"][i]))
	# Wiederholungssperre und Obergrenzen in pool
	var p := NT.pool("tag", false, false, {}, ["marienkaefer", "biene", "libelle", "pusteblume"])
	var pid := p.map(func(x: Array) -> String: return str(x[0]))
	check(not pid.has("biene") and not pid.has("marienkaefer") and pid.has("spatz"), "pool: die letzten 4 gesperrt")
	check(not NT.pool("tag", false, false, {"partie": {"heissluftballon": 1}}).map(func(x: Array) -> String: return str(x[0])).has("heissluftballon"),
		"pool: je_partie erschöpft")
	check(NT.pool("tag", true, false).map(func(x: Array) -> String: return str(x[0])) == ["wolke"], "pool: reduziert tagsüber nur die Wolke (Zufall)")
	check(not NT.pool("nacht", false, true).map(func(x: Array) -> String: return str(x[0])).has("ufo"), "pool: fremder Zug im eigenen Zug gesperrt")
	var fp := NT.flip_pool("nacht").map(func(x: Array) -> String: return str(x[0]))
	fp.sort()
	check(fp == ["eule", "fledermaus", "gluehwuermchen"], "flip_pool Nacht (%s)" % str(fp))
	check(NT.flip_pool("tag").map(func(x: Array) -> String: return str(x[0])) == ["regenbogen"], "flip_pool Tag: Regenbogen")
	# Sonne und Mond wie im Shader
	var f := FileAccess.open("res://assets/shaders/table_background.gdshader", FileAccess.READ)
	var src := f.get_as_text() if f != null else ""
	check(src.contains("vec2(size.x * 0.07, size.y * (0.03 + 1.05 * t))") and src.contains("vec2(size.x * 0.94, size.y * (1.12 - 1.04 * t))")
		and src.contains("moon - vec2(17.0, -12.0)") and src.contains("smoothstep(40.0, 37.5, md)"),
		"Shader: Sonnen- und Mondformel unverändert (nature_fx.gd anchors spiegelt sie)")


func band_checks() -> void:
	var ring: DirectionRing = t._ring
	var worst := 0.0
	for i in 160:
		var deg := float(i) * 360.0 / 160.0
		worst = maxf(worst, ring.point_at(deg).distance_to(NatureFx.band_point(ring.radii, deg)))
	check(worst < 0.5, "Plattform: band_point = DirectionRing.point_at (größte Abweichung %.2f px)" % worst)
	var c := t.table_center()
	var a := nf.band_world(90.0, 0.0)
	var b := nf.band_world(90.0, 1.0)
	check(b.y > a.y + 20.0 and absf(a.x - c.x) < 1.0, "Plattform: quer 0 innen, 1 außen (vorn %s → %s)" % [a, b])
	var an := nf.anchors()
	for key in ["band_hinten", "band_schulter", "band_vorn_seite"]:
		var deg := float(an[key]["deg"])
		var okr := false
		match key:
			"band_hinten":
				okr = deg >= 240.0 and deg <= 300.0
			"band_schulter":
				okr = (deg >= 200.0 and deg <= 215.0) or (deg >= 325.0 and deg <= 340.0)
			"band_vorn_seite":
				okr = (deg >= 115.0 and deg <= 160.0) or (deg >= 20.0 and deg <= 65.0)
		check(okr, "Anker %s im Bereich (%.0f°)" % [key, deg])
	var fr: Rect2 = an["himmel_frei"]
	check(fr.size == Vector2(240, 160) and not fr.intersects(NatureFx.TOP_LEFT), "Anker himmel_frei 240 × 160, nicht über den Knöpfen oben links (%s)" % fr)
	check((an["mond"]["pos"] as Vector2).is_equal_approx(Vector2(1600 * 0.94, 720 * 0.08)) and (an["sonne"]["pos"] as Vector2).is_equal_approx(Vector2(112, 21.6)),
		"Anker Sonne und Mond wie im Shader")
	var ecke: Dictionary = an["ecke_unten_rechts"]
	var mr: Rect2 = ecke["mau"]
	check((ecke["pos"] as Vector2).is_equal_approx(Vector2(1600, 720)) and mr.has_area() and mr.end.x > 1500.0 and mr.end.y > 640.0,
		"Anker ecke_unten_rechts: Ecke und Mau-Knopf (%s)" % str(mr))
	var obs := nf.obstacles()
	for key in ["hand", "stapel", "ablage", "platz", "name", "leiste", "mau", "sortieren", "rueckseiten", "stapelzahl", "oben_links"]:
		check(obs.has(key), "Schutzfläche %s vorhanden (%s)" % [key, str(obs.keys())])
	var hc := nf.hand_card()
	check(not hc.is_empty() and (hc["rect"] as Rect2).position.y < 720.0 - 20.0, "Handkarte: mittlere sichtbare Karte gefunden (%s)" % str(hc.get("rect")))


# ================================================================= Dauerlauf (10 h)

func long_run() -> void:
	await fresh(4, 1)
	var fun := t.fun
	fun.cat_chance = 0.4
	fun.rng.seed = 5
	var sim := RandomNumberGenerator.new()
	sim.seed = 9
	var sample := TableSamples.create(4, 7)
	var starts: Array = []
	var ends: Array = []
	var problems: Array[String] = []
	var st := {"game": 0, "rnd": 1}
	var per_game := {}
	var per_round := {}
	nf.started.connect(func(id: String) -> void:
		var e := NT.entry(id)
		var side := "nacht" if nf.night > 0.5 else "tag"
		var c := nf.current
		var hist: Array = (nf.history[str(e["seite"])] as Array).duplicate()
		var gk := "%d|%s" % [st["game"], id]
		var rk := "%d|%d|%s" % [st["game"], st["rnd"], id]
		per_game[gk] = int(per_game.get(gk, 0)) + 1
		per_round[rk] = int(per_round.get(rk, 0)) + 1
		starts.append({"id": id, "now": nf.now, "anlass": c.anlass, "last_end": nf.last_end, "hist": hist, "side": side,
			"seite": str(e["seite"]), "cat": fun.cat.active(), "sky": fun.sky.active() and not c.bridge,
			"necken": int(nf.lage_override.get("necken", 0)), "game": gk, "round": rk,
			"prev_reason": str(ends[-1]["grund"]) if not ends.is_empty() else ""}))
	nf.ended.connect(func(id: String) -> void:
		var last: Dictionary = nf.protocol[-1] if not nf.protocol.is_empty() else {}
		ends.append({"id": id, "now": nf.now, "grund": str(last.get("grund", ""))}))
	var total := 36000.0
	var next_view := 0.0
	var next_flip := sim.randf_range(600.0, 1200.0)
	var next_round := 1200.0
	var turn := 1
	var cats := 0
	var cat_overlap := 0
	var draws := 40
	while nf.now < total:
		if nf.now >= next_view:
			turn = (turn + 1) % 4
			sample.turn = turn
			draws -= 1
			if draws < 5:
				draws = 40
			var v := sample.view_for(0)
			v["draw_count"] = draws
			nf.lage_override["regie_leer"] = sim.randf() > 0.15
			if sim.randf() < 0.03:
				nf.lage_override["necken"] = 1
			else:
				nf.lage_override.erase("necken")
			t.apply_view(v)
			next_view = nf.now + (sim.randf_range(30.0, 50.0) if sim.randf() < 0.1 else sim.randf_range(4.0, 12.0))
		if nf.now >= next_flip:
			var to_night := nf.night < 0.5
			nf.on_event({"e": "flip", "side": "dunkel" if to_night else "hell"})
			t.night = 1.0 if to_night else 0.0
			sample.side = "dunkel" if to_night else "hell"
			next_flip = nf.now + sim.randf_range(600.0, 1200.0)
		if nf.now >= next_round:
			st["rnd"] = int(st["rnd"]) + 1
			if int(st["rnd"]) > 3:
				st["rnd"] = 1
				st["game"] = int(st["game"]) + 1
			nf.on_event({"e": "round_start", "round": st["rnd"]})
			fun.on_event({"e": "round_start", "round": st["rnd"]})
			next_round = nf.now + 1200.0
		nf.tick(0.5)
		fun.tick(0.5)
		if fun.cats_started != cats:
			cats = fun.cats_started
			if nf.current != null:
				cat_overlap += 1
	print("Dauerlauf: %d Ereignisse, %d Katzen" % [starts.size(), cats])
	check(starts.size() > 120, "Dauerlauf: genug Ereignisse in 10 h (%d)" % starts.size())
	var gaps := 0.0
	for i in range(1, starts.size()):
		gaps += float(starts[i]["now"]) - float(starts[i - 1]["now"])
	var mean := gaps / maxf(1.0, float(starts.size() - 1))
	check(mean >= 150.0 and mean <= 230.0, "Dauerlauf: mittlerer Abstand 150–230 s (%.0f s)" % mean)
	check(cats > 0 and cat_overlap == 0, "Dauerlauf: Katze kommt nie zusammen mit einem Natur-Ereignis (%d Katzen, %d gleichzeitig)" % [cats, cat_overlap])
	var seen := {}
	for s in starts:
		seen[s["id"]] = true
		if bool(s["cat"]) or bool(s["sky"]) or int(s["necken"]) > 0:
			problems.append("%s startet neben Katze/Himmel/Necken" % s["id"])
		if str(s["seite"]) != str(s["side"]):
			problems.append("%s (%s) auf der Seite %s" % [s["id"], s["seite"], s["side"]])
		var gap := float(s["now"]) - float(s["last_end"])
		if s["anlass"] == "zufall" and gap < 100.0 - 1e-6:
			problems.append("%s zufällig %.1f s nach dem letzten Ende" % [s["id"], gap])
		if (s["anlass"] == "flip" or s["anlass"] == "troedeln") and gap < 25.0 - 1e-6 and s["prev_reason"] != "schnecke":
			problems.append("%s (%s) %.1f s nach dem letzten Ende" % [s["id"], s["anlass"], gap])
		if s["anlass"] == "zufall":
			var hist: Array = s["hist"]
			if hist.slice(maxi(0, hist.size() - 4)).has(s["id"]):
				problems.append("%s wiederholt (letzte %s)" % [s["id"], str(hist.slice(maxi(0, hist.size() - 4)))])
		var e := NT.entry(str(s["id"]))
		if int(e["je_partie"]) > 0 and int(per_game[s["game"]]) > int(e["je_partie"]):
			problems.append("%s öfter als je_partie" % s["id"])
		if int(e["je_runde"]) > 0 and int(per_round[s["round"]]) > int(e["je_runde"]):
			problems.append("%s öfter als je_runde" % s["id"])
	check(problems.is_empty(), "Dauerlauf: Regeln eingehalten (%d Funde, z. B. %s)" % [problems.size(), str(problems.slice(0, 4))])
	var missing: Array = []
	for e in NT.entries():
		if float(e["zufall"]) > 0.0 and not seen.has(str(e["id"])):
			missing.append(str(e["id"]))
	check(missing.is_empty(), "Dauerlauf: jedes Zufallsereignis kommt vor (fehlt: %s)" % str(missing))
	check(seen.has("regenbogen") or seen.has("schnecke"), "Dauerlauf: Anlässe kommen vor (Regenbogen/Schnecke)")
	check(fun.sky_started == 0, "Dauerlauf: FunFx würfelt keinen eigenen Himmel mehr (%d)" % fun.sky_started)
	var max_log := 0
	for s in starts:
		max_log = maxi(max_log, 1)
	check(nf.protocol.size() > 0, "Dauerlauf: Protokoll geführt")


# ================================================================= Bedingungen

func starts_within(seconds: float) -> bool:
	var before := nf.protocol.filter(func(z: Dictionary) -> bool: return z["was"] == "start").size()
	var end := nf.now + seconds
	while nf.now < end:
		nf.due = minf(nf.due, nf.now)
		nf.tick(0.5)
	return nf.protocol.filter(func(z: Dictionary) -> bool: return z["was"] == "start").size() > before


func condition_checks() -> void:
	await fresh(4, 1)
	arm()
	nf.tick(0.5)
	check(nf.current != null and nf.current.anlass == "zufall", "Bedingungen: in Ruhe startet ein fälliges Ereignis")
	# großer Modus
	await fresh(4, 1)
	arm()
	t.set_big(true)
	check(not starts_within(60.0), "Bedingungen: nichts im großen Modus")
	t.set_big(false)
	# Dialog (modal_cb)
	await fresh(4, 1)
	t.tease.modal_cb = func() -> bool: return true
	arm()
	check(not starts_within(60.0), "Bedingungen: nichts bei offenem Dialog (modal_cb)")
	t.tease.modal_cb = Callable()
	check(starts_within(10.0), "Bedingungen: nach dem Dialog geht es weiter")
	# Erwischt-Fenster
	await fresh(4, 1)
	t.apply_view(view_for(1, 4, "turn", [2]))
	arm()
	check(not starts_within(60.0), "Bedingungen: nichts im Erwischt-Fenster")
	# Phasen
	for ph in ["round_over", "color", "gamble", "discard_pick", "challenge", "game_over"]:
		await fresh(4, 1)
		t.apply_view(view_for(1, 4, ph))
		arm()
		check(not starts_within(30.0), "Bedingungen: nichts in Phase %s" % ph)
	await fresh(4, 1)
	t.apply_view(view_for(1, 4, "drawn"))
	arm()
	check(starts_within(5.0), "Bedingungen: Phase drawn erlaubt")
	# Regie erst seit < 2 s ruhig
	await fresh(4, 1)
	arm()
	nf.lage_override["regie_leer"] = false
	nf.tick(0.5)
	var busy_at := nf.now
	nf.lage_override["regie_leer"] = true
	nf.due = nf.now
	nf.tick(0.5)
	check(nf.current == null, "Bedingungen: Regie erst 0,5 s ruhig – noch nichts")
	var guard := 0
	while nf.current == null and guard < 100:
		nf.tick(0.5)
		guard += 1
	check(nf.current != null and float(nf.protocol[-1]["now"]) >= busy_at + 2.0, "Bedingungen: Start frühestens 2 s nach der Regie")
	# reduziert: nur die ruhigen, Abstände doppelt
	await fresh(4, 1)
	t.reduced = true
	arm()
	var ids := {}
	var rs := {"last_end": -1.0, "short": 0}
	nf.ended.connect(func(_id: String) -> void: rs["last_end"] = nf.now)
	nf.started.connect(func(id: String) -> void:
		ids[id] = true
		if float(rs["last_end"]) >= 0.0 and nf.now - float(rs["last_end"]) < 200.0:
			rs["short"] = int(rs["short"]) + 1)
	for i in 30:
		t.night = 1.0 if i % 2 == 1 else 0.0
		run_for(600.0)
	var non_calm := ids.keys().filter(func(id: String) -> bool: return not bool(NT.entry(id)["ruhig"]))
	check(not ids.is_empty() and non_calm.is_empty(), "reduziert: nur ruhige Einträge (%s)" % str(ids.keys()))
	check(int(rs["short"]) == 0, "reduziert: Abstände doppelt (≥ 200 s ab Ende, %d kürzer)" % int(rs["short"]))
	t.reduced = false
	# fremder Zug: im eigenen Zug nie Biene, UFO, Motte
	await fresh(4, 0)
	var fz := {"n": 0}
	nf.started.connect(func(id: String) -> void:
		if bool(NT.entry(id)["fremder_zug"]):
			fz["n"] = int(fz["n"]) + 1)
	arm()
	for i in 24:
		t.night = 1.0 if i % 2 == 1 else 0.0
		var v := view_for(0)
		v["draw_count"] = 30 + i
		t.apply_view(v)
		run_for(600.0)
	check(int(fz["n"]) == 0, "fremder Zug: im eigenen Zug nie Biene/UFO/Motte (%d)" % int(fz["n"]))


# ================================================================= Flip

func flip_checks() -> void:
	# Tagereignis geht beim Flip in ≤ 0,4 s
	await fresh(4, 1)
	arm()
	nf.tick(0.5)
	var c := nf.current
	check(c != null and str(c.e["seite"]) == "tag", "Flip: Tagereignis läuft")
	nf.on_event({"e": "flip", "side": "dunkel"})
	check(c.leaving(), "Flip: Tagereignis geht sofort")
	nf.tick(0.45)
	check(nf.current == null, "Flip: nach ≤ 0,4 s weg")
	# Anlass nach Ruhe + 1,5 s, gewichtet Glühwürmchen/Fledermaus/Eule, verfällt nach 6 s
	var hits := 0
	var bad := 0
	for s in 40:
		await fresh(4, 1)
		nf.rng.seed = 100 + s
		nf.tick(0.5)
		nf.due = INF
		t.night = 1.0
		nf.on_event({"e": "flip", "side": "dunkel"})
		var at := nf.now
		run_for(8.0)
		var fl := nf.protocol.filter(func(z: Dictionary) -> bool: return z["was"] == "start" and z["anlass"] == "flip")
		if not fl.is_empty():
			hits += 1
			var dt := float(fl[0]["now"]) - at
			if dt < 1.5 - 1e-6 or dt > 6.0 or not (str(fl[0]["id"]) in ["gluehwuermchen", "fledermaus", "eule"]):
				bad += 1
	check(hits >= 8 and hits <= 26 and bad == 0, "Flip-Anlass: etwa 40 %% (%d von 40), 1,5–6 s nach dem Flip, Nachtauswahl (%d falsch)" % [hits, bad])
	# verfällt, wenn 6 s keine Ruhe ist
	var late := 0
	for s in 20:
		await fresh(4, 1)
		nf.rng.seed = 100 + s
		nf.tick(0.5)
		nf.due = INF
		t.night = 1.0
		nf.on_event({"e": "flip", "side": "dunkel"})
		nf.lage_override["regie_leer"] = false
		run_for(6.5)
		nf.lage_override.erase("regie_leer")
		run_for(10.0)
		if not nf.protocol.filter(func(z: Dictionary) -> bool: return z["was"] == "start" and z["anlass"] == "flip").is_empty():
			late += 1
	check(late == 0, "Flip-Anlass verfällt nach 6 s (%d)" % late)
	# Regenbogen höchstens einmal je Runde
	await fresh(4, 1)
	nf.tick(0.5)
	nf.due = INF
	var rb := {"n": 0}
	nf.started.connect(func(id: String) -> void:
		if id == "regenbogen":
			rb["n"] = int(rb["n"]) + 1)
	for i in 30:
		t.night = 1.0
		nf.on_event({"e": "flip", "side": "dunkel"})
		run_for(30.0)
		t.night = 0.0
		nf.on_event({"e": "flip", "side": "hell"})
		run_for(30.0)
	check(int(rb["n"]) == 1, "Regenbogen: höchstens einmal je Runde (%d)" % int(rb["n"]))
	nf.on_event({"e": "round_start", "round": 2})
	for i in 30:
		t.night = 1.0
		nf.on_event({"e": "flip", "side": "dunkel"})
		run_for(30.0)
		t.night = 0.0
		nf.on_event({"e": "flip", "side": "hell"})
		run_for(30.0)
	check(int(rb["n"]) == 2, "Regenbogen: in der nächsten Runde wieder möglich (%d)" % int(rb["n"]))


# ================================================================= Trödeln

func snail_checks() -> void:
	var found := 0
	var early := 0
	var again := 0
	for s in 20:
		await fresh(4, 2)
		nf.rng.seed = 200 + s
		nf.tick(0.5)
		nf.due = INF
		var since := float(nf.troedel["since"])
		run_for(40.0)
		var sn := nf.protocol.filter(func(z: Dictionary) -> bool: return z["was"] == "start" and z["id"] == "schnecke")
		if sn.is_empty():
			continue
		found += 1
		if float(sn[0]["now"]) - since < 35.0:
			early += 1
		check(nf.current != null and nf.current.id == "schnecke" and nf.current.anlass == "troedeln", "Schnecke läuft beim Trödler")
		check(int(nf.current.node.ctx["troedler"]) == 2, "Schnecke: Ziel ist der Trödler")
		var v := view_for(3)
		t.apply_view(v)
		nf.tick(0.5)
		check(nf.current == null or nf.current.leaving(), "Schnecke: geht beim Zugende")
		run_for(30.0)
		# derselbe Spieler trödelt noch einmal: nicht in dieser Partie
		for k in 6:
			var v2 := view_for(2)
			v2["draw_count"] = 20 + k
			t.apply_view(v2)
			run_for(45.0)
		if nf.protocol.filter(func(z: Dictionary) -> bool: return z["was"] == "start" and z["id"] == "schnecke").size() > 1:
			again += 1
	check(found >= 3 and early == 0, "Schnecke: ab 35 s mit Chance (%d von 20, %d zu früh)" % [found, early])
	check(again == 0, "Schnecke: höchstens einmal je Spieler und Partie (%d)" % again)
	# nicht im Zug der Katze
	var with_cat := 0
	var cats := 0
	for s in 12:
		await fresh(4, 2)
		t.fun.cat_chance = 1.0
		nf.rng.seed = 300 + s
		nf.tick(0.5)
		nf.due = INF
		run_for(45.0, 0.5, true)
		cats += t.fun.cats_started
		if not nf.protocol.filter(func(z: Dictionary) -> bool: return z["was"] == "start" and z["id"] == "schnecke").is_empty():
			with_cat += 1
	check(cats == 12 and with_cat == 0, "Schnecke: nie im Zug der Katze (%d Katzen, %d Schnecken)" % [cats, with_cat])
	# die Katze verdrängt ein laufendes Ereignis und kommt danach
	await fresh(4, 2)
	t.fun.cat_chance = 1.0
	Probe.min_dur = 30.0
	nf.tick(0.5)
	nf.due = INF
	run_for(20.0, 0.5, true)
	nf.due = nf.now
	run_for(1.0, 0.5, true)
	check(nf.current != null and t.fun.cats_started == 0, "Katze: Natur-Ereignis läuft vor der Katze")
	var displaced := false
	var overlap := false
	var guard := 0
	while t.fun.cats_started == 0 and guard < 80:
		nf.tick(0.1)
		t.fun.tick(0.1)
		if nf.current != null and nf.current.leaving() and nf.current.reason == "katze":
			displaced = true
		if t.fun.cats_started > 0 and nf.current != null:
			overlap = true
		guard += 1
	check(displaced and t.fun.cats_started == 1 and not overlap, "Katze: verdrängt das Ereignis (make_room) und kommt danach")
	Probe.min_dur = 0.0


# ================================================================= Abbruch

func spawned(id: String, turn := 1) -> NatureCreature:
	nf.spawn(id, 5)
	nf.tick(0.0)
	return nf.creature() as NatureCreature


func abort_checks() -> void:
	await fresh(4, 1)
	var b := spawned("biene")
	t.apply_view(view_for(0))
	nf.tick(0.5)
	check(b.leaving() or nf.current == null, "Abbruch: Biene geht, wenn der eigene Zug beginnt")
	for ev in ["mau", "catch", "finish"]:
		await fresh(4, 1)
		b = spawned("biene")
		nf.on_event({"e": ev, "seat": 2})
		check(b.leaving(), "Abbruch: vorn geht bei %s" % ev)
	await fresh(4, 1)
	var u := spawned("ufo")
	nf.on_event({"e": "draw", "seat": 2, "count": 1})
	check(not u.leaving() and nf.current != null, "Abbruch: UFO bleibt bei draw (1.6.15)")
	nf.on_event({"e": "shuffle"})
	check(u.leaving(), "Abbruch: UFO geht bei shuffle")
	await fresh(4, 1)
	u = spawned("ufo")
	nf.notice_press(nf.world_bounds().get_center() + Vector2(60, 0))
	nf.notice_press(t.draw_pile_position())
	check(not u.leaving() and int(u.get("pressed")) == 0, "Abbruch: UFO nicht scheu (Druck daneben und auf den Stapel, 1.6.15)")
	await fresh(4, 1)
	var m := spawned("motte")
	nf.on_event({"e": "play", "seat": 2})
	check(m.leaving(), "Abbruch: Motte geht bei play")
	await fresh(4, 1)
	m = spawned("motte")
	nf.on_event({"e": "mau", "seat": 2})
	check(m.leaving(), "Abbruch: Motte (fremder Zug) geht bei mau")
	await fresh(4, 1)
	b = spawned("biene")
	nf.on_event({"e": "play", "seat": 0})
	check(b.leaving(), "Abbruch: Biene geht, wenn eine Karte die eigene Hand verlässt")
	await fresh(4, 1)
	u = spawned("ufo")
	nf.lage_override["dialog"] = true
	nf.tick(0.5)
	check(u.leaving() or nf.current == null, "Abbruch: vorn geht bei offenem Dialog")
	await fresh(4, 1)
	var s := spawned("spatz")
	nf.lage_override["dialog"] = true
	nf.tick(0.5)
	check(nf.current != null and not s.leaving(), "Abbruch: mitte läuft hinter dem Dialog weiter")
	await fresh(4, 1)
	b = spawned("biene")
	nf.tick(0.5)
	nf.lage_override["necken"] = 1
	nf.tick(0.5)
	check(b.leaving() or nf.current == null, "Abbruch: vorn geht, wenn ein Necken-Effekt beginnt")
	await fresh(4, 1)
	b = spawned("biene")
	nf.lage_override["hand_beruehrt"] = true
	nf.tick(0.5)
	check(b.leaving() or nf.current == null, "Abbruch: Biene geht bei Handberührung")
	await fresh(4, 1)
	b = spawned("biene")
	t.hand.call("select", t.hand.call("get_order")[0])
	nf.tick(0.5)
	check(b.leaving() or nf.current == null, "Abbruch: Biene geht bei Auswahl in der Hand")
	await fresh(4, 1)
	s = spawned("spatz")
	NatureCheck.resize(t, Vector2(1600, 900))
	check(nf.current == null, "Abbruch: neue Tischgröße entfernt sofort")
	await fresh(4, 1)
	s = spawned("spatz")
	t.set_big(true)
	check(nf.current == null, "Abbruch: großer Modus entfernt sofort")
	t.set_big(false)
	await fresh(4, 1)
	s = spawned("spatz")
	t.reduced = true
	check(nf.current == null, "Abbruch: reduziert entfernt nicht ruhige sofort")
	var w := spawned("wolke")
	nf.tick(0.5)
	check(nf.current != null and not w.leaving() and bool(w.calm), "reduziert: Wolke bleibt (ruhige Variante)")
	t.reduced = false
	for ev in ["round_over", "game_over", "round_start", "deal", "seats"]:
		await fresh(4, 1)
		s = spawned("spatz")
		nf.on_event({"e": ev, "round": 2})
		check(s.leaving(), "Abbruch: alle gehen bei %s" % ev)
	# Seite wechselt über night
	await fresh(4, 1)
	arm()
	nf.tick(0.5)
	var c := nf.current
	t.night = 1.0
	nf.tick(0.5)
	check(c != null and (c.leaving() or nf.current == null), "Abbruch: Tagereignis geht, wenn night über 0,5 steigt")
	t.night = 0.0


# ================================================================= Tippen am echten Tisch

class FakeSource:
	extends TableSource
	var sent: Array = []

	func mode() -> String:
		return "client"

	func local_seat() -> int:
		return 0

	func current_view() -> Dictionary:
		return {}

	func send_fx(req: Dictionary) -> void:
		sent.append(req)


func tap_checks() -> void:
	await fresh(4, 0)
	var actions: Array = []
	t.action.connect(func(a: Dictionary) -> void: actions.append(a))
	# Stapel unter dem UFO → draw
	var pile := t.draw_pile_position()
	var u := spawned("ufo")
	check(not nf.tap(pile), "Tippen: Stapel ist Schutzfläche (UFO nimmt nichts)")
	check(t._tap(pile) and actions.size() == 1 and actions[0]["a"] == "draw", "Tippen: Stapel unter dem UFO zieht (%s)" % str(actions))
	# Ablage neben der Motte: wirkt wie ohne Motte
	await fresh(4, 1)
	var dp := t.discard_position()
	nf.clear()
	var without := t._tap(dp)
	var open0 := t.discard_browser.is_open()
	t.discard_browser.close_now()
	spawned("motte")
	check(not nf.tap(dp) and t._tap(dp) == without and t.discard_browser.is_open() == open0, "Tippen: Ablage neben der Motte wirkt wie sonst")
	# Kopf → Necken-Menü (auch mit Tier daneben)
	await fresh(4, 1)
	var src := FakeSource.new()
	root.add_child(src)
	t.tease.attach(src)
	var head: Vector2 = t.get_global_transform().affine_inverse() * t.seat_node(2).avatar_global()
	spawned("spatz")
	check(t._tap(head) and t.tease.menu != null, "Tippen: Kopf öffnet das Necken-Menü (Spatz am Tisch)")
	t.tease.close_menu(false)
	src.queue_free()
	# Biene über der Hand: Druck auf die Hand → Biene geht, Hand reagiert weiter
	await fresh(4, 1)
	var b := spawned("biene")
	var hc := nf.hand_card()
	var hp: Vector2 = (hc["xf"] as Transform2D) * Vector2(0, -float((hc["size"] as Vector2).y) * 0.4)
	b.set("pos", hp)
	nf.seek(2.0)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = hp
	t._gui_input(e)
	check(b.leaving() and int(b.get("pressed")) == 1, "Tippen: Biene geht bei Druck auf die Hand (scheu)")
	var hl: Vector2 = (t.hand as Node2D).to_local(t._world.get_global_transform() * hp)
	var took := bool(t.hand.call("touch_down", hl))
	t.hand.call("touch_up", hl)
	check(took, "Tippen: die Hand bekommt den Tipp unter der Biene")
	# freier Spatz → Reaktion, keine Aktion
	await fresh(4, 1)
	actions.clear()
	t.action.connect(func(a: Dictionary) -> void: actions.append(a))
	var s := spawned("spatz")
	nf.seek(2.0)
	var sp := nf.world_bounds().get_center()
	var blocked := false
	var obs := nf.obstacles()
	for key in obs:
		for r in obs[key]:
			blocked = blocked or (r as Rect2).has_point(sp)
	check(not blocked, "Tippen: Spatz sitzt frei (%s)" % sp)
	check(t._tap(sp) and actions.is_empty() and int(s.get("reacted")) == 1, "Tippen: freier Spatz reagiert, keine Spielaktion")
	check(not t._tap(sp), "Tippen: höchstens eine Reaktion je Ereignis")
	nf.clear()
	check(not t._tap(sp) and actions.is_empty(), "Tippen: ohne Tier ins Leere wie bisher (false)")


# ================================================================= Ebenen, Aufräumen, Bestand, Vorführung

func layer_checks() -> void:
	await fresh(4, 1)
	var h: Node2D = nf.layers["hinten"]
	var m: Node2D = nf.layers["mitte"]
	var v: Node2D = nf.layers["vorn"]
	check(h.get_parent() == t and h.get_index() == t._bg.get_index() + 1, "Ebenen: hinten direkt nach dem Hintergrund")
	check(t.fun.sky.get_index() > h.get_index() and t._world.get_index() > h.get_index(), "Ebenen: hinten unter Welt und FunHimmel")
	check(m.get_parent() == t._world and m.get_index() == t._ring.get_index() + 1, "Ebenen: mitte direkt nach der Plattform")
	check(m.get_index() < t._seat_layer.get_index() and m.get_index() < t._pile.get_index() and m.get_index() < t.hand_layer.get_index(),
		"Ebenen: mitte unter Plätzen, Stapel, Hand")
	check(v.get_parent() == t._world and v.get_index() == t.hand_layer.get_index() + 1 and v.get_index() < t.fx.get_index(),
		"Ebenen: vorn direkt über der Hand, unter fx")
	check(t._ui.get_index() > t._world.get_index() and t._catch_layer.get_index() > t._world.get_index(), "Ebenen: Hinweisleiste, Knöpfe, Erwischt darüber")
	for id in ["spatz", "biene", "wolke"]:
		nf.spawn(id, 1)
		check(nf.creature().get_parent() == nf.layers[NT.entry(id)["ebene"]], "Ebenen: %s in %s" % [id, NT.entry(id)["ebene"]])
	nf.clear()


func cleanup_checks() -> void:
	await fresh(4, 1)
	await process_frame
	var before := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	var ids := NT.ids().filter(func(id: String) -> bool: return not bool(NT.entry(id)["bestand"]))
	for i in 1000:
		nf.spawn(str(ids[i % ids.size()]), i)
		var c := nf.creature()
		nf.seek(float(c.get("dur")) + 1.0)
		nf.tick(0.0)
	var left := 0
	for k in nf.layers:
		left += (nf.layers[k] as Node).get_child_count()
	check(left == 0 and nf.current == null, "Aufräumen: nach 1000 Ereignissen keine Knoten übrig (%d)" % left)
	await process_frame
	await process_frame
	var after := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	check(after <= before + 1, "Aufräumen: keine verwaisten Knoten (%d → %d)" % [before, after])


func bridge_checks() -> void:
	await fresh(4, 1)
	var fun := t.fun
	check(not fun.sky_auto and fun.nature == nf, "Bestand: FunFx übergibt den Himmel an NatureFx")
	nf.spawn("schmetterling", 4)
	check(fun.sky.active() and fun.sky.kind == "butterfly" and nf.creature() == null and nf.current.bridge, "Bestand: Schmetterling über fun.sky")
	var guard := 0
	while nf.current != null and guard < 200:
		fun.tick(0.1)
		nf.tick(0.1)
		guard += 1
	check(nf.current == null and not fun.sky.active(), "Bestand: Ende mit dem Schmetterling")
	t.night = 1.0
	nf.spawn("sternschnuppe", 4)
	check(fun.sky.kind == "star" and bool(fun.sky.star.get("running")), "Bestand: Sternschnuppe (shooting_star_fx.gd)")
	nf.on_event({"e": "round_over"})
	check(nf.current == null and not fun.sky.active(), "Bestand: Abbruch stoppt den Himmel")
	t.night = 0.0
	fun.on_view(view_for(1))
	for i in 600:
		fun.tick(1.0)
	check(fun.sky_started == 0 and not fun.sky.active(), "Bestand: FunFx startet selbst keinen Himmel (sky_auto aus)")
	# ohne NatureFx bleibt FunFx wie bisher (test_fun_fx)
	var f := FunFx.new()
	check(f.sky_auto and f.nature == null, "Bestand: FunFx ohne Natur unverändert")
	f.free()


func demo_checks() -> void:
	await fresh(4, 1)
	nf.tick(0.5)
	nf.due = INF
	var p := Vector2.INF                      # freie Stelle am Himmel (keine Schutzfläche, 30 px Rand)
	var obs := nf.obstacles()
	for cand in [Vector2(800, 40), Vector2(450, 50), Vector2(1150, 50), Vector2(600, 150), Vector2(1000, 150), Vector2(400, 200)]:
		var free := true
		for key in obs:
			for r in obs[key]:
				free = free and not (r as Rect2).grow(30.0).has_point(cand)
		if free:
			p = cand
			break
	check(p != Vector2.INF, "Vorführung: freie Stelle am Himmel gefunden")
	for i in 7:
		check(not t._tap(p + Vector2(i * 3, 0)), "Vorführung: Tipp ins Leere bleibt unverbraucht")
		nf.tick(0.2)
	check(nf.demo, "Vorführung: 7 Tipps in 4 s schalten sie ein")
	nf.tick(0.5)
	var first := nf.current.id if nf.current != null else ""
	check(first == "marienkaefer", "Vorführung: beginnt mit dem ersten Tagereignis (%s)" % first)
	run_for(13.0)
	var second := nf.current.id if nf.current != null else ""
	check(second == "biene", "Vorführung: alle 12 s das nächste (%s)" % second)
	for i in 7:
		nf.tap(p)
		nf.tick(0.1)
	check(not nf.demo, "Vorführung: 7 Tipps schalten sie wieder aus")
	nf.set_demo(true)
	t.visible = false
	nf.tick(0.5)
	check(not nf.demo, "Vorführung: Tisch verlassen schaltet sie aus")
	t.visible = true


func probe_check() -> void:
	await fresh(4, 1)
	var errs := NatureCheck.check_creature(nf, "spatz", [Vector2(1600, 720), Vector2(1600, 900)], [2, 4])
	check(errs.is_empty(), "nature_check: Probe-Tier besteht (%s)" % str(errs.slice(0, 3)))
	check(NatureCheck.check_creature(nf, "schmetterling").is_empty(), "nature_check: Bestand ohne Prüfung")


func source_checks() -> void:
	var bad: Array = []
	for path in ["res://scripts/ui/nature_fx.gd", "res://scripts/ui/nature_creature.gd", "res://scripts/ui/nature_table.gd",
			"res://scripts/ui/nature_day.gd", "res://scripts/ui/nature_night.gd"]:
		if not FileAccess.file_exists(path):
			continue
		var src := FileAccess.get_file_as_string(path)
		for word in ["AppSound", "UiApp.sound", "UiApp.vibrate", "vibrate(", "send(", "fetch(", "WebSocket", "http"]:
			if src.contains(word):
				bad.append("%s: %s" % [path.get_file(), word])
	check(bad.is_empty(), "Quelltext: kein Ton, keine Vibration, kein Netz (%s)" % str(bad))
