# Gerätetest Beta 1.4.2 – Mitspieler dazuholen und entfernen (10.10.2026)

APK `builds/MauMauFlip-1.4.2.apk`, SHA-256 `f92c45fe6a929abf4623a99a925515e173de59af9fae3d6c4f50a21b0c7d12a7`, version/code 1004002.
Tests: `tools/build.ps1 -Target Test -NoTestCache` – alle 73 Läufe grün (4,1 min). Der erste Lauf scheiterte an `test_ui_celebrate`, weil ein paralleler Agent den Effekt gerade umbaute. Nach dessen Ende waren die Tests grün.

Geräte: S21 (Android 15) als Gastgeber im Heim-WLAN mit 2 Computergegnern, S10 (Android 12) als App-Gast. Der Browser-Gast wurde nicht am Gerät geprüft.

## Ablauf und Ergebnis

| Schritt | Ergebnis | Bild |
|---|---|---|
| Partie läuft, ☰ → „Mitspieler dazuholen“ (Einladefeld mit QR) | ok | n_01 |
| S10 sucht und tritt bei: Warteliste, „Bereit“ ausgeblendet | ok | n_02 |
| Gastgeber: „Am Tisch (1)“, Kim orange, ▲ rückt zwischen Minka und Mogli | ok | n_03 |
| Rückfrage „… bekommt 10 Karten“ (höchste Hand 10 = Start 10) | ok | n_04 |
| S10 sitzt am richtigen Platz mit 10 Karten, Ziehstapel 81 → 71 | ok | n_05 |
| Einige Züge zwischen beiden Geräten | ok | – |
| S10 wechselt in eine andere App: Die Sofort-Leiste mit „Computer übernimmt“ und „Aus dem Spiel nehmen“ erscheint sofort (< 3 s) | ok | n_06 |
| „Aus dem Spiel nehmen“ mit Rückfrage: Platz klappt weg, Karten gehen unter den Stapel (70 → 79), Partie läuft weiter | ok | n_07–n_09 |
| Computergegner entfernen, neuen dazuholen („bekommt 8 Karten“ = höchste Hand 8), Stapel 89 → 81 | ok | n_11, n_12 |
| logcat: kein Absturz und keine Skriptfehler; nur einmal `!is_inside_tree()` (can_process) gegen Partiebeginn | ok | – |

## Mängel

- **Mittel – der entfernte Gast erfährt den Grund nicht:** Kim war beim Entfernen in einer anderen App. Nach der Rückkehr zeigt S10 nur „Spiel beendet.“ und dazu „Selbst eröffnen“. Der Text „Der Gastgeber hat dich aus dem Spiel genommen.“ erscheint nicht (n_10). Vermutlich lief der Weg über das Wiederverbinden mit Ablehnung statt über `bye`. Das `bye` kommt nicht an, solange die App pausiert ist.
- **Mittel – Beitrittsseite überschreibt Hinweise:**
  - Ist das Feld „Mitspieler“ beim Gastgeber zu, wird der Beitritt abgelehnt mit „Die Partie läuft schon. Warte, bis der Gastgeber eine neue Runde eröffnet.“ Der Text steht nur kurz da, dann ersetzt ihn die Suche durch „1 Spiel gefunden“ (`join_screen._refresh_games` bei `games_changed`). Für den Gast passiert also scheinbar nichts. Außerdem passt der Text nicht mehr: Der Gastgeber kann jetzt über ☰ dazuholen.
  - Dasselbe passiert beim Ablehnen: „Der Gastgeber hat dich nicht dazugeholt.“ ist nach weniger als 1 s überschrieben.
- **Niedrig:**
  - Beim Hinsetzen zeigte S10 etwa 1 s lang einen leeren Tisch („Stapel · 0“) und erst dann die Partie.
  - Die Sofort-Leiste überdeckt den unteren Rand des rechten Gegnerfächers (n_06).
  - Die Gegnerfarben wechseln mit der Platznummer (Mogli: blau → gelb).
  - Der neue Computergegner heißt wieder „Mogli“.

## Nicht geprüft

Browser-Gast (Lite) am Gerät, Online über den Vermittler, Spiel-WLAN, großer Modus und Nacht am Gerät, ältere App-Clients (1.4.1) nach der Neunummerierung, „Computer übernimmt“ über die Sofort-Leiste.

## Nachtest (10.10.2026, nach den Korrekturen)

APK `builds/MauMauFlip-1.4.2.apk`, SHA-256 `a7e53fe59352b2b0af6394ae8504506b0a8f5c6ea81739be9efcc807b0ee9344`, version/code 1004002.
Tests: `tools/build.ps1 -Target Test -NoTestCache` – alle 74 Läufe grün (4,2 min), danach `-Target Android`.

Geräte: S21 (Android 15) als Gastgeber **online** über den Vermittler (Raum BIBER-59) mit 1 Computergegner. S10 (Android 12) war zuerst App-Gast über den Raumcode und dann Browser-Gast (Chrome, WLAN, `http://192.168.178.8:24690`). Den Browser-Gast über den Vermittler gibt es erst nach der Veröffentlichung (`/c/1.4.2/`).

| Schritt | Ergebnis | Bild |
|---|---|---|
| (c) App-Gast tritt online bei, solange „Mitspieler dazuholen“ zu ist: „Das Spiel läuft schon. Bitte den Gastgeber, dich dazuzuholen (☰ → Mitspieler dazuholen).“ steht nach 16 s immer noch da | ok | nt_01 |
| Gastgeber öffnet ☰ → Mitspieler dazuholen. Der Gast landet auf der Warteliste, sein Hinweis bleibt stehen | ok | nt_02 |
| ▲ setzt Kim zwischen Anna und Minka. Rückfrage „bekommt 10 Karten“. Kim sitzt richtig mit 10 Karten, Stapel 87 → 77. Sitzrichtung stimmt auf beiden Geräten | ok | nt_03, nt_04 |
| Einige Züge zwischen beiden Geräten (Gastgeber, Gast, Computer) | ok | – |
| Ladehinweis: beim Hinsetzen kein leerer Tisch mehr, nur kurz die Überblendung | ok | – |
| (b) Kim wechselt zum Startbildschirm. Die Sofort-Leiste erscheint rechts zwischen Minka und dem Mau-Knopf. Sie verdeckt weder Fächer noch Stapel oder Mau-Knopf und streift nur den Außenring. „Aus dem Spiel nehmen“ + Rückfrage, Stapel 77 → 86 | ok | nt_05 |
| Kim kehrt zurück: „Der Gastgeber hat dich aus dem Spiel genommen.“ / „Der Gastgeber kann dich wieder dazuholen.“ mit „Wieder beitreten“ und „Zum Menü“ | ok | nt_06 |
| „Wieder beitreten“ öffnet die Beitrittsseite mit Raumcode und dem Hinweis zum Dazuholen | ok | – |
| (c) Erneut auf der Warteliste, Gastgeber lehnt ab: „Der Gastgeber hat dich nicht dazugeholt.“ steht nach 15 s immer noch da | ok | nt_07 |
| Browser-Gast (Lite, WLAN): Warteliste, an den Tisch (10 Karten, Stapel 86 → 76), Karte gelegt, entfernt: „Der Gastgeber hat dich aus dem Spiel genommen.“ | ok | nt_08–nt_10 |
| Namen der Computergegner: Nach Minka kamen Mogli und nach dessen Entfernen Luna. Es gab keinen doppelten Namen | ok | – |
| (d) Browser-Feier am S10 (Testmodus `?mock=1&szene=rundenende`, ausgelöst über DevTools). Gemessene Teilchenzahl je Sekunde: 52, 100, 143, 141, 149, 139, 127, 102, 72, 44, 20, 7, 0. Also 5 s Regen, dann Ausrieseln, nach 13 s leer. Konfetti am Tag und Sterne in der Nacht; kein sichtbares Ruckeln | ok | nt_11, nt_12 |
| (d) App: Nach dem Entfernen des letzten Gegners endet die Partie. Der Konfettiregen läuft, aber hinter dem noch offenen Mitspieler-Fenster | ok, siehe Mängel | nt_13, nt_14 |
| logcat: kein Absturz und keine Skriptfehler. Nur wieder einmal `!is_inside_tree()` (bekannt) | ok | – |

### Mängel im Nachtest

Keine hohen oder mittleren Mängel.

- **Niedrig:**
  - Entfernt der Gastgeber den letzten Gegner, bleibt das Fenster „Mitspieler“ offen. Die Feier läuft dahinter und ist kaum zu sehen.
  - Nach diesem Partieende zeigt der Gastgeber „Warte auf Anna …“, obwohl er selbst Anna ist. Es gibt dort keinen Knopf für eine neue Runde, nur „Zum Menü“ (nt_14).
  - Hinter der Meldung „aus dem Spiel genommen“ steht beim Gast noch der alte Tisch mit „kurz in einer anderen App“ (nt_06).
  - Die Lite-Lobby zählt Gäste auf der Warteliste mit („3 Spieler“).
  - Die Seite „aus dem Spiel genommen“ im Browser ist auch tagsüber dunkel.
  - Bekannt: Die Gegnerfarben wechseln mit der Platznummer. Im Mitspieler-Fenster waren Kim und Minka nach ▲ kurz beide grün.

### Nicht geprüft

Den Browser-Gast über den Vermittler gibt es erst nach der Veröffentlichung. Die App-Feier wurde nicht frei im Bild gesehen, nur hinter dem Fenster. Ebenfalls nicht geprüft: großer Modus und Nacht in der App am Gerät, Spiel-WLAN, iPhone.
