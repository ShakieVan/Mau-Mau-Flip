class_name I18n
extends RefCounted
# Sprache der App (Beta 1.2.2, englische Fassung). Deutsch ist Quelle und Standard; Englisch kommt aus gettext-Dateien
# (game/i18n/en_*.po, msgid = deutscher Text, msgstr = Englisch), eingetragen in project.godot (internationalization/locale/
# translations, Rückfall-Sprache "de", damit ein deutsches Gerät nie auf Englisch zurückfällt). Bezeichnungen: game/i18n/GLOSSAR.md.
#
# Einstellung App.settings "sprache": "auto" (Systemsprache de* → Deutsch, sonst Englisch) | "de" | "en"; wirkt sofort
# (ScreenNav hört auf App.settings.changed → I18n.apply). Testläufe (godot --script) bleiben immer auf Deutsch (forced_test),
# außer ein Test ruft ausdrücklich I18n.set_language("en").
#
# Wie Texte übersetzt werden:
# - Label, Button, CheckButton, LineEdit.placeholder_text, tooltip_text: Godot übersetzt sie selbst (auto_translate), auch live.
# - Formatstrings: I18n.t("… %d …") % n (bzw. tr(…) in Nodes). Zwischengespeicherte Texte bei NOTIFICATION_TRANSLATION_CHANGED
#   neu setzen; eigene Zeichnung (draw_string) mit I18n.t(…) und dort queue_redraw().
# - Texte, die der Gastgeber an Gäste schickt (Hinweise, Fehler, Meldungen): als „Bausteine“ (lt), damit jedes Gerät in seiner
#   eigenen Sprache anzeigt. Format (JSON-tauglich, auch webclient/i18n.js):
#     lt   := Array von Teilen, angezeigt mit " " verbunden
#     Teil := String (msgid ohne Platzhalter) | Array [vorlage, arg…] (vorlage = msgid mit %s/%d)
#     arg  := int/float (Zahl) | String (wörtlich, z. B. Spielername) | {"t": Teil} (wird selbst übersetzt, z. B. Farbname)
#   I18n.render(lt, false) ergibt genau den bisherigen deutschen Text (Feld "text" bleibt für ältere Geräte erhalten).

const SETTING := "sprache"
const CHOICES := ["auto", "de", "en"]
const LANGS := ["de", "en"]
const CHOICE_NAMES := [["auto", "Automatisch"], ["de", "Deutsch"], ["en", "English"]]
const FILES := ["res://i18n/en_screens.po", "res://i18n/en_table.po", "res://i18n/en_rules.po"]

static var _loaded := false
static var collect := false            # Lückentest (test_i18n): jeden übersetzten Text merken
static var seen := {}                  # msgid → Ergebnis (nur mit collect)


# Sprache aus der Einstellung: "de" oder "en"
static func resolve(setting: String) -> String:
	if setting == "de" or setting == "en":
		return setting
	return "de" if OS.get_locale_language().to_lower().begins_with("de") else "en"


# Testläufe (godot --script/-s) zeigen Deutsch, damit die Tests weiter deutsche Texte prüfen.
static func forced_test() -> bool:
	var args := OS.get_cmdline_args()
	return args.has("--script") or args.has("-s")


# Einstellung anwenden (App-Start, Einstellungen). Im Testlauf immer Deutsch.
static func apply(setting: String) -> void:
	set_language("de" if forced_test() else resolve(setting))


# Sprache direkt setzen ("de"/"en"); Godot schickt allen Nodes NOTIFICATION_TRANSLATION_CHANGED.
static func set_language(lang: String) -> void:
	ensure_loaded()
	var l := lang if LANGS.has(lang) else "de"
	if TranslationServer.get_locale() != l:
		TranslationServer.set_locale(l)


static func language() -> String:
	return "en" if TranslationServer.get_locale().to_lower().begins_with("en") else "de"


static func english() -> bool:
	return language() == "en"


# Lädt die .po-Dateien, falls project.godot sie (z. B. in einem Testaufbau) noch nicht geladen hat.
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not TranslationServer.get_loaded_locales().has("en"):
		for path in FILES:
			if ResourceLoader.exists(path):
				var tr_res := load(path) as Translation
				if tr_res != null:
					TranslationServer.add_translation(tr_res)


# Übersetzt einen deutschen Text (msgid) in die aktuelle Sprache; unbekannte Texte bleiben, wie sie sind.
static func t(text: String) -> String:
	if text == "":
		return ""
	var out := String(TranslationServer.translate(text))
	if collect:
		seen[text] = out
	return out


# --- Bausteine (lt) ---

# Ein Teil mit Platzhaltern: I18n.part("%s ist dran.", [name])
static func part(template: String, args: Array = []) -> Variant:
	if args.is_empty():
		return template
	var p: Array = [template]
	p.append_array(args)
	return p


# Argument, das selbst übersetzt wird (Farbname, Kartenart, Teilsatz)
static func tr_arg(p: Variant) -> Dictionary:
	return {"t": p}


# Baustein-Liste → Text. translate = false: deutsch (wie bisher gesendet).
static func render(lt: Variant, translate := true) -> String:
	if lt is String:
		return t(lt) if translate else str(lt)
	if not lt is Array:
		return ""
	var out: PackedStringArray = []
	for p in lt:
		var s := render_part(p, translate)
		if s != "":
			out.append(s)
	return " ".join(out)


static func render_part(p: Variant, translate := true) -> String:
	if p is String:
		return t(p) if translate else str(p)
	if p is Array and not (p as Array).is_empty():
		var arr: Array = p
		var tmpl := str(arr[0])
		if translate:
			tmpl = t(tmpl)
		var args: Array = []
		for i in range(1, arr.size()):
			args.append(_arg(arr[i], translate))
		if args.is_empty():
			return tmpl
		return tmpl % args
	return ""


static func _arg(a: Variant, translate: bool) -> Variant:
	if a is Dictionary:
		return render_part((a as Dictionary).get("t", ""), translate)
	if a is float and is_equal_approx(a, roundf(a)):
		return int(a)
	if a is int or a is float:
		return a
	return str(a)


# Text einer Netz-Nachricht ({text, lt?}) in der eigenen Sprache; fallback, wenn beides fehlt.
static func msg_text(msg: Dictionary, fallback := "") -> String:
	var lt: Variant = msg.get("lt")
	if lt is Array and not (lt as Array).is_empty():
		return render(lt)
	var text := str(msg.get("text", ""))
	return t(text if text != "" else fallback)


# Ablehnungsgrund eines Regel-Ergebnisses ({reason, reason_lt?}, MauGame.apply) in der eigenen Sprache
static func reason(r: Dictionary) -> String:
	var lt: Variant = r.get("reason_lt")
	if lt is Array and not (lt as Array).is_empty():
		return render(lt)
	return t(str(r.get("reason", "")))


# Nachricht mit deutschem Text und Bausteinen: I18n.with_lt({"t":"err"}, [I18n.part("…", [x])])
static func with_lt(msg: Dictionary, lt: Array) -> Dictionary:
	msg["text"] = render(lt, false)
	msg["lt"] = lt
	return msg


# Gleiche Platzhalter in msgid und msgstr (Lückentest): Liste der Platzhalter in Reihenfolge
static func placeholders(text: String) -> Array:
	var out: Array = []
	var i := 0
	while i < text.length():
		if text[i] == "%" and i + 1 < text.length():
			var j := i + 1
			while j < text.length() and "0123456789.-+ ".contains(text[j]):
				j += 1
			if j < text.length():
				var c := text[j]
				if c != "%":
					out.append(text.substr(i, j - i + 1))
				i = j + 1
				continue
		i += 1
	return out
