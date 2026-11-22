extends CanvasLayer
## Autoload "Scenes": Wechsel zwischen den Gebieten (Wald <-> Frosthöhle) mit weichem Überblenden.
## Das Leben wird mitgenommen (Game.carry_health), alles andere liegt ohnehin in "Game".

const MAIN := "res://scenes/main.tscn"
const ARENA := "res://scenes/arena.tscn"

var busy := false
var _rect: ColorRect


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(0.02, 0.03, 0.08, 1.0)
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.modulate.a = 0.0
	_rect.visible = false
	add_child(_rect)


## Wechselt das Gebiet. entry sagt dem neuen Gebiet, woher man kommt ("from_arena", "respawn", "").
func change_area(path: String, entry := "") -> void:
	if busy:
		return
	busy = true
	Game.next_entry = entry
	var player := get_tree().get_first_node_in_group("player") as Player
	Game.carry_health = -1 if (player == null or player.dead or entry == "respawn") else player.health
	if entry != "respawn":
		Sound.play("portal")
	_rect.visible = true
	var out := create_tween()
	out.tween_property(_rect, "modulate:a", 1.0, 0.55)
	await out.finished
	get_tree().paused = false
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	var back := create_tween()
	back.tween_property(_rect, "modulate:a", 0.0, 0.8)
	await back.finished
	_rect.visible = false
	busy = false


## Neues Spiel von vorn (Pause-Menü "Neustart").
func restart_game() -> void:
	Game.new_game()
	change_area(MAIN, "respawn")
