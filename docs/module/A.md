# Modul A – Regelwerk

Stand 05.10.2026, Nachtschicht (Nachbesserung nach der Prüfung, siehe Abschnitt „Nachbesserung“ am Ende). Das Regelwerk ist vollständig umgesetzt und getestet: reine Logik ohne Nodes in `game/scripts/rules/`, deterministisch aus einem Seed. Alle Pflichtprüfungen aus BETA1_PLAN Abschnitt 4 laufen headless und sind grün.

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
  - Ein Flip als letzte Karte wird ausgeführt; gewertet wird die neue Seite (Option). Bei `flip_last_card=ignore` wird er nie ausgeführt, auch nicht, wenn die Runde bei `round_end=last` weiterläuft.
- **Stapel leer:**
  - Leerer Nachziehstapel: Die Ablage außer der obersten Karte wird gemischt; die Wunschfarbe bleibt.
  - Sind beide Stapel leer, entfällt das Ziehen (Ereignis `pass`), und offene Strafen verfallen.
- **Stillstand:** Wiederholt sich bei fast leeren Stapeln dieselbe Lage zum dritten Mal, endet die Runde als „blockiert“; vorn liegt, wer die wenigsten Karten hat (siehe Abweichung 5).
- **Mau!**
  - Das Fenster öffnet sich, sobald man mit 2 Karten am Zug ist und eine Karte legen kann (sonst gibt es weder `can_mau` noch die Erinnerung „Denk an „Mau!““; ein Ruf wird abgelehnt). Es schließt mit der ersten Zughandlung des nächsten handelnden Spielers (`play`, `draw`, `challenge`, `accept`), bei „Alle aussetzen“ also mit dem eigenen Zusatzzug.
  - Ein Opfer, das automatisch zieht (+1/+5 ohne Stapeln), und ein Übersprungener handeln nicht selbst; das Fenster bleibt dann bis zur Handlung des Übernächsten offen. Das ist Absicht: Sonst könnte niemand erwischen, und es passt zur Schonfrist im Netz.
  - Wer vergisst, kann erwischt werden: Er zieht `mau_penalty` Karten.
  - Weitere Modi: `auto` (Strafe beim Fensterende), `reminder` (nur Erinnerung; nachträglicher Ruf wie bei `catch` möglich, aber kein Erwischen und keine Strafe), `off`.
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
  - Ruft „Mau!“ immer, aber nur, wenn er im selben Zug auf 1 Karte kommt (erst wird die Aktion gewählt; ist sie `play`, kommt vorher `mau`). Nachträglich ruft er, wenn er mit 1 Karte und offenem Fenster wieder dran ist (Zusatzzug). Erwischt sofort und blufft auf Stufe 2 nie.
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
var g := MauGame.create(RuleConfig.preset("offiziell"), [{name="Lena", kind="human", host=true}, {name="Kater", kind="bot"}], seed)
# host = true (optional, auch 1 aus JSON): Gastgeber-Platz, sonst Platz 0. g.host_seat(), g.set_host(seat)
# 2–10 Spieler, sonst push_error und g.is_valid() == false: start_round() liefert [], apply() lehnt ab.
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

- `next_round` darf nur der Gastgeber-Platz auslösen (`players[i].host` in `create()`, Standard Platz 0), und nur in `round_over`. Nur er bekommt `hints.can_next_round` und den Hinweis „Weiter mit der nächsten Runde.“.
- `mau` und `catch` gehen jederzeit während der Runde, von jedem Platz (wenn die Regeln es erlauben, siehe `hints`).
- **Typprüfung:** `a` und `color` nur als String, `card` und `target` nur als `int` oder ganzzahliger `float` (JSON). Anderes (null, Text, Array, Dictionary, 1.5, bool) lehnt `apply()` mit „Ungültige Aktion.“ bzw. „Unbekannte Aktion.“ ab; der Zustand bleibt unverändert.

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
2. **`flip_last_card`:** zusätzlich der Wert `ignore` (Flip als letzte Karte wird nicht ausgeführt, auch bei `round_end=last`), wie im Optionsbildschirm des Regelberichts vorgeschlagen.
3. **Wertung `points500` gilt nur bei `round_end=first`** (`RuleConfig.effective_scoring()`).
   - Bei `last` zählen Platzierungen.
   - Bei `scoring=none` zählt `score` die Rundensiege. Es gibt kein `game_over`; die Spielsteuerung startet beliebig viele Runden.
4. **`mau_call=auto`** straft beim Fensterende, also bei der ersten Handlung des Nächsten, nicht schon beim Legen. So bleibt „Mau!“ auch nach dem Legen möglich (Regelbericht: „vor oder nach dem Legen“), auch beim Weitergeben. Ist der Säumige selbst der Nächste (zu zweit, Alle aussetzen) und legt einen Wünscher +2 oder eine Farbjagd, zählt für Regelgerechtheit und Anzweifeln die Hand vor der Strafe.
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
12. **`view_for(-1)`** enthält die Rückseiten aller Spieler, weil sie am Tisch sichtbar sind. Laut AGENTS.md Nr. 15 darf der Weitergeben-Sichtschutz keine Karten zeigen; das muss die Oberfläche beachten: **Der Sichtschutz rendert nichts aus `view_for(-1)`, auch nicht `top` oder `draw_back`** (für Modul G/F).
13. Der Parameter von `create` heißt `rng_seed` statt `seed`, damit er die globale Funktion `seed()` nicht verdeckt.
14. **Gastgeber-Platz** im Regelwerk (`players[i].host`, gespeichert als `host` in `to_dict`): Der Plan sagt „nur Platz 0 bzw. Gastgeber“; im Netzspiel legt der Gastgeber die Sitzordnung fest und sitzt nicht unbedingt auf Platz 0.
15. **Mau-Fenster nach automatischem Ziehen** bleibt offen, bis der nächste Spieler selbst handelt (siehe Regeln, Mau!). Nach Regel 1.9 begänne der Zug des Opfers schon mit dem Ziehen; dann könnte aber niemand erwischen.

## Tests

Alle headless, über `tools/godot_run.ps1`:

| Test | Inhalt | Ergebnis |
|---|---|---|
| `test_rules_cards.gd` | CardDB: Anzahlen, Kontrollsummen, 108 Gesichter, Schlüssel, Punkte, Sortierung. RuleConfig: Standard, Voreinstellungen, JSON-Rundreise, Grenzen, `describe`. RulesText: alle 108 Gesichter, optionsabhängige Sätze, Übersicht | 655 ok |
| `test_rules_play.gd` | Jede Karte, Regel und Option in gebauten Situationen, je mit Prüfung der 112 Karten. Abgelehnte Aktionen lassen den Zustand byte-gleich. Dazu der Rundenstart über 200 Seeds, kaputte Aktionen, Gastgeber-Platz, Spielerzahl | 1 053 ok |
| `test_rules_views.gd` (Standardlauf) | siehe unten | 66 ok |
| `test_rules_views_long.gd` | volle Partienzahlen, gleiche Prüfungen | 66 ok |
| `test_rules_bots.gd` (Standardlauf) | siehe unten | 190 ok |
| `test_rules_bots_long.gd` | 10 000 Partien, Stärketest 3 000, gleiche Prüfungen | siehe unten |

**Laufzeiten** (in Godot gemessen, ohne Start und ohne Warten auf die Godot-Sperre): cards und play je unter 1 s, views 13 s, bots 10 s, zusammen also etwa 25 s plus viermal Godot-Start. Lange Läufe: views_long 55 s, bots_long siehe unten. Die Wanduhr ist bei parallel arbeitenden Agenten oft viel höher, weil `godot_run.ps1` auf die Sperre wartet.

**`test_rules_play.gd` deckt ab:** Passen, Wünscher, +1/+5/+2, Aussetzen, Richtungswechsel (auch zu zweit, mit und ohne Option), Alle aussetzen, Flip mit allen Sonderfällen, Startkarte, Bluff und Anzweifeln in allen Kombinationen, `enforce` und `free`, Farbjagd (auch mit `jagd_wild_stops` und ohne erreichbare Farbe), Stapeln aller Ziehkarten, letzte Karte, Mischen, leere Stapel, Blockade, Stillstand, Mau in allen Modi samt Fenster, `round_end=last`, Wertung und Partieende, `draw_rule`, `drawn_card`, Hinweistexte und Begründungen.

**`test_rules_views.gd` prüft:**
- Sortierte Rückseiten, eigene Rückseiten, Zuschauersicht, genaue Feldliste.
- JSON-Tauglichkeit von Sichten, Ereignissen und `to_dict`: nur JSON-Typen, Zahlen als int, `stringify` → `parse` gleich.
- `events_for`.
- **Partienzahlen:** Standardlauf / lang (`test_rules_views_long.gd`): JSON-Prüfung 10 / 30, Lecktest 16 / 60, Hinweisprüfung 5 / 16, Rundreise 15 / 40 Partien. Einzeln per Umgebungsvariable (`RULES_JSON_GAMES`, `RULES_LEAK_GAMES`, `RULES_HINT_GAMES`, `RULES_TRIP_GAMES`).
- **Lecktest:** Bot-Partien, jede Sicht jedes Platzes (auch −1) nach jedem Schritt: im Standardlauf 32 387 Sichten und 32 618 gefilterte Ereignislisten, im langen Lauf 165 156 und 166 257 (vor der Nachbesserung mit anderem Bot-Verhalten 307 089 und 308 497).
  - Die Gesichter in der Sicht stimmen als Multimenge exakt mit dem Erlaubten überein.
  - Seed und Zufallszustand kommen nie vor; Gleiches gilt für alle gefilterten Ereignisse.
- **Determinismus:** gleicher Seed und gleiche Aktionen ergeben denselben Zustand, unabhängig von der globalen Zufallsquelle. Die Paarung wechselt je Runde.
- **Rundreise:** `to_dict` → JSON → `from_dict` mitten im Spiel. Danach spielen beide Fassungen identisch weiter.
- **Hinweise = Regeln:** In Bot-Partien wird nach jedem Schritt jede Handkarte, Ziehen, Behalten, Anzweifeln, Annehmen, Farbwahl, Mau und jedes Erwischen an einer Zustandskopie ausprobiert. `apply()` nimmt genau an, was `hints` erlaubt: 28 543 Versuche im Standardlauf, 69 950 im langen Lauf.

**Standardlauf `test_rules_bots.gd`:**
- Bot-Entscheidungen in gebauten Situationen, dazu die Mau-Entscheidungen aller Stufen.
- Spielstärke: 600 Partien, Schwelle 37 % (gemessen 241 = 40,2 %).
- 300 Bot-Partien mit zufälligen Regeln, 2–10 Spielern und Stufen 0–2. Bei Punktewertung wird bis `game_over` gespielt, sonst teils mehrere Runden.
- Vergessene Mau-Rufe und Erwischen sind simuliert. Blinde Mau-Rufe (Ruf mit 2 Karten, danach kein `play`) werden gezählt und müssen 0 sein (4 372 Rufe, 0 blind).
- Nach jeder Aktion: 112 Karten, jede id einmal, gültiger Platz am Zug, Farbe passt zur Seite. Zugobergrenze 5 000 je Runde.
- Dauer etwa 10 s. Anzahl über `-EnvPairs 'RULES_GAMES=200'` bzw. `RULES_STRENGTH`.

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

## Nachbesserung (05.10.2026, Teilaufgabe FixA)

Grundlage: Befunde des Prüfers in `docs/module/A_pruefung.json`. Die Schnittstelle bleibt kompatibel: Alles Bisherige gilt weiter, neu sind nur optionale Felder und Funktionen.

| Befund (Schwere) | Behebung |
|---|---|
| Keine Typprüfung der Aktionsfelder (mittel) | `MauGame._int_field()`: `card`/`target` nur als `int` oder ganzzahliger, endlicher `float` (JSON), sonst „Ungültige Aktion.“; `a` und `color` nur als String (`_str_field()`). Kein Skriptfehler mehr, kein `ok=true` ohne Wirkung, `card:"abc"` spielt nicht mehr id 0. `catch` prüft zusätzlich die Platzgrenzen. |
| `next_round` fest an Platz 0 (mittel) | Gastgeber-Platz `host` (Absprache der Phase): `create()` liest je Spieler optional `host: true` (auch `1` aus JSON; erster markierter Platz gewinnt, sonst Platz 0). Nur dieser Platz darf `next_round` und bekommt `hints.can_next_round` samt „Weiter mit der nächsten Runde.“. Gespeichert als `host` in `to_dict()`; alte Stände ohne `host` laden mit Platz 0. Dazu `host_seat()`, `set_host(seat)`, im Fixture `spec.host`. |
| Blinde Mau-Rufe der Bots, Hinweis „Denk an Mau“ ohne legbare Karte (mittel) | Regelwerk: `can_mau` vor dem Legen nur, wenn eine Karte legbar ist (`_has_playable`); damit auch keine Erinnerung, und `apply` lehnt den Ruf ab („„Mau!“ rufst du, wenn du deine vorletzte Karte legen kannst – gerade passt keine.“). Bot: wählt erst die Aktion und ruft nur vor einem `play` (oder nachträglich mit 1 Karte im eigenen Zusatzzug); nach einem Ruf bleibt er beim Legen (unehrliches Stapeln). Dauerlauf zählt blinde Rufe: 0. |
| `flip_last_card=ignore` bei `round_end=last` (niedrig) | Der Flip als letzte Karte wird bei `ignore` auch dann nicht ausgeführt, wenn die Runde weiterläuft; Texte stimmen damit. |
| auto-Strafe vor der Regelgerechtheit (niedrig) | `_act_play` bestimmt `legal` und die Hand fürs Anzweifeln (`snap`) vor `_begin_turn`, also mit der Hand, auf der Hinweis und Entscheidung beruhten. Der Herausforderer sieht die Hand ohne die Strafkarten. |
| `reminder`: kein Ruf nach dem Legen (niedrig) | `mau_open` wird auch bei `reminder` gesetzt: nachträglicher Ruf wie bei `catch`/`auto`; Erwischen bleibt `catch`, Strafe bleibt `auto` vorbehalten. |
| Spielerzahl nicht erzwungen (niedrig) | `create()` mit weniger als 2 oder mehr als 10 Spielern: `push_error`, `is_valid() == false`, `start_round()` liefert `[]`, `apply()` lehnt ab („Ungültige Spielerzahl.“). `MauGame.valid_player_count(n)` für Aufrufer. 10 × 10 Handkarten + Startkarte passen (112). |
| Testlaufzeiten (niedrig) | Standardläufe gekürzt, volle Zahlen in `*_long` (siehe unten). |
| Widerspruch in der Übersicht bei `may_not` (niedrig) | „Du darfst auch freiwillig ziehen; danach ist dein Zug vorbei.“ |
| Mau-Fenster nach automatischem Ziehen (niedrig) | Als Absicht dokumentiert (Abweichung 15): Sonst könnte niemand erwischen; passt zur Schonfrist im Netz. Test hält das Verhalten fest. |
| Abweichungen in BETA1_PLAN übertragen (niedrig, Koordinator) | Nicht in meinen Dateien. Für den Koordinator: Abweichungen 1–15 nach BETA1_PLAN übernehmen und die Stillstandsregel (Abweichung 5) dem Nutzer vorlegen. Hinweis für G/F in Abweichung 12: Der Sichtschutz rendert nichts aus `view_for(-1)`. |

**Neue Tests:**
- `test_rules_play.gd`: `_broken_actions` (null, Array, Dictionary, Text, 1.5, bool, INF/NaN als `card`/`target`/`a`/`color`; JSON-float wird angenommen), `_host_seat` (Markierung, JSON-Zahl, Speichern, alter Stand, nur Gastgeber startet, Hinweistext, `set_host`, Spielerzahl 1/11 ungültig, 2/10 gültig, 10 × 10 Karten), `_fixes` (kein blinder Ruf, Opfer mit/ohne Stapeln, Flip-ignore bei `last`, auto-Strafe in `bluff`/`enforce`, `reminder`, Fenster nach automatischem Ziehen, Übersicht `may_not`). Ein bestehender Fall nutzte einen blinden Ruf und legt jetzt eine passende Karte bereit.
- `test_rules_bots.gd`: `_mau_decisions` für alle Stufen, Zählung blinder Rufe im Dauerlauf (muss 0 sein).
- Die zwei `ERROR: MauGame: 2 bis 10 Spieler nötig …` in der Ausgabe von `test_rules_play.gd` sind beabsichtigt (Prüfung der Spielerzahl).
