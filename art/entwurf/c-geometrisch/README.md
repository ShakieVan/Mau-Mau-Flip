# Mau-Mau Flip – Entwurf C „Geometrisch & kräftig“

Gestaltungsrichtung im Stil von Bauhaus und Swiss Modern: Kreis, Halbkreis, Dreieck und Balken, große ruhige Flächen, hoher Kontrast, große Ziffern. Ziel ist der Eindruck eines modernen Brettspielverlags, verspielt, aber erwachsen.

Alles ist selbst als Vektor gezeichnet und wird von `werkzeug/build.pl` (Perl, ohne Zusatzmodule) erzeugt. Fremde Bilder sind nicht eingebettet.

## Dateien

| Datei | Inhalt |
|---|---|
| `cards/*.svg` | 24 Karten, 560 × 870 (56:87). Die 16 geforderten plus 8 Zusatzkarten für die Handansicht |
| `logo.svg`, `logo.png` | Logo quer, 1600 × 900 |
| `icon.svg`, `icon.png` | App-Symbol, 512 × 512 |
| `preview.html`, `preview.png` | Gesamtübersicht: Logo, App-Symbol in 512/96/48 px, alle Kartenpaare, Handansicht, Streifentest, Palette, Farbprüfung, Begründung |
| `hand.html`, `hand.png` | Spielansicht im Querformat, 1600 × 720 |
| `logo.html`, `icon.html` | Einzelseiten zum Rendern |
| `bild_prompt.md` | Prompt für einen KI-Bildgenerator (englisch) mit Erläuterung |
| `werkzeug/build.pl` | Generator. Aufruf: `perl werkzeug/build.pl` |
| `werkzeug/render.sh` | PNG-Export mit Chrome headless: `./werkzeug/render.sh preview.html preview.png 1600 5632` (Höhe = Seitenhöhe) |

## Gestaltungsidee

**Tag und Nacht.** Die helle Seite ist ein bedrucktes Papier: Cremeweißer Rand, volle Farbfläche, massive Ziffer. Die dunkle Seite ist eine Nacht: Fast schwarzer Grund, die Farbe leuchtet als Kontur und als Mondsichel, die Ziffer ist eine Leuchtröhre. Beide Seiten sind auch ohne Farbsehen sofort zu unterscheiden (siehe Graustufenreihe in der Vorschau).

**Mitte.** Hell: aufrechte Sonnenscheibe, die untere Hälfte dunkler mit drei Horizontstreifen. Dunkel: Mondsichel aus zwei Kreisen, die Ziffer steht im Hohlraum, dazu Sterne. Beides ist rund und aufrecht.

**Aktionen** als eigene Piktogramme:

| Karte | Mitte | Eckindex |
|---|---|---|
| Zieh 1 / Zieh 5 / Wünscher +2 | kompaktes „+“ und große Ziffer | „+1“, „+5“, „+2“ mit kleinem Plus |
| Aussetzen | schlafender Katzenkopf mit „Zz“ | „Zz“ |
| Alle aussetzen | Ring aus sechs schlafenden Katzenköpfen um „Zz“ | „Zz“ im Punktring |
| Richtungswechsel | zwei Kreispfeile, die Enden rund wie eine Schwanzspitze | Kreispfeile |
| Flip | Scheibe halb Tag (Papier, Sonne), halb Nacht (Mond), umkreist von zwei Pfeilen | halb gefüllter Kreis |
| Wünscher | Pfote, die vier Zehenballen in den vier Farben der Seite | Pfote + 2×2-Farbraster |
| Farbjagd | Kartenstapel mit „?“ | „?“ + 2×2-Farbraster |

Die Joker der hellen Seite haben eine Fläche aus vier Farbquadranten mit einer Papierscheibe. Die dunklen Joker haben eine in vier Farbbänder geteilte Mondsichel und einen Leuchtrahmen im Farbverlauf.

**Mau-Katze.** Eine Smoking-Katze (schwarz mit cremeweißer Brust und Pfoten) aus Kreisen, Dreiecken und Bögen. Sie sitzt, schaut nach oben, hält eine Pfote ans offene Maul und sagt „Mau!“. Die Augen sind mandelförmig, auf der Stirn trägt sie ein „M“ wie eine getigerte Katze. Dadurch wirkt sie erwachsen und trotzdem süß. Ein cremefarbener Freistellrand trennt sie von beiden Karten.

**Schriftzug.** „Mau-Mau“ über einem großen „Flip“. Der i-Punkt ist eine kleine Tag-Nacht-Scheibe. Darunter die Zeile „KARTENSPIEL MIT ZWEI SEITEN“ und ein Band aus den acht Spielfarben.

## Für den Fächer im Querformat

- Karte in der Hand 76 × 118 dp, sichtbarer Streifen 22 dp = 162 von 560 Einheiten.
- Eckindex oben links: Wert 180 Einheiten Schriftgröße (Ziffernhöhe ≈ 126 E ≈ 17 dp), darunter das Farbsymbol (84 E ≈ 11 dp). Alles liegt innerhalb x ≤ 165, also im Streifen. Der Streifentest in `preview.html` zeigt alle 16 Karten genau so.
- Bei „+5“ und „+2“ ist das Plus kleiner gezeichnet, damit der Index nicht breiter wird.
- Das Farbsymbol wiederholt sich oben rechts Ton in Ton (hell) bzw. halbtransparent (dunkel). So ist auch der obere Rand der vordersten Karte eindeutig.
- 6 und 9 sind im Index und in der Mitte unterstrichen.
- Index unten rechts ist um 180° gedreht.

## Ebenen in den SVGs

Jede Karte hat dieselben benannten Gruppen, damit Godot sie getrennt animieren kann (Strahlen aus der Kontur, Flip-Übergang):

`grund` (Fläche bzw. Nachtgrund) · `motiv` (Sonne bzw. Mond und Sterne) · `symbol` (Farbsymbol oben rechts/unten links) · `wert` (Mitte) · `index` (beide Ecken) · `rahmen` (Papierrand bzw. Leuchtkontur)

## Palette und Formsymbole

| Seite | Farbe | Wert | Symbol |
|---|---|---|---|
| hell | Rot | `#B3202A` | Flamme |
| hell | Gelb | `#FFDD33` | Sonne |
| hell | Grün | `#43B05C` | Kleeblatt |
| hell | Blau | `#2A5BD7` | Kristall |
| dunkel | Pink | `#FF99CC` | Herz |
| dunkel | Türkis | `#00838F` | Welle |
| dunkel | Orange | `#FF6F00` | Laterne |
| dunkel | Lila | `#4527A0` | Stern |

Die Startpaletten sind unverändert übernommen. Zusätzlich gibt es nur Hilfstöne: Auf der hellen Seite eine dunklere Stufe für die Sonnenscheibe, auf der dunklen Seite einen hellen Leuchtton je Farbe für Konturen und Index (zum Beispiel Lila `#A891FF`). Die Erkennungsfarbe bleibt die Grundfarbe.

Nachrechnung im Generator (OKLab, Machado 2009, Schweregrad 1), kleinster Abstand je Seite:

| Seite | normal | Rotschwäche | Grünschwäche | Blau-Gelb-Schwäche |
|---|---|---|---|---|
| hell | 0,268 | 0,190 | 0,164 | 0,152 (Grün–Blau) |
| dunkel | 0,193 | 0,160 | 0,184 | 0,149 (Pink–Orange) |

Mit diesen Werten stimmen die Startwerte aus der Recherche überein (≈ 0,15). Die Formsymbole decken die knappen Paare zusätzlich ab.

## Schrift

| Schrift | Herkunft | Lizenz | Verwendung |
|---|---|---|---|
| **Jost** | Owen Earl (indestructible type*), Google Fonts | SIL Open Font License 1.1 | Ziffern, Index, Schriftzug, Bedienelemente |

Die HTML-Seiten laden Jost per `<link>` von fonts.googleapis.com. Die SVGs setzen `font-family="Jost, Futura, …"` und enthalten zusätzlich ein `@import`, damit sie auch einzeln im Browser richtig aussehen. Für die App sollte die Schriftdatei (OFL erlaubt Einbetten und Weitergabe mit Lizenztext) ins Projekt gelegt werden.

## Abstand zum Vorbild

- Kein Oval, weder gerade noch schräg. Die Mitte ist eine aufrechte Kreisscheibe (Sonne) bzw. eine Mondsichel.
- Keine Zahl mit Schlagschatten. Hell: flache, massive Ziffer. Dunkel: Ziffer als Leuchtkontur.
- Keine schwarze Joker-Karte und keine Rückseite mit rotem Oval. Die Joker der hellen Seite sind bunt geviertelt mit Pfote, die „Rückseite“ ist die eigene Nachtseite.
- Eigene Aktionssymbole (Katzenkopf, Kreispfeile mit Schwanzspitze, Tag-Nacht-Scheibe, Pfote, Kartenstapel mit „?“) statt der bekannten Piktogramme.
- Eigene Schrift (geometrische Grotesk), eigene Ränder (Papierrand bzw. Leuchtrahmen), eigenes Maskottchen.
- Der Name des Vorbilds kommt in keiner Datei vor.

## Hinweise für die Umsetzung in Godot

- Godot rastert SVGs mit ThorVG. Text in SVGs und Unschärfefilter (`feGaussianBlur`) werden dort nicht zuverlässig dargestellt. Empfehlung: Wert und Index in Godot als Label mit Jost (MSDF) zeichnen und das Leuchten als Shader; die SVG-Ebenen `grund`, `motiv`, `symbol`, `rahmen` als Texturen exportieren. Alternativ in Inkscape „Objekt in Pfad umwandeln“ und das Leuchten als eigene PNG-Ebene backen.
- Für ein adaptives Android-Symbol muss der Vordergrund auf die sichere Zone (66 dp von 108 dp) verkleinert werden; `icon.svg` ist die volle Fläche mit abgerundeten Ecken für Vorschau und GitHub.
- Die Handansicht nimmt Dichte 2,0 an (1600 × 720 px = 800 × 360 dp).

## Offene Punkte

- **Katze:** Der angewinkelte Arm liegt jetzt mit sichtbarem Ellbogen vor der weißen Brust. Die Schulter bildet links noch eine kleine Wölbung, und der Kopf ist nur leicht nach hinten geneigt. Für ein deutlicheres „schaut nach oben“ könnte der Kopf stärker kippen.
- **App-Symbol bei 48 px:** Das Gesicht wird klein. Für kleine Größen kann eine Kopf-Variante ohne Arm und Schwanz besser sein.
- **Lila auf Nacht** ist dunkel (#4527A0). Die Sichel lebt von der hellen Kante. Auf dem Gerät prüfen, ob die Fläche heller werden darf, ohne den Abstand zu Türkis zu verlieren.
- **Farbjagd:** Das Piktogramm (Stapel mit „?“) ist weniger sprechend als die übrigen.
- **„Alle aussetzen“ im Index:** Der Punktring ist bei 10 dp fein. Gegebenenfalls nur „Zz“ mit dickerem Ring.
- Die Werte der Farbprüfung stammen aus diesem Generator und sollten mit dem Werkzeug aus Draw2Race gegengeprüft werden.
- Rückseiten-Großansicht (Antippen fremder Karten, Durchblättern) und das kurze Umdrehen der eigenen Hand sind in der Handansicht nur als Bedienelement angedeutet.
