class_name AppScreen
extends Control
# Grundlage aller Bildschirme (Hauptmenü, Einrichtungen, Lobby, Regeln, Einstellungen, Tisch). Die Bildschirmverwaltung
# (ScreenNav, main.tscn) setzt nav, blendet über und fragt bei Zurück (Android-Taste, Esc) zuerst on_back().

var nav: ScreenNav
var built := false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	if not built:
		built = true
		build()


# Aufbau einmalig beim ersten Erscheinen
func build() -> void:
	pass


# Zurück gedrückt: true = selbst erledigt (z. B. Rückfrage), false = eine Ebene zurück
func on_back() -> bool:
	return false


# Bildschirm wird (wieder) oberster bzw. verlässt die oberste Ebene
func on_enter() -> void:
	pass


func on_leave() -> void:
	pass


# Eigener Vollbild-Hintergrund (Tisch): der gemeinsame Menühintergrund darf ruhen
func covers_background() -> bool:
	return false


# Seitengerüst: Rand, Kopfzeile mit Zurück-Knopf und Titel; liefert den Inhaltsbereich (VBox, füllt den Rest)
func page(title_text: String, with_back := true, extra: Control = null) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 44)
	margin.add_theme_constant_override("margin_right", 44)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 26)
	add_child(margin)
	var outer := ScreenKit.vbox(18)
	margin.add_child(outer)
	var head := ScreenKit.hbox(20)
	head.custom_minimum_size = Vector2(0, ScreenKit.TOUCH)
	outer.add_child(head)
	if with_back:
		var back := ScreenKit.button("", "GhostButton", "zurueck", ScreenKit.TOUCH)
		back.name = "Zurueck"
		back.tooltip_text = "Zurück"
		back.pressed.connect(func() -> void:
			if nav != null:
				nav.go_back())
		head.add_child(back)
	var t := ScreenKit.title(title_text)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size_flags_vertical = Control.SIZE_FILL
	head.add_child(t)
	head.add_child(ScreenKit.spacer())
	if extra != null:
		head.add_child(extra)
	var content := ScreenKit.vbox(18)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(content)
	return content


func toast(text: String) -> void:
	if nav != null:
		nav.toast(text)
