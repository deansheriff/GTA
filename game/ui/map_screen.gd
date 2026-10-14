extends Control
## Full-screen map of tropical-island Lagos: districts, story landmarks, you, other players and the
## GPS route. Tap anywhere to set a waypoint; tap a landmark to route there.

signal waypoint_set(pos: Vector2)
signal waypoint_cleared
signal closed

var map: MapData
var player_pos := Vector2.ZERO
var waypoint := Vector2.INF
var route := PackedVector2Array()
var _map_rect := Rect2()
var _tex: TextureRect


func setup(m: MapData, land: Texture2D, road: Texture2D) -> void:
	map = m
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.05, 0.92)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_tex = TextureRect.new()
	_tex.texture = land
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/minimap.gdshader")
	mat.set_shader_parameter("land_tex", land)
	mat.set_shader_parameter("road_tex", road)
	mat.set_shader_parameter("center_uv", Vector2(0.5, 0.5))
	mat.set_shader_parameter("span_uv", Vector2.ONE)
	_tex.material = mat
	add_child(_tex)
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(func() -> void: _draw_overlay(overlay))
	add_child(overlay)
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.position = Vector2(-16, 12)
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	var clear := Button.new()
	clear.text = "Clear route"
	clear.pressed.connect(func() -> void:
		waypoint = Vector2.INF
		route = PackedVector2Array()
		waypoint_cleared.emit()
		overlay.queue_redraw())
	bar.add_child(clear)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	bar.add_child(close)
	resized.connect(_layout)
	_layout()


func refresh(player: Vector2, wp: Vector2, r: PackedVector2Array) -> void:
	_layout() # size is only known once the screen is visible
	player_pos = player
	waypoint = wp
	route = r
	(get_child(2) as Control).queue_redraw()


func _layout() -> void:
	if size.x < 10.0:
		return
	var avail := size - Vector2(32, 72)
	var s := minf(avail.x / map.world_px.x, avail.y / map.world_px.y)
	var sz := map.world_px * s
	_map_rect = Rect2((size - sz) * 0.5 + Vector2(0, 24), sz)
	_tex.position = _map_rect.position
	_tex.size = _map_rect.size


func _to_screen(p: Vector2) -> Vector2:
	return _map_rect.position + p / map.world_px * _map_rect.size


func _to_world(sp: Vector2) -> Vector2:
	return (sp - _map_rect.position) / _map_rect.size * map.world_px


func _draw_overlay(c: Control) -> void:
	var font := ThemeDB.fallback_font
	for d in map.districts:
		var sp := _to_screen(d["center"])
		c.draw_string_outline(font, sp - Vector2(80, 0), d["name"], HORIZONTAL_ALIGNMENT_CENTER, 160, 16, 5, Color("#1d1611"))
		c.draw_string(font, sp - Vector2(80, 0), d["name"], HORIZONTAL_ALIGNMENT_CENTER, 160, 16, Color("#f1e6c8"))
	for id in map.landmarks:
		var lp := _to_screen(map.landmarks[id]["pos"])
		c.draw_circle(lp, 5.0, Color("#a8382c"))
		c.draw_arc(lp, 5.0, 0, TAU, 12, Color("#1d1611"), 1.5, true)
		c.draw_string_outline(font, lp + Vector2(8, 4), map.landmarks[id]["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color("#1d1611"))
		c.draw_string(font, lp + Vector2(8, 4), map.landmarks[id]["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#f1e6c8"))
	if route.size() > 1:
		var pts := PackedVector2Array()
		for p in route:
			pts.append(_to_screen(p))
		c.draw_polyline(pts, Color("#e0a91c"), 3.0, true)
	if waypoint != Vector2.INF:
		var wp := _to_screen(waypoint)
		c.draw_circle(wp, 7.0, Color("#e0a91c"))
		c.draw_arc(wp, 7.0, 0, TAU, 16, Color("#1d1611"), 2.0, true)
	var pp := _to_screen(player_pos)
	c.draw_circle(pp, 7.0, Color("#f1e6c8"))
	c.draw_arc(pp, 7.0, 0, TAU, 16, Color("#1d1611"), 2.5, true)


func _gui_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed)
	if not pressed or not _map_rect.has_point(event.position):
		return
	var wp := _to_world(event.position)
	# Snap to a nearby landmark if the tap was close to one.
	for id in map.landmarks:
		if _to_screen(map.landmarks[id]["pos"]).distance_to(event.position) < 14.0:
			wp = map.landmarks[id]["pos"]
	waypoint = wp
	waypoint_set.emit(wp)
	accept_event()
