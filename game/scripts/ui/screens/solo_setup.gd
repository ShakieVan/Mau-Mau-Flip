class_name SoloSetupScreen
extends AppScreen
# Übungsspiel einrichten: Anzahl Computergegner (1–5), Regeln (Voreinstellung oder angepasst), Start.

const BOT_NAMES := ["Kater Karlo", "Mimi", "Socke", "Tiger", "Luna", "Pfötchen", "Minka", "Felix", "Nala"]

var bots := 3
var _seats: HBoxContainer
var _rules: RulesBar


func build() -> void:
	bots = clampi(int(UiApp.setting("uebung_gegner", 3)), 1, 5)
	var content := page("Übungsspiel")
	var cols := ScreenKit.hbox(28)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cols)
	# links: Gegner
	var left := ScreenKit.card()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var lv := ScreenKit.vbox(18)
	left.add_child(lv)
	lv.add_child(ScreenKit.heading("Computergegner"))
	var step := ScreenKit.stepper(1, 5, bots, _on_bots)
	step.name = "Gegner"
	lv.add_child(step)
	_seats = ScreenKit.hbox(12)
	lv.add_child(_seats)
	lv.add_child(ScreenKit.hint("Du sitzt unten, die Computergegner im Halbkreis um den Tisch. Sie denken kurz nach, bevor sie legen.", 19))
	# rechts: Regeln und Start
	var right := ScreenKit.card()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var rv := ScreenKit.vbox(18)
	right.add_child(rv)
	_rules = RulesBar.new()
	_rules.nav = nav
	rv.add_child(_rules)
	rv.add_child(ScreenKit.spacer(false))
	var start := ScreenKit.button("Los geht's", "PrimaryButton", "start")
	start.name = "Start"
	start.custom_minimum_size = Vector2(0, 100)
	start.add_theme_font_size_override("font_size", 30)
	start.pressed.connect(start_game)
	rv.add_child(start)
	_refresh_seats()


func on_enter() -> void:
	if _rules != null:
		_rules.nav = nav
		_rules.refresh()


func _on_bots(v: int) -> void:
	bots = v
	var app := UiApp.app()
	var st: Variant = app.get("settings") if app != null else null
	if st is Object:
		(st as Object).call("set_value", "uebung_gegner", v)
	_refresh_seats()


func _refresh_seats() -> void:
	for c in _seats.get_children():
		c.queue_free()
	_seats.add_child(ScreenKit.avatar(0, _my_name(), "human", 60.0))
	for i in bots:
		_seats.add_child(ScreenKit.avatar(i + 1, BOT_NAMES[i], "bot", 60.0))


static func _my_name() -> String:
	var n := str(UiApp.setting("name", ""))
	return n if n != "" else "Du"


func players() -> Array:
	var out: Array = [{"name": _my_name(), "kind": "human"}]
	for i in bots:
		out.append({"name": BOT_NAMES[i], "kind": "bot"})
	return out


func start_game() -> void:
	var source := GameStarter.local("solo", RulesBar.current(), players())
	if source == null:
		toast("Die Spielsteuerung fehlt.")
		return
	nav.push(TableScreen.create(source, source.start))
