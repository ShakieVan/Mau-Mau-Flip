class_name UiFonts
extends RefCounted
# Schriften der Oberfläche (Modul B legt sie in res://assets/fonts/ ab): Bricolage Grotesque für Werte und Text – immer mit
# opsz 12, sonst werden 6 und 9 zu dünn –, Fraunces für Überschriften und „Mau!“. Fehlt eine Datei, gilt die Standardschrift.

const BRICOLAGE := "res://assets/fonts/BricolageGrotesque.ttf"
const FRAUNCES := "res://assets/fonts/Fraunces.ttf"
const FRAUNCES_ITALIC := "res://assets/fonts/Fraunces-Italic.ttf"

# Schriftgrößen (Beta 1.0.1, Nutzer: „fast überall zu klein“): alle Bildschirme und Tischbeschriftungen nehmen ihre Größe von
# hier, statt eigene Zahlen zu streuen. size(name) liefert die Stufe in px (Basis 1600×720) mal Faktor der Einstellung
# „Schriftgröße“ (App.settings "schrift": normal/gross/sehr_gross, je Gerät). Kartenbilder sind davon nicht betroffen.
const SIZES := {
	"mini": 17,          # winzige Abzeichen am Tisch („KI“, Zusatzchips)
	"pille": 19,         # Kartenzahl-Pillen, Punkte, „gleich dran“, Stapelzahl
	"klein": 21,         # kleinste Nebentexte (Unterzeilen, Skalenbeschriftung)
	"hinweis": 22,       # graue Beschreibungen
	"text": 24,          # Fließtext, Auswahlknöpfe
	"knopf": 26,         # Knöpfe (Standard im Thema)
	"name": 25,          # Spielernamen am Tisch
	"zeile": 27,         # fette Zeilenbeschriftung, Namen in Listen
	"hinweisleiste": 25, # Hinweisleiste am Tisch („+1 auf dich – Zieh 2.“)
	"zwischen": 31,      # Zwischenüberschriften
	"start": 32,         # große Startknöpfe
	"abschnitt": 34,     # Überschriften der Abschnitte
	"zahl": 36,          # Zahlenwähler
	"ueberschrift": 39,  # Überschriften der Dialoge
	"dialog": 43,
	"titel": 52,
}
# Faktor je Stufe der Einstellung „Schriftgröße“
const LEVELS := {"normal": 1.0, "gross": 1.15, "sehr_gross": 1.3}
const LEVEL_NAMES := [["normal", "Normal"], ["gross", "Groß"], ["sehr_gross", "Sehr groß"]]
const _SIZE_KEYS := ["font_size", "normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]

static var _cache: Dictionary = {}
static var scale := 1.0
static var level := "normal"


# Schriftgröße einer Stufe (siehe SIZES) in px, mit Faktor der Einstellung
static func size(name: String) -> int:
	return px(float(SIZES.get(name, 24)))


# Beliebige Grundgröße mit dem Faktor der Einstellung (für Größen, die aus Maßen abgeleitet sind)
static func px(base: float) -> int:
	return maxi(1, roundi(base * scale))


static func factor(lvl: String) -> float:
	return float(LEVELS.get(lvl, 1.0))


# Stufe setzen: Thema anpassen und, wenn root gegeben ist, alle schon gebauten Beschriftungen darunter umrechnen und neu
# zeichnen (wirkt live). Knoten mit Methode on_font_scale() bauen ihren Text selbst neu. true = Faktor geändert.
static func set_level(lvl: String, root: Node = null) -> bool:
	if not LEVELS.has(lvl):
		lvl = "normal"
	var old := scale
	level = lvl
	scale = factor(lvl)
	UiTheme.apply_scale(UiTheme.get_theme())
	if is_equal_approx(old, scale):
		return false
	if root != null:
		rescale_tree(root, old)
	return true


# Vorhandene Größen-Overrides von old_scale auf den aktuellen Faktor umrechnen (Grundgröße im Meta, damit nichts wandert)
static func rescale_tree(n: Node, old_scale: float) -> void:
	if n is Control:
		var c := n as Control
		for k in _SIZE_KEYS:
			if not c.has_theme_font_size_override(k):
				continue
			var cur := c.get_theme_font_size(k)
			var meta: String = "fs_" + str(k)
			var base := float(cur) / old_scale
			if c.has_meta(meta):
				var m: Vector2 = c.get_meta(meta)
				if roundi(m.y) == cur:
					base = m.x
			var v := px(base)
			c.set_meta(meta, Vector2(base, v))
			c.add_theme_font_size_override(k, v)
	if n is CanvasItem:
		(n as CanvasItem).queue_redraw()
	if n.has_method("on_font_scale"):
		n.call("on_font_scale")
	for ch in n.get_children():
		rescale_tree(ch, old_scale)


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
