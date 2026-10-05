extends SceneTree
# Modul B: Kartenbilder, Browser-Bilder, Schriften und UI-Grafiken prüfen (docs/BETA1_PLAN.md Abschnitt 3).
# Liest die Quelldateien direkt (Image.load_from_file), prüft zusätzlich, dass Godot die Karten importiert hat.

const LIGHT := ["rot", "gelb", "gruen", "blau"]
const DARK := ["pink", "tuerkis", "orange", "lila"]
const PAPER := Color("#F4EADA")
# Kartenfarbe hell (Fläche) bzw. dunkel (Neonkontur)
const FIELD := {"rot": Color("#B3202A"), "gelb": Color("#FFDD33"), "gruen": Color("#43B05C"), "blau": Color("#2A5BD7"),
	"pink": Color("#FFB3DC"), "tuerkis": Color("#0B97A3"), "orange": Color("#FF7F14"), "lila": Color("#5E3BD8")}

var ok := 0
var fails := 0


func check(cond: bool, text: String) -> void:
	if cond:
		ok += 1
	else:
		fails += 1
		print("FAIL: " + text)


# Alle 108 Gesichter laut Plan plus Rückseite
static func all_keys() -> Array[String]:
	var keys: Array[String] = []
	for c: String in LIGHT:
		for n in range(1, 10):
			keys.append("hell_%s_%d" % [c, n])
		for t: String in ["plus1", "aussetzen", "richtungswechsel", "flip"]:
			keys.append("hell_%s_%s" % [c, t])
	keys.append_array(["hell_wuenscher", "hell_wuenscher_plus2"])
	for c: String in DARK:
		for n in range(1, 10):
			keys.append("dunkel_%s_%d" % [c, n])
		for t: String in ["plus5", "alle_aussetzen", "richtungswechsel", "flip"]:
			keys.append("dunkel_%s_%s" % [c, t])
	keys.append_array(["dunkel_wuenscher", "dunkel_farbjagd", "rueckseite"])
	return keys


static func load_image(res_path: String) -> Image:
	var path := ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(path):
		return null
	return Image.load_from_file(path)


static func nearest(col: Color, names: Array) -> String:
	var best := ""
	var best_d := 99.0
	for n: String in names:
		var f: Color = FIELD[n]
		var d := Vector3(col.r - f.r, col.g - f.g, col.b - f.b).length()
		if d < best_d:
			best_d = d
			best = n
	return best


func _init() -> void:
	var keys := all_keys()
	check(keys.size() == 109, "109 Schlüssel erwartet, %d" % keys.size())
	_check_carddb(keys)
	_check_cards(keys)
	_check_import(keys)
	_check_web(keys)
	_check_web_match(keys)
	_check_fonts()
	_check_woff2()
	_check_ui()
	_check_color_symbols()
	_check_splash()
	print("RESULT: %d ok" % ok)
	quit(0 if fails == 0 else 1)


# Spitzenrauschabstand zweier RGBA8-Bilder gleicher Größe in dB; Farbe vormultipliziert (unsichtbare Pixel zählen nicht), jedes step-te Pixel
static func psnr(a: PackedByteArray, b: PackedByteArray, step := 1) -> float:
	if a.size() != b.size() or a.is_empty():
		return 0.0
	var sum := 0.0
	var n := 0
	var i := 0
	while i < a.size():
		var aa := a[i + 3]
		var ab := b[i + 3]
		for c in 3:
			var d := (a[i + c] * aa - b[i + c] * ab) / 255.0
			sum += d * d
		var da := float(aa - ab)
		sum += da * da
		n += 4
		i += 4 * step
	var mse := sum / maxf(n, 1)
	return 99.0 if mse < 1e-9 else 10.0 * log(255.0 * 255.0 / mse) / log(10.0)


# Relative Leuchtdichte nach WCAG 2
static func luminance(c: Color) -> float:
	var lin := func(v: float) -> float: return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * lin.call(c.r) + 0.7152 * lin.call(c.g) + 0.0722 * lin.call(c.b)


static func contrast(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


# Vertrag mit Modul A: dieselben 108 Gesichtsschlüssel wie CardDB (falls vorhanden)
func _check_carddb(keys: Array[String]) -> void:
	if not ResourceLoader.exists("res://scripts/rules/card_db.gd"):
		print("  Hinweis: CardDB fehlt, Abgleich übersprungen")
		return
	var db: Script = load("res://scripts/rules/card_db.gd")
	var theirs: PackedStringArray = db.call("all_keys")
	var mine := keys.duplicate()
	mine.erase("rueckseite")
	var missing: Array[String] = []
	for k in theirs:
		if not mine.has(k):
			missing.append(k)
	var extra: Array[String] = []
	for k in mine:
		if not theirs.has(k):
			extra.append(k)
	check(theirs.size() == 108 and missing.is_empty() and extra.is_empty(),
		"Schlüssel weichen von CardDB ab: fehlen %s, überzählig %s" % [str(missing), str(extra)])
	check(not theirs.has("rueckseite"), "CardDB führt rueckseite als Gesicht")


# Import: Karten verlustbehaftet (WebP 0,9) mit Mipmaps, Bediensymbole mit Mipmaps, Projektfilter nutzt Mipmaps.
# Qualität des verlustbehafteten Imports gegen das Quellbild an einer Stichprobe.
func _check_import(keys: Array[String]) -> void:
	var filt := int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", 1))
	check(filt == 3, "default_texture_filter ist %d statt 3 (Linear Mipmap): Mipmaps der Karten wirken sonst nicht" % filt)
	var bad_cfg := 0
	for key in keys:
		var cfg := ConfigFile.new()
		if cfg.load("res://assets/cards/%s.png.import" % key) != OK \
				or int(cfg.get_value("params", "compress/mode", -1)) != 1 \
				or absf(float(cfg.get_value("params", "compress/lossy_quality", 0.0)) - 0.9) > 0.001 \
				or not bool(cfg.get_value("params", "mipmaps/generate", false)):
			bad_cfg += 1
	check(bad_cfg == 0, "%d Karten nicht mit compress/mode=1, lossy_quality=0.9, Mipmaps importiert" % bad_cfg)
	var worst := 99.0
	var worst_key := ""
	var no_mip := 0
	for i in range(0, keys.size(), 9):
		var key := keys[i]
		var tex := load("res://assets/cards/%s.png" % key) as Texture2D
		var src := load_image("res://assets/cards/%s.png" % key)
		if tex == null or src == null:
			no_mip += 1
			continue
		var img := tex.get_image()
		if img == null or not img.has_mipmaps():
			no_mip += 1
			continue
		img.clear_mipmaps()
		img.convert(Image.FORMAT_RGBA8)
		src.convert(Image.FORMAT_RGBA8)
		var p := psnr(img.get_data(), src.get_data(), 2)
		if p < worst:
			worst = p
			worst_key = key
	check(no_mip == 0, "%d Kartentexturen ohne Mipmaps oder nicht ladbar" % no_mip)
	check(worst >= 32.0, "Verlustbehafteter Import zu grob: %s nur %.1f dB" % [worst_key, worst])
	print("  Karten-Import: schlechteste Stichprobe %s %.1f dB" % [worst_key, worst])
	var ui_no_mip: Array[String] = []
	for n: String in ["sortieren", "rueckseiten", "hilfe", "zurueck", "mau", "farben/lila", "farben/rot", "logo_klein"]:
		var t := load("res://assets/ui/%s.png" % n) as Texture2D
		var im := t.get_image() if t != null else null
		if im == null or not im.has_mipmaps():
			ui_no_mip.append(n)
	check(ui_no_mip.is_empty(), "UI-Grafiken ohne Mipmaps: %s" % str(ui_no_mip))


# WebP passt inhaltlich zum PNG desselben Schlüssels (verkleinert verglichen) und deutlich schlechter zum Nachbarschlüssel
func _check_web_match(keys: Array[String]) -> void:
	var web := ProjectSettings.globalize_path("res://").path_join("../webclient/cards")
	var small := {}
	for key in keys:
		var src := load_image("res://assets/cards/%s.png" % key)
		if src == null:
			continue
		src.convert(Image.FORMAT_RGBA8)
		src.resize(200, 311, Image.INTERPOLATE_CUBIC)
		small[key] = src.get_data()
	var bad: Array[String] = []
	var worst := 99.0
	var best_wrong := 0.0
	for i in keys.size():
		var key := keys[i]
		var other := keys[(i + 1) % keys.size()]
		var path := web.path_join("%s.webp" % key)
		var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
		if img == null or not small.has(key) or not small.has(other):
			bad.append(key)
			continue
		img.convert(Image.FORMAT_RGBA8)
		var own := psnr(img.get_data(), small[key], 2)
		var wrong := psnr(img.get_data(), small[other], 2)
		worst = minf(worst, own)
		best_wrong = maxf(best_wrong, wrong)
		if own < 24.0 or own < wrong + 3.0:
			bad.append("%s (%.1f dB, Nachbar %s %.1f dB)" % [key, own, other, wrong])
	check(bad.is_empty(), "WebP passt nicht zum PNG: %s" % str(bad))
	print("  WebP gegen PNG: schlechtestes Paar %.1f dB, ähnlichster Nachbar %.1f dB" % [worst, best_wrong])


func _check_cards(keys: Array[String]) -> void:
	var hashes := {}
	var bad_size := 0
	var bad_alpha := 0
	var bad_side := 0
	var bad_color := 0
	var missing := 0
	var not_imported := 0
	for key in keys:
		var img := load_image("res://assets/cards/%s.png" % key)
		if img == null:
			missing += 1
			continue
		if not ResourceLoader.exists("res://assets/cards/%s.png" % key):
			not_imported += 1
		if img.get_width() != 300 or img.get_height() != 466:
			bad_size += 1
			continue
		img.convert(Image.FORMAT_RGBA8)
		# Ecken transparent, Kante und Mitte deckend
		var corners := [Vector2i(0, 0), Vector2i(299, 0), Vector2i(0, 465), Vector2i(299, 465)]
		var solid := [Vector2i(150, 2), Vector2i(150, 463), Vector2i(2, 233), Vector2i(297, 233), Vector2i(150, 233)]
		for p: Vector2i in corners:
			if img.get_pixelv(p).a > 0.01:
				bad_alpha += 1
		for p: Vector2i in solid:
			if img.get_pixelv(p).a < 0.99:
				bad_alpha += 1
		hashes[hash(img.get_data())] = key
		# Seite am Rand erkennen: Papier (hell) gegen Nacht (dunkel)
		var rim := img.get_pixel(6, 233)
		if key.begins_with("hell_") and rim.get_luminance() < 0.75:
			bad_side += 1
		if key.begins_with("dunkel_") and rim.get_luminance() > 0.2:
			bad_side += 1
		# Farbe: helle Seite am Farbfeld oben rechts, dunkle an der Neonkontur rechts
		var parts := key.split("_")
		if parts.size() >= 3 and FIELD.has(parts[1]):
			var c: String = parts[1]
			if key.begins_with("hell_"):
				if nearest(img.get_pixel(270, 22), LIGHT) != c:
					bad_color += 1
					print("  Farbe falsch: %s" % key)
			else:
				if nearest(img.get_pixel(282, 200), DARK) != c:
					bad_color += 1
					print("  Farbe falsch: %s" % key)
	check(missing == 0, "%d Kartenbilder fehlen" % missing)
	check(bad_size == 0, "%d Kartenbilder nicht 300×466" % bad_size)
	check(bad_alpha == 0, "%d Alpha-Prüfpunkte falsch (Ecken transparent, Rand/Mitte deckend)" % bad_alpha)
	check(hashes.size() == keys.size() - missing - bad_size, "Kartenbilder nicht alle verschieden (%d eindeutige)" % hashes.size())
	check(bad_side == 0, "%d Karten mit falscher Seite am Rand" % bad_side)
	check(bad_color == 0, "%d Karten mit falscher Kartenfarbe" % bad_color)
	check(not_imported == 0, "%d Kartenbilder nicht von Godot importiert (tools/godot_import.ps1)" % not_imported)


func _check_web(keys: Array[String]) -> void:
	var web := ProjectSettings.globalize_path("res://").path_join("../webclient")
	var bad := 0
	for key in keys:
		var path := web.path_join("cards/%s.webp" % key)
		var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
		if img == null or img.get_width() != 200 or img.get_height() != 311 or not img.detect_alpha():
			bad += 1
			print("  WebP fehlt/falsch: %s" % key)
	check(bad == 0, "%d WebP-Karten fehlen oder sind nicht 200×311 mit Alpha" % bad)
	var bad_sym := 0
	for c: String in LIGHT + DARK:
		var path := web.path_join("cards/farbe_%s.webp" % c)
		var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
		if img == null or img.get_width() != 96 or img.get_height() != 96:
			bad_sym += 1
	check(bad_sym == 0, "%d Farbsymbole (WebP) fehlen" % bad_sym)
	for f: String in ["BricolageGrotesque.ttf", "Fraunces.ttf", "Fraunces-Italic.ttf", "OFL.txt"]:
		var a := FileAccess.get_file_as_bytes(web.path_join("fonts/" + f))
		var b := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path("res://assets/fonts/" + f))
		check(a.size() > 0 and a == b, "webclient/fonts/%s fehlt oder weicht vom Spiel ab" % f)


func _check_fonts() -> void:
	var axes := {"BricolageGrotesque.ttf": ["wght", "wdth", "opsz"], "Fraunces.ttf": ["wght", "opsz", "SOFT", "WONK"],
		"Fraunces-Italic.ttf": ["wght", "opsz", "SOFT", "WONK"]}
	for f: String in axes:
		var font := FontFile.new()
		var err := font.load_dynamic_font("res://assets/fonts/" + f)
		check(err == OK, "Schrift %s lädt nicht (%d)" % [f, err])
		if err != OK:
			continue
		var vars := font.get_supported_variation_list()
		for ax: String in axes[f]:
			check(vars.has(TextServerManager.get_primary_interface().name_to_tag(ax)), "%s: Achse %s fehlt" % [f, ax])
		for ch: String in "0123456789+?!ÄÖÜäöüß€–„“":
			if not font.has_char(ch.unicode_at(0)):
				check(false, "%s: Zeichen %s fehlt" % [f, ch])
	var lic := FileAccess.get_file_as_string("res://assets/fonts/OFL.txt")
	check(lic.contains("SIL Open Font License") and lic.contains("Bricolage") and lic.contains("Fraunces"), "OFL.txt unvollständig")
	# Kursiv nur Fraunces-Italic; Standardinstanz der Dateien (deshalb immer FontVariation mit opsz 12, siehe B.md)
	for f: String in ["BricolageGrotesque.ttf", "Fraunces.ttf", "Fraunces-Italic.ttf"]:
		var font := FontFile.new()
		if font.load_dynamic_font("res://assets/fonts/" + f) != OK:
			continue
		var italic := (font.get_font_style() & TextServer.FONT_ITALIC) != 0
		check(italic == (f == "Fraunces-Italic.ttf"), "%s: kursiv=%s erwartet %s" % [f, italic, f == "Fraunces-Italic.ttf"])


# WOFF2 im Browser-Client (Plan Abschnitt 8): gleiche Schrift wie die TTF (Achsen, Namen, Laufweite)
func _check_woff2() -> void:
	var web := ProjectSettings.globalize_path("res://").path_join("../webclient/fonts")
	var tag := TextServerManager.get_primary_interface()
	for n: String in ["BricolageGrotesque", "Fraunces", "Fraunces-Italic"]:
		var path := web.path_join(n + ".woff2")
		var bytes := FileAccess.get_file_as_bytes(path)
		check(bytes.size() > 1000 and bytes.slice(0, 4).get_string_from_ascii() == "wOF2", "%s.woff2 fehlt oder ist kein WOFF2" % n)
		var w := FontFile.new()
		var t := FontFile.new()
		var ew := w.load_dynamic_font(path)
		var et := t.load_dynamic_font("res://assets/fonts/%s.ttf" % n)
		check(ew == OK and et == OK, "%s.woff2 lädt in Godot nicht (%d)" % [n, ew])
		if ew != OK or et != OK:
			continue
		var same := w.get_font_name() == t.get_font_name() and w.get_font_style_name() == t.get_font_style_name() \
			and w.get_supported_variation_list() == t.get_supported_variation_list()
		for size: int in [12, 40]:
			var s := "Mau-Mau Flip 0123456789 ÄÖÜß€"
			same = same and w.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size) == t.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		check(same, "%s.woff2 weicht von der TTF ab (Name, Achsen oder Laufweite)" % n)
		check(w.get_supported_variation_list().has(tag.name_to_tag("opsz")), "%s.woff2: Achse opsz fehlt" % n)


func _check_ui() -> void:
	var want := {"logo.png": Vector2i(1600, 900), "logo_klein.png": Vector2i(800, 450), "icon_512.png": Vector2i(512, 512),
		"android_main_192.png": Vector2i(192, 192), "android_adaptive_foreground_432.png": Vector2i(432, 432),
		"android_adaptive_background_432.png": Vector2i(432, 432), "android_adaptive_monochrome_432.png": Vector2i(432, 432),
		"splash.png": Vector2i(1600, 720), "touch_icon_180.png": Vector2i(180, 180)}
	for n: String in ["sortieren", "rueckseiten", "hilfe", "einstellungen", "teilen", "update", "zurueck", "wlan", "qr", "regeln",
			"spieler", "roboter", "start", "mau", "ziehen"]:
		want[n + ".png"] = Vector2i(96, 96)
	for c: String in LIGHT + DARK:
		want["farben/%s.png" % c] = Vector2i(96, 96)
	for f: String in want:
		var img := load_image("res://assets/ui/" + f)
		check(img != null and img.get_size() == want[f], "UI-Grafik %s fehlt oder hat nicht %s" % [f, str(want[f])])
		if img == null:
			continue
		img.convert(Image.FORMAT_RGBA8)
		var s := img.get_size()
		if f.get_file() in ["logo.png", "logo_klein.png", "splash.png", "android_adaptive_background_432.png"]:
			check(img.get_pixel(s.x / 2, s.y / 2).a > 0.99 and img.get_pixel(0, 0).a > 0.99, "%s soll deckend sein" % f)
		elif f.get_file() in ["touch_icon_180.png"]:
			check(img.get_pixel(0, 0).a > 0.99, "%s: iOS braucht deckende Ecken" % f)
		else:
			# Symbole: Ecke transparent, Inhalt vorhanden
			var used := img.get_used_rect()
			check(img.get_pixel(0, 0).a < 0.01 and used.size.x > s.x / 3 and used.size.y > s.y / 3, "%s: transparente Ecke oder Inhalt fehlt" % f)
	# Bediensymbole in Papierfarbe
	var hilfe := load_image("res://assets/ui/hilfe.png")
	if hilfe != null:
		hilfe.convert(Image.FORMAT_RGBA8)
		var p := hilfe.get_pixel(48, 9)   # oberer Rand des Kreises
		check(p.a > 0.9 and Vector3(p.r - PAPER.r, p.g - PAPER.g, p.b - PAPER.b).length() < 0.05, "Bediensymbole nicht in Papierfarbe")


# Farbsymbole: heller Außenrand mit mindestens 3:1 Kontrast zum dunklen Tisch (#1B2040) und zum Nachtgrund
func _check_color_symbols() -> void:
	var table := Color("#1B2040")
	var night := Color("#0A0D20")
	var lows: Array[String] = []
	for c: String in LIGHT + DARK:
		var img := load_image("res://assets/ui/farben/%s.png" % c)
		if img == null:
			lows.append(c + " fehlt")
			continue
		img.convert(Image.FORMAT_RGBA8)
		# Außenkante: deckende Pixel mit einem durchsichtigen Nachbarn
		var sum := Vector3.ZERO
		var n := 0
		for y in range(1, img.get_height() - 1):
			for x in range(1, img.get_width() - 1):
				var px := img.get_pixel(x, y)
				if px.a < 0.9:
					continue
				if img.get_pixel(x - 1, y).a < 0.3 or img.get_pixel(x + 1, y).a < 0.3 or img.get_pixel(x, y - 1).a < 0.3 or img.get_pixel(x, y + 1).a < 0.3:
					sum += Vector3(px.r, px.g, px.b)
					n += 1
		var rim := Color(sum.x / n, sum.y / n, sum.z / n) if n > 0 else Color.BLACK
		var k := minf(contrast(rim, table), contrast(rim, night))
		if n < 40 or k < 3.0:
			lows.append("%s %.1f:1" % [c, k])
	check(lows.is_empty(), "Farbsymbole mit zu schwachem Rand auf dunklem Grund: %s" % str(lows))


# Startbild: die äußersten 2 px exakt #0A0D20 (= boot_splash/bg_color)
func _check_splash() -> void:
	var img := load_image("res://assets/ui/splash.png")
	if img == null:
		check(false, "splash.png fehlt")
		return
	img.convert(Image.FORMAT_RGB8)
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var border: Array[Vector2i] = []
	for x in w:
		for y: int in [0, 1, h - 2, h - 1]:
			border.append(Vector2i(x, y))
	for y in range(2, h - 2):
		for x: int in [0, 1, w - 2, w - 1]:
			border.append(Vector2i(x, y))
	var off := 0
	for p in border:
		var i := (p.y * w + p.x) * 3
		if data[i] != 10 or data[i + 1] != 13 or data[i + 2] != 32:
			off += 1
	check(off == 0, "Startbild: %d Randpixel nicht genau #0A0D20" % off)
	var bg: Color = ProjectSettings.get_setting("application/boot_splash/bg_color", Color.BLACK)
	check(bg.to_html(false).to_upper() == "0A0D20", "boot_splash/bg_color ist #%s statt #0A0D20" % bg.to_html(false))
