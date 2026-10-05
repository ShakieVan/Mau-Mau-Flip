# Kartenbilder und Grafiken (Modul B)

Erzeugt alle Kartenbilder, Bediensymbole, Farbsymbole, App-Symbole, Logo und Startbild aus dem gewählten Entwurf A „Papier & Neon“ (`art/entwurf/a-papier-neon/`). Dazu spiegelt es die Schriften in den Browser-Client und packt sie als WOFF2.

## Aufruf

```bash
bash tools/cards/build_cards.sh                  # alles (etwa 30 s)
bash tools/cards/build_cards.sh karten bogen     # nur einzelne Schritte: karten symbole app logo splash schriften bogen
```

Voraussetzungen:

- Git Bash mit `perl` und `brotli` (beide liefert Git für Windows mit)
- Chrome (`CHROME=…` überschreibt den Pfad)
- ffmpeg **ab Version 7** mit libwebp (getestet 9.0.1). Ältere Versionen kennen `-/filter_complex` nicht; das Skript prüft die Version.
- Schriften in `game/assets/fonts/`

Zwischendateien liegen in `%TEMP%\mmf_build_cards`. Danach einmal `tools/godot_import.ps1`, damit Godot neue Bilder kennt. Prüfung: `tools/godot_run.ps1 -Script res://tests/test_b_assets.gd -Headless`.

## Ablauf

1. `render.html?blatt=<name>` zeichnet einen Bogen mit allen Bildern eines Schritts. Die Seite lädt die Schriften lokal aus `game/assets/fonts/` und wartet, bis sie geladen sind. Fehlen sie, zeichnet sie nichts und meldet `@@ERROR`. Die Lage jedes Bildes schreibt sie in `#out`.
2. `build_cards.sh` liest diese Lage per `--dump-dom`. Es bricht ab, wenn die Schriften fehlen. Dann macht es einen Screenshot in genau der Bogengröße mit transparentem Hintergrund.
3. **Deckungsprüfung:** Der Screenshot ist ein zweiter, unabhängiger Chrome-Lauf. Deshalb mittelt ein ffmpeg-Lauf jedes Bild auf ein Pixel und prüft das Alpha (Karten mindestens 240/255, sonst 8/255). Ein leerer oder halb gezeichneter Bogen bricht den Bau ab.
4. Ein einziger ffmpeg-Lauf je Bogen schneidet alle Bilder aus. Verkleinert wird mit vormultipliziertem Alpha, damit an den Ecken keine dunklen Säume entstehen.
5. **Schriften:** TTF und `OFL.txt` werden nach `webclient/fonts/` gespiegelt. `woff2.pl` packt jede TTF als WOFF2: Null-Transformation, alle Tabellen bleiben Byte für Byte gleich, Brotli mit Qualität 11. `schriften.html` lädt TTF und WOFF2 im Browser und vergleicht die gezeichneten Glyphen Pixel für Pixel in mehreren Stärken, Breiten und Größen.
6. `kontrollbogen.html` zeigt alle 109 Kartenbilder aus `game/assets/cards/` auf kariertem Grund und prüft Anzahl und Größe. Der Screenshot landet in `docs/module/B_kartenbogen.png`.

## Dateien

| Datei | Inhalt |
|---|---|
| `mmf.js`, `logo.js` | Unveränderte Kopie des Entwurfsgenerators (Karten, Farben, Symbole, Logo, App-Symbol) |
| `karten.js` | Alle 108 Gesichter mit den Schlüsseln aus `docs/BETA1_PLAN.md` Abschnitt 3, neutrale Rückseite `rueckseite` |
| `symbole.js` | Bediensymbole, Farbsymbole, Android-Symbole (adaptiv, einfarbig), Touch-Icon, Startbild |
| `render.html` | Bogenseite für Chrome ohne Fenster |
| `kontrollbogen.html` | Kontrollbogen der fertigen PNGs |
| `woff2.pl` | TTF → WOFF2 (Null-Transformation, Brotli über den `brotli`-Befehl, ohne Python) |
| `schriften.html` | Vergleich WOFF2 gegen TTF im Browser |
| `build_cards.sh` | Der ganze Ablauf |

Die Katze im Logo und in den App-Symbolen ist `art/entwurf/a-papier-neon/katze_mau.png`, eine KI-Illustration des Nutzers.

## Ausgaben

| Ziel | Inhalt |
|---|---|
| `game/assets/cards/<schlüssel>.png` | 109 Bilder, 300 × 466, transparente Ecken (Import siehe unten) |
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
  - Alle 109 Karten belegen in der APK etwa 4 MB statt 17 MB.
  - Im Speicher ändert sich nichts: etwa 0,75 MB je Karte mit Mipmaps.
  - Schlechteste Karte gegen das Quellbild: 34,8 dB (`hell_gelb_plus1`). Papierkorn und Neon-Glut sind in dreifacher Vergrößerung gleich.
- **Bediensymbole, Farbsymbole, Logo** (`game/assets/ui/*.png.import` außer App-Symbolen und Startbild): `mipmaps/generate=true`, verlustfrei.
- Mipmaps wirken nur mit dem Projektfilter `rendering/textures/canvas_textures/default_texture_filter=3` (Linear Mipmap, Modul C). Der Test prüft das.

## Gestaltung ändern

- **Kartengesichter:** nur nach Rücksprache mit dem Nutzer („Karten schön so wie sie sind, bitte nicht ändern“).
  - `mmf.js` ist mit dem Entwurf abgeglichen: Die 19 Entwurfskarten aus `art/entwurf/a-papier-neon/cards/` entstehen daraus Byte für Byte gleich.
  - Eine Änderung gehört in beide Kopien.
- **Rückseite:** `backSVG()` in `karten.js`.
- **Bediensymbole:** `UI_ICONS` in `symbole.js`, Raster 96 × 96, Linienstärke 8.
- **Farbsymbole:** `colorSymbolSVG()` und `farbRand()` in `symbole.js`. Der helle Außenrand sorgt für mindestens 3:1 Kontrast auf dunklem Tisch, der Test prüft das.
