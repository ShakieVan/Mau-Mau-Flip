# Modul G – Spielsteuerung

Stand 05.10.2026 (Beta 0.1.1). Beschrieben nach dem Code in `game/scripts/game/`. Grundlage: `docs/BETA1_PLAN.md` Abschnitt 6.

## Dateien

| Datei | Klasse | Aufgabe |
|---|---|---|
| `table_source.gd` | `TableSource` (Node) | Einheitliche Schnittstelle für die Tischoberfläche, Speicherstand-Hilfen |
| `game_table.gd` | `GameTable` (erbt `TableSource`) | Gemeinsame Basis mit eigenem Regelwerk: `MauGame`, Computergegner-Takt, Speicherstand |
| `local_table.gd` | `LocalTable` (erbt `GameTable`) | Übungsspiel (`"solo"`) und Weitergeben (`"pass"`) |
| `host_table.gd` | `HostTable` (erbt `GameTable`) | Netzwerkspiel, Gastgeber: Lobby und Partie über `NetHostSession` (Modul D) |
| `client_table.gd` | `ClientTable` (erbt `TableSource`) | Netzwerkspiel, App-Mitspieler über `NetClient` (Modul D) |

Erzeugt werden die Quellen von `GameStarter` (`game/scripts/ui/screens/game_starter.gd`, Modul F2).

## Schnittstelle `TableSource`

```gdscript
signal state_changed(events: Array, view: Dictionary)   # Ereignisse abspielen, dann mit der Sicht abgleichen
signal notice(text: String)                              # Hinweis: Ablehnung, Verbindung, getrennte Spieler …
signal handover(next_seat: int, name: String)            # nur Weitergeben: Sichtschutz zeigen, danach reveal()
signal lobby_changed(lobby: Dictionary)                  # Netz: {t:"lobby", rev, players, rules, host_id}
signal connection_changed(state: String)                 # Client: "connecting" | "open" | "closed" | "rejected"
signal game_started(seat: int)                           # Partie beginnt, eigener Platz

func act(action: Dictionary) -> void      # Aktion des eigenen Platzes; Ablehnung kommt als notice
func local_seat() -> int                  # wessen Hand gezeigt wird (-1: keine, z. B. Sichtschutz offen)
func mode() -> String                     # "solo" | "pass" | "host" | "client"
func current_view() -> Dictionary         # letzte Sicht ({} vor dem ersten Stand)
func reveal() -> void                     # Weitergeben: Sichtschutz aufgedeckt
func leave() -> void                      # Tisch verlassen: Netz schließen, Speicherstand löschen

static func has_saved(path) / load_saved(path) / clear_saved(path)   # user://laufende_partie.json
```

Sichten und Ereignisse kommen bereits gefiltert für `local_seat()` an (`MauGame.view_for` / `events_for`). Eine fremde Hand erreicht die Oberfläche nie.

## GameTable (Basis von LocalTable und HostTable)

- Jede angenommene Aktion läuft über `_apply()` und dann `_changed(events)`. Dort steigt der Zähler `rev`, der Stand wird gespeichert (`autosave`), verteilt (`_distribute`, je Unterklasse), und der nächste Bot-Zug wird neu geplant.
- **Computergegner** handeln nie sofort:
  - Denkpause 0,6–1,2 s, „Mau!“ nach 0,35 s, nach dem Austeilen zusätzlich 1,2 s; alles mal `speed` (Tests: 0).
  - Bots werden auch außerhalb ihres Zugs gefragt (Erwischen).
  - Ist bei einem Menschen das Mau-Fenster offen, bekommt er eine Schonfrist von 1,5 s (+ bis 0,5 s), bevor ein Bot ihn erwischt oder mit seinem Zug das Fenster schließt.
  - `busy_check` (vom Tisch: `director.is_busy`) hält Bots an, solange die Regie noch abspielt; neuer Versuch nach 0,3 s.
  - Lehnt das Regelwerk eine Bot-Aktion ab (sollte nicht vorkommen), versucht der Takt `draw`, `accept`, `keep`, `color`, damit das Spiel nie hängt (`push_warning`).
- Zeit läuft nur in `pump()` (aus `_process`, wenn `auto_process`). Tests rufen `pump()` selbst.
- `view_of(seat)` passt `hints.can_next_round` an die Spielsteuerung an: Bei `LocalTable` darf jeder Mensch weiterschalten, bei `HostTable` nur der Gastgeber.
- **Speicherstand** `{format: 1, mode, saved, game: MauGame.to_dict(), seats, host_seat, extra}`. Er wird über eine `.tmp`-Datei geschrieben und dann umbenannt.

## LocalTable

- `setup(mode, players, config, seed) -> bool`: Für `"solo"` genau 1 Mensch, für `"pass"` mindestens 2 Menschen, insgesamt 2–10 Spieler. Sonst kommt `notice` und das Ergebnis ist `false`. Der erste Mensch ist Gastgeber-Platz.
- `start()` sendet `game_started` und teilt aus. `resume(data)` setzt einen Speicherstand fort.
- **Weitergeben:**
  - Gezeigt wird immer genau eine Hand.
  - Muss ein anderer Mensch handeln (Zug, Anzweifeln, Farbwahl, gezogene Karte), kommt erst `handover(next_seat, name)`. Bis `reveal()` ist `local_seat()` = −1, Ereignisse werden gesammelt, und Bots warten.
  - Nach dem eigenen Zug kommt der Sichtschutz erst nach 0,6 s (die Karte fliegt noch). Hat der Spieler gerade seine vorletzte Karte gelegt, wartet er die Mau-Schonfrist ab, damit „Mau!“ auch nach dem Legen geht.
  - Ziehen Bots zwischendurch, sieht der zuletzt gezeigte Mensch mit seiner eigenen Hand zu.
- `act()` ohne gezeigte Hand meldet „Erst das Handy weitergeben.“; `next_round` gilt immer für den Gastgeber-Platz.

## HostTable

- **Lobby:**
  - `open(host_name, port_first, port_last)` startet `NetHostSession` (Port 24690…24699, UDP-Suche, Web-Zip, APK-Anbieter aus `App.apk_share`).
  - Weitere Funktionen: `add_bot()` (Katzennamen), `remove_player(id)`, `set_seat_order(ids)`, `set_rules(cfg)` und `host_urls()` für QR-Code und Text.
- `start(seed)`: ab 2 Spielern. `MauGame` entsteht in der Sitzordnung der Lobby; der Gastgeber-Platz bekommt `host: true`, nur er darf `next_round`.
- **Verteilung nach jeder Änderung:**
  - Der Gastgeber bekommt `state_changed`.
  - Jeder verbundene Gast bekommt `{t:"state", rev, seq_ack?, events: events_for(seat), view: view_of(seat)}`.
  - Hinweise an alle gehen als `{t:"notice", text}`.
- **Gast-Aktionen** `{t:"act", seq, a}` gelten immer für den Platz des Absenders. Ablehnungen gehen als `{t:"err", text, seq_ack?}`; `next_round` von einem Gast wird abgelehnt.
- **Trennen und Wiederkommen:**
  - Der Platz bleibt. Ist ein getrennter Mensch am Zug, wartet das Spiel; alle sehen „… ist getrennt – warte …“.
  - `substitute_bot(seat)` lässt einen Bot einspringen. Mit `auto_substitute_s > 0` geschieht das automatisch; Standard 0 = warten.
  - Wer mit seinem Token zurückkommt, bekommt sofort den Stand. Handelt der Mensch selbst, endet der Ersatz.
- `resume(data)`: Sitzung neu eröffnen, Gäste mit ihren Token eintragen (zunächst getrennt), Computergegner neu anlegen.
- `back_to_lobby()` verwirft die Partie, die Spieler bleiben. `leave()` beendet die Sitzung mit „bye“ an alle.

## ClientTable

- `join(address, port, name, token)` verbindet über `NetClient` mit `kind: "app"`. Das Token wird je Gastgeber-Adresse gemerkt, und die Verbindung wird bei Verlust selbst erneuert.
- **Nachrichten:**
  - `lobby` → `lobby_changed`, `start` → `game_started`, `state` → `state_changed`.
  - `err` und `notice` → `notice`.
  - `reject` → `connection_changed("rejected")` plus `notice`; bei falscher Version mit dem Hinweis `http://<host>:<port>/apk`.
  - `bye` → `notice` plus `"closed"`.
- `act()` schickt `{t:"act", seq, a}`; ohne Verbindung kommt ein Hinweis. `set_ready(bool)` meldet den Bereit-Status in der Lobby.

## Mau-Ruf für alle (AGENTS.md 21)

Der Ruf ist eine normale Aktion `{a:"mau"}`. Das Regelwerk erzeugt das Ereignis `mau{seat}`, beim Fertigwerden `finish{seat}`. `events_for` gibt beide an **jeden** Platz weiter: an den Gastgeber über `state_changed`, an App-Gäste und Browser-Gäste über `{t:"state"}`. Jedes Gerät spielt daraufhin den Ton und zeigt die Sprechblase (`F2.md`, Browser: `webclient/tisch.js`). Die Spielsteuerung selbst spielt keinen Ton.

## Abweichungen vom Plan

| Plan | Umsetzung | Grund |
|---|---|---|
| `handover(next_seat)` | `handover(next_seat, name)` | Der Sichtschutz nennt den Namen, ohne die Sicht zu kennen. |
| Signale nur `state_changed`, `notice` | dazu `lobby_changed`, `connection_changed`, `game_started` | Lobby, Verbindungsanzeige und Wechsel Lobby → Tisch |
| Speichern nur beim `HostTable` | auch `LocalTable` speichert | Gemeinsame Basis; Fortsetzen nach App-Neustart möglich |
| Protokoll ohne `notice`/`rev` | `{t:"notice"}` und `rev` in `state` | Hinweise an alle; Gäste erkennen verpasste Stände |

## Tests

| Test | Inhalt |
|---|---|
| `game/tests/test_game_local.gd` | Übungsspiel (1 Mensch + 3 Bots) bis Rundenende und weiter in Runde 2; Denkpausen; Weitergeben mit 3 Menschen (+0/1 Bot) und 2 Menschen + 2 Bots: Sichtschutz vor jedem Menschenwechsel, nie eine fremde Hand in `state_changed`, keine fremden gezogenen Gesichter; Speichern und Fortsetzen |
| `game/tests/test_game_net.gd` | HostTable und ClientTables über 127.0.0.1 (TCP 24890/24891): Lobby mit Bot und Sitzordnung (Gastgeber nicht auf Platz 0), ganze Runde, Lecktest auf allen empfangenen Nachrichten, Fehlaktionen, Trennen und Wiederkommen mit Token, Ersatz-Bot, nächste Runde, Versionsablehnung mit `/apk`-Hinweis, Fortsetzen samt Token, „bye“ |

Ergebnisse: siehe `docs/IMPLEMENTIERUNG.md`.

## Offene Punkte

- Die Oberfläche bietet „Partie fortsetzen“ noch nicht an. `TableSource.has_saved()`, `LocalTable.resume()` und `HostTable.resume()` sind fertig und getestet.
- `HostTable._restore_guest()` greift auf Interna von `NetHostSession` zu (`_next_id`, `_next_seat()`). Eine eigene Funktion in Modul D wäre sauberer.
- Browser-Gäste spielen über dieselbe Sitzung (`kind: "web"`); ihr Client ist Modul E und nutzt dasselbe `state`-Format.
