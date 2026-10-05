# Beta 0.1.1 – Bauplan und Schnittstellen

Stand 04.10.2026, Nachtschicht. Der Nutzer hat Entwurf, Bau und Veröffentlichung der ersten Beta beauftragt. Diese Datei ist der **verbindliche Vertrag** zwischen den Modulen. Wer davon abweichen muss, schreibt es in den Abschnitt „Abweichungen“ am Ende und begründet es.

Hintergrund: `AGENTS.md` (Nutzerentscheidungen), `docs/recherche/` (Recherche), `art/entwurf/a-papier-neon/` (gewählte Gestaltung).

## 1. Umfang der Beta

**Muss**
- **Regelwerk** vollständig nach den offiziellen Regeln (Fassung 2024 als Standard), deterministisch, mit Regeloptionen und Voreinstellungen (Abschnitt 4).
- **Drei Spielarten** mit derselben Tischoberfläche:
  - **Übungsspiel:** 1 Mensch gegen 1–5 Computergegner.
  - **Weitergeben:** 2–10 Menschen an einem Gerät, optional plus Computergegner. Vor jedem Zug ein Sichtschutz ohne Karten.
  - **Netzwerk:** Gastgeber-Handy plus App-Mitspieler (Suche im WLAN oder Adresse) plus Browser-Gäste (QR-Code). Computergegner kann der Gastgeber hinzufügen.
- **Tisch** im Querformat nach `art/entwurf/a-papier-neon/hand.png`:
  - Gegner im Halbkreis, aus Sicht des eigenen Platzes gedreht.
  - Nachziehstapel zeigt die Gegenseite der obersten Karte. Ablage spiegelbildlich dazu, mit Farbring.
  - Aktuelle Farbe zwischen den Stapeln, Richtungsring, Zuganzeige.
  - Knöpfe: Mau!, Sortieren, Rückseiten.
- **Hand:** Fächer (≤ 7), Lupe beim Gleiten (8–15), Bogen-Karussell mit Schwung, Einrasten und Gummiband (≥ 16).
  - Ausspielen per Wischen nach oben oder Doppeltipp.
  - Wünscher: Beim Ziehen erscheinen vier Farbfelder um die Ablage. Rückfall: Farbrad.
  - Halten und nach unten auf „?“ ziehen öffnet die Kartenhilfe.
  - Sortieren: Farbe, Wert, Punkte, manuell.
  - Eigene Rückseiten kurz ansehen.
- **Tischregie:** Ereignisse werden nacheinander animiert:
  - Ausspielen, Ziehen, +1/+5/+2, Aussetzen, Alle aussetzen, Richtungswechsel, Wunschfarbe, Farbjagd, Mau, Erwischt, Strafe, Rundenende, Sieg.
  - **Flip** als Tag→Nacht-Übergang: Welle über alle Karten, Hintergrund wechselt.
- **Netz:** Ein Port für alles (HTTP-Seiten, APK-Download, WebSocket), UDP-Suche, Wiederverbinden per Token, Sitzordnung durch den Gastgeber.
- **Browser-Client „Lite“:** reines HTML/CSS/JS ohne Build-Schritt, vom Gastgeber ausgeliefert, spielt vollständig mit.
- **App:**
  - Updater (Release- und Beta-Kanal), „App teilen“ (Teilen-Menü) und APK-Download von der Gastgeber-Seite.
  - Einstellungen: Name, Mau-Ton aus/leise/normal, Vibration, Effekte voll/reduziert, Beta-Kanal.
  - Regelübersicht und Kartenhilfe.
- **Töne:** Mau-Ton (aus `audio/entwurf/mau/`) sowie Karte legen, ziehen, mischen, Flip und Sieg, selbst synthetisiert.
- **Bau und Veröffentlichung:** signierte Release-APK (eigener Schlüssel), Windows-Build zum Testen, GitHub-Release im Beta-Repo.

**Später (nicht in 0.1.1):** Godot-Web-Client (experimentell), Spiel-WLAN per LocalOnlyHotspot mit WLAN-QR, „Update vom Gastgeber“ automatisch, Reinwerfen und 7-Tausch, „Rückseiten wie am echten Tisch“, Musik.

## 2. Projektaufbau

```
game/                         Godot 4.6.1, Compatibility-Renderer, Querformat, Basisgröße 1600×720
  project.godot               gehört Modul C; Autoload "App" = res://scripts/app/app.gd
  scenes/main.tscn            Startszene (Modul F)
  scripts/rules/              Modul A: Regelwerk (reine Logik, keine Nodes)
  scripts/net/                Modul D: Transport, Protokoll, Lobby, Suche
  scripts/app/                Modul C: App, Einstellungen, Updater, ApkShare, NetAndroid, Ton
  scripts/game/               Modul G: Spielsteuerung (LocalTable, HostTable, ClientTable), Computergegner-Takt
  scripts/ui/                 Modul F: Tisch, Hand, Karten, Regie, Effekte, Menüs
  assets/cards/               Modul B: Kartenbilder PNG
  assets/fonts/ assets/sfx/ assets/ui/   Modul B / C
  assets/web.zip              Modul E: Browser-Client (vom Bau erzeugt aus webclient/)
  android/build/              Modul C: Gradle-Vorlage samt Java-Helfern
  tests/                      Testskripte aller Module (test_<modul>_*.gd)
webclient/                    Modul E: Quellen des Browser-Clients (index.html, app.js, style.css)
tools/                        Bau-, Test-, Asset- und Veröffentlichungsskripte
```

- Jedes Modul schreibt nur in seine Ordner. Gemeinsame Dateien wie `project.godot`, `export_presets.cfg` und `.gitignore` ändert nur Modul C. Bedarf anderer Module meldet es im Bericht.
- **Godot-Läufe** gehen immer über `tools/godot_run.ps1`. Das Skript hält den Systemmutex `Global\MauMauFlipGodot`, weil sich alle Läufe `game/.godot` teilen.
- **Tests** sind `SceneTree`-Skripte unter `game/tests/` und geben am Ende `RESULT: <n> ok` oder `FAIL: …` aus (Muster aus Draw2Race).
- **Sprache:** Code-Kommentare und Oberflächentexte auf Deutsch. Bezeichner englisch oder deutsch, aber je Datei einheitlich.

## 3. Karten

- **112 Karten.** Jede hat eine helle und eine dunkle Seite.
- **Hell:** Farben `rot gelb gruen blau`.
  - je Farbe: Zahlen 1–9 doppelt, `plus1` ×2, `aussetzen` ×2, `richtungswechsel` ×2, `flip` ×2
  - `wuenscher` ×4, `wuenscher_plus2` ×4
- **Dunkel:** Farben `pink tuerkis orange lila`.
  - je Farbe: Zahlen 1–9 doppelt, `plus5` ×2, `alle_aussetzen` ×2, `richtungswechsel` ×2, `flip` ×2
  - `wuenscher` ×4, `farbjagd` ×4
- **Gesichtsschlüssel** (Dateiname ohne Endung):
  - farbige Karten: `<seite>_<farbe>_<wert>`, z. B. `hell_rot_7`, `hell_gelb_plus1`, `dunkel_lila_alle_aussetzen`, `dunkel_pink_flip`
  - Joker: `<seite>_<typ>`, also `hell_wuenscher`, `hell_wuenscher_plus2`, `dunkel_wuenscher`, `dunkel_farbjagd`
  - insgesamt 108 verschiedene Gesichter
- **Neutrale Rückseite** `rueckseite` für die Regel „Rückseiten verdeckt“.
- **Bilder:**
  - App: `game/assets/cards/<schluessel>.png`, 300×466 px, transparente Ecken.
  - Browser: `webclient/cards/<schluessel>.webp`, 200×311 px.
- **Paarung hell↔dunkel:** wird je Runde aus dem Seed zufällig gebildet (Regelbericht 1.1). Kartenkennungen `id` sind Zahlen 0–111. Sie werden je Runde neu gemischt, damit niemand Kennungen und Rückseiten verknüpfen kann.

## 4. Regelwerk (Modul A) – `scripts/rules/`

### Dateien und Klassen

- **`card_db.gd` (`class_name CardDB`)**
  - statische Kartenliste (112 Paare von Gesichtern `{side, color, kind, value}`)
  - `face_key(face) -> String`
  - Punktwerte
  - `static func faces_light() / faces_dark()`
- **`rule_config.gd` (`class_name RuleConfig`)**
  - Optionen mit Standardwerten
  - `to_dict()` / `from_dict()`
  - `static func preset(name)`: `"offiziell"`, `"klassisch500"`, `"familie"`, `"mau_mau"`
  - `describe() -> Array[String]` für die Regelübersicht
- **`mau_game.gd` (`class_name MauGame`, `RefCounted`):** die Zustandsmaschine
- **`bot.gd` (`class_name MauBot`):**
  - `static func choose(view: Dictionary, rng_seed: int, level := 1) -> Dictionary` liefert eine Aktion.
  - Arbeitet nur auf der Sicht eines Platzes, schummelt also nicht.
- **`rules_text.gd` (`class_name RulesText`):** Hilfetexte je Gesicht und je Konfiguration (Kartenhilfe), Regelübersicht

### Regeloptionen (Standard = Voreinstellung „offiziell“)

| Schlüssel | Werte (Standard fett) |
|---|---|
| `round_end` | **`first`** (erster fertig) / `last` (bis zum Letzten, Platzierungen) |
| `scoring` | **`none`** / `points500` (Sieger erhält Restpunkte, Partie bis `target`) |
| `target` | **500** |
| `hand_size` | **7** (5–10) |
| `draw_rule` | **`one`** (eine Karte, darf sie sofort legen) / `until_playable` |
| `drawn_card` | **`may`** / `must` / `may_not` |
| `stacking` | **`off`** / `same` (gleiche Ziehkarte weitergeben, Summe wächst) |
| `wild_restriction` | **`bluff`** (+2/Farbjagd nur ohne aktuelle Farbe, Anzweifeln möglich) / `enforce` (App verhindert) / `free` |
| `wild_counts_for_bluff` | **true** (Fassung 2024: Joker auf der Hand zählen als passend) / false |
| `jagd_wild_stops` | **false** (gezogener Joker beendet die Farbjagd nicht) |
| `mau_call` | **`catch`** (Mitspieler können erwischen) / `auto` (App bestraft sofort) / `reminder` (nur Hinweis) / `off` |
| `mau_penalty` | **2** |
| `backs_visible` | **true** (Rückseiten der Mitspieler sichtbar) / false (neutrale Rückseite) |
| `peek_own_backs` | **true** (eigene Rückseiten ansehen erlaubt) |
| `two_player_reverse_skips` | **true** |
| `flip_last_card` | **`execute`** (Flip als letzte Karte wird ausgeführt, Wertung auf neuer Seite) |

Startkarte, Flip und Neumischen verhalten sich wie in Abschnitt 1.13 von `docs/recherche/07_regeln_hausregeln.md`.

**Voreinstellungen**
- **`familie`:** `round_end=last`, `stacking=same`, `wild_restriction=enforce`, `mau_penalty=1`
- **`mau_mau`:** `stacking=same`, `wild_restriction=enforce`, `mau_penalty=1`
- **`klassisch500`:** `scoring=points500`, `wild_counts_for_bluff=false`

### Schnittstelle `MauGame`

```gdscript
static func create(config: RuleConfig, players: Array, seed: int) -> MauGame
    # players: [{name: String, kind: "human"|"bot"}], Reihenfolge = Sitzordnung im Uhrzeigersinn; Platz 0 gibt zuerst.
func start_round() -> Array          # Ereignisse (Austeilen, Startkarte)
func apply(seat: int, action: Dictionary) -> Dictionary
    # → {ok: bool, reason: String (deutsch, für Hinweis), events: Array}
func view_for(seat: int) -> Dictionary   # seat = -1: Zuschauer/Sichtschutz (keine eigene Hand)
func events_for(seat: int, events: Array) -> Array   # filtert verdeckte Information je Empfänger
func current_seat() -> int
func phase() -> String
func is_over() -> bool
func to_dict() -> Dictionary / static func from_dict(d) -> MauGame   # Speichern/Fortsetzen
```

### Aktionen

`{a: <name>, …}`:

| Aktion | Bedeutung |
|---|---|
| `{a:"play", card:<id>, color:<farbe>?}` | Karte legen. Wünscher brauchen `color` (Farbe der aktiven Seite). |
| `{a:"draw"}` | Ziehen (nach Regel `draw_rule`). |
| `{a:"keep"}` | Gezogene, spielbare Karte behalten; der Zug endet. |
| `{a:"challenge"}` / `{a:"accept"}` | Anzweifeln oder annehmen, nur der Betroffene nach +2 bzw. Farbjagd im Modus `bluff`. |
| `{a:"mau"}` | Mau rufen (gültig ab „2 Karten und am Zug“ bis zum Beginn des nächsten Zugs). |
| `{a:"catch", target:<seat>}` | Erwischen. |
| `{a:"next_round"}` | Nächste Runde, nur Platz 0 bzw. Gastgeber. |

### Phasen

| Phase | Bedeutung |
|---|---|
| `turn` | normaler Zug |
| `drawn` | gezogene Karte: `play` oder `keep` |
| `challenge` | Betroffener entscheidet `challenge` oder `accept` |
| `round_over` | Runde beendet |
| `game_over` | Partie beendet |

### Sicht `view_for(seat)`

Alle Daten JSON-tauglich: Zahlen als `int`, keine Godot-Typen.

```json
{
  "v": 1, "seat": 2, "side": "hell", "phase": "turn", "turn": 2, "dir": 1, "color": "blau",
  "players": [ {"seat":0, "name":"Lena", "kind":"human", "count":6, "backs":["dunkel_pink_flip", "..."],
                "place":0, "mau":false, "connected":true, "score":0} ],
  "hand": [ {"id":17, "face":"hell_blau_9", "back":"dunkel_orange_2"} ],
  "top": {"id":5, "face":"hell_blau_9"}, "draw_back":"dunkel_tuerkis_7", "draw_count":47,
  "pending": {"kind":"stack", "amount":2}, "hints": {"playable":[17], "can_draw":true, "can_keep":false,
  "can_challenge":false, "can_mau":false, "catch":[1], "need_color":false, "text":"Du bist dran."},
  "round": 1, "ranking": [], "rules": {"...": "RuleConfig.to_dict()"}
}
```

**Felder**
- `players[].backs`: sichtbare Gegenseiten der Handkarten dieses Spielers.
  - **sortiert** nach Seite, Farbe, Art und Wert, nie in der Reihenfolge des Besitzers;
  - leer, wenn `backs_visible=false` oder der Spieler man selbst ist.
- `hand[].back`: nur gesetzt, wenn `peek_own_backs=true`.
- `hints`: Der Client braucht keine eigene Regelkenntnis.

**Ereignisse:** `{e: <name>, seat?, …}`, z. B.:
- `deal`, `play{seat, card, face}`, `draw{seat, count, faces?}` (`faces` nur für den Ziehenden)
- `skip{seat}`, `skip_all`, `reverse{dir}`, `color{color}`, `flip{side}`, `pending{amount}`
- `challenge{seat, success}`, `mau{seat}`, `catch{seat, target}`, `penalty{seat, count}`
- `shuffle`, `round_over{ranking, scores}`, `game_over`

### Prüfungen (Pflicht)

- Kontrollsummen der Punkte (hell 1280, dunkel 1480).
- Jede Regel einzeln testen, dazu alle Optionen.
- 10 000 Bot-Partien ohne Fehler, Kartenzahl immer 112.
- Lecktest: `view_for(s)` enthält nie fremde Vorderseiten und nie den Seed.
- Determinismus: gleicher Seed und gleiche Aktionen ergeben denselben Zustand.

## 5. Netz (Modul D) – `scripts/net/`

**Ein TCP-Port: `24690`** (Rückfall 24691–24699, falls belegt).

**HTTP/1.1-Server in GDScript**
- `net_server.gd`, `class_name NetServer`, nicht blockierend, Abfrage in `poll()`.
- Wenn das erste Byte einer Verbindung `0x16` ist (TLS-Versuch), sofort schließen.
- Routen:
  - `GET /` → `index.html`
  - `GET /<datei>` → aus `assets/web.zip`, mit korrekten MIME-Typen, Gzip optional
  - `GET /info` → JSON `{game:"mau-mau-flip", version, name, players, port}`
  - `GET /apk` → APK-Datei (Quelle ApkShare), gestückelt gestreamt, mit `Content-Disposition` `MauMauFlip-<version>.apk`
  - `GET /ws` → eigener WebSocket-Handshake (RFC 6455, SHA-1 plus Base64), danach Rahmen lesen und schreiben (Text, Ping/Pong, Close, maskierte Client-Rahmen)
- Kein HSTS, keine Umleitung auf https, kein `upgrade-insecure-requests`. Größengrenzen beachten.

**App-Client:** Godot `WebSocketPeer` auf `ws://<host>:<port>/ws`.

**Protokoll** (`net_protocol.gd`, `class_name NetProtocol`): JSON-Textrahmen. Die Protokollversion `PROTO := 1` steht in jeder Begrüßung.

Client → Host:

| Nachricht | Inhalt |
|---|---|
| `{t:"hello", proto, game:"0.1.1", name, kind:"app"\|"web", token?}` | Anmeldung; mit `token` als Wiederverbindung |
| `{t:"act", seq, a:{…}}` | Spielaktion (Abschnitt 4) |
| `{t:"lobby_ready", ready:bool}` | Bereit-Meldung in der Lobby |
| `{t:"ping", ts}` | Lebenszeichen |
| `{t:"log", text}` | Fehler aus dem Browser für das Gastgeber-Log |

Host → Client:

| Nachricht | Inhalt |
|---|---|
| `{t:"welcome", id, token, host_name}` | Anmeldung angenommen |
| `{t:"reject", code, text}` | `code`: `version`, `full`, `running`, `proto` |
| `{t:"lobby", rev, players:[{id, name, kind, connected, ready, seat}], rules, host_id}` | Lobby-Stand |
| `{t:"start", seat}` | Partie beginnt |
| `{t:"state", seq_ack?, events:[…], view:{…}}` | nach jeder Änderung: gefilterte Ereignisse plus vollständige Sicht (Abschnitt 4) |
| `{t:"err", text}` | Aktion abgelehnt; Text für den Hinweis |
| `{t:"pong", ts}` | Antwort auf `ping` |
| `{t:"bye", text}` | Gastgeber beendet |

**Sitzungsregeln**
- `net_session.gd`, `class_name NetHostSession`; spielunabhängig, kennt nur Spieler, Token und Plätze:
  - Spieler-Kennung `id` (Zahl), Token mit 24 Zeichen aus `Crypto.generate_random_bytes`.
  - Plätze ordnet der Gastgeber (`set_seat_order(ids)`).
  - Verbindungsverlust: Platz bleibt reserviert, `connected=false`.
  - Wiederbeitritt mit Token: derselbe Platz, sofort `lobby` bzw. `state`.
  - Höchstens 10 Spieler. 8 KB je Client-Nachricht, 20 Nachrichten pro Sekunde.
- `net_client.gd`, `class_name NetClient`:
  - verbindet, merkt sich das Token je Host-Adresse, verbindet automatisch neu (Abstand 1, 2, 4 s, höchstens 5 s).
- `net_discovery.gd`, `class_name NetDiscovery`: UDP-Port `24692`.
  - Rundruf „MMF?“, Antwort JSON aus `/info`.
  - Gerichtete Rundrufe je Schnittstelle (Lehre aus Draw2Race), Multicast-Sperre über NetAndroid.
- **Ton:** Den Mau-Ton spielt nur das Gerät, das „Mau!“ gedrückt hat (Katzen-Leitplanke). Alle anderen zeigen nur die Animation.
- **Tests:**
  - Gastgeber und mehrere Clients im selben Prozess über 127.0.0.1, eigene Testports 24790+.
  - Handshake, Rahmen (auch fragmentiert und groß), Wiederverbinden, Ablehnungen, TLS-Byte.
  - HTTP-Routen mit Zip-Inhalt, APK-Streaming mit Range optional.

## 6. Spielsteuerung (Modul G) – `scripts/game/`

Eine einheitliche Schnittstelle für die Oberfläche: `TableSource` (`table_source.gd`).

```gdscript
signal state_changed(events: Array, view: Dictionary)   # Oberfläche spielt events ab und gleicht dann mit view ab
signal notice(text: String)                                # Hinweis (Ablehnung, Verbindung …)
func act(action: Dictionary) -> void
func local_seat() -> int                                   # wessen Hand gerade gezeigt wird
func mode() -> String                                      # "solo" | "pass" | "host" | "client"
```

**Umsetzungen**
- **`LocalTable`** (Übung und Weitergeben):
  - MauGame im Prozess, Computergegner mit Denkpause 0,6–1,2 s.
  - Im Weitergeben-Modus: Signal `handover(next_seat)`, bevor die Hand eines anderen Menschen gezeigt wird.
- **`HostTable`:**
  - MauGame plus NetHostSession. Sendet jedem Client `events_for(seat)` und `view_for(seat)`.
  - Computergegner laufen beim Gastgeber.
  - Speichert den Stand nach jedem Ereignis (`user://laufende_partie.json`).
- **`ClientTable`:** NetClient; gibt `state` weiter.

## 7. Oberfläche (Modul F) – `scripts/ui/`, `scenes/`

**Szenen**
- Hauptmenü mit Logo:
  - Übungsspiel
  - Auf einem Handy (Weitergeben)
  - Im WLAN spielen: Gastgeber oder Beitreten
  - Regeln
  - Einstellungen
  - App teilen
  - Update
- Einrichtung Weitergeben (Namen, Reihenfolge, Computergegner).
- Lobby (Gastgeber):
  - Spielerliste mit Ziehen zum Ordnen der Plätze
  - QR-Code und Adresse (`http://ip:port/`)
  - Regeln wählen, Computergegner hinzufügen, Start
- Beitreten: gefundene Spiele, Adresse eingeben.
- Tisch, Sichtschutz, Rundenende und Wertung, Regeln, Einstellungen.

**Bausteine**
- `card_view.gd`: Karte mit Vorder- und Rückseite, Flip über eine Faux-3D-Drehung, Schatten, Hervorhebung.
- `hand_view.gd`: Hand in drei Stufen, Schwung, Federn, Gesten.
- `table_view.gd`: Plätze, Stapel, Ringe, Knöpfe.
- `director.gd`: spielt Ereignisse ab.
- `effects.gd`: Partikel, Farbwelle, Konfetti, Flip-Übergang.
- QR-Code: eigenes GDScript, Byte-Modus, Fehlerkorrektur M (Lizenzfreiheit sicherstellen).

**Maßstab:** `art/entwurf/a-papier-neon/hand.png` (Querformat 1600×720). Die Oberfläche richtet sich nach dem Entwurf: Papier und Neon, Bricolage Grotesque für Werte und UI, Fraunces für Überschriften und „Mau!“.

**Prüfungen**
- Kontrollbilder mit echtem Renderer: `tools/godot_run.ps1` ohne `-Headless`, Viewport-Bild speichern. Szenarien: Hand mit 5, 12 und 25 Karten, Flip, Wünscher, Sichtschutz, Lobby.
- Gesten-Logik als reine Funktionen testen (headless).

## 8. Browser-Client (Modul E) – `webclient/`

- `index.html`, `style.css`, `app.js`, `qr`-frei.
- Ohne externe Abhängigkeiten, ohne Webfonts von außen: Die Schriften liegen als woff2 im Client.
- Ablauf:
  1. Startseite „Mau-Mau Flip – Mitspielen“: Name eingeben, Knopf „Beitreten“. Der Knopf schaltet zugleich den Ton frei und startet den Video-Trick gegen das Abdunkeln.
  2. Lobby-Ansicht.
  3. Tisch im Querformat, Hinweis „Bitte quer halten“.
- Spielt vollständig mit: Hand als Fächer bzw. waagerecht wischbar, Antippen hebt an, zweites Tippen oder Wischen nach oben spielt aus, Farbwahl, Ziehen, Behalten, Anzweifeln, Mau, Erwischen.
- Animationen in reduzierter Form (CSS).
- Wiederverbinden: Token in `localStorage` (mit try/catch abgesichert), bei `visibilitychange` und `pageshow` neu verbinden.
- Android-Gäste sehen auf der Startseite zusätzlich „App installieren (APK)“ → `/apk`.
- Fehler gehen per `{t:"log"}` an den Gastgeber.
- Testbar am PC mit Chrome headless gegen einen Godot-Gastgeber (Testmodus `?autotest=1`).

## 9. Android, App, Bau (Modul C)

- **Paket und Version:** `de.maumauflip.game`, Name „Mau-Mau Flip“, Version 0.1.1, Code 1001 (X·1 000 000 + Y·1 000 + Z).
- **Gradle-Bau** mit Java-Helfern aus Draw2Race 1.0.0, angepasst:
  - `Updater.java` mit `SDK_INT`-Prüfungen und `catch (Throwable)`
  - `NetHelper.java`, `ApkShare.java`, `GodotApp.java`
- **Berechtigungen:** INTERNET, REQUEST_INSTALL_PACKAGES, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE, CHANGE_WIFI_MULTICAST_STATE, VIBRATE, WAKE_LOCK (Bildschirm an).
- **Signatur:** `.tools/maumauflip-release.keystore` (Daten in `.tools/maumauflip-release.properties`), Release-Export. Der Bau bricht ab, wenn der Schlüssel fehlt.
- **Updater:**
  - Repos `ShakieVan/Mau-Mau-Flip` (Releases) und `ShakieVan/Mau-Mau-Flip-Beta` (Testversionen), Asset `MauMauFlip-X.Y.Z.apk`.
  - **Beta-Kanal ist an, wenn die installierte Version nicht auf `.0` endet.**
  - HTTP 403 als „GitHub-Limit erreicht“ melden.
  - Knopf „Im Browser herunterladen“.
- **Skripte**
  - `tools/setup.ps1`
  - `tools/build.ps1 -Target Test|Windows|Android|Web|All`; `Web` packt `webclient/` nach `game/assets/web.zip`.
  - `tools/godot_run.ps1`
  - `tools/release.ps1`: Release im Beta- oder Haupt-Repo, nur nach erfolgreichem Bau und Test.

## 10. Reihenfolge

1. **Fundament (parallel):**
   - A Regelwerk
   - B Kartenbilder, Schriften, Symbole
   - C Projekt, Android, Updater, Bau
   - D Netz
   - F1 Oberflächenbausteine mit Beispieldaten
   - E1 Browser-Client gegen Beispieldaten
2. **Zusammenbau:** G Spielsteuerung, F2 Szenen und Tisch mit echtem Regelwerk, E2 Browser-Client am echten Gastgeber, Töne.
3. **Prüfung:**
   - Tests, Kontrollbilder, Bot-Dauerläufe.
   - Gerätetest: S21 als Gastgeber, S10 per App, Chrome auf S10 als Browser-Gast, PC-Browser.
   - Gegenprüfung durch eigene Prüfer (Regeln, Lecks, Bedienung).
4. **Veröffentlichung:** Bau, Signaturprüfung, Release 0.1.1 im Beta-Repo, Quellcode im Haupt-Repo, Doku.

## Abweichungen

(von Modulen ergänzt)
