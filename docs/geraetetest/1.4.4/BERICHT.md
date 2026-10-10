# Gerätetest Beta 1.4.4 – Ostereier Teil 1 (10.10.2026)

Gerät: S21 (SM-G991B), Heim-WLAN. APK `builds/MauMauFlip-1.4.4.apk` (SHA-256 1abdaa800fdf076c7915565aef42ffa380ef724364e241a143eb0c95debb5d34, 40,2 MB). `build.ps1 -Target Test -NoTestCache`: alle 77 Testläufe grün. S10 nicht benutzt, S24 nicht angefasst. Bilder `n_*.png`.

| Prüfung | Ergebnis |
|---|---|
| Hauptmenü: 7x schnell auf die Katze | OK, Funkeln über dem Bildschirm (n_01) |
| Einstellungen: „Sprüche Aus/Nett/Frech“ (Frech ab Werk), „Deine Titel“ in der Statistik | vorhanden (n_03); Titel-Hinweis „Noch kein Titel verdient“ |
| Übungspartie, Frech: Sprüche statt „Du bist dran“ | OK („Pokerface aufsetzen. Jetzt!“ n_11, „Kehrtwende! …“ n_20_b1) |
| Katze nach langem Warten | OK: schläft mit Zzz auf dem Ziehstapel (n_20_b12), Tipp scheucht sie weg (n_21) |
| Trödel-Spruch 15/30 s | nicht im Bild erwischt (Zeitfenster knapp); per Test abgedeckt |
| Stufe „Aus“/„Nett“ | nicht am Gerät, nur Test |
| logcat | keine Fehler der App |

## Mängel

- niedrig: Einstellungen, Zeile „Sprüche“: Beschreibungsspalte schmal, die Knöpfe Aus/Nett/Frech werden sehr hoch (n_03). Kosmetisch.
- niedrig: Autsch-Stempel und Autsch-Spruch können bei +5 auf die letzte Karte zusammenkommen (nicht gesehen).
- Browser-Sprüche nur per Vertragstest, kein iPhone/Browser-Bild.
