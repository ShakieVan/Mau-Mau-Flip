# Mau-Mau Flip — Projektkontext

## Stand

Am 04.10.2026 begonnen. Stand 20.11.2026: Beta 1.6.20 (14.11.2026, `ShakieVan/Mau-Mau-Flip-Beta`), letztes Release 1.6.0 (11.10.2026, `ShakieVan/Mau-Mau-Flip`). Godot 4.6.1 mit Compatibility-Renderer. Schwesterprojekt und Vorlage ist Draw2Race (`C:\Users\Shakie\Documents\Programmierung\Draw2Race`).

Wo was steht:
- **`docs/VERLAUF.md`:** was in welcher Version kam, mit Nutzerbefunden, Einzelentscheidungen im Wortlaut und Gerätetests (stand bis 20.11.2026 hier). **Neue Einträge „Erledigt in Beta …“ kommen dorthin**, nicht hierher. Diese Datei behält nur dauerhafte Entscheidungen, Arbeitsregeln und Offenes.
- `docs/BETA1_PLAN.md`: Schnittstellen-Vertrag (Kartenschlüssel, Regeln, Sichten, Netzprotokoll). Wird bei Protokolländerungen mitgepflegt, `test_net_away` liest ihn.
- `docs/module/*.md`: Modulberichte und Entwürfe (Regeln `A.md`, `kontern.md`, `uebergabe.md`, `eastereggs2.md`, `natur.md`, `raum_behalten.md` …), Kontrollbilder siehe `docs/module/BILDER.md`.
- `docs/TESTS.md` (Bau und Tests), `docs/geraetetest/<Version>/BERICHT.md`, `docs/release_notes/<Version>.md`, `docs/online/ENTWURF.md`, `docs/recherche/` (Einstieg `README.md`, dort auch die Korrekturen nach der Gegenprüfung).

## Festgelegt (Nutzerentscheidungen 04.10.2026)

1. **Name:** „Mau-Mau Flip“. Kartenspiel nach den Regeln mit doppelseitigen Karten (helle und dunkle Seite, Flip-Karte wendet alles). Ansagen „Mau!“ (letzte Karte) und „Mau-Mau!“ (fertig).
2. **Keine Markenelemente des Vorbilds:** Der Name des Originalspiels erscheint nirgends (App, Store-Texte, Repo); kein schräges weißes Oval, kein Logo, keine nachgeahmte Kartengestaltung. Regeln und Spielmechanik dürfen übernommen werden.
3. **Veröffentlichung nur auf GitHub,** nicht im Play Store:
   - `ShakieVan/Mau-Mau-Flip` (öffentlich): Quellcode und reguläre Releases.
   - `ShakieVan/Mau-Mau-Flip-Beta` (öffentlich): nur Testversionen, README und LICENSE wie bei `Draw2Race-Beta`.
4. **Lizenz:** CC BY-NC 4.0 wie Draw2Race (`LICENSE`).
5. **Anforderungen:**
   - Mehrspieler „Weitergeben“ (ein Handy, Hand nur für den aktuellen Spieler sichtbar) und „Netzwerk“ (WLAN), wie bei Draw2Race.
   - Update-Funktion in der App wie bei Draw2Race (Release- und Beta-Kanal).
   - Der Host gibt die APK ohne Internet an Geräte in der Nähe weiter (Urlaub mit schlechtem Netz).
   - Mitspieler ohne App (vor allem iPhone) spielen im Browser mit; Link per QR-Code und an Geräte in der Nähe. Der Nutzer hat kein iPhone und keinen Mac.
   - Hand sortierbar und „fancy“ scrollbar.
   - Der Host legt die Sitzordnung fest; jedes Gerät zeigt die anderen in der richtigen Richtung.
   - Karten nahe am Original, aber mit eigenen, auffälligen Effekten (z. B. Joker-Strahlen aus der sichtbaren Kontur, animierter Richtungswechsel).
   - Optionale Hausregeln, z. B. bis zum Letzten spielen.

## Festgelegt (Nutzerentscheidungen 04.10.2026, zweite Runde)

6. **Browser-Gäste bekommen beide Clients:** Godot-Web-Export (volle Optik) und schlanker HTML/TypeScript-Client („Lite“). Der Gast wählt auf seinem Gerät; scheitert Godot-Web, schaltet er auf Lite um. Ein eigenes iPhone zum Testen gibt es nicht und wird nicht angeschafft; iPhone-Tests nur über Cloud-Geräte, Simulator-CI und Freunde.
7. **Android-Entwicklerverifizierung (2027):** vorerst abwarten, nichts registrieren.
8. **Querformat.** In der Hand ist nur der obere Teil der Karten sichtbar; der Eckindex oben links muss das tragen.
9. **Paketname** `de.maumauflip.game` (endgültig).
10. **Signatur:** eigener Release-Schlüssel `.tools/maumauflip-release.keystore` (RSA 4096, Alias `maumauflip`, 50 Jahre gültig), Passwort in `.tools/maumauflip-release.properties`. Beides ist per `.gitignore` ausgeschlossen und muss außerhalb des Projekts gesichert werden. Ohne diesen Schlüssel sind keine Updates mehr möglich. Der Build bricht ab, wenn er fehlt.
11. **Hand:** Fächer bis 7 Karten, Lupe beim Darübergleiten bis 15, ab 16 Bogen-Karussell mit Schwung, Einrasten und Gummiband.
12. **Sortieren:** alle Modi anbieten: Farbe, Wert, Punkte, manuell; Automatik an/aus.
13. **Eigene Rückseiten:** Ein Spieler kann seine Hand kurz umdrehen und die eigenen Rückseiten durchsehen.
14. **Rückseiten der Mitspieler** als globale Regeloption: sichtbar (offiziell) oder verdeckt („unter dem Tisch“). Vorgeschlagen zusätzlich „wie am echten Tisch“ (Fächer in Handreihenfolge, nur teilweise sichtbar), damit man z. B. Joker-Rückseiten verdecken kann. Sind Rückseiten sichtbar, öffnet ein Tipp auf eine Gegnerhand eine vergrößerte Ansicht zum Durchblättern.
15. **Weitergeben-Dialoge** zeigen keinerlei Karten, auch keine Rückseiten.
16. **Gestaltung:** Leitmotiv Tag/Nacht mit „Mau-Katze“. Logo: erwachsen-süße Katze, die mit der Pfote auf ihr offenes Maul zeigt und „Mau“ sagt, dahinter links eine helle Karte (Sonne), rechts eine dunkle (Mond); Schriftzug „Mau-Mau Flip“. Pose-Referenz: `art/referenz/katze_pose_entwurf.png` (Stil dort noch zu kindlich). Kartendesign zuerst, dann ins Logo übernehmen. Drei Entwurfsrichtungen in `art/entwurf/`.
17. **Gewählt: Richtung A „Papier & Neon“** (`art/entwurf/a-papier-neon/`, Generator `quelle/`, Neuaufbau mit `bash quelle/build.sh`). Logo und App-Symbol zeigen die KI-Illustration des Nutzers (`katze_mau.png`, Original und Montage in `art/referenz/`). Spiegelungen stehen mittig unter Sonne bzw. Mond. Werte mit Bricolage Grotesque bei fester optischer Größe `opsz 12`, damit 6 und 9 nicht zu dünn werden.
18. **Regelhilfe per Geste:** Karte gedrückt halten (Großansicht), dann nach unten auf ein erscheinendes „?“ ziehen. Es öffnet sich eine kurze Hilfe zu genau dieser Karte, passend zu den aktiven Hausregeln. Gesten: halten + nach oben = ausspielen, halten + seitlich = umsortieren, halten + nach unten = Hilfe.
19. **„Mau!“-Knopf** spielt ein süßes Mauzen, das echte Katzen weder anlockt noch verwirrt (Entwürfe in `audio/entwurf/mau/`).
20. **Mau-Töne sind die Aufnahmen des Nutzers** (05.10.2026): „Mao“ für „Mau!“ und „Mao-Mao“ für „Mau-Mau!“, aufbereitet mit `tools/make_mau_aufnahmen.sh` (Originale in `audio/aufnahmen/`, Stärke „mittel“ im Spiel). Die synthetischen Mau-Varianten klangen dem Nutzer „schrecklich“ und entfallen.
21. **Mau ist für alle hör- und sichtbar** (05.10.2026, ersetzt die Recherche-Empfehlung „nur das eigene Gerät“): Der Ton spielt auf **allen** Geräten (außer der Ton ist dort abgeschaltet). Zusätzlich erscheint beim rufenden Spieler eine witzig animierte Sprechblase „Mau!“; es gibt mehrere Animationsvarianten, die zufällig gewählt werden. So sieht man es auch ohne Ton.
22. **Hausregeln Ziehkarten** (05.10.2026): „Ziehkarten stapeln“ (gleiche Karte drauflegen, Summe wandert weiter; offiziell nicht erlaubt) und neu „Nach dem Strafziehen weiterspielen“ (`penalty_turn = play`: wer +1, +5, Wünscher +2 oder Farbjagd abbekommt, zieht und ist danach trotzdem dran; offiziell setzt er aus). Beide sind in der Voreinstellung „Familie“ an.
23. **Kartentausch-Karte** (05.10.2026, Hausregel `swap_cards`, Standard aus): 4 zusätzliche Karten (Deck 116), hell je eine in Rot/Gelb/Grün/Blau, dunkel je eine in Pink/Türkis/Orange/Lila. Wer sie legt, lässt alle ihre ganze Hand weitergeben – im Uhrzeigersinn oder als Option in Spielrichtung (`swap_direction`). Wer dadurch auf 1 Karte kommt, muss nicht „Mau!“ rufen; als letzte Karte ist der Leger fertig.
24. **„Spielbare Karten hervorheben“** ist eine persönliche Einstellung je Gerät (an/aus), nie eine Regel, die der Gastgeber vorgibt.
25. **Kartentausch in „Familie“** (05.10.2026): Die Voreinstellung „Familie“ schaltet den Kartentausch ein.
26. **Glücksspielkarte** (05.10.2026, Hausregel, Standard aus): Joker (passt immer, je 2 pro Seite, beim Legen Farbe wählen). Danach legt der Spieler reihum eine beliebige Karte verdeckt auf seinen Einsatz und drückt den Glücksspielknopf. Je Glücksspielkarte wird geheim eine Trefferquote zwischen 1:1 und 1:10 ausgelost; bei einem Treffer zeigt der Generator 1–10 (gleich wahrscheinlich): so viele Karten ziehen und alle verdeckten Karten zurücknehmen, Zug vorbei. Bei 0 weiter (nächste Karte verdeckt, wieder drücken), bis die Hand leer ist (fertig, mit „Mau!“/„Mau-Mau!“) oder ein Treffer kommt. **Aufhören** (06.10.2026, immer erlaubt, keine Option): Nach mindestens einem Druck ohne Treffer darf der Spieler statt weiterzusetzen aufhören; der Einsatz kommt unter den Ablagestapel, der Zug ist vorbei. Das ist der Nervenkitzel: noch eine Karte riskieren oder aufhören, bevor die Hand voll wird.
27. **„Farbe mit ablegen“-Karte** (05.10.2026, Hausregel, Standard aus): je Seite 4 farbige (eine je Farbe) und 2 bunte Joker. Wer sie legt, legt alle eigenen Karten dieser Farbe (Joker: gewählte Farbe) mit ab; Joker auf der Hand bleiben. Mitabgelegte Aktionskarten wirken nicht. Oben bleibt die Ablegen-Karte.
28. **Alle neuen Karten kommen in Beta 0.1.1** (Nutzerentscheidung): Veröffentlichung erst, wenn Kartentausch, Glücksspiel und Farbe ablegen fertig und auf den Geräten geprüft sind.
29. **Browser-Client folgt Tag/Nacht wie die App** (06.10.2026, Nutzerbefund): Die Tagseite des Tisches ist hell (Papier, Sonne, helle Plattform, dunkle Schrift), nicht dunkelblau; nur die Nachtseite ist dunkel.
30. **Regelsätze** (06.10.2026, Nutzerwunsch): Eigene Regeln lassen sich unter einem Namen speichern, laden, überschreiben und löschen. App-Gäste merken sich die Regeln des Gastgebers automatisch („Zuletzt gespielt bei …“) und können sie als eigenen Satz speichern, damit ein anderer mit denselben Regeln weitermachen kann, wenn der Gastgeber gehen muss.
31. **Glücksspiel-Treffer als Hausregel** (25.10.2026, Nutzerbefund „Das Glücksrad macht viel zu oft "0". Unsere Einstellung ist zu hoch.“, gewählt „als Hausregel wählbar“): Option `gamble_odds` „Glücksspiel-Treffer“ – „Selten“ (geheime Quote 1:1 bis 1:10 wie bisher, im Mittel 71 % Nullen; Standard außerhalb von „Familie“, damit eigene Regelsätze unverändert spielen), „Mittel“ (bis 1:5, 54 % Nullen; in „Familie“, alte Familie-Sätze werden gehoben), „Oft“ (bis 1:3, 39 % Nullen). Gilt nur mit Glücksspiel. Ältere Gastgeber losen weiter bis 1:10. Einzelheiten `docs/module/A.md` (Abschnitt Glücksspiel). Erledigt in Beta 1.6.16 (veröffentlicht 25.10.2026); am Gerät nur die Regelzeile geprüft. Die drei Stufen ersetzt seit 07.11.2026 der Regler (Nr. 32).
32. **Glücksspiel-Treffer als Regler** (07.11.2026, Nutzerwunsch „Bitte die Einstellungen der Glücksspieltreffer von "1:3" bis "1:10" mittels Regler "stufenlos" einstellbar machen.“): Regelschlüssel `gamble_max` (Obergrenze der geheimen Quote, 3–10, Standard 10, „Familie“ 6 – Nutzer 07.11.2026 „Mach den Standard bei Familie bitte auf 1:6“; Familie-Sätze mit „Mittel“ und ältere Familie werden gehoben, angezeigt wird bei einem Gastgeber 1.6.16–1.6.18 weiter bis 1:5, womit er lost) statt der drei Stufen. Regler im Regel-Editor von „oft“ (bis 1:3) bis „selten“ (bis 1:10), rastet bei jeder ganzen Quote ein (die geheime Quote ist immer 1:q mit ganzem q; Zwischenwerte würden die bisherigen Anteile verändern), daneben „bis 1:7“ und „im Mittel 63 % Nullen“. `gamble_odds` steht abgeleitet weiter in den Regeln (3 oft, 4–6 mittel, 7–10 selten), damit ältere Gäste eine passende Stufe zeigen; Stufen von Gastgebern, Regelsätzen und Spielständen 1.6.16–1.6.18 werden zu 3/5/10. Computergegner und Statistik je Obergrenze (alte Stufen-Zähler werden übernommen), Browser-Client liest `gamble_max`. Einzelheiten `docs/module/A.md` (Abschnitt Glücksspiel), Kontrollbilder `docs/module/optik_gluecksspiel_regler_*.jpg` (`game/tests/test_gluecksspiel_regler_shot.gd`). Alle 114 Testläufe grün. Erledigt in Beta 1.6.19 (veröffentlicht 07.11.2026); nicht am Gerät geprüft.

## Weitere Festlegungen (Kurzfassung)

Getroffen beim Bau der jeweiligen Version; Wortlaut und Begründung im Verlauf. Vor Änderungen an einer dieser Funktionen dort und im passenden `docs/module/*.md` nachlesen.

- **Ab Werk:** Spieltöne „normal“, Hinweis bei „Nicht stören“ ohne Medien (1.5.1); Vibration beim eigenen Zug an, App und Browser (1.2.1/1.2.2); „Bei deinem Zug: Ton“ eigens abschaltbar (1.6.15); Sprüche „frech“ und „Oft“ (1.4.4/1.4.5); Necken an (1.6.3).
- **Töne:** Aussetzen = Schnurren `schnurren3_03` (1.3.4); Jubel `jubel_1`/`jubel_2` per Zufall statt Sieg-Ton (1.4.2); Easter-Egg- und Reaktionstöne wie in 1.6.3 bis 1.6.15 gewählt. Heulen, Facepalm, Hmm und Küsschen sind Aufnahmen des Nutzers. **Kein Gähnen** (steckt an, Nutzer 15.10.2026).
- **Reaktionen:** feste Bilder aus Microsoft Fluent Emoji „Color“ (keine System-Emojis, kein Noto), als direkte Knöpfe; Reihenfolge Lachen, Klatschen, Daumen hoch, Schreck (Nutzer 15.10.2026), dahinter die späteren; Block 5 + 5 (1.6.5 bis 1.6.15).
- **Feier am Partie-Ende:** 5 s Regen über die ganze Breite, dann 5 s Ausrieseln; tagsüber Konfetti, nachts Funkelsterne (App `SparkleShowerFx`, Browser fünfzackig) (1.3.4 bis 1.4.2).
- **Necken:** Papierkugel jederzeit (auch an Bots), Schnarchen und Wecker nur an den Spieler am Zug ab 10 s, Furzkissen geheim oder mit Namen (Zufallssperre 1–3 min, die Restdauer kennt nur der Leger); das Menü schließt erst nach 15 s ohne Tipp, nicht bei Zugwechsel; „Erwischt!“ als großer roter Buzzer (1.6.3 bis 1.6.10, `docs/module/eastereggs2.md`).
- **Joker:** keine Farbfelder um die Ablage, immer das Farbrad nach dem Legen (1.6.16). Ablege-Joker: Ablegefarbe durch Antippen einer Handkarte, danach ein Farbrad für die Spielfarbe (1.4.9).
- **Strafziehen:** `penalty_turn = play` bleibt trotz des Befunds „bei +2 bekommt man 3“, dagegen nur Doppeltipp-Schutz (1.6.15).
- **Kontern:** Regeln und Nutzerentscheidungen in `docs/module/kontern.md` (1.6.11 bis 1.6.16).
- **Online:** Der Raumcode bleibt nach dem Verlassen für Gastgeber und Gäste (`docs/module/raum_behalten.md`, 1.6.16). Gastgeber-Übergabe: Jeder App-Gast hält den Spielstand (`docs/module/uebergabe.md`, 1.6.1/1.6.2).
- **Natur:** seltene Bild-Ereignisse ohne Ton in App und Browser (`docs/module/natur.md`); das UFO lässt sich nicht verscheuchen (1.6.17).
- **Bedienung:** „Regeln ansehen“ und „So geht's“ bleiben doppelt (☰ und Zurück-Menü, 1.1.3); Statistik nur in den Einstellungen, kein Hauptmenü-Knopf (1.2.1); Abwesenden-Dialog hinter dem gelben „…“-Knopf (1.6.17).
- **Begriff:** „Easter Eggs“ sagen, nicht „Ostereier“ (Nutzer 15.10.2026; alte Datei- und Ordnernamen bleiben).

## Arbeitsregeln

### Bauen und Veröffentlichen

- Bauen mit `tools/build.ps1 -Target Test|Windows|Android|Web|Relay|All`. Tests, Testcache, Spuren, wackelige Läufe und Kontrollbilder: `docs/TESTS.md`. Schalter `-NoTestCache`, `-Parallel n`, `-SkipTests` (nur Probebauten). Godot-Läufe sperren `Global\MauMauFlipGodot`; einzelne Läufe über `tools/godot_run.ps1` bzw. `tools/godot_import.ps1`.
- Veröffentlichen mit `tools/release.ps1` (braucht `docs/release_notes/<version>.md`): erst committen und pushen, dann Release; das Skript legt den Tag an. **Nie starten, während ein Agent im Arbeitsbaum ändert** (1.3.5: Bau mit halb fertigen Änderungen, Tests rot, Abbruch).
- **Tags sind unveränderlich:** Der Vermittler holt `/c/<version>/` vom Tag `v<version>` und speichert es bis zu 1 Jahr (Cloudflare und Browser). Tags nur beim Veröffentlichen setzen. Vorabtests über den echten Vermittler mit einer Versionsnummer, die danach übersprungen wird.
- Ältere APKs liegen in den GitHub-Releases; lokal steht in `builds/` nur der aktuelle Bau (aufgeräumt am 20.11.2026).
- Kontrollbilder kommen als JPEG ins Repo (`docs/module/BILDER.md`).

### Texte und Sprache

- Neue Texte immer mit `I18n.t`/`M.t` und Eintrag in der passenden .po (`game/i18n/en_*.po`, msgid = deutscher Text, Glossar `game/i18n/GLOSSAR.md`); `test_i18n` prüft streng auf Lücken. Im Browser entsteht `webclient/i18n_po.js` beim Bauen aus den .po. Hinweise im Protokoll tragen `lt` (Bausteine), `text` bleibt deutsch für ältere Geräte.

### Testhandys und Geräte

- **Reservierung** über die zentrale Seite „Testhandy-Reservierung“; Ablauf in `C:\Users\Shakie\.claude\CLAUDE.md` (gilt für alle Sitzungen).
- `adb` liegt nicht im PATH: `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`. Geräte per `adb devices -l` nach Modell ansprechen (drahtloses Debugging, wechselnde Ports): SM-G991B = S21 (Android 15), SM-G973F = S10 (seit 14.11.2026 LineageOS 23.2, Android 16), SM-S928B = S24 (Gerät des Nutzers, **nur nach Absprache**), SM-P200 = Galaxy Tab A mit S Pen (Android 9, nur erreichbar, wenn der Nutzer es per USB ansteckt).
- **S21 und S10 stehen für Tests vollständig zur Verfügung** (Nutzer 10.10.2026), auch WLAN-Wechsel (z. B. ins Spiel-WLAN des anderen Handys) und Neustarts per `adb reboot` (Nutzer 09.10.2026; danach ist das WLAN-Debugging meist aus, bis der Nutzer es einschaltet). Nach Tests den Ausgangszustand wiederherstellen (normales WLAN). Nichts senden oder teilen, keine Konten. Chrome darf dort die Vermittler-Adresse öffnen (Nutzer 08.10.2026).
- **Gesperrt testen** (der Nutzer lässt S21 und S10 oft gesperrt liegen; Sperren schaltet das WLAN-Debugging nicht ab): `adb shell setprop log.tag.MauMauFlipTestLock VERBOSE`, dann `adb shell am start -n de.maumauflip.game/com.godot.game.GodotAppLauncher` – die App erscheint über dem Sperrbildschirm, das Handy bleibt gesperrt. Gesperrt nicht möglich: Chrome/Lite, QR-Scanner, Systemdialoge. **Nach jedem Test `setprop log.tag.MauMauFlipTestLock INFO`**, sonst verschwinden z. B. die Installationsdialoge hinter der Sperre. Das Entsperrmuster gibt der Assistent nie ein. Weitere Befunde (WLAN-Wechsel im gesperrten Zustand, Skripte per nohup, Neustart nach 72 h) im Verlauf unter Beta 1.1.2.
- Das Necken-Menü schließt nach 15 s ohne Tipp: Kopf und Knopf möglichst in einem Befehl tippen. Stift nachstellen mit `adb shell input stylus tap|swipe`.

### Töne

- Spieltöne entstehen als Kandidaten mit MOSS-SoundEffect; der Nutzer wählt per Hörseite. Nichts aus `audio/referenz/` verwenden (Fremdmaterial). Nie aus Stücken zusammenschneiden (Jubel Runde 2 klang „staccatomäßig“), sondern in einem Stück erzeugen. Kein Ton darf echte Katzen anlocken oder verwirren (Nr. 19).
- Aufnahmen des Nutzers liegen in `audio/aufnahmen/` und werden mit `tools/make_mau_aufnahmen.sh` bzw. `tools/make_reaktion_aufnahmen.py` aufbereitet (Reaktionen in Stufe `nur6`: +6 Halbtöne bei gleicher Länge).
- **GPU:** Auf beiden GPUs läuft oft LM Studio (`llama-server`, je ~17 GB). Vor MOSS-Läufen `nvidia-smi` prüfen. LM Studio darf dafür beendet werden (Nutzer 16.10.2026), danach nicht selbst neu starten; sonst nur mit Speichergrenze (`tools/make_ostereier.py --vram`).

### Vermittler (Online-Spiel)

- `https://mau-mau-flip-relay.shakie.workers.dev` (Cloudflare Worker mit Durable Objects, Gratistarif, Konto des Nutzers), Standard in `NetProtocol.RELAY_DEFAULT`. Code in `relay/`; Änderungen müssen in die Kopie im GitHub-Konto des Nutzers nachgezogen werden (Workers Builds stellt dann neu bereit). Konten anlegen und Zugangsdaten eingeben macht nur der Nutzer.

## Offen

Gesammelt aus dem Verlauf, jeweils mit der Version, in der der Punkt zuletzt als offen stand. Vor dem Bearbeiten im Code prüfen, ob er noch besteht.

- **Glücksspiel-Treffer am Handy messen** (1.6.18): Der Nutzer zweifelt die Quote weiter an. Entscheiden kann erst der Zähler unter „Deine Statistik“ nach etwa 50 Glücksspielen. Nicht als erledigt abtun.
- **Godot-Web-Client** (volle Optik für Browser-Gäste, Nr. 6): nicht gebaut; laut Fahrplan Teil von Release 1.7 (Gastgeber-Übergabe und Easter Eggs Teil 2, die dazugehörten, sind fertig).
- **Draw2Race** hat denselben Updater-Fehler auf Android 9/10 (`Updater.java`, Signaturabfrage), nicht korrigiert (1.6.20). Mau-Mau Flip bis 1.6.19 muss dort einmal von Hand installiert werden.
- **Nie geprüft:** iPhone als Gast (WLAN, online, Lite), Android 10, das In-App-Update auf Android 9 ab 1.6.20, mobile Daten am Gast (keine SIM), Android 16+ mit Spiel-WLAN und gleichzeitig online bzw. nur mit Mobilfunk (S24, nur nach Absprache).
- **Nicht am Gerät geprüft** (nur automatisch oder per Kontrollbild): Natur-Überraschungen (1.6.12/1.6.15), verlorene Aktionen beim App-Gast (1.6.16), Abwesenden-„…“, Reaktionsknöpfe im großen Modus und UFO (1.6.17), Glücksspiel-Regler (1.6.19), Kontern-Sonderfälle (1.6.13 bis 1.6.16), Lite im Spiel-WLAN und QR-Scanner nach „lost“ (1.6.2).
- **Nicht gehört:** mehrere Töne nur im Protokoll geprüft (Schnurren, Jubel, Easter Eggs, neuere Reaktionen); Spieltöne nach einem echten Anruf am S24 (1.5.1).
- **Kleine Fehler (niedrig):** eigene aufsteigende Reaktion startet am S10 teils hinter der Denkblase (1.6.5); `OpponentSeat.add_card` ohne Schutz für das Flugende in einem langen Bild (1.6.17); großer Modus der App: „Du bist dran“ überdeckt die untere Ecke der Ablage (1.2.1); Spiel-WLAN bleibt nach „Lobby schließen“ bzw. Verlassen offen, Dialog „Lobby schließen?“ zählt getrennte Gäste als verbunden (1.4.3); Ladehinweis nachts kurz hell, Gegnerfarben wechseln mit der Platznummer, Dazuholen in Weitergeben/Übung fehlt (1.4.2); HTTP-Fehler- und APK-Hinweisseiten des Gastgebers nur deutsch, Sprachwahl im Browser nicht auf der Startseite (1.2.2).
- Play-Protect-Warnung (Fahrplan nach Release 1.2.0).

## Empfehlung aus der Recherche

- Godot 4.6.1 mit Compatibility-Renderer, Host entscheidet allein, jeder Client bekommt nur seine Sicht. WebSocket mit JSON für App- und Browser-Mitspieler.
- Offline-Verteilung: Teilen-Menü (Quick Share) und eine Download-Seite auf dem Host. Für Hotel-WLAN mit Geräte-Isolierung ein Spiel-WLAN per LocalOnlyHotspot mit WLAN-QR.
- Einzelheiten: `docs/recherche/12_empfehlung.md`.
- Browser-Gäste kommen per http (`docs/recherche/17_https_empfehlung.md`): Alle Browser öffnen `http://<private IP>:<Port>` in der Grundeinstellung; echtes HTTPS gibt es offline nicht. Der Host weist TLS-Versuche (erstes Byte 0x16) sofort ab, leitet nie auf https um, nutzt einen festen Port > 1024 und liefert Seite und WebSocket möglichst über denselben Port (eigener kleiner WebSocket-Handshake in GDScript). QR-Code immer mit `http://` und Port, Adresse zusätzlich als Text. Alles offline ausliefern (keine CDN, keine Webfonts von außen). Standard für Browser-Gäste ist der schlanke Client; Godot-Web gilt als „experimentell“, bis es über http mit eigener Startseite, ohne Threads und mit Ton läuft. Das lässt sich mit Android-Browsern testen, weil die Secure-Context-Regeln überall gleich sind.

Diese Datei fasst den Kontext zusammen. Neuere Nutzeranweisungen haben Vorrang.
