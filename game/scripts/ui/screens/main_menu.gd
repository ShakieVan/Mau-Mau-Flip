class_name MainMenuScreen
extends AppScreen
# Hauptmenü: Logo links (Katze mit Tag- und Nachtkarte), rechts die Spielarten als große Knöpfe, darunter Regeln und
# Einstellungen; unter dem Logo „Update ↓“ (nur wenn der Updater eine neuere Version kennt) und „App teilen“, darunter klein die Version.

var _update_btn: Button
var _logo: LogoCard
var _version: Label
var _fx: TableEffects                # Konfetti/Sterne des Geheimtipps (Beta 1.4.4)
var easter_count := 0                # Tests: so oft wurde der Katzen-Geheimtipp ausgelöst
# Mau-Mau Flip (Beta 1.6.1, Gastgeber-Übergabe, docs/module/uebergabe.md 4.4): „Partie fortsetzen“ (Netzpartie aus der Datei, Zeile
# „Lena, Ben · Runde 2 · vor 3 min“) und „Partie verwerfen“, nur wenn HostSwitch.saved_offer etwas anbietet. Der Ablauf läuft in einem
# HostSwitch unter diesem Bildschirm (resume_saved): Warten mit „Abbrechen“, Rückfrage (confirm_needed), Raum abgelaufen (expired) mit
# „Partie verwerfen“; der fertige Tisch kommt über swapped.
# Beta 1.6.2 (docs/module/uebergabe.md 10.8, 10.13, 10.14): WLAN-Dateien (auch Gast) mit vorgeschalteter Suche („Verbinde …“ auch in
# searching), eigene Partie im Spiel-WLAN mit der Rückfrage „Spiel-WLAN neu öffnen“ · „Beim neuen Gastgeber scannen“
# (JoinScreen.rejoin), Raum abgelaufen zusätzlich „In neuem Raum fortsetzen“ (HostSwitch.resume_new_room) und „Mit neuem Code beitreten“.
var save_path := TableSource.NET_SAVE_PATH
var now_unix := -1                   # Tests: Wanduhr in s (−1 = echte Uhr)
var resume_row: VBoxContainer
var _resume_sub: Label
var _resume_sw: HostSwitch
var _resume_box: ConfirmBox          # Warten bzw. Rückfrage des Ablaufs
var _right: VBoxContainer            # Knopfspalte (mit „Partie fortsetzen“ etwas dichter)
# Mau-Mau Flip (Beta 1.6.16, Raum behalten, docs/module/raum_behalten.md 3): „Zurück ins Spiel“ (GuestReturn) mit „KATZE-42 · bei Lena ·
# vor 3 min“ und „Nicht mehr anzeigen“ – an derselben Stelle wie „Partie fortsetzen“, nie beide zugleich (Fortsetzen geht vor). Beim
# Anzeigen fragt das Menü den Vermittler (/info?room=); ist der Raum weg, verschwindet die Zeile.
var rejoin_row: VBoxContainer
var rejoin_check := true             # Tests: false = den Vermittler nicht fragen
var _rejoin_sub: Label
var _rejoin_http: HTTPRequest
var _rejoin_asked := ""              # Raum der letzten /info-Frage (room + t)


func build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)
	var cols := ScreenKit.hbox(56)
	margin.add_child(cols)
	# Logo links
	var left := ScreenKit.vbox(16)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.25
	cols.add_child(left)
	_logo = LogoCard.new()
	_logo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_logo)
	_logo.easter.connect(_on_easter)
	# Fußzeile (Beta 1.6.4, Nutzerbefund S24 Ultra mit 1.6.0): Versionstext, „App teilen“ und „Update ↓“ lagen in einer Zeile. Deren
	# Mindestbreite (~1070 px) machte die linke Spalte breiter als ihren Anteil, und die Knopfspalte lief rechts aus dem Bild. Jetzt: Knöpfe
	# in einer umbrechenden Reihe („Update ↓“ zuerst, sonnengelb), darunter der Versionstext mit Wortumbruch – die Fußzeile ist nie
	# breiter als ihr breitester Knopf.
	var foot := ScreenKit.vbox(8)
	foot.name = "Fuss"
	left.add_child(foot)
	var btns := HFlowContainer.new()
	btns.name = "FussKnoepfe"
	btns.add_theme_constant_override("h_separation", 14)
	btns.add_theme_constant_override("v_separation", 10)
	foot.add_child(btns)
	_update_btn = ScreenKit.button("Update ↓", "PrimaryButton", "update")
	_update_btn.name = "Update"
	_update_btn.add_theme_font_size_override("font_size", UiFonts.size("text"))
	_update_btn.visible = false
	_update_btn.pressed.connect(func() -> void: nav.push(SettingsScreen.new()))
	btns.add_child(_update_btn)
	var share := ScreenKit.button("App teilen", "GhostButton", "teilen")
	share.add_theme_font_size_override("font_size", UiFonts.size("text"))
	share.name = "AppTeilen"
	share.pressed.connect(_share)
	btns.add_child(share)
	_version = ScreenKit.label(I18n.t("Version %s · Ein Hobbyprojekt von ShakieVan") % _version_text(), "HintLabel", UiFonts.size("hinweis"))
	_version.name = "Version"
	_version.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_child(_version)
	# Knöpfe rechts
	var right := ScreenKit.vbox(16)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_child(right)
	_right = right
	resume_row = ScreenKit.vbox(2)
	resume_row.name = "Fortsetzen"
	resume_row.visible = false
	right.add_child(resume_row)
	var resume := _big("Partie fortsetzen", "", "start", "PrimaryButton")
	resume.name = "PartieFortsetzen"
	resume.pressed.connect(resume_saved)
	resume_row.add_child(resume)
	_resume_sub = resume.find_child("Unterzeile", true, false) as Label
	for l: Label in [resume.find_child("Titel", true, false), _resume_sub]:
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS   # nie über den Knopfrand (Namen, große Schrift)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(_resume_sub.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var drop_row := ScreenKit.hbox(0)
	resume_row.add_child(drop_row)
	drop_row.add_child(ScreenKit.spacer())
	var drop := ScreenKit.button("Partie verwerfen", "GhostButton", "", 0.0)
	drop.name = "PartieVerwerfen"
	drop.custom_minimum_size.y = 52
	drop.add_theme_font_size_override("font_size", UiFonts.size("hinweis"))
	drop.pressed.connect(ask_discard)
	drop_row.add_child(drop)
	_build_rejoin(right)
	var solo := _big("Übungsspiel", "gegen Computergegner", "start", "PrimaryButton")
	solo.name = "Uebungsspiel"
	solo.pressed.connect(func() -> void: nav.push(SoloSetupScreen.new()))
	right.add_child(solo)
	var pass_btn := _big("Auf einem Handy", "Weitergeben, 2–10 Spieler", "spieler")
	pass_btn.name = "Weitergeben"
	pass_btn.pressed.connect(func() -> void: nav.push(PassSetupScreen.new()))
	right.add_child(pass_btn)
	var wlan := _big("Mit anderen spielen", "WLAN oder online", "wlan")
	wlan.name = "Wlan"
	wlan.pressed.connect(func() -> void: nav.push(WlanScreen.new()))
	right.add_child(wlan)
	var row := ScreenKit.hbox(16)
	right.add_child(row)
	var rules := ScreenKit.button("Regeln", "", "regeln")
	rules.name = "Regeln"
	rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules.pressed.connect(func() -> void: nav.push(RulesScreen.new()))
	row.add_child(rules)
	var settings := ScreenKit.button("Einstellungen", "", "einstellungen")
	settings.name = "Einstellungen"
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.pressed.connect(func() -> void: nav.push(SettingsScreen.new()))
	row.add_child(settings)
	_fx = TableEffects.new()
	_fx.name = "GeheimEffekte"
	add_child(_fx)
	var app := UiApp.app()
	var up: Variant = app.get("updater") if app != null else null
	if up is Object and (up as Object).has_signal("changed"):
		(up as Object).connect("changed", _refresh_update)
	_refresh_update()
	refresh_resume()
	# App-Link „In der App spielen“ (Beta 1.0.2): Das Hauptmenü liegt immer unten im Stapel und nimmt Links entgegen
	if app != null and app.has_signal("app_link_received"):
		app.connect("app_link_received", _on_app_link)
		_on_app_link.call_deferred()


func _on_app_link() -> void:
	var app := UiApp.app()
	if nav == null or app == null or not app.has_method("take_pending_link"):
		return
	JoinScreen.handle_link(nav, app.call("take_pending_link"))


# Geheimtipps im Logo (Beta 1.4.4): "cat" = 7× schnell auf die Katze → Mau-Ton und kurzer Konfetti-/Sternenregen
func _on_easter(kind: String) -> void:
	if kind != "cat":
		return
	easter_count += 1
	MauSound.play(-1, -1, "mau")
	if _fx != null:
		_fx.night = float(easter_count % 2)          # abwechselnd Konfetti und Sterne
		_fx.reduced = UiApp.reduced_effects()
		_fx.celebrate(Rect2(0, 0, maxf(size.x, 800.0), 10), 80)


func on_enter() -> void:
	_refresh_update()
	_retext_version()
	refresh_resume()


func _retext_version() -> void:
	if _version != null:
		_version.text = I18n.t("Version %s · Ein Hobbyprojekt von ShakieVan") % _version_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_retext_version()
		refresh_resume()


# Großer Knopf mit zweiter Zeile (Erklärung)
func _big(text: String, sub: String, icon_name: String, variation := "") -> Button:
	var b := ScreenKit.button("", variation, "", 0.0)
	b.custom_minimum_size = Vector2(0, 104)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var inner := ScreenKit.hbox(20)
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 30
	inner.offset_right = -24
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(inner)
	# Beta 1.6.4: Ein Button zählt seine Kinder nicht zur Mindestgröße – die Mindestbreite folgt dem Inhalt (Symbol + Texte, auch live
	# bei geänderter Schrift), damit die Knopfspalte nie schmaler als ihr Text wird.
	var fit := func() -> void:
		b.custom_minimum_size.x = inner.get_combined_minimum_size().x + inner.offset_left - inner.offset_right
	inner.minimum_size_changed.connect(fit)
	var ic := TextureRect.new()
	ic.texture = ScreenKit.icon(icon_name)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(48, 48)
	ic.modulate = UiPalette.INK
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(ic)
	var texts := ScreenKit.vbox(0)
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(texts)
	var t := ScreenKit.label(text, "", UiFonts.size("zwischen"))
	t.add_theme_font_override("font", UiFonts.title(800, false, 50.0, 48.0))
	texts.add_child(t)
	t.name = "Titel"
	var s := ScreenKit.label(sub, "", UiFonts.size("hinweis"), Color(UiPalette.INK, 0.78))
	s.name = "Unterzeile"
	texts.add_child(s)
	fit.call()
	return b


func _refresh_update() -> void:
	if _update_btn == null:
		return
	var app := UiApp.app()
	var up: Variant = app.get("updater") if app != null else null
	var avail := false
	if up is Object and (up as Object).has_method("available"):
		avail = bool((up as Object).call("available"))
	_update_btn.visible = avail


func _share() -> void:
	var app := UiApp.app()
	var share: Variant = app.get("apk_share") if app != null else null
	if share is Object and (share as Object).has_method("available") and bool((share as Object).call("available")):
		(share as Object).call("share")
	else:
		toast("Teilen geht nur in der Android-App.")


# --- „Zurück ins Spiel“ (Beta 1.6.16, Raum behalten) ---

func _build_rejoin(right: VBoxContainer) -> void:
	rejoin_row = ScreenKit.vbox(2)
	rejoin_row.name = "Zurueck"
	rejoin_row.visible = false
	right.add_child(rejoin_row)
	var btn := _big("Zurück ins Spiel", "", "start", "PrimaryButton")
	btn.name = "ZurueckInsSpiel"
	btn.pressed.connect(rejoin_game)
	rejoin_row.add_child(btn)
	_rejoin_sub = btn.find_child("Unterzeile", true, false) as Label
	_rejoin_sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for l: Label in [btn.find_child("Titel", true, false), _rejoin_sub]:
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(_rejoin_sub.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var drop_row := ScreenKit.hbox(0)
	rejoin_row.add_child(drop_row)
	drop_row.add_child(ScreenKit.spacer())
	var drop := ScreenKit.button("Nicht mehr anzeigen", "GhostButton", "", 0.0)
	drop.name = "ZurueckVergessen"
	drop.custom_minimum_size.y = 52
	drop.add_theme_font_size_override("font_size", UiFonts.size("hinweis"))
	drop.pressed.connect(forget_rejoin)
	drop_row.add_child(drop)


# Gemerktes Online-Spiel als Gast (Tests überschreiben das)
func _rejoin_offer() -> Dictionary:
	return GuestReturn.current(now_unix)


# Zeile zeigen, wenn es ein gemerktes Spiel gibt und „Partie fortsetzen“ nicht da ist (und kein Fortsetzen-Ablauf läuft)
func refresh_rejoin() -> void:
	if rejoin_row == null:
		return
	var d := _rejoin_offer()
	var busy := _resume_sw != null and is_instance_valid(_resume_sw)
	rejoin_row.visible = not d.is_empty() and not resume_row.visible and not busy
	if not rejoin_row.visible:
		return
	_rejoin_sub.text = GuestReturn.subline(d, now_unix)
	_ask_rejoin_room(d)


func rejoin_game() -> void:
	var d := _rejoin_offer()
	if d.is_empty() or nav == null:
		refresh_resume()
		return
	GuestReturn.open(nav, d)


func forget_rejoin() -> void:
	GuestReturn.forget()
	refresh_resume()


# Gibt es den Raum noch? /info?room= beim Vermittler (einmal je gemerktem Raum und Menü); open:false → vergessen.
func _ask_rejoin_room(d: Dictionary) -> void:
	var key := "%s@%d" % [str(d.room), int(d.t)]
	if not rejoin_check or key == _rejoin_asked:
		return
	_rejoin_asked = key
	if _rejoin_http == null:
		_rejoin_http = HTTPRequest.new()
		_rejoin_http.name = "ZurueckPruefung"
		_rejoin_http.timeout = 8.0
		add_child(_rejoin_http)
		_rejoin_http.request_completed.connect(_on_rejoin_info)
	_rejoin_http.cancel_request()
	NetAddresses.hold_unbound(_rejoin_hold(), 10000)   # Android: ins Internet, nicht ins Spiel-WLAN
	if _rejoin_http.request(str(d.relay) + "/info?room=" + str(d.room)) != OK:
		NetAddresses.release_hold(_rejoin_hold())


func _rejoin_hold() -> String:
	return "rejoin_check:%d" % get_instance_id()


func _on_rejoin_info(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	NetAddresses.release_hold(_rejoin_hold())
	if result != HTTPRequest.RESULT_SUCCESS or status != 200:
		return                           # Vermittler nicht erreichbar: Zeile bleibt (der Tipp sagt dann, was los ist)
	var info: Variant = JSON.parse_string(body.get_string_from_utf8())
	var room: Variant = info.get("room") if info is Dictionary else null
	if room is Dictionary and not bool(room.get("open", false)):
		GuestReturn.forget()
		refresh_resume()


# --- „Partie fortsetzen“ (Beta 1.6.1, Gastgeber-Übergabe) ---

func _offer() -> Dictionary:
	return HostSwitch.saved_offer(save_path, now_unix)


# Zeile anzeigen bzw. verstecken: „Lena, Ben · Runde 2 · vor 3 min“ (die anderen am Tisch, höchstens zwei Namen)
func refresh_resume() -> void:
	if resume_row == null:
		return
	var d := _offer()
	resume_row.visible = not d.is_empty() and (_resume_sw == null or not is_instance_valid(_resume_sw))
	refresh_rejoin()
	if _right != null:
		_right.add_theme_constant_override("separation", 10 if resume_row.visible or rejoin_row.visible else 16)
	if d.is_empty() or _resume_sub == null:
		return
	var mine := int(d.host_seat) if str(d.role) == "host" else int(d.my_seat)
	var names: PackedStringArray = []
	for s in (d.seats as Array).size():
		if s != mine:
			names.append(str((d.seats[s] as Dictionary).get("name", "?")))
	var who := ", ".join(names.slice(0, 2)) + (" …" if names.size() > 2 else "")
	var now := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	var age := maxi(1, int(ceil(MatchSnapshot.age_s(d, now) / 60.0)))
	_resume_sub.text = I18n.t("%s · Runde %d · vor %d min") % [who, maxi(int((d.game as Dictionary).get("round", 1)), 1), age]


# Tipp auf „Partie fortsetzen“: zuerst als Gast mit dem eigenen Platz-Token (HostSwitch.resume_saved); antwortet niemand, führt dieses
# Handy (Rückfrage, außer bei der eigenen, eben gespeicherten Gastgeber-Partie).
func resume_saved() -> void:
	var d := _offer()
	if d.is_empty() or (_resume_sw != null and is_instance_valid(_resume_sw)):
		refresh_resume()
		return
	var sw := HostSwitch.new()
	sw.save_path = save_path
	if now_unix >= 0:
		sw.wall_ms = func() -> int: return now_unix * 1000
	_resume_sw = sw
	add_child(sw)
	_hook_resume(sw)
	resume_row.visible = false
	var err := sw.resume_saved(d)
	if err != OK and _resume_sw == sw:
		_close_resume_box()
		_end_resume()
		toast(I18n.t("Das geht gerade nicht."))


func _on_resume_state(state: String) -> void:
	if _resume_sw != null and is_instance_valid(_resume_sw) and _resume_sw.get_parent() != self and state != "off":
		return                              # zieht gerade mit dem neuen Tisch um (swapped folgt)
	match state:
		"resuming", "searching", "search":
			# Beta 1.6.2 (10.14): bei einer WLAN-Datei sucht der HostSwitch zuerst die gid im Netz – ebenfalls „Verbinde …“
			if _resume_box != null and is_instance_valid(_resume_box) and _resume_box.name == "FortsetzenWarten":
				return
			_close_resume_box()
			_resume_box = ConfirmBox.ask(self, "Partie fortsetzen", "Verbinde mit den anderen …", "", "Abbrechen")
			_resume_box.name = "FortsetzenWarten"
			var yes := _resume_box.find_child("Ja", true, false) as Control
			if yes != null:
				yes.visible = false
			_resume_box.answered.connect(func(_y: bool) -> void:
				_resume_box = null
				if _resume_sw != null and is_instance_valid(_resume_sw):
					_resume_sw.cancel())
		"expired":
			_close_resume_box()
			var sw := _resume_sw
			var why := sw.last_error if sw != null and sw.last_error != "" else "Der Online-Raum ist abgelaufen. Die Partie lässt sich nicht mehr fortsetzen."
			# Beta 1.6.2 (10.13): „In neuem Raum fortsetzen“ (der HostSwitch bleibt dafür bis zur Antwort) und „Mit neuem Code beitreten“
			var new_room := sw != null and is_instance_valid(sw) and sw.can_new_room()
			if not new_room:
				_end_resume()
			_resume_box = ConfirmBox.ask(self, "Partie fortsetzen", I18n.t(why), "Partie verwerfen", "Zurück")
			_resume_box.name = "FortsetzenAbgelaufen"
			var box := _resume_box
			if new_room:
				var nr := _resume_box.add_option("In neuem Raum fortsetzen", "start")
				nr.name = "NeuerRaum"
				nr.pressed.connect(func() -> void:
					_close_box(box)
					if _resume_sw == null or not is_instance_valid(_resume_sw) or _resume_sw.resume_new_room() or _resume_box != null:
						return                          # läuft (swapped bringt den Tisch) bzw. die Meldung steht schon wieder da
					toast(I18n.t("Das geht gerade nicht."))
					if _resume_sw.state == "expired":
						_on_resume_state("expired")
					else:
						_end_resume())
			var nc := _resume_box.add_option("Mit neuem Code beitreten", "qr")
			nc.name = "NeuerCode"
			nc.pressed.connect(func() -> void:
				_close_box(box)
				_end_resume()
				join_with_new_code())
			_resume_box.answered.connect(func(yes: bool) -> void:
				if _resume_box == box:
					_resume_box = null
				_end_resume()
				if yes:
					discard_saved())
		"off":
			# Gerätetest 1.6.1: Antwortet ein Gastgeber, zieht der HostSwitch mit dem neuen Gast-Tisch um (attach → „off“) und meldet
			# erst danach swapped. Das ist kein Abbruch – nur solange er noch am Hauptmenü hängt, ist „off“ das Ende des Ablaufs.
			if _resume_sw != null and is_instance_valid(_resume_sw) and _resume_sw.get_parent() != self:
				return
			_close_resume_box()
			_end_resume()


# Rückfrage, wenn niemand antwortet: Gast-Datei („Spiel als Gastgeber fortsetzen?“) bzw. ältere eigene Gastgeber-Datei
func _on_resume_confirm(info: Dictionary) -> void:
	_close_resume_box()
	var title := I18n.t("Spiel als Gastgeber fortsetzen?") if str(info.get("role", "")) == "guest" \
		else I18n.t("Deine Partie von vor %d min fortsetzen?") % maxi(int(info.get("age_min", 0)), 1)
	var ap := resume_in_game_wifi(info)
	# Beta 1.6.2 (10.8): eigene Partie im Spiel-WLAN – immer fragen, ob das Netz neu geöffnet oder beim neuen Gastgeber gescannt wird
	_resume_box = ConfirmBox.ask(self, title, "Dein Handy führt das Spiel ab jetzt. Die anderen kommen von selbst wieder dazu.",
		"Spiel-WLAN neu öffnen" if ap else "Fortsetzen", "Abbrechen")
	_resume_box.name = "FortsetzenRueckfrage"
	for w in info.get("warnings", []):
		_resume_box.add_note(I18n.render([w]))
	var box := _resume_box
	if ap:
		var scan := _resume_box.add_option("Beim neuen Gastgeber scannen", "qr")
		scan.name = "BeimNeuenScannen"
		scan.pressed.connect(func() -> void:
			_close_box(box)
			var d := _resume_data()
			_end_resume()
			rejoin_scan(d))
	_resume_box.answered.connect(func(yes: bool) -> void:
		if _resume_box == box:
			_resume_box = null
		if _resume_sw != null and is_instance_valid(_resume_sw):
			_resume_sw.confirm_resume(yes))


# Beta 1.6.2: Rückfrage zum Spiel-WLAN? (info.ap vom HostSwitch, sonst eigene Gastgeber-Datei mit wlan.ap)
func resume_in_game_wifi(info: Dictionary) -> bool:
	if info.has("ap"):
		return bool(info.ap)
	var d := _resume_data()
	var wlan: Dictionary = d.get("wlan", {}) if d.get("wlan") is Dictionary else {}
	return str(d.get("role", "")) == "host" and bool(wlan.get("ap", false)) and (d.get("online", {}) as Dictionary).is_empty()


# Stand des laufenden Ablaufs (bzw. die Datei)
func _resume_data() -> Dictionary:
	if _resume_sw != null and is_instance_valid(_resume_sw) and not _resume_sw._saved.is_empty():
		return _resume_sw._saved
	return _offer()


# „Beim neuen Gastgeber scannen“: Scanner auf der Beitrittsseite; mit bk_token landet man auf dem eigenen Platz (Datei bleibt)
func rejoin_scan(d: Dictionary) -> void:
	if nav == null:
		return
	var mine := int(d.get("host_seat", -1)) if str(d.get("role", "")) == "host" else int(d.get("my_seat", -1))
	var seats: Array = d.get("seats", []) if d.get("seats") is Array else []
	var who := str((seats[mine] as Dictionary).get("name", "")) if mine >= 0 and mine < seats.size() else ""
	nav.push(WlanScreen.new(), false)
	nav.push(JoinScreen.rejoin(str(d.get("gid", "")), who))


# „Mit neuem Code beitreten“ (Raum abgelaufen): Beitrittsseite (Raumcode, QR oder Link); die Datei bleibt für bk_token
func join_with_new_code() -> void:
	if nav == null:
		return
	nav.push(WlanScreen.new(), false)
	nav.push(JoinScreen.new())


# Rückfrage schließen, ohne zu antworten (der Ablauf entscheidet selbst weiter)
func _close_box(box: ConfirmBox) -> void:
	if _resume_box == box:
		_resume_box = null
	if box != null and is_instance_valid(box):
		box.queue_free()


# Fertig: Der HostSwitch hängt schon an der neuen Quelle (Gastgeber oder Gast); der Tisch kommt obenauf.
func _on_resume_swapped(src: TableSource, note: String) -> void:
	_close_resume_box()
	_unhook_resume(_resume_sw)             # der HostSwitch zieht mit der Quelle um; ab jetzt gehört er dem Tisch (TableScreen)
	_resume_sw = null
	if nav == null:
		return
	nav.push(TableScreen.create(src))
	if note != "":
		nav.toast(note)


func _close_resume_box() -> void:
	if _resume_box != null and is_instance_valid(_resume_box):
		_resume_box.queue_free()          # ohne answered: der Ablauf läuft weiter
	_resume_box = null


func _hook_resume(sw: HostSwitch) -> void:
	sw.swapped.connect(_on_resume_swapped)
	sw.confirm_needed.connect(_on_resume_confirm)
	sw.state_changed.connect(_on_resume_state)


# Signale des HostSwitch lösen: Nach „Partie fortsetzen“ zieht er mit der Quelle um und meldet später jeden Wechsel des Tisches – den
# ersetzt der TableScreen selbst; das Hauptmenü legte sonst einen zweiten Tisch an bzw. zeigte eine verdeckte Rückfrage.
func _unhook_resume(sw: HostSwitch) -> void:
	if sw == null or not is_instance_valid(sw):
		return
	for c in [[sw.swapped, _on_resume_swapped], [sw.confirm_needed, _on_resume_confirm], [sw.state_changed, _on_resume_state]]:
		if (c[0] as Signal).is_connected(c[1]):
			(c[0] as Signal).disconnect(c[1])


func _end_resume() -> void:
	var sw := _resume_sw
	_resume_sw = null
	_unhook_resume(sw)
	if sw != null and is_instance_valid(sw) and sw.get_parent() == self:
		sw.cancel()
		sw.queue_free()
	refresh_resume()


# „Partie verwerfen“: Rückfrage, dann die Datei löschen
func ask_discard() -> void:
	_close_resume_box()
	_resume_box = ConfirmBox.ask(self, "Partie verwerfen?", "Der gespeicherte Spielstand wird gelöscht.", "Verwerfen", "Abbrechen")
	_resume_box.name = "Verwerfen"
	_resume_box.answered.connect(func(yes: bool) -> void:
		_resume_box = null
		if yes:
			discard_saved())


# Zurück-Taste bei offener Rückfrage bzw. Warten: wie „Abbrechen“ (sonst schlösse sie die App)
func on_back() -> bool:
	if _resume_box != null and is_instance_valid(_resume_box) and not _resume_box.is_queued_for_deletion():
		_resume_box.cancel()
		return true
	return false


func discard_saved() -> void:
	TableSource.clear_saved(save_path)
	refresh_resume()


static func _version_text() -> String:
	var app := UiApp.app()
	if app != null and app.has_method("version"):
		return str(app.call("version"))
	return str(ProjectSettings.get_setting("application/config/version", ""))


# Logo als abgerundete Tafel mit Schatten; schwebt sanft (reduzierte Effekte: still)
class LogoCard:
	extends Control
	signal easter(kind: String)          # "cat" (7 Tipps), "sun" / "moon" (langes Drücken); Beta 1.4.4
	var tex: Texture2D
	var _t := 0.0
	var _mat: ShaderMaterial
	var _img: TextureRect
	var _face: FaceLayer
	var _fun := FunLogo.new()
	var _press_region := ""
	var _press_t := -1.0                 # Haltedauer in Sekunden, < 0 = nicht gedrückt
	var _hold_done := false
	var _hop_t := -1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		var path := "res://assets/ui/logo_klein.png"
		tex = load(path) as Texture2D if ResourceLoader.exists(path) else null
		_img = TextureRect.new()
		_img.texture = tex
		_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_img.stretch_mode = TextureRect.STRETCH_SCALE
		_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nuniform vec2 box_size = vec2(800.0, 450.0);\nuniform float radius = 34.0;\nvoid fragment() {\n\tvec2 p = UV * box_size;\n\tvec2 q = abs(p - box_size * 0.5) - (box_size * 0.5 - vec2(radius));\n\tfloat d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;\n\tCOLOR = texture(TEXTURE, UV);\n\tCOLOR.a *= clamp(0.5 - d, 0.0, 1.0);\n}\n"
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_img.material = _mat
		add_child(_img)
		_face = FaceLayer.new()
		_img.add_child(_face)
		resized.connect(_fit)

	func _rect() -> Rect2:
		var aspect := 16.0 / 9.0
		var w := minf(size.x, size.y * aspect)
		var h := w / aspect
		return Rect2((size.x - w) * 0.5, (size.y - h) * 0.5, w, h)

	func _fit() -> void:
		var r := _rect()
		_img.position = r.position
		_img.size = r.size
		_mat.set_shader_parameter("box_size", r.size)
		_mat.set_shader_parameter("radius", r.size.x * 0.04)
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var r := _rect()
		if mb.pressed:
			_press_region = FunLogo.region((mb.position - r.position) / r.size)
			_press_t = 0.0
			_hold_done = false
			return
		var was := _press_t >= 0.0 and not _hold_done and _press_region == "cat"
		_press_t = -1.0
		if was and _fun.register_tap(Time.get_ticks_msec()):
			hop()
			easter.emit("cat")

	# Kleiner Hüpfer der Katze beim 7. Tipp
	func hop() -> void:
		_hop_t = 0.0

	func _process(delta: float) -> void:
		# langes Drücken auf Sonne/Mond (Beta 1.4.4): grinst bzw. zwinkert kurz
		if _press_t >= 0.0 and not _hold_done and (_press_region == "sun" or _press_region == "moon"):
			_press_t += delta
			if _press_t >= FunLogo.HOLD_S:
				_hold_done = true
				_face.start(_press_region)
				easter.emit(_press_region)
		_face.step(delta)
		var lift := 0.0
		if _hop_t >= 0.0:
			_hop_t += delta
			lift = sin(clampf(_hop_t / 0.5, 0.0, 1.0) * PI) * 14.0
			if _hop_t >= 0.5:
				_hop_t = -1.0
		if UiApp.reduced_effects():
			return
		_t += delta
		var r := _rect()
		_img.position = r.position + Vector2(0, sin(_t * 0.9) * 4.0 - lift)
		_img.rotation = sin(_t * 0.6) * 0.004

	func _draw() -> void:
		var r := _rect()
		var sb := UiTheme.box(UiPalette.NIGHT, Color(0, 0, 0, 0), 0, int(r.size.x * 0.04))
		sb.shadow_color = Color(0.13, 0.1, 0.17, 0.35)
		sb.shadow_size = 28
		sb.shadow_offset = Vector2(0, 14)
		draw_style_box(sb, r.grow(-2.0))


# Gesichter für Sonne und Mond (Geheimtipp, Beta 1.4.4): liegt als Kind auf dem Logobild (Koordinaten des Bildes, 800 × 450)
class FaceLayer:
	extends Control
	const DUR := 1.7
	var kind := ""
	var t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func start(k: String) -> void:
		kind = k
		t = 0.0
		queue_redraw()

	func step(delta: float) -> void:
		if kind == "":
			return
		t += delta
		if t >= DUR:
			kind = ""
		queue_redraw()

	func _draw() -> void:
		if kind == "":
			return
		var s := size.x / 800.0
		var u := clampf(t / DUR, 0.0, 1.0)
		var a := clampf(minf(u * 8.0, (1.0 - u) * 5.0), 0.0, 1.0)
		var pop := 1.0 + 0.12 * sin(u * PI * 3.0)
		if kind == "sun":
			var c := Vector2(FunLogo.SUN.x, FunLogo.SUN.y + 2.0) * s
			var ink := Color(0.35, 0.12, 0.05, a)
			for sx in [-1.0, 1.0]:
				draw_arc(c + Vector2(sx * 17.0, -8.0) * s * pop, 8.0 * s, PI * 1.1, PI * 1.9, 10, ink, 4.0 * s, true)
				draw_circle(c + Vector2(sx * 30.0, 6.0) * s, 7.0 * s, Color(1.0, 0.45, 0.4, 0.55 * a))
			var grin := PackedVector2Array()
			for i in 15:
				var ang := lerpf(0.0, PI, i / 14.0)
				grin.append(c + Vector2(cos(ang) * 22.0, 4.0 + sin(ang) * 16.0 * pop) * s)
			draw_colored_polygon(grin, ink)
			var teeth := PackedVector2Array()
			for i in 15:
				var ang := lerpf(0.15, PI - 0.15, i / 14.0)
				teeth.append(c + Vector2(cos(ang) * 17.0, 5.0 + sin(ang) * 6.0) * s)
			draw_colored_polygon(teeth, Color(1, 0.97, 0.9, a))
		else:
			var c := Vector2(FunLogo.MOON.x, FunLogo.MOON.y) * s
			var ink := Color(0.12, 0.09, 0.3, a)
			draw_circle(c + Vector2(-17.0, -6.0) * s, 8.0 * s, Color(1, 1, 1, 0.9 * a))
			draw_circle(c + Vector2(-15.0, -6.0) * s, 4.4 * s, ink)
			draw_circle(c + Vector2(-16.5, -8.0) * s, 1.4 * s, Color(1, 1, 1, a))
			# zwinkerndes Auge: geschlossen als nach oben gewölbter Bogen
			draw_arc(c + Vector2(19.0, -5.0) * s, 8.0 * s, PI * 1.05, PI * 1.95, 10, ink, 4.0 * s, true)
			draw_arc(c + Vector2(0.0, 8.0) * s, 13.0 * s, 0.25 * PI, 0.75 * PI, 10, ink, 3.2 * s, true)
			# kleiner Funkelstern neben dem Auge
			var tw := 0.5 + 0.5 * sin(u * PI * 6.0)
			var sp := c + Vector2(40.0, -22.0) * s
			var l := (6.0 + 8.0 * tw) * s
			var col := Color(1, 0.95, 0.7, a)
			draw_line(sp - Vector2(l, 0), sp + Vector2(l, 0), col, 2.2 * s, true)
			draw_line(sp - Vector2(0, l), sp + Vector2(0, l), col, 2.2 * s, true)
