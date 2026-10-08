class_name SettingsScreen
extends AppScreen
# Einstellungen: Name, Ton (Mau-Ton aus/leise/normal mit Probehören der Aufnahmen „Mau!“ und „Mau-Mau!“, Spieltöne
# aus/leise/normal, Standard aus), Schriftgröße (Normal/Groß/Sehr groß, live), Spielbare Karten hervorheben (nur dieses Gerät), Vibration, Effekte, Updates (Beta-Kanal,
# Jetzt prüfen, Fortschritt, Installieren, Im Browser herunterladen), App teilen, Online (Vermittler-Adresse, Verbindung testen, QR),
# Deine Statistik (AppStats, mit Zurücksetzen),
# Info (Version, Lizenz, Schriften).
# Alles wird sofort in App.settings gespeichert.

var _name: LineEdit
var _update_status: Label
var _update_bar: ProgressBar
var _check_btn: Button
var _download_btn: Button
var _install_btn: Button
var _browser_btn: Button
var _share_status: Label
var _stats_list: VBoxContainer
var _stats_confirm: ConfirmBox
var _relay: LineEdit
var _relay_status: Label
var _relay_qr: TextureRect
var _relay_qr_label: Label
var _relay_test: HTTPRequest
var _relay_test_ms := 0
var _relay_ms := 0
var _relay_step := 0                 # 0 = /info, 1 = /c/<Version>/index.html
var _relay_info_body := ""


func build() -> void:
	var content := page("Einstellungen")
	var scroll := ScreenKit.scroller()
	content.add_child(scroll)
	var cols := ScreenKit.hbox(26)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cols)
	var left := ScreenKit.vbox(22)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var right := ScreenKit.vbox(22)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	# --- Spieler und Ton
	var player := _section(left, "Du")
	_name = LineEdit.new()
	_name.name = "Name"
	_name.text = str(UiApp.setting("name", ""))
	_name.placeholder_text = "Dein Name"
	_name.max_length = AppSettings.NAME_MAX
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.custom_minimum_size = Vector2(0, ScreenKit.TOUCH)
	_name.text_changed.connect(func(t: String) -> void: _store("name", AppSettings.clean_name(t)))
	_name.text_submitted.connect(func(_t: String) -> void: _name.release_focus())
	player.add_child(ScreenKit.row("Name", _name, 190.0))
	# Sprache (Beta 1.2.2, I18n): Automatisch = Systemsprache; wirkt sofort (App → I18n.apply, Texte übersetzen sich selbst).
	var lang_val := str(UiApp.setting(I18n.SETTING, "auto"))
	var lang := ScreenKit.choice(I18n.CHOICE_NAMES, lang_val if I18n.CHOICES.has(lang_val) else "auto",
		func(v: String) -> void: _store(I18n.SETTING, v), UiFonts.size("text"))
	lang.name = "Sprache"
	for b in lang.get_children():
		if b is Button and str(b.get_meta("key", "")) == "en":
			(b as Button).auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # „English“ heißt in jeder Sprache so
	player.add_child(ScreenKit.row("Sprache", lang, 190.0))
	personal(left, _section, true)
	# --- Updates, Teilen, Info
	var upd := _section(right, "Updates")
	var beta := ScreenKit.switch("Testversionen (Beta-Kanal)", _beta(), _on_beta)
	beta.name = "Beta"
	upd.add_child(beta)
	_update_status = ScreenKit.text_block("", UiFonts.size("text"))
	upd.add_child(_update_status)
	_update_bar = ProgressBar.new()
	_update_bar.custom_minimum_size = Vector2(0, 16)
	_update_bar.show_percentage = false
	_update_bar.visible = false
	upd.add_child(_update_bar)
	var urow := HFlowContainer.new()
	urow.add_theme_constant_override("h_separation", 12)
	urow.add_theme_constant_override("v_separation", 12)
	upd.add_child(urow)
	_check_btn = ScreenKit.button("Jetzt prüfen", "", "update")
	_check_btn.name = "JetztPruefen"
	_check_btn.pressed.connect(func() -> void: _updater_call("check", [true]))
	urow.add_child(_check_btn)
	_download_btn = ScreenKit.button("Herunterladen", "PrimaryButton", "update")
	_download_btn.pressed.connect(func() -> void: _updater_call("download"))
	urow.add_child(_download_btn)
	_install_btn = ScreenKit.button("Installieren", "PrimaryButton", "start")
	_install_btn.name = "Installieren"
	_install_btn.pressed.connect(_install)
	urow.add_child(_install_btn)
	_browser_btn = ScreenKit.button("Im Browser herunterladen", "GhostButton")
	_browser_btn.name = "ImBrowser"
	_browser_btn.pressed.connect(func() -> void: _updater_call("open_release_page"))
	urow.add_child(_browser_btn)
	var share := _section(right, "App weitergeben")
	share.add_child(ScreenKit.hint("Ohne Internet an Geräte in der Nähe, z. B. per Quick Share. Im WLAN-Spiel bekommen Mitspieler die App auch über die Seite des Gastgebers.", UiFonts.size("hinweis")))
	var srow := ScreenKit.hbox(14)
	share.add_child(srow)
	var sb := ScreenKit.button("App teilen", "", "teilen")
	sb.name = "AppTeilen"
	sb.pressed.connect(_share)
	srow.add_child(sb)
	_share_status = ScreenKit.hint("", UiFonts.size("hinweis"))
	_share_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_share_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	srow.add_child(_share_status)
	_build_online(_section(right, "Online"))
	_build_stats(_section(right, AppStats.TITLE))
	var info := _section(right, "Info")
	var ver := ScreenKit.text_block("Mau-Mau Flip %s" % MainMenuScreen._version_text(), UiFonts.size("text"))
	ver.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	info.add_child(ver)
	info.add_child(ScreenKit.text_block("Ein Hobbyprojekt von ShakieVan.", UiFonts.size("text")))
	info.add_child(ScreenKit.hint("Lizenz: CC BY-NC 4.0 (nicht kommerziell). Schriften: Bricolage Grotesque und Fraunces unter der SIL Open Font License 1.1. Quellcode und Versionen auf GitHub: ShakieVan/Mau-Mau-Flip.", UiFonts.size("hinweis")))
	var app := UiApp.app()
	for key in ["updater", "apk_share"]:
		var obj: Variant = app.get(key) if app != null else null
		if obj is Object and (obj as Object).has_signal("changed"):
			(obj as Object).connect("changed", _refresh)
	_refresh()


# Persönliche Einstellungen „Ton“ und „Bedienung und Optik“ (Beta 1.1.2): hier und im Spiel (IngameSettings über den ☰-Knopf)
# dieselben Zeilen. section(parent, titel) → VBoxContainer legt einen Abschnitt an; tempo = Regler der Computergegner zeigen.
static func personal(parent: Control, section: Callable, tempo := true) -> void:
	var sound: Control = section.call(parent, "Ton")
	var levels := [["aus", "Aus"], ["leise", "Leise"], ["normal", "Normal"]]
	var ton := ScreenKit.choice(levels, MauSound.level(), _on_mau_ton, UiFonts.size("text"))
	ton.name = "MauTon"
	sound.add_child(ScreenKit.row("Mau-Ton", ton, 190.0))
	var probe_row := ScreenKit.hbox(12)
	var probe := ScreenKit.button("Mau!", "GhostButton", "mau")
	probe.name = "Probehoeren"
	probe.tooltip_text = "Probehören: „Mao“"
	probe.pressed.connect(func() -> void: MauSound.probe("mau"))
	probe_row.add_child(probe)
	var probe2 := ScreenKit.button("Mau-Mau!", "GhostButton", "mau")
	probe2.name = "ProbehoerenMauMau"
	probe2.tooltip_text = "Probehören: „Mao-Mao“"
	probe2.pressed.connect(func() -> void: MauSound.probe("mau_mau"))
	probe_row.add_child(probe2)
	sound.add_child(ScreenKit.row("Probehören", probe_row, 190.0))
	var cat := ScreenKit.hint("Der Mau-Ton klingt auf allen Geräten am Tisch, wenn jemand „Mau!“ ruft oder fertig wird. Die Sprechblase sieht man auch ohne Ton. Katze im Raum? Leise stellen.", UiFonts.size("hinweis"))
	cat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sound.add_child(cat)
	var toene_val := str(UiApp.setting("toene", "aus"))
	var toene := ScreenKit.choice(levels, toene_val if AppSettings.TOENE.has(toene_val) else "aus", _on_toene, UiFonts.size("text"))
	toene.name = "Toene"
	sound.add_child(ScreenKit.row("Spieltöne", toene, 190.0, "Karte, Ziehen, Mischen, Flip, Sieg"))
	var look: Control = section.call(parent, "Bedienung und Optik")
	# Schriftgröße je Gerät (Beta 1.0.1): wirkt sofort auf alle Bildschirme und den Tisch (ScreenNav → UiFonts.set_level)
	var big_hint := ScreenKit.hint("Tipp: Im großen Modus werden auch Karten, Ablage und Mitspieler riesig.", UiFonts.size("hinweis"))
	big_hint.name = "HinweisGrosserModus"
	big_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	big_hint.visible = str(UiApp.setting("schrift", "normal")) == "sehr_gross" and not bool(UiApp.setting("grosser_modus", false))
	var schrift := ScreenKit.choice(UiFonts.LEVEL_NAMES, str(UiApp.setting("schrift", "normal")), func(v: String) -> void:
		_store("schrift", v)
		if is_instance_valid(big_hint):
			big_hint.visible = v == "sehr_gross" and not bool(UiApp.setting("grosser_modus", false)))
	schrift.name = "Schrift"
	look.add_child(ScreenKit.row("Schrift", schrift, 190.0))
	look.add_child(big_hint)
	# Großer Modus (Beta 1.1.1): riesiger Stapel und Ablage, Mitspieler als Liste rechts; wirkt sofort am Tisch (TableView hört
	# auf App.settings.changed). Persönlich je Gerät.
	var on_big := func(on: bool) -> void:
		_store("grosser_modus", on)
		if is_instance_valid(big_hint):
			big_hint.visible = str(UiApp.setting("schrift", "normal")) == "sehr_gross" and not on
	look.add_child(ScreenKit.switch_row("Großer Modus", "Riesige Karten, Ablage und Farbe, Mitspieler als Liste rechts. Für schlechte Augen oder schlechtes Licht.",
		bool(UiApp.setting("grosser_modus", false)), on_big, "GrosserModus"))
	look.add_child(ScreenKit.switch_row("Bei deinem Zug: Vibration", "Kurz vibrieren, wenn du dran bist. Den Dran-Ton schaltest du mit den Spieltönen.",
		bool(UiApp.setting("zug_vibration", true)), func(on: bool) -> void: _store("zug_vibration", on), "ZugVibration"))
	# Persönliche Hilfe, nie eine Regel des Gastgebers (AGENTS.md 24); der Tisch (HandView) hört auf App.settings.changed.
	look.add_child(ScreenKit.switch_row("Spielbare Karten hervorheben", "Nur auf diesem Gerät: Karten, die du gerade legen kannst, werden in deiner Hand hervorgehoben.",
		bool(UiApp.setting("hervorheben", true)), func(on: bool) -> void: _store("hervorheben", on), "Hervorheben"))
	look.add_child(ScreenKit.switch_row("Vibration", "", bool(UiApp.setting("vibration", true)), func(on: bool) -> void: _store("vibration", on), "Vibration"))
	var fx := ScreenKit.choice([["voll", "Voll"], ["reduziert", "Reduziert"]], str(UiApp.setting("effekte", "voll")), func(v: String) -> void: _store("effekte", v), UiFonts.size("text"))
	fx.name = "Effekte"
	look.add_child(ScreenKit.row("Effekte", fx, 190.0, "Reduziert: kürzer, weniger Teilchen"))
	if tempo:
		look.add_child(tempo_row())


# „Online“ (docs/online/ENTWURF.md 3): Adresse des Vermittlers, „Verbindung testen“ (GET /info: Antwortzeit und ob er diese
# Version ausliefert) und ein QR-Code mit der Startseite des Vermittlers zum Weitergeben der Adresse.
func _build_online(box: VBoxContainer) -> void:
	var intro := ScreenKit.hint("Für Spiele über das Internet: Ein Vermittler reicht die Nachrichten weiter, die Spiellogik bleibt beim Gastgeber. Einrichten kostenlos bei Cloudflare, Anleitung auf GitHub (ShakieVan/Mau-Mau-Flip). Gäste brauchen nur Raumcode oder Link.", UiFonts.size("hinweis"))
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(intro)
	_relay = LineEdit.new()
	_relay.name = "Vermittler"
	_relay.placeholder_text = "z. B. mau.dein-name.workers.dev"
	_relay.text = NetProtocol.relay_host(str(UiApp.setting("vermittler", NetProtocol.RELAY_DEFAULT)))
	_relay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_relay.custom_minimum_size = Vector2(0, ScreenKit.TOUCH)
	_relay.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	_relay.text_submitted.connect(func(_t: String) -> void:
		_relay.release_focus()
		store_relay())
	_relay.focus_exited.connect(store_relay)
	box.add_child(ScreenKit.row("Vermittler", _relay, 190.0))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 12)
	box.add_child(row)
	var test := ScreenKit.button("Verbindung testen", "", "update")
	test.name = "VerbindungTesten"
	test.pressed.connect(test_relay)
	row.add_child(test)
	var qr_btn := ScreenKit.button("QR-Code", "GhostButton")
	qr_btn.name = "VermittlerQR"
	qr_btn.tooltip_text = "Adresse des Vermittlers als QR-Code weitergeben"
	qr_btn.pressed.connect(func() -> void: show_relay_qr(not _relay_qr.visible))
	row.add_child(qr_btn)
	_relay_status = ScreenKit.text_block("", UiFonts.size("text"))
	_relay_status.name = "VermittlerStatus"
	box.add_child(_relay_status)
	_relay_qr = TextureRect.new()
	_relay_qr.name = "VermittlerQRBild"
	_relay_qr.custom_minimum_size = Vector2(220, 220)
	_relay_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_relay_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_relay_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_relay_qr.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_relay_qr.visible = false
	box.add_child(_relay_qr)
	_relay_qr_label = ScreenKit.hint("", UiFonts.size("hinweis"))
	_relay_qr_label.visible = false
	box.add_child(_relay_qr_label)


# Eingabe übernehmen ("" = keiner). Ungültig → Hinweis, gespeichert bleibt der alte Wert.
func store_relay() -> void:
	if _relay == null:
		return
	var raw := _relay.text.strip_edges()
	var url := NetProtocol.normalize_relay_url(raw)
	if raw != "" and url == "":
		_relay_status.text = I18n.t("Diese Adresse passt nicht. Beispiel: mau.dein-name.workers.dev")
		return
	_store("vermittler", url)
	_relay.text = NetProtocol.relay_host(url)
	if _relay_qr.visible:
		show_relay_qr(true)


# GET <vermittler>/info: Antwortzeit und unterstützte Versionen
func test_relay() -> void:
	store_relay()
	var url := NetProtocol.normalize_relay_url(str(UiApp.setting("vermittler", "")))
	if url == "":
		_relay_status.text = I18n.t("Bitte zuerst die Adresse des Vermittlers eintragen.")
		return
	if _relay_test == null:
		_relay_test = HTTPRequest.new()
		_relay_test.name = "VermittlerTest"
		_relay_test.timeout = 10.0
		add_child(_relay_test)
		_relay_test.request_completed.connect(_on_relay_tested)
	_relay_test.cancel_request()
	_relay_test_ms = Time.get_ticks_msec()
	_relay_info_body = ""
	_relay_step = 0
	_relay_status.text = I18n.t("Teste die Verbindung …")
	if _relay_test.request(url + "/info") != OK:
		_on_relay_tested(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())


func _on_relay_tested(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var good := result == HTTPRequest.RESULT_SUCCESS
	var version := NetProtocol.game_version()
	if _relay_step == 0:
		_relay_ms = Time.get_ticks_msec() - _relay_test_ms
		_relay_info_body = body.get_string_from_utf8()
		if good and status == 200 and relay_info_ok(_relay_info_body):
			var url := NetProtocol.normalize_relay_url(str(UiApp.setting("vermittler", "")))
			_relay_step = 1
			if _relay_test.request(url + "/c/" + version + "/index.html") == OK:
				_relay_status.text = I18n.t("Prüfe den Browser-Client für Version %s …") % version
				return
			status = 0
			good = false
		else:
			_relay_status.text = relay_test_text(good and status == 200, _relay_info_body, _relay_ms, version, -1)
			return
	_relay_step = 0
	_relay_status.text = relay_test_text(true, _relay_info_body, _relay_ms, version, status if good else 0)


static func relay_info_ok(body: String) -> bool:
	var info: Variant = JSON.parse_string(body) if body.begins_with("{") else null
	return info is Dictionary and str(info.get("game", "")) == NetProtocol.GAME_ID


# Ergebnistext von „Verbindung testen“ (ohne Netz prüfbar). ok: /info kam mit 200; c_status: HTTP-Status von
# /c/<Version>/index.html (0 = keine Antwort, -1 = nicht abgefragt). Ein Vermittler ab Fassung 2 holt den Client selbst von GitHub.
static func relay_test_text(ok: bool, body: String, ms: int, version: String, c_status: int = 200) -> String:
	if not ok:
		return I18n.t("Vermittler nicht erreichbar. Stimmt die Adresse, und hast du Internet?")
	if not relay_info_ok(body):
		return I18n.t("Unter dieser Adresse antwortet kein Vermittler für Mau-Mau Flip.")
	var t := I18n.t("Vermittler antwortet (%d ms).") % ms
	if c_status == 200:
		return t + " " + I18n.t("Alles bereit für Online-Spiele.")
	var info: Dictionary = JSON.parse_string(body)
	if int(info.get("relay", 1)) >= 2 and (c_status == 404 or c_status >= 500):
		return t + " " + I18n.t("Die Version %s ist noch nicht auf GitHub veröffentlicht. Mit der App klappt es trotzdem.") % version
	return t + " " + I18n.t("Vermittler zu alt: Er kann den Browser-Client nicht selbst holen. Bitte neu bereitstellen (Anleitung auf GitHub). Mit der App klappt es trotzdem.")


# QR-Code mit der Startseite des Vermittlers (https://<v>/), darunter die Adresse
func show_relay_qr(on: bool) -> void:
	var url := NetProtocol.normalize_relay_url(str(UiApp.setting("vermittler", "")))
	_relay_qr.visible = on and url != ""
	_relay_qr_label.visible = _relay_qr.visible
	if on and url == "":
		_relay_status.text = I18n.t("Bitte zuerst die Adresse des Vermittlers eintragen.")
	if _relay_qr.visible:
		var code := QrCode.encode(url + "/")
		_relay_qr.texture = code.to_texture(8, 3, UiPalette.INK, Color.WHITE) if code != null else null
		_relay_qr_label.text = I18n.t("Scannen öffnet die Seite des Vermittlers: %s") % NetProtocol.relay_host(url)


# „Deine Statistik“ (Beta 1.2.1, AppStats): Zahlen dieses Geräts, Zurücksetzen mit Rückfrage. Kein eigener Knopf im Hauptmenü.
func _build_stats(box: VBoxContainer) -> void:
	var intro := ScreenKit.hint(AppStats.INTRO, UiFonts.size("hinweis"))
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(intro)
	_stats_list = ScreenKit.vbox(6)
	_stats_list.name = "StatistikZahlen"
	box.add_child(_stats_list)
	var pass_note := ScreenKit.hint(AppStats.PASS_NOTE, UiFonts.size("klein"))
	pass_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(pass_note)
	var reset := ScreenKit.button(AppStats.RESET, "GhostButton")
	reset.name = "StatistikZuruecksetzen"
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(_ask_reset_stats)
	box.add_child(reset)
	var st := _stats()
	if st != null and st.has_signal("changed"):
		st.connect("changed", _fill_stats)
	_fill_stats()


func _stats() -> Object:
	var app := UiApp.app()
	var st: Variant = app.get("stats") if app != null else null
	return st as Object if st is Object else null


func _fill_stats() -> void:
	if _stats_list == null or not is_instance_valid(_stats_list):
		return
	for c in _stats_list.get_children():
		c.queue_free()
	var st := _stats()
	if st == null or bool(st.call("is_empty")):
		_stats_list.add_child(ScreenKit.text_block(AppStats.EMPTY, UiFonts.size("text")))
		return
	for entry in st.call("rows"):
		var r := ScreenKit.hbox(12)
		var l := ScreenKit.label(str(entry[0]), "", UiFonts.size("text"))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		r.add_child(l)
		var v := ScreenKit.label(str(entry[1]), "", UiFonts.size("zeile"))
		v.add_theme_font_override("font", UiFonts.text(800))
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(v)
		_stats_list.add_child(r)


func _ask_reset_stats() -> void:
	if _stats_confirm != null and is_instance_valid(_stats_confirm):
		return
	_stats_confirm = ConfirmBox.ask(self, AppStats.RESET_TITLE, AppStats.RESET_TEXT, AppStats.RESET_YES, AppStats.RESET_NO)
	_stats_confirm.answered.connect(func(yes: bool) -> void:
		if yes:
			var st := _stats()
			if st != null:
				st.call("reset")
			toast(AppStats.RESET_DONE))


func _section(parent: Control, title_text: String) -> VBoxContainer:
	var card := ScreenKit.card(26.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var v := ScreenKit.vbox(12)
	card.add_child(v)
	v.add_child(ScreenKit.heading(title_text, UiFonts.size("zwischen")))
	return v


# Regler „Tempo der Computergegner“ (persönlich je Gerät, stufenlos; Mitte = Standard). Gespeichert wird beim Loslassen.
static func tempo_row() -> Control:
	var v := ScreenKit.vbox(4)
	v.name = "Tempo"
	var l := ScreenKit.label("Tempo der Computergegner", "", UiFonts.size("zeile"))
	l.add_theme_font_override("font", UiFonts.text(700))
	v.add_child(l)
	var h := ScreenKit.hbox(12)
	v.add_child(h)
	h.add_child(ScreenKit.label("gemütlich", "HintLabel", UiFonts.size("hinweis")))
	var s := HSlider.new()
	s.name = "TempoRegler"
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.value = clampf(float(UiApp.setting("bot_tempo", 0.5)), 0.0, 1.0)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(0, ScreenKit.TOUCH)
	s.focus_mode = Control.FOCUS_NONE
	# Großer, daumentauglicher Griff (Gerätetest 0.1.3: der Standardgriff war winzig)
	s.add_theme_icon_override("grabber", UiTheme.grabber_texture(46, UiPalette.CREAM, UiPalette.INK))
	s.add_theme_icon_override("grabber_highlight", UiTheme.grabber_texture(46, UiPalette.PAPER_D, UiPalette.INK))
	s.drag_started.connect(func() -> void: s.set_meta("dragging", true))
	s.drag_ended.connect(func(_changed: bool) -> void:
		s.set_meta("dragging", false)
		_store("bot_tempo", s.value))
	s.value_changed.connect(func(_v: float) -> void:   # Tippen auf die Leiste, Tastatur, Tests
		if not bool(s.get_meta("dragging", false)):
			_store("bot_tempo", s.value))
	h.add_child(s)
	h.add_child(ScreenKit.label("flott", "HintLabel", UiFonts.size("hinweis")))
	var hint := ScreenKit.hint("Nur die Bedenkzeit, nicht die Animationen. Im WLAN gilt der Regler des Gastgebers.", UiFonts.size("klein"))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(hint)
	return v


static func _settings() -> Object:
	var app := UiApp.app()
	var st: Variant = app.get("settings") if app != null else null
	return st as Object if st is Object else null


static func _store(key: String, value: Variant) -> void:
	var st := _settings()
	if st != null:
		st.call("set_value", key, value)


# Neue Lautstärke gleich hörbar machen (bei „aus“ still)
static func _on_mau_ton(v: String) -> void:
	_store("mau_ton", v)
	if v != "aus":
		MauSound.probe("mau")


static func _on_toene(v: String) -> void:
	_store("toene", v)
	if v != "aus":
		UiApp.sound("karte")


func _updater() -> Object:
	var app := UiApp.app()
	var up: Variant = app.get("updater") if app != null else null
	return up as Object if up is Object else null


func _updater_call(method: String, args: Array = []) -> void:
	var up := _updater()
	if up != null and up.has_method(method):
		up.callv(method, args)
	_refresh()


func _beta() -> bool:
	var up := _updater()
	if up != null and up.has_method("beta"):
		return bool(up.call("beta"))
	return bool(UiApp.setting("beta", true))


func _on_beta(on: bool) -> void:
	var up := _updater()
	if up != null and up.has_method("set_beta"):
		up.call("set_beta", on)
	else:
		_store("beta", on)
	_refresh()


func _install() -> void:
	var up := _updater()
	if up == null:
		return
	if up.has_method("can_install") and not bool(up.call("can_install")):
		toast("Bitte „Unbekannte Apps installieren“ für Mau-Mau Flip erlauben.")
		up.call("open_permission")
		return
	up.call("install")


func _share() -> void:
	var app := UiApp.app()
	var share: Variant = app.get("apk_share") if app != null else null
	if share is Object and (share as Object).has_method("available") and bool((share as Object).call("available")):
		(share as Object).call("share")
	else:
		toast("Teilen geht nur in der Android-App.")
	_refresh()


func _refresh() -> void:
	if _update_status == null:
		return
	var up := _updater()
	if up == null:
		_update_status.text = "Updates gibt es nur in der App."
		for b in [_check_btn, _download_btn, _install_btn]:
			(b as Button).visible = false
		return
	var status := str(up.get("status"))
	var avail := up.has_method("available") and bool(up.call("available"))
	var busy := bool(up.get("busy"))
	var ready := bool(up.get("apk_ready"))
	var pct := int(up.get("percent"))
	var rel: Variant = up.get("release")
	# Statustexte des Updaters sind deutsche msgids (ohne Platzhalter) und werden hier übersetzt.
	var text := I18n.t(status)
	for pre in ["Zuletzt geprüft: ", "Last checked: "]:   # gespeicherter Status mit Zeit: in der aktuellen Sprache neu setzen
		if status.begins_with(pre):
			text = I18n.t("Zuletzt geprüft: %s.") % status.substr(pre.length()).trim_suffix(".")
	if avail and rel is Dictionary and not ready:
		text = tr("Neue Version %s verfügbar.") % str((rel as Dictionary).get("version", "")) + (" " + I18n.t(status) if status.begins_with("Lade") else "")
	_update_status.text = text.strip_edges()
	_update_bar.visible = busy and pct >= 0
	_update_bar.value = pct
	_check_btn.disabled = busy
	_download_btn.visible = avail and not ready and not busy
	_install_btn.visible = ready
	_browser_btn.visible = true
	var share: Variant = UiApp.app().get("apk_share") if UiApp.app() != null else null
	if share is Object:
		_share_status.text = I18n.t(str((share as Object).get("status")))


# Sprache gewechselt (I18n): Labels und Knöpfe übersetzen sich selbst, nur die zusammengesetzten Statuszeilen neu setzen.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and built:
		_refresh()
