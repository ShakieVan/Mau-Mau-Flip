# Modul „Easter Eggs Teil 2: Necken“ (Beta 1.6.3)

Stand 15.10.2026, Entwurf, überarbeitet nach der Gegenprüfung (15 Befunde, alle übernommen; gewählte Lösungen und nicht gewählte Alternativen in Abschnitt 11). Nutzerwunsch (10.10.2026): Braucht jemand zu lange, können die anderen bei ihm etwas auslösen, z. B. ein langes **Schnarchen** oder einen **Wecker**, der 3 s abläuft und dann klingelt. Dazu angenommen: **schnelle Reaktionen** an den ganzen Tisch (😂 😱 👏 👍) mit Sperrzeit und eine **Papierkugel**, die mit Flugbahn und Plopp auf einen Mitspieler fliegt. **Gähnen entfällt** (Nutzer 15.10.2026).

Oberbegriff in der Oberfläche: **„Necken“**. Teil 1 (`fun_fx.gd`, `fun_texts.gd`, `spass.js`) bleibt rein lokal. Teil 2 ist das erste Easter Egg, das über das Netz geht. Es ändert **nie** den Spielstand: kein `rev`, kein Speicherstand, keine Sicherung (`bk`), kein Einfluss auf Bots, Züge oder Statistik.

## 1. Was, wann, an wen

| Art (`k`) | Ziel | Wann | Sperren (prüft der Gastgeber) |
|---|---|---|---|
| `snore` Schnarchen | nur der Spieler am Zug, nie man selbst, nur Menschen | Ziel ist am Zug und hat seit **10 s** nichts getan (`FX_SLOW_MS = 10000`) | je Sender und Zug des Ziels einmal; je Ziel läuft höchstens eine Weckaktion |
| `alarm` Wecker | wie Schnarchen | wie Schnarchen | wie Schnarchen (eigene Art, d. h. Schnarchen und Wecker je einmal) |
| `ball` Papierkugel | jeder andere Platz, auch Computergegner | jederzeit während der Partie (nicht am Rundenende) | Eimer je Sender 2, +1 je 5 s; am selben Ziel frühestens 1,5 s nach dem letzten Treffer |
| `react` Reaktion `r` ∈ `lachen`, `schreck`, `klatschen`, `daumen` | der ganze Tisch | jederzeit, auch am Rundenende | Eimer je Sender 3, +1 je 3 s |

Für alle Arten zusammen gilt am Tisch ein Eimer mit 8 und +4 je s. Der schützt den Vermittler, falls viele gleichzeitig senden.

**Begründungen:**
- **10 s:** Die Denkblase erscheint nach 5 s (`OpponentSeat.THINK_AFTER`). Necken soll erst kommen, wenn die Blase schon eine Weile steht. Die Mau-Katze (25 s) und der Trödel-Spruch (`SLOW_OTHER` 25 s) bleiben später. „Zug“ heißt jede Phase, in der `current_seat()` handeln muss: turn, drawn, color, challenge, gamble, discard_pick. Die Uhr beginnt neu, wenn `current` wechselt oder das Ziel selbst eine Aktion schickt, genau wie die Denkblase (`_poke`). Beim Gastgeber zählt eine Aktion des Ziels nur, wenn `_apply(...)` sie annimmt und dabei ein Ereignis mit dem Platz des Ziels entsteht. Das ist genau der Fall, in dem auch die Gäste `_poke` sehen. Abgelehnte Aktionen (`_err`, keine Sicht) setzen keine Uhr zurück, sonst lehnte der Gastgeber still ab, was beim Gast erlaubt aussah.
- **Einmal je Zug:** Wer ohnehin lange überlegt, soll nicht unter Dauerbeschuss stehen. Zwei Mitspieler können ihn aber je einmal wecken, nacheinander. „Höchstens eine Weckaktion“ heißt: Schnarchen 4,5 s bzw. Wecker 5 s lang nimmt der Gastgeber für dieses Ziel keine zweite an.
- **Keine Bots als Ziel von Schnarchen/Wecker:** Bots trödeln nicht absichtlich, und die Aktion hätte keinen Adressaten. Die Papierkugel darf Bots treffen, das ist harmloser Spaß für alle. Der Bot antwortet mit „Mpf!“ (wie die weggeschobene Katze).
- **Kein Ziel ist,** wer getrennt ist, „kurz in einer anderen App“ (`away`), von einem Computer vertreten wird (`_substitute`) oder Necken ausgeschaltet hat (Abschnitt 5). Diese Regeln gelten für Schnarchen, Wecker und Ball. Er bekäme es nicht mit, oder er will es nicht.
- **Absender:** jeder Mensch am Tisch, auch fertige Spieler („bis zum Letzten“, `place > 0`, die gerade Zeit haben). Nicht absenden können Wartende (Warteliste), Bots (sie necken nie) und Plätze, die ein Computer vertritt.
- **Dazuholen/Entfernen** (`seats`-Ereignis, `MauGame.insert_player/remove_player`, `_remap`): Platznummern verschieben sich. Deshalb leert der Gastgeber dabei den `TeaseRules`-Zustand der Partie (`sent`, `busy_until`, Eimer, Zugbeginn), und jedes Gerät räumt in `TeaseFx` die Effekte je Platz ab (liegende Kugeln, Z, Wecker, Mütze). Ummappen lohnt sich für Effekte von wenigen Sekunden nicht. Ein offenes Necken-Menü schließt sich.
- **Weitergeben (`pass`):** nichts. Alle sitzen am selben Handy, und die gezeigte Hand wechselt. Ein Menü am Gegner wäre dort nur verwirrend. Ein Tipp verhält sich wie bisher.
- **Übung (`solo`):** nur die Papierkugel auf Computergegner, lokal ohne Netz (LocalTable). Sie kostet fast nichts, lässt sich gut testen und wirkt gegen Langeweile. Schnarchen, Wecker und Reaktionen hätten dort keinen Empfänger.

## 2. Bedienung (App und Lite gleich)

**Gegner antippen:**
- **Kopf (Avatar, Name, Kartenzahl)** → kleines **Necken-Menü** am Platz (Sprechblase mit Zipfel zum Avatar). Titel „Kim · 5 Karten“ (bei einer Karte „Kim · 1 Karte“: App mit den vorhandenen msgids `%d Karte`/`%d Karten` wie `round_end_view.gd`, Lite `kartenText(p.count)`), darunter runde Symbolknöpfe:
  - **Papierkugel**
  - **Schnarchen**
  - **Wecker**: nur beim Spieler am Zug. Vor 10 s sind sie ausgegraut, darunter steht „Erst, wenn Kim eine Weile überlegt.“
  - **Karten ansehen**: nur, wenn die Rückseiten sichtbar sind.
  Ein Tipp daneben schließt das Menü, und **der Tipp wirkt normal weiter** (wie beim Durchsehen der Ablage). So bleiben Mau-Knopf, Ziehstapel und Hand ohne Umweg erreichbar. Nach 5 s ohne Tipp schließt es sich von selbst.
- **Fächer** → wie bisher die Großansicht der Rückseiten (`BacksViewer`, Lite `gegnerAnsicht`), wenn sie sichtbar sind. Ohne sichtbare Rückseiten öffnet der Fächer jetzt das Necken-Menü. Bisher kam dort nichts (App) bzw. nur die Meldung mit der Kartenzahl (Lite), die nun im Titel des Menüs steht.
- **Großer Modus (Liste):** Der Avatar-Kreis der Zeile öffnet das Menü. Der Rest der Zeile verhält sich wie bisher.
- **„Erwischt!“** wird zuerst geprüft (`hit_catch` vor allem anderen, wie heute) und bleibt damit unberührt. Damit ein Menüknopf nie über dem Erwischt-Knopf liegt (sonst löste ein Tipp aufs Menü ein Erwischen aus): Das Menü wird nie über `_catch_rect` (App) bzw. `.erwischen` (Lite) platziert, sondern auf die abgewandte Seite geklemmt. Außerdem schließt es sich, sobald eine Sicht einen Platz `catchable` macht oder `turn` wechselt. So ist Erwischen im 3–4,5-s-Fenster nie blockiert.
- **Lite hochkant:** Die Bühne skaliert mit `s = Breite/1180` (≈ 0,33 bei 390 px). Necken-Menü und Reaktionsfächer hängen deshalb **außerhalb** der skalierten `.buehne` in einer eigenen Ebene über dem Viewport. Die Position kommt aus `getBoundingClientRect()` des Kopfs, Knöpfe sind mindestens 44 CSS-px groß, die Schrift folgt `--fs`. Trefferfläche ist der ganze `.kopf`, nicht nur `.ava`.
- Gibt es nichts zu necken (Weitergeben, Ziel hat Necken aus, eigenes Necken aus), öffnet der Kopf wie bisher die Rückseiten (falls sichtbar) bzw. tut nichts. Hat das Ziel Necken aus, steht im Menü „Kim möchte gerade nicht geneckt werden.“ (nur „Karten ansehen“ bleibt).

**Reaktionen:** ein kleiner runder Knopf mit gezeichnetem Lachgesicht am **eigenen Platz** (App: rechts am Namensschild `me_badge` links über Sortieren/Rückseiten; großer Modus: links in der eigenen Zeile „Du“; Lite: eigenes Element neben `#ich-zahl` mit `pointer-events:auto`, nicht als Kind davon, weil `.ich-zahl` `pointer-events:none` hat; im großen Modus ist `.ich-zahl` ausgeblendet, dort sitzt der Knopf in der eigenen `.gg`-Zeile mit `seat === v.seat`, wie in der App). Ein Tipp auf den Knopf (oder auf das Namensschild) fächert 4 Reaktionen nach oben auf, ein Tipp auf eine Reaktion schickt sie. Danach schließt sich der Fächer. Ist der eigene Eimer leer, sind die Reaktionen kurz ausgegraut. Am Rundenende liegt der Knopf über der Rundenend-Tafel (App: `TableScreen.top_layer`; Lite: z-index über `#runde`). Im Kontrollbild muss gezeigt werden, dass er nichts verdeckt: weder Sortieren, Rückseiten, Mau-Knopf, Hinweisleiste noch Sofort-Leiste. Die Sofort-Leiste des Gastgebers kennt beide: `TableScreen.bar_obstacles()` nimmt das Rechteck des Reaktionsknopfs und, solange offen, das des Necken-Menüs bzw. Fächers auf.

**Ab Beta 1.6.5 (Nutzerwunsch nach der Familienrunde, 15.10.2026):** Kein Lachgesicht-Knopf und kein Fächer mehr. Die vier Reaktionen stehen als eigene runde Knöpfe direkt am eigenen Platz, ein Tipp sendet. Reihenfolge überall: Lachen 😂, Klatschen 👏, Daumen hoch 👍, Schreck 😱 (`TeaseMenu.REACT_ORDER`; `TeaseRules.FX_REACTS` bleibt die Liste des Protokolls). App: `TeaseMenu.ReactionBar`, Radius 24 (Trefferfläche ≥ 48 px), Lage nach `TeaseFx._place_reactions` (als Reihe rechts neben Name und Kartenzahl, sonst darüber oder 2 × 2; hart gemieden: Hand, Stapel, Mau, Sortieren/Rückseiten, „Erwischt!“-Felder und Fächer der Mitspieler, Hinweisleiste als Band), großer Modus in der Zeile „Du“ vor der Kartenzahl (`OpponentSeat.row_reserve` kürzt Name und Status). Sperrzeit: alle vier grau. Bilder: Das gezeichnete „Daumen hoch“ ließ sich anders deuten, System-Emoji sehen je Gerät anders aus. Deshalb zeigen App und Browser feste Bilder aus **Microsoft Fluent Emoji, Stil „Color“** (MIT, `game/assets/ui/reaktionen/*.svg` mit `LIZENZ.md`, unverändert). Die App importiert die SVG 12-fach (384 px, Mipmaps) und zeichnet sie mit `TeaseFx.draw_reaction` (Knöpfe, aufsteigende Reaktionen). Lite nutzt dieselben Dateien als Kopie in `webclient/bilder/reaktionen/` (samt `LIZENZ.md`; der Gastgeber liefert sie aus `web.zip`, der Vermittler unter `/c/<version>/bilder/reaktionen/…` als `image/svg+xml`): `<img class="nk-ri">` in den vier Knöpfen der Leiste `#nk-leiste` und in den aufsteigenden Reaktionen; lädt ein Bild nicht, bleibt das Emoji der Geräteschrift sichtbar. `test_web_contract` prüft, dass die Kopie der App gleicht. Kontrollbilder `docs/module/optik_165_*.png` (Lite: `optik_165_lite_*.png`, `tools/webtest/necken_bilder.ps1`).

**Lokal vorgeprüft:** Menü und Knöpfe zeigen nur, was nach denselben Regeln (Abschnitt 6, `TeaseRules`) mit den lokalen Uhren gerade geht. Die Uhr des Gastgebers läuft nie kürzer als die des Gasts (der Gast sieht den Zug später), deshalb lehnt der Gastgeber einen lokal erlaubten Wunsch selten ab. Lehnt er doch ab (Ziel hat schon gespielt, Ziel wird gerade geweckt, Tisch-Eimer leer – den kennt der Gast lokal nicht), schickt er **nur dem Absender** `{t:"fx_no", why:"late"|"busy"|"rate"}`. Das ist kein `err`, also gibt es keinen Fehlerton. Der Absender sieht eine kurze, leise Zeile (Abschnitt 3) bzw. bei `rate` kurz ausgegraute Knöpfe. Die anderen merken nichts. Der Absender sieht seinen Effekt erst, wenn das Ereignis des Gastgebers kommt. Dann sehen ihn alle gleichzeitig.

## 3. Darstellung und Töne

Effekte liegen in `fx_top` der TableView (über Fächern und Ablage, unter den Overlays). Der Bezugspunkt ist der Avatar (`OpponentSeat.avatar_global()`, eigener Platz: `me_badge`, großer Modus: Listenzeile). Farben kommen aus `UiPalette` mit Tag/Nacht über `night` (tagsüber Tinte auf Papier, nachts Creme mit leichtem Neon-Schein), Maße mal `k = 1.3` im großen Modus, Texte über `UiFonts`.

| Art | Bild | Absender | Ziel | Zuschauer |
|---|---|---|---|---|
| Schnarchen | 4,2 s lang steigen „Z z z“ in Wellen über dem Avatar auf (`TableEffects.zzz`, wie bei der Katze), dazu eine kleine Schlafmütze auf dem Avatar. Beim Ziel zusätzlich ein Text über dem eigenen Namensschild: „Kim findet, du schläfst gleich ein.“ | Ton leise (−12 dB) | Ton `schnarchen` normal | nur Bild |
| Wecker | Ein gezeichneter Wecker hüpft über den Avatar. 3 s lang dreht der Zeiger, und der Wecker tickt sichtbar (kleines Zucken je Sekunde, ohne Ton). Dann klingelt er 1,8 s lang mit kräftigem Wackeln und Schwinglinien. Beim Ziel ist er groß über dem eigenen Namensschild: „Kim hat dir einen Wecker gestellt!“ | Klingeln leise (−12 dB) | `wecker` normal + Vibration 3 × 250 ms (Einstellung „Vibration“) | nur Bild |
| Papierkugel | Eine gezeichnete, zerknüllte Kugel fliegt vom Absender (eigener Platz: über der Hand) auf einer Parabel zum Ziel (0,7 s, dreht sich). Beim Treffer gibt es einen Plopp, der Avatar staucht sich kurz (`_bump`), die Kugel springt einmal zurück, bleibt 3 s am Platz liegen und blendet dann aus. Höchstens 3 liegen je Platz. Bot: „Mpf!“. Beim Ziel: „Papierkugel von Kim!“ | `papier_wurf` normal | `papier_plopp` normal + Vibration 40 ms | Plopp leise (−12 dB) |
| Reaktion | Das Symbol steigt am Platz des Absenders auf (1,6 s, leicht schwingend, blendet aus). App: gezeichnet wie der Applaus (`ApplauseFx` für 👏), Lachen, Schreck und Daumen als eigene Vektorbilder. Lite: System-Emoji 😂 😱 👏 👍. Kommen Reaktionen schnell hintereinander, steigen sie nebeneinander auf. | Ton normal | Ton normal | Ton normal |

**Wer hört was (Begründung):** Am WLAN-Tisch sitzen alle in einem Raum. Würde das Schnarchen auf sechs Handys zugleich laufen, wäre es nur Lärm, und das Ziel stäche nicht heraus. Deshalb ist es laut nur beim Betroffenen, der Absender hört es leise als Bestätigung, und die Zuschauer sehen es nur. Reaktionen sind kurz und für alle gedacht (vor allem online), deshalb hören sie alle.

**Reaktionstöne gedeckelt:** Gerade am Rundenende (Jubel ~7 s, Mau-Mau) feuern viele gleichzeitig 👏/😂. SoundPool verdrängt bei gleicher Priorität den ältesten Ton, also den Jubel; `_play_jubel` verlöre seinen Eintrag. Deshalb spielt jedes Gerät höchstens **2 Reaktionstöne gleichzeitig**, dazu je Reaktionsname eine Sperre von **600 ms** (statt der üblichen 40 ms). Weitere Reaktionen bleiben stumm, das Bild erscheint trotzdem. Stimmen bleiben 6 (Abschnitt 6).

**Wecker abstellen (kleine Belohnung):** Handelt das Ziel während der 3 s Ticken (eine Sicht mit einem Ereignis des Ziels oder `turn ≠ Ziel`), fällt der Wecker auf diesem Gerät um, klingelt nicht, und beim Ziel steht „Gerade noch geschafft!“. Schnarchen blendet aus (Ton 0,3 s, `SfxPool.fade` bzw. Gain-Rampe). Jedes Gerät entscheidet das selbst. Kleine Unterschiede durch die Laufzeit sind egal.

**Kommt zu spät:** Ist das Ziel beim Eintreffen schon nicht mehr am Zug, zeigt das Gerät nichts. Weil der Gastgeber das schon ablehnt, kommt die Rückmeldung über `fx_no`: `late` → „Zu spät – Kim hat schon gespielt.“, `busy` → „Kim wird gerade schon geweckt.“, `rate` → nur kurz ausgegraute Knöpfe (kein Text). Ohne `fx_no` (eine angenommene `fx` kommt auf derselben Verbindung immer vor der nächsten `state`) erschiene die Zeile praktisch nie.

**Größe und Lage (Befund an den Kontrollbildern, 15.10.2026):** Bei Mitspielern gingen die Effekte auf dem Handy unter. Seitdem sind Wecker, „Z“ und Schlafmütze etwa doppelt so groß (App: Wecker `s = 40·k`, großer Modus `36·k`; Z 60/80/100 px; Mütze `1,9·r`, oben am Rand kleiner; Lite: Wecker 144 × 166, Z 68 px, Mütze 120 × 68), Reaktionen 1,6-fach (App `REACT_R = 38`, Lite 84 px) und die fliegende Kugel 1,6-fach (App `BALL_FLY_R = 27`, liegend `BALL_LIE_R = 21`; Lite 64 px, liegend `scale(.78)`). Der Wecker beim Ziel bleibt wie er war. Die Lage wählt `TeaseFx._choose` bzw. `MMF.Necken._waehle` aus mehreren Kandidaten (über/links neben dem Avatar, rechts neben dem Kopf, großer Modus in der Zeile vor der Kartenzahl; die Z-Wolke steigt am Rand auch nach rechts auf): jeweils auch ins Bild geschoben, hart gemieden werden Mau-Knopf, „Erwischt!“, Ziehstapel, Ablage, Hand und die Knöpfe, weich die Köpfe. Kontrollbilder: `optik_163_schnarchen*`, `wecker_oben_tag`, `reaktionen_tag`, `gross_effekte_*`, Lite `optik_163_lite_{schnarchen_oben_tag, wecker_*, reaktionen_*, gross_effekte*, hochkant_effekte, reduziert}`.

**Extra:** Liegt die Mau-Katze (Teil 1) auf dem Ziehstapel, wenn ein Wecker klingelt, springt sie davon (`FunFx.cat.leave(true, …)`).

**„Effekte reduziert“:** Die Kugel fliegt nicht, sondern erscheint am Ziel mit Plopp. Kein Wackeln, kein Stauchen. Die Z stehen still und blenden aus. Die Reaktion steigt nicht auf, sondern blendet am Platz ein und aus. Die Töne bleiben. Im Lite gilt das für `body.reduziert` **und** für `@media (prefers-reduced-motion: reduce)`, wie bei `.denk`/`.kranz` (`style.css`).
**Spieltöne aus/leise** (`toene`, Lite `toene` + Stummknopf): Alle Neck-Töne folgen dieser Stufe, der Mau-Ton spielt keine Rolle. „Leise“ bleibt relativ, der Absender hört dann −12 dB unter leise.

## 4. Protokoll

Alles zusätzlich, `PROTO` bleibt 1.

| Richtung | Nachricht |
|---|---|
| Gast → Gastgeber | `{t:"fx", k:"snore"\|"alarm"\|"ball"\|"react", to?:int, r?:String}` |
| Gast → Gastgeber | `{t:"fx_pref", off:bool}` (nach jedem `welcome` und bei Änderung der Einstellung) |
| Gastgeber → alle Sitzenden | `{t:"fx", k, from:int, to?:int, r?:String}` |
| Gastgeber → nur Absender | `{t:"fx_no", why:"late"\|"busy"\|"rate"}` (Ablehnung, kein `err`) |
| Gastgeber → alle Sitzenden | `{t:"fx_offs", seats:[int]}` (Plätze mit Necken aus; nur bei Änderung, dazu einmal an einen Gast nach seinem `welcome`) |

- **Keine laufende Nummer:** Doppelte Zustellung gibt es nicht (eine WS-Verbindung liefert der Reihe nach, der Vermittler wiederholt nichts). Eine Nummer je Partie würde nach einer Übernahme (1.6.1/1.6.2) beim neuen Gastgeber wieder bei 0 beginnen, und Gäste, die danach entprellen, verwürfen alle Neck-Ereignisse. Deshalb entfällt `n`.
- **Sitzende statt alle:** `session.broadcast` erreicht alle Verbindungen, auch die Warteliste (`join_open`). Gesendet wird deshalb mit `session.send_many(ids, text)` an die verbundenen Fern-Ids aus `_seat_ids` (online weiterhin **ein** `send`-Rahmen mit der Liste `c`), `fx_no` mit `send_to`. Im Lite wertet `case 'fx'` nur bei `this.screen === 'tisch'` aus.
- **Prüfung:** `NetProtocol.clean_client_message` bekommt die Fälle `fx` (nur `k` aus `FX_KINDS`, `to` int, `r` aus `FX_REACTS`, sonst `{}`) und `fx_pref`. Heute würden unbekannte Typen unverändert durchgereicht. Der Gastgeber prüft in `HostTable._on_fx(id, msg)` mit `TeaseRules.check(...)`. Während `_frozen`/`_settling` (Übergabe) nimmt er nichts an (ohne `fx_no`).
- **`fx_pref` ohne Sicherung:** Der Gastgeber merkt sich den Wert je Spieler-id. Nur wenn er sich **ändert**, schickt er `fx_offs` an die Sitzenden. Kein `_changed`, kein `_persist`, kein `bk`, kein `seq++`, keine vollen Sichten. Das Vorbild `_on_away` (das `_changed([])` ruft) wird hier ausdrücklich **nicht** übernommen, weil `fx_pref` nach jeder Neuverbindung kommt. Ein neu angemeldeter Gast bekommt nach seinem `welcome` einmal die aktuelle Liste. Der Gastgeber selbst steht ebenfalls in der Liste.
- **Gastgeber selbst:** Seine Wünsche gehen über `source.send_fx(req)` durch dieselbe Prüfung. Der eigene Tisch bekommt das Ereignis über das neue Signal `TableSource.fx_event(msg)`. ClientTable sendet bei `t == "fx"` dasselbe Signal, LocalTable (Übung) direkt.
- **Lebenszeichen:** `fx`-Pakete zählen wie jede Gastgebernachricht als Lebenszeichen (`NetClient` setzt `last_host_wall` bei jedem Paket des Gastgebers). Das ist unschädlich, weil ein eingefrorener Gastgeber (`_frozen`) nichts verteilt. Eine Sicherung (`bk`) ist `fx` nicht.
- **Ältere Geräte:** Gemischte Versionen kommen an einem Tisch gar nicht zusammen, weil `NetProtocol.check_hello` jede andere Spielversion ablehnt (`code version`). Der Lite-Client kommt immer vom Gastgeber bzw. vom Vermittler unter `/c/<version>/`. Trotzdem schadet nichts:
  - ClientTable bis 1.6.2 übergeht unbekannte `t` (`match` ohne Standardzweig), NetClient reicht sie nur weiter.
  - Lite `app.js nachricht()` hat `default: break`.
  - Ein Gastgeber bis 1.6.2 verwirft alles außer `act`/`handover_*` (`_on_message`).
  - Dasselbe gilt für `fx_no` und `fx_offs`. Die Sicht bleibt unverändert (kein neues Feld).
  Eine Fähigkeitsmarke braucht es deshalb nicht.
- **Vermittler:** keine Änderung an `relay/`. Kosten: je Necken 1 Gastrahmen + 1 Gastgeberrahmen = 2/20 Anfrage im Gratistarif. Selbst bei 1 Necken je 10 s über 3 h sind das ≈ 110 Anfragen am Abend. Die Grenzen des Vermittlers (Gast 20/s, Gastgeber 200/s) liegen weit darüber, und die Tischgrenze (4/s) deckelt den ungünstigsten Fall.

## 5. Einstellung

`necken` (bool, ab Werk **an**, je Gerät; App `AppSettings.defaults/sanitize`, Lite `Speicher 'necken'`). Name in den Einstellungen im Abschnitt der Sprüche: **„Necken (Papierkugel, Schnarchen, Wecker, Reaktionen)“ – An/Aus**, Erklärzeile „Mitspieler können dir Schnarchen, einen Wecker oder eine Papierkugel schicken.“

Nicht an „Sprüche: Aus“ gekoppelt: Sprüche sind Texte auf dem eigenen Gerät, Necken betrifft andere. Wer die Sprüche nervig findet, will vielleicht trotzdem Papierkugeln werfen.

**Aus heißt:** Man sieht und hört nichts davon (auch keine Reaktionen anderer) und kann selbst nichts schicken: Reaktionsknopf weg, Kopf-Tipp wie früher. Wer nicht geneckt werden will, neckt auch nicht. Der Gastgeber erfährt es über `fx_pref` und nimmt solche Ziele nicht an. Die anderen erfahren es über `fx_offs`, bei ihnen steht im Menü der Hinweis aus Abschnitt 2. Der Wert lebt beim Gastgeber nur im Speicher je Spieler-id. Nach einer Neuverbindung oder Übergabe schickt der Gast ihn mit dem nächsten `welcome` erneut.

## 6. Bausteine (Dateien)

- **`game/scripts/game/tease_rules.gd`** (neu, `class_name TeaseRules`, rein, ohne Szene, mit einspritzbarer Uhr): Konstanten (`FX_KINDS`, `FX_REACTS`, `FX_SLOW_MS`, Eimer, `BALL_GAP_MS`, `WAKE_BUSY_MS {snore 4500, alarm 5000}`), Zustand je Partie (Zugzähler und Zugbeginn, `sent[sender][kind] = zugnr`, Eimer, `busy_until[ziel]`), `note_view(view, now)`, `note_act(seat, now)`, `check(sender, req, view, now, flags) -> String` („“ = ok, sonst Grund `late`/`busy`/`rate`/…), `commit(...)`, `reset()` (bei `seats`), `caps(mode)`. Der Gastgeber nutzt die Klasse mit seiner Uhr, die Oberfläche mit der lokalen (für Ausgrauen und Menüeinträge).
- **`game/scripts/net/net_protocol.gd`:** Prüfung `fx`/`fx_pref`, `make_fx`, `clean_fx` (Host-Nachricht auf der Gast-Seite), Kopfkommentar „Beta 1.6.3“.
- **`game/scripts/game/table_source.gd`:** `signal fx_event(msg)`, `signal fx_refused(why)`, `signal fx_offs_changed(seats)`, `fx_off_seats() -> Array`, `send_fx(req)`, `set_fx_off(on)`, `fx_caps() -> Dictionary` (Standard `{}`).
- **`host_table.gd`:** `_on_fx`, `_fx_off` je id, `fx_offs` bei Änderung und nach `welcome` (ohne `_changed`/`_persist`), Zugbeginn in `_after_change`, `note_act` nur bei angenommener Aktion mit Ereignis des Ziels, `reset()` bei `seats`, Versand per `send_many` an die Sitzenden, `fx_no` per `send_to`. **`client_table.gd`:** `fx`/`fx_no`/`fx_offs` → Signale, `send_fx` → `client.send`, `fx_pref` nach `welcome`. **`local_table.gd`:** in `solo` nur `ball` auf Bots, direkt als Ereignis.
- **`game/scripts/ui/tease_fx.gd`** (neu, `class_name TeaseFx`): Effekte (`PaperBallFx`, `AlarmClockFx`, Schnarchen mit `TableEffects.zzz`, `ReactionFx` mit `ReactIcon`), `on_fx(msg)`, `on_view(v)`/`on_event(ev)` (Abstellen; bei `seats` alle Effekte je Platz abräumen), Töne und Vibration (höchstens 2 Reaktionstöne gleichzeitig, 600 ms je Name), `tick(delta)` für Tests (wie `FunFx`).
- **`game/scripts/ui/tease_menu.gd`** (neu): `TeaseMenu` (Blase am Gegner) und `ReactionPicker` (Knopf + Fächer).
- **`table_view.gd`:** `OpponentSeat.hit_head()` (neu) in `_tap`, Menü öffnen (Platzierung nie über `_catch_rect`, Schließen bei `catchable`/Zugwechsel/`seats`), `fx_top`, Anbindung von `TeaseFx`. **`opponent_seat.gd`:** `hit_head`, Schlafmütze. **`table_screen.gd`:** `source.fx_event` → `table.tease.on_fx`, Menüwahl → `source.send_fx`, `necken` aus den Einstellungen, Reaktionsknopf am Rundenende in `top_layer`, Knopf und offenes Menü in `bar_obstacles()`. **`big_layout.gd`:** Platz des Reaktionsknopfs in der eigenen Zeile.
- **`game/scripts/app/sound.gd`:** `NAMES` um `schnarchen, wecker, papier_wurf, papier_plopp, lachen, schreck, klatschen, daumen` ergänzen. Neu `play(name, extra_db := 0.0)` für „leise“ (−12 dB) und `fade_out(name, ms)` für Schnarchen und Wecker (Godot-Abspieler bzw. `SfxPool.fade` über `_native_playing`). `SfxPool.java` bleibt unverändert: Es lädt, was `sound.gd` als CSV übergibt, und `tools/build.ps1` kopiert jede `game/assets/sfx/*.ogg` als `res/raw/sfx_<name>.ogg`. Der Name muss nur `[a-z0-9_]` sein. **Stimmen bleiben 6:** `SfxPool.MAX_STREAMS` (Java) und `VOICES` in `sound.gd` (Godot-Abspieler und Buchführung `_native_playing`) sind gekoppelt und werden nur gemeinsam geändert. Würde nur Java angehoben, striche `_start_native` den Schnarch-Eintrag, obwohl er noch läuft, und `fade_out('schnarchen')` fände keine Stream-Id. Die Deckelung der Reaktionstöne (Abschnitt 3) hält Stimmen frei. `fade_out(name)` sucht den Eintrag über den Namen.
- **`settings.gd`, `ingame_settings.gd`, `screens/settings_screen.gd`:** `necken`.
- **Lite:** `webclient/necken.js` (neu, `M.Necken`: Regeln als Spiegel von `TeaseRules`, Menü, Reaktionsfächer, Effekte als DOM/CSS mit SVG-Kugel und SVG-Wecker), `index.html` (Skript zwischen `spass.js` und `tisch.js`), `tisch.js` (Klick auf den ganzen `.kopf` → Menü, `.faecher` wie bisher; Menü und Fächer als Viewport-Ebene außerhalb der `.buehne`; Reaktionsknopf als eigenes Element bzw. im großen Modus in der eigenen `.gg`-Zeile), `app.js` (`case 'fx'` nur auf dem Tisch, `fx_no`, `fx_offs`, `fx_pref` nach `welcome`, Einstellung `necken` im Lite-Menü, `VERSION`), `ton.js` (`SPIEL_TOENE` + Namen, `spiele(name, pegel)` mit Faktor 0,25 ≈ −12 dB, `stoppe(name)` mit Rampe), `style.css` (Tag/Nacht, `.reduziert` und `prefers-reduced-motion`, großer Modus), `sfx/index.json`.
- **Texte:** App `I18n.t` mit Einträgen in `game/i18n/en_fun.po`. Lite `M.t` (aus `i18n_po.js`, beim Bauen erzeugt), reine Lite-Texte in `i18n_en.js`. Die englischen Begriffe stehen im Glossar `game/i18n/GLOSSAR.md` („Necken“ → „Tease“, Papierkugel → „paper ball“).

### 6.1 Schnittstelle für die Oberfläche (Stufe 1 „Netz“, umgesetzt 15.10.2026)

Alle Spielsteuerungen (`TableSource`: `LocalTable`, `HostTable`, `ClientTable`) bieten dasselbe. Die Oberfläche (Stufe 3, `TeaseFx`/`TeaseMenu`, `table_screen.gd`) braucht nur das:

| Teil | Bedeutung |
|---|---|
| `signal fx_event(msg)` | angenommenes Necken `{t:"fx", k, from, to?, r?}` (`react` mit `r`, sonst mit `to`). Kommt auf **allen** Geräten gleich, auch beim Absender und beim Gastgeber selbst. Erst dann den Effekt zeigen. |
| `signal fx_refused(why)` | nur beim Absender: `"late"`, `"busy"` oder `"rate"` (Zeilen bzw. Ausgrauen aus Abschnitt 3). Kein `notice`, kein Fehlerton. |
| `signal fx_offs_changed(seats)` | Plätze mit Necken aus haben sich geändert (Menü-Hinweis „%s möchte gerade nicht geneckt werden.“). |
| `send_fx(req)` | `{k:"snore"\|"alarm"\|"ball", to:int}` bzw. `{k:"react", r:"lachen"\|"schreck"\|"klatschen"\|"daumen"}`. Ungültiges wird verworfen. |
| `set_fx_off(off)` / `fx_off()` | Einstellung „necken“ dieses Geräts (`off = not settings.necken`). Startwert liest jede Quelle selbst aus `App.settings` (`TableSource.setting_fx_off()`); die Oberfläche ruft `set_fx_off` bei Änderung. Gast: geht als `fx_pref` hinaus (auch nach jedem `welcome`), Gastgeber: steht selbst in `fx_offs`. |
| `fx_off_seats()` | aktuelle Liste (Plätze, aufsteigend). |
| `fx_caps()` | `{kinds:[…], bots_only}`: host/client alles, solo `["ball"]` nur auf Bots, pass nichts (`TeaseRules.caps`). |
| `fx_check(req) -> String` | lokale Vorprüfung für den eigenen Platz mit der lokalen Uhr: `""` = Knopf aktiv, sonst Grund (siehe unten). |
| `fx_slow_left_ms(seat) -> int` | Restzeit bis Schnarchen/Wecker (0 = jetzt, −1 = nicht am Zug), z. B. für einen Fortschrittsring. |
| `tease` | `TeaseRules`-Instanz (Gastgeber maßgeblich, sonst Spiegel). Nur lesen. |
| `fx_clock` | Tests: `() -> ms` (Monotonuhr fürs Necken; Gastgeber ohne sie `_now_ms()`). |

**Gründe** von `TeaseRules.check`/`fx_check`: `late` (Ziel nicht mehr am Zug), `busy` (Ziel wird gerade geweckt, 4,5 s/5 s), `rate` (eigener Eimer, Kugel-Abstand am Ziel, Tisch-Eimer) – diese drei gehen als `fx_no` an den Absender. Still verworfen (die Oberfläche zeigt den Knopf dann nicht bzw. ausgegraut): `kind`, `mode` (Spielart), `sender` (Wartender, Bot, abwesend/vertreten), `off` (eigenes oder Ziel-Necken aus), `self`, `target` (ungültig, Bot bei Schnarchen/Wecker, Mensch in der Übung, Ziel abwesend), `phase` (Kugel am Rundenende, alles ohne Partie), `early` (vor 10 s), `once` (je Sender und Zug schon geschickt).

**Spiegel:** `ClientTable` füttert `tease` mit jeder Sicht (`note_view`) und deren Ereignissen (`note_events`, wie `_poke`) und verbucht jedes empfangene `fx` (`commit`), `GameTable._changed` tut dasselbe beim Gastgeber und in der Übung. Ein Ereignis `seats` leert den Zustand (`reset`). Weil der Gast Sichten und `fx` später sieht als der Gastgeber, ist der Spiegel immer etwas strenger. Den Tisch-Eimer kennt der Spiegel über die empfangenen `fx` mit.

**Umgesetzte Einzelheiten:**
- Gastgeber: `HostTable._on_fx` (Gast und `send_fx` des Gastgebers), Versand per `send_many` an die sitzenden entfernten Menschen (nie an die Warteliste), `fx_no` per `send_to`; eingefroren, in der Einschwingzeit und während der Wächter-Prüfung nach der Rückkehr (`is_waking`) wird nichts angenommen. `fx_pref` je Spieler-id in `_fx_off_ids` (nur im Speicher, nach `resume()` leer); `fx_offs` geht bei Änderung der Platzliste an alle Sitzenden (auch nach Platzwechseln über `_after_distribute`, dann mit neuen Nummern), einzeln an einen Zurückkehrenden bzw. Dazugeholten, wenn sie nicht leer ist. Beim Partiebeginn nur, wenn schon jemand aus ist.
- Gast: Beim `welcome` leert er `tease` und seine Liste `fx_offs` und schickt `fx_pref`; der Gastgeber schickt die Liste danach neu, falls sie nicht leer ist. `fx` wertet er nur mit Platz und Sicht aus (nie auf der Warteliste).
- „Zug“ für „einmal je Zug“: Die Zugnummer steigt, wenn der Platz am Zug wechselt (auch über −1 am Rundenende). Spielt jemand bei zwei Spielern nach einem Aussetzen gleich noch einmal, gilt das als derselbe Zug (seine Uhr beginnt trotzdem neu). Eine laufende Weckaktion (`busy`) endet mit dem Zugwechsel.
- Einstellung: `necken` (bool, ab Werk `true`) steht schon in `AppSettings.defaults()`/`sanitize()`; Bedienelemente in `ingame_settings.gd`/`settings_screen.gd` folgen in Stufe 3.
- Version 1.6.3 gesetzt (`game/project.godot`, `webclient/app.js`).
- Tests: `game/tests/test_tease_rules.gd` (rein, eingespritzte Uhr), `game/tests/test_game_net_tease.gd` (Netzspur mit `NetRelayDouble`, `handover_kit.gd`: Übung/Weitergeben, Schnarchen bis zum Browser-Gast, busy/late/rate, Spielstand unberührt, `fx_pref`/`fx_offs`, Warteliste, Dazuholen, eingefroren/Einschwingzeit, unbekannte Typen am Gast, Übernahme online).

### 6.2 App-Oberfläche und Töne (Stufen 2 und 3, umgesetzt 15.10.2026)

- **Töne:** die 8 Dateien unverändert nach `game/assets/sfx/` (Godot-Import), `AppSound.NAMES` + `TEASE_NAMES`, `play(name, extra_db)` mit `QUIET_DB = −12`, `fade_out(name, ms)` und `is_playing(name)` (Godot-Abspieler bzw. `SfxPool.fade` über `_native_playing`); `SfxPool.java` unverändert. `audio/sfx_README.md` ergänzt. Die Browser-Fassungen (`webclient/sfx/*.ogg|m4a`, `index.json`) gehören zur Lite-Stufe; bis dahin meldet `test_web_contract` die 8 fehlenden Einträge.
- **`game/scripts/ui/tease_fx.gd` (`TeaseFx`):** hängt am Tisch (`TableView.tease`), Effekt-Ebene direkt über `fx_top`, Uhr über `tick` (Tests: `auto_process = false`), Attrappen `sound`/`vibrate_cb`. Effekte als eigene Knoten ohne `_process` (`SnoreFx`, `AlarmFx`, `BallFx`, `ReactFx`, `TextFx`), gezeichnete Bilder `draw_icon` (Kugel, Schnarchen, Wecker, Karten, 4 Reaktionen, Lachgesicht), `draw_cap`, `draw_clock`. Abweichungen im Detail: Z und Wecker stehen links über dem Avatar (rechts steht die Denkblase); der Bogen der Kugel liegt quer zur Wurfrichtung (bei steilen Würfen zur Seite); Kugeln liegen links neben dem Avatar; Reaktionen von Plätzen am oberen Rand steigen links neben dem Avatar auf; die Zeilen beim Ziel stehen linksbündig über dem eigenen Namensschild (Wecker: rechts neben dem großen Wecker).
- **`game/scripts/ui/tease_menu.gd`:** `TeaseMenu` (Blase, `_has_point` nur die Blase, Tipp daneben schließt über `_input` ohne Verbrauch) und `TeaseMenu.ReactionPicker` (Knopf rechts am Namensschild, im großen Modus links der Zeile „Du“; Fächer nach oben bzw. links; Hilfetexte „Lachen“ …). Lage des Menüs: rechts, links, links neben dem „Erwischt!“-Feld, darunter, darüber, jeweils an harten Hindernissen vorbeigeschoben; hart gemieden: „Erwischt!“-Feld des Ziels und erwischbarer Plätze, Zurück/☰ (`avoid_cb` aus `TableScreen`), Mau-Knopf; weich: Köpfe bzw. Listenzeilen aller Gegner.
- **Einhängepunkte:** `TableView` (`tease`, `_tap`: eigenes Namensschild → Fächer, Kopf → Menü, Fächer ohne sichtbare Rückseiten → Menü; `apply_view`/`play_event`/`skip_event`, reduziert, Nacht, groß, Einstellung `necken`), `OpponentSeat.hit_head`, `TableScreen` (`tease.attach(source)`, `avoid_cb`, `bar_obstacles`), `UiApp.sound_db`/`fade_sound`, `SettingsScreen.personal` (Schalter „Necken (…)“, auch im Spiel), `RulesText.controls(cfg, tease)` + `IngameHelp` (Absatz „Necken“ nur, wenn der Tisch es anbietet). Texte in `game/i18n/en_fun.po`, Glossar ergänzt.
- **Tests:** `test_ui_tease.gd` (Gesten, Menü, Rollen und Töne, Wecker abstellen, Deckel der Reaktionstöne, `fx_no`, Necken aus, Weitergeben, reduziert, groß, Übung über die echte `LocalTable`), `test_app_sound.gd` (19 Töne, leise, `fade_out` bei 6 laufenden Tönen), Kontrollbilder `test_tease_shot.gd` → `docs/module/optik_163_*.png`.

## 7. Töne

Dateien **unverändert kopiert** (wie Schnurren, Herkunft MOSS-SoundEffect v2.0, Apache 2.0), dazu ein Eintrag in `audio/sfx_README.md`:

| Spielname | Quelle `audio/entwurf/ostereier/` | Dauer | Lautheit (integriert) / Spitze |
|---|---|---|---|
| `schnarchen` | `schnarchen_01.ogg` | 4,17 s | −21,7 LUFS / −2,2 dBFS |
| `wecker` | `klingeln_01.ogg` (nur Klingeln) | 1,82 s | −19,1 / −6,2 |
| `papier_wurf` | `papierkugel_wurf_03.ogg` | 1,32 s | −23,6 / −1,2 |
| `papier_plopp` | `papierkugel_plopp_01.ogg` | 0,30 s | (zu kurz für I) Mittel −24,7 dB / −1,2 |
| `lachen` | `lachen_06.ogg` | 1,92 s | −23,8 / −6,7 |
| `schreck` | `schreck_01.ogg` | 0,61 s | −19,4 / −5,5 |
| `klatschen` | `klatschen_05.ogg` | 1,92 s | −21,5 / −1,1 |
| `daumen` | `daumen_04.ogg` | 0,62 s | −20,0 / −10,9 |

Die Pegel liegen im Bereich der vorhandenen Spieltöne (`dran` −19,2, `schnurren` −23,6 LUFS) und wurden bei der Erzeugung schon für den Handylautsprecher ausgesteuert. `TRIM_DB` bleibt leer. Sollte `lachen` beim Hörtest zu leise sein, wird es dort angehoben, nicht in der Datei. Es gibt keine `*_handy.ogg` (das sind Simulationen).

Ziele: `game/assets/sfx/<name>.ogg`, `webclient/sfx/<name>.ogg` und `<name>.m4a`. Die m4a erzeugt `tools/make_ostereier.py --spiel` (neue Stufe, ohne GPU): kopieren, dann `ffmpeg -c:a aac -b:a 160k -movflags +faststart` wie `make_sfx_moss.py`, mono 48 kHz. `sfx/index.json` bekommt die 8 Einträge.

## 8. Texte (Deutsch)

„Necken“, „Papierkugel“, „Schnarchen“, „Wecker“, „Karten ansehen“, „%s · %s“ (mit den vorhandenen „%d Karte“/„%d Karten“), „Erst, wenn %s eine Weile überlegt.“, „%s möchte gerade nicht geneckt werden.“, „%s findet, du schläfst gleich ein.“, „%s hat dir einen Wecker gestellt!“, „Gerade noch geschafft!“, „Papierkugel von %s!“, „Mpf!“, „Zu spät – %s hat schon gespielt.“, „%s wird gerade schon geweckt.“, „Reaktion“, „Lachen“, „Schreck“, „Klatschen“, „Daumen hoch“ (Barrierefreiheit/aria), Einstellung „Necken (Papierkugel, Schnarchen, Wecker, Reaktionen)“ und „Mitspieler können dir Schnarchen, einen Wecker oder eine Papierkugel schicken.“. In „So geht's“ kommt eine Zeile dazu: „Tippe auf einen Mitspieler, um ihn zu necken. Der Knopf am eigenen Platz schickt eine Reaktion an alle.“

## 9. Tests

- **`test_tease_rules.gd`** (rein, schnell, Uhr eingespritzt):
  - Schnarchen/Wecker vor bzw. ab 10 s, Uhr neu bei Zugwechsel und bei eigener Aktion des Ziels, je Sender einmal je Zug, zweiter Sender erst nach `WAKE_BUSY_MS`.
  - Ausgeschlossene Ziele und Absender: nie man selbst, nie Bots, nicht `away`, getrennt, vertreten oder Necken aus (`fx_offs`); Wartende und Bots als Absender.
  - Phasen: turn, drawn, color, challenge, gamble, discard_pick erlaubt, round_over nur `react`.
  - Ball-Eimer und Abstand am Ziel, Reaktions-Eimer, Tischgrenze; Gründe `late`/`busy`/`rate`.
  - Abgelehnte Aktion des Ziels setzt die Uhr nicht zurück, angenommene schon.
  - `reset()` nach Platzwechsel.
  - `caps` für pass/solo/host/client.
- **`test_game_net_tease.gd`** (Netzspur, wie `test_game_net_seats.gd`): Gast → Gastgeber → alle (auch der Gastgeber per `fx_event` und der Absender selbst).
  - Ablehnung: nur der Absender bekommt `fx_no` mit Grund, kein `err`, kein Stand, `rev` und Speicherdatei unverändert.
  - Wartende (Warteliste) bekommen kein `fx`.
  - `fx_pref` → `fx_offs` an alle Sitzenden nur bei Änderung; Speicherdatei, `seq` und Zahl der `bk` bleiben unverändert; gleicher Wert erneut → nichts. Neu angemeldeter Gast bekommt die Liste. Bereinigung kaputter Nachrichten.
  - Übernahme (1.6.1/1.6.2), danach kommt `fx` beim Gast an und wird angezeigt.
  - Dazuholen/Entfernen leert den Zustand.
  - Eingefroren (Übergabe) nimmt nichts an; ein Client ohne Kenntnis von `fx`/`fx_no`/`fx_offs` bleibt unberührt (Nachricht direkt an `ClientTable._on_message`).
  - Übung: Ball nur auf Bots.
- **`test_ui_tease.gd`** (Bildschirmspur):
  - Gesten: Kopf-Tipp → Menü, Fächer-Tipp → BacksViewer (sichtbar) bzw. Menü (verdeckt), Erwischt geht vor, Tipp daneben schließt das Menü und wirkt weiter (Ziehstapel, Mau).
  - Menü offen, Platz wird erwischbar → Menü zu, Erwischen geht; Menü überlappt nie `_catch_rect`; Zugwechsel schließt es; Titel „1 Karte“.
  - 7 gleichzeitige Töne (Attrappe), danach `fade_out('schnarchen')` findet den Eintrag; mehr als 2 Reaktionen gleichzeitig bleiben stumm, Jubel läuft weiter.
  - `fx_no` → Zeile bzw. ausgegraute Knöpfe beim Absender.
  - `bar_obstacles()` enthält Reaktionsknopf und offenes Menü.
  - Menüeinträge ausgegraut/aktiv nach lokaler Uhr.
  - Effekte entstehen und räumen sich auf; Wecker abstellen; Schnarchen ausblenden.
  - Töne über die `AppSound`-Attrappe (Name und dB: Ziel normal, Absender −12, Zuschauer still bzw. leise), Vibration gezählt.
  - `necken` aus: nichts.
  - Reduziert, großer Modus.
- **`test_tease_shot.gd`** (`SHOT_DIR`) → `docs/module/optik_163_*.png`, alle Bilder ansehen:
  - `menue_tag`/`menue_nacht`, `menue_ausgegraut`
  - `schnarchen`, `wecker_tickt`, `wecker_klingelt`, `wecker_ziel`
  - `kugel_flug`, `kugel_liegt`
  - `reaktionen` (alle 4), `reaktion_knopf`
  - `gross_menue`, `sehr_gross` (Schrift „Sehr groß“), `rundenende_reaktion`, `en_menue`
- **`test_web_contract.gd`:** Gleichlauf `necken.js` ↔ `TeaseRules`/`NetProtocol` (Arten, Reaktionen, Zeiten, Eimer), 8 Einträge in `sfx/index.json` mit `.ogg` und `.m4a`, `case 'fx'` in `app.js`, neue Texte in .po/`i18n_en.js`. `test_i18n` streng mit 0 Lücken.
- **Lite-Bilder:** `tools/webtest/web_e2e.ps1 -Bilder -Zusatz '&szenario=necken'` (neues Szenario in `app.js`: Menü öffnen, Ball, Reaktion, Wecker an einem Bot-Ziel nur in der Szene) → `docs/module/optik_163_lite_*.png` (Tag, Nacht, `lite_gross` mit Reaktionsknopf in der eigenen Zeile, `lite_hochkant` 390×844 mit Menü in Viewport-Größe).
- **Gerätetest (Hauptsitzung, S21 + S10 gesperrt, `MauMauFlipTestLock`):** S21 Gastgeber, S10 App-Gast (WLAN, danach einmal online).
  - Per `input tap` wird auf dem S10 der Kopf des S21 angetippt → Papierkugel. Per `screencap` werden beide Geräte geprüft: Flug, Kugel liegt, „Papierkugel von …“.
  - Das S21 bleibt ≥ 10 s am Zug, dann vom S10 Schnarchen und Wecker; ein zweiter Wecker desselben Senders im selben Zug ist ausgegraut (kein Effekt, bei den anderen keine Meldung).
  - Reaktion vom S21; Wecker abstellen (S21 spielt innerhalb von 3 s).
  - Hören geht nicht. Stattdessen `logcat` mit `SfxPool:` (Name und Lautstärke: Ziel normal, Absender leise, Zuschauer kein Eintrag) und `dumpsys vibrator_manager` (Muster beim Ziel).
  - Lite gesperrt nicht möglich, also nur Chrome headless.
  - Danach den Ausgangszustand wiederherstellen und die Testhandys nach Absprache mit der Draw2Race-Sitzung belegen/freigeben.

## 10. Stufen (überschneidungsfrei)

1. **Netz** (core): `tease_rules.gd`, `net_protocol.gd`, `table_source.gd`, `host_table.gd`, `client_table.gd`, `local_table.gd`, `test_tease_rules.gd`, `test_game_net_tease.gd`. **Hier einmal die Version auf 1.6.3 setzen** (`game/project.godot` `config/version`, `webclient/app.js` `VERSION`).
2. **Töne:** `tools/make_ostereier.py --spiel`, `game/assets/sfx/*`, `webclient/sfx/*`, `sound.gd`, `audio/sfx_README.md`.
3. **App:** `tease_fx.gd`, `tease_menu.gd`, `table_view.gd`, `opponent_seat.gd`, `table_screen.gd`, `big_layout.gd`, `settings.gd`, `ingame_settings.gd`, `settings_screen.gd`, `en_fun.po`, `test_ui_tease.gd`, `test_tease_shot.gd`.
4. **Lite:** `necken.js`, `index.html`, `tisch.js`, `app.js` (ohne `VERSION`), `ton.js`, `style.css`, `i18n_en.js`, `test_web_contract.gd`.

## 11. Risiken

- **Belästigung:** Bremsen sind die Sperren, „einmal je Zug“, der Absendername beim Ziel und der Schalter „Necken aus“. Bleibt es zu viel, lässt sich `FX_SLOW_MS` später auf 15 s anheben (eine Konstante, im Lite gespiegelt, durch `test_web_contract` abgesichert).
- **Überdeckung:** Reaktionsknopf und Menü auf kleinen Handys bzw. im großen Modus und bei „Sehr groß“. Die Kontrollbilder prüfen das, der Menüplatz wird an den Tischrand geklemmt.
- **Gesten:** Kopf-Tipp öffnet nicht mehr direkt die Rückseiten (einen Tipp mehr über „Karten ansehen“). Der Fächer und die Zeile im großen Modus bleiben wie bisher.
- **Emoji in der App:** Die App bringt keine Emoji-Schrift mit, und der Rückfall auf die Android-Systemschrift ist unzuverlässig (1.3.3: schwarzes Quadrat statt Pfeil). Deshalb sind alle App-Symbole gezeichnet. Im Lite sind System-Emoji in allen Handy-Browsern sicher.
- **SoundPool:** Mehr Töne (19) verlängern das Vorladen etwas. Die Stimmen bleiben bei 6 (Java und `sound.gd` gekoppelt), die Reaktionstöne sind auf 2 gleichzeitig gedeckelt. Laufen Schnarchen, Jubel und Spieltöne trotzdem zugleich, verdrängt SoundPool den ältesten Ton, und `sound.gd` streicht denselben Eintrag. Das prüft `test_ui_tease` mit der Attrappe, am Gerät die `logcat`-Zeilen.
- **Gegenprüfung (15.10.2026), nicht gewählte Alternativen:**
  - Laufende Nummer `n` behalten und bei `welcome`/`moved` bzw. nach (epoch, gen) zurücksetzen: unnötig, weil es keine doppelte Zustellung gibt. Jede Nummer wäre nur eine weitere Fehlerquelle bei der Übernahme.
  - `fx_off` in der Sicht mit `_send_state` je Platz ohne `_persist`: hätte bei jeder Änderung volle Sichten an alle geschickt. `fx_offs` ist kleiner und berührt den Spielstand nicht.
  - Ohne `fx_no` lokal „Zu spät“ ableiten (offene Anfrage, nächste Sicht mit `turn ≠ Ziel`): deckt `busy`/`rate` nicht ab und wäre fehleranfälliger.
  - `SfxPool.play` um eine Priorität erweitern (Jubel/Mau 2, Reaktionen 0): erst, wenn der Gerätetest trotz Deckelung abgerissene Töne zeigt. Es wäre eine Java-Änderung mit neuem Bau des Android-Teils.
  - Effekte bei `seats` ummappen statt abräumen: lohnt sich für Effekte von wenigen Sekunden nicht.
  - Verworfen wurde kein Befund.
- **Laufzeit online:** 100–300 ms bis zum Effekt, auch beim Absender. Das ist gewollt (alle gleichzeitig), wirkt aber träger als lokal. Die Knöpfe geben deshalb sofort eine kleine Drückrückmeldung.
- **iPhone (Lite):** m4a und Web Audio wie die übrigen Töne, Vibration gibt es dort nicht (`navigator.vibrate` fehlt). Ungetestet wie bisher.
