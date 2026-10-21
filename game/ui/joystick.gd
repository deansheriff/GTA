extends Control
## On-screen thumb-stick. `value` is a screen-space vector, length 0..1.
## Robust against getting stuck (phone feedback, 2026-10-19):
##  - a finger that presses inside the stick is followed anywhere on screen (global _input), so a
##    thumb that slides off the stick still releases it;
##  - on touch devices the emulated mouse events Android sends are ignored (they track only the
##    first finger and used to fight the real touch);
##  - the stick lets go when hidden, paused, or when the app loses focus or goes to the background.

var value := Vector2.ZERO
var _touch := -1
var _mouse := false
const RADIUS := 64.0


func _ready() -> void:
	custom_minimum_size = Vector2(RADIUS * 2.4, RADIUS * 2.4)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS # hears releases even while the game is paused


func _center() -> Vector2:
	return size * 0.5


func _touchscreen() -> bool:
	return DisplayServer.is_touchscreen_available()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		if _touch != -1 or _mouse:
			_release()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touch == -1 and get_global_rect().has_point(event.position):
				_touch = event.index
				_update(event.position)
				get_viewport().set_input_as_handled()
		elif event.index == _touch:
			_release()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == _touch:
			_update(event.position)
			get_viewport().set_input_as_handled()
	elif not _touchscreen():
		# Desktop: the mouse plays the finger.
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and get_global_rect().has_point(event.position):
				_mouse = true
				_update(event.position)
				get_viewport().set_input_as_handled()
			elif not event.pressed and _mouse:
				_release()
		elif event is InputEventMouseMotion and _mouse:
			if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
				_update(event.position)
			else:
				_release() # the button came up somewhere we didn't hear


func _update(global_pos: Vector2) -> void:
	# Sensitivity (Settings): higher reaches full speed with a shorter push.
	var local := global_pos - get_global_rect().position
	var v := (local - _center()) / (RADIUS / clampf(float(Settings.get_pref("stick_sens", 1.0)), 0.5, 2.0))
	value = v.limit_length(1.0)
	queue_redraw()


func _release() -> void:
	_touch = -1
	_mouse = false
	value = Vector2.ZERO
	queue_redraw()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_VISIBILITY_CHANGED, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_PAUSED:
			_release()


func _draw() -> void:
	var c := _center()
	draw_circle(c, RADIUS, Color(0.11, 0.09, 0.07, 0.45))
	draw_arc(c, RADIUS, 0, TAU, 40, Color(0.95, 0.9, 0.8, 0.35), 3.0, true)
	draw_circle(c + value * RADIUS, RADIUS * 0.42, Color(0.88, 0.66, 0.11, 0.9))
	draw_arc(c + value * RADIUS, RADIUS * 0.42, 0, TAU, 32, Color("#1d1611"), 3.0, true)
