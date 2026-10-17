class_name Controls
extends Control
## Control schemes and sensitivity (M14, owner: "choice of control… set their control sensitivity").
## Settings → Controls:
##   Joystick       the thumb-stick for walking and driving (point where you want to go).
##   Steering       walking uses the stick; driving uses ◀ ▶ on the left and GAS / BRAKE on the right,
##                  like a racing game.
##   Tilt to steer  as Steering, but you tilt the phone to turn.
## Sensitivity: stick sensitivity (how far you push for full speed), dead zone, steering
## sensitivity (how sharply the vehicle turns), tilt sensitivity, pinch-zoom sensitivity.

const SCHEMES := [["stick", "Joystick"], ["buttons", "Steering buttons"], ["tilt", "Tilt to steer"]]

var _left: _Pad
var _right: _Pad
var _gas: _Pad
var _brake: _Pad
var driving := false


static func scheme() -> String:
	return String(Settings.get_pref("control_scheme", "stick"))


static func pref(key: String, fallback: float) -> float:
	return float(Settings.get_pref(key, fallback))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left = _pad("◀", Vector2(20, -128), true)
	_right = _pad("▶", Vector2(150, -128), true)
	# Left of the action button (which grows with its text) and the ability column.
	_gas = _pad("GAS", Vector2(-420, -228), false)
	_brake = _pad("BRAKE", Vector2(-420, -128), false)


func _pad(label: String, at: Vector2, left_side: bool) -> _Pad:
	var p := _Pad.new()
	p.label = label
	p.custom_minimum_size = Vector2(118, 92)
	# Offsets from the corner anchor (not `position`, which goes wrong before the screen has a size).
	var ax := 0.0 if left_side else 1.0
	p.anchor_left = ax
	p.anchor_right = ax
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = at.x
	p.offset_right = at.x + 118.0
	p.offset_top = at.y
	p.offset_bottom = at.y + 92.0
	add_child(p)
	return p


func _process(_d: float) -> void:
	var show := driving and scheme() != "stick"
	_gas.visible = show
	_brake.visible = show
	_left.visible = show and scheme() == "buttons"
	_right.visible = show and scheme() == "buttons"


## Steering input as a screen-space direction for danfo.drive(): turn relative to the heading,
## GAS to go, BRAKE to stop and then reverse. Returns ZERO when nothing is held.
func drive_vector(heading: float) -> Vector2:
	var steer := 0.0
	if scheme() == "tilt":
		var a := Input.get_accelerometer() # landscape phone: tilting left/right shows up on y
		steer = clampf(a.y / 6.0 * pref("tilt_sens", 1.0), -1.0, 1.0)
		if absf(steer) < 0.08:
			steer = 0.0
	else:
		steer = (1.0 if _right.down else 0.0) - (1.0 if _left.down else 0.0)
	# Keyboard works in every scheme.
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		steer -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		steer += 1.0
	var gas := _gas.down or Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)
	var brake := _brake.down or Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)
	if brake:
		return Vector2.from_angle(heading + PI) # past 2.4 rad off the heading = brake, then reverse
	if gas:
		return Vector2.from_angle(heading + clampf(steer, -1.0, 1.0) * 0.9)
	if steer != 0.0:
		return Vector2.from_angle(heading + steer * 0.9) * 0.35 # coasting round a corner
	return Vector2.ZERO


## A hold-to-press pad that works with several fingers at once.
class _Pad extends Control:
	var label := ""
	var down := false
	var _touch := -1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventScreenTouch:
			if e.pressed and _touch == -1:
				_touch = e.index
				_hold(true)
			elif not e.pressed and e.index == _touch:
				_touch = -1
				_hold(false)
			accept_event()
		elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			_hold(e.pressed)
			accept_event()

	func _hold(v: bool) -> void:
		down = v
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
			down = false
			_touch = -1

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.88, 0.66, 0.11, 0.85) if down else Color(0.11, 0.09, 0.07, 0.55)
		sb.border_color = Color(0.95, 0.9, 0.8, 0.6)
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(18)
		draw_style_box(sb, r)
		var font := UiStyle.display()
		var fs := 30 if label.length() <= 2 else 22
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2((size.x - w) * 0.5, size.y * 0.5 + fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#1d1611") if down else Color("#f1e6c8"))
