# Gerätetest Beta 0.1.1 – Nachtest Runde 1

06.10.2026, 07:08–08:14. Geprüft wurde `builds/MauMauFlip-0.1.1.apk` (Version 0.1.1, Code 1001, SHA-256 `d42670c0…cfe1cedc`, Build 06.10.2026 03:08 laut `MauMauFlip-0.1.1.build.json`). Installiert mit `adb install -r`, danach auf beiden Geräten `pm clear`. Die installierte APK hat auf beiden Geräten denselben SHA-256 wie der Build.

| Gerät | Android | Bildschirm | WLAN-IP |
|---|---|---|---|
| S21 (SM-G991B) | 15 | 2400×1080, 120 Hz | 192.168.178.8 |
| S10 (SM-G973F) | 12 | 2280×1080 (Override) | 192.168.178.9 |

Beide Geräte waren stumm und blieben es. Bedienung über `adb shell input` anhand von Bildschirmfotos. Die Belege liegen in diesem Ordner mit dem Präfix `n1_` (JPEG, halbe Auflösung). Den Code habe ich nicht geändert.

## Gesamturteil

**Veröffentlichungsreif: nein – noch nicht entscheidbar.**

Ich habe den Test um 08:13 abgebrochen, weil wieder fremde Eingaben auftauchten (siehe „Abbruch“). Dadurch ist der einzige hohe Mangel aus dem ersten Test, **H1 (WLAN-Spiel startet nicht), am Gerät nicht nachgeprüft**. Ohne diesen Nachweis kann ich die APK nicht freigeben.

Alles, was ich prüfen konnte, ist in Ordnung:

- M1 (Zurück-Taste), M2 (Wischen), M3 (Bildrate/CPU) und N1 („Bereit“ beim App-Gast) sind behoben.
- Die neuen Karten (Kartentausch, Glücksspiel, Farbe ablegen) laufen im Übungsspiel ohne Hänger, auch bei Tag und Nacht.
- Im Log stehen keine Abstürze, keine Skriptfehler und keine Warnungen der App.

Neu gefunden habe ich nur drei niedrige Mängel (N3–N5). Wenn H1 im Wiederholungstest besteht und dabei kein neuer hoher Mangel auftaucht, ist die APK aus meiner Sicht veröffentlichungsreif.

## Abbruch wegen fremder Eingaben

Laut Auftrag hatte ich die Handys allein. Trotzdem:

1. **S10, 07:20:35–07:29:34:** 55 echte Fingereingaben in die App (`InputDispatcher: Delivering touch` ohne zugehöriges `Inject motion`). Ich habe in dieser Zeit nur am S21 gearbeitet. Danach stand das S10 wieder im Hauptmenü. Meine eigenen Eingaben am S10 begannen erst um 08:08.
2. **08:10, Lobby des S21:** Ein Browser-Gast „Shakie“ trat bei (`n1_l12_s21_lobby_fremder_browsergast.jpg`, `n1_l13_s10_lobby_fremder_browsergast.jpg`).
   - Er kam von **192.168.178.4**: nicht der PC (.29), nicht S21 oder S10.
   - Die MAC-Adresse ist eine zufällige lokale Adresse, also vermutlich ein Handy.
   - Er lud die Seite frisch (mehrere HTTP-Verbindungen) und hielt eine WebSocket-Verbindung.
   - Ich hatte zu diesem Zeitpunkt keinen Browser gestartet, auch nicht den Chrome des S10.
3. **S21, 08:11:40:** eine echte Fingereingabe in die App. Danach war „Shakie“ aus der Lobby verschwunden (`n1_l14_s21_lobby_gast_wieder_weg.jpg`). Ob der Gast entfernt wurde oder selbst ging, ist offen.

Daneben erschien am S21 um etwa 07:35 die Systemmeldung einer Zwischenablage-Übernahme von einem anderen Samsung-Gerät. Auch das ist ein Hinweis, dass ein weiteres Gerät in der Nähe aktiv war.

Ich habe danach nichts mehr eingegeben und nicht versucht, den Gast zu entfernen oder sonst zu reagieren.

**Zustand am Ende:**

- S21: App läuft, Gastgeber-Lobby „Spiel eröffnen“ mit Sam und Ben, Regeln „Familie“ plus Glücksspiel und Farbe ablegen, Tauschrichtung „In Spielrichtung“.
- S10: App läuft als Gast „Ben“ in dieser Lobby.
- Chrome des S10: nicht benutzt.
- `adb reverse`: nicht gesetzt.

## Mängel

| Nr. | Schwere | Mangel | Stand |
|---|---|---|---|
| H1 | **hoch** | WLAN-Spiel startet nicht (Gastgeber-Server geht beim Start aus) | **nicht nachgeprüft** (Abbruch vor „Start“) |
| M1 | mittel | Zurück-Taste doppelt ausgeführt | **behoben** (Lobby mit Gästen nicht geprüft) |
| M2 | mittel | Kein Wisch-Bildlauf in Einstellungen und Regeln | **behoben** |
| M3 | mittel | ~40 fps und ~90 % CPU im Ruhezustand | **behoben** (S21: 60 fps gleichmäßig, ~40 % CPU) |
| N1 | niedrig | App-Gast: „Bereit“ nicht sichtbar | **behoben** |
| N2 | niedrig | Gastgeber-Lobby: Spielerliste ab 3 Spielern abgeschnitten | 3 Spieler ganz sichtbar; 5 und mehr nicht geprüft |
| N3 | niedrig | „gleich dran“ steht bei Spielern, die schon fertig sind | neu |
| N4 | niedrig | App-Gast: „Bereit ✓“ bleibt gedrückt, nachdem der Gastgeber die Regeln geändert hat | neu |
| N5 | niedrig | Nach der Namenseingabe mit „Enter“ liegt ein Grauschleier über der ganzen App | neu, Ursache unklar |

### N3 – „gleich dran“ bei fertigen Spielern (niedrig)

- **Beobachtung:** Mit „Bis zum Letzten“ zeigt die Nebenzeile „gleich dran“ einen Spieler, der schon fertig ist (Platzmarke, 0 Karten).
  - `n1_e25_s21_gegner_gluecksspiel_b.jpg`: Kater Karlo „4.“, 0 Karten, „gleich dran“.
  - `n1_e26_s21_gleich_dran_bei_fertigem.jpg`: Tiger „1.“, 0 Karten, „gleich dran“, während Socke am Zug ist.
- **Ursache:** `table_view.gd:445` setzt `next` auf `posmod(turn + dir, n)`. Fertige Spieler werden dabei nicht übersprungen; ebenso wenig wirken Aussetzen-Effekte.
- **Folge:** Nur eine falsche Vorschau, das Spiel selbst läuft richtig weiter.

### N4 – „Bereit ✓“ des App-Gasts nach Regeländerung (niedrig)

- **Beobachtung:** Der App-Gast (S10) drückte „Bereit“, danach änderte der Gastgeber die Regeln.
  - Der Gastgeber zeigt den Gast wieder als „App · verbunden“, also nicht bereit (`n1_l12`).
  - Die Liste des Gasts zeigt nur „App“.
  - Sein Knopf steht aber weiter auf „Bereit ✓“ (`n1_l13`). Um wieder bereit zu sein, muss der Gast zweimal tippen.
- **Ursache:** `NetHostSession.set_rules()` (`net_session.gd:248–253`) setzt `ready = false` für alle Gäste. `join_screen.gd` gleicht `_ready_btn` in `_on_lobby()` aber nicht mit dem eigenen `ready` aus der Lobby ab. Der Browser-Client tut das (`webclient/app.js:358–361`).
- **Folge:** Der Gastgeber kann trotzdem starten.

### N5 – Grauschleier nach der Namenseingabe (niedrig, Ursache unklar)

- **Ablauf:** „Im WLAN spielen“ → Namensfeld antippen → Name eingeben → Enter (`input keyevent 66`). Die Tastatur schloss sich, aber die ganze App blieb abgedunkelt (`n1_l01_s21_abgedunkelt_nach_eingabe.jpg`).
  - Der Schleier blieb auch in der Lobby, zurück im WLAN-Menü und im Hauptmenü. Die Bedienung funktionierte weiter.
  - Erst nachdem ich das Feld erneut antippte und die Tastatur mit Zurück bzw. mit der OK-Taste der Tastatur schloss, war das Bild wieder normal (`n1_l03_s21_tastatur_und_zurueck.jpg`, `n1_l05_s21_nach_ok_taste.jpg`).
- **Weitere Hinweise:**
  - Im abgebrochenen Versuch zeigt `r1_j10_s21_abgedunkelt_nach_ok.jpg` dasselbe.
  - SurfaceFlinger listete zwei „Dim layer“ der Systemoberfläche (uid 10050). Möglicherweise blieb also eine Abdunklung der Tastatur bzw. des Systems stehen und kommt nicht von der App.
  - Ob ein echter Fingertipp auf die Enter-Taste dasselbe auslöst, ist ungeprüft.

### Hinweise aus dem abgebrochenen Versuch

- **`r1_e23` (Meldung teilweise hinter den Gegnerkarten):** nicht nachgestellt. In den durchgesehenen Bildern und Bildfolgen mit Mau-Blasen und Hinweisen sah ich keinen Text hinter Karten. Einmal stand eine Mau-Blase links von Mimi mitten in der Animation verwischt; das halte ich für ein Zwischenbild.
- **`r1_j10` (abgedunkelt nach OK):** siehe N5.

## Ergebnis je Punkt

### 1. Installation und Start – bestanden

- `adb install -r`: „Success“ auf beiden Geräten. `dumpsys package`: `versionName=0.1.1`, `versionCode=1001`.
- Frischer Start nach `pm clear`: Hauptmenü auf beiden Seitenverhältnissen sauber (`n1_a01_s21_start.jpg`, `n1_a01_s10_start.jpg`).
- Log beim Start (beide Geräte):
  - „Mau-Mau Flip 0.1.1 (Android)“
  - Netzinfo
  - „Eigene APK: MauMauFlip-0.1.1.apk, 40415940 Bytes, SHA-256 d42670c0…“
  - „Updater: Noch kein passendes Release veröffentlicht. (Kanal Beta)“

### 2. Nachtest der Mängel aus BERICHT.md

#### H1 – nicht geprüft (Abbruch)

Bis zum Abbruch lief alles:

- **Lobby und `/info`:** Lobby mit QR-Code und Adresse `192.168.178.8:24690` (`n1_l02`, `n1_l06`). `/info` lieferte `{"name":"Sam","players":1,"port":24690,"running":false,"version":"0.1.1",…}`.
- **Beitritt der S10-App:**
  - Die S10-App fand „Spiel von Sam“ über die Suche (`n1_l07_s10_suche.jpg`) und trat bei.
  - Beide Lobbys stimmen überein (`n1_l08_s10_app_lobby.jpg`, `n1_l09_s21_lobby_mit_appgast.jpg`).
  - „Bereit“ ist sichtbar und wirkt (`n1_l10_s10_bereit.jpg`).
- **Regeländerung:** Die Änderung des Gastgebers (Familie + Glücksspiel + Farbe ablegen, 124 Karten) kam sofort beim Gast an („7 Handkarten“, „124 Karten · mit Kartentausch, Glücksspiel und Farbe ablegen“, `n1_l11`, `n1_l13`).

„Start“ habe ich nicht mehr gedrückt. Ebenfalls offen sind Mehrspieler-Runden, Rundenende, Trennen und Wiederverbinden während der Partie sowie der Browser-Gast im Chrome des S10 und am PC.

#### M1 – behoben

| Ort | Erwartet | Ergebnis | Beleg |
|---|---|---|---|
| Regeln, kurz | Hauptmenü | Hauptmenü | `n1_b03` |
| Einstellungen, kurz | Hauptmenü | Hauptmenü | `n1_b09` (links) |
| Einstellungen, lang | Hauptmenü | Hauptmenü, App bleibt offen | `n1_b08` |
| Regeln, lang | Hauptmenü | Hauptmenü, App bleibt offen | `n1_b09` (rechts) |
| Spiel, kurz | Rückfrage „Partie verlassen?“ | Rückfrage, einmal | `n1_h01` |
| Spiel mit offener Rückfrage | Rückfrage schließen | schließt, Spiel läuft weiter | `n1_h02` |
| Großansicht einer Karte | nur Großansicht schließen | nur Großansicht zu, keine Rückfrage | `n1_h03` |
| Spiel, lang | Rückfrage | Rückfrage, einmal | `n1_h05` |
| Tastatur offen (Namensfeld) | Tastatur schließen | nur Tastatur zu | `n1_l03` |
| Lobby mit Gästen | eine Rückfrage | nicht geprüft (Abbruch) | – |

Die App schloss sich kein einziges Mal ungewollt. „Verlassen“ in der Rückfrage führt ins Hauptmenü.

#### M2 – behoben

Senkrechtes Wischen über den Inhalt blättert:

- Regeln (`n1_b02_s21_regeln_gewischt.jpg`)
- Einstellungen, linke und rechte Spalte (`n1_b05`, `n1_b06`); auch zurück nach oben
- Regel-Editor des Übungsspiels bis zu den Hausregeln mit Zusatzkarten (`n1_c05_s21_zusatzkarten_an.jpg`)

#### M3 – behoben (S21)

Gemessen wie im ersten Test:

- **Bildrate:** `dumpsys SurfaceFlinger --latency` auf der SurfaceView-Ebene der App, je 2 s.
- **CPU:** `top -d 3`, zweiter Wert, % eines Kerns.

| Lage (Übungsspiel, 5 Computergegner) | Bilder/s | Bildabstand Mittel / max. | Bilder > 20 ms | CPU |
|---|---|---|---|---|
| Ruhezustand, Tag, eigener Zug | 60,0 | 16,7 / 16,9 ms | 0 | 41 % |
| Eigene +5 ausgespielt (Animation) | 60,2 | 16,6 / 41,7 ms | 2 | – |
| Gegner spielen, Animationen laufen | 60,0 | 16,7 / 25,0 ms | 0–1 | 35 % |
| Nacht, 18 Handkarten im Karussell | 60,0 | 16,7 / 25,0 ms | 2 | 45 % |

Vorher waren es 38 fps im Ruhezustand mit 16,7/25-ms-Wechsel und etwa 90 % CPU. Jetzt läuft die App bei 120 Hz Anzeige gleichmäßig mit 60 fps. Nur beim Ausspielen fällt gelegentlich ein Bild aus.

Speicher am Tisch: PSS 577 MB (Grafik 327 MB, Native Heap 172 MB). Das S10 habe ich am Tisch nicht gemessen.

#### N1 – behoben

In der Gast-Lobby des S10 blättert der Regeltext für sich, „Bereit“ steht ganz sichtbar darunter und schaltet auf „Bereit ✓“ (`n1_l08`, `n1_l10`).

#### N2 – teilweise geprüft

- Mit 3 Spielern (Gastgeber, App-Gast, Browser-Gast) sind alle Zeilen ganz sichtbar (`n1_l12`).
- Spielerzahl und „Computer −/+“ stehen in der Kopfzeile, die Regeln als eine Zeile mit Knopf unter der Liste (`n1_l09`).
- 5 Spieler und mehr habe ich nicht mehr geprüft.

### 3. Neue Karten im Übungsspiel – bestanden

**Aufbau:**

- **Erste Partie:** S21, 5 Computergegner, Voreinstellung „Familie“ (Kartentausch im Uhrzeigersinn, bis zum Letzten, Ziehkarten weitergeben, nach Strafziehen weiterspielen) plus Glücksspiel und Farbe ablegen. Das ergibt 124 Karten (`n1_c05`, `n1_c06`). Gespielt: Runde 1 bis Mau-Mau, Runde 2 bis zum Rundenende, Runde 3 kurz.
- **Zweite Partie:** 2 Computergegner, 10 Startkarten und „Bis eine passt“, damit ich selbst eine Glücksspielkarte bekomme.

Danach war jede neue Karte mehrfach im Spiel, selbst gelegt und bei Gegnern.

| Karte | Selbst gelegt | Bei Gegnern | Belege |
|---|---|---|---|
| Kartentausch | ja: Tausch ausgeführt, die neue Hand kommt an, Kartenzahlen danach stimmig (die Animation selbst ist auf meinen Standbildern zu spät erfasst) | ja, mehrfach: Banner „Kartentausch!“ mit Pfeilen, „Kater Karlo und Mimi tauschen die Hände.“ Luna legte ihn als letzte Karte; danach tauschten nur die beiden Übrigen, wie es die Regel verlangt | `n1_e14`–`n1_e16`, `n1_e21` |
| Glücksspiel | ja: Farbrad, „Leg eine Karte verdeckt auf deinen Einsatz.“, Karte antippen (hebt sie) und nochmals antippen (setzt sie), „Drück den Glücksspielknopf!“ | ja: Kater Karlo „Einsatz 1“ mit Wurf 0; Mimi mit „Treffer! 9“ | `n1_g01`–`n1_g08`, `n1_e24`, `n1_e21` |
| Farbe ablegen (farbig) | ja: „Du legst eine orange Karte mit ab.“, „Du legst 2 türkise Karten mit ab.“, „Du hast keine weitere pinke Karte.“ | ja: „Kater Karlo legt 5 rote Karten mit ab.“ | `n1_e21` |
| Farbe ablegen (Joker) | ja: Farbrad mit Anzahl je Farbe (z. B. „Pink ×8“), danach „Du legst 8 pinke Karten mit ab.“ mit Fächer-Animation | – | `n1_e09`, `n1_e10`, `n1_g09`–`n1_g11` |

Zum eigenen Glücksspiel im Einzelnen:

- „Los!“ ergab erst **0**: Einsatz bleibt, nächste Karte setzen (`n1_g03_s21_gluecksspiel_wurf0.jpg`).
- Dann **„Treffer! 1“**: 1 Karte ziehen, beide Einsatzkarten zurück, Zug vorbei (`n1_g04_s21_gluecksspiel_treffer.jpg`, `n1_g08`).

**Weitere Beobachtungen:**

- **Ablauf:** Flip Tag ↔ Nacht mehrfach ohne Hänger. „Mau!“-Knopf mit Blase (`n1_e17`), Fertigwerden mit „Mau-Mau!“ (`n1_e19`), Rundenende „bis zum Letzten“ mit Plätzen 1–6 und Konfetti (`n1_e20`), „Nächste Runde“.
- **Hand:** Karussell ab 16 Karten; die Glücksspielkarte habe ich aus dem Karussell gespielt.
- **Kartenhilfe:** Großansicht mit „?“ (`n1_h03`).
- **Eigene Rückseiten:** „Rückseiten“ halten zeigt sie.
- **Hänger und Kartenzahlen:** Keine Hänger. Stapel- und Handzahlen waren stimmig, soweit sichtbar; systematisch nachgezählt habe ich nicht.
- **Lesbarkeit:** Tag und Nacht gut lesbar, Eckindex auch auf den neuen Karten. Hinweise wie „Du bist dran – lege Pink oder eine Ablegen-Karte.“ und „Wünscher +2 auf dich – lege Wünscher +2 drauf oder zieh 2.“ passen ohne Überlauf.
- **Gegneranzeige:** Siehe N3.

**WLAN mit Browser-Gast (Lite) und den neuen Karten:** nicht geprüft (Abbruch).

### 4. „Spielbare Karten hervorheben“ – teilweise

- **App, ab Werk an** (Schalter in den Einstellungen, `n1_b05`): Spielbare Handkarten leuchten in der Farbe der Ablage, nicht spielbare nicht (z. B. `n1_g08`: die orangen Karten leuchten, die türkisen nicht).
- **Nicht geprüft:** Ausschalten in der App sowie die Einstellung im Lite-Client.

### 5. Weitergeben mit 2 Menschen + 1 Computergegner – nicht geprüft (Abbruch)

### 6. Spieltöne – bestanden, soweit stumm prüfbar

- „Spieltöne: Normal“ eingestellt (`n1_b11_s21_spieltoene_normal.jpg`).
- Während des Spiels hat die App in AudioFlinger eine aktive Ausgabe: Sitzung 521, 44,1 kHz Stereo, `USAGE_MEDIA`, OpenSL ES `state:started`, 0 Unterläufe.
- Im Log stehen keine Audiofehler.
- Einzelne `play()`-Aufrufe schreibt der Release-Build nicht ins Log, daher lassen sie sich nicht einzeln belegen.
- Die Geräte blieben stumm.

### 7. Log – bestanden

`logcat -b all` seit dem Start um 07:10 auf beiden Geräten, gefiltert nach `FATAL`, `Fatal signal`, `ANR`, `tombstone`, `SCRIPT ERROR` und `E/W godot`:

- **Treffer der App:** keine.
- **Sonstiges von der App:** nur Info-Zeilen (Start, Netz, Updater) sowie zwei Systemwarnungen ohne Bedeutung (GC-Histogramm, `InteractionJankMonitor`).

## Nicht geprüft (wegen Abbruch)

1. H1 vollständig:
   - S21 als Gastgeber, S10-App, Chrome-Gast auf dem S10 und Computergegner
   - Start und mehrere Runden bis zum Rundenende
   - nur die eigene Hand sichtbar; Ereignisse und Mau-Blasen auf allen Geräten
   - Sitzordnung am Tisch
   - `force-stop` und Wiederbeitritt eines Gasts während der Partie
2. Browser-Gast (Lite) mit Glücksspiel und Kartentausch: S10-Chrome und PC-Chrome headless mit `?autotest=1&pflicht=tausch,ablegen,gluecksspiel`.
3. „Spielbare Karten hervorheben“ aus (App) sowie an/aus im Lite-Client.
4. Weitergeben mit 2 Menschen + 1 Computergegner und den neuen Hausregeln: kein Sichtschutz-Dialog zeigt Karten.
5. Zurück-Taste in der Lobby mit Gästen; N2 mit 5 und mehr Spielern.
6. M3 auf dem S10.

## Hinweise zum Ablauf

- **adb-Verbindung:** Um 07:38 brach die adb-Verbindung zum S21 über `192.168.178.8:35829` ab. Ich habe über die mDNS-Verbindungen (`adb-R5CT…`, `adb-RF8M…`) weitergearbeitet, ohne am Gerät etwas einzustellen.
- **Beim Start nichts Fremdes aktiv:** Vor dem Start liefen keine fremden Skripte (`autoplay.sh` o. Ä.) am PC.
- **Unverändert:** Am Gerät wurde nichts eingestellt, nichts geteilt oder gesendet. Die App `de.shakie.wlandebugkeepalive` habe ich nicht angefasst.
- **Belege:**
  - Bildschirmfotos mit `screencap`, mit ffmpeg auf halbe Auflösung verkleinert.
  - Für Gegnerzüge lief zeitweise eine Bildfolge (alle 0,5–0,7 s) im Scratchpad; Auszüge davon sind `n1_e21` und `n1_e24`.
- **Vorgaben:** `audio/referenz/` und `.tools/` habe ich nicht verwendet bzw. nicht gelesen.

## Empfehlung

- Den Wiederholungstest erst starten, wenn sicher niemand sonst die Handys bedient. Für Browser-Gäste von anderen Geräten im WLAN gilt dasselbe.
- Dann die Punkte unter „Nicht geprüft“ abarbeiten, vor allem H1.
- N3–N5 sind niedrig und verhindern die Veröffentlichung nicht. N4 ist eine kleine Änderung in `join_screen.gd` (`_ready_btn` aus dem eigenen `ready` der Lobby setzen).
