extends Control
## On-screen thumb-stick. `value` is a screen-space vector, length 0..1.

var value := Vector2.ZERO
var _touch := -1
const RADIUS := 64.0


func _ready() -> void:
	custom_minimum_size = Vector2(RADIUS * 2.4, RADIUS * 2.4)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _center() -> Vector2:
	return size * 0.5


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch == -1:
			_touch = event.index
			_update(event.position)
		elif not event.pressed and event.index == _touch:
			_release()
		accept_event()
	elif event is InputEventScreenDrag and event.index == _touch:
		_update(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_update(event.position)
		else:
			_release()
		accept_event()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_update(event.position)
		accept_event()


func _update(pos: Vector2) -> void:
	# Sensitivity (Settings → Controls): higher reaches full speed with a shorter push.
	var v := (pos - _center()) / (RADIUS / clampf(float(Settings.get_pref("stick_sens", 1.0)), 0.5, 2.0))
	value = v.limit_length(1.0)
	queue_redraw()


func _release() -> void:
	_touch = -1
	value = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	var c := _center()
	draw_circle(c, RADIUS, Color(0.11, 0.09, 0.07, 0.45))
	draw_arc(c, RADIUS, 0, TAU, 40, Color(0.95, 0.9, 0.8, 0.35), 3.0, true)
	draw_circle(c + value * RADIUS, RADIUS * 0.42, Color(0.88, 0.66, 0.11, 0.9))
	draw_arc(c + value * RADIUS, RADIUS * 0.42, 0, TAU, 32, Color("#1d1611"), 3.0, true)
