class_name City3D
extends Node3D
## Buildings and street props for the whole island (D-020), from the map's building and prop lists.
## Each building gets a Meshy model chosen by its type, district and landmark, turned to face its
## road, with a solid collision box, its painted shop sign and its generator.
## Performance (phone feedback, 2026-10-19): models aren't separate scene instances. Every copy is
## a transform in a MultiMesh per model part per 48 m area, so the whole city is a few hundred draws
## at most, and far areas are culled as blocks.

const K := Terrain3D.K
const BUILDING_FAR := 170.0
const PROP_FAR := 95.0

var map: MapData
var models: Models3D
var obstacles: Array[Vector3] = [] # solid props as (x, z, radius) for people to walk round
var far_scale := 1.0 # graphics preset: shorter draw distance on low-end phones
const CHUNK := 48.0
var debug_spots: Array[Vector3] = [] # QA: where some kit buildings stand
var _batch := {} # model key -> {xforms: Array[Transform3D], far: float, shadow: bool}
var _templates := {} # model key -> {parts: [[mesh, xform]], aabb: AABB}


func build(m: MapData, lib: Models3D) -> void:
	map = m
	models = lib
	_buildings()
	_props()
	_street_furniture()
	_build_batches()


func _buildings() -> void:
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color("#8a5a3c")
	roof_mat.roughness = 0.55
	roof_mat.metallic = 0.35
	for b in map.buildings:
		var fp: Rect2 = b.footprint()
		var size := Vector3(fp.size.x * K - 0.6, clampf(b.height * K * 1.25, 3.2, 7.5), fp.size.y * K - 0.6)
		var body := StaticBody3D.new()
		body.position = Terrain3D.w(fp.get_center())
		add_child(body)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position.y = size.y * 0.5
		body.add_child(shape)
		var dist: Dictionary = map.district_at(fp.get_center())
		var key := models.building_key(b.art, b.seed, String(dist.get("id", "")), b.landmark)
		var face := _road_side(fp)
		var holder := Node3D.new()
		holder.rotation.y = face
		body.add_child(holder)
		var quarter := absf(sin(face)) > 0.5
		var local := Vector3(size.z, size.y, size.x) if quarter else size
		var base := Transform3D(Basis(Vector3.UP, face), body.position)
		if key != "" and _template(key) != null:
			_place_row(key, local, base, key in ["office_tower", "apartment"], key.begins_with("city_"))
		else:
			_box(holder, local, b.wall, roof_mat)
		if b.sign_text != "":
			_sign(holder, b.sign_text, local)
		if b.generator:
			_queue_fit("generator", 0.9, base * Transform3D(Basis(), Vector3(local.x * 0.5 + 0.6, 0, local.z * 0.5 - 0.8)), PROP_FAR, false)
		_yard(base, key, local, b.seed)
		Models3D.far_cull(body, BUILDING_FAR * far_scale)


## Lived-in details: an overhead water tank behind some houses, plastic tables out front of
## canteens, shops and bars.
func _yard(base: Transform3D, key: String, size: Vector3, seed: int) -> void:
	var adds := []
	if seed % 4 == 0 and key in ["bungalow", "island_cottage", "shop", "apartment", "shack", "mansion"]:
		adds.append(["water_tank", 3.6, Vector3(size.x * 0.5 - 1.2, 0, -size.z * 0.5 - 1.4)])
	if key in ["canteen", "provision_store", "beach_bar", "pos_shop"]:
		adds.append(["plastic_table", 0.8, Vector3(-size.x * 0.25, 0, size.z * 0.5 + 2.2)])
	# Window AC units on the street front, the Lagos skyline's signature.
	if key in ["shop", "apartment", "provision_store", "canteen", "pos_shop"] and seed % 2 == 0:
		adds.append(["ac_unit", 0.6, Vector3(size.x * 0.28, 2.7, size.z * 0.5 + 0.12)])
		if key == "apartment":
			adds.append(["ac_unit", 0.6, Vector3(-size.x * 0.22, 5.4, size.z * 0.5 + 0.12)])
	for a: Array in adds:
		var yaw := 0.0 if a[0] == "ac_unit" else float(seed % 7) * 0.4 # AC units face the street
		_queue_fit(a[0], float(a[1]), base * Transform3D(Basis(Vector3.UP, yaw), a[2]), PROP_FAR, false)


## The yaw that turns a model's front (+Z) towards the side of the footprint with the most road.
func _road_side(fp: Rect2) -> float:
	var best := 0.0
	var most := -1
	for side in [[Vector2(0, 1), 0.0], [Vector2(0, -1), PI], [Vector2(1, 0), PI * 0.5], [Vector2(-1, 0), -PI * 0.5]]:
		var d: Vector2 = side[0]
		var count := 0
		for i in 9:
			var t := (i + 0.5) / 9.0
			var edge := fp.get_center() + Vector2(d.x * fp.size.x, d.y * fp.size.y) * 0.5
			var along := Vector2(-d.y, d.x) * (t - 0.5) * (fp.size.y if d.x != 0.0 else fp.size.x)
			for reach in [40.0, 100.0, 170.0]:
				if map.is_roadlike(map.surface_at(edge + along + d * reach)):
					count += 1
					break
		if count > most:
			most = count
			best = side[1]
	return best


## A row of copies across the footprint at natural proportions (scaled to the depth, capped in
## height; towers may go tall).
func _place_row(key: String, size: Vector3, base: Transform3D, tall := false, real := false) -> void:
	var bb: AABB = _templates[key]["aabb"]
	if bb.size.x <= 0.0:
		return
	var k := minf(size.z / bb.size.z, (22.0 if tall else 10.0) / bb.size.y)
	if real:
		# Real-scale kit buildings: never enlarged, only shrunk to fit the plot's depth and width.
		k = minf(1.0, minf(size.z / bb.size.z, size.x / bb.size.x))
	var width := bb.size.x * k
	var n := maxi(1, int(floor(size.x / width)))
	var gap := (size.x - n * width) / n
	for i in n:
		var x := -size.x * 0.5 + (width + gap) * (i + 0.5)
		var off := Vector3(x - bb.get_center().x * k, -bb.position.y * k, -bb.get_center().z * k)
		_queue(key, base * Transform3D(Basis().scaled(Vector3.ONE * k), off), BUILDING_FAR, true)


## A model's parts (mesh + transform under its root) and bounds, read once from its GLB.
func _template(key: String) -> Variant:
	if _templates.has(key):
		return _templates[key]
	var m := models.make(key)
	if m == null:
		_templates[key] = null
		return null
	var parts := []
	for c in m.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var xf := mi.transform
		var p: Node = mi.get_parent()
		while p != m and p is Node3D:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var mesh: Mesh = mi.mesh
		if Models3D.CITYKIT.has(key):
			mesh = _kit_mesh(mesh)
		parts.append([mesh, xf])
	_templates[key] = { "parts": parts, "aabb": Models3D.aabb(m) }
	m.free()
	return _templates[key]


## The MegaKit stores a wear mask in its vertex colours for its own shader; Godot's importer would
## paint it on as colour (red bands along every wall). Render the asset as its author shows it:
## materials without vertex colour as albedo.
func _kit_mesh(mesh: Mesh) -> Mesh:
	var copy: Mesh = mesh.duplicate()
	for i in copy.get_surface_count():
		var mat := copy.surface_get_material(i)
		if mat is BaseMaterial3D and (mat as BaseMaterial3D).vertex_color_use_as_albedo:
			var d: BaseMaterial3D = mat.duplicate()
			d.vertex_color_use_as_albedo = false
			copy.surface_set_material(i, d)
	return copy


func _queue(key: String, xf: Transform3D, far: float, shadow: bool) -> void:
	if not _batch.has(key):
		_batch[key] = { "xforms": [], "far": far, "shadow": shadow }
	(_batch[key]["xforms"] as Array).append(xf)


## Queue a model scaled to a height, standing on the ground at `at` (centred).
func _queue_fit(key: String, height: float, at: Transform3D, far: float, shadow: bool) -> void:
	var t: Variant = _template(key)
	if t == null:
		return
	var bb: AABB = t["aabb"]
	if bb.size.y <= 0.0:
		return
	var k := height / bb.size.y
	_queue(key, at * Transform3D(Basis().scaled(Vector3.ONE * k), Vector3(-bb.get_center().x * k, -bb.position.y * k, -bb.get_center().z * k)), far, shadow)


func _build_batches() -> void:
	if "--look" in OS.get_cmdline_user_args():
		print("city batches: ", _batch.keys().map(func(k: String) -> String: return "%s=%d" % [k, (_batch[k]["xforms"] as Array).size()]))
		for k in ["city_large", "city_small"]:
			if _batch.has(k):
				debug_spots.append((_batch[k]["xforms"][0] as Transform3D).origin)
	for key: String in _batch:
		var t: Variant = _templates.get(key)
		if t == null:
			continue
		var b: Dictionary = _batch[key]
		var chunks := {}
		for xf: Transform3D in b["xforms"]:
			var c := Vector2i(int(floor(xf.origin.x / CHUNK)), int(floor(xf.origin.z / CHUNK)))
			if not chunks.has(c):
				chunks[c] = []
			chunks[c].append(xf)
		for c in chunks:
			var list: Array = chunks[c]
			for part: Array in t["parts"]:
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = part[0]
				mm.instance_count = list.size()
				for i in list.size():
					mm.set_instance_transform(i, (list[i] as Transform3D) * (part[1] as Transform3D))
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				mmi.visibility_range_end = float(b["far"]) * far_scale
				mmi.visibility_range_end_margin = float(b["far"]) * far_scale * 0.1
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if b["shadow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mmi)


func _box(parent: Node3D, size: Vector3, wall_col: Color, roof_mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position.y = size.y * 0.5
	var wall := StandardMaterial3D.new()
	wall.albedo_color = wall_col.darkened(0.12).lerp(Color("#c9b49a"), 0.35)
	wall.roughness = 0.85
	mi.material_override = wall
	parent.add_child(mi)
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(size.x + 0.6, 1.4, size.z + 0.6)
	roof.mesh = pm
	roof.position.y = size.y + 0.7
	roof.rotation_degrees.y = 90.0 if size.x < size.z else 0.0
	roof.material_override = roof_mat
	parent.add_child(roof)


## The shop's painted sign board over its front, like the 2D game's signs.
func _sign(parent: Node3D, text: String, size: Vector3) -> void:
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var bw := clampf(text.length() * 0.32, 2.4, size.x - 0.4)
	bm.size = Vector3(bw, 0.75, 0.08)
	board.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#f1e6c8")
	mat.roughness = 0.7
	board.material_override = mat
	board.position = Vector3(0, minf(size.y * 0.55, 3.2), size.z * 0.5 + 0.35)
	parent.add_child(board)
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 64
	lbl.pixel_size = 0.006
	lbl.outline_size = 0
	lbl.modulate = Color("#1d1611")
	lbl.width = bw / 0.006
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.position = Vector3(0, 0, 0.05)
	var fs := minf(64.0, bw / 0.006 / maxf(1.0, text.length() * 0.62))
	lbl.font_size = int(fs)
	board.add_child(lbl)


func _props() -> void:
	for p in map.props:
		var spec: Array = Models3D.PROPS.get(p.kind, [])
		if spec.is_empty() or _template(spec[0]) == null:
			continue
		var pos := Terrain3D.w(p.pos)
		var yaw := float(p.seed % 360) * 0.0174
		var count := 3 if p.kind == "palm-cluster" else 1
		var big: bool = float(spec[1]) > 3.0
		var far := PROP_FAR * (1.5 if big else 1.0)
		for i in count:
			var off := Vector3(cos(i * 2.1) * 1.6, 0, sin(i * 2.1) * 1.6) if i > 0 else Vector3.ZERO
			_queue_fit(spec[0], float(spec[1]) * (1.0 - 0.12 * i), Transform3D(Basis(Vector3.UP, yaw + i * 1.3), pos + off), far, big)
		if p.kind in MapData.SOLID_PROPS:
			var r: float = float(MapData.PROP_RADIUS.get(p.kind, 12.0)) * K
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = maxf(0.25, r)
			cyl.height = 3.0
			cs.shape = cyl
			cs.position.y = 1.5
			body.add_child(cs)
			body.position = pos
			add_child(body)
			obstacles.append(Vector3(pos.x, pos.z, maxf(0.25, r)))


## Manhole covers down the middle of each lane and zebra crossings across every road just before
## its junctions (Downtown City MegaKit, CC0).
func _street_furniture() -> void:
	var junctions := {}
	for id in map.road_graph:
		if (map.road_graph[id] as Array).size() >= 3:
			junctions[id] = (map.road_nodes[id] as Vector2) * K
	for r: Dictionary in map.roads:
		var pts: PackedVector2Array = r["points"]
		var half: float = float(r["width"]) * K * 0.5
		if pts.size() < 2:
			continue
		var run := 0.0
		for i in pts.size() - 1:
			var a := pts[i] * K
			var b := pts[i + 1] * K
			var seg := a.distance_to(b)
			var dir := (b - a) / maxf(seg, 0.001)
			var side := Vector2(-dir.y, dir.x)
			var t := fmod(40.0 - run, 40.0)
			while t < seg:
				var p := a + dir * t + side * (half * 0.45)
				_queue("manhole", Transform3D(Basis(Vector3.UP, -dir.angle()), Vector3(p.x, Terrain3D.ROAD_Y + 0.02, p.y)), PROP_FAR * 0.6, false)
				t += 40.0
			run += seg
		# Crossings 10 m out from each end that meets a junction, spanning the road.
		for end in [0, pts.size() - 1]:
			var j := pts[end] * K
			var near_junction := false
			for q: Vector2 in junctions.values():
				if q.distance_to(j) < 3.0:
					near_junction = true
			if not near_junction:
				continue
			var other := pts[1 if end == 0 else pts.size() - 2] * K
			var dir2 := (other - j).normalized()
			var c := j + dir2 * 10.0
			# The decal's stripes run along its X; turn it so they cross the road.
			var w := half * 2.0
			var tpl: Variant = _template("crosswalk")
			if tpl == null:
				continue
			var bb: AABB = tpl["aabb"]
			var sx := w / maxf(bb.size.z, 0.1)
			var xf := Transform3D(Basis(Vector3.UP, -dir2.angle()) * Basis.from_scale(Vector3(1.0, 1.0, sx)), Vector3(c.x, Terrain3D.ROAD_Y + 0.025, c.y))
			_queue("crosswalk", xf, PROP_FAR, false)
