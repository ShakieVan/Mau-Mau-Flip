class_name ScreenNav
extends Control
# Bildschirmverwaltung der App (Startszene res://scenes/main.tscn): Stapel von AppScreen-Bildschirmen mit kurzer Überblendung,
# gemeinsamer Tag-Hintergrund mit sanfter Bewegung, Android-Zurück-Taste bzw. Esc = eine Ebene zurück (der oberste Bildschirm
# darf vorher selbst entscheiden, z. B. „Partie verlassen?“). Im Hauptmenü beendet Zurück die App (nur Android).

const FADE_IN := 0.18
const FADE_OUT := 0.12

var stack: Array[AppScreen] = []
var autostart := true               # Tests: false = ohne Hauptmenü starten

var _bg: TableBackground
var _layer: Control
var _toast: Toast
var _toast_layer: CanvasLayer
var _blocker: Control


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.get_theme()
	_bg = TableBackground.new()
	_bg.name = "Hintergrund"
	add_child(_bg)
	_layer = Control.new()
	_layer.name = "Bildschirme"
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer)
	_blocker = Control.new()
	_blocker.name = "Sperre"
	_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.visible = false
	_layer.add_child(_blocker)
	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = 20
	add_child(_toast_layer)
	_toast = Toast.new()
	_toast.night = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_toast_layer.add_child(_toast)


func _ready() -> void:
	get_tree().quit_on_go_back = false
	_bg.tageszeit = 0.0
	_bg.motion = not UiApp.reduced_effects()
	resized.connect(_on_resized)
	_on_resized()
	if autostart and stack.is_empty():
		push(MainMenuScreen.new(), false)


func _on_resized() -> void:
	_bg.table_center = Vector2(size.x * 0.5, size.y * 0.45)


func top() -> AppScreen:
	return stack[-1] if not stack.is_empty() else null


func depth() -> int:
	return stack.size()


# Neuer Bildschirm obenauf; der bisherige bleibt (unsichtbar) erhalten
func push(screen: AppScreen, animate := true) -> AppScreen:
	var old := top()
	stack.append(screen)
	_show(screen, old, false, animate)
	return screen


# Obersten Bildschirm ersetzen (z. B. Lobby → Tisch)
func replace(screen: AppScreen, animate := true) -> AppScreen:
	var old: AppScreen = stack.pop_back() if not stack.is_empty() else null
	stack.append(screen)
	_show(screen, old, true, animate)
	return screen


# Alles bis zum Hauptmenü schließen
func home(animate := true) -> void:
	while stack.size() > 2:
		var s: AppScreen = stack.pop_at(1)
		s.on_leave()
		s.queue_free()
	if stack.size() == 2:
		pop(animate)


func pop(animate := true) -> void:
	if stack.size() <= 1:
		return
	var old: AppScreen = stack.pop_back()
	var now := top()
	_show(now, old, true, animate)


# Zurück (Android-Taste, Esc, Zurück-Knopf)
func go_back() -> void:
	var t := top()
	if t == null:
		return
	if t.on_back():
		return
	if stack.size() > 1:
		pop()
	elif OS.has_feature("android"):
		get_tree().quit()


func toast(text: String, kind := "info") -> void:
	_toast.toast(text, kind)


func _show(screen: AppScreen, old: AppScreen, free_old: bool, animate: bool) -> void:
	screen.nav = self
	if screen.get_parent() == null:
		_layer.add_child(screen)
	screen.visible = true
	screen.process_mode = Node.PROCESS_MODE_INHERIT
	_layer.move_child(screen, -1)
	_bg.visible = not screen.covers_background()
	if old != null and old != screen:
		old.on_leave()
	screen.on_enter()
	if animate and is_inside_tree():
		screen.modulate.a = 0.0
		_block(true)
		var tw := create_tween()
		tw.tween_property(screen, "modulate:a", 1.0, FADE_IN).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(_block.bind(false))
	else:
		screen.modulate.a = 1.0
	if old != null and old != screen:
		if animate and is_inside_tree():
			var tw2 := create_tween()
			tw2.tween_property(old, "modulate:a", 0.0, FADE_OUT)
			tw2.tween_callback(_retire.bind(old, free_old))
		else:
			_retire(old, free_old)


func _retire(old: AppScreen, free_old: bool) -> void:
	if not is_instance_valid(old):
		return
	if free_old:
		old.queue_free()
	elif old != top():
		old.visible = false
		old.process_mode = Node.PROCESS_MODE_DISABLED


# Während der Überblendung liegt eine Sperre über beiden Bildschirmen (kein Doppeltipp in den alten)
func _block(on: bool) -> void:
	_blocker.visible = on
	if on:
		_layer.move_child(_blocker, -1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and (k.keycode == KEY_ESCAPE or k.keycode == KEY_BACK):
		get_viewport().set_input_as_handled()
		go_back()
