extends SceneTree
# Schnurren und Sternenschauer, headless: Aussetzen-Ereignisse (skip, skip_all) spielen den Ton „schnurren“, Rundenende nachts
# Sterne und tagsüber Konfetti, „Effekte reduziert“ ruhig, Ton über „Spieltöne“ geregelt.

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
	await _sound_events()
	await _celebration()
	_sound_file()
	print("RESULT: %d ok" % ok)
	await CleanExit.finish(self, 0 if fails == 0 else 1)


func _table() -> TableView:
	var s := TableSamples.create(4, 5, [7, 6, 5, 3])
	var t := TableView.new()
	root.add_child(t)
	await process_frame
	t.apply_view(s.view_for(0))
	return t


func _sound_events() -> void:
	var snd: AppSound = root.get_node("App").sound
	snd.now_override = 100000
	var settings := AppSettings.new("user://test_celebrate_%d.json" % Time.get_ticks_usec())
	settings.set_value("toene", "normal")
	snd.settings = settings
	var t := await _table()
	for e in ["skip", "skip_all"]:
		snd.last_played = ""
		snd.now_override += 1000
		t.play_event({"e": e, "seat": 1}, 1.0)
		check(snd.last_played == "schnurren", "Ereignis %s spielt das Schnurren" % e)
	snd.last_played = ""
	snd.now_override += 1000
	t.play_event({"e": "reverse"}, 1.0)
	check(snd.last_played != "schnurren", "Richtungswechsel schnurrt nicht")
	t.queue_free()
	await process_frame


func _celebration() -> void:
	var area := Rect2(0, 0, 1280, 10)
	var fx := TableEffects.new()
	root.add_child(fx)
	fx.night = 1.0
	fx.celebrate(area, 220)
	check(fx.last_celebration == "sterne", "Nacht: Sternenschauer")
	# Funkelsterne (1.3.6): ein additiver Zeichenknoten, mehr und kleinere Sterne (8–28 px), je Stern eigene Funkelphase und
	# ein bis zwei Blitze, dazu stehende Glitzerpunkte; gleiche Dauer wie das Konfetti
	var sh := fx.get_child(0) as TableEffects.SparkleShowerFx
	check(fx.get_child_count() == 1 and sh != null, "Nacht: ein Funkelstern-Knoten")
	if sh != null:
		var mat := sh.material as CanvasItemMaterial
		check(mat != null and mat.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD, "Funkelsterne additiv")
		# 1.4.2 Regen: Sterne starten 5 s lang gleichmäßig verteilt oberhalb des Rands, über die ganze Breite
		check(sh.stars.size() >= 250 and sh.glints.size() >= 10, "Regen: deutlich mehr Sterne (>= 250) plus Glitzerpunkte")
		check(absf(TableEffects.SparkleShowerFx.DUR - 5.0) < 0.01, "Sterne starten über 5 s")
		var sizes_ok := true
		var phases := {}
		var flashes_ok := true
		var born_min := 99.0
		var born_max := 0.0
		var above := true
		var life_ok := true
		var xs := [0, 0, 0, 0, 0]
		var secs := [0, 0, 0, 0, 0]
		for st in sh.stars:
			sizes_ok = sizes_ok and float(st["size"]) >= 14.0 and float(st["size"]) <= 42.0
			phases[snappedf(float(st["ph"]), 0.001)] = true
			flashes_ok = flashes_ok and (st["flash"] as Array).size() >= 1
			born_min = minf(born_min, float(st["born"]))
			born_max = maxf(born_max, float(st["born"]))
			above = above and (st["pos"] as Vector2).y < 0.0
			life_ok = life_ok and float(st["life"]) >= 2.0 and float(st["life"]) <= 3.0
			xs[clampi(int((st["pos"] as Vector2).x / 1280.0 * 5.0), 0, 4)] += 1
			secs[clampi(int(float(st["born"])), 0, 4)] += 1
		check(sizes_ok, "Sterne 14–42 px")
		check(born_min < 0.3 and born_max > 4.7, "Startzeiten reichen über fast 5 s")
		check(above, "Start oberhalb des oberen Rands")
		check(life_ok, "Fallzeit 2–3 s")
		var spread_ok := true
		for i in 5:
			spread_ok = spread_ok and xs[i] > sh.stars.size() / 5 * 0.6 and secs[i] > sh.stars.size() / 5 * 0.6
		check(spread_ok, "Gleichmäßig über Breite und Zeit verteilt")
		check(sh._end >= TableEffects.RAIN_DUR + TableEffects.RAIN_TAPER + 2.0 and sh._end < TableEffects.RAIN_DUR + TableEffects.RAIN_TAPER + 5.0,
				"Schauer endet erst nach den letzten Sternen (5 s voll + 5 s Ausrieseln)")
		# Ausrieseln (Nutzerwunsch): nach 5 s werden es gleichmäßig weniger neue Sterne, bis ~10 s
		var early := 0
		var late := 0
		for st in sh.stars:
			var b := float(st["born"])
			if b >= 5.0 and b < 7.5:
				early += 1
			elif b >= 7.5:
				late += 1
		check(born_max > 8.5 and born_max <= 10.0 and early > late * 2 and late > 0, "Ausrieseln 5–10 s (%d früh, %d spät)" % [early, late])
		check(is_equal_approx(TableEffects.rain_time(0.0), 0.0) and is_equal_approx(TableEffects.rain_time(2.0 / 3.0), 5.0)
				and is_equal_approx(TableEffects.rain_time(1.0), 10.0), "rain_time: 0 → 0 s, 2/3 → 5 s, 1 → 10 s")
		check(phases.size() > sh.stars.size() / 2, "Funkeln zeitversetzt je Stern")
		check(flashes_ok, "Jeder Stern blitzt mindestens einmal auf")
		var y0: float = (sh.stars[0]["pos"] as Vector2).y
		for i in 40:
			await process_frame
		check(sh.t > 0.3 and ((sh.stars[0]["pos"] as Vector2).y > y0 or float(sh.stars[0]["born"]) > sh.t - 0.05), "Sterne fallen")
	fx.night = 0.0
	var before := fx.get_child_count()
	fx.celebrate(area, 220)
	check(fx.last_celebration == "konfetti" and fx.get_child_count() == before + 5, "Tag: Konfetti (voller Regen + 4 Stufen Ausrieseln)")
	var cf := fx.get_child(before) as CPUParticles2D
	var taper_ok := true
	for i in range(before + 1, before + 5):
		var tp := fx.get_child(i) as CPUParticles2D
		taper_ok = taper_ok and tp != null and not tp.emitting and tp.amount < (fx.get_child(i - 1) as CPUParticles2D).amount
	check(taper_ok, "Konfetti rieselt in 4 Stufen mit sinkender Menge aus")
	check(cf != null and not cf.one_shot and cf.emitting and cf.explosiveness == 0.0 and cf.amount >= 200
			and cf.position.y < 0.0 and cf.emission_rect_extents.x >= 600.0, "Konfetti: fortlaufender Regen über die Breite oberhalb des Rands")
	# Fortlaufend 5 s, danach nur noch Ausfallen
	var tw_ok := cf != null and absf(TableEffects.RAIN_DUR - 5.0) < 0.01 and TableEffects.RAIN_LIFE <= 3.0
	check(tw_ok, "Konfetti: 5 s Erzeugung, Fallzeit höchstens 3 s")
	# reduziert: nachts wenige ruhige Lichtpunkte ohne Blitzen und Glitzer, tags wie bisher reduziertes Konfetti
	var calm := TableEffects.new()
	calm.reduced = true
	root.add_child(calm)
	calm.night = 1.0
	calm.celebrate(area, 220)
	var cs := calm.get_child(0) as TableEffects.SparkleShowerFx
	var quiet := cs != null and cs.calm and cs.stars.size() <= 40 and cs.glints.is_empty()
	if cs != null:
		for st in cs.stars:
			quiet = quiet and (st["flash"] as Array).is_empty() and float(st["spin"]) == 0.0
	check(calm.get_child_count() == 1 and quiet, "Reduziert: wenige ruhige Lichtpunkte")
	calm.night = 0.0
	var before_calm := calm.get_child_count()
	calm.celebrate(area, 220)
	var cc := calm.get_child(before_calm) as CPUParticles2D
	check(cc != null and cc.amount <= 100 and cc.amount >= 12 and absf(cc.lifetime - TableEffects.RAIN_LIFE) < 0.01, "Reduziert tags: wenig Konfetti, ebenfalls 5 s Regen")
	# Strahlentextur: Mitte hell, lange Strahlen auf den Achsen bis fast zum Rand, diagonal daneben dunkel
	var ray := TableEffects.sparkle_ray_texture().get_image()
	check(TableEffects.sparkle_ray_texture().get_width() == 64 and ray.get_pixel(32, 32).a > 0.9 and ray.get_pixel(32, 12).a > 0.15
			and ray.get_pixel(12, 32).a > 0.15 and ray.get_pixel(14, 14).a < 0.05 and ray.get_pixel(32, 24).a > ray.get_pixel(29, 24).a + 0.3,
			"Strahlentextur: feine Strahlen auf den Achsen")
	var core := TableEffects.sparkle_core_texture().get_image()
	check(core.get_pixel(16, 16).a > 0.9 and core.get_pixel(1, 1).a < 0.05, "Kerntextur: heller Kern, weicher Rand")
	fx.queue_free()
	calm.queue_free()
	# Tisch: Rundenende wählt nach der Tischseite
	var t := await _table()
	t.fx_top.night = 1.0
	t.play_event({"e": "round_over", "ranking": [0]}, 1.0)
	check(t.fx_top.last_celebration == "sterne", "Tisch nachts: Sterne zum Rundenende")
	t.fx_top.night = 0.0
	t.play_event({"e": "game_over", "ranking": [0]}, 1.0)
	check(t.fx_top.last_celebration == "konfetti", "Tisch tags: Konfetti zum Partieende")
	t.queue_free()
	await process_frame



func _sound_file() -> void:
	check(AppSound.NAMES.has("schnurren") and AppSound.path_for("schnurren") != "", "Datei schnurren vorhanden")
	var settings := AppSettings.new("user://test_celebrate_%d.json" % Time.get_ticks_usec())
	var snd := AppSound.new()
	snd.settings = settings
	snd.now_override = 5000
	root.add_child(snd)
	check(not snd.play("schnurren"), "Spieltöne ab Werk aus: Schnurren still")
	settings.set_value("toene", "normal")
	check(snd.play("schnurren") and is_equal_approx(snd.last_db, float(AppSound.TON_DB["normal"])), "Schnurren in Spielton-Lautstärke")
	snd.queue_free()
