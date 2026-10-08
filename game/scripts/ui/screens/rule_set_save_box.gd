class_name RuleSetSaveBox
extends Control
# „Regeln speichern“: Papierkarte über abgedunkeltem Hintergrund (wie ConfirmBox), ganz oben am Bildschirm und kompakt, damit die
# Bildschirmtastatur (im Querformat gut die untere Hälfte) Namensfeld, „Speichern“ und Meldung nicht verdeckt:
#   Kopf: Titel „Regeln speichern“ (fest, wird nie gekürzt), Kartenzahl, „Abbrechen“ · darunter, was gespeichert wird (beim Gast
#   „Regeln von Lena: …“) · Namensfeld und „Speichern“ in einer Zeile · Meldung (Hinweis, Fehler).
#   Speichern → neuer Name: speichern · gleicher Name mit anderen Regeln: Rückfrage in einer eigenen Zeile statt der Meldung
#   („„Oma“ gibt es schon …“ mit „Anderer Name“ und „Überschreiben“). „Speichern“ ist dann gesperrt, „Überschreiben“ steht eine Zeile
#   tiefer und nimmt erst nach GUARD_MS an: ein Doppeltipp überschreibt nichts. Die Tastatur geht dabei zu, damit sie die Rückfrage
#   nicht verdeckt; Weitertippen oder „Anderer Name“ = neuer Name · gleicher Name, gleiche Regeln: einfach fertig · schon 12 Sätze
#   und neuer Name: Hinweis, die Karte bleibt offen · leerer Name: Hinweis · Datei nicht geschrieben: Hinweis, Karte bleibt offen.
# Die Texte passen zum Ort: im Regel-Editor ohne Verweis auf „Regeln“ → „Anpassen“, beim Gast (host_name gesetzt) mit Verweis.
# update_rules(): Der Gastgeber hat die Regeln geändert, während die Karte offen ist – gespeichert werden dann die neuen.
# saved(name) mit dem gespeicherten Namen, danach schließt die Karte. „Abbrechen“, Tipp daneben oder cancel(): cancelled.

signal saved(set_name: String)
signal cancelled

const TITLE := "Regeln speichern"
const HINT_EDITOR := "Höchstens 20 Zeichen. Der Satz steht danach unter „Gespeichert“."
const HINT_GUEST := "Höchstens 20 Zeichen. Später findest du ihn unter „Regeln“ bei „Gespeichert“."
const TOP := 14.0
const GUARD_MS := 400

var cfg: RuleConfig
var host_name := ""                  # Gast: Name des Gastgebers; "" = Regel-Editor
var settings: AppSettings            # Tests: eigene Einstellungen; null = App.settings
var field: LineEdit
var _card: PanelContainer
var _what: Label
var _pill: PanelContainer
var _pill_label: Label
var _msg: Label
var _yes: Button
var _no: Button
var _question: HBoxContainer         # Rückfrage zum Überschreiben (statt der Meldung)
var _question_label: Label
var _over: Button                    # „Überschreiben“
var _other: Button                   # „Anderer Name“
var _pending := ""                   # Name, der auf „Überschreiben“ wartet
var _asked_ms := -1


# host_name: Gast (Regeln eines Gastgebers, Texte mit Verweis auf „Regeln“); "" = Regel-Editor
static func ask(parent: Node, rules: RuleConfig, suggestion := "", from_host := "", st: AppSettings = null) -> RuleSetSaveBox:
	var box := RuleSetSaveBox.new()
	box.cfg = rules.duplicate_config() if rules != null else RuleConfig.new()
	box.host_name = from_host
	box.settings = st
	box.theme = UiTheme.get_theme()
	parent.add_child(box)
	box._build(suggestion)
	return box


func hint_text() -> String:
	return HINT_GUEST if host_name != "" else HINT_EDITOR


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	name = "RegelnSpeichern"


func _build(suggestion: String) -> void:
	var top := MarginContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_constant_override("margin_top", int(TOP))
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(center)
	_card = ScreenKit.card(26.0)
	_card.custom_minimum_size = Vector2(900, 0)
	center.add_child(_card)
	var v := ScreenKit.vbox(10)
	_card.add_child(v)
	# Kopf: Titel, Kartenzahl, Abbrechen
	var head := ScreenKit.hbox(16)
	v.add_child(head)
	var h := ScreenKit.heading(TITLE, UiFonts.size("ueberschrift"))
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(h)
	_pill = PanelContainer.new()
	_pill.name = "Kartenzahl"
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pill_label = ScreenKit.label("", "", UiFonts.size("text"))
	_pill_label.add_theme_font_override("font", UiFonts.text(800))
	_pill.add_child(_pill_label)
	head.add_child(_pill)
	_no = ScreenKit.button("Abbrechen", "GhostButton")
	_no.name = "Nein"
	_no.add_theme_font_size_override("font_size", UiFonts.size("text"))
	_no.pressed.connect(cancel)
	head.add_child(_no)
	# Was gespeichert wird (beim Gast mit dem Namen des Gastgebers)
	_what = ScreenKit.hint("", UiFonts.size("klein"))
	_what.name = "Inhalt"
	_what.max_lines_visible = 2
	_what.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(_what)
	_show_rules()
	# Name und Speichern
	var row := ScreenKit.hbox(14)
	v.add_child(row)
	field = LineEdit.new()
	field.name = "Name"
	field.placeholder_text = "Name, z. B. Oma-Regeln"
	field.max_length = RuleSets.NAME_MAX
	field.text = RuleSets.clean_name(suggestion)
	field.custom_minimum_size = Vector2(0, ScreenKit.TOUCH)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_theme_font_size_override("font_size", UiFonts.size("zwischen"))
	field.select_all_on_focus = true
	field.text_changed.connect(_on_typed)
	field.text_submitted.connect(func(_t: String) -> void: confirm())
	row.add_child(field)
	_yes = ScreenKit.button("Speichern", "PrimaryButton", "", 250.0)
	_yes.name = "Ja"
	_yes.icon = ScreenKit.glyph("haken", 36)
	_yes.pressed.connect(confirm)
	row.add_child(_yes)
	_msg = ScreenKit.hint(hint_text(), UiFonts.size("hinweis"))
	_msg.name = "Meldung"
	v.add_child(_msg)
	# Rückfrage zum Überschreiben: eigene Zeile unter dem Feld, „Überschreiben“ rechts außen (eine Zeile unter „Speichern“)
	_question = ScreenKit.hbox(14)
	_question.name = "Rueckfrage"
	_question.visible = false
	v.add_child(_question)
	_question_label = ScreenKit.text_block("", UiFonts.size("text"))
	_question_label.add_theme_font_override("font", UiFonts.text(800))
	_question_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_question_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_question.add_child(_question_label)
	_other = ScreenKit.button("Anderer Name", "GhostButton")
	_other.name = "AndererName"
	_other.add_theme_font_size_override("font_size", UiFonts.size("text"))
	_other.pressed.connect(other_name)
	_question.add_child(_other)
	_over = ScreenKit.button("Überschreiben", "PrimaryButton", "", 250.0)
	_over.name = "Ueberschreiben"
	_over.pressed.connect(_on_overwrite_pressed)
	_question.add_child(_over)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)
	_focus_field.call_deferred()


# Kopf und Kurzbeschreibung zu cfg
func _show_rules() -> void:
	var extra := cfg.card_count() > CardDB.CARD_COUNT
	_pill.add_theme_stylebox_override("panel", UiTheme.box(UiPalette.FILL["gelb"] if extra else Color(UiPalette.INK, 0.06), Color(UiPalette.INK, 0.8 if extra else 0.3), 2, 24, 18.0, 6.0))
	_pill_label.text = I18n.t("%d Karten") % cfg.card_count()
	var s := RulesBar.summary(cfg) + "."
	_what.text = (I18n.t("Regeln von %s: %s") % [host_name, s]) if host_name != "" else s


# Der Gastgeber hat die Regeln geändert, während die Karte offen ist: gespeichert werden die neuen (eine offene Rückfrage verfällt).
func update_rules(rules: RuleConfig) -> void:
	if rules == null or is_queued_for_deletion() or RuleSets.same(rules, cfg):
		return
	cfg = rules.duplicate_config()
	_show_rules()
	if _pending != "":
		_clear_question()
	_show_msg("Der Gastgeber hat die Regeln eben geändert. Gespeichert werden die neuen.")


func _focus_field() -> void:
	if is_instance_valid(field) and field.is_inside_tree():
		field.grab_focus()
		field.select_all()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.1, 0.55))


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if not _card.get_global_rect().has_point(get_global_transform() * mb.position):
			cancel()
		accept_event()


# Beim Tippen: Zeichen filtern (Cursor bleibt an seiner Stelle); eine offene Überschreiben-Frage verfällt (anderer Name).
func _on_typed(t: String) -> void:
	var f := RuleSets.filter_name(t)
	if f != t:
		var col := field.caret_column - (t.length() - f.length())
		field.text = f
		field.caret_column = clampi(col, 0, f.length())
	if _pending != "":
		_clear_question()
		_show_msg(hint_text())
	elif _msg.text != hint_text():
		_show_msg(hint_text())


# „Speichern“ (auch Eingabetaste). Bei offener Rückfrage geschieht nichts: Überschreiben nur über „Überschreiben“.
func confirm() -> void:
	if is_queued_for_deletion() or _pending != "":
		return
	var n := RuleSets.clean_name(field.text)
	if n == "":
		_show_msg("Gib dem Regelsatz einen Namen.", true)
		return
	if RuleSets.would_overwrite(n, cfg, settings):
		_ask_overwrite(RuleSets.stored_name(n, settings))
		return
	_save(n)


# „Überschreiben“ nach der Rückfrage
func overwrite() -> void:
	if is_queued_for_deletion() or _pending == "":
		return
	_save(_pending)


func _on_overwrite_pressed() -> void:
	if _asked_ms >= 0 and Time.get_ticks_msec() - _asked_ms < GUARD_MS:
		return                           # zweiter Tipp eines Doppeltipps auf „Speichern“
	overwrite()


# „Anderer Name“: Rückfrage zu, zurück ins Namensfeld
func other_name() -> void:
	_clear_question()
	_show_msg(hint_text())
	if is_instance_valid(field) and field.is_inside_tree():
		field.grab_focus()
		field.select_all()


func _save(n: String) -> void:
	var result := RuleSets.save(n, cfg, settings)
	if result == RuleSets.OK_SAVED:
		_close()
		saved.emit(n)
		return
	_clear_question()
	if result == RuleSets.ERR_FULL and host_name != "":
		_show_msg(I18n.t("Schon %d Regelsätze gespeichert. Nimm einen vorhandenen Namen; löschen kannst du später unter „Regeln“ bei „Gespeichert“.") % RuleSets.MAX, true)
	elif result == RuleSets.ERR_FULL:
		_show_msg(I18n.t("Schon %d Regelsätze gespeichert. Nimm einen vorhandenen Namen – oder brich ab und lösche unter „Gespeichert“ einen Satz mit seinem ×.") % RuleSets.MAX, true)
	elif result == RuleSets.ERR_WRITE:
		_show_msg("Speichern hat nicht geklappt. Ist der Speicher des Geräts voll?", true)
	else:
		_show_msg("Gib dem Regelsatz einen Namen.", true)


func cancel() -> void:
	if is_queued_for_deletion():
		return
	_close()
	cancelled.emit()


func _close() -> void:
	if field != null and field.has_focus():
		field.release_focus()
	queue_free()


# Rückfrage zeigen: eigene Zeile statt der Meldung, „Speichern“ gesperrt, Tastatur zu (sie deckte sonst die Rückfrage)
func _ask_overwrite(existing: String) -> void:
	_pending = existing
	_asked_ms = Time.get_ticks_msec()
	_question_label.text = I18n.t("„%s“ gibt es schon – mit anderen Regeln. Überschreiben?") % existing
	_question.visible = true
	_msg.visible = false
	_yes.disabled = true
	if field.has_focus():
		field.release_focus()


func _clear_question() -> void:
	_pending = ""
	_asked_ms = -1
	_question.visible = false
	_msg.visible = true
	_yes.disabled = false


# alert: Fehler (rot) · sonst Hinweis
func _show_msg(text: String, alert := false) -> void:
	_msg.text = text
	if alert:
		_msg.add_theme_color_override("font_color", UiPalette.ALERT)
	else:
		_msg.remove_theme_color_override("font_color")
