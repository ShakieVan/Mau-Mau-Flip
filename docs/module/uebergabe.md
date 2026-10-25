# Modul „Gastgeber-Übergabe“ (Betas 1.6.1 und 1.6.2)

Stand 13.10.2026, Entwurf nach der Gegenprüfung. Nutzerentscheidungen: (1) **geplant**: Der Gastgeber tippt „Gastgeber übergeben“, wählt einen App-Gast, der vollständige Spielstand geht an ihn, alle werden umgeleitet. (2) **unerwarteter Ausfall** (Akku leer, Absturz, App versehentlich geschlossen): **Jeder App-Gast** hält ständig eine Sicherungskopie des vollständigen Spielstands. Die App zeigt fremde Karten daraus nie an; das ist ein akzeptierter Kompromiss. Ein Ersatz-Gastgeber übernimmt nach einigen Sekunden automatisch. Zusätzlich gibt es „Spiel als Gastgeber fortsetzen“ von Hand. Auch der Gastgeber selbst speichert und kann nach einem Absturz fortsetzen. (3) Erst online, dann WLAN und Spiel-WLAN.

**Ergebnis der Prüfung: Der Vermittler bleibt unverändert.** Mit dem Raum-Token kann jedes Gerät den Raum als Gastgeber übernehmen (`relay/src/core.js:203-215`): Der alte Gastgeber-Socket bekommt 4000, Code und Raum bleiben. `GET /info?room=CODE` meldet schon heute `{open, host}` (`worker.js:52`, `core.js:230`). Alles Weitere passiert in der App. Der Lite-Client braucht für Stufe 1 ebenfalls keine Änderung.

## 1. Spielstand-Schnappschuss

### 1.1 Format (`format: 2`)

Neue Klasse `MatchSnapshot` (`game/scripts/game/match_snapshot.gd`, nur statische Funktionen). Der Inhalt baut auf `GameTable._save()` auf (`game_table.gd:296`):

```
{format:2, mode:"host", role:"host"|"guest", gid, gen, epoch, parent:[gen, epoch, seq], seq, saved_unix,
 game: MauGame.to_dict(),                 # Regelzustand inkl. rng_state, gamble.q, discard_pick/undo, mau_open, dlog
 seats: [{name, kind, host, net:"app"|"web"|"bot", token}],   # ohne id; JEDER Menschenplatz hat dauerhaft ein Token, auch der Gastgeber
 host_seat,                               # Token des Gastgebers = seats[host_seat].token (kein eigenes Feld)
 substitute: [Platz …],                   # „Computer spielt für …“ (heute verloren, game_table.gd:46/320)
 gone_names: [Name …],
 waiting: [{name, net, token}], join_open, # Warteliste (Dazuholen, seit 1.4.2)
 heirs: [Token …],                        # Ersatz-Rangfolge (4.2); [] = keine automatische Übernahme
 wlan_humans: bool,                       # entfernte Menschen im WLAN am Tisch (Stufe 1: sperrt Automatik)
 online: {relay, room, token, conns:[c …], max_c, created_unix} | {},
 wlan: {port, addrs:[…]},                 # Stufe 2 nutzt addrs
 my_seat}                                 # nur in der Datei des Gastes: eigener Platz (aus dem eigenen Token)
```

- **`gid`**: Kennung der Partie, 8 Byte zufällig (hex), entsteht in `HostTable.start()` und bleibt über alle Übergaben gleich.
- **`gen`**: Generation des Gastgebers, beginnt bei 1. **Regel: `gen` steigt genau dann um 1, wenn `host_seat` wechselt** (Übergabe, Übernahme durch einen Gast). Setzt ein Gerät seinen eigenen Zweig fort (Gastgeber nach Absturz, abgetretener Gastgeber bekommt per `handover own` zurück), bleiben `gen` und `epoch`. Damit verliert ein alter Gastgeber, der mit seiner eigenen Datei weitermacht, immer gegen jede spätere Übernahme.
- **`epoch`**: 4 Byte zufällig (hex), neu bei jedem `gen`-Wechsel. Unterscheidet zwei Zweige mit gleicher `gen` (zwei Gäste übernehmen gleichzeitig).
- **`parent`**: `[gen, epoch, seq]` des Schnappschusses, aus dem dieser Zweig entstand (bei `gen` 1: `[0, "", 0]`).
- **`seq`**: Zähler der Schnappschüsse, wird bei jedem `_changed` um 1 erhöht und bei einem `gen`-Wechsel **nicht** zurückgesetzt.
- **`saved_unix`**: `Time.get_unix_time_from_system()`. Daran hängen die Ablaufzeiten (4.6).
- **`max_c`**: höchste `c`, die der Gastgeber je gesehen hat (für den 4012-Rundumschlag, 3.2).

### 1.2 Was nicht hinein muss

- `rev`: Clients vergleichen ihn nicht (`client_table.gd:187`).
- `_seq` und `seq_ack`: Lite verwirft nur seine offene Aktion.
- Sichten, Ereignisse und `_plan`: Der Bot-Plan wird neu berechnet (`_plan_dirty`), damit auch die Erwischt-Frist (`catch_grace`).
- Bot-RNG, `think_factor`, `bot_level`: Das sind Einstellungen des Geräts.
- Session-ids, `away` und `gone_since`: Sie werden nach der Rückkehr neu gelernt.
- `_forced_rolls` (Testhaken), `_valid`, `limits`, Log, APK.
- **`_seat_ops`** (aufgeschobene Platzaufträge): Sie hängen an Session-ids und gehen bei einer Übergabe verloren. Der neue Gastgeber kann sie neu geben; das ist selten und wird dokumentiert. Die **Warteliste selbst** kommt dagegen mit (`waiting`, `join_open`).

### 1.3 Erzeugen

- `GameTable._snapshot() -> Dictionary` wird aus `_save()` herausgelöst. `_save()` schreibt dann `_snapshot()`. `HostTable` ergänzt über `_save_extra()` die Felder `gid, gen, epoch, parent, seq, substitute, gone_names, waiting, join_open, heirs, wlan_humans, online, wlan`.
- **Token des Gastgebers:** `HostTable.start()` erzeugt für den Gastgeber-Platz ein Token wie `_hello` (`net_session.gd:576`) und legt es in `seats[host_seat].token` ab. Der Spieler des Gastgebers in der Sitzung bleibt `local` mit `token:""`. Es gibt **kein** Feld `host_token`; wer es braucht, liest `seats[host_seat].token`. Jedes Token bleibt dauerhaft an seinem Platz, über alle Übergaben hinweg.
- **`online`** kommt aus `session.online_room()`, das neu ist: `{relay: relay.relay_url, room, token, conns: [conn − RELAY_CONN_BASE aller Online-Spieler], max_c, created_unix}`. `created_unix` setzt `NetRelayHost` beim ersten `room`-Rahmen mit Token. Der Vermittler hält einen Raum höchstens 24 h (`core.js:24`).

### 1.4 Wiederherstellen

`HostTable.resume(data, my_seat := -1, port_first, port_last)` erweitert die vorhandene Funktion (`host_table.gd:156`):

- `my_seat < 0` oder `my_seat == data.host_seat`: Fortsetzen des eigenen Zweigs. `host_seat`, `gen`, `epoch` bleiben.
- `my_seat ≠ data.host_seat` (Übernahme): `host_seat = my_seat`, alle `seats[*].host` umstellen, `game.set_host(my_seat)` (`mau_game.gd:204`). **Alle Tokens bleiben unverändert**; der alte Gastgeber-Platz wird ein entfernter Gast mit `net:"app"` und behält sein Token aus `seats`, er gilt wie jeder andere als getrennt. Danach `parent = [gen, epoch, seq]`, `gen += 1`, neue `epoch`.
- Gäste werden über das neue öffentliche `session.restore_player(name, net, token, waiting := false) -> id` eingetragen. Es ersetzt den privaten Zugriff in `_restore_guest` (`host_table.gd:616`). Die Warteliste kommt mit `waiting:true` zurück, `join_open` wie gespeichert.
- `_substitute` wird aus `substitute` wiederhergestellt; heute leert `_restore_seats` es.
- Online: `session.open_online_existing(relay, room, token, conns, max_c)` (Abschnitt 3.2).
- Am Ende `_changed([])` **ohne Ereignisse**. Damit zählt die Statistik nichts doppelt, denn `AppStats` zählt eine Partie nur bei `round_start{round:1}`.
- **Bots und Aktionen warten in der Einschwingzeit** (`_settling`): bis alle App-Gäste aus `heirs` und alle Gäste, deren Token im letzten `bk`-Verteiler stand, ihr `hello` geschickt haben, höchstens `TAKEOVER_SETTLE_MAX_MS` = 15 s (länger als `RELAY_HOST_AWAY_MS` = 10 s, die Wartezeit der Gäste nach 4503). Erst danach laufen Bots und werden Aktionen angenommen.

### 1.5 Größe

Gemessen werden soll im Test; geschätzt bei 116 Karten und 10 Plätzen:

| Teil | Größe |
|---|---|
| `to_dict` (faces 232, Stapel, Hände, dlog ≤ 116 Einträge, config) | ≈ 8–12 KB |
| seats und Rest | ≈ 2 KB |

Versendet wird `z = Marshalls.raw_to_base64(JSON.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP))`, also ≈ 3–5 KB. Grenze im Code ist `SNAPSHOT_MAX` = 128 KB: Liegt ein Schnappschuss darüber, wird er nicht verschickt (`push_warning`), weil der Vermittler über 256 KB den Gastgeber mit 1009 schließt (`core.js:258`). Entpacken beim Gast erfolgt mit `decompress_dynamic(512 KB)`. Ein Gast schickt **nie** einen Stand hoch (Client→Host höchstens 8 KB).

## 2. Verteilung

- **Reihenfolge: erst Sicherung, dann Stand.** In `HostTable._distribute()` wird **zuerst** der fällige Schnappschuss gebaut, die eigene Datei geschrieben und `{t:"bk", gid, gen, epoch, seq, z}` verschickt, **danach** gehen die Sichten hinaus. Der Vermittler hält die Reihenfolge je Socket ein. So sieht kein Gast je einen Stand, der nicht schon in seiner Sicherung liegt; nach einer Übernahme springt keine Karte zurück, und ein Rundenende entsteht nicht doppelt.
- Zusammengefasst wird nur innerhalb eines `_changed`-Pakets (ein `bk` je `_changed`). Für Tests mit `speed = 0` und vielen Zügen je `pump()` gibt es den Schalter `backup_enabled` (ab Werk an).
- **Empfänger:** nur verbundene Spieler mit Platz am Tisch, die im `hello` das Feld `bk` mitgeschickt haben (3.5). `kind` allein reicht nicht, weil der Gast es selbst angibt (`clean_client_message`). Browser bekommen nichts. Der neue `session.send_many(ids, text)` braucht online **einen** `send`-Rahmen für alle (`core.js:265`, bis 64 Ziele).
- **Lebenszeichen:** Ist `ALIVE_MS` = 15 s lang nichts an die App-Gäste gegangen, kommt `{t:"alive", gid, gen, epoch, seq}`. Das ist nötig, weil der Vermittler das Text-„ping“ der Gäste selbst beantwortet (`worker.js:96`, AutoResponse). Ein still toter Gastgeber-Socket (Akku leer, kein FIN) fällt den Gästen sonst nie auf. 15 s statt 5 s, damit der Raum in Spielpausen ruhen kann (Kosten unten).
- **Eigene Datei:** Gastgeber und Gast schreiben dieselbe Form nach `user://netz_partie.json` (`TableSource.NET_SAVE_PATH`, neu), atomar über `.tmp` und rename. `role` ist `"host"` oder `"guest"`. `HostTable.save_path` zeigt dorthin. Übung und Weitergeben behalten `user://laufende_partie.json`, so überschreiben sich die Spielarten nicht gegenseitig. Ein Gerät spielt immer nur eine Netzpartie.
- **Gast überschreibt seine Datei nur** mit einem `bk` derselben `gid` und `gen ≥ Datei-gen`. Ein abgetretener Gastgeber behält so seinen Zweig, bis ein Gastgeber mit gleicher oder höherer `gen` sendet (4.3.5).
- **Löschen:**
  - Gastgeber bei `leave()` und `back_to_lobby()` (wie heute).
  - Gast bei eigenem „Verlassen“, bei `bye`, bei `removed`, bei `lobby` ohne `waiting` (Gastgeber hat die Partie in die Lobby zurückgeholt) und bei `start` mit anderer `gid`.
  - Bei `game_over` bleibt die Datei, wird aber nicht mehr angeboten.
- **Alte und fremde Geräte:**
  - `bk` und `alive` sind unbekannte Typen. `ClientTable` und Lite ignorieren sie (`client_table.gd:169`, `app.js:498`).
  - App-Gäste haben ohnehin genau die Version des Gastgebers (`check_hello`, `net_protocol.gd:384`).
- **Kosten im Gratistarif** (vor dem Umsetzen die aktuellen Bedingungen prüfen):
  - *Anfragen:* Eingehende WebSocket-Nachrichten zählen 20:1, ausgehende sind frei. Abend mit ≈ 2 000 Änderungen in 3 h: `bk` ≈ 2 000 Rahmen ≈ 100 Anfragen; `alive` höchstens 720 Rahmen ≈ 36 Anfragen. Zusammen **≈ 140 Anfragen zusätzlich**, gut 0,1 % von 100 000 pro Tag.
  - *Laufzeit (GB-s):* Ein Durable Object kostet Laufzeit, solange es wach ist; es ruht (Hibernation) erst einige Sekunden nach dem letzten Rahmen. Das Text-„ping“ der Gäste weckt es nicht (AutoResponse), jedes `alive` schon. Mit 15 s Abstand ruht der Raum in Spielpausen den größten Teil der Zeit; im laufenden Spiel ist er durch die Züge ohnehin wach, `bk` ändert daran nichts. Weil der Standard-Vermittler des Nutzers in jeder App voreingestellt ist, teilen sich alle Gruppen eines Tages dieses Kontingent. Beim Gerätetest die Laufzeit im Cloudflare-Dashboard ablesen (Nutzer).
  - Kein Speicherzugriff je Nachricht.
  - Datenmenge je App-Gast: ≈ 2 000 × 4,5 KB ≈ 9 MB pro Abend. Später lässt sich das mit Deltas sparen (Abschnitt 9).

## 3. Netz-Bausteine (ohne Vermittler-Änderung)

### 3.1 Raum nicht mehr versehentlich beenden

- `NetRelayHost.close(end_room := false)`: Der Standard dreht sich um, und `NOTIFICATION_PREDELETE` (`net_relay_host.gd:162`) schickt **kein** `end` mehr.
- `NetHostSession.stop(text := "", end_room := false)` und `_close_relay(end_room)`. `{k:"end"}` geht nur noch bei ausdrücklichem Ende hinaus:
  - `HostTable.leave()` → `session.stop("Der Gastgeber hat das Spiel beendet.", true)` – **seit Beta 1.6.16** übergibt `leave()` den
    Raum vorher dem RoomKeeper (Gäste bekommen „bye“, der Raum bleibt bis zu 30 min für die nächste Lobby; Gäste mit einer Sicherung
    der beendeten Partie bekommen dort „bye“ statt 4503, damit niemand übernimmt). Siehe `docs/module/raum_behalten.md`.
  - `close_online()` in der Lobby
- Folge: Schließt der Gastgeber die App ohne „Tisch verlassen“, bleibt der Raum 10 min offen. Die Gäste sehen 4503 und die Übernahme greift (4.3). Genau das ist gewünscht.
- Der offene Punkt aus 1.3.3 („Raum blieb nach Verlassen ~10 min offen“) betrifft nur das **ausdrückliche** Verlassen. Dort geht `end` weiter hinaus.

### 3.2 Bestehenden Raum übernehmen

- `NetRelayHost.open_existing(url, room, token, conns: Array, max_c, created_unix)` setzt `room` und `token`, bevor `_connect()` läuft. `_connect` nimmt dann schon heute `role=host&room&token` (`:240`).
- Die `conns` kommen vorab in `_held` (Frist −1). Beim `room`-Rahmen schickt das vorhandene `_resync_held()` allen 4012. Dieselbe Mechanik nutzt schon die Rückkehr nach „away“.
- **4012-Rundumschlag:** Beim ersten `room`-Rahmen nach einer Übernahme schickt der neue Gastgeber zusätzlich `{k:"kick", c, code:4012}` an alle `c` von 1 bis `max(max_c, höchste selbst gesehene c) + 256`, ausgenommen die schon bekannten. Grund: Lite hat keine Frist für eine unbeantwortete Anmeldung. Hat sich Lite (Seite neu geladen, „Neu verbinden“) mit neuer `c` beim still toten alten Gastgeber angemeldet, kennt der Schnappschuss diese `c` nicht, und Lite würde ohne eigenes Senden ewig einen alten Tisch zeigen. Antworten `err unknown_c` (`core.js:273`) werden still verworfen. Die Rahmen werden auf höchstens 150 je Frame verteilt, damit sie mit dem übrigen Verkehr unter `host_burst` 400 bzw. `host_rate` 200/s bleiben (`core.js:21-22`).
- Zusätzlich gilt: Eine `msg` von einem unbekannten `c` beantwortet der Gastgeber mit `{k:"kick", c, code:4012}`, statt sie zu verwerfen (`:284`).
- `NetHostSession.open_online_existing(…)` ist das Gegenstück zu `open_online` (`net_session.gd:612`).

### 3.3 Verdrängt werden heißt abtreten

- Bei Code 4000 (`CLOSE_REPLACED`, `net_relay_host.gd:231`) ruft `poll()` künftig **nicht** mehr `_fail()` auf, denn `_fail` ruft `_drop_all_guests` und damit `ws_closed` für alle, bevor jemand vom Abtreten weiß. Neu: zuerst das Signal `replaced`, dann `state = "stepped_down"`; die Gäste-Liste bleibt unberührt, es geht nichts mehr hinaus (kein `bye`, kein `end`, kein `kick`).
- `NetHostSession` reicht `replaced` an `HostTable` weiter (→ `stepped_down`), das **sofort** `_frozen = true` setzt.
- **Solange `_frozen` gilt:** kein `_save`, kein `_distribute`, kein `bk`, keine Bots; `_on_left`, `_on_away` und `set_away` sind wirkungslos, es gehen keine Meldungen „ist getrennt“ hinaus. Dasselbe gilt im eingefrorenen Zustand der geplanten Übergabe (4.1), wo das Schließen des Gast-Sockets des Ziels sonst ein `_changed` auslösen würde.
- Danach wechselt `HostTable` zum Gast (4.5).
- **Rückkehr aus dem Hintergrund:** `app_resumed` → `set_away(host, false)` wird erst ausgeführt, wenn der Vermittler wieder `open` ist (also nach der Prüfung aus 3.4). Ein 4000, das im Hintergrund ankam, wird so zuerst gelesen.

### 3.4 Vorsichtiges Neuverbinden des Gastgebers

- **Jede** Neuverbindung eines Gastgebers mit bestehendem Online-Raum geht den vorsichtigen Weg – nach jedem `_lost` und nach jeder Rückkehr aus dem Hintergrund, unabhängig von der Dauer. Die Prüfung sitzt in `NetRelayHost._connect()`, nicht nur in `_lost`. Eine Messung der Pausendauer mit `Time.get_ticks_msec()` ist auf Android unbrauchbar (CLOCK_MONOTONIC steht im Tiefschlaf); daher gibt es keine Schwelle wie `HOST_SAFE_MS` mehr.
- Ausnahme: Ein noch offener Host-Socket wird nach der Rückkehr nur mit `check_now()` („ping“, Antwort binnen 3 s) geprüft. Kommt „pong“ ohne vorheriges 4000, ist das Gerät weiter Gastgeber (der Vermittler hätte es sonst mit 4000 geschlossen).
- **Ablauf** (`state = "check"`, Signal `needs_check`):
  1. `GET /info?room=CODE`. Bei `host:false` (oder `open:false` → 4.4 abgelaufen) sofort als Gastgeber verbinden.
  2. Bei `host:true` Probe als Gast (4.5, „Probe“) mit dem eigenen Token aus `seats[host_seat]`: Kommt ein `welcome`, tritt das Gerät ab (4.5). Bleibt die frische Probe-Verbindung `PROBE_MS` = 8 s unbeantwortet oder kommt 4503, verbindet es sich als Gastgeber (der Rest ist das eigene halboffene Socket beim Vermittler).
  3. Ist `/info` nicht erreichbar (eigenes Netz weg), wird weiter gewartet und erneut versucht – nie blind als Gastgeber anmelden.
- Fristen, die über Pausen hinweg gelten müssen (`saved_unix`, Alter der Datei, Pause des Gastgebers), werden mit der **Wanduhr** gemessen (`Time.get_unix_time_from_system()`, Zeitstempel bei `NOTIFICATION_APPLICATION_PAUSED`). Für Tests ist die Uhr einspritzbar (`clock: Callable` in `HostSwitch`, `NetRelayHost`).

### 3.5 Begrüßung

- `welcome` bekommt zusätzlich `gid`, `gen` und `epoch`. Lite ignoriert sie.
- `hello` bekommt zusätzlich `bk:[gen, epoch, seq]` und `bk_token` (nur App). Eine App ohne Sicherung schickt `bk:[0, "", 0]`; **das Vorhandensein von `bk` heißt „kann Sicherungen halten“** und ist Voraussetzung für den Empfang von `bk` (2.). `clean_client_message` (`net_protocol.gd:228`) übernimmt beides; heute werden unbekannte Felder der Begrüßung abgeschnitten.
- `_hello` (`net_session.gd:548`) erkennt einen Spieler auch an `bk_token`, wenn `token` unbekannt ist. Damit findet ein App-Gast seinen Platz bei einem Gastgeber mit neuer Adresse oder neuem Raum (Stufe 2). In Stufe 1 ist es eine Rückfallebene.
- `NetClient` schickt `bk_token` nur, wenn eine Sicherung mit passendem `gid` vorliegt. Den `gid` kennt der Gast aus der Datei, und er wird nach `welcome` verglichen.

### 3.6 Umsetzung der Netz-Bausteine (Beta 1.6.1) – Abweichungen und Ergänzungen

- **Rundumschlag-Budget:** zusätzlich zu höchstens 150 je Frame ein Zeitbudget von 100 Rahmen auf einmal, danach 100/s (`SWEEP_BUDGET`, `SWEEP_REFILL_PER_S`); jeder `send`-Rahmen des Spiels zählt mit (Vorrang vor dem Rundumschlag). Grund: Der Nachbau (`NetRelayDouble`) begrenzt den Gastgeber-Socket schon im `NetServer` auf einen Eimer von 200, und die Rückkehr der Gäste braucht Platz. Mit 150 auf einmal verwarf der Nachbau im Test einzelne Stände (ein Browser-Gast blieb auf einem alten Stand, die Partie wartete auf ihn) – siehe 4.8. 256 Rahmen dauern so etwa 2 s.
- **Hängendes Socket bleibt liegen:** Erkennt `NetRelayHost` Stille (offenes Socket, Zustand `open`), schließt es das alte Socket nicht selbst, sondern hält es ungepollt bis zur neuen Anmeldung (`_stale_ws`). Sonst bemerkt der Vermittler das Schließen, während `/info` läuft, und schickt allen Gästen 4503 (sie warten dann 10 s). Folge: `/info` meldet in diesem Fall `host:true` (das eigene Socket); mit Probe durch die Spielsteuerung dauert die Rückkehr dann `PROBE_MS`. Tests mit hängendem Gastgeber (`test_net_away` D, `test_net_hang` A) brauchen dann eine kurze Probe-Frist.
- **Rückfall ohne Empfänger:** Hört niemand auf `needs_check` (bzw. `NetHostSession.online_needs_check`), meldet sich der Gastgeber sofort an; hört niemand auf `NetHostSession.replaced`, gibt die Sitzung online auf wie bis 1.6.0 (`failed`, Online-Gäste getrennt). So bleibt die App bis zur Anbindung in `HostTable` unverändert.
- **Zustände:** Während `/info` bleibt der Zustand `away` (die Oberfläche zeigt „verbinde neu“); `check` gibt es nur bei `host:true` mit Empfänger. Neu sind `check` und `stepped_down`; die Oberfläche (`invite_panel`, `table_screen`) muss `check` wie `away` behandeln.
- `finish(text, end_room := true)` beendet den Raum weiter; `HostTable._close_session()` ruft `stop(text, true)` (Verlassen = ausdrückliches Ende).
- `hello.bk` merkt sich die Sitzung nur bei `kind:"app"` (`players[id].bk`, `backup_ids()`, `backup_mark(id)`).
- Packen/Entpacken der Sicherung (`pack_snapshot`/`unpack_snapshot`), Kopf-Prüfung beim Gast (`clean_backup_message`) und Markenvergleich (`compare_marks`) liegen in `NetProtocol`, damit `MatchSnapshot` und `HostSwitch` sie teilen.

## 4. Abläufe

### 4.1 Geplante Übergabe

1. Der Gastgeber öffnet ☰ → „Gastgeber übergeben …“ und wählt einen Gast (Dialog `host_pick_dialog.gd`). Wählbar sind App-Gäste, die verbunden, nicht `away` und im `bk`-Verteiler sind.
   - Stufe 1 zusätzlich: Die Partie hat einen Online-Raum, und **alle** entfernten Menschen sind Online-Gäste. Sonst ist der Eintrag ausgegraut mit Begründung.
2. `HostTable.handover_to(seat)` schickt nur an das Ziel `{t:"handover", gid, gen, epoch, seq, z, within_ms: 8000}`, an alle die Meldung „Gastgeber wechselt zu %s …“ und setzt `_frozen = true` (Wirkung wie 3.3).
   - Aktionen der Gäste werden mit `err` „Einen Moment – der Gastgeber wechselt.“ abgelehnt.
   - Der eigene Tisch zeigt dasselbe.
3. Das Ziel (`ClientTable` → `HostSwitch`) prüft `gid` und schreibt `z` als eigene Datei. Dann schließt es seinen Gast-Socket ohne `bye`, legt `HostTable.resume(data, my_seat)` an (→ `gen+1`, neue `epoch`) und `open_online_existing`. Der Tisch wird ersetzt (`nav.replace(TableScreen.create(ht, …))`).
   - **Frist:** Kommt binnen `within_ms` (ab Empfang beim Ziel) kein `room`-Rahmen, bricht das Ziel ab, schließt den Host-Socket und meldet sich wieder als Gast an (Datei bleibt, `gen` des Ziels gilt nicht, weil es nie Gastgeber war).
   - Der Vermittler schließt den alten Gastgeber mit 4000.
   - Die alten `c` bekommen 4012 (plus Rundumschlag 3.2), alle Gäste melden sich mit ihrem Token neu an. Das gilt für App und Lite, denn der Token-Schlüssel ist der Raumcode (`net_client.gd:475`, `app.js:69`).
4. Der alte Gastgeber bekommt 4000 und tritt ab (4.5). Er meldet sich mit dem Token seines Platzes als Gast an.
5. **Fehlschlag:** Kommt binnen `HANDOVER_TIMEOUT_MS` = 25 s (deutlich länger als `within_ms`) kein 4000, prüft der Gastgeber mit `check_now()` („ping“), ob sein Host-Socket noch lebt. Kommt „pong“ ohne 4000, hebt er `_frozen` auf und meldet „Übergabe an %s hat nicht geklappt. Du bleibst Gastgeber.“ `gen` bleibt unverändert. Kommt kein „pong“, geht er den vorsichtigen Weg (3.4).
   - Hat das Ziel trotz allem noch übernommen, gilt die Abstammungsregel (4.3.5): Sein `gen` ist höher, der alte Gastgeber tritt beim 4000 ab.

**Bots** laufen ab der Übernahme auf dem neuen Gerät, mit dessen Tempo-Einstellung. **Tokens** bleiben alle gleich.

### 4.2 Ersatz-Rangfolge

- **`heirs`** berechnet der Gastgeber bei jedem Schnappschuss. Es ist die Liste der Tokens der App-Gäste im `bk`-Verteiler, die verbunden und nicht `away` sind, in Sitzordnung ab dem Platz nach dem Gastgeber im Uhrzeigersinn. Die Spielrichtung zählt nicht, so ist es „der Nächste am Tisch“.
- **Stufe 1:** Sitzt ein entfernter Mensch mit WLAN-Verbindung am Tisch (`wlan_humans`), ist `heirs = []` – keine automatische Übernahme. Sonst würde ein Online-Gast übernehmen, während der Gastgeber nur länger in einer anderen App ist, und die WLAN-Gäste neben dem Rückkehrer säßen fest. Der Knopf von Hand bleibt, mit Warnzeile „WLAN-Mitspieler kommen dann nicht mit.“
- Die Liste hängt am Token, nicht an der Platznummer. Plätze verschieben sich durch Dazuholen.
- **Aktuell** ist ein Gast, dessen `(gen, epoch, seq)` dem letzten `alive` oder `bk` entspricht. Wer nicht aktuell ist, übernimmt nie automatisch.

### 4.3 Unerwarteter Ausfall: Erkennung und Übernahme (Gast-Wächter `HostSwitch`)

Der Wächter ist nur scharf in den Phasen aus `MauGame.PLAY_PHASES` und bei `round_over`, mit Online-Raum und mit Sicherung derselben `gid`. In Lobby und `game_over` ist er aus.

| Lage | Erkannt durch | Frist bis „Gastgeber fehlt“ |
|---|---|---|
| Gastgeber in einer anderen App (`players[host].away` gesetzt) – **auch wenn danach 4503 kommt** | `away`, später ggf. 4503 | `T_AWAY` = 180 s **ab dem `away`** |
| Gastgeber sauber weg ohne vorheriges `away` (App getötet, Netz weg mit FIN) | 4503 vom Vermittler | `T_SILENT` = 40 s ab 4503 |
| Gastgeber still tot (halboffener Socket) | kein `bk`/`alive`/`state` | `T_SILENT` = 40 s ab der letzten Nachricht |

- **Zuordnung `away` + 4503:** War `away` für den Gastgeber vor dem 4503 gesetzt oder kommt es bis zu `AWAY_LINK_MS` = 2 s danach, gilt `T_AWAY` ab dem `away`. Android trennt Sockets von Hintergrund-Apps oft nach Sekunden (Gerätetest 1.3.3); ein kurzer Wechsel zu Threema darf keine Übernahme auslösen.
- Alle Fristen laufen über die Wanduhr (3.4), damit sie auch auf einem Gast stimmen, der selbst kurz im Hintergrund war.

Ablauf auf jedem App-Gast mit aktueller Sicherung:

1. **Frist überschritten:** Der Gast meldet sich neu als Gast an (`NetClient.reconnect_now()`, neue `c`). Kommt ein `welcome`, ist alles gut, und es geht wieder bei Null los. Das gilt auch, wenn inzwischen jemand anderes Gastgeber ist.
2. **Wartezeit nach Rang:** Wird die Verbindung angenommen, aber nicht beantwortet, oder kommt 4503, beginnt die Wartezeit `rank × T_STEP` (12 s; Rang 0 = sofort, Rang −1 = nicht in `heirs`, kein Automatismus). Sie läuft, solange kein `welcome` kommt.
   - Ist der Vermittler selbst nicht erreichbar (eigenes Netz weg), wird **nie** übernommen.
3. **Unmittelbar vor der Übernahme** (die Probe aus Schritt 2 ist mehrdeutig – ein frischer Ersatz-Gastgeber kennt die ältere `c` des Prüfenden nicht und antwortet ihr nicht):
   - `GET /info?room=CODE`. Bei `host:false` sofort übernehmen.
   - Bei `host:true` eine **frische** Probe-Verbindung (neue `c`) öffnen. Kommt `welcome`, Abbruch. Bleibt sie `PROBE_MS` = 8 s unbeantwortet, übernehmen.
   - Zusammen mit dem 4012-Rundumschlag (3.2) ist der Fall „Ersatz kennt meine `c` nicht“ damit erledigt.
4. **Übernahme:** Wie 4.1 Schritt 3, mit dem gespeicherten Schnappschuss (`gen+1`, neue `epoch`). Danach geht an alle die Meldung „%s führt das Spiel weiter (Gastgeber war weg).“
5. **Abstammung: neuerer Zweig gewinnt** (gilt dauerhaft für jeden Gastgeber, nicht nur nach einer Übernahme). Der Gastgeber vergleicht das `hello.bk = [g', e', s']` jedes App-Gastes mit seinem eigenen Stand `[gen, epoch, seq]` und `parent = [pg, pe, ps]`:
   - **`g' > gen`:** Der Gast hält einen jüngeren Zweig (z. B. der alte Gastgeber hat mit seiner Datei weitergemacht, während der Gast schon übernommen hatte). Der Gastgeber übergibt sofort mit `{t:"handover", own:true, gid, gen:g', epoch:e', seq:s', within_ms:8000}` **ohne `z`**: Das Ziel nimmt seine eigene Sicherung.
   - **`[g', e'] == [pg, pe]` und `s' > ps`**, solange `_settling` gilt (noch keine Aktion angenommen): Der Gast hat einen neueren Stand derselben Vorgeneration. Ebenfalls `handover own:true`.
   - **Gleiche `gen`, andere `epoch`:** nichts tun. Zwei Gäste haben gleichzeitig übernommen; der Vermittler hat schon einen per 4000 entschieden, ein Hin und Her wäre schlimmer als die verlorenen Sekunden.
   - Sonst nichts.
   - **Ziel von `own:true`:** prüft, ob seine Datei noch genau `[g', e', s']` mit derselben `gid` ist. Wenn ja: Übernahme wie Schritt 4 (`resume(data, my_seat)`; `gen` steigt nur, wenn `host_seat` wechselt – Ausnahme Einschwing-Regel mit `host_gen`, 4.7). Wenn nein: `{t:"handover_no"}`, der Gastgeber taut auf. Je Gast und `gen` versucht der Gastgeber das höchstens einmal.
   - Weil `gen` nur bei einem Platzwechsel steigt (1.1), verliert ein alter Gastgeber, der seine eigene Datei fortsetzt, immer gegen eine spätere Übernahme.
6. **Schutz gegen zwei Gastgeber:**
   - Ein Späterer sieht beim Neuverbinden oder in der frischen Probe das `welcome` des Früheren und bricht ab.
   - Übernehmen zwei gleichzeitig, schließt der Vermittler den ersten mit 4000. Er tritt ab (4.5), behält seine Datei und kommt mit seinem Gast-Token zurück. Verloren gehen höchstens die Sekunden dazwischen.
   - Ein zurückkehrender alter Gastgeber geht immer den vorsichtigen Weg (3.4).

**Der Platz des ausgefallenen Gastgebers** gilt als getrennter Gast. Ist er am Zug, sieht der neue Gastgeber sofort „Computer übernimmt“ und „Aus dem Spiel nehmen“ (wie seit 1.4.2). Kommt er zurück, spielt er selbst weiter.

### 4.4 „Spiel als Gastgeber fortsetzen“ (von Hand)

- **Am Tisch (Gast):** Im Verbindungsstreifen (`table_screen.gd:533`) erscheint ab „Gastgeber fehlt“ der Knopf „Spiel als Gastgeber fortsetzen“. Er ist für jeden App-Gast mit Sicherung sichtbar, auch ohne Rang, auch wenn die Sicherung nicht aktuell ist und auch bei `wlan_humans` (jeweils mit Warnzeile). Nach einer Rückfrage folgt die Übernahme wie 4.3 Schritt 3–4 (mit `/info` und frischer Probe).
- **Hauptmenü:** Der Eintrag „Partie fortsetzen“ erscheint, wenn `user://netz_partie.json` existiert, die Phase nicht `game_over` ist und der Stand jünger als `RESUME_MAX_H` = 12 h ist (online zusätzlich: weniger als 24 h seit `created_unix`).
  - Ablauf immer zuerst als **Gast** mit dem eigenen Platz-Token (`role:"host"` → `seats[host_seat].token`, `role:"guest"` → `seats[my_seat].token`). Antwortet ein Gastgeber, spielt man als Gast weiter; das `hello.bk` sorgt dafür, dass ein jüngerer Zweig auf diesem Gerät zurückgeholt wird (4.3.5).
  - Antwortet niemand (`/info` `host:false` oder frische Probe 8 s still):
    - `role:"host"` und Datei jünger als `RESUME_QUIET_MIN` = 5 min: Fortsetzen ohne Rückfrage (es ist die eigene Partie, eigener Zweig, `gen` bleibt).
    - `role:"host"` und älter, oder `role:"guest"`: Rückfrage wie am Tisch.
  - **WLAN in Stufe 1:** Nur `role:"host"` setzt fort, als Gastgeber auf dem gespeicherten Port (`wlan.port`). Bei gleicher IP finden App-Gäste (Schlüssel `ip:port`) und Lite (gleicher Ursprung, Neuversuch ohne Ende) von selbst zurück. Ein Spiel-WLAN ist nach einem Absturz weg; siehe Stufe 2.
  - Ist der Raum abgelaufen (`/info` `open:false`, 4404 bzw. 4403 beim Übernehmen), erscheint: „Der Online-Raum ist abgelaufen. Die Partie lässt sich nicht mehr fortsetzen.“ Der Knopf „Partie verwerfen“ löscht die Datei. Ein neuer Raum für eine alte Partie kommt mit Stufe 2.

### 4.5 Abtreten (alter Gastgeber wird Gast)

- `HostTable.stepped_down` kommt aus 4000 (3.3) oder aus einer Probe mit fremdem `welcome` (3.4). `_frozen` ist da schon gesetzt.
- `HostSwitch.become_guest(data)`:
  - `HostTable` ohne `bye` und ohne `end` abbauen (`handover_shutdown()`: `session.stop("", false)`).
  - `ClientTable.join(room_link, 0, name, seats[host_seat].token)` mit `hello.bk` der eigenen Datei.
  - `nav.replace(TableScreen.create(ct))`.
  - Meldung „Du spielst jetzt als Gast weiter. Gastgeber ist %s.“
- Die eigene Datei bekommt `role:"guest"`, bleibt inhaltlich aber erhalten, bis ein `bk` mit gleicher oder höherer `gen` kommt (2.). So kann der Gastgeber über `hello.bk` einen jüngeren Zweig zurückholen.

### 4.6 Ablaufzeiten

| Was | Grenze | Grund |
|---|---|---|
| Automatische Übernahme | spätestens 10 min nach 4503 | `grace_s` 600, danach ist der Raum weg (`core.js:23`) |
| Online insgesamt | 24 h ab `created_unix` | `life_s` (`core.js:24`) |
| „Partie fortsetzen“ | 12 h | danach wohl keiner mehr da |
| Fortsetzen ohne Rückfrage (eigene Gastgeber-Datei) | 5 min | danach könnte längst ein anderer führen |

### 4.7 Umsetzung Schnappschuss und HostTable (Beta 1.6.1) – Abweichungen und Ergänzungen

- **Feld `bk_to`** im Schnappschuss (zusätzlich zu `heirs`): Tokens der Gäste, die genau diesen Stand als `bk` bekamen. Die Einschwingzeit wartet auf `heirs ∪ bk_to` ohne den eigenen Platz; ohne `bk_to` ließe sich „alle aus dem letzten Verteiler“ nicht wiederherstellen.
- **Feld `seats[*].link`** (`"online"`/`"wlan"`, beim Verbinden gesetzt): Grundlage für `wlan_humans`, auch für Gäste, die gerade getrennt sind. Der alte Gastgeber-Platz bekommt bei einer Übernahme `net:"app"`, `link:"online"`.
- **`resume(data, my_seat := -1, port_first, port_last)`**: `my_seat` steht an zweiter Stelle (Aufrufe mit Ports angepasst). Liegt `wlan.port` im erlaubten Bereich, wird er zuerst versucht (eigener Zweig). Ältere Gastgeber-Stände (format 1) werden noch angenommen und bekommen eine neue `gid`.
- **Hook `GameTable._persist()`** statt `_save()` in `_changed`: HostTable baut dort einmal je Änderung den Schnappschuss (`seq + 1`), schreibt die Datei und schickt `bk` – vor `_distribute`.
- **Einschwingzeit:** Aktionen werden mit „Einen Moment – gleich geht es weiter.“ abgelehnt (eigener Text, weil kein Gastgeberwechsel läuft, wenn der Gastgeber selbst fortsetzt). `announce_after_settle(lt)` schickt eine Meldung (z. B. „%s ist jetzt Gastgeber.“) erst danach, wenn die Gäste zurück sind.
- **`stepped_down` kommt nach `session.poll()`** (aus `_poll_extra`), nie mitten aus dem Vermittler-Signal; so darf der Empfänger gleich `handover_shutdown()` aufrufen. Ohne Empfänger (Oberfläche noch nicht angebunden) gibt der Tisch online auf wie bis 1.6.0 und spielt mit WLAN-Gästen und Bots weiter.
- **Vorsichtiges Neuverbinden:** `HostTable` reicht `online_needs_check` als `online_check(info)` weiter; die Probe als Gast macht die Oberfläche (`HostSwitch`, `host_token()`) und meldet `probe_done(other, name)`. Ohne Empfänger meldet sich der Gastgeber sofort an.
- **Fehlschlag der Übergabe:** nach `handover_timeout_ms` `relay.check_now()`; aufgetaut wird, sobald der Vermittler wieder `open` ist und die Prüfung beantwortet wurde (`NetRelayHost.check_pending()`, neu), oder wenn er `failed`/`off` ist. Nach dem Auftauen übernimmt der Tisch den Verbindungsstand aus der Sitzung (eingefroren wirkten `_on_left`/`_on_rejoined` nicht).
- **Abstammungsregel** nur, wenn eine Übergabe an diesen Gast überhaupt möglich ist (`handover_block` leer: online, keine WLAN-Mitspieler, Gast mit `bk` verbunden). `hello.bk` trägt keine `gid`; eine fremde Partie lehnt das Ziel mit `handover_no` ab.
- **Abstammung vor dem ersten `bk`:** `_on_rejoined` prüft die Abstammung, bevor `_changed` dem Zurückgekehrten ein `bk` schickt (sonst überschriebe dessen höhere `gen` die Sicherung des Rückkehrers, und `own:true` fände seine Marke nie). Eingefroren geht dann kein Stand hinaus.
- **Einschwing-Regel mit `host_gen`** (Abweichung von 1.1): `handover own:true` trägt die `gen` des Absenders. Ist die `gen` des Ziels nicht höher (gleiche Vorgeneration, höheres `seq`), führt es mit `host_gen + 1`, `parent` = eigene Marke und neuer `epoch` weiter, obwohl `host_seat` gleich bleibt. Sonst holte der verdrängte Gastgeber (höhere `gen`) das Spiel per `own:true` gleich zurück – Hin und Her. Im Fall `g' > gen` bleibt die `gen` des Ziels wie bisher.
- **Datei erst nach der Übernahme:** Der neue Gastgeber-Tisch schreibt `netz_partie.json` erst, wenn der Raum übernommen ist (`room`-Rahmen bzw. sofort im WLAN); bis dahin bleibt die Gast-Datei. Ein Absturz im Übernahme-Fenster hinterlässt so keine Gastgeber-Datei eines Geräts, das nie Gastgeber war.
- **`wlan.addrs`** wird einmal bei `start()`/`resume()` ermittelt, nicht je Änderung (`NetAddresses.own_addresses()` fragt auf Android per JNI alle Netze ab). Stufe 2 muss die Liste nach einem Neu-Binden auffrischen.
- **„Wieder da“ nach der Rückkehr** wartet höchstens `RELAY_INFO_TIMEOUT_MS + RESUME_PROBE_MS` (9 s) auf den Vermittler (`NetHostSession.unaway_max_ms`), außer während `check`/`stepped_down`; ohne Internet sähen die WLAN-Gäste den Gastgeber sonst für immer „in einer anderen App“. Schließt der Vermittler (`_close_relay`), kommt „wieder da“ sofort.

### 4.8 Umsetzung Gast-Seite und HostSwitch (Beta 1.6.1) – Abweichungen und Ergänzungen

- **`HostSwitch` hängt als Kind an der Quelle** (`HostSwitch.ensure(source)`) und zieht bei jedem Wechsel mit (`swapped(new_source, note)`); die Oberfläche ersetzt nur den Tisch. `TableScreen` ist dafür minimal verdrahtet (`nav.replace(TableScreen.create(new_source))` plus Hinweis als Toast). Verbindungsstreifen, Knopf und Rückfrage fehlen noch: `missing()`, `countdown_ms()`, `can_continue()`, `continue_warnings()`, `continue_as_host()`; Hauptmenü: `HostSwitch.saved_offer()`, `resume_saved(data)`, Signal `confirm_needed`, `confirm_resume(yes)`, `cancel()` („Weiter warten“), Zustand `expired` mit `last_error`.
- **Frische Probe des Gastes = Neuanmeldung der eigenen Verbindung** (`NetClient.reconnect_now()`, neue `c`), keine zweite Verbindung: Mit demselben Token würde ein antwortender Gastgeber die Hauptverbindung mit 4000 ersetzen. Die Probe des zurückkehrenden Gastgebers ist dagegen ein eigener `NetClient` (`connect_probe`, Ergebnis answered/away/gone/silent/unreachable).
- **4503 zählt ab dem ersten der Abwesenheit** (`host_away_wall`; `away_code_wall` = letztes): Sonst schöbe jeder Neuversuch nach 10 s die Frist `T_SILENT` immer weiter. „Vermittler nicht erreichbar“ erkennt `NetClient.reached` (Socket offen oder Schließcode seit dem letzten Verbinden).
- **Meldung nach der Übernahme** („%s ist jetzt Gastgeber.“ bzw. „… führt das Spiel weiter …“) schickt `HostSwitch` erst, wenn die übrigen Menschen wieder verbunden sind (höchstens `settle_max_ms`): Ist das Ziel der einzige Erbe, gibt es keine Einschwingzeit, und `announce_after_settle` ginge sofort ins Leere.
- **`bk` einer anderen Partie** wird übernommen, wenn sie die des aktuellen Gastgebers ist (die Datei einer früheren Partie wird ersetzt); „gen ≥ Datei-gen“ gilt innerhalb derselben `gid`. `lobby` ohne `waiting` löscht nur die Sicherung genau der Partie, in der der Tisch saß (ein Beitritt in eine fremde Lobby lässt eine fortsetzbare eigene Datei stehen); `start` löscht, wenn die gid nicht die des welcome ist.
- **Datei nur mit `persist_backup`** und – beim gemeinsamen Standardpfad – nur, wenn auch die Token gespeichert werden (`persist_tokens`). Grund: Tests mit mehreren Gästen in einem Prozess teilten sich sonst eine Datei und über `bk_token` einen Platz.
- **`handover` wird in `HostSwitch.pump()` ausgeführt,** nicht im Signal (der Gast-Tisch baut dabei seine Verbindung ab). Ohne Empfänger antwortet `ClientTable` nicht selbst mit `handover_no` (nur ohne Sicherungen); der Gastgeber taut nach seiner Frist auf.
- **Abbruch einer Übernahme** (Frist, Raum weg, oder gleichzeitig übernommen und mit 4000 verloren): Gastgeber-Tisch ohne bye/end abbauen, Datei wie vorher (`ClientTable.resume_guest()`), wieder als Gast anmelden.
- **Uhr zurückgestellt:** Der Wächter zählt dann ab jetzt (nie eine Frist in der Zukunft festhalten).
- **Offen (Risiko):** Verwirft der Vermittler einen Rahmen des Gastgebers wegen der Rate, bleibt der betroffene Gast ohne Fehlermeldung auf einem alten Stand, bis sich wieder etwas ändert; wartet die Partie gerade auf ihn, steht sie. Der echte Vermittler erlaubt 400 auf einmal, der Nachbau 200.

### 4.9 Umsetzung Oberfläche (Beta 1.6.1) – Abweichungen und Ergänzungen

- **☰ „Gastgeber übergeben …“** steht beim Netz-Gastgeber nach „Mitspieler entfernen“ und ist ausgegraut, wenn niemand wählbar ist; darunter steht klein der aussagekräftigste Grund der Mitspieler („Geht in dieser Version nur …“ vor „%s ist gerade nicht verbunden.“ vor „Nur Mitspieler mit der App …“), vor dem Austeilen und nach dem Partie-Ende „Das geht gerade nicht.“ Mit sechs Einträgen passt das Menü nicht immer auf 720 px: Es wird dann flacher, rückt nach oben und bei großer Schrift zweispaltig (`IngameMenu._fit`).
- **Auswahldialog** (`HostPickDialog`): alle Menschen außer dem Gastgeber, ausgegraute mit Grund (`handover_block`); die Liste wird zweimal je Sekunde nachgeführt, eine Wahl verfällt, sobald der Gewählte nicht mehr geht.
- **Verbindungsstreifen:** Gastgeber eingefroren → „Gastgeber wechselt zu %s …“; Abtreten (`joining`) und Übernahme (`taking`) → „Einen Moment – der Gastgeber wechselt.“; Einschwingzeit → „Einen Moment – gleich geht es weiter.“; `check` wie `away`. Raum abgelaufen (`gone`) → Meldung mit „Zum Menü“. Die Warnzeilen der Rückfrage stehen fett in Signalrot (`ConfirmBox.add_note`).
- **Dazuholen/Einladen** (`invite_panel`): `check` und `stepped_down` zeigen den offenen Raum mit „Online-Verbindung unterbrochen – verbinde neu …“; der Haken bleibt bei `check`.
- **Hauptmenü:** Nach dem Wechsel (`swapped`) löst das Hauptmenü die Signale des HostSwitch; er gehört dann dem Tisch.
- **Hauptmenü:** In der Zeile „%s · Runde %d · vor %d min“ stehen für `%s` bis zu zwei Namen der anderen am Tisch (der Gastgebername wäre bei der eigenen Datei der eigene). „Partie verwerfen“ fragt nach („Partie verwerfen?“). Während des Ablaufs: „Verbinde mit den anderen …“ mit „Abbrechen“. Rückfrage: Gast-Datei „Spiel als Gastgeber fortsetzen?“, eigene ältere Datei „Deine Partie von vor %d min fortsetzen?“, Knöpfe „Fortsetzen · Abbrechen“ (im Hauptmenü wartet nichts weiter). Raum abgelaufen: Meldung mit „Partie verwerfen · Zurück“.
- **So geht's:** Die beiden Sätze stehen in der Hilfe der Gastgeber-Lobby (Zeile „Ausfall“).

## 5. Gemischte Versionen und Browser-Gäste

- **App-Gäste** haben innerhalb einer Partie genau die Version des Gastgebers (`check_hello`). Gemischte App-Versionen gibt es also nicht.
- **Ältere Gastgeber** (≤ 1.6.0) schicken kein `bk`. Bei ihnen bleibt alles wie bisher, ohne Übernahme und ohne Knopf.
- **Lite online:** Lite folgt einer Übernahme ohne Änderung. Es bekommt 4503 oder 4012 und meldet sich mit `mmf.token:CODE` neu an; der neue Gastgeber kennt das Token aus `seats`. `welcome.host_name` zeigt den neuen Namen. Hängt Lite mit einer `c`, die der Schnappschuss nicht kennt, holt es der 4012-Rundumschlag (3.2).
  - Die Version des Raums bleibt die des ersten Gastgebers (`core.js:192`, `loader.js:50`). Weil der Ersatz dieselbe Version hat, passt das.
- **Lite und `bye`:** Lite löscht sein Token bei `bye` (`app.js:486`). Deshalb schicken Übergabe und Abtreten **nie** `bye`.
- **Wartende** (Warteliste) kommen nach einer Übergabe wieder auf die Warteliste und werden nicht mit `reject running` abgewiesen (1.4). Sonst löschte Lite sein Token (`app.js:436`) und die App zeigte fälschlich „Der Gastgeber hat dich aus dem Spiel genommen.“ (`net_client.gd:398`).
- **Lite im WLAN** folgt erst mit Stufe 2.
- **Statistik:** Übernahme und Abtreten erzeugen keine Ereignisse (`_changed([])`). Es entsteht kein `round_start` und damit keine doppelte Partie. Weil `bk` vor dem Stand hinausgeht (2.), entsteht auch kein Rundenende doppelt. Die „größte Hand“ ist ein Maximum, bleibt also ohnehin richtig.
- **Zeitgeber:**
  - Die Erwischt-Frist und die Bot-Bedenkzeit entstehen auf dem neuen Gerät neu (`_plan_dirty`). Ein offenes Mau-Fenster (`mau_open`) steht im Spielstand, ein Mensch bekommt also wieder die volle Frist.
  - Auf das Warten auf getrennte Spieler (`_wait_since`) beginnt eine neue Frist.
  - Die Denkblase (5 s) ist nur Oberfläche.
- **Datenschutz und Schummeln** (dokumentierter Kompromiss, ehrlich benannt): Jede App-Sicherung enthält alle Hände, den Ziehstapel, `rng_state` (macht künftige Karten vorhersagbar), die geheime Glücksspiel-Quote `q`, **alle Spieler-Tokens und das Raum-Token**. Die App zeigt nichts davon an. Wer aber gezielt schummeln will, kommt heran: Die Datei liegt auf dem Gerät, und ein Browser kann sich mit `kind:'app'` und `bk` in den Entwicklerwerkzeugen als App ausgeben. Dass `bk` nur an Gäste mit `hello.bk` geht, verhindert nur das versehentliche Mitsenden, ist aber kein Schutz. Wer Mitspielern nicht traut, sollte ohne Sicherung spielen (Einstellung beim Gastgeber, siehe Nutzerfrage in 9).

## 6. Oberflächentexte (Deutsch; Englisch über `en_screens.po`/`en_table.po`)

| Ort | Text |
|---|---|
| ☰ (Gastgeber) | Gastgeber übergeben … |
| Dialog Titel | Gastgeber übergeben |
| Dialog Text | Wer führt das Spiel weiter? Es läuft dann über sein Handy, du spielst als Gast weiter. |
| Dialog Knöpfe | Übergeben · Abbrechen |
| ausgegraut | Nur Mitspieler mit der App können Gastgeber werden. / %s ist gerade nicht verbunden. / Geht in dieser Version nur, wenn alle online mitspielen. |
| an alle | Gastgeber wechselt zu %s … |
| Aktion abgelehnt | Einen Moment – der Gastgeber wechselt. |
| neuer Gastgeber | Du bist jetzt Gastgeber. Bitte lass die App offen. |
| an alle | %s ist jetzt Gastgeber. |
| Fehlschlag | Übergabe an %s hat nicht geklappt. Du bleibst Gastgeber. |
| alter Gastgeber | Du spielst jetzt als Gast weiter. Gastgeber ist %s. |
| Streifen (Gast) | Gastgeber antwortet nicht – warte … |
| Streifen mit Rang | Gastgeber antwortet nicht. Du übernimmst in %d s. |
| Knopf | Spiel als Gastgeber fortsetzen |
| Rückfrage Titel | Spiel als Gastgeber fortsetzen? |
| Rückfrage Text | Dein Handy führt das Spiel ab jetzt. Die anderen kommen von selbst wieder dazu. |
| Rückfrage Knöpfe | Fortsetzen · Weiter warten |
| Warnzeile | Dein Spielstand ist vielleicht nicht der neueste. |
| Warnzeile (WLAN) | WLAN-Mitspieler kommen dann nicht mit. |
| an alle | %s führt das Spiel weiter (Gastgeber war weg). |
| Hauptmenü | Partie fortsetzen |
| Hauptmenü, Zeile | %s · Runde %d · vor %d min |
| Hauptmenü | Partie verwerfen |
| Rückfrage Hauptmenü (ältere eigene Datei) | Deine Partie von vor %d min fortsetzen? |
| Fortsetzen, besetzt | %s führt das Spiel inzwischen. Du spielst als Gast weiter. |
| Fortsetzen, abgelaufen | Der Online-Raum ist abgelaufen. Die Partie lässt sich nicht mehr fortsetzen. |
| So geht's (zwei Sätze) | Fällt der Gastgeber aus, führt ein Mitspieler mit der App das Spiel weiter. Dafür hat jede App eine Sicherung des ganzen Spielstands – die App zeigt fremde Karten nie, wer schummeln will, käme aber heran. |

## 7. Testplan

**Automatisch.** Alle Tests laufen in einem Prozess und werden synchron gepumpt wie `test_game_online.gd`. Sie laufen in der seriellen Spur, nutzen die freien Ports 24961–24969 und sollten jeweils unter 60 s bleiben (`speed = 0`, kurze `retry_ms`, `host_away_ms`, `T_SILENT`, `T_AWAY`, `T_STEP`, `PROBE_MS` als Eigenschaften; **einspritzbare Uhr** für alle Wanduhr-Fristen; `backup_enabled`).

- `test_handover_snapshot.gd`
  - Schnappschuss → `resume(data, my_seat)` mit Platzwechsel.
  - Zustände: Farbwahl, offene Strafe, Glücksspiel mit `q`, Ablege-Auswahl samt `undo`, Mau-Fenster, `substitute`, Warteliste mit `join_open`, Rundenende.
  - Prüfungen: `view_for` aller Plätze vorher gleich nachher (bis auf `host`); gzip-Größe bei 10 Plätzen und 116 Karten < 16 KB; `gen` steigt nur bei Platzwechsel, `parent` stimmt.
  - **Tokens A→B→C:** Übernahme A→B, dann B→C; alle Tokens bleiben an ihren Plätzen, kein Token doppelt; A und B kommen zurück und landen auf ihren eigenen Plätzen.
- `test_relay_takeover.gd` (`NetRelayDouble`)
  - `open_existing` mit `conns`; 4012 an alte `c`.
  - **Rundumschlag:** Lite-artiger Gast meldet sich mit neuer `c` beim still toten Gastgeber an, sendet danach nichts; nach der Übernahme bekommt er 4012 und meldet sich neu an. Rahmenzahl je Frame ≤ 150.
  - Unbekannte `c` mit `msg` wird gekickt.
  - `PREDELETE` und `stop()` ohne `end`, `leave()` mit `end`.
  - **4000:** `replaced` vor jedem `ws_closed`, kein `_drop_all_guests`, danach keine Datei geschrieben, kein Bot-Zug, keine Meldung „getrennt“.
  - Zwei Bewerber: Der Verlierer bekommt `replaced` und behält seine Datei.
  - **Vorsichtiges Neuverbinden:** nach jedem `_lost` mit Raum erst `/info`; `host:true` → Probe; mit eingespritzter Uhr auch nach „10 min Tiefschlaf“, bei der die Monotonuhr nur Sekunden zeigt.
- `test_handover_online.gd` (Gastgeber, 2 App-Gäste, 1 Gast `kind:"web"`, 1 Bot)
  - Einige Züge mit `MauBot`, dann geplante Übergabe an Gast B.
  - Prüfungen:
    - Alle sitzen auf denselben Plätzen.
    - Der alte Gastgeber ist Gast.
    - Die Partie läuft bis Rundenende weiter.
    - Kein `bye`.
    - `check_message` (Lecktest): `bk` geht nie an `web` und nie an einen Gast mit `kind:"app"` ohne `hello.bk`.
    - Reihenfolge je Gast: `bk` mit `seq` n kommt vor der Sicht, die zu n gehört.
  - **Frist `within_ms`:** Ziel bekommt keinen `room`-Rahmen → bricht ab, ist wieder Gast; alter Gastgeber taut nach `check_now` auf, `gen` unverändert.
  - Eingefrorener Gastgeber: Schließen des Gast-Sockets des Ziels erzeugt kein `_changed`.
- `test_takeover_online.gd`
  - Harter Ausfall, einmal mit `r._ws = null` ohne Schließen (still) und einmal mit Schließen (4503).
  - Rang 0 übernimmt, Rang 1 bricht ab.
  - **Frische Probe:** Rang 1, dessen alte `c` der neue Gastgeber nicht kennt, übernimmt nicht ein zweites Mal (`/info` `host:true`, frische Probe bekommt `welcome`).
  - Zwei gleichzeitig: Einer tritt ab, gleiche `gen`, andere `epoch` → kein Hin und Her.
  - Ein nicht aktueller Gast übernimmt nicht.
  - Gastgeber `away` → keine Übernahme vor `T_AWAY`.
  - **`away` → Socket zu → 4503 → keine Übernahme vor `T_AWAY` ab dem `away`**; ebenso 4503 und `away` innerhalb 2 s danach.
  - Der alte Gastgeber kommt mit Probe zurück und wird Gast.
  - **Abstammung:** alter Gastgeber setzt nach Übernahme durch B seine eigene Datei fort (`gen` 1), B (`gen` 2) wird verdrängt, meldet sich als Gast mit `hello.bk` → `handover own:true` an B, B führt mit seinem Stand weiter; `handover_no`, wenn B's Datei inzwischen abweicht.
  - „Neuester Stand gewinnt“ in der Einschwingzeit (gleiche Vorgeneration, höheres `seq`).
  - Einschwingzeit endet, sobald alle Erben `hello` geschickt haben, spätestens nach 15 s.
  - `wlan_humans` → `heirs = []`, keine Automatik.
- `test_host_resume.gd`
  - Gastgeber `free()` ohne `leave()`, dann neues `HostTable` aus `netz_partie.json`.
  - Online gleicher Raum, WLAN gleicher Port: Gäste kommen per Token zurück.
  - Datei wird bei `leave()` gelöscht.
  - **Gast:** Datei wird bei `lobby` ohne `waiting` und bei `start` mit anderer `gid` gelöscht; Wächter in Lobby aus.
  - Hauptmenü: eigene Datei < 5 min ohne Rückfrage, älter mit Rückfrage (eingespritzte Uhr).
- Lite (`Invoke-WebOnlineTest`, Chrome headless): Fall „Übernahme online“. Lite meldet sich nach 4012 mit Token beim neuen Gastgeber an; zweiter Fall Lite mit neuer `c` während eines stillen Gastgebers.
  - **Umsetzung (1.6.1):** nicht in `netz_online.html` (Schein-WebSocket ohne Gastgeber), sondern mit dem echten Lite (Selbsttest `autotest.js`) am echten Gastgeber: Godot-Skript `game/tests/web_takeover.gd` (auf `handover_kit.gd`, Vermittler-Nachbau mit Lader, TCP 24961–24964), aufgerufen von `tools/build.ps1` → `Invoke-WebTakeoverTest` nach dem Browser-Onlinetest (kein `test_*`, weil es Chrome braucht). Fall 1: Hanna still tot, Anna übernimmt, Lite folgt per 4012 mit Token und spielt weiter. Fall 2: Anna still tot, Lites Socket wird beim Vermittler geschlossen, Lite meldet sich mit neuer `c` beim toten Gastgeber an; Ben übernimmt, erst der Rundumschlag holt Lite zurück. Geprüft über den Gastgeber (Token, Platz, verbunden, Aktionen von Lites Platz, Zug geht weiter). Gegenprobe `OHNE_RUNDUMSCHLAG=1`: Fall 2 scheitert. ≈ 20 s.

**Gerätetest S21/S10, gesperrt** (Testschalter `MauMauFlipTestLock`):
- Online im Heim-WLAN; S21 ist Gastgeber, S10 App-Gast plus ein Bot. Vermittler ist der echte (die App lädt kein `/c/<version>/`, ein Versions-Tag ist nicht nötig) oder `relay_double_main` über `adb reverse tcp:24700`.
- Ablauf:
  1. Partie starten, mit zeitversetzten `input tap`.
  2. **Andere App:** `adb shell input keyevent HOME` am S21. Erwartung: S10 zeigt „… ist kurz in einer anderen App“, **keine Übernahme vor 180 s**. Danach S21 per `am start` zurückholen, Partie läuft weiter.
  3. **Ausfall:** `adb shell am force-stop de.maumauflip.game` am S21. Das S10 übernimmt nach ≈ 40–55 s; prüfen per `logcat` und `screencap`.
  4. **Rückkehr:** `adb shell am start -n de.maumauflip.game/com.godot.game.GodotAppLauncher` am S21 (kein Neustart: der Testschalter verfällt dabei, und das WLAN-Debugging ist danach meist aus) → „Partie fortsetzen“ → es wird Gast.
  5. Geplante Übergabe S10 → S21 per Tipp.
- Erfolgskriterien: dieselben Hände wie vorher (Bildschirmfoto), kein Hinweis „Raum beendet“, kein doppelter Gastgeber im Log.
- Still toter Gastgeber, Tiefschlaf-Uhr und Doppel-Gastgeber nur automatisch (`svc wifi disable` trennt auch ADB).
- Danach den Ausgangszustand herstellen. Laufzeit des Vermittlers im Cloudflare-Dashboard notiert der Nutzer bei Gelegenheit.

## 8. Lieferstufen

**Beta 1.6.1: online.**
- Schnappschuss (mit Tokens aller Plätze, `epoch`/`parent`, Warteliste), Verteilung (`bk` vor dem Stand, `alive` 15 s), eigene Sicherung beim Gastgeber.
- Kein `end` mehr beim Schließen; Raum übernehmen mit 4012-Rundumschlag; 4000 ohne `_drop_all_guests`, `_frozen`.
- Vorsichtiges Neuverbinden bei jeder Rückkehr (`/info` + Probe), Wanduhr.
- Geplante Übergabe (nur wenn alle entfernten Menschen online sind), automatische Übernahme (nicht bei WLAN-Mitspielern), Abstammungsregel, „Spiel als Gastgeber fortsetzen“, Hauptmenü „Partie fortsetzen“.
- Fortsetzen durch den **Gastgeber selbst auch im WLAN**. Das ist fast gratis, weil Adresse und Port gleich bleiben.
- Keine Änderung an Vermittler und Lite. Die Version ist schon auf 1.6.1 gesetzt, der Testschalter liegt in `GodotApp.java`.

**Beta 1.6.2: WLAN und Spiel-WLAN.** Ausgearbeitet in Abschnitt 10 (13.10.2026); wo 10 von den Stichpunkten hier abweicht, gilt 10.
- **Suche:** `info()`/Suchantwort mit `gid`, `gen` (`net_session.gd:460`, `NetProtocol.parse_reply`).
  - App-Gäste suchen nach dem Ausfall mit eigener `NetDiscovery` nach `gid`.
  - Geplant: `{t:"move", addr, port, gid, gen}`.
  - Rückkehr mit `bk_token`.
- **Lite:**
  - `{t:"hosts", gid, list:[{name, url}]}` mit Ersatz-Adressen (IP der Erben, Port 24690).
  - `Verbindung` probiert sie reihum (`netz.js:87`).
  - „Seite neu laden“ führt auf die aktuelle Adresse, das Token steht in `#t=…`.
  - Der neue Gastgeber erlaubt die Herkunft früherer Gastgeber-Adressen (`net_server.gd:912`, Liste `wlan.addrs` im Schnappschuss).
- **Spiel-WLAN:**
  - Erst Stand übernehmen, dann `QrJoin.wifi_release()`, dann eigenes Spiel-WLAN mit QR (vorhandenes `GameWifiPanel`).
  - Gäste kommen über den QR-Scanner (`bk_token`). Browser-Gäste nutzen WLAN-QR und Spiel-QR; sie landen auf der Warteliste, dann kommt neu **„Auf den Platz von %s setzen“** (`HostTable.seat_assign(id, seat)`, `seat_manager.gd`).
  - Fehler `QrWifi.release` beheben (Bindung an ein verlorenes Netz wird nicht gelöst).
- Automatische Übernahme auch in gemischten Partien (`wlan_humans` sperrt dann nicht mehr).
- **Abgelaufener Online-Raum:** Ein neuer Raum für die alte Partie (Link teilen; App-Gäste per `bk_token`, Browser per „Auf den Platz von …“).
- **Begründung für den Schnitt:** Die WLAN-Übernahme braucht Änderungen an Lite und an der Herkunftsprüfung, und ein Spiel-WLAN lässt sich gesperrt nicht prüfen (Systemdialog „Mit Gerät verbinden?“). Online ist ohne beides fertig.

## 9. Risiken und offene Punkte

- **Still toter Gastgeber erst nach 40 s erkannt:** Kürzer geht es nur mit häufigerem `alive`, das den Raum öfter weckt (Laufzeit, 2.). Verworfen wurde die Alternative „Rang 0 pingt den Gastgeber nach 15 s Stille“: Sie spart im laufenden Spiel nichts (dort fließen ohnehin Züge), macht aber den Rang-0-Gast zur Voraussetzung der Erkennung.
- **Gastgeber lange in einer anderen App** (Anruf > 3 min): Ein Gast übernimmt. Das ist gewollt; der Rückkehrer spielt als Gast weiter.
- **Halboffener Socket des alten Gastgebers beim Vermittler:** `/info` meldet dann `host:true`. Deshalb gilt vor jeder Übernahme die frische Probe „8 s ohne Antwort“.
- **Gleiche `gen`, andere `epoch`** (zwei Gäste übernehmen fast gleichzeitig): kein automatischer Ausgleich, die Sekunden des Verlierers gehen verloren. Ein Vergleich über `seq` könnte zu Hin und Her führen, weil nur der aktive Zweig weiterzählt.
- **Gäste mit Mobilfunk:** ≈ 9 MB pro Abend zusätzlich. Später kann der Gastgeber nur `game`-Deltas oder höchstens alle 2 s einen Schnappschuss schicken. Ein Zeitraster passt aber schlecht zur Regel „erst Sicherung, dann Stand“; dann müsste der Stand mit dem `bk` warten.
- **Aufgeschobene Platzaufträge** (`_seat_ops`) gehen bei einer Übergabe verloren (1.2). Die Warteliste kommt mit.
- **Android:** Der neue Gastgeber muss die App offen halten. Im Hintergrund pausiert Android sie, und dann gilt wieder die 180-s-Regel.
- **Gemischte Partien in Stufe 1** (WLAN- und Online-Gäste zugleich): keine automatische Übernahme, geplante Übergabe gesperrt, „Spiel als Gastgeber fortsetzen“ nur mit Warnzeile. Kommt mit Stufe 2.
- **4012-Rundumschlag** erzeugt bis zu ≈ 300 Rahmen und ebenso viele `err unknown_c`. Das ist einmalig je Übernahme und liegt unter den Grenzen des Vermittlers; bei sehr hohen `c` (lange Räume mit vielen Neuverbindungen) wird es mehr – dann auf `max_c + 256` begrenzt, ältere `c` sind ohnehin bekannt oder längst zu.
- **Schummeln:** siehe 5. Die Einstellung „Sicherung an Mitspieler“ ist offen (Nutzerfrage).
- **iPhone und Lite** sind ungetestet wie bisher.

**Verworfen bzw. angepasst aus der Gegenprüfung:**
- Rundumschlag „an alle `c` in 1 … max + 256 in einem Frame“: angepasst auf höchstens 150 je Frame, weil Übernahme und erster Stand in denselben Frame fallen und `host_burst` 400 sonst knapp wird.
- „`role:"host"` im Hauptmenü erst nach `T_AWAY`“: nicht übernommen. Stattdessen `/info` + frische Probe, ohne Rückfrage nur bei einer Datei < 5 min. Ein Irrtum heilt sich über die Abstammungsregel (der eigene Zweig behält `gen`, ein Ersatz mit höherer `gen` wird per `handover own` zurückgeholt); 3 min Wartezeit für den häufigen Fall „App versehentlich geschlossen“ wären zu lang.
- `alive`-Abstand: 15 s übernommen, `T_SILENT` auf 40 s; die Rang-0-Variante verworfen (Begründung oben).

## 10. Stufe 2: WLAN und Spiel-WLAN (Beta 1.6.2)

Stand 13.10.2026, Entwurf gegen den Code von Beta 1.6.1. Nutzerwunsch vom 13.10.: Bei einer Übernahme im Spiel-WLAN öffnet der neue Gastgeber ein eigenes Spiel-WLAN und gibt es per QR-Code weiter. Die anderen kommen über den vorhandenen Weg: QR-Scanner der App, im Browser WLAN-QR + Spiel-QR. Jeder App-Gast hält den Spielstand (wie 1.6.1).

**Grundsatz:** Im WLAN gibt es keinen Schiedsrichter wie den Vermittler (4000, `/info`). Ersatz:
1. **Suche mit Partie-Kennung:** `/info` und die Suchantwort tragen `gid`, `gen` und `epoch`. Wer den Gastgeber vermisst, sucht die Partie, nicht die Adresse.
2. **Bestätigte Übergabe:** Das Ziel meldet `handover_ok`. Erst dann schickt der alte Gastgeber `move` an alle und tritt ab.
3. **Gastgeber-Wächter:** Jeder WLAN-Gastgeber fragt alle 5 s nach Gastgebern derselben `gid`; der ältere Zweig tritt ab (10.11).

**Der Vermittler bleibt unverändert.** Lite ändert sich (10.9):
- Im WLAN liefert jeder Gastgeber seine eigene Lite-Fassung aus.
- Online liefert der Vermittler die Fassung des Raums (Tag `v1.6.2`, also erst ab dem Release). Lite online braucht die neuen Teile nicht.

### 10.1 Protokoll (nur additiv)

| Nachricht | Richtung | Inhalt | Ältere Geräte |
|---|---|---|---|
| `/info`, Suchantwort | Gastgeber → alle | zusätzlich `gid`, `gen`, `epoch` und `conn` (Zahl der verbundenen entfernten Menschen, für den Wächter 10.11); nur mit laufender Partie, aus `welcome_extra` | ignorieren |
| `hello` (App) | Gast → Gastgeber | zusätzlich `hp`, `bk_gid` (gid der Sicherung) und `ap:{ok, perm}`. `hp` ist der Port, auf dem dieses Gerät als Gastgeber lauschen würde (`HostSwitch.port_first`, Standard 24690). `ap.ok`: Das Gerät kann ein Spiel-WLAN öffnen (LocalOnlyHotspot vorhanden); `ap.perm`: Die Erlaubnis dafür ist schon erteilt | – |
| `welcome` (aus `assign_seat`) | Gastgeber → Gast | zusätzlich `assigned:true` (10.10) | ignorieren (Lite alt: unschädlich, siehe 10.10) |
| `handover_ok` | Ziel → Gastgeber | `{port, qr}`: Das Ziel führt. `port` ist sein Server; `qr:true` heißt, es öffnet ein eigenes Spiel-WLAN (keine LAN-Adresse) | – |
| `move` | Gastgeber → Gäste | `{gid, gen, epoch, name, how:"lan"\|"online"\|"qr", addr, port, room, relay, url}` | ignorieren |
| `hosts` | Gastgeber → Browser | `{gid, gen, list:[{name, url}], online, ap, ap_name}`. `url` ist `http://<addr>:<hp>/` je Erbe mit Link „wlan“, in Rangfolge; `online` ist der Raum-Link oder ""; `ap` wie `wlan.ap`, `ap_name` ist der Name dessen, der bei Verlust des Spiel-WLANs ein neues öffnet (10.8). Geht bei `start` und `resume` **immer** hinaus (auch mit leerer Liste), nach jeder Übernahme mit der neuen `gen` und bei jeder Änderung | ignorieren |

- **`/info` und Suche:** `make_info` bleibt. `NetHostSession.info()` (`net_session.gd:535`) ergänzt `gid`, `gen` und `epoch` aus `welcome_extra`. Danach muss `HostTable._update_welcome()` (`host_table.gd:741`) `/info` und die Suche auffrischen. Das geht über `session._changed()` oder ein neues `session.set_game_mark(gid, gen, epoch)`, das beides erledigt.
- **Suchantwort lesen:** `parse_reply` (`net_protocol.gd:578`) übernimmt `gid` (hex, ≤ 32), `gen` (int ≥ 0), `epoch` (hex, ≤ 16) und `conn` (int 0–16). `NetDiscovery.games` führt sie je Eintrag.
- **Uhr der Suche:** `NetDiscovery` zählt heute mit `Time.get_ticks_msec` (Abfrageabstand, Verfall). Neu ist `now_ms: Callable` (Standard `Time.get_ticks_msec`), auch für `scan_ms`; die Tests spritzen die Uhr ein.
- **Nachrichten der Gäste:** `clean_client_message` übernimmt `hp` (1024–65535), `bk_gid` (hex, ≤ 32), `ap` (`ok`/`perm` bool) und den neuen Typ `handover_ok` (`port` int, `qr` bool). Neu sind `make_move`, `clean_move` und `make_hosts`. `clean_move` prüft auf dem Gast die `gid` wie `clean_backup_message`.
- **`bk_token` nur bei passender `gid`:** `_hello` (`net_session.gd:631`) nimmt `bk_token` nur noch, wenn `bk_gid == welcome_extra.gid`. Grund: Der Gast schickt `bk_token` künftig an jede Adresse (10.6). Ein fremder Gastgeber lernt so höchstens ein Token, das bei ihm nichts gilt.
- **Abstammung nur für dieselbe Partie:** `_check_lineage` überspringt Gäste mit anderem `bk_gid`. Das ersetzt das `handover_no` für fremde Partien aus 4.7.
- **Neue Konstanten** in `NetProtocol`:
  - `HOST_SCAN_MS` = 5000 (Gastgeber-Wächter)
  - `LAN_SEARCH_MS` = 2000 (Suche vor der Übernahme)
  - `PAST_MAX` = 16 (frühere Gastgeber-Adressen)

### 10.2 Schnappschuss-Ergänzungen (`format` bleibt 2)

- **`seats[*].addr`:** die IPv4, unter der der Gastgeber diesen Platz zuletzt im WLAN sah (`players[id].address`, nur bei Link „wlan“).
- **`seats[*].hp`:** der Port aus `hello.hp`. `addr` und `hp` setzt `_note_link`.
- **`seats[*].ap`:** `{ok, perm}` aus `hello.ap` (10.1), nur im Speicher des Gastgebers und im Schnappschuss; ältere Apps ohne Feld gelten als `{ok:false, perm:false}`.
- **`wlan: {port, addrs, ap, ap_seat, past}`:**
  - `ap`: Die Partie läuft in einem Spiel-WLAN (`NetAddresses.binding() == "hotspot"` beim Gastgeber, oder der Gastgeber sitzt selbst im Spiel-WLAN eines Mitspielers, siehe `ap_seat`). Die Gäste wissen damit: Fällt das Spiel-WLAN weg, ist ihr Netz weg (10.8).
  - `ap_seat`: der Platz, dessen Handy das Spiel-WLAN führt (−1 ohne Spiel-WLAN). Normalerweise der Gastgeber. Nach einer Übernahme innerhalb des noch bestehenden Spiel-WLANs (alter Gastgeber nur abwesend oder eingefroren) bleibt es der alte Platz (10.8, „Übernahme im fremden Spiel-WLAN“).
  - `past`: frühere Gastgeber-Adressen dieser Partie als `"ip:port"`. Die Liste wächst über die ganze Kette (A → B → C), höchstens `PAST_MAX` Einträge. Sie ist die Grundlage der Herkunftsprüfung (10.9).
- **Eigene Adressen auffrischen und Neu-Binden** (Gegenprüfung): Heute hängen `rebind` und die Zustandsabfrage am `_process` von `GameWifiPanel`; am Tisch lebt das Panel nur im SeatManager-Overlay. Schließt der neue Gastgeber das Overlay zu früh, bleibt der Server ans alte Netz gebunden. Neu ist deshalb **`GameWifiWatch`** (`game/scripts/app/game_wifi_watch.gd`, Node, Zustandsquelle einspritzbar, Standard `NetAndroid.game_wifi_state`):
  - Der `TableScreen` des Gastgebers legt ihn an, solange eine Netzpartie läuft (auch ohne geöffnetes Overlay).
  - Alle 1,5 s: Zustand lesen; ändert sich Spiel-WLAN (auf/zu, Adresse da) oder die Bindung, dann `session.rebind(…)` wie heute im Panel, danach `HostTable.refresh_addrs()` (neu: `_note_addrs`, `wlan.ap`/`ap_seat` fortschreiben, `hosts` neu verteilen, `bk` neu).
  - `GameWifiPanel` liest nur noch `GameWifiWatch.state` und zeigt an; im Lobby-Ablauf (ohne Tisch) bleibt sein eigenes Neu-Binden wie bisher.
- **`resume()` und `link` des alten Gastgebers** (`host_table.gd:251-252`): `seats[old_hs].link` wird nur dann `"online"`, wenn der Schnappschuss einen Raum hat; sonst `"wlan"`. Sonst stimmen Rangfolge (10.3) und `how` einer Übergabe an ihn (10.7) nicht.
- **`wlan_humans`** bleibt als Feld in `MatchSnapshot.clean`, sperrt aber nichts mehr.

### 10.3 Ersatz-Rangfolge (ersetzt die Stufe-1-Sperre aus 4.2)

- **`heirs()`** (`host_table.gd:629`): App-Gäste im `bk`-Verteiler, die verbunden und nicht `away` sind, im Uhrzeigersinn ab dem Gastgeber.
  - In gemischten Partien kommen zuerst alle mit Link „wlan“, dann die mit Link „online“. Grund: Ein WLAN-Erbe erreicht beide Gruppen (LAN und Raum), ein Online-Erbe nur die Online-Gäste direkt.
  - Online-Erben gibt es nur, wenn die Partie einen Raum hat **und keine WLAN-Mitspieler am Tisch sitzen** (`wlan_humans()`, Gegenprüfung der Umsetzung): Fällt beim Gastgeber nur das Internet aus, merken die WLAN-Gäste nichts (der Server-Thread antwortet), und ein Online-Erbe eröffnete ein zweites Spiel. Von Hand („Spiel als Gastgeber fortsetzen“ mit Warnzeile) bleibt es möglich.
  - WLAN-Erben sperrt `wlan_humans()` nicht mehr.
- **Spiel-WLAN (`wlan.ap`):** Innerhalb jeder Gruppe kommen Geräte mit `ap.ok` zuerst (die mit `ap.perm` vor denen ohne), danach die übrigen im Uhrzeigersinn. So erbt nach Möglichkeit ein Handy, das sofort ein eigenes Spiel-WLAN öffnen kann. Nur Rang 0 übernimmt automatisch (10.8).

### 10.4 Erkennung ohne Vermittler (Gast-Wächter, `HostSwitch`)

- **Scharf auch im WLAN:** `_armed` (`host_switch.gd:398`) verlangt nicht mehr `client.is_online()`. Nötig sind wie bisher eine Sicherung derselben `gid`, dazu WLAN oder Raum.
- **Lebenszeichen:** Im WLAN zählt jede Nachricht des Gastgebers als `last_host_wall`, auch das `pong`.
  - Der Netz-Thread des Servers beantwortet `ping` selbst bei angehaltener Hauptschleife (`net_server.gd:12`). Solange der Prozess lebt, erkennt also niemand einen Ausfall.
  - Ist der Gastgeber nur in einer anderen App, kommt zusätzlich `away`; dann gilt T_AWAY wie online.
- **Gegenstück zu 4503:** `NetClient.host_lost_wall` ist der erste gescheiterte Neuversuch seit der letzten Annahme (Verbindung verweigert, Frist abgelaufen oder Schließen ohne Code). `deadline_for(last, lost, away_since, …)` bleibt unverändert; `lost` tritt an die Stelle von `gone`.
- **Gegenstück zu `reached` („eigenes Netz weg“):** `HostSwitch.lan_ok()` ist wahr, wenn eine eigene Adresse im Netz des alten Gastgebers liegt.
  - Grundlage ist `NetAddresses.interfaces()` (liefert `address` und `prefix`; `own_addresses()` hat kein Präfix) und der Vergleich über das neue `NetProtocol.same_net(a, b, prefix)`. In Tests ist die Prüfung einspritzbar (`net_check: Callable`).
  - Ohne `lan_ok` wird **nie** automatisch übernommen. Ausnahme: Spiel-WLAN, Rang 0 (10.8).
- **Abläufe:**
  1. *watch*: Ist die Frist überschritten, geht es nach *missing*. Der Gast verbindet neu an die alte Adresse (`reconnect_now()`) und startet eine eigene `NetDiscovery`-Suche. Sie geht als Rundruf und zusätzlich per Unicast (`manual`) an die `wlan.addrs` des alten Gastgebers und die `addr` aller Erben; Unicast hilft, wenn der Router Rundrufe filtert.
  2. *missing*, nach `probe_ms` (8 s):
     - Kommt ein `welcome`, geht es zurück nach *watch*.
     - Findet die Suche die `gid` mit `gen ≥ Sicherung.gen`, **folgt** der Gast (10.5).
     - Sonst geht es nach *waiting* mit der Wartezeit Rang × `T_STEP`, nur mit `lan_ok` und aktueller Sicherung. Die Suche läuft weiter; ein Fund beendet das Warten, und der Gast folgt.
  3. *checking* (statt `/info` und frischer Probe): `LAN_SEARCH_MS` lang suchen, dazu eine frische Verbindung zur alten Adresse. Bei einem Fund folgt der Gast, bei einem `welcome` geht es zurück nach *watch*.
     - **Gemischt** kommt die Prüfung von 1.6.1 beim Vermittler dazu: `/info` und eine Probe mit eigenem Token über einen eigenen `NetClient.connect_probe`.
     - Antwortet dort ein Gastgeber, folgt der Gast über den Raum (`_follow_room`) und übernimmt nicht.
     - Ist der Vermittler nicht erreichbar, zählt nur das LAN.
  4. *taking*: `_take_over` wie 1.6.1. Ohne Raum gilt die Übernahme sofort (`_finish_take`, `host_switch.gd:456`); gemischt mit Raum wartet sie wie online auf den `room`-Rahmen – außer bei einem WLAN-Erben ohne Vermittler (10.12).
- **Fristen unverändert:** `T_SILENT` 40 s, `T_STEP` 12 s, `PROBE_MS` 8 s. Ein Ausfall im WLAN führt damit nach ≈ 40–50 s zur Übernahme durch Rang 0.

### 10.5 Folgen nach Übernahme oder Umzug (App-Gast)

- **`ClientTable.move_to(addr, port)`** (neu): Der Gast-Socket schließt ohne `bye`, dann folgt `join(addr, port, _name, eigener Platz-Token)`. Die Sicherung bleibt im Speicher; es ist wie `resume_guest`, nur mit neuer Adresse.
  - Der Tisch bleibt derselbe, der `HostSwitch` braucht keinen Wechsel.
  - Der `NetClient` speichert Tokens je `ip:port` (`net_client.gd:625`). Deshalb wird das Platz-Token ausdrücklich übergeben.
  - `head` und `head_gid` bleiben wie die Sicherung erhalten (`join()` leert sie heute, `client_table.gd:87`); sonst ist `backup_current()` bis zum nächsten `bk` falsch und die Automatik gesperrt.
  - `move_to` sendet das neue Signal `moved`. Der `HostSwitch` ruft darauf `_back_to_watch(now)` mit `_probe_welcomes = 0` und `_armed_at = now`: Der neue `NetClient` beginnt mit `welcomes = 0` und `last_host_wall = 0`; mit den alten Zählern ginge *watch* sofort nach *missing* bzw. *missing* nie zurück nach *watch* (`host_switch.gd:307-318`).
- **`_follow_room(relay, room)`:** dasselbe mit dem Raum-Link.
- **Auslöser:** Suche (10.4), `move` (10.7) und die Niederlage des eigenen Gastgebers gegen den Wächter (10.11).

### 10.6 Sicherung beim Beitritt (Adresse egal)

- **Laden:** `ClientTable._load_backup` (`client_table.gd:272`) lädt die Datei heute nur bei gleichem Raum. Neu lädt es sie bei jeder Adresse und jedem Raum, wenn sie `MatchSnapshot.resumable(d, now, true)` ist.
- **`resumable(d, now, ignore_room := false)`:** Mit `ignore_room` prüft es das Raumalter (`ROOM_LIFE_S`, `match_snapshot.gd:113`) nicht. So genutzt beim Laden hier und für 10.13 (Raum nach 24 h beendet); ohne `ignore_room` nur, wenn der alte Raum benutzt werden soll (`saved_offer` für „Raum übernehmen“, 1.6.1).
- **Mitschicken:** `hello.bk`, `bk_token` und `bk_gid`. Der Gastgeber nimmt `bk_token` nur bei passender `gid` (10.1).
- **Folge:** App-Gäste landen über **jeden** Weg auf ihrem Platz: Suche, QR-Scanner im neuen Spiel-WLAN, neuer Raumcode oder eingetippte Adresse.
- Die Löschregeln aus 2. bleiben, z. B. bei `start` mit fremder gid oder bei `lobby` ohne `waiting` derselben Partie.

### 10.7 Geplante Übergabe im WLAN und gemischt

**Wann sie geht:** `handover_block` (`host_table.gd:653`) erlaubt jetzt WLAN, Spiel-WLAN und gemischte Partien.
- Ausgegraut bleiben Gäste ohne App oder ohne `bk`, nicht verbundene oder `away`, und der eingefrorene Tisch.
- Gemischt mit Online-Ziel bleibt die Übergabe zusätzlich gesperrt, solange der Raum nicht `open` ist.
- Bei `how:"qr"` sind Ziele ohne `ap.ok` ausgegraut (Grund „Kann kein Spiel-WLAN öffnen.“); Ziele ohne `ap.perm` bleiben wählbar, die Zeile sagt dann „Muss das Spiel-WLAN erlauben.“

**Warnzeilen im Auswahldialog:**
- Führt der Gastgeber ein Spiel-WLAN: „Alle müssen danach einen neuen QR-Code scannen.“
- Ist das Ziel online und sitzen WLAN-Mitspieler am Tisch: „WLAN-Mitspieler brauchen dann Internet.“

**Art der Übergabe (`how`):** `online`, wenn das Ziel online verbunden ist – auch wenn der Gastgeber ein Spiel-WLAN führt (Gegenprüfung der Umsetzung: sonst öffnete ein entferntes Ziel ein Spiel-WLAN, das keiner erreicht); sonst `qr`, wenn `wlan.ap` gilt und der Gastgeber das Spiel-WLAN selbst führt (`ap_seat == host_seat`); sonst `lan` (auch im Spiel-WLAN eines Dritten, das bestehen bleibt). Die Warnzeile „Alle müssen danach einen neuen QR-Code scannen.“ gilt nur für `qr`-Ziele.
- `how` übersteht `clean_backup_message`, damit auch ein Ziel ohne beobachteten Gast-Tisch (Zustände *joining*, *resuming*; Abstammung) die richtige Art kennt.
- Der alte Gastgeber folgt der Antwort des Ziels: `qr` nur bei `handover_ok.qr`, mit Port sonst `lan`.

**Ablauf:**
1. **Gastgeber:** schickt `{t:"handover", z, within_ms, how}` an das Ziel, friert ein und meldet allen „Gastgeber wechselt zu %s …“ (wie 4.1).
2. **Ziel** (`HostSwitch._handle_handover`). Immer zuerst `adopt_backup`, dann je nach `how`:
   - `lan`:
     1. `HostTable.resume(d, seat)`: Der Server lauscht, der eigene Gast-Socket bleibt offen.
     2. `handover_ok{port}` über diesen Socket. **Danach den Socket leeren:** `ClientTable.send_and_drain(msg, max_ms = 300)` (neu) bzw. `NetClient.drain(max_ms)` fragt den `WebSocketPeer` per `poll()` ab, bis `get_current_outbound_buffered_amount() == 0` oder die Frist um ist. Erst dann `ct.suspend()`. Grund: Godot schreibt erst in `poll()`, und `_drop_client` gibt den `NetClient` sofort frei (`client_table.gd:372-384`); ohne Leeren käme `handover_ok` womöglich nie an, der alte Gastgeber tauete nach `HANDOVER_TIMEOUT_MS` auf, und es gäbe zwei Gastgeber.
     3. **Erst jetzt** bei Raum `open_online_existing`. So kommt `handover_ok` beim alten Gastgeber vor dem 4000 an.
   - `qr`: `handover_ok{qr:true}` sofort und geleert wie oben, dann `ct.suspend()`, `QrJoin.wifi_release()`, `resume`, gegebenenfalls Raum, dann ein eigenes Spiel-WLAN (10.8, **automatisch mit Wiederholung**).
   - `online`: wie 1.6.1 (4000). `handover_ok` geht zusätzlich hinaus und schadet nicht.
   - Die Frist `within_ms` gilt wie 1.6.1. Ohne Raum zählt nur der Server-Start. Scheitert er, bricht das Ziel ab (`_take_failed`) und ist wieder Gast.
3. **Alter Gastgeber** bei `handover_ok` vom Ziel (nur während der laufenden Übergabe):
   - Er schickt `move` an alle anderen verbundenen Gäste:
     - `lan`: `addr` ist die Adresse des Ziels aus Sicht des Gastgebers (`players[id].address`), `port` kommt aus `handover_ok`, `url = http://addr:port/`.
     - `qr`: der Name des Ziels.
     - `online`: an die WLAN-Gäste `room`, `relay` und als `url` den Raum-Link.
   - Online-Gäste brauchen kein `move`; sie folgen über 4000/4012 wie in 1.6.1.
   - Danach **`session.drain(500)`** und erst dann `stepped_down` mit Ziel `{how, addr, port | room, relay}` (neues Feld `HostTable.step_target`). `session.flush()` genügt nicht: Mit Server-Thread tut es nichts, und `handover_shutdown` → `_close_session("", false)` → `server.stop()` setzt `_quit`, leert `_cmds` und schreibt nur den Close-Rahmen (`net_server.gd:173-188`, `340-347`); noch nicht verarbeitete Befehle und volle `out`-Puffer gingen verloren.
     - Neu `NetServer.drain(max_ms)`: Im Thread (bzw. bei `threaded = false` direkt) erst alle `_cmds` abarbeiten, dann schreiben, bis alle `out`-Puffer leer sind, höchstens `max_ms`. Ohne Thread genügt ein Schleifen-`poll()`. Rückgabe: true, wenn alles hinaus ist.
     - `NetHostSession.drain(max_ms)` ruft `server.drain` und `relay.flush()`.
   - **Gemischt:** Kommt das 4000 vor `handover_ok`, geht `move` mit `port = hp` des Ziels hinaus (Rückfall). Was zuerst kommt, löst das Abtreten aus; das Zweite wird verworfen.
4. **Abtreten** (`_on_stepped_down`; heute steht dort „WLAN: Stufe 2“, `host_switch.gd:662`):
   - `lan`: Gast-Tisch mit `join(addr, port, Name, Platz-Token)` und eigener Datei.
   - `online`: wie 1.6.1.
   - `qr`: Der alte Gastgeber schließt sein Spiel-WLAN (`NetAndroid.game_wifi_stop`) und geht in den Zustand *scan* (10.8). Er scannt wie alle den neuen QR-Code.
     - Das Schließen wartet auf das `drain` aus Schritt 3; danach ist das Netz der anderen ohnehin weg, sie gehen nach *scan* bzw. folgen `move qr`.
5. **Fehlschlag ohne Raum:** Bleibt `handover_ok` `HANDOVER_TIMEOUT_MS` lang aus, taut der Gastgeber auf wie in 4.1, nur ohne `check_now`. Hat das Ziel doch noch übernommen, entscheidet der Gastgeber-Wächter: Die `gen` des Ziels ist höher.
6. **Abstammung** (`own:true`): derselbe Ablauf, `how` nach denselben Regeln.

### 10.8 Spiel-WLAN

**Ausfall** (der alte Gastgeber hatte `wlan.ap`):
- **Auslöser:** Das Netz des Gastgebers ist weg (`lan_ok` falsch). Wer per QR beigetreten ist, sieht zusätzlich den `QrWifi`-Zustand „lost“ oder „unavailable“, und `QrJoin.check_lost` gibt die Anfrage frei.
  - Die Frist ist `T_SILENT` ab `host_lost_wall`.
  - Ist das Netz noch da (der Gastgeber ist nur angehalten), gilt der normale WLAN-Ablauf mit `away` – siehe „Übernahme im fremden Spiel-WLAN“ unten.
- **Wer ein neues Spiel-WLAN öffnet:** Ist `ap_seat == host_seat` (der Gastgeber führte das Netz und ist mit ihm weg), ist es Rang 0. Ist `ap_seat != host_seat` (der Gastgeber saß im Spiel-WLAN eines anderen, siehe unten), ist es **der Gastgeber selbst**: Er lebt ja noch und hat den Stand; die Gäste übernehmen nicht, sondern gehen nach *scan* mit seinem Namen. `hosts.ap_name` (Lite) und der Name im Streifen folgen derselben Regel.
- **Nur Rang 0 übernimmt automatisch.** Die übrigen sehen eine Übernahme nicht, weil sie in einem anderen Netz sind; ein Rang 1 eröffnete sonst ein zweites Spiel.
  - Gegenprüfung der Umsetzung: nicht sofort, sondern nach weiteren `T_STEP` mit Countdown. „Netz weg“ kann auch ein Funkloch nur dieses Geräts sein; Neuverbinden und Suche laufen weiter, ein `welcome` beendet das Warten. Bleibt es länger weg, entstehen zwei Spiele (10.17).
- **Reihenfolge bei Rang 0:**
  1. Stand aus der Sicherung.
  2. `QrJoin.wifi_release()` **vor** `resume`, damit `bind_for("host")` nicht am toten Netz hängt.
  3. `HostTable.resume`.
  4. Spiel-WLAN: Der Tisch öffnet `SeatManager` auf „Dazuholen“. Ist die Erlaubnis schon erteilt, öffnet `GameWifiWatch.auto_open()` das Spiel-WLAN ohne Tippen, unabhängig davon, ob das Overlay offen bleibt. **Wiederholung:** Meldet Android `incompatible_mode` oder hängt das Gerät noch im alten Netz (System-WLAN oder Kamera-QR, wo `wifi_release` nichts trennt), versucht es höchstens 3-mal im Abstand von 2 s erneut; erst dann erscheint „Neu öffnen“ mit dem vorhandenen Hinweis. Ohne Erlaubnis erscheint der Knopf „Spiel-WLAN öffnen“ mit dem Erlaubnisdialog.
  5. `rebind` über `GameWifiWatch` (10.2), `wlan.ap_seat = host_seat`, Warteliste an (10.10).
  - Der neue Gastgeber sieht: „Du bist jetzt Gastgeber. Öffne das Spiel-WLAN und lass die anderen den QR-Code scannen.“
- **Übrige App-Gäste:** Zustand *scan*.
  - Streifen „Spiel-WLAN von %s ist weg.“, dazu der Knopf „Neues Spiel-WLAN bei %s – QR-Code scannen“. `%s` ist Rang 0 laut Sicherung.
  - Der Knopf ruft `ct.suspend()` auf (kein Verlassen, die Datei bleibt) und dann `nav.replace(JoinScreen.rejoin(gid))`. `rejoin` öffnet sofort den Scanner; danach läuft der vorhandene Weg: WLAN-QR → `QrWifi` → Suche bzw. Spiel-QR → `join`.
  - `rejoin` tritt dem gefundenen Spiel mit passender `gid` ohne Namensfeld bei. Der Name kommt aus der Sicherung, der Platz über `bk_token` (10.6).
  - Während *scan* sucht der `HostSwitch` weiter. Sind alle im selben Ersatz-WLAN gelandet, folgt der Gast ohne Scan.
  - Von Hand bleibt „Spiel als Gastgeber fortsetzen“, mit der Warnzeile „Nur wenn %s nicht übernimmt – sonst gibt es zwei Spiele.“
- **Browser-Gäste:**
  1. WLAN-QR mit der Kamera, dann Spiel-QR. Das ergibt eine neue Seite mit neuem Ursprung und ohne Token.
  2. Name eingeben, dann stehen sie auf der Warteliste.
  3. Der Gastgeber tippt „Auf den Platz von %s setzen“ (10.10).
- **Der alte Gastgeber kommt zurück** (Hauptmenü, `role:"host"`, `wlan.ap`): Es kommt eine Rückfrage mit zwei Knöpfen, auch bei einer Datei < 5 min, denn er kann nicht sehen, ob jemand übernommen hat:
  - „Spiel-WLAN neu öffnen“: eigener Zweig, `gen` bleibt.
  - „Beim neuen Gastgeber scannen“: `JoinScreen.rejoin`.

**Übernahme im fremden Spiel-WLAN** (Gegenprüfung): Der alte Gastgeber ist nur abwesend oder eingefroren, sein Spiel-WLAN besteht weiter. Dann übernimmt Rang 0 nach dem normalen WLAN-Ablauf (`T_AWAY`) als Teilnehmer in diesem Netz.
- Der neue Schnappschuss behält `ap:true` und `ap_seat` = Platz des alten Gastgebers.
- Kommt der alte Gastgeber zurück, wird er Gast (Wächter 10.11 bzw. Abstammung); sein Handy führt das Netz weiter.
- Fällt das Spiel-WLAN später weg (App des alten Gastgebers geschlossen, er verlässt den Tisch), sieht das der neue Gastgeber über `GameWifiWatch` bzw. `QrWifi` „lost“. Er verhält sich wie Rang 0 oben (eigenes Spiel-WLAN, `ap_seat = host_seat`), seine Gäste gehen nach *scan* mit seinem Namen. Verlässt der alte Gastgeber den Tisch regulär, warnt sein „Tisch verlassen“ zusätzlich: „Dein Spiel-WLAN geht dann zu – alle müssen einen neuen QR-Code scannen.“
- Ohne `ap_seat` (Schnappschuss einer 1.6.1-App) gilt `ap_seat = host_seat`.

**Geplant:** wie 10.7 mit `how:"qr"`. Das Ziel öffnet sein Spiel-WLAN automatisch mit Wiederholung (oben, Schritt 4).

**Fehler in `QrWifi.release`** (`QrWifi.java:176-198`): Nach `onLost` ist `network` schon `null`. Deshalb löst `release()` die Prozessbindung nicht (`n != null && n.equals(bound)`). Der Prozess bleibt an ein verlorenes Netz gebunden, und neue Sockets für Server, Suche und Vermittler scheitern.

Lösung:
- `bind()` merkt sich das gebundene Netz (`boundNetwork`); `onLost` löscht es nicht.
- `release()` löst die Bindung, wenn `getBoundNetworkForProcess()` gleich `boundNetwork` ist oder zu keinem Netz mit Fähigkeiten mehr gehört (`getNetworkCapabilities(bound) == null`).
- `QrJoin.wifi_release()` setzt außerdem `NetAddresses.bound_to` zurück (heute nur bei `"qr_wifi"`), damit die nächste `bind_for` neu bewertet.

**STA/AP-Gleichzeitigkeit:** Ein Gast im fremden Spiel-WLAN, der selbst eines öffnet, verlässt immer zuerst das alte (release).
- Mit Gleichzeitigkeit (`GameWifi`-Feld `concurrency`) wäre das nicht nötig, schadet aber nicht.
- Ohne Gleichzeitigkeit trennt Android beim Öffnen das WLAN oder meldet `incompatible_mode`. Dann erscheinen der vorhandene Hinweis und „Neu öffnen“.
- Wer über die Systemeinstellungen beigetreten ist (Android < 10, `old_android_text`): `release` wirkt nicht. Android wechselt nach dem Verschwinden des Netzes von selbst.

### 10.9 Lite im WLAN

- **Merken:** Lite nimmt `gid` und `gen` **aus `hosts`**, nicht aus `welcome`: Beim Beitritt in der Lobby ist `welcome_extra` leer, und `start` trägt keine gid (`net_session.gd:492`). Der Gastgeber schickt `hosts` an Browser-Gäste nach jedem `welcome` während der Partie, bei `start` und `resume` immer (auch mit leerer Liste), nach jeder Übernahme mit der neuen `gen` und bei jeder Änderung der Liste. Lite merkt sich die letzte Liste samt `ap` und `ap_name`.
- **Reihum-Probe** (`netz.js`, `Verbindung`):
  - Sie beginnt, wenn der Status seit mindestens `LITE_SUCHE_AB` = 20 s „getrennt“ ist und eine Liste vorliegt.
  - Alle 5 s fragt Lite je Eintrag `fetch(url + "info")` ab (Abbruch nach 2 s, `no-store`). `/info` hat `Access-Control-Allow-Origin: *` (`net_server.gd:673`).
  - Treffer: gleiche `gid` und eine `gen` über der bekannten. Dann `verbindung.umziehen(ws-URL)` (neue URL, `versuche = 0`, sofort verbinden) und `hostBasis = url`.
  - Das Token liegt weiter im Speicher des alten Ursprungs und geht im `hello` mit. Der neue Gastgeber kennt es aus `seats`.
  - Overlay: „Gastgeber fehlt – suche den neuen Gastgeber …“.
- **`move`:**
  - `lan`: sofort umziehen, ohne `/info`.
  - `online`: Kasten „Das Spiel läuft jetzt über das Internet weiter.“ mit Knopf „Weiter“; der Knopf führt `location.assign(url + "#t=" + Token + "&n=" + Name)` aus.
  - `qr`: Kasten „Neues Spiel-WLAN bei %s. Verbinde dich mit dem WLAN-Code auf diesem Handy und scanne dann den Spiel-Code.“
- **Online-Eintrag der Liste:** erst nach mindestens `LITE_ONLINE_AB` = 60 s erfolgloser LAN-Probe, als Knopf „Über das Internet weiterspielen“ (dieselbe Navigation wie bei `move online`).
- **Ungeplanter Verlust des Spiel-WLANs** (`hosts.ap`): Nach 20 s „getrennt“ zeigt Lite den Kasten wie bei `move qr` mit `ap_name` („Neues Spiel-WLAN bei %s …“). Die Reihum-Probe läuft trotzdem weiter. „Seite neu laden“ ist dann ausgeblendet, solange `hostBasis` der eigene (tote) Ursprung ist – sonst zeigte der Browser nur eine Fehlerseite, und Lite wäre weg.
- **„Seite neu laden“** (`#verbinde-laden`, `#ende-zurueck`, `app.js:223-224`): Weicht `hostBasis` vom eigenen Ursprung ab, folgt `location.assign(hostBasis + "#t=…&n=…")`; sonst wie bisher `reload()`.
- **Start** (`init`):
  1. `#t=` und `#n=` lesen.
  2. Das Token unter dem passenden Schlüssel speichern (`token` bzw. `token:CODE`, `app.js:69`) und den Namen vorbelegen.
  3. Den Hash mit `history.replaceState` entfernen.
  - Der Knopf zeigt dann „Weiterspielen“. Automatisch beitreten gibt es nicht, weil Ton und Vollbild ohnehin einen Tipp brauchen.
- **Herkunftsprüfung** (`net_server.gd:939`): Die Lite-Seite des alten Gastgebers verbindet sich mit `Origin: http://<alt>:<port>` zum neuen.
  - Neu: `NetServer.set_extra_origins(list)`, unter `_mutex` gesetzt und im Netz-Thread gelesen, und `origin_allowed(origin, host, extra)`.
  - Erlaubt sind nur exakte `http://<IPv4>:<Port>` aus `wlan.past` ∪ (`wlan.addrs` × `wlan.port`) des Schnappschusses.
  - `HostTable.resume` setzt die Liste und schreibt `past` fort; `NetHostSession` reicht sie durch.
- **Dateien vom alten Ursprung:** Töne lädt Lite beim Start (`ton.js`), Kartenbilder prüft `karten.js` vorab. Was noch nicht geladen war, fehlt bis „Seite neu laden“. Das ist niedrig; im Chrome-Test ansehen.
- **Netzregeln von Chrome** (Private Network Access, Local Network Access): Anfragen von einer Seite mit privater Adresse an eine andere private Adresse sind erlaubt. Der Chrome-Test deckt `fetch /info` und den WebSocket über Ursprünge ab.
- **Alte Lite-Fassungen:**
  - Im WLAN gibt es keine. Die Seite kommt vom Gastgeber, und alle Apps einer Partie haben dieselbe Version (`check_hello`). Ein Tab aus einer früheren Sitzung bekommt „reject version“ → „Seite neu laden“.
  - Lite 1.6.1 (online) ignoriert `hosts` und `move` und folgt online wie in 1.6.1.
  - Bleibt doch ein altes Lite hängen, führt der Weg über Spiel-QR → Warteliste → „Auf den Platz von %s setzen“.

### 10.10 „Auf den Platz von %s setzen“ (`seat_assign`) und Warteliste nach Übernahmen

- **`HostTable.seat_assign(waiting_id, seat) -> bool`** geht nur, wenn:
  - die Partie läuft und der Tisch nicht eingefroren ist,
  - `waiting_id` auf der Warteliste steht,
  - `seat` ein entfernter Menschenplatz ist (nicht der Gastgeber, kein Computer), dessen Spieler nicht verbunden ist.
  - Eine Vertretung durch den Computer endet dabei.
- **`NetHostSession.assign_seat(waiting_id, seat_id)`:**
  - Verbindung, `kind`, `address`, `online` und `bk` des Wartenden gehen auf den Platz-Spieler über. Der Eintrag des Wartenden fällt weg.
  - Auf derselben Verbindung folgt ein zweites `welcome` mit id und Token des Platzes, dann `player_rejoined(seat_id)`. Wie bei einer Rückkehr gehen danach `start{seat}` und der Stand hinaus.
  - Das zweite `welcome` trägt `assigned:true`. `NetClient` (`net_client.gd:516-525`) setzt dann weder `readmitted` noch `removed` und übernimmt das neue Token als `_sent_token`. Nötig, weil ein App-Gast mit einem alten Token aus der Token-Datei für dieselbe `ip:port` ein nicht leeres `_sent_token` hat; die frühere Annahme „bei Neuen leer“ stimmt nur für Lite.
  - Lite (`app.js:426`) kommt mit einem zweiten `welcome` zurecht (`_sent_token`-Logik gibt es dort nicht); alte Lite-Fassungen ebenso. Die Tests prüfen beides ausdrücklich.
- **SeatManager:** In der Zeile eines Wartenden steht neben „An den Tisch holen“ und „Ablehnen“ je getrenntem Menschenplatz der Knopf „Auf den Platz von %s setzen“; bei mehreren Plätzen eine Auswahl.
  - Rückfrage: „%s spielt dann mit den Karten von %s weiter.“
  - Knöpfe: „Hinsetzen · Abbrechen“.
- **Warteliste nach einer Übernahme:** `join_open` geht an, solange ein Menschenplatz getrennt ist; danach gilt wieder der vorige Wert. Neue landen so auf der Warteliste statt bei „reject running“. Kommt jemand dazu, sieht der Gastgeber: „%s möchte mitspielen – ☰ → Mitspieler dazuholen.“

### 10.11 Gastgeber-Wächter (zwei Gastgeber im selben Netz)

- **Suche im Gastgeber-Modus:** `NetDiscovery` bekommt `scan_ms` (Standard `HOST_SCAN_MS`).
  - Sie schickt „MMF?“ an den Rundruf und per Unicast an `manual` (Erben-Adressen und `wlan.past`).
  - Antworten wertet sie auf demselben Socket aus und übergeht die eigene `sid`. Heute verwirft `_poll_host` (`net_discovery.gd:130`) alles außer Anfragen.
  - Bei gleicher `gid` kommt das Signal `rival(info)`.
- **Für Tests:** `ports: Array` (Anfragen an mehrere UDP-Ports), weil mehrere Gastgeber auf 127.0.0.1 nicht denselben Port binden können.
- **`HostTable._on_rival(info)`:** Beide Seiten rechnen dieselbe symmetrische Regel aus den Werten ihrer Suchantworten (`conn`, `gen`, `epoch`; die eigenen Werte so, wie die eigene Suchantwort sie gerade meldet). Der andere gewinnt, wenn
  1. sein `conn` (verbundene entfernte Menschen) größer ist, oder
  2. bei gleichem `conn` seine `gen` größer ist, oder
  3. bei gleichem `conn` und gleicher `gen` seine `epoch` (Zeichenvergleich).
  - Grund (Gegenprüfung): „Höhere `gen` gewinnt“ allein verwirft den Zweig, an dem die Mehrheit weitergespielt hat (z. B. Gast-Aussetzer: Rang 0 übernimmt allein, alle anderen spielen beim alten Gastgeber weiter). Verloren gingen alle Züge seit der Abspaltung.
  - **Abtreten erst bei zwei gleichen Ergebnissen hintereinander** (zwei Scans, ≈ 10 s). So führen kurz schwankende `conn` (Gäste ziehen gerade um) nicht dazu, dass beide gleichzeitig abtreten.
  - **Verlierer:**
    1. einfrieren,
    2. `move{how:"lan", addr, port}` des anderen an alle eigenen verbundenen Gäste,
    3. `session.drain(500)`, dann `stepped_down` mit Ziel, Abtreten wie in 10.7, Schritt 4.
  - **Gewinner:** Ist seine `gen` kleiner oder gleich der des Verlierers, setzt er `gen = rival.gen + 1` (neue `epoch`, `parent` = eigener Stand) und verteilt sofort `bk`. Sonst holte die Abstammungsregel (`_check_lineage`, `host_table.gd:854`) den Zweig des Verlierers zurück, sobald dessen Gäste mit ihrer Sicherung ankommen. Ist die eigene `gen` schon größer, holt die Abstammungsregel wie bisher nichts.
    - Gegenprüfung der Umsetzung: Der Gewinner hebt nach der vollen Regel an, **auch mit offenem Raum** (`HostTable.rival_outcome`; Anheben geht vor Abtreten). Sonst trat ein Gewinner mit Raum gegen einen Verlierer ohne Vermittler mit höherer `gen` selbst ab.
    - Der Verlierer tritt erst ab, wenn die `gen` des Gewinners über der eigenen liegt; höchstens `rival_gen_wait` (4) weitere Scans wartet er darauf (verpasste Scans, UDP-Verlust), dann tritt er trotzdem ab.
  - Beide Seiten nehmen `rival.addresses` × `rival.port` in die zusätzlichen Ursprünge (10.9) und in `wlan.past` auf. Sonst lehnte der Gewinner die WebSockets der Lite-Gäste ab, die ihre Seite beim Verlierer geladen haben.
- **Online** heißt es dagegen „nichts tun“ (4.3.6), weil dort der Vermittler schon per 4000 entschieden hat. Im WLAN entscheidet sonst niemand.
- **Gemischt mit Raum:** Ist der eigene Raum `open`, tritt der Wächter nur bei **kleinerer** `gen` ab; bei gleicher `gen` entscheidet der Vermittler (4000). Sonst könnten Wächter und Vermittler verschiedene Sieger wählen. Ist der eigene Raum **nicht** `open` (Vermittler für diese Seite nicht erreichbar, 10.12), gilt die volle Regel oben; sonst liefen bei gleicher `gen` dauerhaft zwei Spiele im LAN.
- **Grenze:** Zwei Gastgeber in verschiedenen Netzen, etwa zwei Spiel-WLANs, sehen sich nicht (10.17).

### 10.12 Gemischte Partien (WLAN + online)

- **Automatische Übernahme** ist jetzt erlaubt: Rangfolge nach 10.3, Prüfung nach 10.4. WLAN-Gäste prüfen LAN und Vermittler, Online-Gäste wie in 1.6.1.
  - **Ein WLAN-Erbe übernimmt:**
    - Er übernimmt auch den Raum (`open_online_existing`, 4012 an die Online-Gäste) und öffnet seinen Server.
    - WLAN-App-Gäste finden ihn per Suche, Lite über `hosts`.
    - **Ohne Vermittler** (Netzfehler, Zeitüberschreitung; nicht 4404 und nicht abgelehntes Token): Die Übernahme gilt fürs LAN sofort (`_finish_take`), statt in `_poll_taking` auf „open“ zu warten und bei „failed“ abzubrechen (`host_switch.gd:470-479`). `open_online_existing` wiederholt sich im Hintergrund (alle 15 s). Die WLAN-Gäste spielen so weiter; die Online-Gäste kommen, sobald der Raum erreichbar ist. 4404 bzw. abgelehntes Token: Raum weg, weiter nur im LAN, später 10.13.
  - **Ein Online-Gast übernimmt** – nur von Hand, solange WLAN-Mitspieler am Tisch sitzen (Gegenprüfung der Umsetzung, 10.3; automatisch nur ohne WLAN-Mitspieler):
    - WLAN-App-Gäste finden im LAN nichts. In *waiting*/*checking* proben sie den Raum (`connect_probe` mit eigenem Token). Antwortet dort ein Gastgeber, folgen sie über den Raum (`_follow_room`).
    - Lite im WLAN bekommt nach 60 s den Knopf „Über das Internet weiterspielen“.
    - Ohne Internet bleiben sie draußen. Die Rückfrage „Spiel als Gastgeber fortsetzen“ warnt: „WLAN-Mitspieler brauchen dann Internet.“
- **Geplante Übergabe:** erlaubt (10.7, `how` `lan` oder `online`).
- **Abstammung in der Einschwingzeit** (gleiche Vorgeneration, höheres `seq`, 4.3.5): nicht an einen Online-Gast, solange WLAN-Mitspieler am Tisch sitzen. Anlass (15.10.2026, `test_takeover_mixed` 0 wackelig, jetzt Fall 4): Der letzte Stand des alten Gastgebers ging nur noch über den Vermittler hinaus (`server.stop()` verwarf ihn für die WLAN-Gäste); der WLAN-Erbe übernahm mit dem älteren Stand, und `own:true` zog die Partie zum Online-Gast. Dieser eine Zug entfällt jetzt. Ein echter jüngerer Zweig (`g' > gen`) holt das Spiel weiterhin zurück.
- **Abtreten des alten Gastgebers:** Auslöser ist das 4000, `handover_ok` oder der Wächter, je nachdem, was zuerst kommt. Vor dem Abtreten geht `move` an die WLAN-Gäste; bei einem 4000 ohne `handover_ok` mit `port = hp`.
- Die Warnzeile „WLAN-Mitspieler kommen dann nicht mit.“ (4.4) entfällt.

### 10.13 Abgelaufener Online-Raum

- **Neuer Raum für die alte Partie:** `HostSwitch` bietet in den Zuständen *expired* (Hauptmenü) und *gone* (Tisch) den Knopf „In neuem Raum fortsetzen“. `saved_offer` und `resume_saved` prüfen dafür mit `resumable(d, now, true)` (10.6), sonst böten sie eine Datei mit einem Raum älter als 24 h gar nicht an.
  1. `HostTable.resume(d, seat, …, new_room := true)` mit `online = {}`, denn der alte Raum gilt nicht mehr. Danach `session.open_online(o.relay)`.
  2. `gen` folgt den Regeln aus 1.1: bei einem Gast `gen + 1`, im eigenen Zweig bleibt sie.
  3. `join_open` geht an, der Tisch öffnet `SeatManager` „Dazuholen“ (Online-QR, „Link teilen“, Raumcode).
- **App-Gäste:** Am Tisch (*gone*) bzw. im Hauptmenü erscheint der Knopf „Mit neuem Code beitreten“. Er führt zum `JoinScreen` (Raumcode, QR oder Link). Dank 10.6 landen sie mit `bk_token` auf ihrem Platz.
- **Browser:** Der Link führt zur Seite beim Vermittler mit leerem `token:NEUCODE`, von dort auf die Warteliste und mit „Auf den Platz von %s setzen“ an den Tisch.
- **Zwei öffnen gleichzeitig einen neuen Raum:** Dann gibt es zwei Räume und keine Automatik; das ist selten. Wer den Link des anderen nimmt, verlässt vorher seinen Tisch. „Tisch verlassen“ beendet den eigenen Raum und löscht die eigene Datei; über die Warteliste kommt er wieder an seinen Platz.

### 10.14 Hauptmenü „Partie fortsetzen“ (Ergänzungen zu 4.4)

- `saved_offer` bietet jetzt auch WLAN-Gast-Dateien an (`role:"guest"`, ohne Raum).
- **WLAN-Datei:**
  1. Zuerst 3 s nach der `gid` suchen: Rundruf, dazu Unicast an `wlan.addrs` und die `addr` der Erben.
  2. Fund mit `gen ≥ Datei-gen`: weiter als Gast (`move_to`), Meldung wie in 4.9.
  3. Kein Fund:
     - `role:"host"`: eigener Zweig auf dem gespeicherten Port wie in 1.6.1; bei `wlan.ap` die Rückfrage aus 10.8.
     - `role:"guest"`: Rückfrage „Spiel als Gastgeber fortsetzen?“ (`gen + 1`).
  4. Scheitert das Eröffnen (Ports belegt), endet der Ablauf in *expired* mit „Das Spiel ließ sich gerade nicht eröffnen. Bitte noch einmal versuchen.“ (Gegenprüfung der Umsetzung; nicht die Meldung zum abgelaufenen Raum).
- **Raum-Datei:** wie 1.6.1; ist der Raum abgelaufen, gilt 10.13.

### 10.15 Oberflächentexte (Deutsch; Englisch über `en_screens.po`/`en_table.po`, Lite über `M.t`)

| Ort | Text |
|---|---|
| Streifen (Gast) | Suche den neuen Gastgeber … |
| Streifen (Spiel-WLAN weg) | Spiel-WLAN von %s ist weg. |
| Knopf (Gast) | Neues Spiel-WLAN bei %s – QR-Code scannen |
| Warnzeile Rückfrage | Nur wenn %s nicht übernimmt – sonst gibt es zwei Spiele. |
| Warnzeile Rückfrage / Auswahldialog | WLAN-Mitspieler brauchen dann Internet. |
| Warnzeile Auswahldialog | Alle müssen danach einen neuen QR-Code scannen. |
| neuer Gastgeber (Spiel-WLAN) | Du bist jetzt Gastgeber. Öffne das Spiel-WLAN und lass die anderen den QR-Code scannen. |
| SeatManager | Auf den Platz von %s setzen |
| Rückfrage | %s spielt dann mit den Karten von %s weiter. |
| Knöpfe | Hinsetzen · Abbrechen |
| Gastgeber, Hinweis | %s möchte mitspielen – ☰ → Mitspieler dazuholen. |
| an die eigenen Gäste (Wächter) | %s führt dieses Spiel schon – ihr spielt dort weiter. |
| Hauptmenü, Rückfrage Spiel-WLAN | Spiel-WLAN neu öffnen · Beim neuen Gastgeber scannen |
| Raum abgelaufen (Knöpfe) | In neuem Raum fortsetzen · Mit neuem Code beitreten |
| neuer Raum, Gastgeber | Neuer Raum %s. Schick den anderen den Link – sie kommen damit auf ihre Plätze. |
| Lite, Overlay | Gastgeber fehlt – suche den neuen Gastgeber … |
| Lite, Kasten | Das Spiel läuft jetzt über das Internet weiter. · Weiter |
| Lite, Kasten | Neues Spiel-WLAN bei %s. Verbinde dich mit dem WLAN-Code auf diesem Handy und scanne dann den Spiel-Code. |
| Lite, Knopf | Über das Internet weiterspielen |
| Auswahldialog, ausgegraut (qr) | Kann kein Spiel-WLAN öffnen. |
| Auswahldialog, Zeile (qr) | Muss das Spiel-WLAN erlauben. |
| „Tisch verlassen“, Warnzeile (fremdes Spiel-WLAN) | Dein Spiel-WLAN geht dann zu – alle müssen einen neuen QR-Code scannen. |

Der Text „Geht in dieser Version nur, wenn alle online mitspielen.“ entfällt; er bleibt in der .po und schadet dort nicht.

### 10.16 Testplan

**Automatisch.** Die Tests folgen dem Muster von `test_takeover_online.gd`:
- `speed = 0`, einspritzbare Uhr `wall_ms`, kurze Fristen als Eigenschaften.
- Suche mit `use_broadcast = false` plus `probe_local`, `manual` bzw. `ports`.
- Freie Ports laut Suche: 24901–24911, 24917–24929, 24987–24999.

Neue und erweiterte Tests:
- `test_discovery_gid.gd`:
  - Die Suchantwort trägt `gid`, `gen`, `epoch` und `conn`; `parse_reply` lehnt kaputte Felder ab.
  - Der Gastgeber-Scan meldet `rival` nur bei gleicher `gid` und nie für die eigene `sid`.
  - `ports` fragt mehrere UDP-Ports ab; Abfrageabstand und Verfall laufen über die eingespritzte Uhr `now_ms`.
- `test_origin_past.gd`:
  - `origin_allowed` mit `extra` lässt nur exakte `http://ip:port` zu; `https`, Muster und fremde Ports werden abgelehnt.
  - Die Liste wirkt auch im Netz-Thread (threaded).
- `test_server_drain.gd` (neu, `threaded = true`):
  - `send_to` + `drain(500)` + `stop()`: Die Nachricht (auch größer als ein Socket-Puffer, z. B. ein `bk`) kommt vor dem Close-Rahmen beim Gast an.
  - Gegenprobe ohne `drain`: darf verloren gehen (dokumentiert das Verhalten, kein Fehlschlag erzwungen).
- `test_session_assign.gd`:
  - `assign_seat` schickt ein zweites `welcome` mit Platz-Token und `assigned:true`, dann `start` und den Stand.
  - Ein App-Gast mit altem Token aus der Token-Datei für dieselbe `ip:port` wird danach **nicht** `removed`/`readmitted`.
  - Abgelehnt wird bei verbundenem Platz, beim Gastgeber und bei Bots.
  - `bk_token` gilt nur mit passendem `bk_gid`.
- `test_client_move.gd`:
  - `move_to` behält Sicherung, `head`/`head_gid` und Token; `backup_current()` bleibt wahr.
  - Nach `move_to` geht der `HostSwitch` (Signal `moved`) nach *watch* mit frischen Zählern: kein sofortiges *missing*, und ein `welcome` des neuen Gastgebers beendet *missing*.
  - `hello` trägt bei jeder Adresse `hp`, `bk`, `bk_token`, `bk_gid` und `ap`.
  - `host_lost_wall` gilt ab dem ersten gescheiterten Neuversuch.
  - `NetClient.drain`: `handover_ok` über einen **echten** Socket kommt an, obwohl direkt danach `suspend()` folgt.
- `test_handover_wlan.gd` (Gastgeber, 2 App-Gäste, 1 Web-Gast, 1 Bot, alles im WLAN, Server mit Thread):
  - Geplant `lan`: `handover_ok` kommt vor dem Abtreten, `move` geht an alle und kommt vor dem Schließen an (`drain`). Alle sitzen auf ihren Plätzen, es gibt kein `bye`, und die Partie läuft bis zum Rundenende.
  - `qr` mit `QrJoin.wifi_stub`: Reihenfolge `handover_ok` → release → Server; `move how:"qr"`. Ziel ohne `ap.ok` ist bei `qr` ausgegraut. `auto_open` wiederholt bei `incompatible_mode` 3-mal (eingespritzte Zustandsquelle).
  - Ohne `handover_ok` vom Ziel taut der Gastgeber nach der Frist auf; `gen` bleibt unverändert.
  - `resume` ohne Raum setzt `link` des alten Gastgebers auf „wlan“.
- `test_takeover_wlan.gd`:
  - Ausfall zweimal: mit geschlossenem Server (Verbindung verweigert) und still (`NetServer.mute_ws` für alle Verbindungen).
  - Rang 0 übernimmt nach `T_SILENT`; Rang 1 findet ihn per Suche und folgt.
  - Keine Automatik, wenn die Sicherung nicht aktuell ist. Bei `away` passiert vor `T_AWAY` nichts. Ist `lan_ok` falsch (eingespritzt), übernimmt niemand.
  - Spiel-WLAN (`wlan.ap`): Nur Rang 0 übernimmt, die anderen gehen in den Zustand *scan*. Rangfolge: Geräte mit `ap.ok` zuerst.
  - Übernahme im fremden Spiel-WLAN: Der neue Schnappschuss behält `ap_seat` des alten Gastgebers; fällt dessen Netz weg (eingespritzt), öffnet der neue Gastgeber ein eigenes, seine Gäste gehen nach *scan* mit seinem Namen und übernehmen nicht.
  - Der alte Gastgeber setzt seinen eigenen Zweig fort. Der Wächter lässt ihn abtreten, seine Gäste ziehen um.
  - **Mehrheit gewinnt:** Rang 0 übernimmt allein (Gast-Aussetzer), die übrigen spielen beim alten Gastgeber weiter. Beim Wiedersehen tritt Rang 0 ab (kleineres `conn`), der alte Gastgeber hebt `gen` über die des Rang 0, und die Abstammungsregel holt den kleinen Zweig nicht zurück. Die Züge der Mehrheit bleiben erhalten.
  - Gleiches `conn`, gleiche `gen`, verschiedene `epoch`: Genau einer tritt ab (nach zwei gleichen Scans), kein Hin und Her.
  - Herkunft: Ein Lite-Gast, der seine Seite beim Verlierer geladen hat, verbindet sich danach beim Gewinner.
- `test_takeover_mixed.gd` (`NetRelayDouble` + WLAN):
  - Ein WLAN-Erbe übernimmt Raum und LAN. Der Online-Gast folgt per 4012, der WLAN-Gast per Suche.
  - **WLAN-Erbe ohne Vermittler** (Nachbau antwortet nicht): Die Übernahme gilt fürs LAN, der WLAN-Gast folgt; nachdem der Nachbau wieder antwortet, ist der Raum übernommen und der Online-Gast folgt per 4012.
  - Übernimmt ein Online-Gast (von Hand, solange WLAN-Mitspieler am Tisch sitzen – keine Online-Erben), folgt der WLAN-App-Gast über den Raum.
  - Geplante Übergabe an ein Online-Ziel: `move how:"online"` geht an die WLAN-Gäste. Bei geschlossenem Raum ist das Online-Ziel ausgegraut.
  - Bei gleicher `gen` und offenem Raum tritt der Wächter nicht ab; der Vermittler entscheidet. Ist der eigene Raum nicht `open`, gilt die volle Regel (genau einer tritt ab).
- `test_resume_new_room.gd`:
  - Raum abgelaufen (4404 vom Nachbau) → „In neuem Raum fortsetzen“; ebenso mit einer Datei, deren `created_unix` älter als 24 h ist (`resumable(…, true)`).
  - Ein Gast tritt per neuem Code bei und landet mit `bk_token` auf seinem Platz.
  - Das Hauptmenü sucht bei einer WLAN-Datei zuerst nach der `gid`.
- `test_app_qr_join.gd` (Erweiterung):
  - `wifi_release` nach „lost“ setzt die Bindung zurück.
  - Eine Spiel-URL mit `?g=` wird angenommen (Lite ignoriert den Parameter).
- `test_game_wifi_watch.gd` (neu, eingespritzte Zustandsquelle und Uhr, kein Server):
  - Spiel-WLAN geht auf, während kein Overlay offen ist (bzw. das Overlay sofort geschlossen wurde): `rebind` und `refresh_addrs` laufen trotzdem, `wlan.addrs`/`past` und `hosts` sind aktuell.
- `test_ui_handover_wlan.gd` und `_shot`: nur mit Doubles, **ohne** Server und ohne Suche auf UDP 24692, weil `^test_ui_` in die parallele Spur von `build.ps1` fällt (eigenes user://, keine festen Ports). Braucht ein Teil doch Netz, heißt er `test_screens_handover_wlan.gd`. Die Kontrollbilder in Tag/Nacht, im großen Modus und bei Schrift „Sehr groß“ zeigen:
  - den Streifen *scan* mit Knopf,
  - `SeatManager` mit „Auf den Platz von …“,
  - den Auswahldialog mit Warnzeilen,
  - die Rückfrage im Hauptmenü zum Spiel-WLAN,
  - die Anzeige bei abgelaufenem Raum.
- **Lite** (`web_takeover.gd`, Chrome headless, wie `Invoke-WebTakeoverTest`):
  - W1: Hanna stirbt, Anna übernimmt auf einem anderen Port. Lite findet sie über `hosts` und `/info`, verbindet sich mit fremdem Ursprung (Herkunftsliste) und spielt weiter.
  - W2: geplante Übergabe von Anna an Ben (`move lan`).
  - W3: „Seite neu laden“ führt per Navigation mit `#t=` zum neuen Ursprung; Lite sitzt wieder auf seinem Platz.
  - W4: Lite tritt in der Lobby bei (leeres `welcome_extra`), die Partie startet; Lite kennt `gid`/`gen` aus `hosts` und findet nach Hannas Ausfall Anna.
  - W5: `hosts.ap` und Hanna stirbt: Nach 20 s erscheint der Kasten „Neues Spiel-WLAN bei %s …“, „Seite neu laden“ ist ausgeblendet.
  - Gegenprobe ohne Herkunftsliste: W1 scheitert.
- `test_i18n` bleibt streng grün.

**Gerätetest S21/S10, gesperrt** (Testschalter `MauMauFlipTestLock`):

*Grenzen:*
- Gesperrt nicht bedienbar: der Systemdialog „Mit Gerät verbinden?“ (QrWifi), der Erlaubnisdialog des Spiel-WLANs, der QR-Scanner und Chrome/Lite.
- Ein gesperrtes S10 holt in einem Netz ohne Internet den Sperrbildschirm nach vorn. Dann über `logcat` prüfen statt mit `screencap`.

*Ersatz:*
- Netzwechsel per `adb shell cmd wifi connect-network <ssid> wpa2 <passwort>`.
- Die Erlaubnis für das Spiel-WLAN vorab per `adb shell pm grant de.maumauflip.game …` erteilen, nur nach Zustimmung (Nutzerfrage):
  - S21 (Android 15): `android.permission.NEARBY_WIFI_DEVICES`
  - S10 (Android 12): `ACCESS_FINE_LOCATION` und `ACCESS_COARSE_LOCATION`
- SSID und Passwort des Spiel-WLANs per `screencap` vom Gastgeber ablesen.

*Abläufe:*
1. **Heim-WLAN:** S21 ist Gastgeber, S10 App-Gast, dazu ein Bot.
   - `am force-stop` am S21: S10 übernimmt nach ≈ 40–55 s (`logcat`).
   - S21 per `am start` → „Partie fortsetzen“: Die Suche findet S10, S21 wird Gast.
   - Geplante Übergabe S10 → S21 per `input tap`.
2. **Spiel-WLAN:** S21 öffnet ein Spiel-WLAN, S10 tritt per `cmd wifi connect-network` bei und meldet sich über die Suche an.
   - `force-stop` am S21: S10 (Rang 0) übernimmt und öffnet sein eigenes Spiel-WLAN (`screencap`/`logcat`).
   - S21 per `am start`: Es kommt die Rückfrage. „Beim neuen Gastgeber scannen“ ist gesperrt nicht bedienbar. Ersatz: S21 per `cmd wifi connect-network` ins Spiel-WLAN des S10; über die Suche (Zustand *scan* sucht weiter) landet S21 auf seinem Platz.
   - Geplante Übergabe `qr` von S10 an S21 entsprechend.
3. **Gemischt:** S21 ist Gastgeber online und im WLAN, S10 im WLAN. `force-stop` am S21: S10 übernimmt Raum und LAN.
4. **Wiederherstellen:**
   - Spiel-WLAN-Einträge mit `cmd wifi forget-network` entfernen.
   - Beide Handys wieder ins normale WLAN.
   - Testschalter auf `INFO`.

*Erfolgskriterien:*
- dieselben Hände wie vorher (Bildschirmfoto bzw. Log der Handgrößen),
- kein doppelter Gastgeber im Log,
- kein „Raum beendet“,
- die `QrWifi`-Bindung ist nach „lost“ gelöst (`dumpsys connectivity` bzw. Log von `NetAddresses`).

Lite im Browser prüft der Nutzer; das iPhone bleibt offen.

### 10.17 Risiken und offene Punkte

- **Kein Schiedsrichter im WLAN:** Hat ein Gast einen kurzen WLAN-Aussetzer, ist sein Netz noch da, aber der Gastgeber 40 s nicht erreichbar. Dann übernimmt Rang 0 womöglich, obwohl der Gastgeber lebt. Der Gastgeber-Wächter löst das, sobald sich beide wieder sehen: Es gewinnt der Zweig mit mehr verbundenen Menschen (dann `gen`, dann `epoch`, 10.11). Verloren gehen die Züge des kleineren Zweigs seit der Abspaltung – meist nur die des allein übernommenen Rang 0. Bei Gleichstand der Menschen verliert der Zweig mit kleinerer `gen` alle Züge seit der Abspaltung; das ist selten (beide Gruppen gleich groß und getrennt).
- **Beide treten gleichzeitig ab** (Wächter sieht verschiedene `conn`): Durch „zwei gleiche Ergebnisse hintereinander“ unwahrscheinlich. Passiert es doch, sind alle Gast mit Sicherung, und Rang 0 übernimmt nach `T_SILENT` (≈ 40–50 s).
- **`drain` mit Frist:** Ist der Socket eines Gastes voll (schwaches WLAN), reicht 500 ms nicht immer. Dieser Gast fällt auf die Suche zurück (App) bzw. auf die Reihum-Probe (Lite); das kostet ≈ 40 s, aber keinen Stand.
- **Zwei Spiel-WLANs sehen sich nie:** Ist der Gastgeber außer Reichweite, während Rang 0 übernimmt, entstehen zwei Spiele. Die Menschen sehen das und scannen den richtigen QR-Code. Deshalb übernimmt im Spiel-WLAN nur Rang 0 automatisch.
- **Router filtern Rundrufe** (Hotel, Geräte-Isolierung): Unicast an die bekannten Adressen hilft nur ohne Isolierung. Mit Isolierung geht ohnehin nur das Spiel-WLAN.
- **Port des Erben weicht von `hp` ab** (24690 belegt): Lite findet ihn über `hosts` nicht. Dann bleibt der Weg Spiel-QR → Warteliste → „Auf den Platz …“.
- **Lite vom toten Ursprung:** Noch nicht geladene Dateien fehlen bis „Seite neu laden“. Safari auf dem iPhone mit WebSocket zu einem fremden privaten Ursprung ist ungetestet.
- **Netzregeln von Chrome** (Local Network Access) können sich ändern; der Chrome-Test im Bau zeigt es.
- **`bk_token` an fremde Gastgeber** (10.6): Das Token geht auch an den Gastgeber einer anderen Partie hinaus. Es nützt nur beim echten Gastgeber dieser Partie, und alle App-Gäste halten ohnehin alle Tokens (5.).
- **Datenmenge:** im WLAN unverändert (`bk` je Änderung), keine Kosten beim Vermittler.
- **STA/AP:** Geräte ohne Gleichzeitigkeit trennen beim Öffnen des Spiel-WLANs das normale WLAN. Das ist im Ablauf gewollt, weil der neue Gastgeber das alte Netz ohnehin verlässt. Android kann aber `incompatible_mode` melden; der Gerätetest prüft S21 und S10.
- **Erlaubnisdialog beim neuen Gastgeber:** Ohne vorher erteilte Erlaubnis braucht das Spiel-WLAN einen Tipp. Übernimmt ein Handy automatisch, das gerade niemand ansieht, öffnet es kein Spiel-WLAN, bis jemand tippt. Gemildert durch die Rangfolge (`ap.perm` zuerst, 10.3).
- **Kein fähiges Gerät** (alle ohne `ap.ok`, z. B. nur 1.6.1-Apps oder sehr alte Android): Rang 0 übernimmt trotzdem, „Neu öffnen“ scheitert; dann bleibt nur „Spiel als Gastgeber fortsetzen“ im normalen WLAN bzw. online.
- **Erbe im Hintergrund:** Ist die App nicht vorn, pausiert Android sie; Rang 0 übernimmt erst, wenn sie wieder vorn ist. Die anderen warten nach Rang (wie online).

**Aus der Gegenprüfung (13.10.2026):** alle 15 Befunde übernommen. Abwägungen:
- Spiel-WLAN mit nur abwesendem Gastgeber: Statt „keine automatische Übernahme bei `wlan.ap` und `lan_ok`“ gilt die Variante `ap_seat` (10.2, 10.8). Grund: Die Sperre allein hilft nicht bei der Übernahme von Hand (dieselbe Strandungsgefahr), und ein Gastgeber in einem langen Anruf hielte sonst alle fest.
- Lite und `gid`: `hosts` geht immer hinaus, `start` bekommt keine `gid` (ein Weg genügt, `hosts` braucht Lite ohnehin).
- `move_to` und Zähler: Signal `moved` statt Umbau des Zählmodells im `HostSwitch`.
- Wächter: Regel „mehr verbundene Menschen“ übernommen, ergänzt um das Anheben der `gen` beim Gewinner (sonst kehrte die Abstammungsregel die Entscheidung um) und um „zwei gleiche Scans“.
- Neu-Binden: eigener Node `GameWifiWatch` am `TableScreen` statt in `HostTable`, weil `HostTable` (game/) nicht von `NetAndroid` (app/) abhängen soll; einspritzbar für Tests.

**Gegenprüfung der Umsetzung (13.10.2026):** 10 Befunde, 10 behoben (Tests in Klammern):
- `hello.ap` kam in der App nie aus `NetAndroid` (`NetClient.ap_info_default` blieb leer); damit war jede geplante Übergabe im Spiel-WLAN ausgegraut. `App._init` ruft jetzt `NetAndroid.install_net_hooks()` (`test_client_move` 2).
- Wächter: Gewinner hebt auch mit offenem Raum an; der Verlierer wartet auf die höhere `gen` des Gewinners, höchstens `rival_gen_wait` Scans (`test_handover_wlan` 5, `test_takeover_wlan` 9/10).
- `how` übersteht `clean_backup_message`; der alte Gastgeber folgt `handover_ok` (`test_net_protocol`, `test_handover_wlan` 3c).
- Online-Ziel bleibt `online`, auch bei eigenem Spiel-WLAN; QR-Warnzeile nur für `qr`-Ziele (`test_takeover_mixed` 3).
- Keine Online-Erben, solange WLAN-Mitspieler am Tisch sitzen (`test_takeover_online` 8, `test_takeover_mixed` 2).
- Hauptmenü, WLAN-Datei, Ports belegt: eigene Meldung in *expired* (`test_resume_new_room` 2b).
- Nach einer Übernahme mit Spiel-WLAN nur ein `auto_open`: Anfrage vor `swapped`, `GameWifiWatch.auto_open` stößt während eines laufenden Versuchs nichts neu an (`test_game_wifi_watch`).
- Spiel-WLAN weg: Rang 0 übernimmt erst nach weiteren `T_STEP` mit Countdown (`test_takeover_wlan` 5).
- Lite: `webclient/test/lite_umzug.html` läuft im Bau (`Invoke-WebMoveTest`, Chrome headless, virtuelle Zeit); `web_takeover.gd` prüft W4, W1 (fremder Ursprung über `hosts` und `/info`, Herkunftsliste; Gegenprobe `OHNE_HERKUNFT=1` scheitert) und W3 (`#t=` auf dem neuen Ursprung) über die eigene LAN-Adresse des PCs. W2 (`move lan`) und W5 (Kasten bei `hosts.ap`) deckt `lite_umzug.html` mit Schein-Gastgeber ab.
- Gerätetest 1.6.2, Runde 1 (`docs/geraetetest/1.6.2/BERICHT.md`, Abschnitt „Behebung“): `wlan.ap` kommt vom `GameWifiWatch` (`HostTable.hotspot_check`), nicht von `binding() == "hotspot"` – bis Android 15 bleibt die Bindung mit Spiel-WLAN und WLAN "" (F1, `test_wlan_fixes`). `lan_ok` bei Spiel-WLAN des Gastgebers über die eigene Adresse darin (`HostSwitch.lan_reach`); Beitritt zu Adressen in Spiel-WLAN und WLAN zugleich wechselt das Netz je Versuch, jeder Neuversuch bindet neu (F2, F3); Gast-Tisch ohne Stand nach 20 s mit „Zum Hauptmenü“ (`test_ui_wlan_stuck`); Wächter-Prüfung nach der Rückkehr des Gastgebers (B1); „Gastgeber kurz weg“ im WLAN (B2).
