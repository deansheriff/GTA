class_name UiStyle
extends RefCounted
## Shared look for every screen (M13): one type family used everywhere (a sturdy body face and a
## heavier, slightly spaced display face for headings and buttons), and phone safe areas so
## nothing sits under a notch or a rounded corner.
## The faces are variations of the engine's built-in font, so no font file has to ship; a licensed
## display font can replace `display()` later without touching any screen.

const INK := Color("#1d1611")
const DANFO := Color("#e0a91c")
const PAPER := Color("#f1e6c8")
const GREEN := Color("#2f8a52")
const RED := Color("#a8382c")

static var _body: FontVariation
static var _display: FontVariation


static func body() -> Font:
	if _body == null:
		_body = FontVariation.new()
		_body.base_font = ThemeDB.fallback_font
		_body.variation_embolden = 0.25
	return _body


## Headings, buttons, the money counter, banners: heavier and a touch wider.
static func display() -> Font:
	if _display == null:
		_display = FontVariation.new()
		_display.base_font = ThemeDB.fallback_font
		_display.variation_embolden = 0.85
		_display.spacing_glyph = 1
		_display.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-0.06, 1.0), Vector2.ZERO) # a slight forward lean
	return _display


## Fonts for a theme: body everywhere, display on buttons.
static func apply(theme: Theme) -> void:
	theme.default_font = body()
	theme.set_font("font", "Button", display())
	theme.set_font("font", "OptionButton", display())


## Keep a full-screen HUD root inside the phone's safe area (notches, rounded corners).
static func fit_safe_area(root: Control) -> void:
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0 or safe.size.x <= 0 or safe.size == win:
		return
	var vp := root.get_viewport_rect().size
	var k := vp / Vector2(win)
	var left := float(safe.position.x) * k.x
	var top := float(safe.position.y) * k.y
	var right := float(win.x - safe.end.x) * k.x
	var bottom := float(win.y - safe.end.y) * k.y
	root.offset_left = clampf(left, 0.0, 120.0)
	root.offset_top = clampf(top, 0.0, 120.0)
	root.offset_right = -clampf(right, 0.0, 120.0)
	root.offset_bottom = -clampf(bottom, 0.0, 120.0)


static func release() -> void:
	_body = null
	_display = null
