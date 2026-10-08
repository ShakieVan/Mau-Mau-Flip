extends SceneTree

# Modul E2 – Vertrag zwischen Browser-Client „Lite“ (webclient/) und echtem Gastgeber, headless und ohne Browser.
#  1. Was der Client kennt, wird aus seinen Quellen gelesen (eine Quelle der Wahrheit): Phasen, hints-Felder und Ereignisse aus
#     webclient/autotest.js, Ereignis-Effekte (case '…') aus tisch.js, gesendete Aktionen aus app.js/tisch.js.
#  2. Bot-Partien mit zufälligen Regeln (MauGame + MauBot): Jede Sicht jedes Platzes hat die Felder und Typen, die der Client nutzt;
#     jede Phase und jedes Ereignis ist dem Client bekannt; jede Aktion des Clients kennt das Regelwerk; NetProtocol lässt sie durch.
#  3. NetServer liefert eine aus webclient/ gepackte Zip aus: Seite, alle eingebundenen Skripte, Mau-Töne (mau, mau_mau als m4a/ogg),
#     Schrift, Kartenbild, Katzenbild – mit passenden MIME-Typen; sfx/index.json ist gültig, nennt „mau“, „mau_mau“ und die Spieltöne
#     der App (karte, ziehen, mischen, flip, dran, fehler, sieg), jede genannte Datei liegt vor (m4a fürs iPhone, ogg als Rückfall).
#  4. Hausregeln (Kartentausch, Glücksspiel, Farbe mit ablegen): Bot-Partien mit allen drei Hausregeln; view.gamble und
#     hints.can_stake/can_press genau dann, wenn gamble_cards an ist; alle neuen Ereignisse kommen vor und sind dem Client bekannt;
#     Kartenbilder für alle 128 Gesichter; Kartenhilfe, Mock und die Einstellung „Spielbare Karten hervorheben“ im Client.
#  5. Tag und Nacht am Tisch (pruefe_tag_nacht): Tag = Papier mit Sonne wie in der App, Plattform und Schrift je Seite,
#     Schriftkontrast ≥ 4,5:1, weicher Wechsel beim Flip.
# Der Ende-zu-Ende-Test mit echtem Chrome ist tools/webtest/web_e2e.ps1 (Gastgeber game/tests/web_host.gd).

const PORT := 24875
var ok := 0
var fails := 0
var web_dir := ""


func check(cond: bool, msg: String) -> void:
	if cond:
		ok += 1
	else:
		fails += 1
		print("FAIL: ", msg)


func _initialize() -> void:
	call_deferred("run")


func read_web(name: String) -> String:
	return FileAccess.get_file_as_string(web_dir.path_join(name))


# Liste von Zeichenketten aus „const NAME = [ '…', … ];“
func js_list(src: String, name: String) -> Array:
	var re := RegEx.create_from_string("const " + name + " = \\[([^\\]]*)\\]")
	var m := re.search(src)
	if m == null:
		return []
	var out: Array = []
	for s in RegEx.create_from_string("'([a-z_]+)'").search_all(m.get_string(1)):
		out.append(s.get_string(1))
	return out


# Schlüssel und Typen aus „const NAME = { key: 'typ', … };“
func js_types(src: String, name: String) -> Dictionary:
	var re := RegEx.create_from_string("const " + name + " = \\{([^}]*)\\}")
	var m := re.search(src)
	var out := {}
	if m == null:
		return out
	for s in RegEx.create_from_string("([a-z_]+): '([a-z]+)'").search_all(m.get_string(1)):
		out[s.get_string(1)] = s.get_string(2)
	return out


func js_type(v) -> String:
	match typeof(v):
		TYPE_ARRAY:
			return "array"
		TYPE_DICTIONARY:
			return "object"
		TYPE_BOOL:
			return "boolean"
		TYPE_INT, TYPE_FLOAT:
			return "number"
		TYPE_STRING:
			return "string"
	return "null"


# Inhalt des ersten CSS-Blocks, der mit sel beginnt (bis zur schließenden Klammer)
func css_block(css: String, sel: String) -> String:
	var i := css.find(sel)
	if i < 0:
		return ""
	return css.substr(i, css.find("}", i) - i)


# Wert der CSS-Variablen „--name: …;“ in einem Block
func css_var(block: String, name: String) -> String:
	var m := RegEx.create_from_string("--" + name + ":\\s*([^;]+);").search(block)
	return m.get_string(1).strip_edges() if m != null else ""


# Kontrast nach WCAG 2 (relative Luminanz aus linearem sRGB)
func kontrast(a: Color, b: Color) -> float:
	var la := a.srgb_to_linear()
	var lb := b.srgb_to_linear()
	var ya := 0.2126 * la.r + 0.7152 * la.g + 0.0722 * la.b
	var yb := 0.2126 * lb.r + 0.7152 * lb.g + 0.0722 * lb.b
	return (maxf(ya, yb) + 0.05) / (minf(ya, yb) + 0.05)


# Tisch im Browser bei Tag (helle Seite) und Nacht wie in der App (Nutzerbefund 06.10.2026: Tag war dunkel): Papier mit Sonne
# oben links (Farben und Lage aus table_background.gdshader), helle Karton-Plattform mit Druckfarben-Kontur, Schrift in
# Druckfarbe mit ausreichendem Kontrast, weicher Wechsel beim Flip über tisch.js setzeSeite.
# 0.1.4 (Browser): volles Logo, Rahmen statt „Bitte quer halten“, Mond, Strahlenkranz und Denkblase, eigene Kartenzahl,
# Strahlen am Rundenende, Flip-Überraschung (Regeltext, Kartenhilfe, Stempel, Mock, Selbsttest)
func pruefe_014(css: String, tisch: String, karten: String, mock: String, autotest: String, app: String, seite: String) -> void:
	check(seite.contains("bilder/logo.webp") and FileAccess.file_exists(web_dir.path_join("bilder/logo.webp")) and css.contains(".start-logo.mit-bild"),
		"Startseite zeigt das volle Logo (Karten und „Mau!“-Blase)")
	check(app.contains("classList.toggle('rahmen'") and css.contains("body.rahmen #tisch") and css.contains("body.rahmen-hinweis[data-screen=\"tisch\"] .quer")
			and not css.contains("body.hoch[data-screen=\"tisch\"] .quer"),
		"Unpassendes Fenster: Tisch im Rahmen, Hinweis nur im Überstand")
	check(tisch.contains("class=\"mond\"") and css.contains("#tisch[data-seite=\"dunkel\"] .himmel .mond"), "Mond oben rechts auf der dunklen Seite")
	check(tisch.contains("class=\"kranz\"") and css.contains(".gg.dran .kranz") and css.contains("#tisch[data-seite=\"dunkel\"] { --kr-kern")
			and css.contains(".gg.dran .denk") and css.contains(" 5s both") and css.contains("body.reduziert .gg.dran .kranz"),
		"Wer dran ist: Strahlenkranz (Tag/Nacht), Denkblase nach 5 s, reduziert ohne Drehen")
	check(tisch.contains("ichZahl") and css.contains(".ich-zahl") and css.contains(".ich-kranz.an"), "Eigene Kartenzahl und Strahlen hinter der eigenen Hand")
	check(css.contains("#runde::before") and css.contains("body.reduziert #runde::before"), "Rundenende mit sanften Strahlen (voll und reduziert)")
	check(karten.contains("flip_surprise") and karten.contains("Flip-Überraschung") and tisch.contains("case 'flip_surprise'") and tisch.contains("stempel(")
			and css.contains(".stempel") and mock.contains("e: 'flip_surprise'") and js_list(autotest, "EREIGNISSE").has("flip_surprise"),
		"Flip-Überraschung: Regeltext, Kartenhilfe, Stempel, Mock und Selbsttest")


# Beta 1.0.2: „In der App spielen“ (Android, App-Link maumauflip://join?h=&p=) und „Regeln“/„So geht's“ im Spielmenü
func pruefe_102(css: String, karten: String, app: String, seite: String) -> void:
	check(seite.contains("id=\"app-link\"") and seite.contains(">In der App spielen<") and seite.contains("Noch nicht installiert? Dann holst du sie")
			and seite.contains("Die App ist noch nicht installiert – hier kannst du sie laden.") and seite.contains("href=\"/apk\""),
		"Startseite: Knopf „In der App spielen“ mit Zusatz, APK-Bereich mit Hinweis darunter")
	check(app.contains("'intent://join?h='") and app.contains("#Intent;scheme=maumauflip;package=de.maumauflip.game;S.browser_fallback_url=")
			and app.contains("'/?app=1'") and app.contains("params.get('app') === '1'") and app.contains("$('#app-spielen').hidden = !geht")
			and app.contains("const geht = IST_ANDROID"),
		"App-Link: Intent nur auf Android, Rückfall auf ?app=1 klappt den APK-Bereich auf")
	check(seite.contains("id=\"menue-regeln\"") and seite.contains("id=\"menue-sogehts\"") and seite.contains("id=\"regeln\"") and seite.contains("id=\"sogehts\"")
			and app.contains("M.Karten.besondereKarten(r)") and karten.contains("function besondereKarten(") and css.contains(".rk-bild")
			and css.contains(".sogehts-liste"),
		"Spielmenü: „Regeln“ (aktive Regeln und besondere Karten) und „So geht's“")
	for k in ["Karte lange drücken", "Ablage durchsehen", "tipp auf „Mau!“"]:
		check(seite.contains(k), "„So geht's“ erklärt: %s" % k)
	for k in ["hell_rot_tausch", "hell_gluecksspiel", "hell_ablegen_joker", "dunkel_farbjagd"]:
		check(karten.contains("'%s'" % k) and FileAccess.file_exists(web_dir.path_join("cards/%s.webp" % k)), "Besondere Karten: Bild für „%s“" % k)


func pruefe_tag_nacht(css: String, tisch: String) -> void:
	var shader := FileAccess.get_file_as_string("res://assets/shaders/table_background.gdshader")
	var tag_grund := RegEx.create_from_string("day = mix\\(vec3\\(([0-9.]+), ([0-9.]+), ([0-9.]+)\\)").search(shader)
	var css_grund := RegEx.create_from_string("\\.himmel \\.tag \\{ background: radial-gradient\\([^#]*(#[0-9A-Fa-f]{6})").search(css)
	var gleich := false
	if tag_grund != null and css_grund != null:
		var a := Color(float(tag_grund.get_string(1)), float(tag_grund.get_string(2)), float(tag_grund.get_string(3)))
		var b := Color(css_grund.get_string(1))
		gleich = absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01
	check(gleich, "Tag im Browser = Papier wie in der App (Tischgrund %s, Shader %s)" % [css_grund.get_string(1) if css_grund else "?", tag_grund.get_string(0) if tag_grund else "?"])
	check(not css.contains("#303C70"), "kein dunkelblauer Tagshimmel mehr (#303C70)")
	check(tisch.contains("<i class=\"sonne\"></i>") and css.contains(".himmel .sonne { position: absolute; left: 7%; top: 3%;")
		and shader.contains("vec2 sun = vec2(size.x * 0.07, size.y * (0.03"), "Sonne oben links an derselben Stelle wie in der App")
	check(css.contains(".himmel .tag::before") and css.contains("repeating-conic-gradient(from 0deg at 7% 3%"), "Sonnenstrahlen gehen von der Sonne aus")
	# Plattform: Tag heller Karton mit Druckfarben-Kontur und Winkeln in Druckfarbe, Nacht Glas mit Neon (zwei Winkel-Ebenen)
	check(css.contains(".pf-rand { fill: none; stroke: #211B2C;") and css.contains("#tisch[data-seite=\"dunkel\"] .pf-rand { stroke: #B7A8FF;")
		and css.contains(".pf .s1 { stop-color: #FFFAEF; }") and css.contains("#tisch[data-seite=\"dunkel\"] .pf .s1 { stop-color: #2C2266; }"),
		"Plattform: Tag Karton mit Kontur in Druckfarbe, Nacht dunkles Glas mit Neonkante")
	check(css.contains(".richtung .w b::before") and css.contains("stroke='%23211B2C'") and css.contains("#tisch[data-seite=\"dunkel\"] .richtung .w b::after { opacity: 1; }"),
		"Plattform-Winkel: Tag in Druckfarbe, Nacht Neon, als zwei überblendete Ebenen")
	# Schriftfarben und Kontrast (WCAG ≥ 4,5:1) auf Papier (Mitte und Rand des Verlaufs) bzw. Nachtgrund
	var tag := css_block(css, "#tisch { overflow: hidden;")
	var nacht := css_block(css, "#tisch[data-seite=\"dunkel\"] {")
	check(tag != "" and nacht != "" and Color(css_var(tag, "t-text")).is_equal_approx(UiPalette.INK) and Color(css_var(nacht, "t-text")).is_equal_approx(UiPalette.PAPER),
		"Schrift am Tisch: Tag Druckfarbe, Nacht Papier (UiPalette.INK/PAPER)")
	var schwach: Array = []
	for paar in [[tag, ["t-text", "t-muted", "t-zug-ich"], ["#F5ECDC", "#E0CDAF"]], [nacht, ["t-text", "t-muted", "t-zug"], ["#140F36", "#2A1C5E"]]]:
		for v in paar[1]:
			for grund in paar[2]:
				var k := kontrast(Color(css_var(paar[0], v)), Color(grund))
				if k < 4.5:
					schwach.append("%s auf %s: %.2f" % [v, grund, k])
		for p in [["t-dran-fg", "t-dran"], ["t-chip-fg", "t-chip"]]:
			var k := kontrast(Color(css_var(paar[0], p[0])), Color(css_var(paar[0], p[1])))
			if k < 4.5:
				schwach.append("%s auf %s: %.2f" % [p[0], p[1], k])
	check(schwach.is_empty(), "Schriftkontrast am Tisch mindestens 4,5:1 bei Tag und Nacht %s" % str(schwach))
	# Wechsel: eine Stelle setzt die Seite, Himmel blendet über (Nacht über Tag, Dämmerung), Schrift und Knöpfe nur beim Wechsel
	check(tisch.contains("setzeSeite(seite, sofort) {") and tisch.count("t.setzeSeite(e.side)") == 2 and not tisch.contains("dataset.seite = e.side")
		and tisch.contains("this.setzeSeite(v.side, !alt || (typeof v.round === 'number'"), "tisch.js: Seite nur über setzeSeite (Sicht und Flip), erstes Bild einer Partie und neue Runde sofort")
	check(css.contains(".himmel .nacht { opacity: 0; transition: opacity") and css.contains("#tisch[data-seite=\"dunkel\"] .himmel .tag { opacity: 0;")
		and css.contains(".himmel.wechsel .daemmerung") and css.contains("#tisch.wechselt .stapelzahl") and css.contains("#tisch.sofort"),
		"Flip blendet Himmel, Plattform, Schrift und Knöpfe weich über (erstes Bild ohne Überblenden)")
	pruefe_flip_lesbar(css, tisch)
	pruefe_tag_details(css, tisch)


# Prüfung 06.10.2026: Schrift war mitten im Flip 0,3–0,4 s lang unlesbar (Himmel dunkelte früh, Schrift folgte einer flachen
# Kurve). Jetzt: Himmel und Plattform mit derselben symmetrischen S-Kurve, Dämmerung auf halbem Weg am stärksten, Schrift und
# alles mit eigenen Tagesfarben wechselt genau dort (steps), dazwischen ein Schein in der Gegenfarbe um die Schrift.
func pruefe_flip_lesbar(css: String, tisch: String) -> void:
	var tisch_block := css_block(css, "#tisch { overflow: hidden;")
	var wd := css_var(tisch_block, "wd")
	var ms := RegEx.create_from_string("const WECHSEL_MS = (\\d+);").search(tisch)
	check(wd.ends_with("s") and ms != null and absf(float(wd.trim_suffix("s")) * 1000.0 - float(ms.get_string(1))) < 1.0,
		"Dauer des Wechsels: style.css --wd (%s) = tisch.js WECHSEL_MS (%s)" % [wd, ms.get_string(1) if ms else "?"])
	check(css_var(tisch_block, "ws") == "steps(2, jump-none)" and css_var(tisch_block, "tr").begins_with("color var(--wd) var(--ws)")
		and not css.contains("var(--we)"), "Schrift und Knöpfe wechseln auf halbem Weg (steps), nicht über eine flache Kurve")
	check(css.contains(".himmel .nacht { opacity: 0; transition: opacity var(--wd) var(--wg)") and css.contains(".pf stop { transition: stop-color var(--wd) var(--wg)")
		and css.contains(".pf path { transition: fill var(--wd) var(--wg)") and css.contains("@keyframes daemmerung { 0%, 100% { opacity: 0; } 50% {"),
		"Himmel und Plattform mit derselben S-Kurve, Dämmerung auf halbem Weg am stärksten (Mitte = Schriftwechsel)")
	var schein := true
	for k in ["scheinZurNacht", "scheinZumTag", "scheinSvgZurNacht", "scheinSvgZumTag"]:
		var i := css.find("@keyframes %s {" % k)
		var b := css.substr(i, css.find("} }", i) - i) if i >= 0 else ""
		schein = schein and b.contains("20%, 49.99% {") and b.contains("50%, 80% {")
	check(schein and css.contains("#tisch.wechselt .gg .name, #tisch.wechselt .stapelzahl, #tisch.wechselt .farbanzeige span, #tisch.wechselt .pill span")
		and css.contains("#tisch.wechselt .pill svg, #tisch.wechselt .rund svg"), "Schein in der Gegenfarbe um Schrift und Symbole während der Dämmerung, Wechsel zur Mitte")
	# Alles, was je Seite eigene Farben hat, wechselt beim Flip mit (sonst springt es zu Beginn auf die neue Seite, z. B. der
	# Leuchtrand des Stapels): jede Regel #tisch[data-seite="dunkel"] .x gehört zu einem Bauteil mit Regel #tisch.wechselt .x …
	# oder zu Himmel/Plattform (eigene Übergänge).
	var mit := {}
	for m in RegEx.create_from_string("#tisch\\.wechselt (\\.[a-z-]+)").search_all(css):
		mit[m.get_string(1)] = true
	var ohne := {}
	for m in RegEx.create_from_string("#tisch\\[data-seite=\"dunkel\"\\] (\\.[a-z-]+)").search_all(css):
		var t := m.get_string(1)
		if not (mit.has(t) or t.begins_with(".himmel") or t.begins_with(".pf") or t == ".richtung"):
			ohne[t] = true
	check(mit.size() >= 10 and ohne.is_empty(), "Tag/Nacht-Regeln aller Bauteile wechseln beim Flip mit (ohne Übergang: %s)" % str(ohne.keys()))
	check(tisch.contains("const rest = t.wechselRest();") and tisch.contains("Object.assign({}, view, { side: e.side })") and tisch.contains("if (!laeuft) {"),
		"zwei Flips nacheinander: die Regie wartet den Wechsel ab, Zwischenstand mit der Seite des Flips, Dämmerung startet nicht neu")
	check(tisch.contains("this._themaTimer = setTimeout(") and tisch.contains("WECHSEL_MS / 2)"), "Browserleiste (theme-color) wechselt mit der Schrift auf halbem Weg")


# Prüfung 06.10.2026, kleinere Befunde am Tag: Farbwahl ohne dunklen Schleier, Grün in Druckfarbe, Sonnenstrahlen wie in der App,
# getrennte Mitspieler lesbar, Sternchen der Mau-Blase sichtbar, leiser Hinweis deckend.
func pruefe_tag_details(css: String, tisch: String) -> void:
	var karten := read_web("karten.js")
	var schleier := RegEx.create_from_string("\\n\\.farbwahl \\.schleier \\{[^}]*background: rgba\\((\\d+),").search(css)
	check(schleier != null and int(schleier.get_string(1)) > 200 and css.contains("#tisch[data-seite=\"dunkel\"] .farbwahl .schleier { background: rgba(5,6,15,.6); }"),
		"Farbwahl: am Tag heller Schleier (Tisch bleibt hell wie in der App), nachts abgedunkelt")
	var druck := css_block(css, ".farbwahl .feld[data-farbe=\"gelb\"]")
	var schwach: Array = []
	for f in UiPalette.LIGHT_COLORS:
		var hex := RegEx.create_from_string(f + ": \\{ name: '[^']+', hex: '(#[0-9A-Fa-f]{6})'").search(karten)
		if hex == null:
			schwach.append(f + ": keine Farbe in karten.js")
			continue
		var schrift := UiPalette.INK if druck.contains("[data-farbe=\"%s\"]" % f) else Color(UiPalette.CREAM)
		var k := kontrast(schrift, Color(hex.get_string(1)))
		if k < 4.5:
			schwach.append("%s: %.2f" % [f, k])
	check(schwach.is_empty() and druck.contains("color: var(--ink)") and tisch.contains("f === 'gelb' || f === 'gruen' || f === 'pink'"),
		"Farbwahl am Tag: Schrift auf jedem Farbfeld mindestens 4,5:1 (zu schwach: %s)" % str(schwach))
	var strahlen := css_block(css, ".himmel .tag::before {")
	var alpha := 0.0
	for m in RegEx.create_from_string("rgba\\(255,\\d+,\\d+,(\\.\\d+)\\)").search_all(strahlen):
		alpha = maxf(alpha, float(m.get_string(1)))
	var weit := false
	for m in RegEx.create_from_string("rgba\\(0,0,0,(\\.\\d+)\\) (\\d+)%").search_all(strahlen):
		if float(m.get_string(1)) >= 0.08 and int(m.get_string(2)) >= 70:
			weit = true
	check(alpha >= 0.4 and weit and tisch.contains("<i class=\"strahlen\"></i>"),
		"Sonnenstrahlen kräftig wie in der App (bis %.2f Gold, reichen bis in die Ecke, zwei Längen)" % alpha)
	var weg := RegEx.create_from_string("\\.gg \\.marke\\.weg \\{ background: (#[0-9A-Fa-f]{6}); color: (#[0-9A-Fa-f]{6});").search(css)
	check(not css.contains(".gg.weg { opacity") and css.contains(".gg.weg .name { color: var(--t-muted); }") and weg != null
		and kontrast(Color(weg.get_string(1)), Color(weg.get_string(2))) >= 4.5,
		"getrennte Mitspieler: Name in Nebentext-Farbe, Marke voll deckend (keine Deckkraft auf der ganzen Gruppe)")
	check(css_block(css, ".mau-blase .stern {").contains("color: var(--ink)") and css.contains("#tisch[data-seite=\"dunkel\"] .mau-blase .stern { color: #7CF5FF;"),
		"Mau-Blase: Sternchen am Tag in Druckfarbe, nachts Neon")
	var leise := css_block(css, "body.tag .toast.leise {")
	var leise_nacht := css_block(css, "\n.toast.leise {")
	check(leise.contains("background: rgba(33,27,44,.95)") and leise.contains("color: var(--cream)") and leise_nacht.contains("color: var(--ink)")
			and tisch.contains("this.app.themaFarbe") and read_web("app.js").contains("classList.toggle('tag'"),
		"leiser Hinweis: am Tag deckend in Druckfarbe (verschmilzt nicht mit dem Papier), nachts hell")
	# Restbefunde 06.10.2026: Aktionsknöpfe am Tag kräftig, Automat am Tag aus Papier (Neon nur nachts), Plattform-Schatten als
	# eigene Ebene (kein Weichzeichner je Bild beim Flip), nach der Mitte des Flips keine verspätete Schrift
	check(css.contains(".knopf.klein { opacity: 1; }") and css.contains("#tisch:not([data-seite=\"dunkel\"]) .knopf.klein.warn { background: #C4172A; color: #fff; }")
			and kontrast(Color("#FFFFFF"), Color("#C4172A")) >= 4.5, "Aktionsknöpfe am Tag voll deckend, „Anzweifeln“ mit kräftigem Rot")
	check(css_block(css, ".automat .fenster {").contains("background: var(--cream)") and css_block(css, ".automat .walze b {").contains("color: var(--ink)")
			and css.contains("#tisch[data-seite=\"dunkel\"] .automat .fenster { border-color: var(--pink); background: #0A0D20;")
			and tisch.contains("<span class=\"frage\" data-t>Los!</span>"), "Glücksspiel-Automat: Tag Papier mit Druckfarbe, Nacht Neon")
	check(tisch.contains("class=\"pf pf-sch\"") and css.contains(".richtung .pf-sch { opacity: .3; transition: opacity var(--wd) var(--wg); will-change: opacity; }")
			and css.contains(".pf-sch .pf-schatten { fill: #0E0B14; transition: none; }"), "Plattform-Schatten: eigene Ebene, beim Flip nur Deckkraft (kein Weichzeichner je Bild)")
	check(tisch.contains("r.classList.add('halb')") and css.contains("#tisch.wechselt.halb { --tr: none; }") and tisch.contains("if (!alt || !nurLayout) this.setzeSeite("),
		"Flip: ab der Mitte stehen Änderungen (z. B. wer dran ist) sofort in den Farben der neuen Seite; Layout-Aufrufe wechseln die Seite nicht")


# Beta 1.1.1: großer Modus (grosser_modus, Standard aus) und „Bei deinem Zug: Vibration“ (zug_vibration, Standard an seit 1.2.1), je Gerät
func pruefe_111(css: String, tisch: String, autotest: String, app: String, seite: String) -> void:
	var hand := read_web("hand.js")
	check(app.contains("grosser_modus: false, zug_vibration: true") and app.contains("Speicher.get('grosser_modus', false)")
			and app.contains("Speicher.get('zug_vibration', true) !== false") and app.contains("params.get('gross')")
			and seite.contains("data-set=\"grosser_modus\"") and seite.contains("data-set=\"zug_vibration\"") and seite.contains("class=\"schrift-wahl gross-wahl\"")
			and seite.contains("id=\"menue-gross-tipp\""),
		"Großer Modus und Zug-Vibration: Einstellungen im Menü und auf der Startseite, localStorage, ?gross=1")
	check(tisch.contains("setzeGross(an) {") and tisch.contains("_geometrieGross() {") and tisch.contains("this.handF = an ? 1.3 : 1")
			and hand.contains("_zu(cx, cy)") and hand.contains("this.t.handF") and css.contains("#tisch.gross #hand { transform: scale(1.3)")
			and css.contains("#tisch.gross .gg.sprung") and css.contains("#tisch.gross .himmel .sterne") and css.contains("body.reduziert #tisch.gross .gg"),
		"Großer Modus: riesiger Stapel und Ablage, Hand ×1,3, rollende Spielerliste, ruhiger Grund, reduzierte Effekte")
	check(tisch.contains("const blaseLinks = this.gross ||") and tisch.contains("if (this.gross) return { x: g.px - this.g.liste.w / 2 - 60")
			and tisch.contains("w: t.g.sw }") and tisch.contains("w: t.g.aw,") and not tisch.contains("w: 118 }"),
		"Großer Modus: Blasen, Einsatz und Flüge docken an Liste, Stapel und Ablage an")
	# Beta 1.1.3 (Nutzerbefund S10): Liste breit wie in der App (big_layout.gd 0,365), Stapel und Ablage nebeneinander mit Abstand
	check(tisch.contains("Math.min(620, W * 0.365)") and tisch.contains("spalt = Math.max(mitte ? FARBE_SPALT : 0, 30 + 54 * gk)") and tisch.contains("_listeZeilen(nl)")
			and css.contains("width: var(--lw, 440px); height: var(--zh0)") and css.contains("calc(48px * var(--fs)), calc(var(--zh0) * .5)"),
		"Großer Modus im Browser: breite Liste mit großen Namen, Ablage überdeckt den Stapel nicht")
	# Beta 1.2.1: Stapel enden über der Hinweisleiste, in schmalen Fenstern Farbe zwischen Stapel und Ablage; Lobby hochkant ohne Abschneiden
	check(tisch.contains("const kwHoch = Math.min(360, (leisteOben - 12 - 18) / VH)") and tisch.contains("setz(this.leiste, mx, leisteY)")
			and tisch.contains("this.root.classList.toggle('farbe-mitte', mitte)") and tisch.contains("this.root.classList.remove('farbe-mitte')")
			and css.contains("#tisch.gross.farbe-mitte .farbanzeige {"),
		"Großer Modus: Stapel nutzen die Höhe, Hinweis liegt nicht auf den Stapelecken, Farbe im Spalt bei schmalem Fenster")
	check(css.contains(".lobby-inhalt { flex-direction: column; align-items: stretch; }") and css.contains("@media (orientation: portrait) and (max-width: 440px)")
			and css.contains(".lobby-liste { list-style: none; margin: 0; padding: 0; flex: 1 1 auto; min-width: 0;"),
		"Lobby hochkant: Spielerzeilen passen in die Breite")
	check(tisch.contains("this.app.zugVibration()") and app.contains("zugVibration() {") and app.contains("!this.einstellungen.zug_vibration || !navigator.vibrate")
			and autotest.contains("Großer Modus: Spieler am Zug steht nicht oben"),
		"Bei deinem Zug: eigene Vibrations-Einstellung; Selbsttest prüft die Liste im großen Modus")


# Beta 1.1.3: Hausregel draw_play "any" (nach dem Ziehen jede passende Karte), Strafplakette als eigene Ebene, Fenster nachts
func pruefe_113(css: String, tisch: String, mock: String, autotest: String, app: String) -> void:
	check(mock.contains("draw_play:") and mock.contains("REGELN.draw_play !== 'any' && id !== this.gezogen") and app.contains("beliebigNachZiehen(v)")
			and app.contains("v.rules.draw_play === 'any'"),
		"draw_play „any“: Mock lässt nach dem Ziehen jede passende Karte zu, Hinweise im Client passen dazu")
	check(autotest.contains("Nach dem Ziehen fehlt „Behalten“") and autotest.contains("this.haus.beliebig++") and autotest.contains("draw_play \"drawn\")"),
		"autotest.js prüft die Phase drawn (Behalten, nur gezogene bzw. jede passende Karte)")
	check(tisch.contains("this.offenEl = el('div', 'offen')") and tisch.contains("b.appendChild(this.offenEl)") and not tisch.contains("<div class=\"offen\">")
			and css.contains(".buehne > .offen {") and css.contains("z-index: 45; pointer-events: none") and css.contains("#tisch.gross .buehne > .offen"),
		"Strafplakette liegt als eigene Ebene über Ablage, Seitenstapel und Farbe (auch im großen Modus)")
	check(tisch.contains("document.body.dataset.seite = seite") and css.contains("body[data-screen=\"tisch\"][data-seite=\"dunkel\"] .modal-karte"),
		"Fenster (Menü, Regeln, So geht's, Hilfe) folgen am Tisch Tag/Nacht")


func run() -> void:
	var t0 := Time.get_ticks_msec()
	web_dir = ProjectSettings.globalize_path("res://").path_join("../webclient").simplify_path()
	var autotest := read_web("autotest.js")
	var tisch := read_web("tisch.js")
	var app := read_web("app.js")
	check(autotest != "" and tisch != "" and app != "", "webclient/ lesbar (%s)" % web_dir)

	# ---------- 1. Was der Client kennt ----------
	var phasen := js_list(autotest, "PHASEN")
	var ereignisse := js_list(autotest, "EREIGNISSE")
	var hint_typen := js_types(autotest, "HINT_FELDER")
	var sicht_typen := js_types(autotest, "SICHT_FELDER")
	var spieler_typen := js_types(autotest, "SPIELER_FELDER")
	var glueck_hints := js_types(autotest, "HINT_GLUECK")
	var glueck_sicht := js_types(autotest, "SICHT_GLUECK")
	var discard_typen := js_types(autotest, "DISCARD_FELDER")
	check(sicht_typen.get("discard_log") == "array" and discard_typen.get("f") == "string" and discard_typen.get("s") == "number"
			and discard_typen.get("c") == "string" and discard_typen.get("h") == "boolean",
		"Ablage durchsehen: discard_log und Eintragsform in autotest.js (%s)" % str(discard_typen))
	check(phasen.size() >= 6 and ereignisse.size() >= 20 and hint_typen.size() >= 10 and sicht_typen.size() >= 15 and spieler_typen.size() >= 8,
		"Listen in autotest.js gefunden (%d/%d/%d/%d/%d)" % [phasen.size(), ereignisse.size(), hint_typen.size(), sicht_typen.size(), spieler_typen.size()])
	check(glueck_hints.get("can_stake") == "array" and glueck_hints.get("can_press") == "boolean" and glueck_hints.get("can_stop") == "boolean"
			and glueck_sicht.get("gamble") == "object",
		"Glücksspiel-Felder in autotest.js (%s, %s)" % [str(glueck_hints), str(glueck_sicht)])
	check(phasen.has("gamble"), "Phase „gamble“ ist dem Client bekannt")
	var effekte := {}
	for m in RegEx.create_from_string("case '([a-z_]+)'").search_all(tisch):
		effekte[m.get_string(1)] = true
	# Ereignisse mit sichtbarem Effekt am Tisch (Rest gleicht die Sicht ab)
	for e in ["deal", "play", "draw", "skip", "skip_all", "reverse", "color", "flip", "pending", "challenge", "mau", "catch", "penalty",
			"shuffle", "round_over", "game_over", "finish", "pass", "choose_color",
			"swap_hands", "gamble_start", "stake", "gamble_roll", "stake_back", "stake_discard", "discard_color", "discard_pick", "flip_surprise"]:
		check(effekte.has(e), "tisch.js spielt Ereignis „%s“ ab" % e)
	var aktionen := {}
	for src in [app, tisch]:
		for m in RegEx.create_from_string("a: '([a-z_]+)'").search_all(src):
			aktionen[m.get_string(1)] = true
		for m in RegEx.create_from_string("data-a=\"([a-z_]+)\"").search_all(src):
			aktionen[m.get_string(1)] = true
	aktionen.erase("wunsch")     # nur im Client: öffnet die Farbwahl, schickt dann {a:"color"}
	aktionen.erase("ablegen")    # nur im Client: Knopf „Ablegen (n)“, schickt dann {a:"discard_pick"}
	for a in ["play", "draw", "keep", "challenge", "accept", "color", "mau", "catch", "next_round", "stake", "press", "stop", "discard_pick"]:
		check(aktionen.has(a), "Client sendet Aktion „%s“" % a)
	# Nachrichten des Gastgebers (NetHostSession, HostTable), die der Client auswertet
	var nachrichten := {}
	for m in RegEx.create_from_string("case '([a-z_]+)'").search_all(app):
		nachrichten[m.get_string(1)] = true
	for t in ["welcome", "reject", "lobby", "start", "state", "err", "notice", "pong", "bye"]:
		check(nachrichten.has(t), "app.js wertet Nachricht „%s“ aus" % t)
	# Mau für alle (AGENTS.md Nr. 21): Ton und Blase kommen aus den Ereignissen (jedes Gerät), nicht aus dem eigenen Knopf;
	# kein synthetischer Mau-Ton mehr (Nr. 20).
	var ton := read_web("ton.js")
	check(tisch.contains("mauTon(e.seat, 'mau')") and tisch.contains("mauBlase(e.seat, 'mau'"), "Ereignis „mau“ → Ton und Blase beim Rufenden")
	check(tisch.contains("mauTon(e.seat, 'mau_mau')") and tisch.contains("mauBlase(e.seat, 'mau_mau'"), "Ereignis „finish“ → „Mau-Mau!“ (Ton und große Blase)")
	var mau_knopf := app.substr(app.find("    mau() {"), 700)
	check(app.find("    mau() {") >= 0 and not mau_knopf.contains("Ton.spiele") and not mau_knopf.contains("mauTon("), "Mau-Knopf spielt selbst keinen Ton (kein doppelter Ton)")
	check(ton != "" and not ton.contains("mau(t)") and ton.contains("STUFEN_SPIEL") and ton.contains("stufeSpiel = 'aus'"), "ton.js: kein synthetischer Mau-Ton, Spieltöne standardmäßig aus")
	var blasen := js_list(tisch, "BLASEN")
	check(blasen.size() >= 4, "mindestens 4 Varianten der Mau-Blase (%s)" % ", ".join(PackedStringArray(blasen)))
	var css := read_web("style.css")
	for b in blasen:
		check(css.contains(".mau-blase.v-%s .koerper" % b), "style.css animiert die Blasen-Variante „%s“" % b)
	check(css.contains("prefers-reduced-motion") and css.contains(".mau-blase.v-schlicht"), "Mau-Blase: schlichte Variante bei reduzierten Effekten")
	check(css.contains("#tisch[data-seite=\"dunkel\"] .mau-blase"), "Mau-Blase: nachts Neon")

	# Hausregeln im Client: Kartenhilfe und Regeltexte, Mock, Glücksspiel-Automat, persönliche Einstellung „Spielbare Karten hervorheben“
	var karten := read_web("karten.js")
	var mock := read_web("mock.js")
	var seite := read_web("index.html")
	for k in ["tausch", "gluecksspiel", "ablegen", "ablegen_joker"]:
		check(karten.contains("case '%s'" % k), "Kartenhilfe (karten.js) kennt „%s“" % k)
	for k in ["swap_cards", "swap_direction", "gamble_cards", "discard_color"]:
		check(karten.contains(k), "Regeltexte (karten.js) kennen die Option „%s“" % k)
	for k in ["_gluecksspiel", "_ablegen_joker", "_tausch", "'gamble'", "swap_hands", "gamble_start", "gamble_roll", "stake_back", "stake_discard",
			"discard_color", "can_stake", "can_press", "can_stop", "case 'stake'", "case 'press'", "case 'stop'", "'stop')", "'empty')"]:
		check(mock.contains(k), "mock.js kennt „%s“" % k)
	# 0.1.3: vier Tauschrichtungen, kein Anzweifeln in den Regeltexten, Auswahl beim Mitablegen, Glücksspiel mit Aufhören
	for k in ["counter", "against", "gegen den Uhrzeigersinn", "gegen die aktuelle Spielrichtung"]:
		check(karten.contains(k), "Regeltexte (karten.js): Tauschrichtung „%s“" % k)
	check(not karten.contains("anzweifeln") and not karten.contains("Bluffen"), "Regeltexte (karten.js) ohne Anzweifeln")
	check(karten.contains("weiter riskieren oder aufhören"), "Regeltexte (karten.js): Glücksspiel nennt das Aufhören")
	check(tisch.contains("data-a=\"ablegen\">' + M.t('Ablegen (%d)'") and app.contains("'Welche Farbe legst du mit ab?'") and app.contains("'Mit welcher Farbe geht es weiter?'")
			and app.contains("a: 'discard_pick', cards") and css.contains(".hk.kandidat"),
		"Farbe mit ablegen: Auswahl in der Hand, Knopf „Ablegen (n)“, zweistufige Farbwahl beim Joker")
	for k in ["case 'discard_pick'", "can_pick", "pick_color", "e: 'discard_pick'"]:
		check(mock.contains(k), "mock.js kennt „%s“" % k)
	check(autotest.contains("data-a=\"ablegen\"") and autotest.contains("abgewaehlt"), "autotest.js wählt beim Mitablegen (manchmal ab)")
	check(NetProtocol.clean_action({"a": "discard_pick", "cards": [3, 5], "color": "rot"}).get("cards", []) == [3, 5],
		"NetProtocol lässt {a:\"discard_pick\", cards:[…]} samt Kartenliste durch")
	# Glücksspiel aufhören (AGENTS.md Nr. 26): Knopf „Aufhören“ nur mit hints.can_stop, stake_discard mit reason "stop" animiert
	check(tisch.contains("'aufhoeren'") and tisch.contains("h.can_stop") and tisch.contains("Noch eine Karte setzen – oder aufhören?")
			and tisch.contains("e.reason === 'stop'") and app.contains("aufhoeren()") and css.contains(".automat .aufhoeren"),
		"Glücksspiel: Knopf „Aufhören“ (can_stop → {a:\"stop\"}) und stake_discard mit reason „stop“")
	check(seite.contains("data-set=\"hervorheben\"") and app.contains("Speicher.get('hervorheben', true)") and app.contains("'Die Karte passt nicht.'"),
		"Einstellung „Spielbare Karten hervorheben“ (je Gerät, Standard an, sonst Hinweis „Die Karte passt nicht.“)")
	var app_tisch := FileAccess.get_file_as_string("res://scripts/ui/table_view.gd")
	check(tisch.contains("hinweisLokal(h)") and tisch.contains("this.hinweisText(t)") and tisch.contains("'Du bist dran – nichts passt'") and app_tisch.contains("\"Du bist dran – nichts passt\""),
		"Ohne Hervorheben verrät der Hinweis „nichts passt“ nicht (Browser wie App)")
	check(css.contains(".automat .kuppel") and css.contains(".einsatz .zahl") and css.contains("#tisch[data-seite=\"dunkel\"] .automat"),
		"style.css: Glücksspiel-Automat und Einsatzstapel (Tag und Nacht)")
	pruefe_tag_nacht(css, tisch)
	pruefe_014(css, tisch, karten, mock, autotest, app, seite)
	pruefe_102(css, karten, app, seite)
	pruefe_111(css, tisch, autotest, app, seite)
	pruefe_113(css, tisch, mock, autotest, app)
	pruefe_i18n(seite)
	# Pegel der Spieltöne relativ zum Mau-Ton (normal) wie in der App (AppSound.TON_DB gegen MAU_DB), auf 0,5 dB genau
	var stufen := RegEx.create_from_string("STUFEN_SPIEL = \\{ aus: 0, leise: ([0-9.]+), normal: ([0-9.]+) \\}").search(ton)
	var pegel := []
	if stufen != null:
		for i in 2:
			var stufe: String = ["leise", "normal"][i]
			var web_db := 20.0 * log(float(stufen.get_string(i + 1))) / log(10.0)
			var app_db := float(AppSound.TON_DB[stufe]) - float(AppSound.MAU_DB["normal"])
			if absf(web_db - app_db) < 0.5:
				pegel.append(stufe)
	check(ton.contains("SPIEL_TOENE") and pegel.size() == 2, "ton.js: Spieltöne aus sfx/ mit den Pegeln der App (stimmen: %s)" % str(pegel))
	var fehlend: Array = []
	for key in CardDB.all_keys(true):
		if not FileAccess.file_exists(web_dir.path_join("cards/%s.webp" % key)):
			fehlend.append(key)
	check(CardDB.all_keys(true).size() == 128 and fehlend.is_empty(), "webclient/cards/ hat alle %d Gesichter (fehlend: %s)" % [CardDB.all_keys(true).size(), str(fehlend)])

	# ---------- 2. Bot-Partien gegen die Sicht des Clients ----------
	var rng := RandomNumberGenerator.new()
	rng.seed = 2602
	var seen_events := {}
	var seen_phases := {}
	var seen_hints := {}
	var view_checks := 0
	var bad := {}
	var max_bytes := 0
	var max_log := 0
	# 40 Partien wie bisher, danach Partien mit allen drei Hausregeln, bis jedes neue Ereignis vorkam (höchstens 80)
	var haus_events := ["swap_hands", "gamble_start", "stake", "gamble_roll", "stake_back", "stake_discard", "discard_color", "discard_pick"]
	var haus_games := 0
	for gi in 120:
		var haus := gi >= 40
		if haus and (haus_games >= 80 or (haus_games >= 12 and haus_events.all(func(e): return seen_events.has(e)) and seen_hints.has("stake_discard.stop"))):
			break
		if haus:
			haus_games += 1
		var cfg := (RulesFixture.random_config(rng, true, true, true) if haus else RulesFixture.random_config(rng)) if gi > 0 else RuleConfig.new()
		var n := rng.randi_range(2, 6)
		var pl := RulesFixture.players(n)
		pl[0]["host"] = true
		var g := MauGame.create(cfg, pl, rng.randi())
		var events := g.start_round()
		var steps := 0
		while steps < 1500:
			for s in n:
				var v := g.view_for(s)
				view_checks += 1
				var fe := g.events_for(s, events)
				for e in fe:
					seen_events[str(e.get("e", ""))] = true
				if s == 0:
					max_bytes = maxi(max_bytes, NetProtocol.encode({"t": "state", "events": fe, "view": v}).to_utf8_buffer().size())
				seen_phases[str(v.phase)] = true
				for k in sicht_typen:
					if js_type(v.get(k)) != sicht_typen[k]:
						bad["Sicht.%s: %s statt %s" % [k, js_type(v.get(k)), sicht_typen[k]]] = true
				var h: Dictionary = v.hints
				for k in hint_typen:
					if js_type(h.get(k)) != hint_typen[k]:
						bad["hints.%s: %s statt %s" % [k, js_type(h.get(k)), hint_typen[k]]] = true
					elif hint_typen[k] == "boolean" and bool(h[k]):
						seen_hints[k] = true
				# Glücksspiel-Felder: genau mit gamble_cards = on (der Client rechnet sonst mit Standardwerten)
				var glueck := str((v.rules as Dictionary).get("gamble_cards", "off")) == "on"
				for k in glueck_sicht:
					if glueck != v.has(k) or (glueck and js_type(v.get(k)) != glueck_sicht[k]):
						bad["Sicht.%s bei gamble_cards=%s: %s" % [k, glueck, js_type(v.get(k))]] = true
				for k in glueck_hints:
					if glueck != h.has(k) or (glueck and js_type(h.get(k)) != glueck_hints[k]):
						bad["hints.%s bei gamble_cards=%s: %s" % [k, glueck, js_type(h.get(k))]] = true
				if glueck and v.get("gamble") is Dictionary and not (v.gamble as Dictionary).is_empty():
					var gv: Dictionary = v.gamble
					if js_type(gv.get("seat")) != "number" or js_type(gv.get("stake")) != "number" or js_type(gv.get("last")) != "number" \
							or not str(gv.get("need")) in ["stake", "press"] or gv.has("q") or str(v.phase) != "gamble":
						bad["view.gamble passt nicht zum Client: " + str(gv)] = true
					if (h.get("can_stake", []) as Array).size() > 0:
						seen_hints["can_stake"] = true
					if bool(h.get("can_press", false)):
						seen_hints["can_press"] = true
					if bool(h.get("can_stop", false)):
						seen_hints["can_stop"] = true
						if s != int(gv.seat) or str(gv.need) != "stake" or int(gv.stake) < 1:
							bad["hints.can_stop ohne eigenen Einsatz bei need = stake: " + str(gv)] = true
				elif glueck and bool(h.get("can_stop", false)):
					bad["hints.can_stop ohne Glücksspiel"] = true
				# Farbe mit ablegen (0.1.3): discard_pick {seat, color} für alle, ohne Kandidatenzahl; can_pick/pick_color nur für den Wählenden
				var ablegen := str((v.rules as Dictionary).get("discard_color", "off")) == "on"
				if ablegen != v.has("discard_pick") or ablegen != h.has("can_pick"):
					bad["discard_pick/can_pick bei discard_color=%s" % ablegen] = true
				if ablegen and v.get("discard_pick") is Dictionary:
					var dp: Dictionary = v.discard_pick
					var cp: Array = h.get("can_pick", []) if h.get("can_pick") is Array else []
					if dp.is_empty() != (str(v.phase) != "discard_pick") or (not dp.is_empty() and (dp.keys().size() != 2 or js_type(dp.get("seat")) != "number" or js_type(dp.get("color")) != "string")):
						bad["view.discard_pick passt nicht zum Client: %s in Phase %s" % [str(dp), v.phase]] = true
					if not cp.is_empty():
						seen_hints["can_pick"] = true
						if dp.is_empty() or int(dp.seat) != s:
							bad["hints.can_pick bei fremder Auswahl"] = true
					if bool(h.get("pick_color", false)):
						seen_hints["pick_color"] = true
				# Ablage durchsehen (1.0.1): discard_log für alle gleich, Einträge {f, s, c, h}, letzter = oberste Karte, Einsätze ohne Gesicht
				if v.get("discard_log") is Array and v.get("top") is Dictionary:
					var dl: Array = v.discard_log
					if dl.is_empty() or str((dl[dl.size() - 1] as Dictionary).get("f", "")) != str(v.top.get("face", "")):
						bad["discard_log: letzter Eintrag ≠ top"] = true
					for de in dl:
						for k in discard_typen:
							if js_type((de as Dictionary).get(k)) != discard_typen[k]:
								bad["discard_log[].%s: %s statt %s" % [k, js_type((de as Dictionary).get(k)), discard_typen[k]]] = true
						if bool((de as Dictionary).get("h", false)):
							seen_hints["discard_log.h"] = true
							if str(de.get("f", "")) != "":
								bad["discard_log: verdeckter Einsatz mit Gesicht"] = true
						if int((de as Dictionary).get("s", -1)) < -1 or int(de.get("s", -1)) >= n:
							bad["discard_log: Platz außerhalb"] = true
					if s > 0 and str(dl) != str(g.view_for(0).get("discard_log")):
						bad["discard_log nicht für alle gleich"] = true
					max_log = maxi(max_log, dl.size())
				for e in fe:
					if str(e.get("e", "")) == "flip_surprise" and (js_type(e.get("seat")) != "number" or js_type(e.get("face")) != "string"):
						bad["flip_surprise ohne seat/face: " + str(e)] = true
					if str(e.get("e", "")) == "stake_discard":
						if not str(e.get("reason", "")) in ["stop", "empty"]:
							bad["stake_discard.reason " + str(e.get("reason"))] = true
						seen_hints["stake_discard." + str(e.get("reason", ""))] = true
				for p in v.players:
					for k in spieler_typen:
						if js_type(p.get(k)) != spieler_typen[k]:
							bad["players[].%s: %s" % [k, js_type(p.get(k))]] = true
				for c in v.hand:
					if js_type(c.get("id")) != "number" or js_type(c.get("face")) != "string":
						bad["hand[] ohne id/face"] = true
				if not (v.pending as Dictionary).is_empty() and not str(v.pending.get("kind", "")) in ["plus1", "plus5", "wuenscher_plus2", "farbjagd"]:
					bad["pending.kind " + str(v.pending.get("kind"))] = true
				if bool(h.need_color) and str(v.phase) != "color":
					bad["need_color außerhalb der Phase color"] = true
				for id in h.wild:
					if not (h.playable as Array).has(id):
						bad["hints.wild nicht in playable"] = true
				if str(v.phase) in ["round_over", "game_over"] and (v.result.get("ranking", []) as Array).size() != n:
					bad["result.ranking unvollständig"] = true
			var ph := g.phase()
			if ph == "round_over" or ph == "game_over":
				break
			# nächster Handelnder: wer etwas tun kann (Zug, Farbwahl, Anzweifeln, Erwischen)
			events = []
			for s in n:
				var a := MauBot.choose(g.view_for(s), rng.randi(), rng.randi_range(0, 2))
				if a.is_empty():
					continue
				var r := g.apply(s, a)
				if r.ok:
					events = r.events
					break
			steps += 1
		check(g.phase() in ["round_over", "game_over"], "Partie %d endet (Phase %s nach %d Schritten)" % [gi, g.phase(), steps])
	for k in bad:
		check(false, "Sicht passt nicht zum Client: " + str(k))
	check(bad.is_empty(), "%d Sichten passen Feld für Feld zum Client" % view_checks)
	check(max_log >= 5 and seen_hints.has("discard_log.h"), "discard_log wächst (bis %d Karten) und zeigt verdeckte Einsätze ohne Gesicht" % max_log)
	# Browser: Ablage durchsehen (Seitenstapel, Leger, Wunschfarbe, Zähler; springt bei Änderung zurück) und Einstellung „Schriftgröße“
	check(tisch.contains("v.discard_log") and tisch.contains("'seitenstapel'") and tisch.contains("this.durchsehen(1)") and tisch.contains("this.durchsehen(-1)")
			and tisch.contains("this.durchsehen(0)") and tisch.contains("'Startkarte'") and tisch.contains("M.t('%d von %d', n, L)") and tisch.contains("M.t('Wunsch: %s'")
			and mock.contains("discard_log:") and autotest.contains("durchsehenTest()"),
		"Browser: Ablage durchsehen nach dem Protokoll (Tipp Ablage/Seitenstapel/daneben, Leger, Wunschfarbe, Zähler)")
	check(seite.contains("data-set=\"schrift\"") and seite.contains("data-schrift=\"sehr_gross\"") and app.contains("Speicher.get('schrift', 'normal')")
			and css.contains("html[data-schrift=\"gross\"] { --fs: 1.15; }") and css.contains("html[data-schrift=\"sehr_gross\"] { --fs: 1.3; }")
			and css.contains(".gg .name { font: 700 calc(27px * var(--fs))") and css.contains(".hinweis { font: 700 calc(26px * var(--fs))"),
		"Browser: größere Grundschrift und Einstellung „Schriftgröße“ (Normal/Groß/Sehr groß, je Gerät)")
	for ph in seen_phases:
		check(phasen.has(ph), "Phase „%s“ ist dem Client bekannt" % ph)
	for e in seen_events:
		check(ereignisse.has(e), "Ereignis „%s“ ist dem Client bekannt" % e)
	for e in haus_events:
		check(seen_events.has(e), "Ereignis „%s“ kam in %d Partien mit Hausregeln vor" % [e, haus_games])
	# can_challenge/can_accept nicht mehr: "bluff" wird beim Laden zu "free" (0.1.3), die Knöpfe bleiben nur für alte Gastgeber
	for k in ["can_draw", "can_keep", "can_mau", "can_next_round", "can_stake", "can_press", "can_stop", "can_pick", "pick_color"]:
		check(seen_hints.has(k), "hints.%s kam in den Partien vor" % k)
	check(seen_hints.has("stake_discard.stop"), "stake_discard mit reason „stop“ (Aufhören) kam in den Partien vor")
	print("Sichten: %d, Phasen: %s, Ereignisse: %d Arten, Partien mit Hausregeln: %d, größte state-Nachricht: %d Byte" % [view_checks, str(seen_phases.keys()), seen_events.size(), haus_games, max_bytes])
	check(max_bytes < 60000, "state-Nachricht bleibt unter 60 KB (%d)" % max_bytes)

	# Jede Aktion des Clients kennt das Regelwerk (keine „Unbekannte Aktion.“) und übersteht NetProtocol.clean_action
	var g2 := MauGame.create(RuleConfig.new(), RulesFixture.players(3), 7)
	g2.start_round()
	for a in aktionen:
		var act := {"a": a, "card": 0, "color": "rot", "target": 1}
		check(not NetProtocol.clean_action(act).is_empty(), "NetProtocol lässt Aktion „%s“ durch" % a)
		var r := g2.apply(1, NetProtocol.clean_action(act))
		check(str(r.reason) != "Unbekannte Aktion.", "Regelwerk kennt Aktion „%s“" % a)

	# ---------- 3. Auslieferung der Dateien ----------
	await serve_check()
	print("Dauer: %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("RESULT: %d ok" % ok if fails == 0 else "%d ok, %d FAIL" % [ok, fails])
	quit(0 if fails == 0 else 1)


func add_dir(z: ZIPPacker, base: String, rel: String) -> int:
	var n := 0
	var dir := base.path_join(rel) if rel != "" else base
	for f in DirAccess.get_files_at(dir):
		z.start_file(rel.path_join(f) if rel != "" else f)
		z.write_file(FileAccess.get_file_as_bytes(dir.path_join(f)))
		z.close_file()
		n += 1
	for d in DirAccess.get_directories_at(dir):
		n += add_dir(z, base, rel.path_join(d) if rel != "" else d)
	return n


func serve_check() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://web_contract"))
	var zip_path := "user://web_contract/web.zip"
	var z := ZIPPacker.new()
	z.open(zip_path)
	var count := add_dir(z, web_dir, "")
	z.close()
	check(count > 100, "Zip aus webclient/ (%d Dateien)" % count)
	var server := NetServer.new()
	server.threaded = false
	server.auto_poll = false
	server.web_zip_path = zip_path
	root.add_child(server)
	if server.start(PORT, PORT, "127.0.0.1") != OK:
		check(false, "NetServer startet auf Port %d" % PORT)
		server.queue_free()
		return
	var index := await http_get(server, "/")
	check(int(index.status) == 200 and str(index.type).contains("text/html"), "/ liefert index.html (%s %s)" % [index.status, index.type])
	var html := (index.body as PackedByteArray).get_string_from_utf8()
	var srcs: Array = []
	for m in RegEx.create_from_string("<script src=\"([^\"]+)\"").search_all(html):
		srcs.append(m.get_string(1))
	check(srcs.size() >= 6, "index.html bindet die Skripte ein (%d)" % srcs.size())
	srcs.append_array(["mock.js", "autotest.js", "style.css"])
	for s in srcs:
		var r := await http_get(server, "/" + s)
		var want := "css" if s.ends_with(".css") else "javascript"
		check(int(r.status) == 200 and str(r.type).contains(want), "/%s (%s %s)" % [s, r.status, r.type])
	var fonts := DirAccess.get_files_at(web_dir.path_join("fonts"))
	var woff := ""
	for f in fonts:
		if f.ends_with(".woff2"):
			woff = f
			break
	for pair in [["sfx/mau.m4a", "audio/mp4"], ["sfx/mau.ogg", "audio/ogg"], ["sfx/mau_mau.m4a", "audio/mp4"], ["sfx/mau_mau.ogg", "audio/ogg"],
			["cards/hell_rot_7.webp", "image/webp"], ["cards/rueckseite.webp", "image/webp"], ["bilder/katze.webp", "image/webp"], ["bilder/logo.webp", "image/webp"],
			["fonts/" + woff, "font/woff2"], ["wach.mp4", "video/mp4"]]:
		var r := await http_get(server, "/" + str(pair[0]))
		check(int(r.status) == 200 and str(r.type).contains(pair[1]) and (r.body as PackedByteArray).size() > 500,
			"/%s → %s (%s %s, %d Byte)" % [pair[0], pair[1], r.status, r.type, (r.body as PackedByteArray).size()])
	await sfx_index_check(server)
	server.stop()
	server.queue_free()


# sfx/index.json (AGENTS.md 20): Liste der Tondateien, die der Browser-Client statt seiner Synth-Klänge nutzt, {"name": "datei", …}
# (ton.js: String(liste[name])). Pflicht sind die Aufnahmen des Nutzers „mau“ (Mau!) und „mau_mau“ (Mau-Mau!). Jede genannte Datei
# liegt in webclient/sfx/ und wird mit passendem MIME-Typ ausgeliefert.
func sfx_index_check(server: NetServer) -> void:
	var local := FileAccess.get_file_as_string(web_dir.path_join("sfx/index.json"))
	check(local != "", "webclient/sfx/index.json vorhanden")
	var r := await http_get(server, "/sfx/index.json")
	check(int(r.status) == 200 and str(r.type).contains("json"), "/sfx/index.json ausgeliefert (%s %s)" % [r.status, r.type])
	var parsed: Variant = JSON.parse_string(local)
	check(parsed is Dictionary, "sfx/index.json ist gültiges JSON-Objekt")
	if not parsed is Dictionary:
		return
	var liste: Dictionary = parsed
	# Mau-Aufnahmen und die Spieltöne der App (AppSound.NAMES): Der Browser spielt dieselben Dateien, eigener Schalter, Standard aus
	for pflicht in AppSound.NAMES:
		check(liste.has(pflicht), "sfx/index.json nennt „%s“ (%s)" % [pflicht, str(liste.keys())])
		if liste.has(pflicht):
			var d := str(liste[pflicht])
			check(d.ends_with(".m4a"), "sfx/index.json: „%s“ als m4a (iPhone-Safari spielt kein ogg): %s" % [pflicht, d])
			check(FileAccess.file_exists(web_dir.path_join("sfx").path_join(d.get_basename() + ".ogg")), "sfx/%s.ogg als Rückfall vorhanden" % d.get_basename())
	for name in liste:
		var datei: Variant = liste[name]
		check(datei is String and str(datei) != "" and not str(datei).contains("/") and not str(datei).contains(".."),
			"sfx/index.json: „%s“ → schlichter Dateiname (%s)" % [name, str(datei)])
		if not datei is String or str(datei) == "":
			continue
		check(FileAccess.file_exists(web_dir.path_join("sfx").path_join(str(datei))), "sfx/%s (für „%s“) liegt in webclient/sfx/" % [datei, name])
		var want := "audio/mp4" if str(datei).ends_with(".m4a") else ("audio/ogg" if str(datei).ends_with(".ogg") else "audio/")
		var f := await http_get(server, "/sfx/" + str(datei))
		check(int(f.status) == 200 and str(f.type).contains(want) and (f.body as PackedByteArray).size() > 500,
			"/sfx/%s → %s (%s %s, %d Byte)" % [datei, want, f.status, f.type, (f.body as PackedByteArray).size()])


# Einfache HTTP/1.1-Abfrage (Connection: close) gegen den Server im selben Prozess
func http_get(server: NetServer, path: String) -> Dictionary:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", PORT)
	var sent := false
	var buf := PackedByteArray()
	var end := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < end:
		server.poll()
		peer.poll()
		var st := peer.get_status()
		if st == StreamPeerTCP.STATUS_CONNECTED:
			if not sent:
				peer.put_data(("GET %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nConnection: close\r\n\r\n" % [path, PORT]).to_utf8_buffer())
				sent = true
			var n := peer.get_available_bytes()
			if n > 0:
				var got := peer.get_partial_data(n)
				if int(got[0]) == OK:
					buf.append_array(got[1])
			# fertig, sobald Kopf und Content-Length vollständig da sind (falls der Server die Verbindung offen hält)
			var t := buf.get_string_from_ascii()
			var he := t.find("\r\n\r\n")
			if he >= 0:
				var cl := RegEx.create_from_string("(?i)content-length:\\s*(\\d+)").search(t.substr(0, he))
				if cl != null and buf.size() >= he + 4 + int(cl.get_string(1)):
					break
		elif st == StreamPeerTCP.STATUS_NONE or st == StreamPeerTCP.STATUS_ERROR:
			if sent:
				break
		await process_frame
	peer.disconnect_from_host()
	var text := buf.get_string_from_ascii()
	var head_end := text.find("\r\n\r\n")
	if head_end < 0:
		return {"status": 0, "type": "", "body": PackedByteArray()}
	var head := text.substr(0, head_end)
	var status := int(head.get_slice(" ", 1))
	var ctype := ""
	for line in head.split("\r\n"):
		if line.to_lower().begins_with("content-type:"):
			ctype = line.substr(13).strip_edges()
	return {"status": status, "type": ctype, "body": buf.slice(head_end + 4)}


# Englische Fassung (Beta 1.2.2): i18n.js, Wörterbücher i18n_en.js (nur Browser) und i18n_po.js (aus game/i18n/*.po erzeugt),
# Reihenfolge der Skripte; jeder Text in M.t('…')/M.t("…") und in data-t muss im englischen Wörterbuch stehen (streng).
func pruefe_i18n(seite: String) -> void:
	var i18n := read_web("i18n.js")
	check(i18n.contains("M.I18n = I18n") and i18n.contains("render(lt)") and i18n.contains("msgText(m, ersatz)"), "i18n.js: M.I18n mit render und msgText")
	var a := seite.find("i18n_po.js")
	var b := seite.find("i18n_en.js")
	var c := seite.find("src=\"i18n.js\"")
	var d := seite.find("karten.js")
	check(a >= 0 and a < b and b < c and c < d, "index.html lädt i18n_po.js, i18n_en.js, i18n.js vor den übrigen Skripten")
	check(seite.contains("data-set=\"sprache\" data-wert=\"auto\"") and seite.contains("data-wert=\"en\""), "index.html: Umschalter „Sprache“ in den Einstellungen")
	var en := _dict_js(read_web("i18n_en.js"), "window.MMF_I18N_EN = ")
	var po := _dict_js(read_web("i18n_po.js"), "window.MMF_I18N_PO = ")
	check(not en.is_empty() and not po.is_empty(), "Wörterbücher lesbar (i18n_en.js %d, i18n_po.js %d Einträge)" % [en.size(), po.size()])
	# i18n_po.js aktuell? Jeder übersetzte Eintrag der .po-Dateien muss gleich drinstehen (tools/build.ps1 -Target Web erneuert).
	var stale := 0
	for path in I18n.FILES:
		var text := FileAccess.get_file_as_string(path)
		for e in _po_entries(text):
			if str(e[0]) != "" and str(e[1]) != "" and str(po.get(e[0], "")) != str(e[1]):
				stale += 1
				if stale <= 3:
					print("i18n_po.js veraltet: " + str(e[0]).left(80))
	check(stale == 0, "i18n_po.js passt zu game/i18n/*.po (%d abweichend; tools/build.ps1 -Target Web)" % stale)
	var clash := 0
	for k in en:
		if po.has(k) and str(po[k]) != str(en[k]):
			clash += 1
			print("i18n_en.js und .po übersetzen verschieden: " + str(k).left(80))
	check(clash == 0, "keine widersprüchlichen Übersetzungen zwischen i18n_en.js und .po (%d)" % clash)
	var used := {}
	for name in ["app.js", "tisch.js", "hand.js", "karten.js", "netz.js", "ton.js"]:
		var src := read_web(name)
		# M.t('…') und die Kurzform tr('…') (karten.js)
		for m in RegEx.create_from_string(r"\b(?:M\.t|tr)\(\s*'((?:[^'\\]|\\.)*)'").search_all(src):
			used[m.get_string(1).replace(r"\'", "'")] = name
		for m in RegEx.create_from_string(r'\b(?:M\.t|tr)\(\s*"((?:[^"\\]|\\.)*)"').search_all(src):
			used[m.get_string(1).replace(r'\"', '"')] = name
		# data-t in HTML-Texten der Skripte (Tisch: Rückseiten, Glücksspiel …)
		for m in RegEx.create_from_string("data-t(?:-title|-aria|-ph)?=\"([^\"]+)\"").search_all(src):
			used[m.get_string(1)] = name
		for m in RegEx.create_from_string("data-t>([^<]+)<").search_all(src):
			used[m.get_string(1)] = name
	for m in RegEx.create_from_string("data-t(?:-title|-aria|-ph)?=\"([^\"]+)\"").search_all(seite):
		used[m.get_string(1)] = "index.html"
	for m in RegEx.create_from_string("data-t>([^<]+)<").search_all(seite):
		used[m.get_string(1)] = "index.html"
	var missing: Array = []
	for k in used:
		var key := str(k).replace("&amp;", "&")
		if key in ["Mau!", "Mau-Mau!", "Mau-Mau Flip", "Deutsch", "English"] or en.has(key) or po.has(key):
			continue
		missing.append("%s (%s)" % [key, used[k]])
	for m in missing.slice(0, 20):
		print("ohne Übersetzung: " + str(m))
	check(missing.is_empty(), "jeder Text in M.t(…)/data-t steht im englischen Wörterbuch (%d fehlen, %d geprüft)" % [missing.size(), used.size()])


# „window.NAME = {JSON};“ → Dictionary
func _dict_js(src: String, head: String) -> Dictionary:
	var i := src.find(head)
	if i < 0:
		return {}
	var body := src.substr(i + head.length()).strip_edges()
	if body.ends_with(";"):
		body = body.left(body.length() - 1)
	var d: Variant = JSON.parse_string(body)
	return d if d is Dictionary else {}


func _po_entries(text: String) -> Array:
	var out: Array = []
	var id := ""
	var s := ""
	var field := ""
	var have := false
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.begins_with("msgid "):
			if have:
				out.append([id, s])
			id = _po_unq(line.substr(6))
			s = ""
			field = "id"
			have = true
		elif line.begins_with("msgstr "):
			s = _po_unq(line.substr(7))
			field = "str"
		elif line.begins_with("\""):
			if field == "id":
				id += _po_unq(line)
			else:
				s += _po_unq(line)
	if have:
		out.append([id, s])
	return out


func _po_unq(q: String) -> String:
	var t := q.strip_edges()
	if t.length() >= 2 and t.begins_with("\"") and t.ends_with("\""):
		t = t.substr(1, t.length() - 2)
	return t.replace(r"\n", "\n").replace(r'\"', '"').replace(r"\\", "\\")
