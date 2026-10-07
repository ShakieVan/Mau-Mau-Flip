# Gerätetest Beta 1.0.1 (07.10.2026)

APK `builds/MauMauFlip-1.0.1.apk` (version/code 1000001, SHA-256 `ee5303d1ac76ee8c50af0905349869caf0e0313d8757832b1ef93389c25a4967`), Projektschlüssel.
Geräte: S21 (SM-G991B, Android 15), S10 (SM-G973F, Android 12). `build.ps1 -Target Test`: alle 52 Testläufe bestanden (vor und nach den Korrekturen).

## Ergebnis

| Bereich | Ergebnis |
|---|---|
| Schrift Normal/Groß/Sehr groß | lesbar, wirkt sofort; zwei Mängel gefunden und behoben (siehe unten) |
| Tisch, Übung, Regeln, Einstellungen | kein Abschneiden mehr (n_2, n_8, n_10) |
| Ablage durchsehen | vor, zurück, alles zurück, „von …“, „Wunsch: …“, Zähler gehen; Flip setzt zurück (n_3, n_4, n_11) |
| Spiel-WLAN (S21) | Erlaubnisdialog „Geräte in der Nähe“ kommt, Panel mit WLAN-QR und Spiel-QR (n_6, n_7) |
| Hotspot-Schnittstelle | `swlan0` mit 192.168.35.250/24 neben `wlan0`; Server lauscht auf `*:24690` |
| Server über Hotspot-Adresse | `nc 192.168.35.250 24690` auf dem S21: `HTTP/1.1 200 OK`, `Server: MauMauFlip/1.0.1` |
| Fertig / Schließen | „Fertig“ lässt das WLAN offen (gleiche SSID beim Wiederöffnen), „Spiel-WLAN schließen“ entfernt `swlan0` |
| Manifest | NEARBY_WIFI_DEVICES mit neverForLocation, ACCESS_FINE_LOCATION mit maxSdkVersion 32 bleiben im fertigen APK erhalten |
| logcat (App-Prozess) | keine Fehler auf beiden Geräten |

## Behoben in diesem Durchgang

1. **Lobby lief bei „Sehr groß“ rechts über** (n_5): Kopfzeile mit dem neuen Knopf zu breit, „+ Computer“, Pfeile und „Start“ abgeschnitten. Knopf heißt jetzt „Spiel-WLAN“, etwas weniger Abstand (`host_lobby.gd`). Danach passt alles (n_9).
2. **„Schriftgröß-e“ brach bei „Sehr groß“ mitten im Wort um** (n_1): Zeile heißt jetzt „Schrift“ (`settings_screen.gd`, n_10).
3. Beschriftungen beim Ablage-Durchsehen und Texte im Spiel-WLAN-Panel wuchsen nicht mit der Einstellung; jetzt über `UiFonts.px` (`discard_browser.gd`, `game_wifi_panel.gd`).

## Offen / für den Nutzer

- Beitritt eines zweiten Geräts ins Spiel-WLAN per WLAN-QR (Android und iPhone) und Neu-Binden aus dem Hotel-WLAN: nicht selbst getestet.
- Spiel-WLAN auf dem S10 (Android 12, Standortabfrage) nicht getestet.
- Bei „Sehr groß“ mit Joker reicht der Zähler unter dem Seitenstapel bis an die Hinweisleiste (berührt sie, verdeckt nichts, n_11).
- Browser-Client „Lite“ nicht auf den Handys geprüft (nur Chrome headless durch den Browser-Agenten).
- S10 steht noch auf Schrift „Groß“; S21 wieder auf „Normal“.
