#!/usr/bin/env bash
# Mau-Mau Flip – Prüfskript für den Browser-Client „Lite“ (Modul E1, webclient/).
#  1. Autotest: index.html?mock=1&autotest=1 in Chrome headless (virtuelle Zeit), Ergebnis per --dump-dom aus #autotest-result.
#     Mehrere Aufstellungen (2, 4, 7 Spieler, dunkle Seite, große Hand).
#  2. Kontrollbilder über tools/webtest/cdp.ps1 (exakte Geräteansicht per DevTools) nach docs/module/E1_*.png:
#     844×390 (iPhone quer), 1600×720 (Basisgröße), 390×844 (Hochformat-Hinweis).
# Aufruf (Git Bash):  bash tools/webtest/run_webtest.sh [--nur-test|--nur-bilder] [Bildname …]
# Rückgabe: 0 = alle Autotests ok, 1 = Fehler.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WEB="$ROOT/webclient"
OUT="$ROOT/docs/module"
CHROME="/c/Program Files/Google/Chrome/Application/chrome.exe"
TMPD="$(cygpath -u "${TEMP:-/tmp}")/mmf-webtest"
mkdir -p "$TMPD" "$OUT"
BASIS="file:///$(cygpath -m "$WEB" | sed 's/ /%20/g')/index.html"
MODUS="${1:-alles}"
case "$MODUS" in --nur-test|--nur-bilder) shift ;; *) MODUS="alles" ;; esac
NUR=("$@")

fehler=0

# ---------- 1. Autotests ----------
autotest() {   # $1 = Name, $2 = zusätzliche URL-Parameter
	local prof dump res
	prof="$(cygpath -w "$TMPD/prof-$1")"
	rm -rf "$TMPD/prof-$1"
	dump="$TMPD/autotest-$1.html"
	# Fenster 870×490 ergibt in --headless=new eine Ansicht von 844×390
	timeout 300 "$CHROME" --headless=new --disable-gpu --no-first-run --no-default-browser-check --disable-extensions --mute-audio \
		--user-data-dir="$prof" --window-size=870,490 --virtual-time-budget=1500000 \
		--dump-dom "$BASIS?mock=1&autotest=1&tempo=2$2" > "$dump" 2>/dev/null
	res="$(grep -o '<pre id="autotest-result"[^>]*>[^<]*' "$dump" | sed 's/<pre id="autotest-result"[^>]*>//' | sed 's/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g')"
	if [ -z "$res" ]; then echo "FAIL: autotest $1: kein Ergebnis (siehe $dump)"; fehler=1; return; fi
	if grep -q 'id="autotest-result" data-ok="1"' "$dump"; then echo "ok   autotest $1: $res"; else echo "FAIL: autotest $1: $res"; fehler=1; fi
}
if [ "$MODUS" != "--nur-bilder" ]; then
	autotest vier ""
	autotest zwei "&gegner=1&seed=7"
	autotest sieben "&gegner=6&seed=11&karten=18"
	autotest dunkel "&seite=dunkel&seed=5&zuege=10"
fi

# ---------- 2. Kontrollbilder ----------
BEREIT="window.MMF&&MMF.App&&document.fonts.status==='loaded'&&(document.body.dataset.screen!=='tisch'||(MMF.App.tisch&&MMF.App.tisch.regie.leer))"
TISCH="window.MMF&&MMF.App&&MMF.App.tisch&&MMF.App.tisch.regie.leer&&document.fonts.status==='loaded'"
ANDROID="Mozilla/5.0 (Linux; Android 14; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Mobile Safari/537.36"
IPHONE="Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"
bild() {   # Name, URL-Parameter, Breite, Höhe, Dichte, Wartebedingung, Wartezeit ms, [UA]
	local name="$1"
	if [ ${#NUR[@]} -gt 0 ]; then local treffer=0; for n in "${NUR[@]}"; do [ "$n" = "$name" ] && treffer=1; done; [ $treffer = 1 ] || return; fi
	local datei="E1_$name.png"; case "$name" in E2_*) datei="$name.png" ;; esac   # E2_…: Bilder des Moduls E2 (Mau-Blasen)
	local ziel; ziel="$(cygpath -w "$OUT/$datei")"
	local args=(-Url "$BASIS?$2" -Out "$ziel" -Width "$3" -Height "$4" -Scale "$5" -WaitExpr "$6" -WaitMs "$7" -TimeoutMs 25000)
	[ "$3" -lt 1200 ] && args+=(-Mobile)
	[ -n "${8:-}" ] && args+=(-UserAgent "$8")
	local ausgabe
	ausgabe="$(powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$ROOT/tools/webtest/cdp.ps1")" "${args[@]}" 2>&1)"
	if echo "$ausgabe" | grep -q "BILD:"; then echo "bild $datei$(echo "$ausgabe" | grep -E 'WARTEN|JS-AUSNAHMEN' | tr '\n' ' ' | sed 's/^/  /')"; else echo "FAIL: bild $name: $ausgabe"; fehler=1; fi
}
if [ "$MODUS" != "--nur-test" ]; then
	bild start_844x390        "mock=1"                                     844 390 2 "$BEREIT" 600 "$IPHONE"
	bild start_android_844x390 "mock=1"                                    844 390 2 "$BEREIT" 600 "$ANDROID"
	bild start_390x844        "mock=1"                                     390 844 2 "$BEREIT" 600 "$IPHONE"
	bild lobby_844x390        "mock=1&szene=lobby&ruhig=1"                 844 390 2 "$BEREIT&&MMF.App.lobby" 1800
	bild tisch_844x390        "mock=1&szene=tisch&ruhig=1"                 844 390 2 "$TISCH" 900
	bild tisch_1600x720       "mock=1&szene=gewaehlt&ruhig=1"              1600 720 1 "$TISCH" 900
	bild dunkel_844x390       "mock=1&szene=tisch&seite=dunkel&ruhig=1&seed=3" 844 390 2 "$TISCH" 900
	bild farbwahl_844x390     "mock=1&szene=farbwahl&ruhig=1"              844 390 2 "$TISCH" 900
	bild anzweifeln_844x390   "mock=1&szene=anzweifeln&ruhig=1"            844 390 2 "$TISCH" 900
	bild gezogen_844x390      "mock=1&szene=gezogen&ruhig=1"               844 390 2 "$TISCH" 900
	bild mau_844x390          "mock=1&szene=mau&ruhig=1"                   844 390 2 "$TISCH" 900
	bild viele_844x390        "mock=1&szene=viele&ruhig=1"                 844 390 2 "$TISCH" 900
	bild hilfe_844x390        "mock=1&szene=hilfe&ruhig=1"                 844 390 2 "$TISCH" 900
	bild rueckseiten_844x390  "mock=1&szene=rueckseiten&ruhig=1"           844 390 2 "$TISCH" 900
	bild rundenende_844x390   "mock=1&szene=rundenende&ruhig=1"            844 390 2 "$TISCH" 900
	bild getrennt_844x390     "mock=1&szene=getrennt&ruhig=1"              844 390 2 "$TISCH&&!document.getElementById('verbinde').hidden" 400
	bild gegner9_1600x720     "mock=1&szene=tisch&gegner=9&ruhig=1"        1600 720 1 "$TISCH" 900
	bild ersatzkarten_844x390 "mock=1&szene=tisch&ruhig=1&bilder=0&seed=9"  844 390 2 "$TISCH" 900
	bild klein_760x300        "mock=1&szene=tisch&ruhig=1&karten=9"        760 300 2 "$TISCH" 900
	bild hochformat_390x844   "mock=1&szene=tisch&ruhig=1"                 390 844 2 "$TISCH" 600 "$IPHONE"
	# Mau-Sprechblase: alle Varianten zugleich (tags und nachts), mitten in der Animation (ohne ruhig=1)
	bild E2_blasen_1600x720   "mock=1&szene=blasen&gegner=4&seed=3"        1600 720 1 "$TISCH&&document.querySelectorAll('.mau-blase').length>0" 1400
	bild E2_blasen_nacht_844x390 "mock=1&szene=blasen&gegner=4&seed=5&seite=dunkel" 844 390 2 "$TISCH&&document.querySelectorAll('.mau-blase').length>0" 1400
	bild E2_blasen_schlicht_844x390 "mock=1&szene=blasen&gegner=3&variante=schlicht" 844 390 2 "$TISCH&&document.querySelectorAll('.mau-blase').length>0" 900
fi

exit $fehler
