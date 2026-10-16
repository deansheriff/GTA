class_name LightLayer
extends Node
## Cheap night lighting for low-end phones: light pools are additive sprites rendered into a small
## off-screen buffer that follows the camera; one full-screen multiply pass then darkens the world
## everywhere except where it is lit. Cost is constant however many lights the city has.

var _vp: SubViewport
var _cam: Camera2D
var _overlay: ColorRect
var _layer: CanvasLayer
var _tex: Texture2D
var _lights := {} # int handle -> {sprite, generator}
var _next := 1
var _night := false
var _nepa_on := true
var _enabled := true
var _res_scale := 0.5
var night_color := Color(0.36, 0.34, 0.52)
var darkness := 1.0 # 0 day … 1 full night (dusk/dawn blend)
var blackout_color := Color(0.17, 0.15, 0.28)


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.disable_3d = true
	_vp.transparent_bg = true # unlit = (0,0,0,0); lights add on top
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_cam = Camera2D.new()
	_vp.add_child(_cam)
	_cam.make_current()
	var tex := GradientTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.92, 0.7, 1.0), Color(1.0, 0.85, 0.55, 0.45), Color(1, 0.8, 0.5, 0.0)])
	tex.gradient = g
	_tex = tex
	_layer = CanvasLayer.new()
	_layer.layer = 4 # above the world, below the vignette and HUD
	add_child(_layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/night.gdshader")
	mat.set_shader_parameter("light_tex", _vp.get_texture())
	_overlay.material = mat
	_layer.add_child(_overlay)
	_overlay.visible = false


func configure(enabled: bool, res_scale: float) -> void:
	_enabled = enabled
	_res_scale = res_scale
	_refresh()


func add_light(pos: Vector2, radius: float, energy: float, generator: bool) -> int:
	var s := Sprite2D.new()
	s.texture = _tex
	s.position = pos
	s.scale = Vector2.ONE * (radius * 2.0 / 128.0)
	s.modulate = Color(1, 1, 1, energy)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = m
	_vp.add_child(s)
	var h := _next
	_next += 1
	_lights[h] = { "sprite": s, "generator": generator }
	s.visible = _lit(generator)
	return h


## A light that moves (vehicle headlights and tail lights, M13): any texture and colour, always
## on whatever NEPA is doing (they run on the vehicle's battery). Place it with move_light().
func add_moving_light(tex: Texture2D, col: Color) -> int:
	var s := Sprite2D.new()
	s.texture = tex
	s.modulate = col
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = m
	_vp.add_child(s)
	var h := _next
	_next += 1
	_lights[h] = { "sprite": s, "generator": false, "always": true }
	return h


func move_light(h: int, pos: Vector2, rot: float, scale: Vector2) -> void:
	if not _lights.has(h):
		return
	var s: Sprite2D = _lights[h]["sprite"]
	s.position = pos
	s.rotation = rot
	s.scale = scale


func is_night() -> bool:
	return _night and darkness > 0.05


func radial_texture() -> Texture2D:
	return _tex


func remove_light(h: int) -> void:
	if _lights.has(h):
		(_lights[h]["sprite"] as Node).queue_free()
		_lights.erase(h)


func set_state(night: bool, nepa_on: bool) -> void:
	_night = night
	_nepa_on = nepa_on
	_refresh()


func _lit(generator: bool) -> bool:
	return (not _nepa_on) if generator else _nepa_on


func _refresh() -> void:
	var on := _night and darkness > 0.02
	_overlay.visible = on
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on and _enabled else SubViewport.UPDATE_DISABLED
	var mat := _overlay.material as ShaderMaterial
	var base: Color = night_color if _nepa_on else blackout_color
	mat.set_shader_parameter("dark", Color.WHITE.lerp(base, darkness))
	mat.set_shader_parameter("use_lights", _enabled)
	for h in _lights:
		(_lights[h]["sprite"] as Sprite2D).visible = _lights[h].get("always", false) or _lit(_lights[h]["generator"])


## Keep the light buffer aligned with the game camera.
func sync(cam: Camera2D, screen: Vector2) -> void:
	if not _overlay.visible or not _enabled:
		return
	var size := Vector2i(maxi(64, int(screen.x * _res_scale)), maxi(64, int(screen.y * _res_scale)))
	if _vp.size != size:
		_vp.size = size
	_cam.position = cam.get_screen_center_position()
	_cam.zoom = cam.zoom * _res_scale
