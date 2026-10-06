# Modul B – Kartenbilder, Schriften, Logo, Symbole

Stand 04.10.2026, Nachtschicht, nach der Nachbesserung (siehe unten). Alle Teilaufgaben sind erledigt. Ein Aufruf baut alles neu: `bash tools/cards/build_cards.sh` (etwa 30 s). Zwei Läufe hintereinander liefern byte-gleiche Dateien.

Kontrollbogen aller 129 Bilder (128 Gesichter + Rückseite): `docs/module/B_kartenbogen.png`; nur Kartentausch: `docs/module/B_kartentausch.png`; nur Glücksspiel und Farbe ablegen: `docs/module/B_neue_karten.png`

## Glücksspiel und Farbe ablegen (Hausregeln, 05.10.2026)

Für die Hausregeln `gamble_cards = "on"` (+2 Karten) und `discard_color = "on"` (+6 Karten, siehe `docs/module/A.md`) gibt es 12 neue Gesichter. Die Schlüssel stimmen mit `CardDB.gamble_keys()` und `CardDB.discard_keys()` überein:

- Glücksspiel (Joker): `hell_gluecksspiel`, `dunkel_gluecksspiel`
- Farbe ablegen: `hell_rot_ablegen`, `hell_gelb_ablegen`, `hell_gruen_ablegen`, `hell_blau_ablegen`, `dunkel_pink_ablegen`, `dunkel_tuerkis_ablegen`, `dunkel_orange_ablegen`, `dunkel_lila_ablegen`
- Ablegen-Joker: `hell_ablegen_joker`, `dunkel_ablegen_joker`

Kontrollbogen: `docs/module/B_neue_karten.png`. Er zeigt
- jede farbige Ablegen-Karte neben +1 bzw. +5 und dem Kartentausch derselben Farbe,
- die beiden Joker neben Wünscher und Wünscher +2 bzw. Farbjagd,
- alle 12 in Originalgröße
- und je eine Hand, in der nur der obere Kartenteil sichtbar ist (150 und 100 px breit).

**Glücksspiel** (bunter Joker wie der Wünscher; eigener Entwurf):

- Ein großer runder Glücksspielknopf mit Fragezeichen auf einem flachen Sockel. Vorn auf dem Sockel sitzt das Zahlenwerk „0–10“ zwischen vier Lampen in den vier Farben der Seite, daneben Glücksfunkel.
- Hell: Knopf in Druckfarbe mit Glanz, Sockel in Creme, Ziffern gelb auf Druckfarbe, Hintergrund der Sonnenkranz des Jokers. Dunkel: Knopf im Regenbogenverlauf der dunklen Joker-Kontur, Ziffern türkis.
- Eckindex: Knopf mit Fragezeichen, Sockel und zwei Funkel, ohne Zahlenwerk und Lampen; darunter die bunte Pfote wie bei Wünscher +2 und Farbjagd.
- Abgrenzung: Der Wünscher zeigt die Pfote, die Farbjagd ein „?“ als Wert. Eine erste Fassung mit Drückstrichen über einer hohen Kuppel sah im Index wie eine Alarmsirene aus; deshalb ist die Kuppel jetzt flach und statt der Striche gibt es Funkel.

**Farbe ablegen** (Aktionskarte, eigener Entwurf):

- Ein flacher Handfächer aus fünf Karten, aus dem die zweite und vierte Karte nach unten herausrutschen. Die Lücke im Fächer zeigt Bewegungsstriche, darunter steht ein kräftiger Pfeil nach unten auf den Ablagestapel.
- Die abrutschenden Karten tragen die tiefe Kartenfarbe mit dem Farbsymbol (hell) bzw. gedämpftes Neon mit Symbol (dunkel). Die übrigen Handkarten sind neutral (hell ein Grauton, dunkel gedämpft), damit klar ist: nur diese Farbe geht.
- Joker: dieselbe Zeichnung, die abrutschenden Karten haben vier Farbstreifen. Hintergrund und Kontur sind die des Wünschers (Sonnenkranz bzw. Regenbogen).
- Eckindex: drei Karten, die äußeren als Umriss, die mittlere voll (beim Joker mit Farbstreifen) nach unten verschoben, darunter der Pfeil.
- Abgrenzung:
  - +1/+5: drei große Karten hinter der Zahl, der Index zeigt die Zahl
  - Kartentausch: drei Karten im Kreis mit Bogenpfeilen
  - Richtungswechsel: gestreifte Bogenpfeile
  - Flip: geteilte Scheibe
  - Nur die Ablegen-Karte hat einen geraden Pfeil nach unten.
- Rahmen, Index-Laschen, Farbsymbole, Spiegelungen und Papierkorn sind dieselben wie bei allen anderen Karten derselben Seite.

**Bau:**

- Die 12 Gesichter liegen auf einem dritten Bogen `zusatz` (Grund wie beim Kartentausch: Chrome rastert die Glut kachelweise). `bash tools/cards/build_cards.sh` erzeugt alle 128 Gesichter und die Rückseite. Der Schritt `zusatzbogen` erzeugt den Kontrollbogen.
- `mmf.js`: `gluecksPrims()`, `ablegenPrims()`, `ablegenCard()`, Typen `gluecks`, `ablegen`, `ablegenj` in `TYPE_NAMES` und `ICON_OF`. Neu sind außerdem Schrift im Symbol (`kind: 'text'`) und Formen ohne Kontur (`nosil`) in `renderPrims()`, alles rein additiv.
- Geprüft per SHA-256:
  - alle 117 alten PNG und alle 125 alten WebP (117 Karten, 8 Farbsymbole) byte-gleich
  - Bediensymbole, App-Symbole, Logo, Startbild, Schriften und `B_kartentausch.png` nach vollem Neubau unverändert
  - die 20 Entwurfs-SVGs, `logo.svg` und `icon.svg` aus `art/entwurf/a-papier-neon/` entstehen mit dem erweiterten `mmf.js` byte-gleich
  - ein zweiter Lauf: 129 von 129 byte-gleich
- Import: `.import` wie bei den anderen Karten (WebP verlustbehaftet 0,9, Mipmaps), vor dem ersten Import angelegt. Zusammen etwa 0,5 MB in der APK, WebP 116 KB.
- Verlustbehafteter Import der neuen Karten mindestens 35,4 dB gegen das Quellbild (`hell_gelb_ablegen`). WebP gegen PNG wie bei den Nachbarkarten: hell etwa 28 dB, dunkel 34–36 dB.

**Test:** `test_b_assets.gd` prüft jetzt alle 129 Bilder (128 Gesichter + Rückseite). Erledigt ist damit auch der offene Punkt aus dem Kartentausch (der Test prüfte bisher nur 109).
- Die Schlüssel kommen aus einer eigenen Liste. Der Vertrag mit Modul A gleicht sie ab mit
  - `CardDB.all_keys()` (108),
  - `CardDB.all_keys(true)` (128),
  - `swap_keys()` (8), `gamble_keys()` (2) und `discard_keys()` (10).
- Das Regelwerk liefert bereits alle Varianten; eine Abweichung meldet der Test getrennt nach „ohne Bild“ und „ohne Karte im Regelwerk“.
- Alle Zusatzkarten (20) gehen zusätzlich in die Stichprobe des verlustbehafteten Imports.
- Ergebnis: **RESULT: 125 ok**.

**Hinweis an Oberfläche und Browser-Client:** Die Bilder liegen unter den Schlüsseln aus `CardDB.face_key()`, also ohne Sonderfälle. Das Ablegen-Symbol zeigt immer zwei abrutschende Karten; wie viele tatsächlich mitgehen, steht im Ereignis `discard_color` (`count`, `faces`).

## Kartentausch (Hausregel, 05.10.2026)

Für die Hausregel `swap_cards = "on"` (Deck 116, siehe `docs/module/A.md`) gibt es 8 neue Gesichter:

- `hell_rot_tausch`, `hell_gelb_tausch`, `hell_gruen_tausch`, `hell_blau_tausch`
- `dunkel_pink_tausch`, `dunkel_tuerkis_tausch`, `dunkel_orange_tausch`, `dunkel_lila_tausch`

Kontrollbogen: `docs/module/B_kartentausch.png`. Er zeigt jede neue Karte zwischen Richtungswechsel und Flip derselben Farbe, alle 8 in Originalgröße und je eine Hand, in der nur der obere Kartenteil sichtbar ist (Karten 150 und 100 px breit).

**Symbol** (eigener Entwurf):

- Drei aufrechte kleine Karten im Dreieck wie drei Plätze am Tisch. Dazwischen drei kräftige Bogenpfeile im Uhrzeigersinn: Jeder gibt seine Hand an den nächsten Platz.
- Abgrenzung:
  - Richtungswechsel: zwei gestreifte Bogenpfeile ohne Inhalt
  - Flip: geteilte Scheibe
  - Alle aussetzen: drei Katzenköpfe, zwei oben und einer unten; beim Kartentausch steht eine Karte oben, zwei unten.
- Im Eckindex dasselbe Symbol in klein. Die Karten sind dort voll in der Wertfarbe und durch einen schmalen Rand in Papier- bzw. Nachtfarbe von den Pfeilen getrennt.
- Groß haben die kleinen Karten ein Innenfeld in der tiefen Kartenfarbe (hell) bzw. in gedämpftem Neon (dunkel). Die Pfeile sind ungestreift.
- Rahmen, Index-Laschen, Farbsymbole, Spiegelungen und Papierkorn sind dieselben wie bei allen anderen Aktionskarten.
- Die Pfeile zeigen immer im Uhrzeigersinn (Standard `swap_direction = "clockwise"`). Bei `"play"` steht die tatsächliche Richtung im Ereignis `swap_hands` (`dir`); die Oberfläche sollte sie beim Tausch zeigen (Hinweis an Modul F bzw. E).

**Bau:**

- Ein Neubau (`bash tools/cards/build_cards.sh`) erzeugt alle 116 Gesichter und die Rückseite.
- Die 8 neuen Gesichter liegen auf einem eigenen Bogen `tausch`. Im gemeinsamen Bogen hätte Chrome vier dunkle Lila-Karten um einzelne Farbstufen verändert (42–49 dB), weil es die Glut kachelweise rastert.
- Kartenbilder gehen erst in einen Zwischenordner. Eine abweichende vorhandene Datei bleibt erhalten und wird gemeldet; nur `MMF_ERSETZEN=1` ersetzt sie.
- Geprüft per SHA-256:
  - alle 109 alten PNG und alle 117 alten WebP (109 Karten, 8 Farbsymbole) byte-gleich
  - Bediensymbole, App-Symbole, Logo und Startbild nach Neubau unverändert
  - die 20 Entwurfs-SVGs aus `art/entwurf/a-papier-neon/cards/` byte-gleich mit dem erweiterten `mmf.js`
  - ein zweiter Lauf: 117 von 117 byte-gleich
- Import: `.import` wie bei den anderen Karten (WebP verlustbehaftet 0,9, Mipmaps), zusammen etwa 0,3 MB in der APK. `test_b_assets.gd`: weiterhin 120 ok.
- Die neuen Bilder haben je 300 × 466 bzw. 200 × 311 Pixel, transparente Ecken und eine deckende Mitte. WebP gegen PNG liegt so gut wie bei den Nachbarkarten (hell etwa 28 dB, dunkel 32–38 dB, gleiche Messung).

**Erledigt** (mit Glücksspiel und Farbe ablegen, siehe oben): `test_b_assets.gd` prüft alle Bilder einschließlich der 8 Kartentausch-Gesichter gegen `CardDB.all_keys(true)`.

## Umgesetzt

### Kartenpipeline in `tools/cards/`

- **Generator übernommen:** `mmf.js` und `logo.js` sind unveränderte Kopien aus `art/entwurf/a-papier-neon/quelle/`.
- **Gestaltung nachweislich unverändert:**
  - Die 19 Entwurfskarten aus `art/entwurf/a-papier-neon/cards/*.svg` entstehen aus dem neuen Generator Byte für Byte gleich.
  - `logo.png` und `icon_512.png` sind pixelgleich mit den Entwurfsbildern (PSNR unendlich).
- **Neue Typen** im selben Stil, ohne Codeänderung, denn der Generator war schon generisch:
  - Zahlen 1–9 in allen Farben
  - hell: +1, Aussetzen, Richtungswechsel und Flip in allen vier Farben
  - dunkel: +5, Alle aussetzen, Richtungswechsel und Flip in allen vier Farben
- **`karten.js`:** liefert die 108 Gesichter mit den exakten Schlüsseln aus BETA1_PLAN Abschnitt 3 und zeichnet die neue Rückseite.
- **Neutrale Rückseite `rueckseite`:**
  - Diagonal geteilt: links oben Tag (Papier, leise Sonnenstrahlen, Papierkorn, Sonne), rechts unten Nacht (Sterne, leuchtende Mondsichel).
  - Neon-Naht wie im Logo.
  - Kleine Wortmarke entlang der Naht: „Mau-Mau“ in Druckfarbe auf dem Tag, „Flip“ als Neon in der Nacht.
  - Feine Innenkante: auf dem Tag in Druckfarbe, in der Nacht als Neonlinie.
  - Enthält keine Spielinformation. Im Gegnerfächer (60 px) wirkt sie ruhig und gleichförmig, geprüft per Fächer-Probebild.
  - Kein Oval, keine rote Fläche, damit Abstand zum Vorbild.
- **Rendern:**
  - Chrome ohne Fenster rendert je Bogen einen Screenshot mit transparentem Hintergrund, danach schneidet ein einziger ffmpeg-Lauf alle Bilder aus.
  - Schriften kommen lokal aus `game/assets/fonts/`. Der Bau bricht ab, wenn `document.fonts` sie nicht als geladen meldet. Ohne Schriften zeichnet `render.html` gar nichts, und die Deckungsprüfung des Screenshots schlägt an.
  - Werte stehen in Bricolage Grotesque mit `opsz 12`. Stichprobe 1, 6, 9, +5 und +2 in Originalgröße im Kontrollbogen geprüft.
  - Kartenecken werden auf die Kartenrundung beschnitten, kein Glühen ragt hinaus.
  - Glühen und Papierkorn sind eingebacken.
- **WebP:** 200 × 311, Qualität 85, mit Alpha. Verkleinert mit vormultipliziertem Alpha, also ohne dunkle Säume an den Ecken. 109 Dateien, zusammen 0,8 MB.
- **Import in Godot:** Karten verlustbehaftet (WebP, Qualität 0,9) mit Mipmaps, zusammen etwa 4 MB in der APK. Einzelheiten in `tools/cards/README.md`, Abschnitt „Import in Godot“.

### Schriften (SIL OFL 1.1)

- Quelle: github.com/google/fonts, variable TTF.
  - `BricolageGrotesque.ttf` mit den Achsen opsz, wdth, wght
  - `Fraunces.ttf` und `Fraunces-Italic.ttf` mit den Achsen opsz, wght, SOFT, WONK
- `OFL.txt` enthält beide Lizenzdateien unverändert, dazu die Herkunft.
- Ablage in `game/assets/fonts/`. Der Schritt `schriften` spiegelt TTF und `OFL.txt` nach `webclient/fonts/`.
- **WOFF2 für den Browser-Client** (Plan Abschnitt 8):
  - `tools/cards/woff2.pl` packt jede TTF ohne Python: WOFF2 mit Null-Transformation, alle Tabellen bleiben Byte für Byte gleich, Brotli mit Qualität 11 über den `brotli`-Befehl aus Git für Windows.
  - Größen: Bricolage 204 KB, Fraunces 194 KB, Fraunces-Italic 234 KB. Zusammen 0,63 MB statt 1,18 MB.
  - Chrome zeichnet mit WOFF2 und TTF pixelgleich (`schriften.html`). Godot lädt die WOFF2 mit denselben Achsen, Namen und Laufweiten.
- **Achtung, Standardinstanz der Dateien:**
  - Bricolage steht ohne Angaben auf `opsz 96` und `wght 800` („Bricolage Grotesque 96pt ExtraBold“).
  - Fraunces steht auf `wght 900`, `opsz 9` und `WONK 1`.
  - Die TTF deshalb nie direkt als Font oder als Standardschrift im Projekt bzw. Theme verwenden, sondern immer über `FontVariation` mit `opsz 12` (`UiFonts`, `game/scripts/ui/ui_fonts.gd`). Sonst werden 6 und 9 zu dünn (Nutzerentscheidung 17).
  - Im Browser stellt `font-optical-sizing: auto` (Standard) die Achse `opsz` nach der Schriftgröße ein. Kartenwerte kommen dort aus den Bildern, für Zahlen in der Oberfläche setzt `webclient/style.css` bereits `'opsz' 12`.

### UI-Grafiken in `game/assets/ui/`

- **Logo:** `logo.png` (1600 × 900) und `logo_klein.png` (800 × 450), mit der Katze `katze_mau.png`.
- **App-Symbole:**
  - `icon_512.png`: abgerundet, transparente Ecken
  - `android_main_192.png`
  - `android_adaptive_background_432.png`: Tag/Nacht. Sonne und Mond sind leicht nach innen gerückt, damit runde Masken sie zeigen.
  - `android_adaptive_foreground_432.png`: die Katze. Das 512er-Symbol ist auf die sichtbaren 72 dp abgebildet, die Ohren liegen im sicheren Kreis (66 dp). Der Schwanz ist weggeschnitten, damit er bei Parallax nicht hereinragt.
  - **zusätzlich** `android_adaptive_monochrome_432.png` für Android-13-Themensymbole: Katzenkopf mit Augen, Nase und Maul ausgespart.
  - Mit Kreis- und Squircle-Maske geprüft.
- **`splash.png`** (1600 × 720):
  - Nachthimmel mit dem Logo als abgerundete Tafel.
  - Die Ränder laufen in die Nachtfarbe aus. Die äußersten 4 px sind genau `#0A0D20`, also gleich `boot_splash/bg_color`. Damit fallen Balken bei anderem Seitenverhältnis (S10) nicht auf.
- **`touch_icon_180.png`:** quadratisch ohne Rundung, weil iOS selbst rundet und transparente Ecken schwarz würden.
- **15 Bediensymbole** (96 × 96, `#F4EADA` auf transparent, Linienstärke 8): `sortieren`, `rueckseiten` (Karte mit Mondsichel), `hilfe`, `einstellungen`, `teilen`, `update`, `zurueck`, `wlan`, `qr`, `regeln`, `spieler`, `roboter`, `start`, `mau` (Sprechblase mit Katzenohren), `ziehen`. Import mit Mipmaps.
- **8 Farbsymbole** `farben/<farbe>.png` (96 × 96, Import mit Mipmaps):
  - Formen aus `symbolPrims` des Generators.
  - hell: Flächenfarbe mit Druckfarben-Kontur und Papier-Details wie im Eckindex, außen ein Papierrand wie bei einem Aufkleber.
  - dunkel: Neonfarbe mit Nacht-Details und Nachtkontur wie im Eckindex, außen ein Rand in der Neonfarbe, zu 62 % aufgehellt (wie die Werte der dunklen Seite).
  - Der Außenrand hat auf dem dunklen Tisch mindestens 3:1 Kontrast. Lila kam vorher nur auf etwa 2,8:1.
  - Dieselben liegen als `webclient/cards/farbe_<farbe>.webp` vor.

## Schnittstelle (Dateien)

| Pfad | Inhalt |
|---|---|
| `res://assets/cards/<schlüssel>.png` | 108 Gesichter + `rueckseite`, 300 × 466, RGBA; dazu die 20 Gesichter der Hausregeln: `<seite>_<farbe>_tausch`, `<seite>_<farbe>_ablegen`, `<seite>_gluecksspiel`, `<seite>_ablegen_joker` |
| `webclient/cards/<schlüssel>.webp` | dieselben, 200 × 311 |
| `webclient/cards/farbe_<farbe>.webp` | Farbsymbole 96 × 96 |
| `res://assets/fonts/BricolageGrotesque.ttf`, `Fraunces.ttf`, `Fraunces-Italic.ttf`, `OFL.txt` | Schriften |
| `webclient/fonts/*.woff2`, `*.ttf`, `OFL.txt` | dieselben Schriften für den Browser, WOFF2 zuerst |
| `res://assets/ui/*.png`, `res://assets/ui/farben/*.png` | siehe oben |

Schlüssel der Farbsymbole: `rot gelb gruen blau pink tuerkis orange lila`.

Werte für Schriften in Godot über `FontVariation.variation_opentype`, Schlüssel als Tag, z. B. `TextServerManager.get_primary_interface().name_to_tag("opsz")`:

| Verwendung | Achsen |
|---|---|
| Kartenwerte, UI | Bricolage `wght` 800 (UI 700), `wdth` 75 im Index bzw. 100 im Fließtext, **`opsz` immer 12** |
| Überschriften und „Mau!“ | Fraunces `wght` 900, `SOFT` 100, `WONK` 0 im Schriftzug bzw. 1 bei „Mau!“ (kursiv), `opsz` 144 für große Schriftzüge |

## Abweichungen vom Plan

1. **Schriften im Browser-Client:** wie im Plan als WOFF2, **zusätzlich** die TTF.
   - Der Auftrag verlangt dieselben Dateien wie im Spiel, und `webclient/style.css` (Modul E) nennt die TTF als Rückfall.
   - Die erste Fassung hatte nur TTF. Seit der Nachbesserung erzeugt `woff2.pl` die WOFF2, also fällt diese Abweichung weg.
2. **Import:** Karten mit Mipmaps und verlustbehaftet (WebP 0,9); Bediensymbole, Farbsymbole und Logo mit Mipmaps. Der Plan legt das nicht fest. Begründung:
   - Ohne Mipmaps flimmern kleine Karten im Gegnerfächer (300 px Quelle auf etwa 60 px).
   - Verlustfrei wären es 17 MB in der APK, verlustbehaftet etwa 4 MB.
   - Modul C hat `default_texture_filter=3` gesetzt, die Mipmaps wirken also.
3. **Zusätzliche Dateien:**
   - `android_adaptive_monochrome_432.png` (Themensymbol)
   - Präfix `android_` in den Namen der Android-Symbole
   - Godot-Test `game/tests/test_b_assets.gd`
   - `tools/cards/woff2.pl`, `tools/cards/schriften.html`
4. **Nicht kopiert:** `seite.js`, `katze.js` und `build.sh` aus dem Entwurfsordner. Sie bauen nur Vorschauseiten bzw. die alte Vektorkatze, die Produktion braucht sie nicht. Der Entwurfsordner bleibt unverändert.

## Tests

**`game/tests/test_b_assets.gd`: RESULT: 125 ok** (headless, nach `tools/godot_import.ps1`, etwa 6 s). Geprüft wird:

- **Vertrag mit Modul A:** dieselben 108 Schlüssel wie `CardDB.all_keys()`, dieselben 128 wie `CardDB.all_keys(true)` und dieselben Gesichter je Hausregel wie `swap_keys()`, `gamble_keys()`, `discard_keys()`; ohne `rueckseite`. Fehlt `card_db.gd`, wird der Abgleich übersprungen.
- **Kartenbilder:**
  - alle 129 vorhanden (108 Grundgesichter, 20 Gesichter der Hausregeln, Rückseite), alle 300 × 466
  - Ecken transparent, Rand und Mitte deckend
  - alle Bilder verschieden
  - hell mit Papierrand, dunkel mit Nachtrand
  - Kartenfarbe aus dem Bild stimmt mit dem Schlüssel überein (120 farbige Karten)
  - alle von Godot importiert
- **Import:**
  - alle Karten mit `compress/mode=1`, Qualität 0,9 und Mipmaps
  - Projektfilter `default_texture_filter=3`
  - Stichprobe von 13 Karten: Textur mit Mipmaps, gegen das Quellbild mindestens 32 dB (gemessen 35,7 dB; über alle Karten mindestens 34,8 dB)
  - Bediensymbole, Farbsymbole und `logo_klein` mit Mipmaps
- **Browser-Bilder:**
  - alle 129 WebP 200 × 311 mit Alpha, 8 Farbsymbole
  - jede WebP passt zum PNG desselben Schlüssels: mindestens 24 dB und 3 dB besser als der Nachbarschlüssel. Gemessen: schlechtestes Paar 30,6 dB, ähnlichster Nachbar 18,6 dB.
- **Schriften:**
  - `webclient/fonts` byte-gleich mit dem Spiel
  - alle drei laden in Godot und haben die erwarteten Achsen
  - Zeichen wie Umlaute, ß, €, „“ und – vorhanden
  - nur Fraunces-Italic ist kursiv
  - `OFL.txt` vollständig
  - WOFF2: Kennung `wOF2`, lädt in Godot mit gleichen Namen, Achsen und Laufweiten wie die TTF
- **UI-Grafiken:**
  - alle 32 vorhanden mit der richtigen Größe und Deckung
  - Bediensymbole in Papierfarbe
  - Farbsymbole: Außenrand mit mindestens 3:1 gegen `#1B2040` und `#0A0D20`
  - Startbild: äußerste 2 px exakt `#0A0D20`, gleich `boot_splash/bg_color`

**Prüfungen im Bau (`build_cards.sh`):**

- Schriften geladen (`@@FONTS ok`), sonst Abbruch.
- Deckung jedes Bildes im Screenshot, sonst Abbruch. Mit einem leeren Bild nachgestellt: Abbruch mit Meldung.
- ffmpeg ab Version 7.
- WOFF2 gegen TTF in Chrome pixelgleich. Mit einer absichtlich beschädigten WOFF2 nachgestellt: „FEHLER Laden: NetworkError“, Abbruch.
- Kontrollbogen per Chrome: 109 geladen, 0 fehlend, 0 falsche Größe.

**Weitere Prüfungen:**

- Sichtprüfung aller Bögen, der Rückseite im Fächer, der adaptiven Symbole mit Masken, der WebP-Qualität und des Startbilds.
- Nach der Nachbesserung:
  - Farbsymbole auf `#0A0D20`, `#1B2040`, `#2A2350`, Papier und Lila-Feld
  - verlustbehafteter Import der zwei schlechtesten Karten (`hell_gelb_plus1`, `dunkel_orange_plus5`) gegen das Quellbild in dreifacher Vergrößerung
  - Startbild
- Neubau nach der Nachbesserung: Nur Farbsymbole (PNG und WebP) und Startbild haben sich geändert. Alle 109 Karten, alle WebP-Karten und die übrigen UI-Grafiken sind byte-gleich.

## Nachbesserung (nach der Prüfung)

| Befund | Schwere | Stand |
|---|---|---|
| Mipmaps ohne Mipmap-Filter | mittel | **behoben.** Modul C hat `default_texture_filter=3` gesetzt. Die Karten behalten ihre Mipmaps. Der Test prüft Filter, Import-Einstellung und geladene Texturen. |
| Karten verlustfrei, 16,9 MB in der APK | niedrig | **behoben.** `compress/mode=1`, Qualität 0,9: 4,0 MB. Schlechteste Karte 34,8 dB, Glut und Papierkorn im Vergleich in dreifacher Vergrößerung gleich. Der Test misst eine Stichprobe. |
| Lila-Farbsymbol auf dunklem Grund zu schwach | niedrig | **behoben.** Alle Farbsymbole haben einen hellen Außenrand: hell Papier, dunkel die aufgehellte Neonfarbe. Größe 80 statt 86 im 96er-Feld, damit der Rand Platz hat. Der Test prüft den Kontrast von mindestens 3:1. Die Kartengesichter sind unverändert. |
| Bediensymbole ohne Mipmaps | niedrig | **behoben.** `mipmaps/generate=true` für Bedien- und Farbsymbole sowie Logo. |
| Screenshot-Inhalt ungeprüft, ffmpeg-Version | niedrig | **behoben.** Deckungsprüfung je Bild, `render.html` zeichnet ohne Schriften nichts, Versionsprüfung ffmpeg ab 7, README ergänzt. |
| Startbild-Rand ±1 | niedrig | **behoben.** 4-px-Rahmen in reiner Nachtfarbe. Der Test prüft die äußersten 2 px exakt. |
| TTF statt woff2, 404-Anfragen | niedrig | **behoben.** WOFF2 liegt jetzt in `webclient/fonts/`. Die erste Quelle in `style.css` wird gefunden, die TTF-Rückfälle werden nicht mehr angefragt. `style.css` bleibt unverändert. |
| Test ohne CardDB-, Kursiv- und WebP-Abgleich | niedrig | **behoben.** Alle drei Prüfungen sind ergänzt, dazu WOFF2, Import, Farbsymbol-Kontrast und Startbild-Rand. 94 → 120 Prüfungen. |
| Standardinstanz der TTF (opsz 96) | niedrig | **behoben** (Doku). Warnung im Abschnitt Schriften. |
| `theme.tres` von Modul F in `assets/ui/` | niedrig | **offen, Entscheidung des Koordinators.** `build_cards.sh` schreibt nur benannte Dateien und löscht nichts in `assets/ui/`, die Datei ist also sicher. Der Test zählt keine Ordnerinhalte. Sauberer wäre ein eigener Ordner für Modul F, z. B. `res://assets/theme/`. |

## Offene Punkte und Hinweise an andere Module

- **Modul C:**
  - Export-Voreinstellung und Projekt sind wie empfohlen gesetzt: Symbole, `icon_512.png`, `splash.png`, `default_texture_filter=3`.
  - `tools/godot_run.ps1` reicht den Exitcode des Tests nicht durch. Maßgeblich sind die Zeilen `RESULT`/`FAIL`.
- **Modul E:**
  - `touch_icon_180.png` als `apple-touch-icon` nach `webclient/` kopieren; als Favicon eignet sich `android_main_192.png`.
  - Wer Platz sparen will, streicht die TTF-Rückfälle aus `style.css`. Dann können die drei TTF aus `webclient/fonts/` entfallen (1,2 MB weniger in `web.zip` und APK). WOFF2 können alle gängigen Browser seit etwa 2016, Safari ab iOS 10. Dafür müsste der Schritt `schriften` in `build_cards.sh` angepasst werden, er kopiert die TTF.
  - Der Browser-Client nutzt `farbe_<farbe>.webp` in der Farbanzeige, jetzt mit hellem Rand. Der SVG-Ersatz zeichnet dort ebenfalls einen Papierrand, beides passt zusammen.
- **Modul F:**
  - Kartenbilder sind 300 px breit. Eine Großansicht über etwa 300 px (bei 1,5-facher Skalierung auf dem S21 also über 200 px Basisbreite) wird weich. Falls nötig, Karten in doppelter Auflösung erzeugen: in `render.html` Zellengröße und Skalierung anpassen. Das wäre eine Planänderung, Abschnitt 3 sagt 300 × 466.
  - TTF nie als rohe Standardschrift setzen (siehe Schriften).
- **Prüfung auf echten Geräten** (S21/S10) steht noch aus. Zu prüfen sind Lila-Neon auf den Karten bei schwachen Displays, die Lesbarkeit des Eckindex im Fächer (siehe Entwurf, Offene Punkte 5) und die neuen Farbsymbole. Dafür muss ein Mensch auf das Display schauen; ein Bildschirmfoto per adb zeigt nur dieselben Pixel wie am PC.
- **Herkunft:** Die Katze in Logo, App-Symbolen und Startbild ist die KI-Illustration des Nutzers (`art/entwurf/a-papier-neon/katze_mau.png`). Alles andere ist selbst als Vektor gezeichnet.
