extends SceneTree
# UiTheme (Modul F1b): Thema bauen, Schriften und Stile prüfen, große Touch-Ziele; mit SAVE_THEME=1 nach
# res://assets/ui/theme.tres speichern und wieder laden. Dazu UiFonts/UiIcons/UiPalette-Grundprüfungen.

var ok := 0
var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		ok += 1
	else:
		fails += 1
		print("FAIL: " + what)


func _init() -> void:
	check(UiFonts.has_fonts(), "Schriften vorhanden (Modul B)")
	check(UiFonts.text() is FontVariation, "Bricolage als FontVariation")
	var axes: Dictionary = (UiFonts.text() as FontVariation).variation_opentype if UiFonts.text() is FontVariation else {}
	check(int(axes.get("opsz", 0)) == 12, "Bricolage immer mit opsz 12")
	check(UiFonts.mau() is FontVariation and int((UiFonts.mau() as FontVariation).variation_opentype.get("SOFT", 0)) == 100, "Mau-Schrift: Fraunces kursiv SOFT 100")
	var t := UiTheme.build()
	check(t.default_font != null and t.default_font_size == 24, "Grundschrift")
	for type in ["Button", "PrimaryButton", "DarkButton", "GhostButton"]:
		var sb := t.get_stylebox("normal", type) as StyleBoxFlat
		var f := t.get_font("font", "Button")
		var fs := t.get_font_size("font_size", "Button")
		var h := sb.content_margin_top + sb.content_margin_bottom + f.get_height(fs)
		check(h >= UiTheme.TOUCH_MIN, "%s: Höhe %.0f ≥ %d px (48 dp)" % [type, h, UiTheme.TOUCH_MIN])
	var le := t.get_stylebox("normal", "LineEdit") as StyleBoxFlat
	check(le.content_margin_top + le.content_margin_bottom + t.get_font("font", "LineEdit").get_height(26) >= UiTheme.TOUCH_MIN, "Eingabefeld groß genug")
	check(t.get_font("font", "TitleLabel") != null and t.get_font_size("font_size", "TitleLabel") >= 44, "Überschrift Fraunces")
	check((t.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).bg_color == UiPalette.PAPER, "Papierfläche")
	# Symbole rastern
	for c in UiPalette.LIGHT_COLORS + UiPalette.DARK_COLORS:
		var tex := UiIcons.symbol(c, 48)
		var img := tex.get_image()
		var opaque := 0
		for y in range(0, 48, 3):
			for x in range(0, 48, 3):
				if img.get_pixel(x, y).a > 0.5:
					opaque += 1
		check(opaque > 20, "Symbol %s gerastert (%d)" % [c, opaque])
	check(UiPalette.text_on(UiPalette.fill("gelb")) == UiPalette.INK and UiPalette.text_on(UiPalette.fill("lila")) == UiPalette.PAPER, "Schriftfarbe auf Flächen")
	if OS.get_environment("SAVE_THEME") == "1":
		check(UiTheme.save() == OK, "theme.tres gespeichert")
	if ResourceLoader.exists(UiTheme.PATH):
		var loaded := load(UiTheme.PATH) as Theme
		check(loaded != null and loaded.has_stylebox("normal", "PrimaryButton"), "theme.tres lädt")
	print("RESULT: %d ok" % ok)
	quit(0 if fails == 0 else 1)
