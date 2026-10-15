# Beta 1.6.3 – Necken (Easter Eggs Teil 2), Gerätetest Runde 1 (15.10.2026, 08:44–09:15)

Plan nach `docs/module/eastereggs2.md` 9 („Gerätetest“). Beide Handys gesperrt, Testschalter `MauMauFlipTestLock` (war schon `VERBOSE`), Bedienung per `input tap`/`swipe`, Belege per `screencap` (exec-out, für Zeitreihen per Schleife auf dem S10) und logcat (`godot`, `SfxPool:`), Vibration per `dumpsys vibrator_manager`. Kein Browser, kein `/c/1.6.3/`. Bilder 960 px breit, auf 256 Farben verkleinert; Bilder mit zwei Hälften: oben S21 (Englisch, Gastgeber), unten S10 „Kim“ (Deutsch, Gast), sofern nicht anders angegeben.

Hinweis zu den Ton-Belegen: `SfxPool` schreibt seine Zeile „Ton … Lautstärke …“ höchstens einmal je Sekunde (`DIAG_EVERY_MS`). Jede Neck-Aktion wurde deshalb einzeln mit frischem logcat geprüft; bei Serien (Dauerfeuer) zählt das Log nicht jeden Ton. Lautstärke 0,60 = normal (Spieltöne „Normal“), 0,15 = −12 dB (leise).

## Bau
- APK `builds/MauMauFlip-1.6.3.apk`, 43 276 623 Bytes, SHA-256 46202a065b8ffc8071acad79384d62c93447e0a2e819f4dbf655b44f90002fd5 (versionCode 1006003, Bau 15.10. 08:44, Tests gelaufen). Per `adb install -r` auf S21 (Android 15) und S10 (Android 12); beide melden beim Start dieselbe Prüfsumme (logcat `Eigene APK: …`) und `SfxPool: SoundPool bereit: 19 Töne`. App-Daten nicht gelöscht.

## A. Heim-WLAN (S21 Gastgeber, S10 Gast „Kim“, Bot „Minka“) – bestanden bis auf F1/F2
- **Papierkugel S10 → S21** (Kopf antippen → Menü „S21 · 7 Karten“ → Papierkugel): Flugbahn quer über den Tisch auf beiden Geräten, am S21 liegt die Kugel links neben dem Avatar mit „Paper ball from Kim!“ (a01, a02). Log: S10 `papier_wurf` 0,60, S21 `papier_plopp` 0,60; S21 vibriert 57 ms (`dumpsys`: 08:49:30.372, Step 40 ms + Rampe).
- **Papierkugel S10 → Minka (Bot)**: Flug und Treffer mit „Mpf!“ auf beiden Geräten (a03, a04). Log: S10 `papier_wurf` 0,60, S21 (Zuschauer) `papier_plopp` 0,15 (leise) – wie geplant.
- **Reaktionen:** Fächer am eigenen Platz (a05). Kim 😂 → am S10 und S21 am Platz Kim, Ton `lachen` 0,60 auf beiden (a06). S21 👏 → auf beiden am Platz S21, `klatschen` 0,60 auf beiden (a08). Online zusätzlich 👍 (b04).
- **Dauerfeuer:** 5 Reaktionen in ≈ 2,5 s vom S10. Nach der dritten sind die Reaktionen im wieder geöffneten Fächer blass (a07 links); ein Tipp auf eine blasse Reaktion schickt nichts, der Fächer bleibt offen (a07 rechts, ≈ 0,2 s später schon wieder farbig, Eimer +1 je 3 s). Am S21 kam nur an, was angenommen wurde.
- **Schnarchen/Wecker vor 10 s:** S21 am Zug, nach ≈ 4 s Kopf-Tipp am S10: Schnarchen und Wecker blass, darunter „Erst, wenn S21 eine Weile überlegt.“ (a09).
- **Schnarchen nach > 10 s (S10 → S21):** Z-Wolke und Schlafmütze am S21-Platz auf beiden Geräten, am S21 „Kim thinks you're about to fall asleep.“-Zeile über dem Namensschild (a10, a11). Log: S21 `schnarchen` 0,60 (Ziel), S10 `schnarchen` 0,15 (Absender leise).
- **Wecker (S10 → S21, gleicher Zug):** Wecker hüpft, tickt (a12), klingelt nach 3 s (a13; am S10 springt die Mau-Katze vom Stapel). Log: S21 `wecker` 0,60, S10 `wecker` 0,15. **Vibration am S21: 3 × 250 ms** (`dumpsys`: 08:55:38.389, 38.806, 39.205, je „Step=250ms(amplitude=0,60)“).
- **Wecker abstellen:** Neuer Zug von S21, nach > 10 s Wecker vom S10, S21 legt nach ≈ 1 s (Grün 9). Am S10 kippt der Wecker um, kein Klingeln (a14 unten). Am S21 „Just in time!“ – überlappt aber die Zeile „Kim set an alarm clock for you!“ (a15, **F1**). Log: kein `wecker` auf beiden Geräten (nur `karte`), keine Vibration im Fenster.
- **Gastgeber neckt Gast (S21 → Kim):** Schnarchen und Wecker vom S21 (Gastgeber über `send_fx`): Bild auf beiden (a18, a19), Log S10 (Ziel) `schnarchen`/`wecker` 0,60, S21 (Absender) 0,15. Am S10 keine Vibration – dort ist „Vibration“ in den Einstellungen aus (so vorgefunden), also richtig. Papierkugel S21 → Kim: am S10 Treffer mit „Papierkugel von S21!“, Kugel liegt ≈ 3 s und blendet aus (Zeitreihe 1,4 s-Raster).
- **Necken aus am S21** (☰ → Settings → „Teasing (paper ball, snoring, alarm clock, reactions)“ aus): Am S10 zeigt das Menü am S21-Kopf nur noch „Karten ansehen“ und „S21 möchte gerade nicht geneckt werden.“ (a16). Eine Reaktion von Kim erscheint am S10, am S21 nichts (weder Bild noch Ton, logcat S21 leer; a17). Am S21 ist der Reaktionsknopf weg, Kopf-Tipp öffnet wie früher die Rückseiten. Wieder an: Menü am S10 wieder mit Papierkugel (Schnarchen/Wecker fehlen, weil S21 nicht am Zug war).
- **Spiel unbeeinträchtigt:** Ziehen, Behalten, Legen (auch gezogene Karte), Wünscher +2 mit Farbrad, Richtungswechsel, Bot-Züge, „Erwischt!“-Knopf erscheint am S10 neben S21 (S21 legt die vorletzte Karte ohne „Mau!“), Rundenende mit Konfetti, Reaktion am Rundenende über der Tafel (a21), „Nächste Runde“.

## B. Online über den echten Vermittler (S21 Raum TAU-53, S10 per Raumcode) – bestanden
- Schnarchen S21 → Kim (b01), Papierkugel S21 → Kim mit Flug am S21, Treffer und „Papierkugel von S21!“ am S10 (b02, b03), Reaktion 👍 von Kim auf beiden (b04). Log wie im WLAN (Ziel 0,60, Absender 0,15; Kugel: S21 `papier_wurf`, S10 `papier_plopp`). Laufzeit sichtbar kurz (≤ 0,4 s bis zum Bild beim Ziel). Danach normaler Zug (Kim legt Blau 8).
- Beobachtung: Das Necken-Menü schließt sich nach 5 s ohne Tipp (so geplant) – wer langsam zielt, muss neu öffnen.

## C. Übung und Weitergeben – bestanden
- **Übung** (3 Computergegner): kein Reaktionsknopf; Kopf-Tipp auf Mimi → Menü nur „Paper ball“ und „View cards“; Kugel fliegt, Treffer mit „Hmph!“ (c01), Log `papier_wurf` 0,60. Danach normaler Zug.
- **Weitergeben** (2 Personen + Bot): kein Reaktionsknopf, Kopf-Tipp auf Bot und Mitspieler öffnet wie bisher die Rückseiten-Großansicht (c02).

## Logcat
- Beide Geräte in allen geprüften Abschnitten: keine `SCRIPT ERROR`, `USER ERROR`, `E/godot`, kein `FATAL`. Einzige godot-Zeilen sind `SfxPool:`-Diagnosen (S10 als `W`, weil dort die Medienlautstärke 0/15 ist – Gerät stumm, so vorgefunden; S21 Medien 1/15). Kein Neuaufbau des SoundPools, kein Fehlstart.

## Fehler
- **F1 (niedrig) – „Gerade noch geschafft!“ überdeckt beim Ziel die Weckerzeile.** Beleg a15 (S21, 08:57:47): „Just in time!“ liegt quer über „Kim set an alarm clock for you!“ und dem kleinen Wecker. Vermutete Ursache: Beide Zeilen setzt `TeaseFx._banner` (`game/scripts/ui/tease_fx.gd:520–531`), die Weckerzeile rechts neben dem Wecker (`:379`, `left = fx.position + …`), „Gerade noch geschafft!“ (`:215`) mit der Standardlage über dem Namensschild (`a.pos + (-r, -r - 34k)`), das ist praktisch dieselbe Höhe; die alte Zeile läuft noch (`dur = 2.8`). Lösung z. B.: beim Abstellen die laufende Weckerzeile des Ziels entfernen bzw. ersetzen, oder „Gerade noch geschafft!“ an derselben Stelle wie die Weckerzeile zeigen.
- **F2 (niedrig) – Reaktionsknopf liegt über modalen Overlays.** Beleg a20 (Farbrad nach Wünscher +2: Knopf und Fächer hell über der Abdunklung, der Fächer lässt sich öffnen, das Farbrad bleibt bedienbar) und a22 (Dialog „Leave the game?“: Knopf hell über dem Dialog-Hintergrund). Vermutete Ursache: `TeaseFx.mount` hängt den `ReactionPicker` direkt hinter `round_end` ins Overlay (`tease_fx.gd:98–99`, `ov.move_child(picker, t.round_end.get_index() + 1)`), also über Farbrad und Rückfrage-Dialogen; `_sync_picker` blendet ihn nur bei `handover` aus (`:1013–1014`). Lösung z. B.: ausblenden bzw. abdunkeln, solange `wish_picker.is_open()`, ein Rückfrage-/Einstellungsdialog oder die Rückseiten-Ansicht offen ist (am Rundenende bleibt er sichtbar, wie gewollt).

## Beobachtungen
- Am S10 stand die Vibration aus und die Medienlautstärke auf 0 (vorgefunden, nicht verändert); Vibration beim Ziel daher nur am S21 belegt.
- Der Tipp auf eine blasse Reaktion lässt den Fächer offen (kein Wackeln). Das Wackeln (`nudge`) gibt es nur bei `fx_no rate` vom Gastgeber; die lokale Sperre griff vorher, deshalb kam kein `fx_no` vor.
- Das Hauptmenü „Practice game“ zeigt „Saved: Last played at Kim“ – Rest aus 1.6.2 (S21 war dort Gast), kein Fehler.

## Nicht geprüft
- Hören (gesperrt, nur Log). Lite/Chrome (gesperrt nicht bedienbar, `/c/1.6.3/` nicht geöffnet), iPhone.
- Großer Modus, Nacht, „Effekte reduziert“, „Schrift sehr groß“ am Gerät (nur Kontrollbilder).
- `fx_no late/busy` mit Text (lokale Vorprüfung verhindert sie im normalen Ablauf), Dazuholen/Entfernen während eines Effekts, Necken nach Gastgeber-Übergabe.
- Mau-Knopf selbst nicht gedrückt (Minka rief „Mau!“, Sprechblase auf beiden Geräten sichtbar).
- Erwischen bei offenem Necken-Menü: Kopf-Tipp auf S21 und danach Tipp auf „Erwischt!“ kamen zu spät – Minka legte in diesem Moment ihre letzte Karte, die Runde war schon vorbei (Rundenende-Tafel).
- Zweiter Wecker desselben Senders im selben Zug: nicht gezielt angetippt (nach dem Senden schließt das Menü; beim Wiederöffnen zeigte es nach dem Zugwechsel einen neuen Zug).

## Ausgangszustand
- Beide Handys im Heim-WLAN „Siemens-Router1“ (nie gewechselt), Mau-Mau Flip 1.6.3 installiert und beendet (force-stop), keine Partie offen (Partien verlassen).
- Testschalter `log.tag.MauMauFlipTestLock` = VERBOSE (so vorgefunden). Einstellung „Necken“ am S21 wieder an. Keine Testdateien unter `/data/local/tmp` (Zwischenbilder gelöscht); die alten `/sdcard/mmf*` (06./08.10.) blieben liegen.
- Testhandys per Sitzungsnachricht bei der Draw2Race-Sitzung belegt und wieder freigegeben.
