class_name TableSource
extends Node
# Einheitliche Schnittstelle der Spielsteuerung für die Tischoberfläche (docs/BETA1_PLAN.md Abschnitt 6, Modul G).
# Umsetzungen: LocalTable ("solo" | "pass"), HostTable ("host"), ClientTable ("client").
# Die Oberfläche hört auf state_changed (Ereignisse abspielen, dann mit der Sicht abgleichen) und schickt Aktionen mit act().
# Sichten und Ereignisse sind bereits für local_seat() gefiltert; eine fremde Hand kommt hier nie an.

signal state_changed(events: Array, view: Dictionary)   # Oberfläche spielt events ab und gleicht dann mit view ab
signal notice(text: String)                                # Hinweis (Ablehnung, Verbindung, getrennte Spieler …)
signal handover(next_seat: int, name: String)              # nur Weitergeben: Sichtschutz zeigen, danach reveal() aufrufen
signal lobby_changed(lobby: Dictionary)                    # Netz: Lobby-Stand {t:"lobby", rev, players, rules, host_id}
signal connection_changed(state: String)                   # Client: "connecting" | "open" | "closed" | "rejected"
signal game_started(seat: int)                             # zusätzlich: Partie beginnt (Lobby → Tisch), eigener Platz
# Mau-Mau Flip (Beta 1.6.3, Easter Eggs Teil 2 „Necken“, docs/module/eastereggs2.md Abschnitt 6.1 „Schnittstelle“):
signal fx_event(msg: Dictionary)          # angenommenes Necken {t:"fx", k, from, to?, r?} – kommt auf allen Geräten (auch beim Absender);
                                          # Beta 1.6.6: k "kissen" (nur beim Leger: Bestätigung) und "kissen_pop" (alle, from nur bei reveal)
signal fx_refused(why: String)            # eigener Wunsch abgelehnt: "late" | "busy" | "rate" (kein Fehlerton, leise Zeile bzw. ausgrauen);
                                          # Beta 1.6.6: fx_refused_kind sagt, ob es ein Furzkissen war
signal fx_offs_changed(seats: Array)      # Plätze mit Necken aus (fx_offs) haben sich geändert
# Beta 1.6.16: eigene Aktionen kamen nicht beim Gastgeber an (nur ClientTable; Verbindung still abgerissen). actions = die act-Wörterbücher
signal act_lost(actions: Array)

# Necken (Beta 1.6.3): Gastgeber = maßgebliche Regeln, sonst lokaler Spiegel (gleiche Sichten, Ereignisse und fx) für fx_check().
var tease := TeaseRules.new()
var fx_clock := Callable()                # Tests: () -> Monotonuhr in ms fürs Necken (sonst Time.get_ticks_msec bzw. HostTable._now_ms)
var _fx_offs: Array = []                  # Plätze mit Necken aus (vom Gastgeber; beim Gastgeber selbst berechnet)
var _fx_off_self := setting_fx_off()      # Necken an diesem Gerät aus (Einstellung „necken“; set_fx_off ändert es)
# Furzkissen (Beta 1.6.6, docs/module/eastereggs2.md Abschnitt 12.6):
var fx_refused_kind := ""                 # Art der zuletzt abgelehnten eigenen Bitte: "kissen" oder "" (übrige Arten); gilt beim fx_refused
var fx_rand := Callable()                 # Tests: () -> float in [0, 1] für die Kissen-Sperre (sonst randf()); nur Gastgeber und Übung

const SAVE_PATH := "user://laufende_partie.json"
# Mau-Mau Flip (Beta 1.6.1, Gastgeber-Übergabe): Netzpartie in eigener Datei (MatchSnapshot, docs/module/uebergabe.md Abschnitt 2),
# damit sich Übung/Weitergeben und Netzpartie nicht gegenseitig überschreiben. Ein Gerät spielt immer nur eine Netzpartie.
const NET_SAVE_PATH := "user://netz_partie.json"


# Spielaktion des eigenen Platzes, z. B. {a:"play", card:17, color:"blau"}. Ablehnungen kommen als notice.
func act(_action: Dictionary) -> void:
	pass


# Wessen Hand gerade gezeigt wird (-1: keine, z. B. während der Sichtschutz auf reveal() wartet).
func local_seat() -> int:
	return -1


# "solo" | "pass" | "host" | "client"
func mode() -> String:
	return ""


# Letzte ausgegebene Sicht (für einen Neuaufbau der Szene); {} vor dem ersten Stand.
func current_view() -> Dictionary:
	return {}


# Weitergeben: Der Sichtschutz wurde aufgedeckt, jetzt kommt die Sicht des neuen Menschen.
func reveal() -> void:
	pass


# Tisch verlassen: Netz schließen, laufende Partie verwerfen (Speicherstand löschen).
func leave() -> void:
	pass


# --- Necken (Beta 1.6.3, docs/module/eastereggs2.md Abschnitt 6.1) ---

# Necken schicken: {k:"snore"|"alarm"|"ball", to} bzw. {k:"react", r}; Beta 1.6.6: {k:"kissen", to, reveal}. Ergebnis kommt als fx_event
# (an alle; Kissen: Bestätigung nur an den Leger) oder fx_refused.
func send_fx(_req: Dictionary) -> void:
	pass


# Necken an diesem Gerät aus (true) bzw. an. Netz: der Gastgeber erfährt es (fx_pref), alle anderen über fx_offs.
func set_fx_off(off: bool) -> void:
	_fx_off_self = off


func fx_off() -> bool:
	return _fx_off_self


# Plätze, die gerade nicht geneckt werden wollen (Menü-Hinweis „%s möchte gerade nicht geneckt werden.“).
func fx_off_seats() -> Array:
	return _fx_offs.duplicate()


# Was in dieser Spielart geht: {kinds: [...], bots_only} (TeaseRules.caps).
func fx_caps() -> Dictionary:
	return TeaseRules.caps(mode())


# Lokale Vorprüfung eines Wunschs für den eigenen Platz ("" = geht jetzt, sonst Grund wie TeaseRules.check) – zum Ausgrauen von Menü
# und Reaktionen. Der Gastgeber prüft beim Absenden noch einmal (seine Uhr läuft nie kürzer).
func fx_check(req: Dictionary) -> String:
	return tease.check(local_seat(), req, fx_table(), _fx_now())


# Wie lange das Ziel noch überlegen muss, bis Schnarchen/Wecker gehen (ms; 0 = jetzt; −1 = nicht am Zug).
func fx_slow_left_ms(seat: int) -> int:
	return tease.slow_left_ms(seat, _fx_now())


# Tisch-Beschreibung für TeaseRules.check aus der aktuellen Sicht (eigener Platz mit der eigenen Einstellung).
func fx_table() -> Dictionary:
	var offs := _fx_offs.duplicate()
	var me := local_seat()
	if me >= 0:
		offs.erase(me)
		if _fx_off_self:
			offs.append(me)
	return TeaseRules.table_from_view(current_view(), offs, mode())


func _fx_now() -> int:
	return int(fx_clock.call()) if fx_clock.is_valid() else Time.get_ticks_msec()


# Angenommenes fx verbuchen und melden (Spiegel und Gastgeber).
func _fx_deliver(m: Dictionary) -> void:
	tease.commit(m, _fx_now())
	fx_event.emit(m)


# Eigene Bitte abgelehnt (late/busy/rate): fx_refused_kind gilt während des Signals (und bis zur nächsten Ablehnung).
func _fx_refuse(why: String, k := "") -> void:
	fx_refused_kind = TeaseRules.CUSHION if k == TeaseRules.CUSHION else ""
	fx_refused.emit(why)


# Beta 1.6.6: Sperre des Legers nach einem Kissen, zufällig 1–3 min (maßgeblich nur beim Gastgeber bzw. in der Übung).
func _cushion_block_ms() -> int:
	return TeaseRules.cushion_block_ms(float(fx_rand.call()) if fx_rand.is_valid() else randf())


# Einstellung „necken“ dieses Geräts (App.settings; ohne App: an).
static func setting_fx_off() -> bool:
	var loop := Engine.get_main_loop()
	var app: Node = (loop as SceneTree).root.get_node_or_null("App") if loop is SceneTree else null
	if app != null and app.get("settings") is AppSettings:
		return not bool((app.get("settings") as AppSettings).get_value("necken", true))
	return false


# --- Speicherstand (user://laufende_partie.json bzw. NET_SAVE_PATH), gemeinsam für alle Spielarten mit eigenem Regelwerk ---

static func has_saved(path := SAVE_PATH) -> bool:
	return not load_saved(path).is_empty()


# {format, mode, game: MauGame.to_dict(), players: [...], …} oder {} (fehlt/kaputt).
static func load_saved(path := SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not (data as Dictionary).get("game") is Dictionary:
		return {}
	return data


static func clear_saved(path := SAVE_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if FileAccess.file_exists(path + ".tmp"):
		DirAccess.remove_absolute(path + ".tmp")


# Atomar schreiben (erst .tmp, dann umbenennen): Ein Absturz mitten im Schreiben lässt den alten Stand stehen. false = Fehler.
static func write_saved(path: String, data: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return DirAccess.rename_absolute(tmp, path) == OK
