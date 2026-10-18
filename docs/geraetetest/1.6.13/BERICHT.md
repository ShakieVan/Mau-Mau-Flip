# Beta 1.6.13 – Stift, „Heulen“ und „Facepalm“, Gerätetest (18.10.2026, 14:30–15:01)

Vorabbau `builds/MauMauFlip-1.6.13.apk` (42,3 MB, SHA-256 a2b89ba6…915682289, alle 111 Testläufe grün) per `adb install -r` auf S21 (Gastgeber „S21“, Englisch) und S10 (Gast „Kim“, Deutsch); App-Daten behalten, beide melden `SoundPool bereit: 23 Töne`. **Töne „Heulen“ und „Facepalm“ vorläufig** (MOSS `heulen_02` = waeh_frau_7206, `facepalm_01`). Danach gewählt: die Aufnahmen des Nutzers, +6 Halbtöne (`heulen_nur6`, `facepalm_nur6`) – im Spiel nur automatisch geprüft (Dateien, Längen, Gleichlauf App/Browser), nicht am Gerät gehört. Nicht gesperrt (Testschalter `MauMauFlipTestLock` auf `INFO`, nicht verändert), Heim-WLAN. Den Stift stellt `adb shell input stylus tap|swipe` nach (Quelle SOURCE_STYLUS, Werkzeug TOOL_TYPE_STYLUS – Godot behandelt das wie den S Pen als Maus).

## Ergebnis
1. **Fehler nachgestellt (1.6.9, S21, Übungsspiel):** Stift-Tipp auf eine Handkarte hebt sie nicht an, Stift-Wisch nach oben legt sie nicht (weiter 7 Karten, „Your turn“). Knöpfe gehen mit dem Stift (Zurück, „Practice game“, „Let's go“) – genau der Befund des Nutzers. Gegenprobe: derselbe Wisch mit `input touchscreen` legt die Karte (g01 oben: nach dem Stift-Wisch unverändert).
2. **Mit 1.6.13 (S21, Übungsspiel):** Stift-Tipp hebt die gelbe 7 an, Stift-Wisch nach oben legt sie (9 → 8 Karten, g01 unten). Stift halten (1,4 s) öffnet die Großansicht mit „?“, Stift-Tipp auf „?“ die Kartenhilfe „Green 6“ (g02). Finger danach unverändert: Wisch legt die grüne 6 (8 → 7).
3. **Reaktionen im WLAN-Spiel (S21 Gastgeber, S10 Gast):** Auf beiden Geräten stehen die sieben Reaktionen als Block 4 + 3 neben dem eigenen Namen. S21 schickt „Heulen“ per **Stift** → am S10 steigt 😭 am Platz von S21 auf; S10 schickt „Facepalm“ → am S21 steigt 🤦 bei Kim auf (g03). Ton auf beiden Geräten laut Log (`SfxPool: Ton heulen … Ton facepalm`; am S10 Medienlautstärke 0/15, daher nur im Log).
4. **Log:** keine `SCRIPT ERROR`, `USER ERROR`, `E godot` oder `FATAL`.

## Befunde
- Keine Fehler.

## Nicht geprüft
- Echter S Pen (S24 Ultra des Nutzers, nur nach Absprache): `input stylus` erzeugt dieselbe Quelle und dasselbe Werkzeug; Hover (S Pen schwebt über dem Bildschirm) und die Stifttaste sind nicht nachgestellt. Der Stift legt an der Hand jetzt alles, was der Finger kann (Tipp, Wisch nach oben, Halten, „?“, Wischen im Karussell und Umsortieren laut `test_ui_hand_pen.gd`).
- Applaus bei „Mau-Mau!“ mit dem neuen Klatsch-Bild am Gerät (nur Kontrollbilder `docs/module/optik_1613_applaus_*.jpg`); großer Modus und Browser-Client am Gerät; Hören (Medienlautstärke).
- Endgültige Töne „Heulen“ und „Facepalm“ (Wahl des Nutzers).

## Ende
App auf beiden Geräten beendet (force-stop). Testschalter `INFO`, Heim-WLAN nie gewechselt, kein Neustart. Keine Dateien auf den Geräten (Bilder per `exec-out`). Im WLAN lief nebenher eine Partie des Nutzers („Spiel von Shakie“, 1.6.12) – nicht angefasst.

| | |
|---|---|
| ![g01](g01.png) Stift-Wisch: 1.6.9 nichts (oben), 1.6.13 gelegt (unten) | ![g02](g02.png) Stift halten: Großansicht, „?“ → Kartenhilfe |
| ![g03](g03.png) Heulen (per Stift, am S10) und Facepalm (am S21) | |
