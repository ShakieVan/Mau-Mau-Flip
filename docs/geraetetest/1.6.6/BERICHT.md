# Beta 1.6.6 – Furzkissen, kurzer Gerätetest (15.10.2026, 19:41–19:50)

APK `builds/MauMauFlip-1.6.6.apk` (43 682 516 Bytes, Bau 19:40) per `adb install -r` auf S21 (Gastgeber „S21“, Englisch) und S10 (Gast „Kim“, Deutsch); App-Daten behalten, beide melden `SfxPool: SoundPool bereit: 20 Töne`. Gesperrt (Testschalter `MauMauFlipTestLock` war schon `VERBOSE`, so belassen), Heim-WLAN, Bot „Minka“. Bilder: oben S21, unten S10.

## Ergebnis
1. **Kissen „Mit Namen“ S10 → S21:** Bestätigung „Kissen liegt bei S21.“ nur am S10, S21 zeigt nichts (g02). S21 legt Gelb 6 → am S21 Kissen plattgedrückt mit Wolke und „Pfffrt!“ links am eigenen Platz, am S10 Kissen am Platz S21 mit „Das warst du!“ (g03). Log: S21 (Ziel) `furzkissen` 0,60, S10 (Leger) `furzkissen` 0,15. Die Zeile „Kim war's!“ am S21 lag zwischen zwei Aufnahmen und ist nicht im Bild. Ein Strafzug (S21 zieht automatisch +1) löste das Kissen erwartungsgemäß nicht aus. Vibration nicht gemessen.
2. **Sperre:** Erneutes Legen ≈ 70 s nach dem Kissen → Gastgeber lehnt ab, „Das Kissen muss sich erst wieder aufpusten.“ Gleich nach einem Kissen (bei Minka) ist die Kissen-Zeile im Menü ausgegraut, mit diesem Hinweis (g04). Nach Ablauf der Spiegel-Mindestzeit (60 s) ist sie beim Gast wieder aktiv, obwohl der Gastgeber noch sperrt – so geplant (Restzeit geheim).
3. Keine SCRIPT ERROR auf beiden Geräten, Spiel lief weiter.

## Befund
- **F1 (mittel):** Zweimal (g01, und ein zweites Mal bei Minka) bewirkte der Tipp auf „Mit Namen“ nichts: Das Menü schloss sich, aber weder Bestätigung noch Ablehnung erschienen, und das Kissen pupste später nicht. In beiden Fällen lief gerade eine Überraschung über den Tisch (Katze auf dem Stapel bzw. Schmetterling). Ohne Überraschung ging es jedes Mal (zweimal). Vermutung: Die Überraschung oder der Spruch-Wechsel nimmt den Tipp ab bzw. schließt das Menü, bevor der Knopf auslöst. Nicht weiter untersucht.

## Ende
App auf beiden Geräten beendet (force-stop), Testschalter unverändert `VERBOSE`, keine Testdateien auf den Geräten.

| | |
|---|---|
| ![g01](g01.png) Tipp ohne Wirkung (Katze auf dem Stapel) | ![g02](g02.png) Bestätigung nur am S10 |
| ![g03](g03.png) Pups: S21 „Pfffrt!“, S10 „Das warst du!“ | ![g04](g04.png) Kissen ausgegraut |

## Nachtrag F1 (15.10.2026, ohne Testhandys)
**Ursache: kein Fehler der Überraschungen, sondern das Selbstschließen des Necken-Menüs nach 5 s ohne Tipp** (`TeaseFx.MENU_IDLE_S`, so festgelegt in eastereggs2.md Abschnitt 2). Alle Tipps kamen vom S10 („Kim“). Laut Protokoll des Testlaufs lagen zwischen dem Öffnen des Menüs (Tipp auf den Kopf) und dem Tipp auf „Mit Namen“ in beiden Fehlfällen etwa 12 s, weil dazwischen eine Aufnahme und ein eigener Befehl lagen (17:43:17 → 17:43:29 UTC, Ziel S21; 17:48:32 → 17:48:44 UTC, Ziel Minka). Das Menü war also schon zu, und der Tipp traf den leeren Tisch. In den gelungenen Fällen kam der Tipp 1,2 s nach dem Öffnen im selben Befehl. Die Katze in g01 lag außerdem nur am S21 (oben), nicht am tippenden S10. Dass beide Male eine Überraschung lief, war Zufall: Beide kommen nur, wenn lange nichts passiert.

**Vorrang geprüft:** Das Menü (`TeaseMenu`, `MOUSE_FILTER_STOP`, in `_overlay`) und die Reaktionsknöpfe liegen über dem Tisch. Katze und Schmetterling (`FunFx`) sind `Node2D` ohne eigene Eingabe; die Katze reagiert nur über `TableView._tap`, und dort kommt ein Tipp nur an, wenn kein Menü oder Knopf ihn abgenommen hat. Lite hat keine solchen Überraschungen (`spass.js` nur Sprüche), Menü und Reaktionsknöpfe liegen in der eigenen Ebene `#necken` (z-index 1050) über der Bühne. Keine Codeänderung nötig.

**Test:** `game/tests/test_ui_tease.gd` → `surprise_checks()`. Katze schläft auf dem Stapel und liegt jeweils genau unter dem getippten Knopf, der Schmetterling fliegt. Echte Tipps über den Viewport auf „Mit Namen“, „Geheim“, Papierkugel, Schnarchen, Wecker, „Karten ansehen“ und die 4 Reaktionen senden bzw. öffnen jeweils das Richtige, und die Katze bleibt liegen. Ohne Menü schiebt ein Tipp die Katze weiter weg. Nach 5 s ohne Tipp ist das Menü zu, und ein später Tipp auf „Mit Namen“ sendet nichts (der Gerätefall). Gegenprobe: Mit dem Menü ohne Eingabevorrang (`MOUSE_FILTER_IGNORE`, nur vorübergehend) wird der Test rot (unter anderem Kissen, „Karten ansehen“ und alle 4 Reaktionen), mit dem echten Stand grün (268 ok).

**Hinweis für spätere Gerätetests:** Tipp auf den Kopf und Tipp auf den Menüknopf in einem Befehl ausführen, höchstens etwa 4 s Abstand.

**Neu gebaut:** `tools/build.ps1 -Target Android` mit allen 105 Testskripten grün, `builds/MauMauFlip-1.6.6.apk` (43 682 516 Bytes, SHA-256 `369ce61521c096c6e62c851a5a74f084526f279fb0972b2612461afbb4cb73d1`). Die App selbst ist unverändert, nur der Test kam hinzu.
