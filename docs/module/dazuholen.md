# Modul „Dazuholen und entfernen“ (Beta 1.4.2)

Stand 10.10.2026, Entwurf. Nutzerwunsch: Mitten im Spiel jemanden an den Tisch holen (QR, Platz wählen) oder herausnehmen. Wer ausfällt (Akku leer, keine Lust, getrennt, „in einer anderen App“), bekommt beim Gastgeber **sofort** zwei Knöpfe: „Computer übernimmt“ und „Aus dem Spiel nehmen“. Die 30-s-Wartezeit (`SUB_OFFER_MS`) entfällt. Nichts passiert ohne Tippen und Rückfrage.

Gilt nur für das Netzwerkspiel (WLAN, Spiel-WLAN, online) mit `HostTable`. Weitergeben und Solo bleiben vorerst unverändert. Die Regelwerk-API ist allgemein und kann später auch dort genutzt werden.

## 1. Regelwerk (`MauGame`)

Plätze sind Indizes. Beim Dazuholen und Entfernen wird **neu durchnummeriert**: Die Sitzordnung bleibt eine lückenlose Liste im Uhrzeigersinn. So brauchen `view_for`, die Bots, die Statistik und alle Clients keine Lücken zu kennen.

```gdscript
func can_change_seats() -> bool        # state in ["turn", "round_over"] (nicht color/drawn/challenge/gamble/discard_pick/idle/game_over)
func insert_player(at: int, info: Dictionary) -> Dictionary   # {ok, reason, events, seat}; info {name, kind}
func remove_player(seat: int) -> Dictionary                    # {ok, reason, events}; Gastgeber-Platz nicht
func _remap(map: Array) -> void       # map[alt] = neu bzw. -1
```

`_remap` stellt um: `players, connected, hands, mau_said, place, scores`, `host, dealer, current, mau_open`, `pending.by/victim`, `finished`, `gamble.seat`, `dpick.seat`, `dlog[*].s` (−1 bleibt −1, ein entfernter Leger wird zu −1), `result` (Listen `points/gains/scores/hands` je Platz, `ranking`). `seen` wird geleert, `pass_streak = 0`. Höchstens `MAX_PLAYERS` (10), mindestens `MIN_PLAYERS` müssen bleiben. Sonst gilt Abschnitt 1.3.

### 1.1 Wann es wirkt

Sofort, wenn `can_change_seats()`, also zwischen zwei Zügen (`turn`, auch mit offener stapelbarer Strafe) oder am Rundenende. Sonst (Farbwahl, gezogene Karte, Anzweifeln, Glücksspiel, Ablege-Auswahl) merkt sich `HostTable` den Auftrag und führt ihn nach der nächsten Änderung aus, sobald es wieder geht. In der Oberfläche steht dann: „Kommt nach diesem Zug dazu“. **Ausnahme Entfernen:** Ist der Entfernte selbst am Zug, wirkt es sofort (siehe 1.3). Sonst könnte ein Abwesender das Spiel blockieren.

### 1.2 Dazuholen

- **Platz:** `at` = Index in der neuen Reihenfolge (0 … n). Der Gastgeber wählt ihn.
- **Karten:** `k = clamp(max(Handgröße aller aktiven Plätze außer dem Neuen), 1, config.hand_size)`. Aktiv heißt `place == 0`. Gezogen wird über `_draw(seat, k, "join", ev)` (bei leerem Stapel wird wie immer die Ablage gemischt). Sind nicht einmal so viele Karten frei, bekommt der Neue, was da ist. Ist **gar keine** frei, wird er wie am Rundenende behandelt: Er sitzt mit, bekommt die Karten beim nächsten Austeilen und ist bis dahin `place = 0` mit leerer Hand. In diesem Fall wird er übersprungen (`_next_in` wird um „Hand leer und nicht fertig“ ergänzt).
- **Am Rundenende** (`round_over`): Er sitzt sofort mit leerer Hand am Tisch und bekommt seine Karten bei `next_round` (normales `_start`). In `result` bekommt er die Einträge `points 0, gains 0, hands []`. In `ranking` steht er nicht.
- **Wer ist dran:** `current` bleibt. Es geht in Sitzordnung weiter. Sitzt der Neue direkt hinter dem aktuellen Spieler (in Spielrichtung `dir`), ist er als Nächster dran. **Begründung:** Das ist wie an einem echten Tisch, bei dem man sich dazusetzt. Der Gastgeber hat den Platz bewusst gewählt, und eine Sonderregel („erst eine Runde aussetzen“) müsste man erklären und in `_next_in` sowie in `_stalled` mitführen. Eine offene Strafe trifft weiter ihr bisheriges Opfer (`pending.victim` wird nur umnummeriert), nie den Neuen.
- **Mau:** `mau_said[neu] = false`. Das Mau-Fenster (`mau_open`) bleibt beim bisherigen Platz. Bekommt der Neue genau 1 Karte, muss er nicht „Mau!“ rufen (wie beim Kartentausch).
- **Punkte:** Der Neue startet mit dem **niedrigsten Stand der anderen** (`min(scores)`). Das gilt bei `points500` und bei Rundensiegen. So hat er keinen Vorteil, ist aber auch nicht chancenlos. Wer nach dem Entfernen wiederkommt, wird genauso behandelt (kein Merken alter Stände).
- **Ereignisse:** `{e:"seats", map:[neuer Index je altem Platz], join: neu, leave: -1, name, kind}`, danach `{e:"draw", seat: neu, count: k, reason:"join", …}` (kein `round_start`/`deal`; `events_for` filtert es wie jedes Ziehen).

### 1.3 Entfernen

Reihenfolge in `remove_player(r)`:
1. **Karten:** die Hand von `r` und ein laufender Glücksspiel-Einsatz von `r` (`gamble.stake`) gemischt **unter** den Ziehstapel (`draw_pile.insert(0, …)`). Ereignis `{e:"leave_cards", seat:r, count}` (nur die Zahl, keine Gesichter).
2. **Offene Zustände**, wenn `r` beteiligt ist:
   - `pending.victim == r` → die Strafe **verfällt**.
   - `pending.by == r` im Zustand `challenge` → die Strafe verfällt, das Opfer spielt normal weiter (`_new_turn(victim)`). Ein Anzweifeln lässt sich ohne die Hand des Legers nicht prüfen.
   - `state == "color"` und `current == r` → Zufallsfarbe der aktiven Seite, `wished = true`, Ereignis `color` mit `seat:-1` (wie bei der Notfall-Startkarte).
   - `dpick.seat == r` → die Auswahl entfällt (die Ablegen-Karte bleibt oben liegen, keine weiteren Karten).
   - `gamble.seat == r` → `gamble = {}` (der Einsatz ist schon nach 1. verteilt).
   - `mau_open == r` → −1. `finished` ohne `r`, die Plätze `place` der Fertigen werden neu von 1 an vergeben.
   - `dealer == r` → `dealer` = der Platz vor `r` (gegen `dir` = 1), damit das Austeilen der Reihe nach weitergeht.
3. **Zug:** War `r` dran (in jeder Phase), wird zuerst `nxt = _next_in(r, dir)` bestimmt, dann umnummeriert und `_new_turn(map[nxt])` aufgerufen. Sonst bleibt `current` (umnummeriert) und auch die Phase.
4. **`_remap`**, Ereignis `{e:"seats", map, join:-1, leave:r, name, kind}`.
5. **Zu wenige:** Bleibt nur 1 Spieler, folgt `_end_round("left", ev)` und dann `state = "game_over"` mit `game_over` (Sieger ist der Übriggebliebene; der Gastgeber kann zurück in die Lobby). Sind es noch ≥ 2 Spieler, aber nur 1 aktiver (die anderen fertig), endet die Runde normal über `_round_should_end()` → `_end_round("left")`. Der Grund `"left"` ist neu: Ältere Geräte zeigen dafür den Standardtext (sie kennen nur `"blockiert"` gesondert).

Im Zustand `round_over` entfällt Schritt 3. `result` wird umnummeriert (der Entfernte fällt aus `ranking` und den Listen heraus).

### 1.4 Speichern

`to_dict/from_dict` brauchen nichts Neues (alles wird schon je Platz gespeichert). `FORMAT` bleibt 1.

## 2. Gastgeber (`HostTable`, `GameTable`, `NetHostSession`)

- **Einladen im Spiel:** `NetHostSession.join_open` (neu, Standard false). Ist es an und läuft eine Partie, bekommt ein neuer Gast ohne bekannten Token **kein** `reject running` mehr, sondern kommt in die **Warteliste**: `players[id]` mit `seat = -1`, `waiting = true`. Er bekommt `welcome` und `{t:"lobby", late:true, waiting:true, host_name, players:[…]}`. `join_open` ist an, solange beim Gastgeber das Feld „Mitspieler“ offen ist oder jemand auf der Warteliste steht. `max_players` zählt Wartende mit.
- **Warteliste:** `session.waiting_ids()`. Wird ein Wartender getrennt, wird er nach 60 s gestrichen. „Ablehnen“ ruft `session.remove_player(id, "Der Gastgeber hat dich nicht dazugeholt.")` auf und sendet `bye`.
- **Aufträge:** `HostTable.seat_in(id, at)` (Gast von der Warteliste), `add_bot_at(at, name="")` (Computergegner, Name aus `BOT_NAMES`), `remove_seat(seat)` (Mensch oder Bot, nie der Gastgeber). Sie landen in `_seat_ops` und werden in `_after_change`/`_pre_step` ausgeführt, sobald `game.can_change_seats()` (Entfernen eines Spielers am Zug: sofort). `pending_seat_ops()` dient der Anzeige.
- **Nach dem Ausführen:** `_seat_ids`, `seats` (GameTable), `_substitute` (Schlüssel umnummerieren), `host_seat = game.host`, `_waiting_seat = -1`, `_plan_dirty = true`, `session.set_seat_order(_seat_ids)` (Seat-Felder der Sitzung). Neuer Gast: `waiting = false`, dann `send_to(id, {t:"start", seat})`. Entfernter Gast: `session.remove_player(id, "Der Gastgeber hat dich aus dem Spiel genommen.")` (`bye`). Danach `_changed(events)` **als eigener Stand**: Die Ereignisse vor und nach der Umnummerierung stecken nie in derselben `state`-Nachricht, damit die Platznummern in Ereignissen und Sicht zusammenpassen. Hinweise an alle: „%s spielt jetzt mit.“ / „%s ist nicht mehr dabei.“
- **Wiederkommen:** Ein Entfernter hat keinen gültigen Token mehr. Er meldet sich als neuer Gast an und landet bei offenem Einladen auf der Warteliste (neuer Platz, neue Karten, Punkte nach 1.2). Bei geschlossenem Einladen bekommt er wie bisher `reject running`.
- **Vertretung:** `sub_offer_ms` wird 0 (`NetProtocol.SUB_OFFER_MS = 0`, die Eigenschaft bleibt für Tests). `substitutable_seats() == absent_seats()`: Jeder Gast, der getrennt oder `away` ist und keine Vertretung hat, bekommt sofort beide Möglichkeiten. Der Auto-Vertreter (`auto_substitute_s`) bleibt unverändert.
- **Statistik** (`AppStats.record`, je Gerät): keine Änderung. Ein Dazugeholter zählt Partie, Sieg usw. ab seinem Einstieg, weil er die Ereignisse sieht. Ein Entfernter zählt die Partie nicht (er sieht kein Rundenende). `draw` mit `reason:"join"` darf „größte Hand“ erhöhen (ist ein Maximum, bleibt richtig).

## 3. Protokoll und Anzeige

Alles zusätzlich, `PROTO` bleibt 1:

| Nachricht/Ereignis | Neu | Ältere Geräte |
|---|---|---|
| `{t:"lobby", late, waiting}` an Wartende | Anzeige „Du bist auf der Warteliste. Der Gastgeber holt dich gleich an den Tisch.“ | zeigen eine Lobby, danach kommt `start` → Spiel (geht schon heute) |
| `{t:"start", seat}` an den Neuen | wie beim Partiestart | wie bisher |
| `state` mit geänderter Spielerzahl | `view.seat` neu, Plätze neu | `ClientTable` übernimmt `view.seat` schon heute; `TableView.apply_view` legt Plätze nach `seat` an bzw. löscht sie |
| `{e:"seats", map, join, leave, name, kind}` | Animation, Platzknoten zurücksetzen | unbekanntes Ereignis wird übersprungen |
| `{e:"draw", reason:"join"}` | Austeil-Flug zum Neuen | normales Zieh-Ereignis |
| `{e:"leave_cards", seat, count}` | Karten fliegen unter den Ziehstapel | wird übersprungen |
| `round_over.reason = "left"` | „Zu wenige Spieler – “ | Standardtext |

**Anzeige (App und Lite):** Bei `seats` werden die Gegnerplätze neu aufgebaut (in der App `TableView._seats` leeren, weil der Schlüssel der Platzindex ist; im Lite die Sitzanordnung neu berechnen). Beim Neuen erscheint eine Sprechblase „Hallo!“ mit einem kurzen Einblenden (Platz gleitet auf, die übrigen rücken weich zur Seite, 0,4 s). Beim Entfernten blendet der Platz aus und seine Karten fliegen verdeckt unter den Ziehstapel. Die Richtungsanzeige bleibt. Der große Modus (rollende Liste) zeigt dasselbe in der Liste. Tag/Nacht und Schriftgröße folgen den vorhandenen Bausteinen (`UiFonts`, `UiPalette`).

## 4. Oberfläche beim Gastgeber (App)

- **Sofort-Leiste** (ersetzt `_sub_btn`/`_sub_hint` in `table_screen.gd`): Für den ersten abwesenden Gast (zuerst der, auf den das Spiel wartet) steht eine ruhige Zeile im Tag/Nacht-Stil: „Kim ist in einer anderen App“ bzw. „Kim ist getrennt“, dazu zwei GhostButtons: **„Computer übernimmt“** und **„Aus dem Spiel nehmen“**. Bei mehreren Abwesenden steht „+1“, der Rest ist über „Mitspieler“ erreichbar. Rückfragen:
  - „Computer übernimmt?“ – „Ein Computergegner spielt für %s. Kommt %s zurück, spielt er wieder selbst.“ (wie bisher)
  - „%s aus dem Spiel nehmen?“ – „%s scheidet aus. Seine Karten kommen unter den Ziehstapel. Über „Mitspieler dazuholen“ kann er später neu einsteigen.“ Knöpfe „Herausnehmen“ / „Abbrechen“.
- **Menü:** ☰-Menü (`IngameMenu.ITEMS`) und Zurück-Menü bekommen nur beim Netz-Gastgeber den Eintrag **„Mitspieler“**. Er öffnet das Feld „Mitspieler“ (neu `ui/screens/seat_manager.gd`) mit zwei Seiten:
  1. **Dazuholen:** das vorhandene `InvitePanel` (WLAN-/Spiel-WLAN-QR, Online-QR, Raumcode, „Link teilen“), dazu „+ Computergegner“.
  2. **Am Tisch:** die Sitzordnung als Liste (wie in der Lobby, mit Kennung App/Browser/Computer und Status). Wartende erscheinen hervorgehoben. Mit ▲▼ rücken sie an den gewünschten Platz (nur sie bewegen sich, die Sitzenden bleiben in ihrer Reihenfolge). Danach **„An den Tisch holen“** (Rückfrage mit Platz und Kartenzahl: „Kim setzt sich zwischen Anna und Ben und bekommt 5 Karten.“) oder „Ablehnen“. Bei jedem Sitzenden außer dem Gastgeber steht ✕ „Aus dem Spiel nehmen“ (Rückfrage wie oben, bei Computern ohne den Satz zum Wiederkommen).
  Läuft der Auftrag noch, steht in der Zeile „Kommt nach diesem Zug dazu“ bzw. „Geht nach diesem Zug“.
- Gäste (App und Lite) sehen nur die Hinweise und die Animation, keine Verwaltung.

## 5. Tests

- `test_rules_seats.gd` (neu): Einfügen an jedem Platz vor/hinter `current` mit beiden Richtungen; Kartenzahl (max/Start/min 1, leerer Stapel); Punkte `min`; Entfernen in jeder Phase (turn mit Stapelstrafe, drawn, challenge mit by/victim, color, gamble mit Einsatz, discard_pick); Karten landen unten im Ziehstapel; Kartenerhaltung (Summe aller ids = `n_cards`); 2→1 Spieler → game_over; Fertige werden neu platziert; `to_dict/from_dict` nach dem Umbau; Dauerlauf mit zufälligem Dazuholen/Entfernen durch Bots (`teil.gd`-fähig).
- `test_game_net_seats.gd` (neu): Warteliste bei `join_open`, sonst `reject running`; `seat_in` mit aufgeschobenem Auftrag (Farbwahl offen); Neuer bekommt `start` und dann `state` mit richtigem `view.seat`; Entfernter bekommt `bye`; Vertretung sofort (`substitutable_seats` ohne Wartezeit); Rückkehr eines Entfernten nur über die Warteliste.
- `test_ui_seats.gd` + Kontrollbilder (Tag/Nacht, großer Modus, Schrift „Sehr groß“): Sofort-Leiste, Feld „Mitspieler“, Animation.
- `test_web_contract.gd`: `seats`, `leave_cards`, `draw reason join`, `lobby.waiting`, Grund `left`, neue Texte in `i18n_en.js`/.po. `test_i18n` streng.

## 6. Dateiaufteilung (überschneidungsfrei)

- **core:** `game/scripts/rules/mau_game.gd`, `game/scripts/game/game_table.gd`, `game/scripts/game/host_table.gd`, `game/scripts/game/client_table.gd` (Wartezustand `waiting`), `game/scripts/net/net_session.gd`, `game/scripts/net/net_protocol.gd`, `game/tests/test_rules_seats.gd`, `game/tests/test_game_net_seats.gd`, `game/i18n/en_rules.po` (alle neuen Texte aus Regelwerk/Gastgeber/Sitzung).
- **app:** `game/scripts/ui/table_screen.gd`, `game/scripts/ui/table_view.gd`, `game/scripts/ui/director.gd`, `game/scripts/ui/opponent_seat.gd`, `game/scripts/ui/big_layout.gd`, `game/scripts/ui/ingame_menu.gd`, `game/scripts/ui/screens/seat_manager.gd` (neu), `game/scripts/ui/screens/invite_panel.gd` (Einbettung im Spiel), `game/scripts/ui/screens/join_screen.gd` (Warteliste), `game/tests/test_ui_seats.gd`, `game/i18n/en_screens.po`, `game/i18n/en_table.po`.
- **web:** `webclient/app.js`, `webclient/tisch.js`, `webclient/i18n_en.js`, `webclient/style.css`, `game/tests/test_web_contract.gd` (`i18n_po.js` entsteht beim Bauen).

## 7. Offen

- Weitergeben/Solo: Dazuholen dort später (gleiche Regelwerk-API).
- Gastgeber selbst kann nicht entfernt werden (das wäre die Gastgeber-Übergabe, zurückgestellt).
- Wartende Gäste mit älterer App: Sie sehen eine normale Lobby ohne Wartetext. Das ist unkritisch.
