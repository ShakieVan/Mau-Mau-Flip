class_name TableBackground
extends ColorRect
# Vollbild-Hintergrund mit dem Shader res://assets/shaders/table_background.gdshader. tageszeit 0 = Tag (Papier, Sonne),
# 1 = Nacht (Mond, Sterne). Die Karten werden dabei nicht abgedunkelt (06 Abschnitt 4.4: sonst wirkt das Neon matt).

const SHADER := "res://assets/shaders/table_background.gdshader"

var tageszeit := 0.0: set = set_tageszeit
var table_center := Vector2(800, 320): set = set_table_center
var motion := true: set = set_motion


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = UiPalette.PAPER
	var sh := load(SHADER) as Shader
	if sh != null:
		var mat := ShaderMaterial.new()
		mat.shader = sh
		material = mat
	resized.connect(_update_size)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_update_size()
	set_tageszeit(tageszeit)


func set_tageszeit(v: float) -> void:
	tageszeit = clampf(v, 0.0, 1.0)
	color = UiPalette.PAPER.lerp(UiPalette.NIGHT_HI, tageszeit)
	_param("tageszeit", tageszeit)


func set_table_center(p: Vector2) -> void:
	table_center = p
	_param("center", p)


func set_motion(on: bool) -> void:
	motion = on
	_param("motion", 1.0 if on else 0.0)


func _update_size() -> void:
	_param("size", size)


func _param(name: String, value: Variant) -> void:
	var mat := material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter(name, value)
