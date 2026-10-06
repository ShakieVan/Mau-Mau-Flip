class_name RuleSets
extends RefCounted
# Gespeicherte Regelsätze und die Regeln des letzten Gastgebers (Nutzerwunsch 06.10.2026, docs/BETA1_PLAN.md 9).
#  - Eigene Sätze: AppSettings "regelsaetze" = [{name, regeln}, …], höchstens MAX, Namen höchstens NAME_MAX Zeichen (Zeichen wie
#    Spielernamen, dazu & + ( )), gleicher Name ohne Rücksicht auf Groß- und Kleinschreibung = derselbe Satz (Überschreiben).
#  - Gastgeber-Platz: AppSettings "regeln_gastgeber" = {host, regeln}. Ein App-Gast merkt sich die Regeln des Gastgebers
#    automatisch, sobald gespielt wird (jede Sicht am Tisch, nicht schon die Lobby: bloßes Beitreten soll den Platz nicht
#    überschreiben); genau ein Platz, wird überschrieben, zählt nicht zu den eigenen Sätzen. So kann ein anderer mit denselben
#    Regeln eröffnen, wenn der Gastgeber gehen muss.
#  - Zuletzt gewählter Satz: AppSettings "regelsatz_gewaehlt" (Name). Haben zwei Sätze dieselben Regeln, zeigen Editor,
#    Regelzeile und Lobby überall diesen Namen (match_name); geladen bzw. gespeichert wird er mit choose().
#  - Regeln werden immer über RuleConfig.from_dict(…).to_dict() gespeichert: unbekannte Optionen fallen weg, ungültige Werte
#    werden zum Standard, fehlende (Sätze einer älteren Version) bekommen den Standard.
#  - Gleich heißt: gleiche Regeln; ohne Kartentausch zählt die Tauschrichtung nicht (wie RuleConfig.preset_name).
#  - Schlägt das Schreiben der Einstellungsdatei fehl (z. B. Speicher voll), melden save()/remove() das und lassen den Stand im
#    Speicher wie vorher.
# Alle Funktionen nehmen optional ein AppSettings (Tests); ohne gilt App.settings. Fehlt beides, bleibt alles leer.

const KEY := "regelsaetze"
const HOST_KEY := "regeln_gastgeber"
const CHOSEN_KEY := "regelsatz_gewaehlt"
const MAX := 12
const NAME_MAX := 20
const NAME_MARKS := "&+()"           # zusätzlich zu AppSettings.NAME_MARKS

# Ergebnisse von save()
const OK_SAVED := ""
const ERR_NAME := "name"             # leerer Name (nach dem Bereinigen)
const ERR_FULL := "voll"             # schon MAX Sätze und der Name ist neu
const ERR_WRITE := "schreiben"       # Einstellungsdatei nicht geschrieben (bzw. keine Einstellungen vorhanden)


# --- Namen ---

static func name_char_ok(c: int) -> bool:
	return AppSettings.name_char_ok(c) or NAME_MARKS.contains(char(c))


static func _name_chars(text: String) -> String:
	var out := ""
	for i in range(text.length()):
		if name_char_ok(text.unicode_at(i)):
			out += text[i]
	return out


# Beim Tippen: unerlaubte Zeichen weglassen, Länge begrenzen (Leerzeichen am Ende bleiben).
static func filter_name(text: String) -> String:
	return _name_chars(text).left(NAME_MAX)


# Zum Speichern: gefiltert, ohne Rand- und doppelte Leerzeichen, höchstens NAME_MAX Zeichen.
static func clean_name(text: String) -> String:
	var out := _name_chars(text).strip_edges()
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.left(NAME_MAX).strip_edges()


# Namensvorschlag für die Regeln eines Gastgebers: „Regeln von Lena“; zu lang → „Von Lena“, sonst gekürzt.
static func suggestion_for_host(host_name: String) -> String:
	var who := clean_name(host_name)
	if who == "":
		return "Regeln vom Gastgeber"
	for pattern in ["Regeln von %s", "Von %s"]:
		var s := (pattern as String) % who
		if s.length() <= NAME_MAX:
			return s
	return clean_name("Von " + who)


# Bezeichnung des Gastgeber-Platzes: „Zuletzt gespielt bei Lena“
static func host_title(host_name: String) -> String:
	return "Zuletzt gespielt bei %s" % host_name


# --- Prüfen (AppSettings.sanitize) ---

static func normalized(rules: Dictionary) -> Dictionary:
	return RuleConfig.from_dict(rules).to_dict()


# Liste der Sätze bereinigen; null = gar keine Liste (dann gilt der Standard []).
static func sanitize_sets(value: Variant) -> Variant:
	if not value is Array:
		return null
	var out: Array = []
	var seen := {}
	for entry in value:
		var e := _clean_entry(entry)
		if e.is_empty():
			continue
		var k := str(e.name).to_lower()
		if seen.has(k):
			continue
		seen[k] = true
		out.append(e)
		if out.size() >= MAX:
			break
	return out


static func _clean_entry(entry: Variant) -> Dictionary:
	if not entry is Dictionary:
		return {}
	var d: Dictionary = entry
	var n := clean_name(str(d.get("name", ""))) if d.get("name") is String else ""
	if n == "" or not d.get("regeln") is Dictionary:
		return {}
	return {"name": n, "regeln": normalized(d.regeln)}


# Gastgeber-Platz bereinigen: {} = leer, null = ungültig (auch leere Regeln, wie bei remember_host).
static func sanitize_host(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var d: Dictionary = value
	if d.is_empty():
		return {}
	if not d.get("regeln") is Dictionary or (d.regeln as Dictionary).is_empty():
		return null
	return {"host": NetProtocol.clean_name(str(d.get("host", "")), "Gastgeber"), "regeln": normalized(d.regeln)}


# --- Vergleich ---

static func comparable(cfg: RuleConfig) -> Dictionary:
	var d := cfg.to_dict()
	if cfg.swap_cards == "off":
		d["swap_direction"] = RuleConfig.CHOICES["swap_direction"][0]
	return d


static func same(a: RuleConfig, b: RuleConfig) -> bool:
	return a != null and b != null and comparable(a) == comparable(b)


# --- Eigene Sätze ---

static func list(st: AppSettings = null) -> Array:
	var s := _settings(st)
	if s == null:
		return []
	var v: Variant = s.get_value(KEY, [])
	return v if v is Array else []


static func names(st: AppSettings = null) -> Array[String]:
	var out: Array[String] = []
	for e in list(st):
		out.append(str(e.name))
	return out


static func count(st: AppSettings = null) -> int:
	return list(st).size()


# Platz des Satzes mit diesem Namen (ohne Rücksicht auf Groß- und Kleinschreibung), -1 = keiner.
static func index_of(set_name: String, st: AppSettings = null) -> int:
	var key := clean_name(set_name).to_lower()
	if key == "":
		return -1
	var all := list(st)
	for i in all.size():
		if str(all[i].name).to_lower() == key:
			return i
	return -1


static func has_set(set_name: String, st: AppSettings = null) -> bool:
	return index_of(set_name, st) >= 0


# Regeln eines Satzes; null = gibt es nicht.
static func config(set_name: String, st: AppSettings = null) -> RuleConfig:
	var i := index_of(set_name, st)
	if i < 0:
		return null
	return RuleConfig.from_dict(list(st)[i].regeln)


# Gespeicherter Name in der gespeicherten Schreibweise ("" = gibt es nicht).
static func stored_name(set_name: String, st: AppSettings = null) -> String:
	var i := index_of(set_name, st)
	return str(list(st)[i].name) if i >= 0 else ""


# Würde save() einen vorhandenen Satz mit anderen Regeln ersetzen? (dann vorher nachfragen)
static func would_overwrite(set_name: String, cfg: RuleConfig, st: AppSettings = null) -> bool:
	var old := config(set_name, st)
	return old != null and not same(old, cfg)


# Speichern bzw. Überschreiben (gleicher Name: Platz bleibt, Schreibweise wie neu getippt); der Satz gilt danach als gewählt.
# Ergebnis OK_SAVED, ERR_NAME, ERR_FULL, ERR_WRITE.
static func save(set_name: String, cfg: RuleConfig, st: AppSettings = null) -> String:
	var s := _settings(st)
	var n := clean_name(set_name)
	if n == "" or cfg == null:
		return ERR_NAME
	if s == null:
		return ERR_WRITE
	var all := list(s)
	var entry := {"name": n, "regeln": cfg.to_dict()}
	var i := index_of(n, s)
	if i >= 0:
		all[i] = entry
	elif all.size() >= MAX:
		return ERR_FULL
	else:
		all.append(entry)
	if not _write(s, KEY, all):
		return ERR_WRITE
	choose(n, s)
	return OK_SAVED


# Löschen; false = gibt es nicht oder die Datei wurde nicht geschrieben (dann bleibt der Satz).
static func remove(set_name: String, st: AppSettings = null) -> bool:
	var s := _settings(st)
	var i := index_of(set_name, s)
	if i < 0 or s == null:
		return false
	var was_chosen := chosen_name(s).to_lower() == str(list(s)[i].name).to_lower()
	var all := list(s)
	all.remove_at(i)
	if not _write(s, KEY, all):
		return false
	if was_chosen:
		choose("", s)
	return true


# Name des Satzes mit genau diesen Regeln ("" = keiner): der zuletzt gewählte, wenn er passt, sonst der erste passende.
static func match_name(cfg: RuleConfig, st: AppSettings = null) -> String:
	if cfg == null:
		return ""
	var chosen := chosen_name(st)
	if chosen != "" and matches(chosen, cfg, st):
		return chosen
	for e in list(st):
		if same(RuleConfig.from_dict(e.regeln), cfg):
			return str(e.name)
	return ""


# --- Zuletzt gewählter Satz ---

# Name in der gespeicherten Schreibweise ("" = keiner bzw. gibt es nicht mehr).
static func chosen_name(st: AppSettings = null) -> String:
	var s := _settings(st)
	if s == null:
		return ""
	var n := str(s.get_value(CHOSEN_KEY, ""))
	return stored_name(n, s) if n != "" else ""


# Satz als gewählt merken ("" = keiner, z. B. nach einer Voreinstellung). Schreibt nur bei einer Änderung.
static func choose(set_name: String, st: AppSettings = null) -> void:
	var s := _settings(st)
	if s == null:
		return
	var n := stored_name(set_name, s) if set_name != "" else ""
	if str(s.get_value(CHOSEN_KEY, "")) != n:
		s.set_value(CHOSEN_KEY, n)


static func matches(set_name: String, cfg: RuleConfig, st: AppSettings = null) -> bool:
	var c := config(set_name, st)
	return c != null and same(c, cfg)


# --- Regeln des letzten Gastgebers ---

# {host, regeln} oder {} (noch bei keinem Gastgeber gewesen).
static func host_slot(st: AppSettings = null) -> Dictionary:
	var s := _settings(st)
	if s == null:
		return {}
	var v: Variant = s.get_value(HOST_KEY, {})
	return v if v is Dictionary and (v as Dictionary).get("regeln") is Dictionary else {}


static func host_name(st: AppSettings = null) -> String:
	return str(host_slot(st).get("host", ""))


static func host_config(st: AppSettings = null) -> RuleConfig:
	var slot := host_slot(st)
	return RuleConfig.from_dict(slot.regeln) if not slot.is_empty() else null


static func host_matches(cfg: RuleConfig, st: AppSettings = null) -> bool:
	var h := host_config(st)
	return h != null and same(h, cfg)


# Merkt sich die Regeln eines Gastgebers (Sicht `rules` am Tisch des App-Gasts). Schreibt nur bei einer Änderung; leere oder
# fehlende Regeln ändern nichts. true = gespeichert bzw. schon so gemerkt.
static func remember_host(rules: Variant, from_host: String, st: AppSettings = null) -> bool:
	var s := _settings(st)
	if s == null or not rules is Dictionary or (rules as Dictionary).is_empty():
		return false
	var entry := {"host": NetProtocol.clean_name(from_host, "Gastgeber"), "regeln": normalized(rules)}
	if host_slot(s) == entry:
		return true
	return _write(s, HOST_KEY, entry)


# Name des Gastgebers aus einer Lobby-Nachricht {players, host_id}; fallback, wenn er dort fehlt.
static func host_name_in_lobby(lobby: Dictionary, fallback := "") -> String:
	var host_id := int(lobby.get("host_id", -1))
	var players: Variant = lobby.get("players", [])
	if players is Array:
		for p in players:
			if p is Dictionary and int((p as Dictionary).get("id", -2)) == host_id:
				return str((p as Dictionary).get("name", fallback))
	return fallback


# --- intern ---

# set_value mit Rücknahme: Schlägt das Speichern fehl, gilt im Speicher wieder der alte Wert (sonst stünde bis zum Neustart ein
# Satz da, den es in der Datei nicht gibt).
static func _write(s: AppSettings, key: String, value: Variant) -> bool:
	var had := s.data.has(key)
	var before: Variant = s.data.get(key)
	if s.set_value(key, value):
		return true
	if had:
		s.data[key] = before
	else:
		s.data.erase(key)
	s.changed.emit(key, s.get_value(key))
	return false


static func _settings(st: AppSettings) -> AppSettings:
	if st != null:
		return st
	var loop := Engine.get_main_loop()
	var app: Node = (loop as SceneTree).root.get_node_or_null("App") if loop is SceneTree and (loop as SceneTree).root != null else null
	if app != null and app.get("settings") is AppSettings:
		return app.get("settings") as AppSettings
	return null
