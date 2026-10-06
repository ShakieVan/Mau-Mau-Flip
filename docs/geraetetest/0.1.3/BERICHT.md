# Gerätetest 0.1.3

06.10.2026, 16:50–17:45. Getestet wurde `builds/MauMauFlip-0.1.3.apk` (Code 1003) auf dem S21 (Gastgeber, 2400×1080) und dem S10 (2280×1080). Vorher wurden die App-Daten gelöscht. Bedient wurde über `adb shell input`. Die Bilder `n_*.jpg` sind in halber Auflösung. Während des Tests lief im WLAN noch ein fremdes Spiel (0.1.2, 192.168.178.4). Ich habe es nicht angefasst.

## Vor dem Test zusammengeführt

- `net_protocol.gd`: `clean_action` lässt jetzt `cards` durch, als Liste ganzer Zahlen mit höchstens 120 Einträgen. Damit kommt `discard_pick` auch übers Netz an, und `test_web_contract` ist grün.
- Version 0.1.3 in `project.godot` und `webclient/app.js`.
- `build.ps1 -Target Test`: alle 46 Läufe grün.

## Ergebnisse

| Prüfung | Ergebnis |
|---|---|
| Regeln: Wünscher +2 und Farbjagd nur „Immer erlaubt“ oder „App prüft“, kein Joker-Schalter (`n_01`) | ok |
| Tauschrichtung mit 4 Knöpfen, Glücksspiel-Text nennt das Aufhören, Ablegen-Text sagt „du wählst aus“ (`n_02`) | ok |
| Kein Anzweifeln: Auf einen Wünscher +2 und auf eine Farbjagd der Gegner kam keine Rückfrage | ok |
| Farbe ablegen, farbige Karte: Karte vorausgewählt, Knopf „Ablegen (1)“, Abwählen ergibt „(0)“, „Mau!“ in der Auswahl ging (`n_03`, `n_04`) | ok |
| Ablegen-Joker (WLAN-Partie): erst „Welche Farbe legst du mit ab?“ mit Anzahl je Farbe, dann 4 blaue Karten vorausgewählt, 1 abgewählt, danach „Mit welcher Farbe geht es weiter?“. Ergebnis: 3 Karten abgelegt, Spielfarbe Rot (`n_08`–`n_11`) | ok, mit Mangel M1 |
| Computergegner mit Ablegen-Karte und Ablegen-Joker, Banner „Socke legt 2 orange Karten mit ab.“ | ok |
| Kartentausch „Gegen die Spielrichtung“: Die Hände wanderten entgegen der Zugfolge, meine ging an den Spieler vor mir (`n_12`) | ok |
| Tempo-Regler: gemütlich etwa 7,6 s, bis ich wieder dran war; flott 3 Züge der Gegner in etwa 2,5 s (`n_06`) | deutlich spürbar |
| WLAN: S10-App-Gast und Chrome-Gast am PC (`?autotest=1&zuege=4`), gleiche Sitzordnung auf beiden Handys | ok, „AUTOTEST OK: 4 Züge, 0 Ablehnungen“ |
| S10-App beendet: Knopf „Computer spielt für …“ mit Rückfrage, danach spielt die Partie weiter, auch für den getrennten Browser-Gast (`n_07`) | ok |
| Lite-Ablegeauswahl (Mock in Chrome headless): `szene=ablegejoker&pflicht=ablegen_joker` (ausgewählt, abgewählt) und `haus=1&gegner=5&richtung=gegenspiel` | beide OK |
| logcat (S21, S10): keine Fehler, Warnungen oder Abstürze von Godot | ok |

## Mängel und Korrekturen

- **M1 (mittel, behoben):** Der Knopf „Computer spielt für …“ oben links hat die Frage über dem Farbrad verdeckt, z. B. „Mit welcher Farbe geht es weiter?“ (`n_10`). Jetzt ist der Knopf ausgeblendet, solange das Farbrad offen ist (`table_screen.gd`, `_process`).
- **M2 (klein, behoben):** Wer beim Ablegen alle Karten abwählte, sah „Du hast keine weitere grüne Karte.“, obwohl er eine hatte (`n_05`). Der Text heißt jetzt „Du legst keine grüne Karte mit ab.“ (`table_house_rules.gd`).
- **Hinweis:** Die Regelzeile nennt bei „free“ weiter „Joker frei“ (`rules_bar.gd`). Das passt, ist aber anders formuliert als „Immer erlaubt“.
- **Hinweis:** Ein vom Computer vertretener Gast steht am Tisch weiter als „getrennt“ da.
- **Hinweis:** Der Griff des Tempo-Reglers ist sehr klein, ließ sich aber ziehen.

Nach den Korrekturen M1 und M2: `build.ps1 -Target Test` erneut mit 46 von 46 grün, APK neu gebaut (SHA-256 `9d9f9c8e…0329d12`), auf beiden Handys installiert und gestartet. Am Gerät habe ich die Korrekturen nicht mehr geprüft.

## Nicht geprüft

- N6 (App-Gast im Hintergrund) und die Rückkehr eines vertretenen Gastes. Beides ist durch `test_screens_013` abgedeckt.
- Lite mit echtem Gastgeber in der Auswahlphase. Der Autotest gegen das S21 hatte keine Ablegen-Karte. Die Mock-Läufe decken die Phase ab.
