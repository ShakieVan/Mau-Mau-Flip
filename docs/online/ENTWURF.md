# Online-Spiel, Schritt 1 – Entwurf

Stand 08.10.2026. Grundlage: AGENTS.md „Geplant: Online-Spiel, Schritt 1“, Netzprotokoll `docs/BETA1_PLAN.md` Abschnitt 5.
Ziel: Spielen über das Internet mit einem Vermittler (Cloudflare Worker + Durable Object). Die Spiellogik bleibt beim
Gastgeber-Handy (`NetHostSession`, `HostTable`); der Vermittler reicht nur Textrahmen durch und kennt keine Spielinhalte.

## 0. Geprüfte Cloudflare-Bedingungen (08.10.2026)

| Punkt | Stand | Quelle |
|---|---|---|
| Durable Objects im Gratistarif | nur SQLite-Speicher; seit 09.07.2026 müssen neue Namespaces SQLite nutzen | DO Pricing (aktualisiert 30.09.2026), DO Changelog |
| Klassen anlegen | neu (04.07.2026): deklaratives Feld `exports` (`{"Room": {"type":"durable-object","storage":"sqlite"}}`), ersetzt `migrations`/`new_sqlite_classes`. `migrations` bleibt für bestehende Worker voll unterstützt; beide Formen nicht gemischt | DO „Durable Object migrations“, „class migrations (legacy)“, Changelog |
| Gratis-Tageslimits DO | 100 000 Anfragen, 13 000 GB-s Dauer, 5 Mio. Zeilen gelesen, 100 000 Zeilen geschrieben, 5 GB Speicher | DO Pricing |
| Gratis-Tageslimits Worker | 100 000 Anfragen/Tag (Rücksetzung 0 Uhr UTC), danach Fehler 1027 bzw. 429; 10 ms CPU je HTTP-Anfrage; 50 Unteranfragen | Workers Limits |
| WebSocket-Zählung | eingehende Nachrichten im Verhältnis 20:1 als Anfrage; ausgehende Nachrichten und eingehende Protokoll-Pings kostenlos | DO Pricing |
| Hibernation | `ctx.acceptWebSocket(ws, tags)` (max. 10 Tags à 256 Zeichen, max. 32 768 Sockets je Objekt), `webSocketMessage/Close/Error`, `serializeAttachment` (max. 16 384 Byte), `getWebSockets(tag)`, `setWebSocketAutoResponse(pair)` antwortet **ohne das Objekt zu wecken** (je max. 2 048 Zeichen), `getWebSocketAutoResponseTimestamp(ws)`. Leerlaufende, hibernationsfähige Objekte kosten keine Dauer | DO WebSockets, DurableObjectState API |
| Grenzen | WebSocket-Nachricht empfangen bis 32 MiB; 30 s CPU je Anfrage (DO); ~1 000 Anfragen/s je Objekt (weich) | DO Limits |
| Statische Assets | Anfragen an Assets **kostenlos und unbegrenzt**, rufen den Worker nicht auf; nur Pfade in `run_worker_first` zählen (bei Überschreitung 429 statt Rückfall). 20 000 Dateien, 25 MiB je Datei | Static Assets, Billing and limitations |
| Deploy-Knopf | `https://deploy.workers.cloudflare.com/?url=<Repo-URL>`, Bild `https://deploy.workers.cloudflare.com/button`; Unterordner erlaubt (`…/tree/main/relay`), dann muss die Anwendung **vollständig in diesem Ordner** liegen. Klont den Ordner in das GitHub-Konto des Nutzers; liest die Wrangler-Datei und legt Bindungen an, **Durable Objects eingeschlossen**. Build-Befehl bleibt leer, wenn `package.json` keinen `build`-Script hat; Bereitstellung per `deploy`-Script, sonst `npx wrangler deploy`. Nur öffentliche Repos; Monorepos nicht voll unterstützt | Workers „Deploy buttons“ |

Quellen: developers.cloudflare.com/durable-objects/platform/pricing/, …/platform/limits/, …/best-practices/websockets/,
…/api/state/, …/reference/durable-objects-migrations/, …/reference/durable-object-class-migrations-legacy/,
developers.cloudflare.com/changelog/product/durable-objects/, developers.cloudflare.com/workers/platform/limits/,
…/workers/static-assets/, …/workers/static-assets/billing-and-limitations/, …/workers/platform/deploy-buttons/ (alle abgerufen 08.10.2026).

**Konservative Entscheidungen**
- Klasse über `exports` (aktueller Weg für neue Worker). `relay/package.json` mit `"scripts": {"deploy": "wrangler deploy"}` und
  `devDependencies.wrangler: "^4.126.0"` (Version vom 25.08.2026, nach Einführung von `exports`), **kein** `build`-Script und kein
  Bundler. Beim ersten echten Deploy durch den Nutzer prüfen; scheitert `exports`, Rückfall auf `migrations: [{tag:"v1", new_sqlite_classes:["Room"]}]`.
- Unklar, ob DO-Anfragen und Worker-Anfragen dasselbe 100 000-Kontingent teilen → so rechnen, als zählten beide (Upgrade = 2 Anfragen).
- Ob Auto-Antworten als eingehende Nachrichten zählen, ist nicht dokumentiert → als 1/20 Anfrage rechnen. Abstand seit Beta 1.3.3 10 s (vorher 25 s), siehe Überschlag.
- Keine Speicherung je Nachricht (Zeilen-Schreiblimit); Verbindungsdaten in Tags/Attachments.
- `observability` aus, kein `console.log` mit Inhalten oder Raumcodes.

**Überschlag** (6 Spieler, 3 h): Verbindungen ~6×(1+5 Wiederverbindungen)×2 = 72; Spielnachrichten eingehend ~6 000 → 300;
Herzschläge (Beta 1.3.3: alle 10 s statt 25 s) 6×1 080 = 6 480 → 324; Prüf-„ping“ nach eigenem Senden ohne Antwort binnen 6 s
(Gastgeber höchstens einer je 6 s während der Partie, ~1 800 → 90; Gäste selten) – zusammen < 900 Anfragen pro Abend (vorher < 600),
Dauer ~0 (Hibernation). Selbst zehn solche Abende am selben Tag bleiben unter 10 % des Gratis-Kontingents (100 000/Tag).

**Dazu der Browser-Client über `/c/*`** (seit 08.10.2026 über den Worker, nicht mehr als kostenlose Assets): Je erstem Aufruf eines
Browser-Gastes `index.html`, `style.css`, 9 Skripte, 2 Bilder, die benutzten Schriften (~3), Töne (~9, je ein Format) und die nach und
nach gezeigten Karten (bis 137) – grob 30 beim Start, höchstens ~170 bis Spielende. Danach kommt alles aus dem Browser-Speicher
(`immutable`, 1 Jahr); nur `index.html?r=CODE` wird je neuem Raum einmal geholt. Ein Abend mit 3 Browser-Gästen: ~600 + 3×170 ≈ 1 100;
ungünstigster Fall 6 Browser-Gäste ≈ 1 600 → reicht für > 60 Abende am Tag (100 000 Anfragen). GitHub-Abrufe (Unteranfragen) fallen je
Datei höchstens einmal je Cloudflare-Rechenzentrum an, wenn der Zwischenspeicher greift (siehe Abschnitt 4), sonst einmal je
Worker-Anfrage (1–2 Unteranfragen, Grenze 50).

## 1. Vermittler-Protokoll

### Adressen (Worker)

`run_worker_first: ["/ws", "/info", "/c/*"]`; Startseite `/`, `loader.js` und `404.html` sind statische Assets (`relay/public/`, kostenlos).

| Pfad | Bedeutung |
|---|---|
| `GET /info` | `{game:"mau-mau-flip", relay:2, proto:1, source:{repo, url, dir:"webclient", tag:"v<version>"}}` (ohne Objekt-Aufruf; keine Versionsliste mehr) |
| `GET /info?room=CODE` | zusätzlich `room:{open, host, version}` vom Raum-Objekt; `open:false` bei unbekanntem Code |
| `GET /ws?role=host&proto=1&v=<Spielversion>` | Gastgeber öffnet **neuen** Raum; der Worker würfelt den Code (Abschnitt 2) und fragt das Objekt `idFromName(code)`; belegt → neuer Versuch (max. 8), sonst 503 |
| `GET /ws?role=host&room=CODE&token=T` | Gastgeber kehrt zurück (gleiches Token) oder übernimmt (später: Übergabe) |
| `GET /ws?role=guest&room=CODE` | Gast (App oder Browser) |
| `GET /c/<version>/<datei>` | Lite-Client vom Quell-Repo am Tag `v<version>` (Abschnitt 4); `/c/<version>` → 301 auf `/c/<version>/` |
| alles andere | statisch: `/` Lader, `/404.html` |

Code-Normalisierung (`normalizeCode`): Großbuchstaben, Leer-/Unterstrich/fehlender Strich → `WORT-ZZ`; ä/ö/ü/ß werden zu AE/OE/UE/SS
(die Liste enthält keine Umlaute). Ungültig → 400 vor dem Objekt-Aufruf.

### Rahmen

Gäste sehen **nur das unveränderte Spielprotokoll** (Textrahmen wie im WLAN). `NetClient` und Lite ändern nur URL und Herzschlag.

Zwischen Vermittler und Gastgeber gibt es einen Umschlag (JSON, Feld `k`). Verbindungs-ID `c` ist eine Zahl ≥ 1 je Raum.

Vermittler → Gastgeber:

| Rahmen | Bedeutung |
|---|---|
| `{k:"room", room, token, link, limits:{guests, msg, rate, grace_s, life_s}}` | Raum offen (neu oder nach Rückkehr); `token` nur beim Anlegen |
| `{k:"open", c, info:{agent}}` | Gast verbunden (wie `ws_opened`; `agent` gekürzt auf 120 Zeichen, keine IP) |
| `{k:"msg", c, d}` | Nachricht des Gasts, `d` = Rohtext (vom Vermittler nur als JSON-String eingepackt, nie geparst) |
| `{k:"close", c, code}` | Gast getrennt |
| `{k:"drop", c, why:"size"\|"rate", size}` | Nachricht verworfen (wie `ws_dropped`) |
| `{k:"err", code}` | Fehler am Umschlag (`bad`, `unknown_c`) |

Gastgeber → Vermittler:

| Rahmen | Bedeutung |
|---|---|
| `{k:"send", c:[…], d}` | Rohtext `d` an eine oder mehrere Verbindungen (deckt `send_text` und `send_text_many`) |
| `{k:"kick", c, code, reason}` | Gast schließen (z. B. 4000 ersetzt, 1000 entfernt) |
| `{k:"end"}` | Raum schließen: Gäste bekommen 1001, Speicher wird gelöscht |

Herzschlag: `setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"))` – die Gegenstelle schickt im Online-Modus
alle **10 s** den Text `ping` (kein JSON) und gilt nach **25 s** Stille als getrennt (Beta 1.3.3; vorher 25/70 s). Das Spiel-`{t:"ping"}` entfällt über den
Vermittler (RTT-Anzeige leer). Kein Polling, keine Wecker außer den Raum-Alarmen.

**Stille Aussetzer (Beta 1.3.3, Nutzerbefund 1.3.2):** Eine Mobilfunk-/VPN-Verbindung kann ohne Close verschwinden; der Gastgeber
spielte lokal weiter, der Gast sah über eine Minute lang den alten Stand. Seitdem:
- Herzschlag 10 s, 25 s Stille = getrennt (Gastgeber `NetRelayHost`, App-Gast `NetClient`, Lite `netz.js`). Zusätzlich prüft jede
  Seite nach eigenem Senden: Kommt binnen **6 s** gar nichts zurück, sofort `ping`; bleibt auch darauf **4 s** alles still, neu
  verbinden (Lite: bestehende Prüfung „Keine Antwort vom Gastgeber“ nach 6 s mit Weckruf, 3 s).
- Ist nur die Vermittler-Verbindung des Gastgebers weg (`away`), gelten seine Online-Gäste in der Sitzung **nicht** als gegangen
  (kein `ws_closed` → keine Vertretung „Computer spielt für …“, keine Rückfrage). Nach der Rückkehr mit Raum-Token schickt der
  Gastgeber ihren alten Verbindungen `{k:"kick", code: 4012}`: Der Vermittler behält beim Ersetzen eines still toten Gastgeber-Sockets
  die Gäste (`REPLACED` an den alten, kein 4503 an die Gäste), der neue Gastgeber-Socket kennt sie aber nicht. 4012 lässt App und
  Lite sofort mit Token neu anmelden (danach voller Stand). Wer binnen 20 s nicht wiederkommt, gilt dann als getrennt. Ohne
  Änderung am Vermittler (Kick-Codes 3000–4999 sind erlaubt).
- Hinweise: Gastgeber am Tisch „Online-Verbindung unterbrochen – verbinde neu …“ (Lobby gleicher Text), Gäste „Verbindung zum
  Gastgeber unterbrochen – warte …“ bzw. bei 4503 „Gastgeber kurz weg – warte …“ (App und Lite).
- Test: `game/tests/test_net_hang.gd` (Nachbau mit hängendem Socket `hang_host`/`hang_guest`, genau die Abfolge des Befunds).

**App-Wechsel (Beta 1.3.3, Nutzerbefund: kurz in Threema für Screenshots, danach bis zu 70 s alter Stand; „Computer spielt für Püppi“
wirkte wie ein Zustand):** Beim Weggehen schickt das Gerät sofort `{t:"away"}` (Spielprotokoll, für den Vermittler nur Daten), beim
Zurückkommen `{t:"back"}` plus `ping` mit 3 s Frist, sonst sofort neu verbinden (Gast: `NetClient.check_now`, Gastgeber:
`NetRelayHost.check_now`, Lite: `zurueck()`). Alle sehen „kurz in einer anderen App“ am Platz; ist der Gastgeber weg, zeigen die
Gäste „<Name> (Gastgeber) ist kurz in einer anderen App – warte …“. Der Knopf „Computer für %s spielen lassen“ kommt erst nach 30 s.
Einzelheiten: `docs/BETA1_PLAN.md` Abschnitt 5 „App-Wechsel“; Test `game/tests/test_net_away.gd`.

### Raum-Objekt `Room` (Zustand)

- Speicher (wenige Zeilen je Raum): `meta = {code, tokenHash (SHA-256), proto, version, created, hostGoneAt}`; geschrieben beim
  Anlegen, beim Gehen und Wiederkommen des Gastgebers, gelöscht mit `deleteAll()` beim Schließen.
- Je Socket Tags `["host"]` bzw. `["guest", "c:<n>"]`, Attachment `{role, c, since}`; nächste `c` = max(Attachments)+1 (nach
  Hibernation neu ermittelt).
- Ratenzähler nur im Speicher (gehen beim Schlafen verloren – unkritisch).

### Abläufe und Schließcodes

- **Gast ohne Raum** → annehmen und sofort schließen **4404** („Raum nicht gefunden“). **Gastgeber gerade weg** → **4503**; Clients
  warten dann 10 s statt 1–5 s. **Raum voll** → **4409**. **Raum beendet** → **1001**. Zweiter Gastgeber mit gültigem Token ersetzt
  den ersten (**4000** an den alten).
- **Gastgeber trennt:** alle Gäste schließen mit 4503, `hostGoneAt` setzen, Alarm auf +**10 min**. Kommt er mit Token zurück: Alarm
  zurück auf Lebensende, `{k:"room"}` ohne Token; die Gäste melden sich mit ihren Spieler-Tokens neu an (vorhandene Logik in
  `NetHostSession`). Alarm fällig → Raum löschen, Code wieder frei.
- **Lebensdauer** 24 h ab Anlegen (Alarm), danach 1001 an alle.

### Grenzen gegen Missbrauch

| Grenze | Wert |
|---|---|
| Gäste-Verbindungen je Raum | 16 (10 Spieler + Überlappung beim Wiederverbinden) |
| Nachricht Gast → Gastgeber | 8 KB (wie WLAN; sonst `drop size`) |
| Nachricht Gastgeber → Vermittler | 256 KB (Rahmen mit Sicht), größer → Gastgeber-Socket 1009 |
| Rate Gast | 20/s, Spitze 40 (Token-Eimer), sonst `drop rate`; Dauerverstoß 10 s → 4429 |
| Rate Gastgeber | 200/s |
| Lebensdauer / Abwesenheit | 24 h / 10 min |
| Anmeldung | Gäste ohne Spiel-`hello` schließt der Gastgeber nach 10 s (bestehend) |
| Inhalte | werden nie geloggt oder gespeichert |

## 2. Raumcodes

- Form `WORT-ZZ`: Wort aus eigener Liste (`relay/src/words.js`, ~200 kurze deutsche Wörter, 3–6 Buchstaben, ohne Umlaute, gut
  sprechbar und eindeutig im Diktat: Tiere, Natur, Tag/Nacht, Essen – z. B. KATZE, MOND, SONNE, PFOTE, WOLKE, BIRNE), Zahl 10–99
  → ~18 000 Codes. **Keine** Marken- oder Spielbegriffe des Vorbilds, keine Farben-/Kartennamen, nichts Anstößiges; Prüfliste in
  den Tests (verbotene Teilwörter).
- Kollisionsprüfung im Objekt: `meta` vorhanden → „belegt“, der Worker würfelt neu.
- Raten von Codes führt nur in die Lobby; der Gastgeber sieht jeden Gast, kann ihn entfernen, laufende Partien lehnen Neue ohne
  Token ab („running“). Schutz durch Geheimnis im Link (`#k=…`) folgt mit der Verschlüsselung.
- Link: `https://<vermittler>/?r=KATZE-42`; QR enthält genau diesen Link, darunter Code und Adresse als Text.

## 3. App (game/**)

**Transport-Abstraktion.** `NetHostSession` spricht heute nur `NetServer` an (Signale `ws_opened/ws_message/ws_closed/ws_dropped/log_line`,
Aufrufe `send_text`, `send_text_many`, `close_ws`, `stats`). Neu `NetRelayHost` (`game/scripts/net/net_relay_host.gd`) mit **genau
dieser Schnittstelle**; Verbindungsnummern des Vermittlers werden auf `RELAY_CONN_BASE + c` (1 000 000 + c) abgebildet. Die Sitzung
hält `server` (WLAN) und optional `relay`; `_link(conn)` wählt den Transport nach Nummernbereich, `send_text_many` teilt auf.
Damit laufen **WLAN- und Online-Gäste gleichzeitig** in derselben Lobby und Partie; `HostTable` bleibt unverändert.

- `NetHostSession.open_online(relay_url) / close_online()`, Signal `online_changed(state, info)`; `state`: `off | connecting | open |
  away` (Gastgeber kurz getrennt, verbindet mit Token neu: 1, 2, 4 … 30 s) `| failed`; `info`: `room, link, error`.
- `apk_url()` liefert für Online-Gäste den GitHub-Release-Link statt `/apk`; `check_hello` bleibt (exakte Version).
- `finish/stop` schicken zusätzlich `{k:"end"}`.
- `NetClient.connect_relay(relay_url, code, name, kind)`: `wss://<v>/ws?role=guest&room=CODE`; Token-Schlüssel `relay:<v>/<CODE>`;
  Online-Herzschlag (10 s `ping`, 25 s Stille, Prüfung 6 + 4 s nach eigenem Senden); Code 4503 → 10 s warten; 4012 → sofort neu; 4404/4409/1001 endgültig mit Text.
- TLS: `WebSocketPeer` mit `TLSOptions.client()` (eingebaute Zertifikate). `http://`-Vermittler (nur lokaler Nachbau) → `ws://`.

**Bedienung** (kein neuer Hauptmenü-Knopf):
- Gastgeber-Lobby: neben ① WLAN / ② Spiel ein dritter Weg **„Online (Internet)“**. Ohne Vermittler-Adresse: Hinweis und Knopf zu
  den Einstellungen. Sonst „Online öffnen“ → Raumcode groß, Link, QR, „Teilen“ (Android-Teilen-Menü), Zustand mit Leuchte wie ①/②.
  Online-Gäste erscheinen in der Gästeliste mit Weltkugel-Zeichen.
- Beitreten-Bildschirm: Feld **„Raumcode“** mit Knopf „Beitreten“ (verwendet die Vermittler-Adresse aus den Einstellungen bzw. aus
  dem Link).
- App-Link `maumauflip://join?r=KATZE-42&v=<vermittler-host>` (zusätzlich zu `h`/`p`); `AppLink.java`, `NetAndroid.parse_app_link`.
- Einstellungen, Abschnitt **„Online“**: Vermittler-Adresse (Feld), „Verbindung testen“ (`GET /info`, zeigt Ergebnis und Zeit),
  QR zum Weitergeben der Adresse (`https://<v>/` – öffnet die Startseite des Vermittlers, die die Adresse zeigt). Standard
  `NetProtocol.RELAY_DEFAULT := ""` (setzt der Nutzer nach seiner Bereitstellung). Gäste übernehmen `v` aus Link/QR für diesen
  Beitritt und speichern es, falls die eigene Einstellung leer ist.
- Alle Texte über `I18n.t`, Einträge in `game/i18n/en_*.po` (Glossar: „Vermittler“ = *relay*, „Raumcode“ = *room code*).

## 4. Browser (webclient/**)

- **Der Vermittler holt den Lite-Client selbst** (Nutzerentscheidung 08.10.2026; ersetzt die gebündelten Kopien
  `relay/public/c/<version>/` samt `versions.json` und „Sync fork“): `/c/<version>/<datei>` ←
  `https://raw.githubusercontent.com/<CLIENT_REPO>/v<version>/webclient/<datei>` (`relay/src/client.js`). `CLIENT_REPO` steht als
  Variable in `wrangler.jsonc` (Standard `ShakieVan/Mau-Mau-Flip`, Forks stellen um; ungültige Werte → Standard). Grund: Der Gastgeber
  verlangt dieselbe Spielversion (`check_hello`); so bedient jeder Vermittler jede veröffentlichte App-Version, ohne nach Updates neu
  bereitgestellt zu werden. Den Tag `v<version>` auf dem gepushten Stand legt `tools/release.ps1` vor jedem Release an (beide Kanäle);
  `webclient/i18n_po.js` ist eingecheckt.
  - Strenge Prüfung: Version `^\d+\.\d+\.\d+$`, Datei nur `[A-Za-z0-9_./-]`, kein `..`, keine leeren oder mit Punkt beginnenden Teile,
    höchstens 200 Zeichen, nur bekannte Endungen (html, js, css, json, txt, svg, png, webp, jpg, gif, ico, woff2, woff, ttf, otf, mp4,
    m4a, ogg, mp3, wav, wasm, pck). `/c/<version>/` = `index.html`. Nur GET/HEAD.
  - Eigene Köpfe statt GitHubs (`text/plain`, CSP-Sandbox): richtiger Content-Type, `nosniff`, `public, max-age=31536000, immutable`;
    `Range` wird durchgereicht (Video `wach.mp4`, Antwort 206 ohne Cache-API).
  - Zwischenspeicher doppelt: `fetch(…, {cf: {cacheEverything, cacheTtlByStatus: 2xx 1 Jahr, 404 5 min, 5xx 0}})` und Cache-API
    (`caches.default`, Schlüssel ohne Suchteil). Ob beides auf `*.workers.dev` wirkt, ist nicht eindeutig dokumentiert (die Cache-API
    nennt nur eigene Domains) – unschädlich, dann bleibt der Browser-Speicher; beim ersten echten Betrieb prüfen.
  - GitHub drosselt nicht angemeldete Abrufe von raw.githubusercontent.com; bei 429/5xx/Netzfehler Rückfall auf jsDelivr
    (`cdn.jsdelivr.net/gh/<repo>@v<version>/webclient/<datei>`, gleicher Tag). 404 von GitHub → zweisprachige Seite („Für Spielversion X
    gibt es im Quell-Repo keinen Browser-Client (Tag fehlt)“; bei anderen Dateien „Datei fehlt“), 5 min merkbar, weil der Tag später
    kommen kann; nicht erreichbar → 502 `no-store`.
- `relay/public/index.html` ist ein kleiner Lader (Teil des Vermittlers): liest `?r=`, fragt `/info?room=CODE`, leitet auf
  `/c/<version des Gastgebers>/?r=CODE` um (keine Versionsliste mehr; ungültige Versionsform → Hinweis „mit der App beitreten“).
  Ohne `?r=`: Raumcode-Eingabe und Erklärung.
- Lite erkennt `?r=CODE`: verbindet mit `wss://<gleicher Host>/ws?role=guest&room=CODE` (`ws://` bei http, für den lokalen Nachbau),
  Online-Herzschlag `ping`/`pong`, 4503 = „Gastgeber kurz weg – warte …“, 4404/4409/1001 mit Text. `/info` wird im Online-Modus nicht
  als Gastgeber-Info gedeutet. Token-Schlüssel je Raumcode.
- „App installieren (APK)“ → GitHub-Release-Seite statt `/apk`. „In der App spielen“ →
  `intent://join?r=CODE&v=<host>#Intent;scheme=maumauflip;package=de.maumauflip.game;S.browser_fallback_url=…;end`.
- Neue Texte über `M.t` mit Eintrag in `i18n_en.js`; `test_web_contract` prüft weiter alle `t(...)`.

## 5. Später (jetzt nur Vorkehrungen)

- **Godot-Web-Client:** derselbe Weg unter `/c/<version>/godot/` (vom Tag geholt wie Lite; `wasm`/`pck` sind als Typen schon erlaubt).
  Vorher `client.js` auf Durchreichen als Strom umstellen (heute `arrayBuffer`, bei ~40 MiB `wasm` zu viel Speicher) und die Dateien
  ins Repo bzw. an den Tag legen; alternativ als statische Assets. Der Lader erhält
  dafür schon jetzt eine Auswahl-Stelle; das Protokoll braucht nichts Neues.
- **Gastgeber-Übergabe:** Das Raum-Token ist an keine Geräte-ID gebunden; `role=host&token=` ersetzt den bisherigen Gastgeber (4000).
  Übergabe = Token plus Spielstand an das neue Gerät, der Raumcode bleibt. Spieler-Tokens müssen dann mitwandern.
- **Ende-zu-Ende-Verschlüsselung:** Schlüssel im Link-Fragment (`#k=…`, erreicht den Vermittler nie); `d` wird dann Chiffretext. Weil
  der Vermittler `d` nie parst, ändert sich am Vermittler nichts.
- Eigenes Vermittler-Programm (Docker/Tunnel) kann `core.js` direkt wiederverwenden.

## 6. Teststrategie (ohne Node, ohne Bereitstellung)

- **Kern als reines ES-Modul** `relay/src/core.js`: Klasse `RelayRoom` mit eingespritzter Umgebung (`now`, `accept`, `sockets(tag)`,
  `send`, `close`, `attach/getAttach`, `storage.get/put/deleteAll`, `setAlarm`, `random`) plus `normalizeCode`, `newCode`, Grenzen.
  `relay/src/worker.js` ist nur Klebstoff (Routing, Upgrade, Weiterleitung an `RelayRoom` bzw. `serveClient`). `relay/src/client.js`
  (Abruf des Lite-Clients) ist ebenfalls ein reines ES-Modul: `fetch`, Cache und `waitUntil` werden eingespritzt; der Test simuliert
  GitHub (Tag vorhanden/fehlt, 429 → jsDelivr, Netzfehler, Range) und prüft Pfadprüfung, Content-Types, Köpfe und Zwischenspeicher.
- **Chrome headless:** `relay/test/core_test.html` + `core.test.js` laden die Module über `tools/webtest/serve.ps1 -Wurzel relay`
  (Module brauchen http statt file://) und laufen über `tools/webtest/cdp.ps1 -EndExpr`. Einhängen in `tools/build.ps1 -Target Test`.
- **Gemeinsame Testvektoren** `relay/test/vectors.json`: Folgen von (Akteur, Rahmen, Zeit) → erwartete Ausgaben/Schließcodes.
  Laufen gegen `core.js` (Chrome) **und** gegen den GDScript-Nachbau – so bleiben beide Protokolle gleich.
- **GDScript-Nachbau** `game/scripts/net/net_relay_double.gd` (`class_name NetRelayDouble`) auf Basis von `NetServer` (liefert
  `web.zip` wie die Assets, `/ws` und `/info` wie der Worker; Zeiten für Tests einstellbar). Tests `game/tests/test_relay_double.gd`
  (Vektoren) und `test_net_online.gd` (Gastgeber + WLAN-Gast + Online-App-Gast + Lite-Gast über Chrome im selben Durchlauf).
- **Lokaler Gerätetest** (später, nach Absprache): `game/tests/relay_double_main.gd` per `tools/godot_run.ps1` startet den Nachbau auf
  dem PC (Port 24700), Handys per `adb reverse tcp:24700 tcp:24700`, Vermittler-Adresse `http://localhost:24700`.
- Nach der Bereitstellung durch den Nutzer: „Verbindung testen“ in der App und ein Raum mit zwei Geräten.

## 7. Aufteilung der Dateien (überschneidungsfrei)

**Vermittler:** `relay/**` (`wrangler.jsonc`, `package.json`, `src/worker.js`, `src/core.js`, `src/words.js`, `public/index.html`,
`public/404.html`, `public/loader.js`, `src/client.js`, `test/**`, `README.md`; keine Versionskopien mehr), `tools/build.ps1` (`-Target Relay` prüft nur und Einhängen des
Kerntests in `-Target Test`), `tools/webtest/serve.ps1` (Parameter `-Wurzel`), Abschnitt „Online-Spiel / Eigener Vermittler“ mit
Deploy-Knopf in `README.md`, `tools/release.ps1` (Tag `v<version>` im Quell-Repo vor jedem Release).

**App:** `game/**` – `scripts/net/net_relay_host.gd`, `net_relay_double.gd`, `net_session.gd`, `net_client.gd`, `net_protocol.gd`;
`scripts/app/settings.gd`, `net_android.gd`; `scripts/ui/screens/host_lobby.gd`, `invite_panel.gd`, `invite_steps.gd`,
`join_screen.gd`, `settings_screen.gd`; `android/build/src/main/java/com/godot/game/AppLink.java`; `i18n/en_*.po`, `i18n/GLOSSAR.md`;
Tests `game/tests/test_relay_double.gd`, `test_net_online.gd`, `relay_double_main.gd` (liest `relay/test/vectors.json` nur).

**Browser:** `webclient/**` (`app.js`, `netz.js`, `index.html`, `i18n_en.js`, ggf. `style.css`) und `game/tests/test_web_contract.gd`
(einzige Ausnahme unter `game/`).
