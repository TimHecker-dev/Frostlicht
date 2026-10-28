extends CharacterBody2D
class_name Player
## Die Spielfigur: bewegen, zuschlagen, Schaden nehmen.
## Ein Schlag trifft alle Gegner in einem Kegel vor dir (Reichweite und Winkel stehen unten).

signal died
signal health_changed(current: int, maximum: int)
signal stepped(pos: Vector2, dir: Vector2, side: float)

const SPEED := 90.0
const ACCEL := 820.0
const FRICTION := 1100.0
const KNOCKBACK_DECAY := 700.0

const ATTACK_TIME := 0.36          # Dauer eines Schlags in Sekunden
const ATTACK_HIT_AT := 0.10        # so lange nach Beginn zählt der Treffer
const ATTACK_REACH := 26.0         # Reichweite in Pixeln (plus Größe des Gegners)
const ATTACK_ARC_DEG := 140.0      # Öffnungswinkel des Schlags
const ATTACK_MOVE_FACTOR := 0.35   # Lauftempo während des Schlags
const INVULN_TIME := 0.8           # Schonzeit nach einem Treffer
const STEP_LENGTH := 13.0          # Abstand zwischen zwei Fußspuren

var health: int = 50
var aim := Vector2.DOWN            # Blick- und Schlagrichtung
var dead := false

var _move_vel := Vector2.ZERO
var _knockback := Vector2.ZERO
var _attack_t := 0.0
var _attack_hit_done := true
var _buffered := 0.0
var _invuln := 0.0
var _walk_phase := 0.0
var _step_dist := 0.0
var _step_side := 1.0
var _step_count := 0
var _shake := 0.0
var _time := 0.0
var _last_max := 50
var _death_tween: Tween

@onready var sprite: Sprite2D = $Sprite
@onready var camera: Camera2D = $Camera2D
@onready var light: PointLight2D = $Light


func _ready() -> void:
	camera.zoom = Vector2.ONE * Game.WORLD_ZOOM
	_last_max = Game.max_health()
	health = _last_max
	Game.stats_changed.connect(_on_stats_changed)
	Game.level_up.connect(_on_level_up)


func set_world_bounds(r: Rect2) -> void:
	camera.limit_left = int(r.position.x)
	camera.limit_top = int(r.position.y)
	camera.limit_right = int(r.end.x)
	camera.limit_bottom = int(r.end.y)


# --------------------------------------------------------------------- Eingabe
func _unhandled_input(event: InputEvent) -> void:
	if dead or not event.is_action_pressed("attack"):
		return
	if event is InputEventMouseButton and _attack_t <= 0.0:
		var to_mouse := get_global_mouse_position() - (global_position + Vector2(0, -8))
		if to_mouse.length() > 6.0:
			aim = to_mouse.normalized()
	if _attack_t > 0.0:
		_buffered = 0.2          # Druck kurz vor Schlagende wird vorgemerkt
	else:
		_begin_attack()


# --------------------------------------------------------------------- Physik
func _physics_process(delta: float) -> void:
	_invuln = maxf(0.0, _invuln - delta)
	_buffered = maxf(0.0, _buffered - delta)
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)

	if dead:
		_move_vel = Vector2.ZERO
		velocity = _knockback
		move_and_slide()
		return

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var attacking := _attack_t > 0.0
	var top_speed := SPEED * (ATTACK_MOVE_FACTOR if attacking else 1.0)
	if input != Vector2.ZERO:
		_move_vel = _move_vel.move_toward(input * top_speed, ACCEL * delta)
		if not attacking:
			aim = input.normalized()
	else:
		_move_vel = _move_vel.move_toward(Vector2.ZERO, FRICTION * delta)

	velocity = _move_vel + _knockback
	var before := global_position
	move_and_slide()

	_update_attack(delta)
	_update_footsteps(global_position.distance_to(before))
	_animate(delta)


func _process(delta: float) -> void:
	_time += delta
	_shake = move_toward(_shake, 0.0, delta * 14.0)
	if _shake > 0.0:
		camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
	else:
		camera.offset = Vector2.ZERO
	# Laterne flackert ganz leicht
	light.energy = 0.30 + sin(_time * 6.3) * 0.015 + sin(_time * 14.1) * 0.01
	if dead:
		return
	if _invuln > 0.0 and int(_invuln * 22.0) % 2 == 0:
		sprite.modulate.a = 0.35
	else:
		sprite.modulate.a = 1.0


# --------------------------------------------------------------------- Angriff
func _begin_attack() -> void:
	_attack_t = ATTACK_TIME
	_attack_hit_done = false
	_move_vel += aim * 60.0                     # kleiner Satz nach vorn
	Sound.play("swing")
	Fx.slash(self, global_position + Vector2(0, -8), aim.angle())


func _update_attack(delta: float) -> void:
	if _attack_t <= 0.0:
		return
	_attack_t -= delta
	if not _attack_hit_done and ATTACK_TIME - _attack_t >= ATTACK_HIT_AT:
		_attack_hit_done = true
		_deal_damage()
	if _attack_t <= 0.0:
		_attack_t = 0.0
		if _buffered > 0.0:
			_buffered = 0.0
			_begin_attack()


func _deal_damage() -> void:
	var origin := global_position + Vector2(0, -6)
	var cos_half := cos(deg_to_rad(ATTACK_ARC_DEG * 0.5))
	var hits := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e.is_dead():
			continue
		var to_e := (e.global_position + Vector2(0, -6)) - origin
		var dist := to_e.length()
		if dist > ATTACK_REACH + e.hit_radius:
			continue
		if dist > 3.0 and aim.dot(to_e / dist) < cos_half:
			continue
		var dmg := maxi(1, Game.attack_damage() + randi_range(-1, 1))
		e.take_hit(dmg, aim)
		hits += 1
	if hits > 0:
		_shake = maxf(_shake, 1.2)
		Game.hit_stop(0.045)


# --------------------------------------------------------------------- Leben
func take_hit(amount: int, from_pos: Vector2) -> void:
	if dead or _invuln > 0.0:
		return
	var dmg := maxi(1, amount - Game.defence())     # Verteidigung zieht flach ab
	health = maxi(0, health - dmg)
	_invuln = INVULN_TIME
	var away := global_position - from_pos
	_knockback = (away.normalized() if away.length() > 0.1 else -aim) * 140.0
	_shake = 3.0
	Fx.text(self, global_position + Vector2(0, -30), str(dmg), Color(1.0, 0.46, 0.42), 22)
	health_changed.emit(health, Game.max_health())
	if health <= 0:
		_die()
	else:
		Sound.play("hurt")
		Game.hit_stop(0.06)


func heal(amount: int) -> void:
	var maximum := Game.max_health()
	if dead or health >= maximum:
		return
	var before := health
	health = mini(maximum, health + amount)
	Fx.text(self, global_position + Vector2(0, -30), "+%d" % (health - before),
			Color(0.6, 1.0, 0.7), 18, 0.7)
	Sound.play("heal")
	health_changed.emit(health, maximum)


func _die() -> void:
	dead = true
	_attack_t = 0.0
	_buffered = 0.0
	Sound.play("death")
	died.emit()
	_death_tween = create_tween()
	_death_tween.tween_property(sprite, "rotation", PI * 0.5, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func respawn(at: Vector2) -> void:
	if _death_tween != null:
		_death_tween.kill()
	dead = false
	global_position = at
	sprite.rotation = 0.0
	sprite.modulate.a = 1.0
	_move_vel = Vector2.ZERO
	_knockback = Vector2.ZERO
	_last_max = Game.max_health()
	health = _last_max
	_invuln = 2.0
	Sound.play("respawn")
	health_changed.emit(health, _last_max)


func _on_stats_changed() -> void:
	var new_max := Game.max_health()
	if new_max > _last_max:
		health += new_max - _last_max       # neues Max-Leben gibt es sofort dazu
	health = mini(health, new_max)
	_last_max = new_max
	health_changed.emit(health, new_max)


func _on_level_up(new_level: int) -> void:
	health = Game.max_health()
	health_changed.emit(health, health)
	Fx.text(self, global_position + Vector2(0, -38), "Stufe %d!" % new_level, Color(1.0, 0.86, 0.42), 28, 1.1)
	Fx.burst(self, global_position + Vector2(0, -10), Color(1.0, 0.9, 0.55), 24, 0.8, 80.0)


# --------------------------------------------------------------------- Optik
func _update_footsteps(moved: float) -> void:
	if moved < 0.01 or _move_vel.length() < 10.0:
		return
	_step_dist += moved
	if _step_dist >= STEP_LENGTH:
		_step_dist = 0.0
		_step_side = -_step_side
		stepped.emit(global_position, _move_vel.normalized(), _step_side)
		_step_count += 1
		if _step_count % 3 == 0:                 # nicht jede Fußspur ein Geräusch
			Sound.play("step")


func _animate(delta: float) -> void:
	# Blickrichtung -> Bild (0 = vorn, 1 = hinten, 2 = seitlich)
	if absf(aim.x) > absf(aim.y):
		sprite.frame = 2
		sprite.flip_h = aim.x < 0.0
	elif aim.y < 0.0:
		sprite.frame = 1
		sprite.flip_h = false
	else:
		sprite.frame = 0
		sprite.flip_h = false

	var ratio := _move_vel.length() / SPEED
	if ratio > 0.1:
		_walk_phase += delta * (9.0 + 6.0 * ratio)
		sprite.position.y = -absf(sin(_walk_phase)) * 1.8      # Hüpfen beim Laufen
		sprite.rotation = sin(_walk_phase) * 0.07
		sprite.scale = Vector2.ONE
	else:
		sprite.position.y = lerpf(sprite.position.y, 0.0, minf(1.0, delta * 12.0))
		sprite.rotation = lerpf(sprite.rotation, 0.0, minf(1.0, delta * 12.0))
		var breathe := sin(_time * 2.2) * 0.02                  # ruhiges Atmen
		sprite.scale = Vector2(1.0 - breathe, 1.0 + breathe)
	if _attack_t > ATTACK_TIME * 0.5:
		sprite.scale = Vector2(1.1, 0.92)                       # kurz zusammenducken beim Schlag
