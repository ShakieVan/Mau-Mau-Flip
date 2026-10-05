#!/bin/bash
# Mau-Mau Flip, Entwurf A: erzeugt Karten-SVGs, Logo, App-Symbol und Vorschauseiten
# aus quelle/*.js (über Chrome ohne Fenster) und rendert die PNG-Vorschauen.
# Aufruf (Git Bash): bash quelle/build.sh   [--keine-png]
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(dirname "$HERE")"
CHROME="${CHROME:-/c/Program Files/Google/Chrome/Application/chrome.exe}"
WIN_OUT="$(cygpath -m "$OUT")"
URL="file:///$(echo "$WIN_OUT" | sed 's/ /%20/g')"
TMP="$OUT/.build_ausgabe.txt"
UDD="$(cygpath -m "${TEMP:-/tmp}")/mmf_chrome_profil"   # eigenes Chrome-Profil fuer den Lauf ohne Fenster

"$CHROME" --headless=new --disable-gpu --user-data-dir="$UDD" --dump-dom "$URL/quelle/build.html" 2>/dev/null > "$TMP" || true
grep -q "^@@FILE" "$TMP" || { echo "Build-Seite lieferte keine Ausgabe"; exit 1; }
if grep -q '^@@ERROR' "$TMP"; then sed -n '/^@@ERROR/,$p' "$TMP" | head -20; exit 1; fi
mkdir -p "$OUT/cards"
awk -v dir="$OUT" '
  { sub(/\r$/, "") }
  /^@@FILE / { f = dir "/" substr($0, 8); next }
  /^@@END$/  { if (f) close(f); f = ""; next }
  f { print > f }
' "$TMP"
rm -f "$TMP"
echo "Dateien geschrieben: $(ls "$OUT/cards" | wc -l) Karten, logo.svg, icon.svg, hand.html, preview.html"

[ "$1" = "--keine-png" ] && exit 0
shot() { # shot <datei> <breite> <hoehe> <png>
  "$CHROME" --headless=new --disable-gpu --user-data-dir="$UDD" --hide-scrollbars --virtual-time-budget=6000 \
    --default-background-color=00000000 --window-size=$2,$3 \
    --screenshot="$WIN_OUT/$4" "$URL/$1" 2>&1 | grep -E "written" || true
}
shot preview.html 1600 "${PREVIEW_H:-3200}" preview.png
shot hand.html 1600 720 hand.png
shot logo.svg 1600 900 logo.png
shot icon.svg 512 512 icon.png
