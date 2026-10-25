extends SceneTree
# Mau-Mau Flip (Beta 1.6.4): Hauptmenü in Geräteformaten für test_main_menu_fit.gd (Prüfung ohne Bild) und test_main_menu_fit_shot.gd
# (Kontrollbilder). Anlass: Nutzerbefund S24 Ultra (App 1.6.0) – mit „Update ↓“ lief die Knopfspalte rechts aus dem Bild.
# Jedes Format läuft in einer eigenen SubViewport in der virtuellen Größe, die das Projekt auf dem Gerät hätte (Basis 1600×720,
# stretch canvas_items/expand: Die Höhe bestimmt den Maßstab, bei 1280×800 die Breite). Updater-Zustand „Update bereit“ = App.updater.release
# gesetzt (wie nach einer erfolgreichen Suche), „Partie fortsetzen“ über ein untergeschobenes Angebot (FakeMenu._offer).

const BASE := Vector2(1600, 720)
# [Name, Breite, Höhe] in Gerätepixeln (Querformat)
const FORMATS := [["s24_1560x720", 1560, 720], ["2400x1080", 2400, 1080], ["s21_2340x1080", 2340, 1080], ["s10_3040x1440", 3040, 1440],
	["1600x720", 1600, 720], ["1280x800", 1280, 800]]
const FONT_LEVELS := ["normal", "gross", "sehr_gross"]
const NOW := 1_800_000_000


class FakeMenu:
	extends MainMenuScreen
	var offer := {}
	var rejoin := {}                 # Beta 1.6.16: „Zurück ins Spiel“

	func _offer() -> Dictionary:
		return offer

	func _rejoin_offer() -> Dictionary:
		return rejoin


var vp: SubViewport
var nav: ScreenNav
var menu: FakeMenu


# Virtuelle Größe (Einheiten der Oberfläche) eines Geräts mit w × h Pixeln
static func virtual_size(w: int, h: int) -> Vector2i:
	var s := minf(w / BASE.x, h / BASE.y)
	return Vector2i(roundi(w / s), roundi(h / s))


# Angebot „Partie fortsetzen“ mit langen Namen (die Unterzeile kürzt mit „…“)
static func resume_offer() -> Dictionary:
	return {"role": "host", "host_seat": 0, "my_seat": 0, "game": {"round": 3}, "saved_unix": NOW - 12 * 60,
		"seats": [{"name": "Du"}, {"name": "Maximiliane"}, {"name": "Bartholomäus"}, {"name": "Kim"}]}


# Beta 1.6.16: Angebot „Zurück ins Spiel“ mit langem Gastgebernamen
static func rejoin_offer() -> Dictionary:
	return {"room": "KATZE-42", "relay": "https://vermittler.example", "host": "Maximiliane", "t": NOW - 7 * 60}


# Updater-Zustand simulieren: release gesetzt = „Update bereit“ (Updater.available), dann changed wie nach einer Suche
func set_update(on: bool) -> void:
	var app := root.get_node_or_null("App")
	var up: Variant = app.get("updater") if app != null else null
	if not up is Updater:
		return
	(up as Updater).release = {"version": "9.9.9", "beta": true, "notes": "", "size": 1, "url": "", "sha256": ""} if on else {}
	(up as Updater).changed.emit()


# Hauptmenü in einer SubViewport aufbauen (Größe = virtuelle Größe des Formats) und Layout abwarten
func open_menu(w: int, h: int, font: String, lang: String, update: bool, resume: bool, rejoin := false) -> FakeMenu:
	close_menu()
	I18n.set_language(lang)
	set_update(update)
	vp = SubViewport.new()
	vp.size = virtual_size(w, h)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	nav = ScreenNav.new()
	nav.autostart = false
	vp.add_child(nav)                                  # _ready setzt die Schrift aus den Einstellungen …
	UiFonts.set_level(font, root)                      # … deshalb danach die gewünschte Stufe
	menu = FakeMenu.new()
	menu.now_unix = NOW
	menu.offer = resume_offer() if resume else {}
	menu.rejoin = rejoin_offer() if rejoin else {}
	menu.rejoin_check = false
	nav.push(menu, false)
	for i in 6:
		await process_frame
	return menu


func close_menu() -> void:
	if vp != null and is_instance_valid(vp):
		vp.free()
	vp = null
	nav = null
	menu = null


func restore() -> void:
	close_menu()
	set_update(false)
	UiFonts.set_level("normal", root)
	I18n.set_language("de")


# Alles sichtbar und nichts abgeschnitten? Liefert die Befunde (leer = in Ordnung).
func fit_problems(m: MainMenuScreen, screen_size: Vector2) -> PackedStringArray:
	var out: PackedStringArray = []
	var screen := Rect2(Vector2.ZERO, screen_size).grow(0.5)
	var buttons: Array[Button] = []
	for n in m.find_children("*", "Button", true, false):
		var b := n as Button
		if b.is_visible_in_tree():
			buttons.append(b)
	if buttons.size() < 6:
		out.append("nur %d Knöpfe sichtbar" % buttons.size())
	for b in buttons:
		var r := b.get_global_rect()
		if not screen.encloses(r):
			out.append("%s außerhalb: %s (Bild %s)" % [b.name, r, screen_size])
		if b.size.x + 0.5 < b.get_combined_minimum_size().x:
			out.append("%s schmaler als sein Inhalt" % b.name)
		# große Knöpfe: Symbol und Texte (inneres HBox) ganz im Knopf
		for c in b.get_children():
			if c is Container and (c as Control).visible and not r.grow(0.5).encloses((c as Control).get_global_rect()):
				out.append("%s: Inhalt ragt hinaus (%s in %s)" % [b.name, (c as Control).get_global_rect(), r])
		var t := b.find_child("Titel", true, false) as Label
		if t != null and t.text != "":
			var w := t.get_theme_font("font").get_string_size(t.atr(t.text), HORIZONTAL_ALIGNMENT_LEFT, -1, t.get_theme_font_size("font_size")).x
			if w > t.size.x + 1.0:
				out.append("%s: Titel „%s“ gekürzt (%d > %d)" % [b.name, t.text, w, t.size.x])
	for i in buttons.size():
		for j in range(i + 1, buttons.size()):
			var a := buttons[i].get_global_rect().grow(-1.0)
			if a.intersects(buttons[j].get_global_rect().grow(-1.0)):
				out.append("%s überlappt %s" % [buttons[i].name, buttons[j].name])
	for n in m.find_children("*", "Label", true, false):
		var l := n as Label
		if l.is_visible_in_tree() and l.text != "" and not screen.encloses(l.get_global_rect()):
			out.append("Text „%s“ außerhalb: %s" % [l.text, l.get_global_rect()])
	return out
