# Architekturvorschlag „Godot-App + schlanker Web-Client“ für Mau-Mau Flip

Stand 04.10.2026. Ich habe nur gelesen und nichts verändert. Diese Punkte habe ich selbst geprüft:
- Der Projektordner `E:\Documents\Programmierung\Mau-Mau Flip` enthält `.git` und eine noch nicht eingecheckte `LICENSE`.
- Der leere Ordner `Mau-Maul Flip` daneben ist vermutlich ein Tippfehler. Ob er gelöscht wird, entscheidest du.
- In Draw2Race hängen von den 594 Zeilen in `net_session.gd` nur einige Stellen an ENet: `create_server`/`create_client`, `poll`/`get_packet`, `get_peer` (Drossel, Statistik, Zeitgrenzen) und `disconnect_peer`.
- `project.godot` von Draw2Race nutzt den Renderer `mobile`.

**Kennzeichnung:**
- **[Ableitung]**: aus den Berichten oder dem Code geschlossen
- **[Schätzung]**: grob geschätzt
- **[Gerätetest]**: lässt sich nur am echten Gerät klären

---

## 0. Kernentscheidungen

1. **Es gibt einen einzigen Regelkern.** Er ist in GDScript geschrieben und läuft nur auf dem Host.
   - Alle Mitspieler-Geräte sind „dünne“ Clients. Das gilt auch für die Android-App, wenn sie nicht Host ist. Sie zeigen die Ereignisse des Hosts an und schicken Absichten zurück.
   - Der Browser-Client enthält **keine einzige Spielregel**.
2. **Der Host sagt jedem Client auch, was erlaubt ist.** Er schickt:
   - spielbare Karten und mögliche Aktionen,
   - fertige Hinweistexte („Passt nicht – Blau oder 7“),
   - allgemeine Abfragen (Farbe wählen, Spieler wählen, Anzweifeln ja/nein).

   So braucht der TypeScript-Client für neue Hausregeln meist kein Update. Das ist der wichtigste Hebel gegen zwei auseinanderlaufende Codebasen.
3. **Es gibt nur einen Transport: WebSocket mit JSON-Text**, für App-Mitspieler und Browser gleich.
   - ENet entfällt. Für ein rundenbasiertes Spiel ist TCP mit garantierter Zustellung richtig, und die ENet-Drossel-Kniffe aus Draw2Race werden überflüssig.
   - Die UDP-Suche aus Draw2Race bleibt für die Apps erhalten.
4. **Der Host betreibt zwei Server:**
   - HTTP auf Port 24690 in einem eigenen `Thread`: Einladungsseite, Web-Client, APK.
   - WebSocket auf Port 24691 in der Hauptschleife: das Spiel.
   - UDP 24692 und 24693 für die Suche.

   Diese Ports kollidieren nicht mit Draw2Race (24680–24682) und auch nicht mit dessen Testbereichen.
5. **Der Web-Client** besteht aus TypeScript, **PixiJS v8** (MIT) für Tisch und Effekte und normalem DOM für Menüs und Eingaben.
   - Er steckt als `webclient.zip` in der APK und wird offline vom Host ausgeliefert.
   - Folge: Er hat **immer genau die Version des Hosts**. iPhone-Spieler müssen also nie etwas aktualisieren.
6. **Geteilt werden Daten, kein Code.** Beide Seiten testen gegen dieselben Dateien:
   - Protokoll-Beispieldateien („Golden Files“)
   - `layout.json`, `effects.json`, `palette.json`
   - Kartengrafik aus einer gemeinsamen SVG-Quelle
7. **Ein QR-Code für alle:** `http://<ip>:24690/j/<schlüssel>`
   - iPhone: spielt im Browser.
   - Android ohne App: „App installieren (empfohlen)“ oder „Im Browser spielen“.
   - Android mit App: „In der App öffnen“ über einen Intent-Link.
   - Wer eine **falsche App-Version** hat, kann trotzdem im Browser mitspielen.

---

## 1. Komponenten

```
                 GitHub: ShakieVan/Mau-Mau-Flip  +  ShakieVan/Mau-Mau-Flip-Beta
                                  │ HTTPS (nur mit Internet: Updater)
┌─────────────────────────────── Android-App (Godot 4.6.1, GDScript, Compatibility) ──────────────────────────────┐
│ Updater (updater.gd + Updater.java)   Share.java (APK/Link teilen)   Hotspot.java (LOHS, später)                  │
│ NetAndroid + NetHelper.java (WLAN-Bindung, Hotspot-Erkennung, Multicast-Sperre, eigene IPs)                       │
│                                                                                                                   │
│  ┌──────────── Regelkern  game/scripts/core  (rein, deterministisch, nur auf dem Host aktiv) ────────────┐       │
│  │ Deck mit Zufallsgriffen · RuleConfig · GameState · apply(sitz, absicht) -> ereignisse | ablehnung       │       │
│  │ view_for(sitz) · events_for(sitz) · hints_for(sitz) · Bot · Aktionslog + Seed -> Autosave             │       │
│  └──────────────▲─────────────────────────────────────▲───────────────────────────────────────────────────┘       │
│                 │ LocalSeat (im Prozess, gleiche Dicts)  │ HostServer                                              │
│                 │                                        ├─ WsServer   TCPServer + WebSocketPeer.accept_stream     │
│   Weitergeben:  │                                        ├─ HttpServer Thread: /j/<k>, /play/<k>, /app/*.apk        │
│   Engine lokal, │                                        ├─ Discovery  UDP-Ankündigung (aus Draw2Race)              │
│   Übergabekarte │                                        └─ Lobby      Sitze, Tokens, Wiederverbindung, Optionen    │
│                 ▼                                                                                                 │
│  Tisch-UI: Tischregie (Director) · Hand · Effekte (effects.json) · Sitz-Rotation   ◄── WsClient (App als Mitspieler)│
└───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
         ▲ ws:// JSON (+ UDP-Suche)                                ▲ http:// Seite + ws:// JSON
         │                                                         │ (QR-Link / geteilter Link)
   Android-App als Mitspieler (dieselbe App)          Browser-Client (TypeScript + PixiJS + DOM)
                                                       iPhone-Safari · Android ohne App · PC-Browser
```

**Verzeichnisaufbau (Vorschlag):**

| Ordner | Inhalt |
|---|---|
| `game/` | Godot-Projekt: `scripts/core`, `scripts/net`, `scripts/table`, `scripts/party`, `android/build`, `tests` |
| `web/` | TypeScript-Client: `src/`, `package.json`, Vite, Vitest, Playwright |
| `shared/` | `protocol/fixtures/*.json`, `layout.json`, `effects.json`, `palette.json`, `cards/*.svg` |
| `tools/` | `setup.ps1` (lädt zusätzlich ein portables Node LTS nach `.tools/`), `build.ps1`, `godot_run.ps1`, `net_test.ps1`, `e2e.ps1` |
| `docs/` | `AGENTS.md`-Muster wie in Draw2Race |

### 1.1 Regelkern (Spiel-Engine)

**Wo er läuft**
- Im Netzspiel nur beim Host.
- Im Modus „Weitergeben“ lokal.
- Der Mischungs-Seed verlässt das Gerät nie.
- Die Logik rechnet nur mit Ganzzahlen. Gerätegleiches Gleitkomma ist dadurch kein Thema, und es rechnet ohnehin nur ein Gerät.

**Verdeckte Information**
- **Kartengriffe** sind pro Runde zufällige Kennungen, nicht der Index im Deck.
  - Auch die Paarung von heller und dunkler Seite wird pro Runde ausgelost.
  - So verrät ein Griff weder Inhalt noch Paarung.
- **`view_for(sitz)` enthält:**
  - die eigene Hand: Griffe mit der aktiven Seite (die eigenen Rückseiten nur mit der Hausregel),
  - die Hände der Gegner: **ohne Griffe**, nur als sortierte Menge der für mich sichtbaren Seite (Bericht Hand/UX, 2.3),
  - von den Stapeln das jeweils Sichtbare: oben auf dem Nachziehstapel die inaktive Seite, außerdem die Ablage,
  - Wunschfarbe, Richtung, wer am Zug ist, Mau-Status und Punkte.
- **`events_for(sitz, ereignisse)` filtert Ereignisse je Empfänger.** Beispiel `drew`: Der Besitzer bekommt Griff und Vorderseite, alle anderen nur die öffentliche Seite.
- Beim Anzweifeln bekommt nur der Herausforderer die Hand des Angezweifelten.

**`hints_for(sitz)`** liefert:
- `playable: [griffe]`
- `actions: ["draw", "keep", "mau", "catch", "challenge", …]`
- `prompt: {kind: "color" | "player" | "confirm", options, deadline}`
- `msg`

**Bot:** Er dient für Tests, als Füllspieler und für die Option „Bot übernimmt einen getrennten Spieler“.

**Autosave:** Nach jedem Zug werden Seed und Aktionslog gespeichert (`user://partie.json`). Stürzt der Host ab, kann er „Partie fortsetzen“, und die Clients kommen mit ihrem Token zurück.

### 1.2 Netz

**Nachrichtenformat**
- JSON-Text mit `{"v": <proto>, "t": "<typ>", …}`.
- Nur Text-Schlüssel. Godot liefert alle JSON-Zahlen als Float; jede Zahl wird beim Lesen geprüft und umgewandelt.
- Größengrenzen: 8 KB für Client-Nachrichten, 64 KB für Host-Nachrichten.
- `StreamPeerTCP.set_no_delay(true)`.

| Richtung | Typ | Inhalt |
|---|---|---|
| C→H | `hello` | proto, key (aus dem Link bzw. der UDP-Antwort), token?, name, client `app`/`web`, app_version, Gerät |
| H→C | `welcome` / `reject` | Sitz und Token bzw. Code und Grund; das Format von `reject` bleibt über alle Versionen gleich (Muster `encode_reject`) |
| H→C | `lobby` | rev, Spieler, Sitze, Regelzusammenfassung als Text, Phase |
| C→H | `wish` | seq, Name/Avatar/Bereit (Muster `seq`/`ack` aus `NetLobby`) |
| H→C | `snap` | n, view, hints: das vollständige Bild für Einstieg und Wiederverbindung |
| H→C | `ev` | n, events[], hints |
| C→H | `act` | seq, a (`play`/`draw`/`keep`/`color`/`mau`/`catch`/`challenge`/`answer`), Argumente |
| H→C | `nack` | seq, Grund, damit die Karte zurückfedert |
| beide | `ping`/`pong` | alle 2 s; Funkstille ab 6–10 s gilt als „getrennt“ |
| C→H | `log` | Fehler und Messwerte des Browsers für `user://mehrspieler.log` |
| beide | `bye` | Grund |

**Wiederverbindung (Pflicht ab dem ersten Netz-Meilenstein)**
- Token: 128 Bit, im Browser mit `crypto.getRandomValues`, in Godot mit `Crypto.generate_random_bytes`.
  - Im Browser liegt es in `localStorage`, jeder Zugriff in try/catch.
  - Der Sitz bleibt reserviert.
- Nach dem Wiederverbinden bekommt der Client `snap`. Fehlende Ereignisse werden nicht nachgespielt; die Tischregie setzt einfach den Endzustand ohne Animation. Das ist einfach und robust.
- Notweg ohne Token (privater Tab): ein vierstelliger Platzcode auf dem Host-Bildschirm.
- Host-Option bei Abwesenheit: warten, nach x s aussetzen, oder der Bot übernimmt.
- Wechselt die IP des Hosts (WLAN-Wechsel):
  - App-Clients finden ihn per UDP über die Sitzungskennung (`sid`) wieder.
  - Browser-Clients müssen den neuen QR-Code scannen.

**Suche**
- Apps: `NetDiscovery` unverändert, die Antwort enthält zusätzlich `http_port`, `ws_port` und `key`.
- Browser: nur QR-Code oder Link. Browser können kein UDP.

**WLAN-Bindung:** `NetAndroid.host_plan` und `_bind`/`_host_hotspot` werden übernommen. Ein Host mit eigenem Hotspot bindet nie.

**Absicherung**
- Schlüssel im Pfad; Prüfung des `Origin`-Headers.
- Höchstens 20 Nachrichten pro Sekunde je Client, sonst Rauswurf.
- Der Host vertraut keiner Client-Angabe.

### 1.3 HTTP-Server

**Technik:** GDScript, `TCPServer` in einem eigenen `Thread`, nicht blockierend, mehrere Verbindungen gleichzeitig, GET und HEAD, optional `Range: bytes=N-` für abgebrochene Downloads.

**Routen**

| Route | Inhalt |
|---|---|
| `/j/<key>` | Einladungsseite mit Geräteweiche über den User-Agent |
| `/play/<key>` | Web-Client |
| `/app/MauMauFlip-X.Y.Z.apk` | die eigene APK |
| alles andere | 404 |

**Sonderfall Safari:** Safari probiert bei Links zuerst HTTPS. Ein TLS-Versuch (erstes Byte 0x16) wird sofort geschlossen, damit Safari schnell auf HTTP zurückfällt.

**Web-Dateien**
- Der Build legt `webclient.zip` mit vorkomprimierten `.gz`-Dateien nach `game/assets/`. Der Export nimmt die Datei über `include_filter="*.zip"` mit.
- Der Server liest sie über `ZIPReader` in den Speicher (unter 2 MB).
- Er schickt `Content-Encoding: gzip`, wenn der Browser das anbietet, sonst die unkomprimierte Fassung.
- Grund für die ZIP-Datei: Lose `.png`/`.svg` in `res://` würde Godot als Texturen importieren. **[Ableitung, im ersten Export prüfen]**

**APK:** `Share.java.prepareApk()` kopiert einmal `sourceDir` nach `user://share/MauMauFlip-X.Y.Z.apk`. Dieselbe Kopie dient dem FileProvider (Teilen-Menü) und dem HTTP-Server. So entfällt die Frage, ob `FileAccess` `/data/app/…` lesen darf.

**Warum GDScript-Thread und nicht Java**
- Beides läuft weiter, wenn die Godot-Hauptschleife pausiert.
- Vor dem Android-App-Freezer schützt Java auch nicht.
- Die GDScript-Fassung läuft aber auch am PC headless, und die Playwright-Tests brauchen genau das.

### 1.4 Weitergeben-Modus

- Die Engine läuft lokal und hängt an einem `LocalSeat`. Die Tisch-UI ist **derselbe Code** wie für Host und App-Mitspieler.
- Vor jedem Zug kommt die Übergabekarte (Muster `party_hud.gd`, 350 ms Tippsperre, „Zum Aufdecken halten“).
- Der Tisch dreht sich zum aktuellen Spieler. Der Sichtschutz zeigt keine Rückseitenfächer.
- „Mau“ wird automatisch geprüft, oder ein „Erwischt!“-Knopf erscheint kurz auf der Übergabekarte.
- **Mischform (Kann, fast kostenlos, weil Sitz und Verbindung getrennt sind):** Ein Gerät im Netz verwaltet mehrere Sitze mit Übergabe. Das hilft bei Kindern ohne Handy oder bei einem iPhone mit leerem Akku.

### 1.5 Updater

`updater.gd` und `Updater.java` werden mit diesen Änderungen übernommen:

| Änderung | Begründung |
|---|---|
| Repos `ShakieVan/Mau-Mau-Flip` und `-Beta` | neue Repos |
| Asset `MauMauFlip-X.Y.Z.apk` | ohne Leerzeichen; GitHub ersetzt Sonderzeichen, die URL-Prüfung würde scheitern |
| `Build.VERSION.SDK_INT`-Prüfungen und `catch (Throwable)` | `NoSuchMethodError` unter Android 7–8.1 (Fallstrick 5) |
| Knopf „Im Browser herunterladen“ | Notausgang, falls der Updater selbst kaputt ist |
| 403 als „GitHub-Limit erreicht“ anzeigen, nicht als „Keine Verbindung“ | geteiltes Urlaubs-WLAN, 60 Anfragen pro Stunde |
| geladene APK beim Start löschen, wenn die installierte Version gleich oder neuer ist | Fallstrick 9 |
| Zeitstempel erst nach einer erfolgreichen Antwort setzen | Fallstrick 11 |
| versionCode aus der Version berechnen: `X*1_000_000 + Y*1_000 + Z` | Fallstrick 4; eine Beta, die zum Release wird, ist dadurch automatisch höher |
| `build.ps1` bricht ab, wenn der Keystore fehlt | Fallstrick 3 |

- **Ein gemeinsamer Paketname und Schlüssel für beide Kanäle**, damit man zwischen Release und Beta wechseln kann.
- **Schlüssel:** sofort einen eigenen Release-Schlüssel anlegen und dreifach sichern, davon einmal offline. Ich empfehle, als Release zu exportieren (kleiner, nicht debuggable).
  - Dann fällt `adb run-as` weg.
  - Ersatz: „Protokoll teilen“ über das Teilen-Menü (`Share.java`). Die Browser-Protokolle laufen ohnehin über WebSocket ins Protokoll des Hosts.
  - Das ist deine Entscheidung (siehe 8).

### 1.6 APK-Weitergabe offline

1. **„App senden“:** `Share.java` mit `ACTION_SEND` und `createChooser`. Hauptweg ist Quick Share. Bluetooth ist laut AOSP-Quelltext unbrauchbar, weil es keine APK annimmt.
2. **Einladungsseite mit „App installieren“:** Download der APK vom HTTP-Server des Hosts.
3. **„Update vom Host“:**
   - Ein App-Mitspieler mit älterem Protokoll bekommt `reject {code: "version", host: "0.4.0", apk: "/app/…apk", size, sha256}`.
   - Seine App lädt die APK per `HTTPRequest` vom Host, prüft sie mit `Updater.verify()` (Paket, höherer versionCode, Signatur) und installiert.
   - Die SHA-256 berechnet der Host einmal im Thread und speichert sie je versionCode.
   - **Dieses `reject`-Format muss ab der ersten verteilten Version feststehen.** Alte Apps müssen es lesen können (Lehre aus dem Updater-Hotfix 0.2.26).
4. **Der Mitspieler hat die neuere Version:** Hinweis „Der Gastgeber hat eine ältere Version: schick sie ihm mit ‚App senden‘ oder spiel im Browser mit.“ Der Browserweg geht unabhängig von der Version immer.

### 1.7 Hotspot- und QR-Ablauf

**Bildschirm „Mitspieler einladen“ mit drei Kacheln:**
- **Gleiches WLAN:** großer Link-QR, darunter die Adresse im Klartext.
- **Spiel-WLAN** (LocalOnlyHotspot, späterer Meilenstein): ein QR-Code mit Schrittleiste: ① WLAN-QR `WIFI:T:WPA;S:…;P:…;;`, ② Link-QR, im Wechsel oder per Tipp.
- **App senden:** Teilen-Menü. Dazu „Link teilen“ (`text/plain`) für „Geräte in der Nähe“.

Unter den Kacheln zeigt ein Zähler, wie viele Spieler in der Lobby sind.

**Technik und Ersatzwege**
- QR-Erzeugung mit dem Kenyoni-Addon (GDScript, MIT).
- Die IP im Hotspot kommt aus `NetAndroid.hotspot_interfaces`. Seit Android 11 ist das Netz zufällig, man darf also nie 192.168.43.x annehmen.
- Läuft der System-Hotspot, scheitert LOHS mit `ERROR_INCOMPATIBLE_MODE`. Dann zeigt die App den Link-QR plus den Hinweis auf den WLAN-QR in den Hotspot-Einstellungen.
- Für iPhones ist ein Hotspot mit Internet stabiler, weil iOS ein automatisch verbundenes WLAN ohne Internet wieder verlässt.
- **Intent-Link (Soll):**
  - `intent://join?h=<ip>&p=24691&k=<key>#Intent;scheme=maumauflip;package=<paket>;S.browser_fallback_url=…;end`
  - Dafür braucht es einen `intent-filter` im Manifest und in `GodotApp.java` `onNewIntent`, das den Wert in ein statisches Feld schreibt (Draw2Race-Muster: Java speichert, GDScript fragt ab).
  - Rund 1 PT. **[Gerätetest auf Samsung Internet und Chrome]**

### 1.8 Darstellung und Effekte

**Godot**
- **Renderer Compatibility statt Mobile.** Hier widerspreche ich der Begründung im Bericht Hand/UX: In meiner Perspektive geht es nicht um gleiche Optik mit Godot-Web. Gründe für Compatibility:
  - alte Urlaubshandys mit schwachen Vulkan-Treibern,
  - kein 2D-HDR nötig, weil Glühen über additive Texturen entsteht,
  - Godot-Web bleibt als Rückfall offen.
- Bausteine:
  - Tischregie: Ereigniswarteschlange, bei mehr als 3 offenen Ereignissen doppelt so schnell, bei mehr als 8 sofort der Endzustand.
  - Hand als reine Funktion `layout(n, scroll, fokus)`.
  - Federn statt Tweens.
  - Effektkatalog in drei Stufen, Zeiten, Teilchenzahlen und Farben aus `effects.json`.

**Web**
- Dieselbe Gliederung in TypeScript:
  - `director.ts`, `hand.ts` (Formeln und Konstanten aus `layout.json`, geprüft mit Golden-Vektoren), `effects.ts`
  - PixiJS-`ParticleContainer` mit additivem Blending, `TilingSprite` für den Richtungsring
  - DOM-Overlays für Name, Lobby und Hinweise
- Startet in der Stufe „Reduziert“ und lässt sich umschalten.
- Ton erst nach dem ersten Tippen („Beitreten“).

### 1.9 Sitzordnung

- Den Tisch-Editor gibt es nur beim Host (Godot): Avatare von App- und Browser-Spielern auf Plätze ziehen, „Zufällig“, Startspieler.
- Die Lobby schickt `seats: [spieler-ids]`.
- Jeder Client dreht die Ansicht selbst: r = (Platz − meinPlatz + n) mod n, dann wird der Winkel gestaucht. Die Formel aus dem Bericht steht in GDScript und TS, mit gemeinsamen Golden-Vektoren für n = 2–10.
- Nur drehen, nie spiegeln.
- Prüfhilfe auf jedem Gerät: „Links von dir: Lena – stimmt das?“

### 1.10 Hausregeln

- `RuleConfig` mit den Voreinstellungen aus dem Regelbericht (Offiziell R24, Klassisch 500, Familie, Mau-Mau-Tradition, Chaos, Schnell).
- Den Regelbildschirm gibt es nur im Godot-Host.
- Clients bekommen eine vom Host formulierte Textzusammenfassung.
- Neue Bedienung (Reinwerfen, 7-Tausch mit Zielwahl, Anzweifeln) läuft über die allgemeinen `prompt`/`actions`-Hinweise. Der Web-Client braucht dafür nur einmal die allgemeinen Abfrage-Bausteine.
- Reinwerfen und Erwischen entscheidet der Host nach Ankunftszeit, mit etwa 1,5 s Schonfrist.

---

## 2. Anforderungen: wie und wie gut erfüllt

| Anforderung | Lösung | Android-App | iPhone-Browser |
|---|---|---|---|
| GitHub statt Play Store, Release- und Beta-Repo | wie Draw2Race, `gh release create`, Beta als Pre-Release | voll | entfällt; der Client kommt vom Host |
| Update-Funktion | Updater übernommen und verbessert (1.5) | voll, mit Notausgang über den Browser | **nie nötig**, der Client hat immer die Host-Version |
| APK an Geräte in der Nähe | Quick Share, Download von der Einladungsseite, Update vom Host | gut. Grenzen: Quick-Share-Sichtbarkeit „Alle, 10 Min.“, Freigabe „Unbekannte Apps“ beim Empfänger, ab 2027 Entwicklerverifizierung | – |
| Mitspielen ohne App | Web-Client über http:// und ws:// | – | **gut für das Spiel, mit Einschränkungen**: kein Wake Lock (NoSleep-Trick), kein Vollbild, WebSocket bricht beim Sperren ab (Wiederverbindung), Ton erst nach Tippen und still beim Stummschalter |
| Link teilen und QR-Code | ein Link-QR mit Geräteweiche; Link über das Teilen-Menü | voll; mit App über den Intent-Link | QR über die Kamera; Quick Share zu AirDrop nur auf wenigen neuen Geräten, also bleibt der QR der Hauptweg |
| „Bessere Methode“ als Browser? | geprüft und verworfen (siehe Liste unter der Tabelle) | – | Browser bleibt die beste Lösung |
| Weitergeben | Engine lokal und Übergabekarte | voll | auch Rückfall für iPhone-Besitzer |
| Netzwerk lokal | WS-Host, UDP-Suche, Hotspot-Logik aus Draw2Race | voll | voll über den QR-Link; Hotel-WLAN mit Geräte-Isolierung nur über das Spiel-WLAN |
| Sortierbare Hand, „fancy“ scrollbar | anpassungsfähige Hand A/B/C, Schwung, Einrasten, Gummiband, Federn | voll inklusive Haptik-Raster | Verhalten gleich (dieselben Formeln); keine Haptik; Safari-Leisten kosten Höhe |
| Sitzordnung aus Sicht jedes Spielers | 1.9 | voll | voll |
| Coole Effekte | Katalog in drei Stufen, siehe nächste Tabelle | voll | etwa 75–85 % des optischen Eindrucks, deutlich weniger „Gefühl“ (keine Haptik) **[Schätzung]** |
| Hausregeln | `RuleConfig`, Abfragen vom Host | voll | voll, ohne Client-Update |

**Verworfene Alternativen zum Browser:**
- Godot-Web-Export: Die Secure-Context-Prüfung blockiert den Start über http://; ohne die Prüfung gibt es keinen Ton (AudioWorklet).
- PWA: kein Service Worker ohne HTTPS.
- Native iOS-App: braucht Mac und 99 USD im Jahr.
- Online gehosteter Client: Eine https-Seite darf kein ws:// ins lokale Netz öffnen (gemischter Inhalt, LNA).
- Optional später NFC-Tag-Emulation, ein Experiment.

**Effektqualität im Einzelnen**

| Effekt | Android (Godot) | iPhone-Browser (Pixi) |
|---|---|---|
| Wurfbogen, Landung, Sortier-FLIP, Federn | voll | gleich, dieselben Formeln und Konstanten |
| Karte wenden (Faux-3D) | Shader | Skalierung nach Kosinus plus Scherung, fast gleich |
| Glühen | additive, vorgeblurrte Texturen | **dieselben Texturen**, gleich |
| Joker-Strahlen aus der sichtbaren Kontur | `CPUParticles2D` mit `DIRECTED_POINTS` | derselbe Abtast-Algorithmus (~80 Zeilen TS) mit Pixi-Partikeln, fast gleich |
| Richtungsring, animierter Richtungswechsel | UV-Shader, Tween auf die Geschwindigkeit | `TilingSprite` mit Tween, gleich |
| Zieh 5, Zieh bis Farbe (Spielautomat), Konfetti | 800 Teilchen, Line2D-Spuren | höchstens 300 Teilchen, einfachere Spuren, leicht reduziert |
| Flip-Stimmung (Himmel, Sonne/Mond, Sterne) | Vollbild-Shader | Ebenen mit Farb-Tween oder portierter GLSL-Filter, reduziert bis fast gleich |
| Bildschirmwackeln | ja | ja |
| Haptik | voll | Android-Chrome nur die Dauer; iPhone nichts (Checkbox-Trick als Kann) |
| Holo-Joker mit Lagesensor | ja | **nein**, Sensoren nur im sicheren Kontext |
| Musik und Klänge | ja | ja, nach dem ersten Tippen, beim Stummschalter still |

---

## 3. Wiederverwendung aus Draw2Race

| Draw2Race (Zeilen) | Verwendung | Anpassung |
|---|---|---|
| `game/scripts/updater.gd` (317), `Updater.java` (88) | fast 1:1 | Konstanten, Texte, Verbesserungen aus 1.5; `verify()`/`install()` auch für die APK vom Host |
| `NetHelper.java` (260), `net_android.gd` (338) | 1:1 | Paket- und Sperrenname; den eingecheckten Stand nach dem S24-Fix nehmen (dort liegen noch nicht eingecheckte Änderungen) |
| `net_discovery.gd` (310) | 1:1 | Magie `MMF-HOST`/`MMF-SUCHE`, Felder `http_port`, `ws_port`, `key` |
| `net_protocol.gd` (224) | etwa 50 % | `clean_name`, `unique_name`, Suchpakete, `directed_broadcast`, `check_hello`-Reihenfolge; `encode`/`decode` werden JSON; `reject` als festes JSON |
| `net_session.gd` (594) | etwa 40 %, als Muster | `hello`/`welcome`/`reject`, Ping und Funkstille, `close_gracefully`, Schließen nach `poll` verschieben; ENet-Teile (Drossel, Kanäle, Uhrabgleich) fallen weg; neu `WsServer`/`WsClient` |
| `net_lobby.gd` (1052) | etwa 35 %, als Muster | `seq`/`ack`-Wünsche, „Bereit“ bei Einstellungsänderung zurücksetzen, `away`, `_bind`/`_host_hotspot`/`refresh_status`, Test-Schnittstellen (`overrides`, `android_api`, `forced_status`); `join_block` wird zur Platzreservierung |
| `net_log.gd` (59), `net_test_screen.gd` (662) | 1:1 bzw. umbauen | Diagnosebildschirm zeigt zusätzlich HTTP- und WS-Zähler und Browser-Clients |
| `net_cli.gd`, `lobby_cli.gd`, `tools/net_test.ps1` | umbauen | Host plus N headless-Godot-Mitspieler plus M Playwright-Clients, Prüfsummen über öffentliche Daten |
| `party_hud.gd` (Übergabekarte), `pass_party.gd` (Namen) | Muster | Übergabe vor jedem Zug, Tisch dreht sich |
| `lobby_hud.gd` (893) | Muster | Aktualisieren an Ort und Stelle über Signaturen, Toasts, Netzhinweise, Dialoge oben im Bild |
| `player_colors.gd` | Algorithmus | OKLab und Machado zur **Prüfung der Kartenpaletten**; Spieler über Avatar unterscheiden, nicht über Farbe |
| `tools/setup.ps1`, `build.ps1`, `godot_run.ps1` | Gerüst | Mutex `Global\MauMauFlipGodot`; Schritte Node, `npm ci`, `vite build`, ZIP, Vitest, Playwright; Abbruch ohne Keystore; versionCode berechnen |
| `game/tests/test_*.gd`-Muster, `.gitignore` für `android/build`, `org.gradle.daemon=false` | 1:1 | – |
| `AGENTS.md`, `IMPLEMENTIERUNG.md`, `MULTIPLAYER_RECHERCHE.md` (Belegmarken) | Struktur | – |

**Nicht übernehmen:** `net_race.gd`, `net_draw.gd`, `name_tags.gd`, die Rennfelder in `NetLobby`, `RaceVehicle`-Bezüge.

---

## 4. Aufwand und Meilensteine

**PT** heißt hier: ein Arbeitstag des Nutzers mit Claude als Programmierer, einschließlich Gerätetests und Feinschliff. Grafikproduktion steht getrennt. Engpass sind Gerätetests und Entscheidungen, nicht das Code-Schreiben. **[Schätzung]**

| M | Inhalt | PT | Ergebnis |
|---|---|---|---|
| **M0** | Gerüst: Godot 4.6.1, Compatibility, Paketname, Release-Keystore und Sicherung, `setup.ps1`/`build.ps1` (mit portablem Node), **Gradle-Export im Pfad mit Leerzeichen**, Updater portiert, beide Repos; Update-Kette 0.1.1 → 0.1.2 am S10/S21/S24 geprüft | 3–4 | Der Updater stimmt ab der ersten verteilten Version |
| **M0b** | Durchstich (Wegwerf-Code erlaubt): Godot auf Android liefert eine HTML-Seite und ein WS-Echo; S24-Hotspot ohne Internet, S10 mit Chrome, wenn möglich ein iPhone (Bekannte oder BrowserStack) | 1–2 | Grundannahmen belegt, **bevor** die UI doppelt gebaut wird |
| **M1** | Regelkern R24 mit den Optionen aus 1.13, `view_for`/`events_for`/`hints_for`, Bots, 10 000 Bot-Partien, Leck-Test | 5–7 | geprüfte Engine |
| **M2** | Godot-Tisch: Hand Stufe A/B, Stapel, Farbring, Richtungsring, Tischregie, Grundanimationen, Joker-Farbrad, Sitzrotation, Weitergeben | 8–11 | **erstes spielbares Spiel auf einem Handy** (Beta) |
| **M3** | Netz App ↔ App: WS-Host und -Client, JSON-Protokoll mit Golden Files, Lobby, Sitz-Editor, Token-Wiederverbindung, Autosave und Fortsetzen, Suche und NetAndroid übernommen, `net_test.ps1` | 7–10 | Netzspiel zwischen Androids |
| **M4** | HTTP-Server, Einladungsseite, Web-Client MVP (Lobby, Fächer A/B, Tisch, Spielen/Ziehen/Farbe/Mau, Wiederverbindung, Fern-Protokoll), QR-Einladung, Playwright-Ende-zu-Ende | 10–14 | **iPhone spielt mit** |
| **M5** | `Share.java` („App senden“), APK-Download, Update vom Host, Intent-Link | 3–5 | **urlaubstauglich** |
| M6 | Hand komplett: Karussell, Fischauge, Schwung, Sortiermodi, Joker-Geste, Übersichtsblatt. Godot 6–8, Web 4–6 | 10–14 | |
| M7 | Effekte: Godot (Muss und Soll) 10–14, Web-Stufe 6–9 | 16–23 | |
| M8 | Hausregeln, Ansagen und Erwischen, Anzweifeln, Bis zum Letzten, Stapeln, Reinwerfen, Regelbildschirm | 5–8 | Engine-lastig, im Web nur die Abfrage-Bausteine |
| M9 | Spiel-WLAN (LOHS, `Hotspot.java`, Laufzeitberechtigung), WLAN-QR | 3–4 | dazu Gerätetests auf allen drei Samsungs |
| M10 | Kartengrafik (SVG-Baukasten), Klänge, Feinschliff | 6–10 | parallel ab M2 |

**Summen**
- Gesamt etwa **77–112 PT**.
- Urlaubstaugliches MVP (M0–M5 plus Mau-Ansage aus M8): etwa **38–55 PT**.
- **Davon geht auf den Web-Client: etwa 20–28 PT (rund 25 %).** Ohne Browser-Client wäre das Projekt um diesen Anteil kleiner.

**Reihenfolge nach Risiko:** M4 kommt bewusst **vor** dem großen Hand- und Effekt-Feinschliff. Das iPhone ist die größte Unbekannte, und die UI sollte nicht zweimal poliert werden, bevor der Weg trägt.

---

## 5. Risiken

| Risiko | W | A | Gegenmaßnahme |
|---|---|---|---|
| **iPhone ohne Testgerät:** verzögerter Rückfall von HTTPS auf HTTP, ws:// im Hotspot ohne Internet, iOS verlässt ein WLAN ohne Internet, Sperre trennt die Verbindung, Drittbrowser zeigen den Dialog „lokales Netzwerk“ | hoch | hoch | Durchstich M0b; robuste Wiederverbindung mit Snapshot; TLS-Versuch sofort schließen; Hinweise „Safari verwenden“, „Automatische Sperre: Nie“, „‚Kein Internet‘ ist normal“; nach 10 s ohne Verbindung „Bist du noch im WLAN …?“; BrowserStack und Freunde ab M4 (siehe 6) |
| **iOS-Updates ändern WebKit** (Beispiele: ws-Aussetzer in einer iOS-26-Beta, LNA in Arbeit) | mittel | hoch | iPhone-Freunde testen den Beta-Kanal; Fern-Protokoll; das QR-Prinzip ist von LNA laut Chrome-Doku nicht betroffen (Anfragen lokal zu lokal), für Safari **[Gerätetest]** |
| **Zwei Codebasen laufen auseinander** (GDScript und TS) | hoch | mittel | dünner Client ohne Regeln; Hinweise und Texte vom Host; Golden Files in beide Richtungen; gemeinsame `layout.json`/`effects.json`/`palette.json`; eine Protokollversion; `build.ps1` lässt beide Testreihen laufen und bricht bei einem Fehler ab |
| **Doppelte UI-Arbeit** bei jeder Hand- und Effektänderung | sicher | mittel | Änderungen erst in Godot fertig machen, dann portieren; Web-Effekte bewusst eine Stufe einfacher; die Kosten sind ehrlich eingeplant (rund 25 %) |
| **Host-Hauptschleife pausiert** (Anruf, Teilen-Menü, Bildschirm aus) | mittel | mittel | `screen_set_keep_on(true)`; Clients zeigen „Gastgeber pausiert“ und warten; HTTP läuft im Thread weiter; Autosave; bei getötetem Prozess „Partie fortsetzen“ |
| **Android-Funktionen aus Godot** (LOHS-Callback ist eine Klasse, `OS.request_permission` nie erprobt, Intent-Daten) | mittel | mittel | Java-Helfer nach Draw2Race-Muster (statischer Zustand, JSON-Abfrage); LOHS erst in M9; Logik per `FakeAndroid` am PC testbar; ein Nicht-Samsung-Gerät leihen |
| **Entwicklerverifizierung 2027** (Installation und Updates nur registrierter Apps; offline eventuell Abbruch) | sicher (2027) | hoch | 2026 Konto anlegen (Limited mit 20 Geräten oder voll für 25 USD); Installation im Flugmodus testen, sobald es gilt; Browser-Client als Rückfall ganz ohne Installation |
| **Keystore-Verlust** | gering | sehr hoch | dreifache Sicherung; Build bricht ohne Schlüssel ab |
| **Leistung im Web** (alte iPhones, Speichergrenze etwa 300 MB) | gering | mittel | Pixi mit Atlas, unter 2 MB Client, unter 300 Teilchen, Start in „Reduziert“, automatische Rückstufung |
| **Leistung des Hosts** (Hotspot, Server, Darstellung, Akku) | mittel | gering | rundenbasiert, im Leerlauf niedrige Bildrate (`low_processor_mode`); Hinweis „Ladekabel“ |
| **Neue Werkzeugkette** (Node, npm, Playwright) | mittel | gering | portables Node über `setup.ps1`, `package-lock.json`, PixiJS-Version festschreiben |
| **Informationsleck über manipulierte Clients** (DevTools) | mittel | mittel | Filterung je Empfänger beim Host, zufällige Griffe, automatischer Leck-Test |
| **Pfad mit Leerzeichen** (Gradle, Vite) | mittel | gering | in M0 als Erstes prüfen |

---

## 6. Teststrategie ohne iPhone und Mac

1. **Regelkern headless (Godot):**
   - Kontrollsummen: 112 Karten, Punktsumme hell 1280 und dunkel 1480.
   - Jede Option und jeder Sonderfall aus 1.13 als eigene Prüfung.
   - 10 000 Bot-Partien mit Invarianten (keine Karte doppelt oder verloren, Zug immer gültig).
   - **Leck-Test:** Jede `view` und jedes `ev` je Sitz wird serialisiert, und keine verdeckte Seite darf darin vorkommen.
2. **Vertragstests über das Protokoll:**
   - Godot erzeugt `shared/protocol/fixtures/*.json`, Vitest prüft und rendert sie.
   - TS erzeugt Absichten, Godot prüft sie.
   - Golden-Vektoren für Layout und Sitzrotation auf beiden Seiten.
3. **Ende-zu-Ende am PC (`tools/e2e.ps1`):**
   - Ein headless Godot-Host, zwei headless Godot-App-Mitspieler und drei Playwright-Clients (WebKit mit iPhone-SE- und iPhone-15-Profil, Chromium, Firefox) spielen ganze Partien mit Bot-Zügen.
   - Störfälle:
     - Seite schließen und mit Token wieder öffnen,
     - `visibilitychange` mit WS-Abbruch,
     - Host-Pause von 20 s,
     - TLS-Bytes an den HTTP-Port,
     - falsches Protokoll,
     - Platzcode ohne Token.
   - Kontrollbilder: WebKit hochkant und quer, Godot-Kontrollbilder wie `lobby_shots`.
4. **Android-Browser als Clients** (S10, S21, S24, Chrome und Samsung Internet): findet Touch- und Netzprobleme. Es ist aber Blink, nicht WebKit.
5. **WebKitGTK (Epiphany) über WSL2:** eine zweite WebKit-Stichprobe.
6. **Echte iPhones in der Cloud:**
   - BrowserStack Live mit Local-Tunnel; Host ist der Windows-Build am PC.
   - Kostenlos über das Open-Source-Programm, **setzt öffentlichen Quellcode voraus** (wie beim Draw2Race-Repo).
   - Einmal je Meilenstein ab M4. Prüft Laden, Touch, Ton und Wiederverbindung. Sperrbildschirm und Hotspot lassen sich dort nicht prüfen.
7. **iPhones von Freunden** mit fester Checkliste:
   - QR-Scan und wie lange der Rückfall auf HTTP dauert
   - Name eingeben, Hand scrollen, Joker-Geste
   - 30 s sperren, dann zurück
   - WLAN-QR über LOHS
   - Hotspot ohne Internet, 10 min Spiel
   - Stummschalter
   - Chrome als Standardbrowser
   - Debuggen: Fern-Protokoll über WebSocket ins Host-Protokoll (`window.onerror`, Reconnect-Zähler, RTT), Eruda mit `?debug=1`, bei Bedarf inspect.dev unter Windows. iPhone-Tester brauchen keine Installation; sie testen automatisch die Version des Hosts, also auch Betas.

---

## 7. Selbstkritik an dieser Perspektive

- **Der größte Nachteil ist die doppelte Darstellung.** Die Hand-UX ist laut Bericht der größte Muss-Block (30–40 PT). Selbst als dünner Client kostet der Web-Client rund ein Viertel des Projekts, und jede Feinschliff-Runde fällt zweimal an. Mit Godot-Web wäre es *ein* UI-Code.
- **Warum trotzdem nicht Godot-Web?** Hier widerspreche ich dem Vorschlag im Bericht Hand/UX, das per „frühem Versuch“ zu entscheiden:
  - Es braucht einen Patch gegen die Secure-Context-Prüfung, den die Godot-Maintainer ablehnen. Jedes Godot-Update kann ihn brechen.
  - Ohne AudioWorklet gibt es keinen Ton.
  - 6–9 MB WASM müssen über den Hotspot laden und auf alten iPhones kompilieren.
  - Bekannte iOS-Fehler (WebGL context lost, Audio-Abstürze) sind noch offen.
  - Der Versuch selbst bräuchte genau das fehlende iPhone.

  Der Compatibility-Renderer hält diese Tür trotzdem offen.
- **Die Android-App verliert die gehärtete ENet-Sitzung.** Für ein Kartenspiel ist das vertretbar. Der neue WS-Code ist aber neu und muss die Draw2Race-Lehren (Funkstille, sauberes Trennen, Schließen während `poll`) neu beweisen.
- **Dünne App-Clients haben keine Offline-Logik.** Fällt der Host aus, steht alles. Das gilt aber für jede Variante mit autoritativem Host.
- **Die Effektqualität im iPhone-Browser kann ich nicht belegen,** nur schätzen (75–85 %). Haptik fehlt dort ganz. Das „überwältigende“ Gefühl bleibt eine Stärke der App.

---

## 8. Offene Entscheidungen für dich

1. Godot-Web endgültig verwerfen und den Web-Client mit PixiJS bauen (Vorschlag), oder Godot-Web als eintägigen Versuch zusätzlich zu M0b?
2. Nur WebSocket als Transport, ENet entfällt (Vorschlag)?
3. Release-Export mit eigenem Schlüssel und „Protokoll teilen“ statt `adb run-as` (Vorschlag), oder Debug-Export wie bei Draw2Race?
4. Paketname, endgültig (zum Beispiel `de.maumauflip.game`), und Repo-Namen `Mau-Mau-Flip` / `Mau-Mau-Flip-Beta`?
5. Quellcode öffentlich (Voraussetzung für das kostenlose BrowserStack-Programm)?
6. Entwicklerkonto für 2027: Limited (20 Geräte) oder voll (25 USD)?
7. Ordner `Mau-Maul Flip` löschen?

**Relevante Pfade:**
- `C:\Users\Shakie\Documents\Programmierung\Draw2Race\game\scripts\net\net_session.gd`
- `...\game\scripts\net\net_lobby.gd`
- `...\game\scripts\net\net_discovery.gd`
- `...\game\scripts\net\net_android.gd`
- `...\game\scripts\updater.gd`
- `...\game\android\build\src\main\java\com\godot\game\{Updater,NetHelper,GodotApp}.java`
- `...\game\scripts\party_hud.gd`
- `...\game\scripts\lobby_hud.gd`
- `...\tools\{setup,build,godot_run,net_test}.ps1`
- Projektordner: `E:\Documents\Programmierung\Mau-Mau Flip`