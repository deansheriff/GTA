class_name Hud3D
extends CanvasLayer
## Everything on screen in 3D Lagos (D-021): status line and money, objective, messages (ToastStack),
## fight health, touch buttons (ENTER/EXIT, RUN, PUNCH, pause), the minimap, title cards and black
## screens for the story, the dialogue box, and the main menu, pause, settings, missions and credits.

signal action_pressed
signal punch_pressed
signal shoot_pressed
signal run_changed(held: bool)
signal new_game
signal continue_game

var world # Street3D
var info: Label
var money: Label
var objective: Label
var toasts: ToastStack
var health: ProgressBar
var act_btn: Button
var run_btn: Button
var punch_btn: Button
var shoot_btn: Button
var ammo: Label
var pause_btn: Button
var minimap: Minimap3D
var joy: Control
var dialogue: Control
var pause: PauseMenu
var _root: Control
var _title: Control
var _title_text: Label
var _title_sub: Label
var _black: ColorRect
var _menu: Control
var _theme: Theme


func setup(w) -> void:
	world = w
	layer = 10
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_theme = Theme.new()
	UiStyle.apply(_theme)
	_root.theme = _theme
	add_child(_root)
	UiStyle.fit_safe_area(_root)
	info = _label(Vector2(16, 10), 19, UiStyle.PAPER)
	money = _label(Vector2(16, 62), 23, Color("#f6d04d"))
	objective = Label.new()
	objective.anchor_left = 0.2
	objective.anchor_right = 0.8
	objective.offset_top = 104
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(objective, 24, Color("#fff4d6"))
	_root.add_child(objective)
	toasts = ToastStack.new()
	_root.add_child(toasts)
	toasts.offset_top = 170
	health = ProgressBar.new()
	health.max_value = Combat3D.PLAYER_MAX
	health.show_percentage = false
	health.custom_minimum_size = Vector2(260, 18)
	health.position = Vector2(16, 100)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#e8483a")
	health.add_theme_stylebox_override("fill", fill)
	health.visible = false
	_root.add_child(health)
	if DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"):
		joy = preload("res://ui/joystick.gd").new()
		joy.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		joy.position = Vector2(20, -180)
		_root.add_child(joy)
	act_btn = _button("ENTER", Vector2(-170, -130))
	act_btn.pressed.connect(func() -> void: action_pressed.emit())
	run_btn = _button("RUN", Vector2(-170, -250))
	run_btn.button_down.connect(func() -> void: run_changed.emit(true))
	run_btn.button_up.connect(func() -> void: run_changed.emit(false))
	punch_btn = _button("PUNCH", Vector2(-340, -130))
	punch_btn.pressed.connect(func() -> void: punch_pressed.emit())
	punch_btn.visible = false
	shoot_btn = _button("SHOOT", Vector2(-340, -250))
	shoot_btn.pressed.connect(func() -> void: shoot_pressed.emit())
	shoot_btn.visible = false
	ammo = _label(Vector2(16, 126), 20, UiStyle.PAPER)
	pause_btn = _button("II", Vector2(-96, 12), true)
	pause_btn.custom_minimum_size = Vector2(80, 64)
	pause_btn.offset_right = pause_btn.offset_left + 80
	pause_btn.pressed.connect(open_pause)
	minimap = Minimap3D.new()
	_root.add_child(minimap)
	minimap.setup(world)
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.offset_left = -232
	minimap.offset_top = 88
	dialogue = preload("res://ui/dialogue_box.gd").new()
	dialogue.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialogue.visible = false
	_root.add_child(dialogue)
	_build_title()
	pause = PauseMenu.new()
	add_child(pause)
	pause.use_theme(_theme)
	pause.open_settings.connect(func(root: Control) -> void: root.add_child(_settings_panel()))


func _label(at: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.position = at
	_style(l, size, col)
	_root.add_child(l)
	return l


func _style(l: Label, size: int, col: Color) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", UiStyle.INK)
	l.add_theme_constant_override("outline_size", 7)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _button(text: String, at: Vector2, top := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 96)
	b.add_theme_font_size_override("font_size", 24)
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.anchor_top = 0.0 if top else 1.0
	b.anchor_bottom = b.anchor_top
	b.offset_left = at.x
	b.offset_top = at.y
	b.offset_right = at.x + b.custom_minimum_size.x
	b.offset_bottom = at.y + b.custom_minimum_size.y
	_root.add_child(b)
	return b


func _build_title() -> void:
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.modulate.a = 0.0
	_root.add_child(_black)
	_title = Control.new()
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.modulate.a = 0.0
	_root.add_child(_title)
	_title_text = Label.new()
	_title_text.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_title_text.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title_text.grow_vertical = Control.GROW_DIRECTION_BOTH
	_title_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_text.add_theme_font_override("font", UiStyle.display())
	_style(_title_text, 64, UiStyle.DANFO)
	_title_text.add_theme_constant_override("outline_size", 14)
	_title.add_child(_title_text)
	_title_sub = Label.new()
	_title_sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_title_sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title_sub.offset_top = 56
	_title_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(_title_sub, 26, UiStyle.PAPER)
	_title.add_child(_title_sub)


# ---------- story presentation ----------

func show_title(text: String, sub := "", secs := 2.5, col := UiStyle.DANFO) -> void:
	_title_text.text = text
	_title_text.add_theme_color_override("font_color", col)
	_title_sub.text = sub
	var tw := create_tween()
	tw.tween_property(_title, "modulate:a", 1.0, 0.4)
	tw.tween_interval(maxf(0.2, secs - 0.8))
	tw.tween_property(_title, "modulate:a", 0.0, 0.4)
	await tw.finished


func black(secs: float) -> void:
	var tw := create_tween()
	tw.tween_property(_black, "modulate:a", 1.0, 0.15)
	tw.tween_interval(secs)
	tw.tween_property(_black, "modulate:a", 0.0, 0.6)
	await tw.finished


func say(lines: Array) -> Array:
	return await dialogue.play(lines)


func notify(text: String) -> void:
	toasts.show_toast(text)


func set_objective(text: String) -> void:
	objective.text = text


func fight_mode(on: bool, hp: int) -> void:
	health.visible = on
	health.value = hp
	punch_btn.visible = on
	var talking: bool = dialogue.visible
	if not menu_open():
		act_btn.visible = not talking
		run_btn.visible = not talking


func gun_mode(on: bool, clip: int, reserve: int) -> void:
	shoot_btn.visible = on and not dialogue.visible
	ammo.visible = on
	ammo.text = "Pistol %d / %d" % [clip, reserve]


# ---------- menus ----------

func open_pause() -> void:
	if _menu and _menu.visible:
		return
	pause.open()


func show_menu(has_save: bool) -> void:
	_menu = Control.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_menu)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.03, 0.02, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(shade)
	var v := VBoxContainer.new()
	v.anchor_left = 0.06
	v.anchor_top = 0.12
	v.add_theme_constant_override("separation", 10)
	_menu.add_child(v)
	var kicker := Label.new()
	kicker.text = "NAIJA STREET LIFE"
	_style(kicker, 26, UiStyle.PAPER)
	v.add_child(kicker)
	var t := Label.new()
	t.text = "ÈKÓ Ò NÍ BÀJẸ́"
	t.add_theme_font_override("font", UiStyle.display())
	_style(t, 72, UiStyle.DANFO)
	t.add_theme_constant_override("outline_size", 14)
	v.add_child(t)
	var sub := Label.new()
	sub.text = "Lagos will not spoil."
	_style(sub, 22, UiStyle.PAPER)
	v.add_child(sub)
	var items: Array = []
	if has_save:
		items.append(["Continue", func() -> void: _close_menu(); continue_game.emit()])
	items.append(["New game", func() -> void: _close_menu(); new_game.emit()])
	items.append(["Missions", func() -> void: _menu.add_child(_missions_panel())])
	items.append(["Settings", func() -> void: _menu.add_child(_settings_panel())])
	items.append(["Credits", func() -> void: _menu.add_child(_credits_panel())])
	items.append(["Quit", func() -> void: get_tree().quit()])
	for it: Array in items:
		var b := Button.new()
		b.text = it[0]
		b.custom_minimum_size = Vector2(320, 58)
		b.add_theme_font_size_override("font_size", 24)
		b.pressed.connect(it[1])
		v.add_child(b)
	for c in [info, money, objective, act_btn, run_btn, pause_btn, minimap]:
		(c as CanvasItem).visible = false


func menu_open() -> bool:
	return _menu != null and is_instance_valid(_menu)


func _close_menu() -> void:
	_menu.queue_free()
	_menu = null
	for c in [info, money, objective, act_btn, run_btn, pause_btn, minimap]:
		(c as CanvasItem).visible = true


func _panel(title: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_to_group("closable_dialog")
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.custom_minimum_size = Vector2(620, 0)
	var v := VBoxContainer.new()
	v.name = "Body"
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var h := HBoxContainer.new()
	var t := Label.new()
	t.text = title
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style(t, 30, UiStyle.DANFO)
	h.add_child(t)
	var x := Button.new()
	x.text = "Close"
	x.custom_minimum_size = Vector2(120, 48)
	x.pressed.connect(p.queue_free)
	h.add_child(x)
	v.add_child(h)
	return p


func _settings_panel() -> Control:
	var p := _panel("Settings")
	var v: VBoxContainer = p.get_node("Body")
	var row := HBoxContainer.new()
	var gl := Label.new()
	gl.text = "Graphics"
	gl.custom_minimum_size = Vector2(170, 0)
	row.add_child(gl)
	for preset in ["low", "medium", "high"]:
		var b := Button.new()
		b.text = preset.capitalize()
		b.toggle_mode = true
		b.button_pressed = String(Settings.current.get("preset", "")) == preset
		b.custom_minimum_size = Vector2(130, 52)
		b.pressed.connect(func() -> void:
			Settings.use_preset(preset)
			world.apply_quality()
			for o in row.get_children():
				if o is Button:
					(o as Button).button_pressed = o == b)
		row.add_child(b)
	v.add_child(row)
	for spec: Array in [["Music", "vol_music"], ["Sound effects", "vol_sfx"], ["Street sounds", "vol_ambience"], ["Camera speed", "cam_sens"]]:
		var r := HBoxContainer.new()
		var l := Label.new()
		l.text = spec[0]
		l.custom_minimum_size = Vector2(170, 0)
		r.add_child(l)
		var s := HSlider.new()
		s.min_value = 0.0 if spec[1] != "cam_sens" else 0.3
		s.max_value = 1.0 if spec[1] != "cam_sens" else 2.0
		s.step = 0.05
		s.value = float(Settings.get_pref(spec[1], 1.0 if spec[1] == "cam_sens" else 0.7))
		s.custom_minimum_size = Vector2(360, 40)
		var key: String = spec[1]
		s.value_changed.connect(func(val: float) -> void:
			Settings.set_pref(key, val)
			Sound.apply_volumes())
		r.add_child(s)
		v.add_child(r)
	return p


func _missions_panel() -> Control:
	var p := _panel("Missions")
	var v: VBoxContainer = p.get_node("Body")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 420)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	v.add_child(scroll)
	var act := -1
	for id: String in Story.order:
		var m: Dictionary = Story.mission(id)
		if int(m.get("act", 0)) != act:
			act = int(m.get("act", 0))
			var h := Label.new()
			h.text = Story.act_title(act)
			_style(h, 22, UiStyle.DANFO)
			list.add_child(h)
		var l := Label.new()
		var mark := "✔" if Story.done.has(id) else ("▶" if Story.playable(id) else "·")
		var soon := "" if Story.playable(id) else "  (coming soon)"
		l.text = "%s  %s — %s%s" % [mark, String(m.get("title", id)), String(m.get("where", "")), soon]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(560, 0)
		l.add_theme_color_override("font_color", UiStyle.PAPER if Story.playable(id) else Color(0.7, 0.66, 0.58))
		list.add_child(l)
	return p


func _credits_panel() -> Control:
	var p := _panel("Credits")
	var v: VBoxContainer = p.get_node("Body")
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(580, 0)
	l.text = """Naija Street Life: Èkó Ò Ní Bàjẹ́
Story by Sheriff Usman. Design and code made for this project.
3D models made with Meshy (meshy.ai). The first models (danfo, shop, bungalow) are CC BY 4.0.
Free models via Poly Pizza: "Yacht" by Alex Safayan, "Canopy" by Poly by Google, "Ambulance Car" by Zsky (CC-BY 3.0); Quaternius and kazuma models (CC0), including Quaternius's Downtown City MegaKit.
Music and sound effects synthesised from code for this project.
All characters, businesses, agencies and parties are fictional. Real places are used as settings only.
Made with Godot Engine (godotengine.org/license), MIT License. Copyright (c) 2014-present Godot Engine contributors; (c) 2007-2014 Juan Linietsky, Ariel Manzur."""
	v.add_child(l)
	return p
