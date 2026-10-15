extends "res://tests/main_menu_kit.gd"
# Mau-Mau Flip (Beta 1.6.4, Nutzerbefund S24 Ultra mit 1.6.0): Das Hauptmenü läuft in keinem Zustand aus dem Bild. Für alle
# Geräteformate (main_menu_kit.FORMATS) × Update bereit ja/nein × „Partie fortsetzen“ ja/nein × Schrift normal/groß/sehr groß ×
# Deutsch/Englisch: alle Knöpfe ganz im sichtbaren Bereich, keiner schmaler als sein Inhalt, keine Überlappung, Titel ungekürzt.
# Das Hauptmenü hat keine Nachtseite (Hintergrund immer Tag), daher kein Tag/Nacht-Durchlauf.

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
	for f in FORMATS:
		var size := virtual_size(int(f[1]), int(f[2]))
		for lang in ["de", "en"]:
			for font in FONT_LEVELS:
				for update in [false, true]:
					for resume in [false, true]:
						var m := await open_menu(int(f[1]), int(f[2]), font, lang, update, resume)
						var tag := "%s %s %s%s%s" % [f[0], lang, font, " update" if update else "", " fortsetzen" if resume else ""]
						var upd := m.find_child("Update", true, false) as Button
						check(upd != null and upd.is_visible_in_tree() == update, tag + ": Update-Knopf " + ("sichtbar" if update else "versteckt"))
						check(m.resume_row.visible == resume, tag + ": „Partie fortsetzen“ " + ("da" if resume else "nicht da"))
						var probs := fit_problems(m, Vector2(size))
						check(probs.is_empty(), tag + ": " + "; ".join(probs))
	# Live-Wechsel der Schrift auf dem schon gebauten Menü (Einstellung „Schrift“ wirkt ohne Neuaufbau)
	var m2 := await open_menu(1560, 720, "normal", "de", true, true)
	UiFonts.set_level("sehr_gross", root)
	for i in 4:
		await process_frame
	var probs2 := fit_problems(m2, Vector2(virtual_size(1560, 720)))
	check(probs2.is_empty(), "live auf „Sehr groß“: " + "; ".join(probs2))
	restore()
	await process_frame
	print("RESULT: %d ok, %d failed" % [ok, failed])
	quit(1 if failed > 0 else 0)
