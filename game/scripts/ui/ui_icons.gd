class_name UiIcons
extends RefCounted
# Symbole als kleine SVGs, zur Laufzeit gerastert (Image.load_svg_from_string, ThorVG) und je Größe/Farbe zwischengespeichert.
# Die Formsymbole der Farben stammen aus dem Kartengenerator (art/entwurf/a-papier-neon/quelle/mmf.js, Box 100×100):
# Flamme, Sonne, Kleeblatt, Kristall (hell) und Herz, Welle, Laterne, Stern (dunkel). Dazu einige Bedienungssymbole.
# main = Hauptfarbe, cut = Aussparung/Detail (meist die Grundfarbe dahinter).

const CAT_HEAD := "M13 62C13 49 16 41 21 35L23 9C23 6 26 5 28 7L44 25C48 24 52 24 56 25L72 7C74 5 77 6 77 9L79 35C84 41 87 49 87 62C87 82 71 94 50 94C29 94 13 82 13 62Z"

static var _cache: Dictionary = {}


# Formsymbol einer Kartenfarbe ("rot" … "lila")
static func symbol(color_key: String, px: int, main := Color(0, 0, 0, 0), cut := UiPalette.CREAM) -> Texture2D:
	var m := main if main.a > 0.0 else UiPalette.fill(color_key)
	return icon(UiPalette.symbol_of(color_key), px, m, cut)


static func icon(name: String, px: int, main: Color, cut := UiPalette.CREAM) -> Texture2D:
	var key := "%s|%d|%s|%s" % [name, px, main.to_html(), cut.to_html()]
	if _cache.has(key):
		return _cache[key]
	var body := _body(name, "#" + main.to_html(false), main.a, "#" + cut.to_html(false), cut.a)
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 100 100\">%s</svg>" % [px, px, body]
	var img := Image.new()
	var tex: Texture2D = null
	if body != "" and img.load_svg_from_string(svg, 1.0) == OK:
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
	else:
		var empty := Image.create(maxi(px, 1), maxi(px, 1), false, Image.FORMAT_RGBA8)
		tex = ImageTexture.create_from_image(empty)
	_cache[key] = tex
	return tex


static func clear_cache() -> void:
	_cache.clear()


static func _fill(d: String, col: String, a: float, extra := "") -> String:
	return "<path d=\"%s\" fill=\"%s\" fill-opacity=\"%.3f\" %s/>" % [d, col, a, extra]


static func _line(d: String, col: String, a: float, w: float, cap := "round") -> String:
	return "<path d=\"%s\" fill=\"none\" stroke=\"%s\" stroke-opacity=\"%.3f\" stroke-width=\"%.1f\" stroke-linecap=\"%s\" stroke-linejoin=\"round\"/>" % [d, col, a, w, cap]


static func _polar(cx: float, cy: float, r: float, deg: float) -> Vector2:
	var a := deg_to_rad(deg - 90.0)
	return Vector2(cx + r * cos(a), cy + r * sin(a))


static func _star(cx: float, cy: float, n: int, ro: float, ri: float) -> String:
	var d := ""
	for i in n * 2:
		var p := _polar(cx, cy, ri if i % 2 == 1 else ro, i * 180.0 / n)
		d += ("L" if i > 0 else "M") + "%.1f %.1f" % [p.x, p.y]
	return d + "Z"


static func _body(name: String, m: String, ma: float, c: String, ca: float) -> String:
	match name:
		"flamme":
			return _fill("M50 3C59 19 81 33 81 61C81 83 66 97 50 97C34 97 19 83 19 61C19 46 27 36 36 28C36 40 40 48 47 51C43 37 43 19 50 3Z", m, ma) \
				+ _fill("M51 55C57 63 63 69 63 78C63 87 57 92 50 92C43 92 38 87 38 79C38 71 44 64 51 55Z", c, ca)
		"sonne":
			var s := "<circle cx=\"50\" cy=\"50\" r=\"21\" fill=\"%s\" fill-opacity=\"%.3f\"/>" % [m, ma]
			var d := ""
			for i in 8:
				var a := i * 45.0
				var p1 := _polar(50, 50, 30, a - 9)
				var p2 := _polar(50, 50, 30, a + 9)
				var p3 := _polar(50, 50, 48, a)
				d += "M%.1f %.1fL%.1f %.1fL%.1f %.1fZ" % [p1.x, p1.y, p3.x, p3.y, p2.x, p2.y]
			return s + _fill(d, m, ma)
		"klee":
			var heart := "M0 0C-7 -6 -25 -14 -25 -29C-25 -39 -17 -45 -9 -45C-4 -45 0 -41 0 -36C0 -41 4 -45 9 -45C17 -45 25 -39 25 -29C25 -14 7 -6 0 0Z"
			var out := _line("M50 54C52 70 58 82 70 95", m, ma, 8)
			for a in [0, 120, 240]:
				out += _fill(heart, m, ma, "transform=\"translate(50 52) rotate(%d)\"" % a)
			return out
		"kristall":
			return _fill("M28 13H72L93 38L50 95L7 38Z", m, ma) \
				+ _line("M7 38H93M28 13L39 38L50 95M72 13L61 38L50 95M39 38L50 13L61 38", c, ca, 3.2)
		"herz":
			return _fill("M50 91C43 85 7 63 7 36C7 20 19 9 32 9C40 9 46 13 50 21C54 13 60 9 68 9C81 9 93 20 93 36C93 63 57 85 50 91Z", m, ma)
		"welle":
			return _line("M8 36C19 20 30 20 39 34C48 48 59 48 70 34C79 22 88 22 94 30", m, ma, 13) \
				+ _line("M8 68C19 52 30 52 39 66C48 80 59 80 70 66C79 54 88 54 94 62", m, ma, 13)
		"laterne":
			return "<circle cx=\"50\" cy=\"13\" r=\"9\" fill=\"none\" stroke=\"%s\" stroke-opacity=\"%.3f\" stroke-width=\"6\"/>" % [m, ma] \
				+ _fill("M33 20H67V31H33Z", m, ma) + _fill("M31 31H69L84 55L69 82H31L16 55Z", m, ma) + _fill("M36 82H64V93H36Z", m, ma) \
				+ _fill("M50 42C55 50 59 55 59 61C59 67 55 71 50 71C45 71 41 67 41 61C41 55 45 50 50 42Z", c, ca)
		"stern":
			var st := _star(50, 54, 5, 46, 20)
			return _fill(st, m, ma) + _line(st, m, ma, 6)
		"katze":
			# schlafender Katzenkopf (Aussetzen)
			return _fill(CAT_HEAD, m, ma) + _line("M26 60Q33 67 41 60M59 60Q67 67 74 60", c, ca, 5.5) + _fill("M45 69H55L50 75Z", c, ca)
		"katze_wach":
			return _fill(CAT_HEAD, m, ma) + _fill("M27 56a7 8 0 1 0 14 0a7 8 0 1 0 -14 0ZM59 56a7 8 0 1 0 14 0a7 8 0 1 0 -14 0Z", c, ca) \
				+ _fill("M45 69H55L50 75Z", c, ca)
		"pfote":
			return _fill("M50 50C64 50 80 64 80 78C80 89 72 94 64 94C57 94 54 90 50 90C46 90 43 94 36 94C28 94 20 89 20 78C20 64 36 50 50 50Z", m, ma) \
				+ _fill("M12 40a10 13 -20 1 0 20 -6a10 13 -20 1 0 -20 6Z", m, ma) + _fill("M30 20a11 14 -6 1 0 22 0a11 14 -6 1 0 -22 0Z", m, ma) \
				+ _fill("M48 20a11 14 6 1 0 22 0a11 14 6 1 0 -22 0Z", m, ma) + _fill("M68 34a10 13 20 1 0 20 6a10 13 20 1 0 -20 -6Z", m, ma)
		"sortieren":
			# Pfeil nach unten links, Pfeil nach oben rechts
			return _line("M32 16V84M14 66L32 84L50 66", m, ma, 9) + _line("M68 84V16M50 34L68 16L86 34", m, ma, 9)
		"rueckseiten":
			return "<rect x=\"14\" y=\"22\" width=\"44\" height=\"62\" rx=\"8\" fill=\"none\" stroke=\"%s\" stroke-opacity=\"%.3f\" stroke-width=\"7\"/>" % [m, ma] \
				+ "<rect x=\"40\" y=\"12\" width=\"44\" height=\"62\" rx=\"8\" fill=\"%s\" fill-opacity=\"%.3f\" stroke=\"%s\" stroke-opacity=\"%.3f\" stroke-width=\"7\"/>" % [c, ca, m, ma]
		"pfeil":
			return _line("M10 50H84M58 22L86 50L58 78", m, ma, 12)
		"flip":
			return "<circle cx=\"50\" cy=\"50\" r=\"44\" fill=\"%s\" fill-opacity=\"%.3f\"/>" % [m, ma] \
				+ _fill("M81.1 18.9A44 44 0 0 1 18.9 81.1Z", c, ca) \
				+ "<circle cx=\"50\" cy=\"50\" r=\"44\" fill=\"none\" stroke=\"%s\" stroke-opacity=\"%.3f\" stroke-width=\"6\"/>" % [m, ma]
		"haken":
			return _line("M18 52L40 74L84 26", m, ma, 12)
		"kreuz":
			return _line("M24 24L76 76M76 24L24 76", m, ma, 12)
		"stapel":
			return "<rect x=\"30\" y=\"10\" width=\"46\" height=\"66\" rx=\"7\" fill=\"%s\" fill-opacity=\"%.3f\"/>" % [c, ca] \
				+ "<rect x=\"30\" y=\"10\" width=\"46\" height=\"66\" rx=\"7\" fill=\"none\" stroke=\"%s\" stroke-opacity=\"%.3f\" stroke-width=\"6\"/>" % [m, ma] \
				+ "<rect x=\"18\" y=\"24\" width=\"46\" height=\"66\" rx=\"7\" fill=\"%s\" fill-opacity=\"%.3f\"/>" % [m, ma]
	return ""
