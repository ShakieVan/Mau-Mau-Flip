# Beta 1.6.15 – Reaktionen, Zug-Ton, Doppeltipp, Natur, Browser-Tempo: Gerätetest (23.10.2026, 19:39–20:07)

Vorabbau `builds/MauMauFlip-1.6.15.apk` per `adb install -r` auf S21 (Gastgeber „S21“, Englisch) und S10 (Browser-Gast „Kim“ in Chrome, Deutsch); App-Daten behalten. Erster Bau mit allen 111 Testläufen grün, nach dem Fund unten zwei Schnellbauten ohne Tests (Fix Reaktionsleiste, Gast-Protokoll). Beide Handys entsperrt, Testschalter `MauMauFlipTestLock` nicht verändert (`INFO`), Heim-WLAN. Am S21 meldet SoundPool `25 Töne`.

## Ergebnis
1. **„Sound on your turn“ (S21, Übungsspiel):** Schalter unter Sound, nach den Spieltönen (g04). Ausgeschaltet: beim eigenen Zug kein `SfxPool: Ton dran`, Mischen, Karte und Ziehen spielen weiter. Am Ende wieder eingeschaltet.
2. **Doppeltipp auf den Stapel:** App (S21): drei Tipps in einem `input`-Befehl → genau 1 Karte (7 → 8, Stapel 82 → 81), keine Fehlermeldung. Browser (S10): zwei schnelle Tipps → genau 1 Karte (7 → 8, Stapel 97 → 96).
3. **Natur (S21, Vorführung 7 Tipps in den Himmel):** alle Tag-Ereignisse nacheinander, darunter **Hoppelhase** auf dem Tischrand (53 fps) und **Strand** mit Welle und Palme hinter dem Mau-Knopf (44 fps) (g01). Die Nacht-Ereignisse (Feuerwerk, Astronaut, UFO) nur auf den Kontrollbildern.
4. **Reaktionen im WLAN-Spiel (S21 App, S10 Chrome):** App: zehn Knöpfe als Block 5 + 5 neben dem eigenen Namen (g02 oben). Kim schickt 🤔 → am S21 `Ton hmm` (Aufnahme des Nutzers), S21 schickt 😘 → `Ton kuss`, Kim schickt 😴 → `Ton schnarchen`.
5. **Tempo-Messung:** `Gast 2 „Kim“: [web 1.6.15] Tempo: Antwort Ø 39 ms (max 39, n=1), Ping 19 ms, lange Aufgaben 0, Rückstau max 0` (Heim-WLAN; eine Minute vorher Ping 114 ms, 1 lange Aufgabe mit 50 ms beim Laden).

## Befunde (behoben)
- **Browser, großer Modus, kleines Handy (S10 Chrome, 760 × 360):** Für zehn Knöpfe passte kein Block; die Leiste stand als einfache Spalte am linken Rand, die unteren Knöpfe außerhalb des Bildes, der oberste unter dem Kameraloch. Nutzervorschlag „am linken Rand scrollbar machen“: **senkrecht wischbare Spalte** (44 px, sichtbar n½, unten ausgeblendet bis zum Ende; `wisch-v`), nur wenn keine andere Lage frei ist. Nutzerhinweis „da ist auch das Kamera-Loch“: Lagen am linken und rechten Rand beginnen jetzt hinter der Aussparung (Safe Area, `t.ox`/`t.or` wie die Bühne). Am S10 geprüft (g02 unten, g03: gewischt bis 😘, Ausblendung weg).
- **Tempo-Zeilen kamen nicht an:** Die App schrieb die `{t:"log"}`-Zeilen der Gäste nirgends hin (das Signal `log_line` der Sitzung ist nur in Tests verbunden). Jetzt zusätzlich `print` → `adb logcat -s godot`.
- Kleinere Handys quer im normalen Modus (unter etwa 800 × 360) behalten die waagerecht wischbare Reihe neben „Du“; 844 × 390 hat den Block 5 + 5 (36 px).

## Nicht geprüft
- Browser über das **Spiel-WLAN** (der Fall des Nutzers): das S10 hätte dafür das Heim-WLAN verlassen müssen (adb läuft über WLAN). Die Tempo-Zeile zeigt künftig im Protokoll des Gastgebers, ob es am Netz (Antwort, Ping) oder am Browser (lange Aufgaben, Rückstau) liegt.
- Nacht-Ereignisse und UFO am Gerät, iPhone, Hören (Medienlautstärke S21 1/15).

## Ende
App auf beiden Geräten beendet (force-stop), „Sound on your turn“ am S21 wieder an, Testschalter `INFO`, Heim-WLAN nie gewechselt, kein Neustart. Am S10 bleibt der Chrome-Tab mit dem Browser-Client offen. Bilder per `exec-out`, keine Dateien auf den Geräten.

| | |
|---|---|
| ![g01](g01.jpg) Hoppelhase auf dem Tischrand, Strand mit Palme hinter dem Mau-Knopf (S21) | ![g02](g02.jpg) App: Block 5 + 5; Browser, großer Modus: wischbare Spalte hinter der Aussparung |
| ![g03](g03.jpg) Spalte gewischt: Mitte und Ende (ohne Ausblendung) | ![g04](g04.jpg) „Sound on your turn“ |
