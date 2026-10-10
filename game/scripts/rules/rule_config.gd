class_name RuleConfig
extends RefCounted
# Regeloptionen (docs/BETA1_PLAN.md Abschnitt 4, Regelbericht Abschnitte 1.13, 2 und 4). Standard = Voreinstellung „offiziell“
# (Fassung 2024). from_dict() nimmt nur bekannte Schlüssel und gültige Werte an (JSON-Zahlen kommen als float), alles andere
# bleibt beim Standard. describe() liefert kurze deutsche Zeilen für die Regelübersicht.
# Hausregeln mit Zusatzkarten: Kartentausch (swap_cards, swap_direction; in „Familie“ an), Glücksspiel (gamble_cards) und
# Farbe mit ablegen (discard_color; beide in keiner Voreinstellung an). Ohne sie bleibt alles wie im Grundspiel.

# Auswahl-Optionen: Schlüssel → erlaubte Werte, der erste ist der Standard.
const CHOICES := {
	"round_end": ["first", "last"],
	"scoring": ["none", "points500"],
	"draw_rule": ["one", "until_playable"],
	"drawn_card": ["may", "must", "may_not"],
	"draw_play": ["drawn", "any"],             # nach freiwilligem Ziehen nur die gezogene Karte (offiziell) oder jede passende (Hausregel)
	"stacking": ["off", "same"],
	"penalty_turn": ["skip", "play"],          # nach dem Strafziehen aussetzen (offiziell) oder gleich weiterspielen (Hausregel)
	"wild_restriction": ["free", "enforce", "bluff"],  # "bluff" (Anzweifeln) nur aus Verträglichkeit, Oberflächen bieten es nicht an
	"mau_call": ["catch", "auto", "reminder", "off"],
	"flip_last_card": ["execute", "ignore"],
	"swap_cards": ["off", "on"],               # Hausregel Kartentausch: 4 zusätzliche Karten (116), siehe docs/module/A.md
	"swap_direction": ["clockwise", "counter", "play", "against"],  # Platz+1, Platz−1, in bzw. gegen die Spielrichtung
	"gamble_cards": ["off", "on"],             # Hausregel Glücksspiel: 2 zusätzliche Joker, siehe docs/module/A.md
	"discard_color": ["off", "on"],            # Hausregel Farbe mit ablegen: 6 zusätzliche Karten, siehe docs/module/A.md
	"flip_surprise": ["off", "on"],            # Hausregel Flip-Überraschung: Karte oben nach dem Flip wirkt, als hätte der Flip-Spieler sie gelegt
	"flip_mode": ["pile", "card"],             # Flip wendet die ganze Ablage (offiziell) oder nur die gelegte Flip-Karte (Hausregel)
}
const FLAGS := {
	"wild_counts_for_bluff": true,
	"jagd_wild_stops": false,
	"backs_visible": true,
	"peek_own_backs": true,
	"two_player_reverse_skips": true,
}
# Zahlen: Standard, kleinster, größter Wert.
const NUMBERS := {
	"target": [500, 100, 5000],
	"hand_size": [7, 5, 10],
	"mau_penalty": [2, 1, 4],
}
const PRESETS := {
	"offiziell": {},
	"klassisch500": {"scoring": "points500"},
	"familie": {"round_end": "last", "stacking": "same", "penalty_turn": "play", "wild_restriction": "free", "mau_penalty": 1,
		"swap_cards": "on", "swap_direction": "play", "gamble_cards": "on", "discard_color": "on", "flip_surprise": "on",
		"flip_mode": "card", "draw_play": "any"},
	"mau_mau": {"stacking": "same", "wild_restriction": "enforce", "mau_penalty": 1},
}
const PRESET_TITLES := {"offiziell": "Offiziell", "klassisch500": "Klassisch 500", "familie": "Familie", "mau_mau": "Mau-Mau-Tradition"}

var round_end := "first"
var scoring := "none"
var target := 500
var hand_size := 7
var draw_rule := "one"
var drawn_card := "may"
var draw_play := "drawn"
var stacking := "off"
var penalty_turn := "skip"
var wild_restriction := "free"
var wild_counts_for_bluff := true
var jagd_wild_stops := false
var mau_call := "catch"
var mau_penalty := 2
var backs_visible := true
var peek_own_backs := true
var two_player_reverse_skips := true
var flip_last_card := "execute"
var swap_cards := "off"
var swap_direction := "clockwise"
var gamble_cards := "off"
var discard_color := "off"
var flip_surprise := "off"
var flip_mode := "pile"


static func keys() -> Array:
	var out: Array = []
	out.append_array(CHOICES.keys())
	out.append_array(FLAGS.keys())
	out.append_array(NUMBERS.keys())
	return out


static func preset(preset_name: String) -> RuleConfig:
	var cfg := RuleConfig.new()
	cfg.apply_dict(PRESETS.get(preset_name, {}))
	return cfg


static func preset_names() -> Array:
	return PRESETS.keys()


# Frühere „Familie“ (0.1.1 bis 0.1.3), wird von migrate_dict auf die heutige gehoben.
const OLD_FAMILIE := {"round_end": "last", "stacking": "same", "penalty_turn": "play", "wild_restriction": "enforce",
	"mau_penalty": 1, "swap_cards": "on"}


# Gespeicherte Regeln (App-Einstellungen, Regelsätze, Regeln vom Gastgeber) auf den Stand 0.1.4 bringen: Anzweifeln ("bluff")
# gibt es in der Oberfläche nicht mehr und wird zu "free" (0.1.3). Regeln, die genau der früheren „Familie“ entsprechen (mit
# enforce oder, nach bluff → free, mit free), werden zur heutigen „Familie“ (0.1.4). Liefert eine Kopie, d bleibt unverändert.
# Ohne Schlüssel flip_mode (bis 1.0.1) wird die damalige „Familie“ (heutige ohne flip_mode = card) zur heutigen (1.0.2), ebenso
# ohne Schlüssel draw_play (bis 1.1.2) die damalige „Familie“ (heutige ohne draw_play = any) zur heutigen (1.1.3).
static func migrate_dict(d: Dictionary) -> Dictionary:
	var out := d.duplicate()
	if str(out.get("wild_restriction", "")) == "bluff":
		out["wild_restriction"] = "free"
	var mine := RuleConfig.from_dict(out).to_dict()
	if not d.has("flip_mode") or not d.has("draw_play"):
		var fam := RuleConfig.from_dict(out)
		if not d.has("flip_mode"):
			fam.flip_mode = "card"
		if not d.has("draw_play"):
			fam.draw_play = "any"
		if fam.preset_name() == "familie":
			out.merge(RuleConfig.preset("familie").to_dict(), true)
			return out
	for wr in ["enforce", "free"]:
		var old := RuleConfig.from_dict(OLD_FAMILIE)
		old.wild_restriction = wr
		var want := old.to_dict()
		if wr == "free":                 # dann zählt der (entfallene) Schalter nicht
			want["wild_counts_for_bluff"] = mine["wild_counts_for_bluff"]
		if mine == want:
			out.merge(RuleConfig.preset("familie").to_dict(), true)
			return out
	return out


static func from_dict(d: Dictionary) -> RuleConfig:
	var cfg := RuleConfig.new()
	cfg.apply_dict(d)
	return cfg


func to_dict() -> Dictionary:
	var d := {}
	for k in CHOICES:
		d[k] = str(get(k))
	for k in FLAGS:
		d[k] = bool(get(k))
	for k in NUMBERS:
		d[k] = int(get(k))
	return d


# Übernimmt gültige Werte aus d; Unbekanntes und Ungültiges bleibt unverändert.
func apply_dict(d: Dictionary) -> void:
	for k in d:
		var key := str(k)
		var v: Variant = d[k]
		if CHOICES.has(key):
			if (CHOICES[key] as Array).has(str(v)):
				set(key, str(v))
		elif FLAGS.has(key):
			if v is bool:
				set(key, v)
			elif v is int or v is float:
				set(key, v != 0)
		elif NUMBERS.has(key):
			if v is int or v is float or (v is String and (v as String).is_valid_int()):
				var limits: Array = NUMBERS[key]
				set(key, clampi(int(v), int(limits[1]), int(limits[2])))


func duplicate_config() -> RuleConfig:
	return RuleConfig.from_dict(to_dict())


func equals(other: RuleConfig) -> bool:
	return other != null and to_dict() == other.to_dict()


# Name der passenden Voreinstellung oder "" bei eigenen Regeln. Ohne Kartentausch-Karten zählt deren Richtung nicht.
func preset_name() -> String:
	var mine := to_dict()
	if swap_cards == "off":
		mine["swap_direction"] = CHOICES["swap_direction"][0]
	if wild_restriction == "free":   # dann zählt der (in der Oberfläche entfallene) Schalter nicht
		mine["wild_counts_for_bluff"] = FLAGS["wild_counts_for_bluff"]
	for p in PRESETS:
		if RuleConfig.preset(p).to_dict() == mine:
			return p
	return ""


# Kartenzahl der Partie: 112, dazu Kartentausch +4, Glücksspiel +2, Farbe mit ablegen +6 (höchstens 124).
func card_count() -> int:
	return CardDB.card_count(swap_cards == "on", gamble_cards == "on", discard_color == "on")


# Gesichtscodes des Decks einer Seite (s: 0 hell, 1 dunkel) für diese Regeln (CardDB.deck, nicht verändern).
func deck(s: int) -> PackedInt32Array:
	return CardDB.deck(s, swap_cards == "on", gamble_cards == "on", discard_color == "on")


# Spielt die Partie mit Zusatzkarten einer Hausregel?
func has_extra_cards() -> bool:
	return swap_cards == "on" or gamble_cards == "on" or discard_color == "on"


# Tauschrichtung beim Kartentausch als Platzschritt (±1): Uhrzeigersinn +1, gegen den Uhrzeigersinn −1, in bzw. gegen die
# aktuelle Spielrichtung play_dir (±1).
func swap_step(play_dir: int) -> int:
	var d := 1 if play_dir >= 0 else -1
	match swap_direction:
		"counter":
			return -1
		"play":
			return d
		"against":
			return -d
	return 1


# Punktwertung gilt nur, wenn die Runde beim ersten Fertigen endet; bis zum Letzten zählen Platzierungen.
func effective_scoring() -> String:
	return "points500" if scoring == "points500" and round_end == "first" else "none"


# Kurze Zeilen für die Regelübersicht, je eine pro Regelgruppe.
func describe() -> Array[String]:
	var out: Array[String] = []
	var p := preset_name()
	if p != "":
		out.append(I18n.t("Voreinstellung: %s.") % I18n.t(PRESET_TITLES[p]))
	if round_end == "first":
		out.append(I18n.t("Wer zuerst alle Karten los ist, gewinnt die Runde."))
	else:
		out.append(I18n.t("Bis zum Letzten: Wer fertig ist, scheidet aus. Gespielt wird um die Plätze, bis nur einer Karten hat."))
	if effective_scoring() == "points500":
		out.append(I18n.t("Wertung: Der Sieger bekommt die Punkte aller übrigen Handkarten. Wer zuerst %d Punkte hat, gewinnt die Partie.") % target)
	elif scoring == "points500":
		out.append(I18n.t("Wertung: Platzierungen (Punkte zählen nur, wenn die Runde beim ersten Fertigen endet)."))
	else:
		out.append(I18n.t("Wertung: keine – jede Runde zählt für sich, gezählt werden die Siege."))
	out.append(I18n.t("%d Handkarten zu Beginn.") % hand_size)
	if draw_rule == "one":
		out.append(I18n.t("Passt nichts, ziehst du eine Karte."))
	else:
		out.append(I18n.t("Passt nichts, ziehst du so lange, bis eine Karte passt."))
	match drawn_card:
		"may":
			out.append(I18n.t("Eine passende gezogene Karte darfst du sofort legen."))
		"must":
			out.append(I18n.t("Eine passende gezogene Karte musst du sofort legen."))
		"may_not":
			out.append(I18n.t("Eine gezogene Karte darfst du erst im nächsten Zug legen."))
	if draw_play == "any" and draw_rule == "one":
		out.append(I18n.t("Nach dem Ziehen darfst du eine andere passende Karte legen oder alles behalten.") if drawn_card == "may_not" else I18n.t("Nach dem Ziehen darfst du jede passende Karte legen oder alles behalten."))
	if stacking == "same":
		out.append(I18n.t("Stapeln: Wer eine Ziehkarte abbekommt, darf die gleiche drauflegen. Die Summe wandert weiter; bei der Farbjagd zieht das letzte Opfer bis zur Farbe."))
	else:
		out.append(I18n.t("Kein Stapeln: Wer eine Ziehkarte abbekommt, zieht und %s.") % penalty_tail())
	if penalty_turn == "play":
		out.append(I18n.t("Nach dem Strafziehen bist du trotzdem dran: Du darfst legen – oder ziehst ganz normal, wenn nichts passt."))
	var cond := I18n.t("keine Karte in der aktuellen Farbe und keinen anderen Joker hat") if wild_counts_for_bluff else I18n.t("keine Karte in der aktuellen Farbe hat")
	match wild_restriction:
		"bluff":
			out.append(I18n.t("Wünscher +2 und Farbjagd nur, wenn man %s. Der Nächste darf anzweifeln.") % cond)
		"enforce":
			out.append(I18n.t("Wünscher +2 und Farbjagd nur, wenn man %s – die App achtet darauf.") % cond)
		"free":
			out.append(I18n.t("Wünscher +2 und Farbjagd dürfen immer gelegt werden."))
	if jagd_wild_stops:
		out.append(I18n.t("Farbjagd: Ein gezogener Joker beendet das Ziehen."))
	match mau_call:
		"catch":
			out.append(I18n.t("„Mau!“ bei der vorletzten Karte rufen. Wer es vergisst und erwischt wird, zieht %d.") % mau_penalty)
		"auto":
			out.append(I18n.t("„Mau!“ bei der vorletzten Karte rufen. Wer es vergisst, zieht automatisch %d.") % mau_penalty)
		"reminder":
			out.append(I18n.t("„Mau!“ rufen ist freiwillig, die App erinnert nur daran."))
		"off":
			out.append(I18n.t("Ohne „Mau!“-Ansage."))
	if backs_visible:
		out.append(I18n.t("Die Rückseiten der Mitspielerkarten sind sichtbar."))
	else:
		out.append(I18n.t("Die Rückseiten der Mitspielerkarten sind verdeckt."))
	if peek_own_backs:
		out.append(I18n.t("Eigene Rückseiten darfst du ansehen."))
	if two_player_reverse_skips:
		out.append(I18n.t("Zu zweit wirkt der Richtungswechsel wie Aussetzen."))
	if flip_last_card == "execute":
		out.append(I18n.t("Ein Flip als letzte Karte wird noch ausgeführt; gewertet wird die neue Seite."))
	else:
		out.append(I18n.t("Ein Flip als letzte Karte wird nicht mehr ausgeführt."))
	if flip_mode == "card":
		out.append(I18n.t("Flip dreht nur die gelegte Karte: Oben liegt ihre andere Seite, die übrige Ablage bleibt zur Seite gelegt."))
	if flip_surprise == "on":
		out.append(I18n.t("Flip-Überraschung: Die Karte, die nach dem Flip oben liegt, wirkt, als hätte der Flip-Spieler sie gelegt."))
	# Zusatzkarten: Mit genau einer Hausregel steht die Kartenzahl in ihrer Zeile (Kartentausch wie bisher „(116)“), mit mehreren
	# in einer eigenen Zeile.
	var extras := (1 if swap_cards == "on" else 0) + (1 if gamble_cards == "on" else 0) + (1 if discard_color == "on" else 0)
	var total := " (%d)" % card_count() if extras == 1 else ""
	if swap_cards == "on":
		out.append(I18n.t("Kartentausch: 4 zusätzliche Karten%s. Wer eine legt, lässt alle ihre ganze Hand weitergeben, %s.") % [total, swap_direction_text()])
	if gamble_cards == "on":
		out.append(I18n.t("Glücksspiel: 2 zusätzliche Joker%s. Wer einen legt, setzt Karte um Karte verdeckt und drückt den Glücksspielknopf – bei einem Treffer 1 bis 10 Karten ziehen und den Einsatz zurücknehmen. Nach einem Druck ohne Treffer weiter riskieren oder aufhören (der Einsatz kommt unter die Ablage); mit leerer Hand bist du fertig.") % total)
	if discard_color == "on":
		out.append(I18n.t("Farbe ablegen: 6 zusätzliche Karten%s. Wer eine legt, legt dazu eigene Karten dieser Farbe ab, du wählst aus; Joker bleiben auf der Hand. Beim Ablege-Joker wählst du erst die Ablegefarbe, danach die Farbe, mit der es weitergeht.") % total)
	if extras > 1:
		out.append(I18n.t("Gespielt wird mit %d Karten.") % card_count())
	return out


# Tauschrichtung als Satzteil, z. B. „immer im Uhrzeigersinn“ oder „in der aktuellen Spielrichtung“.
func swap_direction_text() -> String:
	match swap_direction:
		"counter":
			return I18n.t("immer gegen den Uhrzeigersinn")
		"play":
			return I18n.t("in der aktuellen Spielrichtung")
		"against":
			return I18n.t("gegen die aktuelle Spielrichtung")
	return I18n.t("immer im Uhrzeigersinn")


# Kurzname einer Tauschrichtung für Auswahllisten.
static func swap_direction_title(value: String) -> String:
	match value:
		"counter":
			return I18n.t("Gegen den Uhrzeigersinn")
		"play":
			return I18n.t("In Spielrichtung")
		"against":
			return I18n.t("Gegen die Spielrichtung")
	return I18n.t("Im Uhrzeigersinn")


# Was nach dem Strafziehen passiert, als Satzende: „… zieht 5 und setzt aus.“ bzw. „… und ist danach trotzdem dran.“
func penalty_tail() -> String:
	return I18n.t("setzt aus") if penalty_turn == "skip" else I18n.t("ist danach trotzdem dran")
