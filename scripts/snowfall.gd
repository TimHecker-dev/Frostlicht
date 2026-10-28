extends CanvasLayer
## Fallender Schnee als Bildschirm-Overlay – zwei Ebenen (fern/nah) für Tiefe.
## Liegt in einer eigenen Ebene, damit die Flocken hell bleiben und nicht von der
## Dämmerungs-Färbung der Welt abgedunkelt werden.

var _layers: Array[CPUParticles2D] = []


func _ready() -> void:
	layer = 3
	#                      Anzahl  Lebensdauer  Tempo (min/max)   Größe (min/max)  Deckkraft
	_layers.append(_make_layer(230, 13.0, 55.0, 80.0, 2.0, 3.2, 0.65))   # ferne, kleine Flocken
	_layers.append(_make_layer(80, 6.5, 115.0, 150.0, 3.2, 5.0, 0.92))    # nahe, große Flocken
	get_viewport().size_changed.connect(_fit)
	_fit()


func _make_layer(amount: int, life: float, v_min: float, v_max: float,
		s_min: float, s_max: float, alpha: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life                      # Bildschirm ist von Anfang an voll Schnee
	p.direction = Vector2(0.28, 1.0)         # leichter Wind von links
	p.spread = 14.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	p.scale_amount_min = s_min
	p.scale_amount_max = s_max
	p.color = Color(1, 1, 1, alpha)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(900, 2)
	add_child(p)
	return p


func _fit() -> void:
	var vp := get_viewport().get_visible_rect().size
	for p in _layers:
		p.position = Vector2(vp.x * 0.5 - 100.0, -12.0)
		p.emission_rect_extents = Vector2(vp.x * 0.5 + 130.0, 2.0)
