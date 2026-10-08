class_name AppStats
extends RefCounted
# Statistik je Gerät (Beta 1.2.1): user://statistik.json, robust wie AppSettings (.tmp, Umbenennen, Vorversion als .bak).
# Gezählt wird für den Spieler dieses Geräts (Übung, Gastgeber, App-Gast). Im Weitergeben-Modus teilen sich mehrere Menschen
# das Gerät; dort zählt nur „Partien auf diesem Gerät“, ohne Zuordnung zu Personen.
# Quelle: dieselben Ereignisse und Sichten wie der Tisch (TableScreen._on_state → record). Eine Partie beginnt mit
# round_start{round: 1}; Fortsetzen eines gespeicherten Spiels oder Neuverbinden zählt nicht doppelt (kein neues round_start).
# Alle Texte dieser Statistik stehen hier gesammelt (LABELS, Sätze in round_note), damit die englische Fassung eine Stelle hat.

signal changed

const PATH := "user://statistik.json"
const VERSION := 1

# Zähler (alle int ≥ 0). Reihenfolge = Anzeige in den Einstellungen.
const KEYS := ["partien", "runden", "runden_gewonnen", "partien_gewonnen", "mau_mau", "erwischt_selbst", "erwischt_worden",
	"groesste_hand", "gluecksspiel_max", "kartentausch", "flip", "partien_weitergeben"]
const MAX_KEYS := ["groesste_hand", "gluecksspiel_max"]   # Höchstwerte statt Summen

const TITLE := "Deine Statistik"
const INTRO := "Nur auf diesem Gerät, für dich als Spieler (Übung, Gastgeber oder Gast)."
const PASS_NOTE := "Beim Weitergeben spielen mehrere an diesem Gerät, darum zählen dort nur die Partien."
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
}

var path := PATH
var data := {}


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
		for key in KEYS:
			var v: Variant = loaded.get(key, 0)
			if (v is float or v is int) and float(v) >= 0.0 and float(v) < 1.0e9:
				data[key] = int(v)
		break


static func empty() -> Dictionary:
	var d := {}
	for key in KEYS:
		d[key] = 0
	return d


func value(key: String) -> int:
	return int(data.get(key, 0))


func is_empty() -> bool:
	for key in KEYS:
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
	for raw in events:
		if not raw is Dictionary:
			continue
		var ev: Dictionary = raw
		var e := str(ev.get("e", ""))
		if e == "round_start" and int(ev.get("round", 0)) == 1:
			_add("partien_weitergeben" if shared else "partien")
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
	var what := "Partiesieg" if kind == "partie" else "Rundensieg"
	if n == 1:
		return "Dein erster %s!" % what
	return "Dein %d. %s!" % [n, what]


# Zeilen für die Einstellungen: [[Beschriftung, Wert als Text], …]; Höchstwerte 0 erscheinen als „–“.
func rows() -> Array:
	var out: Array = []
	for key in KEYS:
		var v := value(key)
		out.append([str(LABELS[key]), "–" if v == 0 and MAX_KEYS.has(key) else str(v)])
	return out


static func _seat_of(entry: Variant) -> int:
	if entry is Dictionary:
		return int((entry as Dictionary).get("seat", -1))
	return int(entry) if entry is int or entry is float else -1


func _add(key: String, n := 1) -> void:
	data[key] = value(key) + n


func _max(key: String, v: int) -> void:
	if v > value(key):
		data[key] = v
