class_name AppSettings
extends RefCounted

# Einstellungen der App (docs/BETA1_PLAN.md 9): user://einstellungen.json, jede Änderung wird sofort gespeichert (über .tmp und
# Umbenennen, die Vorversion bleibt als .bak – Muster Draw2Race ProgressStore). Gespeichert werden nur ausdrücklich gesetzte Werte;
# alles andere kommt aus den Standardwerten. So folgt z. B. der Beta-Kanal der installierten Version, bis jemand ihn umschaltet.
# Reihenfolge in get_value: gespeicherter Wert → Standardwert dieser Datei → Vorgabe des Aufrufers.
# JSON kennt nur Kommazahlen: Zahlen in "regeln" kommen als float zurück (RuleConfig.from_dict wandelt mit int()).
# Gespeicherte Regelsätze ("regelsaetze"), die Regeln des letzten Gastgebers ("regeln_gastgeber") und den zuletzt gewählten Satz
# ("regelsatz_gewaehlt") verwaltet RuleSets; beim Laden werden ihre Regeln über RuleConfig vereinheitlicht (Zahlen wieder int).

signal changed(key: String, value: Variant)

const PATH := "user://einstellungen.json"
const VERSION := 1
const MAU_TON := ["aus", "leise", "normal"]
const TOENE := ["aus", "leise", "normal"]   # übrige Spieltöne (AppSound), Standard aus
const EFFEKTE := ["voll", "reduziert"]
const SORTIERUNG := ["farbe", "wert", "punkte", "manuell"]
const SCHRIFT := ["normal", "gross", "sehr_gross"]   # Schriftgröße je Gerät (UiFonts.LEVELS), Beta 1.0.1
const RECENT_NAMES := 12          # so viele zuletzt benutzte Namen (Weitergeben) bleiben gemerkt

# Spielername wie Draw2Race: höchstens 12 Zeichen; Buchstaben samt Umlauten und ß, Ziffern, Leerzeichen und - _ . ' ! ?
const NAME_MAX := 12
const NAME_MARKS := " -_.'!?"

var path := PATH
var data := {}                    # nur ausdrücklich gesetzte Werte

func _init(save_path := PATH) -> void:
	path = save_path
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(candidate)) != OK or not json.data is Dictionary:
			continue
		var loaded: Dictionary = json.data
		for key in loaded:
			if str(key) == "version":
				continue
			var value: Variant = sanitize(str(key), loaded[key])
			if value != null:
				data[str(key)] = value
		break

static func defaults() -> Dictionary:
	# Standardwerte. Beta-Kanal: an, wenn die installierte Version keine reguläre ist (X.Y.Z mit Z ≠ 0).
	# Mau-Ton (Aufnahmen „Mao“/„Mao-Mao“) ab Werk normal, die übrigen Spieltöne ab Werk aus (Nutzerwunsch 05.10.2026).
	# hervorheben: spielbare Karten der eigenen Hand hervorheben – persönliche Einstellung je Gerät, nie eine Regel (AGENTS.md 24).
	# grosser_modus: großer Tisch für Sehschwäche (Beta 1.1.1, BigLayout); zug_vibration: kurz vibrieren, wenn du dran bist.
	return {"name": "", "mau_ton": "normal", "toene": "aus", "vibration": true, "effekte": "voll", "beta": not app_version().ends_with(".0"),
		"sortierung": "farbe", "hervorheben": true, "regeln": {}, "letzte_namen": [], "regelsaetze": [], "regeln_gastgeber": {},
		"regelsatz_gewaehlt": "", "bot_tempo": 0.5, "schrift": "normal", "grosser_modus": false, "zug_vibration": false}

static func app_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))

static func sanitize(key: String, value: Variant) -> Variant:
	# Prüft einen Wert für einen bekannten Schlüssel; null = ungültig (dann gilt der Standardwert). Unbekannte Schlüssel (Bedarf
	# anderer Module) werden unverändert übernommen.
	match key:
		"name":
			return clean_name(str(value)) if value is String else null
		"mau_ton":
			return value if value is String and MAU_TON.has(value) else null
		"toene":
			return value if value is String and TOENE.has(value) else null
		"effekte":
			return value if value is String and EFFEKTE.has(value) else null
		"schrift":
			return value if value is String and SCHRIFT.has(value) else null
		"sortierung":
			return value if value is String and SORTIERUNG.has(value) else null
		"vibration", "beta", "hervorheben", "grosser_modus", "zug_vibration":
			return value if value is bool else null
		"bot_tempo":                      # Tempo der Computergegner 0 (gemütlich) … 1 (flott), 0,5 = Standard
			return clampf(float(value), 0.0, 1.0) if value is float or value is int else null
		"regeln":
			return RuleSets.migrate(value) if value is Dictionary else null
		"regelsaetze":                    # gespeicherte Regelsätze [{name, regeln}, …], siehe RuleSets
			return RuleSets.sanitize_sets(value)
		"regeln_gastgeber":               # Regeln des letzten Gastgebers {host, regeln}, siehe RuleSets
			return RuleSets.sanitize_host(value)
		"regelsatz_gewaehlt":             # Name des zuletzt gewählten Regelsatzes ("" = keiner), siehe RuleSets
			return RuleSets.clean_name(value) if value is String else null
		"letzte_namen":
			if not value is Array:
				return null
			var names: Array = []
			for entry in value:
				var n := clean_name(str(entry))
				if n != "" and not names.has(n):
					names.append(n)
			return names.slice(0, RECENT_NAMES)
	return value

func get_value(key: String, fallback: Variant = null) -> Variant:
	if data.has(key):
		var stored: Variant = data[key]
		return stored.duplicate(true) if stored is Dictionary or stored is Array else stored
	var builtin := defaults()
	if builtin.has(key):
		return builtin[key]
	return fallback

func has_value(key: String) -> bool:
	# Wurde der Wert ausdrücklich gesetzt (sonst gilt der Standardwert)?
	return data.has(key)

func set_value(key: String, value: Variant) -> bool:
	# Setzt und speichert sofort. false = ungültiger Wert (nichts geändert) oder Speichern fehlgeschlagen.
	var clean: Variant = sanitize(key, value)
	if clean == null:
		push_warning("Einstellung %s: ungültiger Wert %s" % [key, str(value)])
		return false
	data[key] = clean
	var ok := save()
	changed.emit(key, clean)
	return ok

func set_values(values: Dictionary) -> bool:
	# Mehrere Werte mit einem Speichervorgang.
	var any := false
	for key in values:
		var clean: Variant = sanitize(str(key), values[key])
		if clean != null:
			data[str(key)] = clean
			any = true
	var ok := save() if any else true
	for key in values:
		if data.has(str(key)):
			changed.emit(str(key), data[str(key)])
	return ok

func reset(key: String) -> bool:
	# Zurück zum Standardwert.
	if not data.has(key):
		return true
	data.erase(key)
	var ok := save()
	changed.emit(key, get_value(key))
	return ok

func save() -> bool:
	var out := data.duplicate(true)
	out["version"] = VERSION
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(out, "\t"))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
	return DirAccess.rename_absolute(path + ".tmp", path) == OK

# --- Spielername ---

static func name_char_ok(c: int) -> bool:
	return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) \
		or (c >= 0xC0 and c <= 0x17F and c != 0xD7 and c != 0xF7) or NAME_MARKS.contains(char(c))

static func name_chars(text: String) -> String:
	var out := ""
	for i in range(text.length()):
		if name_char_ok(text.unicode_at(i)):
			out += text[i]
	return out

static func filter_name(text: String) -> String:
	# Beim Tippen: unerlaubte Zeichen weglassen, Länge begrenzen (Leerzeichen am Ende bleiben, man tippt ja weiter).
	return name_chars(text).left(NAME_MAX)

static func clean_name(text: String) -> String:
	# Zum Speichern: gefiltert, ohne Rand- und doppelte Leerzeichen, höchstens NAME_MAX Zeichen.
	var out := name_chars(text).strip_edges()
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.left(NAME_MAX).strip_edges()

func player_name() -> String:
	# Eigener Name oder ein einmal gewählter Vorschlag „Spieler NN“ (bleibt gleich, Schlüssel name_hint).
	var own := str(get_value("name", ""))
	if own != "":
		return own
	var hint := clean_name(str(data.get("name_hint", "")))
	if hint == "":
		hint = "Spieler %d" % randi_range(10, 99)
		set_value("name_hint", hint)
	return hint

func remember_names(names: Array) -> void:
	# Weitergeben: zuletzt benutzte Namen vorn, ohne Doppelte.
	var merged: Array = names.duplicate()
	merged.append_array(get_value("letzte_namen", []))
	set_value("letzte_namen", merged)

# Faktor für die Bedenkzeit der Computergegner aus dem Tempo-Regler (0 gemütlich … 1 flott): 2,5 … 1 (bei 0,5) … 0,4.
# Betrifft nur die Bedenkzeit (GameTable.think_factor), nicht die Animationen; im WLAN gilt der Regler des Gastgebers.
static func think_factor(tempo: float) -> float:
	return pow(2.5, 1.0 - 2.0 * clampf(tempo, 0.0, 1.0))
