# Hausregel „Kontern“ (Beta 1.6.11)

Nutzerwunsch vom 16.10.2026. Schlüssel `counter_round` (`off` | `on`), offiziell aus, in der Voreinstellung „Familie“ an.

## Regel

- Wer keine Karten mehr hat, ist noch **nicht fertig**. Er bleibt mit 0 Karten in der Zugfolge und wartet in der
  **Konter-Runde**. Das gilt für jede Art, leer zu werden: letzte Karte gelegt, beim Glücksspiel den letzten Einsatz gesetzt und 0
  gedrückt, beim Farbe-Ablegen alles mitabgelegt, beim Kartentausch eine leere Hand bekommen.
- **Gekontert:** Bekommt er Karten, bevor der Zug wieder bei ihm ankommt – Ziehkarte oder Strafe (+1, +5, Wünscher +2, Farbjagd,
  auch über die Flip-Überraschung), Kartentausch –, ist die Konter-Runde vorbei und er spielt normal weiter. (Erwischen trifft
  ihn nicht: Mit 0 Karten gibt es kein offenes „Mau!“.)
  Eine Ziehkarte auf einen Wartenden zieht er sofort (ohne Karten kann er nichts drauflegen und nichts anzweifeln); danach gilt
  `penalty_turn` wie sonst (aussetzen bzw. gleich dran).
- **Fertig:** wenn der Zug wieder bei ihm ankäme (ein Richtungswechsel kann das verkürzen oder verlängern) oder wenn er
  übersprungen wird (Aussetzen, Alle aussetzen, eine Strafe mit Aussetzen, bei der er nichts ziehen konnte). Alle aussetzen als
  eigene letzte Karte: Alle anderen sind übersprungen, der Leger ist gleich fertig.
- Mehrere Wartende gleichzeitig sind möglich; sie werden in der Reihenfolge fertig, in der der Zug zu ihnen käme.
- **Kartentausch:** Wartende tauschen mit (sie bekommen eine Hand, ihre leere Hand wandert weiter). Wer die leere Hand bekommt,
  wartet nun selbst. Bekommt sie jemand, der gerade nicht dran war, kommt der Zug erst noch bei ihm an: Beim ersten Ankommen
  geht er weiter (`counter_fresh`, im Spielstand `counter.fresh`), fertig ist er beim nächsten Ankommen oder wenn er übersprungen wird.
  War der Kartentausch die eigene letzte Karte, tauscht der Leger nicht mit (die anderen tauschen
  untereinander), wartet aber wie bei jeder letzten Karte.
- Glücksspiel- und Ablegen-Karten als letzte Karte bzw. nach dem Flip mit leerer Hand: kein Glücksspiel, nichts abzulegen (beim Joker
  nur die Farbwahl). Ein Flip als letzte Karte wird nach `flip_last_card` ausgeführt oder nicht.
- „Mau!“: Ruf und Fenster verfallen beim Leerwerden; einen Wartenden kann man nicht erwischen. Wer gekontert wird, muss mit 2
  Karten wieder rufen.
- Endet die Runde anders (blockiert, zu wenige Spieler) oder ist sie mit dem ersten Fertigen vorbei, zählen Wartende wie die
  Übrigen nach ihren Karten (0 Karten = vorn).

## Festlegungen

- **„Mau-Mau!“, Feier, Statistik erst beim endgültigen Fertig.** Das Ereignis `finish` kommt erst dann (mit `survived: true`); daran
  hängen wie bisher Ton und Doppelblase „Mau-Mau!“, die Statistik („Mau-Mau!“) und am Rundenende Feier/Jubel und Rundensieg. Beim
  Legen der letzten Karte zeigt der Hinweis die Konter-Runde („Kim hat keine Karten mehr – wer kontert?“). Ein eigener Ton oder
  Effekt beim Legen bräuchte eine Änderung in `table_view.gd` bzw. `webclient/tisch.js` (nicht Teil dieser Stufe).
- Bots: Der Vorgänger (und jeder, dessen Nächster wartet) kontert bevorzugt mit Ziehkarten, ein Kartentausch kontert alle
  Wartenden; Aussetzen, Alle aussetzen und ein Richtungswechsel zum Wartenden werden gemieden.
- Furzkissen: Der Wartende macht keine Aktion (`play`/`draw`/`accept`/`stake`), ein Kissen auf ihm pupst also erst, wenn er
  gekontert wurde und wieder handelt; sonst verfällt es am Rundenende wie bisher.

## Protokoll (ältere Clients übergehen alles)

- Ereignisse: `counter_open {seat}` (leer, Konter-Runde beginnt), `countered {seat}` (Karten bekommen), `finish {seat, place,
  survived: true}` (Konter-Runde überstanden).
- Sicht, nur mit der Hausregel: `counter: {wait: [Plätze in der Reihenfolge, in der sie leer wurden], done: Platz | -1}` (`done` =
  eben fertig geworden, bis zur nächsten Handlung) und `players[].counter` (bool).
- Hinweise (`hints.text`/`hints.lt`): „%s hat keine Karten mehr – wer kontert?“, „%d Spieler haben keine Karten mehr – wer
  kontert?“, beim Wartenden „Du hast keine Karten mehr – kontert keiner, bist du fertig.“, danach „%s ist fertig!“.
- Spielstand (`to_dict`, damit auch Schnappschuss und Gastgeber-Übergabe): `counter: {wait, done}`; beim Laden werden nur
  gültige Plätze ohne Karten übernommen. Ein Gastgeber vor 1.6.11 kennt die Regel nicht und spielt nach einer Übernahme ohne sie
  weiter.
- Gespeicherte Regeln ohne den Schlüssel, die sonst genau der „Familie“ entsprechen, werden zur heutigen „Familie“ gehoben
  (`RuleConfig.migrate_dict`).

## Code und Tests

- Regelwerk `game/scripts/rules/mau_game.gd` (`counter_wait`, `counter_fresh`, `counter_done`, `_emptied`, `_countered`, `_counter_final`,
  `_counter_skip_all`, `_new_turn`, `_advance`, `_start_pending`, `_after_penalty`, `_swap_hands`), Optionen
  `rule_config.gd`, Texte `rules_text.gd` und `game/i18n/en_rules.po`, Regelauswahl `rules_screen.gd`, Kurzbeschreibung
  `rules_bar.gd`, Bots `bot.gd`, Browser-Regelübersicht und Kartenhilfe `webclient/karten.js` (`regelnText`, `hilfe`).
- `game/tests/test_rules_counter.gd` (gebaute Fälle, Zufallsprüfungen aus `test_rules_views.gd` mit Kontern, Bot-Dauerlauf mit
  allen Hausregeln), `game/tests/test_net_counter.gd` (Gast über den Vermittler-Nachbau, Lite-Sicht, Schnappschuss und resume).
