# Gerätetest Beta 1.2.2 (englische Fassung)

Geräte: S21 (SM-G991B, Gastgeber, App) und S10 (SM-G973F, Lite in Chrome). Beide Systemsprache Deutsch, nicht verstellt. Sprache nur in der App umgeschaltet.

| Prüfung | Ergebnis |
|---|---|
| Tests | `build.ps1 -Target Test -NoTestCache`: 62/62 (test_game_net war wackelig, siehe unten, danach grün); `test_i18n` streng: 0 Lücken, 923 ok; `test_web_contract` 395 ok |
| S21 App „English“ | Hauptmenü, Einstellungen, Spielen im WLAN, Gastgeber-Lobby (n_3 bis n_6), Tisch mit Hinweisleiste (n_11, n_12), Rückfrage „Leave the game?“ (n_16): alles englisch, nichts abgeschnitten |
| S10 Lite auf Deutsch gegen englischen Gastgeber | Lobby und Tisch deutsch (n_8, n_10), der Gastgeber zugleich englisch („Autotest's turn.“ / „Your turn – play Blue or a 5.“): jedes Gerät in seiner Sprache. Zug gezogen, Hinweise auf beiden Seiten richtig |
| Zurück auf „Automatisch“ | Menü wieder deutsch (n_18) |
| logcat | keine Fehler oder Abstürze von de.maumauflip.game |

## Im Test gefunden und behoben
- Rückfrage beim Verlassen („Partie verlassen?“, „Verlassen“, „Regeln ansehen“) und „Computer übernimmt?“ / „Übernehmen“ waren unübersetzt: msgids ergänzt, am Gerät erneut geprüft (n_16).
- Version im Hauptmenü und „Zuletzt geprüft“ in den Einstellungen blieben nach dem Sprachwechsel deutsch: werden jetzt neu gesetzt.
- test_game_net: Der Computer-Spieler konnte beim erzwungenen Glücksspiel zufällig „Aufhören“ wählen und den Test kippen; im Test jetzt unterbunden.

## Offen
- Rundenende, großer Modus und Regeln nur als Kontrollbilder am PC (Bereiche A bis C), nicht am Gerät; kein vollständiges Spiel gespielt.
- Dialoge, die nur auf Abruf entstehen, sind vom Lückentest nicht erfasst (Rückfragen wurden von Hand gegen die .po geprüft; weitere Fälle möglich).
- Fehlerseiten des Hosts für Browser (HTTP, APK-Hinweis) bleiben deutsch; Antworten aus Java-Helfern nur teilweise über `Updater.java_text` übersetzt.
- iPhone weiter ungetestet. Ein Tippfehler beim Beitreten öffnete auf dem S10 kurz die App („In der App spielen“), abgelehnt mit „Bleiben“; nichts gewechselt.
