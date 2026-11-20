# Kontrollbilder

Hier liegen die Kontrollbilder ab Beta 1.6.12 als JPEG (`optik_<Stand>_*.jpg`, `optik_gluecksspiel_regler_*.jpg` …).

Die älteren PNG-Kontrollbilder (Beta 0.1.1 bis 1.6.11, 426 Dateien, 433 MB) wurden am 20.11.2026 beim Aufräumen aus dem Arbeitsordner entfernt. Sie stehen weiter in der Git-Geschichte, Berichte und Code-Kommentare, die auf sie verweisen, gelten für diesen Stand.

Einzelnes Bild zurückholen:

```powershell
git checkout 177793e -- "docs/module/optik_142_regen_tag.png"
```

Alle PNG-Bilder anzeigen, die es damals gab:

```powershell
git ls-tree --name-only 177793e docs/module/ | Select-String '\.png$'
```

Die Shot-Tests (`game/tests/*_shot.gd`) schreiben ohne `SHOT_DIR` weiter PNG hierher. Neue Kontrollbilder bitte als JPEG ins Repo legen (wie seit Beta 1.6.12), die PNG-Ausgabe nur lokal ansehen.
