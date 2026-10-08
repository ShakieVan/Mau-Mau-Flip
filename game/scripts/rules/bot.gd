class_name MauBot
extends RefCounted
# Computergegner (docs/BETA1_PLAN.md Abschnitt 4): wählt eine Aktion allein aus der Sicht eines Platzes (MauGame.view_for), sieht
# also nur, was ein Mensch an diesem Platz sähe. Deterministisch aus rng_seed.
# level 0: zufällige erlaubte Karte; 1: Taktik mit etwas Zufall; 2: Taktik ohne Zufall.
# Taktik: Aktionen bevorzugt, besonders gegen einen Nächsten mit wenigen Karten; Karte, nach der möglichst viele Restkarten
# passen; Joker aufsparen; Flip nach eigenen Rückseiten und den sichtbaren Rückseiten der Gegner; Wunschfarbe nach Handmehrheit;
# „Mau!“ immer rufen, aber nur, wenn er im selben Zug auf 1 Karte kommt (kein blinder Ruf); erwischen, wenn möglich; nie
# bluffen (Stufe 2); anzweifeln bei Verdacht, also wenn der Leger viele Karten hält und daher wahrscheinlich eine passende hatte. Gegen Zufallsbots gewinnt Stufe 2 zu dritt etwa 42 % statt 33 %.
# Kartentausch (Hausregel): nach swap_value() aus den öffentlichen Kartenzahlen; lohnt er nicht und ist er das Einzige, was
# passt, zieht der Bot lieber (bzw. behält ihn nach dem Ziehen). Vor einem Kartentausch ruft er kein „Mau!“.
# Glücksspiel (Hausregel): Den Joker spielt er gern mit kleiner Hand (höchstens 4 Karten) oder wenn sonst nichts passt; gezogen
# behält er ihn bei großer Hand. Gesetzt werden zuerst Karten mit hohen Punkten bzw. schwer spielbare, Joker zuletzt; gedrückt
# wird sofort. „Mau!“ ruft er vor dem Setzen der vorletzten Karte.
# Farbe mit ablegen (Hausregel): bevorzugt, wenn die Karte mindestens 2 weitere mitnimmt oder die Hand leert; der Ablegen-Joker
# wählt die Farbe mit den meisten Karten. „Mau!“ ruft er vor jedem Legen, nach dem genau 1 Karte bleibt.
# Nach dem Ziehen mit draw_play = any (Hausregel): beste passende Karte nach der Zug-Taktik, sonst behalten.
# Liefert {} wenn der Platz nichts zu tun hat; die Spielsteuerung fragt Bots daher auch außerhalb ihres Zugs (Erwischen).

const COLOR_SHARE := 26.0 / 112.0    # Anteil der Karten einer Farbe (je Seite)
const WILD_SHARE := 8.0 / 112.0
const BLUFF_PRIOR := 0.6            # angenommene Neigung anderer, Wünscher +2/Farbjagd regelwidrig zu legen
const AVG_POWER := 0.66             # mittlere Stärke einer unbekannten Handkarte (hell 0,64, dunkel 0,68)


static func choose(view: Dictionary, rng_seed: int, level := 1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var me := int(view.get("seat", -1))
	var state := str(view.get("phase", ""))
	var hints: Dictionary = view.get("hints", {})
	if me < 0 or not state in ["turn", "drawn", "challenge", "color", "gamble", "discard_pick"]:
		return {}
	var catch_list: Array = hints.get("catch", [])
	if not catch_list.is_empty() and (level > 0 or rng.randf() < 0.5):
		return {"a": "catch", "target": int(catch_list[0])}
	if int(view.get("turn", -1)) != me:
		return {}
	var act := {}
	match state:
		"color":
			act = {"a": "color", "color": best_color(view, -1, rng)}
		"challenge":
			act = _challenge(view, hints, rng, level)
		"drawn":
			act = _drawn(view, hints, rng, level)
		"turn":
			act = _turn(view, hints, rng, level)
		"gamble":
			act = _gamble(view, hints, rng, level)
		"discard_pick":
			act = _discard_pick(view, hints, rng)
	# „Mau!“ nur, wenn der Bot mit dieser Handlung auf genau 1 Karte kommt (er legt bzw. setzt gleich), oder nachträglich, wenn er
	# schon höchstens 1 Karte hat (z. B. Zusatzzug nach Aussetzen zu zweit: Seine nächste Handlung schlösse sonst das eigene
	# Fenster). Vor einem Kartentausch nicht: Die Hand wandert weiter, der Ruf verfällt ohnehin.
	var hand_size := (view.get("hand", []) as Array).size()
	var a := str(act.get("a", ""))
	var call := ((a == "play" or a == "stake" or a == "discard_pick") and left_after(view, act) == 1) \
		or (hand_size <= 1 and a != "discard_pick")
	if call and hand_size == 2 and a == "play" and _is_swap(_code_of_id(view, int(act.get("card", -1)))):
		call = false
	if bool(hints.get("can_mau", false)) and call:
		return {"a": "mau"}
	return act


# Karten auf der Hand nach dieser Aktion (play: die Karte, bei Ablegen-Karten dazu die, die der Bot danach mitablegen will
# (_pick_plan); stake: eine Karte; discard_pick: die gewählten); andere Aktionen ändern die Hand hier nicht.
static func left_after(view: Dictionary, act: Dictionary) -> int:
	var hand: Array = view.get("hand", [])
	var a := str(act.get("a", ""))
	if a == "stake":
		return hand.size() - 1
	if a == "discard_pick":
		return hand.size() - (act.get("cards", []) as Array).size()
	if a != "play":
		return hand.size()
	var id := int(act.get("card", -1))
	var code := _code_of_id(view, id)
	if code < 0:
		return hand.size() - 1
	var kind := CardDB.kind_table()[code]
	var col := ""
	if kind == CardDB.DISCARD:
		col = CardDB.color_table()[code]
	elif kind == CardDB.DISCARD_WILD:
		col = str(act.get("color", ""))
	else:
		return hand.size() - 1
	var cand: Array = []
	var ctab := CardDB.color_table()
	for item in hand:
		var c := CardDB.code_of(str(item.face))
		if int(item.id) != id and c >= 0 and ctab[c] == col:
			cand.append(int(item.id))
	return hand.size() - 1 - _pick_plan(view, cand, hand.size() - 1).size()


# Was der Bot mitablegt: Zahlenkarten, Aktionskarten nur, wenn er damit fertig wird (rest = Handgröße ohne die Ablegen-Karte).
static func _pick_plan(view: Dictionary, cand: Array, rest: int) -> Array:
	if cand.size() >= rest:
		return cand.duplicate()
	var out: Array = []
	var ktab := CardDB.kind_table()
	for id in cand:
		var c := _code_of_id(view, int(id))
		if c >= 0 and ktab[c] == "zahl":
			out.append(int(id))
	return out


# Phase discard_pick: Auswahl nach _pick_plan; beim Ablegen-Joker Spielfarbe = häufigste verbleibende Farbe.
static func _discard_pick(view: Dictionary, hints: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var cand: Array = hints.get("can_pick", [])
	var hand: Array = view.get("hand", [])
	var chosen := _pick_plan(view, cand, hand.size())
	var act := {"a": "discard_pick", "cards": chosen}
	if bool(hints.get("pick_color", false)):
		var rest_view := view.duplicate()
		var rest: Array = []
		for item in hand:
			if not chosen.has(int(item.id)):
				rest.append(item)
		rest_view["hand"] = rest
		act["color"] = most_color(rest_view, -1, rng)
	return act


# Karten der Farbe col auf der eigenen Hand ohne die Karte skip_id (Joker haben keine Farbe).
static func _color_count(view: Dictionary, col: String, skip_id: int) -> int:
	var n := 0
	var ctab := CardDB.color_table()
	for item in view.get("hand", []):
		if int(item.id) == skip_id:
			continue
		var code := CardDB.code_of(str(item.face))
		if code >= 0 and ctab[code] == col:
			n += 1
	return n


# Farbe mit den meisten Karten der Hand (ohne skip_id und ohne Joker), bei Gleichstand die mit mehr Punkten, dann zufällig.
static func most_color(view: Dictionary, skip_id: int, rng: RandomNumberGenerator) -> String:
	var colors: Array = view.get("colors", [])
	var ctab := CardDB.color_table()
	var ptab := CardDB.points_table()
	var cnt := {}
	var pts := {}
	for item in view.get("hand", []):
		if int(item.id) == skip_id:
			continue
		var code := CardDB.code_of(str(item.face))
		if code < 0 or ctab[code] == "":
			continue
		cnt[ctab[code]] = int(cnt.get(ctab[code], 0)) + 1
		pts[ctab[code]] = int(pts.get(ctab[code], 0)) + ptab[code]
	var best: Array = []
	var top := [-1, -1]
	for c in colors:
		var k := [int(cnt.get(c, 0)), int(pts.get(c, 0))]
		if k[0] > top[0] or (k[0] == top[0] and k[1] > top[1]):
			top = k
			best = [c]
		elif k[0] == top[0] and k[1] == top[1]:
			best.append(c)
	if best.is_empty():
		return str(colors[0]) if not colors.is_empty() else ""
	return str(best[rng.randi_range(0, best.size() - 1)])


# Wunschfarbe: Farbe mit den meisten (bzw. wertvollsten) Karten der Resthand; bei Gleichstand zufällig.
static func best_color(view: Dictionary, skip_id: int, rng: RandomNumberGenerator) -> String:
	var colors: Array = view.get("colors", [])
	var weight := {}
	for c in colors:
		weight[c] = 0.0
	var ctab := CardDB.color_table()
	var ptab := CardDB.points_table()
	for item in view.get("hand", []):
		if int(item.id) == skip_id:
			continue
		var code := CardDB.code_of(str(item.face))
		if code < 0:
			continue
		var c := ctab[code]
		if weight.has(c):
			weight[c] += 1.0 + ptab[code] * 0.01
	var best: Array = []
	var top := -1.0
	for c in colors:
		var w: float = weight[c]
		if w > top + 0.0001:
			top = w
			best = [c]
		elif absf(w - top) <= 0.0001:
			best.append(c)
	if best.is_empty():
		return str(colors[0]) if not colors.is_empty() else ""
	return str(best[rng.randi_range(0, best.size() - 1)])


static func _play(view: Dictionary, id: int, rng: RandomNumberGenerator) -> Dictionary:
	var act := {"a": "play", "card": id}
	var code := _code_of_id(view, id)
	if code >= 0 and CardDB.wild_table()[code] == 1:
		if CardDB.kind_table()[code] == CardDB.DISCARD_WILD:
			act["color"] = most_color(view, id, rng)       # Ablegen-Joker: die Farbe, die am meisten Karten mitnimmt
		else:
			act["color"] = best_color(view, id, rng)
	return act


# Glücksspiel: drücken, sobald es geht; sonst vielleicht aufhören (stop_chance), sonst setzen – zuerst Karten mit hohen Punkten bzw. schwer spielbare (wenige Karten ihrer
# Farbe), Joker zuletzt. (Bei einem Treffer kommt der Einsatz ohnehin zurück; bei einem Fertigwerden ist alles weg.)
static func _gamble(view: Dictionary, hints: Dictionary, rng: RandomNumberGenerator, level: int) -> Dictionary:
	if bool(hints.get("can_press", false)):
		return {"a": "press"}
	var can: Array = hints.get("can_stake", [])
	if can.is_empty():
		return {}
	if bool(hints.get("can_stop", false)) and rng.randf() < stop_chance(view, level):
		return {"a": "stop"}
	if level <= 0:
		return {"a": "stake", "card": int(can[rng.randi_range(0, can.size() - 1)])}
	var ctab := CardDB.color_table()
	var ptab := CardDB.points_table()
	var best_id := int(can[0])
	var best := -INF
	for pid in can:
		var id := int(pid)
		var code := _code_of_id(view, id)
		if code < 0:
			continue
		var s := float(ptab[code])
		if ctab[code] == "":
			s -= 100.0
		else:
			s += 12.0 / float(1 + _color_count(view, ctab[code], id))
		if level == 1:
			s += rng.randf()
		if s > best:
			best = s
			best_id = id
	return {"a": "stake", "card": best_id}


# Wahrscheinlichkeit, beim Glücksspiel aufzuhören (die Trefferquote kennt der Bot nicht): Je größer der Einsatz, desto eher
# aufhören (ein Treffer brächte alles zurück und dazu bis zu 10 Karten); mit nur noch 1 Karte weiter (kein Treffer = fertig), mit 2
# eher weiter. Einfacher Bot: fester Wurf.
static func stop_chance(view: Dictionary, level: int) -> float:
	var hand := (view.get("hand", []) as Array).size()
	if hand <= 1 or (hand == 2 and _said_mau(view)):      # „Mau!“ gerufen heißt: Die vorletzte Karte wird gesetzt
		return 0.0
	if level <= 0:
		return 0.3
	var stake := int((view.get("gamble", {}) as Dictionary).get("stake", 0))
	var p := 0.1 + 0.18 * float(stake - 1)
	if hand == 2:
		p -= 0.2
	return clampf(p, 0.0, 0.9)


# Wert einer Ablegen-Karte, die n weitere Karten mitnimmt, bei hand Karten auf der Hand: leert sie die Hand, sehr hoch; nimmt sie
# mindestens 2 mit, hoch; sonst niedrig (aufsparen für später). low = Wert ohne Nutzen.
static func _discard_value(n: int, hand: int, low: float) -> float:
	if n + 1 >= hand:
		return 60.0
	if n >= 2:
		return 20.0 + 5.0 * n
	return low + 2.0 * n


static func _code_of_id(view: Dictionary, id: int) -> int:
	for item in view.get("hand", []):
		if int(item.id) == id:
			return CardDB.code_of(str(item.face))
	return -1


# Wäre Wünscher +2/Farbjagd mit dieser Hand regelgerecht? (Gleiche Prüfung wie das Regelwerk, nur aus der eigenen Hand.)
static func _wild_legal(view: Dictionary, id: int) -> bool:
	var col := str(view.get("color", ""))
	var count_wilds := bool((view.get("rules", {}) as Dictionary).get("wild_counts_for_bluff", true))
	var ctab := CardDB.color_table()
	var wtab := CardDB.wild_table()
	for item in view.get("hand", []):
		if int(item.id) == id:
			continue
		var code := CardDB.code_of(str(item.face))
		if code < 0:
			continue
		if ctab[code] == col or (count_wilds and wtab[code] == 1):
			return false
	return true


static func _is_bluff(view: Dictionary, id: int) -> bool:
	var code := _code_of_id(view, id)
	if code < 0:
		return false
	var kind := CardDB.kind_table()[code]
	return (kind == "wuenscher_plus2" or kind == "farbjagd") and not _wild_legal(view, id)


static func _said_mau(view: Dictionary) -> bool:
	var me := int(view.get("seat", -1))
	var p: Dictionary = _players_by_seat(view).get(me, {})
	return bool(p.get("mau", false))


static func _players_by_seat(view: Dictionary) -> Dictionary:
	var out := {}
	for p in view.get("players", []):
		out[int(p.seat)] = p
	return out


# Nächster bzw. voriger aktiver Platz in Spielrichtung.
static func _neighbour(view: Dictionary, step: int) -> Dictionary:
	return _neighbour_dir(view, int(view.get("dir", 1)) * step)


# Nächster aktiver Platz (außer mir) in fester Richtung d (±1, +1 = Uhrzeigersinn); {} wenn es keinen gibt.
static func _neighbour_dir(view: Dictionary, d: int) -> Dictionary:
	var pl: Array = view.get("players", [])
	var n := pl.size()
	var me := int(view.get("seat", 0))
	var s := me
	for i in n:
		s = posmod(s + d, n)
		if int(pl[s].place) == 0 and s != me:
			return pl[s]
	return {}


static func _is_swap(code: int) -> bool:
	return code >= 0 and CardDB.kind_table()[code] == CardDB.SWAP


# Kartentausch aus der eigenen Sicht (Kartenzahlen sind öffentlich): Meine Resthand geht an den Nächsten in Tauschrichtung,
# ich bekomme die Hand des Vorigen. Lohnt, wenn ich deutlich mehr abgebe als ich bekomme, oder wenn der Empfänger kurz vor dem
# Ende ist (er bekommt meine große Hand); nicht, wenn ich selbst kurz vor dem Ende bin. Positiv = lohnt.
static func swap_value(view: Dictionary) -> float:
	var keep := (view.get("hand", []) as Array).size() - 1
	if keep <= 0:
		return 30.0                                   # letzte Karte: fertig
	var rules: Dictionary = view.get("rules", {})
	var step := 1 if str(rules.get("swap_direction", "clockwise")) == "clockwise" or int(view.get("dir", 1)) >= 0 else -1
	var got := int(_neighbour_dir(view, -step).get("count", keep))       # dessen Hand bekomme ich
	var receiver := int(_neighbour_dir(view, step).get("count", keep))   # bekommt meine Resthand
	var v := 4.0 * (keep - got) - 2.0
	if receiver <= 2 and keep >= receiver + 2:
		v += 16.0
	if keep <= 2 and got >= keep:
		v -= 30.0
	return v


# Stärke eines Gesichts auf der Hand für die Flip-Abwägung: Joker und Ziehkarten sind viel wert, Zahlen nichts.
static func power(code: int) -> float:
	if code < 0:
		return 0.0
	match CardDB.kind_table()[code]:
		"wuenscher":
			return 3.0
		"wuenscher_plus2", "farbjagd":
			return 4.0
		"plus1":
			return 2.0
		"plus5":
			return 2.5
		"aussetzen", "alle_aussetzen":
			return 1.5
		"richtungswechsel", "flip":
			return 1.0
		"ablegen_joker":
			return 3.0
		"gluecksspiel", "ablegen":
			return 2.0
	return 0.0


# Lohnt ein Flip? Eigene Hand: Rückseiten (falls bekannt) gegen Vorderseiten. Gegner: Ihre sichtbaren Rückseiten sind nach dem
# Flip ihre Vorderseiten; verglichen mit einer durchschnittlichen unbekannten Hand (AVG_POWER je Karte).
static func _flip_gain(view: Dictionary, mine_now: float, mine_after: float, know_backs: bool) -> float:
	var gain := 0.0
	if know_backs:
		gain += 3.0 * (mine_after - mine_now)
	var me := int(view.get("seat", -1))
	var nxt_seat := int(_neighbour(view, 1).get("seat", -1))
	for p in view.get("players", []):
		if int(p.seat) == me or int(p.place) != 0:
			continue
		var backs: Array = p.get("backs", [])
		if backs.is_empty():
			continue
		var after := 0.0
		for b in backs:
			after += power(CardDB.code_of(str(b)))
		gain -= (1.5 if int(p.seat) == nxt_seat else 0.8) * (after - AVG_POWER * backs.size())
	return gain


static func _turn(view: Dictionary, hints: Dictionary, rng: RandomNumberGenerator, level: int) -> Dictionary:
	var playable: Array = hints.get("playable", [])
	var can_draw := bool(hints.get("can_draw", false))
	if playable.is_empty():
		return {"a": "draw"} if can_draw else {}
	# Schon „Mau!“ gerufen und mehr als 2 Karten (vor einer Ablegen-Karte): bei der Karte bleiben, nach der 1 Karte übrig ist.
	if _said_mau(view) and (view.get("hand", []) as Array).size() > 2:
		for pid in playable:
			var act := _play(view, int(pid), rng)
			if left_after(view, act) == 1:
				return act
	var bluff_mode := str((view.get("rules", {}) as Dictionary).get("wild_restriction", "free")) == "bluff"
	if not (view.get("pending", {}) as Dictionary).is_empty():
		# Stapeln: lieber weitergeben als ziehen; geblufft wird nur selten.
		for id in playable:
			if not _is_bluff(view, int(id)):
				return _play(view, int(id), rng)
		# Nach einem „Mau!“ bleibt der Bot bei seiner Entscheidung zu legen (kein Ruf mit anschließendem Ziehen).
		if not can_draw or _said_mau(view) or rng.randf() < 0.3:
			return _play(view, int(playable[0]), rng)
		return {"a": "draw"}
	if level <= 0:
		return _play(view, int(playable[rng.randi_range(0, playable.size() - 1)]), rng)
	var nxt := _neighbour(view, 1)
	var prv := _neighbour(view, -1)
	var next_count := int(nxt.get("count", 99))
	var prev_count := int(prv.get("count", 99))
	var hand: Array = view.get("hand", [])
	var ctab := CardDB.color_table()
	var ktab := CardDB.kind_table()
	var vtab := CardDB.value_table()
	var ptab := CardDB.points_table()
	var wtab := CardDB.wild_table()
	var color_count := {}
	var code_by_id := {}
	var back_by_id := {}
	var power_front := 0.0
	var power_back := 0.0
	var know_backs := false
	for item in hand:
		var code := CardDB.code_of(str(item.face))
		code_by_id[int(item.id)] = code
		back_by_id[int(item.id)] = CardDB.code_of(str(item.get("back", "")))
		color_count[ctab[code]] = int(color_count.get(ctab[code], 0)) + 1
		power_front += power(code)
		if item.has("back"):
			know_backs = true
			power_back += power(CardDB.code_of(str(item.back)))
	var best_id := -1
	var best_score := -INF
	for pid in playable:
		var id := int(pid)
		var code: int = code_by_id.get(id, -1)
		if code < 0:
			continue
		var kind := ktab[code]
		var s := 0.0
		var danger := 20.0 if next_count <= 2 else 0.0      # Nächster ist kurz vor dem Ziel
		match kind:
			"zahl":
				s = 10.0 + vtab[code] * 0.2
			"plus1", "plus5":
				s = 17.0 + danger
			"aussetzen":
				s = 15.0 + danger
			"richtungswechsel":
				s = 11.0 + (danger if prev_count > 2 else 0.0) - (12.0 if prev_count <= 2 else 0.0)
			"alle_aussetzen":
				s = 14.0 + (12.0 if int(color_count.get(ctab[code], 0)) > 1 else 0.0)
			"flip":
				s = 8.0 + _flip_gain(view, power_front - power(code), power_back - power(int(back_by_id.get(id, -1))), know_backs)
			"wuenscher":
				s = 2.0 + (20.0 if hand.size() <= 2 else 0.0)
			"wuenscher_plus2", "farbjagd":
				s = 12.0 + (danger if next_count <= 3 else 0.0)
				if bluff_mode and not _wild_legal(view, id):
					s -= 40.0 if level >= 2 else 25.0
			"tausch":
				s = 8.0 + swap_value(view)
			"gluecksspiel":
				# Mit kleiner Hand ist die Chance aufs Fertigwerden gut (bei 3 Restkarten fast 50 %); sonst aufsparen – passt
				# nichts anderes, wird er trotzdem gelegt (statt zu ziehen).
				s = 2.0 + (30.0 if hand.size() <= 4 else (8.0 if hand.size() <= 6 else 0.0))
			"ablegen":
				s = _discard_value(_color_count(view, ctab[code], id), hand.size(), 5.0)
			"ablegen_joker":
				var most := 0
				for c in view.get("colors", []):
					most = maxi(most, _color_count(view, str(c), id))
				s = _discard_value(most, hand.size(), 1.0)
		# Beweglichkeit: wie viele Restkarten danach (bei gleicher Farbe) noch passen würden (beim Kartentausch egal: Die Resthand
		# wandert weiter; beim Ablegen geht die Farbe mit).
		if wtab[code] == 0 and kind != CardDB.SWAP and kind != CardDB.DISCARD:
			var mobile := 0
			for other_id in code_by_id:
				if int(other_id) == id:
					continue
				var oc: int = code_by_id[other_id]
				if wtab[oc] == 1 or ctab[oc] == ctab[code] or (ktab[oc] == kind and (kind != "zahl" or vtab[oc] == vtab[code])):
					mobile += 1
			s += 3.0 * mobile
		s += ptab[code] * 0.03
		if level == 1:
			s += rng.randf() * 2.0
		if s > best_score:
			best_score = s
			best_id = id
	if best_id < 0:
		best_id = int(playable[0])
	# Bleibt nur ein Kartentausch, der viel mehr Karten bringt als er abgibt: lieber ziehen.
	if can_draw and _is_swap(int(code_by_id.get(best_id, -1))) and swap_value(view) < -6.0:
		return {"a": "draw"}
	return _play(view, best_id, rng)


static func _drawn(view: Dictionary, hints: Dictionary, rng: RandomNumberGenerator, level: int) -> Dictionary:
	var playable: Array = hints.get("playable", [])
	var can_keep := bool(hints.get("can_keep", false))
	if playable.is_empty():
		return {"a": "keep"} if can_keep else {}
	var id := int(playable[0])
	# Hausregel draw_play = any: beste passende Karte wie im normalen Zug wählen (Ziehen geht nicht mehr), dann wie unten prüfen,
	# ob Behalten besser ist.
	if str((view.get("rules", {}) as Dictionary).get("draw_play", "drawn")) == "any" and playable.size() > 1:
		var th := hints.duplicate()
		th["can_draw"] = false
		var pick := _turn(view, th, rng, level)
		if str(pick.get("a", "")) != "play":
			return {"a": "keep"} if can_keep else _play(view, id, rng)
		id = int(pick.card)
	if can_keep and level > 0:
		var bluff_mode := str((view.get("rules", {}) as Dictionary).get("wild_restriction", "free")) == "bluff"
		if bluff_mode and _is_bluff(view, id):
			return {"a": "keep"}
		var code := _code_of_id(view, id)
		if code >= 0 and CardDB.kind_table()[code] == "wuenscher" and (view.get("hand", []) as Array).size() > 4 \
				and rng.randf() < 0.5:
			return {"a": "keep"}       # Joker aufsparen
		if _is_swap(code) and swap_value(view) < 0.0:
			return {"a": "keep"}       # Kartentausch lohnt gerade nicht
		if code >= 0:
			var size := (view.get("hand", []) as Array).size()
			var kind := CardDB.kind_table()[code]
			if kind == CardDB.GAMBLE and size > 6:
				return {"a": "keep"}           # Glücksspiel mit großer Hand: aufsparen
			if kind == CardDB.DISCARD and _discard_value(_color_count(view, CardDB.color_table()[code], id), size, 0.0) < 10.0:
				return {"a": "keep"}           # nimmt zu wenig mit: aufsparen
			if kind == CardDB.DISCARD_WILD:
				var most := 0
				for c in view.get("colors", []):
					most = maxi(most, _color_count(view, str(c), id))
				if _discard_value(most, size, 0.0) < 10.0:
					return {"a": "keep"}
	return _play(view, id, rng)


static func _challenge(view: Dictionary, hints: Dictionary, rng: RandomNumberGenerator, level: int) -> Dictionary:
	var pend: Dictionary = view.get("pending", {})
	var playable: Array = hints.get("playable", [])
	for id in playable:
		if not _is_bluff(view, int(id)):
			return _play(view, int(id), rng)
	var by := int(pend.get("by", -1))
	var legger: Dictionary = _players_by_seat(view).get(by, {})
	var k := int(legger.get("count", 0))
	if k <= 0 or not bool(hints.get("can_challenge", false)):
		return {"a": "accept"}
	if level <= 0:
		return {"a": "challenge"} if rng.randf() < 0.3 else {"a": "accept"}
	# Verdacht: (1 - q)^k ist die Chance, dass der Leger keine passende Karte hatte (also ehrlich sein musste). Je mehr Karten
	# er hält, desto wahrscheinlicher hatte er eine – geblufft hat er aber nur, wenn er überhaupt blufft (BLUFF_PRIOR).
	var q := COLOR_SHARE
	if bool((view.get("rules", {}) as Dictionary).get("wild_counts_for_bluff", true)):
		q += WILD_SHARE
	var p_bluff := BLUFF_PRIOR * (1.0 - pow(1.0 - q, k))
	# Anzweifeln lohnt, wenn der erwartete Verlust kleiner ist (Strafe des Legers zählt als eigener Vorteil):
	# +2: 4(1-p) - 2p < 2 → p > 1/3. Farbjagd (bis Farbe ≈ E Karten): p > 1/(E+1) ≈ 0,23.
	var threshold := 0.23 if str(pend.get("kind", "")) == "farbjagd" else 0.34
	if level == 1:
		threshold += (rng.randf() - 0.5) * 0.1
	return {"a": "challenge"} if p_bluff > threshold else {"a": "accept"}
