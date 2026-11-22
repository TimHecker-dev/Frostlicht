extends CanvasLayer
class_name Aurora
## Legt das Polarlicht-Schimmern (shaders/aurora.gdshader) über das Bild. Die Arena steuert Stärke und Farben.

@export var intensity := 0.16

var _mat: ShaderMaterial


func _ready() -> void:
	layer = 3
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/aurora.gdshader")
	_mat.set_shader_parameter("intensity", intensity)
	rect.material = _mat
	add_child(rect)


func fade_to(value: float, seconds := 2.0) -> void:
	var from: float = _mat.get_shader_parameter("intensity")
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("intensity", v), from, value, seconds)


func set_colors(a: Color, b: Color) -> void:
	_mat.set_shader_parameter("color_a", a)
	_mat.set_shader_parameter("color_b", b)
