# Recherche zum Projektstart (04.10.2026)

Ergebnis einer Recherche mit mehreren Agenten: Draw2Race ausgewertet, Technikfragen im Web und im Quelltext (Godot 4.6.1, WebKit, AOSP) geprüft, drei Architekturvarianten entworfen und verglichen, kritische Annahmen gegengeprüft. Die Berichte sind Rohfassungen; die Korrekturen unten haben Vorrang.

| Datei | Inhalt |
|---|---|
| `01_draw2race_updater_release.md` | Updater, Versionierung, Signierung, Build und Release von Draw2Race, was sich übernehmen lässt |
| `02_draw2race_netz_weitergeben.md` | Netzcode, Lobby und Weitergeben-Modus von Draw2Race, was für ein Kartenspiel taugt |
| `03_draw2race_android_infrastruktur.md` | Native Android-Funktionen (JavaClassWrapper, Java-Helfer), Machbarkeit von Teilen, Hotspot, HTTP-Server |
| `04_apk_offline_und_netz.md` | APK ohne Internet weitergeben, Hotel-WLAN, LocalOnlyHotspot, WLAN-QR, Entwicklerverifizierung |
| `05_browser_iphone.md` | Mitspielen im iPhone-Browser: Optionen, Safari-Grenzen ohne HTTPS, Testen ohne iPhone |
| `06_hand_ux_effekte.md` | Hand, Sortieren, Sitzordnung, Effektkatalog, Barrierefreiheit, Kartengestaltung |
| `07_regeln_hausregeln.md` | Offizielle Regeln (zwei widersprüchliche Fassungen), Hausregeln, deutsche Begriffe, Optionsbildschirm |
| `08`–`10` | Architekturvorschläge A (Godot), B (Godot + Web-Client), C (Web-Technik) |
| `11_bewertung.md`, `12_empfehlung.md` | Vergleich und Empfehlung |
| `13_gegenpruefung.md` | Gegenprüfung der Annahmen, auf denen die Empfehlung beruht |
| `14`–`16` | HTTPS-Frage: Browserverhalten bei http auf privaten IPs, echte Zertifikate, Secure Context über PWA/WebRTC |
| `17_https_empfehlung.md` | Gutachten und Empfehlung zur HTTPS-Frage (hat Vorrang vor 14–16) |

## Korrekturen nach der Gegenprüfung

1. **Hotspot-Adresse:** Ein zufälliges Subnetz bei *jedem* Einschalten gilt nur für Android 11. Ab Android 12 nimmt Android die letzte Adresse wieder, solange das Handy nicht neu startet und kein Konflikt entsteht. Ab Android 13 sind auch 172.16/12 und 10/8 möglich. Die Adresse bleibt also oft über einen Urlaub gleich, kann sich aber ändern: Platzcode als Notweg bleibt nötig. (Betrifft 04, 05, 11 und Draw2Race `docs/MULTIPLAYER_RECHERCHE.md`.)
2. **Godot-Web über http:** „Startet nicht“ und „kein Ton“ gelten nur für die Standard-Startseite und Godots eigenen Audiotreiber. Mit eigener Startseite, `--audio-driver Dummy` und eigener Web-Audio-Brücke ist der Weg laut Quelltext offen. Ein Beweis auf einem echten iPhone fehlt. (Betrifft 04, 05.)
3. **Server bei pausierter App:** Ein GDScript-Thread allein reicht nicht. Ab Android 14 friert Android gestoppte Apps nach etwa 10 s ein und schließt ihre Verbindungen. Nötig: Bildschirm an lassen und ein kleiner Vordergrunddienst während Verteilung und Partie. (Betrifft 12.)
4. **BrowserStack Open Source:** CC BY-NC 4.0 ist keine OSI-Lizenz, die Aufnahme ins kostenlose Programm ist daher unsicher.
5. **Entwicklerverifizierung ohne Netz:** Auch registrierte Apps könnten sich offline nicht installieren lassen. Offiziell ungeklärt.
