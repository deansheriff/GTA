class_name MiniGame
extends Control
## Base for story mini-games: a dimmed overlay with a painted-ink card. Subclasses build their UI in
## _build(), start in _begin(params) and call finish(result). `await play(params)` returns the result
## ({score: 0-100 or count, ...}). In autoplay the game plays itself (demo and headless QA).

signal finished(result: Dictionary)

const INK := Color("#1d1611")
const PAPER := Color("#f1e6c8")
const DANFO := Color("#e0a91c")
const GOOD := Color("#2f8a52")
const BAD := Color("#a8382c")

var autoplay := false
var card: VBoxContainer
var _title: Label
var _running := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.02, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#2a2018")
	sb.border_color = INK
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(20)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 18
	sb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	card = VBoxContainer.new()
	card.custom_minimum_size = Vector2(560, 0)
	card.add_theme_constant_override("separation", 12)
	panel.add_child(card)
	_title = label("", 26, DANFO)
	_build()


func play(params: Dictionary) -> Dictionary:
	visible = true
	_running = true
	_begin(params)
	var res: Dictionary = await finished
	return res


func finish(result: Dictionary) -> void:
	if not _running:
		return
	_running = false
	await get_tree().create_timer(0.9 if not autoplay else 0.2).timeout
	visible = false
	finished.emit(result)


func set_title(t: String) -> void:
	_title.text = t


func label(text: String, size := 18, colour := PAPER) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	card.add_child(l)
	return l


func big_button(text: String, cb: Callable, parent: Control = null) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 70)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(cb)
	(parent if parent else card).add_child(b)
	return b


func bar(colour := DANFO) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 16)
	var fill := StyleBoxFlat.new()
	fill.bg_color = colour
	fill.set_corner_radius_all(6)
	pb.add_theme_stylebox_override("fill", fill)
	card.add_child(pb)
	return pb


func _build() -> void:
	pass


func _begin(_params: Dictionary) -> void:
	pass
