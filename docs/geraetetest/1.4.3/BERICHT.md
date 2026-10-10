# Gerätetest Beta 1.4.3 – QR-Scanner (10.10.2026)

Geräte: S21 (SM-G991B, Android 15) und S10 (SM-G973F, Android 12), beide im Heim-WLAN, ohne SIM (mobile Daten nicht prüfbar).
Testeinstieg ohne Kamera: `am start … --es mmf_scan "<Text>"`. Bilder `n_*.jpg` (halbe Auflösung).

## Ergebnisse

| Schritt | Ergebnis |
|---|---|
| 1 Spiel-Link `http://192.168.178.8:24690/` (S10 → S21) | OK, Lobby beim Gastgeber (n_03) |
| 2 Online-Raum-Link `https://…workers.dev/?r=WIEGE-61` | OK, „1 Mitspieler online“ (n_06) |
| 2 App-Link `maumauflip://join?h=…&p=24690` | OK, alter Platz per Token zurück (n_07) |
| 3 WLAN-QR des Spiel-WLANs | **zuerst Mangel** (s. u.), nach Korrektur: Systemdialog „Mit Gerät verbinden?“ (n_23), Beitritt am Gateway 192.168.35.250, S10 als 192.168.35.82 im Spiel (n_25–n_28, TCP-Verbindung am Host bestätigt) |
| 4 Systemdialog abbrechen | S21 (falsche SSID): Suche → „Keine Geräte gefunden“ → Abbrechen → Meldung „Keine Verbindung zum Spiel-WLAN …“, Heim-WLAN bleibt (n_32) |
| 4 Seite während des Dialogs verlassen | nicht prüfbar – der Systemdialog liegt modal darüber (Zurück wirkt nicht) |
| 4 Verlassen → Freigabe | **offen**: S10 nach dem Beitritt ohne adb (WLAN-Debugging aus, kein STA+STA) |
| 5 „Hallo“ / kaputter WLAN-Code | OK, passende Meldungen (n_08, n_09) |
| 6 Knopf „QR-Code scannen“ | S10 1. Antippen: „Der Scanner ließ sich nicht öffnen“, Google lud das Modul nach (n_10); 2. Antippen: Kamera-Ansicht „Code scannen“ (n_14b); Abbrechen ohne Meldung (n_15). S21: Kamera sofort (n_31c) |

## Gefundene Mängel und Korrekturen

1. **hoch – Spiel-WLAN per QR ging nie:** `j[0].connect(…)` aus GDScript landet bei `Object.connect` (Signal), nicht bei der Java-Methode („Cannot connect to '': the provided callable is null“). Java-Methode in `QrWifi.request` umbenannt (`qr_join.gd`).
2. **hoch – fehlende Erlaubnis:** `requestNetwork` braucht `CHANGE_NETWORK_STATE` → im Manifest ergänzt.
3. **mittel – Handy bleibt ohne Heim-WLAN, wenn das Spiel-WLAN verschwindet:** Nach Schließen des Spiel-WLANs (Neuinstallation am S21) kam das S10 (Stand ohne Korrektur) in 90 s nicht ins Heim-WLAN zurück – die laufende Anfrage hält ein Handy ohne zweiten WLAN-Empfänger fest. Neu `QrJoin.check_lost` (aus `ClientTable.pump`, alle 2 s): Netz „lost/unavailable“ → Anfrage freigeben. Test in `test_app_qr_join`.
4. **mittel – Seite blieb verschoben:** Mit Fokus im Raumcode-Feld Scanner geöffnet → nach Rückkehr blieb die Seite um die alte Tastaturhöhe hochgeschoben, Liste leer (n_19c–e). `scan_qr` lässt jetzt den Fokus los und schließt die Tastatur; am S21 geprüft (n_31a–d).
5. **mittel – lange Statuszeile verbreiterte die Seite** (Knöpfe rechts abgeschnitten, n_21): `_status` bricht jetzt um (n_22, n_32e).
6. **niedrig – erster Scan ohne Modul:** `QrScan` prüft jetzt `areModulesAvailable`; fehlt das Modul, wird es geladen und „Der Scanner wird gerade von Google geladen …“ gezeigt. Fehler werden geloggt (Tag `MauMauFlip`). Am Gerät nicht mehr nachstellbar (Modul inzwischen auf beiden Handys).

Tests: alle 75 Testläufe grün; APK `builds/MauMauFlip-1.4.3.apk` (SHA-256 b47ae4e1…0037) auf dem S21 installiert. Das S10 hat den Zwischenstand mit 1. und 2., aber ohne 3.–6.

## Offen

- ~~S10 braucht den Nutzer~~ – erledigt, siehe „Nachprüfung“.
- Einmalig, nicht nachstellbar: Nach dem gescheiterten ersten Scan trat das S10 von selbst dem zuletzt genutzten Online-Raum bei (n_11/n_12). Möglicherweise über das fokussierte Raumcode-Feld (Korrektur 4); beobachten.
- Gast verlässt die Lobby per Zurück → beim Gastgeber bleibt er als „getrennt“ stehen, Neubeitritt als „Kim 2“ (vermutlich schon vor 1.4.3).
- Mobile Daten am Gast (eigentlicher Anlass) mangels SIM nicht geprüft.

## Nachprüfung (10.10.2026, 17:30–17:50)

Stand: alle Korrekturen 1.–6. plus Scan-Knopf gelb (`PrimaryButton`). `build.ps1 -Target Test`: alle 75 Testläufe grün; `-Target Android` (mit Tests): `builds/MauMauFlip-1.4.3.apk`, SHA-256 `88271333898d0a6e53c15304f3827bdad97d998aff7f3fe3298840ebac8ec08a`, auf S21 und S10 installiert. Beide Handys im Heim-WLAN, S10 wieder per WLAN-Debugging erreichbar. Bilder `np_*.jpg`.

| Schritt | Ergebnis |
|---|---|
| Scan-Knopf in der Kopfzeile | gelb, rund, gut sichtbar (S21, np_01; S10 ebenso) |
| A: WLAN-QR (Testeinstieg) → Systemdialog „Verbinden“ | S10 im Spiel-WLAN, Kim in der Lobby des S21 (np_02) |
| A: S21 „Spiel-WLAN schließen“ (17:37:15) | `check_lost` greift: Anfrage freigegeben 17:37:16,1, S10 17:37:19,7 wieder im Heim-WLAN (**4 s**); S10 zeigt „Verbindung zum Gastgeber unterbrochen – warte …“ (np_03). adb kam von selbst zurück (WLAN-Debugging mit neuem Port) |
| B: WLAN-QR erneut (neues Spiel-WLAN) | Kim bekommt ihren Platz zurück („App · verbunden“, kein „Kim 2“, np_04) |
| B: S21 Lobby schließen (17:45:16) | Freigabe 17:45:16,8 (Gastgeber-Ende), Heim-WLAN 17:45:20,7 (**4 s**); S10: „Der Gastgeber hat das Spiel beendet.“ (np_05) |
| C: aktives Verlassen am S10 | geprüft über zeitversetzte Tipps auf dem S10 selbst (`nohup sh -c 'sleep 30; input tap …'`): Zurück in der Lobby 17:47:17 → Freigabe 17:47:17,6, Heim-WLAN 17:47:21,4; S10 im Hauptmenü (np_06) |

Kleinigkeiten (niedrig, nicht neu):
- Nach C steht Kim beim Gastgeber als „App · getrennt“; der Dialog „Lobby schließen?“ meldet trotzdem „1 Mitspieler ist verbunden und wird getrennt.“ (np_07).
- „Lobby schließen“ ohne vorheriges „Spiel-WLAN schließen“ lässt das Spiel-WLAN offen (beim erneuten Eröffnen gleiche SSID) – bekannter Punkt.

Ende: S21 und S10 im Hauptmenü, beide im Heim-WLAN, Spiel-WLAN geschlossen.
