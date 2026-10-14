class_name Nav
extends RefCounted
## Pathfinding on the map grid (Godot's native AStarGrid2D):
##   walk: anything not blocked; pavements are cheapest, open ground costs a little more.
##   drive: roads and bridges are cheap, everything else is very expensive (GPS routes stick to roads).

var map: MapData
var walk := AStarGrid2D.new()
var drive := AStarGrid2D.new()


func setup(m: MapData) -> void:
	map = m
	for g in [walk, drive]:
		g.region = Rect2i(0, 0, m.cols, m.rows)
		g.cell_size = Vector2(MapData.CELL, MapData.CELL)
		g.offset = Vector2(MapData.CELL, MapData.CELL) * 0.5
		g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		g.update()
	for y in m.rows:
		for x in m.cols:
			var i := y * m.cols + x
			var c := Vector2i(x, y)
			var s := m.surface[i]
			var solid := m.blocked[i] == 1
			walk.set_point_solid(c, solid)
			if not solid:
				walk.set_point_weight_scale(c, 1.0 if s == MapData.S.WALK else (1.6 if m.is_roadlike(s) else 1.25))
			drive.set_point_solid(c, m.is_water(s) and not m.is_roadlike(s) or (m.occupied[i] == 1))
			drive.set_point_weight_scale(c, 1.0 if m.is_roadlike(s) else 25.0)


func _path(g: AStarGrid2D, from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := _nearest_open(g, map.cell_of(from))
	var b := _nearest_open(g, map.cell_of(to))
	if a == Vector2i(-1, -1) or b == Vector2i(-1, -1):
		return PackedVector2Array()
	var pts := g.get_point_path(a, b, true)
	if pts.size() > 0:
		pts[pts.size() - 1] = to if not map.is_blocked(to) else pts[pts.size() - 1]
	return pts


func walk_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	return _simplify(_path(walk, from, to))


func drive_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	return _simplify(_path(drive, from, to))


func _nearest_open(g: AStarGrid2D, c: Vector2i) -> Vector2i:
	for r in 4:
		for y in range(c.y - r, c.y + r + 1):
			for x in range(c.x - r, c.x + r + 1):
				var q := Vector2i(x, y)
				if g.is_in_boundsv(q) and not g.is_point_solid(q):
					return q
	return Vector2i(-1, -1)


## Drop points on straight runs so walkers move smoothly.
func _simplify(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size() - 1):
		var d1 := (pts[i] - pts[i - 1]).normalized()
		var d2 := (pts[i + 1] - pts[i]).normalized()
		if d1.dot(d2) < 0.999:
			out.append(pts[i])
	out.append(pts[pts.size() - 1])
	return out
