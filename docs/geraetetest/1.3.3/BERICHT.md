# Gerätetest Beta 1.3.3 (08.10.2026)

**Aufbau:** S24 (SM-S928B, Android 16, Gerät des Nutzers, nur `install -r`) = Gastgeber, S21 (SM-G991B, Android 15) = App-Gast,
S10 (SM-G973F) = Lite in Chrome. Alle im Heim-WLAN. Vermittler `https://mau-mau-flip-relay.shakie.workers.dev`.
APK zuerst SHA-256 `21af40cc…8fd92dc`; nach der Korrektur Tests grün (69 Läufe), neu gebaut: `builds/MauMauFlip-1.3.3.apk` SHA-256 `5d93e510…c8bdef77`, auf allen drei Geräten per `install -r`.

| Schritt | Ergebnis | Bild |
|---|---|---|
| a) S24 noch 1.3.2: Online-Raum, Spiel-WLAN auf, Online schließen, neuer Raum | Raum KOFFER-88 öffnet (`/info` open:true). Android-16-Problem tritt hier **nicht** auf: S24 hängt im Heim-WLAN, `host_plan` bindet nicht. Nur ohne WLAN (Spiel-WLAN + Mobilfunk) zu erwarten, hier nicht nachstellbar. | n_01 |
| b) 1.3.3 per `install -r` (S24 Daten erhalten), Online + Spiel-WLAN, neuer Raum bei offenem Spiel-WLAN | APFEL-66 öffnet; S21 tritt per Code bei, Haken „1 Mitspieler online“ | n_02, n_03 |
| S21 App neu gestartet → Beitreten | Code APFEL-66 vorbelegt, Rückkehr per Token | n_04 |
| c) Partie; S21 HOME ~10 s | S24: Pille und Platz „Anna ist kurz in einer anderen App“, kein Vertretungsknopf | n_06 |
| S21 HOME ~38 s | ab 30 s Knopf „Computer für Anna spielen lassen“ (nicht gedrückt) | n_07 |
| S21 zurück | Hinweis weg, Zug/Karten (7/7)/Stapel 109/Ablage gleich | n_08 |
| S24 HOME ~10 s | S21: „Shakie (Gastgeber) ist kurz in einer anderen App – warte …“, nach ~10 s „Gastgeber kurz weg – warte …“ (Android trennt die Vermittler-Verbindung im Hintergrund, Code 4503) | n_09, n_10 |
| S24 zurück, S21 legt Blau 1 | beide gleich (Anna 6, Shakie dran) | n_11 |
| Zurück-Pfeil oben links | gezeichnet, gut sichtbar (Tag; Flip kam nicht) | n_05 |
| d) S10 Lite `http://192.168.178.4:24690` | Startseite tagsüber hell | n_12 |
| Lite-Partie, Chrome HOME ~7 s | S24: „Lisa ist kurz in einer anderen App“; zurück: Stand gleich (7/7, Stapel 108, Gelb 3) | n_13, n_14 |
| e) logcat | keine W/E-Zeilen mit Tag `godot`, keine TLS-Fehler (Ausnahme unten) | – |
| Nachprüfung mit neuem APK (GARTEN-57): S21 HOME 12 s | nur „kurz in einer anderen App“, zurück: Stand gleich, logcat ohne godot-W/E | n_15 |
| f) Aufräumen | Online vom Gastgeber beendet (GARTEN-57 steht laut Vermittler noch mit `host:false`, siehe unten), Spiel-WLAN geschlossen, S24 im Hauptmenü, S21/S10 App beendet | – |

## Mängel und Korrekturen

1. **Mittel, behoben:** Beim ersten HOME des Gastes kappte Android (S21) die Verbindung nach wenigen Sekunden. Der Gastgeber zeigte
   gleichzeitig „Anna ist getrennt.“, „Anna ist getrennt – warte …“ und „kurz in einer anderen App“ (n_00). Jetzt unterdrückt
   `host_table.gd` beide „getrennt“-Meldungen, solange der Platz „away“ ist; der Hinweis „kurz in einer anderen App“ bleibt.
2. **Niedrig, behoben:** Beim Zurückkehren nach so einer Trennung schrieb der Gast `ERROR: ready_state != STATE_OPEN` (wsl_peer `_send`)
   ins logcat. `net_client.gd` `check_now()` sendet das „ping“ nur noch, solange der Socket offen ist.

## Beobachtungen (offen, niedrig)

- **Raum bleibt nach „Verlassen“ bestehen (niedrig, offen):** APFEL-66 und GARTEN-57 blieben nach „Verlassen“ des Gastgebers mit `host:false`
  stehen (der Gast hatte „bye“ bekommen; der Vermittler löscht nach 10 min). Gemeinsam: Der App-Gast war vorher per HOME im Hintergrund.
  Ohne Gast-Abwesenheit (MORGEN-68, GRAS-91, auch mit Gastgeber-HOME) war der Raum sofort `open:false`. Vermutung: `{k:"end"}` kommt
  nach einer Gast-Neuanmeldung nicht an bzw. wird nicht verarbeitet; im Vermittler-Nachbau nachstellen.
- Die Lite-Lobby ist tagsüber weiter dunkel (nur Startseite und Tisch folgen Tag/Nacht).
- Das Spiel-WLAN bleibt nach Verlassen von Lobby/Partie offen, bis man es in der Lobby schließt.
- Chrome kam nach HOME auf dem S10 hochkant zurück („Quer halten“); Stand korrekt.
