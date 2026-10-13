# Beta 1.6.1 – Gastgeber-Übergabe online, Gerätetest Runde 1 und Nachtest (13.10.2026)

Ablauf nach `docs/module/uebergabe.md` Abschnitt 7 („Gerätetest S21/S10, gesperrt“). Beide Handys gesperrt, Testschalter `MauMauFlipTestLock`, Bedienung per `input tap`, Belege per `screencap`/`screenrecord` und logcat. Echter Standard-Vermittler (`mau-mau-flip-relay.shakie.workers.dev`), kein Browser, kein `/c/1.6.1/`.

## Bau
- APK `builds/MauMauFlip-1.6.1.apk`, SHA-256 c69c0a0a7441b3ce2ba53979a4b99d51b8f76786b5a76fd6e6a6cdce7be244ae (Bau 13.10. 10:22, Tests aus dem Cache). Per `adb install -r` auf S21 (Android 15, Englisch) und S10 (Android 12, Deutsch); die App meldet beim Start dieselbe Prüfsumme.

## 1. Online-Partie
- S21 „S21“ eröffnet online, Raum KNOPF-34 (01). S10 „Kim“ tritt per Raumcode als App-Gast bei, dazu Bot „Minka“. Familie, Tag.
- Einige Züge auf beiden Seiten (Legen, Ziehen); Anzeigen auf beiden Geräten gleich.

## 2. Andere App (HOME am S21, 10:28:53)
- S10: oben „Gastgeber kurz weg – warte …“, bei S21 „kurz in einer anderen App“, bei 12, 60, 90, 120, 150 und 175 s unverändert, keine Übernahme (02, 03).
- Nach ≈ 181 s (10:31:54, logcat S10: `keepScreenOn=true`, Ton „dran“) übernimmt S10 wie vorgesehen (`T_AWAY` = 180 s). Bei 192 s ist S10 Gastgeber, S21 „getrennt“ mit „Computer übernimmt“/„Aus dem Spiel nehmen“ (04). Hand von Kim (7 Karten) unverändert.
- S21 per `am start` zurück (10:32:37): sofort „You keep playing as a guest. Kim is the host.“, eigene Hand (6 Karten) unverändert, Partie läuft weiter (05). Kein doppelter Gastgeber, kein „Raum beendet“.

## 5. Geplante Übergabe (vorgezogen, S10 → S21)
- S10 (jetzt Gastgeber) ☰ → „Gastgeber übergeben …“ → Dialog mit S21 → „Übergeben“ (06).
- S21 nach ≈ 1,5 s: „You are the host now. Please keep the app open.“ und „S21 is the host now.“ (07); S10 kurz „Du spielst jetzt als Gast weiter. Gastgeber ist S21.“ und spielt als Gast weiter. Hände unverändert, weitere Züge auf beiden Seiten.

## 3. Ausfall (`am force-stop` am S21-Gastgeber, 10:35:19)
- Vorher: Kim 5 Karten (rot 4/6/8, gelb 4, blau 9), S21 4, Minka 2 (08).
- S10 zeigt bis zur Übernahme „Gastgeber kurz weg – warte …“ (09). Ein Countdown „Du übernimmst in %d s“ erscheint nicht: S10 ist einziger Erbe (Rang 0), die Wartezeit ist 0 – passt zum Entwurf.
- Übernahme nach ≈ 42 s (10:36:01; Bild bei 44 s mitten im Wechsel mit „Du bist jetzt Gastgeber. Bitte lass die App offen.“) (10). Danach ist S10 Gastgeber, S21 „getrennt“ mit „Computer übernimmt“/„Aus dem Spiel nehmen“, Hände unverändert (11). Bot Minka spielt weiter (legt, ruft „Mau!“).

## 4. Rückkehr (`am start` am S21) – Fehler
- Hauptmenü bietet „Continue game – Kim, Minka · Round 1 · 3 min ago“ und „Discard game“ (12).
- Tipp auf „Continue game“: Rückfrage „Connecting to the others …“ steht ≈ 0,3 s, dann wieder das Hauptmenü mit „Continue game“ – kein Tisch (13, Bildfolge 8 fps aus `screenrecord`). Fünfmal versucht (10:37:38, 10:38:01, 10:39:23, 10:41:54, 10:45:33), immer gleich.
- Gleichzeitig am S10: „S21 ist wieder da.“ und sofort „S21 ist getrennt.“ (14). S21 wird also angenommen (welcome), die Verbindung geht aber gleich wieder zu.
- Nachdem S10 die Partie verlassen hatte, meldet „Continue game“ korrekt „The online room has expired …“ mit „Discard game“ (15); verworfen.
- Ursache siehe Fehler F1. Damit ist „Rückkehr als Gast über das Hauptmenü“ nicht bestanden; die Rückkehr als Gast nach dem Abtreten (Schritt 2) funktioniert.

## 6. Spiel-WLAN-Erlaubnis am S10 (Android 12)
- Ausgangszustand: ACCESS_FINE_LOCATION und ACCESS_COARSE_LOCATION `granted=false` (schon vor dem Test).
- WLAN-Lobby → „Lieber eigenes Spiel-WLAN“: System-Dialog „Mau-Mau Flip erlauben, den Gerätestandort abzurufen?“ mit **Genau/Ungefähr** und „Bei Nutzung der App“ erscheint über der Sperre (16). Die Wahl Genau/Ungefähr zeigt Android 12 nur, wenn FINE und COARSE zusammen angefragt werden – die Anfrage enthält also beide Rechte (logcat: `START u0 {act=android.content.pm.action.REQUEST_PERMISSIONS … GrantPermissionsActivity}` aus uid 10198 = Mau-Mau Flip, 10:47:23).
- Bedienen gesperrt nicht möglich: Tipp auf „Bei Nutzung der App“ öffnet den Entsperr-Bildschirm (`mCurrentFocus=Bouncer`); nicht entsperrt, mit Zurück abgebrochen. Die App zeigt danach „Erlaubnis fehlt … Neu öffnen / Zurück“ (17).
- `pm grant` für beide Rechte, „Neu öffnen“: Spiel-WLAN geht auf (AndroidShare_…, `swlan0` 192.168.178.254/24), WLAN-QR, Name/Passwort und Hinweis „Mobile Daten kurz ausschalten …“ sichtbar, Spiel-QR mit 192.168.178.254:24690 (18). „Spiel-WLAN schließen“: `swlan0` weg, S10 weiter im Heim-WLAN.
- Rechte danach per `pm revoke` zurück auf den Ausgangszustand (beide `granted=false`, Flags wie vorher).

## Fehler
- **F1 (hoch) – „Partie fortsetzen“ als Gast öffnet keinen Tisch.** Beleg: 12–14, fünf Versuche. Vermutete Ursache: `HostSwitch._finish_guest()` (`game/scripts/game/host_switch.gd:689`) ruft `_move_to(ct)` → `attach(ct)`, und `attach` setzt für einen ClientTable `_go("off")` (Zeile 140) – das Signal `state_changed("off")` kommt **vor** `swapped`. Das Hauptmenü hält `"off"` für einen Abbruch (`game/scripts/ui/screens/main_menu.gd:288`: `_close_resume_box(); _end_resume()`), löst dabei alle Signale des HostSwitch und bekommt `swapped` nicht mehr. Der ClientTable hängt ohne Elternknoten (HostSwitch als sein Kind), `NetClient._close_if_detached` schließt die Verbindung am Ende des Frames → am Gastgeber „wieder da“/„getrennt“. Der Gastgeber-Weg (`_finish_take` → `attach` → `_go("host")`) ist nicht betroffen. Der Test `test_ui_handover.gd` (Abschnitt Hauptmenü) sendet `swapped` direkt und deckt die Reihenfolge `state_changed("off")` → `swapped` nicht ab. Lösung z. B.: in `_on_resume_state` „off“ nur werten, wenn der HostSwitch noch Kind des Hauptmenüs ist (bzw. `source == null`), oder `swapped` vor dem Zustandswechsel senden.
  - **Behoben (13.10.2026):** `MainMenuScreen._on_resume_state` wertet „off“ nur noch als Abbruch, solange der HostSwitch am Hauptmenü hängt; ist er mit dem Gast-Tisch umgezogen, folgt `swapped` und der Tisch kommt obenauf. Test `test_ui_handover.gd` fährt jetzt den echten Weg (`_finish_guest` mit „off“ vor `swapped`) und prüft zusätzlich, dass „Abbrechen“ den Ablauf weiter beendet (ohne Korrektur: FAIL „Tisch kommt obenauf“). **Am Gerät bestätigt** im Nachtest (siehe unten, n10–n12).

## Beobachtungen (kein Fehler)
- Bei einem einzigen Erben (Rang 0) sieht der Gast nach einem Ausfall 40 s lang nur „Gastgeber kurz weg – warte …“, nie „Gastgeber antwortet nicht …“ mit Countdown. Entspricht dem Entwurf, für den Nutzer aber ohne Hinweis, dass gleich übernommen wird.
- Der Netzprotokoll-Mitschnitt (`netz.log`) ist in der Release-APK nicht per `run-as` lesbar; „kein doppelter Gastgeber“ ist daher nur über die Bildschirme belegt (nie zwei Gastgeber-Meldungen, kein „Raum beendet“).
- Die Systemdialoge der Standort-Erlaubnis lassen sich gesperrt anzeigen, aber nicht bestätigen (Entsperr-Bildschirm).

## Nicht geprüft
- Rückkehr als Gast über „Partie fortsetzen“ mit anschließender Übergabe zurück (wegen F1). Die geplante Übergabe S10 → S21 lief stattdessen vor dem Ausfall.
- Still toter Gastgeber, Doppel-Gastgeber, Tiefschlaf-Uhr (nur automatisch, siehe Testplan).

## Ausgangszustand
- Beide Handys im Heim-WLAN „Siemens-Router1“, Mau-Mau Flip beendet (force-stop), Testschalter `log.tag.MauMauFlipTestLock` = VERBOSE (so vorgefunden), Standort-Rechte am S10 wie vorher (beide aus). Eigene Bildschirmaufnahmen (`/sdcard/mmf_test_rec*.mp4`) gelöscht; ältere Dateien `/sdcard/mmf*.png`/`mmf_rec.mp4` (06./08.10.) stammen aus früheren Tests und blieben liegen.
- Spieldaten: S21-Partiedatei nach „Raum abgelaufen“ über „Discard game“ verworfen; S10 hat die Partie verlassen. Keine App-Daten gelöscht.

# Nachtest (13.10.2026, 11:16–11:34)

Nach der Korrektur von F1. Gleicher Aufbau wie Runde 1 (beide Handys gesperrt, Testschalter, `input tap`, `screencap`, logcat). Bilder `n01`–`n15` (960 px breit).

## Bau
- APK `builds/MauMauFlip-1.6.1.apk`, 42 472 347 Bytes, SHA-256 eac645badbd99a6d2cd43dc996927cddc38df88540626f726b6e9eb0651191a6 (versionCode 1006001, alle 85 Testläufe grün). Per `adb install -r` auf S21 und S10; beide melden beim Start dieselbe Prüfsumme (logcat `Eigene APK: …`). App-Daten nicht gelöscht.

## 1. Online-Partie – bestanden
- S21 eröffnet online über den Standard-Vermittler, Raum **MITTAG-96** (n01). S10 „Kim“ tritt per Raumcode als App-Gast bei, dazu Bot „Minka“. Familie.
- Züge auf beiden Seiten (Legen, Ziehen, Farbwahl); beide Geräte zeigen denselben Stand.

## 2. Andere App (HOME am S21, 11:21:03) – bestanden
- S10: „Gastgeber kurz weg – warte …“, bei S21 „kurz in einer anderen App“; bei 13 s, 64 s (n02) und 180 s (n03) unverändert, keine Übernahme.
- Übernahme nach **181 s** (logcat S10 11:24:04.3 `keepScreenOn=true`, Ton „dran“). Bei 196 s ist S10 Gastgeber, S21 „getrennt“ mit „Computer übernimmt“/„Aus dem Spiel nehmen“ (n04). Hände unverändert (Kim 4, S21 5, Minka 4).
- S21 per `am start` zurück (11:24:43): „You keep playing as a guest. Kim is the host.“, eigene Hand (5 Karten) unverändert (n05). Weitere Züge auf beiden Seiten.

## 5. Geplante Übergabe S10 → S21 (vor dem Ausfall) – bestanden
- S10 ☰ → „Gastgeber übergeben …“ → S21 → „Übergeben“ (11:26:17). Nach ≈ 2 s am S21 „You are the host now. Please keep the app open.“ und „S21 is the host now.“ (n06), am S10 „Du spielst jetzt als Gast weiter. Gastgeber ist S21.“. Hände unverändert, weitere Züge.

## 3. Ausfall (`am force-stop` am S21-Gastgeber, 11:27:12) – bestanden
- Vorher: Kim 3 (Türkis 3, Türkis 3, Lila 6), S21 3 (Lila 2, Lila 8, Joker), Minka 2 (n07 S10/S21).
- S10 zeigt „Gastgeber kurz weg – warte …“ (bei 38 s noch, n08). Übernahme nach **≈ 41 s** (logcat S10 11:27:53.7 `keepScreenOn=true`); Bild bei 44 s: „Du bist jetzt Gastgeber. Bitte lass die App offen.“ und „Kim führt das Spiel weiter (Gastgeber war weg).“, S21 „getrennt“ mit Sofort-Leiste (n09). Hände unverändert (Kim 3, S21 3, Minka 2).
- Kim zieht und legt einen Joker (Türkis), Bot Minka spielt danach weiter (legt +1, ruft „Mau!“).

## 4. Rückkehr über „Partie fortsetzen“ – bestanden (F1 behoben)
- `am start` am S21 (11:29:23) → Hauptmenü „Continue game – Kim, Minka · Round 1 · 3 min ago“ (n10).
- Tipp (11:29:39.8): „Continue game – Connecting to the others …“ (n11), nach ≤ 3 s steht der Tisch: S21 ist Gast auf seinem Platz, Hand unverändert (Lila 2, Lila 8, Joker), Minka inzwischen 1 Karte (n12). Am S10 bleibt S21 verbunden („gleich dran“, kein „getrennt“, n12 S10); auch 8 s und 30 s später unverändert.
- S21 zieht als Gast (Karte passt → „Behalten“), Kim legt weiter – die Partie läuft.
- Kein doppelter Gastgeber (nur ein Gerät meldet je Wechsel „Du bist jetzt Gastgeber“), kein „Raum beendet“.

## 5. Geplante Übergabe nach der Rückkehr (S10 → S21) – bestanden
- Am S10 (Gastgeber) ☰ → „Gastgeber übergeben …“ → S21 → „Übergeben“ (11:30:55, n13). S21: „You are the host now …“/„S21 is the host now.“ (n14 S21); S10: „Du spielst jetzt als Gast weiter. Gastgeber ist S21.“ (n14 S10).
- Danach weitere Züge: Kim legt Türkis 3 mit „Mau!“, S21 legt Türkis-Richtungswechsel und Grün +1, ein Flip wendet den Tisch auf die Tagseite, Minka zieht/legt. Beide Geräte gleich.
- Abschluss: S21 „Leave“ → S10 zeigt „Verbindung zum Gastgeber beendet.“ (n15); beide Hauptmenüs danach ohne „Partie fortsetzen“.

## 6. Spiel-WLAN-Erlaubnis
- Nicht wiederholt (in Runde 1 bestanden, von der Korrektur nicht berührt). Standort-Rechte am S10 unverändert (beide `granted=false`).

## Logcat
- Keine Zeilen `E/godot`, `SCRIPT ERROR` oder `USER ERROR`, kein Absturz (`FATAL`) auf beiden Geräten.

## Fehler im Nachtest
- Keine neuen Fehler im Ablauf 1–5.

## Beobachtung (niedrig, vermutlich älter als 1.6.1)
- **Leiste „Verbindung zum Gastgeber beendet.“ am S10 links abgeschnitten** (n15): Mit „Selbst eröffnen“, „Gespeichert: „Von Spieler 85““ und „Zum Menü“ ist die Zeile breiter als der Bildschirm (S10, Deutsch, 2280 px), Überschrift und Untertitel beginnen außerhalb („…erbindung zum Gastgeber beendet.“). Vermutete Ursache: `game/scripts/ui/table_screen.gd` ≈ Zeile 223–262 (`_conn`: HBox ohne Umbruch/Verkleinerung, Breite nur über `_conn.reset_size()` und Zentrieren in `_layout()` Zeile 337–338 → negative x-Position). Lösung z. B. Knöpfe in eine zweite Zeile oder Schrift verkleinern, wenn `_conn.size.x > sz.x - 32`.

## Ausgangszustand nach dem Nachtest
- Beide Handys im Heim-WLAN „Siemens-Router1“, Mau-Mau Flip beendet (force-stop), Testschalter `log.tag.MauMauFlipTestLock` = VERBOSE (so vorgefunden), Standort-Rechte am S10 unverändert. Bildschirmfotos nur per `exec-out` geholt, keine neuen Dateien auf den Geräten; die alten `/sdcard/mmf*` (06./08.10.) blieben liegen. Keine Partie offen (S21 hat die Partie verlassen).
