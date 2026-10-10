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
		check(sh.stars.size() >= 120 and sh.glints.size() >= 10, "Mehr Sterne als bisher (99) plus Glitzerpunkte")
		check(absf(TableEffects.SparkleShowerFx.LIFE - 3.6) < 0.01, "Sterneschauer: 3,6 s je Stern, gesamt ~5 s wie das Konfetti")
		var sizes_ok := true
		var phases := {}
		var flashes_ok := true
		for st in sh.stars:
			sizes_ok = sizes_ok and float(st["size"]) >= 14.0 and float(st["size"]) <= 42.0
			phases[snappedf(float(st["ph"]), 0.001)] = true
			flashes_ok = flashes_ok and (st["flash"] as Array).size() >= 1
		check(sizes_ok, "Sterne 14–42 px")
		check(absf(sh._end - 5.3) < 0.01, "Schauer ~5 s")
		check(phases.size() > sh.stars.size() / 2, "Funkeln zeitversetzt je Stern")
		check(flashes_ok, "Jeder Stern blitzt mindestens einmal auf")
		var y0: float = (sh.stars[0]["pos"] as Vector2).y
		for i in 40:
			await process_frame
		check(sh.t > 0.3 and ((sh.stars[0]["pos"] as Vector2).y > y0 or float(sh.stars[0]["born"]) > sh.t - 0.05), "Sterne fallen")
	fx.night = 0.0
	var before := fx.get_child_count()
	fx.celebrate(area, 220)
	check(fx.last_celebration == "konfetti" and fx.get_child_count() == before + 1, "Tag: Konfetti")
	# reduziert: nachts wenige ruhige Lichtpunkte ohne Blitzen und Glitzer, tags wie bisher reduziertes Konfetti
	var calm := TableEffects.new()
	calm.reduced = true
	root.add_child(calm)
	calm.night = 1.0
	calm.celebrate(area, 220)
	var cs := calm.get_child(0) as TableEffects.SparkleShowerFx
	var quiet := cs != null and cs.calm and cs.stars.size() <= 20 and cs.glints.is_empty()
	if cs != null:
		for st in cs.stars:
			quiet = quiet and (st["flash"] as Array).is_empty() and float(st["spin"]) == 0.0
	check(calm.get_child_count() == 1 and quiet, "Reduziert: wenige ruhige Lichtpunkte")
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
