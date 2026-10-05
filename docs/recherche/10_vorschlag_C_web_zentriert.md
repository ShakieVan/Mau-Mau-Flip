# Architekturvorschlag „Mau-Mau Flip“, web-zentrierte Variante

Ich habe nur gelesen und nichts verändert. Nebenbei geprüft:
- Im Projektordner `E:\Documents\Programmierung\Mau-Mau Flip` liegen bisher nur `.git` und `LICENSE`. Daneben gibt es noch den Ordner `Mau-Maul Flip`.
- Node.js/npm ist auf dem PC **nicht installiert**. JDK 17 (Temurin 17.0.18) ist vorhanden.

Kennzeichnung: **[belegt]** = Quelle, **[Bericht]** = Erfahrungsbericht, **[Schätzung]**, **[Gerätetest]** = nur am Gerät klärbar.

---

## 0. Kurzfassung

**Vorschlag:** Es gibt eine einzige Spieloberfläche in TypeScript. Den Tisch zeichnet PixiJS v8 mit WebGL2, Menüs, Lobby und Regeloptionen sind DOM/CSS. Der Regelkern ist ebenfalls TypeScript und läuft beim Host in einem Web Worker. Die Android-App ist eine **schlanke eigene Java-Hülle** (kein Capacitor) mit:
- WebView,
- eigenem HTTP-Server und WebSocket-Server, beide auf Threads im Vordergrunddienst,
- UDP-Suche,
- Updater, APK-Weitergabe, LocalOnlyHotspot und WLAN-Bindung.

iPhones, Android-Browser **und auch App-Clients** laden das Oberflächen-Paket vom Host. Dadurch gilt immer die Version des Hosts.

**Was diese Perspektive gewinnt:**
1. **Der iPhone-Spieler bekommt das volle Spiel.** Es ist derselbe Code mit denselben Shadern und Effekten, keine „Lite“-Fassung. Es fehlen nur Haptik, Wachhalten und Lagesensor; das liegt am Browser und gilt bei jeder Technik.
2. **Das Versionsproblem verschwindet weitgehend.** Draw2Race verlangt, dass alle Handys vorher auf dieselbe Version gebracht werden. Hier holt jeder Client die Oberfläche vom Host. Kompatibel sein muss nur noch die kleine Java-Schnittstelle zur Hülle, und die wächst nur durch Ergänzungen.
3. **Es gibt keine doppelte Darstellungsschicht.** Code liegt in zwei Sprachen vor: TypeScript für Kern und Oberfläche, Java für die Hülle. Bei Godot plus HTML-Client wären es GDScript, Java und TypeScript/HTML, und die Oberfläche gäbe es zweimal.
4. **Die echte Oberfläche lässt sich automatisch in WebKit testen** (Playwright), dazu Mobile Safari im iOS-Simulator auf einem GitHub-macOS-Runner (siehe 6).
5. **Server laufen nativ auf Threads.** Sie hängen also nicht an Godots Hauptschleife, die bei Pause still steht. Die APK lässt sich weiter ausliefern, während der Host das Teilen-Menü offen hat.
6. **Die APK ist klein** (geschätzt 8–25 MB), was die Offline-Weitergabe schnell macht. [Schätzung]

**Was sie kostet (ehrlich):**
- Godot-Wissen und GDScript-Code aus Draw2Race fallen weg. Direkt übernehmbar bleiben nur die Java-Helfer und die Konzepte.
- Es braucht eine neue Werkzeugkette: Node, Vite, Vitest, Playwright und Gradle ohne Godot.
- Die Brücke zwischen Java und JavaScript ist eine eigene Fehlerquelle.
- Dass der Host-Kern im Hintergrund weiterläuft, ist am Gerät zu prüfen.
- Auf sehr schwachen Handys ist die WebView vermutlich etwas weniger flüssig als natives Godot. [Schätzung]

**Mein Gesamturteil:** Für *genau diese* Anforderungen (iPhone im Browser gleichwertig, Offline-Verteilung, rundenbasiert, viel Menü- und Optionsoberfläche) ist web-zentriert die passendere Architektur. Ich würde sie aber erst nach einem **Durchstich von 4–6 Tagen mit klaren Abbruchkriterien** festschreiben (Meilenstein M0).

---

## 1. Komponenten-Übersicht

```
┌──────────────────────────── HOST-HANDY (Android-App „Mau-Mau Flip“) ─────────────────────────────┐
│ WebView (System-Chromium)                                                                           │
│  ├─ UI-Paket (TS)  ── Tisch: PixiJS v8 (WebGL2) · Menüs/Lobby/Regeloptionen: DOM/CSS               │
│  │    └─ Tischregie: spielt nummerierte Ereignisse ab (Rückstand → schneller, >8 → Endzustand)     │
│  └─ Web Worker „Host-Kern“ (TS, ohne DOM, dieselbe Datei läuft in Node für Tests/PC-Host)          │
│       Regel-Engine (Seed nur hier) · RuleConfig/Hausregeln · Lobby · Sitzplan · viewFor(seat)       │
│       Ereignislog je Runde · Platz-Token · Snapshot nach jedem Zug                                  │
│            ▲ postMessage (JSON)                                                                    │
│ ─ ─ ─ ─ ─ ─│─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│
│ Java-Hülle  │                                                                                     │
│  Bridge (androidx.webkit addWebMessageListener; Fähigkeiten je Herkunft freigegeben)                │
│  HostService (Vordergrunddienst, nur während eine Lobby offen ist)                                  │
│   ├─ HttpServer  :24700  /j/<token>/ → UI-Paket (.gz)  ·  /app → Landing  ·  /MauMauFlip-x.y.z.apk  │
│   │                      (APK direkt aus ApplicationInfo.sourceDir, Range, Content-Length)          │
│   │                      TLS-Versuch (erstes Byte 0x16) → sofort schließen (Safari „HTTPS zuerst“) │
│   ├─ WsServer    :24701  (Java-WebSocket 1.6.0) – reiner Transport: conn-id ↔ JSON-Text            │
│   └─ Discovery   :24702/24703 UDP (Port von NetDiscovery: Ankündigung, Rundruf, Gateway-Probe)    │
│  NetHelper (aus Draw2Race: Bindung, Hotspot-Erkennung, Multicast) · LocalHotspot (LOHS, neu)        │
│  Updater (GitHub Release + Beta, verify/install aus Draw2Race) · ApkShare (FileProvider, ACTION_SEND)│
│  Haptik (VibrationEffect mit Stärke) · FLAG_KEEP_SCREEN_ON · immersiv · NativeLog (Datei)           │
└─────────────────────────────────────────────────────────────────────────────────────────────────────┘
        │ http:// + ws://                  │ http:// + ws://                │ UDP-Suche, dann http:// + ws://
┌───────────────────────┐   ┌──────────────────────────┐   ┌─────────────────────────────────────────┐
│ iPhone – Safari        │   │ Android – Chrome          │   │ Android-App als Client                    │
│ QR → lädt Paket vom Host│   │ QR → Landing: „App        │   │ WebView navigiert zu http://host/j/<t>/  │
│ Token in localStorage  │   │ installieren“ oder „Im     │   │ = Paket des HOSTS; Bridge nur harmlos:   │
│ Neu verbinden bei       │   │ Browser spielen“           │   │ Haptik, wach, Lage, Log                   │
│ visibilitychange/pageshow│  │                            │   │ nativ: „Update vom Host“ (verify)        │
└───────────────────────┘   └──────────────────────────┘   └─────────────────────────────────────────┘

WEITERGEBEN-MODUS: nur WebView + Host-Kern im Worker, mehrere lokale Plätze, Übergabekarte vor jedem Zug;
                   kein Server, kein Netz. Läuft auch in jedem Browser (z. B. PC).
PC-ENTWICKLUNG:    tools/devhost (Node): derselbe Host-Kern + ws + statischer Server → Playwright, iPhones von
                   Freunden im Heim-WLAN, BrowserStack Local; Vite-Dev-Server mit Live-Reload aufs Handy.
```

### Zuständigkeiten im Einzelnen

**Regelkern**
- Er ist eine deterministische Zustandsmaschine in TypeScript: `apply(state, intent) → {state, events[]}`.
- Zufall kommt aus einem Seed-PRNG (z. B. sfc32). Der Seed entsteht mit `crypto.getRandomValues`, das auch ohne Secure Context verfügbar ist [belegt, Bericht browser-iphone]. Er verlässt den Worker nie.
- Für jede Runde wird zufällig gepaart, welche Vorderseite auf welcher Rückseite liegt (Regelbericht 1.1).
- Ganzzahlig, also ohne die Gleitkomma-Probleme aus Draw2Race.

**Autorität und verdeckte Information**
- Nur der Host-Kern entscheidet. Clients schicken nur **Absichten**: `play {card, color?, seq}`, `draw`, `pass`, `mau`, `catch`, `challenge`, `pick_seat` … Der Host antwortet mit `ack`/`reject {reason}`.
- Ein Client bekommt ausschließlich `viewFor(seat)`:
  - die eigene Hand (aktive Seite);
  - von den Gegnern nur die Rückseiten als **sortierte Menge** (gegen das Sortier-Leck, Bericht hand-ux 2.3) und die Kartenzahl;
  - vom Nachziehstapel die oben sichtbare Gegenseite;
  - eine Liste `playable` mit den Karten, die er gerade legen darf. Der Client prüft also keine Regeln selbst, es gibt nichts doppelt.
- Beim Anzweifeln geht die Hand nur an den Herausforderer.
- Der Host kennt technisch alles. Das ist unvermeidbar (Bericht netz 3.7).

**Protokoll**
- JSON über WebSocket mit Hülle `{t, proto, …}` und Schemaprüfung auf beiden Seiten (z. B. valibot).
- Muster aus Draw2Race:
  - `hello` / `welcome` / `reject {code, reason}`;
  - `lobby {rev, …}` als vollständiger Zustand;
  - Wünsche mit `seq`/`ack`, damit nichts flackert;
  - `ev {n, …}` als fortlaufende Ereignisse, `view` als vollständige Sicht nach dem Wiederverbinden.
- Präsenz über einen Ping auf Anwendungsebene alle 2 s. Browser-JavaScript kann keine WS-Ping-Frames senden.

**Wiederverbinden (Pflicht)**
- Platz-Token mit 128 Bit aus `getRandomValues`, im Browser in localStorage (mit try/catch abgesichert).
- `hello {token, last_ev}`: Der Host reserviert den Platz und schickt danach `view` und die fehlenden Ereignisse. Die Tischregie überspringt die Effekte.
- Notweg ohne Token: „Ich bin wieder da: Platz 3“, der Host bestätigt.
- Option als Hausregel: nach einer Zeitgrenze automatisch aussetzen.

**Hostausfall**
- Nach jedem Zug wird ein Snapshot des Kerns gespeichert, über die Bridge in eine Datei, sonst in IndexedDB.
- Stürzt die App ab oder wird sie getötet, stellt der Host das Spiel beim Neustart wieder her. Die Clients verbinden sich dann mit ihren Token neu.
- Eine Host-Übergabe gibt es bewusst nicht (wie Draw2Race).

---

## 2. Anforderungen: wie sie erfüllt werden und wie gut

| Anforderung | Umsetzung | Bewertung |
|---|---|---|
| **Weitergeben-Modus** | Host-Kern lokal, mehrere Plätze. Übergabekarte vor *jedem* Zug: ganze Fläche ist ein Knopf, Tippsperre 350 ms, „Zum Aufdecken halten“ 500 ms. Der Tisch dreht sich hinter dem Sichtschutz, der keine Rückseitenfächer zeigt. | **Gut.** Braucht kein Netz und läuft sogar im PC-Browser. |
| **Netzwerk (WLAN)** | App-Clients finden den Host per UDP (Port von `NetDiscovery`), Browser per QR. Verbindung per WebSocket über TCP; für ein rundenbasiertes Spiel ist das zuverlässig genug. ENet entfällt komplett. | **Gut.** Ein einziger Transport für alle. |
| **iPhone im Browser** | Volles Paket vom Host über `http://`, Verbindung über `ws://`. Keine Secure-Context-APIs (kein Service Worker, Wake Lock, `navigator.share`, `crypto.subtle` oder `randomUUID`). | **Sehr gut im Vergleich:** dieselbe Oberfläche wie auf Android. Grenzen kommen nur vom Browser (Tabelle unten). |
| **Link per QR / an Geräte in der Nähe** | QR wird im TS-Code erzeugt (kleine Bibliothek). „Link teilen“ läuft nativ über `ACTION_SEND text/plain` (Quick Share; ob Quick Share auch Links überträgt: [Gerätetest]). AirDrop-Austausch nur auf neuen Android-Geräten, die S10, S21 und S24 eher nicht [Bericht]. **Der QR bleibt Hauptweg.** | Gut, für iPhones nur per QR. |
| **APK an verbundene Geräte und Geräte in der Nähe** | (1) Landing-Seite `/app`: Android bekommt „App installieren (x MB)“, die APK wird nativ aus `sourceDir` gestreamt. (2) Teilen-Menü: `sourceDir` nach `files/share/MauMauFlip-x.y.z.apk` kopieren, FileProvider, `ACTION_SEND` → Quick Share. (3) **„Update vom Host“** für App-Clients mit älterer Version: native Prüfung mit `Updater.verify` (Paket, höherer versionCode, gleiche Signatur). (4) Bluetooth nein, AOSP nimmt keine APK an [Quellcode, Bericht apk]. | **Gut**, dank kleiner APK auch schnell. Grenzen: Play Protect, „Unbekannte Apps“ beim Empfänger und ab 2027 die Entwicklerverifizierung. Die betreffen jede Technik gleich. |
| **Update-Funktion wie Draw2Race** | `updater.gd` nach Java portieren, Logik unverändert: `/releases/latest` und Beta-Liste, höchste Version gewinnt, `digest`-SHA-256, exakte URL, Asset-Name `MauMauFlip-X.Y.Z.apk`, Cache, Prüfung höchstens alle 24 h. `HttpURLConnection.setReadTimeout(30 s)` wirkt **pro Lesevorgang**, ist also von selbst der Stillstands-Wächter; die Falle aus 0.2.26 kann nicht entstehen. Neu: Knopf „Im Browser herunterladen“. Dialog in TS über die Bridge. | **Sehr gut.** Browser-Spieler brauchen gar kein Update, sie bekommen immer die Host-Version. |
| **Zwei GitHub-Repos** | `ShakieVan/Mau-Mau-Flip` (Releases, Quellcode) und `ShakieVan/Mau-Mau-Flip-Beta` (nur Pre-Releases). Konventionen wie in Draw2Race. `tools/release.ps1` statt Handarbeit. | Wie Draw2Race, etwas mehr automatisiert. |
| **Hotspot im Urlaub** | LOHS-Helfer in Java: SSID und Passwort auslesen, ein QR mit Schrittleiste („① WLAN“ → „② Spiel“) wechselt automatisch. Fällt LOHS aus (z. B. `ERROR_INCOMPATIBLE_MODE`), weist das Spiel auf den System-Hotspot mit dem System-QR hin. Laufzeitdialog `NEARBY_WIFI_DEVICES` in einer normalen Android-Activity, was einfacher ist als aus Godot. | Gut. Gerätetests sind nötig (S10 mit Standort, Samsung-Eigenheiten). |
| **Handkarten sortierbar, „fancy“ scrollen** | Hand in Pixi mit Federn statt Tweens, Stufen A/B/C, Fischauge, Schwung, Einrasten, Gummiband (Formeln aus dem Bericht hand-ux). Pointer Events; `touch-action:none`, `overscroll-behavior:none`. Sortieren mit FLIP-Animation. Layout als reine Funktion, mit Vitest testbar. | **Gut**, identisch in App und Browser. iPhone-Falle: Wischgeste vom Bildschirmrand (siehe Risiken). |
| **Sitzordnung und Blickrichtung** | Tisch-Editor im DOM (Avatare per Drag auf Plätze), Lobbyzustand `seats[]`. Jeder Client dreht die Ansicht und spiegelt nie (`seat_pos` aus dem Bericht hand-ux nach TS). Prüfhilfe „Links von dir: Lena“. | Gut. |
| **Effekte** | Tischregie, Kartenshader, Partikel (ParticleContainer), Joker-Strahlen (Konturabtastung plus Punkt-in-Polygon, in TS 1:1), Flip-Drehbuch mit Vollbild-Shader, 3D-Wende über `PerspectiveMesh` [belegt: in Pixi v8], Glühen über vorgeblurrte additive Sprites, `pixi-filters` v6 nur für kleine Flächen. Drei Stufen, automatisches Herunterstufen. | **Gut bis sehr gut**, auf beiden Plattformen gleich. Leistung je Gerät ist im Durchstich zu messen. |
| **Hausregeln** | `RuleConfig` als versioniertes Objekt im Kern, Voreinstellungen (Offiziell, Klassisch 500, Familie …). Der Optionsbildschirm mit rund 30 Schaltern ist im DOM deutlich leichter als in Godot-Controls. | Gut. Reinwerfen bleibt aufwendig (Zeitstempel, Schonfrist). |
| **Kartendesign ohne Markenelemente des Originals** | SVG-Bausteine (Leitmotiv Tag/Nacht), zur Bauzeit ein WebP-Atlas, Zahlen als MSDF-Bitmapschrift. | Unabhängig von der Technik. |

### Effektqualität je Plattform

| Merkmal | Android-App (WebView) | Android-Browser | iPhone-Safari |
|---|---|---|---|
| Fächer, Federn, Wurfbögen, Partikel, Joker-Strahlen, Flip-Shader, 3D-Wende | voll | voll | **voll** (gleicher Code) |
| Glühen/Bloom | voll (vorgeblurrt), Filter sparsam | voll | voll |
| Haptik | **mit Stärke** (native Bridge) | ohne Stärke (`navigator.vibrate`) | keine (Kann: Switch-Trick ab iOS 18) |
| Ton | ohne Tipp-Freigabe (`setMediaPlaybackRequiresUserGesture(false)`) | nach erstem Tipp | nach erstem Tipp; Stummschalter schaltet „ambient“ stumm |
| Bildschirm wach | ja (`FLAG_KEEP_SCREEN_ON`) | NoSleep-Trick [Gerätetest] | NoSleep-Trick [Gerätetest] |
| Holo-Joker per Lagesensor | ja (Sensor über die Bridge) | nein (Secure Context) | nein |
| Vollbild | immersiv | Fullscreen-API | nein (Safari-Leisten) |

**Zur Leistung:**
- Auflösung auf `min(devicePixelRatio, 2)` begrenzen. iPhones haben DPR 3, das wäre Füllrate für nichts.
- Im Ruhezustand nur bei Bedarf zeichnen (Ticker stoppen), das spart Akku.
- Texturen insgesamt unter etwa 100 MB halten, wegen der iOS-Speichergrenze von etwa 300 MB [Bericht].

---

## 3. Wiederverwendung aus Draw2Race

Pfade relativ zu `C:\Users\Shakie\Documents\Programmierung\Draw2Race`.

### Java, praktisch 1:1 übernehmbar
- `game/android/build/src/main/java/com/godot/game/Updater.java` (88 Zeilen): `canInstall`, `openInstallPermission`, `installedVersion`, `verify`, `install`.
  - Paket umbenennen, zum Beispiel `de.maumauflip.app`.
  - `SDK_INT`-Prüfungen ergänzen oder minSdk 28 wählen (Fallstrick 5).
  - **Eigenen FileProvider** im Manifest eintragen (`androidx.core`, `files-path`). Den hat bisher die Godot-Bibliothek geliefert.
- `.../NetHelper.java` (260 Zeilen): `state()`, `interfaces()`, `bindWifi`/`bindNetwork`/`unbind`, Multicast-Sperre. Name der Sperre ändern. Den **committeten Stand nach dem S24-Fix** nehmen; im Arbeitsbaum gibt es ungespeicherte Änderungen.

### GDScript, das als Logik portiert wird (Tests mitnehmen)
- `game/scripts/updater.gd` (317 Zeilen) nach Java: `parse`/`parse_release`, `valid_version`, `compare_versions`, Kanalwahl und Cache, `prune`, SHA-256 in Blöcken.
  - Testfälle aus `game/tests/test_core.gd` Zeilen 177–205 als JUnit übernehmen.
- `game/scripts/net/net_android.gd` (338 Zeilen) nach Java: `host_plan`, `hotspot_network`, `hotspot_interfaces`, `bound_to_wifi`, `wifi_gateway`.
  - Fallbeispiele aus `FakeAndroid` in `game/tests/test_lobby.gd` (echte Geräteprotokolle) als JUnit-Fixtures.
- `game/scripts/net/net_discovery.gd` (310 Zeilen) und der Such- bzw. Adressteil von `net_protocol.gd` nach Java:
  - Ankündigung und Anfrage als JSON (neue Magie z. B. `MMF-HOST`/`MMF-SUCHE`);
  - `_parse_json`-Härtung, `directed_broadcast`, `ipv4_to_int`, `usable_ipv4`, `parse_address`;
  - Einträge nach `sid`, Verfall nach 4,5 s, Erkennung „nur angekündigt“ (`_only_announced`).
- `game/scripts/player_colors.gd`: OKLab und Machado als TS- oder Python-Prüfwerkzeug für die Kartenpaletten (Bericht hand-ux 5.1).

### Konzepte, die nach TypeScript wandern (kein Code)
- **`net_session.gd`:** Anmeldung mit Prüfreihenfolge, Ablehnungscodes mit versionsunabhängigem Format, Funkstille-Erkennung, sauberes Beenden.
- **`net_lobby.gd`:** vollständiger Lobbyzustand mit `rev`, `seq`/`ack`, „Bereit“ wird bei Einstellungsänderungen zurückgesetzt, `away` beim Pausieren, `back`/`close`, Revanche-Reihenfolge. `join_block` wird zur Platzreservierung.
- **`pass_party.gd`/`party_hud.gd`:** Übergabekarte mit Tippsperre, Spielerliste mit Stand.
- **`lobby_hud.gd`:** an Ort und Stelle aktualisieren statt neu aufbauen. In DOM mit gezielten Updates ist das einfacher, die Lehre bleibt.
- **`net_log.gd`:** Ringpuffer in TS. Browser-Fehler (`window.onerror`) gehen per WS ins Host-Log, die Bridge schreibt `files/mehrspieler.log`.
- **`net_test.ps1`, `lobby_cli.gd`:** Muster „Host plus N Clients, Ergebniszeilen mit Prüfsummen“ wird zum Playwright-Mehrspielertest.

### Infrastruktur
- **`tools/setup.ps1`** als Muster. Es lädt dann Node LTS (portabel nach `.tools/`), Gradle-Wrapper und SDK-Pfad statt Godot.
- **`tools/build.ps1`** als Gerüst, Ablauf:
  1. Mutex (neuer Name).
  2. `npm ci`, Vitest, Playwright.
  3. Vite-Build, `.gz` in `android/app/src/main/assets/web/`.
  4. JUnit, dann `gradlew assembleRelease`.
  5. Versionsabgleich und Kopie nach `builds/MauMauFlip-X.Y.Z.apk`.

  Neu, aus den Draw2Race-Fallstricken:
  - Abbruch, wenn der Keystore fehlt.
  - versionCode wird **berechnet** (z. B. `X*10000+Y*100+Z`).
- **Doku-Struktur:** `AGENTS.md`, `docs/IMPLEMENTIERUNG.md`, Recherche mit Belegmarken; Release-Konventionen; README-Vorlage des Beta-Repos.

### Nicht übernehmbar
Alles Godot-Spezifische:
- Szenen, HUD-Code, `name_tags.gd`, `NetRace`, `NetDraw`;
- die GDScript-Tests als Code;
- ENet-Feinheiten (Drossel, Kanäle);
- `godot_run.ps1`.

**Ehrliche Bilanz:** Von rund 5 900 Zeilen Netz-, Updater- und Java-Code bleiben etwa 350 Java-Zeilen direkt erhalten. Rund 1 000 Zeilen werden mit Tests portiert, der Rest überträgt sich als Wissen. Allerdings müsste auch eine Godot-Lösung ihren ENet-Netzcode für WebSocket und verdeckte Information umbauen (Bericht netz 3).

---

## 4. Aufwand und Meilensteine

PT = konzentrierte Entwicklungstage einschließlich Gerätetest durch den Nutzer, Claude programmiert. Ohne Grafikproduktion.

| M | Inhalt | PT | Ergebnis / Abnahme |
|---|---|---|---|
| **M0** | **Werkbank und Durchstich.** Node, Vite, TS, Pixi, Vitest, Playwright; Gradle-Projekt (Java, minSdk 26, targetSdk 35); Keystore anlegen und **außerhalb `.tools` sichern**; WebView-Hülle mit Bridge; Java-HTTP- und WS-Server; Pixi-Testtisch mit 20 Karten, Wende, Partikeln und Joker-Strahl-Prototyp. | 4–6 | **Go/No-Go:** S10-WebView ≥ 50 fps bei Effektstufe „Voll“; iPhone (Freund oder BrowserStack) lädt in < 3 s, WS 30 min stabil, nach Bildschirmsperre in < 2 s wieder verbunden; Host-Kern im Worker beantwortet Nachrichten, während die App 60 s im Hintergrund ist. |
| **M1** | **Regelkern:** Karten, Paarung je Runde, Züge, Flip, Bluff, Ansagen, Standards aus Regelbericht 1.13, `viewFor`, Ereignisse; Vitest plus Zufallstests. | 5–7 | Kontrollsummen 1280/1480; 10 000 Bot-Partien ohne Regelbruch; Lecktest: keine verdeckte Karten-ID in fremden Sichten. |
| **M2** | **Spielbar auf einem Handy:** Grundtisch, Hand A/B, Ausspielen per Doppeltipp, Farbrad, Grund-Flip, Sortieren, Tischregie, Weitergeben mit Übergabekarte. | 6–9 | **Spielbarer Kern** auf S10, S21 und S24. |
| **M3** | **Hülle, Updater und Release-Kette:** Updater nach Java portiert (JUnit), TS-Dialog, Beta-Schalter, „Im Browser herunterladen“, `build.ps1`, `release.ps1`, beide Repos. | 4–6 | Erste Beta. **Der Updater stimmt ab der ersten öffentlichen Version.** |
| **M4** | **Netzwerk:** Protokoll, Lobby, Tisch-Editor, Token und Wiederverbinden, Snapshot, QR, Landing-Seite, UDP-Suche (Java), App-Client lädt das Host-Paket, Bridge-Freigaben je Herkunft, NetHelper-Bindung, Vordergrunddienst; Playwright-Mehrspielertest. | 9–13 | 1 Host-App, 1 App-Client, 2 Browser (Chrome, iPhone) spielen eine Partie mit Sperre und Wiederkehr. |
| **M5** | **Offline-Verteilung:** APK über HTTP, Teilen-Menü, Update vom Host, LOHS mit WLAN-QR und Schrittleiste. | 5–8 | Flugmodus-Test: Hotspot ohne Internet, Neuinstallation und Update ohne Internet. |
| **M6** | **Hand-UX komplett:** Stufe C (Karussell), Fischauge, Schwung, Gummiband, Wischen nach oben, Joker in einer Geste, Übersichtsblatt, alle Sortiermodi, Gegnerhände. | 6–9 | Gerätetest mit 25+ Karten. |
| **M7** | **Effekte:** Katalog aus Bericht hand-ux 4.2, Flip-Drehbuch, Joker-Strahlen, Zieh 5, Farbjagd, Sieg, Stufen, automatisches Herunterstufen. | 10–15 | Messung auf dem S10; iPhone-Stichprobe. |
| **M8** | **Hausregeln:** Optionsbildschirm, Voreinstellungen, Bis zum Letzten, Stapeln, Bluff-Modi, Mau/Mau-Mau, später Reinwerfen. | 4–7 | Ein Regeltest je Option. |
| **M9** | **Gestaltung und Klang:** Kartenbaukasten (SVG → Atlas, MSDF), Paletten- und Symbolprüfung, Klänge (MP3 oder AAC statt Ogg, wegen Safari [ungeprüft]). | 6–10 | Zusätzlich Grafikproduktion. |
| | **Summe** | **≈ 59–90** | |

**Vergleich (grob, [Schätzung]):**
- Godot-zentriert mit HTML-Lite-Client für iPhones käme auf etwa 65–105 PT. Draw2Race spart dort etwa 5–8 PT. Dafür kosten der zweite Client 10–20 PT und ein GDScript-HTTP/WS-Server mit Threads 3–5 PT.
- Web-zentriert ist damit **etwa gleich teuer bis 15 PT günstiger**, mit deutlich besserer iPhone-Qualität.
- Die Unsicherheit ist größer als der Unterschied. Deshalb gibt es M0.

---

## 5. Risiken

| # | Risiko | Wahrscheinlichkeit / Wirkung | Gegenmaßnahme |
|---|---|---|---|
| 1 | **Der Host-Kern im WebView stockt, wenn die App im Hintergrund ist**, oder der Prozess wird getötet. | mittel / hoch | Android hält WebView-JavaScript bei `onPause` **nicht** an, nur `pauseTimers()` tut das [belegt]. Wir rufen es nie auf. Chromium kann Timer verborgener Seiten trotzdem drosseln; Ereignisse kommen aber an [Gerätetest]. Weiter: Vordergrunddienst (Android 14 verlangt einen Typ, z. B. `specialUse` mit Begründung; außerhalb von Play ohne Prüfung [belegt]), Snapshot nach jedem Zug. **Notfallplan:** den Kern in `androidx.javascriptengine` (JavaScriptSandbox, stabil 1.1.1 vom 23.09.2026 [belegt]) in den Dienst verlegen. Das geht, weil der Kern kein DOM kennt [ungeprüft]. |
| 2 | **iPhone ohne Testgerät** | hoch / hoch | Nur Web-APIs, die ohne Secure Context gehen. Neu verbinden als Grundprinzip. Mehrstufige Teststrategie (Abschnitt 6). iPhone-Freunde testen Betas, sie brauchen nur einen Browser. |
| 3 | **Safari-Eigenheiten** | hoch / mittel | Wischen vom linken Rand: kein `pushState`, damit es keine Zurück-Seite gibt, und keine Gesten in den äußersten 20 px. Zoom per Doppeltipp und Spreizen: `touch-action`, `gesturestart` abfangen. Höhe mit `dvh`/`visualViewport` statt `100vh`. WebGL-Kontextverlust nach Hintergrund: `webglcontextlost`/`restored` behandeln, sonst die Seite neu laden. Ton nach dem Tipp auf „Beitreten“ freischalten. Speicher unter 300 MB. HTTPS-Erstversuch: TLS sofort abweisen. |
| 4 | **Leistung der WebView auf schwachen Handys** (Speicherbereinigung, Füllrate) | mittel / mittel | Durchstich auf dem S10 mit Abbruchkriterium; Objekt-Pools statt Neuanlage; DPR ≤ 2; vorgeblurrte Sprites statt Vollbildfiltern; Effektstufen; automatisches Herunterstufen. Mindestversion der WebView prüfen und Hinweis zeigen. |
| 5 | **Sicherheit: fremder Code in der App-WebView**, weil der Client das Paket des Hosts lädt | gering / hoch | `addWebMessageListener` mit Prüfung von `sourceOrigin`. Fremde Herkunft bekommt nur Haptik, Wachhalten, Sensor und Log. Installieren gibt es nur über nativen Dialog mit `verify` (gleiche Signatur, höherer Code). Token im Pfad, nur bei offener Lobby. |
| 6 | **Zwei Sprachen und die Bridge** (Wartung) | mittel / mittel | Die Bridge ist schmal und versioniert (`bridge.version`, Feature-Flags, nur Ergänzungen). Java bleibt ein dünner Transport: keine Spiellogik, nur Strings und JSON, Entscheidungen als reine Funktionen wie in Draw2Race. Vertragstests auf beiden Seiten. |
| 7 | **Neue Werkzeugkette**; Node fehlt; Pfad mit Leerzeichen | mittel / gering | Node portabel über `setup.ps1`, Lockfile, feste Versionen (Pixi-Hauptversionen brechen APIs). Leerzeichen im Pfad im M0 mit npm und Gradle prüfen. |
| 8 | **Native Android-Funktionen** (LOHS, Bindung, Berechtigungen, FileProvider) | mittel / mittel | Hier ist die Web-Variante im Vorteil: eine normale Activity mit `requestPermissions`, Callbacks als Klassen, Threads. Kein JavaClassWrapper. Gerätetests bleiben nötig (nur Samsung-Geräte vorhanden). |
| 9 | **Updater-Fehler in v1** | gering / hoch | JUnit-Fälle aus Draw2Race; Knopf „Im Browser herunterladen“; Lesezeitgrenze. |
| 10 | **Android-Entwicklerverifizierung 2027**, Play Protect, Chrome-Warnung bei APK über HTTP | sicher / mittel | Unabhängig von der Technik. Früh registrieren; Installation im Flugmodus testen, sobald die Regel gilt. |
| 11 | **Synergie mit Draw2Race geht verloren** | sicher / gering | Die Java-Helfer könnten später in eine gemeinsame Bibliothek wandern. |

### Kritik an der eigenen Perspektive
- Die Web-Variante lohnt sich nur, weil der iPhone-Browser ein **Hauptziel** ist. Wäre er eine Notlösung, wäre Godot mit dem Draw2Race-Bestand die risikoärmere Wahl.
- Capacitor habe ich bewusst **abgelehnt**:
  - Seit Capacitor 6 ist der Ursprung `https://localhost`, was mit `ws://` kollidiert. Lösbar mit `androidScheme: 'http'` bzw. `allowMixedContent` [belegt], aber unnötig.
  - Alle benötigten nativen Teile sind ohnehin eigener Java-Code.
  - Capacitor nützt vor allem für iOS-Apps, und dafür fehlt der Mac.
  - Mit einem Mac später bliebe Capacitor als Hülle möglich.
- **Widerspruch zum Bericht browser-iphone (Option C „nicht empfohlen“):**
  - „Kein gepflegtes Server-Plugin“ stimmt, betrifft uns aber nicht. Java-WebSocket 1.6.0 [belegt] und ein HTTP-Server mit etwa 250 Zeilen sind weniger Arbeit als ein Server in GDScript, der von der Hauptschleife abhängt.
  - „Godot-Basis geht verloren“ stimmt nur teilweise (siehe 3).
  - „iPhones haben dieselben HTTP-Grenzen“ gilt für alle Optionen und spricht deshalb nicht gegen C.

---

## 6. Teststrategie ohne iPhone und Mac

1. **Regelkern (Vitest, in Node):**
   - Unit-Tests je Regel und Option.
   - Zufallstests mit Bots über 10 000 Partien. Invarianten: 112 Karten bleiben erhalten, Zugreihenfolge stimmt, Wertung stimmt.
   - **Lecktest:** Jede `viewFor`-Ausgabe wird gegen die Menge verdeckter IDs geprüft.
   - Wiederholung: gleiche Ereignisliste plus Seed ergibt einen bytegleichen Zustand.
2. **Layout und Gesten:** Reine Funktionen (`layout(n, scroll, focus)`, `seat_pos`, Konturabtastung) werden mit Vitest getestet. Gesten mit realistischen Touch-Geschwindigkeiten, als Lehre aus Draw2Race 0.2.31.
3. **Mehrspieler-Ende-zu-Ende (Playwright, Windows):**
   - `tools/devhost` (Node) startet den Host-Kern mit ws und statischem Server.
   - Dazu mehrere Browser-Kontexte: Chromium mit Android-Profil, **WebKit mit iPhone-Profil** (Viewport, Touch, DPR 3).
   - Störfälle: `setOffline`, Seite schließen und mit Token wieder öffnen, `visibilitychange`, doppelter Beitritt, falsche Protokollversion.
   - Bildschirmfotos bei 375×812 und 390×844 als Bildvergleich.
4. **Mobile Safari im iOS-Simulator auf GitHub Actions (macOS-Runner):**
   - Der Runner startet den Node-Host. Dann `xcrun simctl openurl booted http://localhost:24700/…`, dazu Bildschirmfotos (`simctl io screenshot`), optional Appium/XCUITest für Tipps.
   - Das ist echtes Mobile-Safari-WebKit ohne eigenen Mac.
   - Für öffentliche Repos sind die Minuten kostenlos, für private teuer. **Prüfen** [Ableitung].
   - Er ersetzt kein echtes Gerät (GPU, Speicher, Sperrbildschirm).
5. **Java (JUnit am PC):**
   - Updater-Prüflogik (Fälle aus `test_core.gd`).
   - Netzentscheidungen (Fixtures aus `test_lobby.gd`).
   - HTTP-Server: MIME, Range, gzip, TLS-Abweisung, Token.
   - WS-Server mit Java-WebSocket-Client.
6. **Android-Geräte (S10, S21, S24):**
   - fps-Overlay und Effektstufen; Host mit eigenem Hotspot und LOHS; Mitspieler mit mobilen Daten.
   - Android-Chrome **und** Samsung Internet als Browser-Client; das kommt dem iPhone-Fall am nächsten.
   - APK-Weitergabe und Update vom Host im Flugmodus.
7. **Echte iPhones:**
   - BrowserStack Live mit Local-Tunnel zum PC-Host (Open-Source-Programm, wenn der Quellcode öffentlich ist).
   - iPhones von Freunden mit Checkliste: QR, HTTPS-Rückfall, Sperre und Wiederkehr, NoSleep, Ton und Stummschalter, Randwischen, 30-min-Partie.
   - Fehlersuche: Eruda per `?debug`, Fern-Log über WS, notfalls inspect.dev per USB unter Windows.
8. **Schnelle Iteration:** Den Vite-Dev-Server im Heim-WLAN direkt auf dem Handy-Browser öffnen, mit Live-Reload und ohne APK-Bau.

---

## 7. Offene Entscheidungen für den Nutzer

1. **Web-zentriert nach dem Durchstich M0 festschreiben?** (Abbruchkriterien siehe M0)
2. **Hülle in Java** (Vorschlag: Draw2Race-Helfer direkt nutzbar, keine Kotlin-Werkzeuge) oder Kotlin?
3. **Paketname** (endgültig), z. B. `de.maumauflip.app`, und **minSdk 26 mit Versionsprüfungen** (Vorschlag) oder 28.
4. **Quellcode öffentlich?** Davon hängen BrowserStack Open Source und kostenlose macOS-Runner ab.
5. **Release-Signatur:** eigener Release-Keystore und Release-Build (nicht debuggable) ab v1. Logs dann über die App-eigene Funktion „Log teilen“ statt `run-as`.
6. **Ordner `Mau-Maul Flip`** neben `Mau-Mau Flip`: wohl ein Tippfehler, kann der Nutzer entfernen.

**Zusätzliche Quellen (über die Berichte hinaus):**
- [JavaScriptEngine Release-Notes](https://developer.android.com/jetpack/androidx/releases/javascriptengine) · [JavaScriptSandbox](https://developer.android.com/reference/androidx/javascriptengine/JavaScriptSandbox)
- [WebView onPause vs. pauseTimers](https://medium.com/einkbro/differences-between-onpause-and-pausetimers-for-android-webview-230759d0d092) · [WebView.OnPause](https://learn.microsoft.com/en-us/dotnet/api/android.webkit.webview.onpause?view=net-android-37.0)
- [Foreground-Service-Typen](https://developer.android.com/develop/background-work/services/fgs/service-types) · [Pflicht ab Android 14](https://developer.android.com/about/versions/14/changes/fgs-types-required)
- [Java-WebSocket](https://github.com/TooTallNate/Java-WebSocket) · [Javadoc 1.6.0](https://javadoc.io/doc/org.java-websocket/Java-WebSocket/latest/index.html)
- [Capacitor: Mixed Content und androidScheme](https://forum.ionicframework.com/t/android-emulator-https-issue/242726)
- [pixi-filters (v6 für Pixi v8)](https://github.com/pixijs/filters) · [Pixi v8.6 / PerspectiveMesh](https://pixijs.com/blog/better-docs-v8)

**Relevante Pfade:**
- `C:\Users\Shakie\Documents\Programmierung\Draw2Race\game\android\build\src\main\java\com\godot\game\Updater.java`
- `C:\Users\Shakie\Documents\Programmierung\Draw2Race\game\android\build\src\main\java\com\godot\game\NetHelper.java`
- `C:\Users\Shakie\Documents\Programmierung\Draw2Race\game\scripts\updater.gd`
- `C:\Users\Shakie\Documents\Programmierung\Draw2Race\game\scripts\net\net_android.gd`
- `C:\Users\Shakie\Documents\Programmierung\Draw2Race\game\scripts\net\net_discovery.gd`
- `C:\Users\Shakie\Documents\Programmierung\Draw2Race\game\scripts\net\net_protocol.gd`
- `C:\Users\Shakie\Documents\Programmierung\Draw2Race\game\tests\test_core.gd`
- `C:\Users\Shakie\Documents\Programmierung\Draw2Race\game\tests\test_lobby.gd`
- `C:\Users\Shakie\Documents\Programmierung\Draw2Race\tools\build.ps1`
- `C:\Users\Shakie\Documents\Programmierung\Draw2Race\tools\setup.ps1`
- `E:\Documents\Programmierung\Mau-Mau Flip`