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
var radio_btn: Button
var _radio: Label
var _timer: Label
var _alarm: ProgressBar
var _stamina: ProgressBar
var _buffs: Label
var _hit: Label
var _vignette: ColorRect
var _white: ColorRect
var _hint: PanelContainer
var _hint_text: Label
var _hint_t := 0.0
var _hint_queue: Array = []
var _prompt_shown := ""
var guide: Guide3D
var map_screen: MapScreen3D
var map_btn: Button
var horn_btn: Button
var police_label: Label


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
		_root.add_child(joy)
		_root.move_child(joy, 0) # behind every button: a press on a button stays the button's
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
	pause.extra = [
		["Map", func(_root: Control) -> void: open_map()],
		["How to play", func(root: Control) -> void: root.add_child(_help_panel())],
		["Street life", func(root: Control) -> void: root.add_child(_street_panel())],
		["Restart from checkpoint", func(_root: Control) -> void: _restart_checkpoint()],
	]
	add_child(pause)
	pause.use_theme(_theme)
	pause.open_settings.connect(func(root: Control) -> void: root.add_child(_settings_panel()))
	_build_extras()
	apply_layout()


# ---------- D-028: prompts, radio, timer, alarm, hit feedback, hints ----------

func _build_extras() -> void:
	guide = Guide3D.new()
	_root.add_child(guide)
	_root.move_child(guide, 1)
	guide.setup(world)
	horn_btn = _button("HORN", Vector2(-340, -130))
	horn_btn.pressed.connect(func() -> void: world.horn())
	horn_btn.visible = false
	police_label = _label(Vector2(16, 176), 20, Color("#ff6a5a"))
	map_btn = _button("MAP", Vector2(-190, 12), true)
	map_btn.custom_minimum_size = Vector2(84, 64)
	map_btn.offset_right = map_btn.offset_left + 84
	map_btn.offset_bottom = map_btn.offset_top + 64
	map_btn.add_theme_font_size_override("font_size", 20)
	map_btn.pressed.connect(open_map)
	var layer := CanvasLayer.new()
	layer.layer = 30
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	map_screen = MapScreen3D.new()
	var mroot := Control.new()
	mroot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mroot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mroot.theme = _theme
	layer.add_child(mroot)
	mroot.add_child(map_screen)
	map_screen.setup(world)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.07)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.show_behind_parent = true
	map_screen.add_child(bg)
	map_screen.move_child(bg, 0)


	radio_btn = _button("RADIO", Vector2(-340, -370))
	radio_btn.custom_minimum_size = Vector2(150, 64)
	radio_btn.offset_bottom = radio_btn.offset_top + 64
	radio_btn.pressed.connect(func() -> void:
		Sound.sfx("static")
		world.roam.next_station())
	radio_btn.visible = false
	_radio = Label.new()
	_radio.anchor_left = 0.18
	_radio.anchor_right = 0.82
	_radio.anchor_top = 1.0
	_radio.anchor_bottom = 1.0
	_radio.offset_top = -64
	_radio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_radio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(_radio, 18, Color("#ffe9b0"))
	_root.add_child(_radio)
	_timer = Label.new()
	_timer.anchor_left = 0.4
	_timer.anchor_right = 0.6
	_timer.offset_top = 64
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.add_theme_font_override("font", UiStyle.display())
	_style(_timer, 34, Color("#f6d04d"))
	_timer.visible = false
	_root.add_child(_timer)
	_alarm = ProgressBar.new()
	_alarm.max_value = 1.0
	_alarm.show_percentage = false
	_alarm.anchor_left = 0.38
	_alarm.anchor_right = 0.62
	_alarm.offset_top = 150
	_alarm.offset_bottom = 164
	var af := StyleBoxFlat.new()
	af.bg_color = Color("#e8483a")
	_alarm.add_theme_stylebox_override("fill", af)
	_alarm.visible = false
	_root.add_child(_alarm)
	_stamina = ProgressBar.new()
	_stamina.max_value = 1.0
	_stamina.show_percentage = false
	_stamina.custom_minimum_size = Vector2(160, 8)
	_stamina.position = Vector2(16, 122)
	var sf := StyleBoxFlat.new()
	sf.bg_color = Color("#4fb3d9")
	_stamina.add_theme_stylebox_override("fill", sf)
	_stamina.visible = false
	_root.add_child(_stamina)
	_buffs = _label(Vector2(16, 150), 17, Color("#9fe0ff"))
	_hit = Label.new()
	_hit.text = "✕"
	_hit.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_hit.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hit.grow_vertical = Control.GROW_DIRECTION_BOTH
	_style(_hit, 40, Color(1, 1, 1))
	_hit.modulate.a = 0.0
	_root.add_child(_hit)
	_vignette = ColorRect.new()
	_vignette.color = Color(0.8, 0.05, 0.02, 0.0)
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_vignette)
	_root.move_child(_vignette, 0)
	_white = ColorRect.new()
	_white.color = Color(1, 1, 1, 0.0)
	_white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_white)
	_hint = PanelContainer.new()
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.offset_left = -300
	_hint.offset_right = 300
	_hint.offset_top = 190
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0.08, 0.06, 0.04, 0.85)
	hs.border_color = UiStyle.DANFO
	hs.set_border_width_all(2)
	hs.set_corner_radius_all(8)
	hs.set_content_margin_all(12)
	_hint.add_theme_stylebox_override("panel", hs)
	_hint_text = Label.new()
	_hint_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_text.custom_minimum_size = Vector2(576, 0)
	_style(_hint_text, 20, UiStyle.PAPER)
	_hint.add_child(_hint_text)
	_hint.visible = false
	_root.add_child(_hint)


## Is a screen point on one of the HUD's touch buttons?
func over_button(p: Vector2) -> bool:
	for b: Button in [act_btn, run_btn, punch_btn, shoot_btn, radio_btn, horn_btn, pause_btn, map_btn]:
		if b and b.is_visible_in_tree() and b.get_global_rect().has_point(p):
			return true
	return false


func open_map() -> void:
	if menu_open() or dialogue.visible or map_screen.visible:
		return
	# From the pause menu: hide it (the game stays paused) and come back to it on Close.
	var from_pause: bool = pause.visible
	if from_pause:
		pause.visible = false
	map_screen.open_map(from_pause)


## Left-handed layout swaps the stick and the buttons; Text size scales the whole interface.
func apply_layout() -> void:
	var left := bool(Settings.get_pref("left_handed", false))
	for b: Button in [act_btn, run_btn, punch_btn, shoot_btn, radio_btn, horn_btn]:
		if b == null:
			continue
		if not b.has_meta("x"):
			b.set_meta("x", b.offset_left)
		var x: float = b.get_meta("x")
		var w := b.custom_minimum_size.x
		b.anchor_left = 0.0 if left else 1.0
		b.anchor_right = b.anchor_left
		b.offset_left = (-x - w) if left else x
		b.offset_right = b.offset_left + w
	if joy:
		joy.left_side = not left
		joy.layout()
	get_tree().root.content_scale_factor = clampf(float(Settings.get_pref("text_scale", 1.0)), 0.8, 1.4)


func prompt(text: String) -> void:
	var want := text if text != "" else ("EXIT" if world.ride else "ENTER")
	if want != _prompt_shown:
		_prompt_shown = want
		act_btn.text = want
		act_btn.add_theme_color_override("font_color", Color("#f6d04d") if text != "" else UiStyle.PAPER)
		act_btn.add_theme_font_size_override("font_size", 24 if want.length() <= 8 else 18)
		# Long prompts widen the button inwards, away from the screen edge.
		var w := maxf(150.0, want.length() * 11.5 + 24.0)
		if act_btn.anchor_left == 1.0:
			act_btn.offset_left = act_btn.offset_right - w
		else:
			act_btn.offset_right = act_btn.offset_left + w
	radio_btn.visible = world.ride != null and not menu_open() and not dialogue.visible
	horn_btn.visible = world.ride != null and not world.ride.on_water and not menu_open() and not dialogue.visible and not world.combat.active
	police_label.text = world.police.label() if world.police else ""
	var st: float = world.player.stamina
	_stamina.visible = st < 0.99 and world.ride == null and not menu_open()
	_stamina.value = st
	var b: Array = []
	if world.roam:
		for k: String in world.roam.buffs:
			var left: float = float(world.roam.buffs[k])
			var name: String = { "regen": "Ewa agoyin", "stamina": "Amala", "iroko": "Ìrókò charm" }.get(k, k)
			b.append(name if left > 1e8 else "%s %d:%02d" % [name, int(left) / 60, int(left) % 60])
	if world.player.in_cover and world.combat.active:
		b.append("IN COVER")
	_buffs.text = " · ".join(b)


func radio(text: String) -> void:
	_radio.text = text


func timer(secs: float) -> void:
	_timer.visible = secs >= 0.0
	if secs >= 0.0:
		_timer.text = "%d:%02d" % [int(secs) / 60, int(secs) % 60]
		_timer.add_theme_color_override("font_color", Color("#e8483a") if secs < 15.0 else Color("#f6d04d"))


## The stealth or blend meter (-1 hides it).
func alarm(v: float) -> void:
	_alarm.visible = v >= 0.0
	_alarm.value = maxf(0.0, v)


func hurt() -> void:
	var tw := create_tween()
	_vignette.color.a = 0.28
	tw.tween_property(_vignette, "color:a", 0.0, 0.35)


func hitmark() -> void:
	_hit.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_hit, "modulate:a", 0.0, 0.25)


func flash_white() -> void:
	_white.color.a = 0.85
	var tw := create_tween()
	tw.tween_property(_white, "color:a", 0.0, 0.4)


## A tip card the first time something comes up (saved, so each shows once).
func hint(id: String, text: String) -> void:
	var seen: Array = Settings.get_pref("hints_seen", [])
	if id in seen or "--shots" in str(OS.get_cmdline_user_args()):
		return
	seen.append(id)
	Settings.set_pref("hints_seen", seen)
	_hint_queue.append(text)


func _process(delta: float) -> void:
	if _hint.visible:
		_hint_t -= delta
		if _hint_t <= 0.0:
			_hint.visible = false
	elif not _hint_queue.is_empty() and not dialogue.visible and not menu_open():
		_hint_text.text = "TIP  " + String(_hint_queue.pop_front())
		_hint.visible = true
		_hint_t = 6.0


func credits_roll() -> void:
	var c := ColorRect.new()
	c.color = Color(0.03, 0.02, 0.02, 0.92)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(c)
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_left = 0.1
	l.anchor_right = 0.9
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style(l, 24, UiStyle.PAPER)
	l.text = "ÈKÓ Ò NÍ BÀJẸ́\n\nNaija Street Life\n\nStory by Sheriff Usman\n\nDayo \"Sabi\" Balogun · Mama Àgbà · Kemi · Sego · Uncle Obi\nAlhaji Kongi · Rasheed · ACP Hauwa Danjuma · Amaka Eze · Bigz Jupiter\nGeneral Tonye · Baba Fakunle · Senator Coker-Bankole\n\n3D models: Meshy, Quaternius (CC0), Poly Pizza contributors (CC-BY)\nMusic and sound synthesised for this game\nMade with Godot Engine\n\nAll characters and businesses are fictional.\nLagos is real. Lagos will not spoil.\n\nThank you for playing."
	c.add_child(l)
	var h := get_viewport().get_visible_rect().size.y
	l.position.y = h
	var tw := create_tween()
	tw.tween_property(l, "position:y", -900.0, 14.0 if not "--shots" in str(OS.get_cmdline_user_args()) else 0.5)
	await tw.finished
	c.queue_free()


func _restart_checkpoint() -> void:
	pause.close()
	var id: String = world.missions.running
	if id == "" or id == "side":
		notify("No mission to restart.")
		return
	world.missions.abort()
	await get_tree().create_timer(0.3).timeout
	world.combat.clear()
	world.stealth.end()
	world.clear_actors()
	world.clear_mission_vehicles()
	world.missions.running = ""
	world.missions.run(id, Story.checkpoint)


## How to play: the controls, touch and keyboard.
func _help_panel() -> Control:
	var p := _panel("How to play")
	var v: VBoxContainer = p.get_node("Body")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 420)
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(570, 0)
	l.text = """MOVE: put your thumb down anywhere on the left of the screen and the stick appears under it (WASD or arrow keys). Push it all the way to run, or hold RUN (Shift).
MAP (M): the whole city. Drag, pinch to zoom, tap to set a waypoint.
LOOK: drag on the right of the screen (right mouse button): left/right turns the camera, up/down raises or lowers it.
ENTER / EXIT: get into the nearest vehicle or out of it (E or F). The button also does what the moment needs: FUEL, REPAIR, SNAP PHOTO, EAT, SIDE JOB, DANCE...
PUNCH (J or Space) in a fight; from behind, a guard goes down silently.
SHOOT (K or left click) once you have the pistol: it aims at the target with the red ring.
RADIO in a vehicle: Gbedu FM, Naija Talk, or off. HORN (H): traffic moves on, people step aside.
PAUSE: the II button (Esc, or your phone's back button).

DANFO: stop at a bus stop and passengers climb in; drive to their stop (the yellow beacon) and stop to collect. The bus owner wants ₦8,000 delivery every day.
CHECKPOINTS: slow down and you settle the roger; blast through and they take your number.
WANTED: stars bring police pickups. PURSUIT while they can see you; break their line of sight and they SEARCH the circle on the minimap. Stay out of it until they give up. Change vehicles out of sight to fool them.
SCRAPES: hit someone's car and they'll want settling. Drive off and people talk.
EXPLORE: a gold ✦ marks a Lagos Story; sacks behind buildings hide stashes; people in the street may need a hand.
FUEL: every ride burns it. Stop at a filling station. Mechanics fix damage.
FOOD: Mama Àgbà's stall by the house heals and keeps you running.
COVER: stand still against a wall in a gunfight and they hit you far less.
ROOFTOPS: run at a gap to jump it. Walking stops at the edge.
STEALTH: darkness hides you, light gives you away; walk, don't run."""
	_style(l, 19, UiStyle.PAPER)
	scroll.add_child(l)
	v.add_child(scroll)
	return p


## Street life: the delivery, what you own, perks and food.
func _street_panel() -> Control:
	var p := _panel("Street life")
	var v: VBoxContainer = p.get_node("Body")
	var r = world.roam
	var lines: Array = []
	if r.delivery_due():
		lines.append("Daily delivery to the bus owner: ₦%s due at midnight (₦%s earned today%s)." % [Life.fmt_naira(r.DELIVERY), Life.fmt_naira(r.today), (", ₦%s owed" % Life.fmt_naira(r.debt)) if r.debt > 0 else ""])
	else:
		lines.append("No more deliveries: nobody collects for Ọkpụ again." if r.postgame == "" else "Post-game: %s" % r.postgame)
	lines.append("Respect %d · Wanted %d" % [Story.respect, int(ceil(Story.wanted - 0.01))])
	lines.append("Vehicles you own: %s" % (", ".join(r.owned) if not r.owned.is_empty() else "the danfo (Uncle Obi's)"))
	if world.explore:
		var c: Array = world.explore.found_count()
		lines.append("Lagos Stories found: %d of %d · Stashes found: %d of %d" % c)
	lines.append("")
	lines.append("RESPECT PERKS")
	lines.append_array(r.perk_lines())
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(570, 0)
	l.text = "\n".join(lines)
	_style(l, 19, UiStyle.PAPER)
	v.add_child(l)
	return p


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
	_title_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_sub.custom_minimum_size = Vector2(900, 0)
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
	items.append(["How to play", func() -> void: _menu.add_child(_help_panel())])
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
	if radio_btn:
		radio_btn.visible = false
		horn_btn.visible = false
		map_btn.visible = false


func menu_open() -> bool:
	return _menu != null and is_instance_valid(_menu)


func _close_menu() -> void:
	_menu.queue_free()
	_menu = null
	for c in [info, money, objective, act_btn, run_btn, pause_btn, minimap]:
		(c as CanvasItem).visible = true
	if map_btn:
		map_btn.visible = true


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
	# Accessibility and comfort (D-028).
	var acc := GridContainer.new()
	acc.columns = 2
	for spec: Array in [["Difficulty", "difficulty", ["Easy", "Normal", "Hard"]], ["Text size", "text_scale", ["100%", "115%", "130%"]]]:
		var lab := Label.new()
		lab.text = spec[0]
		lab.custom_minimum_size = Vector2(170, 0)
		acc.add_child(lab)
		var ob := OptionButton.new()
		for o: String in spec[2]:
			ob.add_item(o)
		var key: String = spec[1]
		var vals: Array = [0, 1, 2] if key == "difficulty" else [1.0, 1.15, 1.3]
		var cur: Variant = Settings.get_pref(key, vals[1] if key == "difficulty" else 1.0)
		ob.selected = maxi(0, vals.find(cur))
		ob.custom_minimum_size = Vector2(200, 46)
		ob.item_selected.connect(func(i: int) -> void:
			Settings.set_pref(key, vals[i])
			apply_layout())
		acc.add_child(ob)
	for spec: Array in [["Reduce motion (no shake)", "motion_off"], ["Left-handed controls", "left_handed"], ["Vibration", "vibration"], ["Battery saver (30 fps)", "battery_saver"], ["Colour-blind markers", "colorblind"]]:
		var cb := CheckButton.new()
		cb.text = spec[0]
		var key: String = spec[1]
		cb.button_pressed = bool(Settings.get_pref(key, key == "vibration"))
		cb.toggled.connect(func(on: bool) -> void:
			Settings.set_pref(key, on)
			apply_layout()
			world.apply_quality())
		acc.add_child(cb)
	v.add_child(acc)
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
