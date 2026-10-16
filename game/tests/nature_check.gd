extends RefCounted
# Mau-Mau Flip (Beta 1.6.12): Prüfhilfe für die Tiere der Natur-Überraschungen (docs/module/natur.md Abschnitt 8.1; kein eigener Test,
# tools/build.ps1 startet nur test_*.gd). Verwendung in test_nature_tag.gd / test_nature_nacht.gd:
#   const NatureCheck := preload("res://tests/nature_check.gd")
#   var t := NatureCheck.make_table(self)                     # echte TableView samt HandView, Uhren aus (auto_process = false)
#   var errs := NatureCheck.check_creature(t.nature, "spatz")  # [] = alles gut, sonst je Fund eine Zeile
# check_creature läuft für jede Größe (Standard SIZES) und Spielerzahl (Standard 2/4/8) seek(t) in 50-ms-Schritten durch und prüft:
#   - Sichtbarkeit in der Hauptphase ≥ 60 % (Hülle im Bild und höchstens zur Hälfte unter Schutzflächen; vorn: im Bild),
#   - Ebene vorn: nur die Flächen aus „deckt“ und höchstens deckt_max_s (Toleranz 0,25 s); Biene nie im Eckindex-Viertel der Handkarte,
#   - nach dur + 1 s ist alles weg (keine Knoten in den Natur-Ebenen),
#   - hit nur auf dem Tier (Mitte der Hülle ja, weit daneben nein),
#   - leave(true) endet in ≤ 0,5 s,
#   - gleicher Samen → gleiche bounds() (Bestimmtheit).
# Bestand-Einträge (Schmetterling, Sternschnuppe) zeichnet FunFx: dafür liefert check_creature [] ohne Prüfung.

const NT := preload("res://scripts/ui/nature_table.gd")
const SIZES := [Vector2(1600, 720), Vector2(1600, 900), Vector2(1760, 720), Vector2(1600, 1000)]
const PLAYERS := [2, 4, 8]
const STEP := 0.05
const VISIBLE_MIN := 0.6
const COVER_TOL := 0.25


# Echte TableView mit HandView (wie TableScreen.build), feste Größe, Uhren von Natur, Ostereiern und Necken aus
static func make_table(tree: SceneTree, sz := Vector2(1600, 720), players := 4, turn := 1) -> TableView:
	var t := TableView.new()
	tree.root.add_child(t)
	t.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	t.size = sz
	t.sprueche.set_level("aus")
	t.fun.auto_process = false
	t.tease.auto_process = false
	t.nature.auto_process = false
	t.nature.print_log = false
	var hand := HandView.new()
	hand.name = "Hand"
	t.set_hand(hand)
	hand.layout_rect = t.hand_rect(sz)
	show(t, players, turn)
	return t


# Sicht mit n Spielern zeigen (ich = Platz 0, am Zug turn) und die Hand einschwingen lassen
static func show(t: TableView, players := 4, turn := 1, sd := 7) -> TableSamples:
	var s := TableSamples.create(players, sd)
	s.turn = turn
	t.apply_view(s.view_for(0))
	settle(t)
	return s


static func settle(t: TableView) -> void:
	var h: Variant = t.hand
	if h is Object and (h as Object).has_method("step"):
		for i in 80:
			(h as Object).call("step", 0.05)


static func resize(t: TableView, sz: Vector2) -> void:
	t.size = sz
	var h: Variant = t.hand
	if h is Object:
		(h as Object).set("layout_rect", t.hand_rect(sz))
	settle(t)


static func check_creature(fx: Object, id: String, sizes: Array = SIZES, players: Array = PLAYERS, sd := 11) -> Array[String]:
	var errs: Array[String] = []
	var e := NT.entry(id)
	if e.is_empty():
		errs.append("%s: unbekannte id" % id)
		return errs
	if bool(e["bestand"]):
		return errs
	var t: TableView = fx.get("table")
	if t == null:
		errs.append("%s: NatureFx ohne Tisch" % id)
		return errs
	var old_size := t.size
	for sz in sizes:
		for n in players:
			resize(t, sz)
			show(t, int(n), 1)
			errs.append_array(_check_one(fx, id, e, "%s %dx%d %d Spieler" % [id, int(sz.x), int(sz.y), int(n)], sd + int(n)))
	resize(t, old_size)
	return errs


static func _check_one(fx: Object, id: String, e: Dictionary, tag: String, sd: int) -> Array[String]:
	var errs: Array[String] = []
	if not bool(fx.call("spawn", id, sd)):
		errs.append("%s: spawn scheitert (kein Tier?)" % tag)
		return errs
	var c: Node2D = fx.call("creature")
	if c == null:
		errs.append("%s: kein Knoten" % tag)
		return errs
	var t: TableView = fx.get("table")
	var screen := Rect2(Vector2.ZERO, t.size)
	var obs: Dictionary = fx.call("obstacles")
	var deckt: Array = e["deckt"]
	var front := str(c.get("layer")) == "vorn"
	var dur := float(c.get("dur"))
	var main_n := 0
	var main_vis := 0
	var cover := {}            # Fläche → Sekunden
	var corner_hits := 0
	var card: Dictionary = fx.call("hand_card")
	var tt := 0.0
	var samples: Array = []
	while tt <= dur + 1e-6:
		fx.call("seek", tt)
		var b: Rect2 = fx.call("world_bounds")
		samples.append(b)
		var vis := b.has_area() and b.intersects(screen) and float(c.modulate.a) > 0.05
		if str(c.call("phase")) == "main":
			main_n += 1
			if vis and (front or _covered(b, obs) <= 0.5):
				main_vis += 1
		if vis and front:
			for key in obs:
				for r in obs[key]:
					if b.intersects(r):
						cover[key] = float(cover.get(key, 0.0)) + STEP
						break
			if id == "biene" and not card.is_empty():
				var lp: Vector2 = (card["xf"] as Transform2D).affine_inverse() * b.get_center()
				var cs: Vector2 = card["size"]
				if lp.x < 0.0 and lp.y < 0.0 and lp.x > -cs.x * 0.5 and lp.y > -cs.y * 0.5:
					corner_hits += 1
		tt += STEP
	if main_n == 0:
		errs.append("%s: keine Hauptphase (in_s/out_s/dur?)" % tag)
	elif float(main_vis) / float(main_n) < VISIBLE_MIN:
		errs.append("%s: in der Hauptphase nur %d %% sichtbar" % [tag, int(100.0 * main_vis / main_n)])
	if front:
		var max_s := float(e["deckt_max_s"])
		for key in cover:
			var s := float(cover[key])
			if deckt.has(key):
				if s > max_s + COVER_TOL:
					errs.append("%s: deckt „%s“ %.2f s (höchstens %.1f s)" % [tag, key, s, max_s])
			elif s > COVER_TOL:
				errs.append("%s: deckt „%s“ %.2f s (nicht erlaubt)" % [tag, key, s])
		if corner_hits > 0:
			errs.append("%s: Biene %d× im Eckindex-Viertel der Handkarte" % [tag, corner_hits])
	# Treffer: Mitte der Hülle ja, weit daneben nein (Mitte der Hauptphase)
	var mid := _main_mid(c, dur)
	fx.call("seek", mid)
	var bm: Rect2 = fx.call("world_bounds")
	if bm.has_area():
		var lay := _layer_of(fx, c)
		var to_l := lay.get_global_transform().affine_inverse() * t._world.get_global_transform()
		if not bool(c.call("hit", to_l * bm.get_center())):
			errs.append("%s: hit trifft die Mitte der Hülle nicht" % tag)
		var far := bm.get_center() + Vector2(maxf(bm.size.x, bm.size.y) + 3.0 * float(NT.timing("treffer_min_r")), 0)
		if bool(c.call("hit", to_l * far)):
			errs.append("%s: hit trifft weit neben dem Tier" % tag)
	# nach dur + 1 s ist alles weg
	fx.call("seek", dur + 1.0)
	if not bool(c.call("is_done")):
		errs.append("%s: nach dur + 1 s nicht fertig" % tag)
	fx.call("tick", 0.0)
	if fx.get("current") != null:
		errs.append("%s: läuft nach dur + 1 s noch" % tag)
	var left := 0
	for key in (fx.get("layers") as Dictionary):
		left += ((fx.get("layers") as Dictionary)[key] as Node).get_child_count()
	if left > 0:
		errs.append("%s: %d Knoten bleiben in den Natur-Ebenen" % [tag, left])
	# leave(true) ≤ 0,5 s
	fx.call("spawn", id, sd)
	var c2: Node2D = fx.call("creature")
	if c2 != null:
		fx.call("seek", mid)
		c2.call("leave", true)
		fx.call("seek", mid + 0.5)
		if not bool(c2.call("is_done")):
			errs.append("%s: leave(true) endet nicht in 0,5 s" % tag)
	# Bestimmtheit: gleicher Samen → gleiche Hülle
	fx.call("spawn", id, sd)
	tt = 0.0
	var i := 0
	var diff := 0
	while tt <= dur + 1e-6 and i < samples.size():
		if i % 10 == 0:
			fx.call("seek", tt)
			var b: Rect2 = fx.call("world_bounds")
			var a: Rect2 = samples[i]
			if not (b.position.is_equal_approx(a.position) and b.size.is_equal_approx(a.size)):
				diff += 1
		tt += STEP
		i += 1
	if diff > 0:
		errs.append("%s: gleicher Samen, %d× andere Hülle (nicht rein in t?)" % [tag, diff])
	fx.call("clear")
	return errs


static func _covered(b: Rect2, obs: Dictionary) -> float:
	var a := b.get_area()
	if a <= 0.0:
		return 0.0
	var s := 0.0
	for key in obs:
		for r in obs[key]:
			if b.intersects(r):
				s += b.intersection(r).get_area()
	return minf(s / a, 1.0)


static func _main_mid(c: Node2D, dur: float) -> float:
	var a := float(c.get("in_s"))
	var b := dur - float(c.get("out_s"))
	return (a + b) * 0.5 if b > a else dur * 0.5


static func _layer_of(fx: Object, c: Node2D) -> Node2D:
	var layers: Dictionary = fx.get("layers")
	return layers.get(str(c.get("layer")), c.get_parent())
