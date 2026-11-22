extends Node2D
## Die Frosthöhle: ein eigenes Gebiet mit dem Endgegner "Der Winterschläfer".
## Betreten wird sie durch den Höhleneingang im Norden des Waldes (E drücken).
## Solange der Boss kämpft, ist der Ausgang zugefroren. Stirbst du hier, wachst du am Lagerfeuer im Wald auf,
## und der Boss ist beim nächsten Mal wieder ausgeruht.

const SIZE := Vector2(760, 560)
const INSET := 28.0
const START_POS := Vector2(380, 466)
const BOSS_POS := Vector2(380, 200)
const PORTAL_POS := Vector2(380, 522)
const PILLARS := [Vector2(200, 330), Vector2(560, 330), Vector2(290, 420), Vector2(470, 420), Vector2(150, 220), Vector2(610, 220)]

@export var layout_seed := 11

var boss: Boss
var portal: Portal

var _rng := RandomNumberGenerator.new()
var _footprint: Texture2D
var _shadow: Texture2D
var _enemy_scene: PackedScene

@onready var ground: Sprite2D = $Ground
@onready var decals: Node2D = $Decals
@onready var entities: Node2D = $Entities
@onready var player: Player = $Entities/Player
@onready var aurora: Aurora = $Aurora
@onready var ui: GameUI = $UI


func _ready() -> void:
	_rng.seed = layout_seed
	_footprint = load("res://art/footprint.png")
	_shadow = load("res://art/shadow.png")
	_enemy_scene = load("res://scenes/enemy.tscn")

	ground.centered = false
	ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ground.region_enabled = true
	ground.region_rect = Rect2(Vector2.ZERO, SIZE)

	player.position = START_POS
	player.aim = Vector2.UP
	player.set_world_bounds(Rect2(Vector2.ZERO, SIZE))
	player.stepped.connect(_on_player_stepped)
	player.died.connect(ui.show_death)
	ui.respawn_requested.connect(_on_respawn_requested)
	ui.bind_player(player)

	_build_walls()
	_build_props()
	_build_portal()
	_build_boss()
	Sound.set_mode("world")
	if not Game.boss_defeated:
		ui.announce("Die Frosthöhle ... irgendetwas schläft hier.", Color(0.7, 0.9, 1.0))


# --------------------------------------------------------------------- Aufbau
func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var t := 80.0
	var i := INSET
	var rects: Array[Rect2] = [
		Rect2(-t, -t, SIZE.x + 2.0 * t, t + i),
		Rect2(-t, SIZE.y - i, SIZE.x + 2.0 * t, t + i),
		Rect2(-t, -t, t + i, SIZE.y + 2.0 * t),
		Rect2(SIZE.x - i, -t, t + i, SIZE.y + 2.0 * t),
	]
	for r in rects:
		var shape := RectangleShape2D.new()
		shape.size = r.size
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.position = r.position + r.size * 0.5
		body.add_child(cs)


func _build_props() -> void:
	var crystal_a: Texture2D = load("res://art/crystal_a.png")
	var crystal_b: Texture2D = load("res://art/crystal_b.png")
	var rock: Texture2D = load("res://art/ice_rock.png")
	var step := 30.0
	var x := INSET + 6.0
	while x < SIZE.x - INSET:
		for y in [INSET + 2.0, SIZE.y - INSET - 2.0]:
			if absf(x - PORTAL_POS.x) < 40.0 and y > SIZE.y * 0.5:
				continue                                          # Lücke für den Ausgang
			_edge_prop(Vector2(x + _rng.randf_range(-6, 6), y + _rng.randf_range(-4, 4)), crystal_a, crystal_b, rock)
		x += step
	var y2 := INSET + 36.0
	while y2 < SIZE.y - INSET - 20.0:
		for xx in [INSET + 4.0, SIZE.x - INSET - 4.0]:
			_edge_prop(Vector2(xx + _rng.randf_range(-4, 4), y2 + _rng.randf_range(-6, 6)), crystal_a, crystal_b, rock)
		y2 += step
	for p in PILLARS:                                             # Eiskristall-Säulen: Deckung vor Eissplittern
		_add_prop(crystal_a, p, 7.0, true)


func _edge_prop(pos: Vector2, crystal_a: Texture2D, crystal_b: Texture2D, rock: Texture2D) -> void:
	var r := _rng.randf()
	if r < 0.55:
		_add_prop(rock, pos, 10.0, false)
	elif r < 0.8:
		_add_prop(crystal_b, pos, 10.0, _rng.randf() < 0.5)
	else:
		_add_prop(crystal_a, pos, 8.0, true)


func _add_prop(tex: Texture2D, pos: Vector2, radius: float, lit: bool) -> void:
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	var sh := Sprite2D.new()
	sh.texture = _shadow
	sh.scale = Vector2.ONE * (float(tex.get_width()) / 28.0 * 0.62)
	body.add_child(sh)
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.offset = Vector2(0, -float(tex.get_height()) * 0.5 + 2.0)
	sp.flip_h = _rng.randf() < 0.5
	body.add_child(sp)
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	cs.shape = shape
	cs.position = Vector2(0, -radius * 0.5)
	body.add_child(cs)
	if lit:                                                       # Kristalle leuchten kühl
		var l := PointLight2D.new()
		l.texture = load("res://art/light.png")
		l.color = Color(0.5, 0.88, 1.0)
		l.energy = 0.5
		l.texture_scale = 0.34
		l.position = Vector2(0, -float(tex.get_height()) * 0.45)
		body.add_child(l)
	entities.add_child(body)


func _build_portal() -> void:
	var scene: PackedScene = load("res://scenes/portal.tscn")
	portal = scene.instantiate()
	portal.position = PORTAL_POS
	portal.target_scene = Scenes.MAIN
	portal.entry = "from_arena"
	portal.prompt = "E: Zurück zum Lager"
	entities.add_child(portal)


func _build_boss() -> void:
	var scene: PackedScene = load("res://scenes/boss.tscn")
	boss = scene.instantiate()
	boss.position = BOSS_POS
	entities.add_child(boss)
	var m := INSET + 44.0
	boss.arena_rect = Rect2(m, m, SIZE.x - 2.0 * m, SIZE.y - 2.0 * m)
	boss.setup_boss(player, Game.level)
	if Game.boss_defeated:
		boss.set_defeated()                                       # friedlich schlafend, kein Kampf mehr
		return
	boss.woke.connect(_on_boss_woke)
	boss.health_changed.connect(_on_boss_health)
	boss.phase_changed.connect(_on_boss_phase)
	boss.adds_requested.connect(_spawn_adds)
	boss.died.connect(_on_boss_died)


# --------------------------------------------------------------------- Kampfverlauf
func _on_boss_woke() -> void:
	ui.show_boss_bar(Boss.BOSS_NAME, boss.health, boss.max_health)
	Sound.set_mode("boss")
	portal.lock("Der Ausgang ist zugefroren ...")
	aurora.fade_to(0.22, 2.5)
	player.set_camera_zoom(2.2, 1.8)                              # herauszoomen: der Boss ist groß
	ui.announce("%s erwacht!" % Boss.BOSS_NAME, Color(1.0, 0.72, 0.55))


func _on_boss_health(current: int, maximum: int) -> void:
	ui.set_boss_hp(current, maximum, boss.phase == 2)


func _on_boss_phase(_phase: int) -> void:
	Sound.set_boss_rage(true)
	aurora.set_colors(Color(1.0, 0.5, 0.35), Color(0.9, 0.35, 0.6))
	aurora.fade_to(0.32, 1.5)
	ui.announce("Der Winterschläfer wird wütend!", Color(1.0, 0.62, 0.5))


func _spawn_adds(count: int) -> void:
	for i in count:
		for attempt in 20:
			var p := boss.global_position + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(110.0, 190.0)
			if p.x < INSET + 50.0 or p.x > SIZE.x - INSET - 50.0 or p.y < INSET + 50.0 or p.y > SIZE.y - INSET - 70.0:
				continue
			var e: Enemy = _enemy_scene.instantiate()
			e.position = p
			entities.add_child(e)
			e.setup("blob", Game.level, player, Vector2(-9999.0, -9999.0), 0.0)
			break


func _on_boss_died(_enemy: Enemy) -> void:
	ui.hide_boss_bar()
	Sound.set_mode("world")
	Sound.play("victory")
	Game.add_skill_points(2)
	player.heal_full()
	for n in get_tree().get_nodes_in_group("enemies"):              # übrige Frostblobs lösen sich auf
		n.queue_free()
	for p in get_tree().get_nodes_in_group("projectiles"):
		p.queue_free()
	portal.unlock()
	aurora.set_colors(Color(0.25, 1.0, 0.65), Color(0.55, 0.35, 1.0))
	aurora.fade_to(0.2, 3.0)
	player.set_camera_zoom(Game.WORLD_ZOOM, 2.5)
	ui.announce("Der Winterschläfer schläft wieder ein.   Belohnung: 2 Fähigkeitspunkte!", Color(1.0, 0.86, 0.42))
	Game.hit_stop(0.2)


func _on_respawn_requested() -> void:
	Scenes.change_area(Scenes.MAIN, "respawn")


func _on_player_stepped(pos: Vector2, dir: Vector2, side: float) -> void:
	var s := Sprite2D.new()
	s.texture = _footprint
	s.position = pos + dir.orthogonal() * side * 2.5 + Vector2(0, -0.5)
	s.rotation = dir.angle()
	s.modulate = Color(1, 1, 1, 0.7)
	decals.add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.0, 8.0).set_delay(2.0)
	tw.tween_callback(s.queue_free)
