extends Control
## "Family Meeting!" group chat overlay: messages pop in one by one like a real phone, the current
## hero's own messages on the right. Used for hero switching, scripted beats and the chat history.

signal _tapped

const INK := Color("#1d1611")
const PAPER := Color("#f1e6c8")
const DANFO := Color("#e0a91c")

var autoplay := false
var _title: Label
var _list: VBoxContainer
var _scroll: ScrollContainer
var _done: Button
var _fast := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.02, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var body := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#16211c")
	sb.border_color = INK
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(28)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	body.add_theme_stylebox_override("panel", sb)
	body.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	body.custom_minimum_size = Vector2(400, 560)
	body.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	body.position = Vector2(-24, -280)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	body.add_child(v)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", PAPER)
	v.add_child(_title)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)
	_done = Button.new()
	_done.text = "Continue"
	_done.custom_minimum_size = Vector2(0, 52)
	_done.pressed.connect(func() -> void: _tapped.emit())
	v.add_child(_done)


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		_fast = true


## Play messages one by one. `me` = hero whose messages sit on the right.
func play(lines: Array, title: String, me: String = "") -> void:
	visible = true
	_fast = autoplay
	_title.text = title
	for c in _list.get_children():
		c.queue_free()
	_done.visible = false
	for line in lines:
		if not _fast:
			await get_tree().create_timer(0.75).timeout
		add_message(line, me)
		await get_tree().process_frame
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
	_done.visible = true
	if autoplay:
		await get_tree().create_timer(0.3).timeout
	else:
		await _tapped
	visible = false


func add_message(line: Dictionary, me: String) -> void:
	var who: String = line.get("who", "")
	var info := Story.who(who)
	var mine := who == me
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END if mine else BoxContainer.ALIGNMENT_BEGIN
	var bubble := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#2f6b4f") if mine else Color("#24302b")
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	bubble.add_theme_stylebox_override("panel", sb)
	bubble.custom_minimum_size = Vector2(120, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	bubble.add_child(v)
	if not mine:
		var n := Label.new()
		n.text = String(info.get("name", who))
		n.add_theme_font_size_override("font_size", 13)
		n.add_theme_color_override("font_color", Color(String(info.get("colour", "#e0a91c"))).lightened(0.3))
		v.add_child(n)
	var t := Label.new()
	t.text = String(line.get("text", ""))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(minf(300.0, 40.0 + t.text.length() * 9.0), 0)
	t.add_theme_font_size_override("font_size", 16)
	t.add_theme_color_override("font_color", PAPER)
	v.add_child(t)
	row.add_child(bubble)
	_list.add_child(row)
