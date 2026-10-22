extends Control
## On-screen thumb-stick, floating (D-033): put your thumb down anywhere on the left side of the
## screen (the right side with left-handed controls) and the stick appears under it; let go and it
## fades back to its resting spot. `value` is a screen-space vector, length 0..1.
## This control covers the stick's side of the screen behind the HUD's buttons, so a press on a
## button is still the button's; the thumb is then followed anywhere on screen until it lifts.
## Robust against getting stuck (phone feedback, 2026-10-19):
##  - a finger that started on the stick is followed anywhere (global _input), so a thumb that
##    slides off still releases it;
##  - on touch devices the emulated mouse events Android sends are ignored;
##  - the stick lets go when hidden, paused, or when the app loses focus or goes to the background.

var value := Vector2.ZERO
var left_side := true
var _touch := -1
var _mouse := false
var _base := Vector2.ZERO # where the stick is centred (local), while held
var _held := false
var _alpha := 0.35
const RADIUS := 64.0
const ZONE := 0.45 # how much of the screen's width the stick's side covers


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS # hears releases even while the game is paused
	layout()


## Cover the stick's side of the screen (below the top HUD lines).
func layout() -> void:
	anchor_top = 0.0
	anchor_bottom = 1.0
	anchor_left = 0.0 if left_side else 1.0 - ZONE
	anchor_right = ZONE if left_side else 1.0
	offset_left = 0.0
	offset_right = 0.0
	offset_top = 150.0
	offset_bottom = 0.0
	queue_redraw()


func _rest() -> Vector2:
	return Vector2(RADIUS * 1.4 + 20.0 if left_side else size.x - RADIUS * 1.4 - 20.0, size.y - RADIUS * 1.4 - 30.0)


func _touchscreen() -> bool:
	return DisplayServer.is_touchscreen_available()


## A press that lands on this control (no button over it): the stick starts here.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed and _touch == -1:
		_touch = event.index
		_start(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not _touchscreen() and not _mouse:
		_mouse = true
		_start(event.position)
		accept_event()


func _start(local: Vector2) -> void:
	_base = local
	_held = true
	_alpha = 1.0
	value = Vector2.ZERO
	queue_redraw()


## After it started, the thumb is followed anywhere on screen until it lifts.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		if _touch != -1 or _mouse:
			_release()
		return
	if event is InputEventScreenTouch:
		if not event.pressed and event.index == _touch:
			_release()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == _touch:
			_update(event.position)
			get_viewport().set_input_as_handled()
	elif not _touchscreen():
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _mouse:
			_release()
		elif event is InputEventMouseMotion and _mouse:
			if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
				_update(event.position)
			else:
				_release() # the button came up somewhere we didn't hear


func _update(global_pos: Vector2) -> void:
	# Sensitivity (Settings): higher reaches full speed with a shorter push.
	var local := global_pos - get_global_rect().position
	var off := local - _base
	var reach := RADIUS / clampf(float(Settings.get_pref("stick_sens", 1.0)), 0.5, 2.0)
	value = (off / reach).limit_length(1.0)
	# A thumb that drags far past the rim pulls the stick's centre along behind it.
	if off.length() > RADIUS * 1.6:
		_base = local - off.normalized() * RADIUS * 1.6
	queue_redraw()


func _release() -> void:
	_touch = -1
	_mouse = false
	_held = false
	value = Vector2.ZERO
	queue_redraw()


func _process(delta: float) -> void:
	if not _held and _alpha > 0.35:
		_alpha = maxf(0.35, _alpha - delta * 2.5)
		queue_redraw()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_VISIBILITY_CHANGED, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_PAUSED:
			_release()
		NOTIFICATION_RESIZED:
			queue_redraw()


func _draw() -> void:
	var c := _base if _held else _rest()
	var a := _alpha
	draw_circle(c, RADIUS, Color(0.11, 0.09, 0.07, 0.45 * a))
	draw_arc(c, RADIUS, 0, TAU, 40, Color(0.95, 0.9, 0.8, 0.35 * a + 0.1), 3.0, true)
	draw_circle(c + value * RADIUS, RADIUS * 0.42, Color(0.88, 0.66, 0.11, 0.9 * a))
	draw_arc(c + value * RADIUS, RADIUS * 0.42, 0, TAU, 32, Color(0.11, 0.09, 0.07, a), 3.0, true)
