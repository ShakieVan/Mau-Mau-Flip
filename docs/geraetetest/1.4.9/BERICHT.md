# Beta 1.4.9 – Ablege-Joker per Tipp (Gerätetest 10.10.2026)

Wunsch: Das erste Farbrad (Ablegefarbe) des Ablege-Jokers entfällt; stattdessen auf eine Karte der Farbe tippen.

## Bau
- Version 1.4.9. Gesamttest (-NoTestCache): alle 79 Läufe grün. APK `builds/MauMauFlip-1.4.9.apk`, SHA-256 741f86f5a19556f7365dc8ede321926d23f68cc3eb9abc10609f71cecdc53558, Signatur Projektschlüssel.

## S21 (Android 15), Übungsspiel „Familie“, Tag
- Ablege-Joker legen: kein Farbrad, Hinweis „Tippe auf eine Karte der Farbe, die du mit ablegen willst.“ mit „Zurücknehmen“ und „Weiter“ (n_27).
- Tipp auf blaue Karte: alle 4 blauen Karten hervorgehoben, „Ablegen (4)“, Hinweis „… in Blau …“ (n_28).
- Eine Karte abgewählt: „Ablegen (3)“ (n_29).
- Farbe wechseln per Tipp auf grüne Karte: Auswahl wechselt auf Grün, „Ablegen (5)“ (n_32).
- Ablegen: normales Farbrad „Mit welcher Farbe geht es weiter?“ (Grün ×0 gezählt) (n_33); Rot gewählt, Hand 31 -> 26, Spielfarbe Rot (n_34).
- logcat: keine Fehler.

## Nicht am Gerät geprüft
- „Zurücknehmen“ (nur Test; kein zweiter Ablege-Joker gezogen), Ablege-Joker ohne farbige Karten, Flip-Überraschung, Nachtseite, großer Modus (Kontrollbilder `docs/module/optik_149_ablegen_tippen.png`).
- Browser auf dem S10 nicht geprüft (Lite-Autotests laufen im Mock).
- Handgröße wurde zum Testen kurz auf 10 gestellt und danach wieder auf Familie (7) gesetzt.
