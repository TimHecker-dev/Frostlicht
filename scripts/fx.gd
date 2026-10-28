class_name Fx
extends RefCounted
## Kleine Helfer für Effekte: schwebende Zahlen, Partikel-Wölkchen, Schlag-Schwung.
## Alles landet im "Fx"-Layer der Welt. Der folgt der Kamera, wird aber nicht von der
## Dämmerungs-Färbung abgedunkelt – so bleiben Zahlen und Funken schön hell.


static func _layer(from: Node) -> Node:
	var layer := from.get_tree().get_first_node_in_group("fx")
	return layer if layer != null else from.get_tree().current_scene


static func text(from: Node, pos: Vector2, msg: String, color: Color = Color.WHITE,
		font_size: int = 20, life: float = 0.8) -> void:
	var label := Label.new()
	label.text = msg
	label.size = Vector2(160, 40)
	label.pivot_offset = label.size * 0.5
	label.position = pos - label.size * 0.5
	label.scale = Vector2.ONE / Game.WORLD_ZOOM   # große Schrift, klein skaliert = scharf
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.15, 0.95))
	label.add_theme_constant_override("outline_size", 6)
	if Game.ui_font != null:
		label.add_theme_font_override("font", Game.ui_font)
	_layer(from).add_child(label)
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - 14.0, life) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(label, "modulate:a", 0.0, life * 0.4).set_delay(life * 0.6)
	tw.chain().tween_callback(label.queue_free)


static func burst(from: Node, pos: Vector2, color: Color, amount: int = 12,
		life: float = 0.5, speed: float = 60.0) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = life
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2(0, 45)
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.damping_min = 25.0
	p.damping_max = 45.0
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.6
	p.color = color
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	p.color_ramp = ramp
	_layer(from).add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


## Heller Hieb, der um den Körper (pos) herumschwingt. angle = Schlagrichtung.
static func slash(from: Node, pos: Vector2, angle: float) -> void:
	var s := Sprite2D.new()
	s.texture = load("res://art/slash.png")
	s.position = pos
	s.offset = Vector2(14, 0)               # Drehpunkt liegt am Körper, der Bogen davor
	s.rotation = angle - 0.6
	s.scale = Vector2(0.8, 0.8)
	_layer(from).add_child(s)
	var tw := s.create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "rotation", angle + 0.6, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "scale", Vector2(1.2, 1.2), 0.2)
	tw.tween_property(s, "modulate:a", 0.0, 0.12).set_delay(0.1)
	tw.chain().tween_callback(s.queue_free)
