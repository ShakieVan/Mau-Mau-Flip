class_name UiFonts
extends RefCounted
# Schriften der Oberfläche (Modul B legt sie in res://assets/fonts/ ab): Bricolage Grotesque für Werte und Text – immer mit
# opsz 12, sonst werden 6 und 9 zu dünn –, Fraunces für Überschriften und „Mau!“. Fehlt eine Datei, gilt die Standardschrift.

const BRICOLAGE := "res://assets/fonts/BricolageGrotesque.ttf"
const FRAUNCES := "res://assets/fonts/Fraunces.ttf"
const FRAUNCES_ITALIC := "res://assets/fonts/Fraunces-Italic.ttf"

static var _cache: Dictionary = {}


# Text und Werte: weight 200–800, width 75–100 (schmal für Eckindex und Zahlen)
static func text(weight := 600, width := 100.0) -> Font:
	return _variation(BRICOLAGE, {"wght": weight, "wdth": width, "opsz": 12})


# Überschriften: Fraunces aufrecht oder kursiv; soft 0–100 rundet die Formen („Mau!“ mit 100)
static func title(weight := 800, italic := false, soft := 50.0, opsz := 72.0) -> Font:
	return _variation(FRAUNCES_ITALIC if italic else FRAUNCES, {"wght": weight, "opsz": opsz, "SOFT": soft, "WONK": 0})


static func mau() -> Font:
	return title(900, true, 100.0, 72.0)


static func has_fonts() -> bool:
	return ResourceLoader.exists(BRICOLAGE) and ResourceLoader.exists(FRAUNCES)


static func _variation(path: String, axes: Dictionary) -> Font:
	var key := path + str(axes)
	if _cache.has(key):
		return _cache[key]
	var font: Font = ThemeDB.fallback_font
	if ResourceLoader.exists(path):
		var base := load(path) as FontFile
		if base != null:
			var fv := FontVariation.new()
			fv.base_font = base
			fv.variation_opentype = axes
			font = fv
	_cache[key] = font
	return font
