class_name Minimap3D
extends Control
## Round minimap for 3D Lagos (D-020): roads around you, turned with the camera (up = where the
## camera looks), bus stops, other vehicles, and the next stop (pinned to the rim when far).

const RADIUS := 105.0 # px
const METRES := 140.0 # metres from the centre to the rim

var world # Street3D
var _roads: Array = [] # PackedVector2Array in metres (x, z)


func setup(w) -> void:
	world = w
	_roads.clear() # a new region's map
	# Roads cut into ~8 m pieces, so the map can draw only the pieces inside its circle.
	for r: Dictionary in world.map.roads:
		var src: PackedVector2Array = r["points"]
		var pts := PackedVector2Array()
		for i in src.size() - 1:
			var a := src[i] * Terrain3D.K
			var b := src[i + 1] * Terrain3D.K
			var n := maxi(1, int(a.distance_to(b) / 8.0))
			for j in n:
				pts.append(a.lerp(b, float(j) / n))
		if src.size() > 0:
			pts.append(src[src.size() - 1] * Terrain3D.K)
		var box := Rect2(pts[0], Vector2.ZERO)
		for q in pts:
			box = box.expand(q)
		_roads.append([pts, float(r["width"]) * Terrain3D.K, box.grow(10.0)])
	custom_minimum_size = Vector2(RADIUS * 2.0, RADIUS * 2.0)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


var _redraw_t := 0.0


func _process(d: float) -> void:
	_redraw_t -= d
	if _redraw_t <= 0.0:
		_redraw_t = 0.08 # 12 redraws a second is plenty for a minimap
		queue_redraw()


func _to_screen(p: Vector2, f: Vector3, yaw: float) -> Vector2:
	var r := Vector2(p.x - f.x, p.y - f.z)
	var x := r.x * cos(yaw) - r.y * sin(yaw)
	var y := r.x * sin(yaw) + r.y * cos(yaw)
	return Vector2(RADIUS, RADIUS) + Vector2(x, y) * (RADIUS / METRES)


func _draw() -> void:
	if world == null or not world._built or not is_instance_valid(world.run):
		return
	var c := Vector2(RADIUS, RADIUS)
	draw_circle(c, RADIUS, Color(0.1, 0.09, 0.07, 0.72))
	var f: Vector3 = world.focus()
	var yaw: float = world.cam_yaw
	var k := RADIUS / METRES
	var lim := (RADIUS - 2.0) * (RADIUS - 2.0)
	var view := Rect2(Vector2(f.x, f.z) - Vector2(METRES, METRES), Vector2(METRES, METRES) * 2.0)
	for item: Array in _roads:
		if not (item[2] as Rect2).intersects(view):
			continue
		var pts: PackedVector2Array = item[0]
		var segs := PackedVector2Array()
		var prev := Vector2.INF
		var prev_in := false
		for p in pts:
			var q := _to_screen(p, f, yaw)
			var q_in := q.distance_squared_to(c) < lim
			if prev_in and q_in:
				segs.append(prev)
				segs.append(q)
			prev = q
			prev_in = q_in
		if not segs.is_empty():
			draw_multiline(segs, Color(0.78, 0.74, 0.66, 0.9), maxf(2.0, float(item[1]) * k))
	var run: DanfoRun3D = world.run
	if run:
		for s: Dictionary in run.stops:
			var q := _to_screen(Vector2(s["pos"].x, s["pos"].z), f, yaw)
			if q.distance_to(c) < RADIUS - 4.0:
				draw_rect(Rect2(q - Vector2(4, 4), Vector2(8, 8)), Color("#e0a91c"))
		var t: Variant = run.target()
		if t != null:
			var q := _to_screen(Vector2(t.x, t.z), f, yaw)
			if q.distance_to(c) > RADIUS - 10.0:
				q = c + (q - c).normalized() * (RADIUS - 10.0)
			draw_circle(q, 8.0, Color("#f6d04d"))
			draw_arc(q, 9.0, 0, TAU, 20, Color("#1d1611"), 2.0)
	for v: Vehicle3D in world.vehicles:
		if v == world.ride:
			continue
		var q := _to_screen(Vector2(v.position.x, v.position.z), f, yaw)
		if q.distance_to(c) < RADIUS - 3.0:
			draw_circle(q, 2.5, Color(0.55, 0.75, 0.95, 0.9))
	# The police: their search circle, and each unit flashing red and blue.
	var pol: Police3D = world.police
	if pol and pol.stage == Police3D.Stage.SEARCH:
		var q := _to_screen(Vector2(pol.last_seen.x, pol.last_seen.z), f, yaw)
		var r: float = pol.search_r * k
		var cb := bool(Settings.get_pref("colorblind", false))
		draw_circle(q, minf(r, RADIUS * 2.0), Color(0.3, 0.5, 1.0, 0.18) if cb else Color(0.95, 0.25, 0.2, 0.16))
		draw_arc(q, minf(r, RADIUS * 2.0), 0, TAU, 40, Color(0.3, 0.5, 1.0, 0.8) if cb else Color(0.95, 0.3, 0.25, 0.75), 2.0)
	if pol:
		for u in pol.units:
			var q := _to_screen(Vector2(u.position.x, u.position.z), f, yaw)
			if q.distance_to(c) > RADIUS - 6.0:
				q = c + (q - c).normalized() * (RADIUS - 6.0)
			draw_circle(q, 4.5, Color(0.95, 0.15, 0.1) if int(Time.get_ticks_msec() / 250) % 2 == 0 else Color(0.2, 0.35, 1.0))
	# You: an arrow pointing where you face.
	var face: float = (world.ride.heading - PI * 0.5) if world.ride else (world.player.facing() + PI)
	var ang := face - yaw # 0 = towards the camera (down), PI = away (up)
	var dir := Vector2(sin(ang), cos(ang)) * -1.0
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([c + dir * 11.0, c - dir * 7.0 + side * 7.0, c - dir * 3.0, c - dir * 7.0 - side * 7.0]), Color("#e8483a"))
	draw_arc(c, RADIUS, 0, TAU, 48, Color(0.95, 0.9, 0.8, 0.6), 3.0)
