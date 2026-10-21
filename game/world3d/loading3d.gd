class_name Loading3D
extends CanvasLayer
## The loading screen (D-028): shown at boot while the city builds over several frames, and when the
## story travels to another region. The bar moves with each build stage, a proverb or tip turns over,
## and a danfo drives across the bottom, so a phone never sits on a frozen black frame.

const TIPS := [
	"Èkó ò ní bàjẹ́: Lagos will not spoil.",
	"Drag on the right of the screen to turn the camera; drag up or down to raise it.",
	"Stop at a bus stop in a danfo and passengers climb in. Drive them to their stop to get paid.",
	"Pull up slowly at a checkpoint and you settle the roger. Blast through and they take your number.",
	"Mama Àgbà's food heals: ewa agoyin and agege bread for health, amala and ewedu for stamina.",
	"When NEPA takes light, the streetlights die and generators roar. Darkness hides you.",
	"No condition is permanent.",
	"Every vehicle needs fuel. Filling stations and mechanics sit by the main roads.",
	"Respect opens doors: better prices, agbero allies and fewer questions at checkpoints.",
	"A go-slow is a market: hawkers bring pure water, gala and phone credit to your window.",
]

var _bar: ProgressBar
var _what: Label
var _tip: Label
var _bus: Label
var _t := 0.0
var _tip_t := 0.0
var _tip_i := 0


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var th := Theme.new()
	UiStyle.apply(th)
	root.theme = th
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color("#14100c")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.custom_minimum_size = Vector2(640, 0)
	v.add_theme_constant_override("separation", 14)
	root.add_child(v)
	var kicker := _label("NAIJA STREET LIFE", 22, UiStyle.PAPER)
	v.add_child(kicker)
	var t := _label("ÈKÓ Ò NÍ BÀJẸ́", 60, UiStyle.DANFO)
	t.add_theme_font_override("font", UiStyle.display())
	t.add_theme_constant_override("outline_size", 12)
	v.add_child(t)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(640, 16)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiStyle.DANFO
	_bar.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.08)
	_bar.add_theme_stylebox_override("background", back)
	v.add_child(_bar)
	_what = _label("", 20, UiStyle.PAPER)
	v.add_child(_what)
	_tip = _label("", 20, Color("#cbbf9f"))
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(640, 60)
	v.add_child(_tip)
	_bus = _label("▬▬▬█▙", 34, UiStyle.DANFO)
	_bus.anchor_top = 1.0
	_bus.anchor_bottom = 1.0
	_bus.offset_top = -80
	root.add_child(_bus)
	_tip_i = randi() % TIPS.size()
	_tip.text = TIPS[_tip_i]
	visible = false


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", UiStyle.INK)
	l.add_theme_constant_override("outline_size", 6)
	return l


func open(where := "") -> void:
	visible = true
	_bar.value = 0.0
	_what.text = where


## progress 0..1, and what is being built ("Laying the roads").
func stage(progress: float, what: String) -> void:
	_bar.value = progress
	_what.text = what


func close() -> void:
	var tw := create_tween()
	tw.tween_property(_bar, "value", 1.0, 0.15)
	tw.tween_interval(0.1)
	await tw.finished
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_tip_t += delta
	if _tip_t > 4.0:
		_tip_t = 0.0
		_tip_i = (_tip_i + 1) % TIPS.size()
		_tip.text = TIPS[_tip_i]
	var w := get_viewport().get_visible_rect().size.x
	_bus.position.x = fmod(_t * 160.0, w + 200.0) - 160.0
