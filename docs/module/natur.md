# Modul „Natur-Überraschungen“ (geplant Beta 1.6.11)

Stand 16.10.2026, Entwurf (noch ohne Gegenprüfung). Nutzerwunsch vom 16.10.2026: „alle, und auch im Browser“. Gemeint sind zufällige, seltene Bild-Ereignisse ohne Ton, wie heute Schmetterling und Sternschnuppe (`fun_fx.gd`), jetzt auch im Lite. Ideen des Nutzers: Marienkäfer, Glühwürmchen, Eule, dazu die Reaktionen beim Antippen von Marienkäfer, Glühwürmchen und Eule.

Kurz:
- 23 neue Ereignisse (11 tags, 12 nachts). Schmetterling und Sternschnuppe kommen als „Bestand“ in denselben Takt, macht 25. Ab Beta 1.6.15 vier weitere (Hoppelhase, Strand mit Palme, Feuerwerk, Astronaut am Mond), macht 29; das UFO ist nicht mehr scheu (Abschnitt 13).
- Ein gemeinsamer Planer je Gerät mit einer gemeinsamen Datentabelle (App und Lite gleich). Es läuft nie mehr als ein Ereignis, im Schnitt etwa alle 3 Minuten eins.
- Drei Ebenen. Fast alles liegt **unter** den Spielelementen. Nur Biene und UFO liegen über Hand bzw. Stapel, und nur kurz, durchscheinend und nie im eigenen Zug.
- Kein Ton, kein Text, nichts übers Netz, keine fremden Grafiken.
- Kleine Eingriffe: `table_view.gd` etwa 14 Zeilen, `fun_fx.gd` etwa 8 Zeilen, `app.js` 2 Zeilen, `index.html` 3 Zeilen. `tisch.js`, `style.css`, `tease_*.gd` und `necken.js` bleiben unberührt.

## 1. Grundsätze

1. **Nur lokal:** Jedes Gerät würfelt selbst. Es geht nichts übers Netz, nichts in Sicht, Speicherstand, Statistik oder Protokoll.
2. **Selten und einzeln:** Es läuft höchstens ein Natur-Ereignis. Keins läuft gleichzeitig mit der Mau-Katze, dem Bestand-Himmel oder einem Necken-Effekt (Abschnitt 4).
3. **Spiel geht vor:** Ein Ereignis startet nur in Ruhe. Bei wichtigen Momenten (eigener Zug, Mau, Erwischt-Fenster, Rundenende) geht es schnell ab (Abschnitt 4.5).
4. **Nichts verdecken:** Hinweisleiste, Mau, „Erwischt!“, Knöpfe, Farbwahl und Dialoge liegen immer über allen Natur-Ebenen. Hand und Stapel deckt nur je ein Ereignis kurz und durchscheinend (Abschnitt 2.3).
5. **Tippen verschluckt nichts:** Ein Tier reagiert nur auf einen Tipp, den kein Spielelement nimmt. Scheue Tiere über Hand, Stapel oder Ablage reagieren nebenbei, der Tipp wirkt normal weiter (Abschnitt 4.6).
6. **Kein Ton, keine Vibration, kein Text.** Einzige Ausnahme ist das gezeichnete „z“ am schlafenden Mond. Es gibt keine .po-Einträge.
7. **Eigene Zeichnung:** App mit Godot-Zeichenbefehlen (Polygone, Bögen, Linien, eigene Teilchen-Listen, Glühen über `TableEffects.glow_texture()`/`additive()`). Lite mit Inline-SVG und CSS. Keine Bilddateien, keine fremden Grafiken.

## 2. Ebenen, Orte, Schutzflächen

### 2.1 Ebenen

| Ebene | App | Lite | Liegt über | Liegt unter |
|---|---|---|---|---|
| `hinten` (Himmel) | `NaturHinten` (Node2D) direkt nach dem Hintergrund (`_bg`), wie `FunHimmel` | `#natur-hinten.natur-ebene` als erstes Kind der `.buehne` (z-index auto) | Hintergrund, Sonne, Mond | allem anderen |
| `mitte` (Tisch) | `NaturMitte` in `_world` direkt nach `_ring` (Index 1) | `#natur-mitte` direkt nach `.richtung` (z-index auto, DOM-Reihenfolge) | Richtungs-Plattform | Plätzen, Stapel, Ablage, Farbring, Farbanzeige, Stapelzahl, Hand |
| `vorn` (über Karten) | `NaturVorn` in `_world` direkt nach `hand_layer`, vor `fx` | `#natur-vorn`, z-index 33 | Hand (Lite 30/31), Stapel, Ablage | Hinweisleiste, Knöpfen, Mau, Erwischt (App `_ui`, `_catch_layer`, Overlays; Lite `.gegner-box` 35, `.leiste` 50, Knöpfe 60, `.flug` 300) |

Lite: Alle drei Ebenen haben `pointer-events: none` und `aria-hidden="true"`. `natur.js` legt sie selbst an, sobald `app.tisch` existiert. Deshalb sind keine Änderungen an `tisch.js`/`style.css` nötig. Wichtig: `mitte` braucht **z-index auto**. Ein positiver z-index läge über `.farbanzeige` und `.stapelzahl`, die selbst auto sind.

### 2.2 Orte (Anker)

Koordinaten in Tisch- bzw. Bühnenpixeln (Höhe 720). W×H = Tischgröße (App `table.size`, Lite `tisch.W`×`tisch.H`), C = Tischmitte (App `TableLayout.table_center`, Lite `tisch.g.cx/cy`).

| Ort | Festlegung |
|---|---|
| `himmel` | ganze Breite, y 0,04–0,30 H. Ein- und Austritt außerhalb des Bilds. |
| `himmel_oben` | y 0,02–0,20 H |
| `himmel_fern` | y 0,06–0,18 H |
| `himmel_frei` | Kasten 240×160 in `himmel_oben`. Kandidaten x-Mitte 0,18/0,32/0,50/0,66 W. Gewählt wird der mit der kleinsten Überdeckung durch Platzköpfe, mindestens 200 px vom Mond entfernt und nicht über den Knöpfen oben links (App 0–280 × 0–110, Lite Menü-Knopf) und oben rechts (Lite Ton-Knopf). |
| `himmel_bogen` | Mittelpunkt (C.x, C.y + 40), Innenradius 0,46 W |
| `sonne` | App wie im Shader (`table_background.gdshader`: `size.x * 0.07, size.y * (0.03 + 1.05 * t)`), also bei Tag (0,07 W; 0,03 H), Radius 64. Lite: Mitte von `.himmel .sonne` (`getBoundingClientRect` → `tisch.zuBuehne`). |
| `mond` | App wie im Shader (`size.x * 0.94, size.y * (1.12 - 1.04 * t)`), nachts (0,94 W; 0,08 H), Sichel r 40, Ausschnitt bei +17/−12. Lite: Rechteck von `.himmel .mond` (um −24° gedreht). |
| `band(°)` | Mitte des Plattformbands, 0° = rechts, im Uhrzeigersinn, 90° = vorn. App: `C + _ring.point_at(°)`. Lite: Ellipse um (g.cx, g.cy + 6) mit rx = max(372·fx, 326) + 33·min(fx, 1), ry = 159, fx = min(330, 0,21 W)/330 (Näherung von `plattform()`, im Kontrollbild prüfen). |
| `band_hinten` | 240–300°, die Stelle mit dem größten Abstand zu allen Platzköpfen |
| `band_schulter` | 200–215° oder 325–340°, die freiere Seite |
| `band_vorn_seite` | 115–160° oder 20–65°. 66–114° liegt unter der Hinweisleiste und ist gesperrt. |
| `band_zum_platz` | Winkel C → Kopf des Trödlers, 66–114° auf 65° bzw. 115° geklemmt. Eigener Platz: 115° (Seite des eigenen Namensschilds). |
| `tisch_quer` | Streifen über dem hinteren Bandrand: y von C.y − ring.y − 60 bis C.y − ring.y + 20 (App `TableLayout.ring_radii(sz).y`, Lite 159) |
| `tisch_rund` | Ring um C mit 1,05–1,45 × Bandradien, nur y ≤ Hinweisleiste − 40 |
| `handkarte` | mittlere sichtbare Handkarte. App: `hand.get_order()`, `hand.card_global_position(id)`, `hand.cards_rect()`. Lite: `tisch.hand.position(id)` → {x, y, w, rot}. |
| `stapel_oben` | Schwebepunkt (Stapel.x, Stapeloberkante − 62) |
| `ablage_ring` | Ablage-Mitte, R = 116 (App `ColorRingView.R`), Lite Radius von `.farbring` |
| `aufsteigend` | Start (x, C.y) mit x in 0,25–0,40 W oder 0,60–0,75 W (der Spalt mit mehr Abstand zu Plätzen), Ziel oberhalb des Bilds |
| `ecke_unten_rechts` | (1.6.15, Strand) Ecke (W, H) und das Rechteck des Mau-Knopfs (`mau`; App `TableView.mau_button`, Lite `#mau` = `.mau-knopf`, rechts 46, unten 40, 150 × 150). App `{pos, mau}`, Lite `{x, y, mau}`. Der Strand liegt in der Ebene `hinten`, Hand und Mau-Knopf bleiben darüber. |

Bei neuer Tischgröße (App `_layout`, Lite neue `W`/`H`/`s`) endet das laufende Ereignis sofort. Orte werden nur beim Start berechnet.

### 2.3 Schutzflächen

Schutzflächen sind: Hand (`cards_rect`), Ziehstapel (+12 px), Ablage mit Farbring (R + 8), Plätze (Kopf und Fächer), eigenes Namensschild, Hinweisleiste, Mau, Sortieren/Rückseiten/Aktionsknöpfe, Erwischt-Buzzer, Glücksspiel-Automat und Einsatz (wenn sichtbar), Farbanzeige der Wunschfarbe (+8 px), Stapelzahl (+4 px), Knöpfe oben links (App `TableScreen`, Lite Menü) und oben rechts (Lite Ton).

- App: `NatureFx.obstacles()` liest sie selbst aus der `TableView` (`table.get(...)`/`call(...)` wie `FunFx`, `OpponentSeat.avatar_global/header_width/header_height/fan_global_center`). `table_view.gd` bekommt dafür keine neue Funktion.
- Lite: `natur.js` misst die Elemente (`#stapel`, `#ablage`, `.gg`, `#hand-zone`/Handkarten, `.leiste`, `.pill`, `#mau`, `.menue-knopf`, `.ton-knopf`, `#automat`, `#einsatz`, `.erwischen`, `.farbanzeige`, `.stapelzahl`) per `getBoundingClientRect` → `zuBuehne`.

**Was darf was decken** (`deckt` in der Tabelle, Prüfung in Abschnitt 8):
- `hinten`/`mitte` liegen unter allem und decken nichts. Ein Ort muss aber so gewählt sein, dass das Tier in der Hauptphase zu mindestens 60 % der Zeit sichtbar ist.
- `vorn`:
  - **Biene:** Hand ≤ 2 s, ≤ 26 px, nie im linken oberen Viertel einer Karte (Eckindex, AGENTS 8).
  - **UFO:** Ziehstapel ≤ 3 s, nur mit dem durchscheinenden Lichtkegel (Deckkraft ≤ 0,22), der Körper schwebt darüber. Ab 1.6.15 nicht mehr scheu (siehe 3.3 Nr. 18).
  - Beide **nur außerhalb des eigenen Zugs**.

## 3. Die Ereignisse

Größen in Pixeln bei Höhe 720. „Fremder Zug“ heißt: startet nur, wenn man nicht selbst dran ist. „Scheu“ heißt: geht bei Berührung in der Nähe sofort ab, ohne den Tipp zu nehmen. „Reduziert“ heißt: Verhalten bei „Effekte reduziert“ (Abschnitt 5.1).

### 3.1 Übersicht

| # | id | Seite | Auslöser (Gewicht) | Ebene · Ort | Dauer s | Antippen | Reduziert |
|---|---|---|---|---|---|---|---|
| 1 | `marienkaefer` | Tag | Zufall 3 | mitte · `band_vorn_seite` | 9–12 | fliegt weg (Nutzer) | aus |
| 2 | `biene` | Tag | Zufall 2, fremder Zug | vorn · Acht, dann `handkarte` | 7–9 | scheu | aus |
| 3 | `libelle` | Tag | Zufall 2 | mitte · `tisch_quer` | 6–8 | flitzt weg | aus |
| 4 | `pusteblume` | Tag | Zufall 2 | hinten · `himmel` | 12–15 | Windstoß | aus |
| 5 | `papierflieger` | Tag | Zufall 2 | hinten · `himmel` | 6–7 | Looping | aus |
| 6 | `seifenblasen` | Tag | Zufall 2 | mitte · `tisch_quer` → Himmel | 8–11 | Blase platzt | aus |
| 7 | `spatz` | Tag | Zufall 2 | mitte · `band_hinten` | 7–10 | fliegt weg | aus |
| 8 | `wolke` | Tag | Zufall 1 | hinten · `sonne` | 12–16 | – | ruhig |
| 9 | `regenbogen` | Tag | nach Flip zu Tag (Chance 0,4, 1 je Runde) | hinten · `himmel_bogen` | 7 | – | ruhig |
| 10 | `heissluftballon` | Tag | Zufall 1, 1 je Partie | hinten · `himmel_fern` | 18–22 | steigt auf | aus |
| 11 | `schnecke` | Tag | Trödeln ≥ 35 s (Chance 0,35) | mitte · `band_zum_platz` | bis Zugende, ≤ 40 | zieht sich ein | aus |
| B1 | `schmetterling` | Tag | Zufall 3 (Bestand) | hinten · `himmel` | 9 | – | aus |
| 24 | `hoppelhase` | Tag | Zufall 2 (1.6.15) | mitte · `band_vorn_seite` | 9–12 | Schreck-Sprung, schnell davon | aus |
| 25 | `strand` | Tag | Zufall 1, 1 je Partie (1.6.15) | hinten · `ecke_unten_rechts` | 7–8 | Palme schüttelt sich, Kokosnuss fällt | aus |
| 12 | `gluehwuermchen` | Nacht | Zufall 3, nach Flip 3 | mitte · `tisch_rund` | 12–15 | stieben auseinander (Nutzer) | aus |
| 13 | `eule` | Nacht | Zufall 3, nach Flip 1 | mitte · `band_schulter` | 12–16 | Kopf drehen, blinzeln (Nutzer) | aus |
| 14 | `fledermaus` | Nacht | Zufall 2, nach Flip 2 | hinten · `himmel` | 4–6 | – | aus |
| 15 | `mond_muetze` | Nacht | Zufall 1, 1 je Partie | hinten · `mond` | 10–12 | wacht kurz auf | ruhig |
| 16 | `polarlicht` | Nacht | Zufall 1, 1 je Partie | hinten · `himmel_oben` | 12–14 | – | ruhig |
| 17 | `sternbild` | Nacht | Zufall 1, 1 je Partie | hinten · `himmel_frei` | 9–10 | funkelt | ruhig |
| 18 | `ufo` | Nacht | Zufall 1, 1 je Partie, fremder Zug | vorn · `stapel_oben` | 7–8 (bis 1.6.14: 6–7) | 1. und 2. Tipp: weicht aus, 3. Tipp: saust davon (bis 1.6.14: sofort davon; scheu) | aus |
| 19 | `satellit` | Nacht | Zufall 2 | hinten · `himmel_oben` | 9–11 | – | aus |
| 20 | `motte` | Nacht | Zufall 2, fremder Zug | mitte · `ablage_ring` | 6–8 | scheu | aus |
| 21 | `igel` | Nacht | Zufall 2 | mitte · `band_vorn_seite` | 10–14 | rollt sich ein | aus |
| 22 | `komet` | Nacht | Zufall 1 | hinten · `himmel_oben` | 14–16 | – | aus |
| 23 | `lampion` | Nacht | Zufall 2 | hinten · `aufsteigend` | 11–13 | glüht auf | aus |
| B2 | `sternschnuppe` | Nacht | Zufall 3 (Bestand) | hinten · `himmel` | 1,2 | – | aus |
| 26 | `feuerwerk` | Nacht | Zufall 1, 1 je Partie (1.6.15) | hinten · `himmel` | 5–6 | Knall an der Tippstelle (höchstens 2) | aus |
| 27 | `astronaut` | Nacht | Zufall 1, 1 je Partie (1.6.15) | hinten · `mond` | 9–12 | langsamer Salto, winkt | aus |

Bestand: In der App zeichnet weiter `FunFx.SkyNode` (Abschnitt 7.1), im Lite kommen Schmetterling und Sternschnuppe neu hinzu (gleiche Bahn wie `SkyNode.launch`).

### 3.2 Tag

**1 Marienkäfer** (Idee des Nutzers)
- **Bewegung:**
  - Anflug 1,2 s im Bogen vom oberen Rand derselben Seite, Flügel offen.
  - Landung, die Deckflügel klappen zu (0,2 s).
  - Krabbelt 6–9 s mit 12 px/s am Band entlang zur Bandmitte. Alle 1,5–2,5 s hält er 0,4–0,8 s an und dreht sich leicht (±15°).
  - Abflug 1 s nach oben außen. Größe 22×18.
- **Antippen:** Die Deckflügel springen auf, er fliegt steil davon (0,8 s).
- **App:**
  - Körper als Halbellipse #E8352E mit INK-Kontur, Mittelnaht, 6 schwarze Punkte.
  - Kopf schwarz mit 2 weißen Augenpunkten, 2 Fühler, 6 trippelnde Beinchen.
  - Im Flug: Deckflügel um ±50° gedreht, Hautflügel 2 Ellipsen Weiß α 0,45, Schlag über y-Skalierung 18 Hz.
- **Lite:** SVG-Gruppe. Die Deckflügel drehen sich über die Klasse `.offen`, die Hautflügel flattern per CSS scaleY, die Bahn läuft per JS.

**2 Biene** (startet nur im fremden Zug)
- **Bewegung:**
  - Einflug von der Seite (1,2 s).
  - 1–2 Achten (Lemniskate 0,36 W × 70 px, je 2,2 s) mit der Mitte bei (0,5 W, H − 300).
  - Sinkflug auf die mittlere sichtbare Handkarte. Landepunkt: Kartenoberkante + 22 px, rechter Rand − 26 px, im Kartensystem gedreht. Nie im linken oberen Viertel.
  - Sitzt 1,5 s, Flügel zittern, Hinterleib wippt. Abflug schräg nach oben (1 s). Ohne Handkarte entfällt die Landung.
  - Größe 20×14, Spannweite 26.
- **Scheu:** Sie geht sofort ab (0,4 s Zickzack nach oben) bei:
  - jeder Berührung der Hand oder im Umkreis von 130 px,
  - Beginn des eigenen Zugs,
  - Karte verlässt die Hand, Sortieren, `swap_hands`,
  - Großansicht oder Auswahl.
  Der Tipp wirkt normal auf die Hand.
- **App:** Körper Ellipse #FFC934 mit 3 INK-Bändern, Stachel, Kopf INK. Flügel 2 Ellipsen Weiß α 0,55 mit Kontur, Schlag 22 Hz. Im Flug ein feiner Bewegungsstrich (α 0,3).
- **Lite:** SVG, Flügel per CSS scaleY (45 ms), Bahn und Landepunkt aus `hand.position(id)`.

**3 Libelle**
- **Bewegung:**
  - 5–7 Abschnitte, jeweils Sprint (0,25 s, bis 160 px, gerade, bremst ab) und Schweben (0,5–1 s, Zittern ±1,5 px).
  - Insgesamt quer von einer Seite zur anderen, der Körper zeigt in Flugrichtung.
  - Größe 46 lang, Spannweite 40.
- **Antippen:** Drei schnelle Zickzack-Sprints (je 0,12 s) hinaus.
- **App:** Hinterleib als Linienzug (8 Glieder, 4→2 px) #19C6D4 mit dunklen Ringen, Brust, Kopf mit 2 großen Augen. 4 Flügel als schmale Ellipsen 32×7, Weiß α 0,35, schimmern zwischen Türkis und Violett, Flimmern über Deckkraft.
- **Lite:** SVG, Flimmern per CSS opacity.

**4 Pusteblumen-Samen**
- **Bewegung:**
  - 7–10 Schirmchen starten zeitversetzt (0–3 s) an einem Rand und treiben quer (40–70 px/s).
  - Sie steigen und sinken sanft (Sinus 12–25 px, 3–5 s), pendeln ±12° und drehen sich langsam.
  - Größe: Schirm Ø 16–22, Stiel 10.
- **Antippen:** Windstoß. Samen im Umkreis von 160 px fliegen vom Tipp weg (Tempo ×4 für 1 s, Drehung).
- **App:** je Samen 10 Strahlen als Linien (1 px, INK α 0,45) mit cremefarbenen Spitzen, Stiel INK α 0,6, Korn braun. Auf Papier gut sichtbar, nicht weiß auf weiß.
- **Lite:** `<symbol>` und je Samen ein `<use>`.

**5 Papierflieger**
- **Bewegung:** Gleitet in einer flachen Welle (eine Periode, 30 px) quer und sinkt dabei 40 px. Die Nase folgt der Bahn, die Flügelbreite schwankt leicht (Rollen). Größe 54×22.
- **Antippen:** Ein Looping (Ø 90, 1 s), dann geht es weiter. Höchstens einmal.
- **App:** 3 Dreiecke (Creme, PAPER_D, Kiel dunkler), INK-Kontur 1,5 px, Falzlinie („Papier & Neon“).
- **Lite:** SVG-Polygone.

**6 Seifenblasen**
- **Bewegung:**
  - 5–8 Blasen (Ø 18–44) starten zeitversetzt (0–4 s) an einer Seite im Streifen `tisch_quer`.
  - Sie treiben quer (30–50 px/s) und steigen langsam (10–20 px/s), wackeln seitlich, wabern (Ø ±4 %) und schillern.
  - Jede platzt nach 3–7 s oder am oberen Rand von selbst.
- **Antippen:** Die getroffene Blase platzt: Ring dehnt sich (0,2 s), 6 Tröpfchen.
- **App:** 2 Randbögen (Türkis/Pink, α 0,6→0,3), Glanzpunkt, Füllung Weiß α 0,06.
- **Lite:** `<div>` mit `border-radius: 50%`, radial-gradient und farbigem `inset`-Schatten (statisch, nicht animiert), Glanz per `::after`.

**7 Spatz**
- **Bewegung:**
  - Anflug von oben im Bogen (1 s), Landung.
  - 2–3 Hüpfer (je 0,25 s, 12–18 px weit, 8 px hoch), Picken (Kopf nickt 3×), Umdrehen.
  - Abflug nach oben (0,8 s). Größe 34×26.
- **Antippen:** Flattert sofort weg, zwei Federchen fallen (0,6 s).
- **App:** Körper als Tropfen-Polygon #A0703C, Brust #E8D2B0, Flügel #6E4A26 mit 2 Streifen, Kappe grau-braun, Schnabel INK, Auge mit Glanz. Flügelschlag als Drehung ±40° mit 12 Hz.
- **Lite:** SVG, Flügel per CSS rotate.

**8 Wolke vor der Sonne**
- **Bewegung:**
  - Zieht mit 25–35 px/s von Sonne − 260 nach Sonne + 320, auf Sonnenhöhe + 10–25. Sie deckt die Sonne etwa 4–6 s.
  - Solange sie die Sonne deckt, liegt ein Hauch Schatten (INK, α ≤ 0,05) über dem **Hintergrund**. Weil die Ebene `hinten` ist, bleiben die Karten hell.
  - Größe 220×90.
- **App:** 5 überlappende Kreise Weiß, Unterseite PAPER_D α 0,7, weicher Rand über eine Glüh-Textur (α 0,25). Schatten mit `draw_rect`.
- **Lite:** SVG-Kreise, Schatten als `<div>` über `#natur-hinten`.
- **Ruhig:** blendet vor der Sonne ein (2 s), steht 6 s, blendet aus (2 s), Schatten α 0,03.

**9 Regenbogen nach Flip**
- **Auslöser:**
  - Flip zur Tagseite, Chance 0,4, höchstens einmal je Runde.
  - Start 1,5 s nach Ende der Flip-Animation, sobald Ruhe ist.
  - Spätestens 6 s nach dem Flip, sonst entfällt er.
  - Damit liegt er nie über dem Banner „Tag!“.
- **Bewegung:** Der Bogen wächst von links nach rechts (180°→360°, 1,5 s), steht 3,5 s und blendet 2 s aus. Er liegt hinter allem und ist nur im freien Himmel zu sehen.
- **App:** 6 Bänder als `draw_arc` (#FF4D57, #FF8A1F, #FFDD33, #4FD36E, #4C7DFF, #8B6BFF), je 9 px breit, α 0,32, mit einem weichen Saum innen und außen (α 0,08).
- **Lite:** 6 SVG-Bögen, Wachsen über `stroke-dashoffset`.
- **Ruhig:** nur Deckkraft (1,5 s ein, 3,5 s stehen, 2 s aus).

**10 Heißluftballon** (höchstens einmal je Partie)
- **Bewegung:** Schwebt langsam quer (70 px/s) und wippt (±4 px, 4 s). Größe 46×70.
- **Antippen:** Der Brenner flammt auf (0,4 s), der Ballon steigt schräg davon.
- **App:** Hülle als Tropfen mit 5 Bahnen (Rot, Gelb, Grün, Blau, Creme), INK-Kontur, Korb, 4 Seile, Flamme mit Glühen.
- **Lite:** SVG.

**11 Schnecke bei Trödlern**
- **Auslöser:**
  - Der Spieler am Zug (auch man selbst) hat seit 35 s nichts getan. Die Uhr läuft wie bei der Mau-Katze: Sie beginnt neu, wenn sich Zug, Ablage oder Stapelzahl ändern.
  - Chance 0,35, höchstens einmal je Spieler und Partie.
  - Nicht, wenn die Mau-Katze in diesem Zug kam oder gerade läuft.
  - Nicht, solange am Platz ein Necken-Effekt läuft. Dann wird es jede Sekunde neu versucht, solange der Zug dauert.
- **Bewegung:**
  - Kriecht unter dem Bandrand hervor (1 s).
  - Kriecht dann mit 6 px/s am Band entlang Richtung Platz. Die Fühler wippen, sie hinterlässt eine glänzende Spur (verblasst nach 4 s).
  - Bei Zugende zieht sie sich ins Haus (0,4 s) und blendet aus (0,5 s). Höchstens 40 s. Größe 36×24.
- **Antippen:** Zieht sich ins Haus, wartet 2 s, kommt wieder heraus.
- **App:** Haus als Spirale (Linienzug, 3 Windungen) auf #C9803E, Körper #B9C7A0 mit Fußwellen, 2 Fühler mit Kugeln, Spur Weiß α 0,25.
- **Lite:** SVG.

**24 Hoppelhase** (1.6.15, Nutzerwunsch: „Ein Hoppelhase hüpft durch das Bild als zufällige Aktion bei Tag“)
- **Bewegung:**
  - Hüpft von außen auf den Plattformrand (quer 0,62) einer Seite (Startseite aus `band_vorn_seite`, sonst die freiere) und vorn herum zur anderen Seite (Start 158–170° bzw. 10–22°, Ziel spiegelbildlich), dort zwei Hüpfer hinaus und Ausblenden.
  - Jeder Hüpfer 0,42 s: Ducken (Stauchen y 0,8), Flug mit Strecken (y bis 1,16) und Bogen (Höhe 0,42 × Hüpfweite), Landen mit Stauchen; Hüpfweite so, dass der Weg in die Tabellendauer passt (App 34–72 px, Lite 40–84).
  - Nach etwa einem und zwei Dritteln eine Pause (1–1,5 s) an einer gut sichtbaren Stelle: einmal Männchen mit Ohrenzucken, einmal nur Ohrenzucken; das Näschen schnuppert.
  - Meidet Plätze, Knöpfe, Hinweisleiste und (Lite) die Reaktionsknöpfe.
- **Antippen:** Großer Schreck-Sprung (0,55 s, 66 px hoch, Ohren steil, Augen groß), danach drei schnelle, weite Hüpfer (je 0,3 s) in Laufrichtung, Ausblenden.
- **App:** Seitenansicht (Ursprung an den Füßen) mit Fell #D3AE87/#B38B64, Bauch und Schnäuzchen #F8EDDC, Wattebausch-Schwänzchen, großer Kopf mit Bäckchen, rosa Innenohr, Näschen #EE7499, INK-Kontur; Schatten wie beim Spatz.
- **Lite:** SVG, Stauchen und Strecken über `scale`, Ohren und Auge über eigene Gruppen.

**25 Strand mit Palme** (1.6.15, Nutzerwunsch: „In der unteren rechten Ecke kommt mit einer Welle für ein paar Sekunden ein Strand ins Bild und eine Palme wächst“; höchstens einmal je Partie)
- **Ort:** `ecke_unten_rechts`, Ebene `hinten`: Hand und Mau-Knopf (rechts 46, unten 40, 150 × 150) liegen darüber, der Knopf bleibt sichtbar und antippbar. Strand = Viertel-Ellipse 410 × 245 um die Ecke (App × min(k, 1,15)), Meer bis zur halben Größe.
- **Ablauf (7–8 s):**
  - Eine Welle rollt aus der Ecke herein (1 s, bis 1,08), weicht bis zur Meereslinie zurück (bis 1,8 s) und lässt nassen Sand zurück, der in 1,6 s trocknet; kleine Wellen lecken am Ufer (Schaumkante mit Bläschen).
  - Die Palme wächst ab 1,7 s Stück für Stück (8 Stammstücke in 1 s), die 8 Wedel entfalten sich (ab 2,5 s), drei Kokosnüsse; sie wiegt sich leicht. Seestern und Muschel liegen im Sand.
  - Der Palmenfuß steht zwischen Hand (höchstens bis W − 270) und Mau-Knopf (ab W − 196), die Krone über dem Knopf.
  - 1,7 s vor Schluss spült eine große Welle (bis 1,18) alles weg: Die Palme kippt und verschwindet, dann weicht das Wasser ganz zurück.
- **Antippen** (nur die Palme; der Sand allein nimmt keinen Tipp): Die Palme schüttelt sich kräftig (abklingend), eine Kokosnuss fällt, hüpft einmal und rollt ein Stück.
- **App:** Sand #F3CC86 mit Papierkante und Schatten, Körnchen, Meer #2FBFD2/#86E6EF, Schaum Weiß, Stamm #B47D46 mit Ringen, Wedel #3DBB6A/#5FD486 mit Mittelrippe #227F44 (als Vierecke je Abschnitt gezeichnet, damit die Triangulierung nie scheitert).
- **Lite:** SVG mit Ursprung in der Ecke; Sand und Meer wachsen per `scale` um die Ecke (Kanten mit `vector-effect: non-scaling-stroke`), Stammstücke und Wedel über Transform-Attribute.

### 3.3 Nacht

**12 Glühwürmchen** (Idee des Nutzers)
- **Bewegung:**
  - 6–9 Leuchtpunkte blenden zeitversetzt ein (0–2 s).
  - Sie schweben auf weichen Bahnen (Summe zweier Sinus je Achse, 12–28 px/s) und leuchten unabhängig voneinander auf und ab (Periode 1,4–3 s, α 0,25–1).
  - Am Ende blenden sie aus (2 s). Kern 3 px, Schein Ø 26.
- **Antippen** (Nutzer: „stieben auseinander“): Trifft der Tipp näher als 60 px an ein Glühwürmchen, fliegen alle radial vom Tipp weg (180 px/s, 0,8 s) und verlöschen. Das Ereignis endet.
- **App:** je Punkt ein Glühen (`TableEffects.glow_texture()`, #D8FF6A, additiv) und ein hellgelber Kern.
- **Lite:** `<i>` mit radial-gradient und `mix-blend-mode: screen`, Funkeln per CSS-Deckkraft mit zufälliger Verzögerung.

**13 Eule** (Idee des Nutzers)
- **Bewegung:**
  - Gleitet lautlos herein (1,6 s, Flügel ausgebreitet), landet und faltet die Flügel (0,3 s).
  - Blinzelt alle 3–4 s (Lid 0,15 s). Dreht den Kopf langsam (0,6 s) zum Spieler am Zug, die Pupillen zeigen hin. Plustert sich einmal auf (×1,06).
  - Am Ende breitet sie die Flügel und gleitet davon (1,2 s).
  - Sitzend 44×56, Spannweite 110.
- **Antippen** (Nutzer): Dreht den Kopf fast ganz herum. Das ist gezeichnet: Die Gesichtszüge wandern zur Seite und schwingen mit Überschwinger zurück (0,9 s). Dazu blinzelt sie zweimal. Danach bleibt sie sitzen.
- **App:**
  - Körper als Tropfen #4A3B63 mit Lavendel-Kontur (`UiPalette.RING`, nachts sichtbar), Brust #7A6A92 mit V-Federn, Federohren.
  - Gesichtsscheiben #8C7BA6, Iris #FFB627, Pupille INK, Glanz.
  - Lider als Halbkreis in Gesichtsfarbe, Schnabel #E8C46A, Krallen.
- **Lite:** SVG-Gruppen (Kopf, Lider), CSS-Transforms.

**14 Fledermaus**
- **Bewegung:** Ruckartiges Zickzack quer über den oberen Himmel: 6–9 Abschnitte zu je 0,35–0,6 s, Richtungswechsel bis ±35°, einmal eine kurze Kehre. Flügelschlag 8 Hz, Spannweite 48.
- **App:** Silhouette als Polygon in `UiPalette.NIGHT` mit Kontur #8B6BFF (1,5 px), 2 pinke Augenpunkte. Der Flügelschlag verschiebt die Spitzen.
- **Lite:** SVG-Pfad mit zwei Flügelstellungen, umgeschaltet per CSS `steps()`.

**15 Mond mit Schlafmütze** (höchstens einmal je Partie)
- **Bewegung:**
  - Eine Zipfelmütze fällt auf die obere Sichelspitze (0,6 s, kleiner Abpraller). Der Mond schließt das Auge (Bogen auf der Sichel).
  - Der Zipfel mit Bommel pendelt (±12°, 2,4 s). Alle 2 s steigt ein „z“ (Creme α 0,8, wächst und verblasst in 1,6 s).
  - Am Ende pustet der Wind die Mütze weg (dreht sich nach oben rechts, 0,8 s), das Auge öffnet sich kurz. Mütze 60×46.
- **Antippen:** Der Mond öffnet das Auge (0,6 s), der Bommel hüpft, dann schläft er weiter.
- **App:** Mütze als Polygon (gebogener Zipfel aus Bezier-Punkten) #FF2FA8 mit 3 cremefarbenen Streifen, Krempe und Bommel Creme. Auge als Bogen INK α 0,6. Das „z“ über `UiFonts` (ein Zeichen, keine Übersetzung).
- **Lite:** SVG am Rechteck von `.himmel .mond`, die Drehung um −24° beachten. Die Mütze kann teilweise hinter dem Ton-Knopf liegen; dann sitzt sie auf der sichtbaren linken Seite (im Kontrollbild prüfen).
- **Ruhig:** Mütze und Auge blenden ein (1 s), stehen still und blenden aus. Keine „z“.

**16 Polarlicht** (höchstens einmal je Partie)
- **Bewegung:**
  - 3 Vorhänge (#4FFFB0, #19E0D4, #A855FF) im oberen Drittel blenden 3 s ein.
  - Sie wogen: Die Phase wandert mit 0,12 Hz, die Unterkante wellt sich ±14 px, die Helligkeit pulsiert sanft.
  - Danach blenden sie 3 s aus. Deckkraft höchstens 0,35, additiv.
- **App:** je Vorhang 48 Abschnitte mit `draw_polygon` und Eckfarben (unten Farbe, oben α 0), 120–180 px hoch, additives Material, dazu feine senkrechte Strahlen (α 0,1).
- **Lite:** 3 `<div>` mit `linear-gradient` und Wellenkante (`clip-path`), CSS-Animation nur auf `transform` und `opacity`, `mix-blend-mode: screen`. Kein `filter: blur`.
- **Ruhig:** ohne Wogen, nur ein- und ausblenden.

**17 Katzen-Sternbild** (höchstens einmal je Partie)
- Startet nie, solange die Mau-Katze aktiv ist.
- **Bewegung:**
  - 11 Sterne leuchten nacheinander auf (je 0,22 s).
  - Dann wachsen dünne Linien (1,6 s) zu einer sitzenden Katze mit zwei Ohrspitzen, Kopf, Rücken und geschwungenem Schwanz. Punkte und Linien stehen in der Tabelle (`form`).
  - Sie steht 4 s (leichtes Funkeln) und verblasst in 2 s. Kasten 240×160.
- **Antippen:** Alle Sterne funkeln einmal hell auf (0,4 s), die Schwanzlinie wackelt.
- **App:** Sterne als kleine Funkel mit 4 Strahlen (#DDE6FF), Linien 1,5 px α 0,45.
- **Lite:** SVG `<line>` mit wachsendem `stroke-dasharray`.
- **Ruhig:** Sterne und Linien blenden gemeinsam ein (1,5 s), stehen und blenden aus.

**18 UFO leuchtet den Stapel an** (höchstens einmal je Partie, nur im fremden Zug, nicht im Glücksspiel)
- **Bewegung:**
  - Einflug in einer Kurve vom oberen Rand (1,5 s, schaukelt ±8°).
  - Schwebt 3 s und wippt ±3 px, die Lichterkette läuft.
  - Nach 0,4 s fällt für 2,5 s ein Lichtkegel auf den Stapel: Deckkraft ≤ 0,22, unten Kartenbreite + 20, 4–6 Funken steigen auf.
  - Danach geht der Kegel aus, das UFO beschleunigt schräg nach oben (0,8 s). Größe 72×34.
- **Abbruch:** Kegel aus und sofort hinaus bei:
  - Ereignis `shuffle` (bis 1.6.14 auch `draw`),
  - Beginn des eigenen Zugs,
  - die Mau-Katze will kommen.
- **Nicht mehr scheu (ab 1.6.15, Nutzerwunsch „Das Ufo bitte nicht so einfach verscheuchen lassen“):** Ein Druck in der Nähe oder auf den Stapel und das Ziehen eines Mitspielers stören es nicht mehr (bis 1.6.14: Berührung im Umkreis von 130 px und `draw` → sofort hinaus; weil es über dem Stapel schwebt, vertrieb es fast jedes Ziehen).
- **Antippen** (das UFO selbst schwebt über dem Stapel, nicht auf ihm; Tabelle `tipp: "ausweichen"`, höchstens 3 Tipps):
  - 1. und 2. Tipp: Es weicht aus – ein kurzer Satz zur Seite (0,22 s, 62 px, weg vom Finger bzw. zur freieren Seite, nie auf einen Platz oder Knopf), es schaukelt, der Lichtkegel flackert (0,55 s); 0,9 s später gleitet es in 0,8 s zurück über den Stapel.
  - 3. Tipp: saust davon (wie bisher beim ersten Tipp).
  - Die Tippzeiten werden gemerkt (App `taps`/`dodges`, Lite `ausweich`), die Pose bleibt rein in t.
  - Kern: `NatureCreature.tap_limit()` (Standard 1) bzw. Lite `inst.tippMax`; `NatureFx.tap` bzw. `_druck` zählen die Tipps je Ereignis.
- **App:** Untertasse aus 2 Ellipsen (#B8C0D8/#6B7394) mit Rand #19C6D4, Kuppel Cyan α 0,45 mit Glanz, 5 Lichter abwechselnd Pink/Gelb/Türkis. Kegel als Trapez mit `draw_polygon` und Eckfarben (oben α 0,22, unten α 0,06), additiv.
- **Lite:** SVG, Kegel als `<div>` mit `clip-path: polygon()`, `linear-gradient` und `mix-blend-mode: screen`.

**19 Satellit**
- **Bewegung:** Ein heller Punkt (2,5 px) zieht gleichmäßig und gerade über den oberen Himmel. Ein rotes Licht blinkt einmal je Sekunde (0,1 s), einmal blitzt er kurz auf (0,4 s, Schein Ø 14).
- **App:** Kreis Weiß, kleines Glühen, rotes Licht #FF4D57.
- **Lite:** 2 `<i>`.

**20 Motte am Ablage-Ring** (nur im fremden Zug)
- Startet nicht bei offener Strafplakette, nicht beim Durchsehen der Ablage und nicht im Glücksspiel oder bei der Ablege-Auswahl.
- **Bewegung:**
  - Taumelt heran (1,2 s, Zitterbahn).
  - Kreist 2–3 Runden um den Ring auf einer Ellipse rx = R + 20, ry = 0,9·R + 14 (2,2 s je Runde). Der Radius zittert ±6 px, ab und zu stupst sie 10 px nach innen.
  - Torkelt davon (1 s).
  - Die Bahn bleibt außerhalb der obersten Karte. Weil die Motte in der Ebene `mitte` liegt, verdecken Ring und Karten sie, nie umgekehrt. Größe 22×16.
- **Scheu:** geht sofort ab bei:
  - Berührung im Umkreis von 130 px (ein Tipp auf die Ablage öffnet wie immer „Ablage durchsehen“),
  - `play`, `flip`, `discard_color`, `stake_discard`, `shuffle`,
  - Beginn des eigenen Zugs.
- **App:** Flügel als abgerundete Dreiecke #8E8170 mit Saum #C9BBA4, fedrige Fühler, Flügelschlag 14 Hz. Leicht in der Ringfarbe getönt (`modulate`, 30 %).
- **Lite:** SVG, Flügel per CSS scaleX.

**21 Igel am Tischrand** (Tischrand = Außenkante der Richtungs-Plattform)
- **Bewegung:**
  - Taucht am äußeren Bandende auf (0,5 s einblenden, als käme er hinter der Plattform hervor).
  - Tippelt mit 20 px/s am Band entlang, bleibt zweimal stehen und schnüffelt (Nase wackelt 0,8 s).
  - Dreht um, tippelt zurück und blendet aus. Größe 44×26.
- **Antippen:** Rollt sich zur Stachelkugel ein (0,3 s), bleibt 1,8 s so, rollt sich aus und tippelt schneller davon.
- **App:** Stachelkleid als Polygon mit 14 Zacken (#5B4632, Spitzen #8A6C4C), Gesicht #D9BE98, Nase und Auge INK mit Glanz, 4 Beinchen, oben eine Mondlicht-Kante in Creme α 0,5.
- **Lite:** SVG, Kugel als eigener Pfad.

**22 Komet**
- Startet nicht in den 20 s nach `skip_all`, damit er nicht mit dem Kometen von „Alle aussetzen“ verwechselt wird. Der kreist in Neon um die Plätze, die Sternschnuppe ist schnell. Der Natur-Komet ist blass, langsam, oben und kreist nie.
- **Bewegung:**
  - Flacher Bogen: Sehne 0,55 W, Durchhang 30 px, sehr langsam.
  - Blendet 2 s ein und 3 s aus.
  - Zwei Schweife gegen die Flugrichtung, je 140–180 px: ein breiter, leicht gebogener Staubschweif (#FFF3C8) und ein gerader, schmaler Ionenschweif (#8FB8FF).
- **App:** Schweife als `draw_polygon` mit Eckfarben (α 0,6 → 0), additiv. Kopf als Glühen mit Kern.
- **Lite:** 2 gedrehte `linear-gradient`-Divs, Kopf als radial-gradient, `mix-blend-mode: screen`.

**23 Lampion**
- **Bewegung:** Steigt hinter dem Tisch auf (liegt hinter Plattform und Plätzen) mit 40–50 px/s. Pendelt ±10 px (3 s), dreht sich ±4°, das Licht flackert sanft (α 0,8–1). Größe 34×44.
- **Antippen:** Glüht hell auf (0,6 s) und schaukelt stärker.
- **App:** Ellipse #FF8A24 mit 4 Rippen (#C45A10), Ringe oben und unten INK, innen ein additives Glühen #FFD27A.
- **Lite:** `<div>` mit radial-gradient und SVG-Rippen.

**26 Feuerwerk** (1.6.15, Nutzerwunsch: „Ein Feuerwerk als zufällige Aktion bei Nacht“; höchstens einmal je Partie)
- **Bewegung (5–6 s):**
  - 2–4 Raketen steigen mit dünner, warmer Leuchtspur 160–240 px auf (0,85–1,05 s, bremsen ab) und zerplatzen in freiem Himmel (y 0,10–0,27 H; Stellen ohne Plätze, Knöpfe, Mond; Abstand zueinander).
  - Je Knall 28–34 Funkenstriche in zwei Farben (Pfingstrose, Ring oder goldene Trauerweide) und ein innerer Kranz; sie fliegen mit Luftwiderstand auseinander (Radius 84–104 px), sinken, funkeln am Ende und verglimmen (1,35–1,8 s). Blitz beim Knall.
- **Antippen:** Ein Tipp in die leuchtende Hülle zündet an der Stelle einen weiteren Knall (ohne Rakete), höchstens zweimal (`tap_limit` 2 bzw. `tippMax` 2); das Ereignis läuft dann mindestens 2 s weiter.
- **Hülle:** Raketen und Knalle, die höchstens zur Hälfte hinter Plätzen liegen (wie `visible_hull`), damit Tipps und Sichtprüfung stimmen.
- **App:** Striche normal gemischt, Köpfe, Raketen und Blitz additiv (`glow`).
- **Lite:** ein SVG über die Bühne mit `mix-blend-mode: screen`; je Knall eine Gruppe (Lichthof, Blitz, Strich-Pfad, Spitzen als runde Punkte, innerer Kranz), die per `scale` wächst und per `translate` sinkt. Etwa 40 Knoten (die zwei Tipp-Knalle sind vorbereitet).

**27 Astronaut am Mond** (1.6.15, Nutzerwunsch: „Ein Astronaut schwebt neben dem Mond als zufällige Aktion bei Nacht“; höchstens einmal je Partie)
- **Bewegung (9–12 s):** Schwebt schräg von oben rechts (vor dem Mond vorbei) neben den Mond (2,2 s), treibt dort sanft (±14/±9 px), taumelt langsam (±17°), strampelt leicht, winkt einmal (1,5 s) und treibt nach links oben davon (2 s).
- **Ort:** freiester Punkt links bzw. unterhalb des Monds (115–220 px, 120–195°), meidet Plätze, Menü- und Ton-Knopf (Lite) und den Mond selbst.
- **Antippen:** langsamer Salto (1,9 s) mit Winken; danach schwebt er weiter.
- **App:** weißer Anzug #F6F4FF mit Lavendel-Kontur #8A80C8, Rucksack, Brustteil mit drei bunten Knöpfen, großer Helm, Visier #1B2147 mit Spiegelung (Lichtbogen, Mondsichel, Türkis-Schimmer), blinkendes Helmlicht; zarter Lichthof.
- **Lite:** SVG, Arm und Beine als Gruppen.

## 4. Häufigkeit und Mischung (Planer)

### 4.1 Konstanten (Tabelle `zeiten`)

| Schlüssel | Wert | Bedeutung |
|---|---|---|
| `erst_s` | 45–150 | erstes Zufallsereignis nach Tischstart (gleichverteilt) |
| `abstand_s` | 100–260 | Abstand vom **Ende** eines Ereignisses zum nächsten Zufallsstart (gleichverteilt) |
| `reduziert_faktor` | 2 | „Effekte reduziert“: Abstände doppelt |
| `neuversuch_s` | 5 | keine Ruhe → in 5 s erneut prüfen |
| `ruhe_s` | 2 | so lange muss die Tischregie schon ruhig sein |
| `anlass_abstand_s` | 25 | Flip- und Trödel-Ereignisse frühestens 25 s nach dem Ende des letzten |
| `keine_wiederholung` | 4 | die letzten 4 Ereignisse derselben Seite werden nicht gezogen |
| `abgang_s` | 0,4 | schneller Abgang |
| `flip_chance` / `flip_nach_s` / `flip_bis_s` | 0,4 / 1,5 / 6 | Flip-Anlass |
| `flip_je_runde` | 1 | höchstens ein Flip-Ereignis je Runde und Seite |
| `troedel_s` / `troedel_chance` / `troedel_max_s` | 35 / 0,35 / 40 | Schnecke |
| `scheu_r` | 130 | Umkreis der Scheu |
| `treffer_min_r` | 40 | kleinster Trefferradius beim Antippen |
| `komet_sperre_s` | 20 | Komet nicht so kurz nach `skip_all` |
| `vorfuehr_tipps` / `vorfuehr_fenster_s` / `vorfuehr_abstand_s` | 7 / 4 / 12 | Vorführung (4.7) |

**Erwartung:**
- Etwa 180 s Abstand plus etwa 10 s Dauer ergeben rund 19 Zufallsereignisse je Stunde bei Ruhe, in einer 20-Minuten-Partie also etwa 5–7.
- Ein einzelnes Tier mit Gewicht 3 kommt etwa einmal in 20 Minuten. Die seltenen (Gewicht 1, je Partie 1) kommen etwa einmal je Stunde.
- Dazu kommen höchstens ein Flip-Ereignis je Runde und Seite und selten eine Schnecke.
- **Folge für den Bestand:** Schmetterling und Sternschnuppe kommen bisher alle 1–3 min. Künftig teilen sie sich den Takt und kommen etwa alle 20 min (vorläufige Festlegung, Abschnitt 11).

### 4.2 Ablauf (gleich in App und Lite)

```
tick(dt):
  now += dt; current?.step(dt); if current?.done: beende(current)
  if not aktiv(): return                       # Tisch nicht sichtbar, großer Modus, Lite hochkant/eng
  if vorfuehrung: … (4.7); return
  if current or andere_laufen(): return        # Mau-Katze, Bestand-Himmel, Necken-Effekte
  if flip_bereit and ruhe() and now ≥ flip.at + flip_nach_s:  versuche_flip(); return
  if troedel_faellig(): versuche_schnecke(); return
  if now ≥ faellig:
    if not ruhe(): faellig = now + neuversuch_s; return
    id = ziehe(seite, reduziert, mein_zug)
    if id == "": faellig = now + 6 × neuversuch_s; return
    starte(id)
beende(c): faellig = now + zufall(abstand_s) × (reduziert ? 2 : 1); letztes_ende = now; verlauf += c.id
```

- **`ziehe`:** gewichtete Wahl (`zufall`) unter den Einträgen der aktuellen Seite.
  - Ausgeschlossen: Einträge mit Gewicht 0, Einträge außerhalb von `ruhig` (wenn reduziert), Einträge mit `fremder_zug` (wenn man selbst dran ist), erschöpfte `je_partie`/`je_runde`, der Komet in der `komet_sperre_s` und das Sternbild, wenn die Mau-Katze in dieser Partie aktiv ist.
  - Außerdem die letzten `keine_wiederholung` Ereignisse dieser Seite. Bleibt dadurch nichts übrig, fällt die älteste Sperre weg.
- **Zähler:** `je_partie` setzt sich zurück bei `round_start` mit `round == 1`, `je_runde` bei jedem `round_start`.
- **Zufall:** Jedes Ereignis bekommt beim Start einen eigenen Samen (`rng.randi()`). Bahn und Aussehen hängen nur davon und von t ab, siehe `pose_at(t)` in Abschnitt 7.

### 4.3 Anlässe

- **Flip:** `flip`-Ereignis gesehen → laufendes Ereignis der alten Seite geht sofort (`abgang_s`), Anlass merken {seite, at}.
  - Sobald Ruhe herrscht (Flip-Animation, „Tag!“/„Nacht!“-Banner und eine etwaige Flip-Überraschung sind vorbei) und `flip_nach_s` verstrichen ist, wird mit `flip_chance` gewürfelt.
  - Gezogen wird gewichtet nach `nach_flip`. Tag hat nur den Regenbogen, Nacht Glühwürmchen 3, Fledermaus 2, Eule 1.
  - Nach `flip_bis_s` verfällt der Anlass.
  - Ein erfolgreicher Anlass zählt wie ein Ereignis (setzt `faellig` neu).
- **Trödeln (Schnecke):** Die Uhr läuft wie bei `FunFx` (Signatur aus turn | top.id | draw_count).
  - Nach `troedel_s` wird einmal je Zug gewürfelt, und nur, wenn die Mau-Katze in diesem Zug nicht kam.
  - Läuft ein anderes Natur-Ereignis, geht es (`abgang_s`), und die Schnecke kommt danach.
  - Die Katze (25 s) hat Vorrang vor der Schnecke (35 s).

### 4.4 Ruhe (Startbedingungen für alle Ereignisse)

1. Der Tisch ist sichtbar, die Partie läuft, Phase `turn` oder `drawn`. Nicht in color, challenge, gamble, discard_pick, round_over oder game_over.
2. Die Tischregie ist seit `ruhe_s` ohne Ereignis (App `director.is_busy()`, Lite `tisch.regie.leer`).
3. Nichts liegt über dem Tisch:
   - **App:** `tease.modal_cb` (= `TableScreen.is_modal_open`, schon gesetzt), Farbwahl, Hilfe, Rückseiten-Ansicht, Rundenende, Sichtschutz (Weitergeben), „Ablage durchsehen“ oder Necken-Menü (`tease.menu`).
   - **Lite:** `.modal` sichtbar, `M.Necken.offen`, `.farbwahl` sichtbar oder `tisch.durch`.
4. Kein Erwischt-Fenster (`hints.catch` leer).
5. Es läuft nichts anderes:
   - **App:** kein Natur-Ereignis, `fun.cat.active()`/`fun.sky.active()` falsch, `tease.effects()` leer.
   - **Lite:** kein Natur-Ereignis, kein `nk-`-Element in `tisch.flug`.
6. Für `fremder_zug`: Ich bin nicht dran (`view.turn != view.seat`), und meine Hand wird gerade nicht berührt.

### 4.5 Abgang und Abbruch

| Auslöser | Wer geht | Wie |
|---|---|---|
| Seite wechselt (`flip`-Ereignis oder `night` über 0,5) | Ereignis der alten Seite | schnell (0,4 s, wegfliegen bzw. ausblenden) |
| `round_over`, `game_over`, `round_start`, `deal`, `seats` | alle | schnell |
| eigener Zug beginnt, Erwischt-Fenster öffnet, `mau`, `finish`, `catch` | Ebene `vorn` (Biene, UFO) und Motte | schnell |
| Dialog oder Menü öffnet (4.4 Nr. 3) | Ebene `vorn` | schnell; `hinten`/`mitte` laufen hinter dem Dialog weiter |
| Necken-Effekt beginnt | Ebene `vorn` | schnell |
| Mau-Katze will kommen (`FunFx`, 7.1) | alle | schnell, die Katze kommt danach |
| Ereignisse am Ort: UFO bei `shuffle` (ab 1.6.15 nicht mehr bei `draw`), Motte bei `play`/`flip`/`discard_color`/`stake_discard`/`shuffle`, Biene bei Kartenverlust/Sortieren/`swap_hands` | dieses | schnell |
| Größe, großer Modus an, „reduziert“ an (nicht ruhige Einträge) | alle betroffenen | sofort entfernen |
| App im Hintergrund bzw. Lite-Tab verdeckt | – | Uhr steht. Nach mehr als 2 s Pause wird `faellig` frühestens `erst_s` später. |

### 4.6 Tippen

- **App:**
  - `TableView._tap` ruft `nature.tap(wp)` als **letzten** Fall vor `return false`. Erwischt, Ablage, Glücksspiel, Mau-Katze, Ziehen, Kopf und Fächer sind also schon geprüft.
  - `nature.tap` gibt false zurück, wenn der Punkt in einer Schutzfläche liegt (2.3), sonst true nur bei einem Treffer auf ein Tier mit `tipp` (Radius mindestens `treffer_min_r`). Höchstens eine Reaktion je Ereignis; ab 1.6.15 höchstens `NatureCreature.tap_limit()` (UFO 3, Feuerwerk 2), im Lite `inst.tippMax`. `tap_at`/`tap_pos` gelten für den ersten Tipp, weitere merkt sich das Tier selbst (`add_tap`/`taps`).
  - Zusätzlich meldet `_gui_input` jeden Druck an `nature.notice_press(wp)` (Scheu). Diese Meldung verbraucht nie etwas.
- **Lite:**
  - Ein `pointerdown`-Hörer in der Einfangphase am Tischwurzel-Element meldet jeden Druck als Scheu.
  - Eine Reaktion gibt es nur, wenn das Ziel „leer“ ist: `ev.target` ist `.buehne`, `#tisch`, `.himmel`, `.richtung` oder eine Natur-Ebene.
  - Nie `preventDefault`/`stopPropagation`. Die Tiere haben `pointer-events: none`, die Trefferprüfung ist geometrisch.
- Damit gilt: Ein Tipp, der ein Spielelement trifft, wirkt immer normal. Ein Tier nimmt nur Tipps, die sonst ins Leere gingen.

### 4.7 Vorführung (Gerätetest und zum Anschauen)

- **Ein- und Ausschalten:** 7 Tipps innerhalb von 4 s auf eine freie Stelle (keine Schutzfläche, kein Tier, Punkte höchstens 80 px auseinander). Gleiches schaltet sie wieder aus, ebenso das Verlassen des Tisches.
- **Ablauf:**
  - Alle 12 s kommt das nächste Ereignis der aktuellen Seite in Tabellenreihenfolge, auch Anlass- und seltene Ereignisse.
  - Ohne `je_partie`, Wiederholungssperre und `fremder_zug`, Scheu und Abbruch gelten aber.
  - Im großen Modus und im Lite hochkant gibt es keine Vorführung.
- **Lite:** zusätzlich `?natur=reihe` in der Adresse (z. B. `index.html?mock=1&natur=reihe` zum Anschauen aller Ereignisse am eigenen Handy).
- **Protokoll:** App schreibt `NatureFx: start <id>` und `NatureFx: ende <id> fps=<n>` (eine Zeile je Ereignis, auch im Release-Bau sichtbar in `logcat`).

## 5. Bestehende Regeln

1. **„Effekte reduziert“:**
   - Es kommen nur die Einträge mit `ruhig: true`: Wolke, Regenbogen, Mond mit Schlafmütze, Polarlicht und Sternbild. Sie erscheinen in ihrer ruhigen Variante (nur ein- und ausblenden, keine Bewegung).
   - Abstände ×2.
   - Alles andere ist aus, wie heute Katze und Himmel in `FunFx`.
   - Lite: `body.reduziert`, ab Werk bei `prefers-reduced-motion`. Die CSS-Animationen der Arten stehen dort still.
2. **Großer Modus:** aus, auch Schmetterling und Sternschnuppe, wie heute (`FunFx._check_sky`).
   - Begründung: ruhiger Hintergrund für Sehschwäche, riesige Stapel oben links, die Liste rechts, kaum freier Himmel.
   - Umschalten während eines Ereignisses entfernt es sofort.
3. **Lite hochkant bzw. eng** (`.buehne.eng`, Maßstab < 0,5): aus, die Tiere wären winzig.
4. **Tag/Nacht durch Flip:** Tagtiere gehen bei Flip-Beginn (bzw. wenn `night` die 0,5 überschreitet) in 0,4 s, Nachttiere kommen danach nur über den Anlass (4.3) oder den normalen Takt. Während der Überblendung startet nichts.
5. **Keine Töne:** Kein Aufruf von `AppSound`/`UiApp.vibrate` bzw. `M.Ton`/`navigator.vibrate`. Der Vertragstest prüft das (8.3).
6. **Mau-Katze nicht doppeln:**
   - Kein Natur-Ereignis zeigt eine Katze, nur das abstrakte Sternbild aus Sternen. Das kommt nie, solange die Stapel-Katze aktiv ist oder wenn sie in dieser Partie schon da war, und höchstens einmal je Partie.
   - Nichts nutzt den Ziehstapel als Ruheplatz.
   - Die Katze hat Vorrang (4.5), die Schnecke kommt nie im selben Zug wie die Katze.
7. **Necken:** Kein Start, solange Necken-Effekte laufen oder das Menü offen ist. `vorn` geht ab, wenn ein Necken-Effekt beginnt. An `tease_fx.gd`/`necken.js` ändert sich nichts, gelesen werden nur `tease.effects()`, `tease.menu`, `tease.modal_cb` bzw. `M.Necken.offen` und die `nk-`-Elemente.
8. **Sprüche und Necken-Schalter** wirken nicht auf die Natur. Es gibt **keine eigene Einstellung** (vorläufig, Abschnitt 11).
9. **Weitergeben:** läuft wie sonst. Der Sichtschutz zählt als Dialog, und `vorn` kommt nur im Zug eines Computergegners.
10. **Eckindex der Handkarten** (AGENTS 8) bleibt frei, siehe Biene.

## 6. Daten (gemeinsame Tabelle)

Die Quelle der Wahrheit ist `game/scripts/ui/nature_table.gd` (`const DATA`, nur einfache Werte). `webclient/natur.js` enthält dieselbe Tabelle als JSON zwischen `/*NATUR-DATEN*/` und `/*ENDE*/`. `test_web_contract.gd` vergleicht beide nach `JSON.parse_string(JSON.stringify(...))` (so stimmen Ganzzahl und Kommazahl überein). Bei einer Abweichung gibt der Test die erwartete Zeile aus.

Felder:
- `zufall`, `nach_flip`: Gewichte (0 = nie)
- `troedeln`: Anlass Trödeln
- `ruhig`: auch bei „reduziert“, dann in der ruhigen Variante
- `tipp`: Reaktion, "" = keine
- `scheu`: geht bei Berührung in `scheu_r`
- `fremder_zug`: nur, wenn ich nicht dran bin
- `je_partie`/`je_runde`: Obergrenzen (0 = frei)
- `deckt`/`deckt_max_s`: was die Ebene `vorn` kurz decken darf
- `bestand`: App zeichnet über `FunFx.SkyNode`

```json
{
 "zeiten": {"erst_s": [45, 150], "abstand_s": [100, 260], "reduziert_faktor": 2, "neuversuch_s": 5, "ruhe_s": 2,
  "anlass_abstand_s": 25, "keine_wiederholung": 4, "abgang_s": 0.4, "flip_chance": 0.4, "flip_nach_s": 1.5, "flip_bis_s": 6,
  "flip_je_runde": 1, "troedel_s": 35, "troedel_chance": 0.35, "troedel_max_s": 40, "scheu_r": 130, "treffer_min_r": 40,
  "komet_sperre_s": 20, "vorfuehr_tipps": 7, "vorfuehr_fenster_s": 4, "vorfuehr_abstand_s": 12},
 "ereignisse": [
  {"id": "marienkaefer", "seite": "tag", "zufall": 3, "nach_flip": 0, "troedeln": false, "ebene": "mitte", "ort": "band_vorn_seite", "dauer": [9, 12], "ruhig": false, "tipp": "wegfliegen", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "biene", "seite": "tag", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "vorn", "ort": "handkarte", "dauer": [7, 9], "ruhig": false, "tipp": "", "scheu": true, "fremder_zug": true, "je_partie": 0, "je_runde": 0, "deckt": ["hand"], "deckt_max_s": 2, "bestand": false},
  {"id": "libelle", "seite": "tag", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "mitte", "ort": "tisch_quer", "dauer": [6, 8], "ruhig": false, "tipp": "wegflitzen", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "pusteblume", "seite": "tag", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel", "dauer": [12, 15], "ruhig": false, "tipp": "wind", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "papierflieger", "seite": "tag", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel", "dauer": [6, 7], "ruhig": false, "tipp": "looping", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "seifenblasen", "seite": "tag", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "mitte", "ort": "tisch_quer", "dauer": [8, 11], "ruhig": false, "tipp": "platzen", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "spatz", "seite": "tag", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "mitte", "ort": "band_hinten", "dauer": [7, 10], "ruhig": false, "tipp": "wegfliegen", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "wolke", "seite": "tag", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "sonne", "dauer": [12, 16], "ruhig": true, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "regenbogen", "seite": "tag", "zufall": 0, "nach_flip": 1, "troedeln": false, "ebene": "hinten", "ort": "himmel_bogen", "dauer": [7, 7], "ruhig": true, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 1, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "heissluftballon", "seite": "tag", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel_fern", "dauer": [18, 22], "ruhig": false, "tipp": "aufsteigen", "scheu": false, "fremder_zug": false, "je_partie": 1, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "schnecke", "seite": "tag", "zufall": 0, "nach_flip": 0, "troedeln": true, "ebene": "mitte", "ort": "band_zum_platz", "dauer": [40, 40], "ruhig": false, "tipp": "einziehen", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "schmetterling", "seite": "tag", "zufall": 3, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel", "dauer": [9, 9], "ruhig": false, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": true},
  {"id": "hoppelhase", "seite": "tag", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "mitte", "ort": "band_vorn_seite", "dauer": [9, 12], "ruhig": false, "tipp": "hochspringen", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "strand", "seite": "tag", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "ecke_unten_rechts", "dauer": [7, 8], "ruhig": false, "tipp": "palme_schuetteln", "scheu": false, "fremder_zug": false, "je_partie": 1, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "gluehwuermchen", "seite": "nacht", "zufall": 3, "nach_flip": 3, "troedeln": false, "ebene": "mitte", "ort": "tisch_rund", "dauer": [12, 15], "ruhig": false, "tipp": "auseinander", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "eule", "seite": "nacht", "zufall": 3, "nach_flip": 1, "troedeln": false, "ebene": "mitte", "ort": "band_schulter", "dauer": [12, 16], "ruhig": false, "tipp": "kopf_blinzeln", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "fledermaus", "seite": "nacht", "zufall": 2, "nach_flip": 2, "troedeln": false, "ebene": "hinten", "ort": "himmel", "dauer": [4, 6], "ruhig": false, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "mond_muetze", "seite": "nacht", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "mond", "dauer": [10, 12], "ruhig": true, "tipp": "aufwachen", "scheu": false, "fremder_zug": false, "je_partie": 1, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "polarlicht", "seite": "nacht", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel_oben", "dauer": [12, 14], "ruhig": true, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 1, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "sternbild", "seite": "nacht", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel_frei", "dauer": [9, 10], "ruhig": true, "tipp": "funkeln", "scheu": false, "fremder_zug": false, "je_partie": 1, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false,
   "form": {"punkte": [[0.12, 0.06], [0.22, 0.20], [0.32, 0.04], [0.08, 0.38], [0.38, 0.34], [0.18, 0.64], [0.22, 0.96], [0.62, 0.48], [0.78, 0.92], [0.97, 0.72], [0.90, 0.38]],
            "linien": [[0, 1], [1, 2], [0, 3], [2, 4], [3, 5], [4, 7], [5, 6], [6, 8], [7, 8], [8, 9], [9, 10]]}},
  {"id": "ufo", "seite": "nacht", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "vorn", "ort": "stapel_oben", "dauer": [7, 8], "ruhig": false, "tipp": "ausweichen", "scheu": false, "fremder_zug": true, "je_partie": 1, "je_runde": 0, "deckt": ["stapel"], "deckt_max_s": 3, "bestand": false},
  {"id": "satellit", "seite": "nacht", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel_oben", "dauer": [9, 11], "ruhig": false, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "motte", "seite": "nacht", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "mitte", "ort": "ablage_ring", "dauer": [6, 8], "ruhig": false, "tipp": "", "scheu": true, "fremder_zug": true, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "igel", "seite": "nacht", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "mitte", "ort": "band_vorn_seite", "dauer": [10, 14], "ruhig": false, "tipp": "einrollen", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "komet", "seite": "nacht", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel_oben", "dauer": [14, 16], "ruhig": false, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "lampion", "seite": "nacht", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "aufsteigend", "dauer": [11, 13], "ruhig": false, "tipp": "leuchten", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "sternschnuppe", "seite": "nacht", "zufall": 3, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel", "dauer": [1.2, 1.2], "ruhig": false, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": true},
  {"id": "feuerwerk", "seite": "nacht", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel", "dauer": [5, 6], "ruhig": false, "tipp": "knallen", "scheu": false, "fremder_zug": false, "je_partie": 1, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "astronaut", "seite": "nacht", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "mond", "dauer": [9, 12], "ruhig": false, "tipp": "salto", "scheu": false, "fremder_zug": false, "je_partie": 1, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false}
 ]
}
```

## 7. Architektur

### 7.1 App

**Neue Dateien** (Klassen mit `class_name`, Verweise untereinander per `preload`/`load` wie die Hausregel-Bausteine in `table_view.gd`, damit der Klassen-Cache nicht stört; vor dem ersten Lauf `tools/godot_import.ps1`):

- **`game/scripts/ui/nature_table.gd`** (`NatureTable`, RefCounted):
  - `const DATA` (Abschnitt 6)
  - `entry(id)`, `ids(side)`, `timing(key)`
  - `pool(side, reduced, my_turn, counts, recent) -> Array` (Paare id, Gewicht) und `flip_pool(side)`
  - Rein und ohne Knoten.
- **`game/scripts/ui/nature_creature.gd`** (`NatureCreature`, Node2D), Grundklasse aller Tiere:
  - Zustand `id, fx, rng (eigener Samen), t, dur, night, reduced, calm, ctx (Orte beim Start), phase ("in"|"main"|"leave"|"done")`.
  - Pflicht: `setup(ctx)` (würfelt nur aus `rng`, setzt `dur`) und `pose_at(t)` (reiner Zustand zur Zeit t).
  - Bereitgestellt:
    - `step(dt)` = `t += dt; pose_at(t); queue_redraw()`, dazu `seek(t)` für Tests und Kontrollbilder.
    - `bounds() -> Rect2` (Welt).
    - `hit(p)`, `on_tap(p)`, `on_press(p)` (Scheu), `on_event(ev)` (Abbruch am Ort), `leave(fast)`, `is_done()`.
    - Reaktionen nach einem Tipp laufen als eigene Zeitlinie ab der Tippzeit, sodass `seek` gleich bleibt.
  - Zeichenhilfen: `poly_ellipse`, `tri`, `wing`, `outline_poly`, `glow(pos, r, col)` (über ein Kind `GlowNode` mit `TableEffects.additive()`, das per Callable zeichnet), Farbkonstanten. Keine `CPUParticles2D`: Teilchen sind eigene Listen, damit alles mit dem Samen festliegt.
- **`game/scripts/ui/nature_fx.gd`** (`NatureFx`, Node), Planer und Verwaltung:
  - Zustand: `table, rng, auto_process, now, reduced, big, night, enabled, demo, current, history, counts`, Signale `started(id)`/`ended(id)`.
  - Einhängen und Spielstand:
    - `mount(t, bg, world, ring, hand_layer)` legt die drei Ebenen an (2.1) und setzt `fun.sky_auto = false`, `fun.nature = self`.
    - `set_reduced`, `set_big`, `set_night`, `on_view(v)`, `on_event(ev)`, `on_layout()`.
    - `tick(dt)` (bei `auto_process` über `_process`).
  - Eingaben: `notice_press(wp)`, `tap(wp) -> bool`.
  - Für `FunFx`: `busy()`, `make_room()`.
  - Lage: `obstacles() -> Dictionary` und `anchors() -> Dictionary` (2.2/2.3).
  - Tests, Bilder, Vorführung: `spawn(id, seed := -1)` ohne Bedingungen.
  - Tiere: `static make(id)` lädt `nature_day.gd`/`nature_night.gd` per `load()`, wenn vorhanden (`ResourceLoader.exists`), und ruft deren `static func make(id) -> NatureCreature` (null = unbekannt). So läuft der Kern schon ohne die Tierdateien, und diese brauchen keinen Eintrag im Kern.
  - Bestand: `schmetterling`/`sternschnuppe` → `table.fun.sky.launch(night > 0.5, rng, size)`, aktiv solange `fun.sky.active()`, Abgang `fun.sky.stop()`.
  - Sonne/Mond: Formeln aus dem Shader gespiegelt, mit Verweis. Der Test prüft die Zahlen im Shader-Text.
- **`game/scripts/ui/nature_day.gd`** / **`nature_night.gd`** (RefCounted mit `static func make(id)`): je Tier eine innere Klasse, die von `preload("res://scripts/ui/nature_creature.gd")` erbt.

**Eingriffe in bestehende Dateien:**

- **`table_view.gd`** (etwa 14 Zeilen):
  - `const NatureFxScript := preload("res://scripts/ui/nature_fx.gd")`, `var nature: NatureFxScript`.
  - In `_init` nach dem Anlegen von `hand_layer`/`_hand_halo` und **vor** `fx`: `nature = NatureFxScript.new(); nature.mount(self, _bg, _world, _ring, hand_layer)`.
  - In `set_reduced`: `nature.set_reduced(on)`. In `set_big`: `nature.set_big(on)`. In `set_night`: `nature.set_night(night)`. In `_layout`: `nature.on_layout()`.
  - In `apply_view`: `nature.on_view(v)`. In `play_event` und `skip_event`: `nature.on_event(ev)`.
  - In `_gui_input` (Druck): `nature.notice_press(_world.to_local(get_global_transform() * mb.position))`.
  - In `_tap` vor `return false`: `if nature.tap(wp): return true`.
  - Mit `if nature` absichern, wo `set_reduced`/`set_night` schon vor dem Einhängen laufen.
- **`fun_fx.gd`** (etwa 8 Zeilen):
  - `var sky_auto := true`, in `_check_sky` gleich zu Beginn `if not sky_auto: return`.
  - `var nature: Object = null`. In `_check_cat` nach Wartezeit und Würfel und **vor** `_rolled = true`: `if nature != null and nature.call("busy"): nature.call("make_room"); return`. Es wird im nächsten Tick neu versucht.
  - `test_fun_fx.gd` bleibt grün, weil die Standardwerte unverändert sind.
- **Nicht geändert:** `tease_fx.gd`, `tease_menu.gd`, `table_screen.gd`, `opponent_seat.gd`, `table_background.gd`, Einstellungen, `.po`.

### 7.2 Lite

**Neue Dateien:**

- **`webclient/natur.js`** (`M.Natur`):
  - Inhalt: Tabelle als JSON zwischen `/*NATUR-DATEN*/ … /*ENDE*/`, Planer (gleicher Ablauf wie 4.2), Ebenen, Orte, Schutzflächen, Tippen und Scheu, Vorführung.
  - Schnittstelle:
    - `init(app)` (legt die Ebenen an, sobald `app.tisch` existiert, Uhr `setInterval` 500 ms nur am Tisch)
    - `sicht(events, view)` (Ereignisse für Flip, Abbruch und Zähler; Zug und Phase)
    - `art(id, def)` (Registrierung), `stil(name, css)` (CSS der Arten einmal als `<style id="natur-stil">`)
    - Test: `test({seed, manuell})`, `tick(dt)`, `zeige(id, {seed, t, stehen})`, `zustand()`, `arten()`
  - Liest nur Vorhandenes: `app.screen`, `app.effekteReduziert()`, `app.tisch.{buehne, root, g, W, H, s, v, regie.leer, gross, hand, durch, flug, zuBuehne, wechselRest}`, `M.Necken.offen`.
  - Bewegungen der Bahnen per `requestAnimationFrame`, aber nur, solange ein Ereignis läuft. Gesetzt werden nur `transform` und `opacity`.
  - Zufall: mulberry32 mit Samen; ohne Test kommt der Samen aus `Math.random`.
  - Seite aus `#tisch[data-seite]`, Größe und eng aus `tisch.W/H/s`, großer Modus aus `tisch.gross`, alles im Uhrtakt abgefragt. Dafür sind keine Haken in `tisch.js` nötig.
- **`webclient/natur_tag.js`** / **`webclient/natur_nacht.js`**:
  - `M.Natur.art('<id>', { baue(ctx, zufall) → { el, ebene, dauer, stelle(t), treffer(p), tipp(p), scheu(p), ereignis(e), abgang(), hulle(t) } })`.
  - SVG als Zeichenketten, CSS mit Präfix `nt-` (Necken nutzt `nk-`).
  - Innere Schleifen (Flügelschlag, Blinzeln, Funkeln) als CSS-Keyframes, die unter `body.reduziert` aus sind.
  - Keine `filter`/`backdrop-filter`, kein animierter `box-shadow`. Nachts glüht es über `mix-blend-mode: screen`.
  - Höchstens etwa 30 Knoten je Ereignis. Nach dem Ende ist alles entfernt.

**Eingriffe:**

- **`index.html`:** `natur.js`, `natur_tag.js`, `natur_nacht.js` nach `necken.js` und vor `tisch.js`.
- **`app.js`** (2 Zeilen):
  - nach `if (M.Necken) M.Necken.init(this);`: `if (M.Natur) M.Natur.init(this);`
  - im Fall `'state'` nach `M.Necken.sicht(...)`: `if (M.Natur) M.Natur.sicht(m.events || [], m.view);`
- **Nicht geändert:** `tisch.js`, `style.css`, `necken.js`, `spass.js`, `hand.js`.
- Der Vermittler liefert neue Dateien ohne Änderung aus (`relay/src/client.js`: jede gültige Datei aus `webclient/` am Tag), und `web.zip` packt alles in `webclient/`.

### 7.3 Nichts übers Netz

Kein `send`, kein `fetch`, keine Felder in Sicht oder Protokoll, keine Änderung an `NetProtocol`, `host_table.gd` oder `relay/`. Jedes Gerät zeigt seine eigenen Ereignisse. Zwei Spieler am selben Tisch sehen also verschiedene Tiere, das ist gewollt.

## 8. Tests

### 8.1 App, automatisch (im Bau)

- **`game/tests/test_nature_fx.gd`** (Kern, mit Probe-Tier, Uhr und Zufall eingespritzt: `auto_process = false`, `tick(dt)`, `rng.seed`):
  - **Tabelle:** 25 Einträge, ids eindeutig, Felder und Werte gültig; jede Seite hat Zufallseinträge; `ruhig` genau die fünf aus 5.1; `vorn` nur Biene und UFO; Sonne- und Mondformel im Shader-Text unverändert.
  - **Dauerlauf:** 10 h simulierte Partie (Sicht alle 4–12 s, Tischregie zufällig beschäftigt, Tag/Nacht wechselt). Geprüft wird:
    - mittlerer Abstand in 150–230 s;
    - nie zwei gleichzeitig, auch nicht mit `FunFx`-Katze, Himmel oder Necken-Attrappe;
    - Abstand ab Ende ≥ 100 s (zufällig) bzw. ≥ 25 s (Anlass);
    - keine Wiederholung unter den letzten 4;
    - `je_partie`/`je_runde` eingehalten, Tagtiere nur bei `night < 0,5`;
    - jedes Zufallsereignis kommt mindestens einmal vor.
  - **Bedingungen:** nichts im großen Modus, bei Dialog (`modal_cb`), Erwischt-Fenster, `round_over`, color, gamble, discard_pick, Regie < 2 s ruhig. „Reduziert“: nur die ruhigen, Abstände ×2. `fremder_zug` nicht im eigenen Zug.
  - **Flip:** Tagereignis läuft, `on_event(flip)` → Abgang ≤ 0,4 s; Anlass nach Ruhe + 1,5 s mit festem Samen; verfällt nach 6 s; Regenbogen höchstens einmal je Runde.
  - **Trödeln:** Schnecke ab 35 s, einmal je Spieler und Partie; nicht im Katzenzug; die Katze verdrängt ein laufendes Ereignis (`make_room`) und kommt danach.
  - **Abbruch:** eigener Zug, `mau`/`catch`, Dialog, Necken-Effekt (vorn), `draw` (UFO), `play` (Motte), Handberührung (Biene), Größe, großer Modus und „reduziert“ entsprechend 4.5.
  - **Mit echter `TableView`** (wie `test_ui_tease.gd`), mit gespawnten Tieren ohne Bedingungen:
    - Tipp auf den Stapel unter dem UFO → Aktion `draw` kommt;
    - Tipp auf die Ablage neben der Motte → „Ablage durchsehen“ öffnet;
    - Tipp auf einen Kopf → Necken-Menü;
    - Handkarte unter der Biene → Hand reagiert, die Biene geht;
    - Tipp auf den freien Spatz → `_tap` ist true, keine Aktion;
    - Tipp ins Leere ohne Tier → false wie bisher.
  - **Ebenen:** Reihenfolge der Knoten wie in 2.1.
  - **Sonstiges:** keine Töne, keine Vibration (`AppSound`-Attrappe zählt 0). 1000 Ereignisse → keine übrigen Knoten. Bestand-Brücke: Schmetterling/Sternschnuppe starten `fun.sky`, `FunFx` würfelt selbst keinen Himmel mehr.
- **`game/tests/nature_check.gd`** (Hilfe, kein eigener Test): `check_creature(fx, id, sizes, players) -> Array[String]`. Für 1600×720, 1600×900, 1760×720, 1600×1000 und 2/4/8 Spieler wird `seek(t)` in 50-ms-Schritten durchlaufen. Geprüft wird:
  - Sichtbarkeit in der Hauptphase ≥ 60 %;
  - `vorn`: nur die Flächen aus `deckt` und höchstens `deckt_max_s`; Biene nie im Eckindex-Viertel;
  - nach `dur` + 1 s ist alles weg;
  - `hit` nur auf dem Tier;
  - `leave(true)` endet in ≤ 0,5 s;
  - gleicher Samen → gleiche `bounds()` (Bestimmtheit).
- **`test_nature_tag.gd`** / **`test_nature_nacht.gd`** (je Tieraufgabe): `nature_check` für jede eigene id. Dazu die Reaktion beim Antippen (Zustand danach) und das Verhalten bei „ruhig“ (keine Bewegung: `bounds` gleich über die Zeit).

### 8.2 Lite, automatisch (im Bau)

**`webclient/test/lite_natur.html`** (wie `lite_necken.html`: `index.html?mock=1&natur=test&seed=…` im iframe, Schein-WebSocket bzw. `mock.js`). Aufruf über `tools/build.ps1` → neue Funktion `Invoke-WebNatureTest`.

- **Planer** (manuelle Uhr, `MMF.Natur.tick`): Abstände, nie zwei gleichzeitig, Wiederholungssperre, Obergrenzen, Flip-Anlass aus `sicht([{e:'flip'…}])`, Schnecke nach 35 s.
- **Aus- und Sonderfälle:** aus bei `gross`, `eng`, Lobby; „reduziert“ nur die ruhigen; Abbruch nach 4.5.
- **Tippen:**
  - Klick auf `#stapel` unter dem UFO → `app.ziehen` wird aufgerufen (Spion);
  - Handkarte unter der Biene → `antippen`/`spielen`;
  - `.gg`-Kopf → Necken-Menü offen;
  - freie Stelle auf dem Spatz → Reaktion, keine App-Aktion;
  - nie `defaultPrevented`.
- **Ebenen:** DOM-Reihenfolge und z-index (`#natur-mitte` vor `.farbanzeige`, `#natur-vorn` unter `.leiste`, `#mau`, `.erwischen`).
- **Generisch für jede registrierte Art** (`MMF.Natur.arten()`): Hülle über die Zeit (Sichtbarkeit, `deckt`), Aufräumen (keine `.nt-`-Knoten danach), Bestimmtheit. Gilt auch für Lite-Größen 1180×720, 1558×720 (844×390), 2000×720.
- **Nichts nach außen:** kein `M.Ton.spiele` aus `natur*.js` (Spion), kein Senden an den Schein-WebSocket.

### 8.3 Gleichlauf (`test_web_contract.gd`, `pruefe_natur`)

- Die JSON-Tabelle in `natur.js` ist gleich `NatureTable.DATA`.
- `index.html` lädt `natur.js`, `natur_tag.js` und `natur_nacht.js` nach `necken.js` und vor `tisch.js`. Die drei Dateien stehen in der Liste der ausgelieferten Skripte.
- **Vollständigkeit:** Jede id ohne `bestand` hat ein Tier in der App (`NatureFx.make(id) != null`). Jede id hat im Lite `M.Natur.art('<id>'`.
- **Haken:** `app.js` enthält die zwei Aufrufe, `table_view.gd` die Aufrufe aus 7.1.
- **Verbote:** `natur*.js` und `nature_*.gd` enthalten weder Ton (`M.Ton`, `vibrate`, `AppSound`, `UiApp.vibrate`) noch Netz (`send(`, `fetch(`, `WebSocket`) noch Adressen (`http`).

### 8.4 Kontrollbilder (alle ansehen)

**App:** `tools/godot_run.ps1 -Script res://tests/<datei> -Resolution 1600x720 -Extra '--rendering-driver','opengl3_angle'`. ANGLE ist am PC Pflicht, sonst malt der native Treiber grüne Blöcke.
- **`test_nature_tag_shot.gd`** / **`test_nature_nacht_shot.gd`:** echte `TableScreen` (Übung, 4 Spieler) wie `test_fun_fx_shot.gd`, `nature.spawn(id, seed)` und `seek(t)` zu drei Zeitpunkten (Anflug, Hauptphase, Reaktion nach Tipp bzw. Abgang). Ergebnis:
  - je id `docs/module/optik_1611_natur_<id>.png`;
  - Übersichten `optik_1611_natur_tag.png`/`_nacht.png`;
  - Zusatzbilder: ruhige Varianten (`_ruhig`), 8 Spieler (Spatz, Eule, Igel, Marienkäfer meiden Plätze), 1600×900, Biene auf der Handkarte (Eckindex frei), UFO-Kegel (Stapel lesbar).
  - Umgebungsvariable `NUR=<id,…>` für einzelne Bilder.
- **`test_nature_flip_shot.gd`:** Flip Tag→Nacht (Tagtier geht, Glühwürmchen kommen) und Nacht→Tag (Regenbogen) → `optik_1611_natur_flip.png`.

**Lite:** `tools/webtest/natur_bilder.ps1 [-Nur ids] [-Stand 1611]` (über `cdp.ps1`, 844×390 @2, dazu 1280×800 für Regenbogen, Polarlicht und UFO).
- Ablauf: `index.html?mock=1&szene=tisch&seite=…&dran=…` → `MMF.Natur.zeige(id, {seed, t, stehen: true})`.
- Ergebnis: `docs/module/optik_1611_lite_natur_<id>.png`, Flip-Bilder `optik_1611_lite_natur_flip_*.png`.

### 8.5 Gerätetest (Hauptsitzung)

- **Geräte:** S21 und S10 gesperrt (`MauMauFlipTestLock`), App in der Übung, Belegung mit der Draw2Race-Sitzung absprechen.
- **Ablauf:** Vorführung per `adb shell input tap` ×7 auf eine freie Himmelsstelle. Je Ereignis ein `screencap`, im `logcat` `NatureFx: start/ende … fps=`.
- **Prüfen:** Ruckeln am S10, Tippen und Scheu (Biene über der Hand, UFO über dem Stapel, Spatz antippen).
- **Lite:** gesperrt nicht möglich, also nur Chrome headless.
- **Zum Anschauen für den Nutzer:** `?mock=1&natur=reihe`.

## 9. Umsetzungsaufgaben (überschneidungsfrei)

| Aufgabe | Dateien (nur diese) | Abhängig von |
|---|---|---|
| **T1 App-Kern** | `game/scripts/ui/nature_table.gd`, `nature_creature.gd`, `nature_fx.gd`, `table_view.gd` (Haken 7.1), `fun_fx.gd` (Takt, Katze), `game/tests/test_nature_fx.gd`, `game/tests/nature_check.gd` | – |
| **T2 Lite-Kern** | `webclient/natur.js`, `webclient/index.html`, `webclient/app.js` (2 Haken, ohne `VERSION`), `webclient/test/lite_natur.html`, `tools/build.ps1` (`Invoke-WebNatureTest`), `tools/webtest/natur_bilder.ps1` | – (Tabelle aus Abschnitt 6) |
| **T3 App-Tagtiere** | `game/scripts/ui/nature_day.gd`, `game/tests/test_nature_tag.gd`, `game/tests/test_nature_tag_shot.gd`, Bilder `optik_1611_natur_<tag-ids>*.png`, `optik_1611_natur_tag.png` | T1 |
| **T4 App-Nachttiere** | `game/scripts/ui/nature_night.gd`, `game/tests/test_nature_nacht.gd`, `game/tests/test_nature_nacht_shot.gd`, Bilder `optik_1611_natur_<nacht-ids>*.png`, `optik_1611_natur_nacht.png` | T1 |
| **T5 Lite-Tagtiere** (11 + Schmetterling) | `webclient/natur_tag.js`, Bilder `optik_1611_lite_natur_<tag-ids>.png` | T2 |
| **T6 Lite-Nachttiere** (12 + Sternschnuppe) | `webclient/natur_nacht.js`, Bilder `optik_1611_lite_natur_<nacht-ids>.png` | T2 |
| **T7 Gleichlauf und Abschluss** | `game/tests/test_web_contract.gd` (`pruefe_natur`, Skriptliste), `game/tests/test_nature_flip_shot.gd`, Version 1.6.11 (`game/project.godot` `config/version`, `webclient/app.js` `VERSION`), Nachtrag in `docs/module/natur.md`, Flip-Bilder App und Lite; voller Bau `tools/build.ps1` | T1–T6 |

- **Reihenfolge:** T1 und T2 laufen parallel, danach T3–T6 parallel, zuletzt T7. Godot-Läufe ordnet der Mutex `Global\MauMauFlipGodot` von selbst.
- **Grenzen:** Keine Aufgabe ändert Dateien einer anderen. T3–T6 tragen ihre Tiere nur in ihre eigene Datei ein (App über `make(id)`, Lite über `M.Natur.art`). Kern und Tests finden sie von selbst.
- **Abnahme je Aufgabe:** eigene Tests grün, Kontrollbilder angesehen. Bei T1 außerdem `test_fun_fx`, `test_ui_tease` und `test_ui_table_*` grün, bei T2 `lite_necken.html` grün.
- **Nicht in den Aufgaben:** Gerätetest, AGENTS.md, Release und Tags (Hauptsitzung). Die Agenten committen nicht. `tools/release.ps1` erst, wenn kein Agent mehr im Arbeitsbaum ändert.

## 10. Risiken

- **Ablenkung:** Abhilfe sind der Takt von etwa 3 min, nur zwei Ereignisse über Karten (nie im eigenen Zug), Abgang bei wichtigen Momenten und `ruhig` bei „reduziert“. Ist es zu viel, `abstand_s` anheben (ein Wert, im Lite gespiegelt und durch den Vertragstest abgesichert).
- **Leistung** (S10, ältere iPhones):
  - Zeichnen nur, solange ein Ereignis läuft. Im Lite nur `transform`/`opacity`, kein Weichzeichner.
  - Das Polarlicht ist das teuerste Ereignis (additive Polygone bzw. 3 Verläufe). Fällt es am S10 auf, dort weniger Abschnitte.
- **Verwechslung mit Spielsignalen:**
  - Komet (siehe 22).
  - Regenbogen erst nach dem Flip-Banner.
  - Keine Zahlen, keine Texte.
  - An der Ablage keine Flächen in Kartenfarben (Motte graubraun).
- **Lite-Orte als Näherung** (Band-Ellipse, Mond gedreht): Das prüfen die Kontrollbilder. Bei Abweichung im Lite nachstellen, nicht in `tisch.js`.
- **Klassen-Cache:** Neue `class_name` erst nach Import. Deshalb `preload`/`load` an den Nahtstellen.
- **iPhone:** `mix-blend-mode` und SVG laufen in Safari. Ungetestet wie bisher.

## 11. Vorläufige Festlegungen (der Nutzer kann widersprechen)

1. **Takt:** Im Schnitt etwa ein Ereignis alle 3 min. Schmetterling und Sternschnuppe kommen dadurch seltener als bisher (etwa alle 20 statt alle 1–3 min).
2. **Keine eigene Einstellung.** „Effekte reduziert“ lässt nur die fünf ruhigen übrig. Ein Schalter „Natur-Überraschungen“ ließe sich später als eine Aufgabe nachrüsten (Einstellung, Menüs App und Lite, `.po`).
3. **Großer Modus und Lite hochkant:** aus.
4. **Über Karten** nur Biene (Handkarte) und UFO (Stapel), beide nur außerhalb des eigenen Zugs.
5. **Schnecke** auch beim eigenen Trödeln; sie kriecht am Plattformrand Richtung Trödler.
6. **„Tischrand“** heißt bei Spatz, Eule, Igel und Marienkäfer die Außenkante der Richtungs-Plattform.
7. **Vorführung** per 7 Tipps auf den freien Himmel (auch ein kleines Easter Egg) und `?natur=reihe` im Lite.
8. **Nach einem Flip zur Nacht** kommen mit Chance 0,4 Glühwürmchen, Fledermaus oder Eule, als Gegenstück zum Regenbogen.

## 12. Nachtrag: Umsetzung (Beta 1.6.12, 16.10.2026)

Umgesetzt wie oben, veröffentlicht als **Beta 1.6.12** (nicht 1.6.11; dort kam nur der Lite-Kern ohne Tiere mit). Die Kontrollbilder heißen deshalb `optik_1612_*` statt `optik_1611_*`.

**Stand der Aufgaben:** T1–T7 fertig. Tests im Bau: `test_nature_fx` (Kern, Dauerlauf 10 h), `test_nature_tag`, `test_nature_nacht`, `test_web_contract` (`pruefe_natur`), Lite `webclient/test/lite_natur.html` (`Invoke-WebNatureTest`, alle 25 Arten angemeldet). Voller Bau `tools/build.ps1 -Target Android` grün (110 Testskripte, `builds/MauMauFlip-1.6.12.apk`), `run_webtest.sh --nur-test` grün.

**Gleichlauf (8.3, `pruefe_natur`):** Tabelle in `natur.js` gleich `NatureTable.DATA` (Vergleich mit sortierten Schlüsseln, bei Abweichung die erwartete Zeile), Ladereihenfolge `necken.js` < `natur.js` < `natur_tag.js` < `natur_nacht.js` < `tisch.js`, die drei Skripte im ausgelieferten `index.html` und in der Skriptliste der Übersetzungsprüfung, jede id ohne Bestand mit Tier in der App (`NatureFx.make`), jede id mit `N.art('<id>'`/`M.Natur.art('<id>'` im Lite, Haken in `app.js`, `table_view.gd` (`nature.mount` vor `fx`) und `fun_fx.gd` (`sky_auto`, `make_room`), Verbote in `natur*.js` und `scripts/ui/nature_*.gd` (Kommentare und SVG-Namensräume `http://www.w3.org/…` ausgenommen).

**Seit dem Entwurf neu:** Die App-Sternschnuppe zeichnet `shooting_star_fx.gd` (leuchtender Kopf, langer farbiger Schweif, Funken); sie läuft über die Bestand-Brücke im gemeinsamen Takt, ihr Aussehen ist unverändert. Die Lite-Sternschnuppe (`natur_nacht.js`) ist im selben leuchtenden Stil gezeichnet. Die Reaktionsleiste hat 5 Knöpfe (inkl. „Bäää“); in der App zählt sie samt Necken-Menü als Schutzfläche, im Lite meiden die Tiere auf dem Band sie selbst (`#nk-leiste`).

**Abweichungen vom Entwurf (in den Quellen begründet):**
- **Schnittstelle App:** `obstacles()` liefert `{Name: [Rect2]}`; `spawn(id, seed, opts)` gibt `bool` zurück, das Tier holt `creature()`. Anker heißen in der App anders als im Lite (Rect2 bzw. `{pos}/{deg}/{center}`), die Tabelle ist gleich.
- **Mau-Katze:** Erst fällt ihr Würfel, dann räumt die Natur den Platz (`make_room`), dann kommt die Katze im nächsten Takt.
- **Biene:** landet oben rechts auf der obersten (rechten) Handkarte statt auf der mittleren (dort läge der Eckindex der nächsten Karte); ihre Acht sucht eine freie Stelle statt (0,5 W; H − 300), Ein- und Abflug meiden alle Schutzflächen außer der Hand.
- **Wolke:** zieht von rechts zur Sonne und blendet dort aus (die Sonne liegt halb hinter den Knöpfen oben links).
- **Regenbogen:** Scheitel oben im Himmel, Füße bei ±0,46 W auf Höhe Tischmitte + 40 (im Lite als Ellipse), Deckkraft 0,36 statt 0,32.
- **Tempo und Größen:** Libelle, Pusteblume und Ballon schneller; Motte (×1,35), Lampion (×1,3), Igel (×1,3) in der App größer; im Lite kleine Tiere etwa ×1,5, damit sie am Handy erkennbar bleiben.
- **Viele Spieler:** Eule, Sternbild, Fledermaus, Satellit und Komet suchen sich innerhalb ihres Ankers eine freiere Stelle bzw. Bahn (bei 8 Spielern sind die Schultern der Plattform zugestellt).
- **Hülle:** Bei Schwärmen und großen Gebilden (Pusteblume, Wolke, Regenbogen) gibt `bounds()` nur die sichtbare Hülle zurück.

**Kontrollbilder:** App je Tier `optik_1612_natur_<id>.png`, Übersichten `optik_1612_natur_tag.jpg`/`_nacht.png`, ruhige Varianten, 8 Spieler, 1600 × 900; Flip `optik_1612_natur_flip.jpg` (`game/tests/test_nature_flip_shot.gd`: Tag mit Marienkäfer → Flip, der Käfer geht in ≤ 0,45 s ab → Glühwürmchen → Flip zum Tag mit Regenbogen). Lite je Art `optik_1612_lite_natur_<id>.png` (`tools/webtest/natur_bilder.ps1 -Stand 1612`), Flip `optik_1612_lite_natur_flip_tag_nacht.jpg`, `_gluehwuermchen.png`, `_nacht_tag.png` (Chrome headless über `cdp.ps1`, `?natur=test`, `MMF.Natur.sicht([{e:'flip'…}])`).

**Offen:** Gerätetest (8.5, S21/S10 gesperrt, Vorführung per 7 Tipps, Ruckeln am S10), iPhone/Safari ungetestet.

## 13. Nachtrag: Beta 1.6.15 – UFO bleibt, vier neue Ereignisse (23.10.2026)

Nutzerwünsche vom 23.10.2026: „Das Ufo bitte nicht so einfach verscheuchen lassen“ und „Ein Feuerwerk als zufällige Aktion bei Nacht; Ein Astronaut schwebt neben dem Mond als zufällige Aktion bei Nacht; Ein Hoppelhase hüpft durch das Bild als zufällige Aktion bei Tag; In der unteren rechten Ecke kommt mit einer Welle für ein paar Sekunden ein Strand ins Bild und eine Palme wächst. Als zufällige Aktion bei Tag“.

- **Tabelle:** 29 Einträge (14 Tag, 15 Nacht). Neu `hoppelhase` (Zufall 2), `strand` (Zufall 1, je Partie 1, neuer Ort `ecke_unten_rechts`), `feuerwerk` und `astronaut` (je Zufall 1, je Partie 1). UFO: `scheu: false`, `tipp: "ausweichen"`, Dauer 7–8 s. Die neuen Einträge stehen am Ende ihrer Seite, die Vorführung (4.7) zeigt sie also nach den bisherigen.
- **UFO** (3.3 Nr. 18): nicht mehr scheu, `draw` vertreibt es nicht mehr (`PLACE_GO`/`ORT_WEG` nur noch `shuffle`), 1. und 2. Tipp: Ausweichen, 3. Tipp: davon.
- **Kern:** `NatureCreature.tap_limit()`, `tap_count()`, `add_tap(p)`/`taps`; `NatureFx.tap` lässt bis zu `tap_limit()` Reaktionen zu. Lite: `inst.tippMax`, `c.tipps` im Kern (auch in `zustand()`). Anker `ecke_unten_rechts` in `NatureFx.anchors()` und `_orte()`.
- **Beschreibungen:** 3.2 Nr. 24 (Hoppelhase), Nr. 25 (Strand), 3.3 Nr. 26 (Feuerwerk), Nr. 27 (Astronaut).
- **Tests:** `test_nature_fx` (29 Einträge, UFO nicht scheu, bleibt bei `draw`, geht bei `shuffle`, Anker), `test_nature_tag` (nature_check für alle 13 Tagtiere, Schreck-Sprung, Palme schüttelt sich und verliert eine Kokosnuss, Sand allein nimmt keinen Tipp, Hase von einer Seite zur anderen mit Stauchen/Strecken und kaum unter der Hinweisleiste, Strand in der Ecke, Palme zwischen Hand und Mau-Knopf, am Ende alles weg), `test_nature_nacht` (14 Nachttiere, UFO-Ausweichen bestimmt und erst der 3. Tipp vertreibt es, Feuerwerk-Knall an der Tippstelle und höchstens zwei, Astronaut-Salto), `test_web_contract` (29 Ereignisse), Lite `lite_natur.html` (29 Einträge, UFO bleibt bei `draw`/Stapel-Tipp, neuer Block mit echten Arten und echtem Druck auf eine freie Stelle).
- **Kontrollbilder:** Die Shot-Tests schreiben jetzt `optik_<STAND>_…` (Umgebung `STAND`, Standard 1615; `SHOT_DIR` auch für die Tagbilder); `tools/webtest/natur_bilder.ps1` kann mit `-TippNach <s>` die Reaktion zeigen (Zusatz `_tipp`) und macht für Strand und Feuerwerk zusätzlich ein Desktop-Bild. Abgelegt als JPEG: App `optik_1615_natur_{hoppelhase,strand,ufo,feuerwerk,astronaut}.jpg`, Übersichten `optik_1615_natur_tag.jpg`/`_nacht.jpg`, `optik_1615_natur_8spieler.jpg`, `optik_1615_natur_nacht_8sp.jpg`, `optik_1615_natur_900.jpg`; Lite `optik_1615_lite_natur_{hoppelhase,strand,feuerwerk,astronaut}[_tipp].jpg`, `optik_1615_lite_natur_ufo_tipp.jpg`, `optik_1615_lite_natur_strand_desktop.jpg`.
- **Offen:** Gerätetest (S21/S10, Ruckeln des Feuerwerks am S10), iPhone/Safari. Im Lite-Desktop-Fenster (Bühne schmaler, z. B. 1280 × 800) reicht die Palmenkrone hinter das rechte Ende der Plattform; sie liegt dahinter (Ebene hinten), das wirkt wie „der Tisch steht am Strand“. Der Hase ist im Lite vorn auf dem Rand nicht antippbar, solange er über `#hand-zone` (untere 270 px) hüpft – an den Seiten schon.
