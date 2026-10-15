extends "res://tests/main_menu_kit.gd"
# Kontrollbilder Beta 1.6.4: Hauptmenü mit „Update bereit“ in den Geräteformaten (Nutzerbefund S24 Ultra mit 1.6.0: Knopfspalte rechts
# abgeschnitten). Mit Renderer; „_shot“: vom Testlauf ausgenommen (die Prüfung ohne Bild ist test_main_menu_fit.gd).
#   tools/godot_run.ps1 -Script res://tests/test_main_menu_fit_shot.gd -Resolution 1600x720 [-EnvPairs "SHOT_DIR=…"]
# Ohne SHOT_DIR nach docs/module/optik_164_hauptmenue_<format>_<zustand>.png. Jedes Bild hat die virtuelle Größe des Formats (Breite
# 1600, Höhe 720 … 1000) – das Layout ist dasselbe wie auf dem Gerät, nur ohne dessen Pixeldichte. Das Hauptmenü hat keine Nachtseite.
# Je Format: update_normal, update_sehr_gross; zusätzlich (S24 und 1280×800) ohne Update, Englisch und mit „Partie fortsetzen“.

var out := ""
var shots := 0


func _initialize() -> void:
	call_deferred("run")


func shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out.path_join("optik_164_hauptmenue_%s.png" % file))
	shots += 1
	var probs := fit_problems(menu, Vector2(vp.size))
	if not probs.is_empty():
		print("BEFUND %s: %s" % [file, "; ".join(probs)])


func run() -> void:
	out = OS.get_environment("SHOT_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("res://").path_join("../docs/module").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	for f in FORMATS:
		var w := int(f[1])
		var h := int(f[2])
		var variants := [["update_normal", "normal", "de", true, false], ["update_sehr_gross", "sehr_gross", "de", true, false]]
		if f[0] == "s24_1560x720" or f[0] == "1280x800":
			variants += [["ohne_update_normal", "normal", "de", false, false], ["update_gross", "gross", "de", true, false],
				["update_en_normal", "normal", "en", true, false], ["update_en_sehr_gross", "sehr_gross", "en", true, false],
				["fortsetzen_update_normal", "normal", "de", true, true], ["fortsetzen_update_sehr_gross", "sehr_gross", "de", true, true],
				["fortsetzen_update_en_sehr_gross", "sehr_gross", "en", true, true]]
		for v in variants:
			await open_menu(w, h, str(v[1]), str(v[2]), bool(v[3]), bool(v[4]))
			await create_timer(0.3).timeout
			await shot("%s_%s" % [f[0], v[0]])
	restore()
	await process_frame
	print("RESULT: %d Bilder nach %s" % [shots, out])
	quit(0)
