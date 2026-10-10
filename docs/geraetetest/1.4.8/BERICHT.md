# Beta 1.4.8 – Ton nach Telefonat (Gerätetest 10.10.2026)

## Befund

S24 (Android 16): „Wenn man die App kurz verlässt und telefoniert, geht danach der Ton nicht mehr.“ Früher einmal: Ton während
eines Telefonats über den Lautsprecher, ein anderes Mal gar keiner (Bluetooth-Kopfhörer im Etui verbunden).

## Ursache (Godot 4.6.1, Quellcode)

- Godot gibt auf Android über **einen** OpenSL-ES-Abspieler mit Puffer-Warteschlange aus (`platform/android/audio_driver_opensl.cpp`).
  Er wird beim Start einmal angelegt; jeder Rückruf reiht selbst den nächsten Puffer ein (`Enqueue`, Rückgabewert ungeprüft).
- Beim Verlassen der App ruft Godot nur `set_pause(true)` (SetPlayState PAUSED), beim Zurückkehren `set_pause(false)`
  (`os_android.cpp`, main_loop_focusout/focusin). Keine Behandlung von Audiofokus, Ausgabewechsel (Hörer, Bluetooth-SCO im Gespräch)
  oder Fehlern, kein Neuanlegen. Bleibt die Puffer-Kette einmal stehen, ist die App bis zum Neustart stumm.
- Aus GDScript lässt sich der Treiber nicht neu starten; `AudioServer.set_output_device` tut unter OpenSL nichts. Weg (a) entfällt.

## Nachstellung S21 (Android 15, ohne SIM)

Kleine Test-App (nur lokal gebaut, danach wieder entfernt): Audiofokus GAIN_TRANSIENT mit USAGE_VOICE_COMMUNICATION,
MODE_IN_COMMUNICATION, Ton über den Sprachkanal, wahlweise Lautsprecher. Drei Abläufe mit 1.4.7: App verlassen → „Gespräch“ 8/25/30 s
→ zurück; Gespräch läuft weiter, während die App vorn ist. Ergebnis jeweils: Godot-Ausgabe danach wieder `started`, Zähler läuft,
`mutedState:none`. **Der Fehler ließ sich ohne echtes Telefonat nicht auslösen** (echter Anruf: MODE_IN_CALL mit Telefonie-Routing,
beim Nutzer zusätzlich Bluetooth).

## Behebung (Weg b)

- Töne spielen auf Android über **SoundPool** (`SfxPool.java`): jede Wiedergabe mit frischer Ausgabe auf dem aktuellen Weg;
  zwei Fehlstarts eines geladenen Tons legen den Vorrat neu an. Pause/Fortsetzen bei Fokus weg/zurück wie bisher.
- `sound.gd`: Stufen, Lautstärken (dB → linear), Jubel-Zufall und -Sperre, 40-ms-Sperre bleiben; ist ein Ton noch nicht geladen,
  spielt Godot. Am PC und in Tests unverändert Godot.
- `tools/build.ps1` kopiert `game/assets/sfx/*.ogg` nach `game/android/build/res/raw/sfx_*.ogg` (in `.gitignore`).

## Prüfung

- `test_app_sound` mit Attrappe (Android-Weg), Gesamttest grün (77 Läufe), APK 1.4.8 gebaut.
- S21 mit 1.4.8: Logcat „SoundPool bereit: 11 Töne“; „Probehören Mau!“ meldet je Tipp `event:started` (SoundPool, USAGE_GAME),
  nach jedem nachgestellten Gespräch und während eines laufenden Gesprächs. Hören konnte ich es nicht.

## Offen

- Echter Anruf am S24 (mit und ohne Bluetooth) durch den Nutzer.
