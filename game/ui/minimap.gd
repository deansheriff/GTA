extends Control
## Round minimap: painted-map view of the area around the player, with the route, waypoint,
## landmarks and other players. Tap it to open the full map.

signal open_map

const RANGE := 2600.0 # world px shown across the minimap

var map: MapData
var focus := Vector2.ZERO
var heading := 0.0
var waypoint := Vector2.INF
var route := PackedVector2Array()
var others: Array[Vector2] = []
var stars: Array[Vector2] = [] # story mission starts
## Street hazards and events (M13): [{pos, kind}] kind = checkpoint | van | flood | event
var marks: Array = []
var _rect: TextureRect


func setup(m: MapData, land: Texture2D, road: Texture2D) -> void:
	map = m
	custom_minimum_size = Vector2(176, 176)
	size = custom_minimum_size
	_rect = TextureRect.new()
	_rect.texture = land
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/minimap.gdshader")
	mat.set_shader_parameter("land_tex", land)
	mat.set_shader_parameter("road_tex", road)
	mat.set_shader_parameter("round_mask", true)
	mat.set_shader_parameter("span_uv", Vector2(RANGE, RANGE) / m.world_px)
	_rect.material = mat
	add_child(_rect)
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(func() -> void: _draw_overlay(overlay))
	add_child(overlay)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true # keep the route line inside the minimap


func update_view(f: Vector2, h: float) -> void:
	focus = f
	heading = h
	(_rect.material as ShaderMaterial).set_shader_parameter("center_uv", f / map.world_px)
	(get_child(1) as Control).queue_redraw()


func _to_local(p: Vector2) -> Vector2:
	return size * 0.5 + (p - focus) / RANGE * size.x


func _inside(lp: Vector2) -> bool:
	return lp.distance_to(size * 0.5) < size.x * 0.46


func _draw_overlay(c: Control) -> void:
	if route.size() > 1:
		var pts := PackedVector2Array()
		for p in route:
			pts.append(_to_local(p))
		c.draw_polyline(pts, Color("#e0a91c"), 3.0, true)
	for id in map.landmarks:
		var lp := _to_local(map.landmarks[id]["pos"])
		if _inside(lp):
			c.draw_circle(lp, 4.0, Color("#a8382c"))
			c.draw_arc(lp, 4.0, 0, TAU, 12, Color("#1d1611"), 1.5, true)
	for s in stars:
		var lp := _to_local(s)
		if not _inside(lp):
			lp = size * 0.5 + (lp - size * 0.5).normalized() * size.x * 0.44
		_star(c, lp, 7.0)
	for o in others:
		var lp := _to_local(o)
		if _inside(lp):
			c.draw_circle(lp, 3.5, Color("#2f6f99"))
	var blink := int(Time.get_ticks_msec() / 250) % 2 == 0
	for m: Dictionary in marks:
		var lp := _to_local(m["pos"])
		if not _inside(lp):
			continue
		match String(m["kind"]):
			"checkpoint":
				c.draw_rect(Rect2(lp - Vector2(5, 5), Vector2(10, 10)), Color("#e86a1c"))
				c.draw_rect(Rect2(lp - Vector2(5, 5), Vector2(10, 10)), Color("#1d1611"), false, 1.5)
			"van":
				c.draw_circle(lp, 5.0, Color("#ff3a2a") if blink else Color("#3a6cff"))
				c.draw_arc(lp, 5.0, 0, TAU, 12, Color("#1d1611"), 1.5, true)
			"flood":
				c.draw_circle(lp, 6.0, Color(0.35, 0.6, 0.85, 0.75))
			"event":
				c.draw_circle(lp, 7.0, Color("#e0a91c"))
				c.draw_string(ThemeDB.fallback_font, lp + Vector2(-3, 5), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#1d1611"))
	if waypoint != Vector2.INF:
		var lp := _to_local(waypoint)
		if not _inside(lp): # clamp to the rim as a direction hint
			lp = size * 0.5 + (lp - size * 0.5).normalized() * size.x * 0.44
		c.draw_circle(lp, 6.0, Color("#e0a91c"))
		c.draw_arc(lp, 6.0, 0, TAU, 16, Color("#1d1611"), 2.0, true)
	# Player arrow.
	var ctr := size * 0.5
	var f := Vector2.from_angle(heading)
	var side := Vector2(-f.y, f.x)
	c.draw_colored_polygon(PackedVector2Array([ctr + f * 9.0, ctr - f * 6.0 + side * 6.0, ctr - f * 3.0, ctr - f * 6.0 - side * 6.0]), Color("#f1e6c8"))
	c.draw_polyline(PackedVector2Array([ctr + f * 9.0, ctr - f * 6.0 + side * 6.0, ctr - f * 3.0, ctr - f * 6.0 - side * 6.0, ctr + f * 9.0]), Color("#1d1611"), 1.5, true)


func _star(c: Control, at: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		pts.append(at + Vector2.from_angle(-PI / 2 + i * PI / 5.0) * (r if i % 2 == 0 else r * 0.45))
	c.draw_colored_polygon(pts, Color("#e0a91c"))
	pts.append(pts[0])
	c.draw_polyline(pts, Color("#1d1611"), 1.5, true)


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		open_map.emit()
		accept_event()
