# Gerätetest Beta 1.1.2 (08.10.2026)

APK `builds/MauMauFlip-1.1.2.apk` (version/code 1001002, SHA-256 `1574eea0c3206517332de5f462b3f0ba6d75e6db23d406f36a20a3aa75e6d75b`), Projektschlüssel, gebaut mit `build.ps1 -Target Android` (alle 59 Testläufe bestanden).
Geräte: S21 (SM-G991B, Gastgeber) und S10 (SM-G973F, Lite in Chrome). Beide per drahtlosem adb erreichbar, angesprochen über die Transport-ID.

## Ergebnis

| Bereich | Ergebnis |
|---|---|
| ☰ am Tisch | neben dem Zurück-Knopf, Tag (n_1). Im großen Modus darunter, Tag (n_8) und Nacht (n_5) |
| Menü | „Einstellungen“, „Regeln ansehen“, „So geht's“ (n_2) |
| Einstellungen im Spiel | Überlagerung, die Partie läuft weiter (n_3). „Schrift: Groß“ und „Großer Modus“ wirken sofort, dahinter ist der große Tisch zu sehen (n_4). Zurück-Taste schließt |
| Regeln / So geht's | öffnen sich aus dem ☰-Menü (n_6, n_7) |
| Weitergeben | Beim Sichtschutz gibt es keinen ☰-Knopf und keine Karten (n_10). Nach dem Aufdecken öffnet ☰ das Menü (n_11) |
| Großer Modus, „bis zum Letzten“ | 3 Plätze (Familie): Mimi wird fertig und verschwindet aus der Liste, es bleiben „Du“ und Kater Karlo (n_9) |
| S10: Lite gegen S21 | Selbsttest `?gross=1&autotest=1`: **OK** (7 Züge, 1 Rundenende, 15 Stände, 0 Ablehnungen, Mau gerufen) (n_12, n_13). Das S10 stand hochkant (Drehung gesperrt, nicht verstellt). Deshalb zeigte Lite den normalen Tisch mit „Quer halten“ |
| logcat (App-Prozess S21) | keine Fehler |

## Behoben in diesem Durchgang

- **Reiter der Regelhilfe nachts:** Der nicht gewählte Reiter („So geht's“ bzw. „Regeln“) hatte dunkle Schrift auf der dunklen Karte und war kaum zu sehen (n_6, n_7). Jetzt ist die Schrift dort nachts hell (`ingame_help.gd`). Der Test `test_ui_ingame_help` prüft das. Am Gerät nur bei Tag gegengeprüft, weil die Partie nicht rechtzeitig in die Nacht kam.
- **`test_screens_flow` schlug im Gesamtlauf fehl** (2 von 2 Läufen, einzeln grün). Ursache: Der Test übernimmt die gespeicherten Hausregeln, und darin waren Glücksspiel und „Farbe ablegen“ an. Auf diese Phasen reagierte die Zugschleife nicht und blieb hängen. Jetzt spielt der Test in diesen Phasen wie ein Computergegner weiter (`MauBot.choose`).
- Version 1.1.2 in `project.godot` und `webclient/app.js`.

## Offen / für den Nutzer

- Die Einstellungen sind auch nachts eine helle Papierkarte (n_3). Das ist gut lesbar und war so gewollt.
- „Regeln ansehen“ und „So geht's“ stehen im ☰-Menü und zusätzlich im Menü des Zurück-Knopfs. Das ist absichtlich so.
- Lite hochkant: In der Lobby sind die Zeilen rechts abgeschnitten („bere…“, „2 Spiel…“) (n_12). Das war vermutlich schon vorher so; die Seite bittet darum, das Handy quer zu halten.
- Lite im großen Modus mit fertigen Spielern ist nur im Chrome-Headless-Test am PC geprüft (`gross_fertig`), nicht am S10. Grund: hochkant und nur 2 Plätze.
