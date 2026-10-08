# Gerätetest Beta 1.3.1 – Online-Spiel, Schritt 1 (lokal, 08.10.2026)

**Version:** 1.3.1 statt der zunächst genannten 1.2.3: Beta 1.2.3 und Release 1.3.0 sind schon veröffentlicht (HEAD „Release 1.3.0“,
versionCode 1003000). Eine neue „1.2.3“ hätte den Namen doppelt belegt und ließe sich nicht über 1.3.0 installieren.
Die Arbeitskopie stand zuvor versehentlich auf 1.2.2.

**Aufbau:** Vermittler-Nachbau (`relay_double_main.gd`, Port 24700) auf dem PC, `adb reverse tcp:24700 tcp:24700` an beiden
Geräten. S21 (SM-G991B) als Gastgeber mit APK 1.3.1, Vermittler `http://localhost:24700`. S10 (SM-G973F) als Lite-Gast in Chrome.
Neu: Der Nachbau liefert `relay/public` wie der Worker aus (Lader → `/info?room=` → `/c/1.3.1/?r=CODE`).

| Schritt | Ergebnis | Bild |
|---|---|---|
| Einstellungen → Online → „Verbindung testen“ | „Vermittler antwortet (89 ms)“ | n_01 |
| Lobby → „Online (Internet)“ → „Online öffnen“ | Raum MEISE-46 mit Link, QR und Teilen | n_02 |
| S10: `localhost:24700/?r=meise46` | Der Lader leitet auf `/c/1.3.1/` weiter, Code normalisiert, Beitritt | n_03 |
| Gastgeber sieht den Gast | Haken, „1 Mitspieler online“ | n_04 |
| Kurze Partie (5 Züge, Ziehen/Behalten, Richtungswechsel) | Beide Seiten synchron | n_06, n_07 |
| S10 öffnet den Link neu, „Weiterspielen“ | Mit Token zurück, gleiche Hand (5 Karten) | n_05 |
| Gastgeber „Verlassen“ | Lite: „Der Gastgeber hat das Spiel beendet.“, `/info?room` → `open:false` | n_08 |
| logcat der App (pid) | 0 Zeilen mit Stufe E/F | – |

**Gefunden und behoben:** Lite zeigte „Spiel von true“, weil der Vermittler bei `room.host` nur ja/nein liefert und keinen
Namen. Lite übernimmt jetzt nur noch einen Text als Namen (`webclient/app.js`).

**Nicht am Gerät geprüft:** Abbruch des Gastgebers mit Rückkehr per Token. Das deckt `test_game_online` und `test_net_online` in
Godot headless ab. wss/TLS lässt sich erst mit dem echten Cloudflare-Vermittler prüfen.
Das APK auf dem S21 war der Stand vor der Lite-Korrektur. Das endgültige APK unterscheidet sich nur im mitgelieferten Browser-Client.
