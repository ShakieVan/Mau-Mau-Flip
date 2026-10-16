class_name TeaseRules
extends RefCounted
# Mau-Mau Flip (Beta 1.6.3, Easter Eggs Teil 2): Regeln und Sperrzeiten fürs Necken (docs/module/eastereggs2.md Abschnitte 1, 4, 6).
# Rein, ohne Szene und ohne eigene Uhr: Jede Funktion bekommt die Zeit now (ms, monoton) vom Aufrufer (einspritzbar in Tests).
# Der Gastgeber (HostTable) hält die maßgebliche Instanz und prüft jeden Wunsch mit check(), bevor er ihn verteilt; jedes andere
# Gerät hält einen Spiegel (TableSource.tease), den es mit denselben Sichten, Ereignissen und angenommenen fx-Ereignissen füttert –
# so graut die Oberfläche lokal aus, was der Gastgeber ablehnen würde (Abschnitt 2 „Lokal vorgeprüft“). Der Spielstand bleibt
# unberührt (kein rev, keine Sicherung).
#
# Zustand je Partie: Zug (turn, Zugnummer, Zugbeginn since), sent[sender][kind] = Zugnummer (Schnarchen/Wecker je Sender und Zug
# einmal), busy_until[Ziel] (laufende Weckaktion), last_ball[Ziel], Eimer je Sender und Art sowie der Tisch-Eimer.
# Zug: jede Phase aus TURN_PHASES, in der current_seat() handeln muss. Die Zugnummer steigt, wenn der Platz am Zug wechselt (auch über
# −1 am Rundenende); die Uhr since beginnt außerdem neu, wenn der Platz am Zug selbst handelt (Ereignis mit seinem Platz, wie
# TableView._poke). Abgelehnte Aktionen erzeugen keine Ereignisse und setzen die Uhr deshalb nicht zurück.
#
# Tisch-Beschreibung für check() (table): {mode, phase, turn, seats: [{bot, gone, off}]} – bot = Computergegner (kein vertretener
# Mensch), gone = getrennt, „kurz in einer anderen App“ oder vom Computer vertreten, off = Necken aus. table_from_view() baut sie aus
# einer Sicht (Gäste, Oberfläche), HostTable aus seinen eigenen Daten.
#
# Gründe von check() ("" = erlaubt): REFUSALS ("late", "busy", "rate") gehen als {t:"fx_no", why} an den Absender zurück; alle übrigen
# ("kind", "mode", "sender", "off", "self", "target", "phase", "early", "once") verwirft der Gastgeber still – die Oberfläche zeigt
# solche Knöpfe gar nicht erst bzw. ausgegraut.
#
# Furzkissen (Beta 1.6.6, docs/module/eastereggs2.md Abschnitt 12): Art "kissen" {to, reveal}. Je Zielplatz liegt höchstens ein Kissen
# (cushions[Ziel] = {from, reveal, at}; zweites → "busy"), je Leger eine Zufallssperre von 1–3 min (cushion_until[Leger]; → "rate", die
# Restzeit wird nie verraten). Ausgelöst wird es von der Spielsteuerung (GameTable._apply) bei der nächsten angenommenen Aktion des Ziels
# aus CUSHION_TRIGGERS (Karte legen oder ziehen), dann geht "kissen_pop" an alle. Kissen gehen in keinen Eimer (weder Sender- noch
# Tisch-Eimer): Das Legen ist geheim, die Spiegel der anderen könnten es nicht mitzählen. Rundenende (note_turn außerhalb der
# Zugphasen), „seats“ und reset() lassen offene Kissen still verfallen. Der Spiegel des Legers kennt sein eigenes Kissen (Bestätigung)
# und sperrt ihn nur die Mindestzeit CUSHION_BLOCK_MIN_MS; alle anderen Spiegel wissen nichts davon (der Gastgeber antwortet mit fx_no).
# Beta 1.6.8 (Nutzerbefund S10: Knopf nach 60 s wieder frei, obwohl die Sperre noch lief): Die Sperre bleibt vor anderen geheim, der
# Leger selbst darf sie kennen. Der Gastgeber schickt ihm in der Bestätigung und in fx_no rate die Restdauer left (ms ab Versand, keine
# gemeinsame Uhr); sein Spiegel sperrt genau so lange (commit, note_cushion_wait). Ohne left (Gastgeber bis 1.6.7) wie bisher 60 s.

const FX_KINDS := ["snore", "alarm", "ball", "react", "kissen"]   # Wünsche der Spieler (Gast → Gastgeber)
const CUSHION := "kissen"                       # Beta 1.6.6: Furzkissen legen {to, reveal}
const CUSHION_POP := "kissen_pop"               # Beta 1.6.6: Furzkissen löst aus (nur Gastgeber → alle, nie ein Wunsch)
const CUSHION_BLOCK_MIN_MS := 60000             # Sperre des Legers nach jedem Kissen: zufällig 1 …
const CUSHION_BLOCK_MAX_MS := 180000            # … bis 3 min (beim Gastgeber ausgelost, Restzeit geheim)
const CUSHION_TRIGGERS := ["play", "draw", "accept", "stake"]   # angenommene Aktionen des Ziels, die das Kissen auslösen
const FX_REACTS := ["lachen", "schreck", "klatschen", "daumen", "baeh"]   # Beta 1.6.11: + „Bäää“ (😝); Geräte bis 1.6.10 verwerfen sie
const WAKE_KINDS := ["snore", "alarm"]
const FX_SLOW_MS := 10000                       # Schnarchen/Wecker erst, wenn das Ziel so lange nichts getan hat
const WAKE_BUSY_MS := {"snore": 4500, "alarm": 5000}   # so lange nimmt der Gastgeber für dieses Ziel keine zweite Weckaktion an
const BALL_BUCKET := 2                          # Papierkugel: Eimer je Sender …
const BALL_REFILL_MS := 5000                    # … +1 je 5 s
const BALL_GAP_MS := 1500                       # am selben Ziel frühestens so lange nach der letzten Kugel
const REACT_BUCKET := 3                         # Reaktion: Eimer je Sender …
const REACT_REFILL_MS := 3000                   # … +1 je 3 s
const TABLE_BUCKET := 8                         # alle Arten zusammen am Tisch …
const TABLE_REFILL_MS := 250                    # … +4 je s (schützt den Vermittler)
const TURN_PHASES := ["turn", "drawn", "color", "challenge", "gamble", "discard_pick"]   # = MauGame.PLAY_PHASES
const REACT_PHASES := ["turn", "drawn", "color", "challenge", "gamble", "discard_pick", "round_over", "game_over"]
const REFUSALS := ["late", "busy", "rate"]      # Gründe, die der Absender als fx_no erfährt

var turn := -1                    # Platz am Zug (−1: keiner, z. B. Rundenende)
var turn_no := 0                  # Zugnummer (steigt bei jedem Wechsel von turn)
var since := 0                    # Zugbeginn bzw. letzte eigene Aktion des Platzes am Zug (ms)
var sent := {}                    # Absender -> {kind: Zugnummer}
var busy_until := {}              # Ziel -> ms (laufende Weckaktion)
var last_ball := {}               # Ziel -> ms (letzte Papierkugel)
var buckets := {}                 # "Absender:Art" bzw. "table" -> {level: float, t: int}
var cushions := {}                # Beta 1.6.6: Ziel -> {from, reveal, at} (offenes Furzkissen; beim Gastgeber maßgeblich)
var cushion_until := {}           # Beta 1.6.6: Leger -> ms (Sperre bis dahin; Spiegel des Legers: ab 1.6.8 left des Gastgebers, sonst die Mindestzeit)


# Was in dieser Spielart geht: kinds = erlaubte Arten, bots_only = nur Computergegner als Ziel (Übung).
# host/client: alles; solo (Übung): Papierkugel und (ab 1.6.6) Furzkissen auf Computergegner; pass (Weitergeben) und sonst: nichts.
static func caps(mode: String) -> Dictionary:
	match mode:
		"host", "client":
			return {"kinds": FX_KINDS.duplicate(), "bots_only": false}
		"solo":
			return {"kinds": ["ball", CUSHION], "bots_only": true}
	return {"kinds": [], "bots_only": false}


# Tisch-Beschreibung aus einer Sicht (view.players: kind, connected, away, substituted). offs = Plätze mit Necken aus (fx_offs).
static func table_from_view(view: Dictionary, offs: Array, mode: String) -> Dictionary:
	var list: Array = []
	var players: Array = view.get("players", []) if view.get("players") is Array else []
	for p in players:
		var d: Dictionary = p if p is Dictionary else {}
		var s := list.size()
		list.append({"bot": str(d.get("kind", "")) == "bot",
			"gone": d.get("connected") == false or d.get("away") == true or d.get("substituted") == true,
			"off": offs.has(s)})
	return {"mode": mode, "phase": str(view.get("phase", "")), "turn": int(view.get("turn", -1)) if view.get("turn") is int else -1,
		"seats": list}


# Zug aus einer Sicht übernehmen (Gäste, Oberfläche).
func note_view(view: Dictionary, now: int) -> void:
	var t: int = int(view.get("turn", -1)) if view.get("turn") is int else -1
	note_turn(t, str(view.get("phase", "")), now)


# Platz am Zug (current_seat(), −1 außerhalb der Spielphasen). Wechsel: neue Zugnummer, Uhr neu.
func note_turn(cur: int, phase: String, now: int) -> void:
	if not phase in TURN_PHASES:
		cur = -1
		cushions.clear()          # Beta 1.6.6: Runde vorbei – offene Furzkissen verfallen still
	if cur != turn:
		turn = cur
		turn_no += 1
		since = now
		busy_until.clear()        # eine Weckaktion gilt nur im Zug ihres Ziels


# Angenommene Ereignisse: Ein Ereignis mit dem Platz am Zug setzt dessen Uhr zurück (wie TableView._poke); „seats“ (Dazuholen/Entfernen)
# leert den ganzen Zustand, weil sich die Platznummern verschieben.
func note_events(events: Array, now: int) -> void:
	for e in events:
		if not e is Dictionary:
			continue
		if str((e as Dictionary).get("e", "")) == "seats":
			reset()
			continue
		var s = (e as Dictionary).get("seat")
		if (s is int or s is float) and int(s) >= 0:
			note_act(int(s), now)


# Der Platz seat hat gehandelt (angenommene Aktion).
func note_act(seat: int, now: int) -> void:
	if seat == turn and turn >= 0:
		since = now


# Alles vergessen (Platzwechsel, neue Partie, neuer Gastgeber). Der Zug wird mit der nächsten Sicht neu gesetzt.
func reset() -> void:
	turn = -1
	turn_no += 1
	since = 0
	sent.clear()
	busy_until.clear()
	last_ball.clear()
	buckets.clear()
	cushions.clear()              # Beta 1.6.6: offene Kissen verfallen, Sperren beginnen neu (Platznummern gelten nicht mehr)
	cushion_until.clear()


# Wie lange das Ziel noch überlegen muss, bis Schnarchen/Wecker gehen (ms); −1 = es ist nicht am Zug.
func slow_left_ms(seat: int, now: int) -> int:
	if seat < 0 or seat != turn:
		return -1
	return maxi(0, FX_SLOW_MS - (now - since))


# Wunsch req {k, to?, r?} des Platzes sender prüfen. "" = erlaubt, sonst der Grund (siehe Kopf).
func check(sender: int, req: Dictionary, table: Dictionary, now: int) -> String:
	var k := str(req.get("k", ""))
	if not k in FX_KINDS:
		return "kind"
	var cap := caps(str(table.get("mode", "")))
	if not k in (cap.kinds as Array):
		return "mode"
	var seats: Array = table.get("seats", []) if table.get("seats") is Array else []
	if sender < 0 or sender >= seats.size():
		return "sender"
	var me: Dictionary = seats[sender]
	if bool(me.get("bot", false)) or bool(me.get("gone", false)):
		return "sender"
	if bool(me.get("off", false)):
		return "off"
	var phase := str(table.get("phase", ""))
	if k == "react":
		if not req.get("r") is String or not str(req.r) in FX_REACTS:
			return "kind"
		if not phase in REACT_PHASES:
			return "phase"
		if _level("%d:react" % sender, REACT_BUCKET, REACT_REFILL_MS, now) < 1.0:
			return "rate"
		return _table_ok(now)
	var to = req.get("to")
	if not to is int:
		return "target"
	if int(to) == sender:
		return "self"
	if int(to) < 0 or int(to) >= seats.size():
		return "target"
	var tgt: Dictionary = seats[int(to)]
	if bool(cap.bots_only) and not bool(tgt.get("bot", false)):
		return "target"
	if bool(tgt.get("gone", false)):
		return "target"
	if bool(tgt.get("off", false)):
		return "off"
	if k == CUSHION:
		# Beta 1.6.6: jeder andere Platz (Übung: nur Bots), nur während der Runde; erst die eigene Sperre, dann das Ziel
		if not phase in TURN_PHASES:
			return "phase"
		if cushion_until.has(sender) and now < int(cushion_until[sender]):
			return "rate"
		if cushions.has(int(to)):
			return "busy"
		return ""
	if k == "ball":
		if not phase in TURN_PHASES:
			return "phase"
		if _level("%d:ball" % sender, BALL_BUCKET, BALL_REFILL_MS, now) < 1.0:
			return "rate"
		if last_ball.has(int(to)) and now - int(last_ball[int(to)]) < BALL_GAP_MS:
			return "rate"
		return _table_ok(now)
	# snore / alarm: nur Menschen, nur am Zug, erst nach FX_SLOW_MS, je Sender und Zug einmal, je Ziel eine Weckaktion
	if bool(tgt.get("bot", false)):
		return "target"
	if not phase in TURN_PHASES or int(to) != int(table.get("turn", -1)) or int(to) != turn:
		return "late"
	if now - since < FX_SLOW_MS:
		return "early"
	if int((sent.get(sender, {}) as Dictionary).get(k, -1)) == turn_no:
		return "once"
	if busy_until.has(int(to)) and now < int(busy_until[int(to)]):
		return "busy"
	return _table_ok(now)


# Angenommenes Ereignis {k, from, to?, r?} verbuchen (Gastgeber nach check(), Spiegel beim Empfang). Ohne Prüfung.
func commit(msg: Dictionary, now: int) -> void:
	var k := str(msg.get("k", ""))
	var from := int(msg.get("from", -1)) if msg.get("from") is int else -1
	var to := int(msg.get("to", -1)) if msg.get("to") is int else -1
	if k == CUSHION:
		# Spiegel des Legers (Bestätigung): Kissen merken. Sperre: Beta 1.6.8 die Restdauer left des Gastgebers (bereinigt in
		# NetProtocol.clean_fx); ohne left (Gastgeber bis 1.6.7) nur die Mindestzeit (die echte kannte dann nur der Gastgeber)
		if from >= 0 and to >= 0:
			var block := int(msg.left) if msg.get("left") is int and int(msg.left) >= 0 else CUSHION_BLOCK_MIN_MS
			place_cushion(from, to, (msg.get("reveal") is bool and bool(msg.reveal)), now, block)
		return
	if k == CUSHION_POP:
		cushions.erase(to)
		return
	_take("table", TABLE_BUCKET, TABLE_REFILL_MS, now)
	match k:
		"react":
			_take("%d:react" % from, REACT_BUCKET, REACT_REFILL_MS, now)
		"ball":
			_take("%d:ball" % from, BALL_BUCKET, BALL_REFILL_MS, now)
			if to >= 0:
				last_ball[to] = now
		"snore", "alarm":
			if not sent.has(from):
				sent[from] = {}
			(sent[from] as Dictionary)[k] = turn_no
			if to >= 0:
				busy_until[to] = now + int(WAKE_BUSY_MS[k])


# --- Furzkissen (Beta 1.6.6) ---

# Kissen auf den Platz to legen (nach check() == ""): block_ms = Sperre des Legers (Gastgeber: cushion_block_ms(Zufall), Spiegel: Minimum).
func place_cushion(from: int, to: int, reveal: bool, now: int, block_ms: int) -> void:
	cushions[to] = {"from": from, "reveal": reveal, "at": now}
	cushion_until[from] = now + block_ms


# Beta 1.6.8: Restdauer der Sperre des Legers seat (ms, 0 = frei) – geht nur an ihn selbst (Bestätigung, fx_no rate).
func cushion_left_ms(seat: int, now: int) -> int:
	return maxi(0, int(cushion_until[seat]) - now) if cushion_until.has(seat) else 0


# Beta 1.6.8: Spiegel des Legers – der Gastgeber nennt die Restdauer seiner Sperre (fx_no rate mit left): genau so lange gesperrt.
func note_cushion_wait(seat: int, left_ms: int, now: int) -> void:
	if seat >= 0 and left_ms >= 0:
		cushion_until[seat] = now + left_ms


# Offenes Kissen am Platz seat ({} = keins), ohne es zu entfernen.
func cushion_at(seat: int) -> Dictionary:
	return (cushions[seat] as Dictionary).duplicate() if cushions.has(seat) else {}


# Kissen am Platz seat herausnehmen (es löst aus); {} = keins.
func take_cushion(seat: int) -> Dictionary:
	var c := cushion_at(seat)
	cushions.erase(seat)
	return c


# Sperre aus einer Zufallszahl u ∈ [0, 1]: gleichmäßig 1–3 min (ganze ms).
static func cushion_block_ms(u: float) -> int:
	return CUSHION_BLOCK_MIN_MS + int(roundf(clampf(u, 0.0, 1.0) * float(CUSHION_BLOCK_MAX_MS - CUSHION_BLOCK_MIN_MS)))


# Löst diese Aktion (wenn angenommen) ein Kissen aus? Nur Karte legen oder ziehen – nicht Mau, Erwischt, Farbwahl, Behalten …
static func cushion_trigger(action: Dictionary) -> bool:
	return action.get("a") is String and str(action.a) in CUSHION_TRIGGERS


func _table_ok(now: int) -> String:
	return "" if _level("table", TABLE_BUCKET, TABLE_REFILL_MS, now) >= 1.0 else "rate"


# Füllstand eines Eimers jetzt (voll = cap), ohne ihn zu verändern.
func _level(key: String, cap: int, refill_ms: int, now: int) -> float:
	if not buckets.has(key):
		return float(cap)
	var b: Dictionary = buckets[key]
	return minf(float(cap), float(b.level) + float(maxi(0, now - int(b.t))) / float(refill_ms))


func _take(key: String, cap: int, refill_ms: int, now: int) -> void:
	buckets[key] = {"level": maxf(0.0, _level(key, cap, refill_ms, now) - 1.0), "t": now}
