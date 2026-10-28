extends Node
## Autoload "Sound": Musik, Umgebungsgeräusche und Effekte an einer Stelle.
## Alle Klänge liegen in res://audio/ (erzeugt von tools/make_audio.py).
##
## Benutzung aus anderen Skripten:
##   Sound.play("swing")                       # normaler Effekt
##   Sound.play_at("hit", global_position)     # räumlich: links/rechts und leiser, wenn weit weg
##
## Was zusätzlich automatisch passiert:
##   - Musik läuft in zwei Ebenen. Sind Gegner hinter dir her, blendet sich eine leise rhythmische Ebene ein.
##   - Im Menü / bei Pause klingen Musik und Wind gedämpft, wie durch eine Hüttenwand.
##   - Am Lagerfeuer wird der Wind leiser (windgeschützt) und das Knistern lauter.

const BUS_MUSIC := "Music"
const BUS_AMBIENCE := "Ambience"
const BUS_SFX := "SFX"
const SETTINGS_PATH := "user://settings.cfg"

# --- Lautstärken in dB. Die Dateien sind schon aufeinander abgestimmt; hier wird nur feinjustiert. ---
const MUSIC_DB := 0.0           # ruhige Musik
const ALERT_DB := 1.0           # zusätzliche Gefahr-Ebene (voll eingeblendet)
const WIND_DB := -2.0
const FIRE_DB := 4.0            # Lagerfeuer-Knistern (räumlich, wird mit Abstand leiser)
const MENU_CUTOFF := 750.0      # Tiefpass im Menü (Hz)
const OPEN_CUTOFF := 20000.0
const SHELTER_DB := -7.0        # so viel leiser wird der Wind direkt am Feuer

# Name -> [Varianten (Dateinamen), Zusatz-Lautstärke dB, zufällige Tonhöhen-Streuung]
const SOUNDS := {
	"step": [["sfx_step_a", "sfx_step_b", "sfx_step_c"], 0.0, 0.08],
	"swing": [["sfx_swing_a", "sfx_swing_b"], 0.0, 0.05],
	"hit": [["sfx_hit_a", "sfx_hit_b", "sfx_hit_c"], 0.0, 0.06],
	"enemy_die": [["sfx_enemy_die"], 0.0, 0.05],
	"hurt": [["sfx_hurt"], 0.0, 0.04],
	"alert": [["sfx_alert"], 0.0, 0.03],
	"lunge": [["sfx_lunge"], 0.0, 0.05],
	"levelup": [["sfx_levelup"], 0.0, 0.0],
	"unlock": [["sfx_unlock"], 0.0, 0.0],
	"heal": [["sfx_heal"], 0.0, 0.04],
	"death": [["sfx_death"], 0.0, 0.0],
	"respawn": [["sfx_respawn"], 0.0, 0.0],
	"ui_hover": [["sfx_ui_hover"], 0.0, 0.05],
	"ui_click": [["sfx_ui_click"], 0.0, 0.04],
	"ui_open": [["sfx_ui_open"], 0.0, 0.0],
	"ui_close": [["sfx_ui_close"], 0.0, 0.0],
	"deny": [["sfx_deny"], 0.0, 0.0],
}

var music_volume := 0.8          # 0..1, im Pause-Menü einstellbar
var sfx_volume := 0.8            # gilt für Effekte und Umgebungsgeräusche

var _streams := {}               # Name -> Array[AudioStream]
var _last_variant := {}          # Name -> zuletzt gespielte Variante (kein Doppel hintereinander)
var _pool: Array[AudioStreamPlayer] = []
var _pool_2d: Array[AudioStreamPlayer2D] = []
var _next := 0
var _next_2d := 0

var _music: AudioStreamPlayer
var _alert: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _lp_music: AudioEffectLowPassFilter
var _lp_ambience: AudioEffectLowPassFilter

var _fade_in := 0.0              # sanfter Einstieg beim Spielstart
var _muffle := 0.0               # 0 = offen, 1 = Menü (gedämpft)
var _alert_level := 0.0
var _hostile_hold := 0.0
var _shelter := 0.0
var _shelter_target := 0.0
var _poll_t := 0.0
var _save_t := -1.0
var _quitting := false
var _quit_fade := 1.0
var _extra_loops: Array[AudioStreamPlayer2D] = []     # z. B. das Lagerfeuer-Knistern


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS          # Musik und Menütöne laufen auch bei Pause
	get_tree().auto_accept_quit = false              # wir beenden selbst, mit sanftem Ausblenden
	_setup_buses()
	_load_settings()
	_load_streams()
	_make_players()
	_apply_volumes()
	_start_loops()
	Game.level_up.connect(func(_lv: int) -> void: play("levelup"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()


## Beendet das Spiel: Musik blendet kurz aus, die Wiedergabe wird sauber gestoppt, dann ist Schluss.
## (Ohne das Stoppen meldet Godot beim Beenden "nicht freigegebene Objekte".)
func quit_game() -> void:
	if _quitting:
		return
	_quitting = true
	var tw := create_tween()
	tw.tween_property(self, "_quit_fade", 0.0, 0.5)
	await tw.finished
	for p in [_music, _alert, _wind]:
		if p != null:
			p.stop()
	for p2 in _extra_loops:
		if is_instance_valid(p2):
			p2.stop()
	for p3 in _pool:
		p3.stop()
	for p4 in _pool_2d:
		p4.stop()
	await get_tree().create_timer(0.25).timeout
	get_tree().quit()


# --------------------------------------------------------------------- Öffentlich
func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	var stream := _pick(sound)
	if stream == null:
		return
	var p := _free_player()
	p.stream = stream
	p.volume_db = float(SOUNDS[sound][1]) + volume_db
	p.pitch_scale = pitch * (1.0 + randf_range(-1.0, 1.0) * float(SOUNDS[sound][2]))
	p.play()


func play_at(sound: String, pos: Vector2, volume_db := 0.0, pitch := 1.0) -> void:
	var stream := _pick(sound)
	if stream == null:
		return
	var p := _free_player_2d()
	p.stream = stream
	p.global_position = pos
	p.volume_db = float(SOUNDS[sound][1]) + volume_db
	p.pitch_scale = pitch * (1.0 + randf_range(-1.0, 1.0) * float(SOUNDS[sound][2]))
	p.play()


## Meldet einen weiteren Endlos-Klang an, der beim Beenden gestoppt werden soll.
func register_loop(p: AudioStreamPlayer2D) -> void:
	for i in range(_extra_loops.size() - 1, -1, -1):      # Reste von neu geladenen Szenen entfernen
		if not is_instance_valid(_extra_loops[i]):
			_extra_loops.remove_at(i)
	_extra_loops.append(p)


## Liefert eine Endlos-Schleife aus res://audio/<file>.ogg (oder null, falls die Datei fehlt).
func loop_stream(file: String) -> AudioStream:
	var path := "res://audio/%s.ogg" % file
	if not ResourceLoader.exists(path):
		push_warning("Klang fehlt: " + path)
		return null
	var s: AudioStream = load(path)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	return s


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_volumes()
	_save_t = 0.6


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply_volumes()
	_save_t = 0.6


# --------------------------------------------------------------------- Aufbau
func _setup_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_AMBIENCE, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	# Musik und Ambiente bekommen einen Tiefpass, der im Menü zugeht
	_lp_music = AudioEffectLowPassFilter.new()
	_lp_music.cutoff_hz = OPEN_CUTOFF
	AudioServer.add_bus_effect(AudioServer.get_bus_index(BUS_MUSIC), _lp_music)
	_lp_ambience = AudioEffectLowPassFilter.new()
	_lp_ambience.cutoff_hz = OPEN_CUTOFF
	AudioServer.add_bus_effect(AudioServer.get_bus_index(BUS_AMBIENCE), _lp_ambience)
	# Effekte: ein kleiner, weicher Raum
	var room := AudioEffectReverb.new()
	room.room_size = 0.35
	room.damping = 0.7
	room.wet = 0.10
	room.dry = 1.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index(BUS_SFX), room)


func _load_streams() -> void:
	for sound_name in SOUNDS:
		var list: Array = []
		for file in SOUNDS[sound_name][0]:
			var path := "res://audio/%s.wav" % file
			if ResourceLoader.exists(path):
				list.append(load(path))
			else:
				push_warning("Klang fehlt: " + path)
		_streams[sound_name] = list


func _make_players() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_pool.append(p)
	for i in 14:
		var p2 := AudioStreamPlayer2D.new()
		p2.bus = BUS_SFX
		p2.max_distance = 360.0              # weiter weg ist der Effekt nicht mehr zu hören
		p2.attenuation = 1.2                 # gemessen: -8 dB am Bildschirmrand, -30 dB bei 330 px
		p2.panning_strength = 2.0            # gemessen: +-5 dB links/rechts bei 120 px, +-11 dB bei 240 px
		add_child(p2)
		_pool_2d.append(p2)


func _loop_player(file: String, bus: String) -> AudioStreamPlayer:
	var s := loop_stream(file)
	if s == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = bus
	p.volume_db = -60.0
	add_child(p)
	return p


func _start_loops() -> void:
	_music = _loop_player("music_calm", BUS_MUSIC)
	_alert = _loop_player("music_alert", BUS_MUSIC)      # läuft immer mit (stumm), damit beide synchron bleiben
	_wind = _loop_player("amb_wind", BUS_AMBIENCE)
	for p in [_music, _alert, _wind]:
		if p != null:
			p.play()


func _pick(sound: String) -> AudioStream:
	var list: Array = _streams.get(sound, [])
	if list.is_empty():
		return null
	var i := randi() % list.size()
	if list.size() > 1 and i == int(_last_variant.get(sound, -1)):
		i = (i + 1 + randi() % (list.size() - 1)) % list.size()
	_last_variant[sound] = i
	return list[i]


func _free_player() -> AudioStreamPlayer:
	for k in _pool.size():
		var p := _pool[(_next + k) % _pool.size()]
		if not p.playing:
			_next = (_next + k + 1) % _pool.size()
			return p
	_next = (_next + 1) % _pool.size()          # alle belegt: ältesten Klang abbrechen
	return _pool[_next]


func _free_player_2d() -> AudioStreamPlayer2D:
	for k in _pool_2d.size():
		var p := _pool_2d[(_next_2d + k) % _pool_2d.size()]
		if not p.playing:
			_next_2d = (_next_2d + k + 1) % _pool_2d.size()
			return p
	_next_2d = (_next_2d + 1) % _pool_2d.size()
	return _pool_2d[_next_2d]


# --------------------------------------------------------------------- Laufend
func _process(delta: float) -> void:
	_fade_in = minf(1.0, _fade_in + delta / 5.0)
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = 0.25
		_poll_world()
	var rate := 0.6 if _hostile_hold > 0.0 else 0.28
	_alert_level = move_toward(_alert_level, 1.0 if _hostile_hold > 0.0 else 0.0, delta * rate)
	_shelter = move_toward(_shelter, _shelter_target, delta * 0.8)

	# Menü: Tiefpass zufahren, ein wenig leiser
	_muffle = move_toward(_muffle, 1.0 if get_tree().paused else 0.0, delta * 2.5)
	var k := _muffle * _muffle * (3.0 - 2.0 * _muffle)
	var cutoff := exp(lerpf(log(OPEN_CUTOFF), log(MENU_CUTOFF), k))
	_lp_music.cutoff_hz = cutoff
	_lp_ambience.cutoff_hz = cutoff
	var duck := -3.0 * k

	if _music != null:
		_music.volume_db = MUSIC_DB + duck + _level_db(_fade_in * _quit_fade)
	if _alert != null:
		_alert.volume_db = ALERT_DB + duck + _level_db(_alert_level * _quit_fade)
	if _wind != null:
		_wind.volume_db = WIND_DB + duck + _level_db(_fade_in * _quit_fade) + SHELTER_DB * _shelter

	if _save_t > 0.0:
		_save_t -= delta
		if _save_t <= 0.0:
			_save_settings()


func _level_db(level: float) -> float:
	return -80.0 if level < 0.002 else linear_to_db(level * level)


## Schaut zweimal pro Sekunde nach: Sind Gegner hinter dem Spieler her? Wie weit ist das Lagerfeuer?
func _poll_world() -> void:
	var tree := get_tree()
	var player := tree.get_first_node_in_group("player") as Player
	var hostile := false
	if player != null and not player.dead:
		for node in tree.get_nodes_in_group("enemies"):
			var e := node as Enemy
			if e != null and e.is_hostile():
				hostile = true
				break
	_hostile_hold = 3.5 if hostile else maxf(0.0, _hostile_hold - 0.25)
	var fire := tree.get_first_node_in_group("campfire") as Node2D
	if player != null and fire != null:
		var dist := player.global_position.distance_to(fire.global_position)
		_shelter_target = clampf(1.0 - (dist - 50.0) / 190.0, 0.0, 1.0)
	else:
		_shelter_target = 0.0


# --------------------------------------------------------------------- Einstellungen
func _apply_volumes() -> void:
	_set_bus(BUS_MUSIC, music_volume)
	_set_bus(BUS_AMBIENCE, sfx_volume)
	_set_bus(BUS_SFX, sfx_volume)


func _set_bus(bus_name: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_mute(i, v < 0.01)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v * v, 0.0001)))     # weiche, ohrgerechte Kurve


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
		sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)                      # andere Einstellungen nicht überschreiben
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.save(SETTINGS_PATH)
