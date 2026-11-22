extends CanvasLayer
## Legt Vignette und Dunst (shaders/atmosphere.gdshader) über das ganze Bild.
## Die Werte lassen sich pro Gebiet im Editor einstellen (Frosthöhle: dunkler und kühler).

@export var vignette := 0.62
@export var fog := 0.10
@export var fog_color := Color(0.78, 0.87, 1.0)
@export var vignette_color := Color(0.03, 0.05, 0.13)


func _ready() -> void:
	layer = 4
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/atmosphere.gdshader")
	mat.set_shader_parameter("vignette_strength", vignette)
	mat.set_shader_parameter("fog_amount", fog)
	mat.set_shader_parameter("fog_color", fog_color)
	mat.set_shader_parameter("vignette_color", vignette_color)
	rect.material = mat
	add_child(rect)
