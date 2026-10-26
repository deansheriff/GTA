class_name MapScreen3D
extends Control
## The full-screen map (D-033): the whole of Lagos (or the region you're in): land, lagoon and sea,
## every road, district names, landmarks, you, the next mission, the objective, filling stations,
## mechanics, the vehicle dealer and boat yard, job boards, Mama Àgbà's stall, Lagos Stories you've
## found, the police search circle and your waypoint.
## Drag to pan, pinch or scroll (or + / −) to zoom, tap to drop a waypoint (tap it again to clear
## it). The waypoint shows on the minimap and the objective arrow. The game pauses while it's open.

signal closed

var world # Street3D
var center := Vector2.ZERO # metres
var zoom := 1.0 # pixels per metre
var _land: Array = [] # PackedVector2Array (metres)
var _inner: Array = [] # each land polygon shrunk by the beach (metres), for the green
var _lagoon := PackedVector2Array()
var _roads: Array = [] # [PackedVector2Array, width m, class]
var _drag_from := Vector2.INF
var _moved := 0.0
var _touches := {} # index -> position (pinch zoom)
var _pinch := 0.0
var _font: Font
var _legend: Label

const WATER := Color("#2a5f78")
const LAGOON := Color("#2f6d84")
const LAND := Color("#55603e")
const SAND := Color("#c9b083")
const ROAD := Color("#e8dcc0")
const MAIN := Color("#f0c454")


func setup(w) -> void:
	world = w
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = UiStyle.display()
	visible = false
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(140, 60)
	close.anchor_left = 1.0
	close.anchor_right = 1.0
	close.offset_left = -160
	close.offset_right = -20
	close.offset_top = 20
	close.offset_bottom = 80
	close.pressed.connect(close_map)
	add_child(close)
	for spec: Array in [["+", -150.0, 1.4], ["−", -80.0, 1.0 / 1.4]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(60, 60)
		b.anchor_left = 1.0
		b.anchor_right = 1.0
		b.anchor_top = 1.0
		b.anchor_bottom = 1.0
		b.offset_left = spec[1]
		b.offset_right = float(spec[1]) + 60.0
		b.offset_top = -90
		b.offset_bottom = -30
		var k: float = spec[2]
		b.pressed.connect(func() -> void: _zoom_by(k, size * 0.5))
		add_child(b)
	_legend = Label.new()
	_legend.position = Vector2(20, 20)
	_legend.add_theme_font_size_override("font_size", 17)
	_legend.add_theme_color_override("font_color", UiStyle.PAPER)
	_legend.add_theme_color_override("font_outline_color", UiStyle.INK)
	_legend.add_theme_constant_override("outline_size", 6)
	_legend.text = "▲ You   ◆ Objective   ● Next mission   ✚ Waypoint\nF Fuel   R Repairs   $ Dealer / boats   J Jobs   M Mama Àgbà   ✦ Lagos Story\nDrag to move · pinch or scroll to zoom · tap to set a waypoint"
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_legend)


## The map changed (another region): read its shapes again.
func rebuild() -> void:
	var map: MapData = world.map
	_land.clear()
	_inner.clear()
	for poly in map.land_polys:
		var p := PackedVector2Array()
		for v in poly:
			p.append(v * Terrain3D.K)
		_land.append(p)
		# The green inland of each shore, worked out once (a sandy 8 m beach round it).
		for q in Geometry2D.offset_polygon(p, -8.0):
			if q.size() > 2:
				_inner.append(q)
	_lagoon = PackedVector2Array()
	for v in map.lagoon_poly:
		_lagoon.append(v * Terrain3D.K)
	_roads.clear()
	for r: Dictionary in map.roads:
		var pts := PackedVector2Array()
		for v in r["points"]:
			pts.append(v * Terrain3D.K)
		_roads.append([pts, float(r["width"]) * Terrain3D.K, String(r["class"])])


var _from_pause := false


func open_map(from_pause := false) -> void:
	_from_pause = from_pause
	if _land.is_empty():
		rebuild()
	var f: Vector3 = world.focus()
	center = Vector2(f.x, f.z)
	var span := Vector2(world.map.cols, world.map.rows) * Terrain3D.CELL_M
	zoom = clampf(minf(size.x / span.x, size.y / span.y) * 1.4, 0.15, 6.0)
	visible = true
	get_tree().paused = true
	Clock.paused = true
	Sound.sfx("tap")
	queue_redraw()


func close_map() -> void:
	visible = false
	if _from_pause:
		world.hud.pause.open() # back where the player came from; still paused
	else:
		get_tree().paused = false
		Clock.paused = false
	_from_pause = false
	closed.emit()


func _to_screen(p: Vector2) -> Vector2:
	return (p - center) * zoom + size * 0.5


func _to_world(s: Vector2) -> Vector2:
	return (s - size * 0.5) / zoom + center


func _zoom_by(k: float, at: Vector2) -> void:
	var before := _to_world(at)
	zoom = clampf(zoom * k, 0.12, 8.0)
	center += before - _to_world(at)
	queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
			if _touches.size() == 1:
				_drag_from = e.position
				_moved = 0.0
			elif _touches.size() == 2:
				var v: Array = _touches.values()
				_pinch = (v[0] as Vector2).distance_to(v[1])
		else:
			_touches.erase(e.index)
			if _touches.is_empty() and _moved < 12.0 and _drag_from != Vector2.INF:
				_tap(e.position)
			_drag_from = Vector2.INF
		accept_event()
	elif e is InputEventScreenDrag:
		_touches[e.index] = e.position
		if _touches.size() >= 2:
			var v: Array = _touches.values()
			var d := (v[0] as Vector2).distance_to(v[1])
			if _pinch > 0.0:
				_zoom_by(d / _pinch, ((v[0] as Vector2) + (v[1] as Vector2)) * 0.5)
			_pinch = d
			_moved = 999.0
		else:
			center -= e.relative / zoom
			_moved += e.relative.length()
			queue_redraw()
		accept_event()
	elif e is InputEventMouseButton and not DisplayServer.is_touchscreen_available():
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			_zoom_by(1.15, e.position)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			_zoom_by(1.0 / 1.15, e.position)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_drag_from = e.position
				_moved = 0.0
			else:
				if _moved < 6.0:
					_tap(e.position)
				_drag_from = Vector2.INF
		accept_event()
	elif e is InputEventMouseMotion and _drag_from != Vector2.INF and e.button_mask & MOUSE_BUTTON_MASK_LEFT:
		center -= e.relative / zoom
		_moved += e.relative.length()
		queue_redraw()
		accept_event()


func _unhandled_input(e: InputEvent) -> void:
	if visible and e is InputEventKey and e.pressed and not e.echo and e.physical_keycode in [KEY_ESCAPE, KEY_M]:
		close_map()
		get_viewport().set_input_as_handled()


## Tap: drop a waypoint there (or clear the one you tapped).
func _tap(at: Vector2) -> void:
	var w := _to_world(at)
	if world.waypoint != null:
		var cur: Vector3 = world.waypoint
		if _to_screen(Vector2(cur.x, cur.z)).distance_to(at) < 28.0:
			world.waypoint = null
			Sound.sfx("tap", 0.8)
			queue_redraw()
			return
	world.waypoint = Vector3(w.x, 0, w.y)
	Sound.sfx("tap", 1.3)
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var map: MapData = world.map
	draw_rect(Rect2(Vector2.ZERO, size), WATER if not map.inland else LAND.darkened(0.2))
	if _lagoon.size() > 2:
		draw_colored_polygon(_xf(_lagoon), LAGOON)
	for poly: PackedVector2Array in _land:
		var sp := _xf(poly)
		draw_colored_polygon(sp, SAND)
		if map.inland:
			draw_colored_polygon(sp, LAND)
	if not map.inland:
		# A shrunk copy in green inside the sand gives a beach round every shore.
		for poly: PackedVector2Array in _inner:
			draw_colored_polygon(_xf(poly), LAND)
	for r: Array in _roads:
		var pts := _xf(r[0])
		var wpx := maxf(1.5, float(r[1]) * zoom)
		draw_polyline(pts, (MAIN if r[2] != "street" else ROAD), wpx, true)
	# Stilt villages.
	for v: Dictionary in map.stilt_villages:
		var c := _to_screen((v["center"] as Vector2) * Terrain3D.K)
		draw_circle(c, float(v["radius"]) * Terrain3D.K * zoom, Color(0.45, 0.33, 0.22, 0.6))
	# District names.
	for d: Dictionary in map.districts:
		var c := _to_screen((d["center"] as Vector2) * Terrain3D.K)
		_text(c, String(d["name"]).to_upper(), 17 if zoom < 1.2 else 20, Color(1, 1, 1, 0.75))
	# Landmarks (names once you've zoomed in).
	for id in map.landmarks:
		var lm: Dictionary = map.landmarks[id]
		var c := _to_screen((lm["pos"] as Vector2) * Terrain3D.K)
		draw_circle(c, 3.5, Color(0.95, 0.92, 0.85))
		if zoom > 1.1:
			_text(c + Vector2(0, -12), String(lm["name"]), 14, UiStyle.PAPER)
	# Services (Lagos).
	if world.roam:
		for st: Dictionary in world.roam.stations:
			var c := _to_screen(Vector2(st["pos"].x, st["pos"].z))
			var icon: String = { "fuel": "F", "mechanic": "R", "dealer": "$", "boats": "$", "jobs": "J", "stall": "M" }.get(String(st["kind"]), "•")
			var col: Color = { "fuel": Color("#4fd17a"), "mechanic": Color("#c0c0c0"), "dealer": Color("#f6d04d"), "boats": Color("#f6d04d"), "jobs": Color("#6fc6ff"), "stall": Color("#ff9a6a") }.get(String(st["kind"]), Color.WHITE)
			draw_circle(c, 11.0, Color(0.08, 0.06, 0.04, 0.8))
			_text(c + Vector2(0, 6), icon, 16, col)
	if world.explore:
		for s: Dictionary in Explore3D.STORIES:
			if world.roam.found.has(s["id"]) and world.explore._story_pos.has(s["id"]):
				var p: Vector3 = world.explore._story_pos[s["id"]]
				_text(_to_screen(Vector2(p.x, p.z)) + Vector2(0, 7), "✦", 18, Color("#f6d04d"))
	# The police search circle.
	if world.police and world.police.stage == Police3D.Stage.SEARCH:
		var c := _to_screen(Vector2(world.police.last_seen.x, world.police.last_seen.z))
		draw_circle(c, world.police.search_r * zoom, Color(0.95, 0.25, 0.2, 0.2))
		draw_arc(c, world.police.search_r * zoom, 0, TAU, 48, Color(0.95, 0.3, 0.25, 0.8), 2.0)
	# The next mission, the objective, the waypoint.
	if world.stage and world.stage._marker.visible:
		var m: Vector3 = world.stage._marker.position
		var c := _to_screen(Vector2(m.x, m.z))
		draw_circle(c, 10.0, Color("#e8483a"))
		draw_arc(c, 10.0, 0, TAU, 20, UiStyle.INK, 2.0)
		_text(c + Vector2(0, -16), String(world.stage._marker_label.text), 16, Color("#ffb0a0"))
	var t: Variant = world.run.target() if is_instance_valid(world.run) and world.run.story_target != null else null
	if t != null:
		var c := _to_screen(Vector2((t as Vector3).x, (t as Vector3).z))
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -11), c + Vector2(11, 0), c + Vector2(0, 11), c + Vector2(-11, 0)]), Color("#f6d04d"))
	if world.waypoint != null:
		var wp: Vector3 = world.waypoint
		var c := _to_screen(Vector2(wp.x, wp.z))
		draw_line(c + Vector2(-10, 0), c + Vector2(10, 0), Color("#4fb3ff"), 4.0)
		draw_line(c + Vector2(0, -10), c + Vector2(0, 10), Color("#4fb3ff"), 4.0)
		draw_arc(c, 13.0, 0, TAU, 24, Color("#4fb3ff"), 2.0)
	# You.
	var f: Vector3 = world.focus()
	var you := _to_screen(Vector2(f.x, f.z))
	var face: float = (-world.ride.heading + PI * 0.5) if world.ride else world.player.facing()
	var dir := Vector2(sin(face), cos(face))
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([you + dir * 14.0, you - dir * 9.0 + side * 9.0, you - dir * 4.0, you - dir * 9.0 - side * 9.0]), Color("#e8483a"))
	draw_polyline(PackedVector2Array([you + dir * 14.0, you - dir * 9.0 + side * 9.0, you - dir * 4.0, you - dir * 9.0 - side * 9.0, you + dir * 14.0]), Color.WHITE, 2.0)
	_text(Vector2(size.x * 0.5, size.y - 24), String(map.title).to_upper(), 22, UiStyle.DANFO)


func _xf(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = _to_screen(pts[i])
	return out


func _text(at: Vector2, s: String, sz: int, col: Color) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string_outline(_font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 5, UiStyle.INK)
	draw_string(_font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
