# Modul A – Regelwerk

Stand 04.10.2026, Nachtschicht. Das Regelwerk ist vollständig umgesetzt und getestet: reine Logik ohne Nodes in `game/scripts/rules/`, deterministisch aus einem Seed. Alle Pflichtprüfungen aus BETA1_PLAN Abschnitt 4 laufen headless und sind grün.

## Umgesetzt

| Datei | Klasse | Inhalt |
|---|---|---|
| `card_db.gd` | `CardDB` | 112 Karten je Seite, 108 Gesichter, Schlüssel, Punkte, Sortierung |
| `rule_config.gd` | `RuleConfig` | alle Optionen aus dem Plan, Voreinstellungen, `to_dict`/`from_dict`, `describe()` |
| `mau_game.gd` | `MauGame` | Zustandsmaschine: Aktionen, Sichten, Ereignisfilter, Speichern |
| `bot.gd` | `MauBot` | Computergegner auf der Sicht eines Platzes |
| `rules_text.gd` | `RulesText` | deutsche Kartenhilfe je Gesicht und Regelübersicht, passend zur `RuleConfig` |
| `rules_fixture.gd` | `RulesFixture` | **zusätzlich:** baut gezielte Spielsituationen für Tests und Kontrollbilder |

### Regeln

Grundlage: `docs/recherche/07_regeln_hausregeln.md`, Abschnitte 1.1–1.13 und Hausregeln.

- **Karten:**
  - Zahlen 1–9, keine 0.
  - Kontrollsummen hell 1280, dunkel 1480.
- **Paarung und Kennungen:** Die Paarung hell↔dunkel und die Kennungen `id` werden in jeder Runde aus dem Seed neu gemischt.
- **Zufall:** nur aus dem eigenen `RandomNumberGenerator`; nirgends `Array.shuffle()` oder `randi()`.
- **Startkarte:**
  - Aktion, Joker oder Flip bleibt im Ablagestapel liegen, dann wird die nächste Karte aufgedeckt.
  - Der Geber rotiert im Uhrzeigersinn; es beginnt der Spieler links vom Geber.
- **Passen:** Farbe, Zahl oder Symbol; Joker passen immer. Liegt ein Joker oben, zählt nur die Wunschfarbe.
- **Flip:**
  - Kehrt Ablage und Nachziehstapel um und schaltet die Seite. Die neue Oberkarte ist die bisher unterste, nun mit der anderen Seite.
  - Die Wunschfarbe verfällt. Eine Aktionskarte, die danach oben liegt, wirkt nicht.
  - Liegt ein Joker oben, wählt der Flip-Spieler die Farbe.
- **Wünscher +2 und Farbjagd:**
  - Einschränkung nach Tabelle 1.6, in drei Modi: `bluff`, `enforce`, `free`.
  - Ob Joker auf der Hand als „passend“ zählen, regelt `wild_counts_for_bluff` (Fassung 2024 bzw. 2018).
  - Anzweifeln: Die Hand des Legers sieht nur der Herausforderer.
  - Bluff erwischt: Der Leger zieht die Strafe, der Herausforderer ist danach normal dran.
  - Leger war ehrlich: Der Herausforderer zieht 4 bzw. bis zur Farbe plus 2 und setzt aus.
  - Die Wunschfarbe bleibt in jedem Fall.
- **Farbjagd:**
  - Das Opfer zieht bis zur Wunschfarbe, behält alle Karten und setzt aus.
  - `jagd_wild_stops` legt fest, ob ein gezogener Joker die Jagd beendet.
  - Kommt die Farbe in keinem Stapel mehr vor, endet das Ziehen; das Opfer setzt trotzdem aus.
- **Alle aussetzen:** Der Spieler bekommt einen Zusatzzug.
- **Zu zweit:** Der Richtungswechsel wirkt wie Aussetzen (Option). Aussetzen und Ziehkarten geben dem Leger von selbst den nächsten Zug.
- **Letzte Karte:**
  - Ist sie eine Ziehkarte, zieht der Nächste trotzdem, auch eine gestapelte Summe.
  - Ein Flip als letzte Karte wird ausgeführt; gewertet wird die neue Seite (Option).
- **Stapel leer:**
  - Leerer Nachziehstapel: Die Ablage außer der obersten Karte wird gemischt; die Wunschfarbe bleibt.
  - Sind beide Stapel leer, entfällt das Ziehen (Ereignis `pass`), und offene Strafen verfallen.
- **Stillstand:** Wiederholt sich bei fast leeren Stapeln dieselbe Lage zum dritten Mal, endet die Runde als „blockiert“; vorn liegt, wer die wenigsten Karten hat (siehe Abweichung 5).
- **Mau!**
  - Das Fenster öffnet sich, sobald man mit 2 Karten am Zug ist. Es schließt mit der ersten Zughandlung des nächsten Zugs (`play`, `draw`, `challenge`, `accept`), bei „Alle aussetzen“ also mit dem eigenen Zusatzzug.
  - Wer vergisst, kann erwischt werden: Er zieht `mau_penalty` Karten.
  - Weitere Modi: `auto`, `reminder`, `off`.
  - Ein Ruf verfällt, sobald man Karten bekommt.
- **`round_end=last`:**
  - Wer fertig ist, scheidet aus; am Ende stehen Platzierungen.
  - Wird jemand mit „Alle aussetzen“ fertig, macht der Nächste weiter.
  - Bei 2 Verbleibenden gilt die Zweierregel.
- **Wertung `points500`:** Der Sieger bekommt die Restpunkte der aktiven Seite. Die Partie endet bei `target` mit `game_over`.
- **Stapeln (`stacking=same`):**
  - Nur die gleiche Ziehkarte darf drauf, die Summe wandert weiter.
  - Bei der Farbjagd zieht das letzte Opfer bis zur zuletzt gewünschten Farbe.
  - Wird ein Bluff im Stapel erwischt, zieht der Leger die ganze Summe; war er ehrlich, zieht der Herausforderer Summe + 2.
- **Ziehen:**
  - `draw_rule=until_playable`: ziehen, bis eine Karte passt.
  - `drawn_card` mit den Werten `may`, `must` oder `may_not`.
  - Freiwilliges Ziehen ist erlaubt; danach darf man nur die gezogene Karte legen.

### Computergegner (`MauBot.choose(view, rng_seed, level := 1)`)

- Arbeitet nur auf der Sicht des eigenen Platzes, funktioniert also auch mit einer Sicht, die über JSON kam.
- **Stufen:** 0 = zufällig, 1 = Taktik mit etwas Zufall, 2 = Taktik.
- **Taktik:**
  - Aktionskarten bevorzugt, besonders gegen einen Nächsten mit höchstens 2 Karten. Vor einem Richtungswechsel achtet der Bot auf den Vorgänger.
  - Er wählt die Karte, nach der die meisten Restkarten noch passen, und spart Joker auf.
  - Flip: Er wägt die eigenen Rückseiten gegen die sichtbaren Rückseiten der Gegner ab, denn die sind nach dem Flip deren Vorderseiten.
  - Wunschfarbe nach Handmehrheit.
  - Ruft immer „Mau!“, erwischt sofort und blufft auf Stufe 2 nie.
- **Anzweifeln bei Verdacht:** Der Bot schätzt, wie wahrscheinlich der Leger eine passende Karte hatte. Das wächst mit dessen Kartenzahl, gewichtet mit der angenommenen Bluffneigung `BLUFF_PRIOR`. Angezweifelt wird, wenn die erwarteten Kosten dadurch sinken.
- **Spielstärke** zu dritt gegen zwei Zufallsbots: gemessen 42 % Siege bei 3 000 Partien. Zufall läge bei 33 %; das Spiel hängt stark vom Glück ab.
- Liefert `{}`, wenn der Platz nichts zu tun hat. Auch außerhalb des eigenen Zugs kommt `{a:"catch"}` zurück, wenn jemand erwischt werden kann.

### Texte

- **`RulesText.card_help(key, config) -> Array[String]`:** kurze Sätze; der erste beschreibt die Wirkung. Beispiele: „+5 darf gestapelt werden …“, Bluff-Regel je Modus, Flip-Seite, Punkte.
- **`RulesText.overview(config) -> Array[{title, text}]`:** Ziel, Karten, Start, Spielzug, helle und dunkle Seite, Flip, Ziehkarten, Joker, Mau!, Sonderfälle.
- **Namen:** `face_title(key)` („Grün 7“, „Türkis +5“, „Wünscher +2“), `color_name`, `kind_name`, `side_name`, `match_phrase`.
- **`RuleConfig.describe() -> Array[String]`:** eine Zeile je Regelgruppe; nennt die Voreinstellung, falls eine passt.

## Schnittstelle

Siehe BETA1_PLAN Abschnitt 4. Hier nur, was der Plan offenlässt.

```gdscript
var g := MauGame.create(RuleConfig.preset("offiziell"), [{name="Lena", kind="human"}, {name="Kater", kind="bot"}], seed)
var ev := g.start_round()                  # Ereignisse UNGEFILTERT → für jeden Empfänger durch events_for()
var r := g.apply(seat, {a="play", card=17, color="blau"})   # {ok, reason (deutsch), events (ungefiltert)}
var v := g.view_for(seat)                  # seat -1 = Zuschauer/Sichtschutz
var act := MauBot.choose(g.view_for(bot_seat), rng.randi(), 1)
g.set_connected(seat, false)               # erscheint in players[].connected
```

**Wichtig:** `apply().events` und `start_round()` enthalten private Daten: gezogene Gesichter und die Hand beim Anzweifeln. Weitergeben nur über `events_for(seat, events)`.

### Aktionen

Alle Aktionen aus dem Plan, dazu:

| Aktion | Bedeutung |
|---|---|
| `{a:"color", color}` | Farbwahl in der Phase `color` (Flip mit Joker oben) |
| `{a:"draw"}` in der Phase `challenge` | entspricht `accept` |
| `{a:"draw"}` unter offener Stapelstrafe | Strafe nehmen und aussetzen |

- `next_round` darf nur Platz 0 auslösen, und nur in `round_over`.
- `mau` und `catch` gehen jederzeit während der Runde, von jedem Platz.

### Phasen

`idle` (vor `start_round`), `turn`, `drawn`, `challenge`, `color`, `round_over`, `game_over`. `current_seat()` ist −1 außerhalb von `turn`, `drawn`, `challenge` und `color`.

### Sicht

Felder laut Plan, dazu:

- `wish` (bool)
- `colors`: Farben der aktiven Seite
- `discard_count`
- `drawn`: id der gezogenen Karte, nur für den Ziehenden
- `dealer`
- `result`: nach Rundenende `{ranking, points, gains, scores, hands, reason, side, round}`; `reason` ist `fertig` oder `blockiert`
- `pending`: `{kind, amount, by, victim, color}`; `kind` ist der Kartentyp (`plus1`, `plus5`, `wuenscher_plus2`, `farbjagd`), nicht „stack“
- `hints`: alle Felder des Plans, dazu `wild` (spielbare ids, die eine Farbe brauchen), `can_accept` und `can_next_round`
- `ranking`: während der Runde die bisher Fertigen

Zahlen sind immer `int`.

### Ereignisse

Ereignisse laut Plan:

| Ereignis | Felder |
|---|---|
| `deal` | `{dealer, count}` |
| `play` | `{seat, card, face}` |
| `draw` | `{seat, count, reason, cards*, faces*, backs}` |
| `skip` | `{seat}` |
| `skip_all` | `{seat}` |
| `reverse` | `{dir, seat}` |
| `color` | `{color, seat}`; `seat` −1 bei der Startfarbe |
| `flip` | `{side, card, face, draw_back}` |
| `pending` | `{kind, amount, seat (Opfer), by}` |
| `challenge` | `{seat, target, success, hand*}` |
| `mau` | `{seat}` |
| `catch` | `{seat, target}` |
| `penalty` | `{seat, count, reason:"mau"}` |
| `shuffle` | `{count}` |
| `round_over` | `{ranking, scores, points, gains, hands, reason}` |
| `game_over` | `{winner, scores}` |

- `*` = nur für den Berechtigten.
- `draw.reason` ist `zug`, `strafe`, `mau` oder `bluff`.
- Rückseiten in `draw.backs` sind für andere sortiert; bei `backs_visible=false` fehlen sie.

Zusätzlich:

| Ereignis | Felder / Bedeutung |
|---|---|
| `round_start` | `{round, dealer}` |
| `start` | `{card, face, ignored}`, je aufgedeckter Startkarte |
| `turn` | `{seat}`, wer jetzt handelt |
| `keep` | `{seat}` |
| `accept` | `{seat}` |
| `choose_color` | `{seat}` |
| `finish` | `{seat, place}` |
| `pass` | `{seat}`, Ziehen entfällt |

## Abweichungen vom Plan (mit Begründung)

1. **Phase `color` und Aktion `{a:"color"}`.** Beim Flip mit Joker oben wählt nach R24 der Flip-Spieler die Farbe; das braucht einen eigenen Schritt. Der Browser-Client (`webclient/mock.js`) nutzt dieselbe Form.
2. **`flip_last_card`:** zusätzlich der Wert `ignore` (Flip als letzte Karte wird nicht ausgeführt), wie im Optionsbildschirm des Regelberichts vorgeschlagen.
3. **Wertung `points500` gilt nur bei `round_end=first`** (`RuleConfig.effective_scoring()`).
   - Bei `last` zählen Platzierungen.
   - Bei `scoring=none` zählt `score` die Rundensiege. Es gibt kein `game_over`; die Spielsteuerung startet beliebig viele Runden.
4. **`mau_call=auto`** straft beim Fensterende, also bei der ersten Handlung des Nächsten, nicht schon beim Legen. So bleibt „Mau!“ auch nach dem Legen möglich (Regelbericht: „vor oder nach dem Legen“), auch beim Weitergeben.
5. **Ende ohne Sieger durch Legen (zusätzliche Regeln, keine Fassung regelt das):**
   - Ziehen bei leeren Stapeln ist nur erlaubt, wenn nichts passt; dann ist es ein Aussetzen. Passen alle aktiven Spieler nacheinander, endet die Runde als „blockiert“. Praktisch nie erreichbar, weil Wünscher immer passen.
   - **Stillstandsregel:** Hat der Nachziehstapel samt Ablage höchstens so viele freie Karten wie Spieler und tritt dieselbe Lage zum dritten Mal ein, endet die Runde ebenfalls als „blockiert“. Die Lage umfasst Hände, Stapel, Platz am Zug, Richtung, Farbe, Seite und offene Strafe. Das ist wie die dreifache Stellungswiederholung im Schach.
   - In beiden Fällen liegt vorn, wer die wenigsten Karten hat; Fertige behalten ihre Plätze.
   - Anlass: Der lange Lauf fand eine echte Endlosschleife. 10 Spieler, fast alle Karten auf der Hand, `drawn_card=must`: Zwei Nachbarn reichen sich zwei Richtungswechsel hin und her, weil das Mischen immer genau die eben gelegte Karte zurückgibt und der Richtungswechsel den Zug sofort zurückgibt. Nachgestellt in `test_rules_play.gd`.
6. **Einschränkung und Anzweifeln gelten auch für gestapelte Wünscher +2 und Farbjagden.** Daraus folgt die Hausregel „Bluff im Stapel = ganze Strafe“.
7. **Letzte Karte Wünscher +2 oder Farbjagd im Bluff-Modus:**
   - Erst wird über das Anzweifeln entschieden, dann gilt man als fertig (Vorschlag aus dem Regelbericht 1.10).
   - Mit leerer Resthand ist der Zug immer regelgerecht. Anzweifeln kostet den Herausforderer dann 4 Karten bzw. Farbe + 2.
   - Stapeln auf diese letzte Karte ist ausgeschlossen.
8. **`round_end=last`:** Aussetzen, Richtungswechsel und Ziehkarten wirken auch als letzte Karte weiter, wie Ziehkarten in der offiziellen Regel. Ist nach einem letzten Flip ein Joker oben, wählt der gerade fertig gewordene Spieler trotzdem die Farbe.
9. **Platzierung bei `round_end=first`:** Sieger, dann die anderen nach Restpunkten.
10. **Notfall Startkarte:** Ist im Stapel keine Zahl mehr übrig (nur bei 10 Spielern mit 10 Karten denkbar), bleibt die letzte Karte oben. Ein Joker bekommt dann eine zufällige Farbe aus dem Seed.
11. **Resthände sind nach Rundenende öffentlich** (`round_over.hands`, `view.result.hands`), für die Wertungsanzeige.
12. **`view_for(-1)`** enthält die Rückseiten aller Spieler, weil sie am Tisch sichtbar sind. Laut AGENTS.md Nr. 15 darf der Weitergeben-Sichtschutz keine Karten zeigen; das muss die Oberfläche beachten.
13. Der Parameter von `create` heißt `rng_seed` statt `seed`, damit er die globale Funktion `seed()` nicht verdeckt.

## Tests

Alle headless, über `tools/godot_run.ps1`:

| Test | Inhalt | Ergebnis |
|---|---|---|
| `test_rules_cards.gd` | CardDB: Anzahlen, Kontrollsummen, 108 Gesichter, Schlüssel, Punkte, Sortierung. RuleConfig: Standard, Voreinstellungen, JSON-Rundreise, Grenzen, `describe`. RulesText: alle 108 Gesichter, optionsabhängige Sätze, Übersicht | 655 ok |
| `test_rules_play.gd` | Jede Karte, Regel und Option in gebauten Situationen, je mit Prüfung der 112 Karten. Abgelehnte Aktionen lassen den Zustand byte-gleich. Dazu der Rundenstart über 200 Seeds | 771 ok |
| `test_rules_views.gd` | siehe unten | 66 ok |
| `test_rules_bots.gd` (Standardlauf) | siehe unten | 15 ok |
| `test_rules_bots_long.gd` | 10 000 Partien, gleiche Prüfungen | 15 ok |

**`test_rules_play.gd` deckt ab:** Passen, Wünscher, +1/+5/+2, Aussetzen, Richtungswechsel (auch zu zweit, mit und ohne Option), Alle aussetzen, Flip mit allen Sonderfällen, Startkarte, Bluff und Anzweifeln in allen Kombinationen, `enforce` und `free`, Farbjagd (auch mit `jagd_wild_stops` und ohne erreichbare Farbe), Stapeln aller Ziehkarten, letzte Karte, Mischen, leere Stapel, Blockade, Stillstand, Mau in allen Modi samt Fenster, `round_end=last`, Wertung und Partieende, `draw_rule`, `drawn_card`, Hinweistexte und Begründungen.

**`test_rules_views.gd` prüft:**
- Sortierte Rückseiten, eigene Rückseiten, Zuschauersicht, genaue Feldliste.
- JSON-Tauglichkeit von Sichten, Ereignissen und `to_dict`: nur JSON-Typen, Zahlen als int, `stringify` → `parse` gleich.
- `events_for`.
- **Lecktest:** 60 Bot-Partien, jede Sicht jedes Platzes (auch −1) nach jedem Schritt: 307 089 Sichten und 308 497 gefilterte Ereignislisten.
  - Die Gesichter in der Sicht stimmen als Multimenge exakt mit dem Erlaubten überein.
  - Seed und Zufallszustand kommen nie vor; Gleiches gilt für alle gefilterten Ereignisse.
- **Determinismus:** gleicher Seed und gleiche Aktionen ergeben denselben Zustand, unabhängig von der globalen Zufallsquelle. Die Paarung wechselt je Runde.
- **Rundreise:** `to_dict` → JSON → `from_dict` in 40 Partien mitten im Spiel. Danach spielen beide Fassungen identisch weiter.
- **Hinweise = Regeln:** In 16 Bot-Partien wird nach jedem Schritt jede Handkarte, Ziehen, Behalten, Anzweifeln, Annehmen, Farbwahl, Mau und jedes Erwischen an einer Zustandskopie ausprobiert. Ergebnis: 89 175 Versuche, `apply()` nimmt genau an, was `hints` erlaubt.

**Standardlauf `test_rules_bots.gd`:**
- Bot-Entscheidungen in gebauten Situationen.
- Spielstärke: 600 Partien, Schwelle 37 %.
- 1 000 Bot-Partien mit zufälligen Regeln, 2–10 Spielern und Stufen 0–2. Bei Punktewertung wird bis `game_over` gespielt, sonst teils mehrere Runden.
- Vergessene Mau-Rufe und Erwischen sind simuliert.
- Nach jeder Aktion: 112 Karten, jede id einmal, gültiger Platz am Zug, Farbe passt zur Seite. Zugobergrenze 5 000 je Runde.
- Dauer etwa 30 s. Anzahl über `-EnvPairs 'RULES_GAMES=200'`.

**Langer Lauf** `test_rules_bots_long.gd`:
- 10 000 Partien in 275 s, ohne Fehler.
- 17 349 Runden, 3 411 406 Aktionen, 167 069 Flips, 25 045 Anzweifeln, 30 164 Mischvorgänge, 4 914-mal erwischt, 2 502 Partien bis 500 Punkte.
- 268-mal entfiel das Ziehen, einmal griff die Stillstandsregel.
- Der erste Lauf hatte genau diese eine Partie (Nr. 2861) an der Zugobergrenze; daraus entstand die Stillstandsregel.
- Weil er rund 5 Minuten die Godot-Sperre hält, gehört er nicht in einen „alle Tests“-Lauf, sondern wird gezielt gestartet.

Aufruf:

```
powershell -NoProfile -Command "& 'E:\Documents\Programmierung\Mau-Mau Flip\tools\godot_run.ps1' -Script res://tests/test_rules_play.gd -Headless -Timeout 300"
```

## Offene Punkte und Hinweise für andere Module

- **Modul E (Browser-Client):**
  - Mit `stacking=same` darf das Opfer auch in der Phase `challenge` einen Wünscher +2 bzw. eine Farbjagd drauflegen (`hints.playable` ist dann nicht leer). `app.js` und `tisch.js` lassen Legen bisher nur in `turn`/`drawn` zu.
  - Die echte Sicht meldet in der Farbwahl `phase:"color"`, das Mock `turn`.
  - `pending.kind` ist der Kartentyp.
- **Modul G (Spielsteuerung):**
  - Bots auch außerhalb ihres Zugs fragen (Erwischen). Mit Denkpause, sonst erwischen Bots Menschen sofort.
  - Für Netzspiele eine Schonfrist beim Erwischen am Gastgeber umsetzen (Regelbericht: etwa 1,5 s). Das Regelwerk schließt das Fenster mit der ersten Handlung des Nächsten.
  - Den Stand mit `to_dict()` speichern (JSON-fest, Seed und Zufallszustand als Zeichenketten).
- **Modul F:** `RulesFixture.build(config, n, spec)` baut beliebige Tischlagen mit echtem Regelwerk für Kontrollbilder, z. B. 25 Karten auf der Hand oder Joker nach Flip. Die Hilfe-Geste nutzt `RulesText.card_help(key, config)` und `face_title(key)`.
- **Nicht in 0.1.1 (laut Plan „später“):**
  - Reinwerfen, 7-Tausch, „Mau-Mau!“-Ansage, Flip-Start dunkel, R18-Startkarten, „Joker nach Flip: Nächster wählt“.
  - Die Optionen ließen sich in `RuleConfig` und `MauGame` ergänzen, ohne die Schnittstelle zu ändern.
- **Spielstärke des Bots:** Die Taktik bringt messbar mehr Siege (42 % statt 33 %). Eine stärkere Stufe bräuchte Kartenzählen (welche Farben schon gefallen sind) und Wissen über das Bluffverhalten der Mitspieler. Beides ist für die Beta nicht nötig.
