extends Node2D
class_name Portal
## Ein Durchgang zu einem anderen Gebiet (Höhleneingang im Wald, Ausgang in der Frosthöhle).
## Steht man davor, erscheint ein Hinweis; mit E (Controller: B) geht es durch.
## Mit lock() lässt sich der Durchgang sperren (z. B. solange der Boss kämpft).

@export var target_scene := ""
@export var entry := ""
@export var prompt := "E: Betreten"
@export var locked_prompt := "Der Ausgang ist vereist ..."

var enabled := true
var _near := false
var _player: Player
var _time := randf() * 10.0

@onready var light: PointLight2D = $Light


func _ready() -> void:
	add_child(_make_motes())


func lock(text := "") -> void:
	enabled = false
	if text != "":
		locked_prompt = text
	modulate = Color(0.7, 0.8, 1.0)


func unlock() -> void:
	enabled = true
	modulate = Color.WHITE


func _process(delta: float) -> void:
	_time += delta
	light.energy = (0.6 if enabled else 0.25) + sin(_time * 2.3) * 0.08


func _physics_process(_delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
		return
	var near := not _player.dead and _player.global_position.distance_to(global_position) < 36.0
	var ui := get_tree().get_first_node_in_group("ui") as GameUI
	if near != _near:
		_near = near
		if ui != null:
			ui.set_prompt((prompt if enabled else locked_prompt) if near else "")
	if _near and Input.is_action_just_pressed("interact"):
		if enabled:
			Scenes.change_area(target_scene, entry)
		else:
			Sound.play("deny")
			if ui != null:
				ui.announce(locked_prompt)


func _make_motes() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = Vector2(0, -18)
	p.amount = 10
	p.lifetime = 2.2
	p.preprocess = 2.2
	p.direction = Vector2.UP
	p.spread = 25.0
	p.gravity = Vector2(0, -6)
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 12.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(8, 10)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.8
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	ramp.colors = PackedColorArray([Color(0.7, 0.95, 1.0, 0.0), Color(0.7, 0.95, 1.0, 0.9), Color(0.7, 0.95, 1.0, 0.0)])
	p.color_ramp = ramp
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = add
	return p
