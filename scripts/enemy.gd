extends CharacterBody2D
class_name Enemy
## Gegner mit kleinem Verhaltens-Automaten. Jede Art in KINDS hat ein "behavior":
##   lunge  - Frostblob, Schneegeist: heranlaufen, ausholen (gelbes "!"), Satz nach vorn
##   pounce - Frostfuchs: umkreist dich, springt blitzschnell zu und huscht danach kurz zurück
##   ranged - Schneemann: hält Abstand und wirft langsame Schneebälle (mit einem Schlag wegzuschlagen)
##   roller - Eisigel: rollt sich zusammen und rast los; im Ball hält er viel aus, danach ist er benommen
## Neue Art: Eintrag in KINDS ergänzen, Bild unter art/ ablegen, in world.gd (KIND_TABLE) einplanen.

signal died(enemy: Enemy)

enum State { IDLE, CHASE, WINDUP, LUNGE, RECOVER, HURT, DEAD, STRAFE, ROLL, DIZZY }

const PROJECTILE_SCENE := "res://scenes/projectile.tscn"

const KINDS := {
	"blob": {
		"texture": "res://art/enemy_blob.png", "behavior": "lunge",
		"hp": 28, "damage": 9, "xp": 10,
		"speed": 34.0, "aggro": 110.0, "lose": 200.0,
		"reach": 22.0, "windup": 0.55, "lunge_speed": 150.0, "lunge_time": 0.16, "recover": 0.8,
		"hit_radius": 7.0, "knockback": 120.0, "shadow": 0.9, "style": "hop",
	},
	"wisp": {
		"texture": "res://art/enemy_wisp.png", "behavior": "lunge",
		"hp": 16, "damage": 6, "xp": 8,
		"speed": 52.0, "aggro": 130.0, "lose": 220.0,
		"reach": 26.0, "windup": 0.45, "lunge_speed": 190.0, "lunge_time": 0.18, "recover": 0.9,
		"hit_radius": 6.0, "knockback": 170.0, "shadow": 0.6, "style": "float",
	},
	"fox": {
		"texture": "res://art/enemy_fox.png", "behavior": "pounce", "flip": true,
		"hp": 22, "damage": 7, "xp": 12,
		"speed": 74.0, "aggro": 150.0, "lose": 250.0,
		"strafe_radius": 56.0, "windup": 0.34, "lunge_speed": 270.0, "lunge_time": 0.2, "recover": 0.55,
		"hit_radius": 6.0, "knockback": 150.0, "shadow": 0.75, "style": "run", "lunge_sound": "pounce",
	},
	"snowman": {
		"texture": "res://art/enemy_snowman.png", "behavior": "ranged",
		"hp": 36, "damage": 9, "xp": 16,
		"speed": 26.0, "aggro": 160.0, "lose": 260.0,
		"throw_range": 135.0, "keep_away": 64.0, "throw_cooldown": 2.3, "windup": 0.7, "recover": 0.6,
		"projectile_speed": 105.0,
		"hit_radius": 8.0, "knockback": 70.0, "shadow": 1.0, "style": "wobble",
	},
	"hedgehog": {
		"texture": "res://art/enemy_hedgehog.png", "behavior": "roller", "flip": true, "frames": 2,
		"hp": 30, "damage": 11, "xp": 14,
		"speed": 40.0, "aggro": 125.0, "lose": 230.0,
		"roll_trigger": 120.0, "windup": 0.8, "roll_speed": 215.0, "roll_time": 0.9, "dizzy": 1.4, "roll_cooldown": 2.0,
		"hit_radius": 7.0, "knockback": 100.0, "shadow": 0.9, "style": "waddle", "lunge_sound": "roll",
	},
}

var kind := "blob"
var behavior := "lunge"
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
var _strafe_dir := 1.0
var _throw_cd := 0.0
var _roll_cd := 0.0
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
	behavior = String(stats.get("behavior", "lunge"))
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
	_throw_cd = randf_range(0.8, 1.6)

	var tex: Texture2D = load(stats["texture"])
	sprite.texture = tex
	sprite.hframes = int(stats.get("frames", 1))
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


## Ist der Gegner im Kampf (nicht gemütlich am Streunen)? Steuert die Gefahr-Ebene der Musik.
func is_hostile() -> bool:
	return state != State.IDLE and state != State.DEAD


# --------------------------------------------------------------------- Verhalten
func _physics_process(delta: float) -> void:
	if state == State.DEAD or stats.is_empty():
		return
	_time += delta
	if _bar_timer > 0.0:
		_bar_timer = maxf(0.0, _bar_timer - delta)
		queue_redraw()
	_knock = _knock.move_toward(Vector2.ZERO, 500.0 * delta)
	_throw_cd = maxf(0.0, _throw_cd - delta)
	_roll_cd = maxf(0.0, _roll_cd - delta)

	var move := Vector2.ZERO
	match state:
		State.IDLE:
			move = _state_idle(delta)
		State.CHASE:
			move = _state_chase(delta)
		State.STRAFE:
			move = _state_strafe(delta)
		State.WINDUP:
			move = _state_windup(delta)
		State.LUNGE:
			move = _state_lunge(delta)
		State.ROLL:
			move = _state_roll(delta)
		State.RECOVER:
			move = _state_recover(delta)
		State.DIZZY:
			move = _state_dizzy(delta)
		State.HURT:
			move = _state_hurt(delta)
	velocity = move + _knock
	move_and_slide()
	_animate(delta)


func _player_alive() -> bool:
	return _target != null and is_instance_valid(_target) and not _target.dead


func _player_safe() -> bool:
	# Am Lagerfeuer ist der Spieler sicher - Gegner scheuen das Feuer.
	return _target.global_position.distance_to(_fire_pos) < _fire_radius


func _can_see_player() -> bool:
	if not _player_alive() or _player_safe():
		return false
	return global_position.distance_to(_target.global_position) < float(stats["aggro"])


func _lost_target() -> bool:
	return not _player_alive() or _player_safe() \
			or global_position.distance_to(_target.global_position) > float(stats["lose"])


func _steer(dir: Vector2, speed: float) -> Vector2:
	if get_slide_collision_count() > 0:          # Hindernis? seitlich ausweichen
		dir = (dir + dir.orthogonal() * _side * 0.9).normalized()
		if randf() < 0.02:
			_side = -_side
	return dir * speed


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
	if _lost_target():
		state = State.IDLE
		return Vector2.ZERO
	var to_p := _target.global_position - global_position
	var dist := to_p.length()
	var dir := to_p / maxf(dist, 0.001)
	var speed := float(stats["speed"])
	match behavior:
		"pounce":
			if dist < float(stats["strafe_radius"]) * 1.4:
				_enter_strafe()
				return Vector2.ZERO
		"ranged":
			return _chase_ranged(to_p, dist, dir, speed)
		"roller":
			if dist < float(stats["roll_trigger"]) and _roll_cd <= 0.0:
				_start_windup(to_p)
				return Vector2.ZERO
		_:
			if dist < float(stats["reach"]):
				_start_windup(to_p)
				return Vector2.ZERO
	return _steer(dir, speed)


## Schneemann: wirft aus der Ferne, weicht zurück, wenn man ihm zu nah kommt.
func _chase_ranged(to_p: Vector2, dist: float, dir: Vector2, speed: float) -> Vector2:
	var throw_range := float(stats["throw_range"])
	if dist <= throw_range and dist > 24.0 and _throw_cd <= 0.0:
		_start_windup(to_p)
		return Vector2.ZERO
	if dist > throw_range * 0.9:
		return _steer(dir, speed)
	if dist < float(stats["keep_away"]):
		return -dir * speed * 0.9
	return dir.orthogonal() * _side * speed * 0.35        # gemütlich seitwärts schlurfen


## Fuchs: umkreist den Spieler, bis er zuspringt.
func _enter_strafe() -> void:
	state = State.STRAFE
	_timer = randf_range(0.9, 1.8)
	_strafe_dir = 1.0 if randf() < 0.5 else -1.0


func _state_strafe(delta: float) -> Vector2:
	if _lost_target():
		state = State.IDLE
		return Vector2.ZERO
	var to_p := _target.global_position - global_position
	var dist := to_p.length()
	var dir := to_p / maxf(dist, 0.001)
	var radius := float(stats["strafe_radius"])
	_timer -= delta
	if _timer <= 0.0:
		if dist < radius * 1.8:
			_start_windup(to_p)
		else:
			state = State.CHASE
		return Vector2.ZERO
	if get_slide_collision_count() > 0:
		_strafe_dir = -_strafe_dir
	var tangent := dir.orthogonal() * _strafe_dir
	var radial := dir * clampf((dist - radius) * 0.08, -1.0, 1.0)
	return (tangent + radial).normalized() * float(stats["speed"]) * 0.85


func _start_windup(to_p: Vector2) -> void:
	state = State.WINDUP
	_timer = float(stats["windup"])
	_lunge_dir = to_p.normalized() if to_p.length() > 0.01 else Vector2.DOWN
	Fx.text(self, global_position + Vector2(0, -_sprite_h - 8.0), "!", Color(1.0, 0.85, 0.3), 28, 0.45)
	Sound.play_at("alert", global_position)


func _state_windup(delta: float) -> Vector2:
	_timer -= delta
	if _player_alive() and behavior != "roller":           # zielt noch ein bisschen nach (Igel nicht)
		var to_p := _target.global_position - global_position
		if to_p.length() > 1.0:
			_lunge_dir = _lunge_dir.slerp(to_p.normalized(), minf(1.0, delta * 3.0))
	if _timer <= 0.0:
		_finish_windup()
	return Vector2.ZERO


func _finish_windup() -> void:
	match behavior:
		"ranged":
			_throw()
		"roller":
			state = State.ROLL
			_timer = float(stats["roll_time"])
			_lunge_hit = false
			Sound.play_at(String(stats.get("lunge_sound", "lunge")), global_position)
		_:
			state = State.LUNGE
			_timer = float(stats["lunge_time"])
			_lunge_hit = false
			Sound.play_at(String(stats.get("lunge_sound", "lunge")), global_position)


func _throw() -> void:
	var scene: PackedScene = load(PROJECTILE_SCENE)
	var pr: Projectile = scene.instantiate()
	pr.position = global_position + _lunge_dir * 8.0
	get_parent().add_child(pr)
	pr.launch(_lunge_dir, float(stats["projectile_speed"]), damage, "snowball")
	_throw_cd = float(stats["throw_cooldown"])
	Sound.play_at("throw", global_position)
	state = State.RECOVER
	_timer = float(stats["recover"])


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


## Igel: rast geradeaus, bis er an etwas stößt oder die Zeit um ist.
func _state_roll(delta: float) -> Vector2:
	_timer -= delta
	if not _lunge_hit and _player_alive():
		if _target.global_position.distance_to(global_position) < hit_radius + 9.0:
			_lunge_hit = true
			_target.take_hit(damage, global_position)
	var bonked := false
	for i in get_slide_collision_count():
		if get_slide_collision(i).get_collider() is StaticBody2D:
			bonked = true
	if bonked or _timer <= 0.0:
		state = State.DIZZY
		_timer = float(stats["dizzy"]) * (1.25 if bonked else 1.0)
		_roll_cd = float(stats["roll_cooldown"])
		if bonked:
			Sound.play_at("snowball", global_position)
			Fx.text(self, global_position + Vector2(0, -_sprite_h - 6.0), "*", Color(1.0, 0.9, 0.5), 26, 0.9)
		return Vector2.ZERO
	return _lunge_dir * float(stats["roll_speed"])


func _state_recover(delta: float) -> Vector2:
	_timer -= delta
	var v := Vector2.ZERO
	if behavior == "pounce" and _timer > float(stats["recover"]) - 0.3:
		v = -_lunge_dir * float(stats["speed"]) * 1.1        # Fuchs huscht kurz zurück
	if _timer <= 0.0:
		if not _can_see_player():
			state = State.IDLE
		elif behavior == "pounce":
			_enter_strafe()
		else:
			state = State.CHASE
	return v


func _state_dizzy(delta: float) -> Vector2:
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
	var armored := state == State.ROLL                       # im Ball: Stacheln wehren ab
	if armored:
		amount = maxi(1, int(round(float(amount) * 0.4)))
		Sound.play_at("tink", global_position)
	elif state == State.DIZZY:
		amount = int(round(float(amount) * 1.6))             # benommen: trifft besonders gut
	hp -= amount
	if not armored:
		Sound.play_at("hit", global_position, -4.0 if hp <= 0 else 0.0)
	_bar_timer = 2.5
	_flash = 0.12
	Fx.text(self, global_position + Vector2(0, -_sprite_h - 2.0), str(amount), Color.WHITE, 22)
	Fx.burst(self, global_position + Vector2(0, -_sprite_h * 0.5), Color(0.85, 0.95, 1.0), 6, 0.3, 50.0)
	if hp <= 0:
		_die()
		return
	if armored:
		queue_redraw()
		return                                               # kein Rückstoß, keine Unterbrechung
	_knock = dir.normalized() * float(stats["knockback"])
	if state != State.DIZZY:
		state = State.HURT                                   # unterbricht auch einen Angriff
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
	var style := String(stats["style"])
	var moving := velocity.length() > 8.0
	var lift := 0.0
	var scl := Vector2.ONE
	var rot := 0.0
	match style:
		"hop":
			if moving:
				var h := absf(sin(_time * 7.0 + _phase))
				lift = h * 3.5
				scl = Vector2(1.0 - h * 0.06, 1.0 + h * 0.10)
			else:
				var b := sin(_time * 2.0 + _phase) * 0.05
				scl = Vector2(1.0 + b, 1.0 - b)
		"float":
			lift = 6.0 + sin(_time * 3.0 + _phase) * 2.0
			var b2 := sin(_time * 4.0 + _phase) * 0.04
			scl = Vector2(1.0 - b2, 1.0 + b2)
			rot = clampf(velocity.x / 220.0, -0.25, 0.25)
		"run":
			if moving:
				lift = absf(sin(_time * 16.0 + _phase)) * 1.6
				scl = Vector2(1.04, 0.96)
			else:
				var b3 := sin(_time * 3.0 + _phase) * 0.03
				scl = Vector2(1.0 + b3, 1.0 - b3)
		"wobble":
			if moving:
				rot = sin(_time * 5.0 + _phase) * 0.06
			else:
				var b4 := sin(_time * 1.8 + _phase) * 0.02
				scl = Vector2(1.0 - b4, 1.0 + b4)
		"waddle":
			if moving:
				lift = absf(sin(_time * 8.0 + _phase)) * 1.2
				rot = sin(_time * 8.0 + _phase) * 0.07

	var tint := Color.WHITE
	match state:
		State.WINDUP:
			var k := 1.0 - clampf(_timer / float(stats["windup"]), 0.0, 1.0)
			tint = Color.WHITE.lerp(Color(1.7, 1.25, 0.8), k)
			match behavior:
				"pounce":
					scl = Vector2(1.0 + 0.3 * k, 1.0 - 0.3 * k)             # duckt sich zum Sprung
				"ranged":
					scl = Vector2(1.0 - 0.1 * k, 1.0 + 0.15 * k)            # reckt sich zum Wurf
				"roller":
					rot = sin(_time * 40.0) * 0.12 * k                      # zittert beim Zusammenrollen
				_:
					scl = Vector2(1.0 + 0.25 * k, 1.0 - 0.25 * k)
		State.LUNGE:
			scl = Vector2(1.2, 0.8) if behavior == "pounce" else Vector2(0.85, 1.25)
		State.ROLL:
			rot = sprite.rotation + delta * 18.0 * (1.0 if _lunge_dir.x >= 0.0 else -1.0)
			tint = Color(0.9, 1.0, 1.15)
		State.DIZZY:
			rot = sin(_time * 9.0) * 0.28
			tint = Color(1.05, 1.05, 1.25)
	if _flash > 0.0:
		tint = Color(2.4, 2.4, 2.4)
	sprite.modulate = tint
	sprite.scale = scl
	sprite.position.y = -lift
	sprite.rotation = rot
	sprite.frame = 1 if (behavior == "roller" and (state == State.WINDUP or state == State.ROLL)) else 0
	if bool(stats.get("flip", false)):                                    # Bilder schauen nach rechts
		var fx := _lunge_dir.x if state == State.WINDUP else velocity.x
		if absf(fx) > 4.0:
			sprite.flip_h = fx < 0.0
	shadow.scale = Vector2.ONE * float(stats["shadow"]) * (1.0 - lift * 0.025)


func _draw() -> void:
	if state == State.DEAD or _bar_timer <= 0.0 or stats.is_empty():
		return
	var w := 20.0
	var y := -_sprite_h - 4.0 - (6.0 if String(stats["style"]) == "float" else 0.0)
	draw_rect(Rect2(-w * 0.5 - 1.0, y - 1.0, w + 2.0, 5.0), Color(0.08, 0.1, 0.18, 0.85))
	var frac := clampf(float(hp) / float(max_hp), 0.0, 1.0)
	draw_rect(Rect2(-w * 0.5, y, w * frac, 3.0), Color(0.92, 0.38, 0.38))
