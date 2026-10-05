# Mau-Mau Flip: der Spieltisch. Ideenkatalog mit Recherche und Umsetzung in Godot 4.6

Stand 04.10.2026. Ich habe nur gelesen und keine Dateien angelegt oder verändert. Als Referenz dienten Draw2Race (`AGENTS.md`, `docs/RICHTLINIEN.md`, `game/scripts/pass_party.gd`, `game/scripts/player_colors.gd`), Webquellen und eigene Rechnungen. Rechnungen und Annahmen sind im Text als solche gekennzeichnet. Der Projektordner `E:\Documents\Programmierung\Mau-Mau Flip` enthält bisher nur `.git`.

**Legende**
- **Priorität:** Muss, Soll, Kann.
- **Aufwand:** S = höchstens ½ Tag, M = 1–2 Tage, L = 3–5 Tage, XL = mehr als 1 Woche. Gemeint sind Entwicklungstage einschließlich Feinschliff auf dem Gerät, ohne Grafikproduktion.

---

## 0. Kurzfassung: die 12 wichtigsten Empfehlungen

1. **Die Hand passt sich der Kartenzahl an.**
   - Bis 7 Karten: großer Fächer.
   - 8–15 Karten: dichter Fächer. Der Finger gleitet darüber, die Karte darunter hebt sich (Lupe).
   - Ab 16 Karten: **Bogen-Karussell** mit Fischauge, Schwung und Einrasten.
   - Für 25 und mehr Karten gibt es zusätzlich ein Übersichtsblatt. „Zwei Reihen“ ist eine Option.
2. **Ausspielen** geht per Wischen nach oben oder per Doppeltipp: Der erste Tipp hebt die Karte an, der zweite spielt sie. Ein-Tipp-Ausspielen gibt es nur als Option.
3. **Joker** werden mit einer einzigen Geste gespielt: Beim Ziehen fächern vier Farbfelder um die Ablage auf.
4. **Gegnerhände** zeigt jedes Gerät nach der für den Betrachter sichtbaren Seite sortiert, nicht in der Reihenfolge des Besitzers. So verrät die eigene Sortierung nichts.
5. Der **Nachziehstapel zeigt die Gegenseite seiner obersten Karte**, wie im echten Spiel. Dort liegt der Stapel mit der dunklen Seite nach oben.
6. **Sitzordnung:** Der Host zieht die Avatare an einen Tisch in Draufsicht. Jedes Gerät dreht die Ansicht nur und spiegelt sie nie. Die Winkel werden oberhalb der eigenen Hand gestaucht.
7. **Die Darstellung reagiert nur auf Ereignisse.** Eine „Tischregie“ spielt die Ereignisse des Hosts der Reihe nach ab und holt Rückstand schneller auf. Dieselben Ereignisse treiben App und Browser. Das entspricht der Draw2Race-Leitplanke „Darstellung verändert nie das Ergebnis“.
8. **Renderer:** Anders als Draw2Race (Mobile) sollte das Projekt den **Compatibility-Renderer** nutzen. Dann sehen App und Web gleich aus. Glühen entsteht über additive Texturen statt 2D-HDR, Spuren über Line2D.
9. **Joker-Strahlen:** Man tastet die Kontur ab und prüft jeden Punkt mit `Geometry2D.is_point_in_polygon` gegen die darüberliegenden Karten. Die sichtbaren Punkte speisen `CPUParticles2D` mit `EMISSION_SHAPE_DIRECTED_POINTS`. Die Kosten sind vernachlässigbar.
10. **Farbsehschwäche:** Meine Rechnung zeigt andere kritische Paare als erwartet: **Pink–Türkis (Grünschwäche, Abstand 0,05)** und **Rot–Grün (0,03)**, nicht in erster Linie Pink–Lila. Abhilfe bringen abgestimmte Paletten (Mindestabstand ≈ 0,15) und eigene Formsymbole. ColorADD ist lizenzpflichtig.
11. **Leitmotiv „Tag und Nacht der Mau-Katze“:**
    - Helle Seite: Papier, gefüllte Farbe, Sonne.
    - Dunkle Seite: Nacht, Neonkontur, Mond.
    - Kein Oval.
12. **Drei Effektstufen** (Voll, Reduziert, Minimal). Höchstens 3 Hell-Dunkel-Wechsel pro Sekunde. Bei Ruckeln stuft das Spiel automatisch herunter.

---

## 1. Handkarten

### 1.1 Platzrechnung (eigene Rechnung)

Annahmen:
- Referenzhandy 1080×2400 px bei ~420 dpi, also **411×914 dp**.
- Die Handzone ist das untere Drittel, ≈ 275 dp hoch.
- Eine Handkarte misst **76×118 dp** (Seitenverhältnis 56:87 wie echte Karten).
- Ein sichtbarer Streifen braucht ≥ 22 dp, damit der Eckindex lesbar ist.
- Bequem antippbar sind erst ≥ 48 dp, die Material-Mindestgröße für Touchziele.

Ein einreihiger Fächer auf 395 dp nutzbarer Breite fasst n = 1 + (395 − 76) / Streifenbreite Karten:

| Streifen | Karten | Folge |
|---|---|---|
| 48 dp | 7 | jede Karte direkt antippbar |
| 30 dp | 11 | gut lesbar, Tippen wird unsicher |
| 22 dp | 15 | Index gerade noch lesbar, „Gleiten und Anheben“ nötig |
| 16 dp | 20 | nur mit Fischauge oder Lupe lesbar |

Zwei Reihen mit 22-dp-Streifen fassen 30 Karten ohne Scrollen. Sie brauchen ≈ 118 + 59 = 177 dp Höhe, das passt. Zieh 5 und „Zieh bis Farbe“ überschreiten regelmäßig 15 Karten. Ab etwa 16 Karten muss die Hand deshalb ihre Darstellung wechseln.

### 1.2 Darstellungsmuster im Vergleich

| Muster | 1–7 | 8–15 | 16–30+ | Urteil |
|---|---|---|---|---|
| Fächer/Bogen (Stil Slay the Spire/Hearthstone) | sehr gut | gut mit Anheben | unlesbar | Basis |
| Flache überlappende Reihe | gut | ok | nur mit Scroll | wirkt weniger edel als der Bogen |
| Lupe/Dock-Effekt | unnötig | sehr gut | gut bis ~20 | Pflicht ab 8 Karten |
| 3D-Zylinder-Karussell | Spielerei | ok | Ränder verzerrt und schwer lesbar | Kann |
| Rad/Drehscheibe (Bogen-Karussell) | ok | gut | sehr gut, scrollbar | **Empfehlung ab 16** |
| Zweireihig | unnötig | ok | gut bis 30, Überblick ohne Scroll | Option |
| Stapel je Farbe mit Zähler | – | – | gut bei 30+, aber ein Tipp mehr | Kann |
| Übersichtsblatt (Hand hochziehen, Raster nach Farben) | – | – | sehr gut bei 25+ | Soll |

### 1.3 Empfehlung: die anpassungsfähige Hand „Bogen“

| Baustein | Umsetzung | Prio | Aufwand |
|---|---|---|---|
| Stufe A (≤ 7 Karten) | Bogen mit Radius ≈ 2,5 × Bildschirmbreite, Drehung höchstens ±12°, Abstand ≥ 48 dp, direkt antippbar | Muss | M |
| Stufe B (8–15 Karten) | Finger aufsetzen und seitlich gleiten: Die Karte unter dem Finger hebt sich (+24 dp, ×1,15), die Nachbarn weichen aus | Muss | M |
| Stufe C (ab 16 Karten oder per Einstellung) | Bogen-Karussell: Wischen dreht das Rad. In der Mitte groß, zum Rand gestaucht, abgesenkt, auf 75 % abgedunkelt. Alle Karten bleiben als Streifen sichtbar, damit man die Menge spürt. | Muss | L |
| Fischauge | Kartenabstand s(d) = s_min + (s_max − s_min)·exp(−(d/σ)²). Dabei ist d der Abstand zur Mitte in Karten, s_max ≈ 52 dp, s_min ≈ 10 dp, σ ≈ 2,5. Wirkt wie das Mac-Dock. | Muss | S |
| Hysterese | Wechsel zu C ab 16 Karten, zurück zu B erst bei ≤ 13. Der Moduswechsel wird animiert und flackert nicht. | Muss | S |
| Übersichtsblatt | Griff über der Hand nach oben ziehen: halbe Bildschirmhöhe, Raster nach Farben gruppiert, Ausspielen wie gewohnt | Soll | M |
| Randmarken | Punkte in Kartenfarbe am Rand zeigen spielbare Karten außerhalb des Blicks. Tippen scrollt dorthin. | Soll | S |
| Zwei Reihen | Option „ab 15 Karten zwei Reihen“ für alle, die Überblick ohne Scrollen wollen | Kann | M |

### 1.4 „Fancy“ Scrollen

| Baustein | Umsetzung | Prio | Aufwand |
|---|---|---|---|
| Schwung | Die Geschwindigkeit ergibt sich aus den Touchproben der letzten ~100 ms (gewichtetes Mittel). Abklingen mit v·e^(−t/τ), τ ≈ 0,35–0,5 s. Apples Abklingrate 0,998 pro ms entspricht τ ≈ 0,5 s. Projektion nach WWDC18: Ziel = Position + v·d/(1−d)/1000. | Muss | M |
| Einrasten | Ziel ist die Kartenmitte, die der *projizierten* Endposition am nächsten liegt. Eine kritisch gedämpfte Feder fährt dorthin, so landet jeder Wisch sauber auf einer Karte. | Muss | S |
| Gummiband | Überscroll x wird als (1 − 1/(x·c/d + 1))·d gezeigt, mit c = 0,55 (UIScrollView) und d = Handbreite. Beim Loslassen federt die Hand zurück. | Soll | S |
| Wölbung | Karten liegen auf dem Bogen. Der Scrollversatz ist ein Winkel, die Kartendrehung folgt dem Bogenwinkel, Skalierung 1,0 in der Mitte bis 0,85 am Rand. | Muss (Stufe C) | M |
| Schwung-Neigung | Faux-3D-Neigung (`rotation_y`) proportional zur Geschwindigkeit, begrenzt auf ±12°, federt zurück. Shader „Faux 3D Perspective“ (MIT, Godot 4.4+). | Soll | S |
| Parallaxe | Die Motivebene (Sonne/Mond) verschiebt sich gegen den Rahmen, je nach Position auf dem Bogen. Ein Glanzstreifen wandert beim Scrollen über die Karten. | Kann | M |
| Haptik-Raster | Kurzer Puls, wenn eine Karte die Mitte kreuzt: 10 ms, Stärke 0,2, höchstens alle 35 ms | Soll | S |
| Ton | Leises Kartenschnarren, Tonhöhe folgt dem Tempo | Kann | S |
| **Federn statt Tweens für die Hand** | Jede Karte folgt ihrem Layoutziel mit einer Feder: `vel += (k*(ziel-pos) - c*vel)*dt; pos += vel*dt`. Unterbrechungen wie eine neue Karte oder Umsortieren mitten im Scrollen ruckeln dann nie. Tweens nur für einmalige Flüge. | Muss | M |

### 1.5 Ausspielen und Fehlbedienung vermeiden

**Gestenerkennung:**
- Nach 8 dp Bewegungstoleranz entscheidet der Winkel. Ist |dy| > 1,2·|dx| und die Bewegung geht nach oben, wird ausgespielt. Sonst wird gescrollt bzw. geglitten.
- 350 ms Drücken ohne Bewegung öffnet die Großansicht. Zieht man danach seitlich, sortiert man von Hand um.

| Baustein | Umsetzung | Prio | Aufwand |
|---|---|---|---|
| Doppeltipp | Der erste Tipp hebt die Karte an, sie glüht, über der Ablage erscheint „Spielen“. Der zweite Tipp auf die Karte oder die Ablage spielt sie. Tipp ins Leere hebt die Auswahl auf. | Muss | S |
| Wischen/Ziehen nach oben | Über eine Schwelle (≈ 25 % Bildschirmhöhe über der Hand) oder per Schnippen (> 1200 dp/s, ±35°). Ein Geisterbild auf der Ablage zeigt die Vorschau. Zurückziehen bricht ab. | Muss | M |
| Joker in einer Geste | Beim Ziehen eines Jokers fächern vier Farbfelder um die Ablage auf, jeweils mit Symbol und Anzahl der eigenen Karten dieser Farbe. Loslassen auf einem Feld spielt die Karte und wählt die Farbe. Als Rückfall gibt es ein Farbrad nach dem Tippen. | Muss (Farbrad) / Soll (eine Geste) | M |
| Nicht spielbar | Die Karte schüttelt „nein“ (3 Schwingungen, 250 ms), dazu ein Doppelbrummen und der Hinweis „Passt nicht – Blau oder 7“ | Muss | S |
| Nicht am Zug | Scrollen und Sortieren sind erlaubt, Ausspielen nicht: Die Karte federt zurück. Bei der Hausregel „Reinwerfen“ gilt eine höhere Schwelle. | Muss / Kann (Hausregel) | S |
| Optimistische Animation | Die Karte fliegt sofort los. Lehnt der Host ab, federt sie zurück. Wichtig für Browser und WLAN mit Verzögerung. | Muss | S |
| Gezogene Karte ist spielbar | „Ausspielen/Behalten“ erscheint direkt an der Karte | Muss | S |
| Schnell-Ausspielen | Ein Tipp spielt sofort, als Option für Geübte | Kann | S |

### 1.6 Spielbare Karten hervorheben

- **Spielbar:** 8 dp angehoben, volle Helligkeit, feiner Rand in der aktuellen Farbe. Das Anheben ist ein Signal unabhängig von Farbe.
- **Nicht spielbar:** 70 % Helligkeit, leicht entsättigt.
- Alle Karten teilen einen Shader. Werte je Karte laufen über `modulate`/`self_modulate`, damit ein einziges Material genügt.
- **Joker +2 und Joker „Zieh bis Farbe“:** Laut Regel nur erlaubt, wenn man keine Karte der aktuellen Farbe hat. Gegner dürfen das anzweifeln.
  - Wird das Anzweifeln umgesetzt, ist so ein Zug ein Bluff und kein Verbot. Die Karte wird dann nicht gesperrt, sondern mit „anzweifelbar“ gekennzeichnet.
  - Ohne Anzweifeln gilt sie als nicht spielbar. **Das ist eine Regelentscheidung.**
- Option „Hervorheben aus“: Kann, S.

### 1.7 Godot-Technik für die Hand

- Tisch und Hand als `Node2D` aufbauen, nicht als Container.
- Treffertest selbst schreiben: die Kartenpolygone von oben nach unten mit `Geometry2D.is_point_in_polygon` prüfen. Das ist bei gedrehten, überlappenden Karten zuverlässiger als `mouse_filter` von Controls.
- Das Layout ist eine reine Funktion `layout(n, scroll, fokus) -> Array[Transform2D]`. So lässt sie sich wie in Draw2Race headless testen (`tools/build.ps1 -Target Test`).
- Als Ideenquelle eignet sich `stormtoy/card_fan_demo` (MIT): parabelförmiger Bogen, Anheben, ausweichende Nachbarn.

---

## 2. Sortieren

### 2.1 Varianten

| Modus | Beschreibung | Prio | Aufwand |
|---|---|---|---|
| Farbe → Wert (Standard) | Feste Farbfolge je Seite: hell Rot, Gelb, Grün, Blau; dunkel Pink, Türkis, Orange, Lila. Innerhalb einer Farbe Zahlen aufsteigend, dann Aktionen, Joker ganz rechts. 6 dp Lücke zwischen den Farbgruppen. | Muss | S |
| Wert → Farbe | Gleiche Zahlen nebeneinander, hilfreich für Zahl auf Zahl | Muss | S |
| Punkte zuerst | Teure Karten nach vorn: Joker 40–60 Punkte, Aktionen 20–30. Hilft, wenn jemand kurz vor dem Ende ist. | Soll | S |
| Farbe nach Menge | Die häufigste Farbe zuerst, hilfreich bei der Joker-Farbwahl | Kann | S |
| Manuell | Langes Drücken und seitlich ziehen. Schaltet die Automatik ab, mit dem Hinweis „Automatisch sortieren: aus“. | Soll | M |
| Automatik an/aus | Neue Karten werden einsortiert und schimmern 3 s als „neu“. Ist die Automatik aus, kommen sie rechts dazu. | Muss | S |
| Bedienung | Sortierknopf neben der Hand: Tippen wechselt den Modus (Symbol zeigt ihn), langes Drücken öffnet die Auswahl | Muss | S |
| Umsortier-Animation | FLIP-Prinzip (First-Last-Invert-Play): Ziele berechnen, dann federn die Karten hin. Weite Wege laufen über einen Bogen von +20 dp, damit Karten nicht durcheinander hindurchfahren. 15 ms Versatz je Karte. | Muss | S |

### 2.2 Besonderheiten durch Flip

- Sortiert wird immer nach der aktiven Seite.
- Ablauf nach einem Flip:
  1. Eine Welle dreht die Karten der Hand um.
  2. **100 ms Pause**, damit man die neue Seite erkennt.
  3. Die Karten federn in die neue Sortierung.

  Ohne die Pause wirkt es chaotisch.
- Manuelle Reihenfolge je Seite merken (Kann, S): Jede Karte trägt zwei Ränge, einen für hell und einen für dunkel. Nach dem Flip gilt wieder die gemerkte Ordnung der neuen Seite.
- **Eigene Rückseiten:** Man hält die aktive Seite zu sich und sieht nicht, was die anderen sehen. Die Regel sagt zum Nachsehen nichts. Vorschlag: standardmäßig nicht zeigen, als Hausregel „eigene Rückseiten zeigen“ (Kann).

### 2.3 Verrät die eigene Sortierung etwas über die Rückseiten?

**Ja.** Sortiert mein Gerät nach der hellen Seite, sehen die Gegner meine dunklen Rückseiten in Blöcken. Die Blockgrenzen verraten meine hellen Farben. Am echten Tisch passiert das nur, wenn ein Spieler selbst sortiert. Digital wäre es systematisch.

**Empfehlung (Muss, S):**
- Der Host schickt die Rückseiten einer Hand als **sortierte Menge**, nicht in Handreihenfolge.
- Jedes Gerät zeigt Gegnerhände nach der für den Betrachter sichtbaren Seite sortiert.
- Das schließt das Informationsleck auch gegenüber einem manipulierten Browser-Client. Nebenbei sind gruppierte Rückseiten besser lesbar.
- Eine Hausregel „echte Reihenfolge“ gibt es nur als Kann.

**Weitere Regeln dazu:**
- Wer zieht, dessen gezogene Karte sehen alle als Rückseite, wie am echten Tisch. Sie wird im Fächer des Gegners kurz hervorgehoben.
- Nach jedem Flip schickt der Host neue Rückseitenmengen.

---

## 3. Sitzordnung und Tischlayout

### 3.1 Plätze festlegen

| Baustein | Umsetzung | Prio | Aufwand |
|---|---|---|---|
| Tisch-Editor des Hosts | Runder Tisch in Draufsicht mit n Plätzen. Verbundene Spieler (App und Browser) warten als Avatare auf einer Bank und werden auf Plätze gezogen. Dazu „Zufällig“ und „Startspieler“. Der Host sitzt unten. | Muss | M |
| Prüfhilfe | Jedes Gerät zeigt kurz „Links von dir: Lena, rechts: Tom – stimmt das?“. Falsche Plätze fallen sofort auf. | Soll | S |
| Selbstanordnung | Jeder tippt an, wer links von ihm sitzt. Die Kette ergibt die Reihenfolge. | Kann | M |
| Weitergeben-Modus | Namen reihum eingeben, mit dem Hinweis „so wie ihr sitzt, links herum“ | Muss | S |

### 3.2 Ansicht drehen (eigene Rechnung)

Die Standard-Spielrichtung ist im Uhrzeigersinn von oben gesehen, also zum linken Nachbarn.

So wird jeder Gegner auf dem Bildschirm platziert:
1. **Relativer Platz:** r = (Platz − meinPlatz + n) mod n.
2. **Wahrer Winkel:** θ = 360°·r/n, im Uhrzeigersinn ab „unten“ gemessen.
3. **Stauchen:** Unten liegt die eigene Hand, deshalb wird der Winkel gestaucht. Mit φ0 ≈ 55° gilt φ = φ0 + θ·(360° − 2φ0)/360°.
4. **Ergebnis:** Der nächste Spieler erscheint links unten, die Reihenfolge bleibt erhalten.

**Nur drehen, nie spiegeln.** Sonst stimmen links und rechts nicht mehr.

```gdscript
func seat_pos(r: int, n: int, center: Vector2, radii: Vector2, phi0 := deg_to_rad(55.0)) -> Vector2:
	var theta := TAU * r / n                            # wahrer Winkel, im Uhrzeigersinn ab „unten“
	var phi := phi0 + theta * (TAU - 2.0 * phi0) / TAU  # gestaucht: unten bleibt frei für die Hand
	return center + Vector2(-sin(phi) * radii.x, cos(phi) * radii.y)  # y zeigt nach unten
```

### 3.3 Layout für 2–10 Spieler im Hochformat

| n | Gegnerpositionen | Darstellung der Gegnerhand |
|---|---|---|
| 2 | oben Mitte | großer Fächer der Rückseiten, Minikarten 32×50 dp mit lesbarem Wert und Symbol |
| 3 | oben links, oben rechts (θ = 120°/240°) | große Fächer |
| 4 | links, oben, rechts | Fächer mit Minikarten 26×40 dp |
| 5–6 | U-Bogen | kompakte Fächer, ab 8 Karten mit „+n“ |
| 7–10 | U-Bogen, zwei Ebenen versetzt | **Abzeichen** mit Avatar, gekürztem Namen und Kartenzahl. Ein **Farbbalken** zeigt die Rückseiten als Segmente je Farbe mit Symbol und Anzahl. Auffällige Rückseiten (Joker, Zieh 5, Flip) haben eigene Symbole. Tippen öffnet ein Detailblatt. |

- **Hat ein Gegner nur noch eine Karte, wird deren Rückseite groß angezeigt** (Muss, S). Am echten Tisch sieht sie jeder, und sie ist taktisch wichtig.
- Minikarten sind eine eigene Detailstufe: Farbe, großes Symbol, Wert. Eine bloß verkleinerte Vollkarte wäre unlesbar.

### 3.4 Tischmitte und Spielrichtung

| Baustein | Umsetzung | Prio | Aufwand |
|---|---|---|---|
| Nachziehstapel | Die Gegenseite der obersten Karte wird als echte Kartenfläche gezeigt, nicht als neutraler Rücken | Muss | S |
| Aktuelle Farbe | Ring um die Ablage in der Farbe, dazu Symbol und Farbname. Nach einem Joker unverzichtbar. | Muss | S |
| Richtungsring | Ring aus Chevrons um die Mitte, Fließrichtung per Shader (UV-Verschiebung). Dazu kleine Pfeile zwischen den Abzeichen entlang des U. | Muss | M |
| Am Zug | Das Abzeichen pulsiert, beim nächsten Spieler steht „Nächster“. Beim eigenen Zug hebt sich die Hand leicht, dazu Haptik und Ton. | Muss | S |
| Zugspur | Die zuletzt gespielte Karte trägt ein kleines Avatar-Abzeichen. Eine Leiste zeigt die letzten 5 Züge. | Soll | S |
| Gemeinsame Tischanzeige | Ein Browser auf Laptop oder Fernseher zeigt nur den öffentlichen Tisch | Kann | M |

### 3.5 Weitergeben-Modus: Tisch drehen?

**Empfehlung: ja** (Muss, M). Der aktuelle Spieler sitzt immer unten. Sonst kämen „Nächster“, Richtungspfeile und Gegner-Rückseiten aus der falschen Richtung.

Ablauf:
1. Zugende.
2. Sichtschutz „Gib das Handy nach links an Lena →“. Den Pfeil berechnet das Spiel aus der Sitzordnung.
3. Hinter dem Sichtschutz dreht sich der Tisch.
4. Lena hält 500 ms „Zum Aufdecken halten“.
5. Die Hand erscheint.

Der Sichtschutz zeigt nur Ablage, Stapel und Kartenzahlen, **keine Rückseitenfächer**. Sonst sähe Lena ihre eigenen Rückseiten. Eine Option „Tisch fest“ ist Kann.

---

## 4. Effekte

### 4.1 Grundsätze

| Grundsatz | Umsetzung | Prio | Aufwand |
|---|---|---|---|
| Tischregie | Der Host schickt nummerierte Ereignisse: gespielt, gezogen, Farbe, Flip, Mau, Strafe, Sieg. Die Clients spielen sie aus einer Warteschlange ab. Liegen mehr als 3 Ereignisse zurück, läuft alles doppelt so schnell. Bei mehr als 8 werden Effekte übersprungen und der Endzustand gesetzt. | Muss | M |
| Compatibility-Renderer | Laut Godot-Doku die einzige Wahl fürs Web. Glow geht, 2D-HDR, Partikelspuren und 2D-MSAA nicht. Glühen deshalb als vorgeblurrte Texturen mit `CanvasItemMaterial.BLEND_MODE_ADD`, Spuren als Line2D mit Punktpuffer. Billig und überall gleich. | Muss | – |
| Shader vorwärmen | Jeden Effekt beim Laden einmal unsichtbar abspielen. Der Shader Baker aus 4.5 ist laut Release-Notes für Metal, D3D12 u. a. gedacht; für Compatibility und Web ist er nicht belegt. | Soll | S |
| Ein Kartenshader | Wenden, Neigen, Abdunkeln und Glanz in einem Shader. Werte je Karte über `modulate`/Vertexfarbe. | Muss | M |
| Bildschirmwackeln | „Trauma“-Modell nach Eiserloh (GDC 2016): trauma ∈ [0,1], Wackeln ∝ trauma², Rauschen statt Zufall, in 2D Verschiebung plus leichte Drehung. Nur auf dem Gerät des Betroffenen. | Soll | S |
| Blitzschutz | Höchstens 3 Hell-Dunkel-Wechsel pro Sekunde, kein großflächiges gesättigtes Rot (WCAG 2.3.1) | Muss | – |
| Haptik | `Input.vibrate_handheld(duration_ms, amplitude)`. Android braucht die **VIBRATE-Berechtigung im Exportprofil**. Im Web ist die Stärke nicht einstellbar, Safari unterstützt es nicht. Muster per Timer-Folge. | Soll | S |
| Klänge | Selbst synthetisieren wie in Draw2Race (`tools/make_impact_sounds.py` als Vorbild): Papierwischen, Klatschen, Wumms, Fanfare | Soll | M |

### 4.2 Katalog je Karte und Ereignis

| Ereignis | Helle Seite (Tag) | Dunkle Seite (Nacht) | Godot-Technik | Haptik/Ton | Prio | Aufw. |
|---|---|---|---|---|---|---|
| Zahlenkarte ausspielen | Wurfbogen, Landung mit Stauchen (1,06 → 1,0), Papierstaub in Kartenfarbe | Ring aus Neonfunken | Tween auf Bezier, CPUParticles2D mit 12–20 Teilchen | 15 ms, „Klatsch“ | Muss | S |
| Karte ziehen | Karte gleitet vom Stapel und wendet sich für den Besitzer | wie hell, mit Neonkante | Faux-3D `rotation_y` | 8 ms, Wischen | Muss | S |
| Zieh 1 | Eine Karte springt zum Nächsten, über dem Avatar ploppt „+1“ | – | Label-Tween 0 → 1,2 → 1 (TRANS_BACK) | Opfer 20 ms | Muss | S |
| Zieh 5 | – | Schockwelle beim Aufprall. 5 Karten im 80-ms-Takt mit Neonspur, „+5“ als Stempel, Wackeln beim Opfer. | Ring-Shader auf Quad (additiv), Line2D-Spur, Trauma 0,5 | Opfer 5 Pulse 20 → 40 ms, Bass-Wumms | Muss (ohne Spur) / Soll | M |
| Aussetzen | Der Zugmarker hüpft im Bogen über den Übersprungenen. Dessen Avatar zeigt „Zzz“ und ist 1 s grau. | – | Tween auf quadratischer Bezier, Entsättigung im Shader | 2×10 ms, „Boing“ | Muss | S |
| Alle aussetzen | – | Der Zugmarker rast als Komet um den Tisch zurück. Die Avatare werden der Reihe nach grau, dann erscheint „Nochmal du!“. | Path2D/PathFollow2D, Line2D-Schweif | 30 ms, steigendes Sirren | Muss | M |
| Richtungswechsel | Auf der Karte dreht sich langsam eine Katzenschwanz-Pfeil-Ebene, solange sie oben liegt. Beim Ausspielen ein 360°-Wirbel. Der Tischring bremst, steht kurz und läuft mit Überschwinger rückwärts an. | gleiche Mechanik in Neon, der Ring wechselt die Farbe | Eigenes Sprite oder UV-Drehung im Shader. Der Uniform `speed` läuft per Tween durch 0 (TRANS_BACK). | 2×15 ms, „Wusch“ rückwärts | Muss | M |
| Flip | siehe 4.4 | | | | Muss (Grundform) / Soll (alles) | L |
| Joker in der Hand | Kurze Strahlen aus der sichtbaren Kontur in den 4 Tagfarben, Farbe je Quadrant, langsam rotierend | Nachtfarben, länger, flackernd mit höchstens 3 Hz | siehe 4.3 | – | Soll | M |
| Joker ausspielen | Die Pfoten-Quadranten drehen sich und verschmelzen zur gewählten Farbe. Eine Farbwelle läuft als Ring über den Tisch, der Farbring der Ablage färbt sich. | Neonwelle | Ring-Shader, Tween auf Shader-Uniform | 25 ms, Akkord je Farbe | Muss (einfach) | M |
| Joker +2 | Das Strahlenbündel richtet sich auf das Opfer, 2 Karten fliegen hinüber | – | Strahlrichtung = lerp(Normale, Richtung zum Opfer) | Opfer 2×25 ms | Soll | S |
| Joker „Zieh bis Farbe“ | – | **Spielautomat:** Karten fliegen in immer kürzeren Abständen (300 → 90 ms). Zuschauer sehen die helle Seite, das Opfer blitzt kurz die dunkle. Der Spannungston steigt mit jeder Karte. Treffer: Explosion in der Zielfarbe, „Treffer!“, Kamerastoß. | Tween-Kette, `AudioStreamPlayer.pitch_scale` +6 % je Karte, Burst | ein Puls je Karte, Treffer 60 ms | Soll | M |
| Letzte Karte „Mau!“ | Sprechblase mit Katzenohren ploppt auf, Abzeichen pulsiert warm, die letzte Rückseite wird groß gezeigt | Neonblase | Tween, NinePatchRect | 30 ms, Miau-Akzent | Muss | S |
| Mau vergessen | Bei den anderen erscheint für etwa 2 s ein „Erwischt!“-Knopf | | Timer | | Muss | S |
| Strafkarten | Ein einzelner roter Randpuls (kein Blinken), Karten mit Stempel „Strafe“ | | Vignette im Shader | 2×20 ms, Tröte | Muss | S |
| Anzweifeln (falls umgesetzt) | Eine Lupe wandert über die Hand. Nur der Herausforderer sieht die Karten. Dann „Bluff!“ oder „Sauber!“. | | Der Host schickt die Hand nur an den Berechtigten | | Soll | M |
| Sieg „Mau-Mau!“ | Konfetti in 4 Tagfarben, Sonnenstrahlen hinter dem Gewinner. Die Restkarten fliegen zum Gewinner, die Punkte zählen hoch. Wertung: Zahl = Augen, Zieh 1 = 10, Zieh 5/Richtungswechsel/Aussetzen/Flip = 20, Alle aussetzen = 30, Joker 40, Joker +2 50, Zieh bis Farbe 60. | Feuerwerk mit Raketen und Funkenregen, Sterne | CPUParticles2D mit 200–300 Teilchen, Zählwerk per Tween | 3 Pulse, Fanfare | Muss (einfach) / Soll | M |
| Nachmischen | Riffle-Animation | | Tween-Welle | Ticks | Soll | S |
| Leerlauf | Spielbare Karten „atmen“, alle 4 s ein Glanz | | Shader mit TIME | – | Kann | S |
| Holo-Joker | Regenbogenfolie, Neigung über den Lagesensor | | Holo-Shader von godotshaders, `Input.get_accelerometer()` (Sensor in den Projekteinstellungen aktivieren) | – | Kann | S |

### 4.3 Joker-Strahlen aus der sichtbaren Kontur

**Verfahren A: Kontur abtasten (empfohlen)**

1. **Einmal je Kartengröße:** Den Umriss als abgerundetes Rechteck alle ~6 dp abtasten, das sind ≈ 64 Proben. Je Probe die Normale analytisch speichern: an Kanten senkrecht, in Ecken radial vom Eckmittelpunkt. Numerisch berechnet zittern die Strahlen an den Ecken.
2. **Je Bild während Bewegung, sonst nur bei Layoutänderung:** Jede Probe in Tischkoordinaten umrechnen. Dann gegen alle höheren Karten prüfen, deren Rechteck überlappt. Verdeckte Proben fallen weg.
3. **Partikel speisen:** Die übrigen Proben gehen an `CPUParticles2D` mit `EMISSION_SHAPE_DIRECTED_POINTS`, `emission_points`, `emission_normals` und `emission_colors` (Farbe je Quadrant). `particle_flag_align_y` richtet eine längliche Strahltextur nach der Bewegung aus. Das Material ist additiv.
4. **„Auf den Spieler zu“:**
   - In der Hand mischt die Richtung die Normale mit der Radialen vom Kartenmittelpunkt. Die Strahlen werden beim Wachsen breiter und blasser und wirken wie Licht, das zum Betrachter strahlt.
   - Auf dem Tisch mischt sie die Normale mit der Richtung zum Zielspieler.
5. **Zeichenreihenfolge:** Den Partikelknoten als Kind der Jokerkarte mit `show_behind_parent = true` anlegen. Die Strahlen liegen dann über tieferen Karten, aber unter dem Joker und unter höheren Karten. Weil Schritt 2 verdeckte Proben entfernt, ragen keine Strahlen unter höheren Karten hervor.

```gdscript
# Sichtbare Konturproben in Kartenkoordinaten (outline_samples einmalig vorberechnet: [{pos, normal}])
func visible_samples(card, above: Array) -> Array:
	var xf: Transform2D = card.global_transform
	var hits := above.filter(func(c): return c.global_rect().intersects(card.global_rect()))
	var pts := PackedVector2Array()
	var nrm := PackedVector2Array()
	for s in card.outline_samples:
		var p: Vector2 = xf * s.pos
		var covered := false
		for c in hits:
			if Geometry2D.is_point_in_polygon(p, c.global_polygon()):
				covered = true
				break
		if not covered:
			pts.append(s.pos)     # lokal: der Partikelknoten ist Kind der Karte
			nrm.append(s.normal)
	return [pts, nrm]             # → rays.emission_points / rays.emission_normals
```

**Kosten (eigene Abschätzung):** 64 Proben × ~3 überlappende Karten ≈ 200 Aufrufe in C++ je Joker und Bild. Das ist vernachlässigbar. Dazu je Joker ~40 Teilchen.

**Alternativen:**
- **B, exakte Konturstücke:** `Geometry2D.clip_polyline_with_polygon(umriss, höhereKarte)` nacheinander für jede höhere Karte anwenden. Ergebnis sind lückenlose sichtbare Konturstücke, z. B. für eine durchgehende Leuchtlinie mit Line2D. `clip_polygons` (Fläche minus Fläche) braucht man nur, wenn ein Glühen die sichtbare *Fläche* füllen soll. Es liefert unter Umständen auch Löcher, erkennbar mit `is_polygon_clockwise` (Achtung: Ergebnis in Bildschirmkoordinaten umgekehrt).
- **C, Masken-Shader mit SubViewport:** Die höheren Karten als weiße Silhouetten in einen SubViewport mit ¼ Auflösung rendern. Der Strahlshader liest die Maske am Ursprung jedes Strahls und verwirft verdeckte Strahlen. Pixelgenau auch bei beliebigen Formen, kostet aber einen zusätzlichen Renderdurchgang je Bild und Viewport-Verwaltung, im Web teurer. Nur wenn A nicht reicht.
- **D, nur Zeichenreihenfolge:** Kein Aufwand, aber Strahlen verdeckter Kanten ragen hervor. Als Notlösung für die Stufe „Minimal“.

### 4.4 Drehbuch für den Flip (Voll ≈ 1,6 s, Reduziert 0,7 s, Minimal 0,3 s Überblendung)

| Zeit | Ereignis | Technik |
|---|---|---|
| 0,00 | Flip-Karte landet, das Bild zoomt 3 % hinein, „Einatmen“-Ton | Tween auf `Camera2D.zoom` |
| 0,15 | Die Ablage wendet sich in 300 ms | Faux-3D `rotation_y` 0 → 180°, Seitenwechsel bei 90°, Lichtstreifen auf der Kante |
| 0,30 | **Welle** vom Ablagestapel nach außen: Nachziehstapel, Gegnerhände nach Entfernung, zuletzt die eigene Hand von links nach rechts. Versatz 20 ms, je Karte 200 ms. | Verzögerung = Abstand / Wellengeschwindigkeit |
| 0,30–1,20 | **Stimmung:** Der Himmel geht von warm zu tiefblau, die Sonne sinkt hinter den Tischrand, der Mond steigt, Sterne erscheinen, der Filz wird dunkler, die Bedienelemente wechseln ins Nachtthema. Die Karten selbst werden *nicht* abgedunkelt, sonst wirkt das Neon matt. | Ein Vollbild-Shader mit dem Uniform `tageszeit`, kein globales CanvasModulate auf die Karten |
| 1,20 | Neon „zündet“: einmaliges Aufglimmen der Ränder, kein Flackern | additive Randtextur |
| 1,20 | Musik blendet auf die Nachtvariante über, alternativ ein Tiefpass-Sweep | `AudioEffectFilter` oder zwei Spuren |
| 1,30–1,60 | Die Hände sortieren sich neu | Federn |

- **Haptik:** 60 ms bei 0,3, kurze Pause, dann 120 ms bei 0,5.
- **Rückweg von dunkel nach hell:** Sonnenaufgang mit derselben Mechanik rückwärts.
- **Eingaben** sind während des Übergangs gesperrt. Ein „FlipRegie“-Knoten steuert alles mit `create_tween()`, `set_parallel()`, `tween_interval()` und `chain()`.

### 4.5 Leistungsbudget und „Effekte reduzieren“

Ziel auf einem Mittelklasse-Android (Annahme: Grafikchip etwa Mali-G57/G68 oder Adreno 6xx): 60 fps, GPU-Zeit ≤ 8 ms.

| Größe | Voll | Reduziert | Minimal |
|---|---|---|---|
| Gleichzeitige Teilchen (CPU) | ≤ 800 | ≤ 300 | 0 |
| Vollbild-Shaderdurchgänge | ≤ 2 | 1 | 1 (statisch) |
| Bildschirmwackeln | ja | nein | nein |
| Daueranimationen (Atmen, Holo, Ring) | ja | nur Ring | Ring statisch mit Pfeilen |
| Flip | 1,6 s | 0,7 s | 0,3 s Überblendung |
| Bildschirm auslesen (SCREEN_TEXTURE/BackBufferCopy) | nur während des Flips | nie | nie |

**Weitere Hinweise:**
- **Karten aus Bausteinen zusammensetzen:** Grund je Farbe, Muster, Symbol, Wert. 224 fertige Bilder bei 256×400 RGBA wären ≈ 92 MB unkomprimiert (eigene Rechnung).
- **Zahlen als MSDF-Schrift**, dann bleiben sie in jeder Größe scharf.
- **Ruhephasen:** Im Menü und ohne Animation die Bildrate senken (`Engine.max_fps` oder Low-Processor-Modus).
- **Automatische Rückstufung (Soll, S):** Liegt die Bildrate während Effekten 3 s unter 45 fps, geht es eine Stufe tiefer, mit Hinweis.
- **Web:** `prefers-reduced-motion` über JavaScriptBridge auslesen und als Startstufe nutzen (Kann, S).

### 4.6 Haptik-Plan

Gilt für Android. Im Android-Browser ohne Stärke, im iPhone-Browser gar nicht.

| Ereignis | Dauer / Stärke |
|---|---|
| Scroll-Raster | 10 ms / 0,2, höchstens alle 35 ms |
| Karte anheben | 8 ms / 0,3 |
| Ausspielen | 15 ms / 0,5 |
| Nicht spielbar | 2× 15 ms / 0,4 |
| Du bist dran | 25 ms / 0,4 |
| Zieh 1 oder Joker +2 (Opfer) | 1–2× 20 ms / 0,5 |
| Zieh 5 (Opfer) | 5 Pulse von 20 auf 40 ms steigend |
| Zieh bis Farbe | ein Puls je Karte, Treffer 60 ms / 0,8 |
| Flip | 60 ms / 0,3, Pause, 120 ms / 0,5 |
| Sieg | 3 Pulse |

Billige Vibrationsmotoren übertragen Pulse unter ~10 ms kaum. Die Werte auf dem Gerät abstimmen. Einstellung: aus, leicht, stark.

---

## 5. Barrierefreiheit

### 5.1 Farbprüfung (eigene Rechnung)

**Methode:**
- Dieselbe Rechnung wie `PlayerColors.distance()` in Draw2Race: OKLab-Abstand und Simulation nach Machado et al. 2009, Schweregrad 1.
- Zusätzlich habe ich Tritanopie (Blau-Gelb-Schwäche) geprüft.
- Draw2Race nennt ≈ 0,02 „eben unterscheidbar“ und verlangt für Spielerfarben ≥ 0,14.
- Die „typischen“ Töne habe ich geschätzt, sie sind nicht vom Original gemessen.

| Palette | Werte | Kritischstes Paar |
|---|---|---|
| hell, typisch | Rot E53935, Gelb F5C400, Grün 2E9E44, Blau 1E6FD9 | **Rot–Grün (Grünschwäche) 0,03**, Grün–Blau (Tritanopie) 0,07 |
| dunkel, typisch | Pink E5308C, Türkis 00A8A8, Orange F28C28, Lila 6A2C91 | **Pink–Türkis (Grünschwäche) 0,05**, Pink–Lila (Rotschwäche) 0,13, Pink–Orange (Tritanopie) 0,13 |
| **hell, abgestimmt** | Rot B3202A, Gelb FFDD33, Grün 43B05C, Blau 2A5BD7 | Mindestabstand 0,15 (Grün–Blau, Tritanopie) |
| **dunkel, abgestimmt** | Pink FF99CC, Türkis 00838F, Orange FF6F00, Lila 4527A0 | Mindestabstand 0,15 (Pink–Orange, Tritanopie) |

**Ergebnis:**
- Das Hauptproblem der dunklen Seite ist **Pink–Türkis bei Grünschwäche**, der häufigsten Form, nicht Pink–Lila.
- Abhilfe bringt eine klare Helligkeitsstaffel:
  - Hell: Gelb 0,90 > Grün 0,67 > Rot und Blau ≈ 0,5.
  - Dunkel: Pink 0,80 > Orange 0,71 > Türkis 0,56 > Lila 0,39.
- Die Werte sind Startwerte und müssen auf dem Gerät gegengeprüft werden.
- **Muss, S.** Das Werkzeug existiert in Draw2Race schon.

### 5.2 Formsymbole je Farbe

ColorADD ist außerhalb von Schulen lizenzpflichtig (der Hersteller des Originalspiels nutzt es für eine Sonderausgabe). Deshalb eigene Symbole: acht eindeutige Umrisse, auch bei 10 dp unterscheidbar.

| Seite | Farbe → Symbol |
|---|---|
| Hell | Rot ▲ Flamme, Gelb ● Sonne, Grün ♣ Kleeblatt, Blau ◆ Kristall |
| Dunkel | Pink ♥ Herz, Türkis ≋ Welle, Orange ⬢ Laterne, Lila ★ Stern |

- Kein „+“ als Symbol, das ist durch +1, +2 und +5 belegt.
- Die Symbole erscheinen im Eckindex, im Farbrad, im Farbring der Ablage und in den Farbbalken der Gegner.
- Option „Farbsymbole: immer / nur Eckindex / aus“, Standard „immer“.
- **Muss, S**, dazu kommt die Grafik.

### 5.3 Lesbarkeit und weitere Optionen

| Baustein | Prio | Aufwand |
|---|---|---|
| Runde, fette Schrift mit Kontur (OFL-lizenziert, z. B. Fredoka oder Nunito), 6 und 9 unterstrichen, Eckindex mindestens 18 dp hoch, MSDF-Darstellung | Muss | S |
| Farbe nie allein: aktuelle Farbe als Ring, Symbol und Wort („Türkis“), Ansagen als Text („Lena wählt Türkis“) | Muss | S |
| Blitzschutz nach WCAG 2.3.1 | Muss | – |
| Kartengröße S/M/L | Soll | S |
| Entwicklerwerkzeug: Vollbildshader „Farbsehschwäche-Vorschau“ (Protan, Deutan, Tritan); im Web zusätzlich Chrome DevTools „Sehschwächen emulieren“ | Soll | S |
| Linkshänder-Modus (Knöpfe gespiegelt) | Kann | S |
| Screenreader: Seit Godot 4.5 experimentell für Controls; für ein Echtzeit-Kartenspiel nachrangig | Kann | – |

---

## 6. Eigene Kartengestaltung

**Leitmotiv „Tag und Nacht der Mau-Katze“.** „Mau“ klingt nach „Miau“, das ergibt ein Maskottchen: tagsüber eine getigerte Katze in der Sonne, nachts eine schwarze Katze mit leuchtenden Augen.

| Element | Helle Seite „Tag/Papier“ | Dunkle Seite „Nacht/Neon“ |
|---|---|---|
| Kartenkörper | Cremefarbener Papierrand, die Fläche voll in der Kartenfarbe, feines Sonnenstrahlen-Muster mit ~8 % Kontrast | Fast schwarzes Nachtblau. Die Farbe erscheint als leuchtende Kontur und als große, farbig glühende Mondsichel hinter dem Wert, dazu Sternpunkte. |
| Mitte | Großer Wert, aufrecht in fetter runder Schrift mit dunkler Kontur. Optional ein aufrechtes Sonnen-Medaillon mit gezacktem Strahlenkranz. **Kein Oval, nichts schräg.** | Wert mit Neonglühen auf der Mondsichel |
| Ecken | Oben links und unten rechts (gedreht): Wert und Farbsymbol. Oben links bleibt im Fächer sichtbar. | gleich |
| Unterschied der Seiten | gefüllte Farbfläche | leuchtende Kontur auf Schwarz. So sind die Seiten auch ohne Farbsehen klar unterscheidbar. |

**Aktionssymbole (eigene Entwürfe):**
- **Zieh 1 / Zieh 5:** Kartenstapel-Piktogramm mit „+1“ bzw. „+5“.
- **Aussetzen:** schlafende Katze mit „Zzz“.
- **Alle aussetzen:** „Zzz“ in einem Kreis kleiner Katzenköpfe.
- **Richtungswechsel:** ein Katzenschwanz, der sich zum Kreis mit Pfeilspitze rollt. Lässt sich animieren.
- **Flip:** eine Scheibe, halb Sonne, halb Mond. Sie dreht sich beim Flip.
- **Joker:** vier Pfoten in den vier Farben der Seite (2×2) um einen Katzenkopf.
- **Joker +2:** Pfoten mit „+2“.
- **Joker „Zieh bis Farbe“:** Pfoten mit einem Kartenstapel und „?“.

**Vermeiden:**
- schräges weißes Oval
- Logo und Schriftzug des Originals
- schwarze Rückseite mit rotem Oval
- „Zahl im Oval mit Schlagschatten“
- den Namen des Originalspiels in sichtbaren Inhalten

**Herstellung:**
- Vektorbausteine (SVG/Inkscape). Godot setzt die Karte aus Ebenen zusammen, damit Ebenen wie der Schwanz oder die Flip-Scheibe animierbar sind.
- KI-Grafik ist erlaubt wie bei Draw2Race, die Herkunft wird dokumentiert.
- **Priorität:** Grunddesign Muss (M–L einschließlich Grafik), Maskottchen-Animationen Kann.

---

## 7. Was geht im Browser-Client?

### 7.1 Zwei Wege im Vergleich

| | Godot-Web-Export | Leichter HTML/JS-Client |
|---|---|---|
| Code | dieselbe Darstellungsschicht, nur das Netz ist anders | zweite Darstellung; die Spiellogik bleibt beim Host |
| Renderer | nur Compatibility mit WebGL 2. Deshalb sollte auch die App Compatibility nutzen. | DOM/CSS und Canvas |
| Größe | Standardvorlage ≈ 42 MB unkomprimiert, ≈ 9 MB gezippt. Eine schlanke eigene Vorlage (ohne 3D, mit wasm-opt und Brotli) kommt laut Erfahrungsberichten auf 3–6 MB. | ≈ 0,3–1 MB |
| Auslieferung | Über das lokale WLAN des Hosts sind auch 9 MB nur Sekunden. Der Host muss `.wasm` als `application/wasm` ausliefern und gzip-Dateien vorhalten. | einfach |
| iPhone | Seit 4.3 gibt es einen Single-Thread-Export ohne SharedArrayBuffer und ohne COOP/COEP-Header. Das hat iOS-Einfrierprobleme behoben. Offen bleiben Berichte über Safari-Neuladen wegen Speicher („significant memory“), und die Godot-Doku nennt WebGL-2-Probleme in Safari. | erprobte Standardtechnik |
| Netz | Browser können nur WebSocket und WebRTC, kein ENet. Der Host braucht einen WebSocket-Server. | gleich |
| Testen ohne iPhone | Playwright-WebKit unter Windows (nur näherungsweise), BrowserStack mit echten iPhones (Probezugang), Mitreisende | gleich |
| Aufwand | gering: Netzschicht und Startseite | groß: Hand, Tisch und Effekte doppelt, L–XL |

### 7.2 Machbarkeit je Baustein

| Baustein | Godot-Web | HTML-Client |
|---|---|---|
| Fächer, Lupe, Bogen-Karussell | identisch | CSS-Transforms und Pointer Events, M |
| Schwung, Gummiband, Einrasten | identisch | eigene Logik mit denselben Formeln |
| Sortieranimation | identisch | FLIP-Technik |
| Karten wenden | Faux-3D | CSS 3D mit `backface-visibility` |
| Partikel, Konfetti, Feuerwerk | CPUParticles2D | Canvas, weniger Teilchen |
| Joker-Strahlen | identisch | derselbe Abtast-Algorithmus in JS |
| Flip-Stimmung | Shader | reduziert: Verlaufsebenen und CSS-Übergang |
| Glühen | additive Texturen | vorgerenderte PNGs; animierte CSS-Filter sind auf Handys teuer |
| Bildschirmwackeln, Ton | ja, Ton erst nach dem ersten Tippen; der Knopf „Beitreten“ dient als Freischalter | ja, Web Audio ebenso |
| Haptik | Android-Chrome ja (ohne Stärke), iPhone nein | ebenso. Für das iPhone gibt es einen Trick ab iOS 18: unsichtbarer `<input type=checkbox switch>` (Kann). |
| Lage-Parallaxe (Holo-Joker) | **geht nicht über http:// im WLAN**: Die Lagesensoren gibt es nur im sicheren Kontext, iOS verlangt zusätzlich eine Erlaubnis per Tippen | ebenso |
| Bildschirm wach halten | Wake Lock nur im sicheren Kontext, im LAN also nein. Ersatz: stumm laufendes Mini-Video („NoSleep-Trick“), zu prüfen. | ebenso |
| Vollbild | Auf dem iPhone fehlt Element-Vollbild oder ist unzuverlässig. Ersatz „Zum Home-Bildschirm“, zu prüfen. | ebenso |

### 7.3 Empfehlung

- Jeder Effekt bekommt eine Web-Stufe (voll, reduziert oder aus). Derselbe Effektkatalog steuert App und Browser.
- **Früher Versuch (M):**
  - Eine minimale Tischszene als Godot-Web-Export, vom Android-Host im WLAN ausgeliefert.
  - Auf einem fremden iPhone oder per BrowserStack prüfen: Ladezeit, Speicher, Touch, Ton.
  - Läuft das stabil, nimmt man Godot-Web: gleicher Code, alle Effekte außer Haptik und Sensoren.
  - Sonst einen leichten HTML-Client mit reduzierter Optik.
- Browser-Clients starten in der Stufe „Reduziert“, wegen Akku und unbekannter Geräte, und lassen sich umschalten.

---

## 8. Gesamtübersicht nach Priorität (grobe Schätzung)

**Muss, ≈ 30–40 Entwicklungstage**
- Anpassungsfähige Hand A/B/C mit Fischauge (L)
- Schwung und Einrasten (M)
- Federn (M)
- Gesten, Joker-Farbrad, Rückmeldungen (M)
- Hervorhebung (S)
- Sortiermodi mit Animation und Flip-Umsortierung (M)
- Neutrale Gegneransicht (S)
- Tisch-Editor, Drehung, Layout für 2–10 Spieler, Abzeichen und Minikarten (L)
- Tischmitte, Farbring, Richtungsring, Zuganzeige (M)
- Weitergeben mit Drehung und Sichtschutz (M)
- Tischregie (M)
- Grundeffekte für alle Karten (L)
- Flip in der Grundform (M–L)
- Palette und Formsymbole (S)
- Kartenbaukasten mit MSDF (L)
- Effektstufen (S)

**Soll, ≈ 12–18 Tage**
- Joker-Strahlen (M)
- Joker in einer Geste (S)
- Gummiband, Schwung-Neigung, Haptik-Raster (S)
- Übersichtsblatt und Randmarken (M)
- Manuelles Sortieren (M)
- Prüfhilfe für die Plätze (S)
- Zugspur (S)
- Zieh 5 komplett und Spielautomat (M)
- Flip komplett mit Stimmung und Musik (M)
- Sieg komplett (S)
- Anzweifeln (M)
- Bildschirmwackeln (S)
- Shader vorwärmen (S)
- Automatische Rückstufung (S)
- Entwicklerwerkzeug für Farbsehschwäche (S)
- Kartengröße S/M/L (S)
- Klänge (M)
- Früher Web-Versuch (M)

**Kann**
- Zwei Reihen
- 3D-Zylinder
- Parallaxe und Glanz
- Holo-Joker mit Lagesensor
- Atmen im Leerlauf
- Ein-Tipp-Ausspielen
- Hausregeln „Reinwerfen“, „echte Reihenfolge“, „eigene Rückseiten“
- Manuelle Reihenfolge je Seite
- Selbstanordnung der Plätze
- Gemeinsame Tischanzeige
- iPhone-Haptik-Trick
- `prefers-reduced-motion`
- Linkshänder-Modus
- Maskottchen-Animationen

---

## 9. Offene Entscheidungen für den Nutzer

1. **Große Hände:** Bogen-Karussell als Standard (Vorschlag) oder lieber zwei Reihen? Am besten prototypisch beides auf dem Gerät testen.
2. **Ausspielen:** Doppeltipp plus Wischen (Vorschlag) oder ein Tipp?
3. **Gegnerhände:** neutral sortiert (Vorschlag) oder echte Reihenfolge des Besitzers?
4. **Eigene Rückseiten** standardmäßig ausblenden (Vorschlag)?
5. **Anzweifeln** von Joker +2 und „Zieh bis Farbe“ umsetzen? Davon hängt die Hervorhebung ab.
6. **Weitergeben-Modus:** Tisch zum aktuellen Spieler drehen (Vorschlag)?
7. **Leitmotiv** Sonne/Mond mit Mau-Katze und die abgestimmten Paletten in Ordnung?
8. **Renderer:** Compatibility statt Mobile (Vorschlag), damit App und Browser gleich aussehen?
9. **Browser-Client:** Soll der frühe iPhone-Versuch zwischen Godot-Web und HTML-Client entscheiden?

---

## Quellen

- Godot-Doku: [Geometry2D](https://docs.godotengine.org/en/stable/classes/class_geometry2d.html) · [CPUParticles2D](https://docs.godotengine.org/en/stable/classes/class_cpuparticles2d.html) · [Input.vibrate_handheld](https://docs.godotengine.org/en/stable/classes/class_input.html) · [Renderer-Vergleich](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html) · [Web-Export](https://docs.godotengine.org/en/latest/tutorials/export/exporting_for_web.html)
- Godot-Versionen: [Web-Export in 4.3](https://godotengine.org/article/progress-report-web-export-in-4-3/) · [Godot 4.5 Release](https://godotengine.org/releases/4.5/) · [Godot 4.6 Zusammenfassung](https://gamefromscratch.com/godot-4-6-released/)
- Web-Export klein bekommen: [Lean Godot Web Templates](https://jion.in/devlog/godot-web-minification) · [Build-Größe minimieren](https://popcar.bearblog.dev/how-to-minify-godots-build-size/)
- Shader und Beispiele: [Faux 3D Perspective (MIT)](https://godotshaders.com/shader/faux-3d-perspective-shader-for-2d-canvas-items/) · [Balatro card tilt](https://godotshaders.com/shader/balatro-card-tilt/) · [2D holographic card](https://godotshaders.com/shader/2d-holographic-card-shader/) · [card_fan_demo (MIT)](https://github.com/stormtoy/card_fan_demo)
- Bewegung und Gefühl: [Rubber-Band-Formel](https://gist.github.com/originell/6961057) · [WWDC18 Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/) · [Eiserloh, Juicing Your Cameras (GDC 2016)](http://www.mathforgameprogrammers.com/gdc2016/GDC2016_Eiserloh_Squirrel_JuicingYourCameras.pdf) · [FLIP-Animationen (Paul Lewis)](https://aerotwist.com/blog/flip-your-animations/)
- Spielregeln: Regelseite zur Flip-Ausgabe des Originals (Stapel, Wertung, Joker-Einschränkung); Link nur in der lokalen Quellenliste
- Farbe: [ColorADD (Lizenz)](https://en.wikipedia.org/wiki/ColorADD) · Farbenblind-Ausgabe des Originals (Link lokal) · [Machado et al. 2009](https://www.inf.ufrgs.br/~oliveira/pubs_files/CVD_Simulation/CVD_Simulation.html)
- Barrierefreiheit: [WCAG 2.3.1](https://w3c.github.io/wcag21/understanding/three-flashes-or-below-threshold.html) · [Touch-Zielgröße 48 dp](https://support.google.com/accessibility/android/answer/7101858)
- Browser-Einschränkungen: [Screen Wake Lock (MDN)](https://developer.mozilla.org/en-US/docs/Web/API/Screen_Wake_Lock_API) · [Safari 18.4](https://webkit.org/blog/16574/webkit-features-in-safari-18-4/) · [DeviceOrientation requestPermission](https://developer.mozilla.org/en-US/docs/Web/API/DeviceOrientationEvent/requestPermission_static) · [iOS-Haptik über Switch-Input](https://x.com/firt/status/2028807962295230776) · [Vollbild auf dem iPhone](https://developer.apple.com/forums/thread/133248) · [Playwright und iOS-Tests](https://www.browserstack.com/guide/playwright-ios-automation)
- Lokal gelesen: `C:\Users\Shakie\Documents\Programmierung\Draw2Race\game\scripts\player_colors.gd` (OKLab und Machado, wiederverwendbar für die Farbprüfung), `...\docs\RICHTLINIEN.md`, `...\AGENTS.md`, `...\game\scripts\pass_party.gd`