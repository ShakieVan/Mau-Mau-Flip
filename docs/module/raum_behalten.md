# Raum behalten (Beta 1.6.16)

Nutzerwunsch vom 25.10.2026: „Wenn man aus einem Online-Spiel (kurz) herausgeht, wäre es schön, wenn der Raumcode erhalten bleibt und
man wieder einfach dazustoßen kann.“ Auf Rückfrage: für **Gastgeber und Gast**.

Ohne Änderung am Vermittler (`relay/`): Der Nutzer müsste sie sonst in seine Worker-Kopie nachziehen. Es gelten dessen Grenzen:
Ein Raum lebt höchstens 24 h ab dem Anlegen (`life_s`), ohne angemeldeten Gastgeber noch 10 min (`grace_s`), dann ist der Code weg.

## 1. Bisher

- **Gast:** Der Raumcode stand schon auf der Beitrittsseite (`letzter_raum`, seit 1.3.3), das Platz-Token je Raum in
  `user://netz_token.json`, und der Gastgeber hält den Platz eines getrennten Gasts frei. Nach „Partie verlassen“ ging es aber nur über
  Hauptmenü → Mit anderen spielen → Beitreten → Beitreten zurück; „Partie fortsetzen“ gibt es nach eigenem Verlassen nicht (die
  Sicherung wird gelöscht).
- **Gastgeber:** „Partie verlassen“ und „Lobby schließen“ (`HostTable.leave`) schickten `{k:"end"}`: Der Code war sofort frei, die
  nächste Lobby bekam einen neuen, und alle mussten den neuen Code bekommen.

## 2. Gastgeber: Raumhalter (`game/scripts/net/room_keeper.gd`)

- `HostTable.leave()` beendet den Online-Raum nicht mehr. Die Online-Gäste bekommen wie bisher „bye“ („Der Gastgeber hat das Spiel
  beendet.“), der Vermittler-Anschluss (`NetRelayHost`, Socket bleibt offen) geht über `NetHostSession.detach_online` an den
  **RoomKeeper** (`RoomKeeper.keep`). Er hält den Raum **höchstens 30 min** (`KEEP_S`), danach `{k:"end"}`.
- **Neue Lobby:** `InvitePanel.reopen_kept_room` holt den Raum sofort zurück (`HostTable.open_online` → `RoomKeeper.take` →
  `NetHostSession.adopt_online`, ohne Neuverbinden), zeigt den Weg „Online (Internet)“ und „Gleicher Raumcode wie vorhin – warte auf
  Mitspieler …“. Nur mit demselben Vermittler und mindestens 3 h Restlaufzeit (`MIN_LIFE_S`); sonst endet der alte Raum und es gibt
  einen neuen. „Online schließen“ beendet den Raum wie bisher ausdrücklich.
- **Wer in der Zwischenzeit kommt:**
  - Gäste mit einer **Sicherung der beendeten Partie** (`hello.bk_gid` = gid der Partie oder `hello.bk_token` eines ihrer Plätze)
    bekommen „bye“. Das betrifft Gäste, die beim Verlassen gerade nicht verbunden waren: Ohne „bye“ sähen sie 4503 und ihr
    HostSwitch übernähme nach T_SILENT den verlassenen Raum mit der alten Partie. So löschen sie ihre Sicherung wie alle anderen.
  - Alle anderen (App ohne Sicherung, Browser) bekommen **4503** („Gastgeber kurz weg“): Sie versuchen es alle 10 s erneut und landen
    von selbst in der neuen Lobby, sobald der Gastgeber wieder eröffnet. Gäste ohne hello nach 10 s ebenfalls 4503.
- **App beendet:** Der Halter schreibt `user://eigener_raum.json` (`relay, room, token, max_c, created_unix, seen_unix, gid`, Lebenszeichen
  jede Minute). Ohne laufenden Halter gilt die Datei bis 9 min nach dem letzten Lebenszeichen (`REUSE_GRACE_S`, unter `grace_s`); die
  neue Lobby holt den Raum dann per `open_online_kept` (`open_existing`) zurück. Ist er doch weg (4404) oder gilt das Token nicht
  (4403), öffnet `NetHostSession.poll` sofort einen neuen Raum. In diesem Fenster gibt es keinen Halter, der alten Gästen „bye“ sagt;
  übernimmt einer, verdrängt ihn die neue Lobby beim Zurückholen (4000), sein Tisch tritt ab und meldet sich als Gast an.
- Raum weg (`failed`), von einem anderen Gerät übernommen (`stepped_down`) oder geschlossen: Der Halter vergisst ihn (in `pump`, nie
  mitten im Signal des Anschlusses). Bricht die Verbindung ab, meldet er sich ohne Probe wieder an (`needs_check` ohne Empfänger →
  `claim`).
- Hinweis in „Partie verlassen?“ und „Lobby schließen?“: „Eröffnest du gleich wieder ein Spiel, gilt derselbe Raumcode %s.“
  (`HostTable.keepable_room`).
- Nur in der App eingeschaltet (`RoomKeeper.enabled`, `App._init`); Testläufe schalten es selbst ein.

## 3. Gast: „Zurück ins Spiel“ (`game/scripts/ui/screens/guest_return.gd`)

- Gemerkt (`zurueck_ins_spiel` = `{room, relay, host, t}`) wird, wenn ein App-Gast ein **Online**-Spiel verlässt (Tisch: „Partie
  verlassen“; Gast-Lobby: Zurück bzw. Seite verlassen) oder der Gastgeber „bye“ schickt. Nicht bei Herausgenommenen.
- Das Hauptmenü zeigt an der Stelle von „Partie fortsetzen“ **„Zurück ins Spiel“** mit „KATZE-42 · bei Lena · vor 3 min“ und
  „Nicht mehr anzeigen“. „Partie fortsetzen“ geht vor (nie beide). Beim Anzeigen fragt das Menü `/info?room=`; ist der Raum weg,
  verschwindet die Zeile. Höchstens 3 h (`MAX_AGE_S`).
- Ein Tipp öffnet die Beitrittsseite direkt für diesen Raum (wie ein App-Link). Mit dem gemerkten Token sitzt der Gast wieder auf seinem
  Platz; hat der Gastgeber mit demselben Code neu eröffnet, kommt er in die neue Lobby; ist der Gastgeber gerade weg, wartet die Seite
  mit „Gastgeber kurz weg – warte …“ und tritt von selbst bei.
- Vergessen beim nächsten Beitritt (welcome), beim Eröffnen eines eigenen Spiels und mit „Nicht mehr anzeigen“.
- Gemerkt wird nur in der App (`GuestReturn.enabled`, `App._init`); Testläufe schreiben so nicht in die echte Einstellungsdatei.
- Fortsetzen aus dem Hauptmenü mit alter Sicherung, während der Gastgeber nur noch den Raum hält: „bye“ → „Der Gastgeber hat das
  Spiel beendet.“ ohne „In neuem Raum fortsetzen“ (`HostSwitch._poll_resume`).

## 4. Browser (Lite)

Der Raum steckt im Link (`?r=CODE`), das Token im Browser-Speicher: Neu laden bzw. „Zur Startseite“ tritt wieder bei, bei 4503 versucht
es die Startseite alle 10 s erneut. Neu ist nur der Hinweis nach „bye“ eines Online-Gastgebers: „Eröffnet der Gastgeber gleich wieder
ein Spiel, kommst du über „Zur Startseite“ mit demselben Raumcode wieder hinein.“

## 5. Grenzen

- Der Gastgeber hält den Raum nur, solange die App läuft (höchstens 30 min); ohne laufende App hält ihn der Vermittler noch 10 min.
- Ein Raum lebt höchstens 24 h ab dem Anlegen; mit weniger als 3 h Rest gibt es beim Wiedereröffnen einen neuen Code.
- Gäste, die der Gastgeber mit „bye“ verabschiedet hat, kommen nicht automatisch zurück – über „Zurück ins Spiel“ bzw. „Zur Startseite“
  geht es mit einem Tipp.

## 6. Tests und Bilder

- `game/tests/test_room_keeper.gd` (Vermittler-Nachbau): Einheiten, Ablauf (bye an Gäste mit Sicherung, 4503 für neue Gäste, neue Lobby
  mit gleichem Code, wartende Gäste kommen von selbst hinein), Datei (Zurückholen, abgelaufener Raum → neuer Code), Höchstdauer.
- `game/tests/test_main_menu_fit.gd`: „Zurück ins Spiel“ in allen Formaten, Schriftstufen und Sprachen; „Partie fortsetzen“ geht vor.
- Kontrollbilder `game/tests/test_raum_behalten_shot.gd` → `docs/module/optik_1616_menue_zurueck.jpg`,
  `optik_1616_lobby_gleicher_code.jpg`, `optik_1616_lobby_schliessen.jpg`.
