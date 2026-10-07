# Gerätetest Beta 1.0.2 (07.10.2026)

APK `builds/MauMauFlip-1.0.2.apk` (version/code 1000002, SHA-256 `c963b9ebf33d9147f93be5dc2d055e8cb77befd6357f218b18d03deee1fdbbd9`), Projektschlüssel.
Geräte: S21 (Gastgeber, 192.168.178.8) und S10 (Gast, 192.168.178.9), beide im Heim-WLAN.
`build.ps1 -Target Test`: alle 56 Testläufe bestanden. Danach eine kleine Textkorrektur im Lite-Client, `test_web_contract` erneut grün (374 ok).

## Ergebnis

| Bereich | Ergebnis |
|---|---|
| Neue Lobby | Kopfzeile „So geht's / Regeln / Start“, Start sichtbar und erst ab 2 Spielern aktiv (n_1, n_8) |
| Blättern | Wischen zur Spielerliste rastet ein, Tipp auf den Randhinweis blättert zurück (n_2) |
| So geht's | Dialog mit Einladen-Anleitung und „Ohne App spielen“ (n_3) |
| ① im WLAN | „Mitspieler verbinden sich mit demselben WLAN wie du.“ + „Lieber eigenes Spiel-WLAN“, ① leuchtet (n_1) |
| Haken ① | erscheint, sobald der S10-Chrome die Spielseite öffnet; danach leuchtet ② (n_4) |
| Haken ② | erscheint beim Beitritt, Start wird aktiv (n_8) |
| „In der App spielen“ | Knopf im S10-Chrome (n_5) öffnet die App, sie fragt nach dem fehlenden Namen und tritt dem S21 direkt bei (n_6, n_7) |
| App-Link bei laufender App | `maumauflip://join?...` an die laufende App: Beitritt ohne Suche (n_16) |
| Regeln/So geht's im Spiel (App) | Spielmenü mit beiden Knöpfen, Überlagerung mit Reitern, Partie läuft weiter (n_9, n_10) |
| Regeln/So geht's im Spiel (Lite) | im ☰-Menü, bei Schrift „Groß“ gut lesbar (n_11, n_12) |
| Schrift „Groß“ (App) | Lobby passt (n_13); danach wieder auf „Normal“ gestellt |
| Spiel-WLAN | öffnen: WLAN-QR, Name, Passwort, Spiel-Adresse 192.168.35.250 (n_14); schließen: `swlan0` weg, zurück zu „im WLAN“, Server unter 192.168.178.8 erreichbar (n_15) |
| Manifest | `.GodotAppLink` mit VIEW/BROWSABLE und Schema `maumauflip`; NEARBY_WIFI_DEVICES mit neverForLocation und ACCESS_FINE_LOCATION mit maxSdkVersion 32 erhalten |
| logcat (App-Prozess) | keine Fehler der App; nur übliche Surface-Meldungen des Systems beim Wechsel in den Hintergrund |

## Behoben in diesem Durchgang

- Lite-Regeltext: „(1 Strafkarten)“ heißt jetzt „(eine Strafkarte)“, ebenso „kostet sofort eine Karte“ (`webclient/karten.js`).

## Offen / für den Nutzer

- Wischen über der Spielerliste mit echtem Finger (geprüft nur per adb-Wischgeste).
- Haken ① beim Seitenaufruf aus dem Spiel-WLAN (kein Beitritt ins Spiel-WLAN getestet).
- Nach „Spiel-WLAN schließen“ bindet die Sitzung nicht neu; im Heim-WLAN war der Server trotzdem erreichbar.
- iPhone und Godot-Web nicht geprüft.
