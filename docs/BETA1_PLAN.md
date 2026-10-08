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
  - Einstellungen: Name, Mau-Ton aus/leise/normal, Spieltöne aus/leise/normal (Standard aus), „Spielbare Karten hervorheben“ (je Gerät, Standard an), Vibration, Effekte voll/reduziert, Beta-Kanal.
  - Regelübersicht und Kartenhilfe, Regel-Editor mit Abschnitt „Hausregeln mit Zusatzkarten“ (Kartentausch samt Tauschrichtung, Glücksspiel, Farbe mit ablegen) und Kartenzahl 112–124.
- **Töne:** Mau-Ton und „Mau-Mau!“ sind die Aufnahmen des Nutzers (`audio/aufnahmen/`, AGENTS.md 20) und klingen auf allen Geräten (AGENTS.md 21). Spieltöne Karte legen, ziehen, mischen, Flip, Du bist dran, Fehler und Sieg: KI-erzeugt mit MOSS-SoundEffect v2.0, nachbearbeitet mit `tools/make_sfx_moss.py --spiel` (Katzen-Leitplanke, `audio/sfx_README.md`); App und Browser nutzen dieselben Dateien und Pegel.
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
  - statische Kartenliste (112 Paare von Gesichtern `{side, color, kind, value}`), dazu die Zusatzkarten der Hausregeln (Kartentausch +4, Glücksspiel +2, Farbe mit ablegen +6, höchstens 124 Karten und 128 verschiedene Gesichter)
  - `face_key(face) -> String`
  - Punktwerte
  - `static func faces_light() / faces_dark()`, mit Hausregeln `faces_light(with_swap, with_gamble, with_discard)`; ebenso `deck(s, …)`, `card_count(…)`, `point_sum(s, …)`; `all_keys()` = 108 Gesichter des Grunddecks, `all_keys(true)` = alle 128
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
| `draw_play` | **`drawn`** (offiziell: nach freiwilligem Ziehen nur die gezogene Karte; passt sie nicht, endet der Zug) / `any` (Hausregel „Nach dem Ziehen: beliebige Karte legen“, ab 1.1.3: Phase `drawn` bleibt, solange irgendeine Karte passt; jede passende Karte legen oder `keep`; passt nichts, endet der Zug; `hints.playable` listet alle passenden). Nicht beim Strafziehen, nicht bei `draw_rule=until_playable`. Mit `drawn_card=must` muss eine passende gezogene Karte gelegt werden, mit `may_not` ist nur die gezogene gesperrt. In „Familie“ `any`; `RuleConfig.migrate_dict` hebt die Familie 1.1.2 (ohne Schlüssel) |
| `stacking` | **`off`** / `same` (gleiche Ziehkarte weitergeben, Summe wächst) |
| `wild_restriction` | **`free`** (+2/Farbjagd immer erlaubt, ab 0.1.3 Standard in allen Voreinstellungen) / `enforce` (nur ohne aktuelle Farbe, App verhindert) / `bluff` (nur noch aus Verträglichkeit, Anzweifeln; Oberflächen bieten es nicht an, `RuleConfig.migrate_dict()` macht gespeichertes `bluff` beim Laden zu `free`) |
| `wild_counts_for_bluff` | **true** (Fassung 2024: Joker auf der Hand zählen als passend) / false; ab 0.1.3 nicht mehr in der Oberfläche, zählt bei `free` nicht für die Voreinstellung |
| `jagd_wild_stops` | **false** (gezogener Joker beendet die Farbjagd nicht) |
| `mau_call` | **`catch`** (Mitspieler können erwischen) / `auto` (App bestraft sofort) / `reminder` (nur Hinweis) / `off` |
| `mau_penalty` | **2** |
| `backs_visible` | **true** (Rückseiten der Mitspieler sichtbar) / false (neutrale Rückseite) |
| `peek_own_backs` | **true** (eigene Rückseiten ansehen erlaubt) |
| `two_player_reverse_skips` | **true** |
| `flip_last_card` | **`execute`** (Flip als letzte Karte wird ausgeführt, Wertung auf neuer Seite) |
| `swap_cards` | **`off`** / `on` (Hausregel Kartentausch: 4 zusätzliche Karten, also 116; hell je eine `hell_<farbe>_tausch`, dunkel je eine `dunkel_<farbe>_tausch`, 20 Punkte, legbar auf gleiche Farbe oder jeden Kartentausch; alle aktiven Spieler geben ihre ganze Hand an den nächsten aktiven Platz weiter, danach ist der Nächste in Spielrichtung dran; in der Voreinstellung „Familie“ an) |
| `swap_direction` | **`clockwise`** (Platz + 1) / `counter` (Platz − 1) / `play` (in der aktuellen Spielrichtung) / `against` (gegen die Spielrichtung); Texte „Im Uhrzeigersinn“, „Gegen den Uhrzeigersinn“, „In Spielrichtung“, „Gegen die Spielrichtung“ (`RuleConfig.swap_direction_title()`) |
| `gamble_cards` | **`off`** / `on` (Hausregel Glücksspiel: 2 zusätzliche Karten, je Seite zweimal der Joker `hell_gluecksspiel` bzw. `dunkel_gluecksspiel`, 50 Punkte; Legen mit Farbwahl, danach Phase `gamble`: Karte verdeckt setzen, Knopf drücken, bis ein Treffer kommt oder die Hand leer ist; in keiner Voreinstellung) |
| `discard_color` | **`off`** / `on` (Hausregel Farbe mit ablegen: 6 zusätzliche Karten, je Seite `hell_<farbe>_ablegen` je Farbe, 30 Punkte, legbar auf gleiche Farbe oder jede Ablegen-Karte, und zweimal der Joker `hell_ablegen_joker` bzw. `dunkel_ablegen_joker`, 50 Punkte; danach wählt der Leger in der Phase `discard_pick`, welche seiner Karten der Farbe (außer Jokern) ohne Wirkung mit auf die Ablage kommen; in keiner Voreinstellung) |
| `flip_surprise` | **`off`** / `on` (Hausregel „Flip-Überraschung“: Liegt nach einem ausgeführten Flip eine klassische Aktionskarte oben – `plus1`, `plus5`, `aussetzen`, `alle_aussetzen`, `richtungswechsel`, `wuenscher_plus2`, `farbjagd` –, wirkt sie, als hätte der Flip-Spieler sie gelegt; betroffen ist der Nächste nach ihm. Bei Wünscher +2 und Farbjagd wählt der Flip-Spieler zuerst die Farbe (Phase `color`). Flip, Wünscher und Zusatzkarten oben lösen nichts aus, ebenso wenig ein Flip, mit dem die Runde endet. Stapeln und `penalty_turn` gelten wie beim Legen, Anzweifeln gibt es nicht. In „Familie“ an) |
| `flip_mode` | **`pile`** / `card` (Hausregel „Flip dreht nur die gelegte Karte“, 1.0.2: Bei `card` wird nur die Flip-Karte umgedreht, oben liegt ihre andere Seite; die übrige Ablage bleibt in ihrer Reihenfolge darunter und erscheint in `view.discard_log` mit der Seite, mit der sie lag. Nachziehstapel und Hände wenden sich wie offiziell. In „Familie“ `card`) |

Kartenzahl je Partie: 112 + 4 (`swap_cards`) + 2 (`gamble_cards`) + 6 (`discard_color`), also 112 bis 124. Prüfsummen je Seite: hell 1280, dunkel 1480, dazu Kartentausch +80, Glücksspiel +100, Farbe mit ablegen +220. Die Kartencodes des Grunddecks und des Kartentauschs bleiben unverändert, die neuen hängen dahinter (Einzelheiten: `docs/module/A.md`).

Startkarte, Flip und Neumischen verhalten sich wie in Abschnitt 1.13 von `docs/recherche/07_regeln_hausregeln.md`.

**Voreinstellungen**
- **`familie`:** `round_end=last`, `stacking=same`, `penalty_turn=play`, `wild_restriction=free`, `mau_penalty=1`, `swap_cards=on`, `swap_direction=play`, `gamble_cards=on`, `discard_color=on`, `flip_surprise=on`, ab 1.0.2 `flip_mode=card` (Nutzerentscheidung 06.10.2026, ab 0.1.4; also 124 Karten). Gespeicherte Familie 1.0.1 (ohne `flip_mode`) hebt `RuleConfig.migrate_dict` auf die neue. Bis 0.1.3 war es `wild_restriction=enforce`, `swap_cards=on` ohne die übrigen Zusatzregeln (116 Karten). `RuleConfig.migrate_dict` hebt gespeicherte Regeln, die genau dieser alten „Familie“ entsprechen (mit `enforce` oder, nach `bluff` → `free`, mit `free`), auf die neue.
- **`mau_mau`:** `stacking=same`, `wild_restriction=enforce`, `mau_penalty=1`
- **`klassisch500`:** `scoring=points500` (seit 0.1.3 ohne `wild_counts_for_bluff=false`, das bei `free` nicht zählt)

**Eigene Regelsätze** gehören nicht zum Regelwerk. Sie sind gespeicherte `RuleConfig.to_dict()` in den Einstellungen des Geräts (`RuleSets`, Abschnitt 9), dazu die Regeln des letzten Gastgebers. `RuleConfig` bleibt dafür unverändert.

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
| `{a:"mau"}` | Mau rufen (gültig ab „2 Karten und am Zug“ bis zum Beginn des nächsten Zugs; mit Ablegen-Karten auch mit mehr Karten, wenn eine legbare Karte genau 1 übrig lassen kann, und in der Phase `discard_pick`; im Glücksspiel mit 2 Karten vor dem Setzen). |
| `{a:"catch", target:<seat>}` | Erwischen. |
| `{a:"next_round"}` | Nächste Runde, nur Platz 0 bzw. Gastgeber. |
| `{a:"stake", card:<id>}` | Glücksspiel: eine beliebige eigene Handkarte verdeckt auf den Einsatz legen (Pflicht vor jedem Druck). |
| `{a:"press"}` | Glücksspiel: Knopf drücken (erst nach einem `stake`). |
| `{a:"stop"}` | Glücksspiel: aufhören (immer erlaubt, nach mindestens einem Druck ohne Treffer, also bei `need = "stake"` und Einsatz ≥ 1). Der Einsatz kommt unter die Ablage, der Zug ist vorbei. |
| `{a:"discard_pick", cards:[<id>…], color:<farbe>?}` | Farbe mit ablegen, nur in Phase `discard_pick`: Teilmenge von `hints.can_pick` (auch leer); `color` = Spielfarbe, nur und Pflicht nach dem Ablegen-Joker. |

Glücksspiel und Ablegen-Joker werden wie Wünscher mit `{a:"play", card, color}` gelegt; beim Ablegen-Joker ist `color` die Ablegefarbe, die Spielfarbe folgt mit `discard_pick`.

### Phasen

| Phase | Bedeutung |
|---|---|
| `turn` | normaler Zug |
| `drawn` | gezogene Karte: `play` oder `keep` |
| `challenge` | Betroffener entscheidet `challenge` oder `accept` |
| `color` | nach einem Flip liegt ein Joker oben: der Flip-Spieler wählt `{a:"color", color}` |
| `gamble` | Glücksspiel des Legers (`current_seat()`): abwechselnd `stake` und `press`, bis ein Treffer kommt (1–10 Karten ziehen, Einsatz zurück, Zug vorbei) oder bei 0 die Hand leer ist (Einsatz unter die Ablage, fertig); `mau` und `catch` gehen wie sonst |
| `discard_pick` | Farbe mit ablegen (seit 0.1.3): Der Leger (`current_seat()`) wählt mit `discard_pick` die mitabgelegten Karten, beim Ablegen-Joker dazu die Spielfarbe. Entsteht nach einer Ablegen-Karte, wenn der Leger Nicht-Joker-Karten der Ablegefarbe hat, nach einem Ablegen-Joker immer. `mau` geht, wenn nach der Auswahl genau 1 Karte bleiben kann. |
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
- `hints`: Der Client braucht keine eigene Regelkenntnis. `hints.text` ist deutsch, `hints.lt` (seit 1.2.2) dieselbe Zeile als Bausteine für die eigene Sprache (siehe Abschnitt 5, „Texte in jeder Sprache“).
- `discard_log` (seit 1.0.1, „Ablage durchsehen“, immer vorhanden, für alle Plätze gleich): die Ablage von unten nach oben, so wie sie gerade liegt (seit dem letzten Mischen; nach einem Flip die andere Seite in umgekehrter Reihenfolge). Eintrag `{f: Gesicht oder "" wenn verdeckt, s: Platz des Legers oder −1 (Startkarte/unbekannt), c: Wunschfarbe bei Jokern oder "", h: true bei verdeckten Glücksspiel-Einsätzen}`; der letzte Eintrag ist die oberste Karte (`top`). Mitabgelegte Karten („Farbe mit ablegen“) tragen den Leger. Verdeckte Einsätze haben nie ein Gesicht; liegt ein Einsatz nach einem Flip oben, ist er offen (`h` bleibt true). Mischen leert das Protokoll bis auf die oberste Karte. Im Spielstand als `dlog` `[[id, s, c, h], …]`.
- **Nur mit `gamble_cards=on`** (sonst fehlen die Felder, damit Sichten ohne die Hausregel unverändert bleiben):
  - `gamble`: während eines Glücksspiels `{seat, stake: Anzahl der Einsatzkarten, need: "stake"|"press", last: letzter Wert 0–10 oder −1}` für alle Plätze, sonst `{}`. Die Trefferquote und die Einsatzgesichter stehen nie in einer Sicht.
  - `hints.can_stake`: ids der setzbaren Karten (nur der Glücksspieler bei `need = "stake"`, sonst `[]`), `hints.can_press` (bool), `hints.can_stop` (bool, nur mit der Hausregel; sonst fehlt das Feld wie `can_stake`/`can_press`). Hinweistexte: „Leg eine Karte verdeckt auf deinen Einsatz.“, „Noch eine Karte setzen – oder aufhören?“ (bei `can_stop`) bzw. „Drück den Glücksspielknopf!“.
- **Nur mit `discard_color=on`:** `discard_pick`: während der Auswahl `{seat, color}` (Ablegefarbe) für alle Plätze, sonst `{}` (keine Kandidatenzahl, das wäre ein Leck); `hints.can_pick` = ids der wählbaren Karten (nur der Leger), `hints.pick_color` = true nach dem Ablegen-Joker (Spielfarbe nötig).

**Ereignisse:** `{e: <name>, seat?, …}`, z. B.:
- `deal`, `play{seat, card, face}`, `draw{seat, count, faces?}` (`faces` nur für den Ziehenden)
- `skip{seat}`, `skip_all`, `reverse{dir}`, `color{color}`, `flip{side}`, `pending{amount}`
- `flip_surprise{seat, face}` (Flip-Überraschung, öffentlich): `seat` = Flip-Spieler, `face` = Gesicht oben; direkt nach `flip` (bzw. nach `color` beim Joker oben) und vor den Wirkungs-Ereignissen (`skip`, `reverse`, `skip_all`, `pending` …).
- `challenge{seat, success}`, `mau{seat}`, `catch{seat, target}`, `penalty{seat, count}`
- `shuffle`, `round_over{ranking, scores}`, `game_over`
- `swap_hands{seat, dir, counts, hand?, backs?}` (Kartentausch): `seat` = Leger, `dir` = Tauschrichtung ±1, `counts` = Kartenzahl je Platz nach dem Tausch; `hand` = nur die eigene neue Hand (`events_for`), `backs` = Rückseiten je Platz sortiert (bei `backs_visible`). Danach liefert `view_for` die neuen Hände. Wer so auf 1 Karte kommt, muss nicht „Mau!“ rufen. Als letzte Karte: Leger fertig, Tausch nur unter den Übrigen bzw. entfällt bei Rundenende (Einzelheiten: `docs/module/A.md`, „Kartentausch“).
- Glücksspiel (Einzelheiten: `docs/module/A.md`, „Glücksspiel“):
  - `gamble_start{seat}` nach `play` (und `color`): Phase `gamble` beginnt.
  - `stake{seat, count, card*, face*, back*}`: Karte verdeckt gesetzt; `count` = Einsatzgröße danach; id, Gesicht und Rückseite (bei `peek_own_backs`) nur für den Spieler selbst.
  - `gamble_roll{seat, value}`: 0 = kein Treffer, 1–10 = Treffer.
  - bei einem Treffer `draw{…, reason:"gluecksspiel"}`, dann `stake_back{seat, count, cards*, faces*, backs}` (ganzer Einsatz zurück; Rückseiten wie beim Ziehen), danach `turn` des Nächsten.
  - bei 0 und leerer Hand `stake_discard{seat, count, cards*, faces*, reason:"empty"}` (Einsatz unter die Ablage), dann `finish` und `round_over` bzw. `turn`.
  - bei `{a:"stop"}` `stake_discard{seat, count, cards*, faces*, reason:"stop"}`, dann `turn` des Nächsten. Bleibt genau 1 Karte, gilt die normale Mau-Regel: Das Fenster hat schon das Setzen geöffnet (vorher rufen, sonst erwischbar, bis der Nächste handelt).
- Farbe mit ablegen: `discard_pick{seat, color}` nach `play`, wenn die Auswahl beginnt (öffentlich); nach der Auswahl (bzw. direkt nach `play`, wenn es keine Kandidaten gibt) `discard_color{seat, color, cards, faces, count}`: öffentlich, nur die gewählten Karten, unter der Ablegen-Karte nach Rang sortiert; beim Ablegen-Joker folgt `color{color}` mit der Spielfarbe.

### Prüfungen (Pflicht)

- Kontrollsummen der Punkte (hell 1280, dunkel 1480; je Deckvariante mit Zusatzkarten, siehe oben).
- Jede Regel einzeln testen, dazu alle Optionen.
- 10 000 Bot-Partien ohne Fehler, Kartenzahl immer 112; mit den Hausregeln je ein Dauerlauf mit konstanter Kartenzahl der Variante (alle Hausregeln an: 124).
- Lecktest: `view_for(s)` enthält nie fremde Vorderseiten und nie den Seed; beim Glücksspiel nie die Trefferquote und nie fremde Einsatzgesichter.
- Mit allen neuen Hausregeln aus bleibt das Regelwerk bit-gleich (Fingerabdruck über Bot-Partien).
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
| `{t:"reject", code, text, lt?}` | `code`: `version`, `full`, `running`, `proto`; `lt` siehe „Texte in jeder Sprache“ |
| `{t:"lobby", rev, players:[{id, name, kind, connected, ready, seat}], rules, host_id}` | Lobby-Stand |
| `{t:"start", seat}` | Partie beginnt |
| `{t:"state", seq_ack?, events:[…], view:{…}}` | nach jeder Änderung: gefilterte Ereignisse plus vollständige Sicht (Abschnitt 4) |
| `{t:"err", text, lt?}` | Aktion abgelehnt; Text für den Hinweis |
| `{t:"notice", text, lt?}` | Meldung an alle (z. B. „Kim ist getrennt – warte …“) |
| `{t:"pong", ts}` | Antwort auf `ping` |
| `{t:"bye", text}` | Gastgeber beendet |

**Texte in jeder Sprache** (seit Beta 1.2.2, englische Fassung; `game/scripts/app/i18n.gd`, `webclient/i18n.js`)
- Jedes Gerät zeigt Texte des Gastgebers in seiner eigenen Sprache. `text` bleibt deutsch (ältere Geräte zeigen ihn wie bisher).
- Ohne Platzhalter ist `text` selbst der Schlüssel (deutsche msgid); der Empfänger übersetzt ihn.
- Mit Platzhaltern (Namen, Zahlen, Farben) kommt zusätzlich `lt` (Bausteine): `hints.lt`, `err.lt`, `notice.lt`, `reject.lt`.
  - `lt` = Liste von Teilen, angezeigt mit Leerzeichen verbunden; Teil = String (msgid) oder `[vorlage, arg…]` (vorlage = msgid mit `%s`/`%d`).
  - arg = Zahl, String (wörtlich, z. B. Spielername) oder `{t: Teil}` (wird selbst übersetzt, z. B. Farbname „Blau“).
  - Beispiel: `[["%s ist dran.", "Lena"], "Denk an „Mau!“"]` → „Lena ist dran. Denk an „Mau!““ bzw. „Lena's turn. Remember “Mau!”“.
  - Deutsch gerendert ergibt `lt` genau `text` (Prüfung in `test_i18n`).
- `MauGame.apply` liefert bei Ablehnung zusätzlich `reason_lt`; `view_for` liefert `hints.lt`.
- Lobby, Ereignisse und Regeln enthalten nur Schlüssel (Phasen, Farben, Regeloptionen) und Namen, keine fertigen Sätze.

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
- **Ton:** Der Mau-Ton spielt auf allen Geräten, sobald das Ereignis `mau` bzw. `finish` ankommt (AGENTS.md 21, ersetzt „nur das eigene Gerät“), dazu eine animierte Sprechblase beim Rufenden. Wer den Ton abgeschaltet hat, sieht nur die Blase.
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
  - Spielerliste mit Ziehen zum Ordnen der Plätze (Zeilen 72 px, bei 1600 × 720 fünf Spieler ganz sichtbar, ab sechs wischen; nach „+“ oder einem Pfeil rollt die Liste zum Spieler)
  - Kopfzeile mit Spielerzahl und Computergegner −/+
  - QR-Code und Adresse (`http://ip:port/`)
  - Regelzeile unter der Liste: Knopf „Regeln“ (Editor mit den Voreinstellungen), daneben z. B. „Familie · 116 Karten“ und eine höchstens zweizeilige Beschreibung; Start
- Gast-Lobby: Regelkopf fett (z. B. „Familie · 116 Karten · mit Kartentausch“) über dem Regeltext, „Bereit“.
- Regeln: Voreinstellungen, alle Optionen, Abschnitt „Hausregeln mit Zusatzkarten“ mit Kartenbildern und Schaltern; die Tauschrichtung ist ohne Kartentausch gesperrt.
- Einstellungen: Abschnitt Ton (Mau-Ton, Spieltöne), Bedienung und Optik („Spielbare Karten hervorheben“ mit Hinweis „Nur auf diesem Gerät …“, Vibration, Effekte), Updates, App teilen, Info.
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
- Spielt vollständig mit: Hand als Fächer bzw. waagerecht wischbar, Antippen hebt an, zweites Tippen oder Wischen nach oben spielt aus, Farbwahl, Ziehen, Behalten, Anzweifeln, Mau, Erwischen; dazu die Hausregeln Kartentausch, Glücksspiel (Setzen per Tipp, Kuppelknopf → `press`) und Farbe mit ablegen.
- Menü: Mau-Ton, Spieltöne (dieselben Dateien und Pegel wie die App), „Spielbare Karten hervorheben“ (je Gerät in `localStorage`, Standard an), Effekte, Vibration, Vollbild; Sortieren über den Knopf am Tisch.
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
- **Einstellungen** (`AppSettings`, `user://einstellungen.json`, je Gerät, sofort gespeichert; Bildschirm `SettingsScreen`):
  - `name`, `mau_ton` (aus/leise/**normal**), `toene` (**aus**/leise/normal), `vibration` (**an**), `effekte` (**voll**/reduziert), `beta` (nach installierter Version), `sortierung` (**farbe**/wert/punkte/manuell), `regeln` (RuleConfig als Dictionary, zuletzt benutzte Regeln), `letzte_namen`, `regelsaetze`, `regeln_gastgeber` und `regelsatz_gewaehlt` (siehe unten).
  - `hervorheben` (bool, **an**): „Spielbare Karten hervorheben“. Persönliche Einstellung je Gerät, nie eine Regel des Gastgebers (AGENTS.md 24); steht nicht in `RuleConfig` und geht nicht übers Netz. Der Tisch liest `App.settings.get_value("hervorheben", true)` und hört auf `changed`. Aus: kein Rand, kein Leuchten, kein Anheben, kein Abdunkeln; eine unpassende Karte springt mit „Die Karte passt nicht.“ zurück (ohne Strafe), und der Hinweis „Du bist dran – nichts passt …“ wird zu „Du bist dran.“. Der Browser-Client hat dieselbe Einstellung unter demselben Namen (`localStorage` `mmf.hervorheben`).
  - Pegel (`AppSound`): Mau aus/leise/normal −80/−12/−2 dB, Spieltöne −80/−12,5/−4,5 dB.
  - **Gespeicherte Regelsätze** (Nutzerwunsch 06.10.2026, `scripts/app/rule_sets.gd`, `class_name RuleSets`):
    - `regelsaetze`: Liste `[{name, regeln}]`, höchstens 12. Name höchstens 20 Zeichen, Zeichen wie beim Spielernamen und zusätzlich `& + ( )`. Gleicher Name ohne Rücksicht auf Groß- und Kleinschreibung gilt als derselbe Satz: Überschreiben nach Rückfrage, der Platz bleibt. Löschen nach Rückfrage (im Regel-Editor: Satz gedrückt halten; das lädt ihn nicht).
    - `regeln_gastgeber`: `{host, regeln}`, genau ein Platz. Jeder App-Gast merkt sich die Regeln des Gastgebers selbst, sobald gespielt wird: aus jeder Sicht am Tisch (`TableScreen`), nicht schon aus der Lobby (bloßes Beitreten überschreibt den Platz nicht, Prüfung 06.10.2026). Geschrieben wird nur bei einer Änderung; leere Regeln ändern nichts. Gastgeber-, Übungs- und Weitergeben-Partien schreiben nichts. Der Platz zählt nicht zu den 12 Sätzen. Im Regel-Editor heißt er „Zuletzt gespielt bei <Gastgeber>“ und steht vorn. Muss der Gastgeber gehen, eröffnet ein anderer ohne Vorbereitung mit denselben Regeln: „Selbst eröffnen“ in der Leiste „Verbindung zum Gastgeber beendet.“ oder später der Knopf „Regeln von Lena“ (WLAN-Symbol, übernimmt sie) in der Gastgeber-Lobby.
    - `regelsatz_gewaehlt`: Name des zuletzt geladenen bzw. gespeicherten Satzes (Standard „“). Haben zwei Sätze dieselben Regeln, zeigen Editor, Regelzeile und Lobby überall diesen Namen. Eine Voreinstellung oder der Gastgeber-Platz heben die Wahl auf, Löschen des Satzes ebenso.
    - Prüfung beim Laden und Setzen: Regeln laufen immer durch `RuleConfig.from_dict(…).to_dict()`. Unbekannte Optionen fallen weg, ungültige Werte werden zum Standard bzw. begrenzt, und fehlende Optionen (Sätze einer älteren Version) bekommen den Standard. Einträge ohne Namen oder Regeln, Doppelte und alles über 12 fallen weg. Eine falsche Art (keine Liste bzw. Gastgeber ohne oder mit leeren Regeln) ergibt den Standard (leer).
    - Schreibfehler: Lässt sich die Einstellungsdatei nicht schreiben (z. B. Speicher voll), melden `RuleSets.save` (`ERR_WRITE`) und `remove` (false) das, und im Speicher bleibt der alte Stand. Der Speichern-Dialog sagt „Speichern hat nicht geklappt …“ und bleibt offen.
    - Gleich heißt gleiche Regeln. Ohne Kartentausch zählt die Tauschrichtung nicht, wie bei `RuleConfig.preset_name()`. Den passenden Namen zeigen der Regel-Editor (Hervorhebung, Übersicht „Gespeichert: …“) und die Regelzeile (`RulesBar.title`). Dabei gilt die Reihenfolge Voreinstellung, eigener Satz, Gastgeber-Platz, „Eigene Regeln“. Die Gast-Lobby zeigt fremde Regeln aus Sicht des Gastes: Voreinstellung, sonst ein passender eigener Satz, sonst „Regeln von <Gastgeber>“ (`JoinScreen.lobby_head`).
    - **Protokoll unverändert:** Der Gast bekommt die Regeln schon vollständig. `lobby.rules` und `view.rules` enthalten jeweils `RuleConfig.to_dict()`. Den Namen des Gastgebers liefern `lobby.players[host_id].name` bzw. `welcome.host_name`. Browser-Gäste können nicht eröffnen und speichern deshalb nichts.
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

- **06.10.2026, Zusammenführung der Hausregel-Oberflächen:**
  - Ohne „Spielbare Karten hervorheben“ zeigen App und Browser statt „Du bist dran – nichts passt, zieh eine Karte.“ nur „Du bist dran.“ (sonst verriete der Hinweis die Markierung). Nicht ausdrücklich beauftragt, Bestätigung des Nutzers steht aus.
  - Glücksspiel-Joker und Ablegen-Joker bekommen in der App auf der Ablage die Joker-Strahlen wie die übrigen Joker (`JokerRays.JOKERS`). Bestätigung steht aus.
  - Die Regie (`director.gd`) zählt Ereignisse ohne Animation (`quiet_events`, z. B. `turn`) nicht mehr zum Rückstand; dadurch läuft sie seltener im doppelten Tempo.
  - Gastgeber-Lobby: Die Schnellwahl der Voreinstellungen ist in den Regel-Editor gewandert (Knopf „Regeln“), damit fünf Spieler ganz sichtbar sind.
  - Spieltöne: KI-erzeugt (MOSS-SoundEffect v2.0) statt selbst synthetisiert; Pegel −12,5/−4,5 dB statt −16/−8 dB, im Browser 0,3/0,75 statt 0,2/0,5.
