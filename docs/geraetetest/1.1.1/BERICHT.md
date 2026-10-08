# Gerätetest Beta 1.1.1 (08.10.2026)

APK `builds/MauMauFlip-1.1.1.apk` (version/code 1001001, SHA-256 `0aab4d9603b8684424e6af731b288b14796379dcff1aec0e13fa1da15a1b8b97`), Projektschlüssel, gebaut mit `build.ps1 -Target Android` (alle 58 Testläufe bestanden).
Gerät: S21 (Gastgeber, 192.168.178.8). **Das S10 war nicht per adb erreichbar**; der Lite-Gast lief deshalb in Chrome headless auf dem PC (eigenes Profil, 760×360, Handy-Emulation) gegen den S21-Gastgeber im Heim-WLAN.

## Ergebnis

| Bereich | Ergebnis |
|---|---|
| Einstellungen | „Großer Modus“ und „Bei deinem Zug: Vibration“ unter „Bedienung und Optik“ (n_1). Bei „Sehr groß“ und ausgeschaltetem großem Modus erscheint der Tipp (n_14) |
| Übungsspiel, 5 Computer, Familie | großer Stapel, große Ablage, Farbschild, Hand, Knöpfe, Liste rechts (n_2). Tag und Nacht (n_6), Hintergrund ruhig |
| Liste | wer dran ist, steht oben, darunter „gleich dran“. Sie rollt beim Zugwechsel (n_5), beim Richtungswechsel steht die Reihenfolge andersherum (n_3) |
| Effekte an der Liste | Mau-Schild an der Zeile (n_7), Glücksspiel: Automat in der Farbspalte, Einsatz über dem Ziehstapel (n_4), Ablage durchsehen über dem Ziehstapel (n_9) |
| Tipp auf eine Zeile | öffnet die Rückseiten (n_10) |
| Farbwahl bei „Sehr groß“ | lesbar, nichts abgeschnitten (n_8) |
| Sichtschutz bei „Sehr groß“ | passt (n_13, n_16) |
| Zurückschalten | normaler Tisch wie bisher (n_15) |
| Lite im großen Modus gegen den S21 | Selbsttest `?gross=1&autotest=1&schrift=sehr_gross`: **OK** (6 Züge, 18 Stände, 0 Ablehnungen, Glücksspiel gesetzt und gedrückt, Band gewischt) (n_12). Dazu `web_e2e.ps1 -Zusatz '&gross=1'` gegen den Godot-Gastgeber am PC: bestanden |
| Vibration | Der Vibrator wird von der App angesprochen (`dumpsys vibrator_manager`). Am Finger nicht gefühlt |
| logcat (App-Prozess) | keine Fehler, nur übliche System-Warnungen (Tastatur, GL-Kontext) |

## Behoben in diesem Durchgang

- **Hinweisleiste im großen Modus:** Wenn ein anderer dran war, lag die Leiste halb durchsichtig auf der großen Ablage und war auf roten Karten kaum lesbar (n_11). Jetzt hat sie einen deckenden Grund (`toast.gd` `opaque`, gesetzt in `table_view.gd`) (n_17).
- **Eigener Glücksspiel-Einsatz im großen Modus** etwas größer (96 statt 70 px).
- **Sichtschutz beim Partiebeginn** (Fehler schon vor 1.1.1): Er zeigte „Cleo ist wieder dran“ und „Ablage: 0 Karten · Stapel: 0 Karten“ (n_13). Jetzt steht dort „Gib das Handy an Cleo“, und die Zahlen fehlen, bis ausgeteilt ist (n_16).
- Version 1.1.1 in `project.godot` und `webclient/app.js`.

## Offen / für den Nutzer

- S10 im Chrome (echtes Wischen, schwaches Gerät) nicht geprüft, weil das Gerät nicht verbunden war. iPhone ebenfalls nicht.
- Rundenende bei „Sehr groß“ am Gerät nicht erreicht (zu lange Partie). Geprüft nur über die Kontrollbilder von `test_ui_dialogs_font_shot`.
- In der Liste bleiben Spieler, die schon fertig sind, mit 0 Karten stehen. „Gleich dran“ zeigt trotzdem richtig auf den Nächsten.
- Bei 8 Spielern zeigt die Liste 4 Zeilen (Mindesthöhe 84 px); mit 76 px wären es 5. Das entscheidet der Nutzer.
- Kräftigere Ränder der Handkarten (`card_view.gd`) gibt es noch nicht.
- `test_screens_flow` ist einmal unter Last gescheitert („eigene Züge gespielt (2)“, Frist 40 s). Einzeln und in den folgenden Bauten war er grün.
- Wichtig für Lite: Die Vibration beim eigenen Zug hängt jetzt nur noch an der neuen Einstellung (Standard aus). Wer nichts umstellt, bekommt dort keine Vibration mehr.
