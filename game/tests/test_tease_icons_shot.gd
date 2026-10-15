extends SceneTree
# Kontrollbilder Beta 1.6.5 (Nutzerwunsch: Reaktionen als feste Bilder, die überall gleich aussehen – Microsoft Fluent Emoji „Color“,
# assets/ui/reaktionen/*.svg) – die Bilder allein, mit Renderer („_shot“: vom Testlauf ausgenommen):
#   tools/godot_run.ps1 -Script res://tests/test_tease_icons_shot.gd -Resolution 1600x720 [-EnvPairs "SHOT_DIR=…"]
#   (15.10.2026: mit -Extra '--rendering-driver','opengl3_angle' – der native OpenGL-Treiber der RTX 3090 malte grüne Blöcke in
#   die kleinen Mipmap-Stufen aller Bilder mit Transparenz, auch Zurück-Pfeil und ☰; mit ANGLE sauber)
# Ohne SHOT_DIR nach docs/module/optik_165_*.png:
#   daumen_gross   „Daumen hoch“ groß (≈ 280 px) im Knopfrahmen auf Papier und auf Nachtgrund, rechts alle 4 Reaktionen mittelgroß
#   daumen_klein   die 4 Reaktionsknöpfe in Originalgröße (Tag und Nacht, Reihenfolge Lachen, Klatschen, Daumen hoch, Schreck),
#                  rechts daneben in der Größe der aufsteigenden Reaktion; darunter dasselbe 3-fach vergrößert (Pixel sichtbar)

var out := ""


class Board:
	extends Control
	var mode := "gross"

	func _draw() -> void:
		if mode == "gross":
			draw_rect(Rect2(0, 0, 400, 340), UiPalette.PAPER)
			draw_rect(Rect2(400, 0, 400, 340), UiPalette.NIGHT_PANEL)
			draw_rect(Rect2(800, 0, 400, 340), UiPalette.PAPER)
			for i in 2:
				var c := Vector2(200 + i * 400, 170)
				draw_circle(c, 150.0 + 4.0, UiPalette.MOON if i == 1 else UiPalette.INK)
				draw_circle(c, 150.0, UiPalette.NIGHT_HI if i == 1 else UiPalette.CREAM)
				TeaseFx.draw_icon(self, "daumen", c, 128.0)
			for i in TeaseMenu.REACT_ORDER.size():
				TeaseFx.draw_icon(self, TeaseMenu.REACT_ORDER[i], Vector2(900 + (i % 2) * 200, 85 + (i / 2) * 170), 64.0)
			return
		draw_rect(Rect2(0, 0, 560, 70), UiPalette.PAPER)
		draw_rect(Rect2(0, 70, 560, 70), UiPalette.NIGHT_PANEL)
		for row in 2:
			var dark := row == 1
			var y := 35.0 + row * 70.0
			for i in TeaseMenu.REACT_ORDER.size():
				var c := Vector2(36.0 + i * 58.0, y)
				var r := TeaseMenu.REACT_BTN_R
				if dark:
					draw_circle(c, r + 8.0, Color(UiPalette.RING, 0.16))
				draw_circle(c, r + 3.0, UiPalette.MOON if dark else UiPalette.INK)
				draw_circle(c, r, UiPalette.NIGHT_HI if dark else UiPalette.CREAM)
				TeaseFx.draw_icon(self, TeaseMenu.REACT_ORDER[i], c, r * TeaseMenu.REACT_ICON)
			for i in TeaseMenu.REACT_ORDER.size():
				TeaseFx.draw_icon(self, TeaseMenu.REACT_ORDER[i], Vector2(300.0 + i * 70.0, y), 28.0, 0.3)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	out = OS.get_environment("SHOT_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("res://").path_join("../docs/module").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	var b := Board.new()
	b.size = Vector2(1600, 720)
	root.add_child(b)
	var sc := root.get_texture().get_size().x / 1600.0      # Fenster ≙ 1600 × 720 logisch
	for m in ["gross", "klein"]:
		b.mode = m
		b.queue_redraw()
		for i in 3:
			await process_frame
		var img := root.get_texture().get_image()
		if m == "gross":
			img = img.get_region(Rect2i(0, 0, int(1200 * sc), int(340 * sc)))
		else:
			img = img.get_region(Rect2i(0, 0, int(560 * sc), int(140 * sc)))
			var big := img.duplicate() as Image
			big.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
			var both := Image.create(big.get_width(), img.get_height() + big.get_height() + 10, false, img.get_format())
			both.fill(Color.WHITE)
			both.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
			both.blit_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), Vector2i(0, img.get_height() + 10))
			img = both
		img.save_png(out.path_join("optik_165_daumen_%s.png" % m))
		print("Bild: optik_165_daumen_%s.png" % m)
	print("RESULT: 1 ok")
	quit(0)
