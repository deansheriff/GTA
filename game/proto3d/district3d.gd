extends Node3D
## 3D prototype of one district (owner request 2026-10-17): Yaba, built from the same map data as
## the 2D game, to judge whether a 3D Naija Street Life looks and runs well on a phone.
##  - Ground per map cell: asphalt roads with lane lines, interlock pavements, grass and dirt yards.
##  - Buildings on their real footprints (boxes until Meshy models replace them: art3d/*.glb).
##  - A drivable vehicle (the Meshy danfo when present) with arcade handling and a chase camera.
##  - A few traffic cars along the real road graph, palms and poles, people standing about.
##  - Sun with soft shadows, sky, filmic tonemap, glow, and glossy car paint.
## Runs on the Compatibility renderer (the same as the game) so it shows what low-end phones get.
## Launch: Godot --path game -- --proto3d   (or the "3D prototype" button on the title screen).

const K := 0.0625 # metres per map pixel: a 64 px cell is 4 m
const CELL_M := 4.0
const REGION := Rect2i(84, 38, 42, 38) # map cells: Yaba and its edges
const ART := "res://art3d/"
## Meshy buildings face +Z (towards the viewer in Meshy); the map's fronts face south (+Z) too.
const MODEL_FRONT_YAW := 0.0

var map: MapData
var car: CharacterBody3D
var car_model: Node3D
var cam: Camera3D
var heading := 0.0
var speed := 0.0
var traffic: Array = [] # {node, a, b, t}
var hud: Label
var _joy: Control
var _fps_t := 0.0
var _frames := 0


func _ready() -> void:
	map = MapData.shared()
	_environment()
	_ground()
	_buildings()
	_props()
	_people()
	_spawn_car()
	_spawn_traffic()
	_hud()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots(a.trim_prefix("--shots="))


## QA: drive a little and take pictures, then quit.
func _shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(1.5).timeout
	_save(dir + "/3d-0-start.png")
	demo_drive = true
	await get_tree().create_timer(3.0).timeout
	_save(dir + "/3d-1-driving.png")
	demo_turn = 0.7 # swing right before the district's edge
	await get_tree().create_timer(1.8).timeout
	_save(dir + "/3d-2-driving.png")
	demo_drive = false
	print("proto3d: " + hud.text.replace(char(10), " | "))
	get_tree().quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


# ---------- world ----------

func _environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color("#4f8fd0")
	mat.sky_horizon_color = Color("#cfe2ea")
	mat.ground_horizon_color = Color("#c9b99a")
	mat.sun_angle_max = 20.0
	sky.sky_material = mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.04
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_color = Color("#fff1d8")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


## World position (metres) of a map pixel position.
func w(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x * K, y, p.y * K)


func _tex_mat(path: String, tint := Color.WHITE, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = Art.tex(path)
	m.albedo_color = tint
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.25, 0.25, 0.25) # one texture tile every 4 m
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## One quad per map cell, batched per surface type (MultiMesh).
func _ground() -> void:
	var kinds := {
		MapData.S.ROAD: _tex_mat("ground/asphalt.png", Color(0.85, 0.85, 0.85), 0.75),
		MapData.S.BRIDGE: _tex_mat("ground/asphalt.png", Color(0.9, 0.9, 0.9), 0.75),
		MapData.S.WALK: _tex_mat("ground/interlock.png"),
		MapData.S.GUTTER: _tex_mat("ground/interlock.png", Color(0.6, 0.6, 0.6)),
		MapData.S.GROUND: _tex_mat("ground/grass.png", Color(0.5, 0.56, 0.42)), # the painted grass is very bright in 3D light
		MapData.S.BEACH: _tex_mat("ground/sand.png"),
	}
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.13, 0.42, 0.5)
	water.roughness = 0.08
	water.metallic = 0.2
	kinds[MapData.S.SEA] = water
	kinds[MapData.S.LAGOON] = water
	var buckets := {}
	for y in range(REGION.position.y, REGION.end.y):
		for x in range(REGION.position.x, REGION.end.x):
			if not map.in_bounds(Vector2i(x, y)):
				continue
			var s := map.surface[y * map.cols + x]
			if not buckets.has(s):
				buckets[s] = []
			buckets[s].append(Vector2i(x, y))
	# Land around the district (so the horizon isn't empty), and walls at its edge.
	var origin := Vector3(REGION.position.x, 0, REGION.position.y) * CELL_M
	var span := Vector3(REGION.size.x, 0, REGION.size.y) * CELL_M
	var base := MeshInstance3D.new()
	var bp := PlaneMesh.new()
	bp.size = Vector2(span.x * 4.0, span.z * 4.0)
	base.mesh = bp
	base.position = origin + span * 0.5 + Vector3(0, -0.05, 0)
	base.material_override = kinds[MapData.S.GROUND]
	add_child(base)
	for side in 4:
		var wall := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		var horiz := side < 2
		bx.size = Vector3(span.x + 8.0, 6.0, 2.0) if horiz else Vector3(2.0, 6.0, span.z + 8.0)
		cs.shape = bx
		wall.add_child(cs)
		wall.position = origin + span * 0.5 + (Vector3(0, 3, (span.z * 0.5 + 1.0) * (1 if side == 0 else -1)) if horiz else Vector3((span.x * 0.5 + 1.0) * (1 if side == 2 else -1), 3, 0))
		add_child(wall)
	var quad := PlaneMesh.new()
	quad.size = Vector2(CELL_M, CELL_M)
	for s in buckets:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = quad
		var cells: Array = buckets[s]
		mm.instance_count = cells.size()
		var lift := 0.02 if s == MapData.S.WALK else (-0.25 if map.is_water(s) else 0.0)
		for i in cells.size():
			var c: Vector2i = cells[i]
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3((c.x + 0.5) * CELL_M, lift, (c.y + 0.5) * CELL_M)))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = kinds.get(s, kinds[MapData.S.GROUND])
		add_child(mi)
	# Dashed lane lines down the middle of every road inside the region.
	var dash := BoxMesh.new()
	dash.size = Vector3(1.6, 0.02, 0.18)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.95, 0.9, 0.7)
	dmat.roughness = 0.6
	var xf := []
	var area := Rect2(Vector2(REGION.position) * 64.0, Vector2(REGION.size) * 64.0)
	var seen := {}
	for a in map.road_graph:
		for b: String in map.road_graph[a]:
			var key: String = (a + b) if a < b else (b + a)
			if seen.has(key):
				continue
			seen[key] = true
			var pa: Vector2 = map.road_nodes[a]
			var pb: Vector2 = map.road_nodes[b]
			var n := int(pa.distance_to(pb) / 64.0)
			for i in n:
				var p := pa.lerp(pb, (i + 0.5) / n)
				if area.has_point(p):
					xf.append(Transform3D(Basis(Vector3.UP, -(pb - pa).angle()), w(p, 0.03)))
	if not xf.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = dash
		mm.instance_count = xf.size()
		for i in xf.size():
			mm.set_instance_transform(i, xf[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = dmat
		add_child(mi)


func _in_region(fp: Rect2) -> bool:
	return Rect2(Vector2(REGION.position) * 64.0, Vector2(REGION.size) * 64.0).encloses(fp)


## Buildings on their footprints: a Meshy model if one matches, otherwise a box with a zinc roof.
func _buildings() -> void:
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color("#8a5a3c")
	roof_mat.roughness = 0.55
	roof_mat.metallic = 0.35
	for b in map.buildings:
		var fp: Rect2 = b.footprint()
		if not _in_region(fp):
			continue
		var size := Vector3(fp.size.x * K - 0.6, clampf(b.height * K * 1.25, 3.2, 7.5), fp.size.y * K - 0.6)
		var center := w(fp.get_center(), 0.0)
		var model := _model_for(b)
		var body := StaticBody3D.new()
		body.position = center
		add_child(body)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position.y = size.y * 0.5
		body.add_child(shape)
		if model:
			# Turn the row so the fronts face the nearest road (a quarter turn swaps width and depth).
			var face := _road_side(fp)
			var holder := Node3D.new()
			holder.rotation.y = face + MODEL_FRONT_YAW
			body.add_child(holder)
			var quarter := absf(sin(face)) > 0.5
			_place_row(model, Vector3(size.z, size.y, size.x) if quarter else size, holder)
			continue
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.position.y = size.y * 0.5
		var wall := StandardMaterial3D.new()
		wall.albedo_color = b.wall.darkened(0.12).lerp(Color("#c9b49a"), 0.35) # weathered plaster, not candy
		wall.roughness = 0.85
		mi.material_override = wall
		body.add_child(mi)
		var roof := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(size.x + 0.6, 1.4, size.z + 0.6)
		roof.mesh = pm
		roof.position.y = size.y + 0.7
		roof.rotation_degrees.y = 90.0 if size.x < size.z else 0.0
		roof.material_override = roof_mat
		body.add_child(roof)


## The yaw that turns a model's front (+Z) towards the side of the footprint with the most road
## alongside it: 0 = south (+Z), PI = north, PI/2 = east (+X), -PI/2 = west.
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


## A Meshy building model for this footprint, if one has been downloaded.
func _model_for(b: Layout.BuildingSpec) -> Node3D:
	var key := "bungalow" if b.art in ["bungalow", "island-cottage"] else "shop"
	var m := _load_model(key)
	if m == null and key == "bungalow":
		m = _load_model("shop") # one painted building is better than boxes
	return m


func _load_model(key: String) -> Node3D:
	var path := ART + key + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var ps: PackedScene = load(path)
	return ps.instantiate() if ps else null


## Scale a model so its bounding box fills `size` (keeping proportions), standing on the ground.
## A row of buildings across a footprint: each copy at its natural proportions (scaled to the
## footprint's depth, no taller than ~10 m), as many as fit side by side.
func _place_row(model: Node3D, size: Vector3, parent: Node3D) -> void:
	var aabb := _aabb(model)
	if aabb.size.x <= 0.0:
		model.queue_free()
		return
	var k := minf(size.z / aabb.size.z, 10.0 / aabb.size.y)
	var w := aabb.size.x * k
	var n := maxi(1, int(floor(size.x / w)))
	var gap := (size.x - n * w) / n
	for i in n:
		var m: Node3D = model if i == 0 else model.duplicate()
		m.scale = Vector3.ONE * k
		var x := -size.x * 0.5 + (w + gap) * (i + 0.5)
		m.position = Vector3(x - aabb.get_center().x * k, -aabb.position.y * k, -aabb.get_center().z * k)
		parent.add_child(m)


func _fit_model(model: Node3D, size: Vector3, stretch := false) -> void:
	var aabb := _aabb(model)
	if aabb.size.x <= 0.0:
		return
	var k := minf(size.x / aabb.size.x, size.z / aabb.size.z)
	var sc := Vector3.ONE * k
	if stretch:
		# Buildings fill their footprint; height follows, capped near the planned height.
		var kx := size.x / aabb.size.x
		var kz := size.z / aabb.size.z
		var ky := minf((kx + kz) * 0.5, size.y * 1.4 / aabb.size.y)
		sc = Vector3(kx, ky, kz)
	model.scale = sc
	model.position = Vector3(-aabb.get_center().x * sc.x, -aabb.position.y * sc.y, -aabb.get_center().z * sc.z)


func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var bb := mi.get_aabb()
		var xf := mi.transform
		var p: Node = mi.get_parent()
		while p != n and p is Node3D:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		bb = xf * bb
		out = bb if first else out.merge(bb)
		first = false
	return out


func _props() -> void:
	var palm := _load_model("palm")
	var pole := _load_model("pole")
	for p in map.props:
		if not _in_region(Rect2(p.pos, Vector2.ONE)):
			continue
		var n: Node3D = null
		if p.kind in ["palm", "palm-cluster", "mango"]:
			n = palm.duplicate() if palm else _simple_tree()
			if palm:
				_fit_height(n, 7.0)
		elif p.kind == "pole":
			n = pole.duplicate() if pole else _simple_pole()
			if pole:
				_fit_height(n, 8.0)
		elif p.kind == "umbrella":
			n = _umbrella()
		if n:
			n.position = w(p.pos)
			n.rotation.y = float(p.seed % 360) * 0.0174
			add_child(n)
	for t in [palm, pole]:
		if t:
			t.free()


func _fit_height(model: Node3D, h: float) -> void:
	var aabb := _aabb(model)
	if aabb.size.y > 0.0:
		var k := h / aabb.size.y
		model.scale = Vector3.ONE * k
		model.position.y = -aabb.position.y * k


func _simple_tree() -> Node3D:
	var root := Node3D.new()
	var trunk := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18
	cm.bottom_radius = 0.28
	cm.height = 5.0
	trunk.mesh = cm
	trunk.position.y = 2.5
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color("#6b4a2e")
	trunk.material_override = tm
	root.add_child(trunk)
	var crown := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.0
	sm.height = 2.4
	crown.mesh = sm
	crown.position.y = 5.4
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color("#3f7a2e")
	crown.material_override = lm
	root.add_child(crown)
	return root


func _simple_pole() -> Node3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.1
	cm.bottom_radius = 0.14
	cm.height = 8.0
	mi.mesh = cm
	mi.position.y = 4.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#5a4632")
	mi.material_override = m
	var root := Node3D.new()
	root.add_child(mi)
	return root


func _umbrella() -> Node3D:
	var root := Node3D.new()
	var canopy := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 1.4
	cm.height = 0.5
	canopy.mesh = cm
	canopy.position.y = 2.2
	var m := StandardMaterial3D.new()
	m.albedo_color = [Color("#c8432f"), Color("#e0a91c"), Color("#2f6f99")][randi() % 3]
	canopy.material_override = m
	root.add_child(canopy)
	var stick := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.03
	sm.bottom_radius = 0.03
	sm.height = 2.2
	stick.mesh = sm
	stick.position.y = 1.1
	root.add_child(stick)
	return root


## Townspeople: the Meshy Tunde model stands in for now (or simple figures).
func _people() -> void:
	var tunde := _load_model("tunde")
	var r := RandomNumberGenerator.new()
	r.seed = 9
	var n := 0
	for i in 200:
		if n >= 14:
			break
		var c := Vector2i(r.randi_range(REGION.position.x, REGION.end.x - 1), r.randi_range(REGION.position.y, REGION.end.y - 1))
		if map.surface[c.y * map.cols + c.x] != MapData.S.WALK:
			continue
		var p: Node3D = tunde.duplicate() if tunde else _figure(r)
		if tunde:
			_fit_height(p, 1.75)
		p.position += Vector3((c.x + 0.5) * CELL_M, 0, (c.y + 0.5) * CELL_M)
		p.rotation.y = r.randf() * TAU
		add_child(p)
		n += 1
	if tunde:
		tunde.free() # the template itself never joins the scene


func _figure(r: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.28
	cm.height = 1.7
	body.mesh = cm
	body.position.y = 0.85
	var m := StandardMaterial3D.new()
	m.albedo_color = [Color("#a8382c"), Color("#2f6f99"), Color("#c96f24"), Color("#2f8a52")][r.randi() % 4]
	body.material_override = m
	root.add_child(body)
	return root


# ---------- the car ----------

func _spawn_car() -> void:
	car = CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.6, 2.0, 2.0)
	shape.shape = box
	shape.position.y = 1.0
	car.add_child(shape)
	car_model = _load_model("danfo")
	if car_model:
		_fit_model(car_model, Vector3(4.8, 0, 2.2))
		var holder := Node3D.new()
		holder.add_child(car_model)
		holder.rotation.y = PI # Meshy's van faces -X; our forward is +X
		car_model = holder
	else:
		car_model = _box_car(Color("#e0a91c"), Vector3(4.6, 1.9, 2.0))
	car.add_child(car_model)
	_glossy(car_model)
	add_child(car)
	# Start on Yaba's main junction, pointing down a road.
	var start: Vector2 = map.road_nodes.get("yaba_c", Vector2(REGION.get_center()) * 64.0)
	var nb: Array = map.road_graph.get("yaba_c", [])
	if not nb.is_empty():
		# The neighbour furthest away inside the district: the longest road to drive down.
		var area := Rect2(Vector2(REGION.position) * 64.0, Vector2(REGION.size) * 64.0)
		var best: Vector2 = map.road_nodes[nb[0]]
		for id in nb:
			var p: Vector2 = map.road_nodes[id]
			if area.has_point(p) and (not area.has_point(best) or p.distance_to(start) > best.distance_to(start)):
				best = p
		var dir := (best - start).normalized()
		heading = -dir.angle()
		start += Vector2(-dir.y, dir.x) * 30.0 # in the lane
	car.position = w(start)
	car.rotation.y = heading
	cam = Camera3D.new()
	cam.fov = 62.0
	add_child(cam)
	cam.make_current()


## Car paint shines: lower roughness and a touch of metal on every surface of the model.
func _glossy(n: Node) -> void:
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		for s in mi.get_surface_override_material_count():
			var m: Material = mi.get_active_material(s)
			if m is StandardMaterial3D:
				var g: StandardMaterial3D = (m as StandardMaterial3D).duplicate()
				g.roughness = minf(g.roughness, 0.35)
				g.metallic = maxf(g.metallic, 0.25)
				g.metallic_specular = 0.7
				mi.set_surface_override_material(s, g)


func _box_car(col: Color, size: Vector3) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position.y = size.y * 0.5 + 0.3
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.25
	m.metallic = 0.3
	mi.material_override = m
	root.add_child(mi)
	return root


func _input_vec() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): v.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): v.y += 1
	if _joy:
		v += _joy.value
	return v.limit_length(1.0)


func _physics_process(delta: float) -> void:
	var inp := _input_vec()
	if demo_drive:
		inp = Vector2(demo_turn, -1.0)
	# Arcade handling: up/down = gas/brake, left/right = steer (screen-relative to the car).
	var gas := -inp.y
	var top := 16.0 # m/s, about 58 km/h
	speed = move_toward(speed, top * gas, (9.0 if gas * speed >= 0.0 else 16.0) * delta)
	if absf(gas) < 0.05:
		speed = move_toward(speed, 0.0, 5.0 * delta)
	heading -= inp.x * 1.9 * delta * clampf(absf(speed) / 6.0, 0.0, 1.0) * signf(speed if speed != 0.0 else 1.0)
	car.rotation.y = heading
	car.velocity = Vector3(cos(heading), 0, -sin(heading)) * speed
	car.move_and_slide()
	if car.get_slide_collision_count() > 0:
		speed *= 0.4
	# Chase camera: behind and above, easing in.
	var back := Vector3(-cos(heading), 0, sin(heading))
	var want := car.position + back * 9.0 + Vector3(0, 5.5, 0)
	cam.position = cam.position.lerp(want, minf(1.0, delta * 4.0))
	cam.look_at(car.position + Vector3(0, 1.2, 0))
	_drive_traffic(delta)
	_frames += 1
	_fps_t += delta
	if _fps_t >= 0.5:
		hud.text = "3D prototype · Yaba · %d km/h · %d fps\nWASD / stick to drive · Esc to go back" % [int(absf(speed) * 3.6), int(round(_frames / _fps_t))]
		_frames = 0
		_fps_t = 0.0


var demo_drive := false
var demo_turn := 0.0


# ---------- traffic ----------

func _spawn_traffic() -> void:
	var cols := [Color("#2f6f99"), Color("#c8432f"), Color("#ece4d2"), Color("#1d1d1d"), Color("#e0a91c")]
	var area := Rect2(Vector2(REGION.position) * 64.0, Vector2(REGION.size) * 64.0)
	# Traffic uses the Meshy danfo and keke (alternating) when they're present.
	var kinds := [["danfo", Vector3(4.8, 0, 2.2)], ["keke", Vector3(2.6, 0, 1.4)]]
	var i := 0
	for a in map.road_graph:
		if i >= 8:
			break
		if not area.has_point(map.road_nodes[a]):
			continue
		var nbs: Array = map.road_graph[a]
		if nbs.is_empty():
			continue
		var n: Node3D
		var spec: Array = kinds[i % kinds.size()]
		var m := _load_model(spec[0])
		if m:
			n = Node3D.new()
			_fit_model(m, spec[1])
			var turn := Node3D.new()
			turn.rotation.y = PI # Meshy vehicles face -X
			turn.add_child(m)
			n.add_child(turn)
			_glossy(n)
		else:
			n = _box_car(cols[i % cols.size()], Vector3(4.0, 1.4, 1.8))
		add_child(n)
		traffic.append({ "node": n, "a": a, "b": nbs[i % nbs.size()], "t": 0.2 })
		i += 1


func _drive_traffic(delta: float) -> void:
	for v: Dictionary in traffic:
		var pa: Vector2 = map.road_nodes[v["a"]]
		var pb: Vector2 = map.road_nodes[v["b"]]
		var len := maxf(1.0, pa.distance_to(pb) * K)
		v["t"] = float(v["t"]) + 9.0 * delta / len
		if float(v["t"]) >= 1.0:
			var nbs: Array = (map.road_graph.get(v["b"], []) as Array).filter(func(x: String) -> bool: return x != v["a"])
			if nbs.is_empty():
				nbs = [v["a"]]
			v["a"] = v["b"]
			v["b"] = nbs[randi() % nbs.size()]
			v["t"] = 0.0
			continue
		var dir := (pb - pa).normalized()
		var p := pa.lerp(pb, float(v["t"])) + Vector2(-dir.y, dir.x) * 30.0
		var n: Node3D = v["node"]
		n.position = w(p)
		n.rotation.y = -dir.angle()


# ---------- HUD ----------

func _hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 20)
	hud.add_theme_color_override("font_color", Color("#f1e6c8"))
	hud.add_theme_color_override("font_outline_color", Color("#1d1611"))
	hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(hud)
	if DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"):
		_joy = preload("res://ui/joystick.gd").new()
		_joy.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_joy.position = Vector2(20, -180)
		layer.add_child(_joy)
	var back := Button.new()
	back.text = "Back to the 2D game"
	back.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	back.position = Vector2(-240, 12)
	back.custom_minimum_size = Vector2(220, 52)
	back.pressed.connect(_back)
	layer.add_child(back)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE:
		_back()


func _back() -> void:
	get_tree().change_scene_to_file("res://main.tscn")
