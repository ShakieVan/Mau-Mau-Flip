#!/bin/bash
# Mau-Töne aus den Aufnahmen des Nutzers (05.10.2026, Handy-Mikrofon): audio/aufnahmen/mao_original.m4a und mao-mao_original.m4a.
# Nutzerwunsch: „etwas brillanter machen und besser aussteuern, damit man das über den Telefonlautsprecher gut hören kann“.
# Die Aufnahmen sind sauber, aber dumpf: fast alle Energie unter 1,5 kHz, Handy-Lautsprecher geben erst ab etwa 750 Hz
# kräftig wieder. Deshalb:
#   1. Zuschneiden (Stille vorn weg, kurzer natürlicher Ausklang) mit weichen Rändern, ohne Knacken.
#   2. Tiefen unter 180 Hz weg (kosten Pegel, hört man am Handy nicht), Dröhnen um 250 Hz leicht absenken.
#   0. Vorher entrauschen (afftdn) und das Rauschband der Handy-Aufnahme über 4,3 kHz abschneiden – sonst hebt die Präsenz
#      es als Zischen mit an (erster Versuch 05.10.2026).
#   3. Präsenz 1–3 kHz anheben (Verständlichkeit am Handy), dazu 3,2 kHz für Brillanz. Kein Obertonerzeuger (aexciter):
#      Die Stimme hat Obertöne nur bis etwa 2,4 kHz, er erzeugte aus dem Restrauschen ein Zischband bei 4–7 kHz.
#   4. Tiefpass bei 5,2 kHz (kein Zischen; Katzen-Leitplanke: oberhalb 8 kHz bleibt fast nichts).
#   5. Verdichten (Kompressor) und auf −1 dBTP begrenzen, dann auf eine einheitliche Momentan-Lautheit bringen.
# Drei Stärken zum Vergleich (mild, mittel, stark); ins Spiel kommt „mittel“ (STANDARD unten).
# Aufruf (Git Bash, ffmpeg im PATH):  bash tools/make_mau_aufnahmen.sh
set -euo pipefail
HIER="$(cd "$(dirname "$0")/.." && pwd)"
IN="$HIER/audio/aufnahmen"
OUT="$HIER/audio/aufnahmen/aufbereitet"
STANDARD="mittel"
mkdir -p "$OUT"

# name  quelle  anfang  ende (s, aus silencedetect −40 dB: Mao 0,187–0,513 s, Mao-Mao 0,215–0,628 s; plus Ausklang)
TOENE=("mau mao_original.m4a 0.165 0.660" "mau_mau mao-mao_original.m4a 0.195 0.780")

kette() { # kette <stärke> → Filterkette
	local praesenz anreg hoehen komp tief
	case "$1" in
		mild)   praesenz=5; anreg=0; hoehen=2; komp=3; tief=170 ;;
		mittel) praesenz=8; anreg=0; hoehen=4; komp=4; tief=240 ;;
		stark)  praesenz=11; anreg=0; hoehen=6; komp=6; tief=320 ;;
	esac
	echo "afftdn=nr=24:nf=-75,lowpass=f=4300:poles=2,lowpass=f=4300:poles=2,highpass=f=${tief}:poles=2,equalizer=f=250:t=q:w=1:g=-3,equalizer=f=1100:t=q:w=1:g=3,equalizer=f=2200:t=q:w=1.1:g=${praesenz},equalizer=f=3200:t=q:w=1.2:g=${hoehen},lowpass=f=5200:poles=2,acompressor=threshold=0.08:ratio=${komp}:attack=3:release=90:makeup=2,alimiter=limit=0.89:attack=2:release=40:level=disabled"
}

for eintrag in "${TOENE[@]}"; do
	read -r name quelle anfang ende <<< "$eintrag"
	dauer=$(awk "BEGIN{print $ende-$anfang}")
	aus=$(awk "BEGIN{print $dauer-0.06}")
	for staerke in mild mittel stark; do
		ziel="$OUT/${name}_${staerke}"
		# Zuschneiden, Ränder weich (8 ms rein, 60 ms raus), Kette, danach Spitze auf −1 dBTP (zweiter Durchgang über volumedetect)
		ffmpeg -hide_banner -loglevel error -y -i "$IN/$quelle" -af "atrim=start=$anfang:end=$ende,asetpts=PTS-STARTPTS,afade=t=in:d=0.008,afade=t=out:st=$aus:d=0.06,$(kette $staerke)" -ar 48000 -ac 1 "$ziel.tmp.wav"
		spitze=$(ffmpeg -hide_banner -nostats -i "$ziel.tmp.wav" -af volumedetect -f null - 2>&1 | sed -n 's/.*max_volume: \(-\?[0-9.]*\) dB.*/\1/p')
		anheben=$(awk "BEGIN{print -1.0 - ($spitze)}")
		ffmpeg -hide_banner -loglevel error -y -i "$ziel.tmp.wav" -af "volume=${anheben}dB" -c:a pcm_s16le "$ziel.wav"
		rm -f "$ziel.tmp.wav"
		ffmpeg -hide_banner -loglevel error -y -i "$ziel.wav" -c:a libvorbis -q:a 6 "$ziel.ogg"
		ffmpeg -hide_banner -loglevel error -y -i "$ziel.wav" -c:a aac -b:a 160k -movflags +faststart "$ziel.m4a"
		laut=$(ffmpeg -hide_banner -nostats -i "$ziel.wav" -af ebur128=peak=true -f null - 2>&1 | grep -E "^\s+I:" | tail -1 | awk '{print $2}')
		handy=$(ffmpeg -hide_banner -nostats -i "$ziel.wav" -af "highpass=f=800:poles=2,volumedetect" -f null - 2>&1 | sed -n 's/.*mean_volume: \(-\?[0-9.]*\) dB.*/\1/p')
		voll=$(ffmpeg -hide_banner -nostats -i "$ziel.wav" -af "volumedetect" -f null - 2>&1 | sed -n 's/.*mean_volume: \(-\?[0-9.]*\) dB.*/\1/p')
		printf '%-8s %-7s Dauer %.2f s  Lautheit %s LUFS  Anteil ab 800 Hz (Handy) %s dB\n' "$name" "$staerke" "$dauer" "$laut" "$(awk "BEGIN{printf \"%.1f\", $handy-($voll)}")"
	done
	# Ins Spiel: Standardstärke
	cp "$OUT/${name}_${STANDARD}.ogg" "$HIER/game/assets/sfx/${name}.ogg"
	cp "$OUT/${name}_${STANDARD}.ogg" "$HIER/webclient/sfx/${name}.ogg"
	cp "$OUT/${name}_${STANDARD}.m4a" "$HIER/webclient/sfx/${name}.m4a"
done
# Zum Vergleich: Originale mit derselben Messung
for q in mao_original.m4a mao-mao_original.m4a; do
	handy=$(ffmpeg -hide_banner -nostats -i "$IN/$q" -af "highpass=f=800:poles=2,volumedetect" -f null - 2>&1 | sed -n 's/.*mean_volume: \(-\?[0-9.]*\) dB.*/\1/p')
	voll=$(ffmpeg -hide_banner -nostats -i "$IN/$q" -af "volumedetect" -f null - 2>&1 | sed -n 's/.*mean_volume: \(-\?[0-9.]*\) dB.*/\1/p')
	printf '%-20s Original  Anteil ab 800 Hz (Handy) %s dB\n' "$q" "$(awk "BEGIN{printf \"%.1f\", $handy-($voll)}")"
done
echo "Ins Spiel kopiert: Stärke $STANDARD → game/assets/sfx/mau.ogg, mau_mau.ogg und webclient/sfx/"
