class_name PauseMenu
extends CanvasLayer
## Pause (M13): the "II" button, Escape, or the Android back button when nothing else is open.
## The world stops (tree paused); this menu keeps running. Resume, Settings, Save, Save & quit.

signal open_settings(root: Control)

var _root: Control
var _tips := ["Argue with the marshals only when your street reputation is good.", "Park off the lane, or the drivers behind you will get out.", "Rain means higher fares, but watch for floods on the low roads.", "A generator saves your sleep when NEPA takes light at night.", "Crews that hold a route earn 10% more on every run."]


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = Theme.new()
	UiStyle.apply(_root.theme)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.02, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(360, 0)
	center.add_child(v)
	var t := Label.new()
	t.text = "PAUSED"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_override("font", UiStyle.display())
	t.add_theme_font_size_override("font_size", 46)
	t.add_theme_color_override("font_color", UiStyle.DANFO)
	t.add_theme_color_override("font_outline_color", UiStyle.INK)
	t.add_theme_constant_override("outline_size", 10)
	v.add_child(t)
	for spec: Array in [["Resume", close], ["Settings", func() -> void: open_settings.emit(_root)], ["Save", _save], ["Save & quit", _quit]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(360, 62)
		b.add_theme_font_size_override("font_size", 24)
		b.pressed.connect(spec[1])
		v.add_child(b)
	var tip := Label.new()
	tip.name = "Tip"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.custom_minimum_size = Vector2(360, 0)
	tip.add_theme_color_override("font_color", UiStyle.PAPER)
	tip.add_theme_font_size_override("font_size", 15)
	v.add_child(tip)


func _unhandled_input(e: InputEvent) -> void:
	if visible and e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


## Use the HUD's look (button boxes, fonts).
func use_theme(t: Theme) -> void:
	_root.theme = t


func open() -> void:
	if visible:
		return
	visible = true
	(_root.find_child("Tip", true, false) as Label).text = "Tip: " + _tips[randi() % _tips.size()]
	get_tree().paused = true
	Clock.paused = true
	Sound.sfx("tap")


func close() -> void:
	for c in _root.get_children():
		if c.is_in_group("closable_dialog"):
			c.queue_free() # settings opened from here close with the menu
	visible = false
	get_tree().paused = false
	Clock.paused = false


func _save() -> void:
	SaveGame.save_now()
	(_root.find_child("Tip", true, false) as Label).text = "Saved."


func _quit() -> void:
	SaveGame.save_now()
	get_tree().paused = false
	get_tree().quit()
