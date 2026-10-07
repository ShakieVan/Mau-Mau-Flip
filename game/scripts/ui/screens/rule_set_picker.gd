class_name RuleSetPicker
extends Control
# „Gespeicherte Regeln“ direkt wählen (Übung und Weitergeben: Knopf „Gespeichert“ der RulesBar; Prüfung 06.10.2026). Papierkarte
# über abgedunkeltem Hintergrund wie ConfirmBox: Kopf mit Titel und „Schließen“, ein Hinweis, darunter die Knöpfe, umbrechend und
# bei sehr vielen langen Namen im eigenen Bildlauf. Zuerst die Regeln des letzten Gastgebers („Zuletzt gespielt bei Lena“, WLAN-
# Symbol), dann die eigenen Sätze; der zu den aktuellen Regeln passende ist sonnengelb.
# Antippen wählt und schließt: picked(cfg, set_name), set_name "" = Gastgeber-Platz. „Schließen“, Tipp daneben oder cancel():
# cancelled. Speichern, ändern und löschen gehen im Regel-Editor („Regeln anpassen“).

signal picked(cfg: RuleConfig, set_name: String)
signal cancelled

const MAX_LIST_H := 380.0

var flow: HFlowContainer
var _card: PanelContainer
var _scroll: ScrollContainer


static func ask(parent: Node, current: RuleConfig) -> RuleSetPicker:
	var p := RuleSetPicker.new()
	p.theme = UiTheme.get_theme()
	parent.add_child(p)
	p._build(current)
	return p


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	name = "GespeicherteRegeln"


func _build(current: RuleConfig) -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = ScreenKit.card(30.0)
	_card.custom_minimum_size = Vector2(1100, 0)
	center.add_child(_card)
	var v := ScreenKit.vbox(12)
	_card.add_child(v)
	var head := ScreenKit.hbox(16)
	v.add_child(head)
	var h := ScreenKit.heading("Gespeicherte Regeln", UiFonts.size("ueberschrift"))
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(h)
	var close := ScreenKit.button("Schließen", "GhostButton")
	close.name = "Schliessen"
	close.add_theme_font_size_override("font_size", UiFonts.size("text"))
	close.pressed.connect(cancel)
	head.add_child(close)
	v.add_child(ScreenKit.hint("Antippen wählt die Regeln. Speichern, ändern und löschen kannst du sie unter „Regeln anpassen“.", UiFonts.size("hinweis")))
	_scroll = ScreenKit.scroller()
	_scroll.name = "Liste"
	_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_scroll.custom_minimum_size = Vector2(0, ScreenKit.TOUCH)
	v.add_child(_scroll)
	flow = HFlowContainer.new()
	flow.name = "Saetze"
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	_scroll.add_child(flow)
	var host := RuleSets.host_name()
	if host != "":
		var hb := ScreenKit.button(RuleSets.host_title(host), "PrimaryButton" if RuleSets.host_matches(current) else "GhostButton", "wlan")
		hb.name = "Gastgeber"
		hb.add_theme_font_size_override("font_size", UiFonts.size("text"))
		hb.set_meta("host", true)
		hb.pressed.connect(_pick_host)
		flow.add_child(hb)
	var active := RuleSets.match_name(current)
	var all := RuleSets.list()
	for i in all.size():
		var n := str(all[i].name)
		var b := ScreenKit.button(n, "PrimaryButton" if n == active else "GhostButton")
		b.name = "Satz%d" % i
		b.add_theme_font_size_override("font_size", UiFonts.size("text"))
		b.set_meta("set", n)
		b.pressed.connect(_pick_set.bind(n))
		flow.add_child(b)
	if flow.get_child_count() == 0:
		var e := ScreenKit.hint("Noch nichts gespeichert. Unter „Regeln anpassen“ → „Speichern unter …“ legst du einen Regelsatz an.", UiFonts.size("text"))
		e.name = "Leer"
		e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.add_child(e)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)
	_fit_height.call_deferred()


# Bildlauf so hoch wie die umbrochenen Knöpfe, höchstens MAX_LIST_H (erst nach dem Layout bekannt)
func _fit_height() -> void:
	if is_inside_tree():
		get_tree().process_frame.connect(_apply_height, CONNECT_ONE_SHOT)


func _apply_height() -> void:
	if not is_instance_valid(flow) or not is_inside_tree():
		return
	var h := flow.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = clampf(h, ScreenKit.TOUCH, MAX_LIST_H)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.1, 0.55))


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if not _card.get_global_rect().has_point(get_global_transform() * mb.position):
			cancel()
		accept_event()


func _pick_host() -> void:
	var c := RuleSets.host_config()
	if c != null:
		_done(c, "")


func _pick_set(set_name: String) -> void:
	var c := RuleSets.config(set_name)
	if c != null:
		_done(c, RuleSets.stored_name(set_name))


func _done(c: RuleConfig, set_name: String) -> void:
	if is_queued_for_deletion():
		return
	queue_free()
	picked.emit(c, set_name)


func cancel() -> void:
	if is_queued_for_deletion():
		return
	queue_free()
	cancelled.emit()
