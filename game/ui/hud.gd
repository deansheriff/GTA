extends CanvasLayer
## HUD, buttons, joystick, toasts, first-run graphics suggestion and the settings panel.
## Built in code so it scales with Settings "ui_scale" and needs no scene files.

signal toggle_night
signal toggle_nepa
signal enter_exit
signal action_pressed
signal waypoint_set(pos: Vector2)
signal waypoint_cleared

const INK := Color("#1d1611")
const DANFO := Color("#e0a91c")
const PAPER := Color("#f1e6c8")

var joystick: Control
var minimap: Control
var map_screen: Control
var _root: Control
var _stats: PanelContainer
var _stats_label: Label
var _online_label: Label
var _job_label: Label
var _needs_bars := {}
var phone: Control
var pos_game: Control
var _action: Button
var _toast: Label
var _toast_t := 0.0
var _settings_panel: Control
var _theme := Theme.new()


func _ready() -> void:
	layer = 10
	_build_theme()
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme
	add_child(root)
	_root = root

	var title := _panel_label("Naija Street Life", 15)
	title.position = Vector2(12, 12)
	root.add_child(title)

	_stats = _panel_label("", 15)
	_stats.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_stats.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stats.offset_right = -12
	_stats.offset_top = 12
	root.add_child(_stats)
	_stats_label = _stats.get_meta("label")
	var online := _panel_label("Offline", 14)
	online.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	online.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	online.offset_right = -12
	online.offset_top = 56
	root.add_child(online)
	_online_label = online.get_meta("label")

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	col.position = Vector2(-12, -90)
	col.add_theme_constant_override("separation", 10)
	root.add_child(col)
	col.add_child(_button("Phone", func() -> void: if phone: phone.open()))
	col.add_child(_button("Settings", func() -> void: _show_settings(root)))
	if "--dev" in OS.get_cmdline_user_args() or "--demo" in OS.get_cmdline_user_args():
		col.add_child(_button("Night", func() -> void: toggle_night.emit()))
		col.add_child(_button("NEPA", func() -> void: toggle_nepa.emit()))

	var job := _panel_label("", 14)
	job.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	job.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	job.offset_right = -12
	job.offset_top = 98
	job.visible = false
	root.add_child(job)
	_job_label = job.get_meta("label")

	_action = _button("Enter danfo", func() -> void: action_pressed.emit())
	_action.custom_minimum_size = Vector2(170, 64)
	_action.add_theme_font_size_override("font_size", 22)
	HudLayout.pin_bottom_right(_action, 16, 16)
	_action.add_theme_color_override("font_color", INK)
	_action.add_theme_stylebox_override("normal", _box(DANFO, INK))
	_action.add_theme_stylebox_override("hover", _box(DANFO.lightened(0.1), INK))
	_action.add_theme_stylebox_override("pressed", _box(DANFO.darkened(0.1), INK))
	_action.visible = false
	root.add_child(_action)

	joystick = preload("res://ui/joystick.gd").new()
	joystick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	joystick.grow_vertical = Control.GROW_DIRECTION_BEGIN
	joystick.position = Vector2(20, -20)
	joystick.visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	root.add_child(joystick)

	if not joystick.visible:
		var hint := _panel_label("Click to walk · WASD/arrows move or drive · E enters the danfo · wheel zooms", 13)
		hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
		hint.position = Vector2(12, -12)
		root.add_child(hint)

	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.position = Vector2(0, 150)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 40)
	_toast.add_theme_color_override("font_color", DANFO)
	_toast.add_theme_color_override("font_outline_color", INK)
	_toast.add_theme_constant_override("outline_size", 10)
	_toast.visible = false
	root.add_child(_toast)

	Settings.changed.connect(func(_s: Dictionary) -> void: _apply_ui_scale(root))
	_apply_ui_scale(root)


func set_state(_mode: String, _near_danfo: bool, _night: bool, nepa_on: bool, fps: int) -> void:
	_stats_label.text = "%s   ₦%s   %s   %s%s" % [Clock.label(), Life.fmt_naira(Life.money), Life.mood_label(), "" if nepa_on else "No light   ", ("%d fps" % fps) if "--demo" in OS.get_cmdline_user_args() else ""]
	for n in _needs_bars:
		var pb: ProgressBar = _needs_bars[n]
		pb.value = Life.needs[n]
		(pb.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color("#2f8a52") if pb.value > 50 else (DANFO if pb.value > 25 else Color("#a8382c"))


## Context action (bottom right): "" hides it.
func set_action(text: String) -> void:
	_action.visible = text != ""
	_action.text = text


func set_job(text: String) -> void:
	_job_label.get_parent().visible = text != ""
	_job_label.text = text


## Phone, POS mini-game and needs bars (M2).
func setup_life(jobs: JobRunner) -> void:
	var needs_box := VBoxContainer.new()
	needs_box.position = Vector2(14, 236)
	needs_box.add_theme_constant_override("separation", 3)
	_root.add_child(needs_box)
	for n in Life.NEEDS:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = { "hunger": "Belle", "energy": "Power", "fun": "Joy", "social": "Gist", "hygiene": "Neat" }[n]
		l.custom_minimum_size = Vector2(40, 0)
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", PAPER)
		l.add_theme_color_override("font_outline_color", INK)
		l.add_theme_constant_override("outline_size", 4)
		row.add_child(l)
		var pb := ProgressBar.new()
		pb.max_value = 100
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(124, 9)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.11, 0.09, 0.07, 0.7)
		bg.set_corner_radius_all(4)
		pb.add_theme_stylebox_override("background", bg)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color("#2f8a52")
		fill.set_corner_radius_all(4)
		pb.add_theme_stylebox_override("fill", fill)
		row.add_child(pb)
		needs_box.add_child(row)
		_needs_bars[n] = pb
	phone = preload("res://ui/phone.gd").new()
	phone.visible = false
	_root.add_child(phone)
	phone.setup(jobs)
	phone.open_map.connect(func() -> void: map_screen.visible = true)
	phone.open_settings.connect(func() -> void: _show_settings(_root))
	pos_game = preload("res://ui/pos_game.gd").new()
	_root.add_child(pos_game)


## Vendor menu: buy food and items with game money.
func open_shop(title: String, stock: Array) -> void:
	var card := _card(_root, title, "Wallet: ₦%s" % Life.fmt_naira(Life.money), true)
	var dlg := _dialog_root(card)
	for id in stock:
		var it := Life.item(id)
		if it.is_empty():
			continue
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = "%s · ₦%s" % [it["name"], Life.fmt_naira(int(it["price"]))]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := _button("Buy", func() -> void:
			if Life.buy(id):
				dlg.queue_free())
		row.add_child(b)
		card.add_child(row)
	card.add_child(_button("Waka pass (leave)", func() -> void: dlg.queue_free()))


## Minimap under the title, full map on tap (M1).
func setup_maps(m: MapData, land: Texture2D, road: Texture2D) -> void:
	minimap = preload("res://ui/minimap.gd").new()
	minimap.setup(m, land, road)
	minimap.position = Vector2(12, 52)
	_root.add_child(minimap)
	map_screen = preload("res://ui/map_screen.gd").new()
	map_screen.visible = false
	_root.add_child(map_screen)
	map_screen.setup(m, land, road)
	minimap.open_map.connect(func() -> void: map_screen.visible = true)
	map_screen.waypoint_set.connect(func(p: Vector2) -> void: waypoint_set.emit(p))
	map_screen.waypoint_cleared.connect(func() -> void: waypoint_cleared.emit())


func set_online(text: String) -> void:
	_online_label.text = text


func toast(text: String, big := false) -> void:
	_toast.text = text
	_toast.add_theme_font_size_override("font_size", 52 if big else 26)
	_toast.visible = true
	_toast_t = 2.4


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast.visible = false


# ---------- dialogs ----------

signal welcome_closed


## First-run graphics suggestion; resolves when the player has chosen.
func show_welcome() -> void:
	_show_welcome(_root)
	await welcome_closed


func _show_welcome(root: Control) -> void:
	var s: Dictionary = Settings.suggestion
	var names := { "low": "Low", "medium": "Medium", "high": "High" }
	var body := "%s%s" % [names.get(s.get("preset"), "Medium"), " + Data saver" if s.get("data_saver") else ""]
	var reasons: Array = s.get("reasons", [])
	if reasons.size() > 0:
		body += "\nBecause: %s." % ", ".join(reasons)
	var card := _card(root, "We set up graphics for your phone", body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_button("Use this", func() -> void:
		Settings.set_all(Settings.current)
		_dialog_root(card).queue_free()
		welcome_closed.emit()))
	row.add_child(_button("Choose myself", func() -> void:
		_dialog_root(card).queue_free()
		_show_settings(root)
		_settings_panel.tree_exited.connect(func() -> void:
			Settings.set_all(Settings.current)
			welcome_closed.emit(), CONNECT_ONE_SHOT)))
	card.add_child(row)


func _show_settings(root: Control) -> void:
	if is_instance_valid(_settings_panel):
		return
	var card := _card(root, "Settings", "", true, func() -> void:
		if is_instance_valid(_settings_panel):
			_settings_panel.queue_free())
	_settings_panel = _dialog_root(card)
	var gfx := Label.new()
	gfx.text = "Graphics"
	gfx.add_theme_font_size_override("font_size", 20)
	card.add_child(gfx)
	var s: Dictionary = Settings.current
	var sug: String = Settings.suggestion.get("preset", "medium")
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 8)
	for p in ["low", "medium", "high"]:
		var label: String = p.capitalize() + (" ★" if p == sug else "")
		var b := _button(label, func() -> void:
			Settings.use_preset(p)
			_settings_panel.queue_free()
			_show_settings(root))
		b.disabled = s.get("preset") == p
		presets.add_child(b)
	card.add_child(presets)
	card.add_child(_small("★ suggested for this device" + ("  ·  you are on Custom" if s.get("preset") == "custom" else "")))
	card.add_child(_toggle("Data saver (low textures, still cutscenes)", s.get("data_saver", false), func(v: bool) -> void:
		Settings.set_all(DeviceProfile.apply_data_saver(Settings.current.duplicate(), v))))
	card.add_child(_choice("Effects", "effects", [["off", "Off"], ["low", "Low"], ["full", "Full"]]))
	card.add_child(_choice("Night & NEPA lighting", "lighting", [["simple", "Simple"], ["full", "Full"]]))
	card.add_child(_choice("Frame-rate cap", "fps_cap", [[30, "30"], [60, "60"], [0, "No cap"]]))
	card.add_child(_choice("Draw distance", "draw_distance", [[1, "Near"], [2, "Medium"], [3, "Far"]]))
	card.add_child(_choice("Text size", "ui_scale", [[1.0, "Normal"], [1.2, "Large"], [1.4, "Larger"]]))
	card.add_child(_toggle("Reduce motion (no screen shake)", s.get("reduced_motion", false), func(v: bool) -> void: Settings.set_value("reduced_motion", v)))
	card.add_child(_toggle("Weather", s.get("weather", true), func(v: bool) -> void: Settings.set_value("weather", v)))
	card.add_child(_toggle("News chatter (NPCs react to real headlines, with sources)", Settings.get_pref("news_chatter", true), func(v: bool) -> void: Settings.set_pref("news_chatter", v)))
	card.add_child(_toggle("Share anonymous stats and crash reports", Settings.get_pref("telemetry", false), func(v: bool) -> void: Settings.set_pref("telemetry", v)))
	var snd := Label.new()
	snd.text = "Sound"
	snd.add_theme_font_size_override("font_size", 20)
	card.add_child(snd)
	for k in [["vol_music", "Music"], ["vol_sfx", "Effects"], ["vol_ambience", "Street sounds"]]:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = k[1]
		l.custom_minimum_size = Vector2(140, 0)
		row.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(Settings.get_pref(k[0], 0.8))
		sl.custom_minimum_size = Vector2(220, 40)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key: String = k[0]
		sl.value_changed.connect(func(v: float) -> void: Settings.set_pref(key, v))
		row.add_child(sl)
		card.add_child(row)
	var acc := Label.new()
	acc.text = "Accessibility"
	acc.add_theme_font_size_override("font_size", 20)
	card.add_child(acc)
	card.add_child(_choice_pref("Dialogue text speed", "dialogue_speed", [[0.6, "Slow"], [1.0, "Normal"], [2.0, "Fast"], [99.0, "Instant"]]))
	card.add_child(_toggle("Hold buttons work as tap-to-toggle (e.g. SHOUT)", Settings.get_pref("hold_as_toggle", false), func(v: bool) -> void: Settings.set_pref("hold_as_toggle", v)))
	# Online: your Coolify server address (docs/COOLIFY.md) and display name.
	var online_h := Label.new()
	online_h.text = "Online"
	online_h.add_theme_font_size_override("font_size", 20)
	card.add_child(online_h)
	var server_edit := LineEdit.new()
	server_edit.placeholder_text = "Server address, e.g. game.your-domain.com"
	server_edit.text = Net.server
	card.add_child(server_edit)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Your name on the street"
	name_edit.text = Net.player_name
	name_edit.max_length = 20
	card.add_child(name_edit)
	card.add_child(_button("Connect", func() -> void:
		Net.set_server(server_edit.text, name_edit.text)
		Net.start(Net._pending_hello)
		_settings_panel.queue_free()))
	if Net.server != "":
		var legal := HBoxContainer.new()
		legal.add_child(_button("Privacy policy", func() -> void: OS.shell_open(Net.http_base() + "/privacy")))
		legal.add_child(_button("Terms", func() -> void: OS.shell_open(Net.http_base() + "/terms")))
		card.add_child(legal)
	card.add_child(_button("Close", func() -> void: _settings_panel.queue_free()))


# ---------- building blocks ----------

func _build_theme() -> void:
	_theme.default_font_size = 18
	_theme.set_stylebox("normal", "Button", _box(Color(0.11, 0.09, 0.07, 0.86), DANFO.darkened(0.15)))
	_theme.set_stylebox("hover", "Button", _box(Color(0.18, 0.15, 0.11, 0.9), DANFO))
	_theme.set_stylebox("pressed", "Button", _box(Color(0.25, 0.2, 0.12, 0.95), DANFO))
	_theme.set_stylebox("disabled", "Button", _box(DANFO.darkened(0.2), INK))
	_theme.set_color("font_color", "Button", PAPER)
	_theme.set_color("font_disabled_color", "Button", INK)
	_theme.set_stylebox("panel", "PanelContainer", _box(Color(0.95, 0.9, 0.79, 0.98), INK, 18))
	_theme.set_color("font_color", "Label", INK)


func _box(bg: Color, border: Color, radius := 12) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(3)
	b.set_corner_radius_all(radius)
	b.content_margin_left = 14
	b.content_margin_right = 14
	b.content_margin_top = 8
	b.content_margin_bottom = 8
	return b


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(48, 48)
	b.pressed.connect(cb)
	return b


func _panel_label(text: String, size: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(0.11, 0.09, 0.07, 0.82), Color(0, 0, 0, 0), 10))
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", PAPER)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Expose the label so callers can update its text.
	p.set_meta("label", l)
	return p


func _small(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.modulate = Color(1, 1, 1, 0.75)
	return l


## A dimmed modal card. With `on_close`, a Close button is pinned in the header (outside any
## scrolling) and the Android back button closes it too (owner feedback: settings had no way out).
func _card(root: Control, heading: String, body: String, scrollable := false, on_close := Callable()) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.02, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var h := Label.new()
	h.text = heading
	h.add_theme_font_size_override("font_size", 24)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(h)
	if on_close.is_valid():
		var x := _button("Close", on_close)
		x.custom_minimum_size = Vector2(110, 52)
		head.add_child(x)
		dim.set_meta("on_close", on_close)
		dim.add_to_group("closable_dialog")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.custom_minimum_size = Vector2(440, 0)
	if scrollable:
		# Long lists scroll on small phones; height capped to the screen. Drag anywhere to scroll.
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.scroll_deadzone = 8
		scroll.custom_minimum_size = Vector2(470, minf(470.0, get_viewport().get_visible_rect().size.y - 150.0))
		outer.add_child(scroll)
		scroll.add_child(v)
	else:
		outer.add_child(v)
	if body != "":
		var b := Label.new()
		b.text = body
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(b)
	return v


## The dim backdrop that owns a card (card -> panel -> center -> dim).
func _dialog_root(card: Control) -> Control:
	var n: Node = card
	while n and not (n is ColorRect):
		n = n.get_parent()
	return n as Control


func _toggle(text: String, value: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = value
	c.add_theme_color_override("font_color", INK)
	c.add_theme_color_override("font_pressed_color", INK)
	c.add_theme_color_override("font_hover_color", INK)
	c.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	c.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	c.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	c.toggled.connect(cb)
	return c


func _choice(text: String, key: String, options: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var ob := OptionButton.new()
	for i in options.size():
		ob.add_item(String(options[i][1]), i)
		if options[i][0] == Settings.get_value(key):
			ob.select(i)
	ob.item_selected.connect(func(i: int) -> void: Settings.set_value(key, options[i][0]))
	row.add_child(ob)
	return row


func _choice_pref(text: String, key: String, options: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var ob := OptionButton.new()
	for i in options.size():
		ob.add_item(String(options[i][1]), i)
		if is_equal_approx(float(options[i][0]), float(Settings.get_pref(key, 1.0))):
			ob.select(i)
	ob.item_selected.connect(func(i: int) -> void: Settings.set_pref(key, options[i][0]))
	row.add_child(ob)
	return row


func _apply_ui_scale(root: Control) -> void:
	var sc := float(Settings.get_value("ui_scale", 1.0))
	_theme.default_font_size = int(18 * sc)
	root.scale = Vector2.ONE # fonts scale via theme; layout grows with content


## Android back button / Escape: close the top-most closable dialog. Returns false if none was open.
func close_top_dialog() -> bool:
	var open := get_tree().get_nodes_in_group("closable_dialog")
	for i in range(open.size() - 1, -1, -1):
		var d: Node = open[i]
		if is_instance_valid(d) and not d.is_queued_for_deletion() and d.is_visible_in_tree():
			(d.get_meta("on_close") as Callable).call()
			return true
	if phone and phone.visible:
		phone.visible = false
		return true
	if map_screen and map_screen.visible:
		map_screen.visible = false
		return true
	return false
