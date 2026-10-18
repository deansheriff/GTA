class_name City3D
extends Node3D
## Buildings and street props for the whole island (D-020), from the 2D map's building and prop
## lists. Each building gets a Meshy model chosen by its type, district and landmark, turned to face
## its road, with a solid collision box, its painted shop sign and its generator. Far things are
## hidden by distance so the whole city can stay built.

const K := Terrain3D.K
const BUILDING_FAR := 170.0
const PROP_FAR := 95.0

var map: MapData
var models: Models3D
var obstacles: Array[Vector3] = [] # solid props as (x, z, radius) for people to walk round


func build(m: MapData, lib: Models3D) -> void:
	map = m
	models = lib
	_buildings()
	_props()


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
		var m := models.make(key) if key != "" else null
		if m:
			_place_row(m, local, holder, key in ["office_tower", "apartment"])
		else:
			_box(holder, local, b.wall, roof_mat)
		if b.sign_text != "":
			_sign(holder, b.sign_text, local)
		if b.generator and models.has("generator"):
			var g := models.make("generator")
			Models3D.fit_height(g, 0.9)
			var gh := Node3D.new()
			gh.add_child(g)
			gh.position = Vector3(local.x * 0.5 + 0.6, 0, local.z * 0.5 - 0.8)
			holder.add_child(gh)
		Models3D.far_cull(body, BUILDING_FAR)


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
func _place_row(model: Node3D, size: Vector3, parent: Node3D, tall := false) -> void:
	var bb := Models3D.aabb(model)
	if bb.size.x <= 0.0:
		model.free()
		return
	var k := minf(size.z / bb.size.z, (22.0 if tall else 10.0) / bb.size.y)
	var width := bb.size.x * k
	var n := maxi(1, int(floor(size.x / width)))
	var gap := (size.x - n * width) / n
	for i in n:
		var m: Node3D = model if i == 0 else model.duplicate()
		m.scale = Vector3.ONE * k
		var x := -size.x * 0.5 + (width + gap) * (i + 0.5)
		m.position = Vector3(x - bb.get_center().x * k, -bb.position.y * k, -bb.get_center().z * k)
		parent.add_child(m)


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
		if spec.is_empty():
			continue
		var holder := Node3D.new()
		holder.position = Terrain3D.w(p.pos)
		holder.rotation.y = float(p.seed % 360) * 0.0174
		var count := 3 if p.kind == "palm-cluster" else 1
		var made := false
		for i in count:
			var m := models.make(spec[0])
			if m == null:
				break
			Models3D.fit_height(m, float(spec[1]) * (1.0 - 0.12 * i))
			var h := Node3D.new()
			h.add_child(m)
			if count > 1:
				h.position = Vector3(cos(i * 2.1) * 1.6, 0, sin(i * 2.1) * 1.6) * (1 if i > 0 else 0)
				h.rotation.y = i * 1.3
			holder.add_child(h)
			made = true
		if not made:
			holder.free()
			continue
		add_child(holder)
		var big: bool = float(spec[1]) > 3.0
		Models3D.far_cull(holder, PROP_FAR * (1.5 if big else 1.0))
		if not big:
			Models3D.no_shadow(holder)
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
			body.position = holder.position
			add_child(body)
			obstacles.append(Vector3(holder.position.x, holder.position.z, maxf(0.25, r)))
