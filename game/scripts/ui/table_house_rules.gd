class_name TableHouseRules
extends RefCounted
# Tischregie der Hausregeln mit Zusatzkarten (BETA1_PLAN Abschnitt 4, docs/module/A.md; AGENTS.md Nr. 23, 26, 27):
#   Kartentausch     swap_hands: alle Hände wandern gleichzeitig auf Bögen über den Tisch an den nächsten Platz in Tauschrichtung
#                    (auch die eigene Hand geht weg, die neue kommt an), Bogenpfeile in der Mitte, Hinweis mit Richtung.
#   Glücksspiel      gamble_start, stake, gamble_roll, stake_back, stake_discard (reason empty/stop) und view.gamble/hints.can_stake/
#                    can_press/can_stop (Knopf „Aufhören“):
#                    Automat in der Tischmitte (GambleMachine), Einsatzstapel am Platz (StakePile), Setzen über die Hand.
#   Farbe ablegen    discard_color: die mitabgelegten Karten fliegen schnell nacheinander unter die Ablegen-Karte, mit Farbschwung.
# Gehört zur TableView (t) und nutzt deren Bausteine. Wie alle Ereignisse sind die Abläufe nur das Drehbuch; maßgeblich bleibt die
# Sicht, mit der die TableView danach abgleicht. Animationen laufen nur während ihres Ereignisses (Flüge und Zeitgeber hängen an
# Effektknoten und verfallen beim Überspringen). Ohne die Hausregeln gibt es diese Ereignisse und view.gamble nicht: nichts ändert sich.
# Rückseiten der Mitspieler erscheinen nur, wenn backs_visible gilt; Einsatzkarten zeigen immer die neutrale Rückseite.

const GambleMachineScript := preload("res://scripts/ui/gamble_machine.gd")
const StakePileScript := preload("res://scripts/ui/stake_pile.gd")
const COLOR_ADJ := {"rot": "rote", "gelb": "gelbe", "gruen": "grüne", "blau": "blaue", "pink": "pinke", "tuerkis": "türkise",
	"orange": "orange", "lila": "lila"}
const SWAP_FLY := 0.72
const SWAP_STAGGER := 0.022
const SWAP_MAX_FLY := 14          # höchstens so viele Flugkarten je Hand (der Rest reist im Bündel unsichtbar mit)

var t: TableView
var swaps := 0                    # Zähler für Tests
var _swap_lock := false
var _my_stake: Array[int] = []    # eigene Einsatzkarten (ids), damit das Ziehen beim Treffer sie nicht für gezogene hält


func _init(table: TableView) -> void:
	t = table


# ================================================================= Hilfen

func _me() -> int:
	return t.my_seat if int(t.view.get("seat", -1)) >= 0 else -1


func _hidden() -> bool:
	return not bool((t.view.get("rules", {}) as Dictionary).get("backs_visible", true))


# global → Welt (Koordinaten der Effekte)
func _w(p: Vector2) -> Vector2:
	return t._world.to_local(p)


func _name(seat: int) -> String:
	return str(t._player(seat).get("name", "Platz %d" % (seat + 1)))


# Landepunkt einer Hand in Weltkoordinaten: {pos, width}
func _seat_target(seat: int) -> Dictionary:
	if seat >= 0 and seat == _me():
		return {"pos": t._hand_point(), "width": TableView.HAND_CARD_W * 0.7}
	var node := t.seat_node(seat)
	if node != null:
		return {"pos": _w(node.fan_global_center()), "width": node.card_w}
	return {"pos": t._seat_point(seat), "width": 56.0}


# Eine Karte verlässt einen Platz: eigene aus der Hand (Knoten wird entnommen), Gegner aus dem Fächer. {pos, rot, width, key} (Welt)
func _take_one(seat: int, id: int, face := "") -> Dictionary:
	if seat >= 0 and seat == _me():
		var h := t.hand
		if h != null and h.has_method("take_card") and id >= 0:
			var got: Variant = h.call("take_card", id)
			if got is CardView:
				var c := got as CardView
				var out := {"pos": _w(c.global_position), "rot": c.global_rotation, "width": c.width * c.global_scale.x, "key": c.current_key()}
				c.queue_free()
				return out
			if got is Dictionary and not (got as Dictionary).is_empty():
				var d := got as Dictionary
				return {"pos": _w(d["pos"]), "rot": float(d.get("rot", 0.0)), "width": float(d.get("width", TableView.HAND_CARD_W)), "key": face}
		return {"pos": t._hand_point(), "rot": 0.0, "width": TableView.HAND_CARD_W, "key": face if face != "" else CardTextures.BACK}
	var node := t.seat_node(seat)
	if node != null:
		var tk := node.take_card(t._back_removed(seat))
		return {"pos": _w(tk["pos"]), "rot": float(tk["rot"]), "width": float(tk["width"]), "key": str(tk["key"])}
	return {"pos": t._center, "rot": 0.0, "width": TableView.CARD_W * 0.6, "key": CardTextures.BACK}


# Ausgangspunkt eines Platzes (Welt) für Farbschwung und Hinweise
func _seat_origin(seat: int) -> Vector2:
	if seat >= 0 and seat == _me():
		return t._hand_point()
	var node := t.seat_node(seat)
	if node != null:
		return _w(node.fan_global_center())
	return t._seat_point(seat)


# Quadratische Bahn von a nach b; der Bogen wölbt sich zu toward (INF: nach oben) – wie TableEffects.fly_card
static func bow_path(a: Vector2, b: Vector2, toward := Vector2.INF, steps := 16) -> PackedVector2Array:
	var mid := (a + b) * 0.5
	var perp := (b - a).orthogonal().normalized()
	if toward.is_finite():
		if perp.dot(toward - mid) < 0.0:
			perp = -perp
	elif perp.y > 0.0:
		perp = -perp
	var ctrl := mid + perp * clampf(a.distance_to(b) * 0.18, 20.0, 140.0)
	var out := PackedVector2Array()
	for i in steps + 1:
		var u := float(i) / steps
		out.append((1.0 - u) * (1.0 - u) * a + 2.0 * (1.0 - u) * u * ctrl + u * u * b)
	return out


func _lock(on: bool) -> void:
	_swap_lock = on
	if t.hand != null and t.hand.has_method("set_input_locked"):
		t.hand.call("set_input_locked", on)


# Eigene Einsatzkarte? (TableView._ev_draw nimmt sie beim Treffer nicht als gezogene Karte)
func is_reserved(id: int) -> bool:
	return _my_stake.has(id)


# Überspringen (großer Rückstand): laufende Abläufe beenden, Sperren lösen; den Rest erledigt der Abgleich mit der Sicht
func skip(ev: Dictionary) -> void:
	match str(ev.get("e", "")):
		"swap_hands":
			_lock(false)
		"gamble_roll":
			t.gamble_machine.finish_spin()
			t.gamble_machine.set_value(int(ev.get("value", -1)))
		"stake_back", "stake_discard":
			t.stake_pile.set_state(false, 0)
			_my_stake.clear()


# ================================================================= Abgleich mit der Sicht (Glücksspiel)

# view.gamble (nur mit der Hausregel): Automat, Einsatzstapel, Farbanzeige und Setzen über die Hand. Ohne Glücksspiel bleibt alles aus.
func apply_view(v: Dictionary) -> void:
	if _swap_lock and not t.director.is_busy():
		_lock(false)
	var raw: Variant = v.get("gamble", {})
	var gb: Dictionary = raw if raw is Dictionary else {}
	var hints: Dictionary = v.get("hints", {})
	var me := int(v.get("seat", -1))
	var machine := t.gamble_machine
	if gb.is_empty():
		if machine.active:
			machine.hide_machine(true)
		t.stake_pile.set_state(false, 0)
		t.set_color_mark_visible(true)
		_my_stake.clear()
		_set_staking(false, [])
		return
	var seat := int(gb.get("seat", -1))
	var mine := me >= 0 and seat == me
	var need := str(gb.get("need", ""))
	machine.accent = UiPalette.avatar(seat)
	machine.reduced = t.reduced
	if not machine.active:
		machine.show_machine(true)
	machine.set_value(int(gb.get("last", -1)))
	machine.press_sent = false
	machine.can_press = mine and bool(hints.get("can_press", false))
	machine.can_stop = mine and bool(hints.get("can_stop", false))
	place_pile(seat)
	t.stake_pile.set_state(true, int(gb.get("stake", 0)), mine and need == "stake")
	t.set_color_mark_visible(false)
	_set_staking(mine and need == "stake", hints.get("can_stake", []))


# Einsatzstapel an den Platz des Glücksspielers legen (auch nach Größenänderungen)
func place_pile(seat := -1) -> void:
	var s := seat
	if s < 0:
		var gb: Variant = t.view.get("gamble", {})
		if not gb is Dictionary or (gb as Dictionary).is_empty():
			return
		s = int((gb as Dictionary).get("seat", -1))
	t.stake_pile.position = t.stake_point(s)
	t.stake_pile.card_w = t.stake_card_w(s)


# Setzen über die Hand: spielbar sind die setzbaren Karten (ohne Markierung, es geht ja jede), Ziel ist der Einsatzstapel
func _set_staking(on: bool, ids: Array) -> void:
	t.staking = on
	var h := t.hand
	if h != null:
		if on and h.has_method("set_playable"):
			h.call("set_playable", ids)
		if "show_playable" in h:
			h.set("show_playable", not on)
	t.update_hand_target()


# ================================================================= Kartentausch

func ev_swap(ev: Dictionary) -> float:
	var dir := 1 if int(ev.get("dir", 1)) >= 0 else -1
	var counts: Array = ev.get("counts", [])
	var tv := t._target()
	var players: Array = tv.get("players", []) if not tv.is_empty() else []
	if players.is_empty():
		players = t.view.get("players", [])
	var n := players.size()
	var active: Array[int] = []
	for p in players:
		if int(p.get("place", 0)) == 0:
			active.append(int(p.get("seat", -1)))
	active.sort()
	if n < 2 or active.size() < 2:
		return 0.0
	swaps += 1
	var me := _me()
	var hidden := _hidden()
	var backs: Array = ev.get("backs", [])
	var my_hand: Array = ev.get("hand", [])
	var dest := {}
	for s in active:
		var d := s
		for i in n:
			d = posmod(d + dir, n)
			if active.has(d):
				break
		dest[s] = d
	_announce_swap(dir, active, dest, me)
	_lock(true)
	var fly := t._d(SWAP_FLY)
	var stagger := t._d(SWAP_STAGGER)
	var longest := 0.0
	for s in active:
		var d: int = dest[s]
		var tgt := _seat_target(d)
		var starts := _take_hand(s)
		var land_keys: Array[String] = []
		if d == me:
			for c in my_hand:
				land_keys.append(str((c as Dictionary).get("face", "")))
		else:
			land_keys = _seat_keys(d, counts, backs, hidden)
		var arrive := _arrival(d, me, my_hand, land_keys, tgt["pos"])
		if starts.is_empty():
			t.fx.after(fly, arrive)
			longest = maxf(longest, fly)
			continue
		var m := starts.size()
		for i in m:
			var st: Dictionary = starts[i]
			var key_from := str(st["key"])
			var key_to := CardTextures.BACK
			if not land_keys.is_empty() and land_keys[i % land_keys.size()] != "":
				key_to = land_keys[i % land_keys.size()]
			var spread := Vector2((float(i) - float(m - 1) * 0.5) * minf(6.0, 60.0 / m), 0.0)
			var delay := float(i) * stagger
			var dist := (st["pos"] as Vector2).distance_to(tgt["pos"])
			t.fx.fly_card(key_from, st["pos"], float(st["rot"]), float(st["width"]), Vector2(tgt["pos"]) + spread, 0.0, float(tgt["width"]), fly,
				{"flip_to": key_to if key_to != key_from else "", "delay": delay, "bow_to": t._center,
				"arc": clampf(dist * 0.2, 30.0, 150.0), "on_land": arrive if i == m - 1 else Callable()})
			longest = maxf(longest, delay + fly)
	t.fx.after(longest + t._d(0.15), func() -> void: _lock(false))
	UiApp.sound("mischen")
	return longest + t._d(0.35)


# Hinweis mit Richtung, wie sie auf diesem Gerät aussieht (Plätze im Uhrzeigersinn, eigene Hand unten): Bogenpfeile, Stempel, Meldung
func _announce_swap(dir: int, active: Array[int], dest: Dictionary, me: int) -> void:
	var neon := t.night > 0.5
	var col := TableEffects.NEON_PINK if neon else UiPalette.INK
	t.fx.swap_arrows(t._center, dir, Color(col, 0.85), t._d(1.5))
	# Stempel über den Pfeilen (der Fächer oben ist während des Tauschs ohnehin unterwegs)
	t.fx.stamp(t._center + Vector2(0, -116), "Kartentausch!", TableEffects.NEON_PINK if neon else UiPalette.INK, 42, t._d(0.8), -0.06)
	var text := ""
	var mine := me >= 0 and active.has(me)
	if active.size() == 2:
		if mine:
			text = "Kartentausch! Du tauschst die Hand mit %s." % _name(int(dest[me]))
		else:
			text = "Kartentausch! %s und %s tauschen die Hände." % [_name(active[0]), _name(active[1])]
	else:
		var way := "im Uhrzeigersinn" if dir > 0 else "gegen den Uhrzeigersinn"
		if mine:
			text = "Kartentausch! Alle Hände wandern %s – deine zu %s." % [way, _name(int(dest[me]))]
		else:
			text = "Kartentausch! Alle Hände wandern %s weiter." % way
	t.hint_bar.toast(text, "info", 3.4)


# Karten einer Hand für den Abflug: eigene aus der HandView (Knoten werden entnommen), Gegner aus dem Fächer (danach leer)
func _take_hand(s: int) -> Array:
	var out: Array = []
	if s == _me():
		var h := t.hand
		if h != null and h.has_method("get_order") and h.has_method("take_card"):
			var ids: Array = h.call("get_order")
			for id in ids:
				var got: Variant = h.call("take_card", int(id))
				if got is CardView:
					var c := got as CardView
					if out.size() < SWAP_MAX_FLY:
						out.append({"pos": _w(c.global_position), "rot": c.global_rotation, "width": c.width * c.global_scale.x,
							"key": c.current_key()})
					c.queue_free()
		return out
	var node := t.seat_node(s)
	if node == null:
		return out
	for c in node.fan_cards():
		out.append({"pos": _w(c["pos"]), "rot": float(c["rot"]), "width": float(c["width"]), "key": str(c["key"])})
	if out.is_empty() and node.count() > 0:
		var from := _w(node.fan_global_center())
		var key := node.keys[0] if not node.keys.is_empty() else CardTextures.BACK
		for i in mini(node.count(), 4):
			out.append({"pos": from + Vector2(float(i) * 4.0, 0.0), "rot": 0.0, "width": node.card_w, "key": key})
	node.give_away()
	return out


# Rückseiten der neuen Hand eines Gegners (sortiert aus dem Ereignis) bzw. neutrale Rückseiten
func _seat_keys(d: int, counts: Array, backs: Array, hidden: bool) -> Array[String]:
	var k := int(counts[d]) if d >= 0 and d < counts.size() else 0
	var out: Array[String] = []
	var b: Array = []
	if not hidden and d >= 0 and d < backs.size() and backs[d] is Array:
		b = backs[d]
	if b.size() == k and k > 0:
		for key in b:
			out.append(str(key))
	else:
		for i in k:
			out.append(CardTextures.BACK)
	return out


# Ankunft der neuen Hand: eigene Hand fächert sich am Landepunkt auf, Gegner bekommen ihren Fächer zurück
func _arrival(d: int, me: int, my_hand: Array, land_keys: Array[String], land_pos: Vector2) -> Callable:
	if d >= 0 and d == me:
		return func() -> void:
			var h := t.hand
			if h == null or not h.has_method("set_cards"):
				return
			var keep: Variant = h.get("spawn_from")
			if keep != null:
				h.set("spawn_from", t._world.to_global(land_pos))
			h.call("set_cards", my_hand)
			if keep != null:
				h.set("spawn_from", keep)
			UiApp.vibrate(25, 0.5)
	return func() -> void:
		var node := t.seat_node(d)
		if node != null:
			node.receive_hand(land_keys)


# ================================================================= Glücksspiel

func ev_gamble_start(ev: Dictionary) -> float:
	var seat := int(ev.get("seat", -1))
	var m := t.gamble_machine
	m.accent = UiPalette.avatar(seat)
	m.reduced = t.reduced
	m.press_sent = false
	m.can_press = false
	m.can_stop = false
	m.set_value(-1)
	m.show_machine(true)
	place_pile(seat)
	t.stake_pile.set_state(true, 0, false)
	t.set_color_mark_visible(false)
	_my_stake.clear()
	var neon := t.night > 0.5
	t.fx.float_text(t._center + Vector2(0, -124), "Glücksspiel!", 40, GambleMachineScript.NEON if neon else UiPalette.TURN, t._d(1.2), 26.0)
	UiApp.sound("dran")
	return t._d(0.75)


func ev_stake(ev: Dictionary) -> float:
	var seat := int(ev.get("seat", -1))
	var count := maxi(int(ev.get("count", 1)), 1)
	var pile := t.stake_pile
	place_pile(seat)
	if not pile.shown:
		pile.set_state(true, count - 1)
	var id := int(ev.get("card", -1))
	if seat == _me() and id >= 0 and not _my_stake.has(id):
		_my_stake.append(id)
	var st := _take_one(seat, id, str(ev.get("face", "")))
	var to := pile.position + StakePileScript.LAYER_STEP * float(clampi(count - 1, 0, StakePileScript.MAX_LAYERS - 1))
	var dur := t._d(0.4)
	var key := str(st["key"])
	t.fx.fly_card(key, st["pos"], float(st["rot"]), float(st["width"]), to, 0.0, pile.card_w, dur,
		{"flip_to": CardTextures.BACK if key != CardTextures.BACK else "", "arc": 40.0, "on_land": func() -> void:
			pile.set_count(count, true)
			UiApp.sound("karte")})
	if seat == _me():
		UiApp.vibrate(15, 0.4)
	return dur + t._d(0.1)


func ev_roll(ev: Dictionary) -> float:
	var seat := int(ev.get("seat", -1))
	var value := clampi(int(ev.get("value", 0)), 0, 10)
	var m := t.gamble_machine
	if not m.active:
		m.show_machine(false)
	m.can_press = false
	m.can_stop = false
	m.press_sent = false
	m.press_anim()
	var spin := t._d(1.05)
	m.spin_to(value, spin)
	UiApp.sound("mischen")
	var me := seat >= 0 and seat == _me()
	var reel := t._world.transform * (m.position + m.reel_center())
	t.fx.after(spin, func() -> void:
		if value == 0:
			m.shake()
			# „Nichts!“ steigt über dem (gerade unbenutzten) Knopf auf; die 0 in der Walze bleibt lesbar
			var btn := t._world.transform * (m.position + m.button_center())
			t.fx_top.float_text(t._table_to(t.fx_top, btn + Vector2(0, 6)), "Nichts!", 40, UiPalette.CREAM, t._d(1.0), 22.0)
			UiApp.sound("fehler")
			if me:
				UiApp.vibrate(20, 0.3)
		else:
			m.flash()
			t.fx_top.hit_burst(t._table_to(t.fx_top, reel + Vector2(0, 26)), str(value), t._d(1.3))
			UiApp.sound("dran")
			if me:
				UiApp.vibrate(60, 0.8)
				if not t.reduced:
					t._shake = maxf(t._shake, 0.4))
	# Nachlauf: „Nichts!“ bzw. der Treffer stehen kurz, bevor es weitergeht (Computergegner warten auf die Regie)
	return spin + t._d(0.75 if value == 0 else 1.05)


# Treffer: der ganze Einsatz fliegt zurück zum Glücksspieler (eigene Gesichter wenden sich in der Luft)
func ev_stake_back(ev: Dictionary) -> float:
	var seat := int(ev.get("seat", -1))
	var n := maxi(int(ev.get("count", 0)), 0)
	var cards: Array = ev.get("cards", [])
	var faces: Array = ev.get("faces", [])
	var backs: Array = ev.get("backs", [])
	var pile := t.stake_pile
	place_pile(seat)
	var me := seat >= 0 and seat == _me()
	var hidden := _hidden()
	var node := t.seat_node(seat)
	var tgt := _seat_target(seat)
	var fly := t._d(0.42)
	var step := t._d(0.07)
	for i in n:
		var from := pile.position + StakePileScript.LAYER_STEP * float(clampi(n - 1 - i, 0, StakePileScript.MAX_LAYERS - 1))
		var key_to := CardTextures.BACK
		var info := {}
		if me and i < cards.size():
			info = {"id": int(cards[i]), "face": str(faces[i]) if i < faces.size() else ""}
			if i < backs.size():
				info["back"] = str(backs[i])
			key_to = str(info["face"])
		elif not hidden and i < backs.size():
			key_to = str(backs[i])
		var left := n - i - 1
		var delay := float(i) * step
		t.fx.after(delay, func() -> void: pile.set_count(left))
		var land := Callable()
		if me and not info.is_empty():
			var dest_g := t._world.to_global(Vector2(tgt["pos"]))
			land = func() -> void:
				if t.hand != null and t.hand.has_method("receive_card"):
					t.hand.call("receive_card", info, dest_g)
		elif node != null:
			var k := key_to
			land = func() -> void: node.add_card(k)
		t.fx.fly_card(CardTextures.BACK, from, 0.0, pile.card_w, tgt["pos"], 0.0, float(tgt["width"]), fly,
			{"flip_to": key_to if key_to != CardTextures.BACK else "", "delay": delay, "bow_to": t._center, "on_land": land})
	var total := float(maxi(n - 1, 0)) * step + fly
	t.fx.after(total, func() -> void:
		pile.set_state(false, 0)
		t.gamble_machine.hide_machine(true))
	if n > 0:
		UiApp.sound("ziehen")
	_my_stake.clear()
	return total + t._d(0.15)


# Kein Treffer und Hand leer (reason "empty") oder Aufhören ("stop"): der Einsatz kommt unter die Ablage (gleitet unter den Stapel)
func ev_stake_discard(ev: Dictionary) -> float:
	var seat := int(ev.get("seat", -1))
	var n := maxi(int(ev.get("count", 0)), 0)
	var faces: Array = ev.get("faces", [])
	var pile := t.stake_pile
	place_pile(seat)
	var fly := t._d(0.4)
	var step := t._d(0.08)
	var bottom := t.discard_bottom()
	var layer := t.discard_layer()
	for i in n:
		var from := pile.position + StakePileScript.LAYER_STEP * float(clampi(n - 1 - i, 0, StakePileScript.MAX_LAYERS - 1))
		var face := str(faces[i]) if i < faces.size() else ""
		var left := n - i - 1
		var delay := float(i) * step
		t.fx.after(delay, func() -> void: pile.set_count(left))
		var from_l := layer.to_local(t._world.to_global(from))
		var rot := bottom.rotation if bottom != null else 0.0
		t.fx.fly_card(CardTextures.BACK, from_l, 0.0, pile.card_w, Vector2.ZERO, rot, TableView.CARD_W, fly,
			{"flip_to": face, "delay": delay, "parent": layer, "below": bottom, "arc": 50.0})
	var total := float(maxi(n - 1, 0)) * step + fly
	t.fx.after(total, func() -> void:
		pile.set_state(false, 0)
		t.gamble_machine.hide_machine(true))
	if n > 0:
		UiApp.sound("karte")
	_my_stake.clear()
	# Aufhören: alle sehen, wer aufhört und wie viele Karten unter die Ablage gehen
	if str(ev.get("reason", "")) == "stop":
		t.gamble_machine.can_stop = false
		t.show_notice(stop_text(seat, n, seat >= 0 and seat == _me()))
		var neon := t.night > 0.5
		t.fx.float_text(t._center + Vector2(0, -124), "Aufgehört!", 40, GambleMachineScript.NEON if neon else UiPalette.TURN, t._d(1.2), 26.0)
		return total + t._d(0.6)
	return total + t._d(0.15)


# Meldung beim Aufhören („Mimi hört auf – 3 Karten unter die Ablage.“)
func stop_text(seat: int, n: int, mine: bool) -> String:
	var cards := "1 Karte" if n == 1 else "%d Karten" % n
	if mine:
		return "Du hörst auf – %s unter die Ablage." % cards
	return "%s hört auf – %s unter die Ablage." % [_name(seat), cards]


# ================================================================= Farbe mit ablegen

func ev_discard_color(ev: Dictionary) -> float:
	var seat := int(ev.get("seat", -1))
	var col := str(ev.get("color", ""))
	var cards: Array = ev.get("cards", [])
	var faces: Array = ev.get("faces", [])
	var n := mini(maxi(int(ev.get("count", faces.size())), 0), faces.size())
	t.hint_bar.toast(discard_text(seat, col, n), "info", 3.0)
	if n <= 0:
		return t._d(0.35)
	var glow := UiPalette.glow(col)
	var fly := t._d(0.36)
	var step := t._d(0.085)
	var top := t.discard_top()
	var layer := t.discard_layer()
	# Farbschwung: ein Lichtstreif vom Platz zur Ablage, vor den Karten her
	t.fx.comet(bow_path(_seat_origin(seat), t._discard_pos), t._d(0.5), glow)
	for i in n:
		var id := int(cards[i]) if i < cards.size() else -1
		var face := str(faces[i])
		var st := _take_one(seat, id, face)
		var fan := under_fan(i, n)
		var from_l := layer.to_local(t._world.to_global(st["pos"]))
		var holder: Array = []
		var first := i < 3
		var c := t.fx.fly_card(str(st["key"]), from_l, float(st["rot"]), float(st["width"]), fan["pos"], float(fan["rot"]),
			TableView.CARD_W, fly, {"flip_to": face if str(st["key"]) != face else "", "delay": float(i) * step, "parent": layer,
			"below": top, "keep": true, "on_land": func() -> void:
				if not holder.is_empty():
					t.adopt_under_top(holder[0])
				if first:
					UiApp.sound("karte")})
		holder.append(c)
	var total := float(n - 1) * step + fly
	t.fx.after(total, func() -> void:
		t.fx.ring_wave(t._discard_pos, glow, 60.0, 250.0, t._d(0.6), 12.0, 0.62)
		t.fx.land_burst(t._discard_pos, glow, t.night > 0.5, TableView.CARD_W * 0.55))
	if seat == _me():
		UiApp.vibrate(25, 0.5)
	return total + t._d(0.3)


# Lage der i-ten von n mitabgelegten Karten unter der Ablegen-Karte (relativ zur Ablagemitte): ein kleiner Fächer, der links und
# rechts unter der obersten Karte hervorschaut
static func under_fan(i: int, n: int) -> Dictionary:
	var a := deg_to_rad(16.0)
	if n > 1:
		var spread := deg_to_rad(minf(12.0 * float(n), 56.0))
		a = -spread * 0.5 + spread * (float(i) + 0.5) / float(n)
	var pivot := Vector2(0.0, 74.0)
	return {"pos": pivot + Vector2(0.0, -74.0).rotated(a), "rot": a}


# „Mia legt 4 rote Karten mit ab.“ / „Du legst eine blaue Karte mit ab.“ / „Ben hat keine weitere grüne Karte.“
func discard_text(seat: int, col: String, n: int) -> String:
	var adj: String = COLOR_ADJ.get(col, "")
	var me := seat >= 0 and seat == _me()
	var who := "Du" if me else _name(seat)
	var card1 := ("%s Karte" % adj) if adj != "" else "Karte"
	if n <= 0:
		return "%s %s keine weitere %s." % [who, "hast" if me else "hat", card1]
	var verb := "legst" if me else "legt"
	if n == 1:
		return "%s %s eine %s mit ab." % [who, verb, card1]
	return "%s %s %d %s mit ab." % [who, verb, n, ("%s Karten" % adj) if adj != "" else "Karten"]
