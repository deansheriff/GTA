extends Control
## Story dialogue: painted portrait, name plate, typewriter text, choices and a Skip button.
## `await play(lines)` returns every choice the player picked (Array of choice dictionaries).
## In autoplay (demo, tests) lines advance by themselves and the first choice is taken.

signal _advance
signal _chosen(choice: Dictionary)

const INK := Color("#1d1611")
const PAPER := Color("#f1e6c8")
const DANFO := Color("#e0a91c")
const CPS := 55.0 # typewriter characters per second

var autoplay := false
var auto_choice := 0
var _portrait: TextureRect
var _initial: Label
var _name: Label
var _text: Label
var _choices: VBoxContainer
var _skip: Button
var _hint: Label
var _typing := false
var _skipping := false
var _shown := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.03, 0.02, 0.25)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#2a2018").lerp(INK, 0.3)
	sb.border_color = INK
	sb.set_border_width_all(5)
	sb.set_corner_radius_all(18)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 190
	panel.offset_right = -24
	panel.offset_bottom = -18
	panel.offset_top = -200
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 22)
	_name.add_theme_color_override("font_outline_color", INK)
	_name.add_theme_constant_override("outline_size", 6)
	v.add_child(_name)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 21)
	_text.add_theme_color_override("font_color", PAPER)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_text)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 6)
	v.add_child(_choices)
	_hint = Label.new()
	_hint.text = "Tap to continue"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	v.add_child(_hint)

	# Portrait sits on the left, overlapping the panel like a comic.
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_portrait.offset_left = 8
	_portrait.offset_right = 230
	_portrait.offset_top = -270
	_portrait.offset_bottom = -10
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)
	_initial = Label.new()
	_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_initial.add_theme_font_size_override("font_size", 64)
	_initial.add_theme_color_override("font_outline_color", INK)
	_initial.add_theme_constant_override("outline_size", 12)
	_initial.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_initial.offset_left = 30
	_initial.offset_right = 170
	_initial.offset_top = -190
	_initial.offset_bottom = -50
	_initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_initial)

	_skip = Button.new()
	_skip.text = "Skip ››"
	_skip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip.offset_left = -140
	_skip.offset_right = -24
	_skip.offset_top = -254
	_skip.offset_bottom = -208
	_skip.pressed.connect(func() -> void:
		_skipping = true
		_advance.emit())
	add_child(_skip)


func _gui_input(event: InputEvent) -> void:
	var tap: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed)
	if tap and _choices.get_child_count() == 0:
		accept_event()
		if _typing:
			_finish_typing()
		else:
			_advance.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.pressed and not event.echo and (event as InputEventKey).keycode in [KEY_SPACE, KEY_ENTER, KEY_E]:
		if _choices.get_child_count() == 0:
			get_viewport().set_input_as_handled()
			if _typing:
				_finish_typing()
			else:
				_advance.emit()


func _process(delta: float) -> void:
	if not _typing:
		return
	_shown += delta * CPS * float(Settings.get_pref("dialogue_speed", 1.0))
	# Compare with the string length: get_total_character_count() is 0 until the label has been
	# shaped, which on Android ended the typewriter at zero characters (empty dialogue boxes).
	if int(_shown) >= _text.text.length():
		_finish_typing()
	else:
		_text.visible_characters = int(_shown)


## Show the whole line (end of typing, or the player tapped to skip ahead).
func _finish_typing() -> void:
	_typing = false
	_text.visible_characters = -1


## Play a conversation. Returns the choices picked, in order.
func play(lines: Array) -> Array:
	var picked: Array = []
	visible = true
	_skipping = false
	var queue: Array = lines.duplicate()
	while not queue.is_empty():
		var line: Dictionary = queue.pop_front()
		_show(line)
		var choices: Array = line.get("choices", [])
		if choices.is_empty():
			if _skipping:
				continue
			if autoplay:
				await get_tree().create_timer(0.12).timeout
			else:
				await _advance
			continue
		# Choices always stop a skip: decisions matter.
		_skipping = false
		_typing = false
		_text.visible_characters = -1
		_hint.visible = false
		for i in choices.size():
			var c: Dictionary = choices[i]
			var b := Button.new()
			b.text = "▸ " + String(c["text"])
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(0, 46)
			b.pressed.connect(func() -> void: _chosen.emit(c))
			_choices.add_child(b)
		var chosen: Dictionary
		if autoplay:
			await get_tree().create_timer(0.15).timeout
			chosen = choices[clampi(auto_choice, 0, choices.size() - 1)]
		else:
			chosen = await _chosen
		for b in _choices.get_children():
			_choices.remove_child(b)
			b.queue_free()
		picked.append(chosen)
		var reply: Array = chosen.get("reply", [])
		queue = reply + queue
	visible = false
	return picked


func _show(line: Dictionary) -> void:
	var who: String = line.get("who", "")
	var info := Story.who(who)
	_name.text = String(info.get("name", who))
	var col := Color(String(info.get("colour", "#e0a91c")))
	_name.add_theme_color_override("font_color", col.lightened(0.25))
	var tex: Texture2D = Art.tex(info["portrait"]) if info.has("portrait") else null
	_portrait.texture = tex
	_portrait.visible = tex != null
	_initial.visible = tex == null and who != "tip" and who != "chat"
	_initial.text = _name.text.trim_prefix("\"").left(1)
	_initial.add_theme_color_override("font_color", col)
	_text.text = String(line.get("text", ""))
	_text.add_theme_color_override("font_color", DANFO.lightened(0.4) if who == "tip" else PAPER)
	_hint.visible = true
	if _skipping or autoplay or Settings.get_value("reduced_motion", false):
		_typing = false
		_text.visible_characters = -1
	else:
		_typing = true
		_shown = 0.0
		_text.visible_characters = 0
