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
