# Entwurf B „Art déco / Tarot“

Gestaltungsentwurf für Karten, Logo und App-Symbol von Mau-Mau Flip. Alles ist selbst als Vektor gezeichnet und wird von einem Perl-Skript erzeugt. Es gibt keine eingebetteten fremden Bilder.

## Gestaltungsidee

**Tag und Nacht der Mau-Katze als Art-déco-Tarot.** Beide Kartenseiten haben dieselbe Bauordnung: Goldrahmen, Bogenfenster mit Landschaft, Schlussstein mit Farbsymbol, hängendes Index-Banner und Titelband. So wirkt der Flip wie eine Verwandlung.

| | Helle Seite „Tag“ | Dunkle Seite „Nacht“ |
|---|---|---|
| Grund | Elfenbeinpapier, feine Goldlinien | Mitternachtsblau, Goldlinien und Neonkontur in der Kartenfarbe |
| Bogenfenster | Sonnenaufgang mit Ringen, Strahlenkranz, Berge, gestreiftes Wasser | Mondsichel, Sterne, Mondphasen am Bogen, schwarze Berge, Neon-Spiegelung |
| Großer Wert | aufrecht, Kartenfarbe mit Tintenkontur, Papierfuge und Goldlinie | Neonröhre: helle Kontur mit Leuchten auf dunkler Füllung |
| Index | Banner in voller Kartenfarbe mit Wert und Formsymbol | gleich, mit Leuchtsaum |

**Funktion zuerst.** Das Index-Banner hängt oben links von der Rahmenlinie (x = 28…132 von 560) und liegt damit vollständig im 22-dp-Streifen, der im Fächer sichtbar bleibt. Es zeigt Wert (Limelight, 122 Einheiten) und Formsymbol. Unten rechts steht es um 180° gedreht. Im oberen Kartendrittel stehen außerdem der Schlussstein mit dem Farbsymbol und der obere Teil des großen Werts. Die Handansicht (`hand.png`) zeigt neun Karten mit etwa 22 dp Streifen.

**Erwachsen statt kindlich.** Feine Goldlinien, Eckfächer, Bogenfenster und Display-Schrift der 1920er. Die Werte stehen aufrecht mit doppelter Kontur statt mit Schlagschatten.

**Eigene Aktionssymbole:**

| Karte | Symbol |
|---|---|
| Aussetzen | Sanduhr |
| Alle aussetzen | Sanduhr im Ring mit vier Punkten |
| Richtungswechsel | zwei Kreispfeile |
| Flip | Scheibe: links Sonne mit Strahlen, rechts Nacht mit Stern |
| Wünscher | Katzenpfote, die vier Zehen in den vier Farben der Seite |
| Wünscher +2 | Pfote über „+2“ |
| Farbjagd | Katzenauge mit Iris aus vier Farbbögen und Schlitzpupille |
| +1 / +5 | „+1“ / „+5“ als großer Wert |

**Logo.** Eine Smokingkatze (Mitternachtsblau, elfenbeinfarbener Latz, weiße Pfoten) sitzt im Profil, hebt den Kopf, öffnet das Maul und legt die Pfote ans Maul. Goldenes Streiflicht links (Tag), violettes rechts (Nacht), Halsband mit Sonne-Mond-Medaillon. Dahinter links die Tag-Karte, rechts die Nacht-Karte im Kartendesign, darüber die Sprechblase „Mau!“, darunter der Schriftzug „Mau-Mau Flip“. Bei „Flip“ wechselt die Farbe mitten im Wort von Elfenbein zu Violett. Die Katze ist bewusst stilisiert (Profil statt Dreiviertelansicht), weil diese Form als Vektor sicher sauber wirkt. Für eine reichere Illustration in der Pose der Referenz siehe `bild_prompt.md`.

**App-Symbol.** Die Katze als Brustbild hinter einer goldenen Brüstung vor einer Scheibe aus Tag (links) und Nacht (rechts). Ohren, Scheibe und Pfote tragen auch bei 48 px.

## Dateien

| Datei | Inhalt |
|---|---|
| `cards/*.svg` | 23 Karten (16 geforderte und 7 Zusatzkarten für die Handansicht), viewBox `0 0 560 870`, Ecken mit Radius 34 |
| `logo.svg`, `logo.png` | Logo 1600 × 900 |
| `icon.svg`, `icon.png` | App-Symbol 512 × 512 (PNG mit transparenten Ecken) |
| `preview.html`, `preview.png` | Gesamtübersicht: Logo, App-Symbol in 512/96/48 px, alle Kartenpaare, Handansichten hell und dunkel, Palette, Graustufenprobe, Begründung |
| `hand.html`, `hand.png` | Handbildschirm 1600 × 720 (helle Phase) |
| `logo.html`, `icon.html` | Hilfsseiten zum Rendern mit geladenen Schriften |
| `bild_prompt.md` | Prompt für einen KI-Bildgenerator |
| `generator/` | `erzeugen.pl` (baut alles), `karten.pl`, `katze.pl`, `logo.pl` |

**Ebenen jeder Karten-SVG** (für spätere Effekte): `grund` (Papier oder Nacht), `motiv` (Bogenlandschaft, Sonne oder Mond, Sterne), `rahmen` (Goldrahmen, Bogenkontur, Neonkontur, Eckfächer, Titelband), `wert` (großer Wert oder Aktionssymbol), `symbol` (Schlussstein mit Farbsymbol), `index` (beide Banner). Strahlen-Effekte können an der Bogen- und Bannerkontur ansetzen; beim Flip lassen sich Sonne und Mond in `motiv` tauschen.

**Neu erzeugen** (Git Bash, im Ordner `b-art-deco`):

```bash
perl generator/erzeugen.pl
"/c/Program Files/Google/Chrome/Application/chrome.exe" --headless=new --disable-gpu --hide-scrollbars --virtual-time-budget=8000 --window-size=1600,3200 --screenshot="<absoluter Pfad>/preview.png" "file:///E:/Documents/Programmierung/Mau-Mau%20Flip/art/entwurf/b-art-deco/preview.html"
```

Weitere Karten entstehen durch einen Eintrag in `@CARDS` in `generator/karten.pl` (Name, Seite, Farbe, Typ, Wert).

## Schriften

| Schrift | Verwendung | Urheber | Lizenz |
|---|---|---|---|
| **Limelight** | Werte, Index, Schriftzug, „Mau!“ | Sorkin Type (Google Fonts) | SIL Open Font License 1.1 |
| **Josefin Sans** | Titelband (Farbwort), Bedienelemente | Santiago Orozco (Google Fonts) | SIL Open Font License 1.1 |

Die HTML-Seiten laden beide per `<link>` von fonts.googleapis.com. Die SVGs setzen nur `font-family` (Ersatz: Playfair Display, Georgia, serif bzw. Century Gothic, Futura, sans-serif). Ohne installierte Schrift zeigt eine einzeln geöffnete SVG die Ersatzschrift.

## Farben und Barrierefreiheit

- Kernfarben unverändert aus der Recherche: hell Rot `#B3202A`, Gelb `#FFDD33`, Grün `#43B05C`, Blau `#2A5BD7`; dunkel Pink `#FF99CC`, Türkis `#00838F`, Orange `#FF6F00`, Lila `#4527A0`. Die Helligkeitsstaffel bleibt damit erhalten.
- Für Neonlinien auf der Nachtseite gibt es hellere Leuchttöne (Pink `#FFC6E2`, Türkis `#3FD9E4`, Orange `#FFA64D`, Lila `#B9A6FF`), für die Berge der hellen Seite dunklere Schattentöne. Sie tragen keine Farbinformation allein.
- Formsymbole: hell Flamme, Sonne, Kleeblatt, Kristall; dunkel Herz, Welle, Laterne, Stern. Sie stehen im Index-Banner, im Schlussstein und in der Farbanzeige am Tisch.
- Seiten ohne Farbsehen unterscheidbar: Elfenbeinpapier gegen Nachtgrund (siehe Graustufenprobe in `preview.png`).
- 6 und 9 sind im großen Wert und im Index unterstrichen. Das Farbwort steht im Titelband.
- Textfarbe im Banner nach Kontrast: Elfenbein auf Rot, Blau, Türkis, Lila; Tinte auf Gelb, Grün, Pink, Orange.

## Abstand zum Vorbild

- Kein Oval in der Kartenmitte, nichts Schräges, keine Zahl mit Schlagschatten. Die Mitte ist ein aufrechtes Bogenfenster, die Werte stehen gerade.
- Kein fremdes Logo, kein fremder Schriftzug, keine Rückseite mit Oval. Die Karten haben zwei Vorderseiten im eigenen Stil.
- Alle Aktionssymbole sind eigene Entwürfe (Sanduhr, Kreispfeile, Sonne-Mond-Scheibe, Pfote, Katzenauge). Auch die Joker vermeiden vierfarbige Viertelflächen: Farben erscheinen als Zehen, Irisbögen und Strahlen.
- Der Name des Vorbilds kommt in keiner Datei vor.

## Offene Punkte

1. **Leuchttöne prüfen.** Die abgeleiteten Neon- und Schattentöne sowie die Logo-Farben (Sonne `#E8762B`, Mond `#6F55E8`) sind nicht mit der Farbsehschwäche-Rechnung geprüft. Lila auf Nachtgrund ist der schwächste Kontrast und sollte auf dem Gerät getestet werden.
2. **Text in Pfade wandeln oder in Godot zeichnen.** Werte und Titel sind echte Texte. Für den Godot-Import entweder in Pfade umwandeln (Inkscape: „Objekt in Pfad“) oder die Ebenen `wert` und `index` in Godot mit Limelight als MSDF-Schrift setzen.
3. **Leuchten als Shader.** Die SVGs nutzen `feGaussianBlur` für Glühen. Ob der SVG-Import in Godot diese Filter unterstützt, ist ungeprüft; besser das Leuchten als Shader oder vorgerenderte Textur umsetzen.
4. **22-dp-Streifen nur im Modell geprüft.** Grundlage ist eine Hand-Kartenbreite von 88 dp. Bei größeren Karten (Größe L) wird der sichtbare Streifen in Karteneinheiten schmaler; dann den Fächer weiter aufziehen.
5. **Restliche Karten.** Der volle Satz von 112 Karten fehlt noch, ebenso Zahl 0 falls gewünscht. Der Generator kann sie erzeugen.
6. **Katze verfeinern.** Die Vektorkatze ist bewusst einfach. Für Store-Grafik oder Titelbild kann eine Illustration nach `bild_prompt.md` folgen. Animationen (Pfote heben, Maul öffnen) sind mit den getrennten Formen in `generator/katze.pl` vorbereitet, aber nicht als eigene Ebenen-IDs ausgewiesen.
7. **Titelband übersetzen.** Das Farbwort im Titelband ist deutsch und müsste bei einer Übersetzung mitwandern oder abschaltbar sein.
