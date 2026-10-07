# Modul A – Regelwerk

Stand 05.10.2026, Nachtschicht (Nachbesserung nach der Prüfung, siehe Abschnitt „Nachbesserung“; danach die Hausregeln Kartentausch, Glücksspiel und Farbe mit ablegen, siehe die Abschnitte am Ende). Das Regelwerk ist vollständig umgesetzt und getestet: reine Logik ohne Nodes in `game/scripts/rules/`, deterministisch aus einem Seed. Alle Pflichtprüfungen aus BETA1_PLAN Abschnitt 4 laufen headless und sind grün.

## Umgesetzt

| Datei | Klasse | Inhalt |
|---|---|---|
| `card_db.gd` | `CardDB` | 112 Karten je Seite, 108 Gesichter (mit Zusatzkarten der Hausregeln bis 124 Karten, 128 Gesichter), Schlüssel, Punkte, Sortierung |
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
  - Die Wunschfarbe verfällt. Eine Aktionskarte, die danach oben liegt, wirkt nicht (mit der Hausregel `flip_surprise=on` doch, siehe „Flip-Überraschung“).
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

`idle` (vor `start_round`), `turn`, `drawn`, `challenge`, `color`, `gamble` (Hausregel Glücksspiel), `round_over`, `game_over`. `current_seat()` ist −1 außerhalb von `turn`, `drawn`, `challenge`, `color` und `gamble` (`MauGame.PLAY_PHASES`).

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
| `flip_surprise` | `{seat (Flip-Spieler), face}`; öffentlich, vor den Wirkungs-Ereignissen der Oberkarte |
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
| `test_rules_cards.gd` | CardDB: Anzahlen, Kontrollsummen, 108 Gesichter, Schlüssel, Punkte, Sortierung. RuleConfig: Standard, Voreinstellungen, JSON-Rundreise, Grenzen, `describe`. RulesText: alle 108 Gesichter, optionsabhängige Sätze, Übersicht | 660 ok |
| `test_rules_play.gd` | Jede Karte, Regel und Option in gebauten Situationen, je mit Prüfung der 112 Karten. Abgelehnte Aktionen lassen den Zustand byte-gleich. Dazu der Rundenstart über 200 Seeds, kaputte Aktionen, Gastgeber-Platz, Spielerzahl | 1 053 ok |
| `test_rules_views.gd` (Standardlauf) | siehe unten | 66 ok |
| `test_rules_views_long.gd` | volle Partienzahlen, gleiche Prüfungen | 66 ok |
| `test_rules_bots.gd` (Standardlauf) | siehe unten | 190 ok |
| `test_rules_bots_long.gd` | 10 000 Partien, Stärketest 3 000, gleiche Prüfungen | siehe unten |
| `test_rules_swap.gd` | Hausregel Kartentausch (116 Karten), siehe Abschnitt „Kartentausch“ | 900 ok |
| `test_rules_gamble.gd` | Hausregel Glücksspiel, alle Deckvarianten, Dauerlauf mit allen Hausregeln, siehe Abschnitt „Glücksspiel“ | siehe dort |
| `test_rules_discard.gd` | Hausregel Farbe mit ablegen, siehe Abschnitt „Farbe mit ablegen“ | siehe dort |

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

## Kartentausch (Hausregel, 05.10.2026)

Nutzerwunsch: eine „Kartentausch“-Karte, mit der alle ihre Karten im Uhrzeigersinn weitergeben, wahlweise in Spielrichtung. Festlegung des Koordinators, umgesetzt im Regelwerk; Oberfläche und Browser-Client bauen dagegen.

### Regeln

- **Optionen** (`RuleConfig`):
  - `swap_cards`: **`off`** (offiziell, keine Kartentausch-Karten) / `on`
  - `swap_direction`: **`clockwise`** (immer Platz + 1) / `counter` (immer Platz − 1) / `play` (aktuelle Spielrichtung `dir`) / `against` (gegen `dir`), seit 0.1.3 vier Richtungen (siehe „Änderungen für 0.1.3“)
  - Seit der Nutzerentscheidung vom 05.10.2026 in der Voreinstellung „Familie“ an (mit `clockwise`), sonst in keiner. `preset_name()` übergeht `swap_direction`, solange `swap_cards=off` ist (die Richtung allein macht noch keine „eigenen Regeln“).
- **Karten:** Bei `on` kommen 4 doppelseitige Karten dazu, also **116**. Hell je eine Kartentausch-Karte in Rot, Gelb, Grün, Blau, dunkel je eine in Pink, Türkis, Orange, Lila. Die Paarung hell↔dunkel wird wie bei allen Karten je Runde aus dem Seed gebildet.
  - Gesichtsschlüssel `hell_<farbe>_tausch` bzw. `dunkel_<farbe>_tausch`, Art `tausch`, 20 Punkte.
  - Prüfsummen mit Kartentausch: hell 1360, dunkel 1560 (ohne: 1280/1480).
- **Passen:** auf die gleiche Farbe oder auf jeden anderen Kartentausch, wie eine Aktionskarte. Als Startkarte bleibt sie liegen (wie jede Aktion). Unter einer offenen Stapelstrafe ist sie nicht legbar.
- **Wirkung:** Alle aktiven Spieler (noch nicht fertig) geben gleichzeitig ihre **ganze Hand** an den nächsten aktiven Platz in Tauschrichtung. Danach ist ganz normal der Nächste in **Spielrichtung** dran. Zu zweit tauschen die beiden ihre Hände. Fertige (`round_end=last`) werden übersprungen.
- **Mau:** Wer durch den Tausch auf 1 Karte kommt, muss nicht „Mau!“ rufen. Das offene Mau-Fenster schließt (`mau_open = −1`), alle Rufe verfallen (`mau_said` überall `false`); niemand kann dafür erwischt werden, bei `auto` gibt es keine Strafe. Der Bot ruft vor einem Kartentausch kein „Mau!“.
- **Letzte Karte:** Der Leger ist fertig wie bei jeder letzten Karte. Endet damit die Runde (`round_end=first`, oder bei `last` bleibt nur einer übrig), entfällt der Tausch. Läuft die Runde weiter (`last`), tauschen nur die übrigen aktiven Spieler; danach ist der Nächste nach dem Leger dran.
- **Flip danach:** Die getauschten Karten wenden sich wie alle (Hände sind ids, das Gesicht folgt der aktiven Seite).

### Schnittstelle

- **`CardDB`:**
  - `deck(s, with_swap := false)`, `faces_light(with_swap)`, `faces_dark(with_swap)`, `card_count(with_swap)` (112/116)
  - `all_keys()` bleibt bei den **108** Gesichtern des Grunddecks (Vertrag mit den Kartenbildern, `test_b_assets.gd`); `all_keys(true)` liefert alle Gesichter aller Hausregeln (seit Glücksspiel und Farbe mit ablegen **128**), `swap_keys()` die 8 des Kartentauschs
  - `SWAP = "tausch"`, `is_swap(face)`, Konstanten `CARD_COUNT_SWAP`, `FACE_COUNT_SWAP`, `SUM_LIGHT_SWAP`, `SUM_DARK_SWAP`
  - **Codes:** Die Gesichtscodes 0–107 sind unverändert, die 8 neuen hängen dahinter (108–115). Gespeicherte Partien (`to_dict().faces`) bleiben damit gültig. Weil die Codes nicht mehr die Sortierreihenfolge sind, sortieren `sort_keys` und die Rückseiten in der Sicht über `rank_table()`/`order_table()`. Der Kartentausch steht in seiner Farbe hinter dem Flip.
- **`RuleConfig`:** `card_count()`, `swap_step(dir)` (±1), `swap_direction_text()`; `describe()` hat bei `on` eine Zeile „Kartentausch: …“.
- **`MauGame`:**
  - Die Konstante `N_CARDS` entfällt. Stattdessen `g.n_cards` (112 bzw. 116, aus `config.card_count()`, fest je Partie, auch in `from_dict`). `faces` hat `2 × n_cards` Einträge (`faces[s * n_cards + id]`), ids sind 0 bis `n_cards − 1`.
  - Alte Spielstände ohne `swap_cards` laden als `off` mit 112 Karten.
- **Ereignis `swap_hands`** (nach `play`, vor `turn`; bei der letzten Karte nach `finish`):

| Feld | Bedeutung |
|---|---|
| `seat` | Leger |
| `dir` | Tauschrichtung: +1 = Uhrzeigersinn (Hand an Platz + 1), −1 = gegen den Uhrzeigersinn |
| `counts` | Kartenzahl je Platz **nach** dem Tausch |
| `hand`* | nur nach `events_for(seat)`: die eigene neue Hand wie `view.hand`, also `[{id, face, back?}]` (`back` nur bei `peek_own_backs`); Zuschauer (−1) bekommen `[]` |
| `backs` | nur bei `backs_visible`: je Platz die Rückseiten sortiert; der eigene Eintrag ist leer |

Ungefiltert enthält das Ereignis `hands` (alle Hände mit Gesichtern); `events_for()` nimmt das immer heraus. Danach liefert `view_for()` die neuen Hände wie gewohnt: jeder nur seine eigene, Rückseiten der anderen sortiert.

### Computergegner

`MauBot.swap_value(view)` bewertet den Kartentausch nur aus der eigenen Sicht (Kartenzahlen sind öffentlich): Resthand `keep` gegen die Hand `got` des Vorigen in Tauschrichtung, die man bekommt.

- Wert `4 · (keep − got) − 2`, dazu +16, wenn der Empfänger höchstens 2 Karten hat und mindestens 2 weniger als `keep`, und −30, wenn man selbst höchstens 2 Karten behielte und nicht weniger bekäme. Als letzte Karte immer.
- Im Zug geht der Wert in die übliche Kartenwahl ein (Basis 8). Bleibt nur ein Kartentausch mit Wert < −6, zieht der Bot lieber. Ein gezogener Kartentausch mit negativem Wert wird behalten.
- **Stärke** zu dritt gegen zwei Zufallsbots mit Kartentausch: 252 von 600 Partien (42 %), wie ohne.

### Texte

- `card_help` für `*_tausch`:
  - Wirkung mit Richtung („immer im Uhrzeigersinn“ bzw. „in der aktuellen Spielrichtung“ samt „andersherum“-Hinweis)
  - Passen, zu zweit, letzte Karte (je nach `round_end`), Mau-Hinweis (nicht bei `mau_call=off`), Punkte
  - ohne Hausregel der Zusatz „gerade nicht im Spiel“
- `overview`: Absatz „Kartentausch“, „116 Karten …“ im Absatz Karten und Kartentausch in der Punkteliste, jeweils nur bei `on`. Ohne die Hausregel sind alle Texte unverändert.
- Namen: `kind_name("tausch")` „Kartentausch“, `face_title` „Rot Kartentausch“, `match_phrase` „einen Kartentausch“.

### Tests

**`test_rules_swap.gd`** (900 ok seit Glücksspiel und Farbe ablegen, etwa 92 s, davon 75 s Dauerlauf) erweitert `test_rules_views.gd` mit `swap_mode() = true`.

- **Gebaute Fälle:**
  - Kartendaten: 112/116, Prüfsummen 1280/1480 bzw. 1360/1560, je Farbe ein Kartentausch, unveränderte Codes 0–107, Sortierung
  - Optionen und Texte, Rundenstart über 60 Seeds und Runde 2
  - Tausch im Uhrzeigersinn; nach einem Richtungswechsel in beiden Modi; zu zweit; mit Fertigem in beiden Richtungen
  - letzte Karte bei `first`, bei `last` und bei `last` mit nur einem Übrigen
  - Mau-Fenster bei `catch` und `auto`: niemand erwischbar, keine Strafe, Fertigwerden ohne Ruf
  - Flip danach; dunkle Seite
  - Lecktest an gebauten Lagen für alle Kombinationen aus `backs_visible` und `peek_own_backs`: Gesichter im gefilterten Ereignis exakt als Multimenge
  - to_dict/from_dict mit 116 Karten nach einem Tausch, gleich weitergespielt; alter Stand ohne die Option lädt mit 112
  - Passen, Startkarte, Punkte, Bot-Entscheidungen (auch auf JSON-Sicht)
- **Zufallsprüfungen** aus `test_rules_views.gd` mit Kartentausch: JSON, Lecktest (26 696 Sichten, davon 588 Kartentausch-Ereignisse geprüft), Hinweise = Regeln (17 420 Versuche; seit den Glücksspiel-Aktionen in der Prüfung 23 292), Rundreise.
- **Stärketest** (600 Partien) und **Dauerlauf:** 2000 Partien mit zufälligen Regeln, 2–10 Spielern und Stufen 0–2, Kartenzahl immer 116, `deck_check` je Runde, Zugobergrenze 5000. Ergebnis: 3 460 Runden, 780 836 Aktionen, 15 478 Tausche (3 891 gegen den Uhrzeigersinn, 248 als letzte Karte), 0 blinde Mau-Rufe. Anzahl per `-EnvPairs 'RULES_SWAP_GAMES=200'`.

**Ohne Hausregel bit-gleich:** Ein Fingerabdruck (SHA-256 über 120 Bot-Partien mit zufälligen Regeln: alle Sichten ohne `rules`, alle gefilterten Ereignisse, Aktionen, Endzustand ohne `config`; 1,84 Mio. Teile) ist für HEAD und den neuen Stand identisch. Der Stärketest in `test_rules_bots.gd` liefert weiter genau 241 von 600.

- `RulesFixture.random_config(rng)` zieht dieselben Zufallszahlen wie vorher (Kartentausch aus); `random_config(rng, true)` schaltet ihn ein und zieht die Richtung zuletzt.
- `RulesFixture.card_check` prüft gegen `g.n_cards`; neu ist `RulesFixture.deck_check(g)`: Gesichter je Seite = Deck der Variante.

### Hinweise für andere Module

- **Kartenbilder (B/F):** Die 8 Gesichter `hell_{rot,gelb,gruen,blau}_tausch` und `dunkel_{pink,tuerkis,orange,lila}_tausch` brauchen Bilder. `test_b_assets.gd` vergleicht mit `CardDB.all_keys()` (weiter 108). Kommen die Bilder dazu, dort auf `all_keys(true)` und 116 umstellen.
- **Oberfläche und Browser-Client:**
  - Optionen `swap_cards`/`swap_direction` im Regelbildschirm (die Liste in `rules_screen.gd` ist handgepflegt).
  - Ereignis `swap_hands` animieren und danach die Hand aus `hand` bzw. der neuen Sicht übernehmen; eine manuelle Handsortierung gilt für die alte Hand nicht mehr.
  - Hilfetexte kommen aus `RulesText`.
- **Spielsteuerung (G):** nichts zu tun. `test_game_local.gd` prüft fest auf 112 Karten; das stimmt, solange dort ohne Kartentausch gespielt wird (sonst `t.game.n_cards`).
- **`webclient/mock.js`** rechnet mit 112 Karten (Sache des Browser-Clients).

## Glücksspiel (Hausregel, 05.10.2026)

Nutzerwunsch (AGENTS.md Nr. 26), Festlegung des Koordinators, umgesetzt im Regelwerk im selben Muster wie der Kartentausch; Oberfläche und Browser-Client bauen dagegen.

### Regeln

- **Option** `gamble_cards`: **`off`** / `on`, in keiner Voreinstellung.
- **Karten:** 2 zusätzliche doppelseitige Karten, je Seite zweimal `hell_gluecksspiel` bzw. `dunkel_gluecksspiel` (Art `gluecksspiel`, Joker, 50 Punkte). Deck 114, mit allen Hausregeln 124. Prüfsummen je Seite +100.
- **Legen:** `{a:"play", card, color}` wie ein Wünscher; die gewählte Farbe gilt nach dem Glücksspiel.
  - Passt immer, außer unter einer offenen Ziehstrafe (Stapeln) und beim Anzweifeln, wie jeder Joker. Zählt bei `wild_counts_for_bluff` als „anderer Joker“.
  - Als Startkarte bleibt es liegen. Liegt es nach einem Flip oben, wählt der Flip-Spieler nur die Farbe (Phase `color`); ein Glücksspiel gibt es dann nicht.
  - **Als letzte Karte** ist der Spieler fertig wie bei jeder letzten Karte; es gibt kein Glücksspiel, weil nichts zu setzen ist.
- **Ablauf:** Danach ist der Leger in der Phase **`gamble`** (`current_seat()` bleibt der Leger).
  - Je Glücksspiel wird geheim eine **Trefferquote q** (1–10, gleich wahrscheinlich) aus dem Spielzufall gelost. Sie steht in `to_dict()`, nie in einer Sicht oder einem Ereignis.
  - `{a:"stake", card}`: eine beliebige eigene Handkarte verdeckt auf den Einsatz (Pflicht vor jedem Druck), dann `{a:"press"}`.
  - **Treffer** (Wahrscheinlichkeit 1/q): Wert 1–10, gleich wahrscheinlich. Der Spieler zieht so viele Karten (übliches Ziehen, Grund `gluecksspiel`; leerer Nachziehstapel → Ablage mischen, der Einsatz nicht; sind beide Stapel leer, entfällt das Ziehen), nimmt den ganzen Einsatz zurück (hinten an die Hand), und der Zug ist vorbei: Nächster in Spielrichtung.
  - **Kein Treffer** (Wert 0): Ist die Hand leer, kommt der Einsatz unter die Ablage (die zuerst gesetzte Karte ganz unten) und der Spieler ist fertig wie bei einer letzten Karte (Rundenende bzw. Platzierung bei `round_end=last`). Sonst folgt der nächste Einsatz – oder der Spieler hört auf.
  - **Aufhören** (06.10.2026, AGENTS.md Nr. 26, immer erlaubt, keine Option): Nach mindestens einem Druck ohne Treffer (`need = "stake"`, Einsatz ≥ 1) darf der Spieler statt weiterzusetzen `{a:"stop"}` schicken. Der ganze Einsatz kommt unter die Ablage (wie bei leerer Hand), der Zug ist vorbei: Nächster in Spielrichtung. Bleibt genau 1 Karte, gilt die normale Mau-Regel: Das Fenster hat das Setzen geöffnet (vorher rufen, sonst erwischbar, bis der Nächste handelt); ein Ruf bleibt gültig.
  - Einsatzkarten wirken nie (auch Flip, Kartentausch, Ablegen). Während des Glücksspiels gibt es keinen Flip; die Seite bleibt.
  - Das Glücksspiel endet immer: Jeder Druck trifft mit mindestens 10 %, jeder Fehlschuss kostet eine Handkarte. Eine künstliche Grenze gibt es nicht.
- **Mau:**
  - Sinkt die Hand durch Legen des Glücksspiels oder durch einen Einsatz auf 1 Karte ohne Ruf, öffnet sich das Mau-Fenster wie üblich. Andere dürfen während des Glücksspiels erwischen, bis der Nächste handelt, auch wenn die Hand schon leer ist (Ruf bei 1 Karte vergessen). Die Strafkarten kommen auf die Hand, das Glücksspiel geht weiter.
  - Ruf vorher: in der Phase `gamble` mit 2 Karten vor dem Setzen (`hints.can_mau`, Erinnerung „Denk an „Mau!““). Beim Drücken gibt es keinen Ruf.
  - Bei einem Treffer verfällt der Ruf, und ein offenes Fenster des Spielers schließt (er bekommt Karten zurück).
  - `auto`: Die Strafe käme erst beim Fensterende. Weil das Glücksspiel immer mit Fertigwerden oder Zurücknehmen endet, gibt es im Glücksspiel keine automatische Strafe.

### Schnittstelle

- **Phase** `gamble` (in `MauGame.PLAY_PHASES`). Erlaubt sind dort nur `stake`, `press` und `stop` (Glücksspieler) sowie `mau` und `catch`.
- **Aktionen:** `{a:"stake", card:<id>}` (`card` typgeprüft wie bei `play`), `{a:"press"}` und `{a:"stop"}`. Begründungen beim Ablehnen:
  - „Leg erst eine Karte verdeckt auf deinen Einsatz.“ (`press` vor dem Setzen)
  - „Erst den Glücksspielknopf drücken.“ (zweites `stake`; `play`/`draw`/`keep`/`stop` vor dem Drücken)
  - „Aufhören geht erst nach dem ersten Druck.“ (`stop` vor dem ersten Einsatz)
  - „Erst eine Karte verdeckt auf den Einsatz legen.“ (`play`/`draw`/`keep` vor dem Setzen)
  - „Gerade läuft kein Glücksspiel.“, „Glücksspiel gibt es in diesen Regeln nicht.“, „Du bist nicht dran.“, „Diese Karte hast du nicht.“, „Ungültige Aktion.“
  - Mau mit 2 Karten beim Drücken: „„Mau!“ rufst du, bevor du deine vorletzte Karte auf den Einsatz legst.“
- **Ereignisse:**

| Ereignis | Felder |
|---|---|
| `gamble_start` | `{seat}`, nach `play` und `color` |
| `stake` | `{seat, count, card*, face*, back*}`; `count` = Einsatzgröße danach; `card`, `face` und `back` (nur bei `peek_own_backs`) nur für den Spieler selbst |
| `gamble_roll` | `{seat, value}`; 0 = kein Treffer, 1–10 = Treffer |
| `draw` | bei einem Treffer wie sonst, `reason:"gluecksspiel"` |
| `stake_back` | `{seat, count, cards*, faces*, backs}`: ganzer Einsatz zurück; Rückseiten wie beim Ziehen (für andere sortiert bei `backs_visible`, für den Spieler bei `peek_own_backs`); danach `turn` |
| `stake_discard` | `{seat, count, cards*, faces*, reason}`: Einsatz unter die Ablage; `reason:"empty"` (0 bei leerer Hand, danach `finish` und `round_over` bzw. `turn`) oder `reason:"stop"` (Aufhören, danach `turn`) |

`*` = nach `events_for()` nur für den Spieler selbst. Die Quote steht in keinem Ereignis.

- **Sicht** (Felder **nur bei `gamble_cards=on`**; ohne die Hausregel fehlen sie, damit die Sicht bit-gleich bleibt – Clients lesen mit Standardwert):
  - `gamble`: `{seat, stake, need, last}` während eines Glücksspiels für alle Plätze (auch −1), sonst `{}`. `stake` = Anzahl der Einsatzkarten, `need` = `"stake"` oder `"press"`, `last` = letzter Wert (0–10) bzw. −1 vor dem ersten Druck.
  - `hints.can_stake`: ids der setzbaren Karten (nur der Glücksspieler bei `need="stake"`, sonst `[]`); `hints.can_press` (bool); `hints.can_stop` (bool, nur mit der Hausregel). `hints.playable` ist in der Phase leer, `can_draw` falsch.
  - Hinweistexte des Spielers: „Leg eine Karte verdeckt auf deinen Einsatz.“, nach einer 0 „Noch eine Karte setzen – oder aufhören?“ bzw. „Drück den Glücksspielknopf!“. Andere: z. B. „Anna spielt Glücksspiel – Einsatz: 2 Karten.“
- **Spielstand:** `to_dict()` hat bei `gamble_cards=on` zusätzlich `gamble` = `{seat, q, stake: [ids], need, last}` (`{}` außerhalb). Ohne die Hausregel fehlt der Schlüssel; alte Stände laden ohne Glücksspiel.
- **Testhaken:** `g.force_rolls([0, 0, 4])` gibt die nächsten Druckergebnisse vor (ohne Zufallszahlen, nicht gespeichert). `RulesFixture.build(…, {"gamble": {q, stake: [Schlüssel], need, last}})` baut ein laufendes Glücksspiel des Platzes `current` (Phase `gamble`).
- **`CardDB`:** `GAMBLE = "gluecksspiel"`, `gamble_keys()`, `is_gamble(face)`; dazu „Gemeinsame Änderungen“.
- **`RuleConfig`:** `gamble_cards`; `describe()` hat bei `on` eine Zeile „Glücksspiel: …“.

### Computergegner

- Legt den Glücksspiel-Joker gern mit kleiner Hand (höchstens 4 Karten: Wert 32, bis 6 Karten 10, sonst 2) und immer, wenn sonst nichts passt (statt zu ziehen). Gezogen behält er ihn bei mehr als 6 Karten.
- Setzt zuerst Karten mit hohen Punkten bzw. schwer spielbare (Punkte + 12 / (1 + weitere Karten derselben Farbe)), Joker zuletzt; drückt sofort.
- **Aufhören** (`MauBot.stop_chance`, ohne Kenntnis der Quote, Zufall aus dem übergebenen Seed): Stufe 0 mit 30 %, sonst 10 % + 18 % je weiterer Einsatzkarte (höchstens 90 %), mit 2 Karten 20 % weniger; mit 1 Karte nie (kein Treffer = fertig), nach einem „Mau!“-Ruf mit 2 Karten auch nicht (er setzt dann die vorletzte Karte).
- Ruft „Mau!“ vor dem Setzen der vorletzten Karte (und vor dem Glücksspiel als vorletzte Karte).
- **Stärke** zu dritt gegen zwei Zufallsbots mit Glücksspiel: 257 von 600 Partien (43 %), Schwelle im Test 36 %.

### Texte

- `card_help` für `*_gluecksspiel`: Joker und Farbe, Ablauf, Quote 1:1 bis 1:10, Treffer 1 bis 10, Ende bei leerer Hand (je nach `round_end`), Aufhören nach einer 0, Einsatzkarten wirken nicht, Mau-Hinweis (nicht bei `mau_call=off`), Ziehstrafe (bei `stacking=same`), letzte Karte, Punkte; ohne Hausregel der Zusatz „gerade nicht im Spiel“.
- `overview`: Absatz „Glücksspiel“ (mit Aufhören), im Absatz Karten „zwei Glücksspiel-Joker“, in der Punkteliste „… Glücksspiel … 50“, jeweils nur bei `on`. Ist eine der Hausregeln mit Zusatzkarten aus, stellt der Absatz „Weitere besondere Karten“ deren Karten kurz vor (Nutzerwunsch: Anleitung „Regeln“ mit allen besonderen Karten).
- Namen: `kind_name("gluecksspiel")` und `face_title` „Glücksspiel“, `match_phrase` „ein Glücksspiel“.

### Tests

**`test_rules_gamble.gd`** (721 ok, etwa 77 s, davon 41 s Dauerlauf) erweitert `test_rules_views.gd` mit `gamble_mode() = true`.

- **Gebaute Fälle:** Kartendaten aller 8 Deckvarianten (Kartenzahl, Gesichter, Prüfsummen, Grunddeck vorn, feste Codes 0–127, Sortierung); Optionen und Texte; Rundenstart über 60 Seeds (114 bzw. 124 Karten); Legen, Phase, Sicht und alle Ablehnungen (Zustand byte-gleich); Treffer in beiden Richtungen; Fertigwerden bei `first` (mit Wertung) und `last` (auch mit nur einem Übrigen und zu zweit); letzte Karte; Mau in allen Lagen (Fenster nach Legen und Setzen, Erwischen mit 1 und 0 Karten, Ruf vorher, Treffer, `auto`, `off`); offene Stapelstrafe, Anzweifeln, `enforce`, Startkarte; gesetzter Flip ohne Wirkung und unter der Ablage, Glücksspiel oben nach einem Flip, dunkle Seite; leere Stapel (Mischen ohne Einsatz, beide leer); mit Kartentausch; Zufall (Quote gleichverteilt über 5000 Lose, Trefferrate 1/q für q = 1, 2, 5, 10, Werte 1–10 gleichverteilt, gleicher Seed = gleiche Würfe); Lecktest für alle Kombinationen aus `backs_visible` und `peek_own_backs` (Einsatzgesichter als Multimenge nur beim Besitzer, keine Quote); Rundreise mitten im Glücksspiel (auch aus Bot-Partien) und alter Stand; Bot-Entscheidungen (auch auf JSON-Sicht).
- **Zufallsprüfungen** aus `test_rules_views.gd` mit Glücksspiel: JSON, Lecktest (87 878 Sichten, davon 6 512 Einsatz-Ereignisse und 1 276 Quotenprüfungen), Hinweise = Regeln (17 359 Versuche, darunter jedes `stake` und `press`), Rundreise. In jeder Glücksspiel-Lage des Lecktests werden alle Sichten mit einer anderen Quote verglichen; sie müssen gleich bleiben.
- **Dauerlauf mit allen Hausregeln** (Kartentausch, Glücksspiel, Farbe mit ablegen): 2000 Partien mit zufälligen Regeln, 2–10 Spielern und Stufen 0–2; Kartenzahl immer 124, `deck_check` je Runde, Invarianten nach jeder Aktion, Zugobergrenze 5000 je Runde. Ergebnis: 3 196 Runden, 414 379 Aktionen, 6 993 Glücksspiele (20 647 Drucke, 4 425 Treffer, 2 568-mal damit fertig, das längste mit 51 Aktionen), 175-mal im Glücksspiel erwischt, 17 588-mal Farbe abgelegt (41 626 Karten mit), 6 358 Kartentausche; jedes Glücksspiel endet, 0 blinde Mau-Rufe (19-mal folgte einem Ruf eines Zufallsbots ein Kartentausch, der alle Rufe löscht; das zählt wie im Kartentausch-Test nicht). Anzahl per `-EnvPairs 'RULES_GAMBLE_GAMES=200'`.

## Farbe mit ablegen (Hausregel, 05.10.2026)

Nutzerwunsch (AGENTS.md Nr. 27), Festlegung des Koordinators.

### Regeln

- **Option** `discard_color`: **`off`** / `on`, in keiner Voreinstellung.
- **Karten:** 6 zusätzliche doppelseitige Karten. Je Seite eine farbige Ablegen-Karte je Farbe (`hell_<farbe>_ablegen` bzw. `dunkel_<farbe>_ablegen`, Art `ablegen`, 30 Punkte) und zweimal den Ablegen-Joker (`hell_ablegen_joker` bzw. `dunkel_ablegen_joker`, Art `ablegen_joker`, 50 Punkte). Deck 118, mit allen Hausregeln 124. Prüfsummen je Seite +220.
- **Passen:** Die farbige Karte passt auf ihre Farbe und auf jede andere farbige Ablegen-Karte (gleiches Symbol), der Ablegen-Joker immer (`{a:"play", card, color}`). Auf einem Joker zählt wie immer nur die Wunschfarbe. Unter einer offenen Ziehstrafe und beim Anzweifeln nicht legbar; als Startkarte bleiben beide liegen. Der Ablegen-Joker zählt bei `wild_counts_for_bluff` als „anderer Joker“.
- **Wirkung:** Alle übrigen Karten der Hand in der Farbe der Karte (beim Joker in der gewählten Farbe) kommen mit auf die Ablage, **unter** die Ablegen-Karte, die oben bleibt; deren Farbe bzw. die Wunschfarbe gilt.
  - Joker aller Art (Wünscher, Wünscher +2, Farbjagd, Glücksspiel, Ablegen-Joker) bleiben auf der Hand.
  - Mitabgelegte Aktionskarten wirken nicht (kein Aussetzen, keine Strafe, kein Richtungswechsel, kein Flip, kein Kartentausch), auch nicht als letzte Karten.
  - Reihenfolge in der Ablage nach Rang (nie Besitzerreihenfolge); nach einem späteren Flip kommen sie wie jede Ablagekarte nach oben.
  - Danach ist der Nächste dran; die Ablegen-Karte selbst hat keine weitere Wirkung.
- **Mau:** Bleibt 1 Karte ohne Ruf, öffnet sich das Fenster wie üblich (erwischen, `auto`-Strafe beim Fensterende). Bleibt keine, ist der Spieler fertig (Rundenende bzw. Platz). Zum Ruf vorher siehe „Gemeinsame Änderungen“.

### Schnittstelle

- **Ereignis** `discard_color` `{seat, color, cards, faces, count}` nach `play` (und `color`), vor `finish`/`turn`. Öffentlich (die Karten liegen offen); `cards`/`faces` in der Reihenfolge, in der sie unter der Ablegen-Karte liegen (unten zuerst). Auch mit `count` 0, wenn nichts weiter abzulegen war.
- Begründungen wie gewohnt, z. B. „Passt nicht – lege Gelb oder eine Ablegen-Karte.“
- **`CardDB`:** `DISCARD = "ablegen"`, `DISCARD_WILD = "ablegen_joker"`, `discard_keys()`, `is_discard(face)`.
- **`RuleConfig`:** `discard_color`; `describe()` hat bei `on` eine Zeile „Farbe ablegen: …“.

### Computergegner

- Bevorzugt die Ablegen-Karte, wenn sie mindestens 2 weitere Karten mitnimmt (Wert 20 + 5 je Karte) oder die Hand leert (60); sonst spart er sie auf (niedriger Wert, der Ablegen-Joker wie ein Wünscher). Gezogen behält er sie, wenn sie weniger als 2 mitnimmt und die Hand nicht leert.
- Der Ablegen-Joker wählt die Farbe mit den meisten Karten (`MauBot.most_color`; bei Gleichstand die mit mehr Punkten, dann zufällig).
- Ruft „Mau!“ vor jedem Legen, nach dem genau 1 Karte bleibt (`MauBot.left_after(view, act)`), und bleibt nach dem Ruf bei so einer Karte.

### Texte

- `card_help` für `*_ablegen` und `*_ablegen_joker`: Wirkung, Passen, Joker bleiben, Aktionskarten wirken nicht, Mau bzw. Fertigwerden (je nach `round_end` und `mau_call`), Punkte; ohne Hausregel „gerade nicht im Spiel“.
- `overview`: Absatz „Farbe ablegen“, im Absatz Karten „vier Ablegen-Karten (eine je Farbe) und zwei Ablegen-Joker“, in der Punkteliste „Alle aussetzen und Farbe ablegen 30“ und „… Ablegen-Joker 50“, jeweils nur bei `on`.
- Namen: `kind_name("ablegen")` „Farbe ablegen“, `face_title("hell_rot_ablegen")` „Rot ablegen“, Joker „Ablegen-Joker“, `match_phrase` „eine Ablegen-Karte“ bzw. „einen Ablegen-Joker“.

### Tests

**`test_rules_discard.gd`** (255 ok, etwa 32 s, davon 22 s Dauerlauf) erweitert `test_rules_views.gd` mit `discard_mode() = true`.

- **Gebaute Fälle:** Kartendaten (Schlüssel, Punkte, je Farbe eine, 2 Joker, Prüfsummen 1500/1700, Sortierung, Namen); Optionen und Texte; Rundenstart über 40 Seeds; Passen (Farbe, jede Ablegen-Karte, auf dem Joker nur die Wunschfarbe, Begründungen, Startkarte); Wirkung mit Jokern und allen Aktionskarten der Farbe auf der Hand (keine Wirkung, Reihenfolge unter der Karte, öffentliches Ereignis), ohne weitere Karten (`count` 0); Ablegen-Joker (Farbwahl, andere Joker bleiben, Richtungswechsel ohne Wirkung); Mau (Fenster bei 1 Karte, Erwischen, Ruf vorher mit 4 Karten, Ruf verfällt bei mehr, Joker mit passender und unpassender Farbe, kein Ruf, wenn keine Karte 1 übrig lässt, alles auf einmal ohne Ruf, `auto`, `off`); Fertigwerden bei `first` (Punkte 30/50) und `last`; offene Stapelstrafe, `enforce`, Anzweifeln; dunkle Seite (Farbjagd bleibt, +5 und Alle aussetzen wirken nicht) und Flip danach; mit Kartentausch und Glücksspiel; Rundreise; Bot-Entscheidungen.
- **Zufallsprüfungen** aus `test_rules_views.gd` mit „Farbe ablegen“: JSON, Lecktest (24 494 Sichten, davon 1 166 „Farbe ablegen“-Ereignisse), Hinweise = Regeln (29 583 Versuche), Rundreise.
- **Dauerlauf:** 1000 Partien mit zufälligen Regeln, Kartentausch bei jeder zweiten, Glücksspiel bei jeder dritten; Kartenzahl der Variante konstant, Zugobergrenze 5000. Ergebnis: 1 753 Runden, 225 763 Aktionen, 10 190-mal abgelegt (22 720 Karten mit), 753-mal damit fertig, 525 Rufe mit mehr als 2 Karten vor dem Ablegen, 0 blinde Rufe. Anzahl per `-EnvPairs 'RULES_DISCARD_GAMES=200'`.

## Gemeinsame Änderungen (Glücksspiel und Farbe mit ablegen)

- **Kartencodes** (fest, Spielstände speichern sie): 0–107 Grunddeck, 108–115 Kartentausch, 116 `hell_gluecksspiel`, 117 `dunkel_gluecksspiel`, 118–121 `hell_{rot,gelb,gruen,blau}_ablegen`, 122 `hell_ablegen_joker`, 123–126 `dunkel_{pink,tuerkis,orange,lila}_ablegen`, 127 `dunkel_ablegen_joker`. Im Deck einer Partie steht das Grunddeck vorn, dahinter Kartentausch, Glücksspiel, Ablegen (soweit eingeschaltet); so bleiben Paarung und ids aus dem Seed für die bisherigen Varianten gleich.
- **Rang** (Sortierung von Hand und Rückseiten): in ihrer Farbe Zahlen, Aktionen, Kartentausch, Ablegen-Karte; unter den Jokern der Seite Wünscher, Wünscher +2 bzw. Farbjagd, Glücksspiel, Ablegen-Joker.
- **`CardDB`:** `deck(s, with_swap, with_gamble, with_discard)`, `faces_light/dark(…)`, `card_count(…)`, `face_count(…)`, `point_sum(s, …)`, `variant(…)` (Bitmaske 1/2/4); Konstanten `EXTRA_CARDS`, `EXTRA_FACES`, `EXTRA_POINTS`, `CARD_COUNT_ALL` 124, `FACE_COUNT_ALL` 128, `SUM_LIGHT_ALL` 1680, `SUM_DARK_ALL` 1880. `all_keys(true)` liefert alle 128 Gesichter, `all_keys()` weiter die 108 des Grunddecks.
- **`RuleConfig`:** `card_count()` (112–124), `deck(s)`, `has_extra_cards()`. In `describe()` steht bei genau einer Hausregel mit Zusatzkarten die Kartenzahl in ihrer Zeile (Kartentausch unverändert „(116)“), bei mehreren in einer eigenen Zeile „Gespielt wird mit N Karten.“
- **Voreinstellung „Familie“ mit Kartentausch** (Nutzerentscheidung, AGENTS.md Nr. 25): `swap_cards=on`, also 116 Karten. Glücksspiel und Farbe ablegen sind in keiner Voreinstellung.
- **`RulesFixture`:** `random_config(rng, with_swap, with_gamble, with_discard)` (ohne Schalter dieselben Zufallszahlen wie vorher), `card_check` zählt den Einsatz mit, `deck_check` nimmt das Deck der Regeln, `invariants` prüft die Phase `gamble`, `spec.gamble`.
- **`test_rules_views.gd`** (gemeinsame Zufallsprüfungen): `gamble_mode()`/`discard_mode()` wie `swap_mode()`; Lecktest prüft Einsatz-Ereignisse (`_leak_stake`), `discard_color` (öffentlich, Farbe stimmt), Glücksspiel-Felder der Sicht und die Quote (`_quota_check`); die Hinweisprüfung probiert zusätzlich jedes `stake` und `press`.
- **Mau-Regel, verallgemeinert:**
  - Vor dem Legen darf rufen, wer am Zug ist und eine Karte legen kann, nach der genau 1 Karte bleibt. Ohne Ablegen-Karten heißt das wie bisher: 2 Karten und eine legbar. Eine Ablegen-Karte lässt „Hand − 1 − übrige Karten ihrer Farbe“ übrig, ein Ablegen-Joker zählt, wenn irgendeine Farbe 1 übrig lässt. Im Glücksspiel: 2 Karten vor dem Setzen.
  - Ein Ruf verfällt, wenn nach dem Legen bzw. Setzen mehr als 1 Karte bleibt (z. B. Ruf vor dem Ablegen-Joker, dann eine Farbe mit wenigen Karten). Ohne die neuen Karten kam das nie vor.
  - Die Erinnerung „Denk an „Mau!““ erscheint auch mit mehr als 2 Karten, wenn so ein Ruf möglich ist.
  - Mit 2 Karten, wenn die einzige legbare Karte die Hand leert: „Damit legst du alles auf einmal ab – „Mau!“ brauchst du nicht.“
- **Bot:** `MauBot.left_after(view, act)` und `MauBot.most_color(view, skip_id, rng)`; Ruf nur, wenn die gewählte Aktion genau 1 Karte übrig lässt oder er höchstens 1 Karte hat. Die Dauerläufe zählen „blinde“ Rufe (Ruf mit mindestens 2 Karten, danach bleiben mehr als 1; ein Erwischen dazwischen zählt nicht als Handlung): 0.
- **Ohne die neuen Hausregeln bit-gleich:** Ein Fingerabdruck (SHA-256 über 120 Bot-Partien mit zufälligen Regeln ohne Hausregelkarten und drei Voreinstellungen: alle Sichten ohne `rules`, alle gefilterten Ereignisse, Aktionen und Antworten, Endzustand ohne `config`, dazu `describe`, `overview`, `card_help` der 108 Gesichter und die Codetabelle 0–115; 1,31 Mio. Teile) ist vor und nach der Änderung gleich: `8e2e91de…0d08`. Auch mit Kartentausch bleibt alles gleich: Der Dauerlauf in `test_rules_swap.gd` liefert genau die dokumentierten Zahlen (3 460 Runden, 780 836 Aktionen, 15 478 Tausche), der Stärketest 252 von 600. Der Stärketest in `test_rules_bots.gd` liefert weiter 241 von 600.

### Hinweise für andere Module

- **Kartenbilder (B/F):** neue Gesichter `hell_gluecksspiel`, `dunkel_gluecksspiel`, `hell_{rot,gelb,gruen,blau}_ablegen`, `dunkel_{pink,tuerkis,orange,lila}_ablegen`, `hell_ablegen_joker`, `dunkel_ablegen_joker` (Listen: `CardDB.gamble_keys()`, `CardDB.discard_keys()`). `test_b_assets.gd` vergleicht weiter mit `CardDB.all_keys()` (108); `all_keys(true)` hat jetzt 128.
- **Oberfläche und Browser-Client:**
  - Optionen `gamble_cards` und `discard_color` im Regelbildschirm (die Liste in `rules_screen.gd` ist handgepflegt); „Familie“ schaltet jetzt den Kartentausch ein.
  - Phase `gamble`: Einsatz-Stapel (`view.gamble.stake`), Knopf „Glücksspiel“ bei `hints.can_press`, setzbare Karten aus `hints.can_stake` (→ `{a:"stake", card}`), Wert aus `gamble_roll.value` bzw. `view.gamble.last`. Die Felder fehlen ohne die Hausregel.
  - `discard_color` animieren: Karten aus `cards` von der Hand unter die Ablegen-Karte; die Gesichter sind für alle offen.
  - Der Mau-Knopf kann jetzt auch mit mehr als 2 Karten erscheinen (`hints.can_mau`).
  - Handsortierung: Rang aus `CardDB.rank_table()` kennt die neuen Gesichter, Punkte aus `points_table()`.
- **Spielsteuerung (G):** nichts zu tun; Bots liefern in der Phase `gamble` über `MauBot.choose` `stake`/`press`. `test_game_local.gd` zählt Karten nur in Stapeln und Händen; mit Glücksspiel müsste der Einsatz (`game.gamble.stake`) mitgezählt werden. „Familie“ spielt dort jetzt mit 116 Karten (der Test prüft die Kartenzahl nur in „Offiziell“).
- **`webclient/mock.js`** kennt die neuen Karten und die Phase nicht (Sache des Browser-Clients).

## Änderungen für 0.1.3 (06.10.2026)

- **Tauschrichtung** `swap_direction`: `clockwise` (Platz + 1, Standard), `counter` (Platz − 1), `play` (in Spielrichtung), `against` (gegen die Spielrichtung). `RuleConfig.swap_step(dir)` liefert ±1, `swap_direction_text()` den Satzteil, `RuleConfig.swap_direction_title(wert)` die Kurznamen „Im Uhrzeigersinn“, „Gegen den Uhrzeigersinn“, „In Spielrichtung“, „Gegen die Spielrichtung“. Ereignis `swap_hands` unverändert (`dir` ±1). `RulesFixture.random_config` lost alle vier Richtungen.
- **Kein Anzweifeln mehr:** `wild_restriction` steht standardmäßig und in allen Voreinstellungen auf `free` (`CHOICES` jetzt `["free", "enforce", "bluff"]`). `bluff` bleibt in der Engine aus Verträglichkeit. `RuleConfig.migrate_dict(d)` (statisch, liefert eine Kopie) macht gespeichertes `bluff` zu `free`; das rufen App-Einstellungen, Regelsätze und Regeln vom Gastgeber beim Laden auf. `klassisch500` setzt `wild_counts_for_bluff` nicht mehr; bei `free` zählt der Schalter für `preset_name()` nicht.
- **Farbe mit ablegen mit Auswahl:** Nach einer Ablegen-Karte (Ablegefarbe = Kartenfarbe) bzw. einem Ablegen-Joker (`{a:"play", card, color: Ablegefarbe}`) beginnt die Phase `discard_pick` (in `PLAY_PHASES`), wenn der Leger Nicht-Joker-Karten der Farbe hat; beim Joker immer, weil die Spielfarbe noch fehlt. Ohne Kandidaten bei der farbigen Karte gibt es keine Phase, `discard_color` mit `count` 0 wie bisher.
  - Ereignis `discard_pick{seat, color}` (öffentlich). Sicht `discard_pick = {seat, color}` für alle (nur mit der Hausregel, sonst fehlt das Feld; `{}` außerhalb der Phase), `hints.can_pick` (ids, nur der Leger), `hints.pick_color` (bool, Joker). Hinweistexte: „Wähle, welche Karten in Rot du mit ablegst.“, beim Joker „… und die Farbe, mit der es weitergeht.“ bzw. ohne Kandidaten „Wähle die Farbe, mit der es weitergeht.“; andere sehen „Anna legt Rot mit ab.“
  - Aktion `{a:"discard_pick", cards: [...], color?}`: Teilmenge von `can_pick` (auch leer, keine Doppelten), `color` = Spielfarbe nur und Pflicht beim Joker (bei der farbigen Karte übergangen). Danach `discard_color` mit den gewählten Karten (nach Rang), beim Joker `color` mit der Spielfarbe, dann Fertig/Wirkung wie bisher (`_play_rest`). Die Ablegen-Karte bleibt oben; der Spielfarbwechsel beim Joker kommt erst mit der Auswahl.
  - Mau: In der Phase geht `{a:"mau"}`, wenn nach der Auswahl genau 1 Karte bleiben kann (Hand − Kandidaten ≤ 1 ≤ Hand). Vor dem Legen gilt dasselbe für jede legbare Ablegen-Karte (`_can_leave_one`); 2 Karten mit einer Ablegen-Karte und einer Karte ihrer Farbe erlauben also jetzt den Ruf. Das Mau-Fenster öffnet sich erst nach der Auswahl.
  - Speichern: `to_dict()` hat bei `discard_color=on` das Feld `discard_pick` (`{seat, color, card, wild}` oder `{}`).
  - Computergegner: legt Zahlenkarten mit, behält Aktionskarten, außer er wird mit allen Kandidaten fertig; Spielfarbe beim Joker = häufigste verbleibende Farbe. `left_after` rechnet mit diesem Plan, der Ruf kommt vor dem Legen oder in der Auswahl.
- **Texte:** Kartenhilfe und Übersicht nennen die Auswahl und die getrennte Spielfarbe des Ablegen-Jokers, die vier Tauschrichtungen und das Aufhören beim Glücksspiel; `describe()` sagt bei `free` „Wünscher +2 und Farbjagd dürfen immer gelegt werden.“ N8 (Gerätetest 0.1.1): Die Dopplung kam nicht aus `rules_text.gd`; `RulesText.overview` nennt ausgeschaltete Zusatzkarten nur im Absatz „Weitere besondere Karten“, der zweite Hinweis in `rules_screen.gd` ist schon entfernt.
- **Tests:** `test_rules_discard.gd` (Auswahl, Ablehnungen, Joker mit getrennter Farbe, Joker ohne Kandidaten und als letzte Karte, Mau in der Auswahl, Bot-Auswahl, Rundreise in der Phase), `test_rules_views.gd` (Sicht- und Ereignisfelder, Hinweise gegen `apply()` auch für `discard_pick`), `test_rules_swap.gd` (vier Richtungen mit und ohne Richtungswechsel, Texte), `test_rules_cards.gd` (Standard `free`, `migrate_dict`, `swap_step`). `test_rules_play.gd` setzt für seine Anzweifel-Fälle `bluff` ausdrücklich als Grundlage.

## Flip-Überraschung (Hausregel, 0.1.4)

- **Option** `flip_surprise`: `off` (Standard, offiziell) / `on`. In „Familie“ an.
- **Regel:** Liegt nach einem ausgeführten Flip eine klassische Aktionskarte oben (`MauGame.SURPRISE_KINDS`: +1, +5, Aussetzen, Alle aussetzen, Richtungswechsel, Wünscher +2, Farbjagd), wirkt sie, als hätte der Flip-Spieler sie gelegt. Ereignis `flip_surprise{seat, face}` direkt vor den Wirkungs-Ereignissen.
  - Wünscher +2 und Farbjagd: erst Phase `color` für den Flip-Spieler, nach `{a:"color"}` folgt die Überraschung (`_act_color` erkennt sie an der Oberkarte, kein zusätzlicher Zustand; Speichern mitten in der Farbwahl geht).
  - Flip, Wünscher und Zusatzkarten (Kartentausch, Glücksspiel, Ablegen) oben lösen nichts aus.
  - Stapeln und `penalty_turn` wie beim Legen. Anzweifeln gibt es nicht (niemand hat die Karte gelegt), auch nicht im alten Modus `bluff`.
  - Endet die Runde mit dem Flip (letzte Karte), gibt es keine Überraschung. Läuft sie bei `round_end=last` weiter, wirkt sie wie beim Legen vom gerade Fertigen aus.
- **Computergegner:** unverändert. Die Gegenseite der untersten Ablagekarte liegt verdeckt; ein Bot, der sie kennt, wäre ein Leck.
- **Familie 0.1.4:** zusätzlich `wild_restriction=free`, `swap_direction=play`, `gamble_cards=on`, `discard_color=on`, `flip_surprise=on` (124 Karten). `RuleConfig.migrate_dict` hebt Regeln, die genau der alten „Familie“ entsprechen (`RuleConfig.OLD_FAMILIE`, mit `enforce` oder `free`), auf die neue.
- **Texte:** Kartenhilfe Flip, Regelübersicht (Absatz „Flip“) und Kurzfassung (`describe`) nennen die Überraschung nur, wenn sie an ist.
- **Tests:** `test_rules_flip_surprise.gd` (jede Kartenart, Reihenfolge der Ereignisse, Joker oben mit Farbwahl auch nach Speichern, Bluff-Modus, Stapeln, `penalty_turn=play`, keine Überraschung bei Flip/Wünscher/Zusatzkarten oben, offiziell und am Rundenende, Familie und Hebung, Texte). Die Zufallsprüfungen (`RulesFixture.random_config`) würfeln `flip_surprise` mit.

## Ablage-Protokoll (1.0.1, „Ablage durchsehen“)

- **Sicht:** `view.discard_log` (BETA1_PLAN Abschnitt Sichten): Ablage unten → oben als `{f, s, c, h}`, für alle Plätze gleich. Intern `MauGame.dlog` (id → `{s, c, h}`), gesetzt in `_play` (Leger), `_discard_color` (Mitabgelegte mit Leger), `_stake_under` (Einsatz verdeckt, `h`), `_note_wish` bei jedem Farbereignis (Joker, Farbwahl, Start-Notfall). Flip dreht nur `discard` (Gesichter aus der aktiven Seite), `_reshuffle` behält nur den Eintrag der obersten Karte, Rundenstart leert. Speichern als `dlog`.
- **Lecktest:** `test_rules_views.gd` erwartet die offenen Ablagegesichter im Protokoll (`_expected_keys`) und prüft Form, Reihenfolge, Leger und verdeckte Einsätze (`_check_discard_log`); läuft so auch in `test_rules_gamble.gd`, `test_rules_discard.gd` und `test_rules_swap.gd` mit.
- **Tests:** `test_rules_discard_log.gd` (Legen, Joker mit Farbe, Farbe mit ablegen, Glücksspiel-Einsatz verdeckt, Flip, Mischen, gleiche Liste für alle, Speichern).

## Flip dreht nur die gelegte Karte (1.0.2, Hausregel)

- **Option** `flip_mode`: `pile` (Standard, offiziell: ganze Ablage wenden, oben die bisher unterste Karte mit ihrer anderen Seite) / `card` (nur die Flip-Karte wird umgedreht, oben liegt ihre andere Seite; die übrige Ablage bleibt in ihrer Reihenfolge darunter, „zur Seite gelegt“). Nachziehstapel und Hände wenden sich in beiden Fällen. In „Familie“ `card` (Nutzerentscheidung 07.10.2026).
- **Umsetzung:** `_do_flip` kehrt `discard` nur bei `pile` um. Bei `card` merkt `MauGame.dside` (id → Seite) die Seite, mit der jede Ablagekarte liegt (`_lay`: Legen, Mitabgelegte, Einsatz, Startkarte, Flip-Karte nach dem Flip, oberste nach dem Mischen); `view.discard_log` zeigt darunter diese Seite, oben die aktive. Spielstand speichert `dside` nur bei `card`. Flip-Überraschung wirkt auf die Karte oben (bei `card` die andere Seite der Flip-Karte). Bot unverändert (sagt die Oberkarte nach dem Flip nicht vorher).
- **Familie 1.0.1 → 1.0.2:** `RuleConfig.migrate_dict` hebt Regeln ohne Schlüssel `flip_mode`, die mit `flip_mode=card` der Familie entsprächen, auf die neue Familie. Ein gespeichertes `pile` bleibt.
- **Tests:** `test_rules_flip_mode.gd` (beide Modi: Oberkarte, Reihenfolge, Protokoll auch nach zwei Flips, Überraschung, Speichern, Mischen, Familie, Hebung, Texte); `test_rules_views.gd` (`_shown`) und `RulesFixture.random_config` würfeln `flip_mode` mit.
