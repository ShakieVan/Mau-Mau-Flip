class_name BigLayout
extends RefCounted
# Geometrie des großen Modus (Beta 1.1.1, AGENTS.md „Geplant für Beta 1.1.1“) als reine Funktionen, headless testbar
# (tests/test_ui_big_layout.gd). Basis 1600×720 quer. Links riesig der Nachziehstapel, daneben riesig die Ablage (fast volle
# Höhe; die Hand darf die untere Hälfte überdecken, die Karten sind symmetrisch), rechts daneben die aktuelle Farbe als Wort und
# Symbol, ganz rechts die endlos rollende Spielerliste über dem Mau-Knopf. Knöpfe bleiben an ihren Stellen, nur größer.
# Persönliche Einstellung je Gerät: App.settings "grosser_modus" (TableView.set_big, live umschaltbar).

const MARGIN := 20.0
const MENU := 104.0              # Zurück-Knopf oben links (sonst ScreenKit.TOUCH = 84)
const MAU := 190.0               # Mau-Knopf rechts unten (sonst 150)
const HAND_H := 300.0            # Handbereich: Kartenbreite 0,86 × 300 ≈ 258 px (sonst 220 → 189)
const PILE_GAP := 22.0           # Abstand Stapel – Ablage
const COLOR_MIN := 230.0         # Mindestbreite der Spalte „aktuelle Farbe“
const ROW_GAP := 10.0            # Abstand der Listeneinträge
const ROW_MIN := 84.0            # kleinste Zeilenhöhe (Touch)
const ROW_MAX := 132.0
const ROW_TOP := 1.25            # erste Zeile (wer dran ist) so viel höher
const PILL_H := 104.0            # Trefferhöhe der Pillenknöpfe (sonst 84)
const PILL_FONT := 30            # Grundgröße der Pillenschrift (sonst 20), mal UiFonts-Faktor
const HINT_SCALE := 1.4          # Hinweisleiste und Meldungen größer
const COLOR_SCALE := 2.1         # aktuelle Farbe (Symbol und Wort)


# Spalte der Spielerliste: rechts, von oben bis über den Mau-Knopf
static func list_rect(sz: Vector2) -> Rect2:
	# Namensbereich doppelt so breit wie in 1.1.1 (Nutzerwunsch 08.10.2026: Namen bei großer Schrift abgeschnitten); Stapel und
	# Ablage werden dafür entsprechend schmaler (pile_w rechnet mit dem Rest).
	var w := clampf(sz.x * 0.365, 440.0, 620.0)
	var bottom := mau_pos(sz).y - 14.0
	return Rect2(sz.x - MARGIN - w, MARGIN, w, maxf(bottom - MARGIN, ROW_MIN))


static func mau_pos(sz: Vector2) -> Vector2:
	return Vector2(sz.x - 46.0 - MAU, sz.y - 40.0 - MAU)


# Linker Rand des Stapels: rechts neben dem Zurück-Knopf (der liegt bei 14, 10)
static func pile_x0() -> float:
	return 14.0 + MENU + 12.0


# Breite von Stapel und Ablage: so hoch wie möglich (fast ganze Höhe), aber Platz für die Farbspalte vor der Liste
static func pile_w(sz: Vector2) -> float:
	var by_h := (sz.y - 2.0 * MARGIN) * 0.97 / CardView.ASPECT
	var avail := list_rect(sz).position.x - 16.0 - pile_x0() - COLOR_MIN - PILE_GAP
	return maxf(minf(by_h, avail * 0.5), 116.0)


static func pile_h(sz: Vector2) -> float:
	return pile_w(sz) * CardView.ASPECT


static func draw_pile_pos(sz: Vector2) -> Vector2:
	return Vector2(pile_x0() + pile_w(sz) * 0.5, MARGIN + pile_h(sz) * 0.5)


static func discard_pos(sz: Vector2) -> Vector2:
	return draw_pile_pos(sz) + Vector2(pile_w(sz) + PILE_GAP, 0.0)


# Spalte zwischen Ablage und Liste (aktuelle Farbe, Glücksspiel-Automat, Stempel)
static func color_column(sz: Vector2) -> Rect2:
	var x0 := discard_pos(sz).x + pile_w(sz) * 0.5 + 8.0
	var x1 := list_rect(sz).position.x - 8.0
	return Rect2(x0, MARGIN, maxf(x1 - x0, 0.0), hand_rect(sz).position.y - MARGIN)


# „Tischmitte“ im großen Modus: Mitte der Farbspalte (Automat, Kartentausch-Pfeile, Stempel)
static func table_center(sz: Vector2) -> Vector2:
	var c := color_column(sz)
	return Vector2(c.get_center().x, MARGIN + pile_h(sz) * 0.40)


static func color_mark_pos(sz: Vector2) -> Vector2:
	var c := color_column(sz)
	return Vector2(c.get_center().x, MARGIN + pile_h(sz) * 0.24)


# Handbereich (Kartenmitte ruht auf der Unterkante): zwischen den Knöpfen links und dem Mau-Knopf rechts
static func hand_rect(sz: Vector2) -> Rect2:
	var x0 := 370.0                       # rechts neben Sortieren/Rückseiten (Randkarten ragen etwas über den Bereich)
	var x1 := mau_pos(sz).x - 50.0
	return Rect2(x0, sz.y - HAND_H, maxf(x1 - x0, 400.0), HAND_H)


# Mitte der Hinweisleiste: knapp über den sichtbaren Handkarten
static func hint_y(sz: Vector2) -> float:
	var card_h := HandLayout.card_width(HAND_H) * CardView.ASPECT
	return sz.y - card_h * 0.5 - 52.0


static func sort_pos(sz: Vector2) -> Vector2:
	return Vector2(36.0, sz.y - 2.0 * PILL_H - 18.0)


static func backs_pos(sz: Vector2) -> Vector2:
	return Vector2(36.0, sz.y - PILL_H - 10.0)


# Zeilen der Liste: k sichtbare Zeilen, h0 = erste Zeile (dran), h1 = übrige
static func list_rows(sz: Vector2, n: int) -> Dictionary:
	var r := list_rect(sz)
	n = maxi(n, 1)
	var k := n
	while k > 1 and (r.size.y - (k - 1) * ROW_GAP) / (k - 1 + ROW_TOP) < ROW_MIN:
		k -= 1
	var h1 := minf((r.size.y - (k - 1) * ROW_GAP) / (k - 1 + ROW_TOP), ROW_MAX)
	if k == 1:
		h1 = minf(r.size.y / ROW_TOP, ROW_MAX)
	return {"k": k, "h0": h1 * ROW_TOP, "h1": h1, "top": r.position.y, "x": r.get_center().x, "w": r.size.x}


# Mitte (y) der Zeile an der fortlaufenden Stelle w (0 = oben, 1 = darunter …; Zwischenwerte beim Rollen)
static func row_y(w: float, rows: Dictionary) -> float:
	var h0 := float(rows["h0"])
	var h1 := float(rows["h1"])
	var top := float(rows["top"])
	if w <= 0.0:
		return top + h0 * 0.5 + w * (h0 + ROW_GAP)
	var first := top + h0 * 0.5
	var second := top + h0 + ROW_GAP + h1 * 0.5
	if w <= 1.0:
		return lerpf(first, second, w)
	return second + (w - 1.0) * (h1 + ROW_GAP)


static func row_h(w: float, rows: Dictionary) -> float:
	return lerpf(float(rows["h0"]), float(rows["h1"]), clampf(w, 0.0, 1.0))


# Sichtbarkeit an der Stelle w bei n Einträgen: oben raus und unten rein weich ausblenden, hinter der letzten sichtbaren Zeile 0
static func row_alpha(w: float, n: int, k: int) -> float:
	var a := clampf((w + 0.5) * 2.0, 0.0, 1.0)
	a *= clampf((float(mini(k, n)) - 0.5 - w) * 2.0, 0.0, 1.0)
	return a


# Fortlaufende Stelle (Rollen über das Ende hinaus) → angezeigte Stelle in [-0,5, n − 0,5)
static func wrap(slot: float, n: int) -> float:
	return fposmod(slot + 0.5, float(maxi(n, 1))) - 0.5


# Reihenfolge der Liste: wer dran ist zuerst, dann in Spielrichtung (dir 1 = Platz + 1). Fertige Spieler filtert TableView._list_entries vorher heraus.
static func list_order(seats: Array, turn: int, dir: int) -> Array[int]:
	var sorted: Array[int] = []
	for s in seats:
		sorted.append(int(s))
	sorted.sort()
	var out: Array[int] = []
	var n := sorted.size()
	if n == 0:
		return out
	var start := sorted.find(turn)
	if start < 0:
		start = 0
	var step := -1 if dir < 0 else 1
	for i in n:
		out.append(sorted[posmod(start + i * step, n)])
	return out


# Nächstgelegenes Ziel für das Rollen: gleiche Stelle modulo n, möglichst kurzer Weg von slot aus
static func roll_target(slot: float, index: int, n: int) -> float:
	var nf := float(maxi(n, 1))
	return float(index) + nf * roundf((slot - float(index)) / nf)
