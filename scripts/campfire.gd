extends Node2D
class_name Campfire
## Das Lagerfeuer: Flammen, Funken, flackerndes Licht – und ein sicherer Ort.
## Wer in der Nähe steht, erholt sich langsam; Gegner meiden den Feuerschein.

signal rest_changed(resting: bool)

const REST_RADIUS := 48.0        # so nah muss man sein, um sich zu erholen
const HEAL_INTERVAL := 0.6       # alle x Sekunden ...
const HEAL_AMOUNT := 3           # ... so viel Leben

var player_near := false        # true, solange man am Feuer geheilt wird

var _time := randf() * 10.0
var _heal_t := 0.4
var _player: Player
var _crackle: AudioStreamPlayer2D

@onready var light: PointLight2D = $Light
@onready var chill: PointLight2D = $Chill


func _ready() -> void:
	_add_particles.call_deferred()      # erst nach dem Platzieren durch die Welt
	var loop := Sound.loop_stream("amb_fire")
	if loop != null:                    # Knistern: räumlich, wird mit Abstand leiser und wandert beim Drehen mit
		var crackle := AudioStreamPlayer2D.new()
		_crackle = crackle
		crackle.stream = loop
		crackle.bus = Sound.BUS_AMBIENCE
		crackle.volume_db = Sound.FIRE_DB
		crackle.max_distance = 300.0
		crackle.attenuation = 1.3
		crackle.panning_strength = 1.5
		crackle.position = Vector2(0, -6)
		crackle.process_mode = Node.PROCESS_MODE_ALWAYS     # im Menü läuft es (gedämpft) weiter
		add_child(crackle)
		Sound.register_loop(crackle)
		crackle.play(randf() * 8.0)


## Flammen und Funken liegen in der hellen Fx-Ebene, damit sie nicht von der Dämmerung gedämpft werden.
func _add_particles() -> void:
	var host: Node = get_tree().get_first_node_in_group("fx")
	var base := global_position
	if host == null:
		host = self
		base = Vector2.ZERO
	var flames := _make_flames()
	flames.position = base + Vector2(0, -8)
	host.add_child(flames)
	var embers := _make_embers()
	embers.position = base + Vector2(0, -10)
	host.add_child(embers)


func _exit_tree() -> void:
	if _crackle != null:
		_crackle.stop()
		_crackle.stream = null


func _process(delta: float) -> void:
	_time += delta
	light.energy = 0.75 + sin(_time * 9.0) * 0.05 + sin(_time * 23.0) * 0.035 + sin(_time * 3.1) * 0.03
	light.texture_scale = 0.62 + sin(_time * 7.0) * 0.012
	chill.texture_scale = light.texture_scale
	chill.energy = 0.7 + (light.energy - 0.8) * 0.8

	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
		return
	var near := not _player.dead and _player.global_position.distance_to(global_position) < REST_RADIUS
	var healing := near and _player.health < Game.max_health()
	if healing != player_near:
		player_near = healing                 # true = man wird gerade geheilt
		rest_changed.emit(healing)
	if healing:
		_heal_t -= delta
		if _heal_t <= 0.0:
			_heal_t = HEAL_INTERVAL
			_player.heal(HEAL_AMOUNT)
	else:
		_heal_t = 0.4


func _make_flames() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = 40
	p.lifetime = 0.8
	p.preprocess = 0.8
	p.direction = Vector2.UP
	p.spread = 12.0
	p.gravity = Vector2(0, -44)
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 14.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 3.5
	p.scale_amount_min = 4.0
	p.scale_amount_max = 7.0
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.1))
	p.scale_amount_curve = shrink
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 0.75, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.95, 0.55, 1.0), Color(1.0, 0.68, 0.2, 0.95),
			Color(0.95, 0.3, 0.1, 0.7), Color(0.6, 0.12, 0.08, 0.0)])
	p.color_ramp = ramp
	return p


func _make_embers() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = 10
	p.lifetime = 2.6
	p.preprocess = 2.6
	p.direction = Vector2.UP
	p.spread = 26.0
	p.gravity = Vector2(5, -9)
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 24.0
	p.scale_amount_min = 1.4
	p.scale_amount_max = 2.2
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.85, 0.45, 1.0), Color(1.0, 0.55, 0.2, 0.8), Color(1.0, 0.3, 0.1, 0.0)])
	p.color_ramp = ramp
	return p
