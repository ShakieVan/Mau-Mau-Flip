# Gerätetest Beta 1.3.1 – Online-Spiel, Schritt 1 (lokal, 08.10.2026)

**Version:** 1.3.1 statt der zunächst genannten 1.2.3: Beta 1.2.3 und Release 1.3.0 sind schon veröffentlicht (HEAD „Release 1.3.0“,
versionCode 1003000). Eine neue „1.2.3“ hätte den Namen doppelt belegt und ließe sich nicht über 1.3.0 installieren.
Die Arbeitskopie stand zuvor versehentlich auf 1.2.2.

**Aufbau:** Vermittler-Nachbau (`relay_double_main.gd`, Port 24700) auf dem PC, `adb reverse tcp:24700 tcp:24700` an beiden
Geräten. S21 (SM-G991B) als Gastgeber mit APK 1.3.1, Vermittler `http://localhost:24700`. S10 (SM-G973F) als Lite-Gast in Chrome.
Neu: Der Nachbau liefert `relay/public` wie der Worker aus (Lader → `/info?room=` → `/c/1.3.1/?r=CODE`).

| Schritt | Ergebnis | Bild |
|---|---|---|
| Einstellungen → Online → „Verbindung testen“ | „Vermittler antwortet (89 ms)“ | n_01 |
| Lobby → „Online (Internet)“ → „Online öffnen“ | Raum MEISE-46 mit Link, QR und Teilen | n_02 |
| S10: `localhost:24700/?r=meise46` | Der Lader leitet auf `/c/1.3.1/` weiter, Code normalisiert, Beitritt | n_03 |
| Gastgeber sieht den Gast | Haken, „1 Mitspieler online“ | n_04 |
| Kurze Partie (5 Züge, Ziehen/Behalten, Richtungswechsel) | Beide Seiten synchron | n_06, n_07 |
| S10 öffnet den Link neu, „Weiterspielen“ | Mit Token zurück, gleiche Hand (5 Karten) | n_05 |
| Gastgeber „Verlassen“ | Lite: „Der Gastgeber hat das Spiel beendet.“, `/info?room` → `open:false` | n_08 |
| logcat der App (pid) | 0 Zeilen mit Stufe E/F | – |

**Gefunden und behoben:** Lite zeigte „Spiel von true“, weil der Vermittler bei `room.host` nur ja/nein liefert und keinen
Namen. Lite übernimmt jetzt nur noch einen Text als Namen (`webclient/app.js`).

**Nicht am Gerät geprüft:** Abbruch des Gastgebers mit Rückkehr per Token. Das deckt `test_game_online` und `test_net_online` in
Godot headless ab. wss/TLS lässt sich erst mit dem echten Cloudflare-Vermittler prüfen.
Das APK auf dem S21 war der Stand vor der Lite-Korrektur. Das endgültige APK unterscheidet sich nur im mitgelieferten Browser-Client.

## Internet (echter Vermittler, 08.10.2026)

**Aufbau:** APK 1.3.1 neu gebaut (`tools/build.ps1 -Target Android`, Tests grün, SHA-256 `0533d38e…6404036`), auf S21 und S10
installiert. Vermittler `https://mau-mau-flip-relay.shakie.workers.dev` (Standard, `wss://`). S21 = Gastgeber (Android 15, Heim-WLAN),
S10 = App-Gast bzw. Chrome. Auf dem S21 vorher App-Daten gelöscht, weil vom lokalen Test noch `http://localhost:24700` eingestellt war.

| Schritt | Ergebnis | Bild |
|---|---|---|
| S21: Mit anderen spielen → Eröffnen → Online (Internet) → Online öffnen | Raum SCHUH-40, QR, „Link teilen“, Standard-Vermittler | n_10 |
| S10 App: Beitreten → `schuh40` eintippen | normalisiert, in der Lobby; Gastgeber: Haken, „1 Mitspieler online“ | n_11, n_12 |
| Kurze Partie (Aussetzen, Farbwechsel, Ziehen) | beide Seiten synchron | n_13, n_14 |
| S10: App force-stop, neu starten, Code erneut eingeben | Gastgeber zeigt „getrennt“; Gast kommt per Token zurück, gleiche Hand (4 Karten) | n_15 |
| Gastgeber „Verlassen“ | App-Gast: „Verbindung zum Gastgeber beendet“ mit „Selbst eröffnen“/„Regeln speichern“ | – |
| Falscher Code KROKO-77 | „Raum nicht gefunden. Prüf den Code – oder lass dir am besten den Link schicken.“ | n_16 |
| Online-Raum PLANET-56 offen, dann Spiel-WLAN geöffnet | Vermittler-Verbindung bleibt | n_19 |
| S10 Chrome: `…workers.dev/?r=planet56` | Lader → `/c/1.3.1/?r=PLANET-56`, Lite tritt bei (Lobby, „Browser“) | n_17, n_18 |
| Lite-Partie bei offenem Spiel-WLAN (Legen, Ziehen) | synchron | n_20, n_21 |
| Neuer Raum LAUCH-22 bei offenem Spiel-WLAN, dann Spiel-WLAN schließen | Raum öffnet, bleibt offen (`/info?room` → `open:true`); nach „Zurück“ `open:false` | – |
| logcat beider Geräte | keine E/W-Zeilen mit Tag `godot`, keine TLS-/Zertifikatsfehler; nur übliche System-Meldungen (BufferQueue) | – |

**Spiel-WLAN + Online:** Auf dem S21 (Android 15, Heim-WLAN) bleibt der Prozess bei offenem Spiel-WLAN ungebunden
(`host_plan`: Hotspot und WLAN → ""), daher läuft die Vermittler-Verbindung übers Standardnetz. Nicht prüfbar: Android 16+
ohne WLAN (nur Spiel-WLAN + mobile Daten) – dort bindet `host_plan` an den Hotspot; ein **neu** aufgebauter Vermittler-Socket
(Raum öffnen oder Neuverbinden nach Netzwechsel) liefe dann ins Spiel-WLAN ohne Internet. Ebenso bei Bindung an ein WLAN ohne Internet.

**Kleinigkeiten:** Nach einem Neustart steht der letzte Raumcode nicht im Feld (man tippt ihn neu, dann Token-Rückkehr).
Die Lite-Startseite ist auch tagsüber dunkel (Tisch dann hell wie vorgesehen).
