class_name MauGame
extends RefCounted
# Regelwerk (docs/BETA1_PLAN.md Abschnitt 4, Regeln nach docs/recherche/07_regeln_hausregeln.md 1.1–1.13 und Hausregeln):
# deterministische Zustandsmaschine ohne Nodes. Plätze handeln über apply(); view_for() enthält nur, was ein Platz sehen darf,
# events_for() filtert die Ereignisse eines apply() je Empfänger. Zufall nur aus dem eigenen RandomNumberGenerator, der ganze
# Zustand steckt in to_dict() (JSON-tauglich).
#
# Karten: ids 0 bis n_cards − 1 (112, mit den Hausregeln Kartentausch +4, Glücksspiel +2, Farbe mit ablegen +6; n_cards folgt
# aus config.card_count()).
# faces[s * n_cards + id] = Gesichtscode (CardDB) der Seite s (0 hell, 1 dunkel). Paarung hell↔dunkel und
# ids werden je Runde aus dem Seed neu gemischt. Stapel sind Arrays, oben = letztes Element. Alle Karten liegen gleich
# ausgerichtet: Ein Flip kehrt beide Stapel um und schaltet die aktive Seite; Hände wenden sich dadurch von selbst.
# Bei flip_mode = card bleibt die Ablage in ihrer Reihenfolge, oben liegt die andere Seite der Flip-Karte; die Karten darunter
# gelten als zur Seite gelegt und zeigen im Ablage-Protokoll die Seite, mit der sie lagen (dside, nur in diesem Modus).
#
# Abläufe (Kurzfassung):
# - Ziehkarte → offene Strafe (pending). Wünscher +2/Farbjagd bei wild_restriction=bluff: Phase "challenge" für das Opfer.
#   Sonst bei stacking=same: Opfer ist normal dran und darf nur die gleiche Ziehkarte legen oder ziehen (= Strafe nehmen).
#   Sonst zieht das Opfer sofort und setzt aus.
# - Flip → Joker oben: Phase "color", der Flip-Spieler wählt mit {a:"color"} (Abweichung vom Plan, dort dokumentiert).
# - Mau: Fenster von „2 Karten, am Zug und eine Karte legbar“ bis zur ersten Zughandlung (play/draw/challenge/accept) des
#   nächsten handelnden Spielers; mau_open = Platz, der auf 1 Karte kam, ohne zu rufen (bei catch erwischbar, bei auto Strafe
#   beim Fensterende, bei reminder nur nachträglich rufbar). Ein Opfer, das automatisch zieht, oder ein Übersprungener handelt
#   nicht selbst und schließt das Fenster daher nicht (Absicht: Zeit zum Erwischen, passt zur Schonfrist im Netz).
# - Gastgeber: players[i].host = true markiert den Platz, der die nächste Runde startet (Standard Platz 0).
# - Aktionen kommen auch als freies JSON aus dem Netz: Felder werden typgeprüft, Falsches wird mit Begründung abgelehnt.
# - Letzte Karte: Wünscher +2/Farbjagd im Bluff-Modus → erst anzweifeln, dann fertig (finisher). Sonst fertig; endet die Runde,
#   wirkt eine Ziehkarte noch (Nächster zieht). Ein Flip als letzte Karte wird nur bei flip_last_card=execute ausgeführt
#   (bei ignore nie, auch nicht, wenn die Runde bei round_end=last weiterläuft).
# - Ende ohne Sieger durch Legen: Passen alle reihum (beide Stapel leer) oder wiederholt sich bei fast leeren Stapeln dieselbe
#   Lage zum dritten Mal (_stalled), endet die Runde als „blockiert“; vorn liegt, wer die wenigsten Karten hat.
# - Kartentausch (swap_cards = on): Alle aktiven Spieler geben ihre ganze Hand gleichzeitig an den nächsten aktiven Platz in
#   Tauschrichtung weiter (Ereignis swap_hands), danach ist der Nächste in Spielrichtung dran. Mau-Fenster und Rufe verfallen.
#   Als letzte Karte: fertig wie sonst; der Tausch läuft nur unter den Übrigen und entfällt, wenn die Runde damit endet.
# - Glücksspiel (gamble_cards = on): Joker mit Farbwahl, danach Phase "gamble" für den Leger. Je Glücksspiel wird geheim eine
#   Trefferquote q (1–10) gelost (nur in to_dict, nie in Sicht oder Ereignissen). Reihum {a:"stake"} (eine Handkarte verdeckt auf
#   den Einsatz) und {a:"press"}: Treffer (Wahrscheinlichkeit 1/q) → 1–10 Karten ziehen, Einsatz zurück, Zug vorbei; sonst 0 →
#   ist die Hand leer, kommt der Einsatz unter die Ablage und der Spieler ist fertig, sonst der nächste Einsatz.
#   {a:"stop"} (Aufhören, immer erlaubt): nach mindestens einem Druck ohne Treffer statt weiterzusetzen. Der Einsatz kommt unter
#   die Ablage (stake_discard mit reason "stop"; bei leerer Hand reason "empty"), der Zug ist vorbei. Bleibt 1 Karte, gilt die
#   normale Mau-Regel: Das Fenster hat schon das Setzen geöffnet (vorher rufen, sonst erwischbar).
# - Farbe mit ablegen (discard_color = on): Ablegefarbe = Kartenfarbe bzw. beim Ablegen-Joker das Feld color der play-Aktion.
#   Hat der Leger Nicht-Joker-Karten dieser Farbe (beim Joker immer, weil noch die Spielfarbe fehlt), beginnt die Phase
#   "discard_pick" (Ereignis discard_pick, Sicht discard_pick = {seat, color}, hints.can_pick nur für ihn). {a:"discard_pick",
#   cards: Teilmenge von can_pick, color: Spielfarbe nur beim Joker}: Die gewählten Karten kommen unter der Ablegen-Karte mit auf
#   die Ablage und wirken nicht (Ereignis discard_color), beim Joker folgt das Farbereignis, dann geht es weiter.
# - Ein „Mau!“-Ruf verfällt, wenn nach dem Legen bzw. Setzen mehr als eine Karte bleibt. Vor dem Legen darf rufen, wer eine Karte
#   legen kann, nach der genau 1 Karte bleibt (ohne Ablegen-Karten heißt das: 2 Karten auf der Hand).
# - Flip-Überraschung (flip_surprise = on): Liegt nach einem ausgeführten Flip (nicht am Rundenende) eine klassische Aktionskarte
#   oben (SURPRISE_KINDS), wirkt sie, als hätte der Flip-Spieler sie gelegt (öffentliches Ereignis flip_surprise {seat, face}
#   direkt vor den Wirkungs-Ereignissen). Bei Wünscher +2/Farbjagd wählt er zuerst die Farbe (Phase "color"). Kein Anzweifeln.

const FORMAT := 1
const SWAP := "tausch"
const GAMBLE := "gluecksspiel"
const DISCARD := "ablegen"
const DISCARD_WILD := "ablegen_joker"
const SIDES: Array[String] = ["hell", "dunkel"]
const PLAY_PHASES := ["turn", "drawn", "challenge", "color", "gamble", "discard_pick"]
const JAGD := "farbjagd"
const PLUS2 := "wuenscher_plus2"
# Flip-Überraschung: Diese Karten wirken, wenn sie nach einem Flip oben liegen (Flip, Wünscher und Zusatzkarten nicht).
const SURPRISE_KINDS := ["plus1", "plus5", "aussetzen", "alle_aussetzen", "richtungswechsel", PLUS2, JAGD]
const MIN_PLAYERS := 2
const MAX_PLAYERS := 10
const BAD_FIELD := -9999         # _int_field: Feld hat einen falschen Typ

var config: RuleConfig
var players: Array = []          # [{name, kind}] in Sitzordnung (Uhrzeigersinn)
var host := 0                    # Gastgeber-Platz: nur er startet die nächste Runde (players[i].host in create())
var connected: Array = []        # bool je Platz; setzt die Spielsteuerung (set_connected)
var round_no := 0
var dealer := 0
var side := 0                    # aktive Seite: 0 hell, 1 dunkel
var n_cards := CardDB.CARD_COUNT # Kartenzahl der Partie: 112 bis 124 je nach Hausregeln (aus config, fest je Partie)
var faces := PackedInt32Array()  # 2 × n_cards Gesichtscodes (s * n_cards + id)
var draw_pile: Array = []        # ids, oben = letztes Element
var discard: Array = []          # ids, oben = letztes Element
var hands: Array = []            # je Platz die ids in Besitzerreihenfolge
var current := -1
var dir := 1                     # 1 = Uhrzeigersinn (Platz + 1)
var color := ""                  # aktuelle Farbe (Kartenfarbe oder Wunsch)
var wished := false
var state := "idle"              # idle, turn, drawn, challenge, color, gamble, round_over, game_over
var pending := {}                # offene Strafe {kind, amount, by, victim, color, legal, snap, finisher}
var drawn_id := -1
var mau_said: Array = []
var mau_open := -1
var turn_started := false
var place: Array = []            # 0 = spielt noch, sonst Platzierung
var finished: Array = []         # fertige Plätze in Reihenfolge
var scores: Array = []           # Punkte (points500) bzw. Rundensiege
var result := {}                 # Ergebnis der letzten Runde
var pass_streak := 0             # aufeinanderfolgende Züge ohne Karte (beide Stapel leer)
var seen := {}                   # Lagen bei fast leeren Stapeln → Anzahl (Stillstandsregel, _stalled)
var gamble := {}                 # laufendes Glücksspiel {seat, q (geheim, 1–10), stake: [ids], need: "stake"|"press", last}
var dpick := {}                  # offene Ablege-Auswahl {seat, color (Ablegefarbe), card (Ablegen-Karte), wild}
var dlog := {}                   # Ablage-Protokoll: id → {s: Leger (-1 Startkarte), c: Wunschfarbe, h: verdeckter Einsatz}
var dside := {}                  # nur flip_mode = card: id → Seite (0/1), mit der die Ablagekarte liegt

var _valid := true              # false bei ungültiger Spielerzahl: start_round() und apply() lehnen ab
var _forced_rolls: Array = []   # Testhaken (force_rolls): vorgegebene Ergebnisse der nächsten Drucke, nicht gespeichert
var _seed := 0
var _rng := RandomNumberGenerator.new()
var _key: PackedStringArray
var _color: PackedStringArray
var _kind: PackedStringArray
var _value: PackedInt32Array
var _points: PackedInt32Array
var _wild: PackedByteArray


func _init() -> void:
	_key = CardDB.key_table()
	_color = CardDB.color_table()
	_kind = CardDB.kind_table()
	_value = CardDB.value_table()
	_points = CardDB.points_table()
	_wild = CardDB.wild_table()
	config = RuleConfig.new()


# players: [{name, kind: "human"|"bot", host?: true}], Platz 0 gibt zuerst. 2–10 Spieler; bei anderer Zahl gibt es push_warning
# (kein push_error: Aufrufer prüfen vorher mit valid_player_count(), die Tests lösen den Fall absichtlich aus), und das Spiel startet nie (start_round() liefert [], apply() lehnt ab, is_valid() = false). Gastgeber ist der erste Platz mit
# host = true, sonst Platz 0.
static func create(cfg: RuleConfig, player_list: Array, rng_seed: int) -> MauGame:
	var g := MauGame.new()
	g.config = cfg.duplicate_config() if cfg != null else RuleConfig.new()
	g._valid = valid_player_count(player_list.size())
	if not g._valid:
		push_warning("MauGame: %d bis %d Spieler nötig, nicht %d" % [MIN_PLAYERS, MAX_PLAYERS, player_list.size()])
	var host_set := false
	for p in player_list:
		var d: Dictionary = p if p is Dictionary else {}
		var kind := "bot" if str(d.get("kind", "human")) == "bot" else "human"
		if not host_set and _truthy(d.get("host", false)):
			g.host = g.players.size()
			host_set = true
		g.players.append({"name": str(d.get("name", "Spieler %d" % (g.players.size() + 1))), "kind": kind})
		g.connected.append(true)
		g.hands.append([])
		g.mau_said.append(false)
		g.place.append(0)
		g.scores.append(0)
	g._seed = rng_seed
	g._rng.seed = rng_seed
	g.n_cards = g.config.card_count()
	g.faces.resize(g.n_cards * 2)
	return g


func current_seat() -> int:
	return current if state in PLAY_PHASES else -1


func phase() -> String:
	return state


func is_over() -> bool:
	return state == "game_over"


func seat_count() -> int:
	return players.size()


func side_name() -> String:
	return SIDES[side]


func set_connected(seat: int, on: bool) -> void:
	if seat >= 0 and seat < connected.size():
		connected[seat] = on


static func valid_player_count(n: int) -> bool:
	return n >= MIN_PLAYERS and n <= MAX_PLAYERS


func is_valid() -> bool:
	return _valid


func host_seat() -> int:
	return host


# Gastgeber-Platz nachträglich setzen (z. B. nach einem Platzwechsel); ungültige Plätze werden ignoriert.
func set_host(seat: int) -> void:
	if seat >= 0 and seat < players.size():
		host = seat


func start_round() -> Array:
	var ev: Array = []
	if _valid and (state == "idle" or state == "round_over"):
		_start(ev)
	return ev


# --- Aktionen ---

func apply(seat: int, action: Dictionary) -> Dictionary:
	if not _valid:
		return {"ok": false, "reason": "Ungültige Spielerzahl.", "events": []}
	if seat < 0 or seat >= players.size():
		return {"ok": false, "reason": "Unbekannter Platz.", "events": []}
	var av: Variant = action.get("a", "")
	var a: String = av if av is String else ""
	var ev: Array = []
	var why := ""
	match a:
		"play":
			why = _act_play(seat, action, ev)
		"draw":
			why = _act_draw(seat, ev)
		"keep":
			why = _act_keep(seat, ev)
		"challenge":
			why = _act_decide(seat, true, ev)
		"accept":
			why = _act_decide(seat, false, ev)
		"color":
			why = _act_color(seat, action, ev)
		"stake":
			why = _act_stake(seat, action, ev)
		"press":
			why = _act_press(seat, ev)
		"stop":
			why = _act_stop(seat, ev)
		"discard_pick":
			why = _act_discard_pick(seat, action, ev)
		"mau":
			why = _act_mau(seat, ev)
		"catch":
			why = _act_catch(seat, action, ev)
		"next_round":
			why = _act_next_round(seat, ev)
		_:
			why = "Unbekannte Aktion."
	if why != "":
		return {"ok": false, "reason": why, "events": []}
	return {"ok": true, "reason": "", "events": ev}


func _phase_reason() -> String:
	match state:
		"idle":
			return "Die Runde hat noch nicht begonnen."
		"round_over":
			return "Die Runde ist vorbei."
		"game_over":
			return "Die Partie ist vorbei."
		"color":
			return "Erst die Farbe wählen."
		"drawn":
			return "Du hast schon gezogen – legen oder behalten."
		"challenge":
			return "Erst anzweifeln oder annehmen."
		"gamble":
			if str(gamble.get("need", "")) == "press":
				return "Erst den Glücksspielknopf drücken."
			return "Erst eine Karte verdeckt auf den Einsatz legen."
		"discard_pick":
			return "Erst auswählen, welche Karten mit abgelegt werden."
	return "Das geht gerade nicht."


# Begründung für stake/press außerhalb eines Glücksspiels.
func _no_gamble_reason() -> String:
	if config.gamble_cards != "on":
		return "Glücksspiel gibt es in diesen Regeln nicht."
	if state in PLAY_PHASES:
		return "Gerade läuft kein Glücksspiel."
	return _phase_reason()


# Ganzzahliges Aktionsfeld (aus JSON kommen Zahlen als float): int oder ganzzahliger, endlicher float. Fehlt das Feld: fallback;
# anderer Typ (null, String, Array, Dictionary, 1.5 …): BAD_FIELD.
static func _int_field(action: Dictionary, key: String, fallback := -1) -> int:
	if not action.has(key):
		return fallback
	var v: Variant = action[key]
	if v is int:
		return v
	if v is float:
		var f: float = v
		if is_finite(f) and f == floorf(f) and absf(f) < 1.0e9:
			return int(f)
	return BAD_FIELD


# Text-Aktionsfeld: nur String, sonst "".
static func _str_field(action: Dictionary, key: String) -> String:
	var v: Variant = action.get(key, "")
	return v if v is String else ""


static func _truthy(v: Variant) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	return false


func _act_play(seat: int, action: Dictionary, ev: Array) -> String:
	if not state in ["turn", "drawn", "challenge"]:
		return _phase_reason()
	if seat != current:
		return "Du bist nicht dran."
	var id := _int_field(action, "card")
	if id == BAD_FIELD:
		return "Ungültige Aktion."
	if not (hands[seat] as Array).has(id):
		return "Diese Karte hast du nicht."
	if not _playable(seat, id):
		return _why_not(seat, id)
	var f := faces[side * n_cards + id]
	var wish := ""
	if _wild[f] == 1:
		wish = _str_field(action, "color")
		if not (CardDB.COLORS[SIDES[side]] as Array).has(wish):
			return "Wähle eine Farbe der %s." % RulesText.side_name(SIDES[side])
	# Regelgerechtheit und die Hand fürs Anzweifeln mit der Hand zum Zeitpunkt der Entscheidung, also vor einer auto-Strafe,
	# die _begin_turn noch verhängen kann (Hinweise und enforce-Prüfung beruhen auf derselben Hand).
	var legal := true
	if _kind[f] == PLUS2 or _kind[f] == JAGD:
		legal = _wild_legal(seat, id)
	var snap: Array = (hands[seat] as Array).duplicate()
	snap.erase(id)
	_begin_turn(ev)
	_play(seat, id, wish, legal, snap, ev)
	return ""


func _act_draw(seat: int, ev: Array) -> String:
	if state == "challenge":
		return _act_decide(seat, false, ev)      # Ziehen = Strafe annehmen
	if state != "turn":
		return _phase_reason()
	if seat != current:
		return "Du bist nicht dran."
	if not pending.is_empty():
		_begin_turn(ev)
		_take_pending(seat, ev)
		_after_penalty(seat, ev)
		return ""
	if not _can_draw_free(seat):
		return "Der Stapel ist leer – lege eine passende Karte."
	_begin_turn(ev)
	var got: Array
	if config.draw_rule == "until_playable":
		got = _draw_until(seat, "playable", "", "zug", ev)
	else:
		got = _draw(seat, 1, "zug", ev)
	if got.is_empty():
		_pass(seat, ev)
		return ""
	var id: int = got.back()
	var f := faces[side * n_cards + id]
	if config.drawn_card != "may_not" and _matches(f) and _restriction_ok(seat, id, f):
		drawn_id = id
		state = "drawn"
	else:
		_advance(seat, false, ev)
	return ""


func _act_keep(seat: int, ev: Array) -> String:
	if state != "drawn":
		return "Es gibt keine gezogene Karte zu behalten." if state == "turn" else _phase_reason()
	if seat != current:
		return "Du bist nicht dran."
	if config.drawn_card == "must":
		return "Die gezogene Karte passt – du musst sie legen."
	drawn_id = -1
	ev.append({"e": "keep", "seat": seat})
	_advance(seat, false, ev)
	return ""


# Anzweifeln (challenge = true) oder Strafe annehmen.
func _act_decide(seat: int, challenge: bool, ev: Array) -> String:
	if state != "challenge":
		return "Hier gibt es nichts anzuzweifeln." if challenge else _phase_reason()
	if seat != current:
		return "Du bist nicht dran."
	_begin_turn(ev)
	var by := int(pending.by)
	var kind := str(pending.kind)
	var amount := int(pending.amount)
	var wish := str(pending.color)
	var finisher := bool(pending.get("finisher", false))
	if challenge:
		var legal := bool(pending.legal)
		var shown: Array = []
		for id in pending.snap:
			shown.append(_key[faces[side * n_cards + int(id)]])
		ev.append({"e": "challenge", "seat": seat, "target": by, "success": not legal, "hand": shown})
		pending = {}
		if not legal:
			# Bluff erwischt: Der Leger zieht die Strafe, der Herausforderer ist normal dran, die Wunschfarbe bleibt.
			if kind == JAGD:
				_draw_until(by, "color", wish, "bluff", ev)
			else:
				_draw(by, amount, "bluff", ev)
			state = "turn"
			ev.append({"e": "turn", "seat": seat})
			return ""
		if kind == JAGD:
			_draw_until(seat, "color", wish, "strafe", ev)
			_draw(seat, 2, "strafe", ev)
		else:
			_draw(seat, amount + 2, "strafe", ev)
		if config.penalty_turn == "skip":
			ev.append({"e": "skip", "seat": seat})
	else:
		ev.append({"e": "accept", "seat": seat})
		_take_pending(seat, ev)
	pending = {}
	if finisher:
		_finish(by, ev)
		if _round_should_end():
			_end_round("fertig", ev)
			return ""
	_after_penalty(seat, ev)
	return ""


func _act_color(seat: int, action: Dictionary, ev: Array) -> String:
	if state != "color":
		return "Gerade ist keine Farbwahl offen."
	if seat != current:
		return "Du bist nicht dran."
	var c := _str_field(action, "color")
	if not (CardDB.COLORS[SIDES[side]] as Array).has(c):
		return "Wähle eine Farbe der %s." % RulesText.side_name(SIDES[side])
	color = c
	wished = true
	_note_wish(c)
	ev.append({"e": "color", "color": c, "seat": seat})
	if _surprise_kind() != "":
		_surprise(seat, ev)                # Wünscher +2/Farbjagd oben nach dem Flip
	else:
		_advance(seat, false, ev)
	return ""


# Glücksspiel: eine beliebige Handkarte verdeckt auf den Einsatz legen (Pflicht vor jedem Druck). Wer dadurch auf 1 Karte kommt,
# ohne gerufen zu haben, öffnet das Mau-Fenster wie beim Legen.
func _act_stake(seat: int, action: Dictionary, ev: Array) -> String:
	if state != "gamble":
		return _no_gamble_reason()
	if seat != current:
		return "Du bist nicht dran."
	if str(gamble.need) != "stake":
		return "Erst den Glücksspielknopf drücken."
	var id := _int_field(action, "card")
	if id == BAD_FIELD:
		return "Ungültige Aktion."
	if not (hands[seat] as Array).has(id):
		return "Diese Karte hast du nicht."
	(hands[seat] as Array).erase(id)
	(gamble.stake as Array).append(id)
	gamble.need = "press"
	ev.append({"e": "stake", "seat": seat, "count": (gamble.stake as Array).size(), "card": id,
		"face": _key[faces[side * n_cards + id]], "back": _key[faces[(1 - side) * n_cards + id]]})
	_after_hand_shrinks(seat)
	return ""


# Glücksspiel: Knopf drücken. Treffer: so viele Karten ziehen, wie der Generator zeigt, den ganzen Einsatz zurücknehmen, Zug
# vorbei. Kein Treffer (0): Ist die Hand leer, kommt der Einsatz unter die Ablage und der Spieler ist fertig; sonst der nächste
# Einsatz oder Aufhören (_act_stop).
func _act_press(seat: int, ev: Array) -> String:
	if state != "gamble":
		return _no_gamble_reason()
	if seat != current:
		return "Du bist nicht dran."
	if str(gamble.need) != "press":
		return "Leg erst eine Karte verdeckt auf deinen Einsatz."
	var value := _roll()
	gamble.last = value
	ev.append({"e": "gamble_roll", "seat": seat, "value": value})
	var stake: Array = gamble.stake
	if value > 0:
		_draw(seat, value, "gluecksspiel", ev)
		gamble = {}
		(hands[seat] as Array).append_array(stake)
		var keys: Array = []
		var backs: Array = []
		for id in stake:
			keys.append(_key[faces[side * n_cards + int(id)]])
			backs.append(_key[faces[(1 - side) * n_cards + int(id)]])
		ev.append({"e": "stake_back", "seat": seat, "count": stake.size(), "cards": stake.duplicate(), "faces": keys,
			"backs": backs})
		# Wer Karten zurückbekommt, muss neu rufen; ein offenes Fenster des Spielers ist damit erledigt.
		mau_said[seat] = false
		if mau_open == seat:
			mau_open = -1
		_advance(seat, false, ev)
		return ""
	if (hands[seat] as Array).is_empty():
		_stake_under(seat, "empty", ev)
		_finish(seat, ev)
		if _round_should_end():
			_end_round("fertig", ev)
			return ""
		_advance(seat, false, ev)
		return ""
	gamble.need = "stake"
	return ""


# Glücksspiel: aufhören (immer erlaubt, nach mindestens einem Druck ohne Treffer, also wenn wieder gesetzt werden müsste). Der
# Einsatz kommt unter die Ablage, der Zug ist vorbei. Mau-Fenster und Ruf bleiben, wie das Setzen sie hinterlassen hat.
func _act_stop(seat: int, ev: Array) -> String:
	if state != "gamble":
		return _no_gamble_reason()
	if seat != current:
		return "Du bist nicht dran."
	if not _can_stop(seat):
		if str(gamble.need) == "press":
			return "Erst den Glücksspielknopf drücken."
		return "Aufhören geht erst nach dem ersten Druck."
	_stake_under(seat, "stop", ev)
	_advance(seat, false, ev)
	return ""


# Farbe mit ablegen: Auswahl der mitabgelegten Karten (Teilmenge von _pick_candidates, auch leer); beim Ablegen-Joker zusätzlich
# Pflichtfeld color = Spielfarbe (bei der farbigen Karte wird color nicht gebraucht und übergangen).
func _act_discard_pick(seat: int, action: Dictionary, ev: Array) -> String:
	if state != "discard_pick":
		if config.discard_color != "on":
			return "Farbe mit ablegen gibt es in diesen Regeln nicht."
		return "Gerade ist nichts zum Mitablegen offen." if state in PLAY_PHASES else _phase_reason()
	if seat != current:
		return "Du bist nicht dran."
	var raw: Variant = action.get("cards", [])
	if not raw is Array:
		return "Ungültige Aktion."
	var cand := _pick_candidates(seat)
	var chosen: Array = []
	for x in raw:
		var c := _int_field({"c": x}, "c")
		if c == BAD_FIELD or chosen.has(c):
			return "Ungültige Aktion."
		if not cand.has(c):
			return "Diese Karte kannst du nicht mit ablegen."
		chosen.append(c)
	var wild := bool(dpick.get("wild", false))
	var wish := ""
	if wild:
		wish = _str_field(action, "color")
		if not (CardDB.COLORS[SIDES[side]] as Array).has(wish):
			return "Wähle die Farbe, mit der es weitergeht."
	var id := int(dpick.card)
	var col := str(dpick.color)
	dpick = {}
	state = "turn"
	_discard_color(seat, id, col, chosen, ev)
	if wild:
		color = wish
		wished = true
		_note_wish(wish)
		ev.append({"e": "color", "color": wish, "seat": seat})
	_play_rest(seat, DISCARD_WILD if wild else DISCARD, true, [], ev)
	return ""


# Wählbare Karten der offenen Ablege-Auswahl: Nicht-Joker-Karten der Ablegefarbe auf der Hand des Legers (Besitzerreihenfolge).
func _pick_candidates(seat: int) -> Array:
	var out: Array = []
	if state != "discard_pick" or dpick.is_empty() or seat != int(dpick.seat):
		return out
	var col := str(dpick.color)
	for c in hands[seat]:
		if _color[faces[side * n_cards + int(c)]] == col:
			out.append(int(c))
	return out


func _can_stop(seat: int) -> bool:
	return state == "gamble" and seat == current and str(gamble.get("need", "")) == "stake" \
		and (gamble.get("stake", []) as Array).size() >= 1


# Einsatz unter die Ablage legen und das Glücksspiel beenden (Ereignis stake_discard).
func _stake_under(seat: int, reason: String, ev: Array) -> void:
	var stake: Array = gamble.stake
	gamble = {}
	var keys: Array = []
	for id in stake:
		keys.append(_key[faces[side * n_cards + int(id)]])
	for id in stake:
		dlog[int(id)] = {"s": seat, "c": "", "h": true}
		_lay(int(id))
	var under := stake.duplicate()
	under.append_array(discard)
	discard = under
	ev.append({"e": "stake_discard", "seat": seat, "count": stake.size(), "cards": stake.duplicate(), "faces": keys,
		"reason": reason})


# Testhaken: Die nächsten Drucke liefern diese Ergebnisse (0 = kein Treffer, 1–10 = Treffer) statt des Zufalls. Wird nicht
# gespeichert (nur für gebaute Testfälle).
func force_rolls(values: Array) -> void:
	_forced_rolls = values.duplicate()


# Ergebnis eines Drucks: Treffer mit Wahrscheinlichkeit 1/q, dann 1–10 gleich wahrscheinlich; sonst 0.
func _roll() -> int:
	if not _forced_rolls.is_empty():
		return clampi(int(_forced_rolls.pop_front()), 0, 10)
	if _rng.randi_range(1, int(gamble.q)) != 1:
		return 0
	return _rng.randi_range(1, 10)


func _act_mau(seat: int, ev: Array) -> String:
	if config.mau_call == "off":
		return "„Mau!“ ist in diesen Regeln ausgeschaltet."
	if not state in PLAY_PHASES:
		return _phase_reason()
	if not _can_mau(seat):
		if mau_said[seat]:
			return "Du hast schon „Mau!“ gerufen."
		if seat == current and (hands[seat] as Array).size() == 2 and state in ["turn", "drawn", "challenge"]:
			if _has_playable(seat):
				return "Damit legst du alles auf einmal ab – „Mau!“ brauchst du nicht."
			return "„Mau!“ rufst du, wenn du deine vorletzte Karte legen kannst – gerade passt keine."
		if seat == current and (hands[seat] as Array).size() == 2 and state == "gamble":
			return "„Mau!“ rufst du, bevor du deine vorletzte Karte auf den Einsatz legst."
		if seat == current and state == "discard_pick":
			return "„Mau!“ geht hier nur, wenn nach dem Ablegen genau 1 Karte bleiben kann."
		return "„Mau!“ geht erst, wenn du mit 2 Karten dran bist."
	mau_said[seat] = true
	if mau_open == seat:
		mau_open = -1
	ev.append({"e": "mau", "seat": seat})
	return ""


func _act_catch(seat: int, action: Dictionary, ev: Array) -> String:
	if config.mau_call != "catch":
		return "Erwischen gibt es in diesen Regeln nicht."
	if not state in PLAY_PHASES:
		return _phase_reason()
	var target := _int_field(action, "target")
	if target == BAD_FIELD:
		return "Ungültige Aktion."
	if target == seat:
		return "Dich selbst kannst du nicht erwischen."
	if target < 0 or target >= players.size() or target != mau_open or mau_said[target]:
		return "Zu spät – oder es gibt niemanden zu erwischen."
	mau_open = -1
	ev.append({"e": "catch", "seat": seat, "target": target})
	_mau_penalty(target, ev)
	return ""


func _act_next_round(seat: int, ev: Array) -> String:
	if state != "round_over":
		return "Die Partie ist vorbei." if state == "game_over" else "Die Runde läuft noch."
	if seat != host:
		return "Die nächste Runde startet der Gastgeber."
	_start(ev)
	return ""


# --- Ablauf ---

func _start(ev: Array) -> void:
	var n := players.size()
	round_no += 1
	dealer = 0 if round_no == 1 else (dealer + 1) % n
	side = 0
	dir = 1
	pending = {}
	drawn_id = -1
	mau_open = -1
	pass_streak = 0
	seen = {}
	finished = []
	result = {}
	gamble = {}
	dpick = {}
	for s in n:
		mau_said[s] = false
		place[s] = 0
		hands[s] = []
	# Paarung hell↔dunkel und ids neu mischen: id → zufälliges helles und zufälliges dunkles Gesicht.
	var light := _shuffled_range(n_cards)
	var dark := _shuffled_range(n_cards)
	var dl := config.deck(0)
	var dd := config.deck(1)
	faces.resize(n_cards * 2)
	for id in n_cards:
		faces[id] = dl[light[id]]
		faces[n_cards + id] = dd[dark[id]]
	draw_pile = _shuffled_range(n_cards)
	discard = []
	dlog = {}
	dside = {}
	ev.append({"e": "round_start", "round": round_no, "dealer": dealer})
	for k in config.hand_size:
		for i in n:
			hands[(dealer + 1 + i) % n].append(draw_pile.pop_back())
	ev.append({"e": "deal", "dealer": dealer, "count": config.hand_size})
	_reveal_start_card(ev)
	_new_turn((dealer + 1) % n, ev)


# Startkarte (Regelbericht 1.3, R24): Aktion, Joker oder Flip bleiben liegen, die nächste Karte wird aufgedeckt.
func _reveal_start_card(ev: Array) -> void:
	while not draw_pile.is_empty():
		var id: int = draw_pile.pop_back()
		discard.append(id)
		_lay(id)
		var f := faces[side * n_cards + id]
		var number := _kind[f] == "zahl"
		ev.append({"e": "start", "card": id, "face": _key[f], "ignored": not number})
		if number:
			break
	var top := faces[side * n_cards + int(discard.back())]
	color = _color[top]
	wished = false
	if color == "":         # Notfall: keine Zahl mehr im Stapel und oben ein Joker
		color = CardDB.COLORS[SIDES[side]][_rng.randi_range(0, 3)]
		wished = true
	if wished:
		_note_wish(color)
	ev.append({"e": "color", "color": color, "seat": -1})


func _new_turn(seat: int, ev: Array) -> void:
	current = seat
	state = "turn"
	turn_started = false
	drawn_id = -1
	if _stalled():
		_end_round("blockiert", ev)
		return
	ev.append({"e": "turn", "seat": seat})


# Stillstand: Bei fast leeren Stapeln (höchstens so viele freie Karten wie Spieler) kann sich das Spiel endlos wiederholen,
# z. B. zwei Nachbarn reichen sich zwei Richtungswechsel hin und her, weil das Mischen immer genau die eben gelegte Karte
# zurückgibt. Tritt dieselbe Lage zum dritten Mal ein, endet die Runde wie eine Blockade (wenigste Karten gewinnt).
func _stalled() -> bool:
	if draw_pile.size() + discard.size() - 1 > players.size():
		if not seen.is_empty():
			seen.clear()
		return false
	var sig: Array = [side, current, dir, color, wished, str(pending.get("kind", "")), int(pending.get("amount", 0)),
		draw_pile, discard, place]
	for h in hands:
		var sorted_hand: Array = (h as Array).duplicate()
		sorted_hand.sort()
		sig.append(sorted_hand)
	var key := sig.hash()
	var count := int(seen.get(key, 0)) + 1
	seen[key] = count
	return count >= 3


# Weiter zum nächsten aktiven Platz nach from; skip überspringt einen.
func _advance(from: int, skip: bool, ev: Array) -> void:
	var nxt := _next_active(from)
	if skip:
		ev.append({"e": "skip", "seat": nxt})
		nxt = _next_active(nxt)
	_new_turn(nxt, ev)


func _next_active(from: int) -> int:
	return _next_in(from, dir)


# Nächster aktiver Platz nach from in Richtung step (±1); from selbst, wenn kein anderer aktiv ist.
func _next_in(from: int, step: int) -> int:
	var n := players.size()
	var s := from
	for i in n:
		s = posmod(s + step, n)
		if place[s] == 0:
			return s
	return from


func _active_count() -> int:
	var c := 0
	for p in place:
		if p == 0:
			c += 1
	return c


# Erste Zughandlung des laufenden Zugs: schließt das Mau-Fenster des vorigen Zugs.
func _begin_turn(ev: Array) -> void:
	if turn_started:
		return
	turn_started = true
	if mau_open >= 0:
		var t := mau_open
		mau_open = -1
		if config.mau_call == "auto" and not mau_said[t] and (hands[t] as Array).size() == 1:
			_mau_penalty(t, ev)


func _mau_penalty(seat: int, ev: Array) -> void:
	ev.append({"e": "penalty", "seat": seat, "count": config.mau_penalty, "reason": "mau"})
	_draw(seat, config.mau_penalty, "mau", ev)


# legal/snap: Regelgerechtheit und Resthand zum Zeitpunkt der Entscheidung (siehe _act_play).
func _play(p: int, id: int, wish: String, legal: bool, snap: Array, ev: Array) -> void:
	var f := faces[side * n_cards + id]
	var kind := _kind[f]
	(hands[p] as Array).erase(id)
	discard.append(id)
	dlog[id] = {"s": p, "c": "", "h": false}
	_lay(id)
	drawn_id = -1
	pass_streak = 0
	ev.append({"e": "play", "seat": p, "card": id, "face": _key[f]})
	var dcol := ""
	if kind == DISCARD_WILD:
		dcol = wish                            # beim Ablegen-Joker ist color die Ablegefarbe, die Spielfarbe folgt in discard_pick
	elif wish != "":
		color = wish
		wished = true
		_note_wish(wish)
		ev.append({"e": "color", "color": wish, "seat": p})
	else:
		color = _color[f]
		wished = false
	if kind == DISCARD or kind == DISCARD_WILD:
		if kind == DISCARD:
			dcol = color
		if kind == DISCARD_WILD or _color_count(p, dcol, -1) > 0:
			dpick = {"seat": p, "color": dcol, "card": id, "wild": kind == DISCARD_WILD}
			state = "discard_pick"
			current = p
			ev.append({"e": "discard_pick", "seat": p, "color": dcol})
			return
		_discard_color(p, id, dcol, [], ev)
	_play_rest(p, kind, legal, snap, ev)


# Zweiter Teil von _play (nach dem Ablegen): Mau-Fenster, Fertig und die Wirkung der Karte.
func _play_rest(p: int, kind: String, legal: bool, snap: Array, ev: Array) -> void:
	var challengeable := (kind == PLUS2 or kind == JAGD) and config.wild_restriction == "bluff"
	var left := (hands[p] as Array).size()
	_after_hand_shrinks(p)
	var finishing := left == 0
	if finishing and not challengeable:
		_finish(p, ev)
		if _round_should_end():
			_final_effect(p, kind, ev)
			_end_round("fertig", ev)
			return
		finishing = false
		if kind == "flip" and config.flip_last_card == "ignore":
			_advance(p, false, ev)             # Flip als letzte Karte wird nicht ausgeführt, auch wenn die Runde weiterläuft.
			return
	match kind:
		"aussetzen":
			_advance(p, true, ev)
		"richtungswechsel":
			dir = -dir
			ev.append({"e": "reverse", "dir": dir, "seat": p})
			_advance(p, _active_count() == 2 and config.two_player_reverse_skips, ev)
		"alle_aussetzen":
			ev.append({"e": "skip_all", "seat": p})
			if place[p] != 0:
				_advance(p, false, ev)         # fertig: Der Zusatzzug entfällt, der Nächste macht weiter.
			else:
				_new_turn(p, ev)
		"flip":
			_do_flip(ev)
			if color == "":
				state = "color"                # Joker oben: Der Flip-Spieler wählt die Farbe (Überraschung danach in _act_color).
				current = p
				ev.append({"e": "choose_color", "seat": p})
			elif _surprise_kind() != "":
				_surprise(p, ev)
			else:
				_advance(p, false, ev)
		"plus1", "plus5", PLUS2, JAGD:
			_start_pending(p, kind, legal, snap, finishing, ev)
		SWAP:
			_swap_hands(p, ev)
			_advance(p, false, ev)
		GAMBLE:
			if place[p] != 0:
				_advance(p, false, ev)             # als letzte Karte: fertig, ohne Glücksspiel (es gibt nichts zu setzen)
			else:
				_start_gamble(p, ev)
		_:
			_advance(p, false, ev)


# Nach Legen oder Setzen: Bleibt mehr als eine Karte, verfällt ein früher Ruf (z. B. vor einem Ablegen-Joker, der dann eine
# andere Farbe nimmt); bleibt genau eine ohne Ruf, öffnet sich das Fenster für den nachträglichen Ruf (erwischen nur bei catch,
# Strafe nur bei auto, siehe _act_catch und _begin_turn).
func _after_hand_shrinks(p: int) -> void:
	var left := (hands[p] as Array).size()
	if left > 1:
		mau_said[p] = false
	elif left == 1 and not mau_said[p] and config.mau_call != "off":
		mau_open = p


# Glücksspiel beginnt: geheime Trefferquote 1:q (q = 1–10 gleich wahrscheinlich) aus dem Spielzufall, Phase "gamble" für den Leger.
func _start_gamble(p: int, ev: Array) -> void:
	gamble = {"seat": p, "q": _rng.randi_range(1, 10), "stake": [], "need": "stake", "last": -1}
	state = "gamble"
	current = p
	drawn_id = -1
	ev.append({"e": "gamble_start", "seat": p})


# Farbe mit ablegen: Die gewählten Handkarten der Ablegefarbe col (chosen, aus _pick_candidates) kommen mit auf die Ablage, unter die
# Ablegen-Karte, die oben bleibt. Die Karten wirken nicht. Reihenfolge nach Rang (nie Besitzerreihenfolge, nie Auswahlreihenfolge);
# die Gesichter liegen offen, das Ereignis ist öffentlich.
func _discard_color(p: int, id: int, col: String, chosen: Array, ev: Array) -> void:
	var rank := CardDB.rank_table()
	var items: Array = []
	for c in chosen:
		var fc := faces[side * n_cards + int(c)]
		items.append([rank[fc], int(c)])
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var ids: Array = []
	var keys: Array = []
	for it in items:
		var c: int = it[1]
		ids.append(c)
		keys.append(_key[faces[side * n_cards + c]])
		(hands[p] as Array).erase(c)
		dlog[c] = {"s": p, "c": "", "h": false}
		_lay(c)
	discard.pop_back()
	discard.append_array(ids)
	discard.append(id)
	ev.append({"e": "discard_color", "seat": p, "color": col, "cards": ids, "faces": keys, "count": ids.size()})


# Flip-Überraschung (flip_surprise = on): klassische Aktionsart der Karte oben nach einem Flip, sonst "".
func _surprise_kind() -> String:
	if config.flip_surprise != "on" or discard.is_empty():
		return ""
	var k := _kind[faces[side * n_cards + int(discard.back())]]
	return k if SURPRISE_KINDS.has(k) else ""


# Die Aktionskarte oben wirkt, als hätte der Flip-Spieler p sie gelegt (die Farbe steht schon fest, bei Jokern aus _act_color).
# Anzweifeln gibt es dabei nicht: Niemand hat die Karte gelegt.
func _surprise(p: int, ev: Array) -> void:
	var k := _surprise_kind()
	ev.append({"e": "flip_surprise", "seat": p, "face": _key[faces[side * n_cards + int(discard.back())]]})
	match k:
		"aussetzen":
			_advance(p, true, ev)
		"richtungswechsel":
			dir = -dir
			ev.append({"e": "reverse", "dir": dir, "seat": p})
			_advance(p, _active_count() == 2 and config.two_player_reverse_skips, ev)
		"alle_aussetzen":
			ev.append({"e": "skip_all", "seat": p})
			if place[p] != 0:
				_advance(p, false, ev)
			else:
				_new_turn(p, ev)
		_:
			_start_pending(p, k, true, [], false, ev, false)


func _start_pending(p: int, kind: String, legal: bool, snap: Array, finishing: bool, ev: Array, challengeable := true) -> void:
	var amount := int(CardDB.DRAW_AMOUNT[kind])
	if not pending.is_empty() and str(pending.kind) == kind:
		amount += int(pending.amount)
	var victim := _next_active(p)
	pending = {"kind": kind, "amount": amount, "by": p, "victim": victim, "color": color, "legal": legal,
		"snap": snap.duplicate(), "finisher": finishing}
	ev.append({"e": "pending", "kind": kind, "amount": amount, "seat": victim, "by": p})
	if challengeable and (kind == PLUS2 or kind == JAGD) and config.wild_restriction == "bluff":
		current = victim
		state = "challenge"
		turn_started = false
		drawn_id = -1
		ev.append({"e": "turn", "seat": victim})
	elif config.stacking == "same":
		_new_turn(victim, ev)
	else:
		_take_pending(victim, ev)
		_after_penalty(victim, ev)


# Opfer nimmt die offene Strafe: zieht (und setzt aus, wenn penalty_turn = skip; wie es weitergeht, entscheidet _after_penalty).
func _take_pending(seat: int, ev: Array) -> void:
	var kind := str(pending.kind)
	if kind == JAGD:
		_draw_until(seat, "color", str(pending.color), "strafe", ev)
	else:
		_draw(seat, int(pending.amount), "strafe", ev)
	pending = {}
	pass_streak = 0
	if config.penalty_turn == "skip":
		ev.append({"e": "skip", "seat": seat})


# Nach dem Strafziehen: offiziell setzt das Opfer aus (der Nächste ist dran); mit der Hausregel penalty_turn = play ist das
# Opfer danach ganz normal am Zug (legen oder, wenn nichts passt, wie üblich ziehen).
func _after_penalty(seat: int, ev: Array) -> void:
	if config.penalty_turn == "play":
		_new_turn(seat, ev)
	else:
		_advance(seat, false, ev)


# Letzte Karte, Runde endet: Ziehkarten wirken noch, ein Flip nach flip_last_card.
func _final_effect(p: int, kind: String, ev: Array) -> void:
	if CardDB.DRAW_AMOUNT.has(kind):
		var amount := int(CardDB.DRAW_AMOUNT[kind])
		if not pending.is_empty() and str(pending.kind) == kind:
			amount += int(pending.amount)
		pending = {}
		var victim := _next_active(p)
		if victim == p:
			return
		ev.append({"e": "pending", "kind": kind, "amount": amount, "seat": victim, "by": p})
		if kind == JAGD:
			_draw_until(victim, "color", color, "strafe", ev)
		else:
			_draw(victim, amount, "strafe", ev)
	elif kind == "flip" and config.flip_last_card == "execute":
		_do_flip(ev)


func _do_flip(ev: Array) -> void:
	if config.flip_mode != "card":
		discard.reverse()              # offiziell: ganze Ablage wenden; bei "card" dreht sich nur die Flip-Karte oben
	draw_pile.reverse()
	side = 1 - side
	wished = false
	var top: int = discard.back()
	_lay(top)
	var f := faces[side * n_cards + top]
	color = _color[f]
	ev.append({"e": "flip", "side": SIDES[side], "card": top, "face": _key[f], "draw_back": _draw_back()})


# Kartentausch: Jeder aktive Platz gibt seine ganze Hand gleichzeitig an den nächsten aktiven Platz in Tauschrichtung
# (config.swap_step: Uhrzeigersinn oder aktuelle Spielrichtung). Fertige (round_end=last) und ein eben fertig gewordener
# Leger nehmen nicht teil. Wer dadurch auf 1 Karte kommt, muss nicht „Mau!“ rufen: Fenster und alle Rufe verfallen.
# Ereignis (ungefiltert, privat): hands = je Platz [{id, face, back}] nach dem Tausch, backs = je Platz die Rückseiten sortiert;
# events_for() gibt jedem nur die eigene neue Hand (hand) und die Rückseiten der anderen.
func _swap_hands(p: int, ev: Array) -> void:
	var n := players.size()
	var step := config.swap_step(dir)
	if _active_count() < 2:
		return
	var old: Array = hands.duplicate()
	for s in n:
		if place[s] == 0:
			hands[_next_in(s, step)] = old[s]
	mau_open = -1
	for s in n:
		mau_said[s] = false
	var counts: Array = []
	var items: Array = []
	var backs: Array = []
	for s in n:
		counts.append((hands[s] as Array).size())
		var hand_items: Array = []
		for id in hands[s]:
			hand_items.append({"id": int(id), "face": _key[faces[side * n_cards + int(id)]],
				"back": _key[faces[(1 - side) * n_cards + int(id)]]})
		items.append(hand_items)
		backs.append(_sorted_backs(s))
	ev.append({"e": "swap_hands", "seat": p, "dir": step, "counts": counts, "hands": items, "backs": backs})


# Rückseiten (Gegenseite) der Hand eines Platzes, sortiert nach Seite, Farbe, Art und Wert (nie in Besitzerreihenfolge).
func _sorted_backs(s: int) -> Array:
	var rank := CardDB.rank_table()
	var order := CardDB.order_table()
	var other := 1 - side
	var ranks := PackedInt32Array()
	for id in hands[s]:
		ranks.append(rank[faces[other * n_cards + int(id)]])
	ranks.sort()
	var out: Array = []
	for r in ranks:
		out.append(_key[order[r]])
	return out


func _finish(p: int, ev: Array) -> void:
	finished.append(p)
	place[p] = finished.size()
	mau_said[p] = false
	if mau_open == p:
		mau_open = -1
	ev.append({"e": "finish", "seat": p, "place": place[p]})


func _round_should_end() -> bool:
	if config.round_end == "first":
		return not finished.is_empty()
	return _active_count() <= 1


func _pass(seat: int, ev: Array) -> void:
	ev.append({"e": "pass", "seat": seat})
	pass_streak += 1
	if pass_streak >= _active_count():
		_end_round("blockiert", ev)    # niemand kann legen, beide Stapel leer
	else:
		_advance(seat, false, ev)


func _end_round(reason: String, ev: Array) -> void:
	var n := players.size()
	var pts: Array = []
	var counts: Array = []
	for s in n:
		pts.append(_hand_points(s))
		counts.append((hands[s] as Array).size())
	var rest: Array = []
	for s in n:
		if place[s] == 0:
			rest.append(s)
	var by_cards := reason == "blockiert"
	rest.sort_custom(func(a: int, b: int) -> bool:
		var ka: Array = [counts[a], pts[a], a] if by_cards else [pts[a], counts[a], a]
		var kb: Array = [counts[b], pts[b], b] if by_cards else [pts[b], counts[b], b]
		for i in 3:
			if ka[i] != kb[i]:
				return ka[i] < kb[i]
		return false)
	var ranking: Array = finished.duplicate()
	ranking.append_array(rest)
	for i in ranking.size():
		place[ranking[i]] = i + 1
	var winner: int = ranking[0]
	var gains: Array = []
	gains.resize(n)
	gains.fill(0)
	if config.effective_scoring() == "points500":
		var sum := 0
		for s in n:
			if s != winner:
				sum += int(pts[s])
		gains[winner] = sum
	else:
		gains[winner] = 1
	for s in n:
		scores[s] = int(scores[s]) + int(gains[s])
	var shown: Array = []
	for s in n:
		var keys: Array = []
		for id in hands[s]:
			keys.append(_key[faces[side * n_cards + int(id)]])
		shown.append(keys)
	pending = {}
	mau_open = -1
	drawn_id = -1
	gamble = {}
	result = {"ranking": ranking, "points": pts, "gains": gains, "scores": scores.duplicate(), "hands": shown,
		"reason": reason, "side": SIDES[side], "round": round_no}
	ev.append({"e": "round_over", "ranking": ranking.duplicate(), "scores": scores.duplicate(), "points": pts.duplicate(),
		"gains": gains.duplicate(), "hands": shown.duplicate(true), "reason": reason})
	state = "round_over"
	if config.effective_scoring() == "points500" and int(scores[winner]) >= config.target:
		state = "game_over"
		ev.append({"e": "game_over", "winner": winner, "scores": scores.duplicate()})


func _hand_points(s: int) -> int:
	var sum := 0
	for id in hands[s]:
		sum += _points[faces[side * n_cards + int(id)]]
	return sum


# --- Ziehen und Mischen ---

func _draw(seat: int, n: int, reason: String, ev: Array) -> Array:
	var all: Array = []
	var got: Array = []
	for i in n:
		if draw_pile.is_empty():
			if discard.size() <= 1:
				break
			_flush_draw(seat, got, reason, ev)
			got = []
			_reshuffle(ev)
		var id: int = draw_pile.pop_back()
		hands[seat].append(id)
		got.append(id)
		all.append(id)
	_flush_draw(seat, got, reason, ev)
	return all


# Zieht, bis eine Karte passt (mode "playable") bzw. die Farbe col kommt (mode "color", Farbjagd), oder kein Stapel mehr da ist.
func _draw_until(seat: int, mode: String, col: String, reason: String, ev: Array) -> Array:
	var all: Array = []
	var got: Array = []
	while true:
		if draw_pile.is_empty():
			if discard.size() <= 1:
				break
			_flush_draw(seat, got, reason, ev)
			got = []
			_reshuffle(ev)
		var id: int = draw_pile.pop_back()
		hands[seat].append(id)
		got.append(id)
		all.append(id)
		var f := faces[side * n_cards + id]
		if mode == "color":
			if _color[f] == col or (config.jagd_wild_stops and _wild[f] == 1):
				break
		elif _matches(f) and _restriction_ok(seat, id, f):
			break
	_flush_draw(seat, got, reason, ev)
	return all


func _flush_draw(seat: int, got: Array, reason: String, ev: Array) -> void:
	if got.is_empty():
		return
	mau_said[seat] = false
	pass_streak = 0
	var keys: Array = []
	var backs: Array = []
	for id in got:
		keys.append(_key[faces[side * n_cards + int(id)]])
		backs.append(_key[faces[(1 - side) * n_cards + int(id)]])
	ev.append({"e": "draw", "seat": seat, "count": got.size(), "reason": reason, "cards": got.duplicate(), "faces": keys,
		"backs": backs})


# Nachziehstapel leer: Ablage außer der obersten Karte mischen (Wunschfarbe bleibt).
func _reshuffle(ev: Array) -> void:
	var top: int = discard.pop_back()
	var rest := discard
	_shuffle(rest)
	draw_pile.append_array(rest)
	discard = [top]
	var keep: Variant = dlog.get(top)
	dlog = {}
	if keep != null:
		dlog[top] = keep
	dside = {}
	_lay(top)
	ev.append({"e": "shuffle", "count": draw_pile.size()})


# Wunschfarbe an der obersten Ablagekarte vermerken (Ablage-Protokoll, view.discard_log).
func _note_wish(c: String) -> void:
	if discard.is_empty():
		return
	var id := int(discard.back())
	var e: Dictionary = dlog.get(id, {"s": -1, "c": "", "h": false})
	e.c = c
	dlog[id] = e


# flip_mode = card: Seite merken, mit der die Karte auf die Ablage kommt (beim Flip die neue Seite der Flip-Karte).
func _lay(id: int) -> void:
	if config.flip_mode == "card":
		dside[id] = side


# Öffentliches Ablage-Protokoll (für alle gleich): von unten nach oben, verdeckte Einsätze ohne Gesicht. Bei flip_mode = card
# zeigen die Karten unter der obersten die Seite, mit der sie lagen (dside); offiziell alle die aktive Seite.
func _discard_log() -> Array:
	var out: Array = []
	for i in discard.size():
		var id: int = discard[i]
		var e: Dictionary = dlog.get(id, {})
		var hid := bool(e.get("h", false)) and i < discard.size() - 1   # oben (nach einem Flip) ist die Karte ohnehin offen
		var shown := side if i == discard.size() - 1 else int(dside.get(int(id), side))
		out.append({"f": "" if hid else _key[faces[shown * n_cards + int(id)]], "s": int(e.get("s", -1)),
			"c": str(e.get("c", "")), "h": hid})
	return out


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


func _shuffled_range(n: int) -> Array:
	var a: Array = range(n)
	_shuffle(a)
	return a


# --- Regelprüfungen ---

# Passt Gesicht f auf die Ablage? Farbe, Zahl oder Symbol; Joker immer. Auf einem Joker zählt nur die (Wunsch-)Farbe.
func _matches(f: int) -> bool:
	if _wild[f] == 1 or _color[f] == color:
		return true
	if discard.is_empty():
		return false
	var t := faces[side * n_cards + int(discard.back())]
	if _wild[t] == 1 or _kind[f] != _kind[t]:
		return false
	return _kind[f] != "zahl" or _value[f] == _value[t]


# Wünscher +2/Farbjagd regelgerecht? Keine andere Karte der aktuellen Farbe (und je nach Fassung kein anderer Joker).
func _wild_legal(seat: int, skip_id: int) -> bool:
	for id in hands[seat]:
		if id == skip_id:
			continue
		var f := faces[side * n_cards + int(id)]
		if _color[f] == color or (config.wild_counts_for_bluff and _wild[f] == 1):
			return false
	return true


func _restriction_ok(seat: int, id: int, f: int) -> bool:
	if config.wild_restriction != "enforce":
		return true
	var kind := _kind[f]
	return (kind != PLUS2 and kind != JAGD) or _wild_legal(seat, id)


func _playable(seat: int, id: int) -> bool:
	var f := faces[side * n_cards + id]
	match state:
		"drawn":
			return id == drawn_id and config.drawn_card != "may_not" and _matches(f) and _restriction_ok(seat, id, f)
		"turn", "challenge":
			if not pending.is_empty():
				if config.stacking != "same" or bool(pending.get("finisher", false)) or _kind[f] != str(pending.kind):
					return false
				return _restriction_ok(seat, id, f)
			return state == "turn" and _matches(f) and _restriction_ok(seat, id, f)
	return false


func _has_playable(seat: int) -> bool:
	for id in hands[seat]:
		if _playable(seat, int(id)):
			return true
	return false


# Freiwilliges Ziehen geht immer, solange es etwas zu ziehen gibt; sind beide Stapel leer, nur wenn nichts passt (= aussetzen).
func _can_draw_free(seat: int) -> bool:
	return not draw_pile.is_empty() or discard.size() > 1 or not _has_playable(seat)


func _can_mau(seat: int) -> bool:
	if config.mau_call == "off" or seat < 0 or mau_said[seat] or not state in PLAY_PHASES:
		return false
	if mau_open == seat:
		return true
	if seat != current:
		return false
	var size := (hands[seat] as Array).size()
	if state == "gamble":
		return str(gamble.need) == "stake" and size == 2       # vor dem Setzen der vorletzten Karte
	if state == "discard_pick":                                # wenn nach der Auswahl genau 1 Karte bleiben kann
		return size >= 1 and size - _pick_candidates(seat).size() <= 1
	if not state in ["turn", "drawn", "challenge"]:
		return false
	# Vor dem Legen nur, wenn eine Karte legbar ist (sonst zieht man und hätte 3 Karten: kein „blinder“ Ruf), nach der genau
	# 1 Karte bleibt. Ohne Ablegen-Karten heißt das: 2 Karten und irgendeine legbar.
	if config.discard_color != "on":
		return size == 2 and _has_playable(seat)
	for id in hands[seat]:
		if _playable(seat, int(id)) and _can_leave_one(seat, int(id)):
			return true
	return false


# Kann das Legen dieser Karte genau 1 Karte übrig lassen? Normal bei 2 Karten; mit einer Ablegen-Karte darf man beliebig viele der
# übrigen Karten ihrer Farbe mitablegen, mit einem Ablegen-Joker die einer wählbaren Farbe (Joker bleiben).
func _can_leave_one(seat: int, id: int) -> bool:
	var rest := (hands[seat] as Array).size() - 1
	var f := faces[side * n_cards + id]
	if _kind[f] == DISCARD:
		return rest >= 1 and rest - _color_count(seat, _color[f], id) <= 1
	if _kind[f] == DISCARD_WILD:
		var most := 0
		for c in CardDB.COLORS[SIDES[side]]:
			most = maxi(most, _color_count(seat, str(c), id))
		return rest >= 1 and rest - most <= 1
	return rest == 1


# Karten der Farbe col auf der Hand eines Platzes, ohne die Karte skip (Joker haben keine Farbe und zählen nie).
func _color_count(seat: int, col: String, skip: int) -> int:
	var n := 0
	for c in hands[seat]:
		if int(c) != skip and _color[faces[side * n_cards + int(c)]] == col:
			n += 1
	return n


func _why_not(seat: int, id: int) -> String:
	var f := faces[side * n_cards + id]
	if state == "drawn":
		if config.drawn_card == "may_not":
			return "Die gezogene Karte darfst du erst im nächsten Zug legen."
		return "Jetzt darfst du nur die gezogene Karte legen." if id != drawn_id else "Die gezogene Karte passt nicht."
	if not pending.is_empty():
		var kname := RulesText.kind_name(str(pending.kind))
		if config.stacking == "same" and not bool(pending.get("finisher", false)) and _kind[f] == str(pending.kind):
			return "%s nur, wenn du keine Karte in %s hast." % [kname, RulesText.color_name(color)]
		if state == "challenge":
			return "Anzweifeln oder ziehen."
		return "Lege %s drauf oder nimm die Strafe." % kname if config.stacking == "same" else "Erst die Strafe ziehen."
	if (_kind[f] == PLUS2 or _kind[f] == JAGD) and _matches(f):
		return "%s nur, wenn du keine Karte in %s hast%s." % [RulesText.kind_name(_kind[f]), RulesText.color_name(color),
			" und keinen anderen Joker" if config.wild_counts_for_bluff else ""]
	return "Passt nicht – " + _lay_phrase() + "."


func _lay_phrase() -> String:
	var t := faces[side * n_cards + int(discard.back())] if not discard.is_empty() else -1
	if t < 0 or _wild[t] == 1:
		return "lege %s" % RulesText.color_name(color)
	return "lege %s oder %s" % [RulesText.color_name(color), RulesText.match_phrase(_key[t])]


func _draw_back() -> String:
	return "" if draw_pile.is_empty() else _key[faces[(1 - side) * n_cards + int(draw_pile.back())]]


# --- Sichten ---

func view_for(seat: int) -> Dictionary:
	var n := players.size()
	var me := seat if seat >= 0 and seat < n else -1
	var other := 1 - side
	var pl: Array = []
	for i in n:
		var backs: Array = []
		if config.backs_visible and i != me:
			backs = _sorted_backs(i)
		pl.append({"seat": i, "name": players[i].name, "kind": players[i].kind, "count": (hands[i] as Array).size(),
			"backs": backs, "place": place[i], "mau": mau_said[i], "connected": connected[i], "score": scores[i]})
	var hand: Array = []
	if me >= 0:
		for id in hands[me]:
			var item := {"id": id, "face": _key[faces[side * n_cards + int(id)]]}
			if config.peek_own_backs:
				item["back"] = _key[faces[other * n_cards + int(id)]]
			hand.append(item)
	var top := {}
	if not discard.is_empty():
		top = {"id": discard.back(), "face": _key[faces[side * n_cards + int(discard.back())]]}
	var pend := {}
	if not pending.is_empty():
		pend = {"kind": pending.kind, "amount": pending.amount, "by": pending.by, "victim": pending.victim,
			"color": pending.color}
	var v := {
		"v": FORMAT, "seat": me, "side": SIDES[side], "phase": state, "turn": current_seat(), "dir": dir, "color": color,
		"wish": wished, "colors": (CardDB.COLORS[SIDES[side]] as Array).duplicate(), "players": pl, "hand": hand,
		"top": top, "draw_back": _draw_back(), "draw_count": draw_pile.size(), "discard_count": discard.size(),
		"pending": pend, "drawn": drawn_id if me >= 0 and me == current and state == "drawn" else -1,
		"hints": _hints(me), "round": round_no, "dealer": dealer, "ranking": finished.duplicate(),
		"result": {}, "rules": config.to_dict(), "discard_log": _discard_log(),
	}
	if state == "round_over" or state == "game_over":
		v.ranking = (result.get("ranking", []) as Array).duplicate()
		v.result = result.duplicate(true)
	# Glücksspiel (nur mit der Hausregel, damit die Sicht ohne sie unverändert bleibt): öffentlich sind Platz, Einsatzgröße, nächster
	# Schritt und letzter Wert; die Quote und die Einsatzgesichter nie.
	if config.gamble_cards == "on":
		var gv := {}
		if not gamble.is_empty():
			gv = {"seat": int(gamble.seat), "stake": (gamble.stake as Array).size(), "need": str(gamble.need),
				"last": int(gamble.last)}
		v["gamble"] = gv
	# Farbe mit ablegen: offene Auswahl öffentlich nur mit Platz und Ablegefarbe (keine Kandidatenzahl, das wäre ein Leck).
	if config.discard_color == "on":
		v["discard_pick"] = {"seat": int(dpick.seat), "color": str(dpick.color)} if state == "discard_pick" and not dpick.is_empty() else {}
	return v


func _hints(me: int) -> Dictionary:
	var h := {"playable": [], "wild": [], "can_draw": false, "can_keep": false, "can_challenge": false,
		"can_accept": false, "can_mau": false, "catch": [], "need_color": false, "can_next_round": false, "text": ""}
	if config.gamble_cards == "on":
		h["can_stake"] = []
		h["can_press"] = false
		h["can_stop"] = false
	if config.discard_color == "on":
		h["can_pick"] = []
		h["pick_color"] = false
	if me >= 0 and state in PLAY_PHASES:
		if me == current:
			var playable: Array = []
			var wild: Array = []
			if state in ["turn", "drawn", "challenge"]:
				for id in hands[me]:
					if _playable(me, int(id)):
						playable.append(id)
						if _wild[faces[side * n_cards + int(id)]] == 1:
							wild.append(id)
			h.playable = playable
			h.wild = wild
			match state:
				"turn":
					h.can_draw = not pending.is_empty() or not draw_pile.is_empty() or discard.size() > 1 or playable.is_empty()
				"drawn":
					h.can_keep = config.drawn_card != "must"
				"challenge":
					h.can_draw = true
					h.can_challenge = true
					h.can_accept = true
				"color":
					h.need_color = true
				"gamble":
					if str(gamble.need) == "stake":
						h.can_stake = (hands[me] as Array).duplicate()
						h.can_stop = _can_stop(me)
					else:
						h.can_press = true
				"discard_pick":
					h.can_pick = _pick_candidates(me)
					h.pick_color = bool(dpick.get("wild", false))
		h.can_mau = _can_mau(me)
		if config.mau_call == "catch" and mau_open >= 0 and mau_open != me and not mau_said[mau_open]:
			h.catch = [mau_open]
	h.can_next_round = state == "round_over" and me >= 0 and me == host
	h.text = _hint_text(me, h)
	return h


func _name(s: int) -> String:
	return str(players[s].name) if s >= 0 and s < players.size() else "?"


func _hint_text(me: int, h: Dictionary) -> String:
	match state:
		"idle":
			return "Die Runde beginnt gleich."
		"round_over", "game_over":
			var rk: Array = result.get("ranking", [])
			var w: int = rk[0] if not rk.is_empty() else -1
			var head := ""
			if result.get("reason", "") == "blockiert":
				head = "Nichts geht mehr – "
			if state == "game_over":
				return head + ("Du gewinnst die Partie!" if w == me else "%s gewinnt die Partie." % _name(w))
			var t := head + ("Du gewinnst die Runde!" if w == me else "%s gewinnt die Runde." % _name(w))
			if me >= 0 and w != me and config.round_end == "last":
				t += " Du bist auf Platz %d." % int(place[me])
			if bool(h.can_next_round):
				t += " Weiter mit der nächsten Runde."
			return t
	if me < 0 or me != current:
		var who := _name(current)
		var t := ""
		if not (h.catch as Array).is_empty():
			t = "%s hat nicht „Mau!“ gerufen – erwischen! " % _name(int(h.catch[0]))
		if me >= 0 and place[me] > 0:
			t += "Du bist fertig (Platz %d). " % int(place[me])
		match state:
			"challenge":
				return t + "%s überlegt: anzweifeln oder ziehen?" % who
			"color":
				return t + "%s wählt eine Farbe." % who
			"gamble":
				var n := (gamble.stake as Array).size()
				return t + "%s spielt Glücksspiel – Einsatz: %d %s." % [who, n, "Karte" if n == 1 else "Karten"]
			"discard_pick":
				return t + "%s legt %s mit ab." % [who, RulesText.color_name(str(dpick.get("color", "")))]
		return t + "%s ist dran." % who
	var text := ""
	match state:
		"discard_pick":
			var cname := RulesText.color_name(str(dpick.get("color", "")))
			if (h.can_pick as Array).is_empty():
				text = "Wähle die Farbe, mit der es weitergeht."
			elif bool(h.pick_color):
				text = "Wähle, welche Karten in %s du mit ablegst, und die Farbe, mit der es weitergeht." % cname
			else:
				text = "Wähle, welche Karten in %s du mit ablegst." % cname
		"color":
			text = "Nach dem Flip liegt ein Joker oben – wähle die neue Farbe."
		"gamble":
			if str(gamble.need) != "stake":
				text = "Drück den Glücksspielknopf!"
			elif bool(h.get("can_stop", false)):
				text = "Noch eine Karte setzen – oder aufhören?"
			else:
				text = "Leg eine Karte verdeckt auf deinen Einsatz."
		"challenge":
			var by := _name(int(pending.by))
			var col := RulesText.color_name(str(pending.color))
			if str(pending.kind) == JAGD:
				text = "Farbjagd auf %s von %s – anzweifeln oder ziehen, bis %s kommt?" % [col, by, col]
			else:
				text = "Wünscher +2 von %s (%s) – anzweifeln oder %d ziehen?" % [by, col, int(pending.amount)]
			if not (h.playable as Array).is_empty():
				text += " Du kannst auch %s drauflegen." % RulesText.kind_name(str(pending.kind))
		"drawn":
			text = "Die gezogene Karte passt – du musst sie legen." if config.drawn_card == "must" \
				else "Die gezogene Karte passt – legen oder behalten?"
		"turn":
			if not pending.is_empty():
				var kname := RulesText.kind_name(str(pending.kind))
				var take := "zieh, bis %s kommt" % RulesText.color_name(str(pending.color)) if str(pending.kind) == JAGD \
					else "zieh %d" % int(pending.amount)
				if (h.playable as Array).is_empty():
					text = "%s auf dich – %s." % [kname, take.substr(0, 1).to_upper() + take.substr(1)]
				else:
					text = "%s auf dich – lege %s drauf oder %s." % [kname, kname, take]
			elif (h.playable as Array).is_empty():
				text = "Du bist dran – nichts passt, zieh eine Karte." if not draw_pile.is_empty() or discard.size() > 1 \
					else "Du bist dran – nichts passt und beide Stapel sind leer: aussetzen."
			else:
				text = "Du bist dran – " + _lay_phrase()
				if wished:
					text += " (Wunschfarbe)"
				text += "."
	# Erinnerung vor dem Legen bzw. Setzen (mit 2 Karten; mit Ablegen-Karten auch mit mehr, wenn danach 1 Karte bleiben kann).
	var size := (hands[me] as Array).size()
	if bool(h.can_mau) and config.mau_call != "off" and (size == 2 or (size > 2 and mau_open != me)):
		text += " Denk an „Mau!“"
	return text


# Filtert Ereignisse für einen Empfänger: gezogene Gesichter und ids nur für den Ziehenden, die Hand beim Anzweifeln nur für den
# Herausforderer, beim Kartentausch nur die eigene neue Hand, beim Glücksspiel die Einsatzkarten nur für den Spieler selbst.
# Andere sehen Anzahl und – wenn Rückseiten sichtbar sind – die Rückseiten sortiert. Die Trefferquote steht nie in Ereignissen.
func events_for(seat: int, events: Array) -> Array:
	var out: Array = []
	for e in events:
		var d: Dictionary = e
		var c: Dictionary = d.duplicate(true)
		match str(d.get("e", "")):
			"draw":
				if int(d.seat) != seat:
					c.erase("cards")
					c.erase("faces")
					if config.backs_visible:
						c["backs"] = CardDB.sort_keys(d.get("backs", []))
					else:
						c.erase("backs")
				elif not config.peek_own_backs:
					c.erase("backs")
			"challenge":
				if int(d.seat) != seat:
					c.erase("hand")
			"swap_hands":
				# Nur die eigene neue Hand (wie view_for.hand), dazu die sortierten Rückseiten der anderen.
				var all_hands: Array = d.get("hands", [])
				c.erase("hands")
				var own: Array = []
				if seat >= 0 and seat < all_hands.size():
					own = (all_hands[seat] as Array).duplicate(true)
					if not config.peek_own_backs:
						for item in own:
							(item as Dictionary).erase("back")
				c["hand"] = own
				if config.backs_visible:
					var b: Array = c.get("backs", [])
					if seat >= 0 and seat < b.size():
						b[seat] = []
				else:
					c.erase("backs")
			"stake":
				# Verdeckt gesetzt: id, Gesicht (und Rückseite bei peek_own_backs) nur für den Besitzer.
				if int(d.seat) != seat:
					c.erase("card")
					c.erase("face")
					c.erase("back")
				elif not config.peek_own_backs:
					c.erase("back")
			"stake_back":
				# Wie ein Ziehereignis: Gesichter nur für den Besitzer, Rückseiten für andere sortiert (bei backs_visible).
				if int(d.seat) != seat:
					c.erase("cards")
					c.erase("faces")
					if config.backs_visible:
						c["backs"] = CardDB.sort_keys(d.get("backs", []))
					else:
						c.erase("backs")
				elif not config.peek_own_backs:
					c.erase("backs")
			"stake_discard":
				if int(d.seat) != seat:
					c.erase("cards")
					c.erase("faces")
		out.append(c)
	return out


# --- Speichern ---

func to_dict() -> Dictionary:
	var d := {
		"format": FORMAT, "config": config.to_dict(), "players": players.duplicate(true), "host": host, "connected": connected.duplicate(),
		"seed": str(_seed), "rng_state": str(_rng.state), "round": round_no, "dealer": dealer, "side": side,
		"faces": Array(faces), "draw": draw_pile.duplicate(), "discard": discard.duplicate(), "hands": hands.duplicate(true),
		"current": current, "dir": dir, "color": color, "wished": wished, "phase": state, "pending": pending.duplicate(true),
		"drawn": drawn_id, "mau_said": mau_said.duplicate(), "mau_open": mau_open, "turn_started": turn_started,
		"place": place.duplicate(), "finished": finished.duplicate(), "scores": scores.duplicate(),
		"result": result.duplicate(true), "pass_streak": pass_streak, "seen": _seen_list(),
		"dlog": _dlog_list(),
	}
	# Laufendes Glücksspiel samt geheimer Quote (nur mit der Hausregel; ohne sie bleibt der Spielstand wie bisher).
	if config.gamble_cards == "on":
		d["gamble"] = gamble.duplicate(true)
	if config.discard_color == "on":
		d["discard_pick"] = dpick.duplicate(true)
	if config.flip_mode == "card":       # nur in diesem Modus, sonst bleibt der Spielstand wie bisher
		var ds: Array = []
		for id in discard:
			if dside.has(int(id)):
				ds.append([int(id), int(dside[int(id)])])
		d["dside"] = ds
	return d


func _dlog_list() -> Array:
	var out: Array = []
	for id in discard:
		if dlog.has(int(id)):
			var e: Dictionary = dlog[int(id)]
			out.append([int(id), int(e.s), str(e.c), bool(e.h)])
	return out


static func from_dict(d: Dictionary) -> MauGame:
	var g := MauGame.new()
	g.config = RuleConfig.from_dict(d.get("config", {}))
	for p in d.get("players", []):
		g.players.append({"name": str(p.get("name", "")), "kind": str(p.get("kind", "human"))})
	var n := g.players.size()
	g._valid = valid_player_count(n)
	g.host = clampi(_int_field(d, "host", 0), 0, maxi(n - 1, 0))
	g.connected = _bools(d.get("connected", []), n, true)
	g._seed = str(d.get("seed", "0")).to_int()
	g._rng.seed = g._seed
	g._rng.state = str(d.get("rng_state", "0")).to_int()
	g.round_no = int(d.get("round", 0))
	g.dealer = int(d.get("dealer", 0))
	g.side = int(d.get("side", 0))
	g.n_cards = g.config.card_count()
	g.faces = PackedInt32Array(_ints(d.get("faces", [])))
	g.faces.resize(g.n_cards * 2)
	g.draw_pile = _ints(d.get("draw", []))
	g.discard = _ints(d.get("discard", []))
	g.dlog = {}
	var dl: Variant = d.get("dlog", [])
	if dl is Array:
		for e in dl:
			if e is Array and (e as Array).size() == 4:
				g.dlog[int(e[0])] = {"s": int(e[1]), "c": str(e[2]), "h": bool(e[3])}
	g.dside = {}
	var dsl: Variant = d.get("dside", [])
	if dsl is Array:
		for e in dsl:
			if e is Array and (e as Array).size() == 2:
				g.dside[int(e[0])] = clampi(int(e[1]), 0, 1)
	g.hands = []
	var hs: Array = d.get("hands", [])
	for s in n:
		g.hands.append(_ints(hs[s]) if s < hs.size() else [])
	g.current = int(d.get("current", -1))
	g.dir = int(d.get("dir", 1))
	g.color = str(d.get("color", ""))
	g.wished = bool(d.get("wished", false))
	g.state = str(d.get("phase", "idle"))
	var pd: Dictionary = d.get("pending", {})
	g.pending = {}
	if not pd.is_empty():
		g.pending = {"kind": str(pd.get("kind", "")), "amount": int(pd.get("amount", 0)), "by": int(pd.get("by", 0)),
			"victim": int(pd.get("victim", 0)), "color": str(pd.get("color", "")), "legal": bool(pd.get("legal", true)),
			"snap": _ints(pd.get("snap", [])), "finisher": bool(pd.get("finisher", false))}
	g.drawn_id = int(d.get("drawn", -1))
	g.mau_said = _bools(d.get("mau_said", []), n, false)
	g.mau_open = int(d.get("mau_open", -1))
	g.turn_started = bool(d.get("turn_started", false))
	g.place = _ints(d.get("place", []))
	g.place.resize(n)
	for i in n:
		if g.place[i] == null:
			g.place[i] = 0
	g.finished = _ints(d.get("finished", []))
	g.scores = _ints(d.get("scores", []))
	g.scores.resize(n)
	for i in n:
		if g.scores[i] == null:
			g.scores[i] = 0
	g.result = _result_from(d.get("result", {}))
	g.pass_streak = int(d.get("pass_streak", 0))
	g.seen = {}
	for pair in d.get("seen", []):
		if pair is Array and (pair as Array).size() == 2:
			g.seen[int(pair[0])] = int(pair[1])
	var gb: Dictionary = d.get("gamble", {}) if d.get("gamble", {}) is Dictionary else {}
	g.gamble = {}
	if not gb.is_empty():
		g.gamble = {"seat": int(gb.get("seat", 0)), "q": clampi(int(gb.get("q", 1)), 1, 10), "stake": _ints(gb.get("stake", [])),
			"need": str(gb.get("need", "stake")), "last": int(gb.get("last", -1))}
	var dp: Dictionary = d.get("discard_pick", {}) if d.get("discard_pick", {}) is Dictionary else {}
	g.dpick = {}
	if not dp.is_empty():
		g.dpick = {"seat": int(dp.get("seat", 0)), "color": str(dp.get("color", "")), "card": int(dp.get("card", -1)),
			"wild": bool(dp.get("wild", false))}
	return g


static func _ints(a: Variant) -> Array:
	var out: Array = []
	if a is Array or a is PackedInt32Array or a is PackedInt64Array or a is PackedFloat64Array:
		for x in a:
			out.append(int(x))
	return out


static func _bools(a: Variant, n: int, fallback: bool) -> Array:
	var out: Array = []
	var src: Array = a if a is Array else []
	for i in n:
		out.append(bool(src[i]) if i < src.size() else fallback)
	return out


static func _result_from(r: Dictionary) -> Dictionary:
	if r.is_empty():
		return {}
	var hands_out: Array = []
	for h in r.get("hands", []):
		var keys: Array = []
		for k in h:
			keys.append(str(k))
		hands_out.append(keys)
	return {"ranking": _ints(r.get("ranking", [])), "points": _ints(r.get("points", [])), "gains": _ints(r.get("gains", [])),
		"scores": _ints(r.get("scores", [])), "hands": hands_out, "reason": str(r.get("reason", "")),
		"side": str(r.get("side", "hell")), "round": int(r.get("round", 0))}


# Stillstandszähler als sortierte Liste [[Lage, Anzahl], …] (JSON-fest, unabhängig von der Einfügereihenfolge).
func _seen_list() -> Array:
	var keys: Array = seen.keys()
	keys.sort()
	var out: Array = []
	for k in keys:
		out.append([int(k), int(seen[k])])
	return out
