# Jury-Bewertung der Architekturvorschläge für Mau-Mau Flip

Stand 04.10.2026. Ich habe nur gelesen und nichts verändert oder angelegt.

**Kürzel:**
- **A** = godot-zentriert
- **B** = Godot-App plus schlanker Web-Client (TypeScript/PixiJS)
- **C** = web-zentriert (alles TypeScript/PixiJS, Android-App als Java-Hülle mit WebView)
- **PT** = Personentage, also ein Arbeitstag des Nutzers mit Claude als Programmierer, einschließlich Gerätetests.

---

## 1. Was ich als Jury selbst nachgeprüft habe

| Behauptung | Geprüft an | Ergebnis |
|---|---|---|
| Die Secure-Context-Sperre steht nur in der Standardseite `godot.html`, nicht in der Engine (A) | `Draw2Race\.tools\export\templates\web_nothreads_release.zip` (4.6.1), im Speicher gelesen | **Bestätigt.** `godot.js` ruft `getMissingFeatures()` an keiner Stelle selbst auf. Das tut nur `godot.html`, und zwar vor `engine.startGame()`. |
| `GodotAudio.init()` ruft `ctx.audioWorklet.addModule(...)` ohne Schutz auf (A) | dieselbe Datei | **Bestätigt.** Ohne Secure Context gibt es `audioWorklet` nicht, der Aufruf wirft also einen Fehler. Im Browser muss Godots eigener Audiotreiber deshalb aus bleiben (`--audio-driver Dummy`), die Klänge laufen über eine eigene Web-Audio-Brücke. |
| „Godot-Web über http scheitert“ bzw. „läuft nur ohne Ton“ (B, Berichte android-infra und browser-iphone) | dieselbe Datei | **Nur halb richtig.** Das gilt für die Standardseite und für Godots eigenen Ton. Mit eigener Startseite und eigener Ton-Brücke ist der Weg nach dem Quelltext offen. Ein Lauf auf einem echten iPhone fehlt aber noch. |
| `godot.wasm` hat 37,7 MB roh und 9,5 MB komprimiert, `godot.js` 316 kB | Einträge im Zip | Bestätigt. |
| Von der Web-Crypto-API wird nur `crypto.getRandomValues` genutzt | `godot.js` | Bestätigt. `subtle` und `randomUUID` kommen nicht vor. |
| Die Web-Vorlagen liegen nur in `.tools\export\templates`, nicht in `%APPDATA%\Godot\export_templates\4.6.1.stable` (A) | Verzeichnislisten | Bestätigt. `setup.ps1` muss die Vorlagen mitkopieren. |
| Node.js und npm sind nicht installiert (C) | `Get-Command` | Bestätigt. B und C brauchen also ein portables Node. |
| Draw2Race nutzt den Mobile-Renderer (B) | `game/project.godot` | Bestätigt. Für Mau-Mau Flip halten alle drei Vorschläge den Compatibility-Renderer für richtig. |
| Neben `Mau-Mau Flip` existiert ein Ordner `Mau-Maul Flip` | Dateisystem | Bestätigt. Der Projektordner enthält nur `.git` und `LICENSE`. |

Die Zeilenzahlen unterscheiden sich zwischen den Vorschlägen, z. B. `net_session.gd` mit 548 Zeilen bei A und 594 bei B. Das liegt nur daran, ob Leerzeilen mitgezählt werden, und spielt für das Urteil keine Rolle.

---

## 2. Die drei Vorschläge in Kürze

**Was alle drei gemeinsam haben** (Kern):
- Der Host entscheidet allein.
- Jeder Spieler bekommt nur seine eigene Sicht (`view_for`).
- Gegnerhände kommen als sortierte Menge ohne Kennungen.
- Der Seed bleibt beim Host.
- WebSocket mit JSON ersetzt ENet. Die UDP-Suche gibt es nur für Apps, Browser kommen über einen QR-Link.
- Wiederverbinden per Token, Quick Share, Download unter `/apk` und „Update vom Host“.
- LocalOnlyHotspot (LOHS) mit WLAN-QR, Compatibility-Renderer und ein Lecktest.

Die Vorschläge unterscheiden sich fast nur in zwei Fragen: **Womit wird im Browser der Tisch gezeichnet, und in welcher Technik ist die App gebaut?**

- **A, godot-zentriert:**
  - Eine einzige Godot-Codebasis für App und Browser.
  - iPhones bekommen den Godot-Web-Export vom Host-Handy über http, mit eigener Startseite und ohne Godots eigenen Ton.
  - Ein harter iPhone-Test (M1) entscheidet früh. Als Plan B ist ein HTML-Client vorgesehen, der dasselbe Protokoll spricht.
  - Aufwand: 70–90 PT.
- **B, Godot-App plus Web-Client:**
  - Die App ist in Godot gebaut, Browser bekommen einen schlanken TypeScript/PixiJS-Client.
  - Der Host schickt auch mit, was gerade erlaubt ist (spielbare Karten, Abfragen, Hinweistexte). Der Client kennt deshalb keine einzige Regel.
  - Es gibt zwei Darstellungen, was rund 25 % Mehraufwand kostet. Aufwand: 77–112 PT.
- **C, web-zentriert:**
  - Alles ist TypeScript/PixiJS, auch der Regelkern (im Web Worker) und die App-Oberfläche.
  - Die Android-App ist eine Java-Hülle mit WebView. Darin laufen HTTP- und WebSocket-Server in einem Vordergrunddienst, dazu die Java-Helfer aus Draw2Race.
  - Godot fällt weg. Aufwand: 59–90 PT.

---

## 3. Bewertungstabelle

Punkte von 1 bis 5, 5 ist am besten. Beim Risiko heißt 5 „geringstes Risiko“.

Die Gewichte habe ich aus den Aussagen des Nutzers abgeleitet:
- Mehrfach „wie bei Draw2Race“: Darum zählt die Wiederverwendung.
- Hobbyprojekt: Darum zählen Aufwand und Wartbarkeit dreifach.
- iPhone-Spieler „erstmal“ per Browser: wichtig, aber nicht das Hauptziel.

| # | Kriterium | Gewicht | A godot-zentriert | B Godot + Web-Client | C web-zentriert | Synthese (A + Ideen aus B/C), bei bestandenem M1 |
|---|---|---|---|---|---|---|
| 1 | Erfüllung aller Anforderungen | 3 | 4 | 4 | 5 | 5 |
| 2 | Effektqualität Android | 2 | 5 | 5 | 4 | 5 |
| 3 | Spielerlebnis iPhone-Browser | 2 | 3 | 4 | 5 | 4 |
| 4 | Offline-Tauglichkeit inkl. APK-Weitergabe und Hotspot | 2 | 3 | 4 | 5 | 3 |
| 5 | Wiederverwendung Draw2Race | 2 | 5 | 4 | 2 | 5 |
| 6 | Aufwand und Wartbarkeit (Hobby + Claude) | 3 | 4 | 2 | 3 | 4 |
| 7 | Testbarkeit ohne iPhone/Mac | 1 | 3 | 4 | 5 | 4 |
| 8 | Technisches Risiko | 2 | 2 | 4 | 3 | 3 |
| | **Summe ungewichtet (max. 40)** | | **29** | **31** | **32** | **33** |
| | **Summe gewichtet (max. 85)** | | **63** | **64** | **67** | **71** |

**So ist die Synthese-Spalte zu lesen:**
- Die Spalte gilt nur für den Fall, dass der iPhone-Test M1 bestanden wird.
- Fällt M1 durch, landet die Synthese genau bei den Werten von B (64). Dann ist B gegen C (67) abzuwägen (siehe Abschnitt 6).
- Die Abstände sind klein. **Die Unsicherheit in den Schätzungen ist größer als die Punktunterschiede.** Entscheidend ist deshalb die Reihenfolge der Schritte, nicht die Summe.

---

## 4. Begründung je Kriterium

**(1) Anforderungen**
- Alle drei decken jede Anforderung ab.
- C bietet als einziger sicher die gleiche Optik auf dem iPhone. Bei A gilt das nur, wenn M1 besteht. B liefert auf dem iPhone bewusst eine „Lite“-Fassung (nach eigener Schätzung 75–85 % des optischen Eindrucks).
- Das „Update wie bei Draw2Race“ übernehmen A und B 1:1. C portiert den Updater nach Java: gleiche Funktion, aber erprobter Code wird ersetzt.

**(2) Effektqualität Android**
- A und B zeichnen nativ in Godot. Glühen entsteht über additive Texturen statt 2D-HDR; das akzeptieren alle drei.
- C zeichnet mit PixiJS in der System-WebView. Für einen 2D-Kartentisch reicht das in der Regel.
- Bei C kommen aber zusätzliche Unsicherheiten dazu: gleichmäßige Bildfolge, Pausen der Speicherbereinigung und alte WebView-Versionen auf Urlaubshandys. C macht deshalb selbst „S10 ≥ 50 fps“ zum Abbruchkriterium.

**(3) iPhone-Browser**
- **C ist hier am besten:** gleicher Code, Client unter 2 MB, schneller Start, ausgereifte PixiJS/WebGL2-Unterstützung in Safari.
- **B** nutzt dieselbe Technik, aber mit bewusst reduzierten Effekten.
- **A** sieht gleich aus, wenn es läuft. Dafür muss jeder Gast etwa 10 MB WASM (komprimiert) plus das `.pck` laden, die Kompilierzeit abwarten, und GDScript läuft in WASM langsamer. Godots eigener Ton fällt weg und wird durch die Brücke ersetzt. Dazu kommen bekannte iOS-Probleme: „WebGL context lost“ und Neuladen bei Speichermangel.
- Nach Risiko gewichtet bekommt A deshalb 3 Punkte.

**(4) Offline**
Quick Share, `/apk`, „Update vom Host“, LOHS und WLAN-QR sind überall gleich. Die Unterschiede:
- **APK-Größe:** C 8–25 MB (Schätzung), A 40–55 MB einschließlich Web-Export, B dazwischen.
- **Daten je Browser-Gast und Sitzung:** A 12–15 MB, B und C unter 2 MB.
- **Server, wenn die Host-Activity pausiert:** Bei C laufen sie in Java im Vordergrunddienst weiter. Bei A und B läuft HTTP in einem GDScript-Thread weiter, der WebSocket hängt an der Hauptschleife, und die Gäste sehen „Host pausiert“.

Neuer Befund der Jury: Seit Android 11 wählt der Hotspot bei jedem Einschalten ein zufälliges Subnetz. Die Seitenadresse ändert sich damit je Sitzung, und Browser-Cache und `localStorage` gelten nur bis zum nächsten Hotspot-Start. Das trifft A am stärksten, weil der große Download jede Sitzung neu anfällt.

**(5) Wiederverwendung**
- **A** übernimmt fast alles: Updater, NetHelper/NetAndroid, Suche, Testgerüst, Build und Doku-Struktur. Das spart etwa 8–12 PT.
- **B** übernimmt dasselbe für die App, baut aber einen zweiten Client.
- **C** behält rund 350 Java-Zeilen direkt, portiert etwa 1000 Zeilen nach Java und baut die Werkzeugkette neu auf.

**(6) Aufwand und Wartbarkeit**
- **A:** Eine Oberfläche im bekannten Stack. Der Sonderweg (Startseite, Ton-Brücke, gzip-Server) kostet etwa 5–7 PT. Das Dauerrisiko: Jedes Godot-Update kann den Sonderweg brechen. Gegenmittel: Godot auf 4.6.x festhalten und vor jedem Update einen Regressionstest fahren.
- **B:** Zwei Oberflächen in zwei Sprachen plus Java. Jede Feinschliff-Runde an Hand und Effekten fällt doppelt an, und B hat die höchste Gesamtsumme.
- **C:** Eine Oberfläche, zwei Sprachen. Lobby und Optionen sind im DOM leichter zu bauen, und Live-Reload auf dem Handy beschleunigt die Feinarbeit am Spielgefühl. Dagegen stehen eine neue Werkzeugkette und ein deutlich größerer Java-Teil (Server, Suche, Bridge, Dienst, Updater). Die Schätzung von 59–90 PT halte ich für optimistisch.

**(7) Testbarkeit**
- **C ist hier am besten:** Regelkern mit Vitest in Node, die echte Oberfläche mit Playwright-WebKit, Mobile Safari im iOS-Simulator auf einem GitHub-macOS-Runner, ein PC-Host in Node.
- **B:** Golden Files in beide Richtungen, Playwright für den Client, Godot headless für den Rest.
- **A:** Stark bei Protokoll und Logik, denn die headless Godot-Mitspieler sind derselbe Code wie der Web-Export. Aber die Godot-Zeichenfläche ist für Playwright undurchsichtig und braucht einen Test-Haken. Ob WebGL2 in Playwright-WebKit unter Windows läuft, ist unbelegt.
- Alle drei brauchen vor dem Einsatz ein echtes iPhone.

**(8) Risiko**
- **A** hat das größte Einzelrisiko: eine Konfiguration, die Godot nicht unterstützt. Dieses Risiko ist aber an einer Stelle gebündelt, früh prüfbar, und der Rückfall kostet wegen des JSON-Protokolls fast nichts.
- **C** hat viele mittlere Risiken: WebView-Leistung, Bridge, WebView im Hintergrund, Stack-Wechsel. Jede Einzeltechnik ist Standard; das Risiko liegt im Gesamtumbau.
- **B** hat das geringste technische Risiko. Sein Risiko ist organisatorisch: zwei Oberflächen, die auseinanderlaufen.

---

## 5. Fehler und Lücken in den Vorschlägen (Befunde der Jury)

1. **B lehnt Godot-Web mit veralteten Angaben ab.** „Ohne AudioWorklet kein Ton“ stimmt nur für Godots eigenen Audiotreiber. A beschreibt einen gangbaren Weg (Dummy-Treiber plus eigene Web-Audio-Brücke), und der ist im Quelltext nachvollziehbar.
2. **C testet Mobile Safari im Simulator über `http://localhost`.** `localhost` gilt im Browser als Secure Context. Genau die echte Lage (http im lokalen Netz) würde dieser Test also nicht nachstellen. Richtig ist die Netzwerk-IP des Runners. A weist für Playwright korrekt darauf hin.
3. **Wechselnde Adresse je Hotspot-Sitzung** (steht in keinem Vorschlag): Mit dem zufälligen Subnetz gelten Token, gespeicherter Name und HTTP-Cache nur innerhalb einer Sitzung. Folgen:
   - Bei A laden die Gäste jedes Mal 12–15 MB.
   - Bei allen wird der vierstellige Platzcode aus B als Notweg wichtig.
   - `Cache-Control: immutable` hilft nur innerhalb derselben Sitzung.
4. **C: Die versionCode-Formel `X*10000+Y*100+Z` läuft über**, sobald Betas die letzte Stelle über 99 zählen. Draw2Race steht schon bei 0.2.31. B rechnet mit `X*1_000_000+Y*1_000+Z` sicher.
5. **A: Die Ports 8080/8081** sind typische Ports lokaler Entwicklungsserver und kollidieren leicht bei PC-Tests. B nutzt den Bereich 24690–24693 direkt neben Draw2Race (24680–24682); das ist besser.
6. **A: JSON-Zahlen.** Godot liefert beim Parsen alle Zahlen als Float. B prüft und wandelt ausdrücklich um, A erwähnt das nicht.
7. **A: Der Client berechnet die spielbaren Karten selbst.** Bei Hausregeln (Stapeln, Bluff-Modi, Reinwerfen) ist `hints_for` vom Host aus B robuster, und Plan B wird damit fast kostenlos.
8. **Alle Aufwandszahlen sind Selbstschätzungen.**
   - Die 5–7 PT, die A für den Godot-Web-Sonderweg ansetzt, sind ohne eigenes iPhone knapp, denn die Fehlersuche über ein Fern-Log dauert.
   - C unterschätzt vermutlich die Java-Portierungen, die Bridge, den Vordergrunddienst und den Neuaufbau der Werkzeugkette, zusammen grob 10–15 PT.
9. **C [ungeprüft]:** Ein Vordergrunddienst hält den App-Prozess am Leben, aber nicht automatisch den Renderer-Prozess einer unsichtbaren WebView. `setRendererPriorityPolicy` wäre dafür zu prüfen.

---

## 6. Urteil

**Die Einzelvorschläge**
- **C liegt nach Punkten knapp vorn.** C hat die beste iPhone-Erfahrung, die beste Testbarkeit, die kleinste APK und die robustesten Server. Der Preis: Godot und die Draw2Race-Basis fallen komplett weg, die Werkzeugkette ist neu, und der Java-Teil ist groß. Das alles würde fällig, bevor feststeht, dass der Godot-Weg das iPhone nicht genauso bedienen kann.
- **B** ist technisch am sichersten, auf Dauer aber am teuersten, weil es zwei Oberflächen gibt.
- **A** hat das größte Einzelrisiko. Es ist aber der einzige Vorschlag, der die Architekturfrage mit Messwerten statt mit Annahmen entscheidet: Ein Test von rund einer Woche klärt die iPhone-Frage, bevor Regelkern und Oberfläche entstehen. Das JSON-Protokoll hält Plan B ohne Mehrkosten offen.

**Entscheidung der Jury**
- A wird die Grundlage, aber strikt in der Reihenfolge „erst testen, dann bauen“.
- Ergänzt wird A um die Host-Hinweise (`hints_for`) und die Härtung aus B sowie um die Safari- und Testideen aus C.
- Besteht M1, ist das Ergebnis (71) besser als jeder Einzelvorschlag.
- Fällt M1 durch, sind erst etwa 6 PT verbraucht. Dann entscheidet der Nutzer mit echten Messwerten zwischen zwei Wegen:
  - **B:** Die Godot-App bleibt, iPhones bekommen die „Lite“-Optik. Das ist der Standard, wenn das iPhone ein Nebenziel bleibt.
  - **C:** Kompletter Stack-Wechsel, iPhones bekommen die gleiche Optik.

**Ausnahme:** Wer die gleiche Optik auf dem iPhone von Anfang an zur Pflicht macht und den Abschied von Godot nicht scheut, sollte gleich C wählen. Das ist die zentrale offene Entscheidung des Nutzers.