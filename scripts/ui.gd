extends CanvasLayer
class_name GameUI
## Oberfläche: HUD, Fähigkeitenbaum, Pause und der Bildschirm nach dem Erschöpftwerden.
## Alles wird hier im Code gebaut – Farben und Layout stehen oben in den Konstanten.

signal respawn_requested

const TEXT := Color(0.96, 0.94, 0.88)
const TEXT_DIM := Color(0.66, 0.72, 0.82)
const PANEL_BG := Color(0.07, 0.10, 0.18, 0.95)
const GOLD := Color(0.97, 0.76, 0.42)

# Layout des Fähigkeitenbaums (Pixel im 1280x720-Fenster)
const PANEL_SIZE := Vector2(780, 640)
const NODE_SIZE := Vector2(200, 62)
const COL_STEP := 224.0
const ROOT_CENTER := Vector2(390, 150)
const BUS_Y := 198.0
const CAPTION_Y := 206.0
const TIER0_Y := 240.0
const TIER_STEP := 80.0

var player: Player

var root: Control
# HUD
var level_label: Label
var health_bar: ProgressBar
var health_label: Label
var xp_bar: ProgressBar
var points_hint: Label
var rest_label: Label
var toast_label: Label
# Fähigkeitenbaum
var skill_dim: ColorRect
var skill_panel: Panel
var lines: TreeLines
var skill_points_label: Label
var skill_summary_label: Label
var root_label: Label
var node_buttons := {}            # Ast -> Array[Button]
# Pause / Tod
var pause_dim: ColorRect
var death_dim: ColorRect
var respawn_button: Button
var resume_button: Button
var _toast_tween: Tween
var _quiet_focus := false          # kein Tick, wenn der Fokus automatisch gesetzt wird


## Zeichnet die Verbindungslinien des Baums (liegt hinter den Knöpfen).
class TreeLines extends Control:
	var segments: Array = []            # [von, bis, Farbe]
	var root_center := Vector2.ZERO

	func _draw() -> void:
		for s in segments:
			draw_line(s[0], s[1], s[2], 3.0, true)
		draw_circle(root_center, 27.0, Color(0.1, 0.14, 0.24, 1.0))
		draw_arc(root_center, 27.0, 0.0, TAU, 40, Color(0.97, 0.76, 0.42), 3.0, true)


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS       # Oberfläche läuft auch bei Pause weiter
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Game.ui_font != null:
		var th := Theme.new()
		th.default_font = Game.ui_font
		th.default_font_size = 18
		root.theme = th
	add_child(root)
	_build_hud()
	_build_skill_tree()
	_build_pause_menu()
	_build_death_screen()
	_build_toast()

	Game.xp_changed.connect(_refresh_hud)
	Game.skills_changed.connect(_refresh_tree)
	Game.stats_changed.connect(_refresh_tree)
	Game.level_up.connect(_on_level_up)
	_refresh_hud()
	_refresh_tree()


func bind_player(p: Player) -> void:
	player = p
	p.health_changed.connect(_on_health_changed)
	_on_health_changed(p.health, Game.max_health())


func set_resting(resting: bool) -> void:
	rest_label.visible = resting


func show_death() -> void:
	await get_tree().create_timer(1.0).timeout
	if not is_instance_valid(player) or not player.dead:
		return
	death_dim.visible = true
	death_dim.modulate.a = 0.0
	create_tween().tween_property(death_dim, "modulate:a", 1.0, 0.9)
	respawn_button.grab_focus()


# --------------------------------------------------------------------- Eingabe
func _unhandled_input(event: InputEvent) -> void:
	if death_dim.visible:
		return
	if event.is_action_pressed("skill_tree"):
		if not pause_dim.visible:
			_set_skill_tree(not skill_dim.visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		if skill_dim.visible:
			_set_skill_tree(false)
		else:
			_set_pause(not pause_dim.visible)
		get_viewport().set_input_as_handled()


func _set_skill_tree(open: bool) -> void:
	if open == skill_dim.visible:
		return
	skill_dim.visible = open
	get_tree().paused = open
	Sound.play("ui_open" if open else "ui_close")
	if not open:
		return
	_refresh_tree()
	var target: Button = null
	if Game.skill_points > 0:                  # Fokus auf die nächste kaufbare Stufe
		for branch in Game.BRANCHES:
			var rank: int = Game.ranks[branch]
			var list: Array = node_buttons[branch]
			if rank < list.size():
				target = list[rank]
				break
	if target == null:
		target = node_buttons["health"][0]
	_quiet_focus = true
	target.grab_focus()
	_quiet_focus = false


func _set_pause(open: bool) -> void:
	if open == pause_dim.visible:
		return
	pause_dim.visible = open
	get_tree().paused = open
	Sound.play("ui_open" if open else "ui_close")
	if open:
		_quiet_focus = true
		resume_button.grab_focus()
		_quiet_focus = false


func _on_node_pressed(branch: String, tier: int) -> void:
	var rank: int = Game.ranks[branch]
	if tier < rank:
		return
	if tier > rank:
		Sound.play("deny")
		_toast("Schalte zuerst die Fähigkeit davor frei.")
	elif Game.skill_points <= 0:
		Sound.play("deny")
		_toast("Dir fehlt ein Fähigkeitspunkt – besiege Gegner, um aufzusteigen.")
	else:
		Sound.play("unlock")
		Game.unlock_next(branch)


# --------------------------------------------------------------------- Aktualisieren
func _on_health_changed(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "%d / %d" % [current, maximum]


func _refresh_hud() -> void:
	if level_label == null:
		return
	level_label.text = "Stufe %d" % Game.level
	xp_bar.max_value = Game.xp_to_next()
	xp_bar.value = Game.xp
	var pts := Game.skill_points
	points_hint.visible = pts > 0
	points_hint.text = "%d Fähigkeitspunkt%s – K drücken" % [pts, "" if pts == 1 else "e"]


func _on_level_up(new_level: int) -> void:
	_toast("Stufe %d erreicht!  Mit K öffnest du den Fähigkeitenbaum." % new_level, GOLD)


func _refresh_tree() -> void:
	if skill_panel == null:
		return
	skill_points_label.text = "Fähigkeitspunkte: %d" % Game.skill_points
	skill_summary_label.text = "Leben %d        Angriff %d        Verteidigung %d" % [
		Game.max_health(), Game.attack_damage(), Game.defence()]
	root_label.text = "Stufe\n%d" % Game.level

	var neutral := Color(1, 1, 1, 0.28)
	var segs: Array = []
	var cx_left := PANEL_SIZE.x * 0.5 - COL_STEP
	var cx_right := PANEL_SIZE.x * 0.5 + COL_STEP
	segs.append([ROOT_CENTER + Vector2(0, 27), Vector2(ROOT_CENTER.x, BUS_Y), neutral])
	segs.append([Vector2(cx_left, BUS_Y), Vector2(cx_right, BUS_Y), neutral])

	for col in Game.BRANCHES.size():
		var branch: String = Game.BRANCHES[col]
		var info: Dictionary = Game.TREE[branch]
		var color: Color = info["color"]
		var nodes: Array = info["nodes"]
		var rank: int = Game.ranks[branch]
		var cx := PANEL_SIZE.x * 0.5 + (col - 1) * COL_STEP
		var lit := Color(color.r, color.g, color.b, 0.95)
		var dim := Color(1, 1, 1, 0.16)

		segs.append([Vector2(cx, BUS_Y), Vector2(cx, CAPTION_Y), Color(color.r, color.g, color.b, 0.5)])
		var prev := Vector2(cx, CAPTION_Y + 28.0)
		var buttons: Array = node_buttons[branch]
		for i in nodes.size():
			var top := Vector2(cx, TIER0_Y + i * TIER_STEP)
			segs.append([prev, top, lit if rank > i else dim])
			prev = top + Vector2(0, NODE_SIZE.y)

			var btn: Button = buttons[i]
			var nd: Dictionary = nodes[i]
			btn.text = "%s\n+%d %s" % [nd["name"], nd["bonus"], info["stat"]]
			var state := "locked"
			if i < rank:
				state = "unlocked"
			elif i == rank:
				state = "available"
			_style_node(btn, state, color, Game.skill_points > 0)
	lines.segments = segs
	lines.root_center = ROOT_CENTER
	lines.queue_redraw()


# --------------------------------------------------------------------- Aufbau
func _box(bg: Color, border := Color(0, 0, 0, 0), border_w := 0, radius := 10, margin := 8.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


func _label(text: String, font_size: int, color: Color = TEXT,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.06, 0.14, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	return l


func _bar(fill: Color, bar_size: Vector2) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = bar_size
	b.show_percentage = false
	b.max_value = 100.0
	b.value = 100.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := int(bar_size.y * 0.5)
	b.add_theme_stylebox_override("background", _box(Color(0.03, 0.05, 0.11, 0.85), Color(1, 1, 1, 0.08), 1, r, 0.0))
	b.add_theme_stylebox_override("fill", _box(fill, Color(0, 0, 0, 0), 0, r, 0.0))
	return b


func _button(text: String, btn_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = btn_size
	b.size = btn_size
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_stylebox_override("normal", _box(Color(0.14, 0.20, 0.33, 1.0), GOLD.darkened(0.35), 2, 10))
	b.add_theme_stylebox_override("hover", _box(Color(0.20, 0.28, 0.44, 1.0), GOLD, 2, 10))
	b.add_theme_stylebox_override("pressed", _box(Color(0.10, 0.15, 0.26, 1.0), GOLD, 2, 10))
	b.add_theme_stylebox_override("focus", _focus_box())
	_wire_hover(b)
	b.pressed.connect(Sound.play.bind("ui_click"))
	return b


## Weicher Tick, wenn die Maus über ein Element fährt oder der Fokus (Tastatur/Controller) dorthin springt.
func _wire_hover(c: Control) -> void:
	c.mouse_entered.connect(Sound.play.bind("ui_hover"))
	c.focus_entered.connect(_on_focus_tick)


func _on_focus_tick() -> void:
	if not _quiet_focus:
		Sound.play("ui_hover")


func _focus_box() -> StyleBoxFlat:
	var f := _box(Color(0, 0, 0, 0), Color.WHITE, 3, 10)
	f.draw_center = false
	return f


func _style_node(btn: Button, state: String, color: Color, affordable: bool) -> void:
	var bg := Color(0.09, 0.12, 0.20, 0.9)
	var border := Color(1, 1, 1, 0.10)
	var txt := Color(0.52, 0.58, 0.68)
	var width := 2
	if state == "unlocked":
		bg = color.darkened(0.55)
		bg.a = 0.96
		border = color.lightened(0.2)
		txt = TEXT
	elif state == "available":
		bg = Color(0.12, 0.17, 0.28, 0.98)
		border = color if affordable else color.darkened(0.5)
		txt = TEXT if affordable else TEXT_DIM
		width = 3 if affordable else 2
	for sname in ["normal", "pressed", "disabled"]:
		btn.add_theme_stylebox_override(sname, _box(bg, border, width, 10))
	var hover_bg := bg if state == "locked" else bg.lightened(0.12)
	btn.add_theme_stylebox_override("hover", _box(hover_bg, border, width, 10))
	btn.add_theme_stylebox_override("focus", _focus_box())
	for cname in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		btn.add_theme_color_override(cname, txt)


func _build_hud() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _box(Color(0.06, 0.09, 0.17, 0.74), Color(1, 1, 1, 0.10), 1, 12, 12.0))
	root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	level_label = _label("Stufe 1", 20, GOLD)
	vb.add_child(level_label)
	health_bar = _bar(Color(0.90, 0.36, 0.36), Vector2(250, 22))
	vb.add_child(health_bar)
	health_label = _label("", 15, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	health_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	health_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	health_bar.add_child(health_label)
	xp_bar = _bar(Color(0.96, 0.78, 0.40), Vector2(250, 8))
	vb.add_child(xp_bar)
	points_hint = _label("", 16, GOLD)
	vb.add_child(points_hint)
	var pulse := create_tween().set_loops()
	pulse.tween_property(points_hint, "modulate:a", 0.5, 0.8)
	pulse.tween_property(points_hint, "modulate:a", 1.0, 0.8)

	rest_label = _label("Am Lagerfeuer erholst du dich ...", 18, Color(1.0, 0.82, 0.55), HORIZONTAL_ALIGNMENT_CENTER)
	rest_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	rest_label.offset_top = 46.0
	rest_label.offset_bottom = 76.0
	rest_label.visible = false
	root.add_child(rest_label)

	var hint := _label("WASD / Pfeile: Laufen      Leertaste / J / Linksklick: Zuschlagen      K: Fähigkeiten      Esc: Pause",
			14, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -34.0
	hint.offset_bottom = -10.0
	hint.modulate.a = 0.9
	root.add_child(hint)


func _build_skill_tree() -> void:
	skill_dim = ColorRect.new()
	skill_dim.color = Color(0.02, 0.04, 0.09, 0.62)
	skill_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	skill_dim.visible = false
	root.add_child(skill_dim)

	skill_panel = Panel.new()
	skill_panel.custom_minimum_size = PANEL_SIZE
	skill_panel.size = PANEL_SIZE
	skill_panel.add_theme_stylebox_override("panel", _box(PANEL_BG, GOLD.darkened(0.25), 2, 18))
	skill_dim.add_child(skill_panel)
	skill_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)

	var title := _label("Fähigkeiten", 30, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(0, 14)
	title.size = Vector2(PANEL_SIZE.x, 40)
	skill_panel.add_child(title)
	skill_summary_label = _label("", 17, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	skill_summary_label.position = Vector2(0, 58)
	skill_summary_label.size = Vector2(PANEL_SIZE.x, 26)
	skill_panel.add_child(skill_summary_label)
	skill_points_label = _label("", 20, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	skill_points_label.position = Vector2(0, 88)
	skill_points_label.size = Vector2(PANEL_SIZE.x, 28)
	skill_panel.add_child(skill_points_label)

	lines = TreeLines.new()
	lines.size = PANEL_SIZE
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skill_panel.add_child(lines)

	root_label = _label("", 14, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	root_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root_label.position = ROOT_CENTER - Vector2(27, 22)
	root_label.size = Vector2(54, 44)
	skill_panel.add_child(root_label)

	for col in Game.BRANCHES.size():
		var branch: String = Game.BRANCHES[col]
		var info: Dictionary = Game.TREE[branch]
		var cx := PANEL_SIZE.x * 0.5 + (col - 1) * COL_STEP
		var caption := _label(info["title"], 20, info["color"], HORIZONTAL_ALIGNMENT_CENTER)
		caption.position = Vector2(cx - NODE_SIZE.x * 0.5, CAPTION_Y)
		caption.size = Vector2(NODE_SIZE.x, 28)
		skill_panel.add_child(caption)
		var list: Array = []
		for i in (info["nodes"] as Array).size():
			var b := Button.new()
			b.position = Vector2(cx - NODE_SIZE.x * 0.5, TIER0_Y + i * TIER_STEP)
			b.size = NODE_SIZE
			b.add_theme_font_size_override("font_size", 16)
			b.pressed.connect(_on_node_pressed.bind(branch, i))
			_wire_hover(b)
			skill_panel.add_child(b)
			list.append(b)
		node_buttons[branch] = list

	var reset_btn := _button("Zurücksetzen", Vector2(180, 44))
	reset_btn.position = Vector2(PANEL_SIZE.x * 0.5 - 190.0, 572)
	reset_btn.pressed.connect(Game.reset_skills)
	skill_panel.add_child(reset_btn)
	var close_btn := _button("Schließen (K)", Vector2(180, 44))
	close_btn.position = Vector2(PANEL_SIZE.x * 0.5 + 10.0, 572)
	close_btn.pressed.connect(_set_skill_tree.bind(false))
	skill_panel.add_child(close_btn)


func _build_pause_menu() -> void:
	pause_dim = ColorRect.new()
	pause_dim.color = Color(0.02, 0.04, 0.09, 0.68)
	pause_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_dim.visible = false
	root.add_child(pause_dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_dim.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	box.add_child(_label("Pause", 44, GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_slider_row("Musik", Sound.music_volume, Sound.set_music_volume, false))
	box.add_child(_slider_row("Effekte", Sound.sfx_volume, Sound.set_sfx_volume, true))
	resume_button = _button("Weiter", Vector2(260, 48))
	resume_button.pressed.connect(_set_pause.bind(false))
	box.add_child(resume_button)
	var restart := _button("Neustart", Vector2(260, 48))
	restart.pressed.connect(_restart)
	box.add_child(restart)
	var quit := _button("Beenden", Vector2(260, 48))
	quit.pressed.connect(Sound.quit_game)
	box.add_child(quit)


## Eine Zeile mit Beschriftung und Lautstärke-Regler (0 bis 1).
func _slider_row(label_text: String, value: float, setter: Callable, ping: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var l := _label(label_text, 18, TEXT)
	l.custom_minimum_size = Vector2(80, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(170, 30)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.add_theme_stylebox_override("slider", _box(Color(0.03, 0.05, 0.11, 0.9), Color(1, 1, 1, 0.14), 1, 4, 3.0))
	var filled := _box(GOLD.darkened(0.12), Color(0, 0, 0, 0), 0, 4, 3.0)
	s.add_theme_stylebox_override("grabber_area", filled)
	s.add_theme_stylebox_override("grabber_area_highlight", filled)
	var knob := _knob(GOLD)
	for icon_name in ["grabber", "grabber_highlight", "grabber_disabled"]:
		s.add_theme_icon_override(icon_name, knob)
	s.value_changed.connect(setter)
	if ping:                                   # beim Loslassen kurz hörbar machen, wie laut Effekte sind
		s.drag_ended.connect(func(_changed: bool) -> void: Sound.play("ui_click"))
	_wire_hover(s)
	row.add_child(s)
	return row


func _knob(color: Color) -> ImageTexture:
	var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	for y in 20:
		for x in 20:
			var d := Vector2(x - 9.5, y - 9.5).length()
			if d <= 8.0:
				img.set_pixel(x, y, color.lightened(0.15) if d > 6.0 else color)
			elif d <= 9.0:
				img.set_pixel(x, y, Color(color.r, color.g, color.b, 0.5))
	return ImageTexture.create_from_image(img)


func _build_death_screen() -> void:
	death_dim = ColorRect.new()
	death_dim.color = Color(0.02, 0.03, 0.08, 0.82)
	death_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_dim.visible = false
	root.add_child(death_dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_dim.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	box.add_child(_label("Du bist erschöpft ...", 42, GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_label("Die Kälte war zu stark. Am Lagerfeuer wärmst du dich wieder auf.", 18, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	respawn_button = _button("Am Lagerfeuer aufwachen", Vector2(320, 52))
	respawn_button.pressed.connect(_on_respawn_pressed)
	box.add_child(respawn_button)


func _build_toast() -> void:
	toast_label = _label("", 20, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	toast_label.offset_top = 6.0
	toast_label.offset_bottom = 38.0
	toast_label.modulate.a = 0.0
	root.add_child(toast_label)


func _toast(msg: String, color: Color = TEXT) -> void:
	toast_label.text = msg
	toast_label.add_theme_color_override("font_color", color)
	toast_label.modulate.a = 1.0
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.6)


func _on_respawn_pressed() -> void:
	death_dim.visible = false
	respawn_requested.emit()


func _restart() -> void:
	Game.new_game()
	get_tree().reload_current_scene()
