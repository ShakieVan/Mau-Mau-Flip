class_name UiApp
extends RefCounted
# Zugriff der Oberfläche auf den Autoload „App“ (Modul C). Alles ist abgesichert: In Tests und Demos kann App fehlen oder
# unvollständig sein; dann gelten Standardwerte (Effekte voll, kein Ton, keine Vibration).

static func app() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("App")


static func setting(key: String, fallback: Variant = null) -> Variant:
	var a := app()
	if a == null:
		return fallback
	var s: Variant = a.get("settings")
	if s is Object and (s as Object).has_method("get_value"):
		return (s as Object).call("get_value", key, fallback)
	return fallback


# Effektstufe „reduziert“: kürzere Abläufe, weniger Teilchen, kein Wackeln
static func reduced_effects() -> bool:
	return str(setting("effekte", "voll")) == "reduziert"


static func sound(name: String) -> void:
	var a := app()
	if a == null:
		return
	var s: Variant = a.get("sound")
	if s is Object and (s as Object).has_method("play"):
		(s as Object).call("play", name)


# Mau-Mau Flip (Beta 1.6.3, Necken): Ton mit zusätzlicher Dämpfung (AppSound.QUIET_DB = „leise beim Absender“) bzw. ausblenden
static func sound_db(name: String, extra_db: float) -> bool:
	var a := app()
	var s: Variant = a.get("sound") if a != null else null
	if s is Object and (s as Object).has_method("play"):
		return bool((s as Object).call("play", name, extra_db))
	return false


static func fade_sound(name: String, ms := 300) -> void:
	var a := app()
	var s: Variant = a.get("sound") if a != null else null
	if s is Object and (s as Object).has_method("fade_out"):
		(s as Object).call("fade_out", name, ms)


static func vibrate(ms: int, strength := 0.5) -> void:
	var a := app()
	if a != null and a.has_method("vibrate"):
		a.call("vibrate", ms, strength)


static func fade_cheer() -> void:
	# Jubel sanft ausblenden (Tisch verlassen).
	var a := app()
	if a == null:
		return
	var s: Variant = a.get("sound")
	if s is Object and (s as Object).has_method("fade_out_jubel"):
		(s as Object).call("fade_out_jubel")
