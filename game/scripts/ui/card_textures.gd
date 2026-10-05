class_name CardTextures
extends RefCounted
# Kartenbilder laden (docs/BETA1_PLAN.md Abschnitt 3): res://assets/cards/<schlüssel>.png, 300×466 px mit transparenten Ecken.
# Zwischenspeicher je Schlüssel. Fehlt ein Bild (z. B. bevor Modul B die Karten erzeugt hat), entsteht ein Platzhalter in der
# Kartenfarbe, damit Oberfläche und Tests trotzdem laufen.

const DIR := "res://assets/cards/"
const SIZE := Vector2i(300, 466)
const BACK := "rueckseite"

const COLORS := {
	"rot": Color("#B3202A"), "gelb": Color("#FFDD33"), "gruen": Color("#43B05C"), "blau": Color("#2A5BD7"),
	"pink": Color("#FF9ECF"), "tuerkis": Color("#00838F"), "orange": Color("#FF6F00"), "lila": Color("#4527A0"),
}
const PAPER := Color("#F4EADA")
const NIGHT := Color("#0A0D20")

static var _cache: Dictionary = {}


static func path_for(key: String) -> String:
	return DIR + key + ".png"


static func has_image(key: String) -> bool:
	return ResourceLoader.exists(path_for(key))


static func get_texture(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	var path := path_for(key)
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		tex = _placeholder(key)
	_cache[key] = tex
	return tex


static func clear_cache() -> void:
	_cache.clear()


# Farbe eines Gesichtsschlüssels ("hell_rot_7" → "rot"); Joker und Rückseite → "".
static func color_of(key: String) -> String:
	var parts := key.split("_")
	if parts.size() >= 3 and COLORS.has(parts[1]):
		return parts[1]
	return ""


static func side_of(key: String) -> String:
	return "hell" if key.begins_with("hell_") else ("dunkel" if key.begins_with("dunkel_") else "")


# Platzhalter: Papier- bzw. Nachtkarte mit Farbfeld, halbe Auflösung reicht.
static func _placeholder(key: String) -> Texture2D:
	var w := SIZE.x / 2
	var h := SIZE.y / 2
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var dark := side_of(key) == "dunkel" or key == BACK
	var base := NIGHT if dark else PAPER
	img.fill(Color(0, 0, 0, 0))
	var col_name := color_of(key)
	var field: Color = COLORS[col_name] if col_name != "" else (Color("#2A2350") if dark else Color("#E9DCC4"))
	var r := 12
	for y in h:
		for x in w:
			# abgerundete Ecken
			var cx := clampi(x, r, w - 1 - r)
			var cy := clampi(y, r, h - 1 - r)
			if Vector2(x - cx, y - cy).length() > r:
				continue
			var inner := x >= 10 and x < w - 10 and y >= 10 and y < h - 10
			img.set_pixel(x, y, field if inner else base)
	return ImageTexture.create_from_image(img)
