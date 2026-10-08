class_name InviteSteps
extends RefCounted
# Welcher Einladen-Schritt der Gastgeber-Lobby leuchtet und welcher einen grünen Haken trägt (Beta 1.0.2, ohne Anzeige).
# ① (WLAN) gilt als geschafft, sobald ein fremdes Gerät die Spielseite aufruft (NetHostSession.page_visited) – Android verrät
# normalen Apps nicht, wer im Spiel-WLAN ist – oder ein Gast beigetreten ist. ② (Spiel) gilt mit dem ersten Gast als geschafft.
# Es leuchtet immer der nächste offene Schritt. Fällt eine Bedingung weg (kein Gast mehr, Netz weg, anderes Netz, z. B. Spiel-WLAN
# geschlossen), beginnt es von vorn.

const KINDS := ["none", "wlan", "hotspot", "game_wifi"]   # feste Netzarten; „starting“ und „problem“ sind Zwischenstände

var net := false             # Spielseite erreichbar (eine Adresse für ②)
var kind := "none"           # letzte feste Netzart
var page_seen := false
var guests := 0              # Mitspieler außer dem Gastgeber und den Computergegnern


func page_visited() -> void:
	page_seen = true


func set_guests(n: int) -> void:
	if n <= 0 and guests > 0:
		page_seen = false
	guests = maxi(n, 0)


func set_net(on: bool, mode: String) -> void:
	if not on:
		page_seen = false
	if KINDS.has(mode) and mode != kind:
		page_seen = false
		kind = mode
	net = on


func step1_done() -> bool:
	return guests > 0 or (net and page_seen)


func step2_done() -> bool:
	return guests > 0


# 1 oder 2 = dieser Schritt leuchtet, 0 = beide erledigt
func glow() -> int:
	if not step1_done():
		return 1
	if not step2_done():
		return 2
	return 0


# --- Weg „Online (Internet)“ (docs/online/ENTWURF.md 3): leuchtet, solange der Raum offen ist und noch kein Online-Gast da ist;
# Haken, sobald einer beigetreten ist (auch während der Gastgeber kurz weg ist).

static func online_glow(state: String, online_guests: int) -> bool:
	return state == "open" and online_guests <= 0


static func online_done(state: String, online_guests: int) -> bool:
	return online_guests > 0 and state in ["open", "away"]
