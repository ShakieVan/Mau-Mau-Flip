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

## Empfehlung aus der Recherche

- Godot 4.6.1 mit Compatibility-Renderer, Host entscheidet allein, jeder Client bekommt nur seine Sicht. WebSocket mit JSON für App- und Browser-Mitspieler.
- Offline-Verteilung: Teilen-Menü (Quick Share) und eine Download-Seite auf dem Host. Für Hotel-WLAN mit Geräte-Isolierung ein Spiel-WLAN per LocalOnlyHotspot mit WLAN-QR.
- Einzelheiten: `docs/recherche/12_empfehlung.md`.
- Browser-Gäste kommen per http (`docs/recherche/17_https_empfehlung.md`): Alle Browser öffnen `http://<private IP>:<Port>` in der Grundeinstellung; echtes HTTPS gibt es offline nicht. Der Host weist TLS-Versuche (erstes Byte 0x16) sofort ab, leitet nie auf https um, nutzt einen festen Port > 1024 und liefert Seite und WebSocket möglichst über denselben Port (eigener kleiner WebSocket-Handshake in GDScript). QR-Code immer mit `http://` und Port, Adresse zusätzlich als Text. Alles offline ausliefern (keine CDN, keine Webfonts von außen). Standard für Browser-Gäste ist der schlanke Client; Godot-Web gilt als „experimentell“, bis es über http mit eigener Startseite, ohne Threads und mit Ton läuft. Das lässt sich mit Android-Browsern testen, weil die Secure-Context-Regeln überall gleich sind.

Diese Datei fasst den Kontext zusammen. Neuere Nutzeranweisungen haben Vorrang.
