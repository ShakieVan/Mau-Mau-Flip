class_name NatureFx
extends Node
# Mau-Mau Flip (Beta 1.6.12): „Natur-Überraschungen“ am Tisch – Planer und Verwaltung (docs/module/natur.md, Aufgabe T1).
# Seltene, lautlose Bild-Ereignisse (Marienkäfer, Glühwürmchen, Eule …), nur lokal je Gerät: nichts geht übers Netz, nichts in Sicht,
# Speicher, Statistik oder Protokoll; kein Ton, keine Vibration, kein Text. Gleicher Ablauf wie webclient/natur.js (Abschnitt 4.2).
#   - Es läuft höchstens ein Ereignis, nie zusammen mit Mau-Katze, Bestand-Himmel (FunFx.SkyNode) oder Necken-Effekten; im Schnitt
#     etwa alle 3 min eins (Tabelle zeiten in nature_table.gd). Anlässe: Flip (Regenbogen bzw. Glühwürmchen/Fledermaus/Eule), Trödeln
#     (Schnecke). Startet nur in Ruhe (4.4), geht bei wichtigen Momenten schnell ab (4.5).
#   - Drei Ebenen (2.1): NaturHinten direkt nach dem Hintergrund (Himmel), NaturMitte in der Welt direkt nach der Richtungs-Plattform,
#     NaturVorn in der Welt direkt nach der Hand (nur Biene und UFO, nie im eigenen Zug).
#   - Bestand: Schmetterling und Sternschnuppe zeichnet weiter FunFx.SkyNode (Sternschnuppe: shooting_star_fx.gd); sie laufen jetzt im
#     selben Takt (FunFx.sky_auto = false, fun.nature = self). Die Mau-Katze hat Vorrang: FunFx fragt busy() und ruft make_room().
#   - Tiere: static make(id) lädt nature_day.gd/nature_night.gd (wenn vorhanden) und ruft deren static func make(id) -> NatureCreature.
#     Fehlt ein Tier, kommt sein Ereignis einfach nicht vor.
# Der Tisch (TableView) ruft: mount, set_reduced, set_big, set_night, on_layout, on_view, on_event, notice_press, tap. Die Uhr läuft
# über _process; Tests schalten auto_process aus und rufen tick(dt). Tests/Kontrollbilder: spawn(id, seed) ohne Bedingungen, seek(t),
# creature(), anchors(), obstacles(), make_cb (Probe-Tier), lage_override (Lage überschreiben).
# Protokoll (eine Zeile je Ereignis, auch im Release-Bau in logcat): „NatureFx: start <id>“ und „NatureFx: ende <id> fps=<n>“.

signal started(id: String)
signal ended(id: String)

const NT := preload("res://scripts/ui/nature_table.gd")
const DAY_PATH := "res://scripts/ui/nature_day.gd"
const NIGHT_PATH := "res://scripts/ui/nature_night.gd"
const TURN_PHASES := ["turn", "drawn"]
const ALL_GO := ["round_over", "game_over", "round_start", "deal", "seats", "start"]
const FRONT_GO := ["mau", "finish", "catch", "gamble_start"]
# Ereignisse am Ort (4.5): UFO am Stapel, Motte am Ablage-Ring, Biene auf der Hand
const PLACE_GO := {"stapel_oben": ["draw", "shuffle"], "ablage_ring": ["play", "flip", "discard_color", "stake_discard", "shuffle"],
	"handkarte": ["swap_hands"]}
const HAND_GO := ["play", "draw", "stake", "stake_back", "discard_color", "unplay"]   # eigene Hand ändert sich
const TOP_LEFT := Rect2(0, 0, 280, 110)                 # Zurück- und ☰-Knopf (TableScreen)
const RING_R := 116.0                                   # TableView.ColorRingView.R
const LOG_MAX := 60
const PAUSE_S := 2.0


# Ein laufendes Ereignis
class Running:
	extends RefCounted
	var id := ""
	var e: Dictionary = {}
	var node: Node2D = null              # NatureCreature (null beim Bestand)
	var bridge := false                  # Bestand über FunFx.SkyNode
	var layer := ""
	var seed_value := 0
	var t := 0.0                         # nur Bestand (die Tiere haben ihre eigene Uhr)
	var anlass := ""                     # zufall | flip | troedeln | demo | zeige
	var reason := ""
	var still := false                   # eingefroren (Kontrollbilder)
	var tapped := false
	var frames := 0
	var run_s := 0.0

	func time() -> float:
		return t if bridge or node == null else float(node.get("t"))

	func leaving() -> bool:
		return node != null and bool(node.call("leaving"))


var table: Control = null                # TableView
var fun: Object = null                   # FunFx
var rng := RandomNumberGenerator.new()
var auto_process := true
var now := 0.0
var reduced := false
var big := false
var night := 0.0
var enabled := true
var demo := false
var current: Running = null
var history := {"tag": [], "nacht": []}  # letzte Ereignisse je Seite (Wiederholungssperre)
var counts := {"partie": {}, "runde": {}}
var due := INF                           # nächster Zufallsstart
var last_end := -1.0e9
var flip_cue: Dictionary = {}            # Anlass {side, at}
var flip_round := {}                     # Seite → Flip-Ereignisse dieser Runde
var troedel := {"sig": "", "since": 0.0, "rolled": false, "seat": -1, "players": {}, "cats": 0}
var snail_wait: Dictionary = {}          # Schnecke wartet {seat, sig, displaced}
var comet_block_until := -1.0e9
var demo_next := 0.0
var demo_pos := {"tag": -1, "nacht": -1}
var view: Dictionary = {}
var protocol: Array = []                    # [{was: start|ende, id, now, anlass, grund, ...}]
var print_log := true
var make_cb := Callable()                # Tests: (id) -> NatureCreature statt nature_day/nature_night
var lage_override: Dictionary = {}       # Tests: Felder der Lage überschreiben (z. B. {"regie_leer": false})
var layers := {}                         # hinten | mitte | vorn → Node2D

var _world: Node2D = null
var _ring: Node2D = null
var _hand_layer: Node2D = null
var _unrest := -1.0e9
var _plan_at := -1.0e9
var _was_active := false
var _was_table := false
var _alt: Dictionary = {}
var _taps: Array = []
var _makeable := {}
var _last_size := Vector2.ZERO
var _paused_ms := -1


func _init() -> void:
	name = "Natur"
	rng.randomize()


# Ebenen einhängen (2.1) und den Bestand-Himmel übernehmen
func mount(t: Control, bg: Node, world: Node2D, ring: Node2D, hand_layer: Node2D) -> void:
	table = t
	_world = world
	_ring = ring
	_hand_layer = hand_layer
	t.add_child(self)
	var h := Node2D.new()
	h.name = "NaturHinten"
	t.add_child(h)
	t.move_child(h, bg.get_index() + 1)
	var m := Node2D.new()
	m.name = "NaturMitte"
	world.add_child(m)
	world.move_child(m, ring.get_index() + 1)
	var v := Node2D.new()
	v.name = "NaturVorn"
	world.add_child(v)
	world.move_child(v, hand_layer.get_index() + 1)
	layers = {"hinten": h, "mitte": m, "vorn": v}
	var f: Variant = t.get("fun")
	if f is Object:
		fun = f
		fun.set("sky_auto", false)
		fun.set("nature", self)
	_last_size = t.size


func set_reduced(on: bool) -> void:
	reduced = on
	if on and current != null and not current.still and not bool(current.e.get("ruhig", false)):
		_remove(current, "reduziert")


func set_big(on: bool) -> void:
	big = on
	if on and current != null and not current.still:
		_remove(current, "gross")


func set_night(v: float) -> void:
	night = v


# Neue Tischgröße: das laufende Ereignis endet sofort (Orte gelten nur für die Größe beim Start)
func on_layout() -> void:
	if table == null:
		return
	var sz := table.size
	if sz.is_equal_approx(_last_size):
		return
	_last_size = sz
	if current != null and not current.still:
		_remove(current, "groesse")


func _process(delta: float) -> void:
	if not auto_process:
		return
	if delta > PAUSE_S:                  # App war im Hintergrund: die Uhr stand
		_after_pause()
		delta = 0.0
	tick(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_paused_ms = Time.get_ticks_msec()
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if _paused_ms >= 0 and Time.get_ticks_msec() - _paused_ms > int(PAUSE_S * 1000.0):
			_after_pause()
		_paused_ms = -1


func _after_pause() -> void:
	due = maxf(due, now + NT.span("erst_s", rng))


# Zeit voranschalten
func tick(dt: float) -> void:
	dt = clampf(dt, 0.0, 5.0)
	now += dt
	if table == null:
		return
	if current != null:
		_step(current, dt)
	if auto_process and now - _plan_at < 0.25:
		return
	_plan_at = now
	_plan()


func _step(c: Running, dt: float) -> void:
	if c.still:
		return
	c.frames += 1
	c.run_s += dt
	if c.bridge:
		c.t += dt
		var sky: Variant = fun.get("sky") if fun != null else null
		if not (sky is Object) or not bool((sky as Object).call("active")):
			_finish(c)
		return
	c.node.call("step", dt)
	if bool(c.node.call("is_done")):
		_finish(c)


# ================================================================= Lage (4.4)

func _lage() -> Dictionary:
	var v := view
	var seat := int(v.get("seat", -1)) if v.get("seat") is int or v.get("seat") is float else -1
	var turn := int(v.get("turn", -1)) if v.get("turn") is int or v.get("turn") is float else -1
	var hints: Dictionary = v.get("hints", {}) if v.get("hints") is Dictionary else {}
	var pending: Dictionary = v.get("pending", {}) if v.get("pending") is Dictionary else {}
	var tease := _tease()
	var L := {
		"tisch": enabled and table != null and table.is_inside_tree() and table.is_visible_in_tree() and not v.is_empty(),
		"seite": "nacht" if night > 0.5 else "tag",
		"size": table.size if table != null else Vector2.ZERO,
		"gross": big,
		"reduziert": reduced,
		"phase": str(v.get("phase", "")),
		"mein_zug": seat >= 0 and turn == seat,
		"regie_leer": _director_idle(),
		"dialog": _dialog(),
		"fang": hints.get("catch") is Array and not (hints.get("catch") as Array).is_empty(),
		"necken": (tease.call("effects") as Array).size() if tease != null else 0,
		"strafe": int(pending.get("amount", 0)) > 0,
		"hand_sig": _hand_sig(),
		"gewaehlt": _hand_selected(),
		"hand_beruehrt": _hand_touched(),
		"andere": _others_running(),
		"katze_partie": _cat_this_game(),
	}
	for key in lage_override:
		L[key] = lage_override[key]
	return L


func _aktiv(L: Dictionary) -> bool:
	return bool(L["tisch"]) and not bool(L["gross"])


func _ruhe(L: Dictionary) -> bool:
	return _aktiv(L) and TURN_PHASES.has(L["phase"]) and bool(L["regie_leer"]) and now - _unrest >= float(NT.timing("ruhe_s")) \
		and not bool(L["dialog"]) and not bool(L["fang"]) and int(L["necken"]) == 0 and not bool(L["andere"])


func _tease() -> Object:
	if table == null:
		return null
	var t: Variant = table.get("tease")
	return t as Object if t is Object else null


func _director_idle() -> bool:
	if table == null:
		return true
	var d: Variant = table.get("director")
	if d is Object and bool((d as Object).call("is_busy")):
		return false
	if table.has_method("is_flipping") and bool(table.call("is_flipping")):
		return false
	return true


func _vis(n: Variant) -> bool:
	return n is CanvasItem and is_instance_valid(n) and (n as CanvasItem).visible


# Liegt etwas über dem Tisch (Rückfragen/Menüs von TableScreen über tease.modal_cb, Farbwahl, Hilfe, Rückseiten, Rundenende,
# Sichtschutz, „Ablage durchsehen“, Necken-Menü)?
func _dialog() -> bool:
	if table == null:
		return false
	var tease := _tease()
	if tease != null:
		var cb: Variant = tease.get("modal_cb")
		if cb is Callable and (cb as Callable).is_valid() and bool((cb as Callable).call()):
			return true
		var menu: Variant = tease.get("menu")
		if menu is Object and is_instance_valid(menu):
			return true
	var wp: Variant = table.get("wish_picker")
	if wp is Object and bool((wp as Object).call("is_open")):
		return true
	for key in ["help_popup", "backs_viewer", "round_end", "handover"]:
		if _vis(table.get(key)):
			return true
	var db: Variant = table.get("discard_browser")
	if db is Object and bool((db as Object).call("is_open")):
		return true
	return false


func _hand() -> Node:
	var h: Variant = table.get("hand") if table != null else null
	return h as Node if h is Node and is_instance_valid(h) else null


func _hand_sig() -> String:
	var h := _hand()
	if h == null or not h.has_method("get_order"):
		return ""
	return ",".join((h.call("get_order") as Array).map(func(x: Variant) -> String: return str(x)))


func _hand_selected() -> bool:
	var h := _hand()
	if h == null:
		return false
	if h.has_method("get_selected") and int(h.call("get_selected")) != -1:
		return true
	return h.has_method("is_big_view_open") and bool(h.call("is_big_view_open"))


func _hand_touched() -> bool:
	var h := _hand()
	if h == null:
		return false
	var tch: Variant = h.get("_touch")
	return (tch is int and int(tch) != -1) or (h.has_method("is_play_armed") and bool(h.call("is_play_armed")))


func _others_running() -> bool:
	if fun == null:
		return false
	var cat: Variant = fun.get("cat")
	if cat is Object and bool((cat as Object).call("active")):
		return true
	var sky: Variant = fun.get("sky")
	var bridge := current != null and current.bridge
	return sky is Object and bool((sky as Object).call("active")) and not bridge


func _cat_this_game() -> bool:
	if fun == null:
		return false
	var used: Variant = fun.get("cat_used")
	var cat: Variant = fun.get("cat")
	return (used is Dictionary and not (used as Dictionary).is_empty()) or (cat is Object and bool((cat as Object).call("active")))


func _cat_count() -> int:
	return int(fun.get("cats_started")) if fun != null else 0


# ================================================================= Planer (4.2)

func _plan() -> void:
	var L := _lage()
	if not bool(L["regie_leer"]):
		_unrest = now
	_observe(L)
	var aktiv := _aktiv(L)
	var was_table := _was_table
	_was_table = bool(L["tisch"])
	if not aktiv:
		_was_active = false
		if not bool(L["tisch"]) and was_table:
			demo = false                       # Tisch verlassen: Vorführung aus
		return
	if not _was_active:                        # Tischstart (auch nach großem Modus): erstes Ereignis nach erst_s
		_was_active = true
		due = now + NT.span("erst_s", rng)
	if demo:
		_demo_step(L)
		return
	if _troedeln(L):
		return
	if current != null or int(L["necken"]) > 0 or bool(L["andere"]):
		return
	var ruhe := _ruhe(L)
	if not flip_cue.is_empty():
		var f := flip_cue
		var at := float(f["at"])
		var side := str(f["side"])
		if now > at + float(NT.timing("flip_bis_s")) \
				or (side != L["seite"] and bool(L["regie_leer"]) and now > at + float(NT.timing("flip_nach_s")) + 1.0):
			flip_cue = {}                       # verfallen bzw. der Tisch hat die Seite gar nicht gewechselt
		elif ruhe and side == L["seite"] and now >= at + float(NT.timing("flip_nach_s")) \
				and now >= last_end + float(NT.timing("anlass_abstand_s")):
			flip_cue = {}                       # einmal würfeln
			if int(flip_round.get(side, 0)) < int(NT.timing("flip_je_runde")) and rng.randf() < float(NT.timing("flip_chance")):
				var id := NT.pick(NT.flip_pool(side, bool(L["reduziert"]), _foreign_blocked(L), counts, _exclude(L)), rng)
				if id != "" and _start(id, {"anlass": "flip"}):
					flip_round[side] = int(flip_round.get(side, 0)) + 1
			return
	if now >= due:
		if not ruhe:
			due = now + float(NT.timing("neuversuch_s"))
			return
		var id := NT.pick(NT.pool(str(L["seite"]), bool(L["reduziert"]), _foreign_blocked(L), counts, history[L["seite"]], _exclude(L)), rng)
		if id == "":
			due = now + 6.0 * float(NT.timing("neuversuch_s"))
			return
		if not _start(id, {"anlass": "zufall"}):
			due = now + float(NT.timing("neuversuch_s"))


# „fremder Zug“-Einträge gesperrt: ich bin dran oder meine Hand wird gerade berührt
func _foreign_blocked(L: Dictionary) -> bool:
	return bool(L["mein_zug"]) or bool(L["hand_beruehrt"])


func _exclude(L: Dictionary) -> Array:
	var out: Array = []
	for e in NT.entries():
		var id := str(e["id"])
		if not can_make(id):
			out.append(id)
		elif id == "komet" and now < comet_block_until:
			out.append(id)
		elif str(e["ort"]) == "ablage_ring" and bool(L["strafe"]):
			out.append(id)
		elif id == "sternbild" and bool(L["katze_partie"]):
			out.append(id)                      # nie, solange die Stapel-Katze aktiv ist oder sie in dieser Partie schon da war
	return out


# Trödeln (4.3): true = der Planer ist für diesen Takt fertig
func _troedeln(L: Dictionary) -> bool:
	var tr := troedel
	if str(tr["sig"]) != "" and not bool(tr["rolled"]) and TURN_PHASES.has(L["phase"]) \
			and now - float(tr["since"]) >= float(NT.timing("troedel_s")):
		tr["rolled"] = true
		var seat := int(tr["seat"])
		var e := NT.entry("schnecke")
		var cat_now := _cat_count() != int(tr["cats"]) or _cat_active()
		if seat >= 0 and not (tr["players"] as Dictionary).has(seat) and not e.is_empty() and str(e["seite"]) == L["seite"] \
				and can_make("schnecke") and not bool(L["reduziert"]) and not cat_now \
				and rng.randf() < float(NT.timing("troedel_chance")):
			snail_wait = {"seat": seat, "sig": tr["sig"], "displaced": false}
	if snail_wait.is_empty():
		return false
	var w := snail_wait
	if str(w["sig"]) != str(tr["sig"]) or bool(L["reduziert"]) or str(NT.entry("schnecke")["seite"]) != L["seite"] \
			or _cat_count() != int(tr["cats"]):
		snail_wait = {}                         # Zug vorbei, reduziert, andere Seite oder die Katze kam in diesem Zug
		return false
	var c := current
	if c != null:
		if c.id != "schnecke" and not c.leaving() and not c.still:
			_leave(c, "schnecke")
			w["displaced"] = true
		return true
	if int(L["necken"]) > 0 or not _ruhe(L):
		return true                             # jede Sekunde neu versuchen, solange der Zug dauert
	if not bool(w["displaced"]) and now < last_end + float(NT.timing("anlass_abstand_s")):
		return true
	snail_wait = {}
	if _start("schnecke", {"anlass": "troedeln", "troedler": int(w["seat"])}):
		(tr["players"] as Dictionary)[int(w["seat"])] = true
	return true


func _cat_active() -> bool:
	if fun == null:
		return false
	var cat: Variant = fun.get("cat")
	return cat is Object and bool((cat as Object).call("active"))


# Vorführung (4.7): alle vorfuehr_abstand_s das nächste Ereignis der Seite in Tabellenreihenfolge (ohne je_partie, Sperre, fremder_zug)
func _demo_step(L: Dictionary) -> void:
	if current != null or bool(L["dialog"]) or now < demo_next:
		return
	var ids: Array = []
	for e in NT.entries():
		if str(e["seite"]) == L["seite"] and can_make(str(e["id"])) and (not bool(L["reduziert"]) or bool(e["ruhig"])):
			ids.append(str(e["id"]))
	if ids.is_empty():
		return
	var side := str(L["seite"])
	var pos := (int(demo_pos[side]) + 1) % ids.size()
	demo_pos[side] = pos
	demo_next = now + float(NT.timing("vorfuehr_abstand_s"))
	_start(str(ids[pos]), {"anlass": "demo", "troedler": int(view.get("turn", -1))})


func set_demo(on: bool) -> void:
	if on == demo:
		return
	demo = on
	demo_next = now
	if not on:
		if current != null and not current.still:
			_leave(current, "demo")
		due = maxf(due, now + NT.span("abstand_s", rng))


# ================================================================= Sicht und Ereignisse

func on_view(v: Dictionary) -> void:
	view = v
	var top_id := -1
	if v.get("top") is Dictionary:
		top_id = int((v["top"] as Dictionary).get("id", -1))
	var sig := "%s|%d|%d" % [str(v.get("turn", -1)), top_id, int(v.get("draw_count", 0))]
	if sig == str(troedel["sig"]):
		return
	troedel["sig"] = sig
	troedel["since"] = now
	troedel["rolled"] = false
	troedel["seat"] = int(v.get("turn", -1)) if v.get("turn") is int or v.get("turn") is float else -1
	troedel["cats"] = _cat_count()
	if not snail_wait.is_empty() and str(snail_wait["sig"]) != sig:
		snail_wait = {}
	var c := current
	if c != null and c.id == "schnecke" and not c.still and c.anlass != "zeige":
		_leave(c, "zugende")


# Ereignis der Tischregie (play_event und skip_event)
func on_event(ev: Dictionary) -> void:
	_unrest = now
	var k := str(ev.get("e", ""))
	var c := current if current != null and not current.still else null
	if k == "flip":
		var s := _side_of(ev)
		if c != null and str(c.e["seite"]) != s:
			_leave(c, "flip")
		flip_cue = {"side": s, "at": now}
	elif ALL_GO.has(k):
		if c != null:
			_leave(c, k)
		flip_cue = {}
		snail_wait = {}
		if k == "round_start":
			counts["runde"] = {}
			flip_round = {}
			if int(ev.get("round", 0)) == 1:
				counts["partie"] = {}
				troedel["players"] = {}
	elif FRONT_GO.has(k):
		if c != null and (c.layer == "vorn" or bool(c.e.get("fremder_zug", false))):
			_leave(c, k)
	elif k == "skip_all":
		comet_block_until = now + float(NT.timing("komet_sperre_s"))
	var cc := current if current != null and not current.still else null
	if cc == null or cc.leaving():
		return
	var place: Array = PLACE_GO.get(str(cc.e["ort"]), [])
	if place.has(k):
		_leave(cc, k)
		return
	var me := int(view.get("seat", -1)) if view.get("seat") is int or view.get("seat") is float else -1
	if str(cc.e["ort"]) == "handkarte" and HAND_GO.has(k) and ev.get("seat") != null and int(ev.get("seat", -2)) == me:
		_leave(cc, k)
		return
	if cc.node != null and bool(cc.node.call("on_event", ev)):
		_leave(cc, k)


func _side_of(ev: Dictionary) -> String:
	var s := str(ev.get("side", ""))
	if s == "":
		s = "hell" if str(view.get("side", "hell")) == "dunkel" else "dunkel"
	return "nacht" if s == "dunkel" or s == "nacht" else "tag"


# ================================================================= Abgang und Abbruch (4.5)

func _observe(L: Dictionary) -> void:
	var alt := _alt
	_alt = {"size": L["size"], "necken": L["necken"], "hand_sig": L["hand_sig"], "seite": L["seite"]}
	var c := current
	if c == null or c.still:
		return
	if not _aktiv(L):
		_remove(c, "gross" if bool(L["gross"]) else "tisch")
		return
	if not alt.is_empty() and not (alt["size"] as Vector2).is_equal_approx(L["size"]):
		_remove(c, "groesse")
		return
	if bool(L["reduziert"]) and not bool(c.e["ruhig"]):
		_remove(c, "reduziert")
		return
	if c.leaving():
		return
	if str(c.e["seite"]) != L["seite"] and c.anlass != "zeige":
		_leave(c, "seite")
		return
	var front := c.layer == "vorn"
	var foreign := front or bool(c.e["fremder_zug"])
	if foreign and (bool(L["mein_zug"]) or bool(L["fang"])):
		_leave(c, "mein_zug" if bool(L["mein_zug"]) else "erwischt")
		return
	if front and not TURN_PHASES.has(L["phase"]):
		_leave(c, "phase")                    # Glücksspiel, Ablege-/Farbauswahl, Rundenende
		return
	if front and bool(L["dialog"]):
		_leave(c, "dialog")
		return
	if front and not alt.is_empty() and int(L["necken"]) > int(alt["necken"]):
		_leave(c, "necken")
		return
	if (c.e["deckt"] as Array).has("hand") and (bool(L["gewaehlt"]) or bool(L["hand_beruehrt"])
			or (not alt.is_empty() and str(alt["hand_sig"]) != str(L["hand_sig"]))):
		_leave(c, "hand")


# Schnell abgehen (Tier fliegt weg bzw. blendet aus; Bestand hört sofort auf)
func _leave(c: Running, reason: String) -> void:
	if c == null or c.leaving():
		return
	c.reason = reason
	if c.bridge:
		_stop_sky()
		_finish(c)
		return
	c.node.call("leave", true)
	if bool(c.node.call("is_done")):
		_finish(c)


# Sofort entfernen (Größe, großer Modus, reduziert, Tisch weg)
func _remove(c: Running, reason: String) -> void:
	if c.reason == "":
		c.reason = reason
	if c.bridge:
		_stop_sky()
	_finish(c)


func _stop_sky() -> void:
	var sky: Variant = fun.get("sky") if fun != null else null
	if sky is Object:
		(sky as Object).call("stop")


func _finish(c: Running) -> void:
	if current != c:
		return
	if c.node != null and is_instance_valid(c.node):
		var p := c.node.get_parent()
		if p != null:
			p.remove_child(c.node)
		c.node.queue_free()
	current = null
	var fps := int(round(float(c.frames) / c.run_s)) if c.run_s > 0.05 else int(Engine.get_frames_per_second())
	if c.anlass != "zeige":
		if c.anlass != "demo":
			due = now + NT.span("abstand_s", rng) * (float(NT.timing("reduziert_faktor")) if reduced else 1.0)
			var h: Array = history[str(c.e["seite"])]
			h.append(c.id)
			if h.size() > 8:
				h.pop_front()
		else:
			demo_next = maxf(demo_next, now + 0.5)
		last_end = now
	_log({"was": "ende", "id": c.id, "now": now, "anlass": c.anlass, "grund": c.reason, "dauer": c.time(), "fps": fps})
	if print_log:
		print("NatureFx: ende %s fps=%d" % [c.id, fps])
	ended.emit(c.id)


func _log(z: Dictionary) -> void:
	protocol.append(z)
	if auto_process and protocol.size() > LOG_MAX:
		protocol.pop_front()


# ================================================================= Start

func _start(id: String, o: Dictionary) -> bool:
	var e := NT.entry(id)
	if e.is_empty() or table == null or layers.is_empty():
		return false
	var sd: int = int(o["seed"]) if o.get("seed", -1) is int and int(o.get("seed", -1)) >= 0 else int(rng.randi())
	var L := _lage()
	var c := Running.new()
	c.id = id
	c.e = e
	c.seed_value = sd
	c.anlass = str(o.get("anlass", ""))
	c.layer = str(e["ebene"])
	if bool(e["bestand"]):
		var sky: Variant = fun.get("sky") if fun != null else null
		if not (sky is Object):
			return false
		var r := RandomNumberGenerator.new()
		r.seed = sd
		(sky as Object).set("glow", night)
		(sky as Object).call("launch", id == "sternschnuppe", r, table.size)
		c.bridge = true
	else:
		var node := _make(id)
		if node == null:
			return false
		var ctx := _ctx(e, sd, L, o)
		node.call("init_creature", id, sd, ctx, self)
		var lay := str(node.get("layer"))
		if not layers.has(lay):
			lay = str(e["ebene"])
		c.layer = lay
		(layers[lay] as Node2D).add_child(node)
		c.node = node
	current = c
	if c.anlass != "zeige" and c.anlass != "demo":
		counts["partie"][id] = int(counts["partie"].get(id, 0)) + 1
		counts["runde"][id] = int(counts["runde"].get(id, 0)) + 1
	_log({"was": "start", "id": id, "now": now, "anlass": c.anlass, "seite": e["seite"], "tisch_seite": L["seite"],
		"mein_zug": L["mein_zug"], "seed": sd})
	if print_log:
		print("NatureFx: start %s" % id)
	started.emit(id)
	return true


func _make(id: String) -> Node2D:
	if make_cb.is_valid():
		return make_cb.call(id) as Node2D
	return make(id)


# Tier zu einer id aus nature_day.gd/nature_night.gd (null = unbekannt oder Datei fehlt)
static func make(id: String) -> Node2D:
	var e := NT.entry(id)
	if e.is_empty() or bool(e.get("bestand", false)):
		return null
	var paths := [DAY_PATH, NIGHT_PATH] if str(e["seite"]) == "tag" else [NIGHT_PATH, DAY_PATH]
	for path in paths:
		if not ResourceLoader.exists(path):
			continue
		var s := load(path) as Script
		if s == null:
			continue
		var has := false
		for m in s.get_script_method_list():
			if str(m.get("name", "")) == "make":
				has = true
				break
		if not has:
			continue
		var n: Variant = s.call("make", id)
		if n is Node2D:
			return n
		if n is Node:
			(n as Node).free()
	return null


# Gibt es zu id etwas zu zeigen? (Bestand: FunFx.SkyNode; Tier: make(id); gemerkt je id)
func can_make(id: String) -> bool:
	var e := NT.entry(id)
	if e.is_empty():
		return false
	if bool(e["bestand"]):
		return fun != null and fun.get("sky") is Object
	if make_cb.is_valid():
		return true
	if not _makeable.has(id):
		var n := make(id)
		_makeable[id] = n != null
		if n != null:
			n.free()
	return bool(_makeable[id])


# ================================================================= Für FunFx (Mau-Katze hat Vorrang)

func busy() -> bool:
	return current != null


func make_room() -> void:
	if current != null and not current.still:
		_leave(current, "katze")


# ================================================================= Tippen und Scheu (4.6)

# Jeder Druck auf den Tisch (Weltkoordinaten); verbraucht nie etwas
func notice_press(wp: Vector2) -> void:
	if table == null:
		return
	var L := _lage()
	if not _aktiv(L):
		return
	var c := current
	if c == null or c.still or c.bridge or c.leaving() or not bool(c.e["scheu"]):
		return
	var at_place := false
	var deckt: Array = c.e["deckt"]
	if deckt.has("hand"):
		for r in _hand_rects():
			at_place = at_place or (r as Rect2).has_point(wp)
	if deckt.has("stapel"):
		at_place = at_place or _pile_rect().grow(12.0).has_point(wp)
	var b := world_bounds()
	if at_place or (b.has_area() and _rect_dist(wp, b) <= float(NT.timing("scheu_r"))):
		c.node.call("on_press", _to_layer(c, wp))
		_leave(c, "scheu")


# Tipp ins Leere (letzter Fall in TableView._tap, Weltkoordinaten); true nur bei einer Reaktion eines Tiers
func tap(wp: Vector2) -> bool:
	if table == null:
		return false
	var L := _lage()
	if not _aktiv(L):
		return false
	var obs := obstacles()
	for key in obs:
		for r in obs[key]:
			if (r as Rect2).has_point(wp):
				return false
	var c := current
	if c != null and not c.still and not c.bridge:
		var lp := _to_layer(c, wp)
		if bool(c.node.call("hit", lp)):
			if str(c.e["tipp"]) != "" and not c.tapped and not c.leaving():
				c.tapped = true
				c.node.set("tap_at", float(c.node.get("t")))
				c.node.set("tap_pos", lp)
				c.node.call("on_tap", lp)
				return true
			return false                        # Tier ohne Reaktion: keine Vorführungs-Zählung
	_demo_tap(wp)
	return false


# 7 Tipps in 4 s auf eine freie Stelle (höchstens 80 px auseinander) schalten die Vorführung ein bzw. aus
func _demo_tap(p: Vector2) -> void:
	var win := float(NT.timing("vorfuehr_fenster_s"))
	_taps = _taps.filter(func(x: Dictionary) -> bool: return now - float(x["at"]) <= win and (x["p"] as Vector2).distance_to(p) <= 80.0)
	_taps.append({"p": p, "at": now})
	if _taps.size() >= int(NT.timing("vorfuehr_tipps")):
		_taps.clear()
		set_demo(not demo)


static func _rect_dist(p: Vector2, r: Rect2) -> float:
	return Vector2(maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x), maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)).length()


# ================================================================= Tests, Kontrollbilder, Vorführung

# Ereignis ohne Bedingungen starten (Tests, Kontrollbilder); opts: t (gleich dorthin springen), still (eingefroren), troedler
func spawn(id: String, sd := -1, opts := {}) -> bool:
	if current != null:
		_remove(current, "zeige")
	var o := {"seed": sd, "anlass": str(opts.get("anlass", "zeige")), "troedler": int(opts.get("troedler", -1))}
	if not _start(id, o):
		return false
	current.still = bool(opts.get("still", false))
	if opts.has("t"):
		seek(float(opts["t"]))
	return true


func creature() -> Node2D:
	return current.node if current != null else null


func seek(tt: float) -> void:
	if current != null and current.node != null:
		current.node.call("seek", tt)


func clear() -> void:
	if current != null:
		_remove(current, "clear")


# Hülle des laufenden Tiers in Weltkoordinaten (Rect2() = nichts)
func world_bounds() -> Rect2:
	var c := current
	if c == null or c.node == null:
		return Rect2()
	var b: Rect2 = c.node.call("bounds")
	if not b.has_area():
		return Rect2()
	return _layer_to_world(c.layer) * b


func _layer_to_world(lay: String) -> Transform2D:
	var n: Node2D = layers.get(lay)
	if n == null or _world == null or not n.is_inside_tree() or not _world.is_inside_tree():
		return Transform2D.IDENTITY
	return _world.get_global_transform().affine_inverse() * n.get_global_transform()


func _to_layer(c: Running, wp: Vector2) -> Vector2:
	return _layer_to_world(c.layer).affine_inverse() * wp


# ================================================================= Orte und Schutzflächen (2.2 / 2.3)

func _wx() -> Transform2D:
	if _world == null or not _world.is_inside_tree():
		return Transform2D.IDENTITY
	return _world.get_global_transform().affine_inverse()


func _canvas_to_world() -> Transform2D:
	if _world == null or not _world.is_inside_tree():
		return Transform2D.IDENTITY
	return _world.get_global_transform_with_canvas().affine_inverse()


func _size() -> Vector2:
	return table.size if table != null and table.size.x > 10.0 else TableLayout.BASE


func _center() -> Vector2:
	if table != null and table.has_method("table_center"):
		return table.call("table_center")
	return TableLayout.table_center(_size())


func _pile_w() -> float:
	return float(table.get("pile_w")) if table != null and table.get("pile_w") != null else 116.0


func _pile_rect() -> Rect2:
	var p: Vector2 = table.call("draw_pile_position") if table != null else TableLayout.draw_pile_pos(_size())
	var w := _pile_w()
	var h := w * 466.0 / 300.0
	return Rect2(p - Vector2(w, h) * 0.5, Vector2(w, h))


func _hand_rects() -> Array:
	var h := _hand()
	if h == null or not h.has_method("cards_rect") or not (h is Node2D) or not (h as Node2D).is_inside_tree():
		return []
	var r: Rect2 = h.call("cards_rect")
	if not r.has_area():
		return []
	var w := (_wx() * (h as Node2D).get_global_transform()) * r
	var clip := Rect2(Vector2.ZERO, _size())
	return [w.intersection(clip)] if w.intersects(clip) else []


# Kopf eines Platzes (Avatar, Name, Kartenzahl) in Weltkoordinaten
func _head_rect(node: Node2D) -> Rect2:
	var ar := float(node.call("avatar_radius"))
	var hw := float(node.call("header_width"))
	var x0 := float(node.call("_header_x0"))
	return (_wx() * node.get_global_transform()) * Rect2(x0 - 6.0, -ar - 8.0, hw + 12.0, ar * 2.0 + 16.0)


# Kopf und Fächer (wie OpponentSeat.hit_fan)
func _seat_rect(node: Node2D) -> Rect2:
	var fmw := maxf(float(node.get("fan_max_w")), OpponentSeat.BAR_W)
	var hh := float(node.call("header_height"))
	var cw := float(node.get("card_w"))
	return (_wx() * node.get_global_transform()) * Rect2(-fmw * 0.5 - 10.0, -hh * 0.6, fmw + 20.0, hh + cw * 1.9 + 20.0)


func _seat_nodes() -> Array:
	var out: Array = []
	if table == null:
		return out
	var seats: Variant = table.get("_seats")
	if seats is Dictionary:
		for s in seats:
			var n: Variant = seats[s]
			if n is Node2D and is_instance_valid(n) and (n as Node2D).is_visible_in_tree():
				out.append(n)
	return out


# Köpfe der Plätze [{seat, pos, rect, me}]
func seats() -> Array:
	var out: Array = []
	for n in _seat_nodes():
		var r := _head_rect(n)
		out.append({"seat": int(n.get("seat")), "pos": r.get_center(), "rect": r, "me": false})
	var me: Variant = table.get("me_badge") if table != null else null
	if me is Node2D and (me as Node2D).is_visible_in_tree():
		var r := _head_rect(me)
		out.append({"seat": int(view.get("seat", -1)), "pos": r.get_center(), "rect": r, "me": true})
	return out


func _ctl_rect(n: Variant) -> Rect2:
	if not (n is Control) or not is_instance_valid(n) or not (n as Control).is_visible_in_tree():
		return Rect2()
	var c := n as Control
	return (_canvas_to_world() * c.get_global_transform_with_canvas()) * Rect2(Vector2.ZERO, c.size)


# Schutzflächen (2.3) in Weltkoordinaten: Name → Array[Rect2]
func obstacles() -> Dictionary:
	var out := {}
	if table == null:
		return out
	var add := func(key: String, r: Rect2, grow: float) -> void:
		if r.has_area():
			if not out.has(key):
				out[key] = []
			(out[key] as Array).append(r.grow(grow))
	var sz := _size()
	for r in _hand_rects():
		add.call("hand", r, 0.0)
	var pr := _pile_rect()
	add.call("stapel", pr, 12.0)
	var dp: Vector2 = table.call("discard_position")
	var rr := RING_R + 8.0
	add.call("ablage", Rect2(dp - Vector2(rr, rr), Vector2(rr, rr) * 2.0), 0.0)
	for n in _seat_nodes():
		add.call("platz", _seat_rect(n), 0.0)
		add.call("platz", _head_rect(n), 0.0)
		if bool(n.get("catchable")):
			add.call("erwischt", (_wx() * (n as Node2D).get_global_transform()) * (n.call("_catch_rect") as Rect2), 18.0)
	var me: Variant = table.get("me_badge")
	if me is Node2D and (me as Node2D).is_visible_in_tree():
		add.call("name", _head_rect(me), 0.0)
	var hb: Variant = table.get("hint_bar")
	if hb is Object:
		var hy := float((hb as Object).get("hint_y"))
		var hh := float((hb as Object).call("hint_h"))
		add.call("leiste", Rect2(sz.x * 0.5 - 330.0, hy - hh * 0.5 - 6.0, 660.0, hh + 12.0), 0.0)
	add.call("mau", _ctl_rect(table.get("mau_button")), 0.0)
	add.call("sortieren", _ctl_rect(table.get("_sort_btn")), 0.0)
	add.call("rueckseiten", _ctl_rect(table.get("_backs_btn")), 0.0)
	var acts: Variant = table.get("_act_btns")
	if acts is Dictionary:
		for key in acts:
			add.call("knopf", _ctl_rect(acts[key]), 0.0)
	var gm: Variant = table.get("gamble_machine")
	if gm is Node2D and bool((gm as Node2D).get("active")) and (gm as Node2D).visible:
		add.call("automat", (_wx() * (gm as Node2D).get_global_transform()) * Rect2(-110.0, -130.0, 220.0, 300.0), 0.0)
	var sp: Variant = table.get("stake_pile")
	if sp is Node2D and (sp as Node2D).is_visible_in_tree() and (sp as Node2D).get_child_count() > 0:
		add.call("einsatz", Rect2((sp as Node2D).position - Vector2(90.0, 120.0), Vector2(180.0, 240.0)), 0.0)
	var cm: Variant = table.get("_color_mark")
	if cm is Node2D and str((cm as Node2D).get("color_key")) != "":
		var kk := float((cm as Node2D).get("k"))
		add.call("farbe", Rect2((cm as Node2D).position + Vector2(-62.0, -48.0) * kk, Vector2(124.0, 104.0) * kk), 8.0)
	var pw := _pile_w()
	add.call("stapelzahl", Rect2(pr.get_center().x - 72.0, pr.end.y + 2.0, 144.0, 34.0 * pw / 116.0), 4.0)
	add.call("oben_links", TOP_LEFT, 0.0)
	var tease := _tease()
	if tease != null and tease.has_method("obstacles"):
		for r in tease.call("obstacles"):
			add.call("reaktionen", _canvas_to_world() * (r as Rect2), 0.0)
	return out


static func _overlap(a: Rect2, b: Rect2) -> float:
	var i := a.intersection(b)
	return i.get_area() if a.intersects(b) else 0.0


# Punkt auf der Richtungs-Plattform relativ zur Tischmitte, wie DirectionRing._rebuild (Superellipse, Kippung, Perspektive):
# deg 0 = rechts, 90 = vorn (im Uhrzeigersinn, Parameterwinkel wie DirectionRing.point_at); quer 0 Innenkante, 0,5 Mitte, 1 Außenkante.
static func band_point(radii: Vector2, deg: float, quer := 0.5) -> Vector2:
	var st: Dictionary = DirectionRing.STYLES[DirectionRing.STYLE_DEFAULT]
	var fx := radii.x / 330.0
	var fy := radii.y / 160.0
	var hole: Vector2 = st["hole"]
	var ai := maxf(hole.x * fx, DirectionRing.HOLE_MIN_X)
	var bi := hole.y * fy / DirectionRing.TILT
	var bw := float(st["band"]) * minf(fx, fy)
	var zref := bi + bw
	var sq := DirectionRing.SQUARE
	var yf := _proj(Vector2(0, bi), zref).y
	var yb := _proj(Vector2(0, -bi), zref).y
	var yoff := DirectionRing.HOLE_DY * fy - (yf + yb) * 0.5
	var a := deg_to_rad(deg)
	var c := cos(a)
	var s := sin(a)
	var q := Vector2(ai * signf(c) * pow(absf(c), 2.0 / sq), bi * signf(s) * pow(absf(s), 2.0 / sq))
	var n := Vector2(signf(q.x) * pow(absf(q.x) / ai, sq - 1.0) / ai, signf(q.y) * pow(absf(q.y) / bi, sq - 1.0) / bi).normalized()
	return _proj(q + n * bw * quer, zref) + Vector2(0, yoff)


static func _proj(p: Vector2, zref: float) -> Vector2:
	var s := 1.0 / (1.0 - DirectionRing.PERSP * p.y / zref)
	return Vector2(p.x * s, DirectionRing.TILT * p.y * s)


func _radii() -> Vector2:
	if _ring != null and _ring.get("radii") is Vector2:
		return _ring.get("radii")
	return TableLayout.ring_radii(_size())


# Punkt auf der Plattform in Weltkoordinaten (ctx.band)
func band_world(deg: float, quer := 0.5) -> Vector2:
	return _center() + band_point(_radii(), deg, quer)


# Mittlere sichtbare Handkarte {id, pos, rot, size, xf, rect} in Weltkoordinaten ({} ohne Hand). Sichtbar = Oberkante im Bild (nur der
# obere Teil der Karten ist zu sehen, AGENTS 8).
func hand_card() -> Dictionary:
	var h := _hand()
	if h == null or not h.has_method("get_order") or not (h as Node2D).is_inside_tree():
		return {}
	var slots: Variant = h.get("_slots")
	if not (slots is Dictionary):
		return {}
	var sz := _size()
	var vis: Array = []
	for id in h.call("get_order"):
		var s: Variant = (slots as Dictionary).get(id)
		if s == null or not (s.get("view") is Node2D):
			continue
		var cv: Node2D = s.get("view")
		var xf := _wx() * cv.get_global_transform()
		var w := float(cv.get("width"))
		var csz := Vector2(w, w * 466.0 / 300.0)
		var rect := xf * Rect2(-csz * 0.5, csz)
		if xf.origin.x > 0.0 and xf.origin.x < sz.x and rect.position.y < sz.y - 20.0:
			vis.append({"id": int(id), "pos": xf.origin, "rot": xf.get_rotation(), "size": csz, "xf": xf, "rect": rect})
	if vis.is_empty():
		return {}
	return vis[(vis.size() - 1) / 2]


# Alle Anker (2.2) in Weltkoordinaten; z würfelt kleine Abweichungen (Startsamen), troedler = Ziel der Schnecke
func anchors(z: RandomNumberGenerator = null, troedler := -1) -> Dictionary:
	if z == null:
		z = RandomNumberGenerator.new()
		z.seed = 1
	var sz := _size()
	var W := sz.x
	var H := sz.y
	var C := _center()
	var radii := _radii()
	var obs := obstacles()
	var heads := seats()
	var hint_y := sz.y - 207.0
	var hb: Variant = table.get("hint_bar") if table != null else null
	if hb is Object:
		hint_y = float((hb as Object).get("hint_y"))
	# freiester Winkel auf dem Band (5°-Schritte, kleiner Zufall gegen immer denselben Platz)
	var freedom := func(p: Vector2) -> float:
		var d := 1.0e9
		for q in heads:
			var r: Rect2 = q["rect"]
			d = minf(d, p.distance_to(r.get_center()) - maxf(r.size.x, r.size.y) * 0.5)
		for key in obs:
			if key == "hand":
				continue
			for r in obs[key]:
				d = minf(d, _rect_dist(p, r) + 40.0)
		return d
	var best_deg := func(ranges: Array) -> float:
		var best: float = float(ranges[0][0])
		var bw := -1.0e9
		for rg in ranges:
			var w := float(rg[0])
			while w <= float(rg[1]) + 1e-6:
				var sc: float = freedom.call(C + band_point(radii, w)) + z.randf() * 12.0
				if sc > bw:
					bw = sc
					best = w
				w += 5.0
		return best
	# Himmel
	var moon := Vector2(W * 0.94, H * 0.08)            # table_background.gdshader: (size.x * 0.94, size.y * (1.12 - 1.04 * t)), Nacht
	var sun := Vector2(W * 0.07, H * 0.03)             # table_background.gdshader: (size.x * 0.07, size.y * (0.03 + 1.05 * t)), Tag
	var free_r := Rect2()
	var free_k := INF
	for f in [0.18, 0.32, 0.50, 0.66]:
		var r := Rect2(f * W - 120.0, 0.02 * H + 4.0, 240.0, 160.0)
		var k := 0.0
		for q in heads:
			k += _overlap(r, q["rect"])
		if r.get_center().distance_to(moon) < 200.0:
			k += 1.0e7
		if r.intersects(TOP_LEFT):
			k += 1.0e6
		if k < free_k:
			free_k = k
			free_r = r
	# Band zum Trödler
	var target := troedler if troedler >= 0 else int(view.get("turn", -1))
	var to_seat := 115.0
	for q in heads:
		if int(q["seat"]) == target and not bool(q["me"]):
			var p: Vector2 = q["pos"]
			to_seat = fposmod(rad_to_deg(atan2((p.y - C.y) / radii.y, (p.x - C.x) / radii.x)), 360.0)
			if to_seat >= 66.0 and to_seat <= 114.0:
				to_seat = 65.0 if to_seat < 90.0 else 115.0
	# Aufsteigend: der Spalt mit mehr Abstand zu den Plätzen
	var gaps := [[0.25, 0.40], [0.60, 0.75]]
	var gd: Array = []
	for g in gaps:
		var d := 1.0e9
		var mid := (float(g[0]) + float(g[1])) * 0.5 * W
		for q in heads:
			if not bool(q["me"]):
				var p: Vector2 = q["pos"]
				d = minf(d, absf(p.x - mid) + absf(p.y - C.y) * 0.5)
		gd.append(d)
	var gap: Array = gaps[0] if float(gd[0]) >= float(gd[1]) else gaps[1]
	var pr := _pile_rect()
	var dp: Vector2 = table.call("discard_position") if table != null else TableLayout.discard_pos(sz)
	return {
		"himmel": Rect2(0, 0.04 * H, W, 0.26 * H),
		"himmel_oben": Rect2(0, 0.02 * H, W, 0.18 * H),
		"himmel_fern": Rect2(0, 0.06 * H, W, 0.12 * H),
		"himmel_frei": free_r,
		"himmel_bogen": {"center": Vector2(C.x, C.y + 40.0), "r": 0.46 * W},
		"sonne": {"pos": sun, "r": 64.0},
		"mond": {"pos": moon, "r": 40.0, "cut": Vector2(17.0, -12.0)},
		"band_hinten": {"deg": best_deg.call([[240.0, 300.0]])},
		"band_schulter": {"deg": best_deg.call([[200.0, 215.0], [325.0, 340.0]])},
		"band_vorn_seite": {"deg": best_deg.call([[115.0, 160.0], [20.0, 65.0]])},
		"band_zum_platz": {"deg": to_seat, "seat": target},
		"tisch_quer": Rect2(0, C.y - radii.y - 60.0, W, 80.0),
		"tisch_rund": {"center": C, "radii": radii, "f0": 1.05, "f1": 1.45, "ymax": hint_y - 40.0},
		"handkarte": hand_card(),
		"stapel_oben": {"pos": Vector2(pr.get_center().x, pr.position.y - 62.0), "pile": pr},
		"ablage_ring": {"pos": dp, "r": RING_R},
		"aufsteigend": {"pos": Vector2((float(gap[0]) + z.randf() * (float(gap[1]) - float(gap[0]))) * W, C.y), "target_y": -80.0},
	}


func _ctx(e: Dictionary, sd: int, L: Dictionary, o: Dictionary) -> Dictionary:
	var z := RandomNumberGenerator.new()
	z.seed = sd ^ 0x9E3779B9
	var tr := int(o.get("troedler", -1))
	var an := anchors(z, tr)
	var obs := obstacles()
	var me := int(view.get("seat", -1)) if view.get("seat") is int or view.get("seat") is float else -1
	return {
		"id": str(e["id"]), "entry": e, "size": _size(), "center": _center(), "side": str(e["seite"]), "night": night,
		"reduced": bool(L["reduziert"]), "calm": bool(L["reduziert"]) and bool(e["ruhig"]), "timing": NT.DATA["zeiten"],
		"form": e.get("form", {}), "layer": str(e["ebene"]), "ort": an.get(str(e["ort"]), {}), "anchors": an,
		"band": Callable(self, "band_world"), "ring_radii": _radii(), "seats": seats(), "obstacles": obs,
		"free": Callable(self, "_overlap_sum").bind(obs),
		"hand": Callable(self, "hand_card"),
		"troedler": tr if tr >= 0 else int(view.get("turn", me)), "my_seat": me, "demo": str(o.get("anlass", "")) == "demo",
	}


# Überdeckung von r mit allen Schutzflächen (px²; ctx.free)
func _overlap_sum(r: Rect2, obs: Dictionary) -> float:
	var s := 0.0
	for key in obs:
		for q in obs[key]:
			s += _overlap(r, q)
	return s
