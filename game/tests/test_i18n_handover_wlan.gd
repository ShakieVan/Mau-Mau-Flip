extends SceneTree
# Mau-Mau Flip (Beta 1.6.2, Gastgeber-Übergabe im WLAN und Spiel-WLAN): englische Texte aus docs/module/uebergabe.md, Abschnitt 10.15.
# Jeder deutsche Text (App über I18n.t, Lite über M.t → webclient/i18n_po.js aus den .po) hat genau eine msgid mit Übersetzung,
# gleichen Platzhaltern und ohne deutsche Reste. Schnell, ohne Netz.
#   godot_run.ps1 -Script res://tests/test_i18n_handover_wlan.gd -Headless

const CleanExit := preload("res://tests/clean_exit.gd")
const I18nTest := preload("res://tests/test_i18n.gd")

# Abschnitt 10.15 (Knopfpaare „A · B“ einzeln); „Abbrechen“ und „Weiter“ gibt es schon.
const TEXTS := [
	"Suche den neuen Gastgeber …",
	"Spiel-WLAN von %s ist weg.",
	"Neues Spiel-WLAN bei %s – QR-Code scannen",
	"Nur wenn %s nicht übernimmt – sonst gibt es zwei Spiele.",
	"WLAN-Mitspieler brauchen dann Internet.",
	"Alle müssen danach einen neuen QR-Code scannen.",
	"Du bist jetzt Gastgeber. Öffne das Spiel-WLAN und lass die anderen den QR-Code scannen.",
	"Auf den Platz von %s setzen",
	"%s spielt dann mit den Karten von %s weiter.",
	"Hinsetzen",
	"Abbrechen",
	"%s möchte mitspielen – ☰ → Mitspieler dazuholen.",
	"%s möchte mitspielen – ☰ → „Mitspieler dazuholen“.",
	"%s führt dieses Spiel schon – ihr spielt dort weiter.",
	"Spiel-WLAN neu öffnen",
	"Beim neuen Gastgeber scannen",
	"In neuem Raum fortsetzen",
	"Mit neuem Code beitreten",
	"Neuer Raum %s. Schick den anderen den Link – sie kommen damit auf ihre Plätze.",
	"Gastgeber fehlt – suche den neuen Gastgeber …",
	"Das Spiel läuft jetzt über das Internet weiter.",
	"Weiter",
	"Neues Spiel-WLAN bei %s. Verbinde dich mit dem WLAN-Code auf diesem Handy und scanne dann den Spiel-Code.",
	"Über das Internet weiterspielen",
	"Kann kein Spiel-WLAN öffnen.",
	"Muss das Spiel-WLAN erlauben.",
	"Dein Spiel-WLAN geht dann zu – alle müssen einen neuen QR-Code scannen.",
]

var ok := 0
var failed := false


func _initialize() -> void:
	call_deferred("run")


func check(cond: bool, what: String) -> void:
	if cond:
		ok += 1
	else:
		failed = true
		print("FAIL: " + what)


func run() -> void:
	var ids := {}            # msgid → Anzahl über alle .po
	var strs := {}           # msgid → msgstr
	for path in I18n.FILES:
		for e in I18nTest.parse_po(FileAccess.get_file_as_string(path)):
			var id := str(e[0])
			if id == "":
				continue
			ids[id] = int(ids.get(id, 0)) + 1
			strs[id] = str(e[1])
	I18n.set_language("en")
	for t in TEXTS:
		check(int(ids.get(t, 0)) == 1, "genau eine msgid: " + t)
		var s := str(strs.get(t, ""))
		check(s != "" and s != t, "Übersetzung vorhanden: " + t)
		check(I18n.placeholders(s) == I18n.placeholders(t), "Platzhalter gleich: %s → %s" % [t, s])
		check(not I18nTest.looks_german(s), "keine deutschen Reste: " + s)
		check(I18n.t(t) == s, "I18n.t übersetzt: %s → %s" % [t, I18n.t(t)])
	I18n.set_language("de")
	check(I18n.t("Hinsetzen") == "Hinsetzen", "zurück auf Deutsch")
	if failed:
		print("FAIL: test_i18n_handover_wlan")
	else:
		print("RESULT: %d ok" % ok)
	await CleanExit.finish(self, 1 if failed else 0)
