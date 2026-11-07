class_name AppStats
extends RefCounted
# Statistik je Gerät (Beta 1.2.1): user://statistik.json, robust wie AppSettings (.tmp, Umbenennen, Vorversion als .bak).
# Gezählt wird für den Spieler dieses Geräts (Übung, Gastgeber, App-Gast). Im Weitergeben-Modus teilen sich mehrere Menschen
# das Gerät; dort zählt nur „Partien auf diesem Gerät“, ohne Zuordnung zu Personen.
# Quelle: dieselben Ereignisse und Sichten wie der Tisch (TableScreen._on_state → record). Eine Partie beginnt mit
# round_start{round: 1}; Fortsetzen eines gespeicherten Spiels oder Neuverbinden zählt nicht doppelt (kein neues round_start).
# Alle Texte dieser Statistik stehen hier gesammelt (LABELS, Sätze in round_note), damit die englische Fassung eine Stelle hat.
# Glücksspiel-Zähler (Nutzerbefund 01.11.2026: Zeigt der Knopf zu selten 0?): je Obergrenze der Trefferquote (Regler 3–10, seit
# 07.11.2026) flache Schlüssel gs_<obergrenze>_<feld>; die Zähler der früheren Stufen (gs_rare_… usw.) übernimmt das Laden.
# Sie zählen jedes Glücksspiel am Tisch, egal wer es legt, aber nur, wo dieses Gerät würfelt (solo, host): So misst die Statistik den
# echten Zufall im echten Spiel. Ein Glücksspiel, das nach einem App-Neustart weiterläuft, zählt nur bei den Drucken (erster Druck unbekannt).

signal changed

const PATH := "user://statistik.json"
const VERSION := 1

# Zähler (alle int ≥ 0). Reihenfolge = Anzeige in den Einstellungen.
const KEYS := ["partien", "runden", "runden_gewonnen", "partien_gewonnen", "mau_mau", "erwischt_selbst", "erwischt_worden",
	"groesste_hand", "gluecksspiel_max", "kartentausch", "flip", "partien_weitergeben", "gezogen", "aussetzen"]
const MAX_KEYS := ["groesste_hand", "gluecksspiel_max"]   # Höchstwerte statt Summen
const GAMBLE_FIELDS := ["spiele", "spiele0", "drucke", "drucke0"]   # erster Druck je Glücksspiel, davon 0; alle Drucke, davon 0

const TITLE := "Deine Statistik"
const INTRO := "Nur auf diesem Gerät, für dich als Spieler (Übung, Gastgeber oder Gast)."
const PASS_NOTE := "Beim Weitergeben spielen mehrere an diesem Gerät, darum zählen dort nur die Partien."
const GAMBLE_NOTE := "Die Glücksspiel-Zeilen zählen jedes Glücksspiel am Tisch, egal wer es legt, wenn dieses Gerät würfelt (Übung oder Gastgeber)."
const EMPTY := "Noch keine Partie gespielt."
const RESET := "Statistik zurücksetzen"
const RESET_TITLE := "Statistik zurücksetzen?"
const RESET_TEXT := "Alle Zahlen auf diesem Gerät gehen auf null. Das lässt sich nicht rückgängig machen."
const RESET_YES := "Zurücksetzen"
const RESET_NO := "Behalten"
const RESET_DONE := "Statistik zurückgesetzt."
const LABELS := {
	"partien": "Partien gespielt",
	"runden": "Runden gespielt",
	"runden_gewonnen": "Runden gewonnen (Platz 1)",
	"partien_gewonnen": "Partien mit Punkten gewonnen",
	"mau_mau": "„Mau-Mau!“ (fertig geworden)",
	"erwischt_selbst": "Andere erwischt",
	"erwischt_worden": "Selbst erwischt worden",
	"groesste_hand": "Größte Hand (Karten)",
	"gluecksspiel_max": "Höchster Glücksspiel-Treffer",
	"kartentausch": "Kartentausch gelegt",
	"flip": "Flip gelegt",
	"partien_weitergeben": "Partien beim Weitergeben",
	"gezogen": "Karten gezogen",
	"aussetzen": "Selbst ausgesetzt",
}

var path := PATH
var data := {}
var _gamble_first := false      # gamble_start gesehen, der erste Druck dieses Glücksspiels steht noch aus (nicht gespeichert)


func _init(save_path := PATH) -> void:
	path = save_path
	data = empty()
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(candidate)) != OK or not json.data is Dictionary:
			continue
		var loaded: Dictionary = json.data
		for key in all_keys():
			var v: Variant = loaded.get(key, 0)
			if _count_ok(v):
				data[key] = int(v)
		# Zähler der früheren Stufen (1.6.18: gs_rare_…, gs_medium_…, gs_often_…) gehören zu den Obergrenzen 10, 5 und 3
		for level in RuleConfig.GAMBLE_MAX_Q:
			for field in GAMBLE_FIELDS:
				var old: Variant = loaded.get("gs_%s_%s" % [level, field], 0)
				if _count_ok(old):
					var key := gamble_key(int(RuleConfig.GAMBLE_MAX_Q[level]), str(field))
					data[key] = value(key) + int(old)
		break


static func _count_ok(v: Variant) -> bool:
	return (v is float or v is int) and float(v) >= 0.0 and float(v) < 1.0e9


# Alle gespeicherten Zähler: die angezeigten KEYS und die Glücksspiel-Zähler je Obergrenze der Trefferquote (3 bis 10)
static func all_keys() -> Array:
	var out: Array = KEYS.duplicate()
	for top in gamble_tops():
		for field in GAMBLE_FIELDS:
			out.append(gamble_key(top, str(field)))
	return out


# Mögliche Obergrenzen der Glücksspiel-Quote (Regler 1:3 bis 1:10)
static func gamble_tops() -> Array:
	var limits: Array = RuleConfig.NUMBERS["gamble_max"]
	return range(int(limits[1]), int(limits[2]) + 1)


static func gamble_key(top: int, field: String) -> String:
	return "gs_%d_%s" % [top, field]


static func empty() -> Dictionary:
	var d := {}
	for key in all_keys():
		d[key] = 0
	return d


func value(key: String) -> int:
	return int(data.get(key, 0))


func is_empty() -> bool:
	for key in all_keys():
		if value(key) > 0:
			return false
	return true


func reset() -> bool:
	data = empty()
	var ok := save()
	changed.emit()
	return ok


func save() -> bool:
	var out := data.duplicate()
	out["version"] = VERSION
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(out, "\t"))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
	return DirAccess.rename_absolute(path + ".tmp", path) == OK


# Ereignisse und Sicht einer Lieferung zählen. mode: "solo" | "pass" | "host" | "client".
# Rückgabe: kleiner Satz fürs Rundenende („Dein 12. Rundensieg!“) oder "" (dann nichts zeigen).
func record(events: Array, view: Dictionary, mode: String) -> String:
	var before := data.duplicate()
	var note := ""
	var me := int(view.get("seat", -1))
	var shared := mode == "pass"
	var dice_here := mode == "solo" or mode == "host"
	for raw in events:
		if not raw is Dictionary:
			continue
		var ev: Dictionary = raw
		var e := str(ev.get("e", ""))
		if e == "round_start" and int(ev.get("round", 0)) == 1:
			_add("partien_weitergeben" if shared else "partien")
		if dice_here and e == "gamble_start":
			_gamble_first = true
		elif dice_here and e == "gamble_roll":
			_count_gamble(int(ev.get("value", 0)), view)
		if shared or me < 0:
			continue
		var seat := int(ev.get("seat", -2))
		match e:
			"round_over":
				_add("runden")
				var ranking: Array = ev.get("ranking", [])
				if not ranking.is_empty() and _seat_of(ranking[0]) == me:
					_add("runden_gewonnen")
					note = round_note("runde", value("runden_gewonnen"))
			"game_over":
				if int(ev.get("winner", -1)) == me:
					_add("partien_gewonnen")
					note = round_note("partie", value("partien_gewonnen"))
			"finish":
				if seat == me:
					_add("mau_mau")
			"catch":
				if seat == me:
					_add("erwischt_selbst")
				if int(ev.get("target", -1)) == me:
					_add("erwischt_worden")
			"gamble_roll":
				if seat == me:
					_max("gluecksspiel_max", int(ev.get("value", 0)))
			"swap_hands":
				if seat == me:
					_add("kartentausch")
			"play":
				if seat == me and str(ev.get("face", "")).ends_with("_flip"):
					_add("flip")
			"draw":
				if seat == me and str(ev.get("reason", "")) != "join":
					_add("gezogen", maxi(int(ev.get("count", 1)), 1))
			"skip":
				if seat == me:
					_add("aussetzen")
	if not shared and me >= 0:
		var hand: Variant = view.get("hand", [])
		if hand is Array:
			_max("groesste_hand", (hand as Array).size())
	if data != before:
		save()
		changed.emit()
	return note


# Satz fürs Rundenende. kind "runde" | "partie", n = neuer Stand.
static func round_note(kind: String, n: int) -> String:
	if n == 1:
		return I18n.t("Dein erster Partiesieg!") if kind == "partie" else I18n.t("Dein erster Rundensieg!")
	return (I18n.t("Dein %d. Partiesieg!") if kind == "partie" else I18n.t("Dein %d. Rundensieg!")) % n


# Zeilen für die Einstellungen: [[Beschriftung, Wert als Text], …]; Höchstwerte 0 erscheinen als „–“.
func rows() -> Array:
	var out: Array = []
	for key in KEYS:
		var v := value(key)
		out.append([str(LABELS[key]), "–" if v == 0 and MAX_KEYS.has(key) else str(v)])
	out.append_array(gamble_rows())
	return out


# Glücksspiel-Zeilen je Obergrenze, mit der schon gedrückt wurde (aufsteigend wie der Regler): Anteil der 0 beim ersten Druck (mit dem
# erwarteten Wert, RuleConfig.gamble_zero_percent) und bei allen Drucken. Bei allen Drucken gibt es keinen festen Vergleichswert, er
# hängt davon ab, wie oft die Spieler aufhören.
func gamble_rows() -> Array:
	var out: Array = []
	for top in gamble_tops():
		var games := value(gamble_key(top, "spiele"))
		if games > 0:
			out.append([I18n.t("Glücksspiel bis 1:%d: 0 beim ersten Druck (erwartet %s)") % [top, "%d %%" % RuleConfig.gamble_zero_percent(top)],
				_share_text(value(gamble_key(top, "spiele0")), games)])
		var presses := value(gamble_key(top, "drucke"))
		if presses > 0:
			out.append([I18n.t("Glücksspiel bis 1:%d: 0 bei allen Drucken") % top, _share_text(value(gamble_key(top, "drucke0")), presses)])
	return out


static func _share_text(part: int, whole: int) -> String:
	return (I18n.t("%d von %d") % [part, whole]) + " · %d %%" % roundi(100.0 * part / whole)


# Spaßtitel (FunTitles): [{key, title, why, power}], höchstens drei, stärkste zuerst; leer, solange keiner verdient ist
func titles() -> Array:
	return FunTitles.earned(data)


static func _seat_of(entry: Variant) -> int:
	if entry is Dictionary:
		return int((entry as Dictionary).get("seat", -1))
	return int(entry) if entry is int or entry is float else -1


func _count_gamble(roll: int, view: Dictionary) -> void:
	var top := RuleConfig.gamble_max_in(view.get("rules", {}))
	_add(gamble_key(top, "drucke"))
	if roll == 0:
		_add(gamble_key(top, "drucke0"))
	if _gamble_first:
		_gamble_first = false
		_add(gamble_key(top, "spiele"))
		if roll == 0:
			_add(gamble_key(top, "spiele0"))


func _add(key: String, n := 1) -> void:
	data[key] = value(key) + n


func _max(key: String, v: int) -> void:
	if v > value(key):
		data[key] = v
