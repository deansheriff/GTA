extends Control
## The current hero's meter (BP / Aura / Battery + Hype) on the left, and their two ability buttons
## above the action button on the right. The Conductor Combo opens a row of Sule's calls.

signal ability_pressed(ability: String)
signal call_pressed(call: String)

const INK := Color("#1d1611")
const PAPER := Color("#f1e6c8")
const DANFO := Color("#e0a91c")

var _meter_box: VBoxContainer
var _hero_label: Label
var _bars := {} # stat -> ProgressBar
var _btn_col: VBoxContainer
var _buttons := {} # ability -> Button
var _calls: HBoxContainer
var _hero := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meter_box = VBoxContainer.new()
	_meter_box.position = Vector2(14, 340)
	_meter_box.add_theme_constant_override("separation", 3)
	_meter_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_meter_box)
	_hero_label = _outlined("", 15, DANFO)
	_meter_box.add_child(_hero_label)
	_btn_col = VBoxContainer.new()
	_btn_col.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_btn_col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_btn_col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_btn_col.position = Vector2(-16, -96)
	_btn_col.add_theme_constant_override("separation", 10)
	add_child(_btn_col)
	_calls = HBoxContainer.new()
	_calls.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_calls.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_calls.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_calls.position = Vector2(0, -110)
	_calls.add_theme_constant_override("separation", 8)
	_calls.visible = false
	add_child(_calls)
	for k in Abilities.CALLS:
		var b := Button.new()
		b.text = Abilities.CALLS[k]
		b.custom_minimum_size = Vector2(0, 58)
		var key: String = k
		b.pressed.connect(func() -> void:
			_calls.visible = false
			call_pressed.emit(key))
		_calls.add_child(b)


func _outlined(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _rebuild(ab: Abilities) -> void:
	_hero = Life.hero
	for c in _meter_box.get_children():
		if c != _hero_label:
			c.queue_free()
	_bars.clear()
	var stats: Array = { "tunde": [["bp", "BP", Color("#c4473a"), 100.0]], "ngozi": [["aura", "Aura", Color("#a46ad0"), 100.0]], "kc": [["battery", "Battery", Color("#3f8a3a"), 100.0], ["hype", "Hype", Color("#e07a1c"), 1000.0]] }.get(_hero, [])
	for s in stats:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := _outlined(s[1], 12, PAPER)
		l.custom_minimum_size = Vector2(62, 0)
		row.add_child(l)
		var pb := ProgressBar.new()
		pb.max_value = s[3]
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(104, 11)
		pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.11, 0.09, 0.07, 0.7)
		bg.set_corner_radius_all(4)
		pb.add_theme_stylebox_override("background", bg)
		var fill := StyleBoxFlat.new()
		fill.bg_color = s[2]
		fill.set_corner_radius_all(4)
		pb.add_theme_stylebox_override("fill", fill)
		row.add_child(pb)
		_meter_box.add_child(row)
		_bars[s[0]] = pb
	for c in _btn_col.get_children():
		c.queue_free()
	_buttons.clear()
	for a in Abilities.HERO_ABILITIES.get(_hero, []):
		var b := Button.new()
		b.custom_minimum_size = Vector2(118, 56)
		var icon: Texture2D = Art.tex("ui/ab-%s.png" % a)
		if icon:
			b.icon = icon
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 36)
		var key: String = a
		b.pressed.connect(func() -> void:
			if key == "conductor":
				_calls.visible = not _calls.visible
			else:
				ability_pressed.emit(key))
		_btn_col.add_child(b)
		_buttons[a] = b
	_calls.visible = false


func refresh(ab: Abilities) -> void:
	if _hero != Life.hero:
		_rebuild(ab)
	_hero_label.text = "%s%s" % [Story.HERO_NAME.get(Life.hero, Life.hero), "  · ₦s %s" % Life.fmt_naira(Story.story_money) if Story.story_money > 0 else ""]
	for s in _bars:
		(_bars[s] as ProgressBar).value = float(Life.stats.get(s, 0.0))
	if _bars.has("bp"):
		var fill := (_bars["bp"] as ProgressBar).get_theme_stylebox("fill") as StyleBoxFlat
		var bp := float(Life.stats.get("bp", 0.0))
		fill.bg_color = Color("#2f8a52") if bp < 40.0 else (DANFO if bp < 80.0 else Color("#c4473a"))
	for a in _buttons:
		var b: Button = _buttons[a]
		var cd := ab.cooldown(a)
		var label: String = Abilities.LABELS.get(a, a)
		if ab.tier(a) <= 0:
			b.text = "Locked: " + label
			b.disabled = true
		else:
			b.disabled = false
			var on: bool = (a == "film" and ab.filming) or (a == "golive" and ab.live)
			b.text = ("● " if on else "") + label + (" %ds" % int(ceil(cd)) if cd > 0.5 else "")
			if a == "ajo":
				b.text = "%s %d/%d" % [label, maxi(0, ab.tier(a) - ab.ajo_used), ab.tier(a)]
			elif a == "gist":
				b.text = "%s %d/3" % [label, maxi(0, 3 - ab.gist_used)]
	visible = true
