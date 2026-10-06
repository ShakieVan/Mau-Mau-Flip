class_name StakePile
extends Node2D
# Einsatzstapel des Glücksspielers (Hausregel „Glücksspiel“, AGENTS.md Nr. 26): verdeckt gesetzte Karten mit der neutralen
# Rückseite – die Gesichter kennt nur der Besitzer, Rückseiten werden beim Setzen nicht gezeigt – und ein Zähler „Einsatz N“.
# Am eigenen Platz liegt er vor der Hand (links), bei Gegnern neben ihrem Fächer zur Tischmitte hin (TableView.stake_point).
# target = eigener Einsatz fällig: die Ablagefläche bekommt einen Rand (statisch, kein Dauerzeichnen).
# Ursprung = Mitte der untersten Karte; top_point() ist die Mitte der obersten.

const MAX_LAYERS := 5
const LAYER_STEP := Vector2(1.6, -2.4)

var card_w := 64.0: set = set_card_w
var count := 0
var shown := false
var target := false
var night := 0.0: set = set_night

var _bump := 0.0


func _init() -> void:
	visible = false
	set_process(false)


func set_card_w(w: float) -> void:
	card_w = maxf(w, 20.0)
	queue_redraw()


func set_night(v: float) -> void:
	night = clampf(v, 0.0, 1.0)
	queue_redraw()


# Stapel zeigen/ausblenden, Anzahl und ob er gerade das Ziel des eigenen Setzens ist
func set_state(on: bool, n: int, is_target := false) -> void:
	shown = on
	visible = on
	count = maxi(n, 0)
	target = is_target and on
	queue_redraw()


func set_count(n: int, bump := false) -> void:
	count = maxi(n, 0)
	if bump:
		_bump = 1.0
		set_process(true)
	queue_redraw()


# Mitte der obersten Karte (lokal): Ziel bzw. Start der Flüge
func top_point() -> Vector2:
	return LAYER_STEP * float(clampi(count - 1, 0, MAX_LAYERS - 1))


func card_size() -> Vector2:
	return Vector2(card_w, card_w * CardView.ASPECT)


func _process(delta: float) -> void:
	_bump = maxf(_bump - delta / 0.3, 0.0)
	queue_redraw()
	if _bump <= 0.0:
		set_process(false)


func _draw() -> void:
	if not shown:
		return
	var sz := card_size()
	var k := 1.0 + 0.10 * sin(_bump * PI)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	var line := UiPalette.ui_line(night)
	if count == 0 or target:
		# freie Fläche bzw. Ziel: gestrichelter Kartenumriss
		var at := top_point() + LAYER_STEP if count > 0 else Vector2.ZERO
		_dashed_card(Rect2(at - sz * 0.5, sz), Color(UiPalette.TURN, 0.95) if target else line, 3.0 if target else 2.0)
	var layers := mini(count, MAX_LAYERS)
	if layers > 0:
		var soft := CardView.soft_texture()
		var ss := sz.x / CardView.SOFT_CARD.x
		var soft_sz := Vector2(soft.get_width(), soft.get_height()) * ss
		draw_texture_rect(soft, Rect2(Vector2(sz.x * 0.03, sz.x * 0.06) - soft_sz * 0.5, soft_sz), false, Color(0, 0, 0, 0.4))
		var tex := CardTextures.get_texture(CardTextures.BACK)
		for i in layers:
			var p := LAYER_STEP * float(i)
			draw_texture_rect(tex, Rect2(p - sz * 0.5, sz), false)
	# Zähler unter dem Stapel
	var f := UiFonts.text(800, 90.0)
	var txt := "Einsatz %d" % count
	var fs := 14
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pill := Rect2(-tw * 0.5 - 9.0, sz.y * 0.5 + 8.0, tw + 18.0, 22.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiPalette.PAPER if night > 0.5 else UiPalette.INK
	sb.set_corner_radius_all(11)
	sb.anti_aliasing = true
	draw_style_box(sb, pill)
	draw_string(f, Vector2(pill.position.x + 9.0, pill.position.y + 16.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		UiPalette.INK if night > 0.5 else UiPalette.PAPER)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _dashed_card(r: Rect2, col: Color, w: float) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		draw_dashed_line(pts[i], pts[i + 1], col, w, 7.0, true, true)
