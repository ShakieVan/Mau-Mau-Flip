class_name RulesText
extends RefCounted
# Deutsche Texte zum Regelwerk (docs/BETA1_PLAN.md Abschnitt 4): Namen von Farben und Karten, Kartenhilfe je Gesicht passend zur
# aktiven RuleConfig (Geste „halten und nach unten auf ?“) und die Regelübersicht in kurzen Absätzen. Begriffe nach
# Regelbericht Abschnitt 3 (keine Marken des Vorbilds).

const COLOR_NAMES := {"rot": "Rot", "gelb": "Gelb", "gruen": "Grün", "blau": "Blau",
	"pink": "Pink", "tuerkis": "Türkis", "orange": "Orange", "lila": "Lila"}
const KIND_NAMES := {"plus1": "+1", "plus5": "+5", "aussetzen": "Aussetzen", "alle_aussetzen": "Alle aussetzen",
	"richtungswechsel": "Richtungswechsel", "flip": "Flip", "wuenscher": "Wünscher", "wuenscher_plus2": "Wünscher +2",
	"farbjagd": "Farbjagd"}
# Mit unbestimmtem Artikel im Akkusativ („lege … oder eine 7“).
const KIND_WITH_ARTICLE := {"plus1": "eine +1", "plus5": "eine +5", "aussetzen": "ein Aussetzen",
	"alle_aussetzen": "ein Alle aussetzen", "richtungswechsel": "einen Richtungswechsel", "flip": "einen Flip",
	"wuenscher": "einen Wünscher", "wuenscher_plus2": "einen Wünscher +2", "farbjagd": "eine Farbjagd"}
const SIDE_NAMES := {"hell": "helle Seite", "dunkel": "dunkle Seite"}


static func color_name(color: String) -> String:
	return str(COLOR_NAMES.get(color, color))


static func kind_name(kind: String) -> String:
	return str(KIND_NAMES.get(kind, kind))


static func side_name(side: String) -> String:
	return str(SIDE_NAMES.get(side, side))


# Kurzer Name eines Gesichts, z. B. „Rot 7“, „Gelb +1“, „Lila Alle aussetzen“, „Wünscher +2“.
static func face_title(key: String) -> String:
	var f := CardDB.parse_key(key)
	if f.is_empty():
		return key
	var kind := str(f.kind)
	if str(f.color) == "":
		return kind_name(kind)
	if kind == "zahl":
		return "%s %d" % [color_name(str(f.color)), int(f.value)]
	return "%s %s" % [color_name(str(f.color)), kind_name(kind)]


# Wie man auf eine Karte mit diesem Gesicht antwortet („eine 7“, „ein Aussetzen“).
static func match_phrase(key: String) -> String:
	var f := CardDB.parse_key(key)
	if f.is_empty():
		return ""
	if str(f.kind) == "zahl":
		return "eine %d" % int(f.value)
	return str(KIND_WITH_ARTICLE.get(str(f.kind), kind_name(str(f.kind))))


# Kartenhilfe: kurze Sätze zu genau diesem Gesicht unter den aktiven Regeln (erster Eintrag = Wirkung).
static func card_help(key: String, config: RuleConfig = null) -> Array[String]:
	var cfg := config if config != null else RuleConfig.new()
	var f := CardDB.parse_key(key)
	var out: Array[String] = []
	if f.is_empty():
		out.append("Unbekannte Karte.")
		return out
	var side := str(f.side)
	var other := CardDB.other_side(side)
	var color := color_name(str(f.color))
	var kind := str(f.kind)
	var title := kind_name(kind)
	match kind:
		"zahl":
			out.append("Zahlenkarte ohne Sonderwirkung.")
			out.append("Passt auf %s und auf jede %d." % [color, int(f.value)])
		"plus1", "plus5":
			var n := int(CardDB.DRAW_AMOUNT[kind])
			out.append("Der Nächste zieht %d %s und setzt aus." % [n, "Karte" if n == 1 else "Karten"])
			out.append("Passt auf %s und auf jede %s." % [color, title])
			if cfg.stacking == "same":
				out.append("%s darf gestapelt werden: Wer sie abbekommt, kann eine %s drauflegen; die Summe wandert weiter." % [title, title])
			else:
				out.append("Nicht stapelbar: Wer sie abbekommt, zieht sofort und setzt aus.")
			out.append("Auch als letzte Karte: Der Nächste zieht trotzdem.")
		"aussetzen":
			out.append("Der Nächste wird übersprungen.")
			out.append("Passt auf %s und auf jedes Aussetzen." % color)
			out.append("Zu zweit bist du gleich noch einmal dran.")
		"alle_aussetzen":
			out.append("Alle anderen setzen aus: Du bist sofort noch einmal dran und legst oder ziehst ganz normal.")
			out.append("Passt auf %s und auf jedes Alle aussetzen." % color)
			if cfg.round_end == "last":
				out.append("Bist du damit fertig, macht der Nächste weiter.")
		"richtungswechsel":
			out.append("Die Spielrichtung dreht sich um.")
			out.append("Passt auf %s und auf jeden Richtungswechsel." % color)
			if cfg.two_player_reverse_skips:
				out.append("Zu zweit wirkt er wie Aussetzen: Du bist gleich noch einmal dran.")
			else:
				out.append("Zu zweit hat er keine Wirkung.")
		"flip":
			out.append("Wendet alles: Ablage, Nachziehstapel und alle Hände. Danach gilt die %s." % side_name(other))
			out.append("Passt auf %s und auf jeden Flip – ein Flip ist kein Joker." % color)
			out.append("Oben liegt dann die bisher unterste Ablagekarte mit ihrer anderen Seite. Eine Wunschfarbe verfällt.")
			out.append("Liegt danach eine Aktionskarte oben, wirkt sie nicht. Liegt ein Joker oben, wählst du die Farbe.")
			if cfg.flip_last_card == "execute":
				out.append("Als letzte Karte wird der Flip noch ausgeführt; gewertet wird die neue Seite.")
			else:
				out.append("Als letzte Karte wird der Flip nicht mehr ausgeführt.")
		"wuenscher":
			out.append("Passt immer. Du wünschst dir eine Farbe, auch die bisherige.")
			out.append("Du darfst ihn auch legen, wenn du andere passende Karten hast.")
		"wuenscher_plus2", "farbjagd":
			if kind == "wuenscher_plus2":
				out.append("Passt immer. Du wünschst eine Farbe, der Nächste zieht 2 Karten und setzt aus.")
			else:
				out.append("Passt immer. Du wünschst eine Farbe; der Nächste zieht, bis er eine Karte dieser Farbe hat, behält alle gezogenen Karten und setzt aus.")
				if cfg.jagd_wild_stops:
					out.append("Ein gezogener Joker beendet die Jagd.")
				else:
					out.append("Ein gezogener Joker beendet die Jagd nicht.")
			out.append_array(_restriction_lines(kind, cfg))
			if cfg.stacking == "same":
				if kind == "wuenscher_plus2":
					out.append("Wünscher +2 darf gestapelt werden: Wer ihn abbekommt, kann einen Wünscher +2 drauflegen; die Summe wandert weiter.")
				else:
					out.append("Farbjagd darf weitergegeben werden: Das letzte Opfer zieht bis zur zuletzt gewünschten Farbe.")
			out.append("Auch als letzte Karte: Der Nächste zieht trotzdem.")
	out.append(_points_line(kind, CardDB.points(f), cfg))
	return out


static func _restriction_lines(kind: String, cfg: RuleConfig) -> Array[String]:
	var out: Array[String] = []
	var cond := "keine Karte in der aktuellen Farbe hast"
	if cfg.wild_counts_for_bluff:
		cond += " und keinen anderen Joker"
	match cfg.wild_restriction:
		"bluff":
			out.append("Eigentlich nur erlaubt, wenn du %s. Bluffen ist möglich." % cond)
			if kind == "wuenscher_plus2":
				out.append("Der Nächste darf anzweifeln: Hast du geblufft, ziehst du %s; warst du ehrlich, zieht er %s und setzt aus."
					% ["die Strafe" if cfg.stacking == "same" else "2", "2 mehr" if cfg.stacking == "same" else "4"])
			else:
				out.append("Der Nächste darf anzweifeln: Hast du geblufft, ziehst du bis zur Farbe; warst du ehrlich, zieht er bis zur Farbe, dann 2 weitere, und setzt aus.")
			out.append("Die gewünschte Farbe bleibt in jedem Fall.")
		"enforce":
			out.append("Nur legbar, wenn du %s – die App achtet darauf." % cond)
		"free":
			out.append("Darf jederzeit gelegt werden.")
	return out


static func _points_line(kind: String, pts: int, cfg: RuleConfig) -> String:
	var unit := "Punkt" if pts == 1 else "Punkte"
	if cfg.effective_scoring() == "points500":
		return "Zählt %d %s bei der Wertung." % [pts, unit]
	return "Wert: %d %s." % [pts, unit]


# Regelübersicht: kurze Absätze {title, text}, passend zu den aktiven Regeln.
static func overview(config: RuleConfig = null) -> Array[Dictionary]:
	var cfg := config if config != null else RuleConfig.new()
	var out: Array[Dictionary] = []
	var goal := "Wer zuerst alle Karten los ist, gewinnt die Runde." if cfg.round_end == "first" \
		else "Gespielt wird bis zum Letzten: Wer fertig ist, scheidet aus, die anderen spielen um die Plätze weiter."
	if cfg.effective_scoring() == "points500":
		goal += " Der Sieger bekommt die Punkte aller übrigen Handkarten (Zahlen nach Wert, +1 10, +5, Aussetzen, Richtungswechsel und Flip 20, Alle aussetzen 30, Wünscher 40, Wünscher +2 50, Farbjagd 60). Wer zuerst %d Punkte hat, gewinnt die Partie." % cfg.target
	out.append({"title": "Ziel", "text": goal})
	out.append({"title": "Karten", "text": "112 Karten mit einer hellen und einer dunklen Seite, Zahlen 1 bis 9. Hell: Rot, Gelb, Grün, Blau. Dunkel: Pink, Türkis, Orange, Lila. Alle Karten liegen gleich herum: Du spielst die aktive Seite, die anderen sehen deine Rückseiten%s." % ("" if cfg.backs_visible else " nicht (verdeckt)")})
	out.append({"title": "Start", "text": "Jeder bekommt %d Karten. Die Runde beginnt auf der hellen Seite. Ist die erste Ablagekarte keine Zahl, bleibt sie liegen und die nächste wird aufgedeckt. Der Geber wechselt jede Runde im Uhrzeigersinn; es beginnt der Spieler links von ihm." % cfg.hand_size})
	var draw := "Passt nichts, ziehst du eine Karte." if cfg.draw_rule == "one" else "Passt nichts, ziehst du so lange, bis eine Karte passt."
	match cfg.drawn_card:
		"may":
			draw += " Passt sie, darfst du sie sofort legen."
		"must":
			draw += " Passt sie, musst du sie sofort legen."
		"may_not":
			draw += " Gelegt wird sie frühestens im nächsten Zug."
	var voluntary := "Du darfst auch freiwillig ziehen; danach ist dein Zug vorbei." if cfg.drawn_card == "may_not" \
		else "Du darfst auch freiwillig ziehen; dann darfst du nur die gezogene Karte legen."
	out.append({"title": "Spielzug", "text": "Lege eine Karte, die in Farbe, Zahl oder Symbol zur obersten Ablagekarte passt. Joker passen immer. %s %s" % [draw, voluntary]})
	out.append({"title": "Helle Seite", "text": "+1: Der Nächste zieht 1 und setzt aus. Aussetzen: Der Nächste wird übersprungen. Richtungswechsel: Die Richtung dreht sich. Wünscher: Farbe wünschen. Wünscher +2: Farbe wünschen, der Nächste zieht 2 und setzt aus."})
	out.append({"title": "Dunkle Seite", "text": "+5: Der Nächste zieht 5 und setzt aus. Alle aussetzen: Du bist sofort noch einmal dran. Richtungswechsel und Wünscher wie hell. Farbjagd: Farbe wünschen, der Nächste zieht, bis er diese Farbe hat, und setzt aus."})
	out.append({"title": "Flip", "text": "Der Flip wendet Ablage, Nachziehstapel und alle Hände. Oben liegt dann die bisher unterste Ablagekarte mit ihrer anderen Seite. Eine Wunschfarbe verfällt, eine Aktionskarte oben wirkt nicht; liegt ein Joker oben, wählt der Flip-Spieler die Farbe."})
	var stack := "Ziehkarten werden nicht gestapelt: Wer sie abbekommt, zieht und setzt aus." if cfg.stacking == "off" \
		else "Wer eine Ziehkarte abbekommt, darf die gleiche drauflegen (+1 auf +1, +5 auf +5, Wünscher +2 auf Wünscher +2, Farbjagd auf Farbjagd). Die Summe wandert weiter; bei der Farbjagd zieht das letzte Opfer bis zur Farbe."
	out.append({"title": "Ziehkarten", "text": stack + " Ist die letzte Karte eine Ziehkarte, zieht der Nächste trotzdem."})
	var cond := "keine Karte in der aktuellen Farbe hat"
	if cfg.wild_counts_for_bluff:
		cond += " und keinen anderen Joker"
	var wild := ""
	match cfg.wild_restriction:
		"bluff":
			wild = "Wünscher +2 und Farbjagd darf nur legen, wer %s. Der Betroffene darf anzweifeln und sieht dann die Hand. Bluff erwischt: Der Leger zieht die Strafe selbst, der Herausforderer ist normal dran. Leger war ehrlich: Der Herausforderer zieht 2 Karten mehr und setzt aus. Die Wunschfarbe bleibt." % cond
		"enforce":
			wild = "Wünscher +2 und Farbjagd darf nur legen, wer %s. Die App lässt nichts anderes zu." % cond
		"free":
			wild = "Wünscher +2 und Farbjagd dürfen immer gelegt werden."
	out.append({"title": "Joker", "text": wild})
	var mau := ""
	match cfg.mau_call:
		"catch":
			mau = "Wer mit 2 Karten dran ist, ruft „Mau!“ – vor oder nach dem Legen, bis der nächste Zug beginnt. Wer es vergisst und erwischt wird, zieht %d %s." % [cfg.mau_penalty, "Karte" if cfg.mau_penalty == 1 else "Karten"]
		"auto":
			mau = "Wer mit 2 Karten dran ist, ruft „Mau!“ – vor oder nach dem Legen, bis der nächste Zug beginnt. Sonst zieht er automatisch %d %s." % [cfg.mau_penalty, "Karte" if cfg.mau_penalty == 1 else "Karten"]
		"reminder":
			mau = "„Mau!“ rufen ist freiwillig; die App erinnert nur daran."
		"off":
			mau = "In diesen Regeln wird nicht „Mau!“ gerufen."
	out.append({"title": "Mau!", "text": mau})
	var special := "Ist der Nachziehstapel leer, wird die Ablage außer der obersten Karte gemischt. Sind beide leer, entfällt das Ziehen. Wiederholt sich bei fast leeren Stapeln dieselbe Lage zum dritten Mal, endet die Runde; vorn liegt, wer die wenigsten Karten hat."
	if cfg.two_player_reverse_skips:
		special += " Zu zweit wirkt der Richtungswechsel wie Aussetzen."
	special += " Ein Flip als letzte Karte wird %s." % ("noch ausgeführt, gewertet wird die neue Seite" if cfg.flip_last_card == "execute" else "nicht mehr ausgeführt")
	out.append({"title": "Sonderfälle", "text": special})
	return out
