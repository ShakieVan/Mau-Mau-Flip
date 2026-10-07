extends SceneTree
# Beta 1.0.1: Schriftgrößen zentral (UiFonts.SIZES) und Einstellung „Schriftgröße“ (normal/gross/sehr_gross) – Faktor, Thema,
# Umrechnen schon gebauter Bildschirme ohne Wandern (hin und zurück wieder gleich), keine Mindestgröße unter den alten Werten.

var ok := 0
var failed := 0


func check(cond: bool, text: String) -> void:
	if cond:
		ok += 1
	else:
		failed += 1
		print("FAIL: ", text)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	UiFonts.set_level("normal")
	check(UiFonts.size("hinweis") >= 22 and UiFonts.size("pille") >= 18 and UiFonts.size("mini") >= 16, "Grundgrößen angehoben")
	var th := UiTheme.get_theme()
	check(th.get_font_size("font_size", "HintLabel") == UiFonts.size("hinweis"), "Thema: HintLabel aus der Tabelle")
	var nav := ScreenNav.new()
	nav.autostart = false
	root.add_child(nav)
	var st := SettingsScreen.new()
	nav.push(st, false)
	await process_frame
	await process_frame
	var hint := ScreenKit.hint("Probe", UiFonts.size("klein"))
	st.add_child(hint)
	var before := hint.get_theme_font_size("font_size")
	check(st.find_child("Schrift", true, false) != null, "Einstellungen: Auswahl Schriftgröße")
	UiFonts.set_level("sehr_gross", root)
	check(hint.get_theme_font_size("font_size") == roundi(UiFonts.SIZES["klein"] * 1.3), "live umgerechnet (Override)")
	check(th.get_font_size("font_size", "HintLabel") == roundi(UiFonts.SIZES["hinweis"] * 1.3), "live umgerechnet (Thema)")
	check(UiFonts.size("text") == roundi(24 * 1.3), "size() mit Faktor")
	UiFonts.set_level("gross", root)
	UiFonts.set_level("normal", root)
	check(hint.get_theme_font_size("font_size") == before, "hin und zurück ohne Wandern")
	check(not UiFonts.set_level("normal", root), "gleiche Stufe: nichts zu tun")
	UiFonts.set_level("unbekannt")
	check(UiFonts.level == "normal" and is_equal_approx(UiFonts.scale, 1.0), "unbekannte Stufe = normal")
	nav.queue_free()
	await process_frame
	print("RESULT: %d ok, %d failed" % [ok, failed])
	quit(1 if failed > 0 else 0)
