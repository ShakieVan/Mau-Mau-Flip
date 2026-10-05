# Entwurfsvergleich: drei Gestaltungsrichtungen für Mau-Mau Flip

Stand 04.10.2026. Geprüft wurden die Entwürfe in `a-papier-neon/`, `b-art-deco/` und `c-geometrisch/`. Die Entwürfe selbst habe ich nicht verändert. Die Wahl trifft der Nutzer.

Übersicht mit allen Bildern: `index.html` (gerendert als `uebersicht.png`). Farbsehschwäche im Detail: `farbsehschwaeche.html` (gerendert als `farbsehschwaeche.png`).

## So wurde geprüft

1. **Alle Bilder der Designer angesehen:** `logo.png`, `hand.png`, `icon.png` und `preview.png` jeder Richtung.
2. **Gleiche Bedingungen für alle:** Die 16 geforderten Karten jeder Richtung habe ich einzeln aus den SVGs gerendert, jeweils mit den Schriften der Richtung. Daraus entstanden:
   - je ein **Kartenbogen** (`_pruefung/kartenbogen_?.png`),
   - je ein **Streifentest** (`_pruefung/streifen_?.png`): Karte 80 dp breit, davon 22 dp sichtbar, nur die obere Kartenhälfte. Links die helle Hand, rechts die dunkle. Alle acht Farben kommen vor.
   - Neu erzeugen lässt sich alles mit `bash _pruefung/pruefbilder.sh`.
3. **Farbsehschwäche:**
   - Handansicht und Streifentest jeder Richtung mit SVG-Farbmatrix-Filtern für Protanopie, Deuteranopie und Tritanopie. Grundlage sind die Matrizen von Machado 2009 mit Schweregrad 1, angewendet im linearen RGB. Dazu kommt eine Ansicht nur nach Helligkeit.
   - Außerdem habe ich die OKLab-Abstände aller Farbsätze nachgerechnet, auch die der Leuchttöne, die die Designer zusätzlich eingeführt haben.
4. **Technik:**
   - Merkmale der SVGs gezählt: Text, Filter, Rauschen, Mischmodi, Ebenen.
   - Eine Karte je Richtung direkt als SVG-Datei geöffnet, um das Laden der Schrift zu prüfen.
   - Den Namen des Vorbilds in allen Textdateien gesucht: kein Treffer.
5. **App-Symbole** auf 48 px verkleinert und vergrößert betrachtet.

## Noten

Note 1 = sehr gut, 2 = gut, 3 = befriedigend, 4 = ausreichend, 5 = mangelhaft.

| Kriterium | A Papier & Neon | B Art déco | C Geometrisch |
|---|:-:|:-:|:-:|
| (a) Eckindex im 22-dp-Fächer, Querformat | **1** | 2 | **1** |
| (b) Farbsehschwäche (Protan, Deutan, Tritan) | **1** | 2 | 3 |
| (c) Abstand zum Vorbild | **1** | **1** | 2 |
| (d) Katze und Logo: „erwachsen, aber süß“ | 3 | **2** | 3 |
| (e) App-Symbol bei 48 px | **2** | 4 | **2** |
| (f) Animation (Ebenen) und Godot-Import | 3 | 3 | **1** |
| (g) Kartenfarbe auf einen Blick (Ablage, Gegner) | **1** | 3 | **1** |
| (h) Kartenwirkung hochwertig und erwachsen | 2 | **1** | 3 |
| **Durchschnitt** | **1,8** | 2,3 | 2,0 |
| Durchschnitt, (d) und (h) doppelt gewichtet | **1,9** | 2,1 | 2,2 |

(g) und (h) habe ich zusätzlich zu den Kriterien (a) bis (f) aufgenommen. Sie entsprechen den Wünschen „nahe am vertrauten Funktionsprinzip“ und „hochwertig, erwachsen“.

## Befunde je Kriterium

### (a) Eckindex im Fächer

Im Streifentest bei gleichen Bedingungen (80 dp Kartenbreite, 22 dp sichtbar, obere Hälfte) bleiben bei allen drei Richtungen Wert und Formsymbol vollständig im Streifen.

- **A:** Der Wert steht hoch und schmal in Druckschwarz auf der Papierlasche, das Symbol darunter in Farbe, das Farbfeld direkt daneben. Sehr klar. Auf der dunklen Seite steht der Wert in Mondlicht, gut lesbar. „Alle aussetzen“ (drei Katzenköpfe) ist das feinste Zeichen.
- **B:** Das Banner nutzt nur etwa zwei Drittel des Streifens. Die Werte in Limelight sind deshalb kleiner, und das „+“ bei +1, +5 und +2 ist winzig. Die kleinen Rauten unter der Pfote im Joker-Banner wirken unruhig. Lesbar, aber am knappsten.
- **C:** Die größten und kräftigsten Ziffern (Jost, schwer) mit kompaktem „+“ und voller Farbe dahinter. Am besten lesbar. Den Punktring um „Zz“ bei „Alle aussetzen“ sieht man im Streifen gerade noch.

Die Designer haben in ihren eigenen Handansichten unterschiedlich breite Streifen gewählt: A 36 dp, B etwa 22 dp, C 22 bis 52 dp. Erst der Streifentest unter gleichen Bedingungen macht sie vergleichbar.

### (b) Farbsehschwäche

Kleinster OKLab-Abstand zwischen den vier Farben einer Seite (eigene Nachrechnung, Ziel ≥ 0,15):

| Farbsatz | normal | Protan | Deutan | Tritan |
|---|:-:|:-:|:-:|:-:|
| Hell, Flächen (alle drei) | 0,268 | 0,190 | 0,164 | 0,152 (Grün–Blau) |
| Dunkel, Flächen (Startpalette, B und C) | 0,193 | 0,160 | 0,184 | 0,149 (Pink–Orange) |
| Dunkel, Flächen A (Pink #FF9ECF) | 0,198 | 0,160 | 0,189 | 0,161 |
| Dunkel, Neon A | 0,208 | 0,161 | 0,195 | 0,165 |
| Dunkel, Leuchttöne B (Konturen, Neon-Werte) | 0,151 | **0,005** (Pink–Türkis) | **0,071** | **0,123** |
| Dunkel, Leuchttöne C (Wert und Symbol im Index) | 0,162 | **0,005** (Pink–Türkis) | **0,083** | **0,123** |

- **A:** Am robustesten. Auch die Neontöne folgen der Helligkeitsstaffel, deshalb bleiben die vier dunklen Farben in jeder Simulation getrennt. Die Angaben des Designers stimmen.
  - Schwachpunkt: Lila-Neon `#5E3BD8` hat auf dem Nachtgrund nur etwa 2,8 : 1 Kontrast und wirkt matt.
  - Einfach aufhellen hilft nicht. Schon `#6A48E0` (3,3 : 1) drückt Türkis–Lila bei Tritanopie auf 0,136. Besser bekommen lila Elemente einen hellen Kern oder eine helle Kontur, und der Farbton bleibt im Leuchten.
- **B:** Die Index-Banner sind in den Flächenfarben gefüllt und tragen damit die geprüfte Staffel. Die neuen, sehr hellen Leuchttöne fallen bei Protanopie praktisch zusammen. Das betrifft aber nur Konturen und Neon-Werte, und B hat sie selbst als ungeprüft gemeldet.
- **C:** Die helle Seite ist in jeder Simulation die stärkste, weil die vollen Flächen die Farbe tragen. Auf der dunklen Seite stehen Wert und Symbol im Index aber im hellen Leuchtton:
  - Bei Protanopie und Deuteranopie sehen Pink und Türkis im Index gleich aus. Dann trennt nur noch die Form (Herz bzw. Welle).
  - Bei Tritanopie liegen Orange und Pink nahe beieinander.
  - Die Prüftabelle von C rechnet nur die Grundfarben und erfasst das nicht.
- **Alle drei:** Grün und Blau liegen bei Tritanopie an der Grenze (0,152). Rot und Blau sind ohne Farbe gleich hell (L 0,50 und 0,52). An beiden Stellen müssen Kleeblatt, Kristall und Flamme die Unterscheidung tragen. Das tun sie bei allen drei.
- Hell und dunkel sind bei allen drei auch ohne Farbe sofort zu unterscheiden.

### (c) Abstand zum Vorbild

- **Bei allen drei eingehalten:**
  - kein Oval, nichts Schräges, keine Zahl mit Schlagschatten, keine Oval-Rückseite,
  - kein fremder Name in den Dateien,
  - eigene Aktionssymbole.
- **A** hat mit der Papierlasche die eigenständigste Silhouette.
- **B** ist durch Tarot-Bogen, Banner und Goldlinien am weitesten entfernt.
- **C** ist im Gesamteindruck am vertrautesten: volle Farbfläche, weiße Ziffer in der Mitte, heller Rand. Das ist gewollt und zulässig. Der helle Wünscher aus vier Farbvierteln mit heller Scheibe in der Mitte erinnert aber am stärksten an das bekannte Joker-Bild. Ihn würde ich ändern.

### (d) Katze und Logo

Die Referenz zeigt eine Katze in Vorder- bzw. Dreiviertelansicht. Sie legt den Kopf in den Nacken, schaut nach oben und legt die Pfote an den Maulwinkel.

- **A:** Handwerklich sauber, mit schöner Komposition: Die Bildfläche ist diagonal in Papier und Nacht geteilt, und der Schriftzug wechselt die Seite („Mau-Mau“ in Druckfarbe, „Flip“ als Neon).
  - Die Katze ist aber eine Comicfigur mit großem Kopf und Kulleraugen. Sie wirkt eher jünger als die Referenz, und das war der Hauptkritikpunkt des Nutzers.
  - Sie schaut eher geradeaus als nach oben.
  - Im Logo-SVG sind Katze und Schriftzug nicht als Ebenen benannt.
- **B:** Am erwachsensten und als einzige wirklich mit Blick nach oben: eine elegante Smokingkatze mit Goldlicht links, violettem Licht rechts und Sonne-Mond-Medaillon. Logo und Schriftzug (Limelight in Gold) wirken wie aus einem Guss. Schwächen:
  - Profil statt Dreiviertelansicht.
  - Der Arm ist eine gerade Röhre ohne Ellbogen.
  - Das dunkelblaue Fell verschwindet fast im dunkelblauen Grund und lebt nur vom Goldrand.
  - Der Zeiger der Sprechblase läuft durch die Schnurrhaare.
- **C:** Wirkt wie eine fertige Marke: Wortmarke rechts, der i-Punkt als Tag-Nacht-Scheibe, Farbband. Schwächen:
  - Die Katze ist unten sehr massig, und links sitzt eine Schulterbeule.
  - Der Kopf ist kaum geneigt.
  - Die Pfote ist eine Scheibe vor dem Maul.
  - Freundlich, aber plump statt anmutig.

### (e) App-Symbol bei 48 px

- **A:** Das Katzengesicht füllt die Fläche, Sonne und Mond sind erkennbar. Gut.
- **B:** Dunkel und kleinteilig, der doppelte Goldrahmen kostet etwa ein Viertel der Fläche. Android legt bei adaptiven Symbolen seine eigene Maske über das Symbol und würde den Rahmen beschneiden.
- **C:** Die Hälften in Gelb und Nachtblau sind das stärkste Signal bei kleiner Größe. Das Gesicht wird klein, weil Arm und Schwanz mit im Bild sind.

### (f) Animation und Godot

- **Bei allen drei gleich:** Jede Karte hat die Ebenen `rahmen`, `grund`, `motiv`, `symbol`, `wert` und `index`, und alle setzen Werte und Index als Text. Godot rastert SVGs mit ThorVG, Text und Filter werden dort nicht zuverlässig dargestellt. Werte und Index müssen also als Label mit der Schrift gesetzt oder in Pfade umgewandelt werden. Das sollte mit einem Probe-Import in Godot 4.6 bestätigt werden.
- **A:** Mit Abstand am meisten Effekte im SVG: 163 Filterverweise auf 20 Karten, Papierkorn per Rauschfilter und Mischmodi. Der Look hängt daran und muss als Shader nachgebaut werden.
  - Die Karten haben zusätzlich `index_oben` und `index_unten`, das ist gut für Animationen.
  - Das Logo hat keine benannten Gruppen für Katze und Schriftzug.
- **B:**
  - Viel Text (auch das Farbwort im Titelband), viele feine Goldlinien und Glühen auf der Nachtseite.
  - Die feinen Linien werden bei 80 dp Kartenbreite flimmern oder verschwinden.
  - Die Karten-SVGs binden die Schrift nicht ein: Einzeln geöffnet erscheint eine Ersatzschrift, das habe ich geprüft.
  - Das Logo ist gut gegliedert (`katze`, `mau`, `schriftzug`).
- **C:** Flache Formen, Filter nur für das Glühen der Nachtseite, die kleinsten Dateien (etwa 5 KB pro Karte). Das Logo ist gut gegliedert (`katze`, `ausruf`, `schriftzug`, `flip-punkt`). Am leichtesten in Godot nachzubauen.
- **Für den Browser-Client:** A und C nutzen in jeder Karte dieselben IDs für Verläufe (z. B. A `feldlicht` und `mondlicht`, C `halo`), deren Farben aber je Karte verschieden sind. Setzt der Lite-Client mehrere Karten direkt in eine Seite, greifen alle Karten auf die Definitionen der ersten zu und bekommen falsche Farben. B hängt den Kartennamen an die IDs an.

### (g) Kartenfarbe auf einen Blick

- **A und C:** Die Kartenfarbe ist sofort da, auch auf dem Ablagestapel und in den kleinen Gegnerfächern.
- **B:** Die helle Seite ist überwiegend Elfenbein mit pastellfarbenen Strahlen. Die Farbe steckt im Banner und im großen Wert, und das kostet im schnellen Spiel Erkennbarkeit.

### (h) Kartenwirkung

- **B:** Am hochwertigsten und erwachsensten. Das Art-déco-Tarot liegt auch am nächsten am Kartenstil der Referenz (Sonne bzw. Mond über Wasser, feine Linien).
- **A:** Eigenständig und sympathisch: Siebdruck und Neon, hell und dunkel klar als dieselbe Landschaft erkennbar. Die Katzengesichter auf den Aktionskarten und der sehr bunte helle Wünscher ziehen die Wirkung etwas ins Verspielte.
- **C:** Sauber und modern. Die helle Seite wirkt aber wie ein übliches Familienkartenspiel. Die dunkle Seite mit Mondsichel und Leuchtrahmen ist deutlich stärker.

## Richtung A „Papier & Neon“

**Stärken**
- Eigene Silhouette durch die Papierlasche: wiedererkennbar und klar entfernt vom Vorbild.
- Tag und Nacht als dieselbe Landschaft, dadurch ist der Flip als Verwandlung lesbar.
- Beste Farbsehschwäche-Werte auf beiden Seiten, auch bei den Neontönen.
- Index sehr gut lesbar, Kartenfarbe sofort erkennbar.
- Starke Logo-Idee: geteilte Bildfläche, Schriftzug wechselt die Seite, das „M“ auf der Stirn.
- Gutes App-Symbol.

**Schwächen**
- Katze im Comicstil mit großem Kopf, nicht erwachsen. Sie schaut kaum nach oben.
- Viele SVG-Effekte (Korn, Glühen, Mischmodi), die Godot nicht übernimmt.
- Heller Wünscher und Wünscher +2 sehr bunt. Lila-Neon matt.
- Logo ohne benannte Ebenen. Generische IDs in den Karten.

**Konkrete Verbesserungen**
1. **Katze neu proportionieren:**
   - Kopf etwa 1/4 statt 1/3 der Figur, mandelförmige Augen mit Pupillen oben.
   - Kopf in den Nacken, schlanker Hals, Pfote mit Ellbogen an den Maulwinkel.
   - Dünnere Kontur.
   - Pose wie in der Referenz, Haltung wie die Katze aus B.
2. **Aktionsmotive** grafischer: Katzensilhouetten statt Kulleraugen-Gesichter, z. B. eine schlafende Katze als Linie.
3. **Hellen Wünscher beruhigen:** Vierfarbiger Kranz nur als schmaler Ring, mehr Papier.
4. **Lila-Elemente auf Nacht** mit hellem Kern oder heller Kontur statt helleren Farbtons, damit Türkis–Lila bei Tritanopie über 0,15 bleibt.
5. **Korn und Glühen** nicht ins SVG, sondern als Shader in Godot. SVG flach halten, Werte als Label oder Pfad.
6. **Logo:** Gruppen `katze`, `mau` und `schriftzug` benennen. In den Karten die IDs mit dem Kartennamen versehen.
7. **Kräftigere Indexziffern,** z. B. Bricolage in fetterem Schnitt, wie bei C.

## Richtung B „Art déco / Tarot“

**Stärken**
- Erwachsenster, edelster Gesamteindruck. Am nächsten am Kartenstil der Referenz.
- Durchgängiges System: Bogen, Banner, Schlussstein, Titelband, Goldrahmen.
- Die Katze schaut wirklich nach oben, mit einer eleganten Smokingfigur.
- Schöne Details: Sonne-Mond-Medaillon, Mondphasen am Bogen, Sanduhr für Aussetzen, Katzenauge für Farbjagd.
- Sehr guter Bild-Prompt mit und ohne Schrift und einem Hinweis zur Posen-Referenz.
- Bedienelemente der Hand vollständig: alle vier Sortierarten, „Rückseiten ansehen“.

**Schwächen**
- Auf der hellen Seite wenig Kartenfarbe: Elfenbein mit Pastell.
- Index-Schrift klein, „+“ winzig.
- App-Symbol bei 48 px schwach, der Rahmen kollidiert mit der Android-Maske.
- Katze: Arm wie eine Röhre, geringer Kontrast zum Grund, Profil statt Dreiviertelansicht.
- Sehr helle Leuchttöne, die bei Rotschwäche zusammenfallen.
- Feine Goldlinien bei Handgröße, Schrift nicht in die SVGs eingebunden.

**Konkrete Verbesserungen**
1. **Mehr Kartenfarbe:**
   - Bogenfenster in voller Kartenfarbe statt Pastell, oder ein farbiger Rand bzw. ein breiter Farbstreifen am Kartenrand.
   - Ziel: Die Farbe ist auf dem Ablagestapel aus einem Meter Abstand klar.
2. **Index-Banner breiter:** bis an die Streifengrenze, also rechte Kante bei etwa 150 statt 132 von 560 Einheiten (22 dp bei 80 dp Kartenbreite). Werte größer, „+“ in voller Strichstärke, Joker-Banner mit klarer Pfote ohne kleine Rauten.
3. **App-Symbol neu:**
   - Ohne eingebauten Rahmen.
   - Kopf mit Pfote groß vor einer hellen Tag-Nacht-Scheibe.
   - Als adaptive Ebenen (Vordergrund in der sicheren Zone).
4. **Katze verfeinern:**
   - Dreiviertelansicht wie in der Referenz.
   - Arm mit Ellbogen und Pfote mit erkennbaren Zehen.
   - Helleres Halo hinter dem Kopf für mehr Kontrast.
   - Sprechblase seitlich absetzen.
5. **Leuchttöne in die Helligkeitsstaffel bringen** wie bei A.
6. **Für Godot und Handgröße:**
   - Linien mindestens etwa 4 Einheiten stark.
   - Das Farbwort im Titelband abschaltbar oder weglassen (wegen Übersetzung).
   - Schrift per Datei mitliefern.

## Richtung C „Geometrisch & kräftig“

**Stärken**
- Beste Lesbarkeit im Fächer, volle Farbe.
- Am einfachsten in Godot und im Lite-Client umzusetzen.
- Klare Markenwirkung: Wortmarke, Farbband, der i-Punkt als Tag-Nacht-Scheibe.
- Gutes App-Symbol durch die geteilte Fläche.
- Gründliche Selbstprüfung: Streifentest, Simulation, Graustufen.
- Dunkle Seite mit Mondsichel und Leuchtrahmen attraktiv.

**Schwächen**
- Index der dunklen Seite in fast gleich hellen Leuchttönen: Pink und Türkis sind bei Rotschwäche nur noch an der Form zu unterscheiden.
- Heller Wünscher aus vier Farbvierteln am nächsten am bekannten Vorbild.
- Helle Seite wirkt wenig erwachsen, eher wie ein Familienkartenspiel.
- Katze plump: Schulterbeule, massiger Unterkörper, kaum Blick nach oben.
- Farbjagd-Symbol (Stapel mit „?“) wenig sprechend.

**Konkrete Verbesserungen**
1. **Index der dunklen Seite** in Tönen der Helligkeitsstaffel. Zum Beispiel die Neontöne von A (`#FFB3DC`, `#0B97A3`, `#FF7F14`, `#5E3BD8`) mit hellem Kern bei Lila. Nachrechnen, ob in jeder Simulation 0,15 erreicht werden.
2. **Hellen Wünscher umbauen:** Papiergrund oder Kartenfarbe mit Pfote, die Zehen in den vier Farben (wie B), keine Farbviertel.
3. **Mehr Wertigkeit auf der hellen Seite:** feine Innenlinie im Papierrand, Horizontstreifen feiner, dezente Papierstruktur als Shader.
4. **Katze:**
   - Schulter glätten, Unterkörper schmaler.
   - Kopf deutlich in den Nacken legen, Pupillen oben.
   - Pfote mit Ellbogen von der Seite an den Maulwinkel.
5. **App-Symbol** für kleine Größen nur mit Kopf und Pfote.
6. **Farbjagd:** sprechenderes Symbol, z. B. Pfote, die einen Stapel aufdeckt, oder Auge mit vier Farben. „Alle aussetzen“ im Index ohne feinen Punktring.

## Gut kombinierbare Elemente

| Element | aus | passt zu |
|---|---|---|
| Papierlasche als Index-Feld, Sonne bzw. Mond über gestreiftem Meer | A | Grundlage der Karten |
| Neontöne in der Helligkeitsstaffel | A | allen dunklen Seiten (behebt die Schwächen von B und C) |
| Logo-Bildteilung Papier/Nacht, Schriftzug wechselt die Seite | A | jeder Katze |
| Erwachsene Smokingkatze mit Blick nach oben, Gold- und Violettlicht, Sonne-Mond-Medaillon | B | Logo von A (dann in Dreiviertelansicht) |
| Feine Goldlinie im Rand, Mondphasen, Schlussstein mit Farbsymbol | B | Karten von A als „erwachsene“ Veredelung, sparsam |
| Pfote mit Zehen in den vier Farben als Joker | B (auch A) | allen Richtungen, ersetzt die Farbviertel von C |
| Sanduhr (Aussetzen), Katzenauge (Farbjagd) | B | A und C als ruhigere Aktionsmotive |
| Kräftige, große Indexziffern, kompaktes „+“ | C | Papierlasche von A |
| Flache Bauweise, Effekte erst in Godot | C | allen (Korn und Glühen als Shader) |
| App-Symbol mit hälftig geteiltem Tag/Nacht-Grund, i-Punkt als Tag-Nacht-Scheibe | C | Logo und Symbol jeder Richtung |
| Streifentest und Farbprüfung als festes Werkzeug | C, dieser Vergleich | weitere Entwurfsrunden |

## Empfehlung

Die Wahl trifft der Nutzer. Mein Vorschlag:

1. **Karten auf Basis von A.** A ist funktional der stärkste Entwurf: Index, Farbe auf einen Blick und Farbsehschwäche. Mit der Papierlasche hat A außerdem eine Form, die nur diesem Spiel gehört. Erwachsener wird A durch:
   - kräftigere Indexziffern nach C,
   - eine feine Goldlinie im Rand nach B,
   - ruhigere Aktionsmotive (Silhouetten statt Kulleraugen, Sanduhr bzw. Katzenauge nach B),
   - einen beruhigten hellen Wünscher.
2. **Logo-Katze nach B,** aber in Dreiviertelansicht wie in der Referenz und mit angewinkeltem Arm. Dazu die Bildteilung und der Schriftzug von A. Für eine hochwertige Fassung den Bild-Prompt aus B (Variante ohne Schrift, Referenzbild als Posenvorlage) nutzen und das Ergebnis als Vorlage nachzeichnen.
3. **App-Symbol** nur mit Kopf und Pfote vor dem geteilten Tag/Nacht-Grund nach C. Ohne Rahmen und als adaptive Ebenen.
4. **Alternative:** Wer den edlen Gesamteindruck über alles stellt, wählt B. Dann sind Pflicht:
   - mehr Kartenfarbe auf der hellen Seite,
   - breitere Banner mit größerer Schrift,
   - ein neues App-Symbol.

C empfehle ich als Ganzes nicht. Es ist ein gutes Werkzeug- und Markensystem, aber auf der hellen Seite am wenigsten erwachsen und am nächsten am Vorbild. Seine Stärken (Index, flache Bauweise, App-Symbol) lassen sich gut übernehmen.

## Offene Punkte für alle Richtungen

- **Offline-Schriften:** Laut Projektkontext dürfen keine Webfonts von außen geladen werden. Die `@import`-Zeilen zu fonts.googleapis.com in den SVGs (A, C) und Vorschauen sind nur für die Entwürfe gedacht. Für App und Lite-Client die Schriftdateien mit OFL-Lizenztext mitliefern. Werte und Index in Pfade umwandeln oder zur Laufzeit setzen. Ein `<img>` mit SVG lädt im Browser keine Schriften.
- **Verdeckte Gegnerhand:** Eine neutrale Darstellung für die Regel „Rückseiten verdeckt (unter dem Tisch)“ hat noch keiner entworfen. Ebenso fehlen die Großansicht zum Durchblättern fremder Rückseiten und das kurze Umdrehen der eigenen Hand.
- **Vollständiger Satz:** Für alle 112 Karten fehlt die Liste, welche helle Seite zu welcher dunklen gehört.
- **Effekte:** Joker-Strahlen und der Übergang beim Flip sind nur über die Ebenen vorbereitet. Ein kurzer Bewegungsentwurf (z. B. als HTML-Animation) wäre der nächste Prüfstein für die gewählte Richtung.
- **Gerätetest:** Lila auf Nacht und die feinen Linien (vor allem bei B) auf einem echten Display prüfen.

## Dateien dieses Vergleichs

- `VERGLEICH.md`: diese Bewertung.
- `index.html`, `uebersicht.png`: Übersicht mit Logo, Hand, Kartenbogen, Streifentest, App-Symbol und Farbsehschwäche.
- `farbsehschwaeche.html`, `farbsehschwaeche.png`: Handansicht und Streifentest jeder Richtung unter Protanopie, Deuteranopie, Tritanopie und ohne Farbe, dazu die OKLab-Tabelle.
- `_pruefung/kartenbogen_?.png`, `_pruefung/streifen_?.png`: Prüfbilder aus den Karten-SVGs.
- `_pruefung/pruefbilder.sh`: erzeugt die Prüfbilder neu.
