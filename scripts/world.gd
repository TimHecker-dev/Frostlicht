extends Node2D
## Baut die Spielwelt auf: Boden, Wald, Felsen, Schneehügel, Begrenzung –
## und sorgt dafür, dass immer ein paar Gegner unterwegs sind.
## Der Wald ist bei jedem Start gleich (layout_seed), die Gegner sind zufällig.

const MAP_SIZE := Vector2(1600, 1120)
const FIRE_POS := Vector2(800, 560)
const FIRE_SAFE_RADIUS := 64.0     # in diesem Umkreis sind Spieler und Lagerplatz sicher
const WALL_INSET := 22.0           # unsichtbare Wand zum Kartenrand
const MAX_ENEMIES := 7
const SPAWN_INTERVAL := 5.0
const TREE_TARGET := 250
const ROCK_TARGET := 26
const MOUND_TARGET := 90
const CELL := 24.0

# Die Dämmerung "atmet" ganz langsam zwischen diesen zwei Farben.
const DUSK_A := Color(0.50, 0.58, 0.86)
const DUSK_B := Color(0.57, 0.65, 0.92)

@export var layout_seed := 7

var _rng := RandomNumberGenerator.new()
var _grid := {}                    # Zelle -> Array[Vector2] bereits belegter Stellen
var _sway: Array = []              # [Sprite2D, Phase, Stärke] – wiegende Bäume
var _spawn_t := 3.0
var _time := 0.0
var _footprint: Texture2D
var _shadow: Texture2D
var _enemy_scene: PackedScene

@onready var tint: CanvasModulate = $CanvasModulate
@onready var ground: Sprite2D = $Ground
@onready var decals: Node2D = $Decals
@onready var entities: Node2D = $Entities
@onready var player: Player = $Entities/Player
@onready var campfire: Campfire = $Entities/Campfire
@onready var ui: GameUI = $UI


func _ready() -> void:
	_rng.seed = layout_seed
	_footprint = load("res://art/footprint.png")
	_shadow = load("res://art/shadow.png")
	_enemy_scene = load("res://scenes/enemy.tscn")

	ground.centered = false
	ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ground.region_enabled = true
	ground.region_rect = Rect2(Vector2.ZERO, MAP_SIZE)

	campfire.position = FIRE_POS
	player.position = FIRE_POS + Vector2(0, 62)
	player.set_world_bounds(Rect2(Vector2.ZERO, MAP_SIZE))
	player.stepped.connect(_on_player_stepped)
	player.died.connect(ui.show_death)
	campfire.rest_changed.connect(ui.set_resting)
	ui.respawn_requested.connect(_on_respawn_requested)
	ui.bind_player(player)

	_build_walls()
	_scatter_props()
	for i in MAX_ENEMIES - 2:
		_spawn_enemy(140.0)


func _process(delta: float) -> void:
	_time += delta
	for s in _sway:
		(s[0] as Sprite2D).rotation = sin(_time * 0.9 + float(s[1])) * float(s[2])
	tint.color = DUSK_A.lerp(DUSK_B, 0.5 + 0.5 * sin(_time * 0.12))

	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = SPAWN_INTERVAL
		if not player.dead and get_tree().get_nodes_in_group("enemies").size() < MAX_ENEMIES:
			_spawn_enemy(230.0)


# --------------------------------------------------------------------- Aufbau
func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var t := 80.0
	var i := WALL_INSET
	var rects: Array[Rect2] = [
		Rect2(-t, -t, MAP_SIZE.x + 2.0 * t, t + i),
		Rect2(-t, MAP_SIZE.y - i, MAP_SIZE.x + 2.0 * t, t + i),
		Rect2(-t, -t, t + i, MAP_SIZE.y + 2.0 * t),
		Rect2(MAP_SIZE.x - i, -t, t + i, MAP_SIZE.y + 2.0 * t),
	]
	for r in rects:
		var shape := RectangleShape2D.new()
		shape.size = r.size
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.position = r.position + r.size * 0.5
		body.add_child(cs)


func _scatter_props() -> void:
	_claim(FIRE_POS)
	# Zwei geschmückte Bäume am Rand der Lichtung
	_place_lit_tree(FIRE_POS + Vector2(-128, -78))
	_place_lit_tree(FIRE_POS + Vector2(142, -58))

	var trees: Array = [load("res://art/tree_a.png"), load("res://art/tree_b.png"), load("res://art/tree_c.png")]
	var placed := 0
	var attempts := 0
	while placed < TREE_TARGET and attempts < 9000:
		attempts += 1
		var p := Vector2(_rng.randf_range(18.0, MAP_SIZE.x - 18.0), _rng.randf_range(30.0, MAP_SIZE.y - 10.0))
		if p.distance_to(FIRE_POS) < 115.0:
			continue                                   # Lichtung um das Lagerfeuer
		var edge := minf(minf(p.x, MAP_SIZE.x - p.x), minf(p.y, MAP_SIZE.y - p.y))
		if edge > 120.0 and _rng.randf() > 0.2:
			continue                                   # am Rand dichter Wald, innen lichter
		if not _free_spot(p, 24.0):
			continue
		_claim(p)
		var tex: Texture2D = trees[_rng.randi() % trees.size()]
		var body := _add_prop(tex, p, 4.0, _rng.randf() < 0.5)
		_sway.append([body.get_node("Sprite"), _rng.randf() * TAU, _rng.randf_range(0.012, 0.03)])
		placed += 1

	var rock: Texture2D = load("res://art/rock.png")
	placed = 0
	attempts = 0
	while placed < ROCK_TARGET and attempts < 3000:
		attempts += 1
		var p := Vector2(_rng.randf_range(40.0, MAP_SIZE.x - 40.0), _rng.randf_range(50.0, MAP_SIZE.y - 30.0))
		if p.distance_to(FIRE_POS) < 90.0 or not _free_spot(p, 24.0):
			continue
		_claim(p)
		_add_prop(rock, p, 7.0, _rng.randf() < 0.5)
		placed += 1

	var mound: Texture2D = load("res://art/mound.png")
	for i in MOUND_TARGET:
		var m := Sprite2D.new()
		m.texture = mound
		m.position = Vector2(_rng.randf_range(30.0, MAP_SIZE.x - 30.0), _rng.randf_range(40.0, MAP_SIZE.y - 20.0))
		m.scale = Vector2.ONE * _rng.randf_range(0.8, 1.6)
		m.flip_h = _rng.randf() < 0.5
		decals.add_child(m)


func _place_lit_tree(pos: Vector2) -> void:
	_claim(pos)
	var body := _add_prop(load("res://art/tree_lit.png"), pos, 4.0, false)
	var lamp := PointLight2D.new()
	lamp.texture = load("res://art/light.png")
	lamp.color = Color(1.0, 0.78, 0.45)
	lamp.energy = 0.5
	lamp.texture_scale = 0.4
	lamp.position = Vector2(0, -30)
	body.add_child(lamp)


func _add_prop(tex: Texture2D, pos: Vector2, radius: float, flip: bool) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	var sh := Sprite2D.new()
	sh.name = "Shadow"
	sh.texture = _shadow
	sh.scale = Vector2.ONE * (float(tex.get_width()) / 28.0 * 0.62)
	body.add_child(sh)
	var sp := Sprite2D.new()
	sp.name = "Sprite"
	sp.texture = tex
	sp.offset = Vector2(0, -float(tex.get_height()) * 0.5 + 2.0)
	sp.flip_h = flip
	body.add_child(sp)
	if radius > 0.0:
		var cs := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = radius
		cs.shape = shape
		cs.position = Vector2(0, -radius * 0.5)
		body.add_child(cs)
	entities.add_child(body)
	return body


# Einfaches Raster, damit Bäume und Felsen Abstand halten, ohne dass alles gegen alles geprüft wird
func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


func _claim(p: Vector2) -> void:
	var key := _cell(p)
	if not _grid.has(key):
		_grid[key] = []
	_grid[key].append(p)


func _free_spot(p: Vector2, min_dist: float) -> bool:
	var c := _cell(p)
	var reach := ceili(min_dist / CELL)
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			var key := Vector2i(c.x + dx, c.y + dy)
			if _grid.has(key):
				for q in _grid[key]:
					if (q as Vector2).distance_to(p) < min_dist:
						return false
	return true


# --------------------------------------------------------------------- Laufendes Spiel
## Lässt einen Gegner in einem Ring um den Spieler auftauchen: nicht im Bild, aber nah genug,
## dass man ihn bald trifft. min_dist = Mindestabstand zum Spieler.
func _spawn_enemy(min_dist: float) -> void:
	for attempt in 50:
		var p := player.global_position + Vector2.from_angle(randf() * TAU) * randf_range(min_dist, min_dist + 200.0)
		if p.x < 70.0 or p.x > MAP_SIZE.x - 70.0 or p.y < 80.0 or p.y > MAP_SIZE.y - 50.0:
			continue
		if p.distance_to(FIRE_POS) < FIRE_SAFE_RADIUS + 50.0:
			continue
		if not _free_spot(p, 16.0):
			continue
		var enemy: Enemy = _enemy_scene.instantiate()
		enemy.position = p
		entities.add_child(enemy)
		var wisp_chance := minf(0.55, 0.25 + 0.03 * float(Game.level))
		enemy.setup("wisp" if randf() < wisp_chance else "blob", Game.level, player, FIRE_POS, FIRE_SAFE_RADIUS)
		return


func _on_player_stepped(pos: Vector2, dir: Vector2, side: float) -> void:
	var s := Sprite2D.new()
	s.texture = _footprint
	s.position = pos + dir.orthogonal() * side * 2.5 + Vector2(0, -0.5)
	s.rotation = dir.angle()
	s.modulate = Color(1, 1, 1, 0.85)
	decals.add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.0, 8.0).set_delay(2.0)
	tw.tween_callback(s.queue_free)


func _on_respawn_requested() -> void:
	player.respawn(FIRE_POS + Vector2(0, 62))
