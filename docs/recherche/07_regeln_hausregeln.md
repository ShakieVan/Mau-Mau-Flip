# Regelgrundlage „Mau-Mau Flip“ (Recherche, Stand 04.10.2026)

## 0. Quellenlage: Es gibt zwei offizielle Fassungen, und sie widersprechen sich

| Kürzel | Fassung | Inhalt |
|---|---|---|
| **R18** | Originalauflage ©2018: EN-Blatt GDR44-0970 [Q1] und deutsches Blatt im 5-Sprachen-Faltblatt [Q2] | „helle/dunkle Seite“, Punkte bis 500, eigene Regeln für Aktionskarten als Startkarte |
| **R24** | Neuauflage mit Farbenblind-Symbolen: EN ©2024 GDR44-4B71 [Q4] und DE-Blatt „milde/wilde Seite“ [Q3] | Aktionskarte als Startkarte wird ignoriert. Neue Regel dazu, was nach einem Flip oben liegt. Joker zählen bei der Bluff-Prüfung als „passend“. Sieg = als Erster fertig, Punkte nur optional (das DE-Blatt R24 enthält gar keine Punktwertung). |

Das deutsche Blatt R18 hat Übersetzungsfehler: Der Text der „Zieh 5“-Karte steht auf Französisch, und in der Punktetabelle steht „Carte +5“. Einzelne Webseiten (z. B. fundexgames [Q20], 33rdsquare) erfinden Regeln (etwa „Bluff kostet 6 Karten“ oder „Spieler wählt Farbe UND Symbol“). Die sind nicht verlässlich.

---

## 1. Offizielle Regeln im Detail

### 1.1 Material (beide Fassungen gleich) [Q1][Q2][Q4]
112 doppelseitige Karten, 2–10 Spieler, ab 7 Jahren. **Es gibt keine 0.** Die Zahlen gehen von 1 bis 9, jede Zahl zweimal pro Farbe.

| Helle Seite (weißer Rand): Rot, Gelb, Grün, Blau | Anz. | Dunkle Seite (schwarzer Rand): Pink, Türkis, Orange, Lila | Anz. |
|---|---|---|---|
| Zahlen 1–9 (2× je Farbe) | 72 | Zahlen 1–9 (2× je Farbe) | 72 |
| Zieh 1 (2 je Farbe) | 8 | Zieh 5 (2 je Farbe) | 8 |
| Richtungswechsel | 8 | Richtungswechsel | 8 |
| Aussetzen | 8 | Alle aussetzen | 8 |
| Flip | 8 | Flip | 8 |
| Joker | 4 | Joker | 4 |
| Joker +2 | 4 | Joker „Zieh bis Farbe“ | 4 |

- Pro Farbe gibt es 26 Karten, dazu 8 Joker je Seite.
- Kontrollsummen für Unit-Tests: Punktsumme aller Karten hell = 1280, dunkel = 1480.
- **Welche Vorderseite auf welcher Rückseite liegt, veröffentlicht der Hersteller nicht.** Engine-Empfehlung: Die Paarung pro Runde mit Seed zufällig erzeugen. Da Mitspieler die Rückseiten sehen, kann sich dann niemand Paarungen merken.

### 1.2 Vorbereitung
- Alle Karten liegen gleich ausgerichtet. Jeder bekommt 7 Karten und hält die helle Seite zu sich. Die Mitspieler sehen also die dunkle Seite.
- Der Nachziehstapel liegt mit der hellen Seite nach unten. **Oben sieht man die dunkle Seite der obersten Karte.** Das ist offene Information und sollte in der UI sichtbar sein.
- Die oberste Karte des Nachziehstapels wird mit der hellen Seite nach oben als Ablagestapel aufgedeckt.
- Geber:
  - R18: Jeder zieht eine Karte, die höchste Zahl gibt (Symbolkarten zählen 0).
  - R24: „Geber bestimmen“.
  - Wer in Folgerunden gibt, steht in keiner Fassung. Engine-Vorschlag: Der Geber rotiert im Uhrzeigersinn (nicht offiziell).
- Es beginnt der Spieler links vom Geber, danach geht es im Uhrzeigersinn. Jede Runde startet auf der hellen Seite.

### 1.3 Startkarte (Sonderfälle)

| Startkarte | R18 | R24 | Andere Quellen | Engine-Default |
|---|---|---|---|---|
| Zieh 1 | Erster Spieler zieht 1 und setzt aus | ignorieren, nächste Karte aufdecken | – | R24 |
| Richtungswechsel | Geber beginnt, danach rechtsherum | ignorieren | – | R24 |
| Aussetzen | Spieler links vom Geber wird übersprungen | ignorieren | – | R24 |
| Joker | Spieler links vom Geber wählt die Farbe | ignorieren | gamerules.com: Geber wählt [Q15] | R24 |
| Joker +2 | zurück in den Stapel (DE: „einmischen“), neue Karte | ignorieren | – | R24 |
| **Flip** | **nicht geregelt** | ignorieren | Wikibooks, gamerules.com, eine weitere Regelseite, card-games.ca: alles wird gewendet, Start auf der dunklen Seite [Q12][Q14][Q15][Q19]. officialgamerules.org: zurückmischen [Q16]. Asmodee: unklar [Q17] | R24, dazu Option „Flip-Start dunkel“ |

**Unsicher:** Bei „ignorieren“ sagt R24 nicht, ob die Karte liegen bleibt oder zurückgemischt wird. Mein Vorschlag: Sie bleibt im Ablagestapel liegen, so wie es Wikipedia für die gleiche Regel des klassischen Originals von 2022 beschreibt [Q10]. Beim ersten Flip kommt dann ihre Rückseite nach oben, das ist unproblematisch.

### 1.4 Spielzug [Q1][Q2][Q4]
- Gelegt werden darf eine Karte, die zur obersten Ablagekarte passt: in Farbe, Zahl oder Symbol. Aussetzen darf also auf Aussetzen jeder Farbe. Joker gehen immer.
- Liegt ein Joker oben, zählt die gewünschte Farbe.
- Ein Joker darf auch gelegt werden, wenn man andere passende Karten hat. Man darf jede Farbe wünschen, auch die bisherige.
- Hat man keine passende Karte, zieht man **genau 1 Karte**. Passt sie, darf man sie sofort legen, muss aber nicht. Sonst ist der Zug vorbei.
- Man darf auch freiwillig ziehen, obwohl man eine passende Karte hat. Danach darf man **nur die gezogene Karte** legen.
- Pro Zug wird eine Karte gelegt. Einzige Ausnahme: „Alle aussetzen“ gibt einen kompletten Zusatzzug.

### 1.5 Karteneffekte

| Karte | Wirkung | Legbar auf | Punkte |
|---|---|---|---|
| Zieh 1 | Nächster Spieler zieht 1 und setzt aus | gleiche Farbe oder Zieh 1 | 10 |
| Richtungswechsel (beide Seiten) | Spielrichtung dreht sich | gleiche Farbe oder Richtungswechsel | 20 |
| Aussetzen | Nächster Spieler wird übersprungen | gleiche Farbe oder Aussetzen | 20 |
| Flip (beide Seiten) | siehe 1.7 | gleiche Farbe oder Flip (Flip ist kein Joker) | 20 |
| Joker (beide Seiten) | Wunschfarbe | immer | 40 |
| Joker +2 | Wunschfarbe; Nächster zieht 2 und setzt aus. Nur erlaubt ohne Karte der aktuellen Farbe auf der Hand. Kann angezweifelt werden. | immer | 50 |
| Zieh 5 | Nächster zieht 5 und setzt aus | gleiche Farbe oder Zieh 5 | 20 |
| Alle aussetzen | Alle anderen werden übersprungen; wer die Karte gelegt hat, ist sofort wieder dran (dann normal legen oder ziehen) | gleiche Farbe oder Alle aussetzen | 30 |
| Joker „Zieh bis Farbe“ | Wunschfarbe; Nächster zieht, bis er eine Karte dieser Farbe hat, behält alle Karten und setzt aus. Gleiche Einschränkung, kann angezweifelt werden. | immer | 60 |

**Kein Stapeln.** Zieh 1 auf Zieh 1 ist nur ein Symbol-Treffer, nachdem der Nächste schon gezogen hat. Der Hersteller hat für das klassische Original offiziell erklärt, dass Stapeln nicht erlaubt ist [Q9][Q10]. Für Flip sagen Asmodee und eine Regelseite dasselbe [Q12][Q17].

### 1.6 Joker +2 und „Zieh bis Farbe“: Einschränkung und Anzweifeln
- **Bedingung:** Man hat keine Karte in der aktuellen Farbe auf der Hand (bei Joker oben: die gewünschte Farbe). Passende Zahlen oder Symbole in anderen Farben sind erlaubt.
- **Widerspruch zwischen den Fassungen:** R24 sagt, Joker auf der Hand zählen ebenfalls als passend. Wer also irgendeinen Joker hält, darf nicht bluffen.
  - Wörtlich gelesen gilt das sogar für einen zweiten Joker +2. Wer zwei Joker +2 und nichts in der Farbe hat, dürfte dann keinen von beiden legen.
  - R18 erwähnt Joker nicht und prüft nur die Farbe.
  - Das wird eine Option.
- **Anzweifeln:** Nur der betroffene nächste Spieler darf anzweifeln, und zwar statt zu ziehen. Der Angezweifelte zeigt seine Hand nur dem Herausforderer.

| | Joker +2 | Zieh bis Farbe |
|---|---|---|
| Bluff erwischt | Leger zieht 2, Herausforderer zieht nichts | Leger zieht bis zur (selbst gewünschten) Farbe |
| Leger war ehrlich | Herausforderer zieht 4 und setzt aus | Herausforderer zieht bis zur Farbe, dann 2 weitere, und setzt aus |

  - Die gewünschte Farbe bleibt in jedem Fall bestehen (R24 sagt das ausdrücklich).
  - Ob der Herausforderer nach einem erfolgreichen Anzweifeln normal am Zug ist: Bei R18 steht das nicht ausdrücklich. R24 und das klassische Original legen es nahe [Q8][Q10]. Engine: ja.
  - Wer illegal legt und nicht angezweifelt wird, bekommt keine Strafe.
- **Ziehen bei „Zieh bis Farbe“:**
  - Man zieht auch dann, wenn man die Farbe schon auf der Hand hat [Q14].
  - **Unsicher:** Ob ein gezogener Joker das Ziehen beendet, regelt keine Fassung. Das Fan-Wiki und Geeky Hobbies sagen nein [Q13][Q21]. Engine-Default: Joker beendet das Ziehen nicht (als Option einstellbar).
  - Ist der Stapel leer, wird neu gemischt (siehe 1.11). Gibt es die Farbe in keinem Stapel mehr, ist das ungeregelt. Engine: Das Ziehen endet, der Spieler setzt trotzdem aus.
  - Manche deutschen Seiten schreiben, die gefundene Karte werde sofort abgelegt. Das ist falsch, man behält sie.

### 1.7 Flip im Detail [Q1][Q2][Q4]
Offizielle Reihenfolge: Zuerst wird der **Ablagestapel komplett umgedreht**, sodass die gerade gespielte Flip-Karte unten liegt. Dann wird der **Nachziehstapel umgedreht**, dann alle Handkarten. Die neue Seite gilt bis zum nächsten Flip.

In der Engine heißt das: Ablagestapel umkehren, Nachziehstapel umkehren, aktive Seite umschalten. Pro Karte muss keine eigene Ausrichtung gespeichert werden, weil immer alle Karten gleich liegen.

- **Neue oberste Ablagekarte** ist die bisher unterste Karte (Startkarte bzw. die Karte, die beim letzten Neumischen oben lag), jetzt mit ihrer anderen Seite. Die oberste Karte des Nachziehstapels ist die bisher unterste.
- Eine alte Wunschfarbe verfällt. Die Spielrichtung bleibt. Danach ist ganz normal der nächste Spieler dran.
- **Liegt nach dem Flip eine Aktionskarte oben:**
  - R18 regelt das nicht.
  - R24 (nur im EN-Text, im DE-R24-Text nicht gefunden): Die Aktion wird nicht ausgeführt. Der Wortlaut „muss nicht“ ist leicht mehrdeutig.
- **Liegt nach dem Flip ein Joker oben** (auch Joker +2 oder Zieh bis Farbe, dann ohne Ziehen):
  - R24: Wer den Flip gelegt hat, wählt die Farbe.
  - Wikibooks: Der nächste Spieler wählt [Q14].
  - Engine: R24.
- Sichtbarkeit: Mitspieler sehen jeweils die inaktive Seite deiner Handkarten. Oben auf dem Nachziehstapel sieht jeder die inaktive Seite.
- Ob man die Rückseiten der **eigenen** Karten ansehen darf, verbietet keine Regel. Eine Diskussion auf StackExchange sagt „erlaubt“ (nur über ein Suchergebnis gesehen, nicht direkt gelesen). Das ist eine Designentscheidung, siehe Optionen.

### 1.8 Zu zweit
- Die Flip-Anleitungen sagen dazu nichts.
- Die klassische Anleitung des Herstellers hat einen Abschnitt „Two-Handed Play“ [Q7]:
  - Richtungswechsel wirkt wie Aussetzen.
  - Nach Aussetzen oder einer Ziehkarte ist der Leger wieder dran.
  - last.cards sagt für Flip dasselbe [Q18].
- Ohne diese Regel hätte ein Richtungswechsel zu zweit gar keine Wirkung.
- Engine: Richtungswechsel bei 2 aktiven Spielern = Aussetzen. „Alle aussetzen“ wirkt zu zweit ohnehin genauso.

### 1.9 Letzte Karte ansagen
- Wer seine vorletzte Karte legt, ruft die Ansage (im Original der Spielname).
- Wird er erwischt, bevor der nächste Spieler seinen Zug beginnt, zieht er 2 Karten.
- Präzisierung aus der klassischen Anleitung [Q7]:
  - Man kann erst erwischt werden, wenn die vorletzte Karte auf dem Stapel liegt.
  - Wer selbst ruft, bevor ihn jemand erwischt, ist sicher.
  - Ein Zug beginnt, sobald man vom Stapel zieht oder eine Karte aus der Hand nimmt.
- Klassisches Original 2022: Ruft ein anderer zuerst, gibt es 2 Strafkarten [Q8].

### 1.10 Rundenende und letzte Karte
- Die Runde endet sofort, wenn eine Hand leer ist.
- Ist die letzte Karte eine Ziehkarte (Zieh 1, Zieh 5, Joker +2, Zieh bis Farbe), zieht der Nächste trotzdem. Diese Karten zählen bei der Wertung mit [Q1][Q2].
- Aussetzen, Richtungswechsel und Alle aussetzen haben als letzte Karte keine Bedeutung.
- **Flip als letzte Karte:** nicht geregelt. Es gibt nur den Hinweis „nach der Seite werten, auf der die Runde endete“.
  - gamerules.com, last.cards und Geeky Hobbies (dort als eigene Auslegung) sagen: Der Flip wird ausgeführt, gewertet wird auf der neuen Seite [Q13][Q15][Q18].
  - Engine: Flip ausführen, dann werten (Option).
- **Unsicher:** Darf man eine Joker-Ziehkarte anzweifeln, mit der jemand fertig geworden ist? Das ist ungeregelt. Mein Vorschlag: Ja. Wird der Bluff erwischt, zieht der Leger die Strafkarten und die Runde geht weiter.
- Offiziell darf man mit jeder Karte fertig werden, auch mit einem Joker.

### 1.11 Nachziehstapel leer
- Offiziell wird der Ablagestapel neu gemischt [Q1][Q2].
- Dass die oberste Karte liegen bleibt, steht beim Hersteller nicht ausdrücklich, ist aber üblich (bei Mau-Mau ausdrücklich so [Q26]). Engine: oberste Karte und ihre Wunschfarbe behalten.
- **Welche Seite?** Das ist nicht geregelt, ergibt sich aber aus der Physik: Der Ablagestapel liegt mit der aktiven Seite oben. Er wird gemischt und umgedreht, dann liegt die aktive Seite unten wie immer. In der Engine reicht einfaches Mischen.
- Sind beide Stapel erschöpft, verfallen restliche Ziehstrafen, und der Spieler passt (ungeregelt).

### 1.12 Wertung und Spielende
- Wer eine Runde gewinnt, bekommt die Punkte der Karten, die die anderen noch auf der Hand haben:
  - Zahlen zählen ihren Wert.
  - Zieh 1 = 10 Punkte.
  - Zieh 5, Richtungswechsel, Aussetzen, Flip = 20 Punkte.
  - Alle aussetzen = 30 Punkte.
  - Joker = 40, Joker +2 = 50, Zieh bis Farbe = 60 Punkte.
- **Gewertet wird die Seite, die bei Rundenende aktiv war.**
- R18: Wer zuerst 500 Punkte oder mehr hat, gewinnt.
- Alternative R18: Jeder sammelt die eigenen Restpunkte. Sobald einer 500 erreicht, gewinnt der Spieler mit den wenigsten Punkten.
- R24: Gewonnen hat, wer als Erster fertig ist. Die 500 Punkte sind nur eine optionale Variante.
- Gleichstand ist ungeregelt. Engine: geteilter Sieg oder eine Zusatzrunde (Option).

### 1.13 Offene Punkte und Engine-Default (Übersicht)
| Frage | Default |
|---|---|
| Flip als Startkarte | ignorieren und neu aufdecken (R24) |
| Aktionskarte nach Flip oben | keine Wirkung (R24) |
| Joker nach Flip oben | Flip-Spieler wählt die Farbe (R24) |
| Joker bei der Bluff-Prüfung | zählt nicht (R18), Option R24 |
| Joker beim Ziehen für „Zieh bis Farbe“ | beendet das Ziehen nicht |
| Flip als letzte Karte | wird ausgeführt, Wertung auf der neuen Seite |
| Richtungswechsel zu zweit | wirkt wie Aussetzen |
| Neumischen | oberste Ablagekarte bleibt liegen |
| Herausforderer nach erwischtem Bluff | ist normal am Zug |

---

## 2. Hausregeln
Komplexität für die Engine: **S** = einfacher Schalter, **M** = zusätzlicher Zustand oder UI, **L** = Echtzeit, Netzwerk oder verdeckte Information.

1. **Bis zum Letzten (Platzierungen)** [Q24]
   - Wer fertig ist, scheidet aus der Zugreihenfolge aus. Gespielt wird, bis nur noch einer Karten hat.
   - Flip: Fertige Spieler haben keine Hand mehr, die gewendet wird.
   - Ist die letzte Karte „Alle aussetzen“, ginge der Zug zurück an jemanden, der schon fertig ist. Vorschlag: Dann ist der Nächste nach ihm dran, die Karte wirkt also nicht.
   - Bei 2 Verbleibenden gilt die Zweierregel.
   - Wertung: entweder nur Platzierungen oder Platzierungspunkte. **M**
2. **Ziehkarten stapeln** [Q6] (offizielle Hausregel des Herstellers von 2008)
   - Wer von einer Ziehkarte betroffen ist, legt die gleiche Ziehkarte nach. Die Summe wandert weiter. Pro Zug darf man nur eine Ziehkarte legen.
   - Wird ein Joker +2 im Stapel erfolgreich angezweifelt, zählt die Strafe des ganzen Stapels.
   - Varianten:
     - (a) nur gleiche Karte: Zieh 1 auf Zieh 1, Joker +2 auf Joker +2, Zieh 5 auf Zieh 5
     - (b) gleiche oder höhere Karte, wie bei „No Mercy“ (dort nur aus einem Suchergebnis belegt): z. B. Joker +2 auf Zieh 1
     - (c) gemischt: jede Ziehkarte der aktiven Seite
   - Flip: Gestapelt wird immer nur innerhalb einer Seite. Ein Flip ist keine gültige Antwort auf einen offenen Stapel, außer man erfindet eine Variante (z. B. „ein Flip in derselben Farbe löscht den Stapel“, das wäre eine eigene Erfindung).
   - „Zieh bis Farbe“ hat keine Zahl. Vorschlag: Weitergeben ist erlaubt, das letzte Opfer zieht bis zur zuletzt gewünschten Farbe.
   - Zieh 5 sammelt sich schnell an: dreimal gestapelt sind 15 Karten.
   - Komplexität: **M**, beim Anzweifeln im Stapel **L**.
3. **Reinwerfen (Jump-In)** [Q6]
   - Wer eine exakt gleiche Karte hält (gleiche Farbe und gleicher Wert auf der aktiven Seite), darf sie sofort außer der Reihe legen. Danach geht es vom Reinwerfer aus weiter.
   - Doppelte Karten legt man nacheinander, damit andere dazwischen reinwerfen können.
   - Wirft man mit Aussetzen, Richtungswechsel oder einer Ziehkarte rein, verdoppelt sich die Wirkung nicht. Die Karte wirkt einfach ab dem Reinwerfer.
   - Flip: Auf einen Flip kann man nicht reinwerfen, weil er danach unten liegt.
   - Im Modus „Weitergeben“ ist das praktisch nicht spielbar. Im Netzwerk entscheidet der Host anhand von Zeitstempeln, wer zuerst war. **L**
4. **7-0** [Q6]
   - Wer eine 7 legt, tauscht seine Hand mit einem Spieler seiner Wahl. Bei einer 0 geben alle ihre Hand in Spielrichtung weiter.
   - **In Flip gibt es keine 0.** Vorschlag: frei wählbare „Weitergabe-Zahl“, z. B. die 1 („eins weiter“).
   - Wer durch Tauschen auf 1 Karte kommt, muss nicht „Mau!“ rufen.
   - Laut Fan-Wiki hat Ubisoft 7-0 im Flip-Modus nicht angeboten (nur über ein Suchergebnis gesehen, Quelle nicht geöffnet).
   - Es gibt 8 Siebener pro Seite. **M**
5. **Ziehen bis spielbar** (bei Ubisoft „Draw to Match“) [Q23][Q24]
   - Man zieht, bis eine Karte passt.
   - Zusammen mit der dunklen Seite wird das hart.
   - Wenn kein Stapel mehr da ist: abbrechen. **S**
6. **Spielzwang**, in drei Varianten:
   - (a) Eine passende gezogene Karte **muss** gelegt werden (Ubisoft „Force Play“).
   - (b) Wer legen kann, muss legen [Q24].
   - (c) Eine gezogene Karte darf **nicht** gelegt werden (regionale Mau-Mau-Variante [Q27]).
   - Zwang kann ungewollte Flips erzwingen. **S**
7. **Bluff und Anzweifeln**, drei Modi:
   - offiziell (Bluff möglich, Anzweifeln erlaubt)
   - App erzwingt die Regel (Bluff unmöglich, gut für Kinder)
   - frei spielbar (keine Einschränkung; Ubisoft „No Bluffing“)
   - Beim Anzweifeln muss der Host die Hand nur an den Herausforderer schicken. **M** bis **L**
8. **Ansagen „Mau!“ und „Mau-Mau!“**
   - Mau-Mau-Tradition [Q26][Q27][Q28]: „Mau“ nach der vorletzten Karte. Wer es vergisst und erwischt wird, zieht 1 Karte (Deutschland) bzw. 2 (Österreich und Schweiz).
   - „Mau-Mau“ ruft man bei der letzten Karte. Wer es vergisst, hat nicht gewonnen und zieht 1 bis 2 Strafkarten.
   - Details siehe Abschnitt 3. **M**
9. **Beenden mit Aktionskarte**
   - erlaubt (offiziell)
   - nicht mit Joker (Mau-Mau: „nicht mit Bube“)
   - nicht mit Aktionskarte
   - Ende mit Joker zählt doppelt [Q27]
   - Ist das Beenden verboten und hat man nur noch eine solche Karte, muss man ziehen. **S**
10. **Joker auf Joker verboten** („Bube auf Bube stinkt“) [Q26]. Gilt für beide Seiten. **S**
11. **Rundenzahl statt 500 Punkte**: feste Rundenzahl (3, 5 oder 10), dazu Zielpunkte frei einstellbar (250, 500 oder 1000) oder Strafpunkte-Wertung. **S**
12. **Gnadenregel**: Wer 25 oder mehr Karten hat, scheidet aus (aus „No Mercy“, nur über ein Suchergebnis belegt). Passt zur Härte der dunklen Seite. **S**
13. **Flip-spezifische Varianten**:
    - Flip als Startkarte → Partie beginnt auf der dunklen Seite [Q14][Q15]
    - „Flip-Überraschung“: Die Aktionskarte, die nach dem Flip oben liegt, wirkt auf den Nächsten
    - „Progressive Flip“: Jeder Flip lässt den Nächsten 1 Karte ziehen [Q19]
    - Eigene Rückseiten sehen ein oder aus
    - Joker nach Flip: Flip-Spieler wählt / Nächster wählt
    - Alles **S**
14. **Zugzeit** (Mau-Mau kennt dafür die „Schlafkarte“ [Q27]): Läuft die Zeit ab, wird automatisch gezogen. **S**
15. Für später: **Partnerspiel** (offizielle klassische Variante, Partner sitzen gegenüber [Q7]) und mehrere gleiche Karten auf einmal legen [Q23]. **M**

---

## 3. Deutsche Begriffe (keine Marken des Herstellers)
Der Name des Originalspiels kommt nirgends vor, auch kein Logo und kein Oval. Die beschreibenden Kartennamen sind allgemeine Spielsprache. Wortschöpfungen des Herstellers meide ich trotzdem: „Retour“, „Farbenwahl-Karte“, „Kartenstock“, „Ablegestapel“, „milde/wilde Seite“, „Farbe ziehen-Joker“. Die Kombination „Mau-Mau Flip“ würde ich vor der Veröffentlichung im DPMAregister und in EUIPO eSearch prüfen [Q29]. „Mau-Mau“ selbst ist ein traditioneller Spielname, den es seit etwa den 1930er-Jahren gibt [Q26]. Das ist kein Rechtsrat.

| Element | Vorschlag | Alternative |
|---|---|---|
| Seiten | Helle Seite / Dunkle Seite | Tag / Nacht |
| Farben | Rot, Gelb, Grün, Blau / Pink, Türkis, Orange, Lila | – |
| +1 | „+1“ (Zieh 1) | Eins ziehen |
| +5 | „+5“ (Zieh 5) | Fünf ziehen |
| Aussetzen / Alle aussetzen | Aussetzen / Alle aussetzen | Pause / Rundum-Pause |
| Richtungswechsel | Richtungswechsel | Kehrtwende |
| Flip | Flip | Wende |
| Joker | Wünscher (Mau-Mau-Tradition) | Joker, Farbwunsch |
| Joker +2 | Wünscher +2 | Joker +2 |
| Joker „Zieh bis Farbe“ | Farbjagd | Zieh bis Farbe, Farbfalle |
| Stapel | Nachziehstapel, Ablagestapel | Talon |
| Weitere Aktionen | Anzweifeln („Bluff!“), Erwischt!, Wunschfarbe, Strafkarte, Geber, Runde, Partie | – |

**Ansage-Regel für die App:**
- **„Mau!“** muss gerufen werden, wenn man die vorletzte Karte legt.
  - Der Button wird aktiv, sobald man am Zug ist und 2 Karten hält. Man darf ihn vor oder nach dem Legen drücken, bis der nächste Zug beginnt.
  - Wer selbst ruft, bevor er erwischt wird, ist sicher.
  - Vergessen und erwischt: Standard 2 Strafkarten, als Option 1.
  - Kommt man durch Tauschen auf 1 Karte, ist keine Ansage nötig.
  - Bei „Alle aussetzen“ endet das Zeitfenster, sobald der eigene Zusatzzug beginnt.
- **„Mau-Mau!“** ist optional und wird mit der letzten Karte gerufen.
  - Fehlt der Ruf und jemand drückt „Erwischt!“ rechtzeitig, ist man noch nicht fertig und zieht Strafkarten (Standard 1, Option 2). Die Wirkung der gelegten Karte gilt trotzdem.
  - Erwischt niemand den Spieler, hat er gewonnen.
- **Wer kontrolliert:**
  - „Erwischen“: Mitspieler drücken einen Button. Im Netzwerk entscheidet der Host anhand von Zeitstempeln, mit etwa 1,5 s Schonfrist wegen Latenz.
  - „Automatisch“: Die App bestraft sofort.
  - „Nur Erinnerung“: für Kinder.
  - Im Modus „Weitergeben“: Entweder „Automatisch“, oder der „Erwischt!“-Button erscheint ein paar Sekunden auf dem Übergabe-Bildschirm.

---

## 4. Vorschlag für den Regeloptionen-Bildschirm
Gruppen, jeweils mit **Standardwert** in Klammern:

1. **Spielziel und Wertung**
   - Rundenende: (Erster fertig) / Bis zum Letzten
   - Wertung: (keine) / Siegpunkte / Strafpunkte / Platzierungspunkte
   - Partieende: (500 Punkte; einstellbar 250 / 500 / 1000) / Rundenzahl 1–20
   - Flip als letzte Karte: (ausführen und neue Seite werten) / nicht ausführen
2. **Start**
   - Handkarten: 5–10 (7)
   - Aktionskarte als Startkarte: (ignorieren, R24) / Wirkung wie R18
   - Flip als Startkarte: (neu aufdecken) / Partie startet dunkel
   - Startspieler: (links vom rotierenden Geber) / Sieger der Vorrunde / Verlierer der Vorrunde / zufällig
3. **Ziehen und Legen**
   - Ziehen, wenn nichts passt: (1 Karte) / bis spielbar
   - Gezogene Karte: (darf) / muss / darf nicht gelegt werden
   - Legepflicht: (aus) / an
   - Joker auf Joker: (erlaubt) / verboten
   - Beenden mit: (jeder Karte) / nicht mit Joker / nicht mit Aktionskarte / Joker zählt doppelt
4. **Ziehkarten und Joker**
   - Stapeln: (aus) / gleiche Karte / gleich oder höher / gemischt
   - Farbjagd weitergeben: (nein) / ja
   - Joker-Einschränkung: (Bluff mit Anzweifeln) / App erzwingt / frei
   - Joker zählen bei der Bluff-Prüfung: (nein, R18) / ja, R24
   - Gezogener Joker beendet die Farbjagd: (nein) / ja
5. **Flip**
   - Aktionskarte nach Flip: (keine Wirkung) / Flip-Überraschung
   - Joker nach Flip: (Flip-Spieler wählt) / Nächster wählt
   - Eigene Rückseiten sehen: (aus) / an
   - Progressive Flip: (aus) / an
6. **Ansagen**
   - „Mau!“: (an) / aus
   - „Mau-Mau!“: (aus) / an
   - Kontrolle: (Erwischen im Netzwerk; automatisch bei Weitergeben) / automatisch / nur Erinnerung
   - Strafkarten: Mau (2), Mau-Mau (1)
7. **Sonderregeln**
   - Reinwerfen: (aus) / an. Nur im Netzwerk- und Browser-Modus, bei „Weitergeben“ ausgegraut.
   - 7 = Hände tauschen: (aus) / an
   - Weitergabe-Zahl: (keine) / 1–9
   - Zu zweit wirkt Richtungswechsel wie Aussetzen: (an) / aus
   - Gnadenregel: (aus) / 25 Karten
   - Zugzeit: (aus) / 15 / 30 / 60 s

**Voreinstellungen** (nur die Abweichungen vom Standard sind aufgeführt):

| Voreinstellung | Abweichungen |
|---|---|
| **Offiziell** (R24, als Startwert) | Joker zählen bei der Bluff-Prüfung: ja. Wertung: keine (500 Punkte optional). |
| **Klassisch 500** (R18) | Siegpunkte bis 500. Startkarte nach R18, Flip als Startkarte wird neu aufgedeckt. |
| **Familie** | Bis zum Letzten, Wertung nach Platzierung. Stapeln nur gleiche Karte. App erzwingt die Joker-Regel. Mau! und Mau-Mau! mit Erwischen, je 1 Strafkarte. |
| **Mau-Mau-Tradition** | Stapeln nur gleiche Karte (wie die Siebener). Joker auf Joker verboten. Nicht mit Joker beenden. Mau! und Mau-Mau! Pflicht, je 1 Strafkarte. App erzwingt die Joker-Regel. |
| **Chaos** | Bis zum Letzten. Ziehen bis spielbar. Stapeln gemischt, Farbjagd weitergeben. Reinwerfen an. 7-Tausch und Weitergabe-Zahl 1. Flip-Überraschung und Progressive Flip an. Gnadenregel 25. |
| **Schnell** | 5 Handkarten, 3 Runden, Zugzeit 20 s. |

Vorschlag für die Umsetzungsreihenfolge:
- **Zuerst:** offizielle Regeln, die Optionen aus 1.13, Bis zum Letzten, Stapeln, die Mau-Ansagen und die drei Bluff-Modi.
- **Danach:** Reinwerfen, 7-Tausch und Partnerspiel.

Die Engine sollte eine deterministische Zustandsmaschine mit Seed-Zufall und einem Regel-Konfigurationsobjekt sein. Jeder Spieler bekommt nur die Informationen, die er sehen darf.

---

## Quellen

Links, die den Namen des Originalspiels enthalten, stehen nur in der lokalen Quellenliste (`docs/recherche/_lokal/`, nicht im Repo).
- [Q1] Herstelleranleitung, Flip-Ausgabe EN 2018 (GDR44-0970)
- [Q2] Herstelleranleitung, Flip-Ausgabe 5-sprachig inkl. DE 2018
- [Q3] Herstelleranleitung, Flip-Ausgabe DE-Neuauflage
- [Q4] Herstelleranleitung, Flip-Ausgabe EN ©2024 mit Farbenblind-Symbolen (GDR44-4B71)
- [Q5] Hersteller-Service, Produktseite GDR44
- [Q6] Herstelleranleitung, klassisches Original 2008 (Hausregeln Progressive / Seven-O / Jump-In)
- [Q7] Herstelleranleitung, klassisches Original 52277 (Two-Handed Play, Strafen, Partner)
- [Q8] Herstelleranleitung, klassisches Original 2022 (HJH90)
- [Q9] Offizielles Konto des Herstellers auf X zum Stapeln
- [Q10] Wikipedia (en), Artikel zum klassischen Original
- [Q11] Wikipedia (en), Artikel zur Flip-Ausgabe
- [Q12] Regelseite zur Flip-Ausgabe
- [Q13] geekyhobbies.com, Test und Regeln der Flip-Ausgabe 2019
- [Q14] Wikibooks, Seite zur Flip-Ausgabe
- [Q15] gamerules.com, Regeln der Flip-Ausgabe
- [Q16] officialgamerules.org, Regeln der Flip-Ausgabe
- [Q17] Asmodee UK, Blogbeitrag zu den Flip-Regeln
- [Q18] last.cards, Regeln der Flip-Ausgabe
- [Q19] card-games.ca, Regeln der Flip-Ausgabe
- [Q20] (unzuverlässig) fundexgames.com, Flip-Regeln erklärt
- [Q21] (nur Suchergebnis) Fan-Wiki zum Original: Joker „Farbe ziehen“; Hausregeln der Ubisoft-Umsetzung
- [Q22] (nur Suchergebnis) StackExchange, eigene Rückseiten in der Flip-Ausgabe
- [Q23] pagat.com, Varianten des Originals
- [Q24] Regelseite mit Hausregeln
- [Q25] (nur Suchergebnis) Regelseite zur No-Mercy-Ausgabe
- [Q26] https://de.wikipedia.org/wiki/Mau-Mau_(Kartenspiel)
- [Q27] https://www.spielwiki.de/Mau-Mau
- [Q28] https://www.spielkarten.com/blog/spiel-und-spass/mau-mau-regeln-die-einen-umhauen/
- [Q29] https://register.dpma.de/ und https://euipo.europa.eu/eSearch/