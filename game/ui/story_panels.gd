extends Control
## Still-panel cutscenes: painted comic frames with a caption, a slow push-in and tap to continue.
## Cheap on any phone (one texture at a time) and the default for low-bandwidth mode.

signal _next

const INK := Color("#1d1611")
const PAPER := Color("#f1e6c8")
const DANFO := Color("#e0a91c")

var autoplay := false
var _img: TextureRect
var _caption: Label
var _title: Label
var _cap_panel: PanelContainer
var _tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var bg := ColorRect.new()
	bg.color = Color("#0d0a07")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_img = TextureRect.new()
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_img)
	_title = Label.new()
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.offset_bottom = -220
	_title.add_theme_font_size_override("font_size", 84)
	_title.add_theme_color_override("font_color", DANFO)
	_title.add_theme_color_override("font_outline_color", INK)
	_title.add_theme_constant_override("outline_size", 22)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	_cap_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.05, 0.03, 0.82)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 16
	sb.content_margin_bottom = 18
	_cap_panel.add_theme_stylebox_override("panel", sb)
	_cap_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_cap_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_cap_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cap_panel)
	_caption = Label.new()
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 24)
	_caption.add_theme_color_override("font_color", PAPER)
	_cap_panel.add_child(_caption)


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		accept_event()
		_next.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.pressed and not event.echo and (event as InputEventKey).keycode in [KEY_SPACE, KEY_ENTER, KEY_E]:
		get_viewport().set_input_as_handled()
		_next.emit()


## Show panels one after another: [{img, text, title?}]
func play(panels: Array) -> void:
	visible = true
	for p in panels:
		var tex: Texture2D = Art.tex(String(p.get("img", "")))
		_img.texture = tex
		var is_title: bool = p.get("title", false)
		_title.visible = is_title
		_title.text = String(p.get("text", "")) if is_title else ""
		_cap_panel.visible = not is_title and String(p.get("text", "")) != ""
		_caption.text = String(p.get("text", ""))
		_img.pivot_offset = size * 0.5
		_img.scale = Vector2.ONE
		_img.modulate = Color(1, 1, 1, 0)
		if _tween:
			_tween.kill()
		_tween = create_tween().set_parallel()
		_tween.tween_property(_img, "modulate:a", 1.0, 0.35)
		if not Settings.get_value("reduced_motion", false):
			_tween.tween_property(_img, "scale", Vector2(1.06, 1.06), 7.0).set_trans(Tween.TRANS_SINE)
		if autoplay:
			await get_tree().create_timer(0.9).timeout
		else:
			await get_tree().create_timer(0.3).timeout # ignore the tap that opened us
			await _next
	visible = false
