# Beta 1.6.7 – Necken-Menü und „Erwischt!“-Buzzer, kurzer Gerätetest (16.10.2026, 07:20–07:31)

APK `builds/MauMauFlip-1.6.7.apk` (43 693 584 Bytes, SHA-256 94b2f11a…30ff86) per `adb install -r` auf S21 (Gastgeber „S21“, Englisch) und S10 (Gast „Kim“, Deutsch); App-Daten behalten, beide melden `SoundPool bereit: 20 Töne` und dieselbe Prüfsumme. Gesperrt (Testschalter `MauMauFlipTestLock` war schon `VERBOSE`, so belassen), Heim-WLAN, neue Partie mit Bot „Minka“ (Offiziell). Bilder 960 px breit, 256 Farben.

## Ergebnis
1. **Menü bleibt offen, schließt nach 15 s:** Kopf-Tipp am S10 auf S21 (am Zug), danach Bildserie ohne Tipp. Aufnahme bei 11,9–13,5 s nach dem Tipp: Menü offen (Schnarchen/Wecker aktiv); bei 14,0–15,7 s noch offen; bei 16,2–18,0 s zu (g01: oben ≈ 12 s, unten ≈ 17 s). Passt zu `MENU_IDLE_S = 15`.
2. **Zugwechsel bei offenem Menü:**
   - S21 öffnet das Menü auf Kim, während Kim am Zug ist (> 10 s): Schnarchen und Wecker aktiv (g02 oben). Kim legt Blau 6 → Menü bleibt offen, Titel „Kim · 7 cards“ aktualisiert, Schnarchen/Wecker grau mit „Only when it's Kim's turn.“ (g02 unten).
   - Am S10 umgekehrt belegt: Menü auf S21, während Kim am Zug ist → Schnarchen/Wecker grau, „Erst, wenn S21 dran ist.“ (in g03 nicht enthalten, Rohbild w2).
   - Bot: Menü am S10 auf Minka geöffnet (g03 oben, „Minka · 6 Karten“), danach zogen S21 und spielte Minka – Menü über zwei Zugwechsel offen, Kartenzahl auf „5 Karten“ aufgefrischt (g03 unten). Bei Bots gibt es kein Schnarchen/Wecker (wie bisher).
3. **Buzzer über offenem Menü:** S21 öffnet das Menü auf Kim, Kim legt ihre vorletzte Karte (Rot 5) ohne „Mau!“. Am S21 erscheint der rote „Caught!“-Buzzer groß neben Kims Platz, über der Menüblase; das Menü bleibt offen (g04 oben, ≈ 0,6 s danach). Ein Tipp auf den Buzzer erwischt (Stempel „Caught!“/„Erwischt!“ auf beiden Geräten, roter Rand am S10, Menü zu; g04 unten); Kim bekommt 2 Strafkarten (1 → 3). Minka hat nicht vorher erwischt.
4. **Log:** keine `SCRIPT ERROR`, `USER ERROR`, `E godot` oder `FATAL` auf beiden Geräten.

## Befunde
- Keine Fehler.
- Beobachtung (niedrig, nicht neu geprüft): Nach dem Ausspielen per Wischen am S10 kurz der Hinweis „Du bist gerade nicht dran.“ (Rohbild y1) – vermutlich das Ende der Wischgeste nach dem Legen; nicht weiter untersucht.

## Nicht geprüft
- Buzzer ohne offenes Menü in 1.6.7 (nur mit Menü), mehrere Erwischbare gleichzeitig, großer Modus/Nacht am Gerät.
- Senden eines Necken-Effekts nach dem Zugwechsel aus dem offen gebliebenen Menü; Hören (gesperrt, nur Log); Lite/iPhone.

## Ende
App auf beiden Geräten beendet (force-stop; Partie ist als „Partie fortsetzen“ gespeichert, wie vor dem Test eine ältere). Testschalter unverändert `VERBOSE`. Heim-WLAN nie gewechselt, kein Neustart. Keine Dateien auf den Geräten (Bilder per `exec-out`).

| | |
|---|---|
| ![g01](g01.png) Menü offen ≈ 12 s, zu ≈ 17 s (S10) | ![g02](g02.png) Zugwechsel: aktiv → grau (S21) |
| ![g03](g03.png) Bot-Menü bleibt über Zugwechsel offen (S10) | ![g04](g04.png) Buzzer über dem Menü, Tipp erwischt |
