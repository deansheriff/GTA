class_name Celebrate
extends Control
## Unlock moments (M13): a ribbon drops from the top with a title, a line under it, confetti in
## danfo yellow, green and red, and the success sound. Used for awards, a new bus, a new house, a
## generator, joining a crew and winning races. Queues if several arrive at once.

var _queue: Array = []
var _busy := false
var _ribbon: PanelContainer
var _title: Label
var _sub: Label
var _bits: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ribbon = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1d1611")
	sb.border_color = UiStyle.DANFO
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(18)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 10
	_ribbon.add_theme_stylebox_override("panel", sb)
	_ribbon.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_ribbon.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ribbon)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_ribbon.add_child(v)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", UiStyle.display())
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", UiStyle.DANFO)
	v.add_child(_title)
	_sub = Label.new()
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_font_size_override("font_size", 18)
	_sub.add_theme_color_override("font_color", UiStyle.PAPER)
	v.add_child(_sub)
	_ribbon.visible = false


func show_moment(kicker: String, title: String) -> void:
	_queue.append([kicker, title])
	if not _busy:
		_next()


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var item: Array = _queue.pop_front()
	_sub.text = item[0]
	_title.text = item[1]
	_ribbon.visible = true
	_ribbon.reset_size()
	_ribbon.offset_top = -140
	_ribbon.offset_left = -_ribbon.size.x * 0.5
	_ribbon.offset_right = _ribbon.size.x * 0.5
	Sound.sfx("success")
	_confetti()
	var tw := create_tween()
	tw.tween_property(_ribbon, "offset_top", 70.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.4)
	tw.tween_property(_ribbon, "offset_top", -160.0, 0.3).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		_ribbon.visible = false
		_next())


func _confetti() -> void:
	if Settings.get_value("reduced_motion", false):
		return
	var w := get_viewport_rect().size.x
	for i in 40:
		_bits.append({ "p": Vector2(w * 0.5 + randf_range(-260, 260), randf_range(40, 110)), "v": Vector2(randf_range(-160, 160), randf_range(-220, -60)), "r": randf() * TAU, "c": [UiStyle.DANFO, UiStyle.GREEN, UiStyle.RED, UiStyle.PAPER][i % 4], "t": 0.0 })


func _process(delta: float) -> void:
	if _bits.is_empty():
		return
	for b: Dictionary in _bits:
		b["t"] += delta
		b["v"] += Vector2(0, 420) * delta
		b["p"] += b["v"] * delta
		b["r"] += delta * 8.0
	_bits = _bits.filter(func(b: Dictionary) -> bool: return b["t"] < 2.2)
	queue_redraw()


func _draw() -> void:
	for b: Dictionary in _bits:
		draw_set_transform(b["p"], b["r"])
		draw_rect(Rect2(-5, -3, 10, 6), Color(b["c"], 1.0 - b["t"] / 2.2))
	draw_set_transform(Vector2.ZERO)
