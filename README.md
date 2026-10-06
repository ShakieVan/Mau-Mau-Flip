# Mau-Mau Flip

Mau-Mau mit Wendekarten für Android. Jede Karte hat eine **helle Seite** (Rot, Gelb, Grün, Blau) und eine **dunkle Seite** (Pink, Türkis, Orange, Lila). Wer eine Flip-Karte legt, dreht den ganzen Tisch um – aus Tag wird Nacht, aus „Zieh 1“ wird „Zieh 5“. Und weil man von den Karten der anderen immer die Gegenseite sieht, weiß man ungefähr, was nach dem nächsten Flip auf einen zukommt.

**Version 0.1.1 (Beta)** · Godot 4.6.1 · offline spielbar · nicht-kommerzielles Hobbyprojekt

## Spielen

1. Unter [Releases](../../releases) (reguläre Versionen) bzw. im [Beta-Repo](https://github.com/ShakieVan/Mau-Mau-Flip-Beta/releases) (Testversionen) die Datei `MauMauFlip-<Version>.apk` herunterladen. Spätere Updates bietet die App selbst an.
2. Auf dem Android-Handy öffnen und die Installation erlauben („Installation aus unbekannten Quellen“).

### Drei Spielarten

- **Übungsspiel** gegen 1–5 Computergegner.
- **Auf einem Handy:** Das Handy wird reihum weitergereicht. Vor jedem Zug verdeckt ein Sichtschutz alle Karten.
- **Im WLAN:** Ein Handy eröffnet das Spiel. Mitspieler treten mit der App bei (sie finden das Spiel automatisch) oder **im Browser** – etwa auf dem iPhone – über den QR-Code des Gastgebers. Internet braucht dafür niemand.

### Ohne Internet im Urlaub

- **Hotel-WLAN:** Dort sehen sich die Geräte oft nicht. Dann den Hotspot des Gastgeber-Handys einschalten und alle damit verbinden.
- **App teilen:** Die App gibt sich selbst weiter – über das Teilen-Menü (z. B. Quick Share) oder als Download auf der Seite des Gastgebers (`http://<Adresse>:24690/apk`).

## Bedienung

- **Ausspielen:** Karte nach oben wischen oder zweimal antippen. Wünscher zur Ablage ziehen und auf eine der vier Farben fallen lassen.
- **Ziehen:** auf den Nachziehstapel tippen.
- **Hilfe zu einer Karte:** Karte gedrückt halten und nach unten auf „?“ ziehen.
- **Sortieren:** Farbe, Wert, Punkte oder von Hand (Karte halten und seitlich ziehen).
- **Rückseiten:** Knopf gedrückt halten, um die eigenen Rückseiten zu sehen. Tipp auf die Karten eines Mitspielers zeigt dessen Rückseiten groß.
- **„Mau!“** rufen, wenn man nur noch eine Karte hat – sonst können die anderen „Erwischt!“ drücken.
- **Spielbare Karten hervorheben** lässt sich in den Einstellungen abschalten – nur für das eigene Gerät.

## Regeln und Hausregeln

Voreinstellungen „Offiziell“, „Familie“, „Mau-Mau-Tradition“ und „Klassisch 500“; dazu lassen sich einzeln einstellen: bis zum Letzten spielen, Ziehkarten stapeln, nach dem Strafziehen weiterspielen, Bluff mit Anzweifeln oder von der App erzwungen, Ziehen bis spielbar, Mau-Ansage (Erwischen, automatisch, nur Erinnerung), Rückseiten der Mitspieler sichtbar oder verdeckt, Punkte bis 500. Eigene Einstellungen lassen sich unter einem Namen speichern; App-Mitspieler merken sich die Regeln des Gastgebers und können damit selbst ein Spiel eröffnen.

### Zusatzkarten (Hausregeln)

- **Kartentausch:** Alle geben ihre ganze Hand an den Nachbarn weiter – im Uhrzeigersinn oder in Spielrichtung. In „Familie“ an.
- **Glücksspiel:** Joker mit Glücksspielknopf. Wer ihn legt, setzt reihum eine Karte verdeckt und drückt den Knopf. Nach jeder Niete heißt es: noch eine Karte riskieren oder aufhören? Wer aufhört, wird den Einsatz los; ein Treffer bringt 1–10 Karten und den Einsatz zurück auf die Hand.
- **Farbe mit ablegen:** Alle eigenen Karten dieser Farbe kommen mit auf die Ablage (als Joker: Farbe wählen). Mitabgelegte Aktionskarten wirken nicht.

## Selbst bauen

```powershell
./tools/setup.ps1              # Godot 4.6.1 und Exportvorlagen nach .tools/
./tools/build.ps1 -Target Test # alle Headless-Prüfungen
./tools/build.ps1 -Target All  # Browser-Client, Windows- und Android-Build nach builds/
```

Android benötigt zusätzlich JDK 17, das Android-SDK und den Signaturschlüssel in `.tools/` (nicht im Repo).

## Unterlagen

- [Projektkontext und Entscheidungen](AGENTS.md)
- [Bauplan der Beta](docs/BETA1_PLAN.md) und [Module](docs/module/)
- [Recherche](docs/recherche/README.md): Regeln, Netz ohne Internet, Browser-Gäste, Hand und Effekte
- [Gestaltung „Papier & Neon“](art/entwurf/a-papier-neon/README.md)
- [Mau-Ton und Katzen](audio/entwurf/mau/README.md), [Spieltöne](audio/sfx_README.md)

## Herkunft und Lizenzen

Mau-Mau Flip steht unter **[CC BY-NC 4.0](LICENSE)**: Teilen und Verändern mit Namensnennung erlaubt, kommerzielle Nutzung nicht.

- **Spielprinzip:** Mau-Mau mit doppelseitigen Karten. Gestaltung, Karten, Symbole und Töne sind eigene Arbeiten.
- **Engine:** [Godot Engine](https://godotengine.org) (MIT).
- **Schriften:** Bricolage Grotesque und Fraunces (SIL Open Font License 1.1), `game/assets/fonts/OFL.txt`.
- **Katze in Logo und App-Symbol:** KI-Illustration, vom Autor erzeugt.
- **„Mau!“ und „Mau-Mau!“:** Aufnahmen des Autors, aufbereitet mit `tools/make_mau_aufnahmen.sh`.
- **Spieltöne:** KI-erzeugt mit [MOSS-SoundEffect v2.0](https://huggingface.co/OpenMOSS-Team/MOSS-SoundEffect-v2.0) (Apache 2.0), nachbearbeitet mit `tools/make_sfx_moss.py`; Einzelheiten in `audio/sfx_README.md`.
