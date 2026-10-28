class_name Hud
extends CanvasLayer
## On-screen interface: status bars, hive marker, touch controls and menus.

const JOY_RADIUS := 95.0
const HONEY := Color(1.0, 0.76, 0.2)
const TEXT_DIM := Color(1.0, 0.95, 0.82, 0.75)

var bee: Bee
var hive: Hive
var joy := Vector2.ZERO ## Virtual joystick, -1..1 on each axis.
var menu_open := false

var _touch := false
var _root: Control
var _overlay: Control
var _honey_label: Label
var _bars := {}
var _prompt: Label
var _toast: Label
var _toast_tween: Tween
var _hive_panel: PanelContainer
var _hive_stats: Label
var _upgrade_rows := {}
var _pause_panel: PanelContainer
var _intro_panel: PanelContainer
var _queen_panel: PanelContainer
var _queen_text: Label
var _quest_text: Label
var _quest_bar: ProgressBar
var _claim_button: Button
var _quest_label: Label
var _interact_button: TouchScreenButton
var _interact_label: Label
var _fade: ColorRect
var _cam_button: Button
var _quality_button: Button
var _buttons: Array[TouchScreenButton] = []
var _hive_button: TouchScreenButton
var _joy_index := -1
var _joy_center := Vector2.ZERO
var _look_index := -1
var _look_delta := Vector2.ZERO
var _textures := {}


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_touch = DisplayServer.is_touchscreen_available()
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_root.add_child(_overlay)

	_build_status()
	_build_labels()
	_build_hive_panel()
	_build_pause_panel()
	_build_intro_panel()
	_build_queen_panel()
	_fade = ColorRect.new()
	_fade.color = Color(0.05, 0.03, 0.0, 0.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)
	if _touch:
		_build_touch_controls()
	get_viewport().size_changed.connect(_layout)
	_layout()
	Game.message.connect(show_toast)
	if not Game.seen_intro:
		_intro_panel.visible = true
	_update_menu_state()


func take_look() -> Vector2:
	var d := _look_delta
	_look_delta = Vector2.ZERO
	return d


func set_prompt(text: String) -> void:
	_prompt.text = text


func show_toast(text: String) -> void:
	_toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(3.2)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.8)


func toggle_pause() -> void:
	var paused := not _pause_panel.visible
	_hive_panel.visible = false
	_pause_panel.visible = paused
	get_tree().paused = paused
	_refresh_settings()
	_update_menu_state()
	Game.save_game()


func toggle_hive() -> void:
	_hive_panel.visible = not _hive_panel.visible
	_update_menu_state()


func open_queen() -> void:
	_refresh_queen()
	_queen_panel.visible = true
	_update_menu_state()


func close_queen() -> void:
	_queen_panel.visible = false
	_update_menu_state()


## Fades to black, runs the callback, then fades back in.
func fade(callback: Callable) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.3)
	tween.tween_callback(callback)
	tween.tween_property(_fade, "color:a", 0.0, 0.45)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause"):
		if _queen_panel.visible:
			close_queen()
		elif _hive_panel.visible:
			toggle_hive()
		elif not _intro_panel.visible:
			toggle_pause()
	if not get_tree().paused and not _intro_panel.visible:
		if Input.is_action_just_pressed("toggle_camera"):
			Game.third_person = not Game.third_person
			show_toast("Third-person view" if Game.third_person else "First-person view")
		if Input.is_action_just_pressed("interact") and not menu_open:
			bee.interact()
		if Input.is_action_just_pressed("hive_menu") and not _queen_panel.visible:
			if _hive_panel.visible or bee.at_hive:
				toggle_hive()
			else:
				show_toast("Fly back to the hive entrance to open the hive.")
	if _hive_panel.visible:
		if not bee.at_hive:
			toggle_hive()
		else:
			_refresh_hive()
	if _hive_button:
		_hive_button.visible = bee.at_hive and not menu_open
	if _interact_button:
		var labels := {"enter": "ENTER", "exit": "EXIT", "talk": "TALK"}
		var what := bee.interaction()
		_interact_button.visible = what != "" and not menu_open
		_interact_label.text = labels.get(what, "")
	if _queen_panel.visible:
		_refresh_queen()
	_update_status()
	_overlay.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _queen_panel.visible:
			close_queen()
		elif _hive_panel.visible:
			toggle_hive()
		elif not _intro_panel.visible:
			toggle_pause()


func _input(event: InputEvent) -> void:
	if not _touch:
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			if menu_open or _on_button(e.position):
				return
			if e.position.x < _root.size.x * 0.42 and _joy_index < 0:
				_joy_index = e.index
				_joy_center = e.position
				joy = Vector2.ZERO
			elif _look_index < 0:
				_look_index = e.index
		elif e.index == _joy_index:
			_joy_index = -1
			joy = Vector2.ZERO
		elif e.index == _look_index:
			_look_index = -1
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _joy_index:
			var v := d.position - _joy_center
			if v.length() > JOY_RADIUS:
				_joy_center = d.position - v.normalized() * JOY_RADIUS # base follows the thumb
			joy = (d.position - _joy_center) / JOY_RADIUS
		elif d.index == _look_index:
			_look_delta += d.relative


func _on_button(pos: Vector2) -> bool:
	for b in _buttons:
		if b.visible:
			var r: int = b.get_meta("radius")
			if Rect2(b.position, Vector2.ONE * r * 2).has_point(pos):
				return true
	return false


func _update_menu_state() -> void:
	menu_open = _pause_panel.visible or _hive_panel.visible or _intro_panel.visible or _queen_panel.visible
	if menu_open:
		joy = Vector2.ZERO
		_joy_index = -1
		_look_index = -1
	if not _touch:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if menu_open else Input.MOUSE_MODE_CAPTURED
	for b in _buttons:
		if b != _hive_button and b != _interact_button:
			b.visible = not menu_open


# --- building the interface ---------------------------------------------------

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 24
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.12, 0.08, 0.03, 0.8)
	panel.set_corner_radius_all(18)
	panel.set_border_width_all(2)
	panel.border_color = Color(1.0, 0.75, 0.2, 0.55)
	panel.set_content_margin_all(18)
	t.set_stylebox("panel", "PanelContainer", panel)
	var colors := {"normal": Color(0.96, 0.68, 0.12), "hover": Color(1.0, 0.78, 0.25),
		"pressed": Color(0.82, 0.55, 0.08), "disabled": Color(0.45, 0.38, 0.28, 0.7)}
	for state in colors:
		var sb := StyleBoxFlat.new()
		sb.bg_color = colors[state]
		sb.set_corner_radius_all(14)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		t.set_stylebox(state, "Button", sb)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color(0.2, 0.11, 0.02))
	t.set_color("font_hover_color", "Button", Color(0.2, 0.11, 0.02))
	t.set_color("font_pressed_color", "Button", Color(0.2, 0.11, 0.02))
	t.set_color("font_disabled_color", "Button", Color(0.9, 0.85, 0.75, 0.6))
	t.set_color("font_color", "Label", Color(1.0, 0.97, 0.88))
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.55))
	t.set_constant("outline_size", "Label", 5)
	t.set_color("font_color", "CheckButton", Color(1.0, 0.97, 0.88))
	return t


func _label(text: String, size: int, color := Color(1.0, 0.97, 0.88)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 58
	b.pressed.connect(callback)
	return b


func _build_status() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var honey_row := HBoxContainer.new()
	honey_row.add_theme_constant_override("separation", 10)
	box.add_child(honey_row)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(36, 36)
	icon.draw.connect(func() -> void: _draw_hex(icon, Vector2(18, 18), 16.0, HONEY))
	honey_row.add_child(icon)
	_honey_label = _label("", 30, HONEY)
	honey_row.add_child(_honey_label)
	_bars["nectar"] = _add_bar(box, "Nectar", Color(1.0, 0.6, 0.1))
	_bars["pollen"] = _add_bar(box, "Pollen", Color(1.0, 0.9, 0.25))
	_bars["energy"] = _add_bar(box, "Energy", Color(0.45, 0.88, 0.35))
	_quest_label = _label("", 16, Color(1.0, 0.9, 0.65))
	_quest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_label.custom_minimum_size.x = 330
	box.add_child(_quest_label)


func _add_bar(parent: Control, title: String, color: Color) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := _label(title, 19)
	l.custom_minimum_size.x = 76
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(160, 20)
	bar.show_percentage = false
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(8)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(8)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	row.add_child(bar)
	var value := _label("", 17, TEXT_DIM)
	value.custom_minimum_size.x = 76
	row.add_child(value)
	return [bar, value]


func _build_labels() -> void:
	_toast = _label("", 24)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.anchor_left = 0.2
	_toast.anchor_right = 0.8
	_toast.offset_top = 24
	_toast.offset_bottom = 110
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toast)
	_prompt = _label("", 24, Color(1.0, 0.9, 0.6))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.anchor_left = 0.25
	_prompt.anchor_right = 0.75
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.offset_top = -70
	_prompt.offset_bottom = -30
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_prompt)
	if not _touch:
		var hint := _label("WASD fly   Mouse look   Space / Q up / down   Shift boost   V camera   H hive   Esc pause", 16, TEXT_DIM)
		hint.anchor_top = 1.0
		hint.anchor_bottom = 1.0
		hint.offset_left = 18
		hint.offset_top = -30
		hint.offset_bottom = -6
		_root.add_child(hint)


func _panel(width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size.x = width
	panel.visible = false
	_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	return box


func _build_hive_panel() -> void:
	var box := _panel(780)
	_hive_panel = box.get_parent() as PanelContainer
	box.add_child(_label("The Hive", 36, HONEY))
	_hive_stats = _label("", 19, TEXT_DIM)
	box.add_child(_hive_stats)
	box.add_child(HSeparator.new())
	for id in Game.UPGRADES:
		var info: Dictionary = Game.UPGRADES[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		box.add_child(row)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 0)
		row.add_child(text)
		text.add_child(_label(info["name"], 24))
		text.add_child(_label(info["desc"], 17, TEXT_DIM))
		var level := _label("", 19, TEXT_DIM)
		level.custom_minimum_size.x = 80
		level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(level)
		var buy := _button("", _buy.bind(id))
		buy.custom_minimum_size = Vector2(250, 56)
		buy.add_theme_font_size_override("font_size", 19)
		row.add_child(buy)
		_upgrade_rows[id] = [level, buy]
	box.add_child(HSeparator.new())
	box.add_child(_button("Back to the meadow", toggle_hive))


func _build_pause_panel() -> void:
	var box := _panel(620)
	_pause_panel = box.get_parent() as PanelContainer
	box.add_child(_label("Paused", 36, HONEY))
	box.add_child(_button("Resume", toggle_pause))
	_cam_button = _button("", func() -> void:
		Game.third_person = not Game.third_person
		_refresh_settings())
	box.add_child(_cam_button)
	_quality_button = _button("", func() -> void:
		Game.high_quality = not Game.high_quality
		Game.settings_changed.emit()
		_refresh_settings())
	box.add_child(_quality_button)
	var row := HBoxContainer.new()
	box.add_child(row)
	row.add_child(_label("Look speed", 20))
	var slider := HSlider.new()
	slider.min_value = 0.3
	slider.max_value = 2.5
	slider.step = 0.05
	slider.value = Game.look_sensitivity
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float) -> void: Game.look_sensitivity = v)
	row.add_child(slider)
	var invert := CheckButton.new()
	invert.text = "Invert look up / down"
	invert.button_pressed = Game.invert_y
	invert.toggled.connect(func(on: bool) -> void: Game.invert_y = on)
	box.add_child(invert)


func _build_intro_panel() -> void:
	var box := _panel(700)
	_intro_panel = box.get_parent() as PanelContainer
	box.add_child(_label("Bee Sim", 44, HONEY))
	var how := _label("You are a honeybee! Fly to flowers and hover close to sip nectar and gather pollen. "
		+ "Carry pollen between flowers of the same kind to pollinate them, and new flowers will sprout. "
		+ "Bring your haul home to the hive, where nectar ripens into honey. Fly inside the hive to meet Queen Melissa, "
		+ "who has tasks for you, and spend your honey on upgrades and worker bees.", 20)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.custom_minimum_size.x = 660
	box.add_child(how)
	var controls := "Left thumb: fly.  Right thumb: look around.  UP / DOWN: climb and dive.  BOOST: go fast.  CAM: switch view." \
		if _touch else "WASD fly, mouse to look, Space / Q to climb and dive, Shift to boost, V to switch camera, H for the hive."
	var c := _label(controls, 18, TEXT_DIM)
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.custom_minimum_size.x = 660
	box.add_child(c)
	box.add_child(_button("Start flying!", func() -> void:
		_intro_panel.visible = false
		Game.seen_intro = true
		Game.save_game()
		_update_menu_state()))


func _build_queen_panel() -> void:
	var box := _panel(700)
	_queen_panel = box.get_parent() as PanelContainer
	box.add_child(_label("Queen Melissa", 38, HONEY))
	_queen_text = _label("", 20)
	_queen_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_queen_text.custom_minimum_size.x = 660
	box.add_child(_queen_text)
	box.add_child(HSeparator.new())
	_quest_text = _label("", 22, Color(1.0, 0.9, 0.65))
	_quest_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_text.custom_minimum_size.x = 660
	box.add_child(_quest_text)
	_quest_bar = ProgressBar.new()
	_quest_bar.custom_minimum_size = Vector2(660, 24)
	_quest_bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(10)
	var fg := StyleBoxFlat.new()
	fg.bg_color = HONEY
	fg.set_corner_radius_all(10)
	_quest_bar.add_theme_stylebox_override("background", bg)
	_quest_bar.add_theme_stylebox_override("fill", fg)
	box.add_child(_quest_bar)
	_claim_button = _button("", func() -> void:
		var reward := Game.claim_quest()
		if reward > 0.0:
			show_toast("The Queen rewards you with %d honey!" % int(reward))
		_refresh_queen())
	box.add_child(_claim_button)
	box.add_child(_button("Goodbye, Your Majesty", close_queen))


func _refresh_queen() -> void:
	var q := Game.quest()
	if q["done"]:
		_queen_text.text = "Splendid work, my dear! The whole colony is buzzing about you. Here is your reward."
	elif Game.quest_index == 0 and q["progress"] <= 0.0:
		_queen_text.text = "Welcome, little one. I am Queen Melissa. Every bee in this hive is my child, and each of us works for the colony. Will you help us grow strong?"
	else:
		_queen_text.text = "The colony is counting on you. Come back to me when the task is done."
	_quest_text.text = "Task %d: %s" % [Game.quest_index + 1, q["text"]]
	_quest_bar.max_value = q["target"]
	_quest_bar.value = q["progress"]
	_claim_button.disabled = not q["done"]
	if q["done"]:
		_claim_button.text = "Claim %d honey" % int(q["reward"])
	else:
		_claim_button.text = "%d / %d done" % [int(q["progress"]), int(q["target"])]


func _build_touch_controls() -> void:
	_buttons.append(_touch_button("UP", "ascend", 62))
	_buttons.append(_touch_button("DOWN", "descend", 52))
	_buttons.append(_touch_button("BOOST", "boost", 56))
	_buttons.append(_touch_button("CAM", "toggle_camera", 40))
	_buttons.append(_touch_button("II", "pause", 40))
	_hive_button = _touch_button("HIVE", "hive_menu", 54)
	_buttons.append(_hive_button)
	_interact_button = _touch_button("", "interact", 54)
	_interact_label = _interact_button.get_child(0) as Label
	_buttons.append(_interact_button)


func _touch_button(text: String, action: String, radius: int) -> TouchScreenButton:
	var b := TouchScreenButton.new()
	b.texture_normal = _circle_texture(radius, Color(0.1, 0.07, 0.02, 0.35), Color(1.0, 0.8, 0.3, 0.75))
	b.texture_pressed = _circle_texture(radius, Color(1.0, 0.75, 0.2, 0.55), Color(1.0, 0.92, 0.55, 0.95))
	b.action = action
	b.visibility_mode = TouchScreenButton.VISIBILITY_TOUCHSCREEN_ONLY
	b.set_meta("radius", radius)
	b.set_meta("action", action)
	var l := Label.new()
	l.text = text
	l.size = Vector2.ONE * radius * 2
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 22 if radius > 45 else 18)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 4)
	b.add_child(l)
	add_child(b)
	return b


func _circle_texture(radius: int, fill: Color, ring: Color) -> ImageTexture:
	var key := "%d_%s_%s" % [radius, fill, ring]
	if _textures.has(key):
		return _textures[key]
	var size := radius * 2
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(radius, radius) - Vector2(0.5, 0.5)
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(c)
			var col := fill.lerp(ring, clampf(d - (radius - 6.0), 0.0, 1.0))
			col.a *= clampf(radius - d, 0.0, 1.0)
			img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex


func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	for b in _buttons:
		var r: int = b.get_meta("radius")
		var center := Vector2.ZERO
		match b.get_meta("action"):
			"ascend":
				center = Vector2(s.x - 120, s.y - 255)
			"descend":
				center = Vector2(s.x - 120, s.y - 105)
			"boost":
				center = Vector2(s.x - 270, s.y - 115)
			"hive_menu":
				center = Vector2(s.x - 275, s.y - 265)
			"interact":
				center = Vector2(s.x - 420, s.y - 150)
			"toggle_camera":
				center = Vector2(s.x - 190, 64)
			"pause":
				center = Vector2(s.x - 80, 64)
		b.position = center - Vector2(r, r)


# --- updating -------------------------------------------------------------------

func _update_status() -> void:
	_honey_label.text = "Honey  %d" % int(Game.honey)
	_set_bar("nectar", Game.nectar, Game.nectar_capacity())
	_set_bar("pollen", Game.pollen, Game.pollen_capacity())
	_set_bar("energy", Game.energy, Game.max_energy())
	var q := Game.quest()
	if q["done"]:
		_quest_label.text = "Task done! Visit the Queen inside the hive."
	else:
		_quest_label.text = "Queen's task: %s (%d/%d)" % [q["text"], int(q["progress"]), int(q["target"])]


func _set_bar(key: String, value: float, maximum: float) -> void:
	var row: Array = _bars[key]
	var bar: ProgressBar = row[0]
	var label: Label = row[1]
	bar.max_value = maximum
	bar.value = value
	label.text = "%d / %d" % [int(value), int(maximum)]


func _refresh_hive() -> void:
	_hive_stats.text = "Honey %d     Nectar ripening %d     Pollen stored %d\nWorker bees %d     Flowers pollinated %d" % [
		int(Game.honey), ceili(Game.hive_nectar), int(Game.hive_pollen), Game.levels["workers"], Game.pollinated]
	for id in _upgrade_rows:
		var row: Array = _upgrade_rows[id]
		var level_label: Label = row[0]
		var buy: Button = row[1]
		var level: int = Game.levels[id]
		var max_level: int = Game.UPGRADES[id]["max"]
		level_label.text = "Lv %d/%d" % [level, max_level]
		if level >= max_level:
			buy.text = "Maxed out"
			buy.disabled = true
		else:
			var cost := Game.upgrade_cost(id)
			buy.text = "%d honey" % cost.x + (" + %d pollen" % cost.y if cost.y > 0.0 else "")
			buy.disabled = not Game.can_upgrade(id)


func _refresh_settings() -> void:
	_cam_button.text = "Camera: " + ("third person" if Game.third_person else "first person")
	_quality_button.text = "Graphics: " + ("high" if Game.high_quality else "battery saver")


func _buy(id: String) -> void:
	if Game.buy_upgrade(id):
		show_toast("%s upgraded!" % Game.UPGRADES[id]["name"])


# --- overlay drawing ----------------------------------------------------------

func _draw_overlay() -> void:
	if menu_open:
		return
	if _touch:
		var base := _joy_center if _joy_index >= 0 else Vector2(180, _root.size.y - 170)
		_overlay.draw_circle(base, JOY_RADIUS, Color(1, 1, 1, 0.08))
		_overlay.draw_arc(base, JOY_RADIUS, 0.0, TAU, 48, Color(1.0, 0.85, 0.4, 0.5), 3.0, true)
		_overlay.draw_circle(base + joy * JOY_RADIUS, 40.0, Color(1.0, 0.8, 0.3, 0.5))
	if not Game.third_person:
		_overlay.draw_arc(_root.size * 0.5, 6.0, 0.0, TAU, 20, Color(1, 1, 1, 0.5), 2.0, true)
	_draw_hive_marker()


func _draw_hive_marker() -> void:
	if not bee or not hive:
		return
	var inside := bee.world.inside
	var goal := bee.world.interior.queen_position() if inside else hive.entrance
	var dist := bee.global_position.distance_to(goal)
	if dist < (2.5 if inside else 6.0):
		return
	var cam := bee.camera
	var target := goal + Vector3.UP * (1.0 if inside else 2.5)
	var size := _root.size
	var center := size * 0.5
	var margin := 70.0
	var depth := (cam.global_transform.affine_inverse() * target).z
	if absf(depth) < 0.05:
		return
	var behind := cam.is_position_behind(target)
	var p := cam.unproject_position(target)
	var inner := Rect2(Vector2.ONE * margin, size - Vector2.ONE * margin * 2.0)
	var color := HONEY
	color.a = 0.9
	if behind or not inner.has_point(p):
		var dir := p - center
		if behind:
			dir = -dir
		if dir.length() < 1.0:
			dir = Vector2.DOWN
		var half := center - Vector2.ONE * margin
		var k := minf(half.x / absf(dir.x) if absf(dir.x) > 0.001 else INF, half.y / absf(dir.y) if absf(dir.y) > 0.001 else INF)
		p = center + dir * k
		var n := dir.normalized()
		var tip := p + n * 34.0
		_overlay.draw_colored_polygon(PackedVector2Array([tip, p + n * 20.0 + n.orthogonal() * 10.0,
			p + n * 20.0 - n.orthogonal() * 10.0]), color)
	_draw_hex(_overlay, p, 18.0, color)
	var font := ThemeDB.fallback_font
	if Game.quest()["done"]:
		_overlay.draw_string(font, p + Vector2(-20, 8), "!", HORIZONTAL_ALIGNMENT_CENTER, 40, 24, Color(0.3, 0.15, 0.0))
	_overlay.draw_string_outline(font, p + Vector2(-60, 40), "%d m" % int(dist), HORIZONTAL_ALIGNMENT_CENTER, 120, 18, 4, Color(0, 0, 0, 0.6))
	_overlay.draw_string(font, p + Vector2(-60, 40), "%d m" % int(dist), HORIZONTAL_ALIGNMENT_CENTER, 120, 18, Color.WHITE)


func _draw_hex(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 6:
		pts.append(c + Vector2.from_angle(TAU * i / 6.0 + PI / 6.0) * r)
	ci.draw_colored_polygon(pts, color)
	pts.append(pts[0])
	ci.draw_polyline(pts, Color(0.35, 0.2, 0.02), 2.5, true)
