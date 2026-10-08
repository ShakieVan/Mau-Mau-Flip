# Gerätetest Beta 1.2.1 (08.10.2026)

APK `builds/MauMauFlip-1.2.1.apk` (version/code 1002001, SHA-256 `0cbb725e725f676493c08144b81925039147307e4b24e9015ca0ed8812fc20cf`), Projektschlüssel, gebaut mit `build.ps1 -Target Android` (alle 61 Testläufe bestanden).
Vorher zweimal hintereinander `build.ps1 -Target Test -NoTestCache`: beide grün (2,9 min).
Geräte: S21 (SM-G991B, App, Gastgeber) und S10 (SM-G973F, Lite in Chrome), beide per drahtlosem adb. Daten der App vorher gelöscht.

## Ergebnis

| Bereich | Ergebnis |
|---|---|
| Rundenende | Runde 1 verloren: kein Satz, so ist es gedacht (n_rundenende_verloren). Runde 2 gewonnen: unter „Du gewinnst Runde 2!“ steht klein und gelb „Dein erster Rundensieg!“, nachts gut lesbar (n_rundenende_sieg) |
| Statistik | Nach der Partie in den Einstellungen: 1 Partie, 2 Runden, 1 Rundensieg, 1 „Mau-Mau!“, größte Hand 10, Glücksspiel „–“. Das stimmt mit der Partie überein (n_statistik). Kein neuer Knopf im Hauptmenü |
| Zurücksetzen | Rückfrage „Statistik zurücksetzen?“ mit Behalten/Zurücksetzen (n_statistik_rueckfrage), danach „Noch keine Partie gespielt.“ (n_statistik_leer) |
| Großer Modus (App) | Handkarten mit kräftigem dunklem Rand, gut abgesetzt (n_gross_tag, Ausschnitt am PC vergrößert). Die Nachtseite nur in den Kontrollbildern geprüft |
| S10 Lite gegen S21 | Beitreten, Bereit, Start klappt. Großer Modus quer: Hinweis über der Hand, Ecken von Stapel und Ablage frei, Zug gespielt (n_s10_gross_quer). Auf dem S21 kommt der Zug an (n_s21_gross_wlan) |
| Browser-Vibration | „Bei deinem Zug: Vibration“ steht ab Werk auf An (n_s10_vibration_an) |
| Lobby hochkant (S10) | Zeilen nutzen die volle Breite. Bei Schrift „Groß“ ragte „bereit“ rechts aus der Gastgeber-Zeile (n_s10_lobby_hochkant_gross), bei „Normal“ schrumpfte die Art zu „A..“ (n_s10_lobby_hochkant_normal). Behoben, siehe unten |
| logcat (App-Prozess S21) | keine Fehler (nur die Systemmeldung `AppWidgetSupplier` wie immer) |

## Behoben in diesem Durchgang

- **Lobby hochkant (`webclient/style.css`):** Unter 440 px Breite kürzt sich die Marke „Gastgeber“ mit „…“. In der Gastgeber-Zeile fällt die Angabe App/Browser weg. Am PC mit 390×844 bei Normal, Groß und Sehr groß geprüft: nichts ragt mehr heraus. Die Bilder sind nicht am Gerät entstanden, weil das S10 nach der Partie quer blieb und am Gerät nichts umgestellt werden darf.
- **`test_screens_flow`:** Die Zugschleifen hatten feste Fristen (40 s und 45 s). Jetzt verlängert jeder Fortschritt die Frist um 30 s, insgesamt höchstens 150 s. Ein echter Stillstand scheitert weiterhin. Außerdem spielt der Test mit offiziellen Regeln statt mit den zuletzt am PC gespeicherten; diese werden am Ende wiederhergestellt.
- **`test_net_rebind` / `net_session.gd`:** Der Fehler ließ sich nicht nachstellen (27 Läufe, davon 15 unter Last mit 6 parallelen Dauerläufen, alle grün). Vermutete Ursache: Windows gibt den Port nach dem Schließen nicht sofort frei, oder ein anderer Prozess belegt ihn. Deshalb versucht `rebind()` den alten Port jetzt bis zu viermal kurz hintereinander (25–100 ms), bevor es auf den Bereich ausweicht. Das hilft auch in der App. Der Test sucht sich zudem den ersten freien Port ab 24916 und gibt bei einem Fehler das Netzprotokoll aus.
- Version 1.2.1 in `game/project.godot` und `webclient/app.js`.

## Offen / für den Nutzer

- **App, großer Modus:** Der Hinweis „Du bist dran …“ liegt wie bisher über der unteren Ecke der Ablage (n_s21_gross_wlan). Im Browser ist das behoben, in `big_layout.gd` noch nicht. Niedrig.
- **App: „Bei deinem Zug: Vibration“** (`zug_vibration`) steht ab Werk weiter auf Aus. Ab Werk an ist nur der Browser, so steht es im Fahrplan.
- Die Lobby-Korrektur hochkant ist nur am PC geprüft, das S10 blieb nach der Partie quer.
- „Flip gelegt 4“ ließ sich nicht genau nachzählen, weil die Partie teils per Skript gespielt wurde. Plausibel ist der Wert.
- iPhone als Gast weiter ungetestet.
