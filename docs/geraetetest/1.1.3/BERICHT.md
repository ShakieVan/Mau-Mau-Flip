# Gerätetest Beta 1.1.3 (08.10.2026)

APK `builds/MauMauFlip-1.1.3.apk` (version/code 1001003, SHA-256 `f19561e5c69538a5e5d2a0b14faa05699abd34e2fc337e0b3e2f6cf3ff4f0b43`), Projektschlüssel, gebaut mit `build.ps1 -Target Android` (alle 60 Testläufe bestanden).
Geräte: S21 (SM-G991B, Gastgeber) und S10 (SM-G973F, Lite in Chrome), beide per drahtlosem adb.

## Ergebnis

| Bereich | Ergebnis |
|---|---|
| Familie: freiwillig ziehen | Mit spielbarer Hand gezogen (gelbe 9 passt nicht): Der Zug läuft weiter, „Behalten“ ist da, der Hinweis lautet „Passende Karte legen oder behalten?“, grüne +1 und Richtungswechsel sind markiert (n_1). Danach die +1 gelegt (n_2). „Behalten“ beendet den Zug |
| Großer Modus: Strafplakette | „+2“ liegt gut sichtbar über der Ablage, nichts verdeckt sie (n_2, zweimal geprüft) |
| Nachts im Spiel | Menü (n_3), Einstellungen (n_4), Regeln mit der neuen Hausregel (n_5) und die Kartenhilfe per Geste (n_6) sind dunkle Karten mit heller Schrift |
| Rundenende, Rückfrage, Kartenhilfe nachts | am PC mit echtem Renderer geprüft, siehe n_7 (`test_ui_overlay_night_shot.gd`) |
| S10: Lite gegen S21 | Lite läuft nachts mit Neon-Fenstern (n_8). Selbsttest `?gross=1&autotest=1&pflicht=beliebig&zuege=12`: **OK** (12 Züge, 0 Ablehnungen, beliebig=1, behalten=2) (n_9). Ein längerer Lauf vorher: 67 Züge, 0 Ablehnungen, beliebig=9, behalten=3. Er endete nur deshalb mit Zeitüberschreitung, weil der Gastgeber nicht mehr weitergespielt hat |
| logcat (App-Prozess S21) | keine Fehler |

## Behoben in diesem Durchgang

- **Nachts dunkel:** Kartenhilfe (`help_popup.gd`), Rundenende (`round_end_view.gd`) und die Rückfrage „Partie verlassen?“ (`confirm_box.gd`, nur am Tisch) sind jetzt ebenfalls dunkel. Die Knöpfe darin werden dann cremefarben, denn der dunkle Knopf „Verstanden“ war auf der dunklen Karte kaum zu sehen (n_6, vor der Korrektur). Das Kontrollbild-Skript erzeugt diese Bilder mit.
- **Hinweis kürzer:** In der Phase drawn heißt es jetzt „Passende Karte legen oder behalten?“, passend zum Lite-Schein-Gastgeber. Der lange Text wurde im großen Modus gekürzt.
- **Regel-Kurzbeschreibung** (Übungsspiel, Lobby): nennt jetzt auch „nach dem Ziehen beliebige Karte legen“ (`rules_bar.gd`).
- **`run_webtest.sh`:** neuer Lauf `beliebig` (`&beliebig=1&pflicht=beliebig`). Alle 10 Läufe am PC sind ok.
- Version 1.1.3 in `project.godot` und `webclient/app.js`.

## Offen / für den Nutzer

- Die Strafplakette am Gerät nur auf der hellen Seite gesehen (+1/+2). Nachts liegt sie im selben Knoten.
- Die Rückseiten-Ansicht (`backs_viewer.gd`) hat keine Papierkarte und war schon vorher dunkel.
- Der Selbsttest von Lite wartet nach dem Laden höchstens 15 s auf den Tisch. Am echten Gastgeber muss man deshalb rasch auf „Start“ tippen.
