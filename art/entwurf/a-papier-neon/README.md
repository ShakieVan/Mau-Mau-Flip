# Mau-Mau Flip, Entwurf A: „Papier & Neon“

Gestaltungsentwurf für Karten, Logo und App-Symbol. Alles ist selbst als Vektor gezeichnet und wird aus `quelle/` erzeugt. Es sind keine fremden Bilder eingebettet.

## Dateien

| Datei | Inhalt |
|---|---|
| `cards/*.svg` | 20 Kartenseiten: die 16 geforderten und 4 zusätzliche für die Handansicht (`hell_gelb_3`, `hell_gruen_6`, `dunkel_orange_9`, `dunkel_tuerkis_aussetzen`) |
| `logo.svg`, `logo.png` | Logo im Querformat, 1600 × 900 |
| `icon.svg`, `icon.png` | App-Symbol, 512 × 512 |
| `hand.html`, `hand.png` | Handansicht, Handy quer (1600 × 720 px ≈ 800 × 360 dp) |
| `preview.html`, `preview.png` | Gesamtübersicht: Logo, App-Symbol in 512/96/48 px, alle Karten, Hand, Palette, Begründung |
| `bild_prompt.md` | Englischer Prompt für einen KI-Bildgenerator (Logo-Motiv) mit deutscher Erläuterung |
| `quelle/` | Generator: `mmf.js` (Karten, Farben, Symbole), `katze.js`, `logo.js`, `seite.js`, `build.html`, `build.sh` |

**Neu erzeugen** (Git Bash, Chrome installiert): `bash quelle/build.sh` schreibt alle SVG/HTML-Dateien und rendert die PNGs. Mit `--keine-png` entstehen nur die Dateien.

## Gestaltungsidee

**Tag und Nacht der Mau-Katze.** Beide Seiten zeigen dieselbe Landschaft: Ein Himmelskörper steht über einem gestreiften Meer.

- **Helle Seite: Siebdruck auf Papier.**
  - Warmer Papierrand, das Farbfeld voll in der Kartenfarbe.
  - Sonnenstrahlen mit rund 9 % Kontrast und feinem Papierkorn.
  - Der Wert ist als Papier ausgespart (Creme) und hat eine Kontur in Druckfarbe.
- **Dunkle Seite: Neon in der Nacht.**
  - Nachtblauer Grund, Leuchtkontur in der Kartenfarbe.
  - Mondsichel hinter dem Wert, Sterne, Spiegellinien im Meer.
  - Der Wert leuchtet in Mondlicht.
- **Papierlasche.** Das Farbfeld spart oben links und unten rechts (um 180° gedreht) eine Lasche aus.
  - Dort steht der Eckindex: Wert groß in schmaler Schrift, darunter das Farbsymbol.
  - Die Lasche ist 158 von 560 Einheiten breit. Wert und Symbol liegen in den linken rund 150 Einheiten. Bei einer Kartenbreite von 95 dp sind das etwa 25 dp, ab etwa 80 dp Kartenbreite passen sie in einen Streifen von 22 dp. In der Handansicht ist jeder Streifen 36 dp breit.
  - Die Lasche gibt der Karte eine eigene Silhouette, die man sofort wiedererkennt.
- **Aktionssymbole als Katzenmotive:**
  - Aussetzen: schlafende Katze mit „zz“.
  - Alle aussetzen: drei schlafende Katzen.
  - Richtungswechsel: zwei Bogenpfeile, getigert wie Katzenschwänze.
  - Flip: Tag/Nacht-Scheibe.
  - Wünscher: Pfote mit vier Farbzehen.
  - Zieh +1/+5 und Wünscher +2: Kartenfächer hinter dem Wert.
  - Farbjagd: Kartenstapel mit „?“ und Pfote im Index.
  - Der helle Wünscher hat einen Sonnenkranz in den vier Farben. Der dunkle hat eine Regenbogen-Neonkontur.
- **Logo.** Die Bildfläche ist schräg geteilt: links Papier mit Sonnenstrahlen, rechts Nacht mit Sternen.
  - Die getigerte Katze sitzt auf der Wendelinie, schaut nach oben und tippt mit der Pfote ans offene Maul. Eine Sprechblase sagt „Mau!“.
  - Seit 04.10.2026 ist die Katze die Illustration des Nutzers (`katze_mau.png`, 1209×1301 mit Alphakanal), eingebunden als `<image>` in der Lage seiner Montage (`art/referenz/logo_montage_nutzer.png`). Die Vektorkatze (`quelle/katze.js`) dient nur noch dem App-Symbol.
  - Dahinter steht links eine Sonnenkarte, rechts eine Mondkarte.
  - Der Schriftzug wechselt die Seite: „Mau-Mau“ in Druckfarbe auf Papier, „Flip“ als Neon in der Nacht.
  - Die Tigerzeichnung auf der Stirn bildet ein „M“ wie Mau.
- **App-Symbol.** Die Katze als Büste vor Tag (Sonne) und Nacht (Mond). Bei 48 px bleibt sie als Katzengesicht erkennbar.

## Karten-Technik

- Format 56:87, `viewBox="0 0 560 870"`, Eckradius 40.
- **Benannte Ebenen** in jeder Karte, für spätere Effekte:
  - `rahmen`: Kartenkörper und Kontur, für die Joker-Strahlen.
  - `grund`: Farbfeld, Strahlen bzw. Neonkontur.
  - `motiv`: Sonne bzw. Mond, Meer, Sterne.
  - `symbol`: Farbsymbole in den freien Feldecken.
  - `wert`: Zahl oder Aktionssymbol.
  - `index`: enthält `index_oben` und `index_unten`.
- 6 und 9 sind in der Mitte und im Index unterstrichen.
- Der Eckindex ist mindestens 18 dp hoch, wenn die Karte in der Hand rund 95 dp breit ist.

## Farben und Symbole

| Seite | Farbe | Fläche | Neon (Kontur) | Symbol | OKLab-L |
|---|---|---|---|---|---|
| hell | Rot | `#B3202A` | – | Flamme | 0,50 |
| hell | Gelb | `#FFDD33` | – | Sonne | 0,90 |
| hell | Grün | `#43B05C` | – | Kleeblatt | 0,67 |
| hell | Blau | `#2A5BD7` | – | Kristall | 0,52 |
| dunkel | Pink | `#FF9ECF` | `#FFB3DC` | Herz | 0,81 |
| dunkel | Türkis | `#00838F` | `#0B97A3` | Welle | 0,56 |
| dunkel | Orange | `#FF6F00` | `#FF7F14` | Laterne | 0,71 |
| dunkel | Lila | `#4527A0` | `#5E3BD8` | Stern | 0,39 |

Weitere Farben: Papier `#F4EADA`, Druckfarbe `#211B2C`, Nacht `#0A0D20`, Mondlicht `#F4F0FF`.

**Prüfung.** Kleinster OKLab-Abstand unter Simulation nach Machado 2009, Schweregrad 1. Die Rechnung steht im Generator und in `preview.html`:

| Satz | Wert |
|---|---|
| hell | 0,152 (Grün–Blau, Blau-Gelb-Schwäche) |
| dunkel, Flächen | 0,160 |
| dunkel, Neon | 0,161 |

Gegenüber der Startpalette habe ich zwei Dinge angepasst:

- Pink ist minimal heller (`#FF99CC` → `#FF9ECF`). Mit der Startfarbe lag Pink–Orange bei Blau-Gelb-Schwäche in meiner Rechnung bei 0,149, jetzt bei 0,161.
- Die Neonvarianten folgen derselben Helligkeitsstaffel.

Helle und dunkle Seite unterscheiden sich auch ohne Farbsehen deutlich: Papierfläche gegen Nachtgrund. Die Symbole sind eigene Entwürfe.

## Schriften

| Schrift | Verwendung | Lizenz | Quelle |
|---|---|---|---|
| **Bricolage Grotesque** (Mathieu Triay) | Kartenwerte, Index mit Breite 75 %, Oberfläche | SIL Open Font License 1.1 | Google Fonts |
| **Fraunces** (Undercase Type: Phaedra Charles, Flavia Zimbardi) | Schriftzug „Mau-Mau Flip“, „Mau!“ | SIL Open Font License 1.1 | Google Fonts |

- Die HTML-Vorschauen laden beide Schriften per `<link>` von fonts.googleapis.com.
- Die SVGs setzen `font-family` und binden die Schrift zusätzlich per `@import` ein, damit sie auch einzeln geöffnet richtig aussehen.

## Abstand zum Vorbild

- Kein Oval, nichts schräg gestellt, keine Zahl im Oval, keine Schlagschatten an Zahlen.
- Keine rote Oval-Rückseite. Hier gibt es überhaupt keine neutrale Rückseite: Die „Rückseite“ ist die andere Spielseite.
- Kein fremdes Logo, kein fremder Name. Der Name des Vorbilds steht in keiner Datei.
- **Eigene Bildsprache:**
  - Papierlasche statt Index auf der Farbfläche.
  - Sonne bzw. Mond hinter aufrechten Werten.
  - Siebdruck- und Neon-Ästhetik.
  - Katzenmotive für alle Aktionen.
  - Der Joker ist ein Sonnenkranz bzw. eine Regenbogenkontur, keine viergeteilte Ellipse.
- Übernommen ist nur das Funktionsprinzip: große Zahl, Kartenfarbe, Eckindex.

## Offene Punkte

1. **Stil der Katze.** Erledigt: Logo und App-Symbol zeigen die Illustration des Nutzers. Die Vektorkatze in `quelle/katze.js` wird nicht mehr verwendet.
2. **Godot-Import.** Godot rendert SVG über ThorVG. Text in SVG wird dort nicht dargestellt. Filter (Glühen, Papierkorn) und `mix-blend-mode` werden ignoriert. Vorschlag:
   - Werte zur Laufzeit als Label mit der Schrift (MSDF) setzen oder vorher in Pfade umwandeln (Inkscape: Objekt in Pfad).
   - Glühen und Korn als Shader nachbauen. Die benannten Ebenen sind dafür vorbereitet.
3. **Vollständiger Satz.** Der Generator kann alle 112 Karten erzeugen. Dafür fehlt nur die Liste der Kartenpaare, also welche helle Seite zu welcher dunklen gehört.
4. **Rückseiten der Mitspieler.** Ist die globale Option „Rückseiten sichtbar“ aus, braucht der Tisch eine neutrale Darstellung, z. B. einen abgedunkelten Kartenkörper ohne Wert. Das ist noch nicht entworfen.
5. **Auf dem Gerät prüfen.**
   - Lila-Neon ist auf dem Nachtgrund bewusst dunkel (Helligkeitsstaffel) und könnte auf schwachen Displays zu matt wirken.
   - Der helle Wünscher ist sehr bunt.
   - Beides an echten Bildschirmen und mit Farbsehschwäche-Simulation testen.
6. **Android-Adaptive-Icon.** `icon.svg` ist eine fertige 512-px-Fläche mit Eckenrundung. Für Android braucht es noch getrennte Vorder- und Hintergrundebenen mit Sicherheitszone.
7. **Herkunft.** Die Posevorlage und die Logo-Katze (`katze_mau.png`, Original `art/referenz/katze_mau_original.webp`) sind KI-Bilder, die der Nutzer erzeugt hat. Weitere KI-Grafik ebenso dokumentieren.

## Änderungen

- **04.10.2026, nach Nutzerrückmeldung:** Richtung A gewählt.
  - Logo-Katze durch die Illustration des Nutzers ersetzt.
  - Spiegelung des Mondes auf der dunklen Seite zentriert (war um 60 Einheiten nach links versetzt).
  - Werte mit fester optischer Größe `opsz 12` gesetzt. Vorher wählte der Browser bei großen Werten `opsz 96`, und 6 und 9 verjüngten sich in der Mitte zu stark.
- **04.10.2026, zweite Rückmeldung:** Karten bleiben unverändert (Nutzerwunsch).
  - App-Symbol: Kopf und Pfote der Nutzer-Katze als Büste vor Tag und Nacht, Sonne als leuchtende Scheibe statt Kreis mit Kontur.
  - Handansicht: Ablagestapel auf Höhe des Nachziehstapels und spiegelbildlich zur Tischmitte; die aktuelle Farbe steht zwischen den Stapeln.
