# Beta 1.6.2 – Gastgeber-Übergabe im WLAN und Spiel-WLAN, Gerätetest Runde 1 (13.10.2026, 23:18–23:58)

Plan nach `docs/module/uebergabe.md` 10.16 („Gerätetest S21/S10, gesperrt“). Beide Handys gesperrt, Testschalter `MauMauFlipTestLock` (war schon `VERBOSE`), Bedienung per `input tap`, Belege per `screencap` (exec-out bzw. Skript auf dem S10) und logcat. Kein Browser, kein `/c/1.6.2/`. Bilder 960 px breit, auf 256 Farben verkleinert; Bilder mit zwei Hälften: oben S21 (Englisch), unten S10 (Deutsch), sofern nicht anders angegeben.

## Bau
- APK `builds/MauMauFlip-1.6.2.apk`, 42 546 652 Bytes, SHA-256 4b0f6f0f4229afe326960eec9aef9129aa57b32cbd5aab89c483e88e85983f11 (versionCode 1006002, Bau 13.10. 23:17, Tests aus dem Cache). Per `adb install -r` auf S21 (Android 15) und S10 (Android 12); beide melden beim Start dieselbe Prüfsumme (logcat `Eigene APK: …`). App-Daten nicht gelöscht.

## A. Heim-WLAN – bestanden
- S21 eröffnet im WLAN, S10 „Kim“ findet das Spiel über „Suchen“ (192.168.178.8) und tritt bei, dazu Bot „Minka“. Offiziell, Tag. Züge auf beiden Seiten (Legen, Ziehen).
- **Ausfall** (`am force-stop` am S21, 23:22:09.8). Vorher Kim 6, S21 6, Minka 5 (a01). S10 zeigt „Verbindung zum Gastgeber unterbrochen – warte …“ (bei 42 s noch, a02). **Übernahme nach ≈ 51 s** (logcat S10 23:23:01.3 `keepScreenOn=true`). Danach ist S10 Gastgeber, S21 „getrennt“ mit „Computer übernimmt“/„Aus dem Spiel nehmen“, Hände unverändert (a03).
- **Rückkehr** (`am start` am S21, 23:24:05): Hauptmenü „Continue game – Kim, Minka · Round 1“ (a04). Tipp 23:24:20 → nach ≤ 3 s steht der Tisch, S21 ist Gast auf seinem Platz, Hand (6) unverändert (a05, a06). Die Suche fand S10 im LAN.
- Weitere Züge: S21 legt Wünscher +2 → Gelb, Kim zieht/legt Gelb 1 usw.
- **Geplante Übergabe S10 → S21** (☰ → „Gastgeber übergeben …“ → S21 → „Übergeben“, 23:26:23, a07): nach ≈ 1 s am S21 „You are the host now. Please keep the app open.“, am S10 „Einen Moment – der Gastgeber wechselt.“ und danach Gast (a08). Kein Rückfall, weitere Züge auf beiden Seiten (S21 Gelb 2, Kim Gelb 2, a09).

## C. Andere App (HOME am S21-Gastgeber, Heim-WLAN, 23:27:54) – bestanden
- S10 bei 15, 60, 120, 170 und 178 s: keine Übernahme, S21 „kurz in einer anderen App“ (c01). Oben steht allerdings „Verbindung zum Gastgeber unterbrochen – warte …“ (siehe Beobachtung B2).
- **Übernahme nach ≈ 191 s** (logcat S10 23:31:04.8 `keepScreenOn=true`); bei 186 s noch Gast, bei 210 s Gastgeber mit S21 „getrennt“ und Sofort-Leiste (c02).
- `am start` am S21 (23:31:53): Bei 6 s zeigt S21 die **Gastgeber-Ansicht** („Kim is disconnected“ mit „Computer takes over“/„Remove from game“), gleichzeitig S10 Gastgeber mit „S21 ist getrennt“ (c03) – zwei Gastgeber für einige Sekunden. Bei 12 s ist S21 Gast („Your turn – play Yellow or a 2.“), S10 zeigt S21 verbunden (c04). Die Menüs bestätigen die Rollen: S21 nur Settings/Rules/How to play, S10 mit „Gastgeber übergeben …“ (c05). Der Gastgeber-Wächter hat entschieden; kein Zug ging verloren (S21 war vor und nach dem Wechsel am Zug). Siehe Beobachtung B1.
- Weiter: S21 legt Gelb 6, Minka legt einen Richtungswechsel (Bot spielt beim neuen Gastgeber, c06). Partie danach von S10 („Verlassen“) beendet; S21 „Verbindung zum Gastgeber beendet.“

## B. Spiel-WLAN – nicht bestanden (F1, F2)
Erlaubnis vorab per `pm grant` (S21 NEARBY_WIFI_DEVICES, S10 ACCESS_FINE/COARSE_LOCATION), am Ende zurückgenommen.
- S21 eröffnet, „Lieber eigenes Spiel-WLAN“: AndroidShare_4905, Spiel-QR 192.168.35.250:24690 (b01). S10 per Skript auf dem Gerät: `cmd wifi connect-network AndroidShare_4905 wpa2 …` (23:36:50, verbunden 23:37:03; danach stand kurz die Benachrichtigungsleiste vorn, das Skript holte die App per `am start` zurück), „Beitreten“ → Suche findet „Spiel von S21 · 192.168.35.250“ → beigetreten (b02). Bot Minka dazu, Start 23:37:40 (b03). Hand Kim 7, S21 7, Minka 7.
- **Ausfall** (`am force-stop` am S21, 23:38:08): Das Spiel-WLAN verschwindet, Android verbindet das S10 nach ≈ 3 s selbst wieder mit „Siemens-Router1“ (logcat 23:38:11–12; Skriptprotokoll ab 23:38:18 „connected to Siemens-Router1“).
  - S10 bei 9 s „Verbindung zum Gastgeber unterbrochen – warte …“, bei 44 s „Suche den neuen Gastgeber …“ mit „Spiel als Gastgeber fortsetzen“ (b04). **Übernahme nach ≈ 52 s** (logcat S10 23:39:00.3 `keepScreenOn=true`), danach S10 Gastgeber mit „S21 ist getrennt“ und Sofort-Leiste, Hände unverändert (b05, 23:40:27).
  - Die Übernahme lief aber als **normale WLAN-Übernahme**: **kein eigenes Spiel-WLAN** (kein `swlan0` am S10, kein Versuch im logcat, kein Hinweis „Du bist jetzt Gastgeber. Öffne das Spiel-WLAN …“, kein „Dazuholen“-Fenster). Ursache: F1. Dass überhaupt automatisch übernommen wurde, liegt am Heim-WLAN mit Präfix /16: 192.168.178.9/16 gilt als „im selben Netz“ wie die alte Spiel-WLAN-Adresse 192.168.35.250 (`lan_ok` zufällig wahr). Mit einem /24-Heimnetz hätte niemand übernommen.
  - logcat S10 23:38:08–23:38:48: 11× `E/godot ERROR: Condition "_sock == -1" is true` (`drivers/unix/net_socket_unix.cpp:287`, siehe F3). Kein SCRIPT ERROR.
- **Rückkehr** (`am start` am S21, 23:41, S21 im Heim-WLAN): „Continue game – Kim, Minka · Round 1 · 5 min ago“; Tipp 23:42:26 → nach ≤ 2 s ist S21 Gast auf seinem Platz (Hand 7 unverändert, b06); die Suche fand S10 im Heim-WLAN. Kim legt Blau 7 und Blau 4 (b07).
  - Der geplante Teil „S21 per `connect-network` ins Spiel-WLAN des S10“ entfiel, weil das S10 kein eigenes Spiel-WLAN geöffnet hatte (F1).
- **Spiel-WLAN beim neuen Gastgeber von Hand:** S10 (Gastgeber) ☰ → „Mitspieler dazuholen“ → „Lieber eigenes Spiel-WLAN“: AndroidShare_3008, **swlan0 192.168.178.254/24**, Spiel-QR 192.168.178.254:24690 (b08). Das S10 bleibt dabei im Heim-WLAN (192.168.178.9/16) – das Spiel-WLAN liegt im selben Adressbereich wie das Heim-WLAN.
- **Geplante Übergabe S10 → S21 bei offenem Spiel-WLAN des S10:** Der Auswahldialog zeigt **keine** Warnzeile „Alle müssen danach einen neuen QR-Code scannen.“ (b09; F1: `wlan.ap` falsch, also `how:"lan"`). „Übergeben“ 23:44:3x: S21 „You are the host now …“ (Kim „disconnected“), S10 „Einen Moment – der Gastgeber wechselt.“ (b10).
  - Danach **hängt S10 als Gast bei „Der Tisch wird geladen …“** – über 2,5 min, ohne Hinweis, Knopf oder Rückfall (b11; ☰ zeigt nur Einstellungen/Regeln/So geht's). Sein Spiel-WLAN blieb offen (`swlan0` 192.168.178.254 noch um 23:45:51). `ip route get 192.168.178.8` am S10 → `dev swlan0 table 97`, `ping 192.168.178.8` → „Destination Host Unreachable“ von 192.168.178.254. Ursache: F2.
  - Aufgelöst von Hand: `am force-stop` am S10 (Spiel-WLAN zu), `am start` → „Partie fortsetzen – S21, Minka · Runde 1“ → nach ≤ 3 s Gast auf seinem Platz, Hand (5) unverändert (b12). Weitere Züge (S21 Blau 3, Kim am Zug, b13). S21 verlässt die Partie, S10 „Verbindung zum Gastgeber beendet.“
- Kein doppelter Gastgeber, kein „Raum beendet“ in B.

## D. Gemischt (S21 WLAN + online, S10 im WLAN) – bestanden
- S21 eröffnet online, Raum **FUCHS-56** über den Standard-Vermittler (d01); S10 tritt über die WLAN-Suche bei (192.168.178.8), Bot Minka. Züge (d02: Kim 6, S21 7, Minka 6).
- `am force-stop` am S21 (23:51:47): S10 „Suche den neuen Gastgeber …“ (d03 oben, ≈ 50 s), **Übernahme nach ≈ 52 s** (logcat 23:52:39.6 `keepScreenOn=true`), danach S21 „getrennt“ mit Sofort-Leiste (d03 unten). Unter „Mitspieler dazuholen → Online (Internet)“ zeigt S10 denselben Raum FUCHS-56 (d04) – Raum übernommen.
- `am start` am S21, „Continue game“ (23:54:29): sofort „Kim is running the game now. You keep playing as a guest.“, Hand (7) unverändert (d05). S21 legt Gelb 5, Kim am Zug (d06). Kein „Raum beendet“, kein doppelter Gastgeber.

## Logcat
- Beide Geräte: keine `SCRIPT ERROR`, `USER ERROR`, kein `FATAL`. Einzige `E/godot`-Zeilen: F3 (S10, Spiel-WLAN-Verlust).
- Der Netzmitschnitt (`netz.log`) ist in der Release-APK nicht lesbar; Rollen und „kein doppelter Gastgeber“ sind über Bildschirme/Menüs belegt.

## Fehler
- **F1 (hoch) – Ein offenes Spiel-WLAN wird unter Android ≤ 15 nie als `wlan.ap` erkannt.** Folgen: Nach Verlust des Spiel-WLANs gilt der normale WLAN-Ablauf (Übernahme nur bei zufällig passendem `lan_ok`, hier wegen /16-Heimnetz), der Erbe öffnet kein eigenes Spiel-WLAN, keine Warnzeile/`how:"qr"` bei der geplanten Übergabe, der alte Gastgeber schließt sein Spiel-WLAN beim Abtreten nicht. Belege: b04/b05 (Übernahme ohne Spiel-WLAN, kein `swlan0`), b09 (Dialog ohne QR-Warnzeile trotz offenem Spiel-WLAN), `swlan0` am S10 nach der Übergabe noch offen.
  - Vermutete Ursache: `HostTable._update_ap()` (`game/scripts/game/host_table.gd:1333–1340`) setzt `_ap` nur, wenn `hotspot_check` gesetzt ist (nur in Tests) oder `NetAddresses.binding() == "hotspot"`. Mit Spiel-WLAN **und** WLAN liefert `NetAndroid.host_plan` aber `bind = ""` (`game/scripts/app/net_android.gd:298–311`; „hotspot“ nur Android 16+ ohne WLAN), also bleibt `_ap` auf S21/S10 immer falsch. Folge im Gast: `wlan.ap` fehlt im Schnappschuss, es gilt der normale WLAN-Ablauf (10.4) ohne `auto_open`; in einem /24-Heimnetz (S10 wieder im Heim-WLAN, alte Adresse 192.168.35.250 nicht im eigenen Netz) übernähme niemand automatisch.
  - Lösung z. B.: In der App `hotspot_check` setzen (z. B. in `TableScreen` beim Anlegen des `GameWifiWatch`: eigenes Spiel-WLAN offen = `GameWifiWatch.state`/`NetAndroid.hotspot_addresses(NetAndroid.state())` nicht leer bzw. `game_wifi_state().open`) statt die Bindung zu prüfen. Ein Test, der `hotspot_check` **nicht** einspritzt und `binding() == ""` mit offenem Spiel-WLAN nachbildet, fehlt.
- **F2 (hoch) – Alter Gastgeber mit eigenem Spiel-WLAN hängt nach der geplanten Übergabe bei „Der Tisch wird geladen …“.** Beleg: b10/b11, `ip route get`/`ping` oben; ≥ 2,5 min ohne Hinweis oder Rückfall; erst `force-stop` + „Partie fortsetzen“ half (b12).
  - Vermutete Ursache: (a) wegen F1 `how:"lan"` statt `"qr"`, das Spiel-WLAN bleibt offen; (b) das LocalOnlyHotspot des S10 bekommt **192.168.178.254/24** – derselbe Bereich wie das Heim-WLAN (192.168.178.0, Präfix /16). `join(192.168.178.8, …)` → `NetAddresses.bind_for("join", addr)` (`game/scripts/net/net_addresses.gd:201–202`) hält die Adresse über `in_hotspot` für einen Spiel-WLAN-Teilnehmer, `join_binding` gibt unter Android 12 `""` (kein Hotspot-Netz-Handle, `net_android.gd:286–291`) → ungebundener Socket → der Kernel nimmt die spezifischere Route über `swlan0` → S21 unerreichbar. (c) Der Gast-Tisch im Ladezustand zeigt keinen Streifen/HostSwitch-Hinweis und keinen Ausweg.
  - Lösung z. B.: beim Abtreten das eigene Spiel-WLAN vor `join` schließen, sobald F1 behoben ist (`qr`), und unabhängig davon in `bind_for("join")` bei einer Adresse, die **auch** im WLAN-Netz liegt und über das WLAN bekannt ist (`players[id].address` aus Sicht des WLAN), ans WLAN binden statt ungebunden; zusätzlich im Ladezustand nach einer Frist einen Hinweis mit „Partie fortsetzen“/„Zum Menü“ zeigen. Gleiches Problem droht einem Gastgeber, dessen Spiel-WLAN den Bereich des Heim-WLANs überdeckt: neue Verbindungen von WLAN-Gästen aus 192.168.178.0/24 liefen ins Spiel-WLAN (nicht geprüft).
- **F3 (niedrig) – Engine-Fehler nach Verlust des Spiel-WLANs.** S10 23:38:08–23:38:48, 11× `E/godot ERROR: Condition "_sock == -1" is true` at `_inet_open (drivers/unix/net_socket_unix.cpp:287)`. Vermutlich ist der Prozess per `bind_for("join")` (`bind_wifi`) noch an das verschwundene AndroidShare-Netz gebunden; Sockets (Neuversuch, Suche) lassen sich bis zum Neu-Binden nicht anlegen (nach ≈ 40 s vorbei). Kein Absturz, aber Suche/Neuverbinden laufen in dieser Zeit ins Leere; die Bindung bei `onLost` der System-WLAN-Verbindung lösen (wie für `QrWifi` in 10.8).

## Beobachtungen
- **B1 (niedrig):** Nach HOME-Übernahme (C) ist der zurückkehrende alte Gastgeber einige Sekunden selbst Gastgeber (c03), bis der Wächter ihn abtreten lässt. Ein Zug in diesem Fenster ginge verloren. Online (1.6.1) entschied der Vermittler sofort. Möglich: beim Zurückkehren aus dem Hintergrund (`back`) sofort einen Wächter-Scan und bis dahin den Tisch einfrieren.
- **B2 (niedrig):** In C zeigt der Gast bei abwesendem Gastgeber „Verbindung zum Gastgeber unterbrochen – warte …“ statt „Gastgeber kurz weg – warte …“, obwohl am Platz „kurz in einer anderen App“ steht (c01). Im WLAN gibt es kein 4503; der Text kommt aus `NetClient.hint()` (`host_away` nur online).
- Bei einem einzigen Erben (Rang 0) gibt es im WLAN wie online keinen Countdown; nach ≈ 40 s erscheint nur „Suche den neuen Gastgeber …“.
- Gesperrt im Netz ohne Internet holte das S10 kurz die Benachrichtigungsleiste (`NotificationShade`) nach vorn; `am start` brachte die App zurück. Der Sperrbildschirm selbst kam nicht nach vorn.

## Nicht geprüft
- Automatische Übernahme mit eigenem Spiel-WLAN des Erben, S21 im Spiel-WLAN des S10, geplante Übergabe `qr` mit Wechsel des Spiel-WLANs und Zustand *scan* („Neues Spiel-WLAN bei %s – QR-Code scannen“): wegen F1 nicht erreichbar.
- `QrWifi`-Bindung nach „lost“: Gesperrt gibt es weder QR-Scanner noch den Systemdialog „Mit Gerät verbinden?“; das S10 kam per `cmd wifi connect-network` (System-WLAN) ins Spiel-WLAN, nicht über `QrWifi`.
- Lite/Chrome (gesperrt nicht bedienbar; `/c/1.6.2/` nicht geöffnet), iPhone.
- Erlaubnisdialoge (vorab per `pm grant` erteilt).

## Ausgangszustand
- Beide Handys im Heim-WLAN „Siemens-Router1“, Mau-Mau Flip beendet (force-stop), keine Partie offen (S21 bzw. S10 haben die Partien verlassen, Hauptmenüs ohne „Partie fortsetzen“).
- Testschalter `log.tag.MauMauFlipTestLock` = VERBOSE (so vorgefunden). Rechte wie vorher: S21 NEARBY_WIFI_DEVICES `granted=false`, S10 ACCESS_FINE/COARSE_LOCATION `granted=false` (per `pm revoke`, Flags wie vorher).
- Eigener WLAN-Eintrag „AndroidShare_4905“ am S10 per `cmd wifi forget-network 14` gelöscht; der ältere Eintrag „AndroidShare_4367“ am S21 bestand schon vorher und blieb. Testskript und Bilder unter `/data/local/tmp` gelöscht; die alten `/sdcard/mmf*` (06./08.10.) blieben liegen.

## Behebung (14.10.2026, ohne Geräte; Tests `game/tests/test_wlan_fixes.gd`, `game/tests/test_ui_wlan_stuck.gd`)
- **F1:** `GameWifiWatch.setup` setzt `HostTable.hotspot_check` auf den eigenen Zustand (`own_open`: Spiel-WLAN „on“ oder an den Hotspot gebunden); ohne Watch prüft `HostTable.own_game_wifi_open()` auf Android `GameWifi.hotspotState`. Damit gilt `wlan.ap` auch mit Spiel-WLAN **und** WLAN (Bindung ""): Übergabe `how:"qr"` mit Warnzeile, beim Abtreten schließt der alte Gastgeber sein Spiel-WLAN. Dazu `HostSwitch.lan_reach`: Führte der alte Gastgeber das Spiel-WLAN und ist die eigene Adresse daraus (`seats[mine].addr`) weg, gilt das Netz als weg – auch wenn ein Heim-WLAN /16 die alte Adresse umfasst. Rang 0 übernimmt dann mit eigenem Spiel-WLAN (`_take_ap`), die anderen gehen nach *scan*.
- **F2:** (a) folgt aus F1. (b) `NetAddresses.bind_for("join")`: Liegt die Adresse im eigenen Hotspot **und** in einem WLAN (`NetAndroid.in_wifi`), wechselt die Bindung je Versuch (zuerst WLAN, dann wie bisher). (c) Gast-Tisch ohne ersten Stand: Verbindungsstreifen sofort; nach `TableScreen.load_stuck_ms` (20 s) „Der Gastgeber antwortet nicht.“ mit „Zum Hauptmenü“ (ohne bye, die Partie bleibt unter „Partie fortsetzen“).
- **F3:** `NetClient._open` ruft bei jedem Neuversuch im WLAN `bind_for("join")`; eine Bindung an ein verlorenes Netz wird so sofort ersetzt bzw. gelöst.
- **B1:** `HostTable` merkt sich die Zeit im Hintergrund; nach ≥ `WAKE_PAUSE_MS` (20 s) fragt der Wächter sofort (`NetDiscovery.scan_soon`), Aktionen und Bots warten `WAKE_CHECK_MS` (3 s, Streifen „Einen Moment – gleich geht es weiter.“). Ein Rivale mit höherer gen gewinnt in dieser Zeit schon beim ersten Scan.
- **B2:** `ClientTable.connection_hint`: Gastgeber laut Stand `away` → „Gastgeber kurz weg – warte …“ (auch im WLAN).
- Offen: Ein Gastgeber, dessen Spiel-WLAN den Bereich des Heim-WLANs überdeckt, erreicht neue WLAN-Gäste aus diesem Bereich womöglich nicht (ungebundener Server, engere Route ins Spiel-WLAN) – am Gerät prüfen.

# Nachtest (14.10.2026, 00:27–01:27)

Nach der Behebung von F1–F3, B1 und B2. Gleicher Aufbau wie Runde 1: beide Handys gesperrt, Testschalter `MauMauFlipTestLock` (war `VERBOSE`), `input tap`/`swipe`, `screencap` (exec-out bzw. Skript auf dem Gerät, solange es im Spiel-WLAN ohne adb war) und logcat. Kein Browser, kein `/c/1.6.2/`. Bilder `n01`–`n20` (960 px breit, 256 Farben); Doppelbilder oben S21 (Englisch), unten S10 (Deutsch), Bildreihen mit Zeitangabe im Namen.

## Bau
- APK `builds/MauMauFlip-1.6.2.apk`, 42 550 732 Bytes, SHA-256 64df8427e449d2d28c89a5261461779427593d6d35a1e7eb38d2b9693b692e4f (versionCode 1006002). Per `adb install -r` auf S21 (Android 15) und S10 (Android 12); beide melden beim Start dieselbe Prüfsumme (logcat `Eigene APK: …`). App-Daten nicht gelöscht.
- Spiel-WLAN-Erlaubnis vorab per `pm grant` (S21 NEARBY_WIFI_DEVICES, S10 ACCESS_FINE/COARSE_LOCATION), am Ende per `pm revoke` zurück.

## B. Spiel-WLAN (vorher F1, F2) – bestanden
- S21 eröffnet im WLAN, „Use your own game Wi-Fi instead“: AndroidShare_5713, swlan0 192.168.35.250/24 (n01). S10 per Skript auf dem Gerät: `cmd wifi connect-network AndroidShare_5713 …` (00:44:28, 192.168.35.176/24), „Beitreten“ → Suche → beigetreten (00:44:56). Bot Minka, Start 00:48:3x; Kim 7, S21 7, Minka 7 (n02).
  - Die ersten beiden Beitrittsversuche per Skript (AndroidShare_6832, _8638) scheiterten an der Bedienung: Im Netz ohne Internet lag am gesperrten S10 die Benachrichtigungsleiste vorn (`mCurrentFocus=NotificationShade`), Tipps gingen ins Leere. Kein App-Befund.
- **Ausfall** (`am force-stop` am S21, 00:49:00.9). Android verbindet das S10 selbst wieder mit „Siemens-Router1“. S10: bei 42 s „Suche den neuen Gastgeber …“, dann **Countdown „Gastgeber antwortet nicht. Du übernimmst in 12 s“ … „in 4 s“** (n03). **Übernahme nach ≈ 63 s** (logcat 00:50:04.3 `keepScreenOn=true`) – T_SILENT + Probe + T_STEP, wie für Rang 0 im Spiel-WLAN vorgesehen (10.8).
  - **Das S10 öffnet automatisch ein eigenes Spiel-WLAN**: `lohs.onStateChanged` 00:50:04.66 (0,3 s nach der Übernahme, ohne Tippen), swlan0 192.168.178.254/24; das Fenster „Mitspieler → Dazuholen“ mit WLAN-QR, Name/Passwort und Spiel-QR geht auf (n03 unten rechts, n04: AndroidShare_9216). S21 „getrennt“ mit Sofort-Leiste, Hände unverändert (Kim 7, S21 7, Minka 7). **F1 behoben.**
- **Rückkehr in das Spiel-WLAN des S10:** `am start` am S21 → „Continue game – Kim, Minka · Round 1 · 4 min ago“; Skript auf dem S21: `cmd wifi connect-network AndroidShare_9216 …` (00:52:46, 192.168.178.137/24), Tipp 00:52:57 → nach ≤ 3 s „Kim is running the game now. You keep playing as a guest.“, Hand (7) unverändert (n05). Das S21 fand das S10 per Suche **im Spiel-WLAN des S10**.
- **Geplante Übergabe S10 → S21 bei offenem Spiel-WLAN (`qr`):** Der Auswahldialog zeigt jetzt die Warnzeile „Alle müssen danach einen neuen QR-Code scannen.“ (n06). „Übergeben“ 00:55:19:
  - Das S10 schließt sein Spiel-WLAN (danach nur noch wlan0); das S21 verliert damit dessen Netz, Android verbindet es wieder mit „Siemens-Router1“.
  - Das S21 wird Gastgeber („You are the host now …“) und **öffnet automatisch ein eigenes Spiel-WLAN** (swlan0 192.168.35.250, Fenster mit WLAN-QR und Spiel-QR, n08).
  - Das S10 zeigt „Du spielst jetzt als Gast weiter. Gastgeber ist S21.“, den Streifen *scan* „Spiel-WLAN von Kim ist weg.“ mit „Spiel als Gastgeber fortsetzen“ / „Neues Spiel-WLAN bei S21 – QR-Code scannen“ und „Der Tisch wird geladen …“ (2, 5, 10 s); **bei 35 s steht der Tisch**, S10 ist Gast (n07). Die Suche im Heim-WLAN fand das S21. Kein Hängen mehr (**F2 behoben**; die 20-s-Frist „Der Gastgeber antwortet nicht.“ wurde dabei nicht erreicht).
  - Weitere Züge: S21 legt Gelb 2, Kim Gelb +1 (n09). Kein doppelter Gastgeber, kein „Raum beendet“.
- Abschluss: S21 „Leave“ → S10 „Verbindung zum Gastgeber beendet.“

## A. Heim-WLAN – bestanden
- S21 eröffnet im WLAN, S10 „Kim“ findet „Spiel von S21 · 192.168.178.8“ über die Suche, dazu Bot Minka (Start 01:02). Züge: Kim legt Gelb 4 → Blau 4, S21 zieht.
- **Ausfall** (`am force-stop` am S21, 01:03:15.7): S10 bei 20 s „Verbindung zum Gastgeber unterbrochen – warte …“, bei 42 s „Suche den neuen Gastgeber …“ mit „Spiel als Gastgeber fortsetzen“; **Übernahme nach ≈ 52 s** (logcat 01:04:07.3 `keepScreenOn=true`), danach S21 „getrennt“ mit Sofort-Leiste (n10). Hände unverändert (Kim 6, S21 8, Minka 6). Kim zieht und legt den gezogenen Wünscher +2 → Grün; Bot Minka zieht 2 und spielt beim neuen Gastgeber.
- **Rückkehr** (`am start` am S21, „Continue game – Kim, Minka · Round 1 · 4 min ago“, Tipp 01:06:15.7): nach ≤ 1,8 s „Kim is running the game now. You keep playing as a guest.“, Hand (8) unverändert (n11). S21 legt Grün 2.
- **Geplante Übergabe S10 → S21** (☰ → „Gastgeber übergeben …“, ohne QR-Warnzeile, da kein Spiel-WLAN; „Übergeben“ 01:07:42): S21 „You are the host now. Please keep the app open.“ / „S21 is the host now.“ (n12). Kein Rückfall; Kim legt Grün 1, Minka Grün 9 (n13).

## C. Andere App (HOME am S21-Gastgeber, Heim-WLAN, 01:08:46) – bestanden
- S10 bei 15, 60 und 178 s: **„Gastgeber kurz weg – warte …“** und am Platz „kurz in einer anderen App“, keine Übernahme (n14; **B2 behoben**).
- Übernahme nach **≈ 191 s** (logcat S10 01:11:56.9 `keepScreenOn=true`); bei 200 s S10 Gastgeber, S21 „getrennt“ mit Sofort-Leiste (n14 unten rechts).
- `am start` am S21 (01:12:48): Das erste Bild nach ≈ 1,8 s zeigt noch die Gastgeber-Ansicht, aber mit dem Streifen „One moment – the host is changing.“ (Tisch eingefroren); nach ≈ 3,6 s ist S21 Gast („You keep playing as a guest. Kim is the host.“), danach „Your turn – play Green or a 9.“ (n15). Das Fenster mit zwei Gastgebern ist von 6–12 s auf ≈ 2–4 s geschrumpft und eingefroren (**B1 behoben**). S21 legt Rot 9 als Gast, kein Zug verloren.

## Spiel-WLAN im Adressbereich des Heim-WLANs (offener Punkt aus der Behebung) – kein Fehler
- S10 (Gastgeber nach C, im Heim-WLAN 192.168.178.9/16) öffnet am Tisch „Lieber eigenes Spiel-WLAN“: AndroidShare_9715, **swlan0 192.168.178.254/24** (n16). `ip route get 192.168.178.8` (Shell) → `dev swlan0 table 97`.
- Der schon verbundene Gast S21 (192.168.178.8, Heim-WLAN) bekommt weiter jeden Zug (Kim legt Rot 6 → Blau 6, am S21 sichtbar).
- **Neue Verbindung:** `am force-stop` am S21, `am start`, „Continue game“ (01:16:33): nach ≤ 3 s Gast auf seinem Platz, Hand (6) unverändert; S21 zieht, am S10 sichtbar (n17). Der ungebundene Server nimmt also neue WLAN-Gäste aus 192.168.178.0/24 an (Antwort über die Schnittstelle der eingehenden Verbindung). Nicht geprüft: ein ganz neuer Gast, der den Gastgeber nur per Rundruf-Suche findet.
- S10 „Verlassen“ → swlan0 bleibt offen, bis die App beendet wird (bekannt seit 1.3.3/1.4.3, „Spiel-WLAN bleibt nach Verlassen offen“).

## D. Gemischt (S21 WLAN + online, S10 im WLAN) – bestanden
- S21 eröffnet online, Raum **ECHSE-38**; S10 tritt über die WLAN-Suche bei, Bot Minka. Kim legt Blau 3, Wünscher +2 → Gelb an S21 (Kim 6, S21 9, Minka 6).
- `am force-stop` am S21 (01:21:06.4): S10 bei 45 s „Suche den neuen Gastgeber …“, **Übernahme nach ≈ 52 s** (logcat 01:21:58.5), S21 „getrennt“ (n18). Unter „Mitspieler → Online (Internet)“ zeigt das S10 denselben Raum ECHSE-38 (n19).
- `am start` am S21, „Continue game“ (01:23:52): „Kim is running the game now. You keep playing as a guest.“, Hand (9) unverändert (n20). Kim zieht Gelb 1 und legt es, am S21 sichtbar. Kein „Raum beendet“, kein doppelter Gastgeber.

## Logcat
- Beide Geräte: keine `SCRIPT ERROR`, `USER ERROR`, kein `FATAL`.
- `E/godot ERROR: Condition "_sock == -1"` (`net_socket_unix.cpp:287`) nur noch **je einmal** genau im Moment des Netzverlusts: S10 00:49:00.977 (Spiel-WLAN des S21 weg), S21 00:55:20.497 (Spiel-WLAN des S10 weg). Dazu am S10 2× „Connection to remote host failed!“ (00:49:01/04, Neuversuche an die tote Adresse). In Runde 1 waren es 11× über 40 s (**F3 behoben**).

## Fehler im Nachtest
- Keine.

## Beobachtungen (niedrig)
- (Behoben, siehe Nachtrag 15.10.2026.) Nach der geplanten `qr`-Übergabe zeigt der **alte Gastgeber** (S10) einige Sekunden den Streifen „Spiel-WLAN von Kim ist weg.“ – Kim ist das S10 selbst – mit „Spiel als Gastgeber fortsetzen“ (n07). Er hat gerade abgegeben; ein Tipp dort eröffnete einen zweiten Zweig, den erst der Wächter auflöst. Vermutlich geht der `HostSwitch` beim Abtreten mit `how:"qr"` in den Zustand *scan* mit dem Namen aus `wlan.ap_seat` (alter Platz) und bietet wie nach einem Ausfall die Übernahme von Hand an. Vorschlag: beim Abtreten den Streifen ohne „Spiel als Gastgeber fortsetzen“ und mit dem Namen des Ziels („Neues Spiel-WLAN bei S21 …“) zeigen.
- Gesperrt im Netz ohne Internet holte das S10 (und einmal das S21) die Benachrichtigungsleiste nach vorn; die Skripte holten die App per `am start` zurück.

## Nicht geprüft
- `QrWifi`-Bindung nach „lost“: gesperrt kein QR-Scanner und kein Systemdialog „Mit Gerät verbinden?“; beide Handys kamen per `cmd wifi connect-network` (System-WLAN) in die Spiel-WLANs.
- Zustand *scan* mit QR-Scan und eine Übernahme, nach der der Gast **nicht** von selbst ins Heim-WLAN zurückfällt (beide Handys kennen „Siemens-Router1“; ohne bekanntes Netz bliebe nur der Scan).
- Der Hinweis „Der Gastgeber antwortet nicht.“ nach 20 s im Ladezustand (F2 c) – der Tisch kam vorher.
- Neuer Gast per Rundruf-Suche bei einem Gastgeber, dessen Spiel-WLAN den Bereich des Heim-WLANs überdeckt.
- Erlaubnisdialoge (vorab per `pm grant`), Lite/Chrome, iPhone.

## Ausgangszustand nach dem Nachtest
- Beide Handys im Heim-WLAN „Siemens-Router1“, Mau-Mau Flip beendet (force-stop), keine Spiel-WLANs offen (kein swlan0). App-Daten nicht gelöscht; das S21 kann im Hauptmenü noch „Continue game“ zur Gast-Datei der gemischten Partie zeigen (S10 hat sie verlassen).
- Testschalter `log.tag.MauMauFlipTestLock` = VERBOSE (so vorgefunden). Rechte wie vorher: S21 NEARBY_WIFI_DEVICES `granted=false`, S10 ACCESS_FINE/COARSE_LOCATION `granted=false` (Flags wie vorher).
- Eigene WLAN-Einträge gelöscht: S21 „AndroidShare_9216“; S10 „AndroidShare_6832“, „AndroidShare_8638“, „AndroidShare_5713“. Der ältere Eintrag „AndroidShare_4367“ am S21 bestand schon vorher und blieb. Testskripte und Bilder unter `/data/local/tmp` auf beiden gelöscht.

# Nachtrag (15.10.2026): alter Gastgeber nach der Übergabe `qr` – behoben

Befund aus den Beobachtungen des Nachtests (n07): Nach „Übergeben“ im eigenen Spiel-WLAN zeigte das S10 einige Sekunden „Spiel-WLAN von Kim ist weg.“ (Kim = S10 selbst) mit „Spiel als Gastgeber fortsetzen“.

- **Ursache:** Beim Abtreten mit `how:"qr"` schließt `HostSwitch._on_stepped_down` das eigene Spiel-WLAN (`wifi_stop`) und setzt den neuen Gast-Tisch ohne Verbindung über `_scan_next` direkt in den Zustand *scan* (nicht über `_poll_missing_lan`). *scan* behandelte ihn wie einen Gast nach einem Ausfall: Streifen „Spiel-WLAN von %s ist weg.“ mit dem Namen aus `wlan.ap_seat` (der alte Gastgeber selbst) und `can_continue()` wahr, also „Spiel als Gastgeber fortsetzen“ – ein Tipp hätte einen zweiten Zweig eröffnet.
- **Behebung:** `HostSwitch.handed_off()` – wahr in *scan*, wenn das Gerät eben selbst mit `qr` abgegeben hat, für `handoff_wait_ms` (60 s). Solange: Streifen „Einen Moment – der Gastgeber wechselt.“ (vorhandener Text), Knopf „Neues Spiel-WLAN bei S21 – QR-Code scannen“ bleibt, **kein** „Spiel als Gastgeber fortsetzen“ (`can_continue()` falsch, `continue_as_host()` wirkungslos); die Suche läuft weiter und folgt beim Fund wie bisher. Kommt das Ziel in dieser Zeit nicht an, gilt *scan* wie nach einem Ausfall (mit Übernahme von Hand). Andere Plätze in *scan* (move `qr`, fremdes Spiel-WLAN weg) und die Erkennung echter Ausfälle sind unverändert; kein neuer Text.
- **Tests:** `test_takeover_wlan` Fall 11 (geplant `qr`, beide Suchen ins Leere: Hanna wartet ohne Übernahme, Ben in *scan* unverändert mit Knopf, nach der Wartezeit *scan* wie nach einem Ausfall) und `test_ui_handover_wlan` W (Streifen „Einen Moment …“ mit QR-Knopf, ohne „Spiel als Gastgeber fortsetzen“). Gegenprobe mit abgeschaltetem `handed_off()`: Fall 11 rot (5 Fehler, Hanna wird zweite Gastgeberin), UI-Test rot (2 Fehler). Mit Behebung einzeln grün: `test_takeover_wlan` (180), `test_ui_handover_wlan` (58), `test_handover_wlan` (128), `test_wlan_fixes` (40), `test_ui_handover` (32), `test_i18n` (1460), `test_i18n_handover_wlan` (136). `test_takeover_mixed` 3 von 5 Läufen grün (72); die beiden roten Läufe scheiterten an Frist-Überschreitungen in Fall 0/1 (Raum-Folge, ohne Abtreten mit `qr`, von der Änderung nicht berührt).
- Am Gerät noch nicht nachgeprüft.
