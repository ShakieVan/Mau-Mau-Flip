# Kartenbilder und Grafiken (Modul B)

Erzeugt alle Kartenbilder, Bediensymbole, Farbsymbole, App-Symbole, Logo und Startbild aus dem gewählten Entwurf A „Papier & Neon“ (`art/entwurf/a-papier-neon/`). Dazu spiegelt es die Schriften in den Browser-Client und packt sie als WOFF2.

## Aufruf

```bash
bash tools/cards/build_cards.sh                  # alles (etwa 35 s)
bash tools/cards/build_cards.sh karten bogen     # nur einzelne Schritte: karten symbole app logo splash schriften bogen tauschbogen zusatzbogen
MMF_ERSETZEN=1 bash tools/cards/build_cards.sh karten   # abweichende Kartenbilder wirklich ersetzen (siehe Ablauf, Schritt 5)
```

Voraussetzungen:

- Git Bash mit `perl` und `brotli` (beide liefert Git für Windows mit)
- Chrome (`CHROME=…` überschreibt den Pfad)
- ffmpeg **ab Version 7** mit libwebp (getestet 9.0.1). Ältere Versionen kennen `-/filter_complex` nicht; das Skript prüft die Version.
- Schriften in `game/assets/fonts/`

Zwischendateien liegen in `%TEMP%\mmf_build_cards`. Danach einmal `tools/godot_import.ps1`, damit Godot neue Bilder kennt. Prüfung: `tools/godot_run.ps1 -Script res://tests/test_b_assets.gd -Headless`.

## Ablauf

1. `render.html?blatt=<name>` zeichnet einen Bogen mit allen Bildern eines Schritts. Die Seite lädt die Schriften lokal aus `game/assets/fonts/` und wartet, bis sie geladen sind. Fehlen sie, zeichnet sie nichts und meldet `@@ERROR`. Die Lage jedes Bildes schreibt sie in `#out`.
   - Der Schritt `karten` zeichnet drei Bögen: `karten` mit den 108 Grundgesichtern und der Rückseite (Lage und Inhalt wie seit Beta 0.1.1), `tausch` mit den 8 Kartentausch-Gesichtern und `zusatz` mit den 12 Gesichtern von Glücksspiel und Farbe ablegen.
   - Getrennt, weil Chrome Glut-Filter kachelweise rastert: Neue Karten im selben Bogen ändern die Nachbarkarten um einzelne Farbstufen (gemessen 42–49 dB an vier dunklen Lila-Karten). Mit eigenem Bogen bleiben die alten Bilder byte-gleich. Weitere neue Karten bekommen deshalb jeweils einen eigenen Bogen.
2. `build_cards.sh` liest diese Lage per `--dump-dom`. Es bricht ab, wenn die Schriften fehlen. Dann macht es einen Screenshot in genau der Bogengröße mit transparentem Hintergrund.
3. **Deckungsprüfung:** Der Screenshot ist ein zweiter, unabhängiger Chrome-Lauf. Deshalb mittelt ein ffmpeg-Lauf jedes Bild auf ein Pixel und prüft das Alpha (Karten mindestens 240/255, sonst 8/255). Ein leerer oder halb gezeichneter Bogen bricht den Bau ab.
4. Ein einziger ffmpeg-Lauf je Bogen schneidet alle Bilder aus. Verkleinert wird mit vormultipliziertem Alpha, damit an den Ecken keine dunklen Säume entstehen.
5. **Übernahme der Kartenbilder** (`uebernehmen`): Kartenbilder (PNG und WebP) gehen zuerst nach `%TEMP%\mmf_build_cards\neu`.
   - Fehlt eine Datei im Ziel, wird sie geschrieben. Ist sie byte-gleich, passiert nichts.
   - Weicht sie ab, bleibt die alte Datei und der Bau meldet sie („abweichend und behalten“). Nur `MMF_ERSETZEN=1` ersetzt sie.
   - So kann eine neue Chrome- oder ffmpeg-Version die fertigen Gesichter nicht unbemerkt verändern (Nutzerwunsch: Karten nicht ändern).
   - Die übrigen Schritte (`symbole`, `app`, `logo`, `splash`) schreiben wie bisher direkt.
6. **Schriften:** TTF und `OFL.txt` werden nach `webclient/fonts/` gespiegelt. `woff2.pl` packt jede TTF als WOFF2: Null-Transformation, alle Tabellen bleiben Byte für Byte gleich, Brotli mit Qualität 11. `schriften.html` lädt TTF und WOFF2 im Browser und vergleicht die gezeichneten Glyphen Pixel für Pixel in mehreren Stärken, Breiten und Größen.
7. `kontrollbogen.html` zeigt die Kartenbilder aus `game/assets/cards/` auf kariertem Grund und prüft Anzahl und Größe.
   - Schritt `bogen`: alle 129 Bilder → `docs/module/B_kartenbogen.png`
   - Schritt `tauschbogen` (`?satz=tausch`): die 8 Kartentausch-Gesichter neben Richtungswechsel und Flip derselben Farbe, in Originalgröße und als Hand mit nur dem oberen Kartenteil → `docs/module/B_kartentausch.png`
   - Schritt `zusatzbogen` (`?satz=zusatz`): die 12 Gesichter von Glücksspiel und Farbe ablegen neben +1 bzw. +5, Kartentausch und Wünscher derselben Seite, in Originalgröße und als Hand → `docs/module/B_neue_karten.png`

## Dateien

| Datei | Inhalt |
|---|---|
| `mmf.js`, `logo.js` | Kopie des Entwurfsgenerators (Karten, Farben, Symbole, Logo, App-Symbol). `mmf.js` hat zusätzlich die Kartentypen `tausch`, `gluecks`, `ablegen` und `ablegenj` (siehe „Gestaltung ändern“). |
| `karten.js` | Alle 128 Gesichter mit den Schlüsseln aus `docs/BETA1_PLAN.md` Abschnitt 3 und den Hausregeln Kartentausch, Glücksspiel und Farbe mit ablegen, neutrale Rückseite `rueckseite`. `baseFaces()` = 108 Grundgesichter, `tauschFaces()` = 8, `gluecksFaces()` = 2, `ablegenFaces()` = 10, `zusatzFaces()` = Glücksspiel + Farbe ablegen, `deckFaces()` = alle 128, `allKeys()` = 129 Schlüssel. |
| `symbole.js` | Bediensymbole, Farbsymbole, Android-Symbole (adaptiv, einfarbig), Touch-Icon, Startbild |
| `render.html` | Bogenseite für Chrome ohne Fenster |
| `kontrollbogen.html` | Kontrollbögen der fertigen PNGs (alle, `?satz=tausch` bzw. `?satz=zusatz`) |
| `woff2.pl` | TTF → WOFF2 (Null-Transformation, Brotli über den `brotli`-Befehl, ohne Python) |
| `schriften.html` | Vergleich WOFF2 gegen TTF im Browser |
| `build_cards.sh` | Der ganze Ablauf |

Die Katze im Logo und in den App-Symbolen ist `art/entwurf/a-papier-neon/katze_mau.png`, eine KI-Illustration des Nutzers.

## Ausgaben

| Ziel | Inhalt |
|---|---|
| `game/assets/cards/<schlüssel>.png` | 129 Bilder (128 Gesichter + Rückseite), 300 × 466, transparente Ecken (Import siehe unten) |
| `webclient/cards/<schlüssel>.webp` | dieselben, 200 × 311, WebP Qualität 85 mit Alpha |
| `webclient/cards/farbe_<farbe>.webp` | 8 Farbsymbole, 96 × 96 |
| `game/assets/ui/<name>.png` | 15 Bediensymbole, 96 × 96, Papierfarbe `#F4EADA` auf transparent |
| `game/assets/ui/farben/<farbe>.png` | 8 Farbsymbole, 96 × 96 (hell: Fläche mit Druckfarben-Kontur und Papierrand, dunkel: Neon mit Nachtkontur und aufgehelltem Neonrand) |
| `game/assets/ui/logo.png`, `logo_klein.png` | 1600 × 900, 800 × 450 |
| `game/assets/ui/icon_512.png` | App-Symbol 512 mit runden Ecken |
| `game/assets/ui/android_main_192.png` | Android-Symbol 192 |
| `game/assets/ui/android_adaptive_{foreground,background,monochrome}_432.png` | adaptives Android-Symbol, 432 × 432 |
| `game/assets/ui/splash.png` | Startbild 1600 × 720, äußerste 4 px genau `#0A0D20` |
| `webclient/fonts/` | `BricolageGrotesque`, `Fraunces`, `Fraunces-Italic` als `.woff2` und `.ttf`, dazu `OFL.txt` |
| `game/assets/ui/touch_icon_180.png` | iOS-Touch-Icon ohne Eckenrundung (iOS rundet selbst) |

## Import in Godot

Die Einstellungen stehen in den `.import`-Dateien neben den Bildern und gehören zum Modul. Ein neuer Bau überschreibt nur die PNGs, die `.import`-Dateien bleiben.

- **Karten** (`game/assets/cards/*.png.import`): `compress/mode=1` (verlustbehaftetes WebP), `compress/lossy_quality=0.9`, `mipmaps/generate=true`.
  - Die 109 Bilder des Grunddecks belegen in der APK etwa 4 MB statt 17 MB, die 8 Kartentausch-Gesichter zusammen etwa 0,3 MB, die 12 Gesichter von Glücksspiel und Farbe ablegen zusammen etwa 0,5 MB.
  - Im Speicher ändert sich nichts: etwa 0,75 MB je Karte mit Mipmaps.
  - Schlechteste Karte gegen das Quellbild: 34,8 dB (`hell_gelb_plus1`). Papierkorn und Neon-Glut sind in dreifacher Vergrößerung gleich.
  - Neue Kartenbilder brauchen ihre `.import`-Datei **vor** dem ersten Import, sonst importiert Godot verlustfrei ohne Mipmaps. Es reicht eine Kopie mit `[remap]` (`importer`, `type`), `[deps] source_file` und dem `[params]`-Block einer vorhandenen Karte; `uid`, `path` und `dest_files` ergänzt Godot beim Import.
- **Bediensymbole, Farbsymbole, Logo** (`game/assets/ui/*.png.import` außer App-Symbolen und Startbild): `mipmaps/generate=true`, verlustfrei.
- Mipmaps wirken nur mit dem Projektfilter `rendering/textures/canvas_textures/default_texture_filter=3` (Linear Mipmap, Modul C). Der Test prüft das.

## Gestaltung ändern

- **Kartengesichter:** nur nach Rücksprache mit dem Nutzer („Karten schön so wie sie sind, bitte nicht ändern“).
  - `mmf.js` ist mit dem Entwurf abgeglichen: Die 20 Entwurfs-SVGs aus `art/entwurf/a-papier-neon/cards/` entstehen daraus Byte für Byte gleich (zuletzt geprüft am 05.10.2026 nach dem Einbau von Glücksspiel und Farbe ablegen).
  - Eine Änderung an bestehenden Gesichtern gehört in beide Kopien.
- **Kartentausch** (nur Produktion, nicht im Entwurf): `tauschPrims()` und `rrPath()` in `mmf.js`, dazu je ein Eintrag `tausch` in `TYPE_NAMES`, `indexContent()`, `lightValue()` und `darkValue()`.
  - Drei aufrechte Karten im Dreieck (Plätze am Tisch), dazwischen drei kräftige Bogenpfeile im Uhrzeigersinn, ohne Streifen.
  - Die kleinen Karten haben einen Trennrand (`front`, `ringW: 6`): groß in Druck- bzw. Nachtfarbe, im Eckindex in Papier- bzw. Nachtfarbe.
  - Innenfeld (`panel`): hell die tiefe Kartenfarbe, dunkel eine Mischung aus Feld und Neon. Im Eckindex sind die Karten voll in der Wertfarbe.
  - `renderPrims()` kennt dafür `ringW` (Breite des Trennrands, sonst wie bisher 9).
  - Die Erweiterung ist rein additiv: Die Entwurfs-SVGs und alle 109 alten Bilder bleiben byte-gleich.
- **Glücksspiel** (nur Produktion): `gluecksPrims()` in `mmf.js`, Typ `gluecks` (Joker). Runder Glücksspielknopf mit Fragezeichen auf flachem Sockel, vorn das Zahlenwerk „0–10“ zwischen vier Lampen in den Farben der Seite, daneben Glücksfunkel. Hell: Knopf in Druckfarbe; dunkel: Knopf im Regenbogenverlauf des dunklen Jokers. Im Eckindex ohne Zahlenwerk und Lampen.
- **Farbe ablegen** (nur Produktion): `ablegenPrims()` und `ablegenCard()` in `mmf.js`, Typen `ablegen` (farbig) und `ablegenj` (Joker). Flacher Handfächer, aus dem zwei Karten der Farbe nach unten herausrutschen (Lücke mit Bewegungsstrichen), darunter ein Pfeil nach unten. Die übrigen Handkarten sind neutral (`ncard`/`npanel`), die abrutschenden tragen die tiefe Kartenfarbe mit Farbsymbol bzw. beim Joker vier Farbstreifen. Im Eckindex drei Karten, die mittlere rutscht.
- Dafür kennt `renderPrims()` zusätzlich Schrift im Symbol (`kind: 'text'`) und Formen ohne Kontur (`nosil`), `iconPrims()` bekommt über `iconOpt()` Index, Joker und Farbsymbol. Alles rein additiv: die Entwurfs-SVGs und alle 117 älteren Bilder bleiben byte-gleich.
- **Rückseite:** `backSVG()` in `karten.js`.
- **Bediensymbole:** `UI_ICONS` in `symbole.js`, Raster 96 × 96, Linienstärke 8.
- **Farbsymbole:** `colorSymbolSVG()` und `farbRand()` in `symbole.js`. Der helle Außenrand sorgt für mindestens 3:1 Kontrast auf dunklem Tisch, der Test prüft das.
