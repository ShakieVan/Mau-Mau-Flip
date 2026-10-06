class_name SettingsScreen
extends AppScreen
# Einstellungen: Name, Ton (Mau-Ton aus/leise/normal mit Probehören der Aufnahmen „Mau!“ und „Mau-Mau!“, Spieltöne
# aus/leise/normal, Standard aus), Spielbare Karten hervorheben (nur dieses Gerät), Vibration, Effekte, Updates (Beta-Kanal,
# Jetzt prüfen, Fortschritt, Installieren, Im Browser herunterladen), App teilen, Info (Version, Lizenz, Schriften).
# Alles wird sofort in App.settings gespeichert.

var _name: LineEdit
var _update_status: Label
var _update_bar: ProgressBar
var _check_btn: Button
var _download_btn: Button
var _install_btn: Button
var _browser_btn: Button
var _share_status: Label


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
	player.add_child(ScreenKit.row("Name", _name, 150.0))
	var sound := _section(left, "Ton")
	var levels := [["aus", "Aus"], ["leise", "Leise"], ["normal", "Normal"]]
	var ton := ScreenKit.choice(levels, MauSound.level(), _on_mau_ton, 21)
	ton.name = "MauTon"
	sound.add_child(ScreenKit.row("Mau-Ton", ton, 150.0))
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
	sound.add_child(ScreenKit.row("Probehören", probe_row, 150.0))
	var cat := ScreenKit.hint("Der Mau-Ton klingt auf allen Geräten am Tisch, wenn jemand „Mau!“ ruft oder fertig wird. Die Sprechblase sieht man auch ohne Ton. Katze im Raum? Leise stellen.", 18)
	cat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sound.add_child(cat)
	var toene_val := str(UiApp.setting("toene", "aus"))
	var toene := ScreenKit.choice(levels, toene_val if AppSettings.TOENE.has(toene_val) else "aus", _on_toene, 21)
	toene.name = "Toene"
	sound.add_child(ScreenKit.row("Spieltöne", toene, 150.0, "Karte, Ziehen, Mischen, Flip, Sieg"))
	var look := _section(left, "Bedienung und Optik")
	# Persönliche Hilfe, nie eine Regel des Gastgebers (AGENTS.md 24); der Tisch (HandView) hört auf App.settings.changed.
	look.add_child(ScreenKit.switch_row("Spielbare Karten hervorheben", "Nur auf diesem Gerät: Karten, die du gerade legen kannst, werden in deiner Hand hervorgehoben.",
		bool(UiApp.setting("hervorheben", true)), func(on: bool) -> void: _store("hervorheben", on), "Hervorheben"))
	look.add_child(ScreenKit.switch_row("Vibration", "", bool(UiApp.setting("vibration", true)), func(on: bool) -> void: _store("vibration", on), "Vibration"))
	var fx := ScreenKit.choice([["voll", "Voll"], ["reduziert", "Reduziert"]], str(UiApp.setting("effekte", "voll")), func(v: String) -> void: _store("effekte", v), 21)
	fx.name = "Effekte"
	look.add_child(ScreenKit.row("Effekte", fx, 150.0, "Reduziert: kürzer, weniger Teilchen"))
	# --- Updates, Teilen, Info
	var upd := _section(right, "Updates")
	var beta := ScreenKit.switch("Testversionen (Beta-Kanal)", _beta(), _on_beta)
	beta.name = "Beta"
	upd.add_child(beta)
	_update_status = ScreenKit.text_block("", 21)
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
	share.add_child(ScreenKit.hint("Ohne Internet an Geräte in der Nähe, z. B. per Quick Share. Im WLAN-Spiel bekommen Mitspieler die App auch über die Seite des Gastgebers.", 19))
	var srow := ScreenKit.hbox(14)
	share.add_child(srow)
	var sb := ScreenKit.button("App teilen", "", "teilen")
	sb.name = "AppTeilen"
	sb.pressed.connect(_share)
	srow.add_child(sb)
	_share_status = ScreenKit.hint("", 18)
	_share_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_share_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	srow.add_child(_share_status)
	var info := _section(right, "Info")
	info.add_child(ScreenKit.text_block("Mau-Mau Flip %s\nEin Hobbyprojekt von ShakieVan." % MainMenuScreen._version_text(), 22))
	info.add_child(ScreenKit.hint("Lizenz: CC BY-NC 4.0 (nicht kommerziell). Schriften: Bricolage Grotesque und Fraunces unter der SIL Open Font License 1.1. Quellcode und Versionen auf GitHub: ShakieVan/Mau-Mau-Flip.", 18))
	var app := UiApp.app()
	for key in ["updater", "apk_share"]:
		var obj: Variant = app.get(key) if app != null else null
		if obj is Object and (obj as Object).has_signal("changed"):
			(obj as Object).connect("changed", _refresh)
	_refresh()


func _section(parent: Control, title_text: String) -> VBoxContainer:
	var card := ScreenKit.card(26.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var v := ScreenKit.vbox(12)
	card.add_child(v)
	v.add_child(ScreenKit.heading(title_text, 30))
	return v


func _settings() -> Object:
	var app := UiApp.app()
	var st: Variant = app.get("settings") if app != null else null
	return st as Object if st is Object else null


func _store(key: String, value: Variant) -> void:
	var st := _settings()
	if st != null:
		st.call("set_value", key, value)


# Neue Lautstärke gleich hörbar machen (bei „aus“ still)
func _on_mau_ton(v: String) -> void:
	_store("mau_ton", v)
	if v != "aus":
		MauSound.probe("mau")


func _on_toene(v: String) -> void:
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
	var text := status
	if avail and rel is Dictionary and not ready:
		text = "Neue Version %s verfügbar. %s" % [str((rel as Dictionary).get("version", "")), status if status.begins_with("Lade") else ""]
	_update_status.text = text.strip_edges()
	_update_bar.visible = busy and pct >= 0
	_update_bar.value = pct
	_check_btn.disabled = busy
	_download_btn.visible = avail and not ready and not busy
	_install_btn.visible = ready
	_browser_btn.visible = true
	var share: Variant = UiApp.app().get("apk_share") if UiApp.app() != null else null
	if share is Object:
		_share_status.text = str((share as Object).get("status"))
