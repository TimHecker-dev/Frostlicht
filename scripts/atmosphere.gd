extends CanvasLayer
## Legt Vignette und Dunst (shaders/atmosphere.gdshader) über das ganze Bild.


func _ready() -> void:
	layer = 4
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/atmosphere.gdshader")
	rect.material = mat
	add_child(rect)
