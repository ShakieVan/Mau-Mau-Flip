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
#   Reaktion    😂 👏 👍 😱 (ab 1.6.5 feste Bilder aus Fluent Emoji, wie im Browser) steigen 1,6 s am Platz des Absenders auf; Ton
#               auf allen Geräten, je Gerät höchstens 2 gleichzeitig und je Name 600 ms Sperre (Jubel und Mau behalten ihre Stimmen).
#   Furzkissen  (Beta 1.6.6, eastereggs2.md 12.4) Menüzeile „Furzkissen“ mit „Mit Namen“/„Geheim“. Der Leger bekommt nur eine leise
#               Zeile „Kissen liegt bei Kim.“ (fx k "kissen", kein Bild, kein Ton). Beim Pups (k "kissen_pop", alle): Am Platz des
#               Ziels erscheint ein Kissen, wird plattgedrückt (der Avatar staucht sich), eine kleine Wolke steigt aus dem Ventil,
#               „Pfffrt!“; danach an derselben Stelle „Kim war's!“ bzw. „Wer war das?“ (geheim, auch beim Leger). Ton laut beim
#               Ziel, leise bei allen anderen (auch beim Leger: ein lauteres Handy verriete ihn), Vibration 150 ms beim Ziel. Beim Ziel
#               groß über dem eigenen Namensschild. Reduziert: kein Plattdrücken, Kissen und Wolke blenden ein und aus.
# Bedienung: Kopf eines Gegners → Necken-Menü (TeaseMenu), Fächer ohne sichtbare Rückseiten ebenso; die 4 Reaktionsknöpfe am eigenen
# Platz (TeaseMenu.ReactionBar, Beta 1.6.5: ein Tipp sendet, kein Fächer mehr). Beide zeigen nur, was nach TeaseRules mit der
# lokalen Uhr gerade geht (source.fx_check).
# Effekte reduziert: keine Flugbahn (Kugel erscheint am Ziel), kein Wackeln/Stauchen, Z stehen still, Reaktionen blenden am Platz.
# Spieltöne aus/leise gelten für alle Neck-Töne (AppSound), „Necken aus“ (Einstellung necken): nichts sehen, hören oder schicken.
# Der Tisch ruft: mount, attach(source), on_view, on_event, on_fx, on_refused, tap_head/tap_fan, set_enabled.
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
const MENU_IDLE_S := 15.0                  # Beta 1.6.7 (Nutzerwunsch 16.10.2026): vorher 5 s, das Menü verschwand zu früh
const RATE_GRAY_S := 1.2                   # fx_no "rate": Knöpfe kurz ausgegraut
const REOPEN_GAP_MS := 400                 # derselbe Kopf direkt nach dem Schließen: nicht gleich wieder öffnen
const SYNC_S := 0.15                       # Beta 1.6.3: Abstand der Regelprüfung in tick (Reaktionsknöpfe, Menüeinträge)
const REACT_GAP := 10.0                    # Beta 1.6.5: Abstand zwischen den Reaktionsknöpfen
const CUSHION_S := 2.6                     # Beta 1.6.6: Furzkissen sichtbar (Erscheinen, Plattdrücken, Wolke, Ausblenden)
const CUSHION_W := 50.0                    # halbe Kissenbreite an Mitspielern (× k), etwa wie der Wecker
const CUSHION_W_ME := 62.0                 # beim Ziel groß über dem eigenen Namensschild
const CUSHION_LINE_AT := 1.15              # „Kim war's!“/„Wer war das?“ ab hier (nach „Pfffrt!“) …
const CUSHION_LINE_S := 2.8                # … so lange
const CUSHION_VIBE_MS := 150

var table: TableView
var source: TableSource
var layer: Node2D                          # Effekte (über Ablage und Fächern, unter Farbwahl-Rad, Hilfe und Sichtschutz)
var menu: TeaseMenu                        # offenes Necken-Menü (oder null)
var reactions: TeaseMenu.ReactionBar      # Beta 1.6.5: die 4 Reaktionsknöpfe am eigenen Platz
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
var _later_q: Array = []                   # Beta 1.6.6: [{at, cb}] geplante Schritte (Zeile nach dem Pups)
var _rate_until := -1.0
var _last_target := -1                     # Ziel des letzten eigenen Wunschs (für „Zu spät – Kim …“)
var _turn := -1
var _closed_seat := -1
var _closed_ms := -100000
var _sync_left := 0.0                     # Beta 1.6.3: bis zur nächsten vollen Prüfung (Reaktionsknöpfe, Menü) in tick
var _react_cap := false                  # Beta 1.6.3: Reaktionen in dieser Spielart (caps), zuletzt geprüft
var _react_why := "mode"                  # Beta 1.6.3: zuletzt geprüfter Grund für Reaktionen (fx_check)
var _react_key := ""                      # zuletzt gezeichneter Stand der Reaktionsknöpfe
var _react_rel: Array[Vector2] = []       # Beta 1.6.5: gewählte Knopfmitten relativ zum Avatar (normaler Modus)


func _init() -> void:
	name = "Necken"


# Ebenen einhängen: Effekte direkt über fx_top, Menü unter der Rückseiten-Großansicht, Reaktionsknöpfe über dem Rundenende.
func mount(t: TableView) -> void:
	table = t
	t.add_child(self)
	var ov: Control = t.get("_overlay")
	layer = Node2D.new()
	layer.name = "NeckenEffekte"
	ov.add_child(layer)
	ov.move_child(layer, t.fx_top.get_index() + 1)
	reactions = TeaseMenu.ReactionBar.new()
	reactions.name = "Reaktionen"
	reactions.visible = false
	reactions.chosen.connect(_on_react_chosen)
	ov.add_child(reactions)
	ov.move_child(reactions, t.round_end.get_index() + 1)
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
	_sync_reactions()


func set_enabled(on: bool) -> void:
	enabled = on
	if source != null:
		source.set_fx_off(not on)
	if not on:
		close_menu()
		clear()
	_sync_reactions()


func set_night(v: float) -> void:
	night = v
	if menu != null:
		menu.night = v
		menu.queue_redraw()
	if reactions != null:
		reactions.night = v
		reactions.queue_redraw()


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
	if not _later_q.is_empty():
		var due: Array = []
		var keep: Array = []
		for e in _later_q:
			(due if now >= float(e.at) else keep).append(e)
		_later_q = keep
		for e in due:
			(e.cb as Callable).call()
	# Beta 1.6.3: Regeln (fx_check, Menüeinträge) nur alle SYNC_S neu prüfen; Sicht, fx, fx_no und fx_offs prüfen sofort.
	_sync_left -= delta
	var full := _sync_left <= 0.0
	if full:
		_sync_left = SYNC_S
	if menu != null:
		menu.idle += delta
		if menu.idle >= MENU_IDLE_S:
			close_menu()
		else:
			if full:
				_refresh_menu()
			_sync_menu_buzzers()
	_sync_reactions(full)


# ================================================================= Sicht und Ereignisse

func on_view(v: Dictionary) -> void:
	var phase := str(v.get("phase", ""))
	var turn: int = int(v.get("turn", -1)) if v.get("turn") is int or v.get("turn") is float else -1
	if not phase in TeaseRules.TURN_PHASES:
		turn = -1
	# Beta 1.6.7 (Nutzerwunsch 16.10.2026): Zugwechsel und erwischbare Plätze schließen das Menü nicht mehr („es wird einem unterm
	# Finger weggeklaut“). Beim Zugwechsel frischt es auf (Schnarchen/Wecker grau bzw. aktiv, ohne zu springen); ein „Erwischt!“-Buzzer
	# unter dem Menü bleibt sichtbar und drückbar (_sync_menu_buzzers). Nur das Rundenende (kein Zug mehr) schließt es.
	if turn != _turn:
		_turn = turn
		if turn < 0:
			close_menu()
		else:
			_refresh_menu()
	_sync_menu_buzzers()
	for e in effects():
		if (e is AlarmFx or e is SnoreFx) and e.target != turn:
			_wake_up(e)
	_sync_reactions()


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
	_later_q.clear()


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
		"kissen":                                 # TeaseRules.CUSHION
			_cushion_placed(from, to)
		"kissen_pop":                             # TeaseRules.CUSHION_POP
			_cushion_pop(from, to, msg.get("reveal") is bool and bool(msg.reveal))


# Eigener Wunsch abgelehnt (fx_no): „late“/„busy“ als leise Zeile, „rate“ graut kurz aus. Kein Fehlerton.
# Beta 1.6.6: Kissen (source.fx_refused_kind == "kissen"): „busy“ → „Da liegt schon ein Kissen.“, „rate“ → „Das Kissen muss sich erst
# wieder aufpusten.“ (ohne Restzeit; die übrigen Knöpfe bleiben aktiv, das Kissen hat keinen Eimer).
func on_refused(why: String) -> void:
	if not enabled or table == null:
		return
	if source != null and str(source.fx_refused_kind) == TeaseRules.CUSHION:
		match why:
			"busy":
				table.show_notice(I18n.t("Da liegt schon ein Kissen."))
			"rate":
				table.show_notice(I18n.t("Das Kissen muss sich erst wieder aufpusten."))
		_refresh_menu()
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
			_sync_reactions()
			# Das Menü ist nach dem Senden meist schon zu: die Reaktionsknöpfe wackeln und sind kurz blass (Beta 1.6.3)
			if reactions != null and reactions.visible:
				reactions.nudge()


func rate_limited() -> bool:
	return now < _rate_until


func _on_offs(_seats: Array) -> void:
	_refresh_menu()
	_sync_reactions()


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


# ================================================================= Furzkissen (Beta 1.6.6, eastereggs2.md 12.4)

# Bestätigung (nur beim Leger): leise Zeile, kein Bild am Ziel und kein Ton (sonst hörte es der Tisch)
func _cushion_placed(from: int, to: int) -> void:
	if to < 0 or from != _me():
		return
	table.show_notice(I18n.t("Kissen liegt bei %s.") % _name(to))
	_refresh_menu()


# Pups am Platz to: Kissen + Wolke + „Pfffrt!“, danach die Zeile mit dem Absender (nur mit reveal und from, sonst „Wer war das?“)
func _cushion_pop(from: int, to: int, reveal: bool) -> void:
	if to < 0:
		return
	var me := _me()
	var fx := CushionFx.new()
	_setup(fx, "kissen", to)
	fx.target = to
	fx.cw = (CUSHION_W_ME if to == me else CUSHION_W) * k()
	_place_cushion(fx, to)
	_add(fx)
	_play("furzkissen", to != me)
	if to == me:
		_vibrate(CUSHION_VIBE_MS)
	if not reduced:
		var node: OpponentSeat = _seat_badge(to)
		if node != null:
			node.set("_bump", 1.0)
			node.create_tween().tween_property(node, "_bump", 0.0, 0.45)
	# mit Namen: „Kim war's!“ (eigener Name: „Das warst du!“); geheim bzw. ohne from: „Wer war das?“ – auch beim Leger selbst
	var line := I18n.t("Wer war das?")
	if reveal and from >= 0:
		line = I18n.t("Das warst du!") if from == me else I18n.t("%s war's!") % _name(from)
	_later_q.append({"at": now + CUSHION_LINE_AT, "cb": _cushion_line.bind(line, weakref(fx), to)})


# Zeile nach dem Pups an der Stelle von „Pfffrt!“ (beim Ziel in Bannergröße)
func _cushion_line(text: String, fx_ref: WeakRef, to: int) -> void:
	if not enabled or layer == null:
		return
	var b := TextFx.new()
	_setup(b, "text", to)
	b.text = text
	b.color = UiPalette.CREAM if to != _me() else UiPalette.TURN
	b.size_px = int((UiFonts.size("hinweisleiste") if to == _me() else 30) * k())
	b.dur = CUSHION_LINE_S
	b.rise = 0.0 if reduced else 10.0
	var p := Vector2(anchor(to).pos)
	var fx: CushionFx = fx_ref.get_ref() as CushionFx
	if fx != null and is_instance_valid(fx):
		p = fx.position + fx.text_at(b.text_width())
		if to == _me() and not fx.text_side:  # beim Ziel neben dem Kissen (darüber liegt meist ein Fächer)
			p = fx.position + Vector2(fx.dir * (fx.cw * 1.7 + b.text_width() * 0.5), -fx.cw * 0.2)
	b.position = _clamp_text(p, b.text_width())
	_add(b)


# Lage nach _choose: links neben dem Avatar (Wolke nach links), darüber, rechts neben dem Kopf, darunter; großer Modus in der Zeile
# vor der Kartenzahl; beim Ziel groß über dem eigenen Namensschild. Hart gemieden wie bei den übrigen Effekten (Mau, Erwischt,
# Stapel, Hand, Knöpfe), beim Ziel zusätzlich die Reaktionsknöpfe.
func _place_cushion(fx: CushionFx, seat: int) -> void:
	var a := anchor(seat)
	var c := Vector2(a.pos)
	var r := float(a.r)
	var lst := _list_mode(seat)
	if lst:                                   # großer Modus: etwas kleiner, damit es in die Zeile passt; Text neben der Wolke
		fx.cw *= 0.8
		fx.text_side = true
	var cw := fx.cw
	var hd := head_of(seat)
	var hr: Rect2 = hd.rect
	var cands: Array = []
	var add := func(pos: Vector2, dir: float) -> void:
		fx.dir = dir
		cands.append({"pos": pos, "dir": dir, "rel": fx.area()})
	if lst:
		add.call(Vector2(float(hd.count_x) - cw * 1.4 - 8.0, c.y + r * 0.2), -1.0)
		add.call(c + Vector2(r + cw * 1.4, r * 0.2), 1.0)
		if seat == _me():                     # Zeile „Du“: davor liegen die Reaktionsknöpfe – dann knapp darüber
			add.call(c + Vector2(r + cw * 1.4, -r - cw * 0.45), 1.0)
	elif seat == _me():
		add.call(c + Vector2(r * 0.2 + cw * 0.4, -r - cw * 0.75), 1.0)
		add.call(c + Vector2(r * 0.2 + cw * 0.4, -r - cw * 1.1), 1.0)
		add.call(Vector2(hr.end.x + cw * 1.3 + 8.0, c.y), 1.0)
		add.call(c + Vector2(-r - cw * 1.4, -cw * 0.3), -1.0)
	else:
		add.call(c + Vector2(-r - cw * 1.35, r * 0.45), -1.0)
		add.call(c + Vector2(0.0, -r - cw * 0.7), 1.0)
		add.call(Vector2(hr.end.x + cw * 1.3 + 8.0, c.y + r * 0.3), 1.0)
		add.call(c + Vector2(0.0, r + cw * 1.6), 1.0)
	var blk := _blockers(seat)
	# Fächer der Mitspieler weich meiden (das Kissen samt „Pfffrt!“ soll keine Karten zudecken, wenn es woanders Platz hat)
	var soft: Array[Rect2] = blk.soft
	for st in table.get("_seats"):
		var sn: OpponentSeat = table.seat_node(int(st))
		if sn == null or not sn.is_visible_in_tree() or sn.list_mode or int(st) == _me():
			continue
		var av := _g2l(sn.avatar_global())
		var half := (OpponentSeat.BAR_W if sn.compact else sn.fan_max_w) * 0.5 + 6.0
		var fan_h := sn.header_height() * 0.5 + 6.0 + (OpponentSeat.BAR_H + 20.0 if sn.compact else sn.card_w * 1.62)
		soft.append(_rect_of(av + Vector2(-half, sn.avatar_radius() * 0.6), av + Vector2(half, fan_h)))
	if seat == _me() and reactions != null and reactions.visible:
		var hard: Array[Rect2] = blk.hard
		var rb := reactions.bounds()
		var xf := layer.get_global_transform_with_canvas().affine_inverse() * reactions.get_global_transform_with_canvas()
		hard.append(_rect_of(xf * rb.position, xf * rb.end))
	var best := _choose(cands, blk)
	fx.position = Vector2(best.pos)
	fx.dir = float(best.dir)


# Furzkissen: runder rosa Gummi mit Ventil zur Seite dir (±1); w = halbe Breite, sq = plattgedrückt (0 … 1)
const CUSHION_PINK := Color("#E8577F")
const CUSHION_DARK := Color("#B93A62")
const CLOUD_DAY := Color("#B5C46E")
const CLOUD_NIGHT := Color("#C9EE7E")


static func draw_cushion(ci: CanvasItem, c: Vector2, w: float, sq := 0.0, dir := 1.0, night_v := 0.0, alpha := 1.0) -> void:
	var lw := maxf(1.5, w * 0.075)
	var sx := 1.0 + 0.16 * sq
	var sy := 1.0 - 0.38 * sq
	var h := w * 0.72
	var bottom := h * 0.82
	var cy := c.y + bottom * (1.0 - sy)              # Unterkante bleibt liegen
	var ink := Color(INK, alpha)
	var ell := func(cx: float, cyy: float, rx: float, ry: float, a0: float, a1: float, n: int) -> PackedVector2Array:
		var out := PackedVector2Array()
		for i in n + 1:
			var a := lerpf(a0, a1, float(i) / float(n))
			out.append(Vector2(cx + cos(a) * rx, cyy + sin(a) * ry))
		return out
	if night_v > 0.5:                                  # leichter Neon-Schein (folgt der Form)
		for i in 2:
			var g: PackedVector2Array = ell.call(c.x, cy, w * sx * (1.14 + i * 0.12), h * sy * (1.28 + i * 0.2), 0.0, TAU, 36)
			g.remove_at(g.size() - 1)
			ci.draw_colored_polygon(g, Color(CUSHION_PINK, (0.16 - i * 0.07) * alpha))
	# Ventil (Röhrchen mit Rand), hinter dem Körper
	var base := Vector2(c.x + dir * w * sx * 0.82, cy + h * sy * 0.2)
	var tip := Vector2(c.x + dir * (w * sx + w * 0.34), cy + h * sy * 0.08 - w * 0.06 * sq)
	var n := (tip - base).normalized().orthogonal()
	var tube := PackedVector2Array([base + n * w * 0.12, tip + n * w * 0.08, tip - n * w * 0.08, base - n * w * 0.12])
	ci.draw_colored_polygon(tube, Color(CUSHION_DARK, alpha))
	var tl := tube.duplicate()
	tl.append(tube[0])
	ci.draw_polyline(tl, ink, lw, true)
	ci.draw_circle(tip, w * 0.1 + lw * 0.5, ink)
	ci.draw_circle(tip, w * 0.1 - lw * 0.4, Color(CUSHION_DARK.darkened(0.25), alpha))
	# Körper: Ellipse, unten etwas flacher
	var pts := PackedVector2Array()
	for i in 36:
		var a := TAU * i / 36.0
		var y := sin(a) * h * sy
		if y > 0.0:
			y *= 0.82
		pts.append(Vector2(c.x + cos(a) * w * sx, cy + y))
	ci.draw_colored_polygon(pts, Color(CUSHION_PINK, alpha))
	# Naht: dunklere untere Hälfte (Mondsichel zwischen Unterkante und Naht)
	var low := PackedVector2Array()
	for i in 19:
		var a := PI * i / 18.0
		low.append(Vector2(c.x + cos(a) * w * sx * 0.98, cy + sin(a) * h * sy * 0.8))
	for i in range(17, 0, -1):
		var a := PI * i / 18.0
		low.append(Vector2(c.x + cos(a) * w * sx * 0.9, cy + sin(a) * h * sy * 0.3))
	ci.draw_colored_polygon(low, Color(CUSHION_DARK, 0.55 * alpha))
	ci.draw_polyline(ell.call(c.x, cy, w * sx * 0.95, h * sy * 0.3, 0.12, PI - 0.12, 16), Color(CUSHION_DARK.darkened(0.2), alpha), lw * 0.8, true)
	var outline := pts.duplicate()
	outline.append(pts[0])
	ci.draw_polyline(outline, ink, lw * 1.2, true)
	# Glanz oben links (als Ellipsenbogen, wird mit plattgedrückt)
	ci.draw_polyline(ell.call(c.x - w * sx * 0.28, cy - h * sy * 0.22, w * sx * 0.36, h * sy * 0.48, PI * 1.08, PI * 1.5, 10),
		Color(UiPalette.CREAM, 0.85 * alpha), lw * 1.6, true)
	ci.draw_circle(Vector2(c.x + w * sx * 0.16, cy - h * sy * 0.62), lw * 0.9, Color(UiPalette.CREAM, 0.75 * alpha))


# kleine Wolke aus mehreren Kreisen (Mitte c, Radius rr). pass 0 = Rand (für alle Bäusche zuerst), 1 = Füllung, so verschmelzen
# überlappende Bäusche zu einer Wolke (mit Rand je Bausch sahen sie aus wie Trauben).
static func draw_puff(ci: CanvasItem, c: Vector2, rr: float, night_v: float, alpha: float, pass_i := 1) -> void:
	var col := CLOUD_NIGHT if night_v > 0.5 else CLOUD_DAY
	var offs := [Vector2(0, 0), Vector2(-0.55, 0.15), Vector2(0.5, 0.2), Vector2(0.1, -0.45)]
	var rs := [0.62, 0.45, 0.48, 0.42]
	for i in offs.size():
		if pass_i == 0:
			ci.draw_circle(c + (offs[i] as Vector2) * rr, rr * float(rs[i]) + maxf(1.5, rr * 0.08), Color(col.darkened(0.35), 0.9 * alpha))
		else:
			ci.draw_circle(c + (offs[i] as Vector2) * rr, rr * float(rs[i]), Color(col, 0.97 * alpha))
	if pass_i == 1:
		ci.draw_circle(c + Vector2(-0.12, -0.2) * rr, rr * 0.2, Color(UiPalette.CREAM, 0.45 * alpha))


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


# ================================================================= Bedienung: Menü am Gegner, Reaktionsknöpfe

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
		# Beta 1.6.7: bei Menschen immer da (das Menü bleibt beim Zugwechsel offen und soll nicht springen), nicht am Zug ausgegraut
		if not _is_bot(seat):
			var at_turn := seat == _current_turn()
			for kk in ["snore", "alarm"]:
				if kinds.has(kk):
					var it := _item(kk, I18n.t("Schnarchen") if kk == "snore" else I18n.t("Wecker"), {"k": kk, "to": seat})
					var left := source.fx_slow_left_ms(seat) if source != null and at_turn else -1
					it["progress"] = 1.0 - float(left) / float(TeaseRules.FX_SLOW_MS) if left >= 0 else 1.0
					if not at_turn:
						it["on"] = false
						note = I18n.t("Erst, wenn %s dran ist.") % _name(seat)
					elif str(it.get("why", "")) == "early":
						note = I18n.t("Erst, wenn %s eine Weile überlegt.") % _name(seat)
					items.append(it)
	if node != null and node.backs_visible():
		items.append({"key": "backs", "label": I18n.t("Karten ansehen"), "on": true, "progress": 1.0})
	# Beta 1.6.6: Furzkissen als eigene Zeile mit „Mit Namen“/„Geheim“. Die Vorprüfung kennt nur das eigene Kissen (fremde verrät sie
	# nie, auch beim Gastgeber nicht): rate = eigene Sperre, busy = eigenes Kissen liegt schon bei diesem Ziel.
	var cushion := {}
	if not off and kinds.has(TeaseRules.CUSHION):
		var why := source.fx_check({"k": TeaseRules.CUSHION, "to": seat, "reveal": true}) if source != null else "mode"
		cushion = {"label": I18n.t("Furzkissen"), "on": why == "", "why": why, "opts": [
			{"key": "kissen_name", "label": I18n.t("Mit Namen")}, {"key": "kissen_geheim", "label": I18n.t("Geheim")}]}
		var cn := ""
		if why == "rate":
			cn = I18n.t("Das Kissen muss sich erst wieder aufpusten.")
		elif why == "busy":
			cn = I18n.t("Da liegt schon ein Kissen.")
		if cn != "":
			note = cn if note == "" else note + "\n" + cn
	return {"items": items, "note": note, "cushion": cushion}


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
	menu = TeaseMenu.new()
	menu.name = "NeckenMenue"
	menu.seat = seat
	menu.night = night
	menu.k = k()
	menu.title = menu_title(seat)
	var d := menu_items(seat)
	menu.items = d.items
	menu.note = str(d.note)
	menu.cushion = d.cushion
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
	menu.set_items(d.items, str(d.note), d.cushion)
	if menu.size_changed:
		place_menu(true)                      # Beta 1.6.7: möglichst an der Stelle bleiben (nicht unter dem Finger wegspringen)


# Beta 1.6.7: „Erwischt!“-Buzzer, die gerade unter dem offenen Menü liegen (jemand wurde erwischbar, während es offen war). Das Menü
# zeichnet sie über sich und lässt Tipps dort durch (TeaseMenu.buzzers/_has_point) – der Tisch erwischt, das Menü schließt wie bei
# jedem Tipp daneben. Es bleibt offen und springt nicht.
func _sync_menu_buzzers() -> void:
	if menu == null or table == null:
		return
	var out: Array = []
	var mr := Rect2(Vector2.ZERO, menu.size)
	for s in table.get("_seats"):
		var sn: OpponentSeat = table.seat_node(int(s))
		if sn == null or not sn.catchable or not sn.is_visible_in_tree() or sn.modulate.a < 0.5:
			continue
		var hit := catch_rect_of(int(s), menu)
		if not hit.intersects(mr):
			continue
		out.append({"rect": catch_rect_of(int(s), menu, 0.0), "hit": hit, "t": float(sn.get("_time")), "fs": sn.buzzer_font_size(), "red": sn.reduced})
	if not out.is_empty() or not menu.buzzers.is_empty():
		menu.buzzers = out
		menu.queue_redraw()


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
	if key == "kissen_name" or key == "kissen_geheim":
		send({"k": TeaseRules.CUSHION, "to": seat, "reveal": key == "kissen_name"})
		close_menu(false)
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
# darüber – jeweils in den Bildschirm geklemmt. Gemieden werden das „Erwischt!“-Feld des Ziels und jedes gerade erwischbaren Platzes,
# die Knöpfe oben links (avoid_cb, TableScreen), der Mau-Knopf und möglichst der Kopf des Ziels. Beta 1.6.7: Weil das Menü offen
# bleibt, wenn jemand erwischbar wird, meidet es auch die „Erwischt!“-Felder der übrigen Plätze (etwas schwächer). keep = beim
# Auffrischen mit neuer Größe die bisherige Lage bevorzugen (die dem Avatar zugewandte Kante bleibt stehen).
func place_menu(keep := false) -> void:
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
	var mid: Array[Rect2] = []                # Beta 1.6.7: „Erwischt!“-Felder der übrigen Plätze, die (noch) nicht erwischbar sind
	for s in table.get("_seats"):
		var sn: OpponentSeat = table.seat_node(int(s))
		if sn == null or int(s) == menu.seat or not sn.is_visible_in_tree() or sn.modulate.a < 0.5:
			continue
		if sn.catchable:
			hard.append(catch_rect_of(int(s), par))
		else:
			mid.append(catch_rect_of(int(s), par, 0.0))
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
		for b in mid:
			if rect.intersects(b):
				cost += rect.intersection(b).get_area() * 12.0
		for b in soft:
			if rect.intersects(b):
				cost += rect.intersection(b).get_area() * 4.0
		return cost
	var best := Vector2.INF
	var best_cost := INF
	if keep and menu.position.is_finite():
		# bisherige Lage mit der neuen Größe: die Kante zum Avatar bleibt stehen; gewinnt, solange sie nichts Hartes trifft
		var old := Rect2(menu.position, menu.old_size)
		var c := Vector2(old.position.x if old.get_center().x >= a.x else old.end.x - s.x,
			old.position.y if old.get_center().y >= a.y else old.end.y - s.y)
		c = clamp_c.call(c)
		best_cost = cost_of.call(c, 0) - 800.0
		best = c
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
func catch_rect_of(seat: int, node: CanvasItem, margin := 18.0) -> Rect2:
	var sn := table.seat_node(seat)
	if sn == null:
		return Rect2()
	var inv := table.get_global_transform().affine_inverse()
	var cr: Rect2 = sn._catch_rect().grow(margin)
	var p0: Vector2 = table._table_to(node, inv * sn.to_global(cr.position))
	var p1: Vector2 = table._table_to(node, inv * sn.to_global(cr.end))
	return Rect2(p0, Vector2.ZERO).expand(p1)


# Tipp auf den Kopf (Avatar, Name, Kartenzahl) eines Gegners: true = Menü offen (verbraucht)
func tap_head(seat: int) -> bool:
	return open_menu(seat)


func _on_react_chosen(r: String) -> void:
	if reactions.gray:
		return
	send({"k": "react", "r": r})


# Beta 1.6.5: die 4 Reaktionsknöpfe – nur mit Reaktionen in dieser Spielart, eigenem Platz und Necken an. Lage: normal neben dem
# eigenen Namen (Platzwahl _place_reactions), großer Modus in der Zeile „Du“ vor der Kartenzahl (_row_reactions).
# full = auch die Regeln und die Platzwahl neu prüfen (alle SYNC_S); sonst nur Lage und Uhr (jedes Bild), gezeichnet nur bei Änderung.
func _sync_reactions(full := true) -> void:
	if reactions == null or table == null:
		return
	if full:
		var kinds: Array = caps().get("kinds", [])
		_react_cap = kinds.has("react")
		_react_why = source.fx_check({"k": "react", "r": "lachen"}) if source != null and _react_cap else "mode"
	var badge := table.me_badge
	var show := enabled and _react_cap and _me() >= 0 and badge.visible and badge.modulate.a > 0.5 \
		and not table.handover.visible and not covered()
	if show and badge.list_mode and _row_hidden(badge):
		show = false
	if show != reactions.visible:
		reactions.visible = show
		_react_key = ""
		_react_rel.clear()
	if not show or not badge.list_mode:
		_set_row_reserve(badge, 0.0)
	if not show:
		return
	reactions.night = night
	reactions.reduced = reduced
	if badge.list_mode:
		_row_reactions(badge)
	else:
		reactions.squash = 1.0
		if full or _react_rel.size() != TeaseMenu.REACT_ORDER.size():
			_place_reactions(badge)
		var av := _g2r(anchor(_me()).pos)
		var cs: Array[Vector2] = []
		for p in _react_rel:
			cs.append(av + p)
		reactions.centers = cs
	reactions.gray = _react_why != "" or rate_limited()
	reactions.dim = rate_limited()
	var key := "%s|%s|%s|%s|%s|%s" % [reactions.centers.map(func(p: Vector2) -> Vector2: return p.round()), reactions.r, reactions.gray,
		reactions.dim, reactions.night, snappedf(reactions.squash, 0.01)]
	if key != _react_key:
		_react_key = key
		reactions.queue_redraw()


# Effekt-Ebene → Koordinaten der Reaktionsknöpfe (beide liegen in den Overlays des Tisches)
func _g2r(p: Vector2) -> Vector2:
	if layer == null:
		return p
	return reactions.get_global_transform_with_canvas().affine_inverse() * (layer.get_global_transform_with_canvas() * p)


func _set_row_reserve(badge: OpponentSeat, v: float) -> void:
	if not is_equal_approx(badge.row_reserve, v):
		badge.row_reserve = v
		badge.queue_redraw()


# Großer Modus: Knöpfe rechtsbündig in der Zeile „Du“ vor der großen Kartenzahl. Dem Wort „Du“ bleibt sein Platz, sonst werden die
# Knöpfe kleiner (nie unter 22 px Radius). Die Zeile kürzt Namen und „dran“ um diesen Platz (OpponentSeat.row_reserve).
func _row_reactions(badge: OpponentSeat) -> void:
	var rh := badge.row_size.y
	var cr := badge.count_rect()
	var ar := badge.avatar_radius()
	var nx := -badge.row_size.x * 0.5 + 12.0 + ar * 2.0 + 14.0
	var x_end := cr.position.x - 12.0
	var name_fs := mini(UiFonts.px(36), int(rh * 0.46))
	var name_w := UiFonts.text(800, 100.0).get_string_size(I18n.t("Du"), HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs).x + 10.0
	var gap := REACT_GAP * k()
	var n := TeaseMenu.REACT_ORDER.size()
	var r := minf(TeaseMenu.REACT_BTN_R * k(), (rh - 14.0) * 0.5)
	var room := x_end - nx - name_w
	if 2.0 * r * n + gap * (n - 1) > room:
		gap = 8.0
		r = (room - gap * (n - 1)) / (2.0 * n)
	r = maxf(r, 22.0)
	var inv := table.get_global_transform().affine_inverse()
	var cs: Array[Vector2] = []
	for i in n:
		var lx := x_end - r - float(n - 1 - i) * (2.0 * r + gap)
		cs.append(table._table_to(reactions, inv * badge.to_global(Vector2(lx, 0.0))))
	reactions.centers = cs
	reactions.r = r
	reactions.squash = badge.flip_y
	_set_row_reserve(badge, 2.0 * r * n + gap * (n - 1) + 8.0)


# Großer Modus: liegt gerade eine andere Zeile über „Du“ (erwischbarer Spieler außerhalb der sichtbaren Zeilen), weichen die Knöpfe.
func _row_hidden(badge: OpponentSeat) -> bool:
	var mine := Rect2(badge.to_global(badge.list_rect().position), badge.list_rect().size)
	for s in table.get("_seats"):
		var sn: OpponentSeat = table.seat_node(int(s))
		if sn == null or not sn.is_visible_in_tree() or sn.modulate.a < 0.5 or sn.z_index <= badge.z_index:
			continue
		if Rect2(sn.to_global(sn.list_rect().position), sn.list_rect().size).grow(-4.0).intersects(mine):
			return true
	return false


# Normaler Modus: Lage nach TeaseFx._choose (wie die größeren Effekte) – (1) als Reihe rechts neben Name und Kartenzahl, (2) darüber,
# (3) 2 × 2 rechts daneben, (4) etwas weiter rechts. Hart gemieden: Hand, Ziehstapel, Ablage, Mau, Sortieren/Rückseiten, Knöpfe oben
# links, „Erwischt!“-Felder aller Mitspieler (auch wenn gerade niemand erwischbar ist – sonst sprängen die Knöpfe), die Fächer der
# Mitspieler, die Hinweisleiste (als Band über die ganze Breite, damit lange Hinweise nichts verschieben) und der Einsatzstapel im
# Glücksspiel; weich die Köpfe. Ergebnis: Knopfmitten relativ zum eigenen Avatar (_react_rel).
func _place_reactions(badge: OpponentSeat) -> void:
	var r := TeaseMenu.REACT_BTN_R
	var gap := REACT_GAP
	var n := TeaseMenu.REACT_ORDER.size()
	var a: Vector2 = anchor(_me()).pos
	var ar := badge.avatar_radius()
	var head: Rect2 = head_of(_me()).rect
	var sz := _screen()
	var blk := _blockers(_me())
	var hard: Array[Rect2] = blk.hard
	for st in table.get("_seats"):
		var sn: OpponentSeat = table.seat_node(int(st))
		if sn == null or not sn.is_visible_in_tree() or int(st) == _me():
			continue
		hard.append(catch_rect_of(int(st), layer))
		var av := _g2l(sn.avatar_global())
		var half := (OpponentSeat.BAR_W if sn.compact else sn.fan_max_w) * 0.5 + 10.0
		var fan_h := sn.header_height() * 0.5 + 10.0 + (OpponentSeat.BAR_H + 24.0 if sn.compact else sn.card_w * 1.62)
		hard.append(_rect_of(av + Vector2(-half, -sn.avatar_radius()), av + Vector2(half, fan_h)))
	var hb := table.hint_bar
	var hint_top := _g2l(hb.get_global_transform() * Vector2(0.0, hb.hint_y - hb.hint_h() * 0.5)).y - 6.0
	hard.append(_rect_of(Vector2(0.0, hint_top), Vector2(sz.x, hint_top + hb.hint_h() + 12.0)))
	var sp: Node2D = table.stake_pile
	if sp != null and sp.visible:
		var w := float(sp.get("card_w"))
		var c := table._table_to(layer, (table.get("_world") as Node2D).transform * sp.position)
		hard.append(Rect2(c - Vector2(w * 0.65, w * CardView.ASPECT * 0.65), Vector2(w * 1.3, w * CardView.ASPECT * 1.3)))
	var row := Vector2(2.0 * r * n + gap * (n - 1), 2.0 * r)
	var grid := Vector2(4.0 * r + gap, 4.0 * r + gap)
	var y_max := hint_top - 4.0                        # Unterkante über der Hinweisleiste
	var cands: Array = []
	var add := func(top_left: Vector2, shape: Vector2, cols: int) -> void:
		cands.append({"pos": Vector2(top_left.x, minf(top_left.y, y_max - shape.y)), "rel": Rect2(Vector2.ZERO, shape), "cols": cols})
	add.call(Vector2(head.end.x + 14.0, a.y - r), row, n)
	add.call(Vector2(a.x - ar, a.y - ar - 14.0 - row.y), row, n)
	add.call(Vector2(head.end.x + 14.0, a.y - grid.y * 0.5), grid, 2)
	add.call(Vector2(head.end.x + 14.0 + 2.0 * r, a.y - r), row, n)
	var best := _choose(cands, {"hard": hard, "soft": blk.soft})
	var tl: Vector2 = best.pos
	var cols := int(best.cols)
	var rel: Array[Vector2] = []
	for i in n:
		rel.append(tl + Vector2(r + float(i % cols) * (2.0 * r + gap), r + float(i / cols) * (2.0 * r + gap)) - a)
	_react_rel = rel
	reactions.r = r


# Gerätetest 1.6.3: Liegt etwas Modales über dem Tisch, verschwinden die Reaktionsknöpfe. Sie hängen hinter dem Rundenende
# in den Overlays, also über Farbrad, Rückseiten-Großansicht und Kartenhilfe; Rückfragen und Menüs von TableScreen über modal_cb.
func covered() -> bool:
	if table == null:
		return false
	if table.wish_picker.is_open() or table.backs_viewer.visible or table.help_popup.visible:
		return true
	return modal_cb.is_valid() and bool(modal_cb.call())


# Flächen für die Sofort-Leiste (TableScreen.bar_obstacles, Bildschirmkoordinaten): Reaktionsknöpfe und Menü
func obstacles() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if reactions != null and reactions.visible:
		out.append(Rect2(reactions.get_global_transform_with_canvas() * reactions.bounds().position, reactions.bounds().size))
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


# ================================================================= Bilder (Reaktionen ab Beta 1.6.5 als feste Emoji-Bilder, siehe draw_reaction)

const INK := Color("#211B2C")
const CLOCK := Color("#E5484D")
const CAP := Color("#7B6BE0")


# Bild kind (ball, snore, alarm, backs, lachen, klatschen, daumen, schreck) mit Mitte c und Größe s (≈ Radius).
# t = Zeit für kleine Bewegungen (Zeiger).
static func draw_icon(ci: CanvasItem, kind: String, c: Vector2, s: float, t := 0.0, seed_v := 3) -> void:
	if REACT_TEX.has(kind):
		draw_reaction(ci, kind, c, s)             # Beta 1.6.5: Reaktionen als feste Emoji-Bilder
		return
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
		"kissen":                                     # Beta 1.6.6: Furzkissen
			draw_cushion(ci, c + Vector2(-s * 0.15, s * 0.15), s * 0.95, 0.0, 1.0, 0.0)
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


# ================================================================= Reaktionen als feste Bilder (Beta 1.6.5)

# Nutzerwunsch nach der Familienrunde (15.10.2026): Das gezeichnete „Daumen hoch“ ließ sich anders deuten. System-Emoji sehen je Gerät
# anders aus (Samsung, Google), deshalb zeigen App und Browser dieselben vier Bilder: Microsoft Fluent Emoji, Stil „Color“ (MIT-Lizenz,
# assets/ui/reaktionen/LIZENZ.md), unverändert als SVG im Projekt. Godot rastert sie beim Import 12-fach (384 × 384 px, svg/scale in
# der .import-Datei) mit Mipmaps; der Standard-Texturfilter des Projekts (linear mit Mipmaps) hält sie in Knopfgröße wie groß glatt.
# Tag und Nacht unverändert.
const REACT_TEX := {
	"lachen": preload("res://assets/ui/reaktionen/lachen.svg"),
	"klatschen": preload("res://assets/ui/reaktionen/klatschen.svg"),
	"daumen": preload("res://assets/ui/reaktionen/daumen.svg"),
	"schreck": preload("res://assets/ui/reaktionen/schreck.svg"),
}
const REACT_IMG := 2.2          # Bildkante relativ zu s (≈ Radius): das Motiv (gut 28 von 32 Einheiten) füllt dann etwa 2 s


# Reaktion kind mit Mitte c und Größe s (≈ Radius wie bei den übrigen Bildern)
static func draw_reaction(ci: CanvasItem, kind: String, c: Vector2, s: float, alpha := 1.0) -> void:
	var tex: Texture2D = REACT_TEX.get(kind)
	if tex == null:
		return
	var e := s * REACT_IMG
	ci.draw_texture_rect(tex, Rect2(c - Vector2.ONE * e * 0.5, Vector2.ONE * e), false, Color(1, 1, 1, alpha))


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


# Beta 1.6.6: Furzkissen am Platz des Ziels – erscheint, wird plattgedrückt (mit kleinem Nachfedern), aus dem Ventil steigt eine
# Wolke zur Seite dir, „Pfffrt!“ springt auf; nach CUSHION_S ausgeblendet. Reduziert: liegt schon flach, blendet nur ein und aus.
class CushionFx:
	extends TeaseEffect
	var target := -1
	var cw := CUSHION_W           # halbe Kissenbreite (TeaseFx setzt sie samt k)
	var dir := 1.0                # Ventil und Wolke nach rechts (1) oder links (−1)
	var text_side := false        # großer Modus: „Pfffrt!“ und die Zeile neben der Wolke (text_at)

	# Umriss relativ zur Kissenmitte: Kissen, Ventil und Wolke zur Seite d, darüber „Pfffrt!“
	static func bounds(w: float, d: float) -> Rect2:
		var x0 := -1.3 * w
		var x1 := 3.2 * w
		if d < 0.0:
			x0 = -3.2 * w
			x1 = 1.3 * w
		return Rect2(Vector2(x0, -1.95 * w), Vector2(x1 - x0, 2.55 * w))

	# Mitte von „Pfffrt!“ (und danach der Zeile mit dem Absender), relativ zur Kissenmitte; w_text = Breite des Textes (−1: „Pfffrt!“).
	# Großer Modus (text_side): in der Zeile neben der Wolke statt darüber (darüber liegt die nächste Zeile bzw. „Reihenfolge“).
	func text_at(w_text := -1.0) -> Vector2:
		if text_side:
			var tw := w_text if w_text >= 0.0 else pfffrt_w()
			return Vector2(dir * (cw * 2.2 + tw * 0.5), -cw * 0.05)
		return Vector2(dir * cw * 0.75, -cw * 1.45)

	func pfffrt_fs() -> int:
		return int(cw * (0.6 if text_side else 0.72))

	func pfffrt_w() -> float:
		return UiFonts.title(800, true, 100.0).get_string_size(I18n.t("Pfffrt!"), HORIZONTAL_ALIGNMENT_LEFT, -1, pfffrt_fs()).x

	# Umriss samt Text (relativ zur Kissenmitte) für die Platzwahl
	func area() -> Rect2:
		var b := bounds(cw, dir)
		if text_side:                     # Text in der Zeile: oben nur die Wolke
			b = Rect2(Vector2(b.position.x, -1.15 * cw), Vector2(b.size.x, 1.75 * cw))
		if text_side:
			var c := text_at()
			b = b.merge(Rect2(c - Vector2(pfffrt_w() * 0.5 + 6.0, cw * 0.45), Vector2(pfffrt_w() + 12.0, cw * 0.9)))
		return b

	func squash() -> float:
		if reduced:
			return 0.5
		if t < 0.12:
			return 0.0
		var u := clampf((t - 0.12) / 0.16, 0.0, 1.0)
		var sq := 1.0 - (1.0 - u) * (1.0 - u)
		if t > 0.28:
			sq -= 0.14 * sin((t - 0.28) * 16.0) * exp(-(t - 0.28) * 6.0)
		return clampf(sq, 0.0, 1.0)

	func step(delta: float) -> bool:
		super.step(delta)
		return t < CUSHION_S

	func _draw() -> void:
		var a_in := clampf(t / 0.12, 0.0, 1.0)
		var alpha := minf(a_in, clampf((CUSHION_S - t) / 0.4, 0.0, 1.0))
		var sq := squash()
		var sc := 1.0 if reduced else lerpf(0.6, 1.0, 1.0 - (1.0 - a_in) * (1.0 - a_in))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * sc)
		TeaseFx.draw_cushion(self, Vector2.ZERO, cw, sq, dir, night, alpha)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# Wolke aus dem Ventil: vier Bäusche nacheinander, wachsen, steigen schräg auf und verblassen
		var h := cw * 0.72                      # wie TeaseFx.draw_cushion
		var sx := 1.0 + 0.16 * sq
		var sy := 1.0 - 0.38 * sq
		var tip := Vector2(dir * (cw * sx + cw * 0.34), h * 0.82 * (1.0 - sy) + h * sy * 0.08 - cw * 0.06 * sq)
		for k_i in 8:                           # erst alle Ränder, dann alle Füllungen (eine zusammenhängende Wolke)
			var i := k_i % 4
			var born := 0.2 + i * 0.09
			var u := (t - born) / 1.15
			if u <= 0.0 or u >= 1.0:
				continue
			var ue := 0.5 if reduced else 1.0 - (1.0 - u) * (1.0 - u)
			var pa := clampf(minf(u / 0.12, (1.0 - u) / 0.45), 0.0, 1.0) * alpha
			var p := tip + Vector2(dir * cw * (0.15 + 0.45 * ue) * (1.0 + i * 0.35), -cw * (0.05 + 0.45 * ue) * (0.7 + i * 0.12))
			var rr := cw * (0.24 + 0.24 * ue) * (1.0 - i * 0.08)
			TeaseFx.draw_puff(self, p, rr, night, pa, 0 if k_i < 4 else 1)
		# „Pfffrt!“
		var t0 := 0.18
		var t1 := 1.45
		if t >= t0 and t <= t1:
			var tt := t - t0
			var pop := 1.0 if reduced else 0.55 + 0.45 * minf(tt / 0.12, 1.0) + 0.12 * sin(minf(tt / 0.3, 1.0) * PI)
			var ta := clampf(minf(tt / 0.08, (t1 - t) / 0.3), 0.0, 1.0) * alpha
			var f := UiFonts.title(800, true, 100.0)
			var fs := pfffrt_fs()
			var txt := I18n.t("Pfffrt!")
			var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var rise := 0.0 if reduced else tt * 14.0
			draw_set_transform(text_at() + Vector2(0.0, -rise), -0.1 * dir, Vector2.ONE * pop)
			var day := night < 0.5
			var edge := Color(UiPalette.INK if day else UiPalette.NIGHT, 0.95 * ta)
			var fill := Color(Color("#FF7FA3") if day else Color("#FF9CBB"), ta)
			draw_string_outline(f, Vector2(-tw * 0.5, fs * 0.34), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(5, fs / 5), edge)
			draw_string(f, Vector2(-tw * 0.5, fs * 0.34), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fill)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
