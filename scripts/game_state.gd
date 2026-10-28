extends Node
## Autoload "Game": Fortschritt (Stufe, Erfahrung, Fähigkeitspunkte), der Fähigkeitenbaum,
## die Tastenbelegung und ein paar globale Helfer.
## Alle Zahlen zum Ausbalancieren stehen hier oben – ändere sie einfach und probiere es aus.

signal xp_changed
signal level_up(new_level: int)
signal skills_changed      # Fähigkeit freigeschaltet oder zurückgesetzt
signal stats_changed       # Max-Leben / Angriff / Verteidigung haben sich geändert

const WORLD_ZOOM := 3.0    # Kamera-Zoom (sorgt für den groben Pixel-Look)

# Grundwerte ohne Fähigkeiten
const BASE_MAX_HEALTH := 50
const BASE_ATTACK := 8
const BASE_DEFENCE := 0

# Fähigkeitenbaum: drei Äste mit je vier Stufen. Eine Stufe lässt sich erst freischalten, wenn die
# davor aktiv ist. Jede Stufe kostet 1 Fähigkeitspunkt; pro Stufenaufstieg gibt es 1 Punkt.
# "bonus" wird auf den Grundwert addiert.
const BRANCHES := ["health", "attack", "defence"]
const TREE := {
	"health": {
		"title": "Lebenskraft",
		"stat": "Max. Leben",
		"color": Color(0.92, 0.42, 0.40),
		"nodes": [
			{"name": "Warme Suppe", "bonus": 15},
			{"name": "Dicke Socken", "bonus": 15},
			{"name": "Kaminfeuer", "bonus": 20},
			{"name": "Winterherz", "bonus": 30},
		],
	},
	"attack": {
		"title": "Schlagkraft",
		"stat": "Angriff",
		"color": Color(0.96, 0.68, 0.36),
		"nodes": [
			{"name": "Fester Griff", "bonus": 2},
			{"name": "Schwung holen", "bonus": 2},
			{"name": "Eiskristall", "bonus": 3},
			{"name": "Frostklinge", "bonus": 4},
		],
	},
	"defence": {
		"title": "Standfestigkeit",
		"stat": "Verteidigung",
		"color": Color(0.46, 0.72, 0.96),
		"nodes": [
			{"name": "Wollschal", "bonus": 1},
			{"name": "Dicker Mantel", "bonus": 1},
			{"name": "Fellstiefel", "bonus": 2},
			{"name": "Pelzmütze", "bonus": 2},
		],
	},
}

var level := 1
var xp := 0
var skill_points := 0
var ranks := {"health": 0, "attack": 0, "defence": 0}   # freigeschaltete Stufen je Ast

var ui_font: Font = null


func _ready() -> void:
	_register_inputs()
	_make_font()


# --------------------------------------------------------------------- Fortschritt
func xp_to_next() -> int:
	return 25 + 15 * (level - 1)


func add_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		skill_points += 1
		level_up.emit(level)
	xp_changed.emit()


# --------------------------------------------------------------------- Werte
func _bonus(branch: String) -> int:
	var total := 0
	var nodes: Array = TREE[branch]["nodes"]
	for i in int(ranks[branch]):
		total += int(nodes[i]["bonus"])
	return total


func max_health() -> int:
	return BASE_MAX_HEALTH + _bonus("health")


func attack_damage() -> int:
	return BASE_ATTACK + _bonus("attack")


func defence() -> int:
	return BASE_DEFENCE + _bonus("defence")


# --------------------------------------------------------------------- Fähigkeiten
## Schaltet die nächste Stufe eines Astes frei. Gibt true zurück, wenn es geklappt hat.
func unlock_next(branch: String) -> bool:
	var nodes: Array = TREE[branch]["nodes"]
	if skill_points <= 0 or int(ranks[branch]) >= nodes.size():
		return false
	ranks[branch] = int(ranks[branch]) + 1
	skill_points -= 1
	skills_changed.emit()
	stats_changed.emit()
	xp_changed.emit()
	return true


## Gibt alle Fähigkeitspunkte kostenlos zurück (zum Ausprobieren).
func reset_skills() -> void:
	for b in BRANCHES:
		skill_points += int(ranks[b])
		ranks[b] = 0
	skills_changed.emit()
	stats_changed.emit()
	xp_changed.emit()


func new_game() -> void:
	level = 1
	xp = 0
	skill_points = 0
	for b in BRANCHES:
		ranks[b] = 0
	Engine.time_scale = 1.0
	get_tree().paused = false


# --------------------------------------------------------------------- Helfer
## Kurzes Einfrieren beim Treffer – gibt Schlägen mehr Wucht.
func hit_stop(duration := 0.05) -> void:
	if Engine.time_scale < 1.0 or get_tree().paused:
		return
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_F9:        # Test-Taste: sofort eine Stufe aufsteigen
		add_xp(xp_to_next())
	elif event.keycode == KEY_F11:     # Vollbild an/aus
		var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _make_font() -> void:
	if not ResourceLoader.exists("res://fonts/Nunito.ttf"):
		return
	var base: Font = load("res://fonts/Nunito.ttf")
	var fv := FontVariation.new()
	fv.base_font = base
	var tag: int = TextServerManager.get_primary_interface().name_to_tag("wght")
	fv.variation_opentype = {tag: 650.0}
	ui_font = fv


# --------------------------------------------------------------------- Tastenbelegung
# Die Aktionen werden hier im Code angelegt (statt in den Projekteinstellungen),
# damit alles an einer Stelle steht. Mit Controller funktioniert es auch.
func _register_inputs() -> void:
	_action("move_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("move_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_action("move_up", [KEY_W, KEY_UP], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]])
	_action("move_down", [KEY_S, KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]])
	_action("attack", [KEY_SPACE, KEY_J], [JOY_BUTTON_X, JOY_BUTTON_A], [], true)
	_action("skill_tree", [KEY_K], [JOY_BUTTON_Y])
	_action("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START])


func _action(action: String, keys: Array, buttons: Array = [], axes: Array = [], mouse_left := false) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.3)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k as Key
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b as JoyButton
		InputMap.action_add_event(action, jb)
	for a in axes:
		var jm := InputEventJoypadMotion.new()
		jm.axis = a[0] as JoyAxis
		jm.axis_value = float(a[1])
		InputMap.action_add_event(action, jm)
	if mouse_left:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event(action, mb)
