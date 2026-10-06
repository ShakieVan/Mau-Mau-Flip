# Modul F1b – Tisch, Regie, Effekte, Bausteine

Stand 04.10.2026, Nachtschicht (Beta 0.1.1, Phase 1: Bausteine mit Beispieldaten, ohne Regelwerk). Grundlage: `docs/BETA1_PLAN.md` Abschnitte 4 und 7, `docs/recherche/06_hand_ux_effekte.md` Abschnitte 3–7, Zielbild `art/entwurf/a-papier-neon/hand.png`.

## Umgesetzt

| Baustein | Datei (`game/scripts/ui/`) | Klasse |
|---|---|---|
| Tisch | `table_view.gd` | `TableView` (Control) mit inneren Klassen `PileView`, `ColorRingView`, `ColorMark` |
| Tischregie | `director.gd` | `Director` |
| Geometrie (reine Funktionen) | `table_layout.gd` | `TableLayout` |
| Gegnerplatz | `opponent_seat.gd` | `OpponentSeat` |
| Effekte | `effects.gd` | `TableEffects` (innere Klassen `TextFx`, `BubbleFx`, `RingFx`, `RaysFx`) |
| Joker-Strahlen | `joker_rays.gd` | `JokerRays` |
| Hintergrund Tag/Nacht | `table_background.gd` + `assets/shaders/table_background.gdshader` | `TableBackground` |
| Richtungsring | `direction_ring.gd` | `DirectionRing` |
| Farbwahl | `wish_picker.gd` | `WishPicker` (siehe Abweichungen) |
| Kartenhilfe | `help_popup.gd` | `HelpPopup` |
| Sichtschutz | `handover_screen.gd` | `HandoverScreen` |
| Großansicht Rückseiten | `backs_viewer.gd` | `BacksViewer` |
| Rundenende/Sieg | `round_end_view.gd` | `RoundEndView` |
| Mau-Knopf | `mau_button.gd` | `MauButton` |
| Pillenknopf | `pill_button.gd` | `PillButton` |
| Hinweisleiste und Meldungen | `toast.gd` | `Toast` |
| QR-Code | `qr_code.gd` | `QrCode` |
| Thema | `ui_theme.gd` → `res://assets/ui/theme.tres` | `UiTheme` |
| Farben, Schriften, Symbole, App-Zugriff | `ui_palette.gd`, `ui_fonts.gd`, `ui_icons.gd`, `ui_app.gd` | `UiPalette`, `UiFonts`, `UiIcons`, `UiApp` |
| Beispieldaten | `table_samples.gd` | `TableSamples` |
| Demo | `game/scenes/dev/table_demo.tscn` + `table_demo.gd`, `demo_hand.gd` | `TableDemo`, `DemoHand` |
| Randpuls | `assets/shaders/edge_pulse.gdshader` | – |

### Tisch (`TableView`)

- **Layout nach Entwurf** (1600×720, passt sich der Größe an): Nachziehstapel links der Mitte zeigt die Gegenseite der obersten Karte (`draw_back`) samt Stapelkanten und „Stapel · 47“; Ablage spiegelbildlich rechts mit leuchtendem Farbring (bis 3 Karten leicht verdreht); aktuelle Farbe dazwischen als Formsymbol + Wort; Richtungsring aus zwei Leuchtbögen mit Pfeilspitzen und wandernden Winkeln; Hinweisleiste über der Hand („Du bist dran.“ hervorgehoben); Pillen „Farbe“ (Sortieren) und „Rückseiten“ links unten, Mau! rechts unten; Knöpfe „Behalten“, „Anzweifeln“, „Annehmen“ nach `hints`.
- **Plätze relativ zum eigenen Platz** nach 06 Abschnitt 3.2 (r = (Platz − ich) mod n, φ = φ0 + θ·(360° − 2φ0)/360°, φ0 = 55°): nur gedreht, nie gespiegelt – der nächste Spieler sitzt links. 2–6 Spieler mit Mini-Fächer der Rückseiten (Breite je Spielerzahl, Überlänge als „+n“), ab 7 Spielern Abzeichen auf zwei versetzten Ebenen mit Farbbalken (Segmente je Farbe mit Symbol und Zahl, Marken für Joker/+5/Flip). Hat ein Gegner nur noch eine Karte, wird deren Rückseite groß gezeigt (auch im Abzeichen). Rückseiten verdeckt (`backs_visible=false` bzw. leere `backs`) → neutrale Rückseite `rueckseite`.
- **Kopfzeile je Gegner**: Avatar (Farbe je Platz, Initiale, „KI“-Marke für Computergegner), Name, Kartenzahl als Pille; pulsierender Ring am Zug, „gleich dran“ beim nächsten, der noch mitspielt (Fertige übersprungen, `TableView.next_seat`), „getrennt“, Punkte bei `points500`, „Mau!“-Marke, Platz bei „bis zum Letzten“, roter „Erwischt!“-Knopf (`hints.catch`), Aussetzen = Avatar grau mit schlafender Katze.
- **Tipp auf eine Gegnerhand** öffnet die Großansicht der Rückseiten (`BacksViewer`, wischen mit Schwung und Gummiband, Tipp schließt) – nur wenn sichtbar.
- **Eingaben**: Tipp auf den Stapel = `{a:"draw"}` (nur mit `hints.can_draw`), Erwischen = `{a:"catch", target}`, Mau-Knopf = `{a:"mau"}` (spielt den Mau-Ton nur auf diesem Gerät), Knöpfe = `keep`/`challenge`/`accept`, Rundenende = `next_round`, Farbrad bei `hints.need_color` = `{a:"color", color}`. Nicht verbrauchte Eingaben laufen weiter zu `_unhandled_input` (HandView).
- **Tag/Nacht**: Hintergrund-Shader mit Uniform `tageszeit` – Tag: Papier mit Sonnenstrahlen, Korn und Sonne oben links; Nacht: Verlauf wie im Entwurf mit Sternen und Mondsichel oben rechts; dazwischen Dämmerung, die Sonne sinkt, der Mond steigt. Die Karten werden nie abgedunkelt. Schrift- und Knopffarben wechseln steil in der Mitte (nie grau auf Dämmerung).

### Tischregie (`Director`)

Warteschlange aus Ereignissen und Sichten; `TableView.handle_state(events, view)` reiht ein, nach den Ereignissen folgt der Abgleich `apply_view(view)` (die Sicht ist maßgeblich). Rückstand > 3 → doppeltes Tempo, > 8 → Effekte überspringen (`skip_event`) und sofort die letzte Sicht setzen, auch mitten in einer laufenden Animation. Reine Buchungen ohne Animation (`Director.quiet_events`, von der `TableView` gesetzt: `turn`, `keep`, `accept`, `choose_color`, `pass`, `round_start`, `start`) zählen nicht zum Rückstand (06.10.2026; sonst lief z. B. jeder Glücksspiel-Treffer mit Wurf, Ziehen, Einsatz zurück und `turn` im doppelten Tempo). `upcoming_view()` liefert die Zielsicht, damit Flüge die richtigen Seiten zeigen (Rückseiten-Mehrfachmengen alt/neu). `flush()` setzt alles sofort.

### Effekte (je Ereignis aus Abschnitt 4)

| Ereignis | Darstellung |
|---|---|
| `play` | Karte fliegt im Bogen von der Hand bzw. aus dem Gegnerfächer zur Ablage; Gegnerkarten wenden in der Flugmitte von der Rückseite zum Gesicht; Landung mit Stauchen, Papierstaub (Tag) bzw. Neonfunken (Nacht), Ton „karte“, Haptik beim eigenen Zug |
| `draw` | Karten fliegen vom Stapel; eigene Karten wenden zum Gesicht, Gegner sehen die sichtbare Seite; der Stapel zeigt zwischendurch die nächste Gegenseite; ab 2 Karten bzw. nach Ziehkarte „+N“-Stempel am Opfer, bei +5 Schockwelle und Wackeln (nur beim Opfer) |
| Farbjagd | Spielautomat: Takt von 300 auf 90 ms, am Ende „Treffer!“ mit Funken in der Zielfarbe |
| `skip` | „Zzz“ steigt auf, Avatar 1 s grau mit schlafender Katze (eigener Platz: „Du setzt aus“) |
| `skip_all` | Komet läuft auf einer Catmull-Rom-Kurve einmal um den Tisch, die Avatare werden der Reihe nach grau, dann „Nochmal du!“ |
| `reverse` | Ring bremst auf 0, steht kurz und läuft mit Überschwinger rückwärts an (Pfeilspitzen schrumpfen und wachsen in neuer Richtung), oberste Ablagekarte dreht sich 360° |
| `color` | Farbwelle läuft als Ellipse über den Tisch, Farbring und Farbsymbol färben sich um |
| `flip` | Drehbuch 06 Abschnitt 4.4 (1,6 s; reduziert 0,7 s): Einatmen-Zoom 3 %, Ablage wendet, Welle nach Entfernung über Stapel (ganzer Stapel dreht), Gegnerfächer und Hand (20 ms Versatz, 200 ms je Karte), Himmel/Sonne/Mond/Sterne über `tageszeit`, Neon zündet einmal (kein Flackern), Haptik 60 ms + 120 ms, Eingaben gesperrt |
| `pending` | „+N“-Marke an der Ablage |
| `challenge` | Stempel „Bluff!“ bzw. „Sauber!“ |
| `mau` | Sprechblase mit Katzenohren über dem Avatar (eigener Platz: über dem Mau-Knopf), „Mau!“-Marke bleibt |
| `catch` / `penalty` | Stempel „Erwischt!“ / „Strafe +N“, beim Betroffenen ein einzelner roter Randpuls (kein Blinken) |
| `shuffle` | Stapel ruckelt (Riffle), Ton „mischen“ |
| `deal` | Karten fliegen reihum zu allen Plätzen |
| `round_over` / `game_over` | Konfetti in den Tagfarben, Sonnenstrahlen, Ergebniskarte mit Platzierungen, Runden- und Gesamtpunkten, „Nächste Runde“ (Platz 0 bzw. `can_next_round`) |
| `swap_hands` (Hausregel) | Alle Hände fliegen gleichzeitig auf Bögen über den Tisch zum nächsten Platz in Tauschrichtung, Bogenpfeile in der Mitte, Stempel „Kartentausch!“, Meldung mit Richtung (`TableHouseRules`, Einzelheiten `F2.md`) |
| `gamble_start`, `stake`, `gamble_roll`, `stake_back`, `stake_discard` (Hausregel) | Automat in der Tischmitte (Walze 0–10, großer Knopf), Einsatzstapel am Platz, Walze dreht ~1 s; „Nichts!“ bzw. große Zahl mit Strahlen; Einsatz zurück bzw. unter die Ablage (`GambleMachine`, `StakePile`) |
| `discard_color` (Hausregel) | Farbschwung vom Platz zur Ablage, die Karten fliegen schnell nacheinander unter die Ablegen-Karte und bleiben als kleiner Fächer darunter |

Effektstufe „reduziert“ (`App.settings` „effekte“, auch live über das Signal `changed`): alle Abläufe × 0,6, Flip 0,7 s, Teilchen × 0,35, keine Schockwelle, kein Wackeln, kein Zoom, Hintergrund ohne Daueranimation.

### Joker-Strahlen (`JokerRays`, Verfahren A aus 06 Abschnitt 4.3)

`JokerRays.attach(card_view, cards_above)`: Umriss als abgerundetes Rechteck mit analytischen Normalen abgetastet (≈ 70 Proben bei 120 px), je Bild gegen die Umrisse der darüberliegenden Karten geprüft (`Geometry2D.is_point_in_polygon`); nur sichtbare Proben speisen `CPUParticles2D` (`EMISSION_SHAPE_DIRECTED_POINTS`) und einen weichen Leuchtsaum entlang der sichtbaren Konturstücke. Farben der vier Farben der aktiven Seite je Viertel, weich übergehend und langsam drehend; Nacht additiv, länger, Flackern 2,5 Hz; Tag normal gemischt (additiv wäre auf Papier unsichtbar). `target_dir` neigt die Strahlen zum Zielspieler. Der Knoten ist erstes Kind der Karte und liegt damit unter ihr. Benutzt auf der Ablage (automatisch) und in der Demo-Hand; HandView kann ihn genauso anhängen.

### Weitere Bausteine

- **`WishPicker`**: `open_fields(side, counts)` fächert beim Ziehen eines Jokers vier Farbfelder um die Ablage auf (Farben der aktiven Seite, Formsymbol, Anzahl eigener Karten); `hover(global)` hebt das Feld unter dem Finger hervor (Haptik), `drop(global)` wählt (Signal `color_chosen`) oder bricht ab (`cancelled`). Rückfall `open_wheel()`: Farbrad als Dialog mit abgedunkeltem Tisch. `TableView.open_color_fields()/open_color_wheel()` übergeben die Farbzählung der Hand.
- **`HelpPopup`**: `show_help(face, title, bbcode_text)` – Großkarte links, Fraunces-Titel, Bricolage-Fließtext mit BBCode, „Verstanden“; Tipp daneben schließt.
- **`HandoverScreen`**: `show_for(name, from_seat, to_seat, n, discard_count, draw_count, side)`; deckt alles ab, zeigt keine Karten, nur Ablage- und Stapelzahl. Text und Pfeil aus der Sitzordnung (`direction_info`: links/rechts/gegenüber, Plätze dazwischen), z. B. „Gib das Handy nach links an Lena“. Aufdecken durch 500 ms Halten (Fortschrittsring), 350 ms Tippsperre. Signal `revealed`.
- **`MauButton`**: Zustände `IDLE`, `READY` (pulsierender rosa Kranz, Plopp), `CALLED` (gedämpft mit Haken), `HIDDEN`; Drücken staucht, Signal beim Loslassen im Knopf. Schrift passt sich der Kreisgröße an.
- **`Toast`**: Hinweisleiste (`show_hint(text, my_turn)`) und gestapelte Meldungen (`toast(text, "info"|"warn"|"error")`, gleiche Meldung nur einmal). `TableView.show_notice()` für `TableSource.notice`.
- **`QrCode`**: eigene Umsetzung nach ISO/IEC 18004, Byte-Modus (UTF-8), Fehlerkorrektur M, Versionen 1–10 (bis 213 Bytes), Reed-Solomon über GF(256), Verschränkung der Blöcke, Masken 0–7 mit Strafregeln N1–N4. `QrCode.encode(text).to_texture(module_px, border, dark, light)` bzw. `to_image()`.
- **Thema** `res://assets/ui/theme.tres` (aus `UiTheme.build()`): Papierfarben, Bricolage als Grundschrift (opsz 12), Fraunces für `TitleLabel`/`HeadingLabel`, Knöpfe als Pillen mit ≥ 84 px Höhe (≈ 48 dp quer), Variationen `PrimaryButton` (Sonnengelb), `DarkButton` (Nacht), `GhostButton`, `CardPanel`, `NightPanel`, `HintLabel`, `NightLabel`; dazu LineEdit, CheckBox/CheckButton, PopupMenu, ItemList, Schieber, Bildlauf, RichTextLabel, Reiter, Tooltip. Neu erzeugen: `godot_run.ps1 -Script res://tests/test_ui_table_theme.gd -Headless -EnvPairs 'SAVE_THEME=1'`.

### Demo `res://scenes/dev/table_demo.tscn`

Spielt 17 Schritte ab (4 Spieler): Blau 7, Aussetzen, Flip (Tag → Nacht), Wünscher → Lila, +5 an Tom, Mia „Mau!“, Ziehen, Richtungswechsel, Alle aussetzen, Farbjagd → Orange (Spielautomat), weitere Züge, eigenes „Mau!“, letzte Karte → Rundenende. Tasten: Leertaste nächster Schritt, A Automatik, R neu, F Farbrad, H Kartenhilfe, S Sichtschutz, E Effekte voll/reduziert. Die Hand ist eine einfache CardView-Reihe (`DemoHand`) mit dem Hand-Adapter.

## Schnittstelle

```gdscript
# TableView (Control, füllt den Elternbereich)
signal action(a: Dictionary)            # → TableSource.act(a)
signal sort_pressed / backs_pressed     # Knöpfe für die Hand
signal seat_tapped(seat: int)
func handle_state(events: Array, view: Dictionary)   # TableSource.state_changed
func apply_view(view: Dictionary)                    # Sofortabgleich (Start, Wiederverbinden)
func play_events(events: Array)
func set_hand(node: Node)                            # Hand in hand_layer (Weltkoordinaten = Tischkoordinaten)
func show_notice(text, kind := "info") / show_help(face, title, body)
func open_color_fields() / open_color_wheel()        # wish_picker.color_chosen(color)
func set_sort_label(text) / set_backs_active(on)
var reduced, can_next_round (-1 auto = Platz 0), director, wish_picker, mau_button, hint_bar, handover, help_popup, backs_viewer, round_end, fx, fx_top, hand_layer
func seat_node(seat) / discard_position() / draw_pile_position() / table_center() / discard_cards() / pile_top() / is_flipping()

# Hand-Adapter (alle Methoden optional; DemoHand setzt sie um)
apply_view(view)                         # Hand mit der Sicht abgleichen
take_card(id) -> CardView | {pos, rot, width}     # eigene Karte verlässt die Hand (HandView.take_card passt bereits)
receive_card(card: {id, face, back}, from_global) # gezogene Karte kommt an
landing_point() -> Vector2 (global)      # Ziel der Zieh-Flüge
flip_wave(delay, step, dur, faces: {id: face})    # Flip-Welle über die Hand
set_input_locked(on) / own_color_counts() -> {farbe: Anzahl}

# Director
func enqueue(events, view := {}) / step(dt) / flush() / clear() / backlog() / is_busy() / upcoming_view()
var handler  # play_event(ev, speed) -> float, skip_event(ev), apply_view(view)

# Sonstiges
JokerRays.attach(card, above, side := "") / JokerRays.is_joker(key)
QrCode.encode(text, min_version := 1, force_mask := -1) -> QrCode   # null, wenn zu lang
HandoverScreen.direction_info(from_seat, to_seat, n) / headline(name, info)
TableLayout.seat_positions(n, my_seat, size) / seat_angle / fan / smooth_path
UiTheme.get_theme() / build() / save() ; UiFonts.text(weight, width) / title(...) / mau() ; UiIcons.symbol(farbe, px) / icon(name, px, farbe)
```

Benutzte Ereignisfelder: `play{seat, card, face}`, `draw{seat, count, faces?}`, `penalty{seat, count}`, `skip{seat}`, `skip_all{seat?}`, `reverse{dir}`, `color{color}`, `flip{side}`, `pending{amount}`, `challenge{seat, success}`, `mau{seat}`, `catch{seat, target}`, `shuffle`, `deal{count?, dealer?}`, `round_over{ranking, scores}`, `game_over`. Sichtfelder wie Abschnitt 4 (u. a. `players[].backs/count/mau/place/connected/score/kind`, `hand`, `top`, `draw_back`, `draw_count`, `pending`, `hints`, `rules.backs_visible`, `rules.scoring`, `round`, `ranking`).

## Abweichungen vom Plan

1. **`WishPicker` statt `ColorPicker`**: Godot hat bereits eine Klasse `ColorPicker`; ein gleichnamiges `class_name` geht nicht.
2. **Effekte heißen `TableEffects`** (Datei `effects.gd` wie geplant), damit der Name nicht mit allgemeinen Bezeichnern kollidiert.
3. **`res://assets/ui/theme.tres`** liegt im Ordner von Modul B/C; der Auftrag F1b verlangt das Thema dort. Sonst nichts in `assets/ui/` geändert.
4. **Hintergrund am Tag hell**: Der Entwurf `hand.png` zeigt auch zur hellen Seite einen Nachttisch; der Auftrag verlangt den Shader Papier/Sonne ↔ Nacht/Mond/Sterne. Umgesetzt wie im Auftrag (Tag = Papier wie im Logo, Nacht = Entwurf). Lässt sich mit `TableBackground.tageszeit` jederzeit anders festlegen.
5. **Farbjagd-Erkennung**: Ein eigenes Ereignis gibt es im Plan nicht. Der Tisch spielt den Spielautomaten, wenn nach `play` mit `dunkel_farbjagd` ein `draw` eines anderen Platzes folgt. Modul A kann alternativ ein Feld setzen; dann hier anpassen.
6. **`{a:"color", color}`** für `hints.need_color` (z. B. Wünscher als Startkarte) ist im Aktionskatalog nicht vorgesehen; Modul A/G entscheidet.
7. **Sicht mit `seat = -1`**: Der Tisch richtet sich dann nach dem Spieler am Zug (Zuschauer); der Sichtschutz selbst braucht keine Sicht.
8. **Komet bei „Alle aussetzen“** läuft in Spielrichtung einmal um den Tisch zurück zum Spieler (06: „rast als Komet um den Tisch zurück“).
9. **Pillen**: sichtbar 56 px hoch wie im Entwurf, die Trefferfläche ist 84 px hoch (≥ 48 dp).
10. **QR-Code ohne ECI-Kopf**: Bytes sind UTF-8, wie heute alle verbreiteten Leser annehmen; Adressen sind ohnehin ASCII.

## Tests (alle grün)

| Test | Inhalt | Ergebnis |
|---|---|---|
| `test_ui_table_layout.gd` | Sitzwinkel, Drehen statt Spiegeln für 2–10 Spieler und jeden eigenen Platz, Plätze im Bild und mit Mindestabstand, Abzeichen ab 7, Fächer (Breite, Mitte, „+n“), Sichtschutz-Richtung und Überschrift | RESULT: 145 ok |
| `test_ui_table_director.gd` | Reihenfolge, Abgleich nach Ereignissen, Tempo ×2 bei > 3, Überspringen bei > 8 (auch mitten im Warten), mehrere Abschnitte, `flush`, Ereignisse ohne Dauer | RESULT: 19 ok |
| `test_ui_table_qr.gd` | ISO-Beispiel Reed-Solomon (1-M „01234567“), Formatbits M0–M7, Versionsbits 7–10, Kapazitäten; vier Referenzmatrizen aus libqrencode (v1, v5, v7, v10 inkl. UTF-8) Modul für Modul identisch, auch die Maskenwahl; Lesbarkeit aller 80 Kombinationen Version 1–10 × Maske 0–7 mit dem Decoder quirc (ffmpeg-Filter, Nutzlast byte-genau) | RESULT: 140 ok |
| `test_ui_table_theme.gd` | Schriften (opsz 12, Mau-Schrift), Knopf- und Feldhöhen ≥ 84 px, Symbole gerastert, theme.tres lädt | RESULT: 22 ok (23 mit `SAVE_THEME=1`) |
| `test_ui_table_view.gd` | Abgleich (Plätze, Fächer = Rückseiten, Stapel, Ablage, Farbe, Hinweis, Mau-Knopf, Erwischen, Behalten), Drehung aus Sicht von Platz 2, verdeckte Rückseiten, Großansicht nur sichtbar, letzte Karte groß, 2/3/6/7/10 Spieler, Eingaben (Ziehen nur am Zug, Erwischen, Mau), komplette Demo-Folge mit Prüfung „Anzeige = Sicht“ nach jedem Schritt, Überspringen bei Rückstand, Sichtschutz (keine Karten, 350 ms Sperre, 500 ms Halten), Farbwahl (Felder, Farbrad-Viertel, Nachtfarben), Joker-Strahlen (Normalen, Abdeckung, echte Karten), reduzierte Effekte, Meldungen | RESULT: 61 ok |
| `test_ui_table_smoke.gd` | Demo-Szene laden und alle Schritte durchspielen | RESULT: 2 ok |
| `test_ui_table_shots.gd` | Kontrollbilder mit Renderer (vom Testlauf in `build.ps1` ausgenommen) | 11 Bilder |

Prüfung der QR-Lesbarkeit: ffmpeg 9.0.1 enthält libquirc (Filter `quirc`) und libqrencode (`qrencodesrc`). Die Referenzmatrizen sind im Test eingebettet; die quirc-Prüfung läuft, wenn `ffmpeg` im PATH liegt (sonst Hinweis, kein Fehler). quirc verwechselt bei mehr als vier kleinen Codes je Bild Suchmuster verschiedener Codes, daher je Bild vier Codes.

## Kontrollbilder (`docs/module/`, 1600×720, Compatibility-Renderer)

`F1b_tisch_hell.png`, `F1b_tisch_dunkel.png` (mit Mau-Marke, „Erwischt!“, „+5“, letzte Karte groß), `F1b_flip.png` (mitten in der Welle, Dämmerung), `F1b_farbwahl.png` (Felder, gezogener Joker über Gelb), `F1b_farbrad.png`, `F1b_sichtschutz.png`, `F1b_8_spieler.png` (Abzeichen, Richtung −1), `F1b_rundenende.png` (Punkte 500), `F1b_qr.png`, zusätzlich `F1b_effekte.png` (Stempel, Zzz, Mau-Blase, Erwischt, Farbwelle, Randpuls), `F1b_hilfe.png`, `F1b_grossansicht.png`. Erzeugen: `godot_run.ps1 -Script res://tests/test_ui_table_shots.gd -Resolution 1600x720` (einzeln mit `-EnvPairs 'SHOT=flip'`; `SHOT=ablauf` legt zur Durchsicht Bilder jedes Demo-Schritts nach `%TEMP%`).

## Änderungen 0.1.4

- **Wer dran ist:** `TurnHalo` (`scripts/ui/turn_halo.gd`, Shader `assets/shaders/turn_halo.gdshader`) legt einen Strahlenkranz um Kopfzeile und Fächer des Spielers am Zug (Tag golden, Nacht bläulich); beim eigenen Zug um das eigene Namensschild und die Hand (`HandView.cards_rect()`). Nur während des Zugs sichtbar, danach ausgeblendet und unsichtbar; Effekte reduziert: Strahlen stehen.
- **Eigener Platz:** `TableView.me_badge` (`OpponentSeat` mit `header_only`) links über „Farbe“: Avatar, Name, Kartenzahl als Pille, Mau-Marke.
- **Denkblase:** nach 5 s ohne Handlung am Namen (`OpponentSeat.THINK_AFTER`); jedes Ereignis mit `seat` setzt die Uhr zurück (`poke`).
- **Kartenhilfe:** Das „?“ der offenen Großansicht meidet den Mau-Knopf (`HandView.avoid_global`), und solange die Großansicht offen ist, nimmt der Mau-Knopf keine Eingaben.
- **Rundenende:** `TableEffects.SoftRaysFx` (Shader `soft_rays.gdshader`, Art wie die Tischstrahlen) statt der Keile.
- **Partiestart:** Ohne bisherige Sicht baut `deal` zuerst den leeren Tisch der Zielsicht auf (Plätze mit 0 Karten, volle Stapelhöhe), dann fliegen die Karten wie bei „Nächste Runde“.
- **Flip-Überraschung:** Ereignis `flip_surprise` → Stempel „Flip-Überraschung!“ über der Ablage; folgende Strafen zeigen sich wie nach einem Legen.
- **Vertretener Gast:** `GameTable.view_of` setzt `players[i].substituted`; der Platz zeigt „Computer spielt“ statt „getrennt“.
- Tests: `test_ui_014.gd` (33 ok). Kontrollbilder: `test_ui_014_shot.gd` → `optik_014_dran_tag.png`, `optik_014_ich_nacht.png`, `optik_014_rundenende.png`.

## Offene Punkte

1. **Integration Phase 2 (F2)**: HandView (F1a) braucht einen kleinen Adapter auf die Hand-Schnittstelle oben (`apply_view` → `set_cards`/`set_playable`, `receive_card`/`landing_point` bzw. `spawn_from`, `flip_wave`). `take_card` passt bereits (CardView wird übernommen). Bei `drag_started` eines Jokers `open_color_fields()`, bei `drag_moved` `wish_picker.hover()`, bei `drag_ended` `wish_picker.drop()`.
2. **Ereignisdetails mit Modul A abgleichen**: Farbjagd (Punkt 5 der Abweichungen), Felder von `deal`, `skip_all{seat}`, Rundenpunkte in `round_over.ranking` (`{seat, points}` wird unterstützt, ebenso reine Platzlisten).
3. **Ton**: `App.sound.play` hat keine Tonhöhe; der Spielautomat (Tonhöhe +6 % je Karte) und ein „Boing“/„Wusch“ fehlen. Benutzt werden „karte“, „ziehen“, „mischen“, „flip“, „sieg“, „mau“.
4. **Nicht umgesetzt (Soll/Kann aus 06)**: Zugspur, Lupe beim Anzweifeln, Shader vorwärmen, automatische Rückstufung bei < 45 fps, Musik-Überblendung beim Flip, Holo-Joker.
5. **Gerätetest** auf S21/S10 steht aus (Bildrate mit Hintergrund-Shader, Joker-Teilchen, Lesbarkeit der Mini-Karten und Abzeichen bei 8–10 Spielern).
6. Modul B liefert eigene Symbolbilder in `assets/ui/farben/`; der Tisch rastert die Formsymbole zur Laufzeit aus denselben Pfaden des Kartengenerators (beliebige Größe und Farbe). Bei Bedarf umstellen.
