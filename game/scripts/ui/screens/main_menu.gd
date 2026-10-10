class_name MainMenuScreen
extends AppScreen
# Hauptmenü: Logo links (Katze mit Tag- und Nachtkarte), rechts die Spielarten als große Knöpfe, darunter Regeln und
# Einstellungen; klein: Version, „Update ↓“ (nur wenn der Updater eine neuere Version kennt) und „App teilen“.

var _update_btn: Button
var _logo: LogoCard
var _version: Label
var _fx: TableEffects                # Konfetti/Sterne des Geheimtipps (Beta 1.4.4)
var easter_count := 0                # Tests: so oft wurde der Katzen-Geheimtipp ausgelöst


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
	var foot := ScreenKit.hbox(14)
	left.add_child(foot)
	_version = ScreenKit.label(I18n.t("Version %s · Ein Hobbyprojekt von ShakieVan") % _version_text(), "HintLabel", UiFonts.size("hinweis"))
	_version.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_version)
	foot.add_child(ScreenKit.spacer())
	var share := ScreenKit.button("App teilen", "GhostButton", "teilen")
	share.add_theme_font_size_override("font_size", UiFonts.size("text"))
	share.name = "AppTeilen"
	share.pressed.connect(_share)
	foot.add_child(share)
	_update_btn = ScreenKit.button("Update ↓", "PrimaryButton", "update")
	_update_btn.name = "Update"
	_update_btn.add_theme_font_size_override("font_size", UiFonts.size("text"))
	_update_btn.visible = false
	_update_btn.pressed.connect(func() -> void: nav.push(SettingsScreen.new()))
	foot.add_child(_update_btn)
	# Knöpfe rechts
	var right := ScreenKit.vbox(16)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_child(right)
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


func _retext_version() -> void:
	if _version != null:
		_version.text = I18n.t("Version %s · Ein Hobbyprojekt von ShakieVan") % _version_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_retext_version()


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
	var s := ScreenKit.label(sub, "", UiFonts.size("hinweis"), Color(UiPalette.INK, 0.78))
	texts.add_child(s)
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
