class_name Terrain3D
extends Node3D
## The ground of the whole island in 3D (D-020), built from the 2D map data:
##  - one quad per map cell, batched per surface (grass yards, laterite, sand, pavement, water);
##  - pavements raised 12 cm, so every street gets a kerb;
##  - roads as smooth ribbons along the real road polylines, with white edge lines and dashed
##    centre lines (the cell grid under them is bare laterite, like a Lagos road shoulder);
##  - the lagoon and sea with a moving, glossy water shader.

const K := 0.0625 # metres per map pixel (a 64 px cell is 4 m)
const CELL_M := 4.0
const WALK_H := 0.12
const ROAD_Y := 0.035

var map: MapData


func build(m: MapData) -> void:
	map = m
	_cells()
	_roads()
	_bounds()


static func w(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x * K, y, p.y * K)


## Height of the ground at a world position (pavements are raised).
func height_at(pos: Vector3) -> float:
	var c := Vector2i(int(pos.x / CELL_M), int(pos.z / CELL_M))
	if not map.in_bounds(c):
		return 0.0
	return WALK_H if map.surface[c.y * map.cols + c.x] == MapData.S.WALK else 0.0


static func tex_mat(path: String, tint := Color.WHITE, rough := 0.9, scale := 0.25) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = Art.tex(path)
	m.albedo_color = tint
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _cells() -> void:
	var mats := {
		MapData.S.ROAD: tex_mat("ground/dirt.png", Color(0.74, 0.62, 0.54)), # laterite shoulder under the ribbon
		MapData.S.BRIDGE: tex_mat("ground/asphalt.png", Color(0.75, 0.75, 0.75), 0.75),
		MapData.S.WALK: tex_mat("ground/interlock.png", Color(0.92, 0.9, 0.86)),
		MapData.S.GUTTER: tex_mat("ground/interlock.png", Color(0.45, 0.45, 0.45)),
		MapData.S.GROUND: tex_mat("ground/grass.png", Color(0.47, 0.5, 0.38)),
		MapData.S.BEACH: tex_mat("ground/sand.png"),
	}
	var water := _water_material()
	mats[MapData.S.SEA] = water
	mats[MapData.S.LAGOON] = water
	var buckets := {}
	for y in map.rows:
		for x in map.cols:
			var s := map.surface[y * map.cols + x]
			if not buckets.has(s):
				buckets[s] = []
			buckets[s].append(Vector2i(x, y))
	var quad := PlaneMesh.new()
	quad.size = Vector2(CELL_M, CELL_M)
	var kerb := BoxMesh.new() # pavement slabs: their sides are the kerbs
	kerb.size = Vector3(CELL_M, WALK_H, CELL_M)
	for s in buckets:
		var cells: Array = buckets[s]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var is_walk: bool = s == MapData.S.WALK
		mm.mesh = kerb if is_walk else quad
		mm.instance_count = cells.size()
		var y := WALK_H * 0.5 if is_walk else (-0.35 if map.is_water(s) else 0.0)
		for i in cells.size():
			var c: Vector2i = cells[i]
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3((c.x + 0.5) * CELL_M, y, (c.y + 0.5) * CELL_M)))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mats.get(s, mats[MapData.S.GROUND])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	# Sea beyond the map edge, so the horizon is water, not void.
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(map.cols * CELL_M * 3.0, map.rows * CELL_M * 3.0)
	sea.mesh = pm
	sea.position = Vector3(map.cols * CELL_M * 0.5, -0.4, map.rows * CELL_M * 0.5)
	sea.material_override = water
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)


func _water_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform vec3 deep : source_color = vec3(0.07, 0.30, 0.38);
uniform vec3 shallow : source_color = vec3(0.16, 0.50, 0.55);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float t = TIME * 0.6;
	vec2 p = wpos.xz * 0.35;
	// Two crossing swell patterns bend the normal; cheap enough for low-end phones.
	float a = sin(p.x * 1.7 + t) * cos(p.y * 1.3 - t * 0.8);
	float b = sin((p.x + p.y) * 2.3 - t * 1.4);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(0.18 * a, 0.0, 0.14 * b, 0.0)).xyz);
	ALBEDO = mix(deep, shallow, 0.5 + 0.25 * a);
	ROUGHNESS = 0.06;
	METALLIC = 0.1;
	SPECULAR = 0.8;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


# ---------- roads ----------

func _roads() -> void:
	var asphalt := tex_mat("ground/asphalt.png", Color(0.8, 0.8, 0.8), 0.72, 0.2)
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.9, 0.88, 0.82)
	line_mat.roughness = 1.0
	line_mat.metallic_specular = 0.1 # painted lines are matt: no sky-blue sheen
	var dash_mat := StandardMaterial3D.new()
	dash_mat.albedo_color = Color(0.93, 0.78, 0.25) # yellow centre dashes
	dash_mat.roughness = 1.0
	dash_mat.metallic_specular = 0.1
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lines := SurfaceTool.new()
	lines.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dashes := []
	# Junctions (3+ roads meet): painted lines stop short of them instead of crossing.
	var junctions: Array[Vector2] = []
	for id in map.road_graph:
		if (map.road_graph[id] as Array).size() >= 3:
			junctions.append(map.road_nodes[id])
	# Wider roads first, slightly higher, so junctions don't flicker where ribbons overlap.
	var order := map.roads.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["width"]) < float(b["width"]))
	for i in order.size():
		var r: Dictionary = order[i]
		var pts: PackedVector2Array = r["points"]
		if pts.size() < 2:
			continue
		var half: float = float(r["width"]) * K * 0.5
		var y := ROAD_Y + i * 0.0004
		_ribbon(road, pts, -half, half, y)
		for run in _open_runs(pts, junctions):
			_ribbon(lines, run, half - 0.45, half - 0.3, y + 0.004)
			_ribbon(lines, run, -half + 0.3, -half + 0.45, y + 0.004)
			if half > 2.4:
				_dashes(dashes, run, y + 0.005)
	for pair in [[road, asphalt], [lines, line_mat]]:
		var st: SurfaceTool = pair[0]
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = pair[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	if not dashes.is_empty():
		var dash := BoxMesh.new()
		dash.size = Vector3(2.0, 0.01, 0.16)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = dash
		mm.instance_count = dashes.size()
		for j in dashes.size():
			mm.set_instance_transform(j, dashes[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = dash_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


const JUNCTION_PX := 150.0 # painted lines stop this far (map px) from a junction centre


## The parts of a polyline away from junctions, cut into separate runs (2 m resolution).
func _open_runs(pts: PackedVector2Array, junctions: Array[Vector2]) -> Array[PackedVector2Array]:
	var runs: Array[PackedVector2Array] = []
	var cur := PackedVector2Array()
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var n := maxi(1, int(a.distance_to(b) / 32.0))
		for j in n + 1:
			if j == n and i < pts.size() - 2:
				continue # the next segment starts here
			var p := a.lerp(b, float(j) / n)
			var near := false
			for q in junctions:
				if p.distance_squared_to(q) < JUNCTION_PX * JUNCTION_PX:
					near = true
					break
			if near:
				if cur.size() >= 2:
					runs.append(cur)
				cur = PackedVector2Array()
			else:
				cur.append(p)
	if cur.size() >= 2:
		runs.append(cur)
	return runs


## A strip between two offsets (metres, left negative) along a polyline, with mitred corners.
func _ribbon(st: SurfaceTool, pts: PackedVector2Array, off_a: float, off_b: float, y: float) -> void:
	var n := pts.size()
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for i in n:
		var p := pts[i] * K
		var d_in := (p - pts[i - 1] * K).normalized() if i > 0 else Vector2.ZERO
		var d_out := (pts[i + 1] * K - p).normalized() if i < n - 1 else Vector2.ZERO
		var d := (d_in + d_out).normalized()
		if d == Vector2.ZERO:
			d = d_in if d_in != Vector2.ZERO else d_out
		var nrm := Vector2(-d.y, d.x)
		# Mitre: push corners out so the strip keeps its width through bends (capped).
		var ref := d_in if d_in != Vector2.ZERO else d_out
		var scale := 1.0 / maxf(0.5, nrm.dot(Vector2(-ref.y, ref.x)))
		left.append(Vector3(p.x + nrm.x * off_a * scale, y, p.y + nrm.y * off_a * scale))
		right.append(Vector3(p.x + nrm.x * off_b * scale, y, p.y + nrm.y * off_b * scale))
	for i in n - 1: # clockwise seen from above (Godot's front faces)
		st.add_vertex(left[i])
		st.add_vertex(left[i + 1])
		st.add_vertex(right[i])
		st.add_vertex(right[i])
		st.add_vertex(left[i + 1])
		st.add_vertex(right[i + 1])


func _dashes(out: Array, pts: PackedVector2Array, y: float) -> void:
	var carry := 0.0
	for i in pts.size() - 1:
		var a := pts[i] * K
		var b := pts[i + 1] * K
		var seg := a.distance_to(b)
		var dir := (b - a) / maxf(seg, 0.001)
		var t := carry
		while t < seg:
			var p := a + dir * (t + 1.0)
			out.append(Transform3D(Basis(Vector3.UP, -dir.angle()), Vector3(p.x, y, p.y)))
			t += 5.0
		carry = t - seg


## Invisible walls round the map edge.
func _bounds() -> void:
	var span := Vector3(map.cols * CELL_M, 0, map.rows * CELL_M)
	for side in 4:
		var wall := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		var horiz := side < 2
		bx.size = Vector3(span.x + 8.0, 8.0, 2.0) if horiz else Vector3(2.0, 8.0, span.z + 8.0)
		cs.shape = bx
		wall.add_child(cs)
		wall.position = span * 0.5 + (Vector3(0, 4, (span.z * 0.5 + 1.0) * (1 if side == 0 else -1)) if horiz else Vector3((span.x * 0.5 + 1.0) * (1 if side == 2 else -1), 4, 0))
		add_child(wall)
