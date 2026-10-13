class_name HostPickDialog
extends Control
# Mau-Mau Flip (Beta 1.6.1, Gastgeber-Übergabe, docs/module/uebergabe.md Abschnitte 4.1 und 6): Auswahl, wer das Spiel weiterführt.
# Karte über abgedunkeltem Hintergrund (am Tisch nachts dunkel, TableView.follow_night). Je Mitspieler (ohne Computergegner) eine
# Zeile mit Avatar und Name; wer nicht Gastgeber werden kann, ist ausgegraut, der Grund steht darunter (HostTable.handover_block).
# Die Liste kommt aus provider (() -> [{seat, name, kind, reason}], reason "" = wählbar) und wird zweimal je Sekunde nachgeführt:
# Trennt sich der Gewählte, ist die Wahl weg. „Übergeben“ → chosen(seat, name) und schließt; „Abbrechen“, Tipp daneben oder Zurück
# (TableScreen.on_back) schließt ohne Wahl. Zeigt keine Karten.

signal chosen(seat: int, player_name: String)
signal closed

const REFRESH_MS := 500
const ROW_H := 92.0

var provider := Callable()
var night := false
var _card: PanelContainer
var _list: VBoxContainer
var _scroll: ScrollContainer
var _ok: Button
var _rows: Array = []            # zuletzt gezeigte Liste (Vergleich beim Nachführen)
var _pick := -1                  # gewählter Platz
var _pick_name := ""
var _next_ms := 0


static func open(parent: Node, list_provider: Callable) -> HostPickDialog:
	var d := HostPickDialog.new()
	d.theme = UiTheme.get_theme()
	d.provider = list_provider
	parent.add_child(d)
	d._build()
	TableView.follow_night(d, d.set_night)
	return d


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	name = "GastgeberUebergeben"


func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = ScreenKit.card(30.0)
	_card.custom_minimum_size = Vector2(UiFonts.px(700), 0)
	center.add_child(_card)
	var v := ScreenKit.vbox(14)
	_card.add_child(v)
	v.add_child(ScreenKit.heading("Gastgeber übergeben", UiFonts.size("ueberschrift")))
	var intro := ScreenKit.text_block("Wer führt das Spiel weiter? Es läuft dann über sein Handy, du spielst als Gast weiter.", UiFonts.size("text"))
	intro.name = "Erklaerung"
	v.add_child(intro)
	_scroll = ScreenKit.scroller()
	_scroll.name = "Liste"
	v.add_child(_scroll)
	_list = ScreenKit.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	var row := ScreenKit.hbox(16)
	v.add_child(row)
	var no := ScreenKit.button("Abbrechen", "")
	no.name = "Abbrechen"
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.pressed.connect(close)
	row.add_child(no)
	_ok = ScreenKit.button("Übergeben", "PrimaryButton")
	_ok.name = "Uebergeben"
	_ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ok.disabled = true
	_ok.pressed.connect(_confirm)
	row.add_child(_ok)
	refresh(true)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() >= _next_ms:
		refresh()


# Liste neu holen; Zeilen nur neu bauen, wenn sich etwas geändert hat (force: immer).
func refresh(force := false) -> void:
	_next_ms = Time.get_ticks_msec() + REFRESH_MS
	var rows: Array = provider.call() if provider.is_valid() else []
	if not force and rows == _rows:
		return
	_rows = rows.duplicate(true)
	var still := false
	for r: Dictionary in _rows:
		if int(r.seat) == _pick and str(r.name) == _pick_name and str(r.get("reason", "")) == "":
			still = true
	if not still:
		_pick = -1
		_pick_name = ""
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for r: Dictionary in _rows:
		_list.add_child(_row(r))
	if _rows.is_empty():
		_list.add_child(ScreenKit.hint("Nur Mitspieler mit der App können Gastgeber werden.", UiFonts.size("hinweis")))
	# höchstens etwa drei Zeilen hoch, darüber blättern (die Karte passt so auch mit großer Schrift auf 720 px)
	var row_h := UiFonts.px(ROW_H) + 8.0
	_scroll.custom_minimum_size = Vector2(0, minf(maxf(_rows.size(), 1) * row_h, row_h * 3.2))
	_ok.disabled = _pick < 0
	if night:
		set_night(true)


func _row(r: Dictionary) -> Button:
	var seat := int(r.seat)
	var reason := str(r.get("reason", ""))
	var b := ScreenKit.button("", "GhostButton", "", 0.0)
	b.name = "Platz_%d" % seat
	b.toggle_mode = true
	b.button_pressed = seat == _pick
	b.disabled = reason != ""
	b.custom_minimum_size = Vector2(0, UiFonts.px(ROW_H))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(_select.bind(seat, str(r.name)))
	var inner := ScreenKit.hbox(18)
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 18
	inner.offset_right = -18
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(inner)
	var av := ScreenKit.avatar(seat, str(r.name), str(r.get("kind", "human")), 56.0)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(av)
	var texts := ScreenKit.vbox(0)
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(texts)
	var n := ScreenKit.label(str(r.name), "", UiFonts.size("zeile"))
	n.name = "Name"
	n.add_theme_font_override("font", UiFonts.text(700))
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(n)
	if reason != "":
		var why := ScreenKit.hint(reason, UiFonts.size("klein"))
		why.name = "Grund"
		texts.add_child(why)
		inner.modulate.a = 0.6
	var tick := TextureRect.new()
	tick.name = "Haken"
	tick.texture = ScreenKit.glyph("haken", 40)
	tick.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tick.modulate = UiPalette.INK
	tick.visible = seat == _pick
	inner.add_child(tick)
	return b


func _select(seat: int, player_name: String) -> void:
	_pick = seat
	_pick_name = player_name
	for b in _list.get_children():
		if b is Button:
			var mine := str(b.name) == "Platz_%d" % seat
			(b as Button).set_pressed_no_signal(mine)
			var tick := b.find_child("Haken", true, false) as TextureRect
			if tick != null:
				tick.visible = mine
	_ok.disabled = false


func _confirm() -> void:
	if _pick < 0 or is_queued_for_deletion():
		return
	var seat := _pick
	var who := _pick_name
	close()
	chosen.emit(seat, who)


# Tag/Nacht des Tisches: nachts dunkle Karte mit heller Schrift; der Haken in der Schriftfarbe
func set_night(on: bool) -> void:
	night = on
	if _card != null:
		ScreenKit.set_card_night(_card, on)
	if _list != null:
		for t in _list.find_children("Haken", "TextureRect", true, false):
			(t as TextureRect).modulate = UiPalette.PAPER if on else UiPalette.INK


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.1, 0.55))


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if not _card.get_global_rect().has_point(get_global_transform() * mb.position):
			close()
		accept_event()


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()
