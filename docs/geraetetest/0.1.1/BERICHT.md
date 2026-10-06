# Gerätetest Beta 0.1.1

05.10.2026, 21:00–22:08. Geprüft wurde `builds/MauMauFlip-0.1.1.apk` (Code 1001, SHA-256 `2b267a03…5c1152`), installiert mit `adb install -r`. Vor dem Test wurden die App-Daten auf beiden Geräten mit `pm clear` gelöscht, damit jeder Test frisch beginnt.

| Gerät | Android | Bildschirm | WLAN-IP |
|---|---|---|---|
| S21 (SM-G991B) | 15 | 2400×1080 | 192.168.178.8 |
| S10 (SM-G973F) | 12 | 2280×1080 (Override) | 192.168.178.9 |

Beide Geräte waren stummgeschaltet. Die Bedienung lief über `adb shell input` anhand von Bildschirmfotos. Die Bilder liegen in diesem Ordner als halbe Auflösung (JPEG). Den Code habe ich nicht geändert.

## Gesamturteil

**Veröffentlichungsreif: nein.**

Das WLAN-Spiel ist mit der App als Gastgeber nicht spielbar: Sobald der Gastgeber auf „Start“ tippt, beendet die App ihren eigenen Server (H1). Damit fällt eine Kernanforderung der Beta weg: Netzwerk, Browser-Gäste und APK-Weitergabe im Spiel.

Daneben schließt die Zurück-Taste aus Unterseiten die ganze App, und im Spiel erscheint keine Rückfrage (M1). In Einstellungen und Regeln lässt sich nicht per Wischen blättern (M2).

Übungsspiel, Weitergeben, Einstellungen, Updater und Teilen funktionieren. Im Log gab es keine Abstürze und keine Skriptfehler.

## Mängel

| Nr. | Schwere | Mangel |
|---|---|---|
| H1 | **hoch** | WLAN-Spiel startet nicht: Der Gastgeber-Server geht beim Start aus, der Tisch bleibt leer, alle Gäste verlieren die Verbindung |
| M1 | mittel | Zurück-Taste wird doppelt ausgeführt: keine Rückfrage im Spiel, die App schließt sich aus Regeln/Einstellungen, in der Lobby erscheinen zwei Dialoge |
| M2 | mittel | Kein Bildlauf per Wischen in Einstellungen und Regeln, nur über den schmalen Scrollbalken |
| M3 | mittel | Etwa 40 fps mit ungleichmäßigem Takt und etwa 90 % CPU (ein Kern) auch im Ruhezustand am Tisch |
| N1 | niedrig | App-Gast: Der Knopf „Bereit“ in der Lobby ist nicht sichtbar (unter dem Regeltext abgeschnitten) |
| N2 | niedrig | Gastgeber-Lobby: Ab 3 Spielern ist nur ein Teil der Liste sichtbar; der Rest geht nur über den Scrollbalken |

### H1 – WLAN-Spiel startet nicht (hoch)

- **Beobachtung:** Ich habe dreimal reproduziert:
  1. mit Browser-Gast (Chrome headless am PC) und Computergegner;
  2. nur mit Computergegner;
  3. mit S10-App-Gast plus Chrome-Gast auf dem S10.

  Jedes Mal wechselt der Gastgeber nach „Start“ auf einen leeren Tisch: „Stapel · 0“, keine Hand, keine Gegner, kein Hinweis. `curl http://192.168.178.8:24690/info` meldet danach `Connection refused`. Der Browser-Gast zeigt dauerhaft „Verbinde neu … Dein Platz bleibt frei.“ Der Selbsttest im PC-Chrome endet mit „Zeitüberschreitung: Tisch“.
- **Belege:** `54a_s21_lobby_mit_browsergast.jpg` (vor dem Start), `54b_s21_netz_tisch.jpg`, `56d_s21_start_nur_ki.jpg`, `80a_s21_netz_start_leer.jpg`, `80b_s10_chrome_nach_start.jpg`.
- **Ursache (Code gelesen):**
  1. `host_lobby.gd:242` ruft `nav.replace(TableScreen.create(host, …))` auf.
  2. `table_screen.gd:114–117` hängt die Quelle mit `source.reparent(self)` um. Beim Umhängen löst Godot `NOTIFICATION_EXIT_TREE` für den ganzen Teilbaum aus.
  3. Dadurch läuft `NetHostSession._exit_tree()` (`net_session.gd:136`) und ruft `stop()` auf: Der Server schließt, `players.clear()`; ebenso `NetServer._exit_tree()` (`net_server.gd:251`).
  4. Danach scheitert `HostTable.start()` (`host_table.gd:124`) an „mindestens zwei Spieler“.

  Dasselbe Muster gilt für App-Gäste: `join_screen.gd:269` hängt `ClientTable` mit dem Kind `NetClient` (`client_table.gd:47`) um, und `NetClient._exit_tree()` (`net_client.gd:98`) ruft `close()` auf. Am Gerät ließ sich das nicht mehr prüfen, weil der Gastgeber vorher scheitert. Übungsspiel und Weitergeben sind nicht betroffen, weil `LocalTable` noch keinen Elternknoten hat (`add_child` statt `reparent`).
- **Warum die Tests das nicht finden:** `test_game_net` nutzt `HostTable` ohne den Wechsel von der Lobby zum Tisch.
- **Vorschlag:**
  - Die Quelle nicht umhängen; zum Beispiel kann sie bis zum Spielende unter einem dauerhaften Knoten bleiben.
  - Oder `stop()`/`close()` nur beim echten Freigeben ausführen (`NOTIFICATION_PREDELETE`), nicht in `_exit_tree`.
  - Dazu einen UI-Test: Lobby → Start → Server läuft noch, Spieler sind vorhanden.

### M1 – Zurück-Taste wird doppelt ausgeführt (mittel)

- **Beobachtung:** Jeder Druck auf die Android-Zurück-Taste löst zwei Zurück-Schritte aus:
  - **Regeln:** Ein Druck schließt die App statt zum Hauptmenü zu gehen (`81b_s21_regeln.jpg` → `81c_s21_zurueck_aus_regeln.jpg`).
  - **Einstellungen:** Ebenso (`64a_s21_zurueck_aus_einstellungen.jpg`).
  - **Im Spiel:** Ein Druck zeigt keine Rückfrage; der Dialog geht auf und sofort wieder zu (`40a_s21_zurueck_im_spiel.jpg`, `83b_s21_zurueck_im_spiel_einmal.jpg`).
  - **Offene Rückfrage:** Ein Druck schließt sie und öffnet sie neu (`40d_s21_zurueck_bei_rueckfrage.jpg`).
  - **Offene Großansicht:** Ein Druck schließt sie und öffnet zusätzlich „Partie verlassen?“ (`40f_s21_zurueck_bei_grossansicht.jpg`).
  - **Lobby mit Gästen:** Zwei „Lobby schließen?“-Dialoge liegen übereinander. Nach einmal „Bleiben“ steht der zweite noch da (`85b_s21_lobby_zurueck.jpg`, `85c_s21_lobby_bleiben_einmal.jpg`).

  Der Zurück-Pfeil auf dem Bildschirm funktioniert richtig (`40c_s21_zurueckknopf_im_spiel.jpg`). Das Teilen-Menü schließt mit Zurück korrekt (`63b`).
- **Ursache:** `screen_nav.gd:166–175` ruft `go_back()` sowohl bei `NOTIFICATION_WM_GO_BACK_REQUEST` als auch bei `KEY_BACK` in `_unhandled_input` auf. Godot liefert auf Android beides für einen Tastendruck.
- **Vorschlag:** Nur einen der beiden Wege nutzen, oder eine Sperre setzen, sodass höchstens ein `go_back` pro Frame bzw. pro 150 ms läuft.

### M2 – Kein Wisch-Bildlauf in Einstellungen und Regeln (mittel)

- **Beobachtung:** Senkrechtes Wischen über den Inhalt bewegt nichts, weder in Einstellungen (linke und rechte Spalte) noch in den Regeln. Nur das Ziehen am schmalen Scrollbalken am rechten Rand blättert. Dadurch sind Spieltöne, Vibration, Effekte, Info und fast die ganze Regelübersicht schwer zu erreichen.
- **Belege:** `60c_s21_einstellungen_unten.jpg` (nach dem Wischen unverändert), `60d_s21_einstellungen_nach_scrollbalken.jpg` (nach dem Ziehen am Balken), `82a_s21_regeln_wischen.jpg`.
- **Vermutete Ursache:** `ScreenKit.card()` (`screen_kit.gd:105`) ist ein `PanelContainer` mit Standard-`mouse_filter = STOP`. Er liegt im `ScreenKit.scroller()` (`screen_kit.gd:235`) und fängt den Druck ab, bevor der `ScrollContainer` die Ziehgeste bekommt. Betroffen sind `settings_screen.gd:20/127` und `rules_screen.gd:44–60`; vermutlich auch `pass_setup.gd` und `join_screen.gd`.
- **Vorschlag:** Für Karten im Bildlauf `MOUSE_FILTER_PASS` setzen.

### M3 – Bildrate und CPU-Last am Tisch (mittel)

- **Beobachtung (S21, Übungsspiel):**
  - **Beim Wischen der Hand:** SurfaceFlinger-Messung mit 111 Bildern, im Mittel 24 ms, höchstens 34 ms; die Bildabstände wechseln zwischen 16,7 und 25 ms.
  - **Ruhezustand ohne Animation:** 38 Bilder pro Sekunde.
  - **CPU:** Die App braucht dauerhaft etwa 90 % eines Kerns (`dumpsys cpuinfo` 89 %, `top` 92,5 %).

  Beim Wischen sieht man leichtes Ruckeln. Bei langen Partien ist mit spürbarem Akkuverbrauch und Wärme zu rechnen.
- **Vermutete Ursache:** Es wird dauerhaft neu gezeichnet: `_process` in `table_background`, `direction_ring`, `joker_rays`, `hand_view`, `mau_button`, `opponent_seat`, `table_view` u. a., dazu der Hintergrund-Shader. In `project.godot` ist weder `low_processor_mode` noch eine Bildratenbegrenzung gesetzt.
- **Vorschlag:** Neuzeichnen nur bei Änderungen, `OS.low_processor_usage_mode` außerhalb von Animationen, oder `Engine.max_fps = 60`.

### N1 – „Bereit“ für App-Gäste nicht sichtbar (niedrig)

- **Beobachtung:** In der Lobby des App-Gasts füllt der Regeltext die rechte Spalte. Der Knopf „Bereit“ liegt darunter und ist nicht erreichbar; die Spalte blättert nicht (`72c_s10_app_lobby.jpg`, `76a_s10_lobby_beigetreten.jpg`). Der Gastgeber kann trotzdem starten. Er sieht den App-Gast aber nie als „bereit“.
- **Ursache:** In `join_screen.gd:71–87` hat die rechte Spalte keinen Bildlauf, und der Regeltext der Voreinstellung „Offiziell“ ist lang.

### N2 – Spielerliste in der Gastgeber-Lobby (niedrig)

- **Beobachtung:** Ab 3 Spielern ist nur ein Teil sichtbar; der Rest erscheint nur über den Scrollbalken (`78d_s21_lobby_app_und_browser.jpg`, `79a`). Wahrscheinlich gilt dieselbe Wischursache wie bei M2.
- **Vermerk (06.10.2026, behoben, am Gerät noch zu prüfen):**
  - Die Liste blättert per Wischen (Bildlauf aus M2, `ScreenKit.TouchScroll`).
  - Die Lobby ist neu aufgeteilt:
    - Spielerzahl und Computergegner − / + stehen in der Kopfzeile.
    - Die Regeln sind eine Zeile unter der Liste (Knopf „Regeln“ öffnet den Editor samt Voreinstellungen).
    - Die Zeilen sind 72 px hoch.
  - Bei 1600 × 720 (S21 quer) sind damit 5 Spieler ganz sichtbar, vorher 2. Ab 6 Spielern blättert die Liste. Nach „+“ oder einem Pfeil rollt sie zum betroffenen Spieler.
  - Gast-Lobby bei 1600 × 720: 5 Spieler, Regelkopf und „Bereit“ sind ganz sichtbar.
  - Prüfung: `game/tests/test_screens_rules.gd` (Lage aller Zeilen) und `test_screens_device_fixes.gd` (Wischen). Kontrollbild: `docs/module/F2_lobby_5_spieler.png`.

## Ergebnis je Punkt

### 1. Installation und Start – bestanden

- Installation auf beiden Geräten: „Success“.
- Start mit `monkey`; Startbild und Hauptmenü sind auf beiden Seitenverhältnissen sauber (`01_*`, `02_*`).
- Log beim Start:
  - „Mau-Mau Flip 0.1.1 (Android)“
  - Netzinfo
  - eigene APK mit SHA-256 wie im Build
  - „Updater: Noch kein passendes Release veröffentlicht. (Kanal Beta)“

### 2. Übungsspiel gegen 3 Computergegner (S21) – bestanden, mit M3

Etwa 7 Runden gespielt, teils von Hand, teils mit einer Schleife (ziehen und behalten), bis 23 Handkarten.

- **Ausspielen:** Antippen hebt die Karte, das zweite Antippen spielt sie aus. Wischen nach oben spielt ebenfalls aus.
- **Ziehen:** Tipp auf den Stapel, danach „Behalten“ (`20a`).
- **Wünscher:** Beim Ziehen erscheinen vier Farbfelder; Loslassen auf Grün setzt die Farbe (`21a`, `21c`).
- **Sortieren:** Der Knopf wechselt die Sortierung (Farbe/Wert/…).
- **Rückseiten:** Halten zeigt die eigenen Rückseiten, Loslassen beendet die Ansicht (`08`).
- **Kartenhilfe:** Halten öffnet die Großansicht (`09a`); nach unten auf „?“ ziehen öffnet die passende Kartenhilfe (`09c`).
- **+2 vom Gegner:** „Anzweifeln“ und „Annehmen“ funktionieren (`11`).
- **Mau:**
  - „Mau!“ bei 2 Karten (`19a`).
  - Gegner-Mau als „Mau!“-Marke über dem Gegner (`40a`).
- **Effekte:**
  - Richtungswechsel animiert (`18a`).
  - Flip Tag→Nacht und zurück mehrfach ohne Hänger (`23a`, `23b`).
- **Rundenende:** Rundenende mit „Nächste Runde“ funktioniert (`16`).
- **Hand ab 16 Karten:** Bogen-Karussell mit Schwung, Einrasten und Gummiband; Ausspielen aus dem Karussell (`24a`, `26_s21_karussell_ablauf.jpg`, `26g`).
- **Bedienbarkeit:** Tipps und Gesten haben mit den adb-Koordinaten zuverlässig getroffen.
- **Lesbarkeit:** Eckindex und Hinweiszeile gut lesbar, auch auf der Nachtseite.
- **Hänger und Fehler:** keine Hänger, keine Fehler im Log.
- **Nicht gezielt geprüft:** die Lupe bei 8–15 Karten.

### 3. Weitergeben mit 2 Menschen + 1 Computergegner (S21) – bestanden

- Vor jedem Menschenwechsel erscheint der Sichtschutz, z. B. „Gib das Handy … an Anna“ bzw. „… ist wieder dran“. Er zeigt keine Karten und keine Rückseiten, nur „Ablage: n Karten · Stapel: n Karten“ (`31a`, `32_s21_sichtschutz_anna.jpg`).
- Halten (0,5 s mit Ring) deckt die Hand auf (`31b` → `31c`, `33b`).
- Ein kurzes Antippen deckt nicht auf.
- Die Züge des Computergegners laufen hinter dem Sichtschutz.

### 4. WLAN – nicht bestanden (H1)

**Was funktioniert**

- **Lobby:** QR-Code und Adresse `192.168.178.8:24690` als Text, mit Hinweisen (`51_s21_lobby_qr.jpg`).
- **`/info`:** `{"addresses":["192.168.178.8"],"game":"mau-mau-flip","max":10,"name":"Sam","players":1,"port":24690,"proto":1,"running":false,…,"version":"0.1.1"}`
- **`/apk`:**
  - `200`, `application/vnd.android.package-archive`, `Content-Length: 39156408`, `Content-Disposition: attachment; filename="MauMauFlip-0.1.1.apk"`, `Accept-Ranges: bytes`.
  - Download in 2,7 s; SHA-256 identisch mit dem Build.
  - Range-Anfrage: `206`.
- **Weitere Antworten:** `GET /` liefert `200 text/html`. Ein HTTPS-Versuch wird sofort abgewiesen.
- **Suche:** Die UDP-Suche des S10 findet „Spiel von Sam“ (`75b`).
- **App-Gast:** Beitreten klappt, beide Lobbys stimmen überein (`76a`, `76b`).
- **Wiederverbinden in der Lobby:** S10-App mit `am force-stop` beendet → der Gastgeber zeigt „App · getrennt“ (`77a`). Nach Neustart und erneutem Beitritt steht der Gast auf demselben Platz 2 als „verbunden“ (`77d`).
- **Browser-Gast:** Chrome auf dem S10 über `http://192.168.178.8:24690/` mit Startseite, Name, Lobby und „Bereit“ (`78a`, `78c`, `79b`). Ein zweiter Browser-Gast (PC-Chrome headless) trat ebenfalls bei (`54a`).
- **Sitzordnung:** Eine Änderung durch den Gastgeber kommt sofort im Browser an (`79a`/`79b`).
- **Erneut eröffnete Lobby:** Nachdem der Gastgeber die Lobby schloss und neu eröffnete, traten App- und Browser-Gast automatisch wieder bei (`84a`).

**Was nicht funktioniert:** Der Start, siehe H1. Deshalb waren am Gerät nicht prüfbar:

- abwechselnde Züge S21/S10,
- „jeder sieht nur seine Hand“,
- Ereignisse und Mau-Blasen auf allen Geräten,
- die Sitzordnung am Tisch,
- das Wiederverbinden während der Partie.

**Ersatzprüfung für den Browser-Client:** Der Lite-Client lief im echten Chrome des S10 gegen den PC-Testgastgeber `game/tests/web_host.gd` (echte `HostTable`, über `adb reverse`) mit `?autotest=1`. Ergebnis: „AUTOTEST OK: 15 Züge, 1 Rundenende, 62 Zustände, 0 Ablehnungen“ mit 5 Flips, 5 Mau-Ereignissen und 6 Blasen; der Gastgeber meldete `RESULT: 2 ok` (`86a`, `86b`). Der Browser-Client selbst spielt also auf einem echten Android-Chrome. Er braucht nur einen funktionierenden Gastgeber.

### 5. Einstellungen – bestanden, mit M2

- **Mau-Probehören:** Die Wiedergabe startet. `dumpsys audio` zeigt einen OpenSL-Player der App mit `state:started`, `USAGE_MEDIA`. Hörbar war nichts, weil das Gerät stumm ist (`60b`).
- **Spieltöne:** Aus/Leise/Normal schaltbar (`61a`); danach wieder auf „Aus“ gestellt.
- **Beta-Kanal:** Der Schalter schaltet um (`62a`); danach wieder auf „an“ gestellt.
- **„Jetzt prüfen“:** In beiden Kanälen erscheint „Noch kein passendes Release veröffentlicht.“, ohne Absturz (`62b`, `62c`; Log „Kanal Release“/„Kanal Beta“).
- **„App teilen“:** Das Android-Teilen-Menü zeigt `MauMauFlip-0.1.1.apk` (`63a`). Zurück schließt es, danach erscheint der Hinweis „Teilen-Menü geöffnet …“ (`63b`). Es wurde nichts versendet.

### 6. Zurück-Taste – Mängel (M1)

| Ort | Erwartet | Tatsächlich |
|---|---|---|
| Spiel | Rückfrage „Partie verlassen?“ | keine sichtbare Reaktion |
| Spiel mit offener Rückfrage | Rückfrage schließen | Rückfrage bleibt bzw. öffnet neu |
| Großansicht | schließen | schließt, und die Rückfrage öffnet sich |
| Lobby mit Gästen | eine Rückfrage | zwei Rückfragen übereinander |
| Regeln, Einstellungen | Hauptmenü | App wird geschlossen |
| Hauptmenü | App schließen | App wird geschlossen (in Ordnung) |
| Teilen-Menü | schließen | schließt (in Ordnung) |

## Log

- `logcat -d` (main und crash), gefiltert nach `FATAL`, `AndroidRuntime`, `SCRIPT ERROR`, `E godot`, `ANR`: keine Treffer auf beiden Geräten. Der Release-Build schreibt nur Infozeilen (Start, Netz, Updater).
- Zu H1 gibt es keine Logzeile, weil der Server kontrolliert gestoppt wird. Belege sind `Connection refused` und die Bildschirmfotos.

## Hinweise zum Ablauf

- Zwischen 21:41 und 21:46 gab es auf dem S10 echte Fingereingaben (`InputReader`, nicht über adb). Offenbar hat dort jemand ein Übungsspiel gespielt. Ich habe dieses Spiel um 21:55 mit „Verlassen“ beendet, um den WLAN-Test zu machen.
- Am Gerät wurde nichts eingestellt und nichts geteilt oder versendet. `adb reverse` für den PC-Testgastgeber habe ich danach wieder entfernt.
- Die App ist am Ende auf beiden Geräten installiert (0.1.1).

## Nach der Korrektur erneut prüfen

1. Punkt 4 vollständig:
   - S21 als Gastgeber mit S10-App und S10-Chrome: Züge abwechselnd, nur die eigene Hand sichtbar, Ereignisse und Mau-Blasen überall.
   - Sitzordnung am Tisch.
   - S10 während der Partie mit `force-stop` beenden und wieder beitreten.
2. Zurück-Taste an allen Orten der Tabelle oben.
3. Wisch-Bildlauf in Einstellungen, Regeln, Weitergeben-Einrichtung und Lobbys.
