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
  übersprungen wird und der Zug an ihm vorbei zu einem anderen geht (Aussetzen mit drei und mehr Spielern, eine Strafe mit
  Aussetzen, bei der er nichts ziehen konnte). Alle aussetzen als eigene letzte Karte: Andere Wartende sind übersprungen und fertig;
  der Leger wartet, der Nächste ist dran (ab 1.6.14, s. u.; bis 1.6.13 war der Leger gleich fertig).
- **Bleibt der Zug beim Leger, setzt der Wartende nur aus** (ab der Beta nach 1.6.15, Nutzerbefund 25.10.2026: zu zweit, der andere
  hatte eben seine letzte Karte gelegt, ein Flip mit Richtungswechsel auf der Rückseite – Flip-Überraschung – machte ihn sofort
  fertig, „obwohl er aussetzt und man noch dran wäre“). Das gilt zu zweit für Aussetzen und Richtungswechsel (gelegt oder aus der
  Flip-Überraschung) und für Alle aussetzen mit beliebig vielen Spielern: Der Leger ist noch einmal dran und kann kontern; legt er
  normal, kommt der Zug zum Wartenden, und der ist fertig. Nutzerentscheidung: „immer, wenn der Leger dran bleibt“. Code:
  `MauGame._skip_keeps_turn`, `_counter_skip_all` (finisht nur noch, wenn der Leger selbst wartet). Bis 1.6.15 war der Wartende in
  diesen Fällen sofort fertig.
- **Nach der letzten Karte ist immer noch mindestens ein anderer dran** (ab Beta 1.6.14, Nutzerbefund 18.10.2026: zu dritt, einer
  fertig, Aussetzen als letzte Karte – die Runde war sofort vorbei, „der andere Spieler hätte noch die Möglichkeit haben müssen, eine
  Karte zu ziehen“). Wer in seinem eigenen Zug leer wird, ist mit `counter_guard` markiert, bis ein anderer dran ist; kommt der Zug
  vorher zu ihm zurück, geht er weiter. Zu zweit setzt der andere nach Aussetzen bzw. Richtungswechsel als letzter Karte deshalb nicht
  aus (kein `skip`-Ereignis), nach „Alle aussetzen“ als letzter Karte ist der Nächste dran. Mit drei und mehr Spielern wirkt Aussetzen
  wie bisher (der Übernächste ist dran). Im Spielstand als `counter.guard` (ältere Gastgeber übergehen es).
- Mehrere Wartende gleichzeitig sind möglich; sie werden in der Reihenfolge fertig, in der der Zug zu ihnen käme.
- **Kartentausch:** Wartende tauschen mit (sie bekommen eine Hand, ihre leere Hand wandert weiter). Wer die leere Hand bekommt,
  wartet nun selbst. Bekommt sie jemand, der gerade nicht dran war, kommt der Zug erst noch bei ihm an: Beim ersten Ankommen
  geht er weiter (`counter_fresh`, im Spielstand `counter.fresh`), fertig ist er beim nächsten Ankommen oder wenn er übersprungen wird.
  War der Kartentausch die eigene letzte Karte, **tauscht der Leger mit** (ab Beta 1.6.13, Nutzerwunsch 18.10.2026: „die
  Lücke wandert weiter“): Er bekommt die Hand seines Vorgängers in Tauschrichtung und spielt normal weiter (`counter_open`, dann
  `countered` für ihn), seine leere Hand geht an den Nächsten, der nun wartet (frisch, s. o.). Zu zweit bekommt der Leger die Hand
  des anderen. Gilt ebenso für einen Kartentausch aus der Flip-Überraschung. Bis 1.6.12 tauschte der Leger nicht mit (die anderen
  untereinander) und wartete selbst. Ohne Kontern bleibt es dabei: Als letzte Karte ist er fertig, die anderen tauschen
  untereinander. Bots legen den Kartentausch mit Kontern nicht als letzte Karte (`swap_value` negativ), sondern ziehen, außer
  jemand wartet.
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
  Wartenden; Aussetzen (mit drei und mehr Spielern) und ein Richtungswechsel zum Wartenden werden gemieden. Zu zweit und bei Alle
  aussetzen bleibt der Bot dran, der Wartende wartet nur weiter – dort gibt es keinen Abzug mehr (zu zweit ohne
  `two_player_reverse_skips` kommt der Zug nach einem Richtungswechsel zum Wartenden: weiter gemieden).
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
