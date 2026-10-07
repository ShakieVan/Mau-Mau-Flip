class_name ScreenNav
extends Control
# Bildschirmverwaltung der App (Startszene res://scenes/main.tscn): Stapel von AppScreen-Bildschirmen mit kurzer Überblendung,
# gemeinsamer Tag-Hintergrund mit sanfter Bewegung, Android-Zurück-Taste bzw. Esc = eine Ebene zurück (der oberste Bildschirm
# darf vorher selbst entscheiden, z. B. „Partie verlassen?“). Im Hauptmenü beendet Zurück die App (nur Android).

const FADE_IN := 0.18
const FADE_OUT := 0.12
const BACK_REPEAT_MS := 650         # Zurück-Taste: Meldungen desselben Drucks zusammenfassen (back_pressed)

const KB_GAP := 16.0                # Abstand des Eingabefelds zur Oberkante der Bildschirmtastatur

# Bildschirmtastatur (Nutzerbefund 06.10.2026: im Querformat verdeckte sie Namensfelder). Tests: Höhe in Einheiten des Viewports
# vorgeben (≥ 0), -1 = DisplayServer.virtual_keyboard_get_height().
static var keyboard_height_override := -1.0

var stack: Array[AppScreen] = []
var autostart := true               # Tests: false = ohne Hauptmenü starten
var _last_back_ms := -1
var _kb := 0.0                      # zuletzt angewandte Tastaturhöhe (Viewport-Einheiten)
var _kb_screen: AppScreen           # Bildschirm, der gerade gestaucht ist
var _kb_field: Control              # Eingabefeld, das sichtbar gehalten wird
var _kb_busy := false

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
	# Einstellung „Schriftgröße“ (je Gerät): beim Start setzen, Änderungen wirken live auf alles schon Gebaute
	UiFonts.set_level(str(UiApp.setting("schrift", "normal")), get_tree().root)
	var app := UiApp.app()
	var st: Variant = app.get("settings") if app != null else null
	if st is Object and (st as Object).has_signal("changed"):
		(st as Object).connect("changed", _on_setting_changed)
	resized.connect(_on_resized)
	_on_resized()
	if autostart and stack.is_empty():
		push(MainMenuScreen.new(), false)


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "schrift" and is_inside_tree():
		UiFonts.set_level(str(value), get_tree().root)


func _on_resized() -> void:
	_bg.table_center = Vector2(size.x * 0.5, size.y * 0.45)


# ----------------------------------------------------------------- Bildschirmtastatur
# Solange die Tastatur offen ist und ein Eingabefeld des obersten Bildschirms (auch in dessen Dialogen) den Fokus hat, endet der
# Bildschirm an der Tastaturkante: Bildläufe schrumpfen auf die freie Höhe, der nächste Bildlauf über dem Feld blättert es ins
# Bild (ensure_control_visible). Passt es dann noch nicht (Bildschirm ohne Bildlauf bzw. Mindesthöhe größer als der freie Platz),
# rückt der ganze Bildschirm so weit nach oben, dass das Feld knapp über der Tastatur steht. Tastatur zu = alles zurück.
func _process(_delta: float) -> void:
	_track_keyboard()


# Höhe der Bildschirmtastatur in Einheiten des Viewports (0 = zu)
func keyboard_height() -> float:
	if keyboard_height_override >= 0.0:
		return keyboard_height_override
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return 0.0
	var px := DisplayServer.virtual_keyboard_get_height()
	var win := DisplayServer.window_get_size()
	if px <= 0 or win.y <= 0:
		return 0.0
	return float(px) * get_viewport().get_visible_rect().size.y / float(win.y)


# Eingabefeld mit Fokus im obersten Bildschirm (null = keins)
func _focused_field() -> Control:
	var f := get_viewport().gui_get_focus_owner()
	var t := top()
	if f == null or t == null or not (f is LineEdit or f is TextEdit) or not t.is_ancestor_of(f) or not f.is_visible_in_tree():
		return null
	return f


func _track_keyboard() -> void:
	if _kb_busy:
		return
	var field := _focused_field()
	var kb := keyboard_height() if field != null else 0.0
	if kb < 1.0:
		kb = 0.0
	var screen: AppScreen = top() if kb > 0.0 else null
	if absf(kb - _kb) < 1.0 and field == _kb_field and _kb_screen == screen:
		return
	_apply_keyboard(kb, field if kb > 0.0 else null)


func _apply_keyboard(kb: float, field: Control) -> void:
	_kb = kb
	_kb_field = field
	if _kb_screen != null and is_instance_valid(_kb_screen) and (field == null or _kb_screen != top()):
		_set_screen_bottom(_kb_screen, 0.0, 0.0)
	_kb_screen = null
	if field == null:
		return
	var s := top()
	_kb_screen = s
	_set_screen_bottom(s, kb, 0.0)
	_kb_busy = true
	await get_tree().process_frame
	await get_tree().process_frame
	var sc := _scroll_of(field) if is_instance_valid(field) and field.is_inside_tree() else null
	var extra := 0.0
	if sc != null:
		# Bildlauf niedriger als das Feld (große Schrift, fester Inhalt darüber und darunter): Bildschirm oben um den Rest
		# hinausschieben, damit der Bildlauf das Feld ganz zeigen kann
		if sc.size.y < field.size.y + 8.0:
			extra = field.size.y + 8.0 - sc.size.y
			_set_screen_bottom(s, kb - extra, extra)
			await get_tree().process_frame
		sc.ensure_control_visible(field)
		await get_tree().process_frame
	if is_instance_valid(field) and field.is_inside_tree() and is_instance_valid(s) and _kb_screen == s:
		var r := field.get_global_rect()
		var free := get_viewport().get_visible_rect().size.y - kb - KB_GAP
		var lift := clampf(r.end.y - free, 0.0, maxf(0.0, r.position.y - KB_GAP))
		if lift > 0.0:
			_set_screen_bottom(s, kb - extra, lift + extra)
	_kb_busy = false


func _set_screen_bottom(s: AppScreen, kb: float, lift: float) -> void:
	s.offset_top = -lift
	s.offset_bottom = -kb - lift


# Nächster Bildlauf über dem Feld, der senkrecht blättern kann
func _scroll_of(c: Control) -> ScrollContainer:
	var n := c.get_parent()
	while n != null and n != self:
		if n is ScrollContainer and (n as ScrollContainer).vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			return n
		n = n.get_parent()
	return null


# Tests: Feld ganz oberhalb der Tastatur und im sichtbaren Teil seines Bildlaufs?
func field_visible(field: Control) -> bool:
	var r := field.get_global_rect()
	var free := get_viewport().get_visible_rect().size.y - keyboard_height()
	var sc := _scroll_of(field)
	if sc != null:
		var sr := sc.get_global_rect()
		if r.position.y < sr.position.y - 1.0 or r.end.y > sr.end.y + 1.0:
			return false
	return r.position.y >= -1.0 and r.end.y <= free + 1.0


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
		back_pressed()


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and (k.keycode == KEY_ESCAPE or k.keycode == KEY_BACK):
		get_viewport().set_input_as_handled()
		back_pressed()


# Zurück-Taste des Geräts bzw. Esc. Android meldet einen Druck mehrfach: die Taste KEY_BACK und 1 ms später
# NOTIFICATION_WM_GO_BACK_REQUEST, beim Halten nach gut 0,5 s weitere Benachrichtigungen im Takt der Tastenwiederholung (am S21
# gemessen). Eine Meldung innerhalb von BACK_REPEAT_MS nach der vorigen gehört zum selben Druck; das Fenster gleitet mit, damit
# auch langes Halten nur einen Schritt auslöst (Gerätetest 0.1.1, M1: sonst schloss ein Druck aus den Regeln die App, und
# Rückfragen gingen auf und sofort wieder zu). Der Zurück-Knopf auf dem Bildschirm ruft go_back() direkt.
func back_pressed() -> bool:
	var now := Time.get_ticks_msec()
	var same := _last_back_ms >= 0 and now - _last_back_ms < BACK_REPEAT_MS
	_last_back_ms = now
	if same:
		return false
	go_back()
	return true
