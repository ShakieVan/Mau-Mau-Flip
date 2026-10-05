class_name RuleConfig
extends RefCounted
# Regeloptionen (docs/BETA1_PLAN.md Abschnitt 4, Regelbericht Abschnitte 1.13, 2 und 4). Standard = Voreinstellung „offiziell“
# (Fassung 2024). from_dict() nimmt nur bekannte Schlüssel und gültige Werte an (JSON-Zahlen kommen als float), alles andere
# bleibt beim Standard. describe() liefert kurze deutsche Zeilen für die Regelübersicht.

# Auswahl-Optionen: Schlüssel → erlaubte Werte, der erste ist der Standard.
const CHOICES := {
	"round_end": ["first", "last"],
	"scoring": ["none", "points500"],
	"draw_rule": ["one", "until_playable"],
	"drawn_card": ["may", "must", "may_not"],
	"stacking": ["off", "same"],
	"wild_restriction": ["bluff", "enforce", "free"],
	"mau_call": ["catch", "auto", "reminder", "off"],
	"flip_last_card": ["execute", "ignore"],
}
const FLAGS := {
	"wild_counts_for_bluff": true,
	"jagd_wild_stops": false,
	"backs_visible": true,
	"peek_own_backs": true,
	"two_player_reverse_skips": true,
}
# Zahlen: Standard, kleinster, größter Wert.
const NUMBERS := {
	"target": [500, 100, 5000],
	"hand_size": [7, 5, 10],
	"mau_penalty": [2, 1, 4],
}
const PRESETS := {
	"offiziell": {},
	"klassisch500": {"scoring": "points500", "wild_counts_for_bluff": false},
	"familie": {"round_end": "last", "stacking": "same", "wild_restriction": "enforce", "mau_penalty": 1},
	"mau_mau": {"stacking": "same", "wild_restriction": "enforce", "mau_penalty": 1},
}
const PRESET_TITLES := {"offiziell": "Offiziell", "klassisch500": "Klassisch 500", "familie": "Familie", "mau_mau": "Mau-Mau-Tradition"}

var round_end := "first"
var scoring := "none"
var target := 500
var hand_size := 7
var draw_rule := "one"
var drawn_card := "may"
var stacking := "off"
var wild_restriction := "bluff"
var wild_counts_for_bluff := true
var jagd_wild_stops := false
var mau_call := "catch"
var mau_penalty := 2
var backs_visible := true
var peek_own_backs := true
var two_player_reverse_skips := true
var flip_last_card := "execute"


static func keys() -> Array:
	var out: Array = []
	out.append_array(CHOICES.keys())
	out.append_array(FLAGS.keys())
	out.append_array(NUMBERS.keys())
	return out


static func preset(preset_name: String) -> RuleConfig:
	var cfg := RuleConfig.new()
	cfg.apply_dict(PRESETS.get(preset_name, {}))
	return cfg


static func preset_names() -> Array:
	return PRESETS.keys()


static func from_dict(d: Dictionary) -> RuleConfig:
	var cfg := RuleConfig.new()
	cfg.apply_dict(d)
	return cfg


func to_dict() -> Dictionary:
	var d := {}
	for k in CHOICES:
		d[k] = str(get(k))
	for k in FLAGS:
		d[k] = bool(get(k))
	for k in NUMBERS:
		d[k] = int(get(k))
	return d


# Übernimmt gültige Werte aus d; Unbekanntes und Ungültiges bleibt unverändert.
func apply_dict(d: Dictionary) -> void:
	for k in d:
		var key := str(k)
		var v: Variant = d[k]
		if CHOICES.has(key):
			if (CHOICES[key] as Array).has(str(v)):
				set(key, str(v))
		elif FLAGS.has(key):
			if v is bool:
				set(key, v)
			elif v is int or v is float:
				set(key, v != 0)
		elif NUMBERS.has(key):
			if v is int or v is float or (v is String and (v as String).is_valid_int()):
				var limits: Array = NUMBERS[key]
				set(key, clampi(int(v), int(limits[1]), int(limits[2])))


func duplicate_config() -> RuleConfig:
	return RuleConfig.from_dict(to_dict())


func equals(other: RuleConfig) -> bool:
	return other != null and to_dict() == other.to_dict()


# Name der passenden Voreinstellung oder "" bei eigenen Regeln.
func preset_name() -> String:
	var mine := to_dict()
	for p in PRESETS:
		if RuleConfig.preset(p).to_dict() == mine:
			return p
	return ""


# Punktwertung gilt nur, wenn die Runde beim ersten Fertigen endet; bis zum Letzten zählen Platzierungen.
func effective_scoring() -> String:
	return "points500" if scoring == "points500" and round_end == "first" else "none"


# Kurze Zeilen für die Regelübersicht, je eine pro Regelgruppe.
func describe() -> Array[String]:
	var out: Array[String] = []
	var p := preset_name()
	if p != "":
		out.append("Voreinstellung: %s." % PRESET_TITLES[p])
	if round_end == "first":
		out.append("Wer zuerst alle Karten los ist, gewinnt die Runde.")
	else:
		out.append("Bis zum Letzten: Wer fertig ist, scheidet aus. Gespielt wird um die Plätze, bis nur einer Karten hat.")
	if effective_scoring() == "points500":
		out.append("Wertung: Der Sieger bekommt die Punkte aller übrigen Handkarten. Wer zuerst %d Punkte hat, gewinnt die Partie." % target)
	elif scoring == "points500":
		out.append("Wertung: Platzierungen (Punkte zählen nur, wenn die Runde beim ersten Fertigen endet).")
	else:
		out.append("Wertung: keine – jede Runde zählt für sich, gezählt werden die Siege.")
	out.append("%d Handkarten zu Beginn." % hand_size)
	if draw_rule == "one":
		out.append("Passt nichts, ziehst du eine Karte.")
	else:
		out.append("Passt nichts, ziehst du so lange, bis eine Karte passt.")
	match drawn_card:
		"may":
			out.append("Eine passende gezogene Karte darfst du sofort legen.")
		"must":
			out.append("Eine passende gezogene Karte musst du sofort legen.")
		"may_not":
			out.append("Eine gezogene Karte darfst du erst im nächsten Zug legen.")
	if stacking == "same":
		out.append("Stapeln: Wer eine Ziehkarte abbekommt, darf die gleiche drauflegen. Die Summe wandert weiter; bei der Farbjagd zieht das letzte Opfer bis zur Farbe.")
	else:
		out.append("Kein Stapeln: Wer eine Ziehkarte abbekommt, zieht und setzt aus.")
	var cond := "keine Karte in der aktuellen Farbe hat"
	if wild_counts_for_bluff:
		cond += " und keinen anderen Joker"
	match wild_restriction:
		"bluff":
			out.append("Wünscher +2 und Farbjagd nur, wenn man %s. Der Nächste darf anzweifeln." % cond)
		"enforce":
			out.append("Wünscher +2 und Farbjagd nur, wenn man %s – die App achtet darauf." % cond)
		"free":
			out.append("Wünscher +2 und Farbjagd dürfen immer gelegt werden.")
	if jagd_wild_stops:
		out.append("Farbjagd: Ein gezogener Joker beendet das Ziehen.")
	match mau_call:
		"catch":
			out.append("„Mau!“ bei der vorletzten Karte rufen. Wer es vergisst und erwischt wird, zieht %d." % mau_penalty)
		"auto":
			out.append("„Mau!“ bei der vorletzten Karte rufen. Wer es vergisst, zieht automatisch %d." % mau_penalty)
		"reminder":
			out.append("„Mau!“ rufen ist freiwillig, die App erinnert nur daran.")
		"off":
			out.append("Ohne „Mau!“-Ansage.")
	if backs_visible:
		out.append("Die Rückseiten der Mitspielerkarten sind sichtbar.")
	else:
		out.append("Die Rückseiten der Mitspielerkarten sind verdeckt.")
	if peek_own_backs:
		out.append("Eigene Rückseiten darfst du ansehen.")
	if two_player_reverse_skips:
		out.append("Zu zweit wirkt der Richtungswechsel wie Aussetzen.")
	if flip_last_card == "execute":
		out.append("Ein Flip als letzte Karte wird noch ausgeführt; gewertet wird die neue Seite.")
	else:
		out.append("Ein Flip als letzte Karte wird nicht mehr ausgeführt.")
	return out
