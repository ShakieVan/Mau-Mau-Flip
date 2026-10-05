# Modul F1a – Hand und Kartenbaustein

Stand 04.10.2026, Nachtschicht. Die Hand ist vollständig umgesetzt und mit Kontrollbildern geprüft. Grundlage: `docs/recherche/06_hand_ux_effekte.md` Abschnitte 1 und 2, Nutzerentscheidungen 8, 11–13 und 18 in `AGENTS.md`, Zielbild `art/entwurf/a-papier-neon/hand.png`.

## Dateien

| Datei | Inhalt |
|---|---|
| `game/scripts/ui/hand_layout.gd` | `HandLayout`: reine Rechnungen (Stufen, Fischauge, Fächer, Lupe, Karussell, Schwung, Gummiband, Federn, Geschwindigkeit, Gestenerkennung) |
| `game/scripts/ui/card_sort.gd` | `CardSort`: Sortierung Farbe/Wert/Punkte/manuell, Gruppenlücken |
| `game/scripts/ui/hand_view.gd` | `HandView` (Node2D): die Hand mit Federn, Gesten, Großansicht und „?“ |
| `game/scripts/ui/card_view.gd` | `CardView` erweitert (API kompatibel) |
| `game/scenes/dev/hand_demo.tscn`, `hand_demo.gd` | Entwicklerszene mit angedeutetem Tisch |
| `game/tests/test_ui_hand_layout.gd`, `test_ui_hand_gesture.gd`, `test_ui_hand_sort.gd`, `test_ui_hand_view.gd` | Tests, headless |
| `game/tests/test_ui_hand_shots.gd` | Kontrollbilder mit echtem Renderer |
| `docs/module/F1a_*.png` | Kontrollbilder |

## Umgesetzt

### Drei Stufen

- **Fächer (bis 7 Karten):** Kreisbogen, Drehung höchstens ±12°. Abstand 48–56 dp, jede Karte direkt antippbar.
- **Lupe (8–15):** dichter Fächer mit höchstens 40 dp Abstand.
  - Finger aufsetzen und seitlich gleiten: Die Karte unter dem Finger hebt sich (+24 dp, ×1,15) und liegt obenauf.
  - Die Nachbarn weichen aus. Die Lücken um den Finger öffnen sich gaußförmig, die Gesamtbreite bleibt im Handbereich.
  - Am PC wirkt die Lupe auch beim Darübergleiten mit der Maus. Auf Touchgeräten ist das abgeschaltet.
- **Bogen-Karussell (ab 16, zurück zur Lupe erst bei ≤ 13):**
  - Fischauge s(d) = s_min + (s_max − s_min)·exp(−(d/σ)²) mit s_max = 52 dp, σ = 2,5. Die Positionen sind die Stammfunktion (mit erf), deshalb springt beim Scrollen nichts.
  - Die Karten liegen auf einem Kreisbogen, die Drehung folgt dem Bogen.
  - Zum Rand werden sie kleiner (bis 0,85), abgesenkt und auf 75 % abgedunkelt.
  - s_min (≤ 10 dp) schrumpft bei vielen Karten so weit, dass alle Karten als Streifen sichtbar bleiben (geprüft bis 60 Karten).
- **Querformat:** Die Kartenmitte ruht auf der Unterkante des Handbereichs, sichtbar ist die obere Hälfte mit dem Eckindex. Die Kartenbreite beträgt 189 px wie im Entwurf.
- **Gruppenlücke:** 6 dp zwischen Farbgruppen. Sie ist auch im Karussell stetig und wird zum Rand mit dem Fischauge gestaucht.

### Bewegung

- **Federn statt Tweens:**
  - Jede Karte folgt ihrem Layoutziel mit einer exakt gelösten gedämpften Feder (ω = 17, ζ = 0,8), stabil bei jedem Zeitschritt.
  - Neue Karten, Umsortieren, Stufenwechsel und Flip mitten im Scrollen ruckeln deshalb nie.
- **Umsortieren:** Die Karten starten mit 15 ms Versatz. Weite Wege (≥ 3 Plätze) laufen über einen Bogen von 20 dp, damit Karten nicht durcheinander hindurchfahren.
- **Schwung:**
  - Die Geschwindigkeit stammt aus den Touchproben der letzten 100 ms (gewichtetes Mittel).
  - Projektion nach WWDC18 mit Abklingrate 0,998/ms.
  - Ziel ist die nächste Kartenmitte. Eine kritisch gedämpfte Feder (ω = 5 > 1/τ) fährt ohne Überschwingen dorthin und übernimmt dabei die Wischgeschwindigkeit.
- **Gummiband:** (1 − 1/(x·0,55/d + 1))·d mit d = Handbreite. Beim Loslassen federt die Hand zurück.
- **Schwung-Neigung (Soll):** Die Karussellkarten neigen sich gegen die Bewegung, umgesetzt als Scherung. Höchstens 12°, federt zurück.
- **Haptik-Raster:** 10 ms bei Stärke 0,2, wenn eine Karte die Mitte kreuzt, höchstens alle 35 ms.
- **Austeilen und neue Karten:**
  - In eine leere Hand fliegen die Karten nacheinander ein (50 ms Abstand).
  - Karten, die zu einer bestehenden Hand dazukommen, fliegen vom Nachziehstapel ein und schimmern 3 s: dreimal ein Glanzstreifen (Shader, nur solange er läuft) und ein warmes Glühen, das ausklingt.
- **Flip (Seitenwechsel):**
  - Die Karten wenden sich als Welle von links nach rechts: 20 ms Versatz, je Karte 200 ms.
  - Danach 100 ms Pause, dann federt die Hand in die Sortierung der neuen Seite.

### Gesten

`HandLayout.Gesture` ist eine Zustandsmaschine. Eingaben sind Zeit und Weg, die Toleranz beträgt 8 dp.

| Geste | Wirkung |
|---|---|
| Tipp | hebt an (+23 dp, goldenes Glühen), `selection_changed` |
| zweiter Tipp oder Doppeltipp | spielt aus. Nicht spielbar: Karte schüttelt „nein“ (3 Schwingungen, 250 ms), Doppelbrummen, `play_denied` |
| Tipp ins Leere | hebt die Auswahl auf |
| Ziehen nach oben (\|dy\| > 1,2·\|dx\|) | Karte folgt dem Finger; wird scharf (Glühen) ab 25 % Bildhöhe, begrenzt auf 70–110 dp, oder per Schnippen > 1200 dp/s innerhalb ±35°; Zurückziehen bricht ab |
| seitlich | Lupe gleiten (B) bzw. Karussell drehen (C); danach deutlich nach oben = die Karte unter dem Finger ausspielen |
| Halten 350 ms | **Großansicht:** Die Karte steigt ×1,4 vergrößert über den Finger, der Tisch wird abgedunkelt, Pfeile deuten oben/links/rechts an, darunter erscheint im frei gewordenen Raum ein „?“ |
| Halten + oben | ausspielen |
| Halten + seitlich | umsortieren (andere Karten machen Platz, am Karussellrand dreht es weiter); schaltet auf „manuell“ (`sort_mode_changed`, `order_changed`) |
| Halten + kurz nach unten (~40 dp) | „?“ wird scharf (golden, Puls), Loslassen = `help_requested(id, face)`. Am unteren Bildrand genügt ein kürzerer Zug |
| Halten + loslassen | Großansicht bleibt offen, mit „?“-Knopf daneben. Tipp auf „?“ = Hilfe, auf der Karte nach oben wischen = ausspielen, Tipp daneben = schließen |

Ausspielen ist **optimistisch**: Die Karte verlässt die Hand sofort und fliegt zu `play_target`, falls gesetzt.
- `cancel_play(id)` holt sie zurück und schüttelt sie (Host lehnt ab).
- Ohne Antwort kehrt sie nach 4 s zurück.
- `take_card(id)` übergibt den Knoten an die Regie.

### Sortieren (`CardSort`)

- **Farbe:** feste Farbfolge je Seite, Zahlen aufsteigend, dann Aktionen.
- **Wert:** gleiche Zahlen nebeneinander, dann Aktionen.
- **Punkte:** aufsteigend nach Restpunkten.
- **Joker** stehen in jeder automatischen Sortierung rechts.
- **Manuell:** Die Reihenfolge bleibt, neue Karten kommen rechts dazu.
- Sortiert wird nach der aktiven Seite (`face`). Die Punktwerte sind geprüft: Summe hell 1280, dunkel 1480.

### Eigene Rückseiten

`set_peek_backs(true)` wendet alle Karten als Welle zur Rückseite. Ausspielen und Anheben sind dann gesperrt, Scrollen und Großansicht gehen weiter.

### CardView (erweitert, API kompatibel)

- **Innerer Körper:** Wende, Schütteln und Schimmern wirken auf einen inneren Körper. `position`, `rotation`, `scale` und `skew` der Karte gehören dem Besitzer, die Federn der Hand stören deshalb keine Wende.
- **Neu:**
  - `flip_to(front, dur, delay)` (eindeutig auch mitten in einer Wende)
  - `shake()`, `shimmer(dauer)`, `is_flipping()`, `is_shimmering()`
  - `brightness`, `elevation` (Schatten weiter und weicher, wenn angehoben), `set_glow(color)`
  - `static soft_texture(sigma)`
- **Schatten und Glühen:** einmal erzeugte weiche Kartenformen (Gaußrand). Das Glühen ist additiv wie Neon auf dem Nachtgrund. Spielbar: feines cremefarbenes Glühen. Gewählt: goldenes Glühen nach dem Entwurf.
- **Unverändert:** `setup`, `current_key`, `width`, `card_size`, `set_state`, `show_side`, `flip`, `global_polygon`, `contains_global_point`, Signal `flipped`. `test_card_view.gd` läuft weiter.

## Schnittstelle

```gdscript
var hand := HandView.new()          # Node2D, im Ursprung des Tisches
hand.layout_rect = Rect2(270, 500, 1060, 220)   # Handbereich (Standard; Knöpfe links/rechts bleiben frei)
hand.play_target = ablage_global    # optional: ausgespielte Karte fliegt dorthin
hand.spawn_from = stapel_global     # optional: neue Karten kommen von dort
hand.set_cards([{id, face, back}])  # face = aktive Seite
hand.set_playable(ids)
hand.set_sort_mode("farbe" | "wert" | "punkte" | "manuell")
hand.set_peek_backs(on)
hand.set_enabled(on)
```

**Signale laut Plan**
- `play_requested(id, drop_global)`
- `help_requested(id, face)`
- `drag_started(id, face)`, `drag_moved(global)`, `drag_ended(id, global, played)`
- `order_changed(ids)`
- `selection_changed(id)`

Positionen sind global und geben die Fingerposition an.

**Zusätzliche Signale**
- `play_denied(id)`: Der Tisch zeigt den Hinweis „Passt nicht …“.
- `sort_mode_changed(mode)`: manuelles Umsortieren hat die Automatik abgeschaltet.
- `big_view_changed(id)`: −1 = geschlossen.

**Zusätzliche Methoden**
- `play_selected()`: Tipp auf die Ablage. Funktioniert auch kurz nachdem ein Tipp außerhalb die Auswahl aufgehoben hat.
- `cancel_play(id)`, `take_card(id) -> CardView`
- `select(id)`, `close_big_view()`, `is_big_view_open()`, `get_order()`, `get_selected()`, `get_mode()`, `get_scroll()`, `card_view(id)`, `card_global_position(id)`
- `deselect_on_outside`, `enforce_playable`, `dim_unplayable`, `haptics`
- Testzugang: `touch_down/touch_move/touch_up(lokal, t_ms)`, `step(dt)`, `clock_ms`

**Adapter für `TableView` (F1b)** mit den dort erwarteten Methoden:
- `apply_view(view)`
- `take_card(id)`
- `receive_card(card, from_global)`
- `landing_point()`
- `flip_wave(delay, step, dur, faces)`
- `set_input_locked(on)`
- `own_color_counts()`

**Reine Funktionen in `HandLayout`**
- `layout(n, scroll, focus, mode, width, height[, gaps]) -> Array[Transform2D]`
- `choose_mode(n, current)`
- `fisheye`, `fisheye_offset`, `index_at`, `shade`
- `project`, `snap`, `rubber_band`, `rubber_scroll`, `spring`
- `Velocity`, `Gesture`

## Abweichungen vom Plan (mit Begründung)

1. **`HandLayout.layout` hat einen optionalen 7. Parameter `gaps`** (Indizes der Gruppenlücken). Die 6-dp-Lücke gehört ins Layout, sonst stimmen Treffer und Index nicht.
2. **„Punkte“ sortiert aufsteigend:** teure Karten rechts.
   - Die Recherche nennt „teure nach vorn“, der Auftrag verlangt „Joker rechts“.
   - Aufsteigend erfüllt beides widerspruchsfrei: Die teuersten Karten, also die Joker, stehen außen rechts, wie in den anderen Modi.
3. **Großansicht = die gehaltene Karte selbst,** vergrößert über dem Finger, keine zweite Karte.
   - So entsteht der im Auftrag beschriebene frei gewordene Raum für das „?“ direkt unter der Karte.
   - Aus der offenen Großansicht kann man zusätzlich nach oben ausspielen.
4. **Schwelle zum Ausspielen:** 25 % der Bildhöhe, begrenzt auf 70–110 dp (180 px bei 720 px Höhe). Auf hohen Bildschirmen (Tablet, headless 1600×1600) wäre der Weg sonst unbequem lang.
5. **Nicht spielbare Karten:** auf 84 % abgedunkelt statt 70 %, und nur, solange überhaupt etwas spielbar ist, also nur im eigenen Zug.
   - Der Entwurf `hand.png` dunkelt gar nicht ab. 70 % wirkte auf dem Nachtgrund grau.
   - Nicht umgesetzt: Entsättigung.
6. **Zusätzliche Signale und Methoden** (siehe oben), alle rein ergänzend.
7. **Karussell-Mindestabstand** kann unter 10 dp fallen (bis 1,5 dp), damit bei 25+ Karten alle als Streifen sichtbar bleiben, wie die Recherche verlangt.
8. **CardView-Wende** wirkt auf den inneren Körper statt auf `scale` des Knotens. Optisch gleich, aber Besitzer dürfen `scale` jetzt frei setzen.

## Tests

Alle headless über `tools/godot_run.ps1 … -Headless`:

| Test | Ergebnis | Inhalt |
|---|---|---|
| `test_ui_hand_layout.gd` | **79 ok** | Stufen und Hysterese; Fischauge samt Stammfunktion; Fächer: Symmetrie, ±12°, ≥ 48 dp; Lupe: +24 dp, ×1,15, Nachbarn weichen, bleibt im Bereich; Karussell: Mitte, Rand 0,85/75 %, alle sichtbar bei 16/25/40/60; Stetigkeit über Lücken (größter Sprung < 0,5 px); Gruppenlücke 6 dp; Streifen-Index; Projektion; Einrasten; Gummiband; Federn (ohne Überschwingen, stabil bei dt = 0,5); Geschwindigkeit |
| `test_ui_hand_gesture.gd` | **42 ok** | Tipp, Doppeltipp (Zeit und Ort), Toleranz, Winkel, Schwelle, Zurückziehen, Schnippen (Tempo und ±35°), Halten 350 ms, Halten + oben/seitlich/unten, „?“ scharf ab 40 dp bzw. kürzer am Rand, Gleiten → hochwischen |
| `test_ui_hand_sort.gd` | **21 ok** | Zerlegen der Schlüssel, Punkte, Summen 1280/1480, Farbe hell und dunkel, Wert, Punkte, Joker immer rechts (60 Zufallshände), Lücken, manuell |
| `test_ui_hand_view.gd` | **74 ok** | HandView mit Testuhr: Austeilen, Reihenfolge, Tipp/Doppeltipp/Nein, optimistisches Ausspielen und `cancel_play`, Wischen (Schwelle, Abbruch, nicht spielbar), Großansicht → „?“ per Zug und per Knopf, Ausspielen aus der offenen Großansicht, Umsortieren → manuell, neue Karte (rechts bzw. einsortiert, schimmert), Ausblenden, Stufenwechsel 12/16/14/13, Lupe, Karussell (Schwung, Einrasten, Gummiband, Tipp dreht zur Mitte), Flip-Welle und Neusortierung, Rückseiten, Eingabe aus, Abwählen und `play_selected`, `take_card`, 4-s-Rückkehr, Adapter (`apply_view`, `receive_card`, `landing_point`, `flip_wave`, `own_color_counts`, `set_input_locked`) |
| `test_card_view.gd` (bestehend) | **5 ok** | läuft unverändert weiter |

**Kontrollbilder:** `tools/godot_run.ps1 -Script res://tests/test_ui_hand_shots.gd -Resolution 1600x720` (einzeln mit `-EnvPairs 'SHOT=<name>'`). Es entstehen:

| Bild | Inhalt |
|---|---|
| `F1a_hand5.png` | Fächer mit 5 Karten |
| `F1a_hand12.png` | Lupe mit 12 Karten, Finger auf der 7. Karte |
| `F1a_hand25.png` | Karussell mit 25 Karten |
| `F1a_schwung.png` | Karussell mitten im Schwung, Neigung |
| `F1a_angehoben.png` | angehobene Karte mit goldenem Glühen |
| `F1a_grossansicht.png` | gehalten, „?“ scharf |
| `F1a_grossansicht_knopf.png` | Großansicht offen mit „?“-Knopf |
| `F1a_rueckseiten.png` | Rückseiten-Ansicht |
| `F1a_dunkel.png` | dunkle Seite |

Alle angesehen und nachgebessert:
- Kein Schimmern beim ersten Austeilen.
- Engeres Glühen.
- Handbereich frei von den Knöpfen links.

**Entwicklerszene:** `res://scenes/dev/hand_demo.tscn`. Tasten:

| Taste | Wirkung |
|---|---|
| 1–6 | 5/9/12/16/25/40 Karten |
| S | Sortierung |
| B | Rückseiten |
| F | Flip |
| N | ziehen |
| P | alles spielbar |
| E | Eingabe |
| D | Status |

## Offene Punkte

- **Gerätetest auf S21/S10:**
  - Gestenschwellen, dp-Umrechnung (`_compute_dp` aus dpi und Fenstermaßstab, begrenzt auf 1,5–2,6 px/dp) und Haptikstärken sind nur am PC geprüft.
  - Federkonstanten auf dem Gerät nachstimmen.
- **Nicht umgesetzt (Soll/Kann aus der Recherche):**
  - Übersichtsblatt bei 25+ Karten (Soll)
  - Randmarken für spielbare Karten außerhalb des Blicks (Soll; im Karussell bleiben alle Karten sichtbar und spielbare glühen auch am Rand)
  - Kartenschnarren als Ton
  - manuelle Reihenfolge je Seite merken (Kann)
  - Entsättigung nicht spielbarer Karten
- **Für F1b (Tisch):**
  - „Spielen“-Hinweis über der Ablage bei `selection_changed`.
  - Tipp auf die Ablage ruft `play_selected()` auf.
  - Farbfelder des Wünschers über `drag_started`/`drag_moved`/`drag_ended`.
  - Hinweistext bei `play_denied`.
  - Bedienelemente außerhalb von `layout_rect` halten (die Hand nimmt Berührungen im ganzen Handbereich an).
  - `help_requested` öffnet die Kartenhilfe.
- Kein Bedarf an `project.godot`, `export_presets.cfg` oder `.gitignore`.
