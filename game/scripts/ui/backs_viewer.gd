class_name BacksViewer
extends Control
# Großansicht der Rückseiten eines Mitspielers (AGENTS.md Nr. 14): nur wenn Rückseiten sichtbar sind. Karten nebeneinander,
# seitlich wischen zum Durchblättern (mit Schwung), Tipp ohne Wischen schließt.

signal closed

const CARD_W := 176.0
const GAP := 18.0

var _dim: ColorRect
var _strip: Node2D
var _title: Label
var _cards: Array[CardView] = []
var _scroll := 0.0
var _vel := 0.0
var _dragging := false
var _moved := 0.0
var _last_x := 0.0


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_dim = ColorRect.new()
	_dim.color = Color(0.03, 0.04, 0.10, 0.78)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_strip = Node2D.new()
	add_child(_strip)
	_title = UiTheme.label("", UiFonts.title(800, false, 50.0, 48.0), 36, UiPalette.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.position.y = 40
	add_child(_title)


func show_backs(name: String, keys: Array) -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	for i in keys.size():
		var c := CardView.new()
		c.width = CARD_W
		c.setup(i, str(keys[i]), "", true)
		_strip.add_child(c)
		_cards.append(c)
	_title.text = "%s · %d %s" % [name, keys.size(), "Rückseite" if keys.size() == 1 else "Rückseiten"]
	_scroll = 0.0
	_vel = 0.0
	visible = true
	_layout()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)


func close() -> void:
	visible = false
	closed.emit()


func content_width() -> float:
	return _cards.size() * (CARD_W + GAP) - GAP


func _max_scroll() -> float:
	return maxf(content_width() - (size.x - 120.0), 0.0)


func _layout() -> void:
	var total := content_width()
	var x0 := (size.x - total) * 0.5 if _max_scroll() <= 0.0 else 60.0
	for i in _cards.size():
		var c := _cards[i]
		c.position = Vector2(x0 + i * (CARD_W + GAP) + CARD_W * 0.5 - _scroll, size.y * 0.53)
		var off := (c.position.x - size.x * 0.5) / size.x
		c.rotation = off * 0.08
		c.scale = Vector2.ONE * (1.0 - absf(off) * 0.12)


func _process(delta: float) -> void:
	if not visible:
		return
	if not _dragging:
		_scroll += _vel * delta
		_vel *= exp(-delta / 0.4)
		# Gummiband an den Enden
		var target := clampf(_scroll, 0.0, _max_scroll())
		_scroll = lerpf(_scroll, target, 1.0 - exp(-delta * 12.0))
	_layout()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_dragging = true
			_moved = 0.0
			_last_x = mb.position.x
			_vel = 0.0
		else:
			_dragging = false
			if _moved < 12.0:
				close()
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _dragging:
		var dx := mm.position.x - _last_x
		_last_x = mm.position.x
		_moved += absf(dx)
		var over := _scroll < 0.0 or _scroll > _max_scroll()
		_scroll -= dx * (0.45 if over else 1.0)
		_vel = -mm.velocity.x
		accept_event()
