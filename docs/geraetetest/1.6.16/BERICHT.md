# Beta 1.6.16 – Raum behalten, Joker ohne Farbfelder, Stift, Glücksspiel-Treffer: Gerätetest (25.10.2026, 17:03–17:13)

Geprüfter Bau `builds/MauMauFlip-1.6.16.apk` (alle 114 Testskripte grün, `-Parallel 4`) per `adb install -r` auf S21 (Gastgeber „S21“, Englisch) und S10 (App-Gast „Kim“, Deutsch); App-Daten behalten. Beide Handys entsperrt, Heim-WLAN, Testschalter `MauMauFlipTestLock` nicht verändert (`INFO`). Online über den echten Vermittler `mau-mau-flip-relay.shakie.workers.dev`.

## Ergebnis
1. **Gast verlässt die Partie (online, Raum GECKO-95):** Kim tritt per App-Link `maumauflip://join?r=GECKO-95` bei, die Partie startet. Kim tippt Zurück → „Verlassen“: Das Hauptmenü zeigt oben **„Zurück ins Spiel · GECKO-95 · bei S21 · vor 1 min“** mit „Nicht mehr anzeigen“ (g01). Am S21 währenddessen „Kim is disconnected“ mit „Computer takes over“/„Remove from game“. Tipp auf „Zurück ins Spiel“ → Kim sitzt wieder auf seinem Platz, gleiche 7 Karten, weiter am Zug.
2. **Gastgeber verlässt die Partie:** „Leave the game?“ zeigt „If you host again soon, the room code GECKO-95 stays the same.“ (g02). Nach „Leave“: Protokoll `[Raumhalter] Raum GECKO-95 bleibt bis zu 30 min erhalten`; Kim bekommt „Verbindung zum Gastgeber beendet.“, das Hauptmenü zeigt wieder „Zurück ins Spiel“.
3. **Warten und gleicher Code:** Kim tippt „Zurück ins Spiel“, bevor S21 neu eröffnet → Beitrittsseite „Verbinde …“. S21 eröffnet neu: Die Lobby öffnet von selbst den Weg „Online (internet)“ mit **GECKO-95** und „Same room code as before – waiting for players …“ (g03); Kim landet ohne weiteren Tipp in der neuen Lobby.
4. **Joker ziehen (S21, Übungsspiel „Family“):** Wünscher +2 mit `input motionevent` nach oben gezogen und unterwegs angehalten: **keine Farbfelder** um die Ablage, nur die gezogene Karte (g04). Loslassen → Farbrad; Tipp daneben → Joker zurück in der Hand.
5. **Stift-Doppeltipp:** zweimal `input stylus tap` auf den Joker (erster Tipp hebt an, zweiter legt) → **Farbrad bleibt offen** (2,5 s später noch da, g05). Stifttipp auf Grün → Joker mit Grün gelegt, der Nächste zieht 2.
6. **Glücksspiel-Treffer:** Regeln → Customize, „Family“: neue Zeile „Gamble hits“ unter „Gamble“ mit „Rare (up to 1:10)“, „Medium (up to 1:5)“ (gewählt), „Often (up to 1:3)“ (g06).

## Nicht geprüft
- **Verlorene Aktion** (Karte kommt nicht beim Gastgeber an): am Gerät nicht nachstellbar, ohne die adb-Verbindung (WLAN) des Gasts zu kappen; deckt `test_net_act_lost` ab.
- **Kontern** (Wartender setzt nur aus, wenn der Leger dran bleibt) nur automatisch (`test_rules_counter`, Nutzerfall nachgestellt).
- Lite/Browser und iPhone, App-Neustart des Gastgebers innerhalb der Vermittler-Frist (Datei `eigener_raum.json`).

## Kleinigkeit
- Während Kim auf den neu eröffnenden Gastgeber wartete, stand auf der Beitrittsseite „Verbinde …“ statt „Gastgeber kurz weg – warte …“. Das Beitreten klappte von selbst; niedrig.

## Ende
App auf beiden Geräten beendet (force-stop), S21-Regeln wieder „Official“ (für den Test kurz „Family“), Testschalter `INFO`, Heim-WLAN nie gewechselt, kein Neustart. Am S10 zeigt das Hauptmenü noch „Zurück ins Spiel“ (verschwindet, sobald der Raum weg ist). Bilder per `exec-out`, keine Dateien auf den Geräten.

| | |
|---|---|
| ![g01](g01.jpg) „Zurück ins Spiel“ im Hauptmenü (S10) | ![g02](g02.jpg) Hinweis beim Verlassen: gleicher Raumcode (S21) |
| ![g03](g03.jpg) Neue Lobby mit demselben Code (S21) | ![g04](g04.jpg) Joker ziehen ohne Farbfelder (S21) |
| ![g05](g05.jpg) Farbrad nach Stift-Doppeltipp bleibt offen | ![g06](g06.jpg) Hausregel „Gamble hits“ |
