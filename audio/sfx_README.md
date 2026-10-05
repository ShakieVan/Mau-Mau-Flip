# Spieltöne (außer „Mau!“)

Kurze Töne im Stil „Papier & Neon“: Papier für Karten und Mischen, weiche Glocken- und Marimba-Töne für Glanz, Sieg und „Du bist dran“.

**Herkunft:** synthetisch, eigenes Skript `tools/make_sfx.py` (numpy/scipy). Keine Aufnahmen, keine fremden Samples, keine KI-Generatoren. Das Rauschen kommt aus einem Zufallsgenerator mit festem Startwert, ein neuer Lauf ergibt dieselben Abtastwerte. Lizenz wie das Projekt (CC BY-NC 4.0).

**Niemand hat die Töne bisher gehört.** Bitte vor dem Release auf einem Handy-Lautsprecher anhören (siehe „Offene Punkte“).

## Töne

| Ton | Datei | Klang | Dauer |
|---|---|---|---|
| Karte legen | `karte` | weiches Papierklatschen: Rauschen 600–2400 Hz, dunkler Luftstoß, leiser tiefer Plopp 170 → 105 Hz | 117 ms |
| Karte ziehen | `ziehen` | weiches Gleiten: Rauschen durch einen wandernden Bandpass 450 → 1300 → 900 Hz, Tiefpass 2,4 kHz (kein Zischen), darunter ein sehr leiser Gleitton G4 → C5, am Ende ein leises Aufsetzen | 248 ms |
| Mischen | `mischen` | Riffle: 26 kleine Papierklapse in unregelmäßigen Abständen (≈ 85/s, keine Pulsfolge im Bereich 15–50 Hz), am Ende ein weiches Zusammenschieben | 400 ms |
| Flip | `flip` | Wusch, der hell aufgeht und dunkel schließt (Bandpass 350 → 1700 → 450 Hz), dazu ein kurzer Glanz A5 → E5 → C5 abwärts (a-Moll, Tag → Nacht) und ein leiser Gleitton D4 → A3 | 600 ms |
| Sieg | `sieg` | kleine Fanfare: Marimba G4 C5 E5 G5, dann C6 im Glockenspiel-Klang über C-Dur, Ausklang | 1,2 s |
| Fehler | `fehler` | weiches tiefes „nö“: stilisierte Stimme B3 → G3, Formanten n → ö (460/1350 Hz) | 150 ms |
| Du bist dran | `dran` | sanfter Zweiklang E5 → A5, Vibraphon-artig | 250 ms |

Ausgabe: `game/assets/sfx/<ton>.ogg` (Ogg Vorbis q6, Godot) sowie `webclient/sfx/<ton>.ogg` und `webclient/sfx/<ton>.m4a` (AAC 128 kbit/s, vor dem Kodieren Tiefpass 6 kHz und Kodierer-Grenze 6 kHz). `webclient/sfx/index.json` meldet dem Browser-Client die M4A-Dateien (AAC spielen alle Zielbrowser, auch Safari); fehlt eine Datei oder scheitert das Dekodieren, nimmt `ton.js` seinen eingebauten Synth-Klang.

## Neu erzeugen

```powershell
. E:\Draw2Race-AudioLab\env.ps1
& E:\Draw2Race-AudioLab\analyse\.venv\Scripts\python.exe tools\make_sfx.py
```

Die Werkstatt wird nur gelesen; das Skript schreibt keine Zwischendateien (ffmpeg bekommt die Abtastwerte über stdin, zum Messen dekodiert es über stdout). Danach in Godot importieren (`tools/godot_import.ps1`). Auf stdout stehen alle Messwerte als JSON und die Tabelle unten.

## Leitplanken (sinngemäß aus `audio/entwurf/mau/README.md`)

- **Tiefpass:** am Ende Butterworth 4. Ordnung vor- und rückwärts bei 5 kHz (zusammen 48 dB/Oktave). Rauschanteile haben zusätzlich einen Tiefpass 2,4 kHz (36 dB/Oktave).
- **Kein Piepen bei 3–4 kHz:** Teiltöne über 2,2 kHz werden weich ausgeblendet (über 2,6 kHz fehlen sie ganz). In den tonalen Klängen (Sieg, Fehler, Dran) liegt im Bereich 3–4 kHz weniger als −95 dB der Energie. In den Papierklängen ist dort nur breitbandiges Rauschen (−26 bis −32 dB Anteil), keine Spitze.
- **Kein Rauschen über 6 kHz:** Energie über 6/10/12 kHz höchstens −61/−80/−81 dB gegenüber gesamt (Grenze aus dem Mau-README: −30/−50/−60 dB), auch nach dem Kodieren.
- **Weicher Einsatz:** Kosinus-Anstieg, mindestens 1 ms je Klaps, 3 ms beim Kartenlegen, 6–7 ms bei den Glocken, 14 ms beim „nö“; weicher Ausklang, kein harter Schnitt, keine Schleife.
- **Pegel:** Bezug ist der Mau-Ton (Datei −18 LUFS, im Spiel bei „normal“ −6 dB → −24 LUFS). Die übrigen Töne spielen mit −8 dB. Ihre Dateien liegen bei −16 bis −19 LUFS, im Spiel also bei −24 bis −27 LUFS: Der Sieg ist so laut wie der Mau-Ton, alle anderen leiser, keiner lauter (Empfehlung aus der Mau-Prüfung). Die echte Spitze ist auf −4 dBTP begrenzt. Das Kartenlegen erreicht deshalb nur −22 LUFS; weil das Messfenster 400 ms lang ist, der Ton aber nur 117 ms dauert, wirkt er trotzdem etwa so laut wie die anderen.

## Messwerte

Gemessen vom Skript an den 16-Bit-Abtastwerten vor dem Kodieren und an den dekodierten Dateien. Dauer: Hüllkurve (2 ms) über −40 dB vom Höchstwert. Anstieg: erster Einsatz, von −40 dB bis 3 dB unter dem Höchstwert der ersten 60 ms. LUFS: höchste Momentan-Lautheit (400 ms, BS.1770). Handy: Lautheitsverlust mit Hochpass 800 Hz (12 dB/Oktave). 3–4 kHz: Energieanteil gegenüber gesamt / stärkste Spektralspitze im Band gegenüber der stärksten Spitze überhaupt.

| Ton | Dauer | Anstieg | LUFS (Ziel) | Spitze | RMS | Schwerpunkt | Handy | > 6/10/12 kHz | 3–4 kHz Anteil / Spitze | OGG > 6 kHz, Spitze | M4A > 6 kHz, Spitze |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `karte` | 117 ms | 2,8 ms | −22,2 (−18) | −4,2 dBTP | −17,0 dBFS | 673 Hz | −2,5 dB | −61/−80/−81 dB | −26,4 / −29,0 dB | −61,2 dB, −4,1 dBTP | −62,3 dB, −4,0 dBTP |
| `ziehen` | 248 ms | 34,9 ms | −19,0 (−19) | −5,0 dBTP | −17,7 dBFS | 1234 Hz | −1,1 dB | −84/−86/−86 dB | −28,9 / −22,7 dB | −89,7 dB, −4,7 dBTP | −94,8 dB, −5,0 dBTP |
| `mischen` | 377 ms | 27,1 ms | −18,0 (−18) | −4,7 dBTP | −19,1 dBFS | 1477 Hz | −0,6 dB | −61/−85/−85 dB | −32,2 / −31,7 dB | −60,6 dB, −4,8 dBTP | −61,6 dB, −4,7 dBTP |
| `flip` | 560 ms | 52,7 ms | −17,0 (−17) | −5,2 dBTP | −19,4 dBFS | 1330 Hz | −0,9 dB | −82/−84/−85 dB | −27,7 / −25,2 dB | −87,0 dB, −5,3 dBTP | −92,9 dB, −5,3 dBTP |
| `sieg` | 1162 ms | 4,5 ms | −16,0 (−16) | −6,1 dBTP | −18,1 dBFS | 681 Hz | −3,8 dB | −84/−85/−86 dB | −96,3 / −105,7 dB | −92,3 dB, −6,2 dBTP | −93,7 dB, −6,1 dBTP |
| `fehler` | 143 ms | 12,8 ms | −16,5 (−16,5) | −4,2 dBTP | −11,3 dBFS | 374 Hz | −12,2 dB | −92/−93/−94 dB | −104,5 / −109,6 dB | −111,8 dB, −4,0 dBTP | −74,9 dB, −4,2 dBTP |
| `dran` | 242 ms | 4,7 ms | −17,0 (−17) | −5,4 dBTP | −14,4 dBFS | 766 Hz | −3,6 dB | −88/−89/−90 dB | −99,9 / −109,8 dB | −98,4 dB, −5,3 dBTP | −77,2 dB, −5,4 dBTP |
| `mau_stimme` (Bezug) | 311 ms | 32,7 ms | −17,9 | −8,1 dBTP | −16,2 dBFS | 500 Hz | −7,4 dB | −98/−101/−104 dB | −80,2 / −84,0 dB | – | – |

Bemerkungen:

- Beim Ziehen, Mischen und Flip ist der „Anstieg“ das bewusst weiche Anschwellen (Gleiten, Riffle, Wusch), kein Knack.
- Der AAC-Kodierer legt bei den tonalen Tönen einen leisen Schleier über 6 kHz (−75 bis −77 dB), weit unter der Grenze. Godot nutzt die OGG-Dateien.
- Das „nö“ verliert auf einem Handy-Lautsprecher am meisten (−12 dB, tiefe Stimme); deshalb liegt seine Datei 1,5 dB über den anderen kurzen Tönen.

## Im Spiel (`game/scripts/app/sound.gd`)

- `App.sound.play(name)`; die übrigen Töne folgen der Einstellung `toene` (aus/leise/normal: −80/−16/−8 dB), der Mau-Ton `mau_ton` (aus/leise/normal: −80/−14/−6 dB) und `mau_klang`.
- Derselbe Ton startet innerhalb von 40 ms nur einmal; bis zu sechs Töne klingen gleichzeitig.
- Feinabgleich je Ton ohne neue Dateien: `TRIM_DB` in `sound.gd` (dB je Name).

## Offene Punkte

1. **Hörtest** auf einem Handy-Lautsprecher und mit Kopfhörern: Klingt das Kartenlegen nach Papier, nervt etwas beim 50. Mal, knackt etwas? Besonders `karte` und `ziehen` erklingen in jeder Partie sehr oft.
2. **Pegel auf dem Gerät** gegen den Mau-Ton abgleichen (Sieg = Mau, alle anderen leiser) und bei Bedarf `TRIM_DB` setzen.
3. Ein eigenes Motiv für „Mau-Mau!“ (höchstens 600 ms) gibt es noch nicht; bis dahin passt `sieg`.
