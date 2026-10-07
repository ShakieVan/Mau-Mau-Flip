class_name UiPalette
extends RefCounted
# Farben der Oberfläche nach Entwurf A „Papier & Neon“ (art/entwurf/a-papier-neon/README.md): Kartenfarben je Seite mit Namen
# und Formsymbol, Papier/Druckfarbe/Nacht, Avatarfarben. Tag = helle Seite (Papier, Druckfarbe), Nacht = dunkle Seite (Neon).

const PAPER := Color("#F4EADA")
const PAPER_D := Color("#E6D7BC")      # Papierkante
const CREAM := Color("#FFF7E8")
const INK := Color("#211B2C")          # Druckfarbe
const NIGHT := Color("#0A0D20")
const NIGHT_HI := Color("#161C3F")
const NIGHT_PANEL := Color("#1B2147")
const MOON := Color("#F4F0FF")
const RING := Color("#9A86FF")         # Richtungsring (Lavendel)
const MUTED_NIGHT := Color("#DCD7F4")  # Nebentext auf Nacht (1.0.1 heller: mehr Kontrast)
const MUTED_DAY := Color("#4F4459")    # Nebentext auf Papier (1.0.1 dunkler: mehr Kontrast)
const TURN := Color("#FFD65A")         # Zugmarke (warmes Gelb)
const ALERT := Color("#E5484D")        # Strafe/Erwischt (kein großflächiges Rot)

const LIGHT_COLORS: Array[String] = ["rot", "gelb", "gruen", "blau"]
const DARK_COLORS: Array[String] = ["pink", "tuerkis", "orange", "lila"]

const FILL := {
	"rot": Color("#B3202A"), "gelb": Color("#FFDD33"), "gruen": Color("#43B05C"), "blau": Color("#2A5BD7"),
	"pink": Color("#FF9ECF"), "tuerkis": Color("#00838F"), "orange": Color("#FF6F00"), "lila": Color("#4527A0"),
}
# Leuchtfarbe für Ringe, Wellen und Strahlen: hell = kräftige Fläche, dunkel = Neon (Lila heller, sonst versinkt es im Nachtgrund)
const GLOW := {
	"rot": Color("#E0403F"), "gelb": Color("#FFD21F"), "gruen": Color("#4CC46A"), "blau": Color("#3F74F2"),
	"pink": Color("#FFB3DC"), "tuerkis": Color("#19C3CF"), "orange": Color("#FF8A24"), "lila": Color("#8A6BFF"),
}
const NAMES := {
	"rot": "Rot", "gelb": "Gelb", "gruen": "Grün", "blau": "Blau",
	"pink": "Pink", "tuerkis": "Türkis", "orange": "Orange", "lila": "Lila",
}
const SYMBOLS := {
	"rot": "flamme", "gelb": "sonne", "gruen": "klee", "blau": "kristall",
	"pink": "herz", "tuerkis": "welle", "orange": "laterne", "lila": "stern",
}
# Avatarfarben je Platz (hell genug für dunkle Initialen)
const AVATAR: Array[Color] = [
	Color("#FF99CC"), Color("#4CC46A"), Color("#FFDD33"), Color("#7FB2FF"), Color("#FF9F5A"),
	Color("#B9A3FF"), Color("#5ED6D0"), Color("#F2C6A0"), Color("#C8E66B"), Color("#FF8A8A"),
]


static func colors_of(side: String) -> Array[String]:
	return DARK_COLORS if side == "dunkel" else LIGHT_COLORS


static func side_of_color(color: String) -> String:
	return "dunkel" if DARK_COLORS.has(color) else "hell"


static func fill(color: String) -> Color:
	return FILL.get(color, Color("#8A8597"))


static func glow(color: String) -> Color:
	return GLOW.get(color, RING)


static func color_name(color: String) -> String:
	return NAMES.get(color, color.capitalize())


static func symbol_of(color: String) -> String:
	return SYMBOLS.get(color, "")


static func avatar(seat: int) -> Color:
	return AVATAR[posmod(seat, AVATAR.size())]


# Lesbare Schriftfarbe auf einer Fläche (Druckfarbe oder Papier)
static func text_on(bg: Color) -> Color:
	return INK if bg.get_luminance() > 0.45 else PAPER


# Oberflächenfarben nach Tageszeit (0 = Tag/Papier, 1 = Nacht). Der Wechsel ist steil (Mitte des Flips), damit Schrift nie
# grau auf Dämmerungsgrund steht.
static func ui_mix(night: float) -> float:
	return smoothstep(0.4, 0.6, night)


static func ui_text(night: float) -> Color:
	return INK.lerp(PAPER, ui_mix(night))


static func ui_muted(night: float) -> Color:
	return MUTED_DAY.lerp(MUTED_NIGHT, ui_mix(night))


static func ui_line(night: float) -> Color:
	return Color(INK, 0.28).lerp(Color(PAPER, 0.35), ui_mix(night))


static func ui_fill(night: float) -> Color:
	return Color(INK, 0.06).lerp(Color(PAPER, 0.10), ui_mix(night))


static func ring_color(night: float) -> Color:
	return Color("#B07A3C").lerp(RING, clampf(night, 0.0, 1.0))
