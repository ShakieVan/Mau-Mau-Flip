class_name GameStarter
extends RefCounted
# Erzeugt die Spielsteuerung (Modul G) für die Bildschirme. Die Quelle wird erst gestartet, wenn der Tisch sie angeschlossen hat
# (TableScreen.create(source, starter)), damit kein erster Stand verloren geht.

static var test_speed := -1.0       # Tests: Pausen der Computergegner (0 = keine); < 0 = Standard


# Übungsspiel ("solo") oder Weitergeben ("pass"); null = ungültige Besetzung
static func local(mode: String, cfg: RuleConfig, players: Array, rng_seed := 0) -> LocalTable:
	var t := LocalTable.new()
	t.name = "Spiel"
	if test_speed >= 0.0:
		t.speed = test_speed
	if not t.setup(mode, players, cfg, rng_seed if rng_seed != 0 else randi()):
		t.free()
		return null
	return t


# Gastgeber (noch ohne Lobby: der Aufrufer hängt ihn ein und ruft open())
static func host() -> HostTable:
	var t := HostTable.new()
	t.name = "Gastgeber"
	t.set_rules(RulesBar.current())
	if test_speed >= 0.0:
		t.speed = test_speed
	return t


# App-Mitspieler (noch nicht verbunden: der Aufrufer hängt ihn ein und ruft join())
static func client() -> ClientTable:
	var t := ClientTable.new()
	t.name = "Mitspieler"
	return t
