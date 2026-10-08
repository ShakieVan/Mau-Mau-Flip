# Gerätetest Beta 1.3.4 (08.10.2026), kurz

**Aufbau:** nur S21 (SM-G991B, Android 15), `install -r`. APK `builds/MauMauFlip-1.3.4.apk`, SHA-256 `4420d9f460f401a342eb61c39d2d283968d1c0054f1dfd708c739b33f09369e3`, Projektschlüssel, Version 1.3.4 (Code 1003004).
**Tests:** `build.ps1 -Target Test -NoTestCache`: alle 70 Läufe grün (test_web_contract 421 ok, test_i18n grün).

| Schritt | Ergebnis |
|---|---|
| Installation, Start | Hauptmenü zeigt „Version 1.3.4“ |
| Spieltöne auf „Normal“ (vorher „Aus“) | Einstellung greift |
| Übungspartie mit 1 Computergegner (Regeln Offiziell) | Zug, Ziehen, Legen ok |
| Richtungswechsel-Karte gelegt (bei 2 Spielern wie Aussetzen) | Gegner zeigt Schlaf-Anzeige (Skip-Ereignis), das Schnurren wird dabei ausgelöst; logcat ohne W/E/F von godot, keine Abstürze |
| Spieltöne zurück auf „Aus“ | wiederhergestellt, App beendet |

**Nicht geprüft:** Das Schnurren ist nicht gehört worden (kein Hörtest am Gerät möglich), Partie-Ende mit Sternen/Konfetti nicht auf dem Gerät gesehen (nur Kontrollbilder `docs/module/optik_134_partieende_*.png`), Browser-Client nicht auf einem Gerät, Browser-Nacht-Lobby und Hochformat offen. Im Browser bleibt die Lobby nach einer Nachtpartie dunkel (bewusst offen).
