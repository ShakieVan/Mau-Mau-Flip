extends Node2D
# Entwicklerszene der Hand (Modul F1a): HandView mit Beispieldaten vor einem angedeuteten Tisch nach
# art/entwurf/a-papier-neon/hand.png (Nachziehstapel, Ablage mit Farbring, Knöpfe „Farbe“ und „Rückseiten“).
# Kein Regelwerk: spielbar ist, was zur obersten Ablagekarte passt (Farbe, Wert, Joker); Ausspielen legt die Karte ab.
# Tasten: 1–6 = 5/9/12/16/25/40 Karten, S = Sortierung weiter, B = Rückseiten, F = Flip (Seitenwechsel), N = Karte ziehen,
# P = alles spielbar an/aus, E = Eingabe an/aus, D = Statuszeile.

const PILE := Vector2(977, 321)
const DRAW := Vector2(623, 321)
const PILE_W := 124.0
const COLOR_NAMES := {"rot": "Rot", "gelb": "Gelb", "gruen": "Grün", "blau": "Blau", "pink": "Pink", "tuerkis": "Türkis",
	"orange": "Orange", "lila": "Lila"}
const NEON := {"rot": Color("#E0453E"), "gelb": Color("#FFDD33"), "gruen": Color("#43B05C"), "blau": Color("#2A5BD7"),
	"pink": Color("#FFB3DC"), "tuerkis": Color("#0B97A3"), "orange": Color("#FF7F14"), "lila": Color("#5E3BD8")}

var hand: HandView
var side := "hell"
var show_debug := true: set = set_show_debug
var all_playable := false
var top_face := "hell_blau_9"
var current_color := "blau"
var pairs: Array = []          # [{id, hell, dunkel}] – 112 Karten, Paarung zufällig aus dem Seed
var hand_ids: Array = []
var draw_index := 0
var _rng := RandomNumberGenerator.new()
var _bg: TextureRect
var _ring: Node2D
var _pile_views: Array[CardView] = []
var _draw_views: Array[CardView] = []
var _sort_btn: Button
var _peek_btn: Button
var _turn_label: Label
var _color_label: Label
var _color_icon: TextureRect
var _count_label: Label
var _debug: Label
var _help: Label
var _help_timer := 0.0


func _ready() -> void:
	_build_background()
	_build_table()
	hand = HandView.new()
	hand.play_target = PILE
	hand.spawn_from = DRAW
	add_child(hand)
	hand.play_requested.connect(_on_play)
	hand.help_requested.connect(_on_help)
	hand.drag_started.connect(func(id: int, face: String) -> void: _log("drag_started %d %s" % [id, face]))
	hand.drag_ended.connect(func(id: int, g: Vector2, played: bool) -> void: _log("drag_ended %d %s" % [id, played]))
	hand.order_changed.connect(func(ids: Array) -> void: _log("order_changed %s" % [ids]))
	hand.selection_changed.connect(func(id: int) -> void: _log("selection_changed %d" % id))
	hand.play_denied.connect(func(id: int) -> void: _log("play_denied %d – passt nicht" % id))
	hand.sort_mode_changed.connect(func(m: String) -> void: _update_buttons())
	hand.big_view_changed.connect(func(id: int) -> void: _log("big_view %d" % id))
	_build_buttons()
	deal(9, 2)


# Neue Hand mit n Karten (Seed bestimmt Paarung und Auswahl).
func deal(n: int, seed_value := 1) -> void:
	_rng.seed = seed_value
	_make_pairs()
	hand_ids.clear()
	for i in mini(n, pairs.size()):
		hand_ids.append(i)
	draw_index = n
	hand.set_cards([])   # neue Runde: alte Hand räumen, dann austeilen (sonst gälten gleiche Kennungen als Flip)
	_push_cards()


func set_side(s: String) -> void:
	side = s
	top_face = "hell_blau_9" if s == "hell" else "dunkel_orange_9"
	current_color = "blau" if s == "hell" else "orange"
	_update_table()
	_push_cards()


func draw_card() -> void:
	if draw_index >= pairs.size():
		return
	hand_ids.append(draw_index)
	draw_index += 1
	_push_cards()


func set_show_debug(on: bool) -> void:
	show_debug = on
	if _debug != null:
		_debug.visible = on


func card_dicts() -> Array:
	var out: Array = []
	for id in hand_ids:
		var p: Dictionary = pairs[id]
		var other := "dunkel" if side == "hell" else "hell"
		out.append({"id": id, "face": p[side], "back": p[other]})
	return out


func _push_cards() -> void:
	var cards := card_dicts()
	hand.set_cards(cards)
	var ids: Array = []
	for c in cards:
		if all_playable or _fits(str(c.face)):
			ids.append(c.id)
	hand.set_playable(ids)
	_count_label.text = "Stapel · %d" % (pairs.size() - draw_index)


func _fits(face: String) -> bool:
	var p := CardSort.parse(face)
	var t := CardSort.parse(top_face)
	return p.joker or p.color == current_color or (p.kind == "zahl" and t.kind == "zahl" and p.value == t.value) or (p.kind != "zahl" and p.kind == t.kind)


func _make_pairs() -> void:
	var light := _faces("hell")
	var dark := _faces("dunkel")
	for i in range(dark.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: String = dark[i]
		dark[i] = dark[j]
		dark[j] = tmp
	var idx: Array = range(light.size())
	for i in range(idx.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: int = idx[i]
		idx[i] = idx[j]
		idx[j] = tmp
	pairs.clear()
	for k in idx.size():
		pairs.append({"id": k, "hell": light[idx[k]], "dunkel": dark[idx[k]]})


static func _faces(s: String) -> Array:
	var out: Array = []
	var acts := ["plus1", "aussetzen", "richtungswechsel", "flip"] if s == "hell" else ["plus5", "alle_aussetzen", "richtungswechsel", "flip"]
	for c in CardSort.COLOR_ORDER[s]:
		for v in range(1, 10):
			out.append("%s_%s_%d" % [s, c, v])
			out.append("%s_%s_%d" % [s, c, v])
		for a in acts:
			out.append("%s_%s_%s" % [s, c, a])
			out.append("%s_%s_%s" % [s, c, a])
	for j in (["wuenscher", "wuenscher_plus2"] if s == "hell" else ["wuenscher", "farbjagd"]):
		for k in 4:
			out.append("%s_%s" % [s, j])
	return out


func _on_play(id: int, drop: Vector2) -> void:
	_log("play_requested %d bei %s" % [id, drop])
	await get_tree().create_timer(0.35).timeout
	if not hand_ids.has(id):
		return
	hand_ids.erase(id)
	var face: String = pairs[id][side]
	top_face = face
	var p := CardSort.parse(face)
	if p.color != "":
		current_color = p.color
	_update_table()
	_push_cards()


func _on_help(id: int, face: String) -> void:
	_log("help_requested %d %s" % [id, face])
	_help.text = "Kartenhilfe: %s" % face
	_help.visible = true
	_help_timer = 2.5


func _process(delta: float) -> void:
	if _help_timer > 0.0:
		_help_timer -= delta
		if _help_timer <= 0.0:
			_help.visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_1: deal(5, 3)
		KEY_2: deal(9, 2)
		KEY_3: deal(12, 5)
		KEY_4: deal(16, 4)
		KEY_5: deal(25, 7)
		KEY_6: deal(40, 9)
		KEY_S: _cycle_sort()
		KEY_B: _toggle_peek()
		KEY_F: set_side("dunkel" if side == "hell" else "hell")
		KEY_N: draw_card()
		KEY_P:
			all_playable = not all_playable
			_push_cards()
		KEY_E: hand.set_enabled(not hand.is_enabled())
		KEY_D: show_debug = not show_debug


func _cycle_sort() -> void:
	hand.set_sort_mode(CardSort.next_mode(hand.sort_mode))
	_update_buttons()


func _toggle_peek() -> void:
	hand.set_peek_backs(not hand.is_peeking())
	_update_buttons()


func _log(text: String) -> void:
	if _debug != null:
		_debug.text = "%s · %s · %s\n%s" % [["Fächer", "Lupe", "Karussell"][hand.get_mode()], hand.sort_mode, side, text]


# ---------------------------------------------------------------- Kulisse

func _build_background() -> void:
	_bg = TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color("#26305A"), Color("#171C38"), Color("#0C0F22")])
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.46)
	gt.fill_to = Vector2(1.2, 0.46)
	gt.width = 800
	gt.height = 360
	_bg.texture = gt
	_bg.size = Vector2(1600, 720)
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)


func _build_table() -> void:
	_ring = Ring.new()
	_ring.position = PILE
	add_child(_ring)
	for k in 3:
		var v := CardView.new()
		v.width = 118.0
		v.position = DRAW + Vector2(8 - k * 4, 12 - k * 6)
		v.rotation = deg_to_rad([-3.0, -1.0, 1.5][k])
		add_child(v)
		_draw_views.append(v)
	for k in 3:
		var v := CardView.new()
		v.width = PILE_W
		v.position = PILE + [Vector2(-14, 2), Vector2(-4, -1), Vector2(4, 0)][k]
		v.rotation = deg_to_rad([16.0, -11.0, 4.0][k])
		add_child(v)
		_pile_views.append(v)
	_count_label = _label(17, Color("#C9C3E8"), 700)
	_count_label.position = Vector2(DRAW.x - 75, 426)
	_count_label.size = Vector2(150, 24)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_count_label)
	_color_icon = TextureRect.new()
	_color_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_color_icon.size = Vector2(44, 44)
	_color_icon.position = Vector2(800 - 22, PILE.y - 44)
	add_child(_color_icon)
	_color_label = _label(22, Color("#F4EADA"), 800)
	_color_label.position = Vector2(700, PILE.y + 4)
	_color_label.size = Vector2(200, 30)
	_color_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_color_label)
	_turn_label = _label(19, Color("#211B2C"), 700)
	_turn_label.text = "Du bist dran"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#FFF7E8")
	sb.set_corner_radius_all(30)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 6
	sb.content_margin_bottom = 7
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	_turn_label.add_theme_stylebox_override("normal", sb)
	_turn_label.position = Vector2(728, 452)
	add_child(_turn_label)
	_help = _label(20, Color("#211B2C"), 700)
	_help.add_theme_stylebox_override("normal", sb.duplicate())
	_help.position = Vector2(620, 40)
	_help.visible = false
	_help.z_index = 3000
	add_child(_help)
	_debug = _label(15, Color(0.85, 0.82, 0.95, 0.8), 500)
	_debug.position = Vector2(16, 10)
	_debug.text = "1–6 Kartenzahl · S Sortierung · B Rückseiten · F Flip · N ziehen · P alles spielbar · E Eingabe · D Status"
	_debug.z_index = 3000
	add_child(_debug)
	_update_table()


func _update_table() -> void:
	var stack := [top_face, top_face, top_face]
	stack[0] = "hell_gelb_plus1" if side == "hell" else "dunkel_pink_plus5"
	stack[1] = "hell_blau_richtungswechsel" if side == "hell" else "dunkel_orange_richtungswechsel"
	for k in 3:
		_pile_views[k].setup(-1, stack[k])
	var other := "dunkel" if side == "hell" else "hell"
	var backs := ["%s_lila_6" % other if other == "dunkel" else "hell_gruen_6", "%s_tuerkis_7" % other if other == "dunkel" else "hell_rot_7",
		"%s_orange_9" % other if other == "dunkel" else "hell_gelb_9"]
	for k in 3:
		_draw_views[k].setup(-1, backs[k])
	(_ring as Ring).color = NEON.get(current_color, Color.WHITE)
	_ring.queue_redraw()
	_color_label.text = COLOR_NAMES.get(current_color, "")
	var icon := "res://assets/ui/farben/%s.png" % current_color
	_color_icon.texture = load(icon) if ResourceLoader.exists(icon) else null


func _build_buttons() -> void:
	_sort_btn = _pill("res://assets/ui/sortieren.png", Vector2(46, 560))
	_sort_btn.pressed.connect(_cycle_sort)
	_peek_btn = _pill("res://assets/ui/rueckseiten.png", Vector2(46, 632))
	_peek_btn.pressed.connect(_toggle_peek)
	_update_buttons()


func _update_buttons() -> void:
	_sort_btn.text = CardSort.LABELS.get(hand.sort_mode, hand.sort_mode)
	_peek_btn.text = "Vorderseiten" if hand.is_peeking() else "Rückseiten"


func _pill(icon_path: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.position = pos
	b.custom_minimum_size = Vector2(0, 52)
	b.focus_mode = Control.FOCUS_NONE
	if ResourceLoader.exists(icon_path):
		b.icon = load(icon_path)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 26)
	b.add_theme_constant_override("h_separation", 10)
	b.add_theme_font_override("font", _font(700))
	b.add_theme_font_size_override("font_size", 20)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.957, 0.918, 0.855, 0.16 if st == "pressed" else (0.13 if st == "hover" else 0.1))
		sb.border_color = Color(0.957, 0.918, 0.855, 0.35)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(40)
		sb.content_margin_left = 20
		sb.content_margin_right = 22
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		b.add_theme_stylebox_override(st, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Color("#F4EADA"))
	add_child(b)
	return b


func _label(size: int, color: Color, weight: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _font(weight: int) -> Font:
	var path := "res://assets/fonts/BricolageGrotesque.ttf"
	if not ResourceLoader.exists(path):
		return ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = load(path)
	fv.variation_opentype = {"wght": weight, "opsz": 12}
	return fv


# Farbring um die Ablage (Neon: weiches Glühen aus mehreren Ringen).
class Ring:
	extends Node2D
	var color := Color("#2A5BD7")

	func _draw() -> void:
		for i in 6:
			draw_arc(Vector2.ZERO, 116.0, 0.0, TAU, 96, Color(color.r, color.g, color.b, 0.07), 5.0 + i * 5.0, true)
		draw_arc(Vector2.ZERO, 116.0, 0.0, TAU, 96, color, 5.0, true)
