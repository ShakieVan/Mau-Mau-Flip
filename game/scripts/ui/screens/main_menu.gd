class_name MainMenuScreen
extends AppScreen
# Hauptmenü: Logo links (Katze mit Tag- und Nachtkarte), rechts die Spielarten als große Knöpfe, darunter Regeln und
# Einstellungen; klein: Version, „Update ↓“ (nur wenn der Updater eine neuere Version kennt) und „App teilen“.

var _update_btn: Button
var _logo: LogoCard
var _version: Label


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
	var foot := ScreenKit.hbox(14)
	left.add_child(foot)
	_version = ScreenKit.label("Version %s · Ein Hobbyprojekt von ShakieVan" % _version_text(), "HintLabel", 19)
	_version.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_version)
	foot.add_child(ScreenKit.spacer())
	var share := ScreenKit.button("App teilen", "GhostButton", "teilen")
	share.add_theme_font_size_override("font_size", 21)
	share.name = "AppTeilen"
	share.pressed.connect(_share)
	foot.add_child(share)
	_update_btn = ScreenKit.button("Update ↓", "PrimaryButton", "update")
	_update_btn.name = "Update"
	_update_btn.add_theme_font_size_override("font_size", 21)
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
	var wlan := _big("Im WLAN spielen", "Spiel eröffnen oder beitreten", "wlan")
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
	var app := UiApp.app()
	var up: Variant = app.get("updater") if app != null else null
	if up is Object and (up as Object).has_signal("changed"):
		(up as Object).connect("changed", _refresh_update)
	_refresh_update()


func on_enter() -> void:
	_refresh_update()


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
	var t := ScreenKit.label(text, "", 31)
	t.add_theme_font_override("font", UiFonts.title(800, false, 50.0, 48.0))
	texts.add_child(t)
	var s := ScreenKit.label(sub, "", 19, Color(UiPalette.INK, 0.62))
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
	var tex: Texture2D
	var _t := 0.0
	var _mat: ShaderMaterial
	var _img: TextureRect

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	func _process(delta: float) -> void:
		if UiApp.reduced_effects():
			return
		_t += delta
		var r := _rect()
		_img.position = r.position + Vector2(0, sin(_t * 0.9) * 4.0)
		_img.rotation = sin(_t * 0.6) * 0.004

	func _draw() -> void:
		var r := _rect()
		var sb := UiTheme.box(UiPalette.NIGHT, Color(0, 0, 0, 0), 0, int(r.size.x * 0.04))
		sb.shadow_color = Color(0.13, 0.1, 0.17, 0.35)
		sb.shadow_size = 28
		sb.shadow_offset = Vector2(0, 14)
		draw_style_box(sb, r.grow(-2.0))
