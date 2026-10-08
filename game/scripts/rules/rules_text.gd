class_name RulesText
extends RefCounted
# Deutsche Texte zum Regelwerk (docs/BETA1_PLAN.md Abschnitt 4): Namen von Farben und Karten, Kartenhilfe je Gesicht passend zur
# aktiven RuleConfig (Geste „halten und nach unten auf ?“) und die Regelübersicht in kurzen Absätzen. Begriffe nach
# Regelbericht Abschnitt 3 (keine Marken des Vorbilds).

const COLOR_NAMES := {"rot": "Rot", "gelb": "Gelb", "gruen": "Grün", "blau": "Blau",
	"pink": "Pink", "tuerkis": "Türkis", "orange": "Orange", "lila": "Lila"}
const KIND_NAMES := {"plus1": "+1", "plus5": "+5", "aussetzen": "Aussetzen", "alle_aussetzen": "Alle aussetzen",
	"richtungswechsel": "Richtungswechsel", "flip": "Flip", "wuenscher": "Wünscher", "wuenscher_plus2": "Wünscher +2",
	"farbjagd": "Farbjagd", "tausch": "Kartentausch", "gluecksspiel": "Glücksspiel", "ablegen": "Farbe ablegen",
	"ablegen_joker": "Ablegen-Joker"}
# Mit unbestimmtem Artikel im Akkusativ („lege … oder eine 7“).
const KIND_WITH_ARTICLE := {"plus1": "eine +1", "plus5": "eine +5", "aussetzen": "ein Aussetzen",
	"alle_aussetzen": "ein Alle aussetzen", "richtungswechsel": "einen Richtungswechsel", "flip": "einen Flip",
	"wuenscher": "einen Wünscher", "wuenscher_plus2": "einen Wünscher +2", "farbjagd": "eine Farbjagd",
	"tausch": "einen Kartentausch", "gluecksspiel": "ein Glücksspiel", "ablegen": "eine Ablegen-Karte",
	"ablegen_joker": "einen Ablegen-Joker"}
const SIDE_NAMES := {"hell": "helle Seite", "dunkel": "dunkle Seite"}


static func color_name(color: String) -> String:
	return str(COLOR_NAMES.get(color, color))


static func kind_name(kind: String) -> String:
	return str(KIND_NAMES.get(kind, kind))


static func side_name(side: String) -> String:
	return str(SIDE_NAMES.get(side, side))


# Kurzer Name eines Gesichts, z. B. „Rot 7“, „Gelb +1“, „Lila Alle aussetzen“, „Wünscher +2“, „Grün ablegen“.
static func face_title(key: String) -> String:
	var f := CardDB.parse_key(key)
	if f.is_empty():
		return key
	var kind := str(f.kind)
	if str(f.color) == "":
		return kind_name(kind)
	if kind == "zahl":
		return "%s %d" % [color_name(str(f.color)), int(f.value)]
	if kind == CardDB.DISCARD:
		return "%s ablegen" % color_name(str(f.color))
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
			out.append("Der Nächste zieht %d %s und %s." % [n, "Karte" if n == 1 else "Karten", cfg.penalty_tail()])
			out.append("Passt auf %s und auf jede %s." % [color, title])
			if cfg.stacking == "same":
				out.append("%s darf gestapelt werden: Wer sie abbekommt, kann eine %s drauflegen; die Summe wandert weiter." % [title, title])
			else:
				out.append("Nicht stapelbar: Wer sie abbekommt, zieht sofort und %s." % cfg.penalty_tail())
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
			if cfg.flip_mode == "card":
				out.append("Wendet Nachziehstapel, alle Hände und sich selbst. Danach gilt die %s." % side_name(other))
			else:
				out.append("Wendet alles: Ablage, Nachziehstapel und alle Hände. Danach gilt die %s." % side_name(other))
			out.append("Passt auf %s und auf jeden Flip – ein Flip ist kein Joker." % color)
			if cfg.flip_mode == "card":
				out.append("Oben liegt dann die andere Seite dieses Flips; die übrige Ablage bleibt zur Seite gelegt. Eine Wunschfarbe verfällt.")
			else:
				out.append("Oben liegt dann die bisher unterste Ablagekarte mit ihrer anderen Seite. Eine Wunschfarbe verfällt.")
			if cfg.flip_surprise == "on":
				out.append("Flip-Überraschung: Liegt danach eine Aktionskarte oben, wirkt sie auf den Nächsten, als hättest du sie gelegt. Bei Wünscher +2 und Farbjagd wählst du zuerst die Farbe.")
				out.append("Flip, Wünscher und Zusatzkarten oben wirken nicht; beim Joker wählst du nur die Farbe.")
			else:
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
				out.append("Passt immer. Du wünschst eine Farbe, der Nächste zieht 2 Karten und %s." % cfg.penalty_tail())
			else:
				out.append("Passt immer. Du wünschst eine Farbe; der Nächste zieht, bis er eine Karte dieser Farbe hat, behält alle gezogenen Karten und %s." % cfg.penalty_tail())
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
		"tausch":
			out.append_array(_swap_lines(color, cfg))
		"gluecksspiel":
			out.append_array(_gamble_lines(cfg))
		"ablegen", "ablegen_joker":
			out.append_array(_discard_lines(kind, color, cfg))
	out.append(_points_line(kind, CardDB.points(f), cfg))
	return out


# Kartenhilfe zum Glücksspiel-Joker (Ende nach round_end, Mau-Hinweis, Stapelstrafe).
static func _gamble_lines(cfg: RuleConfig) -> Array[String]:
	var out: Array[String] = []
	out.append("Joker: passt immer. Du wünschst eine Farbe; sie gilt nach dem Glücksspiel.")
	out.append("Dann spielst du um dein Glück: Leg eine beliebige Karte deiner Hand verdeckt auf deinen Einsatz und drück den Glücksspielknopf. Das geht reihum weiter.")
	out.append("Für jedes Glücksspiel wird geheim eine Trefferquote zwischen 1:1 und 1:10 ausgelost.")
	out.append("Treffer: Der Knopf zeigt 1 bis 10. So viele Karten ziehst du, nimmst deinen ganzen Einsatz zurück, und dein Zug ist vorbei.")
	if cfg.round_end == "first":
		out.append("Zeigt er 0 und deine Hand ist leer, kommt der Einsatz unter den Ablagestapel: Du bist fertig und gewinnst die Runde.")
	else:
		out.append("Zeigt er 0 und deine Hand ist leer, kommt der Einsatz unter den Ablagestapel und du bist fertig.")
	out.append("Nach einer 0 darfst du auch aufhören: Dein ganzer Einsatz kommt unter den Ablagestapel, und dein Zug ist vorbei. Noch eine Karte riskieren oder aufhören?")
	out.append("Die Einsatzkarten liegen verdeckt und wirken nicht, auch kein Flip.")
	if cfg.mau_call != "off":
		out.append("Bleibt dir nach dem Setzen nur noch 1 Karte, ruf „Mau!“ – wie beim Legen.")
	if cfg.stacking == "same":
		out.append("Liegt eine Ziehstrafe auf dir, passt das Glücksspiel nicht (wie jeder andere Joker).")
	out.append("Als letzte Karte bist du einfach fertig; dann gibt es kein Glücksspiel.")
	if cfg.gamble_cards != "on":
		out.append("Gehört zur Hausregel Glücksspiel (gerade nicht im Spiel).")
	return out


# Kartenhilfe zu „Farbe ablegen“ (farbige Karte bzw. Ablegen-Joker).
static func _discard_lines(kind: String, color: String, cfg: RuleConfig) -> Array[String]:
	var out: Array[String] = []
	if kind == "ablegen":
		out.append("Danach wählst du, welche deiner Karten in %s du mit ablegst (alle, einige oder keine); sie kommen unter diese Karte, die oben bleibt." % color)
		out.append("Passt auf %s und auf jede andere Ablegen-Karte." % color)
	else:
		out.append("Joker: passt immer. Du wählst eine Farbe und dann, welche deiner Karten dieser Farbe du mit ablegst; sie kommen unter den Joker.")
		out.append("Danach wählst du die Farbe, mit der es weitergeht – sie darf eine andere sein.")
	out.append("Joker auf deiner Hand bleiben dort. Mitabgelegte Aktionskarten wirken nicht.")
	var end := "gewinnst du die Runde" if cfg.round_end == "first" else "bist du fertig"
	if cfg.mau_call != "off":
		out.append("Bleibt dir danach 1 Karte, ruf „Mau!“ (auch schon vorher erlaubt); bleibt keine, %s." % end)
	else:
		out.append("Bleibt dir danach keine Karte, %s." % end)
	if cfg.discard_color != "on":
		out.append("Gehört zur Hausregel Farbe ablegen (gerade nicht im Spiel).")
	return out


# Kartenhilfe zum Kartentausch (Richtung nach swap_direction, letzte Karte nach round_end, Mau-Hinweis).
static func _swap_lines(color: String, cfg: RuleConfig) -> Array[String]:
	var out: Array[String] = []
	out.append("Alle geben gleichzeitig ihre ganze Hand an den Nächsten weiter, %s. Danach ist ganz normal der Nächste in Spielrichtung dran." % cfg.swap_direction_text())
	if cfg.swap_direction == "play" or cfg.swap_direction == "against":
		out.append("Nach einem Richtungswechsel wandern die Hände also andersherum.")
	out.append("Passt auf %s und auf jeden Kartentausch." % color)
	out.append("Zu zweit tauscht ihr einfach eure Hände.")
	if cfg.round_end == "first":
		out.append("Auch als letzte Karte: Du bist fertig und gewinnst die Runde; getauscht wird dann nicht mehr.")
	else:
		out.append("Auch als letzte Karte: Du bist fertig, die anderen tauschen trotzdem untereinander.")
	if cfg.mau_call != "off":
		out.append("Wer durch den Tausch nur noch 1 Karte hat, muss nicht „Mau!“ rufen.")
	if cfg.swap_cards != "on":
		out.append("Gehört zur Hausregel Kartentausch (gerade nicht im Spiel).")
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
				out.append("Der Nächste darf anzweifeln: Hast du geblufft, ziehst du %s; warst du ehrlich, zieht er %s und %s."
					% ["die Strafe" if cfg.stacking == "same" else "2", "2 mehr" if cfg.stacking == "same" else "4", cfg.penalty_tail()])
			else:
				out.append("Der Nächste darf anzweifeln: Hast du geblufft, ziehst du bis zur Farbe; warst du ehrlich, zieht er bis zur Farbe, dann 2 weitere, und %s." % cfg.penalty_tail())
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
	var swap_on := cfg.swap_cards == "on"
	var gamble_on := cfg.gamble_cards == "on"
	var discard_on := cfg.discard_color == "on"
	if cfg.effective_scoring() == "points500":
		var fifty := "Wünscher +2"
		if gamble_on and discard_on:
			fifty = "Wünscher +2, Glücksspiel und Ablegen-Joker"
		elif gamble_on:
			fifty = "Wünscher +2 und Glücksspiel"
		elif discard_on:
			fifty = "Wünscher +2 und Ablegen-Joker"
		goal += " Der Sieger bekommt die Punkte aller übrigen Handkarten (Zahlen nach Wert, +1 10, +5, Aussetzen, Richtungswechsel%s und Flip 20, Alle aussetzen%s 30, Wünscher 40, %s 50, Farbjagd 60). Wer zuerst %d Punkte hat, gewinnt die Partie." % [", Kartentausch" if swap_on else "", " und Farbe ablegen" if discard_on else "", fifty, cfg.target]
	out.append({"title": "Ziel", "text": goal})
	var cards := "112 Karten mit einer hellen und einer dunklen Seite, Zahlen 1 bis 9."
	if cfg.has_extra_cards():
		var extras: Array[String] = []
		if swap_on:
			extras.append("vier Kartentausch-Karten (eine je Farbe)")
		if gamble_on:
			extras.append("zwei Glücksspiel-Joker")
		if discard_on:
			extras.append("vier Ablegen-Karten (eine je Farbe) und zwei Ablegen-Joker")
		var list := extras[0]
		if extras.size() == 2:
			list = "%s sowie %s" % [extras[0], extras[1]]
		elif extras.size() == 3:
			list = "%s, %s sowie %s" % [extras[0], extras[1], extras[2]]
		cards = "%d Karten mit einer hellen und einer dunklen Seite, Zahlen 1 bis 9, dazu je Seite %s." % [cfg.card_count(), list]
	out.append({"title": "Karten", "text": "%s Hell: Rot, Gelb, Grün, Blau. Dunkel: Pink, Türkis, Orange, Lila. Alle Karten liegen gleich herum: Du spielst die aktive Seite, die anderen sehen deine Rückseiten%s." % [cards, "" if cfg.backs_visible else " nicht (verdeckt)"]})
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
	if cfg.draw_play == "any" and cfg.draw_rule == "one":
		voluntary = "Du darfst auch freiwillig ziehen. Hausregel: Danach darfst du %s passende Karte legen oder alles behalten; passt nichts, ist dein Zug vorbei." \
			% ("eine andere" if cfg.drawn_card == "may_not" else "jede")
	out.append({"title": "Spielzug", "text": "Lege eine Karte, die in Farbe, Zahl oder Symbol zur obersten Ablagekarte passt. Joker passen immer. %s %s" % [draw, voluntary]})
	out.append({"title": "Helle Seite", "text": ("+1: Der Nächste zieht 1 und %s. Aussetzen: Der Nächste wird übersprungen. Richtungswechsel: Die Richtung dreht sich. Wünscher: Farbe wünschen. Wünscher +2: Farbe wünschen, der Nächste zieht 2 und %s.") % [cfg.penalty_tail(), cfg.penalty_tail()]})
	out.append({"title": "Dunkle Seite", "text": ("+5: Der Nächste zieht 5 und %s. Alle aussetzen: Du bist sofort noch einmal dran. Richtungswechsel und Wünscher wie hell. Farbjagd: Farbe wünschen, der Nächste zieht, bis er diese Farbe hat, und %s.") % [cfg.penalty_tail(), cfg.penalty_tail()]})
	var flip_top := "eine Aktionskarte oben wirkt nicht; liegt ein Joker oben, wählt der Flip-Spieler die Farbe." if cfg.flip_surprise != "on" \
		else "liegt ein Joker oben, wählt der Flip-Spieler die Farbe. Flip-Überraschung (Hausregel): Die Aktionskarte, die nach dem Flip oben liegt (+1, +5, Aussetzen, Alle aussetzen, Richtungswechsel, Wünscher +2, Farbjagd), wirkt auf den Nächsten, als hätte der Flip-Spieler sie gelegt; Stapeln gilt wie sonst."
	var flip_turn := "Der Flip wendet Ablage, Nachziehstapel und alle Hände. Oben liegt dann die bisher unterste Ablagekarte mit ihrer anderen Seite." if cfg.flip_mode != "card" \
		else "Der Flip wendet Nachziehstapel und alle Hände, von der Ablage aber nur sich selbst (Hausregel): Oben liegt seine andere Seite, die übrige Ablage bleibt zur Seite gelegt."
	out.append({"title": "Flip", "text": flip_turn + " Eine Wunschfarbe verfällt, " + flip_top})
	if swap_on:
		var last := "Als letzte Karte bist du fertig und gewinnst; getauscht wird dann nicht mehr." if cfg.round_end == "first" \
			else "Als letzte Karte bist du fertig; die anderen tauschen trotzdem untereinander."
		var mau_note := " Wer so auf 1 Karte kommt, muss nicht „Mau!“ rufen." if cfg.mau_call != "off" else ""
		out.append({"title": "Kartentausch", "text": "Hausregel: Wer einen Kartentausch legt, lässt alle Spieler gleichzeitig ihre ganze Hand an den Nächsten weitergeben, %s. Danach ist der Nächste in Spielrichtung dran; zu zweit tauscht ihr einfach eure Hände. Der Kartentausch passt auf seine Farbe und auf jeden anderen Kartentausch.%s %s" % [cfg.swap_direction_text(), mau_note, last]})
	if gamble_on:
		var done := "bist fertig und gewinnst die Runde" if cfg.round_end == "first" else "bist fertig"
		var mau_g := " Bleibt nach dem Setzen 1 Karte, gilt „Mau!“ wie beim Legen." if cfg.mau_call != "off" else ""
		out.append({"title": "Glücksspiel", "text": "Hausregel: Der Glücksspiel-Joker passt immer; du wünschst eine Farbe, die nach dem Glücksspiel gilt. Dann legst du reihum eine beliebige Karte verdeckt auf deinen Einsatz und drückst den Glücksspielknopf. Je Glücksspiel wird geheim eine Trefferquote zwischen 1:1 und 1:10 ausgelost. Bei einem Treffer zeigt der Knopf 1 bis 10: So viele Karten ziehst du, nimmst den ganzen Einsatz zurück, und dein Zug ist vorbei. Zeigt er 0, geht es weiter; ist deine Hand dann leer, kommt der Einsatz unter den Ablagestapel und du %s. Nach einer 0 darfst du statt weiterzusetzen auch aufhören: Der ganze Einsatz kommt unter den Ablagestapel, dein Zug ist vorbei. Die Einsatzkarten wirken nicht.%s" % [done, mau_g]})
	if discard_on:
		var mau_d := " Bleibt dir 1 Karte, ruf „Mau!“." if cfg.mau_call != "off" else ""
		out.append({"title": "Farbe ablegen", "text": "Hausregel: Wer eine Ablegen-Karte legt, wählt danach, welche eigenen Karten derselben Farbe er mit ablegt (alle, einige oder keine). Beim Ablegen-Joker wählst du zuerst die Ablegefarbe und danach getrennt die Farbe, mit der es weitergeht. Die Karten kommen unter die Ablegen-Karte, die oben bleibt. Joker bleiben auf der Hand, mitabgelegte Aktionskarten wirken nicht. Die farbige Ablegen-Karte passt auf ihre Farbe und auf jede andere Ablegen-Karte, der Ablegen-Joker immer.%s Bleibt keine Karte, bist du fertig." % mau_d})
	# Besondere Karten der ausgeschalteten Hausregeln kurz vorstellen (eingeschaltete haben oben einen eigenen Absatz).
	var more: Array[String] = []
	if not swap_on:
		more.append("Kartentausch (eine je Farbe): Alle geben ihre ganze Hand an den Nächsten weiter.")
	if not gamble_on:
		more.append("Glücksspiel-Joker (zwei je Seite): Du setzt reihum Karten verdeckt und drückst den Glücksspielknopf. Bei 0 setzt du weiter oder hörst auf (der Einsatz kommt unter die Ablage); ist die Hand leer, bist du fertig. Bei einem Treffer ziehst du 1 bis 10 Karten und nimmst den Einsatz zurück.")
	if not discard_on:
		more.append("Farbe ablegen (eine je Farbe, dazu zwei Joker je Seite): Du legst Karten dieser Farbe mit ab, welche, wählst du.")
	if not more.is_empty():
		out.append({"title": "Weitere besondere Karten", "text": "Diese Karten kommen nur mit ihrer Hausregel ins Spiel (einschalten unter „Anpassen“ → „Hausregeln mit Zusatzkarten“): " + " ".join(more)})
	var stack := "Ziehkarten werden nicht gestapelt: Wer sie abbekommt, zieht und %s." % cfg.penalty_tail() if cfg.stacking == "off" \
		else "Wer eine Ziehkarte abbekommt, darf die gleiche drauflegen (+1 auf +1, +5 auf +5, Wünscher +2 auf Wünscher +2, Farbjagd auf Farbjagd). Die Summe wandert weiter; bei der Farbjagd zieht das letzte Opfer bis zur Farbe. Wer am Ende zieht, %s." % cfg.penalty_tail()
	out.append({"title": "Ziehkarten", "text": stack + " Ist die letzte Karte eine Ziehkarte, zieht der Nächste trotzdem."})
	var cond := "keine Karte in der aktuellen Farbe hat"
	if cfg.wild_counts_for_bluff:
		cond += " und keinen anderen Joker"
	var wild := ""
	match cfg.wild_restriction:
		"bluff":
			wild = "Wünscher +2 und Farbjagd darf nur legen, wer %s. Der Betroffene darf anzweifeln und sieht dann die Hand. Bluff erwischt: Der Leger zieht die Strafe selbst, der Herausforderer ist normal dran. Leger war ehrlich: Der Herausforderer zieht 2 Karten mehr und %s. Die Wunschfarbe bleibt." % [cond, cfg.penalty_tail()]
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


# „So geht's“ im Spielmenü (Beta 1.0.2): Bedienung und Gesten in kurzen Absätzen {title, text}, passend zu den aktiven Regeln.
static func controls(config: RuleConfig = null) -> Array[Dictionary]:
	var cfg := config if config != null else RuleConfig.new()
	var out: Array[Dictionary] = []
	out.append({"title": "Karte ausspielen", "text": "Tipp eine Karte an, sie hebt sich. Ein zweiter Tipp legt sie. Du kannst sie auch nach oben auf die Ablage ziehen oder schnippen. Passende Karten leuchten, wenn „Spielbare Karten hervorheben“ in den Einstellungen an ist."})
	out.append({"title": "Ziehen", "text": "Passt nichts, tipp auf den Nachziehstapel links von der Ablage. Er leuchtet, wenn du ziehen darfst."})
	out.append({"title": "Hilfe zu einer Karte", "text": "Halte eine Karte gedrückt, dann siehst du sie groß. Zieh sie nach unten auf das „?“: Dann steht da kurz, was sie kann."})
	out.append({"title": "Sortieren", "text": "Der Sortierknopf wechselt zwischen Farbe, Wert, Punkte und Eigene. Willst du selbst ordnen, halte eine Karte und schieb sie zur Seite."})
	var backs := "Viele Karten? Wisch über deine Hand, sie dreht sich wie ein Karussell."
	if cfg.peek_own_backs:
		backs += " Halte den Rückseiten-Knopf, dann siehst du die Rückseiten deiner Karten."
	if cfg.backs_visible:
		backs += " Tipp auf die Karten eines Mitspielers, dann siehst du seine Rückseiten groß."
	out.append({"title": "Hand und Rückseiten", "text": backs})
	match cfg.mau_call:
		"catch":
			out.append({"title": "Mau rufen", "text": "Hast du nur noch 2 Karten und bist dran, tipp auf „Mau!“ – vor oder nach dem Legen. Vergisst es jemand, tipp schnell auf seine Karten: erwischt!"})
		"auto", "reminder":
			out.append({"title": "Mau rufen", "text": "Hast du nur noch 2 Karten und bist dran, tipp auf „Mau!“ – vor oder nach dem Legen."})
	out.append({"title": "Ablage durchsehen", "text": "Tipp auf die Ablage: Die oberste Karte rutscht zur Seite, und du siehst, was darunter liegt und wer es gelegt hat. Tipp auf den Stapel daneben legt eine zurück, ein Tipp auf den Tisch alle."})
	if cfg.gamble_cards == "on":
		out.append({"title": "Glücksspiel", "text": "Nach dem Glücksspiel-Joker ziehst du eine Karte aus deiner Hand auf deinen Einsatz und drückst „Los!“. Bei 0 setzt du weiter oder tippst „Aufhören“."})
	if cfg.discard_color == "on":
		out.append({"title": "Farbe ablegen", "text": "Nach der Ablegen-Karte sind die passenden Karten schon ausgewählt. Tipp eine an, um sie zu behalten, und dann auf „Ablegen“."})
	out.append({"title": "Spielmenü", "text": "Der Zurück-Knopf oben links öffnet dieses Menü. Dort kannst du die Regeln ansehen oder die Partie verlassen."})
	return out
