extends Area2D
class_name Projectile
## Ein Geschoss: Schneeball (vom Schneemann) oder Eissplitter (vom Boss).
## Schneebälle kann man mit einem Schlag wegschlagen, Eissplitter nicht.

var velocity := Vector2.ZERO
var damage := 8
var swattable := true
var hit_radius := 5.0
var kind := "snowball"
var _life := 3.0

@onready var sprite: Sprite2D = $Sprite


func _ready() -> void:
	add_to_group("projectiles")
	body_entered.connect(_on_body_entered)


func launch(dir: Vector2, speed: float, dmg: int, projectile_kind := "snowball") -> void:
	kind = projectile_kind
	velocity = dir.normalized() * speed
	damage = dmg
	if kind == "shard":
		sprite.texture = load("res://art/shard.png")
		swattable = false
		hit_radius = 4.0
		sprite.rotation = velocity.angle() + PI * 0.5
		sprite.modulate = Color(2.0, 2.2, 2.5)             # Splitter leuchten: sie sind die wichtigste Gefahr
		_life = 3.2
	else:
		sprite.texture = load("res://art/snowball.png")
		sprite.modulate = Color(1.5, 1.5, 1.65)
		_life = 3.0


func _physics_process(delta: float) -> void:
	position += velocity * delta
	if kind == "snowball":
		sprite.rotation += delta * 5.0
	_life -= delta
	if _life <= 0.0:
		_pop(false)


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		(body as Player).take_hit(damage, global_position)
		_pop(true)
	elif body is StaticBody2D:
		_pop(false)


## Vom Spieler weggeschlagen.
func swat() -> void:
	Sound.play_at("tink", global_position)
	_burst()
	queue_free()


func _pop(_hit_player: bool) -> void:
	Sound.play_at("tink" if kind == "shard" else "snowball", global_position)
	_burst()
	queue_free()


func _burst() -> void:
	set_deferred("monitoring", false)
	var col := Color(0.62, 0.9, 1.0) if kind == "shard" else Color(0.92, 0.97, 1.0)
	Fx.burst(self, global_position + Vector2(0, -8), col, 8, 0.35, 45.0)
