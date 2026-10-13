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
  - `HostTable.leave()` → `session.stop("Der Gastgeber hat das Spiel beendet.", true)`
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

**Beta 1.6.2: WLAN und Spiel-WLAN.**
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
