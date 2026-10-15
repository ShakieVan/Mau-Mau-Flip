class_name TeaseFx
extends Node
# Mau-Mau Flip (Beta 1.6.3, Easter Eggs Teil 2 „Necken“, docs/module/eastereggs2.md Abschnitte 2 und 3): die Oberfläche des Neckens
# am Tisch. Teil 1 (FunFx) bleibt rein lokal; hier kommt an, was der Gastgeber als {t:"fx", k, from, to?, r?} verteilt
# (TableSource.fx_event, auf allen Geräten gleich, auch beim Absender) – erst dann erscheint der Effekt.
#   Schnarchen  „Z z z“ steigen 4,2 s in Wellen über dem Avatar auf, dazu eine Schlafmütze; Ton laut beim Ziel, leise beim Absender.
#   Wecker      hüpft über den Avatar, tickt 3 s sichtbar (ohne Ton), klingelt dann 1,8 s mit Wackeln und Schwinglinien; beim Ziel
#               groß über dem eigenen Namensschild, Klingeln + Vibration 3 × 250 ms. Handelt das Ziel vorher, fällt er um
#               („Gerade noch geschafft!“). Liegt die Mau-Katze auf dem Stapel, springt sie beim Klingeln davon.
#   Papierkugel fliegt auf einer Parabel (0,7 s, dreht sich) vom Absender zum Ziel, Plopp, der Avatar staucht sich, die Kugel springt
#               zurück und bleibt 3 s liegen (höchstens 3 je Platz). Bot: „Mpf!“.
#   Reaktion    😂 😱 👏 👍 als gezeichnete Bilder (keine Emoji-Schrift in der App) steigen 1,6 s am Platz des Absenders auf; Ton
#               auf allen Geräten, je Gerät höchstens 2 gleichzeitig und je Name 600 ms Sperre (Jubel und Mau behalten ihre Stimmen).
# Bedienung: Kopf eines Gegners → Necken-Menü (TeaseMenu), Fächer ohne sichtbare Rückseiten ebenso; Reaktionsknopf am eigenen Platz
# (TeaseMenu.ReactionPicker). Beide zeigen nur, was nach TeaseRules mit der lokalen Uhr gerade geht (source.fx_check).
# Effekte reduziert: keine Flugbahn (Kugel erscheint am Ziel), kein Wackeln/Stauchen, Z stehen still, Reaktionen blenden am Platz.
# Spieltöne aus/leise gelten für alle Neck-Töne (AppSound), „Necken aus“ (Einstellung necken): nichts sehen, hören oder schicken.
# Der Tisch ruft: mount, attach(source), on_view, on_event, on_fx, on_refused, tap_head/tap_fan/tap_me, set_enabled.
# Die Uhr läuft über _process; Tests schalten auto_process aus und rufen tick(delta) (wie FunFx).

signal send_requested(req: Dictionary)   # Menüwahl → source.send_fx (attach verbindet das selbst)

const MenuScript := preload("res://scripts/ui/tease_menu.gd")

const SNORE_S := 4.2
const ALARM_HOP_S := 0.25
const ALARM_TICK_S := 3.0
const ALARM_RING_S := 1.8
const BALL_FLY_S := 0.7
const BALL_LIE_S := 3.0
const BALL_MAX := 3
const BALL_FLY_R := 27.0                   # Beta 1.6.3: Kugel im Flug 1,6-fach (vorher 17), liegend etwas kleiner
const BALL_LIE_R := 21.0
const REACT_R := 38.0                      # Beta 1.6.3: Reaktionsbilder 1,6-fach (vorher 24)
const REACT_RISE := 80.0
const REACT_S := 1.6
const REACT_SOUND_MAX := 2                 # je Gerät höchstens so viele Reaktionstöne gleichzeitig
const REACT_SOUND_GAP_MS := 600            # je Reaktionsname
const REACT_LEN_MS := {"lachen": 1920, "schreck": 610, "klatschen": 1920, "daumen": 620}   # Dateilängen (eastereggs2.md 7)
const SOUND_OF := {"lachen": "lachen", "schreck": "schreck", "klatschen": "klatschen", "daumen": "daumen"}
const MENU_IDLE_S := 5.0
const RATE_GRAY_S := 1.2                   # fx_no "rate": Knöpfe kurz ausgegraut
const REOPEN_GAP_MS := 400                 # derselbe Kopf direkt nach dem Schließen: nicht gleich wieder öffnen
const SYNC_S := 0.15                       # Beta 1.6.3: Abstand der Regelprüfung in tick (Reaktionsknopf, Menüeinträge)

var table: TableView
var source: TableSource
var layer: Node2D                          # Effekte (über Ablage und Fächern, unter Farbwahl-Rad, Hilfe und Sichtschutz)
var menu: TeaseMenu                        # offenes Necken-Menü (oder null)
var picker: TeaseMenu.ReactionPicker       # Reaktionsknopf am eigenen Platz
var enabled := true                        # Einstellung „necken“ dieses Geräts
var reduced := false
var night := 0.0: set = set_night
var big := false
var auto_process := true
var now := 0.0                             # Uhr der Effekte (Sekunden, nur über tick)
var sound: Object = null                   # Tests: Attrappe mit play(name, db) und fade_out(name, ms); sonst App.sound
var vibrate_cb := Callable()               # Tests: (ms) statt UiApp.vibrate
var modal_cb := Callable()                # Gerätetest 1.6.3, TableScreen: () -> bool, ein Dialog/Menü liegt über dem Tisch
var avoid_cb := Callable()                # TableScreen: () -> Array[Rect2] (Bildschirm), die das Menü meidet (Knöpfe oben links)
var sounds: Array = []                     # Tests/Protokoll: [name, extra_db] je gestartetem Ton
var vibrations: Array = []                 # Tests: ms je Vibration
var fades: Array = []                      # Tests: ausgeblendete Töne
var shown := 0                             # Tests: Zahl der gezeigten Effekte

var _react_play: Array = []                # [{name, until}] laufende Reaktionstöne (ms auf der Uhr now)
var _react_last := {}                      # Name → ms
var _vibes: Array = []                     # [{at, ms}] geplante Vibrationen
var _rate_until := -1.0
var _last_target := -1                     # Ziel des letzten eigenen Wunschs (für „Zu spät – Kim …“)
var _turn := -1
var _closed_seat := -1
var _closed_ms := -100000
var _picker_closed_ms := -100000         # Beta 1.6.3: Fächer per Tipp daneben geschlossen (Uhr now, ms)
var _sync_left := 0.0                     # Beta 1.6.3: bis zur nächsten vollen Prüfung (Reaktionsknopf, Menü) in tick
var _react_cap := false                  # Beta 1.6.3: Reaktionen in dieser Spielart (caps), zuletzt geprüft
var _react_why := "mode"                  # Beta 1.6.3: zuletzt geprüfter Grund für Reaktionen (fx_check)
var _picker_key := ""                     # Beta 1.6.3: zuletzt gezeichneter Stand des Reaktionsknopfs


func _init() -> void:
	name = "Necken"


# Ebenen einhängen: Effekte direkt über fx_top, Menü unter der Rückseiten-Großansicht, Reaktionsknopf über dem Rundenende.
func mount(t: TableView) -> void:
	table = t
	t.add_child(self)
	var ov: Control = t.get("_overlay")
	layer = Node2D.new()
	layer.name = "NeckenEffekte"
	ov.add_child(layer)
	ov.move_child(layer, t.fx_top.get_index() + 1)
	picker = TeaseMenu.ReactionPicker.new()
	picker.name = "Reaktionsknopf"
	picker.visible = false
	picker.chosen.connect(_on_react_chosen)
	picker.dismissed.connect(_on_picker_dismissed)
	ov.add_child(picker)
	ov.move_child(picker, t.round_end.get_index() + 1)
	enabled = HandView.truthy(UiApp.setting("necken", true))


# Spielsteuerung anschließen (TableScreen): fx_event → on_fx, fx_refused → on_refused, Menüwahl → send_fx.
func attach(src: TableSource) -> void:
	if src == null:
		return
	source = src
	if not src.fx_event.is_connected(on_fx):
		src.fx_event.connect(on_fx)
		src.fx_refused.connect(on_refused)
		src.fx_offs_changed.connect(_on_offs)
	if not send_requested.is_connected(src.send_fx):
		send_requested.connect(src.send_fx)
	src.set_fx_off(not enabled)
	_sync_picker()


func set_enabled(on: bool) -> void:
	enabled = on
	if source != null:
		source.set_fx_off(not on)
	if not on:
		close_menu()
		clear()
	_sync_picker()


func set_night(v: float) -> void:
	night = v
	if menu != null:
		menu.night = v
		menu.queue_redraw()
	if picker != null:
		picker.night = v
		picker.queue_redraw()


func k() -> float:
	return 1.3 if big else 1.0


func _process(delta: float) -> void:
	if auto_process:
		tick(delta)


# Zeit voranschalten (eine Bildzeit): Effekte, geplante Vibrationen, Menü (Ausgrauen nach lokaler Uhr, Selbstschließen).
func tick(delta: float) -> void:
	now += delta
	if layer != null:
		for c in layer.get_children():
			if c is TeaseEffect and not (c as TeaseEffect).step(delta):
				c.queue_free()
				layer.remove_child(c)
	var still: Array = []
	for v in _vibes:
		if now >= float(v.at):
			_vibrate(int(v.ms))
		else:
			still.append(v)
	_vibes = still
	# Beta 1.6.3: Regeln (fx_check, Menüeinträge) nur alle SYNC_S neu prüfen; Sicht, fx, fx_no und fx_offs prüfen sofort.
	_sync_left -= delta
	var full := _sync_left <= 0.0
	if full:
		_sync_left = SYNC_S
	if menu != null:
		menu.idle += delta
		if menu.idle >= MENU_IDLE_S:
			close_menu()
		elif full:
			_refresh_menu()
	_sync_picker(full)


# ================================================================= Sicht und Ereignisse

func on_view(v: Dictionary) -> void:
	var phase := str(v.get("phase", ""))
	var turn: int = int(v.get("turn", -1)) if v.get("turn") is int or v.get("turn") is float else -1
	if not phase in TeaseRules.TURN_PHASES:
		turn = -1
	if turn != _turn:
		_turn = turn
		close_menu()
	var h: Variant = v.get("hints", {})
	if h is Dictionary and (h as Dictionary).get("catch") is Array and not ((h as Dictionary).get("catch") as Array).is_empty():
		close_menu()                          # Erwischen geht vor (eastereggs2.md 2)
	for e in effects():
		if (e is AlarmFx or e is SnoreFx) and e.target != turn:
			_wake_up(e)
	_sync_picker()


func on_event(ev: Dictionary) -> void:
	var e := str(ev.get("e", ""))
	if e == "seats":
		close_menu()
		clear()                               # Platznummern verschieben sich: Effekte je Platz abräumen
		return
	var s = ev.get("seat")
	if s is int or s is float:
		for fx in effects():
			if (fx is AlarmFx or fx is SnoreFx) and fx.target == int(s):
				_wake_up(fx)


# Das Ziel hat gehandelt bzw. ist nicht mehr am Zug: Wecker fällt um (klingelt nicht), Schnarchen blendet aus.
func _wake_up(fx: TeaseEffect) -> void:
	if fx is AlarmFx:
		var a := fx as AlarmFx
		if a.state == "hop" or a.state == "tick":
			a.defuse()
			if a.target == _me():
				# Gerätetest 1.6.3: an die Stelle der Zeile „… hat dir einen Wecker gestellt!“ (rechts neben dem Wecker), die alte
				# Zeile verschwindet – vorher lag „Gerade noch geschafft!“ quer über ihr und dem Wecker
				if a.banner != null and is_instance_valid(a.banner):
					a.banner.queue_free()
					if a.banner.get_parent() == layer:
						layer.remove_child(a.banner)
				a.banner = null
				_banner(I18n.t("Gerade noch geschafft!"), UiPalette.TURN, _alarm_text_left(a) if a.big_clock else Vector2.INF)
	elif fx is SnoreFx:
		var s := fx as SnoreFx
		if not s.ending:
			s.end_soon()
			if s.loud or s.quiet:
				_fade("schnarchen")


func effects() -> Array:
	var out: Array = []
	if layer != null:
		for c in layer.get_children():
			if c is TeaseEffect and not c.is_queued_for_deletion():
				out.append(c)
	return out


func effects_of(kind: String) -> Array:
	var out: Array = []
	for e in effects():
		if (e as TeaseEffect).kind == kind:
			out.append(e)
	return out


func clear() -> void:
	for e in effects():
		# Beta 1.6.3: laufende Töne mit abräumen (Necken aus, Platzwechsel): Schnarchen (4,2 s) und Klingeln blenden aus
		if e is SnoreFx and not (e as SnoreFx).ending and ((e as SnoreFx).loud or (e as SnoreFx).quiet):
			_fade("schnarchen")
		elif e is AlarmFx and (e as AlarmFx).state == "ring" and ((e as AlarmFx).loud or (e as AlarmFx).quiet):
			_fade("wecker")
		e.queue_free()
		layer.remove_child(e)
	_vibes.clear()


# ================================================================= Angenommenes Necken (fx_event)

func on_fx(msg: Dictionary) -> void:
	_sync_left = 0.0                          # Beta 1.6.3: Eimer haben sich geändert – im nächsten tick neu prüfen
	if not enabled or table == null:
		return
	var k_ := str(msg.get("k", ""))
	var from: int = int(msg.get("from", -1)) if msg.get("from") is int or msg.get("from") is float else -1
	var to: int = int(msg.get("to", -1)) if msg.get("to") is int or msg.get("to") is float else -1
	match k_:
		"snore":
			_snore(from, to)
		"alarm":
			_alarm(from, to)
		"ball":
			_ball(from, to)
		"react":
			_react(from, str(msg.get("r", "")))


# Eigener Wunsch abgelehnt (fx_no): „late“/„busy“ als leise Zeile, „rate“ graut kurz aus. Kein Fehlerton.
func on_refused(why: String) -> void:
	if not enabled or table == null:
		return
	var who := _name(_last_target)
	match why:
		"late":
			table.show_notice(I18n.t("Zu spät – %s hat schon gespielt.") % who)
		"busy":
			table.show_notice(I18n.t("%s wird gerade schon geweckt.") % who)
		"rate":
			_rate_until = now + RATE_GRAY_S
			_refresh_menu()
			_sync_picker()
			# Menü bzw. Fächer sind nach dem Senden meist schon zu: der Reaktionsknopf wackelt und ist kurz blass (Beta 1.6.3)
			if picker != null and picker.visible:
				picker.nudge()


func rate_limited() -> bool:
	return now < _rate_until


func _on_offs(_seats: Array) -> void:
	_refresh_menu()
	_sync_picker()


func _me() -> int:
	if table == null or int(table.view.get("seat", -1)) < 0:
		return -1
	return table.my_seat


func _current_turn() -> int:
	var v: Dictionary = source.current_view() if source != null else table.view
	if v.is_empty():
		v = table.view
	if not str(v.get("phase", "")) in TeaseRules.TURN_PHASES:
		return -1
	return int(v.get("turn", -1)) if v.get("turn") is int or v.get("turn") is float else -1


func _name(seat: int) -> String:
	var p := table._player(seat) if table != null else {}
	return str(p.get("name", I18n.t("Spieler %d") % (seat + 1)))


func _is_bot(seat: int) -> bool:
	return str(table._player(seat).get("kind", "human")) == "bot"


func _snore(from: int, to: int) -> void:
	if to < 0 or to != _current_turn():
		return                                # kommt zu spät: nichts zeigen (der Gastgeber hat es ohnehin angenommen)
	var me := _me()
	var a := anchor(to)
	var fx := SnoreFx.new()
	_setup(fx, "snore", to)
	fx.target = to
	fx.position = a.pos
	fx.r = float(a.r)
	_place_snore(fx, to)
	fx.loud = to == me
	fx.quiet = from == me and to != me
	_add(fx)
	if fx.loud:
		_play("schnarchen", false)
		_banner(I18n.t("%s findet, du schläfst gleich ein.") % _name(from), UiPalette.MOON)
	elif fx.quiet:
		_play("schnarchen", true)


func _alarm(from: int, to: int) -> void:
	if to < 0 or to != _current_turn():
		return
	var me := _me()
	var a := anchor(to)
	var fx := AlarmFx.new()
	_setup(fx, "alarm", to)
	fx.target = to
	fx.loud = to == me
	fx.quiet = from == me and to != me
	fx.big_clock = fx.loud
	# beim Ziel groß über dem eigenen Namensschild, sonst schräg links über dem Avatar (rechts steht die Denkblase); Beta 1.6.3:
	# bei Mitspielern doppelt so groß (ging auf dem Handy unter), Lage nach _choose (im Bild, nicht über Erwischt/Mau/Stapel/Hand)
	if fx.big_clock:
		fx.position = Vector2(a.pos) + Vector2(6.0 * k(), -float(a.r) - 52.0 * k())
	else:
		var s := (36.0 if _list_mode(to) else 40.0) * k()
		fx.sz = s
		var r := float(a.r)
		var c := Vector2(a.pos)
		var rel := Rect2(-1.25 * s, -1.45 * s - 18.0 * k(), 2.5 * s, 2.5 * s + 18.0 * k())
		var cands: Array = []
		var hd := head_of(to)
		if _list_mode(to):                    # großer Modus: in der eigenen Zeile links neben der Kartenzahl
			cands.append({"pos": Vector2(float(hd.count_x) - s * 1.3 - 8.0, c.y + s * 0.1), "rel": rel})
		cands.append({"pos": c + Vector2(-r * 0.55, -r - s * 1.1), "rel": rel})
		cands.append({"pos": c + Vector2(-r - s * 1.3 - 4.0, -s * 0.15), "rel": rel})
		cands.append({"pos": c + Vector2(0.0, -r - s * 1.15), "rel": rel})
		cands.append({"pos": Vector2((hd.rect as Rect2).end.x + s * 1.3 + 6.0, c.y), "rel": rel})
		fx.position = Vector2(_choose(cands, _blockers(to)).pos)
	fx.on_ring = _on_ring.bind(fx)
	_add(fx)
	if fx.loud:
		fx.banner = _banner(I18n.t("%s hat dir einen Wecker gestellt!") % _name(from), UiPalette.TURN, _alarm_text_left(fx))


# Textzeile beim Ziel: beginnt rechts neben dem großen Wecker
func _alarm_text_left(fx: AlarmFx) -> Vector2:
	return fx.position + Vector2(fx.size_s() * 1.5 + 8.0 * k(), 0.0)


func _on_ring(fx: AlarmFx) -> void:
	if fx.loud:
		_play("wecker", false)
		for i in 3:
			_vibes.append({"at": now + i * 0.4, "ms": 250})
	elif fx.quiet:
		_play("wecker", true)
	var fun: FunFx = table.fun
	if fun != null and fun.cat != null and fun.cat.active():
		fun.cat.leave(true, table.size.x if table.size.x > 10.0 else 1600.0)   # Extra: die Mau-Katze erschrickt


func _ball(from: int, to: int) -> void:
	if to < 0:
		return
	var me := _me()
	var a_to := anchor(to)
	var from_pos: Vector2 = _throw_point(from)
	var fx := BallFx.new()
	_setup(fx, "ball", to)
	fx.target = to
	fx.from = from_pos
	fx.to = Vector2(a_to.pos) + Vector2(0, -float(a_to.r) * 0.2)
	fx.r_target = float(a_to.r)
	fx.seed_v = int(now * 1000.0) + from * 31 + to * 7
	fx.on_hit = _on_ball_hit.bind(fx, from, to)
	# höchstens BALL_MAX Kugeln je Platz: die älteste liegende verschwindet
	var lying: Array = []
	for e in effects_of("ball"):
		if (e as BallFx).target == to:
			lying.append(e)
	while lying.size() >= BALL_MAX:
		var old: BallFx = lying.pop_front()
		old.queue_free()
		layer.remove_child(old)
	# liegt links neben dem Avatar, mehrere nebeneinander (nicht über Avatar, Name oder Computer-Abzeichen)
	var slot := 0
	for e in lying:
		slot = maxi(slot, (e as BallFx).slot + 1)
	fx.slot = slot % BALL_MAX
	# Beta 1.6.3: im Flug 1,6-fach (BALL_FLY_R), liegend etwas kleiner (BALL_LIE_R); großer Modus: in der Zeile vor der Kartenzahl
	if _list_mode(to):
		var hd := head_of(to)
		fx.rest = Vector2(float(hd.count_x) - BALL_LIE_R * k() - 10.0 - fx.slot * 36.0 * k(), Vector2(a_to.pos).y + float(a_to.r) * 0.35)
	else:
		fx.rest = Vector2(a_to.pos) + Vector2(-float(a_to.r) - 24.0 * k() - fx.slot * 36.0 * k(), float(a_to.r) * 0.5)
		fx.rest.x = maxf(fx.rest.x, BALL_LIE_R * k() + 8.0)
	_add(fx)
	if from == me:
		_play("papier_wurf", false)
	if reduced:
		fx.skip_flight()


func _on_ball_hit(_fx: BallFx, from: int, to: int) -> void:
	var me := _me()
	if to == me:
		_play("papier_plopp", false)
		_vibrate(40)
		_banner(I18n.t("Papierkugel von %s!") % _name(from), UiPalette.CREAM)
	elif from != me:
		_play("papier_plopp", true)
	if not reduced:
		var node: OpponentSeat = table.me_badge if to == me else table.seat_node(to)
		if node != null:
			node.set("_bump", 1.0)
			node.create_tween().tween_property(node, "_bump", 0.0, 0.35)
	var fresh := effects_of("text").filter(func(e: TextFx) -> bool: return e.seat == to and e.t < 0.6)
	if _is_bot(to) and fresh.is_empty():             # „Mpf!“ nicht doppelt übereinander
		var a := anchor(to)
		_float(I18n.t("Mpf!"), Vector2(a.pos) + Vector2(0, -float(a.r) - 26.0 * k()), UiPalette.CREAM, to)


func _react(from: int, r: String) -> void:
	if not r in TeaseRules.FX_REACTS:
		return
	var a := anchor(from)
	var fx := ReactFx.new()
	_setup(fx, "react", from)
	fx.r_name = r
	var near := 0
	for e in effects_of("react"):
		if (e as ReactFx).seat == from and (e as ReactFx).t < 0.8:
			near += 1
	var side_k := float(ceili(near / 2.0)) * (1.0 if near % 2 == 1 else -1.0)
	# Beta 1.6.3: 1,6-fach; Lage nach _choose: über dem Avatar, links daneben, rechts neben dem Kopf (großer Modus: in der Zeile),
	# jeweils im Bild und möglichst nicht über Erwischt, Mau, Stapel und Hand
	var s := REACT_R * k()
	fx.s = s
	fx.rise = 0.0 if reduced else REACT_RISE * k()
	var ar := float(a.r)
	var c := Vector2(a.pos)
	var dx := side_k * s * 2.15
	var rel := Rect2(-s - 8.0 * k(), -fx.rise - s * 1.15, 2.0 * s + 16.0 * k(), fx.rise + s * 2.2)
	var hd := head_of(from)
	var cands: Array = []
	if _list_mode(from):
		cands.append({"pos": Vector2(lerpf(c.x + ar, float(hd.count_x), 0.6) + dx, c.y), "rel": rel})
	cands.append({"pos": c + Vector2(dx, -ar - s * 0.85), "rel": rel})
	cands.append({"pos": c + Vector2(-ar - s - 14.0 * k() + dx, -s * 0.2), "rel": rel})
	cands.append({"pos": Vector2((hd.rect as Rect2).end.x + s + 10.0 + dx, c.y), "rel": rel})
	fx.position = Vector2(_choose(cands, _blockers(from)).pos)
	_add(fx)
	_react_sound(r)


# Reaktionston mit Deckel: höchstens REACT_SOUND_MAX gleichzeitig, derselbe Name frühestens nach REACT_SOUND_GAP_MS. true = gespielt.
func _react_sound(r: String) -> bool:
	var ms := int(now * 1000.0)
	var still: Array = []
	for e in _react_play:
		if int(e.until) > ms:
			still.append(e)
	_react_play = still
	if _react_play.size() >= REACT_SOUND_MAX:
		return false
	if _react_last.has(r) and ms - int(_react_last[r]) < REACT_SOUND_GAP_MS:
		return false
	if not _play(str(SOUND_OF[r]), false):
		return false
	_react_last[r] = ms
	_react_play.append({"name": r, "until": ms + int(REACT_LEN_MS[r])})
	return true


func _setup(fx: TeaseEffect, kind: String, seat: int) -> void:
	fx.kind = kind
	fx.seat = seat
	fx.k = k()
	fx.night = night
	fx.reduced = reduced


func _add(fx: TeaseEffect) -> void:
	layer.add_child(fx)
	shown += 1


func _banner(text: String, color: Color, left := Vector2.INF) -> TextFx:
	# Text beim Ziel, linksbündig über dem eigenen Namensschild (bzw. ab left), ganz im Bild
	var a := anchor(_me())
	var b := TextFx.new()
	_setup(b, "text", _me())
	b.text = text
	b.color = color
	b.size_px = int(UiFonts.size("hinweisleiste") * k())
	b.dur = 2.8
	var l := left if left.is_finite() else Vector2(a.pos) + Vector2(-float(a.r), -float(a.r) - 34.0 * k())
	b.position = _clamp_text(l + Vector2(b.text_width() * 0.5, 0.0), b.text_width())
	_add(b)
	return b


func _float(text: String, pos: Vector2, color: Color, seat := -1) -> void:
	var b := TextFx.new()
	_setup(b, "text", seat)
	b.text = text
	b.color = color
	b.size_px = int(30 * k())
	b.dur = 0.9
	b.rise = 26.0
	b.position = _clamp_text(pos, b.text_width())
	_add(b)


func _clamp_text(pos: Vector2, w: float) -> Vector2:
	var sz := _screen()
	return Vector2(clampf(pos.x, w * 0.5 + 12.0, maxf(w * 0.5 + 12.0, sz.x - w * 0.5 - 12.0)), clampf(pos.y, 40.0, sz.y - 40.0))


func _screen() -> Vector2:
	return table.size if table != null and table.size.x > 10.0 else TableLayout.BASE


# ================================================================= Lage am Tisch

# Bezugspunkt eines Platzes in Koordinaten der Effekt-Ebene: Avatar (Gegner, großer Modus: Listenzeile), eigener Platz am
# Namensschild (me_badge), sonst über der Hand. {pos, r}
func anchor(seat: int) -> Dictionary:
	var me := _me()
	if seat >= 0 and seat == me:
		if table.me_badge.visible:
			return {"pos": _g2l(table.me_badge.avatar_global()), "r": table.me_badge.avatar_radius()}
		return {"pos": _g2l(_hand_global() + Vector2(0, -60)), "r": 40.0}
	var node := table.seat_node(seat)
	if node != null:
		return {"pos": _g2l(node.avatar_global()), "r": node.avatar_radius()}
	return {"pos": _g2l(table.get_global_transform() * table.table_center()), "r": 30.0}


# Abwurf der Papierkugel: Gegner am Avatar, eigener Platz über der Hand
func _throw_point(seat: int) -> Vector2:
	if seat >= 0 and seat == _me():
		return _g2l(_hand_global() + Vector2(0, -70))
	return Vector2(anchor(seat).pos)


func _hand_global() -> Vector2:
	var w: Node2D = table.get("_world")
	return table.get_global_transform() * (w.transform * table._hand_point())


# globale Tischkoordinate (Canvas des Tisches) → Effekt-Ebene
func _g2l(g: Vector2) -> Vector2:
	if layer == null:
		return g
	return table._table_to(layer, table.get_global_transform().affine_inverse() * g)


static func _rect_of(p0: Vector2, p1: Vector2) -> Rect2:
	return Rect2(p0, Vector2.ZERO).expand(p1)


func _g2l_rect(g: Rect2) -> Rect2:
	return _rect_of(_g2l(g.position), _g2l(g.end))


# Platz (Gegner oder eigenes Namensschild) als Knoten
func _seat_badge(seat: int) -> OpponentSeat:
	if table == null:
		return null
	if seat >= 0 and seat == _me():
		return table.me_badge if table.me_badge.visible else null
	return table.seat_node(seat)


func _list_mode(seat: int) -> bool:
	var sn := _seat_badge(seat)
	return sn != null and sn.list_mode


# Beta 1.6.3: Kopf eines Platzes in der Effekt-Ebene: rect (Avatar, Name, Kartenzahl bzw. die ganze Listenzeile) und count_x
# (großer Modus: linker Rand der großen Kartenzahl, sonst das Ende des Kopfs)
func head_of(seat: int) -> Dictionary:
	var a := anchor(seat)
	var sn := _seat_badge(seat)
	var r := float(a.r)
	if sn == null:
		var c := Vector2(a.pos)
		return {"rect": Rect2(c - Vector2(r, r), Vector2(2.0 * r, 2.0 * r)), "count_x": c.x + r}
	var loc := sn.list_rect() if sn.list_mode else Rect2(sn._header_x0(), -sn.avatar_radius(), sn.header_width(), 2.0 * sn.avatar_radius())
	var rect := _rect_of(_g2l(sn.to_global(loc.position)), _g2l(sn.to_global(loc.end)))
	var cx := rect.end.x
	if sn.list_mode:
		cx = _g2l(sn.to_global(sn.count_rect().position)).x
	return {"rect": rect, "count_x": cx}


# Beta 1.6.3 (größere Effekte): was ein Effekt am Platz seat möglichst nicht überdeckt, in der Effekt-Ebene.
# hard: „Erwischt!“ erwischbarer Plätze, Mau-Knopf, Ziehstapel, Ablage, Hand, Knöpfe (oben links, Sortieren, Rückseiten); soft: Köpfe
func _blockers(seat: int) -> Dictionary:
	var hard: Array[Rect2] = []
	var soft: Array[Rect2] = []
	if table == null or layer == null:
		return {"hard": hard, "soft": soft}
	if table.mau_button.visible:
		hard.append(_g2l_rect(table.mau_button.get_global_rect()))
	for st in table.get("_seats"):
		var sn: OpponentSeat = table.seat_node(int(st))
		if sn == null:
			continue
		if sn.catchable:
			hard.append(catch_rect_of(int(st), layer))
		if int(st) != seat and sn.is_visible_in_tree() and sn.modulate.a > 0.5:
			soft.append(head_of(int(st)).rect)
	if seat != _me() and table.me_badge.visible and _me() >= 0:
		soft.append(head_of(_me()).rect)
	# der eigene Kopf des Platzes (Avatar, Name) ebenso; als Listenzeile nur deren linker Teil (rechts davon ist Platz für Effekte)
	var own: Rect2 = head_of(seat).rect
	if _list_mode(seat):
		own.size.x *= 0.35
	soft.append(own)
	var w: Node2D = table.get("_world")
	var half := Vector2(table.pile_w, table.pile_w * CardView.ASPECT) * 0.5
	for p: Vector2 in [table.draw_pile_position(), table.discard_position()]:
		hard.append(_rect_of(table._table_to(layer, w.transform * (p - half)), table._table_to(layer, w.transform * (p + half))))
	var hr := table.hand_rect(_screen())
	hard.append(_rect_of(table._table_to(layer, hr.position + Vector2(0, 40)), table._table_to(layer, hr.end)))
	if avoid_cb.is_valid():
		for g in avoid_cb.call():
			hard.append(_g2l_rect(g as Rect2))
	for b in [table.get("_sort_btn"), table.get("_backs_btn")]:
		if b is Control and (b as Control).is_visible_in_tree():
			hard.append(_g2l_rect((b as Control).get_global_rect()))
	return {"hard": hard, "soft": soft}


# Beste Lage aus cands [{pos, rel}] (rel = Umriss relativ zu pos): jede auch ins Bild geschoben; Kosten nach Reihenfolge, Verschiebung,
# Fläche außerhalb des Bildes und Überdeckung (hart × 12, weich × 2). Gibt die gewählte Lage mit dem endgültigen pos zurück.
func _choose(cands: Array, blk: Dictionary) -> Dictionary:
	var sz := _screen()
	var bounds := Rect2(Vector2(6, 6), sz - Vector2(12, 12))
	var best := {}
	var best_cost := INF
	for i in cands.size():
		var c: Dictionary = cands[i]
		var p0: Vector2 = c.pos
		var rel: Rect2 = c.rel
		var r0 := Rect2(p0 + rel.position, rel.size)
		var sh := Vector2.ZERO
		if r0.position.x < bounds.position.x:
			sh.x = bounds.position.x - r0.position.x
		elif r0.end.x > bounds.end.x:
			sh.x = bounds.end.x - r0.end.x
		if r0.position.y < bounds.position.y:
			sh.y = bounds.position.y - r0.position.y
		elif r0.end.y > bounds.end.y:
			sh.y = bounds.end.y - r0.end.y
		for p: Vector2 in [p0, p0 + sh]:
			var r := Rect2(p + rel.position, rel.size)
			var cost := i * 2500.0 + (p - p0).length() * 20.0
			var inside := r.intersection(bounds).get_area() if r.intersects(bounds) else 0.0
			cost += (r.get_area() - inside) * 30.0
			for b: Rect2 in blk.hard:
				if r.intersects(b):
					cost += r.intersection(b).get_area() * 12.0
			for b: Rect2 in blk.soft:
				if r.intersects(b):
					cost += r.intersection(b).get_area() * 2.0
			if cost < best_cost:
				best_cost = cost
				best = c.duplicate()
				best["pos"] = p
	return best


# Schnarchen (Beta 1.6.3, doppelt so groß): Mütze auf dem Avatar (oben am Bildrand kleiner), die „Z“-Wolke nach _choose schräg links
# über der Mütze, rechts neben dem Kopf (steigt nach rechts), links neben dem Avatar oder im großen Modus in der Zeile.
func _place_snore(fx: SnoreFx, seat: int) -> void:
	var r := fx.r
	var c := fx.position
	var lst := _list_mode(seat)
	fx.kz = k() * (0.8 if lst else 1.0)
	fx.cap_at = Vector2(-r * 0.3, -r * 1.02)
	fx.cap_s = r * (1.5 if lst else 1.9)
	# Bommel ≈ 1,25 · cap_s über der Krempe: am oberen Rand kleiner, damit die Mütze ganz im Bild bleibt
	fx.cap_s = clampf((c.y + fx.cap_at.y - 6.0) / 1.25, r * 0.9, fx.cap_s)
	var kz := fx.kz
	var hd := head_of(seat)
	var hr: Rect2 = hd.rect
	var cands: Array = []
	var add := func(zo: Vector2, zdir: float) -> void:
		cands.append({"pos": c, "zo": zo, "zdir": zdir, "rel": SnoreFx.cloud_rect(zo, zdir, kz)})
	if lst:
		add.call(Vector2(float(hd.count_x) - c.x - 40.0 * kz, hr.end.y - c.y - 6.0), -1.0)
	add.call(Vector2(-r * 1.15 - 40.0 * kz, -r * 0.55), -1.0)
	add.call(Vector2(hr.end.x - c.x + 10.0, r * 0.6), 1.0)
	add.call(Vector2(-r - 46.0 * kz, r * 1.2), -1.0)
	var best := _choose(cands, _blockers(seat))
	var shift: Vector2 = Vector2(best.pos) - c
	fx.zo = Vector2(best.zo) + shift
	fx.zdir = float(best.zdir)


# ================================================================= Bedienung: Menü am Gegner, Reaktionsknopf

func caps() -> Dictionary:
	if source == null or not enabled:
		return {"kinds": [], "bots_only": false}
	return source.fx_caps()


# Kann der Kopf dieses Platzes das Necken-Menü öffnen? (sonst wirkt der Tipp wie bisher)
func can_open(seat: int) -> bool:
	if table == null or source == null or not enabled or seat < 0 or seat == _me() or _me() < 0:
		return false
	var c := caps()
	var kinds: Array = c.get("kinds", [])
	kinds = kinds.filter(func(x: String) -> bool: return x != "react")
	if kinds.is_empty():
		return false
	if bool(c.get("bots_only", false)) and not _is_bot(seat):
		return false
	return table.seat_node(seat) != null


# Einträge des Menüs für einen Platz: [{key, label, on, progress}] und ein Hinweis darunter.
func menu_items(seat: int) -> Dictionary:
	var items: Array = []
	var note := ""
	var c := caps()
	var kinds: Array = c.get("kinds", [])
	var node := table.seat_node(seat)
	var off := source != null and source.fx_off_seats().has(seat)
	if off:
		note = I18n.t("%s möchte gerade nicht geneckt werden.") % _name(seat)
	else:
		if kinds.has("ball"):
			items.append(_item("ball", I18n.t("Papierkugel"), {"k": "ball", "to": seat}))
		if not _is_bot(seat) and seat == _current_turn():
			for kk in ["snore", "alarm"]:
				if kinds.has(kk):
					var it := _item(kk, I18n.t("Schnarchen") if kk == "snore" else I18n.t("Wecker"), {"k": kk, "to": seat})
					var left := source.fx_slow_left_ms(seat) if source != null else -1
					it["progress"] = 1.0 - float(left) / float(TeaseRules.FX_SLOW_MS) if left >= 0 else 0.0
					if str(it.get("why", "")) == "early":
						note = I18n.t("Erst, wenn %s eine Weile überlegt.") % _name(seat)
					items.append(it)
	if node != null and node.backs_visible():
		items.append({"key": "backs", "label": I18n.t("Karten ansehen"), "on": true, "progress": 1.0})
	return {"items": items, "note": note}


func _item(key: String, label: String, req: Dictionary) -> Dictionary:
	var why := source.fx_check(req) if source != null else "mode"
	var on := why == "" and not rate_limited()
	return {"key": key, "label": label, "on": on, "why": why, "progress": 1.0}


func menu_title(seat: int) -> String:
	var n := table.seat_node(seat).count() if table.seat_node(seat) != null else 0
	var cards := (I18n.t("%d Karte") if n == 1 else I18n.t("%d Karten")) % n
	return I18n.t("%s · %s") % [_name(seat), cards]


func open_menu(seat: int) -> bool:
	if not can_open(seat):
		return false
	if seat == _closed_seat and int(now * 1000.0) - _closed_ms < REOPEN_GAP_MS:
		return true                           # der Tipp hat das offene Menü dieses Platzes gerade geschlossen
	close_menu(false)
	if picker != null:
		picker.open = false
	menu = TeaseMenu.new()
	menu.name = "NeckenMenue"
	menu.seat = seat
	menu.night = night
	menu.k = k()
	menu.title = menu_title(seat)
	var d := menu_items(seat)
	menu.items = d.items
	menu.note = str(d.note)
	menu.chosen.connect(_on_menu_chosen)
	menu.closed.connect(_on_menu_closed)
	var ov: Control = table.get("_overlay")
	ov.add_child(menu)
	ov.move_child(menu, table.backs_viewer.get_index())
	menu.relayout()
	place_menu()
	return true


func close_menu(remember := false) -> void:
	if menu == null:
		return
	var m := menu
	menu = null
	if remember:
		_closed_seat = m.seat
		_closed_ms = int(now * 1000.0)
	if is_instance_valid(m):
		if m.closed.is_connected(_on_menu_closed):
			m.closed.disconnect(_on_menu_closed)
		m.queue_free()


func _on_menu_closed() -> void:
	close_menu(true)


func _refresh_menu() -> void:
	if menu == null:
		return
	if table.seat_node(menu.seat) == null or not can_open(menu.seat):
		close_menu()
		return
	var d := menu_items(menu.seat)
	menu.title = menu_title(menu.seat)
	menu.set_items(d.items, str(d.note))
	if menu.size_changed:
		place_menu()


func _on_menu_chosen(key: String) -> void:
	if menu == null:
		return
	var seat := menu.seat
	if key == "backs":
		var node := table.seat_node(seat)
		close_menu(false)
		if node != null and node.backs_visible():
			table.backs_viewer.show_backs(node.player_name(), node.keys)
		return
	var kk: String = {"ball": "ball", "snore": "snore", "alarm": "alarm"}.get(key, "")
	if kk == "":
		return
	send({"k": kk, "to": seat})
	close_menu(false)


# Wunsch abschicken (Knöpfe sofort mit kleiner Drückrückmeldung; der Effekt kommt erst mit dem fx des Gastgebers).
func send(req: Dictionary) -> void:
	if not enabled:
		return
	_last_target = int(req.get("to", -1)) if req.get("to") is int else -1
	UiApp.vibrate(15, 0.3)
	send_requested.emit(req)


# Menü am Avatar platzieren: rechts neben Name und Kartenzahl, links, links neben dem „Erwischt!“-Feld (großer Modus), darunter oder
# darüber – jeweils in den Bildschirm geklemmt. Gemieden werden das „Erwischt!“-Feld des Ziels und jedes gerade erwischbaren Platzes
# (das Menü schließt sich ohnehin, sobald jemand erwischbar wird), die Knöpfe oben links (avoid_cb, TableScreen), der Mau-Knopf und
# möglichst der Kopf des Ziels.
func place_menu() -> void:
	if menu == null:
		return
	var node := table.seat_node(menu.seat)
	if node == null:
		return
	var sz := _screen()
	var par: CanvasItem = menu.get_parent()
	var to_m := func(g: Vector2) -> Vector2: return table._table_to(par, table.get_global_transform().affine_inverse() * g)
	var a: Vector2 = to_m.call(node.avatar_global())
	var r := node.avatar_radius()
	var head_end: Vector2 = to_m.call(node.to_global(Vector2(node.list_rect().end.x if node.list_mode else (node.header_width() * 0.5), 0.0)))
	var head := Rect2(a - Vector2(r, r), Vector2(maxf(head_end.x - a.x + r, 2.0 * r), 2.0 * r)).grow(6.0)
	var rc := catch_rect_of(menu.seat, par)
	var hard: Array[Rect2] = [rc]
	for s in table.get("_seats"):
		var sn: OpponentSeat = table.seat_node(int(s))
		if sn != null and sn.catchable and int(s) != menu.seat:
			hard.append(catch_rect_of(int(s), par))
	if avoid_cb.is_valid():
		for g in avoid_cb.call():
			hard.append(g as Rect2)
	if table.mau_button.visible:
		hard.append(table.mau_button.get_global_rect())
	var s := menu.size
	var gap := 16.0 * k()
	var bounds := Rect2(Vector2(8, 8), sz - Vector2(16, 16))
	# weich gemieden: die Köpfe (bzw. Listenzeilen) der anderen Mitspieler
	var soft: Array[Rect2] = [head]
	for st in table.get("_seats"):
		var sn: OpponentSeat = table.seat_node(int(st))
		if sn == null or int(st) == menu.seat or not sn.is_visible_in_tree() or sn.modulate.a < 0.5:
			continue
		var p0: Vector2 = to_m.call(sn.to_global(sn.list_rect().position if sn.list_mode else Vector2(-sn.header_width() * 0.5 - 4.0, -sn.avatar_radius() - 4.0)))
		var p1: Vector2 = to_m.call(sn.to_global(sn.list_rect().end if sn.list_mode else Vector2(sn.header_width() * 0.5 + 4.0, sn.avatar_radius() + 24.0)))
		soft.append(Rect2(p0, Vector2.ZERO).expand(p1))
	var base: Array[Vector2] = [
		Vector2(head.end.x + gap, a.y - s.y * 0.5),
		Vector2(a.x - r - gap - s.x, a.y - s.y * 0.5),
		Vector2(minf(rc.position.x, a.x - r) - gap - s.x, a.y - s.y * 0.5),
		Vector2(a.x - s.x * 0.5, maxf(a.y + r, rc.end.y) + gap),
		Vector2(a.x - s.x * 0.5, a.y - r - gap - s.y),
	]
	var clamp_c := func(c: Vector2) -> Vector2:
		return Vector2(clampf(c.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - s.x)),
			clampf(c.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - s.y)))
	var cost_of := func(c: Vector2, i: int) -> float:
		var rect := Rect2(c, s)
		var cost := float(i) * 400.0
		for b in hard:
			if rect.intersects(b):
				cost += rect.intersection(b).get_area() * 40.0
		for b in soft:
			if rect.intersects(b):
				cost += rect.intersection(b).get_area() * 4.0
		return cost
	var best := Vector2.INF
	var best_cost := INF
	for i in base.size():
		# jede Lage auch an harten Hindernissen vorbeigeschoben (z. B. rechts neben die Knöpfe oben links)
		var tries: Array[Vector2] = [clamp_c.call(base[i])]
		for b in hard:
			var c0: Vector2 = tries[0]
			if Rect2(c0, s).intersects(b):
				tries.append(clamp_c.call(Vector2(b.end.x + 6.0, c0.y)))
				tries.append(clamp_c.call(Vector2(b.position.x - s.x - 6.0, c0.y)))
				tries.append(clamp_c.call(Vector2(c0.x, b.end.y + 6.0)))
				tries.append(clamp_c.call(Vector2(c0.x, b.position.y - s.y - 6.0)))
		for c in tries:
			var cost: float = cost_of.call(c, i)
			if cost < best_cost:
				best_cost = cost
				best = c
	menu.position = best
	# Zipfel zum nächsten Punkt des Kopfs (Avatar, Name, Kartenzahl), nicht quer über den Namen
	var mc := Rect2(best, s).get_center()
	var hp := Vector2(clampf(mc.x, head.position.x, head.end.x), clampf(mc.y, head.position.y, head.end.y))
	menu.tail_to = hp - best
	menu.tail_r = 2.0
	menu.queue_redraw()


# „Erwischt!“-Feld eines Platzes in Koordinaten von node (auch wenn er gerade nicht erwischbar ist)
func catch_rect_of(seat: int, node: CanvasItem) -> Rect2:
	var sn := table.seat_node(seat)
	if sn == null:
		return Rect2()
	var inv := table.get_global_transform().affine_inverse()
	var cr: Rect2 = sn._catch_rect().grow(18.0)
	var p0: Vector2 = table._table_to(node, inv * sn.to_global(cr.position))
	var p1: Vector2 = table._table_to(node, inv * sn.to_global(cr.end))
	return Rect2(p0, Vector2.ZERO).expand(p1)


# Tipp auf den Kopf (Avatar, Name, Kartenzahl) eines Gegners: true = Menü offen (verbraucht)
func tap_head(seat: int) -> bool:
	return open_menu(seat)


# Tipp auf den eigenen Platz: Reaktionsfächer auf/zu. true = verbraucht.
func tap_me() -> bool:
	if picker == null or not picker.visible:
		return false
	if not picker.open and int(now * 1000.0) - _picker_closed_ms < REOPEN_GAP_MS:
		return true                           # Beta 1.6.3: derselbe Tipp hat den Fächer gerade geschlossen (ReactionPicker._input)
	picker.toggle()
	return true


func _on_picker_dismissed() -> void:
	_picker_closed_ms = int(now * 1000.0)


func _on_react_chosen(r: String) -> void:
	if picker.gray:
		return
	send({"k": "react", "r": r})


# Reaktionsknopf: nur mit Reaktionen in dieser Spielart, eigenem Platz und Necken an; Lage am Namensschild bzw. in der Zeile „Du“.
# Beta 1.6.3: full = auch die Regeln neu prüfen (caps, fx_check); sonst nur Lage und Uhr (jedes Bild), gezeichnet nur bei Änderung.
func _sync_picker(full := true) -> void:
	if picker == null or table == null:
		return
	if full:
		var kinds: Array = caps().get("kinds", [])
		_react_cap = kinds.has("react")
		_react_why = source.fx_check({"k": "react", "r": "lachen"}) if source != null and _react_cap else "mode"
	var badge := table.me_badge
	var show := enabled and _react_cap and _me() >= 0 and badge.visible and badge.modulate.a > 0.5 \
		and not table.handover.visible and not covered()
	if show != picker.visible:
		picker.visible = show
		_picker_key = ""
		if not show:
			picker.open = false
	if not show:
		return
	picker.k = k()
	picker.night = night
	picker.big = big
	picker.reduced = reduced
	var inv := table.get_global_transform().affine_inverse()
	var r := TeaseMenu.ReactionPicker.BTN_R * k()
	var g: Vector2
	if badge.list_mode:
		g = badge.to_global(Vector2(-badge.row_size.x * 0.5 - 12.0 - r, 0.0))
	else:
		g = badge.to_global(Vector2(badge.header_width() + 14.0 + r, 0.0))
	picker.center = table._table_to(picker, inv * g)
	picker.gray = _react_why != "" or rate_limited()
	picker.dim = rate_limited()
	var key := "%s|%s|%s|%s|%s|%s|%s" % [picker.center.round(), picker.gray, picker.dim, picker.open, picker.k, picker.night, picker.big]
	if key != _picker_key:
		_picker_key = key
		picker.queue_redraw()


# Gerätetest 1.6.3: Liegt etwas Modales über dem Tisch, verschwindet der Reaktionsknopf samt Fächer. Er hängt hinter dem Rundenende
# in den Overlays, also über Farbrad, Rückseiten-Großansicht und Kartenhilfe; Rückfragen und Menüs von TableScreen über modal_cb.
func covered() -> bool:
	if table == null:
		return false
	if table.wish_picker.is_open() or table.backs_viewer.visible or table.help_popup.visible:
		return true
	return modal_cb.is_valid() and bool(modal_cb.call())


# Flächen für die Sofort-Leiste (TableScreen.bar_obstacles, Bildschirmkoordinaten): Reaktionsknopf (offen samt Fächer) und Menü
func obstacles() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if picker != null and picker.visible:
		out.append(Rect2(picker.get_global_transform_with_canvas() * picker.bounds().position, picker.bounds().size))
	if menu != null and is_instance_valid(menu):
		out.append(Rect2(menu.get_global_transform_with_canvas() * Vector2.ZERO, menu.size))
	return out


# ================================================================= Töne und Vibration

func _play(sound_name: String, quiet: bool) -> bool:
	var db := AppSound.QUIET_DB if quiet else 0.0
	sounds.append([sound_name, db])
	if sound != null:
		return bool(sound.call("play", sound_name, db))
	return UiApp.sound_db(sound_name, db)


func _fade(sound_name: String) -> void:
	fades.append(sound_name)
	if sound != null and sound.has_method("fade_out"):
		sound.call("fade_out", sound_name, 300)
	elif sound == null:
		UiApp.fade_sound(sound_name, 300)


func _vibrate(ms: int) -> void:
	vibrations.append(ms)
	if vibrate_cb.is_valid():
		vibrate_cb.call(ms)
	else:
		UiApp.vibrate(ms, 0.6)


# ================================================================= Gezeichnete Bilder (keine Emoji-Schrift in der App)

const INK := Color("#211B2C")
const SKIN := Color("#F2C48D")
const FACE := Color("#FFD65A")
const TEAR := Color("#8FD3FF")
const CLOCK := Color("#E5484D")
const CAP := Color("#7B6BE0")


static func _ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color, rot := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in 28:
		var a := TAU * i / 28.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	ci.draw_colored_polygon(pts, col)


static func _face(ci: CanvasItem, c: Vector2, s: float, fill: Color) -> void:
	ci.draw_circle(c, s + maxf(2.0, s * 0.09), INK)
	ci.draw_circle(c, s, fill)


# Bild kind (ball, snore, alarm, backs, lachen, schreck, klatschen, daumen, smile) mit Mitte c und Größe s (≈ Radius).
# t = Zeit für kleine Bewegungen (Zeiger, Klatschen).
static func draw_icon(ci: CanvasItem, kind: String, c: Vector2, s: float, t := 0.0, seed_v := 3) -> void:
	var lw := maxf(1.5, s * 0.09)
	match kind:
		"ball":
			var pts := PackedVector2Array()
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_v
			# zerknülltes Papier: zackiger Umriss, schattierte Facetten, kurze Knickfalten (keine Linien durch die Mitte)
			var n := 14
			for i in n:
				var a := TAU * i / float(n)
				pts.append(c + Vector2(cos(a), sin(a)) * s * (rng.randf_range(0.84, 1.0) if i % 2 == 0 else rng.randf_range(0.7, 0.86)))
			var outline := pts.duplicate()
			outline.append(pts[0])
			ci.draw_colored_polygon(pts, UiPalette.CREAM)
			for f in 3:                                   # Schattenfacetten unten rechts
				var i0 := 3 + f * 2
				ci.draw_colored_polygon(PackedVector2Array([c + (pts[i0] - c) * 0.35, pts[i0], pts[(i0 + 1) % n], pts[(i0 + 2) % n]]),
					Color(UiPalette.PAPER_D, 0.9 - f * 0.15))
			ci.draw_polyline(outline, INK, lw * 1.3, true)
			for i in 5:
				var a := TAU * (i / 5.0) + rng.randf_range(-0.3, 0.3)
				var p0 := c + Vector2(cos(a), sin(a)) * s * 0.3
				var p1 := c + Vector2(cos(a + 0.35), sin(a + 0.35)) * s * 0.55
				var p2 := c + Vector2(cos(a + 0.1), sin(a + 0.1)) * s * 0.78
				ci.draw_polyline(PackedVector2Array([p0, p1, p2]), Color(INK, 0.5), lw * 0.75, true)
		"snore":
			draw_cap(ci, c + Vector2(-s * 0.15, s * 0.25), s * 0.95, -0.25)
			var f := UiFonts.title(800, true, 100.0)
			ci.draw_string_outline(f, c + Vector2(s * 0.25, -s * 0.15), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(s * 0.7), int(lw * 2.0), UiPalette.CREAM)
			ci.draw_string(f, c + Vector2(s * 0.25, -s * 0.15), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(s * 0.7), INK)
			ci.draw_string_outline(f, c + Vector2(s * 0.5, -s * 0.5), "Z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(s * 0.9), int(lw * 2.0), UiPalette.CREAM)
			ci.draw_string(f, c + Vector2(s * 0.5, -s * 0.5), "Z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(s * 0.9), INK)
		"alarm":
			draw_clock(ci, c, s, t * TAU / 3.0, 0.0)
		"backs":
			for i in 2:
				var off := Vector2((i - 0.5) * s * 0.55, (0.5 - i) * s * 0.12)
				var rect := Rect2(c + off - Vector2(s * 0.42, s * 0.62), Vector2(s * 0.84, s * 1.24))
				var sb := StyleBoxFlat.new()
				sb.bg_color = UiPalette.NIGHT_HI
				sb.border_color = UiPalette.CREAM
				sb.set_border_width_all(int(maxf(2.0, lw)))
				sb.set_corner_radius_all(int(s * 0.14))
				sb.anti_aliasing = true
				ci.draw_style_box(sb, rect)
				ci.draw_circle(rect.get_center(), s * 0.16, UiPalette.RING)
		"lachen", "smile":
			_face(ci, c, s, FACE)
			# lachende, zugekniffene Augen
			for side in [-1.0, 1.0]:
				var e := c + Vector2(side * s * 0.36, -s * 0.22)
				ci.draw_polyline(PackedVector2Array([e + Vector2(-s * 0.17, s * 0.06), e + Vector2(0, -s * 0.1), e + Vector2(s * 0.17, s * 0.06)]), INK, lw * 1.3, true)
			# offener Mund
			var mouth := PackedVector2Array()
			for i in 17:
				var a := PI * i / 16.0
				mouth.append(c + Vector2(cos(a) * s * 0.52, s * 0.08 + sin(a) * s * (0.5 if kind == "lachen" else 0.38)))
			ci.draw_colored_polygon(mouth, INK)
			if kind == "lachen":
				_ellipse(ci, c + Vector2(0, s * 0.42), s * 0.22, s * 0.12, Color("#F27C8F"))
				for side in [-1.0, 1.0]:
					var tc := c + Vector2(side * s * 0.78, -s * 0.02 + fmod(t * 1.5, 1.0) * s * 0.25)
					_ellipse(ci, tc, s * 0.13, s * 0.2, TEAR)
					ci.draw_circle(tc + Vector2(0, -s * 0.15), s * 0.07, TEAR)
		"schreck":
			_face(ci, c, s, Color("#FFE7A3"))
			_ellipse(ci, c + Vector2(0, -s * 0.55), s * 0.75, s * 0.32, Color("#A8C6FF", 0.75))
			for side in [-1.0, 1.0]:
				var e := c + Vector2(side * s * 0.33, -s * 0.18)
				_ellipse(ci, e, s * 0.17, s * 0.22, Color.WHITE)
				ci.draw_circle(e, s * 0.17 + lw * 0.4, Color(INK, 0.0))
				ci.draw_arc(e, s * 0.2, 0, TAU, 20, INK, lw, true)
				ci.draw_circle(e + Vector2(0, s * 0.03), s * 0.07, INK)
			_ellipse(ci, c + Vector2(0, s * 0.38), s * 0.16, s * 0.24, INK)
			for side in [-1.0, 1.0]:      # Hände an den Wangen
				var hc := c + Vector2(side * s * 0.92, s * 0.32)
				_ellipse(ci, hc, s * 0.25 + lw, s * 0.36 + lw, INK, side * 0.3)
				_ellipse(ci, hc, s * 0.25, s * 0.36, SKIN, side * 0.3)
		"klatschen":
			var cyc := 0.5 + 0.5 * cos(t * 3.0 * TAU)
			var d := s * (0.28 + 0.3 * cyc)
			for side in [-1.0, 1.0]:
				var hc := c + Vector2(side * d, s * 0.1)
				_ellipse(ci, hc, s * 0.36 + lw, s * 0.55 + lw, INK, -side * 0.32)
				_ellipse(ci, hc, s * 0.36, s * 0.55, SKIN, -side * 0.32)
				for i in 3:
					var x := (i - 1) * s * 0.17
					var base := hc + Vector2(x, -s * 0.2).rotated(-side * 0.32)
					var top := hc + Vector2(x * 1.1, -s * 0.78).rotated(-side * 0.32)
					ci.draw_line(base, top, INK, s * 0.2, true)
					ci.draw_line(base, top, SKIN, s * 0.12, true)
			if cyc < 0.3:
				for i in 5:
					var a := -PI * 0.5 + (i - 2) * 0.45
					var dir := Vector2(cos(a), sin(a))
					ci.draw_line(c + dir * s * 0.95, c + dir * s * 1.25, UiPalette.TURN, lw * 1.2, true)
		"daumen":
			# Faust mit Daumen nach oben, Ärmel
			var fist := Rect2(c + Vector2(-s * 0.72, -s * 0.12), Vector2(s * 1.22, s * 0.98))
			var sb := StyleBoxFlat.new()
			sb.bg_color = SKIN
			sb.border_color = INK
			sb.set_border_width_all(int(maxf(2.0, lw)))
			sb.set_corner_radius_all(int(s * 0.3))
			sb.anti_aliasing = true
			ci.draw_style_box(sb, fist)
			for i in 3:
				var y := fist.position.y + s * (0.26 + i * 0.25)
				ci.draw_line(Vector2(fist.position.x + s * 0.12, y), Vector2(fist.end.x - s * 0.2, y), Color(INK, 0.6), lw * 0.8, true)
			var th0 := c + Vector2(-s * 0.36, -s * 0.02)
			var th1 := c + Vector2(-s * 0.3, -s * 0.92)
			ci.draw_line(th0, th1, INK, s * 0.62, true)
			ci.draw_circle(th1, s * 0.31, INK)
			ci.draw_line(th0, th1, SKIN, s * 0.46, true)
			ci.draw_circle(th1, s * 0.23, SKIN)
			ci.draw_line(th1 + Vector2(s * 0.08, -s * 0.05), th1 + Vector2(s * 0.08, s * 0.25), Color(INK, 0.45), lw * 0.7, true)
			var cuff := Rect2(Vector2(fist.end.x - s * 0.1, fist.position.y + s * 0.04), Vector2(s * 0.42, s * 0.9))
			sb = sb.duplicate()
			sb.bg_color = Color("#3F74F2")
			sb.set_corner_radius_all(int(s * 0.1))
			ci.draw_style_box(sb, cuff)


# Schlafmütze (Spitze nach rechts oben, Bommel)
static func draw_cap(ci: CanvasItem, c: Vector2, s: float, rot := -0.2) -> void:
	var lw := maxf(1.5, s * 0.08)
	var xf := Transform2D(rot, c)
	var body := PackedVector2Array([Vector2(-s * 0.7, 0), Vector2(s * 0.7, 0), Vector2(s * 0.95, -s * 0.95), Vector2(s * 0.2, -s * 0.75)])
	var pts := PackedVector2Array()
	for p in body:
		pts.append(xf * p)
	var outline := pts.duplicate()
	outline.append(pts[0])
	ci.draw_colored_polygon(pts, CAP)
	ci.draw_polyline(outline, INK, lw, true)
	for i in 2:   # Streifen
		var u := 0.35 + i * 0.3
		ci.draw_line(xf * Vector2(lerpf(-s * 0.7, s * 0.2, u), -s * 0.75 * u), xf * Vector2(lerpf(s * 0.7, s * 0.95, u), -s * 0.95 * u), Color(UiPalette.CREAM, 0.8), lw * 1.4, true)
	var brim := Rect2(Vector2(-s * 0.8, -s * 0.12), Vector2(s * 1.6, s * 0.3))
	var bp := PackedVector2Array([xf * brim.position, xf * Vector2(brim.end.x, brim.position.y), xf * brim.end, xf * Vector2(brim.position.x, brim.end.y)])
	ci.draw_colored_polygon(bp, UiPalette.CREAM)
	bp.append(bp[0])
	ci.draw_polyline(bp, INK, lw, true)
	ci.draw_circle(xf * Vector2(s * 0.95, -s * 0.95), s * 0.2 + lw, INK)
	ci.draw_circle(xf * Vector2(s * 0.95, -s * 0.95), s * 0.2, UiPalette.CREAM)


# Wecker: roter Körper, zwei Glocken mit Hammer, Zifferblatt; hand = Winkel des Minutenzeigers
static func draw_clock(ci: CanvasItem, c: Vector2, s: float, hand: float, wobble: float) -> void:
	var lw := maxf(1.5, s * 0.08)
	var xf := Transform2D(wobble, c)
	for side in [-1.0, 1.0]:
		var leg0: Vector2 = xf * Vector2(side * s * 0.5, s * 0.75)
		var leg1: Vector2 = xf * Vector2(side * s * 0.72, s * 1.02)
		ci.draw_line(leg0, leg1, INK, lw * 1.6, true)
		var bell: Vector2 = xf * Vector2(side * s * 0.62, -s * 0.78)
		ci.draw_circle(bell, s * 0.34 + lw, INK)
		ci.draw_circle(bell, s * 0.34, Color("#FFD65A"))
	ci.draw_line(xf * Vector2(0, -s * 0.85), xf * Vector2(0, -s * 1.12), INK, lw * 1.4, true)
	ci.draw_circle(xf * Vector2(0, -s * 1.15), s * 0.1, INK)
	ci.draw_circle(c, s * 0.92 + lw, INK)
	ci.draw_circle(c, s * 0.92, CLOCK)
	ci.draw_circle(c, s * 0.72, UiPalette.CREAM)
	for i in 12:
		var a := TAU * i / 12.0 + wobble
		var d := Vector2(cos(a), sin(a))
		ci.draw_line(c + d * s * 0.6, c + d * s * (0.68 if i % 3 != 0 else 0.7), INK, lw * (0.7 if i % 3 != 0 else 1.1), true)
	var hh := Vector2(cos(hand / 12.0 - PI * 0.5 + wobble), sin(hand / 12.0 - PI * 0.5 + wobble)) * s * 0.36
	var mh := Vector2(cos(hand - PI * 0.5 + wobble), sin(hand - PI * 0.5 + wobble)) * s * 0.55
	ci.draw_line(c, c + hh, INK, lw * 1.4, true)
	ci.draw_line(c, c + mh, INK, lw, true)
	ci.draw_circle(c, lw * 1.2, INK)


# ================================================================= Effekte (ohne eigenes _process: TeaseFx.tick treibt sie)

class TeaseEffect:
	extends Node2D
	var kind := ""
	var seat := -1
	var k := 1.0
	var night := 0.0
	var reduced := false
	var t := 0.0

	# false = fertig (wird entfernt)
	func step(delta: float) -> bool:
		t += delta
		queue_redraw()
		return true


class SnoreFx:
	extends TeaseEffect
	var target := -1
	var r := 27.0
	var loud := false
	var quiet := false
	var ending := false
	var cap_at := Vector2.INF     # Beta 1.6.3: Lage und Größe der Mütze, Ursprung zo und Richtung zdir der „Z“-Wolke (TeaseFx._place_snore)
	var cap_s := 0.0
	var zo := Vector2.INF
	var zdir := -1.0
	var kz := 1.0
	var _end_t := -1.0

	# Buchstabe i der Wolke beim Aufstieg rise (0 … 1): Grundlinie links relativ zu zo, Schriftgröße
	static func letter(i: int, rise: float, zdir_: float, kz_: float) -> Array:
		return [Vector2(zdir_ * (i * 34.0 + 34.0 * rise) * kz_, -(i * 44.0 + 50.0 * rise) * kz_), int((60 + i * 20) * kz_)]

	# Umriss der Wolke relativ zum Avatar (oben blenden die Buchstaben schon aus: nicht ganz bis zur Spitze)
	static func cloud_rect(zo_: Vector2, zdir_: float, kz_: float) -> Rect2:
		if zdir_ < 0.0:
			return Rect2(zo_ + Vector2(-102.0 * kz_, -170.0 * kz_), Vector2(140.0 * kz_, 170.0 * kz_))
		return Rect2(zo_ + Vector2(0.0, -170.0 * kz_), Vector2(164.0 * kz_, 170.0 * kz_))

	func end_soon() -> void:
		ending = true
		_end_t = t

	func alpha() -> float:
		var a := clampf(t / 0.2, 0.0, 1.0)
		if ending:
			a *= clampf(1.0 - (t - _end_t) / 0.3, 0.0, 1.0)
		return minf(a, clampf((SNORE_S - t) / 0.4, 0.0, 1.0))

	func step(delta: float) -> bool:
		super.step(delta)
		if ending and t - _end_t >= 0.3:
			return false
		return t < SNORE_S

	func _draw() -> void:
		var a := alpha()
		modulate.a = a
		# Schlafmütze schräg auf dem Avatar (Beta 1.6.3: etwa doppelt so groß, Lage aus TeaseFx._place_snore)
		var ca := cap_at if cap_at.is_finite() else Vector2(-r * 0.3, -r * 1.02)
		TeaseFx.draw_cap(self, ca, cap_s if cap_s > 0.0 else r * 1.9, 0.18)
		# „Z z z“ in Wellen (alle 1,4 s drei Buchstaben), reduziert: stehen still und blenden
		var f := UiFonts.text(900, 100.0)
		var ink := UiPalette.MOON if night > 0.5 else UiPalette.INK
		var edge := Color(UiPalette.INK, 0.85) if night > 0.5 else Color(UiPalette.CREAM, 0.95)
		var o := zo if zo.is_finite() else Vector2(-r * 1.15 - 40.0 * kz, -r * 0.55)
		for w in 3:
			for i in 3:
				var start := w * 1.4 + i * 0.22
				var u := (t - start) / 1.3
				if u < 0.0 or u > 1.0:
					continue
				var la := clampf(minf(u / 0.15, (1.0 - u) / 0.3), 0.0, 1.0)
				var rise := 0.35 if reduced else u
				# steigen schräg nach links oben (rechts über dem Avatar steht die Denkblase), am Rand auch nach rechts
				var lt := letter(i, rise, zdir, kz)
				var p: Vector2 = o + Vector2(lt[0])
				var fs: int = lt[1]
				var txt := "Z"
				draw_string_outline(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(8 * kz), Color(edge, edge.a * la))
				draw_string(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(ink, la))


class AlarmFx:
	extends TeaseEffect
	var target := -1
	var loud := false
	var quiet := false
	var big_clock := false
	var state := "hop"            # hop | tick | ring | fall | done
	var sz := 0.0                 # Beta 1.6.3: Größe bei Mitspielern (TeaseFx._alarm); 0 = wie bisher
	var banner: TextFx            # Gerätetest 1.6.3: Zeile „… hat dir einen Wecker gestellt!“ (beim Abstellen ersetzt)
	var on_ring: Callable
	var _st := 0.0                # Beginn des Zustands
	var _fall_from := 0.0

	func defuse() -> void:
		if state == "hop" or state == "tick":
			state = "fall"
			_st = t
			_fall_from = rotation

	func size_s() -> float:
		if sz > 0.0:
			return sz
		return (34.0 if big_clock else 40.0) * k

	func step(delta: float) -> bool:
		super.step(delta)
		match state:
			"hop":
				if t >= ALARM_HOP_S:
					state = "tick"
					_st = t
			"tick":
				if t >= ALARM_HOP_S + ALARM_TICK_S:
					state = "ring"
					_st = t
					if on_ring.is_valid():
						on_ring.call()
			"ring":
				if t - _st >= ALARM_RING_S:
					state = "done"
					_st = t
			"fall":
				if t - _st >= 0.9:
					return false
			"done":
				if t - _st >= 0.3:
					return false
		return true

	func _draw() -> void:
		var s := size_s()
		var off := Vector2.ZERO
		var wob := 0.0
		var hand := 0.0
		var alpha := 1.0
		match state:
			"hop":
				var u := clampf(t / ALARM_HOP_S, 0.0, 1.0)
				off = Vector2(0, -sin(u * PI) * 18.0 * k)
				alpha = u
				scale = Vector2.ONE * lerpf(0.5, 1.0, u)
			"tick":
				var tt := t - _st
				scale = Vector2.ONE
				hand = tt * TAU / ALARM_TICK_S * 2.0
				var frac := fmod(tt, 1.0)
				if frac < 0.12 and not reduced:          # kleines Zucken je Sekunde
					off = Vector2(0, -4.0 * k * sin(frac / 0.12 * PI))
					wob = 0.06 * sin(frac / 0.12 * TAU)
			"ring":
				var tt := t - _st
				hand = ALARM_TICK_S * TAU / ALARM_TICK_S * 2.0
				if not reduced:
					wob = sin(tt * 42.0) * 0.22
					off = Vector2(sin(tt * 53.0) * 3.0 * k, -absf(sin(tt * 21.0)) * 5.0 * k)
				# Schwinglinien
				for side in [-1.0, 1.0]:
					for i in 3:
						var a: float = -PI * 0.5 + side * (0.55 + i * 0.32)
						var d := Vector2(cos(a), sin(a))
						var pulse := 0.5 + 0.5 * sin(tt * 30.0 + i)
						var col := Color(UiPalette.TURN if night > 0.5 else UiPalette.ALERT, 0.85)
						draw_line(d * s * (1.25 + 0.1 * pulse), d * s * (1.6 + 0.2 * pulse), col, maxf(2.0, s * 0.1), true)
			"fall":
				var u := clampf((t - _st) / 0.45, 0.0, 1.0)
				wob = _fall_from + u * u * (PI * 0.5)
				off = Vector2(u * s * 0.6, u * u * s * 0.6)
				alpha = clampf(1.0 - (t - _st - 0.5) / 0.4, 0.0, 1.0)
				hand = 0.0
			"done":
				alpha = clampf(1.0 - (t - _st) / 0.3, 0.0, 1.0)
		modulate.a = alpha
		TeaseFx.draw_clock(self, off, s, hand, wob)


class BallFx:
	extends TeaseEffect
	var target := -1
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var r_target := 27.0
	var seed_v := 1
	var rest := Vector2.INF        # Liegeplatz (TeaseFx setzt ihn links neben den Avatar)
	var slot := 0
	var on_hit: Callable
	var state := "fly"            # fly | bounce | lie | fade
	var _st := 0.0
	var _rest := Vector2.ZERO
	var _hit := false

	func _ready() -> void:
		position = Vector2.ZERO

	func skip_flight() -> void:
		t = BALL_FLY_S

	# Beta 1.6.3: im Flug BALL_FLY_R, beim Zurückspringen auf BALL_LIE_R
	func radius() -> float:
		match state:
			"fly":
				return BALL_FLY_R * k
			"bounce":
				return lerpf(BALL_FLY_R, BALL_LIE_R, clampf((t - _st) / 0.35, 0.0, 1.0)) * k
		return BALL_LIE_R * k

	func ball_pos() -> Vector2:
		match state:
			"fly":
				var u := clampf(t / BALL_FLY_S, 0.0, 1.0)
				# Bogen quer zur Wurfrichtung (nach oben bzw. bei steilen Würfen zur Seite)
				var d := to - from
				var n := d.orthogonal().normalized()
				if n.y > 0.0 or (absf(n.y) < 0.01 and n.x < 0.0):
					n = -n
				var peak := minf(d.length() * 0.28, 170.0) + 30.0
				return from.lerp(to, u) + n * sin(u * PI) * peak
			"bounce":
				var u := clampf((t - _st) / 0.35, 0.0, 1.0)
				return to.lerp(_rest, u) + Vector2(0, -sin(u * PI) * 26.0 * k)
		return _rest

	func step(delta: float) -> bool:
		super.step(delta)
		match state:
			"fly":
				if t >= BALL_FLY_S:
					state = "bounce"
					_st = t
					_rest = rest if rest.is_finite() else to + Vector2(-r_target - 16.0 * k, r_target * 0.6)
					if reduced:
						state = "lie"
						position = Vector2.ZERO
					if not _hit:
						_hit = true
						if on_hit.is_valid():
							on_hit.call()
			"bounce":
				if t - _st >= 0.35:
					state = "lie"
					_st = t
			"lie":
				if t - _st >= BALL_LIE_S:
					state = "fade"
					_st = t
			"fade":
				if t - _st >= 0.4:
					return false
		return true

	func _draw() -> void:
		var p := ball_pos()
		var spin := t * 9.0 if state == "fly" else 0.6
		var a := 1.0 if state != "fade" else clampf(1.0 - (t - _st) / 0.4, 0.0, 1.0)
		modulate.a = a
		draw_set_transform(p, spin, Vector2.ONE)
		TeaseFx.draw_icon(self, "ball", Vector2.ZERO, radius(), 0.0, seed_v)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class ReactFx:
	extends TeaseEffect
	var r_name := "lachen"
	var s := REACT_R              # Beta 1.6.3: Größe (TeaseFx._react setzt sie samt k) und Aufstieg
	var rise := REACT_RISE

	func step(delta: float) -> bool:
		super.step(delta)
		return t < REACT_S

	func _draw() -> void:
		var u := clampf(t / REACT_S, 0.0, 1.0)
		var a := clampf(minf(u / 0.1, (1.0 - u) / 0.3), 0.0, 1.0)
		modulate.a = a
		var off := Vector2.ZERO
		var sc := 1.0
		if not reduced:
			off = Vector2(sin(t * 5.0) * 7.0 * k, -rise * (1.0 - pow(1.0 - u, 2.0)))
			sc = 0.6 + 0.4 * minf(u / 0.12, 1.0) + 0.08 * sin(minf(u / 0.25, 1.0) * PI)
		TeaseFx.draw_icon(self, r_name, off, s * sc, t)


class TextFx:
	extends TeaseEffect
	var text := ""
	var color := Color.WHITE
	var size_px := 25
	var dur := 2.8
	var rise := 0.0

	func text_width() -> float:
		return UiFonts.text(800, 100.0).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x

	func step(delta: float) -> bool:
		super.step(delta)
		return t < dur

	func _draw() -> void:
		var f := UiFonts.text(800, 100.0)
		var u := clampf(t / dur, 0.0, 1.0)
		var a := clampf(minf(t / 0.15, (dur - t) / 0.4), 0.0, 1.0)
		var w := text_width()
		var p := Vector2(-w * 0.5, size_px * 0.34 - rise * u)
		var day := night < 0.5
		draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, maxi(5, size_px / 5), Color(UiPalette.CREAM if day else UiPalette.INK, 0.95 * a))
		draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(UiPalette.INK if day else color, a))
