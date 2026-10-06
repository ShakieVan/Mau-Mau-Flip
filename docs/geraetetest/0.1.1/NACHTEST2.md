# Gerätetest Beta 0.1.1 – Nachtest Runde 2

06.10.2026, 12:30–13:50. Geprüft wurde `builds/MauMauFlip-0.1.1.apk` (0.1.1, Code 1001), installiert mit `adb install -r` und danach `pm clear` auf beiden Geräten. Die installierte APK hatte auf beiden Geräten denselben SHA-256 wie der Build.

- Getesteter Build: SHA-256 `74b0920d…439094dd`.
- **Endgültiger Build** nach der Textkorrektur unten: SHA-256 `9c781e4090b390c2ba83ae632dddc47f46f4f453ec8fc86b5d6e65685610d439`. `build.ps1 -Target Android` (mit allen 45 Testläufen grün), auf beiden Geräten installiert (Hash geprüft), gestartet, korrigierter Text gesehen (`n2_r04`), Log ohne Fehler.

| Gerät | Rolle | WLAN-IP |
|---|---|---|
| S21 (SM-G991B, Android 15) | Gastgeber, Übungsspiel | 192.168.178.8 |
| S10 (SM-G973F, Android 12) | App-Gast, Lite im Chrome | 192.168.178.9 |
| PC, Chrome headless (eigenes Profil im Scratchpad) | Browser-Gast `?autotest=1&trennen=1&runden=1` | 192.168.178.29 |

Bedienung über `adb shell input`. Fremde Eingaben gab es diesmal keine: Jede `Delivering touch` im Log hat ein zugehöriges `Inject motion`. Belege liegen mit Präfix `n2_` in diesem Ordner (JPEG, halbe Auflösung).

## Gesamturteil

**Veröffentlichungsreif: ja.** Alle Pflichtpunkte a)–e) bestanden, kein hoher Mangel offen. H1 aus dem ersten Test ist behoben.

## Pflichtpunkte

| Punkt | Ergebnis | Belege |
|---|---|---|
| a) H1: WLAN-Spiel S21 + S10-App + Browser-Gast + Computer | **bestanden.** Start klappt, Server bleibt an (`/info`: `running:true`). Sitzordnung auf beiden Handys richtig gedreht. Partie mit 5 Handkarten bis zum Rundenende („Minka gewinnt Runde 1“, Plätze 1–4 auf allen Geräten gleich). Browser-Gast: Selbsttest `AUTOTEST-OK` (10 Züge, 1 Rundenende, 0 Ablehnungen, „Wiederverbindung ok“, Mau-Blasen). App-Gast: `force-stop`, Neustart, „Beitreten“ → sitzt sofort wieder mit seiner Hand am Tisch. | `n2_l08`, `n2_l11_*`, `n2_l12`, `n2_l14`, `n2_l16`, `n2_l17` |
| b) Glücksspiel mit Aufhören (Übungsspiel) | **bestanden.** Glücksspiel-Joker gelegt, Farbe gewählt, 1 Karte gesetzt, „Los!“ → 0. Knopf „Aufhören“ erscheint unter „Los!“, Hinweis „Noch eine Karte setzen – oder aufhören?“. Tipp → „Aufgehört!“, Meldung „Du hörst auf – 1 Karte unter die Ablage.“, danach ist Kater Karlo dran. | `n2_g01`–`n2_g03` |
| c) Tastatur „Auf einem Handy“ | **bestanden.** Unterstes Namensfeld (Platz 3) bleibt über der Samsung-Tastatur sichtbar, die Liste rückt nach oben; nach dem Schließen alles wie vorher, kein Grauschleier. | `n2_k01`, `n2_k02` |
| d) Lite im Chrome des S10 | **bestanden.** Seite vom Gastgeber (`…:24690/?mock=1&szene=gluecksspiel&need=stake`): Tag hell aus Papier, Nacht dunkel mit Neon. „Los!“ und „Aufhören“ sichtbar und wirksam („Aufgehört!“, Einsatz unter die Ablage; „Los!“ → Treffer 9, Einsatz zurück). | `n2_d01`–`n2_d04` |
| e) logcat | **bestanden.** Seit der Installation auf beiden Geräten kein `FATAL`, `Fatal signal`, ANR, Tombstone, `SCRIPT ERROR` und keine `E/W godot`. Nur Systemzeilen beim Wechsel in den Hintergrund (BufferQueue, S10). | – |

Zusätzlich geprüft:

- **Regelanleitung „Besondere Karten“** (Nutzerwunsch): Abschnitt mit Kartenbildern, Name, Seite und Kartenhilfe; Glücksspiel samt Aufhören; Hinweis auf die ausgeschalteten Zusatzkarten (`n2_r01`, `n2_r02`).
- **„Regeln von Sam übernehmen“**: Nach der Partie eröffnet das S10 selbst. Der Knopf erscheint und übernimmt „Zuletzt gespielt bei Sam“ samt 5 Handkarten (`n2_o02`, `n2_o03`).
- **Gastgeber beendet**: Der App-Gast zeigt „Verbindung zum Gastgeber beendet.“ mit „Selbst eröffnen“ (`n2_l15`).
- Regelsatz speichern/laden am Gerät: nicht geprüft (nur Tests).

## Behoben in diesem Durchgang

- **„Kurz gesagt“ ohne Aufhören** (niedrig): Die Kurzfassung der Hausregel Glücksspiel (`RuleConfig.describe`, auch in der Lobby der Gäste) nannte das Aufhören nicht. Satz ergänzt („Nach einem Druck ohne Treffer darf er aufhören; der Einsatz kommt dann unter die Ablage.“), wie im Lite-Client (`game/scripts/rules/rule_config.gd`). Neu gebaut, alle Tests grün, am S21 nachgesehen (`n2_r04`).

## Offene Mängel (keiner hoch)

| Nr. | Schwere | Mangel |
|---|---|---|
| M4 | mittel | **Getrennter Gast blockiert die Partie.** Ist ein getrennter Mensch am Zug, wartet das Spiel („… ist getrennt – warte …“, `n2_l13`). Kommt er nicht zurück (z. B. Browser-Profil weg, Handy aus), hat der Gastgeber am Tisch keinen Knopf „Computer übernimmt“; `HostTable.substitute_bot()` gibt es, aber nur die Lobby ruft `remove_player`. Einziger Ausweg: Partie verlassen. Vorschlag: am Tisch des Gastgebers nach einigen Sekunden Warten ein Knopf „Computer spielt für Kim“. |
| N6 | niedrig | **Gast verbindet endlos neu, wenn der Gastgeber im Hintergrund beendet hat.** Lag die App des Gasts im Hintergrund, als der Gastgeber „Zum Menü“ tippte, steht danach dauerhaft „Verbinde neu …“ (`n2_o01`, > 20 s). „Zum Menü“ funktioniert. |
| N7 | niedrig | Gastgeber-Lobby am S10: Knopf „Regeln von Sam übern…“ ist abgeschnitten (`n2_o02`). |
| N8 | niedrig | Übersicht nennt die ausgeschalteten Zusatzkarten doppelt: Absatz „Weitere besondere Karten“ (RulesText) und Hinweis unter „Besondere Karten“ (RulesScreen). Inhaltlich richtig. |

Nicht angesehen: Nachtansicht des App-Knopfs „Aufhören“ (der Lite-Knopf nachts ist in Ordnung).

## Hinweise zum Ablauf

- Der erste Browser-Lauf brach mit „Zeitüberschreitung: eigener Zug“ ab. Ursache war der Testaufbau: Der Selbsttest wartet höchstens 60 s auf seinen Zug, und ich habe zwei Menschen per Bildschirmfoto gesteuert. Dabei zeigte sich M4. Der zweite Lauf mit 5 Handkarten lief durch.
- Kein Gerät wurde umgestellt, nichts gesendet; `de.shakie.wlandebugkeepalive` nicht angefasst. Chrome des S10 nur mit der lokalen Adresse des Gastgebers.
