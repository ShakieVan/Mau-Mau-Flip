# Mau-Mau Flip — Projektkontext

## Stand

Am 04.10.2026 begonnen. Bisher Brainstorming und Recherche, noch kein Code. Ergebnisse in `docs/recherche/` (Einstieg: `docs/recherche/README.md`, dort auch die Korrekturen nach der Gegenprüfung). Schwesterprojekt und Vorlage ist Draw2Race (`C:\Users\Shakie\Documents\Programmierung\Draw2Race`, Godot 4.6.1).

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

## Erledigt in 0.1.3 (veröffentlicht 06.10.2026)

Tempo-Regler der Computergegner, vier Tauschrichtungen, „Farbe mit ablegen“ mit Auswahl, Ablegen-Joker mit getrennter Ablege- und Spielfarbe, kein Anzweifeln (Wünscher +2 und Farbjagd immer erlaubt, „App prüft“ freiwillig), „Computer spielt für …“ bei getrennten Gästen, N6–N8. Bericht: `docs/geraetetest/0.1.3/BERICHT.md`. Update 0.1.1 → 0.1.2 vom Nutzer bestätigt. Hörtest der Spieltöne durch den Nutzer steht weiter aus.

## Erledigt in 0.1.4 (veröffentlicht 06.10.2026)

Schein von hinten für den Spieler am Zug (ohne Kasten/Rand, erst nach dem Austeilen, Namen mit Kontur in der Gegenfarbe), Denkblase nach 5 s, eigene Kartenzahl, Flip-Überraschung (Hausregel), neue „Familie“ mit allen Zusatzkarten (alte Familie wird automatisch angehoben), Partiestart wie „Nächste Runde“, sanfte Strahlen am Rundenende, „?“ löst kein „Mau!“ mehr aus, Browser: Mond, Startbild, Rahmen statt „Bitte quer halten“. Gerätetest wurde wegen der Kranz-Korrektur abgebrochen; Kontrollbilder `docs/module/optik_014_*.png`.

## Offen für 0.1.6 (nach dem Release 1.0)

- **Ablage durchsehen** (Nutzerwunsch 06.10.2026, „damit Streitfragen aus dem Weg geräumt werden“): Tipp auf den Ablagestapel schiebt die oberste Karte zur Seite, Karte für Karte; Tipp auf den Seitenstapel schiebt eine zurück; Tipp irgendwo sonst schiebt alle zurück. Vorschlag: an jeder Karte steht, wer sie gelegt hat (und bei Jokern die gewünschte Farbe); Zähler „3 von 27“; legt jemand eine Karte, springt alles zurück. Gezeigt wird die Ablage, wie sie liegt (seit dem letzten Mischen; nach einem Flip gewendet). Verdeckte Glücksspiel-Einsätze unter der Ablage nur als Rückseite. App und Browser; die Sicht braucht dafür die öffentliche Ablage-Liste (kein Leck: die Ablage ist offen).

- **Schrift am Handy zu klein** (Nutzer, 06.10.2026). Vorschlag: (1) kleinste Texte (Beschreibungen, Hinweise, Pillen) allgemein größer; (2) Einstellung „Schriftgröße“ (Normal/Groß/Sehr groß) je Gerät. Dafür die bisher verstreut festgelegten Schriftgrößen zentral bündeln (z. B. in UiFonts) und alle Bildschirme samt Tisch per Bildschirmfoto-Tests in allen Stufen auf Überlauf prüfen. Kartenbilder bleiben unverändert. Laut Nutzer ist „gefühlt fast überall“ außer der großen Schrift zu klein; Extreme (Bilder in `docs/geraetetest/0.1.5/`, nur lokal): am Tisch „KI“-Abzeichen, „gleich dran“, Spielernamen, Kartenzahl-Pillen, „Stapel · 83“, Hinweisleiste („+1 auf dich – Zieh 2.“); in den Bildschirmen die grauen Beschreibungen (z. B. „Du sitzt unten …“) und die Regel-Kurzfassung unter „Regeln“.

## Empfehlung aus der Recherche

- Godot 4.6.1 mit Compatibility-Renderer, Host entscheidet allein, jeder Client bekommt nur seine Sicht. WebSocket mit JSON für App- und Browser-Mitspieler.
- Offline-Verteilung: Teilen-Menü (Quick Share) und eine Download-Seite auf dem Host. Für Hotel-WLAN mit Geräte-Isolierung ein Spiel-WLAN per LocalOnlyHotspot mit WLAN-QR.
- Einzelheiten: `docs/recherche/12_empfehlung.md`.
- Browser-Gäste kommen per http (`docs/recherche/17_https_empfehlung.md`): Alle Browser öffnen `http://<private IP>:<Port>` in der Grundeinstellung; echtes HTTPS gibt es offline nicht. Der Host weist TLS-Versuche (erstes Byte 0x16) sofort ab, leitet nie auf https um, nutzt einen festen Port > 1024 und liefert Seite und WebSocket möglichst über denselben Port (eigener kleiner WebSocket-Handshake in GDScript). QR-Code immer mit `http://` und Port, Adresse zusätzlich als Text. Alles offline ausliefern (keine CDN, keine Webfonts von außen). Standard für Browser-Gäste ist der schlanke Client; Godot-Web gilt als „experimentell“, bis es über http mit eigener Startseite, ohne Threads und mit Ton läuft. Das lässt sich mit Android-Browsern testen, weil die Secure-Context-Regeln überall gleich sind.

Diese Datei fasst den Kontext zusammen. Neuere Nutzeranweisungen haben Vorrang.
