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
	var stars := 0
	for c in fx.get_children():
		if c is CPUParticles2D and (c as CPUParticles2D).texture == TableEffects.star_texture():
			stars += 1
			check(absf((c as CPUParticles2D).lifetime - 2.6) < 0.01, "Sterne fallen so lange wie das Konfetti")
	check(stars == 1 and fx.get_child_count() == 2, "Sterne plus Glitzerschweif")
	fx.night = 0.0
	var before := fx.get_child_count()
	fx.celebrate(area, 220)
	check(fx.last_celebration == "konfetti" and fx.get_child_count() == before + 1, "Tag: Konfetti")
	# reduziert: nachts wenige ruhige Sterne ohne Schweif, tags wie bisher reduziertes Konfetti
	var calm := TableEffects.new()
	calm.reduced = true
	root.add_child(calm)
	calm.night = 1.0
	calm.celebrate(area, 220)
	var p := calm.get_child(0) as CPUParticles2D
	check(calm.get_child_count() == 1 and p.amount <= 20 and p.scale_amount_curve == null, "Reduziert: wenige ruhige Sterne")
	# Gerade, spitze Zacken (Nutzerbefund 1.3.4: gebogene Kanten wirkten wie Blumen): Mitte und Spitze deckend, zwischen Spitze
	# und Tal bei Radius 18,5 durchsichtig (bei der alten, gebogenen Form lag der Rand dort erst bei ~20 → deckend)
	var star_img := TableEffects.star_texture().get_image()
	var c := Vector2(32, 32)
	var mid := c + Vector2(cos(deg_to_rad(-72.0)), sin(deg_to_rad(-72.0))) * 18.5
	check(TableEffects.star_texture().get_width() == 64 and star_img.get_pixel(32, 32).a > 0.9 and star_img.get_pixel(32, 6).a > 0.5
			and star_img.get_pixelv(Vector2i(mid)).a < 0.2, "Sterntextur: gerade, spitze Zacken")
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
