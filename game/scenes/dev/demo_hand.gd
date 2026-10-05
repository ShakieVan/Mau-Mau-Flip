class_name DemoHand
extends Node2D
# Einfache Kartenreihe für die Tisch-Demo und Kontrollbilder (Modul F1b). Die echte Hand baut F1a (HandView); diese Reihe
# setzt nur den Hand-Adapter des Tisches um (apply_view, take_card, receive_card, landing_point, flip_wave, own_color_counts),
# damit Flüge, Flip-Welle und Joker-Strahlen ohne HandView sichtbar sind.

const W := 150.0

var cards: Array[CardView] = []
var rays: Array[JokerRays] = []
var center := Vector2(800, 652)
var max_w := 900.0
var my_turn := false
var playable: Array = []
var selected := -1
var dragged := -1                    # Kontrollbild „Farbwahl“: angehobene, gezogene Karte
var dragged_pos := Vector2.ZERO


func apply_view(v: Dictionary) -> void:
	my_turn = int(v.get("turn", -1)) == int(v.get("seat", 0))
	playable = (v.get("hints", {}) as Dictionary).get("playable", [])
	var want: Array = v.get("hand", [])
	var keep: Array[CardView] = []
	for c in want:
		var id := int(c.get("id", -1))
		var cv := _find(id)
		if cv == null:
			cv = CardView.new()
			cv.width = W
			add_child(cv)
		cv.setup(id, str(c.get("face", "")), str(c.get("back", "")), true)
		keep.append(cv)
	for cv in cards:
		if not keep.has(cv):
			cv.queue_free()
	cards = keep
	for i in cards.size():
		move_child(cards[i], i)
	_relayout(false)


func _find(id: int) -> CardView:
	for c in cards:
		if c.card_id == id and id >= 0:
			return c
	return null


func slot_transform(i: int, n: int) -> Transform2D:
	var step := minf(W * 0.62, (max_w - W) / maxf(n - 1, 1))
	var mid := (n - 1) * 0.5
	var d := i - mid
	var p := center + Vector2(d * step, d * d * 1.4)
	return Transform2D(d * 0.03, p)


func _relayout(animate: bool) -> void:
	for r in rays:
		if is_instance_valid(r):
			r.queue_free()
	rays.clear()
	var n := cards.size()
	for i in n:
		var c := cards[i]
		var xf := slot_transform(i, n)
		var lift := 0.0
		if my_turn and playable.has(c.card_id):
			c.set_state(CardView.State.PLAYABLE)
			lift = 14.0
		elif my_turn and not playable.is_empty():
			c.set_state(CardView.State.DIMMED)
		else:
			c.set_state(CardView.State.NORMAL)
		if c.card_id == selected:
			c.set_state(CardView.State.SELECTED)
			lift = 34.0
		var target := Vector2(xf.origin.x, xf.origin.y - lift)
		if c.card_id == dragged:
			target = dragged_pos
			move_child(c, -1)        # über den anderen Handkarten, unter den Farbfeldern
		if animate:
			var tw := create_tween().set_parallel()
			tw.tween_property(c, "position", target, 0.25).set_trans(Tween.TRANS_SINE)
			tw.tween_property(c, "rotation", 0.0 if c.card_id == dragged else xf.get_rotation(), 0.25)
		else:
			c.position = target
			c.rotation = 0.0 if c.card_id == dragged else xf.get_rotation()
	# Joker-Strahlen: verdeckt werden sie von allen Karten rechts daneben
	for i in n:
		var c := cards[i]
		if JokerRays.is_joker(c.current_key()):
			var above: Array = []
			for j in range(i + 1, n):
				above.append(cards[j])
			rays.append(JokerRays.attach(c, above))


func take_card(id: int) -> Dictionary:
	var c := _find(id)
	if c == null:
		return {}
	var out := {"pos": c.global_position, "rot": c.global_rotation, "width": c.width}
	cards.erase(c)
	c.queue_free()
	_relayout(true)
	return out


func receive_card(card: Dictionary, _from_global: Vector2) -> void:
	var cv := CardView.new()
	cv.width = W
	add_child(cv)
	cv.setup(int(card.get("id", -1)), str(card.get("face", "")), str(card.get("back", "")), true)
	cv.global_position = landing_point()
	cards.append(cv)
	_relayout(true)


func landing_point() -> Vector2:
	return to_global(center + Vector2(cards.size() * 18.0, -10.0))


func flip_wave(delay: float, step: float, dur: float, faces: Dictionary) -> void:
	for r in rays:
		if is_instance_valid(r):
			r.queue_free()
	rays.clear()
	for i in cards.size():
		var c := cards[i]
		var nf := str(faces.get(c.card_id, c.back_key))
		c.setup(c.card_id, c.current_key(), nf, true)
		c.flip(dur, delay + i * step)


func own_color_counts() -> Dictionary:
	var out := {}
	for c in cards:
		var col := CardTextures.color_of(c.current_key())
		if col != "":
			out[col] = int(out.get(col, 0)) + 1
	return out


func set_input_locked(_on: bool) -> void:
	pass
