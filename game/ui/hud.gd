extends CanvasLayer
## HUD, buttons, joystick, toasts, first-run graphics suggestion and the settings panel.
## Built in code so it scales with Settings "ui_scale" and needs no scene files.

signal toggle_night
signal toggle_nepa
signal enter_exit

const INK := Color("#1d1611")
const DANFO := Color("#e0a91c")
const PAPER := Color("#f1e6c8")

var joystick: Control
var _stats: PanelContainer
var _stats_label: Label
var _online_label: Label
var _action: Button
var _toast: Label
var _toast_t := 0.0
var _settings_panel: Control
var _theme := Theme.new()


func _ready() -> void:
	layer = 10
	_build_theme()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme
	add_child(root)

	var title := _panel_label("Naija Street Life\n[M0 style test · AI-painted art]", 15)
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
	col.add_child(_button("Settings", func() -> void: _show_settings(root)))
	col.add_child(_button("Night", func() -> void: toggle_night.emit()))
	col.add_child(_button("NEPA", func() -> void: toggle_nepa.emit()))

	_action = _button("Enter danfo", func() -> void: enter_exit.emit())
	_action.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_action.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_action.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_action.position = Vector2(-16, -16)
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

	if Settings.first_run and not "--demo" in OS.get_cmdline_user_args():
		_show_welcome(root)
	Settings.changed.connect(func(_s: Dictionary) -> void: _apply_ui_scale(root))
	_apply_ui_scale(root)


func set_state(mode: String, near_danfo: bool, night: bool, nepa_on: bool, fps: int) -> void:
	_stats_label.text = "%d fps   %s   %s" % [fps, "Night" if night else "Day", "Light dey" if nepa_on else "No light"]
	_action.visible = near_danfo or mode == "driving"
	_action.text = "Comot from danfo" if mode == "driving" else "Enter Baba God Dey"


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
		_dialog_root(card).queue_free()))
	row.add_child(_button("Choose myself", func() -> void:
		_dialog_root(card).queue_free()
		_show_settings(root)))
	card.add_child(row)


func _show_settings(root: Control) -> void:
	if is_instance_valid(_settings_panel):
		return
	var card := _card(root, "Graphics", "", true)
	_settings_panel = _dialog_root(card)
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


func _card(root: Control, heading: String, body: String, scrollable := false) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.02, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.custom_minimum_size = Vector2(440, 0)
	if scrollable:
		# Long lists scroll on small phones; height capped to the screen.
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(460, minf(520.0, get_viewport().get_visible_rect().size.y - 80.0))
		panel.add_child(scroll)
		scroll.add_child(v)
	else:
		panel.add_child(v)
	var h := Label.new()
	h.text = heading
	h.add_theme_font_size_override("font_size", 24)
	v.add_child(h)
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


func _apply_ui_scale(root: Control) -> void:
	var sc := float(Settings.get_value("ui_scale", 1.0))
	_theme.default_font_size = int(18 * sc)
	root.scale = Vector2.ONE # fonts scale via theme; layout grows with content
