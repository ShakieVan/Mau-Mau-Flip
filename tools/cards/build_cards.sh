#!/bin/bash
# Mau-Mau Flip, Modul B: Kartenbilder, Bediensymbole, Farbsymbole, App-Symbole, Logo und Startbild erzeugen.
# Quelle: tools/cards/*.js (Entwurf A „Papier & Neon“), Chrome ohne Fenster rendert Bögen, ffmpeg schneidet aus.
# Aufruf (Git Bash mit perl und brotli, Chrome, ffmpeg ab 7; Schriften in game/assets/fonts/):
#   bash tools/cards/build_cards.sh                 alles
#   bash tools/cards/build_cards.sh karten bogen    nur einzelne Schritte (karten symbole app logo splash schriften bogen)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CHROME="${CHROME:-/c/Program Files/Google/Chrome/Application/chrome.exe}"
WORK="$(cygpath -u "${TEMP:-/tmp}")/mmf_build_cards"        # Zwischendateien außerhalb des Projekts
UDD="$(cygpath -m "$WORK")/chrome_profil"                   # eigenes Chrome-Profil für den Lauf ohne Fenster
URL="file:///$(cygpath -m "$HERE" | sed 's/ /%20/g')"
CARDS="$ROOT/game/assets/cards"; UI="$ROOT/game/assets/ui"; WEB="$ROOT/webclient/cards"; DOCS="$ROOT/docs/module"
mkdir -p "$WORK" "$CARDS" "$UI/farben" "$WEB" "$DOCS"
for f in BricolageGrotesque.ttf Fraunces.ttf Fraunces-Italic.ttf; do
  [ -s "$ROOT/game/assets/fonts/$f" ] || { echo "Schrift fehlt: game/assets/fonts/$f"; exit 1; }
done
# ffmpeg ab 7 (Filtergraph aus Datei per -/filter_complex), getestet mit 9.0.1
FFV="$(ffmpeg -hide_banner -version 2>/dev/null | sed -n 's/^ffmpeg version n\{0,1\}\([0-9]*\).*/\1/p')"
[ -n "$FFV" ] && [ "$FFV" -ge 7 ] || { echo "ffmpeg 7 oder neuer nötig (gefunden: ${FFV:-keins})"; exit 1; }

chrome() { "$CHROME" --headless=new --disable-gpu --user-data-dir="$UDD" --hide-scrollbars --force-device-scale-factor=1 \
  --default-background-color=00000000 --virtual-time-budget=10000 "$@" 2>/dev/null; }
win() { cygpath -m "$1"; }

# bogen <name>: Lage der Bilder lesen (#out per --dump-dom), dann Screenshot in genau dieser Größe → $WORK/<name>.png
bogen() {
  local name="$1" dom="$WORK/$1.dom" man="$WORK/$1.txt" png="$WORK/$1.png" W H
  chrome --dump-dom "$URL/render.html?blatt=$name" | tr -d '\r' > "$dom" || true
  if grep -q '^@@ERROR' "$dom"; then sed -n '/^@@ERROR/,/^<\/script>/p' "$dom" | head -20; exit 1; fi
  grep '^@@' "$dom" > "$man" || { echo "Bogen $name: keine Ausgabe"; exit 1; }
  grep -q '^@@FONTS ok' "$man" || { echo "Bogen $name: Schriften nicht geladen"; grep '^@@FONTS' "$man"; exit 1; }
  read -r _ W H < <(grep '^@@SIZE' "$man")
  rm -f "$png"
  chrome --window-size="$W,$H" --screenshot="$(win "$png")" "$URL/render.html?blatt=$name" > /dev/null || true
  [ -s "$png" ] || { echo "Bogen $name: Screenshot fehlt"; exit 1; }
  local got; got="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$png")"
  [ "$got" = "${W}x${H}" ] || { echo "Bogen $name: Screenshot $got statt ${W}x${H}"; exit 1; }
  # Der Screenshot ist ein zweiter Chrome-Lauf: render.html fügt die Bilder nur ein, wenn die Schriften geladen sind.
  # Ein leerer Bogen fiele beim Schneiden nicht auf, deshalb hier die Deckung jedes Bildes prüfen (Karten fast voll deckend).
  local min=8; [ "$name" = karten ] && min=240
  deckung "$name" "$min"
  echo "Bogen $name: ${W}x${H}, $(grep -c '^@@ITEM' "$man") Bilder"
}

# deckung <name> <mindestens>: mittleres Alpha (0–255) jedes Bildes im Screenshot, ein ffmpeg-Lauf (je Bild auf 1×1 gemittelt,
# nebeneinander als eine Zeile ausgegeben). Bricht ab, wenn ein Bild unter <mindestens> liegt.
deckung() {
  local name="$1" min="$2" graph="$WORK/$1.deckung" n=0 chains="" ins="" splits="" key x y w h i
  local -a keys=() alpha=()
  while read -r _ key x y w h; do
    chains+="[d$n]crop=$w:$h:$x:$y,format=rgba,scale=1:1:flags=area[a$n];"
    ins+="[a$n]"; splits+="[d$n]"; keys+=("$key"); n=$((n + 1))
  done < <(grep '^@@ITEM' "$WORK/$name.txt")
  if [ "$n" -gt 1 ]; then chains+="${ins}hstack=inputs=$n[out]"; else chains+="${ins}null[out]"; fi
  printf '[0:v]split=%d%s;%s' "$n" "$splits" "$chains" > "$graph"
  mapfile -t alpha < <(ffmpeg -hide_banner -v error -i "$(win "$WORK/$name.png")" -/filter_complex "$(win "$graph")" \
    -map "[out]" -frames:v 1 -f rawvideo -pix_fmt rgba - | od -An -v -tu1 -w4 | awk '{print $4}')
  [ "${#alpha[@]}" -eq "$n" ] || { echo "Bogen $name: Deckungsprüfung lieferte ${#alpha[@]} statt $n Werte"; exit 1; }
  local bad=0 lo=255
  for ((i = 0; i < n; i++)); do
    [ "${alpha[$i]}" -lt "$lo" ] && lo="${alpha[$i]}"
    if [ "${alpha[$i]}" -lt "$min" ]; then echo "Bogen $name: ${keys[$i]} leer oder unvollständig (Deckung ${alpha[$i]}/255, mindestens $min)"; bad=$((bad + 1)); fi
  done
  [ "$bad" -eq 0 ] || exit 1
  echo "Bogen $name: Deckung geprüft, kleinste $lo/255"
}

# schneiden <name> <regel>: ein ffmpeg-Lauf schneidet alle Bilder eines Bogens aus.
# Die Regel-Funktion bekommt <schlüssel> <breite> <höhe> und gibt Zeilen "art|ziel[|breite|höhe]" aus (art: png, png_skaliert, webp).
schneiden() {
  local name="$1" regel="$2" graph="$WORK/$1.filter" n=0 key x y w h
  local -a outs=()
  : > "$graph"
  local chains=""
  while read -r _ key x y w h; do
    while IFS="|" read -r art ziel sw sh; do
      [ -n "$art" ] || continue
      local lbl="o$n"
      case "$art" in
        png)  chains+="[s$n]crop=$w:$h:$x:$y[$lbl];"
              outs+=(-map "[$lbl]" -c:v png -pred mixed "$(win "$ziel")") ;;
        png_skaliert) chains+="[s$n]crop=$w:$h:$x:$y,format=rgba,premultiply=inplace=1,scale=$sw:$sh:flags=lanczos,unpremultiply=inplace=1[$lbl];"
              outs+=(-map "[$lbl]" -c:v png -pred mixed "$(win "$ziel")") ;;
        webp) chains+="[s$n]crop=$w:$h:$x:$y,format=rgba,premultiply=inplace=1,scale=$sw:$sh:flags=lanczos,unpremultiply=inplace=1,format=bgra[$lbl];"
              outs+=(-map "[$lbl]" -c:v libwebp -quality 85 -compression_level 6 "$(win "$ziel")") ;;
      esac
      n=$((n + 1))
    done < <("$regel" "$key" "$w" "$h")
  done < <(grep '^@@ITEM' "$WORK/$name.txt")
  local splits=""; for ((i = 0; i < n; i++)); do splits+="[s$i]"; done
  printf '[0:v]split=%d%s;%s' "$n" "$splits" "${chains%;}" > "$graph"
  ffmpeg -hide_banner -v error -y -i "$(win "$WORK/$name.png")" -/filter_complex "$(win "$graph")" "${outs[@]}"
  echo "Bogen $name: $n Dateien geschrieben"
}

regel_karten()  { echo "png|$CARDS/$1.png"; echo "webp|$WEB/$1.webp|200|311"; }
regel_symbole() {
  case "$1" in
    ui_*)    echo "png|$UI/${1#ui_}.png" ;;
    farbe_*) echo "png|$UI/farben/${1#farbe_}.png"; echo "webp|$WEB/$1.webp|$2|$3" ;;
  esac
}
regel_app() {
  case "$1" in
    icon_512)            echo "png|$UI/icon_512.png"; echo "png_skaliert|$UI/android_main_192.png|192|192" ;;
    icon_eckig_512)      echo "png_skaliert|$UI/touch_icon_180.png|180|180" ;;
    adaptive_background) echo "png|$UI/android_adaptive_background_432.png" ;;
    adaptive_foreground) echo "png|$UI/android_adaptive_foreground_432.png" ;;
    adaptive_monochrome) echo "png|$UI/android_adaptive_monochrome_432.png" ;;
  esac
}
regel_logo()   { echo "png|$UI/logo.png"; echo "png_skaliert|$UI/logo_klein.png|800|450"; }
regel_splash() { echo "png|$UI/splash.png"; }

# schriften: TTF und OFL.txt aus game/assets/fonts nach webclient/fonts spiegeln, dazu WOFF2 (woff2.pl, Plan Abschnitt 8).
# schriften.html lädt TTF und WOFF2 im Browser und vergleicht die gezeichneten Glyphen Pixel für Pixel.
schriften() {
  local f src="$ROOT/game/assets/fonts" dst="$ROOT/webclient/fonts" dom="$WORK/schriften.dom"
  mkdir -p "$dst"
  for f in BricolageGrotesque.ttf Fraunces.ttf Fraunces-Italic.ttf OFL.txt; do cmp -s "$src/$f" "$dst/$f" || cp "$src/$f" "$dst/$f"; done
  for f in BricolageGrotesque Fraunces Fraunces-Italic; do perl "$HERE/woff2.pl" "$src/$f.ttf" "$dst/$f.woff2"; done
  chrome --dump-dom "$URL/schriften.html" | tr -d '\r' > "$dom" || true
  grep '^@@' "$dom" || { echo "Schriftprüfung: keine Ausgabe"; exit 1; }
  grep -q '^@@SCHRIFTEN ok' "$dom" || { echo "Schriftprüfung: WOFF2 fehlt oder weicht von der TTF ab"; exit 1; }
}

# Kontrollbogen aller 109 Kartenbilder aus game/assets/cards → docs/module/B_kartenbogen.png
kontrollbogen() {
  local dom="$WORK/bogen.dom" W H
  chrome --dump-dom "$URL/kontrollbogen.html" | tr -d '\r' > "$dom" || true
  grep -q '^@@BOGEN' "$dom" || { echo "Kontrollbogen: keine Ausgabe"; exit 1; }
  grep '^@@' "$dom"
  read -r _ W H _ < <(grep '^@@BOGEN' "$dom")
  chrome --window-size="$W,$H" --screenshot="$(win "$DOCS/B_kartenbogen.png")" "$URL/kontrollbogen.html" > /dev/null || true
  grep -q '^@@BOGEN .* OK$' "$dom" || { echo "Kontrollbogen: Bilder fehlen oder haben die falsche Größe"; exit 1; }
}

schritte=("$@"); [ ${#schritte[@]} -gt 0 ] || schritte=(karten symbole app logo splash schriften bogen)
for s in "${schritte[@]}"; do
  case "$s" in
    karten|symbole|app|logo|splash) bogen "$s"; schneiden "$s" "regel_$s" ;;
    schriften) schriften ;;
    bogen) kontrollbogen ;;
    *) echo "Unbekannter Schritt: $s"; exit 1 ;;
  esac
done
echo "Fertig."
