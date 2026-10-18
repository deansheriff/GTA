extends CanvasLayer
## Title screen: an aerial view of the island, logo, Continue / New game, Settings and Credits (with the Godot
## licence notice the engine's MIT licence requires).

signal play(new_game: bool)
signal open_settings

const INK := Color("#1d1611")
const PAPER := Color("#f1e6c8")
const DANFO := Color("#e0a91c")

var has_save := false
var _root: Control
var _menu: VBoxContainer
var _loading: Label
var _tip: Label
var _tip_t := 0.0
var _tip_i := 0
const TIPS := ["Tip: argue with the marshals only when your street reputation is good.", "Tip: park off the lane, or the drivers behind you will get out.", "Tip: rain means higher fares, but the low roads flood.", "Tip: a generator saves your sleep when NEPA takes light.", "Tip: crews that hold a route earn 10% more on every run.", "Tip: the Traffic Gist station warns you about checkpoints on your route.", "Tip: hide off the main roads to cool your Area heat.", "Tip: Mallam's suya stand pays well after 7pm."]
var _scene: Control


func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_root.theme = Theme.new()
	UiStyle.apply(_root.theme)
	var bg := ColorRect.new()
	bg.color = Color("#0d0a07")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	# Tropical-island Lagos from the air: planes, surf, birds, boats, traffic (ui/title_aerial.gd).
	_scene = TitleAerial.new()
	_root.add_child(_scene)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.offset_top = 30
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(v)
	for t in [["NAIJA STREET LIFE", 64, DANFO], ["UP NEPA!", 40, PAPER]]:
		var l := Label.new()
		l.text = t[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", t[1])
		l.add_theme_font_override("font", UiStyle.display())
		l.add_theme_color_override("font_color", t[2])
		l.add_theme_color_override("font_outline_color", INK)
		l.add_theme_constant_override("outline_size", 18)
		v.add_child(l)
	var menu := VBoxContainer.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	menu.grow_vertical = Control.GROW_DIRECTION_BEGIN
	menu.offset_bottom = -40
	menu.add_theme_constant_override("separation", 10)
	_root.add_child(menu)
	_menu = menu
	_loading = Label.new()
	_loading.text = "Loading Lagos…"
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.add_theme_font_size_override("font_size", 26)
	_loading.add_theme_color_override("font_color", PAPER)
	_loading.add_theme_color_override("font_outline_color", INK)
	_loading.add_theme_constant_override("outline_size", 10)
	menu.add_child(_loading)
	_tip = Label.new()
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(620, 0)
	_tip.add_theme_font_size_override("font_size", 17)
	_tip.add_theme_color_override("font_color", PAPER)
	_tip.add_theme_color_override("font_outline_color", INK)
	_tip.add_theme_constant_override("outline_size", 7)
	_tip.text = TIPS[randi() % TIPS.size()]
	menu.add_child(_tip)


## Called once the world is built: swap "Loading…" for the menu.
func set_ready(saved: bool) -> void:
	has_save = saved
	_loading.queue_free()
	_tip.queue_free()
	_tip = null
	_build_menu(_menu)


func _build_menu(menu: VBoxContainer) -> void:
	if has_save:
		menu.add_child(_btn("Continue", func() -> void: _go(false)))
	menu.add_child(_btn("New game" if has_save else "Play", func() -> void:
		if has_save:
			_confirm_new()
		else:
			_go(true)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_btn("Settings", func() -> void: open_settings.emit(), 180))
	row.add_child(_btn("Credits", _credits, 180))
	menu.add_child(row)
	if ResourceLoader.exists("res://world3d/street3d.tscn"):
		menu.add_child(_btn("3D Lagos (preview)", func() -> void:
			if Engine.has_meta("save_ready"):
				SaveGame.save_now() # 3D Lagos starts from the freshest save
			get_tree().change_scene_to_file("res://world3d/street3d.tscn")))


func _btn(text: String, cb: Callable, w := 370) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 60)
	b.add_theme_font_size_override("font_size", 24)
	# Solid, high-contrast buttons over the bright painting (device test).
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.11, 0.08, 0.05, 0.92) if state != "pressed" else DANFO.darkened(0.2)
		sb.border_color = DANFO
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(14)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", PAPER)
	b.add_theme_color_override("font_hover_color", DANFO)
	b.pressed.connect(func() -> void:
		Sound.sfx("tap")
		cb.call())
	return b


func _go(new_game: bool) -> void:
	play.emit(new_game)
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.4)
	tw.tween_callback(queue_free)


func _confirm_new() -> void:
	var d := ConfirmationDialog.new()
	d.title = "Start a new game?"
	d.dialog_text = "This replaces your saved progress on this phone (your online account is not affected)."
	d.ok_button_text = "Start over"
	d.confirmed.connect(func() -> void: _go(true))
	_root.add_child(d)
	d.popup_centered()


func _credits() -> void:
	var d := AcceptDialog.new()
	d.title = "Credits"
	d.dialog_text = """Naija Street Life: Up NEPA!

Story, design and code made for this project.
Painted art generated for this project with GPT Image, from our own style reference (see docs/art/PROVENANCE.md).
3D models made with Meshy (meshy.ai). The first models (danfo, shop, bungalow) are CC BY 4.0.
Music and sound effects synthesised from code for this project.
All characters, businesses, agencies and parties are fictional. Real places are used as settings only.

Made with Godot Engine (godotengine.org/license):
Copyright (c) 2014-present Godot Engine contributors. Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.
Permission is hereby granted, free of charge, to any person obtaining a copy of this software, to deal in the Software without restriction, subject to the MIT License conditions. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND."""
	d.dialog_autowrap = true
	d.size = Vector2i(720, 520)
	_root.add_child(d)
	d.popup_centered()


## The world's map is ready (main.gd stage 1): the aerial title starts traffic on the real roads.
func set_map(m: MapData) -> void:
	if _scene and _scene.has_method("set_map"):
		_scene.set_map(m)


func _process(delta: float) -> void:
	if _tip == null:
		return
	_tip_t += delta
	if _tip_t > 4.0:
		_tip_t = 0.0
		_tip_i += 1
		_tip.text = TIPS[(_tip_i + int(Time.get_ticks_msec())) % TIPS.size()]
