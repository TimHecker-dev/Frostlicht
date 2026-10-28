extends CharacterBody2D
class_name Enemy
## Einfacher Gegner mit kleinem Verhaltens-Automaten:
## streunen -> verfolgen -> ausholen (Warnzeichen "!") -> Satz nach vorn -> kurze Erholung.
## Die Werte der Gegnerarten stehen in KINDS – dort kannst du neue Arten ergänzen.

signal died(enemy: Enemy)

enum State { IDLE, CHASE, WINDUP, LUNGE, RECOVER, HURT, DEAD }

const KINDS := {
	"blob": {
		"texture": "res://art/enemy_blob.png",
		"hp": 28, "damage": 9, "xp": 10,
		"speed": 34.0, "aggro": 110.0, "lose": 200.0,
		"reach": 22.0, "windup": 0.55, "lunge_speed": 150.0, "lunge_time": 0.16, "recover": 0.8,
		"hit_radius": 7.0, "knockback": 120.0, "shadow": 0.9, "style": "hop",
	},
	"wisp": {
		"texture": "res://art/enemy_wisp.png",
		"hp": 16, "damage": 6, "xp": 8,
		"speed": 52.0, "aggro": 130.0, "lose": 220.0,
		"reach": 26.0, "windup": 0.45, "lunge_speed": 190.0, "lunge_time": 0.18, "recover": 0.9,
		"hit_radius": 6.0, "knockback": 170.0, "shadow": 0.6, "style": "float",
	},
}

var kind := "blob"
var stats: Dictionary = {}
var hp := 20
var max_hp := 20
var damage := 8
var xp_reward := 10
var hit_radius := 7.0
var state: State = State.IDLE

var _target: Player
var _fire_pos := Vector2.ZERO
var _fire_radius := 0.0
var _timer := 0.0
var _knock := Vector2.ZERO
var _lunge_dir := Vector2.DOWN
var _lunge_hit := false
var _wander_timer := 0.0
var _wander_dir := Vector2.ZERO
var _side := 1.0
var _flash := 0.0
var _bar_timer := 0.0
var _time := 0.0
var _sprite_h := 20.0
var _phase := randf() * TAU

@onready var sprite: Sprite2D = $Sprite
@onready var shadow: Sprite2D = $Shadow
@onready var collision: CollisionShape2D = $Collision


## Wird direkt nach dem Hinzufügen zum Baum aufgerufen. Gegner werden mit der Stufe stärker.
func setup(kind_name: String, level: int, player: Player, fire_pos: Vector2, fire_radius: float) -> void:
	kind = kind_name
	stats = KINDS[kind]
	var growth := 1.0 + 0.12 * float(level - 1)
	max_hp = int(round(float(stats["hp"]) * growth))
	hp = max_hp
	damage = int(stats["damage"]) + int(float(level - 1) * 0.5)
	xp_reward = int(stats["xp"])
	hit_radius = float(stats["hit_radius"])
	_target = player
	_fire_pos = fire_pos
	_fire_radius = fire_radius
	_side = 1.0 if randf() < 0.5 else -1.0
	_wander_timer = randf_range(0.5, 2.0)

	var tex: Texture2D = load(stats["texture"])
	sprite.texture = tex
	_sprite_h = float(tex.get_height())
	sprite.offset = Vector2(0, -_sprite_h * 0.5 + 2.0)
	shadow.scale = Vector2.ONE * float(stats["shadow"])
	if kind == "wisp":                      # Schneegeister leuchten leicht bläulich
		var glow := PointLight2D.new()
		glow.texture = load("res://art/light.png")
		glow.color = Color(0.55, 0.78, 1.0)
		glow.energy = 0.5
		glow.texture_scale = 0.32
		glow.position = Vector2(0, -12)
		add_child(glow)
	add_to_group("enemies")


func is_dead() -> bool:
	return state == State.DEAD


## Ist der Gegner gerade hinter dem Spieler her (oder im Kampf)? Steuert die Gefahr-Ebene der Musik.
func is_hostile() -> bool:
	return state in [State.CHASE, State.WINDUP, State.LUNGE, State.RECOVER, State.HURT]


# --------------------------------------------------------------------- Verhalten
func _physics_process(delta: float) -> void:
	if state == State.DEAD or stats.is_empty():
		return
	_time += delta
	if _bar_timer > 0.0:
		_bar_timer = maxf(0.0, _bar_timer - delta)
		queue_redraw()
	_knock = _knock.move_toward(Vector2.ZERO, 500.0 * delta)

	var move := Vector2.ZERO
	match state:
		State.IDLE:
			move = _state_idle(delta)
		State.CHASE:
			move = _state_chase(delta)
		State.WINDUP:
			move = _state_windup(delta)
		State.LUNGE:
			move = _state_lunge(delta)
		State.RECOVER:
			move = _state_recover(delta)
		State.HURT:
			move = _state_hurt(delta)
	velocity = move + _knock
	move_and_slide()
	_animate(delta)


func _player_alive() -> bool:
	return _target != null and is_instance_valid(_target) and not _target.dead


func _player_safe() -> bool:
	# Am Lagerfeuer ist der Spieler sicher – Gegner scheuen das Feuer.
	return _target.global_position.distance_to(_fire_pos) < _fire_radius


func _can_see_player() -> bool:
	if not _player_alive() or _player_safe():
		return false
	return global_position.distance_to(_target.global_position) < float(stats["aggro"])


func _state_idle(delta: float) -> Vector2:
	if _can_see_player():
		state = State.CHASE
		return Vector2.ZERO
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(1.2, 3.0)
		_wander_dir = Vector2.from_angle(randf() * TAU) if randf() < 0.6 else Vector2.ZERO
	var v := _wander_dir * float(stats["speed"]) * 0.4
	var from_fire := global_position - _fire_pos
	if from_fire.length() < _fire_radius:        # raus aus dem Feuerschein
		v = from_fire.normalized() * float(stats["speed"]) * 0.9
	return v


func _state_chase(_delta: float) -> Vector2:
	if not _player_alive() or _player_safe() \
			or global_position.distance_to(_target.global_position) > float(stats["lose"]):
		state = State.IDLE
		return Vector2.ZERO
	var to_p := _target.global_position - global_position
	var dist := to_p.length()
	if dist < float(stats["reach"]):
		_start_windup(to_p)
		return Vector2.ZERO
	var dir := to_p / maxf(dist, 0.001)
	if get_slide_collision_count() > 0:          # Hindernis? seitlich ausweichen
		dir = (dir + dir.orthogonal() * _side * 0.9).normalized()
		if randf() < 0.02:
			_side = -_side
	return dir * float(stats["speed"])


func _start_windup(to_p: Vector2) -> void:
	state = State.WINDUP
	_timer = float(stats["windup"])
	_lunge_dir = to_p.normalized() if to_p.length() > 0.01 else Vector2.DOWN
	Fx.text(self, global_position + Vector2(0, -_sprite_h - 8.0), "!", Color(1.0, 0.85, 0.3), 28, 0.45)
	Sound.play_at("alert", global_position)


func _state_windup(delta: float) -> Vector2:
	_timer -= delta
	if _player_alive():                          # zielt noch ein bisschen nach
		var to_p := _target.global_position - global_position
		if to_p.length() > 1.0:
			_lunge_dir = _lunge_dir.slerp(to_p.normalized(), minf(1.0, delta * 3.0))
	if _timer <= 0.0:
		state = State.LUNGE
		_timer = float(stats["lunge_time"])
		_lunge_hit = false
		Sound.play_at("lunge", global_position)
	return Vector2.ZERO


func _state_lunge(delta: float) -> Vector2:
	_timer -= delta
	if not _lunge_hit and _player_alive():
		if _target.global_position.distance_to(global_position) < hit_radius + 9.0:
			_lunge_hit = true
			_target.take_hit(damage, global_position)
	if _timer <= 0.0:
		state = State.RECOVER
		_timer = float(stats["recover"])
	return _lunge_dir * float(stats["lunge_speed"])


func _state_recover(delta: float) -> Vector2:
	_timer -= delta
	if _timer <= 0.0:
		state = State.CHASE if _can_see_player() else State.IDLE
	return Vector2.ZERO


func _state_hurt(delta: float) -> Vector2:
	_timer -= delta
	if _timer <= 0.0:
		state = State.CHASE if _player_alive() else State.IDLE
	return Vector2.ZERO


# --------------------------------------------------------------------- Treffer & Tod
func take_hit(amount: int, dir: Vector2) -> void:
	if state == State.DEAD:
		return
	hp -= amount
	Sound.play_at("hit", global_position, -4.0 if hp <= 0 else 0.0)
	_bar_timer = 2.5
	_flash = 0.12
	_knock = dir.normalized() * float(stats["knockback"])
	Fx.text(self, global_position + Vector2(0, -_sprite_h - 2.0), str(amount), Color.WHITE, 22)
	Fx.burst(self, global_position + Vector2(0, -_sprite_h * 0.5), Color(0.85, 0.95, 1.0), 6, 0.3, 50.0)
	if hp <= 0:
		_die()
		return
	state = State.HURT                           # unterbricht auch einen Angriff
	_timer = 0.25
	queue_redraw()


func _die() -> void:
	state = State.DEAD
	Sound.play_at("enemy_die", global_position)
	remove_from_group("enemies")
	collision.set_deferred("disabled", true)
	Game.add_xp(xp_reward)
	Fx.text(self, global_position + Vector2(0, -_sprite_h - 12.0), "+%d EP" % xp_reward,
			Color(1.0, 0.86, 0.42), 20, 1.0)
	Fx.burst(self, global_position + Vector2(0, -_sprite_h * 0.5), Color(0.8, 0.93, 1.0), 18, 0.6, 80.0)
	died.emit(self)
	queue_redraw()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(sprite, "scale", Vector2(1.5, 0.2), 0.25)
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(queue_free)


# --------------------------------------------------------------------- Optik
func _animate(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	var lift := 0.0
	var scl := Vector2.ONE
	if String(stats["style"]) == "hop":
		if velocity.length() > 8.0:
			var h := absf(sin(_time * 7.0 + _phase))
			lift = h * 3.5
			scl = Vector2(1.0 - h * 0.06, 1.0 + h * 0.10)
		else:
			var b := sin(_time * 2.0 + _phase) * 0.05
			scl = Vector2(1.0 + b, 1.0 - b)
	else:
		lift = 6.0 + sin(_time * 3.0 + _phase) * 2.0
		var b2 := sin(_time * 4.0 + _phase) * 0.04
		scl = Vector2(1.0 - b2, 1.0 + b2)
		sprite.rotation = clampf(velocity.x / 220.0, -0.25, 0.25)

	var tint := Color.WHITE
	if state == State.WINDUP:
		var k := 1.0 - clampf(_timer / float(stats["windup"]), 0.0, 1.0)
		scl = Vector2(1.0 + 0.25 * k, 1.0 - 0.25 * k)
		tint = Color.WHITE.lerp(Color(1.7, 1.25, 0.8), k)
	elif state == State.LUNGE:
		scl = Vector2(0.85, 1.25)
	if _flash > 0.0:
		tint = Color(2.4, 2.4, 2.4)
	sprite.modulate = tint
	sprite.scale = scl
	sprite.position.y = -lift
	shadow.scale = Vector2.ONE * float(stats["shadow"]) * (1.0 - lift * 0.025)


func _draw() -> void:
	if state == State.DEAD or _bar_timer <= 0.0 or stats.is_empty():
		return
	var w := 20.0
	var y := -_sprite_h - 4.0 - (6.0 if String(stats["style"]) == "float" else 0.0)
	draw_rect(Rect2(-w * 0.5 - 1.0, y - 1.0, w + 2.0, 5.0), Color(0.08, 0.1, 0.18, 0.85))
	var frac := clampf(float(hp) / float(max_hp), 0.0, 1.0)
	draw_rect(Rect2(-w * 0.5, y, w * frac, 3.0), Color(0.92, 0.38, 0.38))
