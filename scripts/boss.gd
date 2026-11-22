extends Enemy
class_name Boss
## Endgegner "Der Winterschläfer": ein riesiger Bär, den du aus dem Winterschlaf geholt hast.
## Er schläft, bis du ihm zu nahe kommst oder ihn weckst. Drei Angriffe, jeder mit deutlicher Warnung:
##   Pranken-Hieb   - roter Kegel vor ihm (nach der Warnung ausweichen oder aus dem Kegel laufen)
##   Sprung         - roter Kreis am Boden zeigt, wo er landet (in der Luft ist er unverwundbar)
##   Eissplitter    - ein Ring aus Splittern; in den Lücken stehen bleiben oder dahinter in Deckung gehen
## Unter der Hälfte seines Lebens wird er wütend: schneller, kürzere Pausen, doppelte Splitter-Welle
## und zwei Frostblobs kommen dazu. Nach dem Sieg schläft er wieder ein.
## Alle Zahlen zum Ausbalancieren stehen direkt unten.

signal woke
signal phase_changed(phase: int)
signal health_changed(current: int, maximum: int)
signal adds_requested(count: int)

enum BS { SLEEP, WAKING, WALK, SWIPE_WIND, SWIPE, SLAM_WIND, SLAM_AIR, RECOVER, ROAR, SHARDS, DYING, DEAD }

const BOSS_NAME := "Der Winterschläfer"
const BASE_HEALTH := 320           # wächst mit deiner Stufe (+8 % je Stufe)
const WAKE_RADIUS := 125.0         # so nah darfst du dem schlafenden Bären kommen
const WALK_SPEED := 30.0
const SWIPE_RANGE := 60.0
const SWIPE_ARC_DEG := 130.0
const SWIPE_TIME := 0.95           # Warnzeit vor dem Hieb
const SLAM_TIME := 0.85            # Warnzeit vor dem Sprung
const SLAM_AIR_TIME := 0.5
const SLAM_RADIUS := 46.0
const SHARD_TIME := 0.8
const SHARDS_PER_WAVE := 10
const SHARD_SPEED := 92.0
const DMG_SWIPE := 15
const DMG_SLAM := 19
const DMG_SHARD := 9
const TEX_SLEEP := "res://art/boss_sleep.png"
const TEX_AWAKE := "res://art/boss.png"

var bs: BS = BS.SLEEP
var phase := 1
var max_health := BASE_HEALTH
var health := BASE_HEALTH
var arena_rect := Rect2(60, 60, 640, 440)    # hier landet er höchstens (von der Arena gesetzt)

var _t := 0.0
var _total := 1.0
var _cd := 1.0
var _last := ""
var _face := Vector2.DOWN
var _swipe_dir := Vector2.DOWN
var _slam_from := Vector2.ZERO
var _slam_to := Vector2.ZERO
var _wave := -1.0
var _telegraph := 0.0
var _waves_left := 0
var _shard_off := 0.0
var _step_t := 0.0
var _zzz_t := 2.0
var _bonus := 0
var _bflash := 0.0

@onready var glow: PointLight2D = $Light
@onready var chill: PointLight2D = $Chill          # zieht Blau ab: sein Fell bleibt in der kalten Höhle warm-braun


func setup_boss(player: Player, level: int) -> void:
	_target = player
	stats = {"style": "boss"}
	max_health = int(round(float(BASE_HEALTH) * (1.0 + 0.08 * float(level - 1))))
	health = max_health
	hp = health
	max_hp = max_health
	hit_radius = 17.0
	xp_reward = 120
	_bonus = int(float(level - 1) * 0.5)
	damage = DMG_SWIPE + _bonus
	var tex: Texture2D = load(TEX_SLEEP)
	sprite.texture = tex
	sprite.hframes = 1
	sprite.offset = Vector2(0, -float(tex.get_height()) * 0.5 + 2.0)
	shadow.scale = Vector2.ONE * 2.2
	glow.energy = 0.0
	chill.energy = 0.0
	add_to_group("enemies")


## Nach dem Sieg (oder wenn er schon besiegt war): friedlich schlafender Bär, kein Gegner mehr.
func set_defeated() -> void:
	bs = BS.DEAD
	remove_from_group("enemies")
	collision.set_deferred("disabled", true)
	var tex: Texture2D = load(TEX_SLEEP)
	sprite.texture = tex
	sprite.hframes = 1
	sprite.offset = Vector2(0, -float(tex.get_height()) * 0.5 + 2.0)
	sprite.modulate = Color.WHITE
	sprite.scale = Vector2.ONE
	glow.energy = 0.0
	chill.energy = 0.0


func is_dead() -> bool:
	return bs == BS.DYING or bs == BS.DEAD


func is_hostile() -> bool:
	return bs != BS.SLEEP and bs != BS.DYING and bs != BS.DEAD


func _use_awake() -> void:
	var tex: Texture2D = load(TEX_AWAKE)
	sprite.texture = tex
	sprite.hframes = 3
	sprite.offset = Vector2(0, -float(tex.get_height()) * 0.5 + 2.0)
	glow.energy = 0.7
	chill.energy = 0.6


# --------------------------------------------------------------------- Ablauf
func _physics_process(delta: float) -> void:
	_time += delta
	_bflash = maxf(0.0, _bflash - delta)
	if _wave >= 0.0:
		_wave += delta / 0.35
		if _wave > 1.0:
			_wave = -1.0
	var moving := false
	match bs:
		BS.SLEEP:
			_do_sleep()
		BS.WAKING:
			_do_waking(delta)
		BS.WALK:
			moving = _do_walk(delta)
		BS.SWIPE_WIND:
			_do_swipe_wind(delta)
		BS.SWIPE:
			_do_swipe(delta)
		BS.SLAM_WIND:
			_do_slam_wind(delta)
		BS.SLAM_AIR:
			_do_slam_air(delta)
		BS.RECOVER:
			_do_recover(delta)
		BS.ROAR:
			_do_roar(delta)
		BS.SHARDS:
			_do_shards(delta)
		BS.DYING:
			_do_dying(delta)
		BS.DEAD:
			_do_dead(delta)
	if not moving:
		velocity = Vector2.ZERO
	move_and_slide()
	if bs != BS.DYING:
		_animate_boss(delta)
	queue_redraw()


func _do_sleep() -> void:
	if _player_alive() and global_position.distance_to(_target.global_position) < WAKE_RADIUS:
		wake()


func wake() -> void:
	if bs != BS.SLEEP:
		return
	bs = BS.WAKING
	_t = 2.0
	_use_awake()
	Sound.play_at("boss_roar", global_position)
	if _target != null:
		_target.add_shake(3.0)
	woke.emit()


func _do_waking(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		bs = BS.WALK
		_cd = 1.0


func _speed() -> float:
	return WALK_SPEED * (1.35 if phase == 2 else 1.0)


func _do_walk(delta: float) -> bool:
	if not _player_alive():
		return false
	var to_p := _target.global_position - global_position
	var dist := to_p.length()
	_face = to_p / maxf(dist, 0.001)
	var moving := dist > 44.0
	if moving:
		velocity = _face * _speed()
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = 0.55
			Sound.play_at("step", global_position, 3.0, 0.55)       # schwere Schritte: tiefer Schneeknirsch
	_cd -= delta
	if _cd <= 0.0:
		_pick_attack(dist)
	return moving


func _pick_attack(dist: float) -> void:
	var pool: Array[String] = []
	if dist < 75.0:
		pool = ["swipe", "swipe", "slam", "shards"]
	else:
		pool = ["slam", "slam", "shards"]
	if phase == 2:
		pool.append("shards")
	var pick := pool[randi() % pool.size()]
	if pick == _last and randf() < 0.7:
		pick = pool[randi() % pool.size()]
	_last = pick
	match pick:
		"swipe":
			_start_swipe()
		"slam":
			_start_slam()
		_:
			_start_shards()


func _rage() -> float:
	return 1.25 if phase == 2 else 1.0


# --- Pranken-Hieb
func _start_swipe() -> void:
	bs = BS.SWIPE_WIND
	_total = SWIPE_TIME / _rage()
	_t = _total
	_swipe_dir = _face
	_telegraph = 0.0


func _do_swipe_wind(delta: float) -> void:
	_t -= delta
	_telegraph = 1.0 - clampf(_t / _total, 0.0, 1.0)
	if _player_alive():
		var to_p := (_target.global_position - global_position).normalized()
		_swipe_dir = _swipe_dir.slerp(to_p, minf(1.0, delta * 1.4))     # zielt langsam nach
	_face = _swipe_dir
	if _t <= 0.0:
		bs = BS.SWIPE
		_t = 0.35
		Sound.play_at("boss_swipe", global_position)
		if _player_alive():
			var to_p2 := _target.global_position - global_position
			var d := to_p2.length()
			var cos_half := cos(deg_to_rad(SWIPE_ARC_DEG * 0.5))
			if d < SWIPE_RANGE + 6.0 and (d < 4.0 or _swipe_dir.dot(to_p2 / d) >= cos_half):
				_target.take_hit(DMG_SWIPE + _bonus, global_position)
				_target.add_shake(4.0)


func _do_swipe(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_to_recover(0.7)


# --- Sprung
func _start_slam() -> void:
	bs = BS.SLAM_WIND
	_total = SLAM_TIME / _rage()
	_t = _total
	_slam_from = global_position
	_slam_to = _clamp_to_arena(_target.global_position if _player_alive() else global_position)
	_telegraph = 0.0


func _clamp_to_arena(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, arena_rect.position.x, arena_rect.end.x), clampf(p.y, arena_rect.position.y, arena_rect.end.y))


func _do_slam_wind(delta: float) -> void:
	_t -= delta
	_telegraph = 1.0 - clampf(_t / _total, 0.0, 1.0)
	if _t > _total * 0.5 and _player_alive():                  # erst zielt er nach, dann steht das Ziel fest
		_slam_to = _slam_to.lerp(_clamp_to_arena(_target.global_position), minf(1.0, delta * 2.0))
	_face = (_slam_to - global_position).normalized()
	if _t <= 0.0:
		bs = BS.SLAM_AIR
		_t = SLAM_AIR_TIME
		_slam_from = global_position
		Sound.play_at("lunge", global_position, 2.0, 0.5)


func _do_slam_air(delta: float) -> void:
	_t -= delta
	var k := 1.0 - clampf(_t / SLAM_AIR_TIME, 0.0, 1.0)
	global_position = _slam_from.lerp(_slam_to, k)
	sprite.position.y = -sin(k * PI) * 46.0
	shadow.scale = Vector2.ONE * (2.2 - sin(k * PI) * 0.9)
	if _t <= 0.0:
		_land()


func _land() -> void:
	global_position = _slam_to
	sprite.position.y = 0.0
	shadow.scale = Vector2.ONE * 2.2
	_wave = 0.0
	Sound.play_at("boss_slam", global_position)
	Fx.burst(self, global_position + Vector2(0, -4), Color(0.92, 0.97, 1.0), 26, 0.7, 110.0)
	if _player_alive():
		_target.add_shake(4.5)
		if _target.global_position.distance_to(global_position) < SLAM_RADIUS + 4.0:
			_target.take_hit(DMG_SLAM + _bonus, global_position)
	_to_recover(1.1)                                           # nach der Landung ist er verwundbar und müde


# --- Eissplitter
func _start_shards() -> void:
	bs = BS.SHARDS
	_total = SHARD_TIME / _rage()
	_t = _total
	_waves_left = 2 if phase == 2 else 1
	_shard_off = randf() * TAU
	_telegraph = 0.0
	Sound.play_at("boss_roar", global_position, -5.0, 1.15)


func _do_shards(delta: float) -> void:
	_t -= delta
	_telegraph = 1.0 - clampf(_t / _total, 0.0, 1.0)
	if _t > 0.0:
		return
	var n := SHARDS_PER_WAVE + (4 if phase == 2 else 0)
	var scene: PackedScene = load("res://scenes/projectile.tscn")
	for i in n:
		var ang := _shard_off + float(i) * TAU / float(n)
		var pr: Projectile = scene.instantiate()
		pr.position = global_position + Vector2(0, -6) + Vector2.from_angle(ang) * 14.0
		get_parent().add_child(pr)
		pr.launch(Vector2.from_angle(ang), SHARD_SPEED, DMG_SHARD + _bonus, "shard")
	Sound.play_at("shards", global_position)
	_waves_left -= 1
	if _waves_left > 0:
		_shard_off += PI / float(n)                            # zweite Welle versetzt: die Lücken wandern
		_t = 0.55
		_total = 0.55
	else:
		_to_recover(0.9)


func _to_recover(seconds: float) -> void:
	bs = BS.RECOVER
	_t = seconds / _rage()
	_telegraph = 0.0


func _do_recover(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		bs = BS.WALK
		_cd = 1.0 if phase == 1 else 0.6


# --- Wut-Phase
func _enter_phase2() -> void:
	phase = 2
	bs = BS.ROAR
	_t = 1.6
	glow.color = Color(1.0, 0.55, 0.45)
	glow.energy = 1.0
	Sound.play_at("boss_roar", global_position)
	_target.add_shake(4.0)
	adds_requested.emit(2)
	phase_changed.emit(2)


func _do_roar(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		bs = BS.WALK
		_cd = 0.8


# --------------------------------------------------------------------- Treffer & Tod
func take_hit(amount: int, _dir: Vector2) -> void:
	if bs == BS.DYING or bs == BS.DEAD:
		return
	if bs == BS.SLAM_AIR or bs == BS.WAKING or bs == BS.ROAR:
		Sound.play_at("tink", global_position)                 # in der Luft / beim Brüllen: nichts geht durch
		return
	if bs == BS.SLEEP:
		wake()                                                 # der erste Treffer weckt ihn (und zählt)
	health = maxi(0, health - amount)
	hp = health
	_bflash = 0.12
	Sound.play_at("boss_hit", global_position)
	Fx.text(self, global_position + Vector2(0, -sprite.texture.get_height() - 4.0), str(amount), Color.WHITE, 22)
	Fx.burst(self, global_position + Vector2(0, -22), Color(0.85, 0.95, 1.0), 6, 0.3, 50.0)
	health_changed.emit(health, max_health)
	if health <= 0:
		_die()
	elif phase == 1 and health <= max_health / 2:
		_enter_phase2()


func _die() -> void:
	bs = BS.DYING
	_t = 2.8
	_zzz_t = 0.0
	remove_from_group("enemies")
	collision.set_deferred("disabled", true)
	Game.add_xp(xp_reward)
	Game.boss_defeated = true
	Sound.play_at("boss_die", global_position)
	glow.energy = 0.0
	chill.energy = 0.0
	died.emit(self)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(sprite, "scale", Vector2(1.12, 0.72), 2.2)
	tw.tween_property(sprite, "modulate", Color(0.85, 0.9, 1.05), 2.2)


func _do_dying(delta: float) -> void:
	_t -= delta
	_zzz_t -= delta
	if _zzz_t <= 0.0:
		_zzz_t = 0.35
		Fx.burst(self, global_position + Vector2(randf_range(-18, 18), randf_range(-40, -6)),
				Color(0.8, 0.95, 1.0), 10, 0.6, 50.0)
	if _t <= 0.0:
		set_defeated()
		_zzz_t = 1.0


func _do_dead(delta: float) -> void:
	_zzz_t -= delta
	if _zzz_t <= 0.0:
		_zzz_t = 2.4
		Fx.text(self, global_position + Vector2(18, -34), "Zzz", Color(0.85, 0.93, 1.0), 16, 1.8)


# --------------------------------------------------------------------- Optik
func _animate_boss(_delta: float) -> void:
	var lift := 0.0
	var scl := Vector2.ONE
	var frame := 0
	match bs:
		BS.SLEEP, BS.DEAD:
			var b := sin(_time * 1.6) * 0.03                  # atmet ruhig
			scl = Vector2(1.0 - b, 1.0 + b)
		BS.WAKING, BS.ROAR:
			frame = 2
			scl = Vector2(1.0 + sin(_time * 34.0) * 0.025, 1.0 - sin(_time * 34.0) * 0.025)
		BS.WALK:
			if velocity.length() > 5.0:
				lift = absf(sin(_time * 5.0)) * 2.0
		BS.SWIPE_WIND:
			frame = 1
			scl = Vector2(1.0 - 0.08 * _telegraph, 1.0 + 0.08 * _telegraph)
		BS.SWIPE:
			frame = 1
		BS.SLAM_WIND:
			frame = 2
			scl = Vector2(1.0 + 0.2 * _telegraph, 1.0 - 0.25 * _telegraph)      # geht in die Hocke
		BS.SLAM_AIR:
			frame = 2
			scl = Vector2(0.9, 1.15)
		BS.SHARDS:
			frame = 2
			scl = Vector2(1.0 + 0.1 * _telegraph, 1.0 + 0.1 * _telegraph)
	sprite.frame = frame if sprite.hframes > 1 else 0
	if bs != BS.SLAM_AIR:
		sprite.position.y = -lift
	sprite.scale = scl
	if absf(_face.x) > 0.15 and sprite.hframes > 1:
		sprite.flip_h = _face.x < 0.0
	if _bflash > 0.0:
		sprite.modulate = Color(2.2, 2.2, 2.2)
	elif phase == 2 and bs != BS.DEAD:
		sprite.modulate = Color(1.15, 0.9, 0.88)
	else:
		sprite.modulate = Color.WHITE
	if phase == 2 and bs != BS.DEAD:
		glow.energy = 1.0 + sin(_time * 6.0) * 0.12


func _draw() -> void:
	var c := Vector2(0, -8)
	if bs == BS.SWIPE_WIND or bs == BS.SWIPE:
		var half := deg_to_rad(SWIPE_ARC_DEG * 0.5)
		var pts := PackedVector2Array([c])
		for i in 17:
			pts.append(c + Vector2.from_angle(_swipe_dir.angle() - half + 2.0 * half * float(i) / 16.0) * SWIPE_RANGE)
		var a := 0.12 + 0.30 * (1.0 if bs == BS.SWIPE else _telegraph)
		draw_colored_polygon(pts, Color(1.0, 0.35, 0.3, a))
		pts.append(c)
		draw_polyline(pts, Color(1.0, 0.55, 0.45, 0.7), 1.0)
	elif bs == BS.SLAM_WIND:
		var tl := to_local(_slam_to)
		draw_circle(tl, SLAM_RADIUS, Color(1.0, 0.3, 0.25, 0.12 + 0.30 * _telegraph))
		draw_arc(tl, SLAM_RADIUS * (0.25 + 0.75 * _telegraph), 0.0, TAU, 40, Color(1.0, 0.65, 0.55, 0.85), 1.5)
		draw_arc(tl, SLAM_RADIUS, 0.0, TAU, 40, Color(1.0, 0.5, 0.4, 0.75), 1.0)
	elif bs == BS.SHARDS:
		draw_arc(c, 14.0 + 26.0 * _telegraph, 0.0, TAU, 32, Color(0.6, 0.9, 1.0, 0.8), 1.5)
	if _wave >= 0.0:
		draw_arc(Vector2(0, -2), SLAM_RADIUS * _wave * 1.25, 0.0, TAU, 48, Color(0.88, 0.96, 1.0, 1.0 - _wave), 2.0)
