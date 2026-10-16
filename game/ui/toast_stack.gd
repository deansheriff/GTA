class_name ToastStack
extends VBoxContainer
## Messages that stack instead of replacing each other (M13). Each one is a pill with an icon and
## a colour by kind (money in, money out, warning, award, info), slides in, and fades after a few
## seconds; at most three show at once. They sit under the top bar, clear of the dialogue box.
## big = true: a centred banner for the moments that matter.

const MAX := 3
const KINDS := {
	"money": ["₦", Color("#2f8a52")],
	"spend": ["₦", Color("#a8382c")],
	"warn": ["!", Color("#c8432f")],
	"award": ["★", Color("#e0a91c")],
	"info": ["i", Color("#3a3226")],
}

var _banner: Label
var _banner_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	offset_top = 164 # under the status pills and the button row
	add_theme_constant_override("separation", 6)
	alignment = BoxContainer.ALIGNMENT_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner = Label.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.custom_minimum_size = Vector2(700, 0)
	_banner.add_theme_font_override("font", UiStyle.display())
	_banner.add_theme_font_size_override("font_size", 36)
	_banner.add_theme_color_override("font_color", UiStyle.DANFO)
	_banner.add_theme_color_override("font_outline_color", UiStyle.INK)
	_banner.add_theme_constant_override("outline_size", 12)
	_banner.offset_top = -120
	_banner.visible = false
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE


## The banner lives on the HUD root (centred on screen), not in the stack.
func attach_banner(root: Control) -> void:
	root.add_child(_banner)


static func guess_kind(text: String) -> String:
	var t := text.to_lower()
	if t.begins_with("award") or t.contains("unlocked"):
		return "award"
	if text.contains("₦"):
		for w in ["+₦", "fares", "tip", "prize", "earn", "sold", "commission", "returns", "bonus", "reward"]:
			if t.contains(w):
				return "money"
		return "spend"
	if t.contains("!") and (t.contains("task force") or t.contains("impound") or t.contains("fuel don finish") or t.contains("limping") or t.contains("flood") or t.contains("thief")):
		return "warn"
	return "info"


func show_toast(text: String, big := false, kind := "") -> void:
	if big:
		_banner.text = text
		_banner.visible = true
		_banner.modulate = Color(1, 1, 1, 0)
		_banner.scale = Vector2(0.85, 0.85)
		_banner.pivot_offset = _banner.size * 0.5
		var tw := _banner.create_tween()
		tw.tween_property(_banner, "modulate:a", 1.0, 0.15)
		tw.parallel().tween_property(_banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_banner_t = 2.6
		return
	# The same message again just refreshes the existing pill.
	for c in get_children():
		if c.get_meta("text", "") == text:
			c.set_meta("t", 3.2)
			return
	if kind == "":
		kind = guess_kind(text)
	var spec: Array = KINDS.get(kind, KINDS["info"])
	var pill := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.09, 0.07, 0.9)
	sb.border_color = spec[1]
	sb.set_border_width_all(2)
	sb.border_width_left = 8
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 12
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	pill.add_theme_stylebox_override("panel", sb)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	pill.add_child(row)
	var icon := Label.new()
	icon.text = spec[0]
	icon.add_theme_font_override("font", UiStyle.display())
	icon.add_theme_font_size_override("font_size", 22)
	icon.add_theme_color_override("font_color", (spec[1] as Color).lightened(0.35))
	row.add_child(icon)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(minf(560.0, 18.0 + text.length() * 10.5), 0)
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", UiStyle.PAPER)
	row.add_child(l)
	pill.set_meta("text", text)
	pill.set_meta("t", 3.2 + minf(2.0, text.length() / 40.0))
	add_child(pill)
	move_child(pill, 0)
	pill.modulate = Color(1, 1, 1, 0)
	var tw := pill.create_tween()
	tw.tween_property(pill, "modulate:a", 1.0, 0.18)
	while get_child_count() > MAX:
		var old := get_child(get_child_count() - 1)
		remove_child(old)
		old.queue_free()


func _notification(what: int) -> void:
	# The banner lives on the HUD root once attached; if it never was, it's ours to free.
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_banner) and _banner.get_parent() == null:
		_banner.free()


func _process(delta: float) -> void:
	for c in get_children():
		var t: float = c.get_meta("t", 0.0) - delta
		c.set_meta("t", t)
		if t < 0.4:
			c.modulate.a = maxf(0.0, t / 0.4)
		if t <= 0.0:
			c.queue_free()
	if _banner_t > 0.0:
		_banner_t -= delta
		if _banner_t < 0.4:
			_banner.modulate.a = maxf(0.0, _banner_t / 0.4)
		if _banner_t <= 0.0:
			_banner.visible = false


## Is anything showing? (tests and the demo)
func latest() -> String:
	return String(get_child(0).get_meta("text", "")) if get_child_count() > 0 else (_banner.text if _banner.visible else "")


## Headless tests: drop the shared font faces so nothing is reported as leaked at exit.
static func release_fonts() -> void:
	UiStyle.release()
