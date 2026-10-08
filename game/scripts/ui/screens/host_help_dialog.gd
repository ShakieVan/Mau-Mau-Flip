class_name HostHelpDialog
extends Control
# „So geht's“ der Gastgeber-Lobby (Beta 1.0.2): kurze Anleitung zum Einladen, auch für Gäste ohne App (früher als Hinweise neben
# dem QR-Code). Papierkarte über abgedunkeltem Hintergrund; Tipp daneben, „Alles klar“ oder Zurück schließt.

signal closed

const TEXTS := [
	["① WLAN", "Alle Handys müssen im selben WLAN sein. Ist keins da, tippe „Spiel-WLAN öffnen“. Die anderen scannen dann den WLAN-Code mit der Kamera."],
	["② Spiel", "Danach den Spiel-Code scannen oder die Adresse im Browser eintippen. Mit der App: „Mit anderen spielen“ → „Beitreten“, das Spiel erscheint von selbst."],
	["Grüner Haken", "Zeigt, was schon geklappt hat. Der nächste Schritt leuchtet."],
	["Mitspieler", "Nach rechts blättern: Dort siehst du alle, änderst die Sitzordnung mit den Pfeilen und fügst Computergegner hinzu."],
]
const TIPS := [
	"Warnseite „nicht sicher“? Das ist normal im eigenen WLAN: „Weiter“ bzw. „Trotzdem öffnen“.",
	"iPhone: am besten mit Safari öffnen.",
	"Hotel- oder Gäste-WLAN: Dort finden sich die Handys oft nicht. Öffne dann lieber ein eigenes Spiel-WLAN.",
	"Meldet ein Handy im Spiel-WLAN „Kein Internet“: einfach verbunden bleiben.",
]

var _card: PanelContainer


static func open(parent: Node) -> HostHelpDialog:
	var d := HostHelpDialog.new()
	d.theme = UiTheme.get_theme()
	parent.add_child(d)
	d._build()
	return d


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	name = "SoGehts"


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 120)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	add_child(margin)
	_card = ScreenKit.card(30.0)
	margin.add_child(_card)
	var v := ScreenKit.vbox(14)
	_card.add_child(v)
	v.add_child(ScreenKit.heading("So geht's", UiFonts.size("ueberschrift")))
	var scroll := ScreenKit.scroller()
	v.add_child(scroll)
	var body := ScreenKit.vbox(12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	for t in TEXTS:
		var r := ScreenKit.hbox(16)
		var cap := ScreenKit.label(str(t[0]), "", UiFonts.size("text"))
		cap.add_theme_font_override("font", UiFonts.text(800))
		cap.custom_minimum_size = Vector2(UiFonts.px(190), 0)
		cap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		r.add_child(cap)
		var txt := ScreenKit.text_block(str(t[1]), UiFonts.size("text"))
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(txt)
		body.add_child(r)
	body.add_child(ScreenKit.heading("Ohne App spielen", UiFonts.size("zwischen")))
	for tip in TIPS:
		body.add_child(ScreenKit.hint("• " + I18n.t(str(tip)), UiFonts.size("hinweis")))
	var row := ScreenKit.hbox(12)
	v.add_child(row)
	row.add_child(ScreenKit.spacer())
	var ok := ScreenKit.button("Alles klar", "PrimaryButton", "", 240.0)
	ok.name = "AllesKlar"
	ok.pressed.connect(close)
	row.add_child(ok)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.1, 0.55))


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if not _card.get_global_rect().has_point(get_global_transform() * mb.position):
			close()
		accept_event()


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()
