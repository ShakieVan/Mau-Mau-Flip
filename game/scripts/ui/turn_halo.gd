class_name TurnHalo
extends Node2D
# Strahlenkranz um den Spieler am Zug (0.1.4): Shader res://assets/shaders/turn_halo.gdshader auf einem Rechteck um set_box().
# Liegt hinter dem Elternknoten (show_behind_parent). Sichtbar und animiert nur während des Zugs; aus = ausgeblendet und unsichtbar
# (kein Dauer-Neuzeichnen). night 0 Tag (gold) … 1 Nacht (bläulich); motion false (Effekte reduziert) hält die Strahlen an.

const SHADER := "res://assets/shaders/turn_halo.gdshader"

var active := false
var night := 0.0: set = set_night
var motion := true: set = set_motion
var reach := 64.0
var box := Rect2(-60, -20, 120, 40)

var _mat: ShaderMaterial
var _strength := 0.0
var _tw: Tween


func _init() -> void:
	show_behind_parent = true
	visible = false
	var sh := load(SHADER) as Shader
	if sh != null:
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		material = _mat
	_apply()


func set_box(r: Rect2, corner := 18.0) -> void:
	box = r
	position = r.get_center()
	_param("half_size", r.size * 0.5)
	_param("corner", minf(corner, minf(r.size.x, r.size.y) * 0.5))
	_param("reach", reach)
	_param("pad", _pad())
	queue_redraw()


func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	if on:
		visible = true
		_tw.tween_method(_set_strength, _strength, 1.0, 0.25)
	else:
		_tw.tween_method(_set_strength, _strength, 0.0, 0.2)
		_tw.tween_callback(func() -> void: visible = false)


func strength() -> float:
	return _strength


func set_night(v: float) -> void:
	night = clampf(v, 0.0, 1.0)
	_param("night", night)


func set_motion(on: bool) -> void:
	motion = on
	_param("motion", 1.0 if on else 0.0)


func _set_strength(v: float) -> void:
	_strength = v
	_param("strength", v)


func _apply() -> void:
	_param("night", night)
	_param("motion", 1.0 if motion else 0.0)
	_param("strength", _strength)


func _param(n: String, v: Variant) -> void:
	if _mat != null:
		_mat.set_shader_parameter(n, v)


func _pad() -> float:
	return reach * 1.9 + 8.0


func _draw() -> void:
	var pad := _pad()
	var h := box.size * 0.5 + Vector2(pad, pad)
	draw_rect(Rect2(-h, h * 2.0), Color.WHITE)
