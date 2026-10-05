#!/usr/bin/env bash
# Prüfbilder für den Entwurfsvergleich (art/entwurf/VERGLEICH.md).
# Rendert die 16 geforderten Karten jeder Richtung einzeln (mit den Schriften der
# jeweiligen Richtung), setzt daraus je Richtung einen Kartenbogen und einen
# Streifentest (Fächer, 22 dp sichtbar, nur oberer Kartenteil) zusammen und
# rendert danach farbsehschwaeche.html und index.html.
# Die Entwürfe selbst werden nur gelesen, nie verändert.
#
# Aufruf (Git Bash):  bash art/entwurf/_pruefung/pruefbilder.sh [TEMP-ORDNER]
# Der Temp-Ordner sollte einen kurzen Pfad haben (Chrome scheitert an Pfaden > 260 Zeichen).
set -euo pipefail

HIER="$(cd "$(dirname "$0")" && pwd)"
ENTWURF="$(dirname "$HIER")"
TMP="${1:-$(mktemp -d)}"
mkdir -p "$TMP/k"
CHROME="/c/Program Files/Google/Chrome/Application/chrome.exe"

url()  { local p; p="$(cygpath -m "$1")"; echo "file:///${p// /%20}"; }
win()  { cygpath -m "$1"; }
shot() { # shot <html> <png> <breite> <hoehe> [transparent]
  local extra=()
  [ "${5:-}" = transparent ] && extra=(--default-background-color=00000000)
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --virtual-time-budget=4000 \
    "${extra[@]}" --window-size="$3,$4" --screenshot="$(win "$2")" "$(url "$1")" >/dev/null 2>&1
}

declare -A ORDNER=( [a]=a-papier-neon [b]=b-art-deco [c]=c-geometrisch )
declare -A FONTS=(
  [a]='https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wdth,wght@12..96,75..100,200..800&family=Fraunces:ital,opsz,wght,SOFT,WONK@0,9..144,100..900,0..100,0..1;1,9..144,100..900,0..100,0..1&display=block'
  [b]='https://fonts.googleapis.com/css2?family=Limelight&family=Josefin+Sans:wght@400;600;700&display=block'
  [c]='https://fonts.googleapis.com/css2?family=Jost:wght@400;500;600;700;800;900&display=block'
)
# Kartenbogen: je Funktion ein Paar hell/dunkel
HELL=(hell_rot_7 hell_gelb_plus1 hell_gruen_aussetzen hell_blau_richtungswechsel hell_rot_flip hell_wuenscher hell_wuenscher_plus2 hell_blau_9)
DUNKEL=(dunkel_tuerkis_7 dunkel_pink_plus5 dunkel_orange_alle_aussetzen dunkel_lila_richtungswechsel dunkel_pink_flip dunkel_wuenscher dunkel_farbjagd dunkel_lila_6)
TITEL=("Zahl 7" "Zieh 1 · Zieh 5" "Aussetzen · Alle" "Richtungswechsel" "Flip" "Wünscher" "Wünscher +2 · Farbjagd" "9 · 6")
# Streifentest: nach Farbe sortiert wie in einer Hand
FAECHER_HELL=(hell_rot_7 hell_rot_flip hell_gelb_plus1 hell_gruen_aussetzen hell_blau_richtungswechsel hell_blau_9 hell_wuenscher hell_wuenscher_plus2)
FAECHER_DUNKEL=(dunkel_pink_plus5 dunkel_pink_flip dunkel_tuerkis_7 dunkel_orange_alle_aussetzen dunkel_lila_richtungswechsel dunkel_lila_6 dunkel_wuenscher dunkel_farbjagd)

for x in a b c; do
  d="${ORDNER[$x]}"
  # 1. Einzelkarten
  for k in "${HELL[@]}" "${DUNKEL[@]}"; do
    h="$TMP/k/${x}_$k.html"
    {
      printf '<!doctype html><html><head><meta charset="utf-8"><link href="%s" rel="stylesheet">' "${FONTS[$x]}"
      printf '<style>html,body{margin:0;background:transparent;overflow:hidden}svg{display:block;width:560px;height:870px}</style></head><body>'
      sed -e 's/<?xml[^>]*?>//' "$ENTWURF/$d/cards/$k.svg"
      printf '</body></html>'
    } > "$h"
    shot "$h" "$TMP/k/${x}_$k.png" 560 870 transparent
  done

  # 2. Kartenbogen (4 Spalten, je Paar hell über dunkel)
  b="$TMP/bogen_$x.html"
  {
    echo '<!doctype html><html><head><meta charset="utf-8"><style>'
    echo 'html,body{margin:0;background:#3a3c46;font:600 20px/1.2 "Segoe UI",Arial,sans-serif;color:#d9dae2}'
    echo '.g{display:grid;grid-template-columns:repeat(4,230px);gap:14px 20px;padding:28px 30px}'
    echo '.p{display:flex;flex-direction:column;gap:12px;align-items:center}.p img{width:230px;height:357px;display:block}'
    echo '.t{text-align:center;font-size:19px;margin-top:2px}</style></head><body><div class="g">'
    for i in 0 1 2 3 4 5 6 7; do
      printf '<div class="p"><img src="%s"><img src="%s"><div class="t">%s</div></div>\n' \
        "$(url "$TMP/k/${x}_${HELL[$i]}.png")" "$(url "$TMP/k/${x}_${DUNKEL[$i]}.png")" "${TITEL[$i]}"
    done
    echo '</div></body></html>'
  } > "$b"
  shot "$b" "$HIER/kartenbogen_$x.png" 1040 1592

  # 3. Streifentest: Karte 80 dp breit (160 px bei Dichte 2), 22 dp (44 px) sichtbar, obere Hälfte
  s="$TMP/streifen_$x.html"
  {
    echo '<!doctype html><html><head><meta charset="utf-8"><style>'
    echo 'html,body{margin:0;background:#1c1f2b}.w{display:flex;gap:40px;padding:24px}'
    echo '.f{position:relative;width:468px;height:124px;overflow:hidden}'
    echo '.f img{position:absolute;top:0;width:160px;height:248.6px;filter:drop-shadow(-3px 0 4px rgba(0,0,0,.45))}</style></head><body><div class="w">'
    for seite in hell dunkel; do
      echo '<div class="f">'
      if [ $seite = hell ]; then liste=("${FAECHER_HELL[@]}"); else liste=("${FAECHER_DUNKEL[@]}"); fi
      i=0
      for k in "${liste[@]}"; do
        printf '<img style="left:%dpx" src="%s">\n' $((i*44)) "$(url "$TMP/k/${x}_$k.png")"
        i=$((i+1))
      done
      echo '</div>'
    done
    echo '</div></body></html>'
  } > "$s"
  shot "$s" "$HIER/streifen_$x.png" 1024 172
done

# 4. Übersichtsseiten
[ -f "$ENTWURF/farbsehschwaeche.html" ] && shot "$ENTWURF/farbsehschwaeche.html" "$ENTWURF/farbsehschwaeche.png" 1600 "${FSH_HOEHE:-4937}"
[ -f "$ENTWURF/index.html" ] && shot "$ENTWURF/index.html" "$ENTWURF/uebersicht.png" 1600 "${INDEX_HOEHE:-4485}"
echo "fertig: $HIER, $ENTWURF/farbsehschwaeche.png, $ENTWURF/uebersicht.png"
